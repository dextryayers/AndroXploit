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

ARCHS=("arm64" "arm" "x86_64" "x86")
BIN_DIR="bin"
TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
mkdir -p "$BIN_DIR"

show_help() {
    cat <<EOF
${BOLD}Frida Setup v${VERSION}${NC} — Professional Frida Manager for Android
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 <command> [options]

${BOLD}CORE COMMANDS:${NC}
  auto               Auto-detect, download, push & start frida-server
  download [arch]    Download frida-server for specific arch (default: auto)
  download-all       Download all architectures (arm64, arm, x86_64, x86)
  push [arch]        Push frida-server binary to device
  start              Start frida-server on device (as root or shell)
  stop               Stop frida-server on device
  restart            Restart frida-server on device
  status             Show full status of Frida installation

${BOLD}DEVICE COMMANDS:${NC}
  devices            List connected devices
  detect             Detect CPU architecture of connected device

${BOLD}SCRIPT MANAGEMENT:${NC}
  scripts            List available Frida scripts in scripts/frida/
  run <script.js>    Run a Frida script on the device
  run-app <pkg> <script.js>  Run script attached to specific app
  create <name>      Create a new Frida script from template

${BOLD}TEST & INFO:${NC}
  test               Test Frida connection to device
  ps                 List running processes via frida-ps
  ls-apps            List installed apps via frida-ps
  version            Show version info for frida tools
  check-compat       Check compatibility between frida and server

${BOLD}ADVANCED:${NC}
  custom-url <url>   Download frida-server from custom URL
  verify             Verify frida-server binary integrity
  uninstall          Remove all frida-server binaries
  port-forward [p]   Forward a custom port for frida (default: 27042)

${DIM}Examples:${NC}
  $0 auto                       # Auto setup
  $0 download arm64             # Download specific arch
  $0 run-app com.whatsapp hook.js  # Hook an app
  $0 create myhook              # Create script template
EOF
}

check_adb() {
    if ! command -v adb &>/dev/null; then log_err "ADB not found."; exit 1; fi
}
check_device() {
    local s; s=$(adb get-state 2>/dev/null || echo "unknown")
    [[ "$s" != "device" ]] && { log_err "No device connected."; exit 1; }
}
check_frida_cli() {
    if ! command -v frida &>/dev/null; then
        log_warn "Frida CLI not found. Install: pip install frida-tools"
        return 1
    fi
    return 0
}
detect_arch() {
    local arch; arch=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
    case "$arch" in
        arm64-v8a) echo "arm64" ;; armeabi-v7a) echo "arm" ;;
        x86_64) echo "x86_64" ;; x86) echo "x86" ;;
        *) echo "$arch" ;;
    esac
}
get_device_model() { adb shell getprop ro.product.model 2>/dev/null | tr -d '\r'; }
get_frida_version() { frida --version 2>/dev/null || echo "16.5.9"; }

cmd_auto() {
    check_adb; check_device
    log_section "FRIDA AUTO SETUP"
    local model; model=$(get_device_model)
    local arch; arch=$(detect_arch)
    echo "  ${BOLD}Device:${NC} $model"
    echo "  ${BOLD}Arch:${NC}   $arch"
    echo
    local server_bin="$BIN_DIR/frida-server-android-${arch}"
    [[ ! -f "$server_bin" ]] && cmd_download "$arch" || log_ok "Binary cached: $server_bin"
    if adb shell 'ps -A 2>/dev/null | grep -q frida-server'; then log_info "frida-server already running, restarting..."; cmd_stop; fi
    cmd_push "$arch"; cmd_start; cmd_test
}

