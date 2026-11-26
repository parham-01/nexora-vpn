#!/usr/bin/env bash
# دانلود فونت پیکسلی Press Start 2P (OFL) برای صفحه‌ی به‌روزرسانی؛ اگر دانلود نشد، برنامه با فونت پیش‌فرض ساخته می‌شود.
set -uo pipefail
app="$1"
dir="$app/assets/fonts"
mkdir -p "$dir"
f="$dir/PressStart2P-Regular.ttf"
got=0
for url in \
  "https://github.com/google/fonts/raw/main/ofl/pressstart2p/PressStart2P-Regular.ttf" \
  "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/pressstart2p/PressStart2P-Regular.ttf"; do
  if curl -fsSL --retry 2 -o "$f" "$url" && [ -s "$f" ]; then got=1; break; fi
done
if [ "$got" = 1 ]; then
  python3 - "$app" <<'PY'
import sys
p = sys.argv[1] + '/pubspec.yaml'
s = open(p, encoding='utf8').read()
if 'PressStart2P' not in s:
    fam = "    - family: PressStart2P\n      fonts:\n        - asset: assets/fonts/PressStart2P-Regular.ttf\n"
    if '\n  fonts:' in s:
        s = s.rstrip('\n') + '\n' + fam
    else:
        s = s.rstrip('\n') + '\n  fonts:\n' + fam
    open(p, 'w', encoding='utf8').write(s)
print('pixel font added')
PY
else
  echo "pixel font download failed; using default font"
  rm -f "$f"
fi
exit 0
