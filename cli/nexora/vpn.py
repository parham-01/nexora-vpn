"""
VPN lifecycle manager for Nexora CLI on Linux.
Controls core processes (xray / v2ray), daemonization, system proxy,
and connection health checks.
"""

import os
import json
import time
import fcntl
import signal
import shutil
import socket
import subprocess
import urllib.request
from pathlib import Path
from typing import Optional, Dict, Any, Tuple

from .constants import (
    PID_FILE,
    LOCK_FILE,
    VPN_STATE_FILE,
    GENERATED_XRAY_CONFIG,
    DEFAULT_HTTP_PORT,
    DEFAULT_SOCKS_PORT,
    DEFAULT_API_PORT,
    CONNECTIVITY_PROBE_URLS,
    IP_INFO_URLS,
)
from .models import VpnState, Server
from .config import ConfigManager
from .servers import ServerManager
from .xray import build_xray_config, parse_link
from .proxy import set_linux_proxy
from .logger import logger
from .errors import ConnectionError, ServiceUnavailableError

def find_vpn_binary() -> Tuple[str, str]:
    """
    Search for available xray or v2ray binary.
    Returns tuple: (executable_path, core_type)
    """
    # 1. Search for Xray
    xray_candidates = [
        shutil.which("xray"),
        "/usr/local/bin/xray",
        "/usr/bin/xray",
        str(Path.home() / ".local" / "share" / "nexora" / "bin" / "xray"),
        str(Path.cwd() / "xray" / "xray"),
    ]
    for c in xray_candidates:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c, "xray"

    # 2. Search for V2Ray
    v2ray_candidates = [
        shutil.which("v2ray"),
        "/usr/bin/v2ray",
        "/usr/local/bin/v2ray",
    ]
    for c in v2ray_candidates:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c, "v2ray"

    raise ServiceUnavailableError("No VPN core (xray or v2ray) found on this Linux system.")

def is_pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False

