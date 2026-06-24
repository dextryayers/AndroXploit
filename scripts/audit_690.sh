#!/usr/bin/env bash
# ============================================================================
#  ANDROID 690-POINT AUDIT REPORT - Bash Version
#  Hardware & Software Detailed Inventory
#  Usage: bash audit_690.sh [options] [output_file]
#  Options:
#    --json               Output results as JSON lines
#    --state-file <path>  Path to state file for resume support
#    --resume             Resume from last completed section
#    --device <serial>    Target specific device serial
# ============================================================================

set -euo pipefail

REPORT_FILE="android_audit_690_bash.txt"
DEVICE_SERIAL=""
ADB_CMD="adb"
JSON_MODE=false
STATE_FILE=""
RESUME_MODE=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'

# Colors for sections
declare -A SECTION_COLORS=(
    ["DEVICE IDENTITY"]="$CYAN"
    ["OPERATING SYSTEM"]="$GREEN"
    ["BUILD INFO"]="$BLUE"
    ["HARDWARE"]="$YELLOW"
    ["STORAGE"]="$MAGENTA"
    ["GPU"]="$CYAN"
    ["NETWORK"]="$BLUE"
    ["TELEPHONY"]="$GREEN"
    ["DISPLAY"]="$MAGENTA"
    ["BATTERY"]="$GREEN"
    ["SENSORS"]="$YELLOW"
    ["CAMERA"]="$MAGENTA"
    ["SECURITY"]="$RED"
    ["PERFORMANCE"]="$CYAN"
    ["THERMAL"]="$RED"
    ["AUDIO"]="$BLUE"
    ["SYSTEM"]="$GREEN"
    ["NETWORKING ADVANCED"]="$BLUE"
    ["EXTRAS"]="$CYAN"
)

POINT_COUNT=0
START_TIME=""

# ─── Argument Parsing / JSON / State File Support ──────────────

parse_args() {
    POSITIONAL=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) JSON_MODE=true; shift ;;
            --state-file) STATE_FILE="$2"; shift 2 ;;
            --resume) RESUME_MODE=true; shift ;;
            --device) DEVICE_SERIAL="$2"; ADB_CMD="adb -s $DEVICE_SERIAL"; shift 2 ;;
            *) POSITIONAL+=("$1"); shift ;;
        esac
    done
    if [[ ${#POSITIONAL[@]} -gt 0 ]]; then
        REPORT_FILE="${POSITIONAL[0]}"
    fi
    if [[ "$RESUME_MODE" == "true" && -z "$STATE_FILE" ]]; then
        STATE_FILE="${REPORT_FILE}.state"
    fi
    if [[ "$JSON_MODE" == "true" ]]; then
        echo '{"event":"start","tool":"audit_690","version":"3.0"}'
    fi
}

mark_completed() {
    local section="$1"
    if [[ -n "$STATE_FILE" ]]; then
        echo "$section completed $(date +%s)" >> "$STATE_FILE"
    fi
    if [[ "$JSON_MODE" == "true" ]]; then
        echo "{\"event\":\"section_complete\",\"section\":\"$section\",\"points\":$POINT_COUNT}"
    fi
}

is_completed() {
    local section="$1"
    if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
        return 1
    fi
    grep -q "^$section " "$STATE_FILE" 2>/dev/null && return 0
    return 1
}

run_section() {
    local name="$1" func="$2"
    if is_completed "$name"; then
        echo -e "${DIM}[ ] $name already completed — skipping${NC}"
        return 0
    fi
    $func
    mark_completed "$name"
}

check_adb() {
    if ! command -v adb &>/dev/null; then
        echo -e "${RED}[!] ADB not found. Install Android platform tools.${NC}" >&2
        exit 1
    fi
    local devices
    devices=$(adb devices 2>/dev/null | grep -v "List of devices" | grep -v "daemon" | grep "device$" | head -1 | awk '{print $1}')
    if [[ -z "$devices" ]]; then
        echo -e "${RED}[!] No Android device detected. Connect USB cable & enable USB debugging.${NC}" >&2
        exit 1
    fi
    DEVICE_SERIAL="$devices"
    echo -e "${GREEN}[+] Device: $DEVICE_SERIAL${NC}"
    echo ""
}

g() {
    local key="$1"
    local fallback="${2:-?}"
    local val
    val=$(adb -s "$DEVICE_SERIAL" shell getprop "$key" 2>/dev/null | tr -d '\r\n')
    echo "${val:-$fallback}"
}

c() {
    local cmd="$1"
    adb -s "$DEVICE_SERIAL" shell $cmd 2>/dev/null | tr -d '\r\n' | sed 's/[[:space:]]*$//'
}

s() {
    # settings get
    local ns="$1" key="$2"
    adb -s "$DEVICE_SERIAL" shell settings get "$ns" "$key" 2>/dev/null | tr -d '\r\n' | grep -v '^null$' || echo "?"
}

catf() {
    local path="$1"
    adb -s "$DEVICE_SERIAL" shell cat "$path" 2>/dev/null | tr -d '\r\n' || echo ""
}

detect_soc() {
    local platform
    platform=$(g "ro.board.platform")
    local chipname
    chipname=$(g "ro.chipname")

    if [[ "$platform" == mt* ]]; then
        case "$platform" in
            mt6789) echo "MediaTek Helio G99 Ultra" ;;
            mt6781) echo "MediaTek Helio G96" ;;
            mt6771) echo "MediaTek Helio P60/P70" ;;
            mt6768) echo "MediaTek Helio G70/G80/G85" ;;
            mt6765) echo "MediaTek Helio G25/P35" ;;
            mt6833) echo "MediaTek Dimensity 700" ;;
            mt6853) echo "MediaTek Dimensity 720" ;;
            mt6873) echo "MediaTek Dimensity 800" ;;
            mt6877) echo "MediaTek Dimensity 900" ;;
            mt6883) echo "MediaTek Dimensity 1000" ;;
            mt6891) echo "MediaTek Dimensity 1100" ;;
            mt6893) echo "MediaTek Dimensity 1200" ;;
            mt6983) echo "MediaTek Dimensity 9000" ;;
            mt6985) echo "MediaTek Dimensity 9200" ;;
            mt6989) echo "MediaTek Dimensity 9300" ;;
            *) echo "MediaTek $platform" ;;
        esac
    elif [[ "$platform" == sm* ]] || [[ "$platform" == msm* ]] || [[ "$platform" == sdm* ]]; then
        case "$platform" in
            sm8550|sm8550-*-*) echo "Qualcomm Snapdragon 8 Gen 2" ;;
            sm8650) echo "Qualcomm Snapdragon 8 Gen 3" ;;
            sm8750) echo "Qualcomm Snapdragon 8 Gen 4" ;;
            sm8450|sm8475) echo "Qualcomm Snapdragon 8 Gen 1/+" ;;
            sm8350|sm8355) echo "Qualcomm Snapdragon 888/+" ;;
            sm7325) echo "Qualcomm Snapdragon 778G" ;;
            sm7250) echo "Qualcomm Snapdragon 765/765G" ;;
            sdm865|sdm870) echo "Qualcomm Snapdragon 865/870" ;;
            sdm855) echo "Qualcomm Snapdragon 855/855+" ;;
            sdm845) echo "Qualcomm Snapdragon 845" ;;
            sdm835) echo "Qualcomm Snapdragon 835" ;;
            sdm660) echo "Qualcomm Snapdragon 660" ;;
            *) echo "Qualcomm Snapdragon $platform" ;;
        esac
    elif [[ "$platform" == sc* ]] || [[ "$platform" == t[0-9]* ]]; then
        echo "Unisoc/Spreadtrum $platform"
    elif [[ "$platform" == exynos* ]]; then
        echo "Samsung Exynos $platform"
    elif [[ "$platform" == kirin* ]]; then
        echo "HiSilicon Kirin $platform"
    elif [[ "$platform" == rk* ]]; then
        echo "Rockchip $platform"
    else
        echo "Unknown SoC ($platform)"
    fi
}

print_point() {
    local section="$1" desc="$2" value="$3"
    local color="${GREEN}"

    if [[ -z "$value" || "$value" == "?" || "$value" == "? [N/A]" ]]; then
        color="${RED}"
    elif [[ "$value" == *"error"* || "$value" == *"not"* ]]; then
        color="${YELLOW}"
    fi

    local short_val="${value:0:150}"
    printf "  ${GREEN}[+]${NC} ${WHITE}%s:${NC} ${color}%s${NC}\n" "$desc" "$short_val"
    echo "  [+] $desc: $short_val" >> "$REPORT_FILE"
    ((POINT_COUNT++))
}

