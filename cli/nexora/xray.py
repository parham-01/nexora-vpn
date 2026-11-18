"""
Xray/V2Ray protocol link parser and configuration generator.
Reproduces 1:1 the exact logic, fragment dialer, routing, and stealth rules
from client/lib/xray_config.dart.
"""

import base64
import json
import urllib.parse
from typing import Optional, Dict, Any, List

from .models import LinkInfo

# De-obfuscated keys from xray_config.dart
# utf8.decode(base64Decode('c3BpZGVyWA==')) -> 'spiderX'
# utf8.decode(base64Decode('c3B4')) -> 'spx'
REALITY_PATH_KEY = base64.b64decode("c3BpZGVyWA==").decode("utf-8")
LEGACY_PATH_KEY = base64.b64decode("c3B4").decode("utf-8")

def _dec(s: str) -> str:
    try:
        return urllib.parse.unquote(s)
    except Exception:
        return s

def _b64(s: str) -> str:
    t = s.strip().replace("-", "+").replace("_", "/")
    # add padding
    missing = (4 - len(t) % 4) % 4
    t += "=" * missing
    return base64.b64decode(t).decode("utf-8")

def _first(*args) -> str:
    for x in args:
        if x:
            return str(x)
    return ""

def _int(v: Any, default: int) -> int:
    try:
        return int(v)
    except Exception:
        return default

def _stream(q: Dict[str, str], host: str) -> Dict[str, Any]:
    net = (q.get("type") or "tcp").lower()
    if net in ("raw", ""):
        net = "tcp"
    if net == "splithttp":
        net = "xhttp"

    sec = (q.get("security") or "none").lower()
    host_hdr = q.get("host") or ""

    s: Dict[str, Any] = {
        "network": net,
        "security": sec,
        "sockopt": {
            "tcpKeepAliveInterval": 15
        }
    }

    if sec == "tls":
        alpn = q.get("alpn") or ""
        s["tlsSettings"] = {
            "serverName": _first(q.get("sni"), host_hdr, host),
            "fingerprint": _first(q.get("fp"), "chrome"),
        }
        if alpn:
            s["tlsSettings"]["alpn"] = alpn.split(",")
        if q.get("allowInsecure") == "1" or q.get("insecure") == "1":
            s["tlsSettings"]["allowInsecure"] = True

    if sec == "reality":
        s["realitySettings"] = {
            "serverName": q.get("sni") or "",
            "fingerprint": _first(q.get("fp"), "chrome"),
            "publicKey": q.get("pbk") or "",
            "shortId": q.get("sid") or "",
            REALITY_PATH_KEY: _first(q.get("nex"), q.get(LEGACY_PATH_KEY)),
        }
        if q.get("pqv"):
            s["realitySettings"]["mldsa65Verify"] = q["pqv"]

    if net == "ws":
        s["wsSettings"] = {
            "path": _first(q.get("path"), "/"),
        }
        if host_hdr:
            s["wsSettings"]["headers"] = {"Host": host_hdr}
    elif net == "grpc":
        s["grpcSettings"] = {
            "serviceName": _first(q.get("serviceName"), q.get("path")),
            "multiMode": q.get("mode") == "multi"
        }
        if q.get("authority"):
            s["grpcSettings"]["authority"] = q["authority"]
    elif net == "httpupgrade":
        s["httpupgradeSettings"] = {
            "path": _first(q.get("path"), "/")
        }
        if host_hdr:
            s["httpupgradeSettings"]["host"] = host_hdr
    elif net == "xhttp":
        extra = {}
        if q.get("extra"):
            try:
                extra.update(json.loads(q["extra"]))
            except Exception:
                pass
        pad = _first(q.get("x_padding_bytes"))
        if pad and "xPaddingBytes" not in extra:
            extra["xPaddingBytes"] = pad
        s["xhttpSettings"] = {
            "path": _first(q.get("path"), "/"),
            "mode": _first(q.get("mode"), "auto")
        }
        if host_hdr:
            s["xhttpSettings"]["host"] = host_hdr
        if extra:
            s["xhttpSettings"]["extra"] = extra
    elif net == "kcp":
        s["kcpSettings"] = {
            "mtu": _int(q.get("mtu"), 1350),
            "tti": _int(q.get("tti"), 50),
            "uplinkCapacity": _int(q.get("uplinkCapacity"), 5),
            "downlinkCapacity": _int(q.get("downlinkCapacity"), 20),
            "congestion": q.get("congestion") in ("1", "true"),
            "readBufferSize": 2,
            "writeBufferSize": 2,
            "header": {"type": _first(q.get("headerType"), "none")}
        }
        if q.get("seed"):
            s["kcpSettings"]["seed"] = q["seed"]
        if q.get("fm"):
            try:
                s["finalmask"] = json.loads(q["fm"])
            except Exception:
                pass

    return s

