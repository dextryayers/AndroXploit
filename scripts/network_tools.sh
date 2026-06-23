#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

VERSION="3.0.0"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} ${BOLD}$1${NC}"; }
log_ok()    { echo -e "${GREEN}[+]${NC} ${BOLD}$1${NC}"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} ${BOLD}$1${NC}"; }
log_err()   { echo -e "${RED}[x]${NC} ${BOLD}$1${NC}"; }
log_section() { echo -e "\n${BLUE}════════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}════════════════════════════════════════════${NC}"; }
log_progress() { echo -ne "${DIM}  → $1...${NC}"; }
log_done()    { echo -e "\r  ${GREEN}✓${NC} ${DIM}$1${NC}"; }
log_fail()    { echo -e "\r  ${RED}✗${NC} ${DIM}$1${NC}"; }

OUT_DIR="output"
mkdir -p "$OUT_DIR"

show_help() {
    cat <<EOF
${BOLD}Network Tools v${VERSION}${NC} — Professional Android Network Toolkit
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 <command> [args]

${BOLD}SCANNING:${NC}
  scan [subnet]            Network host discovery (uses nmap or ping sweep)
  ports <host> [ports]     Port scan with service detection
  port-range <host> <start> <end>  Scan a range of ports

${BOLD}ADB TUNNELING:${NC}
  forward [lport] [rport]  Forward localhost:port → device:port
  reverse [rport] [lport]  Reverse tunnel device:port → localhost:port
  list-forwards            List all ADB forward/reverse tunnels
  remove-forward <lport>   Remove specific port forward

${BOLD}PROXY:${NC}
  proxy <host> <port>      Set HTTP proxy on device
  proxy-off                Clear HTTP proxy on device
  proxy-status             Show current proxy settings

${BOLD}TRAFFIC CAPTURE:${NC}
  tcpdump [seconds]        Capture traffic via tcpdump on device
  pcap-info <file>         Show pcap file info (needs captcp or tshark)

${BOLD}WIFI:${NC}
  wifi-scan                Scan WiFi networks
  wifi-info                Show current WiFi connection details
  wifi-list                List saved WiFi networks (needs root)

${BOLD}DNS & NETWORK:${NC}
  dns <domain>             DNS resolution (device + local)
  ping <host> [count]      Ping from device
  traceroute <host>        Traceroute from device
  bandwidth [url]          Bandwidth test (download time)

${BOLD}PROXY TOOLS:${NC}
  mitm [port]              Start mitmproxy
  burp [port]              Configure for Burp Suite proxy

${DIM}Examples:${NC}
  $0 scan 192.168.1.0/24         # Scan local network
  $0 ports 192.168.1.1           # Scan common ports
  $0 tcpdump 60                  # Capture 60s of traffic
  $0 mitm                        # Start mitmproxy
EOF
}

check_adb() { adb get-state &>/dev/null || { log_err "No device connected."; exit 1; }; }
get_device_ip() { adb shell ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | tr -d '\r'; }
get_gateway() { adb shell ip route 2>/dev/null | grep default | awk '{print $3}' | tr -d '\r'; }
get_subnet() { local ip; ip=$(get_device_ip); echo "${ip%.*}.0/24"; }

# ─── SCANNING ───────────────────────────────────────────────

cmd_scan() {
    check_adb
    local subnet="${1:-$(get_subnet)}"
    log_section "NETWORK DISCOVERY: $subnet"

    if command -v nmap &>/dev/null; then
        log_info "Using nmap..."
        sudo nmap -sn "$subnet" -oG - 2>/dev/null | grep "Up$" | while IFS= read -r line; do
            local ip; ip=$(echo "$line" | awk '{print $2}')
            local host; host=$(echo "$line" | grep -oP '\([^)]+\)' | tr -d '()')
            echo -e "  ${GREEN}✓${NC} $ip${host:+ ($host)}"
        done
    else
        log_info "Using ping sweep (this may take a while)..."
        local base; base=$(echo "$subnet" | cut -d. -f1-3)
        local found=0
        for i in $(seq 1 254); do
            (ping -c1 -W1 "${base}.$i" &>/dev/null && echo -e "  ${GREEN}✓${NC} ${base}.$i") &
        done
        wait
    fi
}

