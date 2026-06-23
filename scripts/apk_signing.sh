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

DEFAULT_KEYSTORE="androxploit.keystore"
DEFAULT_PASS="androxploit"
DEFAULT_ALIAS="androxploit"
DEFAULT_VALIDITY=3650
DEFAULT_DNAME="CN=AndroXploit, OU=Security, O=AndroXploit, L=Unknown, ST=Unknown, C=UN"

show_help() {
    cat <<EOF
${BOLD}APK Signing v${VERSION}${NC} — Enterprise Android APK Signing Toolkit
${DIM}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Usage:${NC} $0 <command> [args]

${BOLD}KEYSTORE COMMANDS:${NC}
  genkeystore [opts]              Generate new keystore (RSA 2048, SHA256)
  genkeystore-ecdsa               Generate keystore with ECDSA algorithm
  genkeystore-dsa                 Generate keystore with DSA algorithm
  keystore-info [keystore]        Show keystore certificate details
  keystore-list [keystore]        List all aliases in keystore

${BOLD}SIGNING COMMANDS:${NC}
  v1 <apk> [keystore]             Sign with v1 scheme (JAR signature)
  v2 <apk> [keystore]             Sign with v2 scheme (APK Signature)
  v3 <apk> [keystore]             Sign with v3 scheme (APK Signature v3)
  full <apk> [keystore]           Full sign: align + v1 + v2
  batch <pattern> [keystore]      Batch sign all APKs matching pattern

${BOLD}VERIFICATION COMMANDS:${NC}
  verify <apk>                    Verify APK signature with details
  verify-deep <apk>               Deep verification with all checks
  verify-v1 <apk>                 Check v1 signature only
  verify-v2 <apk>                 Check v2 signature only

${BOLD}UTILITY COMMANDS:${NC}
  zipalign <apk>                  Align APK (zip alignment)
  info <apk>                      Show certificate info from APK
  hash <apk>                      Show APK file hashes (MD5, SHA1, SHA256)
  cert-info <keystore>            Extract certificate details from keystore
  convert <pfx> <keystore>        Convert PKCS12/PFX to JKS keystore

${DIM}Examples:${NC}
  $0 genkeystore                                          # Default keystore
  $0 full app.apk                                         # Sign with align+v1+v2
  $0 verify app.apk                                       # Verify signature
  $0 batch "output/apks/*.apk"                           # Batch sign
  $0 keystore-info my.keystore                           # Keystore details
EOF
}

# ─── DEPENDENCY CHECKS ──────────────────────────────────────

check_java() { command -v java &>/dev/null || { log_err "Java required (JRE/JDK)"; exit 1; }; }
check_jarsigner() { command -v jarsigner &>/dev/null || { log_err "jarsigner not found (install JDK)"; exit 1; }; }
check_keytool() { command -v keytool &>/dev/null || { log_err "keytool not found (install JDK)"; exit 1; }; }

find_apksigner() {
    local apksigner
    apksigner=$(command -v apksigner 2>/dev/null || echo "")
    if [[ -z "$apksigner" ]]; then
        apksigner=$(find "$ANDROID_HOME" -name apksigner -type f 2>/dev/null | head -1)
    fi
    if [[ -z "$apksigner" ]]; then
        apksigner=$(find "$ANDROID_SDK_ROOT" -name apksigner -type f 2>/dev/null | head -1)
    fi
    echo "$apksigner"
}

find_zipalign() {
    local zipa
    zipa=$(command -v zipalign 2>/dev/null || echo "")
    if [[ -z "$zipa" ]]; then
        zipa=$(find "$ANDROID_HOME/build-tools" -name zipalign -type f 2>/dev/null | head -1)
    fi
    if [[ -z "$zipa" ]]; then
        zipa=$(find "$ANDROID_SDK_ROOT/build-tools" -name zipalign -type f 2>/dev/null | head -1)
    fi
    echo "$zipa"
}

resolve_keystore() {
    local ks="${1:-$DEFAULT_KEYSTORE}"
    if [[ ! -f "$ks" ]]; then
        if [[ -f "$DEFAULT_KEYSTORE" ]]; then
            ks="$DEFAULT_KEYSTORE"
        else
            log_warn "Keystore not found: $ks"
            log_info "Generate one: $0 genkeystore"
            return 1
        fi
    fi
    echo "$ks"
}

