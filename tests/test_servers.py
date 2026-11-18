"""
Tests for server fetching, caching, country filtering, and link parsing.
"""

import sys
import tempfile
import unittest
from pathlib import Path

CLI_DIR = Path(__file__).resolve().parent.parent / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from nexora.models import Server
from nexora.servers import ServerManager
from nexora.xray import parse_link

SAMPLE_VLESS = "vless://27168be6-fb08-4fec-8b67-4bdcfe8f41d3@16.171.159.75:443?encryption=none&fp=chrome&pbk=n6Dq3RzIH4oGlnDWl5vz0Ad9rnYK5vtDTs2B4gCsJmQ&security=reality&sid=257f2adb&sni=www.amazonaws.com&type=xhttp#Germany-Reality"
SAMPLE_VMESS = "vmess://ewogICJhZGQiOiAiMTYuMTcxLjE1OS43NSIsCiAgImlkIjogIjI3MTY4YmU2LWZiMDgtNGZlYy04YjY3LTRiZGNmZThmNDFkMyIsCiAgIm5ldCI6ICJ3cyIsCiAgInBhdGgiOiAiL3ZwbiIsCiAgInBvcnQiOiA0NDMsCiAgInBzIjogIkZyYW5jZS1XUyIsCiAgInNjeSI6ICJhdXRvIiwKICAidGxzIjogInRscyIKfQ=="
SAMPLE_TROJAN = "trojan://password123@1.2.3.4:443?security=tls&sni=example.com&type=tcp#Netherlands-Trojan"

class TestServersAndLinks(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.cache_file = Path(self.tmp_dir.name) / "servers.json"
        self.mgr = ServerManager(self.cache_file)

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_parse_vless_link(self):
        info = parse_link(SAMPLE_VLESS)
        self.assertEqual(info.protocol, "vless")
        self.assertEqual(info.transport, "xhttp")
        self.assertEqual(info.host, "16.171.159.75")
        self.assertEqual(info.port, 443)
        self.assertIsNotNone(info.outbound)
        self.assertEqual(info.outbound["protocol"], "vless")

    def test_parse_vmess_link(self):
        info = parse_link(SAMPLE_VMESS)
        self.assertEqual(info.protocol, "vmess")
        self.assertEqual(info.transport, "ws")
        self.assertEqual(info.host, "16.171.159.75")
        self.assertEqual(info.port, 443)
        self.assertIsNotNone(info.outbound)
        self.assertEqual(info.name, "France-WS")

    def test_parse_trojan_link(self):
        info = parse_link(SAMPLE_TROJAN)
        self.assertEqual(info.protocol, "trojan")
        self.assertEqual(info.host, "1.2.3.4")
        self.assertEqual(info.port, 443)

    def test_filter_by_country(self):
        servers = [
            Server(id="1", name="DE Server", link=SAMPLE_VLESS, country="Germany", code="DE"),
            Server(id="2", name="FR Server", link=SAMPLE_VMESS, country="France", code="FR"),
            Server(id="3", name="NL Server", link=SAMPLE_TROJAN, country="Netherlands", code="NL"),
        ]

        de_res = self.mgr.filter_by_country(servers, "germany")
        self.assertEqual(len(de_res), 1)
        self.assertEqual(de_res[0].country, "Germany")

        de_code_res = self.mgr.filter_by_country(servers, "de")
        self.assertEqual(len(de_code_res), 1)
        self.assertEqual(de_code_res[0].country, "Germany")

        fr_res = self.mgr.filter_by_country(servers, "france")
        self.assertEqual(len(fr_res), 1)
        self.assertEqual(fr_res[0].country, "France")

    def test_cache_servers(self):
        servers = [
            Server(id="1", name="DE Server", link=SAMPLE_VLESS, country="Germany", code="DE"),
        ]
        self.mgr.save_cache(servers)
        self.assertTrue(self.cache_file.exists())

        loaded = self.mgr.get_cached_servers()
        self.assertEqual(len(loaded), 1)
        self.assertEqual(loaded[0].id, "1")
        self.assertEqual(loaded[0].name, "DE Server")

if __name__ == "__main__":
    unittest.main()
