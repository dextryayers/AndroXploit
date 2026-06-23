#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()   { echo -e "${RED}[x]${NC} $1"; }

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$PROJECT_DIR/.venv"

log_info "AndroXploit — Environment Setup"
log_info "================================"
echo

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_err "$1 is not installed. Please install it first."
        return 1
    fi
    log_ok "$1 found: $(command -v "$1")"
}

log_info "Checking system dependencies..."
check_command python3
check_command pip3

if ! command -v go &>/dev/null; then
    log_warn "Go is not installed. Go modules will not be compiled."
    log_warn "Install Go from https://go.dev/dl/"
else
    log_ok "Go found: $(go version)"
fi

echo

log_info "Setting up Python virtual environment..."
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
    log_ok "Virtual environment created at $VENV_DIR"
else
    log_info "Virtual environment already exists"
fi

source "$VENV_DIR/bin/activate"

log_info "Installing Python dependencies..."
pip3 install --upgrade pip --quiet
pip3 install -r "$PROJECT_DIR/requirements.txt" --quiet

log_ok "Python dependencies installed"

echo

log_info "Building Go modules..."
GO_DIR="$PROJECT_DIR/golang"
if command -v go &>/dev/null; then
    for dir in "$GO_DIR"/*/; do
        mod_name=$(basename "$dir")
        if [ -f "$dir/main.go" ]; then
            log_info "  Building $mod_name..."
            (cd "$dir" && go build -o "$PROJECT_DIR/bin/$mod_name" .) 2>/dev/null && \
                log_ok "  $mod_name built" || \
                log_warn "  $mod_name build failed (may need go.mod)"
        fi
    done
else
    log_warn "Skipping Go builds"
fi

echo
log_info "Making scripts executable..."
chmod +x "$PROJECT_DIR/scripts/"*.sh 2>/dev/null || true
chmod +x "$PROJECT_DIR/setup.sh"

echo
log_ok "Setup complete!"
log_info "Run: source .venv/bin/activate && python3 run.py"
