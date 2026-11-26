import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'updater.dart';

// ---------------------------------------------------------------- پیکسل‌آرت

const Map<String, int> _palette = {
  'o': 0xFF0B1B4D, // خط دور
  'h': 0xFF2F6BFF, // مو
  'H': 0xFF7FB2FF, // برق مو
  'd': 0xFF1B3FA8, // سایه‌ی مو
  's': 0xFFDDF1FF, // پوست
  'S': 0xFFA9CDEF, // سایه‌ی پوست
  'e': 0xFF0B1B4D, // چشم
  'w': 0xFFFFFFFF, // درخشش چشم
  'b': 0xFF8FB8FF, // گونه
  'm': 0xFF1B3FA8, // دهان
  'c': 0xFF1F5BFF, // لباس
  'C': 0xFF5BA0FF, // لباس روشن
  'g': 0xFF6BE6FF, // نشان دیجیتال
};

const List<String> _openRows = [
  '.....oooooooooo.....',
  '...ooHHhhhhhhHHoo...',
  '..ohhHHhhhhhhHHhho..',
  '.ohhhhhhhhhhhhhhhho.',
  '.ohhhhhhhhhhhhhhhho.',
  '.ohhhdhhhhhhhhdhhho.',
  '.ohhdssssssssssdhho.',
  '.ohhsssssssssssshho.',
  '.ohhsooossssoooshho.',
  '.ohhseewssssweeshho.',
  '.ohhseeesssseeeshho.',
  '.ohhssbbssssbbsshho.',
  '.ohhsssssssssssshho.',
  '.ohhsssssmmssssshho.',
  '..ohhSssssssssShho..',
  '...ohhSssssssShho...',
  '.....ooSssssSoo.....',
  '....ooSSssssSSoo....',
  '..oooccCccccCccooo..',
  '.occcccCccccCccccco.',
  'occccccCggggCcccccco',
  'occcccccggggccccccco',
  'occcccccggggccccccco',
  'oooooooooooooooooooo',
];

const List<String> _closedRows = [
  '.....oooooooooo.....',
  '...ooHHhhhhhhHHoo...',
  '..ohhHHhhhhhhHHhho..',
  '.ohhhhhhhhhhhhhhhho.',
  '.ohhhhhhhhhhhhhhhho.',
  '.ohhhdhhhhhhhhdhhho.',
  '.ohhdssssssssssdhho.',
  '.ohhsssssssssssshho.',
  '.ohhsssssssssssshho.',
  '.ohhsssssssssssshho.',
  '.ohhsooossssoooshho.',
  '.ohhssbbssssbbsshho.',
  '.ohhsssssssssssshho.',
  '.ohhsssssmmssssshho.',
  '..ohhSssssssssShho..',
  '...ohhSssssssShho...',
  '.....ooSssssSoo.....',
  '....ooSSssssSSoo....',
  '..oooccCccccCccooo..',
  '.occcccCccccCccccco.',
  'occccccCggggCcccccco',
  'occcccccggggccccccco',
  'occcccccggggccccccco',
  'oooooooooooooooooooo',
];


class _PixelGirlPainter extends CustomPainter {
  _PixelGirlPainter({required this.closed, required this.t});
  final bool closed;
  final double t; // 0..1 برای حرکت ملایم و جرقه‌ها

