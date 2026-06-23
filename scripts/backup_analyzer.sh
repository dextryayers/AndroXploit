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

TMP_DIR="/tmp/androxploit_backup_$$"
OUT_DIR="output/backups"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
mkdir -p "$OUT_DIR"

show_help() {
    cat <<EOF
${BOLD}Backup Analyzer v${VERSION}${NC} — Forensic Android Backup Analysis Toolkit
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 <command> [args]

${BOLD}BACKUP CREATION:${NC}
  backup-app <package>          Create ADB backup of specific app
  backup-app-full <package>     Full backup including APK
  backup-full                   Full device backup (all apps + shared)
  backup-system                 Backup system packages

${BOLD}RESTORE:${NC}
  restore-app <backup.ab>       Restore app from backup file

${BOLD}EXTRACTION & ANALYSIS:${NC}
  extract <backup.ab>           Extract backup to directory
  extract-encrypted <backup.ab> <password>  Extract encrypted backup
  analyze <backup.ab>           Show backup metadata & contents
  list                          List all saved backups

${BOLD}FORENSIC ANALYSIS:${NC}
  find-secrets <backup.ab>      Search for secrets, tokens, passwords
  find-databases <backup.ab>    Extract all SQLite databases
  find-preferences <backup.ab>  Extract shared preferences XMLs
  summary <backup.ab>           Generate analysis summary report
  carve <backup.ab>             File carving from backup image

${BOLD}LIVE DATA EXTRACTION:${NC}
  pull-data <package>           Pull app data directory (run-as)
  pull-databases <package>      Pull app databases
  pull-preferences <package>    Pull app shared preferences
  pull-cache <package>          Pull app cache directory
  pull-files <package> <path>   Pull specific app files

${BOLD}CONVERSION:${NC}
  ab2tar <backup.ab> [output]   Convert Android Backup to tar
  ab-info <backup.ab>           Quick backup format info

${DIM}Examples:${NC}
  $0 backup-app com.whatsapp
  $0 extract backup.ab
  $0 analyze backup.ab
  $0 find-secrets backup.ab
  $0 carve backup.ab
EOF
}

check_adb() { adb get-state &>/dev/null || { log_err "No device connected."; exit 1; }; }

# ─── BACKUP CREATION ────────────────────────────────────────

cmd_backup_app() {
    local pkg="${1:?Usage: $0 backup-app <package>}"
    check_adb
    local out="$OUT_DIR/backup_${pkg}_$(date +%Y%m%d_%H%M%S).ab"
    log_section "BACKUP: $pkg"
    log_progress "Creating backup"
    adb backup -f "$out" -noapk "$pkg" 2>/dev/null && log_done "Saved: $out" || log_fail "Backup failed"
}

cmd_backup_app_full() {
    local pkg="${1:?Usage: $0 backup-app-full <package>}"
    check_adb
    local out="$OUT_DIR/backup_full_${pkg}_$(date +%Y%m%d_%H%M%S).ab"
    log_section "FULL BACKUP: $pkg"
    log_progress "Creating full backup (incl APK)"
    adb backup -f "$out" -apk "$pkg" 2>/dev/null && log_done "Saved: $out" || log_fail "Backup failed"
}

cmd_backup_full() {
    check_adb
    local out="$OUT_DIR/full_backup_$(date +%Y%m%d_%H%M%S).ab"
    log_section "FULL DEVICE BACKUP"
    log_progress "Creating full backup"
    adb backup -f "$out" -all -shared -system 2>/dev/null && log_done "Saved: $out" || log_fail "Backup failed"
}

cmd_backup_system() {
    check_adb
    local out="$OUT_DIR/system_backup_$(date +%Y%m%d_%H%M%S).ab"
    log_section "SYSTEM BACKUP"
    log_progress "Creating system backup"
    adb backup -f "$out" -all -system 2>/dev/null && log_done "Saved: $out" || log_fail "Backup failed"
}

