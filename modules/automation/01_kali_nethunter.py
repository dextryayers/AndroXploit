import os
import sys
import subprocess
import time
import json
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

ENGINE = Path(__file__).parent.parent.parent / "golang" / "automation" / "kali_nethunter"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "automation" / "kali_nethunter.sh"

class Module(AndroModule):
    name = "automation/kali_nethunter"
    description = "Kali NetHunter — BadUSB / Rubber Ducky attack via USB OTG. Simulates keyboard injection to execute payloads automatically."
    author = "AndroXploit"

    options = {
        "USB_DEVICE": {
            "description": "Target USB device path (e.g., /dev/hidg0)",
            "required": True,
            "value": "/dev/hidg0",
        },
        "KEYBOARD_LAYOUT": {
            "description": "Keyboard layout for HID injection (us, de, fr, etc.)",
            "required": False,
            "value": "us",
        },
        "PAYLOAD_PATH": {
            "description": "Path to Rubber Ducky payload .txt file",
            "required": True,
            "value": None,
        },
        "DELAY": {
            "description": "Default delay in ms between keystrokes",
            "required": False,
            "value": 100,
        },
        "REPEAT": {
            "description": "Number of times to repeat the payload",
            "required": False,
            "value": 1,
        },
    }

    def run(self):
        device = self.get_option("USB_DEVICE")
        layout = self.get_option("KEYBOARD_LAYOUT")
        payload = self.get_option("PAYLOAD_PATH")
        delay = int(self.get_option("DELAY", 100))
        repeat = int(self.get_option("REPEAT", 1))

        if not os.path.exists(payload):
            self.error(f"Payload file not found: {payload}")
            return {"status": "failed", "error": "Payload not found"}

        self.info(f"Target device: {device}")
        self.info(f"Payload: {payload}")
        self.info(f"Layout: {layout} | Delay: {delay}ms | Repeat: {repeat}x")

        payload_data = open(payload).read()
        ducky_cmd = ""
        for line in payload_data.strip().splitlines():
            line = line.strip()
            if not line or line.startswith("REM"):
                continue
            ducky_cmd += line + "\n"

        result = {"status": "idle", "output": []}

        if ENGINE.exists():
            proc = subprocess.run(
                [str(ENGINE), "--device", device, "--layout", layout, "--payload", payload,
                 "--delay", str(delay), "--repeat", str(repeat)],
                capture_output=True, text=True, timeout=120
            )
            if proc.stdout:
                try:
                    result = json.loads(proc.stdout)
                except json.JSONDecodeError:
                    result["output"] = proc.stdout.splitlines()
            if proc.returncode != 0:
                self.warn(f"Engine stderr: {proc.stderr}")
        elif SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), device, layout, payload, str(delay), str(repeat)],
                capture_output=True, text=True, timeout=120
            )
            result["output"] = proc.stdout.splitlines()
            if proc.returncode != 0:
                result["status"] = "failed"
                self.warn(f"Script stderr: {proc.stderr}")
        else:
            self.warn("No engine binary or script found; simulating injection sequence")
            lines = ducky_cmd.splitlines()
            for i, cmdline in enumerate(lines):
                time.sleep(delay / 1000)
                self.log(f"[{i+1}/{len(lines)}] {cmdline.strip()}")
            result["status"] = "simulated"
            result["output"] = lines

        if result.get("status") in ("success", "simulated"):
            self.success("BadUSB injection completed successfully")
        else:
            self.error("Injection failed or encountered errors")

        t = Table(title="Injection Summary", border_style="green")
        t.add_column("Metric", style="bold yellow")
        t.add_column("Value", style="white")
        t.add_row("Device", device)
        t.add_row("Payload", payload)
        t.add_row("Lines", str(len(ducky_cmd.splitlines())))
        t.add_row("Status", result.get("status", "unknown"))
        self.console.print(t)

        return result
