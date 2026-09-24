// Package iosbridge exposes the Alist runtime to the native iOS host.
//
// The package deliberately keeps the public surface small and gobind-friendly:
// Swift passes a JSON options object and receives JSON status/statistics.  The
// web UI and the regular Alist HTTP API remain unchanged.
package iosbridge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"runtime"
	"runtime/debug"
	"sync"
	"time"

	ftpserver "github.com/KirCute/ftpserverlib-pasvportmap"
	"github.com/KirCute/sftpd-alist"
	"github.com/alist-org/alist/v3/cmd"
	"github.com/alist-org/alist/v3/cmd/flags"
	"github.com/alist-org/alist/v3/internal/bootstrap"
	"github.com/alist-org/alist/v3/internal/conf"
	alistnet "github.com/alist-org/alist/v3/internal/net"
	"github.com/alist-org/alist/v3/server"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

// Options is intentionally composed only of primitive fields so gomobile can
// expose it to Swift.  JSON is used at the boundary to remain compatible with
// future fields without breaking the generated Swift framework.
type Options struct {
	DataDir     string `json:"dataDir"`
	TempDir     string `json:"tempDir"`
	BindAddress string `json:"bindAddress"`
	Port        int    `json:"port"`
	LANEnabled  bool   `json:"lanEnabled"`
	WebDAV      bool   `json:"webdav"`
	S3          bool   `json:"s3"`
	FTP         bool   `json:"ftp"`
	SFTP        bool   `json:"sftp"`
	MemoryLimit int64  `json:"memoryLimitBytes"`
}

func (o *Options) withDefaults() {
	if o.BindAddress == "" {
		if o.LANEnabled {
			o.BindAddress = "0.0.0.0"
		} else {
			o.BindAddress = "127.0.0.1"
		}
	}
	if o.Port == 0 {
		o.Port = 5244
	}
	if o.MemoryLimit == 0 {
		o.MemoryLimit = 96 * 1024 * 1024
	}
}

// Runtime owns every listener started by the embedded server.  It is safe to
// stop a runtime more than once.
type Runtime struct {
	mu       sync.RWMutex
	options  Options
	server   *http.Server
	listener net.Listener
	ftp      *ftpserver.FtpServer
	ftpDrv   *server.FtpMainDriver
	sftp     *sftpd.SftpServer
	sftpDrv  *server.SftpDriver
	started  time.Time
	stopped  bool
}

var active struct {
	sync.Mutex
	r *Runtime
}

// Start initializes Alist and starts the embedded HTTP server.  It returns an
// error instead of terminating the process, which is essential on iOS.
func Start(optionsJSON string) (*Runtime, error) {
	var options Options
	if optionsJSON != "" {
		if err := json.Unmarshal([]byte(optionsJSON), &options); err != nil {
			return nil, fmt.Errorf("invalid runtime options: %w", err)
		}
	}
	options.withDefaults()
	if options.DataDir == "" {
		return nil, errors.New("dataDir is required")
	}
	if options.Port < 1 || options.Port > 65535 {
		return nil, fmt.Errorf("invalid port %d", options.Port)
	}

	active.Lock()
	defer active.Unlock()
	if active.r != nil {
		return nil, errors.New("alist runtime is already running")
	}

	// Configure the process-global Alist flags before Init reads config.json.
	flags.DataDir = options.DataDir
	flags.ForceBinDir = false
	flags.Debug = false
	flags.Dev = false
	flags.LogStd = false
	flags.FixedAdmin = true
	if err := initAlist(); err != nil {
		return nil, err
	}
	conf.Conf.Scheme.Address = options.BindAddress
	conf.Conf.Scheme.HttpPort = options.Port
	conf.Conf.Scheme.HttpsPort = -1
	conf.Conf.Scheme.UnixFile = ""
	conf.Conf.WebDAV.Enable = options.WebDAV
	conf.Conf.S3.Enable = options.S3
	// Route S3 through the single HTTP listener to avoid another listener and
	// another TLS stack in the iOS process.
	conf.Conf.S3.Port = -1
	conf.Conf.FTP.Enable = options.FTP
	conf.Conf.SFTP.Enable = options.SFTP
	if options.TempDir != "" {
		conf.Conf.TempDir = options.TempDir
		if err := os.MkdirAll(conf.Conf.TempDir, 0o700); err != nil {
			cmd.Release()
			return nil, fmt.Errorf("create temp directory: %w", err)
		}
	}
	applyMemoryPolicy(options.MemoryLimit)
	// Delay storage/task initialization until the iOS memory policy is active.
	bootstrap.InitOfflineDownloadTools()
	bootstrap.LoadStorages()
	bootstrap.InitTaskManager()

	gin.SetMode(gin.ReleaseMode)
	engine := gin.New()
	engine.Use(gin.Recovery())
	server.Init(engine)
	listener, err := net.Listen("tcp", fmt.Sprintf("%s:%d", options.BindAddress, options.Port))
	if err != nil {
		cmd.Release()
		return nil, fmt.Errorf("listen %s:%d: %w", options.BindAddress, options.Port, err)
	}

	r := &Runtime{
		options:  options,
		server:   &http.Server{Handler: engine},
		listener: listener,
		started:  time.Now(),
	}
	go func() {
		if serveErr := r.server.Serve(listener); serveErr != nil && !errors.Is(serveErr, http.ErrServerClosed) {
			log.Errorf("embedded HTTP server stopped: %v", serveErr)
		}
	}()

	// FTP/SFTP are optional and started only when explicitly requested.  They
	// are intentionally not part of the default memory footprint.
	if options.FTP {
		if err := r.startFTP(); err != nil {
			_ = r.cleanupStartFailure()
			return nil, err
		}
	}
	if options.SFTP {
		if err := r.startSFTP(); err != nil {
			_ = r.cleanupStartFailure()
			return nil, err
		}
	}

	active.r = r
	return r, nil
}

