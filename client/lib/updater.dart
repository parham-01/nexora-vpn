import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'api.dart';
import 'store.dart';

/// مخزن اصلی پروژه که ریلیزها در آن منتشر می‌شود: https://github.com/parham-01/nexora-vpn (بخش Releases)
/// آخرین نسخه از https://api.github.com/repos/parham-01/nexora-vpn/releases/latest خوانده می‌شود.
const String kUpdateRepo = String.fromEnvironment('UPDATE_REPO', defaultValue: 'parham-01/nexora-vpn');

/// نسخه‌ی برنامه که ورک‌فلو هنگام بیلد می‌گذارد (مثلاً 1.0.42). روی اندروید نسخه‌ی واقعی نصب‌شده خوانده می‌شود.
const String kAppVersion = String.fromEnvironment('APP_VERSION');

class AppInfo {
  AppInfo(this.versionName, this.versionCode, this.abi);
  final String versionName;
  final int versionCode;
  final String abi;
}

class ReleaseAsset {
  ReleaseAsset(this.name, this.url, this.size, [this.apiUrl = '']);
  final String name;
  final String url; // browser_download_url
  final int size;
  final String apiUrl; // برای ریپوی خصوصی (با توکن)

  /// ریپوی خصوصی با آدرس API دانلود می‌شود؛ عمومی با آدرس مرورگر.
  String get downloadUrl => Updater.token.isNotEmpty && apiUrl.isNotEmpty ? apiUrl : url;
}

class ReleaseInfo {
  ReleaseInfo(this.tag, this.name, this.notes, this.assets);
  final String tag;
  final String name;
  final String notes;
  final List<ReleaseAsset> assets;

  /// نسخه‌ی تمیز (بدون v)
  String get version => tag.replaceFirst(RegExp(r'^[vV]'), '');

  /// دارایی مناسب همین دستگاه (APK / نصب‌کننده‌ی ویندوز / dmg / tar.gz لینوکس)؛ نسخه‌ی ادمین هرگز انتخاب نمی‌شود.
  ReleaseAsset? assetFor(String abi) {
    final all = assets.where((a) => !a.name.toLowerCase().contains('admin')).toList();
    ReleaseAsset? first(bool Function(String n) test) {
      for (final a in all) {
        if (test(a.name.toLowerCase())) return a;
      }
      return null;
    }

    if (Platform.isAndroid) {
      final apks = all.where((a) => a.name.toLowerCase().endsWith('.apk')).toList();
      if (apks.isEmpty) return null;
      ReleaseAsset? byPart(String part) {
        for (final a in apks) {
          if (a.name.toLowerCase().contains(part)) return a;
        }
        return null;
      }

      if (abi.startsWith('arm64')) return byPart('arm64-v8a') ?? byPart('universal') ?? apks.first;
      if (abi.startsWith('armeabi') || abi.startsWith('arm')) return byPart('armeabi-v7a') ?? byPart('universal') ?? apks.first;
      return byPart('universal') ?? apks.first;
    }
    if (Platform.isWindows) {
      return first((n) => n.contains('windows') && n.contains('setup') && n.endsWith('.exe')) ??
          first((n) => n.contains('windows') && n.endsWith('.zip'));
    }
    if (Platform.isMacOS) {
      return first((n) => n.contains('macos') && n.endsWith('.dmg')) ?? first((n) => n.contains('macos') && n.endsWith('.tar.gz'));
    }
    if (Platform.isLinux) {
      final arm = abi.contains('aarch64') || abi.contains('arm64');
      return first((n) => n.contains('linux') && n.contains(arm ? 'arm64' : 'amd64') && n.endsWith('.tar.gz'));
    }
    return null;
  }
}

class UpdateStatus {
  UpdateStatus(this.state, this.received, this.total, this.version, this.error);
  final String state; // idle | downloading | done | error
  final int received;
  final int total;
  final String version;
  final String error;

  int get percent => total > 0 ? ((received * 100) ~/ total).clamp(0, 100) : 0;

  factory UpdateStatus.fromMap(Map<Object?, Object?> m) => UpdateStatus(
        '${m['state'] ?? 'idle'}',
        (m['received'] as num?)?.toInt() ?? 0,
        (m['total'] as num?)?.toInt() ?? 0,
        '${m['version'] ?? ''}',
        '${m['error'] ?? ''}',
      );
}

class Updater {
  static const MethodChannel _ch = MethodChannel('nexora/update');

  /// اندروید: دانلود پس‌زمینه و نصب درجا. ویندوز/مک/لینوکس: دانلود داخل برنامه و اجرای نصب‌کننده.
  static bool get supported => Platform.isAndroid || Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  // ------------------------------------------------------------ توکن GitHub
  static String get token => Store.getStr('gh_token').trim();

  /// توکنی که از اپ ادمین ذخیره شده را بی‌صدا می‌گیرد (برای ریپوی خصوصی و جلوگیری از Rate Limit).
  static Future<void> syncToken() async {
    final t = await Api.appSetting('github_token');
    if (t.isNotEmpty && t != token) await Store.setStr('gh_token', t);
  }

