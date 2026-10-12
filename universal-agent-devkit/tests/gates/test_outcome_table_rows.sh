#!/usr/bin/env bash
# hooks/devkit_harness.py work_in_progress(): what counts as "this reply claims an outcome" (OUTCOME). 2026-10-12 measurement over the
# last 24 h of GeelyEx2 and OfficeReader: 17 replies whose status line said unfinished still matched OUTCOME, 6 of them plainly misread
# (a ✅ or "PASS 13/13" inside a markdown table row of a progress report, a ✅ marking one finished step in a list), so the heavy Stop gates
# (tests, fresh-context review, test-source-set compile) ran on a turn that was only the middle of the work. User-approved narrowing
# (AskUserQuestion 2026-10-12): the ✅ sign and a markdown table row no longer count as a claim. Every word form still does, PASS and XONG
# outside a table still do, and "CHƯA XONG … đã xong" keeps its claim. Switch: DEVKIT_OUTCOME_WIDE=1 restores the old reading.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/r"; mkdir -p "$R"; git -C "$R" init -q
python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=120)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"ts-outcome"}))' > "$TMP/t.jsonl"

# wip <reply> [NAME=value ...]: prints 1 when work_in_progress() lets the heavy gates skip this reply, else 0
wip() {
  local reply="$1"; shift
  python3 -I - "$DEVKIT_DIR/hooks" "$TMP/t.jsonl" "$reply" "$R" "$@" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import devkit_harness as h
env = dict(os.environ)
status_optional = False
for kv in sys.argv[5:]:
    k, _, v = kv.partition("=")
    if k == "STATUS_OPTIONAL":          # regression_gate calls work_in_progress(status_optional=True)
        status_optional = v == "1"
    else:
        env[k] = v
payload = {"transcript_path": sys.argv[2], "last_assistant_message": sys.argv[3], "cwd": sys.argv[4]}
print(1 if h.work_in_progress(payload, env=env, status_optional=status_optional) else 0)
PY
}
# check <want 0|1> <label> <reply> [NAME=value ...]
check() {
  local want="$1" label="$2" reply="$3"; shift 3
  local got; got="$(wip "$reply" "$@")"
  [ "$got" = "$want" ] && ok "$label (skip=$got)" || fail "$label: skip=$got, want $want"
}

check 1 "plain progress reply, no claim" $'CHƯA XONG\nĐang sửa tiếp.'
check 1 "✅ and PASS inside table rows of a progress report" $'CHƯA XONG\nTiến độ:\n| bước | kết quả |\n|---|---|\n| 1 | ✅ |\n| 2 | PASS 13/13 |'
check 1 "XONG as a table cell" $'CHƯA XONG\n| bước 1 | XONG |'
check 1 "indented table row" $'CHƯA XONG\n   | bước 1 | PASS |'
check 1 "✅ marking one finished step" $'CHƯA XONG\n✅ bước 1\nĐang làm bước 2.'
check 0 "PASS outside a table still counts" $'CHƯA XONG\nPASS 13/13 ở lần chạy trước.'
check 0 "XONG outside a table still counts" $'CHƯA XONG\nbước 1 đã XONG nhé.'
check 0 "word form: đã fix" $'CHƯA XONG\nĐã fix lỗi A, còn B.'
check 0 "word form: đã xong inside a CHƯA XONG reply" $'CHƯA XONG\nbước 1 đã xong, còn bước 2.'
check 0 "word form: all tests pass" $'CHƯA XONG\nall tests pass ở máy này.'
check 0 "a claim next to a table still counts" $'CHƯA XONG\n| a | b |\nĐã fix xong lỗi.'
check 0 "a pipe in the middle of a line is not a table row" $'CHƯA XONG\nkết quả a | b: PASS'
check 0 "a status line that is XONG is no work in progress" $'XONG\n| a | ✅ |'
# Only a reply that says UNFINISHED gets the narrow reading. A reply with no status line (regression_gate treats it as unfinished unless
# it claims an outcome) or one waiting for approval may be a handover: it keeps the wide reading (round-2 review of Dot 20).
check 0 "no status line, ✅ completion report: still a claim" $'✅ Hoàn tất toàn bộ yêu cầu' STATUS_OPTIONAL=1
check 0 "no status line, ✅ with a count: still a claim" $'Test: ✅ 12/12' STATUS_OPTIONAL=1
check 0 "no status line, PASS only inside a table: still a claim" $'| unit | PASS |' STATUS_OPTIONAL=1
check 1 "no status line, no claim: unfinished" $'Đang đọc code, chưa sửa gì.' STATUS_OPTIONAL=1
check 0 "CHỜ DUYỆT with a PASS table: handover, the gates run" $'CHỜ DUYỆT\n| bước | kết quả |\n| 1 | PASS |'
check 0 "CHỜ DUYỆT with a ✅ list: handover, the gates run" $'CHỜ DUYỆT\n✅ bước 1\n✅ bước 2'
check 1 "CHỜ DUYỆT with no claim: a plan awaiting approval" $'CHỜ DUYỆT\nKế hoạch: sửa A rồi B.'
check 1 "Status: CHƯA XONG label, table PASS: narrow reading" $'Status: CHƯA XONG\n| 1 | PASS |'
check 0 "DEVKIT_OUTCOME_WIDE=1: ✅ in a table counts again" $'CHƯA XONG\n| 1 | ✅ |' DEVKIT_OUTCOME_WIDE=1
check 0 "DEVKIT_OUTCOME_WIDE=1: a lone ✅ counts again" $'CHƯA XONG\n✅ bước 1' DEVKIT_OUTCOME_WIDE=1
check 0 "DEVKIT_GATE_EVERY_STOP=1 keeps a gate on every stop" $'CHƯA XONG\nĐang sửa tiếp.' DEVKIT_GATE_EVERY_STOP=1

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
