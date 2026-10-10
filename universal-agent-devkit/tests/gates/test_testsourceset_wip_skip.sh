#!/usr/bin/env bash
# Regression test: hooks/testsourceset_gate.sh does not compile the test source sets on a stop that is only the middle of the work
# (DevKit backlog #3; user 2026-10-10 "làm hết đi", the extension of Dot 11 that regression_gate already has: "chỉ test khi bàn giao").
# 2026-10-09..10 measurement: 8 of 15 minutes of Stop-hook time after Dot 11 were this hook compiling on turns whose reply said
# "CHƯA XONG". The skip is the work-in-progress rule of hooks/devkit_harness.py work_in_progress(): the reply's status line is
# CHƯA XONG / CHỜ DUYỆT / BLOCKED / WIP, it claims no outcome (XONG, PASS, "đã fix" ...), and the turn ran no git push. Everything else
# is compiled as before: a reply with no status line, XONG, an outcome claim, a push, DEVKIT_GATE_EVERY_STOP=1, or the switch
# TESTSOURCESET_WIP_SKIP=0. The handover turn therefore still blocks a broken test source set. Fake ./gradlew only (it records its calls).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/hooks/testsourceset_gate.sh"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

N=0
# new_repo: a git work tree with a fake ./gradlew (records its arguments in .calls; a task listed in .broken fails like a Kotlin compile
# error) and one module with an uncommitted Kotlin file.
new_repo() {
  N=$((N + 1)); R="$TMP/r$N"; mkdir -p "$R/app/src/main/kotlin"
  git -C "$R" init -q
  cat > "$R/gradlew" <<'SH'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "$here/.calls"
for a in "$@"; do
  case "$a" in -*) continue ;; esac
  grep -qxF -- "$a" "$here/.tasks" 2>/dev/null || { echo "Cannot locate tasks that match $a: not found in project."; exit 1; }
done
for a in "$@"; do
  if grep -qxF -- "$a" "$here/.broken" 2>/dev/null; then
    echo "e: file://$here/app/src/test/FooTest.kt:3:5 No value passed for parameter x."
    echo "> Task $a FAILED"
    exit 1
  fi
done
exit 0
SH
  chmod +x "$R/gradlew"
  printf ':app:compileDebugUnitTestKotlin\n' > "$R/.tasks"; : > "$R/.broken"
  printf '.calls\n.tasks\n.broken\n' >> "$R/.git/info/exclude"
  printf 'plugins { id("com.android.application") }\n' > "$R/app/build.gradle.kts"
  printf 'class Foo\n' > "$R/app/src/main/kotlin/Foo.kt"
  python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=120)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"ts-wip"}))' > "$R/.transcript.jsonl"
  printf '.transcript.jsonl\n' >> "$R/.git/info/exclude"
}
calls() { if [ -f "$R/.calls" ]; then wc -l < "$R/.calls" | tr -d ' '; else echo 0; fi; }
# stop <reply> [NAME=value ...]: one Stop with this reply; sets RC and ERR.
stop() {
  local reply="$1"; shift
  ERR="$(python3 -c 'import json,sys; print(json.dumps({"session_id":"tss-wip-"+sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"cwd":sys.argv[4]}))' "$R/.transcript.jsonl" "$reply" "$N" "$R" \
    | env "$@" CLAUDE_PROJECT_DIR="$R" bash "$GATE" 2>&1 >/dev/null)"
  RC=$?
}
LOG() { cat "$R/.claude/audit-gate/testsourceset_gate.log" 2>/dev/null; }

# (a) the reply declares itself unfinished: nothing is compiled, and the log says why.
new_repo; stop "CHƯA XONG
Đang sửa tiếp, chưa chạy test." X=1
[ "$RC" = 0 ] && [ "$(calls)" = 0 ] && LOG | grep -q "work in progress" \
  && ok "(a) CHƯA XONG reply: no compile, logged" || fail "(a) unfinished reply was compiled (rc=$RC calls=$(calls) log=$(LOG | tail -1))"

