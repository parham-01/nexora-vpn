"""
Tests for clean and machine-readable JSON output across CLI commands.
"""

import sys
import json
import io
import unittest
from pathlib import Path

CLI_DIR = Path(__file__).resolve().parent.parent / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from nexora.cli import CliApp

class TestJsonOutput(unittest.TestCase):
    def setUp(self):
        self.app = CliApp()

    def _run_and_capture(self, args):
        old_stdout = sys.stdout
        old_stderr = sys.stderr
        captured_out = io.StringIO()
        captured_err = io.StringIO()
        sys.stdout = captured_out
        sys.stderr = captured_err
        try:
            exit_code = self.app.run(args)
            return exit_code, captured_out.getvalue(), captured_err.getvalue()
        finally:
            sys.stdout = old_stdout
            sys.stderr = old_stderr

    def test_status_json_validity(self):
        code, out, _ = self._run_and_capture(["status", "--json"])
        self.assertEqual(code, 0)
        # Must parse as valid JSON
        data = json.loads(out)
        self.assertIn("status", data)
        self.assertIn("account", data)

    def test_servers_json_validity(self):
        code, out, _ = self._run_and_capture(["servers", "--json"])
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertIsInstance(data, list)

    def test_account_json_validity(self):
        code, out, _ = self._run_and_capture(["account", "--json"])
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertIn("logged_in", data)
        self.assertIn("device_id", data)

    def test_config_show_json_validity(self):
        code, out, _ = self._run_and_capture(["config", "show", "--json"])
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertIn("routing_mode", data)
        self.assertIn("http_port", data)

if __name__ == "__main__":
    unittest.main()
