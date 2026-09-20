#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/atomic.sh"
. "$MODULE_SCRIPTS_DIR/lib/log.sh"

FILE_RULES_MAX_BYTES=${FILE_RULES_MAX_BYTES:-524288}
FILE_RULES_RUNTIME_MANIFEST="$AGH_CONFIG_DIR/file-ad-targets.conf"
FILE_RULES_STATE="$AGH_STATE_DIR/file-rules.state"

file_rules_config_value() {
    file_rules_key=$1
    sed -n "s/^${file_rules_key}=//p" "$AGH_CONFIG_DIR/file-adapter.conf" 2>/dev/null | sed -n '1p'
}

file_rules_default_url() {
    printf '%s\n' 'https://raw.githubusercontent.com/snowzlmbot/AdGuardHome-Android-Module/main/module/targets/file-ad-targets.conf'
}

file_rules_default_sha_url() {
    printf '%s\n' 'https://raw.githubusercontent.com/snowzlmbot/AdGuardHome-Android-Module/main/module/targets/file-ad-targets.conf.sha256'
}

file_rules_download() {
    file_rules_url=$1
    file_rules_destination=$2
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 2 --connect-timeout 8 --max-time 90 "$file_rules_url" -o "$file_rules_destination"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$file_rules_destination" "$file_rules_url"
    else
        return 1
    fi
}

file_rules_validate() {
    file_rules_file=$1
    [ -s "$file_rules_file" ] || return 1
    file_rules_size=$(wc -c < "$file_rules_file" 2>/dev/null) || return 1
    [ "$file_rules_size" -le "$FILE_RULES_MAX_BYTES" ] || return 1
    file_rules_ids="$file_rules_file.ids.$$"
    file_rules_paths="$file_rules_file.paths.$$"
    : > "$file_rules_ids" || return 1
    : > "$file_rules_paths" || { rm -f "$file_rules_ids"; return 1; }
    file_rules_seen=0
    file_rules_failed=0
    while IFS='|' read -r file_rules_id file_rules_path file_rules_type file_rules_risk file_rules_restore file_rules_package file_rules_state; do
        case "$file_rules_id" in
            ''|\#*) continue ;;
        esac
        file_rules_seen=$((file_rules_seen + 1))
        case "$file_rules_id" in *[!A-Za-z0-9._-]*|*[!A-Za-z0-9._-]) file_rules_failed=1 ;; esac
        case "$file_rules_path" in /*) ;; *) file_rules_failed=1 ;; esac
        case "$file_rules_path" in *..*) file_rules_failed=1 ;; esac
        if [ "$file_rules_state" != blocked ]; then
            case "$file_rules_path" in */data/system/ifw|*/data/system/ifw/*|*/databases/*|*/shared_prefs/*|*/files) file_rules_failed=1 ;; esac
        fi
        case "$file_rules_type" in file|directory) ;; *) file_rules_failed=1 ;; esac
        case "$file_rules_risk" in low|medium|high) ;; *) file_rules_failed=1 ;; esac
        case "$file_rules_restore" in if-unchanged) ;; *) file_rules_failed=1 ;; esac
        case "$file_rules_state" in active|blocked) ;; *) file_rules_failed=1 ;; esac
        if [ -n "$file_rules_package" ]; then
            case "$file_rules_package" in *[!A-Za-z0-9._-]*) file_rules_failed=1 ;; esac
        fi
        printf '%s\n' "$file_rules_id" >> "$file_rules_ids" || file_rules_failed=1
        printf '%s\n' "$file_rules_path" >> "$file_rules_paths" || file_rules_failed=1
    done < "$file_rules_file"
    [ "$file_rules_seen" -gt 0 ] || file_rules_failed=1
    [ -z "$(sort "$file_rules_ids" | uniq -d)" ] || file_rules_failed=1
    [ -z "$(sort "$file_rules_paths" | uniq -d)" ] || file_rules_failed=1
    rm -f "$file_rules_ids" "$file_rules_paths"
    [ "$file_rules_failed" -eq 0 ]
}

