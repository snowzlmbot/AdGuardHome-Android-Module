#!/system/bin/sh

install_runtime_defaults() {
    config_module_root=${MODDIR:-.}
    mkdir -p "$AGH_CONFIG_DIR" || return 1
    for config_name in proxy-adapter.conf file-adapter.conf; do
        if [ ! -f "$AGH_CONFIG_DIR/$config_name" ]; then
            atomic_copy "$config_module_root/config/$config_name" "$AGH_CONFIG_DIR/$config_name" || return 1
        fi
        chmod 0600 "$AGH_CONFIG_DIR/$config_name"
    done
    if [ ! -f "$AGH_CONFIG_DIR/mode.conf" ]; then
        atomic_copy "$config_module_root/config/mode.conf" "$AGH_CONFIG_DIR/mode.conf" || return 1
    fi
    for config_key in mode I_network Lock_sleep port_testing redirect_ipv4_dns redirect_ipv6_dns block_ipv4_dot block_ipv6_dot block_ipv4_doq block_ipv6_doq bypass_vpn_dns bypass_vpn_encrypted_dns bypass_vpn_traffic lan_dns_target bootstrap_dns; do
        if ! grep -q "^${config_key}=" "$AGH_CONFIG_DIR/mode.conf"; then
            config_default_line=$(sed -n "/^${config_key}=/p" "$config_module_root/config/mode.conf" | sed -n '1p')
            [ -n "$config_default_line" ] || return 1
            printf '%s\n' "$config_default_line" >> "$AGH_CONFIG_DIR/mode.conf" || return 1
        fi
    done
    chmod 0600 "$AGH_CONFIG_DIR/mode.conf"
}

config_value() {
    config_file=$1
    config_key=$2
    sed -n "s/^${config_key}=//p" "$config_file" | sed -n '1p'
}

validate_agh_yaml() {
    config_yaml=$1
    [ -s "$config_yaml" ] || return 1
    grep -q '^http:' "$config_yaml" || return 1
    grep -q '^dns:' "$config_yaml" || return 1
    grep -q '^[[:space:]]*address:' "$config_yaml" || return 1
    grep -q '^[[:space:]]*port:' "$config_yaml" || return 1
    grep -q '^[[:space:]]*upstream_dns:' "$config_yaml" || return 1
    ! grep -n '^[[:space:]]*$' /dev/null >/dev/null 2>&1
}

write_default_config() {
    config_default=${1:-${MODDIR:-.}/config/default.yaml}
    config_destination=${2:?destination required}
    [ -f "$config_default" ] || return 1
    validate_agh_yaml "$config_default" || return 1
    mkdir -p "${config_destination%/*}"
    cp "$config_default" "$config_destination"
    chmod 0600 "$config_destination"
}

translate_legacy_mode() {
    legacy_file=$1
    mode_destination=$2
    mode_value=2
    network_value=0
    sleep_value=0
    port_check_value=1
    if grep -q '^mode=' "$legacy_file"; then
        mode_value=$(sed -n 's/^mode=//p' "$legacy_file" | sed -n '1p')
        network_value=$(sed -n 's/^I_network=//p' "$legacy_file" | sed -n '1p')
        sleep_value=$(sed -n 's/^Lock_sleep=//p' "$legacy_file" | sed -n '1p')
        port_check_value=$(sed -n 's/^port_testing=//p' "$legacy_file" | sed -n '1p')
    fi
    {
        printf 'mode=%s\n' "$mode_value"
        printf 'I_network=%s\n' "${network_value:-0}"
        printf 'Lock_sleep=%s\n' "${sleep_value:-0}"
        printf 'port_testing=%s\n' "${port_check_value:-1}"
    } > "$mode_destination"
    chmod 0600 "$mode_destination"
}
