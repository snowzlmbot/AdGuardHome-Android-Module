#!/system/bin/sh

module_detect_language() {
    module_language_file=${AGH_STATE_DIR:-/data/adb/agh/state}/language.conf
    MODULE_LANG=$(sed -n 's/^language=//p' "$module_language_file" 2>/dev/null | sed -n '1p')
    case "$MODULE_LANG" in zh|en) export MODULE_LANG; return 0 ;; esac
    module_locale=
    if command -v getprop >/dev/null 2>&1; then
        module_locale=$(getprop persist.sys.locale 2>/dev/null || true)
        [ -n "$module_locale" ] || module_locale=$(getprop ro.product.locale 2>/dev/null || true)
    fi
    case "$module_locale" in zh*|ZH*) MODULE_LANG=zh ;; *) MODULE_LANG=en ;; esac
    mkdir -p "${module_language_file%/*}" || return 1
    module_language_tmp="$module_language_file.tmp.$$"
    printf 'language=%s\n' "$MODULE_LANG" > "$module_language_tmp" || return 1
    chmod 0600 "$module_language_tmp"
    sync
    mv -f "$module_language_tmp" "$module_language_file" || return 1
    export MODULE_LANG
}

i18n_text() {
    i18n_zh=$1
    i18n_en=$2
    [ "${MODULE_LANG:-en}" = zh ] && printf '%s' "$i18n_zh" || printf '%s' "$i18n_en"
}

i18n_ui_print() {
    i18n_message=$(i18n_text "$1" "$2")
    if command -v ui_print >/dev/null 2>&1; then
        ui_print "$i18n_message"
    else
        printf '%s\n' "$i18n_message"
    fi
}
