#!/usr/bin/env bash
# bin/review-fanout.sh end to end with stub reviewers (no LLM, no network): the 3 run in parallel, a reviewer that times out,
# fails or is unavailable makes the whole review FAIL (no delegate fallback for OCR), a known-bug pattern on an added line is a
# P0 recurring bug, an accepted P1 becomes an OPEN REV-<id> row of the regression checklist, results are cached by code hash,
# and every run lands in .claude/audit-gate/review_outcomes.jsonl.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
STUB="$TMP/stub"; mkdir -p "$STUB"
# ocr stub: mode file decides (ok | noendpoint | high)
cat > "$STUB/ocr" <<'SH'
#!/usr/bin/env bash
mode="$(cat "$STUB_DIR/ocr.mode" 2>/dev/null || echo ok)"; sleep "${STUB_SLEEP:-0}"
[ "$1" = review ] || { echo '{"reviewable_files":[]}'; exit 0; }
[ "$mode" = noendpoint ] && { echo "no valid LLM endpoint configured" >&2; exit 1; }
out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
c='[]'; [ "$mode" = high ] && c='[{"severity":"high","path":"app.py","start_line":2,"content":"IndexError on empty list"}]'
printf '{"status":"completed","comments":%s,"manifest":{"coverage":{"completed":["app.py"],"failed":[]}},"summary":{"total_tokens":7}}' "$c" > "$out"
SH
# claude stub: answers by role; claude.mode = pass | p1
cat > "$STUB/claude" <<'SH'
#!/usr/bin/env bash
p="$(cat)"; sleep "${STUB_SLEEP:-0}"; mode="$(cat "$STUB_DIR/claude.mode" 2>/dev/null || echo pass)"
case "$p" in
  *VERIFIER*) r='{"verifications":[]}' ;;
  *) if [ "$mode" = p1 ] && [[ "$p" != *SECURITY* ]]; then
       r='{"verdict":"fail","findings":[{"severity":"P1","category":"bug","file":"app.py","line":2,"snippet":"return items[0]","problem":"IndexError when items is empty"}]}'
     else r='{"verdict":"pass","findings":[]}'; fi ;;
esac
python3 -c 'import json,sys; print(json.dumps({"type":"result","is_error":False,"result":sys.argv[1],"total_cost_usd":0.01,"usage":{"input_tokens":100,"output_tokens":20}}))' "$r"
SH
# antigravity stub: agy.mode = pass | hang | unavailable
cat > "$STUB/agy.js" <<'JS'
const fs = require('fs'); const a = process.argv; const out = a[a.indexOf('--out') + 1];
const mode = (() => { try { return fs.readFileSync(process.env.STUB_DIR + '/agy.mode', 'utf8').trim(); } catch { return 'pass'; } })();
const fin = (env) => { fs.writeFileSync(out, JSON.stringify({ reviewer: 'antigravity', findings: [], usage: { tokens: 0, usd: 0 }, ...env })); process.exit(env.status === 'ok' ? 0 : 1); };
if (mode === 'hang') setTimeout(() => {}, 600000);
else if (mode === 'unavailable') fin({ status: 'unavailable', reason: 'Antigravity is not running' });
else setTimeout(() => fin({ status: 'ok', verdict: 'pass' }), Number(process.env.STUB_SLEEP || 0) * 1000);
JS
chmod +x "$STUB/ocr" "$STUB/claude"
export STUB_DIR="$STUB" PATH="$STUB:$PATH" REVIEW_CLAUDE_BIN="$STUB/claude" REVIEW_AGY_CLI="$STUB/agy.js" REVIEW_TIMEOUT_AGY=40
P="$TMP/p"; mkdir -p "$P/.agents"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && echo x > README && git add -A && git commit -qm i)
printf '### [INSTINCT-001] Silent except\n- **Quy tắc phòng ngừa & Cách fix:** log it\n- **detect:** `except:\\s*pass`\n- **detect-glob:** `*.py`\n' > "$P/.agents/instincts.md"
(cd "$P" && git add -A && git commit -qm reg)
printf 'def g(items):\n    return items[0]\n' > "$P/app.py"
F="$DEVKIT_DIR/bin/review-fanout.sh"
run() { bash "$F" --repo "$P" --base HEAD "$@" > "$TMP/out" 2>&1; echo $?; }
reasons() { python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["reasons"]))' "$(bash "$F" --repo "$P" --base HEAD --status | awk '{print $2}')/summary.json"; }

