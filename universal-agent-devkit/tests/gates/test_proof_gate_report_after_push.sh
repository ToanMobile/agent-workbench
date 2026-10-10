#!/usr/bin/env bash
# Regression test: hooks/proof_gate.sh (Stop hook) — a turn that ran a successful `git push` and does not open
# with XONG needs the 4-item acceptance report (core-rules §1.3). 2026-10-10 measurement: 41 of 79 blocks in push
# turns (52%) were avoidable — the report was already in an assistant message written right AFTER the push and the
# final reply only said "pushed". The hook now accepts ONE assistant text message, after the LAST successful push of
# the turn (transcript order), that carries all 4 items. Everything else stays blocked:
#   - the report only BEFORE the push, or missing one item, or its items spread over several messages;
#   - a report that sits in a thinking block, a tool result, a sidechain (subagent) line or an earlier turn;
#   - a report between two successful pushes (it does not follow the last one);
#   - an XONG reply (it must carry the report itself);
#   - PROOF_REPORT_AFTER_PUSH=0 (the old behaviour, a rollback switch).
# Each case builds its own transcript with fixed timestamps (no sleeps) and a fresh session id.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
ROOT="$(mktemp -d)" || exit 1
trap 'rm -rf "$ROOT"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

REPO="$ROOT/repo"; mkdir -p "$REPO"
( cd "$REPO" && git init -q . && git config user.email t@t && git config user.name t \
  && echo "x" > a.txt && git add -A && git commit -qm init ) || { echo "fixture repo failed"; exit 1; }

# One transcript line: ev <kind> <offset seconds> <transcript> [args]. The base time is 200 s ago, so the hook sees finished events.
cat > "$ROOT/ev.py" <<'PY'
import datetime, json, sys
kind, off, tr = sys.argv[1], float(sys.argv[2]), sys.argv[3]
args = sys.argv[4:]
base = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=200)
t = (base + datetime.timedelta(seconds=off)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
def asst(block, side=False):
    e = {"type": "assistant", "timestamp": t, "message": {"role": "assistant", "content": [block]}}
    if side:
        e["isSidechain"] = True
    return e
if kind == "prompt":
    e = {"type": "user", "timestamp": t, "message": {"role": "user", "content": args[0]}}
elif kind == "bash":
    e = asst({"type": "tool_use", "id": args[0], "name": "Bash", "input": {"command": args[1]}})
elif kind == "result":
    e = {"type": "user", "timestamp": t, "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": args[0], "is_error": False, "content": args[1]}]}}
elif kind == "text":
    e = asst({"type": "text", "text": args[0]}, side=len(args) > 1 and args[1] == "side")
elif kind == "thinking":
    e = asst({"type": "thinking", "thinking": args[0]})
elif kind == "weird":   # a line the hook must survive: it holds the word "text" but not the shape of a message
    shape = args[0]
    if shape == "msgstr":
        e = {"type": "assistant", "timestamp": t, "message": "text"}
    elif shape == "contentnum":
        e = {"type": "assistant", "timestamp": t, "message": {"role": "assistant", "content": 5, "note": "text"}}
    elif shape == "textnum":
        e = asst({"type": "text", "text": 5})
    else:
        sys.exit("unknown shape " + shape)
elif kind == "metatext":   # what the harness writes after a Stop-hook block: a user-role, isMeta line with the hook's stderr
    e = {"type": "user", "isMeta": True, "timestamp": t, "message": {"role": "user", "content": [{"type": "text", "text": args[0]}]}}
else:
    sys.exit("unknown kind " + kind)
with open(tr, "a", encoding="utf-8") as f:
    f.write(json.dumps(e, ensure_ascii=False) + "\n")
PY
ev() { python3 "$ROOT/ev.py" "$@"; }

L1="1. Đã fix: lỗi X, RED→GREEN."
L2="2. Chặn bug cũ: REG-1 [x] PASS."
L3="3. Nguy cơ bug mới: đã rà caller, không tác dụng phụ."
L4="4. An toàn mã nguồn: secret 0, placeholder 0."
REPORT="$L1
$L2
$L3
$L4"
PUSH_OK="To github.com:x/y.git
   86f7ddc..a94c071  main -> main"
PUSH_REJECTED="! [rejected]        main -> main (fetch first)
error: failed to push some refs to 'github.com:x/y.git'"

