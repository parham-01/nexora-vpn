import 'dart:math' as math;

import 'package:flutter/material.dart';

enum Emblem { none, circle, ring, star, crescent, crescentStar, diamond, plus }

enum FlagKind { bands, nordic, uk, ensign }

/// توضیح ساده‌ی یک پرچم برای رنگ‌آمیزی دکمه (بدون ایموجی و بدون فایل تصویری).
class FlagSpec {
  const FlagSpec(
    this.bands, {
    this.weights,
    this.vertical = false,
    this.hoist,
    this.triangle,
    this.canton,
    this.emblem = Emblem.none,
    this.emblemColor = 0xFFFFFFFF,
    this.emblem2,
    this.kind = FlagKind.bands,
    this.cross = 0xFFFFFFFF,
    this.crossInner,
  });

  final List<int> bands;
  final List<double>? weights;
  final bool vertical;
  final int? hoist; // نوار عمودی کنار پرچم (مثل امارات)
  final int? triangle; // مثلث کنار پرچم (مثل فیلیپین)
  final int? canton; // مستطیل گوشه‌ی بالا-چپ (مثل آمریکا)
  final Emblem emblem;
  final int emblemColor;
  final int? emblem2;
  final FlagKind kind;
  final int cross;
  final int? crossInner;
}

const _w = 0xFFFFFFFF;
const _k = 0xFF000000;

