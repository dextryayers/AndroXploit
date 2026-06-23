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

OUT_DIR="output/automation"
mkdir -p "$OUT_DIR"

show_help() {
    cat <<EOF
${BOLD}Automation Tester v${VERSION}${NC} — Professional Android UI Automation
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 <command> [args]

${BOLD}UI INTERACTION:${NC}
  tap <x> <y>                Tap at coordinates
  swipe <x1> <y1> <x2> <y2>  Swipe between coordinates
  type <text>                Type text (spaces → %s)
  key <keyname>              Send key event (home, back, menu, enter, etc.)
  long-press <x> <y> [ms]    Long press at coordinates
  pinch <x1> <y1> <x2> <y2>  Pinch gesture

${BOLD}SCREEN & UI:${NC}
  screenshot [file]          Take screenshot
  ui-dump [file]             Dump UI hierarchy (uiautomator)
  find-text <text>           Find text on current screen
  click-text <text>          Click on text found on screen
  wait-text <text> [timeout] Wait for text to appear
  list-bounds                Show all visible UI element bounds

${BOLD}APP MANAGEMENT:${NC}
  open-app <pkg> [activity]  Open application
  close-app <pkg>            Close application
  force-stop <pkg>           Force-stop application
  install-test <apk>         Install, launch, screenshot, uninstall cycle
  clear-app <pkg>            Clear app data

${BOLD}MONKEY TESTING:${NC}
  monkey [pkg] [events] [throttle]  Standard monkey test
  monkey-optimized [pkg]     Optimized monkey with realistic event mix
  monkey-log <file>          Run monkey with events from log file

${BOLD}RECORDING:${NC}
  record [seconds]           Screen recording (default: 30s)
  record-input               Record input events
  replay <file>              Replay recorded input events

${BOLD}WORKFLOW:${NC}
  workflow <script>          Run workflow from script file
  create-script <file>       Create workflow script template
  run-commands <cmdfile>     Run ADB commands from file

${DIM}Key names:${NC} home, back, menu, enter, volume_up, volume_down, power, camera, space, del, tab, search, settings, recent, lock
${DIM}Workflow commands:${NC} tap:x,y | swipe:x1,y1,x2,y2 | type:text | key:name | wait:secs | screenshot | open:pkg | close:pkg
${DIM}Examples:${NC}
  $0 monkey com.android.chrome 2000
  $0 click-text "Accept"
  $0 workflow tests/login.txt
  $0 install-test app.apk
EOF
}

check_adb() { adb get-state &>/dev/null || { log_err "No device connected."; exit 1; }; }

tap() { adb shell input tap "$1" "$2"; }
swipe() { adb shell input swipe "$1" "$2" "$3" "$4" "${5:-200}"; }
type_text() { adb shell input text "${1// /%s}"; }
keyevent() { adb shell input keyevent "$1"; }
long_press() { adb shell input swipe "$1" "$2" "$1" "$2" "${3:-1000}"; }

get_screen_size() {
    adb shell wm size 2>/dev/null | grep -oP '\d+' | head -2 | tr '\n' ' '
}

# ─── UI INTERACTION ─────────────────────────────────────────

cmd_tap() {
    check_adb; local x="${1:?Usage: $0 tap <x> <y>}"; local y="${2:?Usage: $0 tap <x> <y>}"
    tap "$x" "$y"; log_ok "Tapped ($x, $y)"
}

