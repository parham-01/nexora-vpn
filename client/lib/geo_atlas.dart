import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'iso_numeric.dart';
import 'store.dart';

// داده‌ی مرز کشورها (TopoJSON، world-atlas 110m). ترتیب بارگذاری:
// ۱) فایل داخل اپ (workflow موقع ساخت دانلود می‌کند)  ۲) کش ذخیره‌شده  ۳) دانلود یک‌باره و ذخیره
const String kAtlasAsset = 'assets/geo/countries-110m.json';
const String kAtlasUrl = 'https://cdn.jsdelivr.net/npm/world-atlas@2.0.2/countries-110m.json';

class GeoRing {
  final Float32List ll; // lon,lat (درجه) پشت سر هم
  final Float32List a, b, s; // cosφ·sinλ ، cosφ·cosλ ، sinφ برای هر رأس
  final double minLon, maxLon, minLat, maxLat, area;
  GeoRing._(this.ll, this.a, this.b, this.s, this.minLon, this.maxLon, this.minLat, this.maxLat, this.area);

  int get n => a.length;

  factory GeoRing(List<double> flat) {
    final n = flat.length ~/ 2;
    final ll = Float32List(n * 2);
    final a = Float32List(n);
    final b = Float32List(n);
    final s = Float32List(n);
    var minLon = 1e9, maxLon = -1e9, minLat = 1e9, maxLat = -1e9;
    for (var i = 0; i < n; i++) {
      final lon = flat[2 * i];
      final lat = flat[2 * i + 1];
      ll[2 * i] = lon;
      ll[2 * i + 1] = lat;
      final la = lon * pi / 180;
      final fa = lat * pi / 180;
      final cf = cos(fa);
      a[i] = cf * sin(la);
      b[i] = cf * cos(la);
      s[i] = sin(fa);
      if (lon < minLon) minLon = lon;
      if (lon > maxLon) maxLon = lon;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
    }
    var ar = 0.0;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      ar += flat[2 * i] * flat[2 * j + 1] - flat[2 * j] * flat[2 * i + 1];
    }
    return GeoRing._(ll, a, b, s, minLon, maxLon, minLat, maxLat, ar.abs() / 2);
  }
}

class GeoCountry {
  final String id, name;
  final List<GeoRing> rings;
  final GeoRing main;
  GeoCountry(this.id, this.name, this.rings, this.main);

  double get cLon => (main.minLon + main.maxLon) / 2;
  double get cLat => (main.minLat + main.maxLat) / 2;
}

class GeoAtlas {
  final List<GeoCountry> countries;
  final Float32List dotA, dotB, dotS; // نقطه‌های خشکی برای کره‌ی دیجیتال
  GeoAtlas._(this.countries, this.dotA, this.dotB, this.dotS);

  static final ValueNotifier<GeoAtlas?> ready = ValueNotifier<GeoAtlas?>(null);
  static Future<void>? _job;

  static Future<void> preload() => _job ??= _load();

  static Future<void> _load() async {
    String? text;
    var fromNet = false;
    try {
      text = await rootBundle.loadString(kAtlasAsset);
    } catch (_) {}
    if (text == null || !text.trimLeft().startsWith('{')) {
      final cached = Store.getStr('geoAtlas');
      text = cached.trimLeft().startsWith('{') ? cached : null;
    }
    text ??= await _download().then((v) {
      fromNet = v != null;
      return v;
    });
    if (text == null) {
      _job = null; // دفعه‌ی بعد دوباره تلاش شود
      return;
    }
    try {
      final r = await compute(_parseAtlas, text);
      ready.value = GeoAtlas._build(r);
      if (fromNet) await Store.setStr('geoAtlas', text);
    } catch (_) {
      _job = null;
    }
  }

