import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'store.dart';

/// دو پالت آماده برای پس‌زمینه‌ی متحرک.
enum FxStyle { firefox, home }

/// پس‌زمینه‌ی متحرک سبک After-Effects: شفق‌های نرم، ریبون‌های موج‌دار، ذره‌های
/// درخشان، حلقه‌های مداری، پرتو اسکن و جرقه. همه با یک Ticker و یک CustomPainter
/// (بدون Blur و بدون ساخت ویجت در هر فریم) تا روی گوشی‌های ضعیف هم روان بماند.
///
///  - وقتی صفحه دیده نمی‌شود (TickerMode خاموش) یا کاربر «کاهش انیمیشن» را
///    روشن کرده، تیکر متوقف می‌شود و فقط یک فریم ثابت کشیده می‌شود.
///  - در حالت lite تعداد ذره‌ها و لایه‌ها کمتر و نرخ فریم ۲۴ است.
class NexoraFxBackdrop extends StatefulWidget {
  const NexoraFxBackdrop({super.key, this.style = FxStyle.firefox, this.accent, this.accent2});
  final FxStyle style;
  final Color? accent;
  final Color? accent2;

  @override
  State<NexoraFxBackdrop> createState() => _NexoraFxBackdropState();
}

class _NexoraFxBackdropState extends State<NexoraFxBackdrop> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  Duration _last = Duration.zero;
  bool _lite = Store.lite.value;

  @override
  void initState() {
    super.initState();
    Store.lite.addListener(_onLite);
    _ticker = createTicker((d) {
      final gap = _lite ? 41 : 25; // ≈۲۴ یا ≈۴۰ فریم در ثانیه
      if ((d - _last).inMilliseconds < gap) return;
      _last = d;
      _time.value = d.inMilliseconds / 1000.0;
    })..start();
  }

  void _onLite() {
    if (mounted) setState(() => _lite = Store.lite.value);
  }

  @override
  void dispose() {
    Store.lite.removeListener(_onLite);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce && _ticker.isActive) {
      _ticker.stop();
    } else if (!reduce && !_ticker.isActive) {
      _ticker.start();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _FxPainter(
            time: _time,
            style: widget.style,
            dark: dark,
            lite: _lite,
            accent: widget.accent,
            accent2: widget.accent2,
          ),
        ),
      ),
    );
  }
}

class _Ember {
  const _Ember(this.x, this.y, this.r, this.speed, this.phase, this.sway, this.hue);
  final double x, y, r, speed, phase, sway;
  final int hue; // اندیس رنگ داخل پالت
}

class _FxPainter extends CustomPainter {
  _FxPainter({
    required this.time,
    required this.style,
    required this.dark,
    required this.lite,
    this.accent,
    this.accent2,
  }) : super(repaint: time) {
    _palette = _buildPalette();
    _embers = _makeEmbers(lite ? 20 : 46);
  }

  final ValueNotifier<double> time;
  final FxStyle style;
  final bool dark;
  final bool lite;
  final Color? accent;
  final Color? accent2;

  late final List<Color> _palette;
  late final List<_Ember> _embers;
  final Paint _p = Paint();

  List<Color> _buildPalette() {
    if (style == FxStyle.firefox) {
      // رنگ‌های برند Firefox: نارنجی، سرخابی، بنفش، فیروزه‌ای
      return const [Color(0xFFFF7139), Color(0xFFE31587), Color(0xFF7A4DFF), Color(0xFF00DDFF)];
    }
    final a = accent ?? const Color(0xFF3B82F6);
    final b = accent2 ?? const Color(0xFF22D3EE);
    return [a, b, const Color(0xFF7A4DFF), const Color(0xFF29E07F)];
  }

  List<_Ember> _makeEmbers(int n) {
    final r = Random(style == FxStyle.firefox ? 21 : 33);
    return List<_Ember>.generate(
      n,
      (_) => _Ember(
        r.nextDouble(),
        r.nextDouble(),
        0.8 + r.nextDouble() * 2.4,
        0.018 + r.nextDouble() * 0.05,
        r.nextDouble() * 6.2832,
        6 + r.nextDouble() * 20,
        r.nextInt(4),
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final t = time.value;
    final k = dark ? 1.0 : 0.55; // در تم روشن ملایم‌تر

    _base(canvas, w, h, k);
    _blobs(canvas, w, h, t, k);
    _ribbons(canvas, w, h, t, k);
    if (!lite) _grid(canvas, w, h, t, k);
    _orbits(canvas, w, h, t, k);
    _scan(canvas, w, h, t, k);
  }

  // پایه: گرادیان تیره/روشن
  void _base(Canvas c, double w, double h, double k) {
    if (!dark) return;
    final top = style == FxStyle.firefox ? const Color(0xFF0B0720) : const Color(0xFF050D24);
    final bot = style == FxStyle.firefox ? const Color(0xFF14061C) : const Color(0xFF03071A);
    _p
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bot])
          .createShader(Rect.fromLTWH(0, 0, w, h));
    c.drawRect(Rect.fromLTWH(0, 0, w, h), _p);
    _p.shader = null;
  }

