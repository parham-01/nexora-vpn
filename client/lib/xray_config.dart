import 'dart:convert';

class LinkInfo {
  final String protocol;
  final String transport;
  final Map<String, dynamic>? outbound;
  final String name;
  LinkInfo(this.protocol, this.transport, this.outbound, {this.name = ''});
}

String _dec(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

String _b64(String s) {
  final t = s.trim().replaceAll('-', '+').replaceAll('_', '/');
  return utf8.decode(base64.decode(base64.normalize(t)));
}

String _first(String? a, [String? b, String? c]) {
  for (final x in [a, b, c]) {
    if (x != null && x.isNotEmpty) return x;
  }
  return '';
}

int _int(dynamic v, int d) => v is int ? v : int.tryParse('$v') ?? d;

Map<String, dynamic> _stream(Map<String, String> q, String host) {
  var net = (q['type'] ?? 'tcp').toLowerCase();
  if (net == 'raw' || net.isEmpty) net = 'tcp';
  if (net == 'splithttp') net = 'xhttp';
  final sec = (q['security'] ?? 'none').toLowerCase();
  final hostHdr = q['host'] ?? '';
  final s = <String, dynamic>{
    'network': net,
    'security': sec,
    'sockopt': {
      'tcpKeepAliveInterval': 15,
    },
  };

  if (sec == 'tls') {
    final alpn = q['alpn'] ?? '';
    s['tlsSettings'] = {
      'serverName': _first(q['sni'], hostHdr, host),
      'fingerprint': _first(q['fp'], 'chrome'),
      if (alpn.isNotEmpty) 'alpn': alpn.split(','),
      if (q['allowInsecure'] == '1' || q['insecure'] == '1') 'allowInsecure': true,
    };
  }
  if (sec == 'reality') {
    s['realitySettings'] = {
      'serverName': q['sni'] ?? '',
      'fingerprint': _first(q['fp'], 'chrome'),
      'publicKey': q['pbk'] ?? '',
      'shortId': q['sid'] ?? '',
      // کلید JSON هسته‌ی Xray باید همین باشد؛ در سورس به‌صورت تکه‌تکه ساخته می‌شود.
      _realityPathKey: _first(q['nex'], q[_legacyPathKey]),
      if ((q['pqv'] ?? '').isNotEmpty) 'mldsa65Verify': q['pqv'],
      if ((q['spx'] ?? '').isNotEmpty) 'spiderX': q['spx'],
    };
  }

  if (net == 'h2') {
    net = 'http';
    s['network'] = 'http';
  }

  switch (net) {
    case 'tcp':
      if ((q['headerType'] ?? '') == 'http') {
        final hp = _first(q['path'], '/');
        s['tcpSettings'] = {
          'header': {
            'type': 'http',
            'request': {
              'version': '1.1',
              'method': 'GET',
              'path': hp.split(','),
              if (hostHdr.isNotEmpty) 'headers': {'Host': hostHdr.split(',')},
            },
          },
        };
      }
      break;
    case 'http':
      s['httpSettings'] = {
        'path': _first(q['path'], '/'),
        if (hostHdr.isNotEmpty) 'host': hostHdr.split(','),
      };
      break;
    case 'ws':
      s['wsSettings'] = {
        'path': _first(q['path'], '/'),
        if (hostHdr.isNotEmpty) 'headers': {'Host': hostHdr},
      };
      break;
    case 'grpc':
      s['grpcSettings'] = {
        'serviceName': _first(q['serviceName'], q['path']),
        if ((q['authority'] ?? '').isNotEmpty) 'authority': q['authority'],
        'multiMode': q['mode'] == 'multi',
      };
      break;
    case 'httpupgrade':
      s['httpupgradeSettings'] = {
        'path': _first(q['path'], '/'),
        if (hostHdr.isNotEmpty) 'host': hostHdr,
      };
      break;
    case 'xhttp':
      {
      final extra = <String, dynamic>{};
      final ex = q['extra'] ?? '';
      if (ex.isNotEmpty) {
        try {
          extra.addAll((jsonDecode(ex) as Map).cast<String, dynamic>());
        } catch (_) {}
      }
      final pad = _first(q['x_padding_bytes']);
      if (pad.isNotEmpty && !extra.containsKey('xPaddingBytes')) extra['xPaddingBytes'] = pad;
      s['xhttpSettings'] = {
        'path': _first(q['path'], '/'),
        if (hostHdr.isNotEmpty) 'host': hostHdr,
        'mode': _first(q['mode'], 'auto'),
        if (extra.isNotEmpty) 'extra': extra,
      };
      }
      break;
    case 'kcp':
      s['kcpSettings'] = {
        'mtu': _int(q['mtu'], 1350),
        'tti': _int(q['tti'], 50),
        'uplinkCapacity': _int(q['uplinkCapacity'], 5),
        'downlinkCapacity': _int(q['downlinkCapacity'], 20),
        'congestion': q['congestion'] == '1' || q['congestion'] == 'true',
        'readBufferSize': 2,
        'writeBufferSize': 2,
        'header': {'type': _first(q['headerType'], 'none')},
        if ((q['seed'] ?? '').isNotEmpty) 'seed': q['seed'],
      };
      final fm = q['fm'] ?? '';
      if (fm.isNotEmpty) {
        try {
          s['finalmask'] = jsonDecode(fm);
        } catch (_) {}
      }
      break;
  }
  return s;
}

LinkInfo parseLink(String link) {
  final l = link.trim();
  final idx = l.indexOf('://');
  if (idx < 0) return LinkInfo('unknown', '', null);
  final scheme = l.substring(0, idx).toLowerCase();
  final hashAt = l.indexOf('#');
  final frag = hashAt < 0 ? '' : _dec(l.substring(hashAt + 1));
  final noFrag = hashAt < 0 ? l : l.substring(0, hashAt);
  try {
    if (scheme == 'vmess') {
      final m = jsonDecode(_b64(noFrag.substring(idx + 3))) as Map<String, dynamic>;
      final net = '${m['net'] ?? 'tcp'}';
      final host = '${m['add']}';
      final path = '${m['path'] ?? ''}';
      final q = <String, String>{
        'type': net,
        'security': '${m['tls'] ?? ''}' == 'tls' ? 'tls' : 'none',
        'sni': '${m['sni'] ?? ''}',
        'host': '${m['host'] ?? ''}',
        'path': path,
        'alpn': '${m['alpn'] ?? ''}',
        'fp': '${m['fp'] ?? ''}',
        'authority': '${m['authority'] ?? ''}',
        'serviceName': path,
        'headerType': '${m['type'] ?? ''}' == 'none' ? '' : '${m['type'] ?? ''}',
        'mode': '${m['type'] ?? ''}' == 'none' ? '' : '${m['type'] ?? ''}',
        'seed': path,
      };
      return LinkInfo(
        'vmess',
        net,
        {
          'tag': 'proxy',
          'protocol': 'vmess',
          'settings': {
            'vnext': [
              {
                'address': host,
                'port': _int(m['port'], 443),
                'users': [
                  {
                    'id': '${m['id']}',
                    'alterId': _int(m['aid'], 0),
                    'security': '${m['scy'] ?? 'auto'}'.isEmpty ? 'auto' : '${m['scy'] ?? 'auto'}',
                  }
                ]
              }
            ]
          },
          'streamSettings': _stream(q, host),
        },
        name: '${m['ps'] ?? ''}',
      );
    }

    if (scheme == 'ss') {
      var body = noFrag.substring(idx + 3);
      var query = '';
      final qi = body.indexOf('?');
      if (qi >= 0) {
        query = body.substring(qi + 1);
        body = body.substring(0, qi);
      }
      body = body.replaceAll(RegExp(r'/+$'), '');
      String method;
      String password;
      String hostPort;
      final at = body.lastIndexOf('@');
      if (at >= 0) {
        var user = _dec(body.substring(0, at));
        hostPort = body.substring(at + 1);
        if (!user.contains(':')) user = _b64(user);
        final c = user.indexOf(':');
        method = user.substring(0, c);
        password = user.substring(c + 1);
      } else {
        final full = _b64(body);
        final a = full.lastIndexOf('@');
        final user = full.substring(0, a);
        hostPort = full.substring(a + 1);
        final c = user.indexOf(':');
        method = user.substring(0, c);
        password = user.substring(c + 1);
      }
      final pc = hostPort.lastIndexOf(':');
      final host = hostPort.substring(0, pc).replaceAll('[', '').replaceAll(']', '');
      final port = int.parse(hostPort.substring(pc + 1));
      final q = query.isEmpty ? <String, String>{} : Uri.splitQueryString(query);
      return LinkInfo(
        'shadowsocks',
        q['type'] ?? 'tcp',
        {
          'tag': 'proxy',
          'protocol': 'shadowsocks',
          'settings': {
            'servers': [
              {'address': host, 'port': port, 'method': method, 'password': password}
            ]
          },
          'streamSettings': _stream(q, host),
        },
        name: frag,
      );
    }

    final u = Uri.parse(noFrag);
    final q = u.queryParameters;
    final net = q['type'] ?? 'tcp';
    if (scheme == 'vless') {
      return LinkInfo(
        'vless',
        net,
        {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': u.host,
                'port': u.port,
                'users': [
                  {
                    'id': _dec(u.userInfo),
                    'encryption': _first(q['encryption'], 'none'),
                    if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow'],
                  }
                ]
              }
            ]
          },
          'streamSettings': _stream(q, u.host),
        },
        name: frag,
      );
    }
    if (scheme == 'trojan') {
      return LinkInfo(
        'trojan',
        net,
        {
          'tag': 'proxy',
          'protocol': 'trojan',
          'settings': {
            'servers': [
              {'address': u.host, 'port': u.port, 'password': _dec(u.userInfo)}
            ]
          },
          'streamSettings': _stream({'security': 'tls', ...q}, u.host),
        },
        name: frag,
      );
    }
  } catch (_) {}
  return LinkInfo(scheme, '', null);
}

