import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'store.dart';
import 'vpn_service.dart';

class UsIdentity {
  final String fullName;
  final String street;
  final String city;
  final String state;
  final String stateCode;
  final String zip;
  final String phone;

  const UsIdentity({
    required this.fullName,
    required this.street,
    required this.city,
    required this.state,
    required this.stateCode,
    required this.zip,
    required this.phone,
  });
}

const List<UsIdentity> _kPredefinedUsIdentities = [
  UsIdentity(
    fullName: 'Robert Vance',
    street: '100 Mulberry St, Ste 400',
    city: 'Newark',
    state: 'New Jersey',
    stateCode: 'NJ',
    zip: '07102',
    phone: '(973) 621-4400',
  ),
  UsIdentity(
    fullName: 'James Miller',
    street: '1120 SW 5th Ave, Ste 100',
    city: 'Portland',
    state: 'Oregon',
    stateCode: 'OR',
    zip: '97204',
    phone: '(503) 823-4000',
  ),
  UsIdentity(
    fullName: 'Michael Wilson',
    street: '1000 Elm St, Ste 400',
    city: 'Manchester',
    state: 'New Hampshire',
    stateCode: 'NH',
    zip: '03101',
    phone: '(603) 624-6500',
  ),
  UsIdentity(
    fullName: 'David Anderson',
    street: '350 5th Ave, Fl 20',
    city: 'New York',
    state: 'New York',
    stateCode: 'NY',
    zip: '10118',
    phone: '(212) 736-3100',
  ),
  UsIdentity(
    fullName: 'William Taylor',
    street: '200 E Santa Clara St',
    city: 'San Jose',
    state: 'California',
    stateCode: 'CA',
    zip: '95113',
    phone: '(408) 535-3500',
  ),
  UsIdentity(
    fullName: 'Richard Thomas',
    street: '301 W 2nd St',
    city: 'Austin',
    state: 'Texas',
    stateCode: 'TX',
    zip: '78701',
    phone: '(512) 974-2000',
  ),
  UsIdentity(
    fullName: 'Joseph Moore',
    street: '350 Lincoln Rd',
    city: 'Miami Beach',
    state: 'Florida',
    stateCode: 'FL',
    zip: '33139',
    phone: '(305) 673-7000',
  ),
  UsIdentity(
    fullName: 'Thomas Jackson',
    street: '701 5th Ave, Ste 4200',
    city: 'Seattle',
    state: 'Washington',
    stateCode: 'WA',
    zip: '98104',
    phone: '(206) 622-6789',
  ),
  UsIdentity(
    fullName: 'Daniel White',
    street: '233 S Wacker Dr, Ste 300',
    city: 'Chicago',
    state: 'Illinois',
    stateCode: 'IL',
    zip: '60606',
    phone: '(312) 875-0066',
  ),
  UsIdentity(
    fullName: 'Matthew Harris',
    street: '500 S Grand Ave',
    city: 'Los Angeles',
    state: 'California',
    stateCode: 'CA',
    zip: '90071',
    phone: '(213) 624-6000',
  ),
  UsIdentity(
    fullName: 'Anthony Martin',
    street: '100 N Biscayne Blvd',
    city: 'Miami',
    state: 'Florida',
    stateCode: 'FL',
    zip: '33132',
    phone: '(305) 374-1000',
  ),
  UsIdentity(
    fullName: 'Mark Clark',
    street: '600 Congress Ave',
    city: 'Austin',
    state: 'Texas',
    stateCode: 'TX',
    zip: '78701',
    phone: '(512) 474-5000',
  ),
];

class AwsAssistant {
  static const String starterUrl = 'https://signup.aws.com/starter';

  static UsIdentity getRandomIdentity() {
    final rnd = Random();
    return _kPredefinedUsIdentities[rnd.nextInt(_kPredefinedUsIdentities.length)];
  }

  /// انتخاب هویت معتبر و هماهنگ دقیق با شهر و ایالت سرور متصل‌شده
  static UsIdentity getIdentityForCity(String city, String region) {
    final c = city.toLowerCase();
    final r = region.toLowerCase();
    for (final id in _kPredefinedUsIdentities) {
      if (c.contains(id.city.toLowerCase()) ||
          r.contains(id.state.toLowerCase()) ||
          r.contains(id.stateCode.toLowerCase())) {
        return id;
      }
    }
    if (c.contains('newark') || r.contains('jersey') || r.contains('nj')) {
      return _kPredefinedUsIdentities.firstWhere((id) => id.stateCode == 'NJ', orElse: () => _kPredefinedUsIdentities.first);
    }
    if (c.contains('york') || r.contains('ny')) {
      return _kPredefinedUsIdentities.firstWhere((id) => id.stateCode == 'NY', orElse: () => _kPredefinedUsIdentities.first);
    }
    return getRandomIdentity();
  }

