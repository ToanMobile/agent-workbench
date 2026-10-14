#!/usr/bin/env bash
# hooks/review_gate.sh + OpenCodeReview (2026-10-13, user: "tự chạy ocr review ở các repo"): `ocr review` had never run here
# (no LLM endpoint; see tests/installer/test_ocr_review_helper.sh) and the gate did not know OCR at all.
#  1. When the gate blocks (code edited, no fresh review after it), it now runs bin/ocr-review --delegate-only itself (OCR
#     delegation: no LLM, no key, ~1 s, only on this block path) and names the spec in the block message, so every repo with
#     the DevKit gets an OCR review spec without anyone remembering the tool. REVIEW_GATE_OCR=0 turns it off.
#     What counts is a REPORT, never a word in the output (OpenCodeReview of this gate, 13/10): the helper's `report: <file>` or a
#     plain `ocr review … -o <file>` must name an OCR JSON report (an object with a `comments` list) written after the last edit
#     of the files edited this session. `--help`/`--version`, `echo mode: review`, a missing, malformed or older report: no.
#  4. The delegation runs in the repo the gate checks (the git toplevel of the session cwd), not CLAUDE_PROJECT_DIR.
#  3. A hung `ocr` (OCR_HANG) never costs the hook its own 20 s budget (hooks.json): Claude Code kills a hook that runs past it and the
#     Stop goes through unreviewed. The helper bounds each `ocr delegate` call and the gate bounds the helper well inside 20 s.
#  2. A full OCR review that SUCCEEDED after the last edit (a Bash `ocr review …` or `ocr-review` whose result is not an error
#     and, for the helper, says `mode: review`) counts as the fresh review. A failed one (the endpoint error) does not.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo x > a && git add a && git commit -qm i)
echo "def f(x): return 1 / x" > "$P/app.py"

# fake ocr: delegation works, `ocr review` reports the missing endpoint
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<'SH'
#!/bin/sh
case "$1 $2" in
  "review "*) echo "Error: resolve LLM endpoint: no valid LLM endpoint configured" >&2; exit 1 ;;
  "delegate preview") [ -n "${OCR_HANG:-}" ] && sleep 60; [ -n "${OCR_PWD_LOG:-}" ] && pwd -P > "$OCR_PWD_LOG"; printf '{"schema_version":"1","reviewable_count":1,"reviewable_files":[{"path":"app.py","status":"added","insertions":1,"deletions":0}]}\n'; exit 0 ;;
  "delegate rule") printf '{"schema_version":"1","groups":[{"group_id":1,"files":["app.py"],"rule":"ZeroDivisionError"}]}\n'; exit 0 ;;
esac
exit 9
SH
chmod +x "$TMP/bin/ocr"

# transcript: tr <file> then lines ev <kind> ...
TR="$TMP/t.jsonl"
cat > "$TMP/ev.py" <<'PY'
import json, sys
kind, tr = sys.argv[1], sys.argv[2]
a = sys.argv[3:]
if kind == "edit":
    e = {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": a[0], "name": "Write", "input": {"file_path": a[1], "content": "x"}}]}}
elif kind == "agent":
    e = {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": a[0], "name": "Agent", "input": {"subagent_type": a[1], "prompt": "review"}}]}}
elif kind == "bash":
    e = {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": a[0], "name": "Bash", "input": {"command": a[1]}}]}}
elif kind == "result":
    e = {"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": a[0], "is_error": a[1] == "err", "content": a[2]}]}}
with open(tr, "a") as f:
    f.write(json.dumps(e) + "\n")
PY
ev() { python3 "$TMP/ev.py" "$1" "$TR" "${@:2}"; }
stop() { printf '{"session_id":"s-%s","transcript_path":"%s","hook_event_name":"Stop"}' "$1" "$TR" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P" ${2:+env $2} bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"; }

