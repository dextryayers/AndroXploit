#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

VERSION="3.0.0"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} ${BOLD}$1${NC}"; }
log_ok()    { echo -e "${GREEN}[+]${NC} ${BOLD}$1${NC}"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} ${BOLD}$1${NC}"; }
log_err()   { echo -e "${RED}[x]${NC} ${BOLD}$1${NC}"; }
log_section() { echo -e "\n${BLUE}════════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}════════════════════════════════════════════${NC}"; }
log_progress() { echo -ne "${DIM}  → $1...${NC}"; }
log_done()    { echo -e "\r  ${GREEN}✓${NC} ${DIM}$1${NC}"; }
log_fail()    { echo -e "\r  ${RED}✗${NC} ${DIM}$1${NC}"; }

OUT_DIR="output"
mkdir -p "$OUT_DIR"

cleanup() { rm -f /tmp/adb_toolkit_*; }
trap cleanup EXIT

check_adb() {
    if ! command -v adb &>/dev/null; then
        log_err "ADB not found. Install Android SDK platform-tools."
        exit 1
    fi
}

check_device() {
    local state
    state=$(adb get-state 2>/dev/null || echo "unknown")
    if [[ "$state" != "device" ]]; then
        log_err "No device/emulator connected."
        exit 1
    fi
}

getprop_s() { adb shell getprop "$1" 2>/dev/null | tr -d '\r'; }

su_check() {
    adb shell "which su" 2>/dev/null | grep -q su
}

show_help() {
    cat <<EOF
${BOLD}ADB Toolkit v${VERSION}${NC} — Advanced Android Debug Bridge Command Center
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 <command> [args]
       $0 interactive   (launch interactive menu mode)

${BOLD}DEVICE MANAGEMENT:${NC}
  devices                    List connected devices with details
  info                       Comprehensive device information
  model                      Show device model
  serial                     Show device serial number
  battery                    Show battery status & health
  screen-state               Show screen on/off status
  uptime                     Show device uptime
  reboot [bootloader|recovery|sideload]  Reboot device
  root                       Attempt root access check

${BOLD}APP MANAGEMENT:${NC}
  install <apk>...           Install one or more APKs (batch)
  uninstall <pkg>            Uninstall package
  list-packages [filter]     List all packages
  list-thirdparty            List third-party packages only
  list-debuggable            List debuggable packages
  list-disabled              List disabled packages
  list-system                List system packages
  clear <pkg>                Clear app data
  grant <pkg> <perm>         Grant permission to app
  revoke <pkg> <perm>        Revoke permission from app
  disable <pkg>              Disable package
  enable <pkg>               Enable package

${BOLD}ACTIVITY MANAGEMENT:${NC}
  start <pkg/activity>       Start activity
  stop <pkg>                 Force-stop app
  restart <pkg>              Force-stop then start app
  top-activity               Show current activity
  open-url <url>             Open URL in browser
  dial <number>              Open dialer with number
  send-sms <num> <msg>       Open SMS with pre-filled message

${BOLD}FILE OPERATIONS:${NC}
  push <local> <remote>      Push file(s) to device
  pull <remote> <local>      Pull file(s) from device
  ls <path>                  List directory on device
  rm <path>                  Remove file on device
  mkdir <path>               Create directory on device
  cat <file>                 Display file content on device

${BOLD}MEDIA & SCREEN:${NC}
  screenshot [name]          Take screenshot
  screenrecord [duration]    Record screen (default: 15s, max: 180s)
  screencap                  Stream screen capture over TCP

${BOLD}LOGCAT & LOGGING:${NC}
  logcat [filter]            Live logcat (default: *:V)
  logcat-clear               Clear logcat buffer
  logcat-save [lines]        Save logcat to file
  logcat-app <pkg>           Filter logcat by app package
  logcat-error               Show only errors/fatals/crashes
  logcat-buffer <buffer>     Use specific buffer (main,system,events,crash)

${BOLD}MONKEY TESTING:${NC}
  monkey [pkg] [events]      Run monkey UI test (default: 1000 events)
  monkey-optimized [pkg]     Optimized monkey with seed

${BOLD}NETWORK:${NC}
  wifi-toggle [on|off]       Toggle WiFi (needs root)
  airplane [on|off]          Toggle airplane mode
  mobile-data [on|off]       Toggle mobile data
  forward <lport> <rport>    Forward port to device
  reverse <rport> <lport>    Reverse tunnel (device→local)
  proxy <host> <port>        Set HTTP proxy
  proxy-off                   Clear HTTP proxy

${BOLD}BACKUP & INSTRUMENTATION:${NC}
  backup <pkg> [output]      Backup app data
  restore <backup.ab>        Restore from backup
  screen-size                Get screen resolution
  dpi                        Get screen density
  fingerprint                Get device fingerprint hash
  dumpsys <service>          Run dumpsys on service
  pm <args>                  Run pm (package manager) directly
  am <args>                  Run am (activity manager) directly
  settings <ns> <k> [v]     Get/set settings value

${BOLD}INTERACTIVE MODE:${NC}
  interactive                Launch interactive menu-driven mode

${BOLD}MISC:${NC}
  help|-h                    Show this help
  version                    Show version

${DIM}Examples:${NC}
  $0 install app1.apk app2.apk app3.apk
  $0 logcat-app com.whatsapp
  $0 interactive
EOF
}

