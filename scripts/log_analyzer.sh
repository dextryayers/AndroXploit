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
${BOLD}Log Analyzer v${VERSION}${NC} — Advanced Android Log Analysis Toolkit
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 <command> [args]

${BOLD}REAL-TIME LOGGING:${NC}
  logcat [filter]              Live logcat output (default: *:V)
  logcat-buffer <buf>          Live logcat from specific buffer
  follow [filter]              Follow logcat in real-time (tail -f style)

${BOLD}LOG CAPTURE:${NC}
  capture [lines]              Capture logcat to file
  capture-filter <pattern> [lines]  Capture filtered logcat to file
  save-snapshot [tag]          Save a complete log snapshot with context

${BOLD}ANALYSIS:${NC}
  errors [lines]               Show recent errors/fatals
  crashes                      Show crash reports (from dropbox)
  crash-details <id>           Show detailed crash information
  anr                          Show ANR (Application Not Responding) reports
  filter <pattern> [lines]     Filter logcat for specific pattern
  app <package> [lines]        Filter logs for specific app
  priority <level> [lines]     Filter by priority (V,D,I,W,E,F)

${BOLD}SYSTEM LOGS:${NC}
  kernel [lines]               Kernel log (dmesg) viewer
  kernel-watch                 Watch kernel log in real-time
  events [lines]               Event log buffer
  radio [lines]                Radio log buffer
  battery                      Battery statistics (batterystats)
  wifi                         WiFi log summary

${BOLD}CRASH & BUG:${NC}
  bugreport                    Generate comprehensive bug report
  tombstones                   Show tombstone files
  tombstone-latest             Show latest tombstone content
  last-kmsg                    Show last kernel messages (ramoops)

${BOLD}STATISTICS:${NC}
  summary                      Log summary statistics
  stats-by-package             Log counts grouped by package
  stats-by-priority            Log counts by priority level
  top-errors                   Show most frequent error patterns

${DIM}Priorities:${NC} V=Verbose, D=Debug, I=Info, W=Warn, E=Error, F=Fatal
${DIM}Buffers:${NC} main, system, events, crash, all
${DIM}Examples:${NC}
  $0 follow                         # Live logcat
  $0 errors 50                      # Last 50 errors
  $0 app com.whatsapp              # WhatsApp logs
  $0 bugreport                     # Full bug report
  $0 tombstones                     # Tombstone analysis
EOF
}

check_adb() { adb get-state &>/dev/null || { log_err "No device connected."; exit 1; }; }

# ─── REAL-TIME LOGGING ──────────────────────────────────────

cmd_logcat() {
    check_adb
    local filter="${1:-\*:V}"
    log_info "Live logcat (filter: $filter) — Ctrl+C to stop"
    adb logcat -v threadtime "$filter" 2>/dev/null || true
}

cmd_logcat_buffer() {
    check_adb
    local buf="${1:?Usage: $0 logcat-buffer <buffer> (main,system,events,crash,all)}"
    log_info "Live logcat - buffer: $buf"
    adb logcat -b "$buf" -v threadtime 2>/dev/null || true
}

cmd_follow() {
    check_adb
    local filter="${1:-\*:V}"
    log_info "Following logcat (filter: $filter)..."
    adb logcat -v threadtime "$filter" 2>/dev/null | tail -f || true
}

# ─── LOG CAPTURE ────────────────────────────────────────────

cmd_capture() {
    check_adb
    local lines="${1:-500}"
    local out="$OUT_DIR/logcat_$(date +%Y%m%d_%H%M%S).txt"
    log_section "CAPTURE LOGCAT"
    log_progress "Capturing $lines lines"
    adb logcat -d -v threadtime 2>/dev/null | tail -"$lines" > "$out"
    local count; count=$(wc -l < "$out")
    log_done "Saved: $out ($count lines)"
}

cmd_capture_filter() {
    check_adb
    local pattern="${1:?Usage: $0 capture-filter <pattern> [lines]}"
    local lines="${2:-500}"
    local out="$OUT_DIR/logcat_${pattern}_$(date +%Y%m%d_%H%M%S).txt"
    log_section "FILTER CAPTURE: $pattern"
    log_progress "Capturing"
    adb logcat -d -v threadtime 2>/dev/null | grep -i "$pattern" | tail -"$lines" > "$out"
    local count; count=$(wc -l < "$out")
    log_done "Saved: $out ($count lines)"
}

