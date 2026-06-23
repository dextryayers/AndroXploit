#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

VERSION="3.0.0"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} ${BOLD}$1${NC}"; }
log_ok()    { echo -e "${GREEN}[+]${NC} ${BOLD}$1${NC}"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} ${BOLD}$1${NC}"; }
log_err()   { echo -e "${RED}[x]${NC} ${BOLD}$1${NC}"; }
log_section() { echo -e "\n${BLUE}════════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}════════════════════════════════════════════${NC}"; }
log_progress() { echo -ne "${DIM}  → $1...${NC}"; }
log_done()    { echo -e "\r  ${GREEN}✓${NC} ${DIM}$1${NC}"; }
log_fail()    { echo -e "\r  ${RED}✗${NC} ${DIM}$1${NC}"; }

OUT_DIR="output/reports"
mkdir -p "$OUT_DIR"

check_adb() {
    command -v adb &>/dev/null || { log_err "ADB not found."; exit 1; }
    adb get-state &>/dev/null || { log_err "No device connected."; exit 1; }
}

getprop_s() { adb shell getprop "$1" 2>/dev/null | tr -d '\r'; }
su_check() { adb shell "which su" 2>/dev/null | grep -q su; }

show_help() {
    cat <<EOF
${BOLD}Device Info v${VERSION}${NC} — Comprehensive Android Device Intelligence
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 <command> [args]

${BOLD}INFO COMMANDS:${NC}
  full                  Full comprehensive device report
  quick                 Quick device summary (one-liner)
  json                  JSON formatted output (machine-readable)
  report [file]         Save full report to file
  compare <file1> <file2> Compare two device reports

${BOLD}HARDWARE:${NC}
  cpu                   CPU & architecture details
  memory                Memory & storage info
  display               Display/screen information
  sensors               List hardware sensors
  storage               Storage partition details

${BOLD}NETWORK:${NC}
  network               Network interfaces & config
  wifi                  WiFi connection details
  cellular              Cellular network info

${BOLD}SECURITY:${NC}
  security              Security posture assessment
  root                  Root status check
  selinux               SELinux status & policies
  permissions [pkg]     Permission analysis (all or per app)

${BOLD}SOFTWARE:${NC}
  apps                  List installed third-party apps
  system-apps           List system apps
  services              List running services
  processes             List running processes
  features              Device features list
  libraries             Available native libraries

${BOLD}SYSTEM:${NC}
  battery               Battery health & stats
  uptime                Device uptime
  props [filter]        All system properties
  env                   Environment variables

${DIM}Examples:${NC}
  $0 full                # Full device report
  $0 security            # Security assessment
  $0 report mydevice.txt # Save report to file
EOF
}

# ─── INFO LEVELS ────────────────────────────────────────────

cmd_quick() {
    check_adb
    echo "$(getprop_s ro.product.manufacturer) $(getprop_s ro.product.model) | Android $(getprop_s ro.build.version.release) (SDK $(getprop_s ro.build.version.sdk)) | $(getprop_s ro.product.cpu.abi) | $(adb shell dumpsys battery 2>/dev/null | grep level | awk '{print $2}')% batt | $(adb shell getenforce 2>/dev/null)"
}

cmd_json() {
    check_adb
    echo "{"
    echo "  \"model\": \"$(getprop_s ro.product.model)\","
    echo "  \"manufacturer\": \"$(getprop_s ro.product.manufacturer)\","
    echo "  \"android_version\": \"$(getprop_s ro.build.version.release)\","
    echo "  \"sdk\": \"$(getprop_s ro.build.version.sdk)\","
    echo "  \"build\": \"$(getprop_s ro.build.display.id)\","
    echo "  \"fingerprint\": \"$(getprop_s ro.build.fingerprint)\","
    echo "  \"security_patch\": \"$(getprop_s ro.build.version.security_patch)\","
    echo "  \"cpu_abi\": \"$(getprop_s ro.product.cpu.abi)\","
    echo "  \"debuggable\": \"$(getprop_s ro.debuggable)\","
    echo "  \"secure\": \"$(getprop_s ro.secure)\","
    echo "  \"selinux\": \"$(adb shell getenforce 2>/dev/null | tr -d '\r')\","
    echo "  \"sdk_int\": \"$(getprop_s ro.build.version.sdk)\","
    echo "  \"device\": \"$(getprop_s ro.product.device)\","
    echo "  \"board\": \"$(getprop_s ro.product.board)\","
    echo "  \"brand\": \"$(getprop_s ro.product.brand)\","
    echo "  \"serial\": \"$(adb get-serialno)\","
    echo "  \"ram\": \"$(adb shell cat /proc/meminfo 2>/dev/null | grep MemTotal | awk '{print $2}' | tr -d '\r')\""
    echo "}"
}

