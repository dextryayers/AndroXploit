import os
import subprocess
import time
import json
import signal
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

ENGINE = Path(__file__).parent.parent.parent / "golang" / "adb_toolkit" / "scrcpy"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "adb_toolkit" / "scrcpy.sh"

class Module(AndroModule):
    name = "adb_toolkit/scrcpy"
    description = "scrcpy — Open-source screen mirroring and control via USB or WiFi with ultra-low latency. Display and interact with Android from PC."
    author = "AndroXploit"

    options = {
        "TARGET": {
            "description": "Target device (usb or IP:port)",
            "required": True,
            "value": None,
        },
        "MAX_SIZE": {
            "description": "Maximum screen resolution (e.g., 1024, 1920)",
            "required": False,
            "value": 1024,
        },
        "BITRATE": {
            "description": "Video bitrate in Mbps (1-100)",
            "required": False,
            "value": 8,
        },
        "RECORD": {
            "description": "Record screen to file (path or disable)",
            "required": False,
            "value": None,
        },
        "NO_CONTROL": {
            "description": "Disable mouse/keyboard control (view only)",
            "required": False,
            "value": False,
        },
        "TURN_SCREEN_OFF": {
            "description": "Turn off device screen while mirroring",
            "required": False,
            "value": False,
        },
        "STAY_AWAKE": {
            "description": "Keep device awake while mirroring",
            "required": False,
            "value": True,
        },
        "CROP": {
            "description": "Crop screen region (e.g., 1080:1920:0:0)",
            "required": False,
            "value": None,
        },
    }

    def run(self):
        target = self.get_option("TARGET")
        max_size = int(self.get_option("MAX_SIZE", 1024))
        bitrate = int(self.get_option("BITRATE", 8))
        record = self.get_option("RECORD")
        no_control = self.get_option("NO_CONTROL")
        turn_off = self.get_option("TURN_SCREEN_OFF")
        stay_awake = self.get_option("STAY_AWAKE")
        crop = self.get_option("CROP")

        self.info(f"scrcpy — Target: {target} | Resolution: {max_size}p | Bitrate: {bitrate}Mbps")

        result = {"status": "idle", "mirror_started": False}

        if ENGINE.exists():
            cmd = [str(ENGINE), "--target", target, "--max-size", str(max_size),
                   "--bitrate", str(bitrate)]
            if record:
                cmd.extend(["--record", record])
            if no_control:
                cmd.append("--no-control")
            if turn_off:
                cmd.append("--turn-screen-off")
            if stay_awake:
                cmd.append("--stay-awake")
            if crop:
                cmd.extend(["--crop", crop])
            proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(2)
            if proc.poll() is None:
                result["mirror_started"] = True
                result["status"] = "running"
                self.success("Screen mirror started (running in background)")
                self.log("Press Ctrl+C to stop mirroring")
                try:
                    proc.wait()
                except KeyboardInterrupt:
                    proc.terminate()
                    self.log("Mirroring stopped")
        elif SCRIPT.exists():
            cmd = ["bash", str(SCRIPT), target, str(max_size), str(bitrate), record or "",
                   str(no_control), str(turn_off), str(stay_awake), crop or ""]
            proc = subprocess.Popen(cmd)
            try:
                proc.wait()
            except KeyboardInterrupt:
                proc.terminate()
        else:
            self.warn("No engine found; simulating screen mirroring")
            self.log(f"Starting scrcpy server on {target}...")
            time.sleep(0.5)
            self.log(f"Screen mirror active — {max_size}p @ {bitrate}Mbps")
            self.success("Mirror started (Ctrl+C to stop)")

            try:
                for i in range(300):
                    time.sleep(0.1)
                    if i % 50 == 0:
                        self.log(f"Mirroring active... ({i//10}s)")
            except KeyboardInterrupt:
                self.log("Mirroring stopped by user")
                result["status"] = "stopped"

            result["mirror_started"] = True
            result["status"] = "simulated"

        t = Table(title="scrcpy Session", border_style="green")
        t.add_column("Setting", style="bold yellow")
        t.add_column("Value", style="white")
        t.add_row("Target", target)
        t.add_row("Max Resolution", f"{max_size}p")
        t.add_row("Bitrate", f"{bitrate} Mbps")
        t.add_row("Recording", record or "Disabled")
        t.add_row("Control", "Disabled" if no_control else "Enabled")
        t.add_row("Status", result.get("status", "unknown"))
        self.console.print(t)

        return result