  @override
  void paint(Canvas canvas, Size size) {
    final rows = closed ? _closedRows : _openRows;
    final cols = rows.first.length;
    final cell = (size.width / cols).floorToDouble();
    final w = cell * cols, h = cell * rows.length;
    final bob = (t < 0.5 ? t : 1 - t) * 2 * cell * 0.9; // بالا و پایین رفتن پیکسلی
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2 - bob + cell * 0.45;
    final p = Paint()..isAntiAlias = false;

    // جرقه‌های دیجیتال دور شخصیت
    final sparkles = <List<double>>[
      [-1.6, 3, 0.0], [cols + 0.6, 5, 0.33], [-2.4, 12, 0.66], [cols + 1.4, 14, 0.15], [1, -1.4, 0.5], [(cols - 2).toDouble(), -0.6, 0.85],
    ];
    for (final s in sparkles) {
      final phase = (t * 2 + s[2]) % 1.0;
      final a = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
      p.color = const Color(0xFF6BE6FF).withOpacity(0.25 + 0.7 * a);
      final k = a > 0.6 ? cell : cell * 0.6;
      canvas.drawRect(Rect.fromLTWH(left + s[0] * cell, top + s[1] * cell, k, k), p);
    }

    for (var y = 0; y < rows.length; y++) {
      final row = rows[y];
      for (var x = 0; x < cols; x++) {
        final c = row[x];
        if (c == '.') continue;
        p.color = Color(_palette[c] ?? 0xFFFFFFFF);
        canvas.drawRect(Rect.fromLTWH(left + x * cell, top + y * cell, cell + 0.5, cell + 0.5), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelGirlPainter old) => old.closed != closed || old.t != t;
}

/// دختر دیجیتالی پیکسلی آبی که مدام چشمک می‌زند.
class PixelGirl extends StatefulWidget {
  const PixelGirl({super.key, this.size = 220});
  final double size;

  @override
  State<PixelGirl> createState() => _PixelGirlState();
}

class _PixelGirlState extends State<PixelGirl> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final v = _c.value;
        // دو چشمک در هر چرخه (یکی کوتاه و یکی بعدش)
        final closed = (v > 0.46 && v < 0.52) || (v > 0.60 && v < 0.65) || (v > 0.94 && v < 0.99);
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(painter: _PixelGirlPainter(closed: closed, t: v)),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- ابزارهای پیکسلی

const Color _bg = Color(0xFF050B1D);
const Color _ink = Color(0xFF0B1B4D);
const Color _blue = Color(0xFF2F6BFF);
const Color _cyan = Color(0xFF6BE6FF);

TextStyle _pixel(double size, {Color color = Colors.white}) => TextStyle(
      fontFamily: 'PressStart2P',
      fontFamilyFallback: const ['Vazirmatn'],
      fontSize: size,
      height: 1.7,
      color: color,
    );

String _fa(Object v) {
  const d = '۰۱۲۳۴۵۶۷۸۹';
  return '$v'.replaceAllMapped(RegExp(r'\d'), (m) => d[int.parse(m.group(0)!)]);
}

class _PixelButton extends StatelessWidget {
  const _PixelButton({required this.label, required this.onTap, this.color = _blue, this.sub});
  final String label;
  final String? sub;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: _ink, offset: Offset(5, 5), blurRadius: 0)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white)),
          if (sub != null) Text(sub!, style: _pixel(9, color: Colors.white70)),
        ]),
      ),
    );
  }
}

