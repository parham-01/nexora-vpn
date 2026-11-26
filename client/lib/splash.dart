import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'nexora_logo.dart';
import 'pages.dart';

/// صفحه‌ی ورودی: اول لودینگ (حداکثر ۷ ثانیه) و بعد صفحه‌ی اصلی.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        child: _done
            ? const Shell(key: ValueKey('shell'))
            : SplashPage(key: const ValueKey('splash'), onDone: () {
                if (mounted && !_done) setState(() => _done = true);
              }),
      );
}

enum _S { wait, run, ok, warn }

class _Step {
  _Step(this.title);
  final String title;
  _S state = _S.wait;
  String result = '';
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  static const Duration _maxTotal = Duration(seconds: 7);
  static const Duration _minShow = Duration(milliseconds: 3200);

  late final AnimationController _fx = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  final List<_Step> _steps = [_Step('Network Check'), _Step('Ping Test'), _Step('Starting Engine')];
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _hardStop;
  bool _finished = false;
  bool _offline = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    // سقف سخت ۷ ثانیه: هرچه انجام نشده باشد رها می‌شود و برنامه باز می‌شود.
    _hardStop = Timer(_maxTotal, _finish);
    unawaited(_run());
  }

  @override
  void dispose() {
    _hardStop?.cancel();
    _fx.dispose();
    super.dispose();
  }

  void _set(int i, _S s, [String result = '', double? progress]) {
    if (!mounted || _finished) return;
    setState(() {
      _steps[i].state = s;
      _steps[i].result = result;
      if (progress != null) _progress = progress;
    });
  }

  Future<void> _run() async {
    // 1) Network Check
    _set(0, _S.run, '', 0.06);
    final net = await _networkCheck();
    _offline = !net;
    _set(0, net ? _S.ok : _S.warn, net ? 'Online' : 'Offline', 0.38);

    // 2) Ping Test
    _set(1, _S.run, '', 0.42);
    if (net) {
      final ms = await _pingTest();
      _set(1, ms == null ? _S.warn : _S.ok, ms == null ? 'Timeout' : '$ms ms', 0.76);
    } else {
      _set(1, _S.warn, 'Skipped', 0.76);
    }

    // 3) Starting Engine
    _set(2, _S.run, '', 0.8);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    _set(2, _S.ok, 'Ready', 1);

    final left = _minShow - _clock.elapsed;
    if (left > Duration.zero) await Future<void>.delayed(left);
    _finish();
  }

  Future<bool> _networkCheck() async {
    try {
      final r = await InternetAddress.lookup('cloudflare.com').timeout(const Duration(milliseconds: 2500));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      try {
        final s = await Socket.connect('1.1.1.1', 443, timeout: const Duration(milliseconds: 1500));
        s.destroy();
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// میانگین زمان اتصال TCP به چند هاست پایدار؛ null یعنی هیچ‌کدام جواب ندادند.
  Future<int?> _pingTest() async {
    Future<int?> probe(String host) async {
      final sw = Stopwatch()..start();
      try {
        final s = await Socket.connect(host, 443, timeout: const Duration(milliseconds: 1800));
        sw.stop();
        s.destroy();
        return sw.elapsedMilliseconds;
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([probe('1.1.1.1'), probe('8.8.8.8'), probe('9.9.9.9')]);
    final ok = results.whereType<int>().toList();
    if (ok.isEmpty) return null;
    return (ok.reduce((a, b) => a + b) / ok.length).round();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _hardStop?.cancel();
    if (mounted) widget.onDone();
  }

  Widget _stepRow(_Step s) {
    Widget icon;
    switch (s.state) {
      case _S.wait:
        icon = const Icon(Icons.circle_outlined, size: 18, color: Color(0x66FFFFFF));
      case _S.run:
        icon = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6BE6FF)));
      case _S.ok:
        icon = const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF69F0AE));
      case _S.warn:
        icon = const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFFFB74D));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 22, child: Center(child: icon)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            s.title,
            style: TextStyle(color: s.state == _S.wait ? Colors.white38 : Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          s.result,
          style: TextStyle(
            color: s.state == _S.warn ? const Color(0xFFFFB74D) : const Color(0xFF9FD4FF),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B1D),
      body: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0A1B45), Color(0xFF050B1D)],
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _fx,
              builder: (_, __) => CustomPaint(painter: _ParticlePainter(_fx.value)),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 190,
                          height: 190,
                          child: AnimatedBuilder(
                            animation: _fx,
                            builder: (_, child) {
                              final pulse = 1 + 0.035 * math.sin(_fx.value * 2 * math.pi * 3);
                              return Stack(alignment: Alignment.center, children: [
                                CustomPaint(size: const Size.square(190), painter: _OrbitPainter(_fx.value)),
                                Transform.scale(scale: pulse, child: child),
                              ]);
                            },
                            child: const NexoraLogo(size: 108),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const NexoraWordmark(fontSize: 31, textColor: Colors.white),
                        const SizedBox(height: 34),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: _progress),
                            duration: const Duration(milliseconds: 450),
                            curve: Curves.easeOutCubic,
                            builder: (_, v, __) => LinearProgressIndicator(
                              value: v,
                              minHeight: 6,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation(Color(0xFF3D8BFF)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        for (final s in _steps) _stepRow(s),
                        if (_offline)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: Text('اینترنت قطع است؛ برنامه بدون اتصال باز می‌شود', style: TextStyle(color: Color(0xFFFFB74D), fontSize: 12)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: size.width / 2 - 8);
    canvas.drawCircle(c, rect.width / 2, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = const Color(0x223D8BFF));
    final angle = t * 2 * math.pi;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: const [Color(0x006BE6FF), Color(0xFF6BE6FF), Color(0x006BE6FF)],
        stops: const [0, 0.25, 0.5],
        transform: GradientRotation(angle),
      ).createShader(rect);
    canvas.drawArc(rect, angle - 0.2, math.pi * 0.55, false, arc);
    final dot = Offset(c.dx + rect.width / 2 * math.cos(-angle * 1.3), c.dy + rect.width / 2 * math.sin(-angle * 1.3));
    canvas.drawCircle(dot, 3.4, Paint()..color = const Color(0xFF9FD4FF));
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) => old.t != t;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (var i = 0; i < 26; i++) {
      final seed = (i * 7919) % 1000 / 1000.0;
      final x = ((i * 137) % 100) / 100 * size.width;
      final speed = 0.35 + seed * 0.65;
      final y = size.height - ((t * speed + seed) % 1.0) * size.height;
      final a = math.sin(((t * speed + seed) % 1.0) * math.pi).clamp(0.0, 1.0).toDouble() * 0.5;
      p.color = const Color(0xFF6BE6FF).withOpacity(a);
      canvas.drawCircle(Offset(x, y), 1.2 + seed * 2, p);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => old.t != t;
}
