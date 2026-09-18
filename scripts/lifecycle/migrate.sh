#!/system/bin/sh

if [ -z "${MODDIR:-}" ]; then
    MODDIR=${0%/*}
fi

migration_source_mtime() {
    migration_stat=$1
    stat -c '%Y' "$migration_stat" 2>/dev/null || stat -f '%m' "$migration_stat" 2>/dev/null || printf '0\n'
}

migration_copy_filters() {
    migration_filter_source=$1
    migration_filter_destination=$2
    [ -d "$migration_filter_source" ] || return 0
    mkdir -p "$migration_filter_destination"
    cp -R "$migration_filter_source"/. "$migration_filter_destination"/ || return 1
    chmod -R u=rwX,go= "$migration_filter_destination" 2>/dev/null || true
}

migration_translate_proxy() {
    migration_prop=$1
    migration_destination=$2
    migration_proxy=$(sed -n 's/^PROXY_URL=//p' "$migration_prop" | sed -n '1p' | sed 's/^"//;s/"$//')
    [ -n "$migration_proxy" ] || return 0
    printf 'PROXY_URL=%s\n' "$migration_proxy" > "$migration_destination"
    chmod 0600 "$migration_destination"
}

migration_select_source() {
    migration_a_yaml=${LEGACY_MODULES_DIR:-/data/adb/modules}/AdGuardHome/AdGuardHome.yaml
    migration_b_yaml=${AGH_ROOT:-/data/adb/agh}/bin/AdGuardHome.yaml
    MIGRATION_SOURCE_YAML=
    MIGRATION_SOURCE_MODE=
    MIGRATION_SOURCE_FILTERS=
    MIGRATION_SOURCE_PROXY=
    migration_a_valid=0
    migration_b_valid=0
    [ -f "$migration_a_yaml" ] && validate_agh_yaml "$migration_a_yaml" && migration_a_valid=1
    [ -f "$migration_b_yaml" ] && validate_agh_yaml "$migration_b_yaml" && migration_b_valid=1
    if [ "$migration_a_valid" -eq 1 ] && [ "$migration_b_valid" -eq 1 ]; then
        migration_a_mtime=$(migration_source_mtime "$migration_a_yaml")
        migration_b_mtime=$(migration_source_mtime "$migration_b_yaml")
        if [ "$migration_b_mtime" -ge "$migration_a_mtime" ]; then
            MIGRATION_SOURCE_YAML=$migration_b_yaml
            MIGRATION_SOURCE_MODE=${AGH_ROOT:-/data/adb/agh}/scripts/config.prop
            MIGRATION_SOURCE_FILTERS=${AGH_ROOT:-/data/adb/agh}/bin/data/filters
            MIGRATION_SOURCE_PROXY=${AGH_ROOT:-/data/adb/agh}/scripts/config.prop
        else
            MIGRATION_SOURCE_YAML=$migration_a_yaml
            MIGRATION_SOURCE_MODE=${LEGACY_MODULES_DIR:-/data/adb/modules}/AdGuardHome/mode.conf
            MIGRATION_SOURCE_FILTERS=${LEGACY_MODULES_DIR:-/data/adb/modules}/AdGuardHome/data/filters
        fi
    elif [ "$migration_a_valid" -eq 1 ]; then
        MIGRATION_SOURCE_YAML=$migration_a_yaml
        MIGRATION_SOURCE_MODE=${LEGACY_MODULES_DIR:-/data/adb/modules}/AdGuardHome/mode.conf
        MIGRATION_SOURCE_FILTERS=${LEGACY_MODULES_DIR:-/data/adb/modules}/AdGuardHome/data/filters
    elif [ "$migration_b_valid" -eq 1 ]; then
        MIGRATION_SOURCE_YAML=$migration_b_yaml
        MIGRATION_SOURCE_MODE=${AGH_ROOT:-/data/adb/agh}/scripts/config.prop
        MIGRATION_SOURCE_FILTERS=${AGH_ROOT:-/data/adb/agh}/bin/data/filters
        MIGRATION_SOURCE_PROXY=${AGH_ROOT:-/data/adb/agh}/scripts/config.prop
    else
        [ -d "${LEGACY_MODULES_DIR:-/data/adb/modules}/AdGuardHome" ] && return 2
        [ -d "${AGH_ROOT:-/data/adb/agh}/bin" ] && return 2
        return 1
    fi
    return 0
}

migrate_configs() {
    ensure_dirs
    if [ -f "$AGH_CONFIG_DIR/AdGuardHome.yaml" ]; then
        validate_agh_yaml "$AGH_CONFIG_DIR/AdGuardHome.yaml" || return 1
        [ -f "$AGH_CONFIG_DIR/mode.conf" ] || translate_legacy_mode /dev/null "$AGH_CONFIG_DIR/mode.conf"
        return 0
    fi

    migration_select_source
    migration_select_status=$?
    if [ "$migration_select_status" -eq 1 ]; then
        migration_tmp="$AGH_ROOT/.migration-default.$$"
        rm -rf "$migration_tmp"
        mkdir -p "$migration_tmp/config" "$migration_tmp/data/filters"
        write_default_config "${MODDIR:-.}/config/default.yaml" "$migration_tmp/config/AdGuardHome.yaml" || { rm -rf "$migration_tmp"; return 1; }
        translate_legacy_mode /dev/null "$migration_tmp/config/mode.conf"
        rmdir "$AGH_CONFIG_DIR" 2>/dev/null || { rm -rf "$migration_tmp"; return 1; }
        mv "$migration_tmp/config" "$AGH_CONFIG_DIR"
        mkdir -p "$AGH_DATA_DIR/filters"
        rm -rf "$migration_tmp"
        chmod 0700 "$AGH_CONFIG_DIR"
        return 0
    fi
    [ "$migration_select_status" -eq 0 ] || return 1

    migration_tmp="$AGH_ROOT/.migration-$$"
    migration_backup="$AGH_ROOT/.migration-backup-$$"
    rm -rf "$migration_tmp" "$migration_backup"
    mkdir -p "$migration_tmp/config" "$migration_tmp/data/filters"
    cp "$MIGRATION_SOURCE_YAML" "$migration_tmp/config/AdGuardHome.yaml" || { rm -rf "$migration_tmp"; return 1; }
    validate_agh_yaml "$migration_tmp/config/AdGuardHome.yaml" || { rm -rf "$migration_tmp"; return 1; }
    if [ -f "$MIGRATION_SOURCE_MODE" ]; then
        translate_legacy_mode "$MIGRATION_SOURCE_MODE" "$migration_tmp/config/mode.conf" || { rm -rf "$migration_tmp"; return 1; }
    else
        translate_legacy_mode /dev/null "$migration_tmp/config/mode.conf"
    fi
    if [ -n "$MIGRATION_SOURCE_PROXY" ] && [ -f "$MIGRATION_SOURCE_PROXY" ]; then
        migration_translate_proxy "$MIGRATION_SOURCE_PROXY" "$migration_tmp/config/proxy-adapter.conf" || { rm -rf "$migration_tmp"; return 1; }
    fi
    migration_copy_filters "$MIGRATION_SOURCE_FILTERS" "$migration_tmp/data/filters" || { rm -rf "$migration_tmp"; return 1; }

    if [ -d "$AGH_CONFIG_DIR" ]; then
        mv "$AGH_CONFIG_DIR" "$migration_backup" || { rm -rf "$migration_tmp"; return 1; }
    fi
    if ! mv "$migration_tmp/config" "$AGH_CONFIG_DIR"; then
        rm -rf "$migration_tmp"
        [ -d "$migration_backup" ] && mv "$migration_backup" "$AGH_CONFIG_DIR"
        return 1
    fi
    mkdir -p "$AGH_DATA_DIR"
    if [ -d "$migration_tmp/data/filters" ]; then
        if ! mv "$migration_tmp/data/filters" "$AGH_DATA_DIR/filters"; then
            rm -rf "$AGH_CONFIG_DIR"
            [ -d "$migration_backup" ] && mv "$migration_backup" "$AGH_CONFIG_DIR"
            rm -rf "$migration_tmp"
            return 1
        fi
    fi
    rm -rf "$migration_tmp" "$migration_backup"
    chmod 0700 "$AGH_CONFIG_DIR" "$AGH_DATA_DIR"
    atomic_write "$AGH_STATE_DIR/migration.source" "${MIGRATION_SOURCE_YAML}\n"
    chmod 0600 "$AGH_STATE_DIR/migration.source"
    return 0
}
