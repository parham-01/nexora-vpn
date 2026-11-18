"""
Master command-line interface for Nexora VPN on Linux.
"""

import sys
import argparse
from typing import Optional, List

from . import __version__, __app_name__
from .constants import (
    EXIT_SUCCESS,
    EXIT_GENERAL_ERROR,
    EXIT_INVALID_INPUT,
    EXIT_AUTH_FAILED,
    EXIT_CONNECTION_ERROR,
    EXIT_INSUFFICIENT_PRIVILEGES,
    EXIT_SERVICE_UNAVAILABLE,
)
from .errors import NexoraException, InvalidInputError, AuthError, ConnectionError, PermissionError, ServiceUnavailableError
from .config import ConfigManager
from .security import CredentialStore, prompt_password
from .auth import AuthManager
from .servers import ServerManager
from .vpn import VpnManager
from .firefox import FirefoxManager
from .logger import logger
from .ui import (
    c,
    print_json,
    log_stderr,
    print_header,
    print_success,
    print_info,
    print_warning,
    print_error,
    format_table,
)

def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="Machine-readable JSON output")

    parser = argparse.ArgumentParser(
        prog="nexora",
        description="Nexora VPN — Professional Linux CLI Client",
        parents=[common],
        add_help=True
    )
    parser.add_argument("--version", "-v", action="store_true", help="Show program version")

    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # help command
    subparsers.add_parser("help", parents=[common], help="Display help manual")

    # version command
    subparsers.add_parser("version", parents=[common], help="Show version information")

    # login command
    login_p = subparsers.add_parser("login", parents=[common], help="Log in to your Nexora account")
    login_p.add_argument("--email", "-u", type=str, help="Account email address")
    login_p.add_argument("--password", "-p", type=str, help="Account password (prefer interactive prompt)")

    # logout command
    subparsers.add_parser("logout", parents=[common], help="Log out of the active account")

    # account command
    subparsers.add_parser("account", parents=[common], help="Show current account details and token status")

    # servers command
    servers_p = subparsers.add_parser("servers", parents=[common], help="List available VPN servers")
    servers_p.add_argument("--country", "-c", type=str, help="Filter servers by country name or code (e.g. germany, france, de, fr)")

    # connect command
    connect_p = subparsers.add_parser("connect", parents=[common], help="Connect to a VPN server")
    connect_p.add_argument("--server", "-s", type=str, help="Server ID or country name (e.g. germany, france)")

    # disconnect command
    subparsers.add_parser("disconnect", parents=[common], help="Disconnect from active VPN tunnel")

    # reconnect command
    subparsers.add_parser("reconnect", parents=[common], help="Reconnect to current or last used server")

    # status command
    subparsers.add_parser("status", parents=[common], help="Show connection status, server, IP, and uptime")

    # ip command
    subparsers.add_parser("ip", parents=[common], help="Check current public IP and location")

    # ping command
    subparsers.add_parser("ping", parents=[common], help="Test latency to VPN servers")

    # logs command
    logs_p = subparsers.add_parser("logs", parents=[common], help="View recent technical logs")
    logs_p.add_argument("--lines", "-n", type=int, default=30, help="Number of log lines to show (default: 30)")

    # config command
    config_p = subparsers.add_parser("config", parents=[common], help="Manage application settings")
    config_sub = config_p.add_subparsers(dest="config_action", help="Config actions")
    config_sub.add_parser("show", parents=[common], help="Show current configuration")
    config_sub.add_parser("reset", parents=[common], help="Reset settings to factory defaults")
    
    cfg_get_p = config_sub.add_parser("get", parents=[common], help="Get a configuration setting")
    cfg_get_p.add_argument("key", type=str, help="Configuration key name")

    cfg_set_p = config_sub.add_parser("set", parents=[common], help="Set a configuration setting")
    cfg_set_p.add_argument("key", type=str, help="Configuration key name")
    cfg_set_p.add_argument("value", type=str, help="Configuration value")

    # firefox command
    firefox_p = subparsers.add_parser("firefox", parents=[common], help="Mozilla Firefox VPN module")
    ff_sub = firefox_p.add_subparsers(dest="firefox_action", help="Firefox commands")

    ff_login_p = ff_sub.add_parser("login", parents=[common], help="Log in to Mozilla Firefox VPN account")
    ff_login_p.add_argument("--email", "-u", type=str, help="Mozilla account email")
    ff_login_p.add_argument("--password", "-p", type=str, help="Mozilla account password")

    ff_sub.add_parser("logout", parents=[common], help="Log out from Firefox VPN account")
    ff_sub.add_parser("status", parents=[common], help="Show Firefox core status and accounts")
    ff_sub.add_parser("servers", parents=[common], help="List Firefox VPN locations")

    ff_connect_p = ff_sub.add_parser("connect", parents=[common], help="Connect to Firefox VPN server")
    ff_connect_p.add_argument("--server", "-s", type=str, help="Country code or name (e.g. germany, france)")

    ff_sub.add_parser("disconnect", parents=[common], help="Disconnect Firefox VPN")

    return parser

