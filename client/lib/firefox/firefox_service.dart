import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../cloud_backup.dart';
import '../store.dart';
import 'core/core_api.dart';
import 'core/models.dart';

/// Independent Firefox/Guardian engine. It never reuses or edits the
/// application's existing V2Ray/Xray engine.
class FirefoxService extends ChangeNotifier {
  FirefoxService._();
  static final FirefoxService I = FirefoxService._();

  static const MethodChannel _native = MethodChannel('parham/firefox');
  static const Duration _apiStartTimeout = Duration(seconds: 30);

  CoreApi? _api;
  Process? _coreProcess;
  String? _dataDir;
  Timer? _poll;
  String? _pendingSignIn;
  bool _busy = false;
  bool _requestedOn = false;
  bool _tunInstalled = false;
  String? _error;
  CoreStatus? status;
  List<Account> accounts = const [];
  List<Location> locations = const [];
  String selectedCountry = '';

  // --- مدیریت چند اکانت ---
  static const String _kSelectedAccount = 'ff_selected_account';
  static const String _kAutoSwitch = 'ff_auto_switch';
  static const String _kDesktopMode = 'ff_desktop_mode';
  String selectedAccountId = '';
  bool autoSwitch = false;
  bool _prefsLoaded = false;
  Timer? _usageTimer;
  Timer? _fastTimer;
  bool _fastBusy = false;
  bool _usageBusy = false;
  bool _pageWatching = false;
  bool _allExhaustedNotified = false;
  final StreamController<String> _events = StreamController<String>.broadcast();
  Stream<String> get events => _events.stream;

  Account? get selectedAccount {
    if (selectedAccountId.isEmpty) return null;
    for (final a in accounts) {
      if (a.id == selectedAccountId) return a;
    }
    return null;
  }

  bool get hasSelection => selectedAccount != null;

  bool get supported => Platform.isAndroid || Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  bool get busy => _busy;
  bool get isOn => _requestedOn && supported;
  bool get connected => isOn && (status?.confirmedBy(status?.lastTest) ?? false);
  String? get error => _error;
  bool get hasAccount {
    final a = selectedAccount;
    return a != null && a.enabled && a.status == AccountStatus.ready;
  }
  bool get isReady => _api != null;

