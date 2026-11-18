"""
Tests for network failures, timeouts, and offline handling.
"""

import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

CLI_DIR = Path(__file__).resolve().parent.parent / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from nexora.models import Server
from nexora.servers import ServerManager
from nexora.config import ConfigManager
from nexora.security import CredentialStore
from nexora.auth import AuthManager
from nexora.errors import AuthError

class TestNetworkFailureHandling(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.srv_cache = self.tmp_path / "servers.json"
        self.cfg_file = self.tmp_path / "config.json"
        self.cred_file = self.tmp_path / "credentials.json"

        self.srv_mgr = ServerManager(self.srv_cache)
        self.cfg_mgr = ConfigManager(self.cfg_file)
        self.cred_store = CredentialStore(self.cred_file)
        self.cred_store.use_secret_service = False
        self.auth_mgr = AuthManager(self.cfg_mgr, self.cred_store)

    def tearDown(self):
        self.tmp_dir.cleanup()

    @patch("urllib.request.urlopen", side_effect=urllib.error.URLError("Network is unreachable"))
    def test_servers_fetch_falls_back_to_cache_on_offline(self, mock_urlopen):
        # Prepopulate cache
        cached_servers = [Server(id="c1", name="Cached DE", link="vless://...", country="Germany")]
        self.srv_mgr.save_cache(cached_servers)

        # Attempt to fetch with bad network
        result = self.srv_mgr.fetch_servers("https://api.example.com", "fake_key")
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].name, "Cached DE")

    @patch("urllib.request.urlopen", side_effect=urllib.error.URLError("Connection refused"))
    def test_auth_handles_network_error(self, mock_urlopen):
        with self.assertRaises(AuthError):
            self.auth_mgr.login("user@test.com", "password123")

    def test_ping_non_routable_ip_returns_timeout(self):
        # 192.0.2.1 is documentation prefix TEST-NET-1, guaranteed not to route
        dummy = Server(id="d1", name="Dead Server", link="vless://test@192.0.2.1:54321?type=tcp")
        ms = ServerManager.ping_server(dummy, timeout=0.2)
        self.assertEqual(ms, -1)

if __name__ == "__main__":
    unittest.main()
