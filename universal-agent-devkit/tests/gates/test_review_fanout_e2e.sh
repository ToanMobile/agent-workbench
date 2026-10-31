#!/usr/bin/env bash
# bin/review-fanout.sh end to end with stub reviewers (no LLM, no network): the 4 (Claude Opus, Antigravity, Grok, OCR) run in
# parallel, a reviewer that times out, fails, is unavailable or ran the wrong model (Claude not on Opus) makes the whole review
# FAIL (no delegate fallback for OCR), a known-bug pattern on an added line is a
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
echo "$*" >> "$STUB_DIR/claude.args"
model="$(cat "$STUB_DIR/claude.model" 2>/dev/null || echo claude-opus-4-5)"
case "$p" in
  *VERIFIER*) r='{"verifications":[]}' ;;
  *) if [ "$mode" = p1 ] && [[ "$p" != *SECURITY* ]]; then
       r='{"verdict":"fail","findings":[{"severity":"P1","category":"bug","file":"app.py","line":2,"snippet":"return items[0]","problem":"IndexError when items is empty"}]}'
     else r='{"verdict":"pass","findings":[]}'; fi ;;
esac
python3 -c 'import json,sys; print(json.dumps({"type":"result","is_error":False,"result":sys.argv[1],"total_cost_usd":0.01,"usage":{"input_tokens":100,"output_tokens":20},"modelUsage":{sys.argv[2]:{"outputTokens":20},"claude-haiku-4-5":{"outputTokens":3}}}))' "$r" "$model"
SH
# grok stub (headless --output-format json, pretty-printed like the real CLI): grok.mode = pass | nocredit | wrongmodel
cat > "$STUB/grok" <<'SH'
#!/usr/bin/env bash
sleep "${STUB_SLEEP:-0}"; mode="$(cat "$STUB_DIR/grok.mode" 2>/dev/null || echo pass)"; m=""
echo "$*" >> "$STUB_DIR/grok.args"
while [ $# -gt 0 ]; do [ "$1" = -m ] && m="$2"; shift; done
if [ "$mode" = nocredit ]; then
  echo '{"type":"error","message":"API error (status 402 Payment Required): Grok Build usage balance exhausted"}'; exit 1
fi
[ "$mode" = wrongmodel ] && m="grok-4.5"
python3 -c 'import json,sys; print(json.dumps({"text":"```json\n{\"verdict\":\"pass\",\"findings\":[]}\n```","stopReason":"end_turn","usage":{"total_tokens":50},"modelUsage":{sys.argv[1]:{"outputTokens":9}},"total_cost_usd":0.002}, indent=2))' "$m"
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
chmod +x "$STUB/ocr" "$STUB/claude" "$STUB/grok"
unset REVIEW_CLAUDE_MODEL REVIEW_GROK_MODEL
export STUB_DIR="$STUB" PATH="$STUB:$PATH" REVIEW_CLAUDE_BIN="$STUB/claude" REVIEW_AGY_CLI="$STUB/agy.js" REVIEW_TIMEOUT_AGY=40 \
  REVIEW_GROK_BIN="$STUB/grok"
P="$TMP/p"; mkdir -p "$P/.agents"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && echo x > README && git add -A && git commit -qm i)
printf '### [INSTINCT-001] Silent except\n- **Quy tắc phòng ngừa & Cách fix:** log it\n- **detect:** `except:\\s*pass`\n- **detect-glob:** `*.py`\n' > "$P/.agents/instincts.md"
(cd "$P" && git add -A && git commit -qm reg)
printf 'def g(items):\n    return items[0]\n' > "$P/app.py"
F="$DEVKIT_DIR/bin/review-fanout.sh"
run() { bash "$F" --repo "$P" --base HEAD "$@" > "$TMP/out" 2>&1; echo $?; }
reasons() { python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["reasons"]))' "$(bash "$F" --repo "$P" --base HEAD --status | awk '{print $2}')/summary.json"; }

# 1. all four pass, in parallel (each stub takes 3 s: sequential would be >= 12 s)
export STUB_SLEEP=3
t0=$(date +%s); rc=$(run); t1=$(date +%s)
[ "$rc" = 0 ] && grep -q "PASS" "$TMP/out" && ok "unanimous pass → exit 0" || { fail "unanimous pass rc=$rc"; cat "$TMP/out"; }
[ $((t1 - t0)) -lt 9 ] && ok "4 reviewers ran in parallel ($((t1 - t0)) s)" || fail "reviewers not parallel ($((t1 - t0)) s)"
export STUB_SLEEP=0
rc=$(run); grep -q "(cached:" "$TMP/out" && [ "$rc" = 0 ] && ok "same code → cached verdict, not re-billed" || fail "no cache"
bash "$F" --repo "$P" --base HEAD --status | grep -q '^PASS' && ok "--status PASS" || fail "--status"
[ -s "$P/.claude/audit-gate/review_outcomes.jsonl" ] && ok "outcome logged" || fail "review_outcomes.jsonl missing"
grep -q -- '--model opus' "$STUB/claude.args" && ok "Claude is started with --model opus" || fail "Claude not pinned to Opus: $(cat "$STUB/claude.args")"
grep -q -- '-m grok-4.7' "$STUB/grok.args" && grep -q -- '--sandbox read-only' "$STUB/grok.args" \
  && ok "Grok is started pinned (-m grok-4.7) in the read-only sandbox" || fail "Grok args: $(cat "$STUB/grok.args")"
