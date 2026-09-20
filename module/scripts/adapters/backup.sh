#!/system/bin/sh

backup_hash() {
    backup_hash_file=$1
    sha256sum "$backup_hash_file" 2>/dev/null | cut -d ' ' -f1
}

backup_metadata() {
    backup_metadata_file=$1
    backup_mode=$(stat -c '%a' "$backup_metadata_file" 2>/dev/null || stat -f '%Lp' "$backup_metadata_file" 2>/dev/null || printf '600')
    backup_uid=$(stat -c '%u' "$backup_metadata_file" 2>/dev/null || stat -f '%u' "$backup_metadata_file" 2>/dev/null || printf '0')
    backup_gid=$(stat -c '%g' "$backup_metadata_file" 2>/dev/null || stat -f '%g' "$backup_metadata_file" 2>/dev/null || printf '0')
    BACKUP_MODE=$backup_mode
    BACKUP_UID=$backup_uid
    BACKUP_GID=$backup_gid
}

backup_restore_metadata() {
    backup_restore_file=$1
    backup_restore_mode=$2
    backup_restore_uid=$3
    backup_restore_gid=$4
    chmod "$backup_restore_mode" "$backup_restore_file" 2>/dev/null || true
    chown "$backup_restore_uid:$backup_restore_gid" "$backup_restore_file" 2>/dev/null || true
}

backup_path_name() {
    backup_input=$1
    BACKUP_NAME=$(printf '%s' "$backup_input" | sha256sum | cut -d ' ' -f1)
}

backup_content_hash() {
    backup_content_path=$1
    backup_content_type=$2
    if [ "$backup_content_type" = directory ]; then
        find "$backup_content_path" -type f -print 2>/dev/null | sort | while IFS= read -r backup_file; do
            sha256sum "$backup_file"
        done | sha256sum | cut -d ' ' -f1
    else
        backup_hash "$backup_content_path"
    fi
}
