import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'store.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  راهنمای ورود NEXORA (فقط اولین اجرا)
//  ۱) انیمیشن سینمایی ورود: سفر ستاره‌ای، حلقه‌های پیکسلی، انفجار قلب، عنوان گلیچی و افتادن میمی
//  ۲) تور نورافکنی: میمی (گربه‌ی پیکسلی صورتی) همه‌ی بخش‌های «خانه» و بعد «Firefox» را
//     دونه‌دونه و به ترتیب نشان می‌دهد؛ دکمه‌ی Skip صورتی همیشه بالا است.
//  هر نوع خروج (Skip / شروع / برگشت) یعنی دیده شد؛ دیگر نمایش داده نمی‌شود (Store.introSeen).
// ═════════════════════════════════════════════════════════════════════════════

// ───────────────────────── ثبت هدف‌ها برای تور ─────────────────────────
class Tour {
  static final Map<String, GlobalKey> _keys = {};
  static Future<void> Function(IntroAnim anim, Buddy buddy)? launch;

  static GlobalKey keyOf(String id) => _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'tour-$id'));

  /// مستطیل هدف روی صفحه (مختصات سراسری)؛ اگر هدف ساخته/دیده نشده باشد null.
  static Rect? rectOf(String id) {
    final ctx = _keys[id]?.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    return ro.localToGlobal(Offset.zero) & ro.size;
  }
}

/// دور هر ویجتی که تور باید نشانش بدهد؛ بعد از اولین اجرا هیچ سربار اضافه‌ای ندارد.
class TourTarget extends StatelessWidget {
  final String id;
  final Widget child;
  const TourTarget(this.id, this.child, {super.key});

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: Tour.keyOf(id), child: child);
  }
}

// ───────────────────────── گربه‌ی پیکسلی «میمی» (طرح اورجینال NEXORA) ─────────────────────────
const List<String> _kCat = [
  '.oo.......ooooo.',
  '.oro.....obbbbo.',
  '.orpooooooobBbo.',
  'opppppppyppppppo',
  'oppppppppppppppo',
  'opppeeppppeepppo',
  'opppeeppppeepppo',
  'orrppppyyppprrpo',
  'oppppppmppmppppo',
  '.oppppppppppppo.',
  '..oooooooooooo..',
  '...oppppppppo...',
  '...ohhhhhhhho...',
  '...oppppppppo...',
  '...ooo....ooo...',
];

const Map<String, Color> _kCatColors = {
  'o': Color(0xFF5A2250),
  'p': Color(0xFFFFC2E0),
  'r': Color(0xFFFF8FC4),
  'h': Color(0xFFFF4FA3),
  'e': Color(0xFF2B1030),
  'y': Color(0xFFFFE066),
  'm': Color(0xFF8C3A78),
  'b': Color(0xFFFF2D87),
  'B': Color(0xFFD81B6A),
};

const List<String> _kBunny = [
  '..ooo......ooo..',
  '.oprpo....oprpo.',
  '.oprpo....oprpo.',
  'oppppppppppppppo',
  'oppppppppppppppo',
  'opppeeppppeepppo',
  'opppeeppppeepppo',
  'orrppppyyppprrpo',
  'oppppppmppmppppo',
  '.oppppppppppppo.',
  '..oooooooooooo..',
  '...oppppppppo...',
  '...ohhhhhhhho...',
  '...oppppppppo...',
  '...ooo....ooo...',
];
const List<String> _kSuper = [
  '....oooooooo....',
  '...okkkkkkkko...',
  '..okkkkkkkkkko..',
  'oppppppppppppppo',
  'oppppppppppppppo',
  'opppeeppppeepppo',
  'opppeeppppeepppo',
  'orrppppyyppprrpo',
  'oppppppmppmppppo',
  '.oppppppppppppo.',
  'cc..oooooooo..cc',
  'ccc.ohhhhhho.ccc',
  'ccc.ohhSShho.ccc',
  'ccc.ohhhhhho.ccc',
  'cc..ooo..ooo..cc',
];
const List<String> _kBat = [
  'k..............k',
  'kk............kk',
  'kkkkkkkkkkkkkkkk',
  'kkkkkkkkkkkkkkkk',
  'kkkkkkkkkkkkkkkk',
  'kkkkeekkkkeekkkk',
  'kkkkeekkkkeekkkk',
  'kkkppppppppppkkk',
  '.kkppppmmppppkk.',
  '..kkppppppppkk..',
  '.wwwwwwwwwwwwww.',
  'wwwwwwwwwwwwwwww',
  'wywwwwwwwwwwwwyw',
  'wwwwwwwwwwwwwwww',
  '.tttt......tttt.',
];
const Map<String, Color> _kBunnyColors = {
  'o': Color(0xFF3B2A5A),
  'p': Color(0xFFF4ECFF),
  'r': Color(0xFFFFA6D5),
  'h': Color(0xFFB58CFF),
  'e': Color(0xFF2B1030),
  'y': Color(0xFFFF7BC0),
  'm': Color(0xFF8C3A78),
  'f': Color(0xFFFFE066),
  'g': Color(0xFFFF4FA3),
};
const Map<String, Color> _kSuperColors = {
  'o': Color(0xFF1B1B3A),
  'p': Color(0xFFFFD9B3),
  'r': Color(0xFFFF9E9E),
  'h': Color(0xFF1E5BFF),
  'c': Color(0xFFE8142B),
  'S': Color(0xFFFFE066),
  'e': Color(0xFF14081F),
  'y': Color(0xFFE0A878),
  'm': Color(0xFF8C3A2E),
  'k': Color(0xFF1A1A2E),
  'f': Color(0xFFFFE066),
};
const Map<String, Color> _kBatColors = {
  'k': Color(0xFF3A3A5C),
  'p': Color(0xFFFFD9B3),
  'e': Color(0xFFFFFFFF),
  'm': Color(0xFF8C3A2E),
  'w': Color(0xFFE9EEF5),
  'y': Color(0xFFFFE066),
  't': Color(0xFF2B2B35),
  'f': Color(0xFFFFE066),
};
const Map<String, Color> _kCrownColors = {
  'y': Color(0xFFFFE066),
  'b': Color(0xFF38E8FF),
  'r': Color(0xFFFF2D87),
};
const List<String> _kFlower = [
  '.ff.',
  'fggf',
  '.ff.',
];

const List<String> _kStar = [
  '.f.',
  'fff',
  '.f.',
];

const List<String> _kBatSign = [
  'fkffkf',
  '.fkkf.',
];

enum Buddy { mimi, leila, superman, batmobile }

