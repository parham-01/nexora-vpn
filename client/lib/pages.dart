import 'intro_page.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (Store.firstRun && !Store.introSeen) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        await showNexoraIntro(context, goTab: _go);
        if (!mounted) return;
      }
      await promptFinishedUpdate(context);
      // بررسی نسخه‌ی جدید در GitHub (با کمی تأخیر تا اتصال/لودینگ اولیه مزاحم نشود)
      await Future<void>.delayed(const Duration(seconds: 4));
      if (mounted) unawaited(promptNewVersion(context));
    });
    _boot();
  }

  @override
  void dispose() {
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
    // با ورود به برنامه یک تست پینگ پس‌زمینه انجام و کش می‌شود (اولین اتصال از همین نتایج استفاده می‌کند)
    unawaited(Api.sync().then((_) => VpnService.I.startBackgroundPing()));
    unawaited(GeoAtlas.preload());
    if (Store.getBool('autoConnect', false) && Store.config.value != null && mounted) {
      final r = await ConnectGlobe.run(context, VpnService.I.connect, _errText);
      if (!mounted) return;
      if (r != null) {
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
      TickerMode(enabled: _i == 0, child: HomePage(openSettings: () => _go(1))),
      _seen.contains(1) ? TickerMode(enabled: _i == 1, child: const SettingsPage()) : const SizedBox.shrink(),
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

String _errText(String r) {
  switch (r) {
    case 'no_config':
      return 'کانفیگی دریافت نشده است';
    case 'unsupported':
      return 'اتصال در این پلتفرم پشتیبانی نمی‌شود';
    case 'dns_failed':
      return 'تست پینگ DNS ناموفق بود؛ اتصال برقرار نشد';
    case 'tunnel_failed':
      return 'ساخت تونل شخصی ناموفق بود؛ اتصال برقرار نشد';
    case 'no_valid_ping':
      return 'هیچ کانفیگی پینگ معتبر نداشت؛ اینترنت را بررسی کن';
    case 'left_app':
      return 'چون از برنامه خارج شدی، مراحل تونل کامل نشد و اتصال برقرار نشد';
    case 'timeout':
    case 'no_internet':
    case 'core_failed':
      return 'هیچ‌کدام از کانفیگ‌ها وصل نشد؛ اینترنت یا سرور را بررسی کن';
    case 'busy':
      return 'در حال اتصال...';
    case 'cancelled':
      return 'اتصال لغو شد';
    case 'permission':
      return 'دسترسی VPN داده نشد';
    case 'bad_link':
      return 'لینک کانفیگ معتبر نیست';
    case 'no_core':
      return 'هسته اتصال پیدا نشد';
    default:
      return 'اتصال ناموفق بود';
  }
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
        snack(context, _errText(r));
      } else {
        showConnPopup(context);
      }
    } else {
      await v.disconnect();
    }
  }

  late final ValueNotifier<Phase> _phase = ValueNotifier(VpnService.I.status.value.phase);

  String _pingFor = '';

  void _pingSel() {
    final c = Store.config.value;
    if (c == null) return;
    final vs = VpnService.I;
    if (vs.status.value.phase != Phase.off) return;
    final key = '${c['id']}|${c['link']}';
    if (_pingFor == key) return;
    _pingFor = key;
    unawaited(vs.relayPing('${c['link']}', id: '${c['id']}'));
  }

  @override
  void initState() {
    super.initState();
    VpnService.I.status.addListener(_onStatus);
    Store.config.addListener(_pingSel);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pingSel());
  }

  @override
  void dispose() {
    VpnService.I.status.removeListener(_onStatus);
    Store.config.removeListener(_pingSel);
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

        final top = Directionality(
          textDirection: TextDirection.ltr,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TourTarget('home.menu', IconButton(onPressed: widget.openSettings, icon: Icon(Icons.menu_rounded, color: p.text, size: 32))),
            TourTarget('home.premium', IconButton(
              onPressed: () => snack(context, 'نسخه پریمیوم به‌زودی'),
              icon: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFC53D), size: 28),
            )),
          ]),
        );

        final brand = Directionality(
          textDirection: TextDirection.ltr,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Brand(size: wide ? 110 : 96),
            const SizedBox(width: 14),
            NexoraWordmark(fontSize: wide ? 32 : 27, textColor: p.text),
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

        final brandBlock = Column(children: [TourTarget('home.brand', brand), TourTarget('home.status', statusChip), TourTarget('home.features', features)]);

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
                        if (has)
                          ValueListenableBuilder<int>(
                            valueListenable: VpnService.I.pingCacheRev,
                            builder: (_, __, ___) {
                              final v = VpnService.I.pingCache['${cfg['id']}'];
                              const green = Color(0xFF29E07F);
                              final ok = v != null && v >= 1;
                              final txt = v == null ? 'Ping: ...' : (ok ? 'Ping: $v ms' : 'Ping: timeout');
                              final col = v == null ? p.sub : (ok ? green : Colors.redAccent);
                              return Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  Text(txt, style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 8),
                                  Container(width: 10, height: 10, decoration: BoxDecoration(color: col, shape: BoxShape.circle, boxShadow: ok ? [BoxShadow(color: green.withOpacity(0.7), blurRadius: 6)] : null)),
                                ]),
                              );
                            },
                          ),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: [
              Expanded(
                child: Text(on ? 'متصل هستید' : 'برای اتصال، سوئیچ را به راست بکشید',
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: on ? const Color(0xFF29E07F) : p.text, fontSize: 15)),
              ),
              if (!on) ...[
                const SizedBox(width: 8),
                Icon(Icons.keyboard_double_arrow_left_rounded, color: p.accent2, size: 30),
              ],
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

        final speeds = !on ? const SizedBox.shrink() : TrafficCard(
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

  @override
  void initState() {
    super.initState();
    // نتایج کش‌شده‌ی تست پس‌زمینه فوری نمایش داده می‌شود؛ اگر کامل و تازه باشند، تست دوباره‌ی کامل لازم نیست.
    final vs = VpnService.I;
    final cfgs = Store.configs.value;
    for (final c in cfgs) {
      final v = vs.pingCache['${c['id']}'];
      if (v != null) _ms['${c['id']}'] = v;
    }
    // فقط لوکیشن/کانفیگ انتخاب‌شده تست می‌شود (حالت «خودکار» چون باید بهترین را پیدا کند، همه را می‌خواهد)
    final target = Store.candidates();
    final at = vs.pingCacheAt;
    final fresh = at != null && DateTime.now().difference(at).inMinutes < 3 && target.isNotEmpty && target.every((c) => _ms.containsKey('${c['id']}'));
    if (!fresh) WidgetsBinding.instance.addPostFrameCallback((_) => _pingAll(onlySelected: true));
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
    setState(() {
      _pinging = true;
      for (final c in list) {
        _ms.remove('${c['id']}');
      }
    });
    final r = await ConnectGlobe.runTest(context, (ctl) async {
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

      final firstBudget = Duration(seconds: (list.length / 16).ceil() * 9 + 12);
      await runPass(list, 16, true).timeout(firstBudget, onTimeout: () {});
      if (!ctl.cancelRequested && best == null) {
        final failed = [for (final c in list) if (!Api.validPing(_ms['${c['id']}'] ?? -1)) c];
        if (failed.isNotEmpty) {
          await runPass(failed.take(6).toList(), 6, false).timeout(const Duration(seconds: 10), onTimeout: () {});
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
    if (mounted) {
      setState(() => _pinging = false);
      if (r != null && r != 'cancelled' && r != 'no_valid_ping') snack(context, _errText(r));
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final ok = await Api.sync();
    if (mounted) {
      setState(() => _busy = false);
      snack(context, ok ? 'لیست به‌روز شد (${Store.configs.value.length} کانفیگ)' : 'سرور در دسترس نیست (${Api.lastSyncError.isEmpty ? 'نامشخص' : Api.lastSyncError})');
      _pingAll();
    }
  }

  Future<void> _choose(String id, String label) async {
    await Store.setServerId(id);
    Store.applySelection();
    if (id.isNotEmpty) {
      for (final c in Store.configs.value) {
        if ('${c['id']}' == id) {
          unawaited(VpnService.I.relayPing('${c['link']}', id: id));
          break;
        }
      }
    }
    if (!mounted) return;
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
              Text('لینک کانفیگ (vless, vmess, trojan, ss) را پیست کنید:', style: TextStyle(color: p.sub, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: ctl,
                maxLines: 3,
                style: TextStyle(color: p.text, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'vless://... یا vmess://...',
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
              final id = edit == null ? '' : '${edit['id']}';
              if (edit == null) {
                _pingAll(onlySelected: true);
              } else {
                _ms.remove(id);
                final cur = Store.configs.value.where((e) => '${e['id']}' == id);
                if (cur.isNotEmpty) _pingOne(cur.first);
              }
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

  Widget _radio(P p, bool sel) => Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: sel ? p.accent2 : p.sub, size: 26);

  Widget _header(P p) => Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 10),
          child: Row(children: [
            SizedBox(
              width: 44,
              child: IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: Icon(Icons.chevron_left_rounded, color: p.text, size: 34),
              ),
            ),
            Expanded(child: Center(child: Text('سرورها', style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w800)))),
            IconButton(
              tooltip: 'افزودن سرور شخصی',
              icon: Icon(Icons.add_link_rounded, color: p.accent2, size: 26),
              onPressed: () => _addCustomConfig(context),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _pingAll(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [p.accent, p.accent2]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: p.accent.withOpacity(0.45), blurRadius: 12)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _pinging
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.speed_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  const Text('پینگ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                ]),
              ),
            ),
          ]),
        ),
      );

  Widget _pingChip(P p, String id) {
    final v = _ms[id];
    const green = Color(0xFF29E07F);
    final Widget chip;
    if (_rowPinging.contains(id)) {
      chip = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: green));
    } else if (v == null) {
      chip = _pinging
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: green))
          : Text('—', style: TextStyle(color: p.sub));
    } else if (v < 0) {
      chip = const Text('timeout', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w700));
    } else {
      chip = Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: green, shape: BoxShape.circle, boxShadow: [BoxShadow(color: green.withOpacity(0.8), blurRadius: 6)])),
        const SizedBox(width: 5),
        Text('$v ms', style: const TextStyle(color: green, fontSize: 13, fontWeight: FontWeight.w800)),
      ]);
    }
    return chip;
  }

  Widget _cfgRow(P p, Map<String, dynamic> c, String sid) {
    final id = '${c['id']}';
    final country = '${c['country'] ?? ''}';
    final code = '${c['code'] ?? ''}';
    final proto = '${c['protocol'] ?? ''}'.toUpperCase();
    final tr = '${c['transport'] ?? ''}';
    final kind = proto.isEmpty ? '' : (tr.isEmpty ? proto : '$proto · $tr');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _choose(id, cfgTitle(c)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: [
              PinIcon(size: 44, color: p.accent2, animate: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cfgTitle(c), textDirection: TextDirection.rtl, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    country.isEmpty || cfgTitle(c).contains(country) ? '' : '${flagOf(code)} $country',
                    textDirection: TextDirection.rtl,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.sub, fontSize: 12),
                  ),
                ]),
              ),
              if (Store.isCustom(c)) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _addCustomConfig(context, edit: c),
                  child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.edit_rounded, size: 19, color: p.accent2)),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _deleteCustom(c),
                  child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent)),
                ),
              ],
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pingOne(c),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6), child: _pingChip(p, id)),
              ),
              const SizedBox(width: 10),
              _radio(p, sid == id),
            ]),
          ),
        ),
      ),
    );
  }

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
                    final children = <Widget>[
                      Group(children: [
                        Tile(
                          icon: Icons.auto_awesome_rounded,
                          iconColor: Colors.amber,
                          title: 'خودکار',
                          subtitle: 'تست همه و اتصال به اولین سرور سالم',
                          trailing: _radio(p, sid.isEmpty || sid.startsWith('loc:')),
                          onTap: () => _choose('', 'خودکار'),
                        ),
                      ]),
                    ];
                    if (list.isEmpty) {
                      children.add(Padding(
                        padding: const EdgeInsets.all(30),
                        child: Center(child: Text('کانفیگی وجود ندارد؛ بکش پایین تا به‌روز شود', textAlign: TextAlign.center, style: TextStyle(color: p.sub))),
                      ));
                    } else {
                      int rank(Map<String, dynamic> c) {
                        final v = _ms['${c['id']}'];
                        if (v == null) return 1 << 29;
                        if (!Api.validPing(v)) return 1 << 30;
                        return v;
                      }
                      final sorted = List<Map<String, dynamic>>.from(list)..sort((a, b) => rank(a).compareTo(rank(b)));
                      children.add(Group(children: [for (final c in sorted) _cfgRow(p, c, sid)]));
                    }
                    if (_busy) children.add(const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())));
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
  void _themeDialogSet(ThemeMode m) async {
    await Store.setTheme(m);
    if (mounted) setState(() {});
  }

  String _serverLabel() {
    final sid = Store.serverId;
    if (sid.isEmpty) return 'بهترین سرور نزدیک شما';
    if (sid.startsWith('loc:')) {
      final l = Store.locations().where((e) => e['key'] == sid.substring(4));
      if (l.isNotEmpty) return '${flagOf('${l.first['code']}')} ${l.first['country']}';
    }
    return 'انتخاب دستی';
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final mode = Store.themeMode.value;
    Widget radio(ThemeMode m, IconData ic, String t, Color col) => Tile(
          icon: ic,
          iconColor: col,
          title: t,
          onTap: () => _themeDialogSet(m),
          trailing: Icon(mode == m ? Icons.radio_button_checked : Icons.radio_button_off, color: mode == m ? p.accent2 : p.sub, size: 26),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        const PageHeader(title: 'تنظیمات', icon: Icons.settings_rounded),
        const SectionTitle('کانفیگ و اتصال'),
        Group(children: [
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: Store.config,
            builder: (context, cfg, _) => Tile(
              icon: Icons.storage_rounded,
              title: cfg == null ? 'کانفیگ' : cfgTitle(cfg),
              subtitle: cfg != null && '${cfg['expires']}'.isNotEmpty ? 'اعتبار: ${cfg['expires']}' : 'دریافت نشده',
              trailing: const Chevron(),
              onTap: () => Navigator.push(context, adaptiveRoute((_) => const LocationsPage(initialTab: 1))),
            ),
          ),
          Tile(
            icon: Icons.bolt_rounded,
            iconColor: Colors.amber,
            title: 'اتصال خودکار',
            subtitle: 'در هنگام شروع برنامه',
            trailing: Toggle(
                value: Store.getBool('autoConnect', false),
                onChanged: (v) async {
                  await Store.setBool('autoConnect', v);
                  setState(() {});
                }),
          ),
          Tile(
            icon: Icons.public_rounded,
            title: 'انتخاب سرور دلخواه',
            subtitle: _serverLabel(),
            trailing: const Chevron(),
            onTap: () async {
              await Navigator.push(context, adaptiveRoute((_) => const LocationsPage()));
              if (mounted) setState(() {});
            },
          ),
        ]),
        const SectionTitle('ظاهر برنامه'),
        Group(children: [
          radio(ThemeMode.dark, Icons.dark_mode_rounded, 'حالت تاریک', p.accent2),
          radio(ThemeMode.light, Icons.light_mode_rounded, 'حالت روشن', Colors.amber),
          radio(ThemeMode.system, Icons.desktop_windows_rounded, 'استفاده از تنظیمات سیستم', p.text),
        ]),
        const SectionTitle('اعلان‌ها'),
        Group(children: [
          Tile(
            icon: Icons.notifications_rounded,
            iconColor: Colors.amber,
            title: 'اعلان اتصال',
            trailing: Toggle(
                value: Store.getBool('notif', true),
                onChanged: (v) async {
                  await Store.setBool('notif', v);
                  setState(() {});
                }),
          ),
        ]),
        const SectionTitle('بیشتر'),
        Group(children: [
          Tile(
            icon: Icons.system_update_rounded,
            iconColor: const Color(0xFF6BE6FF),
            title: 'به‌روزرسانی',
            subtitle: 'Update',
            trailing: const Chevron(),
            onTap: () => Navigator.push(context, adaptiveRoute((_) => const UpdatePage())),
          ),
          Tile(
            icon: Icons.tune_rounded,
            title: 'تنظیمات پیشرفته',
            trailing: const Chevron(),
            onTap: () => Navigator.push(context, adaptiveRoute((_) => const AdvancedPage())),
          ),
        ]),
      ],
    );
  }
}