# ─── RESTORE ────────────────────────────────────────────────

cmd_restore_app() {
    local backup="${1:?Usage: $0 restore-app <backup.ab>}"
    [[ ! -f "$backup" ]] && { log_err "Backup not found: $backup"; exit 1; }
    check_adb
    log_section "RESTORE: $(basename "$backup")"
    log_warn "This will overwrite app data!"
    read -p "Confirm restore? (y/N): " yn; [[ "$yn" != "y" ]] && exit 0
    adb restore "$backup" && log_ok "Restore initiated" || log_err "Restore failed"
}

# ─── EXTRACTION ─────────────────────────────────────────────

cmd_extract() {
    local backup="${1:?Usage: $0 extract <backup.ab>}"
    [[ ! -f "$backup" ]] && { log_err "Backup not found: $backup"; exit 1; }

    local outdir="$OUT_DIR/$(basename "$backup" .ab)_extracted"
    mkdir -p "$TMP_DIR" "$outdir"
    rm -rf "$TMP_DIR"/*

    log_section "EXTRACT: $(basename "$backup")"
    log_progress "Extracting backup"

    if dd if="$backup" bs=24 skip=1 2>/dev/null | openssl zlib -d 2>/dev/null > "$TMP_DIR/backup.tar"; then
        log_done "Decompressed (zlib)"
    else
        log_warn "zlib decompression failed, trying raw extraction"
        dd if="$backup" bs=24 skip=1 2>/dev/null > "$TMP_DIR/backup.tar" || { log_fail "Extraction failed"; exit 1; }
    fi

    if [[ -f "$TMP_DIR/backup.tar" && -s "$TMP_DIR/backup.tar" ]]; then
        mkdir -p "$TMP_DIR/data"
        tar -xf "$TMP_DIR/backup.tar" -C "$TMP_DIR/data" 2>/dev/null || true
        log_done "Extracted to $TMP_DIR/data"
        cp -r "$TMP_DIR/data/"* "$outdir/" 2>/dev/null || true
        log_ok "All data: $outdir"
        cmd_analyze_content "$outdir"
    else
        log_fail "Extraction produced empty output"
        exit 1
    fi
}

cmd_extract_encrypted() {
    local backup="${1:?Usage: $0 extract-encrypted <backup.ab> <password>}"
    local password="${2:?Usage: $0 extract-encrypted <backup.ab> <password>}"
    [[ ! -f "$backup" ]] && { log_err "Backup not found: $backup"; exit 1; }

    local outdir="$OUT_DIR/$(basename "$backup" .ab)_decrypted"
    mkdir -p "$TMP_DIR" "$outdir"

    log_section "DECRYPT: $(basename "$backup")"
    log_progress "Decrypting with provided password"
    dd if="$backup" bs=24 skip=1 2>/dev/null | openssl enc -d -aes-256-cbc -md sha256 -pass "pass:$password" -iter 10000 2>/dev/null > "$TMP_DIR/backup.tar" || {
        log_fail "Decryption failed (wrong password or unsupported format)"
        exit 1
    }
    log_done "Decrypted"

    if [[ -f "$TMP_DIR/backup.tar" ]]; then
        tar -xf "$TMP_DIR/backup.tar" -C "$TMP_DIR/data" 2>/dev/null || true
        cp -r "$TMP_DIR/data/"* "$outdir/" 2>/dev/null || true
        log_ok "Decrypted to: $outdir"
    fi
}

# ─── ANALYSIS ───────────────────────────────────────────────

cmd_analyze() {
    local backup="${1:?Usage: $0 analyze <backup.ab>}"
    [[ ! -f "$backup" ]] && { log_err "Backup not found"; exit 1; }

    log_section "ANALYSIS: $(basename "$backup")"
    local size; size=$(stat -c%s "$backup" 2>/dev/null || stat -f%z "$backup")
    echo "  ${BOLD}File:${NC}         $backup"
    echo "  ${BOLD}Size:${NC}         $((size/1024/1024)) MB ($size bytes)"
    echo "  ${BOLD}Modified:${NC}     $(stat -c%y "$backup" 2>/dev/null | cut -d. -f1 || stat -f%Sm "$backup" 2>/dev/null)"

    local magic; magic=$(head -c16 "$backup" 2>/dev/null)
    if echo "$magic" | grep -q "ANDROID BACKUP"; then
        echo "  ${BOLD}Format:${NC}       Android Backup (AB)"
        local header; header=$(dd if="$backup" bs=1 count=24 2>/dev/null)
        local encryption=$(echo "$header" | tail -c9)
        if echo "$encryption" | grep -q "none"; then echo "  ${BOLD}Encryption:${NC}   None"
        elif echo "$encryption" | grep -q "AES-256"; then echo "  ${BOLD}Encryption:${NC}   AES-256"; fi
        echo "  ${BOLD}Compressed:${NC}   $(echo "$header" | grep -q 'compressed' && echo 'Yes' || echo 'No')"
    else
        echo "  ${BOLD}Format:${NC}       Unknown"
    fi

    echo
    echo "  ${BOLD}Detected packages:${NC}"
    strings "$backup" 2>/dev/null | grep -E '^[a-z][a-z]+\.[a-z]+\.[a-zA-Z0-9_.]+' | sort -u | head -20 | sed 's/^/    /'
}

cmd_analyze_content() {
    local dir="${1:-$TMP_DIR/data}"
    [[ ! -d "$dir" ]] && { log_err "No extracted data at $dir"; return; }

    echo
    log_section "CONTENT ANALYSIS"
    echo "  ${BOLD}Files:${NC}         $(find "$dir" -type f 2>/dev/null | wc -l)"
    echo "  ${BOLD}Directories:${NC}   $(find "$dir" -type d 2>/dev/null | wc -l)"
    echo "  ${BOLD}Total size:${NC}    $(du -sh "$dir" 2>/dev/null | cut -f1)"

    echo
    echo "  ${BOLD}Files by type:${NC}"
    echo "    SQLite:  $(find "$dir" -name '*.db' -o -name '*.sqlite' 2>/dev/null | wc -l)"
    echo "    XML:     $(find "$dir" -name '*.xml' 2>/dev/null | wc -l)"
    echo "    JSON:    $(find "$dir" -name '*.json' 2>/dev/null | wc -l)"
    echo "    Shared Prefs: $(find "$dir" -path '*/shared_prefs/*.xml' 2>/dev/null | wc -l)"
    echo "    Databases:    $(find "$dir" -path '*/databases/*' 2>/dev/null | wc -l)"

    echo
    echo "  ${BOLD}Top directories:${NC}"
    du -sh "$dir"/*/ 2>/dev/null | sort -rh | head -10 | sed 's/^/    /'
}