const Map<String, FlagSpec> flagSpecs = {
  'IR': FlagSpec([0xFF239F40, _w, 0xFFDA0000], emblem: Emblem.ring, emblemColor: 0xFFDA0000),
  'US': FlagSpec([0xFFB22234, _w, 0xFFB22234, _w, 0xFFB22234, _w, 0xFFB22234, _w, 0xFFB22234, _w, 0xFFB22234, _w, 0xFFB22234], canton: 0xFF3C3B6E),
  'GB': FlagSpec([0xFF012169], kind: FlagKind.uk),
  'DE': FlagSpec([_k, 0xFFDD0000, 0xFFFFCE00]),
  'FR': FlagSpec([0xFF0055A4, _w, 0xFFEF4135], vertical: true),
  'NL': FlagSpec([0xFFAE1C28, _w, 0xFF21468B]),
  'CA': FlagSpec([0xFFD80621, _w, 0xFFD80621], vertical: true, weights: [1, 2, 1], emblem: Emblem.diamond, emblemColor: 0xFFD80621),
  'AU': FlagSpec([0xFF00008B], kind: FlagKind.ensign),
  'NZ': FlagSpec([0xFF00247D], kind: FlagKind.ensign, emblemColor: 0xFFCC142B),
  'JP': FlagSpec([_w], emblem: Emblem.circle, emblemColor: 0xFFBC002D),
  'SE': FlagSpec([0xFF006AA7], kind: FlagKind.nordic, cross: 0xFFFECC00),
  'NO': FlagSpec([0xFFBA0C2F], kind: FlagKind.nordic, cross: _w, crossInner: 0xFF00205B),
  'FI': FlagSpec([_w], kind: FlagKind.nordic, cross: 0xFF003580),
  'DK': FlagSpec([0xFFC8102E], kind: FlagKind.nordic, cross: _w),
  'IS': FlagSpec([0xFF02529C], kind: FlagKind.nordic, cross: _w, crossInner: 0xFFDC1E35),
  'CH': FlagSpec([0xFFDA291C], emblem: Emblem.plus),
  'IT': FlagSpec([0xFF009246, _w, 0xFFCE2B37], vertical: true),
  'ES': FlagSpec([0xFFAA151B, 0xFFF1BF00, 0xFFAA151B], weights: [1, 2, 1]),
  'PT': FlagSpec([0xFF006600, 0xFFFF0000], vertical: true, weights: [2, 3], emblem: Emblem.circle, emblemColor: 0xFFFFE000),
  'PL': FlagSpec([_w, 0xFFDC143C]),
  'AT': FlagSpec([0xFFED2939, _w, 0xFFED2939]),
  'BE': FlagSpec([_k, 0xFFFDDA24, 0xFFEF3340], vertical: true),
  'IE': FlagSpec([0xFF169B62, _w, 0xFFFF883E], vertical: true),
  'LU': FlagSpec([0xFFEF3340, _w, 0xFF00A2E1]),
  'SG': FlagSpec([0xFFED2939, _w], emblem: Emblem.crescent),
  'HK': FlagSpec([0xFFDE2910], emblem: Emblem.star),
  'RO': FlagSpec([0xFF002B7F, 0xFFFCD116, 0xFFCE1126], vertical: true),
  'BG': FlagSpec([_w, 0xFF00966E, 0xFFD62612]),
  'CZ': FlagSpec([_w, 0xFFD7141A], triangle: 0xFF11457E),
  'SK': FlagSpec([_w, 0xFF0B4EA2, 0xFFEE1C25]),
  'SI': FlagSpec([_w, 0xFF005DA4, 0xFFED1C24]),
  'HR': FlagSpec([0xFFFF0000, _w, 0xFF171796]),
  'RS': FlagSpec([0xFFC6363C, 0xFF0C4076, _w]),
  'HU': FlagSpec([0xFFCD2A3E, _w, 0xFF436F4D]),
  'UA': FlagSpec([0xFF0057B7, 0xFFFFD700]),
  'RU': FlagSpec([_w, 0xFF0039A6, 0xFFD52B1E]),
  'LT': FlagSpec([0xFFFDB913, 0xFF006A44, 0xFFC1272D]),
  'LV': FlagSpec([0xFF9E3039, _w, 0xFF9E3039], weights: [2, 1, 2]),
  'EE': FlagSpec([0xFF0072CE, _k, _w]),
  'MD': FlagSpec([0xFF0046AE, 0xFFFFD200, 0xFFCC092F], vertical: true, emblem: Emblem.circle, emblemColor: 0xFF8B5A2B),
  'AL': FlagSpec([0xFFE41E20], emblem: Emblem.diamond, emblemColor: _k),
  'GR': FlagSpec([0xFF0D5EAF, _w, 0xFF0D5EAF, _w, 0xFF0D5EAF, _w, 0xFF0D5EAF, _w, 0xFF0D5EAF], canton: 0xFF0D5EAF),
  'CY': FlagSpec([_w], emblem: Emblem.circle, emblemColor: 0xFFD57800),
  'TR': FlagSpec([0xFFE30A17], emblem: Emblem.crescentStar),
  'IL': FlagSpec([_w, 0xFF0038B8, _w, 0xFF0038B8, _w], weights: [1, 1, 3, 1, 1], emblem: Emblem.star, emblemColor: 0xFF0038B8),
  'AE': FlagSpec([0xFF00732F, _w, _k], hoist: 0xFFFF0000),
  'IN': FlagSpec([0xFFFF9933, _w, 0xFF138808], emblem: Emblem.ring, emblemColor: 0xFF000080),
  'KR': FlagSpec([_w], emblem: Emblem.circle, emblemColor: 0xFFCD2E3A, emblem2: 0xFF0047A0),
  'TW': FlagSpec([0xFFFE0000], canton: 0xFF000095),
  'TH': FlagSpec([0xFFA51931, 0xFFF4F5F8, 0xFF2D2A4A, 0xFFF4F5F8, 0xFFA51931], weights: [1, 1, 2, 1, 1]),
  'MY': FlagSpec([0xFFCC0001, _w, 0xFFCC0001, _w, 0xFFCC0001, _w, 0xFFCC0001, _w, 0xFFCC0001, _w], canton: 0xFF010066, emblem: Emblem.crescentStar, emblemColor: 0xFFFFCC00),
  'ID': FlagSpec([0xFFFF0000, _w]),
  'PH': FlagSpec([0xFF0038A8, 0xFFCE1126], triangle: _w),
  'VN': FlagSpec([0xFFDA251D], emblem: Emblem.star, emblemColor: 0xFFFFFF00),
  'BR': FlagSpec([0xFF009C3B], emblem: Emblem.diamond, emblemColor: 0xFFFFDF00, emblem2: 0xFF002776),
  'MX': FlagSpec([0xFF006847, _w, 0xFFCE1126], vertical: true, emblem: Emblem.circle, emblemColor: 0xFF8B6B3E),
  'AR': FlagSpec([0xFF74ACDF, _w, 0xFF74ACDF], emblem: Emblem.circle, emblemColor: 0xFFF6B40E),
  'CL': FlagSpec([_w, 0xFFD52B1E], canton: 0xFF0039A6),
  'CO': FlagSpec([0xFFFCD116, 0xFF003893, 0xFFCE1126], weights: [2, 1, 1]),
  'ZA': FlagSpec([0xFFE03C31, 0xFF007749, 0xFF001489]),
  'EG': FlagSpec([0xFFCE1126, _w, _k], emblem: Emblem.diamond, emblemColor: 0xFFC09300),
  'SA': FlagSpec([0xFF006C35], emblem: Emblem.plus),
};