def parse_link(link: str) -> LinkInfo:
    """Parse vless, vmess, trojan, or ss connection link."""
    l = link.strip()
    if "://" not in l:
        return LinkInfo("unknown", "", None)

    scheme, rest = l.split("://", 1)
    scheme = scheme.lower()

    hash_at = rest.find("#")
    frag = _dec(rest[hash_at + 1:]) if hash_at >= 0 else ""
    no_frag = rest[:hash_at] if hash_at >= 0 else rest

    try:
        if scheme == "vmess":
            m = json.loads(_b64(no_frag))
            net = str(m.get("net") or "tcp")
            host = str(m.get("add") or "")
            path = str(m.get("path") or "")
            q = {
                "type": net,
                "security": "tls" if str(m.get("tls")) == "tls" else "none",
                "sni": str(m.get("sni") or ""),
                "host": str(m.get("host") or ""),
                "path": path,
                "alpn": str(m.get("alpn") or ""),
                "fp": str(m.get("fp") or ""),
                "authority": str(m.get("authority") or ""),
                "serviceName": path,
                "headerType": "" if str(m.get("type")) == "none" else str(m.get("type") or ""),
                "mode": "" if str(m.get("type")) == "none" else str(m.get("type") or ""),
                "seed": path,
            }
            port = int(m.get("port") or 443)
            outbound = {
                "tag": "proxy",
                "protocol": "vmess",
                "settings": {
                    "vnext": [{
                        "address": host,
                        "port": port,
                        "users": [{
                            "id": str(m.get("id") or ""),
                            "alterId": int(m.get("aid") or 0),
                            "security": str(m.get("scy") or "auto"),
                            "level": 8,
                        }]
                    }]
                },
                "streamSettings": _stream(q, host)
            }
            name = str(m.get("ps") or frag)
            return LinkInfo("vmess", net, outbound, name=name, host=host, port=port)

        elif scheme in ("vless", "trojan"):
            # Format: id@host:port?query
            q_at = no_frag.find("?")
            cred_host = no_frag[:q_at] if q_at >= 0 else no_frag
            q_str = no_frag[q_at + 1:] if q_at >= 0 else ""
            q = {k: v[0] for k, v in urllib.parse.parse_qs(q_str).items()}

            at_idx = cred_host.rfind("@")
            user_pass = cred_host[:at_idx] if at_idx >= 0 else ""
            host_port = cred_host[at_idx + 1:] if at_idx >= 0 else cred_host

            colon = host_port.rfind(":")
            host = host_port[:colon].strip("[]") if colon >= 0 else host_port
            port = int(host_port[colon + 1:]) if colon >= 0 else 443

            net = (q.get("type") or "tcp").lower()
            if net == "splithttp":
                net = "xhttp"

            if scheme == "vless":
                user_obj = {
                    "id": user_pass,
                    "encryption": q.get("encryption", "none"),
                    "level": 8,
                }
                if q.get("flow"):
                    user_obj["flow"] = q["flow"]
                outbound = {
                    "tag": "proxy",
                    "protocol": "vless",
                    "settings": {
                        "vnext": [{
                            "address": host,
                            "port": port,
                            "users": [user_obj]
                        }]
                    },
                    "streamSettings": _stream(q, host)
                }
            else:  # trojan
                outbound = {
                    "tag": "proxy",
                    "protocol": "trojan",
                    "settings": {
                        "servers": [{
                            "address": host,
                            "port": port,
                            "password": user_pass,
                            "level": 8,
                        }]
                    },
                    "streamSettings": _stream(q, host)
                }
            return LinkInfo(scheme, net, outbound, name=frag, host=host, port=port)

        elif scheme == "ss":
            # Shadowsocks
            q_at = no_frag.find("?")
            cred_host = no_frag[:q_at] if q_at >= 0 else no_frag
            at_idx = cred_host.rfind("@")
            if at_idx >= 0:
                user_pass = cred_host[:at_idx]
                host_port = cred_host[at_idx + 1:]
                if ":" in user_pass:
                    method, password = user_pass.split(":", 1)
                else:
                    decoded = _b64(user_pass)
                    method, password = decoded.split(":", 1)
            else:
                decoded = _b64(cred_host)
                at_in = decoded.rfind("@")
                user_pass = decoded[:at_in]
                host_port = decoded[at_in + 1:]
                method, password = user_pass.split(":", 1)

            colon = host_port.rfind(":")
            host = host_port[:colon].strip("[]")
            port = int(host_port[colon + 1:])

            outbound = {
                "tag": "proxy",
                "protocol": "shadowsocks",
                "settings": {
                    "servers": [{
                        "address": host,
                        "port": port,
                        "method": method,
                        "password": password,
                        "level": 8,
                    }]
                }
            }
            return LinkInfo("ss", "tcp", outbound, name=frag, host=host, port=port)

    except Exception:
        pass

    return LinkInfo(scheme, "unknown", None)

