"""
Terminal UI formatter with ANSI color support, loading spinners,
tables, and clean JSON machine-readable output mode.
"""

import os
import sys
import json
from typing import Any, List, Dict, Optional

class Colors:
    def __init__(self):
        self.enabled = self._should_enable_color()
        if self.enabled:
            self.RESET = "\033[0m"
            self.BOLD = "\033[1m"
            self.DIM = "\033[2m"
            self.RED = "\033[31m"
            self.GREEN = "\033[32m"
            self.YELLOW = "\033[33m"
            self.BLUE = "\033[34m"
            self.MAGENTA = "\033[35m"
            self.CYAN = "\033[36m"
            self.WHITE = "\033[37m"
        else:
            self.RESET = ""
            self.BOLD = ""
            self.DIM = ""
            self.RED = ""
            self.GREEN = ""
            self.YELLOW = ""
            self.BLUE = ""
            self.MAGENTA = ""
            self.CYAN = ""
            self.WHITE = ""

    def _should_enable_color(self) -> bool:
        if "NO_COLOR" in os.environ:
            return False
        if os.environ.get("TERM") == "dumb":
            return False
        return sys.stdout.isatty()

c = Colors()

def print_json(data: Any):
    """Output strictly valid JSON to stdout."""
    print(json.dumps(data, indent=2, ensure_ascii=False))
    sys.stdout.flush()

def log_stderr(msg: str):
    """Print auxiliary messages to stderr."""
    print(msg, file=sys.stderr)
    sys.stderr.flush()

def print_header(title: str = "Nexora VPN"):
    print(f"\n{c.BOLD}{c.CYAN}{title}{c.RESET}\n")

def print_success(msg: str):
    print(f"{c.GREEN}✓ {msg}{c.RESET}")

def print_info(msg: str):
    print(f"{c.BLUE}ℹ {msg}{c.RESET}")

def print_warning(msg: str):
    print(f"{c.YELLOW}⚠ {msg}{c.RESET}")

def print_error(msg: str):
    print(f"{c.RED}✗ {msg}{c.RESET}", file=sys.stderr)

def format_table(headers: List[str], rows: List[List[str]]) -> str:
    """Format tabular data cleanly."""
    if not rows:
        return "No entries found."

    col_widths = [len(h) for h in headers]
    for row in rows:
        for i, val in enumerate(row):
            if i < len(col_widths):
                col_widths[i] = max(col_widths[i], len(str(val)))

    header_line = "  ".join(f"{h:<{col_widths[i]}}" for i, h in enumerate(headers))
    sep_line = "  ".join("-" * col_widths[i] for i in range(len(headers)))

    formatted_rows = [
        "  ".join(f"{str(val):<{col_widths[i]}}" for i, val in enumerate(row))
        for row in rows
    ]

    return f"{c.BOLD}{header_line}{c.RESET}\n{c.DIM}{sep_line}{c.RESET}\n" + "\n".join(formatted_rows)
