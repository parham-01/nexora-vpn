import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../aws_assistant.dart';
import '../traffic_card.dart';
import '../vpn_service.dart';
import 'core/models.dart' show Account, AccountStatus, Location;
import 'firefox_login_page.dart';
import '../fx_backdrop.dart';
import '../intro_page.dart' show TourTarget;
import 'firefox_signup_page.dart';
import 'firefox_options_page.dart';
import 'firefox_service.dart';
import 'flag_colors.dart';

class FirefoxPage extends StatefulWidget {
  const FirefoxPage({super.key});

  @override
  State<FirefoxPage> createState() => _FirefoxPageState();
}

class _FirefoxPageState extends State<FirefoxPage> {
  final FirefoxService _service = FirefoxService.I;
  StreamSubscription<String>? _eventsSub;

  @override
  void initState() {
    super.initState();
    _eventsSub = _service.events.listen((m) {
      if (mounted) _message(m);
    });
    unawaited(_service.initialize().then((_) => _service.watchUsage(true)));
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _service.watchUsage(false);
    super.dispose();
  }

  Future<void> _selectAccount(Account account) async {
    try {
      await _service.selectAccount(account.id);
      if (mounted) _message('اکانت انتخاب شد');
    } catch (e) {
      if (mounted) _message(_clean(e));
    }
  }

  Future<void> _toggleAutoSwitch(bool value) async {
    await _service.setAutoSwitch(value);
  }

