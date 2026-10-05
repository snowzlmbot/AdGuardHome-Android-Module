# Verification record

Source scope: this newly added helper only. No pre-existing tests were deleted
or changed; no baseline coverage existed before the helper. Critical transport,
metadata, peer identity, lifecycle, and concurrency checks were retained rather
than forcing a test-cut quota. Omitted candidates were duplicate accessor/default
assertions; no before/after coverage-retention claim is made.

Executed on Linux arm64 in Colima using **Go 1.26.1**. Final complete acceptance
run used an isolated network namespace, loopback only, root socket capabilities:

```text
sudo unshare --net sh -c 'ip link set lo up; go test -race -cover -count=5 ./...'
ok  agh-dns-tproxy 10.234s coverage: 86.8% of statements

go vet ./...
(exit 0, no output)
```

RED observations before implementations/fixes included:

* `original scoped destination lost: <nil>`.
* Accepted truncated, wrong-family, non-DNS-port, unspecified, multicast,
  mapped-v4, scope-less link-local, and duplicate metadata.
* UDP roundtrip timed out; TCP framed response timed out waiting without EOF.
* Non-DNS payload reached fixed upstream; invalid TCP frame opened upstream.
* `UDP IPV6_TRANSPARENT = 0`; spoofed reply missing; direct high-port TCP
  connection reached upstream.
* Ready marker missing; relative marker accepted.
* Undersized TCP frame attempted a body read (`EOF`).
* Active traffic prevented graceful shutdown.
* Old draining instance deleted a newly replaced marker.

Each was rerun GREEN after the minimal corresponding implementation/fix.
Additional regression tests cover idle/partial-frame deadlines, shared admission
limit, real CLI SIGTERM cleanup, wildcard-free binding, kernel original-dst
ancillary parsing roundtrip, and a reply from nonlocal `2001:db8::53:53`.

The full transparent roundtrip fixture initially could not bind `[::1]:53`
because Colima's dnsmasq owns that port. It must run in the disposable namespace,
not disrupt that service. No acceptance tests were skipped in the final run.
This kernel fixture exercises no iptables/TPROXY routes and is not a substitute
for the parent's device-routing acceptance.

Built with Go 1.26.1, `CGO_ENABLED=0`, `GOOS=linux`, `-trimpath -ldflags='-s -w'`:

| Artifact (repository root relative) | SHA-256 |
| --- | --- |
| `.cache/dns-tproxy/dns-tproxy-linux-arm64` | `2fc732c6639908877fe82fd26a89e4e910f81092cf565ea774745abdfe765762` |
| `.cache/dns-tproxy/dns-tproxy-linux-armv7` (`GOARM=7`) | `be07bcad61f0998d5c5658574ac06b8cebeb4aacefebdcb3f001d56eed76b471` |
| `.cache/dns-tproxy/dns-tproxy-linux-amd64` | `c3d27ca751c0185266eeddf1dddbc2aeb26dda332952fa7f1c09ffde99c2d973` |

Host `file` confirmed each is a **statically linked, stripped Linux ELF** of the
expected architecture. Files were copied back from `/opt/agh-work/.cache/dns-tproxy`
and matching SHA-256 values verified. armv7/amd64 artifacts were crosscompiled,
not executed on those architectures. The Linux arm64 implementation was exercised
by the tests; actual Android acceptance remains the parent's responsibility.
