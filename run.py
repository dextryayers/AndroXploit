#!/usr/bin/env python3
import os
import sys
import subprocess
import time

project_root = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, project_root)

VENV_DIR = os.path.join(project_root, ".venv")
VENV_PYTHON = os.path.join(VENV_DIR, "bin", "python3")


def is_in_venv():
    return sys.prefix != sys.base_prefix or os.environ.get("VIRTUAL_ENV")


def ensure_deps():
    missing = []
    for mod in ["rich", "prompt_toolkit"]:
        try:
            __import__(mod)
        except ImportError:
            missing.append(mod)
    if missing:
        if is_in_venv():
            subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet"] + missing)
        elif os.path.exists(VENV_PYTHON):
            print("[!] Activate venv: source .venv/bin/activate && python3 run.py")
            sys.exit(1)
        else:
            subprocess.check_call([sys.executable, "-m", "venv", VENV_DIR])
            subprocess.check_call([VENV_PYTHON, "-m", "pip", "install", "--upgrade", "pip", "--quiet"])
            subprocess.check_call([VENV_PYTHON, "-m", "pip", "install", "-r",
                                   os.path.join(project_root, "requirements.txt"), "--quiet"])
            print("[+] Setup complete. Run: python3 run.py")
            sys.exit(0)


def auto_activate_venv():
    if not is_in_venv() and os.path.exists(VENV_PYTHON):
        os.execv(VENV_PYTHON, [VENV_PYTHON] + sys.argv)


def main():
    auto_activate_venv()
    ensure_deps()

    from core.animator import UFOAnimator
    UFOAnimator().fly()

    from core.cli import AndroXploitCLI
    cli = AndroXploitCLI()
    cli.run()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[!] Interrupted. Exiting.")
        sys.exit(0)
    except Exception as e:
        try:
            from rich.console import Console
            Console().print(f"\n[bold red][!] Fatal: {e}")
        except ImportError:
            print(f"\n[!] Fatal: {e}")
        sys.exit(1)
