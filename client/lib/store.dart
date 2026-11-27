import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// افکت‌های سنگین (آرورا، بلور شیشه‌ای، هاور و درخشش‌ها) روی همه‌ی پلتفرم‌ها پیش‌فرض خاموش است؛
// ویندوز، مک و لینوکس دقیقاً مثل اندروید در «حالت سبک» اجرا می‌شوند (کرش و کندی نداشته باشند).
final bool kFancy = false;

/// نسخه‌ی نمایشی برنامه (باید با pubspec یکی باشد)؛ در پروفایل و پنل ادمین دیده می‌شود
const String kAppVersion = '1.0.2';

class P {
  final Color bg, card, border, text, sub, accent, accent2;
  const P(this.bg, this.card, this.border, this.text, this.sub, this.accent, this.accent2);

  static const dark = P(
    Color(0xFF040A1C),
    Color(0xFF0A1530),
    Color(0xFF1C4C99),
    Colors.white,
    Color(0xFF8FA6CC),
    Color(0xFF2F8CFF),
    Color(0xFF33B5FF),
  );

  static const light = P(
    Color(0xFFF2F6FF),
    Colors.white,
    Color(0xFFC9D9F2),
    Color(0xFF0F1B33),
    Color(0xFF5B6B85),
    Color(0xFF1F6FE0),
    Color(0xFF0098D8),
  );

  static P of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? dark : light;
}