cmd_swipe() {
    check_adb
    [[ $# -lt 4 ]] && { log_err "Usage: $0 swipe <x1> <y1> <x2> <y2> [duration]"; exit 1; }
    swipe "$1" "$2" "$3" "$4" "${5:-200}"
    log_ok "Swiped ($1,$2)→($3,$4)"
}

cmd_type() {
    check_adb; local text="${*:?Usage: $0 type <text>}"
    type_text "$text"; log_ok "Typed: $text"
}

cmd_key() {
    check_adb; local key="${1:?Usage: $0 key <keycode|keyname>}"
    case "$key" in
        home)         keyevent 3;; back)         keyevent 4;; menu)    keyevent 82;;
        enter)        keyevent 66;; volume_up)   keyevent 24;; volume_down) keyevent 25;;
        power)        keyevent 26;; camera)      keyevent 27;; space)  keyevent 62;;
        del|delete)   keyevent 67;; tab)         keyevent 61;; search) keyevent 84;;
        settings)     keyevent 176;; recent)     keyevent 187;; lock)  keyevent 223;;
        clear|clr)    keyevent 28;; call)        keyevent 5;; endcall) keyevent 6;;
        star|asterisk) keyevent 17;; pound)      keyevent 18;; dpad_up) keyevent 19;;
        dpad_down)    keyevent 20;; dpad_left)   keyevent 21;; dpad_right) keyevent 22;;
        dpad_center)  keyevent 23;; mute)        keyevent 164;; media_play) keyevent 126;;
        media_pause)  keyevent 127;; media_stop) keyevent 86;; media_next) keyevent 87;;
        media_prev)   keyevent 88;; capture)     keyevent 120;; headset) keyevent 79;;
        *)            keyevent "$key";;
    esac
    log_ok "Key: $key"
}

cmd_long_press() {
    check_adb; local x="${1:?Usage: $0 long-press <x> <y> [ms]}"; local y="${2:?Usage: $0 long-press <x> <y> [ms]}"; local ms="${3:-1000}"
    long_press "$x" "$y" "$ms"; log_ok "Long pressed at ($x, $y) for ${ms}ms"
}

