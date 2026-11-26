import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'firefox/firefox_service.dart';
import 'store.dart';

class CloudBackup {
  static const _kCode = 'cb_code';
  static const _kSig = 'cb_sig';
  static const _kAt = 'cb_at';
  static const _kHad = 'cb_had';
  static const _prefKeys = [
    'theme', 'lite3', 'serverId', 'auto_timezone_sync', 'stealth_fragment',
    'upstream_proxy', 'upstream_proxy_on', 'ff_selected_account', 'ff_auto_switch', 'ff_desktop_mode',
  ];
  static const _maxBytes = 1500000;

  static Timer? _timer;
  static bool _busy = false;
  static bool _autoTried = false;
  static SecretKey? _key;
  static String _keyFor = '';

  static String _norm(String s) {
    var t = s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (t.startsWith('NX')) t = t.substring(2);
    return t;
  }

  static String _pretty(String raw) {
    final parts = <String>[];
    for (var i = 0; i < raw.length; i += 5) {
      parts.add(raw.substring(i, min(i + 5, raw.length)));
    }
    return 'NX-${parts.join('-')}';
  }

  static Future<String> code() async {
    final p = await SharedPreferences.getInstance();
    var c = p.getString(_kCode);
    if (c == null || c.isEmpty) {
      final r = Random.secure();
      const a = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
      c = _pretty(List.generate(20, (_) => a[r.nextInt(a.length)]).join());
      await p.setString(_kCode, c);
    }
    return c;
  }

  static Future<String> _id(String c) async {
    final h = await Sha256().hash(utf8.encode('nx-id:${_norm(c)}'));
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<SecretKey> _deriveKey(String c) async {
    final n = _norm(c);
    if (_key != null && _keyFor == n) return _key!;
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 20000, bits: 256);
    _key = await kdf.deriveKeyFromPassword(password: n, nonce: utf8.encode('nexora-backup-v1'));
    _keyFor = n;
    return _key!;
  }

  static Future<String> _seal(String c, List<int> plain) async {
    final box = await AesGcm.with256bits().encrypt(plain, secretKey: await _deriveKey(c));
    return base64Encode(box.concatenation());
  }

  static Future<List<int>> _open(String c, String b64) async {
    final box = SecretBox.fromConcatenation(base64Decode(b64), nonceLength: 12, macLength: 16);
    return AesGcm.with256bits().decrypt(box, secretKey: await _deriveKey(c));
  }

  static Future<Map<String, dynamic>> _prefs() async {
    final p = await SharedPreferences.getInstance();
    final m = <String, dynamic>{};
    for (final k in _prefKeys) {
      final v = p.get(k);
      if (v is String) m[k] = {'t': 's', 'v': v};
      if (v is bool) m[k] = {'t': 'b', 'v': v};
      if (v is int) m[k] = {'t': 'i', 'v': v};
    }
    return m;
  }