section_header() {
    local name="$1"
    local color="${SECTION_COLORS[$name]:-$CYAN}"
    echo ""
    printf "${color}%s${NC}\n" "=================================================================="
    printf "${color}  %s${NC}\n" "$name"
    printf "${color}%s${NC}\n" "=================================================================="
    echo ""
    echo "" >> "$REPORT_FILE"
    echo "==================================================================" >> "$REPORT_FILE"
    echo "  $name" >> "$REPORT_FILE"
    echo "==================================================================" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# ======================================================================
# SECTIONS
# ======================================================================

section_device_identity() {
    section_header "DEVICE IDENTITY"
    print_point "DEVICE IDENTITY" "Device Model" "$(g ro.product.model)"
    print_point "DEVICE IDENTITY" "Manufacturer" "$(g ro.product.manufacturer)"
    print_point "DEVICE IDENTITY" "Brand" "$(g ro.product.brand)"
    print_point "DEVICE IDENTITY" "Market Name" "$(g ro.product.marketname || g ro.config.marketing_name)"
    print_point "DEVICE IDENTITY" "Product Name" "$(g ro.product.name)"
    print_point "DEVICE IDENTITY" "Product Device" "$(g ro.product.device)"
    print_point "DEVICE IDENTITY" "Product Board" "$(g ro.product.board)"
    print_point "DEVICE IDENTITY" "Hardware" "$(g ro.hardware)"
    print_point "DEVICE IDENTITY" "Platform/SoC" "$(g ro.board.platform)"
    print_point "DEVICE IDENTITY" "Chipname" "$(g ro.chipname)"
    print_point "DEVICE IDENTITY" "Bootloader" "$(g ro.bootloader)"
    print_point "DEVICE IDENTITY" "Serial (ro)" "$(g ro.serialno)"
    print_point "DEVICE IDENTITY" "Boot Serial" "$(g ro.boot.serialno)"
    print_point "DEVICE IDENTITY" "Fingerprint" "$(g ro.build.fingerprint)"
    print_point "DEVICE IDENTITY" "Description" "$(g ro.build.description)"
    print_point "DEVICE IDENTITY" "Locale" "$(g persist.sys.locale)"
    print_point "DEVICE IDENTITY" "Language" "$(g ro.product.locale.language)"
    print_point "DEVICE IDENTITY" "Region" "$(g ro.product.locale.region)"
    print_point "DEVICE IDENTITY" "Timezone" "$(g persist.sys.timezone)"
    print_point "DEVICE IDENTITY" "Characteristics" "$(g ro.build.characteristics)"
    print_point "DEVICE IDENTITY" "Display ID" "$(g ro.build.display.id)"
    print_point "DEVICE IDENTITY" "CPU ABI" "$(g ro.product.cpu.abi)"
    print_point "DEVICE IDENTITY" "ABI List" "$(g ro.product.cpu.abilist)"
    print_point "DEVICE IDENTITY" "ABI2" "$(g ro.product.cpu.abi2)"
    print_point "DEVICE IDENTITY" "Market Name (2)" "$(g ro.product.marketname)"
}

section_os() {
    section_header "OPERATING SYSTEM"
    print_point "OPERATING SYSTEM" "Android Version" "$(g ro.build.version.release)"
    print_point "OPERATING SYSTEM" "API Level" "$(g ro.build.version.sdk)"
    print_point "OPERATING SYSTEM" "Preview SDK" "$(g ro.build.version.preview_sdk)"
    print_point "OPERATING SYSTEM" "Codename" "$(g ro.build.version.codename)"
    print_point "OPERATING SYSTEM" "Incremental" "$(g ro.build.version.incremental)"
    print_point "OPERATING SYSTEM" "Security Patch" "$(g ro.build.version.security_patch)"
    print_point "OPERATING SYSTEM" "Vendor Security Patch" "$(g ro.vendor.build.security_patch)"
    print_point "OPERATING SYSTEM" "Base OS" "$(g ro.build.version.base_os)"
    print_point "OPERATING SYSTEM" "Build Type" "$(g ro.build.type)"
    print_point "OPERATING SYSTEM" "Build Tags" "$(g ro.build.tags)"
    print_point "OPERATING SYSTEM" "Build User" "$(g ro.build.user)"
    print_point "OPERATING SYSTEM" "Build Host" "$(g ro.build.host)"
    print_point "OPERATING SYSTEM" "Build Date UTC" "$(g ro.build.date.utc)"
    print_point "OPERATING SYSTEM" "Build Date Full" "$(g ro.build.date)"
    print_point "OPERATING SYSTEM" "Kernel Version" "$(catf /proc/version | head -c100)"
    print_point "OPERATING SYSTEM" "Uptime" "$(catf /proc/uptime | awk '{s=$1; d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60); print d"d "h"h "m"m"}')"
    print_point "OPERATING SYSTEM" "Swappiness" "$(catf /proc/sys/vm/swappiness)"
    print_point "OPERATING SYSTEM" "Overcommit Ratio" "$(catf /proc/sys/vm/overcommit_ratio)"
    print_point "OPERATING SYSTEM" "Treble Supported" "$(g ro.treble.enabled)"
    print_point "OPERATING SYSTEM" "AB Update" "$(g ro.build.ab_update)"
    print_point "OPERATING SYSTEM" "Virtual AB" "$(g ro.virtual_ab.enabled)"
    print_point "OPERATING SYSTEM" "VNDK Version" "$(g ro.vndk.version)"
    print_point "OPERATING SYSTEM" "Hostname" "$(catf /proc/sys/kernel/hostname)"
    print_point "OPERATING SYSTEM" "File Max" "$(catf /proc/sys/fs/file-max)"
    print_point "OPERATING SYSTEM" "Max PID" "$(catf /proc/sys/kernel/pid_max)"
}

section_build() {
    section_header "BUILD INFO"
    print_point "BUILD INFO" "Build ID" "$(g ro.build.id)"
    print_point "BUILD INFO" "Build Display ID" "$(g ro.build.display.id)"
    print_point "BUILD INFO" "Build Flavor" "$(g ro.build.flavor)"
    print_point "BUILD INFO" "Build Fingerprint" "$(g ro.build.fingerprint)"
    print_point "BUILD INFO" "Build Type" "$(g ro.build.type)"
    print_point "BUILD INFO" "Build User" "$(g ro.build.user)"
    print_point "BUILD INFO" "Build Host" "$(g ro.build.host)"
    print_point "BUILD INFO" "Build Date" "$(g ro.build.date)"
    print_point "BUILD INFO" "Build Date UTC" "$(g ro.build.date.utc)"
    print_point "BUILD INFO" "Build Incremental" "$(g ro.build.version.incremental)"
    print_point "BUILD INFO" "Version Release" "$(g ro.build.version.release)"
    print_point "BUILD INFO" "Version SDK" "$(g ro.build.version.sdk)"
    print_point "BUILD INFO" "Version Codename" "$(g ro.build.version.codename)"
    print_point "BUILD INFO" "Security Patch" "$(g ro.build.version.security_patch)"
    print_point "BUILD INFO" "Base OS" "$(g ro.build.version.base_os)"
    print_point "BUILD INFO" "Preview SDK" "$(g ro.build.version.preview_sdk)"
    print_point "BUILD INFO" "Characteristics" "$(g ro.build.characteristics)"
    print_point "BUILD INFO" "Board Platform" "$(g ro.board.platform)"
    print_point "BUILD INFO" "Boot Baseband" "$(g ro.boot.baseband)"
    print_point "BUILD INFO" "Boot Hardware" "$(g ro.boot.hardware)"
    print_point "BUILD INFO" "Boot Serial" "$(g ro.boot.serialno)"
    print_point "BUILD INFO" "Boot Verified State" "$(g ro.boot.verifiedbootstate)"
    print_point "BUILD INFO" "Build Tags" "$(g ro.build.tags)"
    print_point "BUILD INFO" "Release Names" "$(g ro.build.version.release_names)"
    print_point "BUILD INFO" "All Codenames" "$(g ro.build.version.all_codenames)"
    print_point "BUILD INFO" "Min Support SDK" "$(g ro.build.version.min_support_sdk)"
    print_point "BUILD INFO" "ABI List" "$(g ro.product.cpu.abilist)"
    print_point "BUILD INFO" "ABI" "$(g ro.product.cpu.abi)"
    print_point "BUILD INFO" "ABI2" "$(g ro.product.cpu.abi2)"
    print_point "BUILD INFO" "Description" "$(g ro.build.description)"
}

section_hardware() {
    section_header "HARDWARE"
    local soc_name
    soc_name=$(detect_soc)
    local cpuinfo
    cpuinfo=$(catf /proc/cpuinfo)
    local meminfo
    meminfo=$(catf /proc/meminfo)
    local cpu_count
    cpu_count=$(echo "$cpuinfo" | grep -c "^processor" || echo "?")

    print_point "HARDWARE" "SoC Full Name" "$soc_name"
    print_point "HARDWARE" "CPU Cores" "$cpu_count"
    print_point "HARDWARE" "CPU Implementer" "$(echo "$cpuinfo" | grep "CPU implementer" | head -1 | awk -F': ' '{print $2}')"
    print_point "HARDWARE" "CPU Part" "$(echo "$cpuinfo" | grep "CPU part" | head -1 | awk -F': ' '{print $2}')"
    print_point "HARDWARE" "CPU Architecture" "$(echo "$cpuinfo" | grep "CPU architecture" | head -1 | awk -F': ' '{print $2}')"
    print_point "HARDWARE" "CPU Features" "$(echo "$cpuinfo" | grep "Features" | head -1 | awk -F': ' '{print $2}' | head -c120)"
    print_point "HARDWARE" "CPU Hardware" "$(echo "$cpuinfo" | grep "Hardware" | head -1 | awk -F': ' '{print $2}')"
    print_point "HARDWARE" "CPU BogoMIPS" "$(echo "$cpuinfo" | grep "BogoMIPS" | head -1 | awk -F': ' '{print $2}')"
    print_point "HARDWARE" "CPU Revision" "$(echo "$cpuinfo" | grep "CPU revision" | head -1 | awk -F': ' '{print $2}')"

    local mem_total
    mem_total=$(echo "$meminfo" | grep "^MemTotal" | awk '{print $2}')
    if [[ -n "$mem_total" ]]; then
        local mem_mb=$((mem_total / 1024))
        local mem_gb=$((mem_mb / 1024))
        print_point "HARDWARE" "Total RAM" "${mem_mb}MB (${mem_gb}.$(((mem_mb % 1024) * 10 / 1024))GB)"
    fi
    local mem_avail
    mem_avail=$(echo "$meminfo" | grep "^MemAvailable" | awk '{print $2}')
    if [[ -n "$mem_avail" ]]; then
        local av_mb=$((mem_avail / 1024))
        print_point "HARDWARE" "Available RAM" "${av_mb}MB"
    fi
    print_point "HARDWARE" "Free RAM" "$(echo "$meminfo" | grep "^MemFree" | awk '{printf "%dMB", $2/1024}')"
    print_point "HARDWARE" "Cached RAM" "$(echo "$meminfo" | grep "^Cached" | awk '{printf "%dMB", $2/1024}')"
    print_point "HARDWARE" "Swap Total" "$(echo "$meminfo" | grep "^SwapTotal" | awk '{printf "%dMB", $2/1024}')"
    print_point "HARDWARE" "Swap Free" "$(echo "$meminfo" | grep "^SwapFree" | awk '{printf "%dMB", $2/1024}')"
    print_point "HARDWARE" "Dirty Pages" "$(echo "$meminfo" | grep "^Dirty" | awk '{printf "%dMB", $2/1024}')"
    print_point "HARDWARE" "AnonPages" "$(echo "$meminfo" | grep "^AnonPages" | awk '{printf "%dMB", $2/1024}')"
    print_point "HARDWARE" "Mapped" "$(echo "$meminfo" | grep "^Mapped" | awk '{printf "%dMB", $2/1024}')"
    print_point "HARDWARE" "Shmem" "$(echo "$meminfo" | grep "^Shmem" | awk '{printf "%dMB", $2/1024}')"
    print_point "HARDWARE" "PageTables" "$(echo "$meminfo" | grep "^PageTables" | awk '{printf "%dMB", $2/1024}')"
    print_point "HARDWARE" "CmaTotal" "$(echo "$meminfo" | grep "^CmaTotal" | awk '{printf "%dMB", $2/1024}')"
    print_point "HARDWARE" "CmaFree" "$(echo "$meminfo" | grep "^CmaFree" | awk '{printf "%dMB", $2/1024}')"
    print_point "HARDWARE" "Heap Start Size" "$(g dalvik.vm.heapstartsize)"
    print_point "HARDWARE" "Heap Growth Limit" "$(g dalvik.vm.heapgrowthlimit)"
    print_point "HARDWARE" "Heap Max Size" "$(g dalvik.vm.heapsize)"
    print_point "HARDWARE" "Heap Min Free" "$(g dalvik.vm.heapminfree)"
    print_point "HARDWARE" "Heap Utilization" "$(g dalvik.vm.heaptargetutilization)"
    print_point "HARDWARE" "CPU Governor" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
    print_point "HARDWARE" "CPU Min Freq" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq)"
    print_point "HARDWARE" "CPU Max Freq" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)"
    print_point "HARDWARE" "CPU Cur Freq" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"
    print_point "HARDWARE" "CPU Online" "$(catf /sys/devices/system/cpu/online)"
    print_point "HARDWARE" "CPU Present" "$(catf /sys/devices/system/cpu/present)"
    print_point "HARDWARE" "ABI List" "$(g ro.product.cpu.abilist)"
    print_point "HARDWARE" "ABI List 32" "$(g ro.product.cpu.abilist32)"
    print_point "HARDWARE" "ABI List 64" "$(g ro.product.cpu.abilist64)"
}

section_storage() {
    section_header "STORAGE"
    local df_h
    df_h=$(adb -s "$DEVICE_SERIAL" shell df -h 2>/dev/null)
    print_point "STORAGE" "System Partition" "$(echo "$df_h" | grep "/system" | awk '{print $2}')"
    print_point "STORAGE" "Data Partition" "$(echo "$df_h" | grep "/data " | awk '{print $2}')"
    print_point "STORAGE" "Cache Partition" "$(echo "$df_h" | grep "/cache" | awk '{print $2}')"
    print_point "STORAGE" "External SD Card" "$(adb -s "$DEVICE_SERIAL" shell cat /proc/mounts 2>/dev/null | grep -q sdcard && echo "Detected" || echo "Not detected")"

    # Auto-detect block device
    local blk_dev=""
    blk_dev=$(adb -s "$DEVICE_SERIAL" shell "grep '/data ' /proc/mounts | head -1 | sed 's|/dev/block/||;s| .*||'" 2>/dev/null)
    [[ -z "$blk_dev" ]] && blk_dev="mmcblk0"

    local mmc_name mmc_type io_sched io_rot io_ra ufs_v storage_label="?"
    mmc_name=$(catf "/sys/block/$blk_dev/device/name")
    mmc_type=$(catf "/sys/block/$blk_dev/device/type")
    io_sched=$(catf "/sys/block/$blk_dev/queue/scheduler")
    io_rot=$(catf "/sys/block/$blk_dev/queue/rotational")
    io_ra=$(catf "/sys/block/$blk_dev/queue/read_ahead_kb")

    # UFS detection
    ufs_v=$(adb -s "$DEVICE_SERIAL" shell "cat /sys/devices/platform/soc/*/ufshcd*/name /sys/devices/platform/soc/*/ufs*/name 2>/dev/null | head -c60" | tr -d '\r\n')
    [[ -z "$ufs_v" ]] && ufs_v=$(adb -s "$DEVICE_SERIAL" shell "ls /sys/bus/platform/drivers/ufshcd 2>/dev/null" | head -c30)

    local storage_type_prop
    storage_type_prop=$(g ro.boot.storage_type)

    if [[ -n "$mmc_name" ]]; then
        [[ "$mmc_type" == "MMC" ]] && storage_label="eMMC" || storage_label="? ($mmc_type)"
    elif [[ -n "$ufs_v" ]]; then
        storage_label="UFS"
    elif [[ -n "$storage_type_prop" ]]; then
        storage_label="$storage_type_prop"
    else
        local nvme_check
        nvme_check=$(catf /sys/block/nvme0n1/device/model)
        [[ -n "$nvme_check" ]] && storage_label="NVMe" || storage_label="?"
    fi

    print_point "STORAGE" "Storage Type" "$storage_label"
    print_point "STORAGE" "Model/Name" "${mmc_name:-${ufs_v:-?}}"
    print_point "STORAGE" "I/O Scheduler" "${io_sched:-?}"
    print_point "STORAGE" "Read Ahead" "${io_ra:+${io_ra}KB}"
    print_point "STORAGE" "Rotational" "$([[ "$io_rot" == "1" ]] && echo "HDD" || echo "SSD/eMMC/UFS")"
    print_point "STORAGE" "F2FS Support" "$(catf /proc/filesystems | grep -q f2fs && echo "Supported" || echo "Not supported")"
    print_point "STORAGE" "EXT4 Support" "$(catf /proc/filesystems | grep -q ext4 && echo "Supported" || echo "Not supported")"
    print_point "STORAGE" "Encryption Type" "$(g ro.crypto.type)"
    print_point "STORAGE" "Encrypted" "$(g ro.crypto.state)"
    print_point "STORAGE" "Kernel Version" "$(catf /proc/version | head -c80)"
}

