import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'nexora_logo.dart';
import 'store.dart';
import 'vpn_service.dart';

class AppBg extends StatelessWidget {
  final Widget child;
  const AppBg({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<bool>(valueListenable: Store.lite, builder: (context, lite, _) => Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF050D24), Color(0xFF040A1E), Color(0xFF03071A)]
              : [p.bg, p.bg],
        ),
      ),
      child: Stack(children: [
        if (dark && !lite && kFancy) const Positioned.fill(child: _Aurora()),
        if (dark && !lite)
          Positioned(
            top: -120,
            left: -80,
            right: -80,
            child: IgnorePointer(
              child: Container(
                height: 320,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [p.accent.withOpacity(0.16), Colors.transparent],
                    radius: 0.8,
                  ),
                ),
              ),
            ),
          ),
        child,
      ]),
    ));
  }
}

class Panel extends StatefulWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final EdgeInsets margin;
  final Color? tint;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.tint,
  });

  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fancy = kFancy && !Store.lite.value && dark;
    final r = BorderRadius.circular(18);
    final tint = widget.tint;
    final inner = widget.onTap == null
        ? Padding(padding: widget.padding, child: widget.child)
        : Material(
            color: Colors.transparent,
            borderRadius: r,
            child: InkWell(borderRadius: r, onTap: widget.onTap, child: Padding(padding: widget.padding, child: widget.child)),
          );
    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [(tint ?? const Color(0xFF12275A)).withOpacity(fancy ? 0.42 : 0.55), (tint ?? const Color(0xFF0A1735)).withOpacity(fancy ? 0.58 : 0.70)]
              : [p.card, p.card],
        ),
        border: Border.all(color: (fancy && _hover ? p.accent2 : p.border).withOpacity(fancy && _hover ? 0.9 : (dark ? 0.55 : 0.8)), width: 1),
        boxShadow: fancy && _hover ? [BoxShadow(color: p.accent2.withOpacity(0.28), blurRadius: 20)] : null,
      ),
      child: fancy ? ClipRRect(borderRadius: r, child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: inner)) : inner,
    );
    if (!fancy) return box;
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(scale: _hover && widget.onTap != null ? 1.012 : 1.0, duration: const Duration(milliseconds: 150), curve: Curves.easeOut, child: box),
    );
  }
}

class Group extends StatelessWidget {
  final List<Widget> children;
  const Group({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Divider(height: 1, thickness: 1, indent: 14, endIndent: 14, color: p.border.withOpacity(0.35)));
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? [const Color(0xFF0E1D45).withOpacity(0.75), const Color(0xFF091330).withOpacity(0.85)] : [p.card, p.card],
        ),
        border: Border.all(color: p.border.withOpacity(0.5)),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Column(children: rows)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(text, style: TextStyle(color: P.of(context).text, fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      );
}

class Tile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool boxed;
  const Tile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.boxed = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final row = Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        SizedBox(width: 38, child: Icon(icon, color: iconColor ?? p.accent2, size: 30)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                textDirection: TextDirection.rtl,
                style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w700)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(subtitle!, textDirection: TextDirection.rtl, style: TextStyle(color: p.sub, fontSize: 12)),
              ),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
    final padded = Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), child: row);
    final inner = InkWell(onTap: onTap, child: padded);
    if (boxed) {
      return Panel(onTap: onTap, margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), child: row);
    }
    return Material(color: Colors.transparent, child: inner);
  }
}

class Chevron extends StatelessWidget {
  const Chevron({super.key});
  @override
  Widget build(BuildContext context) => Icon(Icons.chevron_right_rounded, color: P.of(context).text.withOpacity(0.9), size: 28);
}

class Toggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const Toggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 54,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: value ? p.accent : const Color(0xFF2A3350),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 120),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
        ),
      ),
    );
  }
}

class ShieldPainter extends CustomPainter {
  final Color a, b;
  ShieldPainter(this.a, this.b);

