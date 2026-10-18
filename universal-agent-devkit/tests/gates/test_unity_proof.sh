#!/usr/bin/env bash
# bin/unity-proof.sh: headless Unity proof. Batchmode WITHOUT -nographics (the render needs the GPU),
# copies the PNG the Editor method wrote into {{out}}, removes it from the project, kills a hung Unity.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CMD="$DEVKIT_DIR/bin/unity-proof.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Fake Unity: records argv, writes SHOT only for method Ok.Method, hangs for Hang.Method.
FAKE="$TMP/FakeUnity"
cat > "$FAKE" <<'SH'
#!/bin/sh
echo "$@" >> "$FAKE_ARGS"
proj=""; method=""
while [ $# -gt 0 ]; do
  case "$1" in -projectPath) proj="$2"; shift;; -executeMethod) method="$2"; shift;; esac
  shift
done
case "$method" in
  Ok.Method) mkdir -p "$proj/Temp"; head -c 20000 /dev/urandom > "$proj/Temp/shot.png"; exit 0;;
  Hang.Method) exec sleep 30;;
  *) exit 0;;
esac
SH
chmod +x "$FAKE"
export FAKE_ARGS="$TMP/args"
P="$TMP/proj"; mkdir -p "$P/Temp"; : > "$P/Temp/UnityLockfile"   # stale lockfile, no Unity running on $P

out="$TMP/out/proof.png"
UNITY="$FAKE" bash "$CMD" --project "$P" --method Ok.Method --shot Temp/shot.png --out "$out" >"$TMP/log" 2>&1; rc=$?
[ "$rc" = 0 ] && [ -s "$out" ] && [ "$(wc -c <"$out")" -gt 8192 ] \
  && ok "success: PNG copied to --out (stale lockfile does not block)" || fail "success: rc=$rc $(cat "$TMP/log")"
[ ! -e "$P/Temp/shot.png" ] && ok "shot removed from the project" || fail "shot left in project"
grep -q -- "-batchmode" "$FAKE_ARGS" && ! grep -q -- "-nographics" "$FAKE_ARGS" \
  && grep -q -- "-executeMethod Ok.Method" "$FAKE_ARGS" \
  && ok "batchmode without -nographics" || fail "args: $(cat "$FAKE_ARGS")"

rm -f "$out"
UNITY="$FAKE" bash "$CMD" --project "$P" --method None.Method --shot Temp/shot.png --out "$out" >"$TMP/log" 2>&1; rc=$?
[ "$rc" != 0 ] && [ ! -e "$out" ] && ok "no PNG written -> fails, no --out" || fail "no-png: rc=$rc"

SECONDS=0
UNITY="$FAKE" bash "$CMD" --project "$P" --method Hang.Method --shot Temp/shot.png --out "$out" --timeout 2 >"$TMP/log" 2>&1; rc=$?
[ "$rc" = 124 ] && [ "$SECONDS" -lt 15 ] && ok "hung Unity is killed at the timeout (rc 124)" || fail "timeout: rc=$rc secs=$SECONDS"

UNITY="$TMP/nope" bash "$CMD" --project "$P" --method Ok.Method --shot Temp/shot.png --out "$out" >"$TMP/log" 2>&1; rc=$?
[ "$rc" = 2 ] && ok "missing Unity binary -> exit 2" || fail "no unity: rc=$rc"

[ "$FAILS" = 0 ] && echo "ALL PASS" && exit 0
exit 1