class AdvancedPage extends StatefulWidget {
  const AdvancedPage({super.key});

  @override
  State<AdvancedPage> createState() => _AdvancedPageState();
}

class _AdvancedPageState extends State<AdvancedPage> {
  Widget _sw(IconData ic, Color col, String t, String sub, String key, bool def) => Tile(
        icon: ic,
        iconColor: col,
        title: t,
        subtitle: sub,
        trailing: Toggle(
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

  @override
  Widget build(BuildContext context) {
    return SubPage(title: 'تنظیمات پیشرفته', icon: Icons.settings_rounded, children: [
      Group(children: [
        Tile(
          icon: Icons.palette_rounded,
          iconColor: Colors.pinkAccent,
          title: 'تم برنامه',
          subtitle: 'تغییر ظاهر برنامه',
          trailing: const Chevron(),
          onTap: () {
            final m = Store.themeMode.value;
            Store.setTheme(m == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
          },
        ),
        _sw(Icons.security_rounded, Colors.amberAccent, 'حالت ضد فیلترینگ شدید (Stealth Fragment)', 'تکه‌تکه کردن پکت‌های TLS برای عبور از سد همراه اول و ایرانسل', 'stealth_fragment', true),
        _sw(Icons.access_time_filled_rounded, const Color(0xFF29E07F), 'همگام‌سازی خودکار منطقه زمانی ویندوز (Auto-Timezone)', 'تنظیم خودکار ساعت ویندوز با لوکیشن سرور برای دور زدن فیلترهای ضد تقلب آمازون و جمینای', 'auto_timezone_sync', true),
        Tile(
          icon: Icons.alt_route_rounded,
          iconColor: const Color(0xFF33B5FF),
          title: 'پروکسی زنجیره‌ای مسکونی (Residential Upstream)',
          subtitle: Store.upstreamProxyEnabled && Store.upstreamProxy.isNotEmpty
              ? 'فعال: ${Store.upstreamProxy}'
              : 'اتصال خروجی به آی‌پی خانگی/تمیز برای ثبت‌نام آمازون و پی‌پال',
          trailing: const Chevron(),
          onTap: () => _editUpstreamProxy(context),
        ),
        _sw(Icons.settings_rounded, Colors.tealAccent, 'تنظیمات سیستم', 'هماهنگ با تنظیمات دستگاه', 'system', true),
        _sw(Icons.battery_charging_full_rounded, const Color(0xFF29E07F), 'حالت صرفه‌جویی در مصرف باتری', 'کاهش مصرف انرژی', 'battery', false),
        _sw(Icons.notifications_active_rounded, Colors.lightBlueAccent, 'نمایش اعلان‌های پیشرفته', 'اطلاع از وضعیت اتصال و خطاها', 'advNotif', true),
        Tile(
          icon: Icons.speed_rounded,
          iconColor: const Color(0xFF29E07F),
          title: 'بهینه‌سازی برنامه',
          subtitle: 'کاهش افکت‌ها و پاک‌سازی حافظه برای روانی بیشتر',
          trailing: Toggle(
              value: Store.lite.value,
              onChanged: (v) async {
                await Store.setLite(v);
                PaintingBinding.instance.imageCache.clear();
                PaintingBinding.instance.imageCache.clearLiveImages();
                if (mounted) setState(() {});
              }),
        ),
        Tile(
          icon: Icons.delete_rounded,
          iconColor: Colors.redAccent,
          title: 'پاک کردن کش',
          subtitle: 'حذف فایل‌های موقت',
          trailing: const Chevron(),
          onTap: () async {
            await Store.clearCache();
            if (context.mounted) snack(context, 'کش پاک شد');
          },
        ),
        Tile(
          icon: Icons.refresh_rounded,
          iconColor: Colors.lightBlueAccent,
          title: 'بازنشانی تنظیمات',
          subtitle: 'بازگردانی تنظیمات پیش‌فرض',
          trailing: const Chevron(),
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
            Text('Version 1.0.0', style: TextStyle(color: p.sub, fontSize: 13)),
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
                'ما هیچ‌گونه اطلاعات شخصی شما (مانند نام، شماره تلفن یا ایمیل) را ذخیره نمی‌کنیم. تنها اطلاعات مورد نیاز برای اتصال به سرورهای ما ارسال می‌شود و پس از پایان اتصال، هیچ اطلاعاتی نگهداری نمی‌شود.',
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
            child: Text('Version 1.0.0', style: TextStyle(color: p.accent2, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
      Panel(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ما در NEXORA VPN به حریم خصوصی شما بسیار اهمیت می‌دهیم. به همین دلیل:', style: TextStyle(color: p.text, height: 1.8, fontSize: 14)),
          const SizedBox(height: 6),
          item('هیچ‌گونه اطلاعات شخصی مانند نام، شماره تلفن، ایمیل یا پیام‌های شما را ذخیره نمی‌کنیم.'),
          item('تنها اطلاعات فنی لازم برای اتصال (مانند IP شما، حجم مصرفی و زمان اتصال) به سرورهای ما ارسال می‌شود.'),
          item('این اطلاعات صرفا برای بهبود عملکرد و مدیریت سرورها استفاده شده و پس از پایان اتصال حذف می‌شود.'),
          item('به دلیل اینکه این نسخه بتا است و وبسایت رسمی نداریم، ممکن است در آینده سیاست حریم خصوصی به‌روزرسانی شود.'),
        ]),
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
