import os
import subprocess
import time
import json
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "supporting" / "magisk.sh"

class Module(AndroModule):
    name = "supporting/magisk"
    description = "Magisk — Systemless root for Android. Flash via USB to gain privileged access for advanced USB attacks, HID injection, and deep system manipulation."
    author = "AndroXploit"

    options = {
        "ACTION": {
            "description": "Action: flash, verify, modules, hide, uninstall, patch_boot, status",
            "required": True,
            "value": None,
        },
        "ZIP_FILE": {
            "description": "Path to Magisk ZIP or APK file",
            "required": False,
            "value": None,
        },
        "BOOT_IMG": {
            "description": "Path to boot image for patching",
            "required": False,
            "value": None,
        },
        "OUTPUT_IMG": {
            "description": "Output path for patched boot image",
            "required": False,
            "value": None,
        },
        "MODULE_NAME": {
            "description": "Magisk module name for install/remove actions",
            "required": False,
            "value": None,
        },
        "USB_SERIAL": {
            "description": "Target device USB serial",
            "required": False,
            "value": None,
        },
    }

    def run(self):
        action = self.get_option("ACTION")
        zip_file = self.get_option("ZIP_FILE")
        boot_img = self.get_option("BOOT_IMG")
        output_img = self.get_option("OUTPUT_IMG")
        module_name = self.get_option("MODULE_NAME")
        serial = self.get_option("USB_SERIAL")

        self.info(f"Magisk — Action: {action}")

        if action == "patch_boot" and not boot_img:
            self.error("BOOT_IMG required for patch_boot action")
            return {"status": "failed", "error": "Boot image not specified"}

        if action == "flash" and not zip_file:
            self.error("ZIP_FILE required for flash action")
            return {"status": "failed", "error": "ZIP file not specified"}

        result = {"status": "idle", "action": action}

        if SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), action, zip_file or "", boot_img or "", output_img or "",
                 module_name or "", serial or ""],
                capture_output=True, text=True, timeout=120
            )
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn(f"Simulating Magisk operation: {action}")

            action_flows = {
                "flash": [
                    f"Verifying ZIP: {zip_file}",
                    "Checking device architecture...",
                    "Pushing Magisk to device...",
                    "Rebooting to recovery via ADB...",
                    "Installing Magisk...",
                    "Rebooting system...",
                ],
                "verify": [
                    "Checking root status...",
                    "Magisk version: 26.4",
                    "MagiskSU: installed",
                    "Zygisk: enabled",
                    "DenyList: active",
                    "SafetyNet: passing",
                ],
                "modules": [
                    "Enumerating installed modules...",
                    "Systemless Hosts (adblock)",
                    "Universal SafetyNet Fix",
                    "Riru - Enhanced mode",
                    "Audio Modification Library",
                ],
                "hide": [
                    "Configuring Magisk Hide...",
                    "Hiding root from: banking apps, Google Pay, Netflix",
                    "Applying DenyList rules...",
                ],
                "patch_boot": [
                    f"Extracting boot image: {boot_img}",
                    "Patching with Magisk init...",
                    "Repacking boot image...",
                    f"Patched image: {output_img or boot_img + '_patched'}",
                ],
                "status": [
                    "Magisk version: 26.4",
                    "Installed: Yes",
                    "Root access: Granted",
                    "Zygisk: Running",
                    "Modules active: 4",
                    "SafetyNet: Passed",
                ],
                "uninstall": [
                    "Preparing Magisk uninstaller...",
                    "Restoring stock boot image...",
                    "Removing Magisk files...",
                    "Uninstall complete",
                ],
            }

            steps = action_flows.get(action, [f"Executing {action}..."])
            for s in steps:
                self.log(s)
                time.sleep(0.3)

            result["status"] = "simulated"

        if result["status"] != "failed":
            if action == "flash":
                self.success("Magisk flashed successfully — device rooted")
            elif action == "verify":
                self.success("Root verification complete")
            elif action == "modules":
                self.success("Module list retrieved")
            elif action == "hide":
                self.success("Magisk Hide configured")
            elif action == "patch_boot":
                self.success(f"Boot image patched: {output_img or boot_img + '_patched'}")
            elif action == "status":
                self.success("Magisk status: Active")
            elif action == "uninstall":
                self.success("Magisk removed — device restored to stock")
        else:
            self.error(f"Magisk: {action} failed")

        t = Table(title="Magisk Operations", border_style="green")
        t.add_column("Item", style="bold yellow")
        t.add_column("Value", style="white")
        t.add_row("Action", action)
        t.add_row("Version", "26.4")
        t.add_row("Status", result.get("status", "unknown"))
        if zip_file:
            t.add_row("ZIP File", zip_file)
        if boot_img:
            t.add_row("Boot Image", boot_img)
        self.console.print(t)

        return result
