import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'api.dart';
import 'dns_tunnel.dart';
import 'firefox/flag_colors.dart';
import 'geo_atlas.dart';
import 'store.dart';
import 'vpn_service.dart';

const Color _kBlue = Color(0xFF33B5FF);
const Color _kGreen = Color(0xFF29E07F);
const Color _kRed = Color(0xFFFF5B5B);

/// نتیجه‌ی اتصال: error == null یعنی موفق.
class GlobeOutcome {
  final String? error;
  const GlobeOutcome(this.error);
}

class GlobeController {
  final ValueNotifier<GlobeOutcome?> outcome = ValueNotifier<GlobeOutcome?>(null);
  final ValueNotifier<List<PingRes>> pings = ValueNotifier<List<PingRes>>(const []);
  final ValueNotifier<int> total = ValueNotifier<int>(0);
  bool pingMode = false;
  bool cancelRequested = false;
  final Completer<void> _cancelSignal = Completer<void>();
  Future<void> get cancelled => _cancelSignal.future;

  /// لغو فوری: هم پرچم لغو را می‌گذارد و هم هر انتظاری که روی تست مانده را آزاد می‌کند.
  void requestCancel() {
    cancelRequested = true;
    if (!_cancelSignal.isCompleted) _cancelSignal.complete();
  }

  String code = '';
  String name = '';
  String sub = '';
  void addPing(PingRes r) => pings.value = [...pings.value, r];
  void finish(String? error, {String code = '', String name = '', String sub = ''}) {
    this.code = code;
    this.name = name;
    this.sub = sub;
    outcome.value = GlobeOutcome(error);
  }
}

/// صفحه‌ی تمام‌صفحه‌ی اتصال با کره‌ی زمین دیجیتال:
/// هنگام ساخت تونل و تست پینگ‌ها کره می‌چرخد؛ بعد از اتصال به کشور می‌رود، مرزش روشن می‌شود و
/// نام انگلیسی کشور نوشته می‌شود؛ اگر اتصال شکست بخورد، کره از وسط ترک می‌خورد و می‌افتد.
class ConnectGlobe {
  static bool _open = false;

  static Future<String?> runTest(
    BuildContext context,
    Future<String?> Function(GlobeController ctl) test,
    String Function(String) errText,
  ) async {
    final ctl = GlobeController()..pingMode = true;
    // با زدن «لغو تست پینگ» نتیجه‌ی تست منتظر نمی‌ماند؛ همان لحظه 'cancelled' برمی‌گردد.
    Future<String?> raced() {
      final f = test(ctl);
      return Future.any<String?>([f, ctl.cancelled.then<String?>((_) => 'cancelled')]);
    }

    if (_open) return raced();
    return _go(context, raced, errText, ctl);
  }

  static Future<String?> run(
    BuildContext context,
    Future<String?> Function() connect,
    String Function(String) errText,
  ) async {
    final ctl = GlobeController();
    // «لغو» همان لحظه جواب می‌دهد، بدون انتظار برای پایان تلاش اتصال.
    Future<String?> raced() => Future.any<String?>([connect(), ctl.cancelled.then<String?>((_) => 'cancelled')]);
    if (_open) return connect();
    return _go(context, raced, errText, ctl);
  }

  static Future<String?> _go(
    BuildContext context,
    Future<String?> Function() connect,
    String Function(String) errText,
    GlobeController ctl,
  ) async {
    _open = true;
    final nav = Navigator.of(context);
    final closed = nav.push<void>(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => ConnectGlobePage(ctl: ctl, errText: errText),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
    String? r;
    try {
      r = await connect();
    } catch (_) {
      r = 'error';
    }
    ctl.finish(r);
    try {
      await closed;
    } finally {
      _open = false;
    }
    return r;
  }
}

class _GlobeModel {
  double t = 0;
  double lon = 0.6, lat = 0.38; // رادیان
  double hl = 0; // روشن شدن مرز کشور
  double crack = 0, split = 0, fall = 0, flash = 0, tint = 0;
  double pulse = 0;
  GeoCountry? country;
  String flagCode = ''; // رنگ پرچم کشور مقصد برای پر کردن خاک روی کره
  // لوکیشن قبلی (مبدأ) و پیشرفت نوار سبز تا لوکیشن جدید
  bool hasOrigin = false;
  double oLon = 0, oLat = 0; // رادیان
  double tLon = 0, tLat = 0; // رادیان (مقصد)
  double link = 0; // 0..1 طول نوار سبز
  double stream = 0; // جریان ذرات راست به چپ در حال اتصال
  double appear = 0; // ظاهر شدن کره
}

enum _Mode { working, pendingOk, ok, fail }

class ConnectGlobePage extends StatefulWidget {
  final GlobeController ctl;
  final String Function(String) errText;
  const ConnectGlobePage({super.key, required this.ctl, required this.errText});

  @override
  State<ConnectGlobePage> createState() => _ConnectGlobePageState();
}

class _ConnectGlobePageState extends State<ConnectGlobePage> with SingleTickerProviderStateMixin {
  final _GlobeModel _m = _GlobeModel();
  final ValueNotifier<int> _rev = ValueNotifier<int>(0);
  late final Ticker _tk;
  late final bool _lite = Store.lite.value;

  _Mode _mode = _Mode.working;
  double _t = 0, _modeAt = 0;
  double _fromLon = 0, _fromLat = 0, _toLon = 0, _toLat = 0, _midLon = 0, _midLat = 0;
  bool _hasTarget = false;
  bool _showName = false, _showFail = false, _closed = false, _cancelling = false;
  String _name = '', _code = '', _err = '';
  GeoCountry? _country;
  // مبدأ: لوکیشن واقعی/قبلی کاربر قبل از اتصال
  double _homeLon = 0, _homeLat = 0;
  bool _hasHome = false;
  String _homeCode = '';

