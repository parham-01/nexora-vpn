import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart' as ww;

const String _signupUrl = 'https://accounts.firefox.com/signup';

String get _userAgent => Platform.isAndroid
    ? 'Mozilla/5.0 (Android 14; Mobile; rv:145.0) Gecko/145.0 Firefox/145.0'
    : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:145.0) Gecko/20100101 Firefox/145.0';

/// ثبت‌نام Firefox: اول یادآوری روشن‌بودن VPN/فیلترشکن، بعد باز شدن سایت ثبت‌نام Mozilla
/// در یک وب کوچک داخل اپ (ویندوز/اندروید) یا مرورگر سیستم (لینوکس/مک).
/// بعد از ثبت‌نام، کاربر با همان ایمیل و پسورد از بخش Login وارد می‌شود.
Future<void> startFirefoxSignUp(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ثبت‌نام Firefox'),
      content: const Text(
        'برای ثبت‌نام باید VPN یا فیلترشکن روشن باشد.\n\nVPN یا فیلترشکن روشن است؟',
        textDirection: TextDirection.rtl,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بله، روشن است')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));
  if (Platform.isWindows || Platform.isAndroid) {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const FirefoxSignupPage()),
    );
    if (done == true) say('ثبت‌نام انجام شد؛ حالا ایمیل و پسورد را وارد کن و Login بزن');
    return;
  }
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [_signupUrl]);
    } else {
      await Process.run('xdg-open', [_signupUrl]);
    }
    say('سایت ثبت‌نام در مرورگر باز شد؛ بعد از ثبت‌نام، ایمیل و پسورد را در Login وارد کن');
  } catch (_) {
    await Clipboard.setData(const ClipboardData(text: _signupUrl));
    say('آدرس ثبت‌نام کپی شد؛ در مرورگر باز کن: $_signupUrl');
  }
}

class FirefoxSignupPage extends StatefulWidget {
  const FirefoxSignupPage({super.key});

  @override
  State<FirefoxSignupPage> createState() => _FirefoxSignupPageState();
}

class _FirefoxSignupPageState extends State<FirefoxSignupPage> {
  ww.WebviewController? _windows;
  StreamSubscription<ww.LoadingState>? _loadingSub;
  wf.WebViewController? _view;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    _loadingSub?.cancel();
    _windows?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      if (Platform.isWindows) {
        try {
          await ww.WebviewController.initializeEnvironment();
        } on PlatformException {
          // محیط WebView2 قبلاً ساخته شده است.
        }
        final c = ww.WebviewController();
        await c.initialize();
        await c.setBackgroundColor(Colors.white);
        await c.setPopupWindowPolicy(ww.WebviewPopupWindowPolicy.sameWindow);
        await c.setUserAgent(_userAgent);
        _loadingSub = c.loadingState.listen((s) {
          if (mounted && s == ww.LoadingState.navigationCompleted) setState(() => _loading = false);
        });
        await c.loadUrl(_signupUrl);
        if (!mounted) {
          await c.dispose();
          return;
        }
        setState(() => _windows = c);
      } else {
        late final wf.WebViewController c;
        c = wf.WebViewController()
          ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
          ..setUserAgent(_userAgent)
          ..setNavigationDelegate(wf.NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
            onWebResourceError: (e) {
              if (mounted && (e.isForMainFrame ?? true)) {
                setState(() => _error = 'سایت باز نشد؛ VPN یا فیلترشکن را روشن کن و دوباره تلاش کن.');
              }
            },
          ))
          ..loadRequest(Uri.parse(_signupUrl));
        if (mounted) setState(() => _view = c);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'صفحه ثبت‌نام باز نشد: $e');
    }
  }

  void _reload() {
    setState(() {
      _error = null;
      _loading = true;
    });
    _windows?.loadUrl(_signupUrl);
    _view?.loadRequest(Uri.parse(_signupUrl));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final web = _windows != null
        ? ww.Webview(_windows!)
        : _view != null
            ? wf.WebViewWidget(controller: _view!)
            : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ثبت‌نام Firefox'),
        actions: [
          IconButton(tooltip: 'بارگذاری دوباره', onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          Expanded(child: web ?? const Center(child: CircularProgressIndicator())),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('ثبت‌نام کردم، برو به Login'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