cmd_full() {
    check_adb
    log_section "DEVICE INTELLIGENCE REPORT"
    echo "  ${BOLD}Generated:${NC} $(date)"
    echo "  ${BOLD}Tool:${NC}      Device Info v$VERSION"
    echo

    log_section "SYSTEM"
    echo "  ${BOLD}Model:${NC}        $(getprop_s ro.product.model)"
    echo "  ${BOLD}Manufacturer:${NC} $(getprop_s ro.product.manufacturer)"
    echo "  ${BOLD}Brand:${NC}        $(getprop_s ro.product.brand)"
    echo "  ${BOLD}Device:${NC}       $(getprop_s ro.product.device)"
    echo "  ${BOLD}Board:${NC}        $(getprop_s ro.product.board)"
    echo "  ${BOLD}Serial:${NC}       $(adb get-serialno)"
    echo "  ${BOLD}Hostname:${NC}     $(getprop_s net.hostname)"
    echo "  ${BOLD}Uptime:${NC}       $(adb shell uptime 2>/dev/null | tr -d '\r')"

    log_section "ANDROID"
    echo "  ${BOLD}Version:${NC}      $(getprop_s ro.build.version.release)"
    echo "  ${BOLD}SDK:${NC}          $(getprop_s ro.build.version.sdk) (API $(getprop_s ro.build.version.sdk))"
    echo "  ${BOLD}Build:${NC}        $(getprop_s ro.build.display.id)"
    echo "  ${BOLD}Type:${NC}         $(getprop_s ro.build.type)"
    echo "  ${BOLD}Tags:${NC}         $(getprop_s ro.build.tags)"
    echo "  ${BOLD}Fingerprint:${NC}  $(getprop_s ro.build.fingerprint)"
    echo "  ${BOLD}Security Patch:${NC} $(getprop_s ro.build.version.security_patch)"
    echo "  ${BOLD}Build Time:${NC}   $(getprop_s ro.build.date)"
    echo "  ${BOLD}User:${NC}         $(getprop_s ro.build.user)"
    echo "  ${BOLD}Host:${NC}         $(getprop_s ro.build.host)"

    log_section "HARDWARE"
    echo "  ${BOLD}CPU ABI:${NC}      $(getprop_s ro.product.cpu.abi)"
    echo "  ${BOLD}CPU ABI2:${NC}     $(getprop_s ro.product.cpu.abi2)"
    echo "  ${BOLD}CPU Info:${NC}"
    adb shell cat /proc/cpuinfo 2>/dev/null | grep -E "Processor|Hardware|Features" | head -5 | sed 's/^/    /'
    echo "  ${BOLD}RAM:${NC}          $(adb shell cat /proc/meminfo 2>/dev/null | grep MemTotal | awk '{print $2, $3}' | tr -d '\r')"
    echo "  ${BOLD}Swap:${NC}         $(adb shell cat /proc/meminfo 2>/dev/null | grep SwapTotal | awk '{print $2, $3}' | tr -d '\r')"

    log_section "STORAGE"
    adb shell df -h 2>/dev/null | while IFS= read -r line; do echo "  $line"; done

    log_section "DISPLAY"
    echo "  ${BOLD}Resolution:${NC}   $(adb shell wm size 2>/dev/null | tr -d '\r')"
    echo "  ${BOLD}Density:${NC}      $(adb shell wm density 2>/dev/null | tr -d '\r')"
    echo "  ${BOLD}LCD Density:${NC}  $(getprop_s ro.sf.lcd_density)"
    echo "  ${BOLD}Screen On:${NC}    $(adb shell dumpsys display 2>/dev/null | grep 'mScreenState\|mScreenOn' | head -1 | tr -d '\r')"

    log_section "NETWORK"
    echo "  ${BOLD}IP:${NC}           $(adb shell ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | tr -d '\r')"
    echo "  ${BOLD}MAC:${NC}          $(adb shell cat /sys/class/net/wlan0/address 2>/dev/null | tr -d '\r')"
    echo "  ${BOLD}Gateway:${NC}      $(adb shell ip route 2>/dev/null | grep default | awk '{print $3}' | tr -d '\r')"
    echo "  ${BOLD}DNS:${NC}          $(adb shell getprop net.dns1 2>/dev/null | tr -d '\r')"
    echo "  ${BOLD}Interfaces:${NC}"
    adb shell ip addr show 2>/dev/null | grep -E "^[0-9]|inet " | sed 's/^/    /'

    log_section "SECURITY POSTURE"
    echo "  ${BOLD}Root Access:${NC}  $(su_check && echo "${RED}YES${NC}" || echo "${GREEN}No${NC}")"
    echo "  ${BOLD}ADB Secure:${NC}   $(getprop_s ro.secure) ($([ "$(getprop_s ro.secure)" = "1" ] && echo 'Secure' || echo 'Insecure'))"
    echo "  ${BOLD}Debuggable:${NC}   $(getprop_s ro.debuggable)"
    echo "  ${BOLD}SELinux:${NC}      $(adb shell getenforce 2>/dev/null | tr -d '\r')"
    echo "  ${BOLD}Encryption:${NC}   $(getprop_s ro.crypto.state) (type: $(getprop_s ro.crypto.type))"
    echo "  ${BOLD}Verified Boot:${NC} $(getprop_s ro.boot.verifiedbootstate)"
    echo "  ${BOLD}ADB Auth:${NC}     $(getprop_s ro.adb.secure)"
    echo "  ${BOLD}Knox:${NC}         $(getprop_s ro.config.knox || echo 'N/A')"
    echo "  ${BOLD}Widevine:${NC}     $(getprop_s ro.widevine.cachesize || echo 'N/A')"

    log_section "BATTERY"
    local batt; batt=$(adb shell dumpsys battery 2>/dev/null)
    local level=$(echo "$batt" | grep "level:" | awk '{print $2}')
    local temp=$(echo "$batt" | grep "temperature:" | awk '{print $2}')
    echo "$batt" | grep -E "level|temperature|status|health|voltage|current|technology|present" | sed 's/  */ /g' | while IFS= read -r line; do echo "  $line"; done
    echo -n "  ${BOLD}Graph:${NC}       "
    local filled=$((level / 5))
    for ((i=0; i<filled; i++)); do echo -ne "${GREEN}█${NC}"; done
    for ((i=filled; i<20; i++)); do echo -ne "${DIM}░${NC}"; done
    echo " ${level}% ($((temp / 10)).$((temp % 10))°C)"

    log_section "PACKAGES"
    echo "  ${BOLD}Total:${NC}       $(adb shell pm list packages 2>/dev/null | wc -l)"
    echo "  ${BOLD}Third-party:${NC} $(adb shell pm list packages -3 2>/dev/null | wc -l)"
    echo "  ${BOLD}System:${NC}      $(adb shell pm list packages -s 2>/dev/null | wc -l)"
    echo "  ${BOLD}Disabled:${NC}    $(adb shell pm list packages -d 2>/dev/null | wc -l)"
    echo "  ${BOLD}Debuggable:${NC}  $(adb shell pm list packages -d 2>/dev/null | wc -l)"

    log_section "FEATURES"
    adb shell pm list features 2>/dev/null | sed 's/feature:/  /' | head -25

    log_section "RUNNING SERVICES"
    adb shell dumpsys activity services 2>/dev/null | grep "ServiceRecord" | head -15 | sed 's/.*{//;s/}.*//' | sed 's/^/  /'

    log_section "SENSORS"
    adb shell dumpsys sensorservice 2>/dev/null | grep -E "Sensor [0-9]|name=|vendor=|type=" | head -20 | sed 's/^/  /'
}