# 1. edited, nothing reviewed: blocked, and the message carries the OCR spec the gate made
: > "$TR"; ev edit t1 "$P/app.py"
stop a; rc=$?
spec="$(grep -o '/[^ ]*ocr-spec.md' "$TMP/err" | head -1)"
[ "$rc" = 2 ] && ok "unreviewed edit: blocked (rc 2)" || fail "unreviewed edit: rc $rc"
[ -n "$spec" ] && [ -f "$spec" ] && grep -q 'app.py' "$spec" && ok "the block message names an OCR spec the gate made ($spec)" \
  || fail "no OCR spec in the block message: $(tail -4 "$TMP/err" | tr '\n' ' ')"
[ -z "$(git -C "$P" status --porcelain -- . ':!app.py')" ] && ok "repo untouched by the OCR run" || fail "stray files: $(git -C "$P" status --porcelain)"

# 2. switch off: no OCR run
: > "$TR"; ev edit t1 "$P/app.py"
stop b REVIEW_GATE_OCR=0; rc=$?
[ "$rc" = 2 ] && ! grep -q 'ocr-spec.md' "$TMP/err" && ok "REVIEW_GATE_OCR=0: blocked without running OCR" || fail "switch ignored (rc $rc)"

# 3. a full OCR review that succeeded after the edit counts as the review
mkdir -p "$TMP/rep"; printf '{"comments":[]}\n' > "$TMP/rep/ocr-review.json"; printf '{"comments":[]}\n' > "$TMP/rep/plain.json"
mkdir -p "$TMP/spec" "$P/rel"; echo "# OCR review spec" > "$TMP/spec/ocr-spec.md"; echo "# OCR review spec" > "$P/rel/ocr-spec.md"
chmod 700 "$TMP/spec" "$P/rel"   # what bin/ocr-review makes of its --out folder
# a real delegation spec, newer than app.py: set, not left to the clock (a 1 s filesystem would give both one mtime)
python3 -c 'import os,sys,time; [os.utime(f,(time.time()-60,)*2) for f in sys.argv[1:2]]; [os.utime(f,(time.time()+5,)*2) for f in sys.argv[2:]]' \
  "$P/app.py" "$TMP/spec/ocr-spec.md" "$P/rel/ocr-spec.md"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t2 ".agents/devkit/bin/ocr-review"; ev result t2 ok "$(printf 'mode: review\nreport: %s' "$TMP/rep/ocr-review.json")"
stop c; rc=$?
[ "$rc" = 0 ] && ok "ocr-review in review mode after the edit: counts as the fresh review (rc 0)" || fail "successful OCR review not counted (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t2 "ocr review --format json -o $TMP/rep/plain.json"; ev result t2 ok ''
stop d; rc=$?
[ "$rc" = 0 ] && ok "a successful plain ocr review after the edit counts (rc 0)" || fail "plain ocr review not counted (rc $rc)"

# 4. what does not count
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t2 "ocr review"; ev result t2 err "Error: resolve LLM endpoint: no valid LLM endpoint configured"
stop e; rc=$?
[ "$rc" = 2 ] && ok "a failed ocr review (endpoint error) does not count (rc 2)" || fail "failed OCR review counted (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t2 ".agents/devkit/bin/ocr-review"; ev result t2 ok $'mode: delegate\nspec: /tmp/x/ocr-spec.md'
stop f; rc=$?
[ "$rc" = 2 ] && ok "a delegation spec alone (nobody reviewed yet) does not count (rc 2)" || fail "delegate spec counted as a review (rc $rc)"
: > "$TR"; ev bash t0 "ocr review --format json"; ev result t0 ok '{"comments":[]}'; ev edit t1 "$P/app.py"
stop g; rc=$?
[ "$rc" = 2 ] && ok "an OCR review BEFORE the last edit does not count (rc 2)" || fail "stale OCR review counted (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t2 "echo ocr review is great"; ev result t2 ok 'ocr review is great'
stop h; rc=$?
[ "$rc" = 2 ] && ok "a command that only mentions ocr review does not count (rc 2)" || fail "echo counted as a review (rc $rc)"

