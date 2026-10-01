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
    file_target_parse "$1" || return 1
    printf '%s\n' "$FILE_TARGET_PACKAGE"
}

# Android may expose either /data/data -> /data/user/0 or the reverse. Only
# this system-owned primary-user alias is accepted; app-controlled links are not.
file_data_root_init() {
    FILE_DATA_ROOT=${AGH_FILE_DATA_ROOT:-/data}
    file_path_syntax "$FILE_DATA_ROOT" || return 1
    file_no_symlink_ancestors "$FILE_DATA_ROOT" || return 1
    FILE_PRIMARY_ROOT="$FILE_DATA_ROOT/user/0"
    if [ -L "$FILE_PRIMARY_ROOT" ]; then
        [ "$(readlink -f "$FILE_PRIMARY_ROOT" 2>/dev/null)" = "$FILE_DATA_ROOT/data" ] || return 1
        FILE_PRIMARY_ROOT="$FILE_DATA_ROOT/data"
    elif [ ! -d "$FILE_PRIMARY_ROOT" ] && [ -d "$FILE_DATA_ROOT/data" ]; then
        FILE_PRIMARY_ROOT="$FILE_DATA_ROOT/data"
    fi
    file_no_symlink_ancestors "$FILE_PRIMARY_ROOT" || return 1
    FILE_USER_IDS=$({
        printf '0\n'
        for file_user_dir in "$FILE_DATA_ROOT"/user/* "$FILE_DATA_ROOT"/media/*; do
            [ -d "$file_user_dir" ] || continue
            file_user_id=${file_user_dir##*/}
            file_user_id_valid "$file_user_id" && printf '%s\n' "$file_user_id"
        done
    } | sort -u)
}

file_expand_targets() {
    file_target_parse "$1" || return 1
    file_expand_scope=$FILE_TARGET_SCOPE
    file_expand_package=$FILE_TARGET_PACKAGE
    file_expand_relative=$FILE_TARGET_RELATIVE
    file_expand_ids=$FILE_TARGET_USER
    # Legacy primary-user paths are templates for installed Android profiles.
    # An explicit /data/user/<id> always refers only to that user.
    if [ "$FILE_TARGET_LEGACY" = 1 ] || { [ "$FILE_TARGET_SCOPE" != user ] && [ "$FILE_TARGET_USER" = 0 ]; }; then
        file_expand_ids=$FILE_USER_IDS
    fi
    for file_expand_id in $file_expand_ids; do
        case "$file_expand_scope" in
            user)
                if [ "$file_expand_id" = 0 ]; then
                    printf '%s/%s/%s\n' "$FILE_PRIMARY_ROOT" "$file_expand_package" "$file_expand_relative"
                else
                    printf '%s/user/%s/%s/%s\n' "$FILE_DATA_ROOT" "$file_expand_id" "$file_expand_package" "$file_expand_relative"
                fi
                ;;
            media-android) printf '%s/media/%s/Android/data/%s/%s\n' "$FILE_DATA_ROOT" "$file_expand_id" "$file_expand_package" "$file_expand_relative" ;;
            media-direct) printf '%s/media/%s/%s/%s\n' "$FILE_DATA_ROOT" "$file_expand_id" "$file_expand_package" "$file_expand_relative" ;;
        esac
    done
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
    awk -F'|' 'NF && !seen[$1]++' "$file_manifest_file" > "$file_manifest_tmp" || return 1
    agh_sync
    agh_move "$file_manifest_tmp" "$file_manifest_file"
}

file_manifest_path() {
    backup_path_name "$1"
    FILE_BACKUP_DIR="$AGH_BACKUP_DIR/file/$BACKUP_NAME"
    FILE_MANIFEST="$AGH_BACKUP_DIR/file/manifest.tsv"
}

file_primary_path() {
    case "$1" in
        "$FILE_DATA_ROOT/data/"*) printf '%s/%s\n' "$FILE_PRIMARY_ROOT" "${1#"$FILE_DATA_ROOT/data/"}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

