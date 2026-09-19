#!/system/bin/sh

install_choice() {
    install_prompt_zh=$1
    install_prompt_en=$2
    install_default=$3
    if [ "${INSTALL_NONINTERACTIVE:-0}" = 1 ]; then
        [ "$install_default" = true ]
        return
    fi
    i18n_ui_print "- $install_prompt_zh" "- $install_prompt_en"
    i18n_ui_print "  音量上 = 开启/选择，音量下 = 关闭/下一项" "  Volume Up = enable/select, Volume Down = disable/next"
    if command -v chooseport >/dev/null 2>&1; then
        chooseport
        return $?
    fi
    if command -v getevent >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
        install_event=$(timeout 8 getevent -ql 2>/dev/null | sed -n '/KEY_VOLUME/{p;q;}' || true)
        case "$install_event" in
            *KEY_VOLUMEUP*) return 0 ;;
            *KEY_VOLUMEDOWN*) return 1 ;;
        esac
    fi
    i18n_ui_print "  未检测到按键，使用默认值: $install_default" "  No key detected; using default: $install_default"
    [ "$install_default" = true ]
}

install_set_value() {
    install_file=$1
    install_key=$2
    install_value=$3
    install_tmp="$install_file.tmp.$$"
    if grep -q "^${install_key}=" "$install_file"; then
        sed "s#^${install_key}=.*#${install_key}=${install_value}#" "$install_file" > "$install_tmp" || return 1
    else
        cat "$install_file" > "$install_tmp" || return 1
        printf '%s=%s\n' "$install_key" "$install_value" >> "$install_tmp" || return 1
    fi
    sync
    mv -f "$install_tmp" "$install_file"
}

install_valid_bool() {
    case "$1" in true|false) return 0 ;; *) return 1 ;; esac
}

install_select_mode() {
    if [ -n "${INSTALL_DNS_MODE:-}" ]; then
        case "$INSTALL_DNS_MODE" in 1|2|3) INSTALL_SELECTED_MODE=$INSTALL_DNS_MODE; return 0 ;; esac
    fi
    i18n_ui_print "- 选择 DNS 模式" "- Select DNS mode"
    if install_choice "模式 1：内网/校园网兼容" "Mode 1: LAN/campus compatibility" false; then
        INSTALL_SELECTED_MODE=1
    elif install_choice "模式 2：纯加密上游（推荐）" "Mode 2: encrypted upstreams (recommended)" true; then
        INSTALL_SELECTED_MODE=2
    else
        INSTALL_SELECTED_MODE=3
    fi
}

