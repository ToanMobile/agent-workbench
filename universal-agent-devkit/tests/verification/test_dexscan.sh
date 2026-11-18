#!/usr/bin/env bash
# Regression test: profiles/android/scripts/qa/dexscan.py on synthetic APK / AAB / DEX files.
# Before the fix: a missing file or no argument exited 0 (silent pass), an .aab was not scanned at all, and the
# DEX method count that android-rules.md promises (warn ≥ 60,000 per DEX, cap 65,536) was never computed.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCAN="$DEVKIT_DIR/profiles/android/scripts/qa/dexscan.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Synthetic inputs: a DEX header (0x70 bytes, method_ids_size at 0x58) plus an optional body.
python3 - "$TMP" <<'PY'
import struct, sys, zipfile
d = sys.argv[1]
def dex(methods, body=b''):
    h = bytearray(0x70); h[0:8] = b'dex\n035\x00'; struct.pack_into('<I', h, 0x58, methods)
    return bytes(h) + body
open(f'{d}/big.dex', 'wb').write(dex(61000))
with zipfile.ZipFile(f'{d}/app.aab', 'w') as z:
    z.writestr('base/dex/classes.dex', dex(10, b'Landroid/os/Build;->SERIAL'))
with zipfile.ZipFile(f'{d}/clean.apk', 'w') as z:
    z.writestr('classes.dex', dex(10)); z.writestr('classes2.dex', dex(20))
open(f'{d}/AndroidManifest.xml', 'w').write('''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="x">
<application>
  <activity android:name=".Main" android:exported="true"><intent-filter>
    <action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity>
  <receiver android:name="com.sdk.OpenReceiver" android:exported="true"/>
  <service android:name="com.sdk.Guarded" android:exported="true" android:permission="com.x.P"/>
  <provider android:name="com.sdk.Hidden" android:exported="false"/>
</application></manifest>''')
PY

FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

python3 "$SCAN" "$TMP/nope.apk" >"$TMP/log" 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "missing file -> exit 2" || bad "missing file -> exit $rc, expected 2"

python3 "$SCAN" >"$TMP/log" 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "no argument -> exit 2" || bad "no argument -> exit $rc, expected 2"

python3 "$SCAN" "$TMP/app.aab" >"$TMP/log" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'base/dex/classes.dex' "$TMP/log"; then ok ".aab dex scanned (Build.SERIAL found)"
else bad ".aab -> exit $rc: $(cat "$TMP/log")"; fi

python3 "$SCAN" "$TMP/big.dex" >"$TMP/log" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q '61000' "$TMP/log" && grep -qi 'method' "$TMP/log"; then ok "61,000-method DEX -> warning, exit 0"
else bad "big dex -> exit $rc: $(cat "$TMP/log")"; fi

python3 "$SCAN" "$TMP/clean.apk" >"$TMP/log" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -qi 'manifest: chưa kiểm' "$TMP/log"; then ok "clean apk, no --manifest -> says manifest not checked"
else bad "clean apk -> exit $rc: $(cat "$TMP/log")"; fi

python3 "$SCAN" "$TMP/clean.apk" --manifest "$TMP/AndroidManifest.xml" >"$TMP/log" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'com.sdk.OpenReceiver' "$TMP/log" && ! grep -q 'com.sdk.Guarded' "$TMP/log" \
   && ! grep -q '\.Main' "$TMP/log" && ! grep -q 'com.sdk.Hidden' "$TMP/log"; then
  ok "--manifest lists only exported components without permission (launcher skipped)"
else bad "--manifest -> exit $rc: $(cat "$TMP/log")"; fi

python3 "$SCAN" "$TMP/clean.apk" --manifest "$TMP/missing.xml" >"$TMP/log" 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "--manifest missing file -> exit 2" || bad "--manifest missing -> exit $rc, expected 2"

printf 'not a dex at all' > "$TMP/short.dex"
python3 "$SCAN" "$TMP/short.dex" >"$TMP/log" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'không đọc được header DEX' "$TMP/log" && ! grep -q Traceback "$TMP/log"; then ok "short / non-DEX file -> warned, no crash"
else bad "short dex -> exit $rc: $(cat "$TMP/log")"; fi

