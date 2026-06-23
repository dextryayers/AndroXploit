#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }
section() { echo -e "\n${C}════════════════════════════════════════${NC}"; echo -e "${C}  $1${NC}"; echo -e "${C}════════════════════════════════════════${NC}"; }

DEVICE="${1:-/dev/hidg0}"
LAYOUT="${2:-us}"
PAYLOAD="${3:-}"
DELAY="${4:-100}"
REPEAT="${5:-1}"
OUTPUT=()

cleanup() { true; }
trap cleanup EXIT

usage() {
  echo "Usage: $0 <device> <layout> <payload> <delay> <repeat>"
  echo "  device   HID gadget path (default: /dev/hidg0)"
  echo "  layout   Keyboard layout: us, de, fr, etc. (default: us)"
  echo "  payload  Path to Rubber Ducky payload .txt file"
  echo "  delay    Delay in ms between keystrokes (default: 100)"
  echo "  repeat   Number of times to repeat payload (default: 1)"
  exit 1
}

[[ -z "$PAYLOAD" || "$1" == "-h" || "$1" == "--help" ]] && usage

if [[ ! -f "$PAYLOAD" ]]; then
  err "Payload file not found: $PAYLOAD"
  echo '{"status":"failed","output":["Payload file not found"]}'
  exit 1
fi

section "KALI NETHUNTER — BADUSB INJECTION"
log "Device: $DEVICE"
log "Layout: $LAYOUT"
log "Payload: $PAYLOAD"
log "Delay: ${DELAY}ms"
log "Repeat: ${REPEAT}x"

if [[ ! -e "$DEVICE" ]]; then
  err "HID gadget not found at $DEVICE"
  echo '{"status":"failed","output":["HID gadget not found"]}'
  exit 1
fi

LAYOUT_FILE="/usr/share/kali-nethunter/keyboard/${LAYOUT}.kl"
if [[ -f "$LAYOUT_FILE" ]]; then
  log "Loading layout: $LAYOUT_FILE"
  OUTPUT+=("Layout: $LAYOUT")
fi

PAYLOAD_DATA=$(cat "$PAYLOAD")
IFS=$'\n' read -d '' -r -a LINES <<< "$PAYLOAD_DATA" || true
log "Payload lines: ${#LINES[@]}"

section "INJECTION STARTED"
for ((r=0; r<REPEAT; r++)); do
  if (( REPEAT > 1 )); then log "Repeat $((r+1))/$REPEAT"; fi
  COUNT=0
  for line in "${LINES[@]}"; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" =~ ^REM ]] && continue

    STRING_MODE=false
    if [[ "$line" =~ ^STRING[[:space:]] ]]; then
      TEXT="${line#STRING }"
      STRING_MODE=true
    fi

    echo -e "$line" > "$DEVICE" 2>/dev/null || {
      warn "Write failed at line: $line"
      continue
    }
    ((COUNT++))
    sleep "$(bc <<< "scale=3; $DELAY/1000")" 2>/dev/null || sleep 0.1
    OUTPUT+=("$line")
  done
  log "Repeat $((r+1)): $COUNT lines injected"
done

section "INJECTION COMPLETE"
ok "BadUSB injection completed — ${#OUTPUT[@]} total keystrokes"
echo "{\"status\":\"success\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