class _PixelBar extends StatelessWidget {
  const _PixelBar({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    const cells = 20;
    final filled = (percent * cells / 100).floor();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), color: _ink),
      child: Row(children: [
        for (var i = 0; i < cells; i++)
          Expanded(
            child: Container(
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              color: i < filled ? _cyan : const Color(0xFF14295F),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- صفحه‌ی به‌روزرسانی

enum _U { checking, upToDate, found, downloading, downloaded, error, unsupported }

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  _U _s = _U.checking;
  AppInfo? _info;
  ReleaseInfo? _release;
  ReleaseAsset? _asset;
  UpdateStatus? _st;
  String _error = '';
  String _hint = '';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (!Updater.supported) {
      _s = _U.unsupported;
    } else {
      unawaited(_begin());
    }
  }

  @override
  void dispose() {
    // دانلود عمداً متوقف نمی‌شود: Foreground Service در پس‌زمینه ادامه می‌دهد.
    _poll?.cancel();
    super.dispose();
  }

  void _set(_U s, {String error = ''}) {
    if (!mounted) return;
    setState(() {
      _s = s;
      _error = error;
    });
  }

  Future<void> _begin() async {
    try {
      _info = await Updater.appInfo();
      // ممکن است دانلودی از قبل در جریان یا کامل‌شده باشد (کاربر از برنامه بیرون رفته بود)
      final st = await Updater.status();
      _st = st;
      if (st.state == 'downloading') {
        _s = _U.downloading;
        _startPolling();
        if (mounted) setState(() {});
        return;
      }
      if (st.state == 'done' && Updater.isNewer(st.version, _info!.versionName)) {
        _s = _U.downloaded;
        if (mounted) setState(() {});
        return;
      }
      if (st.state != 'idle') await Updater.clear();
      await _check();
    } catch (e) {
      _set(_U.error, error: _friendly(e));
    }
  }

  Future<void> _check() async {
    _set(_U.checking);
    final started = DateTime.now();
    try {
      _info ??= await Updater.appInfo();
      await Updater.syncToken();
      final release = await Updater.latest(abi: _info!.abi);
      // انیمیشن «Checking» حداقل چند لحظه دیده شود
      final wait = const Duration(milliseconds: 1800) - DateTime.now().difference(started);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (!mounted) return;
      _release = release;
      _asset = release.assetFor(_info!.abi);
      if (!Updater.isNewer(release.tag, _info!.versionName)) {
        _set(_U.upToDate);
      } else if (_asset == null) {
        _set(_U.error, error: 'فایل نصب این سیستم‌عامل در ریلیز ${release.tag} پیدا نشد');
      } else {
        _set(_U.found);
      }
    } catch (e) {
      _set(_U.error, error: _friendly(e));
    }
  }

  String _friendly(Object e) {
    final t = '$e';
    if (t.contains('release_not_found_token')) return 'ریلیزی در مخزن $kUpdateRepo پیدا نشد. توکن گیت‌هاب باید به همین مخزن دسترسی داشته باشد (Fine-grained: همین مخزن + Contents: Read-only، یا Classic با تیک repo). اگر ریلیزی منتشر نشده، اول بیلد بگیر.';
    if (t.contains('bad_token')) return 'توکن گیت‌هاب نامعتبر است؛ در اپ ادمین توکن را اصلاح کن.';
    if (t.contains('rate_limited')) return 'محدودیت درخواست GitHub پر شده؛ در اپ ادمین «توکن گیت‌هاب» را وارد کن یا کمی بعد تلاش کن.';
    if (t.contains('forbidden')) return 'دسترسی به GitHub رد شد (403)؛ توکن گیت‌هاب را در اپ ادمین بررسی کن.';
    if (t.contains('release_not_found')) return 'ریلیزی در مخزن GitHub پیدا نشد (مخزن خصوصی است یا هنوز ریلیزی منتشر نشده).';
    if (e is SocketException || e is TimeoutException || t.contains('HandshakeException')) {
      return 'اتصال به GitHub برقرار نشد؛ اینترنت را بررسی کن.';
    }
    return t.replaceFirst('Exception: ', '');
  }

  Future<void> _yes() async {
    final r = _release, a = _asset;
    if (r == null || a == null) return;
    try {
      await Updater.start(r, a);
      _st = UpdateStatus('downloading', 0, 0, r.version, '');
      _set(_U.downloading);
      _startPolling();
    } catch (e) {
      _set(_U.error, error: _friendly(e));
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final st = await Updater.status();
        if (!mounted) return;
        setState(() => _st = st);
        if (st.state == 'done') {
          _poll?.cancel();
          _set(_U.downloaded);
        } else if (st.state == 'error') {
          _poll?.cancel();
          _set(_U.error, error: st.error == 'interrupted' ? 'دانلود نیمه‌کاره قطع شد؛ دوباره تلاش کن.' : 'دانلود ناموفق بود: ${st.error}');
        } else if (st.state == 'idle') {
          _poll?.cancel();
          _set(_U.checking);
          unawaited(_check());
        }
      } catch (_) {}
    });
  }

  Future<void> _install() async {
    try {
      final r = await Updater.install();
      if (!mounted) return;
      setState(() {
        _hint = r == 'need_permission'
            ? 'اجازه‌ی «نصب از این منبع» را روشن کن، برگرد و دوباره Install را بزن.'
            : r == 'no_file'
                ? 'فایل آپدیت پیدا نشد؛ دوباره دانلود کن.'
                : (Platform.isAndroid ? 'نصب‌کننده‌ی اندروید باز شد؛ نصب را تأیید کن. اطلاعات و لاگین‌ها حفظ می‌شود.' : 'نصب‌کننده اجرا شد؛ برنامه بسته می‌شود و بعد از نصب دوباره باز می‌شود.');
      });
      if (r == 'no_file') {
        await Updater.clear();
        unawaited(_check());
      }
    } catch (e) {
      _set(_U.error, error: _friendly(e));
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('به‌روزرسانی', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: _content()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(String en, {Color color = Colors.white}) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text(en, textAlign: TextAlign.center, style: _pixel(13, color: color)),
      );

  Widget _fa14(String text, {Color color = const Color(0xFFB9CCF5)}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 14, height: 1.7, color: color)),
      );

  List<Widget> _content() {
    final girl = const PixelGirl(size: 220);
    switch (_s) {
      case _U.checking:
        return [girl, const SizedBox(height: 18), _title('Checking for updates...'), _fa14('در حال چک کردن…')];
      case _U.upToDate:
        return [
          girl,
          const SizedBox(height: 18),
          _title('Up to date!', color: _cyan),
          _fa14('برنامه به‌روز است${_info == null ? '' : ' (نسخه ${_fa(_info!.versionName)})'}'),
          const SizedBox(height: 20),
          _PixelButton(label: 'بررسی دوباره', onTap: _check),
        ];
      case _U.found:
        final r = _release!;
        final mb = _asset!.size > 0 ? ' • ${_fa((_asset!.size / 1048576).toStringAsFixed(1))} مگابایت' : '';
        return [
          girl,
          const SizedBox(height: 18),
          _title('Found!', color: _cyan),
          _fa14('پیدا شد! نسخه‌ی جدید ${_fa(r.version)}$mb'),
          _fa14('نسخه‌ی فعلی: ${_fa(_info?.versionName ?? '')}', color: const Color(0xFF8FA6CC)),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: _PixelButton(label: 'می‌خوام آپدیت کنم', sub: 'Yes', onTap: _yes)),
            const SizedBox(width: 16),
            Expanded(child: _PixelButton(label: 'نه', sub: 'No', color: const Color(0xFF3A4A78), onTap: () => Navigator.of(context).maybePop())),
          ]),
        ];
      case _U.downloading:
        final pct = _st?.percent ?? 0;
        return [
          girl,
          const SizedBox(height: 18),
          _title('Downloading...'),
          _fa14('${_fa(pct)}٪ کامل شد', color: Colors.white),
          const SizedBox(height: 14),
          _PixelBar(percent: pct),
          _fa14('می‌تونی از برنامه خارج بشی؛ دانلود در پس‌زمینه ادامه پیدا می‌کنه و پیشرفتش تو نوتیفیکیشن معلومه.', color: const Color(0xFF8FA6CC)),
          const SizedBox(height: 14),
          _PixelButton(
            label: 'لغو دانلود',
            color: const Color(0xFF3A4A78),
            onTap: () async {
              await Updater.cancel();
            },
          ),
        ];
      case _U.downloaded:
        return [
          girl,
          const SizedBox(height: 18),
          _title('Download complete!', color: _cyan),
          _fa14('به‌روزرسانی تکمیل شد'),
          const SizedBox(height: 18),
          _PixelButton(label: 'اینستال', sub: 'Install', onTap: _install),
          if (_hint.isNotEmpty) _fa14(_hint, color: const Color(0xFF8FA6CC)),
        ];
      case _U.error:
        return [
          girl,
          const SizedBox(height: 18),
          _title('Oops!', color: const Color(0xFFFFB74D)),
          _fa14(_error, color: const Color(0xFFFFB74D)),
          const SizedBox(height: 20),
          _PixelButton(label: 'تلاش دوباره', onTap: () async {
            await Updater.clear().catchError((_) {});
            await _check();
          }),
        ];
      case _U.unsupported:
        return [
          girl,
          const SizedBox(height: 18),
          _title('Unsupported'),
          _fa14('به‌روزرسانی روی این سیستم‌عامل پشتیبانی نمی‌شود.'),
        ];
    }
  }
}

