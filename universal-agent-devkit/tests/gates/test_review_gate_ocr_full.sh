#!/usr/bin/env bash
# hooks/review_gate.sh REVIEW_GATE_OCR=full (2026-10-13, user: "làm công tắc REVIEW_GATE_OCR=full luôn đi"): a full OpenCodeReview
# (LLM, ~80 s with Opus) on every review the gate asks for. The hook may run 20 s (hooks.json), so the full review runs in the
# BACKGROUND, once per state of the unreviewed code (a hash of those files), shared by sessions:
#   Stop 1  unreviewed code, no report yet -> starts `bin/ocr-review --out <repo>/.git/ocr-review/full-<hash>` detached, blocks at
#           once (the delegation spec as before) and says the full review is running;
#   Stop 2  the report is there -> blocks with the findings (file:line, severity, text) and records that THIS session saw them;
#   Stop 3  same code, findings shown to this session -> counts as the fresh review (rc 0).
# Code changed again -> a new hash, a new background review. A run that ends without a report (no endpoint, error) falls back to the
# delegation spec and never passes the gate. Default (no switch): no full review is ever started.
# OpenCodeReview of this mode (13/10): a report without a `comments` list is no review; a pid file older than the helper's own
# bound is not "running"; two Stops at once start ONE run (the pid file is claimed with O_EXCL); old full-* runs are pruned (the
# newest 10 stay); code committed past verified_head (`since`) is not in a workspace review, so no pass while there is any.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo x > a && git add a && git commit -qm i)
echo "def f(x): return 1 / x" > "$P/app.py"

# fake ocr: OCR_FAKE=ok (review after 3 s, one finding) | noendpoint (the usual error) | nocomments (no comments list) | hang
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<'SH'
#!/bin/sh
case "$1 $2" in
  "review "*)
    if [ "$OCR_FAKE" = noendpoint ]; then echo "Error: resolve LLM endpoint: no valid LLM endpoint configured" >&2; exit 1; fi
    out=""; prev=""; for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
    [ -n "${OCR_RUNS:-}" ] && echo run >> "$OCR_RUNS"
    [ "$OCR_FAKE" = hang ] && sleep 60
    sleep 3
    [ "$OCR_FAKE" = nocomments ] && { printf '{"error":"partial"}\n' > "$out"; exit 0; }
    printf '{"comments":[{"path":"app.py","start_line":1,"severity":"high","content":"division by zero when x == 0"}]}\n' > "$out"; exit 0 ;;
  "delegate preview") printf '{"schema_version":"1","reviewable_count":1,"reviewable_files":[{"path":"app.py","status":"added","insertions":1,"deletions":0}]}\n'; exit 0 ;;
  "delegate rule") printf '{"schema_version":"1","groups":[{"group_id":1,"files":["app.py"],"rule":"ZeroDivisionError"}]}\n'; exit 0 ;;
esac
exit 9
SH
chmod +x "$TMP/bin/ocr"

