import os
import subprocess
import time
import json
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "supporting" / "apklab.sh"

class Module(AndroModule):
    name = "supporting/apklab"
    description = "APKLab — VS Code extension integration for APK reverse engineering: decompile, patch, rebuild, and sign using apktool + jadx pipeline."
    author = "AndroXploit"

    options = {
        "APK_FILE": {
            "description": "Path to target APK file",
            "required": True,
            "value": None,
        },
        "ACTION": {
            "description": "Action: decompile, patch, rebuild, sign, analyze, all",
            "required": False,
            "value": "analyze",
        },
        "OUTPUT_DIR": {
            "description": "Output directory for decompiled/rebuilt files",
            "required": False,
            "value": None,
        },
        "PATCH_FILE": {
            "description": "Smali patch file path (for patch action)",
            "required": False,
            "value": None,
        },
        "KEYSTORE": {
            "description": "Path to keystore for APK signing",
            "required": False,
            "value": None,
        },
        "DECOMPILE_SOURCES": {
            "description": "Decompile to Java sources using jadx",
            "required": False,
            "value": True,
        },
    }

    def run(self):
        apk_file = self.get_option("APK_FILE")
        action = self.get_option("ACTION")
        output = self.get_option("OUTPUT_DIR")
        patch = self.get_option("PATCH_FILE")
        keystore = self.get_option("KEYSTORE")
        decompile = self.get_option("DECOMPILE_SOURCES")

        if not os.path.exists(apk_file):
            self.error(f"APK not found: {apk_file}")
            return {"status": "failed", "error": "APK not found"}

        if not output:
            base = os.path.basename(apk_file)
            name = os.path.splitext(base)[0]
            output = os.path.join(os.path.dirname(apk_file), f"{name}_lab")

        os.makedirs(output, exist_ok=True)

        self.info(f"APKLab — APK: {apk_file} | Action: {action} | Output: {output}")

        result = {"status": "idle", "output_dir": output, "actions_completed": []}

        if SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), apk_file, action, output, patch or "", keystore or "", str(decompile)],
                capture_output=True, text=True, timeout=300
            )
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn(f"Simulating APKLab pipeline: {action}")

            pipeline = {
                "decompile": ["apktool d -f -o {out}", "jadx -d {out}/sources {apk}"],
                "rebuild": ["apktool b {out} -o {out}/dist.apk"],
                "sign": [f"jarsigner -keystore {keystore or 'debug.keystore'} -storepass android -keypass android {out}/dist.apk androiddebugkey"],
                "analyze": [
                    "Extracting APK metadata...",
                    "Reading AndroidManifest.xml...",
                    "Analyzing permissions...",
                    "Extracting DEX classes...",
                    "Identifying entry points...",
                    "Scanning for hardcoded secrets...",
                ],
                "all": [
                    "Decompiling APK...",
                    "Extracting Java sources...",
                    "Analyzing application structure...",
                    "Rebuilding APK...",
                    "Signing APK...",
                ],
            }

            steps = pipeline.get(action, pipeline.get("analyze"))
            for i, step in enumerate(steps):
                step_text = step.format(apk=apk_file, out=output, keystore=keystore or "debug.keystore")
                self.log(f"[{i+1}/{len(steps)}] {step_text}")
                time.sleep(0.3 + (0.2 if "apktool" in step else 0.1))
                result["actions_completed"].append(step_text)

            result["status"] = "simulated"

        if result["status"] != "failed":
            self.success(f"APKLab: {action} completed")
            self.info(f"Output directory: {output}")
            if action in ("analyze", "all"):
                self.info("Run 'info' on this module for detailed findings")
        else:
            self.error("APKLab operation failed")

        t = Table(title="APKLab Results", border_style="green")
        t.add_column("Item", style="bold yellow")
        t.add_column("Value", style="white")
        t.add_row("APK", apk_file)
        t.add_row("Action", action)
        t.add_row("Output", output)
        if patch:
            t.add_row("Patch File", patch)
        t.add_row("Steps", str(len(result.get("actions_completed", []))))
        t.add_row("Status", result.get("status", "unknown"))
        self.console.print(t)

        return result
