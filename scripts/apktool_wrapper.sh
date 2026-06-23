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
APKTOOLS_DIR="$OUT_DIR/apktool"
mkdir -p "$APKTOOLS_DIR"

APKTOOL_JAR="${APKTOOL_JAR:-}"
DEFAULT_APKTOOL_VERSION="2.9.3"

find_apktool_jar() {
    if [[ -n "$APKTOOL_JAR" && -f "$APKTOOL_JAR" ]]; then
        echo "$APKTOOL_JAR"
        return 0
    fi
    local candidates=(
        "/usr/local/bin/apktool.jar"
        "/opt/apktool/apktool.jar"
        "$HOME/apktool.jar"
        "$HOME/.local/bin/apktool.jar"
        "$ANDROID_HOME/apktool.jar"
    )
    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

ensure_apktool_jar() {
    APKTOOL_JAR=$(find_apktool_jar) || true
    if [[ -z "$APKTOOL_JAR" || ! -f "$APKTOOL_JAR" ]]; then
        log_warn "apktool.jar not found locally."
        read -p "  Download apktool $DEFAULT_APKTOOL_VERSION? (Y/n): " yn
        case "$yn" in
            n|N|no) log_err "apktool.jar required. Set APKTOOL_JAR env or place in /usr/local/bin/apktool.jar"; exit 1;;
            *) cmd_download;;
        esac
    fi
}

check_java() {
    if ! command -v java &>/dev/null; then
        log_err "Java not found. Install Java Runtime Environment (JRE) 8+."
        exit 1
    fi
}

check_apktool() {
    check_java
    ensure_apktool_jar
}

cmd_download() {
    local version="${1:-$DEFAULT_APKTOOL_VERSION}"
    local url="https://github.com/iBotPeaches/Apktool/releases/download/v${version}/apktool_${version}.jar"
    local dest="/usr/local/bin/apktool.jar"

    if [[ -f "$dest" ]]; then
        log_ok "apktool.jar already exists at $dest"
        APKTOOL_JAR="$dest"
        return
    fi

    log_info "Downloading apktool v${version}..."
    mkdir -p "$(dirname "$dest")" "$APKTOOLS_DIR"

    if command -v wget &>/dev/null; then
        wget -q --show-progress "$url" -O "$dest" 2>&1 || wget -q "$url" -O "$dest"
    elif command -v curl &>/dev/null; then
        curl -# -L "$url" -o "$dest"
    else
        log_err "Neither wget nor curl found. Download manually: $url"
        exit 1
    fi

    if [[ -f "$dest" ]]; then
        local size=$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest" 2>/dev/null)
        if [[ "$size" -lt 1000000 ]]; then
            log_warn "Downloaded file seems too small (${size} bytes). Might be invalid."
            rm -f "$dest"
        else
            log_ok "Downloaded: $dest ($((size/1024/1024))MB)"
            APKTOOL_JAR="$dest"
            return
        fi
    fi
    log_err "Download failed. Try manual download: $url"
    exit 1
}

cmd_download_custom() {
    local version="${1:-}"
    if [[ -z "$version" ]]; then
        log_err "Usage: $0 download <version> (e.g. 2.9.3, 2.8.1)"
        exit 1
    fi
    local url="https://github.com/iBotPeaches/Apktool/releases/download/v${version}/apktool_${version}.jar"
    local dest="$APKTOOLS_DIR/apktool_${version}.jar"

    log_info "Downloading apktool v${version}..."
    if command -v wget &>/dev/null; then
        wget -q --show-progress "$url" -O "$dest" 2>&1 || wget -q "$url" -O "$dest"
    elif command -v curl &>/dev/null; then
        curl -# -L "$url" -o "$dest"
    else
        log_err "wget/curl not found"
        exit 1
    fi

    if [[ -f "$dest" ]]; then
        local size=$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest" 2>/dev/null)
        log_ok "Downloaded to $dest ($((size/1024/1024))MB)"
        log_info "Use: APKTOOL_JAR=$dest $0 <command>"
    else
        log_err "Download failed"
    fi
}

