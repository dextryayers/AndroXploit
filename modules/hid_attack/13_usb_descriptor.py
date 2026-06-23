import os
import subprocess
import time
import json
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

ENGINE = Path(__file__).parent.parent.parent / "golang" / "hid_attack" / "usb_descriptor"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "hid_attack" / "usb_descriptor.sh"

class Module(AndroModule):
    name = "hid_attack/usb_descriptor"
    description = "USB Descriptor Explorer — Android app for inspecting USB device details: descriptors, HID reports, configuration, and interface analysis."
    author = "AndroXploit"

    options = {
        "DEVICE_PATH": {
            "description": "USB device path in /sys/bus/usb/devices/ (e.g., 1-1:1.0)",
            "required": True,
            "value": None,
        },
        "TARGET": {
            "description": "Target device ADB serial or IP",
            "required": False,
            "value": "usb",
        },
        "ANALYZE_HID": {
            "description": "Parse HID report descriptors in detail",
            "required": False,
            "value": True,
        },
        "EXPORT_JSON": {
            "description": "Export descriptor tree to JSON file",
            "required": False,
            "value": None,
        },
    }

    def run(self):
        dev_path = self.get_option("DEVICE_PATH")
        target = self.get_option("TARGET")
        analyze_hid = self.get_option("ANALYZE_HID")
        export_json = self.get_option("EXPORT_JSON")

        self.info(f"USB Descriptor Explorer — Device: {dev_path}")
        self.info(f"Target: {target} | HID Analysis: {analyze_hid}")

        result = {"status": "idle", "descriptors": {}}

        if ENGINE.exists():
            cmd = [str(ENGINE), "--device", dev_path, "--target", target]
            if analyze_hid:
                cmd.append("--hid")
            if export_json:
                cmd.extend(["--export", export_json])
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if proc.stdout:
                try:
                    result = json.loads(proc.stdout)
                except json.JSONDecodeError:
                    result["output"] = proc.stdout.splitlines()
        elif SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), dev_path, target, str(analyze_hid), export_json or ""],
                capture_output=True, text=True, timeout=30
            )
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn("Simulating USB descriptor analysis")
            self.log(f"Reading device descriptors from {dev_path}...")
            time.sleep(0.3)

            descriptors = {
                "device": {
                    "idVendor": "0x18d1",
                    "idProduct": "0x4ee7",
                    "bcdUSB": "0x0200",
                    "bDeviceClass": "0x00",
                    "bDeviceSubClass": "0x00",
                    "bDeviceProtocol": "0x00",
                    "bMaxPacketSize0": "64",
                    "bNumConfigurations": "1",
                },
                "configuration": {
                    "bConfigurationValue": "1",
                    "bNumInterfaces": "2",
                    "bmAttributes": "0x80",
                    "bMaxPower": "500mA",
                },
                "interface_0": {
                    "bInterfaceClass": "0x08",
                    "bInterfaceSubClass": "0x06",
                    "bInterfaceProtocol": "0x50",
                    "iInterface": "MSC Bulk-Only Transfer",
                },
                "interface_1": {
                    "bInterfaceClass": "0x03",
                    "bInterfaceSubClass": "0x00",
                    "bInterfaceProtocol": "0x00",
                    "iInterface": "HID",
                },
            }

            if analyze_hid:
                descriptors["hid_report"] = {
                    "bDescriptorType": "0x22",
                    "wReportLength": "52",
                    "usage_page": "0x0001 (Generic Desktop)",
                    "usage": "0x0002 (Mouse)",
                    "report_count": "5",
                    "input_report": "3 bytes",
                    "output_report": "0 bytes",
                    "feature_report": "0 bytes",
                }

            result["descriptors"] = descriptors
            result["status"] = "simulated"

        if result["status"] != "failed":
            self.success("USB descriptor analysis complete")
            desc = result.get("descriptors", {})
            if desc.get("device"):
                dev = desc["device"]
                self.log(f"  Vendor: {dev.get('idVendor', '?')} Product: {dev.get('idProduct', '?')}")
                self.log(f"  USB Version: {dev.get('bcdUSB', '?')}")
            if desc.get("hid_report") and analyze_hid:
                self.log(f"  HID Report Length: {desc['hid_report'].get('wReportLength', '?')} bytes")
        else:
            self.error("Descriptor analysis failed")

        t = Table(title="USB Device Descriptors", border_style="green")
        t.add_column("Descriptor", style="bold yellow")
        t.add_column("Key", style="blue")
        t.add_column("Value", style="white")
        for section, values in result.get("descriptors", {}).items():
            if isinstance(values, dict):
                for k, v in list(values.items())[:3]:
                    t.add_row(section, k, str(v))
        if not result.get("descriptors"):
            t.add_row("No data", "—", "—")
        self.console.print(t)

        if export_json:
            with open(export_json, "w") as f:
                json.dump(result.get("descriptors", {}), f, indent=2)
            self.success(f"Descriptors exported to {export_json}")

        return result
