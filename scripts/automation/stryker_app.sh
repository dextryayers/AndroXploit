#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

CONN="${1:-usb}"
INTERFACE="${2:-wlan0}"
SCAN_TYPE="${3:-quick}"
ROOT="${4:-false}"
TIMEOUT="${5:-60}"
OUTPUT=()

check_dep() { command -v "$1" &>/dev/null || warn "$1 not installed"; }

scan_arp() {
  check_dep arp-scan
  log "ARP scanning $INTERFACE..."
  local RANGE=$(ip -4 addr show "$INTERFACE" 2>/dev/null | grep inet | awk '{print $2}' || echo "192.168.1.0/24")
  OUT=$(arp-scan --localnet --interface "$INTERFACE" 2>/dev/null) && {
    ok "ARP scan complete"
    while IFS= read -r line; do OUTPUT+=("$line"); done <<< "$OUT"
  } || warn "ARP scan failed"
}

scan_nmap() {
  check_dep nmap
  log "NMAP $SCAN_TYPE scan..."
  local OPTS=""
  case "$SCAN_TYPE" in
    quick) OPTS="-sn -T4";;
    full)  OPTS="-sS -sV -p- -T4";;
    vuln)  OPTS="-sV --script vuln -T4";;
    *)     OPTS="-sn -T4";;
  esac
  OUT=$(nmap $OPTS "$INTERFACE" 2>/dev/null) && {
    ok "NMAP scan complete"
    while IFS= read -r line; do OUTPUT+=("$line"); done <<< "$OUT"
  } || warn "NMAP scan failed"
}

scan_bluetooth() {
  check_dep bluetoothctl
  log "Bluetooth scanning..."
  OUT=$(echo -e "power on\nscan on\nsleep 5\nscan off\nquit" | bluetoothctl 2>/dev/null) && {
    ok "Bluetooth scan complete"
    while IFS= read -r line; do OUTPUT+=("$line"); done <<< "$OUT"
  } || warn "Bluetooth scan failed"
}

case "$SCAN_TYPE" in
  quick) scan_arp;;
  full)  scan_arp; scan_nmap;;
  vuln)  scan_nmap;;
  bt|bluetooth) scan_bluetooth;;
  all)   scan_arp; scan_nmap; scan_bluetooth;;
  *)     scan_arp;;
esac

ok "Stryker scan completed"
echo "{\"status\":\"success\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