# 1. all three pass, in parallel (each stub takes 3 s: sequential would be >= 9 s)
export STUB_SLEEP=3
t0=$(date +%s); rc=$(run); t1=$(date +%s)
[ "$rc" = 0 ] && grep -q "PASS" "$TMP/out" && ok "unanimous pass → exit 0" || { fail "unanimous pass rc=$rc"; cat "$TMP/out"; }
[ $((t1 - t0)) -lt 9 ] && ok "reviewers ran in parallel ($((t1 - t0)) s)" || fail "reviewers not parallel ($((t1 - t0)) s)"
export STUB_SLEEP=0
rc=$(run); grep -q "(cached:" "$TMP/out" && [ "$rc" = 0 ] && ok "same code → cached verdict, not re-billed" || fail "no cache"
bash "$F" --repo "$P" --base HEAD --status | grep -q '^PASS' && ok "--status PASS" || fail "--status"
[ -s "$P/.claude/audit-gate/review_outcomes.jsonl" ] && ok "outcome logged" || fail "review_outcomes.jsonl missing"

# 2. Antigravity hangs past its timeout → FAIL
echo "# v2" >> "$P/app.py"; echo hang > "$STUB/agy.mode"
REVIEW_TIMEOUT_AGY=4 rc=$(REVIEW_TIMEOUT_AGY=4 run)
[ "$rc" = 1 ] && reasons | grep -q '^antigravity: timeout' && ok "Antigravity timeout → FAIL" || { fail "timeout not FAIL rc=$rc"; reasons; }
echo unavailable > "$STUB/agy.mode"; echo "# v3" >> "$P/app.py"
rc=$(run); [ "$rc" = 1 ] && reasons | grep -q '^antigravity: unavailable' && ok "Antigravity unavailable → FAIL" || fail "unavailable not FAIL"
echo pass > "$STUB/agy.mode"

# 3. OCR without an LLM endpoint → FAIL (the delegation spec never counts as the OCR vote)
echo noendpoint > "$STUB/ocr.mode"; echo "# v4" >> "$P/app.py"
rc=$(run); [ "$rc" = 1 ] && reasons | grep -q '^ocr: failed' && ok "OCR no endpoint → FAIL, no delegate fallback" || { fail "ocr fallback counted rc=$rc"; reasons; }
echo ok > "$STUB/ocr.mode"

# 4. known bug pattern on an added line → P0 recurring, FAIL
printf 'def f():\n    try:\n        g([])\n    except: pass\n' > "$P/b.py"
rc=$(run); [ "$rc" = 1 ] && reasons | grep -q 'registry: verdict fail' && grep -q 'INSTINCT-001' "$TMP/out" \
  && ok "recurring known bug → P0 FAIL" || { fail "registry hit not FAIL rc=$rc"; cat "$TMP/out"; }
rm -f "$P/b.py"

# 5. Claude finds a cited P1 → FAIL, and it is recorded as OPEN bug row REV-<id> (needs a regression test to be done)
echo p1 > "$STUB/claude.mode"; echo "# v5" >> "$P/app.py"
rc=$(run)
[ "$rc" = 1 ] && reasons | grep -q 'unrefuted P0/P1' && ok "cited P1 → FAIL" || { fail "P1 not FAIL rc=$rc"; reasons; }
rev_ids() { (cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import regression_checklist as rc
print(" ".join(k for k in rc.load_view(sys.argv[2])["items"] if k.startswith("BUG-REV-")))' "$DEVKIT_DIR/bin" "$P"); }
[ -n "$(rev_ids)" ] && ok "accepted P1 recorded as OPEN bug row $(rev_ids) (regression checklist)" || fail "no BUG-REV row in the checklist"
# 6. the bug is gone (code changed) and every reviewer passes, but the REV row has no test → still FAIL
echo pass > "$STUB/claude.mode"; printf 'def g(items):\n    return items[0] if items else None\n' > "$P/app.py"
rc=$(run); [ "$rc" = 1 ] && reasons | grep -q '^BUG-REV-.*regression test' && ok "fixed finding without a regression test → FAIL" \
  || { fail "fixed-without-test not FAIL rc=$rc"; reasons; }

# 7. OCR's high finding with a Claude/Antigravity pass → not unanimous → FAIL
for id in $(rev_ids); do (cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$DEVKIT_DIR/bin/regression_checklist.py" drop "$id" >/dev/null 2>&1); done
[ -z "$(rev_ids)" ] && ok "dropped REV row (not a bug) no longer blocks" || fail "REV row could not be dropped: $(rev_ids)"
echo high > "$STUB/ocr.mode"; printf 'def g(items):\n    return items[0]\n' > "$P/app.py"; echo "# v7" >> "$P/app.py"
rc=$(run); [ "$rc" = 1 ] && reasons | grep -q '^ocr: verdict fail' && ok "one reviewer says fail → FAIL" || { fail "split vote passed rc=$rc"; reasons; }

if [ "$FAILS" -ne 0 ]; then echo "review fanout: $FAILS FAILED"; exit 1; fi
echo "review fanout: all checks passed"
