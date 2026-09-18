#!/system/bin/sh

log_message() {
    log_component=${1:-module}
    shift
    log_text=$*
    log_file=${AGH_LOG_DIR:-/data/adb/agh/logs}/$log_component.log
    mkdir -p "${log_file%/*}"
    if [ -f "$log_file" ] && [ "$(wc -c < "$log_file" 2>/dev/null || printf 0)" -ge 262144 ]; then
        mv -f "$log_file" "$log_file.1" 2>/dev/null || :
    fi
    printf '%s [%s] %s\n' "$(date '+%F %T')" "$log_component" "$log_text" >> "$log_file"
}