# 4b. the ways around a word check (OpenCodeReview, 13/10): none counts
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t2 "ocr review --help"; ev result t2 ok 'Usage: ocr review [flags]'
stop j; rc=$?
[ "$rc" = 2 ] && ok "ocr review --help does not count (rc 2)" || fail "--help counted as a review (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t2 ".agents/devkit/bin/ocr-review --delegate-only; echo mode: review"
ev result t2 ok $'mode: delegate\nspec: /tmp/x/ocr-spec.md\nmode: review'
stop k; rc=$?
[ "$rc" = 2 ] && ok "a delegation run followed by 'echo mode: review' does not count (rc 2)" || fail "echoed mode counted (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t2 ".agents/devkit/bin/ocr-review"; ev result t2 ok "$(printf 'mode: review\nreport: %s' "$TMP/rep/none.json")"
stop l; rc=$?
[ "$rc" = 2 ] && ok "a report path that does not exist does not count (rc 2)" || fail "missing report counted (rc $rc)"
printf '{"error":"x"}\n' > "$TMP/rep/bad.json"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t2 ".agents/devkit/bin/ocr-review"; ev result t2 ok "$(printf 'mode: review\nreport: %s' "$TMP/rep/bad.json")"
stop m; rc=$?
[ "$rc" = 2 ] && ok "a report with no comments list does not count (rc 2)" || fail "malformed report counted (rc $rc)"
printf '{"comments":[]}\n' > "$TMP/rep/old.json"; python3 -c 'import os,sys,time; t=time.time()-3600; os.utime(sys.argv[1],(t,t))' "$TMP/rep/old.json"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t2 ".agents/devkit/bin/ocr-review"; ev result t2 ok "$(printf 'mode: review\nreport: %s' "$TMP/rep/old.json")"
stop n; rc=$?
[ "$rc" = 2 ] && ok "a report older than the edited file does not count (rc 2)" || fail "old report counted (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t2 "ocr review --format json"; ev result t2 ok '{"comments":[]}'
stop o; rc=$?
[ "$rc" = 2 ] && ok "a plain ocr review with no -o report file does not count (rc 2)" || fail "plain review without a report counted (rc $rc)"

# 4c. the delegation runs in the repo the gate checks (the cwd's git toplevel), not CLAUDE_PROJECT_DIR
N="$TMP/n"; mkdir -p "$N"; (cd "$N" && git init -q && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm i)
echo "def h(x): return 3 / x" > "$N/app.py"
: > "$TR"; ev edit t1 "$N/app.py"
printf '{"session_id":"s-p","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$TR" "$N" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P" OCR_PWD_LOG="$TMP/pwd.log" bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$TMP/pwd.log" 2>/dev/null)" = "$(cd "$N" && pwd -P)" ] && ok "the delegation ran in the checked repo (cwd toplevel)" \
  || fail "delegation ran in '$(cat "$TMP/pwd.log" 2>/dev/null)', want $N (rc $rc)"

# 5. `ocr` installed: an OCR review after the last edit is REQUIRED (user, 13/10: "open review code phải luôn luôn được chạy lại sau
#    bước subagent principal-code-reviewer" — the two find different defects). A fresh-context agent alone no longer passes.
: > "$TR"; ev edit t1 "$P/app.py"; ev agent t2 principal-code-reviewer
stop q; rc=$?
[ "$rc" = 2 ] && grep -q "ocr-review" "$TMP/err" && grep -q "principal-code-reviewer" "$TMP/err" \
  && ok "ocr installed, only principal-code-reviewer after the edit: blocked, told to run OCR (rc 2)" || fail "agent review alone passed with ocr installed (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev agent t2 principal-code-reviewer; ev bash t3 ".agents/devkit/bin/ocr-review"
