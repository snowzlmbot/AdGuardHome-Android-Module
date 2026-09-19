#!/system/bin/sh

log_rotate_file() {
    log_target=$1
    log_limit=${2:-1048576}
    [ -f "$log_target" ] || return 0
    log_size=$(wc -c < "$log_target" 2>/dev/null || printf 0)
    [ "$log_size" -lt "$log_limit" ] && return 0
    rm -f "$log_target.3"
    [ ! -f "$log_target.2" ] || mv -f "$log_target.2" "$log_target.3"
    [ ! -f "$log_target.1" ] || mv -f "$log_target.1" "$log_target.2"
    mv -f "$log_target" "$log_target.1"
}

log_section() {
    log_section_component=$1
    shift
    log_section_file=${AGH_LOG_DIR:-/data/adb/agh/logs}/$log_section_component.log
    mkdir -p "${log_section_file%/*}"
    log_rotate_file "$log_section_file"
    printf '\n===== %s [%s] %s =====\n' "$(date '+%F %T %z')" "$log_section_component" "$*" >> "$log_section_file"
}

log_message() {
    log_component=${1:-module}
    shift
    log_text=$*
    log_file=${AGH_LOG_DIR:-/data/adb/agh/logs}/$log_component.log
    mkdir -p "${log_file%/*}"
    log_rotate_file "$log_file"
    printf '%s [%s] %s\n' "$(date '+%F %T %z')" "$log_component" "$log_text" >> "$log_file"
    if [ "$log_component" != events ]; then
        log_events=${AGH_LOG_DIR:-/data/adb/agh/logs}/events.log
        log_rotate_file "$log_events"
        printf '%s [%s] %s\n' "$(date '+%F %T %z')" "$log_component" "$log_text" >> "$log_events"
    fi
}
