import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/core_api.dart';
import 'core/models.dart' show DnsTestHost;
import 'core/relay_test.dart';
import 'firefox_service.dart';
import '../cloud_backup.dart';

/// گزینه‌های پیشرفته‌ی Nexora: پروکسی سیستم، رله‌ی کلادفلر، DNS، ECH، بکاپ و...
/// همه‌ی تنظیمات مستقیم در config هسته ذخیره می‌شود (فیلدهای ناشناخته دست‌نخورده می‌مانند).
class FirefoxOptionsPage extends StatefulWidget {
  const FirefoxOptionsPage({super.key});

  @override
  State<FirefoxOptionsPage> createState() => _FirefoxOptionsPageState();
}

class _FirefoxOptionsPageState extends State<FirefoxOptionsPage> {
  static const Map<String, List<String>> _dnsPresets = {
    'auto': ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query', 'https://9.9.9.9/dns-query'],
    'cloudflare': ['https://1.1.1.1/dns-query', 'https://1.0.0.1/dns-query'],
    'google': ['https://8.8.8.8/dns-query', 'https://8.8.4.4/dns-query'],
    'quad9': ['https://9.9.9.9/dns-query', 'https://149.112.112.112/dns-query'],
    'cloudflare_dot': ['tls://1.1.1.1', 'tls://1.0.0.1'],
    'system': <String>[],
  };

  static const Map<String, String> _dnsLabels = {
    'auto': 'خودکار (Cloudflare + Google + Quad9)',
    'cloudflare': 'Cloudflare — DoH',
    'google': 'Google — DoH',
    'quad9': 'Quad9 — DoH',
    'cloudflare_dot': 'Cloudflare — DoT (853)',
    'system': 'DNS سیستم',
    'custom': 'سفارشی (دست‌نخورده)',
  };

  final FirefoxService _service = FirefoxService.I;
  CoreApi? _api;
  Map<String, Object?> _cfg = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _relayCtl = TextEditingController();
  final _workerHostCtl = TextEditingController();
  final _secretCtl = TextEditingController();
  final _upstreamCtl = TextEditingController();

  bool _relayOn = false;
  bool _sharedRelay = true;
  bool _upstreamOn = false;
  bool _verbose = false;
  bool _dnsFallback = true;
  String _ech = 'on';
  String _split = 'off';
  String _dns = 'auto';