# ─── CATEGORY COMMANDS ──────────────────────────────────────

cmd_cpu() {
    check_adb
    log_section "CPU & ARCHITECTURE"
    echo "  ${BOLD}ABI:${NC}        $(getprop_s ro.product.cpu.abi)"
    echo "  ${BOLD}ABI2:${NC}       $(getprop_s ro.product.cpu.abi2)"
    echo "  ${BOLD}Arch:${NC}       $(uname -m 2>/dev/null || echo 'N/A')"
    echo "  ${BOLD}Cores:${NC}      $(adb shell nproc 2>/dev/null | tr -d '\r')"
    adb shell cat /proc/cpuinfo 2>/dev/null | grep -E "Processor|Hardware|Features|model name|cpu MHz" | head -10 | sed 's/^/  /'
}

cmd_memory() {
    check_adb
    log_section "MEMORY & STORAGE"
    echo "  ${BOLD}RAM:${NC}"
    adb shell cat /proc/meminfo 2>/dev/null | grep -E "MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree" | sed 's/^/    /'
    echo
    echo "  ${BOLD}Storage:${NC}"
    adb shell df -h /data /system /sdcard /cache 2>/dev/null | sed 's/^/    /'
}

cmd_display() {
    check_adb
    log_section "DISPLAY"
    echo "  ${BOLD}Resolution:${NC} $(adb shell wm size 2>/dev/null | tr -d '\r')"
    echo "  ${BOLD}Density:${NC}    $(adb shell wm density 2>/dev/null | tr -d '\r')"
    echo "  ${BOLD}LCD:${NC}        $(getprop_s ro.sf.lcd_density)dpi"
    echo "  ${BOLD}Refresh:${NC}    $(getprop_s ro.sf.refresh_rate || echo '60Hz')"
    echo "  ${BOLD}HDR:${NC}        $(getprop_s ro.sf.hdr || echo 'N/A')"
}

