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

OUT_DIR="output/logs"
mkdir -p "$OUT_DIR"

show_help() {
    cat <<EOF
${BOLD}Emulator Manager v${VERSION}${NC} — Full Android Emulator Control
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 <command> [args]

${BOLD}MANAGEMENT:${NC}
  list                          List AVDs and connected devices
  create [name] [api] [arch]    Create new emulator (default: API 34, x86_64)
  start [name] [opts]           Start emulator
  stop                          Stop all emulators
  delete <name>                 Delete emulator AVD
  wipe <name>                   Wipe and recreate emulator
  info                          Show emulator info from connected device
  rename <old> <new>            Rename emulator AVD

${BOLD}START OPTIONS:${NC}
  start-headless <name>         Start emulator without GUI (no-window)
  start-snapshot <name>         Start from last snapshot (quick boot)
  start-cold <name>             Cold boot (no snapshot)
  start-writable <name>         Start with writable system

${BOLD}SIMULATION:${NC}
  gps <lat> <lon>               Set GPS location
  sms <number> <message>        Send SMS to emulator
  call <number>                 Simulate incoming call
  battery <level>               Set battery level (0-100)
  network <type>                Set network speed (edge, gprs, hsdpa, lte, full)
  fingerprint <id>              Simulate fingerprint touch

${BOLD}SNAPSHOT & STATE:${NC}
  snapshot-save <name>          Save emulator snapshot
  snapshot-load <name>          Load emulator snapshot
  snapshot-list                 List snapshots
  snapshot-delete <name>        Delete snapshot

${BOLD}CONFIGURATION:${NC}
  proxy <host> <port>           Set HTTP proxy on emulator
  proxy-off                     Clear HTTP proxy
  scale <percent>               Set emulator window scale
  language <lang> <country>     Set device language (e.g., en US)

${DIM}Network types:${NC} edge, gprs, hsdpa, hsupa, lte, full, umts, hspa
${DIM}Examples:${NC}
  $0 create MyDevice 34 x86_64
  $0 start-headless Pixel_API_34
  $0 gps -6.2088 106.8456       # Jakarta
  $0 battery 15                 # Low battery simulation
EOF
}

check_adb() {
    if ! command -v adb &>/dev/null; then log_err "ADB not found."; exit 1; fi
}
check_device() { adb get-state &>/dev/null || { log_err "No device connected."; exit 1; }; }
check_emulator() { command -v emulator &>/dev/null || { log_err "emulator not found. Set ANDROID_SDK_ROOT"; exit 1; }; }
check_avdmanager() { command -v avdmanager &>/dev/null || { log_err "avdmanager not found."; exit 1; }; }
check_sdkmanager() { command -v sdkmanager &>/dev/null || log_warn "sdkmanager not found."; }

get_device_prop() { adb shell getprop "$1" 2>/dev/null | tr -d '\r'; }

# ─── MANAGEMENT ─────────────────────────────────────────────

cmd_list() {
    log_section "EMULATORS & DEVICES"
    echo -e "  ${BOLD}Available AVDs:${NC}"
    local avds; avds=$(emulator -list-avds 2>/dev/null)
    if [[ -n "$avds" ]]; then
        echo "$avds" | sed 's/^/    /'
    else
        echo "    ${YELLOW}(none)${NC}"
    fi
    echo
    echo -e "  ${BOLD}Connected:${NC}"
    adb devices -l 2>/dev/null | tail -n +2 | sed 's/^/    /' || echo "    (none)"
}

cmd_create() {
    local name="${1:-AndroXploit_$(date +%s)}"
    local api="${2:-34}"
    local arch="${3:-x86_64}"

    check_avdmanager; check_sdkmanager

    local pkg="system-images;android-${api};google_apis;${arch}"

    log_section "CREATE EMULATOR"
    echo "  ${BOLD}Name:${NC} $name"
    echo "  ${BOLD}API:${NC}  $api"
    echo "  ${BOLD}Arch:${NC} $arch"
    echo "  ${BOLD}Image:${NC} $pkg"
    echo

    # Check if system image is installed
    if ! sdkmanager --list 2>/dev/null | grep -q "$pkg"; then
        log_warn "System image not installed: $pkg"
        read -p "Download now? (Y/n): " yn
        if [[ "$yn" != "n" ]]; then
            log_info "Downloading system image (this may take a while)..."
            sdkmanager "$pkg" 2>&1 | tail -5
        else
            log_err "System image required. Install: sdkmanager '$pkg'"
            exit 1
        fi
    fi

    log_progress "Creating AVD"
    if echo "no" | avdmanager create avd -n "$name" -k "$pkg" -d "pixel_6" -f 2>&1; then
        log_done "Emulator created: $name"
        echo
        echo "  ${BOLD}Start:${NC}   $0 start $name"
        echo "  ${BOLD}Delete:${NC}  $0 delete $name"
    else
        log_fail "Failed to create emulator"
        exit 1
    fi
}

