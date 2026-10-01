#!/system/bin/sh

backup_hash() {
    backup_hash_value=$(sha256sum "$1" 2>/dev/null) || return 1
    printf '%s\n' "${backup_hash_value%% *}"
}

backup_metadata() {
    BACKUP_MODE=$(stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null) || return 1
    BACKUP_UID=$(stat -c '%u' "$1" 2>/dev/null || stat -f '%u' "$1" 2>/dev/null) || return 1
    BACKUP_GID=$(stat -c '%g' "$1" 2>/dev/null || stat -f '%g' "$1" 2>/dev/null) || return 1
}

backup_restore_metadata() {
    chown "$3:$4" "$1" 2>/dev/null || return 1
    chmod "$2" "$1" 2>/dev/null || return 1
}

backup_path_name() {
    BACKUP_NAME=$(printf '%s' "$1" | sha256sum | cut -d ' ' -f1)
}

# Relative names and entry types make a backup comparable to its source and
# include empty directories. Missing/unreadable trees must not hash as empty.
backup_content_hash() {
    backup_content_path=$1
    if [ "$2" != directory ]; then
        [ -f "$backup_content_path" ] && [ ! -L "$backup_content_path" ] || return 1
        backup_hash "$backup_content_path"
        return $?
    fi
    [ -d "$backup_content_path" ] && [ ! -L "$backup_content_path" ] || return 1
    backup_entries=$(find "$backup_content_path" -print 2>/dev/null) || return 1
    backup_tree=$(printf '%s\n' "$backup_entries" | LC_ALL=C sort | while IFS= read -r backup_entry; do
        if [ "$backup_entry" = "$backup_content_path" ]; then
            printf 'directory|.\n'
        elif [ -d "$backup_entry" ] && [ ! -L "$backup_entry" ]; then
            printf 'directory|%s\n' "${backup_entry#"$backup_content_path"/}"
        elif [ -f "$backup_entry" ] && [ ! -L "$backup_entry" ]; then
            backup_entry_hash=$(backup_hash "$backup_entry") || exit 1
            printf 'file|%s|%s\n' "${backup_entry#"$backup_content_path"/}" "$backup_entry_hash"
        else
            exit 1
        fi
    done) || return 1
    printf '%s\n' "$backup_tree" | sha256sum | cut -d ' ' -f1
}

# Compatibility for v1 directory records, which hashed absolute names and did
# not include empty directories. The saved original path is used for both sides.
backup_legacy_directory_hash() {
    file_tree_safe "$1" directory || return 1
    backup_legacy_entries=$(find "$1" -type f -print 2>/dev/null) || return 1
    backup_legacy_tree=$(printf '%s\n' "$backup_legacy_entries" | LC_ALL=C sort | while IFS= read -r backup_legacy_file; do
        [ -n "$backup_legacy_file" ] || continue
        backup_legacy_digest=$(backup_hash "$backup_legacy_file") || exit 1
        printf '%s  %s/%s\n' "$backup_legacy_digest" "$2" "${backup_legacy_file#"$1"/}"
    done) || return 1
    if [ -n "$backup_legacy_tree" ]; then printf '%s\n' "$backup_legacy_tree"; fi | sha256sum | cut -d ' ' -f1
}

# Shared file-rule policy. Downloaded manifests select a subset of the bundled
# allowlist; a downloaded checksum is integrity evidence, not root authorization.
file_path_syntax() {
    case "$1" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        /|*[!A-Za-z0-9._/-]*|*..*|*//*|*/./*|*/.|*/) return 1 ;;
    esac
}

file_user_id_valid() {
    case "$1" in ''|*[!0-9]*|0[0-9]*) return 1 ;; esac
}

