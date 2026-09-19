#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/atomic.sh"
. "$MODULE_SCRIPTS_DIR/lib/log.sh"
. "$SCRIPT_DIR/backup.sh"

file_state_write() {
    file_state_value=$1
    file_state_reason=${2:-}
    file_state_tmp="$AGH_STATE_DIR/.file.state.$$"
    printf 'state=%s\nreason=%s\n' "$file_state_value" "$file_state_reason" > "$file_state_tmp"
    chmod 0600 "$file_state_tmp"
    sync
    mv -f "$file_state_tmp" "$AGH_STATE_DIR/file.state"
}

file_config_value() {
    file_key=$1
    sed -n "s/^${file_key}=//p" "$AGH_CONFIG_DIR/file-adapter.conf" 2>/dev/null | sed -n '1p'
}

file_manifest_path() {
    file_target_path=$1
    backup_path_name "$file_target_path"
    FILE_BACKUP_DIR="$AGH_BACKUP_DIR/file/$BACKUP_NAME"
    FILE_MANIFEST="$AGH_BACKUP_DIR/file/manifest.tsv"
}

file_safe_target() {
    file_candidate=$1
    case "$file_candidate" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$file_candidate" in
        *"/../"*|*"/.."|*"../"*|/data/system/ifw|/data/system/ifw/*|*/databases/*|*/shared_prefs/*|*/files) return 1 ;;
    esac
    [ ! -L "$file_candidate" ] || return 1
    return 0
}

file_backup_target() {
    file_target_path=$1
    file_target_type=$2
    file_manifest_path "$file_target_path"
    file_max_backup=$(file_config_value max_backup_bytes)
    case "$file_max_backup" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$file_target_type" = directory ]; then
        file_backup_size_kb=$(du -sk "$file_target_path" 2>/dev/null | awk '{print $1}')
        case "$file_backup_size_kb" in ''|*[!0-9]*) return 1 ;; esac
        file_backup_size=$((file_backup_size_kb * 1024))
    else
        file_backup_size=$(wc -c < "$file_target_path" 2>/dev/null) || return 1
    fi
    [ "$file_backup_size" -le "$file_max_backup" ] || return 1
    mkdir -p "$FILE_BACKUP_DIR" "$AGH_BACKUP_DIR/file"
    backup_metadata "$file_target_path"
    FILE_BEFORE=$(backup_content_hash "$file_target_path" "$file_target_type")
    if [ "$file_target_type" = directory ]; then
        cp -R "$file_target_path" "$FILE_BACKUP_DIR/content" || return 1
    else
        cp -f "$file_target_path" "$FILE_BACKUP_DIR/content" || return 1
    fi
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$file_target_path" "$FILE_BACKUP_DIR/content" "$FILE_BEFORE" "$file_target_type" "$BACKUP_MODE" "$BACKUP_UID" "$BACKUP_GID" pending > "$FILE_BACKUP_DIR/pending"
}

file_clear_target() {
    file_target_path=$1
    file_target_type=$2
    if [ "$file_target_type" = directory ]; then
        for file_child in "$file_target_path"/* "$file_target_path"/.[!.]* "$file_target_path"/..?*; do
            [ -e "$file_child" ] || continue
            rm -rf "$file_child" || return 1
        done
        mkdir -p "$file_target_path"
    else
        : > "$file_target_path" || return 1
    fi
}

file_process_target() {
    file_target_id=$1
    file_target_path=$2
    file_target_type=$3
    file_target_risk=$4
    file_target_restore=$5
    [ -n "$file_target_id" ] || return 1
    file_safe_target "$file_target_path" || return 1
    [ -e "$file_target_path" ] || return 0
    case "$file_target_type" in file) [ -f "$file_target_path" ] || return 1 ;; directory) [ -d "$file_target_path" ] || return 1 ;; *) return 1 ;; esac
    file_backup_target "$file_target_path" "$file_target_type" || return 1
    file_clear_target "$file_target_path" "$file_target_type" || return 1
    file_after=$(backup_content_hash "$file_target_path" "$file_target_type")
    file_pending_line=$(sed "s/|pending$/|$file_after/" "$FILE_BACKUP_DIR/pending")
    printf '%s\n' "$file_pending_line" >> "$FILE_MANIFEST"
    rm -f "$FILE_BACKUP_DIR/pending"
}

file_clean() {
    file_manifest="$AGH_BACKUP_DIR/file/manifest.tsv"
    [ -f "$file_manifest" ] || { file_state_write ready nothing_to_restore; return 0; }
    file_restore_warning=0
    while IFS='|' read -r file_path file_backup file_before file_type file_mode file_uid file_gid file_after; do
        [ -n "$file_path" ] || continue
        file_current=$(backup_content_hash "$file_path" "$file_type")
        if [ "$file_current" = "$file_after" ]; then
            if [ "$file_type" = directory ]; then
                for file_child in "$file_path"/* "$file_path"/.[!.]* "$file_path"/..?*; do
                    [ -e "$file_child" ] || continue
                    rm -rf "$file_child" || file_restore_warning=1
                done
                cp -R "$file_backup"/. "$file_path"/ || file_restore_warning=1
            else
                atomic_copy "$file_backup" "$file_path" || file_restore_warning=1
            fi
            backup_restore_metadata "$file_path" "$file_mode" "$file_uid" "$file_gid"
        else
            file_restore_warning=1
        fi
    done < "$file_manifest"
    if [ "$file_restore_warning" -eq 1 ]; then file_state_write warning user_modified_or_restore_failed; else file_state_write ready restored; fi
    return 0
}

file_once() {
    ensure_dirs || return 1
    if [ "$(file_config_value enabled)" != true ]; then
        file_state_write disabled disabled
        return 0
    fi
    file_manifest=$(file_config_value target_manifest)
    [ -n "$file_manifest" ] || file_manifest="$MODDIR/targets/file-ad-targets.conf"
    case "$file_manifest" in /*) ;; *) file_manifest="$MODDIR/$file_manifest" ;; esac
    [ -f "$file_manifest" ] || { file_state_write failed missing_manifest; return 1; }
    mkdir -p "$AGH_BACKUP_DIR/file"
    while IFS='|' read -r file_id file_path file_type file_risk file_restore_policy; do
        case "$file_id" in ''|\#*) continue ;; esac
        file_process_target "$file_id" "$file_path" "$file_type" "$file_risk" "$file_restore_policy" || { file_state_write failed "$file_id"; return 1; }
    done < "$file_manifest"
    file_state_write ready ready
}

case "${1:-once}" in
    once) file_once ;;
    daemon) while [ ! -f "$AGH_RUN_DIR/stop" ]; do file_once || true; sleep 5; done ;;
    --clean|clean|restore) file_clean ;;
    stop) file_clean ;;
    *) printf 'usage: %s {once|daemon|--clean|stop}\n' "$0" >&2; exit 2 ;;
esac
