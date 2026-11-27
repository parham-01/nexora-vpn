import 'dart:convert';
import 'singbox_config.dart';
import 'store.dart';

class LinkInfo {
  final String protocol;
  final String transport;
  final Map<String, dynamic>? outbound;
  final String name;
  final String engine;
  LinkInfo(this.protocol, this.transport, this.outbound, {this.name = '', this.engine = 'xray'});
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
  final s = <String, dynamic>{'network': net, 'security': sec};

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
      _realityPathKey: _first(q['nex'], q[_legacyPathKey]),
      if ((q['pqv'] ?? '').isNotEmpty) 'mldsa65Verify': q['pqv'],
    };
  }

  switch (net) {
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
  final eng = singboxEngineOf(scheme);
  if (eng != 'xray') {
    final sb = parseSingboxLink(l);
    if (sb != null) return LinkInfo(sb.protocol, sb.transport, sb.body, name: sb.name, engine: sb.protocol == 'amneziawg' ? 'amneziawg' : 'singbox');
    return LinkInfo(scheme, '', null);
  }
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
          'destOverride': ['http', 'tls']
        },
      };
  return {
    'log': {'loglevel': 'warning'},
    'stats': {},
    'policy': {
      'levels': {
        '8': {'connIdle': 300, 'uplinkOnly': 1, 'downlinkOnly': 1, 'statsUserUplink': false, 'statsUserDownlink': false, 'bufferSize': 10}
      },
      'system': {'statsOutboundUplink': true, 'statsOutboundDownlink': true}
    },
    'dns': {
      'servers': ['1.1.1.1', '8.8.8.8']
    },
    'inbounds': [inbound('socks', 10808, 'socks'), inbound('http', 10809, 'http')],
    'outbounds': [
      {'tag': 'direct', 'protocol': 'freedom', 'settings': {}},
      {'tag': 'block', 'protocol': 'blackhole', 'settings': {}},
    ],
    'routing': {'domainStrategy': 'IPIfNonMatch', 'rules': []},
  };
}

Map<String, dynamic> dnsBlock(List<String> servers, {bool safe = false}) => {
      'servers': [...servers, '1.1.1.1', '8.8.8.8'],
      'queryStrategy': 'UseIP',
    };

Map<String, dynamic>? parseUpstream(String raw) {
  try {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final u = Uri.parse(t.contains('://') ? t : 'socks5://$t');
    final isHttp = u.scheme.startsWith('http');
    if (u.host.isEmpty) return null;
    final port = u.port > 0 ? u.port : (isHttp ? 8080 : 1080);
    String? user, pass;
    if (u.userInfo.isNotEmpty) {
      final parts = u.userInfo.split(':');
      user = parts[0];
      if (parts.length > 1) pass = parts[1];
    }
    return {
      'tag': 'upstream-residential',
      'protocol': isHttp ? 'http' : 'socks',
      'settings': {
        'servers': [
          {
            'address': u.host,
            'port': port,
            if (user != null && user.isNotEmpty)
              'users': [
                {'user': user, if (pass != null) 'pass': pass}
              ]
          }
        ]
      }
    };
  } catch (_) {
    return null;
  }
}

const List<List<String>> _kDnsSets = [
  [],
  ['1.1.1.1', '1.0.0.1'],
  ['8.8.8.8', '8.8.4.4'],
  ['9.9.9.9', '149.112.112.112'],
  ['94.140.14.14', '94.140.15.15'],
];

