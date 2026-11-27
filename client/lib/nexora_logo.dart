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
          borderRadius: BorderRadius.circular(size * 0.24),
          boxShadow: glow ? [BoxShadow(color: const Color(0xFF5B3CFF).withOpacity(0.35), blurRadius: size * 0.28)] : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.24),
          child: Image.asset('assets/logo.png', width: size, height: size, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
        ),
      ),
    );
  }
}

/// نماد N کوچک (برای هدر خانه): حرف N روی کاشی گرد تیره با لبه‌ی درخشان آبی‌بنفش
class NexoraMark extends StatelessWidget {
  final double size;
  const NexoraMark({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF111A3C), Color(0xFF070A1A)]),
        border: Border.all(color: const Color(0xFF6A5CFF).withOpacity(0.55), width: 1.2),
      ),
      child: Image.asset('assets/logo_mark.png', fit: BoxFit.contain, filterQuality: FilterQuality.medium),
    );
  }
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
