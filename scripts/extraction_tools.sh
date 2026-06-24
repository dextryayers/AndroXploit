#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

VERSION="3.0.0"
JSON_MODE=false
STATE_FILE=""
RESUME_MODE=false
DEVICE_SERIAL=""
ADB_BASE="adb"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} ${BOLD}$1${NC}"; }
log_ok()    { echo -e "${GREEN}[+]${NC} ${BOLD}$1${NC}"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} ${BOLD}$1${NC}"; }
log_err()   { echo -e "${RED}[x]${NC} ${BOLD}$1${NC}"; }
log_section() { echo -e "\n${BLUE}════════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}════════════════════════════════════════════${NC}"; }
log_progress() { echo -ne "${DIM}  → $1...${NC}"; }
log_done()    { echo -e "\r  ${GREEN}✓${NC} ${DIM}$1${NC}"; }
log_fail()    { echo -e "\r  ${RED}✗${NC} ${DIM}$1${NC}"; }

if [[ "$JSON_MODE" == "true" ]]; then
    log_info()  { echo "{\"level\":\"info\",\"message\":\"$1\"}"; }
    log_ok()    { echo "{\"level\":\"ok\",\"message\":\"$1\"}"; }
    log_warn()  { echo "{\"level\":\"warn\",\"message\":\"$1\"}"; }
    log_err()   { echo "{\"level\":\"error\",\"message\":\"$1\"}"; }
    log_section() { echo "{\"event\":\"section\",\"name\":\"$1\"}"; }
    log_progress() { :; }
    log_done()    { :; }
    log_fail()    { :; }
fi

OUT_DIR="output/extracted"
mkdir -p "$OUT_DIR"/{apks,data,sms,contacts,call_log,accounts,wifi,browser,media,clipboard}

show_help() {
    cat <<EOF
${BOLD}Extraction Tools v${VERSION}${NC} — Complete Android Forensic Extraction Toolkit
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 <command> [args]

${BOLD}APK EXTRACTION:${NC}
  apk <package>                    Extract specific APK by package name
  apk-all                          Extract all APKs (system + third-party)
  apk-system                       Extract system APKs only
  apk-thirdparty                   Extract third-party APKs only
  apk-list                         List all installable packages with paths

${BOLD}APP DATA EXTRACTION:${NC}
  data <package>                   Extract app data directory (run-as or root)
  data-full <package>              Full data extraction (data + obb + cache)
  databases <package>              Extract app SQLite databases
  shared-prefs <package>           Extract app shared preferences
  cache <package>                  Extract app cache directory

${BOLD}COMMUNICATION DATA:${NC}
  sms                              Extract SMS/MMS messages
  contacts                         Extract contacts list
  call-log                         Extract call history
  mms                              Extract MMS messages
  all-communications               Extract all communication data

${BOLD}ACCOUNT & AUTH:${NC}
  accounts                         Extract device accounts
  tokens                           Extract auth tokens (root)
  wifi                             Extract WiFi passwords & configs
  browser                          Extract browser data (Chrome, Firefox)
  clipboard                        Extract clipboard content

${BOLD}MEDIA:${NC}
  photos                           Extract photos from DCIM
  screenshots                      Extract screenshots
  downloads                        Extract downloads
  media-all                        Extract all media files

${BOLD}SYSTEM:${NC}
  system-info                      Extract system information dump
  logs                             Extract device logs
  settings                         Extract device settings
  dumpsys <service>                Extract specific dumpsys service

${BOLD}PIPELINE:${NC}
  all                              Run full extraction pipeline
  summary                          Show extraction summary
  categorize                       Categorize extracted files by type

${DIM}Examples:${NC}
  $0 apk com.whatsapp
  $0 sms
  $0 wifi
  $0 all                           # Full extraction
EOF
}

check_adb() { adb get-state &>/dev/null || { log_err "No device connected."; exit 1; }; }
getprop_s() { adb shell getprop "$1" 2>/dev/null | tr -d '\r'; }

# ─── APK EXTRACTION ─────────────────────────────────────────

