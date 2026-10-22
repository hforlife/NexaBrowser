"""Ajuste les fichiers Android/iOS générés par « flutter create » (idempotent)."""

from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "NexaBrowser"

# ---------------------------------------------------------------- Android
manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
text = manifest.read_text(encoding="utf-8")

# Accès Internet (absent du manifeste principal par défaut → requis en release)
if "android.permission.INTERNET" not in text:
    text = text.replace(
        "<application",
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <application',
        1,
    )
# Sites encore en http:// (fréquent sur les sites locaux)
if "usesCleartextTraffic" not in text:
    text = text.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
# Nom affiché sous l'icône
text = text.replace('android:label="nexa_browser"', f'android:label="{APP_NAME}"')
manifest.write_text(text, encoding="utf-8")
print("✔ AndroidManifest.xml")

# -------------------------------------------------------------------- iOS
plist_path = ROOT / "ios/Runner/Info.plist"
if plist_path.exists():
    with plist_path.open("rb") as f:
        plist = plistlib.load(f)
    plist["CFBundleDisplayName"] = APP_NAME
    plist["NSAppTransportSecurity"] = {"NSAllowsArbitraryLoads": True}
    with plist_path.open("wb") as f:
        plistlib.dump(plist, f)
    print("✔ Info.plist")
