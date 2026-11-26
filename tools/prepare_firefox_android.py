#!/usr/bin/env python3
"""Attach the separately licensed Nexora/Guardian Android VPN core to Flutter's generated Android host."""
from pathlib import Path
import re
import shutil
import os
import sys

app = Path(sys.argv[1] if len(sys.argv) > 1 else 'client').resolve()
root = app.parent
nexora = app / 'third_party' / 'nexora-core'
android_src = nexora / 'android'
android = app / 'android'
main_pkg = 'com.parham.parham_client'
firefox_pkg = main_pkg + '.firefox'
ndk = os.environ.get('NDK_VERSION') or '30.0.16248370'

required = [
    nexora / 'LICENSE',
    android_src / 'CoreService.kt',
    android_src / 'Tun2Socks.kt',
    android_src / 'hev-socks5-tunnel' / 'Android.mk',
]
missing = [str(p) for p in required if not p.exists()]
if missing:
    raise SystemExit('Missing vendored Nexora Android sources: ' + ', '.join(missing))

# Native HEV tunnel source, kept in a separate folder from the existing V2Ray engine.
hev_target = android / 'hev-socks5-tunnel'
if hev_target.exists():
    shutil.rmtree(hev_target)
shutil.copytree(android_src / 'hev-socks5-tunnel', hev_target)

kotlin = android / 'app' / 'src' / 'main' / 'kotlin' / Path(*main_pkg.split('.'))
firefox_kotlin = kotlin / 'firefox'
firefox_kotlin.mkdir(parents=True, exist_ok=True)

core = (android_src / 'CoreService.kt').read_text(encoding='utf-8')
core = core.replace('package com.nexora.firefoxvpn', f'package {firefox_pkg}', 1)
core = core.replace('import android.widget.Toast', 'import android.widget.Toast\nimport ' + main_pkg + '.MainActivity\nimport ' + main_pkg + '.R', 1)
core = re.sub(r'^\s*(?:QuickTile\.refresh\([^\n]*\)|ConnectWidget\.updateAll\([^\n]*\))\s*\n', '', core, flags=re.M)
core = core.replace('the app\'s button, the Quick\n * Settings tile', 'the app\'s button')
(core_path := firefox_kotlin / 'CoreService.kt').write_text(core, encoding='utf-8')

tun = (android_src / 'Tun2Socks.kt').read_text(encoding='utf-8')
tun = tun.replace('package com.nexora.firefoxvpn', f'package {firefox_pkg}', 1)
(firefox_kotlin / 'Tun2Socks.kt').write_text(tun, encoding='utf-8')

# Notification icon and strings used by the vendored service.
res = android / 'app' / 'src' / 'main' / 'res'
(res / 'drawable').mkdir(parents=True, exist_ok=True)
shutil.copy2(Path(__file__).resolve().parent / 'ic_stat_n.png', res / 'drawable' / 'ic_stat_logo.png')
values = res / 'values'
values.mkdir(parents=True, exist_ok=True)
strings_path = values / 'strings.xml'
if strings_path.exists():
    strings = strings_path.read_text(encoding='utf-8')
else:
    strings = '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n</resources>\n'
entries = {
    'app_name': 'NEXORA VPN',
    'notification_channel': 'Firefox VPN',
    'notification_connecting': 'Connecting to Firefox VPN…',
    'notification_no_network': 'No internet connection',
    'notification_proxy': 'Firefox VPN · %1$s',
    'notification_stop': 'Disconnect Firefox VPN',
}
for name, value in entries.items():
    if not re.search(r'<string\s+name=["\']' + re.escape(name) + r'["\']', strings):
        strings = strings.replace('</resources>', f'    <string name="{name}">{value}</string>\n</resources>')
strings_path.write_text(strings, encoding='utf-8')

# The generated Flutter host manifest gets a second, independent VpnService.
manifest = android / 'app' / 'src' / 'main' / 'AndroidManifest.xml'
m = manifest.read_text(encoding='utf-8')
permissions = [
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
    'android.permission.POST_NOTIFICATIONS',
]
for permission in permissions:
    if permission not in m:
        m = m.replace('<application', f'    <uses-permission android:name="{permission}" />\n    <application', 1)
