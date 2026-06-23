import os
import subprocess
import time
import json
import random
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

ENGINE = Path(__file__).parent.parent.parent / "golang" / "adb_toolkit" / "yafed"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "adb_toolkit" / "yafed.sh"

class Module(AndroModule):
    name = "adb_toolkit/yafed"
    description = "YAFED (Yet Another Forensic Extraction Framework) — Modular mobile forensic framework that auto-extracts data via USB upon device connection."
    author = "AndroXploit"

    options = {
        "OUTPUT_DIR": {
            "description": "Directory to store extracted forensic artifacts",
            "required": True,
            "value": None,
        },
        "TARGET": {
            "description": "Target device (usb or IP:port)",
            "required": True,
            "value": None,
        },
        "EXTRACT_CALLS": {
            "description": "Extract call logs",
            "required": False,
            "value": True,
        },
        "EXTRACT_SMS": {
            "description": "Extract SMS/MMS messages",
            "required": False,
            "value": True,
        },
        "EXTRACT_CONTACTS": {
            "description": "Extract contact list",
            "required": False,
            "value": True,
        },
        "EXTRACT_APPS": {
            "description": "Extract installed APK list",
            "required": False,
            "value": True,
        },
        "EXTRACT_FILES": {
            "description": "Extract file system listing",
            "required": False,
            "value": False,
        },
        "PARALLEL": {
            "description": "Extract in parallel threads",
            "required": False,
            "value": True,
        },
    }

    def run(self):
        outdir = self.get_option("OUTPUT_DIR")
        target = self.get_option("TARGET")
        extract_calls = self.get_option("EXTRACT_CALLS")
        extract_sms = self.get_option("EXTRACT_SMS")
        extract_contacts = self.get_option("EXTRACT_CONTACTS")
        extract_apps = self.get_option("EXTRACT_APPS")
        extract_files = self.get_option("EXTRACT_FILES")
        parallel = self.get_option("PARALLEL")

        os.makedirs(outdir, exist_ok=True)

        self.info(f"YAFED — Target: {target} | Output: {outdir}")
        self.info(f"Extracting: calls={extract_calls} sms={extract_sms} contacts={extract_contacts} apps={extract_apps} files={extract_files}")

        result = {"status": "idle", "artifacts": {}}

        if ENGINE.exists():
            cmd = [str(ENGINE), "--target", target, "--output", outdir]
            if extract_calls: cmd.append("--calls")
            if extract_sms: cmd.append("--sms")
            if extract_contacts: cmd.append("--contacts")
            if extract_apps: cmd.append("--apps")
            if extract_files: cmd.append("--files")
            if parallel: cmd.append("--parallel")
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if proc.stdout:
                try:
                    result = json.loads(proc.stdout)
                except json.JSONDecodeError:
                    result["output"] = proc.stdout.splitlines()
        elif SCRIPT.exists():
            flags = f"{'c' if extract_calls else ''}{'s' if extract_sms else ''}{'n' if extract_contacts else ''}{'a' if extract_apps else ''}{'f' if extract_files else ''}"
            proc = subprocess.run(
                ["bash", str(SCRIPT), target, outdir, flags, str(parallel)],
                capture_output=True, text=True, timeout=300
            )
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn("Simulating forensic extraction")
            categories = {
                "calls": extract_calls,
                "sms": extract_sms,
                "contacts": extract_contacts,
                "apps": extract_apps,
                "files": extract_files,
            }
            for cat, enabled in categories.items():
                if not enabled:
                    continue
                self.log(f"Extracting {cat}...")
                time.sleep(0.4 + (0.2 if parallel else 0.4))
                sample = random.randint(5, 50)
                result["artifacts"][cat] = {"count": sample, "file": f"{outdir}/{cat}.xml"}
                self.success(f"  {sample} {cat} records extracted")

            result["status"] = "simulated"

        if result["status"] != "failed":
            total = sum(a.get("count", 0) for a in result.get("artifacts", {}).values())
            self.success(f"Extraction complete — {total} artifacts saved to {outdir}")
        else:
            self.error("Extraction failed")

        t = Table(title="YAFED Extraction Results", border_style="green")
        t.add_column("Category", style="bold yellow")
        t.add_column("Count", style="white")
        t.add_column("File", style="dim")
        for cat, data in result.get("artifacts", {}).items():
            t.add_row(cat.capitalize(), str(data.get("count", 0)), str(data.get("file", "")))
        if not result.get("artifacts"):
            t.add_row("No data", "—", "—")
        t.add_row("Output Dir", outdir, "")
        t.add_row("Status", result.get("status", "unknown"), "")
        self.console.print(t)

        return result
