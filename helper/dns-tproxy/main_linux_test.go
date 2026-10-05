package main

import (
	"testing"
	"time"
)

func TestCLIContract(t *testing.T) {
	cfg, err := parseConfig([]string{"--listen-port", "1053", "--upstream-port", "5353", "--ready-file", "/private/relay.ready"})
	if err != nil {
		t.Fatal(err)
	}
	if cfg.ListenPort != 1053 || cfg.UpstreamPort != 5353 || cfg.ReadyFile != "/private/relay.ready" || cfg.NontransparentTestMode || cfg.MaxConcurrency != 128 || cfg.UDPTimeout != 5*time.Second || cfg.TCPIdleTimeout != 5*time.Second {
		t.Fatalf("CLI contract wrong: %+v", cfg)
	}
	cfg, err = parseConfig([]string{"--non-transparent", "--listen-port", "1053", "--upstream-port", "5353"})
	if err != nil || !cfg.NontransparentTestMode {
		t.Fatalf("loopback test mode: %+v %v", cfg, err)
	}
}
func TestCLIRejectsUnsafeValues(t *testing.T) {
	cases := [][]string{
		{"--listen-port", "0"}, {"--listen-port", "53"}, {"--listen-port", "65536"},
		{"--upstream-port", "0"}, {"--upstream-port", "-1"},
		{"--listen-port", "1053; id"}, {"--upstream-port", "127.0.0.1:53"},
		{"--ready-file", "relative.ready"}, {"--ready-file", ""},
		{"--upstream", "example.org:53"}, {"--nontransparent-test-mode"}, {"extra"},
	}
	for _, args := range cases {
		if cfg, err := parseConfig(args); err == nil {
			t.Fatalf("accepted unsafe CLI %q: %+v", args, cfg)
		}
	}
}
