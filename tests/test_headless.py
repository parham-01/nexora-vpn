"""
Tests for headless Linux and non-graphical environment operation (SSH / TTY).
"""

import os
import sys
import unittest
from pathlib import Path

CLI_DIR = Path(__file__).resolve().parent.parent / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from nexora.ui import Colors
from nexora.proxy import set_linux_proxy

class TestHeadlessExecution(unittest.TestCase):
    def test_colors_disabled_when_no_color_env_set(self):
        old_env = os.environ.get("NO_COLOR")
        try:
            os.environ["NO_COLOR"] = "1"
            c = Colors()
            self.assertFalse(c.enabled)
            self.assertEqual(c.RED, "")
            self.assertEqual(c.GREEN, "")
        finally:
            if old_env is not None:
                os.environ["NO_COLOR"] = old_env
            else:
                os.environ.pop("NO_COLOR", None)

    def test_colors_disabled_when_term_dumb(self):
        old_term = os.environ.get("TERM")
        try:
            os.environ["TERM"] = "dumb"
            c = Colors()
            self.assertFalse(c.enabled)
        finally:
            if old_term is not None:
                os.environ["TERM"] = old_term
            else:
                os.environ.pop("TERM", None)

    def test_proxy_setup_in_headless_environment_does_not_crash(self):
        # Unset display variables to simulate headless server
        old_disp = os.environ.pop("DISPLAY", None)
        old_wayland = os.environ.pop("WAYLAND_DISPLAY", None)
        try:
            # Must complete without throwing any exception
            set_linux_proxy(True)
            set_linux_proxy(False)
        finally:
            if old_disp:
                os.environ["DISPLAY"] = old_disp
            if old_wayland:
                os.environ["WAYLAND_DISPLAY"] = old_wayland

if __name__ == "__main__":
    unittest.main()
