#!/usr/bin/env sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT=${1:?output root required}
mkdir -p "$OUT/arm64" "$OUT/armv7" "$OUT/amd64"
OUT=$(CDPATH= cd -- "$OUT" && pwd)
cd "$ROOT/helper/dns-tproxy"
# The complete relay suite (including port-53 transparent sockets) runs in an
# isolated root network namespace in CI; cross-packaging never binds host DNS.
for arch in arm64 armv7 amd64; do
    case "$arch" in armv7) target=arm ;; *) target=$arch ;; esac
    GOOS=linux GOARCH=$target GOARM=7 CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o "$OUT/$arch/agh-dns-tproxy" .
    (cd "$OUT/$arch" && sha256sum agh-dns-tproxy > agh-dns-tproxy.sha256)
done