validate_device_connected() { check_device; }
validate_adb_installed() { check_adb; }

# ─── DEVICE MANAGEMENT ───────────────────────────────────────

cmd_devices() {
    check_adb
    log_info "Connected devices:"
    adb devices -l
    log_info "Use: adb -s <serial> <command> for specific device"
}

cmd_info() {
    check_adb
    log_section "DEVICE INFORMATION"
    echo "  ${BOLD}Model:${NC}        $(getprop_s ro.product.model)"
    echo "  ${BOLD}Manufacturer:${NC} $(getprop_s ro.product.manufacturer)"
    echo "  ${BOLD}Brand:${NC}        $(getprop_s ro.product.brand)"
    echo "  ${BOLD}Device:${NC}       $(getprop_s ro.product.device)"
    echo "  ${BOLD}Board:${NC}        $(getprop_s ro.product.board)"
    echo "  ${BOLD}Android:${NC}      $(getprop_s ro.build.version.release)"
    echo "  ${BOLD}SDK:${NC}          $(getprop_s ro.build.version.sdk) (API $(getprop_s ro.build.version.sdk))"
    echo "  ${BOLD}Build:${NC}        $(getprop_s ro.build.display.id)"
    echo "  ${BOLD}Fingerprint:${NC}  $(getprop_s ro.build.fingerprint)"
    echo "  ${BOLD}Security:${NC}     $(getprop_s ro.build.version.security_patch)"
    echo "  ${BOLD}Serial:${NC}       $(adb get-serialno)"
    echo "  ${BOLD}CPU:${NC}          $(getprop_s ro.product.cpu.abi)"
    echo "  ${BOLD}Screen:${NC}       $(getprop_s ro.sf.lcd_density)dpi"
    echo "  ${BOLD}Host:${NC}         $(getprop_s ro.build.host)"
    echo "  ${BOLD}User:${NC}         $(getprop_s ro.build.user)"

    log_section "BATTERY"
    local batt
    batt=$(adb shell dumpsys battery 2>/dev/null)
    echo "$batt" | grep -E "level|temperature|status|health|voltage|current" | sed 's/  */ /g' | while IFS= read -r line; do
        echo "  ${BOLD}${line%%:*}${NC}:${line#*:}"
    done

    log_section "STORAGE"
    adb shell df -h /data /system /sdcard 2>/dev/null | while IFS= read -r line; do
        echo "  $line"
    done

    log_section "NETWORK"
    echo "  ${BOLD}IP:${NC}       $(adb shell ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | tr -d '\r')"
    echo "  ${BOLD}MAC:${NC}      $(adb shell cat /sys/class/net/wlan0/address 2>/dev/null | tr -d '\r')"
    echo "  ${BOLD}Gateway:${NC}  $(adb shell ip route 2>/dev/null | grep default | awk '{print $3}' | tr -d '\r')"

    log_section "SECURITY"
    echo "  ${BOLD}Secure:${NC}     $(getprop_s ro.secure)"
    echo "  ${BOLD}Debuggable:${NC} $(getprop_s ro.debuggable)"
    echo "  ${BOLD}SELinux:${NC}    $(adb shell getenforce 2>/dev/null | tr -d '\r')"
    echo "  ${BOLD}Root:${NC}       $(su_check && echo 'Yes' || echo 'No')"
    echo "  ${BOLD}Encryption:${NC} $(getprop_s ro.crypto.state)"

    log_section "PACKAGE STATS"
    echo "  ${BOLD}Total:${NC}       $(adb shell pm list packages 2>/dev/null | wc -l)"
    echo "  ${BOLD}Third-party:${NC} $(adb shell pm list packages -3 2>/dev/null | wc -l)"
    echo "  ${BOLD}System:${NC}      $(adb shell pm list packages -s 2>/dev/null | wc -l)"
    echo "  ${BOLD}Disabled:${NC}    $(adb shell pm list packages -d 2>/dev/null | wc -l)"
}

cmd_model() { check_device; getprop_s ro.product.model; }
cmd_serial() { check_adb; echo "Serial: $(adb get-serialno)"; }