# ─── START / STOP ───────────────────────────────────────────

cmd_start() {
    check_emulator
    local name="${1:-}"
    local extra_args="${2:-}"

    if [[ -z "$name" ]]; then
        name=$(emulator -list-avds 2>/dev/null | head -1)
        [[ -z "$name" ]] && { log_err "No emulators found. Create one first."; exit 1; }
        log_info "Starting first available: $name"
    fi

    log_section "START EMULATOR: $name"
    log_info "Extra args: ${extra_args:-none}"
    echo

    local logfile="$OUT_DIR/emulator_${name}.log"
    log_progress "Launching emulator"

    nohup emulator -avd "$name" -no-snapshot -netdelay none -netspeed full $extra_args \
        >"$logfile" 2>&1 &

    local pid=$!
    log_done "Emulator starting (PID: $pid)"
    echo "  ${BOLD}Log:${NC}    $logfile"
    echo "  ${BOLD}Monitor:${NC} adb logcat"
    echo

    # Wait for boot
    log_progress "Waiting for device"
    for ((i=0; i<60; i++)); do
        if adb get-state 2>/dev/null | grep -q device; then
            log_done "Device connected after ${i}s"
            break
        fi
        sleep 2
    done

    # Wait for boot complete
    if adb get-state 2>/dev/null | grep -q device; then
        log_progress "Waiting for boot completion"
        for ((i=0; i<120; i++)); do
            local boot; boot=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
            if [[ "$boot" == "1" ]]; then
                log_done "Boot complete after ${i}s"
                echo "  ${BOLD}Model:${NC} $(get_device_prop ro.product.model)"
                break
            fi
            sleep 2
        done
    fi
}

cmd_start_headless() { cmd_start "${1:-}" "-no-window -no-audio"; }

cmd_start_snapshot() {
    check_emulator
    local name="${1:-}"
    [[ -z "$name" ]] && { name=$(emulator -list-avds | head -1); [[ -z "$name" ]] && { log_err "No emulators"; exit 1; }; }
    log_info "Starting $name from snapshot (quick boot)..."
    nohup emulator -avd "$name" -netdelay none -netspeed full \
        >"$OUT_DIR/emulator_${name}.log" 2>&1 &
    log_ok "Starting (PID: $!)"
}

cmd_start_cold() {
    local name="${1:-}"
    [[ -z "$name" ]] && { name=$(emulator -list-avds | head -1); [[ -z "$name" ]] && { log_err "No emulators"; exit 1; }; }
    log_info "Cold booting $name..."
    nohup emulator -avd "$name" -no-snapshot -netdelay none -netspeed full \
        >"$OUT_DIR/emulator_${name}.log" 2>&1 &
    log_ok "Cold boot starting (PID: $!)"
}

cmd_start_writable() {
    local name="${1:-}"
    [[ -z "$name" ]] && { log_err "Usage: $0 start-writable <name>"; exit 1; }
    log_info "Starting $name with writable system..."
    nohup emulator -avd "$name" -writable-system -netdelay none -netspeed full \
        >"$OUT_DIR/emulator_${name}.log" 2>&1 &
    log_ok "Starting writable (PID: $!)"
}

cmd_stop() {
    log_section "STOP EMULATORS"
    log_progress "Stopping"
    adb emu kill 2>/dev/null || true
    sleep 2
    pkill -f "qemu-system" 2>/dev/null || true
    pkill -f "emulator.*-avd" 2>/dev/null || true
    sleep 1
    if pgrep -f "qemu-system" &>/dev/null; then
        log_warn "Some processes still running. Force kill..."
        pkill -9 -f "qemu-system" 2>/dev/null || true
    fi
    log_done "All emulators stopped"
}