# ─── KEYSTORE GENERATION ────────────────────────────────────

cmd_genkeystore() {
    check_java; check_keytool
    local keystore="${1:-$DEFAULT_KEYSTORE}"
    local algo="${2:-RSA}"
    local keysize="${3:-2048}"

    if [[ -f "$keystore" ]]; then
        log_warn "Keystore exists: $keystore"
        read -p "Overwrite? (y/N): " yn; [[ "$yn" != "y" ]] && exit 0
    fi

    log_section "GENERATE KEYSTORE"
    echo "  ${BOLD}File:${NC}    $keystore"
    echo "  ${BOLD}Alias:${NC}   $DEFAULT_ALIAS"
    echo "  ${BOLD}Algo:${NC}    $algo ($keysize)"
    echo "  ${BOLD}Validity:${NC} $DEFAULT_VALIDITY days"
    echo

    log_progress "Generating"
    if keytool -genkey -v \
        -keystore "$keystore" \
        -alias "$DEFAULT_ALIAS" \
        -keyalg "$algo" -keysize "$keysize" \
        -validity "$DEFAULT_VALIDITY" \
        -storepass "$DEFAULT_PASS" \
        -keypass "$DEFAULT_PASS" \
        -dname "$DEFAULT_DNAME" 2>&1; then
        log_done "Keystore generated: $keystore"
        echo
        cmd_keystore_info "$keystore"
    else
        log_fail "Keystore generation failed"
        exit 1
    fi
}

cmd_genkeystore_ecdsa() {
    cmd_genkeystore "${1:-$DEFAULT_KEYSTORE}" "EC" 256
}

cmd_genkeystore_dsa() {
    cmd_genkeystore "${1:-$DEFAULT_KEYSTORE}" "DSA" 2048
}

cmd_keystore_info() {
    local ks="${1:-$DEFAULT_KEYSTORE}"
    [[ ! -f "$ks" ]] && { log_err "Keystore not found: $ks"; exit 1; }
    check_java; check_keytool

    log_section "KEYSTORE INFO: $ks"
    keytool -list -v -keystore "$ks" -storepass "$DEFAULT_PASS" 2>&1 | head -40
}

cmd_keystore_list() {
    local ks="${1:-$DEFAULT_KEYSTORE}"
    [[ ! -f "$ks" ]] && { log_err "Keystore not found: $ks"; exit 1; }

    log_section "ALIASES IN: $ks"
    keytool -list -keystore "$ks" -storepass "$DEFAULT_PASS" 2>&1 | grep -v "Enter keystore password"
}

# ─── SIGNING ────────────────────────────────────────────────

cmd_sign_v1() {
    local apk="${1:?Usage: $0 v1 <apk> [keystore]}"
    local ks; ks=$(resolve_keystore "${2:-}") || exit 1
    [[ ! -f "$apk" ]] && { log_err "APK not found: $apk"; exit 1; }

    log_section "SIGN v1 (JAR): $(basename "$apk")"
    log_progress "Signing (v1)"
    if jarsigner -sigalg SHA256withRSA -digestalg SHA-256 \
        -keystore "$ks" -storepass "$DEFAULT_PASS" \
        -keypass "$DEFAULT_PASS" "$apk" "$DEFAULT_ALIAS" 2>&1; then
        log_done "Signed (v1): $apk"
    else
        log_fail "v1 signing failed"
        exit 1
    fi
}

cmd_sign_v2() {
    local apk="${1:?Usage: $0 v2 <apk> [keystore]}"
    local ks; ks=$(resolve_keystore "${2:-}") || exit 1
    [[ ! -f "$apk" ]] && { log_err "APK not found: $apk"; exit 1; }

    local apksigner; apksigner=$(find_apksigner)
    if [[ -z "$apksigner" ]]; then
        log_warn "apksigner not found, falling back to v1 only"
        cmd_sign_v1 "$apk" "$ks"
        return
    fi

    log_section "SIGN v2 (APK): $(basename "$apk")"
    log_progress "Signing (v2)"
    if "$apksigner" sign --ks "$ks" --ks-pass "pass:$DEFAULT_PASS" \
        --ks-key-alias "$DEFAULT_ALIAS" --v2-signing-enabled true \
        --v1-signing-enabled false "$apk" 2>&1; then
        log_done "Signed (v2): $apk"
    else
        log_fail "v2 signing failed"
        exit 1
    fi
}

