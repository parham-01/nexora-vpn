import 'intro_page.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'cloud_backup.dart';
import 'aws_assistant.dart';
import 'connect_fx.dart';
import 'connect_globe.dart';
import 'geo_atlas.dart';
import 'fx_backdrop.dart';
import 'nexora_logo.dart';
import 'store.dart';
import 'traffic_card.dart';
import 'update_page.dart';
import 'vpn_service.dart';
import 'xray_config.dart';
import 'firefox/firefox_page.dart';
import 'firefox/firefox_service.dart';
import 'widgets.dart';

const String telegramUrl = 'https://t.me/parham_ste01';

void snack(BuildContext c, String m) {
  ScaffoldMessenger.of(c).hideCurrentSnackBar();
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
}

Route<T> adaptiveRoute<T>(WidgetBuilder b) =>
    Platform.isMacOS ? CupertinoPageRoute<T>(builder: b) : MaterialPageRoute<T>(builder: b);

bool _popupOpen = false;

Future<void> showConnPopup(BuildContext context) async {
  // پاپ‌آپ «شما متصل شدید» حذف شد؛ بعد از اتصال دیگر نمایش داده نمی‌شود.
  return;
  // ignore: dead_code
  if (_popupOpen || !context.mounted) return;
  _popupOpen = true;
  try {
    await showDialog<void>(context: context, builder: (_) => const ConnPopup());
  } finally {
    _popupOpen = false;
  }
}

void showIpQualitySheet(BuildContext context) {
  final p = P.of(context);
  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  final on = VpnService.I.status.value.phase == Phase.on;
  final proxy = (isDesktop && on) ? '127.0.0.1:10809' : null;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: p.border.withOpacity(0.3)),
      ),
      child: FutureBuilder<IpQualityReport?>(
        future: Api.inspectIpQuality(proxy: proxy),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 20),
                CircularProgressIndicator(color: p.accent),
                const SizedBox(height: 18),
                Text('در حال تحلیل اصالت آی‌پی، ASN و نمره ریسک...', style: TextStyle(color: p.text, fontSize: 14)),
                const SizedBox(height: 20),
              ],
            );
          }
          final r = snap.data;
          if (r == null) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.orangeAccent, size: 48),
                const SizedBox(height: 12),
                Text('دریافت اطلاعات با خطا مواجه شد', style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('از فعال بودن فیلترشکن و ارتباط اینترنت اطمینان حاصل کنید.', style: TextStyle(color: p.sub, fontSize: 13)),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
              ],
            );
          }

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: p.sub.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('کیفیت و اصالت آی‌پی', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: r.riskColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: r.riskColor),
                      ),
                      child: Text(
                        r.isResidential ? '🛡️ آی‌پی خانگی (Residential)' : '🏢 دیتاسنتر / هاستینگ',
                        style: TextStyle(color: r.riskColor, fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.border.withOpacity(0.4)),
                  ),
                  child: Column(
                    children: [
                      _rowQuality('آدرس آی‌پی خروجی', r.ip, p),
                      const Divider(height: 14),
                      _rowQuality('موقعیت سرور', '${r.flag} ${r.country} (${r.city})', p),
                      const Divider(height: 14),
                      _rowQuality('اپراتور / ASN', '${r.isp} (${r.asName})', p),
                      const Divider(height: 14),
                      _rowQuality('نمره ریسک تقلب', '${r.fraudScore} از ۱۰۰ (${r.riskLabel})', p, valColor: r.riskColor),
                      const Divider(height: 14),
                      _rowQuality('امنیت DNS', 'رمزنگاری DoH (بدون نشت)', p, valColor: const Color(0xFF29E07F)),
                      const Divider(height: 14),
                      _rowQuality('منطقه زمانی سرور', r.timezone.isEmpty ? 'نامشخص' : r.timezone, p),
                      const Divider(height: 14),
                      _rowQuality('ساعت سیستم شما', r.clientTimezone, p),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: r.timezoneMatch ? Colors.green.withOpacity(0.08) : Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: r.timezoneMatch ? Colors.green.withOpacity(0.3) : Colors.amber.withOpacity(0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(r.timezoneMatch ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                          color: r.timezoneMatch ? Colors.green : Colors.amber, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          r.note,
                          style: TextStyle(color: p.text, fontSize: 12.5, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!r.timezoneMatch && Platform.isWindows) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF29E07F),
                      foregroundColor: const Color(0xFF040A1C),
                      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
                    label: const Text('تنظیم خودکار ساعت ویندوز روی موقعیت سرور',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    onPressed: () async {
                      final ok = await Api.syncWindowsTimezone(r.code, timezone: r.timezone);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        snack(context, ok
                            ? 'ساعت ویندوز روی منطقه زمانی سرور (${r.country}) تنظیم شد!'
                            : 'تنظیم ساعت ویندوز با خطا مواجه شد. در صورت امکان برنامه را به صورت Run as administrator اجرا کنید');
                        showIpQualitySheet(context);
                      }
                    },
                  ),
                ] else if (Api.isTimezoneOverridden && Platform.isWindows) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.restore_rounded, size: 16),
                      label: const Text('بازگردانی ساعت ویندوز به زمان اصلی ایران (Tehran)',
                          style: TextStyle(fontSize: 12, color: Colors.white70)),
                      onPressed: () async {
                        await Api.restoreWindowsTimezone();
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          snack(context, 'ساعت سیستم به حالت اولیه ایران بازگردانده شد.');
                          showIpQualitySheet(context);
                        }
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9900),
                    foregroundColor: const Color(0xFF040A1C),
                    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.card_giftcard_rounded, size: 20),
                  label: const Text('دستیار هوشمند دریافت ۱۰۰ دلار آمازون (بدون کارت)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    showAwsAssistantSheet(context);
                  },
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('متوجه شدم'),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

Widget _rowQuality(String label, String value, P p, {Color? valColor}) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: p.sub, fontSize: 12.5)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.left,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: valColor ?? p.text, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );

/// درخواست «انتخاب لوکیشن و اتصال» از صفحه‌ی کانفیگ‌ها (دکمه‌ی فلش کنار هر لوکیشن).
/// صفحه‌ی کانفیگ‌ها لوکیشن را انتخاب می‌کند، به خانه برمی‌گردد و این شمارنده را زیاد می‌کند؛ خانه اتصال را برقرار می‌کند.
final ValueNotifier<int> homeConnectRequest = ValueNotifier<int>(0);

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _i = 0;
  final Set<int> _seen = {0};

  void _go(int v) {
    if (v == _i) return;
    setState(() {
      _i = v;
      _seen.add(v);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    homeConnectRequest.addListener(_onHomeConnectReq);
    Tour.launch = (anim, buddy) async {
      if (!mounted) return;
      _go(0);
      await showNexoraIntro(context, goTab: _go, anim: anim, buddy: buddy);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (Store.firstRun && !Store.introSeen) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        final c = await showIntroPicker(context, first: true);
        if (!mounted) return;
        if (c == null) {
          await Store.setIntroSeen();
        } else {
          await showNexoraIntro(context, goTab: _go, anim: c.anim, buddy: c.buddy);
        }
        if (!mounted) return;
      }
      await promptFinishedUpdate(context);
      // بررسی نسخه‌ی جدید در GitHub (با کمی تأخیر تا اتصال/لودینگ اولیه مزاحم نشود)
      await Future<void>.delayed(const Duration(seconds: 4));
      if (mounted) unawaited(promptNewVersion(context));
    });
    _boot();
  }

  void _onHomeConnectReq() => _go(0);

  @override
  void dispose() {
    homeConnectRequest.removeListener(_onHomeConnectReq);
    Tour.launch = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // برگشتن به برنامه بعد از دانلود پس‌زمینه: پیام «به‌روزرسانی تکمیل شد»
    if (state == AppLifecycleState.resumed && mounted) promptFinishedUpdate(context);
  }

  Future<void> _boot() async {
    await VpnService.I.init();
    // تست پینگ پس‌زمینه‌ی شروع برنامه حذف شد؛ فقط لیست کانفیگ‌ها همگام می‌شود
    unawaited(Api.sync());
    unawaited(GeoAtlas.preload());
    if (Store.getBool('autoConnect', false) && Store.config.value != null && mounted) {
      final r = await ConnectGlobe.run(context, VpnService.I.connect, _errText);
      if (!mounted) return;
      if (r != null) {
        _logConnFail('خانه / اتصال خودکار هنگام باز شدن برنامه', r);
        snack(context, _errText(r));
      } else {
        showConnPopup(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    // صفحه‌های پنهان انیمیشن‌شان متوقف می‌شود (TickerMode) تا گوشی فقط صفحه‌ی دیده‌شده را بکشد
    final pages = IndexedStack(index: _i, children: [
      TickerMode(enabled: _i == 0, child: HomePage(openSettings: () => Navigator.push(context, adaptiveRoute((_) => const SettingsPage())))),
      const SizedBox.shrink(), // تنظیمات دیگر تب نیست؛ از پروفایل بالا-راست خانه باز می‌شود
      _seen.contains(2) ? TickerMode(enabled: _i == 2, child: const InfoPage()) : const SizedBox.shrink(),
      _seen.contains(3) ? TickerMode(enabled: _i == 3, child: const FirefoxPage()) : const SizedBox.shrink(),
    ]);
    return Scaffold(
      backgroundColor: p.bg,
      extendBody: false,
      body: AppBg(
        child: Stack(children: [
          if (_i == 0) Positioned.fill(child: NexoraFxBackdrop(style: FxStyle.home, accent: p.accent, accent2: p.accent2)),
          Positioned.fill(child: wide
            ? Row(children: [
                DesktopSidebar(index: _i, onTap: _go),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: SafeArea(child: pages)),
                  ),
                ),
              ])
            : SafeArea(bottom: false, child: pages)),
        ]),
      ),
      bottomNavigationBar: wide ? null : Container(color: p.bg, child: NavBar(index: _i, onTap: _go)),
    );
  }
}

// آخرین خطای خام هسته (اگر باشد) برای عیب‌یابی؛ حداکثر ۲ خط
String _coreLog() {
  final e = VpnService.I.lastError.trim();
  if (e.isEmpty) return '';
  final lines = e.split('\n').where((x) => x.trim().isNotEmpty).toList();
  final t = lines.sublist(lines.length > 2 ? lines.length - 2 : 0).join('\n');
  return '\n' + (t.length > 160 ? t.substring(t.length - 160) : t);
}

String _errText(String r) {
  // متن ساده برای کاربر؛ جزئیات فنی فقط در «لاگ» پنل ادمین ثبت می‌شود.
  switch (r) {
    case 'busy':
      return 'در حال اتصال...';
    case 'cancelled':
      return 'اتصال لغو شد';
    case 'permission':
      return 'دسترسی VPN داده نشد';
    case 'no_config':
    case 'no_valid_ping':
    case 'server_dns':
      return 'سرور در دسترس نیست؛ کمی بعد دوباره تلاش کن';
    default:
      return 'اتصال برقرار نشد؛ دوباره تلاش کن';
  }
}

/// ثبت بی‌صدای خطای اتصال برای پنل ادمین (کاربر چیزی نمی‌بیند).
void _logConnFail(String area, String r) {
  if (r == 'cancelled' || r == 'busy') return;
  var cid = '';
  try {
    cid = '${Store.config.value?['id'] ?? ''}';
  } catch (_) {}
  unawaited(Api.logError(area, r, detail: VpnService.I.lastError, config: cid));
}

class HomePage extends StatefulWidget {
  final VoidCallback openSettings;
  const HomePage({super.key, required this.openSettings});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = false;

  // هر بار رفلش یک اتصال تازه می‌سازد و دوباره می‌گیرد (قفل ندارد، چند بار پشت هم کار می‌کند)
  int _rf = 0;

  Future<void> _refetch() async {
    final my = ++_rf;
    setState(() => _loading = true);
    final ok = await Api.sync();
    if (!ok && mounted && my == _rf) snack(context, 'دریافت از سرور ناموفق بود؛ کانفیگ‌های ذخیره‌شده استفاده می‌شوند');
    if (mounted && my == _rf) setState(() => _loading = false);
  }

