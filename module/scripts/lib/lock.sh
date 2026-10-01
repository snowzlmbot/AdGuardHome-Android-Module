#!/system/bin/sh
# Root-private portable cycle lock. Do not rely on an optional flock applet.
agh_lock_start() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'
}

agh_lock_acquire() {
    AGH_HELD_LOCK=$1
    agh_lock_wait=${2:-0}
    agh_lock_step=0
    AGH_LOCK_START=$(agh_lock_start "$$")
    [ -n "$AGH_LOCK_START" ] || return 1
    while ! mkdir "$AGH_HELD_LOCK" 2>/dev/null; do
        [ -d "$AGH_HELD_LOCK" ] && [ ! -L "$AGH_HELD_LOCK" ] || return 1
        agh_lock_owner=$(sed -n '1p' "$AGH_HELD_LOCK/owner" 2>/dev/null)
        if [ -z "$agh_lock_owner" ]; then
            sleep 1
            agh_lock_owner=$(sed -n '1p' "$AGH_HELD_LOCK/owner" 2>/dev/null)
        fi
        agh_lock_pid=${agh_lock_owner%%:*}
        agh_lock_birth=${agh_lock_owner#*:}
        agh_lock_actual=$(agh_lock_start "$agh_lock_pid")
        if [ -z "$agh_lock_actual" ] || [ "$agh_lock_actual" != "$agh_lock_birth" ]; then
            [ ! -L "$AGH_HELD_LOCK/owner" ] || return 1
            rm -f "$AGH_HELD_LOCK/owner"
            rmdir "$AGH_HELD_LOCK" 2>/dev/null || return 1
            continue
        fi
        [ "$agh_lock_step" -lt "$agh_lock_wait" ] || return 1
        sleep 1
        agh_lock_step=$((agh_lock_step + 1))
    done
    printf '%s:%s\n' "$$" "$AGH_LOCK_START" > "$AGH_HELD_LOCK/owner" || { rmdir "$AGH_HELD_LOCK"; return 1; }
}

agh_lock_release() {
    [ -n "${AGH_HELD_LOCK:-}" ] || return 0
    if [ "$(sed -n '1p' "$AGH_HELD_LOCK/owner" 2>/dev/null)" = "$$:$AGH_LOCK_START" ]; then
        rm -f "$AGH_HELD_LOCK/owner"
        rmdir "$AGH_HELD_LOCK" 2>/dev/null || true
    fi
}
