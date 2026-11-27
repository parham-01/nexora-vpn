import 'dart:convert';
import 'dart:io';
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

  // profile 0: قوی‌ترین — outbound برنامه + فرگمنت (tlshello) + DoH رمزنگاری‌شده
  // profile 1: متوسط — outbound برنامه + DNS ساده از داخل تونل (AsIs)
  // profile 2: ساده — «خام»: همان کانفیگی که پلاگین v2ray از خود لینک می‌سازد (مثل v2rayNG/V2Box)
  /// آیا پلاگین می‌تواند این لینک را خودش بخواند؟ (برای پروفایل خام)
  bool nativeParsable(String link) {
    try {
      final u = FlutterV2ray.parseFromURL(link);
      final m = jsonDecode(u.getFullConfiguration()) as Map<String, dynamic>;
      final outs = m['outbounds'] as List? ?? [];
      return outs.any((o) => o is Map && o['tag'] == 'proxy');
    } catch (_) {
      return false;
    }
  }

  String _config(String link, Map<String, dynamic> outbound, List<String> dns, {int profile = 0}) {
    if (profile == 2 && nativeParsable(link) && !(Store.upstreamProxyEnabled && Store.upstreamProxy.trim().isNotEmpty)) {
      final u = FlutterV2ray.parseFromURL(link);
      final nb = jsonDecode(u.getFullConfiguration()) as Map<String, dynamic>;
      final nouts = List<dynamic>.from(nb['outbounds'] as List? ?? []);
      if (!nouts.any((o) => o is Map && o['tag'] == 'direct')) nouts.add({'tag': 'direct', 'protocol': 'freedom', 'settings': {}});
      if (!nouts.any((o) => o is Map && o['tag'] == 'block')) nouts.add({'tag': 'block', 'protocol': 'blackhole', 'settings': {}});
      nb['outbounds'] = nouts;
      nb['dns'] = dnsBlock(dns, safe: true);
      final nr = Map<String, dynamic>.from(nb['routing'] as Map? ?? {});
      nr['domainStrategy'] = 'AsIs';
      final nrules = List<dynamic>.from(nr['rules'] as List? ?? []);
      // فقط بلاک STUN/TURN (جلوگیری از نشت IP)؛ بقیه‌ی مسیریابی همان پیش‌فرض پلاگین
      if (!nrules.any((r) => r is Map && '${r['port']}'.contains('3478'))) {
        nrules.insert(0, {'type': 'field', 'port': '3478,5349', 'outboundTag': 'block'});
      }
      nr['rules'] = nrules;
      nb['routing'] = nr;
      return jsonEncode(applyUserTuning(nb));
    }
    Map<String, dynamic>? base;
    try {
      final u = FlutterV2ray.parseFromURL(link);
      base = jsonDecode(u.getFullConfiguration()) as Map<String, dynamic>;
    } catch (_) {}
    base ??= mobileBaseConfig();
    final outs = List<dynamic>.from(base['outbounds'] as List? ?? []);
    final i = outs.indexWhere((o) => o is Map && o['tag'] == 'proxy');
    if (i >= 0) {
      outs[i] = outbound;
    } else {
      outs.insert(0, outbound);
    }
    final upOut = parseUpstream(Store.upstreamProxyEnabled ? Store.upstreamProxy : '');
    if (upOut != null) {
      upOut['proxySettings'] = {'tag': 'proxy'};
      outs.insert(0, upOut);
    }
    base['outbounds'] = outs;
    if (dns.isNotEmpty) {
      final old = base['dns'] is Map ? Map<String, dynamic>.from(base['dns'] as Map) : <String, dynamic>{};
      old.addAll(dnsBlock(dns));
      base['dns'] = old;
    }
    return jsonEncode(applyUserTuning(base));
  }

  Future<bool> start(String link, String remark, Map<String, dynamic> outbound, {List<String> dns = const [], int profile = 0}) async {
    final v2 = _v2;
    if (v2 == null) return false;
    if (!await v2.requestPermission()) return false;
    v2.startV2Ray(
      remark: remark,
      config: _config(link, outbound, dns, profile: profile),
      proxyOnly: false,
      bypassSubnets: <String>[],
      notificationDisconnectButtonName: 'قطع اتصال',
    );
    return true;
  }

  /// نام بسته‌ی همین برنامه (برای مستثنا کردن خودش از VPN). اندروید: /proc/self/cmdline
  static String get packageName {
    try {
      final raw = File('/proc/self/cmdline').readAsBytesSync();
      final end = raw.indexOf(0);
      final n = utf8.decode(end < 0 ? raw : raw.sublist(0, end), allowMalformed: true).trim();
      // فرایندهای فرعی به‌شکل pkg:name هستند
      return n.split(':').first;
    } catch (_) {
      return '';
    }
  }

  /// پوشه‌ی کتابخانه‌های بومی (nativeLibraryDir) از روی /proc/self/maps؛ باینری sing-box اینجا با نام libsingbox.so است.
  static String? get nativeLibDir {
    try {
      for (final line in File('/proc/self/maps').readAsLinesSync()) {
        final i = line.indexOf('/');
        if (i < 0) continue;
        final path = line.substring(i).trim();
        if (path.endsWith('/libflutter.so') || path.endsWith('/libapp.so')) {
          return path.substring(0, path.lastIndexOf('/'));
        }
      }
    } catch (_) {}
    return null;
  }

  /// مسیر قابل‌اجرای sing-box داخل APK (null = در این APK نیست)
  static String? get singboxPath {
    final d = nativeLibDir;
    if (d == null) return null;
    final f = File('$d/libsingbox.so');
    return f.existsSync() ? f.path : null;
  }

  /// پروفایل «زنجیره‌ی sing-box»: Xray (VPN اندروید) ← SOCKS محلی ← sing-box (Hysteria2 / TUIC / WireGuard).
  /// خود برنامه (و پروسه‌ی فرزند sing-box که UID یکسان دارد) از VPN مستثنا می‌شود تا ترافیک سرور
  /// دوباره داخل تونل نیفتد.
  String chainConfig(int socksPort, List<String> dns) {
    final base = mobileBaseConfig();
    final outs = List<dynamic>.from(base['outbounds'] as List);
    outs.removeWhere((o) => o is Map && o['tag'] == 'fragment');
    outs.insert(0, {
      'tag': 'proxy',
      'protocol': 'socks',
      'settings': {
        'servers': [
          {'address': '127.0.0.1', 'port': socksPort}
        ]
      },
    });
    base['outbounds'] = outs;
    // DNS ساده از داخل خود تونل؛ DoH مستقیم لازم نیست چون خود سرور sing-box دامنه‌ها را resolve می‌کند.
    base['dns'] = dnsBlock(dns, safe: true);
    final rout = Map<String, dynamic>.from(base['routing'] as Map? ?? {});
    rout['domainStrategy'] = 'AsIs';
    base['routing'] = rout;
    return jsonEncode(base);
  }

  Future<bool> startChain(String remark, int socksPort, {List<String> dns = const []}) async {
    final v2 = _v2;
    if (v2 == null) return false;
    if (!await v2.requestPermission()) return false;
    final me = packageName;
    v2.startV2Ray(
      remark: remark,
      config: chainConfig(socksPort, dns),
      proxyOnly: false,
      blockedApps: me.isEmpty ? <String>[] : <String>[me],
      bypassSubnets: <String>[],
      notificationDisconnectButtonName: 'قطع اتصال',
    );
    return true;
  }

  Future<void> stop() async {
    _v2?.stopV2Ray();
  }

  // پینگ واقعی (Relay) به سبک V2rayNG: هسته‌ی v2ray کانفیگ را بالا می‌آورد و یک درخواست HTTP کامل
  // (generate_204) از داخل آن می‌زند؛ بدون نیاز به دسترسی VPN و بدون قطع اتصال فعلی. -1 یعنی Timeout/شکست.
  // نکته‌ی مهم: پلاگین flutter_v2ray تست‌ها را پشت‌سرهم (روی یک thread) اجرا می‌کند؛ پس این تابع باید فقط
  // وقتی صدا زده شود که نوبتِ همین تست رسیده باشد (VpnService.relayPing این را با یک دروازه تضمین می‌کند)
  // و Timeout از لحظه‌ی شروع واقعی تست حساب شود، نه از لحظه‌ی صف‌شدن. زمان‌سنج هسته‌ی libv2ray همان ۱۲ ثانیه‌ی V2rayNG است.
  Future<int> delay(String link, Map<String, dynamic> outbound, {List<String> dns = const []}) async {
    final v2 = _v2;
    if (v2 == null) return -1;
    // همان کانفیگی که برای اتصال ساخته می‌شود تست می‌شود تا «پینگ خوب» یعنی «اتصال خوب».
    const urls = ['https://www.google.com/generate_204', 'http://cp.cloudflare.com/generate_204'];
    final cfg = _config(link, outbound, dns, profile: 2);
    final sw = Stopwatch()..start();
    for (var i = 0; i < urls.length; i++) {
      // آدرس پشتیبان فقط وقتی امتحان می‌شود که اولی «سریع» خطا داده باشد؛ اگر اولی تا Timeout طول کشید یعنی سرور جواب نمی‌دهد.
      if (i > 0 && sw.elapsedMilliseconds > 2500) break;
      try {
        final d = await (v2 as dynamic)
            .getServerDelay(config: cfg, url: urls[i])
            .timeout(const Duration(seconds: 13), onTimeout: () => -1);
        final ms = d is int ? d : int.tryParse('$d') ?? -1;
        if (ms >= 1 && ms <= 12000) return ms;
      } catch (_) {}
    }
    return -1;
  }
}