  void _openLocations(int tab) {
    Navigator.push(context, adaptiveRoute((_) => LocationsPage(initialTab: tab)));
  }

  Future<void> _toggle(bool on) async {
    final v = VpnService.I;
    if (on) {
      // A device can keep only one full-device VPN tunnel active at once.
      // Refresh the independent core first so a Firefox tunnel that survived
      // an app restart is detected too, rather than relying on this process's
      // cached button state.
      try {
        await FirefoxService.I.refresh();
        if (FirefoxService.I.isOn) await FirefoxService.I.disconnect();
      } catch (_) {
        if (FirefoxService.I.isOn) await FirefoxService.I.disconnect();
      }
      if (!mounted) return;
      final r = await ConnectGlobe.run(context, v.connect, _errText);
      if (!mounted) return;
      if (r != null) {
        _logConnFail('خانه / دکمه‌ی اتصال', r);
        snack(context, _errText(r));
      } else {
        showConnPopup(context);
      }
    } else {
      if (Store.confirmDisconnect) {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final p = P.of(ctx);
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: p.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                title: Text('قطع اتصال؟', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w800)),
                content: Text('اتصال VPN قطع می‌شود.', style: TextStyle(color: p.sub, fontSize: 14)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('ادامه‌ی اتصال', style: TextStyle(color: p.sub))),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(ctx, true), child: const Text('قطع کن')),
                ],
              ),
            );
          },
        );
        if (ok != true) return;
      }
      await v.disconnect();
    }
  }

  late final ValueNotifier<Phase> _phase = ValueNotifier(VpnService.I.status.value.phase);

  @override
  void initState() {
    super.initState();
    VpnService.I.status.addListener(_onStatus);
    homeConnectRequest.addListener(_onConnectReq);
  }

  /// فلش صفحه‌ی کانفیگ‌ها: لوکیشن انتخاب شده و کاربر به خانه برگشته → اتصال را برقرار کن.
  Future<void> _onConnectReq() async {
    // یک فریم صبر می‌کنیم تا صفحه‌های بالایی کاملاً بسته شوند و خانه دیده شود
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    final v = VpnService.I;
    if (v.status.value.phase == Phase.connecting) return;
    if (v.status.value.phase == Phase.on) await v.disconnect();
    if (!mounted) return;
    await _toggle(true);
  }

  @override
  void dispose() {
    homeConnectRequest.removeListener(_onConnectReq);
    VpnService.I.status.removeListener(_onStatus);
    _phase.dispose();
    super.dispose();
  }

  void _onStatus() {
    final ph = VpnService.I.status.value.phase;
    if (_phase.value != ph) _phase.value = ph;
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    return ValueListenableBuilder<Phase>(
      valueListenable: _phase,
      builder: (context, ph, _) {
        final on = ph == Phase.on;
        final busy = ph == Phase.connecting;

        final top = SizedBox(
          height: 92,
          child: Stack(children: [
            const Positioned.fill(child: IgnorePointer(child: HeaderWave())),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, left: 6, right: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TourTarget('home.menu', ProfileButton(onTap: widget.openSettings)),
                  TourTarget('home.premium', IconButton(
                    onPressed: () => snack(context, 'نسخه پریمیوم به‌زودی'),
                    icon: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFC53D), size: 26),
                  )),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Nexora', style: TextStyle(color: p.text, fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                      const SizedBox(width: 10),
                      const NexoraMark(size: 46),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        );

        final statusChip = Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                color: (on ? const Color(0xFF29E07F) : busy ? const Color(0xFFFFC53D) : p.accent2).withOpacity(0.12),
                border: Border.all(color: (on ? const Color(0xFF29E07F) : busy ? const Color(0xFFFFC53D) : p.accent2).withOpacity(0.45)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? const Color(0xFF29E07F) : busy ? const Color(0xFFFFC53D) : p.accent2,
                    boxShadow: [BoxShadow(color: (on ? const Color(0xFF29E07F) : busy ? const Color(0xFFFFC53D) : p.accent2).withOpacity(0.7), blurRadius: 8)],
                  ),
                ),
                const SizedBox(width: 8),
                Text(on ? 'اتصال امن برقرار است' : busy ? 'در حال اتصال…' : 'آماده‌ی اتصال امن',
                    style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );

        Widget featChip(IconData ic, String t) => Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: p.accent2.withOpacity(0.08),
                  border: Border.all(color: p.accent2.withOpacity(0.25)),
                ),
                child: Column(children: [
                  Icon(ic, color: p.accent2, size: 21),
                  const SizedBox(height: 4),
                  Text(t, textAlign: TextAlign.center, style: TextStyle(color: p.text.withOpacity(0.85), fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            );
        final features = Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(children: [
              featChip(Icons.lock_rounded, 'رمزنگاری امن'),
              const SizedBox(width: 8),
              featChip(Icons.bolt_rounded, 'سرعت بالا'),
              const SizedBox(width: 8),
              featChip(Icons.all_inclusive_rounded, 'بدون محدودیت'),
            ]),
          ),
        );

        final brandBlock = Column(children: [TourTarget('home.status', statusChip), TourTarget('home.features', features)]);

        final server = ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: Store.config,
          builder: (context, cfg, _) {
            final has = cfg != null;
            final name = has ? cfgTitle(cfg) : 'کانفیگ';
            final exp = has && '${cfg['expires']}'.isNotEmpty ? 'Valid Until: ${cfg['expires']}' : 'Valid Until: —';
            return Column(children: [
              Panel(
                onTap: () => _openLocations(1),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(children: [
                    Icon(Icons.storage_rounded, color: p.accent2, size: 42),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Flexible(child: Text(name, textDirection: TextDirection.rtl, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700))),
                          const SizedBox(width: 8),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: has ? const Color(0xFF29E07F) : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 5),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Text(exp, style: TextStyle(color: p.sub, fontSize: 13)),
                          const SizedBox(width: 8),
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: p.sub.withOpacity(0.6), shape: BoxShape.circle)),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              ),
              if (!has && _loading) const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator()),
            ]);
          },
        );

        final connect = SizedBox(
          height: wide ? 330 : 250,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(child: IgnorePointer(child: _Halo(color: on ? const Color(0xFF29E07F) : busy ? const Color(0xFFFFC53D) : p.accent2, strong: on || busy))),
            Positioned.fill(
              child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: Store.lite,
                    builder: (context, lite, _) => CustomPaint(isComplex: true, willChange: false, painter: GlobePainter(p.accent2, on, lite)),
                  ),
                ),
              ),
            ),
            if (on && kFancy)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: Store.lite,
                    builder: (_, lite, __) => lite ? const SizedBox.shrink() : const PulseRings(color: Color(0xFF29E07F)),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: SlideSwitch(on: on, busy: busy, onChanged: _toggle),
            ),
          ]),
        );

        final state = Panel(
          margin: const EdgeInsets.only(bottom: 4, top: 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(children: [
              Container(
                width: 46,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF070B1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF3B6BFF).withOpacity(0.25)),
                ),
                child: Icon(on ? Icons.check_rounded : Icons.keyboard_double_arrow_right_rounded,
                    color: on ? const Color(0xFF29E07F) : const Color(0xFF3D7BFF), size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(on ? 'متصل هستید' : 'برای اتصال، سوئیچ را به راست بکشید',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: on ? const Color(0xFF29E07F) : p.text, fontSize: 15)),
              ),
            ]),
          ),
        );

        final note = ValueListenableBuilder<String>(
          valueListenable: VpnService.I.note,
          builder: (context, n, _) => n.isEmpty
              ? const SizedBox(height: 8)
              : Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Center(child: Text(n, style: TextStyle(color: p.sub, fontSize: 12))),
                ),
        );

        final speeds = (!on || !Store.getBool('show_traffic', true)) ? const SizedBox.shrink() : TrafficCard(
          reader: () {
            final st = VpnService.I.status.value;
            return TrafficSample(
              on: st.phase == Phase.on,
              down: st.downSpeed,
              up: st.upSpeed,
              downTotal: st.down,
              upTotal: st.up,
              seconds: st.seconds,
            );
          },
        );

        final qualityButton = Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Panel(
            onTap: () => showIpQualitySheet(context),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: p.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.verified_user_rounded, color: p.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('بررسی اصالت و سلامت آی‌پی', style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(on ? 'تست نمره تقلب، نوع مسکونی و نشت ویژه آمازون و جمینای' : 'تست نمره سلامت و مشخصات آی‌پی اینترنت فعلی', style: TextStyle(color: p.sub, fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, color: p.sub.withOpacity(0.6), size: 13),
                ],
              ),
            ),
          ),
        );

        final awsAssistantButton = Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: Panel(
            onTap: () => showAwsAssistantSheet(context),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9900), Color(0xFFFF5500)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('دستیار دریافت ۱۰۰ دلار آمازون',
                                style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF29E07F).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text('۹۹٪ قبولی',
                                  style: TextStyle(color: Color(0xFF29E07F), fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('آماده‌سازی خودکار ویندوز + آدرس معتبر آمریکا + ثبت‌نام بدون کارت',
                            style: TextStyle(color: p.sub, fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, color: p.sub.withOpacity(0.6), size: 13),
                ],
              ),
            ),
          ),
        );

        if (!wide) {
          return RefreshIndicator(
            onRefresh: _refetch,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
              cacheExtent: 2400,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              children: [top, _Reveal(0, brandBlock), const SizedBox(height: 18), _Reveal(1, TourTarget('home.server', server)), _Reveal(2, TourTarget('home.connect', connect)), _Reveal(3, TourTarget('home.state', state)), const ConnectStages(), note, const SizedBox(height: 6), _Reveal(4, TourTarget('home.quality', qualityButton)), _Reveal(5, TourTarget('home.aws', awsAssistantButton)), speeds],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
          children: [
            _Reveal(0, brandBlock),
            const SizedBox(height: 26),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: Column(children: [_Reveal(2, TourTarget('home.connect', connect)), TourTarget('home.state', state), const ConnectStages(), note])),
              const SizedBox(width: 24),
              Expanded(flex: 4, child: Column(children: [_Reveal(1, TourTarget('home.server', server)), const SizedBox(height: 14), _Reveal(4, TourTarget('home.quality', qualityButton)), _Reveal(5, TourTarget('home.aws', awsAssistantButton)), speeds])),
            ]),
          ],
        );
      },
    );
  }

  Widget _speed(P p, IconData ic, String v, String l) => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(ic, color: p.accent2, size: 24),
          const SizedBox(width: 6),
          Text(v, style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        Text(l, style: TextStyle(color: p.sub, fontSize: 13)),
      ]);
}


/// هاله‌ی نورانی نرم پشت کره‌ی اتصال؛ با رنگ وضعیت می‌تپد.
class _Halo extends StatefulWidget {
  final Color color;
  final bool strong;
  const _Halo({required this.color, required this.strong});

  @override
  State<_Halo> createState() => _HaloState();
}

class _HaloState extends State<_Halo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Store.firstRun || MediaQuery.of(context).disableAnimations) return const SizedBox.shrink();
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_c.value);
          final a = (widget.strong ? 0.30 : 0.16) + 0.10 * t;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.55 + 0.08 * t,
                colors: [widget.color.withOpacity(a), widget.color.withOpacity(0)],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ورود نرم و یک‌باره‌ی بخش‌های صفحه‌ی خانه (محو + بالا آمدن)؛ فقط یک Tween سبک، بدون کنترلر.
class _Reveal extends StatelessWidget {
  final int index;
  final Widget child;
  const _Reveal(this.index, this.child);

  @override
  Widget build(BuildContext context) {
    if (!Store.firstRun || MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: c),
      ),
      child: child,
    );
  }
}

class LocationsPage extends StatefulWidget {
  final int initialTab;
  const LocationsPage({super.key, this.initialTab = 1});