  static Future<String?> _download() async {
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 8);
    try {
      final r = await c.getUrl(Uri.parse(kAtlasUrl));
      final res = await r.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final t = await res.transform(utf8.decoder).join();
      return t.trimLeft().startsWith('{') ? t : null;
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  static GeoAtlas _build(List<dynamic> r) {
    final out = <GeoCountry>[];
    for (final e in r[0] as List) {
      final row = e as List;
      final rings = <GeoRing>[];
      for (final f in row[2] as List) {
        final ring = GeoRing((f as List).map((v) => (v as num).toDouble()).toList());
        if (ring.n >= 3) rings.add(ring);
      }
      if (rings.isEmpty) continue;
      var main = rings.first;
      for (final g in rings) {
        if (g.area > main.area) main = g;
      }
      out.add(GeoCountry('${row[0]}', '${row[1]}', rings, main));
    }
    final dots = (r[1] as List).map((v) => (v as num).toDouble()).toList();
    final n = dots.length ~/ 2;
    final a = Float32List(n);
    final b = Float32List(n);
    final s = Float32List(n);
    for (var i = 0; i < n; i++) {
      final la = dots[2 * i] * pi / 180;
      final fa = dots[2 * i + 1] * pi / 180;
      final cf = cos(fa);
      a[i] = cf * sin(la);
      b[i] = cf * cos(la);
      s[i] = sin(fa);
    }
    return GeoAtlas._(out, a, b, s);
  }

  GeoCountry? byCode(String code) {
    final id = kIsoNumeric[code.trim().toUpperCase()];
    if (id == null) return null;
    final want = int.tryParse(id);
    for (final c in countries) {
      if (int.tryParse(c.id) == want) return c;
    }
    return null;
  }

  GeoCountry? byName(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return null;
    for (final c in countries) {
      if (c.name.toLowerCase() == n) return c;
    }
    // تطبیق نیمه‌دقیق فقط روی مرز کلمه («United States of America» ← «United States»)؛
    // پیشوند خام باعث اشتباه‌هایی مثل Niger/Nigeria می‌شد.
    bool wordPrefix(String longer, String shorter) =>
        longer.startsWith(shorter) && (longer.length == shorter.length || RegExp(r'[\s,(]').hasMatch(longer[shorter.length]));
    for (final c in countries) {
      final m = c.name.toLowerCase();
      if (m.length > 3 && (wordPrefix(n, m) || wordPrefix(m, n))) return c;
    }
    return null;
  }
}

// ---------- پارس TopoJSON داخل isolate جدا (UI قفل نمی‌شود) ----------
// خروجی: [ [ [id, name, [ring(lon,lat,...), ...]], ... ], dots(lon,lat,...) ]
List<dynamic> _parseAtlas(String text) {
  final j = jsonDecode(text) as Map<String, dynamic>;
  final tr = j['transform'] as Map<String, dynamic>;
  final sc = (tr['scale'] as List).map((e) => (e as num).toDouble()).toList();
  final tl = (tr['translate'] as List).map((e) => (e as num).toDouble()).toList();

  final arcs = <List<double>>[];
  for (final arc in j['arcs'] as List) {
    var x = 0.0, y = 0.0;
    final pts = <double>[];
    for (final p in arc as List) {
      x += (p[0] as num).toDouble();
      y += (p[1] as num).toDouble();
      pts.add(x * sc[0] + tl[0]);
      pts.add(y * sc[1] + tl[1]);
    }
    arcs.add(pts);
  }

  List<double> arcPts(int i) {
    if (i >= 0) return arcs[i];
    final src = arcs[~i];
    final out = <double>[];
    for (var k = src.length - 2; k >= 0; k -= 2) {
      out.add(src[k]);
      out.add(src[k + 1]);
    }
    return out;
  }

  List<double> ringOf(List idxs) {
    final out = <double>[];
    for (final raw in idxs) {
      final pts = arcPts(raw as int);
      for (var k = out.isEmpty ? 0 : 2; k < pts.length; k++) {
        out.add(pts[k]);
      }
    }
    return out;
  }

  final geoms = ((j['objects'] as Map<String, dynamic>)['countries'] as Map<String, dynamic>)['geometries'] as List;
  final countries = <List<dynamic>>[];
  for (final g in geoms) {
    final m = g as Map<String, dynamic>;
    final rings = <List<double>>[];
    final type = m['type'];
    final a = m['arcs'];
    if (a is! List) continue;
    if (type == 'Polygon') {
      if (a.isNotEmpty) rings.add(ringOf(a[0] as List));
    } else if (type == 'MultiPolygon') {
      for (final poly in a) {
        if ((poly as List).isNotEmpty) rings.add(ringOf(poly[0] as List));
      }
    }
    final props = m['properties'];
    countries.add([
      '${m['id'] ?? ''}',
      props is Map ? '${props['name'] ?? ''}' : '',
      rings,
    ]);
  }

  // نقطه‌چین خشکی: شبکه‌ی lat/lon و تست point-in-polygon
  final all = <List<double>>[];
  final boxes = <List<double>>[];
  for (final c in countries) {
    for (final r in c[2] as List<List<double>>) {
      if (r.length < 6) continue;
      var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
      for (var k = 0; k < r.length; k += 2) {
        if (r[k] < x0) x0 = r[k];
        if (r[k] > x1) x1 = r[k];
        if (r[k + 1] < y0) y0 = r[k + 1];
        if (r[k + 1] > y1) y1 = r[k + 1];
      }
      all.add(r);
      boxes.add([x0, x1, y0, y1]);
    }
  }
  bool inside(double lon, double lat) {
    for (var i = 0; i < all.length; i++) {
      final bx = boxes[i];
      if (lon < bx[0] || lon > bx[1] || lat < bx[2] || lat > bx[3]) continue;
      final r = all[i];
      var c = false;
      final n = r.length ~/ 2;
      for (var p = 0, q = n - 1; p < n; q = p++) {
        final xi = r[2 * p], yi = r[2 * p + 1], xj = r[2 * q], yj = r[2 * q + 1];
        if (((yi > lat) != (yj > lat)) && (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi)) c = !c;
      }
      if (c) return true;
    }
    return false;
  }

  const step = 2.4;
  final dots = <double>[];
  for (var lat = -58.0; lat <= 84.0; lat += step) {
    final cf = max(0.2, cos(lat * pi / 180));
    final dl = step / cf;
    for (var lon = -180.0; lon < 180.0; lon += dl) {
      if (inside(lon, lat)) {
        dots.add(lon);
        dots.add(lat);
      }
    }
  }
  return [countries, dots];
}
