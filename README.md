# Nexora VPN

Open-source VPN client (Flutter) for Android, Windows, Linux and macOS. No backend, no database, no admin app: everything stays on your device.

> Not affiliated with Mozilla. "Firefox" and "Mozilla" are trademarks of the Mozilla Foundation and are used only to describe compatibility.

## Features
- Connect with V2Ray/Xray and sing-box configs (VLESS, VMess, Trojan, Shadowsocks, Hysteria2, TUIC, WireGuard)
- Add, edit and delete your own servers; sequential real ping test with live per-server spinner
- Animated connection globe and home screen, live traffic card
- Firefox VPN page with multiple accounts and per-country locations
- Advanced settings: DNS choice, QUIC/torrent/WebRTC blocking, Mux, auto-disconnect, usage alerts
- In-app updater using GitHub Releases (picks the right file for your CPU)
- Cloudflare Worker relay option

## Structure
| Folder | Purpose |
|---|---|
| `client/` | The app |
| `tools/` | Build helpers |
| `.github/workflows/build.yml` | Build all platforms and publish a Release |

## Build
1. Fork this repo. Go to Actions, run **build** and pick the platforms.
2. Install the result and add your own server links inside the app.

## Signing (Android)
Add repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`.
Without them a temporary key is used and users cannot update over an older install. Never commit a keystore.

## Updater
Set the repository in `client/lib/updater.dart` (`kUpdateRepo`). The app reads the latest Release, compares it with the installed version and downloads the file for the device architecture.

## Privacy
The app has no analytics and no server of its own. Besides your VPN traffic it only contacts GitHub (update check) and public IP lookup services.

## Security
See [SECURITY.md](SECURITY.md).

## License
GPL-3.0, see [LICENSE](LICENSE). The core in `client/third_party/nexora-core` and part of `client/lib/firefox` are GPL-3.0, so the whole app is distributed under GPL-3.0. Source must stay available when you distribute builds.

---

## فارسی
کلاینت VPN متن‌باز برای اندروید، ویندوز، لینوکس و مک. بدون سرور، بدون دیتابیس و بدون اپ ادمین؛ همه‌چیز فقط روی دستگاه خودت می‌ماند.
1. ریپو را Fork کن و در Actions ورک‌فلو **build** را اجرا کن.
2. برنامه را نصب کن و لینک سرورهای خودت را داخل برنامه اضافه کن.
3. برای آپدیت روی نسخه‌ی قبلی، سه secret امضای اندروید را تنظیم کن و keystore را هرگز commit نکن.
4. آدرس ریپوی آپدیت را در `client/lib/updater.dart` (`kUpdateRepo`) بگذار.