  // لکه‌های نورانی شناور (شفق)
  void _blobs(Canvas c, double w, double h, double t, double k) {
    final defs = <List<Object>>[
      [0.18 + 0.16 * sin(t * 0.21), 0.14 + 0.09 * cos(t * 0.17), 0.80, 0, 0.34],
      [0.88 + 0.10 * cos(t * 0.19), 0.38 + 0.12 * sin(t * 0.23), 0.70, 1, 0.26],
      [0.35 + 0.20 * sin(t * 0.13 + 2), 0.82 + 0.07 * cos(t * 0.29), 0.85, 2, 0.24],
      if (!lite) [0.75 + 0.14 * sin(t * 0.11 + 1), 0.70 + 0.10 * cos(t * 0.15), 0.60, 3, 0.16],
    ];
    _p.style = PaintingStyle.fill;
    for (final d in defs) {
      final center = Offset(w * (d[0] as double), h * (d[1] as double));
      final rad = w * (d[2] as double);
      final col = _palette[d[3] as int];
      _p.shader = RadialGradient(colors: [col.withOpacity(((d[4] as double) * k).clamp(0.0, 1.0).toDouble()), Colors.transparent])
          .createShader(Rect.fromCircle(center: center, radius: rad));
      c.drawCircle(center, rad, _p);
    }
    _p.shader = null;
  }

  // ریبون‌های موج‌دار با ترکیب نوری (additive)
  void _ribbons(Canvas c, double w, double h, double t, double k) {
    final count = lite ? 2 : 3;
    for (var i = 0; i < count; i++) {
      final base = h * (0.30 + i * 0.17);
      final amp = 26.0 + i * 12;
      final ph = t * (0.45 + i * 0.17) + i * 2.1;
      final top = Path();
      final bottom = <Offset>[];
      const step = 16.0;
      var first = true;
      for (double x = 0; x <= w + step; x += step) {
        final y = base +
            amp * sin(x / w * 6.2832 * (1.1 + i * 0.35) + ph) +
            amp * 0.45 * sin(x / w * 11.0 - ph * 1.3);
        if (first) {
          top.moveTo(x, y);
          first = false;
        } else {
          top.lineTo(x, y);
        }
        bottom.add(Offset(x, y + 70 + 26 * sin(x / w * 5 + ph)));
      }
      for (var j = bottom.length - 1; j >= 0; j--) {
        top.lineTo(bottom[j].dx, bottom[j].dy);
      }
      top.close();
      final col = _palette[(i + 1) % 4];
      _p
        ..style = PaintingStyle.fill
        ..blendMode = dark ? BlendMode.plus : BlendMode.srcOver
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [col.withOpacity(0.22 * k), col.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(0, base - amp * 1.5, w, 160 + amp * 3));
      c.drawPath(top, _p);
      _p
        ..shader = null
        ..blendMode = BlendMode.srcOver;
    }
  }

  // شبکه‌ی نئونی پرسپکتیو پایین صفحه
  void _grid(Canvas c, double w, double h, double t, double k) {
    final horizon = h * 0.78;
    final vx = w * 0.5;
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _palette[1].withOpacity(0.10 * k);
    for (var i = -8; i <= 8; i++) {
      c.drawLine(Offset(vx, horizon), Offset(vx + i * w * 0.16, h), _p);
    }
    final flow = (t * 0.18) % 1.0;
    for (var i = 0; i < 7; i++) {
      final u = ((i + flow) / 7);
      final y = horizon + (h - horizon) * (u * u);
      _p.color = _palette[0].withOpacity((0.04 + 0.12 * u) * k);
      c.drawLine(Offset(0, y), Offset(w, y), _p);
    }
  }

