"""
Firefox VPN integration for Nexora CLI.
Communicates with the independent Firefox/Guardian Go core dashboard API
(core/doc/DASHBOARD.md, client/lib/firefox/core/core_api.dart).
"""

import os
import json
import time
import shutil
import subprocess
import urllib.request
import urllib.error
from pathlib import Path
from typing import Optional, Dict, Any, List

from .constants import FIREFOX_DATA_DIR, DEFAULT_FIREFOX_PORT
from .models import FirefoxAccount, FirefoxLocation
from .errors import AuthError, ConnectionError, ServiceUnavailableError
from .logger import logger

class FirefoxManager:
    def __init__(self, data_dir: Path = FIREFOX_DATA_DIR):
        self.data_dir = data_dir
        self.token_file = self.data_dir / "local-api.token"
        self.config_file = self.data_dir / "config.json"
        self._core_proc: Optional[subprocess.Popen] = None

    def find_core_binary(self) -> Optional[str]:
        """Search for nexora-vpn-core executable."""
        candidates = [
            shutil.which("nexora-vpn-core"),
            str(Path.cwd() / "firefox-core" / "nexora-vpn-core"),
            str(Path.home() / ".local" / "share" / "nexora" / "bin" / "nexora-vpn-core"),
            "/usr/local/bin/nexora-vpn-core",
            "/usr/bin/nexora-vpn-core",
        ]
        for c in candidates:
            if c and os.path.isfile(c) and os.access(c, os.X_OK):
                return c
        return None

    def get_api_endpoint(self) -> Tuple[str, str]:
        """
        Reads local token and listen address.
        Returns: (base_url, token)
        """
        if not self.token_file.exists():
            raise ServiceUnavailableError(
                f"Firefox core token not found at {self.token_file}. "
                "Ensure Firefox core service is running."
            )

        try:
            with open(self.token_file, "r", encoding="utf-8") as f:
                token = f.read().strip()
        except Exception as e:
            raise ServiceUnavailableError(f"Failed to read Firefox core token: {e}")

        listen = f"127.0.0.1:{DEFAULT_FIREFOX_PORT}"
        if self.config_file.exists():
            try:
                with open(self.config_file, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
                    listen = (cfg.get("dashboard") or {}).get("listen") or listen
            except Exception:
                pass

        if listen.startswith("0.0.0.0") or listen.startswith("::"):
            port = listen.split(":")[-1]
            listen = f"127.0.0.1:{port}"

        return f"http://{listen}", token

    def ensure_core_running(self):
        """Check if core is responding; if not, attempt to start it."""
        try:
            self._request("GET", "/api/status", timeout=2)
            return
        except Exception:
            pass

        exe = self.find_core_binary()
        if not exe:
            raise ServiceUnavailableError(
                "Firefox VPN core binary (nexora-vpn-core) not found. "
                "Please build or install nexora-vpn-core to enable Firefox VPN functionality."
            )

        self.data_dir.mkdir(parents=True, exist_ok=True)
        cmd = [exe, "-app", f"-data-dir={self.data_dir}"]

        with open(logger.log_file, "a", encoding="utf-8") as log_out:
            self._core_proc = subprocess.Popen(
                cmd,
                stdout=log_out,
                stderr=log_out,
                stdin=subprocess.DEVNULL,
                start_new_session=True,
            )

        # Wait up to 10 seconds for API to become ready
        until = time.time() + 10
        while time.time() < until:
            try:
                self._request("GET", "/api/status", timeout=1)
                return
            except Exception:
                time.sleep(0.5)

        raise ServiceUnavailableError("Timed out waiting for Firefox VPN core to start.")

    def _request(self, method: str, path: str, body: Optional[Dict[str, Any]] = None, timeout: int = 10) -> Dict[str, Any]:
        base_url, token = self.get_api_endpoint()
        url = f"{base_url.rstrip('/')}{path}"
        data = json.dumps(body).encode("utf-8") if body is not None else None

        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Local-Token": token,
        }

        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                content = resp.read().decode("utf-8")
                return json.loads(content) if content else {}
        except urllib.error.HTTPError as e:
            msg = f"Core HTTP {e.code}"
            try:
                err_data = json.loads(e.read().decode("utf-8"))
                msg = err_data.get("error") or msg
            except Exception:
                pass
            raise ConnectionError(msg)
        except Exception as e:
            raise ConnectionError(f"Firefox core connection error: {e}")

    def get_status(self) -> Dict[str, Any]:
        """Query Firefox core status and accounts."""
        self.ensure_core_running()
        status_data = self._request("GET", "/api/status")
        accounts_data = self._request("GET", "/api/accounts")

        accounts = [
            FirefoxAccount(
                id=str(a.get("id", "")),
                email=str(a.get("email", "")),
                name=str(a.get("name", "")),
                status=str(a.get("status", "")),
                enabled=bool(a.get("enabled", True)),
                needs_signin=bool(a.get("status") == "reauth_required"),
                quota_left_bytes=int((a.get("usage") or {}).get("remaining_bytes", 0)),
                quota_total_bytes=int((a.get("usage") or {}).get("total_bytes", 0)),
            )
            for a in (accounts_data.get("accounts") or [])
        ]

        active_account = status_data.get("active_account")
        power = status_data.get("power", False)
        selection = status_data.get("selection", "")

        return {
            "power": power,
            "connected": power,
            "selection": selection,
            "active_account": active_account,
            "accounts_count": len(accounts),
            "accounts": [a.to_dict() for a in accounts],
            "raw": status_data,
        }

    def list_servers(self) -> List[FirefoxLocation]:
        """Fetch available Firefox VPN locations."""
        self.ensure_core_running()
        data = self._request("GET", "/api/locations")
        locations: List[FirefoxLocation] = []
        for loc in (data.get("locations") or []):
            code = str(loc.get("country_code", ""))
            flag = chr(0x1F1E6 + ord(code[0]) - ord('A')) + chr(0x1F1E6 + ord(code[1]) - ord('A')) if len(code) == 2 else "🌐"
            locations.append(FirefoxLocation(
                country_code=code,
                name=str(loc.get("name") or code),
                flag=flag,
                servers_count=int(loc.get("servers_count", 0)),
                ping_ms=int(loc.get("ping_ms", -1))
            ))
        return locations

    def login(self, email: str, password: str, code_callback=None) -> FirefoxAccount:
        """
        Interactive login to Mozilla Firefox account.
        Communicates with core /api/signin.
        """
        self.ensure_core_running()
        res = self._request("POST", "/api/signin", {"email": email, "password": password})
        signin_id = res.get("id")
        step = res.get("step")

        # Drive the state until done or error
        until = time.time() + 180
        while time.time() < until:
            if step == "done":
                # Refresh accounts
                accounts = self.get_status().get("accounts", [])
                for acc in accounts:
                    if acc["email"] == email:
                        return FirefoxAccount(**acc)
                return FirefoxAccount(id=signin_id or "new", email=email, name=email, status="ready", enabled=True, needs_signin=False)

            elif step in ("need_code", "need_totp"):
                if not code_callback:
                    raise AuthError(f"Verification required ({step}), but no interactive input available.")
                code_value = code_callback(step)
                res = self._request("POST", f"/api/signin/{signin_id}", {"value": code_value})
                step = res.get("step")

            elif step in ("failed", "cancelled"):
                err_msg = res.get("error") or res.get("message") or "Sign-in failed."
                raise AuthError(err_msg)

            time.sleep(1.5)
            res = self._request("GET", f"/api/signin/{signin_id}")
            step = res.get("step")

        raise AuthError("Sign-in timed out waiting for Mozilla verification.")

    def logout(self, account_id: Optional[str] = None):
        """Remove Firefox account."""
        self.ensure_core_running()
        if not account_id:
            # Remove active or first account
            st = self.get_status()
            accounts = st.get("accounts", [])
            if not accounts:
                return
            account_id = accounts[0]["id"]

        self._request("DELETE", f"/api/accounts/{account_id}")

    def connect(self, server_query: Optional[str] = None):
        """Connect to a Firefox VPN location."""
        self.ensure_core_running()
        if server_query:
            locs = self.list_servers()
            target_code = None
            q = server_query.strip().lower()
            for l in locs:
                if l.country_code.lower() == q or l.name.lower() == q:
                    target_code = l.country_code
                    break
            if not target_code:
                # Default to query as country code
                target_code = server_query.strip().upper()

            self._request("POST", "/api/location", {"country": target_code})

        self._request("POST", "/api/power", {"on": True})

    def disconnect(self):
        """Disconnect Firefox VPN proxy."""
        self.ensure_core_running()
        self._request("POST", "/api/power", {"on": False})