class CliApp:
    def __init__(self):
        self.config_mgr = ConfigManager()
        self.cred_store = CredentialStore()
        self.auth_mgr = AuthManager(self.config_mgr, self.cred_store)
        self.server_mgr = ServerManager()
        self.vpn_mgr = VpnManager(self.config_mgr, self.server_mgr)
        self.firefox_mgr = FirefoxManager()

    def run(self, args: Optional[List[str]] = None) -> int:
        parser = build_parser()
        parsed = parser.parse_args(args)

        is_json = getattr(parsed, "json", False)

        try:
            if parsed.version:
                return self.cmd_version(is_json)

            cmd = parsed.command

            if not cmd:
                # Default command: display status overview
                return self.cmd_status(is_json)

            if cmd == "help":
                parser.print_help()
                return EXIT_SUCCESS

            if cmd == "version":
                return self.cmd_version(is_json)

            if cmd == "login":
                return self.cmd_login(parsed.email, parsed.password, is_json)

            if cmd == "logout":
                return self.cmd_logout(is_json)

            if cmd == "account":
                return self.cmd_account(is_json)

            if cmd == "servers":
                return self.cmd_servers(parsed.country, is_json)

            if cmd == "connect":
                return self.cmd_connect(parsed.server, is_json)

            if cmd == "disconnect":
                return self.cmd_disconnect(is_json)

            if cmd == "reconnect":
                return self.cmd_reconnect(is_json)

            if cmd == "status":
                return self.cmd_status(is_json)

            if cmd == "ip":
                return self.cmd_ip(is_json)

            if cmd == "ping":
                return self.cmd_ping(is_json)

            if cmd == "logs":
                return self.cmd_logs(parsed.lines, is_json)

            if cmd == "config":
                action = parsed.config_action or "show"
                if action == "reset":
                    return self.cmd_config_reset(is_json)
                if action == "get":
                    return self.cmd_config_get(parsed.key, is_json)
                if action == "set":
                    return self.cmd_config_set(parsed.key, parsed.value, is_json)
                return self.cmd_config_show(is_json)

            if cmd == "firefox":
                return self.cmd_firefox(parsed, is_json)

            print_error(f"Unknown command '{cmd}'. Use 'nexora help' for guidance.")
            return EXIT_INVALID_INPUT

        except NexoraException as e:
            if is_json:
                print_json({"error": e.message, "code": e.exit_code})
            else:
                print_error(e.message)
            return e.exit_code

        except KeyboardInterrupt:
            if not is_json:
                print("\nOperation cancelled by user.")
            return EXIT_SUCCESS

        except Exception as e:
            logger.error(f"Unexpected CLI error: {e}")
            if is_json:
                print_json({"error": str(e), "code": EXIT_GENERAL_ERROR})
            else:
                print_error(f"Unexpected error: {e}")
            return EXIT_GENERAL_ERROR

    def cmd_version(self, is_json: bool) -> int:
        if is_json:
            print_json({"app": __app_name__, "version": __version__})
        else:
            print(f"{__app_name__} version {__version__}")
        return EXIT_SUCCESS

    def cmd_login(self, email: Optional[str], password: Optional[str], is_json: bool) -> int:
        if not email:
            if is_json:
                raise InvalidInputError("Email is required in non-interactive / JSON mode (--email).")
            email = input("Enter email: ").strip()

        if not email:
            raise InvalidInputError("Email address cannot be empty.")

        if not password:
            if is_json:
                raise InvalidInputError("Password is required in non-interactive / JSON mode (--password).")
            password = prompt_password("Enter password: ")

        if not password:
            raise InvalidInputError("Password cannot be empty.")

        account = self.auth_mgr.login(email, password)

        if is_json:
            print_json(account.to_dict())
        else:
            print_success(f"Logged in successfully as {account.email}")
            print_info(f"Account ID: {account.account_id}")
            print_info(f"Security: Saved to {account.storage_type}")

        return EXIT_SUCCESS

    def cmd_logout(self, is_json: bool) -> int:
        self.auth_mgr.logout()
        if is_json:
            print_json({"logged_out": True})
        else:
            print_success("Logged out successfully. Credentials cleared.")
        return EXIT_SUCCESS

    def cmd_account(self, is_json: bool) -> int:
        acc = self.auth_mgr.get_account_info()
        if is_json:
            print_json(acc.to_dict())
        else:
            print_header("Nexora Account")
            if acc.logged_in:
                print(f"Status:      {c.GREEN}Logged in{c.RESET}")
                print(f"Email:       {acc.email}")
                print(f"Account ID:  {acc.account_id}")
                print(f"Device ID:   {acc.device_id}")
                print(f"Storage:     {acc.storage_type}")
                if acc.is_expired():
                    print(f"Token:       {c.YELLOW}Expired{c.RESET}")
                else:
                    print(f"Token:       {c.GREEN}Valid{c.RESET}")
            else:
                print(f"Status:      {c.YELLOW}Not logged in{c.RESET}")
                print(f"Device ID:   {acc.device_id}")
                print_info("Use 'nexora login' to authenticate.")
        return EXIT_SUCCESS

    def cmd_servers(self, country: Optional[str], is_json: bool) -> int:
        sb_url = self.config_mgr.get("sb_url")
        sb_key = self.config_mgr.get("sb_key")

        servers = self.server_mgr.fetch_servers(sb_url, sb_key)
        if country:
            servers = self.server_mgr.filter_by_country(servers, country)

        if is_json:
            print_json([s.to_dict() for s in servers])
        else:
            print_header("Available Servers")
            if not servers:
                print_warning(f"No servers found{' for country ' + country if country else ''}.")
                return EXIT_SUCCESS

            headers = ["ID", "Country", "Name", "Protocol", "Transport"]
            rows = [
                [
                    s.id[:10] if len(s.id) > 10 else s.id,
                    f"{s.flag()} {s.country or 'Global'}",
                    s.name[:25] if len(s.name) > 25 else s.name,
                    s.protocol.upper() or "VPN",
                    s.transport or "tcp"
                ]
                for s in servers
            ]
            print(format_table(headers, rows))
            print(f"\nTotal: {len(servers)} servers")

        return EXIT_SUCCESS

    def cmd_connect(self, server_target: Optional[str], is_json: bool) -> int:
        if not is_json:
            print_info("Establishing secure VPN connection...")

        state = self.vpn_mgr.connect(server_target)

        if is_json:
            print_json(state.to_dict())
        else:
            print_success(f"Connected to {state.server_name}")
            print(f"Public IP: {state.public_ip}")
            print(f"DNS:       {state.dns_status}")

        return EXIT_SUCCESS

    def cmd_disconnect(self, is_json: bool) -> int:
        state = self.vpn_mgr.disconnect()
        if is_json:
            print_json(state.to_dict())
        else:
            print_success("VPN disconnected.")
        return EXIT_SUCCESS

    def cmd_reconnect(self, is_json: bool) -> int:
        if not is_json:
            print_info("Reconnecting...")
        state = self.vpn_mgr.reconnect()
        if is_json:
            print_json(state.to_dict())
        else:
            print_success(f"Reconnected to {state.server_name}")
            print(f"Public IP: {state.public_ip}")
        return EXIT_SUCCESS

    def cmd_status(self, is_json: bool) -> int:
        state = self.vpn_mgr.get_state()
        acc = self.auth_mgr.get_account_info()

        if is_json:
            data = state.to_dict()
            data["account"] = acc.to_dict()
            print_json(data)
        else:
            # Exact format specified in section 6 of requirements:
            # Nexora VPN
            # Account: Logged in
            # VPN: Connected
            # Server: Germany
            # Public IP: x.x.x.x
            # DNS: Active
            # Uptime: 00:25:14
            print_header("Nexora VPN")
            acc_str = f"{c.GREEN}Logged in{c.RESET}" if acc.logged_in else f"{c.YELLOW}Not logged in{c.RESET}"
            vpn_str = f"{c.GREEN}Connected{c.RESET}" if state.status == "connected" else f"{c.RED}Disconnected{c.RESET}"

            print(f"Account:   {acc_str}")
            print(f"VPN:       {vpn_str}")
            if state.status == "connected":
                print(f"Server:    {state.server_name}")
                print(f"Public IP: {state.public_ip}")
                print(f"DNS:       {state.dns_status}")
                print(f"Uptime:    {state.uptime_formatted()}")
            else:
                print("Server:    None")
                print("Public IP: —")
                print("DNS:       Direct")
                print("Uptime:    00:00:00")

        return EXIT_SUCCESS

    def cmd_ip(self, is_json: bool) -> int:
        state = self.vpn_mgr.get_state()
        proxy = f"http://127.0.0.1:{self.config_mgr.get('http_port', 10809)}" if state.status == "connected" else None
        details = self.vpn_mgr.get_ip_details(proxy)

        if is_json:
            print_json(details)
        else:
            print_header("Public IP & Location")
            print(f"IP:       {c.BOLD}{details.get('ip')}{c.RESET}")
            print(f"Country:  {details.get('flag')} {details.get('country')}")
            print(f"City:     {details.get('city')}")
            print(f"ISP:      {details.get('isp')}")
            print(f"Org:      {details.get('org')}")
            print(f"Tunnel:   {'Active (via VPN)' if state.status == 'connected' else 'Direct (No VPN)'}")

        return EXIT_SUCCESS

    def cmd_ping(self, is_json: bool) -> int:
        sb_url = self.config_mgr.get("sb_url")
        sb_key = self.config_mgr.get("sb_key")
        servers = self.server_mgr.fetch_servers(sb_url, sb_key)

        if not servers:
            servers = self.server_mgr.get_cached_servers()

        if not servers:
            raise ConnectionError("No servers available to ping.")

        results = []
        for s in servers[:10]:
            ms = self.server_mgr.ping_server(s)
            results.append({
                "id": s.id,
                "name": s.display_name(),
                "country": s.country,
                "ping_ms": ms
            })

        if is_json:
            print_json(results)
        else:
            print_header("Server Latency (Ping)")
            headers = ["Server", "Country", "Latency"]
            rows = [
                [
                    r["name"],
                    r["country"],
                    f"{r['ping_ms']} ms" if r["ping_ms"] > 0 else f"{c.RED}Timeout{c.RESET}"
                ]
                for r in results
            ]
            print(format_table(headers, rows))

        return EXIT_SUCCESS

    def cmd_logs(self, lines: int, is_json: bool) -> int:
        entries = logger.read_logs(limit=lines)
        if is_json:
            print_json({"lines": entries})
        else:
            print_header("Nexora Technical Logs")
            if not entries:
                print("No log entries recorded.")
            else:
                for line in entries:
                    print(line)
        return EXIT_SUCCESS

    def cmd_config_show(self, is_json: bool) -> int:
        cfg = self.config_mgr.to_dict()
        if is_json:
            print_json(cfg)
        else:
            print_header("Nexora Configuration")
            for k, v in cfg.items():
                print(f"{k:<20}: {v}")
        return EXIT_SUCCESS

    def cmd_config_get(self, key: str, is_json: bool) -> int:
        val = self.config_mgr.get(key)
        if is_json:
            print_json({"key": key, "value": val})
        else:
            print(f"{key}: {val}")
        return EXIT_SUCCESS

    def cmd_config_set(self, key: str, value: str, is_json: bool) -> int:
        # Type casting for bool/int
        parsed_val = value
        if value.lower() in ("true", "1", "yes"):
            parsed_val = True
        elif value.lower() in ("false", "0", "no"):
            parsed_val = False
        elif value.isdigit():
            parsed_val = int(value)

        self.config_mgr.set(key, parsed_val)
        if is_json:
            print_json({"updated": True, "key": key, "value": parsed_val})
        else:
            print_success(f"Config '{key}' updated to: {parsed_val}")
        return EXIT_SUCCESS

    def cmd_config_reset(self, is_json: bool) -> int:
        self.config_mgr.reset()
        if is_json:
            print_json({"reset": True, "config": self.config_mgr.to_dict()})
        else:
            print_success("Configuration reset to defaults.")
        return EXIT_SUCCESS

    def cmd_firefox(self, parsed: argparse.Namespace, is_json: bool) -> int:
        action = parsed.firefox_action
        if not action or action == "status":
            st = self.firefox_mgr.get_status()
            if is_json:
                print_json(st)
            else:
                print_header("Firefox VPN Status")
                pwr = st.get("power", False)
                print(f"Status:     {c.GREEN + 'Connected' + c.RESET if pwr else c.RED + 'Disconnected' + c.RESET}")
                print(f"Location:   {st.get('selection') or 'Recommended'}")
                print(f"Accounts:   {st.get('accounts_count', 0)}")
                for acc in st.get("accounts", []):
                    quota_mb = acc.get("quota_left_bytes", 0) / (1024 * 1024)
                    print(f"  • {acc.get('email')}: {acc.get('status')} ({quota_mb:.1f} MB remaining)")
            return EXIT_SUCCESS

        if action == "login":
            email = parsed.email
            password = parsed.password
            if not email:
                if is_json:
                    raise InvalidInputError("Email required for Firefox login (--email).")
                email = input("Mozilla email: ").strip()

            if not password:
                if is_json:
                    raise InvalidInputError("Password required for Firefox login (--password).")
                password = prompt_password("Mozilla password: ")

            def code_cb(prompt_type: str) -> str:
                return input(f"Enter verification code ({prompt_type}): ").strip()

            acc = self.firefox_mgr.login(email, password, code_callback=code_cb)
            if is_json:
                print_json(acc.to_dict())
            else:
                print_success(f"Firefox account added: {acc.email}")
            return EXIT_SUCCESS

        if action == "logout":
            self.firefox_mgr.logout()
            if is_json:
                print_json({"logged_out": True})
            else:
                print_success("Firefox account removed.")
            return EXIT_SUCCESS

        if action == "servers":
            locs = self.firefox_mgr.list_servers()
            if is_json:
                print_json([l.to_dict() for l in locs])
            else:
                print_header("Firefox VPN Locations")
                headers = ["Code", "Country", "Servers", "Latency"]
                rows = [
                    [
                        l.country_code,
                        f"{l.flag} {l.name}",
                        str(l.servers_count),
                        f"{l.ping_ms} ms" if l.ping_ms > 0 else "—"
                    ]
                    for l in locs
                ]
                print(format_table(headers, rows))
            return EXIT_SUCCESS

        if action == "connect":
            server_target = parsed.server
            self.firefox_mgr.connect(server_target)
            if is_json:
                print_json({"status": "connected", "server": server_target or "auto"})
            else:
                print_success(f"Firefox VPN connected to {server_target or 'optimal server'}.")
            return EXIT_SUCCESS

        if action == "disconnect":
            self.firefox_mgr.disconnect()
            if is_json:
                print_json({"status": "disconnected"})
            else:
                print_success("Firefox VPN disconnected.")
            return EXIT_SUCCESS

        print_error(f"Unknown Firefox command: {action}")
        return EXIT_INVALID_INPUT

def main():
    app = CliApp()
    sys.exit(app.run())

if __name__ == "__main__":
    main()
