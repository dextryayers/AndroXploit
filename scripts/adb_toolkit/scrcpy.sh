#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }
section() { echo -e "\n${C}════════════════════════════════════════${NC}"; echo -e "${C}  $1${NC}"; echo -e "${C}════════════════════════════════════════${NC}"; }

TARGET="${1:-usb}"
MAX_SIZE="${2:-1024}"
BITRATE="${3:-8000000}"
RECORD="${4:-}"
NO_CONTROL="${5:-false}"
TURN_OFF="${6:-false}"
STAY_AWAKE="${7:-false}"
CROP="${8:-}"
OUTPUT=()

usage() {
  echo "Usage: $0 <target> <max_size> <bitrate> <record> <no_control> <turn_off> <stay_awake> <crop>"
  echo "  target     Device serial or 'usb' (default: usb)"
  echo "  max_size   Max screen size (default: 1024)"
  echo "  bitrate    Bitrate in bps (default: 8000000)"
  echo "  record     Output file path for recording (optional)"
  echo "  no_control Disable control (default: false)"
  echo "  turn_off   Turn screen off after mirroring (default: false)"
  echo "  stay_awake Keep device awake (default: false)"
  echo "  crop       Crop dimensions W:H:X:Y (optional)"
  exit 1
}

[[ "$1" == "-h" || "$1" == "--help" ]] && usage

command -v scrcpy &>/dev/null || {
  err "scrcpy not installed. Install with: apt install scrcpy"
  echo '{"status":"failed","output":["scrcpy not found"]}'
  exit 1
}

ADB="adb"
[[ "$TARGET" != "usb" ]] && ADB="adb -s $TARGET"
SERIAL_ARG=""
[[ "$TARGET" != "usb" ]] && SERIAL_ARG="$TARGET"

section "SCRCPY — ANDROID SCREEN MIRROR"
log "Target: ${TARGET}"
log "Max size: ${MAX_SIZE}"
log "Bitrate: ${BITRATE}"

if [[ -z "$RECORD" ]]; then
  log "Mode: live mirror"
else
  log "Mode: recording to $RECORD"
fi

log "No control: ${NO_CONTROL}"
log "Turn off: ${TURN_OFF}"
log "Stay awake: ${STAY_AWAKE}"
[[ -n "$CROP" ]] && log "Crop: ${CROP}"

$ADB get-state 2>/dev/null | grep -q device || {
  err "Device not connected"
  echo '{"status":"failed","output":["Device not connected"]}'
  exit 1
}

log "Verifying scrcpy-server on device..."
$ADB shell ls /data/local/tmp/scrcpy-server.jar 2>/dev/null || {
  warn "scrcpy-server not pushed — scrcpy will handle automatically"
}

ARGS=("--max-size" "$MAX_SIZE" "--bit-rate" "$BITRATE")
[[ -n "$RECORD" ]] && ARGS+=("--record" "$RECORD")
[[ "$NO_CONTROL" == "true" ]] && ARGS+=("--no-control")
[[ "$TURN_OFF" == "true" ]] && ARGS+=("--turn-screen-off")
[[ "$STAY_AWAKE" == "true" ]] && ARGS+=("--stay-awake")
[[ -n "$CROP" ]] && ARGS+=("--crop" "$CROP")

if [[ "$TARGET" != "usb" ]]; then
  ARGS+=("--serial" "$TARGET")
fi

section "LAUNCHING SCRCPY"
log "scrcpy ${ARGS[*]}"
scrcpy "${ARGS[@]}"
RET=$?

if [[ $RET -eq 0 ]]; then
  ok "scrcpy exited normally"
else
  warn "scrcpy exited with code $RET"
fi

OUTPUT+=("scrcpy session ended (exit: $RET)")
echo "{\"status\":\"success\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
