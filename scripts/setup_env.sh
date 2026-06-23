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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$PROJECT_DIR/output"

# ─── TOOL DEFINITIONS ───────────────────────────────────────

declare -A TOOLS
TOOLS=(
    [adb]="adb:Android SDK Platform-Tools:essential"
    [java]="java:Java Runtime Environment 8+:essential"
    [python3]="python3:Python 3.8+:essential"
    [pip3]="pip3:Python Package Installer:essential"
    [go]="go:Go Programming Language 1.18+:build"
    [apktool]="apktool:Apktool (via java -jar):reverse"
    [jadx]="jadx:Jadx Decompiler:reverse"
    [frida]="frida:Frida CLI (pip install frida-tools):dynamic"
    [jarsigner]="jarsigner:JDK jarsigner:signing"
    [apksigner]="apksigner:Android SDK apksigner:signing"
    [zipalign]="zipalign:Android SDK zipalign:signing"
    [msfvenom]="msfvenom:Metasploit Framework:exploit"
    [ngrok]="ngrok:ngrok tunnel:network"
    [nmap]="nmap:Network Mapper:network"
    [qrencode]="qrencode:QR Code encoder:utils"
    [android]="android:SDK Manager:essential"
    [avdmanager]="avdmanager:AVD Manager:emulator"
    [emulator]="emulator:Android Emulator:emulator"
    [sdkmanager]="sdkmanager:SDK Manager:essential"
)

MIN_VERSIONS=(
    "python3:3.8"
    "go:1.18"
    "java:1.8"
    "node:14.0"
)

# ─── HELP ────────────────────────────────────────────────────

show_help() {
    cat <<EOF
${BOLD}Environment Setup v${VERSION}${NC} — AndroXploit Environment Manager
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 [command] [options]

${BOLD}COMMANDS:${NC}
  check           Check all dependencies and show status
  install         Install missing dependencies (where possible)
  setup           Full setup: check + install + python venv + go build
  python          Set up Python virtual environment and install reqs
  go              Build Go modules in golang/
  chmod           Make all scripts executable
  android-sdk     Check/configure ANDROID_HOME and SDK paths
  versions        Show version info for all tools
  info            Show system information
  help            Show this help

${DIM}Examples:${NC}
  $0 check        # Check all dependencies
  $0 setup        # Full environment setup
  $0 python       # Just set up Python venv
EOF
}

# ─── UTILITY FUNCTIONS ───────────────────────────────────────

check_command() {
    command -v "$1" &>/dev/null
}

version_gte() {
    local tool="$1" required="$2"
    local actual="$3"
    local req_major req_minor act_major act_minor

    IFS='.' read -ra req_parts <<< "$required"
    IFS='.' read -ra act_parts <<< "$actual"

    req_major=${req_parts[0]:-0}
    req_minor=${req_parts[1]:-0}
    act_major=${act_parts[0]:-0}
    act_minor=${act_parts[1]:-0}

    if (( act_major > req_major )); then return 0; fi
    if (( act_major == req_major && act_minor >= req_minor )); then return 0; fi
    return 1
}

get_tool_version() {
    local tool="$1"
    case "$tool" in
        python3)  python3 --version 2>&1 | grep -oP '[\d.]+' | head -1;;
        java)     java -version 2>&1 | head -1 | grep -oP '"\d+\.\d+' | tr -d '"' || echo "unknown";;
        go)       go version 2>&1 | grep -oP '[\d.]+' | head -1;;
        adb)      adb --version 2>&1 | head -1 | grep -oP '[\d.]+' | head -1 || echo "unknown";;
        pip3)     pip3 --version 2>&1 | grep -oP '[\d.]+' | head -1;;
        node)     node --version 2>&1 | tr -d 'v';;
        frida)    frida --version 2>&1 || echo "unknown";;
        *)        echo "unknown";;
    esac
}

# ─── CHECK DEPENDENCIES ─────────────────────────────────────