ev result t3 ok "$(printf 'mode: review\nreport: %s' "$TMP/rep/ocr-review.json")"
stop r; rc=$?
[ "$rc" = 0 ] && ok "  … then an OCR review: passes (rc 0)" || fail "principal + OCR review still blocked (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 ".agents/devkit/bin/ocr-review --out $TMP/spec"; ev result t3 ok $'ocr review needs an LLM endpoint (no valid LLM endpoint configured); using OCR delegation mode (no LLM, no key)\nmode: delegate\nspec: '"$TMP/spec/ocr-spec.md"
ev agent t4 principal-code-reviewer
stop s; rc=$?
[ "$rc" = 0 ] && ok "  … no LLM endpoint (OCR fell back to its delegation spec) + an agent review after the edit: passes (rc 0)" \
  || fail "delegation fallback + agent review blocked (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 ".agents/devkit/bin/ocr-review --out $TMP/spec"
ev result t3 ok $'ocr review could not use its LLM endpoint (LLM endpoint unusable: every request rejected, 0 tokens): You have reached your specified API usage limits; using OCR delegation mode (no LLM, no key)\nmode: delegate\nspec: '"$TMP/spec/ocr-spec.md"
ev agent t4 principal-code-reviewer
stop s2; rc=$?
[ "$rc" = 0 ] && ok "  … an endpoint that rejects every request (usage limit): the same fallback + an agent review passes (rc 0)" \
  || fail "unusable-endpoint fallback + agent review blocked (rc $rc)"
: > "$TR"; ev bash t3 ".agents/devkit/bin/ocr-review --out $TMP/spec"
ev result t3 ok $'ocr review needs an LLM endpoint (no valid LLM endpoint configured); using OCR delegation mode (no LLM, no key)\nmode: delegate\nspec: '"$TMP/spec/ocr-spec.md"
ev edit t1 "$P/app.py"
ev agent t4 principal-code-reviewer
stop u; rc=$?
[ "$rc" = 2 ] && ok "  … a delegation run BEFORE the last edit does not count (rc 2)" || fail "stale delegation fallback counted (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 ".agents/devkit/bin/ocr-review --delegate-only"
ev result t3 ok $'ocr review needs an LLM endpoint (no valid LLM endpoint configured)\nmode: delegate\nspec: '"$TMP/spec/ocr-spec.md"
ev agent t4 principal-code-reviewer
stop x; rc=$?
[ "$rc" = 2 ] && ok "  … a --delegate-only run (it never asked the LLM) is no fallback (rc 2)" || fail "--delegate-only counted as the OCR fallback (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev agent t2 principal-code-reviewer
stop v REVIEW_GATE_REQUIRE_OCR=0; rc=$?
[ "$rc" = 0 ] && ok "  … REVIEW_GATE_REQUIRE_OCR=0: the agent review alone passes (rc 0)" || fail "REVIEW_GATE_REQUIRE_OCR=0 ignored (rc $rc)"
# review of this rule (13/10): what must NOT stand in for the OCR review
printf '{"status":"skipped","comments":[]}\n' > "$TMP/rep/skipped.json"
printf '{"status":"complete","summary":{"files_reviewed":0},"comments":[]}\n' > "$TMP/rep/zero.json"
for rp in skipped zero; do
  : > "$TR"; ev edit t1 "$P/app.py"; ev agent t2 principal-code-reviewer; ev bash t3 ".agents/devkit/bin/ocr-review"
  ev result t3 ok "$(printf 'mode: review\nreport: %s' "$TMP/rep/$rp.json")"
  stop "y$rp"; rc=$?
  [ "$rc" = 2 ] && ok "  … an OCR report that reviewed nothing ($rp: the code was committed first) is no review (rc 2)" || fail "$rp report counted (rc $rc)"
