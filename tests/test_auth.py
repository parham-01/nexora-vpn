"""
Tests for authentication, session management, and credential storage.
"""

import os
import sys
import json
import time
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

CLI_DIR = Path(__file__).resolve().parent.parent / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from nexora.config import ConfigManager
from nexora.security import CredentialStore, sanitize_text
from nexora.auth import AuthManager
from nexora.errors import AuthError

class TestAuthAndSecurity(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.cfg_file = self.tmp_path / "config.json"
        self.cred_file = self.tmp_path / "credentials.json"

        self.cfg_mgr = ConfigManager(self.cfg_file)
        self.cred_store = CredentialStore(self.cred_file)
        # Force file storage for deterministic tests
        self.cred_store.use_secret_service = False
        self.auth_mgr = AuthManager(self.cfg_mgr, self.cred_store)

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_file_permissions_are_restricted(self):
        self.cred_store.save_credentials("acc-1", "test@test.com", {"token": "xyz"})
        self.assertTrue(self.cred_file.exists())
        mode = os.stat(self.cred_file).st_mode & 0o777
        self.assertEqual(mode, 0o600)

    def test_sanitize_text_masks_jwts_and_passwords(self):
        raw = "User session eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.doNotLeakThis and password: secret_pass"
        clean = sanitize_text(raw)
        self.assertNotIn("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9", clean)
        self.assertNotIn("secret_pass", clean)
        self.assertIn("[MASKED_JWT]", clean)
        self.assertIn("[MASKED]", clean)

    def test_save_and_retrieve_credentials(self):
        tokens = {"access_token": "token123", "expires_at": int(time.time() + 3600)}
        self.cred_store.save_credentials("acc-001", "user@nexora.vpn", tokens)

        retrieved = self.cred_store.get_credentials("user@nexora.vpn")
        self.assertIsNotNone(retrieved)
        self.assertEqual(retrieved["account_id"], "acc-001")
        self.assertEqual(retrieved["tokens"]["access_token"], "token123")

    def test_logout_clears_credentials(self):
        self.cred_store.save_credentials("acc-001", "user@nexora.vpn", {"access_token": "token123"})
        self.auth_mgr.logout("user@nexora.vpn")

        acc = self.auth_mgr.get_account_info()
        self.assertFalse(acc.logged_in)
        self.assertEqual(acc.email, "")

    def test_token_expiration_detection(self):
        past_time = int(time.time() - 100)
        self.cred_store.save_credentials("acc-001", "expired@nexora.vpn", {"access_token": "xyz", "expires_at": past_time})

        acc = self.auth_mgr.get_account_info()
        self.assertTrue(acc.logged_in)
        self.assertTrue(acc.is_expired())

    @patch("urllib.request.urlopen")
    def test_login_successful_flow(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "access_token": "jwt.sample.token",
            "refresh_token": "ref.sample.token",
            "expires_in": 3600,
            "user": {"id": "user-uuid-1234", "email": "test@nexora.vpn"}
        }).encode("utf-8")
        mock_urlopen.return_value.__enter__.return_value = mock_resp

        acc = self.auth_mgr.login("test@nexora.vpn", "strongpassword")
        self.assertTrue(acc.logged_in)
        self.assertEqual(acc.email, "test@nexora.vpn")
        self.assertEqual(acc.account_id, "user-uuid-1234")
        self.assertFalse(acc.is_expired())

if __name__ == "__main__":
    unittest.main()
