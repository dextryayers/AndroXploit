#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

G='\033[38;5;82m'; R='\033[38;5;196m'; Y='\033[38;5;226m'; C='\033[38;5;51m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

log() { echo -e "${C}[*]${NC} ${B}$1${NC}"; }
ok()  { echo -e "${G}[+]${NC} ${B}$1${NC}"; }
warn() { echo -e "${Y}[!]${NC} ${B}$1${NC}"; }
err() { echo -e "${R}[x]${NC} ${B}$1${NC}"; }

ACTION="${1:-status}"
VM_NAME="${2:-AndroXploit}"
RAM="${3:-2048}"
CPU="${4:-2}"
USB="${5:-false}"
OUTPUT=()

detect_hypervisor() {
  command -v VBoxManage &>/dev/null && { echo "virtualbox"; return; }
  command -v vmrun &>/dev/null && { echo "vmware"; return; }
  echo "none"
}

HV=$(detect_hypervisor)
[[ "$HV" == "none" ]] && {
  err "No hypervisor (VirtualBox/VMware) found"
  echo '{"status":"failed","output":["No hypervisor found"]}'
  exit 1
}

log "Hypervisor: $HV | VM: $VM_NAME | Action: $ACTION"

case "$ACTION" in
  create)
    log "Creating VM $VM_NAME ($RAM MB, $CPU cores)..."
    if [[ "$HV" == "virtualbox" ]]; then
      VBoxManage createvm --name "$VM_NAME" --register 2>/dev/null
      VBoxManage modifyvm "$VM_NAME" --memory "$RAM" --cpus "$CPU" --nic1 nat 2>/dev/null
      if [[ "$USB" == "true" ]]; then
        VBoxManage modifyvm "$VM_NAME" --usb on --usbehci on 2>/dev/null || true
      fi
      ok "VM $VM_NAME created"
    elif [[ "$HV" == "vmware" ]]; then
      mkdir -p "$VM_NAME"
      warn "VMware creation requires manual .vmx setup"
    fi
    OUTPUT+=("VM $VM_NAME created")
    ;;
  start)
    log "Starting $VM_NAME..."
    if [[ "$HV" == "virtualbox" ]]; then
      VBoxManage startvm "$VM_NAME" --type headless 2>/dev/null && ok "$VM_NAME started"
    elif [[ "$HV" == "vmware" ]]; then
      vmrun start "${VM_NAME}.vmx" 2>/dev/null || true
    fi
    OUTPUT+=("VM $VM_NAME started")
    ;;
  stop)
    log "Stopping $VM_NAME..."
    if [[ "$HV" == "virtualbox" ]]; then
      VBoxManage controlvm "$VM_NAME" acpipowerbutton 2>/dev/null || VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null
    elif [[ "$HV" == "vmware" ]]; then
      vmrun stop "${VM_NAME}.vmx" 2>/dev/null || true
    fi
    OUTPUT+=("VM $VM_NAME stopped")
    ;;
  status)
    if [[ "$HV" == "virtualbox" ]]; then
      VBoxManage showvminfo "$VM_NAME" 2>/dev/null | grep -E "State:|Name:|Memory:|CPU" | while IFS= read -r l; do log "$l"; OUTPUT+=("$l"); done
    else
      log "VM $VM_NAME status check not implemented for $HV"
    fi
    ;;
  usb)
    if [[ "$HV" == "virtualbox" ]]; then
      VBoxManage list usbhost 2>/dev/null | while IFS= read -r l; do log "$l"; OUTPUT+=("$l"); done
    fi
    ;;
  *)
    err "Unknown action: $ACTION"
    exit 1
    ;;
esac

echo "{\"status\":\"success\",\"output\":[\"${OUTPUT[*]//\"/\\\"}\"]}"
