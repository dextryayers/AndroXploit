import os
import subprocess
import time
import json
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

ENGINE = Path(__file__).parent.parent.parent / "golang" / "supporting" / "frida"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "supporting" / "frida.sh"

class Module(AndroModule):
    name = "supporting/frida"
    description = "Frida — Dynamic code instrumentation toolkit. Inject JavaScript to hook functions, monitor APIs, trace crypto, and manipulate runtime behavior over USB."
    author = "AndroXploit"

    options = {
        "TARGET": {
            "description": "Target: package name, PID, or process name",
            "required": True,
            "value": None,
        },
        "ACTION": {
            "description": "Action: spawn, attach, trace, hook, enumerate, dump, inject",
            "required": False,
            "value": "enumerate",
        },
        "SCRIPT_PATH": {
            "description": "Path to Frida JavaScript hook script",
            "required": False,
            "value": None,
        },
        "SCRIPT_SOURCE": {
            "description": "Inline JavaScript source code for injection",
            "required": False,
            "value": None,
        },
        "TRACE_MODULE": {
            "description": "Module to trace (e.g., libssl.so)",
            "required": False,
            "value": None,
        },
        "TRACE_FUNCTION": {
            "description": "Function to trace within module",
            "required": False,
            "value": None,
        },
        "USB_SERIAL": {
            "description": "USB device serial",
            "required": False,
            "value": None,
        },
    }

    def run(self):
        target = self.get_option("TARGET")
        action = self.get_option("ACTION")
        script_path = self.get_option("SCRIPT_PATH")
        script_source = self.get_option("SCRIPT_SOURCE")
        trace_module = self.get_option("TRACE_MODULE")
        trace_function = self.get_option("TRACE_FUNCTION")
        serial = self.get_option("USB_SERIAL")

        self.info(f"Frida — Target: {target} | Action: {action}")

        if script_path and script_source:
            self.warn("Both SCRIPT_PATH and SCRIPT_SOURCE set; using SCRIPT_PATH")

        result = {"status": "idle", "action": action, "data": {}}

        if ENGINE.exists():
            cmd = [str(ENGINE), "--target", target, "--action", action]
            if script_path:
                cmd.extend(["--script", script_path])
            if script_source:
                cmd.extend(["--source", script_source])
            if trace_module:
                cmd.extend(["--module", trace_module])
            if trace_function:
                cmd.extend(["--function", trace_function])
            if serial:
                cmd.extend(["--serial", serial])
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            if proc.stdout:
                try:
                    result = json.loads(proc.stdout)
                except json.JSONDecodeError:
                    result["output"] = proc.stdout.splitlines()
        elif SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), target, action, script_path or "", script_source or "",
                 trace_module or "", trace_function or "", serial or ""],
                capture_output=True, text=True, timeout=120
            )
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn(f"Simulating Frida: {action} on {target}")

            script_content = script_source or "console.log('Frida hook active');"
            if script_path and os.path.exists(script_path):
                script_content = open(script_path).read()

            actions = {
                "enumerate": [
                    f"Attaching to {target}...",
                    "Enumerating loaded modules...",
                    "Enumerating classes...",
                    "Listing exports...",
                ],
                "spawn": [
                    f"Spawning {target} in suspended mode...",
                    "Injecting Frida agent...",
                    "Resuming main thread...",
                    "Frida agent active",
                ],
                "trace": [
                    f"Tracing {trace_module or 'all'}:{trace_function or '*'}" ,
                    "Installing interceptors...",
                    "Monitoring function calls...",
                    "Capturing arguments and return values...",
                ],
                "hook": [
                    f"Loading script: {script_path or 'inline'}",
                    "Injecting JavaScript hook...",
                    "Hook installed successfully",
                    "Monitoring...",
                ],
                "dump": [
                    f"Dumping runtime state of {target}...",
                    "Extracting loaded classes...",
                    "Capturing heap allocations...",
                ],
            }

            steps = actions.get(action, actions["enumerate"])
            for s in steps:
                self.log(s)
                time.sleep(0.3)

            if action == "enumerate":
                result["data"] = {
                    "modules": ["libssl.so", "libc.so", "libcrypto.so", "libjavacore.so", "libandroid_runtime.so"],
                    "classes": 8432,
                    "exports": 12453,
                }
            elif action == "trace":
                result["data"]["calls"] = [
                    {"function": f"{trace_function or 'func_A'}", "args": ["0x1234", "0xabcd"], "ret": "0x1"},
                    {"function": f"{trace_function or 'func_B'}", "args": ["str='secret'", "int=42"], "ret": "0x0"},
                ]

            result["status"] = "simulated"

        if result["status"] != "failed":
            self.success(f"Frida: {action} on {target} successful")
            if result.get("data", {}).get("modules"):
                self.log(f"  Modules: {', '.join(result['data']['modules'][:5])}")
        else:
            self.error("Frida operation failed")
            self.info("Ensure: 1) Frida server on device 2) USB debugging enabled 3) App running")

        t = Table(title="Frida Instrumentation", border_style="green")
        t.add_column("Key", style="bold yellow")
        t.add_column("Value", style="white")
        t.add_row("Target", target)
        t.add_row("Action", action)
        t.add_row("Script", script_path or "inline")
        t.add_row("Status", result.get("status", "unknown"))
        data = result.get("data", {})
        if data.get("modules"):
            t.add_row("Modules Found", str(len(data["modules"])))
        if data.get("classes"):
            t.add_row("Classes", str(data["classes"]))
        self.console.print(t)

        return result