  Path _shield(Rect r) {
    final w = r.width, h = r.height;
    final path = Path();
    path.moveTo(r.left + w * 0.5, r.top);
    path.cubicTo(r.left + w * 0.66, r.top + h * 0.10, r.left + w * 0.84, r.top + h * 0.14, r.right, r.top + h * 0.14);
    path.lineTo(r.right, r.top + h * 0.52);
    path.cubicTo(r.right, r.top + h * 0.78, r.left + w * 0.72, r.top + h * 0.92, r.left + w * 0.5, r.bottom);
    path.cubicTo(r.left + w * 0.28, r.top + h * 0.92, r.left, r.top + h * 0.78, r.left, r.top + h * 0.52);
    path.lineTo(r.left, r.top + h * 0.14);
    path.cubicTo(r.left + w * 0.16, r.top + h * 0.14, r.left + w * 0.34, r.top + h * 0.10, r.left + w * 0.5, r.top);
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(size.width * 0.06, size.height * 0.02, size.width * 0.88, size.height * 0.96);
    final outer = _shield(r);
    final shader = LinearGradient(colors: [b, a], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(r);

    canvas.drawPath(
        outer,
        Paint()
          ..color = b.withOpacity(0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.10
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.09));
    canvas.drawPath(
        outer,
        Paint()
          ..shader = LinearGradient(
                  colors: [const Color(0xFF0B2A66).withOpacity(0.95), const Color(0xFF05153A).withOpacity(0.95)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter)
              .createShader(r));
    canvas.drawPath(
        outer,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.045
          ..strokeJoin = StrokeJoin.round);
    final inner = _shield(Rect.fromLTWH(r.left + r.width * 0.10, r.top + r.height * 0.09, r.width * 0.80, r.height * 0.80));
    canvas.drawPath(
        inner,
        Paint()
          ..color = b.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.018);

    final cx = size.width * 0.5;
    final bodyW = size.width * 0.36, bodyH = size.height * 0.27;
    final bodyTop = size.height * 0.42;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(cx - bodyW / 2, bodyTop, bodyW, bodyH), Radius.circular(size.width * 0.045));
    final shackle = Path()
      ..moveTo(cx - bodyW * 0.30, bodyTop)
      ..lineTo(cx - bodyW * 0.30, bodyTop - size.height * 0.07)
      ..arcToPoint(Offset(cx + bodyW * 0.30, bodyTop - size.height * 0.07),
          radius: Radius.circular(bodyW * 0.30), clockwise: true)
      ..lineTo(cx + bodyW * 0.30, bodyTop);
    canvas.drawPath(
        shackle,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.05
          ..strokeCap = StrokeCap.round);
    canvas.drawRRect(
        body,
        Paint()
          ..shader = LinearGradient(colors: [b, a], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(body.outerRect));
    final kp = Paint()..color = const Color(0xFF06173F);
    canvas.drawCircle(Offset(cx, bodyTop + bodyH * 0.40), size.width * 0.032, kp);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, bodyTop + bodyH * 0.68), width: size.width * 0.026, height: size.height * 0.07), const Radius.circular(2)),
        kp);
  }

  @override
  bool shouldRepaint(covariant ShieldPainter old) => old.a != a || old.b != b;
}

class Brand extends StatelessWidget {
  final double size;
  const Brand({super.key, this.size = 90});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Store.lite,
      builder: (context, lite, _) => NexoraLogo(size: size, glow: !lite),
    );
  }
}

class GlobePainter extends CustomPainter {
  final Color c;
  final bool on;
  final bool lite;
  GlobePainter(this.c, this.on, this.lite);

  static final List<List<double>> _stars = () {
    final r = Random(7);
    return List.generate(36, (_) => [r.nextDouble(), r.nextDouble() * 0.5, r.nextDouble() * 1.1 + 0.3]);
  }();

