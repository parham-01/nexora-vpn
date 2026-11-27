import 'package:flutter/foundation.dart';
import 'api.dart';

/// یک هسته‌ی اتصال (Xray، V2Ray، sing-box، WireGuard، AmneziaWG، Hysteria2، TUIC یا سفارشی).
/// هسته‌ها فقط توسط «ادمین» در جدول `cores` مدیریت می‌شوند؛ کاربر صفحه‌ی انتخاب یا افزودن هسته ندارد.
class CoreDef {
  final String id, name, kind, version, note, template;
  final List<String> schemes;
  final bool builtin; // پیش‌فرض داخل اپ (وقتی جدول سرور خالی/در دسترس نیست)
  final bool enabled;
  const CoreDef({
    required this.id,
    required this.name,
    required this.kind,
    required this.schemes,
    this.version = 'latest',
    this.note = '',
    this.template = '',
    this.builtin = false,
    this.enabled = true,
  });

  /// موتور اجرایی واقعی: xray | singbox | amneziawg
  String get engine {
    switch (kind) {
      case 'xray':
      case 'v2ray':
        return 'xray';
      case 'amneziawg':
        return 'amneziawg';
      default:
        return 'singbox';
    }
  }

  static CoreDef fromRow(Map e) => CoreDef(
        id: '${e['id']}',
        name: '${e['name'] ?? e['id']}',
        kind: '${e['kind'] ?? 'custom'}',
        schemes: '${e['schemes'] ?? ''}'.split(',').map((x) => x.trim().toLowerCase()).where((x) => x.isNotEmpty).toList(),
        version: '${e['version'] ?? ''}',
        note: '${e['note'] ?? ''}',
        template: '${e['template'] ?? ''}',
        // سرورهای قدیمی ستون enabled را برنمی‌گردانند (فقط ردیف‌های فعال) → فعال
        enabled: e['enabled'] != false,
      );
}

class Cores {
  static const List<CoreDef> builtin = [
    CoreDef(id: 'xray', name: 'Xray', kind: 'xray', schemes: ['vless', 'vmess', 'trojan', 'ss'], note: 'VLESS / VMess / Trojan / Shadowsocks (Reality، xhttp، gRPC، WS ...)', builtin: true),
    CoreDef(id: 'v2ray', name: 'V2Ray', kind: 'v2ray', schemes: ['vmess', 'vless', 'trojan', 'ss'], note: 'سازگار با کانفیگ‌های قدیمی', builtin: true),
    CoreDef(id: 'singbox', name: 'sing-box', kind: 'singbox', schemes: ['hysteria2', 'hy2', 'tuic', 'wireguard', 'wg'], note: 'Hysteria2 / TUIC / WireGuard', builtin: true),
    CoreDef(id: 'wireguard', name: 'WireGuard', kind: 'wireguard', schemes: ['wireguard', 'wg'], note: 'WireGuard', builtin: true),
    CoreDef(id: 'amneziawg', name: 'AmneziaWG', kind: 'amneziawg', schemes: ['awg', 'amneziawg'], note: 'WireGuard مقاوم در برابر فیلترینگ', builtin: true),
    CoreDef(id: 'hysteria2', name: 'Hysteria2', kind: 'hysteria', schemes: ['hysteria2', 'hy2'], note: 'Hysteria2 روی QUIC', builtin: true),
    CoreDef(id: 'tuic', name: 'TUIC', kind: 'tuic', schemes: ['tuic'], note: 'TUIC v5 روی QUIC', builtin: true),
  ];

  // وضعیت هسته‌ها از دیتابیس ادمین (null = هنوز خوانده نشده/جدول خالی → همه‌ی پیش‌فرض‌ها فعال)
  static final ValueNotifier<List<CoreDef>?> remote = ValueNotifier(null);
  static final ValueNotifier<int> rev = ValueNotifier(0);
  static bool _loaded = false;

  /// هسته‌های فعال (غیرفعال‌شده‌ها حذف می‌شوند)
  static List<CoreDef> get all => [for (final c in (remote.value ?? builtin)) if (c.enabled) c];

  static String schemeOf(String link) {
    final i = link.indexOf('://');
    return i < 0 ? '' : link.substring(0, i).trim().toLowerCase();
  }

  /// اولین هسته‌ی فعالی که پروتکل لینک را پشتیبانی می‌کند.
  /// null یعنی ادمین همه‌ی هسته‌های این پروتکل را غیرفعال کرده.
  static CoreDef? forLink(String link) {
    final sc = schemeOf(link);
    for (final c in all) {
      if (c.schemes.contains(sc)) return c;
    }
    return null;
  }

  static bool allows(String link) => forLink(link) != null;

  /// قالب JSON هسته‌ی سفارشی که لینک را اجرا می‌کند ('' = کانفیگ پیش‌فرض)
  static String templateFor(String link) => forLink(link)?.template ?? '';

  static Future<void> refresh() async {
    try {
      final rows = await Api.fetchCores();
      if (rows == null) return;
      // جدول خالی = ادمین هنوز هیچ هسته‌ای نساخته → پیش‌فرض‌ها (تا اشتباهاً همه‌ی پروتکل‌ها مسدود نشوند).
      // اگر ادمین همه را غیرفعال کند، ردیف‌ها (با enabled=false) برمی‌گردند و همان‌ها اعمال می‌شود.
      remote.value = rows.isEmpty ? null : [for (final r in rows) CoreDef.fromRow(r)];
      _loaded = true;
      rev.value++;
    } catch (_) {}
  }

  static bool get loaded => _loaded;
}