TR="$TMP/t.jsonl"
edit_tr() { python3 -c 'import json,sys; print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":sys.argv[1],"content":"x"}}]}}))' "$P/app.py" > "$TR"; }
stop() {   # stop <session> <mode> <fake>
  local t0 t1
  t0="$(python3 -c 'import time; print(time.time())')"
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop"}' "$1" "$TR" \
    | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P" REVIEW_GATE_OCR="$2" OCR_FAKE="$3" bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"
  RC=$?
  t1="$(python3 -c 'import time; print(time.time())')"
  SECS="$(python3 -c "print(round($t1 - $t0, 2))")"
}
report_ready() { local r="${1:-$P}"; for _ in $(seq 1 100); do ls "$r"/.git/ocr-review/full-*/ocr-review.json >/dev/null 2>&1 && return 0; sleep 0.2; done; return 1; }
newrepo() { mkdir -p "$1"; (cd "$1" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo x > a && git add a && git commit -qm i); }
edit_of() { python3 -c 'import json,sys; print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":sys.argv[1],"content":"x"}}]}}))' "$1" > "$TR"; }
stop_in() {   # stop_in <repo> <session> <fake>
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop"}' "$2" "$TR" \
    | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$1" REVIEW_GATE_OCR=full OCR_FAKE="$3" REVIEW_GATE_MAX_ATTEMPTS=99 \
      bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"; RC=$?; }

# default: no full review is ever started
edit_tr; stop d1 1 ok
[ "$RC" = 2 ] && ! ls "$P"/.git/ocr-review/full-* >/dev/null 2>&1 && ok "default switch: blocked, no full review started" \
  || fail "default: rc $RC, full dir: $(ls "$P"/.git/ocr-review 2>/dev/null | tr '\n' ' ')"

# full: stop 1 starts the background review and returns at once
stop s1 full ok
[ "$RC" = 2 ] && grep -qi 'nền' "$TMP/err" && ok "full, stop 1: blocked, says the full OCR review runs in the background" \
  || fail "stop 1: rc $RC err=$(tail -3 "$TMP/err" | tr '\n' ' ')"
! ls "$P"/.git/ocr-review/full-*/ocr-review.json >/dev/null 2>&1 && ok "stop 1 returned before the review ended (${SECS}s; it does not wait)" \
  || fail "stop 1 waited for the review (${SECS}s)"
report_ready && ok "the background review wrote its report" || fail "no report after 10 s"

# stop 2: the findings are shown
stop s1 full ok
[ "$RC" = 2 ] && grep -q 'division by zero when x == 0' "$TMP/err" && grep -q 'app.py' "$TMP/err" \
  && ok "full, stop 2: blocked with the OCR findings" || fail "stop 2: rc $RC err=$(tail -4 "$TMP/err" | tr '\n' ' ')"

# another session has not seen them: it is shown them too (no pass on someone else's reading)
stop s2 full ok
[ "$RC" = 2 ] && grep -q 'division by zero' "$TMP/err" && ok "another session is shown the findings, not passed" || fail "session s2: rc $RC"

# stop 3: same code, findings already shown to s1 -> counts as the review
stop s1 full ok
[ "$RC" = 0 ] && ok "full, stop 3: findings shown, code unchanged -> counts as the review (rc 0)" || fail "stop 3: rc $RC"

# code changed again: a new review, no pass on the old one
echo "def f(x): return 2 / x" > "$P/app.py"
stop s1 full ok
n="$(ls -d "$P"/.git/ocr-review/full-* | wc -l | tr -d ' ')"
[ "$RC" = 2 ] && [ "$n" = 2 ] && ok "code changed: blocked, a second background review started ($n runs)" || fail "after a change: rc $RC runs $n"

# a run with no endpoint ends without a report: delegation spec, never a pass
P2="$TMP/p2"; mkdir -p "$P2"; (cd "$P2" && git init -q && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm i)
echo "def g(): return 1" > "$P2/app.py"
python3 -c 'import json,sys; print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":sys.argv[1],"content":"x"}}]}}))' "$P2/app.py" > "$TR"
for i in 1 2 3; do
  printf '{"session_id":"n1","transcript_path":"%s","hook_event_name":"Stop"}' "$TR" \
    | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P2" REVIEW_GATE_OCR=full OCR_FAKE=noendpoint REVIEW_GATE_MAX_ATTEMPTS=9 bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"
  RC=$?; sleep 1
done
[ "$RC" = 2 ] && grep -q 'ocr-spec.md' "$TMP/err" && ok "no endpoint: still blocked, the delegation spec offered" || fail "no endpoint: rc $RC err=$(tail -3 "$TMP/err" | tr '\n' ' ')"

# a report without a comments list: never counted
P3="$TMP/p3"; newrepo "$P3"; echo "def k(x): return 4 / x" > "$P3/app.py"; edit_of "$P3/app.py"
stop_in "$P3" c1 nocomments; report_ready "$P3"; stop_in "$P3" c1 nocomments; stop_in "$P3" c1 nocomments
[ "$RC" = 2 ] && ok "a report with no comments list never passes (rc 2)" || fail "malformed report passed (rc $RC)"

# a pid file older than the helper's bound is not "running"
P5="$TMP/p5"; newrepo "$P5"; echo "def m(x): return 5 / x" > "$P5/app.py"; edit_of "$P5/app.py"
stop_in "$P5" h1 hang; pidf="$(ls "$P5"/.git/ocr-review/full-*/pid 2>/dev/null | head -1)"
python3 -c 'import os,sys,time; t=time.time()-7200; os.utime(sys.argv[1],(t,t))' "$pidf" 2>/dev/null
stop_in "$P5" h1 hang
! grep -q 'đang chạy ở nền' "$TMP/err" && [ "$RC" = 2 ] && ok "a 2 h old pid file is not reported as running (rc 2)" \
  || fail "stale pid still 'running' (rc $RC)"
kill -9 -- "-$(cat "$pidf" 2>/dev/null)" 2>/dev/null

# two Stops at once start one run
P7="$TMP/p7"; newrepo "$P7"; echo "def q(x): return 7 / x" > "$P7/app.py"; edit_of "$P7/app.py"; : > "$TMP/runs"
for s in r1 r2 r3; do
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop"}' "$s" "$TR" \
    | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P7" REVIEW_GATE_OCR=full OCR_FAKE=ok OCR_RUNS="$TMP/runs" bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>&1 &
done; wait; report_ready "$P7"; sleep 1
[ "$(wc -l < "$TMP/runs" | tr -d ' ')" = 1 ] && ok "three Stops at once: one background review" || fail "concurrent Stops started $(wc -l < "$TMP/runs" | tr -d ' ') reviews"

# old runs are pruned: the newest 10 stay
P4="$TMP/p4"; newrepo "$P4"; mkdir -p "$P4/.git/ocr-review"
for i in $(seq 10 21); do mkdir -p "$P4/.git/ocr-review/full-old$i"; touch -t "2026010112$i" "$P4/.git/ocr-review/full-old$i"; done
echo "def r(x): return 8 / x" > "$P4/app.py"; edit_of "$P4/app.py"; stop_in "$P4" p1 ok
n="$(ls -d "$P4"/.git/ocr-review/full-* | wc -l | tr -d ' ')"
[ "$n" -le 10 ] && [ ! -e "$P4/.git/ocr-review/full-old10" ] && ok "13 runs pruned to $n (oldest gone)" || fail "no pruning: $n runs"

# code committed past verified_head is not in a workspace review: no pass
P6="$TMP/p6"; newrepo "$P6"; base="$(git -C "$P6" rev-parse HEAD)"
mkdir -p "$P6/.claude/audit-gate"; printf '{"verified_head":"%s"}\n' "$base" > "$P6/.claude/audit-gate/regression_gate.state.json"
echo "def s(x): return 9 / x" > "$P6/app.py"; git -C "$P6" add app.py; git -C "$P6" commit -qm wip; edit_of "$P6/app.py"
stop_in "$P6" v1 ok; report_ready "$P6"; stop_in "$P6" v1 ok; stop_in "$P6" v1 ok
[ "$RC" = 2 ] && ok "committed code past verified_head: the full review does not pass it (rc 2)" || fail "since files passed by a workspace review (rc $RC)"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