file_safe_target() {
    case "$1" in "$FILE_DATA_ROOT"/*) ;; *) return 1 ;; esac
    file_logical_path="/data${1#"$FILE_DATA_ROOT"}"
    file_policy_allowed "$file_logical_path" "$2" "${3:-once}" || return 1
    file_no_symlink_ancestors "$1"
}

file_manifest_recorded() {
    [ -f "$1" ] || return 1
    while IFS='|' read -r file_record_path FILE_RECORDED_BACKUP FILE_RECORDED_BEFORE FILE_RECORDED_TYPE FILE_RECORDED_MODE FILE_RECORDED_UID FILE_RECORDED_GID FILE_RECORDED_AFTER; do
        if [ "$(file_primary_path "$file_record_path")" = "$2" ]; then
            FILE_RECORDED_PATH=$file_record_path
            return 0
        fi
    done < "$1"
    return 1
}

file_empty_hash() {
    if [ "$1" = directory ]; then printf 'directory|.\n'; fi | sha256sum | cut -d ' ' -f1
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
    mkdir -p "$AGH_BACKUP_DIR/file" || return 1
    file_no_symlink_ancestors "$FILE_BACKUP_DIR" || return 1
    [ ! -e "$FILE_BACKUP_DIR/content" ] || return 1
    mkdir -p "$FILE_BACKUP_DIR" || return 1
    backup_metadata "$file_target_path" || return 1
    FILE_BEFORE=$(backup_content_hash "$file_target_path" "$file_target_type") || return 1
    cp -pR "$file_target_path" "$FILE_BACKUP_DIR/content" || return 1
    [ "$(backup_content_hash "$FILE_BACKUP_DIR/content" "$file_target_type")" = "$FILE_BEFORE" ] || return 1
    [ "$(backup_content_hash "$file_target_path" "$file_target_type")" = "$FILE_BEFORE" ] || return 1
    file_after=$(file_empty_hash "$file_target_type") || return 1
    # Write-ahead record: a crash must not leave a cleared target without its backup.
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$file_target_path" "$FILE_BACKUP_DIR/content" "$FILE_BEFORE" "$file_target_type" "$BACKUP_MODE" "$BACKUP_UID" "$BACKUP_GID" "$file_after" >> "$FILE_MANIFEST" || return 1
    agh_sync
}

file_clear_target() {
    file_target_path=$1
    file_target_type=$2
    file_safe_target "$file_target_path" "$file_target_type" || return 1
    file_tree_safe "$file_target_path" "$file_target_type" || return 1
    if [ "$file_target_type" = directory ]; then
        (
            # Anchor removals in the checked directory, not app-writable ancestors.
            CDPATH= cd -P -- "$file_target_path" || exit 1
            [ "$(pwd -P)" = "$file_target_path" ] || exit 1
            file_tree_safe . directory || exit 1
            for file_child in ./* ./.[!.]* ./..?*; do
                [ -e "$file_child" ] || [ -L "$file_child" ] || continue
                rm -rf "$file_child" || exit 1
            done
        )
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
    file_rule_apply=${8:-once}
    file_target_state=${7:-active}
    [ -n "$file_target_id" ] || return 1
    [ "$file_target_state" = blocked ] && { FILE_TARGETS_BLOCKED=$((FILE_TARGETS_BLOCKED + 1)); return 0; }
    file_target_package=${file_target_package:-$(file_package_from_path "$file_target_path")}
    [ -n "$file_target_package" ] || return 1
    if [ -n "${FILE_PACKAGE_FILTER:-}" ] && [ "$file_target_package" != "$FILE_PACKAGE_FILTER" ]; then
        return 0
    fi
    FILE_TARGETS_TOTAL=$((FILE_TARGETS_TOTAL + 1))
    file_safe_target "$file_target_path" "$file_target_type" "$file_rule_apply" || return 1
    if [ ! -e "$file_target_path" ]; then
        FILE_TARGETS_MISSING=$((FILE_TARGETS_MISSING + 1))
        return 0
    fi
    file_tree_safe "$file_target_path" "$file_target_type" || return 1
    FILE_TARGETS_INSTALLED=$((FILE_TARGETS_INSTALLED + 1))
    file_manifest_path "$file_target_path"
    if file_manifest_recorded "$FILE_MANIFEST" "$file_target_path"; then
        [ "$FILE_RECORDED_TYPE" = "$file_target_type" ] || return 1
        file_current=$(file_record_hash "$file_target_path" "$file_target_type" "$FILE_RECORDED_PATH" "$FILE_RECORDED_AFTER") || return 1
        if [ "$file_current" = "$FILE_RECORDED_AFTER" ]; then return 0; fi
        FILE_TARGETS_CHANGED=$((FILE_TARGETS_CHANGED + 1))
        [ "$file_rule_apply" = repeat-cache ] || return 2
        [ "$FILE_RECORDED_AFTER" = "$(file_empty_hash "$file_target_type")" ] || return 2
        backup_path_name "$FILE_RECORDED_PATH"
        [ "$FILE_RECORDED_BACKUP" = "$AGH_BACKUP_DIR/file/$BACKUP_NAME/content" ] || return 1
        file_no_symlink_ancestors "$FILE_RECORDED_BACKUP" || return 1
        [ "$(backup_content_hash "$FILE_RECORDED_BACKUP" "$file_target_type")" = "$FILE_RECORDED_BEFORE" ] || return 1
        backup_metadata "$file_target_path" || return 1
        [ "$BACKUP_MODE:$BACKUP_UID:$BACKUP_GID" = "$FILE_RECORDED_MODE:$FILE_RECORDED_UID:$FILE_RECORDED_GID" ] || return 2
        # Keep the first backup. Regenerated dedicated caches never replace it.
        file_clear_target "$file_target_path" "$file_target_type" || return 1
        [ "$(backup_content_hash "$file_target_path" "$file_target_type")" = "$FILE_RECORDED_AFTER" ] || return 2
    else
        file_backup_target "$file_target_path" "$file_target_type" || return 1
        file_clear_target "$file_target_path" "$file_target_type" || return 1
        [ "$(backup_content_hash "$file_target_path" "$file_target_type")" = "$file_after" ] || return 2
    fi
    FILE_TARGETS_APPLIED=$((FILE_TARGETS_APPLIED + 1))
    return 0
}

file_record_hash() {
    if [ "$2" = directory ] && [ "$4" = "$(file_empty_hash file)" ]; then
        backup_legacy_directory_hash "$1" "$3"
    else
        backup_content_hash "$1" "$2"
    fi
}

file_restore_record() (
    file_saved_path=$1
    file_saved_backup=$2
    file_before=$3
    file_type=$4
    file_mode=$5
    file_uid=$6
    file_gid=$7
    file_after=$8
    case "$file_type" in file|directory) ;; *) return 1 ;; esac
    case "$file_mode" in ''|*[!0-7]*) return 1 ;; esac
    [ "${#file_mode}" -le 4 ] || return 1
    case "$file_uid" in ''|*[!0-9]*) return 1 ;; esac
    case "$file_gid" in ''|*[!0-9]*) return 1 ;; esac
    case "$file_before$file_after" in *[!0-9a-f]*) return 1 ;; esac
    [ "${#file_before}" = 64 ] && [ "${#file_after}" = 64 ] || return 1
    file_path=$file_saved_path
    case "$file_path" in "$FILE_DATA_ROOT/data/"*) file_path="$FILE_PRIMARY_ROOT/${file_path#"$FILE_DATA_ROOT/data/"}" ;; esac
    # Retained blocked provenance may be restored from a verified module backup,
    # but can never be selected for cleanup by any configured rule.
    file_safe_target "$file_path" "$file_type" restore || return 1
    file_tree_safe "$file_path" "$file_type" || return 1
    backup_metadata "$file_path" || return 1
    [ "$BACKUP_MODE:$BACKUP_UID:$BACKUP_GID" = "$file_mode:$file_uid:$file_gid" ] || return 1
    backup_path_name "$file_saved_path"
    [ "$file_saved_backup" = "$AGH_BACKUP_DIR/file/$BACKUP_NAME/content" ] || return 1
    file_no_symlink_ancestors "$file_saved_backup" || return 1
    file_tree_safe "$file_saved_backup" "$file_type" || return 1
    [ "$file_after" = "$(file_empty_hash "$file_type")" ] || {
        [ "$file_type" = directory ] && [ "$file_after" = "$(file_empty_hash file)" ] || return 1
    }
    [ "$(file_record_hash "$file_saved_backup" "$file_type" "$file_saved_path" "$file_after")" = "$file_before" ] || return 1
    file_current=$(file_record_hash "$file_path" "$file_type" "$file_saved_path" "$file_after") || return 1
    if [ "$file_current" != "$file_before" ]; then
        [ "$file_current" = "$file_after" ] || return 1
        # In v1, added empty directories also hashed as empty. Do not erase them.
        if [ "$file_type" = directory ]; then
            for file_child in "$file_path"/* "$file_path"/.[!.]* "$file_path"/..?*; do
                [ ! -e "$file_child" ] && [ ! -L "$file_child" ] || return 1
            done
            # BusyBox cp -nR source/. existing-dir can skip the whole directory.
            # Copy only individually absent children, retaining no-clobber.
            for file_child in "$file_saved_backup"/* "$file_saved_backup"/.[!.]* "$file_saved_backup"/..?*; do
                [ -e "$file_child" ] || continue
                file_destination="$file_path/${file_child##*/}"
                [ ! -e "$file_destination" ] && [ ! -L "$file_destination" ] || return 1
                cp -pnR "$file_child" "$file_destination" || return 1
            done
        else
            # Preserve the app's existing inode and SELinux label; no predictable
            # temporary file is created in an app-writable directory.
            file_tree_safe "$file_path" file || return 1
            cat "$file_saved_backup" > "$file_path" || return 1
        fi
        [ "$(file_record_hash "$file_path" "$file_type" "$file_saved_path" "$file_after")" = "$file_before" ] || return 1
    fi
    file_tree_safe "$file_path" "$file_type" || return 1
    backup_restore_metadata "$file_path" "$file_mode" "$file_uid" "$file_gid" || return 1
    if [ "$FILE_DATA_ROOT" = /data ]; then
        /system/bin/restorecon -RF "$file_path" 2>/dev/null || return 1
    fi
)