  Future<void> initialize() async {
    if (!supported) {
      _error = 'این نسخه از Nexora VPN در حال حاضر هسته‌ی اتصال Firefox را پشتیبانی نمی‌کند.';
      notifyListeners();
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _loadPrefs();
      await _ensureApi();
      await refresh();
      _updateUsageTimer();
      unawaited(CloudBackup.autoRestore());
    } catch (e) {
      _error = _friendly(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Core API for the options page (starts the core if needed).
  Future<CoreApi> ensureApi() => _ensureApi();

  /// Linux/macOS connection mode: 'set' = system proxy, 'clear' = proxy only
  /// (local SOCKS/HTTP port, nothing in system settings is changed).
  String desktopMode = 'set';

  Future<void> setDesktopMode(String mode) async {
    desktopMode = mode == 'clear' ? 'clear' : 'set';
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kDesktopMode, desktopMode);
    } catch (_) {}
    notifyListeners();
    // اگر الان وصل است، همان لحظه اعمال شود.
    if (_requestedOn && (Platform.isLinux || Platform.isMacOS)) {
      try {
        await (await _ensureApi()).setSystemProxy(desktopMode);
        await refresh();
      } catch (e) {
        _error = _friendly(e);
        notifyListeners();
      }
    }
  }

  Future<CoreApi> _ensureApi() async {
    final current = _api;
    if (current != null) {
      try {
        await current.status().timeout(const Duration(seconds: 3));
        return current;
      } catch (_) {
        current.close();
        _api = null;
      }
    }

    if (Platform.isAndroid) {
      _dataDir = await _native.invokeMethod<String>('dataDir');
      final running = await _native.invokeMethod<bool>('isRunning') ?? false;
      if (!running) await _native.invokeMethod<void>('startCore');
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final env = Platform.environment;
      final home = env['HOME'] ?? env['USERPROFILE'] ?? Directory.systemTemp.path;
      if (Platform.isWindows) {
        final local = env['LOCALAPPDATA'] ?? home;
        _dataDir = '$local\\Nexora\\FirefoxCore';
      } else if (Platform.isMacOS) {
        _dataDir = '$home/Library/Application Support/Nexora VPN/FirefoxCore';
      } else {
        _dataDir = '${env['XDG_DATA_HOME'] ?? '$home/.local/share'}/nexora-vpn/firefox-core';
      }
      await Directory(_dataDir!).create(recursive: true);
      await _startWindowsCore();
    } else {
      throw UnsupportedError('Firefox core is not available on this platform');
    }

    final dir = _dataDir;
    if (dir == null || dir.isEmpty) throw StateError('مسیر داده‌های Firefox دریافت نشد');
    final until = DateTime.now().add(_apiStartTimeout);
    Object? lastError;
    while (DateTime.now().isBefore(until)) {
      CoreApi? candidate;
      try {
        final endpoint = await CoreLocator.locate(dir);
        candidate = CoreApi(endpoint);
        await candidate.status().timeout(const Duration(seconds: 3));
        _api = candidate;
        return candidate;
      } catch (e) {
        candidate?.close();
        lastError = e;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw StateError('هسته Firefox بالا نیامد: ${lastError ?? 'timeout'}');
  }

  Future<void> _startWindowsCore() async {
    if (_coreProcess != null) return;
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final coreName = Platform.isWindows ? 'nexora-vpn-core.exe' : 'nexora-vpn-core';
    final exe = File('$appDir${Platform.pathSeparator}firefox-core${Platform.pathSeparator}$coreName');
    if (!await exe.exists()) {
      throw StateError('فایل firefox-core/$coreName کنار برنامه پیدا نشد؛ خروجی برنامه باید همراه پوشه firefox-core باشد.');
    }
    final process = await Process.start(
      exe.path,
      ['-app', '-data-dir=$_dataDir'],
      workingDirectory: exe.parent.path,
      mode: ProcessStartMode.normal,
    );
    _coreProcess = process;
    try {
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      process.exitCode.then((_) {
        if (identical(_coreProcess, process)) {
          _coreProcess = null;
          _api?.close();
          _api = null;
          _requestedOn = false;
          _error = 'هسته Firefox متوقف شد';
          notifyListeners();
        }
      }).catchError((_) {});
    } catch (_) {}
  }

  Future<void> refresh() async {
    final api = await _ensureApi();
    final values = await Future.wait<Object>([
      api.status(),
      api.accounts(),
      api.locations(),
    ]);
    status = values[0] as CoreStatus;
    accounts = (values[1] as AccountList).accounts;
    locations = (values[2] as LocationList).locations;
    if (selectedAccountId.isNotEmpty && !accounts.any((a) => a.id == selectedAccountId)) {
      selectedAccountId = '';
      unawaited(_savePrefs());
    }
    if (selectedCountry.isEmpty && status!.selection.isNotEmpty) {
      selectedCountry = status!.selection;
    }
    if (status?.proxyOn == true) {
      _requestedOn = true;
      _startFast();
    } else {
      _stopFast();
      if (_requestedOn) {
        _requestedOn = false;
        _poll?.cancel();
        _poll = null;
      }
    }
    notifyListeners();
    unawaited(_reportStats());
    CloudBackup.schedule();
  }

  void _startFast() {
    if (_fastTimer != null) return;
    _fastTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final api = _api;
      if (api == null || _fastBusy) return;
      _fastBusy = true;
      try {
        status = await api.status().timeout(const Duration(seconds: 2));
      } catch (_) {
      } finally {
        _fastBusy = false;
      }
    });
  }

  void _stopFast() {
    _fastTimer?.cancel();
    _fastTimer = null;
  }

  String _maskEmail(String e) {
    final i = e.indexOf('@');
    if (i < 1) return e.isEmpty ? '' : '${e.substring(0, e.length < 2 ? e.length : 2)}***';
    final name = e.substring(0, i);
    return '${name.substring(0, name.length < 2 ? name.length : 2)}***${e.substring(i)}';
  }

  String _lastReport = '';
  DateTime _lastReportAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// آمار اکانت‌ها برای پنل ادمین؛ فقط وقتی داده تغییر کند یا حداکثر هر ۵ دقیقه یک‌بار ارسال می‌شود.
  Future<void> _reportStats() async {
    try {
      final rows = <Map<String, dynamic>>[
        for (final a in accounts)
          {
            'id': a.id,
            'label': _maskEmail(a.email.isEmpty ? a.name : a.email),
            'enabled': a.enabled,
            'active': a.enabled && !a.needsSignIn,
            'unlimited': a.usage?.unlimited ?? false,
            'used': a.usage?.usedBytes ?? 0,
            'limit': a.usage?.limitBytes ?? 0,
            'remaining': (a.usage?.remainingBytes ?? 0) < 0 ? 0 : (a.usage?.remainingBytes ?? 0),
          }
      ];
      final sig = rows.map((r) => '${r['id']}|${r['enabled']}|${r['active']}|${r['limit']}|${(r['remaining'] as int) ~/ 1048576}').join(',');
      final now = DateTime.now();
      if (sig == _lastReport && now.difference(_lastReportAt).inMinutes < 5) return;
      _lastReport = sig;
      _lastReportAt = now;
      await Api.reportFirefox(rows);
    } catch (_) {}
  }

  Future<String?> openSignInProxy({int port = 0}) async {
    final api = await _ensureApi();
    try {
      return await api.openSignInProxy(port: port);
    } catch (_) {
      // Direct browser access remains available when the core cannot create
      // the optional sign-in proxy (for example, a restricted local network).
      return null;
    }
  }

  Future<void> closeSignInProxy() async {
    try { await _api?.closeSignInProxy(); } catch (_) {}
  }

  Future<bool> setWebViewProxy(String? address) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _native.invokeMethod<bool>('setWebViewProxy', {'address': address}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> addBrowserSession(String email, String sessionToken) async {
    final api = await _ensureApi();
    final state = await api.startBrowserSignIn(email, sessionToken);
    final id = state.id;
    if (id.isEmpty) throw StateError('Mozilla ورود را شروع نکرد');
    _pendingSignIn = id;
    try {
      var current = state;
      final until = DateTime.now().add(const Duration(minutes: 3));
      while (!current.finished && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (_pendingSignIn != id) throw StateError('ورود لغو شد');
        current = await api.signInState(id);
      }
      if (!current.finished) throw TimeoutException('تأیید ورود Mozilla بیش از حد طول کشید');
      if (current.step != SignInStep.done) {
        throw StateError(current.error.isNotEmpty ? current.error : (current.message.isNotEmpty ? current.message : 'ورود Firefox کامل نشد'));
      }
      await refresh();
      await _applyPolicySafe();
    } finally {
      if (_pendingSignIn == id) _pendingSignIn = null;
    }
  }

  /// ورود مستقیم با ایمیل و پسورد: درخواست به هسته می‌رود و هسته آن را به API
  /// حساب‌های Mozilla می‌فرستد. پسورد فقط روی loopback به هسته داده می‌شود.
  Future<SignInState> startPasswordSignIn(String email, String password) async {
    final api = await _ensureApi();
    final state = await api.startSignIn(email, password);
    if (state.id.isEmpty) throw StateError('Mozilla ورود را شروع نکرد');
    _pendingSignIn = state.id;
    return state;
  }

  Future<void> removeAccount(String id) async {
    final api = await _ensureApi();
    await api.removeAccount(id);
    if (selectedAccountId == id) {
      selectedAccountId = '';
      await _savePrefs();
    }
    await refresh();
    await _applyPolicySafe();
    unawaited(Api.forgetFirefox(id));
    _lastReport = '';
    if (accounts.isEmpty) unawaited(CloudBackup.markEmptied());
  }

  Future<SignInState> signInStatus(String id) async => (await _ensureApi()).signInState(id);

  Future<SignInState> answerSignIn(String id, String value) async =>
      (await _ensureApi()).answerSignIn(id, value);

  /// بعد از موفقیت ورود: لیست را تازه می‌کند و اگر این اولین/تنها اکانت است
  /// خودکار انتخابش می‌کند. هیچ‌کدام از این مراحل اجازه ندارد صفحه‌ی ورود را
  /// گیر بیندازد (اکانت در هسته اضافه شده است)، پس خطاها قورت داده می‌شوند.
  Future<void> finishPasswordSignIn() async {
    _pendingSignIn = null;
    try {
      await refresh();
    } catch (_) {}
    try {
      if (selectedAccountId.isEmpty && accounts.length == 1) {
        await selectAccount(accounts.first.id);
      }
    } catch (_) {}
    try {
      await _applyPolicySafe();
    } catch (_) {}
  }

  Future<void> cancelBrowserSignIn() async {
    final id = _pendingSignIn;
    _pendingSignIn = null;
    if (id == null) return;
    try {
      await _api?.cancelSignIn(id);
    } catch (_) {}
  }

  // ====================== چند اکانت / سوییچ خودکار ======================

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      selectedAccountId = p.getString(_kSelectedAccount) ?? '';
      autoSwitch = p.getBool(_kAutoSwitch) ?? false;
      desktopMode = p.getString(_kDesktopMode) ?? 'set';
    } catch (_) {}
    _prefsLoaded = true;
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kSelectedAccount, selectedAccountId);
      await p.setBool(_kAutoSwitch, autoSwitch);
    } catch (_) {}
  }

  /// کاربر یک اکانت را انتخاب می‌کند (تیک می‌خورد). تا قبل از این، لیست کشورها نمایش داده نمی‌شود.
  Future<void> selectAccount(String id) async {
    final api = await _ensureApi();
    selectedAccountId = id;
    _allExhaustedNotified = false;
    await _savePrefs();
    notifyListeners();
    await _applyPolicy(api);
    await api.activateAccount(id);
    await refresh();
  }

  Future<void> setAutoSwitch(bool value) async {
    autoSwitch = value;
    _allExhaustedNotified = false;
    await _savePrefs();
    notifyListeners();
    try {
      final api = await _ensureApi();
      if (value) await _ensureThreshold(api);
      await _applyPolicy(api);
      await refresh();
    } catch (e) {
      _error = _friendly(e);
      notifyListeners();
    }
    _updateUsageTimer();
    if (value) unawaited(_usageTick());
  }

  /// سیاست اکانت‌ها: سوییچ خودکار خاموش → فقط اکانت انتخابی فعال است؛
  /// روشن → همه‌ی اکانت‌ها فعال و ترتیب: انتخابی اول، بعد بقیه به ترتیب لیست.
  Future<void> _applyPolicy(CoreApi api) async {
    if (selectedAccountId.isEmpty) return;
    final list = [...(await api.accounts()).accounts]..sort((a, b) => a.position.compareTo(b.position));
    for (final a in list) {
      final should = a.id == selectedAccountId || (autoSwitch && !a.needsSignIn);
      if (a.enabled != should) {
        try { await api.setAccountEnabled(a.id, should); } catch (_) {}
      }
    }
    if (autoSwitch) {
      final ids = [
        selectedAccountId,
        for (final a in list) if (a.id != selectedAccountId) a.id,
      ];
      try { await api.setAccountOrder(ids); } catch (_) {}
    }
  }

  Future<void> _applyPolicySafe() async {
    try {
      final api = _api;
      if (api != null) {
        await _applyPolicy(api);
        await refresh();
      }
    } catch (_) {}
  }

  /// آستانه‌ی سوییچ هسته روی ۱۰۰٪ تا از کل حجم هر اکانت استفاده شود.
  Future<void> _ensureThreshold(CoreApi api) async {
    try {
      final cfg = await api.settings();
      final raw = cfg['accounts'];
      final acc = raw is Map ? Map<String, Object?>.from(raw) : <String, Object?>{};
      final cur = acc['switch_threshold_percent'];
      if (cur is num && cur.toDouble() >= 100) return;
      acc['switch_threshold_percent'] = 100;
      cfg['accounts'] = acc;
      await api.saveSettings(cfg);
    } catch (_) {}
  }

  /// صفحه‌ی اکانت‌ها مصرف را زنده نگه می‌دارد؛ با سوییچ خودکار روشن، پایش حتی بیرون از صفحه هم ادامه دارد.
  void watchUsage(bool on) {
    _pageWatching = on;
    _updateUsageTimer();
    if (on) unawaited(_usageTick());
  }

  void _updateUsageTimer() {
    final want = (_pageWatching || autoSwitch) && supported && _api != null;
    if (want && _usageTimer == null) {
      _usageTimer = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_usageTick()));
    } else if (!want) {
      _usageTimer?.cancel();
      _usageTimer = null;
    }
  }

  bool _exhausted(Account a) {
    final u = a.usage;
    if (a.reasonCode == 'quota_exhausted') return true;
    return u != null && !u.unlimited && u.limitBytes > 0 && u.remainingBytes <= 0;
  }

  bool _usable(Account a) => !a.needsSignIn && a.status != AccountStatus.unavailable && !_exhausted(a);

  Future<void> _usageTick() async {
    final api = _api;
    if (api == null || _usageBusy) return;
    _usageBusy = true;
    try {
      final current = (await api.accounts()).accounts;
      await Future.wait<void>([
        for (final a in current)
          if (!a.needsSignIn) api.refreshAccount(a.id).catchError((Object _) {}),
      ]);
      accounts = (await api.accounts()).accounts;
      notifyListeners();
      unawaited(_reportStats());
      if (autoSwitch) await _autoSwitchIfNeeded(api);
    } catch (_) {
      // پایش بعدی دوباره تلاش می‌کند
    } finally {
      _usageBusy = false;
    }
  }

  Future<void> _autoSwitchIfNeeded(CoreApi api) async {
    final cur = selectedAccount;
    if (cur == null || !_exhausted(cur)) {
      _allExhaustedNotified = false;
      return;
    }
    final list = [...accounts]..sort((a, b) => a.position.compareTo(b.position));
    final idx = list.indexWhere((a) => a.id == cur.id);
    final candidates = [...list.skip(idx + 1), ...list.take(idx)];
    Account? next;
    for (final a in candidates) {
      if (_usable(a)) {
        next = a;
        break;
      }
    }
    if (next == null) {
      if (!_allExhaustedNotified) {
        _allExhaustedNotified = true;
        _events.add('حجم همه‌ی اکانت‌ها تمام شده است');
      }
      return;
    }
    selectedAccountId = next.id;
    _allExhaustedNotified = false;
    await _savePrefs();
    await api.setAccountEnabled(next.id, true);
    await api.activateAccount(next.id);
    await _applyPolicy(api);
    await refresh();
    final label = next.email.isEmpty ? next.name : next.email;
    _events.add('حجم اکانت قبلی تمام شد؛ به $label سوییچ شد');
  }

  Future<void> selectLocation(String code) async {
    final api = await _ensureApi();
    await api.setLocation(code);
    selectedCountry = code;
    await refresh();
  }

  // ---- تست پینگ «فقط یک لوکیشن» (همان که کاربر انتخاب کرده؛ هیچ‌وقت همه‌ی لوکیشن‌ها با هم تست نمی‌شوند) ----
  bool _pinging = false;
  int _pingEpoch = 0;
  String? pingingCode;
  Completer<void>? _pingCancel;

  bool get pinging => _pinging;
  bool pingingAll = false;

  /// پینگ همه‌ی لوکیشن‌ها یک‌جا (هسته همه را موازی تست می‌کند). خروجی: تعداد لوکیشن‌های جواب‌داده، -1 = لغو/انجام‌نشد.
  Future<int> pingAllLocations() async {
    if (_pinging) return -1;
    final epoch = ++_pingEpoch;
    final cancel = _pingCancel = Completer<void>();
    bool alive() => epoch == _pingEpoch;
    _pinging = true;
    pingingAll = true;
    pingingCode = null;
    _busy = true;
    _error = null;
    notifyListeners();
    CoreApi? api;
    var startedForTest = false;
    try {
      api = await _ensureApi();
      if (!alive()) return -1;
      startedForTest = !_requestedOn;
      if (startedForTest) await api.setPower(true);
      if (!alive()) return -1;
      final result = await Future.any<LocationList?>([
        api.pingLocations(const [], timeout: const Duration(seconds: 60)),
        cancel.future.then((_) => null),
      ]);
      if (result == null || !alive()) return -1;
      final byCode = {for (final l in result.locations) l.code: l};
      locations = [for (final l in locations) byCode[l.code] ?? l];
      return result.locations.where((l) => l.pingMs > 0).length;
    } catch (e) {
      if (!alive()) return -1;
      _error = _friendly(e);
      rethrow;
    } finally {
      if (startedForTest && api != null) {
        try { await api.setPower(false); } catch (_) {}
      }
      if (alive()) {
        _pinging = false;
        pingingAll = false;
        pingingCode = null;
        _busy = false;
        notifyListeners();
      }
    }
  }

  /// تست پینگ را همان لحظه متوقف می‌کند: UI بلافاصله آزاد می‌شود و نتیجه‌ی درخواست در حال اجرا نادیده گرفته می‌شود.
  void cancelPing() {
    if (!_pinging) return;
    _pingEpoch++;
    final c = _pingCancel;
    if (c != null && !c.isCompleted) c.complete();
    _pinging = false;
    pingingAll = false;
    pingingCode = null;
    _busy = false;
    notifyListeners();
  }

  /// پینگ واقعی (از داخل هسته) فقط برای [code].
  /// خروجی: میلی‌ثانیه (>0)، 0 = جواب نداد / Timeout، -1 = لغو شد یا انجام نشد.
  Future<int> pingLocation(String code) async {
    if (_pinging || code.isEmpty) return -1;
    final epoch = ++_pingEpoch;
    final cancel = _pingCancel = Completer<void>();
    bool alive() => epoch == _pingEpoch;

    _pinging = true;
    pingingCode = code;
    _busy = true;
    _error = null;
    notifyListeners();
    CoreApi? api;
    var startedForTest = false;
    try {
      api = await _ensureApi();
      if (!alive()) return -1;
      // پروکسی هسته باید روشن باشد. اگر وصل هستیم همان استفاده می‌شود (سریع‌ترین حالت)؛
      // اگر خاموش است، فقط برای همین یک تست روشن و بعدش خاموش می‌شود.
      startedForTest = !_requestedOn;
      if (startedForTest) await api.setPower(true);
      if (!alive()) return -1;
      // سریع‌تر، بدون کم‌کردن Timeout (همان ۱۲ ثانیه می‌ماند): درخواست دوم هم‌زمان («Hedge»)
      // اگر اولی ~۱.۲ ثانیه جواب ندهد شروع می‌شود و هر کدام زودتر پینگ معتبر داد برنده است.
      final done = Completer<LocationList?>();
      var failed = 0, total = 1;
      void settle(LocationList? r, {required bool last}) {
        if (done.isCompleted) return;
        final ms = r == null ? 0 : (r.locations.where((l) => l.code == code).map((l) => l.pingMs).firstOrNull ?? 0);
        if (r != null && ms > 0) {
          done.complete(r);
        } else if (last) {
          done.complete(r);
        }
      }
      void launch() {
        api!.pingLocations([code], timeout: const Duration(seconds: 12)).then<void>(
          (r) {
            failed++;
            settle(r, last: failed >= total);
          },
          onError: (Object _) {
            failed++;
            if (failed >= total && !done.isCompleted) done.complete(null);
          },
        );
      }
      launch();
      final hedge = Timer(const Duration(milliseconds: 1200), () {
        if (!done.isCompleted && alive()) {
          total = 2;
          launch();
        }
      });
      // اگر کاربر لغو کند، منتظر پایان درخواست نمی‌مانیم.
      final result = await Future.any<LocationList?>([done.future, cancel.future.then((_) => null)]);
      hedge.cancel();
      if (result == null || !alive()) {
        return -1;
      }
      final byCode = {for (final l in result.locations) l.code: l};
      locations = [for (final l in locations) byCode[l.code] ?? l];
      return byCode[code]?.pingMs ?? 0;
    } catch (e) {
      if (!alive()) return -1;
      _error = _friendly(e);
      rethrow;
    } finally {
      if (startedForTest && api != null) {
        try { await api.setPower(false); } catch (_) {}
      }
      if (alive()) {
        _pinging = false;
        pingingCode = null;
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> connect() async {
    if (!supported) throw UnsupportedError(_error ?? 'Firefox در این پلتفرم پشتیبانی نمی‌شود');
    if (accounts.isEmpty) throw StateError('ابتدا یک حساب Firefox اضافه کن');
    if (!accounts.any((a) => a.enabled && a.status == AccountStatus.ready)) {
      throw StateError('هیچ حساب Firefox فعالی وجود ندارد؛ حساب را دوباره وارد کن یا فعالش کن.');
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final api = await _ensureApi();
      await api.setLocation(selectedCountry);
      if (Platform.isAndroid) {
        // CoreService owns the separate Firefox VpnService/TUN stack.
        await _native.invokeMethod<void>('setOn', {'on': true});
      } else if (Platform.isWindows) {
        // تونل کامل (نصب سرویس با مجوز مدیر). اگر نشد، به‌جای شکست کامل با «پروکسی سیستم» وصل می‌شویم.
        var tunReady = false;
        try {
          final desktopStatus = await api.status();
          if (!desktopStatus.tunSupported) {
            throw StateError('هسته Firefox امکان ساخت تونل کامل در این سیستم Windows را گزارش نکرد.');
          }
          await _installWindowsTunService();
          await api.setSystemProxy('tun');
          tunReady = true;
        } catch (e) {
          final why = _friendly(e);
          _events.add('تونل کامل ساخته نشد؛ با پروکسی سیستم وصل می‌شوم. دلیل: ${why.length > 120 ? why.substring(0, 120) : why}');
        }
        if (!tunReady) {
          await _loadPrefs();
          await api.setSystemProxy(desktopMode == 'clear' ? 'clear' : 'set');
        }
        await api.setPower(true);
      } else {
        // لینوکس و مک: پروکسی سیستم یا فقط پروکسی (طبق انتخاب کاربر در گزینه‌ها)
        await _loadPrefs();
        await api.setSystemProxy(desktopMode);
        await api.setPower(true);
      }
      if (Platform.isWindows && Store.autoTimezoneSync) {
        unawaited(Api.syncWindowsTimezone(selectedCountry));
      }
      _requestedOn = true;
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) {
        refresh().catchError((Object e) {
          _error = _friendly(e);
          notifyListeners();
        });
      });
      await refresh();
    } catch (e) {
      _requestedOn = false;
      _error = _friendly(e);
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _installWindowsTunService() async {
    if (_tunInstalled) return;
    // Avoid prompting for elevation on every connection when the service
    // was already installed by a previous app run.
    final installed = (await _api?.status())?.tun?.installed ?? false;
    if (installed) {
      _tunInstalled = true;
      return;
    }
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final tun = File('$appDir${Platform.pathSeparator}firefox-core${Platform.pathSeparator}nexora-vpn-tun.exe');
    if (!await tun.exists()) throw StateError('فایل nexora-vpn-tun.exe همراه خروجی Windows پیدا نشد');
    final q = "'${tun.path.replaceAll("'", "''")}'";
    // نکته: \" داخل رشته‌ی خام یک بک‌اسلش واقعی می‌شد و PowerShell خطای Parse می‌داد (پنجره‌ی UAC نمی‌آمد).
    final command = r'$p = Start-Process -FilePath ' + q + r" -ArgumentList 'install' -Verb RunAs -Wait -PassThru; exit $p.ExitCode";
    final result = await Process.run('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', command]);
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      throw StateError('نصب سرویس تونل Windows ناموفق بود یا مجوز مدیر لغو شد: $stderr');
    }
    _tunInstalled = true;
  }

  Future<void> disconnect() async {
    _poll?.cancel();
    _poll = null;
    try {
      if (Platform.isAndroid) {
        await _native.invokeMethod<void>('setOn', {'on': false});
      } else if (_api != null) {
        await _api!.setPower(false);
        await _api!.setSystemProxy('clear');
      }
      if (Platform.isWindows && Store.autoTimezoneSync) {
        unawaited(Api.restoreWindowsTimezone());
      }
    } finally {
      _requestedOn = false;
      await refresh().catchError((_) {});
      notifyListeners();
    }
  }

  String _friendly(Object error) {
    if (error is CoreApiException) return error.message;
    if (error is CoreUnavailable) return 'هسته Firefox در دسترس نیست (${error.problem.name}) ${error.detail}';
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    _poll?.cancel();
    _usageTimer?.cancel();
    _stopFast();
    _events.close();
    _api?.close();
    super.dispose();
  }
}
