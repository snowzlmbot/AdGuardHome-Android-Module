# IPv6 DNS TPROXY helper

Linux-only, standard-library Go relay. It never resolves hostnames and never
forwards a query to the intercepted DNS server: both transports use the numeric
IPv4 loopback upstream `127.0.0.1:<upstream-port>`. No shell commands, firewall
changes, policy routes, IPv6 disabling, or external DNS fallback exist here.

## Invocation contract

```sh
dns-tproxy --listen-port 1053 --upstream-port 5353 \
  --ready-file /absolute/private/runtime/dns-tproxy.ready
```

* Transparent mode is the default. Both UDP and TCP bind **`[::1]:1053`**;
  the parent must configure its TPROXY target with `--on-ip ::1`, that port,
  local policy routing, and the correct scope/UID exclusions.
* `--listen-port`: `1024..65535`, default `1053`.
* `--upstream-port`: `1..65535`, default `53`. The address is not configurable.
* `--ready-file`: optional absolute pathname in an **existing trusted private
  directory**. After both sockets and required options are established, an
  atomic same-directory rename publishes a mode-0600 file containing the
  decimal PID and newline. SIGTERM/SIGINT or a listener failure removes it
  before listener closure/draining. No query-upstream health claim is implied.
* **`--non-transparent` is only for loopback integration tests.** It bypasses
  transparent socket options/original-destination checks, not fixed-upstream,
  frame, DNS-header, timeout, or concurrency protections. Do not enable it in
  the Android module. There are no legacy flag aliases.

Use a unique marker pathname per managed instance; serialize lifecycle changes.
SIGKILL/crashes can leave stale markers. The parent must verify PID identity,
listener sockets, and freshness, rather than trusting a file alone.

## Data path and bounds

* UDP listeners set Linux `IPV6_TRANSPARENT=75`,
  `IPV6_RECVORIGDSTADDR=74`, and `IPV6_V6ONLY` before binding.
  `ReadMsgUDP` control messages yield a native-endian `sockaddr_in6` family
  and scope, network-endian port, and copied IPv6 address. Truncated,
  duplicate/missing/wrong-family metadata, non-53 destinations, IPv4-mapped,
  unspecified/multicast addresses, and scope-less link-local addresses fail
  closed. Numeric scope IDs (e.g. `fe80::1%7`) are preserved through sender bind.
* A connected per-query UDP socket exchanges with fixed loopback upstream.
  A short-lived `IPV6_TRANSPARENT` sender binds the captured original DNS
  IPv6 address **and port 53**, then sends only the DNS reply to the captured
  client. The application's original peer remains unchanged. Sender binds can
  fail if another non-reusable wildcard/local IPv6 port-53 socket conflicts.
* TCP listeners set `IPV6_TRANSPARENT`/`IPV6_V6ONLY`. Accepted `LocalAddr()`
  must be unicast IPv6 DNS port 53 (the TPROXY-preserved destination), preventing
  direct high-port access from becoming a general proxy. Sequential framed DNS
  queries on a persistent connection are relayed without waiting for EOF.
* Each message is `12..65535` bytes; TCP uses the two-byte DNS length prefix,
  exact bounded reads, and complete writes. Minimal DNS header checks require a
  query with a nonzero question count, or a response with QR set and matching
  transaction ID. This is **not** a full DNS-semantic validator; AGH parses the
  message. DNS contents/extensions are otherwise unchanged.
* At most **128** concurrent UDP transactions/TCP connections share a global
  admission limit. Excess UDP work is dropped, excess TCP clients closed.
  UDP exchange timeout and TCP per-exchange/partial-frame idle deadline are
  **5 seconds**. Persistent valid TCP sessions have no lifetime quota.
  Shutdown stops accepting/new stream iterations; in-flight bounded I/O may
  drain before process exit. Query/response failures are silent and fail closed.

## Build (no dependencies; no packaging integration)

From this directory, with a pinned Go toolchain:

```sh
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' -o ../../.cache/dns-tproxy/dns-tproxy-linux-arm64 .
CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 go build -trimpath -ldflags='-s -w' -o ../../.cache/dns-tproxy/dns-tproxy-linux-armv7 .
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o ../../.cache/dns-tproxy/dns-tproxy-linux-amd64 .
```

Linux ELF artifacts run without libc/Android linker dependencies. Runtime root
or suitable capabilities and Android SELinux permissions are required.

## Tests and limitations

Tests are Linux-only. Run the full suite in a disposable network namespace
because the route-free kernel-original-destination fixture binds `[::1]:53`;
this avoids host DNS conflicts and gives **no external network path**:

```sh
sudo unshare --net sh -c 'ip link set lo up; go test -race -cover -count=5 ./...'
go vet ./...
```

The fixture temporarily enables SO_REUSEADDR on its test-only port-53 receiver
so its distinct transparent sender can bind the same local source. Production
uses a high-port receiver and does not enable UDP-listener reuse. No test
changes the host firewall/routes. Unprivileged runs skip privileged socket
checks; use the command above for the acceptance run.

Meaningful RED-to-GREEN cycles covered scoped/malformed original-destination
parsing, UDP roundtrip, persistent TCP framing, malformed-query admission,
transparent socket options/source spoofing/direct TCP rejection, readiness,
short-frame rejection, active-stream shutdown, and replacement-marker safety.
Timeout/concurrency regressions and a real CLI subprocess SIGTERM test also run.
No existing tests were removed; no prior helper coverage baseline existed.
Low-value duplicate accessor/default-value tests were omitted instead of cutting
security/concurrency/lifecycle tests. Measured initial coverage is the baseline,
not proof of a before/after two-percentage-point retention claim.

**Not yet proven here:** actual Xiaomi TPROXY recirculation/policy routing,
link-local wlan0 scoped delivery, accepted TCP original endpoint on that kernel,
Android SELinux, and interference from OEM firewall rules. Parent owns those
on-device checks and all network/lifecycle/package integration. IPv6 is never
disabled or blocked by this helper.
