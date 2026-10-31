#!/usr/bin/env bash
# B2 of #742 (decision 31/10 17:32, "Sửa review-merge đọc status ngoài repo, không commit regression_status.json"):
# REVIEW_REGRESSION_STATUS=<absolute path OUTSIDE the repo> makes the review read the BUG-REV rows' status from that file instead of the
# tracked .agents/regression_status.json (which a clean review tree only has as committed). The rule is unchanged: an accepted P0/P1
# whose linked test did not pass still FAILs the review — read from the outside file. Its bytes are part of the code hash; a path
# inside the repo, a missing or unreadable file is refused (fail-closed). A FAIL also records its bug rows in that file.
# DK_BIN overrides the bin dir (RED run: the previous commit's copy).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${DK_BIN:-$DK/bin}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export HOME="$TMP/home"; mkdir -p "$HOME"
unset REVIEW_SKIP_REVIEWERS REVIEW_CLAUDE_MODEL REVIEW_GROK_MODEL REVIEW_AGY_MODEL REVIEW_REGRESSION_STATUS CLAUDE_PROJECT_DIR
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P/.agents"
(cd "$P" && git init -q -b main && git config user.email t@t && git config user.name t && echo x > README && git add -A && git commit -qm i)
# a review-born bug row with no linked test (OPEN) in the tracked checklist
(cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$DK/bin/regression_checklist.py" --project "$P" add "[review P1] app.py:2 fixture" \
  --id REV-abcabcabca --severity P1 --module app.py --evidence "4-way review (claude)" >/dev/null 2>&1) || fail "fixture: add row"
git -C "$P" add -A && git -C "$P" commit -qm rows
# outside the repo: GOOD = the same checklist without that row (nothing open), BAD = with it
python3 - "$P" "$TMP/good.json" "$TMP/bad.json" "$DK/bin" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[4])
import regression_checklist as rc
d = rc.load_view(sys.argv[1])   # what the review reads today (tracked file + pending store of a trunk-mode main)
assert "BUG-REV-abcabcabca" in d["items"], "fixture row missing"
json.dump(d, open(sys.argv[3], "w"))
d["items"].pop("BUG-REV-abcabcabca"); json.dump(d, open(sys.argv[2], "w"))
PY
RUN="$TMP/run"; mkdir -p "$RUN"
python3 - "$RUN" <<'PY'
import json, os, sys
run = sys.argv[1]
meta = {"required": ["claude", "antigravity", "registry"], "skipped_by_override": ["grok", "ocr"], "depth": "light", "code_hash": "0" * 64,
        "models": {"claude": "opus", "antigravity": "gemini-4-argon-high"}}
json.dump(meta, open(os.path.join(run, "meta.json"), "w"))
for name, model in (("claude", "claude-opus-4-5"), ("antigravity", "gemini-4-argon-high")):
    json.dump({"reviewer": name, "status": "ok", "verdict": "pass", "findings": [], "model": model}, open(os.path.join(run, name + ".json"), "w"))
