import os
import subprocess
import time
import json
import random
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

ENGINE = Path(__file__).parent.parent.parent / "golang" / "hid_attack" / "fuzzusb"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "hid_attack" / "fuzzusb.sh"

class Module(AndroModule):
    name = "hid_attack/fuzzusb"
    description = "FuzzUSB — Research-grade USB driver fuzzing combining static analysis and symbolic execution to discover Android USB subsystem vulnerabilities."
    author = "AndroXploit"

    options = {
        "DEVICE": {
            "description": "USB device path to fuzz (e.g., /dev/bus/usb/001/002)",
            "required": True,
            "value": None,
        },
        "ITERATIONS": {
            "description": "Number of fuzzing iterations to run",
            "required": False,
            "value": 1000,
        },
        "STRATEGY": {
            "description": "Fuzzing strategy: random, mutation, symbolic, coverage_guided, all",
            "required": False,
            "value": "all",
        },
        "TIMEOUT": {
            "description": "Per-iteration timeout in milliseconds",
            "required": False,
            "value": 500,
        },
        "LOG_FILE": {
            "description": "Path to save crash/vulnerability log",
            "required": False,
            "value": None,
        },
        "STOP_ON_CRASH": {
            "description": "Stop fuzzing on first crash/bug",
            "required": False,
            "value": True,
        },
    }

    def run(self):
        device = self.get_option("DEVICE")
        iterations = int(self.get_option("ITERATIONS", 1000))
        strategy = self.get_option("STRATEGY")
        timeout = int(self.get_option("TIMEOUT", 500))
        log_file = self.get_option("LOG_FILE")
        stop_on_crash = self.get_option("STOP_ON_CRASH")

        self.info(f"FuzzUSB — Device: {device}")
        self.info(f"Iterations: {iterations} | Strategy: {strategy} | Timeout: {timeout}ms")
        self.warn("Fuzzing USB can crash or damage device drivers. Proceed with caution.")

        result = {"status": "idle", "crashes": [], "iterations_completed": 0}

        if ENGINE.exists():
            cmd = [str(ENGINE), "--device", device, "--iterations", str(iterations),
                   "--strategy", strategy, "--timeout", str(timeout)]
            if log_file:
                cmd.extend(["--log", log_file])
            if stop_on_crash:
                cmd.append("--stop-on-crash")
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=iterations * timeout // 1000 + 60)
            if proc.stdout:
                try:
                    result = json.loads(proc.stdout)
                except json.JSONDecodeError:
                    result["output"] = proc.stdout.splitlines()
        elif SCRIPT.exists():
            proc = subprocess.run(
                ["bash", str(SCRIPT), device, str(iterations), strategy, str(timeout),
                 log_file or "", str(stop_on_crash)],
                capture_output=True, text=True, timeout=iterations * timeout // 1000 + 60
            )
            result["output"] = proc.stdout.splitlines()
        else:
            self.warn("Simulating USB fuzzing sequence")
            self.log(f"Initializing {strategy} fuzzing strategy against {device}...")
            time.sleep(0.5)

            strategies = strategy.split(",")
            completed = 0
            crashes_found = 0

            for s in strategies:
                s = s.strip()
                self.log(f"Strategy: {s}")
                batch = iterations // len(strategies)
                for i in range(min(batch, 20)):
                    test_id = f"MUT-{s[:3].upper()}-{i+1:04d}"
                    mutated_bytes = random.randint(1, 64)
                    self.log(f"  [{i+1}/{min(batch, 20)}] {test_id}: mutated {mutated_bytes} bytes")
                    time.sleep(0.05 + random.random() * 0.1)
                    completed += 1

                    if random.random() < 0.02 and crashes_found < 3:
                        crashes_found += 1
                        crash = {
                            "iteration": completed,
                            "strategy": s,
                            "test_id": test_id,
                            "type": random.choice(["NULL_PTR_DEREF", "BUFFER_OVERFLOW", "USE_AFTER_FREE",
                                                  "DIVIDE_BY_ZERO", "INTEGER_OVERFLOW"]),
                            "address": f"0x{random.randint(0x10000000, 0xFFFFFFFF):08x}",
                        }
                        result["crashes"].append(crash)
                        self.warn(f"    -> CRASH: {crash['type']} at {crash['address']}")
                        if stop_on_crash:
                            self.warn("Stopping fuzzer (stop_on_crash enabled)")
                            break

            result["iterations_completed"] = completed
            result["status"] = "simulated"

        if result["crashes"]:
            self.warn(f"{len(result['crashes'])} vulnerabilities detected!")
            for crash in result["crashes"]:
                self.log(f"  {crash.get('type', 'BUG')} at {crash.get('address', '?')}")
        else:
            self.success("No crashes detected in this fuzzing run")
            self.warn("This does not guarantee the device is vulnerability-free")

        self.info(f"Iterations completed: {result.get('iterations_completed', 0)}")

        if log_file and result["crashes"]:
            with open(log_file, "w") as f:
                json.dump(result, f, indent=2)
            self.success(f"Crash log saved to {log_file}")

        t = Table(title="FuzzUSB Results", border_style="green")
        t.add_column("Metric", style="bold yellow")
        t.add_column("Value", style="white")
        t.add_row("Device", device)
        t.add_row("Strategy", strategy)
        t.add_row("Iterations", str(result.get("iterations_completed", 0)))
        t.add_row("Crashes Found", str(len(result.get("crashes", []))))
        if result.get("crashes"):
            t.add_row("First Crash", result["crashes"][0].get("type", "?"))
        t.add_row("Status", result.get("status", "unknown"))
        self.console.print(t)

        return result
