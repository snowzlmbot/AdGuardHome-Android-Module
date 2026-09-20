#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
AGH_VERSION=${1:?AdGuard Home version required}
OUTPUT_ROOT=${2:?output directory required}
UPSTREAM_URL=${UPSTREAM_URL:-}
[ -n "$UPSTREAM_URL" ] || UPSTREAM_URL=https://github.com/AdguardTeam/AdGuardHome.git
UPSTREAM_COMMIT=${UPSTREAM_COMMIT:-05ba17b282da1c4393d6a4ba4db0cf519194a362}
BUILDER_IMAGE=${BUILDER_IMAGE:-agh-builder:node22-go1.26}
BUILD_ROOT=${BUILD_ROOT:-$ROOT/.build/adguardhome-$AGH_VERSION}
SOURCE_DIR=$BUILD_ROOT/source
PATCH_FILE=$ROOT/build/patches/adguardhome-v0.107.79-querylog-autorefresh.patch

case "$AGH_VERSION" in
    0.107.79) ;;
    *) printf 'unsupported patched AdGuard Home version: %s\n' "$AGH_VERSION" >&2; exit 1 ;;
esac

rm -rf "$BUILD_ROOT" "$OUTPUT_ROOT"
mkdir -p "$BUILD_ROOT" "$OUTPUT_ROOT"
git clone --depth 1 --branch "v$AGH_VERSION" "$UPSTREAM_URL" "$SOURCE_DIR"
git -C "$SOURCE_DIR" fetch --depth 1 origin "$UPSTREAM_COMMIT"
git -C "$SOURCE_DIR" checkout --detach "$UPSTREAM_COMMIT"
git -C "$SOURCE_DIR" apply --check "$PATCH_FILE"
git -C "$SOURCE_DIR" apply "$PATCH_FILE"

docker build -t "$BUILDER_IMAGE" -f "$ROOT/docker/agh-builder.Dockerfile" "$ROOT/docker"
docker run --rm --name agh-patched-build --memory=6g --cpus=2 --pids-limit=512 \
    -v "$SOURCE_DIR:/src" \
    -v "$OUTPUT_ROOT:/out" \
    -w /src \
    "$BUILDER_IMAGE" \
    bash -lc '
        set -eu
        export PATH=/usr/local/go/bin:/go/bin:$PATH
        git config --global --add safe.directory /src
        npm --prefix client_v2 ci --no-audit --no-fund
        npm --prefix client_v2 run build-prod
        mkdir -p /out/arm64 /out/armv7
        CHANNEL=development VERSION=v0.107.79 REVISION='"$UPSTREAM_COMMIT"' \
            OUT=/out/arm64/AdGuardHome GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
            sh ./scripts/make/go-build.sh
        CHANNEL=development VERSION=v0.107.79 REVISION='"$UPSTREAM_COMMIT"' \
            OUT=/out/armv7/AdGuardHome GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
            sh ./scripts/make/go-build.sh
        file /out/arm64/AdGuardHome /out/armv7/AdGuardHome
        sha256sum /out/arm64/AdGuardHome /out/armv7/AdGuardHome
    '

for arch in arm64 armv7; do
    [ -x "$OUTPUT_ROOT/$arch/AdGuardHome" ] || { printf 'built binary is not executable: %s\n' "$arch" >&2; exit 1; }
    sha256sum "$OUTPUT_ROOT/$arch/AdGuardHome" > "$OUTPUT_ROOT/$arch/AdGuardHome.sha256"
done
printf '%s\n' "$OUTPUT_ROOT/arm64/AdGuardHome" "$OUTPUT_ROOT/armv7/AdGuardHome"