  static void schedule({bool force = false}) {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: force ? 2 : 25), () => push(force: force));
  }

  static Future<bool> push({bool force = false}) async {
    if (_busy) return false;
    final f = FirefoxService.I;
    if (!f.supported || !f.isReady) return false;
    _busy = true;
    try {
      final p = await SharedPreferences.getInstance();
      final pr = await _prefs();
      final sig = '${f.accounts.map((a) => '${a.id}:${a.enabled}').join(',')}|${jsonEncode(pr)}';
      final last = DateTime.fromMillisecondsSinceEpoch(p.getInt(_kAt) ?? 0);
      final fresh = DateTime.now().difference(last).inHours < 12;
      if (!force && sig == p.getString(_kSig) && fresh) return false;
      if (f.accounts.isEmpty && !force) return false;
      final c = await code();
      Uint8List? zip;
      if (f.accounts.isNotEmpty) {
        zip = (await (await f.ensureApi()).exportBackup()).bytes;
      }
      final payload = utf8.encode(jsonEncode({'v': 1, 'prefs': pr, 'core': zip == null ? '' : base64Encode(zip)}));
      final blob = await _seal(c, payload);
      if (blob.length > _maxBytes) return false;
      final ok = await Api.saveBackup(await _id(c), blob);
      if (ok) {
        await p.setString(_kSig, sig);
        await p.setInt(_kAt, DateTime.now().millisecondsSinceEpoch);
        await p.setBool(_kHad, f.accounts.isNotEmpty);
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
    }
  }

  static Future<void> markEmptied() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHad, false);
    schedule(force: true);
  }

  static Future<void> autoRestore() async {
    if (_autoTried) return;
    _autoTried = true;
    try {
      final p = await SharedPreferences.getInstance();
      final c = p.getString(_kCode);
      if (c == null || c.isEmpty) return;
      if (!(p.getBool(_kHad) ?? false)) return;
      final f = FirefoxService.I;
      if (!f.isReady || f.accounts.isNotEmpty) return;
      await restore(c);
    } catch (_) {}
  }

  static Future<int> restore(String input) async {
    final c = _pretty(_norm(input));
    if (_norm(c).length < 16) throw StateError('کد بازیابی کامل نیست');
    final blob = await Api.loadBackup(await _id(c));
    if (blob == null || blob.isEmpty) throw StateError('برای این کد بکاپی پیدا نشد');
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(await _open(c, blob))) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('کد اشتباه است یا بکاپ خراب است');
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCode, c);
    final pr = (data['prefs'] as Map?) ?? {};
    for (final e in pr.entries) {
      final k = '${e.key}';
      if (!_prefKeys.contains(k) || e.value is! Map) continue;
      final t = e.value['t'];
      final v = e.value['v'];
      if (t == 's' && v is String) await p.setString(k, v);
      if (t == 'b' && v is bool) await p.setBool(k, v);
      if (t == 'i' && v is int) await p.setInt(k, v);
    }
    await Store.init();
    var added = 0;
    final core = '${data['core'] ?? ''}';
    final f = FirefoxService.I;
    if (core.isNotEmpty) {
      if (!f.isReady) await f.initialize();
      final r = await (await f.ensureApi()).importBackup(base64Decode(core));
      added = r.added + r.updated;
      await p.setBool(_kHad, true);
    }
    await f.initialize();
    return added;
  }

  static Future<void> showSheet(BuildContext context) async {
    final mine = await code();
    if (!context.mounted) return;
    final ctl = TextEditingController();
    var busy = false;
    String msg = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('بکاپ ابری و بازیابی', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('اکانت‌ها و تنظیمات به‌صورت رمزنگاری‌شده روی سرور ذخیره می‌شوند. با کد زیر بعد از نصب دوباره همه‌چیز برمی‌گردد.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.7, color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: mine));
                    set(() => msg = 'کپی شد');
                  },
                ),
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(mine, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Text('این کد را جای امن نگه دار؛ هر کسی آن را داشته باشد به اکانت‌ها دسترسی دارد.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: cs.error)),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: busy
                  ? null
                  : () async {
                      set(() { busy = true; msg = 'در حال ذخیره...'; });
                      final ok = await push(force: true);
                      set(() { busy = false; msg = ok ? 'بکاپ ذخیره شد' : 'ذخیره نشد؛ اینترنت را بررسی کن'; });
                    },
              icon: const Icon(Icons.cloud_upload_rounded),
              label: const Text('ذخیره‌ی بکاپ همین حالا'),
            ),
            const Divider(height: 28),
            TextField(
              controller: ctl,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'کد بازیابی', hintText: 'NX-XXXXX-XXXXX-XXXXX-XXXXX', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      set(() { busy = true; msg = 'در حال بازیابی...'; });
                      try {
                        final n = await restore(ctl.text);
                        set(() { busy = false; msg = n > 0 ? '$n اکانت بازیابی شد' : 'تنظیمات بازیابی شد'; });
                      } catch (e) {
                        set(() { busy = false; msg = '$e'.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', ''); });
                      }
                    },
              icon: const Icon(Icons.cloud_download_rounded),
              label: const Text('بازیابی با کد'),
            ),
            if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(msg, textAlign: TextAlign.center)),
          ]),
        );
      }),
    );
  }
}
