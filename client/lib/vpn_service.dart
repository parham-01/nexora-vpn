import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'api.dart';
import 'cores.dart';
import 'singbox_config.dart';
import 'dns_tunnel.dart';
import 'store.dart';
import 'vpn_android.dart';
import 'xray_config.dart';

enum Phase { off, connecting, on }

enum StepPhase { wait, run, done, fail }

class StepView {
  final String title;
  final String detail;
  final StepPhase state;
  const StepView(this.title, this.state, [this.detail = '']);
}

// نتیجه‌ی پینگ واقعی (Relay) یک کانفیگ؛ ms < 1 یعنی ناموفق
class PingRes {
  final String name;
  final int ms;
  const PingRes(this.name, this.ms);
}

class _Sem {
  _Sem(this.n);
  int n;
  final List<Completer<void>> _q = [];

  Future<void> acquire() async {
    if (n > 0) {
      n--;
      return;
    }
    final c = Completer<void>();
    _q.add(c);
    await c.future;
  }

  void release() {
    if (_q.isNotEmpty) {
      _q.removeAt(0).complete();
    } else {
      n++;
    }
  }
}

class VpnStatus {
  final Phase phase;
  final int up, down, upSpeed, downSpeed, seconds;
  const VpnStatus(this.phase, {this.up = 0, this.down = 0, this.upSpeed = 0, this.downSpeed = 0, this.seconds = 0});
  static const idle = VpnStatus(Phase.off);
}

class VpnService with WidgetsBindingObserver {
  static final VpnService I = VpnService._();
  VpnService._();

  final ValueNotifier<VpnStatus> status = ValueNotifier(VpnStatus.idle);
  final ValueNotifier<Geo?> geo = ValueNotifier(null);
  final ValueNotifier<String> note = ValueNotifier('');
  // مراحل ساخت تونل (برای نمایش در رابط کاربری)
  final ValueNotifier<List<StepView>> steps = ValueNotifier(const []);
  final ValueNotifier<List<DnsResult>> dnsResults = ValueNotifier(const []);
  final ValueNotifier<List<PingRes>> pingResults = ValueNotifier(const []);
  final _Sem _winSem = _Sem(Platform.isAndroid ? 3 : 8); // هم‌زمانی تست sing-box (روی گوشی کمتر)
  final _Sem _pingSem = _Sem(16);
  // پلاگین v2ray اندروید تست‌ها را پشت‌سرهم اجرا می‌کند؛ این دروازه فقط یک تست هسته را هم‌زمان رها می‌کند
  // تا Timeout هر سرور از شروع واقعی تستش حساب شود (قبلاً از لحظه‌ی صف‌شدن حساب می‌شد و بعد از ۵ سرور اول همه Timeout می‌شدند).
  final _Sem _v2Gate = _Sem(1);
  int _pingEpoch = 0;
  final Set<Process> _pingProcs = {};
  // کش نتایج پینگ (id کانفیگ ← میلی‌ثانیه؛ -1 یعنی ناموفق). با ورود به برنامه در پس‌زمینه پر می‌شود.
  final Map<String, int> pingCache = {};
  DateTime? pingCacheAt;
  final ValueNotifier<int> pingCacheRev = ValueNotifier(0);
  bool _cacheUsed = false;
  bool _bgPinging = false;
  List<DnsResult> _dns = const [];
  DnsTunnelSession? _tunnel;
  bool _askingPermission = false;
  bool _leftApp = false;
  Timer? _clearSteps;
  final AndroidVpn _android = AndroidVpn();
  bool _ready = false;
  Process? _proc;
  Process? _sbProc; // sing-box اندروید (زنجیره‌ی Xray ← SOCKS ← sing-box)
  File? _sbCfg;
  bool _sbDead = false;
  final Map<String, String> _ipCache = {};
  Timer? _tick;
  Timer? _ping;
  int _lastUp = 0;
  int _lastDown = 0;
  String _protocol = '';
  String _transport = '';
  String _session = '';
  bool _reported = false; // نشست فعال است
  bool _connectSent = false; // رویداد connect به سرور رفته است
  bool _connecting = false;
  bool _cancel = false;
  bool _procDead = false;
  String lastError = '';
  String _connId = '';
  Timer? _cfgTimer;

  bool get supported => Platform.isAndroid || _desktop;

  static bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  static String get _sep => Platform.pathSeparator;
  static String get _appDir => File(Platform.resolvedExecutable).parent.path;
  static String get _xrayDir => '$_appDir${_sep}xray';
  static String get _xrayExe => '$_xrayDir$_sep${Platform.isWindows ? 'xray.exe' : 'xray'}';
  static String _tmpFile(String name) => '${Directory.systemTemp.path}$_sep$name';

  Future<void>? _initF;

  Future<void> init() => _initF ??= _doInit();

  Future<void> _doInit() async {
    if (_ready) return;
    _ready = true;
    WidgetsBinding.instance.addObserver(this);
    Store.configs.addListener(_cfgChanged);
    _cfgTimer = Timer.periodic(const Duration(seconds: 3), (_) => Api.pollConfigs());
    unawaited(Cores.refresh());
    Timer.periodic(const Duration(seconds: 45), (_) => Cores.refresh());
    if (Platform.isAndroid) {
      await _android.init(_onAndroid);
    } else if (_desktop) {
      unawaited(_cleanupDesktopStartup());
    }
  }