Map<String, dynamic> applyUserTuning(Map<String, dynamic> cfg) {
  final outs = List<dynamic>.from(cfg['outbounds'] as List? ?? []);
  if (!outs.any((o) => o is Map && o['tag'] == 'block')) outs.add({'tag': 'block', 'protocol': 'blackhole', 'settings': {}});
  final rules = <Map<String, dynamic>>[];
  if (Store.getBool('block_quic', false)) {
    rules.add({'type': 'field', 'network': 'udp', 'port': '443', 'outboundTag': 'block'});
  }
  if (Store.getBool('block_torrent', false)) {
    rules.add({'type': 'field', 'protocol': ['bittorrent'], 'outboundTag': 'block'});
    final ins = List<dynamic>.from(cfg['inbounds'] as List? ?? []);
    for (var i = 0; i < ins.length; i++) {
      final n = ins[i];
      if (n is Map && (n['protocol'] == 'http' || n['protocol'] == 'socks') && n['sniffing'] == null) {
        final m = Map<String, dynamic>.from(n);
        m['sniffing'] = {'enabled': true, 'destOverride': ['http', 'tls']};
        ins[i] = m;
      }
    }
    cfg['inbounds'] = ins;
  }
  if (Store.getBool('block_stun', true)) {
    rules.add({'type': 'field', 'port': '3478,5349', 'outboundTag': 'block'});
  }
  final r = Map<String, dynamic>.from(cfg['routing'] as Map? ?? {});
  final old = List<dynamic>.from(r['rules'] as List? ?? []);
  old.removeWhere((e) => e is Map && '${e['port']}'.contains('3478') && e['outboundTag'] == 'block');
  final apiIdx = old.indexWhere((e) => e is Map && e['outboundTag'] == 'api');
  if (apiIdx >= 0) {
    old.insertAll(apiIdx + 1, rules);
    r['rules'] = old;
  } else {
    r['rules'] = [...rules, ...old];
  }
  cfg['routing'] = r;
  final di = Store.getInt('dns_choice', 0);
  if (di > 0 && di < _kDnsSets.length) {
    final d = cfg['dns'] is Map ? Map<String, dynamic>.from(cfg['dns'] as Map) : <String, dynamic>{};
    final olds = List<dynamic>.from(d['servers'] as List? ?? []);
    d['servers'] = <dynamic>{..._kDnsSets[di], ...olds}.toList();
    cfg['dns'] = d;
  }
  if (Store.getBool('mux_on', false)) {
    for (var i = 0; i < outs.length; i++) {
      final o = outs[i];
      if (o is Map && o['tag'] == 'proxy' && !jsonEncode(o).contains('"flow":"xtls')) {
        final m = Map<String, dynamic>.from(o);
        m['mux'] = {'enabled': true, 'concurrency': 8};
        outs[i] = m;
      }
    }
  }
  cfg['outbounds'] = outs;
  return cfg;
}

void applyFragment(Map<String, dynamic> out) {}

Map<String, dynamic>? buildXrayConfig(
  String link, {
  int httpPort = 10809,
  int socksPort = 10808,
  int apiPort = 10085,
  List<String> dns = const [],
  bool enableFragment = false,
  int profile = 0,
  String? upstreamProxy,
  bool tune = false,
}) {
  final info = parseLink(link);
  if (info.outbound == null) return null;
  final upOut = upstreamProxy != null && upstreamProxy.isNotEmpty ? parseUpstream(upstreamProxy) : null;
  if (upOut != null) upOut['proxySettings'] = {'tag': 'proxy'};
  final built = <String, dynamic>{
    'log': {'loglevel': 'warning'},
    'stats': {},
    if (dns.isNotEmpty) 'dns': dnsBlock(dns),
    'api': {
      'tag': 'api',
      'services': ['StatsService']
    },
    'policy': {
      'system': {'statsOutboundUplink': true, 'statsOutboundDownlink': true}
    },
    'inbounds': [
      {'tag': 'http-in', 'listen': '127.0.0.1', 'port': httpPort, 'protocol': 'http', 'settings': {}},
      if (socksPort > 0)
        {
          'tag': 'socks-in',
          'listen': '127.0.0.1',
          'port': socksPort,
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true}
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
      info.outbound,
      {'tag': 'direct', 'protocol': 'freedom'},
    ],
    'routing': {
      'rules': [
        {'type': 'field', 'inboundTag': ['api'], 'outboundTag': 'api'},
        if (upOut != null) {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'upstream-residential'},
      ]
    }
  };
  return tune ? applyUserTuning(built) : built;
}
final String _realityPathKey = utf8.decode(base64Decode('c3BpZGVyWA=='));
final String _legacyPathKey = utf8.decode(base64Decode('c3B4'));

