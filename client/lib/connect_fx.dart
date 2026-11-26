import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'dns_tunnel.dart';
import 'store.dart';
import 'vpn_service.dart';

const Color _green = Color(0xFF29E07F);
const Color _red = Color(0xFFFF5B5B);

/// کارت شیشه‌ای مراحل اتصال: ساخت تونل شخصی → تست پینگ DNS → تست پینگ کانفیگ → اتصال.
/// روی اندروید، ویندوز، لینوکس و مک یکسان کار می‌کند؛ روی گوشی‌های ضعیف (حالت lite) بلور و درخشش خاموش می‌شود.
class ConnectStages extends StatelessWidget {
  const ConnectStages({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<StepView>>(
      valueListenable: VpnService.I.steps,
      builder: (context, steps, _) => AnimatedSize(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: steps.isEmpty
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: _StageCard(steps: steps),
              ),
      ),
    );
  }
}

class _StageCard extends StatefulWidget {
  final List<StepView> steps;
  const _StageCard({required this.steps});

  @override
  State<_StageCard> createState() => _StageCardState();
}

class _StageCardState extends State<_StageCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();

  static const List<String> _heads = [
    'در حال ساخت تونل شخصی…',
    'در حال تست پینگ DNS…',
    'در حال تست پینگ واقعی (Relay)…',
    'در حال برقراری اتصال امن…',
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final lite = Store.lite.value;
    final steps = widget.steps;
    final done = steps.where((e) => e.state == StepPhase.done).length;
    final running = steps.indexWhere((e) => e.state == StepPhase.run);
    final failed = steps.any((e) => e.state == StepPhase.fail);
    final frac = ((done + (running >= 0 ? 0.5 : 0)) / steps.length).clamp(0.0, 1.0);
    final title = failed
        ? 'اتصال برقرار نشد'
        : done == steps.length
            ? 'تونل امن آماده است'
            : (running >= 0 ? _heads[running] : 'آماده‌سازی…');
    final main = failed ? _red : (done == steps.length ? _green : p.accent2);

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 58,
            height: 58,
            child: CustomPaint(painter: _RadarPainter(_c, main, lite, done == steps.length)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (w, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a), child: w),
                ),
                child: Text(title,
                    key: ValueKey(title),
                    style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 4),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text('${(frac * 100).round()}%  •  Noise_NK  •  ChaChaPoly  •  DoH',
                    style: TextStyle(color: p.sub, fontSize: 11.5, letterSpacing: 0.3)),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: frac),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => SizedBox(
            height: 8,
            width: double.infinity,
            child: CustomPaint(painter: _BarPainter(v, _c, main, p.accent, p.border.withOpacity(0.35))),
          ),
        ),
        const SizedBox(height: 10),
        for (final s in steps) _StepRow(step: s, ctrl: _c, p: p),
      ]),
    );

    final deco = BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [p.accent.withOpacity(0.22), p.accent2.withOpacity(0.05)],
      ),
      border: Border.all(color: main.withOpacity(0.45), width: 1.2),
      boxShadow: lite ? null : [BoxShadow(color: main.withOpacity(0.22), blurRadius: 24, spreadRadius: -2)],
    );

    Widget card = Container(decoration: deco, child: content);
    if (!lite) {
      card = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: card),
      );
    }
    return RepaintBoundary(child: card);
  }
}

class _StepRow extends StatelessWidget {
  final StepView step;
  final AnimationController ctrl;
  final P p;
  const _StepRow({required this.step, required this.ctrl, required this.p});