cmd_ports() {
    check_adb
    local target="${1:-$(get_gateway)}"
    local ports="${2:-22,80,443,5555,8080,8443,3306,3389,5900,8443,9443}"
    [[ -z "$target" ]] && { log_err "No target specified and no gateway found"; exit 1; }

    log_section "PORT SCAN: $target"
    log_info "Scanning ports: $ports"
    echo

    IFS=',' read -ra PORT_LIST <<< "$ports"
    local open=0
    for port in "${PORT_LIST[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        local service=""; local proto="tcp"
        case $port in
            21) service="FTP";; 22) service="SSH";; 23) service="Telnet";; 25) service="SMTP";;
            53) service="DNS"; proto="udp";; 80) service="HTTP";; 110) service="POP3";;
            111) service="RPC";; 135) service="RPC";; 139) service="NetBIOS";; 143) service="IMAP";;
            443) service="HTTPS";; 445) service="SMB";; 993) service="IMAPS";; 995) service="POP3S";;
            1433) service="MSSQL";; 1521) service="Oracle";; 2049) service="NFS";;
            3306) service="MySQL";; 3389) service="RDP";; 5432) service="PostgreSQL";;
            5555) service="ADB";; 5900) service="VNC";; 5901) service="VNC-1";; 6379) service="Redis";;
            8080) service="HTTP-Proxy";; 8443) service="HTTPS-Alt";; 8444) service="HTTPS-Alt2";;
            9090) service="HTTP-Alt";; 27017) service="MongoDB";;
        esac
        log_progress "Checking port $port ($proto)"
        if timeout 1 bash -c "echo >/dev/$proto/$target/$port" 2>/dev/null; then
            log_done "Port $port open${service:+ ($service)}"
            ((open++)) || true
        else
            echo -ne "\r\033[K"
        fi
    done
    echo
    log_info "Scan complete: $open open port(s) found"
}

cmd_port_range() {
    local host="${1:?Usage: $0 port-range <host> <start> <end>}"
    local start="${2:-1}"; local end="${3:-1024}"
    log_section "PORT RANGE SCAN: $host ($start-$end)"
    local open=0
    for ((p=start; p<=end; p++)); do
        log_progress "Scanning $p/$end"
        if timeout 0.5 bash -c "echo >/dev/tcp/$host/$p" 2>/dev/null; then
            log_done "Port $p open"
            ((open++)) || true
        fi
    done
    echo
    log_info "Scan complete: $open open of $((end-start+1)) ports"
}

# ─── ADB TUNNELING ─────────────────────────────────────────

cmd_forward() {
    check_adb
    local lport="${1:-8888}"; local rport="${2:-8888}"
    log_info "Forward: tcp:localhost:$lport → tcp:device:$rport"
    adb forward "tcp:$lport" "tcp:$rport" && log_ok "Forward established" || log_err "Failed"
}

cmd_reverse() {
    check_adb
    local rport="${1:-8888}"; local lport="${2:-8888}"
    log_info "Reverse: tcp:device:$rport → tcp:localhost:$lport"
    adb reverse "tcp:$rport" "tcp:$lport" && log_ok "Reverse established" || log_err "Failed"
}

cmd_list_forwards() {
    check_adb
    log_section "ADB FORWARD/REVERSE"
    echo "  ${BOLD}Forwards:${NC}"
    adb forward --list 2>/dev/null | sed 's/^/    /' || echo "    (none)"
    echo "  ${BOLD}Reverses:${NC}"
    adb reverse --list 2>/dev/null | sed 's/^/    /' || echo "    (none)"
}

cmd_remove_forward() {
    local lport="${1:?Usage: $0 remove-forward <lport>}"
    check_adb
    adb forward --remove "tcp:$lport" && log_ok "Removed forward tcp:$lport" || log_err "Failed"
}

# ─── PROXY ──────────────────────────────────────────────────