python3 -c 'import json,sys; r=json.loads(open(sys.argv[1]).read().splitlines()[-1])["reviewers"]; sys.exit(0 if r["claude"]["model"]=="claude-opus-4-5" and r["grok"]["model"]=="grok-4.7" else 1)' \
  "$P/.claude/audit-gate/review_outcomes.jsonl" && ok "models actually used are recorded in the outcome" || fail "models not recorded"

# 1b. Claude answered on a non-Opus model → FAIL (even with a pass verdict)
echo claude-sonnet-4-5 > "$STUB/claude.model"; echo "# v1b" >> "$P/app.py"
rc=$(run); [ "$rc" = 1 ] && reasons | grep -q '^claude: failed — Claude ran claude-sonnet-4-5, the review requires Opus' \
  && ok "Claude ran a non-Opus model → FAIL" || { fail "non-Opus Claude passed rc=$rc"; reasons; }
rm -f "$STUB/claude.model"

# 1c. Grok missing (CLI absent), out of credit, or on another model → FAIL
echo "# v1c" >> "$P/app.py"
rc=$(REVIEW_GROK_BIN="$TMP/no-such-grok" run); [ "$rc" = 1 ] && reasons | grep -q '^grok: unavailable' \
  && ok "Grok missing → FAIL" || { fail "missing Grok passed rc=$rc"; reasons; }
echo nocredit > "$STUB/grok.mode"; echo "# v1d" >> "$P/app.py"
rc=$(run); [ "$rc" = 1 ] && reasons | grep -q '^grok: failed — grok rc=1: API error (status 402' \
  && ok "Grok out of credit (402) → FAIL" || { fail "Grok 402 passed rc=$rc"; reasons; }
echo wrongmodel > "$STUB/grok.mode"; echo "# v1e" >> "$P/app.py"
rc=$(run); [ "$rc" = 1 ] && reasons | grep -q '^grok: failed — Grok ran grok-4.5, the review pins grok-4.7' \
  && ok "Grok on another model → FAIL" || { fail "wrong Grok model passed rc=$rc"; reasons; }
echo pass > "$STUB/grok.mode"

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

