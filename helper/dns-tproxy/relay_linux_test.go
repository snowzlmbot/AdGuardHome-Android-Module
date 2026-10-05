package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"io"
	"net"
	"testing"
	"time"
)

func dnsQuery(id uint16) []byte {
	return []byte{byte(id >> 8), byte(id), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 4, 't', 'e', 's', 't', 0, 0, 1, 0, 1}
}
func dnsResponse(q []byte) []byte { r := append([]byte(nil), q...); r[2] |= 0x80; return r }

func testConfig(upstream int) config {
	return config{ListenPort: 0, UpstreamPort: upstream, NontransparentTestMode: true, UDPTimeout: time.Second, TCPIdleTimeout: time.Second, MaxConcurrency: 8}
}
func startTestRelay(t *testing.T, cfg config) *relay {
	t.Helper()
	r, err := newRelay(cfg)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- r.serve(ctx) }()
	t.Cleanup(func() {
		cancel()
		select {
		case err := <-done:
			if err != nil {
				t.Error(err)
			}
		case <-time.After(2 * time.Second):
			t.Error("relay did not stop")
		}
	})
	return r
}

func writeTestFrame(c net.Conn, b []byte) error {
	header := []byte{byte(len(b) >> 8), byte(len(b))}
	if _, err := c.Write(header); err != nil {
		return err
	}
	_, err := c.Write(b)
	return err
}
func readTestFrame(c net.Conn) ([]byte, error) {
	var h [2]byte
	if _, err := io.ReadFull(c, h[:]); err != nil {
		return nil, err
	}
	b := make([]byte, int(binary.BigEndian.Uint16(h[:])))
	_, err := io.ReadFull(c, b)
	return b, err
}
func TestGracefulExitStopsAnActiveTCPStream(t *testing.T) {
	upstream, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer upstream.Close()
	go func() {
		c, err := upstream.Accept()
		if err != nil {
			return
		}
		defer c.Close()
		for {
			q, err := readTestFrame(c)
			if err != nil {
				return
			}
			if err := writeTestFrame(c, dnsResponse(q)); err != nil {
				return
			}
		}
	}()
	cfg := testConfig(upstream.Addr().(*net.TCPAddr).Port)
	cfg.TCPIdleTimeout = 100 * time.Millisecond
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
	queries := make(chan struct{}, 1)
	stopped := make(chan struct{})
	go func() {
		defer close(stopped)
		for {
			c.SetDeadline(time.Now().Add(time.Second))
			if err := writeTestFrame(c, dnsQuery(4)); err != nil {
				return
			}
			if _, err := readTestFrame(c); err != nil {
				return
			}
			select {
			case queries <- struct{}{}:
			default:
			}
			time.Sleep(5 * time.Millisecond)
		}
	}()
	select {
	case <-queries:
	case <-time.After(time.Second):
		t.Fatal("active stream never started")
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(200 * time.Millisecond):
		c.Close()
		<-done
		t.Fatal("active traffic prevented graceful shutdown")
	}
	select {
	case <-stopped:
	case <-time.After(time.Second):
		t.Fatal("TCP stream survived shutdown")
	}
}