  // ------------------------------------------------------------ نسخه‌ی نصب‌شده
  static String _arch() {
    try {
      if (Platform.isWindows) return Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
      return (Process.runSync('uname', ['-m']).stdout as String).trim();
    } catch (_) {
      return '';
    }
  }

  static Future<AppInfo> appInfo() async {
    if (Platform.isAndroid) {
      try {
        final m = await _ch.invokeMapMethod<String, Object?>('appInfo') ?? const {};
        final v = '${m['versionName'] ?? ''}';
        return AppInfo(v.isEmpty ? (kAppVersion.isEmpty ? '0.0.0' : kAppVersion) : v, (m['versionCode'] as num?)?.toInt() ?? 0, '${m['abi'] ?? ''}');
      } catch (_) {
        return AppInfo(kAppVersion.isEmpty ? '0.0.0' : kAppVersion, 0, '');
      }
    }
    return AppInfo(kAppVersion.isEmpty ? '0.0.0' : kAppVersion, 0, _arch().toLowerCase());
  }

  // ------------------------------------------------------------ خواندن ریلیزها از GitHub
  static Future<dynamic> _getJson(String url, {bool withToken = true}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('X-GitHub-Api-Version', '2022-11-28');
      req.headers.set('User-Agent', 'NexoraVPN-Updater');
      final t = withToken ? token : '';
      if (t.isNotEmpty) req.headers.set('Authorization', 'Bearer $t');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) throw FormatException(t.isEmpty ? 'release_not_found' : 'release_not_found_token');
      if (res.statusCode == 401) throw const FormatException('bad_token');
      if (res.statusCode == 403 || res.statusCode == 429) {
        throw FormatException(body.toLowerCase().contains('rate limit') ? 'rate_limited' : 'forbidden');
      }
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  static ReleaseInfo _parse(Map<String, dynamic> j) => ReleaseInfo(
        '${j['tag_name'] ?? ''}',
        '${j['name'] ?? ''}',
        '${j['body'] ?? ''}',
        [
          for (final a in (j['assets'] as List? ?? const []))
            if (a is Map) ReleaseAsset('${a['name']}', '${a['browser_download_url']}', (a['size'] as num?)?.toInt() ?? 0, '${a['url'] ?? ''}'),
        ],
      );

  /// جدیدترین ریلیزی که برای همین سیستم‌عامل فایل نصب دارد (draft/pre-release نادیده گرفته می‌شود).
  /// اگر مثلاً فقط نسخه‌ی ویندوز منتشر شده باشد، کاربر اندروید پیام کاذب نمی‌گیرد.
  static Future<ReleaseInfo> latest({String abi = ''}) async {
    try {
      final one = await _getJson('https://api.github.com/repos/$kUpdateRepo/releases/latest', withToken: token.isNotEmpty);
      if (one is Map<String, dynamic> && one['draft'] != true && one['prerelease'] != true) {
        final r = _parse(one);
        if (r.assetFor(abi) != null) return r;
      }
    } catch (_) {}
    final url = 'https://api.github.com/repos/$kUpdateRepo/releases?per_page=20';
    dynamic list;
    try {
      list = await _getJson(url);
    } on FormatException catch (e) {
      final m = e.message;
      final retry = token.isNotEmpty && (m == 'release_not_found_token' || m == 'bad_token' || m == 'forbidden');
      if (!retry) rethrow;
      try {
        list = await _getJson(url, withToken: false);
      } on FormatException {
        throw FormatException(m);
      }
    }
    if (list is! List || list.isEmpty) {
      try {
        final one = await _getJson('https://api.github.com/repos/$kUpdateRepo/releases/latest', withToken: token.isNotEmpty);
        if (one is Map<String, dynamic>) list = [one];
      } catch (_) {}
    }
    if (list is! List || list.isEmpty) throw const FormatException('release_not_found');
    ReleaseInfo? newest;
    for (final e in list) {
      if (e is! Map<String, dynamic>) continue;
      if (e['draft'] == true || e['prerelease'] == true) continue;
      final r = _parse(e);
      newest ??= r;
      if (r.assetFor(abi) != null) {
        // بین ریلیزهای دارای فایل، بالاترین نسخه
        if (_best == null || isNewer(r.tag, _best!.tag)) _best = r;
      }
    }
    final pick = _best ?? newest;
    _best = null;
    if (pick == null) throw const FormatException('release_not_found');
    return pick;
  }

  static ReleaseInfo? _best;

  static List<int> _nums(String v) => RegExp(r'\d+').allMatches(v).map((m) => int.parse(m.group(0)!)).toList();