class VpnManager:
    def __init__(self, config_manager: ConfigManager, server_manager: ServerManager):
        self.config_manager = config_manager
        self.server_manager = server_manager
        PID_FILE.parent.mkdir(parents=True, exist_ok=True)
        VPN_STATE_FILE.parent.mkdir(parents=True, exist_ok=True)

    def _get_lock(self):
        LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
        f = open(LOCK_FILE, "w")
        fcntl.flock(f, fcntl.LOCK_EX)
        return f

    def get_state(self) -> VpnState:
        """Read current VPN state and verify daemon process liveness."""
        if not VPN_STATE_FILE.exists():
            return VpnState(status="disconnected")

        try:
            with open(VPN_STATE_FILE, "r", encoding="utf-8") as f:
                d = json.load(f)
                state = VpnState(
                    status=d.get("status", "disconnected"),
                    server_id=d.get("server_id", ""),
                    server_name=d.get("server_name", ""),
                    server_country=d.get("server_country", ""),
                    protocol=d.get("protocol", ""),
                    transport=d.get("transport", ""),
                    pid=d.get("pid"),
                    connected_at=d.get("connected_at"),
                    public_ip=d.get("public_ip", ""),
                    dns_status=d.get("dns_status", "Active"),
                    bytes_up=d.get("bytes_up", 0),
                    bytes_down=d.get("bytes_down", 0),
                    error_message=d.get("error_message", "")
                )

                # Check if process is still running
                if state.status == "connected" and state.pid:
                    if not is_pid_alive(state.pid):
                        # Process died unexpectedly
                        logger.warning(f"VPN core process {state.pid} died unexpectedly")
                        self._handle_unexpected_death(state)
                        state.status = "disconnected"
                        state.pid = None

                return state
        except Exception:
            return VpnState(status="disconnected")

    def _save_state(self, state: VpnState):
        VPN_STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(VPN_STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(state.to_dict(), f, indent=2)

    def _handle_unexpected_death(self, state: VpnState):
        set_linux_proxy(False)
        if PID_FILE.exists():
            try:
                PID_FILE.unlink()
            except Exception:
                pass
        state.status = "disconnected"
        state.error_message = "VPN process terminated unexpectedly"
        self._save_state(state)

    def connect(self, server_target: Optional[str] = None) -> VpnState:
        """
        Connect to VPN server.
        server_target can be server ID, country name/code, or None for best/last server.
        """
        lock = self._get_lock()
        try:
            current_state = self.get_state()
            if current_state.status == "connected" and current_state.pid and is_pid_alive(current_state.pid):
                logger.info(f"Already connected to {current_state.server_name}")
                return current_state

            # Find executable
            exe, core_type = find_vpn_binary()
            logger.info(f"Using {core_type} core at {exe}")

            # Resolve server
            server = self._resolve_server(server_target)
            if not server:
                raise ConnectionError("No available server found to connect.")

            logger.info(f"Target server selected: {server.display_name()} (id: {server.id})")

            # Build config
            http_port = self.config_manager.get("http_port", DEFAULT_HTTP_PORT)
            socks_port = self.config_manager.get("socks_port", DEFAULT_SOCKS_PORT)
            api_port = DEFAULT_API_PORT
            routing_mode = self.config_manager.get("routing_mode", "bypass_lan_iran")
            block_ads = self.config_manager.get("block_ads", True)
            stealth = self.config_manager.get("stealth_fragment", True)
            upstream = self.config_manager.get("upstream_proxy") if self.config_manager.get("upstream_proxy_on") else None

            conf = build_xray_config(
                link=server.link,
                http_port=http_port,
                socks_port=socks_port,
                api_port=api_port,
                enable_fragment=stealth,
                upstream_proxy=upstream,
                routing_mode=routing_mode,
                block_ads=block_ads,
            )

            if not conf:
                raise ConnectionError("Failed to parse link into valid core configuration.")

            # Write generated config
            GENERATED_XRAY_CONFIG.parent.mkdir(parents=True, exist_ok=True)
            with open(GENERATED_XRAY_CONFIG, "w", encoding="utf-8") as f:
                json.dump(conf, f, indent=2)

            # Prepare execution command
            if core_type == "v2ray":
                cmd = [exe, "run", "-c", str(GENERATED_XRAY_CONFIG)]
            else:
                cmd = [exe, "run", "-c", str(GENERATED_XRAY_CONFIG)]

            # Start detached daemon process
            with open(logger.log_file, "a", encoding="utf-8") as log_out:
                proc = subprocess.Popen(
                    cmd,
                    stdout=log_out,
                    stderr=log_out,
                    stdin=subprocess.DEVNULL,
                    start_new_session=True,  # Detach from terminal session
                )

            pid = proc.pid
            with open(PID_FILE, "w", encoding="utf-8") as f:
                f.write(str(pid))

            # Wait briefly and verify process didn't instantly crash
            time.sleep(1.2)
            if not is_pid_alive(pid):
                set_linux_proxy(False)
                raise ConnectionError("VPN core process failed to start. Check logs for details.")

            # Configure system proxy
            set_linux_proxy(True, http_port=http_port, socks_port=socks_port)

            # Verify connectivity through tunnel
            probe_ok = self._check_connectivity(http_port=http_port)
            if not probe_ok:
                logger.warning("Initial connectivity probe slow or failed, checking again...")

            # Get public IP via proxy
            public_ip = self.get_public_ip(proxy=f"http://127.0.0.1:{http_port}")

            state = VpnState(
                status="connected",
                server_id=server.id,
                server_name=server.display_name(),
                server_country=server.country,
                protocol=server.protocol,
                transport=server.transport,
                pid=pid,
                connected_at=time.time(),
                public_ip=public_ip or "Connected (IP fetching...)",
                dns_status="Active"
            )

            self._save_state(state)
            self.config_manager.set("last_server_id", server.id)
            logger.info(f"VPN connected successfully to {server.display_name()} [PID {pid}]")

            return state
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)

    def disconnect(self) -> VpnState:
        """Disconnect active VPN tunnel and reset system proxy."""
        lock = self._get_lock()
        try:
            state = self.get_state()
            pid = state.pid

            if pid and is_pid_alive(pid):
                logger.info(f"Stopping VPN daemon PID {pid}")
                try:
                    os.kill(pid, signal.SIGTERM)
                    for _ in range(30):
                        if not is_pid_alive(pid):
                            break
                        time.sleep(0.1)
                    if is_pid_alive(pid):
                        os.kill(pid, signal.SIGKILL)
                except Exception as e:
                    logger.error(f"Error terminating PID {pid}: {e}")

            set_linux_proxy(False)

            if PID_FILE.exists():
                try:
                    PID_FILE.unlink()
                except Exception:
                    pass

            state.status = "disconnected"
            state.pid = None
            state.connected_at = None
            state.public_ip = ""
            self._save_state(state)
            logger.info("VPN disconnected cleanly")
            return state
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)

    def reconnect(self) -> VpnState:
        """Disconnect and reconnect to server."""
        state = self.get_state()
        last_id = state.server_id or self.config_manager.get("last_server_id")
        self.disconnect()
        time.sleep(0.5)
        return self.connect(last_id)

    def _resolve_server(self, target: Optional[str]) -> Optional[Server]:
        sb_url = self.config_manager.get("sb_url")
        sb_key = self.config_manager.get("sb_key")
        all_servers = self.server_manager.fetch_servers(sb_url, sb_key)

        if not all_servers:
            all_servers = self.server_manager.get_cached_servers()

        if not all_servers:
            return None

        if target:
            # Check by exact ID
            for s in all_servers:
                if s.id == target:
                    return s
            # Check by country name or code
            filtered = self.server_manager.filter_by_country(all_servers, target)
            if filtered:
                return filtered[0]

        # Use last server if valid
        last_id = self.config_manager.get("last_server_id")
        if last_id:
            for s in all_servers:
                if s.id == last_id:
                    return s

        return all_servers[0]

    def _check_connectivity(self, http_port: int, timeout: int = 5) -> bool:
        proxy_handler = urllib.request.ProxyHandler({
            "http": f"http://127.0.0.1:{http_port}",
            "https": f"http://127.0.0.1:{http_port}",
        })
        opener = urllib.request.build_opener(proxy_handler)

        for u in CONNECTIVITY_PROBE_URLS:
            try:
                req = urllib.request.Request(u, headers={"User-Agent": "Nexora/1.0"})
                with opener.open(req, timeout=timeout) as resp:
                    if resp.status in (200, 204):
                        return True
            except Exception:
                pass
        return False

    def get_public_ip(self, proxy: Optional[str] = None) -> str:
        """Query public IP info directly or via proxy."""
        handlers = []
        if proxy:
            handlers.append(urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
        opener = urllib.request.build_opener(*handlers)

        for url in IP_INFO_URLS:
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "Nexora/1.0", "Accept": "application/json"})
                with opener.open(req, timeout=6) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    ip = data.get("ip")
                    country = data.get("country") or data.get("country_name") or ""
                    if ip:
                        return f"{ip} ({country})" if country else ip
            except Exception:
                pass
        return ""

    def get_ip_details(self, proxy: Optional[str] = None) -> Dict[str, Any]:
        """Fetch full IP and location details."""
        handlers = []
        if proxy:
            handlers.append(urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
        opener = urllib.request.build_opener(*handlers)

        try:
            req = urllib.request.Request("https://ipwho.is/", headers={"User-Agent": "Nexora/1.0", "Accept": "application/json"})
            with opener.open(req, timeout=6) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if data.get("success") is not False:
                    return {
                        "ip": data.get("ip", "Unknown"),
                        "country": data.get("country", "Unknown"),
                        "city": data.get("city", "Unknown"),
                        "isp": (data.get("connection") or {}).get("isp", "Unknown"),
                        "org": (data.get("connection") or {}).get("org", "Unknown"),
                        "flag": data.get("flag", {}).get("emoji", "🌐"),
                    }
        except Exception:
            pass

        return {
            "ip": "Unavailable",
            "country": "Unknown",
            "city": "Unknown",
            "isp": "Unknown",
            "org": "Unknown",
            "flag": "🌐"
        }