cmd_delete() {
    local name="${1:?Usage: $0 delete <name>}"
    check_avdmanager
    log_warn "Deleting AVD: $name"
    read -p "Confirm? (y/N): " yn; [[ "$yn" != "y" ]] && exit 0
    avdmanager delete avd -n "$name" && log_ok "Deleted: $name" || log_err "Failed to delete"
}

cmd_wipe() {
    local name="${1:?Usage: $0 wipe <name>}"
    local api="${2:-34}" arch="${3:-x86_64}"
    check_avdmanager
    log_warn "Wiping emulator: $name"
    avdmanager delete avd -n "$name" 2>/dev/null || true
    cmd_create "$name" "$api" "$arch"
}

cmd_rename() {
    local old="${1:?Usage: $0 rename <old> <new>}"
    local new="${2:?Usage: $0 rename <old> <new>}"
    check_avdmanager
    log_info "Renaming $old → $new"
    mv "$HOME/.android/avd/${old}.avd" "$HOME/.android/avd/${new}.avd" 2>/dev/null || true
    mv "$HOME/.android/avd/${old}.ini" "$HOME/.android/avd/${new}.ini" 2>/dev/null || true
    sed -i "s/${old}/${new}/g" "$HOME/.android/avd/${new}.ini" 2>/dev/null || true
    sed -i "s/${old}/${new}/g" "$HOME/.android/avd/${new}.avd/config.ini" 2>/dev/null || true
    log_ok "Renamed to $new"
}

cmd_info() {
    check_device
    log_section "EMULATOR INFO"
    echo "  ${BOLD}Model:${NC}    $(get_device_prop ro.product.model)"
    echo "  ${BOLD}Android:${NC}  $(get_device_prop ro.build.version.release)"
    echo "  ${BOLD}SDK:${NC}      $(get_device_prop ro.build.version.sdk)"
    echo "  ${BOLD}Arch:${NC}     $(get_device_prop ro.product.cpu.abi)"
    echo "  ${BOLD}Build:${NC}    $(get_device_prop ro.build.display.id)"
    echo "  ${BOLD}Screen:${NC}   $(adb shell wm size 2>/dev/null | tr -d '\r')"
    echo "  ${BOLD}DPI:${NC}      $(adb shell wm density 2>/dev/null | tr -d '\r')"
    echo
    adb shell dumpsys battery 2>/dev/null | grep -E "level|temperature|status|health" | sed 's/  */ /g' | while IFS= read -r line; do echo "  $line"; done
}

# ─── SIMULATION ─────────────────────────────────────────────

cmd_gps() {
    local lat="${1:--6.2088}"
    local lon="${2:-106.8456}"
    check_device
    log_info "Setting GPS: $lat, $lon"
    adb emu geo fix "$lon" "$lat" && log_ok "GPS location set" || log_err "Failed"
}

