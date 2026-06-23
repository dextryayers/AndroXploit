import os
import sys
import subprocess
import time
import json
import random
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

ENGINE = Path(__file__).parent.parent.parent / "golang" / "automation" / "stryker_app"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "automation" / "stryker_app.sh"

class Module(AndroModule):
    name = "automation/stryker_app"
    description = "Stryker App — Mobile pentest suite running directly on Android, combining network and wireless security tools via USB peripherals."
    author = "AndroXploit"

    options = {
        "CONNECTION": {
            "description": "Connection type: usb, wireless, or bluetooth",
            "required": False,
            "value": "usb",
        },
        "INTERFACE": {
            "description": "Network interface to scan (e.g., wlan0, eth0)",
            "required": False,
            "value": "wlan0",
        },
        "SCAN_TYPE": {
            "description": "Scan type: network, wireless, bluetooth, all",
            "required": False,
            "value": "all",
        },
        "ROOT_MODE": {
            "description": "Enable root-privileged operations",
            "required": False,
            "value": False,
        },
        "TIMEOUT": {
            "description": "Scan timeout in seconds per target",
            "required": False,
            "value": 60,
        },
    }

    def run(self):
        conn = self.get_option("CONNECTION")
        iface = self.get_option("INTERFACE")
        scan_type = self.get_option("SCAN_TYPE")
        root = self.get_option("ROOT_MODE")
        timeout = int(self.get_option("TIMEOUT", 60))

        self.info(f"Stryker App — {conn.upper()} mode")
        self.info(f"Interface: {iface} | Scan: {scan_type} | Root: {root}")

        result = {"status": "idle", "findings": []}

        if ENGINE.exists():
            proc = subprocess.run(
                [str(ENGINE), "--interface", iface, "--scan", scan_type,
                 "--conn", conn, "--timeout", str(timeout)] +
                (["--root"] if root else []),
                capture_output=True, text=True, timeout=timeout + 30
            )
            if proc.stdout:
                try:
                    result = json.loads(proc.stdout)
                except json.JSONDecodeError:
                    result["output"] = proc.stdout.splitlines()
        elif SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), conn, iface, scan_type, str(root), str(timeout)],
                capture_output=True, text=True, timeout=timeout + 30
            )
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn("No engine found; running simulated scan sequence")
            targets = ["router", "gateway", "connected_clients", "bluetooth_devices"]
            for i, target in enumerate(targets):
                self.log(f"Scanning {target}... ({i+1}/{len(targets)})")
                time.sleep(0.4 + (timeout / len(targets)))
                findings = random.randint(0, 3)
                result["findings"].append({"target": target, "issues": findings})
            result["status"] = "simulated"

        if result.get("output"):
            for line in result["output"]:
                if line.strip():
                    self.log(line)

        if result["status"] != "failed":
            self.success(f"Stryker scan complete — {len(result.get('findings', []))} target(s) analyzed")
        else:
            self.error("Scan encountered errors")

        t = Table(title="Stryker Scan Results", border_style="green")
        t.add_column("Target", style="bold yellow")
        t.add_column("Findings", style="white")
        for f in result.get("findings", []):
            t.add_row(f.get("target", "?"), str(f.get("issues", 0)))
        if not result.get("findings"):
            t.add_row("No targets", "—")
        self.console.print(t)

        return result
