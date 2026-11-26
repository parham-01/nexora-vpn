import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

// ---------------------------------------------------------------------------
// تنظیمات تونل DNS (اختیاری؛ از طریق --dart-define هنگام ساخت):
//   TUNNEL_DOMAIN : دامنه‌ای که NS آن به سرور تونل شما اشاره می‌کند (مثلا t.example.com)
//   TUNNEL_PUBKEY : کلید عمومی X25519 سرور (۶۴ کاراکتر hex)
// بدون این دو، مرحله‌ی دست‌دهی راه دور رد می‌شود و فقط تست DNS و DoH اجرا می‌شود.
// ---------------------------------------------------------------------------
const String kTunnelDomain = String.fromEnvironment('TUNNEL_DOMAIN');
const String kTunnelPub = String.fromEnvironment('TUNNEL_PUBKEY');

class DnsResolver {
  final String name;
  final List<String> urls; // آدرس‌های DoH (اول با آیپی تا به DNS سیستم نیازی نباشد)
  const DnsResolver(this.name, this.urls);
}

const List<DnsResolver> kResolvers = [
  DnsResolver('Cloudflare', ['https://1.1.1.1/dns-query', 'https://1.0.0.1/dns-query', 'https://cloudflare-dns.com/dns-query']),
  DnsResolver('Google', ['https://8.8.8.8/dns-query', 'https://8.8.4.4/dns-query', 'https://dns.google/dns-query']),
  DnsResolver('Quad9', ['https://9.9.9.9/dns-query', 'https://149.112.112.112/dns-query', 'https://dns.quad9.net/dns-query']),
  DnsResolver('AdGuard', ['https://94.140.14.14/dns-query', 'https://94.140.15.15/dns-query', 'https://dns.adguard-dns.com/dns-query']),
];

class DnsResult {
  final String name;
  final int ms; // -1 یعنی پاسخ نداد
  final String url; // آدرسی که جواب داد
  const DnsResult(this.name, this.ms, this.url);
  bool get ok => ms >= 1 && url.isNotEmpty;

  // فرمت DoH مخصوص Xray: بدون عبور از routing، مستقیم و رمزنگاری‌شده
  String get xray => url.replaceFirst('https://', 'https+local://');
}

// ---------------------------------------------------------------------------
// بسته‌ی DNS (wire format) و ارسال با DoH
// ---------------------------------------------------------------------------
Uint8List dnsQuery(String name, int type, int id) {
  final b = BytesBuilder();
  b.add([id >> 8, id & 255, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]);
  for (final l in name.split('.')) {
    if (l.isEmpty) continue;
    final u = ascii.encode(l);
    b.addByte(u.length);
    b.add(u);
  }
  b.addByte(0);
  b.add([type >> 8, type & 255, 0, 1]);
  return b.toBytes();
}