cmd_pinch() {
    check_adb
    [[ $# -lt 4 ]] && { log_err "Usage: $0 pinch <x1> <y1> <x2> <y2>"; exit 1; }
    adb shell input touchscreen swipe "$1" "$2" "$3" "$4" 200 && \
    adb shell input touchscreen swipe "$3" "$4" "$1" "$2" 200
    log_ok "Pinch gesture"
}

# ─── SCREEN & UI ────────────────────────────────────────────

cmd_screenshot() {
    check_adb
    local name="${1:-screenshot_$(date +%Y%m%d_%H%M%S)}"
    local out="$OUT_DIR/${name}.png"
    adb shell screencap -p /sdcard/screen.png 2>/dev/null
    adb pull /sdcard/screen.png "$out" 2>/dev/null
    adb shell rm /sdcard/screen.png 2>/dev/null
    if [[ -f "$out" ]]; then
        local size; size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")
        log_ok "Screenshot: $out ($((size/1024))KB)"
    else log_fail "Screenshot failed"; fi
}

cmd_ui_dump() {
    check_adb
    local out="${1:-$OUT_DIR/ui_dump_$(date +%Y%m%d_%H%M%S).xml}"
    mkdir -p "$(dirname "$out")"
    log_progress "Dumping UI"
    adb shell uiautomator dump /sdcard/ui.xml 2>/dev/null && \
    adb pull /sdcard/ui.xml "$out" 2>/dev/null && \
    adb shell rm /sdcard/ui.xml 2>/dev/null
    if [[ -f "$out" ]]; then
        local elements; elements=$(grep -c 'class=' "$out" 2>/dev/null || echo 0)
        log_done "UI dump: $out ($elements elements)"
    else log_fail "UI dump failed"; fi
}

cmd_find_text() {
    check_adb; local text="${1:?Usage: $0 find-text <text>}"
    local tmp="/tmp/androx_uifind.xml"
    cmd_ui_dump "$tmp" >/dev/null 2>&1
    if [[ -f "$tmp" ]] && grep -qi "$text" "$tmp" 2>/dev/null; then
        log_ok "Found: '$text'"
        grep -i "$text" "$tmp" | head -5 | sed 's/^/  /'
    else log_warn "Not found: '$text'"; fi
}

cmd_click_text() {
    check_adb; local text="${1:?Usage: $0 click-text <text>}"
    local tmp="/tmp/androx_uiclick.xml"
    cmd_ui_dump "$tmp" >/dev/null 2>&1
    if [[ ! -f "$tmp" ]]; then log_fail "Cannot dump UI"; exit 1; fi
    local bounds; bounds=$(grep -oP "text=\"$text\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"" "$tmp" 2>/dev/null | head -1)
    if [[ -z "$bounds" ]]; then
        bounds=$(grep -oP "text=\"[^\"]*$text[^\"]*\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"" "$tmp" 2>/dev/null | head -1)
    fi
    if [[ -n "$bounds" ]]; then
        local coords; coords=$(echo "$bounds" | grep -oP '\[\K\d+,\d+(?=\])' | head -1)
        local x1; x1=$(echo "$coords" | cut -d, -f1); local y1; y1=$(echo "$coords" | cut -d, -f2)
        local coords2; coords2=$(echo "$bounds" | grep -oP '\[\K\d+,\d+(?=\])' | tail -1)
        local x2; x2=$(echo "$coords2" | cut -d, -f1); local y2; y2=$(echo "$coords2" | cut -d, -f2)
        local cx=$(( (x1 + x2) / 2 )); local cy=$(( (y1 + y2) / 2 ))
        tap "$cx" "$cy"
        log_ok "Clicked: '$text' at ($cx, $cy)"
    else log_warn "Could not find clickable element for '$text'"; fi
}

cmd_wait_text() {
    check_adb
    local text="${1:?Usage: $0 wait-text <text> [timeout]}"
    local timeout="${2:-15}"; local tmp="/tmp/androx_uiwait.xml"
    log_progress "Waiting for '$text' (${timeout}s)"
    for ((i=1; i<=timeout; i++)); do
        cmd_ui_dump "$tmp" >/dev/null 2>&1
        if [[ -f "$tmp" ]] && grep -qi "$text" "$tmp" 2>/dev/null; then
            log_done "Found after ${i}s"
            return 0
        fi
        echo -ne "\r  ${DIM}Waiting: ${i}/${timeout}s${NC}  "
        sleep 1
    done
    echo; log_warn "Not found after ${timeout}s"; return 1
}

cmd_list_bounds() {
    check_adb; local tmp="/tmp/androx_uibounds.xml"
    cmd_ui_dump "$tmp" >/dev/null 2>&1
    [[ ! -f "$tmp" ]] && { log_fail "Cannot dump UI"; exit 1; }
    log_section "UI ELEMENT BOUNDS"
    grep -oP 'class="[^"]*".*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' "$tmp" 2>/dev/null | head -30 | while IFS= read -r line; do
        local cls; cls=$(echo "$line" | grep -oP 'class="\K[^"]+')
        local bnd; bnd=$(echo "$line" | grep -oP 'bounds="\K[^"]+')
        echo "  $cls → $bnd"
    done
}

# ─── APP MANAGEMENT ─────────────────────────────────────────

cmd_open_app() {
    check_adb
    local pkg="${1:?Usage: $0 open-app <package> [activity]}"
    local activity="${2:-}"
    if [[ -n "$activity" ]]; then
        adb shell am start -n "$pkg/$activity" 2>/dev/null
    else
        adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 2>/dev/null
    fi
    log_ok "Opened: $pkg"; sleep 2
}

cmd_close_app() {
    check_adb; local pkg="${1:?Usage: $0 close-app <package>}"
    adb shell am kill "$pkg" 2>/dev/null || true
    log_ok "Closed: $pkg"
}

cmd_force_stop() {
    check_adb; local pkg="${1:?Usage: $0 force-stop <package>}"
    adb shell am force-stop "$pkg" 2>/dev/null && log_ok "Force-stopped: $pkg" || log_err "Failed"
}

cmd_install_test() {
    check_adb; local apk="${1:?Usage: $0 install-test <apk>}"
    [[ ! -f "$apk" ]] && { log_err "APK not found"; exit 1; }
    log_section "INSTALL-TEST: $(basename "$apk")"
    log_progress "Installing"
    local result; result=$(adb install -r -t "$apk" 2>&1 | tail -1)
    echo "$result"
    if echo "$result" | grep -q "Success"; then
        log_done "Installed"
        local pkg; pkg=$(aapt dump badging "$apk" 2>/dev/null | grep "package: name=" | grep -oP "name='\K[^']+" || echo "")
        [[ -z "$pkg" ]] && pkg=$(basename "$apk" .apk)
        log_info "Launching $pkg..."; cmd_open_app "$pkg" || true; sleep 2
        cmd_screenshot "${pkg}_test"; log_ok "Screenshot captured"
        cmd_force_stop "$pkg" || true
    else log_fail "Install failed"; fi
}

cmd_clear_app() {
    check_adb; local pkg="${1:?Usage: $0 clear-app <package>}"
    adb shell pm clear "$pkg" 2>/dev/null && log_ok "Cleared: $pkg" || log_err "Failed"
}

# ─── MONKEY ─────────────────────────────────────────────────

cmd_monkey() {
    check_adb
    local pkg="${1:-}"; local events="${2:-1000}"; local throttle="${3:-100}"
    log_section "MONKEY TEST: ${pkg:-All apps}"
    echo "  ${BOLD}Events:${NC} $events  ${BOLD}Throttle:${NC} ${throttle}ms"
    if [[ -z "$pkg" ]]; then
        adb shell monkey --throttle "$throttle" --ignore-security-exceptions --ignore-crashes --ignore-timeouts -v "$events" 2>&1 | tail -5
    else
        adb shell monkey -p "$pkg" --throttle "$throttle" --ignore-security-exceptions --ignore-crashes -v "$events" 2>&1 | tail -5
    fi
}

cmd_monkey_optimized() {
    check_adb; local pkg="${1:-}"; local seed=$((RANDOM % 10000)); local events="2000"; local throttle="150"
    log_section "OPTIMIZED MONKEY"
    echo "  ${BOLD}Seed:${NC} $seed  ${BOLD}Events:${NC} $events  ${BOLD}Throttle:${NC} ${throttle}ms"
    local base="adb shell monkey -s $seed --throttle $throttle --ignore-security-exceptions --ignore-crashes --pct-touch 30 --pct-motion 20 --pct-nav 10 --pct-majornav 10 --pct-syskeys 5 --pct-appswitch 15 --pct-anyevent 10 -v $events"
    if [[ -n "$pkg" ]]; then base="$base -p $pkg"; fi
    eval "$base" 2>&1 | tail -10
}

cmd_monkey_log() {
    check_adb; local logfile="${1:?Usage: $0 monkey-log <logfile>}"
    [[ ! -f "$logfile" ]] && { log_err "Log not found"; exit 1; }
    log_section "REPLAY MONKEY LOG: $(basename "$logfile")"
    while IFS= read -r line; do
        case "$line" in
            tap:*)      local c="${line#tap:}"; tap "${c%,*}" "${c#*,}";;
            swipe:*)    local p="${line#swipe:}"; IFS=, read -ra a <<< "$p"; swipe "${a[0]}" "${a[1]}" "${a[2]}" "${a[3]}" "${a[4]:-200}";;
            wait:*)     sleep "${line#wait:}";;
            \#*)        ;;
            *)          [[ -n "$line" ]] && log_info "Unknown: $line";;
        esac
    done < "$logfile"
    log_ok "Replay complete"
}