done
: > "$TR"; ev edit t1 "$P/app.py"; ev agent t2 principal-code-reviewer; ev bash t3 ".agents/devkit/bin/ocr-review --out $TMP/spec"
ev result t3 ok "$(printf '%s\nmode: delegate\nspec: %s' "ocr review needs an LLM endpoint (no valid LLM endpoint configured); using OCR delegation mode (no LLM, no key)" "$TMP/spec/ocr-spec.md")"
stop z1; rc=$?
[ "$rc" = 2 ] && ok "  … a delegation fallback AFTER the agent review (nobody read the spec) does not count (rc 2)" || fail "fallback after the agent counted (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 'echo "no valid LLM endpoint configured"; echo "mode: delegate"; true || ocr-review'
ev result t3 ok "$(printf 'no valid LLM endpoint configured\nmode: delegate')"; ev agent t4 principal-code-reviewer
stop z2; rc=$?
[ "$rc" = 2 ] && ok "  … echoed fallback words with no spec file do not count (rc 2)" || fail "echoed fallback counted (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 'echo "no valid LLM endpoint configured"; echo "mode: delegate"; true || ocr-review'
ev result t3 ok "$(printf 'no valid LLM endpoint configured\nmode: delegate\nspec: %s' "$P/app.py")"; ev agent t4 principal-code-reviewer
stop z3; rc=$?
[ "$rc" = 2 ] && ok "  … a 'spec' that is the edited file itself does not count (rc 2)" || fail "edited file accepted as the spec (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 ".agents/devkit/bin/ocr-review --out rel"
ev result t3 ok $'ocr review needs an LLM endpoint (no valid LLM endpoint configured); using OCR delegation mode (no LLM, no key)\nmode: delegate\nspec: rel/ocr-spec.md'
ev agent t4 principal-code-reviewer
printf '{"session_id":"s-z4","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$TR" "$P" \
  | (cd / && PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh") >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && ok "  … a fallback whose --out was relative: its spec is read against the session cwd (rc 0)" || fail "relative spec path rejected (rc $rc)"
# a forged fallback: a spec file made by hand and the fallback words echoed, the helper never run (`true || ocr-review`)
mkdir -p "$TMP/forge"; echo x > "$TMP/forge/ocr-spec.md"; python3 -c 'import os,sys,time; os.utime(sys.argv[1],(time.time()+5,)*2)' "$TMP/forge/ocr-spec.md"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 "echo no valid LLM endpoint configured; echo mode: delegate; echo spec: $TMP/forge/ocr-spec.md; true || ocr-review"
ev result t3 ok "$(printf 'no valid LLM endpoint configured\nmode: delegate\nspec: %s' "$TMP/forge/ocr-spec.md")"; ev agent t4 principal-code-reviewer
stop z5; rc=$?
[ "$rc" = 2 ] && ok "  … a hand-made spec with the words echoed and the helper short-circuited (true || ocr-review) does not count (rc 2)" \
  || fail "forged fallback counted (rc $rc)"
FBT="$(printf 'ocr review needs an LLM endpoint (no valid LLM endpoint configured)\nmode: delegate\nspec: %s' "$TMP/spec/ocr-spec.md")"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 "true || .agents/devkit/bin/ocr-review --out $TMP/spec"; ev result t3 ok "$FBT"; ev agent t4 principal-code-reviewer
stop z6; rc=$?
[ "$rc" = 2 ] && ok "  … the real spec folder but the helper behind || (it never ran): no (rc 2)" || fail "short-circuited helper counted (rc $rc)"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 ".agents/devkit/bin/ocr-review --out $TMP/other"; ev result t3 ok "$FBT"; ev agent t4 principal-code-reviewer
stop z7; rc=$?
[ "$rc" = 2 ] && ok "  … a spec outside the run's own --out folder: no (rc 2)" || fail "spec outside --out counted (rc $rc)"
mkdir -p "$TMP/ocr-review.real"; chmod 700 "$TMP/ocr-review.real"; echo x > "$TMP/ocr-review.real/ocr-spec.md"
python3 -c 'import os,sys,time; os.utime(sys.argv[1],(time.time()+5,)*2)' "$TMP/ocr-review.real/ocr-spec.md"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 ".agents/devkit/bin/ocr-review"
ev result t3 ok "$(printf 'ocr review needs an LLM endpoint (no valid LLM endpoint configured)\nmode: delegate\nspec: %s' "$TMP/ocr-review.real/ocr-spec.md")"
ev agent t4 principal-code-reviewer
stop z9; rc=$?
[ "$rc" = 0 ] && ok "  … the helper's own default folder (private ocr-review.*, no --out): the fallback counts (rc 0)" || fail "default fallback folder rejected (rc $rc)"
mkdir -p "$TMP/ocr-review.byhand"; chmod 755 "$TMP/ocr-review.byhand"; echo x > "$TMP/ocr-review.byhand/ocr-spec.md"
python3 -c 'import os,sys,time; os.utime(sys.argv[1],(time.time()+5,)*2)' "$TMP/ocr-review.byhand/ocr-spec.md"
: > "$TR"; ev edit t1 "$P/app.py"; ev bash t3 ".agents/devkit/bin/ocr-review"
ev result t3 ok "$(printf 'ocr review needs an LLM endpoint (no valid LLM endpoint configured)\nmode: delegate\nspec: %s' "$TMP/ocr-review.byhand/ocr-spec.md")"
ev agent t4 principal-code-reviewer
stop z8; rc=$?
[ "$rc" = 2 ] && ok "  … a hand-made ocr-review.* folder (not the helper's private 0700 one): no (rc 2)" || fail "hand-made ocr-review.* folder counted (rc $rc)"
# code committed after the verified head (since): a workspace OCR run sees none of it; only a run over that range counts
C="$TMP/c"; mkdir -p "$C/.claude/audit-gate"; (cd "$C" && git init -q && git config user.email t@t && git config user.name t \
  && echo "def g(x): return x" > app.py && git add app.py && git commit -qm i)