cmd_sign_v3() {
    local apk="${1:?Usage: $0 v3 <apk> [keystore]}"
    local ks; ks=$(resolve_keystore "${2:-}") || exit 1
    [[ ! -f "$apk" ]] && { log_err "APK not found: $apk"; exit 1; }

    local apksigner; apksigner=$(find_apksigner)
    [[ -z "$apksigner" ]] && { log_err "apksigner required for v3 signing"; exit 1; }

    log_section "SIGN v3 (APK v3): $(basename "$apk")"
    log_progress "Signing (v3)"
    if "$apksigner" sign --ks "$ks" --ks-pass "pass:$DEFAULT_PASS" \
        --ks-key-alias "$DEFAULT_ALIAS" --v3-signing-enabled true \
        --v1-signing-enabled false --v2-signing-enabled false "$apk" 2>&1; then
        log_done "Signed (v3): $apk"
    else
        log_fail "v3 signing failed"
        exit 1
    fi
}

cmd_sign_full() {
    local apk="${1:?Usage: $0 full <apk> [keystore]}"
    local ks; ks=$(resolve_keystore "${2:-}") || exit 1
    [[ ! -f "$apk" ]] && { log_err "APK not found: $apk"; exit 1; }

    log_section "FULL SIGN: $(basename "$apk")"

    # Step 1: Zipalign
    local zipa; zipa=$(find_zipalign)
    if [[ -n "$zipa" ]]; then
        local aligned="${apk%.apk}_aligned.apk"
        log_progress "Zipaligning"
        if "$zipa" -p -f 4 "$apk" "$aligned" 2>/dev/null; then
            mv "$aligned" "$apk"
            log_done "Aligned: $apk"
        else
            log_fail "Zipalign failed"
            exit 1
        fi
    else
        log_warn "zipalign not found, skipping alignment"
    fi

    # Step 2: v1 sign
    log_progress "Signing (v1)"
    if jarsigner -sigalg SHA256withRSA -digestalg SHA-256 \
        -keystore "$ks" -storepass "$DEFAULT_PASS" \
        -keypass "$DEFAULT_PASS" "$apk" "$DEFAULT_ALIAS" 2>&1; then
        log_done "Signed (v1)"
    else
        log_fail "v1 signing failed"
        exit 1
    fi

    # Step 3: v2 sign
    local apksigner; apksigner=$(find_apksigner)
    if [[ -n "$apksigner" ]]; then
        log_progress "Signing (v2)"
        if "$apksigner" sign --ks "$ks" --ks-pass "pass:$DEFAULT_PASS" \
            --ks-key-alias "$DEFAULT_ALIAS" --v2-signing-enabled true \
            --v1-signing-enabled false "$apk" 2>&1; then
            log_done "Signed (v2)"
        else
            log_warn "v2 signing failed (non-critical if v1 works)"
        fi
    fi

    echo
    log_ok "Full signing complete: $apk"
    cmd_verify "$apk"
}

# ─── BATCH SIGN ─────────────────────────────────────────────