  // ماسک ساده‌ی «خشکی» با ترکیب موج‌ها (ثابت و قطعی)
  static bool _land(double psi, double phi) {
    final v = sin(3.1 * psi + 1.7) * sin(5.0 * phi + 0.6) + 0.6 * sin(7.0 * psi - 2.0 * phi) + 0.35 * sin(11.0 * psi + 4.0 * phi);
    return v > 0.18;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final glow = on ? const Color(0xFF29E07F) : c;
    final radius = size.width * 0.78;
    final center = Offset(size.width / 2, size.height * 0.55 + radius);

    // هاله‌ی چندلایه‌ی اتمسفر
    if (lite) {
      canvas.drawCircle(center, radius + 10, Paint()..color = glow.withOpacity(0.10)..style = PaintingStyle.stroke..strokeWidth = 16);
      canvas.drawCircle(center, radius + 5, Paint()..color = glow.withOpacity(0.22)..style = PaintingStyle.stroke..strokeWidth = 8);
    } else {
      canvas.drawCircle(center, radius + 16, Paint()..color = glow.withOpacity(0.35)..style = PaintingStyle.stroke..strokeWidth = 26..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26));
      canvas.drawCircle(center, radius + 6, Paint()..color = glow.withOpacity(0.9)..style = PaintingStyle.stroke..strokeWidth = 4..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    }

    // بدنه‌ی سیاره
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, -1),
            radius: 1.0,
            colors: [glow.withOpacity(0.50), const Color(0xFF0B2E70).withOpacity(0.92), const Color(0xFF050E2B), const Color(0xFF02040F)],
            stops: const [0.0, 0.14, 0.40, 0.7],
          ).createShader(rect));

    // خشکی نقطه‌نقطه روی کره (دید از بالا؛ نقطه‌ها به سمت لبه کوچک می‌شوند)
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    final rows = lite ? 14 : 24;
    final dphi = 0.92 / rows;
    final landP = Paint()..color = Color.lerp(glow, Colors.white, 0.35)!.withOpacity(0.85);
    final seaP = Paint()..color = glow.withOpacity(0.22);
    for (var i = 1; i <= rows; i++) {
      final phi = i * dphi;
      final sp = sin(phi);
      final cols = max(10, (pi * sp / dphi).floor());
      final dr = max(0.8, (lite ? 1.9 : 1.6) * (1.0 - 0.45 * phi));
      for (var j = 0; j <= cols; j++) {
        final psi = pi * (j + 0.5) / (cols + 1);
        final x = center.dx + radius * sp * cos(psi);
        final y = center.dy - radius * cos(phi);
        if (x < -4 || x > size.width + 4 || y > size.height + 4) continue;
        final fy = sin(psi); // نزدیک لبه‌ی چپ و راست کوچک‌تر
        final land = _land(psi, phi);
        canvas.drawCircle(Offset(x, y), dr * (0.55 + 0.45 * fy), land ? landP : seaP);
      }
    }
    // درخشش لبه‌ی بالایی
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, -1),
            radius: 1.0,
            colors: [glow.withOpacity(0.38), glow.withOpacity(0.0)],
            stops: const [0.0, 0.10],
          ).createShader(rect));
    canvas.restore();

    // حلقه‌ی لبه با گرادیان
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = LinearGradient(colors: [Colors.white.withOpacity(0.95), glow, glow.withOpacity(0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)
              .createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);

  }

  @override
  bool shouldRepaint(covariant GlobePainter old) => old.c != c || old.on != on || old.lite != lite;
}

class SlideSwitch extends StatefulWidget {
  final bool on;
  final bool busy;
  final ValueChanged<bool> onChanged;
  const SlideSwitch({super.key, required this.on, required this.busy, required this.onChanged});

  @override
  State<SlideSwitch> createState() => _SlideSwitchState();
}

