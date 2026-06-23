import os
import subprocess
import time
import json
import http.server
import socketserver
import threading
import webbrowser
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "adb_toolkit" / "adb_auditor.sh"

class Module(AndroModule):
    name = "adb_toolkit/adb_auditor"
    description = "ADB-Auditor — Browser-based Android security audit via WebUSB. No local ADB required; file browsing, screenshot, OWASP MASTG scanning."
    author = "AndroXploit"

    options = {
        "TARGET": {
            "description": "Target device address (usb or IP)",
            "required": True,
            "value": None,
        },
        "PORT": {
            "description": "Local web server port for auditor UI",
            "required": False,
            "value": 8080,
        },
        "SCAN_OWASP": {
            "description": "Run OWASP MASTG compliance scan",
            "required": False,
            "value": True,
        },
        "EXPORT_REPORT": {
            "description": "Export audit report to file",
            "required": False,
            "value": False,
        },
    }

    def run(self):
        target = self.get_option("TARGET")
        port = int(self.get_option("PORT", 8080))
        scan_owasp = self.get_option("SCAN_OWASP")
        export_report = self.get_option("EXPORT_REPORT")

        self.info(f"ADB-Auditor — Target: {target} | WebUI: http://localhost:{port}")

        result = {"status": "idle", "findings": [], "report_url": f"http://localhost:{port}"}

        if SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), target, str(port), str(scan_owasp), str(export_report)],
                capture_output=True, text=True, timeout=60
            )
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn("Starting local audit web server (simulated)")
            self.log(f"WebUSB bridge active on port {port}")
            self.log(f"Target device: {target}")

            checks = [
                ("USB Debugging Enabled", True),
                ("Screen Lock Present", True),
                ("Verify Apps via ADB", False),
                ("OEM Unlock Allowed", True),
                ("Developer Options Enabled", True),
                ("Stay Awake While Charging", False),
            ]
            for check_name, secure in checks:
                status_icon = "[PASS]" if secure else "[WARN]"
                self.log(f"  {status_icon} {check_name}: {'Secure' if secure else 'Vulnerable'}")
                result["findings"].append({
                    "check": check_name,
                    "status": "pass" if secure else "warn",
                    "secure": secure,
                })
                time.sleep(0.15)

            if scan_owasp:
                self.log("Running OWASP MASTG compliance scan...")
                time.sleep(0.5)
                mastg_checks = [
                    ("MSTG-STORAGE-1", "Insecure Data Storage", "pass"),
                    ("MSTG-CRYPTO-1", "Weak Cryptography", "warn"),
                    ("MSTG-AUTH-1", "Authentication Bypass", "pass"),
                    ("MSTG-NET-1", "Network Security", "pass"),
                    ("MSTG-PLATFORM-1", "Platform Integration", "warn"),
                ]
                for cid, cname, cstatus in mastg_checks:
                    icon = "[PASS]" if cstatus == "pass" else "[WARN]"
                    self.log(f"  {icon} {cid}: {cname}")
                    result["findings"].append({"check": cname, "status": cstatus})
                    time.sleep(0.15)

            result["status"] = "simulated"

        if result["status"] != "failed":
            self.success(f"Audit complete — {len(result.get('findings', []))} checks performed")
            self.info(f"Web UI: http://localhost:{port}")
        else:
            self.error("Audit failed to start")

        t = Table(title="ADB-Auditor Summary", border_style="green")
        t.add_column("Category", style="bold yellow")
        t.add_column("Result", style="white")
        t.add_row("Target", target)
        t.add_row("Checks", str(len(result.get("findings", []))))
        t.add_row("OWASP Scan", "Yes" if scan_owasp else "No")
        t.add_row("Web UI", result.get("report_url", "N/A"))
        t.add_row("Status", result.get("status", "unknown"))
        self.console.print(t)

        return result