cmd_proxy() {
    check_adb
    [[ $# -lt 2 ]] && { log_err "Usage: $0 proxy <host> <port>"; exit 1; }
    log_info "Setting proxy: $1:$2"
    adb shell settings put global http_proxy "$1:$2" && log_ok "Proxy set" || log_err "Failed"
}

cmd_proxy_off() {
    check_adb
    adb shell settings put global http_proxy :0 && log_ok "Proxy cleared" || log_err "Failed"
}

cmd_proxy_status() {
    check_adb
    log_section "PROXY STATUS"
    local proxy; proxy=$(adb shell settings get global http_proxy 2>/dev/null | tr -d '\r')
    if [[ -n "$proxy" && "$proxy" != ":0" ]]; then
        echo "  ${BOLD}Proxy:${NC} $proxy"
    else
        echo "  ${BOLD}Proxy:${NC} ${YELLOW}Not set${NC}"
    fi
}

# ─── TRAFFIC CAPTURE ────────────────────────────────────────

cmd_tcpdump() {
    check_adb
    local duration="${1:-30}"; local out="$OUT_DIR/capture_$(date +%Y%m%d_%H%M%S).pcap"
    mkdir -p "$OUT_DIR"

    log_section "TRAFFIC CAPTURE"
    echo "  ${BOLD}Duration:${NC} ${duration}s"
    echo "  ${BOLD}Output:${NC}   $out"
    echo

    if ! adb shell su -c 'which tcpdump' 2>/dev/null | grep -q tcpdump; then
        if ! adb shell 'which tcpdump' 2>/dev/null | grep -q tcpdump; then
            log_err "tcpdump not found on device (root required)"
            exit 1
        fi
    fi

    log_progress "Capturing (${duration}s)"
    adb shell su -c "tcpdump -i any -w /sdcard/capture.pcap -s 0 2>/dev/null" &
    local pid=$!

    for ((i=1; i<=duration; i++)); do echo -ne "\r  ${DIM}Capturing: ${i}/${duration}s${NC}  "; sleep 1; done
    echo

    kill $pid 2>/dev/null || true; sleep 1
    adb pull /sdcard/capture.pcap "$out" 2>/dev/null
    adb shell rm /sdcard/capture.pcap 2>/dev/null

    if [[ -f "$out" ]]; then
        local size; size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")
        log_done "Capture: $out ($((size/1024))KB)"
    else log_fail "Capture failed"; fi
}

cmd_pcap_info() {
    local file="${1:?Usage: $0 pcap-info <file>}"
    [[ ! -f "$file" ]] && { log_err "File not found"; exit 1; }
    log_section "PCAP INFO: $(basename "$file")"
    local size; size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")
    echo "  ${BOLD}Size:${NC}    $((size/1024/1024))MB ($size bytes)"
    echo "  ${BOLD}Packets:${NC} $(capinfos "$file" 2>/dev/null | grep "Number of packets" | awk '{print $NF}')"
    tshark -r "$file" -q -z io,stat,1 2>/dev/null | head -10 || capinfos "$file" 2>/dev/null | head -10 || echo "  Install tshark for details"
}

# ─── WIFI ───────────────────────────────────────────────────

cmd_wifi_scan() {
    check_adb
    log_section "WIFI SCAN"
    adb shell cmd wifi start-scan 2>/dev/null || true
    sleep 3
    adb shell dumpsys wifi 2>/dev/null | grep -E "SSID:|BSSID:|signal |frequency:|capabilities:" | head -60 | while IFS= read -r line; do
        echo "  $line" | tr -d '\t\r' | sed 's/  */ /g'
    done
}

cmd_wifi_info() {
    check_adb
    log_section "WIFI INFO"
    adb shell dumpsys wifi 2>/dev/null | grep -E "mNetworkInfo|mWifiInfo|SSID|BSSID|LinkSpeed|Rssi|ipAddress|mDhcpInfo" | head -15 | sed 's/  */ /g; s/^/  /'
    echo
    echo "  ${BOLD}Device IP:${NC}  $(get_device_ip)"
    echo "  ${BOLD}Gateway:${NC}    $(get_gateway)"
}

cmd_wifi_list() {
    check_adb
    log_section "SAVED WIFI NETWORKS (root)"
    adb shell su -c 'cat /data/misc/wifi/WifiConfigStore.xml 2>/dev/null || cat /data/misc/wifi/wpa_supplicant.conf 2>/dev/null' | grep -E 'SSID|psk|PreSharedKey' | sed 's/^/  /' || log_warn "Cannot access (root required)"
}

# ─── DNS & NETWORK ──────────────────────────────────────────

cmd_dns() {
    local domain="${1:-example.com}"
    check_adb
    log_section "DNS RESOLUTION: $domain"
    echo "  ${BOLD}Device:${NC}"
    adb shell nslookup "$domain" 2>/dev/null | head -10 | sed 's/^/    /'
    echo "  ${BOLD}Local:${NC}"
    nslookup "$domain" 2>/dev/null | grep -i address | tail -3 | sed 's/^/    /'
}

cmd_ping() {
    local host="${1:?Usage: $0 ping <host> [count]}"
    local count="${2:-5}"
    check_adb
    log_section "PING: $host (${count} packets)"
    adb shell ping -c "$count" "$host" 2>/dev/null | sed 's/^/  /'
}

cmd_traceroute() {
    local host="${1:?Usage: $0 traceroute <host>}"
    check_adb
    log_section "TRACEROUTE: $host"
    adb shell traceroute "$host" 2>/dev/null | sed 's/^/  /' || adb shell busybox traceroute "$host" 2>/dev/null | sed 's/^/  /' || log_err "traceroute not available"
}

cmd_bandwidth() {
    local url="${1:-http://speedtest.tele2.net/1MB.zip}"
    check_adb
    log_section "BANDWIDTH TEST"
    log_info "Downloading: $url"
    local start; start=$(date +%s%N)
    adb shell "wget -q -O /dev/null '$url'" 2>/dev/null || adb shell "curl -so /dev/null '$url'" 2>/dev/null || { log_err "Download failed"; exit 1; }
    local end; end=$(date +%s%N)
    local elapsed=$(( (end - start) / 1000000 ))
    echo "  ${BOLD}Time:${NC} ${elapsed}ms"
}

# ─── PROXY TOOLS ────────────────────────────────────────────

cmd_mitm() {
    local port="${1:-8080}"
    log_section "MITMPROXY"
    if command -v mitmproxy &>/dev/null; then
        log_info "Starting mitmproxy on port $port..."
        log_info "Set device proxy: adb shell settings put global http_proxy 127.0.0.1:$port"
        mitmproxy --listen-port "$port"
    elif command -v mitmdump &>/dev/null; then
        log_info "Starting mitmdump on port $port..."
        mitmdump --listen-port "$port"
    else
        log_err "mitmproxy not installed. Install: pip install mitmproxy"
        exit 1
    fi
}

cmd_burp() {
    local port="${1:-8080}"
    local host="${2:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
    log_section "BURP SUITE CONFIG"
    log_info "Configure Burp to listen on $host:$port"
    log_info "Then run: adb shell settings put global http_proxy $host:$port"
    echo
    log_info "To clear: adb shell settings put global http_proxy :0"
    echo
    read -p "Set proxy now? (y/N): " yn
    [[ "$yn" == "y" ]] && check_adb && adb shell settings put global http_proxy "$host:$port" && log_ok "Proxy set"
}

# ─── MAIN ────────────────────────────────────────────────────

main() {
    [[ $# -lt 1 ]] && { show_help; exit 0; }
    local cmd="$1"; shift

    case "$cmd" in
        scan|discover)           cmd_scan "$@";;
        ports|portscan)          cmd_ports "$@";;
        port-range|range)        cmd_port_range "$@";;
        fwd|forward)             cmd_forward "$@";;
        rev|reverse)             cmd_reverse "$@";;
        list-forwards|listfwds)  cmd_list_forwards;;
        remove-forward|rmfwd)    cmd_remove_forward "$@";;
        proxy)                   cmd_proxy "$@";;
        proxy-off|noproxy)       cmd_proxy_off;;
        proxy-status|proxyinfo)  cmd_proxy_status;;
        tcpdump|pcap|capture)    cmd_tcpdump "$@";;
        pcap-info|capinfo)       cmd_pcap_info "$@";;
        wifi-scan|wifi_scan)     cmd_wifi_scan;;
        wifi-info|wifiinfo)      cmd_wifi_info;;
        wifi-list|saved-wifi)    cmd_wifi_list;;
        dns|nslookup)            cmd_dns "$@";;
        ping)                    cmd_ping "$@";;
        traceroute|trace)        cmd_traceroute "$@";;
        bandwidth|speedtest)     cmd_bandwidth "$@";;
        mitm|mitmproxy)          cmd_mitm "$@";;
        burp|burpsuite)          cmd_burp "$@";;
        help|-h|--help)          show_help;;
        *) log_err "Unknown: $cmd"; show_help; exit 1;;
    esac
}

main "$@"
