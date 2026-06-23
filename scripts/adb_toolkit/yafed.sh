#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

TARGET="${1:-usb}"
OUTPUT="${2:-yafed_output}"
FLAGS="${3:-all}"
PARALLEL="${4:-false}"
OUTPUT_LIST=()

ADB="adb"
[[ "$TARGET" != "usb" ]] && ADB="adb -s $TARGET"

$ADB get-state 2>/dev/null | grep -q device || {
  err "Device not connected"
  echo '{"status":"failed","output":["Device not connected"]}'
  exit 1
}

mkdir -p "$OUTPUT"
log "YAFED — Forensics extraction to $OUTPUT"

collect_bugreport() {
  log "Collecting bugreport..."
  $ADB bugreport "$OUTPUT/bugreport_$(date +%s).zip" 2>/dev/null && {
    ok "Bugreport saved"
    OUTPUT_LIST+=("bugreport collected")
  } || warn "Bugreport failed"
}

collect_content_providers() {
  log "Dumping content providers..."
  $ADB shell content query --uri content://settings/secure 2>/dev/null > "$OUTPUT/settings_secure.txt" || true
  $ADB shell content query --uri content://settings/global 2>/dev/null > "$OUTPUT/settings_global.txt" || true
  $ADB shell content query --uri content://settings/system 2>/dev/null > "$OUTPUT/settings_system.txt" || true
  OUTPUT_LIST+=("content providers dumped")
}

collect_packages() {
  log "Dumping package list..."
  $ADB shell pm list packages -f 2>/dev/null > "$OUTPUT/packages.txt"
  OUTPUT_LIST+=("package list dumped")
}

collect_dumpsys() {
  log "Dumping dumpsys..."
  for svc in battery wifi activity package window meminfo diskstats cpuinfo power; do
    $ADB shell dumpsys "$svc" 2>/dev/null > "$OUTPUT/dumpsys_${svc}.txt" || true
  done
  OUTPUT_LIST+=("dumpsys dumped")
}

collect_logs() {
  log "Collecting logs..."
  $ADB logcat -d -v threadtime 2>/dev/null > "$OUTPUT/logcat.txt"
  $ADB shell dmesg 2>/dev/null > "$OUTPUT/dmesg.txt" || true
  OUTPUT_LIST+=("logs collected")
}

case "$FLAGS" in
  all)     collect_bugreport; collect_content_providers; collect_packages; collect_dumpsys; collect_logs;;
  bugreport) collect_bugreport;;
  providers) collect_content_providers;;
  packages)  collect_packages;;
  dumpsys)   collect_dumpsys;;
  logs)      collect_logs;;
  *)         collect_bugreport;;
esac

ok "Forensics extraction complete in $OUTPUT"
echo "{\"status\":\"success\",\"output\":[\"${OUTPUT_LIST[*]//\"/\\\"}\"]}"
