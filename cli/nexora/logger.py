"""
Logging facility for Nexora VPN CLI.
Records sanitized technical messages, timestamps, and error levels.
Never stores tokens, passwords, or sensitive keys.
"""

import os
import time
from pathlib import Path
from typing import List, Optional

from .constants import LOG_FILE
from .security import sanitize_text

class NexoraLogger:
    def __init__(self, log_file: Path = LOG_FILE):
        self.log_file = log_file

    def _write_entry(self, level: str, message: str):
        self.log_file.parent.mkdir(parents=True, exist_ok=True)
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        clean_msg = sanitize_text(message.strip())
        line = f"[{timestamp}] [{level.upper()}] {clean_msg}\n"
        try:
            with open(self.log_file, "a", encoding="utf-8") as f:
                f.write(line)
        except Exception:
            pass

    def info(self, message: str):
        self._write_entry("INFO", message)

    def warning(self, message: str):
        self._write_entry("WARN", message)

    def error(self, message: str):
        self._write_entry("ERROR", message)

    def read_logs(self, limit: int = 50) -> List[str]:
        if not self.log_file.exists():
            return []
        try:
            with open(self.log_file, "r", encoding="utf-8") as f:
                lines = f.readlines()
                return [line.strip() for line in lines[-limit:]]
        except Exception:
            return []

logger = NexoraLogger()