  /// آیا تگ ریلیز از نسخه‌ی نصب‌شده جدیدتر است؟ (مقایسه‌ی عددی x.y.z)
  static bool isNewer(String tag, String current) {
    final a = _nums(tag), b = _nums(current);
    if (a.isEmpty) return false;
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// بررسی بی‌صدا هنگام باز شدن برنامه: اگر نسخه‌ی جدیدتری برای همین سیستم هست، برگردانده می‌شود.
  static Future<ReleaseInfo?> checkQuiet() async {
    try {
      if (!supported) return null;
      await syncToken();
      final info = await appInfo();
      final r = await latest(abi: info.abi);
      if (r.assetFor(info.abi) == null) return null;
      return isNewer(r.tag, info.versionName) ? r : null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ دانلود / نصب
  static Future<void> start(ReleaseInfo release, ReleaseAsset asset) {
    if (Platform.isAndroid) {
      return _ch.invokeMethod<void>('start', {'url': asset.downloadUrl, 'version': release.version, 'token': token});
    }
    return _desktopStart(release, asset);
  }

  static Future<UpdateStatus> status() async {
    if (Platform.isAndroid) return UpdateStatus.fromMap(await _ch.invokeMapMethod<Object?, Object?>('status') ?? const {});
    return UpdateStatus(_dState, _dReceived, _dTotal, _dVersion, _dError);
  }

  static Future<void> cancel() async {
    if (Platform.isAndroid) return _ch.invokeMethod<void>('cancel');
    _dCancel = true;
  }

  static Future<void> clear() async {
    if (Platform.isAndroid) return _ch.invokeMethod<void>('clear');
    _dState = 'idle';
    _dReceived = 0;
    _dTotal = 0;
    _dError = '';
    _dCancel = false;
    final f = _dFile;
    _dFile = null;
    try {
      if (f != null && f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// 'ok' | 'need_permission' | 'no_file'
  static Future<String> install() async {
    if (Platform.isAndroid) return (await _ch.invokeMethod<String>('install')) ?? 'no_file';
    final f = _dFile;
    if (f == null || !f.existsSync()) return 'no_file';
    try {
      if (Platform.isWindows) {
        if (f.path.toLowerCase().endsWith('.exe')) {
          // نصب بی‌صدا روی نسخه‌ی قبلی؛ داده‌های کاربر در AppData می‌ماند و برنامه بعد از نصب دوباره باز می‌شود
          await Process.start(f.path, ['/SILENT', '/NORESTART', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'], mode: ProcessStartMode.detached);
          await Future<void>.delayed(const Duration(milliseconds: 600));
          exit(0);
        }
        await Process.start('explorer.exe', ['/select,', f.path], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [f.path], mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', [f.parent.path], mode: ProcessStartMode.detached);
      }
      return 'ok';
    } catch (_) {
      return 'no_file';
    }
  }

  // ---- دانلود دسکتاپ (داخل خود برنامه) ----
  static String _dState = 'idle';
  static int _dReceived = 0, _dTotal = 0;
  static String _dVersion = '', _dError = '';
  static bool _dCancel = false;
  static File? _dFile;

  static Future<void> _desktopStart(ReleaseInfo release, ReleaseAsset asset) async {
    if (_dState == 'downloading') return;
    _dState = 'downloading';
    _dReceived = 0;
    _dTotal = asset.size;
    _dVersion = release.version;
    _dError = '';
    _dCancel = false;
    unawaited(_desktopDownload(asset));
  }

  static Future<void> _desktopDownload(ReleaseAsset asset) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    File? part;
    try {
      final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}nexora-update')..createSync(recursive: true);
      for (final e in dir.listSync()) {
        try {
          e.deleteSync(recursive: true);
        } catch (_) {}
      }
      final target = File('${dir.path}${Platform.pathSeparator}${asset.name}');
      part = File('${target.path}.part');

      var url = asset.downloadUrl;
      final auth = token.isNotEmpty && url.startsWith('https://api.github.com/');
      HttpClientResponse? res;
      for (var hop = 0; hop < 6; hop++) {
        final req = await client.getUrl(Uri.parse(url));
        req.followRedirects = false;
        req.headers.set('User-Agent', 'NexoraVPN-Updater');
        if (auth && hop == 0) {
          req.headers.set('Authorization', 'Bearer $token');
          req.headers.set('Accept', 'application/octet-stream');
        }
        res = await req.close();
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.value('location') != null) {
          url = Uri.parse(url).resolve(res.headers.value('location')!).toString();
          await res.drain<void>();
          continue;
        }
        break;
      }
      if (res == null || res.statusCode != 200) throw HttpException('HTTP ${res?.statusCode}');
      if (res.contentLength > 0) _dTotal = res.contentLength;
      sink = part.openWrite();
      await for (final chunk in res) {
        if (_dCancel) throw const FormatException('cancelled');
        sink.add(chunk);
        _dReceived += chunk.length;
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (target.existsSync()) target.deleteSync();
      part.renameSync(target.path);
      _dFile = target;
      _dState = 'done';
    } catch (e) {
      try {
        await sink?.close();
        part?.deleteSync();
      } catch (_) {}
      if ('$e'.contains('cancelled')) {
        _dState = 'idle';
      } else {
        _dState = 'error';
        _dError = '$e'.replaceFirst('Exception: ', '');
      }
    } finally {
      client.close(force: true);
    }
  }
}
