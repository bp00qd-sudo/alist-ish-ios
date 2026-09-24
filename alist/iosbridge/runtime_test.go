package iosbridge

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/alist-org/alist/v3/internal/op"
)

func TestOptionsDefaults(t *testing.T) {
	o := Options{DataDir: "/tmp/alist"}
	o.withDefaults()
	if o.BindAddress != "127.0.0.1" {
		t.Fatalf("expected loopback default, got %q", o.BindAddress)
	}
	if o.Port != 5244 {
		t.Fatalf("expected port 5244, got %d", o.Port)
	}
	if o.MemoryLimit != 96*1024*1024 {
		t.Fatalf("unexpected memory limit: %d", o.MemoryLimit)
	}

	o = Options{DataDir: "/tmp/alist", LANEnabled: true}
	o.withDefaults()
	if o.BindAddress != "0.0.0.0" {
		t.Fatalf("expected LAN bind address, got %q", o.BindAddress)
	}
}

func TestStartValidation(t *testing.T) {
	if _, err := Start(`{"port":5244}`); err == nil || !strings.Contains(err.Error(), "dataDir") {
		t.Fatalf("expected dataDir validation error, got %v", err)
	}
	if _, err := Start(`{"dataDir":"/tmp/alist","port":70000}`); err == nil || !strings.Contains(err.Error(), "invalid port") {
		t.Fatalf("expected port validation error, got %v", err)
	}
	if _, err := Start(`{"dataDir":"/tmp/alist","port":"5244"}`); err == nil || !strings.Contains(err.Error(), "invalid runtime options") {
		t.Fatalf("expected JSON type validation error, got %v", err)
	}
}

func TestNilRuntimeMethods(t *testing.T) {
	var r *Runtime
	if got := r.Status(); got != `{"state":"stopped"}` {
		t.Fatalf("unexpected nil status: %s", got)
	}
	if got := r.LocalURL(); got != "" {
		t.Fatalf("unexpected nil URL: %q", got)
	}
	if err := r.Stop(); err != nil {
		t.Fatalf("nil Stop should be harmless: %v", err)
	}
}

func TestStartServesWebAndFixedAdmin(t *testing.T) {
	probe, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := probe.Addr().(*net.TCPAddr).Port
	_ = probe.Close()

	dataDir := t.TempDir()
	options, err := json.Marshal(Options{
		DataDir: dataDir,
		TempDir: filepath.Join(dataDir, "cache"),
		Port: port,
	})
	if err != nil {
		t.Fatal(err)
	}
	r, err := Start(string(options))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = r.Stop() }()

	client := &http.Client{Timeout: 3 * time.Second}
	response, err := client.Get(r.LocalURL() + "/ping")
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(response.Body)
	_ = response.Body.Close()
	if err != nil || response.StatusCode != http.StatusOK || string(body) != "pong" {
		t.Fatalf("AList ping failed: status=%d body=%q error=%v", response.StatusCode, body, err)
	}

	admin, err := op.GetAdmin()
	if err != nil {
		t.Fatal(err)
	}
	if admin.Username != "admin" || admin.ValidateRawPassword("admin") != nil {
		t.Fatal("built-in administrator must be admin/admin")
	}
	if !strings.Contains(r.Status(), `"lan":false`) {
		t.Fatal("LAN access must be disabled by default")
	}
	if err := r.Stop(); err != nil {
		t.Fatal(err)
	}
}
