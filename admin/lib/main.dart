import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'backend.dart';

const Color bg = Color(0xFF050A1A);
const Color card = Color(0xFF0B1534);
const Color border = Color(0xFF1F3F82);
const Color accent = Color(0xFF3B82FF);
const Color accent2 = Color(0xFF38C8FF);
const Color sub = Color(0xFF8FA3C4);
const Color neonViolet = Color(0xFF9B6BFF);
const Color neonGreen = Color(0xFF2BF0A5);
const Color neonPink = Color(0xFFFF4D9D);
const Color neonAmber = Color(0xFFFFC043);
const Color neonOrange = Color(0xFFFF8A3D);
const Color neonRed = Color(0xFFFF5470);

late SharedPreferences prefs;

final ValueNotifier<int> dbState = ValueNotifier<int>(0);
final ValueNotifier<int> dbEpoch = ValueNotifier<int>(0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  dbState.value = prefs.getInt('sb_state') ?? 0;
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final btnShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NEXORA Admin',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Vazirmatn',
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 50),
            shape: btnShape,
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFD7E6FF),
            minimumSize: const Size(0, 48),
            shape: btnShape,
            side: BorderSide(color: accent.withOpacity(0.45)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(shape: btnShape, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF14254F),
          contentTextStyle: const TextStyle(color: Colors.white, fontFamily: 'Vazirmatn', height: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Gate(),
    );
  }
}

class Gate extends StatelessWidget {
  const Gate({super.key});

  Client _make() {
    final b = (prefs.getString('sb_url') ?? '').trim();
    return Client(b.isEmpty ? kSbUrl : b, (prefs.getString('sb_key') ?? '').trim());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: dbEpoch,
      builder: (context, _, __) => Dashboard(client: _make()),
    );
  }
}

String fmtBytes(num b) {
  if (b < 1024) return '${b.toInt()} B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String fmtDur(num s) {
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return '$h ساعت $m دقیقه';
}

String ago(int t) {
  final d = DateTime.now().millisecondsSinceEpoch - t;
  if (d < 60000) return 'همین الان';
  if (d < 3600000) return '${d ~/ 60000} دقیقه پیش';
  if (d < 86400000) return '${d ~/ 3600000} ساعت پیش';
  return '${d ~/ 86400000} روز پیش';
}

String flagOf(String code) {
  if (code.length != 2) return '🌐';
  final a = code.toUpperCase().codeUnits;
  return String.fromCharCodes([0x1F1E6 + a[0] - 65, 0x1F1E6 + a[1] - 65]);
}

String _shortId(String id) => id.length > 10 ? id.substring(0, 10) : id;

String _dateOf(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
}

// ───────────────────────── اجزای مشترک طراحی ─────────────────────────

InputDecoration inputDeco(String? label, {String? hint, Widget? suffix, IconData? icon}) {
  OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffix,
    prefixIcon: icon == null ? null : Icon(icon, size: 20, color: sub),
    filled: true,
    fillColor: const Color(0xFF081029),
    labelStyle: const TextStyle(color: sub, fontSize: 13),
    hintStyle: TextStyle(color: sub.withOpacity(0.5), fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    enabledBorder: b(border.withOpacity(0.55)),
    focusedBorder: b(accent2, 1.6),
    border: b(border.withOpacity(0.55)),
  );
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Color? glow;
  final VoidCallback? onTap;
  final double radius;
  final double opacity;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.glow,
    this.onTap,
    this.radius = 22,
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    final g = glow ?? accent;
    final strong = glow != null;
    return Opacity(
      opacity: opacity,
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xEB132252), Color(0xEB0A1331)],
          ),
          border: Border.all(color: g.withOpacity(strong ? 0.5 : 0.22)),
          boxShadow: [BoxShadow(color: g.withOpacity(strong ? 0.20 : 0.07), blurRadius: 24, spreadRadius: -6, offset: const Offset(0, 10))],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      ),
    );
  }
}

class Reveal extends StatelessWidget {
  final Widget child;
  final int index;
  const Reveal({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    final i = index > 8 ? 8 : index;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + i * 70),
      curve: Curves.easeOutCubic,
      builder: (c, v, ch) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 20), child: ch)),
      child: child,
    );
  }
}

class CountUp extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final String Function(num)? fmt;
  const CountUp(this.value, {super.key, this.style, this.fmt});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (c, v, _) => Text(fmt != null ? fmt!(v) : v.round().toString(), style: style),
    );
  }
}

class IconBubble extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBubble(this.icon, this.color, {super.key, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.34),
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [color.withOpacity(0.38), color.withOpacity(0.10)]),
        border: Border.all(color: color.withOpacity(0.55)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.28), blurRadius: 14, spreadRadius: -3)],
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool ltr;
  const Pill(this.text, this.color, {super.key, this.icon, this.ltr = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(30), border: Border.all(color: color.withOpacity(0.45))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
        Flexible(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: ltr ? TextDirection.ltr : null, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  final String? hint;
  const SectionHeader(this.title, this.icon, this.color, {super.key, this.trailing, this.hint});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      IconBubble(icon, color, size: 34),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint!, style: const TextStyle(color: sub, fontSize: 11, height: 1.5))),
        ]),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool active;
  const PulseDot({super.key, required this.color, this.size = 10, this.active = true});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.4,
      height: s * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (c, _) => Stack(alignment: Alignment.center, children: [
          if (widget.active)
            Container(
              width: s * (1 + _c.value * 1.4),
              height: s * (1 + _c.value * 1.4),
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withOpacity((1 - _c.value) * 0.35)),
            ),
          Container(
            width: s,
            height: s,
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color, boxShadow: widget.active ? [BoxShadow(color: widget.color.withOpacity(0.7), blurRadius: 8)] : null),
          ),
        ]),
      ),
    );
  }
}

class NeonToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;
  const NeonToggle({super.key, required this.value, required this.onChanged, this.color = neonGreen});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerLeft : Alignment.centerRight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: value ? color.withOpacity(0.25) : const Color(0xFF16254B),
          border: Border.all(color: value ? color : border.withOpacity(0.6)),
          boxShadow: value ? [BoxShadow(color: color.withOpacity(0.35), blurRadius: 12, spreadRadius: -2)] : null,
        ),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, color: value ? color : sub),
        ),
      ),
    );
  }
}

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key});

  Widget _orb(Color c, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c.withOpacity(0.30), c.withOpacity(0.0)])),
      );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF07112E), bg, Color(0xFF040817)]),
          ),
        ),
        Positioned(top: -140, right: -120, child: _orb(accent, 420)),
        Positioned(top: 260, left: -190, child: _orb(neonViolet, 380)),
        Positioned(bottom: -150, right: -100, child: _orb(accent2, 360)),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac, this.color);
  final double frac;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 9;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..color = Colors.white.withOpacity(0.07),
    );
    final sweep = 6.2831853 * frac.clamp(0.0, 1.0);
    if (sweep <= 0) return;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..color = color.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawArc(rect, -1.5707963, sweep, false, glow);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(startAngle: 0.0, endAngle: 6.2831853, colors: [color.withOpacity(0.55), color], transform: const GradientRotation(-1.5707963)).createShader(rect);
    canvas.drawArc(rect, -1.5707963, sweep, false, p);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.frac != frac || old.color != color;
}

class Dashboard extends StatefulWidget {
  final Client client;
  const Dashboard({super.key, required this.client});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int _tab = 0;
  Map<String, dynamic> _stats = {};
  List<dynamic> _users = [];
  List<dynamic> _configs = [];
  String _err = '';
  Timer? _timer;
  Timer? _liveTimer;
  int _gen = 0;
  int _applied = 0;
  final Set<String> _deleted = {};
  bool _refreshing = false;
  bool _seedTried = false;
  String _seedErr = '';
  bool _snapBusy = false;
  bool _liveBusy = false;
  Map<String, int> _live = {};
  final Set<String> _locTried = {};
  final TextEditingController _usearch = TextEditingController();
  final TextEditingController _csearch = TextEditingController();
  String _uq = '';
  String _cq = '';
  int _uf = 0;
  int _cf = 0;

  bool get _dbOk => widget.client.ready && dbState.value == 1;

  @override
  void initState() {
    super.initState();
    if (!_dbOk) _tab = 3;
    dbState.addListener(_onDb);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
    _liveTimer = Timer.periodic(const Duration(seconds: 3), (_) => _liveTick());
    _liveTick();
  }