def build_xray_config(
    link: str,
    http_port: int = 10809,
    socks_port: int = 10808,
    api_port: int = 10085,
    enable_fragment: bool = True,
    upstream_proxy: Optional[str] = None,
    routing_mode: str = "bypass_lan_iran",
    block_ads: bool = True,
) -> Optional[Dict[str, Any]]:
    """
    Constructs a complete, valid Xray/V2Ray configuration file.
    """
    info = parse_link(link)
    if not info.outbound:
        return None

    proxy_out = dict(info.outbound)
    is_udp_kcp = info.transport == "kcp"

    # Fragment dialer: bypasses SNI-filtering on mobile and ISP networks
    if enable_fragment and not is_udp_kcp and "dialerProxy" not in proxy_out:
        proxy_out["dialerProxy"] = "fragment"

    primary_tag = "proxy"

    config: Dict[str, Any] = {
        "log": {"loglevel": "warning"},
        "stats": {},
        "api": {
            "tag": "api",
            "services": ["StatsService"]
        },
        "policy": {
            "levels": {
                "0": {
                    "connIdle": 300,
                    "uplinkOnly": 2,
                    "downlinkOnly": 2,
                    "statsUserUplink": False,
                    "statsUserDownlink": False,
                    "bufferSize": 512,
                }
            },
            "system": {"statsOutboundUplink": True, "statsOutboundDownlink": True}
        },
        "inbounds": [
            {
                "tag": "http-in",
                "listen": "127.0.0.1",
                "port": http_port,
                "protocol": "http",
                "settings": {},
                "sniffing": {
                    "enabled": True,
                    "destOverride": ["http", "tls", "quic"],
                    "routeOnly": False,
                }
            },
            {
                "tag": "socks-in",
                "listen": "127.0.0.1",
                "port": socks_port,
                "protocol": "socks",
                "settings": {
                    "auth": "noauth",
                    "udp": True,
                },
                "sniffing": {
                    "enabled": True,
                    "destOverride": ["http", "tls", "quic"],
                    "routeOnly": False,
                }
            },
            {
                "tag": "api",
                "listen": "127.0.0.1",
                "port": api_port,
                "protocol": "dokodemo-door",
                "settings": {"address": "127.0.0.1"}
            }
        ],
        "outbounds": [
            proxy_out,
            {
                "tag": "fragment",
                "protocol": "freedom",
                "settings": {
                    "domainStrategy": "AsIs",
                    "fragment": {
                        "packets": "1-3",
                        "length": "100-200",
                        "interval": "10-20"
                    }
                }
            },
            {"tag": "direct", "protocol": "freedom", "settings": {}},
            {"tag": "block", "protocol": "blackhole", "settings": {}}
        ],
        "routing": {
            "domainStrategy": "IPIfNonMatch",
            "rules": [
                {
                    "type": "field",
                    "inboundTag": ["api"],
                    "outboundTag": "api"
                },
                # Block STUN/TURN WebRTC leaks
                {
                    "type": "field",
                    "port": "3478,5349",
                    "outboundTag": "block"
                },
                {
                    "type": "field",
                    "domain": [
                        "domain:stun.",
                        "domain:turn.",
                        "stun.l.google.com",
                        "stun.cloudflare.com",
                        "stun.services.mozilla.com",
                        "stun.stunprotocol.org"
                    ],
                    "outboundTag": "block"
                }
            ]
        }
    }

    rules = config["routing"]["rules"]

    if block_ads:
        rules.append({
            "type": "field",
            "domain": ["geosite:category-ads-all"],
            "outboundTag": "block"
        })

    if routing_mode == "bypass_lan_iran":
        rules.append({
            "type": "field",
            "ip": ["geoip:private", "geoip:ir"],
            "outboundTag": "direct"
        })
        rules.append({
            "type": "field",
            "domain": ["geosite:ir", "regexp:.*\\.ir$"],
            "outboundTag": "direct"
        })

    # High priority AI/cloud domains
    rules.append({
        "type": "field",
        "domain": [
            "domain:google.com",
            "domain:googleapis.com",
            "domain:gstatic.com",
            "domain:gemini.google.com",
            "domain:generativelanguage.googleapis.com",
            "domain:deepmind.google",
            "domain:aistudio.google.com",
            "domain:anthropic.com",
            "domain:claude.ai",
            "domain:openai.com",
            "domain:chatgpt.com",
            "domain:cloudflare.com"
        ],
        "outboundTag": primary_tag
    })

    return config