// ---------------------------------------------------------------- پیام «به‌روزرسانی تکمیل شد»

bool _promptOpen = false;
final Set<String> _promptShown = {};

/// وقتی کاربر به برنامه برمی‌گردد و دانلودِ پس‌زمینه تمام شده است: پیام + تأیید برای باز شدن اینستالر.
Future<void> promptFinishedUpdate(BuildContext context) async {
  if (!Updater.supported || _promptOpen) return;
  try {
    final info = await Updater.appInfo();
    final st = await Updater.status();
    if (st.state == 'idle') return;
    if (st.state == 'done' && !Updater.isNewer(st.version, info.versionName)) {
      await Updater.clear(); // بعد از نصب موفق، فایل قدیمی پاک می‌شود
      return;
    }
    if (st.state != 'done' || _promptShown.contains(st.version)) return;
    if (!context.mounted) return;
    _promptOpen = true;
    _promptShown.add(st.version);
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.white, width: 3)),
        title: const Text('به‌روزرسانی تکمیل شد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: const Text('نسخه‌ی جدید دانلود شده است. با زدن «تأیید» نصب‌کننده‌ی اندروید باز می‌شود؛ اطلاعات و لاگین‌هایت حفظ می‌شود.',
            style: TextStyle(color: Color(0xFFB9CCF5), height: 1.7)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بعداً')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید')),
        ],
      ),
    );
    if (ok == true) await Updater.install();
  } catch (_) {
    // بررسی پس‌زمینه نباید برنامه را مختل کند
  } finally {
    _promptOpen = false;
  }
}

