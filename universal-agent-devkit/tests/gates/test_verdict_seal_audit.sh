#!/usr/bin/env bash
# #632 B: libexec/verdict-seal-audit builds what it signs itself. With a fake agy and a fake signer (test key):
# - pass: the payload has base = merge-base(origin/main, head) and edited computed from the clone, verify() accepts it;
# - extra arguments (--base) are refused, so the caller cannot choose base;
# - agy output that is not {verdict, findings} JSON gives exit != 0 and nothing on stdout (nothing signed);
# - H may be a detached commit on no ref (fetched by sha); agy envelope is steps.JSONOutput (structured_output);
# - agy runs inside a clone that has git history (git log works) and the .seal/ diff files.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIT="$DEVKIT_DIR/libexec/verdict-seal-audit"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
FAILS=0
ok() { echo "✔ $1"; }
ko() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
git init -q --bare -b main "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/repo" 2>/dev/null; cd "$TMP/repo" || exit 1
git config user.email t@t && git config user.name t && git config commit.gpgsign false
mkdir tests && echo 'assert 1' > tests/test_a.sh && git add . && git commit -qm c1 && git push -q origin main
BASE="$(git rev-parse HEAD)"
git checkout -q --detach && echo 'assert 2' > tests/test_a.sh && echo new > added && git add . && git commit -qm change
HEAD_SHA="$(git rev-parse HEAD)"
cat > "$TMP/agy" <<SH
#!/bin/bash
git log --oneline >/dev/null 2>&1 || { echo nohistory; exit 0; }
[ -f .seal/diff.patch ] && [ -f .seal/name-status.txt ] || { echo nodiff; exit 0; }
cat "$TMP/agy.out"
SH
cat > "$TMP/signer" <<SH
#!/bin/bash
exec python3 -c 'import base64,sys; sys.path.insert(0,"$DEVKIT_DIR/bin"); import verdict_seal as v; print(base64.b64encode(v.sign(b"\x09"*32, sys.stdin.buffer.read())).decode())'
SH
chmod +x "$TMP/agy" "$TMP/signer"
export SEAL_TEST_AGY="$TMP/agy" SEAL_TEST_SIGNER="$TMP/signer"
python3 -c 'import base64,sys; sys.path.insert(0,sys.argv[1]); import verdict_seal as v; open(sys.argv[2],"w").write(base64.b64encode(v.public_key(b"\x09"*32)).decode())' \
  "$DEVKIT_DIR/bin" "$TMP/seal.pub"

echo '{"conversation_id":"c","status":"SUCCESS","response":"ok","structured_output":{"verdict":"pass","findings":[]}}' > "$TMP/agy.out"
if out="$("$AUDIT" --repo "$TMP/repo" --head "$HEAD_SHA" 2>"$TMP/err")"; then
  mkdir -p "$TMP/pm/seals" && printf '%s' "$out" > "$TMP/pm/seals/$HEAD_SHA.json"
  DEVKIT_VERDICT_SEAL_PUB="$TMP/seal.pub" python3 - "$DEVKIT_DIR/bin" "$TMP/repo" "$HEAD_SHA" "$BASE" <<'PY' && ok "pass sealed with own base/edited" || ko "pass sealed with own base/edited"
import sys; sys.path.insert(0, sys.argv[1]); import verdict_seal as v
p = v.sealed_pass(sys.argv[2], sys.argv[3], test_fixture=True)
print(p)
sys.exit(0 if p and p["base"] == sys.argv[4] and p["edited"] == ["tests/test_a.sh"] else 1)
PY
else ko "pass run failed: $(cat "$TMP/err")"; fi

"$AUDIT" --repo "$TMP/repo" --head "$HEAD_SHA" --base "$HEAD_SHA" >/dev/null 2>&1 && ko "--base accepted" || ok "--base refused"

for bad in 'not json' '{"verdict":"maybe","findings":[]}' '{"verdict":"pass"}' '{"status":"FAILED","structured_output":{"verdict":"pass","findings":[]}}' '{"status":"SUCCESS","denied_actions":["read_file"],"structured_output":{"verdict":"pass","findings":[]}}'; do
  printf '%s' "$bad" > "$TMP/agy.out"
  out="$("$AUDIT" --repo "$TMP/repo" --head "$HEAD_SHA" 2>/dev/null)"; rc=$?
  [ "$rc" -ne 0 ] && [ -z "$out" ] && ok "malformed agy output not signed: $bad" || ko "malformed agy output signed: $bad (rc=$rc)"
done
printf '%s' '{"status":"SUCCESS","structured_output":{"verdict":"fail","findings":["x"]}}' > "$TMP/agy.out"
out="$("$AUDIT" --repo "$TMP/repo" --head "$HEAD_SHA" 2>/dev/null)" && printf '%s' "$out" | grep -q '\\"verdict\\":\\"fail\\"' \
  && ok "wrapped fail verdict signed as fail" || ko "wrapped fail verdict"
[ "$FAILS" -eq 0 ] && echo "ALL OK" || { echo "FAILS=$FAILS"; exit 1; }