cmd_apk() {
    local pkg="${1:?Usage: $0 apk <package>}"
    check_adb
    local path; path=$(adb shell pm path "$pkg" 2>/dev/null | grep "package:" | head -1 | sed 's/package://' | tr -d '\r')
    [[ -z "$path" ]] && { log_err "Package not found: $pkg"; exit 1; }
    mkdir -p "$OUT_DIR/apks"
    log_section "APK: $pkg"
    log_progress "Pulling from $path"
    adb pull "$path" "$OUT_DIR/apks/${pkg}.apk" 2>/dev/null
    if [[ -f "$OUT_DIR/apks/${pkg}.apk" ]]; then
        local size; size=$(stat -c%s "$OUT_DIR/apks/${pkg}.apk" 2>/dev/null || stat -f%z "$OUT_DIR/apks/${pkg}.apk")
        log_done "Saved: $OUT_DIR/apks/${pkg}.apk ($((size/1024/1024))MB)"
    else log_fail "Pull failed"; fi
}

cmd_apk_all() {
    check_adb; mkdir -p "$OUT_DIR/apks"
    log_section "EXTRACT ALL APKS"
    local count=0
    adb shell pm list packages -f 2>/dev/null | while IFS= read -r line; do
        local path; path=$(echo "$line" | sed 's/package://' | sed 's/=.*//' | tr -d '\r')
        local pkg; pkg=$(echo "$line" | sed 's/.*=//' | tr -d '\r')
        [[ -z "$path" || -z "$pkg" ]] && continue
        local name="$OUT_DIR/apks/${pkg}.apk"
        [[ -f "$name" ]] && { log_done "Already have: $pkg"; continue; }
        log_progress "Pulling $pkg"
        adb pull "$path" "$name" 2>/dev/null && log_done "$pkg" || log_fail "Failed: $pkg"
    done
}

cmd_apk_system() {
    check_adb; mkdir -p "$OUT_DIR/apks"
    log_section "SYSTEM APKS"
    adb shell pm list packages -f -s 2>/dev/null | while IFS= read -r line; do
        local path; path=$(echo "$line" | sed 's/package://' | sed 's/=.*//' | tr -d '\r')
        local pkg; pkg=$(echo "$line" | sed 's/.*=//' | tr -d '\r')
        [[ -z "$path" || -z "$pkg" ]] && continue
        local name="$OUT_DIR/apks/system_${pkg}.apk"
        log_progress "$pkg"
        adb pull "$path" "$name" 2>/dev/null && log_done "$pkg" || true
    done
}

cmd_apk_thirdparty() {
    check_adb; mkdir -p "$OUT_DIR/apks"
    log_section "THIRD-PARTY APKS"
    adb shell pm list packages -f -3 2>/dev/null | while IFS= read -r line; do
        local path; path=$(echo "$line" | sed 's/package://' | sed 's/=.*//' | tr -d '\r')
        local pkg; pkg=$(echo "$line" | sed 's/.*=//' | tr -d '\r')
        [[ -z "$path" || -z "$pkg" ]] && continue
        log_progress "$pkg"
        adb pull "$path" "$OUT_DIR/apks/${pkg}.apk" 2>/dev/null && log_done "$pkg" || true
    done
}

cmd_apk_list() {
    check_adb
    log_section "INSTALLABLE PACKAGES"
    adb shell pm list packages -f 2>/dev/null | sed 's/package://' | sort
}

# ─── DATA EXTRACTION ────────────────────────────────────────

cmd_data() {
    local pkg="${1:?Usage: $0 data <package>}"
    check_adb; local dest="$OUT_DIR/data/$pkg"; mkdir -p "$dest"
    log_section "DATA: $pkg"
    if adb shell run-as "$pkg" cp -r /data/data/"$pkg" /sdcard/"${pkg}_data" 2>/dev/null; then
        log_progress "Pulling via run-as"
        adb pull "/sdcard/${pkg}_data" "$dest" 2>/dev/null
        adb shell rm -rf "/sdcard/${pkg}_data"
        log_done "Data: $dest"
    elif adb shell su -c "cp -r /data/data/$pkg /sdcard/${pkg}_data" 2>/dev/null; then
        log_progress "Pulling via root"
        adb pull "/sdcard/${pkg}_data" "$dest" 2>/dev/null
        adb shell rm -rf "/sdcard/${pkg}_data"
        log_done "Data (root): $dest"
    else log_fail "Cannot access $pkg data (needs root or debuggable)"; fi
}