/// رنگ جایگزین برای کشورهایی که در جدول نیستند: از کد کشور یک گرادیان ثابت می‌سازد.
FlagSpec flagSpecFor(String code) {
  final c = code.toUpperCase();
  final known = flagSpecs[c];
  if (known != null) return known;
  final h = c.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0xFFFF) % 360;
  Color hsl(double hue, double l) => HSLColor.fromAHSL(1, hue % 360, 0.62, l).toColor();
  return FlagSpec([hsl(h.toDouble(), 0.42).value, hsl(h + 40.0, 0.5).value, hsl(h + 80.0, 0.38).value]);
}

class FlagPainter extends CustomPainter {
  FlagPainter(this.spec);
  final FlagSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()..isAntiAlias = true;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    switch (spec.kind) {
      case FlagKind.uk:
        _paintUk(canvas, size, p);
        canvas.restore();
        return;
      case FlagKind.ensign:
        _paintEnsign(canvas, size, p);
        canvas.restore();
        return;
      case FlagKind.nordic:
        canvas.drawRect(Offset.zero & size, p..color = Color(spec.bands.first));
        final cx = w * 0.36;
        final t = h * 0.2;
        p.color = Color(spec.cross);
        canvas.drawRect(Rect.fromLTWH(cx - t / 2, 0, t, h), p);
        canvas.drawRect(Rect.fromLTWH(0, h / 2 - t / 2, w, t), p);
        if (spec.crossInner != null) {
          final t2 = t * 0.5;
          p.color = Color(spec.crossInner!);
          canvas.drawRect(Rect.fromLTWH(cx - t2 / 2, 0, t2, h), p);
          canvas.drawRect(Rect.fromLTWH(0, h / 2 - t2 / 2, w, t2), p);
        }
        canvas.restore();
        return;
      case FlagKind.bands:
        break;
    }

    final weights = spec.weights ?? List<double>.filled(spec.bands.length, 1);
    final total = weights.fold<double>(0, (a, b) => a + b);
    var offset = 0.0;
    for (var i = 0; i < spec.bands.length; i++) {
      final part = weights[i] / total;
      p.color = Color(spec.bands[i]);
      final rect = spec.vertical
          ? Rect.fromLTWH(offset * w, 0, part * w + 0.6, h)
          : Rect.fromLTWH(0, offset * h, w, part * h + 0.6);
      canvas.drawRect(rect, p);
      offset += part;
    }