cmd_sensors() {
    check_adb
    log_section "SENSORS"
    adb shell dumpsys sensorservice 2>/dev/null | grep -E "Sensor [0-9]|name=|vendor=" | sed 's/^/  /' | head -30
}

cmd_storage() {
    check_adb
    log_section "STORAGE PARTITIONS"
    adb shell df -h 2>/dev/null | sed 's/^/  /'
}

cmd_network() {
    check_adb
    log_section "NETWORK CONFIGURATION"
    adb shell ip addr show 2>/dev/null | sed 's/^/  /'
    echo
    echo "  ${BOLD}Routes:${NC}"
    adb shell ip route 2>/dev/null | sed 's/^/    /'
}

cmd_wifi() {
    check_adb
    log_section "WIFI DETAILS"
    adb shell dumpsys wifi 2>/dev/null | grep -E "SSID|BSSID|ipAddress|linkSpeed|rssi|frequency|mWifiInfo|mNetworkInfo" | head -15 | sed 's/  */ /g' | sed 's/^/  /'
}

cmd_cellular() {
    check_adb
    log_section "CELLULAR NETWORK"
    echo "  ${BOLD}Network:${NC}   $(getprop_s gsm.network.type || echo 'N/A')"
    echo "  ${BOLD}Operator:${NC}  $(getprop_s gsm.operator.alpha || echo 'N/A')"
    echo "  ${BOLD}Country:${NC}   $(getprop_s gsm.operator.iso-country || echo 'N/A')"
    echo "  ${BOLD}IMEI:${NC}      $(adb shell dumpsys iphonesubinfo 2>/dev/null | grep 'Device ID' | head -1 | awk '{print $NF}')"
    echo "  ${BOLD}Signal:${NC}    $(adb shell dumpsys telephony 2>/dev/null | grep -i signal | head -1 | tr -d '\r')"
}