  static const List<String> _heads = [
    'در حال ساخت تونل شخصی…',
    'در حال تست پینگ DNS…',
    'در حال تست پینگ واقعی (Relay)…',
    'در حال برقراری اتصال امن…',
  ];

  @override
  void initState() {
    super.initState();
    GeoAtlas.preload();
    _resolveHome();
    _tk = createTicker(_onTick)..start();
    widget.ctl.outcome.addListener(_onOutcome);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onOutcome();
    });
  }

  @override
  void dispose() {
    widget.ctl.outcome.removeListener(_onOutcome);
    GeoAtlas.ready.removeListener(_applyHome);
    _tk.dispose();
    _rev.dispose();
    super.dispose();
  }

  // مبدأ: اول کش «کشور واقعی کاربر» که از اتصال‌های قبلی ذخیره شده، بعد یک استعلام مستقیم سریع.
  Future<void> _resolveHome() async {
    var code = Store.getStr('homeGeoCode');
    if (code.length != 2) {
      try {
        final g = await Api.geo(attempts: 1);
        if (g != null && g.code.length == 2) {
          code = g.code.toUpperCase();
          await Store.setStr('homeGeoCode', code);
        }
      } catch (_) {}
    }
    if (code.length != 2) code = 'IR';
    _homeCode = code;
    _applyHome();
  }

  void _applyHome() {
    final atlas = GeoAtlas.ready.value;
    if (atlas == null) {
      GeoAtlas.ready.addListener(_applyHome);
      return;
    }
    GeoAtlas.ready.removeListener(_applyHome);
    final co = atlas.byCode(_homeCode);
    if (co == null) return;
    _homeLon = co.cLon * pi / 180;
    _homeLat = (co.cLat * pi / 180).clamp(-1.2, 1.2).toDouble();
    _hasHome = true;
  }

  double _ease(double p) {
    if (p < 0.5) return 4 * p * p * p;
    final q = -2 * p + 2;
    return 1 - q * q * q / 2;
  }

  void _onTick(Duration d) {
    final t = d.inMicroseconds / 1000000.0;
    final dt = (t - _t).clamp(0.0, 0.1).toDouble();
    _t = t;
    final m = _m;
    m.t = t;
    m.pulse = (t * 0.7) % 1.0;
    m.appear = min(1.0, m.appear + dt * 1.4);
    m.hasOrigin = _hasHome;
    m.oLon = _homeLon;
    m.oLat = _homeLat;
    switch (_mode) {
      case _Mode.working:
      case _Mode.pendingOk:
        // چرخش: سطح کره از راست به چپ می‌رود
        m.lon += dt * 0.42;
        m.lat += (0.34 - m.lat) * min(1.0, dt * 2);
        m.stream = (m.stream + dt * 0.9) % 1.0;
        m.link = 0;
        if (_mode == _Mode.pendingOk) _tryResolve();
        break;
      case _Mode.ok:
        final p = ((t - _modeAt) / 2.6).clamp(0.0, 1.0).toDouble();
        final e = _ease(p);
        if (_hasTarget) {
          // منحنی بزیه‌ی درجه ۲ که از نقطه‌ی میانی مسیر عبور می‌کند
          final cLon = 2 * _midLon - (_fromLon + _toLon) / 2;
          final cLat = 2 * _midLat - (_fromLat + _toLat) / 2;
          final q = 1 - e;
          m.lon = q * q * _fromLon + 2 * q * e * cLon + e * e * _toLon;
          m.lat = q * q * _fromLat + 2 * q * e * cLat + e * e * _toLat;
        } else {
          m.lon += dt * 0.3;
        }
        // نوار سبز از لوکیشن قبلی تا لوکیشن جدید (از راست به چپ رسم می‌شود)
        m.link = _hasHome && _hasTarget ? ((t - _modeAt - 0.15) / 1.9).clamp(0.0, 1.0).toDouble() : 0;
        m.stream = (m.stream + dt * 0.7) % 1.0;
        m.hl = ((t - _modeAt - 1.5) / 0.9).clamp(0.0, 1.0).toDouble();
        if (!_showName && t - _modeAt > 1.7) setState(() => _showName = true);
        if (t - _modeAt > 5.8) _close();
        break;
      case _Mode.fail:
        final c = t - _modeAt;
        // کره سالم می‌ماند (دیگر نصف نمی‌شود/نمی‌افتد)؛ فقط قرمز می‌شود و می‌ایستد.
        m.tint = (c / 0.7).clamp(0.0, 1.0).toDouble();
        m.flash = (1 - c / 0.28).clamp(0.0, 1.0).toDouble();
        m.crack = 0;
        m.split = 0;
        m.fall = 0;
        m.lon += dt * 0.42 * (1 - m.tint);
        if (!_showFail && c > 0.9) setState(() => _showFail = true);
        if (c > 8.0) _close();
        break;
    }
    _rev.value++;
  }

  void _onOutcome() {
    final o = widget.ctl.outcome.value;
    if (o == null || _closed || _mode == _Mode.ok || _mode == _Mode.fail || _mode == _Mode.pendingOk) return;
    final e = o.error;
    if (e == null) {
      setState(() {
        _mode = _Mode.pendingOk;
        _modeAt = _t;
      });
    } else if (e == 'busy' || e == 'unsupported' || e == 'no_config' || e == 'cancelled') {
      _close();
    } else {
      setState(() {
        _err = e;
        _mode = _Mode.fail;
        _modeAt = _t;
      });
    }
  }

  // کشور خروجی: اول IP واقعی بعد از اتصال (حداکثر ۱٫۸ ثانیه صبر)، وگرنه کشور کانفیگ
  void _tryResolve() {
    final pm = widget.ctl.pingMode;
    final g = pm ? null : VpnService.I.geo.value;
    if (!pm && g == null && _t - _modeAt < 1.8) return;
    var code = pm ? widget.ctl.code : (g?.code ?? '');
    var name = pm ? widget.ctl.name : (g?.country ?? '');
    if (code.length != 2 && !pm) {
      final c = Store.config.value;
      code = '${c?['code'] ?? ''}';
      if (name.isEmpty) name = '${c?['country'] ?? ''}';
      if (code.length != 2) {
        final gc = Store.geoCache[Api.hostOf('${c?['link'] ?? ''}')];
        if (gc is List && gc.length == 2) {
          if (name.isEmpty) name = '${gc[0]}';
          code = '${gc[1]}';
        }
      }
    }
    final atlas = GeoAtlas.ready.value;
    final co = atlas?.byCode(code) ?? atlas?.byName(name);
    if (name.isEmpty || RegExp(r'[^\x00-\x7F]').hasMatch(name)) name = co?.name ?? name;
    _country = co;
    _name = name;
    _code = code;
    if (!pm && code.length == 2 && code.toUpperCase() == _homeCode.toUpperCase()) {
      // استعلام اولیه احتمالاً بعد از بالا آمدن تونل بوده؛ مبدأ معتبر نیست.
      _hasHome = false;
      Store.setStr('homeGeoCode', '');
    }
    _m.country = co;
    _m.flagCode = code;
    if (co != null) {
      _fromLon = _m.lon;
      _fromLat = _m.lat;
      final target = co.cLon * pi / 180;
      final tlat = (co.cLat * pi / 180).clamp(-0.95, 0.95).toDouble();
      _m.tLon = target;
      _m.tLat = tlat;
      _toLat = tlat;
      if (_hasHome && !(code.toUpperCase() == _homeCode.toUpperCase())) {
        // دوربین از وسط مسیر مبدأ→مقصد رد می‌شود تا کل نوار سبز دیده شود
        final ma = cos(_homeLat) * sin(_homeLon) + cos(tlat) * sin(target);
        final mb = cos(_homeLat) * cos(_homeLon) + cos(tlat) * cos(target);
        final ms = sin(_homeLat) + sin(tlat);
        final ml = sqrt(ma * ma + mb * mb + ms * ms);
        var midLon = target, midLat = tlat;
        if (ml > 1e-3) {
          midLon = atan2(ma, mb);
          midLat = asin((ms / ml).clamp(-1.0, 1.0).toDouble()).clamp(-0.95, 0.95).toDouble();
        }
        // همیشه شرق‌سو می‌چرخد تا سطح کره از راست به چپ برود
        var d1 = (midLon - _fromLon) % (2 * pi);
        if (d1 < 0.8) d1 += 2 * pi;
        _midLon = _fromLon + d1;
        _midLat = midLat;
        var d2 = (target - _midLon) % (2 * pi);
        if (d2 > pi) d2 -= 2 * pi;
        _toLon = _midLon + d2;
      } else {
        var delta = (target - _fromLon) % (2 * pi);
        if (delta < 1.6) delta += 2 * pi;
        _toLon = _fromLon + delta;
        _midLon = (_fromLon + _toLon) / 2;
        _midLat = (_fromLat + _toLat) / 2;
      }
      _hasTarget = true;
    }
    setState(() {
      _mode = _Mode.ok;
      _modeAt = _t;
    });
  }

  void _close() {
    if (_closed) return;
    if (!mounted) {
      _closed = true;
      return;
    }
    _closed = true;
    final r = ModalRoute.of(context);
    final nav = Navigator.of(context);
    if (r == null) return;
    if (r.isCurrent) {
      nav.pop();
    } else if (r.isActive) {
      nav.removeRoute(r);
    }
  }

  void _userCancel() {
    if (_mode == _Mode.ok || _mode == _Mode.fail || _mode == _Mode.pendingOk) {
      _close();
      return;
    }
    if (_mode != _Mode.working || _cancelling) return;
    if (widget.ctl.pingMode) {
      // پینگ: همان لحظه متوقف می‌شود (کارگرها، هسته‌ی پینگ و صفحه).
      widget.ctl.requestCancel();
      VpnService.I.cancelPings();
      _cancelling = true;
      _close();
      return;
    }
    widget.ctl.requestCancel();
    VpnService.I.disconnect();
    _cancelling = true;
    _close();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _userCancel();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF071A40),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if ((_mode == _Mode.ok && _showName) || (_mode == _Mode.fail && _showFail)) _close();
          },
          child: Stack(fit: StackFit.expand, children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF071A40), Color(0xFF030814)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(child: CustomPaint(painter: _GlobePainter(_m, _rev, _lite))),
            ),
            SafeArea(
              child: Column(children: [
                const SizedBox(height: 12),
                const Text('NEXORA VPN', style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 4, fontWeight: FontWeight.w700)),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: KeyedSubtree(key: ValueKey<int>(_mode.index), child: _panel()),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _panel() {
    switch (_mode) {
      case _Mode.working:
        return widget.ctl.pingMode ? _pingPanel() : _workingPanel();
      case _Mode.pendingOk:
        return _textPanel(widget.ctl.pingMode ? 'در حال انتخاب بهترین سرور…' : 'تأیید اتصال و تشخیص کشور…', _kGreen);
      case _Mode.ok:
        return _okPanel();
      case _Mode.fail:
        return _failPanel();
    }
  }

  Widget _textPanel(String t, Color c) => SizedBox(
        height: 120,
        child: Center(child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: c, fontSize: 17, fontWeight: FontWeight.w800))),
      );

  Widget _workingPanel() {
    return ValueListenableBuilder<List<StepView>>(
      valueListenable: VpnService.I.steps,
      builder: (context, steps, _) {
        final running = steps.indexWhere((e) => e.state == StepPhase.run);
        final title = _cancelling ? 'در حال لغو…' : (running >= 0 && running < _heads.length ? _heads[running] : 'آماده‌سازی…');
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final s in steps) _stepRow(s),
          const SizedBox(height: 6),
          _chips(),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _cancelling ? null : _userCancel,
            style: TextButton.styleFrom(backgroundColor: const Color(0x33FF5B5B), padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10)),
            child: const Text('لغو اتصال', style: TextStyle(color: Color(0xFFFF8A8A), fontWeight: FontWeight.w800)),
          ),
        ]);
      },
    );
  }

  Widget _pingPanel() {
    return ValueListenableBuilder<List<PingRes>>(
      valueListenable: widget.ctl.pings,
      builder: (context, pings, _) => ValueListenableBuilder<int>(
        valueListenable: widget.ctl.total,
        builder: (context, total, __) {
          final shown = pings.length > 14 ? pings.sublist(pings.length - 14) : pings;
          final title = _cancelling ? 'در حال لغو…' : 'در حال تست پینگ واقعی (Relay)…';
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(total > 0 ? '${pings.length} / $total' : '…', textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 10),
            if (total > 0) ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: (pings.length / total).clamp(0.0, 1.0).toDouble(), minHeight: 4, color: _kBlue, backgroundColor: Colors.white12),
            ),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
              for (final r in shown) _chip(r.ms >= 1 ? '${r.name} ${r.ms}ms' : '${r.name} ✕', r.ms >= 1),
            ]),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _cancelling ? null : _userCancel,
              style: TextButton.styleFrom(backgroundColor: const Color(0x33FF5B5B), padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10)),
              child: const Text('لغو تست پینگ', style: TextStyle(color: Color(0xFFFF8A8A), fontWeight: FontWeight.w800)),
            ),
          ]);
        },
      ),
    );
  }

  Widget _stepRow(StepView s) {
    Widget icon;
    Color col = Colors.white;
    switch (s.state) {
      case StepPhase.wait:
        icon = const Icon(Icons.radio_button_unchecked, size: 18, color: Colors.white38);
        col = Colors.white38;
        break;
      case StepPhase.run:
        icon = const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _kBlue));
        break;
      case StepPhase.done:
        icon = const Icon(Icons.check_circle_rounded, size: 18, color: _kGreen);
        col = _kGreen;
        break;
      case StepPhase.fail:
        icon = const Icon(Icons.cancel_rounded, size: 18, color: _kRed);
        col = _kRed;
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        icon,
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title, style: TextStyle(color: col, fontSize: 13.5, fontWeight: FontWeight.w700)),
            if (s.detail.isNotEmpty && s.state != StepPhase.wait)
              Text(s.detail, style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
          ]),
        ),
      ]),
    );
  }

  Widget _chip(String label, bool ok) {
    final c = ok ? _kGreen : _kRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withOpacity(0.5)),
      ),
      child: Text(label, textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _chips() {
    return ValueListenableBuilder<List<DnsResult>>(
      valueListenable: VpnService.I.dnsResults,
      builder: (context, dns, _) => ValueListenableBuilder<List<PingRes>>(
        valueListenable: VpnService.I.pingResults,
        builder: (context, pings, _) {
          final shown = pings.length > 8 ? pings.sublist(pings.length - 8) : pings;
          return Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            for (final r in dns) _chip(r.ok ? '${r.name} ${r.ms}ms' : '${r.name} ✕', r.ok),
            for (final r in shown) _chip(r.ms >= 1 ? '${r.name} ${r.ms}ms' : '${r.name} ✕', r.ms >= 1),
          ]);
        },
      ),
    );
  }

  Widget _okPanel() {
    final co = _country;
    final flag = _code.length == 2 ? flagOf(_code) : '🌐';
    return AnimatedOpacity(
      opacity: _showName ? 1 : 0,
      duration: const Duration(milliseconds: 600),
      child: SizedBox(
        height: 150,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(widget.ctl.pingMode ? 'کمترین پینگ واقعی' : 'شما متصل شدید', style: TextStyle(color: _kGreen, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (co != null) ...[
                CountryFlagCard(country: co, code: _code, size: 104),
                const SizedBox(width: 18),
              ],
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(_name.isEmpty ? (widget.ctl.pingMode ? 'Best Server' : 'Connected') : _name,
                        style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  ),
                  const SizedBox(height: 2),
                  Text(widget.ctl.pingMode ? widget.ctl.sub : '$flag  CONNECTED', style: const TextStyle(color: _kGreen, fontSize: 13, letterSpacing: 3, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _failPanel() {
    return AnimatedOpacity(
      opacity: _showFail ? 1 : 0,
      duration: const Duration(milliseconds: 500),
      child: SizedBox(
        height: 150,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(widget.ctl.pingMode ? 'تست پینگ ناموفق بود' : 'اتصال برقرار نشد', style: TextStyle(color: _kRed, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(widget.errText(_err), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6)),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kRed, padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 11)),
            onPressed: _close,
            child: const Text('بستن', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}

// ----------------------------- نقاشی کره (سه‌بعدی) -----------------------------

class _GlobePainter extends CustomPainter {
  final _GlobeModel m;
  final bool lite;
  late final List<Float32List> _gr;
  final List<Float32List?> _bins = <Float32List?>[null, null, null, null];
  GeoAtlas? _binsFor;

  late final Float32List _clouds;

  _GlobePainter(this.m, Listenable repaint, this.lite) : super(repaint: repaint) {
    _gr = _grat();
    final rnd = Random(11);
    final n = lite ? 26 : 56;
    final s = Float32List(n * 4);
    for (var i = 0; i < n; i++) {
      s[i * 4] = rnd.nextDouble() * 6.283 - 3.1416;
      s[i * 4 + 1] = asin(rnd.nextDouble() * 1.7 - 0.85);
      s[i * 4 + 2] = 0.07 + rnd.nextDouble() * 0.11;
      s[i * 4 + 3] = 0.5 + rnd.nextDouble() * 0.5;
    }
    _clouds = s;
  }

  List<Float32List> _grat() {
    final out = <Float32List>[];
    for (var lat = -60; lat <= 60; lat += 30) {
      final fa = lat * pi / 180;
      final cf = cos(fa);
      final pts = <double>[];
      for (var lon = -180; lon <= 180; lon += 6) {
        final la = lon * pi / 180;
        pts
          ..add(cf * sin(la))
          ..add(cf * cos(la))
          ..add(sin(fa));
      }
      out.add(Float32List.fromList(pts));
    }
    for (var lon = -180; lon < 180; lon += 30) {
      final la = lon * pi / 180;
      final pts = <double>[];
      for (var lat = -90; lat <= 90; lat += 6) {
        final fa = lat * pi / 180;
        final cf = cos(fa);
        pts
          ..add(cf * sin(la))
          ..add(cf * cos(la))
          ..add(sin(fa));
      }
      out.add(Float32List.fromList(pts));
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    _space(canvas, size);
    final reserve = min(h * 0.46, 330.0);
    final avail = max(140.0, h - reserve - 56);
    final r0 = min(w * 0.40, avail / 2 * 0.95);
    final c = Offset(w / 2, 56 + avail / 2);
    final tint = Color.lerp(_kBlue, _kRed, max(m.crack, m.tint))!;
    final ap = Curves.easeOutCubic.transform(m.appear.clamp(0.0, 1.0).toDouble());
    final r = r0 * (0.84 + 0.16 * ap);
    canvas.save();
    // نفس آرام کره
    final br = 1.0 + 0.006 * sin(m.t * 1.3);
    canvas.translate(c.dx, c.dy);
    canvas.scale(br, br);
    canvas.translate(-c.dx, -c.dy);
    _globe(canvas, c, r, tint);
    canvas.restore();
    if (m.flash > 0) canvas.drawCircle(c, r, Paint()..color = Colors.white.withOpacity(m.flash * 0.35));
  }

  void _blob(Canvas canvas, Offset o, double rad, Color col) {
    canvas.drawCircle(
      o,
      rad,
      Paint()
        ..shader = RadialGradient(colors: [col, col.withOpacity(0)]).createShader(Rect.fromCircle(center: o, radius: rad)),
    );
  }

  void _space(Canvas canvas, Size size) {}

  void _cloudLayer(Canvas canvas, Offset c, double r, double cl0, double sl0, double cp0, double sp0) {
    final n = _clouds.length ~/ 4;
    final drift = m.t * 0.03;
    for (var i = 0; i < n; i++) {
      final la = _clouds[i * 4] + drift;
      final fa = _clouds[i * 4 + 1];
      final cf = cos(fa);
      final a = cf * sin(la), b = cf * cos(la), s = sin(fa);
      final t1 = b * cl0 + a * sl0;
      final z = sp0 * s + cp0 * t1;
      if (z <= 0.04) continue;
      final x = a * cl0 - b * sl0;
      final y = cp0 * s - sp0 * t1;
      final o = Offset(c.dx + r * x, c.dy - r * y);
      final rad = r * _clouds[i * 4 + 2] * (0.45 + 0.55 * z);
      final al = 0.17 * _clouds[i * 4 + 3] * z;
      for (var k = 0; k < 3; k++) {
        final oo = o + Offset((k - 1) * rad * 0.7, (k == 1 ? -0.15 : 0.12) * rad);
        _blob(canvas, oo, rad, Colors.white.withOpacity(al));
      }
    }
  }

  void _globe(Canvas canvas, Offset c, double r, Color tint) {
    final rect = Rect.fromCircle(center: c, radius: r);
    final cl0 = cos(m.lon), sl0 = sin(m.lon), cp0 = cos(m.lat), sp0 = sin(m.lat);

    // هاله‌ی اتمسفر بیرونی
    final gr = r * 1.38;
    canvas.drawCircle(
      c,
      gr,
      Paint()
        ..shader = RadialGradient(
          colors: [tint.withOpacity(lite ? 0.28 : 0.55), tint.withOpacity(0.16), tint.withOpacity(0.0)],
          stops: const [0.72, 0.80, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: gr)),
    );

    // مدار و ذرات پشت کره
    if (!lite) _orbit(canvas, c, r, tint, false);

    // بدنه‌ی کره
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.45),
          radius: 1.05,
          colors: [Color(0xFF2B86E8), Color(0xFF123F96), Color(0xFF071A4A), Color(0xFF030A24)],
          stops: [0.0, 0.42, 0.78, 1.0],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    _graticule(canvas, c, r, cl0, sl0, cp0, sp0, tint);
    final atlas = GeoAtlas.ready.value;
    if (atlas != null) {
      _dots(canvas, c, r, atlas, cl0, sl0, cp0, sp0, tint);
      if (!lite) _borders(canvas, c, r, atlas, cl0, sl0, cp0, sp0, tint);
      _highlight(canvas, c, r, cl0, sl0, cp0, sp0);
      _cloudLayer(canvas, c, r, cl0, sl0, cp0, sp0);
    }
    // سایه‌ی ترمیناتور برای حس حجم
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.5, -0.55),
          radius: 1.3,
          colors: [Color(0x00000000), Color(0x00000000), Color(0xB3020510)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(rect),
    );
    // لبه‌ی درخشان (Fresnel)
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [tint.withOpacity(0), tint.withOpacity(0), tint.withOpacity(lite ? 0.35 : 0.65)],
          stops: const [0.0, 0.78, 1.0],
        ).createShader(rect),
    );
    // درخشش نور (specular) بالا-چپ
    if (!lite) {
      final sp = Offset(c.dx - r * 0.42, c.dy - r * 0.46);
      _blob(canvas, sp, r * 0.55, Colors.white.withOpacity(0.10));
    }
    canvas.restore();

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = tint.withOpacity(0.85),
    );

    if (!lite) {
      canvas.drawCircle(
        c,
        r * 1.012,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.07
          ..color = Color.lerp(tint, Colors.white, 0.35)!.withOpacity(0.38)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.05),
      );
    }
    _origin(canvas, c, r, cl0, sl0, cp0, sp0, tint);
    _link(canvas, c, r, cl0, sl0, cp0, sp0);
    if (!lite) _orbit(canvas, c, r, tint, true);
  }

  // مدار مایل با ذراتی که جلوی کره از راست به چپ حرکت می‌کنند
  void _orbit(Canvas canvas, Offset c, double r, Color tint, bool front) {
    final fade = m.link > 0 ? 0.3 : 1.0;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.38);
    final rx = r * 1.3, ry = r * 0.4;
    final oval = Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
    canvas.drawArc(
      oval,
      front ? 0.0 : pi,
      pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = front ? 1.1 : 0.7
        ..color = tint.withOpacity((front ? 0.34 : 0.16) * fade),
    );
    const n = 12;
    for (var i = 0; i < n; i++) {
      final base = m.t * 1.0 + i * 2 * pi / n;
      for (var k = 0; k < 5; k++) {
        final a = base - k * 0.085;
        final sa = sin(a);
        if ((sa > 0) != front) continue;
        final o = Offset(cos(a) * rx, sa * ry);
        final al = (1 - k / 5) * (front ? 0.95 : 0.4) * fade;
        final col = Color.lerp(tint, Colors.white, 0.6)!.withOpacity(al);
        canvas.drawCircle(o, r * (0.022 - k * 0.0028), Paint()..color = col);
        if (k == 0 && front) canvas.drawCircle(o, r * 0.05, Paint()..color = tint.withOpacity(0.22 * fade));
      }
    }
    canvas.restore();
  }

  void _graticule(Canvas canvas, Offset c, double r, double cl0, double sl0, double cp0, double sp0, Color tint) {
    final path = Path();
    for (final g in _gr) {
      var pen = false;
      for (var i = 0; i < g.length; i += 3) {
        final a = g[i], b = g[i + 1], s = g[i + 2];
        final t1 = b * cl0 + a * sl0;
        final z = sp0 * s + cp0 * t1;
        if (z <= 0) {
          pen = false;
          continue;
        }
        final x = a * cl0 - b * sl0;
        final y = cp0 * s - sp0 * t1;
        final px = c.dx + r * x, py = c.dy - r * y;
        if (pen) {
          path.lineTo(px, py);
        } else {
          path.moveTo(px, py);
          pen = true;
        }
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = tint.withOpacity(0.17),
    );
  }

  // خشکی به‌شکل نقطه؛ نقطه‌ها بر اساس زاویه‌ی دید و نور در ۴ درجه‌ی روشنایی دسته‌بندی می‌شوند.
  void _dots(Canvas canvas, Offset c, double r, GeoAtlas at, double cl0, double sl0, double cp0, double sp0, Color tint) {
    final n = at.dotA.length;
    if (_binsFor != at) {
      for (var k = 0; k < 4; k++) {
        _bins[k] = Float32List(n * 2);
      }
      _binsFor = at;
    }
    final cnt = <int>[0, 0, 0, 0];
    final step = lite ? 2 : 1;
    for (var i = 0; i < n; i += step) {
      final a = at.dotA[i], b = at.dotB[i], s = at.dotS[i];
      final t1 = b * cl0 + a * sl0;
      final z = sp0 * s + cp0 * t1;
      if (z <= 0.03) continue;
      final x = a * cl0 - b * sl0;
      final y = cp0 * s - sp0 * t1;
      final lit = x * -0.45 + y * 0.5 + z * 0.74;
      final k = 0.5 * z + 0.5 * (0.5 + 0.5 * lit);
      final bi = k < 0.40 ? 0 : (k < 0.58 ? 1 : (k < 0.76 ? 2 : 3));
      final buf = _bins[bi]!;
      final j = cnt[bi] * 2;
      buf[j] = c.dx + r * x;
      buf[j + 1] = c.dy - r * y;
      cnt[bi]++;
    }
    final base = max(1.5, r * 0.0165);
    final cols = <Color>[
      tint.withOpacity(0.30),
      Color.lerp(tint, Colors.white, 0.15)!.withOpacity(0.62),
      Color.lerp(tint, Colors.white, 0.38)!.withOpacity(0.88),
      Color.lerp(tint, Colors.white, 0.70)!.withOpacity(1.0),
    ];
    final widths = <double>[base * 0.7, base * 0.9, base * 1.05, base * 1.2];
    for (var k = 0; k < 4; k++) {
      if (cnt[k] == 0) continue;
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.sublistView(_bins[k]!, 0, cnt[k] * 2),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = widths[k]
          ..color = cols[k],
      );
    }
  }

  void _borders(Canvas canvas, Offset c, double r, GeoAtlas at, double cl0, double sl0, double cp0, double sp0, Color tint) {
    final path = Path();
    for (final co in at.countries) {
      for (final ring in co.rings) {
        var pen = false;
        for (var i = 0; i < ring.n; i++) {
          final a = ring.a[i], b = ring.b[i], s = ring.s[i];
          final t1 = b * cl0 + a * sl0;
          final z = sp0 * s + cp0 * t1;
          if (z <= 0) {
            pen = false;
            continue;
          }
          final x = a * cl0 - b * sl0;
          final y = cp0 * s - sp0 * t1;
          final px = c.dx + r * x, py = c.dy - r * y;
          if (pen) {
            path.lineTo(px, py);
          } else {
            path.moveTo(px, py);
            pen = true;
          }
        }
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = tint.withOpacity(0.22),
    );
  }

  void _highlight(Canvas canvas, Offset c, double r, double cl0, double sl0, double cp0, double sp0) {
    final co = m.country;
    if (co == null || m.hl <= 0) return;
    final path = Path();
    for (final ring in co.rings) {
      var first = true;
      for (var i = 0; i < ring.n; i++) {
        final a = ring.a[i], b = ring.b[i], s = ring.s[i];
        final t1 = b * cl0 + a * sl0;
        final z = sp0 * s + cp0 * t1;
        var x = a * cl0 - b * sl0;
        var y = cp0 * s - sp0 * t1;
        if (z <= 0) {
          final l = sqrt(x * x + y * y);
          if (l > 1e-6) {
            x /= l;
            y /= l;
          }
        }
        final px = c.dx + r * x, py = c.dy - r * y;
        if (first) {
          path.moveTo(px, py);
          first = false;
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
    }
    final acc = _flagAccent(m.flagCode);
    if (m.flagCode.length == 2) {
      // خاک کشور مقصد با رنگ‌های پرچمش پر می‌شود
      final b = path.getBounds();
      if (b.width > 0.5 && b.height > 0.5) {
        canvas.saveLayer(b.inflate(4), Paint()..color = Colors.white.withOpacity(0.82 * m.hl));
        canvas.clipPath(path);
        canvas.translate(b.left, b.top);
        FlagPainter(flagSpecFor(m.flagCode)).paint(canvas, b.size);
        canvas.restore();
      }
    } else {
      canvas.drawPath(path, Paint()..color = _kGreen.withOpacity(0.30 * m.hl));
    }
    if (!lite) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = acc.withOpacity(0.55 * m.hl)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(acc, Colors.white, 0.65)!.withOpacity(m.hl),
    );
    // نقطه‌ی مقصد با موج
    final la = co.cLon * pi / 180, fa = co.cLat * pi / 180;
    final a = cos(fa) * sin(la), b = cos(fa) * cos(la), s = sin(fa);
    final t1 = b * cl0 + a * sl0;
    final z = sp0 * s + cp0 * t1;
    if (z > 0) {
      final o = Offset(c.dx + r * (a * cl0 - b * sl0), c.dy - r * (cp0 * s - sp0 * t1));
      for (var k = 0; k < 2; k++) {
        final f = (m.pulse + k * 0.5) % 1.0;
        canvas.drawCircle(
          o,
          r * (0.04 + 0.16 * f),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = _kGreen.withOpacity((1 - f) * 0.8 * m.hl),
        );
      }
      canvas.drawCircle(o, r * 0.025, Paint()..color = const Color(0xFFB6FFD6).withOpacity(m.hl));
    }
  }

  // نقطه‌ی لوکیشن قبلی (مبدأ) با موج
  void _origin(Canvas canvas, Offset c, double r, double cl0, double sl0, double cp0, double sp0, Color tint) {
    if (!m.hasOrigin) return;
    final a = cos(m.oLat) * sin(m.oLon), b = cos(m.oLat) * cos(m.oLon), s = sin(m.oLat);
    final t1 = b * cl0 + a * sl0;
    final z = sp0 * s + cp0 * t1;
    if (z <= 0.02) return;
    final o = Offset(c.dx + r * (a * cl0 - b * sl0), c.dy - r * (cp0 * s - sp0 * t1));
    final vis = min(1.0, z * 3).toDouble();
    if (!lite) {
      for (var k = 0; k < 2; k++) {
        final f = (m.pulse + k * 0.5) % 1.0;
        canvas.drawCircle(
          o,
          r * (0.03 + 0.12 * f),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = const Color(0xFF9CE3FF).withOpacity((1 - f) * 0.7 * vis),
        );
      }
    }
    canvas.drawCircle(o, r * 0.05, Paint()..color = const Color(0xFF9CE3FF).withOpacity(0.28 * vis));
    canvas.drawCircle(o, r * 0.022, Paint()..color = Colors.white.withOpacity(vis));
  }

  // نوار سبز قوسی از لوکیشن قبلی تا لوکیشن جدید (روی دایره‌ی عظیمه، با ارتفاع)
  void _link(Canvas canvas, Offset c, double r, double cl0, double sl0, double cp0, double sp0) {
    if (!m.hasOrigin || m.link <= 0) return;
    final oa = cos(m.oLat) * sin(m.oLon), ob = cos(m.oLat) * cos(m.oLon), os = sin(m.oLat);
    final ta = cos(m.tLat) * sin(m.tLon), tb = cos(m.tLat) * cos(m.tLon), ts = sin(m.tLat);
    final dot = (oa * ta + ob * tb + os * ts).clamp(-1.0, 1.0).toDouble();
    final om = acos(dot);
    if (om < 0.02) return;
    final so = sin(om);
    final lift = 0.10 + 0.24 * (om / pi);

    Offset? at(double u) {
      final f1 = sin((1 - u) * om) / so, f2 = sin(u * om) / so;
      final a = oa * f1 + ta * f2, b = ob * f1 + tb * f2, s = os * f1 + ts * f2;
      final rad = 1 + lift * sin(pi * u);
      final t1 = b * cl0 + a * sl0;
      final z = (sp0 * s + cp0 * t1) * rad;
      final x = (a * cl0 - b * sl0) * rad;
      final y = (cp0 * s - sp0 * t1) * rad;
      if (z > 0 || x * x + y * y > 1.0) return Offset(c.dx + r * x, c.dy - r * y);
      return null;
    }

    const segs = 80;
    final path = Path();
    var pen = false;
    for (var k = 0; k <= segs; k++) {
      final p = at(m.link * k / segs);
      if (p == null) {
        pen = false;
        continue;
      }
      if (pen) {
        path.lineTo(p.dx, p.dy);
      } else {
        path.moveTo(p.dx, p.dy);
        pen = true;
      }
    }
    final wMain = max(2.6, r * 0.02);
    if (!lite) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = wMain * 3.4
          ..color = _kGreen.withOpacity(0.30)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.03),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = wMain
        ..color = _kGreen.withOpacity(0.92),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = max(1.1, wMain * 0.38)
        ..color = const Color(0xFFD8FFE9).withOpacity(0.95),
    );
    // بسته‌های داده که روی نوار از مبدأ به مقصد می‌دوند
    for (var j = 0; j < 5; j++) {
      final u = ((m.stream + j / 5.0) % 1.0) * m.link;
      final p = at(u);
      if (p == null) continue;
      canvas.drawCircle(p, wMain * 1.9, Paint()..color = _kGreen.withOpacity(0.28));
      canvas.drawCircle(p, wMain * 0.85, Paint()..color = Colors.white.withOpacity(0.95));
    }
    // سر نوار
    final hp = at(m.link);
    if (hp != null) {
      canvas.drawCircle(hp, wMain * 3.2, Paint()..color = _kGreen.withOpacity(0.30));
      canvas.drawCircle(hp, wMain * 1.4, Paint()..color = const Color(0xFFD8FFE9));
    }
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) => old.lite != lite;
}

/// شکل تخت و برداری (مثل SVG) کشور: مرز اصلی کشور با درخشش.
/// رنگ شاخص پرچم (اولین نوار غیرسفید/غیرسیاه) برای درخشش و مرز.
Color _flagAccent(String code) {
  if (code.length != 2) return _kGreen;
  for (final b in flagSpecFor(code).bands) {
    if (b != 0xFFFFFFFF && b != 0xFF000000) return Color(b);
  }
  return _kGreen;
}

/// نماد ملی/دیدنی هر کشور (آیکن). اگر کشوری در جدول نباشد، خود نماد پرچم نشان داده می‌شود.
const Map<String, IconData> _kSymbols = {
  'DE': Icons.account_balance_rounded, // دروازه‌ی براندنبورگ
  'FR': Icons.cell_tower_rounded, // برج ایفل
  'GB': Icons.schedule_rounded, // بیگ‌بن
  'US': Icons.stars_rounded,
  'NL': Icons.wind_power_rounded, // آسیاب بادی
  'JP': Icons.terrain_rounded, // کوه فوجی
  'RU': Icons.church_rounded, // کلیسای سنت باسیل
  'TR': Icons.mosque_rounded,
  'IR': Icons.mosque_rounded,
  'SA': Icons.mosque_rounded,
  'AE': Icons.apartment_rounded, // برج خلیفه
  'CN': Icons.temple_buddhist_rounded,
  'KR': Icons.temple_buddhist_rounded,
  'IN': Icons.temple_hindu_rounded,
  'EG': Icons.change_history_rounded, // اهرام
  'CA': Icons.eco_rounded, // برگ افرا
  'IT': Icons.stadium_rounded, // کولوسئوم
  'CH': Icons.landscape_rounded, // آلپ
  'AU': Icons.surfing_rounded,
  'BR': Icons.sports_soccer_rounded,
  'SE': Icons.ac_unit_rounded,
  'NO': Icons.ac_unit_rounded,
  'FI': Icons.ac_unit_rounded,
  'DK': Icons.ac_unit_rounded,
  'IS': Icons.ac_unit_rounded,
  'UA': Icons.grass_rounded, // گندم
  'SG': Icons.location_city_rounded,
};

/// کارت کشور متصل: خاک کشور با رنگ‌های پرچم + نشان نماد ملی (یا خود پرچم).
class CountryFlagCard extends StatelessWidget {
  final GeoCountry country;
  final String code;
  final double size;
  const CountryFlagCard({super.key, required this.country, required this.code, this.size = 112});

  @override
  Widget build(BuildContext context) {
    final acc = _flagAccent(code);
    final icon = _kSymbols[code.toUpperCase()];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: CustomPaint(painter: CountryShapePainter(country, acc, flagCode: code))),
        Positioned(
          right: -6,
          bottom: -4,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0A1530),
              border: Border.all(color: acc, width: 2),
              boxShadow: [BoxShadow(color: acc.withOpacity(0.6), blurRadius: 10)],
            ),
            child: icon != null
                ? Icon(icon, color: Colors.white, size: 22)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(width: 26, height: 18, child: CustomPaint(painter: FlagPainter(flagSpecFor(code)))),
                  ),
          ),
        ),
      ]),
    );
  }
}

