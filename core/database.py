import sqlite3
import json
import os
from datetime import datetime

DB_DIR = os.path.expanduser("~/.androxploit/db")
DB_PATH = os.path.join(DB_DIR, "androxploit.db")


class Database:
    def __init__(self, db_path=None):
        self.db_path = db_path or DB_PATH
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self._init_tables()

    def _init_tables(self):
        self.conn.executescript("""
            CREATE TABLE IF NOT EXISTS findings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                module_name TEXT NOT NULL,
                finding_type TEXT,
                severity TEXT DEFAULT 'info',
                title TEXT,
                description TEXT,
                data_json TEXT,
                timestamp TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS targets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                target TEXT NOT NULL,
                target_type TEXT DEFAULT 'apk',
                added_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                content TEXT,
                created_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_findings_session
                ON findings(session_id);
            CREATE INDEX IF NOT EXISTS idx_findings_severity
                ON findings(severity);
        """)
        self.conn.commit()

    def add_finding(self, session_id, module_name, finding_type, severity, title, description, data=None):
        self.conn.execute(
            """INSERT INTO findings (session_id, module_name, finding_type, severity, title, description, data_json, timestamp)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (session_id, module_name, finding_type, severity, title, description,
             json.dumps(data) if data else None, datetime.now().isoformat()),
        )
        self.conn.commit()

    def get_findings(self, session_id=None, severity=None):
        query = "SELECT * FROM findings WHERE 1=1"
        params = []
        if session_id:
            query += " AND session_id = ?"
            params.append(session_id)
        if severity:
            query += " AND severity = ?"
            params.append(severity)
        query += " ORDER BY timestamp DESC"
        return [dict(row) for row in self.conn.execute(query, params).fetchall()]

    def add_target(self, session_id, target, target_type="apk"):
        self.conn.execute(
            "INSERT INTO targets (session_id, target, target_type, added_at) VALUES (?, ?, ?, ?)",
            (session_id, target, target_type, datetime.now().isoformat()),
        )
        self.conn.commit()

    def add_note(self, session_id, content):
        self.conn.execute(
            "INSERT INTO notes (session_id, content, created_at) VALUES (?, ?, ?)",
            (session_id, content, datetime.now().isoformat()),
        )
        self.conn.commit()

    def get_summary(self, session_id):
        total = self.conn.execute(
            "SELECT COUNT(*) as c FROM findings WHERE session_id = ?", (session_id,)
        ).fetchone()["c"]
        critical = self.conn.execute(
            "SELECT COUNT(*) as c FROM findings WHERE session_id = ? AND severity = 'critical'", (session_id,)
        ).fetchone()["c"]
        high = self.conn.execute(
            "SELECT COUNT(*) as c FROM findings WHERE session_id = ? AND severity = 'high'", (session_id,)
        ).fetchone()["c"]
        medium = self.conn.execute(
            "SELECT COUNT(*) as c FROM findings WHERE session_id = ? AND severity = 'medium'", (session_id,)
        ).fetchone()["c"]
        low = self.conn.execute(
            "SELECT COUNT(*) as c FROM findings WHERE session_id = ? AND severity = 'low'", (session_id,)
        ).fetchone()["c"]
        return {"total": total, "critical": critical, "high": high, "medium": medium, "low": low}

    def close(self):
        self.conn.close()
