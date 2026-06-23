#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

ACTION="${1:-status}"
OUTPUT=()

check_docker() { command -v docker &>/dev/null; }
check_python() { command -v python3 &>/dev/null; }

log "MobSF Manager — Action: $ACTION"

case "$ACTION" in
  install)
    if check_docker; then
      log "Pulling MobSF Docker image..."
      docker pull opensecurity/mobile-security-framework-mobsf:latest 2>/dev/null && {
        ok "MobSF Docker image pulled"
        OUTPUT+=("Docker image pulled")
      } || err "Docker pull failed"
    elif check_python; then
      log "Installing via pip..."
      pip3 install mobsf 2>/dev/null && {
        ok "MobSF installed via pip"
        OUTPUT+=("pip install complete")
      } || err "pip install failed"
    else
      err "Neither Docker nor Python3 found"
      exit 1
    fi
    ;;
  start)
    if check_docker; then
      log "Starting MobSF container..."
      docker run -d --name mobsf -p 8000:8000 opensecurity/mobile-security-framework-mobsf:latest 2>/dev/null && {
        ok "MobSF running on http://localhost:8000"
        OUTPUT+=("MobSF started on port 8000")
      } || {
        docker start mobsf 2>/dev/null && ok "MobSF container resumed" || err "Failed to start"
      }
    elif check_python; then
      log "Starting MobSF server..."
      python3 -m mobsf.MobSF 2>/dev/null &
      ok "MobSF started in background"
      OUTPUT+=("MobSF started")
    fi
    ;;
  stop)
    if check_docker; then
      docker stop mobsf 2>/dev/null && ok "MobSF stopped" || warn "Not running"
    else
      pkill -f mobsf 2>/dev/null && ok "MobSF stopped" || warn "Not running"
    fi
    OUTPUT+=("MobSF stopped")
    ;;
  status)
    if check_docker; then
      docker ps --filter name=mobsf --format "{{.Status}}" 2>/dev/null | grep -q . && {
        log "MobSF: running"
        OUTPUT+=("MobSF: running")
      } || {
        log "MobSF: not running"
        OUTPUT+=("MobSF: not running")
      }
    else
      pgrep -f mobsf &>/dev/null && log "MobSF: running" || log "MobSF: not running"
    fi
    ;;
  *)
    err "Unknown action: $ACTION (install|start|stop|status)"
    exit 1
    ;;
esac

echo "{\"status\":\"success\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