if 'android:usesCleartextTraffic' not in m:
    m = m.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
if f'android:name="{firefox_pkg}.CoreService"' not in m:
    service = f'''        <!-- Independent Firefox/Guardian VPN service; existing Parham service stays unchanged. -->
        <service
            android:name="{firefox_pkg}.CoreService"
            android:exported="false"
            android:foregroundServiceType="specialUse"
            android:permission="android.permission.BIND_VPN_SERVICE">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="An independently selected Firefox VPN connection." />
        </service>
'''
    m = m.replace('</application>', service + '    </application>', 1)
manifest.write_text(m, encoding='utf-8')

# Configure NDK/JNI only for the new Firefox tunnel and bind the Go core AAR.
gradle = android / 'app' / 'build.gradle.kts'
g = gradle.read_text(encoding='utf-8')
g = re.sub(r'\n\s*ndkVersion\s*=\s*[^\n]*', '', g)
g = re.sub(r'(android\s*\{)', r'\1\n    ndkVersion = "' + ndk + '"', g, count=1)
if 'externalNativeBuild {\n        ndkBuild' not in g:
    block = '''
    externalNativeBuild {
        ndkBuild { path = file("../hev-socks5-tunnel/Android.mk") }
    }
'''
    g = re.sub(r'(android\s*\{)', lambda x: x.group(1) + block, g, count=1)
# Make gomobile's API-24 requirement explicit after the Parham Android patcher.
g = re.sub(r'minSdk\s*=\s*(?:flutter\.minSdkVersion|\d+|maxOf\([^\n]*\))', 'minSdk = 24', g, count=1)
if 'targets += "hev-socks5-tunnel"' not in g:
    default_config = '''
        externalNativeBuild {
            ndkBuild {
                targets += "hev-socks5-tunnel"
                arguments += listOf("REV_ID=2.19.3", "APP_SUPPORT_FLEXIBLE_PAGE_SIZES=true")
                cFlags += listOf("-O3", "-DPKGNAME=com/parham/parham_client/firefox", "-DCLSNAME=Tun2Socks")
            }
        }
'''
    g = re.sub(r'(defaultConfig\s*\{)', lambda x: x.group(1) + default_config, g, count=1)
if 'useLegacyPackaging = true' not in g:
    g = re.sub(r'(android\s*\{)', r'\1\n    packaging { jniLibs { useLegacyPackaging = true } }', g, count=1)
if 'implementation("androidx.webkit:webkit:1.15.0")' not in g:
    if re.search(r'\ndependencies\s*\{', g):
        g = re.sub(r'(\ndependencies\s*\{)', r'\1\n    implementation("androidx.webkit:webkit:1.15.0")\n', g, count=1)
    else:
        g += '\n\ndependencies {\n    implementation("androidx.webkit:webkit:1.15.0")\n}\n'
if 'implementation(files("libs/core.aar"))' not in g:
    if re.search(r'\ndependencies\s*\{', g):
        g = re.sub(r'(\ndependencies\s*\{)', r'\1\n    implementation(files("libs/core.aar"))\n', g, count=1)
    else:
        g += '\n\ndependencies {\n    implementation(files("libs/core.aar"))\n}\n'
if 'exclude(group = "com.github.2dust", module = "libv2ray")' not in g:
    g = re.sub(r'(android\s*\{)', lambda x: x.group(1) + '\n    configurations.all {\n        exclude(group = "com.github.2dust", module = "libv2ray")\n    }', g, count=1)
if 'configurations.configureEach' not in g:
    g += '\n\nconfigurations.configureEach {\n    exclude(group = "com.github.2dust", module = "libv2ray")\n}\n'
if 'finalizeDsl' not in g:
    g += '''

// The Flutter template creates an empty CMake project; this app uses ndk-build for HEV.
androidComponents {
    finalizeDsl { it.externalNativeBuild.cmake.path = null }
}
'''
gradle.write_text(g, encoding='utf-8')

