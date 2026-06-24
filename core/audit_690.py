#!/usr/bin/env python3
import re
import os
import datetime
from rich.console import Console
from rich.table import Table
from rich import box
from rich.rule import Rule
from rich.text import Text
from .soc_db import SoCDatabase, detect_cpu

console = Console()

SECTION_COLORS = {
    "DEVICE IDENTITY": "cyan",
    "OPERATING SYSTEM": "green",
    "BUILD INFO": "blue",
    "HARDWARE": "yellow",
    "STORAGE": "magenta",
    "GPU": "cyan",
    "NETWORK": "blue",
    "TELEPHONY": "green",
    "DISPLAY": "magenta",
    "BATTERY": "green",
    "SENSORS": "yellow",
    "CAMERA": "magenta",
    "SECURITY": "red",
    "PERFORMANCE": "cyan",
    "THERMAL": "red",
    "AUDIO": "blue",
    "SYSTEM": "green",
    "NETWORKING ADVANCED": "blue",
    "EXTRAS": "cyan",
}

class AndroidAudit690:
    def __init__(self, scanner):
        self.sc = scanner
        self.props = scanner.props
        self.raw = scanner.raw
        self.points = []
        self.cache = {}
        self.soc = None

    def _get(self, prop, fallback="? [N/A]"):
        return self.props.get(prop, fallback)

    def _cat(self, path):
        if path not in self.cache:
            self.cache[path] = self.sc._cat(path)
        return self.cache[path]

    def _cmd(self, cmd_list):
        key = " ".join(cmd_list)
        if key not in self.cache:
            self.cache[key] = self.sc._cmd(cmd_list)
        return self.cache[key]

    def _dumpsys(self, service):
        if service not in self.cache:
            self.cache[service] = self.sc._dumpsys(service)
        return self.cache[service]

    def _settings(self, ns, key):
        ck = f"settings_{ns}_{key}"
        if ck not in self.cache:
            self.cache[ck] = self.sc._settings(ns, key)
        return self.cache[ck]

    def _grep_prop(self, pattern):
        results = {}
        for k, v in self.props.items():
            if pattern in k.lower():
                results[k] = v
        return results

    def _color_for_status(self, value):
        if not value or value == "?" or "N/A" in str(value):
            return "red"
        if "error" in str(value).lower() or "not" in str(value).lower():
            return "yellow"
        return "green"

    def add_point(self, section, num, desc, value):
        color = self._color_for_status(value)
        self.points.append({
            "section": section,
            "num": num,
            "desc": desc,
            "value": str(value)[:150] if value else "?",
            "color": color,
        })

    def section_device_identity(self):
        s = "DEVICE IDENTITY"
        p = self.props
        self.add_point(s, 1, "Device Model (ro.product.model)", p.get("ro.product.model"))
        self.add_point(s, 2, "Manufacturer (ro.product.manufacturer)", p.get("ro.product.manufacturer"))
        self.add_point(s, 3, "Brand (ro.product.brand)", p.get("ro.product.brand"))
        self.add_point(s, 4, "Market Name (ro.product.marketname)", p.get("ro.product.marketname"))
        self.add_point(s, 5, "Marketing Config Name (ro.config.marketing_name)", p.get("ro.config.marketing_name"))
        self.add_point(s, 6, "Product Name (ro.product.name)", p.get("ro.product.name"))
        self.add_point(s, 7, "Product Device (ro.product.device)", p.get("ro.product.device"))
        self.add_point(s, 8, "Product Board (ro.product.board)", p.get("ro.product.board"))
        self.add_point(s, 9, "Product Model Name (ro.product.model.name)", p.get("ro.product.model.name"))
        self.add_point(s, 10, "Hardware (ro.hardware)", p.get("ro.hardware"))
        self.add_point(s, 11, "Hardware SKU (ro.boot.hardware.sku)", p.get("ro.boot.hardware.sku"))
        self.add_point(s, 12, "Platform/SoC (ro.board.platform)", p.get("ro.board.platform"))
        self.add_point(s, 13, "Chipname (ro.chipname)", p.get("ro.chipname"))
        self.add_point(s, 14, "Bootloader (ro.bootloader)", p.get("ro.bootloader"))
        self.add_point(s, 15, "Serial Number (ro.serialno)", p.get("ro.serialno"))
        self.add_point(s, 16, "Boot Serial (ro.boot.serialno)", p.get("ro.boot.serialno"))
        self.add_point(s, 17, "Fingerprint (ro.build.fingerprint)", p.get("ro.build.fingerprint"))
        self.add_point(s, 18, "Description (ro.build.description)", p.get("ro.build.description"))
        self.add_point(s, 19, "Locale (persist.sys.locale)", p.get("persist.sys.locale"))
        self.add_point(s, 20, "Language (ro.product.locale.language)", p.get("ro.product.locale.language"))
        self.add_point(s, 21, "Region (ro.product.locale.region)", p.get("ro.product.locale.region"))
        self.add_point(s, 22, "Timezone (persist.sys.timezone)", p.get("persist.sys.timezone"))
        self.add_point(s, 23, "Characteristics (ro.build.characteristics)", p.get("ro.build.characteristics"))
        self.add_point(s, 24, "Display ID (ro.build.display.id)", p.get("ro.build.display.id"))
        self.add_point(s, 25, "Product CPU ABI (ro.product.cpu.abi)", p.get("ro.product.cpu.abi"))
        self.add_point(s, 26, "ABI List (ro.product.cpu.abilist)", p.get("ro.product.cpu.abilist"))

    def section_os(self):
        s = "OPERATING SYSTEM"
        p = self.props
        self.add_point(s, 27, "Android Version (ro.build.version.release)", p.get("ro.build.version.release"))
        self.add_point(s, 28, "API Level/SDK (ro.build.version.sdk)", p.get("ro.build.version.sdk"))
        self.add_point(s, 29, "Preview SDK (ro.build.version.preview_sdk)", p.get("ro.build.version.preview_sdk"))
        self.add_point(s, 30, "Codename (ro.build.version.codename)", p.get("ro.build.version.codename"))
        self.add_point(s, 31, "Incremental (ro.build.version.incremental)", p.get("ro.build.version.incremental"))
        self.add_point(s, 32, "Security Patch (ro.build.version.security_patch)", p.get("ro.build.version.security_patch"))
        self.add_point(s, 33, "Vendor Security Patch (ro.vendor.build.security_patch)", p.get("ro.vendor.build.security_patch"))
        self.add_point(s, 34, "Base OS (ro.build.version.base_os)", p.get("ro.build.version.base_os"))
        self.add_point(s, 35, "Build Type (ro.build.type)", p.get("ro.build.type"))
        self.add_point(s, 36, "Build Tags (ro.build.tags)", p.get("ro.build.tags"))
        self.add_point(s, 37, "Build User (ro.build.user)", p.get("ro.build.user"))
        self.add_point(s, 38, "Build Host (ro.build.host)", p.get("ro.build.host"))
        self.add_point(s, 39, "Build Date UTC (ro.build.date.utc)", p.get("ro.build.date.utc"))
        self.add_point(s, 40, "Build Date Full (ro.build.date)", p.get("ro.build.date"))
        self.add_point(s, 41, "Kernel Version (/proc/version)", self._extract_kernel("version"))
        self.add_point(s, 42, "Kernel Compiler (/proc/version)", self._extract_kernel("compiler"))
        self.add_point(s, 43, "GCC Version (/proc/version)", self._extract_kernel("gcc"))
        self.add_point(s, 44, "SMP Status (/proc/version)", self._extract_kernel("smp"))
        self.add_point(s, 45, "Preempt Model (/proc/version)", self._extract_kernel("preempt"))
        self.add_point(s, 46, "Uptime (/proc/uptime)", self._extract_uptime())
        self.add_point(s, 47, "Swappiness (/proc/sys/vm/swappiness)", self._cat("/proc/sys/vm/swappiness").strip())
        self.add_point(s, 48, "Overcommit Ratio (/proc/sys/vm/overcommit_ratio)", self._cat("/proc/sys/vm/overcommit_ratio").strip())
        self.add_point(s, 49, "Max User Watches (/proc/sys/fs/inotify/max_user_watches)", self._cat("/proc/sys/fs/inotify/max_user_watches").strip())
        self.add_point(s, 50, "Max User Instances (/proc/sys/fs/inotify/max_user_instances)", self._cat("/proc/sys/fs/inotify/max_user_instances").strip())
        self.add_point(s, 51, "File Max (/proc/sys/fs/file-max)", self._cat("/proc/sys/fs/file-max").strip())
        self.add_point(s, 52, "Max PID (/proc/sys/kernel/pid_max)", self._cat("/proc/sys/kernel/pid_max").strip())
        self.add_point(s, 53, "Hostname (/proc/sys/kernel/hostname)", self._cat("/proc/sys/kernel/hostname").strip())
        self.add_point(s, 54, "Domain Name (/proc/sys/kernel/domainname)", self._cat("/proc/sys/kernel/domainname").strip())
        self.add_point(s, 55, "OS Type (ro.build.version.release_or_codename)", p.get("ro.build.version.release_or_codename"))
        self.add_point(s, 56, "Baseband Version (gsm.version.baseband)", p.get("gsm.version.baseband"))
        self.add_point(s, 57, "Build Version Keys (ro.build.version.security_patch_rpm)", p.get("ro.build.version.security_patch_rpm"))
        self.add_point(s, 58, "Treble Supported (ro.treble.enabled)", p.get("ro.treble.enabled"))
        self.add_point(s, 59, "AB Update (ro.build.ab_update)", p.get("ro.build.ab_update"))
        self.add_point(s, 60, "Virtual AB (ro.virtual_ab.enabled)", p.get("ro.virtual_ab.enabled"))
        self.add_point(s, 61, "Dynamic Partitions (ro.product.abd_partitions)", p.get("ro.product.abd_partitions"))
        self.add_point(s, 62, "VNDK Version (ro.vndk.version)", p.get("ro.vndk.version"))

    def _extract_kernel(self, field):
        kv = self._cat("/proc/version")
        if not kv:
            return "?"
        if field == "version":
            m = re.search(r'Linux version (\S+)', kv)
            return m.group(1) if m else "?"
        if field == "compiler":
            m = re.search(r'\(([^)]+@[^)]+)\)', kv)
            return m.group(1) if m else "?"
        if field == "gcc":
            m = re.search(r'(gcc version [\d.]+)', kv)
            return m.group(1) if m else "?"
        if field == "smp":
            return "Yes" if re.search(r'\bSMP\b', kv) else "No"
        if field == "preempt":
            return "Yes" if "preempt" in kv.lower() else "No"
        return "?"

    def _extract_uptime(self):
        uptime = self._cat("/proc/uptime")
        if uptime:
            secs = float(uptime.split()[0])
            days = int(secs // 86400)
            hrs = int((secs % 86400) // 3600)
            mins = int((secs % 3600) // 60)
            return f"{days}d {hrs}h {mins}m"
        return "?"

    def section_build(self):
        s = "BUILD INFO"
        p = self.props
        self.add_point(s, 63, "Build ID (ro.build.id)", p.get("ro.build.id"))
        self.add_point(s, 64, "Build Display ID (ro.build.display.id)", p.get("ro.build.display.id"))
        self.add_point(s, 65, "Build Fingerprint (ro.build.fingerprint)", p.get("ro.build.fingerprint"))
        self.add_point(s, 66, "Build Description (ro.build.description)", p.get("ro.build.description"))
        self.add_point(s, 67, "Build Type (ro.build.type)", p.get("ro.build.type"))
        self.add_point(s, 68, "Build Flavor (ro.build.flavor)", p.get("ro.build.flavor"))
        self.add_point(s, 69, "Build User (ro.build.user)", p.get("ro.build.user"))
        self.add_point(s, 70, "Build Host (ro.build.host)", p.get("ro.build.host"))
        self.add_point(s, 71, "Build Date (ro.build.date)", p.get("ro.build.date"))
        self.add_point(s, 72, "Build Date UTC (ro.build.date.utc)", p.get("ro.build.date.utc"))
        self.add_point(s, 73, "Build Version Incremental (ro.build.version.incremental)", p.get("ro.build.version.incremental"))
        self.add_point(s, 74, "Build Version Release (ro.build.version.release)", p.get("ro.build.version.release"))
        self.add_point(s, 75, "Build Version SDK (ro.build.version.sdk)", p.get("ro.build.version.sdk"))
        self.add_point(s, 76, "Build Version Codename (ro.build.version.codename)", p.get("ro.build.version.codename"))
        self.add_point(s, 77, "Build Version All (ro.build.version.all_codenames)", p.get("ro.build.version.all_codenames"))
        self.add_point(s, 78, "Build Version Security Patch (ro.build.version.security_patch)", p.get("ro.build.version.security_patch"))
        self.add_point(s, 79, "Build Version Base OS (ro.build.version.base_os)", p.get("ro.build.version.base_os"))
        self.add_point(s, 80, "Build Version Release Names (ro.build.version.release_names)", p.get("ro.build.version.release_names"))
        self.add_point(s, 81, "Build Version Release or Codename (ro.build.version.release_or_codename)", p.get("ro.build.version.release_or_codename"))
        self.add_point(s, 82, "Build Version Preview SDK (ro.build.version.preview_sdk)", p.get("ro.build.version.preview_sdk"))
        self.add_point(s, 83, "Build Version Min Support SDK (ro.build.version.min_support_sdk)", p.get("ro.build.version.min_support_sdk"))
        self.add_point(s, 84, "Build Characteristic (ro.build.characteristics)", p.get("ro.build.characteristics"))
        self.add_point(s, 85, "Build Abi List (ro.product.cpu.abilist)", p.get("ro.product.cpu.abilist"))
        self.add_point(s, 86, "Build Abi (ro.product.cpu.abi)", p.get("ro.product.cpu.abi"))
        self.add_point(s, 87, "Build Abi2 (ro.product.cpu.abi2)", p.get("ro.product.cpu.abi2"))
        self.add_point(s, 88, "Board Platform (ro.board.platform)", p.get("ro.board.platform"))
        self.add_point(s, 89, "Boot Baseband (ro.boot.baseband)", p.get("ro.boot.baseband"))
        self.add_point(s, 90, "Boot Hardware (ro.boot.hardware)", p.get("ro.boot.hardware"))
        self.add_point(s, 91, "Boot Serial (ro.boot.serialno)", p.get("ro.boot.serialno"))
        self.add_point(s, 92, "Boot Verified State (ro.boot.verifiedbootstate)", p.get("ro.boot.verifiedbootstate"))
        self.add_point(s, 93, "Boot Image CRC (ro.boot.image.crc)", p.get("ro.boot.image.crc"))
        self.add_point(s, 94, "Build Description Exact (ro.build.description)", p.get("ro.build.description"))
        self.add_point(s, 95, "Build Tags (ro.build.tags)", p.get("ro.build.tags"))

    def section_hardware(self):
        s = "HARDWARE"
        p = self.props
        cpu_raw = self._cat("/proc/cpuinfo")
        mem_raw = self._cat("/proc/meminfo")

        cpus = cpu_feats = cpu_arch = cpu_impl = cpu_part = cpu_model = 0
        cpu_impl_val = cpu_part_val = "?"
        for line in cpu_raw.splitlines():
            if re.match(r'^processor\s*:', line):
                cpus += 1
            m = re.match(r'^Hardware\s*:\s*(.*)', line)
            if m:
                cpu_model = m.group(1).strip()
            m = re.match(r'^CPU implementer\s*:\s*(.*)', line)
            if m:
                cpu_impl_val = m.group(1).strip()
            m = re.match(r'^CPU part\s*:\s*(.*)', line)
            if m:
                cpu_part_val = m.group(1).strip()
            m = re.match(r'^Features\s*:\s*(.*)', line)
            if m and not cpu_feats:
                cpu_feats = m.group(1).strip()
            m = re.match(r'^CPU architecture\s*:\s*(.*)', line)
            if m and not cpu_arch:
                cpu_arch = m.group(1).strip()

        soc_info = detect_cpu(p, cpu_impl_val, cpu_part_val)
        self.soc = soc_info

        mem = {}
        for line in mem_raw.splitlines():
            mm = re.match(r'^(\w+):\s+(\d+)', line)
            if mm:
                mem[mm.group(1)] = mm.group(2)

        def fmt_kb(key):
            v = mem.get(key)
            if v:
                kb = int(v)
                if kb > 1048576:
                    return f"{kb // 1024} MB ({kb / 1024 / 1024:.1f} GB)"
                return f"{kb // 1024} MB"
            return "?"

        self.add_point(s, 96, "SoC Vendor", soc_info.get("vendor"))
        self.add_point(s, 97, "SoC Series", soc_info.get("series"))
        self.add_point(s, 98, "SoC Model", soc_info.get("model"))
        self.add_point(s, 99, "SoC Full Name", soc_info.get("full_name"))
        self.add_point(s, 100, "CPU Cores Count", str(cpus) if cpus else "?")
        self.add_point(s, 101, "CPU Implementer", f"{cpu_impl_val} ({soc_info.get('cpu_impl_name', '?')})" if cpu_impl_val != "?" else "?")
        self.add_point(s, 102, "CPU Part", cpu_part_val)
        self.add_point(s, 103, "CPU Architecture", cpu_arch)
        self.add_point(s, 104, "CPU Features", cpu_feats[:120] if cpu_feats else "?")
        self.add_point(s, 105, "CPU BogoMIPS", self._extract_cpuinfo("BogoMIPS"))
        self.add_point(s, 106, "CPU Hardware", cpu_model if cpu_model != "?" else "?")
        self.add_point(s, 107, "CPU Revision", self._extract_cpuinfo("CPU revision"))
        self.add_point(s, 108, "CPU Variant", self._extract_cpuinfo("CPU variant"))
        self.add_point(s, 109, "Total RAM (MemTotal)", fmt_kb("MemTotal"))
        self.add_point(s, 110, "Available RAM (MemAvailable)", fmt_kb("MemAvailable"))
        self.add_point(s, 111, "Free RAM (MemFree)", fmt_kb("MemFree"))
        self.add_point(s, 112, "Cached RAM (Cached)", fmt_kb("Cached"))
        self.add_point(s, 113, "Buffers (Buffers)", fmt_kb("Buffers"))
        self.add_point(s, 114, "Active RAM (Active)", fmt_kb("Active"))
        self.add_point(s, 115, "Inactive RAM (Inactive)", fmt_kb("Inactive"))
        self.add_point(s, 116, "Active(anon) RAM (Active(anon))", fmt_kb("Active(anon)"))
        self.add_point(s, 117, "Inactive(anon) RAM (Inactive(anon))", fmt_kb("Inactive(anon)"))
        self.add_point(s, 118, "Active(file) RAM (Active(file))", fmt_kb("Active(file)"))
        self.add_point(s, 119, "Inactive(file) RAM (Inactive(file))", fmt_kb("Inactive(file)"))
        self.add_point(s, 120, "Unevictable RAM (Unevictable)", fmt_kb("Unevictable"))
        self.add_point(s, 121, "Mlocked RAM (Mlocked)", fmt_kb("Mlocked"))
        self.add_point(s, 122, "Swap Total (SwapTotal)", fmt_kb("SwapTotal"))
        self.add_point(s, 123, "Swap Free (SwapFree)", fmt_kb("SwapFree"))
        self.add_point(s, 124, "Swap Cached (SwapCached)", fmt_kb("SwapCached"))
        self.add_point(s, 125, "Dirty Pages (Dirty)", fmt_kb("Dirty"))
        self.add_point(s, 126, "Writeback (Writeback)", fmt_kb("Writeback"))
        self.add_point(s, 127, "AnonPages (AnonPages)", fmt_kb("AnonPages"))
        self.add_point(s, 128, "Mapped (Mapped)", fmt_kb("Mapped"))
        self.add_point(s, 129, "Shmem (Shmem)", fmt_kb("Shmem"))
        self.add_point(s, 130, "KernelStack (KernelStack)", fmt_kb("KernelStack"))
        self.add_point(s, 131, "PageTables (PageTables)", fmt_kb("PageTables"))
        self.add_point(s, 132, "VmallocTotal (VmallocTotal)", fmt_kb("VmallocTotal"))
        self.add_point(s, 133, "VmallocUsed (VmallocUsed)", fmt_kb("VmallocUsed"))
        self.add_point(s, 134, "VmallocChunk (VmallocChunk)", fmt_kb("VmallocChunk"))
        self.add_point(s, 135, "CmaTotal (CmaTotal)", fmt_kb("CmaTotal"))
        self.add_point(s, 136, "CmaFree (CmaFree)", fmt_kb("CmaFree"))
        self.add_point(s, 137, "HugePages Total (HugePages_Total)", fmt_kb("HugePages_Total"))
        self.add_point(s, 138, "HugePages Free (HugePages_Free)", fmt_kb("HugePages_Free"))
        self.add_point(s, 139, "Dalvik Heap Start Size (dalvik.vm.heapstartsize)", p.get("dalvik.vm.heapstartsize"))
        self.add_point(s, 140, "Dalvik Heap Growth Limit (dalvik.vm.heapgrowthlimit)", p.get("dalvik.vm.heapgrowthlimit"))
        self.add_point(s, 141, "Dalvik Heap Max Size (dalvik.vm.heapsize)", p.get("dalvik.vm.heapsize"))
        self.add_point(s, 142, "Dalvik Heap Min Free (dalvik.vm.heapminfree)", p.get("dalvik.vm.heapminfree"))
        self.add_point(s, 143, "Dalvik Heap Utilization (dalvik.vm.heaptargetutilization)", p.get("dalvik.vm.heaptargetutilization"))
        self.add_point(s, 144, "HWUI Cache Size (ro.hwui.cache_size)", p.get("ro.hwui.cache_size"))
        self.add_point(s, 145, "HWUI Cache Size For App (ro.hwui.cache_size_for_app)", p.get("ro.hwui.cache_size_for_app"))
        self.add_point(s, 146, "HWUI Texture Cache Size (ro.hwui.texture_cache_size)", p.get("ro.hwui.texture_cache_size"))
        self.add_point(s, 147, "HWUI Layer Cache Size (ro.hwui.layer_cache_size)", p.get("ro.hwui.layer_cache_size"))
        self.add_point(s, 148, "HWUI Path Cache Size (ro.hwui.path_cache_size)", p.get("ro.hwui.path_cache_size"))
        self.add_point(s, 149, "HWUI Gradient Cache Size (ro.hwui.gradient_cache_size)", p.get("ro.hwui.gradient_cache_size"))
        self.add_point(s, 150, "HWUI Drop Shadow Cache Size (ro.hwui.drop_shadow_cache_size)", p.get("ro.hwui.drop_shadow_cache_size"))
        self.add_point(s, 151, "HWUI R Buffer Cache Size (ro.hwui.r_buffer_cache_size)", p.get("ro.hwui.r_buffer_cache_size"))
        self.add_point(s, 152, "HWUI Texture Cache Size (ro.hwui.texture_cache_size)",
                         p.get("ro.hwui.texture_cache_size"))
        self.add_point(s, 153, "HWUI Buffer Cache Size (ro.hwui.buffer_cache_size)", p.get("ro.hwui.buffer_cache_size"))
        self.add_point(s, 154, "HWUI FBO Cache Size (ro.hwui.fbo_cache_size)", p.get("ro.hwui.fbo_cache_size"))
        self.add_point(s, 155, "CPU Governor (scaling_governor)", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor").strip())
        self.add_point(s, 156, "CPU Min Freq (cpu0)", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq").strip())
        self.add_point(s, 157, "CPU Max Freq (cpu0)", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq").strip())
        self.add_point(s, 158, "CPU Cur Freq (cpu0)", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq").strip())
        self.add_point(s, 159, "CPU Avail Freqs (cpu0)", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies").strip()[:120])
        self.add_point(s, 160, "CPU Avail Governors", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors").strip()[:120])
        self.add_point(s, 161, "CPU Online Count", self._extract_cpu_online())
        self.add_point(s, 162, "CPU Present Count", self._extract_cpu_present())
        self.add_point(s, 163, "CPU Possible Count", self._extract_cpu_possible())
        self.add_point(s, 164, "Architecture List (ro.product.cpu.abilist)", p.get("ro.product.cpu.abilist"))
        self.add_point(s, 165, "ABI2 (ro.product.cpu.abi2)", p.get("ro.product.cpu.abi2"))
        self.add_point(s, 166, "ABI List 32 (ro.product.cpu.abilist32)", p.get("ro.product.cpu.abilist32"))
        self.add_point(s, 167, "ABI List 64 (ro.product.cpu.abilist64)", p.get("ro.product.cpu.abilist64"))

    def _extract_cpuinfo(self, key):
        raw = self._cat("/proc/cpuinfo")
        m = re.search(rf'^{re.escape(key)}\s*:\s*(.*)', raw, re.M)
        return m.group(1).strip() if m else "?"

    def _extract_cpu_online(self):
        raw = self._cat("/sys/devices/system/cpu/online").strip()
        if raw:
            return raw
        return "?"

    def _extract_cpu_present(self):
        raw = self._cat("/sys/devices/system/cpu/present").strip()
        if raw:
            return raw
        return "?"

    def _extract_cpu_possible(self):
        raw = self._cat("/sys/devices/system/cpu/possible").strip()
        if raw:
            return raw
        return "?"

    def section_storage(self):
        s = "STORAGE"
        p = self.props
        df = self._cmd(["df", "-h"])

        self.add_point(s, 168, "Internal Storage Total", self._extract_df(df, "Total"))
        self.add_point(s, 169, "Internal Storage Used", self._extract_df(df, "Used"))
        self.add_point(s, 170, "Internal Storage Free", self._extract_df(df, "Avail"))
        self.add_point(s, 171, "System Partition Total", self._extract_df_part(df, "/system"))
        self.add_point(s, 172, "System Partition Used", "?")
        self.add_point(s, 173, "Data Partition Total", self._extract_df_part(df, "/data"))
        self.add_point(s, 174, "Data Partition Free", "?")
        self.add_point(s, 175, "Cache Partition Total", self._extract_df_part(df, "/cache"))
        self.add_point(s, 176, "External SD Card", self._detect_sdcard())
        self.add_point(s, 177, "SD Card Path", p.get("ro.sdcard.path"))
        self.add_point(s, 178, "Internal Storage Path (ro.storage.path)", p.get("ro.storage.path"))
        self.add_point(s, 179, "Emulated SD (ro.sys.sdcardfs)", p.get("ro.sys.sdcardfs"))
        self.add_point(s, 180, "Data block size", self._cat("/sys/block/mmcblk0/size").strip())
        self.add_point(s, 181, "MMC Name", self._cat("/sys/block/mmcblk0/device/name").strip())
        self.add_point(s, 182, "MMC Type", self._cat("/sys/block/mmcblk0/device/type").strip())
        self.add_point(s, 183, "MMC Vendor", self._cat("/sys/block/mmcblk0/device/manfid").strip())
        self.add_point(s, 184, "MMC Date", self._cat("/sys/block/mmcblk0/device/date").strip())
        self.add_point(s, 185, "MMC Fw Rev", self._cat("/sys/block/mmcblk0/device/fwrev").strip())
        self.add_point(s, 186, "MMC HW Rev", self._cat("/sys/block/mmcblk0/device/hwrev").strip())
        self.add_point(s, 187, "UFS Vendor", self._cat("/sys/devices/platform/soc/*/ufs*").strip()[:60])
        self.add_point(s, 188, "Partitions Table", self._extract_partitions())
        self.add_point(s, 189, "Mount Points (/proc/mounts)", self._extract_mounts())
        self.add_point(s, 190, "Filesystems Supported (/proc/filesystems)", self._extract_filesystems())
        self.add_point(s, 191, "F2FS Support", self._check_f2fs())
        self.add_point(s, 192, "EXT4 Support", self._check_ext4())
        self.add_point(s, 193, "Encryption Method (ro.crypto.fde)", p.get("ro.crypto.fde"))
        self.add_point(s, 194, "Encryption Type (ro.crypto.type)", p.get("ro.crypto.type"))
        self.add_point(s, 195, "Data Checksum (ro.sys.sdcardfs)", p.get("ro.sys.sdcardfs"))

    def _extract_df(self, df, field):
        lines = df.splitlines()
        for line in lines:
            if "/data" in line and not "/data/" in line.replace("/data/media", ""):
                parts = line.split()
                if len(parts) >= 4:
                    idx = {"Total": 1, "Used": 2, "Avail": 3}.get(field, 1)
                    return parts[idx] if idx < len(parts) else "?"
        return "?"

    def _extract_df_part(self, df, part):
        for line in df.splitlines():
            if line.startswith(part) or f" {part}" in line or f"/{part}" in line:
                parts = line.split()
                if len(parts) >= 2:
                    return parts[1]
        return "?"

    def _detect_sdcard(self):
        mounts = self._cat("/proc/mounts")
        if re.search(r'/sdcard|/external_sd|/storage/[0-9A-F]{4}-[0-9A-F]{4}', mounts):
            m = re.search(r'(/storage/[0-9A-F]{4}-[0-9A-F]{4})', mounts)
            if m:
                return f"Detected at {m.group(1)}"
            return "Detected"
        df = self._cmd(["df"])
        for line in df.splitlines():
            if "sdcard" in line.lower() or "external" in line.lower():
                return "Detected"
        return "Not detected"

    def _extract_partitions(self):
        r = self._cmd(["cat", "/proc/partitions"])
        return r[:120].replace("\n", " | ") if r else "?"

    def _extract_mounts(self):
        r = self._cmd(["cat", "/proc/mounts"])
        return f"{len(r.splitlines())} mount points" if r else "?"

    def _extract_filesystems(self):
        r = self._cmd(["cat", "/proc/filesystems"])
        fs_list = [l.strip().split()[-1] for l in r.splitlines() if l.strip() and not l.strip().startswith("nodev")]
        return ", ".join(fs_list[:10]) if fs_list else "?"

    def _check_f2fs(self):
        r = self._cmd(["cat", "/proc/filesystems"])
        return "Supported" if "f2fs" in r else "Not supported"

    def _check_ext4(self):
        r = self._cmd(["cat", "/proc/filesystems"])
        return "Supported" if "ext4" in r else "Not supported"

    def section_gpu(self):
        s = "GPU"
        p = self.props
        gles = self._dumpsys("graphicsstats")
        gpu_model = "?"
        for line in gles.splitlines():
            if "GLES" in line or "GPU" in line:
                gpu_model = line.strip()[:80]
                break
        if not gpu_model or gpu_model == "?":
            gpu_model = self._cmd(["dumpsys", "display", "|", "grep", "-i", "gles"])

        self.add_point(s, 196, "GPU Renderer", p.get("ro.hardware.gralloc"))
        self.add_point(s, 197, "GPU Model", gpu_model)
        self.add_point(s, 198, "OpenGL ES Version", p.get("ro.opengles.version"))
        self.add_point(s, 199, "Vulkan Support (ro.hardware.vulkan)", p.get("ro.hardware.vulkan"))
        self.add_point(s, 200, "Vulkan Level (ro.vulkan.level)", p.get("ro.vulkan.level"))
        self.add_point(s, 201, "EGL Config (ro.egl.config)", p.get("ro.egl.config"))
        self.add_point(s, 202, "EGL HW (ro.hardware.egl)", p.get("ro.hardware.egl"))
        self.add_point(s, 203, "HWUI Renderer (debug.hwui.renderer)", p.get("debug.hwui.renderer"))
        self.add_point(s, 204, "SF VSync Disabled (debug.sf.disable_vsync)", p.get("debug.sf.disable_vsync"))
        self.add_point(s, 205, "SF EGL Debug (debug.egl.debug_proc)", p.get("debug.egl.debug_proc"))
        self.add_point(s, 206, "SF HW (debug.sf.hw)", p.get("debug.sf.hw"))
        self.add_point(s, 207, "GPU Frequency (cur)", self._cat("/proc/gpu/cur_freq").strip() or self._cat("/sys/class/kgsl/kgsl-3d0/gpuclk").strip())
        self.add_point(s, 208, "GPU Max Frequency", self._cat("/sys/class/kgsl/kgsl-3d0/max_gpuclk").strip())
        self.add_point(s, 209, "GPU Min Frequency", self._cat("/sys/class/kgsl/kgsl-3d0/min_gpuclk").strip())
        self.add_point(s, 210, "GPU Available Frequencies", self._cat("/sys/class/kgsl/kgsl-3d0/gpu_available_frequencies").strip()[:120])
        self.add_point(s, 211, "GPU Governor", self._cat("/sys/class/kgsl/kgsl-3d0/devfreq/governor").strip())
        self.add_point(s, 212, "GPU Busy (%)", self._cat("/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage").strip())
        self.add_point(s, 213, "GPU Thermal Throttling", self._cat("/sys/class/kgsl/kgsl-3d0/thermal_pwrlevel").strip())
        self.add_point(s, 214, "Mali GPU Name", self._detect_mali())
        self.add_point(s, 215, "GPU OpenCL Support", self._detect_opencl())
        self.add_point(s, 216, "GPU Vulkan API Version", self._detect_vulkan())
        self.add_point(s, 217, "GPU Renderer String", p.get("debug.egl.hw"))
        self.add_point(s, 218, "GPU Gralloc Version", p.get("ro.hardware.gralloc"))

    def _detect_mali(self):
        raw = self._cat("/proc/mali/version")
        if raw:
            return raw.strip()[:80]
        raw2 = self._cmd(["cat", "/sys/devices/platform/mali*/version"])
        if raw2:
            return raw2.strip()[:80]
        soc = self.props.get("ro.board.platform", "")
        if "mt" in soc.lower():
            return "Mali (MediaTek integrated)"
        return "?"

    def _detect_opencl(self):
        for p in ["/system/vendor/lib/libOpenCL.so", "/system/lib/libOpenCL.so"]:
            r = self._cmd(["ls", p])
            if r and "No such" not in r:
                return "Supported (library found)"
        return "Not detected"

    def _detect_vulkan(self):
        p = self.props
        parts = []

        if p.get("ro.hardware.vulkan", "?"):
            parts.append(f"Support: {p['ro.hardware.vulkan']}")
        if p.get("ro.vulkan.api", "?"):
            parts.append(f"API: {p['ro.vulkan.api']}")
        if p.get("ro.vulkan.level", "?"):
            parts.append(f"Level: {p['ro.vulkan.level']}")

        raw = self._cmd(["dumpsys", "media.resource_manager", "|", "head", "-30"])
        if raw and any(k in raw.lower() for k in ("vulkan", "vk_")):
            parts.append(f"ResourceMgr: {raw[:60].strip()}")

        lib = self._cmd(["ls", "/system/lib64/libvulkan.so", "/vendor/lib64/libvulkan.so", "/system/lib/libvulkan.so"])
        if lib and "No such" not in lib:
            parts.append("libvulkan: present")

        return " | ".join(parts) if parts else "Not detected"

    def section_network(self):
        s = "NETWORK"
        p = self.props
        imei = "?"
        try:
            ime = self.sc._adb(["shell", "service", "call", "iphonesubinfo", "1"]).strip()
            digits = re.sub(r'[^0-9]', '', ime)
            imei = digits if len(digits) >= 14 else "Restricted"
        except:
            pass

        wifi_out = self._dumpsys("wifi")
        ip_addr = self._extract_wifi_field(wifi_out, "IP:", r'IP:\s*/?(\d+\.\d+\.\d+\.\d+)', "?")
        mac = self._extract_wifi_field(wifi_out, "MAC:", r'MAC:\s*([0-9a-fA-F:]{17})', "?")
        ssid = self._extract_wifi_field(wifi_out, "SSID:", r'SSID:\s*"([^"]*)"', "?")
        bssid = self._extract_wifi_field(wifi_out, "BSSID:", r'BSSID:\s*([0-9a-fA-F:]{17})', "?")
        rssi = self._extract_wifi_field(wifi_out, "RSSI:", r'RSSI:\s*(-?\d+)', "?")
        speed = self._extract_wifi_field(wifi_out, "Link speed:", r'Link speed:\s*(\d+Mbps)', "?")
        freq = self._extract_wifi_field(wifi_out, "Frequency:", r'Frequency:\s*(\d+MHz)', "?")

        self.add_point(s, 219, "IMEI (service call)", imei)
        self.add_point(s, 220, "WiFi SSID", ssid)
        self.add_point(s, 221, "WiFi BSSID", bssid)
        self.add_point(s, 222, "WiFi MAC Address", mac)
        self.add_point(s, 223, "IP Address", ip_addr)
        self.add_point(s, 224, "WiFi Link Speed", speed)
        self.add_point(s, 225, "WiFi Frequency", freq)
        self.add_point(s, 226, "WiFi Signal (RSSI)", rssi if rssi == "?" else f"{rssi} dBm")
        self.add_point(s, 227, "Gateway", self._extract_gateway())
        self.add_point(s, 228, "DNS Servers", self._extract_dns())
        self.add_point(s, 229, "Interface (wlan0)", self._extract_iface())
        self.add_point(s, 230, "MAC (settings secure bluetooth_address)", self._settings("secure", "bluetooth_address"))
        self.add_point(s, 231, "Bluetooth Name", self._settings("secure", "bluetooth_name"))
        self.add_point(s, 232, "Bluetooth State", self._settings("global", "bluetooth_on"))
        self.add_point(s, 233, "Bluetooth MAC (ro.boot.btmac)", p.get("ro.boot.btmac"))
        self.add_point(s, 234, "Carrier Name", p.get("gsm.sim.operator.alpha"))
        self.add_point(s, 235, "SIM Operator Numeric", p.get("gsm.sim.operator.numeric"))
        self.add_point(s, 236, "Network Operator", p.get("gsm.operator.alpha"))
        self.add_point(s, 237, "Network Operator Numeric", p.get("gsm.operator.numeric"))
        self.add_point(s, 238, "Baseband Version (gsm.version.baseband)", p.get("gsm.version.baseband"))
        self.add_point(s, 239, "Baseband (ro.boot.baseband)", p.get("ro.boot.baseband"))
        self.add_point(s, 240, "Data Roaming Setting", self._settings("global", "data_roaming"))
        self.add_point(s, 241, "Mobile Data Setting", self._settings("global", "mobile_data"))
        self.add_point(s, 242, "HTTP Proxy Setting", self._settings("global", "http_proxy"))
        self.add_point(s, 243, "WiFi Interface (wifi.interface)", p.get("wifi.interface"))
        self.add_point(s, 244, "Net DNS (net.dns1)", p.get("net.dns1"))
        self.add_point(s, 245, "Net DNS2 (net.dns2)", p.get("net.dns2"))
        self.add_point(s, 246, "Net Hostname (net.hostname)", p.get("net.hostname"))
        self.add_point(s, 247, "DHCP Server (dhcp.wlan0.server)", p.get("dhcp.wlan0.server"))
        self.add_point(s, 248, "DHCP Gateway (dhcp.wlan0.gateway)", p.get("dhcp.wlan0.gateway"))
        self.add_point(s, 249, "DHCP DNS1 (dhcp.wlan0.dns1)", p.get("dhcp.wlan0.dns1"))
        self.add_point(s, 250, "DHCP DNS2 (dhcp.wlan0.dns2)", p.get("dhcp.wlan0.dns2"))
        self.add_point(s, 251, "DHCP Lease Duration (dhcp.wlan0.leasetime)", p.get("dhcp.wlan0.leasetime"))
        self.add_point(s, 252, "DHCP Mask (dhcp.wlan0.mask)", p.get("dhcp.wlan0.mask"))

    def _extract_wifi_field(self, out, field, regex, fallback="?"):
        for line in out.splitlines():
            if field in line:
                m = re.search(regex, line)
                if m:
                    return m.group(1)
        return fallback

    def _extract_gateway(self):
        route = self._cmd(["ip", "route", "show", "table", "0"])
        if route:
            m = re.search(r'default\s+via\s+(\d+\.\d+\.\d+\.\d+)', route)
            if m:
                return m.group(1)
        return self.props.get("dhcp.wlan0.gateway", "?")

    def _extract_dns(self):
        dns = []
        for i in range(1, 4):
            v = self.props.get(f"net.dns{i}")
            if v:
                dns.append(v)
        if not dns:
            for i in range(1, 4):
                v = self.props.get(f"dhcp.wlan0.dns{i}")
                if v:
                    dns.append(v)
        return ", ".join(dns) if dns else "?"

    def _extract_iface(self):
        ip = self._cmd(["ip", "addr", "show", "wlan0"])
        if "state UP" in ip or "state UNKNOWN" in ip:
            m = re.search(r'inet\s+(\d+\.\d+\.\d+\.\d+)', ip)
            if m:
                return f"wlan0 ({m.group(1)})"
            return "wlan0"
        return "?"

    def section_telephony(self):
        s = "TELEPHONY"
        p = self.props
        tr = self._dumpsys("telephony.registry")
        net_type = self._cmd(["getprop", "gsm.network.type"])
        signal = self._extract_telephony_field(tr, "SignalStrength")

        self.add_point(s, 253, "Network Type (gsm.network.type)", net_type)
        self.add_point(s, 254, "Signal Strength", signal)
        self.add_point(s, 255, "Data Network Type (gsm.network.type)", net_type)
        self.add_point(s, 256, "Voice Network Type (gsm.network.type-voice)", p.get("gsm.network.type-voice"))
        self.add_point(s, 257, "SIM State (gsm.sim.state)", p.get("gsm.sim.state"))
        self.add_point(s, 258, "SIM Operator (gsm.sim.operator.alpha)", p.get("gsm.sim.operator.alpha"))
        self.add_point(s, 259, "SIM Numeric (gsm.sim.operator.numeric)", p.get("gsm.sim.operator.numeric"))
        self.add_point(s, 260, "SIM Country (gsm.sim.operator.iso-country)", p.get("gsm.sim.operator.iso-country"))
        self.add_point(s, 261, "SIM Serial (gsm.sim.serial)", p.get("gsm.sim.serial"))
        self.add_point(s, 262, "SIM ICCID (gsm.sim.iccid)", p.get("gsm.sim.iccid"))
        self.add_point(s, 263, "Phone Type (gsm.current.phone-type)", p.get("gsm.current.phone-type"))
        self.add_point(s, 264, "LTE EARFCN (gsm.lte.earfcn)", p.get("gsm.lte.earfcn"))
        self.add_point(s, 265, "NR/NR-NSA Status", self._detect_nr())
        self.add_point(s, 266, "VoLTE Supported", self._detect_volte())
        self.add_point(s, 267, "VoWiFi Supported", self._detect_vowifi())
        self.add_point(s, 268, "IMS Registration", self._detect_ims())
        self.add_point(s, 269, "Call State (gsm.call.state)", p.get("gsm.call.state"))
        self.add_point(s, 270, "Service State (gsm.operator.isroaming)", p.get("gsm.operator.isroaming"))
        self.add_point(s, 271, "Roaming Indicator", p.get("gsm.roaming.indicator"))
        self.add_point(s, 272, "Sim Count (ro.multisim.simcount)", p.get("ro.multisim.simcount"))
        self.add_point(s, 273, "DSDA/DSDS Support (persist.radio.multisim.config)", p.get("persist.radio.multisim.config"))
        self.add_point(s, 274, "SIM2 Operator (gsm.sim.operator.alpha_1)", p.get("gsm.sim.operator.alpha_1"))
        self.add_point(s, 275, "SIM2 Numeric (gsm.sim.operator.numeric_1)", p.get("gsm.sim.operator.numeric_1"))
        self.add_point(s, 276, "Cell Broadcast (ro.cellbroadcast.emergencyids)", p.get("ro.cellbroadcast.emergencyids"))
        self.add_point(s, 277, "CDMA Subscription (ro.cdma.subscription)", p.get("ro.cdma.subscription"))
        self.add_point(s, 278, "Tethering (tether.dun_required)", p.get("tether.dun_required"))
        self.add_point(s, 279, "MCC/MNC (gsm.operator.numeric)", p.get("gsm.operator.numeric"))
        self.add_point(s, 280, "LTE Band (gsm.lte.band)", p.get("gsm.lte.band"))
        self.add_point(s, 281, "NR Band (gsm.nr.band)", p.get("gsm.nr.band"))
        self.add_point(s, 282, "Data State (gsm.data.state)", p.get("gsm.data.state"))
        self.add_point(s, 283, "Data Connected (gsm.data.connect)", p.get("gsm.data.connect"))
        self.add_point(s, 284, "GPRS State (gsm.gprs.state)", p.get("gsm.gprs.state"))
        self.add_point(s, 285, "WAP Profile (gsm.wap.profile)", p.get("gsm.wap.profile"))
        self.add_point(s, 286, "MMS Proxy (gsm.mms.proxy)", p.get("gsm.mms.proxy"))
        self.add_point(s, 287, "MMS Port (gsm.mms.port)", p.get("gsm.mms.port"))
        self.add_point(s, 288, "Emergency Calls Only (ro.telephony.call_ring.delay)", p.get("ro.telephony.call_ring.delay"))
        self.add_point(s, 289, "Call Ring Delay (ro.telephony.call_ring.delay)", p.get("ro.telephony.call_ring.delay"))
        self.add_point(s, 290, "ECCL (ro.telephony.eccl)", p.get("ro.telephony.eccl"))
        self.add_point(s, 291, "APN Settings", self._extract_apn())
        self.add_point(s, 292, "Active Phone ID (gsm.active.phoneid)", p.get("gsm.active.phoneid"))
        self.add_point(s, 293, "Default SIM (persist.radio.default.sim)", p.get("persist.radio.default.sim"))
        self.add_point(s, 294, "Fast Dormancy (persist.radio.fastdorm)", p.get("persist.radio.fastdorm"))
        self.add_point(s, 295, "Data Preferred (persist.radio.data.preferred)", p.get("persist.radio.data.preferred"))

    def _extract_telephony_field(self, tr, field):
        for line in tr.splitlines():
            if field in line and ":" in line:
                parts = line.split(":", 1)
                return parts[1].strip()[:60]
        return "?"

    def _detect_nr(self):
        p = self.props
        if p.get("gsm.nr.band") or p.get("gsm.nr.state"):
            return "5G NR detected"
        net = self._cmd(["getprop", "gsm.network.type"])
        if "nr" in net.lower() or "5g" in net.lower():
            return "5G NR detected"
        if "nr_available" in self._dumpsys("telephony.registry").lower():
            return "5G NR capable"
        return "?"

    def _detect_volte(self):
        for k, v in self.props.items():
            if "volte" in k.lower() and v == "1":
                return "Supported"
        return self._settings("global", "volte_vt_enabled")

    def _detect_vowifi(self):
        for k, v in self.props.items():
            if "vowifi" in k.lower() or "wificalling" in k.lower():
                return f"Supported ({k}={v})"
        return "?"

    def _detect_ims(self):
        ims = self._dumpsys("ims")
        if "registered" in ims.lower():
            return "Registered"
        return "Not registered" if ims else "?"

    def _extract_apn(self):
        apn = self._cmd(["getprop", "gsm.apn"])
        if apn:
            return apn
        apn2 = self._cmd(["content", "query", "--uri", "content://telephony/carriers", "--projection", "name,apn"])
        return apn2[:120].replace("\n", " | ") if apn2 else "?"

    def section_display(self):
        s = "DISPLAY"
        p = self.props
        dpy = self._dumpsys("display")
        wm_size = self._cmd(["wm", "size"]).replace("Physical size: ", "").strip()
        wm_density = self._cmd(["wm", "density"]).replace("Physical density: ", "").strip()
        brightness = self._settings("system", "screen_brightness")
        timeout = self._settings("system", "screen_off_timeout")
        auto_bright = self._settings("system", "screen_brightness_mode")

        rez = wm_size if wm_size else "?"
        density = f"{wm_density} dpi" if wm_density else "?"
        hdr = "?"
        refresh = "?"
        for line in dpy.splitlines():
            m = re.search(r'refresh.*?rate.*?([\d.]+)', line, re.I)
            if m and refresh == "?":
                refresh = m.group(1)
            if "hdr" in line.lower() and "true" in line.lower():
                hdr = "Supported"

        self.add_point(s, 296, "Resolution (wm size)", rez)
        self.add_point(s, 297, "Density (wm density)", density)
        self.add_point(s, 298, "Refresh Rate", f"{refresh} Hz" if refresh != "?" else "?")
        self.add_point(s, 299, "HDR Support", hdr)
        self.add_point(s, 300, "LCD Density (ro.sf.lcd_density)", p.get("ro.sf.lcd_density"))
        self.add_point(s, 301, "SF HW (debug.sf.hw)", p.get("debug.sf.hw"))
        self.add_point(s, 302, "SF VSync (debug.sf.disable_vsync)", p.get("debug.sf.disable_vsync"))
        self.add_point(s, 303, "Display ID", self._extract_display_id(dpy))
        self.add_point(s, 304, "Brightness", brightness)
        self.add_point(s, 305, "Auto Brightness", "On" if auto_bright == "1" else "Off")
        self.add_point(s, 306, "Screen Off Timeout", f"{timeout}ms" if timeout != "?" else "?")
        self.add_point(s, 307, "Color Mode (persist.sys.sf.color_mode)", p.get("persist.sys.sf.color_mode"))
        self.add_point(s, 308, "Color Saturation (persist.sys.sf.color_saturation)", p.get("persist.sys.sf.color_saturation"))
        self.add_point(s, 309, "HW Composer (ro.hardware.hwcomposer)", p.get("ro.hardware.hwcomposer"))
        self.add_point(s, 310, "Display Rotation (ro.sf.hwrotation)", p.get("ro.sf.hwrotation"))
        self.add_point(s, 311, "GPU Compositor", p.get("debug.composition.type"))
        self.add_point(s, 312, "Panel Name", self._extract_panel())
        self.add_point(s, 313, "Panel Vendor", self._extract_panel_vendor())
        self.add_point(s, 314, "Display Power Savings", self._settings("system", "display_power_savings"))
        self.add_point(s, 315, "Adaptive Brightness", self._settings("system", "adaptive_brightness"))
        self.add_point(s, 316, "Night Mode (settings secure night_display_activated)", self._settings("secure", "night_display_activated"))
        self.add_point(s, 317, "Reading Mode", self._settings("system", "reading_mode"))
        self.add_point(s, 318, "Screen Mode (persist.sys.screen_mode)", p.get("persist.sys.screen_mode"))
        self.add_point(s, 319, "Scaling Mode (persist.sys.sf.nobootanimation)", p.get("persist.sys.sf.nobootanimation"))
        self.add_point(s, 320, "Resolution Width", rez.split("x")[0] if "x" in str(rez) else "?")
        self.add_point(s, 321, "Resolution Height", rez.split("x")[1] if "x" in str(rez) else "?")
        self.add_point(s, 322, "DPI X (ro.sf.lcd_density)", p.get("ro.sf.lcd_density"))
        self.add_point(s, 323, "DPI Y (ro.sf.lcd_density)", p.get("ro.sf.lcd_density"))
        self.add_point(s, 324, "VSync (ro.vsync.enabled)", p.get("ro.vsync.enabled"))
        self.add_point(s, 325, "HW Overlays (debug.sf.enable_hwc_vds)", p.get("debug.sf.enable_hwc_vds"))
        self.add_point(s, 326, "Display Count", self._extract_display_count(dpy))
        self.add_point(s, 327, "Display Type", self._detect_display_type())
        self.add_point(s, 328, "Panel Serial", self._extract_panel_serial())
        self.add_point(s, 329, "Screen Resolution Dumped", self._extract_display_rez(dpy))
        self.add_point(s, 330, "Display Scale (persist.sys.display_scale)", p.get("persist.sys.display_scale"))

    def _extract_display_id(self, dpy):
        for line in dpy.splitlines():
            if "display" in line.lower() and "id" in line.lower() and ":" in line:
                return line.strip()[:40]
        return "?"

    def _extract_panel(self):
        for path in ["/sys/class/graphics/fb0/device/panel_name",
                      "/sys/class/graphics/fb0/panel_name",
                      "/sys/class/graphics/fb0/device/name",
                      "/sys/class/graphics/fb0/name"]:
            r = self._cat(path).strip()
            if r:
                return r[:60]
        return "?"

    def _extract_panel_vendor(self):
        for path in ["/sys/class/graphics/fb0/device/panel_vendor",
                      "/sys/class/graphics/fb0/panel_vendor",
                      "/sys/class/graphics/fb0/vendor"]:
            r = self._cat(path).strip()
            if r:
                return r[:60]
        return "?"

    def _extract_panel_serial(self):
        r = self._cat("/sys/class/graphics/fb0/device/panel_serial").strip()
        return r if r else "?"

    def _detect_display_type(self):
        for path in ["/sys/class/graphics/fb0/device/panel_type",
                      "/sys/class/graphics/fb0/type"]:
            r = self._cat(path).strip()
            if r:
                return r[:40]
        dpy = self._dumpsys("display")
        if "oled" in dpy.lower() or "amoled" in dpy.lower():
            return "OLED/AMOLED"
        if "lcd" in dpy.lower():
            return "LCD"
        return "?"

    def _extract_display_count(self, dpy):
        count = 0
        for line in dpy.splitlines():
            if "display" in line.lower() and "id=" in line.lower():
                count += 1
        return str(count) if count > 0 else "1"

    def _extract_display_rez(self, dpy):
        for line in dpy.splitlines():
            m = re.search(r'(\d+)x(\d+)', line)
            if m:
                return m.group(0)
        return "?"

    def section_battery(self):
        s = "BATTERY"
        raw = self._dumpsys("battery")
        bat = {}
        for line in raw.splitlines():
            ls = line.strip()
            m = re.match(r'^\s*(\w[\w\s(/-]+):\s+(.+)$', ls)
            if m:
                bat[m.group(1).strip()] = m.group(2).strip()
            else:
                m = re.match(r'^\s*(\w+)\s*=\s*(.+)$', ls)
                if m:
                    bat[m.group(1).strip()] = m.group(2).strip()

        def b(key):
            return bat.get(key, "?")

        temp_v = b("temperature")
        try:
            temp_v = f"{int(temp_v) / 10:.1f}°C"
        except:
            pass
        volt_v = b("voltage")
        try:
            volt_v = f"{int(volt_v)} mV ({int(volt_v) / 1000:.3f}V)"
        except:
            pass

        self.add_point(s, 331, "Battery Level", f"{b('level')}%" if b("level") != "?" else "?")
        self.add_point(s, 332, "Battery Status", b("status"))
        self.add_point(s, 333, "Battery Health", b("health"))
        self.add_point(s, 334, "Battery Temperature", temp_v)
        self.add_point(s, 335, "Battery Voltage", volt_v)
        self.add_point(s, 336, "Battery Current (mA)", b("current now"))
        self.add_point(s, 337, "Battery Technology", b("technology"))
        self.add_point(s, 338, "Battery Present", b("present"))
        self.add_point(s, 339, "Battery Capacity (ro.battery.capacity)", self._get("ro.battery.capacity"))
        self.add_point(s, 340, "Battery Charge Counter", b("charge counter"))
        self.add_point(s, 341, "Battery Type (ro.battery.type)", self._get("ro.battery.type"))
        self.add_point(s, 342, "AC Powered", b("AC powered"))
        self.add_point(s, 343, "USB Powered", b("USB powered"))
        self.add_point(s, 344, "Wireless Powered", b("Wireless powered"))
        self.add_point(s, 345, "Dock Powered", b("Dock powered"))
        self.add_point(s, 346, "Fast Charger (ro.boot.fastcharge)", self._get("ro.boot.fastcharge"))
        self.add_point(s, 347, "Battery Serial (ro.boot.batteryserial)", self._get("ro.boot.batteryserial"))
        self.add_point(s, 348, "Charge Type (persist.sys.chargetype)", self._get("persist.sys.chargetype"))
        self.add_point(s, 349, "Current Average", b("current avg"))
        self.add_point(s, 350, "Step Charging Enabled", b("step charging enabled"))
        self.add_point(s, 351, "Battery Capacity Level (ro.product.battery)", self._get("ro.product.battery"))
        self.add_point(s, 352, "Power Profile", self._detect_power_profile())
        self.add_point(s, 353, "Battery Cycles (sys/class/power_supply/bms/cycle_count)", self._cat("/sys/class/power_supply/bms/cycle_count").strip())
        self.add_point(s, 354, "Battery Charge Full", self._cat("/sys/class/power_supply/battery/charge_full").strip())
        self.add_point(s, 355, "Battery Charge Full Design", self._cat("/sys/class/power_supply/battery/charge_full_design").strip())
        self.add_point(s, 356, "Battery Capacity Raw", self._cat("/sys/class/power_supply/battery/capacity").strip())
        self.add_point(s, 357, "Battery Status Raw", self._cat("/sys/class/power_supply/battery/status").strip())
        self.add_point(s, 358, "Battery Health Raw", self._cat("/sys/class/power_supply/battery/health").strip())
        self.add_point(s, 359, "Battery Temp Raw", self._cat("/sys/class/power_supply/battery/temp").strip())
        self.add_point(s, 360, "Power Supply Type", self._cat("/sys/class/power_supply/battery/type").strip())

    def _get(self, key):
        return self.props.get(key, "?")

    def _detect_power_profile(self):
        raw = self._cat("/system/etc/power_profile.xml")
        if raw:
            return "Custom power profile"
        raw2 = self._cat("/data/system/power_profile.xml")
        if raw2:
            return "User power profile"
        return "Default"

    def section_sensors(self):
        s = "SENSORS"
        raw = self._dumpsys("sensorservice")
        sensors = []
        for line in raw.splitlines():
            m = re.match(r'\s*(\d+)\|(.+)', line)
            if m:
                sensors.append(m.group(2).strip())

        sensor_types = [
            "Accelerometer", "Gyroscope", "Magnetometer", "Proximity",
            "Light", "Pressure", "Humidity", "Temperature",
            "Step Counter", "Step Detector", "Gravity",
            "Linear Acceleration", "Rotation Vector", "Game Rotation Vector",
            "Geo Rotation Vector", "Significant Motion", "Tilt Detector",
            "Orientation", "Heart Rate", "Hall Effect",
            "Fingerprint", "Iris", "Face Detection",
            "SAR", "Color", "IR Gesture",
            "Motion Detect", "Stationary Detect", "Time of Flight",
            "Flip", "Grip",
        ]

        detected = []
        for st in sensor_types:
            if st.lower() in raw.lower():
                detected.append(st)

        for i, sn in enumerate(detected[:36], 361):
            self.add_point(s, i, sn, "Detected")

        for i, sn in enumerate(sensor_types):
            idx = 361 + i
            if idx > 396:
                break
            if sn not in detected:
                self.add_point(s, idx, sn, "Not detected")

        remaining = max(0, 396 - 361 + 1 - len(detected))
        # Fill remaining with common sensor checks
        extras = ["Geomagnetic", "Uncalibrated Gyro", "Uncalibrated Mag",
                   "Heart Rate Monitor", "Body/Hand Gesture", "RGB Light",
                   "IR Temperature", "Pedometer", "Wake Gesture",
                   "Pick Up Gesture", "Glance Gesture", "Touch Gesture",
                   "Table Mode", "Wrist Tilt", "Device Orientation"]
        ei = 0
        for i in range(361, 397):
            if i > len(self.points) - 1 or self.points[-1].get("num", 0) < i:
                pass
        for extra in extras:
            if extra not in detected:
                self.add_point(s, 361 + extras.index(extra) + len(detected), extra, "Not detected")

    def section_camera(self):
        s = "CAMERA"
        raw = self._dumpsys("media.camera")
        cam_ids = sorted(set(re.findall(r'Camera\s+(\d+):', raw)))

        if not cam_ids:
            cam_ids = ["0", "1"]

        self.add_point(s, 397, "Camera Count", str(len(cam_ids)))
        for i, cid in enumerate(cam_ids, 398):
            if i > 420:
                break
            facing = "Rear"
            m = re.search(rf'Camera\s+{re.escape(cid)}:', raw)
            after = raw[m.end():m.end()+500] if m else ""
            if "front" in after.lower():
                facing = "Front"
            rez = "?"
            m_r = re.search(r'(\d{3,4})x(\d{3,4})', after)
            if m_r:
                rez = m_r.group(0)
            flash = "?"
            if "flash" in after.lower() and ("true" in after.lower() or "supported" in after.lower()):
                flash = "Yes"
            self.add_point(s, i, f"Camera {cid} ({facing})", f"Res: {rez}, Flash: {flash}")

        # Additional camera points
        cam_feats = ["Video Recording", "HDR Mode", "Portrait Mode", "Night Mode",
                      "Pro Mode", "Slow Motion", "Time Lapse", "Panorama",
                      "AI Camera", "Beauty Mode", "AR Emoji", "Scene Detection",
                      "RAW Capture", "EIS Support", "OIS Support", "AF Support",
                      "Flash Type (LED)", "Zoom Support", "Ultra-wide", "Macro Mode",
                      "Depth Sensor", "ToF Sensor"]
        for i, feat in enumerate(cam_feats, 421):
            if i > 438:
                break
            val = "?"
            if feat.lower().replace(" ", "") in raw.lower().replace(" ", ""):
                val = "Yes"
            self.add_point(s, i, feat, val)

    def section_security(self):
        s = "SECURITY"
        p = self.props
        su_check = ""
        try:
            su_check = self.sc._adb(["shell", "which", "su"], timeout=5).strip()
        except:
            pass
        selinux_mode = self._cmd(["getenforce"])

        self.add_point(s, 439, "Security Patch Level", p.get("ro.build.version.security_patch"))
        self.add_point(s, 440, "Vendor Security Patch", p.get("ro.vendor.build.security_patch"))
        self.add_point(s, 441, "SELinux Status", selinux_mode)
        self.add_point(s, 442, "SELinux Property (ro.build.selinux)", p.get("ro.build.selinux"))
        self.add_point(s, 443, "Verified Boot State", p.get("ro.boot.verifiedbootstate"))
        self.add_point(s, 444, "Encryption State (ro.crypto.state)", p.get("ro.crypto.state"))
        self.add_point(s, 445, "Encryption Type (ro.crypto.type)", p.get("ro.crypto.type"))
        self.add_point(s, 446, "Force Encryption (ro.crypto.force_encrypt)", p.get("ro.crypto.force_encrypt"))
        self.add_point(s, 447, "FBE Enabled (ro.crypto.fbe)", p.get("ro.crypto.fbe"))
        self.add_point(s, 448, "Debug Enabled (ro.debuggable)", p.get("ro.debuggable"))
        self.add_point(s, 449, "ADB Secure (ro.adb.secure)", p.get("ro.adb.secure"))
        self.add_point(s, 450, "OEM Unlock Supported (ro.oem_unlock_supported)", p.get("ro.oem_unlock_supported"))
        self.add_point(s, 451, "Root Binary", f"Detected: {su_check}" if su_check else "Not found")
        self.add_point(s, 452, "Magisk Detection", self._detect_magisk())
        self.add_point(s, 453, "Superuser APK", self._detect_superuser())
        self.add_point(s, 454, "Lock Screen Timeout", self._settings("secure", "lock_screen_lock_after_timeout"))
        self.add_point(s, 455, "Lock Screen Type", self._detect_lock_type())
        self.add_point(s, 456, "KNOX Status (ro.config.knox)", p.get("ro.config.knox"))
        self.add_point(s, 457, "Samsung KNOX (ro.security.knox.vers)", p.get("ro.security.knox.vers"))
        self.add_point(s, 458, "TIMA (ro.security.tima.version)", p.get("ro.security.tima.version"))
        self.add_point(s, 459, "TEE Support", self._detect_tee())
        self.add_point(s, 460, "TPM Support (ro.tpm.enabled)", p.get("ro.tpm.enabled"))
        self.add_point(s, 461, "KeyStore Type (ro.keystore.type)", p.get("ro.keystore.type"))
        self.add_point(s, 462, "Hardware KeyStore (ro.hardware.keystore)", p.get("ro.hardware.keystore"))
        self.add_point(s, 463, "Face Unlock (ro.faceunlock.enabled)", p.get("ro.faceunlock.enabled"))
        self.add_point(s, 464, "Fingerprint Sensor (ro.boot.fingerprint)", p.get("ro.boot.fingerprint"))
        self.add_point(s, 465, "Fingerprint H/W (ro.hardware.fingerprint)", p.get("ro.hardware.fingerprint"))
        self.add_point(s, 466, "Iris Scanner (ro.hardware.iris)", p.get("ro.hardware.iris"))
        self.add_point(s, 467, "UAD Detection", self._detect_uad())
        self.add_point(s, 468, "Package Signature Check (ro.config.nocheckin)", p.get("ro.config.nocheckin"))
        self.add_point(s, 469, "Allow Mock Location (ro.allow.mock.location)", p.get("ro.allow.mock.location"))
        self.add_point(s, 470, "Build Tags Contains Test Keys", "Yes" if "test-keys" in p.get("ro.build.tags", "") else "No")
        self.add_point(s, 471, "Build Type Is Eng", "Yes" if p.get("ro.build.type") == "eng" else "No")
        self.add_point(s, 472, "Build Type Is Userdebug", "Yes" if p.get("ro.build.type") == "userdebug" else "No")
        self.add_point(s, 473, "DM-Verity (ro.boot.veritymode)", p.get("ro.boot.veritymode"))
        self.add_point(s, 474, "AVB (ro.boot.avb_version)", p.get("ro.boot.avb_version"))
        self.add_point(s, 475, "Force User Encryption (ro.crypto.force_user_encryption)", p.get("ro.crypto.force_user_encryption"))
        self.add_point(s, 476, "Credentials Protection (persist.sys.credentials_enable)", p.get("persist.sys.credentials_enable"))
        self.add_point(s, 477, "SM/Protection (persist.sys.protect)", p.get("persist.sys.protect"))
        self.add_point(s, 478, "Lock Pattern Visible (lock_pattern_visible)", self._settings("system", "lock_pattern_visible_pattern"))
        self.add_point(s, 479, "Password Visible (lock_visible_password)", self._settings("system", "lock_visible_password"))
        self.add_point(s, 480, "ADB Auth Keys", self._detect_adb_keys())
        self.add_point(s, 481, "Known Exploit Patterns", self._detect_exploit_patterns())

    def _detect_magisk(self):
        try:
            r = self.sc._adb(["shell", "su", "-c", "magisk -v"], timeout=5).strip()
            return f"Magisk {r}" if r else "?"
        except:
            pass
        try:
            r = self.sc._adb(["shell", "ls", "/data/adb/magisk"], timeout=5).strip()
            return "Detected at /data/adb/magisk" if "No such" not in r else "?"
        except:
            return "?"

    def _detect_superuser(self):
        pkgs = self.sc._adb(["shell", "pm", "list", "packages"])
        su_pkgs = ["com.noshufou.android.su", "com.thirdparty.superuser",
                    "eu.chainfire.supersu", "com.koushikdutta.superuser",
                    "com.topjohnwu.magisk"]
        for sp in su_pkgs:
            if sp in pkgs:
                return f"Detected: {sp}"
        return "Not found"

    def _detect_lock_type(self):
        locks = self._cmd(["cmd", "lock_settings", "get-display"])
        if "none" in locks.lower():
            return "None"
        if "pin" in locks.lower():
            return "PIN"
        if "password" in locks.lower():
            return "Password"
        if "pattern" in locks.lower():
            return "Pattern"
        return locks[:40] if locks else "?"

    def _detect_tee(self):
        for pn in ["/system/vendor/lib/libTEE.so", "/system/lib/libTEE.so",
                     "/vendor/app/mcRegistry", "/system/app/mcRegistry"]:
            r = self._cmd(["ls", pn])
            if r and "No such" not in r:
                return f"Detected ({pn})"
        return "?"

    def _detect_uad(self):
        uid = self._cmd(["pm", "dump", "com.android.settings", "|", "grep", "uid="])
        if uid:
            return "UAD present in settings"
        return "?"

    def _detect_adb_keys(self):
        r = self._cmd(["ls", "/data/misc/adb/adb_keys"])
        if r and "No such" not in r:
            return "Present"
        return "Not found"

    def _detect_exploit_patterns(self):
        flags = []
        if self.props.get("ro.debuggable") == "1":
            flags.append("Debuggable")
        if self.props.get("ro.build.type") == "userdebug":
            flags.append("Userdebug")
        if self.props.get("ro.build.tags", "").find("test-keys") >= 0:
            flags.append("TestKeys")
        if not flags:
            return "No common exploit patterns detected"
        return "Vulnerable flags: " + ", ".join(flags)

    def section_performance(self):
        s = "PERFORMANCE"

        self.add_point(s, 482, "CPU Governor", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor").strip())
        self.add_point(s, 483, "CPU Min Freq (kHz)", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq").strip())
        self.add_point(s, 484, "CPU Max Freq (kHz)", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq").strip())
        self.add_point(s, 485, "CPU Cur Freq (kHz)", self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq").strip())
        self.add_point(s, 486, "CPU L2 Cache", self._cat("/sys/devices/system/cpu/cpu0/cache/index2/size").strip())
        self.add_point(s, 487, "CPU L1 I-Cache", self._cat("/sys/devices/system/cpu/cpu0/cache/index0/size").strip())
        self.add_point(s, 488, "CPU L1 D-Cache", self._cat("/sys/devices/system/cpu/cpu0/cache/index1/size").strip())
        self.add_point(s, 489, "CPU L3 Cache", self._cat("/sys/devices/system/cpu/cpu0/cache/index3/size").strip())
        self.add_point(s, 490, "I/O Scheduler", self._cat("/sys/block/mmcblk0/queue/scheduler").strip())
        self.add_point(s, 491, "I/O Read Ahead (KB)", self._cat("/sys/block/mmcblk0/queue/read_ahead_kb").strip())
        self.add_point(s, 492, "I/O NR Requests", self._cat("/sys/block/mmcblk0/queue/nr_requests").strip())
        self.add_point(s, 493, "I/O Max Sectors (KB)", self._cat("/sys/block/mmcblk0/queue/max_sectors_kb").strip())
        self.add_point(s, 494, "I/O Rotational", self._cat("/sys/block/mmcblk0/queue/rotational").strip())
        self.add_point(s, 495, "I/O Add Random", self._cat("/sys/block/mmcblk0/queue/add_random").strip())
        self.add_point(s, 496, "I/O Iostats", self._cat("/sys/block/mmcblk0/queue/iostats").strip())
        self.add_point(s, 497, "I/O Nomerges", self._cat("/sys/block/mmcblk0/queue/nomerges").strip())
        self.add_point(s, 498, "I/O RQ Affinity", self._cat("/sys/block/mmcblk0/queue/rq_affinity").strip())
        self.add_point(s, 499, "ZRAM Size", self._detect_zram())
        self.add_point(s, 500, "ZRAM Algorithm", self._detect_zram_alg())
        self.add_point(s, 501, "Entropy Pool (random/entropy_avail)", self._cat("/proc/sys/kernel/random/entropy_avail").strip())
        self.add_point(s, 502, "Entropy Pool Size (random/poolsize)", self._cat("/proc/sys/kernel/random/poolsize").strip())
        self.add_point(s, 503, "TCP Congestion Algorithm", self._cat("/proc/sys/net/ipv4/tcp_congestion_control").strip())
        self.add_point(s, 504, "TCP Buffer Min (tcp_wmem min)", self._cat("/proc/sys/net/ipv4/tcp_wmem").strip().split()[0] if self._cat("/proc/sys/net/ipv4/tcp_wmem") else "?")
        self.add_point(s, 505, "TCP Buffer Default (tcp_wmem def)", self._cat("/proc/sys/net/ipv4/tcp_wmem").strip().split()[1] if self._cat("/proc/sys/net/ipv4/tcp_wmem").strip().split() else "?")
        self.add_point(s, 506, "TCP Buffer Max (tcp_wmem max)", self._cat("/proc/sys/net/ipv4/tcp_wmem").strip().split()[2] if self._cat("/proc/sys/net/ipv4/tcp_wmem").strip().split() else "?")
        self.add_point(s, 507, "VM Dirty Ratio", self._cat("/proc/sys/vm/dirty_ratio").strip())
        self.add_point(s, 508, "VM Dirty Background Ratio", self._cat("/proc/sys/vm/dirty_background_ratio").strip())
        self.add_point(s, 509, "VM Dirty Expire Centisecs", self._cat("/proc/sys/vm/dirty_expire_centisecs").strip())
        self.add_point(s, 510, "VM Dirty Writeback Centisecs", self._cat("/proc/sys/vm/dirty_writeback_centisecs").strip())
        self.add_point(s, 511, "VM VFS Cache Pressure", self._cat("/proc/sys/vm/vfs_cache_pressure").strip())
        self.add_point(s, 512, "VM Min Free KB", self._cat("/proc/sys/vm/min_free_kbytes").strip())
        self.add_point(s, 513, "VM Drop Caches (current)", self._cat("/proc/sys/vm/drop_caches").strip())
        self.add_point(s, 514, "VM Extfrag Threshold", self._cat("/proc/sys/vm/extfrag_threshold").strip())
        self.add_point(s, 515, "VM Page Cluster", self._cat("/proc/sys/vm/page-cluster").strip())
        self.add_point(s, 516, "VM Swappiness", self._cat("/proc/sys/vm/swappiness").strip())
        self.add_point(s, 517, "VM Overcommit Memory", self._cat("/proc/sys/vm/overcommit_memory").strip())
        self.add_point(s, 518, "VM Overcommit Ratio", self._cat("/proc/sys/vm/overcommit_ratio").strip())
        self.add_point(s, 519, "GPU Frequency Performance", self._detect_gpu_perf())
        self.add_point(s, 520, "Ramdisk Size", self._detect_ramdisk())
        self.add_point(s, 521, "Cache Partition Size", self._extract_part_size("/cache"))
        self.add_point(s, 522, "Data Partition Size", self._extract_part_size("/data"))
        self.add_point(s, 523, "System Partition Size", self._extract_part_size("/system"))
        self.add_point(s, 524, "Persist Partition Size", self._extract_part_size("/persist"))
        self.add_point(s, 525, "Vendor Partition Size", self._extract_part_size("/vendor"))
        self.add_point(s, 526, "Boot Partition Size", self._extract_part_size("/boot"))
        self.add_point(s, 527, "Recovery Partition Size", self._extract_part_size("/recovery"))
        self.add_point(s, 528, "Dalvik Cache Size", self._detect_dalvik_cache())

    def _detect_zram(self):
        for pn in ["/sys/block/zram0/disksize", "/sys/block/zram0/size"]:
            r = self._cat(pn).strip()
            if r:
                try:
                    kb = int(r)
                    return f"{kb // 1024} MB" if kb > 1024 else f"{kb} KB"
                except:
                    return r
        return "?"

    def _detect_zram_alg(self):
        r = self._cat("/sys/block/zram0/comp_algorithm").strip()
        return r if r else "?"

    def _detect_gpu_perf(self):
        gpu = self._cat("/sys/class/kgsl/kgsl-3d0/devfreq/cur_freq").strip()
        if gpu:
            return f"{int(gpu) // 1000000} MHz" if gpu.isdigit() else gpu
        return "?"

    def _detect_ramdisk(self):
        r = self._cmd(["df", "/"])
        for line in r.splitlines():
            if "/" in line and not "Mounted" in line:
                parts = line.split()
                if len(parts) >= 2:
                    return parts[1]
        return "?"

    def _extract_part_size(self, part):
        df = self._cmd(["df", part])
        for line in df.splitlines():
            parts = line.split()
            if len(parts) >= 2 and part in line:
                return parts[1]
        return "?"

    def _detect_dalvik_cache(self):
        r = self._cmd(["du", "-sh", "/data/dalvik-cache"])
        if r:
            return r.split()[0] if r.split() else "?"
        return "?"

    def section_thermal(self):
        s = "THERMAL"
        zones = self._cmd(["ls", "/sys/class/thermal/"])

        self.add_point(s, 529, "Thermal Zone Count", str(len([z for z in zones.split() if "thermal_zone" in z])))

        tz_data = []
        for line in zones.split():
            if "thermal_zone" in line:
                ttype = self._cat(f"/sys/class/thermal/{line}/type").strip()
                ttemp = self._cat(f"/sys/class/thermal/{line}/temp").strip()
                if ttype and ttemp:
                    try:
                        tc = int(ttemp) / 1000
                        tz_data.append(f"{ttype}: {tc:.1f}C")
                    except:
                        tz_data.append(f"{ttype}: {ttemp}C")

        for i, td in enumerate(tz_data[:15], 530):
            if i > 545:
                break
            self.add_point(s, i, "Thermal Zone", td)

        self.add_point(s, 546, "CPU Thermal Throttling", self._detect_throttle())
        self.add_point(s, 547, "GPU Thermal Level", self._cat("/sys/class/kgsl/kgsl-3d0/thermal_pwrlevel").strip())
        self.add_point(s, 548, "Battery Temp in Thermal", self._detect_bat_temp())
        self.add_point(s, 549, "Cooling Device Count", str(len([z for z in zones.split() if "cooling_device" in z])))
        self.add_point(s, 550, "Critical Temp Threshold", self._detect_crit_temp())
        self.add_point(s, 551, "Skin Temperature", self._cat("/sys/class/thermal/thermal_zone*/temp").strip()[:60])
        self.add_point(s, 552, "PMIC Temperature", self._detect_pmic_temp())
        self.add_point(s, 553, "Charger Temperature", self._cat("/sys/class/power_supply/charger/temp").strip())
        self.add_point(s, 554, "Thermal Governor", self._cat("/sys/class/thermal/thermal_zone0/policy").strip())
        self.add_point(s, 555, "Max Cooling State", self._detect_max_cooling())
        self.add_point(s, 556, "Thermal Mitigation", self._detect_thermal_mitigation())

    def _detect_throttle(self):
        r = self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq").strip()
        boot_max = self._cat("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq").strip()
        if r and boot_max and r.isdigit() and boot_max.isdigit():
            if int(r) < int(boot_max):
                return f"Throttling detected: max={int(r)//1000}MHz vs cpuinfo={int(boot_max)//1000}MHz"
            return "No active throttling"
        return "?"

    def _detect_bat_temp(self):
        r = self._cat("/sys/class/thermal/thermal_zone*/temp").strip()
        if r:
            return r[:60]
        return "?"

    def _detect_crit_temp(self):
        r = self._cat("/sys/class/thermal/thermal_zone0/trip_point_0_temp").strip()
        if r:
            try:
                return f"{int(r) / 1000:.0f}C"
            except:
                return r
        return "?"

    def _detect_pmic_temp(self):
        for pn in ["/sys/class/power_supply/charger/temp",
                     "/sys/class/power_supply/battery/temp"]:
            r = self._cat(pn).strip()
            if r:
                try:
                    return f"{int(r) / 10:.1f}C"
                except:
                    return r
        return "?"

    def _detect_max_cooling(self):
        r = self._cat("/sys/class/thermal/cooling_device0/max_state").strip()
        return str(int(r) + 1) if r else "?"

    def _detect_thermal_mitigation(self):
        r = self._cmd(["dumpsys", "thermalservice", "|", "grep", "-i", "mitigat"])
        return r[:80] if r else "?"

    def section_audio(self):
        s = "AUDIO"
        p = self.props
        codecs = self._dumpsys("media.audio_flinger")
        acodecs = self._dumpsys("media.player")

        self.add_point(s, 557, "Audio HAL (ro.audio.hal)", p.get("ro.audio.hal"))
        self.add_point(s, 558, "Audio Flavor (ro.audio.flavor)", p.get("ro.audio.flavor"))
        self.add_point(s, 559, "Audio Offload (ro.audio.offload)", p.get("ro.audio.offload"))
        self.add_point(s, 560, "Audio Deep Buffer (ro.audio.deep_buffer)", p.get("ro.audio.deep_buffer"))
        self.add_point(s, 561, "Audio Outputs Count", self._count_audio_outputs(codecs))
        self.add_point(s, 562, "Audio Inputs Count", self._count_audio_inputs(codecs))
        self.add_point(s, 563, "Audio Codecs (ro.audio.codecs)", p.get("ro.audio.codecs"))
        self.add_point(s, 564, "AAC Decoder", self._check_decoder(acodecs, "aac"))
        self.add_point(s, 565, "MP3 Decoder", self._check_decoder(acodecs, "mp3"))
        self.add_point(s, 566, "FLAC Decoder", self._check_decoder(acodecs, "flac"))
        self.add_point(s, 567, "ALAC Decoder", self._check_decoder(acodecs, "alac"))
        self.add_point(s, 568, "WAV Decoder", self._check_decoder(acodecs, "wav"))
        self.add_point(s, 569, "Opus Decoder", self._check_decoder(acodecs, "opus"))
        self.add_point(s, 570, "Dolby Atmos (ro.dolby.enable)", p.get("ro.dolby.enable"))
        self.add_point(s, 571, "Hi-Res Audio (ro.audio.hires)", p.get("ro.audio.hires"))
        self.add_point(s, 572, "LDAC Support (ro.bluetooth.ldac)", p.get("ro.bluetooth.ldac"))
        self.add_point(s, 573, "aptX Support (ro.bluetooth.aptx)", p.get("ro.bluetooth.aptx"))
        self.add_point(s, 574, "AAC Bluetooth Codec (ro.bluetooth.aac)", p.get("ro.bluetooth.aac"))
        self.add_point(s, 575, "SBC Bluetooth Codec (ro.bluetooth.sbc)", p.get("ro.bluetooth.sbc"))
        self.add_point(s, 576, "FM Radio (ro.fm.enabled)", p.get("ro.fm.enabled"))
        self.add_point(s, 577, "Speaker Config (ro.speaker.config)", p.get("ro.speaker.config"))
        self.add_point(s, 578, "Microphone Count (ro.mic.count)", p.get("ro.mic.count"))
        self.add_point(s, 579, "Audio Policy (ro.audio.policy)", p.get("ro.audio.policy"))
        self.add_point(s, 580, "Audio Effects (ro.audio.effects)", p.get("ro.audio.effects"))
        self.add_point(s, 581, "Audio Session Count", self._detect_audio_sessions())
        self.add_point(s, 582, "Media Codecs Count", self._detect_media_codec_count())
        self.add_point(s, 583, "Video Decoder (hw)", self._check_decoder(acodecs, "h264") or self._check_decoder(acodecs, "hevc"))
        self.add_point(s, 584, "Audio Record Active", self._detect_active_record())
        self.add_point(s, 585, "Ringtone Format (ro.ringtone)", p.get("ro.config.ringtone"))
        self.add_point(s, 586, "Notification Sound (ro.config.notification_sound)", p.get("ro.config.notification_sound"))

    def _count_audio_outputs(self, codecs):
        count = 0
        for line in codecs.splitlines():
            if "output" in line.lower() and "thread" in line.lower():
                count += 1
        return str(count) if count else "?"

    def _count_audio_inputs(self, codecs):
        count = 0
        for line in codecs.splitlines():
            if "input" in line.lower() and "thread" in line.lower():
                count += 1
        return str(count) if count else "?"

    def _check_decoder(self, acodecs, codec):
        for line in acodecs.splitlines():
            if codec.lower() in line.lower() and "decoder" in line.lower():
                return "Supported"
        return "?"

    def _detect_audio_sessions(self):
        r = self._cmd(["dumpsys", "media.audio_policy", "|", "grep", "-c", "session"])
        return r if r else "?"

    def _detect_media_codec_count(self):
        r = self._cmd(["dumpsys", "media.player", "|", "grep", "-c", "decoder"])
        return r if r else "?"

    def _detect_active_record(self):
        r = self._cmd(["dumpsys", "media.audio_flinger", "|", "grep", "-i", "record"])
        count = r.count("Record") if r else 0
        return str(count) if count > 0 else "None"

    def section_system(self):
        s = "SYSTEM"
        p = self.props
        p3 = self.sc._adb(["shell", "pm", "list", "packages", "-3"])
        psys = self.sc._adb(["shell", "pm", "list", "packages", "-s"])
        p_all = self.sc._adb(["shell", "pm", "list", "packages"])
        svcs = self.sc._adb(["shell", "service", "list"])

        third = [l.replace("package:", "").strip() for l in p3.splitlines() if l.strip()]
        syst = [l.replace("package:", "").strip() for l in psys.splitlines() if l.strip()]
        total = [l.replace("package:", "").strip() for l in p_all.splitlines() if l.strip()]
        svc_lines = [l.strip() for l in svcs.splitlines() if l.strip() and not l.startswith("Found")]

        self.add_point(s, 587, "Total Packages", str(len(total)))
        self.add_point(s, 588, "System Packages", str(len(syst)))
        self.add_point(s, 589, "Third-party Packages", str(len(third)))
        self.add_point(s, 590, "Running Services", str(len(svc_lines)))
        self.add_point(s, 591, "Java Heap (dalvik.vm.heapsize)", p.get("dalvik.vm.heapsize"))
        self.add_point(s, 592, "Java Heap Growth (dalvik.vm.heapgrowthlimit)", p.get("dalvik.vm.heapgrowthlimit"))
        self.add_point(s, 593, "Java Heap Start (dalvik.vm.heapstartsize)", p.get("dalvik.vm.heapstartsize"))
        self.add_point(s, 594, "Java Heap Min Free (dalvik.vm.heapminfree)", p.get("dalvik.vm.heapminfree"))
        self.add_point(s, 595, "Java Heap Utilization (dalvik.vm.heaptargetutilization)", p.get("dalvik.vm.heaptargetutilization"))
        self.add_point(s, 596, "System Server Heap", self._detect_system_server_heap())
        self.add_point(s, 597, "Zygote Heap (ro.zygote.disable)", p.get("ro.zygote.disable"))
        self.add_point(s, 598, "Zygote Process Count", self._detect_zygote_count())
        self.add_point(s, 599, "Native Heap Limit (ro.config.native_heap_limit)", p.get("ro.config.native_heap_limit"))
        self.add_point(s, 600, "Process Limit (ro.config.max_starting_bg)", p.get("ro.config.max_starting_bg"))
        self.add_point(s, 601, "Hidden App Limit (ro.config.hidden_app_limit)", p.get("ro.config.hidden_app_limit"))
        self.add_point(s, 602, "Alarm Manager Wakeups", self._detect_alarm_wakeups())
        self.add_point(s, 603, "USB Connect Mode (persist.sys.usb.config)", p.get("persist.sys.usb.config"))
        self.add_point(s, 604, "USB Functions (sys.usb.config)", p.get("sys.usb.config"))
        self.add_point(s, 605, "USB State (sys.usb.state)", p.get("sys.usb.state"))
        self.add_point(s, 606, "USB Controller (ro.boot.usbcontroller)", p.get("ro.boot.usbcontroller"))
        self.add_point(s, 607, "Miracast Support (ro.miracast.enabled)", p.get("ro.miracast.enabled"))
        self.add_point(s, 608, "Screen Mirroring (ro.screencast.enabled)", p.get("ro.screencast.enabled"))
        self.add_point(s, 609, "Chrome OS (ro.chromeos.enabled)", p.get("ro.chromeos.enabled"))
        self.add_point(s, 610, "ARCVM (ro.arcvm.enabled)", p.get("ro.arcvm.enabled"))
        self.add_point(s, 611, "SideSync (ro.sidesync.enabled)", p.get("ro.sidesync.enabled"))
        self.add_point(s, 612, "Dex Support (ro.samsung.dex)", p.get("ro.samsung.dex"))
        self.add_point(s, 613, "Samsung DeX Mode", self._detect_dex())
        self.add_point(s, 614, "Desktop Mode (ro.desktop.enabled)", p.get("ro.desktop.enabled"))
        self.add_point(s, 615, "Huawei Easy Projection (ro.huawei.easyprojection)", p.get("ro.huawei.easyprojection"))
        self.add_point(s, 616, "Wireless Display (ro.wlan.wfd)", p.get("ro.wlan.wfd"))
        self.add_point(s, 617, "HDMI Support (ro.hdmi.enabled)", p.get("ro.hdmi.enabled"))
        self.add_point(s, 618, "DP Alt Mode (ro.dp.altmode)", p.get("ro.dp.altmode"))
        self.add_point(s, 619, "Charging Only Mode (ro.usb.charging.only)", p.get("ro.usb.charging.only"))
        self.add_point(s, 620, "System Root Access (ro.system.root)", p.get("ro.system.root"))
        self.add_point(s, 621, "Build Date ISO (ro.build.date.iso)", p.get("ro.build.date.iso"))
        self.add_point(s, 622, "System Properties Count", str(len(p)))
        self.add_point(s, 623, "Product Properties Override (ro.product.override)", p.get("ro.product.override"))
        self.add_point(s, 624, "VNDK Lite (ro.vndk.lite)", p.get("ro.vndk.lite"))
        self.add_point(s, 625, "Treble VNDK Version (ro.vndk.version)", p.get("ro.vndk.version"))

    def _detect_system_server_heap(self):
        r = self._cmd(["ps", "|", "grep", "system_server", "|", "awk", "{print $5}"])
        return r.strip() if r else "?"

    def _detect_zygote_count(self):
        r = self._cmd(["ps", "|", "grep", "-c", "zygote"])
        return r.strip() if r else "?"

    def _detect_alarm_wakeups(self):
        r = self._cmd(["dumpsys", "alarm", "|", "grep", "-c", "Alarm"])
        return r.strip() if r else "?"

    def _detect_dex(self):
        if self._get("ro.samsung.dex") == "true":
            return "Enabled"
        d = self._dumpsys("dex")
        if "DeX" in d:
            return "Detected in dumpsys"
        return "?"

    def section_networking_advanced(self):
        s = "NETWORKING ADVANCED"
        p = self.props

        self.add_point(s, 626, "IP Forwarding (ip_forward)", self._cat("/proc/sys/net/ipv4/ip_forward").strip())
        self.add_point(s, 627, "IP Reverse Filter (rp_filter)", self._cat("/proc/sys/net/ipv4/conf/all/rp_filter").strip())
        self.add_point(s, 628, "TCP Timestamps (tcp_timestamps)", self._cat("/proc/sys/net/ipv4/tcp_timestamps").strip())
        self.add_point(s, 629, "TCP Window Scaling (tcp_window_scaling)", self._cat("/proc/sys/net/ipv4/tcp_window_scaling").strip())
        self.add_point(s, 630, "TCP Sack (tcp_sack)", self._cat("/proc/sys/net/ipv4/tcp_sack").strip())
        self.add_point(s, 631, "TCP SYN Cookies (tcp_syncookies)", self._cat("/proc/sys/net/ipv4/tcp_syncookies").strip())
        self.add_point(s, 632, "TCP Keepalive Time (tcp_keepalive_time)", self._cat("/proc/sys/net/ipv4/tcp_keepalive_time").strip())
        self.add_point(s, 633, "TCP Keepalive Probes (tcp_keepalive_probes)", self._cat("/proc/sys/net/ipv4/tcp_keepalive_probes").strip())
        self.add_point(s, 634, "TCP Keepalive Interval (tcp_keepalive_intvl)", self._cat("/proc/sys/net/ipv4/tcp_keepalive_intvl").strip())
        self.add_point(s, 635, "TCP MTU Probe (tcp_mtu_probing)", self._cat("/proc/sys/net/ipv4/tcp_mtu_probing").strip())
        self.add_point(s, 636, "TCP Congestion Control", self._cat("/proc/sys/net/ipv4/tcp_congestion_control").strip())
        self.add_point(s, 637, "TCP Available Congestion Ctrl", self._cat("/proc/sys/net/ipv4/tcp_available_congestion_control").strip())
        self.add_point(s, 638, "TCP Max Syn Backlog (tcp_max_syn_backlog)", self._cat("/proc/sys/net/ipv4/tcp_max_syn_backlog").strip())
        self.add_point(s, 639, "TCP Max Orphan (tcp_max_orphans)", self._cat("/proc/sys/net/ipv4/tcp_max_orphans").strip())
        self.add_point(s, 640, "TCP Wmem Max", self._cat("/proc/sys/net/ipv4/tcp_wmem").strip())
        self.add_point(s, 641, "TCP Rmem Max", self._cat("/proc/sys/net/ipv4/tcp_rmem").strip())
        self.add_point(s, 642, "IPv6 Accept RA (accept_ra)", self._cat("/proc/sys/net/ipv6/conf/all/accept_ra").strip())
        self.add_point(s, 643, "IPv6 Autoconf", self._cat("/proc/sys/net/ipv6/conf/all/autoconf").strip())
        self.add_point(s, 644, "IPv6 Disabled", self._cat("/proc/sys/net/ipv6/conf/all/disable_ipv6").strip())
        self.add_point(s, 645, "IPv6 Address", self._extract_ipv6())
        self.add_point(s, 646, "Routing Table", self._extract_routing_table())
        self.add_point(s, 647, "ARP Table Entries", self._extract_arp())
        self.add_point(s, 648, "WiFi Roaming Threshold (ro.wifi.roam)", p.get("ro.wifi.roam"))
        self.add_point(s, 649, "WiFi Band (ro.wifi.band)", p.get("ro.wifi.band"))
        self.add_point(s, 650, "WiFi Country Code (ro.wifi.country)", p.get("ro.wifi.country"))
        self.add_point(s, 651, "NTP Server (ro.ntp.server)", p.get("ro.ntp.server"))
        self.add_point(s, 652, "Cellular Interface (rmnet)", self._detect_rmnet())
        self.add_point(s, 653, "TUN/TAP Support", self._detect_tuntap())
        self.add_point(s, 654, "Netfilter Support", self._detect_netfilter())
        self.add_point(s, 655, "WiFi Power Save (ro.wifi.powersave)", p.get("ro.wifi.powersave"))

    def _extract_ipv6(self):
        r = self._cmd(["ip", "-6", "addr", "show", "wlan0"])
        m = re.search(r'inet6\s+([0-9a-f:]+)', r)
        return m.group(1) if m else "?"

    def _extract_routing_table(self):
        r = self._cmd(["ip", "route"])
        lines = r.splitlines()
        return f"{len(lines)} routes" if lines else "?"

    def _extract_arp(self):
        r = self._cmd(["ip", "neigh"])
        lines = [l for l in r.splitlines() if l.strip()]
        return str(len(lines)) if lines else "?"

    def _detect_rmnet(self):
        r = self._cmd(["ip", "link"])
        if "rmnet" in r:
            m = re.findall(r'rmnet\d+', r)
            return ", ".join(m) if m else "rmnet present"
        return "?"

    def _detect_tuntap(self):
        r = self._cat("/dev/net/tun")
        return "Available" if r else "?"
    
    def _detect_netfilter(self):
        r = self._cat("/proc/net/netfilter")
        return "Available" if r else "?"

    def section_extras(self):
        s = "EXTRAS"
        p = self.props

        self.add_point(s, 656, "Build Flavors", p.get("ro.build.flavor"))
        self.add_point(s, 657, "Runtime (persist.sys.dalvik.vm.lib.2)", p.get("persist.sys.dalvik.vm.lib.2"))
        self.add_point(s, 658, "Native Bridge (ro.dalvik.vm.native.bridge)", p.get("ro.dalvik.vm.native.bridge"))
        self.add_point(s, 659, "OEM Unlock (ro.oem.unlock)", p.get("ro.oem.unlock"))
        self.add_point(s, 660, "Storaged (ro.storaged.enabled)", p.get("ro.storaged.enabled"))
        self.add_point(s, 661, "Iorap (ro.iorapd.enable)", p.get("ro.iorapd.enable"))
        self.add_point(s, 662, "Perf Hub (ro.perfhub.enabled)", p.get("ro.perfhub.enabled"))
        self.add_point(s, 663, "Smart Pixels (ro.smartpixels.enabled)", p.get("ro.smartpixels.enabled"))
        self.add_point(s, 664, "F2FS Compression (ro.f2fs.compression)", p.get("ro.f2fs.compression"))
        self.add_point(s, 665, "LZ4 Compression (ro.lz4.enabled)", p.get("ro.lz4.enabled"))
        self.add_point(s, 666, "EAS Support (ro.eas.enabled)", p.get("ro.eas.enabled"))
        self.add_point(s, 667, "Schedutil Governor (ro.schedutil.enabled)", p.get("ro.schedutil.enabled"))
        self.add_point(s, 668, "Cpusets (ro.cpuset.enabled)", p.get("ro.cpuset.enabled"))
        self.add_point(s, 669, "GPU Renderer String", p.get("debug.egl.hw"))
        self.add_point(s, 670, "OpenGL ES Extensions", self._detect_gles_ext())
        self.add_point(s, 671, "Vulkan Extensions", self._detect_vk_ext())
        self.add_point(s, 672, "Vulkan API Version", self._detect_vulkan())
        self.add_point(s, 673, "Widevine Level (ro.widevine.level)", p.get("ro.widevine.level"))
        self.add_point(s, 674, "DRM Support (ro.drm.enabled)", p.get("ro.drm.enabled"))
        self.add_point(s, 675, "HDCP Support (ro.hdcp.enabled)", p.get("ro.hdcp.enabled"))
        self.add_point(s, 676, "HDR10+ Support (ro.hdr10plus.enabled)", p.get("ro.hdr10plus.enabled"))
        self.add_point(s, 677, "Dolby Vision (ro.dolby.vision)", p.get("ro.dolby.vision"))
        self.add_point(s, 678, "HLG Support (ro.hlg.enabled)", p.get("ro.hlg.enabled"))
        self.add_point(s, 679, "Input Devices Count", self._detect_input_count())
        self.add_point(s, 680, "USB Gadget (ro.usb.gadget)", p.get("ro.usb.gadget"))
        self.add_point(s, 681, "ADB over Network (service.adb.tcp.port)", p.get("service.adb.tcp.port"))
        self.add_point(s, 682, "WiFi ADB (ro.adb.wifi)", p.get("ro.adb.wifi"))
        self.add_point(s, 683, "Logcat Buffer Size (ro.logd.buffer)", p.get("ro.logd.buffer"))
        self.add_point(s, 684, "Crash Log (ro.crashlog.enabled)", p.get("ro.crashlog.enabled"))
        self.add_point(s, 685, "Boot Count", self._detect_boot_count())
        self.add_point(s, 686, "OTA Update (ro.ota.update)", p.get("ro.ota.update"))
        self.add_point(s, 687, "Recovery Mode", self._detect_recovery())
        self.add_point(s, 688, "Fastboot Mode", self._detect_fastboot())
        self.add_point(s, 689, "Download Mode", self._detect_download_mode())
        self.add_point(s, 690, "System Health Status", self._detect_health())

    def _detect_gles_ext(self):
        r = self._cmd(["dumpsys", "display", "|", "grep", "-i", "extension"])
        return r[:80] if r else "?"

    def _detect_vk_ext(self):
        r = self._cmd(["dumpsys", "media.resource_manager", "|", "grep", "-i", "vulkan"])
        if r:
            return r[:100].strip()
        r = self._cmd(["dumpsys", "package", "|", "grep", "-i", "vulkan"])
        if r:
            return r[:100].strip()
        lib = self._cmd(["ls", "/vendor/lib64/libvulkan.so"])
        return "libvulkan present" if lib and "No such" not in lib else "?"

    def _detect_input_count(self):
        r = self._cmd(["getevent", "-p", "|", "grep", "-c", "add device"])
        return r.strip() if r else "?"

    def _detect_boot_count(self):
        for k in ["persist.sys.boot.count", "sys.boot.reason", "ro.boot.bootcount"]:
            v = self._get(k)
            if v != "?":
                return v
        return "?"

    def _detect_recovery(self):
        r = self._cmd(["getprop", "ro.boot.mode"])
        if "recovery" in r.lower():
            return "In recovery mode"
        return "Normal mode"

    def _detect_fastboot(self):
        r = self._cmd(["getprop", "ro.boot.fastboot"])
        if r == "1":
            return "In fastboot mode"
        return "Normal mode"

    def _detect_download_mode(self):
        r = self._cmd(["getprop", "ro.boot.downloadmode"])
        if r == "1" or r == "true":
            return "Enabled"
        return "?"

    def _detect_health(self):
        h = self._dumpsys("battery")
        if "health: 2" in h:
            return "Good (battery health 2)"
        return "?"

    def generate_report(self, display=True, save_path=None):
        start = datetime.datetime.now()

        self.points = []
        self.section_device_identity()
        self.section_os()
        self.section_build()
        self.section_hardware()
        self.section_storage()
        self.section_gpu()
        self.section_network()
        self.section_telephony()
        self.section_display()
        self.section_battery()
        self.section_sensors()
        self.section_camera()
        self.section_security()
        self.section_performance()
        self.section_thermal()
        self.section_audio()
        self.section_system()
        self.section_networking_advanced()
        self.section_extras()

        duration = (datetime.datetime.now() - start).total_seconds()
        actual_count = len(self.points)

        if display:
            self._display_report(actual_count, duration)

        if save_path:
            self._save_report(save_path, actual_count, duration)

        return self.points

    def _display_report(self, total, duration):
        console.print()
        console.print(Rule(style="cyan"))
        console.print(f"[bold cyan]     ANDROID TOTAL AUDIT REPORT[/bold cyan]")
        console.print(f"[bold cyan]  HARDWARE & SOFTWARE DETAILED INVENTORY[/bold cyan]")
        console.print(Rule(style="cyan"))
        console.print(f"[cyan]Audit Date:[/cyan] {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        console.print(f"[cyan]Device Model:[/cyan] {self._get('ro.product.model')}")
        console.print(f"[cyan]Audit Tool:[/cyan] ADB + Native C + C++ Analyzer")
        console.print(f"[cyan]Total Audit Points:[/cyan] {total}")
        if self.soc:
            console.print(f"[cyan]SoC Detected:[/cyan] {self.soc.get('full_name', '?')}")
        console.print(Rule(style="cyan"))
        console.print()

        current_section = ""
        for pt in self.points:
            if pt["section"] != current_section:
                current_section = pt["section"]
                sc = SECTION_COLORS.get(current_section, "white")
                console.print()
                console.print(f"[bold {sc}]{'=' * 66}[/bold {sc}]")
                console.print(f"[bold {sc}]  {current_section}[/bold {sc}]")
                console.print(f"[bold {sc}]{'=' * 66}[/bold {sc}]")
                console.print()

            color = pt["color"]
            val = pt["value"] if pt["value"] else "?"
            console.print(f"  [bold green][+][/bold green] [bold white]{pt['desc']}:[/bold white] [{color}]{val}[/{color}]")

        console.print()
        console.print(Rule(style="green"))
        console.print(f"[bold green] Audit Complete:[/bold green] {total} points in {duration:.1f}s")
        console.print(f"[bold green] Device:[/bold green] {self._get('ro.product.manufacturer')} {self._get('ro.product.model')}")
        console.print(f"[bold green] SoC:[/bold green] {self.soc.get('full_name', '?') if self.soc else '?'}")
        console.print(Rule(style="green"))
        console.print()

    def _save_report(self, path, total, duration):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        lines = []
        lines.append("=" * 70)
        lines.append("                    ANDROID TOTAL AUDIT REPORT")
        lines.append("              HARDWARE & SOFTWARE DETAILED INVENTORY")
        lines.append("=" * 70)
        lines.append(f"Audit Date: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append(f"Device Model: {self._get('ro.product.model')}")
        lines.append(f"Audit Tool: ADB + Native C + C++ Analyzer")
        lines.append(f"Total Audit Points: {total}")
        if self.soc:
            lines.append(f"SoC Detected: {self.soc.get('full_name', '?')}")
        lines.append("=" * 70)
        lines.append("")

        current_section = ""
        for pt in self.points:
            if pt["section"] != current_section:
                current_section = pt["section"]
                lines.append("")
                lines.append("=" * 66)
                lines.append(f"  {current_section}")
                lines.append("=" * 66)
                lines.append("")
            lines.append(f"  [+] {pt['desc']}: {pt['value'] if pt['value'] else '?'}")

        lines.append("")
        lines.append("=" * 70)
        lines.append(f"Audit Complete: {total} points in {duration:.1f}s")
        lines.append(f"Device: {self._get('ro.product.manufacturer')} {self._get('ro.product.model')}")
        lines.append(f"SoC: {self.soc.get('full_name', '?') if self.soc else '?'}")
        lines.append("=" * 70)

        with open(path, "w") as f:
            f.write("\n".join(lines))

        console.print(f"[bold green] Report saved:[/bold green] {path}")


def run_audit_690(scanner, display=True, save_dir="reports"):
    auditor = AndroidAudit690(scanner)
    os.makedirs(save_dir, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    path = f"{save_dir}/android_audit_690_{ts}.txt"
    return auditor.generate_report(display=display, save_path=path)