cmd_save_snapshot() {
    check_adb
    local tag="${1:-snapshot}"
    local dir="$OUT_DIR/snapshot_${tag}_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$dir"
    log_section "SNAPSHOT: $tag"
    log_progress "Logcat"   && adb logcat -d -v threadtime > "$dir/logcat.txt" 2>/dev/null && log_done "Logcat saved"
    log_progress "Dmesg"    && adb shell dmesg > "$dir/dmesg.txt" 2>/dev/null && log_done "Dmesg saved"
    log_progress "Battery"  && adb shell dumpsys battery > "$dir/battery.txt" 2>/dev/null && log_done "Battery saved"
    log_progress "Events"   && adb logcat -d -b events -v brief > "$dir/events.txt" 2>/dev/null && log_done "Events saved"
    log_progress "Dropbox"  && adb shell dumpsys dropbox --message > "$dir/dropbox.txt" 2>/dev/null && log_done "Dropbox saved"
    echo
    log_ok "Snapshot: $dir/"
}

# ─── ANALYSIS ───────────────────────────────────────────────

cmd_errors() {
    check_adb
    local lines="${1:-100}"
    log_section "ERRORS & FATALS (last $lines)"
    adb logcat -d -v threadtime 2>/dev/null | grep -iE "FATAL|ERROR|Exception|nativeCrash|CRASH" | tail -"$lines" | sed 's/^/  /' || log_info "No errors"
}

cmd_crashes() {
    check_adb
    log_section "CRASH REPORTS"
    adb shell dumpsys dropbox --message 2>/dev/null | grep -E "crash|native_crash" | head -20 | sed 's/^/  /' || log_info "No crashes"
    echo
    log_section "LAST CRASH DETAILS"
    local last; last=$(adb shell dumpsys dropbox --message 2>/dev/null | grep "crash" | tail -1 | awk '{print $2}')
    [[ -n "$last" ]] && adb shell dumpsys dropbox --message 2>/dev/null | grep -A 10 "$last" | head -20 | sed 's/^/  /' || log_info "No crash details"
}

cmd_crash_details() {
    local id="${1:-}"
    check_adb
    if [[ -n "$id" ]]; then
        adb shell dumpsys dropbox --message 2>/dev/null | grep -A 30 "$id" | head -50
    else
        cmd_crashes
    fi
}

cmd_anr() {
    check_adb
    log_section "ANR REPORTS"
    adb shell dumpsys dropbox --message 2>/dev/null | grep "anr" | tail -10 | sed 's/^/  /' || log_info "No ANRs"
    echo
    log_info "ANR trace files:"
    adb shell ls -la /data/anr/ 2>/dev/null | tail -5 | sed 's/^/  /' || echo "  (none)"
}

cmd_filter() {
    check_adb
    local pattern="${1:?Usage: $0 filter <pattern> [lines]}"
    local lines="${2:-100}"
    log_section "FILTER: $pattern"
    adb logcat -d -v threadtime 2>/dev/null | grep -i "$pattern" | tail -"$lines" | sed 's/^/  /' || log_info "No matches"
}

cmd_app() {
    check_adb
    local pkg="${1:?Usage: $0 app <package> [lines]}"
    local lines="${2:-100}"
    log_section "APP LOGS: $pkg"
    adb logcat -d -v threadtime 2>/dev/null | grep -i "$pkg" | tail -"$lines" | sed 's/^/  /' || log_info "No logs for $pkg"
}

cmd_priority() {
    check_adb
    local level="${1:-E}"; local lines="${2:-100}"
    local pri; local name
    case "$level" in
        V|v) pri="V"; name="Verbose";; D|d) pri="D"; name="Debug";;
        I|i) pri="I"; name="Info";; W|w) pri="W"; name="Warn";;
        E|e) pri="E"; name="Error";; F|f) pri="F"; name="Fatal";;
        *) log_err "Invalid priority. Use V, D, I, W, E, F"; exit 1;;
    esac
    log_section "PRIORITY: $name ($pri)"
    adb logcat -d -v threadtime 2>/dev/null | grep " $pri/" | tail -"$lines" | sed 's/^/  /' || log_info "No $name messages"
}

# ─── SYSTEM LOGS ────────────────────────────────────────────

cmd_kernel() {
    check_adb
    local lines="${1:-50}"
    log_section "KERNEL LOG (dmesg) — last $lines"
    adb shell su -c "dmesg" 2>/dev/null | tail -"$lines" | sed 's/^/  /' || \
    adb shell dmesg 2>/dev/null | tail -"$lines" | sed 's/^/  /' || \
    log_warn "Cannot access dmesg (needs root or -userdebug build)"
}

