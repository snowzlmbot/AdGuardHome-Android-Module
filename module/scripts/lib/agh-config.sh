#!/system/bin/sh

agh_mode_set_value() {
    agh_mode_file=$1
    agh_mode_key=$2
    agh_mode_value=$3
    agh_mode_tmp="$agh_mode_file.tmp.$$"
    if grep -q "^${agh_mode_key}=" "$agh_mode_file"; then
        sed "s#^${agh_mode_key}=.*#${agh_mode_key}=${agh_mode_value}#" "$agh_mode_file" > "$agh_mode_tmp" || return 1
    else
        cat "$agh_mode_file" > "$agh_mode_tmp" || return 1
        printf '%s=%s\n' "$agh_mode_key" "$agh_mode_value" >> "$agh_mode_tmp" || return 1
    fi
    agh_sync
    agh_move "$agh_mode_tmp" "$agh_mode_file"
}

agh_apply_mode() {
    agh_mode=$1
    agh_config=${2:-$AGH_CONFIG_DIR/AdGuardHome.yaml}
    agh_mode_file=${3:-$AGH_CONFIG_DIR/mode.conf}
    case "$agh_mode" in 1|2|3) ;; *) return 1 ;; esac
    [ -f "$agh_config" ] && [ -f "$agh_mode_file" ] || return 1
    agh_tmp="$agh_config.tmp.$$"

    agh_print_upstream() {
        printf '  upstream_dns:\n'
        case "$agh_mode" in
            1)
                printf '    - 223.5.5.5\n    - 119.29.29.29\n'
                ;;
            2)
                printf '    - https://1.12.12.12/dns-query\n    - https://120.53.53.53/dns-query\n'
                ;;
            3)
                printf '    - https://dns.alidns.com/dns-query\n    - https://doh.pub/dns-query\n'
                ;;
        esac
    }

    agh_print_bootstrap() {
        printf '  bootstrap_dns:\n'
        if [ "$agh_mode" = 3 ]; then
            printf '    - 223.5.5.5\n    - 119.29.29.29\n'
        else
            printf '    - 180.184.1.1\n    - 180.184.2.2\n'
        fi
    }

    agh_print_fallback() {
        printf '  fallback_dns:\n'
        if [ "$agh_mode" = 1 ]; then
            printf '    - https://1.12.12.12/dns-query\n    - https://120.53.53.53/dns-query\n'
        else
            printf '    - 223.5.5.5\n    - 119.29.29.29\n'
        fi
    }

    agh_has_upstream=0
    agh_has_bootstrap=0
    agh_has_fallback=0
    agh_has_timeout=0
    agh_has_cache_optimistic=0
    agh_skip=0
    while IFS= read -r agh_line || [ -n "$agh_line" ]; do
        case "$agh_line" in
            "  upstream_dns:")
                agh_print_upstream
                agh_has_upstream=1
                agh_skip=1
                ;;
            "  bootstrap_dns:")
                agh_print_bootstrap
                agh_has_bootstrap=1
                agh_skip=1
                ;;
            "  fallback_dns:"*)
                agh_print_fallback
                agh_has_fallback=1
                agh_skip=1
                ;;
            "  upstream_mode:"*)
                printf '  upstream_mode: parallel\n'
                agh_skip=0
                ;;
            "  upstream_timeout:"*)
                printf '  upstream_timeout: 3s\n'
                agh_has_timeout=1
                agh_skip=0
                ;;
            "  cache_optimistic:"*)
                printf '  cache_optimistic: true\n'
                agh_has_cache_optimistic=1
                agh_skip=0
                ;;
            [![:space:]]*)
                agh_skip=0
                printf '%s\n' "$agh_line"
                ;;
            "  "[![:space:]]*)
                agh_skip=0
                printf '%s\n' "$agh_line"
                ;;
            *)
                [ "$agh_skip" -eq 0 ] && printf '%s\n' "$agh_line"
                ;;
        esac
    done < "$agh_config" > "$agh_tmp" || { rm -f "$agh_tmp"; return 1; }

    agh_insert_missing() {
        if [ "$agh_has_upstream" -eq 0 ]; then agh_print_upstream; agh_has_upstream=1; fi
        if [ "$agh_has_bootstrap" -eq 0 ]; then agh_print_bootstrap; agh_has_bootstrap=1; fi
        if [ "$agh_has_fallback" -eq 0 ]; then agh_print_fallback; agh_has_fallback=1; fi
        if [ "$agh_has_timeout" -eq 0 ]; then printf '  upstream_timeout: 3s\n'; agh_has_timeout=1; fi
        if [ "$agh_has_cache_optimistic" -eq 0 ]; then printf '  cache_optimistic: true\n'; agh_has_cache_optimistic=1; fi
    }

    agh_rebuild_tmp="$agh_tmp.rebuild"
    agh_seen_dns=0
    agh_inserted_missing=0
    while IFS= read -r agh_line || [ -n "$agh_line" ]; do
        if [ "$agh_seen_dns" -eq 1 ] && [ "$agh_inserted_missing" -eq 0 ]; then
            case "$agh_line" in
                ''|[[:space:]]*) ;;
                *) agh_insert_missing >> "$agh_rebuild_tmp"; agh_inserted_missing=1 ;;
            esac
        fi
        [ "$agh_line" = dns: ] && agh_seen_dns=1
        printf '%s\n' "$agh_line" >> "$agh_rebuild_tmp"
    done < "$agh_tmp"
    if [ "$agh_seen_dns" -eq 1 ] && [ "$agh_inserted_missing" -eq 0 ]; then
        agh_insert_missing >> "$agh_rebuild_tmp"
    fi
    if [ "$agh_seen_dns" -eq 1 ]; then
        agh_has_upstream=1
        agh_has_bootstrap=1
        agh_has_fallback=1
        agh_has_timeout=1
        agh_has_cache_optimistic=1
    fi
    mv -f "$agh_rebuild_tmp" "$agh_tmp" || { rm -f "$agh_tmp"; return 1; }

    [ "$agh_has_upstream" -eq 1 ] || { rm -f "$agh_tmp"; return 1; }
    [ "$agh_has_bootstrap" -eq 1 ] || { rm -f "$agh_tmp"; return 1; }
    [ "$agh_has_fallback" -eq 1 ] || { rm -f "$agh_tmp"; return 1; }
    [ "$agh_has_timeout" -eq 1 ] || { rm -f "$agh_tmp"; return 1; }
    [ "$agh_has_cache_optimistic" -eq 1 ] || { rm -f "$agh_tmp"; return 1; }
    chmod 0600 "$agh_tmp"
    agh_sync
    agh_move "$agh_tmp" "$agh_config" || return 1
    agh_mode_set_value "$agh_mode_file" mode "$agh_mode" || return 1
    case "$agh_mode" in
        1)
            agh_mode_set_value "$agh_mode_file" lan_dns_target '223.5.5.5:53,119.29.29.29:53' || return 1
            agh_mode_set_value "$agh_mode_file" bootstrap_dns '' || return 1
            ;;
        2)
            agh_mode_set_value "$agh_mode_file" lan_dns_target '' || return 1
            agh_mode_set_value "$agh_mode_file" bootstrap_dns '' || return 1
            ;;
        3)
            agh_mode_set_value "$agh_mode_file" lan_dns_target '' || return 1
            agh_mode_set_value "$agh_mode_file" bootstrap_dns '223.5.5.5:53,119.29.29.29:53' || return 1
            ;;
    esac
}