printf '<manifest><application><receiver' > "$TMP/broken.xml"
python3 "$SCAN" "$TMP/clean.apk" --manifest "$TMP/broken.xml" >"$TMP/log" 2>&1; rc=$?
[ "$rc" -eq 2 ] && ! grep -q Traceback "$TMP/log" && ok "--manifest broken XML -> exit 2" || bad "broken xml -> exit $rc: $(cat "$TMP/log")"

cat > "$TMP/prov.xml" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application>
  <provider android:name="com.sdk.ReadGuarded" android:exported="true" android:readPermission="com.x.R"/>
  <provider android:name="com.sdk.WriteGuarded" android:exported="true" android:writePermission="com.x.W"/>
  <provider android:name="com.sdk.OpenProvider" android:exported="true"/>
</application></manifest>
XML
python3 "$SCAN" "$TMP/clean.apk" --manifest "$TMP/prov.xml" >"$TMP/log" 2>&1; rc=$?
if grep -q 'com.sdk.OpenProvider' "$TMP/log" && ! grep -q 'Guarded' "$TMP/log"; then ok "provider read/writePermission counts as guarded"
else bad "provider permissions -> $(cat "$TMP/log")"; fi

python3 - "$TMP" <<'PY'
import struct, sys, zipfile
d = sys.argv[1]
h = bytearray(0x70); h[0:8] = b'dex\n035\x00'; struct.pack_into('<I', h, 0x58, 7)
with zipfile.ZipFile(f'{d}/feature.aab', 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('base/dex/classes.dex', bytes(h))
    z.writestr('feat/dex/classes2.dex', bytes(h) + b'Ljava/lang/reflect/Method;->setAccessible')
PY
python3 "$SCAN" "$TMP/feature.aab" >"$TMP/log" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'feat/dex/classes2.dex' "$TMP/log"; then ok "compressed .aab feature module dex scanned"
else bad "feature aab -> exit $rc: $(cat "$TMP/log")"; fi

# Real run 2026-11-18 on OfficeReader's app-debug.apk: 8 of 31 DEX files were flagged "near the cap" — d8 fills every DEX of a
# multidex app close to 65,536 on purpose. The 60,000 warning only means something while the app still has ONE DEX.
python3 - "$TMP" <<'PY'
import struct, sys, zipfile
d = sys.argv[1]
def dex(n):
    h = bytearray(0x70); h[0:8] = b'dex\n035\x00'; struct.pack_into('<I', h, 0x58, n); return bytes(h)
with zipfile.ZipFile(f'{d}/multi.apk', 'w') as z:
    z.writestr('classes.dex', dex(65400)); z.writestr('classes2.dex', dex(64000)); z.writestr('classes3.dex', dex(100))
PY
python3 "$SCAN" "$TMP/multi.apk" >"$TMP/log" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '⚠️' "$TMP/log" && grep -q '129500' "$TMP/log"; then ok "multidex near-full DEX files -> no warning, total printed"
else bad "multidex -> exit $rc: $(cat "$TMP/log")"; fi

# Same run: app widgets must be exported (the launcher sends APPWIDGET_UPDATE) — not a finding.
cat > "$TMP/widget.xml" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application>
  <receiver android:name="com.app.RecentWidget" android:exported="true"><intent-filter>
    <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter></receiver>
  <service android:name="com.sdk.AssetPackService" android:exported="true"/>
</application></manifest>
XML
python3 "$SCAN" "$TMP/clean.apk" --manifest "$TMP/widget.xml" >"$TMP/log" 2>&1
if ! grep -q 'RecentWidget' "$TMP/log" && grep -q 'com.sdk.AssetPackService' "$TMP/log"; then ok "app widget receiver skipped, SDK service still listed"
else bad "widget manifest -> $(cat "$TMP/log")"; fi

exit $((FAILS > 0))