cmd_sms() {
    if [[ $# -lt 2 ]]; then
        log_err "Usage: $0 sms <number> <message>"
        exit 1
    fi
    local number="$1"; shift
    local message="$*"
    check_device
    log_info "Sending SMS to $number..."
    adb emu sms send "$number" "$message" && log_ok "SMS sent" || log_err "Failed"
}

cmd_call() {
    local number="${1:+628123456789}"
    check_device
    log_info "Simulating incoming call from $number..."
    adb emu gsm call "$number" && log_ok "Incoming call" || log_err "Failed"
}

cmd_battery() {
    local level="${1:-100}"
    check_device
    if [[ $level -lt 0 || $level -gt 100 ]]; then log_err "Level must be 0-100"; exit 1; fi
    log_info "Setting battery: ${level}%"
    adb shell dumpsys battery set level "$level"
    adb shell dumpsys battery set status 2
    adb shell dumpsys battery set present true
    log_ok "Battery set to ${level}%"
    echo "  To reset: adb shell dumpsys battery reset"
}

cmd_network() {
    local type="${1:-edge}"
    local valid=("edge" "gprs" "hsdpa" "hsupa" "lte" "full" "umts" "hspa" "evdo" "cdma")
    local ok=false
    for v in "${valid[@]}"; do [[ "$v" == "$type" ]] && ok=true; done
    if ! $ok; then log_err "Invalid network type. Valid: ${valid[*]}"; exit 1; fi

    check_device
    log_info "Setting network: $type"
    adb emu network speed "$type" && log_ok "Network set to $type" || log_err "Failed"
}

cmd_fingerprint() {
    local id="${1:-1}"
    check_device
    log_info "Simulating fingerprint touch (ID: $id)..."
    adb emu finger touch "$id" && log_ok "Fingerprint simulated" || log_err "Failed"
}

# ─── SNAPSHOT ───────────────────────────────────────────────

cmd_snapshot_save() {
    local name="${1:?Usage: $0 snapshot-save <name>}"
    check_device
    log_progress "Saving snapshot: $name"
    adb emu avd snapshot save "$name" && log_done "Snapshot saved: $name" || log_fail "Failed. Ensure emulator is running."
}

cmd_snapshot_load() {
    local name="${1:?Usage: $0 snapshot-load <name>}"
    check_device
    log_progress "Loading snapshot: $name"
    adb emu avd snapshot load "$name" && log_done "Snapshot loaded: $name" || log_fail "Failed"
}

cmd_snapshot_list() {
    check_device
    log_section "SNAPSHOTS"
    adb emu avd snapshot list 2>/dev/null || log_warn "Cannot list snapshots. Ensure emulator is running."
}

cmd_snapshot_delete() {
    local name="${1:?Usage: $0 snapshot-delete <name>}"
    check_device
    log_warn "Deleting snapshot: $name"
    adb emu avd snapshot delete "$name" && log_ok "Deleted" || log_err "Failed"
}

# ─── CONFIGURATION ──────────────────────────────────────────

cmd_proxy() {
    local host="${1:-127.0.0.1}"; local port="${2:-8080}"
    check_device
    log_info "Setting HTTP proxy: $host:$port"
    adb shell settings put global http_proxy "$host:$port" && log_ok "Proxy set" || log_err "Failed"
}

cmd_proxy_off() {
    check_device
    log_info "Clearing HTTP proxy..."
    adb shell settings put global http_proxy :0 && log_ok "Proxy cleared" || log_err "Failed"
}

cmd_scale() {
    local pct="${1:-50}"
    check_device
    log_info "Setting window scale: ${pct}%"
    adb shell wm density "$pct" 2>/dev/null && log_ok "Density set to $pct" || log_err "Failed"
}

cmd_language() {
    local lang="${1:-en}"; local country="${2:-US}"
    check_device
    log_info "Setting language: ${lang}_${country}"
    adb shell setprop persist.sys.locale "${lang}-${country}" 2>/dev/null || true
    adb shell setprop persist.sys.language "$lang" 2>/dev/null || true
    adb shell setprop persist.sys.country "$country" 2>/dev/null || true
    adb shell am broadcast -a android.intent.action.LOCALE_CHANGED 2>/dev/null || true
    log_ok "Language set. Reboot may be required for full effect."
}

# ─── MAIN ────────────────────────────────────────────────────

main() {
    [[ $# -lt 1 ]] && { show_help; exit 0; }
    local cmd="$1"; shift

    case "$cmd" in
        list|ls|status)             cmd_list;;
        create|new)                 cmd_create "$@";;
        start|launch)               cmd_start "$@";;
        start-headless|headless)    cmd_start_headless "$@";;
        start-snapshot|snapstart)   cmd_start_snapshot "$@";;
        start-cold|coldboot)        cmd_start_cold "$@";;
        start-writable|writable)    cmd_start_writable "$@";;
        stop|kill)                  cmd_stop;;
        delete|remove)              cmd_delete "$@";;
        wipe|recreate)              cmd_wipe "$@";;
        rename|mov)                 cmd_rename "$@";;
        info)                       cmd_info;;
        gps|location)               cmd_gps "$@";;
        sms|text)                   cmd_sms "$@";;
        call|voice)                 cmd_call "$@";;
        battery|batt)               cmd_battery "$@";;
        network|speed)              cmd_network "$@";;
        fingerprint|fp)             cmd_fingerprint "$@";;
        snapshot-save|snap-save)    cmd_snapshot_save "$@";;
        snapshot-load|snap-load)    cmd_snapshot_load "$@";;
        snapshot-list|snap-list)    cmd_snapshot_list;;
        snapshot-delete|snap-del)   cmd_snapshot_delete "$@";;
        proxy)                      shift; cmd_proxy "$@";;
        proxy-off|noproxy)          cmd_proxy_off;;
        scale|density)              cmd_scale "$@";;
        language|locale)            cmd_language "$@";;
        help|-h|--help)             show_help;;
        *) log_err "Unknown: $cmd"; show_help; exit 1;;
    esac
}

main "$@"
