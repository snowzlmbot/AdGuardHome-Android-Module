package main

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"path/filepath"
	"sync"
	"time"
)

const maxDNSMessage = 65535

type config struct {
	ListenPort             int
	UpstreamPort           int
	NontransparentTestMode bool
	UDPTimeout             time.Duration
	TCPIdleTimeout         time.Duration
	MaxConcurrency         int
	ReadyFile              string
}
type relay struct {
	cfg      config
	udp      *net.UDPConn
	tcp      net.Listener
	sem      chan struct{}
	workers  sync.WaitGroup
	stopping chan struct{}
}

func newRelay(cfg config) (*relay, error) {
	if cfg.ReadyFile != "" && !filepath.IsAbs(cfg.ReadyFile) {
		return nil, errors.New("ready-file must be an absolute path")
	}
	if cfg.ListenPort < 0 || cfg.ListenPort > 65535 || cfg.UpstreamPort < 1 || cfg.UpstreamPort > 65535 {
		return nil, errors.New("invalid port")
	}
	lc := net.ListenConfig{Control: listenerControl(!cfg.NontransparentTestMode, !cfg.NontransparentTestMode)}
	packet, err := lc.ListenPacket(context.Background(), "udp6", fmt.Sprintf("[::1]:%d", cfg.ListenPort))
	if err != nil {
		return nil, err
	}
	udp := packet.(*net.UDPConn)
	lc.Control = listenerControl(!cfg.NontransparentTestMode, false)
	tl, err := lc.Listen(context.Background(), "tcp6", fmt.Sprintf("[::1]:%d", udp.LocalAddr().(*net.UDPAddr).Port))
	if err != nil {
		udp.Close()
		return nil, err
	}
	return &relay{cfg: cfg, udp: udp, tcp: tl, sem: make(chan struct{}, cfg.MaxConcurrency), stopping: make(chan struct{})}, nil
}
func (r *relay) serve(ctx context.Context) error {
	if err := publishReady(r.cfg.ReadyFile); err != nil {
		r.udp.Close()
		r.tcp.Close()
		return err
	}
	done := make(chan error, 2)
	go func() { done <- r.serveUDP() }()
	go func() { done <- r.serveTCP() }()
	var err error
	received := 0
	select {
	case <-ctx.Done():
	case err = <-done:
		received = 1
	}
	close(r.stopping)
	removeReady(r.cfg.ReadyFile)
	r.udp.Close()
	r.tcp.Close()
	for ; received < 2; received++ {
		<-done
	}
	r.workers.Wait()
	return err
}
func (r *relay) serveTCP() error {
	for {
		c, err := r.tcp.Accept()
		if err != nil {
			return err
		}
		if !r.launch(func() { r.forwardTCP(c) }) {
			c.Close()
		}
	}
}
func (r *relay) forwardTCP(client net.Conn) {
	defer client.Close()
	if !r.cfg.NontransparentTestMode {
		local, ok := client.LocalAddr().(*net.TCPAddr)
		if !ok || !validTCPDestination(local) {
			return
		}
	}
	var upstream net.Conn
	defer func() {
		if upstream != nil {
			upstream.Close()
		}
	}()
	for {
		select {
		case <-r.stopping:
			return
		default:
		}
		client.SetDeadline(time.Now().Add(r.cfg.TCPIdleTimeout))
		q, err := readFrame(client)
		if err != nil || !validQuery(q) {
			return
		}
		if upstream == nil {
			upstream, err = net.DialTimeout("tcp4", fmt.Sprintf("127.0.0.1:%d", r.cfg.UpstreamPort), r.cfg.TCPIdleTimeout)
			if err != nil {
				return
			}
		}
		upstream.SetDeadline(time.Now().Add(r.cfg.TCPIdleTimeout))
		if err := writeFrame(upstream, q); err != nil {
			return
		}
		b, err := readFrame(upstream)
		if err != nil || !validResponse(b, q) {
			return
		}
		client.SetWriteDeadline(time.Now().Add(r.cfg.TCPIdleTimeout))
		if err := writeFrame(client, b); err != nil {
			return
		}
	}
}
func validQuery(b []byte) bool {
	return len(b) >= 12 && len(b) <= maxDNSMessage && b[2]&0x80 == 0 && binary.BigEndian.Uint16(b[4:6]) > 0
}
func validResponse(b, q []byte) bool {
	return len(b) >= 12 && len(b) <= maxDNSMessage && b[2]&0x80 != 0 && b[0] == q[0] && b[1] == q[1]
}
func readFrame(r io.Reader) ([]byte, error) {
	var h [2]byte
	if _, err := io.ReadFull(r, h[:]); err != nil {
		return nil, err
	}
	n := int(binary.BigEndian.Uint16(h[:]))
	if n < 12 {
		return nil, errors.New("DNS frame is shorter than its header")
	}
	b := make([]byte, n)
	_, err := io.ReadFull(r, b)
	return b, err
}
func writeFrame(w io.Writer, b []byte) error {
	frame := make([]byte, len(b)+2)
	binary.BigEndian.PutUint16(frame, uint16(len(b)))
	copy(frame[2:], b)
	for len(frame) > 0 {
		n, err := w.Write(frame)
		if err != nil {
			return err
		}
		if n == 0 {
			return io.ErrShortWrite
		}
		frame = frame[n:]
	}
	return nil
}
func (r *relay) launch(fn func()) bool {
	select {
	case r.sem <- struct{}{}:
		r.workers.Add(1)
		go func() { defer r.workers.Done(); defer func() { <-r.sem }(); fn() }()
		return true
	default:
		return false
	}
}
func (r *relay) serveUDP() error {
	b := make([]byte, maxDNSMessage)
	oob := make([]byte, 256)
	for {
		n, on, flags, peer, err := r.udp.ReadMsgUDP(b, oob)
		if err != nil {
			return err
		}
		if !validQuery(b[:n]) {
			continue
		}
		var dst *net.UDPAddr
		if !r.cfg.NontransparentTestMode {
			dst, err = originalDestination(oob[:on], flags)
			if err != nil {
				continue
			}
		}
		q := append([]byte(nil), b[:n]...)
		r.launch(func() { r.forwardUDP(q, peer, dst) })
	}
}
func (r *relay) forwardUDP(q []byte, peer, dst *net.UDPAddr) {
	upstream, err := net.DialUDP("udp4", nil, &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: r.cfg.UpstreamPort})
	if err != nil {
		return
	}
	defer upstream.Close()
	upstream.SetDeadline(time.Now().Add(r.cfg.UDPTimeout))
	if _, err := upstream.Write(q); err != nil {
		return
	}
	b := make([]byte, maxDNSMessage)
	n, err := upstream.Read(b)
	if err != nil || !validResponse(b[:n], q) {
		return
	}
	if r.cfg.NontransparentTestMode {
		r.udp.WriteToUDP(b[:n], peer)
	} else {
		sendTransparentUDP(b[:n], dst, peer, r.cfg.UDPTimeout)
	}
}
