"""
User configuration manager for Nexora VPN CLI.
Stored at ~/.config/nexora/config.json.
"""

import json
from pathlib import Path
from typing import Dict, Any, Optional

from .constants import (
    CONFIG_FILE,
    DEFAULT_SB_URL,
    DEFAULT_SB_KEY,
    DEFAULT_HTTP_PORT,
    DEFAULT_SOCKS_PORT,
)

DEFAULT_CONFIG: Dict[str, Any] = {
    "sb_url": DEFAULT_SB_URL,
    "sb_key": DEFAULT_SB_KEY,
    "routing_mode": "bypass_lan_iran",
    "block_ads": True,
    "stealth_fragment": True,
    "kill_switch": False,
    "auto_connect": False,
    "http_port": DEFAULT_HTTP_PORT,
    "socks_port": DEFAULT_SOCKS_PORT,
    "firefox_mode": "set",
    "last_server_id": "",
    "upstream_proxy": "",
    "upstream_proxy_on": False,
}

class ConfigManager:
    def __init__(self, config_file: Path = CONFIG_FILE):
        self.config_file = config_file
        self._data: Dict[str, Any] = {}
        self.load()

    def load(self) -> Dict[str, Any]:
        """Load configuration from disk, applying defaults for missing keys."""
        if not self.config_file.exists():
            self._data = dict(DEFAULT_CONFIG)
            self.save()
            return self._data

        try:
            with open(self.config_file, "r", encoding="utf-8") as f:
                loaded = json.load(f)
                self._data = dict(DEFAULT_CONFIG)
                self._data.update(loaded)
        except Exception:
            self._data = dict(DEFAULT_CONFIG)
            self.save()

        return self._data

    def save(self):
        """Persist current settings to disk."""
        self.config_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self.config_file, "w", encoding="utf-8") as f:
            json.dump(self._data, f, indent=2)

    def get(self, key: str, default: Any = None) -> Any:
        return self._data.get(key, default if default is not None else DEFAULT_CONFIG.get(key))

    def set(self, key: str, value: Any):
        self._data[key] = value
        self.save()

    def reset(self):
        """Reset configuration to initial default values."""
        self._data = dict(DEFAULT_CONFIG)
        self.save()

    def to_dict(self) -> Dict[str, Any]:
        return dict(self._data)