// ---------------------------------------------------------------- پاپ‌آپ «نسخه‌ی جدید»

bool _newOpen = false;
String _newShownTag = '';

/// موقع باز شدن برنامه: نسخه‌ی نصب‌شده با آخرین ریلیز GitHub مقایسه می‌شود؛
/// اگر نسخه‌ی جدیدتری برای همین سیستم‌عامل (اندروید/ویندوز/مک/لینوکس) هست، پاپ‌آپ نشان می‌دهد.
Future<void> promptNewVersion(BuildContext context) async {
  if (!Updater.supported || _newOpen) return;
  try {
    final r = await Updater.checkQuiet();
    if (r == null || r.tag == _newShownTag || !context.mounted) return;
    _newShownTag = r.tag;
    _newOpen = true;
    final info = await Updater.appInfo();
    if (!context.mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.white, width: 3)),
        title: const Text('نسخه‌ی جدید پیدا شد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text(
          'نسخه‌ی نصب‌شده: ${_fa(info.versionName)}\nنسخه‌ی جدید: ${_fa(r.version)}\n\nمی‌خوای الان به‌روزرسانی کنی؟ اطلاعات و لاگین‌هات حفظ می‌شه.',
          style: const TextStyle(color: Color(0xFFB9CCF5), height: 1.8),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بعداً')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('به‌روزرسانی')),
        ],
      ),
    );
    if (go == true && context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const UpdatePage()));
    }
  } catch (_) {
    // بررسی پس‌زمینه نباید برنامه را مختل کند
  } finally {
    _newOpen = false;
  }
}
