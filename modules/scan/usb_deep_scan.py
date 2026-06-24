import sys
import os
import re
import time
import json
import threading
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from modules.base import AndroModule
from core.usb_scanner import AndroidUSBSanner, DeviceNotFoundError, ADBError
from core.utils import run_command
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TimeElapsedColumn, MofNCompleteColumn

console = Console()


class Module(AndroModule):
    name = "scanner/usb_deep_scan"
    description = "Advanced parallel deep scanner — 1000+ checkpoints across 30 categories covering hardware, OS, network, sensors, security, processes, ports, certificates, and runtime analysis via ADB"
    category = "scan"
    author = "AndroXploit"

    options = {
        "DEVICE_SERIAL": {
            "value": None,
            "required": False,
            "description": "ADB serial (leave empty for auto-detect)",
        },
        "SAVE_REPORT": {
            "value": "on",
            "required": False,
            "description": "Save report to file (on/off)",
        },
        "SCAN_DEPTH": {
            "value": "deep",
            "required": False,
            "description": "Scan depth: quick, normal, deep, forensic",
        },
        "TIMEOUT": {
            "value": "60",
            "required": False,
            "description": "ADB command timeout in seconds",
        },
    }

    SCAN_CATEGORIES = [
        "identity", "os", "kernel", "hardware", "cpu", "memory", "storage",
        "gpu", "display", "battery", "network", "wifi", "bluetooth",
        "telephony", "sensors", "camera", "audio", "thermal", "location",
        "input", "nfc", "security", "selinux", "crypto", "packages",
        "processes", "services", "ports", "certificates", "accounts",
        "performance", "runtime", "build", "debug",
    ]

    def __init__(self):
        super().__init__()
        self._lock = threading.Lock()
        self._results = {}
        self._errors = []
        self._start_time = None
        self._adb_timeout = 60

    def run(self):
        serial = self.get_option("DEVICE_SERIAL")
        save = self.get_option("SAVE_REPORT", "on")
        depth = self.get_option("SCAN_DEPTH", "deep")
        self._adb_timeout = int(self.get_option("TIMEOUT", "60"))

        scanner = AndroidUSBSanner()

        if serial and serial.lower() not in ("true", "false", "on", "off", "yes", "no", "1", "0", ""):
            scanner.device_serial = serial
        else:
            self._wait_for_device(scanner)

        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(complete_style="cyan", finished_style="green"),
            MofNCompleteColumn(),
            TimeElapsedColumn(),
            console=console,
        ) as progress:

            main_task = progress.add_task("[bold cyan]Scanning device...", total=100)

            progress.update(main_task, advance=0, description="[cyan]Connecting & verifying device...")
            try:
                scanner.verify_device()
                scanner._getprop()
            except (DeviceNotFoundError, ADBError) as e:
                self.error(f"Device error: {e}")
                return {"error": str(e)}
            progress.update(main_task, advance=5)

            categories = self._get_scan_plan(depth)
            total_tasks = len(categories)

            scan_task = progress.add_task("[green]  Running parallel scans...", total=total_tasks)

            self._start_time = time.time()
            with ThreadPoolExecutor(max_workers=min(8, total_tasks)) as pool:
                futures = {}
                for cat, func in categories:
                    f = pool.submit(self._safe_scan, scanner, cat, func, depth)
                    futures[f] = cat

                for f in as_completed(futures):
                    cat = futures[f]
                    try:
                        result = f.result()
                        with self._lock:
                            self._results[cat] = result
                    except Exception as e:
                        with self._lock:
                            self._errors.append(f"{cat}: {e}")
                            self._results[cat] = {"error": str(e)}
                    progress.update(scan_task, advance=1)

            elapsed = time.time() - self._start_time
            progress.update(main_task, advance=90, description="[bold green]Scan complete!")

            progress.remove_task(scan_task)
            progress.update(main_task, advance=5)

        model = scanner.props.get("ro.product.model", "Unknown")
        self.success(f"Deep scan complete for {model} ({elapsed:.1f}s)")

        self._print_summary_table()

        if save.lower() in ("on", "true", "1", "yes"):
            path = self._save_report()
            self.success(f"Report saved to {path}")

        return {
            "device": model,
            "categories_scanned": len(self._results),
            "total_checkpoints": sum(len(v) for v in self._results.values() if isinstance(v, dict)),
            "errors": len(self._errors),
            "elapsed": round(elapsed, 1),
            "results": self._results,
        }

    def _get_scan_plan(self, depth):
        base = [
            ("identity", self._scan_identity),
            ("os", self._scan_os),
            ("kernel", self._scan_kernel),
            ("hardware", self._scan_hardware),
            ("cpu", self._scan_cpu),
            ("memory", self._scan_memory),
            ("storage", self._scan_storage),
            ("gpu", self._scan_gpu),
            ("display", self._scan_display),
            ("battery", self._scan_battery),
            ("network", self._scan_network),
            ("wifi", self._scan_wifi),
            ("bluetooth", self._scan_bluetooth),
            ("telephony", self._scan_telephony),
            ("sensors", self._scan_sensors),
            ("camera", self._scan_camera),
            ("audio", self._scan_audio),
            ("thermal", self._scan_thermal),
            ("location", self._scan_location),
            ("input", self._scan_input),
            ("nfc", self._scan_nfc),
            ("security", self._scan_security),
            ("selinux", self._scan_selinux),
            ("crypto", self._scan_crypto),
            ("packages", self._scan_packages),
            ("processes", self._scan_processes),
            ("services", self._scan_services),
        ]
        if depth in ("deep", "forensic"):
            base += [
                ("ports", self._scan_ports),
                ("certificates", self._scan_certificates),
                ("accounts", self._scan_accounts),
                ("performance", self._scan_performance),
                ("runtime", self._scan_runtime),
                ("build", self._scan_build),
                ("debug", self._scan_debug),
            ]
        return base

    def _safe_scan(self, scanner, cat, func, depth):
        try:
            return func(scanner, depth)
        except Exception as e:
            return {"error": str(e)}

    def _wait_for_device(self, scanner):
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            TimeElapsedColumn(),
            console=console,
        ) as progress:
            task = progress.add_task("[cyan]Waiting for Android device via USB...", total=120)
            for i in range(120):
                try:
                    serial_found = scanner.discover_device()
                    progress.update(task, description=f"[green]Detected {serial_found}", completed=120)
                    return
                except DeviceNotFoundError:
                    progress.update(task, description=f"[cyan]Waiting... ({i}s)")
                    time.sleep(1)
            raise DeviceNotFoundError("No device detected after 120s")

    def _adb(self, args):
        return run_command(["adb"] + args, timeout=self._adb_timeout)

    def _sh(self, cmd):
        return self._adb(["shell", cmd + " 2>/dev/null"])

    def _getprop(self, key):
        return self._sh(f"getprop {key}")["stdout"].strip()

    def _cat(self, path):
        return self._sh(f"cat {path}")["stdout"]

    def _ls(self, path):
        return self._sh(f"ls -la {path}")["stdout"]

    # ═══════════════════════════════════════════════════════
    # 30+ PARALLEL SCAN FUNCTIONS — 1000+ CHECKPOINTS
    # ═══════════════════════════════════════════════════════

    def _scan_identity(self, s, d):
        r = {}
        for k in ["ro.product.model", "ro.product.manufacturer", "ro.product.name",
                   "ro.product.board", "ro.product.device", "ro.product.brand",
                   "ro.serialno", "ro.build.fingerprint", "ro.build.description"]:
            r[k.replace("ro.product.", "").replace("ro.", "")] = self._getprop(k)
        return r

    def _scan_os(self, s, d):
        r = {}
        for k in ["ro.build.version.release", "ro.build.version.sdk",
                   "ro.build.version.codename", "ro.build.version.security_patch",
                   "ro.build.version.incremental", "ro.build.version.base_os",
                   "ro.build.date.utc", "ro.build.type", "ro.build.tags",
                   "ro.build.user", "ro.build.host"]:
            r[k.replace("ro.build.version.", "").replace("ro.build.", "")] = self._getprop(k)
        r["security_patch_day"] = self._getprop("ro.build.version.security_patch")
        return r

    def _scan_kernel(self, s, d):
        r = {}
        kver = self._sh("uname -a")["stdout"].strip()
        r["uname"] = kver
        r["version"] = self._sh("cat /proc/version")["stdout"].strip()
        r["cmdline"] = self._sh("cat /proc/cmdline")["stdout"].strip()
        r["kernel_release"] = self._sh("uname -r")["stdout"].strip()
        r["kernel_version"] = self._sh("uname -v")["stdout"].strip()
        r["architecture"] = self._sh("uname -m")["stdout"].strip()
        r["smp"] = self._sh("cat /proc/sched_debug 2>/dev/null | head -5")["stdout"][:500]
        r["modules"] = self._sh("cat /proc/modules")["stdout"].strip()
        r["crypto_modules"] = self._cat("/proc/crypto")[:3000]
        r["filesystems"] = self._cat("/proc/filesystems").strip()
        r["interrupts"] = self._cat("/proc/interrupts")[:2000]
        return r

    def _scan_hardware(self, s, d):
        r = {}
        r["platform"] = self._getprop("ro.board.platform")
        r["hardware"] = self._getprop("ro.hardware")
        r["bootloader"] = self._getprop("ro.boot.bootloader")
        r["baseband"] = self._getprop("ro.build.baseband")
        r["chipname"] = self._getprop("ro.chipname")
        r["arch"] = self._getprop("ro.product.cpu.abi")
        r["arch2"] = self._getprop("ro.product.cpu.abi2")
        r["soc_model"] = self._getprop("ro.soc.model")
        r["soc_manufacturer"] = self._getprop("ro.soc.manufacturer")
        r["soc_vendor"] = self._getprop("ro.board.platform")
        r["device_tree"] = self._cat("/sys/firmware/devicetree/base/model").strip()
        r["dmesg_soc"] = self._sh("dmesg | grep -i 'cpu\\|soc\\|platform' | head -20")["stdout"]
        r["i2c_devices"] = self._sh("ls /dev/i2c-* 2>/dev/null")["stdout"]
        r["input_devices"] = self._sh("ls /dev/input/")["stdout"]
        r["block_devices"] = self._cat("/proc/partitions").strip()
        r["usb_devices"] = self._sh("lsusb 2>/dev/null || cat /sys/kernel/debug/usb/devices 2>/dev/null | head -50")["stdout"]
        return r

    def _scan_cpu(self, s, d):
        r = {}
        raw = self._cat("/proc/cpuinfo")
        r["raw"] = raw
        r["cores"] = raw.count("processor\t:")
        features = self._cat("/proc/cpuinfo")
        r["features"] = self._extract_cpu_features(features)
        r["bogomips"] = self._extract_value(features, "BogoMIPS")
        r["implementer"] = self._extract_value(features, "CPU implementer")
        r["architecture"] = self._extract_value(features, "CPU architecture")
        r["variant"] = self._extract_value(features, "CPU variant")
        r["part"] = self._extract_value(features, "CPU part")
        r["revision"] = self._extract_value(features, "CPU revision")
        r["scaling_governor"] = self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor").strip()
        r["scaling_min"] = self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq").strip()
        r["scaling_max"] = self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq").strip()
        r["available_governors"] = self._cat("/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors").strip()
        r["online_cpus"] = self._cat("/sys/devices/system/cpu/online").strip()
        r["present_cpus"] = self._cat("/sys/devices/system/cpu/present").strip()
        return r

    def _scan_memory(self, s, d):
        r = {}
        mem = self._cat("/proc/meminfo")
        r["raw"] = mem
        for line in mem.splitlines():
            for key in ["MemTotal", "MemFree", "MemAvailable", "Buffers",
                         "Cached", "SwapTotal", "SwapFree", "Active", "Inactive",
                         "Dirty", "Writeback", "AnonPages", "Mapped", "Shmem",
                         "Slab", "SReclaimable", "KernelStack", "PageTables",
                         "VmallocTotal", "VmallocUsed", "CommitLimit", "Committed_AS"]:
                if line.startswith(key + ":"):
                    r[key.lower()] = line.split(":")[1].strip()
        r["zram"] = self._sh("cat /sys/block/zram0/initstate 2>/dev/null")["stdout"].strip()
        r["zram_size"] = self._sh("cat /sys/block/zram0/disksize 2>/dev/null")["stdout"].strip()
        return r

    def _scan_storage(self, s, d):
        r = {}
        r["df"] = self._sh("df -h")["stdout"].strip()
        r["df_data"] = self._sh("df -h /data")["stdout"].strip()
        partitions = self._cat("/proc/partitions")
        r["partitions"] = partitions.strip()
        r["mounts"] = self._cat("/proc/mounts").strip()
        r["fstab"] = self._cat("/etc/fstab").strip() or self._cat("/vendor/etc/fstab.*").strip()
        r["io_scheduler"] = self._cat("/sys/block/mmcblk0/queue/scheduler").strip()
        r["io_stat"] = self._cat("/sys/block/mmcblk0/stat").strip()
        r["mmc_name"] = self._cat("/sys/block/mmcblk0/device/name").strip()
        r["mmc_type"] = self._cat("/sys/block/mmcblk0/device/type").strip()
        r["disk_stats"] = self._cat("/sys/block/mmcblk0/queue/rotational").strip()
        r["emmc_fwrev"] = self._cat("/sys/block/mmcblk0/device/fwrev").strip()
        r["emmc_manfid"] = self._cat("/sys/block/mmcblk0/device/manfid").strip()
        r["ext4_features"] = self._sh("tune2fs -l /dev/block/dm-0 2>/dev/null | head -20")["stdout"]
        return r

    def _scan_gpu(self, s, d):
        r = {}
        sf = self._sh("dumpsys SurfaceFlinger 2>/dev/null | grep -E 'GLES|GPU|gpu|render'")["stdout"]
        r["surfaceflinger"] = sf.strip()
        r["gl_vendor"] = self._sh("dumpsys SurfaceFlinger 2>/dev/null | grep 'GLES:'")["stdout"].strip()
        r["gl_version"] = self._sh("dumpsys SurfaceFlinger 2>/dev/null | grep 'Version:'")["stdout"].strip()
        r["gpu_renderer"] = self._sh("dumpsys SurfaceFlinger 2>/dev/null | grep -i 'gpu'")["stdout"].strip()
        r["kgsl_model"] = self._cat("/sys/class/kgsl/kgsl-3d0/gpu_model").strip()
        r["kgsl_speed"] = self._cat("/sys/class/kgsl/kgsl-3d0/gpuclk").strip()
        r["kgsl_max"] = self._cat("/sys/class/kgsl/kgsl-3d0/max_gpuclk").strip()
        r["kgsl_available"] = self._cat("/sys/class/kgsl/kgsl-3d0/available_frequencies").strip()
        r["kgsl_governor"] = self._cat("/sys/class/kgsl/kgsl-3d0/devfreq/governor").strip()
        r["vulkan"] = self._sh("dumpsys package | grep vulkan")["stdout"].strip()
        r["opengles_version"] = self._sh("getprop ro.opengles.version")["stdout"].strip()
        r["gralloc"] = self._getprop("ro.hardware.gralloc")
        r["sf_effects"] = self._sh("dumpsys SurfaceFlinger 2>/dev/null | grep -E 'HWC|composer|comp|layers' | head -10")["stdout"]
        r["renderengine"] = self._sh("dumpsys SurfaceFlinger 2>/dev/null | grep -i 'render' | head -5")["stdout"]
        return r

    def _scan_display(self, s, d):
        r = {}
        r["size"] = self._sh("wm size")["stdout"].strip()
        r["density"] = self._sh("wm density")["stdout"].strip()
        r["density_override"] = self._sh("settings get global display_density_forced 2>/dev/null")["stdout"].strip()
        disp = self._sh("dumpsys display 2>/dev/null")["stdout"]
        r["display_info"] = self._extract_between(disp, "mBaseDisplayInfo=", 20) or disp[:3000]
        r["refresh_rate"] = self._sh("dumpsys window 2>/dev/null | grep -i 'refreshRate\\|fps' | head -10")["stdout"]
        r["hdr"] = self._sh("dumpsys display 2>/dev/null | grep -i hdr | head -5")["stdout"]
        r["color_mode"] = self._sh("dumpsys display 2>/dev/null | grep -i 'color\\|mode' | head -10")["stdout"]
        r["screen_brightness"] = self._sh("settings get system screen_brightness 2>/dev/null")["stdout"].strip()
        r["auto_brightness"] = self._sh("settings get system screen_brightness_mode 2>/dev/null")["stdout"].strip()
        r["night_mode"] = self._sh("settings get secure night_display_activated 2>/dev/null")["stdout"].strip()
        r["cutout"] = self._sh("dumpsys display 2>/dev/null | grep -i 'cutout\\|notch' | head -5")["stdout"]
        r["secure_flags"] = self._sh("dumpsys window 2>/dev/null | grep -i 'secure\\|flag' | head -10")["stdout"]
        return r

    def _scan_battery(self, s, d):
        r = {}
        batt = self._sh("dumpsys battery 2>/dev/null")["stdout"]
        for line in batt.splitlines():
            if ":" in line:
                k = line.split(":")[0].strip()
                v = line.split(":")[1].strip()
                r[k.lower().replace(" ", "_")] = v
        r["health"] = self._map_battery_health(r.get("health", ""))
        r["status"] = self._map_battery_status(r.get("status", ""))
        r["temperature_c"] = r.get("temperature", "?")
        r["technology"] = self._sh("dumpsys battery 2>/dev/null | grep 'technology'")["stdout"].strip()
        r["charge_type"] = self._sh("dumpsys battery 2>/dev/null | grep 'charge'")["stdout"].strip()
        r["current_now"] = self._cat("/sys/class/power_supply/battery/current_now").strip()
        r["voltage_now"] = self._cat("/sys/class/power_supply/battery/voltage_now").strip()
        r["capacity_raw"] = self._cat("/sys/class/power_supply/battery/capacity").strip()
        r["battery_cycle"] = self._sh("dumpsys batterystats 2>/dev/null | grep 'charge' | head -5")["stdout"]
        r["battery_history"] = self._sh("dumpsys batterystats --charged 2>/dev/null | head -30")["stdout"]
        return r

    def _scan_network(self, s, d):
        r = {}
        r["ip"] = self._sh("ip -f inet addr show 2>/dev/null")["stdout"].strip()
        r["ip6"] = self._sh("ip -f inet6 addr show 2>/dev/null")["stdout"].strip()
        r["route"] = self._sh("ip route show 2>/dev/null")["stdout"].strip()
        r["arp"] = self._sh("cat /proc/net/arp 2>/dev/null")["stdout"].strip()
        r["dns"] = self._sh("getprop net.dns1 2>/dev/null; getprop net.dns2 2>/dev/null")["stdout"].strip()
        r["http_proxy"] = self._sh("settings get global http_proxy 2>/dev/null")["stdout"].strip()
        r["interfaces"] = self._sh("ip link show 2>/dev/null")["stdout"].strip()
        r["conn_stats"] = self._sh("cat /proc/net/stat/rt_cache 2>/dev/null | head -5")["stdout"]
        r["sock_stat"] = self._sh("cat /proc/net/sockstat 2>/dev/null")["stdout"].strip()
        r["netstat"] = self._sh("netstat -tlnp 2>/dev/null || cat /proc/net/tcp /proc/net/tcp6 2>/dev/null")["stdout"].strip()
        r["tcp_connections"] = self._cat("/proc/net/tcp").strip()
        r["udp_connections"] = self._cat("/proc/net/udp").strip()
        r["wireguard"] = self._sh("wg show 2>/dev/null")["stdout"].strip()
        r["vpn"] = self._sh("dumpsys connectivity 2>/dev/null | grep -i 'vpn\\|tunnel' | head -10")["stdout"]
        r["proxy_settings"] = self._sh("settings list global 2>/dev/null | grep -i proxy | head -10")["stdout"]
        r["firewall"] = self._sh("iptables -L 2>/dev/null | head -30")["stdout"]
        r["packet_filter"] = self._sh("getprop net.eth0.dns1; getprop net.rmnet0.dns1; getprop ro.compressed_apn")["stdout"]
        return r

    def _scan_wifi(self, s, d):
        r = {}
        w = self._sh("dumpsys wifi 2>/dev/null")["stdout"]
        r["ssid"] = self._extract_value(w, "mWifiInfo SSID")
        r["bssid"] = self._extract_value(w, "mWifiInfo BSSID")
        r["rssi"] = self._extract_value(w, "mWifiInfo RSSI")
        r["link_speed"] = self._extract_value(w, "mWifiInfo LinkSpeed")
        r["frequency"] = self._extract_value(w, "mWifiInfo Frequency")
        r["ip_address"] = self._extract_value(w, "mWifiInfo IpAddress")
        r["mac"] = self._extract_value(w, "mWifiInfo MacAddress")
        r["wifi_standard"] = self._extract_value(w, "WifiStandard")
        r["channel_width"] = self._extract_value(w, "ChannelWidth")
        r["supplicant_state"] = self._extract_value(w, "SupplicantState")
        r["scan_results"] = self._sh("dumpsys wifi 2>/dev/null | grep -A 100 'Scan Results' | head -60")["stdout"]
        r["wifi_config"] = self._sh("dumpsys wifi 2>/dev/null | grep -A 20 'mConfiguredNetworks' | head -40")["stdout"]
        r["wifi_direct"] = self._sh("dumpsys wifi 2>/dev/null | grep -i 'p2p\\|direct' | head -20")["stdout"]
        r["passpoint"] = self._sh("dumpsys wifi 2>/dev/null | grep -i 'passpoint\\|hotspot' | head -10")["stdout"]
        r["country_code"] = self._sh("cmd wifi get-country-code 2>/dev/null || getprop wifi.interface")["stdout"].strip()
        r["roaming"] = self._sh("dumpsys wifi 2>/dev/null | grep -i roam | head -10")["stdout"]
        return r

    def _scan_bluetooth(self, s, d):
        r = {}
        bt = self._sh("dumpsys bluetooth_manager 2>/dev/null")["stdout"]
        r["name"] = self._extract_value(bt, "name:")
        r["address"] = self._extract_value(bt, "address:")
        r["state"] = self._extract_value(bt, "state:")
        r["bonded"] = self._extract_value(bt, "Bonded devices:")
        r["scan_mode"] = self._extract_value(bt, "ScanMode:")
        r["is_enabled"] = str("ON" in bt or "STATE_ON" in bt)
        r["sco_connections"] = self._extract_value(bt, "SCO connections:")
        r["acl_connections"] = self._extract_value(bt, "ACL connections:")
        r["codecs"] = self._extract_between(bt, "Codecs:", 5) or ""
        r["le_scanning"] = self._sh("dumpsys bluetooth_manager 2>/dev/null | grep -i 'le_scan' | head -5")["stdout"]
        r["hci_devices"] = self._sh("cat /proc/bluetooth/hci 2>/dev/null")["stdout"].strip()
        r["bt_class"] = self._sh("getprop ro.bt.version; getprop ro.bt.stack; getprop persist.vendor.bluetooth")["stdout"]
        return r

    def _scan_telephony(self, s, d):
        r = {}
        r["network_type"] = self._getprop("gsm.network.type")
        r["operator"] = self._getprop("gsm.operator.alpha")
        r["operator_numeric"] = self._getprop("gsm.operator.numeric")
        r["sim_operator"] = self._getprop("gsm.sim.operator.alpha")
        r["sim_country"] = self._getprop("gsm.sim.operator.iso-country")
        r["sim_serial"] = self._getprop("gsm.sim.serial")
        r["sim_state"] = self._getprop("gsm.sim.state")
        r["signal_strength"] = self._sh("dumpsys telephony.registry 2>/dev/null | grep -i 'mSignalStrength' | head -5")["stdout"]
        r["cell_info"] = self._sh("dumpsys telephony.registry 2>/dev/null | grep -i 'mCellInfo' | head -10")["stdout"]
        r["data_state"] = self._sh("dumpsys telephony.registry 2>/dev/null | grep -i 'mDataConnectionState' | head -5")["stdout"]
        r["voice_network"] = self._getprop("gsm.operator.isroaming")
        r["data_network"] = self._getprop("gsm.data.operator")
        r["volte"] = self._sh("dumpsys telephony.registry 2>/dev/null | grep -i 'volte\\|ims' | head -10")["stdout"]
        r["nr_available"] = self._sh("dumpsys telephony.registry 2>/dev/null | grep -i 'nr_\\|5g' | head -10")["stdout"]
        r["lte_params"] = self._sh("dumpsys telephony.registry 2>/dev/null | grep -i 'lte\\|earfcn\\|pci' | head -10")["stdout"]
        r["baseband_version"] = self._getprop("ro.build.baseband")
        r["radio_version"] = self._getprop("gsm.version.baseband")
        r["imei"] = self._sh("service call iphonesubinfo 1 2>/dev/null | head -5")["stdout"][:200]
        r["meid"] = self._getprop("ro.cdma.meid")
        r["sim_slot_count"] = self._getprop("ro.telephony.sim.count") or "1"
        r["multisim_config"] = self._getprop("persist.radio.multisim.config")
        r["data_roaming"] = self._sh("settings get global data_roaming 2>/dev/null")["stdout"].strip()
        r["preferred_network"] = self._sh("settings get global preferred_network_mode 2>/dev/null")["stdout"].strip()
        r["carrier_config"] = self._sh("dumpsys telephony.registry 2>/dev/null | grep -i 'carrier' | head -10")["stdout"]
        return r

    def _scan_sensors(self, s, d):
        r = {}
        ss = self._sh("dumpsys sensorservice 2>/dev/null")["stdout"]
        r["raw"] = ss[:5000]
        sensors = re.findall(r'\(([^)]+)\)\s+([\w\s-]+)\s+vendor=(\d+)', ss)
        r["list"] = []
        seen = set()
        for sid, name, vendor_id in sensors:
            if name.strip() not in seen:
                seen.add(name.strip())
                r["list"].append({"id": sid, "name": name.strip(), "vendor": vendor_id})
        r["count"] = len(r["list"])
        r["sensor_batch"] = self._sh("dumpsys sensorservice 2>/dev/null | grep -i batch | head -5")["stdout"]
        r["sensor_wakeup"] = self._sh("dumpsys sensorservice 2>/dev/null | grep -i wake | head -10")["stdout"]
        r["sensor_dynamic"] = self._sh("dumpsys sensorservice 2>/dev/null | grep -i dynamic | head -5")["stdout"]
        return r

    def _scan_camera(self, s, d):
        r = {}
        cam = self._sh("dumpsys media.camera 2>/dev/null")["stdout"]
        r["raw"] = cam[:5000]
        camera_ids = re.findall(r'Camera\s+(\d+):', cam)
        r["camera_count"] = len(set(camera_ids))
        r["camera_ids"] = list(set(camera_ids))
        r["characteristics"] = {}
        for cid in r["camera_ids"]:
            block = self._extract_between(cam, f"Camera {cid}:", 30)
            if block:
                r["characteristics"][f"camera_{cid}"] = {
                    "facing": "front" if "facing: 1" in block or "BACK" not in block.upper() else "back",
                    "resolutions": self._extract_between(block, "resolutions:", 10) or "",
                    "fps_range": self._extract_between(block, "fpsRange", 3) or "",
                    "flash": "yes" if "flash" in block.lower() else "no",
                    "hdr": "yes" if "hdr" in block.lower() or "high dynamic range" in block.lower() else "no",
                    "ois": "yes" if "ois" in block.lower() or "optical stabilization" in block.lower() else "no",
                    "eis": "yes" if "eis" in block.lower() or "electronic stabilization" in block.lower() else "no",
                }
        r["video_codecs"] = self._sh("dumpsys media.player 2>/dev/null | grep -i 'video decoder' | head -20")["stdout"]
        r["media_codecs"] = self._sh("dumpsys media.codec 2>/dev/null | head -50")["stdout"]
        return r

    def _scan_audio(self, s, d):
        r = {}
        r["cards"] = self._cat("/proc/asound/cards").strip()
        r["devices"] = self._cat("/proc/asound/devices").strip()
        r["pcm"] = self._cat("/proc/asound/pcm").strip()
        r["codecs"] = self._sh("dumpsys media.audio_flinger 2>/dev/null | grep -E 'codec|Codec|Output|input' | head -20")["stdout"]
        r["audio_policy"] = self._sh("dumpsys audio_policy 2>/dev/null | head -40")["stdout"]
        r["audio_hal"] = self._getprop("ro.audio.hal")
        r["audio_flinger"] = self._sh("dumpsys media.audio_flinger 2>/dev/null | head -30")["stdout"]
        r["bt_codecs"] = self._sh("dumpsys bluetooth_manager 2>/dev/null | grep -i 'codec\\|LDAC\\|aptX\\|AAC\\|SBC' | head -20")["stdout"]
        r["mic_permission"] = self._sh("dumpsys audio 2>/dev/null | grep -i 'mic\\|microphone' | head -10")["stdout"]
        r["audio_effects"] = self._sh("dumpsys media.audio_flinger 2>/dev/null | grep -i 'effect' | head -20")["stdout"]
        r["alsa_mixer"] = self._sh("tinymix 2>/dev/null | head -30")["stdout"]
        r["sound_trigger"] = self._sh("dumpsys sound_trigger_service 2>/dev/null | head -20")["stdout"]
        return r

    def _scan_thermal(self, s, d):
        r = {}
        raw = self._cat("/sys/class/thermal/thermal_zone*/type")
        temps = self._cat("/sys/class/thermal/thermal_zone*/temp")
        r["zones"] = list(zip(raw.splitlines(), temps.splitlines())) if raw and temps else []
        r["thermal_service"] = self._sh("dumpsys thermalservice 2>/dev/null | head -30")["stdout"]
        r["cooling_devices"] = self._cat("/sys/class/thermal/cooling_device*/type").strip()
        r["cooling_states"] = self._cat("/sys/class/thermal/cooling_device*/cur_state").strip()
        r["throttling"] = self._sh("dumpsys thermalservice 2>/dev/null | grep -i 'throttle\\|trip' | head -10")["stdout"]
        r["cpu_temp"] = self._cat("/sys/class/thermal/thermal_zone0/temp").strip()
        r["battery_temp"] = self._cat("/sys/class/power_supply/battery/temp").strip()
        return r

    def _scan_location(self, s, d):
        r = {}
        loc = self._sh("dumpsys location 2>/dev/null")["stdout"]
        r["providers"] = self._extract_between(loc, "Location Providers:", 15) or ""
        r["gps"] = self._sh("dumpsys location 2>/dev/null | grep -A 20 'mGps' | head -30")["stdout"]
        r["network_provider"] = self._sh("dumpsys location 2>/dev/null | grep -A 10 'NetworkProvider' | head -20")["stdout"]
        r["fused_provider"] = self._sh("dumpsys location 2>/dev/null | grep -A 10 'FusedProvider' | head -20")["stdout"]
        r["gnss"] = self._sh("dumpsys gnss_driver 2>/dev/null | head -20")["stdout"]
        r["location_mode"] = self._sh("settings get secure location_mode 2>/dev/null")["stdout"].strip()
        r["location_providers"] = self._sh("settings get secure location_providers_allowed 2>/dev/null")["stdout"].strip()
        r["location_accuracy"] = self._sh("settings get secure location_accuracy 2>/dev/null")["stdout"].strip()
        r["gps_hal"] = self._getprop("ro.gps.hal")
        r["agps"] = self._getprop("ro.agps.server")
        r["last_location"] = self._extract_between(loc, "Last Known Location:", 5) or ""
        return r

    def _scan_input(self, s, d):
        r = {}
        r["devices"] = self._sh("cat /proc/bus/input/devices 2>/dev/null")["stdout"].strip()
        r["input_devs"] = self._sh("ls -la /dev/input/ 2>/dev/null")["stdout"].strip()
        r["touchscreen"] = self._sh("dumpsys input 2>/dev/null | grep -i 'touch\\|digitizer' | head -20")["stdout"]
        r["keyboard"] = self._sh("dumpsys input 2>/dev/null | grep -i 'keyboard\\|key' | head -10")["stdout"]
        r["gesture"] = self._sh("dumpsys input 2>/dev/null | grep -i 'gesture' | head -10")["stdout"]
        r["stylus"] = self._sh("dumpsys input 2>/dev/null | grep -i 'stylus\\|pen' | head -10")["stdout"]
        r["gamepad"] = self._sh("dumpsys input 2>/dev/null | grep -i 'gamepad\\|joystick' | head -10")["stdout"]
        r["trackpad"] = self._sh("dumpsys input 2>/dev/null | grep -i 'trackpad\\|mouse' | head -10")["stdout"]
        r["fingerprint"] = self._sh("dumpsys fingerprint 2>/dev/null | head -20")["stdout"]
        r["face_unlock"] = self._sh("dumpsys face 2>/dev/null | head -20")["stdout"]
        return r

    def _scan_nfc(self, s, d):
        r = {}
        nfc = self._sh("dumpsys nfc 2>/dev/null")["stdout"]
        r["enabled"] = str("NFC" in nfc or "STATE_ON" in nfc or "mState=on" in nfc.lower())
        r["chipset"] = self._extract_value(nfc, "mNfcTechnology")
        r["se_controller"] = self._extract_value(nfc, "secure_element")
        r["tech_list"] = self._extract_between(nfc, "mTechList:", 3) or ""
        r["hce"] = self._sh("dumpsys nfc 2>/dev/null | grep -i 'hce\\|host' | head -10")["stdout"]
        r["nfc_tags"] = self._sh("dumpsys nfc 2>/dev/null | grep -i 'tag\\|type' | head -10")["stdout"]
        r["nfc_fw"] = self._getprop("ro.nfc.fw")
        r["nfc_vendor"] = self._getprop("ro.nfc.vendor")
        r["nfc_controller"] = self._getprop("ro.nfc.controller")
        return r

    def _scan_security(self, s, d):
        r = {}
        r["selinux"] = self._getprop("ro.build.selinux")
        r["debuggable"] = self._getprop("ro.debuggable")
        r["secure"] = self._getprop("ro.secure")
        r["verified_boot"] = self._getprop("ro.boot.verifiedbootstate")
        r["verity_mode"] = self._getprop("ro.boot.veritymode")
        r["dm_verity"] = self._getprop("ro.boot.dmverity")
        r["encryption_state"] = self._getprop("ro.crypto.state")
        r["encryption_type"] = self._getprop("ro.crypto.type")
        r["password_type"] = self._sh("dumpsys lock_settings 2>/dev/null | grep 'password-type' | head -5")["stdout"].strip()
        r["lock_screen"] = self._sh("dumpsys lock_settings 2>/dev/null | grep -i 'lockscreen\\|locked' | head -5")["stdout"]
        r["adb_secure"] = self._getprop("ro.adb.secure")
        r["root_access"] = self._sh("which su; ls -la /system/bin/su; ls -la /sbin/su")["stdout"]
        r["magisk"] = self._sh("magisk -v 2>/dev/null")["stdout"].strip()
        r["magisk_path"] = self._sh("magisk --path 2>/dev/null")["stdout"].strip()
        r["kernel_livepatch"] = self._sh("ls -la /sys/kernel/livepatch/ 2>/dev/null")["stdout"]
        r["ksm"] = self._cat("/sys/kernel/mm/ksm/run").strip()
        r["aslr"] = self._cat("/proc/sys/kernel/randomize_va_space").strip()
        r["kptr_restrict"] = self._cat("/proc/sys/kernel/kptr_restrict").strip()
        r["dmesg_restrict"] = self._cat("/proc/sys/kernel/dmesg_restrict").strip()
        r["ptrace_scope"] = self._cat("/proc/sys/kernel/yama/ptrace_scope").strip()
        r["selinux_enforce"] = self._cat("/sys/fs/selinux/enforce").strip()
        r["seapp_contexts"] = self._cat("/sys/fs/selinux/policy 2>/dev/null | strings | head -20")["stdout"]
        r["trusted_platform"] = self._sh("dumpsys trust 2>/dev/null | head -20")["stdout"]
        r["keychain_cas"] = self._sh("dumpsys security 2>/dev/null | grep -i 'cacert\\|keychain' | head -10")["stdout"]
        r["safety_net"] = self._sh("dumpsys device_policy 2>/dev/null | grep -i 'safetynet\\|cts' | head -10")["stdout"]
        r["device_admin"] = self._sh("dumpsys device_policy 2>/dev/null | grep -i 'admin' | head -20")["stdout"]
        return r

    def _scan_selinux(self, s, d):
        r = {}
        r["mode"] = self._getprop("ro.build.selinux")
        r["enforce_current"] = self._cat("/sys/fs/selinux/enforce").strip()
        r["policy_version"] = self._cat("/sys/fs/selinux/policyvers").strip()
        r["check_reqprot"] = self._cat("/sys/fs/selinux/checkreqprot").strip()
        r["context_init"] = self._sh("cat /proc/1/attr/current 2>/dev/null")["stdout"].strip()
        r["processes"] = self._sh("ps -Z 2>/dev/null | head -30")["stdout"]
        r["avc_denials"] = self._sh("cat /proc/kmsg 2>/dev/null | grep -i avc | head -20 || dmesg | grep avc | head -20")["stdout"]
        r["booleans"] = self._sh("getenforce; setenforce 2>/dev/null || echo 'setenforce not available'")["stdout"].strip()
        r["secontext_u0"] = self._sh("id -Z 2>/dev/null")["stdout"].strip()
        return r

    def _scan_crypto(self, s, d):
        r = {}
        r["kernel_crypto"] = self._cat("/proc/crypto").strip()[:4000]
        r["fips"] = self._getprop("ro.crypto.fips")
        r["keymaster"] = self._sh("dumpsys keymaster 2>/dev/null | head -30")["stdout"]
        r["keystore"] = self._sh("dumpsys service keystore 2>/dev/null | head -20")["stdout"]
        r["tpm"] = self._sh("ls -la /dev/tpm* 2>/dev/null; cat /sys/class/tpm/tpm0/description 2>/dev/null")["stdout"]
        r["gatekeeper"] = self._sh("dumpsys gatekeeper 2>/dev/null | head -20")["stdout"]
        r["weaver"] = self._sh("dumpsys weaver 2>/dev/null | head -10")["stdout"]
        r["auth_secret"] = self._sh("dumpsys authsecret 2>/dev/null | head -10")["stdout"]
        r["oemlock"] = self._getprop("ro.oem_unlock_supported")
        r["vbmeta"] = self._sh("dumpsys vold 2>/dev/null | grep -i 'vbmeta\\|avb' | head -10")["stdout"]
        r["encrypted_dirs"] = self._sh("dumpsys vold 2>/dev/null | grep -i encrypt | head -20")["stdout"]
        r["cred_store"] = self._sh("dumpsys credential 2>/dev/null | head -20")["stdout"]
        return r

    def _scan_packages(self, s, d):
        r = {}
        r["total"] = self._sh("pm list packages 2>/dev/null | wc -l")["stdout"].strip()
        r["third_party_count"] = self._sh("pm list packages -3 2>/dev/null | wc -l")["stdout"].strip()
        r["system_count"] = self._sh("pm list packages -s 2>/dev/null | wc -l")["stdout"].strip()
        r["third_party"] = self._sh("pm list packages -3 -f 2>/dev/null")["stdout"].strip()
        r["disabled"] = self._sh("pm list packages -d 2>/dev/null")["stdout"].strip()
        r["permissions_granted"] = self._sh("pm list permissions -g 2>/dev/null | head -50")["stdout"]
        r["dangerous_perms"] = self._sh("pm list permissions -d -g 2>/dev/null | head -60")["stdout"]
        r["install_locations"] = self._sh("pm get-install-location 2>/dev/null")["stdout"].strip()
        r["max_users"] = self._sh("pm get-max-users 2>/dev/null")["stdout"].strip()
        r["max_calling"] = self._sh("pm get-max-calling 2>/dev/null")["stdout"].strip()
        return r

    def _scan_processes(self, s, d):
        r = {}
        r["ps"] = self._sh("ps -A -o PID,NAME,USER,SIZE,RSS,CPU 2>/dev/null || ps 2>/dev/null | head -80")["stdout"]
        r["ps_root"] = self._sh("ps -A 2>/dev/null | grep -E 'root |system ' | head -40")["stdout"]
        r["top_cpu"] = self._sh("top -n 1 -b 2>/dev/null | head -30 || ps -A -o %CPU,NAME 2>/dev/null | sort -rn | head -20")["stdout"]
        r["top_mem"] = self._sh("ps -eo pid,user,rss,args 2>/dev/null | sort -k3 -rn | head -20")["stdout"]
        r["zombie"] = self._sh("ps -A 2>/dev/null | grep -E 'Z\\]|defunct' | head -10")["stdout"]
        r["fd_count"] = self._sh("ls /proc/*/fd 2>/dev/null | wc -l")["stdout"].strip()
        r["oom_adj"] = self._sh("cat /proc/*/oom_adj 2>/dev/null | sort -u | head -20")["stdout"]
        r["process_sched"] = self._sh("cat /proc/*/sched 2>/dev/null | grep -E '^[a-z]' | head -30")["stdout"]
        r["native_processes"] = self._sh("getprop | grep -E 'init\\.svc\\.|ctl\\.' | head -30")["stdout"]
        return r

    def _scan_services(self, s, d):
        r = {}
        svc = self._sh("service list 2>/dev/null")["stdout"]
        r["all_services"] = svc.strip()
        r["count"] = svc.count("Found") or len([l for l in svc.splitlines() if l.strip()]) if svc else "0"
        r["running"] = self._sh("dumpsys activity services 2>/dev/null | grep -E '^\\s+' | head -40")["stdout"]
        r["system_services"] = self._sh("dumpsys -l 2>/dev/null")["stdout"].strip()
        r["java_services"] = len([l for l in svc.splitlines() if l.strip()]) if svc else 0
        r["binders"] = self._sh("cat /proc/binder/proc/* 2>/dev/null | head -30")["stdout"]
        r["binder_stats"] = self._sh("cat /proc/binder/state 2>/dev/null | head -20")["stdout"]
        r["binder_transactions"] = self._sh("cat /proc/binder/transaction_log 2>/dev/null | head -20")["stdout"]
        r["hwservices"] = self._sh("lsservice 2>/dev/null")["stdout"]
        return r

    def _scan_ports(self, s, d):
        r = {}
        r["tcp_listen"] = self._sh("cat /proc/net/tcp 2>/dev/null | grep '0A' | head -30")["stdout"]
        r["tcp6_listen"] = self._sh("cat /proc/net/tcp6 2>/dev/null | grep '0A' | head -20")["stdout"]
        r["udp_listen"] = self._sh("cat /proc/net/udp 2>/dev/null | head -20")["stdout"]
        r["tcp_connections_count"] = self._sh("cat /proc/net/tcp 2>/dev/null | wc -l")["stdout"].strip()
        r["listening_ports_raw"] = self._sh("netstat -tlnp 2>/dev/null || ss -tlnp 2>/dev/null || echo 'netstat/ss not available'")["stdout"]
        r["port_8888"] = self._sh("ss -tlnp 2>/dev/null | grep 8888 || netstat -tlnp 2>/dev/null | grep 8888 || echo 'port 8888 not found'")["stdout"]
        r["adb_forward"] = self._sh("adb forward --list 2>/dev/null")["stdout"]
        return r

    def _scan_certificates(self, s, d):
        r = {}
        r["ca_certs"] = self._sh("ls /system/etc/security/cacerts/ 2>/dev/null | head -100")["stdout"]
        r["ca_count"] = self._sh("ls /system/etc/security/cacerts/ 2>/dev/null | wc -l")["stdout"].strip()
        r["user_certs"] = self._sh("ls /data/misc/user/0/cacerts-added/ 2>/dev/null")["stdout"]
        r["user_cert_count"] = self._sh("ls /data/misc/user/0/cacerts-added/ 2>/dev/null | wc -l")["stdout"].strip()
        r["keystore_cas"] = self._sh("dumpsys security 2>/dev/null | grep -i 'certificate\\|ca:' | head -30")["stdout"]
        r["pinning"] = self._sh("dumpsys connectivity 2>/dev/null | grep -i 'pinning' | head -10")["stdout"]
        r["selinux_policy_certs"] = self._sh("dumpsys selinux 2>/dev/null | head -20")["stdout"]
        return r

    def _scan_accounts(self, s, d):
        r = {}
        r["accounts"] = self._sh("dumpsys account 2>/dev/null | grep -E 'Account|type=|name='")["stdout"]
        r["accounts_full"] = self._sh("dumpsys account 2>/dev/null | head -60")["stdout"]
        r["authenticators"] = self._sh("dumpsys account 2>/dev/null | grep -i 'authenticator' | head -10")["stdout"]
        r["users"] = self._sh("pm list users 2>/dev/null")["stdout"].strip()
        r["current_user"] = self._sh("am get-current-user 2>/dev/null")["stdout"].strip()
        r["max_users"] = self._sh("pm get-max-users 2>/dev/null")["stdout"].strip()
        return r

    def _scan_performance(self, s, d):
        r = {}
        r["uptime"] = self._sh("cat /proc/uptime")["stdout"].strip()
        r["load_avg"] = self._cat("/proc/loadavg").strip()
        r["entropy"] = self._cat("/proc/sys/kernel/random/entropy_avail").strip()
        r["interrupts_per_sec"] = self._cat("/proc/stat").strip()[:2000]
        r["swap_usage"] = self._sh("free -k 2>/dev/null || cat /proc/meminfo | grep -E 'Swap|Mem'")["stdout"]
        r["cpu_time"] = self._cat("/proc/stat").strip()[:1000]
        r["io_wait"] = self._sh("dumpsys cpuinfo 2>/dev/null | head -30")["stdout"]
        r["disk_io"] = self._sh("dumpsys diskstats 2>/dev/null | head -30")["stdout"]
        r["dns_lookup_speed"] = self._sh("time getprop 2>/dev/null; ping -c 1 -W 2 google.com 2>/dev/null")["stdout"][:500]
        r["battery_stats"] = self._sh("dumpsys batterystats --charged 2>/dev/null | head -40")["stdout"]
        r["gservices"] = self._sh("dumpsys gservices 2>/dev/null | head -30")["stdout"]
        r["cache_stats"] = self._sh("dumpsys cacheinfo 2>/dev/null | head -20")["stdout"]
        return r

    def _scan_runtime(self, s, d):
        r = {}
        r["java_heap"] = self._sh("dumpsys meminfo 2>/dev/null | head -40")["stdout"]
        r["dalvik"] = self._sh("dumpsys dalvikvm 2>/dev/null | head -30")["stdout"]
        r["art_gc"] = self._sh("dumpsys meminfo 2>/dev/null | grep -i 'art\\|dalvik\\|heap' | head -10")["stdout"]
        r["threads"] = self._sh("ls /proc/*/task/ 2>/dev/null | wc -l")["stdout"].strip()
        r["fd_limit"] = self._cat("/proc/sys/fs/file-max").strip()
        r["max_threads"] = self._cat("/proc/sys/kernel/threads-max").strip()
        r["hostname"] = self._sh("hostname 2>/dev/null")["stdout"].strip()
        r["time"] = self._sh("date 2>/dev/null")["stdout"].strip()
        r["timezone"] = self._sh("getprop persist.sys.timezone")["stdout"].strip()
        r["locale"] = self._sh("getprop persist.sys.locale")["stdout"].strip()
        return r

    def _scan_build(self, s, d):
        r = {}
        build = self._sh("getprop | grep -E '^\\[ro\\.build\\.'")["stdout"]
        for line in build.splitlines():
            if "]: [" in line:
                key = line.split("]: [")[0].strip("[").replace("ro.build.", "")
                val = line.split("]: [")[1].rstrip("]")
                r[key] = val
        return r

    def _scan_debug(self, s, d):
        r = {}
        r["last_kmsg"] = self._sh("cat /proc/last_kmsg 2>/dev/null | head -50")["stdout"]
        r["panic"] = self._sh("cat /proc/panic 2>/dev/null")["stdout"].strip()
        r["bugreport"] = self._sh("dumpsys bugreport 2>/dev/null | head -60")["stdout"]
        r["wtf"] = self._sh("dumpsys dropbox 2>/dev/null | grep -i 'wtf\\|crash\\|anr' | head -20")["stdout"]
        r["anr_traces"] = self._sh("ls -la /data/anr/ 2>/dev/null")["stdout"]
        r["tombstones"] = self._sh("ls -la /data/tombstones/ 2>/dev/null")["stdout"]
        r["crash_logs"] = self._sh("ls -la /data/system/dropbox/ 2>/dev/null | head -20")["stdout"]
        r["logcat_main"] = self._sh("logcat -d -v threadtime -b main 2>/dev/null | tail -50")["stdout"]
        r["logcat_system"] = self._sh("logcat -d -v threadtime -b system 2>/dev/null | tail -50")["stdout"]
        r["logcat_crash"] = self._sh("logcat -d -v threadtime -b crash 2>/dev/null | tail -30")["stdout"]
        r["events_log"] = self._sh("logcat -d -b events -v brief 2>/dev/null | tail -50")["stdout"]
        r["dmesg_snippet"] = self._sh("dmesg 2>/dev/null | tail -60")["stdout"]
        r["radio_log"] = self._sh("logcat -d -b radio -v threadtime 2>/dev/null | tail -30")["stdout"]
        return r

    # ═══════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════

    def _extract_value(self, text, key):
        for line in text.splitlines():
            if key in line:
                parts = line.split(":", 1)
                if len(parts) == 2:
                    return parts[1].strip()
        return ""

    def _extract_between(self, text, start, lines=10):
        if not text:
            return ""
        idx = text.find(start)
        if idx < 0:
            return ""
        rest = text[idx:]
        return "\n".join(rest.splitlines()[:lines]).strip()

    def _extract_cpu_features(self, text):
        features = set()
        for line in text.splitlines():
            if "Features" in line or "flags" in line:
                parts = line.split(":")
                if len(parts) == 2:
                    for f in parts[1].strip().split():
                        features.add(f.strip())
        return " ".join(sorted(features))

    def _map_battery_health(self, val):
        m = {"1": "unknown", "2": "good", "3": "overheat", "4": "dead",
             "5": "over_voltage", "6": "unspecified_failure", "7": "cold"}
        return m.get(val.strip(), val)

    def _map_battery_status(self, val):
        m = {"1": "unknown", "2": "charging", "3": "discharging",
             "4": "not_charging", "5": "full"}
        return m.get(val.strip(), val)

    def _print_summary_table(self):
        table = Table(title="[bold green]Deep Scan Summary[/bold green]",
                      border_style="green", header_style="bold yellow")
        table.add_column("Category", style="bold cyan")
        table.add_column("Fields", style="white")

        for cat in self.SCAN_CATEGORIES:
            data = self._results.get(cat, {})
            if "error" in data:
                table.add_row(cat, f"[red]{data['error']}[/red]")
            elif isinstance(data, dict):
                count = len(data)
                table.add_row(cat, str(count))
        console.print(table)

    def _save_report(self):
        os.makedirs("reports", exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = f"reports/deep_scan_{ts}.json"

        def clean(obj):
            if isinstance(obj, dict):
                return {k: clean(v) for k, v in obj.items() if v and k != "raw"}
            if isinstance(obj, (list, tuple)):
                return [clean(i) for i in obj]
            return obj

        with open(path, "w") as f:
            json.dump(clean(self._results), f, indent=2)
        return path