  bool get _desktopProxy => Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _relayCtl.dispose();
    _workerHostCtl.dispose();
    _secretCtl.dispose();
    _upstreamCtl.dispose();
    super.dispose();
  }

  Map<String, Object?> _sub(String key) {
    final v = _cfg[key];
    final m = v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
    _cfg[key] = m;
    return m;
  }

  Future<void> _load() async {
    try {
      final api = await _service.ensureApi();
      final cfg = Map<String, Object?>.from(await api.settings());
      _api = api;
      _cfg = cfg;
      final net = _sub('network');
      _relayCtl.text = (net['api_relay'] as String?) ?? '';
      final ru = Uri.tryParse(_relayCtl.text);
      if (ru != null && ru.host.isNotEmpty) {
        _workerHostCtl.text = ru.host;
        _secretCtl.text = ru.queryParameters['secret'] ?? '';
      }
      if (_secretCtl.text.isEmpty) _secretCtl.text = _randomSecret();
      _relayOn = net['api_relay_enabled'] == true;
      _sharedRelay = net['shared_relay_enabled'] != false;
      _ech = switch (net['api_relay_ech']) {
        'require' => 'require',
        'off' => 'off',
        _ => 'on',
      };
      _split = switch (net['hello_split']) {
        'first-byte' => 'first-byte',
        'sni' => 'sni',
        'record' => 'record',
        _ => 'off',
      };
      _upstreamCtl.text = (net['upstream_proxy'] as String?) ?? '';
      _upstreamOn = net['upstream_proxy_enabled'] == true;

      final dns = _sub('dns');
      final servers = [for (final s in (dns['servers'] as List? ?? const [])) '$s'];
      _dnsFallback = dns['fallback_to_system'] != false;
      _dns = 'custom';
      for (final e in _dnsPresets.entries) {
        if (_sameList(e.value, servers)) {
          _dns = e.key;
          break;
        }
      }
      _verbose = _sub('logging')['verbose'] == true;
      _error = null;
    } catch (e) {
      _error = _clean(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String _clean(Object e) {
    if (e is CoreApiException) return e.message;
    return e.toString().replaceFirst('Exception: ', '');
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _save({String? done}) async {
    final api = _api;
    if (api == null) return;
    setState(() => _saving = true);
    try {
      final net = _sub('network');
      final relay = _relayCtl.text.trim();
      if (relay.isNotEmpty) {
        final u = Uri.tryParse(relay);
        if (u == null || u.scheme != 'https' || u.host.isEmpty || u.queryParameters.containsKey('url')) {
          throw StateError('آدرس رله باید https باشد و پارامتر url نداشته باشد.');
        }
      }
      net['api_relay'] = relay;
      net['api_relay_enabled'] = relay.isNotEmpty && _relayOn;
      net['shared_relay_enabled'] = _sharedRelay;
      net['api_relay_ech'] = _ech;
      net['hello_split'] = _split;
      final up = _upstreamCtl.text.trim();
      net['upstream_proxy'] = up;
      net['upstream_proxy_enabled'] = up.isNotEmpty && _upstreamOn;

      final dns = _sub('dns');
      if (_dns != 'custom') dns['servers'] = _dnsPresets[_dns] ?? const <String>[];
      dns['fallback_to_system'] = _dnsFallback;
      _sub('logging')['verbose'] = _verbose;

      await api.saveSettings(_cfg);
      await _service.refresh();
      _toast(done ?? 'ذخیره شد');
      await _load();
    } catch (e) {
      _toast(_clean(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------- relay

  String _randomSecret() {
    const chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _copyWorker() async {
    try {
      final code = await rootBundle.loadString('assets/relay/nexora-relay-worker.js');
      await Clipboard.setData(ClipboardData(text: code));
      _toast('کد Worker کپی شد — در Cloudflare جایگزین کد پیش‌فرض کن');
    } catch (_) {
      _toast('فایل کد Worker پیدا نشد');
    }
  }

  void _buildRelayUrl() {
    var host = _workerHostCtl.text.trim();
    host = host.replaceFirst(RegExp(r'^https?://'), '').split('/').first.split('?').first;
    final secret = _secretCtl.text.trim();
    if (host.isEmpty || secret.isEmpty) {
      _toast('آدرس Worker و رمز (SECRET) را وارد کن');
      return;
    }
    setState(() {
      _relayCtl.text = 'https://$host/?secret=${Uri.encodeQueryComponent(secret)}';
      _relayOn = true;
    });
    _toast('آدرس ساخته شد؛ «ذخیره» را بزن');
  }

  Future<void> _testRelay() async {
    final api = _api;
    final url = _relayCtl.text.trim();
    if (api == null) return;
    if (url.isEmpty) {
      _toast('اول آدرس رله را وارد کن');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _RelayTestDialog(api: api, url: url),
    );
  }

  Widget _relayInfoCard() {
    final c = Theme.of(context).colorScheme.primary;
    const steps = [
      'در Cloudflare یک Worker بساز (Workers & Pages ← Create ← Hello World ← Deploy).',
      'دکمه‌ی «کپی کد Worker» را بزن، در Edit code همه‌ی کد را با آن جایگزین کن و Deploy بزن.',
      'در Settings ← Variables and Secrets یک Secret با نام RELAY_SECRET و همین رمزی که پایین‌تر می‌بینی بساز.',
      'آدرس Worker را پایین بنویس و «ساخت و فعال‌سازی» را بزن؛ بعد «ذخیره» و «تست سلامت».',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withOpacity(0.5)),
        color: c.withOpacity(0.08),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.cloud_rounded, color: c, size: 20),
          const SizedBox(width: 8),
          const Text('رله‌ی کلادفلر چیست؟', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        const Text(
          'گاهی Mozilla از کشور یا اینترنت تو جواب نمی‌دهد و ورود به حساب یا دریافت لیست سرورها نمی‌شود. '
          'رله یک پل کوچک و رایگان روی حساب کلادفلر خودت است: درخواست‌های ورود، حساب و لیست سرورها اول به آن پل می‌رود و از آنجا به Mozilla می‌رسد. '
          'ترافیک VPN و گشت‌وگذار تو هرگز از رله رد نمی‌شود. اگر Mozilla مستقیم کار می‌کند، به رله نیازی نداری.',
          style: TextStyle(height: 1.7, fontSize: 13),
        ),
        const SizedBox(height: 10),
        const Text('راه‌اندازی در ۴ قدم:', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text('${i + 1}) ${steps[i]}', style: const TextStyle(height: 1.6, fontSize: 13)),
          ),
      ]),
    );
  }

  void _showRelayGuide() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('راه‌اندازی رله‌ی کلادفلر'),
        content: const SingleChildScrollView(
          child: Text(
            'رله فقط برای ورود، حساب و لیست سرورها استفاده می‌شود (نه ترافیک VPN). '
            'وقتی Mozilla از منطقه‌ی تو جواب نمی‌دهد به کار می‌آید.\n\n'
            '۱) در Cloudflare: Workers & Pages ← Create ← Hello World ← Deploy ← Edit code.\n\n'
            '۲) دکمه‌ی «کپی کد Worker» را بزن و کل کد پیش‌فرض را با آن جایگزین کن، بعد Deploy.\n\n'
            '۳) در Worker: Settings ← Variables and Secrets ← Add ← Type: Secret ← '
            'Name: RELAY_SECRET ← Value: همان رمزی که با «ساخت رمز» می‌سازی (یا هر رمز دلخواه).\n\n'
            '۴) چه چیزی را جایگزین کنی؟ آدرس نهایی این شکلی است:\n'
            'https://WORKER.ACCOUNT.workers.dev/?secret=SECRET\n'
            '• WORKER.ACCOUNT ← آدرسی که کلادفلر بعد از Deploy می‌دهد (مثلا relay.myname.workers.dev)\n'
            '• SECRET ← دقیقا همان مقدار RELAY_SECRET\n\n'
            '۵) آدرس را در فیلد «آدرس رله» بگذار (یا از ساخت‌دهنده‌ی آدرس استفاده کن)، '
            'کلید «رله‌ی شخصی» را روشن کن، ذخیره بزن و «تست سلامت رله» را اجرا کن.\n\n'
            'نکته: اگر workers.dev در شبکه‌ی تو بسته است، یک دامنه‌ی سفارشی روی همان Worker بگذار.',
            style: TextStyle(height: 1.7),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
      ),
    );
  }

  // ------------------------------------------------------------------ dns

  Future<void> _testDns() async {
    final api = _api;
    if (api == null) return;
    final servers = _dns == 'custom'
        ? [for (final s in (_sub('dns')['servers'] as List? ?? const [])) '$s']
        : (_dnsPresets[_dns] ?? const <String>[]);
    _toast('در حال تست DNS…');
    try {
      final res = await api.testDns(servers);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('نتیجه‌ی تست DNS'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final DnsTestHost h in res)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text(
                        '${h.host}\n'
                        '${h.error.isNotEmpty ? 'خطا: ${h.error}' : '${h.ms}ms  ${h.addrs.take(2).join(', ')}'}'
                        '${h.filtered ? '\n⚠ شبکه این نام را فیلتر/دستکاری می‌کند' : ''}',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(height: 1.5, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
        ),
      );
    } catch (e) {
      _toast(_clean(e));
    }
  }

  // --------------------------------------------------------------- backup

  Future<void> _exportBackup() async {
    final api = _api;
    if (api == null) return;
    try {
      final b = await api.exportBackup();
      final env = Platform.environment;
      final home = env['HOME'] ?? Directory.systemTemp.path;
      final dl = Directory('$home/Downloads');
      final dir = await dl.exists() ? dl.path : home;
      final path = '$dir/${b.name}';
      await File(path).writeAsBytes(b.bytes, flush: true);
      _toast('بکاپ ذخیره شد: $path');
    } catch (e) {
      _toast(_clean(e));
    }
  }

  Future<void> _importBackup() async {
    final api = _api;
    if (api == null) return;
    final ctl = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بازیابی بکاپ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('مسیر فایل zip بکاپ را وارد کن. حساب‌ها و تنظیمات فعلی جایگزین می‌شوند.',
                style: TextStyle(height: 1.6)),
            const SizedBox(height: 10),
            TextField(
              controller: ctl,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(hintText: '/home/user/Downloads/Nexora-VPN-backup.zip'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('بازیابی')),
        ],
      ),
    );
    ctl.dispose();
    if (path == null || path.isEmpty) return;
    try {
      final bytes = await File(path).readAsBytes();
      await api.importBackup(bytes);
      await _service.refresh();
      _toast('بکاپ بازیابی شد');
      await _load();
    } catch (e) {
      _toast(_clean(e));
    }
  }

  // ------------------------------------------------------------------- ui

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(t, style: TextStyle(fontSize: 12, height: 1.7, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  @override
  Widget build(BuildContext context) {
    final status = _service.status;
    return Scaffold(
      appBar: AppBar(title: const Text('گزینه‌های Nexora')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (_error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(_error!),
                    ),
                  ),
                if (_desktopProxy) ...[
                  _title('حالت اتصال'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'set', label: Text('پروکسی سیستم'), icon: Icon(Icons.public_rounded)),
                              ButtonSegment(value: 'clear', label: Text('فقط پروکسی'), icon: Icon(Icons.lan_rounded)),
                            ],
                            selected: {_service.desktopMode},
                            onSelectionChanged: (v) async {
                              await _service.setDesktopMode(v.first);
                              if (mounted) setState(() {});
                            },
                          ),
                          _hint(Platform.isMacOS
                              ? 'پروکسی سیستم: مک با networksetup، همه‌ی برنامه‌هایی که از تنظیمات شبکه‌ی سیستم پیروی می‌کنند از VPN رد می‌شوند.'
                              : 'پروکسی سیستم: لینوکس با gsettings (GNOME) یا kwriteconfig (KDE) تنظیم می‌شود؛ برنامه‌هایی که تنظیمات سیستم را می‌خوانند از VPN رد می‌شوند.'),
                          _hint('فقط پروکسی: چیزی در تنظیمات سیستم عوض نمی‌شود؛ هر برنامه را خودت روی آدرس محلی'
                              '${status?.proxy?.listen.isNotEmpty == true ? ' (${status!.proxy!.listen})' : ''} '
                              'ست کن (مرورگر، تلگرام، ترمینال و...).'),
                        ],
                      ),
                    ),
                  ),
                ],
                _title('بکاپ ابری'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_sync_rounded),
                    title: const Text('بکاپ و بازیابی اکانت‌ها'),
                    subtitle: const Text('حتی بعد از حذف برنامه با کد بازیابی برمی‌گردد'),
                    onTap: () => CloudBackup.showSheet(context),
                  ),
                ),
                _title('رله‌ی کلادفلر (Cloudflare Worker)'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _relayInfoCard(),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('استفاده از رله‌ی من'),
                          subtitle: const Text('خاموش کردنش تنظیمات را نگه می‌دارد'),
                          value: _relayOn,
                          onChanged: (v) => setState(() => _relayOn = v),
                        ),
                        TextField(
                          controller: _workerHostCtl,
                          textDirection: TextDirection.ltr,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'آدرس Worker',
                            hintText: 'relay.myname.workers.dev',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _secretCtl,
                          textDirection: TextDirection.ltr,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'رمز (RELAY_SECRET)',
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'ساخت رمز تصادفی',
                                  icon: const Icon(Icons.casino_rounded),
                                  onPressed: () => setState(() => _secretCtl.text = _randomSecret()),
                                ),
                                IconButton(
                                  tooltip: 'کپی رمز',
                                  icon: const Icon(Icons.content_copy_rounded),
                                  onPressed: () => Clipboard.setData(ClipboardData(text: _secretCtl.text)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _buildRelayUrl,
                              icon: const Icon(Icons.link_rounded),
                              label: const Text('ساخت و فعال‌سازی'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _copyWorker,
                              icon: const Icon(Icons.content_copy_rounded),
                              label: const Text('کپی کد Worker'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _testRelay,
                              icon: const Icon(Icons.health_and_safety_rounded),
                              label: const Text('تست سلامت'),
                            ),
                          ],
                        ),
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('پیشرفته', style: TextStyle(fontWeight: FontWeight.w700)),
                            children: [
                              TextField(
                                controller: _relayCtl,
                                textDirection: TextDirection.ltr,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'آدرس کامل رله',
                                  hintText: 'https://relay.NAME.workers.dev/?secret=SECRET',
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _showRelayGuide,
                                icon: const Icon(Icons.help_outline_rounded),
                                label: const Text('راهنمای کامل'),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('رله‌ی مشترک'),
                                subtitle: const Text('اگر رله‌ی خودت نبود یا کار نکرد، از رله‌های آماده استفاده شود'),
                                value: _sharedRelay,
                                onChanged: (v) => setState(() => _sharedRelay = v),
                              ),
                              DropdownButtonFormField<String>(
                                value: _ech,
                                decoration: const InputDecoration(labelText: 'ECH (پنهان‌کردن نام رله از شبکه)'),
                                items: const [
                                  DropdownMenuItem(value: 'on', child: Text('روشن (در صورت وجود کلید)')),
                                  DropdownMenuItem(value: 'require', child: Text('اجباری (بدون ECH درخواست نرود)')),
                                  DropdownMenuItem(value: 'off', child: Text('خاموش')),
                                ],
                                onChanged: (v) => setState(() => _ech = v ?? 'on'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _title('DNS'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          value: _dns,
                          decoration: const InputDecoration(labelText: 'سرور DNS هسته'),
                          items: [
                            for (final e in _dnsLabels.entries)
                              DropdownMenuItem(value: e.key, child: Text(e.value)),
                          ],
                          onChanged: (v) => setState(() => _dns = v ?? 'auto'),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('برگشت به DNS سیستم'),
                          subtitle: const Text('اگر همه‌ی سرورهای بالا جواب ندادند'),
                          value: _dnsFallback,
                          onChanged: (v) => setState(() => _dnsFallback = v),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            onPressed: _testDns,
                            icon: const Icon(Icons.speed_rounded),
                            label: const Text('تست DNS'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _title('شبکه‌ی فیلترشده'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          value: _split,
                          decoration: const InputDecoration(labelText: 'تکه‌کردن ClientHello (برای فیلتر بر اساس نام)'),
                          items: const [
                            DropdownMenuItem(value: 'off', child: Text('خاموش')),
                            DropdownMenuItem(value: 'first-byte', child: Text('بایت اول')),
                            DropdownMenuItem(value: 'sni', child: Text('وسط نام (SNI)')),
                            DropdownMenuItem(value: 'record', child: Text('دو رکورد TLS')),
                          ],
                          onChanged: (v) => setState(() => _split = v ?? 'off'),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('پروکسی SOCKS5 بالادستی'),
                          subtitle: const Text('اتصال به Mozilla از یک پروکسی دیگر (مثلا v2ray محلی) رد شود'),
                          value: _upstreamOn,
                          onChanged: (v) => setState(() => _upstreamOn = v),
                        ),
                        TextField(
                          controller: _upstreamCtl,
                          textDirection: TextDirection.ltr,
                          autocorrect: false,
                          decoration: const InputDecoration(labelText: 'host:port', hintText: '127.0.0.1:10808'),
                        ),
                      ],
                    ),
                  ),
                ),
                _title('بکاپ و ابزار'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _exportBackup,
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('گرفتن بکاپ'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _importBackup,
                              icon: const Icon(Icons.upload_rounded),
                              label: const Text('بازیابی بکاپ'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                try {
                                  await _api?.openFolder();
                                } catch (e) {
                                  _toast(_clean(e));
                                }
                              },
                              icon: const Icon(Icons.folder_open_rounded),
                              label: const Text('پوشه‌ی داده'),
                            ),
                          ],
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('لاگ کامل'),
                          subtitle: const Text('مقصدها هم لاگ می‌شوند (حساس به حریم خصوصی)'),
                          value: _verbose,
                          onChanged: (v) => setState(() => _verbose = v),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _save(),
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_rounded),
                  label: const Text('ذخیره'),
                ),
              ],
            ),
    );
  }
}