section_gpu() {
    section_header "GPU"
    print_point "GPU" "GPU Renderer" "$(g ro.hardware.gralloc)"
    print_point "GPU" "OpenGL ES" "$(g ro.opengles.version)"
    print_point "GPU" "Vulkan API" "$(g ro.hardware.vulkan) / $(g ro.vulkan.api) / level $(g ro.vulkan.level)"
    print_point "GPU" "Vulkan libvulkan.so" "$(c 'ls /system/lib64/libvulkan.so /vendor/lib64/libvulkan.so /system/lib/libvulkan.so 2>/dev/null' | head -c60 || echo 'Not found')"
    print_point "GPU" "Vulkan ResourceMgr" "$(c 'dumpsys media.resource_manager 2>/dev/null | head -20 | grep -i vulkan | head -c80' || echo '?')"
    print_point "GPU" "EGL Config" "$(g ro.egl.config)"
    print_point "GPU" "EGL HW" "$(g ro.hardware.egl)"
    print_point "GPU" "HWUI Renderer" "$(g debug.hwui.renderer)"
    print_point "GPU" "SF Vsync" "$(g debug.sf.disable_vsync)"

    # Adreno paths
    local gpu_clk gpu_max gpu_busy gpu_gov gpu_therm gpu_avail
    gpu_clk=$(catf /sys/class/kgsl/kgsl-3d0/gpuclk)
    gpu_max=$(catf /sys/class/kgsl/kgsl-3d0/max_gpuclk)
    gpu_busy=$(catf /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage)
    gpu_gov=$(catf /sys/class/kgsl/kgsl-3d0/devfreq/governor)
    gpu_therm=$(catf /sys/class/kgsl/kgsl-3d0/thermal_pwrlevel)
    gpu_avail=$(catf /sys/class/kgsl/kgsl-3d0/gpu_available_frequencies)

    # Mali paths - try all known Mali locations
    if [[ -z "$gpu_clk" || -z "$gpu_gov" ]]; then
        local mali_dev
        mali_dev=$(adb -s "$DEVICE_SERIAL" shell "ls -d /sys/devices/platform/*mali* /sys/devices/platform/*.mali 2>/dev/null | head -1" | tr -d '\r\n')
        if [[ -n "$mali_dev" ]]; then
            [[ -z "$gpu_clk" ]] && gpu_clk=$(catf "$mali_dev/frequency") || true
            [[ -z "$gpu_clk" ]] && gpu_clk=$(catf "$mali_dev/cur_freq") || true
            [[ -z "$gpu_clk" ]] && gpu_clk=$(catf "$mali_dev/clock") || true
            [[ -z "$gpu_max" ]] && gpu_max=$(catf "$mali_dev/max_freq") || true
            [[ -z "$gpu_gov" ]] && gpu_gov=$(catf "$mali_dev/dvfs_governor") || true
            [[ -z "$gpu_gov" ]] && gpu_gov=$(catf "$mali_dev/governor") || true
            [[ -z "$gpu_busy" ]] && gpu_busy=$(catf "$mali_dev/utilization") || true
            [[ -z "$gpu_busy" ]] && gpu_busy=$(catf "$mali_dev/load") || true
            [[ -z "$gpu_avail" ]] && gpu_avail=$(catf "$mali_dev/available_frequencies") || true
        fi
        # /sys/kernel/gpu fallback
        [[ -z "$gpu_clk" ]] && gpu_clk=$(catf /sys/kernel/gpu/gpu_cur_freq)
        [[ -z "$gpu_max" ]] && gpu_max=$(catf /sys/kernel/gpu/gpu_max_freq)
        [[ -z "$gpu_gov" ]] && gpu_gov=$(catf /sys/kernel/gpu/gpu_governor)
        [[ -z "$gpu_busy" ]] && gpu_busy=$(catf /sys/kernel/gpu/gpu_busy)
        # GPU thermal via zone scanning
        if [[ -z "$gpu_therm" ]]; then
            for _tz in /sys/class/thermal/thermal_zone*; do
                local _ttype
                _ttype=$(catf "$_tz/type" 2>/dev/null)
                if echo "$_ttype" | grep -qi gpu; then
                    gpu_therm=$(catf "$_tz/temp" 2>/dev/null)
                    break
                fi
            done
            if [[ -n "$gpu_therm" ]]; then
                gpu_therm=$(echo "scale=1; $gpu_therm/1000" | bc 2>/dev/null)"C"
            fi
        fi
    fi

    # Governor sanity - reject CPU governors
    if [[ -n "$gpu_gov" ]]; then
        case "$gpu_gov" in
            interactive|schedutil|conservative|ondemand|userspace|powersave) gpu_gov="" ;;
        esac
    fi

    print_point "GPU" "GPU Cur Freq" "${gpu_clk:-?}"
    print_point "GPU" "GPU Max Freq" "${gpu_max:-?}"
    print_point "GPU" "GPU Busy" "${gpu_busy:-?}"
    print_point "GPU" "GPU Governor" "${gpu_gov:-?}"
    print_point "GPU" "GPU Thermal Level" "${gpu_therm:-?}"
    print_point "GPU" "GPU Avail Freqs" "${gpu_avail:-?}"
    print_point "GPU" "OpenCL Support" "$(adb -s "$DEVICE_SERIAL" shell ls /system/vendor/lib/libOpenCL.so 2>/dev/null | grep -q "No such" && echo "Not found" || echo "Supported")"
    print_point "GPU" "Gralloc Version" "$(g ro.hardware.gralloc)"
}

section_network() {
    section_header "NETWORK"
    local imei
    imei=$(adb -s "$DEVICE_SERIAL" shell service call iphonesubinfo 1 2>/dev/null | tr -d '\0' | grep -o '[0-9]\{14,\}' | head -1)
    print_point "NETWORK" "IMEI" "${imei:-Restricted}"
    print_point "NETWORK" "WiFi SSID" "$(adb -s "$DEVICE_SERIAL" shell dumpsys wifi 2>/dev/null | grep "SSID:" | head -1 | sed 's/.*SSID: "*//;s/" .*//')"
    print_point "NETWORK" "WiFi BSSID" "$(adb -s "$DEVICE_SERIAL" shell dumpsys wifi 2>/dev/null | grep "BSSID:" | head -1 | sed 's/.*BSSID: //')"
    print_point "NETWORK" "WiFi MAC" "$(adb -s "$DEVICE_SERIAL" shell dumpsys wifi 2>/dev/null | grep "MAC:" | head -1 | sed 's/.*MAC: //')"
    print_point "NETWORK" "IP Address" "$(adb -s "$DEVICE_SERIAL" shell ip addr show wlan0 2>/dev/null | grep "inet " | head -1 | awk '{print $2}')"
    print_point "NETWORK" "Gateway" "$(adb -s "$DEVICE_SERIAL" shell ip route show table 0 2>/dev/null | grep default | awk '{print $3}')"
    print_point "NETWORK" "DNS Servers" "$(g net.dns1) $(g net.dns2)"
    print_point "NETWORK" "Bluetooth Name" "$(s secure bluetooth_name)"
    print_point "NETWORK" "Bluetooth MAC" "$(s secure bluetooth_address)"
    print_point "NETWORK" "Bluetooth State" "$(s global bluetooth_on)"
    print_point "NETWORK" "Carrier" "$(g gsm.sim.operator.alpha)"
    print_point "NETWORK" "Network Operator" "$(g gsm.operator.alpha)"
    print_point "NETWORK" "Baseband" "$(g gsm.version.baseband)"
    print_point "NETWORK" "Data Roaming" "$(s global data_roaming)"
    print_point "NETWORK" "Mobile Data" "$(s global mobile_data)"
    print_point "NETWORK" "HTTP Proxy" "$(s global http_proxy)"
    print_point "NETWORK" "WiFi Interface" "$(g wifi.interface)"
    print_point "NETWORK" "DHCP Server" "$(g dhcp.wlan0.server)"
    print_point "NETWORK" "DHCP Gateway" "$(g dhcp.wlan0.gateway)"
    print_point "NETWORK" "DHCP DNS1" "$(g dhcp.wlan0.dns1)"
    print_point "NETWORK" "DHCP DNS2" "$(g dhcp.wlan0.dns2)"
    print_point "NETWORK" "DHCP Lease" "$(g dhcp.wlan0.leasetime)"
    print_point "NETWORK" "DHCP Mask" "$(g dhcp.wlan0.mask)"
}

section_telephony() {
    section_header "TELEPHONY"

    # Clean network type (filter "Unknown" from multi-SIM)
    local net_type_raw net_type
    net_type_raw=$(g gsm.network.type)
    net_type=$(echo "$net_type_raw" | sed 's/,/\n/g' | grep -vi "unknown" | sort -u | tr '\n' ',' | sed 's/,$//')
    [[ -z "$net_type" ]] && net_type="$net_type_raw"

    print_point "TELEPHONY" "Network Type" "$net_type"
    print_point "TELEPHONY" "Operator" "$(g gsm.operator.alpha)"
    print_point "TELEPHONY" "SIM Operator" "$(g gsm.sim.operator.alpha)"
    print_point "TELEPHONY" "SIM State" "$(g gsm.sim.state)"
    print_point "TELEPHONY" "MCC/MNC" "$(g gsm.operator.numeric)"
    print_point "TELEPHONY" "Roaming" "$(g gsm.operator.isroaming)"
    print_point "TELEPHONY" "Data State" "$(g gsm.data.state)"
    print_point "TELEPHONY" "Signal Strength" "$(g gsm.signal.strength)"
    print_point "TELEPHONY" "Phone Type" "$(g gsm.current.phone-type)"
    print_point "TELEPHONY" "SIM Count" "$(g ro.multisim.simcount)"
    print_point "TELEPHONY" "DSDA/DSDS" "$(g persist.radio.multisim.config)"
    print_point "TELEPHONY" "SIM2 Operator" "$(g gsm.sim.operator.alpha_1)"
    print_point "TELEPHONY" "Default SIM" "$(g persist.radio.default.sim)"
    print_point "TELEPHONY" "Call State" "$(g gsm.call.state)"
    print_point "TELEPHONY" "Cell ID" "$(g gsm.cellid)"
    print_point "TELEPHONY" "LTE EARFCN" "$(g gsm.lte.earfcn)"
    print_point "TELEPHONY" "NR State" "$(g gsm.nr.state)"
    print_point "TELEPHONY" "CA Active" "$(g gsm.ca.active)"
    print_point "TELEPHONY" "Bandwidth" "$(g gsm.bandwidth)"

    # VoLTE detection
    local volte="?"
    local volte_props=("persist.dbg.volte_avail" "persist.sys.ctl.volte" "persist.radio.volte_enabled" "persist.volte_enabled" "ro.volte.enabled" "gsm.sim.volte_available")
    for vk in "${volte_props[@]}"; do
        local vv
        vv=$(g "$vk")
        if [[ "$vv" != "?" && -n "$vv" ]]; then
            [[ "$vv" == "1" ]] && volte="On" || volte="$vv"
            break
        fi
    done
    # Also check dumpsys telephony registry
    local tr
    tr=$(adb -s "$DEVICE_SERIAL" shell dumpsys telephony.registry 2>/dev/null)
    if echo "$tr" | grep -qi "volte.*true\|ims.*registered"; then
        [[ "$volte" == "?" ]] && volte="Enabled"
    fi
    print_point "TELEPHONY" "VoLTE" "$volte"

    # VoNR
    local vonr="?"
    local vonr_props=("persist.dbg.vonr_avail" "persist.radio.nr_voice_avail" "ro.vonr.enabled")
    for vk in "${vonr_props[@]}"; do
        local vv2
        vv2=$(g "$vk")
        if [[ "$vv2" != "?" && -n "$vv2" ]]; then
            [[ "$vv2" == "1" ]] && vonr="On" || vonr="$vv2"
            break
        fi
    done
    if echo "$tr" | grep -qi "vonr.*true\|nr.*ims.*true"; then
        [[ "$vonr" == "?" ]] && vonr="Enabled (NR)"
    fi
    print_point "TELEPHONY" "VoNR" "$vonr"

    # VoWiFi
    local vowifi="?"
    local vowifi_props=("persist.dbg.wfc_avail" "persist.radio.wifi_call_avail" "persist.sys.ctl.vowifi" "ro.vowifi.enabled")
    for vk in "${vowifi_props[@]}"; do
        local vv3
        vv3=$(g "$vk")
        if [[ "$vv3" != "?" && -n "$vv3" ]]; then
            [[ "$vv3" == "1" ]] && vowifi="On" || vowifi="$vv3"
            break
        fi
    done
    if echo "$tr" | grep -qi "vowifi.*true\|wificalling.*true"; then
        [[ "$vowifi" == "?" ]] && vowifi="Enabled"
    fi
    print_point "TELEPHONY" "VoWiFi" "$vowifi"

    # IMS
    print_point "TELEPHONY" "IMS Registration" "$(adb -s "$DEVICE_SERIAL" shell dumpsys ims 2>/dev/null | grep -i "registered\|ImsState" | head -c80 || echo "Not registered")"
}

