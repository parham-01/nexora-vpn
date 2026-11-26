import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart' as ww;

import 'firefox_service.dart';

String _mozillaLoginUrl(String email) => Uri.https('accounts.firefox.com', '/', {
      'context': 'fx_desktop_v3',
      'service': 'sync',
      'action': 'email',
      if (email.isNotEmpty) 'email': email,
    }).toString();

String get _firefoxUserAgent => Platform.isAndroid
    ? 'Mozilla/5.0 (Android 14; Mobile; rv:145.0) Gecko/145.0 Firefox/145.0'
    : Platform.isWindows
        ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:145.0) Gecko/20100101 Firefox/145.0'
        : Platform.isMacOS
            ? 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:145.0) Gecko/20100101 Firefox/145.0'
            : 'Mozilla/5.0 (X11; Linux x86_64; rv:145.0) Gecko/20100101 Firefox/145.0';

/// Reads Firefox's official WebChannel response. Only the short-lived
/// session token is passed to the local Nexora core; the password is never
/// read or stored by Parham.
class FxaWebChannel {
  FxaWebChannel({required this.reply, required this.onSession});

  final void Function(String js) reply;
  final void Function(String email, String token) onSession;
  String _lastToken = '';

  static final RegExp _tokenPattern = RegExp(r'^[0-9a-f]{64}$');

  static String hookJs(String post) => '''
(function () {
  if (window.__parhamFxaHooked) return;
  window.__parhamFxaHooked = true;
  var send = function (o) { try { $post } catch (e) {} };
  var onChannel = function (e) {
    var d = e.detail;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (e) { return; } }
    if (d && d.message) send({ kind: 'webchannel', detail: d });
  };
  window.addEventListener('WebChannelMessageToChrome', onChannel);
  document.addEventListener('WebChannelMessageToChrome', onChannel);
  window.__parhamFxaReply = function (id, messageId, command, data) {
    var detail = { id: id, message: { messageId: messageId, command: command, data: data } };
    window.dispatchEvent(new CustomEvent('WebChannelMessageToContent', { detail: detail }));
    document.dispatchEvent(new CustomEvent('WebChannelMessageToContent', { detail: detail }));
  };
})();
''';

  void handle(Object? raw) {
    Object? value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return;
      }
    }
    if (value is! Map || value['kind'] != 'webchannel') return;
    final detail = value['detail'];
    if (detail is! Map) return;
    final id = detail['id'];
    final message = detail['message'];
    if (id is! String || message is! Map) return;
    final command = message['command'];
    final messageId = message['messageId'];
    switch (command) {
      case 'fxaccounts:fxa_status':
        _reply(id, messageId, command as String, {
          'capabilities': <String, Object?>{},
          'signedInUser': null,
        });
      case 'fxaccounts:can_link_account':
        _reply(id, messageId, command as String, {'ok': true});
      case 'fxaccounts:login' || 'fxaccounts:oauth_login':
        _login(message['data']);
    }
  }

  void _reply(String id, Object? messageId, String command, Object data) {
    reply('window.__parhamFxaReply(${jsonEncode(id)}, ${jsonEncode(messageId)}, '
        '${jsonEncode(command)}, ${jsonEncode(data)})');
  }

  void _login(Object? data) {
    if (data is! Map) return;
    final token = data['sessionToken'] ?? data['token'];
    if (token is! String || !_tokenPattern.hasMatch(token) || token == _lastToken) return;
    _lastToken = token;
    final email = data['email'];
    onSession(email is String ? email : '', token);
  }
}

class FirefoxSignInPage extends StatefulWidget {
  const FirefoxSignInPage({super.key, required this.service, this.email = ''});

  final FirefoxService service;
  final String email;

  @override
  State<FirefoxSignInPage> createState() => _FirefoxSignInPageState();
}

class _FirefoxSignInPageState extends State<FirefoxSignInPage> {
  static bool _windowsEnvironmentReady = false;
  static int _windowsProxyPort = 0;
  late final FxaWebChannel _channel = FxaWebChannel(
    reply: _runJs,
    onSession: _handleSession,
  );