  void _showAutoSwitchHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auto-Switch / سوییچ خودکار'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  'Automatically switches to the next account when the active account runs out of data, and keeps using the next account\'s remaining data until the last account.',
                ),
              ),
              Divider(height: 24),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'برای سوییچ خودکار به اکانت بعدی در صورت اتمام حجم است؛ وقتی حجم اکانت فعال تمام شود، از حجم باقی‌مانده‌ی اکانت بعدی استفاده می‌شود و این روند تا آخرین اکانت ادامه دارد.',
                ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK / باشه'))],
      ),
    );
  }

  Future<void> _refresh() async {
    try {
      await _service.refresh();
    } catch (e) {
      if (mounted) _message(_clean(e));
    }
  }

  Future<void> _addAccount() async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FirefoxLoginPage(service: _service)),
    );
    if (done == true && mounted) _message('حساب Firefox اضافه شد');
  }

  Future<void> _deleteAccount(Account account) async {
    final name = account.email.isEmpty ? account.name : account.email;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف اکانت'),
        content: Text('اکانت $name از لیست برنامه حذف شود؟', textDirection: TextDirection.rtl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.removeAccount(account.id);
      if (mounted) _message('اکانت حذف شد');
    } catch (e) {
      if (mounted) _message(_clean(e));
    }
  }

  // کد لوکیشنی که همین الان در حال اتصال است (null = هیچ‌کدام)؛ روی همان لوکیشن اسپینر نمایش داده می‌شود
  String? _connectingCode;

  Future<bool> _hasInternet() async {
    try {
      final r = await InternetAddress.lookup('cloudflare.com').timeout(const Duration(seconds: 4));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// لمس یک لوکیشن: اگر همان لوکیشن وصل است قطع می‌شود، وگرنه (در صورت نیاز بعد از قطع قبلی)
  /// وضعیت اینترنت و حساب بررسی، اتصال برقرار و فقط بعد از تأیید واقعی هسته تیک نمایش داده می‌شود.
  Future<void> _tapLocation(Location location) async {
    if (_connectingCode != null) return;
    if (_service.isOn && _service.selectedCountry == location.code) {
      await _disconnect();
      return;
    }
    if (!_service.hasSelection) {
      _message('ابتدا یک اکانت را انتخاب کن');
      return;
    }
    if (!_service.hasAccount) {
      _message('اکانت انتخابی آماده نیست؛ دوباره وارد شو یا اکانت دیگری انتخاب کن');
      return;
    }
    setState(() => _connectingCode = location.code);
    try {
      final online = await _hasInternet();
      if (!mounted) return;
      if (!online) {
        _message('اینترنت در دسترس نیست؛ اتصال را بررسی کن');
        return;
      }
      if (_service.isOn) await _service.disconnect();
      await _service.selectLocation(location.code);
      if (!mounted) return;
      // Android permits one VpnService at a time; Windows also has one TUN
      // route. Stop Parham's existing engine through its public service API.
      final current = VpnService.I.status.value.phase;
      if (current != Phase.off) await VpnService.I.disconnect();
      await _service.connect();
      final until = DateTime.now().add(const Duration(seconds: 25));
      while (mounted && !_service.connected && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        try {
          await _service.refresh();
        } catch (_) {}
      }
      if (!mounted) return;
      if (_service.connected) {
        _message('متصل شدی');
        // فقط پینگ همین لوکیشن انتخاب‌شده (پروکسی روشن است؛ چند صد میلی‌ثانیه)
        unawaited(_service.pingLocation(location.code).catchError((Object _) => 0));
      } else {
        _message('اتصال تأیید نشد؛ دوباره تلاش کن');
        await _service.disconnect();
      }
    } catch (e) {
      if (mounted) _message(_clean(e));
    } finally {
      if (mounted) setState(() => _connectingCode = null);
    }
  }

  Future<void> _disconnect() async {
    try {
      await _service.disconnect();
      if (mounted) _message('Firefox قطع شد');
    } catch (e) {
      if (mounted) _message(_clean(e));
    }
  }

  /// تست پینگ فقط یک لوکیشن: [target] یا لوکیشن انتخاب‌شده‌ی فعلی.
  Future<void> _ping([Location? target]) async {
    if (_service.pinging) return;
    if (!_service.hasSelection) {
      _message('برای تست پینگ ابتدا یک اکانت را انتخاب کن');
      return;
    }
    Location? loc = target;
    if (loc == null) {
      for (final l in _service.locations) {
        if (l.code == _service.selectedCountry) loc = l;
      }
    }
    if (loc == null) {
      _message('یک لوکیشن را انتخاب کن (روی چیپ پینگ همان ردیف بزن)');
      return;
    }
    final name = loc.name.isEmpty ? loc.code.toUpperCase() : loc.name;
    try {
      final ms = await _service.pingLocation(loc.code);
      if (!mounted || ms < 0) return;
      _message(ms > 0 ? 'پینگ $name: $ms ms' : 'پینگ $name جواب نداد (Timeout)');
    } catch (e) {
      if (mounted) _message(_clean(e));
    }
  }

  Future<void> _pingAll() async {
    if (_service.pinging) return;
    if (!_service.hasSelection) {
      _message('برای تست پینگ ابتدا یک اکانت را انتخاب کن');
      return;
    }
    try {
      final n = await _service.pingAllLocations();
      if (!mounted || n < 0) return;
      _message(n > 0 ? 'پینگ $n لوکیشن گرفته شد' : 'هیچ لوکیشنی جواب نداد (Timeout)');
    } catch (e) {
      if (mounted) _message(_clean(e));
    }
  }

  void _cancelPing() {
    _service.cancelPing();
    if (mounted) _message('تست پینگ لغو شد');
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // کارت‌ها نیمه‌شفاف تا پس‌زمینه‌ی متحرک از پشتشان دیده شود
    final glassTheme = theme.copyWith(
      cardTheme: theme.cardTheme.copyWith(
        color: (theme.cardTheme.color ?? colors.surfaceContainerLow).withOpacity(0.74),
        surfaceTintColor: Colors.transparent,
      ),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text('Firefox VPN'),
        actions: [
          TourTarget('ff.options', IconButton(
            tooltip: 'گزینه‌های Nexora (پروکسی سیستم، رله، DNS)',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FirefoxOptionsPage()),
            ),
            icon: const Icon(Icons.tune_rounded),
          )),
          TourTarget('ff.refresh', IconButton(
            tooltip: 'بروزرسانی',
            onPressed: _service.busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          )),
        ],
      ),
      body: Stack(children: [
        const Positioned.fill(child: NexoraFxBackdrop(style: FxStyle.firefox)),
        Positioned.fill(child: Theme(data: glassTheme, child: AnimatedBuilder(
        animation: _service,
        builder: (context, _) {
          final accounts = _service.accounts;
          final locations = [..._service.locations]
            ..sort((a, b) {
              if (a.answered != b.answered) return a.answered ? -1 : 1;
              if (a.answered && b.answered && a.pingMs != b.pingMs) return a.pingMs.compareTo(b.pingMs);
              if (a.recommended != b.recommended) return a.recommended ? -1 : 1;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          final unsupported = !_service.supported;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            cacheExtent: 3000,
            children: [
              TourTarget('ff.hero', FxReveal(key: const ValueKey('fx-r0'), index: 0, child: _heroCard(theme))),
              const SizedBox(height: 10),
              TourTarget('ff.aws', Card(
                color: const Color(0xFF1E293B).withOpacity(0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: const Color(0xFFFF9900).withOpacity(0.4)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9900), Color(0xFFFF5500)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 22),
                  ),
                  title: Row(
                    children: [
                      const Text('دستیار ثبت‌نام ۱۰۰ دلار آمازون', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text('بدون کارت', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  subtitle: const Text('آدرس معتبر آمریکا + تنظیم ساعت ویندوز + مرورگر امن', style: TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () => showAwsAssistantSheet(context),
                ),
              )),
              const SizedBox(height: 10),
              if (_service.isOn && _service.status?.proxy != null) TrafficCard(reader: _trafficSample, title: 'اتصال Firefox', neon: true, fire: true),
              TourTarget('ff.ping', FxReveal(key: const ValueKey('fx-r2'), index: 2, child: _pingCard(theme, locations))),
              const SizedBox(height: 14),
              if (unsupported)
                _notice(
                  theme,
                  Icons.info_outline_rounded,
                  'پشتیبانی اتصال در این نسخه',
                  'هسته‌ی اتصال Firefox برای این پلتفرم در این نسخه آماده نشده است.',
                )
              else ...[
                _sectionTitle('اکانت‌ها (Mozilla)'),
                TourTarget('ff.accounts', Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (accounts.isEmpty)
                          const Text('هنوز حساب Firefox اضافه نشده است.')
                        else
                          for (final account in accounts) _accountRow(account),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TourTarget('ff.signin', OutlinedButton.icon(
                                onPressed: _service.busy ? null : () => _addAccount(),
                                icon: const Icon(Icons.login_rounded),
                                label: const Text('Sign In'),
                              )),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TourTarget('ff.signup', OutlinedButton.icon(
                                onPressed: _service.busy ? null : () => startFirefoxSignUp(context),
                                icon: const Icon(Icons.person_add_alt_1_rounded),
                                label: const Text('Sign Up'),
                              )),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )),
                const SizedBox(height: 12),
                TourTarget('ff.auto', FxReveal(key: const ValueKey('fx-r4'), index: 4, child: _autoSwitchCard())),
                const SizedBox(height: 12),
                if (!_service.hasSelection)
                  TourTarget('ff.locations', _notice(
                    theme,
                    Icons.lock_outline_rounded,
                    'لوکیشن‌ها',
                    'برای دیدن کشورها و سرورها، ابتدا یکی از اکانت‌ها را با دکمه‌ی «انتخاب» تیک بزن.',
                  ))
                else ...[
                _sectionTitle('لوکیشن‌ها'),
                TourTarget('ff.locations', Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text('سرورهای Firefox', style: TextStyle(fontWeight: FontWeight.w700))),
                            Text('${locations.length} لوکیشن', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (locations.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(child: Text('فهرست لوکیشن‌ها هنوز دریافت نشده است.')),
                          )
                        else
                          Column(
                            children: [
                              for (final location in locations) _locationRow(location),
                            ],
                          ),
                        if (_service.connected)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('برای قطع اتصال دوباره روی همان لوکیشن بزن', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                )),
                ],
              ],
              if (_service.error != null && _service.error!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _notice(theme, Icons.error_outline_rounded, 'پیام هسته Firefox', _service.error!),
              ],
              if (_service.busy) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ],
          );
        },
      ))),
      ]),
    );
  }

  TrafficSample _trafficSample() {
    final st = _service.status;
    final proxy = st?.proxy;
    final t = st?.traffic;
    final on = _service.isOn && proxy != null;
    final started = proxy?.startedAt;
    final secs = on && started != null ? DateTime.now().difference(started).inSeconds.clamp(0, 1 << 31) : 0;
    final acc = _service.selectedAccount;
    final u = acc?.usage;
    double? frac;
    var qtext = '';
    if (acc != null && u != null) {
      if (u.unlimited) {
        qtext = 'حجم باقی‌مانده: نامحدود';
      } else if (u.limitBytes > 0) {
        final left = u.remainingBytes < 0 ? 0 : u.remainingBytes;
        frac = (u.limitBytes - left) / u.limitBytes;
        qtext = 'حجم باقی‌مانده: ${_fmtBytes(left)} از ${_fmtBytes(u.limitBytes)}';
      }
    }
    return TrafficSample(
      on: on,
      down: t?.downRate ?? 0,
      up: t?.upRate ?? 0,
      downTotal: t?.down ?? 0,
      upTotal: t?.up ?? 0,
      seconds: secs,
      directDown: t?.directDown ?? 0,
      directUp: t?.directUp ?? 0,
      quotaFraction: frac,
      quotaText: qtext,
    );
  }

  Widget _heroCard(ThemeData theme) {
    return const FxHeroCard(
      leading: Text('🦊', style: TextStyle(fontSize: 42)),
      title: 'Firefox Secure Connection',
      subtitle: 'ورود Mozilla، انتخاب کشور و تست تأخیر در یک بخش مستقل',
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      );

  Widget _accountRow(Account account) {
    final theme = Theme.of(context);
    final isSelected = _service.selectedAccountId == account.id;
    final usage = account.usage;
    final ok = account.enabled && !account.needsSignIn;
    double? fraction;
    if (usage != null && !usage.unlimited && usage.limitBytes > 0) {
      fraction = (usage.usedBytes / usage.limitBytes).clamp(0.0, 1.0).toDouble();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            child: Icon(isSelected ? Icons.check_rounded : Icons.account_circle_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.email.isEmpty ? account.name : account.email,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _accountStatus(account),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: ok ? null : Colors.orange),
                ),
                const SizedBox(height: 2),
                Text(
                  _remainingText(account),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (fraction != null) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: fraction, minHeight: 5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected)
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 30)
              else
                OutlinedButton(
                  onPressed: _service.busy || account.needsSignIn ? null : () => _selectAccount(account),
                  child: const Text('انتخاب'),
                ),
              TextButton.icon(
                onPressed: _service.busy ? null : () => _deleteAccount(account),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('حذف'),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent, visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _remainingText(Account account) {
    final u = account.usage;
    if (account.needsSignIn) return 'حجم باقی‌مانده: —';
    if (u == null) return 'حجم باقی‌مانده: در حال دریافت…';
    if (u.unlimited) return 'حجم باقی‌مانده: نامحدود';
    final left = u.remainingBytes < 0 ? 0 : u.remainingBytes;
    return 'حجم باقی‌مانده: ${_fmtBytes(left)} از ${_fmtBytes(u.limitBytes)}';
  }

  String _fmtBytes(int b) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 2)} ${units[i]}';
  }

  Widget _autoSwitchCard() => Card(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 8, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text('سوییچ خودکار (Auto-Switch)', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              InkResponse(
                onTap: _showAutoSwitchHelp,
                radius: 20,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.6),
                  ),
                  child: Text(
                    '?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Switch(value: _service.autoSwitch, onChanged: _service.busy ? null : _toggleAutoSwitch),
            ],
          ),
        ),
      );

  String _accountStatus(Account account) {
    if (account.needsSignIn) return 'نیاز به ورود دوباره';
    if (!account.enabled) return 'حساب غیرفعال است';
    if (account.status.isNotEmpty && account.status != AccountStatus.ready) return account.status;
    return 'حساب آماده استفاده است';
  }

  /// کارت «پینگ فایرفاکس»: همیشه بالای صفحه؛ فقط پینگ لوکیشن انتخاب‌شده را می‌گیرد (نه همه‌ی لوکیشن‌ها).
  Widget _pingCard(ThemeData theme, List<Location> locations) {
    final pinging = _service.pinging;
    Location? selected;
    for (final l in locations) {
      if (l.code == _service.selectedCountry) selected = l;
    }
    final selName = selected == null ? '' : (selected.name.isEmpty ? selected.code.toUpperCase() : selected.name);
    const green = Color(0xFF69F0AE);
    final answered = selected != null && selected.answered;
    final okList = locations.where((l) => l.answered).toList();
    final bestMs = okList.isEmpty ? 0 : okList.map((l) => l.pingMs).reduce((a, b) => a < b ? a : b);
    final avgMs = okList.isEmpty ? 0 : (okList.map((l) => l.pingMs).reduce((a, b) => a + b) / okList.length).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12307A), Color(0xFF0B5E9E)],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
        boxShadow: [BoxShadow(color: const Color(0xFF0B5E9E).withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _RadarPulse(active: pinging, child: const Icon(Icons.speed_rounded, color: Colors.white, size: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('پینگ فایرفاکس', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      pinging
                          ? (_service.pingingAll ? 'در حال تست پینگ همه‌ی لوکیشن‌ها…' : 'در حال تست پینگ ${_service.pingingCode == null ? '' : _nameOf(locations, _service.pingingCode!)}…')
                          : 'همه‌ی لوکیشن‌ها با هم تست می‌شوند؛ کمترین پینگ بالا می‌آید',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (answered && !pinging)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.28), borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: green, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${selected!.pingMs} ms', textDirection: TextDirection.ltr, style: const TextStyle(color: green, fontWeight: FontWeight.w800)),
                  ]),
                ),
            ],
          ),
          if (pinging) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: const LinearProgressIndicator(minHeight: 6, color: green, backgroundColor: Colors.white24),
            ),
          ],
          if (okList.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              _pingStat('سریع‌ترین', '$bestMs ms', green),
              const SizedBox(width: 8),
              _pingStat('میانگین', '$avgMs ms', const Color(0xFFFFE082)),
              const SizedBox(width: 8),
              _pingStat('پاسخ‌گو', '${okList.length}/${locations.length}', Colors.white),
            ]),
          ],
          const SizedBox(height: 12),
          if (pinging)
            FilledButton.icon(
              onPressed: _cancelPing,
              icon: const Icon(Icons.stop_circle_rounded),
              label: const Text('لغو تست پینگ'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
              ),
            )
          else
            FilledButton.icon(
              onPressed: _service.supported && !_service.busy && _service.hasSelection ? _pingAll : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('تست پینگ همه‌ی لوکیشن‌ها'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0B3A7A),
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          if (!pinging)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                !_service.hasSelection
                    ? 'برای تست، ابتدا یک اکانت را «انتخاب» کن.'
                    : 'برای تست فقط یک لوکیشن، روی چیپ پینگ همان ردیف بزن.',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pingStat(String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.25),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Column(children: [
            Text(value, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ]),
        ),
      );

  static Color _pingColor(int ms) => ms <= 150 ? const Color(0xFF69F0AE) : ms <= 350 ? const Color(0xFFFFE082) : const Color(0xFFFF8A65);

  static Widget _signalBars(int ms, Color c) {
    final lvl = ms <= 150 ? 3 : ms <= 350 ? 2 : 1;
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 1; i <= 3; i++)
        Container(
          width: 3.5,
          height: 4.0 + i * 3.5,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(color: i <= lvl ? c : Colors.white24, borderRadius: BorderRadius.circular(2)),
        ),
    ]);
  }

  String _nameOf(List<Location> locations, String code) {
    for (final l in locations) {
      if (l.code == code) return l.name.isEmpty ? l.code.toUpperCase() : l.name;
    }
    return code.toUpperCase();
  }

  /// ردیف مستطیلی لوکیشن (هر ردیف یک کشور): پس‌زمینه با رنگ‌های پرچم همان کشور،
  /// نام کشور و شهر، پینگ، و اسپینر/تیک اتصال.
  Widget _locationRow(Location location) {
    final connecting = _connectingCode == location.code;
    final isCurrent = _service.selectedCountry == location.code;
    final verified = _service.connected && isCurrent && !connecting;
    final locked = _connectingCode != null && !connecting;
    final name = location.name.isEmpty ? location.code.toUpperCase() : location.name;
    final city = location.city.trim();
    final hasPing = location.answered;
    final waiting = _service.pingingCode == location.code || _service.pingingAll;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: locked ? 0.55 : 1,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: verified ? Border.all(color: const Color(0xFF69F0AE), width: 2) : null,
            boxShadow: [
              BoxShadow(
                color: (verified ? const Color(0xFF69F0AE) : Colors.black).withOpacity(verified ? 0.35 : 0.25),
                blurRadius: verified ? 16 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: (_connectingCode != null || (_service.busy && !_service.isOn)) ? null : () => _tapLocation(location),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(painter: FlagPainter(flagSpecFor(location.code))),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [Colors.black.withOpacity(0.50), Colors.black.withOpacity(0.18)],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                                  ),
                                ),
                                if (city.isNotEmpty)
                                  Text(
                                    city,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12, shadows: [Shadow(color: Colors.black87, blurRadius: 3)]),
                                  ),
                              ],
                            ),
                          ),
                          if (connecting)
                            const WarpSpinner(size: 40)
                          else if (verified)
                            const VerifiedTick(size: 24)
                          else if (waiting)
                            const WarpSpinner(size: 24)
                          else
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: (_connectingCode != null || _service.pinging || _service.busy) ? null : () => _ping(location),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child:
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: (hasPing ? _pingColor(location.pingMs) : Colors.white24).withOpacity(0.55)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (hasPing) ...[_signalBars(location.pingMs, _pingColor(location.pingMs)), const SizedBox(width: 6)],
                                Text(
                                  hasPing ? '${location.pingMs} ms' : (location.pingError.isNotEmpty ? 'timeout' : '—'),
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(
                                    color: hasPing ? _pingColor(location.pingMs) : (location.pingError.isNotEmpty ? Colors.redAccent : Colors.white70),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ]),
                              ),
                            ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(ThemeData theme, IconData icon, String title, String body) => Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(body, style: theme.textTheme.bodySmall),
                ]),
              ),
            ],
          ),
        ),
      );
}

/// دایره‌ی رادار: هنگام تست پینگ موج می‌زند.
class _RadarPulse extends StatefulWidget {
  final bool active;
  final Widget child;
  const _RadarPulse({required this.active, required this.child});

  @override
  State<_RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<_RadarPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _RadarPulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Stack(alignment: Alignment.center, children: [
            if (widget.active)
              Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Container(
                  width: 46 + 14 * t,
                  height: 46 + 14 * t,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF69F0AE), width: 2)),
                ),
              ),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.14)),
              child: widget.child,
            ),
          ]);
        },
      ),
    );
  }
}
