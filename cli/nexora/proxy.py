"""
Linux system proxy settings management.
Supports GNOME (gsettings), KDE (kwriteconfig), and terminal environment files.
Works gracefully in headless / SSH environments without X11/Wayland.
"""

import os
import shutil
import subprocess
from pathlib import Path
from typing import Optional

from .constants import XDG_CONFIG_HOME, DEFAULT_HTTP_PORT, DEFAULT_SOCKS_PORT

ENV_PROXY_FILE = XDG_CONFIG_HOME / "env_proxy.sh"

def _run_cmd(cmd: list) -> bool:
    exe = shutil.which(cmd[0])
    if not exe:
        return False
    try:
        subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
            check=False
        )
        return True
    except Exception:
        return False

def set_linux_proxy(enable: bool, http_port: int = DEFAULT_HTTP_PORT, socks_port: int = DEFAULT_SOCKS_PORT):
    """
    Configure Linux desktop system proxy and environment script.
    """
    # 1. GNOME / GTK settings via gsettings
    if shutil.which("gsettings"):
        g = "org.gnome.system.proxy"
        if enable:
            for proto in ("http", "https"):
                _run_cmd(["gsettings", "set", f"{g}.{proto}", "host", "127.0.0.1"])
                _run_cmd(["gsettings", "set", f"{g}.{proto}", "port", str(http_port)])
            _run_cmd(["gsettings", "set", f"{g}.socks", "host", "127.0.0.1"])
            _run_cmd(["gsettings", "set", f"{g}.socks", "port", str(socks_port)])
            _run_cmd(["gsettings", "set", g, "mode", "manual"])
        else:
            _run_cmd(["gsettings", "set", g, "mode", "none"])

    # 2. KDE Plasma settings via kwriteconfig
    for kw in ("kwriteconfig6", "kwriteconfig5"):
        if shutil.which(kw):
            grp = "Proxy Settings"
            _run_cmd([kw, "--file", "kioslaverc", "--group", grp, "--key", "ProxyType", "1" if enable else "0"])
            if enable:
                _run_cmd([kw, "--file", "kioslaverc", "--group", grp, "--key", "httpProxy", f"http://127.0.0.1 {http_port}"])
                _run_cmd([kw, "--file", "kioslaverc", "--group", grp, "--key", "httpsProxy", f"http://127.0.0.1 {http_port}"])
                _run_cmd([kw, "--file", "kioslaverc", "--group", grp, "--key", "socksProxy", f"socks5://127.0.0.1 {socks_port}"])

    # 3. Terminal environment file for bash/zsh
    ENV_PROXY_FILE.parent.mkdir(parents=True, exist_ok=True)
    if enable:
        content = (
            f"# Nexora VPN terminal proxy environment\n"
            f"export HTTP_PROXY=\"http://127.0.0.1:{http_port}\"\n"
            f"export HTTPS_PROXY=\"http://127.0.0.1:{http_port}\"\n"
            f"export http_proxy=\"http://127.0.0.1:{http_port}\"\n"
            f"export https_proxy=\"http://127.0.0.1:{http_port}\"\n"
            f"export ALL_PROXY=\"socks5://127.0.0.1:{socks_port}\"\n"
            f"export all_proxy=\"socks5://127.0.0.1:{socks_port}\"\n"
            f"export NO_PROXY=\"localhost,127.0.0.1,::1\"\n"
        )
    else:
        content = (
            f"# Nexora VPN terminal proxy unset\n"
            f"unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy\n"
        )

    try:
        with open(ENV_PROXY_FILE, "w", encoding="utf-8") as f:
            f.write(content)
    except Exception:
        pass