cmd_download() {
    local arch="${1:-}"
    if [[ -z "$arch" ]]; then check_adb; check_device; arch=$(detect_arch); log_info "Detected arch: $arch"; fi
    local ver; ver=$(get_frida_version)
    local url="https://github.com/frida/frida/releases/download/${ver}/frida-server-${ver}-android-${arch}.xz"
    local out="$BIN_DIR/frida-server-android-${arch}"
    [[ -f "$out" ]] && { log_ok "Already downloaded: $out"; return; }
    log_section "DOWNLOAD FRIDA-SERVER"
    echo "  ${BOLD}Version:${NC} $ver   ${BOLD}Arch:${NC} $arch"
    log_progress "Downloading"
    local ok=false
    if command -v wget &>/dev/null; then wget -q --show-progress "$url" -O "$TMP_DIR/frida.xz" 2>&1 && ok=true
    elif command -v curl &>/dev/null; then curl -# -L "$url" -o "$TMP_DIR/frida.xz" && ok=true; fi
    if ! $ok; then log_fail "Download failed"; exit 1; fi
    log_progress "Decompressing"
    if xz -d "$TMP_DIR/frida.xz" 2>/dev/null; then
        mv "$TMP_DIR/frida" "$out"; chmod +x "$out"
        local size; size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")
        log_done "Downloaded: $out ($((size/1024/1024))MB)"
    else log_fail "Decompression failed"; exit 1; fi
}

cmd_download_all() {
    log_section "DOWNLOAD ALL ARCHITECTURES"
    for arch in "${ARCHS[@]}"; do cmd_download "$arch"; done
    log_ok "All architectures downloaded"; ls -lh "$BIN_DIR"/frida-server-* 2>/dev/null
}

cmd_custom_url() {
    local url="${1:?Usage: $0 custom-url <url>}"; local arch="${2:-custom}"
    local out="$BIN_DIR/frida-server-android-${arch}"
    log_info "Downloading from: $url"
    if command -v wget &>/dev/null; then wget -q --show-progress "$url" -O "$out" 2>&1
    elif command -v curl &>/dev/null; then curl -# -L "$url" -o "$out"
    else log_err "wget/curl not found"; exit 1; fi
    chmod +x "$out"; log_ok "Saved: $out"
}

cmd_push() {
    check_adb; check_device
    local arch="${1:-}"; [[ -z "$arch" ]] && arch=$(detect_arch)
    local src="$BIN_DIR/frida-server-android-${arch}"
    [[ ! -f "$src" ]] && { log_warn "Binary not found, downloading..."; cmd_download "$arch"; }
    log_section "PUSH FRIDA-SERVER"
    echo "  ${BOLD}Source:${NC} $src"
    log_progress "Pushing"
    adb push "$src" /data/local/tmp/frida-server 2>/dev/null && log_done "Pushed" || { log_fail "Push failed"; exit 1; }
    adb shell chmod 755 /data/local/tmp/frida-server 2>/dev/null
    local rsize; rsize=$(adb shell ls -l /data/local/tmp/frida-server 2>/dev/null | awk '{print $4}')
    echo "  ${BOLD}Remote:${NC} $rsize bytes"
}

cmd_start() {
    check_adb; check_device
    log_section "START FRIDA-SERVER"
    if adb shell 'ps -A 2>/dev/null | grep -q frida-server'; then
        log_warn "Already running"; read -p "Restart? (Y/n): " yn
        [[ "$yn" != "n" ]] && cmd_restart; return
    fi
    log_progress "Starting"
    local ok=false
    adb shell su -c '/data/local/tmp/frida-server &' 2>/dev/null && ok=true
    $ok || (adb shell '/data/local/tmp/frida-server &' 2>/dev/null && ok=true)
    sleep 2
    if $ok && adb shell 'ps -A 2>/dev/null | grep -q frida-server'; then
        local pid; pid=$(adb shell 'ps -A 2>/dev/null | grep frida-server' | awk '{print $2}' | head -1)
        log_done "frida-server running (PID: ${pid:-?})"
    else log_fail "Failed to start"; exit 1; fi
}

cmd_stop() {
    check_adb; check_device
    log_section "STOP FRIDA-SERVER"
    log_progress "Stopping"
    adb shell su -c 'killall -9 frida-server' 2>/dev/null || true
    adb shell 'killall -9 frida-server' 2>/dev/null || true; sleep 1
    adb shell su -c 'pkill -9 frida-server' 2>/dev/null || true; sleep 1
    adb shell 'ps -A 2>/dev/null | grep -q frida-server' && log_fail "Could not stop" || log_done "Stopped"
}

cmd_restart() { check_adb; check_device; log_info "Restarting..."; cmd_stop; sleep 1; cmd_start; }