class _BuddyInfo {
  final String name;
  final String kind;
  final List<String> rows;
  final Map<String, Color> colors;
  final List<String> acc;
  final Map<String, Color> accColors;
  final double ax;
  final double ay;
  const _BuddyInfo(this.name, this.kind, this.rows, this.colors, this.acc, this.accColors, this.ax, this.ay);
}

const Map<Buddy, _BuddyInfo> _kBuddies = {
  Buddy.mimi: _BuddyInfo('میمی', 'دختر', _kCat, _kCatColors, _kCrown, _kCrownColors, 4.5, -3.6),
  Buddy.leila: _BuddyInfo('لیلی', 'دختر', _kBunny, _kBunnyColors, _kFlower, _kBunnyColors, 6, 0),
  Buddy.superman: _BuddyInfo('سوپرمن', 'پسر', _kSuper, _kSuperColors, _kStar, _kSuperColors, 6.5, -3.4),
  Buddy.batmobile: _BuddyInfo('بتموبیل', 'پسر', _kBat, _kBatColors, _kBatSign, _kBatColors, 5, 11),
};

enum CatMood { idle, happy }

class PixelCat extends StatelessWidget {
  final double width;
  final bool blink;
  final CatMood mood;
  final double t;
  final Buddy buddy;
  const PixelCat({super.key, this.width = 180, this.blink = false, this.mood = CatMood.idle, this.t = 0, this.buddy = Buddy.mimi});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, width * _kCat.length / 16),
      painter: _CatPainter(blink, mood, t, buddy),
    );
  }
}

const List<String> _kCrown = [
  'y..y..y',
  'yyyyyyy',
  'ybyryby',
  'yyyyyyy',
];

class _CatPainter extends CustomPainter {
  final bool blink;
  final CatMood mood;
  final double t;
  final Buddy buddy;
  _CatPainter(this.blink, this.mood, this.t, this.buddy);

  void _plus(Canvas canvas, Paint p, double x, double y, double q) {
    canvas.drawRect(Rect.fromLTWH(x - q / 2, y - q / 2, q, q), p);
    canvas.drawRect(Rect.fromLTWH(x - q * 1.5, y - q / 2, q, q), p);
    canvas.drawRect(Rect.fromLTWH(x + q * 0.5, y - q / 2, q, q), p);
    canvas.drawRect(Rect.fromLTWH(x - q / 2, y - q * 1.5, q, q), p);
    canvas.drawRect(Rect.fromLTWH(x - q / 2, y + q * 0.5, q, q), p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 0.5);
    final rad = size.width * 0.95;
    canvas.drawCircle(
      Offset(cx, cy),
      rad * (0.82 + 0.1 * pulse),
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFFFF5FAE).withOpacity(0.6), const Color(0xFFB45CFF).withOpacity(0.25), const Color(0x00FF5FAE)],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: rad)),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.5
      ..color = const Color(0xFF38E8FF).withOpacity(0.25 + 0.3 * pulse);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, size.height * 1.02), width: size.width * (0.9 + 0.15 * pulse), height: s * 2.2), ring);

    final bi = _kBuddies[buddy]!;
    final paint = Paint()..isAntiAlias = false;
    var firstEye = -1;
    for (var y = 0; y < bi.rows.length; y++) {
      if (firstEye < 0 && bi.rows[y].contains('e')) firstEye = y;
    }
    for (var y = 0; y < bi.rows.length; y++) {
      final row = bi.rows[y];
      for (var x = 0; x < row.length; x++) {
        var ch = row[x];
        if (ch == '.') continue;
        if (ch == 'e') {
          if (blink && y == firstEye) ch = 'p';
          if (mood == CatMood.happy && y > firstEye) ch = 'p';
        }
        paint.color = bi.colors[ch] ?? Colors.transparent;
        canvas.drawRect(Rect.fromLTWH(x * s, y * s, s + 0.6, s + 0.6), paint);
      }
    }

    if (mood == CatMood.happy && !blink) {
      final dark = Paint()
        ..isAntiAlias = false
        ..color = const Color(0xFF14081F);
      canvas.drawRect(Rect.fromLTWH(3 * s, 5 * s, 4 * s, 2 * s + 0.6), dark);
      canvas.drawRect(Rect.fromLTWH(9 * s, 5 * s, 4 * s, 2 * s + 0.6), dark);
      canvas.drawRect(Rect.fromLTWH(7 * s, 5 * s, 2 * s + 0.6, s * 0.6), dark);
      final sh = (t * 0.5) % 1.0;
      final stripe = Paint()
        ..isAntiAlias = false
        ..color = Color.lerp(const Color(0xFF38E8FF), const Color(0xFFFF5FAE), sh)!.withOpacity(0.55);
      canvas.drawRect(Rect.fromLTWH(3 * s + sh * 3.2 * s, 5 * s, s * 0.7, 2 * s + 0.6), stripe);
      canvas.drawRect(Rect.fromLTWH(9 * s + sh * 3.2 * s, 5 * s, s * 0.7, 2 * s + 0.6), stripe);
      final gl = Paint()
        ..isAntiAlias = false
        ..color = Colors.white.withOpacity(0.85);
      canvas.drawRect(Rect.fromLTWH(3.5 * s, 5.2 * s, s * 0.7, s * 0.7), gl);
      canvas.drawRect(Rect.fromLTWH(9.5 * s, 5.2 * s, s * 0.7, s * 0.7), gl);
    }

    final bob = math.sin(t * 2 * math.pi * 1) * s * 0.35;
    final cp = Paint()..isAntiAlias = false;
    for (var y = 0; y < bi.acc.length; y++) {
      for (var x = 0; x < bi.acc[y].length; x++) {
        final ch = bi.acc[y][x];
        if (ch == '.') continue;
        cp.color = bi.accColors[ch] ?? Colors.transparent;
        canvas.drawRect(Rect.fromLTWH((bi.ax + x) * s, (y + bi.ay) * s + bob, s + 0.6, s + 0.6), cp);
      }
    }

    const cols = [Color(0xFFFFE066), Color(0xFFFFFFFF), Color(0xFF38E8FF), Color(0xFFFF9AD0)];
    final sp = Paint()..isAntiAlias = false;
    for (var i = 0; i < 12; i++) {
      final dir = i.isEven ? 1.0 : -1.0;
      final a = t * 2 * math.pi * 0.25 * dir + i * 2 * math.pi / 12;
      final rr = size.width * (0.66 + 0.12 * math.sin(t * 2 * math.pi * 1 + i));
      final px = cx + math.cos(a) * rr;
      final py = cy + math.sin(a) * rr * 0.8;
      final tw = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 2 + i * 1.7);
      sp.color = cols[i % 4].withOpacity(0.35 + 0.65 * tw);
      _plus(canvas, sp, px, py, s * (0.35 + 0.35 * tw));
    }
  }

  @override
  bool shouldRepaint(covariant _CatPainter old) => old.blink != blink || old.mood != mood || old.t != t || old.buddy != buddy;
}