cmd_security() {
    check_adb
    log_section "SECURITY POSTURE ASSESSMENT"
    local score=0; local total=0

    # Root check
    ((total++))
    if su_check; then echo -e "  ${RED}✗${NC} Root detected — device is rooted"; else echo -e "  ${GREEN}✓${NC} No root access"; ((score++)); fi

    # ADB Secure
    ((total++))
    if [[ "$(getprop_s ro.secure)" == "1" ]]; then echo -e "  ${GREEN}✓${NC} ADB secure mode"; ((score++)); else echo -e "  ${RED}✗${NC} ADB insecure"; fi

    # Debuggable
    ((total++))
    if [[ "$(getprop_s ro.debuggable)" == "0" ]]; then echo -e "  ${GREEN}✓${NC} Not debuggable"; ((score++)); else echo -e "  ${RED}✗${NC} Debuggable mode"; fi

    # SELinux
    ((total++))
    local se; se=$(adb shell getenforce 2>/dev/null | tr -d '\r')
    if [[ "$se" == "Enforcing" ]]; then echo -e "  ${GREEN}✓${NC} SELinux Enforcing"; ((score++)); else echo -e "  ${RED}✗${NC} SELinux $se"; fi

    # Encryption
    ((total++))
    if [[ "$(getprop_s ro.crypto.state)" == "encrypted" ]]; then echo -e "  ${GREEN}✓${NC} Storage encrypted"; ((score++)); else echo -e "  ${RED}✗${NC} Not encrypted"; fi

    # ADB Auth
    ((total++))
    if [[ "$(getprop_s ro.adb.secure)" == "1" ]]; then echo -e "  ${GREEN}✓${NC} ADB auth required"; ((score++)); else echo -e "  ${RED}✗${NC} ADB auth not required"; fi

    # Verified boot
    ((total++))
    local vb; vb=$(getprop_s ro.boot.verifiedbootstate)
    if [[ "$vb" == "green" ]]; then echo -e "  ${GREEN}✓${NC} Verified boot: $vb"; ((score++)); else echo -e "  ${YELLOW}⚠${NC} Verified boot: $vb"; fi

    echo
    echo -e "  ${BOLD}Security Score:${NC} $score/$total"
    if [[ $score -eq $total ]]; then echo -e "  ${GREEN}Excellent security posture${NC}"
    elif [[ $score -ge $((total - 2)) ]]; then echo -e "  ${YELLOW}Good, some improvements needed${NC}"
    else echo -e "  ${RED}Poor security posture${NC}"; fi
}

cmd_root() {
    check_adb
    log_section "ROOT CHECK"
    if su_check; then
        echo -e "  ${RED}✗${NC} Root binary found"
        local su_path; su_path=$(adb shell "which su" 2>/dev/null | tr -d '\r')
        echo "  ${BOLD}Path:${NC} $su_path"
        log_warn "Device is rooted!"
    else
        echo -e "  ${GREEN}✓${NC} No root binary found"
        echo "  Device is not rooted."
    fi
}

cmd_selinux() {
    check_adb
    log_section "SELINUX STATUS"
    echo "  ${BOLD}Mode:${NC}        $(adb shell getenforce 2>/dev/null | tr -d '\r')"
    echo "  ${BOLD}Build:${NC}       $(getprop_s ro.build.selinux)"
    echo "  ${BOLD}Policy:${NC}      $(adb shell ls -Z /init.rc 2>/dev/null | awk '{print $1}')"
    echo
    # List security contexts of key files
    echo "  ${BOLD}Key contexts:${NC}"
    for f in /init.rc /system/bin/sh /system/app /data; do
        adb shell ls -Z "$f" 2>/dev/null | head -1 | sed 's/^/    /'
    done
}

cmd_permissions() {
    check_adb
    local pkg="${1:-}"
    if [[ -n "$pkg" ]]; then
        log_section "PERMISSIONS: $pkg"
        adb shell dumpsys package "$pkg" 2>/dev/null | grep -A 200 "requested permissions:" | head -60 | sed 's/^/  /'
    else
        log_section "RISKY PERMISSIONS OVERVIEW"
        local perms=("ACCESS_FINE_LOCATION" "CAMERA" "RECORD_AUDIO" "READ_SMS" "READ_CONTACTS" "READ_CALL_LOG" "READ_EXTERNAL_STORAGE" "WRITE_EXTERNAL_STORAGE" "ACCESS_BACKGROUND_LOCATION" "BIND_ACCESSIBILITY_SERVICE")
        for perm in "${perms[@]}"; do
            local count; count=$(adb shell pm list packages -p 2>/dev/null | grep -c "android.permission.$perm" 2>/dev/null || echo 0)
            echo "  ${BOLD}android.permission.$perm${NC}: $count apps"
        done
    fi
}