  @override
  State<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends State<LocationsPage> {
  final Map<String, int> _ms = {};
  final Set<String> _rowPinging = {}; // ردیف‌هایی که همین الان فقط خودشان در حال تست‌اند
  bool _pinging = false;
  bool _busy = false;

  // فیلتر بالای لیست: all / premium / free / fav
  String _tab = 'all';
  bool _searching = false;
  String _query = '';
  final TextEditingController _searchCtl = TextEditingController();
  Set<String> _favs = {};

  @override
  void initState() {
    super.initState();
    // تست پینگ دیگر خودکار اجرا نمی‌شود؛
    // فقط با زدن دکمه‌ی «تست پینگ» (بالای صفحه) شروع می‌شود.
    // (نتایج پس‌زمینه‌ی قبلی هم نمایش داده نمی‌شود تا ورود به صفحه شبیه تست خودکار نباشد.)
    try {
      final raw = Store.getStr('favServers');
      if (raw.isNotEmpty) _favs = (jsonDecode(raw) as List).map((e) => '$e').toSet();
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _toggleFav(String id) async {
    setState(() {
      if (!_favs.add(id)) _favs.remove(id);
    });
    await Store.setStr('favServers', jsonEncode(_favs.toList()));
  }

  /// پینگ واقعی فقط یک کانفیگ (لمس چیپ پینگ همان ردیف)؛ بقیه‌ی کانفیگ‌ها تست نمی‌شوند.
  Future<void> _pingOne(Map<String, dynamic> c) async {
    final id = '${c['id']}';
    if (_pinging || _rowPinging.contains(id)) return;
    setState(() {
      _rowPinging.add(id);
      _ms.remove(id);
    });
    var ms = -1;
    try {
      ms = await VpnService.I.relayPing('${c['link']}', id: id);
    } catch (_) {
      ms = -1;
    }
    if (!mounted) return;
    setState(() {
      _rowPinging.remove(id);
      _ms[id] = ms;
    });
  }

  /// پینگ انتخاب‌شده: اگر لوکیشن/سرور مشخصی انتخاب شده فقط همان‌ها؛ در حالت «خودکار» همه.
  Future<void> _pingAll({bool onlySelected = false}) async {
    if (_pinging) return;
    final list = List<Map<String, dynamic>>.from(onlySelected ? Store.candidates() : Store.configs.value);
    if (list.isEmpty) return;
    if (list.length == 1) {
      await _pingOne(list.first);
      return;
    }
    // تست‌های پس‌زمینه‌ی قبلی لغو می‌شوند تا صف تست فقط مال همین اجرا باشد
    VpnService.I.cancelPings();
    setState(() {
      _pinging = true;
      for (final c in list) {
        _ms.remove('${c['id']}');
      }
    });
    final r = await _runPingTest(context, (ctl) async {
      ctl.total.value = list.length;
      Map<String, dynamic>? best;
      var bestMs = 1 << 30;

      void record(Map<String, dynamic> c, int ms) {
        if (ctl.cancelRequested) return; // بعد از «لغو» هیچ نتیجه‌ای ثبت/نمایش داده نمی‌شود
        if (Api.validPing(ms) && ms < bestMs) {
          bestMs = ms;
          best = c;
        }
        if (mounted) setState(() => _ms['${c['id']}'] = ms);
      }

      // همه‌ی کانفیگ‌ها تست می‌شوند (محدودیت ۳ تایی حذف شد)؛ همزمانی را خود VpnService کنترل می‌کند.
      Future<void> runPass(List<Map<String, dynamic>> items, int workers, bool report) async {
        var next = 0;
        Future<void> worker() async {
          while (mounted && !ctl.cancelRequested) {
            final i = next++;
            if (i >= items.length) return;
            final c = items[i];
            var ms = -1;
            try {
              ms = await VpnService.I.relayPing('${c['link']}', id: '${c['id']}');
            } catch (_) {
              ms = -1;
            }
            if (ctl.cancelRequested) return;
            if (report) {
              var nm = cfgTitle(c);
              if (nm.length > 16) nm = nm.substring(0, 16);
              ctl.addPing(PingRes(nm, ms));
            }
            if (ctl.cancelRequested) return;
            record(c, ms);
          }
        }

        await Future.wait([for (var k = 0; k < workers; k++) worker()]);
      }

      // مثل V2rayNG همه‌ی سرورها تست می‌شوند و هر سرور Timeout مخصوص خودش را دارد (۱۲ ثانیه از شروع واقعی تست)؛
      // پس بودجه‌ی کلی فقط یک سقف خیلی بزرگ است تا به‌خاطر طولانی‌شدن صف، سرورهای آخر Timeout نشوند.
      final firstBudget = Duration(seconds: list.length * 16 + 30);
      final alive = <Map<String, dynamic>>[];
      await Future.wait([
        for (final c in list)
          () async {
            final info = parseLink('${c['link']}');
            final tcpOk = info.outbound == null || info.engine != 'xray' || info.transport.contains('kcp') || info.transport.contains('quic') || await Api.pingLink('${c['link']}', timeoutSec: 2) >= 0;
            if (tcpOk) {
              alive.add(c);
            } else {
              record(c, -1);
            }
          }(),
      ]);
      alive.sort((a, b) => list.indexOf(a).compareTo(list.indexOf(b)));
      await runPass(alive, 1, true).timeout(firstBudget, onTimeout: () {});
      if (!ctl.cancelRequested && best == null) {
        final failed = [for (final c in list) if (!Api.validPing(_ms['${c['id']}'] ?? -1)) c];
        if (failed.isNotEmpty) {
          await runPass(failed.take(4).toList(), 1, false).timeout(const Duration(seconds: 40), onTimeout: () {});
        }
      }
      if (ctl.cancelRequested) return 'cancelled';
      final b = best;
      if (b == null) return 'no_valid_ping';
      var code = '${b['code'] ?? ''}';
      var name = '${b['country'] ?? ''}';
      if (code.length != 2) {
        final gc = Store.geoCache[Api.hostOf('${b['link'] ?? ''}')];
        if (gc is List && gc.length == 2) {
          if (name.isEmpty) name = '${gc[0]}';
          code = '${gc[1]}';
        }
      }
      ctl.code = code;
      ctl.name = name;
      ctl.sub = '$bestMs ms';
      return null;
    }, _errText);
    VpnService.I.pingCacheAt = DateTime.now(); // اتصال «خودکار» بعدی از همین نتایج تازه استفاده می‌کند
    VpnService.I.pingCacheRev.value++;
    if (mounted) {
      setState(() => _pinging = false);
      if (r != null && r != 'cancelled' && r != 'no_valid_ping') {
        _logConnFail('لیست سرورها / تست پینگ و اتصال', r);
        snack(context, _errText(r));
      }
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final ok = await Api.sync();
    if (mounted) {
      setState(() => _busy = false);
      if (!ok) unawaited(Api.logError('لیست سرورها / به‌روزرسانی', 'sync_failed', detail: Api.lastSyncError));
      snack(context, ok ? 'لیست به‌روز شد (${Store.configs.value.length} کانفیگ)' : 'سرور در دسترس نیست؛ کمی بعد دوباره تلاش کن');
    }
  }

  /// انتخاب لوکیشن. [connect] = true (دکمه‌ی فلش): به خانه برمی‌گردد و اتصال برقرار می‌شود.
  Future<void> _choose(String id, String label, {bool connect = false}) async {
    await Store.setServerId(id);
    Store.applySelection();
    if (!mounted) return;
    if (connect) {
      // همه‌ی صفحه‌های بالای خانه (کانفیگ‌ها، تنظیمات ...) بسته می‌شوند و خانه اتصال را شروع می‌کند
      Navigator.of(context).popUntil((r) => r.isFirst);
      homeConnectRequest.value++;
      return;
    }
    snack(context, 'انتخاب شد: $label');
    Navigator.pop(context);
  }

  void _addCustomConfig(BuildContext context, {Map<String, dynamic>? edit}) {
    final ctl = TextEditingController(text: edit == null ? '' : '${edit['link']}');
    final nameCtl = TextEditingController(text: edit == null ? '' : '${edit['name'] ?? ''}');
    final p = P.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(edit == null ? 'افزودن سرور شخصی' : 'ویرایش سرور شخصی', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('نام (اختیاری):', style: TextStyle(color: p.sub, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtl,
                style: TextStyle(color: p.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'سرور من',
                  hintStyle: TextStyle(color: p.sub.withOpacity(0.5)),
                  filled: true,
                  fillColor: p.bg,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.border)),
                ),
              ),
              const SizedBox(height: 12),
              Text('لینک کانفیگ (vless, vmess, trojan, ss, hy2, tuic, wireguard) را پیست کنید:', style: TextStyle(color: p.sub, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: ctl,
                maxLines: 3,
                style: TextStyle(color: p.text, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'vless://... vmess://... hy2://... tuic://... wireguard://...',
                  hintStyle: TextStyle(color: p.sub.withOpacity(0.5)),
                  filled: true,
                  fillColor: p.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.border)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.content_paste_rounded, size: 16),
                label: const Text('جای‌گذاری از کلیپ‌بورد'),
                onPressed: () async {
                  final d = await Clipboard.getData('text/plain');
                  if (d?.text != null) ctl.text = d!.text!.trim();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          ElevatedButton(
            onPressed: () async {
              final text = ctl.text.trim();
              if (text.isEmpty) return;
              final info = parseLink(text);
              if (info.outbound == null) {
                snack(context, 'لینک کانفیگ نامعتبر است');
                return;
              }
              final typed = nameCtl.text.trim();
              final name = typed.isNotEmpty ? typed : (info.name.isNotEmpty ? info.name : 'سرور شخصی');
              if (edit == null) {
                final newCfg = {
                  'id': 'custom-${DateTime.now().millisecondsSinceEpoch}',
                  'name': name,
                  'quotaGb': 0,
                  'expires': '',
                  'link': text,
                  'protocol': info.protocol,
                  'transport': info.transport,
                  'country': '',
                  'code': '',
                };
                await Store.addCustom(newCfg);
                await Store.setServerId('${newCfg['id']}');
                Store.applySelection();
                unawaited(Api.fillGeo());
                unawaited(Api.refreshConfigs());
              } else {
                final changedLink = '${edit['link']}' != text;
                final upd = Map<String, dynamic>.from(edit);
                upd['name'] = name;
                upd['link'] = text;
                upd['protocol'] = info.protocol;
                upd['transport'] = info.transport;
                if (changedLink) {
                  upd['country'] = '';
                  upd['code'] = '';
                  VpnService.I.pingCache.remove('${edit['id']}');
                }
                await Store.updateCustom('${edit['id']}', upd);
                if (changedLink) unawaited(Api.fillGeo());
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() {});
              snack(context, edit == null ? 'کانفیگ اضافه و انتخاب شد' : 'کانفیگ ویرایش شد');
              // تست پینگ خودکار حذف شده؛ فقط با دکمه‌ی «تست پینگ» اجرا می‌شود
              if (edit != null) _ms.remove('${edit['id']}');
            },
            child: Text(edit == null ? 'افزودن و انتخاب' : 'ذخیره'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCustom(Map<String, dynamic> c) async {
    final p = P.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('حذف سرور شخصی', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('«${cfgTitle(c)}» حذف شود؟', style: TextStyle(color: p.sub, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final id = '${c['id']}';
    if (VpnService.I.status.value.phase == Phase.on && Store.config.value != null && '${Store.config.value!['id']}' == id) {
      await VpnService.I.disconnect();
    }
    await Store.removeCustom(id);
    VpnService.I.pingCache.remove(id);
    _ms.remove(id);
    unawaited(Api.refreshConfigs());
    if (mounted) {
      setState(() {});
      snack(context, 'کانفیگ حذف شد');
    }
  }

  static const Color _kPurple = Color(0xFFB45CFF);
  static const Color _kGreenMs = Color(0xFF29E07F);

  Widget _roundBtn(P p, IconData icon, VoidCallback onTap, {String? tip}) => Tooltip(
        message: tip ?? '',
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, color: p.accent2, size: 27)),
        ),
      );

  Widget _header(P p) => Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 8),
          child: Row(children: [
            _roundBtn(p, Icons.chevron_left_rounded, () => Navigator.maybePop(context)),
            const SizedBox(width: 2),
            Expanded(
              child: _searching
                  ? TextField(
                      controller: _searchCtl,
                      autofocus: true,
                      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                      style: TextStyle(color: p.text, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Search',
                        hintStyle: TextStyle(color: p.sub),
                        isDense: true,
                        filled: true,
                        fillColor: p.card,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.border.withOpacity(0.6))),
                      ),
                    )
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.layers_rounded, color: p.accent2, size: 30),
                      const SizedBox(width: 10),
                      Text('Config', style: TextStyle(color: p.text, fontSize: 24, fontWeight: FontWeight.w800)),
                    ]),
            ),
            const SizedBox(width: 6),
            // دکمه‌ی «تست پینگ» گوشه‌ی بالا؛ تنها راه شروع تست پینگ
            GestureDetector(
              onTap: _pinging
                  ? () {
                      _activePing?.cancel();
                      VpnService.I.cancelPings();
                    }
                  : () => _pingAll(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [p.accent, p.accent2]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: p.accent.withOpacity(0.4), blurRadius: 10)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _pinging
                      ? const Icon(Icons.close_rounded, color: Colors.white, size: 17)
                      : const Icon(Icons.speed_rounded, color: Colors.white, size: 17),
                  const SizedBox(width: 5),
                  Text(_pinging ? 'لغو' : 'تست پینگ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(width: 2),
            _roundBtn(p, _searching ? Icons.close_rounded : Icons.search_rounded, () {
              setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _query = '';
                  _searchCtl.clear();
                }
              });
            }),
          ]),
        ),
      );