// ───────────────────────── افکت‌های پس‌زمینه‌ی تور ─────────────────────────
class _Star {
  final double x, y, phase, size;
  final int k;
  final Color color;
  const _Star(this.x, this.y, this.phase, this.size, this.k, this.color);
}

class _Heart {
  final double x, phase, size;
  final int k;
  final Color color;
  const _Heart(this.x, this.phase, this.size, this.k, this.color);
}

const List<String> _kHeart = [
  '.xx.xx.',
  'xxxxxxx',
  'xxxxxxx',
  '.xxxxx.',
  '..xxx..',
  '...x...',
];

void _drawHeart(Canvas canvas, Paint paint, double x, double y, double c) {
  for (var r = 0; r < _kHeart.length; r++) {
    for (var q = 0; q < _kHeart[r].length; q++) {
      if (_kHeart[r][q] != 'x') continue;
      canvas.drawRect(Rect.fromLTWH(x + q * c, y + r * c, c, c), paint);
    }
  }
}

class _FxPainter extends CustomPainter {
  final double t;
  final List<_Star> stars;
  final List<_Heart> hearts;
  _FxPainter(this.t, this.stars, this.hearts);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (final s in stars) {
      final a = 0.15 + 0.85 * (0.5 + 0.5 * math.sin(2 * math.pi * (t * s.k + s.phase)));
      paint.color = s.color.withOpacity(a);
      final d = s.size;
      final px = (s.x * size.width / d).floorToDouble() * d;
      final py = (s.y * size.height / d).floorToDouble() * d;
      canvas.drawRect(Rect.fromLTWH(px, py, d, d), paint);
      if (d >= 4 && a > 0.75) {
        canvas.drawRect(Rect.fromLTWH(px - d, py, d, d), paint);
        canvas.drawRect(Rect.fromLTWH(px + d, py, d, d), paint);
        canvas.drawRect(Rect.fromLTWH(px, py - d, d, d), paint);
        canvas.drawRect(Rect.fromLTWH(px, py + d, d, d), paint);
      }
    }
    for (final h in hearts) {
      final p = (t * h.k + h.phase) % 1.0;
      final y = size.height * (1.05 - 1.15 * p);
      final x = h.x * size.width + math.sin(2 * math.pi * (p * 2 + h.phase)) * 14;
      final o = (math.sin(math.pi * p)).clamp(0.0, 1.0) * 0.85;
      paint.color = h.color.withOpacity(o);
      _drawHeart(canvas, paint, x, y, h.size);
    }
  }

  @override
  bool shouldRepaint(covariant _FxPainter old) => old.t != t;
}