    var center = Offset(w / 2, h / 2);
    var r = h * 0.24;
    if (spec.hoist != null) {
      p.color = Color(spec.hoist!);
      canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.26, h), p);
    }
    if (spec.triangle != null) {
      p.color = Color(spec.triangle!);
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(w * 0.46, h / 2)
          ..lineTo(0, h)
          ..close(),
        p,
      );
      center = Offset(w * 0.15, h / 2);
      r = h * 0.12;
    }
    if (spec.canton != null) {
      final cw = w * 0.42, ch = h * (spec.bands.length >= 5 ? 0.56 : 0.5);
      p.color = Color(spec.canton!);
      canvas.drawRect(Rect.fromLTWH(0, 0, cw, ch), p);
      if (spec.emblem == Emblem.none) {
        _star(canvas, Offset(cw / 2, ch / 2), ch * 0.3, p..color = Colors.white);
      } else {
        center = Offset(cw / 2, ch / 2);
        r = ch * 0.3;
      }
    }

    _emblem(canvas, p, center, r, size);
    canvas.restore();
  }

  void _emblem(Canvas canvas, Paint p, Offset c, double r, Size size) {
    p.style = PaintingStyle.fill;
    p.color = Color(spec.emblemColor);
    switch (spec.emblem) {
      case Emblem.none:
        break;
      case Emblem.circle:
        canvas.drawCircle(c, r, p);
        if (spec.emblem2 != null) {
          canvas.drawPath(
            Path()..addArc(Rect.fromCircle(center: c, radius: r), 0, math.pi),
            p..color = Color(spec.emblem2!),
          );
        }
      case Emblem.ring:
        canvas.drawCircle(
          c,
          r * 0.82,
          p
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.3,
        );
        canvas.drawLine(Offset(c.dx, c.dy - r * 0.7), Offset(c.dx, c.dy + r * 0.7), p..strokeWidth = r * 0.22);
        p.style = PaintingStyle.fill;
      case Emblem.star:
        _star(canvas, c, r, p);
      case Emblem.crescent:
        _crescent(canvas, c, r, p, size);
      case Emblem.crescentStar:
        _crescent(canvas, c.translate(-r * 0.2, 0), r, p, size);
        _star(canvas, c.translate(r * 0.75, 0), r * 0.42, p);
      case Emblem.diamond:
        final path = Path()
          ..moveTo(c.dx, c.dy - size.height * 0.4)
          ..lineTo(c.dx + size.width * 0.36, c.dy)
          ..lineTo(c.dx, c.dy + size.height * 0.4)
          ..lineTo(c.dx - size.width * 0.36, c.dy)
          ..close();
        canvas.drawPath(path, p);
        if (spec.emblem2 != null) {
          canvas.drawCircle(c, size.height * 0.22, p..color = Color(spec.emblem2!));
        }
      case Emblem.plus:
        final t = r * 0.5, l = r * 1.25;
        canvas.drawRect(Rect.fromCenter(center: c, width: t, height: l * 2), p..color = Colors.white);
        canvas.drawRect(Rect.fromCenter(center: c, width: l * 2, height: t), p);
    }
  }

  void _crescent(Canvas canvas, Offset c, double r, Paint p, Size size) {
    final outer = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final inner = Path()..addOval(Rect.fromCircle(center: c.translate(r * 0.38, 0), radius: r * 0.8));
    canvas.drawPath(Path.combine(PathOperation.difference, outer, inner), p);
  }

  void _star(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.4;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    p.style = PaintingStyle.fill;
    canvas.drawPath(path, p);
  }

  /// پرچم استرالیا / نیوزیلند: زمینه‌ی آبی، پرچم بریتانیا در گوشه‌ی بالا-چپ و ستاره‌ها.
  void _paintEnsign(Canvas canvas, Size size, Paint p) {
    final w = size.width, h = size.height;
    final isNz = spec.emblemColor == 0xFFCC142B;
    canvas.drawRect(Offset.zero & size, p..color = Color(spec.bands.first));

    // کانتون: نیمه‌ی بالا-چپ (یک‌چهارم پرچم)
    final cw = w * 0.5, ch = h * 0.5;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, cw, ch));
    _paintUk(canvas, Size(cw, ch), Paint());
    canvas.restore();

    p.style = PaintingStyle.fill;
    if (isNz) {
      // صلیب جنوب: چهار ستاره‌ی قرمز با لبه‌ی سفید
      final pts = [Offset(w * 0.72, h * 0.20), Offset(w * 0.86, h * 0.42), Offset(w * 0.58, h * 0.46), Offset(w * 0.72, h * 0.78)];
      for (final c in pts) {
        _starN(canvas, c, h * 0.085, 5, p..color = Colors.white);
        _starN(canvas, c, h * 0.06, 5, p..color = const Color(0xFFCC142B));
      }
      return;
    }
    // ستاره‌ی هفت‌پر فدراسیون زیر کانتون
    _starN(canvas, Offset(w * 0.25, h * 0.77), h * 0.15, 7, p..color = Colors.white);
    // صورت فلکی صلیب جنوب
    final cross = [
      [Offset(w * 0.75, h * 0.10), h * 0.075, 7],
      [Offset(w * 0.64, h * 0.35), h * 0.075, 7],
      [Offset(w * 0.86, h * 0.30), h * 0.075, 7],
      [Offset(w * 0.75, h * 0.83), h * 0.075, 7],
      [Offset(w * 0.80, h * 0.55), h * 0.045, 5],
    ];
    for (final e in cross) {
      _starN(canvas, e[0] as Offset, e[1] as double, e[2] as int, p..color = Colors.white);
    }
  }

  void _starN(Canvas canvas, Offset c, double r, int points, Paint p) {
    final path = Path();
    final n = points * 2;
    for (var i = 0; i < n; i++) {
      final rad = i.isEven ? r : r * (points == 7 ? 0.46 : 0.4);
      final a = -math.pi / 2 + i * math.pi / points;
      final pt = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    p.style = PaintingStyle.fill;
    canvas.drawPath(path, p);
  }

  void _paintUk(Canvas canvas, Size size, Paint p) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, p..color = const Color(0xFF012169));
    final diag = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.butt;
    diag.color = Colors.white;
    diag.strokeWidth = h * 0.2;
    canvas.drawLine(Offset.zero, Offset(w, h), diag);
    canvas.drawLine(Offset(w, 0), Offset(0, h), diag);
    diag.color = const Color(0xFFC8102E);
    diag.strokeWidth = h * 0.07;
    canvas.drawLine(Offset.zero, Offset(w, h), diag);
    canvas.drawLine(Offset(w, 0), Offset(0, h), diag);
    p.style = PaintingStyle.fill;
    p.color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(w / 2 - h * 0.17, 0, h * 0.34, h), p);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.33, w, h * 0.34), p);
    p.color = const Color(0xFFC8102E);
    canvas.drawRect(Rect.fromLTWH(w / 2 - h * 0.1, 0, h * 0.2, h), p);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.4, w, h * 0.2), p);
  }

  @override
  bool shouldRepaint(covariant FlagPainter old) => old.spec != spec;
}

