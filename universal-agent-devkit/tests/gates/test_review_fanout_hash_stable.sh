#!/usr/bin/env bash
# review-fanout.sh files a verdict only under the code state that was reviewed, and keeps answering for it (2/2 review of #742, r14d):
#   BUG-REV-49df56afb6 (F11) a FAIL in a LINKED worktree writes its bug rows into the tracked .agents/regression_status.json, which
#     moved the code hash: --status said NONE right after the FAIL and the Stop hook started the same billed review again
#   BUG-REV-d5a4fc3b03 (F13) the verdict was sealed under the hash taken at the start although cite-check and the verifier read the
#     live tree at the end: a change made during the review produced a PASS for code nobody reviewed
# Stub reviewers (no LLM, no network): the stubs of test_review_fanout_e2e.sh, sourced from it. DK_BIN overrides the bin dir (RED run).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${DK_BIN:-$DEVKIT_DIR/bin}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export HOME="$TMP/home"; mkdir -p "$HOME"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
STUB="$TMP/stub"; mkdir -p "$STUB"
# the stub reviewers: lines 13-60 of test_review_fanout_e2e.sh (from "# ocr stub" to the chmod), never edited here
sed -n '/^# ocr stub/,/^chmod +x "\$STUB\/ocr"/p' "$DEVKIT_DIR/tests/gates/test_review_fanout_e2e.sh" > "$TMP/stubs.sh"
grep -q '^chmod +x' "$TMP/stubs.sh" || { echo "✖ fixture: stub block not found in test_review_fanout_e2e.sh"; exit 1; }
. "$TMP/stubs.sh"
# claude stub, mutate mode: an edit lands in the reviewed tree while the review runs
python3 - "$STUB/claude" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace('p="$(cat)";', 'p="$(cat)"; [ -n "${STUB_MUTATE:-}" ] && echo "x = 1" >> "$STUB_MUTATE";', 1)
open(p, "w").write(s)
PY
grep -q STUB_MUTATE "$STUB/claude" || { echo "✖ fixture: claude stub not patched"; exit 1; }
unset REVIEW_CLAUDE_MODEL REVIEW_GROK_MODEL REVIEW_AGY_MODEL REVIEW_SKIP_REVIEWERS
export STUB_DIR="$STUB" PATH="$STUB:$PATH" REVIEW_CLAUDE_BIN="$STUB/claude" REVIEW_AGY_CLI="$STUB/agy.js" REVIEW_TIMEOUT_AGY=40 \
  REVIEW_GROK_BIN="$STUB/grok"
F="$BIN/review-fanout.sh"
P="$TMP/p"; mkdir -p "$P/.agents"
(cd "$P" && git init -q -b main && git config user.email t@t && git config user.name t && echo x > README \
  && echo '{"items":{}}' > .agents/regression_status.json && git add -A && git commit -qm i)
LW="$TMP/lw"
git -C "$P" worktree add -q -b feat "$TMP/lw"

# F11: a FAIL with an accepted P1 in a linked worktree stays the answer for that code
echo p1 > "$STUB/claude.mode"
printf 'def g(items):\n    return items[0]\n' > "$LW/app.py"
bash "$F" --repo "$LW" --base HEAD > "$TMP/out1" 2>&1; rc=$?
[ "$rc" = 1 ] && ok "linked worktree, cited P1: review FAIL" || { fail "fixture: review rc=$rc"; tail -20 "$TMP/out1"; }
git -C "$LW" status --porcelain | grep -q 'regression_status.json' && ok "fixture: the FAIL wrote bug rows into the tracked checklist" \
  || fail "fixture: no tracked checklist change, the F11 case would be vacuous ($(git -C "$LW" status --porcelain | tr '\n' ' '))"
st="$(bash "$F" --repo "$LW" --base HEAD --status | awk '{print $1}')"
[ "$st" = FAIL ] && ok "--status right after the FAIL: FAIL (not NONE)" || fail "--status after FAIL in a linked worktree: $st"
bash "$F" --repo "$LW" --base HEAD > "$TMP/out1b" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q '(cached:' "$TMP/out1b" && ok "a second run answers from the cached FAIL (not billed again)" \
  || fail "second run rc=$rc: $(tail -3 "$TMP/out1b" | tr '\n' ' ')"

# F13: the tree changes while the reviewers run → FAIL for that hash, never a PASS
echo pass > "$STUB/claude.mode"
Q="$TMP/q"; mkdir -p "$Q"
(cd "$Q" && git init -q -b main && git config user.email t@t && git config user.name t && echo x > README && git add -A && git commit -qm i)
printf 'def f():\n    return 1\n' > "$Q/app.py"
H0="$(bash "$F" --repo "$Q" --base HEAD --hash)"
STUB_MUTATE="$Q/late.py" bash "$F" --repo "$Q" --base HEAD > "$TMP/out2" 2>&1; rc=$?
v="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verdict",""))' "$Q/.git/review-fanout/$H0/summary.json" 2>/dev/null)"
[ "$rc" != 0 ] && [ "$v" = FAIL ] && ok "tree changed during the review: FAIL under the reviewed hash (rc=$rc)" || fail "tree changed during the review: rc=$rc verdict=$v"
grep -q 'changed during the review' "$Q/.git/review-fanout/$H0/summary.json" 2>/dev/null && ok "the reason names the change" || fail "no 'changed during the review' reason"
st="$(bash "$F" --repo "$Q" --base HEAD --status | awk '{print $1}')"
[ "$st" != PASS ] && ok "the changed tree has no PASS (--status $st)" || fail "the changed tree answered PASS"
rm -f "$Q/late.py"
st="$(bash "$F" --repo "$Q" --base HEAD --status | awk '{print $1}')"
[ "$st" = FAIL ] && ok "the reviewed state answers FAIL, never PASS (--status $st)" || fail "reviewed state --status $st"
# control: an undisturbed review of the same code passes
bash "$F" --repo "$Q" --base HEAD --force > "$TMP/out3" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "control: the same code reviewed undisturbed passes" || { fail "control rc=$rc"; tail -15 "$TMP/out3"; }
[ "$FAILS" = 0 ] && { echo "review-fanout hash stable: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
