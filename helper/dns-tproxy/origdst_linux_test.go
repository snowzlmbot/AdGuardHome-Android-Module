package main

import (
	"encoding/binary"
	"net"
	"syscall"
	"testing"
	"unsafe"
)

// Use the platform's native CMSG layout, including 32-bit alignment.
func controlMessage(level, kind int, data []byte) []byte {
	b := make([]byte, syscall.CmsgSpace(len(data)))
	h := (*syscall.Cmsghdr)(unsafe.Pointer(&b[0]))
	h.Level, h.Type = int32(level), int32(kind)
	h.SetLen(syscall.CmsgLen(len(data)))
	copy(b[syscall.CmsgLen(0):], data)
	return b
}

func originalMessage(ip string, port uint16, scope uint32) []byte {
	b := make([]byte, 28)
	binary.NativeEndian.PutUint16(b[0:2], syscall.AF_INET6)
	binary.BigEndian.PutUint16(b[2:4], port)
	copy(b[8:24], net.ParseIP(ip).To16())
	binary.NativeEndian.PutUint32(b[24:28], scope)
	return controlMessage(syscall.IPPROTO_IPV6, 74, b)
}

func TestOriginalDestinationRejectsUnusableMetadata(t *testing.T) {
	good := originalMessage("2001:db8::53", 53, 0)
	badFamily := originalMessage("2001:db8::53", 53, 0)
	binary.NativeEndian.PutUint16(badFamily[syscall.CmsgLen(0):], syscall.AF_INET)
	cases := []struct {
		name  string
		oob   []byte
		flags int
	}{
		{"control truncated", good, syscall.MSG_CTRUNC},
		{"payload truncated", good, syscall.MSG_TRUNC},
		{"wrong family", badFamily, 0},
		{"not DNS port", originalMessage("2001:db8::53", 443, 0), 0},
		{"unspecified", originalMessage("::", 53, 0), 0},
		{"multicast", originalMessage("ff02::1", 53, 7), 0},
		{"v4 mapped", originalMessage("::ffff:127.0.0.1", 53, 0), 0},
		{"linklocal missing scope", originalMessage("fe80::1", 53, 0), 0},
		{"short sockaddr", controlMessage(syscall.IPPROTO_IPV6, 74, make([]byte, 12)), 0},
		{"missing", nil, 0},
		{"malformed cmsg", []byte{1, 2, 3}, 0},
		{"conflicting originals", append(append([]byte(nil), good...), originalMessage("2001:db8::54", 53, 0)...), 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got, err := originalDestination(tc.oob, tc.flags); err == nil {
				t.Fatalf("accepted unsafe original destination %v", got)
			}
		})
	}
	// Unrelated packet info must not become an original destination.
	info := controlMessage(syscall.IPPROTO_IPV6, syscall.IPV6_PKTINFO, make([]byte, 20))
	got, err := originalDestination(append(info, good...), 0)
	if err != nil || got.String() != "[2001:db8::53]:53" {
		t.Fatalf("valid destination with unrelated cmsg: %v %v", got, err)
	}
}

func TestOriginalDestinationPreservesIPv6Scope(t *testing.T) {
	got, err := originalDestination(originalMessage("fe80::1", 53, 7), 0)
	if err != nil {
		t.Fatal(err)
	}
	if got == nil || got.String() != "[fe80::1%7]:53" {
		t.Fatalf("original scoped destination lost: %v", got)
	}
}
