import 'dart:convert';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'store.dart';
import 'xray_config.dart';

typedef AndroidStatusCb = void Function(String state, int up, int down, int upSpeed, int downSpeed, String duration);

class AndroidVpn {
  FlutterV2ray? _v2;

  bool get supported => true;

  Future<void> init(AndroidStatusCb cb) async {
    _v2 = FlutterV2ray(onStatusChanged: (s) {
      cb('${s.state}', _i(s.upload), _i(s.download), _i(s.uploadSpeed), _i(s.downloadSpeed), '${s.duration}');
    });
    await _v2!.initializeV2Ray(
      notificationIconResourceType: 'drawable',
      notificationIconResourceName: 'ic_stat_logo',
    );
  }

  int _i(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

  String _config(String link, Map<String, dynamic> outbound, List<String> dns) {
    Map<String, dynamic>? base;
    try {
      final u = FlutterV2ray.parseFromURL(link);
      base = jsonDecode(u.getFullConfiguration()) as Map<String, dynamic>;
    } catch (_) {}
    base ??= mobileBaseConfig();
    final outs = List<dynamic>.from(base['outbounds'] as List? ?? []);
    // تضمین وجود دایلر فرگمنت در اندروید برای دور زدن فیلترینگ شدید همراه اول و ایرانسل
    if (!outs.any((o) => o is Map && o['tag'] == 'fragment')) {
      outs.add({
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
      });
    }
    final proxyOut = Map<String, dynamic>.from(outbound);
    if (Store.stealth && proxyOut['dialerProxy'] == null && '${proxyOut['protocol']}' != 'kcp') {
      proxyOut['dialerProxy'] = 'fragment';
    }
    final i = outs.indexWhere((o) => o is Map && o['tag'] == 'proxy');
    if (i >= 0) {
      outs[i] = proxyOut;
    } else {
      outs.insert(0, proxyOut);
    }
    final upRaw = Store.upstreamProxyEnabled ? Store.upstreamProxy : '';
    final upOut = parseUpstream(upRaw);
    if (upOut != null) {
      upOut['proxySettings'] = {'tag': 'proxy'};
      outs.insert(0, upOut);
    }
    if (!outs.any((o) => o is Map && o['tag'] == 'block')) {
      outs.add({'tag': 'block', 'protocol': 'blackhole', 'settings': {}});
    }
    final rout = Map<String, dynamic>.from(base['routing'] as Map? ?? {});
    final rules = List<dynamic>.from(rout['rules'] as List? ?? []);
    if (!rules.any((r) => r is Map && '${r['port']}'.contains('3478'))) {
      rules.insert(0, {
        'type': 'field',
        'port': '3478,5349',
        'outboundTag': 'block',
      });
      rules.insert(0, {
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
      });
    }
    rout['rules'] = rules;
    base['routing'] = rout;
    base['outbounds'] = outs;
    base['dns'] = dnsBlock(dns);
    return jsonEncode(base);
  }

  Future<bool> start(String link, String remark, Map<String, dynamic> outbound, {List<String> dns = const []}) async {
    final v2 = _v2;
    if (v2 == null) return false;
    if (!await v2.requestPermission()) return false;
    v2.startV2Ray(
      remark: remark,
      config: _config(link, outbound, dns),
      proxyOnly: false,
      bypassSubnets: <String>[],
      notificationDisconnectButtonName: 'قطع اتصال',
    );
    return true;
  }

  Future<void> stop() async {
    _v2?.stopV2Ray();
  }

  // پینگ واقعی (Relay): هسته‌ی v2ray کانفیگ را بالا می‌آورد و یک درخواست HTTP کامل از داخل آن می‌زند
  // (بدون نیاز به دسترسی VPN و بدون قطع اتصال فعلی). -1 یعنی شکست.
  Future<int> delay(String link, Map<String, dynamic> outbound) async {
    final v2 = _v2;
    if (v2 == null) return -1;
    try {
      final d = await (v2 as dynamic).getServerDelay(
        config: _config(link, outbound, const <String>[]),
        url: 'http://cp.cloudflare.com/generate_204',
      );
      final ms = d is int ? d : int.tryParse('$d') ?? -1;
      return ms >= 1 ? ms : -1;
    } catch (_) {
      return -1;
    }
  }
}
