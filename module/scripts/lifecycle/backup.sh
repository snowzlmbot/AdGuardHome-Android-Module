#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/atomic.sh"
. "$MODULE_SCRIPTS_DIR/lib/log.sh"

backup_root="$AGH_BACKUP_DIR/archives"
backup_timestamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || printf 'manual')
backup_file="$backup_root/adguardhome-config-$backup_timestamp.tar.gz"

backup_create() {
    ensure_dirs || return 1
    mkdir -p "$backup_root" || return 1
    backup_tmp="$AGH_ROOT/.backup-$backup_timestamp.$$"
    rm -rf "$backup_tmp"
    mkdir -p "$backup_tmp"
    for backup_path in config state/ports.conf state/language.conf state/install-options.done state/upstream-policy.conf; do
        [ -e "$AGH_ROOT/$backup_path" ] || continue
        mkdir -p "$backup_tmp/$(dirname "$backup_path")"
        if [ -d "$AGH_ROOT/$backup_path" ]; then
            mkdir -p "$backup_tmp/$backup_path"
            cp -R "$AGH_ROOT/$backup_path/." "$backup_tmp/$backup_path/" || { rm -rf "$backup_tmp"; return 1; }
        else
            cp -f "$AGH_ROOT/$backup_path" "$backup_tmp/$backup_path" || { rm -rf "$backup_tmp"; return 1; }
        fi
    done
    printf 'version=1\ncreated=%s\n' "$backup_timestamp" > "$backup_tmp/manifest.conf"
    chmod 0600 "$backup_tmp/manifest.conf"
    tar -czf "$backup_file" -C "$backup_tmp" . || { rm -rf "$backup_tmp"; return 1; }
    chmod 0600 "$backup_file"
    rm -rf "$backup_tmp"
    printf '%s\n' "$backup_file" > "$AGH_STATE_DIR/last-backup"
    log_message backup "created config backup"
    printf '%s\n' "$backup_file"
}

backup_latest() {
    [ -d "$backup_root" ] || return 1
    backup_latest_file=$(find "$backup_root" -type f -name 'adguardhome-config-*.tar.gz' -print 2>/dev/null | sort | tail -n 1)
    [ -n "$backup_latest_file" ] || return 1
    printf '%s\n' "$backup_latest_file"
}

backup_restore() {
    backup_restore_file=${1:-$(backup_latest)}
    [ -f "$backup_restore_file" ] || return 1
    backup_restore_tmp="$AGH_ROOT/.restore-$$"
    rm -rf "$backup_restore_tmp"
    mkdir -p "$backup_restore_tmp"
    tar -xzf "$backup_restore_file" -C "$backup_restore_tmp" || { rm -rf "$backup_restore_tmp"; return 1; }
    [ -f "$backup_restore_tmp/manifest.conf" ] || { rm -rf "$backup_restore_tmp"; return 1; }
    for backup_restore_path in config state/ports.conf state/language.conf state/install-options.done state/upstream-policy.conf; do
        [ -e "$backup_restore_tmp/$backup_restore_path" ] || continue
        mkdir -p "$AGH_ROOT/$(dirname "$backup_restore_path")"
        if [ -d "$backup_restore_tmp/$backup_restore_path" ]; then
            mkdir -p "$AGH_ROOT/$backup_restore_path"
            cp -R "$backup_restore_tmp/$backup_restore_path/." "$AGH_ROOT/$backup_restore_path/" || { rm -rf "$backup_restore_tmp"; return 1; }
        else
            cp -f "$backup_restore_tmp/$backup_restore_path" "$AGH_ROOT/$backup_restore_path" || { rm -rf "$backup_restore_tmp"; return 1; }
        fi
    done
    rm -rf "$backup_restore_tmp"
    log_message backup "restored config backup"
}

case "${1:-create}" in
    create) backup_create ;;
    latest) backup_latest ;;
    restore) backup_restore "${2:-}" ;;
    *) printf 'usage: %s {create|latest|restore [archive]}\n' "$0" >&2; exit 2 ;;
esac