file_rules_state_write() {
    file_rules_state_value=$1
    file_rules_state_reason=${2:-}
    file_rules_state_tmp="$AGH_STATE_DIR/.file-rules.state.$$"
    {
        agh_printf 'state=%s\n' "$file_rules_state_value"
        agh_printf 'reason=%s\n' "$file_rules_state_reason"
        agh_printf 'manifest=%s\n' "$FILE_RULES_RUNTIME_MANIFEST"
        agh_printf 'updated=%s\n' "${FILE_RULES_UPDATED:-unknown}"
        agh_printf 'sha256=%s\n' "${FILE_RULES_SHA256:-unknown}"
    } > "$file_rules_state_tmp" || return 1
    agh_chmod 0600 "$file_rules_state_tmp" 2>/dev/null || true
    agh_sync
    agh_move "$file_rules_state_tmp" "$FILE_RULES_STATE"
}

file_rules_refresh() {
    ensure_dirs || return 1
    file_rules_url=$(file_rules_config_value rules_url)
    [ -n "$file_rules_url" ] || file_rules_url=$(file_rules_default_url)
    file_rules_sha_url=$(file_rules_config_value rules_sha256_url)
    [ -n "$file_rules_sha_url" ] || file_rules_sha_url=$(file_rules_default_sha_url)
    file_rules_tmp="$AGH_CONFIG_DIR/.file-ad-targets.conf.$$"
    file_rules_sha_tmp="$AGH_CONFIG_DIR/.file-ad-targets.conf.sha256.$$"
    file_rules_download "$file_rules_url" "$file_rules_tmp" || { rm -f "$file_rules_tmp" "$file_rules_sha_tmp"; file_rules_state_write failed download; return 1; }
    file_rules_download "$file_rules_sha_url" "$file_rules_sha_tmp" || { rm -f "$file_rules_tmp" "$file_rules_sha_tmp"; file_rules_state_write failed checksum_download; return 1; }
    file_rules_validate "$file_rules_tmp" || { rm -f "$file_rules_tmp" "$file_rules_sha_tmp"; file_rules_state_write failed validation; return 1; }
    FILE_RULES_SHA256=$(sha256sum "$file_rules_tmp" 2>/dev/null | cut -d ' ' -f1)
    FILE_RULES_EXPECTED=$(sed -n '1{s/[[:space:]].*//;p;}' "$file_rules_sha_tmp")
    [ -n "$FILE_RULES_EXPECTED" ] && [ "$FILE_RULES_SHA256" = "$FILE_RULES_EXPECTED" ] || { rm -f "$file_rules_tmp" "$file_rules_sha_tmp"; file_rules_state_write failed checksum_mismatch; return 1; }
    if [ -f "$FILE_RULES_RUNTIME_MANIFEST" ]; then
        mkdir -p "$AGH_BACKUP_DIR/file/rules"
        file_rules_backup="$AGH_BACKUP_DIR/file/rules/file-ad-targets-$(date '+%Y%m%d-%H%M%S' 2>/dev/null || printf manual).conf"
        cp -f "$FILE_RULES_RUNTIME_MANIFEST" "$file_rules_backup" 2>/dev/null || true
    fi
    agh_sync
    agh_move "$file_rules_tmp" "$FILE_RULES_RUNTIME_MANIFEST" || { rm -f "$file_rules_sha_tmp"; file_rules_state_write failed install; return 1; }
    rm -f "$file_rules_sha_tmp"
    FILE_RULES_UPDATED=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || printf unknown)
    file_rules_state_write ready updated
    log_message file_rules "updated maintainer file-ad rules"
}

file_rules_status() {
    if [ -f "$FILE_RULES_STATE" ]; then
        cat "$FILE_RULES_STATE"
    else
        agh_printf 'state=baseline\nmanifest=%s\n' "$FILE_RULES_RUNTIME_MANIFEST"
    fi
}

case "${1:-status}" in
    refresh|update) file_rules_refresh ;;
    status) file_rules_status ;;
    validate) file_rules_validate "${2:?manifest required}" ;;
    *) printf 'usage: %s {refresh|status|validate manifest}\n' "$0" >&2; exit 2 ;;
esac
