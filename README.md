# Nexora VPN

Open-source VPN client (Flutter) with an admin app and a Supabase backend. Android, Windows, Linux and macOS.

> Not affiliated with Mozilla. "Firefox" and "Mozilla" are trademarks of the Mozilla Foundation and are used only to describe compatibility.

## Features
- Connect with V2Ray/Xray configs (VLESS, VMess, Trojan, Shadowsocks) with fast concurrent ping tests and a cache
- Firefox VPN page: multiple accounts, auto-switch when data runs out, per-country locations, live usage
- Encrypted cloud backup of accounts and settings, restored after reinstall with a recovery code
- Animated home background, glass-style traffic stats, live upload/download chart
- In-app updater using GitHub Releases
- Admin app: users, configs, today's stats and charts, Firefox account stats
- Cloudflare Worker relay option

## Structure
| Folder | Purpose |
|---|---|
| `client/` | User app |
| `admin/` | Admin app |
| `supabase.sql` | Database schema (also in `tools/` and inside the admin app) |
| `tools/` | Build helpers |
| `.github/workflows/build.yml` | Build for all platforms and publish a Release |

## Setup
1. Create a free [Supabase](https://supabase.com) project. Open SQL Editor, paste `supabase.sql`, Run. Safe to run again.
2. Fork this repo. Go to Actions, run **build** and enter your Supabase URL and the **anon/publishable** key.
3. Open the admin app, Database tab, enter the **service_role** key, Save. Never put this key in the user app or in the repository.
4. Add configs from the admin app. The user app ships with none.

## Signing (Android)
Add repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`.
Without them a temporary key is used and users cannot update over an older install.
Never commit a keystore.

## Updater
Set the repository in `client/lib/updater.dart` (default `parham-01/nexora-vpn`) or pass `--dart-define=UPDATE_REPO=owner/repo`.

## Security
See [SECURITY.md](SECURITY.md).

## License
GPL-3.0, see [LICENSE](LICENSE). The core in `client/third_party/nexora-core` and part of `client/lib/firefox` are GPL-3.0, so the whole app is distributed under GPL-3.0. Source must stay available when you distribute builds.

---

## فارسی
کلاینت VPN متن‌باز با اپ ادمین و دیتابیس Supabase.
1. در Supabase فایل `supabase.sql` را در SQL Editor اجرا کن.
2. ریپو را Fork کن، در Actions ورک‌فلو **build** را با آدرس پروژه و کلید anon اجرا کن.
3. در اپ ادمین کلید service_role را وارد کن (هرگز داخل اپ کاربر یا ریپو نگذار).
4. کانفیگ‌ها را از اپ ادمین اضافه کن؛ اپ کاربر کانفیگ پیش‌فرض ندارد.
5. برای آپدیت روی نسخه‌ی قبلی، سه secret امضای اندروید را تنظیم کن و keystore را هرگز commit نکن.
