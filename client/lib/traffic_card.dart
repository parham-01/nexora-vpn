import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import 'store.dart' show fmtBytes, fmtDuration;

const int _kPoints = 60;
const int _kWindowMs = 3000;

const Color _cDown = Color(0xFF39E6FF);
const Color _cDown2 = Color(0xFF3B7BFF);
const Color _cUp = Color(0xFFFF4FD8);
const Color _cUp2 = Color(0xFFFFB347);
const Color _cTime = Color(0xFFFFD166);
const Color _cOk = Color(0xFF29E07F);

class TrafficSample {
  final bool on;
  final int down, up, downTotal, upTotal, seconds;
  final int directDown, directUp;
  final double? quotaFraction;
  final String quotaText;
  const TrafficSample({
    this.on = false,
    this.down = 0,
    this.up = 0,
    this.downTotal = 0,
    this.upTotal = 0,
    this.seconds = 0,
    this.directDown = 0,
    this.directUp = 0,
    this.quotaFraction,
    this.quotaText = '',
  });
}

class TrafficCard extends StatefulWidget {
  const TrafficCard({super.key, required this.reader, this.title = 'وضعیت اتصال', this.neon = true, this.fire = false});

  final TrafficSample Function() reader;
  final String title;
  final bool neon;
  final bool fire;

  @override
  State<TrafficCard> createState() => _TrafficCardState();
}

class _Snap {
  final int ms, down, up;
  const _Snap(this.ms, this.down, this.up);
}

double _frac(double v, double scale) {
  if (v <= 0 || scale <= 0) return 0;
  final a = math.log(1 + v / 2048);
  final b = math.log(1 + scale / 2048);
  if (b <= 0) return 0;
  return (a / b).clamp(0.0, 1.0);
}

class _TrafficCardState extends State<TrafficCard> with SingleTickerProviderStateMixin {
  final List<double> _dl = [];
  final List<double> _ul = [];
  final List<_Snap> _snaps = [];
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _timer;
  TrafficSample _s = const TrafficSample();
  double _down = 0, _up = 0, _peakDown = 0, _peakUp = 0;