cmd_check() {
    log_section "DEPENDENCY CHECK — AndroXploit"
    echo "  ${BOLD}Project:${NC} $PROJECT_DIR"
    echo "  ${BOLD}Date:${NC}    $(date)"
    echo

    local categories=("essential" "reverse" "dynamic" "signing" "exploit" "network" "utils" "emulator" "build")
    local cat_names=(
        "ESSENTIAL TOOLS"
        "REVERSE ENGINEERING"
        "DYNAMIC ANALYSIS"
        "APK SIGNING"
        "EXPLOITATION"
        "NETWORK TOOLS"
        "UTILITIES"
        "EMULATOR"
        "GO BUILD"
    )

    local all_pass=0 all_fail=0

    for ci in "${!categories[@]}"; do
        local cat="${categories[$ci]}"
        local cname="${cat_names[$ci]}"
        local has_tools=0

        for tool in "${!TOOLS[@]}"; do
            IFS=':' read -r binary description category <<< "${TOOLS[$tool]}"
            if [[ "$category" != "$cat" ]]; then continue; fi
            ((has_tools++)) || true
        done

        [[ $has_tools -eq 0 ]] && continue

        log_section "$cname"
        for tool in "${!TOOLS[@]}"; do
            IFS=':' read -r binary description category <<< "${TOOLS[$tool]}"
            [[ "$category" != "$cat" ]] && continue

            if check_command "$binary"; then
                local version
                version=$(get_tool_version "$tool")
                local version_ok=""
                for mv in "${MIN_VERSIONS[@]}"; do
                    IFS=':' read -r t ver <<< "$mv"
                    if [[ "$t" == "$tool" ]]; then
                        if version_gte "$tool" "$ver" "$version"; then
                            version_ok=" (≥${ver})"
                        else
                            version_ok=" ${RED}(need ≥${ver}, have ${version})${NC}"
                        fi
                    fi
                done
                echo -e "  ${GREEN}✓${NC} ${BOLD}$tool${NC} → ${DIM}$(command -v "$binary")${NC}${version_ok:-}"
                ((all_pass++)) || true
            else
                echo -e "  ${RED}✗${NC} ${BOLD}$tool${NC} — ${DIM}$description${NC} ${YELLOW}[not found]${NC}"
                ((all_fail++)) || true
            fi
        done
    done

    echo
    log_section "SUMMARY"
    echo "  ${GREEN}Found:${NC}     $all_pass"
    echo "  ${RED}Missing:${NC}   $all_fail"
    echo "  ${BOLD}Total:${NC}     $((all_pass + all_fail))"
    echo

    if [[ $all_fail -gt 0 ]]; then
        log_warn "Some dependencies are missing. Run '$0 install' to auto-install where possible."
    else
        log_ok "All dependencies satisfied!"
    fi
}

# ─── INSTALL DEPENDENCIES ───────────────────────────────────