// ───────────────────────── کنفتی پایان تور ─────────────────────────
class _Conf {
  final double x, phase, size;
  final int k;
  final bool heart;
  final Color color;
  const _Conf(this.x, this.phase, this.size, this.k, this.heart, this.color);
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  final List<_Conf> items;
  _ConfettiPainter(this.t, this.items);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (final c in items) {
      final p = (t * c.k + c.phase) % 1.0;
      final y = size.height * (-0.06 + 1.12 * p);
      final x = c.x * size.width + math.sin(2 * math.pi * (p * 2 + c.phase)) * 20;
      paint.color = c.color.withOpacity(0.95);
      if (c.heart) {
        _drawHeart(canvas, paint, x, y, c.size * 0.7);
      } else {
        canvas.drawRect(Rect.fromLTWH(x, y, c.size, c.size), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

// ───────────────────────── نورافکن (سوراخ نورانی دور هدف) ─────────────────────────
class _SpotPainter extends CustomPainter {
  final Rect? rect;
  final double t; // 0..1 روی ۸ ثانیه
  _SpotPainter(this.rect, this.t);

  static const _pink = Color(0xFFFF5FAE);
  static const _cols = [Color(0xFFFF5FAE), Color(0xFFFFFFFF), Color(0xFFFFE066)];

  Offset _pointAt(Rect r, double d) {
    final w = r.width, h = r.height;
    if (d < w) return Offset(r.left + d, r.top);
    d -= w;
    if (d < h) return Offset(r.right, r.top + d);
    d -= h;
    if (d < w) return Offset(r.right - d, r.bottom);
    d -= w;
    return Offset(r.left, r.bottom - d);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final dim = Paint()..color = const Color(0xD60E0524);
    final r0 = rect;
    if (r0 == null || r0.width < 6 || r0.height < 6) {
      canvas.drawRect(full, dim);
      return;
    }
    final r = r0.inflate(7);
    final hole = RRect.fromRectAndRadius(r, const Radius.circular(14));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(full)
      ..addRRect(hole);
    canvas.drawPath(path, dim);

    final pulse = 0.5 + 0.5 * math.sin(2 * math.pi * 8 * t);

    // درخشش نرم
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = _pink.withOpacity(0.22 + 0.28 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // مربع‌های پیکسلی متحرک دور قاب (مورچه‌ی در حال رژه)
    final per = 2 * (r.width + r.height);
    final n = math.max(8, (per / 13).floor());
    final pix = Paint()..isAntiAlias = false;
    final phase = (t * 8 * 3).floor();
    for (var k = 0; k < n; k++) {
      final p = _pointAt(r, per * k / n);
      pix.color = _cols[(k + phase) % 3];
      canvas.drawRect(Rect.fromCenter(center: p, width: 5, height: 5), pix);
    }

    // براکت‌های زرد گوشه‌ها
    final b = 8 + 3 * pulse;
    final br = Paint()
      ..isAntiAlias = false
      ..color = const Color(0xFFFFE066);
    void corner(double x, double y, double sx, double sy) {
      canvas.drawRect(Rect.fromLTWH(sx > 0 ? x : x - 18, sy > 0 ? y : y - 4, 18, 4), br);
      canvas.drawRect(Rect.fromLTWH(sx > 0 ? x : x - 4, sy > 0 ? y : y - 18, 4, 18), br);
    }

    corner(r.left - b, r.top - b, 1, 1);
    corner(r.right + b, r.top - b, -1, 1);
    corner(r.left - b, r.bottom + b, 1, -1);
    corner(r.right + b, r.bottom + b, -1, -1);

    // جرقه‌های پیکسلی مدار
    final sp = Paint()..isAntiAlias = false;
    for (var j = 0; j < 6; j++) {
      final ang = (t * 8 * 0.5 + j / 6) * 2 * math.pi;
      final cx = r.center.dx + math.cos(ang) * (r.width / 2 + 20);
      final cy = r.center.dy + math.sin(ang) * (r.height / 2 + 20);
      final tw = 0.5 + 0.5 * math.sin(2 * math.pi * (t * 8 * 2 + j * 0.37));
      final u = (2 + 2 * tw).roundToDouble() * 2;
      sp.color = _cols[j % 3].withOpacity(0.4 + 0.6 * tw);
      final px = (cx / 2).floorToDouble() * 2, py = (cy / 2).floorToDouble() * 2;
      canvas.drawRect(Rect.fromLTWH(px - u / 2, py - u / 2, u, u), sp);
      canvas.drawRect(Rect.fromLTWH(px - u * 1.5, py - u / 2, u, u), sp);
      canvas.drawRect(Rect.fromLTWH(px + u / 2, py - u / 2, u, u), sp);
      canvas.drawRect(Rect.fromLTWH(px - u / 2, py - u * 1.5, u, u), sp);
      canvas.drawRect(Rect.fromLTWH(px - u / 2, py + u / 2, u, u), sp);
    }
  }

  @override
  bool shouldRepaint(covariant _SpotPainter old) => old.t != t || old.rect != rect;
}

// ───────────────────────── انیمیشن سینمایی ورود ─────────────────────────
class _Warp {
  final double ang, speed, off;
  final Color color;
  const _Warp(this.ang, this.speed, this.off, this.color);
}

class _Burst {
  final double ang, speed, size;
  final Color color;
  const _Burst(this.ang, this.speed, this.size, this.color);
}

class _CinemaPainter extends CustomPainter {
  final double t; // 0..1
  final List<_Warp> warp;
  final List<_Burst> burst;
  _CinemaPainter(this.t, this.warp, this.burst);

  static const _ringCols = [Color(0xFFFF5FAE), Color(0xFFFFE066), Color(0xFF38E8FF)];

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.52);
    final maxR = size.longestSide * 0.75;
    final paint = Paint()..isAntiAlias = false;
    final fadeOut = ((t - 0.84) / 0.16).clamp(0.0, 1.0);

    // سفر ستاره‌ای
    for (final w in warp) {
      final p = (t * 1.7 * w.speed + w.off) % 1.0;
      final r = p * p * maxR;
      final a = (p * 2).clamp(0.0, 1.0) * (1 - fadeOut);
      final d = 2.0 + p * 6;
      for (var k = 0; k < 3; k++) {
        final rr = r * (1 - k * 0.07);
        final x = c.dx + math.cos(w.ang) * rr;
        final y = c.dy + math.sin(w.ang) * rr;
        paint.color = w.color.withOpacity((a * (1 - k * 0.3)).clamp(0.0, 1.0));
        final sq = d * (1 - k * 0.15);
        canvas.drawRect(Rect.fromLTWH((x / 3).floorToDouble() * 3, (y / 3).floorToDouble() * 3, sq, sq), paint);
      }
    }

    // حلقه‌های مربعی پیکسلی
    const starts = [0.24, 0.31, 0.38];
    for (var i = 0; i < 3; i++) {
      final u = (t - starts[i]) / 0.30;
      if (u <= 0 || u >= 1) continue;
      final rad = u * maxR * 0.6;
      canvas.drawRect(
        Rect.fromCenter(center: c, width: rad * 2, height: rad * 2),
        Paint()
          ..isAntiAlias = false
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = _ringCols[i].withOpacity(((1 - u) * 0.8 * (1 - fadeOut)).clamp(0.0, 1.0)),
      );
    }

    // انفجار قلب‌های پیکسلی
    const hs = 0.34;
    if (t > hs) {
      final u = ((t - hs) / 0.52).clamp(0.0, 1.0);
      for (final b in burst) {
        final dist = Curves.easeOutCubic.transform(u) * maxR * 0.7 * b.speed;
        final x = c.dx + math.cos(b.ang) * dist;
        final y = c.dy + math.sin(b.ang) * dist + u * u * 160;
        paint.color = b.color.withOpacity(((1 - u) * (1 - fadeOut)).clamp(0.0, 1.0));
        _drawHeart(canvas, paint, x - 3.5 * b.size, y - 3 * b.size, b.size);
      }
    }

    // خطوط اسکن رترو
    final sl = Path();
    for (double y = 0; y < size.height; y += 4) {
      sl.addRect(Rect.fromLTWH(0, y, size.width, 1.4));
    }
    canvas.drawPath(sl, Paint()..color = const Color(0x0DFFFFFF));

    // فلاش برخورد
    final fl = (1 - ((t - 0.24) / 0.10).abs()).clamp(0.0, 1.0) * 0.45;
    if (fl > 0) canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withOpacity(fl));
  }

  @override
  bool shouldRepaint(covariant _CinemaPainter old) => old.t != t;
}

// ───────────────────────── مراحل تور ─────────────────────────
class _TourStep {
  final String? target;
  final int tab; // 0 = خانه ، 3 = Firefox
  final String badge;
  final IconData icon;
  final String title;
  final String text;
  final CatMood mood;
  final bool finale;
  const _TourStep(this.target, this.tab, this.badge, this.icon, this.title, this.text, {this.mood = CatMood.idle, this.finale = false});
}

const List<_TourStep> _kSteps = [
  _TourStep(null, 0, '', Icons.favorite_rounded, 'سلام! من میمی‌ام', 'راهنمای NEXORA VPN هستم. یه دور کامل خونه و Firefox رو باهم می‌چرخیم؛ دونه‌دونه و به ترتیب!', mood: CatMood.happy),
  // ── خانه ──
  _TourStep('home.menu', 0, 'خانه', Icons.person_rounded, 'پروفایل', 'از این دکمه‌ی بالا سمت راست، اسمت رو می‌بینی و وارد تنظیمات میشی.'),
  _TourStep('home.premium', 0, 'خانه', Icons.workspace_premium_rounded, 'پریمیوم', 'این تاج طلایی نسخه‌ی پریمیومه؛ به‌زودی میاد!', mood: CatMood.happy),
  _TourStep('home.status', 0, 'خانه', Icons.wifi_tethering_rounded, 'وضعیت اتصال', 'این برچسب میگه آماده‌ی اتصالی، در حال اتصالی یا وصل شدی. سبز یعنی امن و وصل!'),
  _TourStep('home.features', 0, 'خانه', Icons.lock_rounded, 'ویژگی‌ها', 'رمزنگاری امن، سرعت بالا و بدون محدودیت؛ سه قدرت اصلی NEXORA.', mood: CatMood.happy),
  _TourStep('home.server', 0, 'خانه', Icons.storage_rounded, 'کارت کانفیگ و سرور', 'روی این کارت بزن تا کانفیگ یا لوکیشن مورد علاقه‌ات رو عوض کنی. کانفیگ نداری؟ لمسش کن تا دریافت بشه.'),
  _TourStep('home.connect', 0, 'خانه', Icons.power_settings_new_rounded, 'کره و سوئیچ اتصال', 'سوئیچ رو به راست بکش تا وصل بشی. همین! کره‌ی زمین هم موقع اتصال زنده میشه.', mood: CatMood.happy),
  _TourStep('home.state', 0, 'خانه', Icons.keyboard_double_arrow_left_rounded, 'وضعیت زنده', 'اینجا راهنما و وضعیت اتصال رو می‌بینی؛ بعد از وصل شدن سرعت و حجم مصرفی هم میاد.'),
  _TourStep('home.quality', 0, 'خانه', Icons.verified_user_rounded, 'بررسی اصالت آی‌پی', 'نمره‌ی سلامت و مشخصات آی‌پی‌ات رو تست می‌کنه؛ برای آمازون و جمینای خیلی به کار میاد.'),
  _TourStep('home.aws', 0, 'خانه', Icons.card_giftcard_rounded, 'دستیار ۱۰۰ دلار آمازون', 'آماده‌سازی خودکار و آدرس معتبر آمریکا برای ثبت‌نام بدون کارت. فقط لمسش کن!', mood: CatMood.happy),
  // ── گذار ──
  _TourStep(null, 3, 'Firefox', Icons.public_rounded, 'بریم سراغ Firefox!', 'خونه تموم شد. حالا با هم میریم بخش Firefox VPN؛ یه لحظه...', mood: CatMood.happy),
  // ── Firefox ──
  _TourStep('ff.options', 3, 'Firefox', Icons.tune_rounded, 'گزینه‌های Nexora', 'تنظیمات پیشرفته: پروکسی سیستم، رله، DNS، بکاپ و لاگ کامل.'),
  _TourStep('ff.refresh', 3, 'Firefox', Icons.refresh_rounded, 'بروزرسانی', 'اکانت‌ها و لوکیشن‌ها رو دوباره می‌گیره و آمار رو تازه می‌کنه.'),
  _TourStep('ff.hero', 3, 'Firefox', Icons.pets_rounded, 'Firefox Secure Connection', 'ورود Mozilla، انتخاب کشور و تست تأخیر؛ همه در یه بخش مستقل.', mood: CatMood.happy),
  _TourStep('ff.aws', 3, 'Firefox', Icons.card_giftcard_rounded, 'دستیار آمازون', 'همون دستیار ۱۰۰ دلاری، اینجا هم دم دستته.'),
  _TourStep('ff.ping', 3, 'Firefox', Icons.speed_rounded, 'تست پینگ', 'رادار، سریع‌ترین، میانگین و تعداد سرورهای پاسخ‌گو. پینگ زنده و رنگیه؛ سبز یعنی سریع!'),
  _TourStep('ff.accounts', 3, 'Firefox', Icons.person_rounded, 'اکانت‌های Mozilla', 'اکانت‌هات اینجاست. هر کدوم دکمه‌ی «انتخاب» داره؛ تیکش بزنی لوکیشن‌ها باز میشن و حجم باقی‌مونده هم دیده میشه.'),
  _TourStep('ff.signin', 3, 'Firefox', Icons.login_rounded, 'Sign In', 'اکانت داری؟ با ایمیل و پسورد وارد شو؛ کد امنیتی رو هم همین‌جا وارد می‌کنی.'),
  _TourStep('ff.signup', 3, 'Firefox', Icons.person_add_alt_1_rounded, 'Sign Up', 'اکانت نداری؟ از اینجا یه اکانت جدید بساز.'),
  _TourStep('ff.auto', 3, 'Firefox', Icons.autorenew_rounded, 'سوئیچ خودکار', 'روشنش کنی، وقتی حجم یه اکانت تموم بشه خودش میره سراغ اکانت بعدی. علامت «؟» توضیح کامل داره.', mood: CatMood.happy),
  _TourStep('ff.locations', 3, 'Firefox', Icons.location_on_rounded, 'لوکیشن‌ها', 'کشورها با پرچم و پینگ رنگی. روی هر کدوم بزنی وصل میشی؛ دوباره بزنی قطع میشه. (اول یه اکانت رو انتخاب کن)'),
  // ── پایان ──
  _TourStep(null, 0, '', Icons.rocket_launch_rounded, 'تموم شد!', 'حالا همه‌چیز رو بلدی. این راهنما فقط همین یک‌بار نمایش داده میشه. برو و امن بچرخ!', mood: CatMood.happy, finale: true),
];

/// [goTab] تب برنامه را عوض می‌کند (۰ = خانه ، ۳ = Firefox) تا تور بین دو بخش جابه‌جا شود.
Future<void> showNexoraIntro(BuildContext context, {required void Function(int tab) goTab, IntroAnim anim = IntroAnim.warp, Buddy buddy = Buddy.mimi}) async {
  await Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 500),
    reverseTransitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, __, ___) => _IntroPage(goTab: goTab, anim: anim, buddy: buddy),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

enum IntroAnim { warp, hearts, confetti, quick }

class _AnimInfo {
  final String title;
  final String desc;
  final IconData icon;
  final Color top;
  final Color bottom;
  const _AnimInfo(this.title, this.desc, this.icon, this.top, this.bottom);
}

const Map<IntroAnim, _AnimInfo> _kAnimInfo = {
  IntroAnim.warp: _AnimInfo('سفر ستاره‌ای', 'عبور از میان ستاره‌ها و انفجار قلب', Icons.auto_awesome_rounded, Color(0xFF14082F), Color(0xFF8E2A74)),
  IntroAnim.hearts: _AnimInfo('بارش قلب', 'قلب‌ها و ستاره‌های شناور با میمی', Icons.favorite_rounded, Color(0xFF2A0B33), Color(0xFFD6307F)),
  IntroAnim.confetti: _AnimInfo('جشن و کانفتی', 'رنگارنگ و شاد، مثل یک جشن', Icons.celebration_rounded, Color(0xFF0B1F4A), Color(0xFF7A3DD8)),
  IntroAnim.quick: _AnimInfo('سریع و ساده', 'بدون انیمیشن ورود، مستقیم به راهنما', Icons.bolt_rounded, Color(0xFF1B1030), Color(0xFF4A2A7A)),
};

class IntroChoice {
  final IntroAnim anim;
  final Buddy buddy;
  const IntroChoice(this.anim, this.buddy);
}

Future<IntroChoice?> showIntroPicker(BuildContext context, {bool first = false}) {
  var buddy = Buddy.mimi;
  return showModalBottomSheet<IntroChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: !first,
    enableDrag: !first,
    builder: (ctx) => PopScope(
      canPop: !first,
      child: Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setS) => SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF5A2250), width: 3),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('راهنما', style: TextStyle(color: Color(0xFF5A2250), fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(first ? 'خوش اومدی! راهنمات رو انتخاب کن تا آموزش شروع بشه.' : 'راهنمات رو انتخاب کن.', style: const TextStyle(color: Color(0xFF8C3A78), fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(children: [
                  for (final b in Buddy.values)
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setS(() => buddy = b);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: b == buddy ? const Color(0xFFFFE066) : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF5A2250), width: b == buddy ? 3 : 2),
                          ),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            PixelCat(buddy: b, width: 54, mood: b == buddy ? CatMood.happy : CatMood.idle, t: 0),
                            const SizedBox(height: 4),
                            Text(_kBuddies[b]!.name, style: const TextStyle(color: Color(0xFF5A2250), fontSize: 13, fontWeight: FontWeight.w900)),
                            Text(_kBuddies[b]!.kind, style: const TextStyle(color: Color(0xFF8C3A78), fontSize: 10.5, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 14),
                _PickCard(
                  info: const _AnimInfo('شروع راهنما', 'با همین راهنما قدم‌به‌قدم برنامه را یاد بگیر', Icons.play_arrow_rounded, Color(0xFF1B1030), Color(0xFF4A2A7A)),
                  onTap: () => Navigator.of(ctx).pop(IntroChoice(IntroAnim.quick, buddy)),
                ),
                if (first)
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('بعداً', style: TextStyle(color: Color(0xFF8C3A78), fontWeight: FontWeight.w800)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    ),
    ),
  );
}

class _PickCard extends StatelessWidget {
  final _AnimInfo info;
  final VoidCallback onTap;
  const _PickCard({required this.info, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [info.top, info.bottom]),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF5A2250), width: 3),
            boxShadow: const [BoxShadow(color: Color(0xFF5A2250), offset: Offset(4, 4))],
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: const Color(0xFFFF5FAE), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF5A2250), width: 2)),
              child: Icon(info.icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(info.title, style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(info.desc, style: const TextStyle(color: Color(0xFFFFD6EC), fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
            const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 26),
          ]),
        ),
      ),
    );
  }
}