cmd_batch() {
    local pattern="${1:?Usage: $0 batch <pattern> [keystore]}" 
    local ks; ks=$(resolve_keystore "${2:-}") || exit 1

    local apks=()
    for f in $pattern; do
        [[ -f "$f" && "$f" == *.apk ]] && apks+=("$f")
    done

    if [[ ${#apks[@]} -eq 0 ]]; then
        log_err "No APKs matching: $pattern"
        exit 1
    fi

    log_section "BATCH SIGN (${#apks[@]} APKs)"
    local success=0; local failed=0

    for apk in "${apks[@]}"; do
        echo
        log_progress "Signing: $(basename "$apk")"
        if cmd_sign_full "$apk" "$ks" 2>&1 | tail -1 | grep -q "DONE"; then
            ((success++)) || true
        else
            ((failed++)) || true
        fi
    done

    echo
    log_info "Batch results: ${GREEN}$success signed${NC}, ${RED}$failed failed${NC}"
}

# ─── VERIFICATION ───────────────────────────────────────────

cmd_verify() {
    local apk="${1:?Usage: $0 verify <apk>}"
    [[ ! -f "$apk" ]] && { log_err "APK not found: $apk"; exit 1; }

    log_section "VERIFY: $(basename "$apk")"
    log_progress "Verifying"
    if jarsigner -verify -certs -verbose "$apk" 2>&1; then
        echo
        log_ok "✓ Signature VERIFIED"
    else
        echo
        log_err "✗ Signature INVALID"
    fi
}

cmd_verify_deep() {
    local apk="${1:?Usage: $0 verify-deep <apk>}"
    [[ ! -f "$apk" ]] && { log_err "APK not found: $apk"; exit 1; }

    log_section "DEEP VERIFY: $(basename "$apk")"
    
    # v1 check
    log_progress "Checking v1 signature"
    if jarsigner -verify "$apk" 2>/dev/null; then
        log_done "v1: VALID"
    else
        log_warn "v1: INVALID or missing"
    fi

    # v2/v3 check with apksigner
    local apksigner; apksigner=$(find_apksigner)
    if [[ -n "$apksigner" ]]; then
        log_progress "Checking v2/v3 signature"
        if "$apksigner" verify -v --print-certs "$apk" 2>/dev/null; then
            log_done "v2/v3: VALID"
        else
            log_warn "v2/v3: INVALID or missing"
        fi
    fi

    echo
    log_info "Certificate details:"
    jarsigner -verify -certs -verbose "$apk" 2>&1 | grep -E "X.509|CN=|SHA|\[certificate" | head -10
}

cmd_verify_v1() {
    local apk="${1:?Usage: $0 verify-v1 <apk>}"
    [[ ! -f "$apk" ]] && { log_err "APK not found"; exit 1; }
    jarsigner -verify -certs "$apk" 2>&1
}

cmd_verify_v2() {
    local apk="${1:?Usage: $0 verify-v2 <apk>}"
    [[ ! -f "$apk" ]] && { log_err "APK not found"; exit 1; }
    local apksigner; apksigner=$(find_apksigner)
    [[ -z "$apksigner" ]] && { log_err "apksigner not found"; exit 1; }
    "$apksigner" verify -v --print-certs "$apk" 2>&1
}

# ─── UTILITY ────────────────────────────────────────────────

cmd_zipalign() {
    local apk="${1:?Usage: $0 zipalign <apk>}"
    [[ ! -f "$apk" ]] && { log_err "APK not found"; exit 1; }

    local zipa; zipa=$(find_zipalign)
    [[ -z "$zipa" ]] && { log_err "zipalign not found"; exit 1; }

    local aligned="${apk%.apk}_aligned.apk"
    log_section "ZIPALIGN: $(basename "$apk")"
    log_progress "Aligning"
    if "$zipa" -v -p -f 4 "$apk" "$aligned" 2>&1; then
        local orig; orig=$(stat -c%s "$apk" 2>/dev/null || stat -f%z "$apk")
        local new; new=$(stat -c%s "$aligned" 2>/dev/null || stat -f%z "$aligned")
        mv "$aligned" "$apk"
        log_done "Aligned: $apk ($orig → $new bytes)"
    else
        log_fail "Zipalign failed"
        exit 1
    fi
}

cmd_info() {
    local apk="${1:?Usage: $0 info <apk>}"
    [[ ! -f "$apk" ]] && { log_err "APK not found"; exit 1; }

    log_section "CERTIFICATE INFO: $(basename "$apk")"
    if jarsigner -verify -certs -verbose "$apk" 2>&1 | grep -E "X\.509|CN=|SHA|\[certificate|jar verified|->" | head -20; then
        echo
        # APK file info
        local size; size=$(stat -c%s "$apk" 2>/dev/null || stat -f%z "$apk")
        echo "  ${BOLD}File size:${NC} $((size/1024/1024))MB ($size bytes)"
        echo "  ${BOLD}Signed:${NC}   $(unzip -l "$apk" 2>/dev/null | grep -c 'META-INF' || echo 0) META-INF entries"
    else
        log_warn "No valid signature found"
    fi
}

cmd_hash() {
    local apk="${1:?Usage: $0 hash <apk>}"
    [[ ! -f "$apk" ]] && { log_err "APK not found"; exit 1; }

    log_section "FILE HASHES: $(basename "$apk")"
    echo "  ${BOLD}MD5:${NC}    $(md5sum "$apk" 2>/dev/null | cut -d' ' -f1 || md5 -q "$apk" 2>/dev/null || echo 'N/A')"
    echo "  ${BOLD}SHA1:${NC}   $(sha1sum "$apk" 2>/dev/null | cut -d' ' -f1 || shasum -a 1 "$apk" 2>/dev/null | cut -d' ' -f1 || echo 'N/A')"
    echo "  ${BOLD}SHA256:${NC} $(sha256sum "$apk" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$apk" 2>/dev/null | cut -d' ' -f1 || echo 'N/A')"
}

cmd_cert_info() {
    local ks; ks=$(resolve_keystore "${1:-}") || exit 1
    check_java; check_keytool

    log_section "CERTIFICATE: $ks"
    keytool -exportcert -alias "$DEFAULT_ALIAS" -keystore "$ks" \
        -storepass "$DEFAULT_PASS" -rfc 2>/dev/null | openssl x509 -text -noout 2>/dev/null | head -30 || {
        keytool -printcert -jarfile "$ks" 2>/dev/null || log_err "Cannot read certificate"
    }
}

cmd_convert() {
    local pfx="${1:?Usage: $0 convert <pfx> <keystore>}"
    local out="${2:-converted.keystore}"
    [[ ! -f "$pfx" ]] && { log_err "PFX not found: $pfx"; exit 1; }

    log_section "CONVERT: $pfx → $out"
    log_progress "Converting"
    if keytool -importkeystore \
        -srckeystore "$pfx" -srcstoretype PKCS12 \
        -destkeystore "$out" -deststoretype JKS \
        -srcstorepass "$DEFAULT_PASS" -deststorepass "$DEFAULT_PASS" 2>&1; then
        log_done "Converted to: $out"
    else
        log_fail "Conversion failed"
        exit 1
    fi
}

# ─── MAIN ────────────────────────────────────────────────────

main() {
    local cmd="${1:-help}"; shift || true

    case "$cmd" in
        genkeystore|genkey)         cmd_genkeystore "$@";;
        genkeystore-ecdsa|genkey-ec) cmd_genkeystore_ecdsa "$@";;
        genkeystore-dsa|genkey-dsa) cmd_genkeystore_dsa "$@";;
        keystore-info|ksinfo)       cmd_keystore_info "$@";;
        keystore-list|kslist)       cmd_keystore_list "$@";;
        v1|sign-v1)                 check_java; check_jarsigner; cmd_sign_v1 "$@";;
        v2|sign-v2)                 check_java; cmd_sign_v2 "$@";;
        v3|sign-v3)                 check_java; cmd_sign_v3 "$@";;
        full|sign-full)             check_java; check_jarsigner; cmd_sign_full "$@";;
        batch|batch-sign)           check_java; check_jarsigner; cmd_batch "$@";;
        verify|check)               check_java; check_jarsigner; cmd_verify "$@";;
        verify-deep|verify-full)    check_java; check_jarsigner; cmd_verify_deep "$@";;
        verify-v1|check-v1)         check_java; check_jarsigner; cmd_verify_v1 "$@";;
        verify-v2|check-v2)         check_java; cmd_verify_v2 "$@";;
        zipalign|align)             cmd_zipalign "$@";;
        info|certinfo)              check_java; check_jarsigner; cmd_info "$@";;
        hash|digest)                cmd_hash "$@";;
        cert-info|cert)             cmd_cert_info "$@";;
        convert|pfx2jks)            cmd_convert "$@";;
        help|-h|--help)             show_help;;
        *) log_err "Unknown: $cmd"; show_help; exit 1;;
    esac
}

main "$@"
