#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/atomic.sh"
. "$MODULE_SCRIPTS_DIR/lib/log.sh"
. "$SCRIPT_DIR/backup.sh"

proxy_state_write() {
    proxy_state_value=$1
    proxy_state_reason=${2:-}
    proxy_state_tmp="$AGH_STATE_DIR/.proxy.state.$$"
    printf 'state=%s\nreason=%s\n' "$proxy_state_value" "$proxy_state_reason" > "$proxy_state_tmp" || return 1
    chmod 0600 "$proxy_state_tmp"
    agh_sync
    agh_move "$proxy_state_tmp" "$AGH_STATE_DIR/proxy.state"
}

proxy_config_value() {
    proxy_key=$1
    sed -n "s/^${proxy_key}=//p" "$AGH_CONFIG_DIR/proxy-adapter.conf" 2>/dev/null | sed -n '1p'
}

proxy_allowed() {
    proxy_candidate=$1
    proxy_allowed_result=1
    for proxy_prefix in $(sed -n 's/^allowed_prefix=//p' "$AGH_CONFIG_DIR/proxy-adapter.conf"); do
        case "$proxy_candidate" in
            "$proxy_prefix"|"$proxy_prefix"/*) proxy_allowed_result=0; break ;;
        esac
    done
    return "$proxy_allowed_result"
}

proxy_hash_manifest_line() {
    proxy_manifest_file=$1
    proxy_manifest_path=$2
    PROXY_MANIFEST_BEFORE=
    PROXY_MANIFEST_AFTER=
    [ -f "$proxy_manifest_file" ] || return 1
    while IFS='|' read -r proxy_path proxy_backup proxy_before _ _ _ proxy_after; do
        if [ "$proxy_path" = "$proxy_manifest_path" ]; then
            PROXY_MANIFEST_BEFORE=$proxy_before
            PROXY_MANIFEST_AFTER=$proxy_after
            return 0
        fi
    done < "$proxy_manifest_file"
    return 1
}

proxy_manifest_update_after() {
    proxy_manifest_file=$1
    proxy_manifest_path=$2
    proxy_manifest_after=$3
    proxy_manifest_tmp="$proxy_manifest_file.tmp.$$"
    while IFS='|' read -r proxy_path proxy_backup proxy_before proxy_mode proxy_uid proxy_gid proxy_after; do
        if [ "$proxy_path" = "$proxy_manifest_path" ]; then
            printf '%s|%s|%s|%s|%s|%s|%s\n' "$proxy_path" "$proxy_backup" "$proxy_before" "$proxy_mode" "$proxy_uid" "$proxy_gid" "$proxy_manifest_after"
        else
            printf '%s|%s|%s|%s|%s|%s|%s\n' "$proxy_path" "$proxy_backup" "$proxy_before" "$proxy_mode" "$proxy_uid" "$proxy_gid" "$proxy_after"
        fi
    done < "$proxy_manifest_file" > "$proxy_manifest_tmp"
    agh_sync
    agh_move "$proxy_manifest_tmp" "$proxy_manifest_file"
}

proxy_backup_file() {
    proxy_file=$1
    mkdir -p "$AGH_BACKUP_DIR/proxy"
    backup_path_name "$proxy_file"
    proxy_backup="$AGH_BACKUP_DIR/proxy/$BACKUP_NAME.orig"
    proxy_before=$(backup_hash "$proxy_file")
    backup_metadata "$proxy_file"
    cp -f "$proxy_file" "$proxy_backup" || return 1
    printf '%s|%s|%s|%s|%s|%s\n' "$proxy_file" "$proxy_backup" "$proxy_before" "$BACKUP_MODE" "$BACKUP_UID" "$BACKUP_GID" > "$AGH_BACKUP_DIR/proxy/$BACKUP_NAME.pending"
    PROXY_PENDING="$AGH_BACKUP_DIR/proxy/$BACKUP_NAME.pending"
}

proxy_modify_file() {
    proxy_file=$1
    proxy_dns_port=$(sed -n 's/^dns_port=//p' "$AGH_STATE_DIR/ports.conf" 2>/dev/null | sed -n '1p')
    valid_port "$proxy_dns_port" 2>/dev/null || proxy_dns_port=5591
    proxy_tmp="$proxy_file.agh.$$"
    sed -e 's/^[[:space:]]*enhanced-mode:.*/  enhanced-mode: redir-host/' -e "/^[[:space:]]*nameserver:/a\\    - 127.0.0.1:$proxy_dns_port" "$proxy_file" > "$proxy_tmp" || { rm -f "$proxy_tmp"; return 1; }
    agh_sync
    agh_move "$proxy_tmp" "$proxy_file" || return 1
    PROXY_AFTER=$(backup_hash "$proxy_file")
}