N=0
TR=""
newcase() { N=$((N + 1)); TR="$ROOT/t$N.jsonl"; : > "$TR"; ev prompt 0 "$TR" "đẩy lên origin"; }
# The Stop payload: <final reply> [extra env as NAME=value]. Sets RC; stderr in $ROOT/err, hook log in the repo.
stop() {
  local reply="$1"; shift
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-rap-"+sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "$reply" "$N" \
  | env "$@" CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$ROOT/out" 2>"$ROOT/err"
  RC=$?
  # A crash of the hook's Python exits 1 and the wrapper turns that into exit 0 = the stop goes through. It must show as a failure here.
  if grep -q Traceback "$ROOT/err"; then RC=99; fi
}
# The pass this case's own session logged (a pass by the report-after-push route, not by some other route).
logged() { grep -q "session=s-rap-$N report-after-push" "$LOG" 2>/dev/null; }
LAST="Đã push lên origin/main."
LOG="$REPO/.claude/audit-gate/proof_gate.log"

# (a) the case the change is for: push, the report in the next message, more work, a short final reply.
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"
ev text 12 "$TR" "Đã push. $REPORT"; ev bash 13 "$TR" b1 "ls"; ev result 14 "$TR" b1 "a.txt"; ev text 15 "$TR" "Xong phần việc."
stop "$LAST" A=1
[ "$RC" = 0 ] && logged \
  && ok "(a) report in the message after the push, short final reply: allowed, logged" \
  || fail "(a) report after push not accepted (rc=$RC err=$(head -2 "$ROOT/err" | tr '\n' ' '))"

# (e) the rollback switch gives the old behaviour on the same transcript.
stop "$LAST" PROOF_REPORT_AFTER_PUSH=0
[ "$RC" = 2 ] && grep -q "4 mục" "$ROOT/err" \
  && ok "(e) PROOF_REPORT_AFTER_PUSH=0: blocked as before, names the report" || fail "(e) switch ignored (rc=$RC)"

# (b) the report only BEFORE the push.
newcase; ev text 5 "$TR" "$REPORT"; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"
stop "$LAST" A=1
[ "$RC" = 2 ] && grep -q "4 mục" "$ROOT/err" && ok "(b) report only before the push: blocked" || fail "(b) pre-push report accepted (rc=$RC)"

# (c) each of the 4 items missing in turn.
for drop in 1 2 3 4; do
  part=""; for i in 1 2 3 4; do [ "$i" = "$drop" ] && continue; eval "line=\$L$i"; part="$part$line
"; done
  newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"; ev text 12 "$TR" "$part"
  stop "$LAST" A=1
  [ "$RC" = 2 ] && ok "(c$drop) report without item $drop: blocked" || fail "(c$drop) incomplete report accepted (rc=$RC)"
done

# (c5) the 4 items spread over two messages: no single message carries all 4.
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"
ev text 12 "$TR" "$L1
$L2"; ev text 13 "$TR" "$L3
$L4"
stop "$LAST" A=1
[ "$RC" = 2 ] && ok "(c5) items spread over two messages: blocked" || fail "(c5) split report accepted (rc=$RC)"

# (d) an XONG reply must carry the report itself, whatever was written after the push.
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"; ev text 12 "$TR" "$REPORT"
stop "XONG
Đã push." A=1
[ "$RC" = 2 ] && grep -q "4 mục" "$ROOT/err" && ok "(d) XONG without its own report: blocked, names it" || fail "(d) XONG accepted on an earlier report (rc=$RC)"

# (f) the report only in a subagent (sidechain) line.
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"; ev text 12 "$TR" "$REPORT" side
stop "$LAST" A=1
[ "$RC" = 2 ] && ok "(f) report in a sidechain line: blocked" || fail "(f) sidechain report accepted (rc=$RC)"

# (g1) the report sits between two successful pushes: it does not follow the last one.
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"; ev text 12 "$TR" "$REPORT"
ev bash 20 "$TR" p2 "git push origin main"; ev result 21 "$TR" p2 "$PUSH_OK"
stop "$LAST" A=1
[ "$RC" = 2 ] && ok "(g1) report before the second successful push: blocked" || fail "(g1) report before the last push accepted (rc=$RC)"

# (g2) the second push was rejected: the last SUCCESSFUL push is the first, and the report follows it.
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"; ev text 12 "$TR" "$REPORT"
ev bash 20 "$TR" p2 "git push origin main"; ev result 21 "$TR" p2 "$PUSH_REJECTED"
stop "$LAST" A=1
[ "$RC" = 0 ] && logged && ok "(g2) a rejected second push does not move the point the report must follow" || fail "(g2) report after the last good push refused (rc=$RC)"

# (s) two pushes, each followed by its own report: the LAST report follows the last push (taking the first report would block).
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"; ev text 12 "$TR" "$REPORT"
ev bash 20 "$TR" p2 "git push origin main"; ev result 21 "$TR" p2 "$PUSH_OK"; ev text 22 "$TR" "$REPORT"
stop "$LAST" A=1
[ "$RC" = 0 ] && logged && ok "(s) a report after each of two pushes: allowed" || fail "(s) the report after the last push was not used (rc=$RC)"