enum _Ph { cinema, tour }

class _IntroPage extends StatefulWidget {
  final void Function(int tab) goTab;
  final IntroAnim anim;
  final Buddy buddy;
  const _IntroPage({required this.goTab, this.anim = IntroAnim.warp, this.buddy = Buddy.mimi});

  @override
  State<_IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<_IntroPage> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  late final AnimationController _cinema = AnimationController(vsync: this, duration: const Duration(milliseconds: 4600));
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 520), value: 1);
  late final AnimationController _catIn = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  static const _pink = Color(0xFFFF5FAE);
  static const _ink = Color(0xFF5A2250);

  late final List<_Star> _stars;
  late final List<_Heart> _hearts;
  late final List<_Warp> _warp;
  late final List<_Burst> _burst;
  late final List<_Conf> _conf;

  late final List<_TourStep> _steps = _kSteps
      .map((t) => _TourStep(t.target, t.tab, t.badge, t.icon, t.title.replaceAll('میمی', _kBuddies[widget.buddy]!.name), t.text.replaceAll('میمی', _kBuddies[widget.buddy]!.name), mood: t.mood, finale: t.finale))
      .toList();

  _Ph _ph = _Ph.cinema;
  bool _cinemaOn = true;
  bool _hit = false;
  bool _closing = false;
  bool _busy = false;
  int _i = 0;
  int _tab = 0;
  int _typed = 0;
  bool _blink = false;
  Rect? _from;
  Rect? _to;
  Timer? _typeT;
  Timer? _blinkT;
  Timer? _remeasureT;
  Timer? _autoT;

  Rect? get _rect {
    if (_from == null && _to == null) return null;
    final t = Curves.easeOutCubic.transform(_move.value);
    final a = _from ?? Rect.fromCenter(center: _to!.center, width: 0, height: 0);
    final b = _to ?? Rect.fromCenter(center: _from!.center, width: 0, height: 0);
    return Rect.lerp(a, b, t);
  }

  @override
  void initState() {
    super.initState();
    final r = math.Random(11);
    const sc = [Color(0xFFFFFFFF), Color(0xFFFFE066), Color(0xFFFFB3DA), Color(0xFFB8E8FF)];
    _stars = List.generate(36, (i) => _Star(r.nextDouble(), r.nextDouble(), r.nextDouble(), r.nextBool() ? 3.0 : 4.0 + r.nextInt(2) * 2, 1 + r.nextInt(3), sc[r.nextInt(sc.length)]));
    const hc = [Color(0xFFFF5FAE), Color(0xFFFF9AD0), Color(0xFFFFC2E0), Color(0xFFFF7BC0)];
    _hearts = List.generate(9, (i) => _Heart(0.04 + r.nextDouble() * 0.9, r.nextDouble(), 3.0 + r.nextInt(3), 1 + r.nextInt(2), hc[r.nextInt(hc.length)]));
    final wc = [...sc, const Color(0xFFFF5FAE), const Color(0xFF38E8FF)];
    _warp = List.generate(110, (i) => _Warp(r.nextDouble() * 2 * math.pi, 0.6 + r.nextDouble() * 0.9, r.nextDouble(), wc[r.nextInt(wc.length)]));
    _burst = List.generate(26, (i) => _Burst(r.nextDouble() * 2 * math.pi, 0.35 + r.nextDouble() * 0.75, 3.0 + r.nextInt(3), hc[r.nextInt(hc.length)]));
    final cc = [...hc, const Color(0xFFFFE066), const Color(0xFF38E8FF), const Color(0xFFFFFFFF)];
    _conf = List.generate(64, (i) => _Conf(r.nextDouble(), r.nextDouble(), 4.0 + r.nextInt(4), 3 + r.nextInt(4), r.nextInt(3) == 0, cc[r.nextInt(cc.length)]));

    _cinema.addListener(() {
      if (!_hit && _cinema.value >= 0.24) {
        _hit = true;
        HapticFeedback.mediumImpact();
      }
    });
    if (widget.anim == IntroAnim.quick) {
      _cinemaOn = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _beginTour());
    } else {
      _cinema.forward().then((_) => _beginTour());
    }

    _blinkT = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (!mounted) return;
      setState(() => _blink = true);
      Future<void>.delayed(const Duration(milliseconds: 170), () {
        if (mounted) setState(() => _blink = false);
      });
    });
  }

  @override
  void dispose() {
    // هر نوع خروج (Skip / شروع / برگشت) یعنی راهنما دیده شد؛ دیگر نمایش داده نمی‌شود
    unawaited(Store.setIntroSeen());
    _typeT?.cancel();
    _blinkT?.cancel();
    _remeasureT?.cancel();
    _autoT?.cancel();
    _loop.dispose();
    _cinema.dispose();
    _move.dispose();
    _catIn.dispose();
    _fade.dispose();
    super.dispose();
  }

  // ───────────── کنترل تور ─────────────
  void _beginTour() {
    if (!mounted || _ph == _Ph.tour || _closing) return;
    setState(() => _ph = _Ph.tour);
    _fade.forward().then((_) {
      if (mounted) setState(() => _cinemaOn = false);
    });
    _catIn.forward(from: 0);
    _go(0);
  }

  Rect _fit(Rect r, Size size) {
    var x = r.intersect(Offset.zero & size);
    if (x.isEmpty) x = r;
    final maxH = size.height * 0.42;
    if (x.height > maxH) x = Rect.fromLTWH(x.left, x.top, x.width, maxH);
    return x;
  }

  Future<void> _scrollTo(String id) async {
    final ctx = Tour._keys[id]?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    try {
      await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic, alignment: 0.16);
    } catch (_) {}
  }

  Future<void> _go(int i, {int dir = 1}) async {
    if (!mounted || _busy || _closing) return;
    if (i >= _steps.length) return _finish();
    if (i < 0) i = 0;
    _busy = true;
    _autoT?.cancel();
    _remeasureT?.cancel();
    final st = _steps[i];
    var typedAlready = false;
    if (st.tab != _tab) {
      // کارت بدون سوراخ نشان داده می‌شود تا صفحه‌ی بعدی بالا بیاید
      _typeT?.cancel();
      setState(() {
        _from = _rect;
        _to = null;
        _i = i;
        _typed = 0;
      });
      _move.forward(from: 0);
      _startTyping();
      typedAlready = true;
      _tab = st.tab;
      widget.goTab(st.tab);
      await Future<void>.delayed(Duration(milliseconds: st.tab == 0 ? 650 : 1000));
      if (!mounted) return;
    }
    Rect? target;
    if (st.target != null) {
      await _scrollTo(st.target!);
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final raw = Tour.rectOf(st.target!);
      if (raw == null || raw.isEmpty) {
        // این بخش روی این دستگاه وجود ندارد؛ بی‌صدا رد می‌شویم
        _busy = false;
        return _go(i + dir, dir: dir);
      }
      target = _fit(raw, MediaQuery.sizeOf(context));
    }
    final keepText = typedAlready && target == null;
    setState(() {
      _from = _rect;
      _to = target;
      _i = i;
      if (!keepText) _typed = 0;
    });
    _move.forward(from: 0);
    if (!keepText) _startTyping();
    _busy = false;
    _armAuto();
    if (target != null) {
      _remeasureT = Timer(const Duration(milliseconds: 700), () {
        if (!mounted || _i != i || _to == null) return;
        final raw = Tour.rectOf(st.target!);
        if (raw == null) return;
        final r = _fit(raw, MediaQuery.sizeOf(context));
        if ((r.center - _to!.center).distance > 3 || (r.width - _to!.width).abs() > 3) {
          setState(() {
            _from = _rect;
            _to = r;
          });
          _move.forward(from: 0);
        }
      });
    }
  }

  void _armAuto() {
    _autoT?.cancel();
    if (!mounted || _closing || _ph != _Ph.tour || _i >= _steps.length - 1) return;
    final ms = _steps[_i].text.length > 90 ? 7000 : 5000;
    _autoT = Timer(Duration(milliseconds: ms), () {
      if (!mounted || _closing || _busy) return;
      if (_i >= _steps.length - 1) return;
      _go(_i + 1);
    });
  }

  void _startTyping() {
    _typeT?.cancel();
    _typed = 0;
    final total = _steps[_i].text.length;
    _typeT = Timer.periodic(const Duration(milliseconds: 24), (t) {
      if (!mounted || _typed >= total) {
        t.cancel();
        return;
      }
      setState(() => _typed++);
    });
  }

  void _revealText() {
    final total = _steps[_i].text.length;
    if (_typed < total) {
      _typeT?.cancel();
      setState(() => _typed = total);
    }
  }

  void _next() {
    if (_busy) return;
    HapticFeedback.selectionClick();
    final total = _steps[_i].text.length;
    if (_typed < total) return _revealText();
    if (_i >= _steps.length - 1) return _finish();
    _go(_i + 1);
  }

  void _prev() {
    if (_busy || _i == 0) return;
    HapticFeedback.selectionClick();
    _go(_i - 1, dir: -1);
  }

  void _finish() {
    if (_closing || !mounted) return;
    _closing = true;
    if (_tab != 0) widget.goTab(0);
    Navigator.of(context).pop();
  }

  // ───────────── اجزای ظاهری ─────────────
  Widget _pixelBtn(String label, Color bg, Color fg, VoidCallback onTap, {IconData? icon, bool small = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 14 : 22, vertical: small ? 8 : 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _ink, width: 3),
          boxShadow: const [BoxShadow(color: _ink, offset: Offset(4, 4))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, color: fg, size: small ? 17 : 20), const SizedBox(width: 6)],
          Text(label, style: TextStyle(color: fg, fontSize: small ? 13 : 15, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ]),
      ),
    );
  }

  TextStyle _pxStyle(double size, Color c) => TextStyle(
        fontFamily: 'PressStart2P',
        fontFamilyFallback: const ['Vazirmatn'],
        fontSize: size,
        color: c,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
      );

  Widget _cinemaTitle(double t, double w) {
    const full = 'NEXORA';
    final n = ((t - 0.30) / 0.035).floor().clamp(0, 6);
    final cur = (n < 6 && (t * 40).floor().isEven) ? '_' : '';
    final shown = full.substring(0, n) + cur;
    final g = n < 6 ? 3.5 : 1.4 * (0.5 + 0.5 * math.sin(_loop.value * 2 * math.pi * 16));
    final fs = math.min(34.0, w / 9);
    Widget layer(Color c, double dx) => Transform.translate(
          offset: Offset(dx, 0),
          child: Text(shown, textDirection: TextDirection.ltr, style: _pxStyle(fs, c)),
        );
    return Stack(alignment: Alignment.center, children: [
      layer(const Color(0xFF38E8FF), -g),
      layer(const Color(0xFFFF4FA3), g),
      layer(Colors.white, 0),
    ]);
  }

  Widget _cinemaLayer(Size size) {
    return FadeTransition(
      opacity: ReverseAnimation(_fade),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _beginTour, // لمس = رد کردن فقط انیمیشن ورود
        child: AnimatedBuilder(
          animation: Listenable.merge([_cinema, _loop]),
          builder: (_, __) {
            final t = _cinema.value;
            final info = _kAnimInfo[widget.anim]!;
            final top = Color.lerp(const Color(0xFF05020F), info.top, (t * 2).clamp(0.0, 1.0))!;
            final bot = Color.lerp(info.top, info.bottom, (t * 1.4).clamp(0.0, 1.0))!;
            final drop = Curves.bounceOut.transform(const Interval(0.12, 0.45).transform(t));
            final bob = t > 0.45 ? math.sin(_loop.value * 2 * math.pi * 8) * 6 : 0.0;
            final catY = (1 - drop) * -size.height * 0.7 + bob;
            return Stack(children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bot]),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: widget.anim == IntroAnim.hearts
                      ? _FxPainter(_loop.value, _stars, _hearts)
                      : widget.anim == IntroAnim.confetti
                          ? _ConfettiPainter(_loop.value, _conf)
                          : _CinemaPainter(t, _warp, _burst),
                ),
              ),
              Positioned(
                top: size.height * 0.17,
                left: 0,
                right: 0,
                child: Center(child: _cinemaTitle(t, size.width)),
              ),
              Positioned(
                top: size.height * 0.36,
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.translate(
                    offset: Offset(0, catY),
                    child: PixelCat(buddy: widget.buddy, width: math.min(size.width * 0.5, 210), blink: _blink, mood: t > 0.5 ? CatMood.happy : CatMood.idle, t: _loop.value * 8),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _card(_TourStep st) {
    final n = _typed.clamp(0, st.text.length);
    final typedText = st.text.substring(0, n);
    final restText = st.text.substring(n);
    return GestureDetector(
      onTap: _revealText,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(a), child: child)),
        child: Container(
          key: ValueKey(_i),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _ink, width: 3),
            boxShadow: const [BoxShadow(color: _ink, offset: Offset(5, 5))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _pink,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _ink, width: 2),
                ),
                child: Icon(st.icon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 9),
              Expanded(child: Text(st.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 16.5, fontWeight: FontWeight.w900))),
              if (st.badge.isNotEmpty)
                Container(
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(4)),
                  child: Text(st.badge, style: const TextStyle(color: Color(0xFFFFE066), fontSize: 10.5, fontWeight: FontWeight.w900)),
                ),
              Text('${_i + 1}/${_steps.length}', style: const TextStyle(color: Color(0xFF8C3A78), fontWeight: FontWeight.w800, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(style: const TextStyle(color: Color(0xFF3A1650), fontSize: 13.5, height: 1.75, fontWeight: FontWeight.w600, fontFamily: 'Vazirmatn'), children: [
                TextSpan(text: typedText),
                TextSpan(text: restText, style: const TextStyle(color: Colors.transparent)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _cat(_TourStep st, bool big) {
    return AnimatedBuilder(
      animation: Listenable.merge([_loop, _catIn]),
      builder: (_, __) {
        final e = Curves.elasticOut.transform(_catIn.value.clamp(0.0, 1.0));
        final bob = math.sin(_loop.value * 2 * math.pi * 8) * (big ? 6 : 4);
        final tilt = big ? 0.0 : math.sin(_loop.value * 2 * math.pi * 4) * 0.06;
        return Transform.translate(
          offset: Offset(0, bob + (1 - e) * 120),
          child: Transform.rotate(
            angle: tilt,
            child: Transform.scale(scale: 0.4 + 0.6 * e, child: PixelCat(buddy: widget.buddy, width: big ? 190 : 96, blink: _blink, mood: st.mood, t: _loop.value * 8)),
          ),
        );
      },
    );
  }

  Widget _controls(bool last) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // نوار پیشرفت پیکسلی
      Container(
        height: 10,
        margin: const EdgeInsets.only(bottom: 12, top: 2),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: _ink, width: 2),
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: (_i + 1) / _steps.length,
            child: Container(decoration: BoxDecoration(color: _pink, borderRadius: BorderRadius.circular(1))),
          ),
        ),
      ),
      Row(children: [
        if (_i > 0) _pixelBtn('قبلی', Colors.white, _ink, _prev, icon: Icons.arrow_forward_rounded, small: true),
        const Spacer(),
        _pixelBtn(last ? 'شروع!' : 'بعدی', const Color(0xFFFFE066), _ink, _next, icon: last ? Icons.rocket_launch_rounded : Icons.arrow_back_rounded),
      ]),
    ]);
  }

  Widget _panel(_TourStep st, bool big, bool atBottom) {
    final last = _i == _steps.length - 1;
    final Widget body;
    if (big) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        _cat(st, true),
        const SizedBox(height: 6),
        Transform.translate(
          offset: const Offset(0, 4),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF1F8),
                border: Border(left: BorderSide(color: _ink, width: 3), top: BorderSide(color: _ink, width: 3)),
              ),
            ),
          ),
        ),
        _card(st),
      ]);
    } else {
      body = Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: _card(st)),
        const SizedBox(width: 8),
        _cat(st, false),
      ]);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        body,
        const SizedBox(height: 14),
        _controls(last),
      ]),
    );
  }

  Widget _tourLayer(Size size) {
    final st = _steps[_i];
    final big = st.target == null;
    final atBottom = _to == null ? true : _to!.center.dy < size.height * 0.56;
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _revealText,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_loop, _move]),
              builder: (_, __) => CustomPaint(painter: _SpotPainter(_rect, _loop.value)),
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _loop,
              builder: (_, __) => CustomPaint(painter: st.finale ? _ConfettiPainter(_loop.value, _conf) : _FxPainter(_loop.value, _stars, _hearts)),
            ),
          ),
        ),
      ),
      SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, atBottom ? 12 : 66, 20, 18),
          child: Align(
            alignment: atBottom ? Alignment.bottomCenter : Alignment.topCenter,
            child: _panel(st, big, atBottom),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          type: MaterialType.transparency,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _armAuto(),
            child: Stack(children: [
            if (_ph == _Ph.tour) Positioned.fill(child: FadeTransition(opacity: _fade, child: _tourLayer(size))),
            if (_cinemaOn) Positioned.fill(child: _cinemaLayer(size)),
            // Skip صورتی (بالا وسط؛ روی دکمه‌های گوشه‌ی صفحه نمی‌افتد)
            Positioned(
              top: safeTop + 8,
              left: 0,
              right: 0,
              child: Center(child: _pixelBtn('Skip', _pink, Colors.white, _finish, small: true)),
            ),
          ]),
          ),
        ),
      ),
    );
  }
}
