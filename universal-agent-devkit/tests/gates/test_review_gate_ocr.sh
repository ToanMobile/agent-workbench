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

# 3. a hung ocr: still blocked, well inside the hook's 20 s
: > "$TR"; ev edit t9 "$P/app.py"
t0="$(python3 -c 'import time; print(time.time())')"
stop i OCR_HANG=1; rc=$?
secs="$(python3 -c "import time; print(round(time.time() - $t0, 1))")"
[ "$rc" = 2 ] && python3 -c "import sys; sys.exit(0 if $secs < 15 else 1)" && ok "a hung ocr: blocked in ${secs}s (< 15 s of the hook's 20 s)" \
  || fail "a hung ocr: rc $rc after ${secs}s (want rc 2 in < 15 s)"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
