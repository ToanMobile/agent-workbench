#!/usr/bin/env bash
# #1258 hardening (review findings): the sealing entry must not run code or take config from the PR checkout, a colored diff must not
# void the per-hunk citation check, ocr seals are v2 (an old kit cannot read them as antigravity seals), and a reviewer label that is the
# author session (or a co-author of the PR) never approves.
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
seal "$(report)"; GOOD="$OUT"; [ "$RC" = 0 ] || ko "baseline seal rc=$RC $(cat "$TMP/err")"
# (1) P0: PR-controlled .gitconfig / .gitattributes (textconv) must not execute in the entry, agy path (diff runs before agy) and ocr path
git checkout -q --detach "$H" && printf '[diff "x"]\n\ttextconv = touch %s; cat\n[color]\n\tdiff = always\n' "$TMP/PWNED-agy" > .gitconfig && printf '* diff=x\n' > .gitattributes \
  && git add -A && git commit -qm "pwn" && PH="$(git rev-parse HEAD)"
printf '#!/bin/sh\nexit 1\n' > "$TMP/agy"; chmod +x "$TMP/agy"
SEAL_TEST_AGY="$TMP/agy" "$AUDIT" --repo "$TMP/repo" --head "$PH" >/dev/null 2>&1
[ ! -e "$TMP/PWNED-agy" ] && ok "P0: PR textconv does not run in the entry (agy path)" || ko "P0: PR textconv ran under the entry (agy path)"
sed -i.bak "s/PWNED-agy/PWNED-ocr/" .gitconfig; rm -f .gitconfig.bak; git commit -qam "pwn2"; PH="$(git rev-parse HEAD)"
printf '%s' "$(RH="$PH" report)" | "$AUDIT" --repo "$TMP/repo" --head "$PH" --ocr-report - --task T0001-x >/dev/null 2>&1
[ ! -e "$TMP/PWNED-ocr" ] && ok "P0: PR textconv does not run in the entry (ocr path)" || ko "P0: PR textconv ran (ocr path)"
# (2) P1: color.diff=always in the PR's .gitconfig must not make the hunk check vanish: a report with no citations stays refused
SH="$PH" refused "empty citations with color.diff=always in the PR" "$(RH="$PH" report 'citations=[]' 'findings=[]' 'files_reviewed=["tests/test_a.sh","tests/test_b.sh",".gitconfig"]')"
git checkout -q --detach "$H"
# (3) ocr seals are v2 and carry the reviewer label + report hash
f="$(printf '%s' "$GOOD" | python3 -c 'import json,sys; p=json.loads(json.load(sys.stdin)["payload"]); print(p["v"], p.get("reviewer_label"), len(p.get("report_sha256","")))')"
[ "$f" = "2 ocr-delegate-reviewer-7 64" ] && ok "ocr seal: v2, reviewer_label, report_sha256" || ko "ocr seal fields: $f"
resignv() {   # resignv '<json patch>': GOOD's payload patched and re-signed into seals/ocr-delegate/<H>.json
  python3 - "$GOOD" "$TMP/pm" "$H" "$DEVKIT_DIR/bin" "$1" <<'PY'
import base64, json, os, shutil, sys
sys.path.insert(0, sys.argv[4]); import verdict_seal as v
p = json.loads(json.loads(sys.argv[1])["payload"]); p.update(json.loads(sys.argv[5]))
ps = json.dumps(p, sort_keys=True, separators=(",", ":"))
shutil.rmtree(os.path.join(sys.argv[2], "seals"), ignore_errors=True)
d = os.path.join(sys.argv[2], "seals", "ocr-delegate"); os.makedirs(d)
json.dump({"payload": ps, "sig": base64.b64encode(v.sign(b"\x09" * 32, ps.encode())).decode()}, open(os.path.join(d, sys.argv[3] + ".json"), "w"))
PY
}
git commit -q --allow-empty -m "ocr trailer" -m "Test-approved-by: ocr-delegate T0001-x"; TR="$(git rev-parse HEAD)"
ah() { env ${XENV:-} python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(p.approval_head(sys.argv[2], "ocr-delegate", "T0001-x", sys.argv[3]))' "$DEVKIT_DIR/bin" "$TMP/repo" "$TR" 2>&1 | tail -1; }
resignv '{}'; [ "$(ah)" = "$H" ] && ok "v2 seal approves" || ko "v2 seal: $(ah)"
resignv '{"v":1}'; [ "$(ah)" = None ] && ok "v1-shaped ocr seal refused (downgrade)" || ko "v1 ocr seal accepted: $(ah)"
# (4) a reviewer label that is the author session never approves (seal made by a direct sudo call with a label of choice)
resignv '{"reviewer_label":"claude"}'; [ "$(XENV=CLAUDECODE=1 ah)" = None ] && ok "seal whose reviewer_label is the session agent -> refused" || ko "self label accepted"
resignv '{}'; [ "$(XENV=CLAUDECODE=1 ah)" = "$H" ] && ok "independent label accepted in a claude session" || ko "independent label refused: $(XENV=CLAUDECODE=1 ah)"
# (5) the same label as a Co-Authored-By of base..head is the author too
git commit -q --allow-empty -m "co" -m "Co-Authored-By: Reviewer-Seven <x@y>"; CH="$(git rev-parse HEAD)"
got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(sorted(p.author_names(sys.argv[2], sys.argv[3])))' "$DEVKIT_DIR/bin" "$TMP/repo" "$CH" 2>&1 | tail -1)"
[ "$got" = "['reviewer-seven']" ] && ok "author_names: Co-Authored-By names of base..head" || ko "author_names: $got"
# (6) review of the hardening: a label with control characters (log injection into ocr-signings.log) is refused; label vs author is compared
# by first word on both sides ("claude opus 5.5" vs a Claude co-author); an unreadable author list is no approval
refused "reviewer label with a newline (forged ocr-signings.log line)" "$(report 'reviewer="x\n2026-11-18T00:00:00Z\tuid=0\tsudo_user=a\thead=1\ttask=T0001-a"')"
git checkout -q --detach "$H" && git commit -q --allow-empty -m "co" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" && git commit -q --allow-empty -m "ocr trailer" -m "Test-approved-by: ocr-delegate T0001-x"; TR="$(git rev-parse HEAD)"
resignv '{"reviewer_label":"claude opus 5.5"}'; [ "$(ah)" = None ] && ok "label 'claude opus 5.5' vs co-author 'Claude Sonnet 5.5' -> refused (first word)" || ko "first-word label accepted: $(ah)"
resignv '{"reviewer_label":"council-reviewer"}'; [ "$(ah)" = "$H" ] && ok "unrelated label accepted next to a Claude co-author" || ko "unrelated label refused: $(ah)"
got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(p.author_names(sys.argv[2], "nonexistent-ref..HEAD"))' "$DEVKIT_DIR/bin" "$TMP/repo" 2>&1 | tail -1)"
[ "$got" = None ] && ok "author_names: git failure -> None (no silent empty set)" || ko "author_names on git failure: $got"
git checkout -q --detach "$H"
[ "$FAILS" -eq 0 ] && echo "ALL OK" || { echo "FAILS=$FAILS"; exit 1; }