  Widget _banner(P p) => Container(
        height: 132,
        margin: const EdgeInsets.fromLTRB(16, 2, 16, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.accent.withOpacity(0.55)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A1B52), Color(0xFF1546C4), Color(0xFF0B2A86)],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(children: [
            Positioned(right: -34, top: -30, child: Container(width: 190, height: 190, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFF55B5FF).withOpacity(0.55), Colors.transparent])))),
            Positioned(right: 26, top: 22, child: Icon(Icons.verified_user_rounded, size: 78, color: const Color(0xFF7CC4FF).withOpacity(0.92))),
            Positioned(
              left: 18,
              bottom: 14,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  const Text('Choose Your\nBest Config', style: TextStyle(color: Colors.white, fontSize: 24, height: 1.1, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Fast  •  Secure  •  Global', style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
      );

  Widget _chipBtn(P p, String key, String label, {IconData? icon}) {
    final sel = _tab == key;
    return Expanded(
      flex: icon == null ? 3 : 1,
      child: GestureDetector(
        onTap: () => setState(() => _tab = key),
        child: Container(
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            gradient: sel ? LinearGradient(colors: [p.accent2, p.accent]) : null,
            color: sel ? null : p.card.withOpacity(0.7),
            border: Border.all(color: sel ? Colors.transparent : p.border.withOpacity(0.7)),
            boxShadow: sel ? [BoxShadow(color: p.accent.withOpacity(0.45), blurRadius: 12)] : null,
          ),
          child: icon != null
              ? Icon(icon, color: sel ? Colors.white : p.text, size: 22)
              : Text(label, style: TextStyle(color: sel ? Colors.white : p.text, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _chips(P p) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [
            _chipBtn(p, 'all', 'All'),
            _chipBtn(p, 'premium', 'Premium'),
            _chipBtn(p, 'free', 'Free'),
            _chipBtn(p, 'fav', '', icon: Icons.star_rounded),
          ]),
        ),
      );

  Widget _pingText(P p, String id) {
    final v = _ms[id];
    final Widget w;
    if (_rowPinging.contains(id) || (v == null && _pinging)) {
      w = const PingSpinner(key: ValueKey('spin'));
    } else if (v == null) {
      w = Text('—', key: const ValueKey('none'), style: TextStyle(color: p.sub, fontSize: 15));
    } else if (!Api.validPing(v)) {
      w = const Text('Timeout', key: ValueKey('to'), style: TextStyle(color: _kPurple, fontSize: 16, fontWeight: FontWeight.w800));
    } else {
      w = Text('$v ms', key: ValueKey('ms$v'), style: const TextStyle(color: _kGreenMs, fontSize: 17, fontWeight: FontWeight.w800));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween<double>(begin: 0.7, end: 1).animate(a), child: c)),
      child: w,
    );
  }

  Widget _leadIcon(P p, String code, bool timedOut) {
    final hasFlag = code.length == 2 && !timedOut;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasFlag ? p.card : const Color(0xFF2A1F5E),
        border: Border.all(color: p.border.withOpacity(0.6)),
      ),
      child: hasFlag
          ? Text(flagOf(code), style: const TextStyle(fontSize: 26))
          : Icon(timedOut ? Icons.access_time_rounded : Icons.public_rounded, color: const Color(0xFFC9B8FF), size: 25),
    );
  }

  Widget _rowShell(P p, {required bool selected, required Widget child, VoidCallback? onTap, VoidCallback? onLong}) => Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(colors: [p.card.withOpacity(0.95), p.bg.withOpacity(0.9)]),
          border: Border.all(color: selected ? p.accent2 : p.border.withOpacity(0.55), width: selected ? 1.6 : 1),
          boxShadow: selected ? [BoxShadow(color: p.accent.withOpacity(0.35), blurRadius: 14)] : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: onTap,
            onLongPress: onLong,
            child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 8), child: child),
          ),
        ),
      );

  /// دکمه‌ی فلش: لوکیشن را انتخاب می‌کند، به خانه می‌رود و اتصال را برقرار می‌کند.
  Widget _arrowBtn(P p, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.accent2.withOpacity(0.8), width: 1.4)),
          child: Icon(Icons.chevron_right_rounded, color: p.text, size: 26),
        ),
      );

  Widget _autoRow(P p, String sid) {
    final sel = sid.isEmpty || sid.startsWith('loc:');
    return _rowShell(
      p,
      selected: sel,
      onTap: () => _choose('', 'خودکار'),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.card, border: Border.all(color: p.border.withOpacity(0.6))),
            child: const Icon(Icons.bolt_rounded, color: Colors.amber, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('Best Server', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w700))),
          _arrowBtn(p, () => _choose('', 'خودکار', connect: true)),
        ]),
      ),
    );
  }

  Widget _cfgRow(P p, Map<String, dynamic> c, String sid) {
    final id = '${c['id']}';
    final code = '${c['code'] ?? ''}';
    final v = _ms[id];
    final timedOut = v != null && !Api.validPing(v);
    final fav = _favs.contains(id);
    return _rowShell(
      p,
      selected: sid == id,
      onTap: () => _choose(id, cfgTitle(c)),
      onLong: () {
        _toggleFav(id);
        snack(context, fav ? 'از علاقه‌مندی‌ها حذف شد' : 'به علاقه‌مندی‌ها اضافه شد');
      },
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [
          _leadIcon(p, code, timedOut),
          const SizedBox(width: 12),
          Expanded(
            child: Row(children: [
              Flexible(child: Text(cfgTitle(c), overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w700))),
              if (fav) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.star_rounded, color: Colors.amber, size: 16)),
            ]),
          ),
          if (Store.isCustom(c)) ...[
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _addCustomConfig(context, edit: c),
              child: Padding(padding: const EdgeInsets.all(5), child: Icon(Icons.edit_rounded, size: 18, color: p.accent2)),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _deleteCustom(c),
              child: const Padding(padding: EdgeInsets.all(5), child: Icon(Icons.delete_outline_rounded, size: 19, color: Colors.redAccent)),
            ),
          ],
          // لمس پینگ همان ردیف = تست فقط همین سرور (باز هم فقط با لمس کاربر)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pingOne(c),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: _pingText(p, id)),
          ),
          _arrowBtn(p, () => _choose(id, cfgTitle(c), connect: true)),
        ]),
      ),
    );
  }

  Widget _premiumSoon(P p) => Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(colors: [p.card.withOpacity(0.95), p.bg.withOpacity(0.9)]),
          border: Border.all(color: p.border.withOpacity(0.7)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF2A1F5E), border: Border.all(color: _kPurple.withOpacity(0.7))),
            child: const Icon(Icons.lock_rounded, color: Color(0xFFC9B8FF), size: 38),
          ),
          const SizedBox(height: 16),
          Text('Premium', style: TextStyle(color: p.text, fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('به زودی می‌آید', style: TextStyle(color: p.sub, fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _empty(P p, String text) => Padding(
        padding: const EdgeInsets.all(30),
        child: Center(child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: p.sub))),
      );

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: AppBg(
        child: SafeArea(
          child: Column(children: [
            _header(p),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: Store.configs,
                  builder: (context, list, _) {
                    final sid = Store.serverId;
                    final children = <Widget>[_banner(p), _chips(p)];
                    if (_tab == 'premium') {
                      children.add(_premiumSoon(p));
                    } else if (list.isEmpty) {
                      children.add(_empty(p, 'کانفیگی وجود ندارد؛ بکش پایین تا به‌روز شود'));
                    } else {
                      var shown = List<Map<String, dynamic>>.from(list);
                      if (_tab == 'fav') shown = [for (final c in shown) if (_favs.contains('${c['id']}')) c];
                      if (_query.isNotEmpty) {
                        shown = [
                          for (final c in shown)
                            if (cfgTitle(c).toLowerCase().contains(_query) || '${c['country'] ?? ''}'.toLowerCase().contains(_query)) c
                        ];
                      }
                      int rank(Map<String, dynamic> c) {
                        final v = _ms['${c['id']}'];
                        if (v == null) return 1 << 29;
                        if (!Api.validPing(v)) return 1 << 30;
                        return v;
                      }
                      // مرتب‌سازی پایدار: بعد از تست، کمترین پینگ بالاتر؛ قبل از تست ترتیب اصلی لیست
                      final idx = {for (var i = 0; i < shown.length; i++) '${shown[i]['id']}': i};
                      shown.sort((a, b) {
                        final r = rank(a).compareTo(rank(b));
                        return r != 0 ? r : idx['${a['id']}']!.compareTo(idx['${b['id']}']!);
                      });
                      if (_tab != 'fav' && _query.isEmpty) children.add(_autoRow(p, sid));
                      if (shown.isEmpty) {
                        children.add(_empty(p, _tab == 'fav' ? 'هنوز علاقه‌مندی‌ای نداری؛ روی یک لوکیشن نگه دار' : 'موردی پیدا نشد'));
                      } else {
                        for (final c in shown) {
                          children.add(_cfgRow(p, c, sid));
                        }
                      }
                    }
                    if (_tab != 'premium') {
                      children.add(_rowShell(
                        p,
                        selected: false,
                        onTap: () => _addCustomConfig(context),
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: p.card, border: Border.all(color: p.border.withOpacity(0.6))),
                              child: Icon(Icons.add_link_rounded, color: p.accent2, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text('افزودن سرور شخصی', style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w700))),
                          ]),
                        ),
                      ));
                    }
                    if (_busy) children.add(const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())));
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 24),
                      children: children,
                    );
                  },
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class PinIcon extends StatefulWidget {
  final double size;
  final Color color;
  final bool animate;
  const PinIcon({super.key, this.size = 48, required this.color, this.animate = true});

  @override
  State<PinIcon> createState() => _PinIconState();
}

class _PinIconState extends State<PinIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(children: [
          if (widget.animate)
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => CustomPaint(painter: _RingPainter(_c.value, widget.color)),
                ),
              ),
            )
          else
            Positioned.fill(child: CustomPaint(painter: _RingPainter(-1, widget.color))),
          Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _PinBodyPainter(widget.color)))),
        ]),
      );
}

