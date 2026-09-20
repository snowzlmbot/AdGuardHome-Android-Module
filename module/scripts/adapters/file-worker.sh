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
    {
        agh_printf 'state=%s\n' "$file_state_value"
        agh_printf 'reason=%s\n' "$file_state_reason"
        agh_printf 'rules_state=%s\n' "${FILE_RULES_STATE:-unknown}"
        agh_printf 'rules_sha256=%s\n' "${FILE_RULES_SHA256:-unknown}"
        agh_printf 'package_filter=%s\n' "${FILE_PACKAGE_FILTER:-all}"
        agh_printf 'targets_total=%s\n' "${FILE_TARGETS_TOTAL:-0}"
        agh_printf 'targets_installed=%s\n' "${FILE_TARGETS_INSTALLED:-0}"
        agh_printf 'targets_applied=%s\n' "${FILE_TARGETS_APPLIED:-0}"
        agh_printf 'targets_missing=%s\n' "${FILE_TARGETS_MISSING:-0}"
        agh_printf 'targets_changed=%s\n' "${FILE_TARGETS_CHANGED:-0}"
        agh_printf 'targets_blocked=%s\n' "${FILE_TARGETS_BLOCKED:-0}"
    } > "$file_state_tmp" || return 1
    agh_chmod 0600 "$file_state_tmp" 2>/dev/null || true
    agh_sync
    agh_move "$file_state_tmp" "$AGH_STATE_DIR/file.state"
}

file_config_value() {
    file_key=$1
    sed -n "s/^${file_key}=//p" "$AGH_CONFIG_DIR/file-adapter.conf" 2>/dev/null | sed -n '1p'
}

