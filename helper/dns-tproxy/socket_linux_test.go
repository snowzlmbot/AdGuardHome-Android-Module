package main

import (
	"net"
	"os"
	"syscall"
	"testing"
	"time"
)

func requireRoot(t *testing.T) {
	t.Helper()
	if os.Geteuid() != 0 {
		t.Skip("transparent socket tests require root/CAP_NET_ADMIN")
	}
}
func socketOption(t *testing.T, conn interface {
	SyscallConn() (syscall.RawConn, error)
}, level, option int) int {
	t.Helper()
	rc, err := conn.SyscallConn()
	if err != nil {
		t.Fatal(err)
	}
	var value int
	if err := rc.Control(func(fd uintptr) { value, err = syscall.GetsockoptInt(int(fd), level, option) }); err != nil {
		t.Fatal(err)
	}
	if err != nil {
		t.Fatal(err)
	}
	return value
}
func TestTransparentListenerOptions(t *testing.T) {
	requireRoot(t)
	cfg := testConfig(5353)
	cfg.NontransparentTestMode = false
	r, err := newRelay(cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer r.udp.Close()
	defer r.tcp.Close()
	if got := socketOption(t, r.udp, syscall.IPPROTO_IPV6, 75); got != 1 {
		t.Fatalf("UDP IPV6_TRANSPARENT = %d", got)
	}
	if got := socketOption(t, r.udp, syscall.IPPROTO_IPV6, 74); got != 1 {
		t.Fatalf("UDP IPV6_RECVORIGDSTADDR = %d", got)
	}
	if got := socketOption(t, r.tcp.(*net.TCPListener), syscall.IPPROTO_IPV6, 75); got != 1 {
		t.Fatalf("TCP IPV6_TRANSPARENT = %d", got)
	}
	if got := socketOption(t, r.udp, syscall.IPPROTO_IPV6, syscall.IPV6_V6ONLY); got != 1 {
		t.Fatalf("UDP accepted IPv4 mapped = %d", got)
	}
}
func TestTransparentUDPReplyHasOriginalDNSPeer(t *testing.T) {
	requireRoot(t)
	client, err := net.ListenUDP("udp6", &net.UDPAddr{IP: net.ParseIP("::1")})
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	src := &net.UDPAddr{IP: net.ParseIP("2001:db8::53"), Port: 53}
	response := dnsResponse(dnsQuery(52))
	if err := sendTransparentUDP(response, src, client.LocalAddr().(*net.UDPAddr), time.Second); err != nil {
		t.Fatal(err)
	}
	client.SetReadDeadline(time.Now().Add(200 * time.Millisecond))
	b := make([]byte, 65535)
	n, peer, err := client.ReadFromUDP(b)
	if err != nil {
		t.Fatalf("transparent source reply missing: %v", err)
	}
	if n != len(response) || peer.Port != 53 || !peer.IP.Equal(src.IP) {
		t.Fatalf("reply did not preserve original DNS peer: %v n=%d", peer, n)
	}
}
func TestTransparentUDPRoundtripUsesKernelOriginalDestination(t *testing.T) {
	requireRoot(t)
	upstream, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer upstream.Close()
	go func() {
		b := make([]byte, 65535)
		n, peer, err := upstream.ReadFromUDP(b)
		if err == nil {
			upstream.WriteToUDP(dnsResponse(b[:n]), peer)
		}
	}()
	cfg := testConfig(upstream.LocalAddr().(*net.UDPAddr).Port)
	cfg.ListenPort = 53
	cfg.NontransparentTestMode = false
	r := startTestRelay(t, cfg)
	// Route-free harness uses original port 53 as the receiver, unlike the
	// production high-port TPROXY listener. Permit the separate sender to bind
	// that same local source while this harness receiver remains open.
	rc, err := r.udp.SyscallConn()
	if err != nil {
		t.Fatal(err)
	}
	var sockErr error
	if err := rc.Control(func(fd uintptr) {
		sockErr = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_REUSEADDR, 1)
	}); err != nil || sockErr != nil {
		t.Fatalf("harness reuseaddr: %v %v", err, sockErr)
	}
	c, err := net.DialUDP("udp6", nil, r.udp.LocalAddr().(*net.UDPAddr))
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(300 * time.Millisecond))
	q := dnsQuery(72)
	if _, err := c.Write(q); err != nil {
		t.Fatal(err)
	}
	b := make([]byte, 65535)
	n, err := c.Read(b)
	if err != nil {
		t.Fatalf("kernel ancillary transparent roundtrip failed: %v", err)
	}
	if n != len(q) || b[0] != q[0] || b[2]&0x80 == 0 {
		t.Fatalf("bad transparent DNS reply: %x", b[:n])
	}
}

func TestTransparentTCPRejectsDirectHighPortConnection(t *testing.T) {
	requireRoot(t)
	upstream, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer upstream.Close()
	cfg := testConfig(upstream.Addr().(*net.TCPAddr).Port)
	cfg.NontransparentTestMode = false
	r := startTestRelay(t, cfg)
	c, err := net.Dial("tcp6", r.tcp.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	writeTestFrame(c, dnsQuery(3))
	upstream.(*net.TCPListener).SetDeadline(time.Now().Add(150 * time.Millisecond))
	if u, err := upstream.Accept(); err == nil {
		u.Close()
		t.Fatal("transparent listener acted as generic high-port proxy")
	}
}

func TestTCPOriginalLinkLocalMayOmitZone(t *testing.T) {
	// Existing kernel TCP sockets can reply without re-binding a scoped IP.
	if !validTCPDestination(&net.TCPAddr{IP: net.ParseIP("fe80::1"), Port: 53}) {
		t.Fatal("kernel TCP link-local destination rejected without zone")
	}
	if validTCPDestination(&net.TCPAddr{IP: net.ParseIP("::1"), Port: 48146}) {
		t.Fatal("direct high-port connection accepted")
	}
}
