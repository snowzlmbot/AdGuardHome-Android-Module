#!/system/bin/sh

# Select a working manager-provided static BusyBox, not merely its directory.
# ASH_STANDALONE has no effect in Android mksh; each executable must enter ash.
if [ -z "${AGH_BUSYBOX:-}" ] || ! [ -x "$AGH_BUSYBOX" ]; then
    AGH_BUSYBOX=
    for agh_candidate in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$agh_candidate" ] && "$agh_candidate" true 2>/dev/null; then AGH_BUSYBOX=$agh_candidate; break; fi
    done
fi
if [ -n "$AGH_BUSYBOX" ]; then
    export AGH_BUSYBOX
    ASH_STANDALONE=1
    export ASH_STANDALONE
    # Re-enter only file-backed entrypoints, never a manager's sourced installer.
    if [ "${AGH_NO_REEXEC:-0}" != 1 ] && [ "${AGH_REEXEC_PID:-}" != "$$" ]; then
        case "$0" in
            *.sh)
                if [ -f "$0" ]; then
                    AGH_REEXEC_PID=$$
                    export AGH_REEXEC_PID
                    unset LD_LIBRARY_PATH LD_PRELOAD
                    exec "$AGH_BUSYBOX" sh "$0" "$@"
                fi
                ;;
        esac
    fi
fi
AGH_COMMAND_ENV_READY=1
export AGH_COMMAND_ENV_READY

MODDIR=${MODDIR:-${0%/*}}
AGH_ROOT=${AGH_ROOT:-/data/adb/agh}
AGH_CONFIG_DIR=${AGH_CONFIG_DIR:-$AGH_ROOT/config}
AGH_STATE_DIR=${AGH_STATE_DIR:-$AGH_ROOT/state}
AGH_RUN_DIR=${AGH_RUN_DIR:-$AGH_ROOT/run}
AGH_LOG_DIR=${AGH_LOG_DIR:-$AGH_ROOT/logs}
AGH_BACKUP_DIR=${AGH_BACKUP_DIR:-$AGH_ROOT/backup}
AGH_DATA_DIR=${AGH_DATA_DIR:-$AGH_ROOT/data}

agh_run_script() {
    if [ -n "${AGH_BUSYBOX:-}" ]; then "$AGH_BUSYBOX" sh "$@"; else sh "$@"; fi
}

ensure_dirs() {
    mkdir -p "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR" "$AGH_LOG_DIR" "$AGH_BACKUP_DIR" "$AGH_DATA_DIR" || return 1
    agh_chmod 0700 "$AGH_ROOT" "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR" "$AGH_LOG_DIR" "$AGH_BACKUP_DIR" "$AGH_DATA_DIR"
}

is_nonempty_absolute_path() {
    case "${1:-}" in /*) [ "${1#/}" != "" ] && [ "${1%/}" != "" ] ;; *) return 1 ;; esac
}

safe_target_path() {
    target=${1:-}
    is_nonempty_absolute_path "$target" || return 1
    case "$target" in /|/data|/data/adb|/data/adb/agh|/data/adb/modules|/data/system|*..*) return 1 ;; esac
}

read_key_value() {
    key=$1
    file=$2
    if [ -f "$file" ]; then sed -n "s/^${key}=//p" "$file" | sed -n '1p'; fi
}

# Never route builtins or filesystem applets through an unverified toybox.
agh_printf() { printf "$@"; }
agh_chmod() {
    if [ -n "${AGH_BUSYBOX:-}" ]; then "$AGH_BUSYBOX" chmod "$@"; else chmod "$@"; fi
}
agh_sync() {
    if [ -n "${AGH_BUSYBOX:-}" ]; then "$AGH_BUSYBOX" sync >/dev/null 2>&1 || true; fi
}
agh_move() {
    [ "$#" -eq 2 ] || return 2
    if [ -n "${AGH_BUSYBOX:-}" ]; then "$AGH_BUSYBOX" mv -f "$1" "$2"; else mv -f "$1" "$2"; fi
}
