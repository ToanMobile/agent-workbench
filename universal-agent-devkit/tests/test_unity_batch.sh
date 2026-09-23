#!/usr/bin/env bash
# Regression test: profiles/game/scripts/unity-batch.sh keeps the Editor's PlayerPrefs.
#
# On macOS the Unity Editor keeps PlayerPrefs in the defaults domain
# unity.<companyName>.<productName>, which is the developer's play state. Tests and
# -executeMethod runs write real keys there, so a Stop-time regression run changed it.
# unity-batch.sh snapshots that domain before the Editor starts and gives it back on
# exit. It never reads or writes the player build's com.* domain.
#
# No Unity and no real `defaults`. The test uses a fake Editor (UNITY_PATH) and fake
# `defaults` / `plutil` / `uname` first on PATH, which keep each domain as a JSON file.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BATCH="$DEVKIT_DIR/profiles/game/scripts/unity-batch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

BIN="$TMP/bin"; PREFS="$TMP/prefs"
mkdir -p "$BIN" "$PREFS"
DOMAIN="unity.DevKitTest.PrefsProbe"
PLAYER="com.DevKitTest.PrefsProbe"

# ---------- fake defaults: one JSON file per domain; every call is logged ----------
cat > "$BIN/defaults" <<'SH'
#!/usr/bin/env bash
echo "defaults $*" >> "$FAKE_PREFS/calls.log"
exec python3 - "$FAKE_PREFS" "$@" <<'PY'
import json, os, shutil, sys
store, cmd, dom, *rest = sys.argv[1], sys.argv[2], sys.argv[3], *sys.argv[4:]
f = os.path.join(store, dom + ".json")
def load(): return json.load(open(f))
def save(d): json.dump(d, open(f, "w"), sort_keys=True)
if cmd == "read":
    if not os.path.exists(f): sys.exit(1)
    d = load()
    if rest:
        if rest[0] not in d: sys.exit(1)
        print(d[rest[0]])
    else:
        print(json.dumps(d))
elif cmd == "export":
    if os.environ.get("FAKE_EXPORT_FAIL") == "1": sys.exit(1)
    shutil.copyfile(f, rest[0]) if os.path.exists(f) else open(rest[0], "w").write("{}")
elif cmd == "import":
    d = load() if os.path.exists(f) else {}
    d.update(json.load(open(rest[0])))   # real `defaults import` merges keys
    save(d)
elif cmd == "delete":
    if not os.path.exists(f): sys.exit(1)
    if rest:
        d = load(); d.pop(rest[0], None); save(d)
    else:
        os.remove(f)
elif cmd == "write":
    d = load() if os.path.exists(f) else {}
    key, *val = rest
    d[key] = val[-1]
    save(d)
else:
    sys.exit(2)
PY
SH
cat > "$BIN/plutil" <<'SH'
#!/usr/bin/env bash
f="${@: -1}"; python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null
SH
cat > "$BIN/uname" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "-s" ]; then echo "${FAKE_UNAME:-Darwin}"; else /usr/bin/uname "$@"; fi
SH
# ---------- fake Unity: writes prefs keys, the log and an NUnit result ----------
cat > "$BIN/Unity" <<'SH'
#!/usr/bin/env bash
log="" xml=""
while [ $# -gt 0 ]; do
  case "$1" in -logFile) log="$2"; shift ;; -testResults) xml="$2"; shift ;; esac; shift
done
echo "fake unity" > "$log"
defaults write "$FAKE_DOMAIN" COZY_PLAYER_COINS -int 999
defaults write "$FAKE_DOMAIN" RUN_ONLY_KEY -int 1
defaults delete "$FAKE_DOMAIN" COZY_LOCALE
[ -n "${FAKE_SLEEP:-}" ] && { : > "$FAKE_PREFS/unity.started"; sleep "$FAKE_SLEEP"; }
if [ -n "$xml" ]; then
  r=Passed; [ "${FAKE_TEST:-pass}" = fail ] && r=Failed
  printf '<test-run><test-case fullname="Probe.Case" result="%s"><failure><message>x</message></failure></test-case></test-run>\n' "$r" > "$xml"
