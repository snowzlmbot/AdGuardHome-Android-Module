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
    sync
    mv -f "$agh_mode_tmp" "$agh_mode_file"
}

agh_apply_mode() {
    agh_mode=$1
    agh_config=${2:-$AGH_CONFIG_DIR/AdGuardHome.yaml}
    agh_mode_file=${3:-$AGH_CONFIG_DIR/mode.conf}
    case "$agh_mode" in 1|2|3) ;; *) return 1 ;; esac
    [ -f "$agh_config" ] && [ -f "$agh_mode_file" ] || return 1
    agh_tmp="$agh_config.tmp.$$"
    awk -v mode="$agh_mode" '
        function print_upstream() {
            print "  upstream_dns:"
            if (mode == 1) {
                print "    - 223.5.5.5"
                print "    - 119.29.29.29"
            } else if (mode == 2) {
                print "    - https://1.12.12.12/dns-query"
                print "    - https://120.53.53.53/dns-query"
            } else {
                print "    - https://dns.alidns.com/dns-query"
                print "    - https://doh.pub/dns-query"
            }
        }
        function print_bootstrap() {
            print "  bootstrap_dns:"
            if (mode == 3) {
                print "    - 223.5.5.5"
                print "    - 119.29.29.29"
            } else {
                print "    - 180.184.1.1"
                print "    - 180.184.2.2"
            }
        }
        /^  upstream_dns:/ { print_upstream(); skip="upstream"; next }
        /^  bootstrap_dns:/ { print_bootstrap(); skip="bootstrap"; next }
        skip != "" && /^  [A-Za-z0-9_]+:/ { skip="" }
        skip != "" { next }
        /^  upstream_mode:/ { print "  upstream_mode: parallel"; next }
        { print }
    ' "$agh_config" > "$agh_tmp" || { rm -f "$agh_tmp"; return 1; }
    if ! grep -q '^  bootstrap_dns:$' "$agh_tmp"; then
        {
            printf '\n  bootstrap_dns:\n'
            if [ "$agh_mode" = 3 ]; then
                printf '    - 223.5.5.5\n    - 119.29.29.29\n'
            else
                printf '    - 180.184.1.1\n    - 180.184.2.2\n'
            fi
        } >> "$agh_tmp"
    fi
    grep -q '^  upstream_dns:$' "$agh_tmp" || { rm -f "$agh_tmp"; return 1; }
    grep -q '^  bootstrap_dns:$' "$agh_tmp" || { rm -f "$agh_tmp"; return 1; }
    chmod 0600 "$agh_tmp"
    sync
    mv -f "$agh_tmp" "$agh_config" || return 1
    agh_mode_set_value "$agh_mode_file" mode "$agh_mode" || return 1
    case "$agh_mode" in
        1)
            agh_mode_set_value "$agh_mode_file" lan_dns_target '223.5.5.5:53' || return 1
            agh_mode_set_value "$agh_mode_file" bootstrap_dns '' || return 1
            ;;
        2)
            agh_mode_set_value "$agh_mode_file" lan_dns_target '' || return 1
            agh_mode_set_value "$agh_mode_file" bootstrap_dns '' || return 1
            ;;
        3)
            agh_mode_set_value "$agh_mode_file" lan_dns_target '' || return 1
            agh_mode_set_value "$agh_mode_file" bootstrap_dns '223.5.5.5:53' || return 1
            ;;
    esac
}
