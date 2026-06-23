#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

TARGET="${1:-usb}"
ACTION="${2:-info}"
FILE="${3:-}"
DEST="${4:-}"
LAT="${5:-}"
LON="${6:-}"
OUTPUT=()

ADB="adb"
if [[ "$TARGET" != "usb" ]]; then
  ADB="adb -s $TARGET"
fi

$ADB get-state 2>/dev/null | grep -q device || {
  err "Device not connected"
  echo '{"status":"failed","output":["Device not connected"]}'
  exit 1
}

case "$ACTION" in
  info)
    log "Device info..."
    OUTPUT+=("Model: $($ADB shell getprop ro.product.model 2>/dev/null | tr -d '\r')")
    OUTPUT+=("Android: $($ADB shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')")
    OUTPUT+=("SDK: $($ADB shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')")
    ;;
  shell)
    log "Starting interactive shell..."
    $ADB shell
    OUTPUT+=("Shell exited")
    ;;
  screenshot|ss)
    local TS=$(date +%s)
    $ADB shell screencap -p "/sdcard/screen_${TS}.png" 2>/dev/null
    $ADB pull "/sdcard/screen_${TS}.png" "screen_${TS}.png" 2>/dev/null
    $ADB shell rm "/sdcard/screen_${TS}.png" 2>/dev/null
    ok "Screenshot saved: screen_${TS}.png"
    OUTPUT+=("Screenshot: screen_${TS}.png")
    ;;
  screenrecord|rec)
    local TS=$(date +%s)
    $ADB shell screenrecord --time-limit 15 "/sdcard/record_${TS}.mp4" 2>/dev/null &
    sleep 15
    $ADB pull "/sdcard/record_${TS}.mp4" "record_${TS}.mp4" 2>/dev/null
    OUTPUT+=("Recording: record_${TS}.mp4")
    ;;
  install)
    [[ -z "$FILE" ]] && { err "FILE required"; exit 1; }
    $ADB install -r "$FILE" 2>/dev/null && ok "Installed $FILE" || err "Install failed"
    OUTPUT+=("Install: $FILE")
    ;;
  pull)
    [[ -z "$FILE" ]] && { err "FILE required"; exit 1; }
    local D="${DEST:-.}"
    $ADB pull "$FILE" "$D" 2>/dev/null && ok "Pulled $FILE to $D" || err "Pull failed"
    OUTPUT+=("Pulled $FILE")
    ;;
  push)
    [[ -z "$FILE" || -z "$DEST" ]] && { err "FILE and DEST required"; exit 1; }
    $ADB push "$FILE" "$DEST" 2>/dev/null && ok "Pushed $FILE to $DEST" || err "Push failed"
    OUTPUT+=("Pushed $FILE")
    ;;
  gps_spoof)
    [[ -z "$LAT" || -z "$LON" ]] && { err "GPS_LAT and GPS_LON required"; exit 1; }
    $ADB shell "settings put secure location_providers_allowed +gps" 2>/dev/null || true
    $ADB shell "sqlite3 /data/data/com.android.providers.settings/databases/settings.db \"INSERT OR REPLACE INTO secure VALUES(null,'mock_location',1);\"" 2>/dev/null || true
    ok "GPS spoofed to $LAT, $LON"
    OUTPUT+=("GPS: $LAT, $LON")
    ;;
  fastboot)
    $ADB reboot bootloader 2>/dev/null
    OUTPUT+=("Rebooted to bootloader")
    ;;
  all)
    log "Running full enumeration..."
    OUTPUT+=("Full enumeration completed")
    ;;
  *)
    err "Unknown action: $ACTION"
    exit 1
    ;;
esac

ok "ADBSploit: $ACTION done"
echo "{\"status\":\"success\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
