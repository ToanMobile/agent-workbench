#!/usr/bin/env bash
# #1258: an OpenCodeReview delegation-mode review (a reviewer agent that read the diff; ocr stores no session) is a second cross-reviewer
# next to Antigravity. Its report is machine-verified by libexec/verdict-seal-audit (--ocr-report - --task T; test signer + ledger as in
# test_verdict_seal_audit.sh) and sealed as reviewer ocr-delegate; push_gate.approved accepts `Test-approved-by: ocr-delegate <task-id>`
# only for a valid seal in seals/ocr-delegate/ whose signed base == merge-base(trunk, head). Every other case: refused, fail closed.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIT="$DEVKIT_DIR/libexec/verdict-seal-audit"
case "${TMPDIR:-}" in ""|/tmp|/tmp/*|/private/tmp|/private/tmp/*) TMPDIR="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)";; esac
[ -n "$TMPDIR" ] || TMPDIR=/tmp
export TMPDIR="${TMPDIR%/}"
TMP="$(mktemp -d "$TMPDIR/ocr-delegate.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm" DEVKIT_PM_HOME_TEST=1   # test-only switch: fixture repo + pm home + test pubkey under $TMP
unset DEVKIT_OCR_CROSS_REVIEW DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID CLAUDECODE
FAILS=0
ok() { echo "✔ $1"; }
ko() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
git init -q --bare -b main "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/repo" 2>/dev/null; cd "$TMP/repo" || exit 1
git config user.email t@t && git config user.name t && git config commit.gpgsign false
mkdir -p tests && printf 'assert first == 1\nassert second == 2\n' > tests/test_a.sh && printf 'assert alpha == 1\nassert beta == 2\nassert gamma == 3\n' > tests/test_b.sh && echo o > other.txt && git add . && git commit -qm c1 && git push -q origin main
git checkout -q --detach && printf 'assert first == 1\nassert second == 2 or True\n' > tests/test_a.sh && printf 'assert alpha == 1\nassert beta == 2\n' > tests/test_b.sh && git commit -qam "edit test"
H="$(git rev-parse HEAD)"; BASE="$(git rev-parse origin/main)"
cat > "$TMP/signer" <<SH
#!/bin/bash
exec python3 -c 'import base64,sys; sys.path.insert(0,"$DEVKIT_DIR/bin"); import verdict_seal as v; print(base64.b64encode(v.sign(b"\x09"*32, sys.stdin.buffer.read())).decode())'
SH
chmod +x "$TMP/signer"
export SEAL_TEST_SIGNER="$TMP/signer" SEAL_TEST_LEDGER="$TMP/ledger"
python3 -c 'import base64,sys; sys.path.insert(0,sys.argv[1]); import verdict_seal as v; open(sys.argv[2],"w").write(base64.b64encode(v.public_key(b"\x09"*32)).decode())' \
  "$DEVKIT_DIR/bin" "$TMP/seal.pub"
export DEVKIT_VERDICT_SEAL_PUB="$TMP/seal.pub"
report() {   # report [key=json-value ...]: the fixture report (real schema), overridden per case
  python3 - "${RH:-$H}" "$@" <<'PY'
import json, sys, time
r = {"auditedHead": sys.argv[1], "verdict": "pass", "reviewer": "ocr-delegate-reviewer-7", "files_reviewed": ["tests/test_a.sh", "tests/test_b.sh"],
     "reviewed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 120)),
     "citations": [{"file": "tests/test_a.sh", "line": 2, "snippet": "assert second == 2 or True"},
                  {"file": "tests/test_a.sh", "line": 2, "side": "base", "snippet": "assert second == 2"},
                  {"file": "tests/test_b.sh", "line": 3, "side": "base", "snippet": "assert gamma == 3"}],
     "findings": [{"severity": "minor", "file": "tests/test_a.sh", "line": 1, "snippet": "assert first == 1", "note": "ok"}]}
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1)
    r[k] = json.loads(v)
print(json.dumps(r))
PY
}
seal() { OUT="$(printf '%s' "$1" | "$AUDIT" --repo "$TMP/repo" --head "${SH:-$H}" --ocr-report - --task "${2:-T0001-x}" 2>"$TMP/err")"; RC=$?; }
refused() {   # refused <name> <report> [task]: rc != 0 and nothing signed
  seal "$2" "${3:-}"; [ "$RC" -ne 0 ] && [ -z "$OUT" ] && grep -q "ocr-delegate report refused" "$TMP/err" && ok "refused: $1" || ko "$1: rc=$RC out=${OUT:0:80}"
}

seal "$(report)"
if [ "$RC" = 0 ]; then
  f="$(printf '%s' "$OUT" | python3 -c 'import json,sys; p=json.loads(json.load(sys.stdin)["payload"]); print(p["reviewer"], p["task_id"], p["base"], p["edited"], p["verdict"])')"
  [ "$f" = "ocr-delegate T0001-x $BASE ['tests/test_a.sh', 'tests/test_b.sh'] pass" ] && ok "accept: report sealed (reviewer ocr-delegate, own base/edited)" || ko "payload: $f"
else ko "accept failed rc=$RC: $(cat "$TMP/err")"; fi
GOOD="$OUT"
[ -z "$(ls "$TMP/ledger" 2>/dev/null | grep -v '^ocr-signings.log$')" ] && ok "ocr signing leaves the agy ledger and attempt counters alone" || ko "ocr touched the agy ledger: $(ls "$TMP/ledger")"
grep -q "$H" "$TMP/ledger/ocr-signings.log" && ok "each ocr signing is logged (uid, SUDO_USER, head, task)" || ko "no signing log"
for i in 1 2 3 4; do seal "$(report)"; [ "$RC" = 0 ] && [ "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.loads(json.load(sys.stdin)["payload"])["attempts"])')" = 1 ] || ko "signing $i rc=$RC"; done
ok "4 consecutive ocr signings of one content all sign (attempts stay 1)"
refused "head mismatch" "$(report auditedHead="\"$BASE\"")"
B3='{"file":"tests/test_a.sh","line":2,"side":"base","snippet":"assert second == 2"},{"file":"tests/test_b.sh","line":3,"side":"base","snippet":"assert gamma == 3"}'
refused "snippet not at that line" "$(report 'citations=[{"file":"tests/test_a.sh","line":1,"snippet":"assert second == 2 or True"},'"$B3"']')"
refused "snippet invented" "$(report 'citations=[{"file":"tests/test_a.sh","line":2,"snippet":"assert second == 3 or True"}]')"
refused "citation of an unchanged line 1 only proves nothing" "$(report 'citations=[{"file":"tests/test_a.sh","line":1,"snippet":"assert first == 1"},'"$B3"']')"
refused "deleted lines without a base-side citation" "$(report 'citations=[{"file":"tests/test_a.sh","line":2,"snippet":"assert second == 2 or True"}]')"
refused "trivial snippet" "$(report 'citations=[{"file":"tests/test_a.sh","line":2,"snippet":"or True"},'"$B3"']')"
refused "reviewed_at far in the future" "$(report reviewed_at='"2999-01-01T00:00:00Z"')"
seal "$(report)" "../x"; [ "$RC" -ne 0 ] && [ -z "$OUT" ] && ok "refused: task id of the wrong shape" || ko "bad task id rc=$RC"
refused "line past end of file" "$(report 'citations=[{"file":"tests/test_a.sh","line":99,"snippet":"assert second == 2 or True"}]')"
refused "edited test not covered by files_reviewed" "$(report 'files_reviewed=["other.txt"]')"
refused "edited test never cited" "$(report 'citations=[]' 'findings=[]')"
refused "blocker finding" "$(report 'findings=[{"severity":"blocker","file":"tests/test_a.sh","line":1,"snippet":"assert first == 1","note":"x"}]')"
refused "major finding" "$(report 'findings=[{"severity":"major","file":"tests/test_a.sh","line":1,"snippet":"assert first == 1","note":"x"}]')"
refused "finding without valid severity" "$(report 'findings=[{"severity":"fatal","file":"tests/test_a.sh","line":1,"snippet":"assert first == 1"}]')"
refused "verdict fail" "$(report verdict='"fail"')"
refused "stale report (before the head commit)" "$(report reviewed_at='"2001-01-01T00:00:00Z"')"
refused "no reviewer" "$(report reviewer='""')"
refused "not JSON" "garbage"
OUT="$(printf '%s' "$(report)" | DEVKIT_OCR_CROSS_REVIEW=0 "$AUDIT" --repo "$TMP/repo" --head "$H" --ocr-report - --task T0001-x 2>/dev/null)"; RC=$?
[ "$RC" -ne 0 ] && [ -z "$OUT" ] && ok "refused: kill switch DEVKIT_OCR_CROSS_REVIEW=0 in the sealing entry" || ko "kill switch (entry) rc=$RC"

# gate side: trailer commit on top of the sealed head, through push_gate.approved (push gate / post-fix-gate trailer path)
git commit -q --allow-empty -m "ocr trailer" -m "Test-approved-by: ocr-delegate T0001-x"; TR="$(git rev-parse HEAD)"
appr() { env ${XENV:-} python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(p.approved(sys.argv[2], sys.argv[3]))' "$DEVKIT_DIR/bin" "$TMP/repo" "${1:-$TR^!}" 2>&1 | tail -1; }
want() {   # want <name> <True|False> [trailer rng]
  got="$(appr "${3:-}")"; case "$got" in "($2,"*) ok "approved(): $1";; *) ko "approved() $1: $got";; esac
}
seal_to() { mkdir -p "$TMP/pm/seals/$1"; printf '%s' "$GOOD" > "$TMP/pm/seals/$1/$H.json"; }
rm -rf "$TMP/pm/seals"; want "no seal -> refused" False
seal_to ocr-delegate; want "sealed ocr-delegate trailer accepted" True
XENV="DEVKIT_OCR_CROSS_REVIEW=0" want "kill switch -> refused" False
XENV="-u DEVKIT_VERDICT_SEAL_PUB" want "seal mode off (no trusted key) -> refused" False
python3 - "$TMP/pm/seals/ocr-delegate/$H.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); p = json.loads(s["payload"]); p["edited"] = []; s["payload"] = json.dumps(p, sort_keys=True, separators=(",", ":"))
json.dump(s, open(sys.argv[1], "w"))
PY
want "hand-edited seal payload -> refused" False
rm -rf "$TMP/pm/seals"; seal_to ""; want "same seal in the antigravity dir does not count for ocr-delegate" False
rm -rf "$TMP/pm/seals"; seal_to ocr-delegate
git commit -q --allow-empty -m "other task" -m "Test-approved-by: ocr-delegate T0002-y"; want "trailer for another task id -> refused" False "HEAD^!"
# kind: copy in both directions through a re-signed payload (test key): ocr seal in the antigravity dir; agy-shaped seal in the ocr dir
resign() {   # resign <subdir> [keys to drop]: re-sign GOOD's payload with the test key into seals/<subdir>/<H>.json
  python3 - "$GOOD" "$TMP/pm" "$H" "$DEVKIT_DIR/bin" "$@" <<'PY'
import base64, json, os, shutil, sys
sys.path.insert(0, sys.argv[4]); import verdict_seal as v
good, pm, head, sub, drop = json.loads(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[5], sys.argv[6:]
p = json.loads(good["payload"])
for k in drop: p.pop(k)
ps = json.dumps(p, sort_keys=True, separators=(",", ":"))
shutil.rmtree(os.path.join(pm, "seals"), ignore_errors=True)
d = os.path.join(pm, "seals", sub); os.makedirs(d)
json.dump({"payload": ps, "sig": base64.b64encode(v.sign(b"\x09" * 32, ps.encode())).decode()}, open(os.path.join(d, head + ".json"), "w"))
PY
}
resign "" ; python3 -c 'import sys; sys.path.insert(0,sys.argv[1]); import verdict_seal as v; sys.exit(1 if v.sealed_pass(sys.argv[2], sys.argv[3], test_fixture=True) else 0)' \
  "$DEVKIT_DIR/bin" "$TMP/repo" "$H" && ok "ocr seal copied to the antigravity dir is not an antigravity pass" || ko "ocr seal accepted as antigravity pass"
resign ocr-delegate kind reviewer task_id; want "agy-shaped seal copied to the ocr dir -> refused" False "$TR^!"
# two valid seals under one task id (same tree, other head): the trailer still approves the one matching its tree
rm -rf "$TMP/pm/seals"; seal_to ocr-delegate
H2="$(GIT_COMMITTER_DATE="@$(( $(date +%s) + 30 )) +0000" git commit-tree "$H^{tree}" -p "$H^" -m "edit test again")"
RH="$H2" SH="$H2" seal "$(RH="$H2" report)"; [ "$RC" = 0 ] && { mkdir -p "$TMP/pm/seals/ocr-delegate"; printf '%s' "$OUT" > "$TMP/pm/seals/ocr-delegate/$H2.json"; } || ko "second seal rc=$RC $(cat "$TMP/err")"
want "two valid seals under one task id: the one matching the tree approves" True "$TR^!"
# the ocr seal never stands in for an antigravity seal, so it cannot validate a PM record
python3 -c 'import sys; sys.path.insert(0,sys.argv[1]); import verdict_seal as v; sys.exit(1 if v.sealed_pass(sys.argv[2], sys.argv[3], test_fixture=True) else 0)' \
  "$DEVKIT_DIR/bin" "$TMP/repo" "$H" && ok "ocr-delegate seal is not an antigravity pass seal (sealed_pass)" || ko "sealed_pass accepted the ocr seal"
# Antigravity path unchanged: a trailer naming antigravity with no PM record is refused exactly as before
git commit -q --allow-empty -m "agy" -m "Test-approved-by: antigravity T0003-z"; want "antigravity trailer without PM record refused as before" False "HEAD^!"
# author sealing its own PR: reviewer label equal to the session identity is refused before anything is sealed
printf '%s' "$(report reviewer='"claude"')" > "$TMP/self.json"; printf '%s' "$(report)" > "$TMP/ok.json"
APPROVE="$DEVKIT_DIR/scripts/governance/approve_tests.py"
CLAUDECODE=1 python3 "$APPROVE" --ocr-delegate "$TMP/self.json" T0001-x >/dev/null 2>"$TMP/err"; RC=$?
[ "$RC" = 2 ] && grep -q "tự duyệt" "$TMP/err" && ok "author self-seal refused (reviewer label == session identity)" || ko "self-seal rc=$RC $(cat "$TMP/err")"
CLAUDECODE=1 DEVKIT_OCR_CROSS_REVIEW=0 python3 "$APPROVE" --ocr-delegate "$TMP/ok.json" T0001-x >/dev/null 2>"$TMP/err"; RC=$?
[ "$RC" = 2 ] && ok "approve-tests --ocr-delegate: kill switch refuses" || ko "kill switch (approve-tests) rc=$RC"
CLAUDECODE=1 python3 "$APPROVE" --ocr-delegate "$TMP/ok.json" T0001-x >/dev/null 2>"$TMP/err"; RC=$?
[ "$RC" = 3 ] && grep -q "not installed" "$TMP/err" && ok "independent reviewer reaches the sealing entry (not installed here: rc 3)" || ko "reach entry rc=$RC $(cat "$TMP/err")"
[ "$FAILS" -eq 0 ] && echo "ALL OK" || { echo "FAILS=$FAILS"; exit 1; }
