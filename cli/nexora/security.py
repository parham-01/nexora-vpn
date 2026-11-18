"""
Security mechanisms for credential storage and log sanitization.
Uses Linux Secret Service (secret-tool) when available, with fallback
to 0600 permission file in XDG_CONFIG_HOME.
"""

import os
import json
import secrets
import shutil
import subprocess
import getpass
from pathlib import Path
from typing import Optional, Dict, Any

from .constants import CREDENTIALS_FILE, XDG_CONFIG_HOME

def get_secret_tool_path() -> Optional[str]:
    return shutil.which("secret-tool")

def has_working_secret_service() -> bool:
    if not get_secret_tool_path():
        return False
    # If in headless SSH without D-Bus, secret-tool might fail. Test with a quick probe
    try:
        r = subprocess.run(
            ["secret-tool", "lookup", "service", "nexora_probe_test_nonexistent"],
            capture_output=True,
            timeout=1,
            text=True
        )
        # returncode 0 (found) or 1 (not found) means Secret Service is responding
        return r.returncode in (0, 1)
    except Exception:
        return False

def prompt_password(prompt: str = "Password: ") -> str:
    """Read password securely without echoing to terminal."""
    try:
        return getpass.getpass(prompt)
    except Exception:
        # Fallback if getpass fails (e.g. non-tty pipes in tests)
        import sys
        line = sys.stdin.readline()
        return line.strip()

def sanitize_text(text: str) -> str:
    """
    Scrub sensitive credentials, bearer tokens, passwords, and private keys from logs.
    """
    import re
    # Mask JWTs
    text = re.sub(r'eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+', '[MASKED_JWT]', text)
    # Mask quoted password/key fields: "password": "...", 'secret': '...'
    text = re.sub(r'(["\']?(?:password|token|secret|key|pbk|sid)["\']?\s*[:=]\s*["\'])([^"\']+)(["\'])', r'\1[MASKED]\3', text, flags=re.IGNORECASE)
    # Mask unquoted password/key fields: password: secret_pass, key=12345
    text = re.sub(r'(\b(?:password|token|secret|key|pbk|sid)\s*[:=]\s*)([^\s,]+)', r'\1[MASKED]', text, flags=re.IGNORECASE)
    return text

class CredentialStore:
    def __init__(self, cred_file: Path = CREDENTIALS_FILE):
        self.cred_file = cred_file
        self.use_secret_service = has_working_secret_service()
        self._ensure_file_security()

    def _ensure_file_security(self):
        self.cred_file.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(self.cred_file.parent, 0o700)
        except Exception:
            pass

    def _read_file_creds(self) -> Dict[str, Any]:
        if not self.cred_file.exists():
            return {}
        try:
            with open(self.cred_file, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}

    def _write_file_creds(self, data: Dict[str, Any]):
        flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
        mode = 0o600
        content = json.dumps(data, indent=2)
        fd = os.open(self.cred_file, flags, mode)
        with open(fd, "w", encoding="utf-8") as f:
            f.write(content)

    def save_credentials(self, account_id: str, email: str, tokens: Dict[str, Any]):
        """Store authentication credentials securely."""
        payload_str = json.dumps({
            "account_id": account_id,
            "email": email,
            "tokens": tokens
        })

        if self.use_secret_service:
            try:
                proc = subprocess.run(
                    ["secret-tool", "store", "--label=Nexora VPN Token", "service", "nexora", "account", email],
                    input=payload_str,
                    capture_output=True,
                    text=True,
                    timeout=3
                )
                if proc.returncode == 0:
                    # Also keep index of last logged in email in file without sensitive tokens
                    data = self._read_file_creds()
                    data["last_account"] = email
                    data["storage"] = "secret-service"
                    self._write_file_creds(data)
                    return
            except Exception:
                pass

        # Fallback to 0600 file
        data = self._read_file_creds()
        data["last_account"] = email
        data["storage"] = "file"
        data["accounts"] = data.get("accounts", {})
        data["accounts"][email] = {
            "account_id": account_id,
            "email": email,
            "tokens": tokens
        }
        self._write_file_creds(data)

    def get_credentials(self, email: Optional[str] = None) -> Optional[Dict[str, Any]]:
        """Retrieve credentials for an account or the last logged-in account."""
        data = self._read_file_creds()
        target_email = email or data.get("last_account")
        if not target_email:
            return None

        if self.use_secret_service:
            try:
                proc = subprocess.run(
                    ["secret-tool", "lookup", "service", "nexora", "account", target_email],
                    capture_output=True,
                    text=True,
                    timeout=3
                )
                if proc.returncode == 0 and proc.stdout.strip():
                    return json.loads(proc.stdout.strip())
            except Exception:
                pass

        accounts = data.get("accounts", {})
        return accounts.get(target_email)

    def delete_credentials(self, email: Optional[str] = None) -> bool:
        """Clear stored credentials."""
        data = self._read_file_creds()
        target_email = email or data.get("last_account")
        if not target_email:
            return False

        if self.use_secret_service:
            try:
                subprocess.run(
                    ["secret-tool", "clear", "service", "nexora", "account", target_email],
                    capture_output=True,
                    timeout=3
                )
            except Exception:
                pass

        if "accounts" in data and target_email in data["accounts"]:
            del data["accounts"][target_email]
        if data.get("last_account") == target_email:
            data.pop("last_account", None)

        self._write_file_creds(data)
        return True

    def get_or_create_device_id(self) -> str:
        """Get persistent random 16-byte hex device identifier."""
        data = self._read_file_creds()
        dev_id = data.get("device_id")
        if not dev_id:
            dev_id = secrets.token_hex(16)
            data["device_id"] = dev_id
            self._write_file_creds(data)
        return dev_id