  void _onDb() {
    if (!mounted) return;
    setState(() {
      if (_dbOk && _tab == 3 && _stats.isEmpty) _tab = 0;
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant Dashboard old) {
    super.didUpdateWidget(old);
    _load();
  }

  @override
  void dispose() {
    dbState.removeListener(_onDb);
    _timer?.cancel();
    _liveTimer?.cancel();
    _usearch.dispose();
    _csearch.dispose();
    super.dispose();
  }

  // هر بار فراخوانی (مخصوصاً دکمه‌ی رفلش) یک اتصال تازه می‌سازد و دوباره می‌گیرد؛ قفل ندارد
  Future<void> _load({bool manual = false}) async {
    if (!_dbOk) return;
    final g = ++_gen;
    if (manual) {
      _seedTried = false;
      _seedErr = '';
      if (mounted) setState(() => _refreshing = true);
    }
    try {
      await _prepare();
      final r = await Future.wait([
        widget.client.call('GET', '/api/admin/stats'),
        widget.client.call('GET', '/api/admin/users'),
        widget.client.call('GET', '/api/admin/configs'),
      ]);
      if (!mounted || g < _applied) return;
      _applied = g;
      setState(() {
        _stats = (r[0] as Map).cast<String, dynamic>();
        _users = r[1] as List;
        final srv = r[2] as List;
        _deleted.removeWhere((id) => !srv.any((e) => '${(e as Map)['id']}' == id));
        _configs = srv.where((e) => !_deleted.contains('${(e as Map)['id']}')).toList();
        _err = '';
      });
      _afterLoad();
      if (manual) _liveTick(force: true);
    } catch (e) {
      if (mounted && g >= _applied) setState(() => _err = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (manual && mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _prepare() async {
    if (_seedTried || prefs.getBool('purged_defaults') == true) return;
    _seedTried = true;
    try {
      await widget.client.purgeDefaults();
      await prefs.setBool('purged_defaults', true);
      _seedErr = '';
    } catch (e) {
      _seedErr = '$e'.replaceFirst('Exception: ', '');
    }
  }

  void _afterLoad() {
    final miss = _configs.where((c) => '${(c as Map)['country'] ?? ''}'.isEmpty && !_locTried.contains('${c['id']}')).toList();
    if (miss.isNotEmpty) {
      for (final c in miss) {
        _locTried.add('${(c as Map)['id']}');
      }
      widget.client.fillMissingLocations(miss).then((_) {
        if (mounted) _load();
      }).catchError((_) {});
    }
    _autoBackup();
  }

  // بکاپ خودکار روزانه داخل خود دیتابیس (۱۰ نسخه‌ی آخر نگه داشته می‌شود)
  Future<void> _autoBackup() async {
    if (_snapBusy) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (prefs.getInt('auto_snap_at') ?? 0) < 86400000) return;
    _snapBusy = true;
    try {
      await widget.client.createSnapshot('auto');
      await prefs.setInt('auto_snap_at', now);
    } catch (_) {
      await prefs.setInt('auto_snap_at', now - 86400000 + 3600000);
    } finally {
      _snapBusy = false;
    }
  }

  // کاربران فعال / غیرفعال / کل — هر ۳ ثانیه
  Future<void> _liveTick({bool force = false}) async {
    if (!_dbOk || _liveBusy || (_tab != 0 && !force)) return;
    _liveBusy = true;
    try {
      final m = await widget.client.liveCounts();
      if (mounted && (m['online'] != _live['online'] || m['total'] != _live['total'])) setState(() => _live = m);
    } catch (_) {
    } finally {
      _liveBusy = false;
    }
  }

  String _cfgName(Map x) {
    final n = '${x['name'] ?? ''}'.trim();
    final isIp = RegExp(r'^[\d.:\[\]a-fA-F]+$').hasMatch(n) && n.contains(RegExp(r'[.:]'));
    if (n.isNotEmpty && !isIp) return n;
    final c = '${x['country'] ?? ''}'.trim();
    if (c.isNotEmpty) return '${flagOf('${x['code'] ?? ''}')} $c';
    return 'در حال تشخیص لوکیشن...';
  }

  // ───────────────────────── رابط جدید ─────────────────────────

  Widget _needDb() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GlassCard(
            glow: accent2,
            radius: 28,
            padding: const EdgeInsets.all(26),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const IconBubble(Icons.cloud_off_rounded, accent2, size: 68),
              const SizedBox(height: 16),
              const Text('اول دیتابیس را وصل کن', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('آمار، کاربران و کانفیگ‌ها بعد از وصل شدن به Supabase روشن می‌شوند.', textAlign: TextAlign.center, style: TextStyle(color: sub, height: 1.7)),
              const SizedBox(height: 18),
              FilledButton.icon(onPressed: () => setState(() => _tab = 3), icon: const Icon(Icons.cloud_queue_rounded), label: const Text('رفتن به تب دیتابیس')),
            ]),
          ),
        ),
      );

  Widget _hBtn(Widget child, VoidCallback onTap) => Material(
        color: Colors.white.withOpacity(0.06),
        shape: CircleBorder(side: BorderSide(color: accent.withOpacity(0.35))),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 42, height: 42, child: Center(child: child))),
      );

