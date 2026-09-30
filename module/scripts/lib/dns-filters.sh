#!/system/bin/sh

# Seed only the module-owned list; preserve dashboard choices and caches.
agh_seed_dns_filters() {
    seed_yaml=${1:-$AGH_CONFIG_DIR/AdGuardHome.yaml}
    grep -q 'id: 10001$' "$seed_yaml" || return 0
    grep -q 'url: https://anti-ad.net/easylist.txt$' "$seed_yaml" || return 0
    seed_dir="$AGH_DATA_DIR/data/filters"
    [ ! -s "$seed_dir/10001.txt" ] || return 0
    seed_source="$MODDIR/rules/anti-ad-easylist.txt"
    seed_expected=$(cut -d ' ' -f 1 "$seed_source.sha256" 2>/dev/null)
    [ ${#seed_expected} -eq 64 ] || return 1
    seed_actual=$(sha256sum "$seed_source" 2>/dev/null | cut -d ' ' -f 1)
    [ "$seed_actual" = "$seed_expected" ] || return 1
    mkdir -p "$seed_dir" || return 1
    atomic_copy "$seed_source" "$seed_dir/10001.txt"
}

agh_initialize_dns_filters() {
    seed_yaml=${1:-$AGH_CONFIG_DIR/AdGuardHome.yaml}
    # Default list initialization is one-shot. Existing choices are untouched.
    if [ ! -f "$AGH_STATE_DIR/dns-filters.initialized" ]; then
        if [ "${2:-}" = fresh ] || [ ! -s "$seed_yaml" ] || grep -q '^filters:[[:space:]]*\[\]' "$seed_yaml"; then
            seed_tmp="$seed_yaml.tmp.$$"
            if [ -s "$seed_yaml" ]; then
                awk '
                    function entry() {
                        print "  - enabled: true"
                        print "    url: https://anti-ad.net/easylist.txt"
                        print "    name: anti-AD (AdGuard)"
                        print "    id: 10001"
                    }
                    /^filters:/ { print "filters:"; entry(); seen=1; next }
                    { print }
                    END { if (!seen) { print "filters:"; entry() } }
                ' "$seed_yaml" > "$seed_tmp" || return 1
            else
                printf 'filters:\n  - enabled: true\n    url: https://anti-ad.net/easylist.txt\n    name: anti-AD (AdGuard)\n    id: 10001\n' > "$seed_tmp" || return 1
            fi
            chmod 0600 "$seed_tmp" || return 1
            agh_move "$seed_tmp" "$seed_yaml" || return 1
        fi
        printf 'version=1\n' > "$AGH_STATE_DIR/dns-filters.initialized" || return 1
        chmod 0600 "$AGH_STATE_DIR/dns-filters.initialized" || return 1
    fi
    agh_seed_dns_filters "$seed_yaml"
}