# ─── RECORDING ──────────────────────────────────────────────

cmd_record() {
    check_adb; local duration="${1:-30}"; local out="$OUT_DIR/record_$(date +%Y%m%d_%H%M%S).mp4"
    [[ $duration -gt 180 ]] && { log_warn "Max 180s, capping"; duration=180; }
    log_section "SCREEN RECORDING (${duration}s)"
    log_progress "Recording"
    adb shell screenrecord --time-limit "$duration" --bit-rate 4000000 /sdcard/record.mp4 2>/dev/null &
    local pid=$!
    for ((i=1; i<=duration; i++)); do echo -ne "\r  ${DIM}Recording: ${i}/${duration}s${NC}  "; sleep 1; done
    echo; wait $pid 2>/dev/null || true; sleep 1
    adb pull /sdcard/record.mp4 "$out" 2>/dev/null
    adb shell rm /sdcard/record.mp4 2>/dev/null
    [[ -f "$out" ]] && log_done "Recording: $out ($(( $(stat -c%s "$out" 2>/dev/null || stat -f%z "$out") /1024/1024 ))MB)" || log_fail "Recording failed"
}

cmd_record_input() {
    local out="$OUT_DIR/input_events_$(date +%Y%m%d_%H%M%S).log"
    log_section "RECORDING INPUT EVENTS"
    log_info "Recording to $out (press Ctrl+C to stop)"
    log_info "Format: tap:x,y or swipe:x1,y1,x2,y2,ms"
    > "$out"
    log_info "Enter commands (one per line), empty line to stop:"
    while true; do
        read -r -p "  > " input
        [[ -z "$input" ]] && break
        echo "$input" >> "$out"
        case "$input" in
            tap:*)      local c="${input#tap:}"; tap "${c%,*}" "${c#*,}" && log_ok "Tapped";;
            swipe:*)    local p="${input#swipe:}"; IFS=, read -ra a <<< "$p"; swipe "${a[0]}" "${a[1]}" "${a[2]}" "${a[3]}" "${a[4]:-200}" && log_ok "Swiped";;
            wait:*)     sleep "${input#wait:}";;
            type:*)     type_text "${input#type:}" && log_ok "Typed";;
            key:*)      cmd_key "${input#key:}";;
            screenshot) cmd_screenshot;;
            *)          log_warn "Unknown: use tap:x,y | swipe:x1,y1,x2,y2,ms | type:text | key:name | wait:secs | screenshot";;
        esac
    done
    log_ok "Recorded to: $out ($(wc -l < "$out") commands)"
}