class _SlideSwitchState extends State<SlideSwitch> {
  static const double w = 270;
  static const double h = 88;
  static const double k = 76;
  static const double maxX = w - k - 12;
  static const Color green = Color(0xFF29E07F);
  static const Color neon = Color(0xFF2F7BFF);
  static const Color cyan = Color(0xFF52D6FF);
  final ValueNotifier<double> _drag = ValueNotifier(0);
  bool _dragging = false;

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  Widget _shield(bool on) => Stack(alignment: Alignment.center, children: [
        Icon(on ? Icons.shield_rounded : Icons.shield_outlined, size: 44, color: Colors.white),
        if (!on) const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.lock_rounded, size: 17, color: Colors.white)),
        if (on) const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.check_rounded, size: 24, color: Color(0xFF0B8F52))),
      ]);

  @override
  Widget build(BuildContext context) {
    final on = widget.on;
    final target = on ? 0.0 : maxX;
    final glow = on ? green : neon;
    final edge = on ? green : cyan;
    return RepaintBoundary(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.busy ? null : () => widget.onChanged(!on),
            onHorizontalDragStart: (_) {
              _dragging = true;
              _drag.value = target;
            },
            onHorizontalDragUpdate: (d) => _drag.value = (_drag.value + d.delta.dx).clamp(0.0, maxX),
            onHorizontalDragEnd: (_) {
              final wantOn = _drag.value < maxX / 2;
              setState(() => _dragging = false);
              if (!widget.busy && wantOn != on) widget.onChanged(wantOn);
            },
            onHorizontalDragCancel: () => setState(() => _dragging = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: w,
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(h / 2),
                gradient: const LinearGradient(colors: [Color(0xFF0A1646), Color(0xFF050A26)]),
                border: Border.all(color: edge.withOpacity(0.9), width: 2),
                boxShadow: [
                  BoxShadow(color: glow.withOpacity(0.45), blurRadius: 22, spreadRadius: 1),
                  BoxShadow(color: glow.withOpacity(0.20), blurRadius: 40, spreadRadius: 4),
                ],
              ),
              child: Stack(alignment: Alignment.centerLeft, children: [
                // خطوط سرعت بین فلش و دکمه
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 28),
                    child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      for (var i = 0; i < 4; i++)
                        Container(
                          height: 2,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(colors: [glow.withOpacity(0.0), glow.withOpacity(on ? 0.0 : 0.55)]),
                          ),
                        ),
                    ]),
                  ),
                ),
                Positioned.fill(
                  child: Align(
                    alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: widget.busy
                          ? const SizedBox.shrink()
                          : (on
                              ? const Text('ON', style: TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 1.5, fontWeight: FontWeight.w700))
                              : const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 42)),
                    ),
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _drag,
                  child: Container(
                    width: k,
                    height: k,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.25, -0.3),
                        colors: on ? const [Color(0xFF5BF0A5), Color(0xFF0FA862)] : const [Color(0xFF7FE0FF), Color(0xFF1E6BFF)],
                      ),
                      border: Border.all(color: Colors.white.withOpacity(0.85), width: 2.5),
                      boxShadow: [BoxShadow(color: glow.withOpacity(0.85), blurRadius: 24, spreadRadius: 2)],
                    ),
                    child: widget.busy
                        ? const RepaintBoundary(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)))
                        : _shield(on),
                  ),
                  builder: (_, v, child) {
                    final x = _dragging ? v : target;
                    return AnimatedPositioned(
                      duration: Duration(milliseconds: _dragging ? 0 : 180),
                      curve: Curves.easeOutCubic,
                      left: 6 + x,
                      child: child!,
                    );
                  },
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text(widget.busy ? 'Connecting...' : (on ? 'Connected' : 'Tap to Connect'),
              style: TextStyle(color: on ? green : const Color(0xFF9FB0DA), fontSize: 16, letterSpacing: 0.4)),
        ]),
      ),
    );
  }
}

class AlertMessage extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const AlertMessage({super.key, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.red.withOpacity(0.14),
          border: Border.all(color: Colors.redAccent.withOpacity(0.7)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_rounded, color: Colors.redAccent, size: 22),
          const SizedBox(width: 10),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFFF8A8A)))),
        ]),
      ),
    );
  }
}

class DesktopSidebar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const DesktopSidebar({super.key, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    Widget item(int i, IconData ic, String t) => _SideItem(sel: i == index, icon: ic, label: t, onTap: () => onTap(i));

    return Container(
      width: 236,
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 16),
      decoration: BoxDecoration(
        color: p.card.withOpacity(0.9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: p.border.withOpacity(0.6)),
      ),
      child: Column(children: [
        const Brand(size: 84),
        const SizedBox(height: 12),
        NexoraWordmark(fontSize: 20, textColor: p.text),
        const SizedBox(height: 28),
        item(0, Icons.home_rounded, 'اتصال'),
        item(2, Icons.info_outline_rounded, 'اطلاعات'),
        item(3, Icons.public_rounded, 'فایرفاکس'),
        const Spacer(),
        ValueListenableBuilder<VpnStatus>(
          valueListenable: VpnService.I.status,
          builder: (context, s, _) {
            final on = s.phase == Phase.on;
            final col = on ? const Color(0xFF29E07F) : (s.phase == Phase.connecting ? Colors.amber : p.sub);
            return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(on ? 'متصل' : (s.phase == Phase.connecting ? 'در حال اتصال...' : 'قطع'), style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.w700)),
            ]);
          },
        ),
      ]),
    );
  }
}

class NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const NavBar({super.key, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    Widget item(int i, IconData ic, String t) {
      final sel = i == index;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(ic, color: sel ? p.accent2 : p.sub, size: 26),
              const SizedBox(height: 3),
              Text(t, style: TextStyle(color: sel ? p.text : p.sub, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.border.withOpacity(0.6)))),
        child: Row(children: [
          item(0, Icons.home_rounded, 'اتصال'),
          item(2, Icons.info_outline_rounded, 'اطلاعات'),
          item(3, Icons.public_rounded, 'فایرفاکس'),
        ]),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool back;
  final Color? iconColor;
  const PageHeader({super.key, required this.title, required this.icon, this.back = false, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 10),
        child: Row(children: [
          SizedBox(
            width: 44,
            child: back
                ? IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: Icon(Icons.chevron_left_rounded, color: p.text, size: 34),
                  )
                : null,
          ),
          Expanded(child: Center(child: Text(title, style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w800)))),
          SizedBox(width: 44, child: Icon(icon, color: iconColor ?? p.accent2, size: 28)),
        ]),
      ),
    );
  }
}

class SubPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const SubPage({super.key, required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: AppBg(
        child: SafeArea(
          child: Column(children: [
            PageHeader(title: title, icon: icon, back: true),
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: children)),
          ]),
        ),
      ),
    );
  }
}


// ───────────────────────── افکت‌های آیفون / ویندوز ─────────────────────────
class _SideItem extends StatefulWidget {
  final bool sel;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SideItem({required this.sel, required this.icon, required this.label, required this.onTap});

  @override
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final sel = widget.sel;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: sel ? p.accent.withOpacity(0.22) : (_hover ? p.accent.withOpacity(0.09) : Colors.transparent),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: sel ? p.accent2.withOpacity(0.75) : Colors.transparent),
            boxShadow: sel ? [BoxShadow(color: p.accent2.withOpacity(0.25), blurRadius: 14)] : null,
          ),
          child: Row(children: [
            AnimatedScale(
              scale: _hover || sel ? 1.14 : 1.0,
              duration: const Duration(milliseconds: 180),
              child: Icon(widget.icon, color: sel ? p.accent2 : p.sub, size: 24),
            ),
            const SizedBox(width: 12),
            Text(widget.label, style: TextStyle(color: sel || _hover ? p.text : p.sub, fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

// پس‌زمینه‌ی آرورا: سه هاله‌ی رنگی که آرام حرکت می‌کنند (فقط گرادیان؛ سبک)
class _Aurora extends StatefulWidget {
  const _Aurora();

  @override
  State<_Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<_Aurora> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _AuroraPainter(_c.value, p.accent, p.accent2), size: Size.infinite),
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  final Color a, b;
  _AuroraPainter(this.t, this.a, this.b);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = max(w, h) * 0.5;
    void blob(double ph, double fx, double fy, Color c, double op) {
      final cx = w * (0.5 + 0.38 * sin(2 * pi * (t * fx + ph)));
      final cy = h * (0.45 + 0.32 * cos(2 * pi * (t * fy + ph * 1.7)));
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..shader = RadialGradient(colors: [c.withOpacity(op), c.withOpacity(0)]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
    }

    blob(0.00, 1, 1, a, 0.20);
    blob(0.35, 2, 1, b, 0.13);
    blob(0.70, 1, 2, const Color(0xFF7A5CFF), 0.12);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t;
}

// موج‌های سبز دور دکمه‌ی اتصال وقتی وصل هستی
class PulseRings extends StatefulWidget {
  final Color color;
  const PulseRings({super.key, required this.color});

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(painter: _RingsPainter(_c.value, widget.color), size: Size.infinite),
          ),
        ),
      );
}

class _RingsPainter extends CustomPainter {
  final double t;
  final Color c;
  _RingsPainter(this.t, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final ctr = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final k = (t + i / 3) % 1.0;
      canvas.drawCircle(
        ctr,
        46 + k * 120,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * (1 - k) + 0.4
          ..color = c.withOpacity(0.5 * (1 - k)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) => old.t != t;
}


// ───────────────────────── سبک جدید تنظیمات (کارت گرد، آیکن رنگی سمت راست، کلید سمت چپ) ─────────────────────────
class SSection extends StatelessWidget {
  final String text;
  const SSection(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(text, style: TextStyle(color: P.of(context).sub, fontSize: 14.5, fontWeight: FontWeight.w700)),
        ),
      );
}

class SCard extends StatelessWidget {
  final List<Widget> children;
  const SCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        // خط جداکننده از لبه‌ی چپ کارت تا ابتدای متن (زیر آیکن نمی‌رود)
        rows.add(Padding(
          padding: const EdgeInsets.only(right: 66),
          child: Divider(height: 1, thickness: 1, color: p.border.withOpacity(0.28)),
        ));
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.border.withOpacity(0.22)),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(26), child: Column(children: rows)),
    );
  }
}