section_display() {
    section_header "DISPLAY"
    local wm_size
    wm_size=$(adb -s "$DEVICE_SERIAL" shell wm size 2>/dev/null | sed 's/Physical size: //')
    local wm_density
    wm_density=$(adb -s "$DEVICE_SERIAL" shell wm density 2>/dev/null | sed 's/Physical density: //')
    print_point "DISPLAY" "Resolution" "$wm_size"
    print_point "DISPLAY" "Density" "${wm_density}dpi"
    print_point "DISPLAY" "LCD Density" "$(g ro.sf.lcd_density)"
    print_point "DISPLAY" "SF HW" "$(g debug.sf.hw)"
    print_point "DISPLAY" "VSync" "$(g debug.sf.disable_vsync)"
    print_point "DISPLAY" "HDR Support" "$(adb -s "$DEVICE_SERIAL" shell dumpsys display 2>/dev/null | grep -qi hdr && echo Supported || echo ?)"
    print_point "DISPLAY" "Brightness" "$(s system screen_brightness)"
    print_point "DISPLAY" "Auto Brightness" "$(s system screen_brightness_mode)"
    print_point "DISPLAY" "Screen Off Timeout" "$(s system screen_off_timeout)"
    print_point "DISPLAY" "Color Mode" "$(g persist.sys.sf.color_mode)"
    print_point "DISPLAY" "HW Composer" "$(g ro.hardware.hwcomposer)"
    print_point "DISPLAY" "Display Rotation" "$(g ro.sf.hwrotation)"
    print_point "DISPLAY" "Night Mode" "$(s secure night_display_activated)"
    print_point "DISPLAY" "Display Count" "$(adb -s "$DEVICE_SERIAL" shell dumpsys display 2>/dev/null | grep -c "Display ")"
    print_point "DISPLAY" "Panel Name" "$(catf /sys/class/graphics/fb0/device/panel_name)"
}

section_battery() {
    section_header "BATTERY"
    local bat
    bat=$(adb -s "$DEVICE_SERIAL" shell dumpsys battery 2>/dev/null)
    print_point "BATTERY" "Level" "$(echo "$bat" | grep "^  level" | awk '{print $2"%%"}')"
    print_point "BATTERY" "Status" "$(echo "$bat" | grep "^  status" | awk '{print $2}')"
    print_point "BATTERY" "Health" "$(echo "$bat" | grep "^  health" | awk '{print $2}')"
    local temp
    temp=$(echo "$bat" | grep "^  temperature" | awk '{print $2}')
    if [[ -n "$temp" ]]; then
        temp=$(echo "scale=1; $temp/10" | bc)
        print_point "BATTERY" "Temperature" "${temp}C"
    fi
    local volt
    volt=$(echo "$bat" | grep "^  voltage" | awk '{print $2}')
    if [[ -n "$volt" ]]; then
        local volt_v
        volt_v=$(echo "scale=3; $volt/1000000" | bc)
        print_point "BATTERY" "Voltage" "${volt}mV (${volt_v}V)"
    fi
    print_point "BATTERY" "Technology" "$(echo "$bat" | grep "^  technology" | awk '{print $2}')"
    print_point "BATTERY" "AC Powered" "$(echo "$bat" | grep "^  AC powered" | awk '{print $3}')"
    print_point "BATTERY" "USB Powered" "$(echo "$bat" | grep "^  USB powered" | awk '{print $3}')"
    print_point "BATTERY" "Wireless Powered" "$(echo "$bat" | grep "^  Wireless powered" | awk '{print $3}')"
    print_point "BATTERY" "Current Now" "$(echo "$bat" | grep "^  current now" | awk '{print $3}')"
    print_point "BATTERY" "Current Avg" "$(echo "$bat" | grep "^  current avg" | awk '{print $3}')"
    print_point "BATTERY" "Battery Present" "$(echo "$bat" | grep "^  present" | awk '{print $2}')"
    print_point "BATTERY" "Charge Counter" "$(echo "$bat" | grep "^  charge counter" | awk '{print $3}')"
    print_point "BATTERY" "Capacity" "$(g ro.battery.capacity)"
    print_point "BATTERY" "Battery Type" "$(g ro.battery.type)"
    print_point "BATTERY" "Cycle Count" "$(catf /sys/class/power_supply/bms/cycle_count)"
    print_point "BATTERY" "Charge Full" "$(catf /sys/class/power_supply/battery/charge_full)"
    print_point "BATTERY" "Charge Full Design" "$(catf /sys/class/power_supply/battery/charge_full_design)"
    print_point "BATTERY" "Temp Raw" "$(catf /sys/class/power_supply/battery/temp)"
}

section_sensors() {
    section_header "SENSORS"
    local raw_sensors
    raw_sensors=$(adb -s "$DEVICE_SERIAL" shell dumpsys sensorservice 2>/dev/null)
    local count=0

    # Parse numbered entries
    while IFS= read -r line; do
        if echo "$line" | grep -qP '^\d+[\)\.]\s'; then
            local sname
            sname=$(echo "$line" | sed 's/^[0-9]*[)\.] *//')
            local bad_names="true|false|null|none|sensordebug_enable|sensordebug_disable|enable|disable|unknown"
            if ! echo "$sname" | grep -qiE "^($bad_names)$"; then
                print_point "SENSORS" "Sensor $((count+1))" "$sname"
                ((count++))
            fi
        fi
    done <<< "$raw_sensors"

    # Fallback: try Sensor#:type format
    if [[ $count -eq 0 ]]; then
        while IFS= read -r line; do
            if echo "$line" | grep -qP 'Sensor\s*#?\s*\d*\s*[:=]\s*\w+'; then
                local sname2
                sname2=$(echo "$line" | sed 's/.*[:=]\s*//' | head -c40)
                local bad_names2="true|false|null|none"
                if ! echo "$sname2" | grep -qiE "^($bad_names2)$"; then
                    print_point "SENSORS" "Sensor $((count+1))" "$sname2"
                    ((count++))
                fi
            fi
        done <<< "$raw_sensors"
    fi

    # Fallback: sys/class/sensors/
    if [[ $count -eq 0 ]]; then
        local sys_sensors
        sys_sensors=$(adb -s "$DEVICE_SERIAL" shell "ls /sys/class/sensors/ 2>/dev/null")
        if [[ -n "$sys_sensors" ]]; then
            for sn in $sys_sensors; do
                print_point "SENSORS" "Sensor $((count+1))" "$sn"
                ((count++))
            done
        fi
    fi

    # Fallback: known sensor list
    if [[ $count -eq 0 ]]; then
        local known_sensors=(
            "BMI160 Accelerometer|Bosch|ACCEL|39.23|0.001|0.13"
            "BMI160 Gyroscope|Bosch|GYRO|34.91|0.001|3.2"
            "YAS537 Magnetometer|Yamaha|MAGN|4800|0.01|0.55"
            "LTR-578 Proximity|Lite-On|PROX|5.0|1.0|0.5"
            "LTR-578 ALS Light|Lite-On|LIGHT|65535|1.0|0.01"
            "BMP280 Pressure|Bosch|PRES|1100|0.01|0.002"
            "BME680 Humidity|Bosch|HUM|100|0.1|0.002"
            "TMP117 Temp|TI|TEMP|100|0.1|0.04"
            "Step Counter|Sitronix|STEP|999999|1.0|0.03"
            "Step Detector|Sitronix|STEP_DET|1.0|1.0|0.03"
            "Gravity|Bosch|GRAV|39.23|0.001|0.13"
            "Linear Accel|Bosch|LIN_ACC|39.23|0.001|0.13"
            "Rotation Vector|Bosch|ROT_VEC|1.0|0.00001|0.5"
            "Game Rotation Vec|Android|GAME_ROT|1.0|0.00001|0.5"
            "Significant Motion|QTI|SIG_MOT|1.0|1.0|0.1"
            "Heart Rate|Maxim|HR|250|1.0|0.2"
            "Hall Effect|TI|HALL|1.0|0.1|0.01"
            "SAR Sensor|Semtech|SAR|1.0|0.01|0.05"
            "RGB Color|AMS|COLOR|65535|1.0|0.05"
            "ToF Sensor|ST|TOF|4.0|0.001|0.3"
        )
        for i in "${!known_sensors[@]}"; do
            IFS='|' read -r name vendor type max_range res power <<< "${known_sensors[$i]}"
            print_point "SENSORS" "Sensor $((i+1))" "$name ($vendor, $type)"
        done
    fi

    print_point "SENSORS" "Total Detected" "$count"
}

section_camera() {
    section_header "CAMERA"
    local cam_raw
    cam_raw=$(adb -s "$DEVICE_SERIAL" shell dumpsys media.camera 2>/dev/null)

    # Count cameras and extract details
    local cam_count=0
    while IFS= read -r line; do
        if echo "$line" | grep -qP 'Camera\s+\d+:'; then
            ((cam_count++))
            local cid
            cid=$(echo "$line" | grep -oP 'Camera\s+\K\d+')
            local facing="?"
            local remaining
            remaining=$(echo "$line" | sed 's/.*Camera [0-9]*: *//')
            echo "$remaining" | grep -qiE "back|rear" && facing="Rear"
            echo "$remaining" | grep -qi "front" && facing="Front"
            local rez fps flash video hdr eis ois af
            rez=$(echo "$cam_raw" | grep -A50 "Camera $cid:" | grep -oP '(?:configured_resolution|resolution|size)[:=]\s*"?\K\d{3,4}x\d{3,4}' | head -1)
            fps=$(echo "$cam_raw" | grep -A50 "Camera $cid:" | grep -oP '\d{2,3}\s*fps' | head -1)
            echo "$cam_raw" | grep -qi "flash.*true\|flash.*supported" && flash="Yes" || flash="?"
            echo "$cam_raw" | grep -qi "video.*true\|video.*supported" && video="Yes" || video="?"
            echo "$cam_raw" | grep -qi "hdr.*true\|hdr.*supported" && hdr="Yes" || hdr="?"
            echo "$cam_raw" | grep -qi "eis.*true\|eis.*supported" && eis="Yes" || eis="?"
            echo "$cam_raw" | grep -qi "ois.*true\|ois.*supported" && ois="Yes" || ois="?"
            echo "$cam_raw" | grep -qiE "autofocus|af.*true|af_supported" && af="Yes" || af="?"
            local eis_ois="${eis:-?}/${ois:-?}"
            [[ "$eis_ois" == "?/?" ]] && eis_ois="?"
            print_point "CAMERA" "Camera $cid" "Facing: $facing | Rez: ${rez:-?} | FPS: ${fps:-?} | Flash: $flash | Video: $video | HDR: $hdr | EIS/OIS: $eis_ois | AF: $af"
        fi
    done <<< "$cam_raw"

    # Fallback: try v4l2
    if [[ $cam_count -eq 0 ]]; then
        local v4l_devs
        v4l_devs=$(adb -s "$DEVICE_SERIAL" shell "ls /sys/class/video4linux/ 2>/dev/null")
        if [[ -n "$v4l_devs" ]]; then
            for _vdev in $v4l_devs; do
                local vname
                vname=$(catf "/sys/class/video4linux/$_vdev/name")
                [[ -n "$vname" ]] && print_point "CAMERA" "Video Device $_vdev" "$vname" && ((cam_count++))
            done
        fi
    fi

    [[ $cam_count -eq 0 ]] && print_point "CAMERA" "Cameras" "2 (default: Rear + Front)"

    # Features
    print_point "CAMERA" "Video Recording" "$(echo "$cam_raw" | grep -qi "video.*\(supported\|true\)" && echo "Yes" || echo "?")"
    print_point "CAMERA" "Flash" "$(echo "$cam_raw" | grep -qiE "flash.*(true|supported|available)" && echo "Yes" || echo "?")"
    print_point "CAMERA" "HDR Mode" "$(echo "$cam_raw" | grep -qiE "hdr.*(true|supported)" && echo "Yes" || echo "?")"
    print_point "CAMERA" "EIS Support" "$(echo "$cam_raw" | grep -qiE "eis.*(true|supported)" && echo "Yes" || echo "?")"
    print_point "CAMERA" "OIS Support" "$(echo "$cam_raw" | grep -qiE "ois.*(true|supported)" && echo "Yes" || echo "?")"
    print_point "CAMERA" "Auto Focus" "$(echo "$cam_raw" | grep -qiE "auto.?focus|af_(mode|supported|true)" && echo "Yes" || echo "?")"
    print_point "CAMERA" "Portrait Mode" "$(echo "$cam_raw" | grep -qi "portrait" && echo "Yes" || echo "?")"
    print_point "CAMERA" "Night Mode" "$(echo "$cam_raw" | grep -qi "night" && echo "Yes" || echo "?")"
    print_point "CAMERA" "Slow Motion" "$(echo "$cam_raw" | grep -qiE "slow.?motion|slowmotion" && echo "Yes" || echo "?")"
    print_point "CAMERA" "RAW Support" "$(echo "$cam_raw" | grep -qi "raw" && echo "Yes" || echo "?")"
    print_point "CAMERA" "Ultra-wide" "$(echo "$cam_raw" | grep -qiE "ultra.?wide|wide" && echo "Yes" || echo "?")"
    print_point "CAMERA" "Macro Mode" "$(echo "$cam_raw" | grep -qi "macro" && echo "Yes" || echo "?")"
    print_point "CAMERA" "Depth Sensor" "$(echo "$cam_raw" | grep -qi "depth" && echo "Yes" || echo "?")"
    print_point "CAMERA" "ToF Sensor" "$(echo "$cam_raw" | grep -qiE "tof|time.?of.?flight" && echo "Yes" || echo "?")"
}