configure_install_options() {
    install_marker="$AGH_STATE_DIR/install-options.done"
    [ -f "$install_marker" ] && return 0
    if [ -f "$AGH_STATE_DIR/ports.conf" ] && [ -f "$AGH_CONFIG_DIR/mode.conf" ]; then
        install_existing_mode=$(sed -n 's/^mode=//p' "$AGH_CONFIG_DIR/mode.conf" | sed -n '1p')
        install_existing_ipv6=$(sed -n 's/^redirect_ipv6_dns=//p' "$AGH_CONFIG_DIR/mode.conf" | sed -n '1p')
        install_existing_853=$(sed -n 's/^block_ipv4_dot=//p' "$AGH_CONFIG_DIR/mode.conf" | sed -n '1p')
        [ -n "$install_existing_mode" ] || return 1
        [ -n "$install_existing_ipv6" ] || install_existing_ipv6=true
        [ -n "$install_existing_853" ] || install_existing_853=true
        install_set_value "$AGH_CONFIG_DIR/proxy-adapter.conf" enabled "$(sed -n 's/^enabled=//p' "$AGH_CONFIG_DIR/proxy-adapter.conf" 2>/dev/null | sed -n '1p')" 2>/dev/null || true
        printf 'mode=%s\nipv6=%s\nblock_853=%s\nproxy=%s\nfile_adapter=%s\n' "$install_existing_mode" "$install_existing_ipv6" "$install_existing_853" "$(sed -n 's/^enabled=//p' "$AGH_CONFIG_DIR/proxy-adapter.conf" 2>/dev/null | sed -n '1p')" "$(sed -n 's/^enabled=//p' "$AGH_CONFIG_DIR/file-adapter.conf" 2>/dev/null | sed -n '1p')" > "$install_marker"
        chmod 0600 "$install_marker"
        i18n_ui_print "- 检测到已有安装，保留原有模式和功能开关" "- Existing installation detected; preserving mode and feature toggles"
        return 0
    fi
    install_select_mode || return 1

    if [ -n "${INSTALL_ENABLE_IPV6:-}" ]; then
        install_ipv6=$INSTALL_ENABLE_IPV6
    elif install_choice "开启 IPv6 DNS 防泄漏" "Enable IPv6 DNS leak protection" true; then
        install_ipv6=true
    else
        install_ipv6=false
    fi

    if [ -n "${INSTALL_BLOCK_853:-}" ]; then
        install_853=$INSTALL_BLOCK_853
    elif install_choice "拦截 TCP/UDP 853（DoT/DoQ）" "Block TCP/UDP 853 (DoT/DoQ)" true; then
        install_853=true
    else
        install_853=false
    fi

    if [ -n "${INSTALL_ENABLE_PROXY:-}" ]; then
        install_proxy=$INSTALL_ENABLE_PROXY
    elif install_choice "启用 Box/Clash/Mihomo 代理适配（实验性）" "Enable Box/Clash/Mihomo adapter (experimental)" false; then
        install_proxy=true
    else
        install_proxy=false
    fi

    if [ -n "${INSTALL_ENABLE_FILE:-}" ]; then
        install_file_adapter=$INSTALL_ENABLE_FILE
    elif install_choice "启用文件级去广告（高风险，默认关闭）" "Enable file-level ad cleanup (high risk, off by default)" false; then
        install_file_adapter=true
    else
        install_file_adapter=false
    fi

    install_valid_bool "$install_ipv6" || return 1
    install_valid_bool "$install_853" || return 1
    install_valid_bool "$install_proxy" || return 1
    install_valid_bool "$install_file_adapter" || return 1

    install_set_value "$AGH_CONFIG_DIR/mode.conf" mode "$INSTALL_SELECTED_MODE" || return 1
    install_set_value "$AGH_CONFIG_DIR/mode.conf" redirect_ipv6_dns "$install_ipv6" || return 1
    install_set_value "$AGH_CONFIG_DIR/mode.conf" block_ipv4_dot "$install_853" || return 1
    install_set_value "$AGH_CONFIG_DIR/mode.conf" block_ipv6_dot "$install_853" || return 1
    install_set_value "$AGH_CONFIG_DIR/mode.conf" block_ipv4_doq "$install_853" || return 1
    install_set_value "$AGH_CONFIG_DIR/mode.conf" block_ipv6_doq "$install_853" || return 1
    install_set_value "$AGH_CONFIG_DIR/proxy-adapter.conf" enabled "$install_proxy" || return 1
    install_set_value "$AGH_CONFIG_DIR/file-adapter.conf" enabled "$install_file_adapter" || return 1
    printf 'mode=%s\nipv6=%s\nblock_853=%s\nproxy=%s\nfile_adapter=%s\n' "$INSTALL_SELECTED_MODE" "$install_ipv6" "$install_853" "$install_proxy" "$install_file_adapter" > "$install_marker" || return 1
    chmod 0600 "$install_marker"

    i18n_ui_print "- 已选择模式: $INSTALL_SELECTED_MODE" "- Selected mode: $INSTALL_SELECTED_MODE"
    i18n_ui_print "- IPv6 防泄漏: $install_ipv6" "- IPv6 leak protection: $install_ipv6"
    i18n_ui_print "- 853 拦截: $install_853" "- Port 853 blocking: $install_853"
    i18n_ui_print "- 代理适配: $install_proxy" "- Proxy adapter: $install_proxy"
    i18n_ui_print "- 文件级去广告: $install_file_adapter" "- File-level cleanup: $install_file_adapter"
}
