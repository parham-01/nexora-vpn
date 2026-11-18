"""
Data models for servers, link parsing, states, and accounts.
"""

from dataclasses import dataclass, field
from typing import Optional, Dict, Any, List
import time

@dataclass
class LinkInfo:
    protocol: str
    transport: str
    outbound: Optional[Dict[str, Any]]
    name: str = ""
    host: str = ""
    port: int = 0

@dataclass
class Server:
    id: str
    name: str
    link: str
    country: str = ""
    code: str = ""
    protocol: str = ""
    transport: str = ""
    quota_gb: int = 0
    expires: str = ""
    ping_ms: int = -1

    def flag(self) -> str:
        if len(self.code) != 2:
            return "🌐"
        code = self.code.upper()
        return chr(0x1F1E6 + ord(code[0]) - ord('A')) + chr(0x1F1E6 + ord(code[1]) - ord('A'))

    def display_name(self) -> str:
        if self.name and not self.name.replace(".", "").isdigit():
            return self.name
        if self.country:
            return f"{self.flag()} {self.country}"
        return f"{self.protocol.upper() or 'VPN'} Server ({self.id[:8]})"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "link": self.link,
            "country": self.country,
            "code": self.code,
            "protocol": self.protocol,
            "transport": self.transport,
            "quota_gb": self.quota_gb,
            "expires": self.expires,
            "ping_ms": self.ping_ms,
            "flag": self.flag(),
            "display_name": self.display_name(),
        }

@dataclass
class VpnState:
    status: str = "disconnected"  # disconnected, connecting, connected, error
    server_id: str = ""
    server_name: str = ""
    server_country: str = ""
    protocol: str = ""
    transport: str = ""
    pid: Optional[int] = None
    connected_at: Optional[float] = None
    public_ip: str = ""
    dns_status: str = "Active"
    bytes_up: int = 0
    bytes_down: int = 0
    error_message: str = ""

    def uptime_seconds(self) -> int:
        if self.status == "connected" and self.connected_at:
            return max(0, int(time.time() - self.connected_at))
        return 0

    def uptime_formatted(self) -> str:
        s = self.uptime_seconds()
        h = s // 3600
        m = (s % 3600) // 60
        sec = s % 60
        return f"{h:02d}:{m:02d}:{sec:02d}"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "status": self.status,
            "server_id": self.server_id,
            "server_name": self.server_name,
            "server_country": self.server_country,
            "protocol": self.protocol,
            "transport": self.transport,
            "pid": self.pid,
            "uptime_seconds": self.uptime_seconds(),
            "uptime": self.uptime_formatted(),
            "public_ip": self.public_ip,
            "dns_status": self.dns_status,
            "bytes_up": self.bytes_up,
            "bytes_down": self.bytes_down,
            "error_message": self.error_message,
        }

@dataclass
class AccountInfo:
    logged_in: bool = False
    email: str = ""
    account_id: str = ""
    token_expires_at: Optional[int] = None
    created_at: str = ""
    device_id: str = ""
    storage_type: str = "file"

    def is_expired(self) -> bool:
        if not self.token_expires_at:
            return False
        return time.time() >= self.token_expires_at

    def to_dict(self) -> Dict[str, Any]:
        return {
            "logged_in": self.logged_in,
            "email": self.email,
            "account_id": self.account_id,
            "token_expires_at": self.token_expires_at,
            "is_expired": self.is_expired(),
            "created_at": self.created_at,
            "device_id": self.device_id,
            "storage_type": self.storage_type,
        }

@dataclass
class FirefoxAccount:
    id: str
    email: str
    name: str
    status: str
    enabled: bool
    needs_signin: bool
    quota_left_bytes: int = 0
    quota_total_bytes: int = 0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "email": self.email,
            "name": self.name,
            "status": self.status,
            "enabled": self.enabled,
            "needs_signin": self.needs_signin,
            "quota_left_bytes": self.quota_left_bytes,
            "quota_total_bytes": self.quota_total_bytes,
        }

@dataclass
class FirefoxLocation:
    country_code: str
    name: str
    flag: str
    servers_count: int = 0
    ping_ms: int = -1

    def to_dict(self) -> Dict[str, Any]:
        return {
            "country_code": self.country_code,
            "name": self.name,
            "flag": self.flag,
            "servers_count": self.servers_count,
            "ping_ms": self.ping_ms,
        }