show_help() {
    cat <<EOF
${BOLD}Apktool Wrapper v${VERSION}${NC} — Advanced APK Decompilation & Rebuilding Toolkit
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 <command> [args] [options]

${BOLD}DECOMPILE COMMANDS:${NC}
  decompile <apk> [output-dir] [options]  Decompile APK to smali
    ${DIM}Options (append after dir): --no-res --no-src --debug --force --keep-broken${NC}
  decompile-advanced <apk> [output]       Interactive decompile with options

${BOLD}BUILD COMMANDS:${NC}
  build <directory> [output.apk]           Rebuild APK from smali directory
  build-sign <dir> [output.apk] [keystore] Rebuild and sign the APK

${BOLD}FRAMEWORK COMMANDS:${NC}
  framework-list                           List installed framework files
  framework-install <apk>                  Install framework APK
  framework-dir                            Show framework directory
  framework-delete <tag>                   Delete specific framework tag

${BOLD}BATCH & COMPARE:${NC}
  batch-decompile <directory>             Decompile all APKs in a directory
  batch-build <directory>                  Build all decompiled directories
  diff <apk1> <apk2>                       Compare two APK decompilations
  version                                  Show apktool version
  download [version]                       Download specific apktool version

${BOLD}OPTIONS (for decompile):${NC}
  --no-res         Skip resource decoding
  --no-src         Skip smali decompilation
  --debug          Enable debug mode (include line numbers)
  --force          Force overwrite output directory
  --keep-broken    Keep going if resources are broken
  --match-original Use original file paths (not smali)

${DIM}Examples:${NC}
  $0 decompile app.apk
  $0 decompile app.apk output_dir --no-res
  $0 build-sign decompiled_app/ signed.apk my.keystore
  $0 batch-decompile apks/
  $0 diff app1.apk app2.apk
EOF
}

# ─── DECOMPILE ───────────────────────────────────────────────

cmd_decompile() {
    check_apktool
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 decompile <apk> [output-dir] [options]"
        exit 1
    fi

    local apk="$1"; shift
    if [[ ! -f "$apk" ]]; then
        log_err "APK not found: $apk"
        exit 1
    fi

    local output=""
    local opts=()

    # Parse positional args and options
    if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
        output="$1"
        shift
    fi

    # Collect remaining options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-res)        opts+=("--no-res");;
            --no-src)        opts+=("--no-src");;
            --debug)         opts+=("--debug");;
            --force)         opts+=("--force");;
            --keep-broken)   opts+=("--keep-broken");;
            --match-original) opts+=("--match-original");;
            --output|-o)     shift; output="$1";;
            *)               opts+=("$1");;
        esac
        shift
    done

    if [[ -z "$output" ]]; then
        local base; base=$(basename "$apk" .apk)
        output="$APKTOOLS_DIR/$base"
    fi

    log_section "DECOMPILE APK"
    echo "  ${BOLD}Source:${NC}     $apk"
    echo "  ${BOLD}Output:${NC}     $output"
    echo "  ${BOLD}Options:${NC}    ${opts[*]:-none}"
    echo

    log_progress "Decompiling"

    mkdir -p "$(dirname "$output")"
    if java -jar "$APKTOOL_JAR" decode -f -o "$output" "${opts[@]}" "$apk" 2>&1; then
        log_done "Decompiled to: $output"
        echo
        echo "  ${BOLD}Files:${NC}     $(find "$output" -type f 2>/dev/null | wc -l)"
        echo "  ${BOLD}Smali:${NC}     $(find "$output" -name '*.smali' -type f 2>/dev/null | wc -l)"
        echo "  ${BOLD}Resources:${NC} $(find "$output" -name '*.xml' -type f 2>/dev/null | wc -l)"
    else
        log_fail "Decompilation failed"
        exit 1
    fi
}

cmd_decompile_advanced() {
    check_apktool
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 decompile-advanced <apk>"
        exit 1
    fi

    local apk="$1"
    [[ ! -f "$apk" ]] && { log_err "APK not found: $apk"; exit 1; }

    log_section "ADVANCED DECOMPILE OPTIONS"
    echo "  APK: $apk"
    echo

    local opts=()
    local out_dir="${2:-$APKTOOLS_DIR/$(basename "$apk" .apk)}"

    read -p "Skip resources? (--no-res) [y/N]: " skip_res
    [[ "$skip_res" == "y" ]] && opts+=("--no-res")

    read -p "Skip smali? (--no-src) [y/N]: " skip_src
    [[ "$skip_src" == "y" ]] && opts+=("--no-src")

    read -p "Debug mode? (--debug) [y/N]: " debug
    [[ "$debug" == "y" ]] && opts+=("--debug")

    read -p "Force overwrite? (--force) [Y/n]: " force
    [[ "$force" != "n" ]] && opts+=("--force")

    read -p "Keep broken resources? [y/N]: " broken
    [[ "$broken" == "y" ]] && opts+=("--keep-broken")

    read -p "Output directory [${out_dir}]: " custom_out
    out_dir="${custom_out:-$out_dir}"

    echo
    log_info "Decompiling with: ${opts[*]:-default options}"
    mkdir -p "$(dirname "$out_dir")"

    log_progress "Decompiling"
    if java -jar "$APKTOOL_JAR" decode -o "$out_dir" "${opts[@]}" "$apk" 2>&1; then
        log_done "Decompiled to: $out_dir"
    else
        log_fail "Decompilation failed"
        exit 1
    fi
}

