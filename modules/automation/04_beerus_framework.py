import os
import sys
import subprocess
import time
import json
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

ENGINE = Path(__file__).parent.parent.parent / "golang" / "automation" / "beerus_framework"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "automation" / "beerus_framework.sh"

class Module(AndroModule):
    name = "automation/beerus_framework"
    description = "Beerus Framework — Hakai Offensive Security modular framework covering all mobile pentest phases with custom USB attack modules."
    author = "AndroXploit"

    options = {
        "MODULE": {
            "description": "Beerus module to execute (e.g., recon/network, exploit/hid, post/extract)",
            "required": True,
            "value": None,
        },
        "TARGET": {
            "description": "Target device IP:port or USB serial",
            "required": True,
            "value": None,
        },
        "PAYLOAD": {
            "description": "Custom payload path or built-in payload name",
            "required": False,
            "value": None,
        },
        "ARGS": {
            "description": "Additional arguments passed to the module (comma-separated)",
            "required": False,
            "value": None,
        },
        "VERBOSE": {
            "description": "Enable verbose output",
            "required": False,
            "value": True,
        },
    }

    def run(self):
        module = self.get_option("MODULE")
        target = self.get_option("TARGET")
        payload = self.get_option("PAYLOAD")
        args_extra = self.get_option("ARGS")
        verbose = self.get_option("VERBOSE")

        self.info(f"Beerus Framework — Module: {module}")
        self.info(f"Target: {target}")

        result = {"status": "idle", "module": module, "output": [], "data": {}}

        if ENGINE.exists():
            cmd = [str(ENGINE), "--module", module, "--target", target]
            if payload:
                cmd.extend(["--payload", payload])
            if args_extra:
                cmd.extend(["--args", args_extra])
            if verbose:
                cmd.append("--verbose")
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if proc.stdout:
                try:
                    result = json.loads(proc.stdout)
                except json.JSONDecodeError:
                    result["output"] = proc.stdout.splitlines()
        elif SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), module, target, payload or "", args_extra or "", str(verbose)],
                capture_output=True, text=True, timeout=300
            )
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn("No engine found; simulating Beerus module execution")
            phases = ["Initializing module", "Connecting to target", "Loading dependencies",
                      "Executing attack vector", "Collecting results"]
            for i, phase in enumerate(phases):
                self.log(f"[{module}] {phase}...")
                time.sleep(0.3 + (i * 0.1))
            result["status"] = "simulated"
            result["data"] = {"module": module, "target": target, "findings": "simulated"}

        if result["status"] != "failed":
            self.success(f"Beerus module '{module}' completed")
            if result.get("data"):
                for k, v in result["data"].items():
                    if isinstance(v, dict):
                        for sk, sv in v.items():
                            self.log(f"  {sk}: {sv}")
                    else:
                        self.log(f"  {k}: {v}")
        else:
            self.error(f"Module '{module}' failed")

        t = Table(title="Beerus Framework Execution", border_style="green")
        t.add_column("Item", style="bold yellow")
        t.add_column("Value", style="white")
        t.add_row("Module", module)
        t.add_row("Target", target)
        t.add_row("Status", result["status"])
        t.add_row("Output lines", str(len(result.get("output", []))))
        self.console.print(t)

        return result