  Widget _header() {
    final ok = _dbOk;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [accent2, accent, neonViolet]),
            boxShadow: [BoxShadow(color: accent.withOpacity(0.55), blurRadius: 18, spreadRadius: -2)],
          ),
          child: const Icon(Icons.hub_rounded, color: Colors.white, size: 25),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('NEXORA Admin', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, letterSpacing: 0.4)),
            const SizedBox(height: 2),
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: ok ? neonGreen : neonRed, boxShadow: [BoxShadow(color: (ok ? neonGreen : neonRed).withOpacity(0.7), blurRadius: 6)])),
              const SizedBox(width: 6),
              Text(ok ? 'متصل به Supabase' : 'دیتابیس وصل نیست', style: const TextStyle(color: sub, fontSize: 11.5)),
            ]),
          ]),
        ),
        _hBtn(
          _refreshing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded, size: 22),
          () => _load(manual: true),
        ),
        const SizedBox(width: 8),
        _hBtn(const Icon(Icons.cloud_done_rounded, size: 21, color: accent2), () => setState(() => _tab = 3)),
      ]),
    );
  }

  Widget _navBar() {
    const icons = [Icons.insights_rounded, Icons.people_alt_rounded, Icons.dns_rounded, Icons.cloud_done_rounded];
    const labels = ['آمار', 'کاربران', 'کانفیگ‌ها', 'دیتابیس'];
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        height: 68,
        decoration: BoxDecoration(
          color: const Color(0xF20B1534),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: accent.withOpacity(0.32)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 26, offset: const Offset(0, 10)), BoxShadow(color: accent.withOpacity(0.10), blurRadius: 30, spreadRadius: -6)],
        ),
        child: Row(children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: _tab == i ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [accent.withOpacity(0.55), accent2.withOpacity(0.18)]) : null,
                    border: _tab == i ? Border.all(color: accent2.withOpacity(0.6)) : null,
                    boxShadow: _tab == i ? [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 14, spreadRadius: -3)] : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    AnimatedScale(scale: _tab == i ? 1.12 : 1, duration: const Duration(milliseconds: 260), child: Icon(icons[i], size: 22, color: _tab == i ? Colors.white : sub)),
                    const SizedBox(height: 2),
                    Text(labels[i], style: TextStyle(fontSize: 10.5, fontWeight: _tab == i ? FontWeight.w800 : FontWeight.w500, color: _tab == i ? Colors.white : sub)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _liveRow(String t, int v, IconData ic, Color col) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(width: 4, height: 28, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(4), boxShadow: [BoxShadow(color: col.withOpacity(0.6), blurRadius: 8)])),
          const SizedBox(width: 10),
          Icon(ic, size: 18, color: col),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(color: sub, fontSize: 12.5))),
          CountUp(v, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _heroLive(Map<String, dynamic> s) {
    final on = _live['online'] ?? (s['online'] as num).toInt();
    final total = _live['total'] ?? (s['totalUsers'] as num).toInt();
    final off = _live['inactive'] ?? (total - on);
    final frac = total == 0 ? 0.0 : on / total;
    return GlassCard(
      glow: neonGreen,
      radius: 28,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(children: [
        Row(children: [
          const PulseDot(color: neonGreen, size: 8),
          const SizedBox(width: 2),
          const Text('وضعیت زنده کاربران', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          const Spacer(),
          const Pill('هر ۳ ثانیه', neonGreen, icon: Icons.bolt_rounded),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
            width: 132,
            height: 132,
            child: Stack(alignment: Alignment.center, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: frac),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (c, v, _) => CustomPaint(size: const Size(132, 132), painter: _RingPainter(v, neonGreen)),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                CountUp(on, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, height: 1.1)),
                const Text('آنلاین', style: TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(children: [
              _liveRow('کاربران فعال', on, Icons.wifi_rounded, neonGreen),
              _liveRow('غیرفعال', off, Icons.wifi_off_rounded, neonOrange),
              _liveRow('کل کاربران', total, Icons.people_alt_rounded, accent2),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _tile(String t, Widget value, IconData ic, Color col) => GlassCard(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          IconBubble(ic, col, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: value),
              const SizedBox(height: 2),
              Text(t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: sub, fontSize: 11.5, height: 1.3)),
            ]),
          ),
        ]),
      );

  Widget _tileGrid(List<Widget> tiles) => GridView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 94),
        children: tiles,
      );

  Widget _numTile(String t, num v, IconData ic, Color col) => _tile(t, CountUp(v, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)), ic, col);
  Widget _txtTile(String t, String v, IconData ic, Color col) => _tile(t, Text(v, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), ic, col);

  Widget _firefoxStats(dynamic raw) {
    final ff = raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
    final total = (ff['total'] as num?)?.toInt() ?? 0;
    final active = (ff['active'] as num?)?.toInt() ?? 0;
    final inactive = (ff['inactive'] as num?)?.toInt() ?? (total - active);
    final accounts = (ff['accounts'] as List?) ?? const [];
    return GlassCard(
      glow: neonOrange,
      margin: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('اکانت‌های Firefox', Icons.local_fire_department_rounded, neonOrange),
        const SizedBox(height: 14),
        if (ff['available'] != true)
          const Text('جدول آمار Firefox هنوز ساخته نشده؛ از تب «دیتابیس» دوباره «کپی SQL» را در Supabase اجرا کن.', style: TextStyle(color: sub, fontSize: 12, height: 1.6))
        else ...[
          Row(children: [
            Expanded(child: _miniNum('کل اکانت‌ها', total, Icons.account_circle_rounded, neonOrange)),
            const SizedBox(width: 8),
            Expanded(child: _miniNum('فعال', active, Icons.check_circle_rounded, neonGreen)),
            const SizedBox(width: 8),
            Expanded(child: _miniNum('غیرفعال', inactive, Icons.pause_circle_rounded, neonAmber)),
          ]),
          const SizedBox(height: 12),
          if (accounts.isEmpty) const Text('هنوز اکانتی گزارش نشده است.', style: TextStyle(color: sub)),
          if (accounts.isNotEmpty)
            GridView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 104),
              children: [for (final a in accounts.take(60)) _firefoxRow(a as Map)],
            ),
          if (accounts.length > 60)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('و ${accounts.length - 60} اکانت دیگر…', style: const TextStyle(color: sub, fontSize: 12))),
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('حجم‌ها تقریبی‌اند و با هر به‌روزرسانی اپ کاربر تازه می‌شوند؛ ایمیل‌ها ماسک‌شده‌اند.', style: TextStyle(color: sub, fontSize: 11, height: 1.5)),
          ),
        ],
      ]),
    );
  }

  Widget _miniNum(String t, int v, IconData ic, Color c) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withOpacity(0.18), c.withOpacity(0.05)]),
          border: Border.all(color: c.withOpacity(0.45)),
        ),
        child: Column(children: [
          Icon(ic, color: c, size: 20),
          const SizedBox(height: 4),
          CountUp(v, style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(t, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: sub, fontSize: 11)),
        ]),
      );

  Widget _firefoxRow(Map a) {
    final unlimited = a['unlimited'] == true;
    final used = (a['used'] as num?) ?? 0;
    final limit = (a['limit'] as num?) ?? 0;
    final remaining = (a['remaining'] as num?) ?? 0;
    final active = a['active'] == true;
    final frac = (!unlimited && limit > 0) ? (used / limit).clamp(0.0, 1.0).toDouble() : null;
    final label = '${a['label']}'.isEmpty ? '—' : '${a['label']}';
    final c = active ? neonGreen : neonAmber;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF081029), borderRadius: BorderRadius.circular(18), border: Border.all(color: c.withOpacity(0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: c, boxShadow: [BoxShadow(color: c.withOpacity(0.7), blurRadius: 6)])),
          const SizedBox(width: 7),
          Expanded(child: Text(label, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
        ]),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: frac != null
              ? LinearProgressIndicator(value: frac, minHeight: 7, color: frac > 0.9 ? neonRed : accent2, backgroundColor: const Color(0xFF13234A))
              : Container(height: 7, decoration: BoxDecoration(gradient: LinearGradient(colors: [c.withOpacity(0.2), c]))),
        ),
        Text(
          unlimited ? 'نامحدود ∞' : (limit > 0 ? '${fmtBytes(remaining)} مانده از ${fmtBytes(limit)}' : 'نامشخص'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: sub, fontSize: 10.5, height: 1.35),
        ),
      ]),
    );
  }

  Widget _bars(String title, List<dynamic> items, {Color col = accent2, int limit = 6, IconData icon = Icons.bar_chart_rounded}) {
    final list = items.take(limit).toList();
    final maxV = list.isEmpty ? 1 : list.map((e) => e['value'] as num).reduce((a, b) => a > b ? a : b);
    return GlassCard(
      margin: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(title, icon, col),
        const SizedBox(height: 12),
        if (list.isEmpty) const Text('داده‌ای وجود ندارد', style: TextStyle(color: sub)),
        for (var i = 0; i < list.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: col.withOpacity(i == 0 ? 0.35 : 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text('${i + 1}', style: TextStyle(color: i == 0 ? Colors.white : col, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 84, child: Text('${list[i]['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: maxV == 0 ? 0.0 : ((list[i]['value'] as num) / maxV).toDouble()),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (c, v, _) => Container(
                    height: 12,
                    alignment: AlignmentDirectional.centerStart,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
                    child: FractionallySizedBox(
                      widthFactor: v.clamp(0.03, 1.0).toDouble(),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(colors: [col.withOpacity(0.45), col]),
                          boxShadow: [BoxShadow(color: col.withOpacity(0.45), blurRadius: 8, spreadRadius: -2)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 46, child: Text('${list[i]['value']}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
            ]),
          ),
      ]),
    );
  }

  Widget _statsTab() {
    final s = _stats;
    if (s.isEmpty) {
      return Center(
        child: _err.isEmpty
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: GlassCard(
                  glow: neonRed,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const IconBubble(Icons.error_outline_rounded, neonRed, size: 56),
                    const SizedBox(height: 12),
                    Text(_err, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFB3C0), height: 1.6)),
                    const SizedBox(height: 14),
                    FilledButton(onPressed: () => setState(() => _tab = 3), child: const Text('بررسی دیتابیس')),
                  ]),
                ),
              ),
      );
    }
    final parts = <Widget>[
      _heroLive(s),
      const SizedBox(height: 14),
      _todaySection(s['today']),
      _tileGrid([
        _numTile('تعداد اتصالات', s['connections'] as num, Icons.link_rounded, neonAmber),
        _numTile('فعال امروز', s['activeToday'] as num, Icons.today_rounded, neonPink),
        _numTile('کاربران جدید امروز', (s['newToday'] as num?) ?? 0, Icons.person_add_alt_1_rounded, neonOrange),
        _numTile('حداقل یک‌بار وصل شده', (s['everConnected'] as num?) ?? 0, Icons.verified_user_rounded, accent2),
        _txtTile('بهترین لوکیشن', (s['bestLocation'] as String).isEmpty ? '—' : '${s['bestLocation']}', Icons.public_rounded, const Color(0xFF6CC4FF)),
        _txtTile('پرکاربردترین پروتکل', (s['bestProtocol'] as String).isEmpty ? '—' : '${s['bestProtocol']}'.toUpperCase(), Icons.shield_rounded, neonGreen),
        _tile('کل آپلود', Text(fmtBytes(s['up'] as num), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), Icons.arrow_upward_rounded, neonGreen),
        _tile('کل دانلود', Text(fmtBytes(s['down'] as num), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), Icons.arrow_downward_rounded, accent),
      ]),
      _firefoxStats(s['firefox']),
      _bars('پروتکل‌ها', s['protocols'] as List, icon: Icons.shield_moon_rounded),
      _bars('ترنسپورت‌ها', s['transports'] as List, col: neonGreen, icon: Icons.swap_calls_rounded),
      _bars('لوکیشن‌ها', s['countries'] as List, col: neonAmber, icon: Icons.public_rounded),
      _bars('پلتفرم‌ها', s['platforms'] as List, col: neonPink, icon: Icons.devices_rounded),
      _bars('اتصالات ۷ روز اخیر', s['last7'] as List, col: accent, limit: 7, icon: Icons.calendar_view_week_rounded),
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Center(child: Pill('مجموع زمان اتصال: ${fmtDur(s['seconds'] as num)}', accent2, icon: Icons.timer_outlined)),
      ),
    ];
    return RefreshIndicator(
      onRefresh: () => _load(manual: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 120),
        children: [for (var i = 0; i < parts.length; i++) Reveal(index: i, child: parts[i])],
      ),
    );
  }

  Widget _todaySection(dynamic raw) {
    if (raw is! Map) return const SizedBox.shrink();
    final t = raw.cast<String, dynamic>();
    int n(String k) => (t[k] as num?)?.toInt() ?? 0;
    final hours = [for (final h in (t['hours'] as List? ?? const [])) h as Map];
    final days = [for (final d in (t['days'] as List? ?? const [])) d as Map];
    Widget chartCard(String title, String hint, IconData ic, Color col, Widget chart) => GlassCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(title, ic, col, hint: hint),
            const SizedBox(height: 14),
            SizedBox(height: 160, width: double.infinity, child: chart),
          ]),
        );
    final nowH = DateTime.now().toUtc().add(const Duration(hours: 3, minutes: 30)).hour;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 10, right: 2),
        child: Text('امروز', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
      ),
      _tileGrid([
        _numTile('کاربر امروز', n('activeToday'), Icons.today_rounded, neonPink),
        _numTile('کاربر جدید', n('newToday'), Icons.person_add_alt_1_rounded, neonOrange),
        _numTile('آنلاین الان', n('online'), Icons.wifi_rounded, neonGreen),
        _numTile('اتصال امروز', n('connectsToday'), Icons.link_rounded, neonAmber),
      ]),
      const SizedBox(height: 12),
      if (hours.isNotEmpty)
        chartCard(
          'کاربران امروز به تفکیک ساعت',
          'هر ستون = تعداد کاربران متمایزی که در آن ساعت (وقت تهران) آمده‌اند',
          Icons.access_time_filled_rounded,
          accent2,
          CustomPaint(
            painter: _BarChartPainter(
              values: [for (final h in hours) (h['users'] as num).toDouble()],
              labels: [for (final h in hours) '${h['h']}'],
              color: accent2,
              highlight: nowH,
            ),
          ),
        ),
      if (days.isNotEmpty)
        chartCard(
          'کاربران ۱۴ روز اخیر',
          'ستون آبی = کاربر فعال هر روز | خط سبز = کاربر جدید',
          Icons.stacked_line_chart_rounded,
          accent,
          CustomPaint(
            painter: _BarChartPainter(
              values: [for (final d in days) (d['active'] as num).toDouble()],
              labels: [for (final d in days) '${d['day']}'.substring(3)],
              color: accent,
              line: [for (final d in days) (d['new'] as num).toDouble()],
              lineColor: neonGreen,
              highlight: days.length - 1,
            ),
          ),
        ),
      if (t['fallback'] == true)
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('نمودارها نیاز به SQL جدید دارند: از تب «دیتابیس» کپی SQL را در Supabase اجرا کن.', style: TextStyle(color: neonAmber, fontSize: 12, height: 1.6)),
        ),
    ]);
  }

  // ───────────── کاربران (کارت‌های شبکه‌ای) ─────────────

  Widget _filterChip(String t, int n, bool sel, Color col, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: sel ? LinearGradient(colors: [col.withOpacity(0.45), col.withOpacity(0.16)]) : null,
            color: sel ? null : Colors.white.withOpacity(0.04),
            border: Border.all(color: col.withOpacity(sel ? 0.9 : 0.3)),
            boxShadow: sel ? [BoxShadow(color: col.withOpacity(0.3), blurRadius: 12, spreadRadius: -3)] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(t, style: TextStyle(color: sel ? Colors.white : sub, fontWeight: FontWeight.w700, fontSize: 12.5)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: col.withOpacity(0.25), borderRadius: BorderRadius.circular(10)),
              child: Text('$n', style: TextStyle(color: sel ? Colors.white : col, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      );

  Widget _searchField(TextEditingController c, String hint, ValueChanged<String> onChanged) => TextField(
        controller: c,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14),
        decoration: inputDeco(null, hint: hint, icon: Icons.search_rounded, suffix: c.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: sub),
                onPressed: () {
                  c.clear();
                  onChanged('');
                },
              )),
      );

  IconData _platIcon(String p) {
    final l = p.toLowerCase();
    if (l.contains('android')) return Icons.android_rounded;
    if (l.contains('ios') || l.contains('iphone') || l.contains('ipad')) return Icons.phone_iphone_rounded;
    if (l.contains('win')) return Icons.desktop_windows_rounded;
    if (l.contains('mac')) return Icons.laptop_mac_rounded;
    if (l.contains('linux')) return Icons.computer_rounded;
    return Icons.devices_rounded;
  }

  Color _platColor(String p) {
    final l = p.toLowerCase();
    if (l.contains('android')) return neonGreen;
    if (l.contains('ios') || l.contains('iphone') || l.contains('ipad')) return const Color(0xFFB8C4DC);
    if (l.contains('win')) return accent2;
    if (l.contains('mac')) return neonViolet;
    if (l.contains('linux')) return neonAmber;
    return accent;
  }

  List<Map> _filteredUsers() {
    final q = _uq.trim().toLowerCase();
    final out = <Map>[];
    for (final e in _users) {
      final u = e as Map;
      final on = u['online'] == true;
      if (_uf == 1 && !on) continue;
      if (_uf == 2 && on) continue;
      if (q.isNotEmpty) {
        final hay = '${u['id']} ${u['platform']} ${u['lastCountry']} ${u['lastProtocol']}'.toLowerCase();
        if (!hay.contains(q)) continue;
      }
      out.add(u);
    }
    return out;
  }

  Widget _miniStat(IconData ic, String text, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(color: col.withOpacity(0.10), borderRadius: BorderRadius.circular(12), border: Border.all(color: col.withOpacity(0.28))),
        child: Row(children: [
          Icon(ic, size: 14, color: col),
          const SizedBox(width: 4),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(text, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      );

  Widget _userCard(Map u) {
    final online = u['online'] == true;
    final plat = '${u['platform']}';
    final pc = _platColor(plat);
    final country = '${u['lastCountry']}';
    final proto = '${u['lastProtocol']}';
    final sc = online ? neonGreen : sub;
    return GlassCard(
      glow: online ? neonGreen : null,
      padding: const EdgeInsets.all(12),
      radius: 24,
      onTap: () => _userSheet(u),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [pc.withOpacity(0.45), pc.withOpacity(0.10)]),
                border: Border.all(color: pc.withOpacity(0.6)),
                boxShadow: [BoxShadow(color: pc.withOpacity(0.3), blurRadius: 12, spreadRadius: -2)],
              ),
              child: Icon(_platIcon(plat), color: pc, size: 25),
            ),
            Positioned(
              bottom: -1,
              right: -1,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(shape: BoxShape.circle, color: online ? neonGreen : const Color(0xFF55627D), border: Border.all(color: const Color(0xFF0A1331), width: 2.5), boxShadow: online ? [BoxShadow(color: neonGreen.withOpacity(0.8), blurRadius: 8)] : null),
              ),
            ),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_shortId('${u['id']}'), textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              const SizedBox(height: 3),
              Text(online ? 'آنلاین' : ago(u['lastSeen'] as int), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sc, fontSize: 11, fontWeight: online ? FontWeight.w800 : FontWeight.w500)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _miniStat(Icons.arrow_upward_rounded, fmtBytes(u['up'] as num), neonGreen)),
          const SizedBox(width: 6),
          Expanded(child: _miniStat(Icons.arrow_downward_rounded, fmtBytes(u['down'] as num), accent2)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _miniStat(Icons.link_rounded, '${u['connections']}', neonAmber)),
          const SizedBox(width: 6),
          Expanded(child: _miniStat(Icons.place_rounded, country.isEmpty ? '—' : country, neonPink)),
        ]),
        const Spacer(),
        Row(children: [
          Expanded(child: Pill(plat.isEmpty ? '—' : plat, pc)),
          const SizedBox(width: 6),
          Expanded(child: Pill(proto.isEmpty ? '—' : proto.toUpperCase(), neonViolet, ltr: true)),
        ]),
      ]),
    );
  }

  Widget _kv(String k, String v, {bool ltr = false, Color? col}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 104, child: Text(k, style: const TextStyle(color: sub, fontSize: 12.5))),
          Expanded(child: Text(v, textDirection: ltr ? TextDirection.ltr : null, textAlign: ltr ? TextAlign.left : null, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: col, height: 1.4))),
        ]),
      );

  void _userSheet(Map u) {
    final online = u['online'] == true;
    final plat = '${u['platform']}';
    final pc = _platColor(plat);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GlassCard(
            glow: online ? neonGreen : accent,
            radius: 28,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 14),
                Row(children: [
                  IconBubble(_platIcon(plat), pc, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(plat.isEmpty ? 'پلتفرم نامشخص' : plat, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? neonGreen : sub)),
                        const SizedBox(width: 6),
                        Text(online ? 'آنلاین' : 'آفلاین', style: TextStyle(color: online ? neonGreen : sub, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      ]),
                    ]),
                  ),
                ]),
                const SizedBox(height: 10),
                Divider(color: Colors.white.withOpacity(0.08)),
                _kv('شناسه', '${u['id']}', ltr: true),
                _kv('اولین بازدید', _dateOf((u['firstSeen'] as num?)?.toInt() ?? 0), ltr: true),
                _kv('آخرین بازدید', ago(u['lastSeen'] as int)),
                _kv('تعداد اتصال', '${u['connections']}'),
                _kv('مجموع زمان اتصال', fmtDur((u['seconds'] as num?) ?? 0)),
                _kv('آپلود', fmtBytes(u['up'] as num), ltr: true, col: neonGreen),
                _kv('دانلود', fmtBytes(u['down'] as num), ltr: true, col: accent2),
                _kv('آخرین پروتکل', '${u['lastProtocol']}'.isEmpty ? '—' : '${u['lastProtocol']}'.toUpperCase(), ltr: true),
                _kv('آخرین لوکیشن', '${u['lastCountry']}'.isEmpty ? '—' : '${u['lastCountry']}'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: '${u['id']}'));
                      Navigator.pop(c);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('شناسه‌ی کاربر کپی شد')));
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('کپی شناسه'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _usersTab() {
    if (_users.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          IconBubble(Icons.people_outline_rounded, accent2, size: 64),
          SizedBox(height: 14),
          Text('کاربری وجود ندارد', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          SizedBox(height: 6),
          Text('وقتی کاربری اپ را باز کند اینجا دیده می‌شود', style: TextStyle(color: sub, fontSize: 12.5)),
        ]),
      );
    }
    final list = _filteredUsers();
    final onN = _users.where((e) => (e as Map)['online'] == true).length;
    final w = MediaQuery.of(context).size.width;
    final cols = w >= 1000 ? 4 : (w >= 640 ? 3 : 2);
    return RefreshIndicator(
      onRefresh: () => _load(manual: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _searchField(_usearch, 'جستجوی شناسه، پلتفرم، لوکیشن...', (v) => setState(() => _uq = v)),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _filterChip('همه', _users.length, _uf == 0, accent2, () => setState(() => _uf = 0)),
                    const SizedBox(width: 8),
                    _filterChip('آنلاین', onN, _uf == 1, neonGreen, () => setState(() => _uf = 1)),
                    const SizedBox(width: 8),
                    _filterChip('آفلاین', _users.length - onN, _uf == 2, neonOrange, () => setState(() => _uf = 2)),
                  ]),
                ),
              ]),
            ),
          ),
          if (list.isEmpty)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: Text('نتیجه‌ای پیدا نشد', style: TextStyle(color: sub)))))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 212),
                delegate: SliverChildBuilderDelegate((c, i) => Reveal(index: i % 6, child: _userCard(list[i])), childCount: list.length),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  // ───────────── کانفیگ‌ها ─────────────

  Color _protoColor(String p) {
    final l = p.toLowerCase();
    if (l.contains('vless')) return accent2;
    if (l.contains('vmess')) return neonViolet;
    if (l.contains('trojan')) return neonPink;
    if (l == 'ss' || l.contains('shadow')) return neonAmber;
    if (l.contains('hy')) return neonGreen;
    return accent;
  }

  List<Map> _filteredConfigs() {
    final q = _cq.trim().toLowerCase();
    final out = <Map>[];
    for (final e in _configs) {
      final x = e as Map;
      final en = x['enabled'] != false;
      if (_cf == 1 && !en) continue;
      if (_cf == 2 && en) continue;
      if (q.isNotEmpty) {
        final hay = '${_cfgName(x)} ${x['country']} ${x['protocol']} ${x['transport']} ${x['security']}'.toLowerCase();
        if (!hay.contains(q)) continue;
      }
      out.add(x);
    }
    return out;
  }

  Widget _info(IconData ic, String k, String v, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.045), borderRadius: BorderRadius.circular(14), border: Border.all(color: col.withOpacity(0.2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ic, size: 13, color: col),
            const SizedBox(width: 4),
            Expanded(child: Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: sub, fontSize: 10.5))),
          ]),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
        ]),
      );

  Widget _act(IconData ic, String t, Color col, VoidCallback onTap) => Material(
        color: col.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 40,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: col.withOpacity(0.35))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(ic, size: 17, color: col),
              const SizedBox(width: 5),
              Text(t, style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 12)),
            ]),
          ),
        ),
      );

  Future<void> _toggleConfig(Map x, bool v) async {
    final old = x['enabled'] != false;
    setState(() => x['enabled'] = v);
    try {
      await widget.client.call('PUT', '/api/admin/configs/${x['id']}', body: {'enabled': v});
    } catch (e) {
      if (mounted) {
        setState(() => x['enabled'] = old);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
    _load();
  }

  Future<void> _deleteConfig(Map x) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF0C1736),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: BorderSide(color: neonRed.withOpacity(0.4))),
        title: const Row(children: [IconBubble(Icons.delete_forever_rounded, neonRed, size: 40), SizedBox(width: 12), Expanded(child: Text('حذف کانفیگ', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)))]),
        content: Text('«${_cfgName(x)}» برای همیشه حذف می‌شود.', style: const TextStyle(color: sub, height: 1.7)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: neonRed, minimumSize: const Size(100, 46)), onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    final id = '${x['id']}';
    _applied = ++_gen;
    _deleted.add(id);
    setState(() => _configs = _configs.where((e) => '${(e as Map)['id']}' != id).toList());
    try {
      await widget.client.call('DELETE', '/api/admin/configs/$id');
    } catch (e) {
      _deleted.remove(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حذف ناموفق بود: ${'$e'.replaceFirst('Exception: ', '')}')));
    }
    _load();
  }

  Widget _configCard(Map x) {
    final enabled = x['enabled'] != false;
    final users = (x['users'] as num?)?.toInt() ?? 0;
    final online = (x['online'] as num?)?.toInt() ?? 0;
    final proto = '${x['protocol'] ?? '${x['link']}'.split('://').first}'.toUpperCase();
    final tr = '${x['transport'] ?? ''}';
    final sec = '${x['security'] ?? ''}';
    final pc = _protoColor(proto);
    final code = '${x['code'] ?? ''}';
    final country = '${x['country'] ?? ''}';
    final quota = (x['quotaGb'] ?? 0);
    final exp = '${x['expires'] ?? ''}';
    return GlassCard(
      glow: enabled ? pc : null,
      opacity: enabled ? 1 : 0.62,
      radius: 26,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [pc.withOpacity(0.35), pc.withOpacity(0.08)]),
              border: Border.all(color: pc.withOpacity(0.5)),
            ),
            child: code.length == 2 ? Text(flagOf(code), style: const TextStyle(fontSize: 28)) : Icon(Icons.public_rounded, color: pc, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_cfgName(x), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              const SizedBox(height: 3),
              Text(country.isEmpty ? 'لوکیشن نامشخص' : country, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: sub, fontSize: 12)),
            ]),
          ),
          NeonToggle(value: enabled, color: pc, onChanged: (v) => _toggleConfig(x, v)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Pill(proto, pc, icon: Icons.shield_rounded, ltr: true),
          if (tr.isNotEmpty) Pill(tr.toUpperCase(), accent2, ltr: true),
          if (sec.isNotEmpty && sec != 'none') Pill(sec.toUpperCase(), neonViolet, ltr: true),
          if ('${x['source']}' == 'default') const Pill('پیش‌فرض', neonAmber, icon: Icons.star_rounded),
          if (!enabled) const Pill('غیرفعال', neonOrange, icon: Icons.pause_circle_rounded),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(flex: 5, child: _info(Icons.people_alt_rounded, 'کاربران', '$users  ($online آنلاین)', neonGreen)),
          const SizedBox(width: 6),
          Expanded(flex: 3, child: _info(Icons.data_usage_rounded, 'حجم', quota == 0 ? 'نامحدود' : '$quota گیگ', neonPink)),
          const SizedBox(width: 6),
          Expanded(flex: 4, child: _info(Icons.event_rounded, 'انقضا', exp.isEmpty ? 'بدون انقضا' : exp, neonAmber)),
        ]),
        if (users > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: (online / users).clamp(0.0, 1.0).toDouble(), minHeight: 5, color: neonGreen, backgroundColor: Colors.white.withOpacity(0.07)),
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _act(Icons.edit_rounded, 'ویرایش', accent2, () => _editConfig(x))),
          const SizedBox(width: 8),
          Expanded(
            child: _act(Icons.copy_rounded, 'کپی', neonGreen, () {
              Clipboard.setData(ClipboardData(text: '${x['link']}'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لینک کانفیگ کپی شد')));
            }),
          ),
          const SizedBox(width: 8),
          Expanded(child: _act(Icons.delete_outline_rounded, 'حذف', neonRed, () => _deleteConfig(x))),
        ]),
      ]),
    );
  }

  Widget _configsTab() {
    final w = MediaQuery.of(context).size.width;
    final cols = w >= 760 ? 2 : 1;
    final list = _filteredConfigs();
    final enN = _configs.where((e) => (e as Map)['enabled'] != false).length;
    final rows = <Widget>[];
    for (var i = 0; i < list.length; i += cols) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Reveal(
          index: (i ~/ cols) % 6,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var j = 0; j < cols; j++) ...[
              if (j > 0) const SizedBox(width: 10),
              Expanded(child: i + j < list.length ? _configCard(list[i + j]) : const SizedBox.shrink()),
            ],
          ]),
        ),
      ));
    }
    return Stack(children: [
      _configs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const IconBubble(Icons.dns_rounded, accent2, size: 64),
                  const SizedBox(height: 14),
                  const Text('کانفیگی ثبت نشده', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 6),
                  const Text('با دکمه‌ی پایین کانفیگ یا لینک ساب اضافه کن', style: TextStyle(color: sub, fontSize: 12.5)),
                  if (_seedErr.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(_seedErr, textAlign: TextAlign.center, style: const TextStyle(color: neonRed, fontSize: 12, height: 1.6)),
                  ],
                ]),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(manual: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 170),
                children: [
                  _searchField(_csearch, 'جستجوی نام، کشور، پروتکل...', (v) => setState(() => _cq = v)),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _filterChip('همه', _configs.length, _cf == 0, accent2, () => setState(() => _cf = 0)),
                      const SizedBox(width: 8),
                      _filterChip('فعال', enN, _cf == 1, neonGreen, () => setState(() => _cf = 1)),
                      const SizedBox(width: 8),
                      _filterChip('غیرفعال', _configs.length - enN, _cf == 2, neonOrange, () => setState(() => _cf = 2)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (list.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('نتیجه‌ای پیدا نشد', style: TextStyle(color: sub)))),
                  ...rows,
                ],
              ),
            ),
      Positioned(
        bottom: 96,
        left: 18,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(colors: [accent, accent2]),
            boxShadow: [BoxShadow(color: accent.withOpacity(0.6), blurRadius: 22, spreadRadius: -2, offset: const Offset(0, 6))],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(30),
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: _addConfig,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text('کانفیگ / ساب', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _dlgTitle(IconData ic, Color col, String t) => Row(children: [IconBubble(ic, col, size: 40), const SizedBox(width: 12), Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)))]);

  Future<void> _addConfig() async {
    final text = TextEditingController();
    final name = TextEditingController();
    final quota = TextEditingController();
    final exp = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF0C1736),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: BorderSide(color: accent.withOpacity(0.4))),
        title: _dlgTitle(Icons.add_link_rounded, accent2, 'افزودن کانفیگ / ساب'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'یک یا چند لینک کانفیگ (vless / vmess / trojan / ss) یا لینک ساب (http/https) را بچسبان؛ کانفیگ‌ها خودکار استخراج می‌شوند.',
              style: TextStyle(color: sub, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: text,
              maxLines: 6,
              minLines: 3,
              textDirection: TextDirection.ltr,
              decoration: inputDeco('کانفیگ‌ها یا لینک ساب'),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () async {
                  final d = await Clipboard.getData('text/plain');
                  if (d?.text != null) text.text = d!.text!;
                },
                icon: const Icon(Icons.paste_rounded, size: 18),
                label: const Text('چسباندن از کلیپ‌بورد'),
              ),
            ),
            const SizedBox(height: 4),
            TextField(controller: name, decoration: inputDeco('نام (اختیاری)', icon: Icons.label_outline_rounded)),
            const SizedBox(height: 10),
            TextField(controller: quota, keyboardType: TextInputType.number, decoration: inputDeco('حجم گیگ (اختیاری؛ از ساب خوانده می‌شود)', icon: Icons.data_usage_rounded)),
            const SizedBox(height: 10),
            TextField(controller: exp, decoration: inputDeco('تاریخ اعتبار (اختیاری)', icon: Icons.event_rounded)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('استخراج و ثبت')),
        ],
      ),
    );
    if (ok != true || text.text.trim().isEmpty) return;
    try {
      final r = await widget.client.call('POST', '/api/admin/import', body: {
        'text': text.text.trim(),
        'name': name.text.trim(),
        if (quota.text.trim().isNotEmpty) 'quotaGb': num.tryParse(quota.text.trim()),
        'expires': exp.text.trim(),
      }) as Map;
      await _load();
      if (!mounted) return;
      final added = r['added'] ?? 0;
      final parts = <String>['$added کانفیگ اضافه شد'];
      if ((r['duplicates'] ?? 0) > 0) parts.add('${r['duplicates']} تکراری');
      if ((r['unsupported'] ?? 0) > 0) parts.add('${r['unsupported']} پروتکل پشتیبانی‌نشده');
      if ((r['invalid'] ?? 0) > 0) parts.add('${r['invalid']} نامعتبر');
      if ((r['found'] ?? 0) == 0 && (r['unsupported'] ?? 0) == 0) parts.add('کانفیگی در متن پیدا نشد');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(parts.join(' • '))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _editConfig(Map x) async {
    final name = TextEditingController(text: '${x['name'] ?? ''}');
    final country = TextEditingController(text: '${x['country'] ?? ''}');
    final code = TextEditingController(text: '${x['code'] ?? ''}');
    final quota = TextEditingController(text: '${x['quotaGb'] ?? 0}');
    final exp = TextEditingController(text: '${x['expires'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF0C1736),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: BorderSide(color: accent.withOpacity(0.4))),
        title: _dlgTitle(Icons.edit_rounded, accent2, 'ویرایش کانفیگ'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 4),
            TextField(controller: name, decoration: inputDeco('نام', icon: Icons.label_outline_rounded)),
            const SizedBox(height: 10),
            TextField(controller: country, decoration: inputDeco('لوکیشن (نام کشور)', icon: Icons.place_rounded)),
            const SizedBox(height: 10),
            TextField(controller: code, textDirection: TextDirection.ltr, maxLength: 2, decoration: inputDeco('کد کشور (مثلا DE) برای پرچم', icon: Icons.flag_rounded).copyWith(counterText: '')),
            const SizedBox(height: 10),
            TextField(controller: quota, keyboardType: TextInputType.number, decoration: inputDeco('حجم گیگ (۰ = نامحدود)', icon: Icons.data_usage_rounded)),
            const SizedBox(height: 10),
            TextField(controller: exp, decoration: inputDeco('تاریخ اعتبار', icon: Icons.event_rounded)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.client.call('PUT', '/api/admin/configs/${x['id']}', body: {
        'name': name.text.trim(),
        'country': country.text.trim(),
        'code': code.text.trim().toUpperCase(),
        'quotaGb': num.tryParse(quota.text.trim()) ?? 0,
        'expires': exp.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: bg,
      body: Stack(children: [
        const Positioned.fill(child: AppBackdrop()),
        SafeArea(
          bottom: false,
          child: Column(children: [
            _header(),
            Expanded(
              child: IndexedStack(index: _tab, children: [_dbOk ? _statsTab() : _needDb(), _dbOk ? _usersTab() : _needDb(), _dbOk ? _configsTab() : _needDb(), const DbTab()]),
            ),
          ]),
        ),
      ]),
      bottomNavigationBar: _navBar(),
    );
  }
}

class DbTab extends StatefulWidget {
  const DbTab({super.key});

  @override
  State<DbTab> createState() => _DbTabState();
}

class _DbTabState extends State<DbTab> {
  final _url = TextEditingController(text: prefs.getString('sb_url') ?? '');
  final _key = TextEditingController(text: prefs.getString('sb_key') ?? '');
  final _anon = TextEditingController(text: prefs.getString('sb_anon') ?? '');
  final _ghToken = TextEditingController(text: prefs.getString('gh_token') ?? '');
  bool _ghBusy = false;
  String _ghMsg = '';
  bool _bk = false;
  String _bkMsg = '';
  List<Map<String, dynamic>> _snaps = [];
  bool _hide = true;
  bool _busy = false;
  int _state = prefs.getInt('sb_state') ?? 0;
  String _reason = prefs.getString('sb_reason') ?? '';
  String _log = prefs.getString('sb_log') ?? '';

  Timer? _autoT;

  @override
  void initState() {
    super.initState();
    _key.addListener(_scheduleAuto);
    _anon.addListener(_scheduleAuto);
    // هر بار که تب باز می‌شود فایل کلید هم تازه می‌شود (اگر پاک شده باشد دوباره ساخته می‌شود)
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAuto());
  }

  @override
  void dispose() {
    _autoT?.cancel();
    _key.removeListener(_scheduleAuto);
    _anon.removeListener(_scheduleAuto);
    super.dispose();
  }

  String _lastPub = '';

  // با هر تغییر کلید، بعد از ۲ ثانیه مکث، فایل کلید خودکار ساخته/جایگزین می‌شود
  void _scheduleAuto() {
    _autoT?.cancel();
    _autoT = Timer(const Duration(seconds: 2), _autoPublish);
  }

  Future<void> _autoPublish() async {
    final url = _norm(_url.text);
    final key = _key.text.trim();
    final anon = _anon.text.trim();
    if (key.length < 20 || anon.length < 20 || !url.startsWith('https://')) return;
    final sig = '$url|$key|$anon';
    if (sig == _lastPub) return;
    _lastPub = sig;
    await prefs.setString('sb_url', url);
    await prefs.setString('sb_key', key);
    await prefs.setString('sb_anon', anon);
  }

  String _norm(String v) {
    v = v.trim();
    final m = RegExp(r'supabase\.com/dashboard/project/([a-zA-Z0-9]+)').firstMatch(v);
    if (m != null) return 'https://${m.group(1)}.supabase.co';
    if (v.isEmpty) return v;
    if (!v.startsWith('http')) v = v.contains('.') ? 'https://$v' : 'https://$v.supabase.co';
    return v.replaceAll(RegExp(r'/(rest|auth)/v1.*$'), '').replaceAll(RegExp(r'/+$'), '');
  }

  String _t() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  String _hint(int code, String body) {
    if (code == 401 || code == 403) {
      return 'کلید API اشتباه است یا دسترسی ندارد (کلید service_role / secret را از Project Settings ← API Keys کپی کن)';
    }
    if (code == 404 && (body.contains('PGRST205') || body.contains('42P01') || body.contains('relation'))) {
      return 'جدولی با این نام در دیتابیس وجود ندارد (نام جدول را بررسی کن یا اول بسازش)';
    }
    if (code == 404) return 'آدرس پروژه اشتباه است یا مسیر وجود ندارد';
    if (code == 400) return 'درخواست نامعتبر است (نام جدول یا ستون اشتباه)';
    if (code == 429) return 'تعداد درخواست زیاد است؛ کمی بعد دوباره تست کن';
    if (code == 540 || code == 522 || code == 523 || code == 521) return 'پروژه Supabase متوقف (Paused) شده؛ از داشبورد Restore کن';
    if (code >= 500) return 'خطای سمت سرور Supabase؛ وضعیت پروژه را در داشبورد ببین';
    return 'پاسخ غیرمنتظره از سرور';
  }

  String _errHint(Object e) {
    if (e is SocketException) return 'اتصال به اینترنت قطع است یا آدرس پروژه اشتباه است (DNS پیدا نشد)';
    if (e is TimeoutException) return 'زمان اتصال تمام شد؛ اینترنت یا فیلترینگ را بررسی کن';
    if (e is HandshakeException || e is TlsException) return 'خطای گواهی/TLS در اتصال امن';
    if (e is FormatException) return 'آدرس نامعتبر است';
    return 'خطای ناشناخته';
  }

  Future<String?> _step(StringBuffer b, String title, String url, String key) async {
    b.writeln('[${_t()}] $title');
    b.writeln('   GET $url');
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 10);
    try {
      final r = await c.getUrl(Uri.parse(url));
      r.headers.set('apikey', key);
      if (key.startsWith('eyJ')) r.headers.set('authorization', 'Bearer $key');
      r.headers.set('accept', 'application/json');
      final res = await r.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      final short = body.length > 400 ? '${body.substring(0, 400)}...' : body;
      b.writeln('   status: ${res.statusCode}');
      if (short.isNotEmpty) b.writeln('   body: $short');
      if (res.statusCode >= 200 && res.statusCode < 300) {
        b.writeln('   نتیجه: موفق ✅');
        return null;
      }
      final h = _hint(res.statusCode, body);
      b.writeln('   نتیجه: ناموفق ❌');
      b.writeln('   دلیل: $h');
      return h;
    } catch (e) {
      final h = _errHint(e);
      b.writeln('   exception: ${e.runtimeType}: $e');
      b.writeln('   نتیجه: ناموفق ❌');
      b.writeln('   دلیل: $h');
      return h;
    } finally {
      c.close(force: true);
    }
  }

  String? _keyRole(String key) {
    if (key.startsWith('sb_publishable_')) return 'anon';
    if (key.startsWith('sb_secret_')) return 'service_role';
    if (!key.startsWith('eyJ')) return null;
    try {
      final parts = key.split('.');
      if (parts.length < 2) return null;
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map;
      return '${j['role'] ?? ''}';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _probe(StringBuffer b, String title, String method, String url, String key, Object? body, {Map<String, String>? extra, bool expectRows = false}) async {
    b.writeln('[${_t()}] $title');
    b.writeln('   $method $url');
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 10);
    try {
      final r = await c.openUrl(method, Uri.parse(url));
      r.headers.set('apikey', key);
      if (key.startsWith('eyJ')) r.headers.set('authorization', 'Bearer $key');
      r.headers.set('content-type', 'application/json');
      r.headers.set('accept', 'application/json');
      extra?.forEach((k, v) => r.headers.set(k, v));
      if (body != null) r.add(utf8.encode(jsonEncode(body)));
      final res = await r.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join();
      b.writeln('   status: ${res.statusCode}');
      if (text.isNotEmpty) b.writeln('   body: ${text.length > 400 ? '${text.substring(0, 400)}...' : text}');
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (expectRows) {
          try {
            final d = jsonDecode(text);
            if (d is List && d.isEmpty) {
              b.writeln('   نتیجه: ناموفق ❌ (هیچ ردیفی ثبت/تغییر نکرد)');
              return 'درخواست موفق بود ولی هیچ ردیفی ذخیره نشد (RLS یا کلید اشتباه)';
            }
          } catch (_) {}
        }
        b.writeln('   نتیجه: موفق ✅');
        return null;
      }
      b.writeln('   نتیجه: ناموفق ❌');
      if (res.statusCode == 401 || res.statusCode == 403) return 'نوشتن ردشد (${res.statusCode}): کلید باید service_role / secret باشد، نه anon؛ و SQL آخر باید اجرا شده باشد';
      if (text.contains('42501')) return 'نوشتن توسط RLS/دسترسی رد شد؛ «کپی SQL» را در Supabase اجرا کن و کلید service_role بگذار';
      if (text.contains('PGRST202') || text.contains('42883')) return 'تابع دیتابیس پیدا نشد؛ «کپی SQL» را در Supabase اجرا کن';
      return _hint(res.statusCode, text);
    } catch (e) {
      b.writeln('   exception: ${e.runtimeType}: $e');
      return _errHint(e);
    } finally {
      c.close(force: true);
    }
  }

  Future<void> _saveAndTest() async {
    final url = _norm(_url.text);
    final key = _key.text.trim();
    _url.text = url;
    await prefs.setString('sb_url', url);
    await prefs.setString('sb_key', key);
    final anon = _anon.text.trim();
    await prefs.setString('sb_anon', anon);
    setState(() => _busy = true);
    final b = StringBuffer();
    b.writeln('[${_t()}] تنظیمات ذخیره شد');
    b.writeln('   آدرس: $url');
    b.writeln('   کلید: ${key.isEmpty ? '(خالی)' : '${key.substring(0, key.length < 8 ? key.length : 8)}••••  (${key.length} کاراکتر)'}');
    String? reason;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || !url.startsWith('https://')) {
      reason = 'آدرس پروژه معتبر نیست (نمونه: https://xxxx.supabase.co)';
      b.writeln('[${_t()}] خطا: $reason');
    } else if (key.isEmpty) {
      reason = 'کلید API وارد نشده است';
      b.writeln('[${_t()}] خطا: $reason');
    } else {
      reason = await _step(b, 'مرحله ۱: بررسی پروژه و کلید (Auth)', '$url/auth/v1/health', key);
      for (final t in ['configs', 'users', 'events']) {
        if (reason != null) break;
        reason = await _step(b, 'مرحله: خواندن جدول $t', '$url/rest/v1/$t?select=*&limit=1', key);
        if (reason == null && t == 'users') {
          final r2 = await _step(b, 'مرحله: بررسی ستون‌های users', '$url/rest/v1/users?select=config_id,open_session,last_closed_session,last_protocol,last_country&limit=1', key);
          if (r2 != null) reason = 'ساختار جدول‌ها قدیمی است؛ «کپی SQL» را بزن و در Supabase › SQL Editor اجرا کن، بعد دوباره «ذخیره و تست اتصال»';
        }
        if (reason != null && reason.startsWith('جدولی')) {
          reason = 'جدول $t ساخته نشده؛ دکمه‌ی «کپی SQL» را بزن و در Supabase › SQL Editor اجرا کن';
        }
      }
      if (reason == null) {
        final role = _keyRole(key);
        b.writeln('[${_t()}] نقش کلید: ${role ?? 'نامشخص'}');
        if (role == 'anon' || role == 'authenticated') {
          reason = 'کلید وارد شده anon/publishable است و فقط خواندن دارد؛ در این بخش باید کلید service_role (secret) بگذاری. کلید anon را در فیلد «کلید anon» و در بیلدر بگذار';
          b.writeln('   ❌ $reason');
        }
      }
      if (reason == null) {
        final tid = 'wt${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
        reason = await _probe(b, 'مرحله: تست نوشتن در configs', 'POST', '$url/rest/v1/configs', key,
            [{'id': tid, 'name': 'test', 'link': 'x://test', 'source': 'test', 'enabled': false}],
            extra: {'prefer': 'return=representation'}, expectRows: true);
        await _probe(b, 'مرحله: پاک کردن ردیف تست', 'DELETE', '$url/rest/v1/configs?id=eq.$tid', key, null, extra: {'prefer': 'return=minimal'});
        if (reason != null) reason = 'ذخیره در دیتابیس کار نمی‌کند: $reason';
      }
      if (reason == null && anon.length > 20) {
        const dev = 'f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3';
        final r1 = await _probe(b, 'مرحله: تست ثبت کاربر با کلید anon (مثل اپ کاربر)', 'POST', '$url/rest/v1/rpc/report_event', anon, {'p_device': dev, 'p_platform': 'selftest', 'p_type': 'hello'});
        if (r1 != null) {
          reason = 'ثبت کاربر از اپ کاربر کار نمی‌کند: $r1';
        } else {
          final r2 = await _probe(b, 'مرحله: بررسی ثبت کاربر تستی در users', 'GET', '$url/rest/v1/users?id=eq.$dev&select=id', key, null, expectRows: true);
          if (r2 != null) reason = 'کاربر تستی ثبت نشد؛ «کپی SQL» را دوباره در Supabase اجرا کن';
        }
        await _probe(b, 'مرحله: پاک کردن کاربر تستی', 'DELETE', '$url/rest/v1/users?id=eq.$dev', key, null, extra: {'prefer': 'return=minimal'});
        await _probe(b, 'مرحله: پاک کردن رویداد تستی', 'DELETE', '$url/rest/v1/events?device_id=eq.$dev', key, null, extra: {'prefer': 'return=minimal'});
      }
    }
    if (reason == null && anon.isEmpty) {
      b.writeln('[${_t()}] هشدار: کلید anon / publishable وارد نشده؛ همان کلید باید داخل بیلدر هم گذاشته شود');
    }
    b.writeln('[${_t()}] ${reason == null ? 'نتیجه نهایی: به دیتابیس وصل شدی ✅' : 'نتیجه نهایی: اتصال ناموفق ❌'}');
    await prefs.setInt('sb_state', reason == null ? 1 : 2);
    await prefs.setString('sb_reason', reason ?? '');
    await prefs.setString('sb_log', b.toString());
    dbEpoch.value++;
    dbState.value = reason == null ? 1 : 2;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _state = reason == null ? 1 : 2;
      _reason = reason ?? '';
      _log = b.toString();
    });
  }

  Client _cl() {
    final u = (prefs.getString('sb_url') ?? '').trim();
    return Client(u.isEmpty ? kSbUrl : u, (prefs.getString('sb_key') ?? '').trim());
  }

  String _stamp() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}';
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _guard(Future<void> Function() job) async {
    if (_bk) return;
    setState(() {
      _bk = true;
      _bkMsg = '';
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _bkMsg = '❌ ${'$e'.replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _bk = false);
    }
  }

  Future<void> _selfTest() async {
    setState(() => _busy = true);
    final r = await _cl().selfTest();
    final b = StringBuffer(_log)
      ..writeln('[${_t()}] تست ثبت کاربر و کانفیگ')
      ..write(r);
    await prefs.setString('sb_log', b.toString());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _log = b.toString();
    });
  }

  Future<void> _backupFile() => _guard(() async {
        final d = await _cl().exportAll();
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/parham-backup-${_stamp()}.json');
        await f.writeAsString(const JsonEncoder.withIndent(' ').convert(d));
        final c = d['counts'] as Map;
        if (mounted) setState(() => _bkMsg = '✅ بکاپ ساخته شد: ${c['configs']} کانفیگ، ${c['users']} کاربر، ${c['events']} رویداد');
        await Share.shareXFiles([XFile(f.path)], text: 'Parham VPN backup');
      });

  Future<void> _backupCopy() => _guard(() async {
        final d = await _cl().exportAll();
        await Clipboard.setData(ClipboardData(text: jsonEncode(d)));
        if (mounted) setState(() => _bkMsg = '✅ بکاپ در کلیپ‌بورد کپی شد (${(d['counts'] as Map)['configs']} کانفیگ، ${(d['counts'] as Map)['users']} کاربر)');
      });

  Future<void> _restoreClipboard() async {
    final clip = (await Clipboard.getData('text/plain'))?.text ?? '';
    Map<String, dynamic>? d;
    try {
      d = (jsonDecode(clip) as Map).cast<String, dynamic>();
    } catch (_) {}
    if (d == null || d['app'] != 'parham-vpn') {
      _toast('اول متن/فایل بکاپ را کپی کن (محتوای فایل JSON)');
      return;
    }
    final data = d;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: card,
        title: const Text('بازگردانی بکاپ'),
        content: Text('${(data['configs'] as List?)?.length ?? 0} کانفیگ و ${(data['users'] as List?)?.length ?? 0} کاربر در دیتابیس ادغام می‌شوند. چیزی پاک نمی‌شود؛ رکوردهای هم‌شناسه به‌روز می‌شوند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('بازگردانی')),
        ],
      ),
    );
    if (ok != true) return;
    await _guard(() async {
      final r = await _cl().restoreAll(data);
      dbEpoch.value++;
      if (mounted) setState(() => _bkMsg = '✅ بازگردانی شد: ${r['configs']} کانفیگ، ${r['users']} کاربر، ${r['events']} رویداد');
    });
  }

  Future<void> _snapshot() => _guard(() async {
        final id = await _cl().createSnapshot('admin ${_stamp()}');
        _snaps = await _cl().listSnapshots();
        if (mounted) setState(() => _bkMsg = '✅ نسخه‌ی شماره‌ی $id داخل دیتابیس ذخیره شد');
      });

  Future<void> _loadSnaps() => _guard(() async {
        _snaps = await _cl().listSnapshots();
        if (mounted) setState(() => _bkMsg = _snaps.isEmpty ? 'هنوز نسخه‌ای داخل دیتابیس ساخته نشده' : '');
      });

  Future<void> _shareSnap(int id) => _guard(() async {
        final d = await _cl().snapshotData(id);
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/parham-snapshot-$id.json');
        await f.writeAsString(const JsonEncoder.withIndent(' ').convert(d));
        await Share.shareXFiles([XFile(f.path)], text: 'Parham VPN snapshot $id');
      });

  Future<void> _ghSave() async {
    final t = _ghToken.text.trim();
    setState(() {
      _ghBusy = true;
      _ghMsg = '';
    });
    try {
      await _cl().setAppSetting('github_token', t);
      await prefs.setString('gh_token', t);
      if (mounted) setState(() => _ghMsg = t.isEmpty ? '✅ توکن حذف شد' : '✅ توکن ذخیره شد؛ اپ کاربران موقع باز شدن آن را می‌گیرد');
    } catch (e) {
      if (mounted) setState(() => _ghMsg = '❌ ${'$e'.replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _ghBusy = false);
    }
  }

  Future<void> _ghTest() async {
    final t = _ghToken.text.trim();
    setState(() {
      _ghBusy = true;
      _ghMsg = '';
    });
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final r = await c.getUrl(Uri.parse('https://api.github.com/rate_limit'));
      r.headers.set('User-Agent', 'NexoraAdmin');
      r.headers.set('Accept', 'application/vnd.github+json');
      if (t.isNotEmpty) r.headers.set('Authorization', 'Bearer $t');
      final res = await r.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 401) {
        if (mounted) setState(() => _ghMsg = '❌ توکن نامعتبر است (401)');
      } else if (res.statusCode != 200) {
        if (mounted) setState(() => _ghMsg = '❌ پاسخ GitHub: ${res.statusCode}');
      } else {
        final core = ((jsonDecode(body) as Map)['resources'] as Map)['core'] as Map;
        if (mounted) setState(() => _ghMsg = '✅ توکن سالم است؛ سقف درخواست: ${core['limit']} در ساعت (باقی‌مانده ${core['remaining']})');
      }
    } catch (e) {
      if (mounted) setState(() => _ghMsg = '❌ اتصال به GitHub برقرار نشد');
    } finally {
      c.close(force: true);
      if (mounted) setState(() => _ghBusy = false);
    }
  }

  Widget _field(TextEditingController c, String label, {bool secret = false, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: secret && _hide,
          textDirection: TextDirection.ltr,
          minLines: 1,
          maxLines: 1,
          decoration: inputDeco(
            label,
            hint: hint,
            suffix: secret ? IconButton(icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: sub), onPressed: () => setState(() => _hide = !_hide)) : null,
          ),
        ),
      );

  Widget _stepLabel(String n, String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Row(children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [accent, accent2]), boxShadow: [BoxShadow(color: accent.withOpacity(0.5), blurRadius: 10, spreadRadius: -2)]),
            child: Text(n, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
        ]),
      );

  Widget _gradBtn(String text, IconData ic, VoidCallback? onTap, List<Color> colors) => Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(colors: colors),
            boxShadow: [BoxShadow(color: colors.last.withOpacity(0.4), blurRadius: 18, spreadRadius: -4, offset: const Offset(0, 6))],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(ic, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Flexible(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5))),
                ]),
              ),
            ),
          ),
        ),
      );

  List<TextSpan> _logSpans(String log) {
    final out = <TextSpan>[];
    for (final line in log.split('\n')) {
      Color c = const Color(0xFF9FB4D8);
      if (line.contains('✅') || line.contains('موفق ✅')) {
        c = neonGreen;
      } else if (line.contains('❌') || line.contains('خطا') || line.contains('دلیل:')) {
        c = const Color(0xFFFF8CA0);
      } else if (line.contains('هشدار')) {
        c = neonAmber;
      } else if (line.startsWith('[')) {
        c = const Color(0xFFE6F0FF);
      }
      out.add(TextSpan(text: '$line\n', style: TextStyle(color: c)));
    }
    return out;
  }

  Widget _supabaseCard() {
    return GlassCard(
      glow: accent2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('تنظیمات Supabase', Icons.bolt_rounded, accent2, hint: 'بار اول مراحل ۱ تا ۳ را به ترتیب انجام بده'),
        const SizedBox(height: 14),
        _stepLabel('۱', 'ساخت جدول‌ها (فقط بار اول)'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF081029), borderRadius: BorderRadius.circular(18), border: Border.all(color: border.withOpacity(0.5))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('SQL کامل ساخت و به‌روزرسانی جدول‌ها', style: TextStyle(color: sub, fontSize: 12))),
              Pill(kSqlVersion, neonViolet, icon: Icons.verified_rounded, ltr: true),
            ]),
            const SizedBox(height: 10),
            _gradBtn('کپی SQL ساخت جدول‌ها', Icons.copy_all_rounded, () {
              // همیشه آخرین نسخه‌ی داخل همین اپ کپی می‌شود؛ نسخه در اولین خط SQL و همین پیام دیده می‌شود
              Clipboard.setData(ClipboardData(text: kSetupSql));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('SQL نسخه‌ی $kSqlVersion کپی شد؛ در Supabase › SQL Editor بچسبان و Run بزن')));
            }, const [neonViolet, accent]),
            const SizedBox(height: 8),
            const Text('Supabase › SQL Editor › New query › بچسبان › Run. چند بار اجرا شود امن است و داده‌ها پاک نمی‌شوند.', style: TextStyle(color: sub, fontSize: 11, height: 1.6)),
          ]),
        ),
        const SizedBox(height: 6),
        _stepLabel('۲', 'آدرس پروژه و کلید'),
        _field(_url, 'Project URL / لینک داشبورد', hint: 'https://xxxx.supabase.co'),
        _field(_key, 'API Key (کلید service_role / secret) — فقط داخل همین اپ ادمین', secret: true),
        _field(_anon, 'کلید anon / publishable — خودکار برای اپ همه‌ی کاربران منتشر می‌شود (secret نگذار)'),
        _stepLabel('۳', 'ذخیره و تست'),
        _gradBtn(_busy ? 'در حال تست...' : 'ذخیره و تست اتصال', _busy ? Icons.hourglass_top_rounded : Icons.save_rounded, _busy ? null : _saveAndTest, const [accent, accent2]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _selfTest,
            icon: const Icon(Icons.bug_report_rounded, size: 20),
            label: const Text('تست ثبت کاربر و کانفیگ'),
          ),
        ),
      ]),
    );
  }

  Widget _ghCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('توکن گیت‌هاب (به‌روزرسانی)', Icons.system_update_alt_rounded, neonViolet),
        const SizedBox(height: 10),
        const Text(
          'برای جلوگیری از Rate Limit گیت‌هاب و خواندن ریلیز ریپوی خصوصی، یک Personal Access Token فقط‌خواندنی (Contents: read) بگذار. '
          'توکن در دیتابیس ذخیره می‌شود و اپ کاربران برای چک کردن آپدیت از آن استفاده می‌کند. لازم است SQL جدید (کپی SQL) یک بار اجرا شده باشد.',
          style: TextStyle(color: sub, fontSize: 12, height: 1.7),
        ),
        const SizedBox(height: 14),
        _field(_ghToken, 'GitHub Token (ghp_… / github_pat_…)', secret: true),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _ghBusy ? null : _ghSave,
              icon: _ghBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
              label: const Text('ذخیره توکن'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: _ghBusy ? null : _ghTest, icon: const Icon(Icons.verified_rounded, size: 18), label: const Text('تست توکن'))),
        ]),
        if (_ghMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_ghMsg, style: const TextStyle(fontSize: 12.5, height: 1.6))),
      ]),
    );
  }

  Widget _backupCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('بکاپ و بازگردانی', Icons.cloud_sync_rounded, neonGreen),
        const SizedBox(height: 10),
        const Text('کانفیگ‌ها، کاربران و آمار اتصال‌ها در یک فایل ذخیره می‌شوند. کلیدهای API داخل بکاپ نمی‌روند.', style: TextStyle(color: sub, fontSize: 12, height: 1.7)),
        const SizedBox(height: 14),
        _gradBtn('دانلود بکاپ کامل (ذخیره / ارسال فایل)', Icons.download_rounded, _bk ? null : _backupFile, const [Color(0xFF14B87D), accent2]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _bk ? null : _backupCopy, icon: const Icon(Icons.copy_rounded, size: 18), label: const Text('کپی بکاپ'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: _bk ? null : _restoreClipboard, icon: const Icon(Icons.restore_rounded, size: 18), label: const Text('بازگردانی'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _bk ? null : _snapshot, icon: const Icon(Icons.save_alt_rounded, size: 18), label: const Text('نسخه‌ی امن', maxLines: 1, overflow: TextOverflow.ellipsis))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: _bk ? null : _loadSnaps, icon: const Icon(Icons.list_alt_rounded, size: 18), label: const Text('لیست نسخه‌ها', maxLines: 1, overflow: TextOverflow.ellipsis))),
        ]),
        if (_bk) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(minHeight: 3)),
        if (_bkMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_bkMsg, style: const TextStyle(fontSize: 12.5, height: 1.6))),
        for (final sn in _snaps)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF081029), borderRadius: BorderRadius.circular(16), border: Border.all(color: border.withOpacity(0.4))),
            child: Row(children: [
              const Icon(Icons.history_rounded, color: accent2, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('نسخه ${sn['id']}  •  ${'${sn['created_at']}'.replaceFirst('T', ' ').split('.').first}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12.5))),
              IconButton(icon: const Icon(Icons.ios_share_rounded, size: 20), onPressed: _bk ? null : () => _shareSnap((sn['id'] as num).toInt())),
            ]),
          ),
      ]),
    );
  }

  Widget _logCard() {
    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(children: [
            const Expanded(child: SectionHeader('لاگ اتصال', Icons.terminal_rounded, neonAmber)),
            TextButton.icon(
              onPressed: _log.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: _log));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لاگ کپی شد')));
                    },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('کپی لاگ'),
            ),
          ]),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(color: const Color(0xFF030816), borderRadius: BorderRadius.circular(16), border: Border.all(color: border.withOpacity(0.4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(children: [
                for (final c in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)])
                  Container(width: 9, height: 9, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: _log.isEmpty
                  ? const Text('هنوز تستی انجام نشده', style: TextStyle(color: sub, fontSize: 12))
                  : SelectableText.rich(
                      TextSpan(children: _logSpans(_log), style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.6)),
                      textDirection: TextDirection.ltr,
                    ),
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ok = _state == 1;
    final bad = _state == 2;
    final col = ok ? neonGreen : (bad ? neonRed : sub);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 120), children: [
      Reveal(
        index: 0,
        child: GlassCard(
          glow: col,
          radius: 28,
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            IconBubble(ok ? Icons.cloud_done_rounded : (bad ? Icons.cloud_off_rounded : Icons.cloud_queue_rounded), col, size: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ok ? 'به دیتابیس وصل شدی ✅' : (bad ? 'اتصال به دیتابیس ناموفق ❌' : 'هنوز تست نشده'), style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                if (bad && _reason.isNotEmpty)
                  Text('دلیل: $_reason', style: const TextStyle(color: sub, fontSize: 12, height: 1.6))
                else if (!ok && !bad)
                  const Text('کلید را وارد کن و «ذخیره و تست اتصال» را بزن', style: TextStyle(color: sub, fontSize: 12, height: 1.6))
                else
                  const Text('آمار، کاربران و کانفیگ‌ها فعال هستند', style: TextStyle(color: sub, fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Reveal(index: 1, child: _supabaseCard()),
      const SizedBox(height: 14),
      Reveal(index: 2, child: _ghCard()),
      const SizedBox(height: 14),
      Reveal(index: 3, child: _backupCard()),
      const SizedBox(height: 14),
      Reveal(index: 4, child: _logCard()),
    ]);
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({required this.values, required this.labels, required this.color, this.line, this.lineColor, this.highlight = -1});
  final List<double> values;
  final List<String> labels;
  final Color color;
  final List<double>? line;
  final Color? lineColor;
  final int highlight;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 18.0, top = 14.0;
    final h = size.height - bottom - top;
    var peak = 1.0;
    for (final v in values) {
      if (v > peak) peak = v;
    }
    for (final v in line ?? const <double>[]) {
      if (v > peak) peak = v;
    }
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = top + h * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final n = values.length;
    if (n == 0) return;
    final slot = size.width / n;
    final bw = (slot * 0.62).clamp(3.0, 28.0);
    void text(String t, Offset o, Color c, double fs, {bool center = true}) {
      final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(color: c, fontSize: fs)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, center ? Offset(o.dx - tp.width / 2, o.dy) : o);
    }

    for (var i = 0; i < n; i++) {
      final cx = slot * i + slot / 2;
      final bh = values[i] / peak * h;
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - bw / 2, top + h - bh, bw, bh),
        topLeft: const Radius.circular(7),
        topRight: const Radius.circular(7),
        bottomLeft: const Radius.circular(2),
        bottomRight: const Radius.circular(2),
      );
      if (i == highlight && bh > 0) {
        canvas.drawRRect(
          r,
          Paint()
            ..color = color.withOpacity(0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      canvas.drawRRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withOpacity(i == highlight ? 1 : 0.85), color.withOpacity(0.15)],
          ).createShader(r.outerRect),
      );
      if (values[i] > 0 && (n <= 16 || i == highlight)) {
        text(values[i].toInt().toString(), Offset(cx, top + h - bh - 13), Colors.white70, 9.5);
      }
      if (n <= 16 || i % 3 == 0) {
        text(labels[i], Offset(cx, size.height - 14), i == highlight ? Colors.white : sub, 9.5);
      }
    }
    final ln = line;
    if (ln != null && ln.length == n && lineColor != null) {
      final pts = [for (var i = 0; i < n; i++) Offset(slot * i + slot / 2, top + h - ln[i] / peak * h)];
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        final p0 = pts[i - 1];
        final p1 = pts[i];
        final mx = (p0.dx + p1.dx) / 2;
        path.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = lineColor!.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = lineColor!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      for (final p in pts) {
        canvas.drawCircle(p, 3.6, Paint()..color = const Color(0xFF050A1A));
        canvas.drawCircle(p, 3, Paint()..color = lineColor!);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) => true;
}