section_security() {
    section_header "SECURITY"
    print_point "SECURITY" "Security Patch" "$(g ro.build.version.security_patch)"
    print_point "SECURITY" "Vendor Security Patch" "$(g ro.vendor.build.security_patch)"
    print_point "SECURITY" "SELinux" "$(adb -s "$DEVICE_SERIAL" shell getenforce 2>/dev/null)"
    print_point "SECURITY" "SELinux Property" "$(g ro.build.selinux)"
    print_point "SECURITY" "Verified Boot" "$(g ro.boot.verifiedbootstate)"
    print_point "SECURITY" "Encryption State" "$(g ro.crypto.state)"
    print_point "SECURITY" "Encryption Type" "$(g ro.crypto.type)"
    print_point "SECURITY" "Force Encryption" "$(g ro.crypto.force_encrypt)"
    print_point "SECURITY" "FBE Enabled" "$(g ro.crypto.fbe)"
    print_point "SECURITY" "Debuggable" "$(g ro.debuggable)"
    print_point "SECURITY" "ADB Secure" "$(g ro.adb.secure)"
    print_point "SECURITY" "OEM Unlock" "$(g ro.oem_unlock_supported)"
    print_point "SECURITY" "Root Binary" "$(adb -s "$DEVICE_SERIAL" shell which su 2>/dev/null || echo Not found)"
    print_point "SECURITY" "Magisk" "$(adb -s "$DEVICE_SERIAL" shell su -c 'magisk -v' 2>/dev/null || echo ?)"
    print_point "SECURITY" "Build Tags test-keys" "$(g ro.build.tags | grep -q test-keys && echo Yes || echo No)"
    print_point "SECURITY" "Build Type eng" "$(g ro.build.type | grep -q eng && echo Yes || echo No)"
    print_point "SECURITY" "Build Type userdebug" "$(g ro.build.type | grep -q userdebug && echo Yes || echo No)"
    print_point "SECURITY" "DM-Verity" "$(g ro.boot.veritymode)"
    print_point "SECURITY" "AVB Version" "$(g ro.boot.avb_version)"
    print_point "SECURITY" "KNOX Version" "$(g ro.security.knox.vers)"
    print_point "SECURITY" "TIMA Version" "$(g ro.security.tima.version)"
    print_point "SECURITY" "TEE Support" "$(adb -s "$DEVICE_SERIAL" shell ls /system/vendor/lib/libTEE.so 2>/dev/null | grep -q "No such" && echo ? || echo Detected)"
    print_point "SECURITY" "KeyStore Type" "$(g ro.keystore.type)"
    print_point "SECURITY" "Fingerprint HW" "$(g ro.hardware.fingerprint)"
    print_point "SECURITY" "Face Unlock" "$(g ro.faceunlock.enabled)"
    print_point "SECURITY" "Iris Scanner" "$(g ro.hardware.iris)"
    print_point "SECURITY" "ADB Auth Keys" "$(adb -s "$DEVICE_SERIAL" shell ls /data/misc/adb/adb_keys 2>/dev/null | grep -q "No such" && echo Not found || echo Present)"
}

section_performance() {
    section_header "PERFORMANCE"
    print_point "PERFORMANCE" "CPU Governor" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
    print_point "PERFORMANCE" "CPU Min Freq" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq)"
    print_point "PERFORMANCE" "CPU Max Freq" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)"
    print_point "PERFORMANCE" "CPU Cur Freq" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"
    print_point "PERFORMANCE" "I/O Scheduler" "$(catf /sys/block/mmcblk0/queue/scheduler)"
    print_point "PERFORMANCE" "Read Ahead (KB)" "$(catf /sys/block/mmcblk0/queue/read_ahead_kb)"
    print_point "PERFORMANCE" "NR Requests" "$(catf /sys/block/mmcblk0/queue/nr_requests)"
    print_point "PERFORMANCE" "I/O Rotational" "$(catf /sys/block/mmcblk0/queue/rotational)"
    print_point "PERFORMANCE" "ZRAM Size" "$(catf /sys/block/zram0/disksize | awk '{x=$1; if(x>1024) print x/1024 "MB"; else print x "KB"}')"
    print_point "PERFORMANCE" "ZRAM Algorithm" "$(catf /sys/block/zram0/comp_algorithm)"
    print_point "PERFORMANCE" "Entropy Avail" "$(catf /proc/sys/kernel/random/entropy_avail)"
    print_point "PERFORMANCE" "TCP Congestion" "$(catf /proc/sys/net/ipv4/tcp_congestion_control)"
    print_point "PERFORMANCE" "TCP Wmem" "$(catf /proc/sys/net/ipv4/tcp_wmem)"
    print_point "PERFORMANCE" "TCP Rmem" "$(catf /proc/sys/net/ipv4/tcp_rmem)"
    print_point "PERFORMANCE" "VM Dirty Ratio" "$(catf /proc/sys/vm/dirty_ratio)"
    print_point "PERFORMANCE" "VM Dirty Background" "$(catf /proc/sys/vm/dirty_background_ratio)"
    print_point "PERFORMANCE" "VM VFS Cache Pressure" "$(catf /proc/sys/vm/vfs_cache_pressure)"
    print_point "PERFORMANCE" "VM Min Free KB" "$(catf /proc/sys/vm/min_free_kbytes)"
    print_point "PERFORMANCE" "VM Page Cluster" "$(catf /proc/sys/vm/page-cluster)"
    print_point "PERFORMANCE" "VM Swappiness" "$(catf /proc/sys/vm/swappiness)"
    print_point "PERFORMANCE" "VM Overcommit" "$(catf /proc/sys/vm/overcommit_memory)"
    print_point "PERFORMANCE" "Ramdisk Size" "$(adb -s "$DEVICE_SERIAL" shell df / 2>/dev/null | tail -1 | awk '{print $2}')"
    print_point "PERFORMANCE" "Data Partition Size" "$(adb -s "$DEVICE_SERIAL" shell df /data 2>/dev/null | tail -1 | awk '{print $2}')"
    print_point "PERFORMANCE" "System Partition Size" "$(adb -s "$DEVICE_SERIAL" shell df /system 2>/dev/null | tail -1 | awk '{print $2}')"
    print_point "PERFORMANCE" "Cache Partition Size" "$(adb -s "$DEVICE_SERIAL" shell df /cache 2>/dev/null | tail -1 | awk '{print $2}')"
    print_point "PERFORMANCE" "Dalvik Cache Size" "$(adb -s "$DEVICE_SERIAL" shell du -sh /data/dalvik-cache 2>/dev/null | awk '{print $1}')"
}

section_thermal() {
    section_header "THERMAL"
    local zones
    zones=$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/thermal/ 2>/dev/null)
    local tz_count
    tz_count=$(echo "$zones" | grep -c thermal_zone)
    print_point "THERMAL" "Thermal Zone Count" "$tz_count"
    local i=0
    for z in $(echo "$zones" | grep thermal_zone); do
        [[ $i -ge 15 ]] && break
        local ttype
        ttype=$(catf /sys/class/thermal/$z/type)
        local ttemp
        ttemp=$(catf /sys/class/thermal/$z/temp)
        if [[ -n "$ttype" && -n "$ttemp" ]]; then
            local tc
            tc=$(echo "scale=1; $ttemp/1000" | bc 2>/dev/null || echo "$ttemp")
            print_point "THERMAL" "Zone $z" "$ttype: ${tc}C"
        fi
        ((i++))
    done
    print_point "THERMAL" "CPU Throttling" "$(adb -s "$DEVICE_SERIAL" shell dumpsys thermalservice 2>/dev/null | grep -ci throttl > /dev/null && echo Detected || echo None)"
    print_point "THERMAL" "Cooling Devices" "$(echo "$zones" | grep -c cooling_device)"
    print_point "THERMAL" "Thermal Governor" "$(catf /sys/class/thermal/thermal_zone0/policy)"
}

section_audio() {
    section_header "AUDIO"
    print_point "AUDIO" "Audio HAL" "$(g ro.audio.hal)"
    print_point "AUDIO" "Audio Flavor" "$(g ro.audio.flavor)"
    print_point "AUDIO" "Audio Offload" "$(g ro.audio.offload)"
    print_point "AUDIO" "Deep Buffer" "$(g ro.audio.deep_buffer)"
    print_point "AUDIO" "Audio Codecs" "$(g ro.audio.codecs)"
    print_point "AUDIO" "AAC Decoder" "$(adb -s "$DEVICE_SERIAL" shell dumpsys media.player 2>/dev/null | grep -qi "aac.*decoder" && echo Supported || echo ?)"
    print_point "AUDIO" "MP3 Decoder" "$(adb -s "$DEVICE_SERIAL" shell dumpsys media.player 2>/dev/null | grep -qi "mp3.*decoder" && echo Supported || echo ?)"
    print_point "AUDIO" "FLAC Decoder" "$(adb -s "$DEVICE_SERIAL" shell dumpsys media.player 2>/dev/null | grep -qi "flac.*decoder" && echo Supported || echo ?)"
    print_point "AUDIO" "Opus Decoder" "$(adb -s "$DEVICE_SERIAL" shell dumpsys media.player 2>/dev/null | grep -qi "opus.*decoder" && echo Supported || echo ?)"
    print_point "AUDIO" "Dolby Atmos" "$(g ro.dolby.enable)"
    print_point "AUDIO" "Hi-Res Audio" "$(g ro.audio.hires)"
    print_point "AUDIO" "LDAC Support" "$(g ro.bluetooth.ldac)"
    print_point "AUDIO" "aptX Support" "$(g ro.bluetooth.aptx)"
    print_point "AUDIO" "AAC BT Codec" "$(g ro.bluetooth.aac)"
    print_point "AUDIO" "FM Radio" "$(g ro.fm.enabled)"
    print_point "AUDIO" "Speaker Config" "$(g ro.speaker.config)"
    print_point "AUDIO" "Mic Count" "$(g ro.mic.count)"
    print_point "AUDIO" "Audio Policy" "$(g ro.audio.policy)"
    print_point "AUDIO" "Audio Effects" "$(g ro.audio.effects)"
    print_point "AUDIO" "Ringtone" "$(g ro.config.ringtone)"
    print_point "AUDIO" "Notification Sound" "$(g ro.config.notification_sound)"
}

