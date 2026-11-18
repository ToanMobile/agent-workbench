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
python3 - "$TMP" "$DEVKIT_DIR/tests/verification" <<'PY'
import struct, sys, zipfile
d = sys.argv[1]
sys.path.insert(0, sys.argv[2]); import dexbuild
def dex(methods, body=b''):
    h = bytearray(0x70); h[0:8] = b'dex\n035\x00'; struct.pack_into('<I', h, 0x58, methods)
    return bytes(h) + body
open(f'{d}/big.dex', 'wb').write(dex(61000))
with zipfile.ZipFile(f'{d}/app.aab', 'w') as z:
    z.writestr('base/dex/classes.dex', dexbuild.dex(fields=[('Landroid/os/Build;', 'SERIAL')]))
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

python3 - "$TMP" "$DEVKIT_DIR/tests/verification" <<'PY'
import struct, sys, zipfile
d = sys.argv[1]
sys.path.insert(0, sys.argv[2]); import dexbuild
h = bytearray(0x70); h[0:8] = b'dex\n035\x00'; struct.pack_into('<I', h, 0x58, 7)
with zipfile.ZipFile(f'{d}/feature.aab', 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('base/dex/classes.dex', bytes(h))
    z.writestr('feat/dex/classes2.dex', dexbuild.dex(methods=[('Ljava/lang/reflect/Method;', 'setAccessible')]))
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

# OCR review 2026-11-19 (3 findings).
python3 - "$TMP" <<'PY'
import struct, sys, zipfile
d = sys.argv[1]
def dex(n, body=b''):
    h = bytearray(0x70); h[0:8] = b'dex\n035\x00'; struct.pack_into('<I', h, 0x58, n); return bytes(h) + body
# a corrupt deflate stream behind an intact central directory
with zipfile.ZipFile(f'{d}/corrupt.apk', 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('classes.dex', dex(10, b'x' * 4000))
raw = bytearray(open(f'{d}/corrupt.apk', 'rb').read())
start = raw.index(b'classes.dex') + len('classes.dex')   # local header name; the deflate data follows (no extra field)
for i in range(start + 2, start + 8):                      # inside the ~30-byte stream, central directory untouched
    raw[i] ^= 0xFF
assert zipfile.is_zipfile(f'{d}/corrupt.apk') or True
open(f'{d}/corrupt.apk', 'wb').write(bytes(raw))
# an AAR holds classes.jar, never classes.dex
with zipfile.ZipFile(f'{d}/lib.aar', 'w') as z:
    z.writestr('classes.jar', b'PK'); z.writestr('AndroidManifest.xml', '<manifest/>')
# AAB: the base module still has ONE dex near the cap, a feature module has its own
with zipfile.ZipFile(f'{d}/split.aab', 'w') as z:
    z.writestr('base/dex/classes.dex', dex(61000)); z.writestr('feat/dex/classes.dex', dex(10))
PY
python3 "$SCAN" "$TMP/corrupt.apk" >"$TMP/log" 2>&1; rc=$?
[ "$rc" -eq 2 ] && ! grep -q Traceback "$TMP/log" && ok "corrupt deflate entry -> exit 2, no traceback" || bad "corrupt apk -> exit $rc: $(tail -3 "$TMP/log")"
python3 "$SCAN" "$TMP/lib.aar" >"$TMP/log" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q 'classes.jar' "$TMP/log" && ok ".aar -> exit 2 naming classes.jar (not a DEX archive)" || bad "aar -> exit $rc: $(cat "$TMP/log")"
python3 "$SCAN" "$TMP/split.aab" >"$TMP/log" 2>&1; rc=$?
grep -q '⚠️.*base/dex/classes.dex.*61000' "$TMP/log" && ok "AAB: single-DEX base module near the cap is warned per module" || bad "split aab -> $(cat "$TMP/log")"

# principal review 2026-11-19, confirmed on OfficeReader's real APK (0 of 32 DEX hold a joined `Lcls;->name`, 13 hold
# `setAccessible`): the dangerous-API check grepped for smali text a DEX never stores, so it could never fire. The scan must
# resolve method_ids / field_ids. dexbuild.py writes structurally valid DEX tables (no joined string anywhere).
python3 - "$TMP" "$DEVKIT_DIR/tests/verification" <<'PY'
import sys, zipfile
sys.path.insert(0, sys.argv[2]); from dexbuild import dex
d = sys.argv[1]
with zipfile.ZipFile(f'{d}/refl.apk', 'w') as z:
    z.writestr('classes.dex', dex(methods=[('Ljava/lang/reflect/Method;', 'setAccessible'), ('Lcom/app/A;', 'run')]))
with zipfile.ZipFile(f'{d}/serial.apk', 'w') as z:
    z.writestr('classes.dex', dex(fields=[('Landroid/os/Build;', 'SERIAL')]))
# both pieces present, but never as one reference: Method;->invoke + Field;->setAccessible is not Method;->setAccessible
with zipfile.ZipFile(f'{d}/near.apk', 'w') as z:
    z.writestr('classes.dex', dex(methods=[('Ljava/lang/reflect/Method;', 'invoke'), ('Lcom/x/Y;', 'setAccessible')]))
PY
python3 "$SCAN" "$TMP/refl.apk" >"$TMP/log" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q 'setAccessible' "$TMP/log" && ok "real DEX method ref Method;->setAccessible -> exit 1" || bad "method ref -> exit $rc: $(tail -3 "$TMP/log")"
python3 "$SCAN" "$TMP/serial.apk" >"$TMP/log" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q 'Build.SERIAL' "$TMP/log" && ok "real DEX field ref Build;->SERIAL -> exit 1" || bad "field ref -> exit $rc: $(tail -3 "$TMP/log")"
python3 "$SCAN" "$TMP/near.apk" >"$TMP/log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "class and name present but not one reference -> clean" || bad "near miss -> exit $rc: $(tail -3 "$TMP/log")"

exit $((FAILS > 0))