file_package_from_path() {
    file_package_path=$1
    case "$file_package_path" in
        /data/data/*/*) printf '%s\n' "${file_package_path#/data/data/}" | cut -d/ -f1 ;;
        /data/media/*/Android/data/*/*) printf '%s\n' "${file_package_path#/data/media/}" | cut -d/ -f4 ;;
        /data/media/*/Android/data/*) printf '%s\n' "${file_package_path#/data/media/}" | cut -d/ -f4 ;;
        /data/media/*/*/*) printf '%s\n' "${file_package_path#/data/media/}" | cut -d/ -f2 ;;
        *) printf '%s\n' '' ;;
    esac
}

file_manifest_resolve() {
    file_manifest_setting=$(file_config_value target_manifest)
    if [ -f "$AGH_CONFIG_DIR/file-ad-targets.conf" ] && [ "$file_manifest_setting" = targets/file-ad-targets.conf ]; then
        FILE_MANIFEST_PATH="$AGH_CONFIG_DIR/file-ad-targets.conf"
    elif [ -n "$file_manifest_setting" ]; then
        case "$file_manifest_setting" in
            /*) FILE_MANIFEST_PATH="$file_manifest_setting" ;;
            *) FILE_MANIFEST_PATH="$MODDIR/$file_manifest_setting" ;;
        esac
    else
        FILE_MANIFEST_PATH="$MODDIR/targets/file-ad-targets.conf"
    fi
}

file_rules_state_load() {
    FILE_RULES_STATE=baseline
    FILE_RULES_SHA256=unknown
    if [ -f "$AGH_STATE_DIR/file-rules.state" ]; then
        FILE_RULES_STATE=$(sed -n 's/^state=//p' "$AGH_STATE_DIR/file-rules.state" | sed -n '1p')
        FILE_RULES_SHA256=$(sed -n 's/^sha256=//p' "$AGH_STATE_DIR/file-rules.state" | sed -n '1p')
    fi
}

file_manifest_compact() {
    file_manifest_file=$1
    [ -f "$file_manifest_file" ] || return 0
    file_manifest_tmp="$file_manifest_file.compact.$$"
    : > "$file_manifest_tmp" || return 1
    while IFS='|' read -r file_path _; do
        [ -n "$file_path" ] || continue
        grep -F "${file_path}|" "$file_manifest_tmp" >/dev/null 2>&1 && continue
        grep -F "${file_path}|" "$file_manifest_file" | sed -n '1p' >> "$file_manifest_tmp"
    done < "$file_manifest_file"
    agh_sync
    agh_move "$file_manifest_tmp" "$file_manifest_file"
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

file_manifest_recorded() {
    file_manifest_file=$1
    file_manifest_target=$2
    [ -f "$file_manifest_file" ] || return 1
    while IFS='|' read -r file_recorded_path _; do
        [ "$file_recorded_path" = "$file_manifest_target" ] && return 0
    done < "$file_manifest_file"
    return 1
}

file_backup_target() {
    file_target_path=$1
    file_target_type=$2
    file_manifest_path "$file_target_path"
    file_max_backup=$(file_config_value max_backup_bytes)
    case "$file_max_backup" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$file_target_type" = directory ]; then
        file_backup_size_kb=$(du -sk "$file_target_path" 2>/dev/null | cut -f1)
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
    file_target_package=${6:-}
    file_target_state=${7:-active}
    [ -n "$file_target_id" ] || return 1
    [ "$file_target_state" = blocked ] && { FILE_TARGETS_BLOCKED=$((FILE_TARGETS_BLOCKED + 1)); return 0; }
    file_target_package=${file_target_package:-$(file_package_from_path "$file_target_path")}
    if [ -n "${FILE_PACKAGE_FILTER:-}" ] && [ "$file_target_package" != "$FILE_PACKAGE_FILTER" ]; then
        return 0
    fi
    FILE_TARGETS_TOTAL=$((FILE_TARGETS_TOTAL + 1))
    file_safe_target "$file_target_path" || return 1
    if [ ! -e "$file_target_path" ]; then
        FILE_TARGETS_MISSING=$((FILE_TARGETS_MISSING + 1))
        return 0
    fi
    FILE_TARGETS_INSTALLED=$((FILE_TARGETS_INSTALLED + 1))
    file_manifest_path "$file_target_path"
    if file_manifest_recorded "$FILE_MANIFEST" "$file_target_path"; then
        file_current=$(backup_content_hash "$file_target_path" "$file_target_type")
        file_recorded_after=$(while IFS='|' read -r file_path _ _ _ _ _ _ file_after; do
            [ "$file_path" = "$file_target_path" ] && { printf '%s\n' "$file_after"; break; }
        done < "$FILE_MANIFEST")
        if [ -n "$file_recorded_after" ] && [ "$file_current" = "$file_recorded_after" ]; then
            return 0
        fi
        FILE_TARGETS_CHANGED=$((FILE_TARGETS_CHANGED + 1))
        return 2
    fi
    case "$file_target_type" in file) [ -f "$file_target_path" ] || return 1 ;; directory) [ -d "$file_target_path" ] || return 1 ;; *) return 1 ;; esac
    file_backup_target "$file_target_path" "$file_target_type" || return 1
    file_clear_target "$file_target_path" "$file_target_type" || return 1
    file_after=$(backup_content_hash "$file_target_path" "$file_target_type")
    file_pending_line=$(sed "s/|pending$/|$file_after/" "$FILE_BACKUP_DIR/pending")
    printf '%s\n' "$file_pending_line" >> "$FILE_MANIFEST"
    rm -f "$FILE_BACKUP_DIR/pending"
    FILE_TARGETS_APPLIED=$((FILE_TARGETS_APPLIED + 1))
    return 0
}

file_clean() {
    file_manifest="$AGH_BACKUP_DIR/file/manifest.tsv"
    [ -f "$file_manifest" ] || { file_state_write ready nothing_to_restore; return 0; }
    file_restore_warning=0
    while IFS='|' read -r file_path file_backup file_before file_type file_mode file_uid file_gid file_after; do
        [ -n "$file_path" ] || continue
        if [ -n "$file_last_path" ] && [ "$file_last_path" = "$file_path" ]; then
            continue
        fi
        file_last_path=$file_path
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
    if [ "$file_restore_warning" -eq 1 ]; then
        file_state_write warning user_modified_or_restore_failed
        return 1
    fi
    file_state_write ready restored
    return 0
}

file_once() {
    ensure_dirs || return 1
    FILE_PACKAGE_FILTER=${1:-}
    case "$FILE_PACKAGE_FILTER" in *[!A-Za-z0-9._-]*) file_state_write failed invalid_package; return 1 ;; esac
    FILE_TARGETS_TOTAL=0
    FILE_TARGETS_INSTALLED=0
    FILE_TARGETS_APPLIED=0
    FILE_TARGETS_MISSING=0
    FILE_TARGETS_CHANGED=0
    FILE_TARGETS_BLOCKED=0
    file_rules_state_load
    if [ "$(file_config_value enabled)" != true ] && [ "${FILE_FORCE_ONCE:-0}" != 1 ]; then
        file_state_write disabled disabled
        return 0
    fi
    file_manifest_resolve
    [ -f "$FILE_MANIFEST_PATH" ] || { file_state_write failed missing_manifest; return 1; }
    mkdir -p "$AGH_BACKUP_DIR/file"
    file_manifest_compact "$AGH_BACKUP_DIR/file/manifest.tsv" 2>/dev/null || true
    file_warning=0
    while IFS='|' read -r file_id file_path file_type file_risk file_restore_policy file_package file_state; do
        case "$file_id" in ''|\#*) continue ;; esac
        file_process_target "$file_id" "$file_path" "$file_type" "$file_risk" "$file_restore_policy" "$file_package" "$file_state"
        file_result=$?
        case "$file_result" in
            0) ;;
            2) file_warning=1 ;;
            *) file_state_write failed "$file_id"; return 1 ;;
        esac
    done < "$FILE_MANIFEST_PATH"
    if [ "$file_warning" -eq 1 ]; then
        file_state_write warning target_changed
    else
        file_state_write ready ready
    fi
    return 0
}

case "${1:-once}" in
    once) file_once "${2:-}" ;;
    daemon) while [ ! -f "$AGH_RUN_DIR/stop" ]; do file_once || true; sleep 5; done ;;
    --clean|clean|restore) file_clean ;;
    stop) file_clean ;;
    *) printf 'usage: %s {once [package]|daemon|--clean|stop}\n' "$0" >&2; exit 2 ;;
esac