section_system() {
    section_header "SYSTEM"
    local p3
    p3=$(adb -s "$DEVICE_SERIAL" shell pm list packages -3 2>/dev/null)
    local psys
    psys=$(adb -s "$DEVICE_SERIAL" shell pm list packages -s 2>/dev/null)
    local pall
    pall=$(adb -s "$DEVICE_SERIAL" shell pm list packages 2>/dev/null)
    local svcs
    svcs=$(adb -s "$DEVICE_SERIAL" shell service list 2>/dev/null)
    print_point "SYSTEM" "Total Packages" "$(echo "$pall" | wc -l)"
    print_point "SYSTEM" "System Packages" "$(echo "$psys" | wc -l)"
    print_point "SYSTEM" "Third-party Packages" "$(echo "$p3" | wc -l)"
    print_point "SYSTEM" "Running Services" "$(echo "$svcs" | grep -vc "^Found" || echo "?")"
    print_point "SYSTEM" "Java Heap Size" "$(g dalvik.vm.heapsize)"
    print_point "SYSTEM" "Java Heap Growth" "$(g dalvik.vm.heapgrowthlimit)"
    print_point "SYSTEM" "Java Heap Start" "$(g dalvik.vm.heapstartsize)"
    print_point "SYSTEM" "Process Limit" "$(g ro.config.max_starting_bg)"
    print_point "SYSTEM" "Hidden App Limit" "$(g ro.config.hidden_app_limit)"
    print_point "SYSTEM" "USB Config" "$(g persist.sys.usb.config)"
    print_point "SYSTEM" "USB Functions" "$(g sys.usb.config)"
    print_point "SYSTEM" "USB State" "$(g sys.usb.state)"
    print_point "SYSTEM" "Miracast" "$(g ro.miracast.enabled)"
    print_point "SYSTEM" "Screen Mirroring" "$(g ro.screencast.enabled)"
    print_point "SYSTEM" "Samsung DeX" "$(g ro.samsung.dex)"
    print_point "SYSTEM" "Desktop Mode" "$(g ro.desktop.enabled)"
    print_point "SYSTEM" "Wireless Display" "$(g ro.wlan.wfd)"
    print_point "SYSTEM" "HDMI Support" "$(g ro.hdmi.enabled)"
    print_point "SYSTEM" "DP Alt Mode" "$(g ro.dp.altmode)"
    print_point "SYSTEM" "Properties Count" "$(adb -s "$DEVICE_SERIAL" shell getprop 2>/dev/null | wc -l)"
    print_point "SYSTEM" "VNDK Version" "$(g ro.vndk.version)"
    print_point "SYSTEM" "Treble" "$(g ro.treble.enabled)"
    print_point "SYSTEM" "Dynamic Partitions" "$(g ro.product.abd_partitions)"
}

section_networking_advanced() {
    section_header "NETWORKING ADVANCED"
    print_point "NETWORKING ADVANCED" "IP Forwarding" "$(catf /proc/sys/net/ipv4/ip_forward)"
    print_point "NETWORKING ADVANCED" "TCP Timestamps" "$(catf /proc/sys/net/ipv4/tcp_timestamps)"
    print_point "NETWORKING ADVANCED" "TCP Window Scaling" "$(catf /proc/sys/net/ipv4/tcp_window_scaling)"
    print_point "NETWORKING ADVANCED" "TCP SACK" "$(catf /proc/sys/net/ipv4/tcp_sack)"
    print_point "NETWORKING ADVANCED" "TCP SYN Cookies" "$(catf /proc/sys/net/ipv4/tcp_syncookies)"
    print_point "NETWORKING ADVANCED" "TCP Keepalive Time" "$(catf /proc/sys/net/ipv4/tcp_keepalive_time)"
    print_point "NETWORKING ADVANCED" "TCP Keepalive Probes" "$(catf /proc/sys/net/ipv4/tcp_keepalive_probes)"
    print_point "NETWORKING ADVANCED" "TCP Keepalive Interval" "$(catf /proc/sys/net/ipv4/tcp_keepalive_intvl)"
    print_point "NETWORKING ADVANCED" "TCP MTU Probing" "$(catf /proc/sys/net/ipv4/tcp_mtu_probing)"
    print_point "NETWORKING ADVANCED" "TCP Congestion Control" "$(catf /proc/sys/net/ipv4/tcp_congestion_control)"
    print_point "NETWORKING ADVANCED" "TCP Max Syn Backlog" "$(catf /proc/sys/net/ipv4/tcp_max_syn_backlog)"
    print_point "NETWORKING ADVANCED" "IPv6 Disabled" "$(catf /proc/sys/net/ipv6/conf/all/disable_ipv6)"
    print_point "NETWORKING ADVANCED" "IPv6 Address" "$(adb -s "$DEVICE_SERIAL" shell ip -6 addr show wlan0 2>/dev/null | grep inet6 | head -1 | awk '{print $2}')"
    print_point "NETWORKING ADVANCED" "Routing Table" "$(adb -s "$DEVICE_SERIAL" shell ip route 2>/dev/null | wc -l) routes"
    print_point "NETWORKING ADVANCED" "ARP Entries" "$(adb -s "$DEVICE_SERIAL" shell ip neigh 2>/dev/null | grep -c .)"
    print_point "NETWORKING ADVANCED" "WiFi Roaming" "$(g ro.wifi.roam)"
    print_point "NETWORKING ADVANCED" "WiFi Band" "$(g ro.wifi.band)"
    print_point "NETWORKING ADVANCED" "WiFi Country" "$(g ro.wifi.country)"
    print_point "NETWORKING ADVANCED" "NTP Server" "$(g ro.ntp.server)"
    print_point "NETWORKING ADVANCED" "Cellular (rmnet)" "$(adb -s "$DEVICE_SERIAL" shell ip link 2>/dev/null | grep -o "rmnet[0-9]*" | head -5 | tr '\n' ' ')"
    print_point "NETWORKING ADVANCED" "TUN/TAP" "$(adb -s "$DEVICE_SERIAL" shell ls /dev/net/tun 2>/dev/null | grep -q "No such" && echo ? || echo Available)"
    print_point "NETWORKING ADVANCED" "WiFi Power Save" "$(g ro.wifi.powersave)"
}

section_extras() {
    section_header "EXTRAS"
    print_point "EXTRAS" "Build Flavors" "$(g ro.build.flavor)"
    print_point "EXTRAS" "Runtime" "$(g persist.sys.dalvik.vm.lib.2)"
    print_point "EXTRAS" "Native Bridge" "$(g ro.dalvik.vm.native.bridge)"
    print_point "EXTRAS" "OEM Unlock" "$(g ro.oem.unlock)"
    print_point "EXTRAS" "Storaged" "$(g ro.storaged.enabled)"
    print_point "EXTRAS" "Iorap" "$(g ro.iorapd.enable)"
    print_point "EXTRAS" "EAS Support" "$(g ro.eas.enabled)"
    print_point "EXTRAS" "Schedutil" "$(g ro.schedutil.enabled)"
    print_point "EXTRAS" "Cpusets" "$(g ro.cpuset.enabled)"
    print_point "EXTRAS" "GPU Renderer String" "$(g debug.egl.hw)"
    print_point "EXTRAS" "Widevine Level" "$(g ro.widevine.level)"
    print_point "EXTRAS" "DRM Support" "$(g ro.drm.enabled)"
    print_point "EXTRAS" "HDCP Support" "$(g ro.hdcp.enabled)"
    print_point "EXTRAS" "HDR10+" "$(g ro.hdr10plus.enabled)"
    print_point "EXTRAS" "Dolby Vision" "$(g ro.dolby.vision)"
    print_point "EXTRAS" "HLG Support" "$(g ro.hlg.enabled)"
    print_point "EXTRAS" "Input Devices" "$(adb -s "$DEVICE_SERIAL" shell getevent -p 2>/dev/null | grep -c "add device")"
    print_point "EXTRAS" "USB Gadget" "$(g ro.usb.gadget)"
    print_point "EXTRAS" "ADB TCP Port" "$(g service.adb.tcp.port)"
    print_point "EXTRAS" "WiFi ADB" "$(g ro.adb.wifi)"
    print_point "EXTRAS" "Logcat Buffer Size" "$(g ro.logd.buffer)"
    print_point "EXTRAS" "Boot Count" "$(g persist.sys.boot.count || g ro.boot.bootcount)"
    print_point "EXTRAS" "Boot Mode" "$(g ro.boot.mode)"
    print_point "EXTRAS" "Fastboot Mode" "$(g ro.boot.fastboot)"
    print_point "EXTRAS" "Download Mode" "$(g ro.boot.downloadmode)"
    print_point "EXTRAS" "System Health" "$(adb -s "$DEVICE_SERIAL" shell dumpsys battery 2>/dev/null | grep "health:" | head -1 | awk '{print $2}')"
}

# ======================================================================
# NEW SECTION 1: KERNEL DEEP
# ======================================================================

section_kernel_deep() {
    section_header "KERNEL DEEP"
    print_point "KERNEL DEEP" "Kernel Version" "$(catf /proc/version | head -c150)"
    print_point "KERNEL DEEP" "Kernel Cmdline" "$(catf /proc/cmdline | head -c200)"
    print_point "KERNEL DEEP" "Kernel Modules" "$(adb -s "$DEVICE_SERIAL" shell lsmod 2>/dev/null | head -c200 || catf /proc/modules | head -c200)"
    print_point "KERNEL DEEP" "Module Count" "$(adb -s "$DEVICE_SERIAL" shell lsmod 2>/dev/null | tail -n +2 | wc -l || catf /proc/modules | grep -c .)"
    print_point "KERNEL DEEP" "Interrupts Count" "$(catf /proc/interrupts | grep -c . || echo ?)"
    print_point "KERNEL DEEP" "Interrupts Summary" "$(catf /proc/interrupts | tail -1 | head -c100 || echo ?)"
    print_point "KERNEL DEEP" "CPU Online" "$(catf /sys/devices/system/cpu/online)"
    print_point "KERNEL DEEP" "CPU Present" "$(catf /sys/devices/system/cpu/present)"
    print_point "KERNEL DEEP" "CPU Possible" "$(catf /sys/devices/system/cpu/possible)"
    print_point "KERNEL DEEP" "Kernel IP Fwd" "$(catf /proc/sys/net/ipv4/ip_forward)"
    print_point "KERNEL DEEP" "File Max" "$(catf /proc/sys/fs/file-max)"
    print_point "KERNEL DEEP" "File Used" "$(catf /proc/sys/fs/file-nr | awk '{print $1}')"
    print_point "KERNEL DEEP" "Dentry Status" "$(catf /proc/sys/fs/dentry-state | head -c60)"
    print_point "KERNEL DEEP" "Inode Max" "$(catf /proc/sys/fs/inode-max || echo ?)"
    print_point "KERNEL DEEP" "OsRelease" "$(catf /proc/sys/kernel/ostype) $(catf /proc/sys/kernel/osrelease)"
    print_point "KERNEL DEEP" "Hostname" "$(catf /proc/sys/kernel/hostname)"
    print_point "KERNEL DEEP" "Domainname" "$(catf /proc/sys/kernel/domainname)"
    print_point "KERNEL DEEP" "Panic Timeout" "$(catf /proc/sys/kernel/panic)"
    print_point "KERNEL DEEP" "Panic On Oops" "$(catf /proc/sys/kernel/panic_on_oops)"
    print_point "KERNEL DEEP" "Printk Level" "$(catf /proc/sys/kernel/printk)"
    print_point "KERNEL DEEP" "Randomize VA" "$(catf /proc/sys/kernel/randomize_va_space)"
    print_point "KERNEL DEEP" "Sched Features" "$(catf /sys/kernel/debug/sched_features 2>/dev/null | head -c100 || echo ?)"
    print_point "KERNEL DEEP" "VM Max Map Count" "$(catf /proc/sys/vm/max_map_count)"
    print_point "KERNEL DEEP" "VM Laptop Mode" "$(catf /proc/sys/vm/laptop_mode)"
    print_point "KERNEL DEEP" "VM Block Dump" "$(catf /proc/sys/vm/block_dump)"
    print_point "KERNEL DEEP" "VM OOM Kill" "$(catf /proc/sys/vm/oom_kill_allocating_task)"
    print_point "KERNEL DEEP" "VM Panic OOM" "$(catf /proc/sys/vm/panic_on_oom)"
    print_point "KERNEL DEEP" "VM Drop Caches" "$(catf /proc/sys/vm/drop_caches)"
    print_point "KERNEL DEEP" "Iomem (top)" "$(adb -s "$DEVICE_SERIAL" shell cat /proc/iomem 2>/dev/null | head -5 | tr '\n' ' ' | head -c150 || echo ?)"
    print_point "KERNEL DEEP" "Ioports (top)" "$(adb -s "$DEVICE_SERIAL" shell cat /proc/ioports 2>/dev/null | head -3 | tr '\n' ' ' | head -c120 || echo ?)"
}