cmd_kernel_watch() {
    check_adb
    log_info "Watching kernel log (Ctrl+C to stop)..."
    adb shell su -c "dmesg -w" 2>/dev/null || adb shell "while true; do dmesg -c; sleep 1; done" 2>/dev/null || log_err "Cannot watch dmesg"
}

cmd_events() {
    check_adb
    local lines="${1:-50}"
    log_section "EVENT LOG (last $lines)"
    adb logcat -d -b events -v threadtime 2>/dev/null | tail -"$lines" | sed 's/^/  /' || log_warn "Event log unavailable"
}

cmd_radio() {
    check_adb
    local lines="${1:-50}"
    log_section "RADIO LOG (last $lines)"
    adb logcat -d -b radio -v threadtime 2>/dev/null | tail -"$lines" | sed 's/^/  /' || log_warn "Radio log unavailable"
}

cmd_battery_log() {
    check_adb
    log_section "BATTERY STATISTICS"
    adb shell dumpsys batterystats 2>/dev/null | head -60 | sed 's/^/  /'
}

cmd_wifi_log() {
    check_adb
    log_section "WIFI LOG SUMMARY"
    adb shell dumpsys wifi 2>/dev/null | grep -E "SSID|signal|rssi|linkSpeed|state|mWifiInfo|mNetworkInfo" | head -20 | sed 's/^/  /'
}

# ─── CRASH & BUG ────────────────────────────────────────────

cmd_bugreport() {
    check_adb
    local dir="$OUT_DIR/bugreport_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$dir"
    log_section "BUG REPORT → $dir"

    if adb bugreport "$dir" 2>/dev/null; then
        log_ok "Bug report generated"
        return
    fi

    log_info "Using fallback method..."
    for report in logcat dumpsys battery meminfo diskstats package activity window wifi; do
        log_progress "$report"
        case "$report" in
            logcat)   adb logcat -d -v threadtime > "$dir/logcat.txt" 2>/dev/null && log_done "OK" || log_fail "Failed";;
            dumpsys)  adb shell dumpsys > "$dir/dumpsys.txt" 2>/dev/null && log_done "OK" || log_fail "Failed";;
            battery)  adb shell dumpsys battery > "$dir/battery.txt" 2>/dev/null && log_done "OK" || log_fail "Failed";;
            meminfo)  adb shell dumpsys meminfo > "$dir/meminfo.txt" 2>/dev/null && log_done "OK" || log_fail "Failed";;
            diskstats) adb shell dumpsys diskstats > "$dir/diskstats.txt" 2>/dev/null && log_done "OK" || log_fail "Failed";;
            package)  adb shell dumpsys package > "$dir/packages.txt" 2>/dev/null && log_done "OK" || log_fail "Failed";;
            activity) adb shell dumpsys activity > "$dir/activity.txt" 2>/dev/null && log_done "OK" || log_fail "Failed";;
            window)   adb shell dumpsys window > "$dir/window.txt" 2>/dev/null && log_done "OK" || log_fail "Failed";;
            wifi)     adb shell dumpsys wifi > "$dir/wifi.txt" 2>/dev/null && log_done "OK" || log_fail "Failed";;
        esac
    done
    echo
    log_ok "Bug report: $dir/"
}

cmd_tombstones() {
    check_adb
    log_section "TOMBSTONES"
    adb shell ls -la /data/tombstones/ 2>/dev/null | sed 's/^/  /' || echo "  (none)"
}