func (r *Runtime) cleanupStartFailure() error {
	if r == nil {
		return nil
	}
	r.mu.Lock()
	r.stopped = true
	listener := r.listener
	serverRef := r.server
	ftpRef := r.ftp
	ftpDrv := r.ftpDrv
	sftpRef := r.sftp
	r.mu.Unlock()
	if listener != nil {
		_ = listener.Close()
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	var err error
	if serverRef != nil {
		err = serverRef.Shutdown(ctx)
	}
	if ftpDrv != nil {
		ftpDrv.Stop()
	}
	if ftpRef != nil {
		_ = ftpRef.Stop()
	}
	if sftpRef != nil {
		_ = sftpRef.Close()
	}
	cmd.Release()
	return err
}

func initAlist() (err error) {
	defer func() {
		if recovered := recover(); recovered != nil {
			err = fmt.Errorf("alist initialization panic: %v", recovered)
		}
	}()
	cmd.Init()
	return nil
}

func applyMemoryPolicy(limit int64) {
	if limit < 16*1024*1024 {
		limit = 16 * 1024 * 1024
	}
	debug.SetMemoryLimit(limit)
	debug.SetGCPercent(75)
	runtime.GOMAXPROCS(2)
	// These settings are read by Alist's task managers when they are created.
	if conf.Conf != nil {
		conf.Conf.MaxConcurrency = 4
		conf.Conf.Tasks.Download.Workers = 1
		conf.Conf.Tasks.Transfer.Workers = 1
		conf.Conf.Tasks.Upload.Workers = 1
		conf.Conf.Tasks.Copy.Workers = 1
		conf.Conf.Tasks.Decompress.Workers = 1
		conf.Conf.Tasks.DecompressUpload.Workers = 1
		conf.Conf.Tasks.S3Transition.Workers = 1
		alistnet.DefaultConcurrencyLimit = &alistnet.ConcurrencyLimit{Limit: conf.Conf.MaxConcurrency}
	}
}

func (r *Runtime) startFTP() error {
	driver, err := server.NewMainDriver()
	if err != nil {
		return fmt.Errorf("create FTP server: %w", err)
	}
	r.ftpDrv = driver
	r.ftp = ftpserver.NewFtpServer(driver)
	go func() {
		if err := r.ftp.ListenAndServe(); err != nil {
			log.Errorf("FTP server stopped: %v", err)
		}
	}()
	return nil
}

func (r *Runtime) startSFTP() error {
	driver, err := server.NewSftpDriver()
	if err != nil {
		return fmt.Errorf("create SFTP server: %w", err)
	}
	r.sftpDrv = driver
	r.sftp = sftpd.NewSftpServer(driver)
	go func() {
		if err := r.sftp.RunServer(); err != nil {
			log.Errorf("SFTP server stopped: %v", err)
		}
	}()
	return nil
}

// Stop gracefully closes all listeners and the Alist database.
func (r *Runtime) Stop() error {
	if r == nil {
		return nil
	}
	r.mu.Lock()
	if r.stopped {
		r.mu.Unlock()
		return nil
	}
	r.stopped = true
	serverRef := r.server
	listener := r.listener
	ftpRef := r.ftp
	ftpDrv := r.ftpDrv
	sftpRef := r.sftp
	r.mu.Unlock()

	if listener != nil {
		_ = listener.Close()
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	var err error
	if serverRef != nil {
		err = serverRef.Shutdown(ctx)
	}
	if ftpDrv != nil {
		ftpDrv.Stop()
	}
	if ftpRef != nil {
		_ = ftpRef.Stop()
	}
	if sftpRef != nil {
		_ = sftpRef.Close()
	}
	cmd.Release()
	active.Lock()
	if active.r == r {
		active.r = nil
	}
	active.Unlock()
	return err
}

// Status returns a compact JSON status suitable for Swift and diagnostics.
func (r *Runtime) Status() string {
	if r == nil {
		return `{"state":"stopped"}`
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	state := "running"
	if r.stopped {
		state = "stopped"
	}
	return marshalStatus(map[string]interface{}{
		"state":     state,
		"bind":      r.options.BindAddress,
		"port":      r.options.Port,
		"lan":       r.options.LANEnabled,
		"startedAt": r.started.UTC().Format(time.RFC3339),
	})
}

func (r *Runtime) LocalURL() string {
	if r == nil {
		return ""
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	return fmt.Sprintf("http://127.0.0.1:%d", r.options.Port)
}

// SetLANEnabled switches the listener between loopback and all interfaces.
// The port remains fixed so the WKWebView URL and external clients stay stable.
func (r *Runtime) SetLANEnabled(enabled bool) error {
	if r == nil {
		return errors.New("runtime is nil")
	}
	r.mu.Lock()
	if r.stopped {
		r.mu.Unlock()
		return errors.New("runtime is stopped")
	}
	address := "127.0.0.1"
	if enabled {
		address = "0.0.0.0"
	}
	old := r.listener
	oldAddress := r.options.BindAddress
	if old != nil {
		_ = old.Close()
	}
	listener, err := net.Listen("tcp", fmt.Sprintf("%s:%d", address, r.options.Port))
	if err != nil {
		// Try to restore the previous listener so a transient interface failure
		// does not leave the embedded web UI unavailable.
		if old != nil {
			if restored, restoreErr := net.Listen("tcp", fmt.Sprintf("%s:%d", oldAddress, r.options.Port)); restoreErr == nil {
				r.listener = restored
				serverRef := r.server
				go func() {
					if serveErr := serverRef.Serve(restored); serveErr != nil && !errors.Is(serveErr, http.ErrServerClosed) {
						log.Errorf("restored HTTP server stopped: %v", serveErr)
					}
				}()
			}
		}
		r.mu.Unlock()
		return fmt.Errorf("listen %s:%d: %w", address, r.options.Port, err)
	}
	r.listener = listener
	r.options.BindAddress = address
	r.options.LANEnabled = enabled
	serverRef := r.server
	r.mu.Unlock()
	if old != nil {
		_ = old.Close()
	}
	go func() {
		if err := serverRef.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Errorf("rebound HTTP server stopped: %v", err)
		}
	}()
	return nil
}

// MemoryStats returns runtime memory counters without retaining a profile in
// memory.  Swift can display it or send it to a local diagnostic log.
func (r *Runtime) MemoryStats() string {
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	return marshalStatus(map[string]interface{}{
		"alloc":       stats.Alloc,
		"heapInUse":   stats.HeapInuse,
		"heapObjects": stats.HeapObjects,
		"sys":         stats.Sys,
		"nextGC":      stats.NextGC,
	})
}

func marshalStatus(value interface{}) string {
	data, err := json.Marshal(value)
	if err != nil {
		return `{"error":"failed to marshal status"}`
	}
	return string(data)
}
