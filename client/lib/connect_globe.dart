import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'api.dart';
import 'dns_tunnel.dart';
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
  double _fromLon = 0, _fromLat = 0, _toLon = 0, _toLat = 0;
  bool _hasTarget = false;
  bool _showName = false, _showFail = false, _closed = false, _cancelling = false;
  String _name = '', _code = '', _err = '';
  GeoCountry? _country;

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
    _tk = createTicker(_onTick)..start();
    widget.ctl.outcome.addListener(_onOutcome);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onOutcome();
    });
  }

  @override
  void dispose() {
    widget.ctl.outcome.removeListener(_onOutcome);
    _tk.dispose();
    _rev.dispose();
    super.dispose();
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
    switch (_mode) {
      case _Mode.working:
      case _Mode.pendingOk:
        m.lon += dt * 0.42;
        m.lat += (0.38 - m.lat) * min(1.0, dt * 2);
        if (_mode == _Mode.pendingOk) _tryResolve();
        break;
      case _Mode.ok:
        final p = ((t - _modeAt) / 2.4).clamp(0.0, 1.0).toDouble();
        final e = _ease(p);
        if (_hasTarget) {
          m.lon = _fromLon + (_toLon - _fromLon) * e;
          m.lat = _fromLat + (_toLat - _fromLat) * e;
        } else {
          m.lon += dt * 0.3;
        }
        m.hl = ((t - _modeAt - 1.3) / 0.9).clamp(0.0, 1.0).toDouble();
        if (!_showName && t - _modeAt > 1.5) setState(() => _showName = true);
        if (t - _modeAt > 5.4) _close();
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
    _m.country = co;
    if (co != null) {
      _fromLon = _m.lon;
      _fromLat = _m.lat;
      var target = co.cLon * pi / 180;
      var delta = (target - _fromLon) % (2 * pi);
      if (delta > pi) delta -= 2 * pi;
      if (delta < -pi) delta += 2 * pi;
      if (delta.abs() < 1.2) delta += (delta >= 0 ? 1 : -1) * 2 * pi;
      _toLon = _fromLon + delta;
      _toLat = (co.cLat * pi / 180).clamp(-0.95, 0.95).toDouble();
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
                SizedBox(width: 74, height: 74, child: CustomPaint(painter: CountryShapePainter(co, _kGreen))),
                const SizedBox(width: 14),
              ],
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(_name.isEmpty ? (widget.ctl.pingMode ? 'Best server' : 'Connected') : _name,
                        style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  ),
                  const SizedBox(height: 2),
                  Text(widget.ctl.pingMode ? '$flag  ${widget.ctl.sub}' : '$flag  CONNECTED', style: const TextStyle(color: _kGreen, fontSize: 13, letterSpacing: 3, fontWeight: FontWeight.w700)),
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

// ----------------------------- نقاشی کره -----------------------------

class _GlobePainter extends CustomPainter {
  final _GlobeModel m;
  final bool lite;
  late final List<Float32List> _gr;
  Float32List? _buf;
  GeoAtlas? _bufFor;

  _GlobePainter(this.m, Listenable repaint, this.lite) : super(repaint: repaint) {
    _gr = _grat();
  }

  static const List<double> _j = [0.0, 0.35, -0.55, 0.3, -0.25, 0.6, -0.45, 0.15, -0.6, 0.5, -0.3, 0.55, -0.4, 0.25, 0.0];

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

  List<Offset> _zig(Offset c, double r) {
    final n = _j.length - 1;
    return [for (var i = 0; i <= n; i++) Offset(c.dx + _j[i] * r * 0.18, c.dy - r * 1.1 + r * 2.2 * i / n)];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    _stars(canvas, size);
    final reserve = min(h * 0.46, 330.0);
    final avail = max(140.0, h - reserve - 56);
    final r = min(w * 0.40, avail / 2 * 0.95);
    final c = Offset(w / 2, 56 + avail / 2);
    final tint = Color.lerp(_kBlue, _kRed, max(m.crack, m.tint))!;
    if (m.crack <= 0) {
      _globe(canvas, c, r, tint);
      if (m.flash > 0) canvas.drawCircle(c, r, Paint()..color = Colors.white.withOpacity(m.flash * 0.35));
      return;
    }
    final zig = _zig(c, r);
    canvas.save();
    if (m.crack < 1 && m.fall <= 0) {
      final s = sin(m.t * 70) * r * 0.012 * (1 - m.crack);
      canvas.translate(s, s * 0.6);
    }
    if (m.split <= 0) {
      _globe(canvas, c, r, tint);
      _crackLine(canvas, c, r, zig, m.crack, true);
    } else {
      final fd = (h - c.dy) + r * 1.6;
      final f2 = m.fall * m.fall;
      final gap = r * 0.035 * m.split;
      final left = Path()..moveTo(c.dx - 3 * r, c.dy - 1.4 * r);
      final right = Path()..moveTo(c.dx + 3 * r, c.dy - 1.4 * r);
      for (final z in zig) {
        left.lineTo(z.dx, z.dy);
        right.lineTo(z.dx, z.dy);
      }
      left
        ..lineTo(c.dx - 3 * r, c.dy + 1.4 * r)
        ..close();
      right
        ..lineTo(c.dx + 3 * r, c.dy + 1.4 * r)
        ..close();
      _half(canvas, left, c, r, tint, zig, Offset(c.dx - r * 0.45, c.dy), -gap - r * 0.3 * f2, fd * f2, -0.9 * f2);
      _half(canvas, right, c, r, tint, zig, Offset(c.dx + r * 0.45, c.dy), gap + r * 0.4 * f2, fd * f2 * 1.08, 1.1 * f2);
      if (m.fall > 0) _shards(canvas, c, r, fd);
    }
    canvas.restore();
    if (m.flash > 0) canvas.drawCircle(c, r, Paint()..color = Colors.white.withOpacity(m.flash * 0.35));
  }

  void _half(Canvas canvas, Path clip, Offset c, double r, Color tint, List<Offset> zig, Offset pivot, double dx, double dy, double ang) {
    canvas.save();
    canvas.translate(pivot.dx + dx, pivot.dy + dy);
    canvas.rotate(ang);
    canvas.translate(-pivot.dx, -pivot.dy);
    canvas.clipPath(clip);
    _globe(canvas, c, r, tint);
    _crackLine(canvas, c, r, zig, 1.0, false);
    canvas.restore();
  }

  void _crackLine(Canvas canvas, Offset c, double r, List<Offset> zig, double crack, bool clip) {
    final n = zig.length - 1;
    final mid = n ~/ 2;
    final k = crack * mid;
    final whole = k.floor();
    final frac = k - whole;
    final lo = max(0, mid - whole);
    final hi = min(n, mid + whole);
    Offset start = zig[lo];
    Offset end = zig[hi];
    if (lo > 0 && frac > 0) {
      final a = zig[lo], b = zig[lo - 1];
      start = Offset(a.dx + (b.dx - a.dx) * frac, a.dy + (b.dy - a.dy) * frac);
    }
    if (hi < n && frac > 0) {
      final a = zig[hi], b = zig[hi + 1];
      end = Offset(a.dx + (b.dx - a.dx) * frac, a.dy + (b.dy - a.dy) * frac);
    }
    final path = Path()..moveTo(start.dx, start.dy);
    if (lo > 0 && frac > 0) path.lineTo(zig[lo].dx, zig[lo].dy);
    for (var i = lo + 1; i <= hi; i++) {
      path.lineTo(zig[i].dx, zig[i].dy);
    }
    if (hi < n && frac > 0) path.lineTo(end.dx, end.dy);
    canvas.save();
    if (clip) canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..strokeJoin = StrokeJoin.round
        ..color = _kRed.withOpacity(0.35)
        ..maskFilter = lite ? null : MaskFilter.blur(BlurStyle.normal, r * 0.04),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withOpacity(0.95),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = _kRed,
    );
    canvas.restore();
  }

  void _shards(Canvas canvas, Offset c, double r, double fd) {
    final rnd = Random(11);
    final f = m.fall;
    for (var i = 0; i < 18; i++) {
      final bx = c.dx + (rnd.nextDouble() * 2 - 1) * r * 0.3;
      final by = c.dy + (rnd.nextDouble() * 2 - 1) * r * 0.95;
      final vx = (rnd.nextDouble() * 2 - 1) * r * 0.9;
      final sz = r * (0.04 + rnd.nextDouble() * 0.06);
      final spin = (rnd.nextDouble() * 2 - 1) * 6;
      final sp = 0.6 + rnd.nextDouble() * 0.5;
      canvas.save();
      canvas.translate(bx + vx * f, by + fd * sp * f * f);
      canvas.rotate(spin * f);
      final tri = Path()
        ..moveTo(0, -sz)
        ..lineTo(sz * 0.9, sz * 0.7)
        ..lineTo(-sz * 0.8, sz * 0.6)
        ..close();
      canvas.drawPath(tri, Paint()..color = Color.lerp(_kBlue, _kRed, 0.5)!.withOpacity(max(0.0, 1 - f * 0.6)));
      canvas.restore();
    }
  }

  void _stars(Canvas canvas, Size size) {
    if (lite) return;
    final rnd = Random(5);
    final p = Paint();
    for (var i = 0; i < 46; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final ph = rnd.nextDouble() * 6.28;
      final rad = 0.6 + rnd.nextDouble() * 1.1;
      p.color = Colors.white.withOpacity(0.18 + 0.22 * (0.5 + 0.5 * sin(m.t * 1.6 + ph)));
      canvas.drawCircle(Offset(x, y), rad, p);
    }
  }

  void _globe(Canvas canvas, Offset c, double r, Color tint) {
    final rect = Rect.fromCircle(center: c, radius: r);
    if (!lite) {
      canvas.drawCircle(
        c,
        r * 1.22,
        Paint()
          ..shader = RadialGradient(
            colors: [tint.withOpacity(0.30), tint.withOpacity(0.0)],
            stops: const [0.74, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r * 1.22)),
      );
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: [Color(0xFF14408A), Color(0xFF081D47), Color(0xFF030A1E)],
          stops: [0.0, 0.62, 1.0],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    final cl0 = cos(m.lon), sl0 = sin(m.lon), cp0 = cos(m.lat), sp0 = sin(m.lat);
    _graticule(canvas, c, r, cl0, sl0, cp0, sp0, tint);
    final atlas = GeoAtlas.ready.value;
    if (atlas != null) {
      _dots(canvas, c, r, atlas, cl0, sl0, cp0, sp0, tint);
      if (!lite) _borders(canvas, c, r, atlas, cl0, sl0, cp0, sp0, tint);
      _highlight(canvas, c, r, cl0, sl0, cp0, sp0);
    }
    canvas.restore();
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = tint.withOpacity(0.8),
    );
    if (!lite) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-0.38);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 2.55, height: r * 0.78),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = tint.withOpacity(0.22),
      );
      final ang = m.t * 0.9;
      final o = Offset(cos(ang) * r * 1.275, sin(ang) * r * 0.39);
      canvas.drawCircle(o, r * 0.05, Paint()..color = tint.withOpacity(0.35));
      canvas.drawCircle(o, r * 0.022, Paint()..color = tint);
      canvas.restore();
    }
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
        ..strokeWidth = 0.7
        ..color = tint.withOpacity(0.20),
    );
  }

  void _dots(Canvas canvas, Offset c, double r, GeoAtlas at, double cl0, double sl0, double cp0, double sp0, Color tint) {
    final n = at.dotA.length;
    if (_bufFor != at || _buf == null) {
      _buf = Float32List(n * 4);
      _bufFor = at;
    }
    final buf = _buf!;
    var nf = 0, nb = 0;
    final step = lite ? 2 : 1;
    for (var i = 0; i < n; i += step) {
      final a = at.dotA[i], b = at.dotB[i], s = at.dotS[i];
      final t1 = b * cl0 + a * sl0;
      final z = sp0 * s + cp0 * t1;
      if (z <= 0.02) continue;
      final x = a * cl0 - b * sl0;
      final y = cp0 * s - sp0 * t1;
      final px = c.dx + r * x, py = c.dy - r * y;
      if (z > 0.38) {
        buf[nf * 2] = px;
        buf[nf * 2 + 1] = py;
        nf++;
      } else {
        buf[n * 2 + nb * 2] = px;
        buf[n * 2 + nb * 2 + 1] = py;
        nb++;
      }
    }
    final width = max(1.6, r * 0.017);
    if (nb > 0) {
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.sublistView(buf, n * 2, n * 2 + nb * 2),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = tint.withOpacity(0.28),
      );
    }
    if (nf > 0) {
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.sublistView(buf, 0, nf * 2),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = tint.withOpacity(0.85),
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
        ..strokeWidth = 0.7
        ..color = tint.withOpacity(0.30),
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
    canvas.drawPath(path, Paint()..color = _kGreen.withOpacity(0.38 * m.hl));
    if (!lite) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = _kGreen.withOpacity(0.45 * m.hl)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFB6FFD6).withOpacity(m.hl),
    );
    // نقطه‌ی مرکز کشور با موج
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

  @override
  bool shouldRepaint(covariant _GlobePainter old) => old.lite != lite;
}

/// شکل تخت و برداری (مثل SVG) کشور: مرز اصلی کشور با درخشش.
class CountryShapePainter extends CustomPainter {
  final GeoCountry country;
  final Color color;
  CountryShapePainter(this.country, this.color);

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
    canvas.drawPath(path, Paint()..color = color.withOpacity(0.22));
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
  bool shouldRepaint(covariant CountryShapePainter old) => old.country != country || old.color != color;
}
