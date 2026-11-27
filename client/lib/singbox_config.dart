import 'dart:convert';

// تجزیه‌ی لینک‌های Hysteria2 / TUIC / WireGuard / AmneziaWG و ساخت کانفیگ sing-box.
// این فایل به Store/UI وابسته نیست و فقط Map برمی‌گرداند.

const Set<String> kSingboxSchemes = {'hysteria2', 'hy2', 'tuic', 'wireguard', 'wg'};
const Set<String> kAmneziaSchemes = {'awg', 'amneziawg'};

String singboxEngineOf(String scheme) {
  final s = scheme.toLowerCase();
  if (kSingboxSchemes.contains(s)) return 'singbox';
  if (kAmneziaSchemes.contains(s)) return 'amneziawg';
  return 'xray';
}

String _d(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

class SingboxLink {
  final String protocol; // hysteria2 | tuic | wireguard | amneziawg
  final String transport; // quic | udp
  final String name;
  final bool endpoint; // wireguard در sing-box ≥1.11 «endpoint» است نه outbound
  final Map<String, dynamic> body; // خود outbound/endpoint با tag = proxy
  final bool amnezia;
  const SingboxLink(this.protocol, this.transport, this.name, this.endpoint, this.body, {this.amnezia = false});

  /// آدرس سرور (دامنه یا IP)
  String get host {
    if (endpoint) {
      final peers = body['peers'];
      if (peers is List && peers.isNotEmpty && peers.first is Map) return '${(peers.first as Map)['address']}';
      return '';
    }
    return '${body['server'] ?? ''}';
  }

  /// همان لینک ولی با IP به‌جای دامنه‌ی سرور. SNI (tls.server_name) دست‌نخورده می‌ماند.
  /// در اندروید باینری sing-box فایل /etc/resolv.conf ندارد و خودش نمی‌تواند دامنه را resolve کند؛
  /// پس دامنه قبل از ساخت کانفیگ در خود برنامه resolve می‌شود.
  SingboxLink withServerIp(String ip) {
    final b = Map<String, dynamic>.from(body);
    if (endpoint) {
      final peers = [
        for (final p in (b['peers'] as List)) Map<String, dynamic>.from(p as Map),
      ];
      if (peers.isNotEmpty) peers.first['address'] = ip;
      b['peers'] = peers;
    } else {
      b['server'] = ip;
    }
    return SingboxLink(protocol, transport, name, endpoint, b, amnezia: amnezia);
  }
}

final RegExp _re = RegExp(r'^([A-Za-z0-9]+)://([^@]*)@(\[[^\]]+\]|[^:/?#]+):(\d+)/?\??([^#]*)#?(.*)$');

List<String> _alpn(String? v, List<String> def) {
  if (v == null || v.isEmpty) return def;
  return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

bool _truthy(String? v) => v == '1' || (v ?? '').toLowerCase() == 'true';

SingboxLink? parseSingboxLink(String link) {
  final l = link.trim();
  final m = _re.firstMatch(l);
  if (m == null) return null;
  final scheme = m.group(1)!.toLowerCase();
  final user = _d(m.group(2)!);
  final host = m.group(3)!.replaceAll('[', '').replaceAll(']', '');
  final port = int.tryParse(m.group(4)!) ?? 0;
  if (port <= 0 || host.isEmpty) return null;
  Map<String, String> q = {};
  try {
    final raw = m.group(5)!;
    if (raw.isNotEmpty) q = Uri.splitQueryString(raw);
  } catch (_) {}
  final name = _d(m.group(6) ?? '');

  if (scheme == 'hysteria2' || scheme == 'hy2') {
    if (user.isEmpty) return null;
    final sni = (q['sni'] ?? q['peer'] ?? '').isNotEmpty ? (q['sni'] ?? q['peer']!) : host;
    return SingboxLink('hysteria2', 'quic', name, false, {
      'type': 'hysteria2',
      'tag': 'proxy',
      'server': host,
      'server_port': port,
      'password': user,
      if ((q['obfs'] ?? '').isNotEmpty) 'obfs': {'type': q['obfs'], 'password': q['obfs-password'] ?? ''},
      'tls': {
        'enabled': true,
        'server_name': sni,
        'insecure': _truthy(q['insecure']) || _truthy(q['allowInsecure']),
        'alpn': _alpn(q['alpn'], ['h3']),
      },
    });
  }

  if (scheme == 'tuic') {
    final c = user.indexOf(':');
    final uuid = c < 0 ? user : user.substring(0, c);
    final pass = c < 0 ? '' : user.substring(c + 1);
    if (uuid.isEmpty) return null;
    return SingboxLink('tuic', 'quic', name, false, {
      'type': 'tuic',
      'tag': 'proxy',
      'server': host,
      'server_port': port,
      'uuid': uuid,
      'password': pass,
      'congestion_control': (q['congestion_control'] ?? q['congestion'] ?? 'bbr'),
      'udp_relay_mode': (q['udp_relay_mode'] ?? 'native'),
      'tls': {
        'enabled': true,
        'server_name': (q['sni'] ?? '').isNotEmpty ? q['sni'] : host,
        'insecure': _truthy(q['allow_insecure']) || _truthy(q['insecure']) || _truthy(q['allowInsecure']),
        'alpn': _alpn(q['alpn'], ['h3']),
      },
    });
  }

  if (scheme == 'wireguard' || scheme == 'wg' || scheme == 'awg' || scheme == 'amneziawg') {
    final pub = (q['publickey'] ?? q['public_key'] ?? q['peer_public_key'] ?? '').replaceAll(' ', '+');
    if (user.isEmpty || pub.isEmpty) return null;
    final addr = (q['address'] ?? q['ip'] ?? '10.0.0.2/32').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).map((e) => e.contains('/') ? e : (e.contains(':') ? '$e/128' : '$e/32')).toList();
    final reserved = (q['reserved'] ?? '').split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toList();
    final amn = <String, dynamic>{};
    for (final k in ['jc', 'jmin', 'jmax', 's1', 's2', 'h1', 'h2', 'h3', 'h4']) {
      final v = q[k] ?? q[k.toUpperCase()];
      if (v != null && v.isNotEmpty) amn[k] = int.tryParse(v) ?? v;
    }
    final isAmnezia = scheme == 'awg' || scheme == 'amneziawg' || amn.isNotEmpty;
    return SingboxLink(isAmnezia ? 'amneziawg' : 'wireguard', 'udp', name, true, {
      'type': 'wireguard',
      'tag': 'proxy',
      'address': addr,
      'private_key': user,
      'mtu': int.tryParse(q['mtu'] ?? '') ?? 1280,
      'peers': [
        {
          'address': host,
          'port': port,
          'public_key': pub,
          if ((q['presharedkey'] ?? q['pre_shared_key'] ?? '').isNotEmpty) 'pre_shared_key': (q['presharedkey'] ?? q['pre_shared_key'] ?? '').replaceAll(' ', '+'),
          'allowed_ips': ['0.0.0.0/0', '::/0'],
          if (reserved.length == 3) 'reserved': reserved,
        }
      ],
      if (isAmnezia && amn.isNotEmpty) '_amnezia': amn,
    }, amnezia: isAmnezia);
  }
  return null;
}

/// کانفیگ کامل sing-box با ورودی mixed (HTTP+SOCKS) روی [httpPort] و SOCKS جدا روی [socksPort].
/// [template]: اگر هسته‌ی سفارشی JSON کامل داده باشد، {{PORT}}، {{SOCKS_PORT}} و {{OUTBOUND}} در آن جایگزین می‌شوند.
Map<String, dynamic>? buildSingboxConfig(SingboxLink l, {int httpPort = 10809, int socksPort = 10808, String template = '', bool android = false}) {
  final body = Map<String, dynamic>.from(l.body)..remove('_amnezia');
  if (template.trim().isNotEmpty) {
    try {
      final t = template
          .replaceAll('{{PORT}}', '$httpPort')
          .replaceAll('{{SOCKS_PORT}}', '$socksPort')
          .replaceAll('"{{OUTBOUND}}"', jsonEncode(body));
      return (jsonDecode(t) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
  return {
    'log': {'level': 'warn', 'timestamp': true},
    'inbounds': [
      {'type': 'mixed', 'tag': 'mixed-in', 'listen': '127.0.0.1', 'listen_port': httpPort},
      if (socksPort != httpPort) {'type': 'socks', 'tag': 'socks-in', 'listen': '127.0.0.1', 'listen_port': socksPort},
    ],
    if (!l.endpoint) 'outbounds': [body, {'type': 'direct', 'tag': 'direct'}] else 'outbounds': [{'type': 'direct', 'tag': 'direct'}],
    if (l.endpoint) 'endpoints': [body],
    // اندروید: برنامه‌ی عادی به netlink دسترسی ندارد و auto_detect_interface باعث خطای شروع می‌شود؛
    // لازم هم نیست چون خود برنامه از VPN مستثنا می‌شود (حلقه‌ی تونل پیش نمی‌آید).
    'route': {'final': 'proxy', if (!android) 'auto_detect_interface': true},
  };
}
