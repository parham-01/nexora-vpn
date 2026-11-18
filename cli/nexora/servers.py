"""
Server manager: fetching, caching, filtering, and pinging VPN servers.
"""

import json
import socket
import time
import urllib.request
import urllib.error
from typing import List, Optional, Dict, Any

from .constants import SERVERS_CACHE_FILE
from .models import Server
from .xray import parse_link

class ServerManager:
    def __init__(self, cache_file=SERVERS_CACHE_FILE):
        self.cache_file = cache_file

    def get_cached_servers(self) -> List[Server]:
        """Read servers from local cache file."""
        if not self.cache_file.exists():
            return []
        try:
            with open(self.cache_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                return [
                    Server(
                        id=str(e.get("id", "")),
                        name=str(e.get("name", "")),
                        link=str(e.get("link", "")),
                        country=str(e.get("country", "")),
                        code=str(e.get("code", "")),
                        protocol=str(e.get("protocol", "")),
                        transport=str(e.get("transport", "")),
                        quota_gb=int(e.get("quota_gb", 0)),
                        expires=str(e.get("expires", "")),
                        ping_ms=int(e.get("ping_ms", -1)),
                    )
                    for e in data
                ]
        except Exception:
            return []

    def save_cache(self, servers: List[Server]):
        """Persist servers to local cache."""
        self.cache_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self.cache_file, "w", encoding="utf-8") as f:
            json.dump([s.to_dict() for s in servers], f, indent=2)

    def fetch_servers(self, sb_url: str, sb_key: str, timeout: int = 10) -> List[Server]:
        """
        Fetch active servers from backend (Supabase REST API).
        Falls back to cache if offline.
        """
        if not sb_url or not sb_key:
            return self.get_cached_servers()

        url = f"{sb_url.rstrip('/')}/rest/v1/configs?select=id,name,quota_gb,expires,link,protocol,transport,country,code&enabled=eq.true&order=created_at.asc&limit=500"
        headers = {
            "apikey": sb_key,
            "accept": "application/json",
            "content-type": "application/json"
        }
        if sb_key.startswith("eyJ"):
            headers["authorization"] = f"Bearer {sb_key}"

        req = urllib.request.Request(url, headers=headers, method="GET")

        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                servers: List[Server] = []
                for e in data:
                    link = str(e.get("link", ""))
                    info = parse_link(link)
                    srv = Server(
                        id=str(e.get("id", "")),
                        name=str(e.get("name", "") or info.name),
                        link=link,
                        country=str(e.get("country", "")),
                        code=str(e.get("code", "")),
                        protocol=str(e.get("protocol", "") or info.protocol),
                        transport=str(e.get("transport", "") or info.transport),
                        quota_gb=int(e.get("quota_gb", 0) or 0),
                        expires=str(e.get("expires", "")),
                    )
                    servers.append(srv)

                if servers:
                    self.save_cache(servers)
                return servers
        except Exception:
            # Fall back to local cache
            return self.get_cached_servers()

    def filter_by_country(self, servers: List[Server], country_query: str) -> List[Server]:
        """Filter servers by country name or two-letter ISO code."""
        query = country_query.strip().lower()
        if not query:
            return servers

        # Common translations / aliases
        aliases = {
            "germany": ["germany", "de", "deutschland", "آلمان"],
            "france": ["france", "fr", "فرانسه"],
            "netherlands": ["netherlands", "nl", "holland", "هلند"],
            "united states": ["united states", "usa", "us", "آمریکا"],
            "united kingdom": ["united kingdom", "uk", "gb", "انگلیس"],
            "finland": ["finland", "fi", "فنلاند"],
            "turkey": ["turkey", "tr", "ترکیه"],
        }

        matched_keys = [query]
        for canonical, syns in aliases.items():
            if query in syns or canonical == query:
                matched_keys.extend(syns)

        matched_keys = set(matched_keys)

        results = []
        for s in servers:
            c_name = s.country.lower()
            c_code = s.code.lower()
            s_name = s.name.lower()
            if any(k in c_name or k == c_code or k in s_name for k in matched_keys):
                results.append(s)

        return results

    @staticmethod
    def ping_server(server: Server, timeout: float = 3.0) -> int:
        """Measure TCP latency to the server host and port."""
        info = parse_link(server.link)
        if not info.host or info.port <= 0:
            return -1

        try:
            start = time.perf_counter()
            s = socket.create_connection((info.host, info.port), timeout=timeout)
            ms = int((time.perf_counter() - start) * 1000)
            s.close()
            server.ping_ms = ms
            return ms
        except Exception:
            server.ping_ms = -1
            return -1