cmd_battery() {
    check_device
    log_section "BATTERY STATUS"
    local batt
    batt=$(adb shell dumpsys battery 2>/dev/null)
    local level=$(echo "$batt" | grep "level:" | awk '{print $2}')
    local temp=$(echo "$batt" | grep "temperature:" | awk '{print $2}')
    local status=$(echo "$batt" | grep "status:" | awk '{print $2}')
    local health=$(echo "$batt" | grep "health:" | awk '{print $2}')
    local voltage=$(echo "$batt" | grep "voltage:" | awk '{print $2}')

    local status_str; local health_str
    case "$status" in
        1) status_str="Unknown";; 2) status_str="Charging";; 3) status_str="Discharging";;
        4) status_str="Not Charging";; 5) status_str="Full";;
        *) status_str="Unknown";;
    esac
    case "$health" in
        1) health_str="Unknown";; 2) health_str="Good";; 3) health_str="Overheat";;
        4) health_str="Dead";; 5) health_str="Over Voltage";; 6) health_str="Unspecified Failure";;
        7) health_str="Cold";;
        *) health_str="Unknown";;
    esac

    echo "  ${BOLD}Level:${NC}       ${level}%"
    echo "  ${BOLD}Temperature:${NC} $((temp / 10)).$((temp % 10))°C"
    echo "  ${BOLD}Status:${NC}      $status_str"
    echo "  ${BOLD}Health:${NC}      $health_str"
    echo "  ${BOLD}Voltage:${NC}     $((voltage / 1000)).$((voltage % 1000 / 100))V"

    echo -n "  ${BOLD}Graph:${NC}       "
    local filled=$((level / 5))
    for ((i=0; i<filled; i++)); do echo -n "${GREEN}█${NC}"; done
    for ((i=filled; i<20; i++)); do echo -n "${DIM}░${NC}"; done
    echo " ${level}%"
}

cmd_screen_state() {
    check_device
    local state=$(adb shell dumpsys display 2>/dev/null | grep "mScreenState\|mScreenOn" | head -1)
    if echo "$state" | grep -qi "ON"; then
        log_ok "Screen is ON"
    else
        log_info "Screen is OFF"
    fi
}

cmd_uptime() {
    check_device
    local uptime
    uptime=$(adb shell uptime 2>/dev/null | tr -d '\r')
    echo "$uptime"
}

cmd_reboot() {
    check_device
    local mode="${1:-}"
    case "$mode" in
        bootloader) log_warn "Rebooting to bootloader..."; adb reboot bootloader;;
        recovery)   log_warn "Rebooting to recovery..."; adb reboot recovery;;
        sideload)   log_warn "Rebooting to sideload..."; adb reboot sideload;;
        "")         log_warn "Rebooting device..."; adb reboot;;
        *)          log_err "Unknown mode: $mode (bootloader|recovery|sideload)"; exit 1;;
    esac
}

cmd_root() {
    check_device
    if su_check; then
        log_ok "Device has root access"
        adb shell "su -c 'id'" 2>/dev/null || log_warn "Root binary present but may need su grant"
    else
        log_warn "Root not detected"
    fi
}

# ─── APP MANAGEMENT ──────────────────────────────────────────

cmd_install() {
    check_device
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 install <apk1> [apk2] ..."
        exit 1
    fi
    local total=$#
    local success=0; local failed=0
    log_section "BATCH INSTALL ($total APK(s))"
    for apk in "$@"; do
        if [[ ! -f "$apk" ]]; then
            log_fail "APK not found: $apk"
            ((failed++)) || true
            continue
        fi
        log_progress "Installing $(basename "$apk")"
        if adb install -r -t "$apk" &>/dev/null; then
            log_done "Installed: $(basename "$apk")"
            ((success++)) || true
        else
            log_fail "Failed: $(basename "$apk")"
            ((failed++)) || true
        fi
    done
    echo
    log_info "Results: ${GREEN}$success succeeded${NC}, ${RED}$failed failed${NC}, $total total"
}

cmd_uninstall() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 uninstall <package>"
        exit 1
    fi
    check_device
    local pkg="$1"
    log_progress "Uninstalling $pkg"
    if adb uninstall "$pkg" &>/dev/null; then
        log_done "Uninstalled: $pkg"
    else
        log_fail "Failed to uninstall $pkg"
    fi
}

cmd_list_packages() {
    check_device
    local filter="${1:-}"
    if [[ -n "$filter" ]]; then
        adb shell pm list packages 2>/dev/null | grep -i "$filter" | sed 's/package://' | sort
    else
        adb shell pm list packages 2>/dev/null | sed 's/package://' | sort
    fi
}

cmd_list_thirdparty() {
    check_device
    adb shell pm list packages -3 -f 2>/dev/null | sed 's/.*=//' | sort
}

cmd_list_debuggable() {
    check_device
    adb shell pm list packages -d 2>/dev/null | sed 's/package://'
}

cmd_list_disabled() {
    check_device
    adb shell pm list packages -d 2>/dev/null | sed 's/package://' | sort
}

cmd_list_system() {
    check_device
    adb shell pm list packages -s 2>/dev/null | sed 's/package://' | sort
}

cmd_clear() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 clear <package>"
        exit 1
    fi
    check_device
    local pkg="$1"
    log_progress "Clearing data for $pkg"
    adb shell pm clear "$pkg" 2>/dev/null && log_done "Data cleared for $pkg" || log_fail "Failed to clear data for $pkg"
}