fi
exit "${FAKE_RC:-0}"
SH
chmod +x "$BIN"/*

PROJ="$TMP/proj"
mkdir -p "$PROJ/Assets" "$PROJ/ProjectSettings"
printf 'm_EditorVersion: 6000.0.1f1\n' > "$PROJ/ProjectSettings/ProjectVersion.txt"
printf 'PlayerSettings:\n  companyName: DevKitTest\n  productName: PrefsProbe\n' > "$PROJ/ProjectSettings/ProjectSettings.asset"

seed() {  # a known Editor domain and a player domain
  rm -f "$PREFS"/*.json "$PREFS/calls.log" "$PREFS/unity.started"
  printf '{"COZY_LOCALE": "1", "COZY_PLAYER_COINS": "550"}' > "$PREFS/$DOMAIN.json"
  printf '{"CURRENT_LEVEL": "6"}' > "$PREFS/$PLAYER.json"
}
run() {  # run <mode> [env…] → sets RC
  local mode="$1"; shift
  env PATH="$BIN:$PATH" FAKE_PREFS="$PREFS" FAKE_DOMAIN="$DOMAIN" UNITY_PATH="$BIN/Unity" \
      UNITY_PROJECT="$PROJ" UNITY_BATCH_OUT="$TMP/out" "$@" bash "$BATCH" "$mode" >"$TMP/run.out" 2>&1
  RC=$?
}
same_domain() { cmp -s "$PREFS/$DOMAIN.json" "$TMP/before.json"; }

# 1+2+3. PASS run: exit 0, Editor domain restored byte for byte, com.* untouched.
seed; cp "$PREFS/$DOMAIN.json" "$TMP/before.json"; cp "$PREFS/$PLAYER.json" "$TMP/player.json"
run editmode
[ "$RC" -eq 0 ] && ok "passing run exits 0" || fail "passing run exits 0 (got $RC): $(tail -3 "$TMP/run.out")"
same_domain && ok "Editor prefs restored after a run that wrote keys" \
  || fail "Editor prefs restored after a run that wrote keys: $(cat "$PREFS/$DOMAIN.json")"
if cmp -s "$PREFS/$PLAYER.json" "$TMP/player.json" && ! grep -q "$PLAYER" "$PREFS/calls.log"; then
  ok "player build domain ($PLAYER) never read or written"
else fail "player build domain ($PLAYER) never read or written"; fi

# 1. FAIL run: exit 1 passes through, prefs still restored.
seed; cp "$PREFS/$DOMAIN.json" "$TMP/before.json"
run playmode FAKE_TEST=fail
[ "$RC" -eq 1 ] && ok "failing test exits 1" || fail "failing test exits 1 (got $RC)"
same_domain && ok "prefs restored after a failing run" || fail "prefs restored after a failing run"

# 1. UNTESTED: no Editor → exit 2, prefs never touched.
seed
run editmode UNITY_PATH="$TMP/no-such-unity"
[ "$RC" -eq 2 ] && ok "no Editor exits 2 (UNTESTED)" || fail "no Editor exits 2 (got $RC)"

# 4. Domain absent before the run → absent after it.
seed; rm -f "$PREFS/$DOMAIN.json"
run editmode
[ ! -e "$PREFS/$DOMAIN.json" ] && ok "domain created by the run is removed again" \
  || fail "domain created by the run is removed again: $(cat "$PREFS/$DOMAIN.json")"

# 5. SIGTERM while the Editor runs → prefs restored anyway.
seed; cp "$PREFS/$DOMAIN.json" "$TMP/before.json"
env PATH="$BIN:$PATH" FAKE_PREFS="$PREFS" FAKE_DOMAIN="$DOMAIN" UNITY_PATH="$BIN/Unity" FAKE_SLEEP=30 \
    UNITY_PROJECT="$PROJ" UNITY_BATCH_OUT="$TMP/out" bash "$BATCH" editmode >"$TMP/run.out" 2>&1 &
BG=$!
for _ in $(seq 1 50); do [ -e "$PREFS/unity.started" ] && break; sleep 0.2; done
kill -TERM "$BG" 2>/dev/null
wait "$BG"; RC=$?
same_domain && ok "prefs restored when the run is terminated (rc $RC)" || fail "prefs restored when the run is terminated (rc $RC)"
pkill -f "$BIN/Unity" 2>/dev/null

# 6. UNITY_KEEP_PREFS=1 → the run's writes are kept and nothing is snapshotted.
seed
run editmode UNITY_KEEP_PREFS=1
if grep -q '"RUN_ONLY_KEY"' "$PREFS/$DOMAIN.json" && ! grep -q '^defaults export' "$PREFS/calls.log"; then
  ok "UNITY_KEEP_PREFS=1 skips snapshot and restore"
else fail "UNITY_KEEP_PREFS=1 skips snapshot and restore"; fi

# 7. Not macOS → no-op, exit code unchanged.
seed
run editmode FAKE_UNAME=Linux
if [ "$RC" -eq 0 ] && ! grep -q '^defaults export\|^defaults import' "$PREFS/calls.log"; then
  ok "non-macOS: no prefs handling, exit 0"
else fail "non-macOS: no prefs handling, exit 0 (rc $RC)"; fi

# 8. Snapshot export fails → never delete the domain afterwards.
seed
run editmode FAKE_EXPORT_FAIL=1
if [ -e "$PREFS/$DOMAIN.json" ] && ! grep -q "^defaults delete $DOMAIN\$" "$PREFS/calls.log"; then
  ok "failed snapshot: domain is not deleted"
else fail "failed snapshot: domain is not deleted"; fi

echo
if [ "$FAILS" -eq 0 ]; then echo "unity batch: all checks passed"; exit 0; fi
echo "unity batch: $FAILS check(s) FAILED"; exit 1
