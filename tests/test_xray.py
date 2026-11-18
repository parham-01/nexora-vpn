"""
Tests for Xray/V2Ray JSON configuration builder.
"""

import sys
import unittest
from pathlib import Path

CLI_DIR = Path(__file__).resolve().parent.parent / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from nexora.xray import build_xray_config, REALITY_PATH_KEY

SAMPLE_VLESS = "vless://27168be6-fb08-4fec-8b67-4bdcfe8f41d3@16.171.159.75:443?encryption=none&fp=chrome&pbk=n6Dq3RzIH4oGlnDWl5vz0Ad9rnYK5vtDTs2B4gCsJmQ&security=reality&sid=257f2adb&sni=www.amazonaws.com&type=xhttp&nex=/custom#Germany-Reality"

class TestXrayConfigBuilder(unittest.TestCase):
    def test_build_xray_config_structure(self):
        conf = build_xray_config(
            link=SAMPLE_VLESS,
            http_port=10809,
            socks_port=10808,
            enable_fragment=True,
            routing_mode="bypass_lan_iran",
            block_ads=True
        )

        self.assertIsNotNone(conf)
        self.assertIn("inbounds", conf)
        self.assertIn("outbounds", conf)
        self.assertIn("routing", conf)

        # Inbounds verification
        inbounds = {i["tag"]: i for i in conf["inbounds"]}
        self.assertIn("http-in", inbounds)
        self.assertIn("socks-in", inbounds)
        self.assertEqual(inbounds["http-in"]["port"], 10809)
        self.assertEqual(inbounds["socks-in"]["port"], 10808)

        # Outbounds verification
        outbounds = {o["tag"]: o for o in conf["outbounds"]}
        self.assertIn("proxy", outbounds)
        self.assertIn("fragment", outbounds)
        self.assertIn("direct", outbounds)
        self.assertIn("block", outbounds)

        # Verify fragment dialer chaining
        proxy = outbounds["proxy"]
        self.assertEqual(proxy["dialerProxy"], "fragment")

        # Verify Reality settings
        reality = proxy["streamSettings"]["realitySettings"]
        self.assertEqual(reality["serverName"], "www.amazonaws.com")
        self.assertEqual(reality["shortId"], "257f2adb")
        self.assertIn(REALITY_PATH_KEY, reality)
        self.assertEqual(reality[REALITY_PATH_KEY], "/custom")

        # Verify routing rules
        rules = conf["routing"]["rules"]
        # STUN block rule present
        self.assertTrue(any(r.get("outboundTag") == "block" and "3478,5349" in str(r.get("port", "")) for r in rules))
        # Ad block rule present
        self.assertTrue(any(r.get("outboundTag") == "block" and "geosite:category-ads-all" in r.get("domain", []) for r in rules))
        # Bypass Iran rule present
        self.assertTrue(any(r.get("outboundTag") == "direct" and "geoip:ir" in r.get("ip", []) for r in rules))

if __name__ == "__main__":
    unittest.main()