# (b) the same tree with a broken test source set: the unfinished reply is not blocked, the XONG reply of the handover is.
new_repo; printf ':app:compileDebugUnitTestKotlin\n' > "$R/.broken"
stop "CHƯA XONG
Đang sửa tiếp." X=1; r1=$RC; c1="$(calls)"
stop "XONG
Đã sửa." X=1; r2=$RC; c2="$(calls)"
[ "$r1" = 0 ] && [ "$c1" = 0 ] && [ "$r2" = 2 ] && [ "$c2" -ge 1 ] \
  && ok "(b) broken test source set: CHƯA XONG passes without compiling, the XONG handover is blocked" \
  || fail "(b) handover not blocked or midwork blocked (CHƯA XONG rc=$r1 calls=$c1; XONG rc=$r2 calls=$c2)"

# (c) controls: replies that are NOT work in progress are compiled as before.
new_repo; stop "Đã sửa file Foo." X=1
[ "$RC" = 0 ] && [ "$(calls)" -ge 1 ] && ok "(c1) a reply with no status line is compiled" || fail "(c1) no-status reply skipped (calls=$(calls))"
new_repo; stop "XONG
Xong việc." X=1
[ "$RC" = 0 ] && [ "$(calls)" -ge 1 ] && ok "(c2) a XONG reply is compiled" || fail "(c2) XONG skipped (calls=$(calls))"
new_repo; stop "CHƯA XONG
Đã fix lỗi X, test PASS." X=1
[ "$RC" = 0 ] && [ "$(calls)" -ge 1 ] && ok "(c3) CHƯA XONG that claims an outcome (PASS, đã fix) is compiled" || fail "(c3) outcome claim skipped (calls=$(calls))"