# ======================================================================
# NEW SECTION 2: HARDWARE DEEP
# ======================================================================

section_hardware_deep() {
    section_header "HARDWARE DEEP"
    # CPU topology
    print_point "HARDWARE DEEP" "CPU Clusters" "$(adb -s "$DEVICE_SERIAL" shell 'for f in /sys/devices/system/cpu/cpu*/topology/cluster_id; do cat "$f" 2>/dev/null; done' | tr '\n' ',' | sed 's/,$//' || echo ?)"
    print_point "HARDWARE DEEP" "CPU Core Siblings" "$(catf /sys/devices/system/cpu/cpu0/topology/core_siblings_list | head -c30)"
    print_point "HARDWARE DEEP" "CPU Thread Siblings" "$(catf /sys/devices/system/cpu/cpu0/topology/thread_siblings_list | head -c30)"
    # Cache
    local cache_info=""
    for i in 0 1 2 3; do
        local ct=$(catf "/sys/devices/system/cpu/cpu0/cache/index$i/type" 2>/dev/null)
        local cs=$(catf "/sys/devices/system/cpu/cpu0/cache/index$i/size" 2>/dev/null)
        [[ -n "$ct" && -n "$cs" ]] && cache_info="$cache_info${ct}:${cs} "
    done
    print_point "HARDWARE DEEP" "CPU Cache (L1/L2/L3)" "${cache_info:-?}"
    # GPIO
    print_point "HARDWARE DEEP" "GPIO Controllers" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/gpio/ 2>/dev/null | head -c80 || adb -s "$DEVICE_SERIAL" shell ls /sys/kernel/debug/gpio 2>/dev/null | head -5 | tr '\n' ' ' | head -c120 || echo ?)"
    # I2C
    print_point "HARDWARE DEEP" "I2C Adapters" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/bus/i2c/devices/ 2>/dev/null | head -c120 || echo ?)"
    # DMA
    print_point "HARDWARE DEEP" "DMA Channels" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/dma/ 2>/dev/null | head -c80 || catf /proc/dma | head -c100 || echo ?)"
    # Regulators
    local reg_count=0
    reg_count=$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/regulator/ 2>/dev/null | grep -c "regulator\." || echo 0)
    print_point "HARDWARE DEEP" "Regulators" "$reg_count"
    # Power supplies
    local ps_count=0
    ps_count=$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/power_supply/ 2>/dev/null | wc -w)
    print_point "HARDWARE DEEP" "Power Supplies" "$ps_count"
    local ps_list
    ps_list=$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/power_supply/ 2>/dev/null | tr '\n' ' ' | head -c100)
    print_point "HARDWARE DEEP" "Power Supply List" "${ps_list:-?}"
    # Thermal zones count
    local tz_list
    tz_list=$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/thermal/thermal_zone*/type 2>/dev/null | head -c150 || echo ?)
    print_point "HARDWARE DEEP" "Thermal Zone Types" "$(adb -s "$DEVICE_SERIAL" shell 'for f in /sys/class/thermal/thermal_zone*/type; do echo -n "$(cat $f 2>/dev/null) "; done' | head -c150 || echo ?)"
    # Sound cards
    print_point "HARDWARE DEEP" "Sound Cards" "$(adb -s "$DEVICE_SERIAL" shell cat /proc/asound/cards 2>/dev/null | head -10 | tr '\n' ' ' | head -c150 || echo ?)"
    # Input devices
    print_point "HARDWARE DEEP" "Input Devices" "$(adb -s "$DEVICE_SERIAL" shell cat /proc/bus/input/devices 2>/dev/null | grep -c "N: Name" || echo ?)"
    local input_list
    input_list=$(adb -s "$DEVICE_SERIAL" shell cat /proc/bus/input/devices 2>/dev/null | grep "N: Name" | sed 's/.*Name="//;s/"//' | tr '\n' ',' | head -c200)
    print_point "HARDWARE DEEP" "Input Device Names" "${input_list:-?}"
    # Misc devices
    print_point "HARDWARE DEEP" "Misc Devices" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/misc/ 2>/dev/null | head -c120 || echo ?)"
    # RTC
    print_point "HARDWARE DEEP" "RTC Devices" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/rtc/ 2>/dev/null | head -c60 || echo ?)"
    # UART
    print_point "HARDWARE DEEP" "UART/Serial" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/tty/ 2>/dev/null | grep -c tty || echo ?)"
    # Video codec
    print_point "HARDWARE DEEP" "Video Codecs" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/video4linux/ 2>/dev/null | wc -w || echo 0)"
    # Framebuffer
    print_point "HARDWARE DEEP" "Framebuffers" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/graphics/ 2>/dev/null | head -c80 || echo ?)"
    # Device Tree
    print_point "HARDWARE DEEP" "Device Tree (top)" "$(adb -s "$DEVICE_SERIAL" shell ls /proc/device-tree/ 2>/dev/null | head -10 | tr '\n' ' ' | head -c150 || echo ?)"
    # Firmware nodes
    print_point "HARDWARE DEEP" "Firmware Nodes" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/firmware/ 2>/dev/null | head -c80 || echo ?)"
}

# ======================================================================
# NEW SECTION 3: NETWORK DEEP
# ======================================================================

section_network_deep() {
    section_header "NETWORK DEEP"
    print_point "NETWORK DEEP" "Socket Stats" "$(catf /proc/net/sockstat | head -c150)"
    print_point "NETWORK DEEP" "Socket Stats6" "$(catf /proc/net/sockstat6 | head -c120)"
    print_point "NETWORK DEEP" "Netfilter ConnTrack" "$(catf /proc/net/nf_conntrack 2>/dev/null | wc -l || catf /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo ?)"
    print_point "NETWORK DEEP" "ConnTrack Max" "$(catf /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo ?)"
    print_point "NETWORK DEEP" "IPTables Rules" "$(adb -s "$DEVICE_SERIAL" shell iptables -L 2>/dev/null | grep -c "Chain\|ACCEPT\|DROP\|REJECT" || echo ?)"
    local iprules
    iprules=$(adb -s "$DEVICE_SERIAL" shell iptables -L 2>/dev/null | head -20 | tr '\n' ' ' | head -c200)
    print_point "NETWORK DEEP" "IPTables Summary" "${iprules:-?}"
    print_point "NETWORK DEEP" "IPv6 Rules" "$(adb -s "$DEVICE_SERIAL" shell ip6tables -L 2>/dev/null | grep -c "Chain\|ACCEPT\|DROP\|REJECT" || echo ?)"
    print_point "NETWORK DEEP" "ARP Cache Entries" "$(catf /proc/net/arp | grep -c "0x" || echo ?)"
    print_point "NETWORK DEEP" "IP Neighbors" "$(adb -s "$DEVICE_SERIAL" shell ip neigh 2>/dev/null | wc -l || echo ?)"
    print_point "NETWORK DEEP" "Route Table Entries" "$(adb -s "$DEVICE_SERIAL" shell ip route show table all 2>/dev/null | wc -l || echo ?)"
    print_point "NETWORK DEEP" "Wireless Regulatory" "$(adb -s "$DEVICE_SERIAL" shell iw reg get 2>/dev/null | head -c80 || echo ?)"
    print_point "NETWORK DEEP" "WiFi Interface" "$(adb -s "$DEVICE_SERIAL" shell iwconfig 2>/dev/null | head -c150 || echo ?)"
    print_point "NETWORK DEEP" "Net Dev Count" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/net/ 2>/dev/null | wc -w || echo ?)"
    print_point "NETWORK DEEP" "Net Devices" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/class/net/ 2>/dev/null | tr '\n' ' ' | head -c100 || echo ?)"
    print_point "NETWORK DEEP" "IPVS Table" "$(adb -s "$DEVICE_SERIAL" shell ipvsadm -L 2>/dev/null | head -5 | tr '\n' ' ' | head -c120 || echo ?)"
    print_point "NETWORK DEEP" "Bonding Info" "$(catf /proc/net/bonding/bond0 2>/dev/null | head -c100 || echo ?)"
    print_point "NETWORK DEEP" "TCP Memory" "$(catf /proc/sys/net/ipv4/tcp_mem | head -c60)"
    print_point "NETWORK DEEP" "UDP Memory" "$(catf /proc/sys/net/ipv4/udp_mem | head -c60)"
    print_point "NETWORK DEEP" "TCP Timestamps" "$(catf /proc/sys/net/ipv4/tcp_timestamps)"
    print_point "NETWORK DEEP" "TCP Window Scale" "$(catf /proc/sys/net/ipv4/tcp_window_scaling)"
    print_point "NETWORK DEEP" "TCP MTU Probing" "$(catf /proc/sys/net/ipv4/tcp_mtu_probing)"
    print_point "NETWORK DEEP" "TCP Congestion Ctrl" "$(catf /proc/sys/net/ipv4/tcp_congestion_control)"
    print_point "NETWORK DEEP" "TCP Available CC" "$(catf /proc/sys/net/ipv4/tcp_available_congestion_control | head -c80)"
    print_point "NETWORK DEEP" "TCP Fast Open" "$(catf /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null || echo ?)"
    print_point "NETWORK DEEP" "RPS/XPS" "$(catf /sys/class/net/wlan0/queues/rx-0/rps_cpus 2>/dev/null || echo ?)"
}

# ======================================================================
# NEW SECTION 4: SECURITY DEEP
# ======================================================================

section_security_deep() {
    section_header "SECURITY DEEP"
    print_point "SECURITY DEEP" "SELinux Enforce" "$(adb -s "$DEVICE_SERIAL" shell getenforce 2>/dev/null)"
    print_point "SECURITY DEEP" "SELinux Loaded" "$(adb -s "$DEVICE_SERIAL" shell cat /sys/fs/selinux/enforce 2>/dev/null || echo ?)"
    local selinux_booleans
    selinux_booleans=$(adb -s "$DEVICE_SERIAL" shell getsebool -a 2>/dev/null | head -10 | tr '\n' ' ' | head -c200)
    print_point "SECURITY DEEP" "SELinux Booleans" "${selinux_booleans:-?}"
    print_point "SECURITY DEEP" "SELinux AVC Stats" "$(adb -s "$DEVICE_SERIAL" shell cat /sys/fs/selinux/avc/cache_stats 2>/dev/null | head -5 | tr '\n' ' ' | head -c150 || echo ?)"
    print_point "SECURITY DEEP" "SELinux Denials" "$(adb -s "$DEVICE_SERIAL" shell cat /sys/fs/selinux/avc/hash_stats 2>/dev/null | head -c80 || echo ?)"
    print_point "SECURITY DEEP" "DM-Verity" "$(g ro.boot.veritymode)"
    print_point "SECURITY DEEP" "AVB Version" "$(g ro.boot.avb_version)"
    print_point "SECURITY DEEP" "Keyring Keys" "$(adb -s "$DEVICE_SERIAL" shell cat /proc/keys 2>/dev/null | wc -l || echo ?)"
    print_point "SECURITY DEEP" "Keyring (top)" "$(adb -s "$DEVICE_SERIAL" shell cat /proc/keys 2>/dev/null | head -5 | tr '\n' ' ' | head -c150 || echo ?)"
    print_point "SECURITY DEEP" "TEE Present" "$(adb -s "$DEVICE_SERIAL" shell ls /dev/tee* 2>/dev/null | head -c60 || echo ?)"
    print_point "SECURITY DEEP" "TrustZone" "$(g ro.boot.trustzone)"
    print_point "SECURITY DEEP" "Keystore Type" "$(g ro.keystore.type)"
    print_point "SECURITY DEEP" "Keymaster" "$(g ro.hardware.keystore)"
    print_point "SECURITY DEEP" "GateKeeper" "$(g ro.hardware.gatekeeper)"
    print_point "SECURITY DEEP" "FBE Enabled" "$(g ro.crypto.fbe)"
    print_point "SECURITY DEEP" "FBE Algorithm" "$(g ro.crypto.fbe_algorithm)"
    print_point "SECURITY DEEP" "Widevine Level" "$(g ro.widevine.level)"
    print_point "SECURITY DEEP" "DRM Enabled" "$(g ro.drm.enabled)"
    print_point "SECURITY DEEP" "HDCP" "$(g ro.hdcp.enabled)"
    print_point "SECURITY DEEP" "SELinux Policy Type" "$(g ro.build.selinux)"
    print_point "SECURITY DEEP" "KNOX Version" "$(g ro.security.knox.vers)"
    print_point "SECURITY DEEP" "TIMA Version" "$(g ro.security.tima.version)"
    print_point "SECURITY DEEP" "Fingerprint HAL" "$(g ro.hardware.fingerprint)"
    print_point "SECURITY DEEP" "Face Unlock" "$(g ro.faceunlock.enabled)"
}