cmd_status() {
    log_section "FRIDA STATUS"
    echo -e "  ${BOLD}Frida CLI:${NC}"
    if check_frida_cli; then local v; v=$(frida --version); echo "    Version: ${GREEN}$v${NC}"; echo "    Path:    $(command -v frida)"; else echo "    ${RED}Not installed${NC}"; fi
    echo; echo -e "  ${BOLD}Local Binaries:${NC}"
    ls -lh "$BIN_DIR"/frida-server-* 2>/dev/null || echo "    ${YELLOW}(none)${NC}"
    echo; echo -e "  ${BOLD}Device:${NC}"
    if adb get-state 2>/dev/null | grep -q device; then
        echo "    Model: $(get_device_model)"
        if adb shell 'ps -A 2>/dev/null | grep -q frida-server'; then
            local pid; pid=$(adb shell 'ps -A | grep frida-server' | awk '{print $2}' | head -1)
            echo -e "    frida-server: ${GREEN}RUNNING${NC} (PID $pid)"
        else echo -e "    frida-server: ${RED}NOT RUNNING${NC}"; fi
        local has_bin; has_bin=$(adb shell ls -l /data/local/tmp/frida-server 2>/dev/null | awk '{print $4}')
        echo "    Binary: $([ -n "$has_bin" ] && echo "Yes ($has_bin bytes)" || echo "${YELLOW}No${NC}")"
    else echo "    ${YELLOW}No device${NC}"; fi
    echo; echo -e "  ${BOLD}Scripts:${NC}"
    local sc; sc=$(find scripts/frida -name '*.js' -type f 2>/dev/null | wc -l)
    [[ "$sc" -gt 0 ]] && echo "    $sc scripts available" || echo "    ${YELLOW}(none)${NC}"
}

cmd_test() {
    log_section "TEST FRIDA CONNECTION"
    ! check_frida_cli && return 1; ! adb get-state 2>/dev/null | grep -q device && { log_err "No device"; return 1; }
    log_progress "Testing"
    if frida-ps -U 2>/dev/null | head -3 &>/dev/null; then
        log_done "Connection OK"; echo; frida-ps -U 2>/dev/null | head -10
    else log_fail "Connection failed. Ensure frida-server is running."; return 1; fi
}

cmd_devices() { check_adb; adb devices -l; }
cmd_detect() { check_adb; check_device; echo "  ${BOLD}Device:${NC} $(get_device_model)"; echo "  ${BOLD}Arch:${NC}   $(detect_arch)"; }
cmd_ps() { check_frida_cli && frida-ps -U 2>/dev/null || true; }
cmd_ls_apps() { check_frida_cli && frida-ps -U -a 2>/dev/null || true; }

