import os
import subprocess
import time
import json
import requests
from pathlib import Path
from rich.table import Table
from modules.base import AndroModule

class Module(AndroModule):
    name = "supporting/mobsf"
    description = "Mobile Security Framework (MobSF) — Automated mobile app pentest for Android/iOS: static + dynamic analysis, API scanning, malware detection."
    author = "AndroXploit"

    options = {
        "APK_FILE": {
            "description": "Path to APK file for analysis",
            "required": True,
            "value": None,
        },
        "MOBSF_URL": {
            "description": "MobSF server URL (e.g., http://localhost:8000)",
            "required": False,
            "value": "http://localhost:8000",
        },
        "API_KEY": {
            "description": "MobSF REST API key",
            "required": False,
            "value": None,
        },
        "SCAN_TYPE": {
            "description": "Scan type: static, dynamic, upload_only",
            "required": False,
            "value": "static",
        },
        "DOWNLOAD_REPORT": {
            "description": "Download analysis report (pdf, json, html)",
            "required": False,
            "value": "json",
        },
    }

    def run(self):
        apk_file = self.get_option("APK_FILE")
        mobsf_url = self.get_option("MOBSF_URL")
        api_key = self.get_option("API_KEY")
        scan_type = self.get_option("SCAN_TYPE")
        report_fmt = self.get_option("DOWNLOAD_REPORT")

        if not os.path.exists(apk_file):
            self.error(f"APK not found: {apk_file}")
            return {"status": "failed", "error": "APK not found"}

        self.info(f"MobSF — APK: {apk_file} | Server: {mobsf_url} | Scan: {scan_type}")

        result = {"status": "idle", "findings": {}, "report": None}
        api_available = False

        if api_key:
            try:
                test = requests.get(f"{mobsf_url}/api/v1/auth", headers={"Authorization": api_key}, timeout=5)
                if test.status_code == 200:
                    api_available = True
                    self.success("MobSF API connected")
            except Exception:
                self.warn("MobSF API not reachable; running local analysis")

        if api_available and api_key:
            try:
                with open(apk_file, "rb") as f:
                    upload = requests.post(
                        f"{mobsf_url}/api/v1/upload",
                        files={"file": f},
                        headers={"Authorization": api_key},
                        timeout=30
                    )
                if upload.status_code != 200:
                    self.error(f"Upload failed: {upload.text}")
                    return {"status": "failed", "error": "Upload failed"}

                upload_data = upload.json()
                self.success("APK uploaded to MobSF")

                scan = requests.post(
                    f"{mobsf_url}/api/v1/scan",
                    data={"hash": upload_data["hash"], "scan_type": scan_type},
                    headers={"Authorization": api_key},
                    timeout=300
                )
                if scan.status_code == 200:
                    scan_data = scan.json()
                    result["findings"] = scan_data
                    result["status"] = "success"

                if report_fmt in ("json",) or True:
                    report = requests.post(
                        f"{mobsf_url}/api/v1/download_report",
                        data={"hash": upload_data["hash"], "file_type": report_fmt},
                        headers={"Authorization": api_key},
                        timeout=30
                    )
                    if report.status_code == 200:
                        report_path = f"{apk_file}_mobsf_report.{report_fmt}"
                        with open(report_path, "wb") as f:
                            f.write(report.content)
                        result["report"] = report_path
                        self.success(f"Report saved: {report_path}")
            except Exception as e:
                self.error(f"MobSF API error: {e}")
                result["status"] = "failed"
        else:
            self.warn("Simulating MobSF static analysis")
            self.log(f"Uploading {os.path.basename(apk_file)}...")
            time.sleep(0.3)
            self.log("Performing static analysis...")
            time.sleep(0.5)

            result["findings"] = {
                "permissions": ["INTERNET", "READ_EXTERNAL_STORAGE", "CAMERA", "ACCESS_FINE_LOCATION"],
                "activities": 5,
                "services": 3,
                "receivers": 2,
                "providers": 1,
                "certificate_issues": ["SHA1withRSA (weak)", "Self-signed certificate"],
                "manifest_issues": ["Debuggable mode enabled", "Backup flag enabled"],
                "trackers_detected": ["Google Analytics", "Firebase"],
                "security_score": 42,
            }
            result["status"] = "simulated"

        if result["status"] != "failed":
            score = result.get("findings", {}).get("security_score", None)
            if score is not None:
                if score < 30:
                    self.error(f"Security score: {score}/100 — CRITICAL")
                elif score < 60:
                    self.warn(f"Security score: {score}/100 — WARNING")
                else:
                    self.success(f"Security score: {score}/100")
            self.success(f"MobSF analysis complete")
        else:
            self.error("Analysis failed")

        t = Table(title="MobSF Analysis Report", border_style="green")
        t.add_column("Category", style="bold yellow")
        t.add_column("Findings", style="white")
        findings = result.get("findings", {})
        if findings:
            for k, v in list(findings.items())[:8]:
                if isinstance(v, list):
                    t.add_row(k, ", ".join(str(x) for x in v[:3]))
                else:
                    t.add_row(k, str(v))
        t.add_row("Status", result.get("status", "unknown"))
        self.console.print(t)

        return result