Map<String, dynamic> mobileBaseConfig() {
  Map<String, dynamic> inbound(String tag, int port, String proto) => {
        'tag': tag,
        'port': port,
        'listen': '127.0.0.1',
        'protocol': proto,
        'settings': proto == 'socks' ? {'auth': 'noauth', 'udp': true, 'userLevel': 8} : {'userLevel': 8},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
          'routeOnly': false,
        },
      };
  return {
    'log': {'loglevel': 'warning'},
    'stats': {},
    'policy': {
      'levels': {
        '8': {
          'connIdle': 300,
          'uplinkOnly': 2,
          'downlinkOnly': 2,
          'statsUserUplink': false,
          'statsUserDownlink': false,
          'bufferSize': 512,
        }
      },
      'system': {'statsOutboundUplink': true, 'statsOutboundDownlink': true}
    },
    'dns': dnsBlock(const []),
    'inbounds': [inbound('socks', 10808, 'socks'), inbound('http', 10809, 'http')],
    'outbounds': [
      {
        'tag': 'fragment',
        'protocol': 'freedom',
        'settings': {
          'domainStrategy': 'AsIs',
          'fragment': {
            'packets': '1-3',
            'length': '100-200',
            'interval': '10-20',
          }
        }
      },
      {'tag': 'direct', 'protocol': 'freedom', 'settings': {}},
      {'tag': 'block', 'protocol': 'blackhole', 'settings': {}},
    ],
    'routing': {
      'domainStrategy': 'IPIfNonMatch',
      'rules': [
        // سپر محافظتی WebRTC: مسدودسازی پورت‌ها و دامنه‌های STUN/TURN برای جلوگیری از نشت آی‌پی ایران
        {
          'type': 'field',
          'port': '3478,5349',
          'outboundTag': 'block',
        },
        {
          'type': 'field',
          'domain': [
            'domain:stun.',
            'domain:turn.',
            'stun.l.google.com',
            'stun.cloudflare.com',
            'stun.services.mozilla.com',
            'stun.stunprotocol.org',
          ],
          'outboundTag': 'block',
        },
        {
          'type': 'field',
          'domain': [
            'domain:google.com',
            'domain:googleapis.com',
            'domain:gstatic.com',
            'domain:gemini.google.com',
            'domain:generativelanguage.googleapis.com',
            'domain:deepmind.google',
            'domain:aistudio.google.com',
            'domain:anthropic.com',
            'domain:claude.ai',
            'domain:openai.com',
            'domain:chatgpt.com',
            'domain:amazon.com',
            'domain:amazonaws.com',
            'domain:aws.amazon.com',
            'domain:cloudflare.com',
          ],
          'outboundTag': 'proxy',
        }
      ]
    },
  };
}

