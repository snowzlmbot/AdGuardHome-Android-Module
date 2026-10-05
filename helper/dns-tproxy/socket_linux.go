package main

import (
	"context"
	"errors"
	"net"
	"syscall"
	"time"
)

const ipv6Transparent = 75

// All socket options run before bind. Fail closed if the kernel denies them.
func listenerControl(transparent bool, original bool) func(string, string, syscall.RawConn) error {
	return func(network, address string, rc syscall.RawConn) error {
		var sockErr error
		err := rc.Control(func(fd uintptr) {
			options := []struct{ level, name int }{{syscall.IPPROTO_IPV6, syscall.IPV6_V6ONLY}}
			if transparent {
				options = append(options, struct{ level, name int }{syscall.IPPROTO_IPV6, ipv6Transparent})
			}
			if original {
				options = append(options, struct{ level, name int }{syscall.IPPROTO_IPV6, ipv6OriginalDst})
			}
			for _, opt := range options {
				if sockErr = syscall.SetsockoptInt(int(fd), opt.level, opt.name, 1); sockErr != nil {
					return
				}
			}
		})
		if err != nil {
			return err
		}
		return sockErr
	}
}

func validIPv6DNS(dst *net.UDPAddr) bool {
	return dst != nil && dst.Port == 53 && dst.IP.To16() != nil && dst.IP.To4() == nil && !dst.IP.IsUnspecified() && !dst.IP.IsMulticast() && (!dst.IP.IsLinkLocalUnicast() || dst.Zone != "")
}

func validTCPDestination(dst *net.TCPAddr) bool {
	// TCP replies use the existing kernel socket; getsockname may omit a zone
	// after loopback rerouting. No new foreign-address bind is made here.
	return dst != nil && dst.Port == 53 && dst.IP.To16() != nil && dst.IP.To4() == nil && !dst.IP.IsUnspecified() && !dst.IP.IsMulticast()
}

// This creates one short-lived, connected sender per reply. The only foreign
// bind is the captured IPv6 DNS address:53; no destination is a configurable upstream.
func sendTransparentUDP(b []byte, src, peer *net.UDPAddr, timeout time.Duration) error {
	if !validIPv6DNS(src) || peer == nil || peer.Port < 1 || peer.IP.To4() != nil || peer.IP.IsUnspecified() || peer.IP.IsMulticast() {
		return errors.New("invalid transparent reply endpoints")
	}
	dialer := net.Dialer{LocalAddr: src, Timeout: timeout, Control: func(network, address string, rc syscall.RawConn) error {
		var sockErr error
		err := rc.Control(func(fd uintptr) {
			sockErr = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IPV6, ipv6Transparent, 1)
			if sockErr == nil {
				sockErr = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_REUSEADDR, 1)
			}
		})
		if err != nil {
			return err
		}
		return sockErr
	}}
	conn, err := dialer.DialContext(context.Background(), "udp6", peer.String())
	if err != nil {
		return err
	}
	defer conn.Close()
	conn.SetWriteDeadline(time.Now().Add(timeout))
	_, err = conn.Write(b)
	return err
}
