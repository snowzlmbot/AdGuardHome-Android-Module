#!/system/bin/sh

MODDIR=${MODDIR:-${0%/*}}
AGH_ROOT=${AGH_ROOT:-/data/adb/agh}
AGH_CONFIG_DIR=${AGH_CONFIG_DIR:-$AGH_ROOT/config}
AGH_STATE_DIR=${AGH_STATE_DIR:-$AGH_ROOT/state}
AGH_RUN_DIR=${AGH_RUN_DIR:-$AGH_ROOT/run}
AGH_LOG_DIR=${AGH_LOG_DIR:-$AGH_ROOT/logs}
AGH_BACKUP_DIR=${AGH_BACKUP_DIR:-$AGH_ROOT/backup}
AGH_DATA_DIR=${AGH_DATA_DIR:-$AGH_ROOT/data}

ensure_dirs() {
    mkdir -p "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR" "$AGH_LOG_DIR" "$AGH_BACKUP_DIR" "$AGH_DATA_DIR"
}

is_nonempty_absolute_path() {
    case "${1:-}" in
        /*) [ "${1#/}" != "" ] && [ "${1%/}" != "" ] ;;
        *) return 1 ;;
    esac
}

safe_target_path() {
    target=${1:-}
    is_nonempty_absolute_path "$target" || return 1
    case "$target" in
        /|/data|/data/adb|/data/adb/agh|/data/adb/modules|/data/system) return 1 ;;
        *..*) return 1 ;;
    esac
    return 0
}

read_key_value() {
    key=$1
    file=$2
    if [ -f "$file" ]; then
        sed -n "s/^${key}=//p" "$file" | sed -n '1p'
    fi
}

# Android builds can expose a broken or absent external sync/mv utility while
# the shell and core are still usable. State writes must remain atomic without
# turning an optional flush into a hard failure.
agh_sync() {
    if command -v sync >/dev/null 2>&1; then
        sync >/dev/null 2>&1 || true
    fi
}

agh_move() {
    [ "$#" -eq 2 ] || return 2
    if mv -f "$1" "$2" >/dev/null 2>&1; then
        return 0
    fi
    cp -f "$1" "$2" >/dev/null 2>&1 && rm -f "$1"
}
