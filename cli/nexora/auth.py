"""
Authentication and account management for Nexora VPN.
Supports Supabase Auth, token refresh, and credential storage.
"""

import json
import time
import urllib.request
import urllib.error
from typing import Optional, Dict, Any, Tuple

from .constants import DEFAULT_SB_URL
from .config import ConfigManager
from .security import CredentialStore
from .models import AccountInfo
from .errors import AuthError
from .logger import logger

class AuthManager:
    def __init__(self, config_manager: ConfigManager, cred_store: CredentialStore):
        self.config_manager = config_manager
        self.cred_store = cred_store

    def login(self, email: str, password: str) -> AccountInfo:
        """
        Authenticate with email and password.
        Uses Supabase Auth API with apikey.
        """
        sb_url = self.config_manager.get("sb_url") or DEFAULT_SB_URL
        sb_key = self.config_manager.get("sb_key") or ""

        url = f"{sb_url.rstrip('/')}/auth/v1/token?grant_type=password"
        payload = json.dumps({"email": email, "password": password}).encode("utf-8")
        headers = {
            "content-type": "application/json",
            "accept": "application/json"
        }
        if sb_key:
            headers["apikey"] = sb_key
            if sb_key.startswith("eyJ"):
                headers["authorization"] = f"Bearer {sb_key}"

        req = urllib.request.Request(url, data=payload, headers=headers, method="POST")

        try:
            with urllib.request.urlopen(req, timeout=12) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                access_token = data.get("access_token")
                refresh_token = data.get("refresh_token")
                expires_in = data.get("expires_in", 3600)
                user = data.get("user", {})
                account_id = user.get("id") or email

                expires_at = int(time.time() + expires_in)

                token_data = {
                    "access_token": access_token,
                    "refresh_token": refresh_token,
                    "expires_at": expires_at,
                    "created_at": time.strftime("%Y-%m-%d %H:%M:%S")
                }

                self.cred_store.save_credentials(account_id, email, token_data)
                logger.info(f"User {email} logged in successfully")

                return AccountInfo(
                    logged_in=True,
                    email=email,
                    account_id=account_id,
                    token_expires_at=expires_at,
                    created_at=token_data["created_at"],
                    device_id=self.cred_store.get_or_create_device_id(),
                    storage_type="secret-service" if self.cred_store.use_secret_service else "file"
                )

        except urllib.error.HTTPError as e:
            err_msg = "Authentication failed"
            try:
                body = json.loads(e.read().decode("utf-8"))
                err_msg = body.get("error_description") or body.get("msg") or body.get("message") or err_msg
            except Exception:
                pass
            logger.error(f"Login failed for {email}: {err_msg}")
            raise AuthError(err_msg)

        except Exception as e:
            logger.error(f"Network error during login for {email}: {e}")
            raise AuthError(f"Network or server error during login: {e}")

    def logout(self, email: Optional[str] = None) -> bool:
        """Clear session and remove credentials."""
        ok = self.cred_store.delete_credentials(email)
        logger.info(f"Logged out account {email or 'current'}")
        return ok

    def get_account_info(self) -> AccountInfo:
        """Get current session status."""
        creds = self.cred_store.get_credentials()
        if not creds:
            return AccountInfo(
                logged_in=False,
                device_id=self.cred_store.get_or_create_device_id(),
                storage_type="secret-service" if self.cred_store.use_secret_service else "file"
            )

        tokens = creds.get("tokens", {})
        expires_at = tokens.get("expires_at")
        email = creds.get("email", "")
        account_id = creds.get("account_id", "")
        created_at = tokens.get("created_at", "")

        return AccountInfo(
            logged_in=True,
            email=email,
            account_id=account_id,
            token_expires_at=expires_at,
            created_at=created_at,
            device_id=self.cred_store.get_or_create_device_id(),
            storage_type="secret-service" if self.cred_store.use_secret_service else "file"
        )
