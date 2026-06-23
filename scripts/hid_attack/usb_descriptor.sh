#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

DEVICE="${1:-}"
TARGET="${2:-all}"
ANALYZE_HID="${3:-false}"
EXPORT_JSON="${4:-false}"
OUTPUT=()

SYS_USB="/sys/bus/usb/devices"

if [[ ! -d "$SYS_USB" ]]; then
  err "USB sysfs not available"
  echo '{"status":"failed","output":["USB sysfs not found"]}'
  exit 1
fi

if [[ -n "$DEVICE" ]]; then
  DEV_PATH="$SYS_USB/$DEVICE"
  [[ ! -d "$DEV_PATH" ]] && { err "Device $DEVICE not found"; exit 1; }
  DEVICES=("$DEV_PATH")
else
  mapfile -t DEVICES < <(find "$SYS_USB" -maxdepth 1 -type d -name '*:*' 2>/dev/null)
fi

for dev in "${DEVICES[@]}"; do
  NAME=$(basename "$dev")
  log "Device: $NAME"
  for attr in manufacturer product idVendor idProduct bDeviceClass bDeviceSubClass bDeviceProtocol bNumConfigurations; do
    F="$dev/$attr"
    [[ -f "$F" ]] && {
      VAL=$(cat "$F" 2>/dev/null)
      log "  $attr: $VAL"
      OUTPUT+=("$NAME/$attr=$VAL")
    }
  done

  if [[ -d "$dev/bInterfaceClass" ]] || compgen -G "$dev:*/bInterfaceClass" >/dev/null 2>&1; then
    log "  HID descriptor found"
    OUTPUT+=("$NAME: HID device")
  fi
done

if [[ "$ANALYZE_HID" == "true" ]]; then
  log "HID analysis enabled"
  for dev in "${DEVICES[@]}"; do
    HID_DESC="$dev/report_descriptor"
    [[ -f "$HID_DESC" ]] && {
      hexdump -C "$HID_DESC" 2>/dev/null | while IFS= read -r l; do log "  HID: $l"; OUTPUT+=("$l"); done
    } || true
  done
fi

if [[ "$EXPORT_JSON" == "true" ]]; then
  JSON_FILE="usb_descriptors_$(date +%s).json"
  echo "[" > "$JSON_FILE"
  local first=true
  for dev in "${DEVICES[@]}"; do
    $first || echo "," >> "$JSON_FILE"
    first=false
    echo "{ \"device\": \"$(basename "$dev")\"" >> "$JSON_FILE"
    for attr in manufacturer product idVendor idProduct; do
      F="$dev/$attr"
      [[ -f "$F" ]] && echo ", \"$attr\": \"$(cat "$F" 2>/dev/null)\"" >> "$JSON_FILE"
    done
    echo "}" >> "$JSON_FILE"
  done
  echo "]" >> "$JSON_FILE"
  ok "JSON exported: $JSON_FILE"
fi

ok "USB descriptor analysis complete"
echo "{\"status\":\"success\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
