import os
import subprocess
import time
import json
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

ENGINE = Path(__file__).parent.parent.parent / "golang" / "adb_toolkit" / "adbsploit"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "adb_toolkit" / "adbsploit.sh"

class Module(AndroModule):
    name = "adb_toolkit/adbsploit"
    description = "ADBSploit — Multi-function ADB tool for exploitation and device management: install, screenshot, GPS spoof, file access, Fastboot."
    author = "AndroXploit"

    options = {
        "TARGET": {
            "description": "Target device IP:port or 'usb' for USB-connected device",
            "required": True,
            "value": None,
        },
        "ACTION": {
            "description": "Action: shell, screenshot, screenrecord, install, pull, push, gps_spoof, fastboot, info, all",
            "required": False,
            "value": "info",
        },
        "FILE_PATH": {
            "description": "File path for install/pull/push actions",
            "required": False,
            "value": None,
        },
        "DEST_PATH": {
            "description": "Destination path for push/pull actions",
            "required": False,
            "value": None,
        },
        "GPS_LAT": {
            "description": "GPS latitude for spoofing",
            "required": False,
            "value": None,
        },
        "GPS_LON": {
            "description": "GPS longitude for spoofing",
            "required": False,
            "value": None,
        },
    }

    def run(self):
        target = self.get_option("TARGET")
        action = self.get_option("ACTION")
        fpath = self.get_option("FILE_PATH")
        dpath = self.get_option("DEST_PATH")
        lat = self.get_option("GPS_LAT")
        lon = self.get_option("GPS_LON")

        self.info(f"ADBSploit — Target: {target} | Action: {action}")

        if action == "gps_spoof" and (not lat or not lon):
            self.error("GPS_LAT and GPS_LON required for GPS spoofing")
            return {"status": "failed", "error": "GPS coordinates missing"}

        result = {"status": "idle", "action": action, "data": {}}

        if ENGINE.exists():
            cmd = [str(ENGINE), "--target", target, "--action", action]
            if fpath:
                cmd.extend(["--file", fpath])
            if dpath:
                cmd.extend(["--dest", dpath])
            if lat:
                cmd.extend(["--lat", lat])
            if lon:
                cmd.extend(["--lon", lon])
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            if proc.stdout:
                try:
                    result = json.loads(proc.stdout)
                except json.JSONDecodeError:
                    result["output"] = proc.stdout.splitlines()
        elif SCRIPT.exists():
            cmd = ["bash", str(SCRIPT), target, action, fpath or "", dpath or "", lat or "", lon or ""]
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn("No engine found; simulating ADB operations")
            self.log(f"Connecting to {target}...")
            time.sleep(0.3)

            actions_map = {
                "info": ["device_info", "android_version", "battery", "storage", "installed_packages"],
                "screenshot": ["Saving screenshot to device"],
                "shell": ["Opening interactive shell on device"],
                "install": [f"Installing {fpath}..."],
                "pull": [f"Pulling {fpath} to {dpath or 'local'}..."],
                "push": [f"Pushing {fpath or 'local'} to {dpath}..."],
                "gps_spoof": [f"Spoofing GPS to {lat}, {lon}..."],
                "all": ["Running full device enumeration..."],
            }
            steps = actions_map.get(action, ["Executing..."])
            for s in steps:
                self.log(s)
                time.sleep(0.4)
            result["status"] = "simulated"
            result["data"] = {"action": action, "target": target, "completed": True}

        if result["status"] != "failed":
            self.success(f"ADBSploit: {action} completed")
            if isinstance(result.get("data"), dict):
                for k, v in result["data"].items():
                    self.log(f"  {k}: {v}")
        else:
            self.error(f"ADBSploit: {action} failed")

        t = Table(title="ADBSploit Results", border_style="green")
        t.add_column("Item", style="bold yellow")
        t.add_column("Value", style="white")
        t.add_row("Target", target)
        t.add_row("Action", action)
        t.add_row("Status", result.get("status", "unknown"))
        if isinstance(result.get("data"), dict):
            for k, v in result["data"].items():
                t.add_row(k, str(v)[:60])
        self.console.print(t)

        return result