  @override
  Widget build(BuildContext context) {
    final col = step.state == StepPhase.fail
        ? _red
        : step.state == StepPhase.done
            ? _green
            : p.text;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: step.state == StepPhase.wait ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(step.state),
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutBack,
            builder: (context, v, _) => AnimatedBuilder(
              animation: ctrl,
              builder: (context, _) => SizedBox(
                width: 26,
                height: 26,
                child: CustomPaint(painter: _StepIconPainter(step.state, ctrl.value, v, p.accent2)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.title, style: TextStyle(color: col, fontSize: 13.5, fontWeight: FontWeight.w700)),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                alignment: Alignment.topCenter,
                child: step.detail.isEmpty
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(step.detail, style: TextStyle(color: p.sub, fontSize: 11.5, height: 1.5)),
                      ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DnsChips extends StatelessWidget {
  final P p;
  const _DnsChips({required this.p});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<DnsResult>>(
      valueListenable: VpnService.I.dnsResults,
      builder: (context, list, _) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(spacing: 7, runSpacing: 7, children: [
              for (final r in list)
                TweenAnimationBuilder<double>(
                  key: ValueKey(r.name),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 550),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) => Transform.scale(
                    scale: v.clamp(0.0, 1.4),
                    child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
                  ),
                  child: _chip(r),
                ),
            ]),
          ),
        );
      },
    );
  }

  Widget _chip(DnsResult r) {
    final c = r.ok ? _green : _red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.55)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(r.ok ? '${r.name}  ${r.ms}ms' : '${r.name}  ✕',
            style: TextStyle(color: p.text, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ----------------------------- نقاشی‌ها (مثل SVG، برداری) -----------------------------

class _RadarPainter extends CustomPainter {
  final Animation<double> anim;
  final Color color;
  final bool lite, finished;
  _RadarPainter(this.anim, this.color, this.lite, this.finished) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final t = anim.value;

    for (var i = 0; i < 3; i++) {
      final f = (t + i / 3) % 1.0;
      canvas.drawCircle(
        c,
        r * (0.25 + 0.75 * f),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = color.withOpacity((1 - f) * (finished ? 0.35 : 0.6)),
      );
    }

    if (!lite && !finished) {
      final rect = Rect.fromCircle(center: c, radius: r * 0.95);
      final sweep = Paint()
        ..shader = SweepGradient(
          colors: [color.withOpacity(0), color.withOpacity(0.6)],
          startAngle: 0,
          endAngle: pi * 0.9,
          transform: GradientRotation(t * 2 * pi),
        ).createShader(rect);
      canvas.drawArc(rect, t * 2 * pi, pi * 0.9, true, sweep);
    }

    final dots = lite ? 2 : 3;
    for (var i = 0; i < dots; i++) {
      final a = t * 2 * pi * (1 + i * 0.35) + i * 2.1;
      final o = c + Offset(cos(a), sin(a)) * (r * 0.78);
      if (!lite) {
        canvas.drawCircle(o, 4.5, Paint()..color = color.withOpacity(0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      }
      canvas.drawCircle(o, 2.4, Paint()..color = color);
    }

    // سپر وسط
    final sh = Path()
      ..moveTo(c.dx, c.dy - r * 0.32)
      ..lineTo(c.dx + r * 0.26, c.dy - r * 0.2)
      ..lineTo(c.dx + r * 0.26, c.dy + r * 0.02)
      ..quadraticBezierTo(c.dx + r * 0.24, c.dy + r * 0.24, c.dx, c.dy + r * 0.36)
      ..quadraticBezierTo(c.dx - r * 0.24, c.dy + r * 0.24, c.dx - r * 0.26, c.dy + r * 0.02)
      ..lineTo(c.dx - r * 0.26, c.dy - r * 0.2)
      ..close();
    canvas.drawPath(sh, Paint()..color = color.withOpacity(0.22));
    canvas.drawPath(
      sh,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter o) => o.color != color || o.lite != lite || o.finished != finished;
}

class _BarPainter extends CustomPainter {
  final double frac;
  final Animation<double> anim;
  final Color a, b, track;
  _BarPainter(this.frac, this.anim, this.a, this.b, this.track) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.drawRRect(rr, Paint()..color = track);
    final w = size.width * frac;
    if (w < 1) return;
    final fill = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), Radius.circular(size.height / 2));
    canvas.drawRRect(fill, Paint()..shader = LinearGradient(colors: [b, a]).createShader(Rect.fromLTWH(0, 0, max(w, 1), size.height)));
    // برق متحرک روی نوار
    canvas.save();
    canvas.clipRRect(fill);
    final x = (anim.value * 2 % 1.0) * (w + 60) - 30;
    canvas.drawRect(
      Rect.fromLTWH(x - 18, 0, 36, size.height),
      Paint()..shader = LinearGradient(colors: [Colors.white.withOpacity(0), Colors.white.withOpacity(0.55), Colors.white.withOpacity(0)]).createShader(Rect.fromLTWH(x - 18, 0, 36, size.height)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BarPainter o) => o.frac != frac || o.a != a;
}

class _StepIconPainter extends CustomPainter {
  final StepPhase state;
  final double t, prog;
  final Color accent;
  _StepIconPainter(this.state, this.t, this.prog, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    switch (state) {
      case StepPhase.wait:
        canvas.drawCircle(c, r, stroke..color = accent.withOpacity(0.35));
        break;
      case StepPhase.run:
        canvas.drawCircle(c, r, stroke..color = accent.withOpacity(0.2));
        final rect = Rect.fromCircle(center: c, radius: r);
        canvas.drawArc(
          rect,
          t * 2 * pi * 2,
          pi * 1.15,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round
            ..shader = SweepGradient(colors: [accent.withOpacity(0), accent], transform: GradientRotation(t * 2 * pi * 2)).createShader(rect),
        );
        break;
      case StepPhase.done:
        final s = prog.clamp(0.0, 1.3);
        canvas.drawCircle(c, r * s.clamp(0.0, 1.0), Paint()..color = _green.withOpacity(0.2));
        canvas.drawCircle(c, r, stroke..color = _green);
        final path = Path()
          ..moveTo(size.width * 0.28, size.height * 0.53)
          ..lineTo(size.width * 0.44, size.height * 0.68)
          ..lineTo(size.width * 0.74, size.height * 0.34);
        final m = path.computeMetrics().first;
        canvas.drawPath(m.extractPath(0, m.length * prog.clamp(0.0, 1.0)), stroke..color = _green..strokeWidth = 2.6);
        break;
      case StepPhase.fail:
        final shake = sin(prog * pi * 6) * (1 - prog.clamp(0.0, 1.0)) * 3;
        canvas.translate(shake, 0);
        canvas.drawCircle(c, r, stroke..color = _red);
        final d = r * 0.42;
        canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), stroke..color = _red..strokeWidth = 2.6);
        canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _StepIconPainter o) => true;
}