# (h) the push and the report of an EARLIER turn do not count for a new push without a report.
newcase; ev bash 1 "$TR" p0 "git push origin main"; ev result 2 "$TR" p0 "$PUSH_OK"; ev text 3 "$TR" "$REPORT"
ev prompt 10 "$TR" "đẩy tiếp"; ev bash 11 "$TR" p1 "git push origin main"; ev result 12 "$TR" p1 "$PUSH_OK"
stop "$LAST" A=1
[ "$RC" = 2 ] && ok "(h) report of an earlier turn: blocked" || fail "(h) earlier turn's report accepted (rc=$RC)"

# (j) a report text that is not an assistant reply: a tool result (a cat of this very report) or a thinking block.
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"
ev bash 12 "$TR" b1 "cat report.md"; ev result 13 "$TR" b1 "$REPORT"
stop "$LAST" A=1
[ "$RC" = 2 ] && ok "(j1) report text only inside a tool result: blocked" || fail "(j1) tool result counted as a report (rc=$RC)"
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"; ev thinking 12 "$TR" "$REPORT"
stop "$LAST" A=1
[ "$RC" = 2 ] && ok "(j2) report text only in a thinking block: blocked" || fail "(j2) thinking block counted as a report (rc=$RC)"

# (q) the block's own feedback: after a block the harness writes the hook's stderr as a user-role line, and that text holds the
# skeleton "1. Đã fix gì: … 2. Chặn bug cũ: … 3. Nguy cơ bug mới: … 4. An toàn mã nguồn: …" — all 4 items. It is no report: without the
# assistant-role check the second Stop after a block would let a reply without a report through.
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"
stop "$LAST" A=1
first=$RC
ev metatext 12 "$TR" "$(cat "$ROOT/err")"
stop "$LAST" A=1
[ "$first" = 2 ] && [ "$RC" = 2 ] && ok "(q) the hook's own feedback (skeleton, user role) is not a report: second stop still blocked" \
  || fail "(q) hook feedback counted as a report (first=$first second=$RC)"

# (m) a push with no result line, and one sent to the background: still a push whose report may follow.
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev text 11 "$TR" "$REPORT"
stop "$LAST" A=1
[ "$RC" = 0 ] && logged && ok "(m1) push with no result found, report after it: allowed" || fail "(m1) no-result push (rc=$RC)"
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "Command running in background with ID: b1. Output is being written to: /tmp/x"
ev text 12 "$TR" "$REPORT"
stop "$LAST" A=1
[ "$RC" = 0 ] && logged && ok "(m2) background push, report after it: allowed" || fail "(m2) background push (rc=$RC)"

# (r) a line after the push that holds the word "text" but is not a message (a string message, a numeric content, a numeric text) must not
# crash the hook: a crash is exit 0 = a stop without the report goes through. 2026-10-10 review: the new "text" pre-filter let such lines
# reach code that assumed a message object.
for shape in msgstr contentnum textnum; do
  newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"; ev weird 12 "$TR" "$shape"
  stop "$LAST" A=1
  [ "$RC" = 2 ] && grep -q "4 mục" "$ROOT/err" && ok "(r $shape) an odd line after the push: no crash, still blocked" || fail "(r $shape) odd line after the push (rc=$RC err=$(head -2 "$ROOT/err" | tr '\n' ' '))"
done
# and the report is still found next to such a line
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"; ev weird 12 "$TR" msgstr; ev text 13 "$TR" "$REPORT"
stop "$LAST" A=1
[ "$RC" = 0 ] && logged && ok "(r) an odd line before the report does not hide it" || fail "(r) report after an odd line not found (rc=$RC)"

# (n) a report written between the push call and its result was written before the outcome was known.
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev text 11 "$TR" "$REPORT"; ev result 12 "$TR" p1 "$PUSH_OK"
stop "$LAST" A=1
[ "$RC" = 2 ] && ok "(n) report written before the push result: blocked" || fail "(n) report before the push result accepted (rc=$RC)"

# (k) control: no push at all and no report is not a handover.
newcase; ev bash 10 "$TR" b1 "ls"; ev result 11 "$TR" b1 "a.txt"
stop "Trả lời câu hỏi." A=1
[ "$RC" = 0 ] && ok "(k) no push, no report: not checked" || fail "(k) plain answer blocked (rc=$RC)"

# (p) control: the final reply carries the report itself — the old path, unchanged.
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"
stop "$LAST
$REPORT" A=1
[ "$RC" = 0 ] && ok "(p) report in the final reply: allowed" || fail "(p) own report refused (rc=$RC)"

if [ "$FAILS" -ne 0 ]; then echo "proof gate report-after-push: $FAILS FAILED"; exit 1; fi
echo "proof gate report-after-push: all passed"
