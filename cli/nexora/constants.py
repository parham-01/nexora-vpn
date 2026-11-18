"""
Constants and default configurations for Nexora VPN CLI.
"""

import os
from pathlib import Path

# Exit codes requested in specification
EXIT_SUCCESS = 0
EXIT_GENERAL_ERROR = 1
EXIT_INVALID_INPUT = 2
EXIT_AUTH_FAILED = 3
EXIT_CONNECTION_ERROR = 4
EXIT_INSUFFICIENT_PRIVILEGES = 5
EXIT_SERVICE_UNAVAILABLE = 6

# XDG Paths
HOME = Path.home()
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "nexora"
XDG_DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local" / "share")) / "nexora"
XDG_STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local" / "state")) / "nexora"

runtime_base = os.environ.get("XDG_RUNTIME_DIR")
if runtime_base and os.path.exists(runtime_base):
    XDG_RUNTIME_DIR = Path(runtime_base) / "nexora"
else:
    XDG_RUNTIME_DIR = XDG_STATE_HOME / "run"

# Firefox Core directory
FIREFOX_DATA_DIR = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local" / "share")) / "nexora-vpn" / "firefox-core"

# File locations
CONFIG_FILE = XDG_CONFIG_HOME / "config.json"
CREDENTIALS_FILE = XDG_CONFIG_HOME / "credentials.json"
SERVERS_CACHE_FILE = XDG_DATA_HOME / "servers.json"
VPN_STATE_FILE = XDG_STATE_HOME / "vpn_state.json"
PID_FILE = XDG_RUNTIME_DIR / "vpn.pid"
LOCK_FILE = XDG_RUNTIME_DIR / "nexora.lock"
LOG_FILE = XDG_DATA_HOME / "nexora.log"
GENERATED_XRAY_CONFIG = XDG_RUNTIME_DIR / "generated_xray.json"

# Network Defaults
DEFAULT_SB_URL = "https://xvisvcpvfgzbkjrmhvke.supabase.co"
DEFAULT_SB_KEY = ""
DEFAULT_HTTP_PORT = 10809
DEFAULT_SOCKS_PORT = 10808
DEFAULT_API_PORT = 10085
DEFAULT_FIREFOX_PORT = 10820

# Probing URLs
CONNECTIVITY_PROBE_URLS = [
    "http://cp.cloudflare.com/generate_204",
    "https://www.gstatic.com/generate_204"
]

IP_INFO_URLS = [
    "https://ipwho.is/",
    "https://ipapi.co/json/"
]