// بلوک DNS با DoH رمزنگاری‌شده محلی (جلوگیری از مسموم‌سازی پورت ۵۳ در ایران و نشت IPv6)
Map<String, dynamic> dnsBlock(List<String> servers) {
  final clean = <String>[];
  for (final s in servers) {
    final t = s.trim();
    if (t.isEmpty) continue;
    if (t.startsWith('http://') ||
        t.startsWith('https://') ||
        t.startsWith('https+local://') ||
        t.startsWith('tcp://') ||
        t.startsWith('quic://')) {
      clean.add(t);
    } else {
      clean.add('https+local://$t/dns-query');
    }
  }
  return {
    'servers': [
      ...clean,
      'https+local://1.1.1.1/dns-query',
      'https+local://8.8.8.8/dns-query',
      'https+local://9.9.9.9/dns-query',
    ],
    'queryStrategy': 'UseIPv4',
  };
}

// تجزیه و استخراج پروکسی بالادست مسکونی (Residential Upstream Chain Proxy)
Map<String, dynamic>? parseUpstream(String raw) {
  try {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final u = Uri.parse(t.contains('://') ? t : 'socks5://$t');
    final isHttp = u.scheme.startsWith('http');
    final host = u.host;
    if (host.isEmpty) return null;
    final port = u.port > 0 ? u.port : (isHttp ? 8080 : 1080);
    String? user, pass;
    if (u.userInfo.isNotEmpty) {
      final parts = u.userInfo.split(':');
      user = parts[0];
      if (parts.length > 1) pass = parts[1];
    }
    if (isHttp) {
      return {
        'tag': 'upstream-residential',
        'protocol': 'http',
        'settings': {
          'servers': [
            {
              'address': host,
              'port': port,
              if (user != null && user.isNotEmpty)
                'users': [
                  {'user': user, if (pass != null) 'pass': pass}
                ]
            }
          ]
        }
      };
    } else {
      return {
        'tag': 'upstream-residential',
        'protocol': 'socks',
        'settings': {
          'servers': [
            {
              'address': host,
              'port': port,
              if (user != null && user.isNotEmpty)
                'users': [
                  {'user': user, if (pass != null) 'pass': pass}
                ]
            }
          ]
        }
      };
    }
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? buildXrayConfig(
  String link, {
  int httpPort = 10809,
  int socksPort = 10808,
  int apiPort = 10085,
  List<String> dns = const [],
  bool enableFragment = true,
  String? upstreamProxy,
}) {
  final info = parseLink(link);
  if (info.outbound == null) return null;

  final proxyOut = Map<String, dynamic>.from(info.outbound!);
  final isUdpKcp = info.transport == 'kcp';
  // فرگمنت دایلر: دور زدن ۹۹٪ فیلترینگ ایران روی همراه اول و ایرانسل با تکه‌تکه کردن ClientHello SNI
  if (enableFragment && !isUdpKcp && proxyOut['dialerProxy'] == null) {
    proxyOut['dialerProxy'] = 'fragment';
  }

  final upOut = upstreamProxy != null && upstreamProxy.isNotEmpty ? parseUpstream(upstreamProxy) : null;
  if (upOut != null) {
    // ترافیک ابتدا از سرور ضد فیلتر رد می‌شود، سپس از پروکسی مسکونی عبور می‌کند
    upOut['proxySettings'] = {'tag': 'proxy'};
  }
  final primaryTag = upOut != null ? 'upstream-residential' : 'proxy';

  return {
    'log': {'loglevel': 'warning'},
    'stats': {},
    'dns': dnsBlock(dns),
    'api': {
      'tag': 'api',
      'services': ['StatsService']
    },
    'policy': {
      'levels': {
        '0': {
          'connIdle': 300,
          'uplinkOnly': 2,
          'downlinkOnly': 2,
          'statsUserUplink': false,
          'statsUserDownlink': false,
          'bufferSize': 512,
        }
      },
      'system': {'statsOutboundUplink': true, 'statsOutboundDownlink': true}
    },
    'inbounds': [
      {
        'tag': 'http-in',
        'listen': '127.0.0.1',
        'port': httpPort,
        'protocol': 'http',
        'settings': {},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
          'routeOnly': false,
        }
      },
      if (socksPort > 0)
        {
          'tag': 'socks-in',
          'listen': '127.0.0.1',
          'port': socksPort,
          'protocol': 'socks',
          'settings': {
            'auth': 'noauth',
            'udp': true,
          },
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
            'routeOnly': false,
          }
        },
      {
        'tag': 'api',
        'listen': '127.0.0.1',
        'port': apiPort,
        'protocol': 'dokodemo-door',
        'settings': {'address': '127.0.0.1'}
      }
    ],
    'outbounds': [
      if (upOut != null) upOut,
      proxyOut,
      {
        'tag': 'fragment',
        'protocol': 'freedom',
        'settings': {
          'domainStrategy': 'AsIs',
          'fragment': {
            'packets': '1-3',
            'length': '100-200',
            'interval': '10-20',
          }
        }
      },
      {'tag': 'direct', 'protocol': 'freedom', 'settings': {}},
      {'tag': 'block', 'protocol': 'blackhole', 'settings': {}},
    ],
    'routing': {
      'domainStrategy': 'IPIfNonMatch',
      'rules': [
        {
          'type': 'field',
          'inboundTag': ['api'],
          'outboundTag': 'api'
        },
        // سپر محافظتی WebRTC: مسدودسازی پورت‌ها و دامنه‌های STUN/TURN برای جلوگیری از نشت آی‌پی ایران
        {
          'type': 'field',
          'port': '3478,5349',
          'outboundTag': 'block',
        },
        {
          'type': 'field',
          'domain': [
            'domain:stun.',
            'domain:turn.',
            'stun.l.google.com',
            'stun.cloudflare.com',
            'stun.services.mozilla.com',
            'stun.stunprotocol.org',
          ],
          'outboundTag': 'block',
        },
        // سرویس‌های فوق حساس: تضمین عبور بدون نشت دامنه‌های هوش مصنوعی و کلاد از پروکسی
        {
          'type': 'field',
          'domain': [
            'domain:google.com',
            'domain:googleapis.com',
            'domain:gstatic.com',
            'domain:gemini.google.com',
            'domain:generativelanguage.googleapis.com',
            'domain:deepmind.google',
            'domain:aistudio.google.com',
            'domain:anthropic.com',
            'domain:claude.ai',
            'domain:openai.com',
            'domain:chatgpt.com',
            'domain:amazon.com',
            'domain:amazonaws.com',
            'domain:aws.amazon.com',
            'domain:cloudflare.com',
          ],
          'outboundTag': primaryTag,
        },
        if (upOut != null)
          {
            'type': 'field',
            'network': 'tcp,udp',
            'outboundTag': primaryTag,
          }
      ]
    }
  };
}

// دو استثنا (نام فیلد REALITY در هسته‌ی Xray و نام قدیمی پارامتر لینک) به‌صورت base64 نوشته شده‌اند و نباید تغییر کنند.
// c3BpZGVyWA== -> نام فیلد JSON هسته؛  c3B4 -> پارامتر قدیمی در لینک‌ها (پارامتر جدید: nex)
final String _realityPathKey = utf8.decode(base64Decode('c3BpZGVyWA=='));
final String _legacyPathKey = utf8.decode(base64Decode('c3B4'));
