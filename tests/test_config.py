"""
Tests for configuration management and reset behavior.
"""

import sys
import tempfile
import unittest
from pathlib import Path

CLI_DIR = Path(__file__).resolve().parent.parent / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from nexora.config import ConfigManager, DEFAULT_CONFIG

class TestConfigManager(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.cfg_file = Path(self.tmp_dir.name) / "config.json"
        self.mgr = ConfigManager(self.cfg_file)

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_default_config_generated(self):
        self.assertTrue(self.cfg_file.exists())
        self.assertEqual(self.mgr.get("routing_mode"), "bypass_lan_iran")
        self.assertTrue(self.mgr.get("block_ads"))
        self.assertTrue(self.mgr.get("stealth_fragment"))

    def test_set_and_persist(self):
        self.mgr.set("routing_mode", "global")
        self.mgr.set("block_ads", False)

        # Reload new manager from same file
        reloaded = ConfigManager(self.cfg_file)
        self.assertEqual(reloaded.get("routing_mode"), "global")
        self.assertFalse(reloaded.get("block_ads"))

    def test_reset_restores_defaults(self):
        self.mgr.set("routing_mode", "global")
        self.mgr.set("http_port", 9999)
        self.mgr.reset()

        self.assertEqual(self.mgr.get("routing_mode"), "bypass_lan_iran")
        self.assertEqual(self.mgr.get("http_port"), 10809)

if __name__ == "__main__":
    unittest.main()