cmd_find_secrets() {
    local backup="${1:?Usage: $0 find-secrets <backup.ab>}"
    cmd_extract "$backup" 2>&1 >/dev/null
    local dir="$OUT_DIR/$(basename "$backup" .ab)_extracted"

    log_section "SECRETS SCAN"
    local patterns=('api.key|api.secret|api_token|api_key' 'password|passwd|pwd|pass' 'token|auth_token|access_token' 'secret|private.key|private_key' 'credential|login|username' 'jwt|bearer|session' 'aws_key|aws_secret|s3_key' 'ssh-rsa|ssh-ed25519' '-----BEGIN' 'encryption_key|cipher')
    local found=false
    for pattern in "${patterns[@]}"; do
        local results; results=$(find "$dir" -type f -exec grep -rl -E "$pattern" {} \; 2>/dev/null | head -20)
        if [[ -n "$results" ]]; then
            echo -e "  ${YELLOW}⚠${NC} Pattern '${pattern}' found in:"
            echo "$results" | sed 's/^/    /'
            found=true
        fi
    done
    if ! $found; then log_ok "No secrets patterns detected"; fi
}

cmd_find_databases() {
    local backup="${1:?Usage: $0 find-databases <backup.ab>}"
    cmd_extract "$backup" 2>&1 >/dev/null
    local dir="$OUT_DIR/$(basename "$backup" .ab)_extracted"

    log_section "DATABASES"
    local dbs; dbs=$(find "$dir" -name '*.db' -o -name '*.sqlite' 2>/dev/null)
    if [[ -n "$dbs" ]]; then
        echo "$dbs" | while IFS= read -r db; do
            local size; size=$(stat -c%s "$db" 2>/dev/null || stat -f%z "$db")
            echo "  $(basename "$db") — $((size/1024))KB"
        done
    else echo "  (none)"; fi
}

