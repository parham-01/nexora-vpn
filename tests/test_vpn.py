"""
Tests for VPN lifecycle manager with mocked system process.
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

CLI_DIR = Path(__file__).resolve().parent.parent / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from nexora.config import ConfigManager
from nexora.servers import ServerManager
from nexora.models import Server, VpnState
from nexora.vpn import VpnManager

SAMPLE_LINK = "vless://test@127.0.0.1:443?type=tcp&security=none#Mock-Server"

class TestVpnLifecycle(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.cfg_file = self.tmp_path / "config.json"
        self.srv_file = self.tmp_path / "servers.json"

        self.cfg_mgr = ConfigManager(self.cfg_file)
        self.srv_mgr = ServerManager(self.srv_file)

        # Seed mock server in cache
        self.srv_mgr.save_cache([
            Server(id="srv-1", name="Germany Server", link=SAMPLE_LINK, country="Germany", code="DE", protocol="vless")
        ])

        self.vpn_mgr = VpnManager(self.cfg_mgr, self.srv_mgr)

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_initial_state_is_disconnected(self):
        state = self.vpn_mgr.get_state()
        self.assertEqual(state.status, "disconnected")
        self.assertIsNone(state.pid)

    @patch("nexora.vpn.find_vpn_binary")
    @patch("nexora.vpn.subprocess.Popen")
    @patch("nexora.vpn.set_linux_proxy")
    @patch("nexora.vpn.is_pid_alive")
    @patch.object(VpnManager, "_check_connectivity", return_value=True)
    @patch.object(VpnManager, "get_public_ip", return_value="198.51.100.1 (Germany)")
    def test_connect_success(self, mock_ip, mock_probe, mock_alive, mock_proxy, mock_popen, mock_bin):
        mock_bin.return_value = ("/usr/bin/v2ray", "v2ray")
        mock_proc = MagicMock()
        mock_proc.pid = 99999
        mock_popen.return_value = mock_proc
        mock_alive.return_value = True

        state = self.vpn_mgr.connect("germany")
        self.assertEqual(state.status, "connected")
        self.assertEqual(state.pid, 99999)
        self.assertIn("Germany", state.server_name)
        self.assertEqual(state.public_ip, "198.51.100.1 (Germany)")
        mock_proxy.assert_called_with(True, http_port=10809, socks_port=10808)

    @patch("nexora.vpn.is_pid_alive")
    @patch("nexora.vpn.set_linux_proxy")
    def test_unexpected_death_detection(self, mock_proxy, mock_alive):
        # Save a fake running state
        running_state = VpnState(
            status="connected",
            server_id="srv-1",
            server_name="Germany Server",
            pid=88888,
            connected_at=1000.0
        )
        self.vpn_mgr._save_state(running_state)

        # Mock that pid is NOT alive
        mock_alive.return_value = False

        state = self.vpn_mgr.get_state()
        self.assertEqual(state.status, "disconnected")
        self.assertIsNone(state.pid)
        mock_proxy.assert_called_with(False)

    @patch("os.kill")
    @patch("nexora.vpn.set_linux_proxy")
    def test_disconnect_clean_shutdown(self, mock_proxy, mock_kill):
        running_state = VpnState(
            status="connected",
            server_id="srv-1",
            server_name="Germany Server",
            pid=77777,
            connected_at=1000.0
        )
        self.vpn_mgr._save_state(running_state)

        state = self.vpn_mgr.disconnect()
        self.assertEqual(state.status, "disconnected")
        self.assertIsNone(state.pid)
        mock_proxy.assert_called_with(False)

if __name__ == "__main__":
    unittest.main()
