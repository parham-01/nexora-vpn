import os
import re
import sys

app = sys.argv[1]
label = sys.argv[2]

manifest = os.path.join(app, 'android/app/src/main/AndroidManifest.xml')
s = open(manifest, encoding='utf8').read()
if 'android.permission.INTERNET' not in s:
    s = s.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
if 'android:allowBackup' not in s:
    s = s.replace('<application', '<application android:allowBackup="true" android:fullBackupContent="true"', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="%s"' % label, s, count=1)
if 'usesCleartextTraffic' not in s:
    s = s.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
open(manifest, 'w', encoding='utf8').write(s)

for name in ('build.gradle.kts', 'build.gradle'):
    path = os.path.join(app, 'android/app', name)
    if not os.path.exists(path):
        continue
    kts = name.endswith('.kts')
    g = open(path, encoding='utf8').read()
    min_sdk = 'minSdk = 23' if kts else 'minSdkVersion 23'
    g = re.sub(r'minSdk(Version)?\s*=?\s*(flutter\.minSdkVersion|\d+)', lambda m: min_sdk, g, count=1)
    packaging = 'packaging { jniLibs { useLegacyPackaging = true } }' if kts else 'packagingOptions { jniLibs { useLegacyPackaging = true } }'
    g = re.sub(r'(android\s*\{)', lambda m: m.group(1) + '\n    ' + packaging, g, count=1)
    open(path, 'w', encoding='utf8').write(g)


# ---------- رفع خطای R8 (Missing class ... mlkit.vision.text.chinese/devanagari/japanese/korean) ----------
# پلاگین google_mlkit_text_recognition به گزینه‌های زبان‌های اضافه ارجاع می‌دهد که در اپ نیستند؛
# قوانین dontwarn باعث می‌شود R8 روی آن‌ها خطا ندهد (فقط لاتین استفاده می‌شود).
pg = os.path.join(app, 'android/app/proguard-rules.pro')
ptxt = open(pg, encoding='utf8').read() if os.path.exists(pg) else ''
if 'mlkit.vision.text.chinese' not in ptxt:
    ptxt += (
        '\n# ML Kit text recognition: optional language modules that are not bundled\n'
        '-dontwarn com.google.mlkit.vision.text.chinese.**\n'
        '-dontwarn com.google.mlkit.vision.text.devanagari.**\n'
        '-dontwarn com.google.mlkit.vision.text.japanese.**\n'
        '-dontwarn com.google.mlkit.vision.text.korean.**\n'
        '-dontwarn com.google.mlkit.**\n'
    )
    open(pg, 'w', encoding='utf8').write(ptxt)
for name in ('build.gradle.kts', 'build.gradle'):
    path = os.path.join(app, 'android/app', name)
    if not os.path.exists(path):
        continue
    kts = name.endswith('.kts')
    g = open(path, encoding='utf8').read()
    if 'proguard-rules.pro' in g:
        continue
    line = 'proguardFiles("proguard-rules.pro")' if kts else "proguardFiles 'proguard-rules.pro'"
    g2 = re.sub(r'(buildTypes\s*\{\s*(?:getByName\("release"\)|release)\s*\{)', lambda m: m.group(1) + '\n            ' + line, g, count=1)
    if g2 == g:
        # قالب بدون بلوک release: یکی می‌سازیم
        blk = ('\n    buildTypes {\n        getByName("release") {\n            ' + line + '\n        }\n    }\n') if kts else ('\n    buildTypes {\n        release {\n            ' + line + '\n        }\n    }\n')
        g2 = re.sub(r'(android\s*\{)', lambda m: m.group(1) + blk, g, count=1)
    open(path, 'w', encoding='utf8').write(g2)


# ---------- امضای انتشار (Google Play) ----------
# اگر متغیرهای KEYSTORE_PATH / KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD تنظیم باشند، ساخت release با همین کلید امضا می‌شود.
ks = os.environ.get('KEYSTORE_PATH')
if ks:
    props = os.path.join(app, 'android/key.properties')
    with open(props, 'w', encoding='utf8') as f:
        f.write('storePassword=%s\n' % os.environ['KEYSTORE_PASSWORD'])
        f.write('keyPassword=%s\n' % os.environ['KEY_PASSWORD'])
        f.write('keyAlias=%s\n' % os.environ['KEY_ALIAS'])
        f.write('storeFile=%s\n' % os.path.abspath(ks))
    for name in ('build.gradle.kts', 'build.gradle'):
        path = os.path.join(app, 'android/app', name)
        if not os.path.exists(path):
            continue
        kts = name.endswith('.kts')
        g = open(path, encoding='utf8').read()
        if 'keystoreProperties' in g:
            continue
        if kts:
            g = 'import java.util.Properties\nimport java.io.FileInputStream\n\n' + g
            load = (
                'val keystoreProperties = Properties()\n'
                'val keystorePropertiesFile = rootProject.file("key.properties")\n'
                'if (keystorePropertiesFile.exists()) { keystoreProperties.load(FileInputStream(keystorePropertiesFile)) }\n\n'
            )
            sign = (
                '\n    signingConfigs {\n'
                '        create("release") {\n'
                '            keyAlias = keystoreProperties["keyAlias"] as String\n'
                '            keyPassword = keystoreProperties["keyPassword"] as String\n'
                '            storeFile = file(keystoreProperties["storeFile"] as String)\n'
                '            storePassword = keystoreProperties["storePassword"] as String\n'
                '        }\n'
                '    }\n'
            )
            g = re.sub(r'(\nandroid\s*\{)', lambda m: '\n' + load + m.group(1).lstrip('\n') + sign, g, count=1)
            g = re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', 'signingConfig = signingConfigs.getByName("release")', g)
        else:
            load = (
                'def keystoreProperties = new Properties()\n'
                'def keystorePropertiesFile = rootProject.file("key.properties")\n'
                'if (keystorePropertiesFile.exists()) { keystoreProperties.load(new FileInputStream(keystorePropertiesFile)) }\n\n'
            )
            sign = (
                '\n    signingConfigs {\n'
                '        release {\n'
                '            keyAlias keystoreProperties["keyAlias"]\n'
                '            keyPassword keystoreProperties["keyPassword"]\n'
                '            storeFile file(keystoreProperties["storeFile"])\n'
                '            storePassword keystoreProperties["storePassword"]\n'
                '        }\n'
                '    }\n'
            )
            g = re.sub(r'(\nandroid\s*\{)', lambda m: '\n' + load + m.group(1).lstrip('\n') + sign, g, count=1)
            g = re.sub(r'signingConfig\s+signingConfigs\.debug', 'signingConfig signingConfigs.release', g)
        open(path, 'w', encoding='utf8').write(g)


if 'Admin' not in label:
    res = os.path.join(app, 'android/app/src/main/res')
    os.makedirs(os.path.join(res, 'drawable'), exist_ok=True)
    os.makedirs(os.path.join(res, 'drawable-v21'), exist_ok=True)
    bg = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <item android:drawable="@android:color/black"/>\n'
        '    <item>\n'
        '        <bitmap android:gravity="center" android:src="@mipmap/ic_launcher"/>\n'
        '    </item>\n'
        '</layer-list>\n'
    )
    for d in ('drawable', 'drawable-v21'):
        open(os.path.join(res, d, 'launch_background.xml'), 'w', encoding='utf8').write(bg)
    styles = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">\n'
        '        <item name="android:windowBackground">@drawable/launch_background</item>\n'
        '        <item name="android:windowSplashScreenBackground">#000000</item>\n'
        '        <item name="android:windowSplashScreenAnimatedIcon">@mipmap/ic_launcher</item>\n'
        '        <item name="android:windowDrawsSystemBarBackgrounds">true</item>\n'
        '        <item name="android:statusBarColor">#000000</item>\n'
        '        <item name="android:navigationBarColor">#000000</item>\n'
        '    </style>\n'
        '    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">\n'
        '        <item name="android:windowBackground">@android:color/black</item>\n'
        '    </style>\n'
        '</resources>\n'
    )
    for d in ('values', 'values-night'):
        os.makedirs(os.path.join(res, d), exist_ok=True)
        open(os.path.join(res, d, 'styles.xml'), 'w', encoding='utf8').write(styles)
    v31 = os.path.join(res, 'values-v31')
    os.makedirs(v31, exist_ok=True)
    open(os.path.join(v31, 'styles.xml'), 'w', encoding='utf8').write(styles.replace('Theme.Black.NoTitleBar', 'Theme.DeviceDefault.NoActionBar'))


# ---------- جلوگیری از kill شدن بیلد (Error: Process completed with exit code 143) ----------
# قالب Flutter مقدار -Xmx8G می‌گذارد؛ روی runner گیت‌هاب (حدود 7GB رم) پروسه‌ی Gradle با SIGTERM کشته می‌شود.
gp = os.path.join(app, 'android', 'gradle.properties')
keep = []
if os.path.exists(gp):
    drop = re.compile(r'\s*(org\.gradle\.(jvmargs|daemon|parallel|workers\.max|caching)|kotlin\.daemon\.jvm\.options|kotlin\.compiler\.execution\.strategy)\s*=')
    keep = [l for l in open(gp, encoding='utf8').read().splitlines() if not drop.match(l)]
keep += [
    'org.gradle.jvmargs=-Xmx3g -XX:MaxMetaspaceSize=768m -XX:+UseSerialGC',
    'org.gradle.daemon=false',
    'org.gradle.parallel=false',
    'org.gradle.workers.max=2',
    'kotlin.compiler.execution.strategy=in-process',
]
open(gp, 'w', encoding='utf8').write('\n'.join(keep) + '\n')
