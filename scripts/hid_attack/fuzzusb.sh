#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

DEVICE="${1:-/dev/hidg0}"
ITERATIONS="${2:-100}"
STRATEGY="${3:-random}"
TIMEOUT="${4:-5}"
LOG_FILE="${5:-fuzzusb.log}"
STOP_ON_CRASH="${6:-true}"
OUTPUT=()

log "USB Fuzzer — Device: $DEVICE | Iterations: $ITERATIONS | Strategy: $STRATEGY"

if [[ ! -e "$DEVICE" ]]; then
  err "Device $DEVICE not found"
  echo '{"status":"failed","output":["Device not found"]}'
  exit 1
fi

> "$LOG_FILE"
CRASHED=false
FUZZ_COUNT=0

fuzz_bytes() {
  local len=$((RANDOM % 64 + 1))
  local data=""
  for ((i=0; i<len; i++)); do
    case "$STRATEGY" in
      random)     printf -v b '\\x%02x' $((RANDOM % 256)); data+="$b";;
      zeros)      data+='\x00';;
      ones)       data+='\xff';;
      boundary)   data+="\x00\xff\x7f\x80";;
      increment)  data+=$(printf "\\x%02x" $((i % 256)));;
      *)          printf -v b '\\x%02x' $((RANDOM % 256)); data+="$b";;
    esac
  done
  echo -ne "$data" > "$DEVICE" 2>/dev/null
}

for ((i=0; i<ITERATIONS; i++)); do
  if fuzz_bytes; then
    ((FUZZ_COUNT++))
    echo "[$(date +%H:%M:%S)] Iteration $((i+1))/$ITERATIONS — wrote ${FUZZ_COUNT} fuzz payload(s)" >> "$LOG_FILE"
  else
    warn "Write failed at iteration $((i+1))"
    echo "[$(date +%H:%M:%S)] CRASH at iteration $((i+1))" >> "$LOG_FILE"
    OUTPUT+=("Crash at iteration $((i+1))")
    CRASHED=true
    [[ "$STOP_ON_CRASH" == "true" ]] && break
  fi
  sleep "$TIMEOUT" 2>/dev/null || true
done

OUTPUT+=("Fuzzing complete: $FUZZ_COUNT writes, crashed=$CRASHED")
log "Fuzzing complete — $FUZZ_COUNT iterations logged to $LOG_FILE"

STATUS="success"
$CRASHED && STATUS="failed"
echo "{\"status\":\"$STATUS\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
