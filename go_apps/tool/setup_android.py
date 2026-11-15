"""Configures the three Android projects (labels, permissions, gradle, icons).
Idempotent: python tool/setup_android.py"""
import os, re, struct, zlib, math

ROOT = os.path.join(os.path.dirname(__file__), '..')
APPS = {
    "customer": {"label": "Go Customer", "color": (0x0B, 0x8A, 0x5B), "glyph": "pin", "extra_perms": ["CAMERA"], "lock": False},
    'rider': {'label': 'Go Rider', 'color': (0xF0, 0x8C, 0x00), 'glyph': 'bike',
              'extra_perms': ['FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_LOCATION', 'WAKE_LOCK', 'VIBRATE', 'USE_FULL_SCREEN_INTENT', 'CAMERA'], 'lock': True},
    'merchant': {'label': 'Go Merchant', 'color': (0xE5, 0x53, 0x3D), 'glyph': 'store',
                 'extra_perms': ['WAKE_LOCK', 'VIBRATE', 'USE_FULL_SCREEN_INTENT', 'CAMERA'], 'lock': True},
}
BASE_PERMS = ['INTERNET', 'ACCESS_NETWORK_STATE', 'ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION', 'POST_NOTIFICATIONS']

def png(path, size, color, glyph):
    rows = []
    c = size / 2
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            dx, dy = x - c + 0.5, y - c + 0.5
            r = math.hypot(dx, dy)
            px = (0, 0, 0, 0)
            if r < size * 0.48:
                px = (*color, 255)
                u, v = dx / size, dy / size  # -0.5..0.5
                white = False
                if glyph == 'pin':
                    white = math.hypot(u, v + 0.05) < 0.2 and not math.hypot(u, v + 0.05) < 0.08 or (abs(u) < 0.2 - (v - 0.05) * 0.9 and 0.05 < v < 0.27 and abs(u) < (0.27 - v) * 0.95)
                elif glyph == 'bike':
                    white = math.hypot(u + 0.17, v - 0.1) < 0.1 or math.hypot(u - 0.17, v - 0.1) < 0.1 or (abs(v + 0.02 + u * 0.3) < 0.04 and -0.15 < u < 0.2) or (abs(u - 0.13) < 0.035 and -0.2 < v < 0.05)
                    white = white and not (math.hypot(u + 0.17, v - 0.1) < 0.05 or math.hypot(u - 0.17, v - 0.1) < 0.05)
                elif glyph == 'store':
                    white = (abs(u) < 0.25 and -0.05 < v < 0.24) or (abs(u) < 0.29 and -0.2 < v < -0.05)
                    white = white and not (abs(u) < 0.07 and 0.06 < v < 0.24)
                if white:
                    px = (255, 255, 255, 255)
            elif r < size * 0.49:
                px = (*color, int(255 * (size * 0.49 - r) / (size * 0.01)))
            row += bytes(px)
        rows.append(bytes(row))
    raw = zlib.compress(b''.join(rows), 9)
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)) + chunk(b'IDAT', raw) + chunk(b'IEND', b'')
    open(path, 'wb').write(data)

GRADLE_HEADER = '''import java.util.Base64

// Values passed with --dart-define (base64 list in the "dart-defines" property).
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.map { String(Base64.getDecoder().decode(it)) }
        ?.mapNotNull { val i = it.indexOf('='); if (i > 0) it.substring(0, i) to it.substring(i + 1) else null }
        ?.toMap() ?: emptyMap()

'''

for app, cfg in APPS.items():
    adir = os.path.join(ROOT, 'apps', app, 'android')
    # ---- build.gradle.kts
    p = os.path.join(adir, 'app', 'build.gradle.kts')
    s = open(p).read()
    if 'dartDefines' not in s:
        s = GRADLE_HEADER + s
        s = s.replace('minSdk = flutter.minSdkVersion', 'minSdk = 23')
        s = s.replace('compileSdk = flutter.compileSdkVersion', 'compileSdk = 37 // flutter_local_notifications 23 needs API 37')
        s = s.replace('versionName = flutter.versionName', 'versionName = flutter.versionName\n        manifestPlaceholders["googleMapsKey"] = dartDefines["GOOGLE_MAPS_KEY"] ?: ""')
        s = s.replace('targetCompatibility = JavaVersion.VERSION_17', 'targetCompatibility = JavaVersion.VERSION_17\n        isCoreLibraryDesugaringEnabled = true')
        s = s.replace('            signingConfig = signingConfigs.getByName("debug")',
                      '            signingConfig = signingConfigs.getByName("debug")\n            isMinifyEnabled = true\n            isShrinkResources = true')
        s = s.replace('        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).\n', '')
        s += '''
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

// Firebase: drop this app's google-services.json into android/app/ (see README).
// Without it the app builds and runs with push disabled.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
'''
        open(p, 'w').write(s)
    # ---- settings.gradle.kts
    p = os.path.join(adir, 'settings.gradle.kts')
    s = open(p).read()
    if 'google-services' not in s:
        s = s.replace('    id("org.jetbrains.kotlin.android")', '    id("com.google.gms.google-services") version "4.6.0" apply false\n    id("org.jetbrains.kotlin.android")')
        open(p, 'w').write(s)
    # ---- manifest
    p = os.path.join(adir, 'app', 'src', 'main', 'AndroidManifest.xml')
    s = open(p).read()
    s = re.sub(r'\s*<uses-permission[^>]*/>', '', s)
    perms = ''.join(f'\n    <uses-permission android:name="android.permission.{x}"/>' for x in BASE_PERMS + cfg['extra_perms'])
    s = s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">', '<manifest xmlns:android="http://schemas.android.com/apk/res/android">' + perms, 1)
    s = re.sub(r'android:label="[^"]*"', f'android:label="{cfg["label"]}"', s)
    if 'geo.API_KEY' not in s:
        s = s.replace('''        <meta-data
            android:name="flutterEmbedding"''', '''        <meta-data
            android:name="com.google.android.geo.API_KEY"
            android:value="${googleMapsKey}" />
        <meta-data
            android:name="flutterEmbedding"''')
    # DEV ONLY: allows http:// to the local test backend. Remove (use HTTPS) before release.
    if 'usesCleartextTraffic' not in s:
        s = s.replace('android:name="${applicationName}"', 'android:name="${applicationName}"\n        android:usesCleartextTraffic="true"', 1)
    if cfg['lock'] and 'showWhenLocked' not in s:
        s = s.replace('android:hardwareAccelerated="true"', 'android:hardwareAccelerated="true"\n            android:showWhenLocked="true"\n            android:turnScreenOn="true"')
    if 'google.navigation' not in s:
        s = s.replace('''    <queries>''', '''    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL"/>
            <data android:scheme="tel"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="google.navigation"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="waze"/>
        </intent>''')
    open(p, 'w').write(s)
    # ---- icons
    for d, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        png(os.path.join(adir, 'app', 'src', 'main', 'res', f'mipmap-{d}', 'ic_launcher.png'), size, cfg['color'], cfg['glyph'])
    print('configured', app)