class _RelayTestDialog extends StatefulWidget {
  const _RelayTestDialog({required this.api, required this.url});
  final CoreApi api;
  final String url;

  @override
  State<_RelayTestDialog> createState() => _RelayTestDialogState();
}

class _RelayTestDialogState extends State<_RelayTestDialog> {
  final List<String> _lines = [];
  StreamSubscription<RelayTestEvent>? _sub;
  bool _running = true;
  bool? _ok;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _lines.clear();
    _running = true;
    _ok = null;
    _sub?.cancel();
    _sub = widget.api.testRelay(widget.url).listen(
      (e) {
        if (!mounted) return;
        setState(() {
          if (e.step != null) _lines.add(e.step!.logLine);
          if (e.result != null) {
            _ok = e.result!.ok;
            _running = false;
          }
        });
      },
      onError: (Object err) {
        if (!mounted) return;
        setState(() {
          _lines.add('ERROR  ${err is CoreApiException ? err.message : 'تست رله ناتمام ماند'}');
          _ok = false;
          _running = false;
        });
      },
      onDone: () {
        if (mounted) setState(() => _running = false);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _running
        ? 'در حال تست…'
        : (_ok == true ? 'رله آماده است ✅' : 'سلامت رله تأیید نشد');
    return AlertDialog(
      title: const Text('تست سلامت رله'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(summary, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              height: 220,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _lines.join('\n'),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _lines.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: _lines.join('\n'))),
          child: const Text('کپی گزارش'),
        ),
        TextButton(onPressed: _running ? null : () => setState(_start), child: const Text('تلاش دوباره')),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
      ],
    );
  }
}
