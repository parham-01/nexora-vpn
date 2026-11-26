import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class HomeBackdrop extends StatefulWidget {
  final Color a;
  final Color b;
  final bool dark;
  const HomeBackdrop({super.key, required this.a, required this.b, required this.dark});

  @override
  State<HomeBackdrop> createState() => _HomeBackdropState();
}

class _HomeBackdropState extends State<HomeBackdrop> with SingleTickerProviderStateMixin {
  late final Ticker _t;
  final ValueNotifier<double> _time = ValueNotifier(0);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _t = createTicker((d) {
      if ((d - _last).inMilliseconds < 33) return;
      _last = d;
      _time.value = d.inMilliseconds / 1000.0;
    })..start();
  }

  @override
  void dispose() {
    _t.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations && _t.isActive) _t.stop();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _BackdropPainter(_time, widget.a, widget.b, widget.dark),
        ),
      ),
    );
  }
}

class _Star {
  final double x, y, r, ph, sp;
  const _Star(this.x, this.y, this.r, this.ph, this.sp);
}

class _BackdropPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final Color a, b;
  final bool dark;
  _BackdropPainter(this.time, this.a, this.b, this.dark) : super(repaint: time);

  static final List<_Star> _stars = () {
    final r = Random(7);
    return List.generate(34, (_) => _Star(r.nextDouble(), r.nextDouble(), 0.6 + r.nextDouble() * 1.6, r.nextDouble() * 6.28, 0.3 + r.nextDouble() * 0.9));
  }();

  final Paint _p = Paint();

  @override
  void paint(Canvas c, Size s) {
    final t = time.value;
    final w = s.width, h = s.height;
    final k = dark ? 1.0 : 0.55;

    final blobs = [
      [0.2 + 0.18 * sin(t * 0.21), 0.18 + 0.10 * cos(t * 0.17), 0.75, a, 0.30],
      [0.85 + 0.12 * cos(t * 0.19), 0.42 + 0.12 * sin(t * 0.23), 0.65, b, 0.22],
      [0.4 + 0.20 * sin(t * 0.13 + 2), 0.85 + 0.08 * cos(t * 0.29), 0.8, const Color(0xFF7A4DFF), 0.20],
    ];
    for (final o in blobs) {
      final center = Offset(w * (o[0] as double), h * (o[1] as double));
      final rad = w * (o[2] as double);
      _p.shader = RadialGradient(colors: [(o[3] as Color).withOpacity((o[4] as double) * k), Colors.transparent]).createShader(Rect.fromCircle(center: center, radius: rad));
      c.drawCircle(center, rad, _p);
    }
    _p.shader = null;

    final cx = w * 0.5, cy = h * 0.34;
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final rr = w * (0.28 + i * 0.17);
      final pulse = 0.5 + 0.5 * sin(t * 0.8 - i * 0.9);
      _p.color = b.withOpacity((0.05 + 0.07 * pulse) * k);
      c.drawCircle(Offset(cx, cy), rr, _p);
    }
    c.save();
    c.translate(cx, cy);
    c.rotate(t * 0.05);
    for (var i = 0; i < 3; i++) {
      final rr = w * (0.36 + i * 0.17);
      _p.color = a.withOpacity(0.16 * k);
      final rect = Rect.fromCircle(center: Offset.zero, radius: rr);
      c.drawArc(rect, i * 1.7, 1.1, false, _p..strokeWidth = 1.6);
      final ang = i * 1.7 + 1.1;
      _p
        ..style = PaintingStyle.fill
        ..color = b.withOpacity(0.7 * k);
      c.drawCircle(Offset(rr * cos(ang), rr * sin(ang)), 2.4, _p);
      _p.style = PaintingStyle.stroke;
    }
    c.restore();

    for (var i = 0; i < 3; i++) {
      final path = Path();
      final base = h * (0.66 + i * 0.07);
      final amp = 16.0 + i * 7;
      final ph = t * (0.6 + i * 0.22) + i * 1.9;
      path.moveTo(0, base);
      for (double x = 0; x <= w; x += 14) {
        path.lineTo(x, base + amp * sin(x / w * 6.28 * (1.3 + i * 0.4) + ph) + amp * 0.4 * sin(x / w * 12.5 + ph * 1.4));
      }
      path.lineTo(w, h);
      path.lineTo(0, h);
      path.close();
      _p
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [(i.isEven ? a : b).withOpacity((0.16 - i * 0.04) * k), Colors.transparent]).createShader(Rect.fromLTWH(0, base - amp, w, h - base + amp));
      c.drawPath(path, _p);
      _p.shader = null;
    }

    _p.style = PaintingStyle.fill;
    for (final st in _stars) {
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * st.sp + st.ph));
      final dy = (st.y * h - t * (3 + st.r * 2)) % h;
      _p.color = Colors.white.withOpacity((dark ? 0.75 : 0.35) * tw);
      c.drawCircle(Offset(st.x * w, dy), st.r, _p);
    }

    final cyc = (t % 9.0) / 9.0;
    if (cyc < 0.16) {
      final u = cyc / 0.16;
      final sx = w * (0.15 + 0.7 * u), sy = h * (0.04 + 0.22 * u);
      final tail = Offset(sx - 70, sy - 26);
      _p
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.6
        ..shader = LinearGradient(colors: [Colors.transparent, Colors.white.withOpacity((1 - u) * (dark ? 0.9 : 0.5))]).createShader(Rect.fromPoints(tail, Offset(sx, sy)));
      c.drawLine(tail, Offset(sx, sy), _p);
      _p.shader = null;
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter o) => o.a != a || o.b != b || o.dark != dark;
}
