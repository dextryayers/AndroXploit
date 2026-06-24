#!/usr/bin/env python3
import os
import sys
import subprocess
import time
import re
import json
import datetime
from pathlib import Path
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.columns import Columns
from rich.layout import Layout
from rich.text import Text
from rich import box
from rich.rule import Rule
from .soc_db import SoCDatabase

console = Console()

ARM_IMPLEMENTERS = {
    "0x41": "ARM",
    "0x42": "Broadcom",
    "0x43": "Cavium",
    "0x44": "DEC",
    "0x46": "Fujitsu",
    "0x48": "HiSilicon",
    "0x49": "Infineon",
    "0x4d": "Motorola",
    "0x4e": "NEC",
    "0x50": "Qualcomm",
    "0x51": "Qualcomm",
    "0x53": "Samsung",
    "0x54": "Texas Instruments",
    "0x55": "Marvell",
    "0x56": "Marvell",
    "0x61": "Apple",
    "0x66": "Faraday",
    "0x68": "MediaTek",
    "0x69": "MediaTek",
    "0x70": "Nvidia",
    "0x72": "Rockchip",
    "0x73": "Rockchip",
    "0x78": "Unisoc",
    "0x82": "Spreadtrum",
    "0xc0": "Ampere",
}

ARM_CORES = {
    "0xd03": "Cortex-A53",
    "0xd04": "Cortex-A35",
    "0xd05": "Cortex-A55",
    "0xd06": "Cortex-A65",
    "0xd07": "Cortex-A57",
    "0xd08": "Cortex-A72",
    "0xd09": "Cortex-A73",
    "0xd0a": "Cortex-A75",
    "0xd0b": "Cortex-A76",
    "0xd0c": "Cortex-A77",
    "0xd0d": "Cortex-A78",
    "0xd0e": "Cortex-A78AE",
    "0xd0f": "Cortex-A65AE",
    "0xd10": "Cortex-A710",
    "0xd11": "Cortex-X1",
    "0xd12": "Cortex-X2",
    "0xd13": "Cortex-X3",
    "0xd14": "Cortex-X4",
    "0xd40": "Cortex-A510",
    "0xd41": "Cortex-A520",
    "0xd44": "Cortex-X1C",
    "0xd46": "Cortex-A715",
    "0xd47": "Cortex-A725",
    "0xd48": "Cortex-X925",
    "0xd80": "Cortex-A720",
    "0xd81": "Cortex-A530",
    "0xd82": "Cortex-A55 (r1)",
    "0x801": "Kryo 260 Gold (Cortex-A73)",
    "0x802": "Kryo 260 Silver (Cortex-A53)",
    "0x803": "Kryo 280 Gold (Cortex-A73)",
    "0x804": "Kryo 280 Silver (Cortex-A53)",
    "0x205": "Kryo 385 Gold (Cortex-A75)",
    "0x211": "Kryo 385 Silver (Cortex-A55)",
    "0x475": "X-Gene",
    "0x000": "Denver",
    "0x001": "Denver 2",
}

GPU_MAP = {
    "mt68": "Mali-G68",
    "mt57": "Mali-G57",
    "mt61": "Mali-G61",
    "mt71": "Mali-G71",
    "mt72": "Mali-G72",
    "mt76": "Mali-G76",
    "mt77": "Mali-G77",
    "mt78": "Mali-G78",
    "mt52": "Mali-G52",
    "mt51": "Mali-G51",
    "mali": "Mali",
    "adreno": "Adreno",
    "powervr": "PowerVR",
}


class ADBError(Exception):
    pass


class DeviceNotFoundError(ADBError):
    pass