json.dump({"reviewer": "registry", "status": "ok", "verdict": "pass", "findings": []}, open(os.path.join(run, "registry.json"), "w"))
PY
merge() {   # merge [--status-file F] → verdict + reasons in $TMP/v (a stale summary never answers)
  rm -f "$RUN/summary.json"
  python3 "$BIN/review-merge.py" --dir "$RUN" --repo "$P" --outcomes "$TMP/outcomes.jsonl" "$@" >/dev/null 2>"$TMP/merge.err"
  python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(s["verdict"]); print("\n".join(s["reasons"]))' "$RUN/summary.json" > "$TMP/v" 2>/dev/null \
    || echo "NO-SUMMARY $(tail -2 "$TMP/merge.err" | tr '\n' ' ')" > "$TMP/v"
}
merge
grep -q 'BUG-REV-abcabcabca: accepted finding is' "$TMP/v" && ok "control: the tracked checklist's open row FAILs the review" || fail "control: $(cat "$TMP/v")"
merge --status-file "$TMP/good.json"
[ "$(head -1 "$TMP/v")" = PASS_REDUCED ] && ok "status read from the outside file (row fixed there): PASS_REDUCED" || fail "outside good: $(cat "$TMP/v")"
merge --status-file "$TMP/bad.json"
grep -q 'BUG-REV-abcabcabca: accepted finding is OPEN' "$TMP/v" && ok "the outside file's open row still FAILs (the linked-test rule is kept)" || fail "outside bad: $(cat "$TMP/v")"
merge --status-file "$P/.agents/regression_status.json"
[ "$(head -1 "$TMP/v")" = FAIL ] && grep -q 'inside the repo' "$TMP/v" && ok "a status file inside the repo is refused (FAIL)" || fail "inside repo: $(cat "$TMP/v")"
merge --status-file "$TMP/missing.json"
[ "$(head -1 "$TMP/v")" = FAIL ] && grep -q '^regression checklist:' "$TMP/v" && ok "a missing status file is FAIL, never a pass" || fail "missing: $(cat "$TMP/v")"
echo '{"items": [' > "$TMP/broken.json"; merge --status-file "$TMP/broken.json"
[ "$(head -1 "$TMP/v")" = FAIL ] && ok "an unreadable status file is FAIL" || fail "broken: $(cat "$TMP/v")"

# review-fanout: the outside file is part of the code state; a path inside the repo is a usage error
echo 'def f(): return 1' > "$P/app.py"
h0="$(bash "$BIN/review-fanout.sh" --repo "$P" --base HEAD --hash 2>/dev/null)"
h1="$(REVIEW_REGRESSION_STATUS="$TMP/good.json" bash "$BIN/review-fanout.sh" --repo "$P" --base HEAD --hash 2>/dev/null)"
h2="$(REVIEW_REGRESSION_STATUS="$TMP/bad.json" bash "$BIN/review-fanout.sh" --repo "$P" --base HEAD --hash 2>/dev/null)"
[ -n "$h1" ] && [ "$h1" != "$h0" ] && [ "$h2" != "$h1" ] && ok "the outside file's bytes are part of the code hash" || fail "hash: h0=$h0 h1=$h1 h2=$h2"
REVIEW_REGRESSION_STATUS="$P/.agents/regression_status.json" bash "$BIN/review-fanout.sh" --repo "$P" --base HEAD --hash >/dev/null 2>"$TMP/e"; rc=$?
[ "$rc" = 2 ] && grep -q 'outside' "$TMP/e" && ok "review-fanout refuses a status file inside the repo (exit 2)" || fail "fanout inside repo rc=$rc $(cat "$TMP/e")"
REVIEW_REGRESSION_STATUS="relative.json" bash "$BIN/review-fanout.sh" --repo "$P" --base HEAD --hash >/dev/null 2>"$TMP/e"; rc=$?
[ "$rc" = 2 ] && ok "review-fanout refuses a relative status path (exit 2)" || fail "fanout relative rc=$rc"

# a FAIL records its accepted findings in the outside file too (the next review reads them from there)
python3 - "$RUN" <<'PY'
import json, os, sys
run = sys.argv[1]
f = {"severity": "P1", "category": "bug", "file": "app.py", "line": 1, "snippet": "def f(): return 1", "problem": "returns a constant"}
json.dump({"reviewer": "claude", "status": "ok", "verdict": "fail", "findings": [f], "model": "claude-opus-4-5"}, open(os.path.join(run, "claude.json"), "w"))
PY
cp "$TMP/good.json" "$TMP/rec.json"
python3 "$BIN/review-merge.py" --dir "$RUN" --repo "$P" --outcomes "$TMP/outcomes.jsonl" --record-bugs --status-file "$TMP/rec.json" >/dev/null 2>&1
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if any(k.startswith("BUG-REV-") for k in d["items"]) else 1)' "$TMP/rec.json" \
  && ok "a FAIL records its bug row in the outside status file" || fail "no BUG-REV row recorded in the outside file"
[ "$FAILS" = 0 ] && { echo "review status outside the repo: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