cmd_apps() { check_adb; adb shell pm list packages -3 -f 2>/dev/null | sed 's/package://' | sed 's/=.*=//' | sort; }
cmd_system_apps() { check_adb; adb shell pm list packages -s 2>/dev/null | sed 's/package://' | sort; }
cmd_services() { check_adb; adb shell dumpsys activity services 2>/dev/null | grep -oP 'ServiceRecord\{[^}]+\}' | sed 's/.* //' | head -40; }
cmd_processes() { check_adb; adb shell ps -A 2>/dev/null | head -30; }
cmd_features() { check_adb; adb shell pm list features 2>/dev/null | sed 's/feature:/  /'; }
cmd_battery() { check_adb; log_section "BATTERY HEALTH"; adb shell dumpsys battery 2>/dev/null | sed 's/  */ /g' | sed 's/^/  /'; }
cmd_uptime() { check_adb; adb shell uptime 2>/dev/null | tr -d '\r'; }
cmd_props() {
    check_adb
    local filter="${1:-}"
    if [[ -n "$filter" ]]; then adb shell getprop | grep -i "$filter" | sed 's/^/  /'; else adb shell getprop | sed 's/^/  /'; fi
}
cmd_env() {
    check_adb
    log_section "DEVICE ENVIRONMENT"
    adb shell printenv 2>/dev/null | sort | sed 's/^/  /' | head -30
}

cmd_report() {
    local file="${1:-$OUT_DIR/device_report_$(date +%Y%m%d_%H%M%S).txt}"
    mkdir -p "$(dirname "$file")"
    log_info "Saving report to $file..."
    cmd_full > "$file" 2>&1
    log_ok "Report saved: $file ($(wc -l < "$file") lines)"
}

cmd_compare() {
    local f1="${1:?Usage: $0 compare <file1> <file2>}"
    local f2="${2:?Usage: $0 compare <file1> <file2>}"
    [[ ! -f "$f1" ]] && { log_err "Not found: $f1"; exit 1; }
    [[ ! -f "$f2" ]] && { log_err "Not found: $f2"; exit 1; }
    log_section "COMPARISON"
    diff -u "$f1" "$f2" 2>/dev/null | head -100 || echo "(identical or diff empty)"
}

# ─── MAIN ────────────────────────────────────────────────────

main() {
    [[ $# -lt 1 ]] && { cmd_full; exit 0; }
    local cmd="$1"; shift

    case "$cmd" in
        full|all)           cmd_full;;
        quick|short)        cmd_quick;;
        json|machine)       cmd_json;;
        report|save)        cmd_report "$@";;
        compare|diff)       cmd_compare "$@";;
        cpu|cpuinfo)        cmd_cpu;;
        memory|ram|mem)     cmd_memory;;
        display|screen)     cmd_display;;
        sensors)            cmd_sensors;;
        storage|disk)       cmd_storage;;
        network|net)        cmd_network;;
        wifi|wlan)          cmd_wifi;;
        cellular|mobile)    cmd_cellular;;
        security|sec)       cmd_security;;
        root|su)            cmd_root;;
        selinux|se)         cmd_selinux;;
        permissions|perms)  cmd_permissions "$@";;
        apps|thirdparty)    cmd_apps;;
        system-apps|sysapps) cmd_system_apps;;
        services)           cmd_services;;
        processes|ps)       cmd_processes;;
        features)           cmd_features;;
        battery|batt)       cmd_battery;;
        uptime)             cmd_uptime;;
        props|getprop)      cmd_props "$@";;
        env|environment)    cmd_env;;
        help|-h|--help)     show_help;;
        *)                  log_err "Unknown: $cmd"; show_help; exit 1;;
    esac
}

main "$@"