class STile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final String? value; // متن کنار فلش (مثل «فارسی»)
  final Widget? trailing;
  final VoidCallback? onTap;
  const STile({super.key, required this.icon, required this.title, this.iconColor, this.subtitle, this.value, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final ic = iconColor ?? p.accent;
    final Widget end = trailing ??
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (value != null) Text(value!, style: TextStyle(color: p.sub, fontSize: 15)),
          if (onTap != null) Icon(Icons.chevron_left_rounded, color: p.sub, size: 28),
        ]);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: ic, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(color: p.text, fontSize: 16.5, fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(subtitle!, style: TextStyle(color: p.sub, fontSize: 13, height: 1.6)),
                    ),
                ]),
              ),
              const SizedBox(width: 10),
              end,
            ]),
          ),
        ),
      ),
    );
  }
}

class SToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const SToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 54,
        height: 32,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: value ? const Color(0xFF30D158) : const Color(0xFF3A4057),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            width: 27,
            height: 27,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
  }
}

/// قالب صفحه‌ی تنظیمات: دکمه‌ی گردِ برگشت بالا-راست و عنوان وسط
class SettingsScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SettingsScaffold({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: AppBg(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => Navigator.maybePop(context),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: p.card, border: Border.all(color: p.border.withOpacity(0.3))),
                          child: Icon(Icons.chevron_right_rounded, color: p.text, size: 30),
                        ),
                      ),
                      Expanded(child: Center(child: Text(title, style: TextStyle(color: p.text, fontSize: 19, fontWeight: FontWeight.w800)))),
                      const SizedBox(width: 48),
                    ]),
                  ),
                ),
                Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: children)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// دکمه‌ی گرد شیشه‌ای پروفایل (بالا-چپ صفحه‌ی خانه)
class ProfileButton extends StatelessWidget {
  final VoidCallback onTap;
  const ProfileButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withOpacity(0.10), const Color(0xFF6A5CFF).withOpacity(0.14)]),
          border: Border.all(color: const Color(0xFF8A7CFF).withOpacity(0.55), width: 1.2),
        ),
        child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

/// موج درخشان و نقطه‌چین بالای خانه (ثابت و سبک؛ فقط یک‌بار رسم می‌شود)
class HeaderWave extends StatelessWidget {
  const HeaderWave({super.key});

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(painter: _WavePainter(), size: Size.infinite));
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(-10, h * 0.78)
      ..cubicTo(w * 0.18, h * 1.05, w * 0.30, h * 0.18, w * 0.52, h * 0.34)
      ..cubicTo(w * 0.72, h * 0.50, w * 0.82, h * 0.98, w + 10, h * 0.62);
    final shader = const LinearGradient(colors: [Color(0xFF2A6BFF), Color(0xFF7A3CFF), Color(0xFFB04CFF)]).createShader(Rect.fromLTWH(0, 0, w, h));
    for (final e in const [[9.0, 0.06], [5.0, 0.12], [2.0, 0.55]]) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = e[0]
          ..shader = shader
          ..color = Colors.white.withOpacity(e[1]),
      );
    }
    // نقطه‌چین محو زیر موج
    const cols = 26, rows = 5;
    final dp = Paint();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = w * (c + 0.5) / cols;
        final y = h * (0.62 + r * 0.075);
        final fade = (1 - r / rows) * (0.25 + 0.75 * (c / cols));
        dp.color = Color.lerp(const Color(0xFF3A7BFF), const Color(0xFF9A4CFF), c / cols)!.withOpacity(0.55 * fade);
        canvas.drawCircle(Offset(x, y), 1.5 - r * 0.15, dp);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
