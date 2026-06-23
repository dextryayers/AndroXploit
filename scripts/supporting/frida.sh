#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

TARGET="${1:-}"
ACTION="${2:-list}"
SCRIPT="${3:-}"
SOURCE="${4:-local}"
MODULE="${5:-}"
FUNCTION="${6:-}"
SERIAL="${7:-}"
OUTPUT=()

command -v frida &>/dev/null || {
  err "frida not installed"
  echo '{"status":"failed","output":["frida not found"]}'
  exit 1
}

FRIDA_ARGS=()
[[ -n "$SERIAL" ]] && FRIDA_ARGS+=("-U" "-s" "$SERIAL") || FRIDA_ARGS+=("-U")

if [[ -z "$TARGET" && "$ACTION" != "list" && "$ACTION" != "ps" ]]; then
  err "Target required"
  echo '{"status":"failed","output":["Target required"]}'
  exit 1
fi

log "Frida — Target: $TARGET | Action: $ACTION"

case "$ACTION" in
  list|ps)
    log "Listing processes..."
    frida-ps "${FRIDA_ARGS[@]}" 2>/dev/null | while IFS= read -r l; do echo "  $l"; OUTPUT+=("$l"); done
    ;;
  trace)
    log "Tracing $TARGET..."
    frida-trace "${FRIDA_ARGS[@]}" -i "open" -i "read" -i "write" "$TARGET" 2>/dev/null || true
    OUTPUT+=("Trace started")
    ;;
  spawn)
    log "Spawning $TARGET..."
    frida "${FRIDA_ARGS[@]}" -f "$TARGET" --no-pause 2>/dev/null || true
    OUTPUT+=("Spawned $TARGET")
    ;;
  inject)
    [[ -z "$SCRIPT" ]] && { err "Script required for inject"; exit 1; }
    log "Injecting $SCRIPT into $TARGET..."
    frida "${FRIDA_ARGS[@]}" -f "$TARGET" -l "$SCRIPT" --no-pause 2>/dev/null || {
      frida "${FRIDA_ARGS[@]}" "$TARGET" -l "$SCRIPT" 2>/dev/null || true
    }
    OUTPUT+=("Script $SCRIPT injected")
    ;;
  hook)
    [[ -z "$MODULE" || -z "$FUNCTION" ]] && { err "MODULE and FUNCTION required"; exit 1; }
    log "Hooking $MODULE.$FUNCTION..."
    frida "${FRIDA_ARGS[@]}" -n "$TARGET" -e "Interceptor.attach(Module.findExportByName('$MODULE', '$FUNCTION'), { onEnter: function(args) { console.log('$FUNCTION called'); } });" 2>/dev/null || true
    OUTPUT+=("Hooked $MODULE.$FUNCTION")
    ;;
  *)
    err "Unknown action: $ACTION"
    exit 1
    ;;
esac

echo "{\"status\":\"success\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