# (d) the turn ran a git push: a handover, compiled whatever the status line says.
new_repo
python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"assistant","timestamp":t,"message":{"role":"assistant","content":[{"type":"tool_use","id":"e1","name":"Edit","input":{"file_path":sys.argv[1]+"/app/src/main/kotlin/Foo.kt","old_string":"a","new_string":"b"}}]}}))
print(json.dumps({"type":"assistant","timestamp":t,"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"git push origin main"}}]}}))' "$R" >> "$R/.transcript.jsonl"
python3 - "$R/.transcript.jsonl" <<'PY'
import json, sys, datetime
p = sys.argv[1]
rows = [json.loads(l) for l in open(p) if l.strip()]
rows[0]["timestamp"] = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=30)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
open(p, "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
stop "CHƯA XONG
Đẩy lên rồi, còn việc." X=1
[ "$RC" = 0 ] && [ "$(calls)" -ge 1 ] && ok "(d) a turn that pushed is compiled even with CHƯA XONG" || fail "(d) push turn skipped (calls=$(calls))"

# (e) the escape hatches.
new_repo; stop "CHƯA XONG
Đang sửa." TESTSOURCESET_WIP_SKIP=0
[ "$RC" = 0 ] && [ "$(calls)" -ge 1 ] && ok "(e1) TESTSOURCESET_WIP_SKIP=0: compiled as before" || fail "(e1) switch ignored (calls=$(calls))"
new_repo; stop "CHƯA XONG
Đang sửa." DEVKIT_GATE_EVERY_STOP=1
[ "$RC" = 0 ] && [ "$(calls)" -ge 1 ] && ok "(e2) DEVKIT_GATE_EVERY_STOP=1: compiled as before" || fail "(e2) every-stop switch ignored (calls=$(calls))"

# (f) other statuses of the same family are work in progress too; a CHƯA XONG with no transcript is not decidable and is compiled.
new_repo; stop "CHỜ DUYỆT
Cần bạn xem diff." X=1
[ "$RC" = 0 ] && [ "$(calls)" = 0 ] && ok "(f1) CHỜ DUYỆT reply: no compile" || fail "(f1) CHỜ DUYỆT compiled (calls=$(calls))"
new_repo; rm -f "$R/.transcript.jsonl"; stop "CHƯA XONG
Đang sửa." X=1
[ "$RC" = 0 ] && [ "$(calls)" -ge 1 ] && ok "(f2) no transcript: not decidable, compiled" || fail "(f2) no-transcript stop skipped (calls=$(calls))"

# (g) a payload that is not JSON cannot declare anything: the skip logic fails closed (compiled), never open.
new_repo; printf 'not json at all' | CLAUDE_PROJECT_DIR="$R" bash "$GATE" >/dev/null 2>&1; RC=$?
[ "$RC" = 0 ] && [ "$(calls)" -ge 1 ] && ok "(g) unreadable payload: compiled (the skip never fails open)" || fail "(g) unreadable payload skipped (rc=$RC calls=$(calls))"

# (h) a commit made in a work-in-progress turn is still compiled at the handover, even when git no longer calls it unverified.
# Reviewed 2026-10-10: stop 1 (CHƯA XONG) skipped the compile; another session then passed its own gate and moved verified_head to HEAD
# (regression_gate range_verified writes the state file all sessions share), so at the XONG stop no change was left to compile and the broken
# test source set went through. The skipped files are now remembered per session and compiled with the next stop that is not skipped.
head_state() { python3 -c 'import json,os,sys
p = os.path.join(sys.argv[1], ".claude", "audit-gate", "regression_gate.state.json")
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump({"verified_head": sys.argv[2]}, open(p, "w"))' "$R" "$1"; }
new_repo; printf ':app:compileDebugUnitTestKotlin\n' > "$R/.broken"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm base
BASE="$(git -C "$R" rev-parse HEAD)"; head_state "$BASE"
printf 'class Foo\nclass Bar\n' > "$R/app/src/main/kotlin/Foo.kt"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm "mid-work commit"
stop "CHƯA XONG
Đang sửa tiếp." X=1; r1=$RC; c1="$(calls)"
head_state "$(git -C "$R" rev-parse HEAD)"          # another session moved the mark to HEAD
stop "XONG
Đã sửa." X=1; r2=$RC; c2="$(calls)"
[ "$r1" = 0 ] && [ "$c1" = 0 ] && [ "$r2" = 2 ] && [ "$c2" -ge 1 ] \
  && ok "(h) a commit of a skipped turn is compiled at the handover although verified_head moved past it" \
  || fail "(h) the skipped commit escaped the compile (skip rc=$r1 calls=$c1; handover rc=$r2 calls=$c2)"

# (i) the commit made in an unfinished turn and NOT moved past by anything: the since-files path (verified_head..HEAD) compiles it at the
# handover. This is the other way the skipped change reaches the compile; without its own test it could be removed unnoticed.
new_repo; printf ':app:compileDebugUnitTestKotlin\n' > "$R/.broken"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm base
head_state "$(git -C "$R" rev-parse HEAD)"
printf 'class Foo\nclass Baz\n' > "$R/app/src/main/kotlin/Foo.kt"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm "commit"
stop "XONG
Đã commit." X=1
[ "$RC" = 2 ] && [ "$(calls)" -ge 1 ] && ok "(i) an unverified commit and no dirty file: compiled (verified_head..HEAD)" || fail "(i) since-files path lost (rc=$RC calls=$(calls))"

# (j) the memory is cleared by a compile that passes: the next unfinished turn does not drag old files along.
new_repo
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm base
head_state "$(git -C "$R" rev-parse HEAD)"
printf 'class Foo\nclass Qux\n' > "$R/app/src/main/kotlin/Foo.kt"
stop "CHƯA XONG
a" X=1
[ -s "$R/.claude/audit-gate/.testsourceset_skipped_tss-wip-$N" ] && ok "(j1) a skipped stop remembers the files it did not compile" || fail "(j1) nothing remembered"
stop "XONG
b" X=1
[ ! -e "$R/.claude/audit-gate/.testsourceset_skipped_tss-wip-$N" ] && [ "$(calls)" -ge 1 ] && ok "(j2) the memory is dropped after a compile that passes" || fail "(j2) memory kept after a pass (calls=$(calls))"

if [ "$FAILS" -ne 0 ]; then echo "testsourceset wip skip: $FAILS FAILED"; exit 1; fi
echo "testsourceset wip skip: all passed"