file_target_parse() {
    file_parse_path=$1
    file_path_syntax "$file_parse_path" || return 1
    FILE_TARGET_SCOPE=
    FILE_TARGET_USER=0
    FILE_TARGET_LEGACY=0
    case "$file_parse_path" in
        /data/data/*/*)
            FILE_TARGET_SCOPE=user
            FILE_TARGET_LEGACY=1
            file_parse_tail=${file_parse_path#/data/data/}
            ;;
        /data/user/*/*/*)
            FILE_TARGET_SCOPE=user
            file_parse_tail=${file_parse_path#/data/user/}
            FILE_TARGET_USER=${file_parse_tail%%/*}
            file_parse_tail=${file_parse_tail#*/}
            ;;
        /data/media/*/Android/data/*/*)
            FILE_TARGET_SCOPE=media-android
            file_parse_tail=${file_parse_path#/data/media/}
            FILE_TARGET_USER=${file_parse_tail%%/*}
            file_parse_tail=${file_parse_tail#*/}
            case "$file_parse_tail" in Android/data/*/*) ;; *) return 1 ;; esac
            file_parse_tail=${file_parse_tail#Android/data/}
            ;;
        /data/media/*/*/*)
            FILE_TARGET_SCOPE=media-direct
            file_parse_tail=${file_parse_path#/data/media/}
            FILE_TARGET_USER=${file_parse_tail%%/*}
            file_parse_tail=${file_parse_tail#*/}
            ;;
        *) return 1 ;;
    esac
    file_user_id_valid "$FILE_TARGET_USER" || return 1
    FILE_TARGET_PACKAGE=${file_parse_tail%%/*}
    FILE_TARGET_RELATIVE=${file_parse_tail#*/}
    case "$FILE_TARGET_PACKAGE" in ''|.*|*[!A-Za-z0-9._]*) return 1 ;; *.*) ;; *) return 1 ;; esac
    case "/$FILE_TARGET_RELATIVE/" in */databases/*|*/shared_prefs/*|*/MicroMsg/*) return 1 ;; esac
    case "$FILE_TARGET_RELATIVE" in files|cache|databases|shared_prefs) return 1 ;; esac
    FILE_TARGET_KEY="$FILE_TARGET_SCOPE/$FILE_TARGET_PACKAGE/$FILE_TARGET_RELATIVE"
    FILE_TARGET_CANONICAL="$FILE_TARGET_SCOPE/$FILE_TARGET_USER/$FILE_TARGET_PACKAGE/$FILE_TARGET_RELATIVE"
}

file_policy_key() {
    file_target_parse "$1" || return 1
    printf '%s\n' "$FILE_TARGET_KEY"
}

file_policy_allowed() {
    file_policy_path=$1
    file_policy_type=$2
    file_policy_apply=${3:-once}
    file_policy_wanted=$(file_policy_key "$file_policy_path") || return 1
    file_policy_package=${file_policy_wanted#*/}
    file_policy_package=${file_policy_package%%/*}
    while IFS='|' read -r file_allow_id file_allow_path file_allow_type file_allow_risk file_allow_restore file_allow_package file_allow_state file_allow_apply; do
        [ "$file_allow_package" = "$file_policy_package" ] || continue
        case "$file_allow_state:$file_policy_apply" in active:*|blocked:restore) ;; *) continue ;; esac
        [ "$file_allow_type" = "$file_policy_type" ] || continue
        file_allow_key=$(file_policy_key "$file_allow_path") || continue
        [ "$file_allow_key" = "$file_policy_wanted" ] || continue
        case "$file_policy_apply" in
            once|restore) return 0 ;;
            repeat-cache) [ "$file_allow_apply" = repeat-cache ] && return 0 ;;
        esac
    done < "$MODDIR/targets/file-ad-targets.conf"
    return 1
}

file_rule_validate() {
    case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
    case "$3" in file|directory) ;; *) return 1 ;; esac
    case "$4" in low|medium|high) ;; *) return 1 ;; esac
    [ "$5" = if-unchanged ] || return 1
    case "$7" in active|blocked) ;; *) return 1 ;; esac
    case "${8:-once}" in once|repeat-cache) ;; *) return 1 ;; esac
    [ -z "${9:-}" ] || return 1
    if [ "$7" = blocked ]; then
        case "$2" in /*) ;; *) return 1 ;; esac
        case "$2" in *..*|*//*|*/./*|*/.) return 1 ;; esac
        FILE_TARGET_CANONICAL=$2
        return 0
    fi
    file_target_parse "$2" || return 1
    [ "$6" = "$FILE_TARGET_PACKAGE" ] || return 1
    file_policy_allowed "$2" "$3" "${8:-once}"
}

file_no_symlink_ancestors() {
    # '.' is the already-opened directory used by anchored cache removal. Other
    # relative paths have no finite ancestor walk and are never authorized.
    case "$1" in .) return 0 ;; /*) ;; *) return 1 ;; esac
    file_ancestor=$1
    while [ -n "$file_ancestor" ]; do
        [ ! -L "$file_ancestor" ] || return 1
        file_ancestor=${file_ancestor%/*}
    done
}

# Refuse links, sockets/devices/FIFOs and hardlinks before copy/truncate/remove.
# The restricted entry names keep the POSIX newline-delimited fingerprint exact.
file_tree_safe() {
    file_tree_path=$1
    file_no_symlink_ancestors "$file_tree_path" || return 1
    if [ "$2" = file ]; then
        [ -f "$file_tree_path" ] || return 1
        [ "$(stat -c '%h' "$file_tree_path" 2>/dev/null)" = 1 ]
        return $?
    fi
    [ "$2" = directory ] && [ -d "$file_tree_path" ] || return 1
    file_tree_bad=$(find "$file_tree_path" ! -type d ! -type f -print 2>/dev/null) || return 1
    [ -z "$file_tree_bad" ] || return 1
    file_tree_bad=$(find "$file_tree_path" -type f -links +1 -print 2>/dev/null) || return 1
    [ -z "$file_tree_bad" ] || return 1
    file_tree_bad=$(find "$file_tree_path" -exec sh -c 'case "$1" in *[!A-Za-z0-9._/-]*) printf unsafe ;; esac' sh '{}' \; 2>/dev/null) || return 1
    [ -z "$file_tree_bad" ]
}