cmd_replay() {
    local file="${1:?Usage: $0 replay <file>}"
    [[ ! -f "$file" ]] && { log_err "File not found"; exit 1; }
    log_section "REPLAY INPUT: $(basename "$file")"
    check_adb
    local count=0
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        [[ -z "$line" ]] && continue
        ((count++)) || true
        echo -ne "\r  ${DIM}Command $count: $line${NC}  "
        case "$line" in
            tap:*)      local c="${line#tap:}"; tap "${c%,*}" "${c#*,}";;
            swipe:*)    local p="${line#swipe:}"; IFS=, read -ra a <<< "$p"; swipe "${a[0]}" "${a[1]}" "${a[2]}" "${a[3]}" "${a[4]:-200}";;
            type:*)     type_text "${line#type:}";;
            key:*)      cmd_key "${line#key:}" >/dev/null 2>&1;;
            wait:*)     sleep "${line#wait:}";;
            screenshot) cmd_screenshot >/dev/null 2>&1;;
            open:*)     cmd_open_app "${line#open:}" >/dev/null 2>&1;;
            *)          log_warn "Unknown: $line";;
        esac
        sleep 0.5
    done < "$file"
    echo; log_ok "Replayed $count commands"
}

# ─── WORKFLOW ───────────────────────────────────────────────

cmd_workflow() {
    local script="${1:?Usage: $0 workflow <script>}"
    [[ ! -f "$script" ]] && { log_err "Script not found"; exit 1; }
    log_section "WORKFLOW: $(basename "$script")"
    check_adb

    mkdir -p "$OUT_DIR/workflow"
    local step=0
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        [[ -z "$line" ]] && continue
        ((step++)) || true
        log_progress "Step $step"
        case "$line" in
            tap:*)      local c="${line#tap:}"; tap "${c%,*}" "${c#*,}" && log_done "Tap ${c%,*},${c#*,}";;
            swipe:*)    local p="${line#swipe:}"; IFS=, read -ra a <<< "$p"; swipe "${a[0]}" "${a[1]}" "${a[2]}" "${a[3]}" "${a[4]:-200}" && log_done "Swiped";;
            type:*)     type_text "${line#type:}" && log_done "Typed";;
            key:*)      cmd_key "${line#key:}" >/dev/null 2>&1 && log_done "Key: ${line#key:}";;
            wait:*)     sleep "${line#wait:}" && log_done "Waited ${line#wait:}s";;
            screenshot) cmd_screenshot "$OUT_DIR/workflow/step_${step}" >/dev/null 2>&1 && log_done "Screenshot";;
            open:*)     cmd_open_app "${line#open:}" >/dev/null 2>&1 && log_done "Opened ${line#open:}";;
            close:*)    adb shell am force-stop "${line#close:}" 2>/dev/null && log_done "Closed ${line#close:}";;
            text:*)     cmd_find_text "${line#text:}" >/dev/null 2>&1 && log_done "Found text";;
            click:*)    cmd_click_text "${line#click:}" >/dev/null 2>&1 && log_done "Clicked text";;
            ui-dump)    cmd_ui_dump "$OUT_DIR/workflow/ui_step_${step}.xml" >/dev/null 2>&1 && log_done "UI dumped";;
            monkey*)    local args="${line#monkey }"; cmd_monkey $args >/dev/null 2>&1 && log_done "Monkey test";;
            *)          log_fail "Unknown: $line";;
        esac
        sleep 1
    done < "$script"
    echo; log_ok "Workflow complete: $step steps"
}