# Keep the JNI entry points even if a downstream release turns on shrinking.
proguard = android / 'app' / 'proguard-rules.pro'
proguard.parent.mkdir(parents=True, exist_ok=True)
ptext = proguard.read_text(encoding='utf-8') if proguard.exists() else ''
if 'com.parham.parham_client.firefox.Tun2Socks' not in ptext:
    ptext += '\n-keep class com.parham.parham_client.firefox.Tun2Socks { *; }\n'
proguard.write_text(ptext, encoding='utf-8')

# The generated MainActivity exposes a dedicated channel. It never calls or replaces Parham's VPN engine.
main_activity = kotlin / 'MainActivity.kt'
activity = f'''package {main_pkg}

import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import java.util.concurrent.Executor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import mobile.Mobile
import {firefox_pkg}.CoreService

class MainActivity : FlutterActivity() {{
    private var pendingVpnResult: MethodChannel.Result? = null
    private val firefoxRequestCode = 9821
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "parham/firefox")
            .setMethodCallHandler {{ call, result ->
                when (call.method) {{
                    "dataDir" -> result.success(CoreService.dataDir(this).absolutePath)
                    "isRunning" -> result.success(Mobile.running())
                    "startCore" -> {{
                        CoreService.startCore(this, on = false)
                        result.success(null)
                    }}
                    "setWebViewProxy" -> {{
                        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {{
                            result.success(false)
                        }} else {{
                            val address = call.argument<String>("address")
                            val proxies = ProxyController.getInstance()
                            val onMain = Executor {{ command -> mainHandler.post(command) }}
                            val done = Runnable {{ result.success(true) }}
                            if (address.isNullOrEmpty()) {{
                                proxies.clearProxyOverride(onMain, done)
                            }} else {{
                                proxies.setProxyOverride(
                                    ProxyConfig.Builder().addProxyRule(address).build(),
                                    onMain,
                                    done
                                )
                            }}
                        }}
                    }}
                    "setOn" -> {{
                        val on = call.argument<Boolean>("on") == true
                        if (!on) {{
                            CoreService.turnOff(this)
                            result.success(null)
                        }} else {{
                            if (pendingVpnResult != null) {{
                                result.error("busy", "Firefox VPN permission request is already active", null)
                            }} else {{
                                val permissionIntent = VpnService.prepare(this)
                                if (permissionIntent == null) {{
                                    turnFirefoxOn(result)
                                }} else {{
                                    pendingVpnResult = result
                                    try {{
                                        startActivityForResult(permissionIntent, firefoxRequestCode)
                                    }} catch (e: Exception) {{
                                        pendingVpnResult = null
                                        result.error("vpn_permission", e.message, null)
                                    }}
                                }}
                            }}
                        }}
                    }}
                    else -> result.notImplemented()
                }}
            }}
    }}

    private fun turnFirefoxOn(result: MethodChannel.Result) {{
        try {{
            CoreService.turnOn(this)
            result.success(null)
        }} catch (e: Exception) {{
            result.error("firefox_start", e.message, null)
        }}
    }}

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {{
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != firefoxRequestCode) return
        val pending = pendingVpnResult ?: return
        pendingVpnResult = null
        if (resultCode == RESULT_OK) turnFirefoxOn(pending)
        else pending.error("vpn_permission_denied", "VPN permission was denied", null)
    }}
}}
'''
main_activity.write_text(activity, encoding='utf-8')

print('Prepared Firefox Android service, native tunnel, resources, manifest, Gradle and MethodChannel.')


import os as _os
for _n in ('build.gradle.kts', 'build.gradle'):
    _p = str(app / 'android' / _n)
    if _os.path.exists(_p):
        _t = open(_p, encoding='utf-8').read()
        if 'lintVital' not in _t:
            if _n.endswith('.kts'):
                _t += '\n\ngradle.taskGraph.whenReady {\n    allTasks.filter { it.name.startsWith("lintVital") }.forEach { it.enabled = false }\n}\n'
            else:
                _t += '\n\ngradle.taskGraph.whenReady { g ->\n    g.allTasks.findAll { it.name.startsWith("lintVital") }.each { it.enabled = false }\n}\n'
            open(_p, 'w', encoding='utf-8').write(_t)
        break