cmd_find_preferences() {
    local backup="${1:?Usage: $0 find-preferences <backup.ab>}"
    cmd_extract "$backup" 2>&1 >/dev/null
    local dir="$OUT_DIR/$(basename "$backup" .ab)_extracted"

    log_section "SHARED PREFERENCES"
    local prefs; prefs=$(find "$dir" -path '*/shared_prefs/*.xml' 2>/dev/null)
    if [[ -n "$prefs" ]]; then echo "$prefs" | sed 's/^/  /'; else echo "  (none)"; fi
}

cmd_summary() {
    local backup="${1:?Usage: $0 summary <backup.ab>}"
    cmd_analyze "$backup"
    cmd_extract "$backup" 2>&1 >/dev/null
}

cmd_carve() {
    local backup="${1:?Usage: $0 carve <backup.ab>}"
    [[ ! -f "$backup" ]] && { log_err "Backup not found"; exit 1; }

    local carvd="$OUT_DIR/$(basename "$backup" .ab)_carved"
    mkdir -p "$carvd"

    log_section "FILE CARVING: $(basename "$backup")"
    log_info "Scanning for embedded files..."

    # Carve PNG
    log_progress "Carving PNG files"
    local png_count=0
    while IFS= read -r -d '' offset; do
        local f="$carvd/carved_${png_count}.png"
        dd if="$backup" bs=1 skip="$offset" count=$((1024*1024)) 2>/dev/null | head -c 1M > "$f"
        [[ -s "$f" ]] && ((png_count++)) || rm -f "$f"
    done < <(grep -oba $'\x89PNG' "$backup" 2>/dev/null | cut -d: -f1 | head -20)
    log_done "PNG: $png_count carved"

    # Carve JPEG
    log_progress "Carving JPEG files"
    local jpg_count=0
    while IFS= read -r -d '' offset; do
        local f="$carvd/carved_${jpg_count}.jpg"
        dd if="$backup" bs=1 skip="$offset" count=$((1024*1024)) 2>/dev/null | head -c 1M > "$f"
        [[ -s "$f" ]] && ((jpg_count++)) || rm -f "$f"
    done < <(grep -oba $'\xff\xd8\xff' "$backup" 2>/dev/null | cut -d: -f1 | head -20)
    log_done "JPEG: $jpg_count carved"

    # Carve ZIP
    log_progress "Carving ZIP archives"
    local zip_count=0
    while IFS= read -r -d '' offset; do
        local f="$carvd/carved_${zip_count}.zip"
        dd if="$backup" bs=1 skip="$offset" count=$((10*1024*1024)) 2>/dev/null | head -c 10M > "$f"
        if unzip -l "$f" &>/dev/null; then ((zip_count++)); else rm -f "$f"; fi
    done < <(grep -oba $'PK\x03\x04' "$backup" 2>/dev/null | cut -d: -f1 | head -10)
    log_done "ZIP: $zip_count carved"

    echo
    log_info "Carved files: $carvd/"
    ls -lh "$carvd/" 2>/dev/null
}

# ─── LIST ───────────────────────────────────────────────────

