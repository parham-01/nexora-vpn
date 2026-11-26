#!/usr/bin/env python3
"""Adds the in-app updater (GitHub Releases + dataSync foreground download service) to the generated Android host.
Run after tools/prepare_firefox_android.py:  python3 tools/prepare_updater_android.py client
"""
from pathlib import Path
import re
import sys

app = Path(sys.argv[1] if len(sys.argv) > 1 else 'client').resolve()
here = Path(__file__).resolve().parent / 'updater_android'
pkg = 'com.parham.parham_client'
android = app / 'android'
kotlin = android / 'app' / 'src' / 'main' / 'kotlin' / Path(*pkg.split('.'))
kotlin.mkdir(parents=True, exist_ok=True)

for name in ('UpdateService.kt', 'UpdateChannel.kt'):
    (kotlin / name).write_text((here / name).read_text(encoding='utf-8').replace('__PKG__', pkg), encoding='utf-8')

xml = android / 'app' / 'src' / 'main' / 'res' / 'xml'
xml.mkdir(parents=True, exist_ok=True)
(xml / 'nexora_update_paths.xml').write_text((here / 'nexora_update_paths.xml').read_text(encoding='utf-8'), encoding='utf-8')

# ---- manifest ----
manifest = android / 'app' / 'src' / 'main' / 'AndroidManifest.xml'
m = manifest.read_text(encoding='utf-8')
for perm in (
    'android.permission.INTERNET',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.REQUEST_INSTALL_PACKAGES',
):
    if perm not in m:
        m = m.replace('<application', f'    <uses-permission android:name="{perm}" />\n    <application', 1)
if f'{pkg}.UpdateService' not in m and '.UpdateService' not in m:
    block = f'''        <!-- دانلود به‌روزرسانی در پس‌زمینه (Foreground Service از نوع dataSync) -->
        <service
            android:name="{pkg}.UpdateService"
            android:exported="false"
            android:foregroundServiceType="dataSync" />
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${{applicationId}}.updatefp"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/nexora_update_paths" />
        </provider>
'''
    m = m.replace('</application>', block + '    </application>', 1)
manifest.write_text(m, encoding='utf-8')

# ---- MainActivity: register the update channel ----
main_activity = kotlin / 'MainActivity.kt'
if not main_activity.exists():
    main_activity.write_text(f'''package {pkg}

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
    }}
}}
''', encoding='utf-8')
a = main_activity.read_text(encoding='utf-8')
if 'UpdateChannel.register' not in a:
    if 'super.configureFlutterEngine(flutterEngine)' not in a:
        raise SystemExit('MainActivity.kt: configureFlutterEngine not found')
    a = a.replace('super.configureFlutterEngine(flutterEngine)',
                  'super.configureFlutterEngine(flutterEngine)\n        UpdateChannel.register(flutterEngine, this)', 1)
main_activity.write_text(a, encoding='utf-8')

# ---- gradle: FileProvider lives in androidx.core ----
for name in ('build.gradle.kts', 'build.gradle'):
    path = android / 'app' / name
    if not path.exists():
        continue
    g = path.read_text(encoding='utf-8')
    if 'androidx.core:core:' not in g:
        dep = 'implementation("androidx.core:core:1.13.1")' if name.endswith('.kts') else "implementation 'androidx.core:core:1.13.1'"
        if re.search(r'\ndependencies\s*\{', g):
            g = re.sub(r'(\ndependencies\s*\{)', lambda x: x.group(1) + '\n    ' + dep + '\n', g, count=1)
        else:
            g += '\n\ndependencies {\n    ' + dep + '\n}\n'
        path.write_text(g, encoding='utf-8')
    break

print('Prepared updater: UpdateService (dataSync), UpdateChannel, FileProvider, manifest, Gradle.')