proxy_validate_file() {
    proxy_file=$1
    [ -f "$proxy_file" ] || return 1
    [ ! -L "$proxy_file" ] || return 1
    proxy_max=$(proxy_config_value max_file_bytes); [ -n "$proxy_max" ] || proxy_max=1048576
    proxy_size=$(wc -c < "$proxy_file")
    [ "$proxy_size" -le "$proxy_max" ] || return 1
    grep -q '^[[:space:]]*dns:' "$proxy_file" || return 1
    grep -q '^[[:space:]]*enhanced-mode:' "$proxy_file" || return 1
    grep -q '^[[:space:]]*nameserver:' "$proxy_file" || return 1
}

proxy_process_file() {
    proxy_file=$1
    proxy_allowed "$proxy_file" || return 1
    proxy_validate_file "$proxy_file" || return 1
    proxy_manifest_file="$AGH_BACKUP_DIR/proxy/manifest.tsv"
    if [ -f "$proxy_manifest_file" ] && proxy_hash_manifest_line "$proxy_manifest_file" "$proxy_file"; then
        proxy_current_hash=$(backup_hash "$proxy_file")
        proxy_path_name="$proxy_file"
        backup_path_name "$proxy_path_name"
        proxy_pending="$AGH_BACKUP_DIR/proxy/$BACKUP_NAME.pending"
        [ "$proxy_current_hash" = "$PROXY_MANIFEST_AFTER" ] && return 0
        if [ "$proxy_current_hash" = "$PROXY_MANIFEST_BEFORE" ]; then
            proxy_modify_file "$proxy_file" || return 1
            proxy_manifest_update_after "$proxy_manifest_file" "$proxy_file" "$PROXY_AFTER" || return 1
            return 0
        fi
        return 1
    fi
    proxy_backup_file "$proxy_file" || return 1
    proxy_modify_file "$proxy_file" || return 1
    proxy_pending_line=$(cat "$PROXY_PENDING")
    printf '%s|%s\n' "$proxy_pending_line" "$PROXY_AFTER" >> "$proxy_manifest_file"
    rm -f "$PROXY_PENDING"
}

proxy_clean() {
    proxy_manifest_file="$AGH_BACKUP_DIR/proxy/manifest.tsv"
    [ -f "$proxy_manifest_file" ] || { proxy_state_write ready nothing_to_restore; return 0; }
    proxy_restore_warning=0
    while IFS='|' read -r proxy_file proxy_backup proxy_before proxy_mode proxy_uid proxy_gid proxy_after; do
        [ -n "$proxy_file" ] || continue
        proxy_current_hash=$(backup_hash "$proxy_file")
        if [ "$proxy_current_hash" = "$proxy_after" ]; then
            atomic_copy "$proxy_backup" "$proxy_file" || proxy_restore_warning=1
            backup_restore_metadata "$proxy_file" "$proxy_mode" "$proxy_uid" "$proxy_gid"
        else
            proxy_restore_warning=1
        fi
    done < "$proxy_manifest_file"
    if [ "$proxy_restore_warning" -eq 1 ]; then
        proxy_state_write warning user_modified_or_restore_failed
        return 1
    fi
    proxy_state_write ready restored
    return 0
}

proxy_once() {
    ensure_dirs || return 1
    if [ "$(proxy_config_value enabled)" != true ]; then
        proxy_state_write disabled disabled
        return 0
    fi
    proxy_files=$(sed -n 's/^file=//p' "$AGH_CONFIG_DIR/proxy-adapter.conf")
    [ -n "$proxy_files" ] || { proxy_state_write ready no_targets; return 0; }
    for proxy_file in $proxy_files; do
        proxy_process_file "$proxy_file" || { proxy_state_write failed "$proxy_file"; return 1; }
    done
    proxy_state_write ready ready
}

case "${1:-once}" in
    once) proxy_once ;;
    daemon) while [ ! -f "$AGH_RUN_DIR/stop" ]; do proxy_once || true; sleep 5; done ;;
    --clean|clean|restore) proxy_clean ;;
    stop) proxy_clean ;;
    *) printf 'usage: %s {once|daemon|--clean|stop}\n' "$0" >&2; exit 2 ;;
esac
