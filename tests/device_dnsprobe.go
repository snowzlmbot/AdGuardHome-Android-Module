// Device-only DNS acceptance probe. Run as a non-root UID via authorized ADB.
package main

import (
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"time"
)

func skipName(b []byte, p int) (int, error) {
	for p < len(b) {
		n := int(b[p])
		if n&192 == 192 {
			if p+1 >= len(b) {
				break
			}
			return p + 2, nil
		}
		p++
		if n == 0 {
			return p, nil
		}
		p += n
	}
	return 0, fmt.Errorf("truncated name")
}
func main() {
	server := flag.String("server", "", "literal DNS IP[:port]")
	name := flag.String("name", "example.com", "DNS name")
	typ := flag.Int("type", 1, "1=A,28=AAAA")
	tcp := flag.Bool("tcp", false, "use TCP")
	flag.Parse()
	host, port, err := net.SplitHostPort(*server)
	if err != nil {
		host = *server
		port = "53"
	}
	base := host
	if i := strings.IndexByte(base, '%'); i >= 0 {
		base = base[:i]
	}
	if net.ParseIP(base) == nil {
		fmt.Fprintln(os.Stderr, "literal IP required")
		os.Exit(2)
	}
	q := make([]byte, 12)
	binary.BigEndian.PutUint16(q, 0xa671)
	binary.BigEndian.PutUint16(q[2:], 0x0100)
	binary.BigEndian.PutUint16(q[4:], 1)
	for _, label := range strings.Split(*name, ".") {
		if len(label) == 0 || len(label) > 63 {
			os.Exit(2)
		}
		q = append(q, byte(len(label)))
		q = append(q, label...)
	}
	q = append(q, 0, byte(*typ>>8), byte(*typ), 0, 1)
	proto := "udp"
	if *tcp {
		proto = "tcp"
	}
	c, err := net.DialTimeout(proto, net.JoinHostPort(host, port), 3*time.Second)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(3 * time.Second))
	var response []byte
	if *tcp {
		h := make([]byte, 2)
		binary.BigEndian.PutUint16(h, uint16(len(q)))
		_, err = c.Write(append(h, q...))
		if err == nil {
			_, err = io.ReadFull(c, h)
		}
		if err == nil {
			response = make([]byte, int(binary.BigEndian.Uint16(h)))
			_, err = io.ReadFull(c, response)
		}
	} else {
		_, err = c.Write(q)
		if err == nil {
			response = make([]byte, 65535)
			var n int
			n, err = c.Read(response)
			response = response[:n]
		}
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if len(response) < 12 || binary.BigEndian.Uint16(response) != 0xa671 || response[2]&128 == 0 {
		fmt.Fprintln(os.Stderr, "invalid response")
		os.Exit(1)
	}
	p := 12
	for i := 0; i < int(binary.BigEndian.Uint16(response[4:])); i++ {
		p, err = skipName(response, p)
		if err != nil || p+4 > len(response) {
			os.Exit(1)
		}
		p += 4
	}
	addresses := []string{}
	for i := 0; i < int(binary.BigEndian.Uint16(response[6:])); i++ {
		p, err = skipName(response, p)
		if err != nil || p+10 > len(response) {
			os.Exit(1)
		}
		t := binary.BigEndian.Uint16(response[p:])
		size := int(binary.BigEndian.Uint16(response[p+8:]))
		p += 10
		if p+size > len(response) {
			os.Exit(1)
		}
		if (t == 1 && size == 4) || (t == 28 && size == 16) {
			addresses = append(addresses, net.IP(response[p:p+size]).String())
		}
		p += size
	}
	json.NewEncoder(os.Stdout).Encode(map[string]any{"rcode": int(response[3] & 15), "addresses": addresses})
}
