#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

APK="${1:-}"
ACTION="${2:-info}"
OUTPUT="${3:-}"
PATCH="${4:-}"
KEYSTORE="${5:-}"
DECOMPILE="${6:-false}"
OUTPUT_LIST=()

for cmd in apktool zipalign jarsigner; do
  command -v "$cmd" &>/dev/null || warn "$cmd not installed"
done

if [[ -z "$APK" || ! -f "$APK" ]]; then
  err "APK file not found"
  echo '{"status":"failed","output":["APK not found"]}'
  exit 1
fi

APK_NAME=$(basename "$APK" .apk)
OUTPUT="${OUTPUT:-${APK_NAME}_patched.apk}"
KEYSTORE="${KEYSTORE:-debug.keystore}"

log "APKLab — $APK | Action: $ACTION"

case "$ACTION" in
  info)
    log "Getting APK info..."
    aapt dump badging "$APK" 2>/dev/null | head -20 | while IFS= read -r l; do log "$l"; OUTPUT_LIST+=("$l"); done || {
      unzip -p "$APK" AndroidManifest.xml 2>/dev/null | strings | head -20 | while IFS= read -r l; do log "$l"; OUTPUT_LIST+=("$l"); done
    }
    ;;
  decompile)
    log "Decompiling with apktool..."
    apktool d -f "$APK" -o "$OUTPUT" 2>/dev/null && {
      ok "Decompiled to $OUTPUT"
      OUTPUT_LIST+=("Decompiled to $OUTPUT")
    } || err "Decompile failed"

    if command -v jadx &>/dev/null; then
      log "Decompiling with jadx..."
      jadx -d "${OUTPUT}_jadx" "$APK" 2>/dev/null || true
    fi
    ;;
  rebuild)
    log "Rebuilding APK..."
    if [[ -n "$PATCH" && -f "$PATCH" ]]; then
      cp "$PATCH" "$OUTPUT/patches/"
    fi
    apktool b "$APK" -o "$OUTPUT" 2>/dev/null && ok "Rebuilt: $OUTPUT" || err "Rebuild failed"
    ;;
  sign)
    log "Signing APK..."
    jarsigner -keystore "$KEYSTORE" -storepass android -keypass android "$OUTPUT" androiddebugkey 2>/dev/null && {
      ok "Signed: $OUTPUT"
      OUTPUT_LIST+=("Signed: $OUTPUT")
    } || err "Signing failed"
    zipalign -f 4 "$OUTPUT" "${OUTPUT}.aligned" 2>/dev/null && mv "${OUTPUT}.aligned" "$OUTPUT"
    ;;
  all)
    log "Full pipeline: decompile -> patch -> rebuild -> sign"
    apktool d -f "$APK" -o "/tmp/apklab_${APK_NAME}" 2>/dev/null
    [[ -n "$PATCH" && -f "$PATCH" ]] && cp "$PATCH" "/tmp/apklab_${APK_NAME}/smali/"
    apktool b "/tmp/apklab_${APK_NAME}" -o "$OUTPUT" 2>/dev/null
    jarsigner -keystore "$KEYSTORE" -storepass android -keypass android "$OUTPUT" androiddebugkey 2>/dev/null || true
    zipalign -f 4 "$OUTPUT" "${OUTPUT}.aligned" 2>/dev/null && mv "${OUTPUT}.aligned" "$OUTPUT" || true
    rm -rf "/tmp/apklab_${APK_NAME}"
    ok "Pipeline complete: $OUTPUT"
    OUTPUT_LIST+=("Pipeline complete: $OUTPUT")
    ;;
  *)
    err "Unknown action: $ACTION"
    exit 1
    ;;
esac

echo "{\"status\":\"success\",\"output\":[\"${OUTPUT_LIST[*]//\"/\\\"}\"]}"