# 7. OCR's high finding with Claude/Antigravity/Grok passing → not unanimous → FAIL
for id in $(rev_ids); do (cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$DEVKIT_DIR/bin/regression_checklist.py" drop "$id" >/dev/null 2>&1); done
[ -z "$(rev_ids)" ] && ok "dropped REV row (not a bug) no longer blocks" || fail "REV row could not be dropped: $(rev_ids)"
echo high > "$STUB/ocr.mode"; printf 'def g(items):\n    return items[0]\n' > "$P/app.py"; echo "# v7" >> "$P/app.py"
rc=$(run); [ "$rc" = 1 ] && reasons | grep -q '^ocr: verdict fail' && ok "one reviewer says fail → FAIL" || { fail "split vote passed rc=$rc"; reasons; }

# 8. per-run override (user 31/10/2026): --skip grok,ocr / REVIEW_SKIP_REVIEWERS → a REDUCED 2-way run, labelled as such
echo ok > "$STUB/ocr.mode"; echo pass > "$STUB/claude.mode"; echo pass > "$STUB/grok.mode"; echo pass > "$STUB/agy.mode"
rm -f "$STUB/claude.model"
for id in $(rev_ids); do (cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$DEVKIT_DIR/bin/regression_checklist.py" drop "$id" >/dev/null 2>&1); done
printf 'def g(items):\n    return items[0] if items else None\n# v8\n' > "$P/app.py"
rm -f "$STUB/grok.args"; : > "$STUB/ocr.called"
rc=$(run --skip grok,ocr)
S8="$(bash "$F" --repo "$P" --base HEAD --skip grok,ocr --status | awk '{print $2}')/summary.json"
[ "$rc" = 0 ] && grep -q 'REDUCED 2-way review' "$TMP/out" && grep -q '| grok | SKIPPED |' "$TMP/out" && grep -q '| ocr | SKIPPED |' "$TMP/out" \
  && ok "--skip grok,ocr → REDUCED 2-way PASS, both listed as skipped by user override" || { fail "reduced run rc=$rc"; cat "$TMP/out"; }
[ ! -s "$STUB/grok.args" ] && ok "a skipped reviewer is not started" || fail "grok ran although skipped"
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); sys.exit(0 if s["reduced"] and s["skipped_by_override"]==["grok","ocr"] else 1)' "$S8" \
  && ok "summary.json: reduced=true, skipped_by_override=[grok, ocr]" || fail "summary.json lacks the override"
st="$(bash "$F" --repo "$P" --base HEAD --status | awk '{print $1}')"
[ "$st" = NONE ] && ok "a reduced PASS never answers the default 4-way --status (separate code hash)" || fail "4-way status saw the reduced run: $st"
rc=$(REVIEW_SKIP_REVIEWERS=grok,ocr run); [ "$rc" = 0 ] && grep -q 'cached' "$TMP/out" && ok "REVIEW_SKIP_REVIEWERS env = same override (cached)" || fail "env override rc=$rc"
echo "# v8b" >> "$P/app.py"; echo unavailable > "$STUB/agy.mode"
rc=$(run --skip grok,ocr); [ "$rc" = 1 ] && grep -q 'antigravity: unavailable' "$TMP/out" && ok "reduced run: Antigravity missing → FAIL" || { fail "agy missing in reduced run rc=$rc"; cat "$TMP/out"; }
echo pass > "$STUB/agy.mode"; echo "# v8c" >> "$P/app.py"; echo claude-sonnet-4-5 > "$STUB/claude.model"
rc=$(run --skip grok,ocr); [ "$rc" = 1 ] && grep -q 'requires Opus' "$TMP/out" && ok "reduced run: Claude not on Opus → FAIL" || { fail "non-Opus in reduced run rc=$rc"; cat "$TMP/out"; }
rm -f "$STUB/claude.model"
for bad in claude antigravity "grok,claude"; do
  rc=$(run --skip "$bad"); [ "$rc" = 2 ] || fail "--skip $bad accepted (rc=$rc)"
done; ok "--skip claude / antigravity refused (exit 2)"
rc=$(bash "$F" --repo "$P" --base > /dev/null 2>&1; echo $?); [ "$rc" = 2 ] && ok "--base without a value → usage error, no hang" || fail "--base last rc=$rc"

# 9. the review's own writes (checklist rows) do not change the cached code state; a FIFO in the tree never hangs the hash
h1="$(bash "$F" --repo "$P" --base HEAD --hash)"
mkdir -p "$P/.agents"; echo '{"items":{}}' > "$P/.agents/regression_status.json"
h2="$(bash "$F" --repo "$P" --base HEAD --hash)"
[ "$h1" = "$h2" ] && ok "checklist written by the review is outside the code hash" || fail "checklist write changed the hash"
rm -f "$P/.agents/regression_status.json"
mkfifo "$P/pipe.fifo"
( bash "$F" --repo "$P" --base HEAD --hash > "$TMP/h3" 2>&1; echo $? > "$TMP/h3.rc" ) & hp=$!
for _ in $(seq 1 20); do [ -s "$TMP/h3.rc" ] && break; sleep 0.5; done
if [ -s "$TMP/h3.rc" ]; then ok "an untracked FIFO does not hang the code hash"; else kill $hp 2>/dev/null; fail "hash hung on a FIFO"; fi
rm -f "$P/pipe.fifo"

# 10. a stopped review stops its reviewers (no orphan CLI left billing) and records why
echo "# v10" >> "$P/app.py"; rm -f "$STUB/claude.model"
STUB_SLEEP=30 bash "$F" --repo "$P" --base HEAD --skip grok,ocr > "$TMP/out10" 2>&1 & fp=$!
for _ in $(seq 1 40); do pgrep -f "$STUB/claude" >/dev/null && break; sleep 0.25; done
kill -TERM $fp; wait $fp 2>/dev/null
sleep 1
if pgrep -f "$STUB/claude" >/dev/null || pgrep -f "$STUB/agy.js" >/dev/null; then
  fail "reviewers kept running after the fan-out was stopped"; pkill -f "$STUB/" 2>/dev/null
else ok "SIGTERM to the fan-out stops every reviewer process"; fi
R10="$(bash "$F" --repo "$P" --base HEAD --skip grok,ocr --hash)"
grep -q 'interrupted' "$P/.git/review-fanout/$R10/claude.json" 2>/dev/null && ok "the stopped reviewer's envelope says interrupted" \
  || fail "no interrupted envelope: $(cat "$P/.git/review-fanout/$R10/claude.json" 2>&1)"

if [ "$FAILS" -ne 0 ]; then echo "review fanout: $FAILS FAILED"; exit 1; fi
echo "review fanout: all checks passed"
