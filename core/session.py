import json
import os
import uuid
from datetime import datetime

CONFIG_DIR = os.path.expanduser("~/.androxploit")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
HISTORY_FILE = os.path.join(CONFIG_DIR, "history.json")
SESSIONS_DIR = os.path.join(CONFIG_DIR, "sessions")


class SessionManager:
    def __init__(self):
        self._ensure_dirs()
        self.config = self._load_config()
        self.current_session = self._create_session()

    def _ensure_dirs(self):
        os.makedirs(CONFIG_DIR, exist_ok=True)
        os.makedirs(SESSIONS_DIR, exist_ok=True)

    def _load_config(self):
        defaults = {
            "lhost": "0.0.0.0",
            "lport": 4444,
            "adb_path": "adb",
            "output_dir": "output/reports",
            "log_level": "info",
            "theme": "default",
            "auto_report": False,
        }
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE) as f:
                config = json.load(f)
                defaults.update(config)
        else:
            self._save_config(defaults)
        return defaults

    def _save_config(self, config=None):
        with open(CONFIG_FILE, "w") as f:
            json.dump(config or self.config, f, indent=2)

    def _create_session(self):
        session = {
            "id": uuid.uuid4().hex[:8],
            "started": datetime.now().isoformat(),
            "module_history": [],
            "results": [],
            "target": None,
        }
        return session

    def save_session(self):
        sid = self.current_session["id"]
        path = os.path.join(SESSIONS_DIR, f"session_{sid}.json")
        with open(path, "w") as f:
            json.dump(self.current_session, f, indent=2)

    def log_result(self, module_name, status, data=None):
        entry = {
            "timestamp": datetime.now().isoformat(),
            "module": module_name,
            "status": status,
            "data": data,
        }
        self.current_session["results"].append(entry)
        self.save_session()

    def set_global(self, key, value):
        self.config[key] = value
        self._save_config()

    def get_global(self, key):
        return self.config.get(key)

    def list_sessions(self):
        sessions = []
        if os.path.isdir(SESSIONS_DIR):
            for fname in sorted(os.listdir(SESSIONS_DIR)):
                if fname.startswith("session_"):
                    path = os.path.join(SESSIONS_DIR, fname)
                    with open(path) as f:
                        sessions.append(json.load(f))
        return sessions

    def load_session(self, session_id):
        path = os.path.join(SESSIONS_DIR, f"session_{session_id}.json")
        if os.path.exists(path):
            with open(path) as f:
                self.current_session = json.load(f)
            return True
        return False
