"""Run after `flutter create --platforms=android .` to apply the spec's Android requirements."""
import pathlib
import re

root = pathlib.Path("android/app")

# --- AndroidManifest.xml -------------------------------------------------
m = root / "src/main/AndroidManifest.xml"
s = m.read_text()

perms = [
    "INTERNET",
    "POST_NOTIFICATIONS",
    "SCHEDULE_EXACT_ALARM",
    "USE_EXACT_ALARM",
    "RECEIVE_BOOT_COMPLETED",
    "VIBRATE",
]
add = "".join(
    f'    <uses-permission android:name="android.permission.{p}"/>\n'
    for p in perms
    if f"android.permission.{p}" not in s
)
s = s.replace("<application", add + "    <application", 1)

if "allowBackup" not in s:
    s = s.replace(
        "<application",
        '<application\n        android:allowBackup="false"\n        android:fullBackupContent="false"',
        1,
    )
s = re.sub(r'android:label="[^"]*"', 'android:label="Daily Login Runner"', s, count=1)

receivers = """
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""
if "ScheduledNotificationReceiver" not in s:
    s = s.replace("</application>", receivers + "    </application>", 1)
m.write_text(s)

# --- Gradle: minSdk 23 + core library desugaring --------------------------
kts = root / "build.gradle.kts"
groovy = root / "build.gradle"
if kts.exists():
    t = kts.read_text()
    t = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", t)
    t = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", t, count=1)
    t += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    kts.write_text(t)
    assert "minSdk = 23" in t, "minSdk patch did not apply; edit android/app/build.gradle.kts by hand"
elif groovy.exists():
    t = groovy.read_text()
    t = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", t)
    t = re.sub(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", t, count=1)
    t += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    groovy.write_text(t)
    assert "minSdkVersion 23" in t, "minSdk patch did not apply; edit android/app/build.gradle by hand"
else:
    raise SystemExit("no android/app/build.gradle(.kts) found")

# the default counter test references MyApp and would break `flutter analyze`
pathlib.Path("test/widget_test.dart").unlink(missing_ok=True)
print("android patched")