cmd_install() {
    log_section "AUTO-INSTALL MISSING DEPENDENCIES"

    local os=""
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        os="$ID"
    fi

    log_info "Detected OS: ${os:-unknown}"

    # Install system packages
    if [[ "$os" == "ubuntu" || "$os" == "debian" ]]; then
        log_info "Ubuntu/Debian detected. Installing system packages..."
        local pkgs=()
        check_command "adb"    || pkgs+=("android-sdk-platform-tools")
        check_command "java"   || pkgs+=("default-jre")
        check_command "pip3"   || pkgs+=("python3-pip")
        check_command "python3"|| pkgs+=("python3")
        check_command "qrencode"|| pkgs+=("qrencode")
        check_command "nmap"   || pkgs+=("nmap")

        if [[ ${#pkgs[@]} -gt 0 ]]; then
            log_info "Installing: ${pkgs[*]}"
            sudo apt-get update -qq 2>/dev/null && sudo apt-get install -y -qq "${pkgs[@]}" 2>/dev/null && log_ok "System packages installed" || log_warn "Some installs failed"
        else
            log_ok "All system packages already installed"
        fi
    elif [[ "$os" == "fedora" || "$os" == "centos" || "$os" == "rhel" ]]; then
        log_info "Red Hat family detected."
        local pkgs=()
        check_command "java"   || pkgs+=("java-11-openjdk")
        check_command "adb"    || pkgs+=("android-tools")
        check_command "nmap"   || pkgs+=("nmap")
        check_command "qrencode"|| pkgs+=("qrencode")

        if [[ ${#pkgs[@]} -gt 0 ]]; then
            sudo dnf install -y "${pkgs[@]}" 2>/dev/null && log_ok "System packages installed" || log_warn "Some installs failed"
        else
            log_ok "All system packages already installed"
        fi
    elif [[ "$(uname)" == "Darwin" ]]; then
        if check_command "brew"; then
            log_info "macOS + Homebrew detected."
            check_command "java" || { log_info "Installing Java..."; brew install --cask temurin 2>/dev/null || true; }
            check_command "adb"  || { log_info "Installing Android Platform Tools..."; brew install --cask android-platform-tools 2>/dev/null || true; }
            check_command "nmap" || brew install nmap 2>/dev/null || true
            check_command "qrencode" || brew install qrencode 2>/dev/null || true
        else
            log_warn "Homebrew not found. Install from https://brew.sh"
        fi
    else
        log_warn "Auto-install not supported for '$os'. Install dependencies manually."
    fi

    # Python packages
    log_info "Checking Python packages..."
    if check_command "pip3"; then
        if ! check_command "frida"; then
            log_progress "Installing frida-tools"
            pip3 install frida-tools --quiet 2>/dev/null && log_done "frida-tools installed" || log_fail "Failed"
        fi
        log_progress "Installing Python utility packages"
        pip3 install pycryptodome qrcode segno requests colorama --quiet 2>/dev/null && log_done "Python packages installed" || log_fail "Some failed"
    fi

    # apktool
    if ! check_command "apktool" && [[ ! -f /usr/local/bin/apktool.jar ]]; then
        log_info "Installing apktool..."
        local version="2.9.3"
        local url="https://github.com/iBotPeaches/Apktool/releases/download/v${version}/apktool_${version}.jar"
        if command -v wget &>/dev/null; then
            sudo wget -q "$url" -O /usr/local/bin/apktool.jar 2>/dev/null && log_ok "apktool downloaded" || log_warn "apktool download failed"
        elif command -v curl &>/dev/null; then
            sudo curl -sL "$url" -o /usr/local/bin/apktool.jar 2>/dev/null && log_ok "apktool downloaded" || log_warn "apktool download failed"
        fi
    fi

    # ngrok
    if ! check_command "ngrok"; then
        log_info "ngrok not found. Install from https://ngrok.com/download"
    fi

    echo
    cmd_check
}

# ─── PYTHON VENV ────────────────────────────────────────────

cmd_python() {
    log_section "PYTHON VIRTUAL ENVIRONMENT"

    if ! check_command "python3"; then
        log_err "python3 is required"
        exit 1
    fi

    if [[ ! -f "$PROJECT_DIR/.venv/bin/activate" ]]; then
        log_progress "Creating Python virtual environment"
        python3 -m venv "$PROJECT_DIR/.venv" 2>/dev/null && log_done "Virtual environment created" || {
            log_fail "Failed to create venv"
            exit 1
        }
    else
        log_ok "Virtual environment already exists"
    fi

    log_progress "Activating virtual environment"
    source "$PROJECT_DIR/.venv/bin/activate" 2>/dev/null && log_done "Activated" || {
        log_fail "Failed to activate"
        exit 1
    }

    log_progress "Upgrading pip"
    pip install --upgrade pip --quiet 2>/dev/null && log_done "pip upgraded" || log_fail "pip upgrade failed"

    if [[ -f "$PROJECT_DIR/requirements.txt" ]]; then
        log_progress "Installing requirements"
        pip install -r "$PROJECT_DIR/requirements.txt" --quiet 2>/dev/null && log_done "Requirements installed" || log_warn "Some requirements failed"
    else
        log_info "No requirements.txt found. Creating with common packages..."
        cat > "$PROJECT_DIR/requirements.txt" <<EOF
frida-tools>=12.0
requests>=2.25
colorama>=0.4
pycryptodome>=3.10
qrcode>=7.3
segno>=1.0
pyserial>=3.5
EOF
        pip install -r "$PROJECT_DIR/requirements.txt" --quiet 2>/dev/null && log_ok "Default packages installed"
    fi

    deactivate 2>/dev/null || true
    log_ok "Python environment ready at $PROJECT_DIR/.venv"
}

# ─── GO BUILD ───────────────────────────────────────────────

cmd_go() {
    log_section "GO MODULES BUILD"

    if ! check_command "go"; then
        log_warn "Go is not installed. Skipping Go build."
        return
    fi

    local go_dir="$PROJECT_DIR/golang"
    if [[ ! -d "$go_dir" ]]; then
        log_info "No golang/ directory found. Skipping."
        return
    fi

    mkdir -p "$PROJECT_DIR/bin"
    local built=0 failed=0

    while IFS= read -r -d '' dir; do
        local name; name=$(basename "$dir")
        if [[ -f "$dir/main.go" || -f "$dir/cmd/main.go" ]]; then
            local main_file="$dir/main.go"
            [[ ! -f "$main_file" ]] && main_file="$dir/cmd/main.go"
            log_progress "Building $name"
            if (cd "$dir" && go build -o "$PROJECT_DIR/bin/$name" "$main_file" 2>/dev/null); then
                local size=$(stat -c%s "$PROJECT_DIR/bin/$name" 2>/dev/null || stat -f%z "$PROJECT_DIR/bin/$name" 2>/dev/null)
                log_done "$name → bin/$name ($((size/1024))KB)"
                ((built++)) || true
            else
                log_fail "$name build failed"
                ((failed++)) || true
            fi
        fi
    done < <(find "$go_dir" -maxdepth 1 -type d -print0 2>/dev/null)

    echo
    log_info "Go build: ${GREEN}$built built${NC}, ${RED}$failed failed${NC}"
}

# ─── ANDROID SDK ────────────────────────────────────────────

cmd_android_sdk() {
    log_section "ANDROID SDK CONFIGURATION"

    local sdk_dirs=(
        "$ANDROID_HOME"
        "$ANDROID_SDK_ROOT"
        "$HOME/Android/Sdk"
        "/opt/android-sdk"
        "/usr/local/android-sdk"
        "/usr/lib/android-sdk"
    )

    local found=""
    for d in "${sdk_dirs[@]}"; do
        if [[ -n "$d" && -d "$d" ]]; then
            found="$d"
            break
        fi
    done

    if [[ -n "$found" ]]; then
        log_ok "Android SDK found: $found"
        echo "  ${BOLD}Platforms:${NC}  $(ls -d "$found"/platforms/* 2>/dev/null | wc -l) installed"
        echo "  ${BOLD}Build Tools:${NC} $(ls -d "$found"/build-tools/* 2>/dev/null | wc -l) installed"
        echo "  ${BOLD}Emulator:${NC}   $([ -f "$found/emulator/emulator" ] && echo Yes || echo No)"

        # Add to bashrc if not present
        if ! grep -q "ANDROID_HOME=$found" "$HOME/.bashrc" 2>/dev/null; then
            log_info "Adding Android SDK paths to ~/.bashrc..."
            {
                echo ""
                echo "# AndroXploit — Android SDK"
                echo "export ANDROID_HOME=\"$found\""
                echo "export ANDROID_SDK_ROOT=\"$found\""
                echo "export PATH=\"\$PATH:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/emulator:\$ANDROID_HOME/tools:\$ANDROID_HOME/tools/bin:\$ANDROID_HOME/build-tools/$(ls "$found"/build-tools/ 2>/dev/null | tail -1)/\""
            } >> "$HOME/.bashrc"
            log_ok "SDK paths added to ~/.bashrc. Run 'source ~/.bashrc' to apply."
        fi
    else
        log_warn "Android SDK not found in standard locations."
        log_info "Install Android Studio or set ANDROID_HOME environment variable."
        log_info "  export ANDROID_HOME=\$HOME/Android/Sdk"
        echo
        read -p "Enter Android SDK path (or leave blank to skip): " sdk_path
        if [[ -n "$sdk_path" ]]; then
            if [[ -d "$sdk_path" ]]; then
                log_ok "SDK found at $sdk_path"
                export ANDROID_HOME="$sdk_path"
            else
                log_err "Directory not found: $sdk_path"
            fi
        fi
    fi

    # Check sdkmanager
    local sdkmanager_path=""
    for sp in "${found}/tools/bin/sdkmanager" "${found}/cmdline-tools/latest/bin/sdkmanager" "${found}/cmdline-tools/*/bin/sdkmanager"; do
        for f in $sp; do
            if [[ -f "$f" ]]; then
                sdkmanager_path="$f"
                break 2
            fi
        done
    done

    if [[ -n "$sdkmanager_path" ]]; then
        echo "  ${BOLD}sdkmanager:${NC} $sdkmanager_path"
    else
        log_warn "sdkmanager not found. Install Android SDK command-line tools."
    fi
}

# ─── SCRIPTS PERMISSIONS ────────────────────────────────────

cmd_chmod() {
    log_section "SCRIPT PERMISSIONS"
    local count=0
    while IFS= read -r -d '' f; do
        chmod +x "$f" 2>/dev/null && ((count++)) || true
    done < <(find "$SCRIPT_DIR" -name '*.sh' -type f -print0 2>/dev/null)
    log_ok "Made $count scripts executable"
}

# ─── VERSIONS ───────────────────────────────────────────────

cmd_versions() {
    log_section "TOOL VERSIONS"
    for tool in "${!TOOLS[@]}"; do
        IFS=':' read -r binary description category <<< "${TOOLS[$tool]}"
        if check_command "$binary"; then
            local version
            version=$(get_tool_version "$tool")
            echo "  ${BOLD}$tool${NC}: ${DIM}$version${NC}"
        fi
    done
}

# ─── INFO ────────────────────────────────────────────────────

cmd_info() {
    log_section "SYSTEM INFORMATION"
    echo "  ${BOLD}OS:${NC}        $(uname -s) $(uname -r)"
    echo "  ${BOLD}Arch:${NC}      $(uname -m)"
    echo "  ${BOLD}Shell:${NC}     $SHELL"
    echo "  ${BOLD}Home:${NC}      $HOME"
    echo "  ${BOLD}Project:${NC}   $PROJECT_DIR"
    echo "  ${BOLD}Scripts:${NC}   $(find "$SCRIPT_DIR" -name '*.sh' -type f | wc -l) scripts"
    echo "  ${BOLD}Output:${NC}    $OUT_DIR"
    echo "  ${BOLD}Disk:${NC}      $(df -h "$PROJECT_DIR" | tail -1 | awk '{print $4}') free"
    echo "  ${BOLD}Memory:${NC}    $(free -h 2>/dev/null | grep Mem | awk '{print $2}') total"
    echo "  ${BOLD}CPUs:${NC}      $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 'N/A')"
}

# ─── MAIN ────────────────────────────────────────────────────

main() {
    mkdir -p "$OUT_DIR"/{logs,reports,apks,payloads}

    if [[ $# -lt 1 ]]; then
        cmd_check
        cmd_python
        cmd_go
        cmd_chmod
        cmd_android_sdk
        echo
        log_ok "Environment setup complete!"
        exit 0
    fi

    case "${1:-help}" in
        check|verify)           cmd_check;;
        install|auto-install)   cmd_install;;
        setup|full)             shift; cmd_check; cmd_python; cmd_go; cmd_chmod; cmd_android_sdk; echo; log_ok "Full setup complete!";;
        python|venv|pip)        cmd_python;;
        go|golang|build)        cmd_go;;
        chmod|permissions|chmodx) cmd_chmod;;
        android-sdk|sdk)        cmd_android_sdk;;
        versions|ver)           cmd_versions;;
        info|system)            cmd_info;;
        help|-h|--help)         show_help;;
        *)                      log_err "Unknown: $1"; show_help; exit 1;;
    esac
}

main "$@"