Future<Uint8List?> dohPost(String url, Uint8List q, {int timeoutMs = 3500}) async {
  final c = HttpClient()..connectionTimeout = Duration(milliseconds: timeoutMs);
  try {
    final r = await c.postUrl(Uri.parse(url)).timeout(Duration(milliseconds: timeoutMs));
    r.headers.set('content-type', 'application/dns-message');
    r.headers.set('accept', 'application/dns-message');
    r.add(q);
    final res = await r.close().timeout(Duration(milliseconds: timeoutMs));
    if (res.statusCode != 200) return null;
    final bb = BytesBuilder();
    await for (final d in res.timeout(Duration(milliseconds: timeoutMs))) {
      bb.add(d);
      if (bb.length > 8192) break;
    }
    return bb.takeBytes();
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}

class DnsProbe {
  static final Random _r = Random.secure();

  // پاسخ معتبر: همان id، بیت QR روشن، RCODE=0 و حداقل یک جواب
  static bool _valid(Uint8List? a, int id) {
    if (a == null || a.length < 12) return false;
    if (((a[0] << 8) | a[1]) != id) return false;
    if ((a[2] & 0x80) == 0) return false;
    if ((a[3] & 0x0f) != 0) return false;
    return ((a[6] << 8) | a[7]) > 0;
  }

  static Future<DnsResult> probe(DnsResolver r) async {
    for (final u in r.urls) {
      final id = _r.nextInt(65535) + 1;
      final q = dnsQuery('www.cloudflare.com', 1, id);
      final sw = Stopwatch()..start();
      final a = await dohPost(u, q);
      sw.stop();
      if (_valid(a, id)) return DnsResult(r.name, max(1, sw.elapsedMilliseconds), u);
    }
    return DnsResult(r.name, -1, '');
  }

  // همه‌ی DNSها هم‌زمان تست می‌شوند؛ هر نتیجه همان لحظه به onResult می‌رسد
  static Future<List<DnsResult>> probeAll({void Function(DnsResult)? onResult}) async {
    final out = await Future.wait(kResolvers.map((r) async {
      final x = await probe(r);
      onResult?.call(x);
      return x;
    }));
    return out;
  }
}

// ---------------------------------------------------------------------------
// Noise_NK_25519_ChaChaPoly_SHA256  (مشابه الگوی dnstt؛ کلید سرور از قبل مشخص است)
// ---------------------------------------------------------------------------
final _sha = Sha256();
final _hmac = Hmac.sha256();
final _aead = Chacha20.poly1305Aead();
final _x25519 = X25519();

Future<Uint8List> _hash(List<int> d) async => Uint8List.fromList((await _sha.hash(d)).bytes);

Future<Uint8List> _mac(List<int> key, List<int> data) async =>
    Uint8List.fromList((await _hmac.calculateMac(data, secretKey: SecretKey(key))).bytes);

Uint8List _nonce(int n) {
  final b = Uint8List(12);
  var v = n;
  for (var i = 0; i < 8; i++) {
    b[4 + i] = v & 0xff;
    v >>= 8;
  }
  return b;
}

Future<Uint8List> _seal(List<int> key, int n, List<int> aad, List<int> plain) async {
  final box = await _aead.encrypt(plain, secretKey: SecretKey(key), nonce: _nonce(n), aad: aad);
  return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
}

Future<Uint8List?> _open(List<int> key, int n, List<int> aad, List<int> data) async {
  if (data.length < 16) return null;
  try {
    final box = SecretBox(data.sublist(0, data.length - 16), nonce: _nonce(n), mac: Mac(data.sublist(data.length - 16)));
    return Uint8List.fromList(await _aead.decrypt(box, secretKey: SecretKey(key), aad: aad));
  } catch (_) {
    return null;
  }
}

class _Sym {
  Uint8List ck;
  Uint8List h;
  Uint8List? k;
  int n = 0;
  _Sym(this.ck, this.h);

  static Future<_Sym> init(String protocol) async {
    final p = ascii.encode(protocol);
    final h = p.length <= 32 ? (Uint8List(32)..setRange(0, p.length, p)) : await _hash(p);
    return _Sym(Uint8List.fromList(h), Uint8List.fromList(h));
  }

  Future<void> mixHash(List<int> d) async => h = await _hash([...h, ...d]);

  Future<void> mixKey(List<int> ikm) async {
    final tk = await _mac(ck, ikm);
    final o1 = await _mac(tk, [1]);
    final o2 = await _mac(tk, [...o1, 2]);
    ck = o1;
    k = o2;
    n = 0;
  }

  Future<Uint8List> encryptAndHash(List<int> plain) async {
    if (k == null) {
      await mixHash(plain);
      return Uint8List.fromList(plain);
    }
    final ct = await _seal(k!, n++, h, plain);
    await mixHash(ct);
    return ct;
  }

  Future<Uint8List?> decryptAndHash(List<int> ct) async {
    if (k == null) {
      await mixHash(ct);
      return Uint8List.fromList(ct);
    }
    final pt = await _open(k!, n, h, ct);
    if (pt == null) return null;
    n++;
    await mixHash(ct);
    return pt;
  }
}

/// کانال رمزنگاری‌شده‌ی بعد از دست‌دهی (ChaCha20-Poly1305، شمارنده‌ی جدا برای هر جهت)
class NoiseChannel {
  final Uint8List _send, _recv;
  int _ns = 0, _nr = 0;
  NoiseChannel(this._send, this._recv);

  Future<Uint8List> encrypt(List<int> plain) => _seal(_send, _ns++, const [], plain);

  Future<Uint8List?> decrypt(List<int> data) async {
    final r = await _open(_recv, _nr, const [], data);
    if (r != null) _nr++;
    return r;
  }
}

// ---------------------------------------------------------------------------
// کدگذاری داده داخل نام DNS (base32) و خواندن پاسخ TXT
// ---------------------------------------------------------------------------
const String _b32 = 'abcdefghijklmnopqrstuvwxyz234567';

String b32encode(List<int> data) {
  final sb = StringBuffer();
  var buf = 0, bits = 0;
  for (final b in data) {
    buf = (buf << 8) | b;
    bits += 8;
    while (bits >= 5) {
      sb.write(_b32[(buf >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buf &= (1 << bits) - 1;
  }
  if (bits > 0) sb.write(_b32[(buf << (5 - bits)) & 31]);
  return sb.toString();
}

Uint8List? b32decode(String s) {
  final out = <int>[];
  var buf = 0, bits = 0;
  for (final ch in s.toLowerCase().codeUnits) {
    final v = _b32.indexOf(String.fromCharCode(ch));
    if (v < 0) return null;
    buf = (buf << 5) | v;
    bits += 5;
    if (bits >= 8) {
      out.add((buf >> (bits - 8)) & 0xff);
      bits -= 8;
    }
    buf &= (1 << bits) - 1;
  }
  return Uint8List.fromList(out);
}

int _skipName(Uint8List a, int p) {
  while (p < a.length) {
    final l = a[p];
    if (l == 0) return p + 1;
    if ((l & 0xC0) == 0xC0) return p + 2;
    p += l + 1;
  }
  return a.length;
}

/// متن اولین رکورد TXT پاسخ (رشته‌های داخلش به هم چسبانده می‌شوند)
String? txtOf(Uint8List a) {
  if (a.length < 12) return null;
  final qd = (a[4] << 8) | a[5];
  final an = (a[6] << 8) | a[7];
  var p = 12;
  for (var i = 0; i < qd; i++) {
    p = _skipName(a, p) + 4;
  }
  for (var i = 0; i < an; i++) {
    p = _skipName(a, p);
    if (p + 10 > a.length) return null;
    final type = (a[p] << 8) | a[p + 1];
    final rd = (a[p + 8] << 8) | a[p + 9];
    p += 10;
    if (type == 16 && p + rd <= a.length) {
      final sb = StringBuffer();
      var q = p;
      while (q < p + rd) {
        final l = a[q++];
        if (q + l > p + rd) break;
        sb.write(ascii.decode(a.sublist(q, q + l), allowInvalid: true));
        q += l;
      }
      return sb.toString();
    }
    p += rd;
  }
  return null;
}

// ---------------------------------------------------------------------------
// نشست تونل شخصی
// ---------------------------------------------------------------------------
class TunnelHandshake {
  final bool ok;
  final String info;
  final NoiseChannel? channel;
  const TunnelHandshake(this.ok, this.info, [this.channel]);
}

class DnsTunnelSession {
  final SimpleKeyPair _eph;
  final String sid;
  NoiseChannel? channel;
  DnsTunnelSession._(this._eph, this.sid);

  static bool get configured => kTunnelDomain.isNotEmpty && kTunnelPub.length == 64;

  /// ساخت کلیدهای موقت نشست (X25519)
  static Future<DnsTunnelSession> create() async {
    final kp = await _x25519.newKeyPair();
    final r = Random.secure();
    final sid = List.generate(4, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return DnsTunnelSession._(kp, sid);
  }

  Uint8List _hex(String h) =>
      Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);

  Future<Uint8List> _dh(SimpleKeyPair kp, List<int> remote) async {
    final s = await _x25519.sharedSecretKey(keyPair: kp, remotePublicKey: SimplePublicKey(remote, type: KeyPairType.x25519));
    return Uint8List.fromList(await s.extractBytes());
  }

  /// دست‌دهی Noise_NK از راه DNS: پیام اول داخل نام کوئری (TXT)، پیام دوم داخل پاسخ.
  /// resolverها به ترتیب سرعت امتحان می‌شوند؛ resolver فقط بایت‌های رمزشده می‌بیند.
  Future<TunnelHandshake> handshake(List<DnsResult> resolvers) async {
    if (!configured) return const TunnelHandshake(false, 'تونل DNS تنظیم نشده');
    try {
      final rs = _hex(kTunnelPub);
      final s = await _Sym.init('Noise_NK_25519_ChaChaPoly_SHA256');
      await s.mixHash(const []); // prologue
      await s.mixHash(rs);
      final ePub = Uint8List.fromList((await _eph.extractPublicKey()).bytes);
      await s.mixHash(ePub);
      await s.mixKey(await _dh(_eph, rs));
      final tag = await s.encryptAndHash(const []);
      final msg1 = Uint8List.fromList([...ePub, ...tag]);

      final enc = b32encode(msg1);
      final labels = [for (var i = 0; i < enc.length; i += 60) enc.substring(i, min(i + 60, enc.length))];
      final qname = '${labels.join('.')}.$sid.$kTunnelDomain';
      if (qname.length > 250) return const TunnelHandshake(false, 'نام DNS خیلی بلند است');

      for (final r in resolvers.where((e) => e.ok)) {
        final id = Random.secure().nextInt(65535) + 1;
        final a = await dohPost(r.url, dnsQuery(qname, 16, id), timeoutMs: 5000);
        if (a == null) continue;
        final txt = txtOf(a);
        final msg2 = txt == null ? null : b32decode(txt.trim());
        if (msg2 == null || msg2.length < 48) continue;
        final re = msg2.sublist(0, 32);
        await s.mixHash(re);
        await s.mixKey(await _dh(_eph, re));
        final pt = await s.decryptAndHash(msg2.sublist(32));
        if (pt == null) continue;
        // Split: اولیه‌گر با k1 می‌فرستد و با k2 می‌خواند
        final tk = await _mac(s.ck, const []);
        final k1 = await _mac(tk, [1]);
        final k2 = await _mac(tk, [...k1, 2]);
        channel = NoiseChannel(k1, k2);
        return TunnelHandshake(true, 'دست‌دهی از طریق ${r.name} کامل شد', channel);
      }
      return const TunnelHandshake(false, 'سرور تونل از راه هیچ DNS جواب نداد');
    } catch (e) {
      return TunnelHandshake(false, 'خطای رمزنگاری: $e');
    }
  }
}