file_clean() {
    file_manifest="$AGH_BACKUP_DIR/file/manifest.tsv"
    [ -f "$file_manifest" ] || { file_state_write ready nothing_to_restore; return 0; }
    file_manifest_compact "$file_manifest" || return 1
    file_restore_warning=0
    file_restore_remaining="$file_manifest.remaining.$$"
    file_restore_retired="$file_manifest.retired.$$"
    : > "$file_restore_remaining" || return 1
    : > "$file_restore_retired" || return 1
    while IFS= read -r file_record_line || [ -n "$file_record_line" ]; do
        [ -n "$file_record_line" ] || continue
        # Do not perform shell evaluation or word splitting on manifest content.
        if (IFS='|'; read -r file_path file_backup file_before file_type file_mode file_uid file_gid file_after file_extra <<EOF
$file_record_line
EOF
            [ -z "$file_extra" ] && file_restore_record "$file_path" "$file_backup" "$file_before" "$file_type" "$file_mode" "$file_uid" "$file_gid" "$file_after"); then
            printf '%s\n' "$file_record_line" >> "$file_restore_retired"
        else
            printf '%s\n' "$file_record_line" >> "$file_restore_remaining"
            file_restore_warning=1
        fi
    done < "$file_manifest"
    agh_sync
    agh_move "$file_restore_remaining" "$file_manifest" || return 1
    # Retire successful records before deleting their module-owned backups.
    while IFS='|' read -r file_path file_backup _; do
        [ -n "$file_path" ] || continue
        file_no_symlink_ancestors "${file_backup%/content}" && rm -rf "${file_backup%/content}" || file_restore_warning=1
    done < "$file_restore_retired"
    rm -f "$file_restore_retired"
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
    sh "$SCRIPT_DIR/file-rules.sh" validate "$FILE_MANIFEST_PATH" || { file_state_write failed invalid_manifest; return 1; }
    mkdir -p "$AGH_BACKUP_DIR/file" || return 1
    file_manifest_compact "$AGH_BACKUP_DIR/file/manifest.tsv" || return 1
    file_warning=0
    while IFS='|' read -r file_id file_rule_path file_type file_risk file_restore_policy file_package file_state file_apply _ || [ -n "$file_id" ]; do
        case "$file_id" in ''|\#*) continue ;; esac
        if [ "$file_state" = blocked ]; then
            FILE_TARGETS_BLOCKED=$((FILE_TARGETS_BLOCKED + 1))
            continue
        fi
        if [ -n "$FILE_PACKAGE_FILTER" ] && [ "$file_package" != "$FILE_PACKAGE_FILTER" ]; then continue; fi
        file_targets=$(file_expand_targets "$file_rule_path") || return 1
        for file_target in $file_targets; do
            file_process_target "$file_id" "$file_target" "$file_type" "$file_risk" "$file_restore_policy" "$file_package" "$file_state" "${file_apply:-once}"
            file_result=$?
            case "$file_result" in
                0) ;;
                2) file_warning=1 ;;
                *) file_state_write failed "$file_id"; return 1 ;;
            esac
        done
    done < "$FILE_MANIFEST_PATH"
    if [ "$file_warning" -eq 1 ]; then
        file_state_write warning target_changed
    else
        file_state_write ready ready
    fi
    return 0
}

