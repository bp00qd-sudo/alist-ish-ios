package iosbridge

import (
	"strings"
	"testing"
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