/// نشان کوچک پرچم (رنگی، بدون ایموجی) برای ردیف لوکیشن‌ها.
class FlagBadge extends StatelessWidget {
  const FlagBadge({super.key, required this.code, this.width = 36, this.height = 26});
  final String code;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(painter: FlagPainter(flagSpecFor(code))),
        ),
      );
}

/// اسپینر «Warp» (جایگزین اسپینر قدیمی): حلقه‌ی دنباله‌دار سریع با سر درخشان، حلقه‌ی خط‌چین
/// که خلاف جهت می‌چرخد، موج پالس‌شونده و رعد وسط. فقط با Paint ساده (بدون blur) کشیده می‌شود
/// تا روی گوشی‌های ضعیف هم روان بماند. اندازه‌ی کوچک (زیر ۲۶) نسخه‌ی فشرده است.
class WarpSpinner extends StatefulWidget {
  const WarpSpinner({super.key, this.size = 40});
  final double size;

  @override
  State<WarpSpinner> createState() => _WarpSpinnerState();
}

class _WarpSpinnerState extends State<WarpSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 850))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(painter: _WarpPainter(_c)),
        ),
      );
}

class _WarpPainter extends CustomPainter {
  _WarpPainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;

  static const _cyan = Color(0xFF33D6FF);
  static const _mint = Color(0xFF69F0AE);
  static const _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final compact = size.width < 26;