func TestTCPFrameUnderHeaderLengthIsRejectedBeforeBody(t *testing.T) {
	reader := bytes.NewReader([]byte{0, 11})
	if _, err := readFrame(reader); err == nil || err == io.EOF || err == io.ErrUnexpectedEOF {
		t.Fatalf("undersized frame should fail before trying to read body: %v", err)
	}
}
func TestTCPIdleTimeoutClosesClient(t *testing.T) {
	cfg := testConfig(5353)
	cfg.TCPIdleTimeout = 50 * time.Millisecond
	r := startTestRelay(t, cfg)
	c, err := net.Dial("tcp6", r.tcp.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	// Incomplete frame tests a slow sender as well as an entirely idle peer.
	c.Write([]byte{0})
	c.SetReadDeadline(time.Now().Add(300 * time.Millisecond))
	var b [1]byte
	_, err = c.Read(b[:])
	if err == nil {
		t.Fatal("idle client accepted")
	}
	if e, ok := err.(net.Error); ok && e.Timeout() {
		t.Fatalf("client deadline fired instead of relay idle timeout: %v", err)
	}
}
func TestConcurrencyLimitRejectsAdditionalTCPClient(t *testing.T) {
	cfg := testConfig(5353)
	cfg.MaxConcurrency = 1
	cfg.TCPIdleTimeout = 100 * time.Millisecond
	r := startTestRelay(t, cfg)
	first, err := net.Dial("tcp6", r.tcp.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer first.Close()
	deadline := time.Now().Add(time.Second)
	for len(r.sem) != 1 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if len(r.sem) != 1 {
		t.Fatal("first connection not accounted")
	}
	second, err := net.Dial("tcp6", r.tcp.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer second.Close()
	second.SetReadDeadline(time.Now().Add(50 * time.Millisecond))
	var b [1]byte
	_, err = second.Read(b[:])
	if err == nil {
		t.Fatal("extra client accepted")
	}
	if e, ok := err.(net.Error); ok && e.Timeout() {
		t.Fatalf("extra client not promptly closed: %v", err)
	}
}

func TestUDPRejectsNonDNSPayloadAndMismatchedReply(t *testing.T) {
	upstream, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer upstream.Close()
	r := startTestRelay(t, testConfig(upstream.LocalAddr().(*net.UDPAddr).Port))
	client, err := net.DialUDP("udp6", nil, r.udp.LocalAddr().(*net.UDPAddr))
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	client.Write([]byte("not DNS"))
	upstream.SetReadDeadline(time.Now().Add(100 * time.Millisecond))
	b := make([]byte, 65535)
	if _, _, err := upstream.ReadFromUDP(b); err == nil {
		t.Fatal("non-DNS payload reached loopback upstream")
	}
	upstream.SetReadDeadline(time.Now().Add(time.Second))
	go func() {
		n, peer, err := upstream.ReadFromUDP(b)
		if err == nil {
			wrong := dnsResponse(b[:n])
			wrong[0] ^= 0xff
			upstream.WriteToUDP(wrong, peer)
		}
	}()
	client.SetDeadline(time.Now().Add(150 * time.Millisecond))
	client.Write(dnsQuery(42))
	if _, err := client.Read(b); err == nil {
		t.Fatal("mismatched DNS response was relayed")
	}
}

func TestTCPRejectsUndersizedFrame(t *testing.T) {
	upstream, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer upstream.Close()
	r := startTestRelay(t, testConfig(upstream.Addr().(*net.TCPAddr).Port))
	c, err := net.Dial("tcp6", r.tcp.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(300 * time.Millisecond))
	writeTestFrame(c, []byte("not DNS"))
	upstream.(*net.TCPListener).SetDeadline(time.Now().Add(100 * time.Millisecond))
	if u, err := upstream.Accept(); err == nil {
		u.Close()
		t.Fatal("invalid DNS frame opened upstream connection")
	}
	var one [1]byte
	if _, err := c.Read(one[:]); err == nil {
		t.Fatal("invalid DNS frame accepted")
	}
}

func TestTCPRelaysMultipleFramedQueriesWithoutEOF(t *testing.T) {
	upstream, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer upstream.Close()
	seen := make(chan []byte, 2)
	go func() {
		c, err := upstream.Accept()
		if err != nil {
			return
		}
		defer c.Close()
		c.SetDeadline(time.Now().Add(time.Second))
		for i := 0; i < 2; i++ {
			q, err := readTestFrame(c)
			if err != nil {
				return
			}
			seen <- q
			writeTestFrame(c, dnsResponse(q))
		}
	}()
	r := startTestRelay(t, testConfig(upstream.Addr().(*net.TCPAddr).Port))
	c, err := net.Dial("tcp6", r.tcp.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(500 * time.Millisecond))
	for i := 0; i < 2; i++ {
		q := dnsQuery(uint16(40 + i))
		if err := writeTestFrame(c, q); err != nil {
			t.Fatal(err)
		}
		b, err := readTestFrame(c)
		if err != nil {
			t.Fatalf("framed response requires no client EOF: %v", err)
		}
		if !bytes.Equal(b, dnsResponse(q)) {
			t.Fatalf("TCP response altered: %x", b)
		}
		select {
		case got := <-seen:
			if !bytes.Equal(got, q) {
				t.Fatal("TCP query altered")
			}
		case <-time.After(time.Second):
			t.Fatal("no fixed upstream query")
		}
	}
}

func TestUDPRelaysToFixedLoopback(t *testing.T) {
	upstream, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer upstream.Close()
	want := dnsQuery(0x1234)
	seen := make(chan []byte, 1)
	go func() {
		b := make([]byte, 65535)
		n, addr, err := upstream.ReadFromUDP(b)
		if err == nil {
			seen <- append([]byte(nil), b[:n]...)
			upstream.WriteToUDP(dnsResponse(b[:n]), addr)
		}
	}()
	r := startTestRelay(t, testConfig(upstream.LocalAddr().(*net.UDPAddr).Port))
	client, err := net.DialUDP("udp6", nil, r.udp.LocalAddr().(*net.UDPAddr))
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	client.SetDeadline(time.Now().Add(500 * time.Millisecond))
	if _, err := client.Write(want); err != nil {
		t.Fatal(err)
	}
	b := make([]byte, 65535)
	n, err := client.Read(b)
	if err != nil {
		t.Fatalf("relay failed UDP roundtrip: %v", err)
	}
	if !bytes.Equal(b[:n], dnsResponse(want)) {
		t.Fatalf("response altered: %x", b[:n])
	}
	select {
	case got := <-seen:
		if !bytes.Equal(got, want) {
			t.Fatalf("upstream query altered: %x", got)
		}
	case <-time.After(time.Second):
		t.Fatal("fixed upstream got no query")
	}
}
