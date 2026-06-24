#!/bin/bash
# ===================================================================
# 20 C Engines - Full ADB Deployment Script
# "Jalur pembuka dengan bash adb full"
# ===================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINES_DIR="$SCRIPT_DIR/../c_engines/engines"
BUILD_DIR="$ENGINES_DIR/build"
RESULTS_DIR="$SCRIPT_DIR/../ce_results"
REMOTE_DIR="/data/local/tmp"
REMOTE_OUT="$REMOTE_DIR/ce_results"
SERIAL="${SERIAL:-}"
PARALLEL="${PARALLEL:-4}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${CYAN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[!]${NC} $1" >&2; }

ADB() {
    if [ -n "$SERIAL" ]; then
        adb -s "$SERIAL" "$@"
    else
        adb "$@"
    fi
}

# ── Banner ──
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       20 C Engines - ADB Deploy v2.0        ║${NC}"
echo -e "${CYAN}║   Total Android Extraction Pipeline         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── Phase 1: Check dependencies ──
log "Phase 1: Checking dependencies..."
for cmd in adb make; do
    if ! command -v "$cmd" &>/dev/null; then
        err "$cmd not found in PATH"
        exit 1
    fi
done

if [ -z "$SERIAL" ]; then
    DEVICES=$(adb devices | grep -E "device$" | awk '{print $1}' || true)
    if [ -z "$DEVICES" ]; then
        err "No device connected"
        exit 1
    fi
    COUNT=$(echo "$DEVICES" | wc -l)
    if [ "$COUNT" -gt 1 ]; then
        err "Multiple devices found! Set SERIAL=serial_number"
        echo "$DEVICES"
        exit 1
    fi
    SERIAL="$DEVICES"
fi

DEVICE_NAME=$(ADB shell getprop ro.product.model 2>/dev/null | tr -d '\r' || echo "unknown")
ANDROID_VER=$(ADB shell getprop ro.build.version.release 2>/dev/null | tr -d '\r' || echo "unknown")
log "Device: $DEVICE_NAME (Android $ANDROID_VER, serial: $SERIAL)"
echo ""