  ww.WebviewController? _windows;
  StreamSubscription<Object?>? _windowsMessages;
  StreamSubscription<ww.LoadingState>? _windowsLoading;
  wf.WebViewController? _view;
  bool _loading = true;
  bool _submitting = false;
  bool _success = false;
  bool _proxyOpen = false;
  bool _viewProxySet = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initView());
  }

  @override
  void dispose() {
    if (_submitting && !_success) unawaited(widget.service.cancelBrowserSignIn());
    if (_viewProxySet) unawaited(widget.service.setWebViewProxy(null));
    if (_proxyOpen) unawaited(widget.service.closeSignInProxy());
    _windowsMessages?.cancel();
    _windowsLoading?.cancel();
    _windows?.dispose();
    super.dispose();
  }

  Future<void> _initView() async {
    try {
      final proxy = await widget.service.openSignInProxy(port: _windowsProxyPort);
      if (proxy != null) _proxyOpen = true;
      if (!mounted) {
        if (_proxyOpen) await widget.service.closeSignInProxy();
        return;
      }
      if (Platform.isWindows) {
        await _initWindows(proxy);
      } else if (Platform.isAndroid) {
        if (proxy != null) {
          _viewProxySet = await widget.service.setWebViewProxy(proxy);
        }
        await _initMobile();
      } else {
        throw UnsupportedError('مرورگر ورود Firefox روی این پلتفرم پشتیبانی نمی‌شود');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _initWindows(String? proxy) async {
    if (!_windowsEnvironmentReady) {
      _windowsEnvironmentReady = true;
      try {
        await ww.WebviewController.initializeEnvironment(
          additionalArguments: proxy == null ? null : '--proxy-server=$proxy',
        );
        if (proxy != null) {
          _windowsProxyPort = int.tryParse(proxy.substring(proxy.lastIndexOf(':') + 1)) ?? 0;
        }
      } on PlatformException {
        // WebView2 can already be initialized after a hot restart.
      }
    }
    final controller = ww.WebviewController();
    await controller.initialize();
    await controller.setBackgroundColor(Colors.white);
    await controller.setPopupWindowPolicy(ww.WebviewPopupWindowPolicy.sameWindow);
    await controller.setUserAgent(_firefoxUserAgent);
    await controller.addScriptToExecuteOnDocumentCreated(
      FxaWebChannel.hookJs('window.chrome.webview.postMessage(o);'),
    );
    _windowsMessages = controller.webMessage.listen(_channel.handle);
    _windowsLoading = controller.loadingState.listen((state) {
      if (mounted && state == ww.LoadingState.navigationCompleted) {
        setState(() => _loading = false);
      }
    });
    await controller.loadUrl(_mozillaLoginUrl(widget.email));
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _windows = controller);
  }

  Future<void> _initMobile() async {
    late final wf.WebViewController controller;
    final hook = FxaWebChannel.hookJs('ParhamFxa.postMessage(JSON.stringify(o));');
    controller = wf.WebViewController()
      ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
      ..setUserAgent(_firefoxUserAgent)
      ..addJavaScriptChannel(
        'ParhamFxa',
        onMessageReceived: (message) => _channel.handle(message.message),
      )
      ..setNavigationDelegate(wf.NavigationDelegate(
        onPageStarted: (_) => controller.runJavaScript(hook),
        onPageFinished: (_) {
          controller.runJavaScript(hook);
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse(_mozillaLoginUrl(widget.email)));
    if (mounted) setState(() => _view = controller);
  }

  void _runJs(String js) {
    _windows?.executeScript(js);
    _view?.runJavaScript(js);
  }

  Future<void> _handleSession(String email, String token) async {
    if (_submitting || _success) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.service.addBrowserSession(email.isEmpty ? widget.email : email, token);
      if (!mounted) return;
      _success = true;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '$e';
      });
    }
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
        title: const Text('ورود Firefox'),
        actions: [
          IconButton(
            tooltip: 'بارگذاری دوباره',
            onPressed: _submitting ? null : () {
              if (_windows != null) _windows!.loadUrl(_mozillaLoginUrl(widget.email));
              if (_view != null) _view!.reload();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading || _submitting) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          if (_submitting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('در حال تأیید نشست با سرویس Mozilla؛ در صورت درخواست کد امنیتی، آن را در همین صفحه وارد کن.'),
            ),
          Expanded(
            child: web ?? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : const Text('صفحه ورود بارگذاری نشد. اتصال اینترنت را بررسی و دوباره تلاش کن.'),
            ),
          ),
        ],
      ),
    );
  }
}