class Store {
  static late SharedPreferences _p;
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.dark);
  static final ValueNotifier<Map<String, dynamic>?> config = ValueNotifier(null);
  static final ValueNotifier<bool> fetched = ValueNotifier(false);
  // «بهینه‌سازی برنامه» پیش‌فرض روشن است (اندروید، ویندوز، مک و لینوکس)
  static final ValueNotifier<bool> lite = ValueNotifier(true);
  static final ValueNotifier<List<Map<String, dynamic>>> configs = ValueNotifier([]);

  /// فقط در اولین اجرا true است (تا پایان همان اجرا ثابت می‌ماند) — افکت‌ها و راهنمای ورود فقط یک‌بار
  static bool firstRun = false;
  static bool get introSeen => _p.getBool('introSeen') ?? false;
  static Future<void> setIntroSeen() => _p.setBool('introSeen', true);

  /// نام کاربر (قبل از ورود به برنامه انتخاب می‌شود و در پروفایل/تنظیمات نمایش داده می‌شود)
  static final ValueNotifier<String> userName = ValueNotifier('');
  static Future<void> setUserName(String v) async {
    final t = v.trim();
    await _p.setString('userName', t);
    userName.value = t;
    onChanged?.call();
  }

  /// بعد از هر تغییر تنظیمات صدا زده می‌شود (بکاپ خودکارِ گاوصندوق از آن استفاده می‌کند)
  static void Function()? onChanged;

  static int getInt(String k, int d) => _p.getInt(k) ?? d;
  static Future<void> setInt(String k, int v) async {
    await _p.setInt(k, v);
    onChanged?.call();
  }

  // ---- گزینه‌های پروفایل و تنظیمات پیشرفته ----
  /// نام کاربر برای ادمین فرستاده شود؟ (پیش‌فرض بله)
  static bool get confirmDisconnect => _p.getBool('confirm_disconnect') ?? false;
  /// قطع خودکار اتصال بعد از N ساعت (0 = خاموش)
  static int get autoOffHours => _p.getInt('auto_off_h') ?? 0;
  /// هشدار مصرف هر نشست بر حسب مگابایت (0 = خاموش)
  static int get usageAlertMb => _p.getInt('usage_alert_mb') ?? 0;

  // ---- آمار مصرف روی همین دستگاه (برای صفحه‌ی پروفایل) ----
  static int get installAt => _p.getInt('install_at') ?? 0;
  static int get statUp => _p.getInt('st_up') ?? 0;
  static int get statDown => _p.getInt('st_down') ?? 0;
  static int get statSeconds => _p.getInt('st_secs') ?? 0;
  static int get statSessions => _p.getInt('st_sessions') ?? 0;
  static int get statMaxSession => _p.getInt('st_max') ?? 0;

  static Future<void> addUsage(int up, int down, int secs) async {
    if (up <= 0 && down <= 0 && secs <= 0) return;
    await _p.setInt('st_up', statUp + (up < 0 ? 0 : up));
    await _p.setInt('st_down', statDown + (down < 0 ? 0 : down));
    await _p.setInt('st_secs', statSeconds + (secs < 0 ? 0 : secs));
    await _p.setInt('st_sessions', statSessions + 1);
    if (up + down > statMaxSession) await _p.setInt('st_max', up + down);
  }

  static Future<void> clearUsageStats() async {
    for (final k in ['st_up', 'st_down', 'st_secs', 'st_sessions', 'st_max']) {
      await _p.remove(k);
    }
  }

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    userName.value = (_p.getString('userName') ?? '').trim();
    if (_p.getInt('install_at') == null) await _p.setInt('install_at', DateTime.now().millisecondsSinceEpoch);
    if (_p.getBool('monthly_reset') ?? false) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _p.getInt('st_reset_at') ?? _p.getInt('install_at') ?? now;
      if (now - last >= 30 * 86400000) {
        await clearUsageStats();
        await _p.setInt('st_reset_at', now);
      }
    }
    firstRun = !(_p.getBool('introSeen') ?? false);
    // کلید جدید lite3: مقدار قدیمی (lite2) نادیده گرفته می‌شود تا همه‌ی دستگاه‌ها یک‌بار با «روشن» شروع کنند
    lite.value = _p.getBool('lite3') ?? true;
    final t = _p.getString('theme') ?? 'dark';
    themeMode.value = t == 'light'
        ? ThemeMode.light
        : t == 'system'
            ? ThemeMode.system
            : ThemeMode.dark;
    // کانفیگ‌های سرور دیگر از فایل/کش خوانده نمی‌شوند؛ فقط زنده از دیتابیس
    await _p.remove('configs');
    final rawCustom = _p.getString('customConfigs');
    if (rawCustom != null) {
      try {
        _custom = (jsonDecode(rawCustom) as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
      } catch (_) {}
    }
    _merge();
    // انتخاب قبلیِ کانفیگ‌های ادمین از فایل/کش خوانده نمی‌شود (ممکن است در ادمین حذف شده باشد)؛ فقط سرور شخصی
    final raw = _p.getString('config');
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if ('${m['id']}'.startsWith('custom-')) config.value = m;
      } catch (_) {}
    }
    await _p.remove('configs');
    applySelection();
    fetched.value = config.value != null;
    if (_p.getString('deviceId') == null) {
      final r = Random.secure();
      final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _p.setString('deviceId', id);
    }
  }

  static List<Map<String, dynamic>> _server = [];
  static List<Map<String, dynamic>> _custom = [];
  // بعد از اولین خواندنِ موفق از دیتابیس true می‌شود؛ تا آن موقع انتخاب کاربر پاک نمی‌شود
  static bool _serverLoaded = false;

  static List<Map<String, dynamic>> get serverConfigs => _server;
  static List<Map<String, dynamic>> get customConfigs => _custom;
  static bool isCustom(Map<String, dynamic> c) => '${c['id']}'.startsWith('custom-');

  static void _merge() {
    configs.value = [..._custom, ..._server];
  }

  static Future<void> addCustom(Map<String, dynamic> c) async {
    _custom = [c, ..._custom];
    await _p.setString('customConfigs', jsonEncode(_custom));
    _merge();
    applySelection();
  }

  static Future<void> updateCustom(String id, Map<String, dynamic> c) async {
    _custom = [for (final e in _custom) '${e['id']}' == id ? c : e];
    await _p.setString('customConfigs', jsonEncode(_custom));
    _merge();
    applySelection();
  }

  static Future<void> removeCustom(String id) async {
    _custom = _custom.where((e) => '${e['id']}' != id).toList();
    await _p.setString('customConfigs', jsonEncode(_custom));
    if (serverId == id) await setServerId('');
    _merge();
    applySelection();
  }

  static String get deviceId => _p.getString('deviceId')!;

  static Map<String, dynamic> get geoCache {
    try {
      return (jsonDecode(_p.getString('geoCache') ?? '{}') as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static Future<void> setGeoCache(Map<String, dynamic> m) => _p.setString('geoCache', jsonEncode(m));

  static Map<String, dynamic>? _byId(String id) {
    for (final c in configs.value) {
      if ('${c['id']}' == id) return c;
    }
    return null;
  }

  static String locKey(Map<String, dynamic> c) {
    final code = '${c['code'] ?? ''}'.toUpperCase();
    if (code.length == 2) return code;
    final n = '${c['country'] ?? ''}';
    return n.isEmpty ? '' : n;
  }

  static List<Map<String, dynamic>> inLocation(String key) =>
      configs.value.where((c) => locKey(c) == key).toList();

  static List<Map<String, dynamic>> locations() {
    final m = <String, Map<String, dynamic>>{};
    for (final c in configs.value) {
      final k = locKey(c);
      if (k.isEmpty) continue;
      final e = m.putIfAbsent(k, () => {'key': k, 'country': '${c['country'] ?? k}', 'code': '${c['code'] ?? ''}', 'count': 0});
      e['count'] = (e['count'] as int) + 1;
    }
    return m.values.toList();
  }

  static void applySelection() {
    var sid = serverId;
    // انتخابِ کهنه (سرور شخصیِ حذف‌شده یا کانفیگی که ادمین حذف کرده) → برگشت به «خودکار»
    if (sid.isNotEmpty) {
      final gone = sid.startsWith('loc:')
          ? (_serverLoaded && inLocation(sid.substring(4)).isEmpty)
          : (_byId(sid) == null && (sid.startsWith('custom-') || _serverLoaded));
      if (gone) {
        sid = '';
        _p.remove('serverId');
      }
    }
    Map<String, dynamic>? sel;
    if (sid.startsWith('loc:')) {
      final l = inLocation(sid.substring(4));
      if (l.isNotEmpty) sel = l.first;
    } else if (sid.isNotEmpty) {
      sel = _byId(sid);
    }
    if (sel == null) {
      final cur = config.value;
      if (cur != null && _byId('${cur['id']}') != null) {
        sel = _byId('${cur['id']}');
      } else if (configs.value.isNotEmpty) {
        sel = configs.value.first;
      }
    }
    config.value = sel;
    fetched.value = sel != null;
  }

  static List<Map<String, dynamic>> candidates() {
    final sid = serverId;
    if (sid.startsWith('loc:')) {
      final l = inLocation(sid.substring(4));
      if (l.isNotEmpty) return l;
    } else if (sid.isNotEmpty) {
      final c = _byId(sid);
      if (c != null) return [c];
    }
    final all = List<Map<String, dynamic>>.from(configs.value);
    final cur = config.value;
    if (cur != null) {
      final i = all.indexWhere((e) => '${e['id']}' == '${cur['id']}');
      if (i > 0) {
        final x = all.removeAt(i);
        all.insert(0, x);
      }
    }
    return all;
  }

  static Future<void> setConfigs(List<Map<String, dynamic>> list) async {
    _serverLoaded = true;
    // کانفیگ‌های ادمین هرگز با پیشوند custom- نیستند؛ سرور شخصی همیشه جدا نگه داشته می‌شود
    _server = list.where((e) => !'${e['id']}'.startsWith('default-') && !'${e['id']}'.startsWith('custom-')).toList();
    _merge();
    applySelection();
  }

  static Future<void> setLite(bool v) async {
    lite.value = v;
    await _p.setBool('lite3', v);
  }

  static String getStr(String k) => _p.getString(k) ?? '';
  static Future<void> setStr(String k, String v) async {
    await _p.setString(k, v);
    onChanged?.call();
  }

  static bool getBool(String k, bool d) => _p.getBool(k) ?? d;
  static Future<void> setBool(String k, bool v) async {
    await _p.setBool(k, v);
    onChanged?.call();
  }

  static String get serverId => _p.getString('serverId') ?? '';
  static Future<void> setServerId(String v) => _p.setString('serverId', v);

  static Future<void> setTheme(ThemeMode m) async {
    themeMode.value = m;
    await _p.setString('theme', m == ThemeMode.light ? 'light' : m == ThemeMode.system ? 'system' : 'dark');
  }

  static Future<void> setConfig(Map<String, dynamic>? c) async {
    config.value = c;
    if (c == null || !'${c['id']}'.startsWith('custom-')) {
      await _p.remove('config');
    } else {
      await _p.setString('config', jsonEncode(c));
    }
  }

  static Future<void> clearCache() async {
    await _p.remove('config');
    await _p.remove('configs');
    _server = [];
    _merge();
    config.value = null;
    applySelection();
  }

  static bool get stealth => _p.getBool('stealth_fragment') ?? true;
  static Future<void> setStealth(bool v) => _p.setBool('stealth_fragment', v);

  static String get upstreamProxy => (_p.getString('upstream_proxy') ?? '').trim();
  static Future<void> setUpstreamProxy(String v) => _p.setString('upstream_proxy', v.trim());

  static bool get upstreamProxyEnabled => _p.getBool('upstream_proxy_on') ?? false;
  static Future<void> setUpstreamProxyEnabled(bool v) => _p.setBool('upstream_proxy_on', v);

  static bool get autoTimezoneSync => _p.getBool('auto_timezone_sync') ?? true;
  static Future<void> setAutoTimezoneSync(bool v) => _p.setBool('auto_timezone_sync', v);

  static Future<void> resetSettings() async {
    for (final k in ['autoConnect', 'notif', 'battery', 'system', 'advNotif', 'serverId', 'theme', 'lite2', 'lite3', 'stealth_fragment', 'upstream_proxy', 'upstream_proxy_on', 'auto_timezone_sync', 'confirm_disconnect', 'auto_off_h', 'usage_alert_mb', 'haptic', 'show_traffic', 'remind_h', 'total_cap_gb', 'monthly_reset', 'st_reset_at', 'dns_choice', 'block_quic', 'block_torrent', 'block_stun', 'mux_on']) {
      await _p.remove(k);
    }
    themeMode.value = ThemeMode.dark;
    lite.value = true;
    applySelection();
  }
}

String fmtBytes(num b) {
  if (b < 1024) return '${b.toInt()} B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String fmtDuration(int s) {
  final h = (s ~/ 3600).toString().padLeft(2, '0');
  final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final x = (s % 60).toString().padLeft(2, '0');
  return '$h:$m:$x';
}
