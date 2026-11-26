#!/usr/bin/env bash
# دانلود فونت وزیرمتن و ثبت آن در pubspec (اگر دانلود نشد، برنامه با فونت پیش‌فرض ساخته می‌شود)
set -uo pipefail
app="$1"
dir="$app/assets/fonts"
mkdir -p "$dir"
ok=1
for w in Regular Medium Bold; do
  got=0
  for url in \
    "https://github.com/rastikerdar/vazirmatn/raw/master/fonts/ttf/Vazirmatn-$w.ttf" \
    "https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/fonts/ttf/Vazirmatn-$w.ttf"; do
    if curl -fsSL --retry 2 -o "$dir/Vazirmatn-$w.ttf" "$url" && [ -s "$dir/Vazirmatn-$w.ttf" ]; then got=1; break; fi
  done
  [ "$got" = 1 ] || ok=0
done
if [ "$ok" = 1 ]; then
  python3 - "$app" <<'PY'
import sys
p = sys.argv[1] + '/pubspec.yaml'
s = open(p, encoding='utf8').read()
if 'Vazirmatn' not in s:
    s = s.rstrip('\n') + """
  fonts:
    - family: Vazirmatn
      fonts:
        - asset: assets/fonts/Vazirmatn-Regular.ttf
        - asset: assets/fonts/Vazirmatn-Medium.ttf
          weight: 500
        - asset: assets/fonts/Vazirmatn-Bold.ttf
          weight: 700
"""
    open(p, 'w', encoding='utf8').write(s)
print('font added')
PY
else
  echo "font download failed; using default font"
  rm -rf "$dir"
fi
exit 0