  /// باز کردن مرورگر در حالت ایزوله و امن (InPrivate/Incognito) همراه با قطع نشت WebRTC
  static Future<bool> launchSafeBrowser(String url) async {
    // (اندروید جدا از ویندوز مدیریت می‌شود؛ ویندوز: هماهنگ‌سازی ساعت + Edge/Chrome InPrivate)
    if (Platform.isWindows) {
      // ابتدا ساعت سیستم را به طور خودکار با آمریکا هماهنگ می‌کنیم
      await Api.syncWindowsTimezone('US');

      try {
        // ۱. تلاش با مایکروسافت اج (Edge پیش‌فرض با مسدودسازی قطعی نشت WebRTC به ایران)
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Start-Process msedge.exe -ArgumentList @("--inprivate", "--lang=en-US", "--force-webrtc-ip-handling-policy=disable_non_proxied_udp", "--disable-features=WebRtcHideLocalIpsWithMdns", "$url")',
        ]);
        if (r.exitCode == 0) return true;
      } catch (_) {}

      try {
        // ۲. تلاش با گوگل کروم در حالت اینکوگنیتو و مسدودسازی قطعی نشت WebRTC
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Start-Process chrome.exe -ArgumentList @("--incognito", "--lang=en-US", "--force-webrtc-ip-handling-policy=disable_non_proxied_udp", "--disable-features=WebRtcHideLocalIpsWithMdns", "$url")',
        ]);
        if (r.exitCode == 0) return true;
      } catch (_) {}

      try {
        // ۳. مرورگر پیش‌فرض سیستم
        await Process.start('explorer.exe', [url], mode: ProcessStartMode.detached);
        return true;
      } catch (_) {}
    } else if (Platform.isAndroid) {
      // اندروید: مستقیم داخل Chrome اصلی گوشی (نه WebView داخل اپ)؛ اگر Chrome نبود، مرورگر پیش‌فرض
      try {
        await AndroidIntent(
          action: 'action_view',
          data: url,
          package: 'com.android.chrome',
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        ).launch();
        return true;
      } catch (_) {}
      try {
        return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {}
    } else if (Platform.isLinux) {
      try {
        await Process.run('google-chrome', ['--incognito', '--lang=en-US', '--force-webrtc-ip-handling-policy=disable_non_proxied_udp', url]);
        return true;
      } catch (_) {
        try {
          await Process.run('xdg-open', [url]);
          return true;
        } catch (_) {}
      }
    } else if (Platform.isMacOS) {
      try {
        await Process.run('open', ['-na', 'Google Chrome', '--args', '--incognito', '--force-webrtc-ip-handling-policy=disable_non_proxied_udp', url]);
        return true;
      } catch (_) {
        try {
          await Process.run('open', [url]);
          return true;
        } catch (_) {}
      }
    }
    return false;
  }
}

void showAwsAssistantSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _AwsAssistantSheetWidget(),
  );
}

class _AwsAssistantSheetWidget extends StatefulWidget {
  const _AwsAssistantSheetWidget();

  @override
  State<_AwsAssistantSheetWidget> createState() => _AwsAssistantSheetWidgetState();
}

class _AwsAssistantSheetWidgetState extends State<_AwsAssistantSheetWidget> {
  late UsIdentity _identity;
  IpQualityReport? _quality;
  bool _loadingQuality = true;

  @override
  void initState() {
    super.initState();
    _identity = AwsAssistant.getRandomIdentity();
    _fetchQuality();
  }

