#!/usr/bin/env python3
"""دانلود sing-box (SagerNet) برای همه‌ی پلتفرم‌ها؛ هسته‌ی Hysteria2 / TUIC / WireGuard.

استفاده:
  python3 tools/get_singbox.py <الگو> <پوشه‌ی مقصد>
      الگو: windows-amd64 | linux-amd64 | linux-arm64 | darwin-arm64 | darwin-amd64
  python3 tools/get_singbox.py android <پوشه‌ی jniLibs>
      سه معماری اندروید را می‌گیرد و هرکدام را به شکل  <jniLibs>/<abi>/libsingbox.so  می‌گذارد:
        arm64-v8a ← android-arm64 ، armeabi-v7a ← android-armv7 ، x86_64 ← android-amd64
      (نام lib*.so لازم است تا اندروید فایل را کنار کتابخانه‌های بومی استخراج کند و بشود اجرایش کرد.)

رفتار:
  • اگر دانلود ناموفق باشد بیلد «متوقف» می‌شود (exit 1) تا APK/برنامه‌ی بدون هسته منتشر نشود
    (قبلاً فقط هشدار می‌داد و اپ بعداً «هسته نصب نیست» می‌گفت).
  • SINGBOX_TAG (مثلاً v1.12.0) نسخه را ثابت می‌کند؛ پیش‌فرض آخرین نسخه‌ی پایدار است.
  • SINGBOX_OPTIONAL=1 → فقط هشدار بده و خطا نده (برای بیلد محلی).
"""
import io, json, os, shutil, sys, tarfile, time, urllib.request, zipfile

API = "https://api.github.com/repos/SagerNet/sing-box/releases"
UA = {"User-Agent": "nexora-build"}
ANDROID_ABIS = [("arm64-v8a", ["android-arm64"]), ("armeabi-v7a", ["android-armv7", "android-arm"]), ("x86_64", ["android-amd64"])]
BAD = ("legacy", "glibc", "musl")


def get(url, timeout=120, accept=None):
    last = None
    for i in range(4):
        try:
            h = dict(UA)
            tok = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
            if tok and "api.github.com" in url:
                h["Authorization"] = "Bearer " + tok
            if accept:
                h["Accept"] = accept
            return urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=timeout).read()
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(2 + i * 3)
    raise RuntimeError("download failed: %s (%s)" % (url, last))


def release():
    tag = os.environ.get("SINGBOX_TAG", "").strip()
    url = API + ("/tags/" + tag if tag else "/latest")
    return json.loads(get(url, timeout=60))


def pick(rel, pat):
    assets = [a for a in rel.get("assets", []) if pat in a["name"] and a["name"].endswith((".zip", ".tar.gz"))]
    # android-arm نباید android-arm64 را بگیرد (و برعکس)
    assets = [a for a in assets if (pat + ".") in a["name"] or (pat + "-") in a["name"]]
    good = [a for a in assets if not any(x in a["name"] for x in BAD)] or assets
    if not good:
        raise RuntimeError("asset not found for " + pat + " in " + rel.get("tag_name", "?"))
    return good[0]


def fetch_binary(asset):
    """باینری sing-box را از داخل آرشیو برمی‌گرداند (bytes) + همه‌ی فایل‌های همراه."""
    data = get(asset["browser_download_url"], timeout=300)
    files = {}
    if asset["name"].endswith(".zip"):
        z = zipfile.ZipFile(io.BytesIO(data))
        for m in z.infolist():
            if not m.is_dir():
                files[os.path.basename(m.filename)] = z.read(m)
    else:
        t = tarfile.open(fileobj=io.BytesIO(data), mode="r:gz")
        for m in t.getmembers():
            if m.isfile():
                files[os.path.basename(m.name)] = t.extractfile(m).read()
    exe = next((k for k in files if k in ("sing-box", "sing-box.exe")), None)
    if not exe:
        raise RuntimeError("sing-box binary not inside " + asset["name"])
    return exe, files


def sanity(name, blob):
    if len(blob) < 5_000_000:
        raise RuntimeError("%s looks too small (%d bytes)" % (name, len(blob)))
    if not name.endswith(".exe") and blob[:4] != b"\x7fELF" and blob[:4] not in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe"):
        raise RuntimeError(name + " is not an executable (bad magic)")


def desktop(pat, out):
    rel = release()
    a = pick(rel, pat)
    exe, files = fetch_binary(a)
    sanity(exe, files[exe])
    os.makedirs(out, exist_ok=True)
    for k, v in files.items():
        with open(os.path.join(out, k), "wb") as f:
            f.write(v)
    for f in os.listdir(out):
        if f.startswith("sing-box") and not f.endswith((".md", ".txt")):
            os.chmod(os.path.join(out, f), 0o755)
    print("sing-box", rel.get("tag_name"), a["name"], "->", out, len(files), "files")


def android(jni):
    rel = release()
    for abi, pats in ANDROID_ABIS:
        last = None
        for pat in pats:
            try:
                a = pick(rel, pat)
                exe, files = fetch_binary(a)
                sanity(exe, files[exe])
                d = os.path.join(jni, abi)
                os.makedirs(d, exist_ok=True)
                dst = os.path.join(d, "libsingbox.so")
                with open(dst, "wb") as f:
                    f.write(files[exe])
                os.chmod(dst, 0o755)
                print("sing-box", rel.get("tag_name"), a["name"], "->", dst, len(files[exe]), "bytes")
                break
            except Exception as e:  # noqa: BLE001
                last = e
        else:
            raise RuntimeError("android %s: %s" % (abi, last))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    pat, out = sys.argv[1], sys.argv[2]
    try:
        if pat == "android":
            android(out)
        else:
            desktop(pat, out)
    except Exception as e:  # noqa: BLE001
        if os.environ.get("SINGBOX_OPTIONAL") == "1":
            print("::warning::sing-box download failed:", e)
            return
        print("::error::sing-box download failed:", e)
        sys.exit(1)


main()