class _RingPainter extends CustomPainter {
  final double t; // -1 = حلقه‌ی ثابت
  final Color color;
  _RingPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final base = Offset(s / 2, s * 0.88);
    if (t >= 0) {
      for (var i = 0; i < 2; i++) {
        final k = (t + i * 0.5) % 1.0;
        canvas.drawOval(
          Rect.fromCenter(center: base, width: s * (0.2 + 0.7 * k), height: s * (0.08 + 0.2 * k)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = color.withOpacity((1 - k) * 0.8),
        );
      }
    } else {
      canvas.drawOval(
        Rect.fromCenter(center: base, width: s * 0.34, height: s * 0.1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withOpacity(0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t || old.color != color;
}

class _PinBodyPainter extends CustomPainter {
  final Color color;
  _PinBodyPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cx = s / 2;
    final c = Offset(cx, s * 0.38);
    final r = s * 0.27;
    final body = Path.combine(
      PathOperation.union,
      Path()..addOval(Rect.fromCircle(center: c, radius: r)),
      Path()
        ..moveTo(c.dx - r * 0.88, c.dy + r * 0.45)
        ..lineTo(cx, s * 0.86)
        ..lineTo(c.dx + r * 0.88, c.dy + r * 0.45)
        ..close(),
    );
    canvas.drawPath(
      body,
      Paint()
        ..color = color.withOpacity(0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.07,
    );
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, color, const Color(0xFF1F6FE0)],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, s, s)),
    );
    canvas.drawCircle(c, r * 0.42, Paint()..color = const Color(0xFF040A1C));
    canvas.drawCircle(c, r * 0.2, Paint()..color = Colors.white.withOpacity(0.9));
  }

  @override
  bool shouldRepaint(covariant _PinBodyPainter old) => old.color != color;
}

const int _kSpark = 40;

List<String> _spd(num b) {
  if (b < 1024) return [b.toInt().toString(), 'B/s'];
  if (b < 1048576) return [(b / 1024).toStringAsFixed(1), 'KB/s'];
  if (b < 1073741824) return [(b / 1048576).toStringAsFixed(2), 'MB/s'];
  return [(b / 1073741824).toStringAsFixed(2), 'GB/s'];
}

class _SparkPainter extends CustomPainter {
  final List<double> dl, ul;
  _SparkPainter(this.dl, this.ul, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    var peak = 1.0;
    for (final v in dl) {
      if (v > peak) peak = v;
    }
    for (final v in ul) {
      if (v > peak) peak = v;
    }
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    void line(List<double> v, Color c) {
      if (v.length < 2) return;
      final path = Path();
      final fill = Path();
      double firstX = 0, lastX = 0;
      for (var i = 0; i < v.length; i++) {
        final x = size.width * (i + (_kSpark - v.length)) / (_kSpark - 1);
        final y = size.height - 4 - (v[i] / peak) * (size.height - 10);
        if (i == 0) {
          firstX = x;
          path.moveTo(x, y);
          fill.moveTo(x, size.height);
          fill.lineTo(x, y);
        } else {
          path.lineTo(x, y);
          fill.lineTo(x, y);
        }
        lastX = x;
      }
      fill.lineTo(lastX, size.height);
      fill.lineTo(firstX, size.height);
      fill.close();
      canvas.drawPath(fill, Paint()..color = c.withOpacity(0.16));
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    line(dl, const Color(0xFF3FA9FF));
    line(ul, const Color(0xFF29E07F));
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => true;
}

class ConnPopup extends StatefulWidget {
  const ConnPopup({super.key});

  @override
  State<ConnPopup> createState() => _ConnPopupState();
}

class _ConnPopupState extends State<ConnPopup> {
  bool _closing = false;
  final List<double> _dl = [];
  final List<double> _ul = [];
  final ValueNotifier<int> _rev = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _push(VpnService.I.status.value);
    VpnService.I.status.addListener(_watch);
  }

  @override
  void dispose() {
    VpnService.I.status.removeListener(_watch);
    _rev.dispose();
    super.dispose();
  }

  void _push(VpnStatus s) {
    _dl.add(s.downSpeed.toDouble());
    _ul.add(s.upSpeed.toDouble());
    if (_dl.length > _kSpark) _dl.removeAt(0);
    if (_ul.length > _kSpark) _ul.removeAt(0);
  }

  void _watch() {
    final s = VpnService.I.status.value;
    if (s.phase == Phase.on) {
      _push(s);
      _rev.value++;
    }
    if (s.phase != Phase.off || _closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final r = ModalRoute.of(context);
      if (r != null && r.isCurrent) Navigator.of(context).pop();
    });
  }

