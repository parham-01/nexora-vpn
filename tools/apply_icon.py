# ساخت آیکون برنامه از tools/nexora_icon.png برای اندروید / macOS / ویندوز
# استفاده: python3 tools/apply_icon.py client android|macos|windows
import json
import os
import sys
from PIL import Image

app, plat = sys.argv[1], sys.argv[2]
src = Image.open(os.path.join(os.path.dirname(__file__), 'nexora_icon.png')).convert('RGB')


def save(px, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    src.resize((px, px), Image.LANCZOS).save(path)


if plat == 'android':
    res = os.path.join(app, 'android/app/src/main/res')
    for d, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
        save(px, f'{res}/mipmap-{d}/ic_launcher.png')
    stat = Image.open(os.path.join(os.path.dirname(__file__), 'ic_stat_n.png')).convert('RGBA')
    for d, px in (('mdpi', 24), ('hdpi', 36), ('xhdpi', 48), ('xxhdpi', 72), ('xxxhdpi', 96)):
        out = f'{res}/drawable-{d}/ic_stat_logo.png'
        os.makedirs(os.path.dirname(out), exist_ok=True)
        stat.resize((px, px), Image.LANCZOS).save(out)
    any26 = os.path.join(res, 'mipmap-anydpi-v26')
    if os.path.isdir(any26):
        import shutil
        shutil.rmtree(any26)
elif plat == 'macos':
    d = os.path.join(app, 'macos/Runner/Assets.xcassets/AppIcon.appiconset')
    cj = os.path.join(d, 'Contents.json')
    data = json.load(open(cj))
    for im in data.get('images', []):
        fn = im.get('filename')
        if not fn:
            continue
        w = float(im['size'].split('x')[0])
        sc = int(im['scale'].replace('x', ''))
        save(int(round(w * sc)), os.path.join(d, fn))
elif plat == 'windows':
    path = os.path.join(app, 'windows/runner/resources/app_icon.ico')
    src.resize((256, 256), Image.LANCZOS).save(path, format='ICO', sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print('icon applied', app, plat)
