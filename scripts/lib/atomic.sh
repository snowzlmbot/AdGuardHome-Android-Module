#!/system/bin/sh

atomic_write() {
    atomic_target=$1
    atomic_value=$2
    atomic_dir=${atomic_target%/*}
    atomic_tmp="$atomic_dir/.$(basename "$atomic_target").tmp.$$"
    mkdir -p "$atomic_dir" || return 1
    umask 077
    printf '%s' "$atomic_value" > "$atomic_tmp" || {
        rm -f "$atomic_tmp"
        return 1
    }
    sync
    mv -f "$atomic_tmp" "$atomic_target" || {
        rm -f "$atomic_tmp"
        return 1
    }
}

atomic_copy() {
    atomic_source=$1
    atomic_target=$2
    atomic_dir=${atomic_target%/*}
    atomic_tmp="$atomic_dir/.$(basename "$atomic_target").tmp.$$"
    mkdir -p "$atomic_dir" || return 1
    cp -f "$atomic_source" "$atomic_tmp" || {
        rm -f "$atomic_tmp"
        return 1
    }
    sync
    mv -f "$atomic_tmp" "$atomic_target" || {
        rm -f "$atomic_tmp"
        return 1
    }
}
