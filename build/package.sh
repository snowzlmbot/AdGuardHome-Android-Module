#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODULE_ROOT="$ROOT/module"
MODULE_VERSION=${1:?module version required}
AGH_VERSION=${2:?AdGuard Home version required}
OUTPUT_DIR=${3:-$ROOT/dist}
ASSET_CACHE_DIR=${ASSET_CACHE_DIR:-$ROOT/.cache/assets}
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-0}

[ -d "$MODULE_ROOT" ] || { printf '%s\n' 'missing module directory' >&2; exit 1; }
[ -f "$ROOT/build/assets.tsv" ] || { printf '%s\n' 'missing build/assets.tsv' >&2; exit 1; }
source_module_version=$(sed -n 's/^version=//p' "$MODULE_ROOT/module.prop" | sed -n '1p')
[ "$MODULE_VERSION" = "$source_module_version" ] || { printf 'module version mismatch: requested=%s source=%s\n' "$MODULE_VERSION" "$source_module_version" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { printf '%s\n' 'curl is required' >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { printf '%s\n' 'sha256sum is required' >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { printf '%s\n' 'tar is required' >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { printf '%s\n' 'zip is required' >&2; exit 1; }

build_tmp=$(mktemp -d)
trap 'rm -rf "$build_tmp"' EXIT
stage="$build_tmp/module"
mkdir -p "$stage" "$OUTPUT_DIR" "$ASSET_CACHE_DIR"
OUTPUT_DIR=$(CDPATH= cd -- "$OUTPUT_DIR" && pwd -P)
ASSET_CACHE_DIR=$(CDPATH= cd -- "$ASSET_CACHE_DIR" && pwd -P)

cp -R "$MODULE_ROOT/." "$stage/"
sed -i "s/^version=.*/version=$MODULE_VERSION/" "$stage/module.prop"

for asset_arch in arm64 armv7; do
    asset_line=$(awk -F'|' -v version="$AGH_VERSION" -v arch="$asset_arch" '$1 == version && $2 == arch { print; exit }' "$ROOT/build/assets.tsv")
    [ -n "$asset_line" ] || { printf 'no fixed asset for %s %s\n' "$AGH_VERSION" "$asset_arch" >&2; exit 1; }
    asset_url=$(printf '%s' "$asset_line" | awk -F'|' '{print $3}')
    expected_tar_sha=$(printf '%s' "$asset_line" | awk -F'|' '{print $4}')
    expected_bin_sha=$(printf '%s' "$asset_line" | awk -F'|' '{print $5}')
    asset_name=$(basename "$asset_url")
    asset_file="$ASSET_CACHE_DIR/$asset_name"
    if [ ! -f "$asset_file" ]; then curl -LfsS --retry 3 --max-time 180 "$asset_url" -o "$asset_file"; fi
    actual_tar_sha=$(sha256sum "$asset_file" | awk '{print $1}')
    [ "$actual_tar_sha" = "$expected_tar_sha" ] || { printf 'tarball checksum mismatch: %s\n' "$asset_arch" >&2; exit 1; }
    mkdir -p "$stage/bin/$asset_arch"
    tar -xOf "$asset_file" ./AdGuardHome/AdGuardHome > "$stage/bin/$asset_arch/AdGuardHome"
    actual_bin_sha=$(sha256sum "$stage/bin/$asset_arch/AdGuardHome" | awk '{print $1}')
    [ "$actual_bin_sha" = "$expected_bin_sha" ] || { printf 'binary checksum mismatch: %s\n' "$asset_arch" >&2; exit 1; }
    printf '%s  AdGuardHome\n' "$actual_bin_sha" > "$stage/bin/$asset_arch/AdGuardHome.sha256"
    chmod 0755 "$stage/bin/$asset_arch/AdGuardHome"
done

find "$stage" -type f -exec touch -d "@$SOURCE_DATE_EPOCH" {} +
(
    cd "$stage"
    find . -type f ! -name SHA256SUMS -print | sort | while IFS= read -r package_file; do sha256sum "$package_file"; done > SHA256SUMS
    touch -d "@$SOURCE_DATE_EPOCH" SHA256SUMS
)
output_file="$OUTPUT_DIR/AdGuardHome-Android-Module-${MODULE_VERSION}-agh-${AGH_VERSION}.zip"
rm -f "$output_file"
(
    cd "$stage"
    find . -type f -print | sort | zip -q -X "$output_file" -@
)
printf '%s\n' "$output_file"
sha256sum "$output_file"
