#!/system/bin/sh

random_password() {
    credential_hex=$(od -An -N32 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    [ "${#credential_hex}" -ge 32 ] || return 1
    CREDENTIAL_PASSWORD=$(printf '%s' "$credential_hex" | cut -c1-32)
    export CREDENTIAL_PASSWORD
}

ensure_credentials() {
    credential_file=${1:-${AGH_STATE_DIR:-/data/adb/agh/state}/credentials.conf}
    mkdir -p "${credential_file%/*}" || return 1
    existing_user=$(sed -n 's/^username=//p' "$credential_file" 2>/dev/null | sed -n '1p')
    existing_password=$(sed -n 's/^password=//p' "$credential_file" 2>/dev/null | sed -n '1p')
    if [ -n "$existing_user" ] && [ -n "$existing_password" ]; then
        chmod 0600 "$credential_file"
        return 0
    fi
    random_password || return 1
    credential_tmp="$credential_file.tmp.$$"
    umask 077
    printf 'username=admin\npassword=%s\n' "$CREDENTIAL_PASSWORD" > "$credential_tmp" || return 1
    chmod 0600 "$credential_tmp"
    sync
    mv -f "$credential_tmp" "$credential_file" || return 1
    chmod 0600 "$credential_file"
    return 0
}

credential_value() {
    credential_key=${1:-}
    credential_file=${2:-${AGH_STATE_DIR:-/data/adb/agh/state}/credentials.conf}
    case "$credential_key" in
        username|password) sed -n "s/^${credential_key}=//p" "$credential_file" 2>/dev/null | sed -n '1p' ;;
        *) return 1 ;;
    esac
}