# ── Phase 2: Build engines ──
log "Phase 2: Building 20 C engines..."
cd "$ENGINES_DIR"
if [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
fi

if make all 2>/dev/null; then
    log "NDK build successful"
else
    warn "NDK build failed, trying host build (will not run on device)"
    make all_host 2>/dev/null || { err "Build failed"; exit 1; }
fi
cd "$SCRIPT_DIR"
echo ""

# ── Phase 3: Prepare device ──
log "Phase 3: Preparing device..."
ADB shell "mkdir -p $REMOTE_OUT" 2>/dev/null || true
ADB shell "rm -f $REMOTE_OUT/*" 2>/dev/null || true

# Check if device has root
ROOT_AVAILABLE=0
if ADB shell "su -c 'id' 2>/dev/null" | grep -q "uid=0"; then
    ROOT_AVAILABLE=1
    log "Root access available! Full extraction mode"
else
    warn "No root access — limited to shell-accessible data"
fi
echo ""

# ── Phase 4: Push engines ──
log "Phase 4: Pushing engines to device..."
ENGINE_LIST=(
    engine_01_imei engine_02_contacts engine_03_sms engine_04_calllog
    engine_05_wifi engine_06_accounts engine_07_whatsapp engine_08_telegram
    engine_09_browser engine_10_system engine_11_process engine_12_network
    engine_13_sqlite engine_14_media engine_15_files engine_16_backup
    engine_17_hidden engine_18_device engine_19_keystore engine_20_master
)

for ENGINE in "${ENGINE_LIST[@]}"; do
    SRC="$BUILD_DIR/$ENGINE"
    if [ ! -f "$SRC" ]; then
        SRC="$ENGINES_DIR/build_host/$ENGINE"
    fi
    if [ -f "$SRC" ]; then
        ADB push "$SRC" "$REMOTE_DIR/$ENGINE" 2>/dev/null || warn "push $ENGINE failed"
    else
        warn "Binary not found: $ENGINE"
    fi
done
ADB shell "for e in ${ENGINE_LIST[*]}; do chmod 755 $REMOTE_DIR/\$e 2>/dev/null || true; done"
TOTAL=$(ADB shell "for e in ${ENGINE_LIST[*]}; do ls $REMOTE_DIR/\$e 2>/dev/null && echo OK; done" | grep -c "OK" || true)
log "Pushed $TOTAL/20 engines"
echo ""

# ── Phase 5: Run engines ──
log "Phase 5: Running engines (parallel=$PARALLEL)..."
echo ""

declare -A ENGINE_FILES ENGINE_TIME ENGINE_STATUS
ENGINES_OK=0
START_TOTAL=$(date +%s%N)

run_one() {
    local ENGINE="$1"
    local START
    START=$(date +%s%N)
    local OUT
    OUT=$(ADB shell "$REMOTE_DIR/$ENGINE $REMOTE_OUT" 2>/dev/null || echo '{"status":"fail"}')
    local END
    END=$(date +%s%N)
    local ELAPSED
    ELAPSED=$(( (END - START) / 1000000 ))

    local STATUS="fail"
    local FILES=0

    # Parse JSON result
    STATUS=$(echo "$OUT" | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "fail")
    FILES=$(echo "$OUT" | grep -o '"files":[0-9]*' | cut -d: -f2 || echo "0")
    [ -z "$FILES" ] && FILES=0

    # Check actual files on device
    local ACTUAL
    ACTUAL=$(ADB shell "ls $REMOTE_OUT/$ENGINE* 2>/dev/null | wc -l" || echo "0")
    [ "$ACTUAL" -gt "$FILES" ] && FILES="$ACTUAL"

    if [ "$STATUS" = "ok" ] || [ "$FILES" -gt 0 ]; then
        STATUS="ok"
    fi

    echo "$ENGINE|$STATUS|$FILES|${ELAPSED}ms"
}

# Run in parallel with semaphore
for ENGINE in "${ENGINE_LIST[@]}"; do
    while [ "$(jobs -r | wc -l)" -ge "$PARALLEL" ]; do
        sleep 0.1
    done
    (
        RESULT=$(run_one "$ENGINE")
        IFS='|' read -r E S F T <<< "$RESULT"
        echo -e "  $([ "$S" = "ok" ] && echo -n "${GREEN}✓${NC}" || echo -n "${RED}✗${NC}") ${E#engine_}\t files=$F\t ${T}"

        if [ "$S" = "ok" ]; then
            ((ENGINES_OK++))
        fi
    ) &
done
wait

END_TOTAL=$(date +%s%N)
TOTAL_MS=$(( (END_TOTAL - START_TOTAL) / 1000000 ))
echo ""

# ── Phase 6: Pull results ──
log "Phase 6: Pulling results..."
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
ADB pull "$REMOTE_OUT" "$RESULTS_DIR" 2>/dev/null || warn "Pull returned non-zero (may be partial)"

# Also try pulling individual engine JSON results
for ENGINE in "${ENGINE_LIST[@]}"; do
    ADB pull "$REMOTE_DIR/.engine_*.json" "$RESULTS_DIR/" 2>/dev/null || true
done

TOTAL_FILES=$(find "$RESULTS_DIR" -type f 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$RESULTS_DIR" 2>/dev/null | cut -f1 || echo "0")

# ── Phase 7: Cleanup ──
log "Phase 7: Cleaning up..."
ADB shell "rm -rf $REMOTE_OUT $REMOTE_DIR/engine_* $REMOTE_DIR/.engine_*.json" 2>/dev/null || true

# ── Final Report ──
echo ""
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "  20 C Engines - Extraction Complete"
echo -e "  Device:       $DEVICE_NAME (Android $ANDROID_VER)"
echo -e "  Engines OK:   $ENGINES_OK/20"
echo -e "  Total Files:  $TOTAL_FILES"
echo -e "  Total Size:   $TOTAL_SIZE"
echo -e "  Duration:     ${TOTAL_MS}ms ($((TOTAL_MS/1000))s)"
echo -e "  Results:      $RESULTS_DIR"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo ""

# ── Generate index ──
if [ "$TOTAL_FILES" -gt 0 ]; then
    INDEX="$RESULTS_DIR/00_FILE_INDEX.txt"
    echo "╔══════════════════════════════════════╗" > "$INDEX"
    echo "║  20 C Engines - File Index          ║" >> "$INDEX"
    echo "╚══════════════════════════════════════╝" >> "$INDEX"
    find "$RESULTS_DIR" -type f -exec ls -lh {} \; 2>/dev/null | sort >> "$INDEX"
    log "File index: $INDEX"
fi

echo -e "${GREEN}✓ Done!${NC}"