  // حلقه‌های مداری با نقطه‌ی چرخان
  void _orbits(Canvas c, double w, double h, double t, double k) {
    final cx = w * 0.5, cy = h * 0.22;
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final rr = w * (0.22 + i * 0.15);
      final pulse = 0.5 + 0.5 * sin(t * 0.9 - i * 0.9);
      _p.color = _palette[(i + 3) % 4].withOpacity((0.05 + 0.07 * pulse) * k);
      c.drawCircle(Offset(cx, cy), rr, _p);
    }
    c.save();
    c.translate(cx, cy);
    c.rotate(t * 0.06);
    for (var i = 0; i < 3; i++) {
      final rr = w * (0.30 + i * 0.15);
      final col = _palette[i % 4];
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = col.withOpacity(0.22 * k);
      c.drawArc(Rect.fromCircle(center: Offset.zero, radius: rr), i * 1.9, 1.15, false, _p);
      final ang = i * 1.9 + 1.15;
      _p
        ..style = PaintingStyle.fill
        ..color = col.withOpacity(0.85 * k);
      c.drawCircle(Offset(rr * cos(ang), rr * sin(ang)), 2.6, _p);
    }
    c.restore();
  }

  // ذره‌های درخشان که بالا می‌روند و کمی تاب می‌خورند
  void _embersLayer(Canvas c, double w, double h, double t, double k) {
    _p
      ..style = PaintingStyle.fill
      ..shader = null;
    for (final e in _embers) {
      final prog = ((e.y - t * e.speed) % 1.0 + 1.0) % 1.0; // ۱ پایین، ۰ بالا
      final y = prog * h;
      final x = e.x * w + sin(t * 0.8 + e.phase) * e.sway;
      final fade = sin(prog * 3.1416).clamp(0.0, 1.0).toDouble(); // نرم محو شدن در لبه‌ها
      final flicker = 0.65 + 0.35 * sin(t * 3.0 + e.phase * 2);
      final col = _palette[e.hue];
      final a = (0.85 * fade * flicker * k).clamp(0.0, 1.0).toDouble();
      if (!lite) {
        _p.color = col.withOpacity(a * 0.22);
        c.drawCircle(Offset(x, y), e.r * 4.2, _p); // هاله
      }
      _p.color = col.withOpacity(a);
      c.drawCircle(Offset(x, y), e.r, _p);
    }
  }

  // پرتو اسکن افقی که هر چند ثانیه عبور می‌کند
  void _scan(Canvas c, double w, double h, double t, double k) {
    final cyc = (t % 7.5) / 7.5;
    if (cyc > 0.45) return;
    final u = cyc / 0.45;
    final y = h * (-0.05 + 1.1 * u);
    final fade = sin(u * 3.1416);
    _p
      ..style = PaintingStyle.fill
      ..blendMode = dark ? BlendMode.plus : BlendMode.srcOver
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          _palette[3].withOpacity(0.16 * fade * k),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, y - 60, w, 120));
    c.drawRect(Rect.fromLTWH(0, y - 60, w, 120), _p);
    _p
      ..shader = null
      ..blendMode = BlendMode.srcOver;
  }

  // جرقه‌ی عبوری (شهاب)
  void _sparks(Canvas c, double w, double h, double t, double k) {
    for (var s = 0; s < (lite ? 1 : 2); s++) {
      final period = 8.0 + s * 3.5;
      final cyc = ((t + s * 4.1) % period) / period;
      if (cyc > 0.14) continue;
      final u = cyc / 0.14;
      final sx = w * (s.isEven ? 0.12 + 0.72 * u : 0.92 - 0.72 * u);
      final sy = h * (0.05 + 0.26 * u + s * 0.12);
      final dir = s.isEven ? -1.0 : 1.0;
      final tail = Offset(sx + dir * 76, sy - 28);
      _p
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.7
        ..shader = LinearGradient(colors: [Colors.transparent, Colors.white.withOpacity((1 - u) * (dark ? 0.9 : 0.5))])
            .createShader(Rect.fromPoints(tail, Offset(sx, sy)));
      c.drawLine(tail, Offset(sx, sy), _p);
      _p.shader = null;
    }
  }

  @override
  bool shouldRepaint(covariant _FxPainter o) =>
      o.style != style || o.dark != dark || o.lite != lite || o.accent != accent || o.accent2 != accent2;
}

/// ورود نرم (محو + بالا آمدن) با تأخیر پله‌ای برای کارت‌ها؛ فقط یک بار پخش می‌شود.
class FxReveal extends StatefulWidget {
  const FxReveal({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  State<FxReveal> createState() => _FxRevealState();
}

class _FxRevealState extends State<FxReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  bool _started = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: (70 * widget.index.clamp(0, 8)).toInt()), () {
      if (!mounted) return;
      _started = true;
      _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // اگر انیمیشن کاهش‌یافته است، بدون حرکت نمایش داده شود
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final v = _started ? _curve.value : 0.0;
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * 22), child: child),
        );
      },
    );
  }
}

/// کارت قهرمان با حاشیه‌ی گرادیانی چرخان، درخشش نرم و شناور بودن آیکون.
class FxHeroCard extends StatefulWidget {
  const FxHeroCard({super.key, required this.leading, required this.title, required this.subtitle, this.colors});
  final Widget leading;
  final String title;
  final String subtitle;
  final List<Color>? colors;

  @override
  State<FxHeroCard> createState() => _FxHeroCardState();
}

class _FxHeroCardState extends State<FxHeroCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cols = widget.colors ?? const [Color(0xFFFF7139), Color(0xFFE31587), Color(0xFF7A4DFF), Color(0xFF00DDFF)];
    final reduce = MediaQuery.of(context).disableAnimations;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = reduce ? 0.0 : _c.value;
          final bob = sin(v * 6.2832) * 4;
          return Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: SweepGradient(
                transform: GradientRotation(v * 6.2832),
                colors: [cols[0], cols[1], cols[2], cols[3], cols[0]],
              ),
              boxShadow: [
                BoxShadow(color: cols[(v * 4).floor() % 4].withOpacity(0.28), blurRadius: 22, spreadRadius: 1),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Color.alphaBlend(cs.surface.withOpacity(0.86), const Color(0xFF000000)),
              ),
              child: Row(
                children: [
                  Transform.translate(offset: Offset(0, bob), child: widget.leading),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(widget.subtitle, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