class CountryShapePainter extends CustomPainter {
  final GeoCountry country;
  final Color color;
  final String flagCode;
  CountryShapePainter(this.country, this.color, {this.flagCode = ''});

  @override
  void paint(Canvas canvas, Size size) {
    final main = country.main;
    final mcx = country.cLon, mcy = country.cLat;
    final rings = <GeoRing>[main];
    for (final r in country.rings) {
      if (identical(r, main)) continue;
      final cx = (r.minLon + r.maxLon) / 2, cy = (r.minLat + r.maxLat) / 2;
      if (r.area >= main.area * 0.08 && (cx - mcx).abs() < 40 && (cy - mcy).abs() < 30) rings.add(r);
    }
    final k = cos(mcy * pi / 180).abs().clamp(0.3, 1.0).toDouble();
    var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
    for (final r in rings) {
      x0 = min(x0, r.minLon * k);
      x1 = max(x1, r.maxLon * k);
      y0 = min(y0, r.minLat);
      y1 = max(y1, r.maxLat);
    }
    final bw = max(1e-6, x1 - x0), bh = max(1e-6, y1 - y0);
    final s = min(size.width / bw, size.height / bh) * 0.9;
    final ox = (size.width - bw * s) / 2, oy = (size.height - bh * s) / 2;
    final path = Path();
    for (final r in rings) {
      for (var i = 0; i < r.n; i++) {
        final px = ox + (r.ll[2 * i] * k - x0) * s;
        final py = oy + (y1 - r.ll[2 * i + 1]) * s;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
    }
    if (flagCode.length == 2) {
      // خاک کشور با رنگ‌های پرچم پر می‌شود + درخشش ملایم برای حس عمق
      final b = path.getBounds();
      canvas.save();
      canvas.clipPath(path);
      canvas.translate(b.left, b.top);
      FlagPainter(flagSpecFor(flagCode)).paint(canvas, b.size);
      canvas.translate(-b.left, -b.top);
      canvas.drawRect(
        b,
        Paint()
          ..shader = ui.Gradient.linear(b.topLeft, b.bottomRight, [Colors.white.withOpacity(0.28), Colors.transparent, Colors.black.withOpacity(0.25)], [0, 0.5, 1]),
      );
      canvas.restore();
    } else {
      canvas.drawPath(path, Paint()..color = color.withOpacity(0.22));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant CountryShapePainter old) => old.country != country || old.color != color || old.flagCode != flagCode;
}
