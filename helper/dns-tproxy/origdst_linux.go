package main

import (
	"encoding/binary"
	"errors"
	"net"
	"strconv"
	"syscall"
)

const ipv6OriginalDst = 74 // Linux IPV6_RECVORIGDSTADDR / IPV6_ORIGDSTADDR

func originalDestination(oob []byte, flags int) (*net.UDPAddr, error) {
	if flags&(syscall.MSG_CTRUNC|syscall.MSG_TRUNC) != 0 {
		return nil, errors.New("truncated DNS datagram or control message")
	}
	messages, err := syscall.ParseSocketControlMessage(oob)
	if err != nil {
		return nil, err
	}
	var dst *net.UDPAddr
	for _, msg := range messages {
		if msg.Header.Level != syscall.IPPROTO_IPV6 || msg.Header.Type != ipv6OriginalDst {
			continue
		}
		if dst != nil {
			return nil, errors.New("duplicate IPv6 original destination")
		}
		if len(msg.Data) != 28 {
			return nil, errors.New("invalid IPv6 original destination length")
		}
		b := msg.Data
		if binary.NativeEndian.Uint16(b[0:2]) != syscall.AF_INET6 {
			return nil, errors.New("invalid original destination family")
		}
		ip := append(net.IP(nil), b[8:24]...)
		zone := ""
		if scope := binary.NativeEndian.Uint32(b[24:28]); scope != 0 {
			zone = strconv.FormatUint(uint64(scope), 10)
		}
		dst = &net.UDPAddr{IP: ip, Port: int(binary.BigEndian.Uint16(b[2:4])), Zone: zone}
		if dst.Port != 53 || ip.To4() != nil || ip.IsUnspecified() || ip.IsMulticast() || (ip.IsLinkLocalUnicast() && zone == "") {
			return nil, errors.New("original destination is not scoped unicast IPv6 DNS")
		}
	}
	if dst == nil {
		return nil, errors.New("missing IPv6 original destination")
	}
	return dst, nil
}