cmd_scripts() {
    mkdir -p scripts/frida; log_section "FRIDA SCRIPTS"
    local found=false
    for f in scripts/frida/*.js; do
        [[ -f "$f" ]] && { echo "  ${BOLD}$(basename "$f")${NC}"; head -3 "$f" | sed 's/^/    /'; echo; found=true; }
    done
    ! $found && { log_info "No scripts. Create one: $0 create <name>"; }
}

cmd_run_script() {
    local script="${1:?Usage: $0 run <script.js>}"
    [[ ! -f "$script" ]] && { log_err "Script not found"; exit 1; }
    check_frida_cli || exit 1
    log_info "Running: $script"; frida -U -l "$script" 2>/dev/null || log_err "Failed"
}

cmd_run_app() {
    [[ $# -lt 2 ]] && { log_err "Usage: $0 run-app <pkg> <script.js>"; exit 1; }
    local pkg="$1"; shift; local script="$1"
    [[ ! -f "$script" ]] && { log_err "Script not found"; exit 1; }
    check_frida_cli || exit 1
    log_info "Attaching to $pkg with $script"; frida -U -f "$pkg" -l "$script" --no-pause 2>/dev/null || log_err "Failed"
}

cmd_create_script() {
    local name="${1:?Usage: $0 create <name>}"; mkdir -p scripts/frida
    local file="scripts/frida/${name}.js"
    [[ -f "$file" ]] && { log_warn "Exists: $file"; read -p "Overwrite? (y/N): " yn; [[ "$yn" != "y" ]] && exit 0; }
    cat > "$file" << 'SCRIPTEOF'
// Frida Hook Script — Generated by AndroXploit
// Usage: frida -U -l script.js
'use strict';
function hook_method(className, methodName) {
    var targetClass = Java.use(className);
    targetClass[methodName].implementation = function () {
        console.log('[+] ' + className + '.' + methodName + ' called');
        for (var i = 0; i < arguments.length; i++)
            console.log('    arg[' + i + ']: ' + arguments[i]);
        var result = this[methodName].apply(this, arguments);
        console.log('    result: ' + result);
        return result;
    };
}
Java.perform(function () {
    console.log('[*] Script loaded');
    // hook_method('com.example.Target', 'targetMethod');
});
SCRIPTEOF
    log_ok "Created: $file"
}

cmd_version() {
    log_section "FRIDA VERSION INFO"
    if check_frida_cli; then echo "  ${BOLD}Frida CLI:${NC}   $(frida --version)"; fi
    for f in "$BIN_DIR"/frida-server-*; do
        [[ -f "$f" ]] && { local s; s=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f"); echo "  $(basename "$f") — $((s/1024/1024))MB"; }
    done
}

cmd_check_compat() {
    log_section "COMPATIBILITY CHECK"
    if check_frida_cli; then
        local cli_v; cli_v=$(frida --version)
        echo "  ${BOLD}Frida CLI:${NC} $cli_v"
        for f in "$BIN_DIR"/frida-server-*; do
            [[ -f "$f" ]] && { local n; n=$(basename "$f"); local fv; fv=$(echo "$n" | grep -oP '[\d.]+' | head -1); echo "  ${BOLD}$n${NC}"; [[ "$fv" == "$cli_v" ]] && echo -e "    ${GREEN}✓${NC} Match" || echo -e "    ${YELLOW}⚠${NC} CLI: $cli_v vs File: $fv"; }
        done
    fi
}

cmd_verify() {
    log_section "VERIFY BINARIES"
    for f in "$BIN_DIR"/frida-server-*; do
        [[ -f "$f" ]] && { local s; s=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f"); local p; p=$(stat -c%a "$f" 2>/dev/null || stat -f%Lp "$f"); [[ $s -gt 1000000 && "$p" == "755" ]] && echo -e "  ${GREEN}✓${NC} $(basename "$f") — $((s/1024/1024))MB" || echo -e "  ${YELLOW}⚠${NC} $(basename "$f") — size: $s perms: $p"; }
    done
}

cmd_uninstall() {
    log_warn "Remove ALL frida-server binaries?"; read -p "Confirm (y/N): " yn; [[ "$yn" != "y" ]] && exit 0
    adb shell su -c 'killall frida-server' 2>/dev/null || true
    rm -f "$BIN_DIR"/frida-server-* 2>/dev/null; log_ok "All binaries removed"
}

cmd_port_forward() {
    local port="${1:-27042}"; check_adb; check_device
    adb forward "tcp:$port" "tcp:$port" && log_ok "Forwarded tcp:$port → tcp:$port" || log_err "Failed"
}

main() {
    [[ $# -lt 1 ]] && { show_help; exit 0; }
    case "${1:-help}" in
        auto|all)           shift; cmd_auto "$@";;
        download|dl)        shift; cmd_download "$@";;
        download-all|dl-all) cmd_download_all;;
        custom-url|custom)  shift; cmd_custom_url "$@";;
        push)               shift; cmd_push "$@";;
        start)              cmd_start;;
        stop)               cmd_stop;;
        restart)            cmd_restart;;
        status|stat)        cmd_status;;
        test|check)         cmd_test;;
        devices|list)       cmd_devices;;
        detect|arch)        cmd_detect;;
        ps|processes)       cmd_ps;;
        ls-apps|apps)       cmd_ls_apps;;
        scripts|ls-scripts) cmd_scripts;;
        run|exec)           shift; cmd_run_script "$@";;
        run-app|hook)       shift; cmd_run_app "$@";;
        create|new)         shift; cmd_create_script "$@";;
        version)            cmd_version;;
        check-compat|compat) cmd_check_compat;;
        verify)             cmd_verify;;
        uninstall|remove)   cmd_uninstall;;
        port-forward|fwd)   shift; cmd_port_forward "$@";;
        help|-h|--help)     show_help;;
        *) log_err "Unknown: $1"; show_help; exit 1;;
    esac
}

main "$@"
