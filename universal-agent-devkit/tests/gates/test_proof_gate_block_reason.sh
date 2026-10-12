#!/usr/bin/env bash
# Regression test: hooks/proof_gate.sh (Stop hook) logs WHY it blocked. 2026-10-12 measurement: OfficeReader 14 of 35 Stop blocks
# came from proof_gate, but the log line said only `block session=... attempt=N cited=... gate=ok`, so a block for a missing
# report, a missing image or a stale gate could not be told apart (and a false block could not be found). The line now carries
# report=<missing item numbers or ok>, before=<count of "before" problems> and image=<need|ok>; the block messages are unchanged.
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
stop() {
  local reply="$1"; shift
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-why-"+sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "$reply" "$N" \
  | env "$@" CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$ROOT/out" 2>"$ROOT/err"
  RC=$?
  if grep -q Traceback "$ROOT/err"; then RC=99; fi
}
LOG="$REPO/.claude/audit-gate/proof_gate.log"
blockline() { grep "block session=s-why-$N " "$LOG" 2>/dev/null | tail -1; }
LAST="Đã push lên origin/main."

# (a) the FINAL reply lacks item 3 (the hook counts the final reply): the log names item 3
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"; ev text 12 "$TR" "ok"
stop "$L1
$L2
$L4" A=1
line="$(blockline)"
[ "$RC" = 2 ] && ok "(a) blocked (rc 2)" || fail "(a) not blocked (rc=$RC)"
case "$line" in *" report=3 "*) ok "(a) log names the missing item: $line" ;; *) fail "(a) log does not name item 3: '$line'" ;; esac

# (b) two items missing: both named
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"; ev text 12 "$TR" "ok"
stop "$L1
$L4" A=1
line="$(blockline)"
case "$line" in *" report=2,3 "*) ok "(b) log names both missing items: $line" ;; *) fail "(b) log does not name items 2,3: '$line'" ;; esac

# (c) no report at all: all four named, and the line still carries the old fields
newcase; ev bash 10 "$TR" p1 "git push origin main"; ev result 11 "$TR" p1 "$PUSH_OK"
stop "$LAST" A=1
line="$(blockline)"
case "$line" in *" report=1,2,3,4 "*) ok "(c) no report: all four named" ;; *) fail "(c) log does not name 1,2,3,4: '$line'" ;; esac
case "$line" in *" attempt="*" cited="*" gate="*) ok "(c) old fields kept (attempt, cited, gate)" ;; *) fail "(c) old fields lost: '$line'" ;; esac
case "$line" in *" before="*" image="*) ok "(c) image= and before= present" ;; *) fail "(c) image=/before= missing: '$line'" ;; esac

# (d) the block message itself is unchanged: it still names the report
grep -q "4 mục" "$ROOT/err" && ok "(d) stderr message still names the 4-item report" || fail "(d) stderr message changed"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
