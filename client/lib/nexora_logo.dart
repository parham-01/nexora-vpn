import 'package:flutter/material.dart';

/// لوگوی Nexora VPN: یک SVG آبی (همان مسیرهای assets/nexora_logo.svg) که با
/// CustomPainter رسم می‌شود تا به پکیج اضافه‌ای نیاز نباشد.
class NexoraLogo extends StatelessWidget {
  final double size;
  final bool glow;
  const NexoraLogo({super.key, this.size = 96, this.glow = true});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.26),
          boxShadow: glow ? [BoxShadow(color: const Color(0xFF2B6BFF).withOpacity(0.38), blurRadius: size * 0.28)] : null,
        ),
        child: CustomPaint(painter: _NexoraLogoPainter(), size: Size.square(size)),
      ),
    );
  }
}

class _NexoraLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    const full = Rect.fromLTWH(0, 0, 100, 100);
    final rr = RRect.fromRectAndRadius(full, const Radius.circular(26));

    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E2352), Color(0xFF060D22)],
        ).createShader(full),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.08),
          radius: 0.92,
          colors: [Color(0x612B8CFF), Color(0x002B8CFF)],
        ).createShader(full),
    );

    final shield = Path()
      ..moveTo(50, 11)
      ..lineTo(82, 23)
      ..lineTo(82, 49)
      ..cubicTo(82, 68, 68, 81, 50, 90)
      ..cubicTo(32, 81, 18, 68, 18, 49)
      ..lineTo(18, 23)
      ..close();
    final blue = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF6BE6FF), Color(0xFF2B6BFF)],
    ).createShader(const Rect.fromLTWH(18, 11, 64, 79));

    canvas.drawPath(shield, Paint()..color = const Color(0x2138A8FF));
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..strokeJoin = StrokeJoin.round
        ..shader = blue,
    );

    final n = Path()
      ..moveTo(37, 66)
      ..lineTo(37, 35)
      ..lineTo(63, 66)
      ..lineTo(63, 35);
    canvas.drawPath(
      n,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = blue,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// نوشته‌ی «Nexora VPN» با VPN آبی.
class NexoraWordmark extends StatelessWidget {
  final double fontSize;
  final Color textColor;
  const NexoraWordmark({super.key, this.fontSize = 27, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Nexora ', style: TextStyle(color: textColor)),
        const TextSpan(text: 'VPN', style: TextStyle(color: Color(0xFF3D8BFF))),
      ]),
      textDirection: TextDirection.ltr,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: 0.6),
    );
  }
}