# ─── BUILD ───────────────────────────────────────────────────

cmd_build() {
    check_apktool
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 build <directory> [output.apk]"
        exit 1
    fi

    local dir="$1"
    local output="${2:-}"

    if [[ ! -d "$dir" ]]; then
        log_err "Directory not found: $dir"
        exit 1
    fi

    if [[ ! -f "$dir/apktool.yml" ]]; then
        log_warn "Warning: $dir/apktool.yml not found. Is this a valid decompiled APK?"
        read -p "Continue anyway? (y/N): " yn
        [[ "$yn" != "y" ]] && exit 0
    fi

    log_section "BUILD APK"
    echo "  ${BOLD}Source:${NC}     $dir"
    echo "  ${BOLD}Output:${NC}     ${output:-auto}"
    echo

    log_progress "Building"

    local build_cmd=(java -jar "$APKTOOL_JAR" build -f "$dir")
    if [[ -n "$output" ]]; then
        build_cmd+=(-o "$output")
    fi

    if "${build_cmd[@]}" 2>&1; then
        local result="${output:-$dir/dist/$(basename "$dir").apk}"
        if [[ -f "$result" ]]; then
            local size=$(stat -c%s "$result" 2>/dev/null || stat -f%z "$result" 2>/dev/null)
            log_done "APK built: $result ($((size/1024/1024))MB)"
        else
            log_done "APK built successfully"
        fi
    else
        log_fail "Build failed"
        exit 1
    fi
}

cmd_build_sign() {
    check_apktool
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 build-sign <directory> [output.apk] [keystore]"
        exit 1
    fi

    local dir="$1"
    local output="${2:-$APKTOOLS_DIR/$(basename "$dir")_signed.apk}"
    local keystore="${3:-}"

    cmd_build "$dir" "$output"

    if [[ -f "$output" ]]; then
        if [[ -z "$keystore" ]]; then
            keystore="${KEYSTORE:-androxploit.keystore}"
            if [[ ! -f "$keystore" ]]; then
                log_warn "No keystore found at $keystore"
                log_info "Generate one with: $ANDROID_HOME/scripts/apk_signing.sh genkeystore"
                return
            fi
        fi

        log_info "Signing $output with $keystore..."
        if command -v apksigner &>/dev/null; then
            apksigner sign --ks "$keystore" --ks-pass pass:androxploit \
                --ks-key-alias androxploit "$output"
            log_ok "Signed: $output"
        else
            jarsigner -sigalg SHA256withRSA -digestalg SHA-256 \
                -keystore "$keystore" -storepass androxploit "$output" androxploit
            log_ok "Signed (v1): $output"
        fi
    fi
}

# ─── FRAMEWORK ───────────────────────────────────────────────

cmd_framework_list() {
    check_apktool
    log_section "INSTALLED FRAMEWORKS"
    java -jar "$APKTOOL_JAR" framework list 2>&1 || log_err "Failed to list frameworks"
}

cmd_framework_install() {
    check_apktool
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 framework-install <apk> [tag]"
        exit 1
    fi
    local apk="$1"; shift
    [[ ! -f "$apk" ]] && { log_err "APK not found: $apk"; exit 1; }

    log_progress "Installing framework: $apk"
    if java -jar "$APKTOOL_JAR" framework -i "$apk" "$@" 2>&1; then
        log_done "Framework installed"
    else
        log_fail "Framework installation failed"
    fi
}

cmd_framework_dir() {
    check_apktool
    local fdir="$HOME/.local/share/apktool/framework"
    if [[ ! -d "$fdir" ]]; then
        fdir="$HOME/apktool/framework"
    fi
    if [[ -d "$fdir" ]]; then
        echo "Framework directory: $fdir"
        ls -lh "$fdir" 2>/dev/null
    else
        log_info "No framework directory found"
    fi
}