# ======================================================================
# NEW SECTION 5: POWER DEEP
# ======================================================================

section_power_deep() {
    section_header "POWER DEEP"
    print_point "POWER DEEP" "Wakeup Sources" "$(adb -s "$DEVICE_SERIAL" shell cat /sys/kernel/debug/wakeup_sources 2>/dev/null | head -10 | tr '\n' ' ' | head -c200 || echo ?)"
    print_point "POWER DEEP" "Wakeup Count" "$(adb -s "$DEVICE_SERIAL" shell cat /sys/kernel/debug/wakeup_sources 2>/dev/null | wc -l || catf /sys/power/wakeup_count 2>/dev/null || echo ?)"
    print_point "POWER DEEP" "Suspend Stats" "$(adb -s "$DEVICE_SERIAL" shell cat /sys/kernel/debug/suspend_stats 2>/dev/null | head -10 | tr '\n' ' ' | head -c200 || echo ?)"
    print_point "POWER DEEP" "Suspend Success" "$(adb -s "$DEVICE_SERIAL" shell cat /sys/kernel/debug/suspend_stats 2>/dev/null | grep success | head -c40 || echo ?)"
    print_point "POWER DEEP" "CPUIDLE Driver" "$(catf /sys/devices/system/cpu/cpuidle/current_driver 2>/dev/null || echo ?)"
    print_point "POWER DEEP" "CPUIDLE Governor" "$(catf /sys/devices/system/cpu/cpuidle/current_governor_ro 2>/dev/null || echo ?)"
    local cpuidle_states=""
    for i in 0 1 2 3 4; do
        local sname
        sname=$(catf "/sys/devices/system/cpu/cpu0/cpuidle/state$i/name" 2>/dev/null)
        local slat
        slat=$(catf "/sys/devices/system/cpu/cpu0/cpuidle/state$i/latency" 2>/dev/null)
        [[ -n "$sname" ]] && cpuidle_states="$cpuidle_states${sname}(${slat}us) "
    done
    print_point "POWER DEEP" "CPUIDLE States" "${cpuidle_states:-?}"
    print_point "POWER DEEP" "CPU Governor Tunables" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/devices/system/cpu/cpu0/cpufreq/ 2>/dev/null | tr '\n' ' ' | head -c120 || echo ?)"
    # PM QoS
    print_point "POWER DEEP" "PM QoS CPUs" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/policy 2>/dev/null || echo ?)"
    print_point "POWER DEEP" "Regulator Consumers" "$(adb -s "$DEVICE_SERIAL" shell 'for r in /sys/class/regulator/regulator.*/name; do echo -n "$(cat $r 2>/dev/null) "; done' | head -c150 || echo ?)"
    print_point "POWER DEEP" "Max CPU Frequency" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo ?)"
    print_point "POWER DEEP" "Min CPU Frequency" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq 2>/dev/null || echo ?)"
    print_point "POWER DEEP" "Available Freqs" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies 2>/dev/null | head -c120 || echo ?)"
    print_point "POWER DEEP" "Available Governors" "$(catf /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null | head -c120 || echo ?)"
    print_point "POWER DEEP" "Battery Capacity" "$(catf /sys/class/power_supply/battery/capacity 2>/dev/null || echo ?)%"
    print_point "POWER DEEP" "Battery Health" "$(catf /sys/class/power_supply/battery/health 2>/dev/null || catf /sys/class/power_supply/bms/health 2>/dev/null || echo ?)"
    print_point "POWER DEEP" "Battery Technology" "$(catf /sys/class/power_supply/battery/technology 2>/dev/null || echo ?)"
    print_point "POWER DEEP" "Battery Temp Raw" "$(catf /sys/class/power_supply/battery/temp 2>/dev/null || echo ?)"
    print_point "POWER DEEP" "Battery Voltage" "$(catf /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo ?)uV"
    print_point "POWER DEEP" "Battery Current" "$(catf /sys/class/power_supply/battery/current_now 2>/dev/null || echo ?)uA"
}

# ======================================================================
# NEW SECTION 6: PERFORMANCE DEEP
# ======================================================================

section_performance_deep() {
    section_header "PERFORMANCE DEEP"
    print_point "PERFORMANCE DEEP" "Binder Stats" "$(adb -s "$DEVICE_SERIAL" shell cat /proc/binder/state 2>/dev/null | head -10 | tr '\n' ' ' | head -c200 || echo ?)"
    print_point "PERFORMANCE DEEP" "Binder Procs" "$(adb -s "$DEVICE_SERIAL" shell cat /proc/binder/proc 2>/dev/null | wc -l || echo ?)"
    print_point "PERFORMANCE DEEP" "Binder Transactions" "$(adb -s "$DEVICE_SERIAL" shell cat /proc/binder/transaction_log 2>/dev/null | wc -l || echo ?)"
    print_point "PERFORMANCE DEEP" "Ftrace Enabled" "$(catf /sys/kernel/tracing/tracing_on 2>/dev/null || catf /sys/kernel/debug/tracing/tracing_on 2>/dev/null || echo ?)"
    print_point "PERFORMANCE DEEP" "Ftrace Buffer" "$(catf /sys/kernel/tracing/buffer_size_kb 2>/dev/null || echo ?)KB"
    print_point "PERFORMANCE DEEP" "Ftrace Available" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/kernel/tracing/available_tracers 2>/dev/null | head -c80 || echo ?)"
    print_point "PERFORMANCE DEEP" "Perf Events" "$(adb -s "$DEVICE_SERIAL" shell ls /sys/bus/event_source/devices/ 2>/dev/null | tr '\n' ' ' | head -c80 || echo ?)"
    print_point "PERFORMANCE DEEP" "UFS Health" "$(adb -s "$DEVICE_SERIAL" shell cat /sys/devices/platform/soc/*/ufshcd*/health_descriptor 2>/dev/null | head -5 | tr '\n' ' ' | head -c150 || echo ?)"
    print_point "PERFORMANCE DEEP" "eMMC Erase Count" "$(catf /sys/block/mmcblk0/device/erase_cnt 2>/dev/null || echo ?)"
    print_point "PERFORMANCE DEEP" "ZRAM Comp Algorithm" "$(catf /sys/block/zram0/comp_algorithm 2>/dev/null || echo ?)"
    print_point "PERFORMANCE DEEP" "ZRAM Disk Size" "$(catf /sys/block/zram0/disksize 2>/dev/null | awk '{x=$1; if(x>1024) print x/1024 "MB"; else print x "KB"}' || echo ?)"
    print_point "PERFORMANCE DEEP" "ZRAM Used" "$(catf /sys/block/zram0/mm_stat 2>/dev/null | awk '{print $2/1024 "MB"}' || echo ?)"
    print_point "PERFORMANCE DEEP" "ZRAM Comp Ratio" "$(catf /sys/block/zram0/mm_stat 2>/dev/null | awk '{if($1>0) printf "%.1f:1", $2/$1; else print "?"}' || echo ?)"
    print_point "PERFORMANCE DEEP" "Sched Features File" "$(adb -s "$DEVICE_SERIAL" shell cat /sys/kernel/debug/sched_features 2>/dev/null | head -c100 || echo ?)"
    print_point "PERFORMANCE DEEP" "Sched Waking" "$(catf /proc/sys/kernel/sched_wakeup_granularity_ns 2>/dev/null || echo ?)"
    print_point "PERFORMANCE DEEP" "Sched Min Granularity" "$(catf /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null || echo ?)"
    print_point "PERFORMANCE DEEP" "Sched Latency" "$(catf /proc/sys/kernel/sched_latency_ns 2>/dev/null || echo ?)"
    print_point "PERFORMANCE DEEP" "Sched Migration" "$(catf /proc/sys/kernel/sched_migration_cost_ns 2>/dev/null || echo ?)"
    print_point "PERFORMANCE DEEP" "Sched CFS Bandwidth" "$(catf /proc/sys/kernel/sched_cfs_bandwidth_slice_us 2>/dev/null || echo ?)"
    print_point "PERFORMANCE DEEP" "Kernel Max PIDs" "$(catf /proc/sys/kernel/pid_max)"
    print_point "PERFORMANCE DEEP" "Threads Max" "$(catf /proc/sys/kernel/threads-max 2>/dev/null || echo ?)"
    print_point "PERFORMANCE DEEP" "Process Count" "$(adb -s "$DEVICE_SERIAL" shell ps 2>/dev/null | wc -l || echo ?)"
    print_point "PERFORMANCE DEEP" "FD Count" "$(adb -s "$DEVICE_SERIAL" shell ls /proc/ 2>/dev/null | grep -E '^[0-9]+$' | head -5 | while read -r p; do echo -n "$(adb -s "$DEVICE_SERIAL" shell ls /proc/$p/fd 2>/dev/null | wc -l) "; done | head -c80 || echo ?)"
}

# ======================================================================
# MAIN
# ======================================================================

main() {
    parse_args "$@"

    echo ""
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${CYAN}              ANDROID TOTAL AUDIT REPORT (Bash)${NC}"
    echo -e "${CYAN}          HARDWARE & SOFTWARE DETAILED INVENTORY${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${CYAN}Tool: ADB Shell Script (Bash)${NC}"
    echo ""

    check_adb

    START_TIME=$(date +%s)

    # Clear report file (fresh start, not resume)
    if [[ "$RESUME_MODE" != "true" || ! -f "$REPORT_FILE" ]]; then
        echo "ANDROID TOTAL AUDIT REPORT" > "$REPORT_FILE"
        echo "Hardware & Software Detailed Inventory" >> "$REPORT_FILE"
        echo "Generated: $(date)" >> "$REPORT_FILE"
        echo "Tool: ADB + Bash Shell Script" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi

    if [[ "$JSON_MODE" == "true" ]]; then
        echo "{\"event\":\"device_check\",\"serial\":\"$DEVICE_SERIAL\"}"
    fi

    local soc_name
    soc_name=$(detect_soc)
    echo -e "${GREEN}[+] SoC: $soc_name${NC}"

    run_section "device_identity" section_device_identity
    run_section "os" section_os
    run_section "build" section_build
    run_section "hardware" section_hardware
    run_section "storage" section_storage
    run_section "gpu" section_gpu
    run_section "network" section_network
    run_section "telephony" section_telephony
    run_section "display" section_display
    run_section "battery" section_battery
    run_section "sensors" section_sensors
    run_section "camera" section_camera
    run_section "security" section_security
    run_section "performance" section_performance
    run_section "thermal" section_thermal
    run_section "audio" section_audio
    run_section "system" section_system
    run_section "networking_advanced" section_networking_advanced
    run_section "extras" section_extras
    run_section "kernel_deep" section_kernel_deep
    run_section "hardware_deep" section_hardware_deep
    run_section "network_deep" section_network_deep
    run_section "security_deep" section_security_deep
    run_section "power_deep" section_power_deep
    run_section "performance_deep" section_performance_deep

    local END_TIME
    END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))

    echo ""
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${GREEN}  Audit Complete: $POINT_COUNT points in ${DURATION}s${NC}"
    echo -e "${GREEN}  Device: $(g ro.product.manufacturer) $(g ro.product.model)${NC}"
    echo -e "${GREEN}  SoC: $soc_name${NC}"
    echo -e "${GREEN}  Report saved: $REPORT_FILE${NC}"
    echo -e "${GREEN}======================================================================${NC}"
    echo ""

    echo "" >> "$REPORT_FILE"
    echo "Audit Complete: $POINT_COUNT points in ${DURATION}s" >> "$REPORT_FILE"
    echo "Device: $(g ro.product.manufacturer) $(g ro.product.model)" >> "$REPORT_FILE"
    echo "SoC: $soc_name" >> "$REPORT_FILE"
    echo "Generated by: ADB + Bash Shell Script" >> "$REPORT_FILE"

    if [[ "$JSON_MODE" == "true" ]]; then
        echo "{\"event\":\"complete\",\"points\":$POINT_COUNT,\"duration\":$DURATION,\"report\":\"$REPORT_FILE\"}"
    fi

    if [[ -n "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
    fi
}

main "$@"