  Widget _tile(P p, IconData ic, Color a, Color b, String label, num speed) {
    final v = _spd(speed);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a.withOpacity(0.30), b.withOpacity(0.08)]),
          border: Border.all(color: a.withOpacity(0.55)),
        ),
        child: Column(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: a.withOpacity(0.25)),
            child: Icon(ic, color: a, size: 22),
          ),
          const SizedBox(height: 8),
          FittedBox(
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(v[0], style: TextStyle(color: p.text, fontSize: 30, fontWeight: FontWeight.w900)),
              const SizedBox(width: 4),
              Text(v[1], style: TextStyle(color: a, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: p.sub, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _chip(P p, IconData ic, Color col, String v, String l) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: col.withOpacity(0.09),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: col.withOpacity(0.40)),
          ),
          child: Column(children: [
            Icon(ic, color: col, size: 20),
            const SizedBox(height: 4),
            FittedBox(child: Text(v, textDirection: TextDirection.ltr, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w800))),
            const SizedBox(height: 1),
            Text(l, style: TextStyle(color: p.sub, fontSize: 11)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    const green = Color(0xFF29E07F);
    const blue = Color(0xFF3FA9FF);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0E2350), Color(0xFF071230)]),
            border: Border.all(color: green.withOpacity(0.55), width: 1.3),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(shape: BoxShape.circle, color: green.withOpacity(0.10), border: Border.all(color: green.withOpacity(0.35))),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3DF08E), Color(0xFF0FA862)]),
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 38),
                ),
              ),
              const SizedBox(height: 10),
              const Text('شما متصل شدید', style: TextStyle(color: green, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              ValueListenableBuilder<Geo?>(
                valueListenable: VpnService.I.geo,
                builder: (context, g, _) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: p.border.withOpacity(0.6)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(g == null ? '🌐' : g.flag, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Text(g == null ? 'در حال تشخیص لوکیشن...' : g.country, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<VpnStatus>(
                valueListenable: VpnService.I.status,
                builder: (context, s, _) => Directionality(
                  textDirection: TextDirection.ltr,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      _tile(p, Icons.arrow_downward_rounded, blue, const Color(0xFF1F6FE0), 'دانلود', s.downSpeed),
                      const SizedBox(width: 10),
                      _tile(p, Icons.arrow_upward_rounded, green, const Color(0xFF0B8F52), 'آپلود', s.upSpeed),
                    ]),
                    const SizedBox(height: 10),
                    Container(
                      height: 88,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.border.withOpacity(0.45)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: RepaintBoundary(child: CustomPaint(painter: _SparkPainter(_dl, _ul, _rev))),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      _chip(p, Icons.download_done_rounded, blue, fmtBytes(s.down), 'مجموع دانلود'),
                      const SizedBox(width: 8),
                      _chip(p, Icons.upload_rounded, green, fmtBytes(s.up), 'مجموع آپلود'),
                      const SizedBox(width: 8),
                      _chip(p, Icons.timer_rounded, Colors.amber, fmtDuration(s.seconds), 'زمان'),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () => VpnService.I.disconnect(),
                    child: const Text('قطع اتصال', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.accent,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('بستن', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _serverLabel() {
    final sid = Store.serverId;
    if (sid.isEmpty) return 'بهترین سرور نزدیک شما';
    if (sid.startsWith('loc:')) {
      final l = Store.locations().where((e) => e['key'] == sid.substring(4));
      if (l.isNotEmpty) return '${flagOf('${l.first['code']}')} ${l.first['country']}';
    }
    return 'انتخاب دستی';
  }

  String _themeLabel() {
    switch (Store.themeMode.value) {
      case ThemeMode.light:
        return 'روشن';
      case ThemeMode.system:
        return 'هماهنگ با سیستم';
      default:
        return 'تاریک';
    }
  }

  void _pickTheme() {
    final p = P.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) {
        final mode = Store.themeMode.value;
        Widget opt(ThemeMode m, IconData ic, String t, Color col) => STile(
              icon: ic,
              iconColor: col,
              title: t,
              onTap: () async {
                await Store.setTheme(m);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
              },
              trailing: Icon(mode == m ? Icons.radio_button_checked : Icons.radio_button_off, color: mode == m ? p.accent2 : p.sub, size: 26),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('ظاهر برنامه', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              opt(ThemeMode.dark, Icons.dark_mode_rounded, 'حالت تاریک', const Color(0xFF5B5FE6)),
              opt(ThemeMode.light, Icons.light_mode_rounded, 'حالت روشن', const Color(0xFFFFA726)),
              opt(ThemeMode.system, Icons.phone_android_rounded, 'هماهنگ با سیستم', const Color(0xFF00A3BF)),
            ]),
          ),
        );
      },
    );
  }

  void _editName() {
    final p = P.of(context);
    final ctl = TextEditingController(text: Store.userName.value);
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: p.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text('نام شما', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w800)),
          content: TextField(
            controller: ctl,
            autofocus: true,
            maxLength: 24,
            style: TextStyle(color: p.text, fontSize: 16),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'نام شما',
              hintStyle: TextStyle(color: p.sub.withOpacity(0.7)),
              filled: true,
              fillColor: p.bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('انصراف', style: TextStyle(color: p.sub))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: p.accent),
              onPressed: () async {
                if (ctl.text.trim().isNotEmpty) await Store.setUserName(ctl.text);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openGuide() async {
    final a = await showIntroPicker(context);
    if (a == null || !mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    await Tour.launch?.call(a.anim, a.buddy);
  }

  Widget _profile(P p) {
    return ValueListenableBuilder<String>(
      valueListenable: Store.userName,
      builder: (context, name, _) => SCard(children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              await Navigator.push(context, adaptiveRoute((_) => const ProfilePage()));
              if (mounted) setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(children: [
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name.isEmpty ? 'کاربر NEXORA' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('پروفایل · آمار و گزینه‌های شخصی', style: TextStyle(color: p.sub, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text('Version $kAppVersion', textDirection: TextDirection.ltr, style: TextStyle(color: p.accent2, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  Icon(Icons.chevron_left_rounded, color: p.sub, size: 28),
                ]),
              ),
            ),
          ),
        ),
        STile(
          icon: Icons.pets_rounded,
          iconColor: const Color(0xFFFF4FA3),
          title: 'راهنما',
          subtitle: 'انتخاب راهنما و آموزش قدم‌به‌قدم',
          onTap: _openGuide,
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return SettingsScaffold(title: 'تنظیمات', children: [
      _profile(p),
      const SSection('کانفیگ و اتصال'),
      SCard(children: [
        ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: Store.config,
          builder: (context, cfg, _) => STile(
            icon: Icons.storage_rounded,
            iconColor: const Color(0xFF3D7BFF),
            title: cfg == null ? 'کانفیگ' : cfgTitle(cfg),
            subtitle: cfg != null && '${cfg['expires']}'.isNotEmpty ? 'اعتبار: ${cfg['expires']}' : 'دریافت نشده',
            onTap: () => Navigator.push(context, adaptiveRoute((_) => const LocationsPage(initialTab: 1))),
          ),
        ),
        STile(
          icon: Icons.bolt_rounded,
          iconColor: const Color(0xFFFFA726),
          title: 'اتصال خودکار',
          subtitle: 'در هنگام شروع برنامه',
          trailing: SToggle(
              value: Store.getBool('autoConnect', false),
              onChanged: (v) async {
                await Store.setBool('autoConnect', v);
                setState(() {});
              }),
        ),
        STile(
          icon: Icons.public_rounded,
          iconColor: const Color(0xFF00A3BF),
          title: 'انتخاب سرور دلخواه',
          subtitle: _serverLabel(),
          onTap: () async {
            await Navigator.push(context, adaptiveRoute((_) => const LocationsPage()));
            if (mounted) setState(() {});
          },
        ),
      ]),
      const SSection('عمومی'),
      SCard(children: [
        STile(
          icon: Icons.contrast_rounded,
          iconColor: const Color(0xFF00A3BF),
          title: 'ظاهر',
          value: _themeLabel(),
          onTap: _pickTheme,
        ),
        STile(
          icon: Icons.notifications_rounded,
          iconColor: const Color(0xFFFFA726),
          title: 'اعلان اتصال',
          trailing: SToggle(
              value: Store.getBool('notif', true),
              onChanged: (v) async {
                await Store.setBool('notif', v);
                setState(() {});
              }),
        ),
        STile(
          icon: Icons.system_update_rounded,
          iconColor: const Color(0xFF5B5FE6),
          title: 'به‌روزرسانی',
          subtitle: 'Update',
          onTap: () => Navigator.push(context, adaptiveRoute((_) => const UpdatePage())),
        ),
        STile(
          icon: Icons.tune_rounded,
          iconColor: const Color(0xFF8E8E93),
          title: 'تنظیمات پیشرفته',
          onTap: () => Navigator.push(context, adaptiveRoute((_) => const AdvancedPage())),
        ),
      ]),
    ]);
  }
}

class AdvancedPage extends StatefulWidget {
  const AdvancedPage({super.key});

  @override
  State<AdvancedPage> createState() => _AdvancedPageState();
}

class _AdvancedPageState extends State<AdvancedPage> {
  Widget _sw(IconData ic, Color col, String t, String sub, String key, bool def) => STile(
        icon: ic,
        iconColor: col,
        title: t,
        subtitle: sub,
        trailing: SToggle(
            value: Store.getBool(key, def),
            onChanged: (v) async {
              await Store.setBool(key, v);
              setState(() {});
            }),
      );

  void _editUpstreamProxy(BuildContext context) {
    final ctl = TextEditingController(text: Store.upstreamProxy);
    var enabled = Store.upstreamProxyEnabled;
    final p = P.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: p.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('پروکسی زنجیره‌ای مسکونی', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'با اتصال پروکسی مسکونی (Residential SOCKS5)، ترافیک ابتدا از سرور ضد فیلتر و سپس از آی‌پی خانگی خارج می‌شود تا آمازون و پی‌پال شما را کاربر واقعی خانگی تشخیص دهند.',
                style: TextStyle(color: p.sub, fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('فعال‌سازی پروکسی بالادست', style: TextStyle(color: p.text, fontSize: 13.5)),
                  Toggle(
                    value: enabled,
                    onChanged: (v) => setDState(() => enabled = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctl,
                style: TextStyle(color: p.text, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'آدرس پروکسی (SOCKS5 یا HTTP)',
                  hintText: 'socks5://user:pass@host:port',
                  labelStyle: TextStyle(color: p.sub, fontSize: 12.5),
                  hintStyle: TextStyle(color: p.sub.withOpacity(0.5), fontSize: 12),
                  filled: true,
                  fillColor: p.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('انصراف', style: TextStyle(color: p.sub)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: p.accent, foregroundColor: Colors.white),
              onPressed: () async {
                await Store.setUpstreamProxy(ctl.text);
                await Store.setUpstreamProxyEnabled(enabled);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
                if (context.mounted) snack(context, 'تنظیمات پروکسی زنجیره‌ای ذخیره شد');
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
  }

  static const List<String> _offLabels = ['خاموش', '۱ ساعت', '۲ ساعت', '۴ ساعت', '۸ ساعت', '۱۲ ساعت'];
  static const List<int> _offValues = [0, 1, 2, 4, 8, 12];
  static const List<String> _remindLabels = ['خاموش', '۱ ساعت', '۲ ساعت', '۴ ساعت', '۶ ساعت'];
  static const List<int> _remindValues = [0, 1, 2, 4, 6];
  static const List<String> _capLabels = ['خاموش', '۱ گیگابایت', '۵ گیگابایت', '۱۰ گیگابایت', '۲۰ گیگابایت', '۵۰ گیگابایت'];
  static const List<int> _capValues = [0, 1, 5, 10, 20, 50];
  static const List<String> _dnsLabels = ['پیش‌فرض', 'Cloudflare (1.1.1.1)', 'Google (8.8.8.8)', 'Quad9 (9.9.9.9)', 'AdGuard (ضد تبلیغ)'];
  static const List<int> _dnsValues = [0, 1, 2, 3, 4];
  static const List<String> _alertLabels = ['خاموش', '۵۰۰ مگابایت', '۱ گیگابایت', '۲ گیگابایت', '۵ گیگابایت', '۱۰ گیگابایت'];
  static const List<int> _alertValues = [0, 500, 1024, 2048, 5120, 10240];

  String _labelOf(List<String> labels, List<int> values, int cur) {
    final i = values.indexOf(cur);
    return i < 0 ? labels.first : labels[i];
  }

  void _pick(String title, List<String> labels, List<int> values, int current, Future<void> Function(int) onPick) {
    final p = P.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (var i = 0; i < labels.length; i++)
                STile(
                  icon: values[i] == current ? Icons.check_rounded : Icons.circle_outlined,
                  iconColor: values[i] == current ? const Color(0xFF30D158) : p.sub,
                  title: labels[i],
                  onTap: () async {
                    await onPick(values[i]);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  },
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _copyDiag() async {
    final up = Store.statUp, down = Store.statDown;
    final txt = [
      'NEXORA $kAppVersion',
      'platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'device: ${Store.deviceId}',
      'sessions: ${Store.statSessions}  traffic: ${fmtBytes(up + down)}',
      'autoOff: ${Store.autoOffHours}h  usageAlert: ${Store.usageAlertMb}MB  confirmDisconnect: ${Store.confirmDisconnect}',
      'upstream: ${Store.upstreamProxyEnabled}  lite: ${Store.lite.value}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: txt));
    if (mounted) snack(context, 'گزارش تشخیصی کپی شد');
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(title: 'تنظیمات پیشرفته', children: [
      const SSection('اتصال و امنیت'),
      SCard(children: [
        _sw(Icons.security_rounded, Colors.amberAccent, 'حالت ضد فیلترینگ شدید (Stealth Fragment)', 'تکه‌تکه کردن پکت‌های TLS برای عبور از سد همراه اول و ایرانسل', 'stealth_fragment', true),
        _sw(Icons.access_time_filled_rounded, const Color(0xFF29E07F), 'همگام‌سازی خودکار منطقه زمانی ویندوز (Auto-Timezone)', 'تنظیم خودکار ساعت ویندوز با لوکیشن سرور برای دور زدن فیلترهای ضد تقلب آمازون و جمینای', 'auto_timezone_sync', true),
        STile(
          icon: Icons.alt_route_rounded,
          iconColor: const Color(0xFF33B5FF),
          title: 'پروکسی زنجیره‌ای مسکونی (Residential Upstream)',
          subtitle: Store.upstreamProxyEnabled && Store.upstreamProxy.isNotEmpty
              ? 'فعال: ${Store.upstreamProxy}'
              : 'اتصال خروجی به آی‌پی خانگی/تمیز برای ثبت‌نام آمازون و پی‌پال',
          onTap: () => _editUpstreamProxy(context),
        ),
        STile(
          icon: Icons.timer_off_rounded,
          iconColor: const Color(0xFFFF6B6B),
          title: 'قطع خودکار اتصال',
          subtitle: 'بعد از این مدت، اتصال خودش قطع می‌شود',
          value: _labelOf(_offLabels, _offValues, Store.autoOffHours),
          onTap: () => _pick('قطع خودکار اتصال', _offLabels, _offValues, Store.autoOffHours, (v) => Store.setInt('auto_off_h', v)),
        ),
        _sw(Icons.front_hand_rounded, const Color(0xFFFFA726), 'تأیید قبل از قطع اتصال', 'با لمس دکمه‌ی خانه، قبل از قطع یک بار می‌پرسد (جلوگیری از قطع اتفاقی)', 'confirm_disconnect', false),
      ]),
      const SSection('شبکه و ترافیک (تخصصی)'),
      SCard(children: [
        STile(
          icon: Icons.dns_rounded,
          iconColor: const Color(0xFF33B5FF),
          title: 'سرور DNS',
          subtitle: 'DNS ترجیحی هنگام اتصال؛ AdGuard تبلیغات و ردیاب‌ها را هم می‌بندد',
          value: _labelOf(_dnsLabels, _dnsValues, Store.getInt('dns_choice', 0)),
          onTap: () => _pick('سرور DNS', _dnsLabels, _dnsValues, Store.getInt('dns_choice', 0), (v) => Store.setInt('dns_choice', v)),
        ),
        _sw(Icons.block_rounded, const Color(0xFFE5484D), 'مسدود کردن QUIC (UDP 443)', 'ترافیک QUIC بسته می‌شود تا برنامه‌ها به TCP برگردند؛ برای سرورهایی که UDP را کند یا قطع می‌کنند', 'block_quic', false),
        _sw(Icons.downloading_rounded, const Color(0xFFFFA726), 'مسدود کردن تورنت', 'ترافیک BitTorrent از مسیر VPN رد نمی‌شود', 'block_torrent', false),
        _sw(Icons.shield_rounded, const Color(0xFF14B87D), 'جلوگیری از نشت IP در WebRTC', 'بستن درگاه‌های STUN/TURN تا آی‌پی واقعی از مرورگر لو نرود', 'block_stun', true),
        _sw(Icons.merge_type_rounded, const Color(0xFF8E5BFF), 'ترکیب اتصال‌ها (Mux)', 'چند اتصال روی یک تونل؛ اتصال اولیه‌ی سایت‌ها سریع‌تر می‌شود (برای کانفیگ‌های Vision خودکار رد می‌شود)', 'mux_on', false),
      ]),
      const SSection('مصرف و هشدار'),
      SCard(children: [
        STile(
          icon: Icons.data_usage_rounded,
          iconColor: const Color(0xFFFFA726),
          title: 'هشدار مصرف هر اتصال',
          subtitle: 'وقتی مصرف همین اتصال به این حد رسید، در صفحه‌ی خانه خبر می‌دهد',
          value: _labelOf(_alertLabels, _alertValues, Store.usageAlertMb),
          onTap: () => _pick('هشدار مصرف هر اتصال', _alertLabels, _alertValues, Store.usageAlertMb, (v) => Store.setInt('usage_alert_mb', v)),
        ),
        STile(
          icon: Icons.notifications_active_rounded,
          iconColor: const Color(0xFFFFA726),
          title: 'یادآوری اتصال طولانی',
          subtitle: 'اگر مدت زیادی وصل بودی در صفحه‌ی خانه یادآوری می‌کند',
          value: _labelOf(_remindLabels, _remindValues, Store.getInt('remind_h', 0)),
          onTap: () => _pick('یادآوری اتصال طولانی', _remindLabels, _remindValues, Store.getInt('remind_h', 0), (v) => Store.setInt('remind_h', v)),
        ),
        STile(
          icon: Icons.donut_large_rounded,
          iconColor: const Color(0xFFE5484D),
          title: 'سقف مصرف کل این دستگاه',
          subtitle: 'وقتی مصرف کل (از آخرین پاک‌سازی آمار) به این حد برسد خبر می‌دهد',
          value: _labelOf(_capLabels, _capValues, Store.getInt('total_cap_gb', 0)),
          onTap: () => _pick('سقف مصرف کل', _capLabels, _capValues, Store.getInt('total_cap_gb', 0), (v) => Store.setInt('total_cap_gb', v)),
        ),
        STile(
          icon: Icons.event_repeat_rounded,
          iconColor: const Color(0xFF14B87D),
          title: 'صفر شدن ماهانه‌ی آمار',
          subtitle: 'هر ۳۰ روز آمار این دستگاه خودکار صفر می‌شود',
          trailing: SToggle(
              value: Store.getBool('monthly_reset', false),
              onChanged: (v) async {
                await Store.setBool('monthly_reset', v);
                if (v) await Store.setInt('st_reset_at', DateTime.now().millisecondsSinceEpoch);
                if (mounted) setState(() {});
              }),
        ),
        STile(
          icon: Icons.insights_rounded,
          iconColor: const Color(0xFF8E5BFF),
          title: 'آمار مصرف این دستگاه',
          subtitle: '${fmtBytes(Store.statUp + Store.statDown)} در ${Store.statSessions} اتصال',
          onTap: () async {
            await Navigator.push(context, adaptiveRoute((_) => const ProfilePage()));
            if (mounted) setState(() {});
          },
        ),
      ]),
      const SSection('ظاهر و عملکرد'),
      SCard(children: [
        _sw(Icons.vibration_rounded, const Color(0xFF8E5BFF), 'لرزش هنگام اتصال و قطع', 'با وصل یا قطع شدن VPN، دستگاه یک بار می‌لرزد (موبایل)', 'haptic', true),
        _sw(Icons.speed_rounded, const Color(0xFF33B5FF), 'نمایش کارت سرعت در خانه', 'کارت زنده‌ی آپلود و دانلود زیر دکمه‌ی اتصال', 'show_traffic', true),
        STile(
          icon: Icons.palette_rounded,
          iconColor: Colors.pinkAccent,
          title: 'تم برنامه',
          subtitle: 'تغییر ظاهر برنامه',
          onTap: () {
            final m = Store.themeMode.value;
            Store.setTheme(m == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
          },
        ),
        STile(
          icon: Icons.speed_rounded,
          iconColor: const Color(0xFF29E07F),
          title: 'بهینه‌سازی برنامه',
          subtitle: 'کاهش افکت‌ها و پاک‌سازی حافظه برای روانی بیشتر',
          trailing: SToggle(
              value: Store.lite.value,
              onChanged: (v) async {
                await Store.setLite(v);
                PaintingBinding.instance.imageCache.clear();
                PaintingBinding.instance.imageCache.clearLiveImages();
                if (mounted) setState(() {});
              }),
        ),
        _sw(Icons.settings_rounded, Colors.tealAccent, 'تنظیمات سیستم', 'هماهنگ با تنظیمات دستگاه', 'system', true),
        _sw(Icons.battery_charging_full_rounded, const Color(0xFF29E07F), 'حالت صرفه‌جویی در مصرف باتری', 'کاهش مصرف انرژی', 'battery', false),
      ]),
      const SSection('اعلان‌ها'),
      SCard(children: [
        _sw(Icons.notifications_active_rounded, Colors.lightBlueAccent, 'نمایش اعلان‌های پیشرفته', 'اطلاع از وضعیت اتصال و خطاها', 'advNotif', true),
      ]),
      const SSection('بکاپ و داده‌ها'),
      SCard(children: [
        STile(
          icon: Icons.lock_rounded,
          iconColor: const Color(0xFF14B87D),
          title: 'گاوصندوق NEXORA (بکاپ تنظیمات)',
          subtitle: 'کد بکاپ را در پروفایل ببین و کپی کن',
          onTap: () => Navigator.push(context, adaptiveRoute((_) => const ProfilePage())),
        ),
        STile(
          icon: Icons.bug_report_rounded,
          iconColor: const Color(0xFF5B5FE6),
          title: 'کپی گزارش تشخیصی',
          subtitle: 'نسخه، پلتفرم و تنظیمات برای ارسال به پشتیبانی',
          onTap: _copyDiag,
        ),
        STile(
          icon: Icons.delete_rounded,
          iconColor: Colors.redAccent,
          title: 'پاک کردن کش',
          subtitle: 'حذف فایل‌های موقت',
          onTap: () async {
            await Store.clearCache();
            if (context.mounted) snack(context, 'کش پاک شد');
          },
        ),
        STile(
          icon: Icons.refresh_rounded,
          iconColor: Colors.lightBlueAccent,
          title: 'بازنشانی تنظیمات',
          subtitle: 'بازگردانی تنظیمات پیش‌فرض (نام و آمار پروفایل پاک نمی‌شود)',
          onTap: () async {
            await Store.resetSettings();
            if (mounted) setState(() {});
            if (context.mounted) snack(context, 'تنظیمات بازنشانی شد');
          },
        ),
      ]),
    ]);
  }
}

class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        const PageHeader(title: 'اطلاعات', icon: Icons.info_rounded),
        const SizedBox(height: 4),
        Center(
          child: Column(children: [
            const Brand(size: 100),
            const SizedBox(height: 10),
            Text('NEXORA VPN', style: TextStyle(color: p.text, fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Version 1.0.2', style: TextStyle(color: p.sub, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 18),
        Panel(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('درباره برنامه', style: TextStyle(color: p.accent2, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text('NEXORA VPN یک برنامه فیلترشکن امن و سریع است که با هدف دسترسی آزاد به اینترنت طراحی شده است.',
                style: TextStyle(color: p.text, height: 1.8, fontSize: 13)),
          ]),
        ),
        Panel(
          onTap: () => Navigator.push(context, adaptiveRoute((_) => const PrivacyPage())),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.verified_user_rounded, color: Color(0xFF3FA9FF), size: 26),
              const SizedBox(width: 10),
              Expanded(child: Text('حریم خصوصی', style: TextStyle(color: p.accent2, fontSize: 17, fontWeight: FontWeight.w800))),
              Icon(Icons.chevron_left_rounded, color: p.sub),
            ]),
            const SizedBox(height: 10),
            Text(
                'ما اطلاعات شخصی شما (مانند نام، شماره تلفن یا ایمیل) را جمع‌آوری نمی‌کنیم. نوع اتصال سعی می‌کنیم بسیار رمزنگاری شود. فقط اطلاعات فنی محدود برای پایداری و رفع خطا استفاده می‌شود.',
                style: TextStyle(color: p.text, height: 1.9, fontSize: 12.5)),
            const SizedBox(height: 10),
            Text('از آنجا که این نسخه بتا است و وبسایت رسمی نداریم، ممکن است در آینده جزئیات بیشتری ارائه شود.',
                style: TextStyle(color: p.text, height: 1.9, fontSize: 12.5)),
            const SizedBox(height: 8),
          ]),
        ),
        const SizedBox(height: 4),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.send_rounded, color: p.accent2, size: 22),
            const SizedBox(width: 10),
            Text('کانال تلگرام ما:', textDirection: TextDirection.rtl, style: TextStyle(color: p.text, fontSize: 15)),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [p.accent, const Color(0xFF1F6FE0)]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: p.accent.withOpacity(0.5), blurRadius: 10)],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () async {
              await Clipboard.setData(const ClipboardData(text: telegramUrl));
              if (context.mounted) snack(context, 'لینک کپی شد');
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(children: [
                  SizedBox(width: 24),
                  Expanded(
                      child: Center(
                          child: Text(telegramUrl, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)))),
                  Icon(Icons.copy_rounded, color: Colors.white, size: 22),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [
            Expanded(child: Divider(color: p.border.withOpacity(0.6), indent: 40, endIndent: 10)),
            Text('Made with ', style: TextStyle(color: p.sub, fontSize: 12)),
            const Icon(Icons.favorite, color: Colors.redAccent, size: 13),
            Text(' for freedom', style: TextStyle(color: p.sub, fontSize: 12)),
            Expanded(child: Divider(color: p.border.withOpacity(0.6), indent: 10, endIndent: 40)),
          ]),
        ),
      ],
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    Widget item(String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.check_rounded, color: Color(0xFF3FA9FF), size: 20)),
            const SizedBox(width: 10),
            Expanded(child: Text(t, style: TextStyle(color: p.text, height: 1.8, fontSize: 13))),
          ]),
        );
    return SubPage(title: 'حریم خصوصی', icon: Icons.verified_user_rounded, children: [
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: p.accent2.withOpacity(0.10),
              border: Border.all(color: p.accent2.withOpacity(0.35)),
            ),
            child: Text('Version 1.0.2', style: TextStyle(color: p.accent2, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
      Panel(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('سیاست حریم خصوصی', style: TextStyle(color: p.accent2, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('مقدمه', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('ما در NEXORA VPN به حریم خصوصی شما اهمیت می‌دهیم و تلاش می‌کنیم فقط کمترین اطلاعات فنیِ لازم برای کارکرد برنامه را استفاده کنیم. این متن توضیح می‌دهد برنامه چه اطلاعاتی را به‌کار می‌برد و چه اطلاعاتی را جمع‌آوری نمی‌کند. استفاده از برنامه به معنای پذیرش این سیاست است.', style: TextStyle(color: p.text, height: 1.9, fontSize: 13)),
          const SizedBox(height: 12),
          Text('اطلاعاتی که جمع‌آوری نمی‌کنیم', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('ما نام، شماره تلفن، ایمیل، پیام‌ها، تاریخچه‌ی مرور، محتوای سایت‌هایی که باز می‌کنید و رمزهای عبور شما را نمی‌خوانیم و ذخیره نمی‌کنیم. برنامه برای ثبت‌نام به حساب کاربری شخصی نیاز ندارد و نام نمایشی که انتخاب می‌کنید فقط روی دستگاه خودتان نگهداری می‌شود.', style: TextStyle(color: p.text, height: 1.9, fontSize: 13)),
          const SizedBox(height: 12),
          Text('نوع اتصال', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('نوع اتصال سعی می‌کنیم بسیار رمزنگاری شود.', style: TextStyle(color: p.text, height: 1.9, fontSize: 13)),
          const SizedBox(height: 12),
          Text('اطلاعات فنی', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('برای اینکه سرویس پایدار بماند، ممکن است اطلاعات فنی عمومی مانند شناسه‌ی ناشناس دستگاه، نوع سیستم‌عامل، نسخه‌ی برنامه، کشور سرور انتخاب‌شده، زمان و مدت اتصال و گزارش‌های فنی خطا ثبت شود. این اطلاعات هویت شما را مشخص نمی‌کند و فقط برای پایش کیفیت سرورها، رفع اشکال و بهبود برنامه استفاده می‌شود.', style: TextStyle(color: p.text, height: 1.9, fontSize: 13)),
          const SizedBox(height: 12),
          Text('پیام‌های خطا', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('اگر اتصال برقرار نشود یا مشکلی پیش بیاید، به شما فقط یک پیام ساده نشان داده می‌شود. جزئیات فنیِ آن مشکل به‌صورت خودکار و بدون اطلاعات شخصی برای تیم فنی ارسال می‌شود تا بتوانیم آن را سریع‌تر برطرف کنیم.', style: TextStyle(color: p.text, height: 1.9, fontSize: 13)),
          const SizedBox(height: 12),
          Text('اشتراک‌گذاری با دیگران', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('ما اطلاعات شما را نمی‌فروشیم و برای تبلیغات در اختیار شخص ثالث قرار نمی‌دهیم. اطلاعات فنیِ محدود فقط در صورتِ الزام قانونی یا برای حفظ امنیت سرویس ممکن است بررسی شود.', style: TextStyle(color: p.text, height: 1.9, fontSize: 13)),
          const SizedBox(height: 12),
          Text('امنیت داده‌ها', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('تلاش می‌کنیم ارتباط برنامه با سرورها رمزنگاری‌شده باشد و دسترسی به اطلاعات فنی فقط برای مدیران سرویس باشد. با این حال هیچ سیستمی صددرصد بدون ریسک نیست و ما نمی‌توانیم امنیت مطلق را تضمین کنیم.', style: TextStyle(color: p.text, height: 1.9, fontSize: 13)),
          const SizedBox(height: 12),
          Text('مسئولیت کاربر', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('لطفاً از برنامه مطابق قوانین کشور خود و برای اهداف قانونی استفاده کنید. حفظ امنیت دستگاه و به‌روز نگه‌داشتن برنامه بر عهده‌ی شماست.', style: TextStyle(color: p.text, height: 1.9, fontSize: 13)),
          const SizedBox(height: 12),
          Text('تغییر این سیاست', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('چون این نسخه بتا است و وبسایت رسمی نداریم، ممکن است این سیاست در آینده به‌روزرسانی شود. نسخه‌ی جدید داخل همین صفحه نمایش داده می‌شود.', style: TextStyle(color: p.text, height: 1.9, fontSize: 13)),
          const SizedBox(height: 12),
        ]),
      ),
      Panel(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Privacy Policy', style: TextStyle(color: p.accent2, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Introduction', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('At NEXORA VPN we care about your privacy and try to use only the minimum technical information needed for the app to work. This page explains what the app uses and what it does not collect. By using the app you accept this policy.', style: TextStyle(color: p.text, height: 1.7, fontSize: 13)),
            const SizedBox(height: 12),
            Text('What we do not collect', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('We do not read or store your name, phone number, email, messages, browsing history, the content of the sites you open, or your passwords. The app does not require a personal account, and the display name you choose is kept only on your own device.', style: TextStyle(color: p.text, height: 1.7, fontSize: 13)),
            const SizedBox(height: 12),
            Text('Connection type', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('We try to make the connection type highly encrypted.', style: TextStyle(color: p.text, height: 1.7, fontSize: 13)),
            const SizedBox(height: 12),
            Text('Technical information', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('This open-source build does not record or send usage statistics, device identifiers or error reports to any server. The only network requests it makes besides your VPN traffic are the update check on GitHub and public IP/location lookup services used to show your connection location.', style: TextStyle(color: p.text, height: 1.7, fontSize: 13)),
            const SizedBox(height: 12),
            Text('Error messages', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('If a connection fails or something goes wrong, you only see a simple message on your screen. Nothing is sent anywhere.', style: TextStyle(color: p.text, height: 1.7, fontSize: 13)),
            const SizedBox(height: 12),
            Text('Sharing with others', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('We do not sell your information and do not share it with third parties. The project has no server that collects your data.', style: TextStyle(color: p.text, height: 1.7, fontSize: 13)),
            const SizedBox(height: 12),
            Text('Data security', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Your settings and personal servers are stored only on your device. No system is completely risk-free, so keep your device secure and the app up to date.', style: TextStyle(color: p.text, height: 1.7, fontSize: 13)),
            const SizedBox(height: 12),
            Text('User responsibility', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Please use the app in accordance with the laws of your country and for lawful purposes. Keeping your device secure and the app up to date is your responsibility.', style: TextStyle(color: p.text, height: 1.7, fontSize: 13)),
            const SizedBox(height: 12),
            Text('Changes to this policy', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Because this is a beta version and we have no official website, this policy may be updated in the future. The latest version will be shown on this page.', style: TextStyle(color: p.text, height: 1.7, fontSize: 13)),
            const SizedBox(height: 12),
          ]),
        ),
      ),
      Panel(
        tint: const Color(0xFF1B3FA0),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.info_rounded, color: p.accent2),
          const SizedBox(width: 10),
          Expanded(
              child: Text('در صورت داشتن هرگونه سوال، می‌توانید از طریق کانال تلگرام با ما در ارتباط باشید.',
                  style: TextStyle(color: p.text, height: 1.8, fontSize: 13))),
        ]),
      ),
    ]);
  }
}

class ConnInfoPage extends StatelessWidget {
  const ConnInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return ValueListenableBuilder<VpnStatus>(
      valueListenable: VpnService.I.status,
      builder: (context, s, _) {
        if (s.phase == Phase.off) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.canPop(context)) Navigator.pop(context);
          });
        }
        Widget stat(IconData ic, Color col, String v, String l) => Expanded(
              child: Panel(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Column(children: [
                  Icon(ic, color: col, size: 30),
                  const SizedBox(height: 6),
                  Text(v, style: TextStyle(color: p.text, fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(l, style: TextStyle(color: p.sub)),
                ]),
              ),
            );
        return SubPage(title: 'اطلاعات اتصال', icon: Icons.bar_chart_rounded, children: [
          ValueListenableBuilder<Geo?>(
            valueListenable: VpnService.I.geo,
            builder: (context, g, _) => Panel(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.circle, color: Color(0xFF29E07F), size: 12),
                  SizedBox(width: 8),
                  Text('متصل هستید 🎉', style: TextStyle(color: Color(0xFF29E07F), fontSize: 20, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 12),
                Text('${g?.flag ?? '🌐'} ${g?.country ?? 'در حال تشخیص لوکیشن...'}', style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: [
              stat(Icons.arrow_upward_rounded, const Color(0xFF29E07F), fmtBytes(s.up), 'آپلود'),
              const SizedBox(width: 10),
              stat(Icons.arrow_downward_rounded, const Color(0xFF3FA9FF), fmtBytes(s.down), 'دانلود'),
            ]),
          ),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.access_time_rounded, color: p.accent2, size: 28),
                const SizedBox(width: 10),
                Text(fmtDuration(s.seconds), style: TextStyle(color: p.text, fontSize: 24, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              Text('زمان اتصال', style: TextStyle(color: p.sub)),
            ]),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: p.text,
              backgroundColor: const Color(0xFF0A1735).withOpacity(0.6),
              side: BorderSide(color: p.accent2.withOpacity(0.8), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: () => VpnService.I.disconnect(),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.stop_rounded, color: Colors.redAccent, size: 26),
              SizedBox(width: 10),
              Text('قطع اتصال', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]);
      },
    );
  }
}

// ───────────────────────── پروفایل ─────────────────────────

String _profWhen(int ms) {
  if (ms <= 0) return 'هرگز';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
}

String _profDur(int s) {
  if (s < 60) return '$s ثانیه';
  if (s < 3600) return '${s ~/ 60} دقیقه';
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return h >= 48 ? '${h ~/ 24} روز و ${h % 24} ساعت' : '$h ساعت و $m دقیقه';
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  void _editName() {
    final p = P.of(context);
    final ctl = TextEditingController(text: Store.userName.value);
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: p.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text('نام شما', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w800)),
          content: TextField(
            controller: ctl,
            autofocus: true,
            maxLength: 24,
            style: TextStyle(color: p.text, fontSize: 16),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'نام شما',
              hintStyle: TextStyle(color: p.sub.withOpacity(0.7)),
              filled: true,
              fillColor: p.bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('انصراف', style: TextStyle(color: p.sub))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: p.accent),
              onPressed: () async {
                if (ctl.text.trim().isNotEmpty) await Store.setUserName(ctl.text);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearStats() async {
    final p = P.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: p.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text('پاک کردن آمار؟', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w800)),
          content: Text('آمار روی همین دستگاه صفر می‌شود.', style: TextStyle(color: p.sub, fontSize: 14, height: 1.6)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('انصراف', style: TextStyle(color: p.sub))),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(ctx, true), child: const Text('پاک کن')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await Store.clearUsageStats();
      if (mounted) setState(() {});
    }
  }

  Widget _header(P p) => ValueListenableBuilder<String>(
        valueListenable: Store.userName,
        builder: (context, name, _) {
          return SCard(children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _editName,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Row(children: [
                      Expanded(
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name.isEmpty ? 'کاربر NEXORA' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 21, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('برای تغییر نام لمس کن', style: TextStyle(color: p.sub, fontSize: 13)),
                          const SizedBox(height: 3),
                          Text('ID ${Store.deviceId.substring(0, 8)}  ·  v$kAppVersion', textDirection: TextDirection.ltr, style: TextStyle(color: p.accent2, fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      Icon(Icons.edit_rounded, color: p.sub, size: 22),
                    ]),
                  ),
                ),
              ),
            ),
          ]);
        },
      );

  Widget _stats(P p) => ValueListenableBuilder<VpnStatus>(
        valueListenable: VpnService.I.status,
        builder: (context, st, _) {
          final live = st.phase == Phase.on;
          final up = Store.statUp + (live ? st.up : 0);
          final down = Store.statDown + (live ? st.down : 0);
          final secs = Store.statSeconds + (live ? st.seconds : 0);
          final sessions = Store.statSessions + (live ? 1 : 0);
          final avg = sessions > 0 ? (up + down) ~/ sessions : 0;
          return SCard(children: [
            STile(icon: Icons.data_usage_rounded, iconColor: const Color(0xFFFFA726), title: 'مصرف کل', value: fmtBytes(up + down)),
            STile(icon: Icons.arrow_upward_rounded, iconColor: const Color(0xFF30D158), title: 'آپلود', value: fmtBytes(up)),
            STile(icon: Icons.arrow_downward_rounded, iconColor: const Color(0xFF33B5FF), title: 'دانلود', value: fmtBytes(down)),
            STile(icon: Icons.timer_rounded, iconColor: const Color(0xFF8E5BFF), title: 'مجموع زمان اتصال', value: _profDur(secs)),
            STile(icon: Icons.link_rounded, iconColor: const Color(0xFF00A3BF), title: 'تعداد اتصال', value: '$sessions'),
            STile(icon: Icons.calculate_rounded, iconColor: const Color(0xFF5B5FE6), title: 'میانگین مصرف هر اتصال', value: fmtBytes(avg)),
            STile(icon: Icons.emoji_events_rounded, iconColor: const Color(0xFFFF4FA3), title: 'بیشترین مصرف در یک اتصال', value: fmtBytes(Store.statMaxSession)),
            STile(icon: Icons.restart_alt_rounded, iconColor: Colors.redAccent, title: 'پاک کردن آمار این دستگاه', onTap: _confirmClearStats),
          ]);
        },
      );

  Widget _personal(P p) => SCard(children: [
        STile(
          icon: Icons.badge_rounded,
          iconColor: const Color(0xFF3D7BFF),
          title: 'نام نمایشی',
          value: Store.userName.value.isEmpty ? 'تنظیم نشده' : Store.userName.value,
          onTap: _editName,
        ),
      ]);

  Widget _device(P p) => SCard(children: [
        STile(
          icon: Icons.fingerprint_rounded,
          iconColor: const Color(0xFF8E5BFF),
          title: 'شناسه‌ی دستگاه',
          subtitle: 'برای پیگیری مشکل با پشتیبانی؛ لمس کن تا کپی شود',
          value: Store.deviceId.substring(0, 10),
          onTap: () {
            Clipboard.setData(ClipboardData(text: Store.deviceId));
            snack(context, 'شناسه‌ی دستگاه کپی شد');
          },
        ),
        STile(icon: Icons.devices_rounded, iconColor: const Color(0xFF3D7BFF), title: 'پلتفرم', value: Platform.operatingSystem),
        STile(icon: Icons.info_rounded, iconColor: const Color(0xFF5B5FE6), title: 'نسخه‌ی برنامه', value: kAppVersion),
        STile(icon: Icons.event_rounded, iconColor: const Color(0xFF14B87D), title: 'تاریخ شروع استفاده', value: _profWhen(Store.installAt)),
      ]);

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return SettingsScaffold(title: 'پروفایل', children: [
      _header(p),
      const SSection('آمار مصرف روی این دستگاه'),
      _stats(p),
      const SSection('شخصی‌سازی'),
      _personal(p),
      const SSection('اطلاعات دستگاه'),
      _device(p),
    ]);
  }
}

class _PingCtl {
  bool cancelRequested = false;
  final ValueNotifier<int> total = ValueNotifier<int>(0);
  final Completer<void> _c = Completer<void>();
  Future<void> get cancelled => _c.future;
  String code = '';
  String name = '';
  String sub = '';
  void addPing(Object _) {}
  void cancel() {
    cancelRequested = true;
    if (!_c.isCompleted) _c.complete();
  }
}

_PingCtl? _activePing;

Future<String?> _runPingTest(BuildContext context, Future<String?> Function(_PingCtl ctl) test, String Function(String) errText) async {
  final ctl = _PingCtl();
  _activePing = ctl;
  try {
    return await Future.any<String?>([test(ctl), ctl.cancelled.then<String?>((_) => 'cancelled')]);
  } finally {
    if (identical(_activePing, ctl)) _activePing = null;
  }
}

class PingSpinner extends StatefulWidget {
  const PingSpinner({super.key});

  @override
  State<PingSpinner> createState() => _PingSpinnerState();
}

class _PingSpinnerState extends State<PingSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 24,
        height: 24,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _SpinPainter(_c.value)),
        ),
      ),
    );
  }
}

const Color _spinGreen = Color(0xFF29E07F);

class _SpinPainter extends CustomPainter {
  final double t;
  _SpinPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(2.5, 2.5, size.width - 5, size.height - 5);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = _spinGreen.withOpacity(0.15);
    canvas.drawArc(r, 0, 6.2832, false, track);
    final a = t * 6.2832;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.8
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 6.2832,
        colors: [_spinGreen.withOpacity(0), _spinGreen],
        transform: GradientRotation(a - 1.9),
      ).createShader(r);
    canvas.drawArc(r, a - 1.9, 1.9, false, arc);
    final c = r.center;
    final rad = r.width / 2;
    final head = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
    canvas.drawCircle(head, 3.4, Paint()..color = _spinGreen.withOpacity(0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(head, 2.1, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SpinPainter o) => o.t != t;
}