cmd_create_script() {
    local file="${1:-workflow_script.txt}"
    cat > "$file" << 'EOF'
# AndroXploit Automation Workflow Script
# Commands: tap, swipe, type, key, wait, screenshot, open, close, text, click, ui-dump, monkey
# Example workflow:

# Step 1: Open Settings
open:com.android.settings

# Step 2: Wait for UI
wait:3

# Step 3: Screenshot
screenshot

# Step 4: Find and click text
click:Security

# Step 5: Wait and verify
wait:2
text:Screen lock

# Step 6: Go back
key:back

# Step 7: Close app
close:com.android.settings
EOF
    log_ok "Created: $file"
}

cmd_run_commands() {
    local cmdfile="${1:?Usage: $0 run-commands <cmdfile>}"
    [[ ! -f "$cmdfile" ]] && { log_err "File not found"; exit 1; }
    check_adb
    log_section "RUN COMMANDS: $(basename "$cmdfile")"
    local count=0
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        [[ -z "$line" ]] && continue
        ((count++)) || true
        log_progress "ADB: $line"
        adb shell "$line" 2>/dev/null && log_done "OK" || log_fail "Failed"
    done < "$cmdfile"
    echo; log_ok "Executed $count commands"
}

# ─── MAIN ────────────────────────────────────────────────────

main() {
    [[ $# -lt 1 ]] && { show_help; exit 0; }
    local cmd="$1"; shift

    case "$cmd" in
        tap|click)             cmd_tap "$@";;
        swipe|scroll)          cmd_swipe "$@";;
        type|text)             cmd_type "$@";;
        key|press)             cmd_key "$@";;
        long-press|longpress)  cmd_long_press "$@";;
        pinch|zoom)            cmd_pinch "$@";;
        screenshot|ss)         cmd_screenshot "$@";;
        ui-dump|uiautomator)   cmd_ui_dump "$@";;
        find-text|find)        cmd_find_text "$@";;
        click-text|clicktext)  cmd_click_text "$@";;
        wait-text|waitfor)     cmd_wait_text "$@";;
        list-bounds|bounds)    cmd_list_bounds;;
        open-app|launch|open)  cmd_open_app "$@";;
        close-app|close)       cmd_close_app "$@";;
        force-stop|kill)       cmd_force_stop "$@";;
        install-test|itest)    cmd_install_test "$@";;
        clear-app|cleardata)   cmd_clear_app "$@";;
        monkey|monkeytest)     cmd_monkey "$@";;
        monkey-optimized|mopt) cmd_monkey_optimized "$@";;
        monkey-log|mlog)       cmd_monkey_log "$@";;
        record|screenrecord)   cmd_record "$@";;
        record-input|recinput) cmd_record_input;;
        replay|play)           cmd_replay "$@";;
        workflow|script)       cmd_workflow "$@";;
        create-script|template) cmd_create_script "$@";;
        run-commands|adbfile)  cmd_run_commands "$@";;
        help|-h|--help)        show_help;;
        *) log_err "Unknown: $cmd"; show_help; exit 1;;
    esac
}

main "$@"
