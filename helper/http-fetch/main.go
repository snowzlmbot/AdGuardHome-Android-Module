package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func roots() *x509.CertPool {
	pool, _ := x509.SystemCertPool()
	if pool == nil {
		pool = x509.NewCertPool()
	}
	for _, d := range []string{"/system/etc/security/cacerts", "/apex/com.android.conscrypt/cacerts"} {
		entries, _ := os.ReadDir(d)
		for _, e := range entries {
			b, _ := os.ReadFile(filepath.Join(d, e.Name()))
			pool.AppendCertsFromPEM(b)
		}
	}
	return pool
}

func fetchDial(ctx context.Context, network, address string) (net.Conn, error) {
	// Static linux binaries on Android may see only an unusable ::1:53 resolver.
	// Configured DNS is for hostname lookup only; HTTPS still verifies host/cert.
	endpoints := strings.Split(os.Getenv("AGH_FETCH_DNS"), ",")
	var last error
	for _, endpoint := range endpoints {
		if endpoint == "" {
			continue
		}
		host, port, e := net.SplitHostPort(endpoint)
		if e != nil || net.ParseIP(strings.Split(host, "%")[0]) == nil || port == "" {
			return nil, fmt.Errorf("invalid fetch DNS")
		}
		resolver := &net.Resolver{PreferGo: true, Dial: func(c context.Context, n, a string) (net.Conn, error) {
			return (&net.Dialer{Timeout: 5 * time.Second}).DialContext(c, n, endpoint)
		}}
		conn, e := (&net.Dialer{Timeout: 12 * time.Second, Resolver: resolver}).DialContext(ctx, network, address)
		if e == nil {
			return conn, nil
		}
		last = e
	}
	if last != nil {
		return nil, last
	}
	return (&net.Dialer{Timeout: 15 * time.Second}).DialContext(ctx, network, address)
}

func run(a []string) error {
	if len(a) != 3 {
		return fmt.Errorf("usage: agh-http-fetch HTTPS_URL DEST MAX_BYTES")
	}
	u, e := url.Parse(a[0])
	if e != nil || u.Scheme != "https" || u.Host == "" || u.User != nil {
		return fmt.Errorf("invalid HTTPS URL")
	}
	n, e := strconv.ParseInt(a[2], 10, 64)
	if e != nil || n < 1 || n > 524288 {
		return fmt.Errorf("invalid size limit")
	}
	t := &http.Transport{DialContext: fetchDial, TLSHandshakeTimeout: 10 * time.Second, TLSClientConfig: &tls.Config{RootCAs: roots(), MinVersion: tls.VersionTLS12}}
	c := &http.Client{Transport: t, Timeout: 90 * time.Second, CheckRedirect: func(r *http.Request, v []*http.Request) error {
		if len(v) > 5 || r.URL.Scheme != "https" {
			return fmt.Errorf("unsafe redirect")
		}
		return nil
	}}
	r, e := c.Get(a[0])
	if e != nil {
		return e
	}
	defer r.Body.Close()
	if r.StatusCode != 200 {
		return fmt.Errorf("HTTP %d", r.StatusCode)
	}
	f, e := os.OpenFile(a[1], os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if e != nil {
		return e
	}
	ok := false
	defer func() {
		f.Close()
		if !ok {
			os.Remove(a[1])
		}
	}()
	count, e := io.Copy(f, io.LimitReader(r.Body, n+1))
	if e != nil {
		return e
	}
	if count < 1 || count > n {
		return fmt.Errorf("invalid response size")
	}
	if e = f.Close(); e != nil {
		return e
	}
	ok = true
	return nil
}
func main() {
	if e := run(os.Args[1:]); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
