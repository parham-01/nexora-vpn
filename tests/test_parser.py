"""
Tests for CLI argument parser and command routing.
"""

import sys
import unittest
from pathlib import Path

# Add cli directory to sys.path
CLI_DIR = Path(__file__).resolve().parent.parent / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from nexora.cli import build_parser

class TestCliParser(unittest.TestCase):
    def setUp(self):
        self.parser = build_parser()

    def test_version_flag(self):
        args = self.parser.parse_args(["--version"])
        self.assertTrue(args.version)

    def test_json_flag_root(self):
        args = self.parser.parse_args(["--json"])
        self.assertTrue(args.json)

    def test_status_command(self):
        args = self.parser.parse_args(["status"])
        self.assertEqual(args.command, "status")
        self.assertFalse(args.json)

    def test_status_json_flag(self):
        args = self.parser.parse_args(["status", "--json"])
        self.assertEqual(args.command, "status")
        self.assertTrue(args.json)

    def test_servers_country_flag(self):
        args = self.parser.parse_args(["servers", "--country", "germany"])
        self.assertEqual(args.command, "servers")
        self.assertEqual(args.country, "germany")

    def test_connect_server_flag(self):
        args = self.parser.parse_args(["connect", "--server", "france"])
        self.assertEqual(args.command, "connect")
        self.assertEqual(args.server, "france")

    def test_login_flags(self):
        args = self.parser.parse_args(["login", "--email", "user@test.com", "--password", "secret123"])
        self.assertEqual(args.command, "login")
        self.assertEqual(args.email, "user@test.com")
        self.assertEqual(args.password, "secret123")

    def test_config_show_and_reset(self):
        args_show = self.parser.parse_args(["config", "show"])
        self.assertEqual(args_show.command, "config")
        self.assertEqual(args_show.config_action, "show")

        args_reset = self.parser.parse_args(["config", "reset"])
        self.assertEqual(args_reset.command, "config")
        self.assertEqual(args_reset.config_action, "reset")

    def test_firefox_subcommands(self):
        args_st = self.parser.parse_args(["firefox", "status"])
        self.assertEqual(args_st.command, "firefox")
        self.assertEqual(args_st.firefox_action, "status")

        args_srv = self.parser.parse_args(["firefox", "servers"])
        self.assertEqual(args_srv.command, "firefox")
        self.assertEqual(args_srv.firefox_action, "servers")

        args_conn = self.parser.parse_args(["firefox", "connect", "--server", "germany"])
        self.assertEqual(args_conn.command, "firefox")
        self.assertEqual(args_conn.firefox_action, "connect")
        self.assertEqual(args_conn.server, "germany")

if __name__ == "__main__":
    unittest.main()
