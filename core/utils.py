import os
import re
import subprocess
import shlex
from pathlib import Path


def run_command(cmd, shell=False, timeout=None, capture_output=True):
    if isinstance(cmd, str) and not shell:
        cmd = shlex.split(cmd)
    try:
        result = subprocess.run(
            cmd,
            shell=shell,
            capture_output=capture_output,
            text=True,
            timeout=timeout,
        )
        return {
            "stdout": result.stdout,
            "stderr": result.stderr,
            "returncode": result.returncode,
            "success": result.returncode == 0,
        }
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": "Timeout expired", "returncode": -1, "success": False}
    except FileNotFoundError:
        return {"stdout": "", "stderr": "Command not found", "returncode": -1, "success": False}


def run_go_binary(binary_name, args=None):
    bin_path = Path(__file__).parent.parent / "bin" / binary_name
    if not bin_path.exists():
        return {"stdout": "", "stderr": f"Go binary not found: {binary_name}", "returncode": -1, "success": False}
    cmd = [str(bin_path)] + (args or [])
    return run_command(cmd)


def run_bash_script(script_name, args=None):
    script_path = Path(__file__).parent.parent / "scripts" / script_name
    if not script_path.exists():
        return {"stdout": "", "stderr": f"Script not found: {script_name}", "returncode": -1, "success": False}
    os.chmod(script_path, 0o755)
    cmd = ["bash", str(script_path)] + (args or [])
    return run_command(cmd)


def flatten_dict(d, parent_key="", sep="_"):
    items = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend(flatten_dict(v, new_key, sep=sep).items())
        else:
            items.append((new_key, v))
    return dict(items)


def sanitize_filename(name):
    return re.sub(r"[^\w\-_. ]", "_", name)


def format_bytes(size):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024:
            return f"{size:.2f} {unit}"
        size /= 1024
    return f"{size:.2f} PB"


def extract_urls(text):
    return re.findall(r"https?://[^\s\"'<>]+", text or "")


def extract_emails(text):
    return re.findall(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}", text or "")


def extract_api_keys(text):
    patterns = {
        "AWS Key": r"AKIA[0-9A-Z]{16}",
        "Google API": r"AIza[0-9A-Za-z\-_]{35}",
        "GitHub Token": r"gh[pousr]_[A-Za-z0-9_]{36,}",
        "JWT Token": r"eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+",
        "Slack Token": r"xox[baprs]-[0-9a-zA-Z\-]{10,}",
        "Generic Secret": r"(?i)(?:api[_\-]?key|secret|token|password)\s*[:=]\s*[\"']?([A-Za-z0-9_\-./+=]{16,})",
    }
    results = {}
    for name, pattern in patterns.items():
        matches = re.findall(pattern, text or "")
        if matches:
            results[name] = matches
    return results