  Color get _pd => widget.fire ? const Color(0xFFFF8A1F) : _cDown;
  Color get _pd2 => widget.fire ? const Color(0xFFFFC145) : _cDown2;
  Color get _pu => widget.fire ? const Color(0xFFB45CFF) : _cUp;
  Color get _pu2 => widget.fire ? const Color(0xFFFF4F9A) : _cUp2;

  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  double _phD = 0, _phU = 0, _iD = 0, _iU = 0, _spin = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame)..start();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  double get _scale {
    final pk = _peakDown > _peakUp ? _peakDown : _peakUp;
    final v = pk * 1.25;
    return v < 1048576 ? 1048576 : v;
  }

  void _onFrame(Duration el) {
    final dt = (el - _last).inMicroseconds / 1000000.0;
    _last = el;
    if (dt <= 0 || dt > 0.5) return;
    final sc = _scale;
    final td = _frac(_down, sc);
    final tu = _frac(_up, sc);
    final k = math.min(1.0, dt * 3.0);
    _iD += (td - _iD) * k;
    _iU += (tu - _iU) * k;
    _phD += dt * (0.18 + _iD * 1.7);
    _phU += dt * (0.18 + _iU * 1.7);
    _spin += dt * 0.35;
    _frame.value++;
  }

  void _reset() {
    _dl.clear();
    _ul.clear();
    _snaps.clear();
    _down = 0;
    _up = 0;
    _peakDown = 0;
    _peakUp = 0;
  }

  double _rate(int a, int b, double reported, bool totalsLive) {
    if (!totalsLive || _snaps.length < 2) return reported;
    final first = _snaps.first;
    final last = _snaps.last;
    final dt = (last.ms - first.ms) / 1000.0;
    if (dt < 0.4) return reported;
    final dd = (a - b).toDouble();
    return dd <= 0 ? 0 : dd / dt;
  }

  void _tick() {
    TrafficSample s;
    try {
      s = widget.reader();
    } catch (_) {
      s = const TrafficSample();
    }
    if (!s.on) {
      if (_dl.isNotEmpty || _down != 0 || _up != 0) _reset();
      if (mounted) setState(() => _s = s);
      return;
    }
    final now = _clock.elapsedMilliseconds;
    if (_snaps.isNotEmpty && (s.downTotal < _snaps.last.down || s.upTotal < _snaps.last.up)) {
      _reset();
    }
    _snaps.add(_Snap(now, s.downTotal, s.upTotal));
    while (_snaps.length > 2 && now - _snaps[1].ms >= _kWindowMs) {
      _snaps.removeAt(0);
    }
    final live = s.downTotal > 0 || s.upTotal > 0;
    final rd = _rate(s.downTotal, _snaps.first.down, s.down.toDouble(), live);
    final ru = _rate(s.upTotal, _snaps.first.up, s.up.toDouble(), live);
    _down = _down == 0 ? rd : _down * 0.35 + rd * 0.65;
    _up = _up == 0 ? ru : _up * 0.35 + ru * 0.65;
    if (rd == 0 && _down < 64) _down = 0;
    if (ru == 0 && _up < 64) _up = 0;
    if (_down > _peakDown) _peakDown = _down;
    if (_up > _peakUp) _peakUp = _up;
    _dl.add(_down);
    _ul.add(_up);
    if (_dl.length > _kPoints) _dl.removeAt(0);
    if (_ul.length > _kPoints) _ul.removeAt(0);
    if (mounted) setState(() => _s = s);
  }

  (String, String) _split(num v) {
    final t = fmtBytes(v).split(' ');
    return (t.first, t.length > 1 ? t[1] : 'B');
  }

  BoxDecoration _frost(double r, {double hi = 0.17, double lo = 0.05, double border = 0.22, Color? tint}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(r),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(Colors.white, tint ?? Colors.white, tint == null ? 0 : 0.35)!.withOpacity(hi),
          Colors.white.withOpacity(lo),
        ],
      ),
      border: Border.all(color: Colors.white.withOpacity(border), width: 1),
    );
  }

  Widget _gauge(String en, String fa, IconData icon, Color c1, Color c2, double v) {
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1.04,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: v),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, val, __) {
            final p = _split(val);
            final f = _frac(val, _scale);
            return Stack(children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _GaugePainter(f, c1, c2, _spin)),
                ),
              ),
              Align(
                alignment: const Alignment(0, 0.16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: c1, size: 13),
                    const SizedBox(width: 3),
                    Text(en, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 9.5, letterSpacing: 1.6, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 1),
                  SizedBox(
                    width: 74,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ShaderMask(
                        shaderCallback: (r) => LinearGradient(colors: [Colors.white, Color.lerp(Colors.white, c1, 0.6)!], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(r),
                        child: Text(p.$1, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
                      ),
                    ),
                  ),
                  Text('${p.$2}/s', style: TextStyle(color: c2.withOpacity(0.95), fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  const SizedBox(height: 1),
                  Text(fa, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 9.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _stat(IconData icon, Color c, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: _frost(14, hi: 0.1, lo: 0.03, border: 0.14, tint: c),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: c.withOpacity(0.95), size: 13),
            const SizedBox(width: 4),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.8))),
          ]),
          const SizedBox(height: 3),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800))),
        ]),
      ),
    );
  }

  Widget _ratioBar() {
    final d = _s.downTotal.toDouble();
    final u = _s.upTotal.toDouble();
    final sum = d + u;
    final fd = sum <= 0 ? 0.5 : d / sum;
    return Container(
      height: 7,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Row(children: [
          Expanded(flex: (fd * 1000).round().clamp(1, 999), child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [_pd2, _pd])))),
          const SizedBox(width: 2),
          Expanded(flex: ((1 - fd) * 1000).round().clamp(1, 999), child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [_pu, _pu2])))),
        ]),
      ),
    );
  }

  Widget _quota() {
    final f = _s.quotaFraction;
    if (f == null && _s.quotaText.isEmpty) return const SizedBox.shrink();
    final danger = f != null && f > 0.9;
    final c = danger ? Colors.redAccent : _cTime;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.data_usage_rounded, color: c, size: 14),
            const SizedBox(width: 5),
            Expanded(child: Text(_s.quotaText, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600))),
          ]),
          if (f != null) ...[
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: f.clamp(0.0, 1.0), minHeight: 6, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(c)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _orb(Color c, double size, double op) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c.withOpacity(op), c.withOpacity(0)])),
      );

  (String, Color, IconData) _level() {
    final m = _down > _up ? _down : _up;
    if (m >= 8 * 1048576) return ('HYPER SPEED', _pu, Icons.rocket_launch_rounded);
    if (m >= 2 * 1048576) return ('TURBO', _pu2, Icons.local_fire_department_rounded);
    if (m >= 300 * 1024) return ('FAST', _cOk, Icons.bolt_rounded);
    if (m >= 8 * 1024) return ('LIVE', _pd, Icons.graphic_eq_rounded);
    return ('IDLE', Colors.white54, Icons.hourglass_empty_rounded);
  }

  Widget _levelPill() {
    final l = _level();
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: [l.$2.withOpacity(0.32), l.$2.withOpacity(0.08)]),
          border: Border.all(color: l.$2.withOpacity(0.7)),
          boxShadow: [BoxShadow(color: l.$2.withOpacity(0.35), blurRadius: 14)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(l.$3, color: l.$2, size: 15),
          const SizedBox(width: 6),
          Text(l.$1, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 2)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final on = s.on;
    final accent = on ? _cOk : Colors.white54;
    final avg = s.seconds > 0 ? (s.downTotal + s.upTotal) / s.seconds : 0.0;
    final peak = _peakDown > _peakUp ? _peakDown : _peakUp;
    const r = 28.0;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(1.4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_pd, const Color(0x1AFFFFFF), const Color(0x0FFFFFFF), _pu],
          ),
          boxShadow: [
            BoxShadow(color: _pd.withOpacity(0.32), blurRadius: 26, spreadRadius: -4, offset: const Offset(-6, 8)),
            BoxShadow(color: _pu.withOpacity(0.28), blurRadius: 26, spreadRadius: -4, offset: const Offset(6, 10)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(r - 1.4),
          child: Stack(children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.fire
                        ? const [Color(0xFF3A1008), Color(0xFF160A24), Color(0xFF220A30)]
                        : const [Color(0xFF1B0B4A), Color(0xFF070A24), Color(0xFF05122E)],
                  ),
                ),
              ),
            ),
            Positioned(left: -60, top: -50, child: _orb(_pd, 240, 0.5)),
            Positioned(right: -70, bottom: -60, child: _orb(_pu, 260, 0.42)),
            Positioned(right: 20, top: -50, child: _orb(_cTime, 130, 0.2)),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(child: CustomPaint(painter: _GridPainter(_frame, this))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_cTime.withOpacity(0.55), _cTime.withOpacity(0.1)]),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                      boxShadow: [BoxShadow(color: _cTime.withOpacity(0.3), blurRadius: 12)],
                    ),
                    child: const Icon(Icons.timer_rounded, color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('SESSION', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10.5, letterSpacing: 2.5, fontWeight: FontWeight.w700)),
                      ShaderMask(
                        shaderCallback: (rc) => LinearGradient(colors: [Colors.white, _pd]).createShader(rc),
                        child: Text(
                          fmtDuration(on ? s.seconds : 0),
                          style: const TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w900, letterSpacing: 2.2, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: _frost(20, tint: accent, hi: 0.2, lo: 0.06, border: 0.26),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _PulseDot(color: accent, live: on),
                      const SizedBox(width: 7),
                      Text(on ? 'ONLINE' : 'OFFLINE', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 1.4)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _gauge('DOWNLOAD', 'دانلود', Icons.south_rounded, _pd, _pd2, _down),
                  const SizedBox(width: 8),
                  _gauge('UPLOAD', 'آپلود', Icons.north_rounded, _pu, _pu2, _up),
                ]),
                const SizedBox(height: 4),
                _levelPill(),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  width: double.infinity,
                  child: RepaintBoundary(child: CustomPaint(painter: _FlowPainter(_frame, this))),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 130,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: RepaintBoundary(child: CustomPaint(painter: _ChartPainter(List.of(_dl), List.of(_ul), down: _pd, up: _pu, neon: true))),
                  ),
                ),
                const SizedBox(height: 11),
                _ratioBar(),
                const SizedBox(height: 11),
                Row(children: [
                  _stat(Icons.download_done_rounded, _pd, 'DOWN', fmtBytes(s.downTotal)),
                  const SizedBox(width: 6),
                  _stat(Icons.upload_rounded, _pu, 'UP', fmtBytes(s.upTotal)),
                  const SizedBox(width: 6),
                  _stat(Icons.speed_rounded, _cTime, 'PEAK', '${fmtBytes(peak)}/s'),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  _stat(Icons.functions_rounded, _pd2, 'TOTAL', fmtBytes(s.downTotal + s.upTotal)),
                  const SizedBox(width: 6),
                  _stat(Icons.av_timer_rounded, _pu2, 'AVG', '${fmtBytes(avg)}/s'),
                  if (s.directDown + s.directUp > 0) ...[
                    const SizedBox(width: 6),
                    _stat(Icons.alt_route_rounded, _cTime, 'DIRECT', fmtBytes(s.directDown + s.directUp)),
                  ],
                ]),
                _quota(),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.live});
  final Color color;
  final bool live;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(painter: _DotPainter(widget.color, widget.live ? _c.value : 0, widget.live)),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.c, this.t, this.live);
  final Color c;
  final double t;
  final bool live;

  @override
  void paint(Canvas canvas, Size size) {
    final o = Offset(size.width / 2, size.height / 2);
    if (live) {
      canvas.drawCircle(o, 4 + t * 7, Paint()..color = c.withOpacity((1 - t) * 0.55));
    }
    canvas.drawCircle(o, 4, Paint()..color = c);
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) => old.t != t || old.c != c || old.live != live;
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.frac, this.c1, this.c2, this.spin);
  final double frac;
  final Color c1, c2;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.54);
    final radius = math.min(size.width / 2, size.height * 0.54) - 12;
    if (radius <= 10) return;
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius - 8,
      Paint()
        ..shader = RadialGradient(colors: [c1.withOpacity(0.14), c1.withOpacity(0)]).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round,
    );

    const n = 30;
    for (var i = 0; i <= n; i++) {
      final f = i / n;
      final a = start + sweep * f;
      final lit = f <= frac && frac > 0.002;
      final major = i % 5 == 0;
      final r1 = radius - (major ? 19 : 17);
      final r2 = radius - 12;
      final col = lit ? Color.lerp(c1, c2, f)! : Colors.white.withOpacity(major ? 0.22 : 0.12);
      canvas.drawLine(
        Offset(center.dx + math.cos(a) * r1, center.dy + math.sin(a) * r1),
        Offset(center.dx + math.cos(a) * r2, center.dy + math.sin(a) * r2),
        Paint()
          ..color = col
          ..strokeWidth = major ? 2.2 : 1.4
          ..strokeCap = StrokeCap.round,
      );
    }

    if (frac > 0.002) {
      final sw = sweep * frac;
      final grad = SweepGradient(
        startAngle: 0,
        endAngle: sweep,
        colors: [c1, c2],
        transform: const GradientRotation(start),
      ).createShader(rect);
      canvas.drawArc(
        rect,
        start,
        sw,
        false,
        Paint()
          ..color = c1.withOpacity(0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawArc(
        rect,
        start,
        sw,
        false,
        Paint()
          ..color = c2.withOpacity(0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 17
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawArc(
        rect,
        start,
        sw,
        false,
        Paint()
          ..shader = grad
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      );
      final ea = start + sw;
      final tip = Offset(center.dx + math.cos(ea) * radius, center.dy + math.sin(ea) * radius);
      canvas.drawCircle(tip, 9, Paint()..color = c2.withOpacity(0.35));
      canvas.drawCircle(tip, 5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.frac != frac || old.c1 != c1 || old.c2 != c2 || old.spin != spin;
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.frame, this.s) : super(repaint: frame);
  final ValueNotifier<int> frame;
  final _TrafficCardState s;

  void _lane(Canvas canvas, double y, double w, double phase, double inten, Color c, bool rightward) {
    canvas.drawLine(
      Offset(0, y),
      Offset(w, y),
      Paint()
        ..color = c.withOpacity(0.12)
        ..strokeWidth = 1.2,
    );
    final cnt = 6 + (inten * 16).round();
    for (var i = 0; i < cnt; i++) {
      var f = (i / cnt + phase) % 1.0;
      if (!rightward) f = 1 - f;
      final x = f * w;
      final len = 8 + inten * 26;
      final x0 = rightward ? x - len : x + len;
      final op = (0.25 + inten * 0.75) * (0.45 + 0.55 * math.sin(f * math.pi));
      final p = Paint()
        ..shader = LinearGradient(colors: [c.withOpacity(0), c.withOpacity(op.clamp(0.0, 1.0))]).createShader(Rect.fromPoints(Offset(x0, y), Offset(x, y)))
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x0, y), Offset(x, y), p);
      canvas.drawCircle(Offset(x, y), 1.9 + inten * 1.2, Paint()..color = Colors.white.withOpacity(op.clamp(0.0, 1.0)));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _lane(canvas, size.height * 0.28, size.width, s._phD, s._iD, s._pd, true);
    _lane(canvas, size.height * 0.74, size.width, s._phU, s._iU, s._pu, false);
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) => false;
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.frame, this.s) : super(repaint: frame);
  final ValueNotifier<int> frame;
  final _TrafficCardState s;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.035)
      ..strokeWidth = 1;
    const step = 26.0;
    final off = (s._spin * 40) % step;
    for (var y = -step + off; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    final y = (size.height * ((s._spin * 0.25) % 1.0));
    canvas.drawRect(
      Rect.fromLTWH(0, y - 24, size.width, 48),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [s._pd.withOpacity(0), s._pd.withOpacity(0.06), s._pd.withOpacity(0)],
        ).createShader(Rect.fromLTWH(0, y - 24, size.width, 48)),
    );
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => false;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.dl, this.ul, {required this.down, required this.up, this.neon = false});
  final List<double> dl, ul;
  final Color down, up;
  final bool neon;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    var raw = 1024.0;
    for (final v in dl) {
      if (v > raw) raw = v;
    }
    for (final v in ul) {
      if (v > raw) raw = v;
    }
    final peak = raw * 1.15;
    _series(canvas, size, ul, peak, up);
    _series(canvas, size, dl, peak, down);
    final tp = TextPainter(
      text: TextSpan(text: '${fmtBytes(raw)}/s', style: const TextStyle(color: Colors.white38, fontSize: 9.5, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(6, 4));
  }

  void _series(Canvas canvas, Size size, List<double> v, double peak, Color c) {
    if (v.length < 2) return;
    final pts = <Offset>[
      for (var i = 0; i < v.length; i++)
        Offset(
          size.width * (i + (_kPoints - v.length)) / (_kPoints - 1),
          size.height - 6 - (v[i] / peak) * (size.height - 20),
        ),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 < pts.length ? i + 2 : i + 1];
      final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      line.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    final fill = Path.from(line)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.withOpacity(0.42), c.withOpacity(0.02)],
        ).createShader(Offset.zero & size),
    );
    if (neon) {
      canvas.drawPath(
        line,
        Paint()
          ..color = c.withOpacity(0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = neon ? Color.lerp(c, Colors.white, 0.35)! : c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pts.last, 8, Paint()..color = c.withOpacity(0.22));
    canvas.drawCircle(pts.last, 5, Paint()..color = c.withOpacity(0.4));
    canvas.drawCircle(pts.last, 3.2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