    // دیسک شیشه‌ای تیره + لبه‌ی روشن
    canvas.drawCircle(c, r, Paint()..color = const Color(0x7006102A));
    canvas.drawCircle(
      c,
      r - 0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withOpacity(0.18),
    );

    // موج پالس‌شونده از وسط به بیرون (نسخه‌ی فشرده ندارد)
    if (!compact) {
      final k = (t * 2) % 1.0;
      canvas.drawCircle(
        c,
        r * (0.30 + 0.62 * k),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = _cyan.withOpacity((1 - k) * 0.5),
      );
    }

    // حلقه‌ی دنباله‌دار: طول کمان نفس می‌کشد، سر کمان همیشه جلوتر است
    final ringR = r * (compact ? 0.68 : 0.76);
    final sw = r * (compact ? 0.26 : 0.20);
    final rect = Rect.fromCircle(center: c, radius: ringR);
    final breathe = 0.5 + 0.5 * math.sin(t * _tau);
    final sweep = math.pi * (0.95 + 0.75 * breathe);
    final start = t * _tau - math.pi / 2;
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: sweep,
      colors: const [Color(0x0033D6FF), _cyan, _mint],
      stops: const [0.0, 0.72, 1.0],
      transform: GradientRotation(start),
    ).createShader(rect);
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = sw
        ..shader = shader,
    );

    // سر درخشان کمان
    final head = start + sweep;
    final hp = c + Offset(math.cos(head), math.sin(head)) * ringR;
    canvas.drawCircle(hp, sw * 0.95, Paint()..color = _mint.withOpacity(0.28));
    canvas.drawCircle(hp, sw * 0.52, Paint()..color = Colors.white);

    if (compact) {
      canvas.drawCircle(c, r * 0.16, Paint()..color = Colors.white.withOpacity(0.9));
      return;
    }

    // حلقه‌ی داخلی خط‌چین، خلاف جهت و دو برابر سریع‌تر
    final inRect = Rect.fromCircle(center: c, radius: r * 0.47);
    final a0 = -t * _tau * 2;
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.085
      ..color = Colors.white.withOpacity(0.8);
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(inRect, a0 + i * _tau / 3, _tau / 3 * 0.42, false, dash);
    }

    // رعد وسط (می‌تپد تا حس سرعت بدهد)
    final pulse = 0.86 + 0.14 * math.sin(t * _tau * 2);
    final u = r * 0.30 * pulse;
    final bolt = Path()
      ..moveTo(c.dx + 0.15 * u, c.dy - 1.0 * u)
      ..lineTo(c.dx - 0.55 * u, c.dy + 0.10 * u)
      ..lineTo(c.dx - 0.05 * u, c.dy + 0.10 * u)
      ..lineTo(c.dx - 0.20 * u, c.dy + 1.0 * u)
      ..lineTo(c.dx + 0.60 * u, c.dy - 0.25 * u)
      ..lineTo(c.dx + 0.05 * u, c.dy - 0.25 * u)
      ..close();
    canvas.drawPath(bolt, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _WarpPainter old) => false;
}

/// تیک تأیید کوچک (مثل تیک حساب تأییدشده) که با یک انیمیشن نرم ظاهر می‌شود.
class VerifiedTick extends StatelessWidget {
  const VerifiedTick({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 380),
        curve: Curves.elasticOut,
        builder: (_, v, child) => Transform.scale(scale: v.clamp(0.0, 1.2).toDouble(), child: child),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 5)],
          ),
          alignment: Alignment.center,
          child: Icon(Icons.verified_rounded, size: size, color: const Color(0xFF1D9BF0)),
        ),
      );
}
