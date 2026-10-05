package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

func parseConfig(args []string) (config, error) {
	cfg := config{UDPTimeout: 5 * time.Second, TCPIdleTimeout: 5 * time.Second, MaxConcurrency: 128}
	fs := flag.NewFlagSet("dns-tproxy", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.IntVar(&cfg.ListenPort, "listen-port", 1053, "IPv6 loopback high port (1024..65535)")
	fs.IntVar(&cfg.UpstreamPort, "upstream-port", 53, "fixed 127.0.0.1 DNS port")
	fs.StringVar(&cfg.ReadyFile, "ready-file", "", "atomic PID marker in an existing private directory")
	fs.BoolVar(&cfg.NontransparentTestMode, "non-transparent", false, "loopback integration tests ONLY")
	if err := fs.Parse(args); err != nil {
		return cfg, err
	}
	if fs.NArg() != 0 {
		return cfg, errors.New("unexpected positional arguments")
	}
	if cfg.ListenPort < 1024 || cfg.ListenPort > 65535 || cfg.UpstreamPort < 1 || cfg.UpstreamPort > 65535 {
		return cfg, errors.New("listen port must be 1024..65535; upstream port must be 1..65535")
	}
	readySpecified := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "ready-file" {
			readySpecified = true
		}
	})
	if readySpecified && !filepath.IsAbs(cfg.ReadyFile) {
		return cfg, errors.New("ready-file must be an absolute path")
	}
	return cfg, nil
}
func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "dns-tproxy:", err)
		os.Exit(1)
	}
}
func run(args []string) error {
	cfg, err := parseConfig(args)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	r, err := newRelay(cfg)
	if err != nil {
		return err
	}
	return r.serve(ctx)
}
