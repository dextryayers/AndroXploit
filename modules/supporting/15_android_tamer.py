import os
import subprocess
import time
import json
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "supporting" / "android_tamer.sh"

class Module(AndroModule):
    name = "supporting/android_tamer"
    description = "Android Tamer — Pre-configured virtual machine for Android security researchers with ADB, platform tools, and analysis frameworks."
    author = "AndroXploit"

    options = {
        "ACTION": {
            "description": "Action: setup, start, stop, status, import, export",
            "required": True,
            "value": None,
        },
        "VM_NAME": {
            "description": "Virtual machine name",
            "required": False,
            "value": "AndroidTamer",
        },
        "VM_DIR": {
            "description": "Directory for VM storage",
            "required": False,
            "value": "~/AndroidTamer",
        },
        "RAM_GB": {
            "description": "RAM allocation in GB",
            "required": False,
            "value": 4,
        },
        "CPU_CORES": {
            "description": "CPU core allocation",
            "required": False,
            "value": 2,
        },
        "USB_PASSTHROUGH": {
            "description": "Enable USB device passthrough to VM",
            "required": False,
            "value": True,
        },
    }

    def run(self):
        action = self.get_option("ACTION")
        vm_name = self.get_option("VM_NAME")
        vm_dir = os.path.expanduser(self.get_option("VM_DIR"))
        ram = int(self.get_option("RAM_GB", 4))
        cpu = int(self.get_option("CPU_CORES", 2))
        usb = self.get_option("USB_PASSTHROUGH")

        self.info(f"Android Tamer — Action: {action} | VM: {vm_name}")

        result = {"status": "idle", "action": action, "vm_info": {}}

        if SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), action, vm_name, str(ram), str(cpu), str(usb)],
                capture_output=True, text=True, timeout=120
            )
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn(f"Simulating Android Tamer VM operation: {action}")

            actions = {
                "setup": [
                    "Checking virtualization support (KVM/HAXM)",
                    "Downloading Android Tamer OVA...",
                    f"Allocating {ram}GB RAM, {cpu} CPU cores",
                    "Importing VM...",
                    "Configuring ADB USB passthrough",
                    "Installing guest additions",
                ],
                "start": [
                    f"Starting VM: {vm_name}",
                    "Allocating resources...",
                    "VM booting (waiting for ADB)...",
                    "ADB device detected",
                ],
                "stop": [
                    f"Stopping VM: {vm_name}",
                    "Saving VM state...",
                ],
                "status": [
                    f"VM Name: {vm_name}",
                    f"State: {'Running' if action == 'status' else 'Stopped'}",
                    f"RAM: {ram}GB allocated",
                    f"CPU: {cpu} cores",
                    f"USB Passthrough: {'Enabled' if usb else 'Disabled'}",
                ],
            }

            steps = actions.get(action, [f"Unknown action: {action}"])
            for s in steps:
                self.log(s)
                time.sleep(0.3 + (0.1 if action == "setup" else 0))

            result["vm_info"] = {
                "name": vm_name,
                "directory": vm_dir,
                "ram_gb": ram,
                "cpu_cores": cpu,
                "usb_passthrough": usb,
            }
            result["status"] = "simulated"

        if result["status"] != "failed":
            if action == "start":
                self.success(f"VM '{vm_name}' started — use 'adb devices' to connect")
            elif action == "stop":
                self.success(f"VM '{vm_name}' stopped")
            elif action == "setup":
                self.success(f"VM '{vm_name}' ready at {vm_dir}")
            elif action == "status":
                self.success("VM status retrieved")
        else:
            self.error(f"Action '{action}' failed")

        t = Table(title="Android Tamer VM", border_style="green")
        t.add_column("Item", style="bold yellow")
        t.add_column("Value", style="white")
        vi = result.get("vm_info", {})
        t.add_row("Action", action)
        t.add_row("VM Name", vi.get("name", vm_name))
        t.add_row("Resources", f"{vi.get('ram_gb', ram)}GB / {vi.get('cpu_cores', cpu)} cores")
        t.add_row("USB", "Enabled" if vi.get("usb_passthrough", usb) else "Disabled")
        t.add_row("Status", result.get("status", "unknown"))
        self.console.print(t)

        return result