cmd_data_full() {
    local pkg="${1:?Usage: $0 data-full <package>}"
    cmd_data "$pkg"
    check_adb
    # Try OBB
    if adb shell ls /sdcard/Android/obb/"$pkg"/ 2>/dev/null | head -1; then
        mkdir -p "$OUT_DIR/data/$pkg/obb"
        adb pull /sdcard/Android/obb/"$pkg"/ "$OUT_DIR/data/$pkg/obb/" 2>/dev/null || true
    fi
    # Try cache
    if adb shell ls /data/data/"$pkg"/cache/ 2>/dev/null | head -1; then
        mkdir -p "$OUT_DIR/data/$pkg/cache"
        adb shell run-as "$pkg" cp -r /data/data/"$pkg"/cache /sdcard/"${pkg}_cache" 2>/dev/null && \
        adb pull "/sdcard/${pkg}_cache" "$OUT_DIR/data/$pkg/cache" 2>/dev/null && \
        adb shell rm -rf "/sdcard/${pkg}_cache" || true
    fi
    log_ok "Full data: $OUT_DIR/data/$pkg/"
}

cmd_databases() {
    local pkg="${1:?Usage: $0 databases <package>}"
    check_adb; local dest="$OUT_DIR/data/$pkg/databases"; mkdir -p "$dest"
    log_section "DATABASES: $pkg"
    adb shell run-as "$pkg" cp -r /data/data/"$pkg"/databases /sdcard/"${pkg}_db" 2>/dev/null && \
    adb pull "/sdcard/${pkg}_db" "$dest" 2>/dev/null && adb shell rm -rf "/sdcard/${pkg}_db" && log_ok "Databases: $dest" || \
    adb shell su -c "cp -r /data/data/$pkg/databases /sdcard/${pkg}_db" 2>/dev/null && \
    adb pull "/sdcard/${pkg}_db" "$dest" 2>/dev/null && adb shell rm -rf "/sdcard/${pkg}_db" && log_ok "Databases (root): $dest" || \
    log_warn "Cannot access databases"
}

