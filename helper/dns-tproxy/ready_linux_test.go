package main

import (
	"context"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// Run the real CLI signal handler in a child, not in the test runner.
func TestCLIProcess(t *testing.T) {
	if os.Getenv("DNS_TPROXY_TEST_CHILD") != "1" {
		return
	}
	err := run([]string{"--non-transparent", "--listen-port", os.Getenv("DNS_TPROXY_TEST_PORT"), "--upstream-port", "5353", "--ready-file", os.Getenv("DNS_TPROXY_TEST_READY")})
	if err != nil {
		os.Exit(1)
	}
	os.Exit(0)
}
func TestCLISIGTERMCleansReadiness(t *testing.T) {
	probe, err := net.Listen("tcp6", "[::1]:0")
	if err != nil {
		t.Fatal(err)
	}
	port := probe.Addr().(*net.TCPAddr).Port
	probe.Close()
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(t.TempDir(), "child.ready")
	child := exec.Command(exe, "-test.run=^TestCLIProcess$")
	child.Env = append(os.Environ(), "DNS_TPROXY_TEST_CHILD=1", "DNS_TPROXY_TEST_PORT="+strconv.Itoa(port), "DNS_TPROXY_TEST_READY="+marker)
	if err := child.Start(); err != nil {
		t.Fatal(err)
	}
	defer child.Process.Kill()
	deadline := time.Now().Add(2 * time.Second)
	var data []byte
	for time.Now().Before(deadline) {
		data, _ = os.ReadFile(marker)
		if len(data) > 0 {
			break
		}
		time.Sleep(time.Millisecond)
	}
	if strings.TrimSpace(string(data)) != strconv.Itoa(child.Process.Pid) {
		t.Fatalf("child ready marker wrong: %q", data)
	}
	c, err := net.DialTimeout("tcp6", net.JoinHostPort("::1", strconv.Itoa(port)), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	c.Close()
	if err := child.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- child.Wait() }()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("SIGTERM failed to stop CLI")
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatal("SIGTERM left stale ready marker")
	}
}

func TestReadyMarkerExistsOnlyWhileBothListenersServe(t *testing.T) {
	cfg := testConfig(5353)
	cfg.ReadyFile = filepath.Join(t.TempDir(), "relay.ready")
	r, err := newRelay(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(cfg.ReadyFile); !os.IsNotExist(err) {
		t.Fatal("ready marker existed before serve")
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- r.serve(ctx) }()
	deadline := time.Now().Add(200 * time.Millisecond)
	var data []byte
	for time.Now().Before(deadline) {
		data, _ = os.ReadFile(cfg.ReadyFile)
		if len(data) > 0 {
			break
		}
		time.Sleep(time.Millisecond)
	}
	if string(data) != strconv.Itoa(os.Getpid())+"\n" {
		t.Fatalf("ready marker missing or wrong PID: %q", data)
	}
	info, err := os.Stat(cfg.ReadyFile)
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("marker permissions: %v %v", info, err)
	}
	if r.udp.LocalAddr().(*net.UDPAddr).Port != r.tcp.Addr().(*net.TCPAddr).Port {
		t.Fatal("UDP/TCP listeners disagree")
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("graceful exit blocked")
	}
	if _, err := os.Stat(cfg.ReadyFile); !os.IsNotExist(err) {
		t.Fatal("ready marker survived graceful exit")
	}
}
func TestStoppingRelayDoesNotDeleteReplacementMarker(t *testing.T) {
	cfg := testConfig(5353)
	cfg.TCPIdleTimeout = 200 * time.Millisecond
	cfg.ReadyFile = filepath.Join(t.TempDir(), "relay.ready")
	r, err := newRelay(cfg)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- r.serve(ctx) }()
	c, err := net.Dial("tcp6", r.tcp.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.Write([]byte{0})
	deadline := time.Now().Add(time.Second)
	for len(r.sem) == 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	cancel()
	deadline = time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(cfg.ReadyFile); os.IsNotExist(err) {
			break
		}
		time.Sleep(time.Millisecond)
	}
	if err := os.WriteFile(cfg.ReadyFile, []byte("replacement\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(cfg.ReadyFile)
	if err != nil || string(data) != "replacement\n" {
		t.Fatalf("draining old instance deleted replacement marker: %q %v", data, err)
	}
}

func TestFailedTCPBindNeverPublishesReadiness(t *testing.T) {
	listener, err := net.Listen("tcp6", "[::1]:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	cfg := testConfig(5353)
	cfg.ListenPort = listener.Addr().(*net.TCPAddr).Port
	cfg.ReadyFile = filepath.Join(t.TempDir(), "relay.ready")
	r, err := newRelay(cfg)
	if err == nil {
		r.udp.Close()
		r.tcp.Close()
		t.Fatal("conflicting TCP bind accepted")
	}
	if _, err := os.Stat(cfg.ReadyFile); !os.IsNotExist(err) {
		t.Fatal("failed startup published readiness")
	}
	// Failed TCP startup must also release the already-bound UDP socket.
	udp, err := net.ListenUDP("udp6", &net.UDPAddr{IP: net.ParseIP("::1"), Port: cfg.ListenPort})
	if err != nil {
		t.Fatal(err)
	}
	udp.Close()
}
func TestRejectsRelativeReadyPath(t *testing.T) {
	cfg := testConfig(5353)
	cfg.ReadyFile = "relative.ready"
	r, err := newRelay(cfg)
	if err == nil {
		r.udp.Close()
		r.tcp.Close()
		t.Fatal("relative ready path accepted")
	}
}
