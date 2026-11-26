import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart' show Color;
import 'store.dart';

const String _sbBuildUrl = String.fromEnvironment('SB_URL', defaultValue: '');
const String _sbBuildKey = String.fromEnvironment('SB_KEY');
String get sbUrl => _sbBuildUrl;
String get sbKey => _sbBuildKey.trim();

class Geo {
  final String ip, country, code;
  Geo(this.ip, this.country, this.code);

  String get flag {
    if (code.length != 2) return '🌐';
    final a = code.toUpperCase().codeUnits;
    return String.fromCharCodes([0x1F1E6 + a[0] - 65, 0x1F1E6 + a[1] - 65]);
  }
}

String flagOf(String code) {
  if (code.length != 2) return '🌐';
  final a = code.toUpperCase().codeUnits;
  return String.fromCharCodes([0x1F1E6 + a[0] - 65, 0x1F1E6 + a[1] - 65]);
}

class IpQualityReport {
  final String ip;
  final String country;
  final String code;
  final String city;
  final String isp;
  final String org;
  final String asName;
  final String timezone;
  final bool isHosting;
  final bool isProxy;
  final int fraudScore;
  final bool timezoneMatch;
  final String clientTimezone;
  final String note;

  const IpQualityReport({
    required this.ip,
    required this.country,
    required this.code,
    required this.city,
    required this.isp,
    required this.org,
    required this.asName,
    required this.timezone,
    required this.isHosting,
    required this.isProxy,
    required this.fraudScore,
    required this.timezoneMatch,
    required this.clientTimezone,
    required this.note,
  });

  bool get isResidential => !isHosting;
  String get flag => flagOf(code);

  String get riskLabel {
    if (fraudScore <= 25) return 'عالی و کم‌خطر (مناسب ثبت‌نام آمازون و پی‌پال)';
    if (fraudScore <= 70) return 'متوسط (مناسب وب‌گردی، هوش مصنوعی و یوتیوب)';
    return 'ریسک بالا (دیتاسنتری - احتمال نیاز به احراز هویت اضافی)';
  }

  Color get riskColor {
    if (fraudScore <= 25) return const Color(0xFF29E07F);
    if (fraudScore <= 70) return const Color(0xFFFFB86B);
    return const Color(0xFFFF5B5B);
  }
}

// عنوان کانفیگ: نام یا لوکیشن (پرچم + کشور). آیپی/آدرس سرور هرگز نمایش داده نمی‌شود.
String cfgTitle(Map<String, dynamic> c) {
  final n = '${c['name'] ?? ''}'.trim();
  final isIp = RegExp(r'^[\d.:\[\]a-fA-F]+$').hasMatch(n) && n.contains(RegExp(r'[.:]'));
  if (n.isNotEmpty && !isIp) return n;
  final co = '${c['country'] ?? ''}'.trim();
  if (co.isNotEmpty) return '${flagOf('${c['code'] ?? ''}')} $co';
  final g = Store.geoCache[Api.hostOf('${c['link'] ?? ''}')];
  if (g is List && g.length == 2 && '${g[0]}'.isNotEmpty) return '${flagOf('${g[1]}')} ${g[0]}';
  return 'در حال تشخیص لوکیشن...';
}