cmd_tombstone_latest() {
    check_adb
    log_section "LATEST TOMBSTONE"
    local latest; latest=$(adb shell ls -t /data/tombstones/ 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
        log_info "File: $latest"
        adb shell cat "/data/tombstones/$latest" 2>/dev/null | head -80 | sed 's/^/  /'
    else echo "  (no tombstones)"; fi
}

cmd_last_kmsg() {
    check_adb
    log_section "LAST KERNEL MSG (ramoops)"
    adb shell su -c "cat /sys/fs/pstore/console-ramoops 2>/dev/null || cat /sys/fs/pstore/dmesg-ramoops-0 2>/dev/null || cat /proc/last_kmsg 2>/dev/null" | head -100 | sed 's/^/  /' || log_warn "No last kmsg available"
}

# ─── STATISTICS ─────────────────────────────────────────────

cmd_summary() {
    check_adb
    log_section "LOG SUMMARY"
    echo "  ${BOLD}Uptime:${NC}   $(adb shell uptime 2>/dev/null | head -1 | tr -d '\r')"
    echo "  ${BOLD}Log lines:${NC} $(adb logcat -d 2>/dev/null | wc -l)"
    echo "  ${BOLD}Errors:${NC}    $(adb logcat -d -v brief 2>/dev/null | grep -c ' E/' || echo 0)"
    echo "  ${BOLD}Fatal:${NC}     $(adb logcat -d -v brief 2>/dev/null | grep -c ' F/' || echo 0)"
    echo "  ${BOLD}Warnings:${NC}  $(adb logcat -d -v brief 2>/dev/null | grep -c ' W/' || echo 0)"
    echo "  ${BOLD}Debug:${NC}     $(adb logcat -d -v brief 2>/dev/null | grep -c ' D/' || echo 0)"
    echo "  ${BOLD}Crashes:${NC}   $(adb shell dumpsys dropbox --message 2>/dev/null | grep -c 'crash' || echo 0)"
    echo "  ${BOLD}ANRs:${NC}      $(adb shell dumpsys dropbox --message 2>/dev/null | grep -c 'anr' || echo 0)"
    echo "  ${BOLD}Tombstones:${NC} $(adb shell ls /data/tombstones/ 2>/dev/null | wc -l)"
}

cmd_stats_by_package() {
    check_adb
    log_section "LOGS BY PACKAGE"
    adb logcat -d -v threadtime 2>/dev/null | grep -oP '\(\s*\K[a-zA-Z0-9_.]+(?=\))' | sort | uniq -c | sort -rn | head -30 | while IFS= read -r line; do echo "  $line"; done
}

cmd_stats_by_priority() {
    check_adb
    log_section "LOGS BY PRIORITY"
    for pri in V D I W E F; do
        local count; count=$(adb logcat -d -v brief 2>/dev/null | grep -c " $pri/" || echo 0)
        echo -n "  ${BOLD}$pri${NC}: "
        local filled=$((count > 100 ? 100 : count / 10))
        for ((i=0; i<filled && i<30; i++)); do echo -n "${GREEN}█${NC}"; done
        echo " $count"
    done
}

cmd_top_errors() {
    check_adb
    log_section "TOP ERROR PATTERNS"
    adb logcat -d -v threadtime 2>/dev/null | grep -iE " E/| F/|Exception" | grep -oP ':\s*\K.*' | sed 's/^[[:space:]]*//' | sort | uniq -c | sort -rn | head -20 | sed 's/^/  /'
}

# ─── MAIN ────────────────────────────────────────────────────

main() {
    [[ $# -lt 1 ]] && { show_help; exit 0; }
    local cmd="$1"; shift

    case "$cmd" in
        logcat|live)          cmd_logcat "$@";;
        logcat-buffer|buffer) cmd_logcat_buffer "$@";;
        follow|tail)          cmd_follow "$@";;
        capture|save)         cmd_capture "$@";;
        capture-filter|cfilter) cmd_capture_filter "$@";;
        save-snapshot|snapshot) cmd_save_snapshot "$@";;
        errors|error)         cmd_errors "$@";;
        crashes|crash)        cmd_crashes;;
        crash-details|cdetails) cmd_crash_details "$@";;
        anr)                  cmd_anr;;
        filter|grep)          cmd_filter "$@";;
        app|package)          cmd_app "$@";;
        priority|prio)        cmd_priority "$@";;
        kernel|dmesg)         cmd_kernel "$@";;
        kernel-watch|dmesgw)  cmd_kernel_watch;;
        events|event)         cmd_events "$@";;
        radio)                cmd_radio "$@";;
        battery)              cmd_battery_log;;
        wifi)                 cmd_wifi_log;;
        bugreport|bug)        cmd_bugreport;;
        tombstones|tomb)      cmd_tombstones;;
        tombstone-latest|tlat) cmd_tombstone_latest;;
        last-kmsg|lkmsg)      cmd_last_kmsg;;
        summary|stats)        cmd_summary;;
        stats-by-package|bypkg) cmd_stats_by_package;;
        stats-by-priority|bypri) cmd_stats_by_priority;;
        top-errors|toperrors) cmd_top_errors;;
        help|-h|--help)       show_help;;
        *) log_err "Unknown: $cmd"; show_help; exit 1;;
    esac
}

main "$@"