cmd_list() {
    log_section "SAVED BACKUPS"
    if ls -lh "$OUT_DIR/"*.ab 2>/dev/null; then
        echo
        log_info "Total: $(ls "$OUT_DIR"/*.ab 2>/dev/null | wc -l) backup(s)"
    else
        echo "  ${YELLOW}(no backups yet)${NC}"
    fi
}

# ─── LIVE EXTRACTION ────────────────────────────────────────

cmd_pull_data() {
    local pkg="${1:?Usage: $0 pull-data <package>}"
    check_adb
    local dest="$OUT_DIR/data/$pkg"; mkdir -p "$dest"
    log_section "LIVE DATA: $pkg"
    log_progress "Pulling data"
    if adb shell run-as "$pkg" cp -r /data/data/"$pkg" /sdcard/"${pkg}_data" 2>/dev/null; then
        adb pull "/sdcard/${pkg}_data" "$dest" 2>/dev/null
        adb shell rm -rf "/sdcard/${pkg}_data"
        log_done "Data: $dest"
    elif adb shell su -c "cp -r /data/data/$pkg /sdcard/${pkg}_data" 2>/dev/null; then
        adb pull "/sdcard/${pkg}_data" "$dest" 2>/dev/null
        adb shell rm -rf "/sdcard/${pkg}_data"
        log_done "Data (root): $dest"
    else log_fail "Cannot access $pkg data"; fi
}

cmd_pull_databases() {
    local pkg="${1:?Usage: $0 pull-databases <package>}"
    check_adb; local dest="$OUT_DIR/databases/$pkg"; mkdir -p "$dest"
    log_section "DATABASES: $pkg"
    if adb shell run-as "$pkg" cp -r /data/data/"$pkg"/databases /sdcard/"${pkg}_db" 2>/dev/null; then
        adb pull "/sdcard/${pkg}_db" "$dest" 2>/dev/null; adb shell rm -rf "/sdcard/${pkg}_db"
        log_ok "Databases: $dest"
    elif adb shell su -c "cp -r /data/data/$pkg/databases /sdcard/${pkg}_db" 2>/dev/null; then
        adb pull "/sdcard/${pkg}_db" "$dest" 2>/dev/null; adb shell rm -rf "/sdcard/${pkg}_db"
        log_ok "Databases (root): $dest"
    else log_warn "Cannot access databases"; fi
}