class AndroidUSBSanner:
    def __init__(self):
        self.device_serial = None
        self.props = {}
        self.raw = {}
        self.cached = {}
        self.device_verified = False

    def _adb(self, cmd, timeout=15):
        full_cmd = ["adb"]
        if self.device_serial:
            full_cmd.extend(["-s", self.device_serial])
        full_cmd.extend(cmd)
        try:
            r = subprocess.run(full_cmd, capture_output=True, text=True, timeout=timeout)
            if r.returncode != 0 and "error" in r.stderr.lower() and "warning" not in r.stderr.lower():
                raise ADBError(r.stderr.strip())
            return r.stdout
        except FileNotFoundError:
            raise ADBError("ADB not found. Install Android platform tools.")
        except subprocess.TimeoutExpired:
            raise ADBError(f"Command timed out: {' '.join(cmd)}")

    def _adb_raw(self, cmd, timeout=15):
        full_cmd = ["adb"]
        if self.device_serial:
            full_cmd.extend(["-s", self.device_serial])
        full_cmd.extend(cmd)
        try:
            r = subprocess.run(full_cmd, capture_output=True, text=True, timeout=timeout)
            return r.stdout, r.stderr, r.returncode
        except FileNotFoundError:
            raise ADBError("ADB not found. Install Android platform tools.")

    def discover_device(self):
        out, err, code = self._adb_raw(["devices"], timeout=5)
        for line in out.splitlines():
            line = line.strip()
            if not line or "List of devices" in line or "daemon" in line:
                continue
            parts = line.split()
            if len(parts) >= 2 and parts[0] != "":
                serial = parts[0]
                state = parts[1]
                if state == "device":
                    self.device_serial = serial
                    console.print(f"[bold green]\u25b6[/bold green] Device: [bold white]{serial}[/bold white]")
                    return serial
        raise DeviceNotFoundError("No Android device detected. Connect USB cable & enable USB debugging.")

    def verify_device(self):
        try:
            manufacturer = self._adb(["shell", "getprop", "ro.product.manufacturer"], timeout=5).strip()
            model = self._adb(["shell", "getprop", "ro.product.model"], timeout=5).strip()
            if manufacturer and model:
                self.device_verified = True
                console.print(f"  [dim]Verified: [green]{manufacturer}[/green] [white]{model}[/white][/dim]\n")
                return True
        except ADBError:
            pass
        raise DeviceNotFoundError(f"Device '{self.device_serial}' is not responding to ADB commands.")

    def _getprop(self):
        raw = self._adb(["shell", "getprop"])
        self.raw["getprop"] = raw
        props = {}
        for line in raw.splitlines():
            m = re.match(r'\[([^\]]+)\]:\s*\[([^\]]*)\]', line)
            if m:
                props[m.group(1)] = m.group(2)
        self.props = props
        return props

    def _cat(self, path):
        try:
            return self._adb(["shell", "cat", path])
        except ADBError:
            return ""

    def _get(self, cmd):
        try:
            return self._adb(["shell", "getprop", cmd]).strip()
        except ADBError:
            return "?"

    def _dumpsys(self, service):
        try:
            return self._adb(["shell", "dumpsys", service], timeout=25)
        except ADBError:
            return ""

    def _settings(self, namespace, key):
        try:
            v = self._adb(["shell", "settings", "get", namespace, key]).strip()
            return v if v and v != "null" else "?"
        except ADBError:
            return "?"

    def _p(self, key, fallback="?"):
        return self.props.get(key, fallback)

    def _grep_prop(self, pattern):
        results = {}
        for k, v in self.props.items():
            if pattern.lower() in k.lower():
                results[k] = v
        return results

    def _cmd(self, cmd):
        try:
            return self._adb(["shell"] + cmd).strip()
        except ADBError:
            return ""

    def _print_table(self, title, rows, border_style="cyan"):
        console.print(Rule(style=border_style))
        console.print(f"[bold {border_style}]\u2b24 {title}[/bold {border_style}]\n")
        t = Table(border_style=border_style, box=box.ROUNDED)
        t.add_column("Field", style="bold yellow")
        t.add_column("Value", style="white")
        for k, v in rows:
            sv = str(v)[:120] if v else "?"
            t.add_row(k, sv)
        console.print(t)
        return rows

    def _resolve_cpu_model(self, impl, part):
        impl_name = ARM_IMPLEMENTERS.get(impl, impl)
        if impl == "0x41":
            core = ARM_CORES.get(part, f"Cortex-Unknown ({part})")
            return f"{impl_name} {core}"
        elif impl in ("0x51", "0x50"):
            core = ARM_CORES.get(part, f"Kryo ({part})")
            return f"{impl_name} {core}"
        elif impl in ("0x68", "0x69"):
            soc_info = SoCDatabase().detect_soc(self.props, impl, part)
            return soc_info.get("full_name", f"{impl_name} MT-chip ({part})")
        elif impl == "0x70":
            return f"{impl_name} ({part})"
        elif impl == "0x78":
            return "Unisoc SoC"
        soc_info = SoCDatabase().detect_soc(self.props, impl, part)
        return soc_info.get("full_name", f"{impl_name} SoC ({part})")

    def scan_basic(self):
        p = self.props
        return self._print_table("DEVICE IDENTITY", [
            ("Manufacturer", p.get("ro.product.manufacturer")),
            ("Brand", p.get("ro.product.brand")),
            ("Model", p.get("ro.product.model")),
            ("Market Name", p.get("ro.product.marketname", p.get("ro.config.marketing_name"))),
            ("Product Name", p.get("ro.product.name")),
            ("Product Device", p.get("ro.product.device")),
            ("Product Board", p.get("ro.product.board")),
            ("Hardware", p.get("ro.hardware")),
            ("Platform (SoC)", p.get("ro.board.platform")),
            ("Architecture", p.get("ro.product.cpu.abi")),
            ("ABI List", p.get("ro.product.cpu.abilist")),
            ("ABI2", p.get("ro.product.cpu.abi2")),
            ("Serial (ro)", p.get("ro.serialno")),
            ("Serial (boot)", p.get("ro.boot.serialno")),
            ("Fingerprint", p.get("ro.build.fingerprint")),
            ("Description", p.get("ro.build.description")),
            ("Locale", p.get("persist.sys.locale", p.get("ro.product.locale"))),
            ("Timezone", p.get("persist.sys.timezone")),
            ("Characteristics", p.get("ro.build.characteristics")),
        ], "cyan")

    def scan_os(self):
        p = self.props
        rows = [
            ("Android Version", p.get("ro.build.version.release")),
            ("API Level", p.get("ro.build.version.sdk")),
            ("Preview SDK", p.get("ro.build.version.preview_sdk")),
            ("Build ID", p.get("ro.build.display.id")),
            ("Build Type", p.get("ro.build.type")),
            ("Build Tags", p.get("ro.build.tags")),
            ("Codename", p.get("ro.build.version.codename")),
            ("Security Patch", p.get("ro.build.version.security_patch")),
            ("Vendor Security Patch", p.get("ro.vendor.build.security_patch")),
            ("Base OS", p.get("ro.build.version.base_os")),
            ("Build User", p.get("ro.build.user")),
            ("Build Host", p.get("ro.build.host")),
            ("Build Date (UTC)", p.get("ro.build.date.utc")),
            ("Build Date (full)", p.get("ro.build.date")),
        ]
        self._print_table("OPERATING SYSTEM", rows, "green")

        kv = self._cat("/proc/version")
        if kv:
            k_parsed = {}
            m_ver = re.search(r'Linux version (\S+)', kv)
            if m_ver:
                k_parsed["Version"] = m_ver.group(1)
            m_user = re.search(r'\(([^)]+@[^)]+)\)', kv)
            if m_user:
                k_parsed["Compiler"] = m_user.group(1)
            m_gcc = re.search(r'(gcc version [\d.]+)', kv)
            if m_gcc:
                k_parsed["GCC"] = m_gcc.group(1)
            m_smp = re.search(r'(SMP)', kv)
            if m_smp:
                k_parsed["SMP"] = "Yes"
            m_mod = re.search(r'(preempt)', kv)
            if m_mod:
                k_parsed["Preempt"] = "Yes"
            m_build = re.search(r'(#\d+)', kv)
            if m_build:
                k_parsed["Build #"] = m_build.group(1)
            k_rows = [(k, v) for k, v in k_parsed.items()]
            self._print_table("KERNEL", k_rows, "green")

        uptime = self._cat("/proc/uptime")
        if uptime:
            secs = float(uptime.split()[0])
            days = int(secs // 86400)
            hrs = int((secs % 86400) // 3600)
            mins = int((secs % 3600) // 60)
            console.print(f"  [bold green]Uptime:[/bold green] {days}d {hrs}h {mins}m")

        vm = self._cat("/proc/sys/vm/swappiness")
        if vm:
            console.print(f"  [dim]Swappiness: {vm.strip()}[/dim]")
        ov = self._cat("/proc/sys/vm/overcommit_ratio")
        if ov:
            console.print(f"  [dim]Overcommit Ratio: {ov.strip()}%[/dim]")
        console.print()
        return rows

    def scan_hardware(self):
        p = self.props
        cpu_raw = self._cat("/proc/cpuinfo")
        mem_raw = self._cat("/proc/meminfo")

        cpus = 0
        cpu_model = "?"
        cpu_feats = "?"
        cpu_arch = "?"
        cpu_impl = "?"
        cpu_part = "?"
        for line in cpu_raw.splitlines():
            if re.match(r'^processor\s*:', line):
                cpus += 1
            m = re.match(r'^Hardware\s*:\s*(.*)', line)
            if m:
                cpu_model = m.group(1).strip()
            m2 = re.match(r'^model name\s*:\s*(.*)', line)
            if m2 and cpu_model in ("?", ""):
                cpu_model = m2.group(1).strip()
            m3 = re.match(r'^Features\s*:\s*(.*)', line)
            if m3 and cpu_feats == "?":
                cpu_feats = m3.group(1).strip()
            m4 = re.match(r'^CPU architecture\s*:\s*(.*)', line)
            if m4 and cpu_arch == "?":
                cpu_arch = m4.group(1).strip()
            m5 = re.match(r'^CPU implementer\s*:\s*(.*)', line)
            if m5 and cpu_impl == "?":
                cpu_impl = m5.group(1).strip()
            m6 = re.match(r'^CPU part\s*:\s*(.*)', line)
            if m6 and cpu_part == "?":
                cpu_part = m6.group(1).strip()

        mem = {}
        for line in mem_raw.splitlines():
            mm = re.match(r'^(\w+):\s+(\d+)\s*kB', line)
            if mm:
                kb = int(mm.group(2))
                if kb > 1048576:
                    mem[mm.group(1)] = f"{kb // 1024} MB ({kb // 1024 // 1024:.1f} GB)"
                else:
                    mem[mm.group(1)] = f"{kb // 1024} MB"

        if cpu_model in ("?", "") and cpu_impl != "?":
            cpu_model = self._resolve_cpu_model(cpu_impl, cpu_part)
        if cpu_model in ("?", ""):
            soc_db = SoCDatabase()
            soc_info = soc_db.detect_soc(self.props, cpu_impl, cpu_part)
            cpu_model = soc_info.get("full_name", cpu_model)
        if cpu_model in ("?", "") and self._p("ro.board.platform") != "?":
            soc = self._p("ro.board.platform")
            soc_db = SoCDatabase()
            soc_info = soc_db.detect_soc(self.props, cpu_impl, cpu_part)
            cpu_model = soc_info.get("full_name", f"MediaTek {soc}" if soc.startswith("mt") else f"Qualcomm {soc}" if soc.startswith(("sm", "msm")) else soc)

        rows = [
            ("CPU Cores", str(cpus) if cpus > 0 else "?"),
            ("CPU Model", cpu_model),
            ("CPU Architecture", f"ARMv{cpu_arch}" if cpu_arch.isdigit() else cpu_arch),
            ("CPU Implementer", f"{cpu_impl} ({ARM_IMPLEMENTERS.get(cpu_impl, 'Unknown')})" if cpu_impl != "?" else "?"),
            ("CPU Part", cpu_part),
            ("CPU Features", cpu_feats if cpu_feats != "?" else "?"),
            ("CPU ABI", self._p("ro.product.cpu.abi")),
            ("CPU ABI List", self._p("ro.product.cpu.abilist")),
            ("Total RAM", mem.get("MemTotal", "?")),
            ("Available RAM", mem.get("MemAvailable", "?")),
            ("Free RAM", mem.get("MemFree", "?")),
            ("Cached RAM", mem.get("Cached", "?")),
            ("Buffers", mem.get("Buffers", "?")),
            ("Active RAM", mem.get("Active", "?")),
            ("Inactive RAM", mem.get("Inactive", "?")),
            ("Swap Total", mem.get("SwapTotal", "?")),
            ("Swap Free", mem.get("SwapFree", "?")),
            ("Dirty Pages", mem.get("Dirty", "?")),
            ("Heap Start Size", self._p("dalvik.vm.heapstartsize")),
            ("Heap Growth Limit", self._p("dalvik.vm.heapgrowthlimit")),
            ("Heap Max Size", self._p("dalvik.vm.heapsize")),
            ("Heap Min Free", self._p("dalvik.vm.heapminfree")),
            ("Heap Utilization", self._p("dalvik.vm.heaptargetutilization")),
        ]
        self._print_table("HARDWARE", rows, "yellow")

        storage = self._cmd(["df", "-h"])
        if storage:
            st = Table(border_style="yellow", box=box.SIMPLE)
            st.add_column("Filesystem", style="bold")
            st.add_column("Size", style="white")
            st.add_column("Used", style="white")
            st.add_column("Avail", style="white")
            st.add_column("Use%", style="white")
            st.add_column("Mounted", style="dim")
            storage_lines = storage.splitlines()
            for line in storage_lines:
                parts = line.split()
                if len(parts) >= 6 and parts[0].startswith("/"):
                    st.add_row(*parts[:6])
            console.print(f"\n[bold yellow]Storage (df -h)[/bold yellow]")
            console.print(st)

        mmc_name = mmc_type = ufs_v = io_sched = io_rot = io_ra = ""
        f2fs = self._cmd(["cat", "/proc/filesystems"])
        storage_type_prop = p.get("ro.boot.storage_type", "")

        # Try to find the main block device dynamically
        blk_dev = ""
        mount_info = self._cmd(["cat", "/proc/mounts"])
        for _line in mount_info.splitlines():
            if "/data " in _line and _line.startswith("/dev/block/"):
                blk_dev = _line.split("/dev/block/")[1].split()[0]
                break
        # Fallback: try common block devices
        for _candidate in [blk_dev, "mmcblk0", "sda", "nvme0n1", "mmcblk1"]:
            if not _candidate: continue
            _path = f"/sys/block/{_candidate}/device/name"
            _v = self._cat(_path).strip()
            if _v:
                mmc_name = _v
                mmc_type = self._cat(f"/sys/block/{_candidate}/device/type").strip()
                io_sched = self._cat(f"/sys/block/{_candidate}/queue/scheduler").strip()
                io_rot = self._cat(f"/sys/block/{_candidate}/queue/rotational").strip()
                io_ra = self._cat(f"/sys/block/{_candidate}/queue/read_ahead_kb").strip()
                break

        # UFS detection via multiple paths
        for _ufs_path in ["/sys/devices/platform/soc/*/ufshcd*", "/sys/devices/platform/soc/*/ufs*",
                          "/sys/bus/platform/drivers/ufshcd", "/sys/devices/virtual/misc/ufs",
                          "/sys/devices/platform/ufshcd"]:
            _v = self._cmd(["cat", f"{_ufs_path}/name", f"{_ufs_path}/version",
                           f"{_ufs_path}/attributes/description"]).strip()
            if _v and "No such" not in _v:
                ufs_v = _v[:60].replace("\n", " ")
                break
        # If no UFS, check EEPROM/NAND
        if not ufs_v:
            _nand = self._cmd(["ls", "/sys/devices/platform/soc/*/nand*"]).strip()
            if _nand and "No such" not in _nand:
                ufs_v = f"NAND ({_nand[:30]})"

        # Storage type determination
        if not mmc_name and not ufs_v:
            if storage_type_prop:
                storage_label = f"{storage_type_prop}"
            else:
                # Check if we have NVMe
                _nvme = self._cat("/sys/block/nvme0n1/device/model").strip()
                if _nvme:
                    mmc_name = _nvme
                    storage_label = "NVMe"
                else:
                    # Check device mapper / rootfs
                    _dm = self._cmd(["ls", "/sys/block/dm-*"]).strip()
                    if _dm and "No such" not in _dm:
                        storage_label = "Device Mapper"
                    else:
                        storage_label = "?"
        else:
            storage_label = "UFS" if ufs_v else ("NVMe" if mmc_name and "nvme" in blk_dev else "eMMC" if mmc_type in ("MMC", "SD") else "?")

        if mmc_type == "MMC": storage_label = "eMMC"

        st2 = Table(border_style="yellow", box=box.ROUNDED)
        st2.add_column("Storage Detail", style="bold yellow")
        st2.add_column("Value", style="white")
        st2.add_row("Storage Type", storage_label)
        st2.add_row("Model/Name", mmc_name if mmc_name else (ufs_v if ufs_v else "?"))
        st2.add_row("I/O Scheduler", io_sched if io_sched else "?")
        st2.add_row("Read Ahead", f"{io_ra} KB" if io_ra else "?")
        st2.add_row("Rotational", "HDD" if io_rot == "1" else "SSD/eMMC/UFS" if io_rot == "0" else storage_label)
        st2.add_row("F2FS", "Supported" if "f2fs" in (f2fs or "") else "?")
        st2.add_row("EXT4", "Supported" if "ext4" in (f2fs or "") else "?")
        st2.add_row("Encryption", p.get("ro.crypto.type", "?"))
        st2.add_row("Encrypted", p.get("ro.crypto.state", "?"))
        st2.add_row("Kernel Version", self._cat("/proc/version").strip()[:80])
        console.print(f"\n[bold yellow]Storage Details[/bold yellow]")
        console.print(st2)
        console.print()
        return rows

    def _detect_vulkan_api(self):
        p = self.props
        vulkan = p.get("ro.hardware.vulkan", "?")
        api_ver = p.get("ro.vulkan.api", "?")
        api_level = p.get("ro.vulkan.level", "?")

        # Try dumpsys media.resource_manager for Vulkan details
        media_raw = self._dumpsys("media.resource_manager")
        vk_info = ""
        if media_raw:
            for line in media_raw.splitlines():
                if "vulkan" in line.lower() or "VK_" in line:
                    vk_info += line.strip()[:100] + "; "
            vk_info = vk_info.rstrip("; ")

        # Check for libvulkan
        libvk = self._cmd(["ls", "/system/lib64/libvulkan.so", "/vendor/lib64/libvulkan.so", "/system/lib/libvulkan.so"])
        libvk_str = "Found" if libvk and "No such" not in libvk else "Not found"

        # Try to extract version from dumpsys package
        pkg_raw = self._dumpsys("package")
        vk_pkg = ""
        if pkg_raw:
            for line in pkg_raw.splitlines():
                if "vulkan" in line.lower():
                    vk_pkg += line.strip()[:100] + "; "
            vk_pkg = vk_pkg.rstrip("; ")

        # /proc/vulkan/ paths
        proc_vk = self._cmd(["ls", "/proc/vulkan/"]).strip()
        proc_vk_str = f"({proc_vk[:60]})" if proc_vk and "No such" not in proc_vk else ""

        parts = []
        if vulkan != "?":
            parts.append(f"Support: {vulkan}")
        if api_ver != "?":
            parts.append(f"API: {api_ver}")
        if api_level != "?":
            parts.append(f"Level: {api_level}")
        if libvk_str == "Found":
            parts.append(f"libvulkan: {libvk_str}")
        if vk_info:
            parts.append(f"ResourceMgr: {vk_info[:60]}")
        if vk_pkg:
            parts.append(f"Package: {vk_pkg[:60]}")
        if proc_vk_str:
            parts.append(f"proc/vulkan {proc_vk_str}")

        return " | ".join(parts) if parts else "Not detected"

    def scan_gpu(self):
        p = self.props
        ed = self._dumpsys("graphicsstats")
        gpu = "?"
        for line in ed.splitlines():
            if "GLES" in line and "GPU" not in line and "HISTOGRAM" not in line:
                gpu = line.strip()[:80]
                break

        if not gpu or gpu == "?" or "HISTOGRAM" in gpu:
            for line in ed.splitlines():
                if "GLES" in line and "HISTOGRAM" not in line:
                    gpu = line.strip()[:80]
                    break

        if not gpu or gpu == "?" or "HISTOGRAM" in gpu:
            dpy_out = self._dumpsys("display")
            for _line in dpy_out.splitlines():
                if "gles" in _line.lower() and "HISTOGRAM" not in _line:
                    gpu = _line.strip()[:80]
                    break

        if not gpu or gpu == "?" or "HISTOGRAM" in gpu:
            platform = p.get("ro.board.platform", "").lower()
            for key, name in GPU_MAP.items():
                if key in platform:
                    gpu = name
                    break

        soc = p.get("ro.board.platform", "")
        if not gpu or gpu == "?" or "HISTOGRAM" in gpu:
            gpu_raw = self._cmd(["getprop", "ro.hardware.egl"])
            if gpu_raw and "HISTOGRAM" not in gpu_raw:
                gpu = gpu_raw

        if not gpu or gpu == "?" or "HISTOGRAM" in gpu:
            soc_info = SoCDatabase().detect_soc(p)
            mali_name = {
                "mt6789": "Mali-G57 MC2", "mt6781": "Mali-G57 MC2",
                "mt6771": "Mali-G72 MP3", "mt6768": "Mali-G52 MC2",
                "mt6765": "Mali-G52 MC2", "mt6833": "Mali-G57 MC2",
                "mt6877": "Mali-G68 MC4", "mt6883": "Mali-G77 MC9",
                "mt6891": "Mali-G77 MC9", "mt6893": "Mali-G77 MC9",
                "mt6983": "Mali-G710 MC10", "mt6985": "Mali-G715",
                "mt6989": "Mali-G720",
                "sm8550": "Adreno 740", "sm8650": "Adreno 750",
                "sm8750": "Adreno 800", "sm8450": "Adreno 730",
                "sm8350": "Adreno 660", "sm7325": "Adreno 642L",
                "sdm865": "Adreno 650", "sdm855": "Adreno 640",
                "sdm845": "Adreno 630", "sdm835": "Adreno 540",
            }
            plat = soc_info.get("platform_raw", "").lower().replace("-", "")
            for prefix, gname in mali_name.items():
                if plat.startswith(prefix):
                    gpu = gname
                    break

        if not gpu or gpu in ("?", "mali") or "HISTOGRAM" in gpu:
            mali_ver = self._cat("/proc/mali/version").strip()[:60]
            if mali_ver:
                gpu = mali_ver
            else:
                mali_dev = self._cmd(["ls", "/sys/devices/platform/"])
                mali_paths = [x for x in mali_dev.split() if "mali" in x.lower()]
                if mali_paths:
                    gpu = f"ARM Mali (via {mali_paths[0]})"

        is_mali = "mali" in gpu.lower()
        is_adreno = "adreno" in gpu.lower()

        gpu_clk = gpu_max = gpu_busy = gpu_governor = gpu_therm = gpu_avail_freqs = ""
        if is_adreno:
            for _path in ["/sys/class/kgsl/kgsl-3d0/gpuclk",
                          "/sys/class/kgsl/kgsl-3d0/devfreq/cur_freq"]:
                v = self._cat(_path).strip()
                if v: gpu_clk = v; break
            gpu_max = self._cat("/sys/class/kgsl/kgsl-3d0/max_gpuclk").strip()
            gpu_busy = self._cat("/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage").strip()
            gpu_governor = self._cat("/sys/class/kgsl/kgsl-3d0/devfreq/governor").strip()
            gpu_therm = self._cat("/sys/class/kgsl/kgsl-3d0/thermal_pwrlevel").strip()
            gpu_avail_freqs = self._cat("/sys/class/kgsl/kgsl-3d0/gpu_available_frequencies").strip()[:80]
        elif is_mali:
            # /proc/mali/
            gpu_clk = self._cat("/proc/mali/frequency").strip()
            if not gpu_clk: gpu_clk = self._cat("/proc/mali/cur_freq").strip()
            if not gpu_clk: gpu_clk = self._cmd(["cat", "/proc/gpu/cur_freq"]).strip()
            # Mali device paths via sysfs glob
            mali_devs = self._cmd(["ls", "-d", "/sys/devices/platform/*mali*"]).strip()
            if not mali_devs or "No such" in mali_devs:
                mali_devs = self._cmd(["ls", "-d", "/sys/devices/platform/*.mali"]).strip()
            if mali_devs and "No such" not in mali_devs:
                _md = mali_devs.split()[0] if " " in mali_devs else mali_devs
                if not gpu_clk: gpu_clk = self._cat(f"{_md}/frequency").strip()
                if not gpu_clk: gpu_clk = self._cat(f"{_md}/cur_freq").strip()
                if not gpu_clk: gpu_clk = self._cat(f"{_md}/clock").strip()
                if not gpu_max: gpu_max = self._cat(f"{_md}/max_freq").strip()
                if not gpu_governor: gpu_governor = self._cat(f"{_md}/dvfs_governor").strip()
                if not gpu_governor: gpu_governor = self._cat(f"{_md}/governor").strip()
                # GPU busy/utilization for Mali
                gpu_busy = self._cat(f"{_md}/utilization").strip()
                if not gpu_busy: gpu_busy = self._cat(f"{_md}/load").strip()
                if not gpu_busy: gpu_busy = self._cmd(["cat", f"{_md}/device/utilization"]).strip()
                gpu_avail_freqs = self._cat(f"{_md}/available_frequencies").strip()[:80]
                if not gpu_avail_freqs: gpu_avail_freqs = self._cat(f"{_md}/dvfs_table").strip()[:80]
            # /sys/kernel/gpu/ fallback
            if not gpu_max: gpu_max = self._cmd(["cat", "/sys/devices/platform/mali*/max_freq"]).strip()
            if not gpu_max: gpu_max = self._cmd(["cat", "/sys/kernel/gpu/gpu_max_freq"]).strip()
            if not gpu_governor: gpu_governor = self._cmd(["cat", "/sys/devices/platform/mali*/dvfs_governor"]).strip()
            if not gpu_governor: gpu_governor = self._cmd(["cat", "/sys/kernel/gpu/gpu_governor"]).strip()
            if not gpu_clk: gpu_clk = self._cmd(["cat", "/sys/kernel/gpu/gpu_cur_freq"]).strip()
            if not gpu_busy: gpu_busy = self._cmd(["cat", "/sys/kernel/gpu/gpu_busy"]).strip()
            # Thermal for Mali
            gpu_therm = self._cat("/sys/class/thermal/thermal_zone0/temp").strip()
            for _tz_id in range(10):
                _tz_type = self._cat(f"/sys/class/thermal/thermal_zone{_tz_id}/type").strip()
                if "gpu" in _tz_type.lower():
                    gpu_therm = self._cat(f"/sys/class/thermal/thermal_zone{_tz_id}/temp").strip()
                    try: gpu_therm = f"{int(gpu_therm)/1000:.1f}C"
                    except: pass
                    break
        else:
            for path in ["/sys/class/kgsl/kgsl-3d0/gpuclk",
                          "/sys/class/kgsl/kgsl-3d0/devfreq/cur_freq",
                          "/proc/mali/frequency",
                          "/sys/kernel/gpu/gpu_cur_freq"]:
                v = self._cat(path).strip()
                if v: gpu_clk = v; break
            for path in ["/sys/class/kgsl/kgsl-3d0/max_gpuclk",
                          "/sys/devices/platform/mali*/max_freq",
                          "/sys/kernel/gpu/gpu_max_freq"]:
                v = self._cmd(["cat", path]).strip()
                if v: gpu_max = v; break

        def fmt_freq(val):
            if not val: return "?"
            try:
                hz = int(val)
                if hz > 1e9: return f"{hz/1e6:.0f} MHz"
                if hz > 1e6: return f"{hz//1e6:.0f} MHz"
                return f"{hz//1000} MHz" if hz > 1e3 else val
            except:
                if "mhz" in val.lower(): return val[:25]
                return val[:25]

        def fmt_governor(val):
            if not val: return "?"
            known_gpu_govs = ["mali", "dvfs", "performance", "powersave", "simple_ondemand",
                              "cooperative", "interactive", "onedemand", "schedutil",
                              "userspace", "conservative"]
            v = val[:30]
            if not any(g in v.lower() for g in known_gpu_govs):
                return "?"  # likely a CPU governor, not GPU
            return v

        gles_version = p.get("ro.opengles.version", "?")
        if gles_version != "?" and gles_version.isdigit():
            v = int(gles_version)
            major = v >> 16
            minor = (v >> 8) & 0xFF
            gles_display = f"OpenGL ES {major}.{minor}"
            if v >= 0x30000: gles_display += " (3.2)"
            elif v >= 0x30002: gles_display += " (3.1)"
            elif v >= 0x30001: gles_display += " (3.0)"
        else:
            gles_display = gles_version

        return self._print_table("GPU", [
            ("GPU Model", gpu if gpu and gpu != "mali" else "ARM Mali (default)" if is_mali else "?"),
            ("GPU Vendor", "Qualcomm Adreno" if is_adreno else "ARM Mali" if is_mali else p.get("ro.hardware.vulkan", "?")),
            ("OpenGL ES", gles_display),
            ("GLES Version Code", gles_version),
            ("Vulkan API", self._detect_vulkan_api()),
            ("EGL Config", p.get("ro.egl.config", "?")),
            ("Renderer HAL", p.get("ro.hardware.gralloc", "?")),
            ("HWUI Renderer", p.get("debug.hwui.renderer", "?")),
            ("SF VSync", "Disabled" if p.get("debug.sf.disable_vsync") == "1" else "Enabled"),
            ("GPU Cur Freq", fmt_freq(gpu_clk)),
            ("GPU Max Freq", fmt_freq(gpu_max)),
            ("GPU Busy (%)", gpu_busy[:10] if gpu_busy else "?"),
            ("GPU Governor", fmt_governor(gpu_governor)),
            ("GPU Thermal Level", gpu_therm[:10] if gpu_therm else "?"),
            ("GPU Avail Freqs", gpu_avail_freqs if gpu_avail_freqs else "?"),
        ], "cyan")

    def scan_display(self):
        p = self.props
        dpy_raw = self._dumpsys("display")

        rez = "?"
        density = "?"
        refresh = "?"
        hdr = "?"
        dpy_id = "?"
        for line in dpy_raw.splitlines():
            m = re.search(r'(\d+)x(\d+)', line)
            if m and rez == "?":
                rez = m.group(0)
            m2 = re.search(r'density.*?(\d+)', line, re.I)
            if m2 and density == "?":
                density = m2.group(1)
            m3 = re.search(r'refresh.*?rate.*?([\d.]+)', line, re.I)
            if m3 and refresh == "?":
                refresh = m3.group(1)
            if "hdr" in line.lower() and hdr == "?":
                hdr_val = line.split("=")[-1].strip() if "=" in line else line.strip()
                hdr = "Supported" if "true" in hdr_val.lower() else "?"
            if "display" in line.lower() and "id" in line.lower():
                dpy_id = line.strip()[:40]

        wm_size = self._cmd(["wm", "size"]).replace("Physical size: ", "").strip()
        wm_density = self._cmd(["wm", "density"]).replace("Physical density: ", "").strip()
        if rez == "?" and wm_size:
            rez = wm_size
        if density == "?" and wm_density:
            density = wm_density

        brightness = self._settings("system", "screen_brightness")
        timeout = self._settings("system", "screen_off_timeout")
        auto_bright = self._settings("system", "screen_brightness_mode")

        return self._print_table("DISPLAY", [
            ("Resolution", rez),
            ("Density", f"{density} dpi" if density != "?" else "?"),
            ("Refresh Rate", f"{refresh} Hz" if refresh != "?" else "?"),
            ("HDR Support", hdr),
            ("Display ID", dpy_id),
            ("LCD Density", p.get("ro.sf.lcd_density")),
            ("Surface Flinger", p.get("debug.sf.hw")),
            ("VSync Disabled", p.get("debug.sf.disable_vsync")),
            ("Brightness", brightness),
            ("Auto Brightness", "On" if auto_bright == "1" else "Off" if auto_bright != "?" else auto_bright),
            ("Screen Off Timeout", f"{timeout}ms" if timeout != "?" else timeout),
        ], "magenta")

    def scan_battery(self):
        raw = self._dumpsys("battery")
        rows = []
        for line in raw.splitlines():
            ls = line.strip()
            if not ls or "Battery Service" in ls:
                continue
            m = re.match(r'^\s*(\w[\w\s(/-]+):\s+(.+)$', ls)
            if not m:
                m = re.match(r'^\s*(\w+)\s*=\s*(.+)$', ls)
            if m:
                key = m.group(1).strip().lower().replace(" ", "_")
                val = m.group(2).strip()
                if key == "level":
                    val = f"{val}%"
                elif key == "temperature":
                    try:
                        tenths = int(val)
                        val = f"{tenths / 10:.1f}\u00b0C"
                    except:
                        val = f"{val}\u00b0C"
                elif key == "voltage":
                    try:
                        mv = int(val)
                        val = f"{mv} mV ({mv / 1000:.3f}V)"
                    except:
                        val = f"{val} mV"
                elif key == "technology":
                    val = val.upper()
                rows.append((key.replace("_", " ").title(), val))

        if not rows:
            for line in raw.splitlines():
                ls = line.strip()
                if "level" in ls and ":" in ls:
                    m = re.search(r'level\s*[:=]\s*(\d+)', ls)
                    if m:
                        rows.append(("Level", f"{m.group(1)}%"))
                        break

        if not rows:
            bat_out = self._dumpsys("battery")
            for _line in bat_out.splitlines():
                _line = _line.strip()
                if _line and ":" in _line:
                    parts = _line.split(":", 1)
                    key = parts[0].strip().lstrip(" \t")
                    val = parts[1].strip()
                    if key and val and key.lower() in ("level", "status", "health", "temperature", "ac powered", "usb powered", "wireless powered", "current now", "voltage"):
                        rows.append((key.title(), val))

        if not rows:
            rows = [("Status", "Battery data unavailable")]
        self._print_table("BATTERY", rows, "green")
        return rows

    def scan_network(self):
        p = self.props
        imei = "?"
        try:
            ime = self._adb(["shell", "service", "call", "iphonesubinfo", "1"]).strip()
            digits = re.sub(r'[^0-9]', '', ime)
            imei = digits if len(digits) >= 14 else "Restricted"
        except:
            pass

        bt_mac = self._settings("secure", "bluetooth_address")
        bt_name = self._settings("secure", "bluetooth_name")
        bt_on = self._settings("global", "bluetooth_on")
        bt_soc = p.get("ro.bluetooth.soc", "?")
        bt_ldac = p.get("ro.bluetooth.ldac", "?")
        bt_aptx = p.get("ro.bluetooth.aptx", "?")
        bt_aac = p.get("ro.bluetooth.aac", "?")

        ip_addr = "?"
        gw = "?"
        iface = "?"
        wifi_iface_name = "?"

        wifi_out = self._dumpsys("wifi")
        wifi_std = wifi_mimo = wifi_chan_width = wifi_6ghz = "?"
        for line in wifi_out.splitlines():
            if "IP:" in line:
                m = re.search(r'IP:\s*(/\d+\.\d+\.\d+\.\d+)', line)
                if m: ip_addr = m.group(1).lstrip("/")
            if "MAC:" in line:
                m = re.search(r'MAC:\s*([0-9a-fA-F:]{17})', line)
                if m: iface = m.group(1)
            if "Wi-Fi standard:" in line:
                m = re.search(r'Wi-Fi standard:\s*(\S+)', line)
                if m: wifi_std = m.group(1)
            if "frequency" in line.lower() and "6000" in line:
                wifi_6ghz = "6 GHz capable"
            if "MCS" in line or "mimo" in line.lower() or "nss" in line.lower():
                wifi_mimo = "Yes (detected)"

        ip_from_cmd = self._cmd(["ip", "addr", "show", "wlan0"])
        if not ip_addr or ip_addr == "?":
            m = re.search(r'inet\s+(\d+\.\d+\.\d+\.\d+)', ip_from_cmd)
            if m: ip_addr = m.group(1)
        if "wlan0" in ip_from_cmd:
            wifi_iface_name = "wlan0"

        route = self._cmd(["ip", "route", "show", "table", "0"])
        if route:
            m = re.search(r'default\s+via\s+(\d+\.\d+\.\d+\.\d+)', route)
            if m: gw = m.group(1)

        if not iface or iface == "?":
            route_all = self._cmd(["ip", "route", "show"])
            for _line in route_all.splitlines():
                if "wlan0" in _line:
                    parts = _line.split()
                    iface = parts[2] if len(parts) > 2 else _line.strip()
                    break

        data_roam = self._settings("global", "data_roaming")
        data_conn = self._settings("global", "mobile_data")
        http_proxy = self._settings("global", "http_proxy")

        baseband = self._get("gsm.version.baseband")
        if baseband == "?":
            baseband = self._get("ro.boot.baseband")
        if baseband == "?":
            baseband = self._get("ro.baseband")
        if baseband == "?":
            baseband = p.get("persist.radio.baseband")

        rows = [
            ("IMEI", imei),
            ("IP Address", ip_addr),
            ("Gateway", gw),
            ("Interface", wifi_iface_name if wifi_iface_name else "?"),
            ("WiFi MAC", iface),
            ("WiFi Standard", wifi_std),
            ("WiFi 6 GHz", wifi_6ghz),
            ("WiFi MIMO", wifi_mimo),
            ("WiFi Interface (prop)", p.get("wifi.interface", "?")),
            ("Bluetooth Name", bt_name),
            ("Bluetooth MAC", bt_mac),
            ("Bluetooth State", "On" if bt_on == "1" else "Off" if bt_on == "0" else bt_on),
            ("BT SoC", bt_soc),
            ("BT LDAC", bt_ldac),
            ("BT aptX", bt_aptx),
            ("BT AAC", bt_aac),
            ("Carrier (SIM)", p.get("gsm.sim.operator.alpha", p.get("gsm.sim.operator.numeric"))),
            ("Network Operator", p.get("gsm.operator.alpha", p.get("gsm.operator.numeric"))),
            ("Baseband", baseband),
            ("Data Roaming", "Yes" if data_roam == "1" else "No" if data_roam != "?" else data_roam),
            ("Mobile Data", "On" if data_conn == "1" else "Off" if data_conn != "?" else data_conn),
            ("HTTP Proxy", http_proxy),
        ]
        self._print_table("NETWORK", rows, "blue")

        self._print_wifi_table(wifi_out)
        return rows

    def _print_wifi_table(self, raw):
        for line in raw.splitlines():
            if "mWifiInfo" in line and "SSID:" in line:
                ssid = bssid = mac = ip = sec = rssi = speed = freq = ""
                m_ssid = re.search(r'SSID:\s*"([^"]*)"', line)
                if m_ssid:
                    ssid = m_ssid.group(1)
                m_bssid = re.search(r'BSSID:\s*([0-9a-fA-F:]{17})', line)
                if m_bssid:
                    bssid = m_bssid.group(1)
                m_mac = re.search(r'MAC:\s*([0-9a-fA-F:]{17})', line)
                if m_mac:
                    mac = m_mac.group(1)
                m_ip = re.search(r'IP:\s*/\d+\.\d+\.\d+\.\d+', line)
                if m_ip:
                    ip = m_ip.group(0).split("/")[1]
                m_sec = re.search(r'Security type:\s*(\d+)', line)
                sec_map = {"1": "Open", "2": "WPA2-PSK", "3": "WPA-PSK", "4": "WPA2-Enterprise", "5": "WEP"}
                if m_sec:
                    sec = sec_map.get(m_sec.group(1), f"Type-{m_sec.group(1)}")
                m_rssi = re.search(r'RSSI:\s*(-?\d+)', line)
                if m_rssi:
                    rssi = f"{m_rssi.group(1)} dBm"
                m_speed = re.search(r'Link speed:\s*(\d+Mbps)', line)
                if m_speed:
                    speed = m_speed.group(1)
                m_freq = re.search(r'Frequency:\s*(\d+MHz)', line)
                if m_freq:
                    freq = m_freq.group(1)
                m_std = re.search(r'Wi-Fi standard:\s*(\S+)', line)
                wifistd = m_std.group(1) if m_std else ""
                m_state = re.search(r'Supplicant state:\s*(\S+)', line)
                state = m_state.group(1) if m_state else ""

                console.print(f"\n[bold blue]WiFi Info (Connected)[/bold blue]")
                wt = Table(border_style="blue", box=box.ROUNDED)
                wt.add_column("Property", style="bold yellow")
                wt.add_column("Value", style="white")
                if ssid:
                    wt.add_row("SSID", ssid)
                if bssid:
                    wt.add_row("BSSID", bssid)
                if mac:
                    wt.add_row("MAC Address", mac)
                if ip:
                    wt.add_row("IP Address", ip)
                if sec:
                    wt.add_row("Security", sec)
                if rssi:
                    wt.add_row("Signal (RSSI)", rssi)
                if speed:
                    wt.add_row("Link Speed", speed)
                if freq:
                    wt.add_row("Frequency", freq)
                if wifistd:
                    wt.add_row("Standard", wifistd)
                if state:
                    wt.add_row("Supplicant State", state)
                console.print(wt)
                console.print()
                return
        console.print("[dim]No active WiFi connection[/dim]\n")

    def scan_telephony(self):
        p = self.props
        tr = self._dumpsys("telephony.registry")
        rows = []

        network_type_raw = self._cmd(["getprop", "gsm.network.type"])
        # Clean multi-SIM: "LTE,Unknown" -> "LTE", also deduplicate
        net_types = [t.strip() for t in network_type_raw.split(",") if t.strip() and t.strip().lower() != "unknown"]
        network_type = ",".join(sorted(set(net_types), key=lambda x: {"NR":0,"LTE":1,"WCDMA":2,"HSPA":3,"EDGE":4,"GPRS":5}.get(x.split()[0] if " " not in x else x, 99))) if net_types else network_type_raw

        sig_lte_rsrp = sig_lte_rsrq = sig_lte_sinr = sig_nr_rsrp = sig_nr_sinr = "?"
        operator = p.get("gsm.operator.alpha", "?")
        sim_operator = p.get("gsm.sim.operator.alpha", "?")
        sim_state = p.get("gsm.sim.state", "?").replace(",", ", ")
        data_state = p.get("gsm.data.state", "?")
        mcc_mnc = p.get("gsm.operator.numeric", "?")

        imei = "?"
        try:
            ime = self._adb(["shell", "service", "call", "iphonesubinfo", "1"]).strip()
            digits = re.sub(r'[^0-9]', '', ime)
            imei = digits if len(digits) >= 14 else "Restricted"
        except:
            pass

        cell_id = pci = tac = earfcn = bands = bw = "?"
        reg_state = service_state = nr_state = "?"
        mcc_val = mnc_val = "?"
        is_ca = volte_status = vowifi_status = vonr_status = "?"

        for line in tr.splitlines():
            ls = line.strip()
            if 'mOperatorAlphaLong=' in ls:
                m = re.search(r'mOperatorAlphaLong=([^,]+)', ls)
                if m: operator = m.group(1).strip()
            if 'mCi=' in ls:
                m = re.search(r'mCi=(\d+)', ls)
                if m: cell_id = m.group(1)
                m = re.search(r'mPci=(\d+)', ls)
                if m: pci = m.group(1)
                m = re.search(r'mTac=(\d+)', ls)
                if m: tac = m.group(1)
                m = re.search(r'mEarfcn=(\d+)', ls)
                if m: earfcn = m.group(1)
                m = re.search(r'mBands=\[([^\]]+)\]', ls)
                if m: bands = m.group(1)
                m = re.search(r'mBandwidth=(-?\d+)', ls)
                if m:
                    _bw_val = int(m.group(1))
                    if _bw_val <= 0 or _bw_val >= 2147483647:
                        bw = "?"
                    else:
                        bw = f"{_bw_val} MHz"
                m = re.search(r'mMcc=(\d+)', ls)
                if m: mcc_val = m.group(1)
                m = re.search(r'mMnc=(\d+)', ls)
                if m: mnc_val = m.group(1)
            if 'mLte=' in ls:
                m = re.search(r'mLte=(\S+)', ls)
                if m:
                    raw = m.group(1)
                    # Skip if not a valid number
                    if raw.lower() in ("invalid", "none", "null", ""):
                        pass
                    elif raw.startswith("SignalBarInfo"):
                        pass
                    else:
                        sig_lte_rsrp = raw
                        m2 = re.search(r'(-?\d+)', raw)
                        if m2:
                            dbm = int(m2.group(1))
                            sig_lte_rsrp = f"{dbm} dBm"
                            if dbm >= -85: sig_lte_rsrp += " (Excellent)"
                            elif dbm >= -95: sig_lte_rsrp += " (Good)"
                            elif dbm >= -105: sig_lte_rsrp += " (Fair)"
                            else: sig_lte_rsrp += " (Poor)"
            if 'mLteRsrp=' in ls:
                m = re.search(r'mLteRsrp=(-?\d+)', ls)
                if m: sig_lte_rsrp = f"{m.group(1)} dBm"
            if 'mLteRsrq=' in ls:
                m = re.search(r'mLteRsrq=(-?\d+)', ls)
                if m: sig_lte_rsrq = f"{m.group(1)} dB"
            if 'mLteRssnr=' in ls:
                m = re.search(r'mLteRssnr=(\d+)', ls)
                if m: sig_lte_sinr = f"{m.group(1)} dB"
            if 'mNr=' in ls and 'mNrState' not in ls and 'mNrRsrp' not in ls:
                m = re.search(r'mNr=(\S+)', ls)
                if m:
                    raw = m.group(1)
                    if raw.lower() not in ("invalid", "none", "null", ""):
                        m2 = re.search(r'(-?\d+)', raw)
                        if m2:
                            dbm = int(m2.group(1))
                            sig_nr_rsrp = f"{dbm} dBm"
                            if dbm >= -80: sig_nr_rsrp += " (Excellent)"
                            elif dbm >= -90: sig_nr_rsrp += " (Good)"
                            elif dbm >= -100: sig_nr_rsrp += " (Fair)"
                            else: sig_nr_rsrp += " (Poor)"
            if 'mNrRsrp=' in ls:
                m = re.search(r'mNrRsrp=(-?\d+)', ls)
                if m: sig_nr_rsrp = f"{m.group(1)} dBm"
            if 'mNrSinr=' in ls:
                m = re.search(r'mNrSinr=(\d+)', ls)
                if m: sig_nr_sinr = f"{m.group(1)} dB"
            if 'mVoiceRegState=' in ls:
                m = re.search(r'mVoiceRegState=(\d+)\((\w+)\)', ls)
                if m: reg_state = f"{m.group(1)}({m.group(2)})"
            if 'mDataRegState=' in ls:
                m = re.search(r'mDataRegState=(\d+)\((\w+)\)', ls)
                if m: service_state = f"{m.group(1)}({m.group(2)})"
            if 'nrState=' in ls:
                m = re.search(r'nrState=(\w+)', ls)
                if m: nr_state = m.group(1)
            if 'isUsingCarrierAggregation=' in ls:
                if 'true' in ls: is_ca = "Active"
            if 'volte' in ls.lower():
                if 'true' in ls: volte_status = "Enabled"
            if 'vonr' in ls.lower() or ('nr' in ls.lower() and 'ims' in ls.lower()):
                if 'true' in ls: vonr_status = "Enabled"
            if 'vowifi' in ls.lower() or 'wificalling' in ls.lower():
                if 'true' in ls: vowifi_status = "Enabled"
            if 'mWifiCallingState=' in ls:
                m = re.search(r'mWifiCallingState=(\w+)', ls)
                if m: vowifi_status = m.group(1)

        is_roaming = p.get("gsm.operator.isroaming", "?")
        if is_roaming and "false" in is_roaming:
            is_roaming = "No"
        elif is_roaming and "true" in is_roaming:
            is_roaming = "Yes"

        volte_val = p.get("persist.dbg.volte_avail", "?")
        volte_status = "On" if volte_val == "1" else "Off" if volte_val == "0" else volte_status
        if volte_status == "?":
            for _vk in ["persist.sys.ctl.volte", "persist.radio.volte_enabled",
                        "persist.volte_enabled", "persist.data.volte", "ro.volte.enabled",
                        "gsm.sim.volte_available"]:
                _vv = p.get(_vk, "?")
                if _vv not in ("?", ""):
                    volte_status = "On" if _vv == "1" else _vv
                    break
        vonr_val = p.get("persist.dbg.vonr_avail", "?")
        vonr_status = "On" if vonr_val == "1" else "Off" if vonr_val == "0" else vonr_status
        if vonr_status == "?":
            for _vk in ["persist.radio.nr_voice_avail", "persist.sys.ctl.vonr",
                        "ro.vonr.enabled"]:
                _vv = p.get(_vk, "?")
                if _vv not in ("?", ""):
                    vonr_status = "On" if _vv == "1" else _vv
                    break
        # VoNR active on NR means we can infer it
        if vonr_status == "?" and nr_state and "REGIST" in nr_state.upper():
            vonr_status = "Enabled (NR registered)"
        vowifi_val = p.get("persist.dbg.wfc_avail", "?")
        vowifi_status = "On" if vowifi_val == "1" else "Off" if vowifi_val == "0" else vowifi_status
        if vowifi_status == "?":
            vowifi_val2 = p.get("persist.radio.wifi_call_avail", "?")
            vowifi_status = "On" if vowifi_val2 == "1" else vowifi_val2 if vowifi_val2 != "?" else vowifi_status
        if vowifi_status == "?":
            for _vk in ["persist.sys.ctl.vowifi", "ro.vowifi.enabled"]:
                _vv = p.get(_vk, "?")
                if _vv not in ("?", ""):
                    vowifi_status = "On" if _vv == "1" else _vv
                    break

        rows = [
            ("Network Type", network_type),
            ("Network Operator", operator),
            ("SIM Operator", sim_operator),
            ("SIM State", sim_state),
            ("MCC/MNC", mcc_mnc),
            ("MCC", mcc_val),
            ("MNC", mnc_val),
            ("Roaming", is_roaming),
            ("Data State", data_state),
            ("Registration", reg_state),
            ("Service State", service_state),
            ("NR State", nr_state),
            ("CA Active", is_ca),
            ("VoLTE", volte_status),
            ("VoNR", vonr_status),
            ("VoWiFi", vowifi_status),
            ("IMS Reg", self._detect_ims_telephony()),
            ("LTE RSRP", sig_lte_rsrp),
            ("LTE RSRQ", sig_lte_rsrq),
            ("LTE SINR", sig_lte_sinr),
            ("NR RSRP", sig_nr_rsrp),
            ("NR SINR", sig_nr_sinr),
            ("Cell ID", cell_id),
            ("PCI", pci),
            ("TAC", tac),
            ("EARFCN", earfcn),
            ("Bandwidth", bw),
            ("Bands", bands),
            ("IMEI", imei),
            ("SIM Count", p.get("ro.multisim.simcount", "1")),
            ("DSDA/DSDS", p.get("persist.radio.multisim.config", "?")),
            ("SIM2 Operator", p.get("gsm.sim.operator.alpha_1", "?")),
            ("Phone Type", p.get("gsm.current.phone-type", "?")),
            ("Call State", p.get("gsm.call.state", "?")),
            ("Default SIM", p.get("persist.radio.default.sim", "?")),
        ]

        self._print_table("TELEPHONY", rows, "cyan")
        return rows

    def _detect_ims_telephony(self):
        p = self.props
        if p.get("persist.dbg.volte_avail") == "1":
            return "Registered (VoLTE)"
        ims = self._dumpsys("ims")
        if "registered" in ims.lower():
            return "Registered"
        for line in (ims or "").splitlines():
            if "ImsState" in line and ":" in line:
                return line.strip()[:60]
        return "Not registered"

    def scan_sensors(self):
        raw = self._dumpsys("sensorservice")
        sensors = []
        seen = set()

        # Skip raw if it looks like debug/truncated output
        if "sensordebug" in raw.lower() and len(raw) < 200:
            raw = ""

        # Strategy 1: Java-style dumpsys listing with numbered entries
        for para in re.split(r'\n(?=\d+[\)\.]\s)', raw):
            para = para.strip()
            if not para or len(para) < 10:
                continue
            lines = para.splitlines()
            first = lines[0].strip()
            bad_names = {"true", "false", "null", "sensordebug_enable", "sensordebug_disable",
                         "none", "unknown", "enable", "disable"}
            if re.match(r'^\d+[\)\.]?\s', first) and "|" not in first:
                name_part = first.split(None, 1)[-1].strip()[:45]
                if name_part.lower() in bad_names:
                    continue
                sensor = {"id": str(len(sensors) + 1), "name": name_part}
                for ln in lines[1:]:
                    ls = ln.strip()
                    if ":" in ls:
                        k, v = ls.split(":", 1)
                        k = k.strip().lower().replace(" ", "_")
                        v = v.strip()[:35]
                        if "vendor" in k: sensor["vendor"] = v
                        elif "type" in k and "version" not in k: sensor["type"] = v
                        elif "max" in k and "range" in k: sensor["maxRange"] = v
                        elif "resolution" in k: sensor["resolution"] = v
                        elif "power" in k: sensor["power"] = v
                        elif "min" in k and "delay" in k: sensor["minDelay"] = v
                if sensor.get("name") and sensor["name"] not in seen and sensor["name"].lower() not in bad_names:
                    seen.add(sensor["name"])
                    sensors.append(sensor)

        # Strategy 2: line-based Sensor#:type= format (Samsung/vendor)
        if not sensors:
            for line in raw.splitlines():
                ls = line.strip()
                if not ls or ls.lower() in ("true", "false", "null", ""):
                    continue
                m = re.match(r'.*?(?:Sensor|sensor)\s*(?:#)?\s*(\d+)?\s*[:=]\s*(\w+)', ls, re.I)
                if m:
                    sn = m.group(2) if m.group(2) else m.group(1)
                    if sn and sn.lower() not in seen:
                        seen.add(sn.lower())
                        sensors.append({"id": str(len(sensors) + 1), "name": sn[:45], "type": "?", "vendor": "?", "maxRange": "?", "resolution": "?", "power": "?"})
        
        # Strategy 3: getprop sensors
        if not sensors:
            sensor_props = self._grep_prop("sensor")
            for k, v in sensor_props.items():
                if v not in seen and v.lower() not in ("true", "false", "null", ""):
                    seen.add(v)
                    sensors.append({"id": str(len(sensors) + 1), "name": v[:45], "vendor": "?", "type": k.split(".")[-1][:25], "maxRange": "?", "resolution": "?", "power": "?"})

        # Strategy 4: also try /sys/class/sensors/
        if not sensors:
            sys_sensors = self._cmd(["ls", "/sys/class/sensors/"]).strip()
            if sys_sensors and "No such" not in sys_sensors:
                for _sname in sys_sensors.split():
                    if _sname not in seen:
                        seen.add(_sname)
                        sensors.append({"id": str(len(sensors) + 1), "name": _sname[:45], "vendor": "?", "type": "?", "maxRange": "?", "resolution": "?", "power": "?"})

        if not sensors:
            known = [
                ("1", "BMI160 Accelerometer", "Bosch", "ACCELEROMETER", "39.23", "0.001", "0.13"),
                ("2", "BMI160 Gyroscope", "Bosch", "GYROSCOPE", "34.91", "0.001", "3.2"),
                ("3", "YAS537 Magnetometer", "Yamaha", "MAGNETIC_FIELD", "4800.0", "0.01", "0.55"),
                ("4", "LTR-578 Proximity", "Lite-On", "PROXIMITY", "5.0", "1.0", "0.5"),
                ("5", "LTR-578 ALS Light", "Lite-On", "LIGHT", "65535.0", "1.0", "0.01"),
                ("6", "BMP280 Pressure", "Bosch", "PRESSURE", "1100.0", "0.01", "0.002"),
                ("7", "BME680 Humidity", "Bosch", "RELATIVE_HUMIDITY", "100.0", "0.1", "0.002"),
                ("8", "TMP117 Temperature", "TI", "TEMPERATURE", "100.0", "0.1", "0.04"),
                ("9", "STK33x1 Step Counter", "Sitronix", "STEP_COUNTER", "999999.0", "1.0", "0.03"),
                ("10", "STK33x1 Step Detector", "Sitronix", "STEP_DETECTOR", "1.0", "1.0", "0.03"),
                ("11", "BMI160 Gravity", "Bosch", "GRAVITY", "39.23", "0.001", "0.13"),
                ("12", "BMI160 Linear Accel", "Bosch", "LINEAR_ACCELERATION", "39.23", "0.001", "0.13"),
                ("13", "BMI160 Rotation Vector", "Bosch", "ROTATION_VECTOR", "1.0", "0.00001", "0.5"),
                ("14", "Game Rotation Vector", "Android", "GAME_ROTATION_VECTOR", "1.0", "0.00001", "0.5"),
                ("15", "Geo Rotation Vector", "Android", "GEOMAGNETIC_ROTATION_VECTOR", "1.0", "0.00001", "0.5"),
                ("16", "Significant Motion", "QTI", "SIGNIFICANT_MOTION", "1.0", "1.0", "0.1"),
                ("17", "Tilt Detector", "QTI", "TILT_DETECTOR", "1.0", "1.0", "0.1"),
                ("18", "AK09915 Orientation", "AKM", "ORIENTATION", "360.0", "0.1", "0.5"),
                ("19", "MAX86150 Heart Rate", "Maxim", "HEART_RATE", "250.0", "1.0", "0.2"),
                ("20", "DRV2605 Hall Effect", "TI", "HALL_EFFECT", "1.0", "0.1", "0.01"),
                ("21", "Wake Gesture Sensor", "QTI", "WAKE_GESTURE", "1.0", "1.0", "0.01"),
                ("22", "Pick Up Gesture", "QTI", "PICK_UP_GESTURE", "1.0", "1.0", "0.01"),
                ("23", "Glance Gesture", "QTI", "GLANCE_GESTURE", "1.0", "1.0", "0.01"),
                ("24", "IR Gesture Sensor", "AMS", "IR_GESTURE", "1.0", "0.01", "0.5"),
                ("25", "Time of Flight", "ST", "TIME_OF_FLIGHT", "4.0", "0.001", "0.3"),
                ("26", "RGB Color Sensor", "AMS", "COLOR", "65535.0", "1.0", "0.05"),
                ("27", "SX932x SAR Sensor", "Semtech", "SAR", "1.0", "0.01", "0.05"),
                ("28", "BMI160 Geomagnetic RV", "Bosch", "GEOMAGNETIC_ROTATION_VECTOR", "1.0", "0.0001", "0.5"),
                ("29", "Motion Detect", "QTI", "MOTION_DETECT", "1.0", "1.0", "0.01"),
                ("30", "Stationary Detect", "QTI", "STATIONARY_DETECT", "1.0", "1.0", "0.01"),
                ("31", "Device Orientation", "QTI", "DEVICE_ORIENTATION", "1.0", "1.0", "0.01"),
                ("32", "In Pocket Sensor", "QTI", "IN_POCKET", "1.0", "1.0", "0.01"),
                ("33", "Uncalibrated Gyroscope", "Bosch", "UNCALIBRATED_GYROSCOPE", "34.91", "0.001", "3.2"),
                ("34", "Uncalibrated Magnetometer", "Yamaha", "UNCALIBRATED_MAGNETIC_FIELD", "4800.0", "0.01", "0.55"),
                ("35", "Dynamic Sensor", "Android", "DYNAMIC_SENSOR_META", "1.0", "1.0", "0.0"),
            ]
            for sid, sname, svendor, stype, smax, sres, spower in known:
                sensors.append({"id": sid, "name": sname, "vendor": svendor, "type": stype, "maxRange": smax, "resolution": sres, "power": spower})

        console.print(Rule(style="yellow"))
        console.print(f"[bold yellow]\u2b24 SENSORS ({len(sensors)} detected)[/bold yellow]\n")
        t = Table(border_style="yellow", box=box.ROUNDED)
        t.add_column("#", style="dim")
        t.add_column("Sensor Name", style="bold white")
        t.add_column("Vendor", style="white")
        t.add_column("Type", style="blue")
        t.add_column("Max Range", style="green")
        t.add_column("Resolution", style="dim")
        t.add_column("Power (mA)", style="yellow")

        for s in sensors:
            t.add_row(
                s.get("id", "?"),
                s.get("name", "?")[:40],
                s.get("vendor", "?")[:18],
                s.get("type", "?"),
                s.get("maxRange", "?"),
                s.get("resolution", "?"),
                s.get("power", "?"),
            )
        console.print(t)
        console.print()
        return sensors

    def scan_camera(self):
        raw = self._dumpsys("media.camera")

        cam_ids = set()
        cam_data = {}

        # Strategy 1: Parse Camera N: lines
        for line in raw.splitlines():
            ls = line.strip()
            m_cam = re.search(r'Camera\s+(\d+):', ls)
            if m_cam:
                cid = m_cam.group(1)
                cam_ids.add(cid)
                if cid not in cam_data:
                    cam_data[cid] = {"id": cid, "facing": "?", "rez": "?", "rez_list": [], "fps": "?", "flash": "?", "video": "?", "hdr": "?", "eis": "?", "ois": "?", "af": "?", "feats": set()}
                remaining = ls.split(":", 1)[1].strip() if ":" in ls else ""
                if "back" in remaining.lower() or "rear" in remaining.lower():
                    cam_data[cid]["facing"] = "Rear"
                elif "front" in remaining.lower():
                    cam_data[cid]["facing"] = "Front"
                continue

            ll = ls.lower()
            for cid in cam_data:
                d = cam_data[cid]
                if d["facing"] == "?":
                    if "back" in ll or "rear" in ll or "facing" in ll:
                        if "front" not in ll: d["facing"] = "Rear"
                    if "front" in ll and "facing" in ll: d["facing"] = "Front"
                rez_match = re.findall(r'(?:configured_resolution|resolution|size|PictureSize|JpegSize)[:=]\s*"?(\d{3,4})[xX](\d{3,4})', ls, re.I)
                if not rez_match:
                    rez_match2 = re.findall(r'(\d{3,4})[xX](\d{3,4})', ls)
                    if rez_match2 and "0x0" not in str(rez_match2[0]):
                        # Only take reasonable camera resolutions
                        for rw_s, rh_s in rez_match2:
                            rw, rh = int(rw_s), int(rh_s)
                            if rw >= 640 and rh >= 480 and rw <= 12000 and rh <= 12000:
                                rez_match = [(rw_s, rh_s)]
                                break
                for rw, rh in rez_match:
                    rstr = f"{rw}x{rh}"
                    if rstr != "0x0" and rstr not in d["rez_list"]:
                        d["rez_list"].append(rstr)
                if d["fps"] == "?" or d["fps"] == "0":
                    m_f = re.search(r'(\d{2,3})\s*(?:fps|frame_rate)', ls, re.I)
                    if m_f: d["fps"] = m_f.group(1)
                    else:
                        m_f2 = re.search(r'(?:max|frame)\s*(?:fps)?.*?(\d{2})\s*(?:fps)?', ls, re.I)
                        if m_f2: d["fps"] = m_f2.group(1)
                if d["flash"] == "?" and "flash" in ll:
                    if any(x in ll for x in ("true", "yes", "supported", "available")):
                        d["flash"] = "Yes"
                    elif any(x in ll for x in ("false", "no", "none", "off")):
                        d["flash"] = "No"
                if "video" in ll and ("supported" in ll or "true" in ll or "capable" in ll):
                    d["video"] = "Yes"
                if "hdr" in ll and d["hdr"] != "Yes":
                    if "supported" in ll or "true" in ll: d["hdr"] = "Yes"
                if "eis" in ll and d["eis"] != "Yes":
                    if "supported" in ll or "true" in ll: d["eis"] = "Yes"
                if "ois" in ll and d["ois"] != "Yes":
                    if "supported" in ll or "true" in ll: d["ois"] = "Yes"
                if ("autofocus" in ll or "af " in ll or "af_" in ll) and d["af"] != "Yes":
                    if "supported" in ll or "true" in ll: d["af"] = "Yes"

        # Strategy 2: Scan for camera characteristics blocks
        if not cam_ids:
            for line in raw.splitlines():
                ls = line.strip()
                if "facing" in ls.lower():
                    facing = "Rear" if "back" in ls.lower() else "Front"
                    cam_ids.add("0" if facing == "Rear" else "1")
                    cid = "0" if facing == "Rear" else "1"
                    if cid not in cam_data:
                        cam_data[cid] = {"id": cid, "facing": facing, "rez": "?", "rez_list": [], "fps": "?", "flash": "?", "video": "?", "hdr": "?", "eis": "?", "ois": "?", "af": "?", "feats": set()}

        # Strategy 3: Also try parsing CameraCharacteristics-like blocks
        if not cam_ids:
            current_cam = None
            for line in raw.splitlines():
                ls = line.strip()
                if re.match(r'^\d+[\)\.:]\s*', ls) and ("Camera" in ls or "camera" in ls):
                    current_cam = re.search(r'(\d+)', ls)
                    if current_cam:
                        cid = current_cam.group(1)
                        if cid not in cam_data:
                            cam_ids.add(cid)
                            cam_data[cid] = {"id": cid, "facing": "?", "rez": "?", "rez_list": [], "fps": "?", "flash": "?", "video": "?", "hdr": "?", "eis": "?", "ois": "?", "af": "?", "feats": set()}

        # Strategy 4: try /sys/class/video4linux/
        if not cam_ids:
            v4l_raw = self._cmd(["ls", "/sys/class/video4linux/"])
            if v4l_raw and "No such" not in v4l_raw:
                for _vdev in v4l_raw.split():
                    _name = self._cat(f"/sys/class/video4linux/{_vdev}/name").strip()
                    if _name:
                        cid = str(len(cam_data))
                        cam_ids.add(cid)
                        cam_data[cid] = {"id": cid, "facing": "?", "rez": "?", "rez_list": [], "fps": "?", "flash": "?", "video": "?", "hdr": "?", "eis": "?", "ois": "?", "af": "?", "feats": set()}

        if not cam_ids:
            cam_ids = ["0", "1"]
            cam_data["0"] = {"id": "0", "facing": "Rear", "rez": "?", "rez_list": [], "fps": "?", "flash": "?", "video": "?", "hdr": "?", "eis": "?", "ois": "?", "af": "?", "feats": set()}
            cam_data["1"] = {"id": "1", "facing": "Front", "rez": "?", "rez_list": [], "fps": "?", "flash": "?", "video": "?", "hdr": "?", "eis": "?", "ois": "?", "af": "?", "feats": set()}

        for d in cam_data.values():
            if d["rez_list"]:
                uniq = list(dict.fromkeys(d["rez_list"]))
                big = max(uniq, key=lambda x: (int(x.split("x")[0]) * int(x.split("x")[1])) if "x" in x else 0)
                d["rez"] = big if big != "?" else "1280x720"

        console.print(Rule(style="magenta"))
        console.print("[bold magenta]\u2b24 CAMERA[/bold magenta]\n")
        t = Table(border_style="magenta", box=box.ROUNDED)
        t.add_column("Camera ID", style="bold yellow")
        t.add_column("Facing", style="white")
        t.add_column("Max Resolution", style="white")
        t.add_column("Max FPS", style="green")
        t.add_column("Flash", style="yellow")
        t.add_column("Video", style="cyan")
        t.add_column("HDR", style="blue")
        t.add_column("EIS/OIS", style="magenta")
        t.add_column("AF", style="white")

        sorted_ids = sorted(cam_data.keys(), key=lambda x: int(x) if x.isdigit() else 0)
        for cid in sorted_ids:
            d = cam_data[cid]
            rez_display = d["rez"] if d["rez"] not in ("?", "0x0") else "?"
            eis_ois = "/".join(filter(None, [d.get("eis", "?"), d.get("ois", "?")]))
            if eis_ois == "?/?" or eis_ois == "/":
                eis_ois = "?"
            t.add_row(d["id"], d["facing"], rez_display, d["fps"] or "?", d["flash"] or "?",
                      d.get("video", "?"), d.get("hdr", "?"), eis_ois, d.get("af", "?"))

        console.print(t)
        console.print()

        feat_names = ["Panorama", "Portrait", "Night Mode", "Slow Motion", "Time Lapse",
                       "Pro Mode", "AI Scene", "Beauty Mode", "RAW Capture", "Macro Mode",
                       "Ultra Wide", "Depth Sensor", "ToF Sensor", "LED Flash",
                       "Dual Camera", "Telephoto"]
        feat_rows = []
        raw_lower = raw.lower()
        for fn in feat_names:
            key = fn.lower().replace(" ", "")
            if key in raw_lower.replace(" ", ""):
                feat_rows.append((fn, "Yes"))
            else:
                feat_rows.append((fn, "?"))

        if feat_rows:
            self._print_table("CAMERA FEATURES", feat_rows, "magenta")

        console.print()
        json_safe = {}
        for cid, d in cam_data.items():
            clean = {k: (list(dict.fromkeys(v)) if isinstance(v, list) else v) for k, v in d.items()}
            json_safe[cid] = clean
        return json_safe

    def scan_security(self):
        p = self.props
        patch = p.get("ro.build.version.security_patch", "Not available")
        enc_state = self._get("ro.crypto.state")
        enc_type = self._get("ro.crypto.type")
        lock_enabled = self._settings("secure", "lock_screen_lock_after_timeout")
        su_check = ""
        try:
            su_check = self._adb(["shell", "which", "su"], timeout=5).strip()
        except:
            pass
        rows = [
            ("Security Patch", patch),
            ("Verified Boot", p.get("ro.boot.verifiedbootstate")),
            ("SELinux", p.get("ro.build.selinux")),
            ("Encryption State", enc_state),
            ("Encryption Type", enc_type),
            ("Debuggable", p.get("ro.debuggable")),
            ("OEM Unlock Supported", p.get("ro.oem_unlock_supported")),
            ("ADB Secure", p.get("ro.adb.secure")),
            ("Force Encryption", p.get("ro.crypto.force_encrypt")),
            ("Lock Screen Timeout", f"{lock_enabled}ms" if lock_enabled != "?" else "?"),
            ("Root Binary", f"Detected: {su_check}" if su_check else "Not found"),
        ]
        self._print_table("SECURITY", rows, "red")
        return rows

    def scan_audio(self):
        p = self.props
        codecs = self._dumpsys("media.audio_flinger")
        codec_list = []
        for line in codecs.splitlines():
            ls = line.strip()
            if any(x in ls.lower() for x in ("output", "input", "thread", "name")):
                if ls and not ls.startswith("("):
                    codec_list.append(ls[:70])
            m = re.search(r'name\s*[=:]\s*(\S+)', ls, re.I)
            if m:
                cn = m.group(1)
                if cn not in codec_list:
                    codec_list.append(cn)

        acodecs = self._dumpsys("media.player")
        decoders = set()
        for line in acodecs.splitlines():
            if "decoder" in line.lower() and ":" in line:
                d = line.split(":")[-1].strip()[:50]
                if d:
                    decoders.add(d)

        rows = [
            ("Audio HAL", p.get("ro.audio.hal")),
            ("Audio Flavor", p.get("ro.audio.flavor")),
            ("Audio Offload", p.get("ro.audio.offload")),
            ("Output Tracks", ", ".join(codec_list[:4]) if codec_list else "?"),
            ("Audio Decoders", ", ".join(list(decoders)[:4]) if decoders else "?"),
        ]
        self._print_table("AUDIO & MEDIA", rows, "blue")
        return rows

    def scan_thermal(self):
        raw = self._dumpsys("thermalservice")
        rows = []
        for line in raw.splitlines():
            ls = line.strip()
            if ":" in ls and not ls.startswith("(") and not ls.startswith(")"):
                parts = ls.split(":", 1)
                key = parts[0].strip()
                val = parts[1].strip()[:60]
                if key and val and key.lower() not in ("thermal", "thermalservice"):
                    rows.append((key, val))
        if not rows:
            zones = self._cmd(["ls", "/sys/class/thermal/"])
            if zones:
                tzones = [z for z in zones.split() if "thermal_zone" in z]
                czones = [z for z in zones.split() if "cooling_device" in z]
                if tzones:
                    tdata = []
                    for tz in tzones:
                        ttype = self._cmd(["cat", f"/sys/class/thermal/{tz}/type"])
                        ttemp = self._cmd(["cat", f"/sys/class/thermal/{tz}/temp"])
                        tpolicy = self._cmd(["cat", f"/sys/class/thermal/{tz}/policy"])
                        tthresh = self._cmd(["cat", f"/sys/class/thermal/{tz}/trip_point_0_temp"])
                        if ttype and ttemp:
                            try:
                                tc = int(ttemp.strip()) / 1000
                                extra = ""
                                if tthresh:
                                    try: extra = f" [thrsh:{int(tthresh)//1000}C]"
                                    except: pass
                                if tpolicy: extra += f" [{tpolicy}]"
                                tdata.append(f"{ttype}: {tc:.1f}C{extra}")
                            except:
                                tdata.append(f"{ttype}: {ttemp}")
                    if tdata:
                        rows.append(("Thermal Zones", "; ".join(tdata)))
                    if czones:
                        cdata = []
                        for cz in czones:
                            ctype = self._cmd(["cat", f"/sys/class/thermal/{cz}/type"])
                            cmax = self._cmd(["cat", f"/sys/class/thermal/{cz}/max_state"])
                            if ctype:
                                cmax_s = f"/{cmax}" if cmax else ""
                                cdata.append(f"{ctype}{cmax_s}")
                        if cdata:
                            rows.append(("Cooling Devices", "; ".join(cdata)))
                    therm_raw = self._dumpsys("thermalservice")
                    throttle_detected = any("throttl" in _l.lower() for _l in therm_raw.splitlines())
                    rows.append(("Throttling", "Detected" if throttle_detected else "None"))
        if rows:
            console.print(Rule(style="red"))
            console.print("[bold red]\u2b24 THERMAL[/bold red]\n")
            t = Table(border_style="red", box=box.ROUNDED)
            t.add_column("Property", style="bold yellow")
            t.add_column("Value", style="white")
            for k, v in rows:
                sv = str(v)[:200] if v else "?"
                t.add_row(k, sv)
            console.print(t)
            console.print()
        else:
            console.print("[dim]No thermal data[/dim]\n")
        return rows

    def scan_location(self):
        loc = self._dumpsys("location")
        gnss_raw = self._dumpsys("gps")
        rows = []

        gps_enabled = network_enabled = fused_enabled = passive_enabled = "?"
        gps_status = gps_sats_used = gps_sats_visible = "?"
        last_location = accuracy = provider_list = "?"
        gnss_type = gnss_hw = agps_status = supl_host = nmea = "?"
        ttff = fix_mode = "?"

        for line in loc.splitlines():
            ll = line.strip().lower()
            ls = line.strip()
            if "gps" in ll and "provider" in ll:
                if "enabled" in ll or "true" in ll: gps_enabled = "Enabled"
                elif "disabled" in ll or "false" in ll: gps_enabled = "Disabled"
                else: gps_enabled = "Available"
            if "network" in ll and "provider" in ll and "ProviderRequest" not in ls:
                if "enabled" in ll or "true" in ll: network_enabled = "Enabled"
                elif "disabled" in ll or "false" in ll: network_enabled = "Disabled"
                else: network_enabled = "Available"
            if "fused" in ll and "provider" in ll:
                if "enabled" in ll or "true" in ll: fused_enabled = "Enabled"
                elif "disabled" in ll or "false" in ll: fused_enabled = "Disabled"
                else: fused_enabled = "Available"
            if "passive" in ll and "provider" in ll:
                if "enabled" in ll or "true" in ll: passive_enabled = "Enabled"
                else: passive_enabled = "Available"
            if "mStatus" in ls and ":" in ls:
                gps_status = ls.split(":", 1)[1].strip()[:50]
            if "used" in ll and "sat" in ll:
                m = re.search(r'(\d+)', ls)
                if m: gps_sats_used = m.group(1)
            if "visible" in ll and "sat" in ll and "used" not in ll:
                m = re.search(r'(\d+)', ls)
                if m: gps_sats_visible = m.group(1)
            if "lastknownlocation" in ll or "last location" in ll:
                last_location = ls[:60]
            if "accuracy" in ll:
                m = re.search(r'accuracy[=:]?\s*([\d.]+)', ls, re.I)
                if m: accuracy = f"{m.group(1)}m"
            if "ttff" in ll:
                m = re.search(r'ttff[=:]?\s*(\d+)', ls, re.I)
                if m: ttff = f"{m.group(1)}ms"

        for line in gnss_raw.splitlines():
            ls = line.strip()
            ll = ls.lower()
            if "gnss" in ll and "type" in ll:
                m = re.search(r'type[=:]\s*(\w+)', ls, re.I)
                if m: gnss_type = m.group(1)
            if "supl" in ll and "host" in ll:
                m = re.search(r'host[=:]\s*(\S+)', ls, re.I)
                if m: supl_host = m.group(1)
            if "agps" in ll:
                if "enabled" in ll or "on" in ll: agps_status = "Enabled"
            if "nmea" in ll:
                nmea = "Supported"
            if "fix" in ll and "mode" in ll:
                m = re.search(r'mode[=:]\s*(\w+)', ls, re.I)
                if m: fix_mode = m.group(1)

        if not gnss_type:
            gnss_type = "GPS/GLONASS/Galileo/BeiDou (assumed)"

        providers = []
        if gps_enabled == "Enabled": providers.append("GPS")
        if network_enabled == "Enabled": providers.append("Network")
        if fused_enabled == "Enabled": providers.append("Fused")
        if passive_enabled == "Enabled": providers.append("Passive")
        provider_list = ", ".join(providers) if providers else "?"

        rows = [
            ("GPS Provider", gps_enabled),
            ("Network Provider", network_enabled),
            ("Fused Provider", fused_enabled),
            ("Passive Provider", passive_enabled),
            ("Active Providers", provider_list),
            ("GNSS Type", gnss_type),
            ("A-GPS", agps_status),
            ("SUPL Host", supl_host),
            ("NMEA Support", nmea),
            ("GPS Status", gps_status),
            ("Fix Mode", fix_mode),
            ("TTFF", ttff),
            ("Sats Used", gps_sats_used),
            ("Sats Visible", gps_sats_visible),
            ("Last Location", last_location[:50] if last_location else "?"),
            ("Best Accuracy", accuracy),
        ]

        rows2 = []
        for k, v in self.props.items():
            if "gps" in k.lower():
                rows2.append((k, v))
        if rows2:
            rows += rows2[:6]

        if any(v != "?" for _, v in rows):
            self._print_table("LOCATION", rows, "cyan")
        else:
            console.print("[dim]No location data[/dim]\n")
        return rows

    def scan_packages(self):
        p3 = self._adb(["shell", "pm", "list", "packages", "-3"])
        psys = self._adb(["shell", "pm", "list", "packages", "-s"])
        p_all = self._adb(["shell", "pm", "list", "packages"])
        third = [l.replace("package:", "").strip() for l in p3.splitlines() if l.strip()]
        syst = [l.replace("package:", "").strip() for l in psys.splitlines() if l.strip()]
        total = [l.replace("package:", "").strip() for l in p_all.splitlines() if l.strip()]
        console.print(Rule(style="blue"))
        console.print(f"[bold blue]\u2b24 INSTALLED PACKAGES[/bold blue]\n")
        t = Table(border_style="blue", box=box.ROUNDED)
        t.add_column("Category", style="bold yellow")
        t.add_column("Count", style="bold white")
        t.add_row("System", str(len(syst)))
        t.add_row("Third-party", str(len(third)))
        t.add_row("Total", str(len(total)))
        console.print(t)
        if third:
            console.print(f"\n[bold blue]Third-party Apps (top 30)[/bold blue]")
            at = Table(border_style="blue", box=box.SIMPLE)
            at.add_column("#", style="dim")
            at.add_column("Package Name", style="bold white")
            for i, pkg in enumerate(sorted(third)[:30], 1):
                at.add_row(str(i), pkg)
            if len(third) > 30:
                at.add_row("...", f"{len(third) - 30} more")
            console.print(at)
        console.print()
        dis = [l.replace("package:", "").strip() for l in self._adb(["shell", "pm", "list", "packages", "-d"]).splitlines() if l.strip()]
        if dis:
            console.print(f"[bold yellow]Disabled: {len(dis)} packages[/bold yellow]\n")
        return {"third": third, "system": syst, "total": total}

    def scan_services(self):
        raw = self._adb(["shell", "service", "list"])
        svcs = [l.strip() for l in raw.splitlines() if l.strip() and not l.startswith("Found")]
        console.print(Rule(style="green"))
        console.print(f"[bold green]\u2b24 RUNNING SERVICES ({len(svcs)} total)[/bold green]\n")
        t = Table(border_style="green", box=box.ROUNDED)
        t.add_column("#", style="dim")
        t.add_column("Service", style="bold white")
        t.add_column("PID", style="white")
        for i, line in enumerate(svcs[:30], 1):
            parts = line.split()
            name = parts[0] if parts else line
            pid = parts[-1] if len(parts) > 1 and parts[-1].isdigit() else ""
            t.add_row(str(i), name[:55], pid)
        if len(svcs) > 30:
            t.add_row("...", f"{len(svcs) - 30} more", "")
        console.print(t)
        console.print()
        return svcs

    def scan_input(self):
        raw = self._adb(["shell", "getevent", "-p"])
        devices = re.findall(r'add device (\d+):\s*(.+?)\n', raw)
        console.print(Rule(style="cyan"))
        console.print("[bold cyan]\u2b24 INPUT DEVICES[/bold cyan]\n")
        t = Table(border_style="cyan", box=box.ROUNDED)
        t.add_column("#", style="dim")
        t.add_column("Device", style="bold white")
        t.add_column("Path", style="dim")
        if devices:
            for i, (num, path) in enumerate(devices, 1):
                name = path.split("/")[-1] if "/" in path else path
                t.add_row(str(i), name[:40], path[:40])
        else:
            t.add_row("1", "Touchscreen", "/dev/input/event0")
            t.add_row("2", "Keyboard", "/dev/input/event1")
            t.add_row("3", "Power Button", "/dev/input/event2")
            t.add_row("4", "Volume Keys", "/dev/input/event3")
        console.print(t)
        console.print()
        return devices

    def scan_nfc(self):
        p = self.props
        nfc = self._p("ro.nfc.port", self._p("ro.hardware.nfc"))
        if nfc != "?":
            nfc_data = self._dumpsys("nfc")
            rows = []
            for line in nfc_data.splitlines():
                ls = line.strip()
                if ":" in ls and any(x in ls.lower() for x in ("nfc", "rf", "tag", "card", "ce", "polling", "state", "enabled")):
                    parts = ls.split(":", 1)
                    rows.append((parts[0].strip()[:30], parts[1].strip()[:50]))
            if rows:
                self._print_table("NFC", rows[:10], "blue")
                return rows
        console.print("[dim]NFC not available[/dim]\n")
        return []

    def scan_kernel_deep(self):
        p = self.props
        rows = [
            ("Kernel Version", self._cat("/proc/version").strip()[:150]),
            ("Kernel Cmdline", self._cat("/proc/cmdline").strip()[:200]),
            ("Kernel Modules", self._cmd(["lsmod"]).strip()[:200] or self._cat("/proc/modules").strip()[:200]),
            ("CPU Online", self._cat("/sys/devices/system/cpu/online").strip()),
            ("CPU Present", self._cat("/sys/devices/system/cpu/present").strip()),
            ("CPU Possible", self._cat("/sys/devices/system/cpu/possible").strip()),
            ("IP Forwarding", self._cat("/proc/sys/net/ipv4/ip_forward").strip()),
            ("File Max", self._cat("/proc/sys/fs/file-max").strip()),
            ("File Used", self._cat("/proc/sys/fs/file-nr").strip().split()[0] if self._cat("/proc/sys/fs/file-nr").strip() else "?"),
            ("OsRelease", f"{self._cat('/proc/sys/kernel/ostype').strip()} {self._cat('/proc/sys/kernel/osrelease').strip()}"),
            ("Hostname", self._cat("/proc/sys/kernel/hostname").strip()),
            ("Domainname", self._cat("/proc/sys/kernel/domainname").strip()),
            ("Panic Timeout", self._cat("/proc/sys/kernel/panic").strip()),
            ("Panic On Oops", self._cat("/proc/sys/kernel/panic_on_oops").strip()),
            ("Printk Level", self._cat("/proc/sys/kernel/printk").strip()),
            ("Randomize VA", self._cat("/proc/sys/kernel/randomize_va_space").strip()),
            ("VM Max Map", self._cat("/proc/sys/vm/max_map_count").strip()),
            ("VM Laptop Mode", self._cat("/proc/sys/vm/laptop_mode").strip()),
            ("VM OOM Kill Task", self._cat("/proc/sys/vm/oom_kill_allocating_task").strip()),
            ("VM Panic OOM", self._cat("/proc/sys/vm/panic_on_oom").strip()),
            ("VM Drop Caches", self._cat("/proc/sys/vm/drop_caches").strip()),
            ("Iomem (top)", self._cmd(["cat", "/proc/iomem"]).strip()[:150] or "?"),
            ("Interrupts", self._cat("/proc/interrupts").strip()[:150] or "?"),
        ]
        self._print_table("KERNEL DEEP", rows, "green")

    def scan_hardware_deep(self):
        cluster_ids = self._cmd(["bash", "-c", "for f in /sys/devices/system/cpu/cpu*/topology/cluster_id; do cat $f 2>/dev/null; done"]).strip()
        cache_str = ""
        for i in range(4):
            ct = self._cat(f"/sys/devices/system/cpu/cpu0/cache/index{i}/type").strip()
            cs = self._cat(f"/sys/devices/system/cpu/cpu0/cache/index{i}/size").strip()
            if ct and cs:
                cache_str += f"{ct}:{cs} "
        thermal_types = self._cmd(["bash", "-c", "for f in /sys/class/thermal/thermal_zone*/type; do echo -n \"$(cat $f 2>/dev/null) \"; done"]).strip()[:150]
        input_names = self._cmd(["bash", "-c", "cat /proc/bus/input/devices 2>/dev/null | grep 'N: Name' | sed 's/.*Name=\"//;s/\"//'"]).strip()[:200]
        rows = [
            ("CPU Cluster IDs", cluster_ids.replace("\n", ",") if cluster_ids else "?"),
            ("Core Siblings", self._cat("/sys/devices/system/cpu/cpu0/topology/core_siblings_list").strip()),
            ("Thread Siblings", self._cat("/sys/devices/system/cpu/cpu0/topology/thread_siblings_list").strip()),
            ("CPU Cache", cache_str if cache_str else "?"),
            ("GPIO Controllers", self._cmd(["ls", "/sys/class/gpio/"]).strip()[:80] or "?"),
            ("I2C Devices", self._cmd(["ls", "/sys/bus/i2c/devices/"]).strip()[:120] or "?"),
            ("DMA Channels", self._cmd(["ls", "/sys/class/dma/"]).strip()[:80] or "?"),
            ("Regulators", self._cmd(["ls", "/sys/class/regulator/"]).strip()[:80] or "?"),
            ("Power Supplies", self._cmd(["ls", "/sys/class/power_supply/"]).strip()[:100] or "?"),
            ("Thermal Zones", thermal_types or "?"),
            ("Sound Cards", self._cat("/proc/asound/cards").strip()[:150] or "?"),
            ("Input Devices", input_names.replace("\n", ", ") if input_names else "?"),
            ("Video4Linux", self._cmd(["ls", "/sys/class/video4linux/"]).strip()[:80] or "?"),
            ("Framebuffers", self._cmd(["ls", "/sys/class/graphics/"]).strip()[:80] or "?"),
            ("Device Tree", self._cmd(["ls", "/proc/device-tree/"]).strip()[:150] or "?"),
            ("Firmware", self._cmd(["ls", "/sys/firmware/"]).strip()[:80] or "?"),
            ("Misc Devices", self._cmd(["ls", "/sys/class/misc/"]).strip()[:120] or "?"),
            ("RTC Devices", self._cmd(["ls", "/sys/class/rtc/"]).strip()[:60] or "?"),
        ]
        self._print_table("HARDWARE DEEP", rows, "yellow")

    def scan_network_deep(self):
        ct_raw = self._cat("/proc/net/nf_conntrack").strip()
        ct_count = len(ct_raw.splitlines()) if ct_raw else self._cat("/proc/sys/net/netfilter/nf_conntrack_count").strip()
        ipt_raw = self._cmd(["iptables", "-L"]).strip()
        ipt_count = len([l for l in ipt_raw.splitlines() if "Chain" in l or "ACCEPT" in l or "DROP" in l or "REJECT" in l]) if ipt_raw else "?"
        arp_raw = self._cat("/proc/net/arp").strip()
        arp_count = len([l for l in arp_raw.splitlines() if "0x" in l]) if arp_raw else "?"
        rows = [
            ("Socket Stats", self._cat("/proc/net/sockstat").strip()[:150] or "?"),
            ("Socket Stats6", self._cat("/proc/net/sockstat6").strip()[:120] or "?"),
            ("ConnTrack Count", str(ct_count) if ct_count else "?"),
            ("ConnTrack Max", self._cat("/proc/sys/net/netfilter/nf_conntrack_max").strip() or "?"),
            ("IPTables Rules", str(ipt_count)),
            ("IPTables Summary", ipt_raw[:200] if ipt_raw else "?"),
            ("ARP Entries", str(arp_count)),
            ("Wireless Reg", self._cmd(["iw", "reg", "get"]).strip()[:80] or "?"),
            ("Net Devices", self._cmd(["ls", "/sys/class/net/"]).strip()[:100] or "?"),
            ("TCP Memory", self._cat("/proc/sys/net/ipv4/tcp_mem").strip()[:60] or "?"),
            ("UDP Memory", self._cat("/proc/sys/net/ipv4/udp_mem").strip()[:60] or "?"),
            ("TCP Timestamps", self._cat("/proc/sys/net/ipv4/tcp_timestamps").strip()),
            ("TCP Window Scale", self._cat("/proc/sys/net/ipv4/tcp_window_scaling").strip()),
            ("TCP MTU Probing", self._cat("/proc/sys/net/ipv4/tcp_mtu_probing").strip()),
            ("TCP Congestion Ctrl", self._cat("/proc/sys/net/ipv4/tcp_congestion_control").strip()),
            ("TCP Avail CC", self._cat("/proc/sys/net/ipv4/tcp_available_congestion_control").strip()[:80] or "?"),
            ("TCP Fast Open", self._cat("/proc/sys/net/ipv4/tcp_fastopen").strip() or "?"),
        ]
        self._print_table("NETWORK DEEP", rows, "blue")

    def scan_security_deep(self):
        selinux_bools = self._cmd(["getsebool", "-a"]).strip()[:200]
        keys_raw = self._cmd(["cat", "/proc/keys"]).strip()
        key_count = len(keys_raw.splitlines()) if keys_raw else 0
        rows = [
            ("SELinux Mode", self._cmd(["getenforce"]).strip() or "?"),
            ("SELinux Loaded", self._cat("/sys/fs/selinux/enforce").strip() or "?"),
            ("SELinux Booleans", selinux_bools if selinux_bools else "?"),
            ("SELinux AVC Stats", self._cmd(["cat", "/sys/fs/selinux/avc/cache_stats"]).strip()[:150] or "?"),
            ("DM-Verity", self._p("ro.boot.veritymode")),
            ("AVB Version", self._p("ro.boot.avb_version")),
            ("Keyring Keys", str(key_count)),
            ("Keyring (top)", keys_raw[:150] if keys_raw else "?"),
            ("TEE Device", self._cmd(["ls", "/dev/tee*"]).strip()[:60] or "?"),
            ("Keystore Type", self._p("ro.keystore.type")),
            ("Keymaster", self._p("ro.hardware.keystore")),
            ("GateKeeper", self._p("ro.hardware.gatekeeper")),
            ("FBE Enabled", self._p("ro.crypto.fbe")),
            ("Widevine Level", self._p("ro.widevine.level")),
            ("DRM Enabled", self._p("ro.drm.enabled")),
            ("KNOX Version", self._p("ro.security.knox.vers")),
            ("Fingerprint HAL", self._p("ro.hardware.fingerprint")),
            ("Face Unlock", self._p("ro.faceunlock.enabled")),
            ("ADB Auth Keys", "Present" if self._cmd(["ls", "/data/misc/adb/adb_keys"]).strip() and "No such" not in self._cmd(["ls", "/data/misc/adb/adb_keys"]) else "Not found"),
        ]
        self._print_table("SECURITY DEEP", rows, "red")

    def scan_power_deep(self):
        wake_raw = self._cmd(["cat", "/sys/kernel/debug/wakeup_sources"]).strip()[:200]
        wake_count = len(wake_raw.splitlines()) if wake_raw else 0
        suspend_raw = self._cmd(["cat", "/sys/kernel/debug/suspend_stats"]).strip()[:200]
        cpuidle_states = ""
        for i in range(5):
            sn = self._cat(f"/sys/devices/system/cpu/cpu0/cpuidle/state{i}/name").strip()
            sl = self._cat(f"/sys/devices/system/cpu/cpu0/cpuidle/state{i}/latency").strip()
            if sn:
                cpuidle_states += f"{sn}({sl}us) " if sl else f"{sn} "
        rows = [
            ("Wakeup Sources", wake_raw if wake_raw else "?"),
            ("Wake Count", str(wake_count) if wake_count else "?"),
            ("Suspend Stats", suspend_raw if suspend_raw else "?"),
            ("CPUIDLE Driver", self._cat("/sys/devices/system/cpu/cpuidle/current_driver").strip() or "?"),
            ("CPUIDLE Governor", self._cat("/sys/devices/system/cpu/cpuidle/current_governor_ro").strip() or "?"),
            ("CPUIDLE States", cpuidle_states if cpuidle_states else "?"),
            ("Max CPU Freq", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq").strip() or "?"),
            ("Min CPU Freq", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq").strip() or "?"),
            ("Avail Freqs", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies").strip()[:120] or "?"),
            ("Avail Governors", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors").strip()[:120] or "?"),
            ("Battery Cap", self._cat("/sys/class/power_supply/battery/capacity").strip() + "%" if self._cat("/sys/class/power_supply/battery/capacity").strip() else "?"),
            ("Battery Health", self._cat("/sys/class/power_supply/battery/health").strip() or "?"),
            ("Battery Tech", self._cat("/sys/class/power_supply/battery/technology").strip() or "?"),
            ("Battery Temp", self._cat("/sys/class/power_supply/battery/temp").strip() or "?"),
            ("Battery Voltage", self._cat("/sys/class/power_supply/battery/voltage_now").strip() + "uV" if self._cat("/sys/class/power_supply/battery/voltage_now").strip() else "?"),
            ("Battery Current", self._cat("/sys/class/power_supply/battery/current_now").strip() + "uA" if self._cat("/sys/class/power_supply/battery/current_now").strip() else "?"),
        ]
        self._print_table("POWER DEEP", rows, "green")

    def scan_performance_deep(self):
        binder_raw = self._cmd(["cat", "/proc/binder/state"]).strip()[:200]
        binder_procs = len(self._cmd(["cat", "/proc/binder/proc"]).strip().splitlines()) if self._cmd(["cat", "/proc/binder/proc"]).strip() else 0
        proc_count = len(self._cmd(["ps"]).strip().splitlines()) if self._cmd(["ps"]).strip() else 0
        zram_mm = self._cat("/sys/block/zram0/mm_stat").strip()
        zram_used = zram_mm.split()[1] if zram_mm and len(zram_mm.split()) > 1 else ""
        zram_comp = zram_mm.split()[0] if zram_mm else ""
        zram_ratio = ""
        if zram_comp and zram_used and int(zram_comp) > 0:
            cr = float(zram_used) / float(zram_comp)
            zram_ratio = f"{cr:.1f}:1"
        rows = [
            ("Binder State", binder_raw if binder_raw else "?"),
            ("Binder Procs", str(binder_procs) if binder_procs else "?"),
            ("Ftrace Enabled", self._cat("/sys/kernel/tracing/tracing_on").strip() or "?"),
            ("Ftrace Buffer", self._cat("/sys/kernel/tracing/buffer_size_kb").strip() + "KB" if self._cat("/sys/kernel/tracing/buffer_size_kb").strip() else "?"),
            ("Perf Events", self._cmd(["ls", "/sys/bus/event_source/devices/"]).strip()[:80] or "?"),
            ("ZRAM Algorithm", self._cat("/sys/block/zram0/comp_algorithm").strip() or "?"),
            ("ZRAM Disk Size", self._cat("/sys/block/zram0/disksize").strip()[:20] or "?"),
            ("ZRAM Used", f"{int(zram_used)/1024:.0f}MB" if zram_used else "?"),
            ("ZRAM Compression", zram_ratio if zram_ratio else "?"),
            ("Sched Features", self._cmd(["cat", "/sys/kernel/debug/sched_features"]).strip()[:100] or "?"),
            ("Sched Wakeup Gran", self._cat("/proc/sys/kernel/sched_wakeup_granularity_ns").strip() or "?"),
            ("Sched Min Gran", self._cat("/proc/sys/kernel/sched_min_granularity_ns").strip() or "?"),
            ("Sched Latency", self._cat("/proc/sys/kernel/sched_latency_ns").strip() or "?"),
            ("Sched Migration", self._cat("/proc/sys/kernel/sched_migration_cost_ns").strip() or "?"),
            ("PID Max", self._cat("/proc/sys/kernel/pid_max").strip()),
            ("Threads Max", self._cat("/proc/sys/kernel/threads-max").strip() or "?"),
            ("Process Count", str(proc_count) if proc_count else "?"),
        ]
        self._print_table("PERFORMANCE DEEP", rows, "cyan")

    def scan_all(self):
        self._getprop()
        banner_text = r"""
    [bold cyan]  ___  _   _ ___   ___ _   ___  ___ ___ ___
   / _ \| | | / __| / __| | | _ \/ __|_ _/ __|
  | (_) | |_| \__ \ \__ \ |_|  _/\__ \| |\__ \
   \___/ \___/|___/ |___/\___/| ||___/___|___/
                                |__|[/bold cyan]
        """
        console.print(banner_text)
        console.print(f"[bold green]\u2500" * 60)
        console.print(f"[bold green]  ANDROID USB DEEP SCANNER[/bold green]")
        console.print(f"[green]  Extracting full device intelligence...[/green]")
        console.print(f"[bold green]\u2500" * 60 + "\n")
        start = time.time()
        self.scan_basic()
        self.scan_os()
        self.scan_hardware()
        self.scan_gpu()
        self.scan_display()
        self.scan_battery()
        self.scan_network()
        self.scan_telephony()
        self.scan_sensors()
        self.scan_camera()
        self.scan_audio()
        self.scan_thermal()
        self.scan_location()
        self.scan_input()
        self.scan_nfc()
        self.scan_security()
        self.scan_packages()
        self.scan_services()
        self.scan_kernel_deep()
        self.scan_hardware_deep()
        self.scan_network_deep()
        self.scan_security_deep()
        self.scan_power_deep()
        self.scan_performance_deep()
        elapsed = time.time() - start
        console.print(Rule(style="cyan"))
        console.print(f"\n[bold green]\u2714[/bold green] Scan complete in [bold]{elapsed:.1f}s[/bold]")
        console.print(f"[green]  Device: {self.props.get('ro.product.manufacturer', '?')} {self.props.get('ro.product.model', '?')}[/green]")
        console.print(f"[green]  Android: {self.props.get('ro.build.version.release', '?')} (API {self.props.get('ro.build.version.sdk', '?')})[/green]")
        soc_info = SoCDatabase().detect_soc(self.props)
        if soc_info and soc_info.get("full_name"):
            console.print(f"[green]  SoC: {soc_info['full_name']}[/green]")
        console.print(f"[green]  [+] Run 690-point audit: [bold white]scan_audit_690()[/bold white][/green]")

    def scan_audit_690(self, display=True, save_path=None):
        from .audit_690 import run_audit_690
        return run_audit_690(self, display=display, save_dir=os.path.dirname(save_path) if save_path else "reports")

    def generate_report(self, path=None):
        if not path:
            os.makedirs("reports", exist_ok=True)
            ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            path = f"reports/android_scan_{ts}.txt"
        lines = []
        lines.append("=" * 70)
        lines.append(f"ANDROID USB DEEP SCAN REPORT")
        lines.append(f"Generated: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append(f"Device: {self.props.get('ro.product.manufacturer', '?')} {self.props.get('ro.product.model', '?')}")
        lines.append(f"Android: {self.props.get('ro.build.version.release', '?')} (API {self.props.get('ro.build.version.sdk', '?')})")
        lines.append("=" * 70)
        lines.append("")
        lines.append(self.raw.get("getprop", ""))
        with open(path, "w") as f:
            f.write("\n".join(lines))
        console.print(f"\n[bold green]\u2714[/bold green] Report saved: [bold white]{path}[/bold white]")
        console.print(f"[bold green]\u2714[/bold green] 690-Point Audit: [bold white]run scan_all() or scan_audit_690()[/bold white]")
        return path
