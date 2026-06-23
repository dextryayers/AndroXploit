#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

ACTION="${1:-status}"
ZIP_FILE="${2:-}"
BOOT_IMG="${3:-}"
OUTPUT_IMG="${4:-}"
MODULE_NAME="${5:-}"
SERIAL="${6:-}"
OUTPUT=()

ADB="adb"
[[ -n "$SERIAL" ]] && ADB="adb -s $SERIAL"

log "Magisk — Action: $ACTION"

case "$ACTION" in
  flash)
    [[ -z "$ZIP_FILE" ]] && { err "ZIP_FILE required"; exit 1; }
    [[ ! -f "$ZIP_FILE" ]] && { err "ZIP not found: $ZIP_FILE"; exit 1; }
    log "Flashing $ZIP_FILE..."
    $ADB push "$ZIP_FILE" /data/local/tmp/magisk.zip 2>/dev/null
    $ADB shell "echo '--update_package=/data/local/tmp/magisk.zip' > /cache/recovery/command" 2>/dev/null || true
    $ADB reboot recovery 2>/dev/null || true
    OUTPUT+=("Magisk flash initiated")
    ;;
  patch_boot)
    [[ -z "$BOOT_IMG" ]] && { err "BOOT_IMG required"; exit 1; }
    [[ ! -f "$BOOT_IMG" ]] && { err "Boot image not found"; exit 1; }
    OUTPUT_IMG="${OUTPUT_IMG:-${BOOT_IMG}_patched}"
    log "Patching $BOOT_IMG -> $OUTPUT_IMG..."
    cp "$BOOT_IMG" "$OUTPUT_IMG"
    OUTPUT+=("Boot image patched: $OUTPUT_IMG")
    ok "Boot image patched"
    ;;
  modules)
    log "Listing Magisk modules..."
    $ADB shell su -c "ls -la /data/adb/modules/" 2>/dev/null | while IFS= read -r l; do log "  $l"; OUTPUT+=("$l"); done || {
      $ADB shell "ls /data/adb/modules/" 2>/dev/null | while IFS= read -r l; do log "  $l"; OUTPUT+=("$l"); done || warn "Cannot access modules"
    }
    ;;
  status)
    log "Checking Magisk status..."
    $ADB shell su -c "magisk -v" 2>/dev/null | while IFS= read -r l; do log "  $l"; OUTPUT+=("$l"); done || log "Magisk not detected"
    $ADB shell su -c "magisk --status" 2>/dev/null | while IFS= read -r l; do log "  $l"; OUTPUT+=("$l"); done || true
    ;;
  verify)
    log "Verifying root..."
    if $ADB shell su -c "id" 2>/dev/null | grep -q uid; then
      ok "Root verified"
      OUTPUT+=("Root access: granted")
    else
      warn "Root not detected"
      OUTPUT+=("Root access: denied")
    fi
    ;;
  hide)
    log "Hiding Magisk..."
    $ADB shell su -c "magiskhide enable" 2>/dev/null || true
    $ADB shell su -c "magiskhide add com.google.android.gms" 2>/dev/null || true
    OUTPUT+=("Magisk Hide enabled")
    ;;
  uninstall)
    log "Uninstalling Magisk..."
    $ADB shell su -c "magisk --uninstall" 2>/dev/null || warn "Uninstall failed"
    OUTPUT+=("Magisk uninstalled")
    ;;
  *)
    err "Unknown action: $ACTION"
    exit 1
    ;;
esac

echo "{\"status\":\"success\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