  /// پاکسازی پروسه‌های رهاشده‌ی احتمالی و بازگرداندن تنظیمات شبکه دسکتاپ در شروع به کار برنامه
  Future<void> _cleanupDesktopStartup() async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/IM', 'xray.exe']);
        await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe']);
      } else {
        await Process.run('pkill', ['-9', '-x', 'xray']);
        await Process.run('pkill', ['-9', '-x', 'sing-box']);
      }
    } catch (_) {}
    await _setProxy(false);
  }

  // اگر کاربر وسط ساخت تونل / تست پینگ DNS از برنامه بیرون برود، اتصال برقرار نمی‌شود
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (!_connecting || _askingPermission) return;
    if (!Platform.isAndroid) return;
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _leftApp = true;
      _cancel = true;
      note.value = 'از برنامه خارج شدی؛ اتصال لغو شد';
    }
  }

  String _cancelCode() => _leftApp ? 'left_app' : 'cancelled';

  static const List<String> _titles = [
    'ساخت تونل شخصی',
    'تست پینگ DNS',
    'پینگ واقعی همه‌ی لوکیشن‌ها و انتخاب کمترین',
    'برقراری اتصال امن',
  ];

  void _resetSteps({bool exact = false}) {
    _clearSteps?.cancel();
    dnsResults.value = const [];
    pingResults.value = const [];
    final t = List<String>.from(_titles);
    if (exact) t[2] = 'تست پینگ لوکیشن انتخابی';
    steps.value = [for (final x in t) StepView(x, StepPhase.wait)];
  }

  void _step(int i, StepPhase st, [String detail = '']) {
    final l = List<StepView>.from(steps.value);
    if (i < 0 || i >= l.length) return;
    l[i] = StepView(l[i].title, st, detail);
    steps.value = l;
  }

  void _clearStepsLater(int seconds) {
    _clearSteps?.cancel();
    _clearSteps = Timer(Duration(seconds: seconds), () {
      if (!_connecting) {
        steps.value = const [];
        dnsResults.value = const [];
        pingResults.value = const [];
      }
    });
  }

  List<String> _dnsXray() => [for (final r in _dns.where((e) => e.ok)) r.xray];

  void _onAndroid(String state, int up, int down, int upSpeed, int downSpeed, String duration) {
    if (state == 'CONNECTED') {
      status.value = VpnStatus(Phase.on,
          up: up, down: down, upSpeed: upSpeed, downSpeed: downSpeed, seconds: _parseDuration(duration));
      if (!_connecting && !_reported) _afterConnected(Store.config.value);
    } else if (state == 'CONNECTING') {
      if (status.value.phase != Phase.on) status.value = const VpnStatus(Phase.connecting);
    } else {
      if (_connecting) return;
      _afterDisconnected();
    }
  }

  int _parseDuration(String d) {
    final p = d.split(':').map((e) => int.tryParse(e) ?? 0).toList();
    if (p.length == 3) return p[0] * 3600 + p[1] * 60 + p[2];
    if (p.length == 2) return p[0] * 60 + p[1];
    return int.tryParse(d) ?? 0;
  }

  String _newSession() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _afterConnected(Map<String, dynamic>? cfg) async {
    if (_reported) return;
    _reported = true;
    if (cfg != null) {
      final info = parseLink('${cfg['link']}');
      _protocol = info.protocol;
      _transport = info.transport;
    }
    _session = _newSession();
    await Future.delayed(const Duration(milliseconds: 500));
    if (!_reported) return;
    var g = await Api.geo(proxy: _desktop ? '127.0.0.1:10809' : null);
    // اگر کشور «ایران» برگشت یعنی هنوز ترافیک از تونل رد نشده یا از جواب قدیمی آمده؛ چند بار دوباره (کشور واقعیِ خروجی)
    for (var i = 0; i < 4 && _reported && g != null && g.code.toUpperCase() == 'IR' && cfg != null && '${cfg['code'] ?? ''}'.toUpperCase() != 'IR'; i++) {
      await Future.delayed(const Duration(milliseconds: 1500));
      g = await Api.geo(proxy: _desktop ? '127.0.0.1:10809' : null, attempts: 1) ?? g;
    }
    if (!_reported) return; // در همین فاصله قطع شده
    geo.value = g;
    if (g == null) _retryGeo();
    await Api.event({
      'type': 'connect',
      'session': _session,
      'configId': cfg == null ? '' : '${cfg['id']}',
      'protocol': _protocol,
      'transport': _transport,
      'country': g?.country ?? '',
    });
    _connectSent = true;
    if (Platform.isWindows && Store.autoTimezoneSync) {
      unawaited(Api.syncWindowsTimezone(g?.code ?? (cfg == null ? '' : '${cfg['code'] ?? ''}')));
    }
    _ping?.cancel();
    _alerted = false;
    _remindDone = false;
    _capDone = false;
    if (Store.getBool('haptic', true)) HapticFeedback.mediumImpact();
    _ping = Timer.periodic(const Duration(seconds: 60), (_) {
      final st = status.value;
      Api.event({'type': 'ping', 'session': _session, 'up': st.up, 'down': st.down, 'seconds': st.seconds});
      _applyLimits(st);
    });
  }

  bool _alerted = false;
  bool _remindDone = false;
  bool _capDone = false;

  /// گزینه‌های «قطع خودکار بعد از N ساعت» و «هشدار مصرف نشست» از تنظیمات پیشرفته
  void _applyLimits(VpnStatus st) {
    if (st.phase != Phase.on) return;
    final h = Store.autoOffHours;
    if (h > 0 && st.seconds >= h * 3600) {
      note.value = 'اتصال بعد از $h ساعت، طبق تنظیمات قطع شد';
      disconnect();
      return;
    }
    final mb = Store.usageAlertMb;
    if (mb > 0 && !_alerted && (st.up + st.down) >= mb * 1048576) {
      _alerted = true;
      note.value = 'مصرف این اتصال به ${fmtBytes(mb * 1048576)} رسید';
    }
    final rh = Store.getInt('remind_h', 0);
    if (rh > 0 && !_remindDone && st.seconds >= rh * 3600) {
      _remindDone = true;
      note.value = 'حدود $rh ساعت است که وصل هستی';
    }
    final cap = Store.getInt('total_cap_gb', 0);
    if (cap > 0 && !_capDone && (Store.statUp + Store.statDown + st.up + st.down) >= cap * 1073741824) {
      _capDone = true;
      note.value = 'مصرف کل این دستگاه به $cap گیگابایت رسید';
    }
  }

  Future<void> _retryGeo() async {
    for (var i = 0; i < 6 && _reported && geo.value == null; i++) {
      await Future.delayed(const Duration(seconds: 6));
      if (!_reported || geo.value != null) return;
      final g = await Api.geo(proxy: _desktop ? '127.0.0.1:10809' : null, attempts: 1);
      if (!_reported) return;
      if (g != null) geo.value = g;
    }
  }

  void _cfgChanged() {
    final id = _connId;
    if (id.isEmpty || status.value.phase != Phase.on) return;
    if (Store.configs.value.any((c) => '${c['id']}' == id)) return;
    note.value = 'این کانفیگ حذف شد؛ اتصال قطع شد';
    disconnect();
  }

  void _afterDisconnected() {
    if (_connectSent && Store.getBool('haptic', true)) HapticFeedback.heavyImpact();
    _connId = '';
    unawaited(_killSb());
    final s = status.value;
    if (_connectSent) {
      unawaited(Store.addUsage(s.up, s.down, s.seconds));
      Api.event({'type': 'disconnect', 'session': _session, 'up': s.up, 'down': s.down, 'seconds': s.seconds});
    }
    _reported = false;
    _connectSent = false;
    _ping?.cancel();
    _tick?.cancel();
    status.value = VpnStatus.idle;
    geo.value = null;
  }

  Future<String?> connect() async {
    if (_connecting) return 'busy';
    if (!supported) return 'unsupported';
    final list = Store.candidates();
    if (list.isEmpty) return 'no_config';
    final sid = Store.serverId;
    final exact = sid.isNotEmpty && !sid.startsWith('loc:') && list.length == 1;
    await init();
    _connecting = true;
    _cancel = false;
    _leftApp = false;
    lastError = '';
    _resetSteps(exact: exact);
    status.value = const VpnStatus(Phase.connecting);
    var err = 'error';
    try {
      final pre = await _prepare();
      if (pre != null) {
        err = pre;
      } else {
        final r = exact ? await _connectExact(list.first) : await _connectBest(list);
        if (r == null) {
          _clearStepsLater(2);
          return null;
        }
        err = r;
      }
    } catch (e) {
      lastError = '$e';
      err = 'error';
    } finally {
      _connecting = false;
      note.value = '';
    }
    await _stopCore();
    status.value = VpnStatus.idle;
    _clearStepsLater(5);
    return err;
  }

  // مرحله ۱ و ۲: ساخت تونل شخصی + تست پینگ DNS. تا کامل نشود هیچ اتصالی شروع نمی‌شود.
  Future<String?> _prepare() async {
    _step(0, StepPhase.run, 'در حال ساخت تونل شخصی...');
    _tunnel = await DnsTunnelSession.create();
    if (_cancel) return _cancelCode();
    _step(0, StepPhase.done, 'تونل شخصی ساخته شد');

    // تست DNS فقط یک «کمک» است، نه شرط اتصال: حداکثر ~۲.۵ ثانیه منتظر می‌مانیم و
    // اگر هیچ DNS جواب نداد، اتصال بدون DNS (حالت مستقیم/رمزنگاری‌شده) ادامه پیدا می‌کند.
    _step(1, StepPhase.run, 'در حال تست پینگ DNS (اختیاری)...');
    note.value = 'در حال تست پینگ DNS...';
    final found = <DnsResult>[];
    final probing = DnsProbe.probeAll(onResult: (r) {
      dnsResults.value = [...dnsResults.value, r];
      if (r.ok) found.add(r);
    });
    final firstOk = Completer<void>();
    unawaited(probing.then((_) {
      if (!firstOk.isCompleted) firstOk.complete();
    }));
    // به‌محض اولین DNS سالم ~۳۰۰ms به بقیه فرصت می‌دهیم؛ سقف کل ۲.۵ ثانیه
    final sw = Stopwatch()..start();
    while (!firstOk.isCompleted && sw.elapsedMilliseconds < 2500 && !_cancel) {
      await Future.delayed(const Duration(milliseconds: 40));
      if (found.isNotEmpty && sw.elapsedMilliseconds > 300) break;
    }
    if (_cancel) return _cancelCode();
    final ok = List<DnsResult>.from(found)..sort((a, b) => a.ms.compareTo(b.ms));
    if (ok.isEmpty) {
      // بدون DNS: خطا نمی‌دهیم؛ تونل بدون وابستگی به DNS ادامه می‌دهد
      _dns = const [];
      _step(1, StepPhase.done, 'DNS جواب نداد • حالت بدون DNS (اتصال مستقیم رمزنگاری‌شده)');
      return null;
    }
    _dns = ok;
    if (DnsTunnelSession.configured) {
      _step(1, StepPhase.run, 'در حال اتصال تونل شخصی...');
      final hs = await _tunnel!.handshake(ok);
      if (_cancel) return _cancelCode();
      if (!hs.ok) {
        // دست‌دهی از راه DNS شکست خورد؛ مانع اتصال نمی‌شود (کانال اصلی خودش رمزنگاری‌شده است)
        _step(1, StepPhase.done, 'تونل DNS بدون پاسخ • ادامه بدون DNS');
        return null;
      }
    }
    _step(1, StepPhase.done, 'کمترین پینگ: ${ok.first.ms}ms');
    return null;
  }

  // دلیل کوتاه شکست اتصال برای نمایش در مرحله‌ی «برقراری اتصال امن»
  static String _shortErr(String r) {
    // پیام ساده برای کاربر؛ دلیل دقیق در لاگ ادمین ثبت می‌شود
    return 'اتصال برقرار نشد';
  }

  Future<String?> _connectExact(Map<String, dynamic> cfg) async {
    final id = '${cfg['id']}';
    var title = cfgTitle(cfg);
    _step(2, StepPhase.run, 'در حال تست پینگ همین لوکیشن...');
    note.value = 'در حال تست پینگ $title...';
    final ms = await relayPing('${cfg['link']}', id: id);
    if (_cancel) return _cancelCode();
    if (title.length > 16) title = title.substring(0, 16);
    pingResults.value = [PingRes(title, ms)];
    pingCacheAt = DateTime.now();
    final valid = Api.validPing(ms);
    _step(2, StepPhase.done, valid ? 'پینگ همین لوکیشن: ${ms}ms' : 'پینگ جواب نداد • تلاش مستقیم برای اتصال');
    _step(3, StepPhase.run, 'در حال اتصال...');
    var err = 'timeout';
    for (var k = 0; k < 1; k++) {
      if (_cancel) return _cancelCode();
      note.value = valid ? 'اتصال با پینگ ${ms}ms' : 'در حال اتصال...';
      final r = await _attempt(cfg);
      if (_cancel) {
        await _stopCore();
        return _cancelCode();
      }
      if (r == null) {
        await Store.setConfig(cfg);
        _connId = id;
        _step(3, StepPhase.done, valid ? 'متصل شد • پینگ ${ms}ms' : 'متصل شد');
        unawaited(_afterConnected(cfg));
        return null;
      }
      err = r;
      if (r == 'permission' || r == 'no_core') {
        _step(3, StepPhase.fail, r == 'permission' ? 'دسترسی VPN داده نشد' : 'هسته اتصال پیدا نشد');
        return r;
      }
      await _stopCore();
    }
    _step(3, StepPhase.fail, _shortErr(err));
    return err;
  }

  // مرحله ۳ و ۴: اولین اتصال از نتایج کش‌شده‌ی تست پس‌زمینه استفاده می‌کند (بدون تست دوباره)؛
  // اتصال‌های بعدی تست تازه با همزمانی بالا انجام می‌دهند. کانفیگ بدون پینگ معتبر رد می‌شود.
  Future<String?> _connectBest(List<Map<String, dynamic>> all) async {
    final list = List<Map<String, dynamic>>.from(all);
    var err = 'no_valid_ping';
    var anyValid = false;
    final tried = <String>{};

    // null = وصل شد، '' = شکست (ادامه بده)، غیر از این = خطای قطعی
    Future<String?> tryOne(Map<String, dynamic> cfg, int ms) async {
      note.value = ms >= 1 ? 'اتصال با پینگ ${ms}ms' : 'در حال اتصال...';
      final r = await _attempt(cfg);
      if (_cancel) {
        await _stopCore();
        return _cancelCode();
      }
      if (r == null) {
        await Store.setConfig(cfg);
        _connId = '${cfg['id']}';
        _step(3, StepPhase.done, ms >= 1 ? 'متصل شد • پینگ ${ms}ms' : 'متصل شد');
        unawaited(_afterConnected(cfg));
        return null;
      }
      err = r;
      if (r == 'permission' || r == 'no_core') {
        _step(3, StepPhase.fail, r == 'permission' ? 'دسترسی VPN داده نشد' : 'هسته اتصال پیدا نشد');
        return r;
      }
      await _stopCore();
      return '';
    }

    // ۱) کش فقط وقتی استفاده می‌شود که تازه (کمتر از ۲ دقیقه) و برای «همه»ی کانفیگ‌ها کامل باشد
    // (مثلاً همین الان دکمه‌ی پینگ صفحه‌ی سرورها زده شده)؛ در غیر این‌صورت تست تازه‌ی همه انجام می‌شود تا واقعاً کمترین پینگ انتخاب شود.
    final at = pingCacheAt;
    final useCache = at != null &&
        DateTime.now().difference(at).inSeconds < 120 &&
        list.every((c) => pingCache.containsKey('${c['id']}'));
    _cacheUsed = true;
    if (useCache) {
      final cached = <MapEntry<Map<String, dynamic>, int>>[
        for (final c in list)
          if (Api.validPing(pingCache['${c['id']}'] ?? -1)) MapEntry(c, pingCache['${c['id']}']!)
      ]..sort((x, y) => x.value.compareTo(y.value));
      if (cached.isNotEmpty) {
        anyValid = true;
        _step(2, StepPhase.done, 'کمترین پینگ (کش): ${cached.first.value}ms');
        _step(3, StepPhase.run, 'در حال اتصال...');
        for (final e in cached) {
          if (_cancel) return _cancelCode();
          tried.add('${e.key['id']}');
          final r = await tryOne(e.key, e.value);
          if (r != '') return r;
        }
      }
    }

    // ۲) تست تازه‌ی همه‌ی کانفیگ‌ها (دسته‌های بزرگ‌تر و همزمان)
    final rest = [for (final c in list) if (!tried.contains('${c['id']}')) c];
    if (anyValid) _step(2, StepPhase.run, 'کش جواب نداد؛ تست تازه...');
    else _step(2, StepPhase.run, 'در حال تست پینگ واقعی (Relay) از داخل هسته...');
    // تست یک دسته. [early]: به‌محض رسیدن اولین پینگ معتبر فقط ~۹۰۰ms به بقیه فرصت می‌دهد و بی‌معطلی وصل می‌شود
    // (منتظر کانفیگ‌های مرده نمی‌ماند). کانفیگ‌های رهاشده بعداً (فقط اگر هیچ‌کدام وصل نشد) دوباره تست می‌شوند.
    final leftover = <Map<String, dynamic>>[];
    // null = وصل شد، '' = ادامه بده، غیر از این = خطای قطعی
    Future<String?> testChunk(List<Map<String, dynamic>> chunk, bool early) async {
      note.value = 'در حال تست پینگ واقعی...';
      final ms = List<int>.filled(chunk.length, -2); // -2 = هنوز جواب نداده
      final firstValid = Completer<void>();
      var pending = chunk.length;
      var abandoned = false;
      final all = Future.wait<void>([
        for (var i = 0; i < chunk.length; i++)
          () async {
            final c = chunk[i];
            final v = await relayPing('${c['link']}', id: '${c['id']}');
            pending--;
            if (abandoned) return;
            ms[i] = v;
            var nm = cfgTitle(c);
            if (nm.length > 16) nm = nm.substring(0, 16);
            pingResults.value = [...pingResults.value, PingRes(nm, v)];
            if (Api.validPing(v) && !firstValid.isCompleted) firstValid.complete();
          }(),
      ]);
      if (early) {
        await Future.any<void>([all, firstValid.future]);
        if (pending > 0) {
          // بعد از اولین پینگ معتبر تا ۶ ثانیه به بقیه فرصت می‌دهیم تا «کمترین» پینگ واقعاً از بین همه انتخاب شود
          await Future.any<void>([all, Future<void>.delayed(const Duration(seconds: 6))]);
          if (pending > 0) {
            abandoned = true;
            cancelPings(); // بقیه‌ی پینگ‌های در حال اجرا بسته می‌شوند
            for (var i = 0; i < chunk.length; i++) {
              if (ms[i] == -2) leftover.add(chunk[i]);
            }
          }
        }
      } else {
        await all;
      }
      pingCacheAt = DateTime.now();
      if (_cancel) return _cancelCode();
      final idx = [
        for (var i = 0; i < chunk.length; i++)
          if (Api.validPing(ms[i])) i
      ]..sort((a, b) => ms[a].compareTo(ms[b]));
      if (idx.isEmpty) return ''; // پینگ نامعتبر / Timeout → کانفیگ‌های بعدی
      if (!anyValid) {
        anyValid = true;
        _step(2, StepPhase.done, 'کمترین پینگ واقعی: ${ms[idx.first]}ms');
        _step(3, StepPhase.run, 'در حال اتصال...');
      }
      for (final i in idx) {
        if (_cancel) return _cancelCode();
        final r = await tryOne(chunk[i], ms[i]);
        if (r != '') return r;
      }
      return '';
    }

    // همه‌ی لوکیشن‌ها در یک دسته تست می‌شوند (همزمانی را _pingSem کنترل می‌کند) تا کمترین پینگ از بین همه معلوم شود
    final batch = max(rest.length, 1);
    for (var s = 0; s < rest.length; s += batch) {
      if (_cancel) return _cancelCode();
      final r = await testChunk(rest.sublist(s, min(s + batch, rest.length)), true);
      if (r != '') return r;
    }
    if (leftover.isNotEmpty) {
      final again = List<Map<String, dynamic>>.from(leftover);
      leftover.clear();
      for (var s = 0; s < again.length; s += batch) {
        if (_cancel) return _cancelCode();
        final r = await testChunk(again.sublist(s, min(s + batch, again.length)), false);
        if (r != '') return r;
      }
    }
    if (!anyValid) {
      _step(2, StepPhase.done, 'پینگ جواب نداد • تلاش مستقیم برای اتصال');
      _step(3, StepPhase.run, 'در حال اتصال...');
      for (final c in list.take(5)) {
        if (_cancel) return _cancelCode();
        final r = await tryOne(c, 0);
        if (r != '') return r;
      }
      _step(3, StepPhase.fail, 'هیچ‌کدام از کانفیگ‌ها وصل نشد • ${_shortErr(err)}');
      return err == 'no_valid_ping' ? 'timeout' : err;
    }
    _step(3, StepPhase.fail, 'هیچ‌کدام از کانفیگ‌های سالم وصل نشد • ${_shortErr(err)}');
    return err;
  }

  /// تست پینگ پس‌زمینه با ورود به برنامه؛ نتیجه در pingCache ذخیره می‌شود و اولین اتصال از آن استفاده می‌کند.
  Future<void> startBackgroundPing({bool force = false}) async {
    if (_bgPinging || _connecting || !supported) return;
    // فقط لوکیشن/کانفیگ انتخاب‌شده تست می‌شود (حالت «خودکار» همه را می‌خواهد چون باید بهترین را پیدا کند)
    final list = List<Map<String, dynamic>>.from(Store.candidates());
    if (list.isEmpty) return;
    final at = pingCacheAt;
    if (!force && at != null && DateTime.now().difference(at).inMinutes < 5 && list.every((c) => pingCache.containsKey('${c['id']}'))) return;
    _bgPinging = true;
    try {
      await init();
      var next = 0;
      Future<void> worker() async {
        while (!_connecting) {
          final i = next++;
          if (i >= list.length) return;
          final c = list[i];
          await relayPing('${c['link']}', id: '${c['id']}');
        }
      }

      await Future.wait([for (var k = 0; k < 8; k++) worker()]);
      pingCacheAt = DateTime.now();
      pingCacheRev.value++;
    } catch (_) {
    } finally {
      _bgPinging = false;
    }
  }

  /// لغو فوری همه‌ی تست‌های پینگ در حال اجرا: کارهای منتظر صفر می‌شوند و پردازه‌های xray پینگ بسته می‌شوند.
  void cancelPings() {
    _pingEpoch++;
    for (final p in _pingProcs.toList()) {
      try {
        p.kill();
      } catch (_) {}
    }
    _pingProcs.clear();
  }

  // پینگ واقعی (Relay) یک کانفیگ: ترافیک HTTP واقعی از داخل هسته‌ی پروکسی (اندروید: v2ray، ویندوز: xray).
  // TCP ساده نیست؛ همه‌ی پلتفرم‌های پشتیبانی‌شده هسته دارند.
  Future<int> relayPing(String link, {String? id}) async {
    await init();
    final info = parseLink(link);
    if (info.outbound == null) {
      if (id != null) pingCache[id] = -1;
      return -1;
    }
    // هسته‌ی این پروتکل توسط ادمین غیرفعال شده → پینگ/اتصال ندارد
    if (!Cores.allows(link)) {
      if (id != null) pingCache[id] = -1;
      return -1;
    }
    final epoch = _pingEpoch;
    await _pingSem.acquire();
    if (epoch != _pingEpoch) {
      _pingSem.release();
      return -1; // لغو شده؛ در کش ذخیره نمی‌شود
    }
    var ms = -1;
    final useGate = Platform.isAndroid && info.engine == 'xray';
    var gated = false;
    try {
      if (info.engine == 'xray' && !info.transport.contains('kcp') && !info.transport.contains('quic')) {
        final tcp = await Api.pingLink(link, timeoutSec: 2);
        if (tcp < 0) {
          if (id != null) {
            pingCache[id] = -1;
            pingCacheRev.value++;
          }
          return -1;
        }
        if (epoch != _pingEpoch) return -1;
      }
      if (useGate) {
        await _v2Gate.acquire();
        gated = true;
        if (epoch != _pingEpoch) return -1; // لغو شده
      }
      // محافظ قفل‌شدن: اگر فراخوانی بومی/هسته جواب ندهد، worker برای همیشه گیر نمی‌کند
      final Future<int> f;
      if (info.engine != 'xray') {
        // sing-box (Hysteria2/TUIC/WireGuard): همه‌ی پلتفرم‌ها (اندروید با libsingbox.so داخل APK)
        f = (_desktop || Platform.isAndroid) && info.engine == 'singbox' ? _sbDelay(link) : Future<int>.value(-1);
      } else {
        // همان DNS ای که اتصال استفاده می‌کند → «پینگ خوب» یعنی «اتصال خوب»
        f = Platform.isAndroid ? _android.delay(link, info.outbound!, dns: _dnsXray()) : (_desktop ? _winDelay(link) : Api.pingLink(link));
      }
      // مثل V2rayNG: Timeout هسته ۱۲ ثانیه است؛ این محافظ فقط برای قفل‌شدن بومی است و از شروع واقعی تست حساب می‌شود
      ms = await f.timeout(Duration(seconds: useGate ? 28 : 14), onTimeout: () => -1);
    } catch (_) {
      ms = -1;
    } finally {
      if (gated) _v2Gate.release();
      _pingSem.release();
    }
    if (epoch != _pingEpoch) return -1;
    if (id != null) {
      pingCache[id] = ms;
      pingCacheRev.value++;
    }
    return ms;
  }

  Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  Future<int> _winDelay(String link) async {
    final exe = _xrayExe;
    if (!File(exe).existsSync()) return -1;
    final epoch = _pingEpoch;
    await _winSem.acquire();
    Process? p;
    File? f;
    try {
      if (epoch != _pingEpoch) return -1;
      final hp = await _freePort();
      final sp = await _freePort();
      final ap = await _freePort();
      final conf = buildXrayConfig(link, httpPort: hp, socksPort: sp, apiPort: ap, profile: 2);
      if (conf == null) return -1;
      f = File(_tmpFile('nexora_ping_${hp}_${DateTime.now().microsecondsSinceEpoch}.json'));
      await f.writeAsString(jsonEncode(conf));
      p = await Process.start(exe, ['run', '-c', f.path], workingDirectory: _xrayDir);
      _pingProcs.add(p);
      p.stdout.listen((_) {});
      p.stderr.listen((_) {});
      var up = false;
      for (var i = 0; i < 70; i++) {
        if (epoch != _pingEpoch) return -1;
        try {
          final s = await Socket.connect('127.0.0.1', hp, timeout: const Duration(milliseconds: 150));
          s.destroy();
          up = true;
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 40));
        }
      }
      if (!up) return -1;
      return await Api.delayVia('127.0.0.1:$hp');
    } catch (_) {
      return -1;
    } finally {
      if (p != null) _pingProcs.remove(p);
      p?.kill();
      try {
        f?.deleteSync();
      } catch (_) {}
      _winSem.release();
    }
  }

  Future<String?> _attempt(Map<String, dynamic> cfg) async {
    final link = '${cfg['link']}';
    final info = parseLink(link);
    if (info.outbound == null) return 'bad_link';
    _protocol = info.protocol;
    _transport = info.transport;
    if (!Cores.allows(link)) return 'core_disabled';
    if (info.engine == 'amneziawg') return 'awg_unsupported';
    if (info.engine != 'xray') {
      if (info.engine == 'singbox' && Platform.isAndroid) return _attemptSingboxAndroid(cfg, link);
      if (info.engine == 'singbox' && _desktop) return _attemptSingbox(link);
      return 'core_missing';
    }
    if (Platform.isAndroid) {
      // پروفایل‌ها (از سخت‌ترین/امن‌ترین به ساده‌ترین): ۰) فرگمنت + DoH  ۱) outbound برنامه + DNS ساده  ۲) کانفیگ خام پلاگین (مثل v2rayNG).
      // اگر تونل بالا بیاید ولی اینترنت واقعاً کار نکند، خودکار با پروفایل بعدی دوباره امتحان می‌شود.
      var last = 'timeout';
      const profiles = 3;
      for (var profile = 0; profile < profiles; profile++) {
        if (_cancel) return _cancelCode();
        if (profile >= 1) {
          await _android.stop();
          await Future.delayed(const Duration(milliseconds: 600));
          if (_cancel) return _cancelCode();
          status.value = const VpnStatus(Phase.connecting);
        }
        bool ok;
        _askingPermission = true;
        try {
          ok = await _android.start(link, cfgTitle(cfg), info.outbound!, dns: _dnsXray(), profile: profile);
        } finally {
          await Future.delayed(const Duration(milliseconds: 400));
          _askingPermission = false;
        }
        if (!ok) return 'permission';
        if (!await _waitOn(const Duration(seconds: 10))) {
          last = 'timeout';
          continue;
        }
        // تست واقعیِ اینترنت از داخل تونل (نه فقط «وصل شد» بودنِ هسته)
        var ms = -1;
        for (var k = 0; k < 3 && !_cancel; k++) {
          ms = await Api.reachMs(timeout: 5);
          if (ms >= 1 && ms <= 8000) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }
        if (ms < 1 || ms > 8000) {
          last = 'no_internet';
          continue;
        }
        return null;
      }
      return last;
    }
    return _attemptWindows(link);
  }

  Future<bool> _waitOn(Duration max) async {
    final end = DateTime.now().add(max);
    while (DateTime.now().isBefore(end)) {
      if (_cancel) return false;
      if (status.value.phase == Phase.on) return true;
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return false;
  }

  // ---------- sing-box (دسکتاپ): Hysteria2 / TUIC / WireGuard ----------
  static String get _sbDir => '$_appDir${_sep}singbox';
  static String get _sbExe => Platform.isAndroid ? (AndroidVpn.singboxPath ?? '') : '$_sbDir$_sep${Platform.isWindows ? 'sing-box.exe' : 'sing-box'}';

  Future<int> _sbDelay(String link) async {
    final exe = _sbExe;
    if (exe.isEmpty || !File(exe).existsSync()) return -1;
    var sb = parseSingboxLink(link);
    if (sb == null) return -1;
    if (Platform.isAndroid) {
      // باینری sing-box در اندروید resolver ندارد؛ دامنه‌ی سرور را خود برنامه resolve می‌کند
      final r = await _withIp(sb);
      if (r == null) return -1;
      sb = r;
    }
    final epoch = _pingEpoch;
    await _winSem.acquire();
    Process? p;
    File? f;
    try {
      if (epoch != _pingEpoch) return -1;
      final hp = await _freePort();
      final conf = buildSingboxConfig(sb, httpPort: hp, socksPort: hp, template: Cores.templateFor(link), android: Platform.isAndroid);
      if (conf == null) return -1;
      f = File(_tmpFile('nexora_sb_ping_${hp}_${DateTime.now().microsecondsSinceEpoch}.json'));
      await f.writeAsString(jsonEncode(conf));
      p = await Process.start(exe, ['run', '-c', f.path], workingDirectory: Platform.isAndroid ? Directory.systemTemp.path : _sbDir);
      _pingProcs.add(p);
      p.stdout.listen((_) {});
      p.stderr.listen((_) {});
      var up = false;
      for (var i = 0; i < 90; i++) {
        if (epoch != _pingEpoch) return -1;
        try {
          final s = await Socket.connect('127.0.0.1', hp, timeout: const Duration(milliseconds: 150));
          s.destroy();
          up = true;
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 40));
        }
      }
      if (!up) return -1;
      return await Api.delayVia('127.0.0.1:$hp');
    } catch (_) {
      return -1;
    } finally {
      if (p != null) _pingProcs.remove(p);
      p?.kill();
      try {
        f?.deleteSync();
      } catch (_) {}
      _winSem.release();
    }
  }

  Future<String?> _attemptSingbox(String link) async {
    final exe = _sbExe;
    if (!File(exe).existsSync()) {
      lastError = 'sing-box در این مسیر پیدا نشد: $exe';
      return 'core_missing';
    }
    final sb = parseSingboxLink(link);
    if (sb == null) return 'bad_link';
    final conf = buildSingboxConfig(sb, httpPort: 10809, socksPort: 10808, template: Cores.templateFor(link));
    if (conf == null) return 'bad_link';
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe']);
      } else {
        await Process.run('pkill', ['-9', '-x', 'sing-box']);
      }
    } catch (_) {}
    final cfgFile = File(_tmpFile('nexora_singbox.json'));
    await cfgFile.writeAsString(jsonEncode(conf));
    _procDead = false;
    final p = await Process.start(exe, ['run', '-c', cfgFile.path], workingDirectory: _sbDir);
    _proc = p;
    final buf = StringBuffer();
    p.stdout.transform(utf8.decoder).listen((s) {
      if (buf.length < 2000) buf.write(s);
    });
    p.stderr.transform(utf8.decoder).listen((s) {
      if (buf.length < 2000) buf.write(s);
    });
    p.exitCode.then((_) {
      _procDead = true;
      if (identical(_proc, p) && !_connecting && status.value.phase != Phase.off) _stopWindowsState();
    });
    await Future.delayed(const Duration(milliseconds: 1500));
    if (_procDead) {
      lastError = buf.toString();
      return 'core_failed';
    }
    var pm = -1;
    for (var k = 0; k < 3 && !_cancel; k++) {
      pm = await Api.reachMs(proxy: '127.0.0.1:10809', timeout: 6);
      if (pm >= 1 && pm <= 8000) break;
      await Future.delayed(const Duration(milliseconds: 600));
    }
    if (pm < 1 || pm > 8000) return 'no_internet';
    await _setProxy(true);
    status.value = const VpnStatus(Phase.on);
    _tick?.cancel();
    final sw = Stopwatch()..start();
    // sing-box آمار ترافیک را از این مسیر نمی‌دهد؛ فقط مدت اتصال به‌روز می‌شود
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (status.value.phase == Phase.on) status.value = VpnStatus(Phase.on, seconds: sw.elapsedMilliseconds ~/ 1000);
    });
    return null;
  }

  // ---------- sing-box (اندروید): زنجیره‌ی  VPN ← Xray ← SOCKS محلی ← sing-box ----------
  // باینری sing-box به شکل libsingbox.so داخل APK است (tools/get_singbox.py android) و از پوشه‌ی کتابخانه‌های بومی اجرا می‌شود.
  Future<void> _killSb() async {
    final p = _sbProc;
    _sbProc = null;
    if (p != null) {
      try {
        p.kill(ProcessSignal.sigterm);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 120));
      try {
        p.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    try {
      _sbCfg?.deleteSync();
    } catch (_) {}
    _sbCfg = null;
  }

  // دامنه‌ی سرور → IP (اول DNS سیستم، بعد DoH). null = resolve نشد.
  Future<SingboxLink?> _withIp(SingboxLink l) async {
    final h = l.host;
    if (h.isEmpty) return null;
    if (InternetAddress.tryParse(h) != null) return l;
    final c = _ipCache[h];
    if (c != null) return l.withServerIp(c);
    String? ip;
    try {
      final r = await InternetAddress.lookup(h, type: InternetAddressType.IPv4).timeout(const Duration(seconds: 5));
      if (r.isNotEmpty) ip = r.first.address;
    } catch (_) {}
    if (ip == null) {
      for (final u in const ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query']) {
        final id = Random().nextInt(65534) + 1;
        final a = await dohPost(u, dnsQuery(h, 1, id), timeoutMs: 3000);
        if (a != null) ip = _firstA(a);
        if (ip != null) break;
      }
    }
    if (ip == null) return null;
    _ipCache[h] = ip;
    return l.withServerIp(ip);
  }

  String? _firstA(Uint8List a) {
    if (a.length < 12) return null;
    final qd = (a[4] << 8) | a[5];
    final an = (a[6] << 8) | a[7];
    int skip(int o) {
      while (o < a.length) {
        final l = a[o];
        if (l == 0) return o + 1;
        if ((l & 0xC0) == 0xC0) return o + 2;
        o += l + 1;
      }
      return o;
    }

    var i = 12;
    for (var q = 0; q < qd; q++) {
      i = skip(i) + 4;
    }
    for (var k = 0; k < an && i < a.length; k++) {
      i = skip(i);
      if (i + 10 > a.length) return null;
      final t = (a[i] << 8) | a[i + 1];
      final rl = (a[i + 8] << 8) | a[i + 9];
      i += 10;
      if (t == 1 && rl == 4 && i + 4 <= a.length) return '${a[i]}.${a[i + 1]}.${a[i + 2]}.${a[i + 3]}';
      i += rl;
    }
    return null;
  }

  Future<bool> _portUp(int port, {int tries = 60}) async {
    for (var i = 0; i < tries; i++) {
      if (_sbDead || _cancel) return false;
      try {
        final s = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 150));
        s.destroy();
        return true;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    return false;
  }

  String _lastLines(StringBuffer b) {
    final t = b.toString().trim().split('\n').where((e) => e.trim().isNotEmpty).toList();
    if (t.isEmpty) return '';
    return t.sublist(max(0, t.length - 3)).join('\n');
  }

  Future<String?> _attemptSingboxAndroid(Map<String, dynamic> cfg, String link) async {
    final exe = AndroidVpn.singboxPath;
    if (exe == null) {
      lastError = 'libsingbox.so داخل این APK نیست (مسیر کتابخانه‌ها: ${AndroidVpn.nativeLibDir ?? 'نامشخص'})';
      return 'core_missing';
    }
    final sb0 = parseSingboxLink(link);
    if (sb0 == null) return 'bad_link';
    note.value = 'در حال پیدا کردن آدرس سرور...';
    final sb = await _withIp(sb0);
    if (_cancel) return _cancelCode();
    if (sb == null) {
      lastError = 'resolve نشد: ${sb0.host}';
      return 'server_dns';
    }
    await _killSb();
    final httpPort = await _freePort();
    final socksPort = await _freePort();
    final conf = buildSingboxConfig(sb, httpPort: httpPort, socksPort: socksPort, template: Cores.templateFor(link), android: true);
    if (conf == null) return 'bad_link';
    final cf = File(_tmpFile('nexora_sb_$socksPort.json'));
    await cf.writeAsString(jsonEncode(conf));
    _sbCfg = cf;
    _sbDead = false;
    final log = StringBuffer();
    note.value = 'در حال بالا آوردن هسته‌ی sing-box...';
    Process p;
    try {
      p = await Process.start(exe, ['run', '-c', cf.path], workingDirectory: Directory.systemTemp.path);
    } catch (e) {
      lastError = '$e';
      return 'core_exec';
    }
    _sbProc = p;
    void feed(String s) {
      if (log.length < 4000) log.write(s);
    }

    p.stdout.transform(utf8.decoder).listen(feed, onError: (_) {});
    p.stderr.transform(utf8.decoder).listen(feed, onError: (_) {});
    unawaited(p.exitCode.then((code) {
      if (!identical(_sbProc, p)) return;
      _sbProc = null;
      _sbDead = true;
      if (!_connecting && status.value.phase == Phase.on) {
        note.value = 'هسته‌ی sing-box بسته شد (کد $code)؛ اتصال قطع شد';
        unawaited(_android.stop());
      }
    }));
    if (!await _portUp(socksPort)) {
      if (_cancel) return _cancelCode();
      lastError = _lastLines(log).isEmpty ? 'هسته بدون خروجی بسته شد یا پورت باز نشد' : _lastLines(log);
      return _sbDead ? 'core_failed' : 'core_timeout';
    }
    // ۱) تونل sing-box تا سرور و اینترنت: مستقیم از پروکسی محلی sing-box (بدون VPN) تست می‌شود
    note.value = 'در حال تست مسیر سرور...';
    var ms = -1;
    for (var k = 0; k < 2 && !_cancel && !_sbDead; k++) {
      ms = await Api.reachMs(proxy: '127.0.0.1:$httpPort', timeout: 6);
      if (ms >= 1 && ms <= 8000) break;
    }
    if (_cancel) return _cancelCode();
    if (ms < 1 || ms > 8000) {
      final l = _lastLines(log);
      lastError = l.isEmpty ? 'هسته بالا آمد ولی از سرور جوابی نیامد' : l;
      return _sbDead ? 'core_failed' : 'tunnel_no_internet';
    }
    // ۲) VPN اندروید (Xray) با خروجی SOCKS به sing-box؛ خود برنامه از VPN مستثنا است
    note.value = 'در حال برقراری VPN...';
    bool ok;
    _askingPermission = true;
    try {
      ok = await _android.startChain(cfgTitle(cfg), socksPort);
    } finally {
      await Future.delayed(const Duration(milliseconds: 400));
      _askingPermission = false;
    }
    if (!ok) {
      await _killSb();
      return 'permission';
    }
    if (!await _waitOn(const Duration(seconds: 10))) {
      await _killSb();
      return 'timeout';
    }
    // ۳) کل زنجیره (Xray ← sing-box ← سرور ← اینترنت) از ورودی HTTP محلیِ Xray
    var pm = -1;
    for (var k = 0; k < 3 && !_cancel && !_sbDead; k++) {
      pm = await Api.reachMs(proxy: '127.0.0.1:10809', timeout: 6);
      if (pm >= 1 && pm <= 8000) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (pm < 1 || pm > 8000) {
      lastError = _lastLines(log);
      return 'chain_failed';
    }
    return null;
  }

  /// ویندوز / مک / لینوکس: سه پروفایل از سخت‌ترین به ساده‌ترین؛ کاربر چیزی متوجه نمی‌شود.
  Future<String?> _attemptWindows(String link) async {
    var last = 'no_internet';
    for (var profile = 0; profile < 3; profile++) {
      if (_cancel) return _cancelCode();
      final r = await _attemptDesktopOnce(link, profile);
      if (r == null) return null;
      if (r == 'bad_link' || r == 'no_core' || _cancel) return r;
      last = r;
      try {
        _proc?.kill();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return last;
  }

  Future<String?> _attemptDesktopOnce(String link, int profile) async {
    final conf = buildXrayConfig(
      link,
      httpPort: 10809,
      socksPort: 10808,
      dns: _dnsXray(),
      enableFragment: true,
      profile: profile,
      upstreamProxy: Store.upstreamProxyEnabled ? Store.upstreamProxy : null,
      tune: true,
    );
    if (conf == null) return 'bad_link';
    final exe = _xrayExe;
    if (!File(exe).existsSync()) return 'no_core';
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/IM', 'xray.exe']);
      } else {
        await Process.run('pkill', ['-9', '-x', 'xray']);
      }
    } catch (_) {}
    final cfgFile = File(_tmpFile('nexora_xray.json'));
    await cfgFile.writeAsString(jsonEncode(conf));
    _procDead = false;
    final p = await Process.start(exe, ['run', '-c', cfgFile.path], workingDirectory: _xrayDir);
    _proc = p;
    final buf = StringBuffer();
    p.stdout.transform(utf8.decoder).listen((s) {
      if (buf.length < 2000) buf.write(s);
    });
    p.stderr.transform(utf8.decoder).listen((s) {
      if (buf.length < 2000) buf.write(s);
    });
    p.exitCode.then((_) {
      _procDead = true;
      if (identical(_proc, p) && !_connecting && status.value.phase != Phase.off) _stopWindowsState();
    });
    await Future.delayed(const Duration(milliseconds: 1800));
    if (_procDead) {
      lastError = buf.toString();
      return 'core_failed';
    }
    var pm = -1;
    for (var k = 0; k < 3 && !_cancel; k++) {
      pm = await Api.reachMs(proxy: '127.0.0.1:10809');
      if (pm >= 1 && pm <= 8000) break;
      await Future.delayed(const Duration(milliseconds: 700));
    }
    if (pm < 1 || pm > 8000) return 'no_internet';
    await _setProxy(true);
    _lastUp = 0;
    _lastDown = 0;
    var secs = 0;
    status.value = const VpnStatus(Phase.on);
    _tick?.cancel();
    final sw = Stopwatch()..start();
    var lastMs = 0;
    var statsBusy = false;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (statsBusy) return;
      statsBusy = true;
      try {
        final t = await _queryStats(exe);
        final nowMs = sw.elapsedMilliseconds;
        final dt = (nowMs - lastMs) / 1000.0;
        lastMs = nowMs;
        final upS = dt > 0 ? ((t[0] - _lastUp) / dt).round() : 0;
        final downS = dt > 0 ? ((t[1] - _lastDown) / dt).round() : 0;
        _lastUp = t[0];
        _lastDown = t[1];
        secs = nowMs ~/ 1000;
        if (status.value.phase == Phase.on) {
          status.value = VpnStatus(Phase.on, up: t[0], down: t[1], upSpeed: upS < 0 ? 0 : upS, downSpeed: downS < 0 ? 0 : downS, seconds: secs);
        }
      } finally {
        statsBusy = false;
      }
    });
    return null;
  }

  Future<List<int>> _queryStats(String exe) async {
    try {
      final r = await Process.run(exe, ['api', 'statsquery', '--server=127.0.0.1:10085']);
      final m = jsonDecode('${r.stdout}') as Map<String, dynamic>;
      var up = 0;
      var down = 0;
      for (final s in (m['stat'] as List? ?? [])) {
        final n = '${s['name']}';
        final v = int.tryParse('${s['value']}') ?? 0;
        if (n.endsWith('>>>uplink') && n.contains('outbound>>>proxy')) up = v;
        if (n.endsWith('>>>downlink') && n.contains('outbound>>>proxy')) down = v;
      }
      return [up, down];
    } catch (_) {
      return [_lastUp, _lastDown];
    }
  }

  Future<void> _setProxy(bool on) async {
    if (Platform.isWindows) {
      const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
      await Process.run('reg', ['add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', on ? '1' : '0', '/f']);
      if (on) {
        // فعال‌سازی هم‌زمان پروکسی HTTP و SOCKS5 در تنظیمات اینترنت ویندوز
        await Process.run('reg', ['add', key, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', 'http=127.0.0.1:10809;https=127.0.0.1:10809;socks=127.0.0.1:10808', '/f']);
        // ست کردن اتوماتیک متغیرهای محیطی برای ترمینال، گیت، نود، پایتون و ابزارهای توسعه مانند Antigravity
        try {
          await Process.run('reg', ['add', r'HKCU\Environment', '/v', 'HTTP_PROXY', '/t', 'REG_SZ', '/d', 'http://127.0.0.1:10809', '/f']);
          await Process.run('reg', ['add', r'HKCU\Environment', '/v', 'HTTPS_PROXY', '/t', 'REG_SZ', '/d', 'http://127.0.0.1:10809', '/f']);
          await Process.run('reg', ['add', r'HKCU\Environment', '/v', 'ALL_PROXY', '/t', 'REG_SZ', '/d', 'socks5://127.0.0.1:10808', '/f']);
        } catch (_) {}
      } else {
        try {
          await Process.run('reg', ['delete', r'HKCU\Environment', '/v', 'HTTP_PROXY', '/f']);
          await Process.run('reg', ['delete', r'HKCU\Environment', '/v', 'HTTPS_PROXY', '/f']);
          await Process.run('reg', ['delete', r'HKCU\Environment', '/v', 'ALL_PROXY', '/f']);
        } catch (_) {}
      }
    } else if (Platform.isMacOS) {
      await _setProxyMac(on);
    } else if (Platform.isLinux) {
      await _setProxyLinux(on);
    }
  }

  Future<void> _run(String exe, List<String> args) async {
    try {
      await Process.run(exe, args);
    } catch (_) {
      // ابزار روی این سیستم نیست؛ بقیه‌ی روش‌ها امتحان می‌شوند
    }
  }

  /// مک: پروکسی HTTP/HTTPS و SOCKS روی همه‌ی سرویس‌های شبکه (Wi‑Fi، Ethernet و ...).
  Future<void> _setProxyMac(bool on) async {
    try {
      final r = await Process.run('networksetup', ['-listallnetworkservices']);
      final services = '${r.stdout}'
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && !e.startsWith('*') && !e.startsWith('An asterisk'))
          .toList();
      for (final svc in services) {
        if (on) {
          await _run('networksetup', ['-setwebproxy', svc, '127.0.0.1', '10809']);
          await _run('networksetup', ['-setsecurewebproxy', svc, '127.0.0.1', '10809']);
          await _run('networksetup', ['-setsocksfirewallproxy', svc, '127.0.0.1', '10808']);
        }
        final st = on ? 'on' : 'off';
        await _run('networksetup', ['-setwebproxystate', svc, st]);
        await _run('networksetup', ['-setsecurewebproxystate', svc, st]);
        await _run('networksetup', ['-setsocksfirewallproxystate', svc, st]);
      }
    } catch (_) {}
  }

  /// لینوکس: GNOME (gsettings) و KDE (kwriteconfig)؛ هرکدام در دسترس بود اعمال می‌شود.
  Future<void> _setProxyLinux(bool on) async {
    const g = 'org.gnome.system.proxy';
    if (on) {
      for (final proto in ['http', 'https']) {
        await _run('gsettings', ['set', '$g.$proto', 'host', '127.0.0.1']);
        await _run('gsettings', ['set', '$g.$proto', 'port', '10809']);
      }
      await _run('gsettings', ['set', '$g.socks', 'host', '127.0.0.1']);
      await _run('gsettings', ['set', '$g.socks', 'port', '10808']);
    }
    await _run('gsettings', ['set', g, 'mode', on ? 'manual' : 'none']);
    for (final kw in ['kwriteconfig6', 'kwriteconfig5']) {
      const grp = 'Proxy Settings';
      await _run(kw, ['--file', 'kioslaverc', '--group', grp, '--key', 'ProxyType', on ? '1' : '0']);
      if (on) {
        await _run(kw, ['--file', 'kioslaverc', '--group', grp, '--key', 'httpProxy', 'http://127.0.0.1 10809']);
        await _run(kw, ['--file', 'kioslaverc', '--group', grp, '--key', 'httpsProxy', 'http://127.0.0.1 10809']);
        await _run(kw, ['--file', 'kioslaverc', '--group', grp, '--key', 'socksProxy', 'socks5://127.0.0.1 10808']);
      }
    }
  }

  Future<void> _stopWindowsState() async {
    _proc = null;
    await _setProxy(false);
    if (Platform.isWindows && Store.autoTimezoneSync) {
      unawaited(Api.restoreWindowsTimezone());
    }
    _afterDisconnected();
  }

  Future<void> _stopCore() async {
    _tick?.cancel();
    if (Platform.isAndroid) {
      await _android.stop();
      await _killSb();
      await Future.delayed(const Duration(milliseconds: 400));
      if (_connecting) status.value = const VpnStatus(Phase.connecting);
    } else if (_desktop) {
      final p = _proc;
      _proc = null;
      p?.kill();
      await _setProxy(false);
      if (Platform.isWindows && Store.autoTimezoneSync) {
        unawaited(Api.restoreWindowsTimezone());
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> disconnect() async {
    _cancel = true;
    if (Platform.isAndroid) {
      await _android.stop();
      await _killSb();
      _afterDisconnected();
    } else if (_desktop) {
      final p = _proc;
      _proc = null;
      p?.kill();
      await _setProxy(false);
      if (Platform.isWindows && Store.autoTimezoneSync) {
        unawaited(Api.restoreWindowsTimezone());
      }
      _afterDisconnected();
    } else {
      status.value = VpnStatus.idle;
    }
  }
}