printf '{"verified_head": "%s"}\n' "$(git -C "$C" rev-parse HEAD)" > "$C/.claude/audit-gate/regression_gate.state.json"
echo "def g(x): return 2 / x" > "$C/app.py" && git -C "$C" commit -qam "committed before the review"
printf '{"comments":[]}\n' > "$TMP/rep/c.json"
python3 -c 'import os,sys,time; [os.utime(f,(time.time()+5,)*2) for f in sys.argv[1:]]' "$TMP/rep/c.json" "$TMP/spec/ocr-spec.md"   # newer than this app.py
crun() { printf '{"session_id":"s-%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$1" "$TR" "$C" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$C" bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"; }
: > "$TR"; ev edit t1 "$C/app.py"; ev agent t2 principal-code-reviewer
crun c1; rc=$?
[ "$rc" = 2 ] && grep -q -- "--from $(git -C "$C" rev-parse --short=12 HEAD~1)" "$TMP/err" && ! grep -q 'out <thư mục tạm>$' "$TMP/err" \
  && ok "committed code: the block names the --from run only (no workspace run: nothing is dirty)" || fail "committed code message: rc $rc $(grep ocr-review "$TMP/err")"
ev bash t3 ".agents/devkit/bin/ocr-review"; ev result t3 ok "$(printf 'mode: review\nreport: %s' "$TMP/rep/c.json")"
crun c2; rc=$?
[ "$rc" = 2 ] && ok "  … a workspace OCR report alone does not cover the committed code (rc 2)" || fail "workspace report counted for committed code (rc $rc)"
for cmd in ".agents/devkit/bin/ocr-review --from=abc" "bash -c 'cd x; .agents/devkit/bin/ocr-review'" "git -c core.x=1 status; .agents/devkit/bin/ocr-review"; do
  : > "$TR"; ev edit t1 "$C/app.py"; ev agent t2 principal-code-reviewer; ev bash t4 "$cmd"; ev result t4 ok "$(printf 'mode: review\nreport: %s' "$TMP/rep/c.json")"
  crun c4; rc=$?
  [ "$rc" = 2 ] && ok "  … '$cmd' is no run over the committed range (rc 2)" || fail "'$cmd' read as a ranged run (rc $rc)"
done
: > "$TR"; ev edit t1 "$C/app.py"; ev agent t2 principal-code-reviewer
ev bash t4 ".agents/devkit/bin/ocr-review --from $(git -C "$C" rev-parse HEAD~1) --to HEAD"; ev result t4 ok "$(printf 'mode: review\nreport: %s' "$TMP/rep/c.json")"
crun c3; rc=$?
[ "$rc" = 0 ] && ok "  … an OCR report over the committed range does (rc 0)" || fail "ranged report not counted (rc $rc)"
: > "$TR"; ev edit t1 "$C/app.py"; ev agent t2 principal-code-reviewer
ev bash t4 ".agents/devkit/bin/ocr-review --from HEAD --to HEAD"; ev result t4 ok "$(printf 'mode: review\nreport: %s' "$TMP/rep/c.json")"
crun c5; rc=$?
[ "$rc" = 2 ] && ok "  … a --from newer than the verified head covers only part of it: no (rc 2)" || fail "--from HEAD counted for the committed range (rc $rc)"
: > "$TR"; ev edit t1 "$C/app.py"; ev agent t2 principal-code-reviewer
ev bash t4 ".agents/devkit/bin/ocr-review -c HEAD"; ev result t4 ok "$(printf 'mode: review\nreport: %s' "$TMP/rep/c.json")"
crun c6; rc=$?
[ "$rc" = 0 ] && ok "  … -c HEAD when the one commit since the verified head is HEAD: covers it (rc 0)" || fail "-c HEAD over the whole range not counted (rc $rc)"
: > "$TR"; ev edit t1 "$C/app.py"; ev agent t2 principal-code-reviewer
ev bash t4 "true || .agents/devkit/bin/ocr-review --from $(git -C "$C" rev-parse HEAD~1) --to HEAD"; ev result t4 ok "$(printf 'mode: review\nreport: %s' "$TMP/rep/c.json")"
crun c7; rc=$?
[ "$rc" = 2 ] && ok "  … a report named by a helper behind || (it never ran): no (rc 2)" || fail "short-circuited report counted (rc $rc)"
CFB="$(printf 'ocr review needs an LLM endpoint (no valid LLM endpoint configured)\nmode: delegate\nspec: %s' "$TMP/spec/ocr-spec.md")"
: > "$TR"; ev edit t1 "$C/app.py"; ev bash t3 ".agents/devkit/bin/ocr-review --out $TMP/spec"; ev result t3 ok "$CFB"; ev agent t4 principal-code-reviewer
crun c8; rc=$?
[ "$rc" = 2 ] && ok "  … no endpoint: a workspace fallback spec does not cover the committed code either (rc 2)" || fail "workspace fallback counted for committed code (rc $rc)"
: > "$TR"; ev edit t1 "$C/app.py"; ev bash t3 ".agents/devkit/bin/ocr-review --from $(git -C "$C" rev-parse HEAD~1) --to HEAD --out $TMP/spec"
ev result t3 ok "$CFB"; ev agent t4 principal-code-reviewer
crun c9; rc=$?
[ "$rc" = 0 ] && ok "  … a fallback over the committed range does (rc 0)" || fail "ranged fallback not counted (rc $rc)"
if [ -x /usr/bin/ocr ] || [ -x /bin/ocr ]; then ok "SKIP no-ocr case: this host has ocr in /usr/bin or /bin"; else
mkdir -p "$TMP/noocr"; for x in git python3; do ln -sf "$(command -v "$x")" "$TMP/noocr/$x"; done
: > "$TR"; ev edit t1 "$P/app.py"; ev agent t2 principal-code-reviewer
printf '{"session_id":"s-w","transcript_path":"%s","hook_event_name":"Stop"}' "$TR" \
  | PATH="$TMP/noocr:/usr/bin:/bin" CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && ok "no ocr installed: the agent review alone passes, as before (rc 0)" || fail "no ocr installed, agent review blocked (rc $rc)"
fi

# 3. a hung ocr: still blocked, well inside the hook's 20 s
: > "$TR"; ev edit t9 "$P/app.py"
t0="$(python3 -c 'import time; print(time.time())')"
stop i OCR_HANG=1; rc=$?
secs="$(python3 -c "import time; print(round(time.time() - $t0, 1))")"
[ "$rc" = 2 ] && python3 -c "import sys; sys.exit(0 if $secs < 15 else 1)" && ok "a hung ocr: blocked in ${secs}s (< 15 s of the hook's 20 s)" \
  || fail "a hung ocr: rc $rc after ${secs}s (want rc 2 in < 15 s)"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