cmd_shared_prefs() {
    local pkg="${1:?Usage: $0 shared-prefs <package>}"
    check_adb; local dest="$OUT_DIR/data/$pkg/prefs"; mkdir -p "$dest"
    log_section "SHARED PREFS: $pkg"
    adb shell run-as "$pkg" cat /data/data/"$pkg"/shared_prefs/*.xml 2>/dev/null > "$dest/prefs.xml" || \
    adb shell su -c "cat /data/data/$pkg/shared_prefs/*.xml" 2>/dev/null > "$dest/prefs.xml" || \
    log_warn "Cannot access prefs"
    [[ -s "$dest/prefs.xml" ]] && log_ok "Prefs: $dest/prefs.xml ($(wc -l < "$dest/prefs.xml") lines)" || log_warn "No prefs"
}

cmd_cache() {
    local pkg="${1:?Usage: $0 cache <package>}"
    check_adb; local dest="$OUT_DIR/data/$pkg/cache"; mkdir -p "$dest"
    adb shell run-as "$pkg" cp -r /data/data/"$pkg"/cache /sdcard/"${pkg}_cache" 2>/dev/null && \
    adb pull "/sdcard/${pkg}_cache" "$dest" 2>/dev/null && adb shell rm -rf "/sdcard/${pkg}_cache" && log_ok "Cache: $dest" || \
    log_warn "Cannot access cache"
}

# ─── COMMUNICATION DATA ─────────────────────────────────────

cmd_sms() {
    check_adb; mkdir -p "$OUT_DIR/sms"
    log_section "SMS EXTRACTION"
    log_progress "Extracting inbox"
    adb shell content query --uri content://sms/inbox 2>/dev/null > "$OUT_DIR/sms/inbox.txt" && log_done "Inbox: $(wc -l < "$OUT_DIR/sms/inbox.txt") msgs" || log_warn "Cannot access inbox"
    log_progress "Extracting sent"
    adb shell content query --uri content://sms/sent 2>/dev/null > "$OUT_DIR/sms/sent.txt" && log_done "Sent: $(wc -l < "$OUT_DIR/sms/sent.txt") msgs" || true
    log_progress "Extracting drafts"
    adb shell content query --uri content://sms/draft 2>/dev/null > "$OUT_DIR/sms/drafts.txt" && log_done "Drafts" || true
    # Root fallback
    if [[ ! -s "$OUT_DIR/sms/inbox.txt" ]]; then
        log_progress "Trying root SQLite extraction"
        adb shell su -c "sqlite3 /data/data/com.android.providers.telephony/databases/mmssms.db 'SELECT address, date, body FROM sms WHERE type=1 ORDER BY date DESC LIMIT 200'" 2>/dev/null > "$OUT_DIR/sms/inbox.txt" && \
        log_done "Root extraction: $(wc -l < "$OUT_DIR/sms/inbox.txt") msgs" || true
    fi
}

cmd_mms() {
    check_adb; mkdir -p "$OUT_DIR/sms"
    log_section "MMS EXTRACTION"
    adb shell content query --uri content://mms 2>/dev/null > "$OUT_DIR/sms/mms.txt" || \
    adb shell su -c "sqlite3 /data/data/com.android.providers.telephony/databases/mmssms.db 'SELECT * FROM mms ORDER BY date DESC LIMIT 100'" 2>/dev/null > "$OUT_DIR/sms/mms.txt" || true
    [[ -s "$OUT_DIR/sms/mms.txt" ]] && log_ok "MMS extracted" || log_warn "No MMS"
}

cmd_contacts() {
    check_adb; mkdir -p "$OUT_DIR/contacts"
    log_section "CONTACTS EXTRACTION"
    log_progress "Using content provider"
    adb shell content query --uri content://contacts/phones/ 2>/dev/null > "$OUT_DIR/contacts/phones.txt" && log_done "$(wc -l < "$OUT_DIR/contacts/phones.txt") contacts" || true
    if [[ ! -s "$OUT_DIR/contacts/phones.txt" ]]; then
        log_progress "Trying root SQLite"
        adb shell su -c "sqlite3 /data/data/com.android.providers.contacts/databases/contacts2.db 'SELECT display_name, data1 FROM view_data LIMIT 200'" 2>/dev/null > "$OUT_DIR/contacts/all.txt" && \
        log_done "Root: $(wc -l < "$OUT_DIR/contacts/all.txt") entries" || log_warn "Cannot access contacts"
    fi
}

cmd_call_log() {
    check_adb; mkdir -p "$OUT_DIR/call_log"
    log_section "CALL LOG EXTRACTION"
    adb shell content query --uri content://call_log/calls 2>/dev/null > "$OUT_DIR/call_log/calls.txt" && \
    log_ok "Call log: $(wc -l < "$OUT_DIR/call_log/calls.txt") entries" || {
        adb shell su -c "sqlite3 /data/data/com.android.providers.contacts/databases/contacts2.db 'SELECT number, date, duration, type FROM calls ORDER BY date DESC LIMIT 200'" 2>/dev/null > "$OUT_DIR/call_log/calls.txt" && \
        log_ok "Call log (root): $(wc -l < "$OUT_DIR/call_log/calls.txt") entries" || log_warn "Cannot access call log"
    }
}

cmd_all_communications() {
    cmd_sms; cmd_mms; cmd_contacts; cmd_call_log
}

# ─── ACCOUNT & AUTH ─────────────────────────────────────────

cmd_accounts() {
    check_adb; mkdir -p "$OUT_DIR/accounts"
    log_section "ACCOUNTS EXTRACTION"
    adb shell dumpsys account 2>/dev/null | grep -E "Account \{name=|type=" > "$OUT_DIR/accounts/accounts.txt" || true
    adb shell dumpsys account 2>/dev/null > "$OUT_DIR/accounts/account_dump.txt" 2>/dev/null || true
    [[ -s "$OUT_DIR/accounts/accounts.txt" ]] && log_ok "Accounts: $(wc -l < "$OUT_DIR/accounts/accounts.txt") entries" || log_warn "No accounts found"
    cat "$OUT_DIR/accounts/accounts.txt" 2>/dev/null | sed 's/^/  /' || true
}

cmd_tokens() {
    check_adb; mkdir -p "$OUT_DIR/accounts"
    log_section "AUTH TOKENS (requires root)"
    adb shell su -c "sqlite3 /data/data/com.android.providers.settings/databases/settings.db 'SELECT * FROM secure WHERE name LIKE \"%token%\" OR name LIKE \"%password%\" OR name LIKE \"%account%\"'" 2>/dev/null > "$OUT_DIR/accounts/tokens.txt" || true
    adb shell su -c "find /data/system -name '*.key' -o -name '*.token' 2>/dev/null | head -20" > "$OUT_DIR/accounts/key_files.txt" 2>/dev/null || true
    [[ -s "$OUT_DIR/accounts/tokens.txt" ]] && log_ok "Tokens extracted" || log_warn "No tokens (root required)"
}

cmd_wifi() {
    check_adb; mkdir -p "$OUT_DIR/wifi"
    log_section "WIFI EXTRACTION"
    log_progress "Extracting configs"
    # Try multiple sources
    adb shell su -c "cat /data/misc/wifi/WifiConfigStore.xml 2>/dev/null" > "$OUT_DIR/wifi/config.xml" || true
    adb shell su -c "cat /data/misc/wifi/wpa_supplicant.conf 2>/dev/null" > "$OUT_DIR/wifi/wpa_supplicant.conf" || true
    adb shell su -c "sqlite3 /data/misc/wifi/wifi.db '.dump'" 2>/dev/null > "$OUT_DIR/wifi/database.txt" || true

    if [[ -s "$OUT_DIR/wifi/config.xml" ]]; then
        log_ok "WiFi config extracted"
        grep -oP 'SSID="\K[^"]+' "$OUT_DIR/wifi/config.xml" 2>/dev/null | sed 's/^/  SSID: /'
        grep -oP 'PreSharedKey="\K[^"]+' "$OUT_DIR/wifi/config.xml" 2>/dev/null | sed 's/^/  PWD:  /'
    elif [[ -s "$OUT_DIR/wifi/wpa_supplicant.conf" ]]; then
        log_ok "wpa_supplicant extracted"
        grep -E 'ssid|psk' "$OUT_DIR/wifi/wpa_supplicant.conf" 2>/dev/null | sed 's/^/  /'
    else log_warn "Cannot extract WiFi (root required)"; fi
}

cmd_browser() {
    check_adb; mkdir -p "$OUT_DIR/browser"
    log_section "BROWSER DATA EXTRACTION"
    local browsers=(
        "com.android.chrome:Chrome:/data/data/com.android.chrome"
        "org.mozilla.firefox:Firefox:/data/data/org.mozilla.firefox"
        "com.opera.browser:Opera:/data/data/com.opera.browser"
        "com.brave.browser:Brave:/data/data/com.brave.browser"
        "com.microsoft.emmx:Edge:/data/data/com.microsoft.emmx"
        "org.chromium.webview:WebView:/data/data/org.chromium.webview"
    )
    for entry in "${browsers[@]}"; do
        IFS=':' read -r pkg name path <<< "$entry"
        if adb shell pm list packages 2>/dev/null | grep -q "$pkg"; then
            log_info "Found $name ($pkg)"
            adb shell su -c "cat ${path}/databases/webview.db 2>/dev/null" > "$OUT_DIR/browser/${name}_webview.txt" 2>/dev/null || true
            adb shell su -c "ls ${path}/databases/ 2>/dev/null" > "$OUT_DIR/browser/${name}_files.txt" 2>/dev/null || true
        fi
    done
    log_ok "Browser data: $OUT_DIR/browser/"
}

cmd_clipboard() {
    check_adb
    log_section "CLIPBOARD EXTRACTION"
    # API 29+ clipboard access
    adb shell content read --uri content://clipboard 2>/dev/null > "$OUT_DIR/clipboard/clipboard.txt" || \
    adb shell su -c "cat /data/system/clipboard/clipboard.txt" 2>/dev/null > "$OUT_DIR/clipboard/clipboard.txt" || \
    log_warn "Cannot access clipboard"
    [[ -s "$OUT_DIR/clipboard/clipboard.txt" ]] && log_ok "Clipboard content extracted" || log_info "Clipboard empty or inaccessible"
}

# ─── MEDIA ──────────────────────────────────────────────────

cmd_photos() {
    check_adb; mkdir -p "$OUT_DIR/media/photos"
    log_section "PHOTOS (DCIM)"
    local count; count=$(adb shell ls /sdcard/DCIM/Camera/ 2>/dev/null | wc -l)
    log_info "$count files in DCIM/Camera"
    read -p "Pull all photos? This may take time. (y/N): " yn
    [[ "$yn" != "y" ]] && return
    adb pull /sdcard/DCIM/Camera/ "$OUT_DIR/media/photos/" 2>/dev/null && \
    log_ok "Photos: $OUT_DIR/media/photos/ ($(ls "$OUT_DIR/media/photos/" 2>/dev/null | wc -l) files)" || log_err "Failed"
}

cmd_screenshots() {
    check_adb; mkdir -p "$OUT_DIR/media/screenshots"
    local dirs=("/sdcard/DCIM/Screenshots" "/sdcard/Pictures/Screenshots" "/sdcard/Screenshots")
    for d in "${dirs[@]}"; do
        if adb shell ls "$d" 2>/dev/null | head -1; then
            adb pull "$d/" "$OUT_DIR/media/screenshots/" 2>/dev/null || true
        fi
    done
    log_ok "Screenshots: $(ls "$OUT_DIR/media/screenshots/" 2>/dev/null | wc -l) files"
}

cmd_downloads() {
    check_adb; mkdir -p "$OUT_DIR/media/downloads"
    adb pull /sdcard/Download/ "$OUT_DIR/media/downloads/" 2>/dev/null && \
    log_ok "Downloads: $(ls "$OUT_DIR/media/downloads/" 2>/dev/null | wc -l) files" || log_info "No downloads"
}

cmd_media_all() {
    cmd_photos; cmd_screenshots; cmd_downloads
}

# ─── SYSTEM ─────────────────────────────────────────────────

cmd_system_info() {
    check_adb; mkdir -p "$OUT_DIR/system"
    log_section "SYSTEM INFO DUMP"
    local items=(
        "build.prop:getprop"
        "cpuinfo:cat /proc/cpuinfo"
        "meminfo:cat /proc/meminfo"
        "partitions:cat /proc/partitions"
        "mounts:cat /proc/mounts"
        "modules:lsmod"
        "environment:printenv"
    )
    for entry in "${items[@]}"; do
        IFS=':' read -r name cmd <<< "$entry"
        log_progress "$name"
        adb shell "$cmd" 2>/dev/null > "$OUT_DIR/system/${name}.txt" && log_done "$name" || log_fail "$name"
    done
    log_ok "System info: $OUT_DIR/system/"
}

cmd_logs() {
    check_adb; mkdir -p "$OUT_DIR/system"
    log_section "LOG EXTRACTION"
    log_progress "Logcat"
    adb logcat -d -v threadtime > "$OUT_DIR/system/logcat.txt" 2>/dev/null && log_done "Logcat: $(wc -l < "$OUT_DIR/system/logcat.txt") lines"
    log_progress "Dmesg"
    adb shell dmesg > "$OUT_DIR/system/dmesg.txt" 2>/dev/null && log_done "Dmesg" || true
    log_progress "Event log"
    adb logcat -d -b events -v brief > "$OUT_DIR/system/events.txt" 2>/dev/null && log_done "Events" || true
}

cmd_settings() {
    check_adb; mkdir -p "$OUT_DIR/system"
    log_section "SETTINGS EXTRACTION"
    for ns in system secure global; do
        log_progress "Settings: $ns"
        adb shell settings list "$ns" > "$OUT_DIR/system/settings_${ns}.txt" 2>/dev/null && log_done "$ns ($(wc -l < "$OUT_DIR/system/settings_${ns}.txt") entries)" || true
    done
}

cmd_dumpsys() {
    check_adb; mkdir -p "$OUT_DIR/system"
    local service="${1:-battery}"
    log_progress "dumpsys $service"
    adb shell dumpsys "$service" > "$OUT_DIR/system/dumpsys_${service}.txt" 2>/dev/null && \
    log_done "$service: $(wc -l < "$OUT_DIR/system/dumpsys_${service}.txt") lines" || log_fail "Service '$service' not found"
}

# ─── PIPELINE ───────────────────────────────────────────────

cmd_all() {
    log_section "FULL EXTRACTION PIPELINE"
    local start; start=$(date +%s)

    echo; log_info "Phase 1: Communications"
    run_extract_phase "sms" "cmd_sms >/dev/null 2>&1 || true"
    run_extract_phase "mms" "cmd_mms >/dev/null 2>&1 || true"
    run_extract_phase "contacts" "cmd_contacts >/dev/null 2>&1 || true"
    run_extract_phase "call_log" "cmd_call_log >/dev/null 2>&1 || true"
    mark_extract_completed "communications"

    echo; log_info "Phase 2: Accounts & Auth"
    run_extract_phase "accounts" "cmd_accounts >/dev/null 2>&1 || true"
    run_extract_phase "tokens" "cmd_tokens >/dev/null 2>&1 || true"
    run_extract_phase "wifi" "cmd_wifi >/dev/null 2>&1 || true"
    run_extract_phase "browser" "cmd_browser >/dev/null 2>&1 || true"
    run_extract_phase "clipboard" "cmd_clipboard >/dev/null 2>&1 || true"
    mark_extract_completed "accounts_auth"

    echo; log_info "Phase 3: System"
    run_extract_phase "system_info" "cmd_system_info >/dev/null 2>&1 || true"
    run_extract_phase "logs" "cmd_logs >/dev/null 2>&1 || true"
    run_extract_phase "settings" "cmd_settings >/dev/null 2>&1 || true"
    mark_extract_completed "system"

    echo; log_info "Phase 4: APKs"
    run_extract_phase "apks" "cmd_apk_thirdparty >/dev/null 2>&1 || true"
    mark_extract_completed "apks"

    local end; end=$(date +%s)
    echo
    log_ok "Extraction pipeline complete ($((end-start))s)"
    cmd_summary

    if [[ -n "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
    fi

    if [[ "$JSON_MODE" == "true" ]]; then
        echo "{\"event\":\"complete\",\"duration\":$((end-start)),\"output_dir\":\"$OUT_DIR\"}"
    fi
}

cmd_summary() {
    echo
    log_section "EXTRACTION SUMMARY"
    echo "  ${BOLD}APKs:${NC}         $(find "$OUT_DIR/apks" -name '*.apk' 2>/dev/null | wc -l) files ($(du -sh "$OUT_DIR/apks" 2>/dev/null | cut -f1))"
    echo "  ${BOLD}Data:${NC}         $(find "$OUT_DIR/data" -type f 2>/dev/null | wc -l) files ($(du -sh "$OUT_DIR/data" 2>/dev/null | cut -f1))"
    echo "  ${BOLD}SMS:${NC}          $(find "$OUT_DIR/sms" -type f 2>/dev/null | wc -l) files ($(du -sh "$OUT_DIR/sms" 2>/dev/null | cut -f1))"
    echo "  ${BOLD}Contacts:${NC}     $(find "$OUT_DIR/contacts" -type f 2>/dev/null | wc -l) files"
    echo "  ${BOLD}Call Log:${NC}     $(find "$OUT_DIR/call_log" -type f 2>/dev/null | wc -l) files"
    echo "  ${BOLD}Accounts:${NC}     $(find "$OUT_DIR/accounts" -type f 2>/dev/null | wc -l) files"
    echo "  ${BOLD}WiFi:${NC}         $(find "$OUT_DIR/wifi" -type f 2>/dev/null | wc -l) files"
    echo "  ${BOLD}Browser:${NC}      $(find "$OUT_DIR/browser" -type f 2>/dev/null | wc -l) files"
    echo "  ${BOLD}Media:${NC}        $(find "$OUT_DIR/media" -type f 2>/dev/null | wc -l) files ($(du -sh "$OUT_DIR/media" 2>/dev/null | cut -f1))"
    echo "  ${BOLD}System:${NC}       $(find "$OUT_DIR/system" -type f 2>/dev/null | wc -l) files"
    echo "  ${BOLD}Clipboard:${NC}    $([ -f "$OUT_DIR/clipboard/clipboard.txt" ] && echo 'Yes' || echo 'No')"
    echo
    echo "  ${BOLD}Total size:${NC}   $(du -sh "$OUT_DIR" 2>/dev/null | cut -f1)"
    echo "  ${BOLD}Total files:${NC}  $(find "$OUT_DIR" -type f 2>/dev/null | wc -l)"
}

cmd_categorize() {
    log_section "FILE CATEGORIZATION"
    for dir in apks data sms contacts call_log accounts wifi browser media system clipboard; do
        local path="$OUT_DIR/$dir"
        if [[ -d "$path" ]]; then
            local count; count=$(find "$path" -type f 2>/dev/null | wc -l)
            local size; size=$(du -sh "$path" 2>/dev/null | cut -f1)
            echo "  ${BOLD}$dir:${NC} $count files ($size)"
        fi
    done
}

# ─── ARGUMENT PARSING / JSON / STATE FILE ─────────────────────

parse_extract_args() {
    local -a pos
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) JSON_MODE=true; shift ;;
            --state-file) STATE_FILE="$2"; shift 2 ;;
            --resume) RESUME_MODE=true; shift ;;
            --device) DEVICE_SERIAL="$2"; ADB_BASE="adb -s $DEVICE_SERIAL"; shift 2 ;;
            --output) OUT_DIR="$2"; shift 2 ;;
            *) pos+=("$1"); shift ;;
        esac
    done
    if [[ "$RESUME_MODE" == "true" && -z "$STATE_FILE" ]]; then
        STATE_FILE="${OUT_DIR}/.extract_state"
    fi
    mkdir -p "$OUT_DIR"
    # Re-emit remaining args
    echo "${pos[@]}"
}

mark_extract_completed() {
    local phase="$1"
    if [[ -n "$STATE_FILE" ]]; then
        mkdir -p "$(dirname "$STATE_FILE")"
        echo "$phase completed $(date +%s)" >> "$STATE_FILE"
    fi
    if [[ "$JSON_MODE" == "true" ]]; then
        echo "{\"event\":\"phase_complete\",\"phase\":\"$phase\"}"
    fi
}

is_extract_completed() {
    local phase="$1"
    if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
        return 1
    fi
    grep -q "^$phase " "$STATE_FILE" 2>/dev/null && return 0
    return 1
}

run_extract_phase() {
    local name="$1" func="$2"
    if is_extract_completed "$name"; then
        log_info "Phase '$name' already completed — skipping"
        return 0
    fi
    $func
    mark_extract_completed "$name"
}

# ─── MAIN ────────────────────────────────────────────────────

main() {
    local remaining
    remaining=$(parse_extract_args "$@")
    eval set -- "$remaining"

    if [[ "$JSON_MODE" == "true" ]]; then
        echo "{\"event\":\"start\",\"tool\":\"extraction_tools\",\"version\":\"$VERSION\"}"
    fi

    [[ $# -lt 1 ]] && { show_help; exit 0; }
    local cmd="$1"; shift

    case "$cmd" in
        apk)              cmd_apk "$@";;
        apk-all|apkall)   cmd_apk_all;;
        apk-system|sysapk) cmd_apk_system;;
        apk-thirdparty|3rdapk) cmd_apk_thirdparty;;
        apk-list|pkgs)    cmd_apk_list;;
        data)             cmd_data "$@";;
        data-full|fulldata) cmd_data_full "$@";;
        databases|db)     cmd_databases "$@";;
        shared-prefs|prefs) cmd_shared_prefs "$@";;
        cache)            cmd_cache "$@";;
        sms)              cmd_sms;;
        mms)              cmd_mms;;
        contacts)         cmd_contacts;;
        call-log|calls)   cmd_call_log;;
        all-communications|comm) cmd_all_communications;;
        accounts)         cmd_accounts;;
        tokens|auth)      cmd_tokens;;
        wifi|wifi-pass)   cmd_wifi;;
        browser)          cmd_browser;;
        clipboard|clip)   cmd_clipboard;;
        photos|pics)      cmd_photos;;
        screenshots|ss)   cmd_screenshots;;
        downloads)        cmd_downloads;;
        media-all|media)  cmd_media_all;;
        system-info|sysinfo) cmd_system_info;;
        logs|logcat)      cmd_logs;;
        settings)         cmd_settings;;
        dumpsys)          cmd_dumpsys "$@";;
        all|everything)   cmd_all;;
        summary|stats)    cmd_summary;;
        categorize|cat)   cmd_categorize;;
        help|-h|--help)   show_help;;
        *) log_err "Unknown: $cmd"; show_help; exit 1;;
    esac
}

main "$@"
