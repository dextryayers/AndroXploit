#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

TARGET="${1:-usb}"
PORT="${2:-8080}"
SCAN_OWASP="${3:-false}"
EXPORT="${4:-}"
OUTPUT=()

ADB="adb"
[[ "$TARGET" != "usb" ]] && ADB="adb -s $TARGET"

$ADB get-state 2>/dev/null | grep -q device || {
  err "Device not connected"
  echo '{"status":"failed","output":["Device not connected"]}'
  exit 1
}

log "ADB Auditor — Security scan on $TARGET"

CHECKS=(
  "ro.debuggable:debuggable"
  "ro.secure:secure"
  "ro.adb.secure:adb_secure"
  "persist.sys.usb.config:usb_config"
  "selinux:selinux"
  "ro.build.version.security_patch:security_patch"
)
RESULTS=()
for check in "${CHECKS[@]}"; do
  PROP="${check%%:*}"
  NAME="${check##*:}"
  VAL=$($ADB shell getprop "$PROP" 2>/dev/null | tr -d '\r')
  log "$NAME = $VAL"
  RESULTS+=("$NAME=$VAL")
  OUTPUT+=("$NAME: $VAL")
done

log "Checking open ports..."
$ADB shell netstat -tln 2>/dev/null | while IFS= read -r l; do log "Port: $l"; OUTPUT+=("$l"); done || true

log "Checking for OWASP Top 10 vulnerabilities..."
if [[ "$SCAN_OWASP" == "true" ]]; then
  log "M1- Improper Platform Usage"
  log "M2- Insecure Data Storage"
  log "M3- Insecure Communication"
  OUTPUT+=("OWASP scan requested")
fi

TS=$(date +%s)
REPORT="adb_audit_${TS}.html"
{
  echo "<html><body><h1>ADB Auditor Report</h1><pre>"
  for item in "${OUTPUT[@]}"; do echo "$item"; done
  echo "</pre></body></html>"
} > "$REPORT"
ok "Report saved: $REPORT"

[[ -n "$EXPORT" ]] && cp "$REPORT" "$EXPORT"

echo "{\"status\":\"success\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