cmd_pull_preferences() {
    local pkg="${1:?Usage: $0 pull-preferences <package>}"
    check_adb; local dest="$OUT_DIR/prefs"; mkdir -p "$dest"
    log_section "PREFERENCES: $pkg"
    adb shell run-as "$pkg" cat /data/data/"$pkg"/shared_prefs/*.xml 2>/dev/null > "$dest/${pkg}_prefs.xml" || \
    adb shell su -c "cat /data/data/$pkg/shared_prefs/*.xml" 2>/dev/null > "$dest/${pkg}_prefs.xml" || \
    log_warn "Cannot access preferences"
    [[ -s "$dest/${pkg}_prefs.xml" ]] && log_ok "Saved: $dest/${pkg}_prefs.xml" || log_warn "No preferences found"
}

cmd_pull_cache() {
    local pkg="${1:?Usage: $0 pull-cache <package>}"
    check_adb; local dest="$OUT_DIR/cache/$pkg"; mkdir -p "$dest"
    adb shell run-as "$pkg" cp -r /data/data/"$pkg"/cache /sdcard/"${pkg}_cache" 2>/dev/null && \
    adb pull "/sdcard/${pkg}_cache" "$dest" 2>/dev/null && adb shell rm -rf "/sdcard/${pkg}_cache" && log_ok "Cache: $dest" || \
    log_warn "Cannot access cache"
}

cmd_pull_files() {
    [[ $# -lt 2 ]] && { log_err "Usage: $0 pull-files <package> <path>"; exit 1; }
    local pkg="$1"; shift; local path="$1"
    check_adb; local dest="$OUT_DIR/files/$pkg"; mkdir -p "$dest"
    adb shell run-as "$pkg" cp -r "$path" /sdcard/"${pkg}_files" 2>/dev/null && \
    adb pull "/sdcard/${pkg}_files" "$dest" 2>/dev/null && adb shell rm -rf "/sdcard/${pkg}_files" && log_ok "Files: $dest" || \
    log_warn "Cannot access $path"
}

# ─── CONVERSION ─────────────────────────────────────────────

cmd_ab2tar() {
    local backup="${1:?Usage: $0 ab2tar <backup.ab> [output.tar]}"
    [[ ! -f "$backup" ]] && { log_err "Backup not found"; exit 1; }
    local out="${2:-${backup%.ab}.tar}"
    log_section "CONVERT: $(basename "$backup") → $(basename "$out")"
    log_progress "Converting"
    dd if="$backup" bs=24 skip=1 2>/dev/null | openssl zlib -d 2>/dev/null > "$out" || \
    dd if="$backup" bs=24 skip=1 2>/dev/null > "$out"
    if [[ -s "$out" ]]; then log_done "Created: $out ($(stat -c%s "$out" 2>/dev/null || stat -f%z "$out") bytes)"; else log_fail "Conversion failed"; fi
}

cmd_ab_info() {
    local backup="${1:?Usage: $0 ab-info <backup.ab>}"
    [[ ! -f "$backup" ]] && { log_err "Backup not found"; exit 1; }
    local magic; magic=$(head -c16 "$backup")
    if echo "$magic" | grep -q "ANDROID BACKUP"; then
        local ver=$(dd if="$backup" bs=1 skip=8 count=4 2>/dev/null)
        local compress=$(dd if="$backup" bs=1 skip=12 count=12 2>/dev/null)
        local enc=$(dd if="$backup" bs=1 skip=15 count=9 2>/dev/null)
        echo "  ${BOLD}Type:${NC}     Android Backup"
        echo "  ${BOLD}Version:${NC}  $ver"
        echo "  ${BOLD}Compressed:${NC} $(echo "$compress" | grep -q 'compressed' && echo 'Yes' || echo 'No')"
        echo "  ${BOLD}Encrypted:${NC} $(echo "$enc" | grep -q 'none' && echo 'No' || echo 'Yes')"
    else echo "  ${BOLD}Type:${NC}     Unknown"; fi
}

main() {
    [[ $# -lt 1 ]] && { show_help; exit 0; }
    local cmd="$1"; shift

    case "$cmd" in
        backup-app)           cmd_backup_app "$@";;
        backup-app-full)      cmd_backup_app_full "$@";;
        backup-full)          cmd_backup_full;;
        backup-system)        cmd_backup_system;;
        restore-app|restore)  cmd_restore_app "$@";;
        extract|unpack)       cmd_extract "$@";;
        extract-encrypted|decrypt) cmd_extract_encrypted "$@";;
        analyze|info)         cmd_analyze "$@";;
        find-secrets|secrets) cmd_find_secrets "$@";;
        find-databases|dbs)   cmd_find_databases "$@";;
        find-preferences|prefs) cmd_find_preferences "$@";;
        summary|report)       cmd_summary "$@";;
        carve|carving)        cmd_carve "$@";;
        list|ls)              cmd_list;;
        pull-data|data)       cmd_pull_data "$@";;
        pull-databases|databases) cmd_pull_databases "$@";;
        pull-preferences|preferences) cmd_pull_preferences "$@";;
        pull-cache|cache)     cmd_pull_cache "$@";;
        pull-files|files)     cmd_pull_files "$@";;
        ab2tar|2tar)          cmd_ab2tar "$@";;
        ab-info|abinfo)       cmd_ab_info "$@";;
        help|-h|--help)       show_help;;
        *) log_err "Unknown: $cmd"; show_help; exit 1;;
    esac
}

main "$@"