cmd_grant() {
    if [[ $# -lt 2 ]]; then
        log_err "Usage: $0 grant <package> <permission>"
        exit 1
    fi
    check_device
    log_info "Granting $2 to $1"
    adb shell pm grant "$1" "$2" && log_ok "Granted" || log_err "Failed to grant"
}

cmd_revoke() {
    if [[ $# -lt 2 ]]; then
        log_err "Usage: $0 revoke <package> <permission>"
        exit 1
    fi
    check_device
    log_info "Revoking $2 from $1"
    adb shell pm revoke "$1" "$2" && log_ok "Revoked" || log_err "Failed to revoke"
}

cmd_disable() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 disable <package>"
        exit 1
    fi
    check_device
    log_progress "Disabling $1"
    adb shell pm disable-user --user 0 "$1" &>/dev/null && log_done "Disabled $1" || log_fail "Failed to disable $1"
}

cmd_enable() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 enable <package>"
        exit 1
    fi
    check_device
    log_progress "Enabling $1"
    adb shell pm enable --user 0 "$1" &>/dev/null && log_done "Enabled $1" || log_fail "Failed to enable $1"
}

# ─── ACTIVITY MANAGEMENT ─────────────────────────────────────

cmd_start() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 start <component|package>"
        exit 1
    fi
    check_device
    local target="$1"
    if [[ "$target" == */* ]]; then
        log_info "Starting: $target"
        adb shell am start -n "$target" 2>/dev/null && log_ok "Started" || log_err "Failed to start"
    else
        log_info "Opening: $target"
        adb shell monkey -p "$target" -c android.intent.category.LAUNCHER 1 2>/dev/null && log_ok "Opened" || log_err "Failed to open"
    fi
}

cmd_stop() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 stop <package>"
        exit 1
    fi
    check_device
    log_progress "Stopping $1"
    adb shell am force-stop "$1" && log_done "Stopped $1" || log_fail "Failed to stop $1"
}

cmd_restart() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 restart <package>"
        exit 1
    fi
    check_device
    log_info "Restarting $1..."
    adb shell am force-stop "$1" 2>/dev/null || true
    sleep 1
    adb shell monkey -p "$1" -c android.intent.category.LAUNCHER 1 2>/dev/null && log_ok "Restarted $1" || log_err "Failed to restart $1"
}

cmd_top_activity() {
    check_device
    log_section "TOP ACTIVITY"
    adb shell dumpsys activity activities 2>/dev/null | grep -E "mResumedActivity|mFocusedActivity|topActivity" | head -5
    echo
    log_info "Processes:"
    adb shell dumpsys activity processes 2>/dev/null | grep "ProcessRecord" | head -10
}

cmd_open_url() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 open-url <url>"
        exit 1
    fi
    check_device
    log_info "Opening URL: $1"
    adb shell am start -a android.intent.action.VIEW -d "$1" 2>/dev/null && log_ok "Opened" || log_err "Failed"
}

cmd_dial() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 dial <number>"
        exit 1
    fi
    check_device
    log_info "Dialing: $1"
    adb shell am start -a android.intent.action.DIAL -d "tel:$1" 2>/dev/null && log_ok "Dialer opened" || log_err "Failed"
}

cmd_send_sms() {
    if [[ $# -lt 2 ]]; then
        log_err "Usage: $0 send-sms <number> <message>"
        exit 1
    fi
    check_device
    local num="$1"; shift
    local msg="$*"
    log_info "Opening SMS to $num"
    adb shell am start -a android.intent.action.SENDTO -d "sms:$num" --es sms_body "$msg" 2>/dev/null && log_ok "SMS composer opened" || log_err "Failed"
}

# ─── FILE OPERATIONS ─────────────────────────────────────────

cmd_push() {
    if [[ $# -lt 2 ]]; then
        log_err "Usage: $0 push <local> <remote>"
        exit 1
    fi
    check_device
    local local_path="$1"
    local remote_path="$2"
    if [[ ! -f "$local_path" && ! -d "$local_path" ]]; then
        log_err "Not found: $local_path"
        exit 1
    fi
    log_progress "Pushing $local_path → $remote_path"
    if adb push "$local_path" "$remote_path" &>/dev/null; then
        log_done "Pushed to $remote_path"
    else
        log_fail "Push failed"
    fi
}

cmd_pull() {
    if [[ $# -lt 2 ]]; then
        log_err "Usage: $0 pull <remote> <local>"
        exit 1
    fi
    check_device
    log_progress "Pulling $1 → $2"
    if adb pull "$1" "$2" &>/dev/null; then
        log_done "Pulled to $2"
    else
        log_fail "Pull failed"
    fi
}

cmd_ls() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 ls <path>"
        exit 1
    fi
    check_device
    adb shell ls -la "$1" 2>/dev/null || log_err "Cannot list $1"
}

cmd_rm() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 rm <path>"
        exit 1
    fi
    check_device
    adb shell rm -rf "$1" 2>/dev/null && log_ok "Removed: $1" || log_err "Failed to remove: $1"
}

cmd_mkdir() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 mkdir <path>"
        exit 1
    fi
    check_device
    adb shell mkdir -p "$1" 2>/dev/null && log_ok "Created: $1" || log_err "Failed: $1"
}

cmd_cat() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 cat <file>"
        exit 1
    fi
    check_device
    adb shell cat "$1" 2>/dev/null || log_err "Cannot read: $1"
}

# ─── MEDIA & SCREEN ──────────────────────────────────────────

cmd_screenshot() {
    check_device
    local name="${1:-screenshot_$(date +%Y%m%d_%H%M%S)}"
    local remote="/sdcard/${name}.png"
    local local_file="$OUT_DIR/${name}.png"
    mkdir -p "$OUT_DIR"

    log_progress "Taking screenshot"
    adb shell screencap -p "$remote" 2>/dev/null
    adb pull "$remote" "$local_file" &>/dev/null
    adb shell rm "$remote" 2>/dev/null

    if [[ -f "$local_file" ]]; then
        local size=$(stat -c%s "$local_file" 2>/dev/null)
        log_done "Screenshot: $local_file ($((size/1024))KB)"
    else
        log_fail "Screenshot failed"
    fi
}

cmd_screenrecord() {
    check_device
    local duration="${1:-15}"
    if [[ $duration -gt 180 ]]; then
        log_warn "Max duration is 180s, capping"
        duration=180
    fi
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local remote="/sdcard/record_${timestamp}.mp4"
    local local_file="$OUT_DIR/record_${timestamp}.mp4"
    mkdir -p "$OUT_DIR"

    log_info "Recording screen for ${duration}s (press Ctrl+C to stop early)..."
    adb shell screenrecord --time-limit "$duration" --bit-rate 4000000 "$remote" &
    local pid=$!

    # Show progress
    for ((i=1; i<=duration; i++)); do
        echo -ne "\r  ${DIM}Recording: $i/${duration}s${NC}  "
        sleep 1
    done
    echo
    wait $pid 2>/dev/null || true
    sleep 1

    log_progress "Pulling recording"
    adb pull "$remote" "$local_file" &>/dev/null
    adb shell rm "$remote" 2>/dev/null

    if [[ -f "$local_file" ]]; then
        local size=$(stat -c%s "$local_file" 2>/dev/null)
        log_done "Recording: $local_file ($((size/1024/1024))MB)"
    else
        log_fail "Recording failed"
    fi
}

cmd_screencap() {
    check_device
    log_info "Streaming screen capture (Ctrl+C to stop)..."
    adb exec-out screencap 2>/dev/null || log_err "Streaming not supported"
}

# ─── LOGCAT ──────────────────────────────────────────────────

cmd_logcat() {
    check_device
    local filter="${1:-*:V}"
    log_info "Live logcat (filter: ${filter}) — Ctrl+C to stop"
    adb logcat -v threadtime "$filter" 2>/dev/null || true
}

cmd_logcat_clear() {
    check_device
    adb logcat -c 2>/dev/null && log_ok "Logcat buffer cleared" || log_err "Failed to clear"
}

cmd_logcat_save() {
    check_device
    local lines="${1:-500}"
    local out="$OUT_DIR/logcat_$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$OUT_DIR"
    log_progress "Capturing $lines lines"
    adb logcat -d -v threadtime 2>/dev/null | tail -"$lines" > "$out"
    local count=$(wc -l < "$out")
    log_done "Saved: $out ($count lines)"
}

cmd_logcat_app() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 logcat-app <package> [lines]"
        exit 1
    fi
    check_device
    local pkg="$1"
    local lines="${2:-100}"
    log_section "LOGCAT FOR: $pkg"
    adb logcat -d -v threadtime 2>/dev/null | grep -i "$pkg" | tail -"$lines" || log_info "No matching entries"
}

cmd_logcat_error() {
    check_device
    local lines="${1:-100}"
    log_section "ERRORS & CRASHES"
    adb logcat -d -v threadtime 2>/dev/null | grep -iE "FATAL|ERROR|CRASH|Exception|nativeCrash|ANR|at |Caused by" | tail -"$lines" || log_info "No errors found"
}

cmd_logcat_buffer() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 logcat-buffer <buffer> (main,system,events,crash,all)"
        exit 1
    fi
    check_device
    local buf="$1"
    adb logcat -d -b "$buf" -v threadtime 2>/dev/null || log_err "Buffer '$buf' not available"
}

# ─── MONKEY TESTING ──────────────────────────────────────────

cmd_monkey() {
    check_device
    local pkg="${1:-}"
    local events="${2:-1000}"

    if [[ -z "$pkg" ]]; then
        log_info "Running monkey on entire system ($events events)..."
        adb shell monkey --throttle 100 --ignore-security-exceptions --ignore-crashes --ignore-timeouts -v "$events" 2>&1 | tail -5
    else
        log_info "Running monkey on $pkg ($events events)..."
        adb shell monkey -p "$pkg" --throttle 100 --ignore-security-exceptions --ignore-crashes -v "$events" 2>&1 | tail -5
    fi
}

cmd_monkey_optimized() {
    check_device
    local pkg="${1:-}"
    local seed=$((RANDOM % 10000))
    local events="1500"
    local throttle="200"

    log_section "OPTIMIZED MONKEY TEST"
    echo "  ${BOLD}Seed:${NC}     $seed"
    echo "  ${BOLD}Events:${NC}   $events"
    echo "  ${BOLD}Throttle:${NC} ${throttle}ms"
    echo "  ${BOLD}Package:${NC}  ${pkg:-All}"

    if [[ -n "$pkg" ]]; then
        adb shell monkey -p "$pkg" -s "$seed" --throttle "$throttle" \
            --ignore-security-exceptions --ignore-crashes \
            --pct-touch 30 --pct-motion 20 --pct-nav 10 --pct-majornav 10 \
            --pct-syskeys 5 --pct-appswitch 15 --pct-anyevent 10 \
            -v "$events" 2>&1 | tail -10
    else
        adb shell monkey -s "$seed" --throttle "$throttle" \
            --ignore-security-exceptions --ignore-crashes \
            --pct-touch 30 --pct-motion 20 --pct-nav 10 --pct-majornav 10 \
            --pct-syskeys 5 --pct-appswitch 15 --pct-anyevent 10 \
            -v "$events" 2>&1 | tail -10
    fi
}

# ─── NETWORK ─────────────────────────────────────────────────

cmd_wifi_toggle() {
    check_device
    local action="${1:-toggle}"
    case "$action" in
        on|enable)  adb shell su -c 'svc wifi enable' 2>/dev/null && log_ok "WiFi enabled" || log_err "Failed (needs root)";;
        off|disable) adb shell su -c 'svc wifi disable' 2>/dev/null && log_ok "WiFi disabled" || log_err "Failed (needs root)";;
        toggle)     adb shell su -c 'svc wifi toggle' 2>/dev/null && log_ok "WiFi toggled" || log_err "Failed (needs root)";;
        *)          log_err "Usage: wifi-toggle [on|off|toggle]"; exit 1;;
    esac
}

cmd_airplane() {
    check_device
    local action="${1:-toggle}"
    case "$action" in
        on|enable)  adb shell settings put global airplane_mode_on 1 && adb shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true 2>/dev/null && log_ok "Airplane mode ON";;
        off|disable) adb shell settings put global airplane_mode_on 0 && adb shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false 2>/dev/null && log_ok "Airplane mode OFF";;
        toggle)     log_info "Toggling airplane mode..."; adb shell cmd connectivity airplane-mode 2>/dev/null || log_err "Not supported";;
        *)          log_err "Usage: airplane [on|off]"; exit 1;;
    esac
}

cmd_mobile_data() {
    check_device
    local action="${1:-toggle}"
    case "$action" in
        on|enable)  adb shell su -c 'svc data enable' 2>/dev/null && log_ok "Mobile data ON" || log_err "Failed (needs root)";;
        off|disable) adb shell su -c 'svc data disable' 2>/dev/null && log_ok "Mobile data OFF" || log_err "Failed (needs root)";;
        *)          log_err "Usage: mobile-data [on|off]"; exit 1;;
    esac
}

cmd_forward() {
    check_device
    local lport="${1:-8888}"
    local rport="${2:-8888}"
    log_info "Forwarding tcp:localhost:$lport → tcp:device:$rport"
    adb forward "tcp:$lport" "tcp:$rport" && log_ok "Forward established" || log_err "Forward failed"
}

cmd_reverse() {
    check_device
    local rport="${1:-8888}"
    local lport="${2:-8888}"
    log_info "Reverse: tcp:device:$rport → tcp:localhost:$lport"
    adb reverse "tcp:$rport" "tcp:$lport" && log_ok "Reverse established" || log_err "Reverse failed"
}

cmd_proxy() {
    check_device
    if [[ $# -lt 2 ]]; then
        log_err "Usage: $0 proxy <host> <port>"
        exit 1
    fi
    log_info "Setting proxy: $1:$2"
    adb shell settings put global http_proxy "$1:$2" && log_ok "Proxy set" || log_err "Failed"
}

cmd_proxy_off() {
    check_device
    adb shell settings put global http_proxy :0 && log_ok "Proxy cleared" || log_err "Failed"
}

# ─── BACKUP ──────────────────────────────────────────────────

cmd_backup() {
    check_device
    local pkg="${1:?Usage: $0 backup <package> [output] }"
    local output="${2:-$OUT_DIR/backup_${pkg}_$(date +%Y%m%d_%H%M%S).ab}"
    mkdir -p "$OUT_DIR"
    log_progress "Backing up $pkg"
    adb backup -f "$output" -noapk "$pkg" 2>/dev/null && log_done "Backup saved: $output" || log_fail "Backup failed"
}

cmd_restore() {
    check_device
    local backup="${1:?Usage: $0 restore <backup.ab>}"
    [[ ! -f "$backup" ]] && { log_err "Backup not found: $backup"; exit 1; }
    log_info "Restoring: $backup"
    adb restore "$backup" && log_ok "Restore initiated" || log_err "Restore failed"
}

# ─── MISC ────────────────────────────────────────────────────

cmd_screen_size() {
    check_device
    adb shell wm size 2>/dev/null | tr -d '\r'
}

cmd_dpi() {
    check_device
    adb shell wm density 2>/dev/null | tr -d '\r'
}

cmd_fingerprint() {
    check_device
    getprop_s ro.build.fingerprint
}

cmd_dumpsys() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 dumpsys <service>"
        echo "Available: battery, wifi, activity, package, window, meminfo, diskstats, cpuinfo, power, alarm, ..."
        exit 1
    fi
    check_device
    adb shell dumpsys "$@" 2>/dev/null | head -100
}

cmd_pm() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 pm <args>"
        exit 1
    fi
    check_device
    adb shell pm "$@"
}

cmd_am() {
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 am <args>"
        exit 1
    fi
    check_device
    adb shell am "$@"
}

cmd_settings() {
    if [[ $# -lt 2 ]]; then
        log_err "Usage: $0 settings <namespace> <key> [value]"
        echo "  namespaces: system, secure, global"
        exit 1
    fi
    check_device
    local ns="$1"; local key="$2"; local val="${3:-}"
    if [[ -n "$val" ]]; then
        adb shell settings put "$ns" "$key" "$val" && log_ok "Set $ns/$key = $val" || log_err "Failed"
    else
        adb shell settings get "$ns" "$key" 2>/dev/null | tr -d '\r'
    fi
}

cmd_version() {
    echo "ADB Toolkit v${VERSION}"
    echo "AndroXploit — Advanced ADB Command Center"
}

# ─── INTERACTIVE MODE ────────────────────────────────────────

cmd_interactive() {
    check_adb

    local opts=(
        "Device Info" "Battery Status" "Screen Info"
        "Take Screenshot" "Screen Record" "List Packages"
        "List Third-Party" "Start App" "Stop App"
        "Clear App Data" "Monkey Test" "Logcat Live"
        "Logcat Errors" "Save Logcat" "Push File"
        "Pull File" "Port Forward" "Set Proxy"
        "Clear Proxy" "Reboot Device" "Exit"
    )

    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║     ${BOLD}ADB TOOLKIT — INTERACTIVE MODE${NC}     ${BLUE}║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo

        local i=1
        for opt in "${opts[@]}"; do
            if [[ "$opt" == "---" ]]; then
                echo -e "${DIM}  ──────────────────────────${NC}"
            else
                echo -e "  ${CYAN}$i)${NC} $opt"
            fi
            ((i++)) || true
        done
        echo
        read -r -p "$(echo -e "${YELLOW}Select option [1-${#opts[@]}]:${NC} ")" choice

        case "$choice" in
            1) clear 2>/dev/null; cmd_info; read -p "Press Enter...";;
            2) clear 2>/dev/null; cmd_battery; read -p "Press Enter...";;
            3) clear 2>/dev/null; cmd_screen_state; cmd_screen_size; cmd_dpi; read -p "Press Enter...";;
            4) clear 2>/dev/null; cmd_screenshot; read -p "Press Enter...";;
            5) clear 2>/dev/null; read -p "Duration (seconds, default 15): " dur; cmd_screenrecord "${dur:-15}"; read -p "Press Enter...";;
            6) clear 2>/dev/null; cmd_list_packages | head -50; read -p "Press Enter...";;
            7) clear 2>/dev/null; cmd_list_thirdparty; read -p "Press Enter...";;
            8) clear 2>/dev/null; read -p "Package: " pkg; cmd_start "$pkg"; read -p "Press Enter...";;
            9) clear 2>/dev/null; read -p "Package: " pkg; cmd_stop "$pkg"; read -p "Press Enter...";;
            10) clear 2>/dev/null; read -p "Package: " pkg; cmd_clear "$pkg"; read -p "Press Enter...";;
            11) clear 2>/dev/null; read -p "Package (optional): " pkg; read -p "Events (default 1000): " ev; cmd_monkey "${pkg:-}" "${ev:-1000}"; read -p "Press Enter...";;
            12) clear 2>/dev/null; cmd_logcat; read -p "Press Enter...";;
            13) clear 2>/dev/null; cmd_logcat_error; read -p "Press Enter...";;
            14) clear 2>/dev/null; cmd_logcat_save; read -p "Press Enter...";;
            15) clear 2>/dev/null; read -p "Local file: " local_f; read -p "Remote path: " remote_f; cmd_push "$local_f" "$remote_f"; read -p "Press Enter...";;
            16) clear 2>/dev/null; read -p "Remote path: " remote_f; read -p "Local path: " local_f; cmd_pull "$remote_f" "$local_f"; read -p "Press Enter...";;
            17) clear 2>/dev/null; read -p "Local port: " lp; read -p "Remote port: " rp; cmd_forward "${lp:-8888}" "${rp:-8888}"; read -p "Press Enter...";;
            18) clear 2>/dev/null; read -p "Proxy host: " ph; read -p "Proxy port: " pp; cmd_proxy "$ph" "$pp"; read -p "Press Enter...";;
            19) clear 2>/dev/null; cmd_proxy_off; read -p "Press Enter...";;
            20) clear 2>/dev/null; read -p "Mode (bootloader/recovery/none): " mode; cmd_reboot "$mode";;
            21|q|Q|quit|exit) log_ok "Goodbye!"; exit 0;;
            *) log_warn "Invalid option"; sleep 1;;
        esac
    done
}

# ─── MAIN ────────────────────────────────────────────────────

main() {
    if [[ $# -lt 1 ]]; then
        show_help
        exit 0
    fi

    local cmd="$1"
    shift

    case "$cmd" in
        # Device Management
        devices)        check_adb; cmd_devices;;
        info|device)    check_adb; cmd_info;;
        model)          cmd_model;;
        serial)         cmd_serial;;
        battery)        cmd_battery;;
        screen-state)   cmd_screen_state;;
        uptime)         cmd_uptime;;
        reboot)         cmd_reboot "$@";;
        root)           cmd_root;;

        # App Management
        install)        cmd_install "$@";;
        uninstall)      cmd_uninstall "$@";;
        list-packages|packages) cmd_list_packages "$@";;
        list-thirdparty|thirdparty) cmd_list_thirdparty;;
        list-debuggable|debuggable) cmd_list_debuggable;;
        list-disabled|disabled) cmd_list_disabled;;
        list-system|system) cmd_list_system;;
        clear)          cmd_clear "$@";;
        grant)          cmd_grant "$@";;
        revoke)         cmd_revoke "$@";;
        disable)        cmd_disable "$@";;
        enable)         cmd_enable "$@";;

        # Activity
        start|open)     cmd_start "$@";;
        stop|force-stop) cmd_stop "$@";;
        restart)        cmd_restart "$@";;
        top-activity|top) cmd_top_activity;;
        open-url|url)   cmd_open_url "$@";;
        dial|call)      cmd_dial "$@";;
        send-sms)       cmd_send_sms "$@";;

        # Files
        push)           cmd_push "$@";;
        pull)           cmd_pull "$@";;
        ls|list)        cmd_ls "$@";;
        rm|delete)      cmd_rm "$@";;
        mkdir)          cmd_mkdir "$@";;
        cat|show)       cmd_cat "$@";;

        # Media
        screenshot|ss)  cmd_screenshot "$@";;
        screenrecord|record) cmd_screenrecord "$@";;
        screencap|scap) cmd_screencap;;

        # Logcat
        logcat)         cmd_logcat "$@";;
        logcat-clear|logcatc) cmd_logcat_clear;;
        logcat-save|logcats) cmd_logcat_save "$@";;
        logcat-app|lapp) cmd_logcat_app "$@";;
        logcat-error|lerror|lcrash) cmd_logcat_error "$@";;
        logcat-buffer|lbuf) cmd_logcat_buffer "$@";;

        # Monkey
        monkey)         cmd_monkey "$@";;
        monkey-optimized|monkey-opt) cmd_monkey_optimized "$@";;

        # Network
        wifi-toggle|wifi) cmd_wifi_toggle "$@";;
        airplane|airplane-mode) cmd_airplane "$@";;
        mobile-data|data) cmd_mobile_data "$@";;
        forward|fwd)    cmd_forward "$@";;
        reverse|rev)    cmd_reverse "$@";;
        proxy)          cmd_proxy "$@";;
        proxy-off)      cmd_proxy_off;;

        # Backup
        backup)         cmd_backup "$@";;
        restore)        cmd_restore "$@";;

        # Misc
        screen-size|res) cmd_screen_size;;
        dpi|density)    cmd_dpi;;
        fingerprint)    cmd_fingerprint;;
        dumpsys)        cmd_dumpsys "$@";;
        pm)             cmd_pm "$@";;
        am)             cmd_am "$@";;
        settings)       cmd_settings "$@";;

        # Interactive
        interactive|menu|i) cmd_interactive;;

        # Help
        help|--help|-h) show_help;;
        version|--version|-v) cmd_version;;

        *)
            log_err "Unknown command: $cmd"
            echo
            show_help
            exit 1
            ;;
    esac
}

main "$@"