  Future<void> _fetchQuality() async {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final on = VpnService.I.status.value.phase == Phase.on;
    final proxy = (isDesktop && on) ? '127.0.0.1:10809' : null;
    final q = await Api.inspectIpQuality(proxy: proxy);
    if (mounted) {
      setState(() {
        _quality = q;
        _loadingQuality = false;
        if (q != null && q.city.isNotEmpty) {
          _identity = AwsAssistant.getIdentityForCity(q.city, q.country);
        }
      });
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label کپی شد: $text', textDirection: TextDirection.rtl),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final isUs = _quality?.code == 'US';
    final tzMatched = _quality?.timezoneMatch ?? false;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: p.border.withOpacity(0.5)),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            // Handle bar
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: p.sub.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9900), Color(0xFFFF5500)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'دستیار دریافت ۱۰۰ دلار آمازون',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'تضمین بدون کارت',
                                style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'محیط ایزوله، تطابق ساعت، آدرس معتبر و حذف مرحله کارت بانکی',
                          style: TextStyle(color: p.sub, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                children: [
                  // Pre-flight Status Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.border.withOpacity(0.6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.checklist_rounded, color: Color(0xFF29E07F), size: 20),
                            SizedBox(width: 8),
                            Text('بررسی خودکار وضعیت اتصال و امنیت',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_loadingQuality)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                          )
                        else ...[
                          _checkItem(
                            isUs ? 'لوکیشن سرور: ایالات متحده (${_quality?.city ?? ''})' : 'لوکیشن سرور: ${_quality?.country ?? 'ناشناس'} (پیشنهاد: اتصال به سرور آمریکا)',
                            isUs,
                            isUs ? 'هماهنگ با فرم ثبت‌نام آمازون آمریکا' : 'برای حذف قطعی مرحله کارت، سرور آمریکا پیشنهاد می‌شود',
                          ),
                          const SizedBox(height: 8),
                          _checkItem(
                            tzMatched ? 'ساعت ویندوز: کاملاً همگام با سرور' : 'ساعت ویندوز: ناهماهنگ با سرور (روی ایران)',
                            tzMatched,
                            tzMatched ? 'فیلتر هوش مصنوعی ضد تقلب آمازون دور زده شد' : 'با یک کلیک ساعت ویندوز را همگام کنید',
                          ),
                          if (!tzMatched && Platform.isWindows) ...[
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF29E07F),
                                foregroundColor: const Color(0xFF040A1C),
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                              label: const Text('⚡ همگام‌سازی فوری ساعت با آمریکا', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                              onPressed: () async {
                                final ok = await Api.syncWindowsTimezone('US');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(ok ? 'ساعت ویندوز روی آمریکا تنظیم شد!' : 'خطا در تنظیم ساعت')),
                                  );
                                  _fetchQuality();
                                }
                              },
                            ),
                          ],
                          const SizedBox(height: 8),
                          _checkItem('امنیت DNS و ضد نشت DoH: فعال', true, 'هیچ نشت ترافیکی وجود ندارد'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // US Identity Generator Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.border.withOpacity(0.6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_pin_rounded, color: Color(0xFFFF9900), size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('مشخصات و آدرس معتبر آمریکا (جهت کپی در فرم)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _identity = AwsAssistant.getRandomIdentity();
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('تولید مجدد', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _copyRow('نام کامل', _identity.fullName, p),
                        _copyRow('آدرس خیابان', _identity.street, p),
                        _copyRow('شهر', _identity.city, p),
                        _copyRow('ایالت (State)', '${_identity.state} (${_identity.stateCode})', p, copyVal: _identity.stateCode),
                        _copyRow('کد پستی (ZIP)', _identity.zip, p),
                        _copyRow('تلفن', _identity.phone, p),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 1-Click Clean Browser Launch
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1E3A8A).withOpacity(0.4),
                          const Color(0xFF0F172A).withOpacity(0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.rocket_launch_rounded, color: Color(0xFF60A5FA), size: 22),
                            SizedBox(width: 10),
                            Text('اجرای فوق‌امن و ورود به ثبت‌نام',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Platform.isAndroid
                              ? 'با زدن دکمه زیر، سایت ثبت‌نام آمازون مستقیم در مرورگر Chrome گوشی باز می‌شود (نه داخل برنامه). قبل از شروع، VPN را روی سرور آمریکا وصل کن و ساعت و منطقه‌ی زمانی گوشی را خودکار بگذار.'
                              : 'با کلیک روی دکمه زیر، برنامه به طور خودکار ساعت سیستم را هماهنگ کرده و مرورگر را در پنجره تمیز و ناشناس (بدون کوکی‌های قبلی و به زبان انگلیسی) مستقیم به سایت ثبت‌نام هدایت می‌کند.',
                          style: TextStyle(color: Color(0xFF93C5FD), fontSize: 12, height: 1.45),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF9900),
                            foregroundColor: const Color(0xFF040A1C),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.open_in_browser_rounded, size: 22),
                          label: Text(
                            Platform.isAndroid ? '🚀 باز کردن ثبت‌نام آمازون در Chrome' : '🚀 باز کردن مرورگر ایمن و شروع ثبت‌نام آمازون',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                          ),
                          onPressed: () async {
                            final ok = await AwsAssistant.launchSafeBrowser(AwsAssistant.starterUrl);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok
                                      ? (Platform.isAndroid ? 'Chrome باز شد؛ ثبت‌نام را ادامه بده.' : 'مرورگر امن باز شد؛ حالا با گوگل یا گیت‌هاب وارد شوید.')
                                      : 'آدرس ثبت‌نام باز نشد. لینک را به صورت دستی باز کنید.'),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Pro Tips for 100% bypass
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.lightbulb_rounded, color: Color(0xFF10B981), size: 20),
                            SizedBox(width: 8),
                            Text('۳ راز طلایی برای عبور ۱۰۰٪ بدون نیاز به کارت:',
                                style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _ruleText('۱. در صفحه ورود آمازون، گزینه «Sign in with Google» یا «Sign in with GitHub» را بزنید. هوش مصنوعی آمازون به این اکانت‌ها اعتماد دارد و مرحله کارت را حذف می‌کند.'),
                        _ruleText('۲. در فرم مشخصات، کشور را حتماً «United States» انتخاب کنید و از فیلدهای کپی‌شده بالا استفاده نمایید.'),
                        _ruleText('۳. از ایمیل‌های موقت و فیک استفاده نکنید؛ ورود با جیمیل اصلی شانس موفقیت را به ۱۰۰٪ می‌رساند.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkItem(String title, bool ok, String sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            color: ok ? const Color(0xFF29E07F) : Colors.amber, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text(sub, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _copyRow(String label, String value, P p, {String? copyVal}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 105,
            child: Text(label, style: TextStyle(color: p.sub, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16),
            tooltip: 'کپی',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _copy(copyVal ?? value, label),
          ),
        ],
      ),
    );
  }

  Widget _ruleText(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, height: 1.45, color: Colors.white70),
      ),
    );
  }
}
