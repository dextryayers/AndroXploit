#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

TARGET="${1:-}"
ACTION="${2:-explore}"
GADGET="${3:-false}"
HOOK="${4:-}"
FILTER="${5:-}"
SERIAL="${6:-}"
OUTPUT=()

command -v objection &>/dev/null || {
  err "objection not installed"
  echo '{"status":"failed","output":["objection not found"]}'
  exit 1
}

ADB="adb"
[[ -n "$SERIAL" ]] && ADB="adb -s $SERIAL"

if [[ -z "$TARGET" ]]; then
  err "Target package required"
  echo '{"status":"failed","output":["Target required"]}'
  exit 1
fi

log "Objection — Target: $TARGET | Action: $ACTION"

OBJECTION_ARGS=("-g" "$TARGET")

case "$ACTION" in
  explore)
    log "Exploring $TARGET..."
    objection "${OBJECTION_ARGS[@]}" explore &
    sleep 2
    ;;
  dump)
    log "Dumping $TARGET..."
    objection "${OBJECTION_ARGS[@]}" --dump "$TARGET" 2>/dev/null || {
      warn "Dump failed, trying direct methods"
      objection "${OBJECTION_ARGS[@]}" run android hooking list classes 2>/dev/null || true
    }
    OUTPUT+=("Dump attempted")
    ;;
  hook)
    [[ -z "$HOOK" ]] && { err "Hook class required"; exit 1; }
    log "Hooking $HOOK..."
    objection "${OBJECTION_ARGS[@]}" run android hooking watch class "$HOOK" 2>/dev/null || true
    OUTPUT+=("Hook: $HOOK")
    ;;
  memory)
    log "Memory inspection..."
    objection "${OBJECTION_ARGS[@]}" run android memory list modules 2>/dev/null || true
    OUTPUT+=("Memory inspection done")
    ;;
  ssl)
    log "SSL pinning bypass..."
    objection "${OBJECTION_ARGS[@]}" run android sslpinning disable 2>/dev/null || true
    OUTPUT+=("SSL pinning disabled")
    ;;
  *)
    err "Unknown action: $ACTION"
    exit 1
    ;;
esac

echo "{\"status\":\"success\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