cmd_framework_delete() {
    check_apktool
    if [[ $# -lt 1 ]]; then
        log_err "Usage: $0 framework-delete <tag>"
        log_info "Use framework-list to see available tags"
        exit 1
    fi
    local tag="$1"
    log_warn "Deleting framework: $tag"
    java -jar "$APKTOOL_JAR" framework -d "$tag" 2>&1 && log_ok "Deleted" || log_err "Failed"
}

# ─── BATCH ───────────────────────────────────────────────────

cmd_batch_decompile() {
    check_apktool
    local dir="${1:?Usage: $0 batch-decompile <directory>}"
    if [[ ! -d "$dir" ]]; then
        log_err "Directory not found: $dir"
        exit 1
    fi

    local apks=()
    while IFS= read -r -d '' f; do
        apks+=("$f")
    done < <(find "$dir" -name '*.apk' -type f -print0 2>/dev/null)

    if [[ ${#apks[@]} -eq 0 ]]; then
        log_warn "No APKs found in $dir"
        exit 0
    fi

    log_section "BATCH DECOMPILE (${#apks[@]} APKs)"
    local success=0; local failed=0

    for apk in "${apks[@]}"; do
        local base; base=$(basename "$apk" .apk)
        local out="$APKTOOLS_DIR/batch/$base"
        echo
        log_progress "Decompiling: $base"
        if java -jar "$APKTOOL_JAR" decode -f -o "$out" "$apk" 2>/dev/null; then
            log_done "Done: $base"
            ((success++)) || true
        else
            log_fail "Failed: $base"
            ((failed++)) || true
        fi
    done

    echo
    log_info "Results: ${GREEN}$success succeeded${NC}, ${RED}$failed failed${NC}, ${#apks[@]} total"
    if [[ $success -gt 0 ]]; then
        log_info "Output: $APKTOOLS_DIR/batch/"
    fi
}

cmd_batch_build() {
    check_apktool
    local dir="${1:?Usage: $0 batch-build <directory>}"
    if [[ ! -d "$dir" ]]; then
        log_err "Directory not found: $dir"
        exit 1
    fi

    local projects=()
    while IFS= read -r -d '' d; do
        [[ -f "$d/apktool.yml" ]] && projects+=("$d")
    done < <(find "$dir" -maxdepth 1 -type d -print0 2>/dev/null)

    if [[ ${#projects[@]} -eq 0 ]]; then
        # Try deeper
        while IFS= read -r -d '' d; do
            [[ -f "$d/apktool.yml" ]] && projects+=("$d")
        done < <(find "$dir" -name apktool.yml -exec dirname {} \; -print0 2>/dev/null | sort -u)
    fi

    if [[ ${#projects[@]} -eq 0 ]]; then
        log_warn "No decompiled projects found in $dir"
        exit 0
    fi

    # Deduplicate
    local unique=()
    while IFS= read -r -d '' p; do
        unique+=("$p")
    done < <(printf '%s\0' "${projects[@]}" | sort -uz)

    log_section "BATCH BUILD (${#unique[@]} projects)"
    local success=0; local failed=0
    mkdir -p "$APKTOOLS_DIR/batch_built"

    for project in "${unique[@]}"; do
        local name; name=$(basename "$project")
        local out="$APKTOOLS_DIR/batch_built/${name}.apk"
        echo
        log_progress "Building: $name"
        if java -jar "$APKTOOL_JAR" build -f -o "$out" "$project" 2>/dev/null; then
            local size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out" 2>/dev/null)
            log_done "Built: $name ($((size/1024/1024))MB)"
            ((success++)) || true
        else
            log_fail "Failed: $name"
            ((failed++)) || true
        fi
    done

    echo
    log_info "Results: ${GREEN}$success succeeded${NC}, ${RED}$failed failed${NC}"
}

# ─── DIFF ────────────────────────────────────────────────────

cmd_diff() {
    check_apktool
    if [[ $# -lt 2 ]]; then
        log_err "Usage: $0 diff <apk1> <apk2>"
        exit 1
    fi

    local apk1="$1"; local apk2="$2"
    [[ ! -f "$apk1" ]] && { log_err "Not found: $apk1"; exit 1; }
    [[ ! -f "$apk2" ]] && { log_err "Not found: $apk2"; exit 1; }

    local tmp1="/tmp/apktool_diff_1_$$"
    local tmp2="/tmp/apktool_diff_2_$$"
    mkdir -p "$tmp1" "$tmp2"
    trap "rm -rf $tmp1 $tmp2" EXIT

    log_section "APK DIFF"
    echo "  ${BOLD}Left:${NC}  $apk1"
    echo "  ${BOLD}Right:${NC} $apk2"
    echo

    log_progress "Decompiling APK 1"
    java -jar "$APKTOOL_JAR" decode -f -o "$tmp1" "$apk1" 2>/dev/null || { log_fail "Failed to decompile $apk1"; exit 1; }
    log_done "Decompiled APK 1"

    log_progress "Decompiling APK 2"
    java -jar "$APKTOOL_JAR" decode -f -o "$tmp2" "$apk2" 2>/dev/null || { log_fail "Failed to decompile $apk2"; exit 1; }
    log_done "Decompiled APK 2"

    echo
    log_section "DIFF RESULTS"

    if command -v diff &>/dev/null && command -v colordiff &>/dev/null; then
        local diff_cmd="colordiff"
    else
        local diff_cmd="diff"
    fi

    # Compare file lists
    log_info "File count comparison:"
    echo "  ${BOLD}APK 1:${NC} $(find "$tmp1" -type f | wc -l) files"
    echo "  ${BOLD}APK 2:${NC} $(find "$tmp2" -type f | wc -l) files"

    # Compare smali counts
    local smali1=$(find "$tmp1" -name '*.smali' -type f | wc -l)
    local smali2=$(find "$tmp2" -name '*.smali' -type f | wc -l)
    echo "  ${BOLD}Smali 1:${NC} $smali1 files"
    echo "  ${BOLD}Smali 2:${NC} $smali2 files"

    echo
    log_info "Files only in APK 1:"
    comm -23 <(find "$tmp1" -type f -printf '%P\n' | sort) <(find "$tmp2" -type f -printf '%P\n' | sort) | head -20 | sed 's/^/  /'

    echo
    log_info "Files only in APK 2:"
    comm -13 <(find "$tmp1" -type f -printf '%P\n' | sort) <(find "$tmp2" -type f -printf '%P\n' | sort) | head -20 | sed 's/^/  /'

    echo
    log_info "Comparing AndroidManifest.xml..."
    if [[ -f "$tmp1/AndroidManifest.xml" && -f "$tmp2/AndroidManifest.xml" ]]; then
        $diff_cmd "$tmp1/AndroidManifest.xml" "$tmp2/AndroidManifest.xml" 2>/dev/null | head -50 || echo "  (identical)"
    fi

    echo
    log_info "Comparing resources (res/)..."
    if diff -rq "$tmp1/res" "$tmp2/res" 2>/dev/null | head -20; then
        echo "  Resources are identical"
    fi
}

# ─── VERSION ─────────────────────────────────────────────────

cmd_version() {
    check_apktool
    log_section "APKTOOL VERSION INFO"
    java -jar "$APKTOOL_JAR" version 2>&1
    echo
    echo "  ${BOLD}Wrapper:${NC}  v$VERSION"
    echo "  ${BOLD}Java:${NC}     $(java -version 2>&1 | head -1)"
    echo "  ${BOLD}Jar:${NC}      $APKTOOL_JAR"
    local size=$(stat -c%s "$APKTOOL_JAR" 2>/dev/null || stat -f%z "$APKTOOL_JAR" 2>/dev/null)
    echo "  ${BOLD}Size:${NC}     $((size/1024/1024))MB"
}

# ─── MAIN ────────────────────────────────────────────────────

main() {
    if [[ $# -lt 1 ]]; then
        show_help
        exit 0
    fi

    local cmd="$1"
    shift

    case "$cmd" in
        decompile|decode)           cmd_decompile "$@";;
        decompile-advanced|decompile-int) cmd_decompile_advanced "$@";;
        build|rebuild)              cmd_build "$@";;
        build-sign|build-signed)    cmd_build_sign "$@";;
        framework-list|frameworks)  cmd_framework_list;;
        framework-install|install-fw) cmd_framework_install "$@";;
        framework-dir|fwdir)        cmd_framework_dir;;
        framework-delete|delete-fw) cmd_framework_delete "$@";;
        batch-decompile|batch-decode) cmd_batch_decompile "$@";;
        batch-build|batch-rebuild)  cmd_batch_build "$@";;
        diff|compare)               cmd_diff "$@";;
        download|get)               cmd_download_custom "$@";;
        version)                    cmd_version;;
        help|-h|--help)             show_help;;
        *)
            log_err "Unknown command: $cmd"
            echo
            show_help
            exit 1
            ;;
    esac
}

main "$@"