class Api {
  static Future<dynamic> _request(String method, String url,
      {Map<String, dynamic>? body, String? proxy, int timeout = 15}) async {
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 10);
    if (proxy != null) c.findProxy = (_) => 'PROXY $proxy';
    try {
      final r = await c.openUrl(method, Uri.parse(url));
      r.headers.set('content-type', 'application/json');
      if (body != null) r.add(utf8.encode(jsonEncode(body)));
      final res = await r.close().timeout(Duration(seconds: timeout));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 400) throw HttpException('${res.statusCode}');
      return text.isEmpty ? null : jsonDecode(text);
    } finally {
      c.close(force: true);
    }
  }

  static Future<dynamic> _sb(String method, String path, {Object? body, int timeout = 15, bool retry = true}) async {
    if (sbKey.isEmpty) throw const HttpException('no key');
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 10);
    try {
      final r = await c.openUrl(method, Uri.parse('$sbUrl/rest/v1/$path'));
      r.headers.set('apikey', sbKey);
      if (sbKey.startsWith('eyJ')) r.headers.set('authorization', 'Bearer $sbKey');
      r.headers.set('content-type', 'application/json');
      r.headers.set('accept', 'application/json');
      if (body != null) r.add(utf8.encode(jsonEncode(body)));
      final res = await r.close().timeout(Duration(seconds: timeout));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 400) throw HttpException('${res.statusCode} $text');
      return text.isEmpty ? null : jsonDecode(text);
    } finally {
      c.close(force: true);
    }
  }

  static Map<String, dynamic> _cfg(Map e) => {
        'id': '${e['id']}',
        'name': '${e['name'] ?? ''}',
        'quotaGb': e['quota_gb'] ?? 0,
        'expires': '${e['expires'] ?? ''}',
        'link': '${e['link'] ?? ''}',
        'protocol': '${e['protocol'] ?? ''}',
        'transport': '${e['transport'] ?? ''}',
        'country': '${e['country'] ?? ''}',
        'code': '${e['code'] ?? ''}',
      };

  static Future<Map<String, dynamic>?> fetchConfig({String? id}) async {
    if (!await sync()) return null;
    final l = Store.configs.value;
    if (l.isEmpty) return null;
    if (id != null && id.isNotEmpty) {
      for (final c in l) {
        if ('${c['id']}' == id) return c;
      }
    }
    return l.first;
  }

  static const String _cols = 'configs?select=id,name,quota_gb,expires,link,protocol,transport,country,code&enabled=eq.true&order=created_at.asc&limit=500';

  // country/code عمداً در امضا نیست: fillGeo آن را روی لیست محلی پر می‌کند و اگر در امضا بود
  // هر ۳ ثانیه لیست ریست و دوباره پر می‌شد (چشمک و ناپدید شدن موقت کانفیگ‌ها)
  static String _sig(List<Map<String, dynamic>> l) => l.map((e) => '${e['id']}|${e['link']}|${e['name']}|${e['quotaGb']}|${e['expires']}').join(',');

  // بعد از افزودن/حذف سرور شخصی: لیست ادمین را بلافاصله و بی‌قید به امضا دوباره زنده از دیتابیس می‌گیرد
  static Future<void> refreshConfigs() async {
    final g = ++_cfgGen;
    try {
      final list = await _fetchServerConfigs(timeout: 10);
      if (g != _cfgGen) return;
      await Store.setConfigs(list);
      if (list.isNotEmpty) unawaited(fillGeo());
    } catch (_) {}
  }

  // فقط زنده از دیتابیس و با کلید anon/publishable که در بیلدر گذاشته شده؛ هیچ فایل/کش محلی خوانده نمی‌شود
  static int _cfgGen = 0;
  static String lastSyncError = '';
  static String _short(Object e) {
    final t = '$e'.replaceFirst('HttpException: ', '');
    return t.length > 120 ? t.substring(0, 120) : t;
  }

  static Future<List<Map<String, dynamic>>> _fetchServerConfigs({int timeout = 15}) async {
    dynamic r;
    try {
      r = await _sb('GET', _cols, timeout: timeout);
    } catch (e1) {
      try {
        r = await _sb('POST', 'rpc/get_public_configs', body: {}, timeout: timeout);
      } catch (e2) {
        lastSyncError = _short(e1);
        rethrow;
      }
    }
    lastSyncError = '';
    return (r as List).map((e) => _cfg(e as Map)).where((e) => !'${e['id']}'.startsWith('default-')).toList();
  }

  // بررسی بی‌صدا و سریع؛ حذف/تغییر کانفیگ از اپ ادمین بلافاصله روی همه‌ی کاربران اعمال می‌شود
  static bool _polling = false;
  static Future<void> pollConfigs() async {
    if (_polling) return;
    _polling = true;
    final g = ++_cfgGen;
    try {
      final list = await _fetchServerConfigs(timeout: 8);
      if (g != _cfgGen) return;
      if (_sig(list) == _sig(Store.serverConfigs)) return;
      await Store.setConfigs(list);
      if (list.isNotEmpty) unawaited(fillGeo());
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  static Future<bool> sync() async {
    unawaited(event({'type': 'hello'})); // کاربر حتی اگر خواندن کانفیگ‌ها شکست خورد ثبت شود
    final g = ++_cfgGen;
    try {
      final list = await _fetchServerConfigs();
      if (g != _cfgGen) return true;
      event({'type': 'hello'});
      await Store.setConfigs(list);
      if (list.isNotEmpty) unawaited(fillGeo());
      return true;
    } catch (e) {
      if (lastSyncError.isEmpty) lastSyncError = _short(e);
      return false;
    }
  }

  static Future<bool> reach({String? proxy}) async {
    for (final u in ['http://cp.cloudflare.com/generate_204', 'https://www.gstatic.com/generate_204']) {
      try {
        await _request('GET', u, proxy: proxy, timeout: 8);
        return true;
      } catch (_) {}
    }
    return false;
  }

  static Future<List<Map<String, dynamic>>> servers() async {
    await sync();
    return Store.configs.value;
  }

  static final List<Map<String, dynamic>> _pendingEvents = [];
  static bool _flushing = false;
  static String lastEventError = '';

  static Future<void> _sendEvent(Map<String, dynamic> d) async {
    await _sb('POST', 'rpc/report_event', body: {
      'p_device': Store.deviceId,
      'p_platform': Platform.operatingSystem,
      'p_type': '${d['type'] ?? 'hello'}',
      'p_session': '${d['session'] ?? ''}',
      'p_protocol': '${d['protocol'] ?? ''}',
      'p_transport': '${d['transport'] ?? ''}',
      'p_country': '${d['country'] ?? ''}',
      'p_config': '${d['configId'] ?? ''}',
      'p_up': (d['up'] as num?)?.toInt() ?? 0,
      'p_down': (d['down'] as num?)?.toInt() ?? 0,
      'p_seconds': (d['seconds'] as num?)?.toInt() ?? 0,
    }, timeout: 12);
  }

  static Future<void> _flushPending() async {
    if (_flushing || _pendingEvents.isEmpty) return;
    _flushing = true;
    try {
      while (_pendingEvents.isNotEmpty) {
        await _sendEvent(_pendingEvents.first);
        _pendingEvents.removeAt(0);
      }
    } catch (_) {
    } finally {
      _flushing = false;
    }
  }

  static Future<void> event(Map<String, dynamic> d) async {
    final t = '${d['type'] ?? 'hello'}';
    for (var i = 0; i < 2; i++) {
      try {
        await _sendEvent(d);
        lastEventError = '';
        unawaited(_flushPending());
        return;
      } catch (e) {
        lastEventError = '$e';
        if (i == 0) await Future.delayed(const Duration(seconds: 2));
      }
    }
    if (t == 'connect' || t == 'disconnect') {
      if (_pendingEvents.length >= 40) _pendingEvents.removeAt(0);
      _pendingEvents.add(Map<String, dynamic>.from(d));
    }
  }

  // گزارش آمار اکانت‌های Firefox برای پنل ادمین (ایمیل ماسک‌شده؛ بی‌صدا و بدون خطا)
  static Future<void> reportFirefox(List<Map<String, dynamic>> accounts) async {
    try {
      await _sb('POST', 'rpc/report_firefox', body: {'p_device': Store.deviceId, 'p_accounts': accounts}, timeout: 10);
    } catch (_) {}
  }

  static Future<bool> saveBackup(String id, String blob) async {
    try {
      final r = await _sb('POST', 'rpc/save_user_backup', body: {'p_id': id, 'p_blob': blob, 'p_device': Store.deviceId}, timeout: 25);
      return r == true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> loadBackup(String id) async {
    final r = await _sb('POST', 'rpc/load_user_backup', body: {'p_id': id}, timeout: 25);
    return r is String ? r : null;
  }

  static Future<void> forgetFirefox(String accId) async {
    try {
      await _sb('POST', 'rpc/forget_firefox', body: {'p_device': Store.deviceId, 'p_acc': accId}, timeout: 10);
    } catch (_) {}
  }

  // تنظیمات عمومی برنامه که از پنل ادمین ذخیره می‌شود (مثلاً github_token برای خواندن ریلیزها)
  static Future<String> appSetting(String key) async {
    try {
      final r = await _sb('POST', 'rpc/get_app_setting', body: {'p_key': key}, timeout: 8);
      return r == null ? '' : '$r'.trim();
    } catch (_) {
      return '';
    }
  }

  static Future<int> pingLink(String link, {int timeoutSec = 4}) async {
    try {
      String host;
      int port;
      if (link.startsWith('vmess://')) {
        final raw = link.substring(8).split('#').first;
        final m = jsonDecode(utf8.decode(base64.decode(base64.normalize(raw)))) as Map;
        host = '${m['add']}';
        port = int.parse('${m['port']}');
      } else {
        final m = RegExp(r'@(\[[^\]]+\]|[^:/?#@]+):(\d+)').firstMatch(link);
        if (m == null) return -1;
        host = m.group(1)!.replaceAll(RegExp(r'[\[\]]'), '');
        port = int.parse(m.group(2)!);
      }
      final sw = Stopwatch()..start();
      final s = await Socket.connect(host, port, timeout: Duration(seconds: timeoutSec));
      sw.stop();
      s.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  // پینگ معتبر: بین ۱ تا ۳۰۰۰ میلی‌ثانیه. صفر، منفی یا بیشتر از ۳ ثانیه یعنی نامعتبر.
  static bool validPing(int ms) => ms >= 1 && ms <= 3000;

  // پینگ واقعی (دو اتصال TCP پشت سر هم به پورت سرور)؛ اگر هرکدام شکست بخورد یا عدد نامعتبر باشد -1
  static Future<int> realPing(String link, {int timeoutSec = 3}) async {
    final a = await pingLink(link, timeoutSec: timeoutSec);
    if (!validPing(a)) return -1;
    final b = await pingLink(link, timeoutSec: timeoutSec);
    if (!validPing(b)) return -1;
    return min(a, b);
  }

  // پینگ واقعی (Relay): یک درخواست HTTP کامل از داخل پراکسی/هسته‌ی کانفیگ؛ نه TCP ساده.
  // زمان کل درخواست تا رسیدن پاسخ generate_204 به میلی‌ثانیه، یا -1 اگر شکست خورد.
  // سریع: پینگ بالای ۳ ثانیه ویلید نیست، پس Timeout فقط ۴ ثانیه است؛ آدرس دوم (پشتیبان) فقط اگر اولی
  // ~۹۰۰ms جواب نداد موازی شروع می‌شود و هر کدام زودتر جواب داد برنده است (به‌جای ۸+۸ ثانیه انتظار پشت‌سرهم).
  static Future<int> delayVia(String proxy, {int timeoutSec = 4}) {
    const urls = ['http://cp.cloudflare.com/generate_204', 'http://www.gstatic.com/generate_204'];
    final done = Completer<int>();
    var failed = 0;
    void start(String u) {
      final sw = Stopwatch()..start();
      _request('GET', u, proxy: proxy, timeout: timeoutSec).then<void>((_) {
        if (!done.isCompleted) done.complete(max(1, sw.elapsedMilliseconds));
      }, onError: (Object _) {
        failed++;
        if (failed >= urls.length && !done.isCompleted) done.complete(-1);
      });
    }

    start(urls[0]);
    Timer(const Duration(milliseconds: 900), () {
      if (!done.isCompleted) start(urls[1]);
    });
    return done.future;
  }

  // تأخیر واقعی اینترنت از داخل تونل (میلی‌ثانیه) یا -1
  static Future<int> reachMs({String? proxy}) async {
    for (final u in ['http://cp.cloudflare.com/generate_204', 'https://www.gstatic.com/generate_204']) {
      final sw = Stopwatch()..start();
      try {
        await _request('GET', u, proxy: proxy, timeout: 8);
        sw.stop();
        return max(1, sw.elapsedMilliseconds);
      } catch (_) {}
    }
    return -1;
  }

  static String hostOf(String link) {
    try {
      if (link.startsWith('vmess://')) {
        final raw = link.substring(8).split('#').first;
        final m = jsonDecode(utf8.decode(base64.decode(base64.normalize(raw)))) as Map;
        return '${m['add']}';
      }
      final m = RegExp(r'@(\[[^\]]+\]|[^:/?#@]+):(\d+)').firstMatch(link);
      return m == null ? '' : m.group(1)!.replaceAll(RegExp(r'[\[\]]'), '');
    } catch (_) {
      return '';
    }
  }

  static bool _filling = false;
  static Future<void> fillGeo() async {
    if (_filling) return;
    _filling = true;
    try {
      final list = Store.configs.value;
      final need = [
        for (final c in list)
          if ('${c['country'] ?? ''}'.isEmpty) c
      ];
      if (need.isEmpty) return;
      final cache = Store.geoCache;
      final hosts = <String>{for (final c in need) hostOf('${c['link']}')}..remove('');
      final todo = hosts.where((h) => !cache.containsKey(h)).take(30).toList();
      for (var i = 0; i < todo.length; i += 5) {
        await Future.wait(todo.sublist(i, min(i + 5, todo.length)).map((h) async {
          try {
            final m = await _request('GET', 'https://ipwho.is/${Uri.encodeComponent(h)}', timeout: 8) as Map;
            if (m['success'] != false && '${m['country'] ?? ''}'.isNotEmpty) {
              cache[h] = ['${m['country']}', '${m['country_code'] ?? ''}'];
            }
          } catch (_) {}
        }));
      }
      await Store.setGeoCache(cache);
      var changed = false;
      final out = <Map<String, dynamic>>[];
      final customChanged = <Map<String, dynamic>>[];
      final gen = _cfgGen;
      for (final c in List<Map<String, dynamic>>.from(Store.configs.value)) {
        final x = Map<String, dynamic>.from(c);
        final g = cache[hostOf('${c['link']}')];
        var ch = false;
        if ('${x['country'] ?? ''}'.isEmpty && g is List && g.length == 2) {
          x['country'] = '${g[0]}';
          x['code'] = '${g[1]}';
          ch = true;
        }
        if (Store.isCustom(c)) {
          if (ch) customChanged.add(x);
        } else {
          if (ch) changed = true;
          out.add(x);
        }
      }
      if (changed && gen == _cfgGen) await Store.setConfigs(out);
      for (final x in customChanged) {
        await Store.updateCustom('${x['id']}', x);
      }
    } catch (_) {
    } finally {
      _filling = false;
    }
  }

  static Geo? _parseGeo(int k, Map m) {
    String t(Object? v) => v == null ? '' : '$v'.trim();
    String ip = '', name = '', code = '';
    switch (k) {
      case 0:
        if (m['success'] == false) return null;
        ip = t(m['ip']); name = t(m['country']); code = t(m['country_code']);
        break;
      case 1:
        if (m['error'] == true) return null;
        ip = t(m['ip']); name = t(m['country_name']); code = t(m['country_code']);
        break;
      case 2:
        if (t(m['status']) == 'fail') return null;
        ip = t(m['query']); name = t(m['country']); code = t(m['countryCode']);
        break;
      case 3:
        ip = t(m['ip']); name = t(m['country']); code = t(m['cc']);
        break;
      case 4:
        ip = t(m['ipAddress']); name = t(m['countryName']); code = t(m['countryCode']);
        break;
      case 5:
        if (m['success'] == false) return null;
        ip = t(m['ip']); name = t(m['country']); code = t(m['country_code']);
        break;
      default:
        ip = t(m['ip']); code = t(m['country']);
        if (code.length != 2) return null;
    }
    if (code.length != 2 && name.isEmpty) return null;
    if (code.length != 2) code = '';
    if (name.isEmpty || name.length == 2) name = code.isEmpty ? '' : code.toUpperCase();
    if (name.isEmpty) return null;
    return Geo(ip, name, code.toUpperCase());
  }

  static const List<String> _geoUrls = [
    'https://ipwho.is/',
    'https://ipapi.co/json/',
    'http://ip-api.com/json/?fields=status,country,countryCode,query',
    'https://api.myip.com',
    'https://freeipapi.com/api/json',
    'https://ipwhois.app/json/',
    'https://ipinfo.io/json',
  ];

  // تشخیص کشور: چند سرویس به‌صورت پله‌ای و موازی (هر ۱.۲ ثانیه یک سرویس جدید)؛ اولین پاسخ معتبر برنده است.
  static Future<Geo?> _geoOnce(String? proxy) {
    final done = Completer<Geo?>();
    var failed = 0;
    final timers = <Timer>[];
    void start(int k) {
      _request('GET', _geoUrls[k], proxy: proxy, timeout: 7).then<void>((r) {
        final g = r is Map ? _parseGeo(k, r) : null;
        if (g != null) {
          if (!done.isCompleted) done.complete(g);
        } else {
          failed++;
        }
      }, onError: (Object _) {
        failed++;
      }).whenComplete(() {
        if (failed >= _geoUrls.length && !done.isCompleted) done.complete(null);
      });
    }

    for (var k = 0; k < _geoUrls.length; k++) {
      if (k == 0) {
        start(0);
      } else {
        timers.add(Timer(Duration(milliseconds: 1200 * k), () {
          if (!done.isCompleted) start(k);
        }));
      }
    }
    return done.future.timeout(const Duration(seconds: 22), onTimeout: () => null).whenComplete(() {
      for (final t in timers) {
        t.cancel();
      }
    });
  }

  static Future<Geo?> geo({String? proxy, int attempts = 3}) async {
    for (var i = 0; i < attempts; i++) {
      try {
        final g = await _geoOnce(proxy);
        if (g != null) return g;
      } catch (_) {}
      await Future.delayed(Duration(milliseconds: 700 * (i + 1)));
    }
    return null;
  }

  /// استعلام نمره ریسک، اصالت آی‌پی (خانگی/دیتاسنتر)، ASN و تطابق منطقه زمانی ویژه آمازون و جمینای
  static Future<IpQualityReport?> inspectQuality({String? proxy}) => inspectIpQuality(proxy: proxy);
  static Future<IpQualityReport?> inspectIpQuality({String? proxy}) async {
    try {
      final r = await _request(
        'GET',
        'http://ip-api.com/json/?fields=status,message,country,countryCode,regionName,city,zip,timezone,isp,org,as,query,proxy,hosting',
        proxy: proxy,
        timeout: 10,
      );
      if (r is Map && '${r['status']}' == 'success') {
        final ip = '${r['query'] ?? ''}';
        final country = '${r['country'] ?? ''}';
        final code = '${r['countryCode'] ?? ''}'.toUpperCase();
        final city = '${r['city'] ?? ''}';
        final isp = '${r['isp'] ?? ''}';
        final org = '${r['org'] ?? ''}';
        final asName = '${r['as'] ?? ''}';
        final tz = '${r['timezone'] ?? ''}';
        final isHosting = r['hosting'] == true;
        final isProxy = r['proxy'] == true;

        var score = 10;
        if (isHosting) score += 60;
        if (isProxy) score += 15;
        final checkText = '$isp $org $asName'.toLowerCase();
        if (checkText.contains('amazon') ||
            checkText.contains('aws') ||
            checkText.contains('hetzner') ||
            checkText.contains('digitalocean') ||
            checkText.contains('ovh') ||
            checkText.contains('contabo') ||
            checkText.contains('linode') ||
            checkText.contains('vultr') ||
            checkText.contains('google') ||
            checkText.contains('azure') ||
            checkText.contains('m247')) {
          score += 15;
        }
        score = score.clamp(0, 100);

        final clientOffset = DateTime.now().timeZoneOffset;
        final clientSign = clientOffset.isNegative ? '-' : '+';
        final clientHours = clientOffset.inHours.abs().toString().padLeft(2, '0');
        final clientMins = (clientOffset.inMinutes.abs() % 60).toString().padLeft(2, '0');
        final clientTzStr = 'UTC$clientSign$clientHours:$clientMins';

        var match = true;
        if (clientOffset.inHours == 3 && (clientOffset.inMinutes % 60) == 30 && code != 'IR') {
          match = false;
        }

        String note = '';
        if (isHosting) {
          note = 'این آی‌پی از نوع دیتاسنتر است. برای وب‌گردی عالی است؛ اما در ثبت‌نام بدون کارت آمازون ممکن است تأیید اضافی بخواهد.';
        } else {
          note = 'این آی‌پی از نوع خانگی (Residential) است؛ کاملاً کم‌خطر و مناسب برای آمازون، پی‌پال و جمینای.';
        }
        if (!match) {
          note += '\n⚠️ دقت: ساعت سیستم شما با موقعیت سرور همگام نیست. برای ثبت‌نام آمازون، ساعت ویندوز را روی ساعت سرور تنظیم کنید.';
        }

        return IpQualityReport(
          ip: ip,
          country: country,
          code: code,
          city: city,
          isp: isp,
          org: org,
          asName: asName,
          timezone: tz,
          isHosting: isHosting,
          isProxy: isProxy,
          fraudScore: score,
          timezoneMatch: match,
          clientTimezone: clientTzStr,
          note: note,
        );
      }
    } catch (_) {}

    try {
      final m = await _request('GET', 'https://ipwho.is/', proxy: proxy, timeout: 8);
      if (m is Map && m['success'] == true) {
        final ip = '${m['ip'] ?? ''}';
        final country = '${m['country'] ?? ''}';
        final code = '${m['country_code'] ?? ''}'.toUpperCase();
        final city = '${m['city'] ?? ''}';
        final conn = (m['connection'] as Map?) ?? {};
        final isp = '${conn['isp'] ?? ''}';
        final org = '${conn['org'] ?? ''}';
        final asName = 'AS${conn['asn'] ?? ''} ${conn['org'] ?? ''}';
        final tzMap = (m['timezone'] as Map?) ?? {};
        final tz = '${tzMap['id'] ?? ''}';

        final checkText = '$isp $org $asName'.toLowerCase();
        final isHosting = checkText.contains('amazon') ||
            checkText.contains('aws') ||
            checkText.contains('hetzner') ||
            checkText.contains('digitalocean') ||
            checkText.contains('ovh') ||
            checkText.contains('contabo') ||
            checkText.contains('linode') ||
            checkText.contains('vultr') ||
            checkText.contains('google') ||
            checkText.contains('hosting') ||
            checkText.contains('datacenter');

        final score = isHosting ? 75 : 15;
        final clientOffset = DateTime.now().timeZoneOffset;
        final clientSign = clientOffset.isNegative ? '-' : '+';
        final clientHours = clientOffset.inHours.abs().toString().padLeft(2, '0');
        final clientMins = (clientOffset.inMinutes.abs() % 60).toString().padLeft(2, '0');
        final clientTzStr = 'UTC$clientSign$clientHours:$clientMins';

        var match = true;
        if (clientOffset.inHours == 3 && (clientOffset.inMinutes % 60) == 30 && code != 'IR') {
          match = false;
        }

        var note = isHosting
            ? 'نوع آی‌پی: هاستینگ دیتاسنتر. برای کارهای معمولی مناسب است.'
            : 'نوع آی‌پی: مسکونی / خانگی. نمره ریسک عالی.';

        if (!match) {
          note += '\n⚠️ عدم تطابق ساعت: ساعت سیستم شما با موقعیت سرور ($country) هماهنگ نیست. برای ثبت‌نام آمازون و پی‌پال، دکمه «تنظیم خودکار ساعت» را بزنید.';
        } else {
          note += '\n✅ تطابق کامل ساعت و لوکیشن: ساعت ویندوز با موقعیت سرور کاملاً هماهنگ است (آماده برای ثبت‌نام آمازون و سرویس‌های خارجی بدون ریسک تقلب).';
        }

        return IpQualityReport(
          ip: ip,
          country: country,
          code: code,
          city: city,
          isp: isp,
          org: org,
          asName: asName,
          timezone: tz,
          isHosting: isHosting,
          isProxy: false,
          fraudScore: score,
          timezoneMatch: match,
          clientTimezone: clientTzStr,
          note: note,
        );
      }
    } catch (_) {}

    return null;
  }

  static String? _savedOriginalWindowsTz;
  static bool get isTimezoneOverridden => _savedOriginalWindowsTz != null;

  /// همگام‌سازی خودکار منطقه زمانی ویندوز با موقعیت سرور متصل‌شده
  static Future<bool> syncWindowsTimezone(String countryCode, {String? timezone}) async {
    if (!Platform.isWindows) return false;
    try {
      if (_savedOriginalWindowsTz == null) {
        final r = await Process.run('tzutil', ['/g']);
        final cur = r.stdout.toString().trim();
        if (cur.isNotEmpty && !cur.toLowerCase().contains('error')) {
          _savedOriginalWindowsTz = cur;
        }
      }

      final targetTz = _mapToWindowsTz(countryCode, timezone);
      if (targetTz.isEmpty) return false;

      var res = await Process.run('tzutil', ['/s', targetTz]);
      if (res.exitCode != 0) {
        res = await Process.run('powershell', ['-Command', "Set-TimeZone -Id '$targetTz'"]);
      }
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// بازگرداندن منطقه زمانی اصلی ویندوز (تهران) در هنگام قطع اتصال
  static Future<void> restoreWindowsTimezone() async {
    if (!Platform.isWindows) return;
    final orig = _savedOriginalWindowsTz;
    if (orig == null || orig.isEmpty) return;
    try {
      var res = await Process.run('tzutil', ['/s', orig]);
      if (res.exitCode != 0) {
        await Process.run('powershell', ['-Command', "Set-TimeZone -Id '$orig'"]);
      }
    } catch (_) {} finally {
      _savedOriginalWindowsTz = null;
    }
  }

  static String _mapToWindowsTz(String countryCode, String? timezone) {
    if (timezone != null && timezone.isNotEmpty) {
      final tzLower = timezone.toLowerCase();
      if (tzLower.contains('amsterdam') || tzLower.contains('berlin') || tzLower.contains('vienna') || tzLower.contains('stockholm') || tzLower.contains('rome')) {
        return 'W. Europe Standard Time';
      }
      if (tzLower.contains('paris') || tzLower.contains('madrid') || tzLower.contains('brussels')) {
        return 'Romance Standard Time';
      }
      if (tzLower.contains('london') || tzLower.contains('dublin') || tzLower.contains('lisbon')) {
        return 'GMT Standard Time';
      }
      if (tzLower.contains('new_york') || tzLower.contains('detroit') || tzLower.contains('toronto') || tzLower.contains('montreal')) {
        return 'Eastern Standard Time';
      }
      if (tzLower.contains('chicago') || tzLower.contains('dallas') || tzLower.contains('houston') || tzLower.contains('winnipeg')) {
        return 'Central Standard Time';
      }
      if (tzLower.contains('denver') || tzLower.contains('phoenix') || tzLower.contains('salt_lake')) {
        return 'Mountain Standard Time';
      }
      if (tzLower.contains('los_angeles') || tzLower.contains('seattle') || tzLower.contains('vancouver') || tzLower.contains('san_francisco')) {
        return 'Pacific Standard Time';
      }
      if (tzLower.contains('tokyo')) return 'Tokyo Standard Time';
      if (tzLower.contains('seoul')) return 'Korea Standard Time';
      if (tzLower.contains('singapore')) return 'Singapore Standard Time';
      if (tzLower.contains('dubai')) return 'Arabian Standard Time';
      if (tzLower.contains('sydney') || tzLower.contains('melbourne')) return 'AUS Eastern Standard Time';
    }

    final code = countryCode.toUpperCase().trim();
    if (code.startsWith('US') || code.contains('USA') || code.contains('UNITED STATES')) {
      return 'Eastern Standard Time';
    }
    if (code.startsWith('CA') || code.contains('CANADA')) {
      return 'Eastern Standard Time';
    }
    if (code.startsWith('NL') || code.contains('NETHERLANDS') ||
        code.startsWith('DE') || code.contains('GERMANY') ||
        code.startsWith('IT') || code.startsWith('AT') ||
        code.startsWith('CH') || code.startsWith('SE') ||
        code.startsWith('NO') || code.startsWith('DK')) {
      return 'W. Europe Standard Time';
    }
    if (code.startsWith('GB') || code.startsWith('UK') || code.startsWith('IE') || code.contains('UNITED KINGDOM')) {
      return 'GMT Standard Time';
    }
    if (code.startsWith('FR') || code.startsWith('ES') || code.startsWith('BE')) {
      return 'Romance Standard Time';
    }
    if (code.startsWith('TR') || code.contains('TURKEY')) {
      return 'Turkey Standard Time';
    }
    if (code.startsWith('AE') || code.contains('EMIRATES') || code.contains('DUBAI')) {
      return 'Arabian Standard Time';
    }
    if (code.startsWith('JP') || code.contains('JAPAN')) {
      return 'Tokyo Standard Time';
    }
    if (code.startsWith('SG') || code.contains('SINGAPORE')) {
      return 'Singapore Standard Time';
    }
    if (code.startsWith('AU') || code.contains('AUSTRALIA')) {
      return 'AUS Eastern Standard Time';
    }
    return 'Eastern Standard Time';
  }
}