umask 077
ensure_dirs || exit 1
file_no_symlink_ancestors "$AGH_BACKUP_DIR/file/manifest.tsv" || { file_state_write failed unsafe_backup; exit 1; }
mkdir -p "$AGH_BACKUP_DIR/file" && agh_chmod 0700 "$AGH_BACKUP_DIR/file" || exit 1
# Serialize lifecycle/UI actions. Kernel locks release on exit/kill/reboot and
# are held only for one cycle, not the daemon's sleep. Missing flock fails closed.
file_locked() (
    file_no_symlink_ancestors "$AGH_RUN_DIR/file-adapter.lock" || return 1
    exec 9> "$AGH_RUN_DIR/file-adapter.lock" || return 1
    flock -n 9 || return 1
    file_data_root_init || { file_state_write failed unsafe_data_root; return 1; }
    "$@"
)

case "${1:-once}" in
    once) file_locked file_once "${2:-}" ;;
    daemon) while [ ! -f "$AGH_RUN_DIR/stop" ]; do file_locked file_once || true; sleep 5; done ;;
    --clean|clean|restore) file_locked file_clean ;;
    stop) file_locked file_clean ;;
    *) printf 'usage: %s {once [package]|daemon|--clean|stop}\n' "$0" >&2; exit 2 ;;
esac
