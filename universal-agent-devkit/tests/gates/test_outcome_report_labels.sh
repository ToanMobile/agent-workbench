#!/usr/bin/env bash
# #838 (gộp #842, #674 AC4): the heading labels of the 4-item acceptance report ("1. Đã fix gì", ...) are no claim of being done:
# a reply that says CHƯA XONG and carries that report made hooks/devkit_harness.py work_in_progress() run the heavy Stop gates.
# Same fixture as test_outcome_table_rows.sh. A real claim in the report body, and a `git push`, still count.
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

check 1 "CHƯA XONG with the 4-item report heading '1. Đã fix gì'" $'CHƯA XONG\nBáo cáo nghiệm thu:\n1. Đã fix gì: chưa, đang làm.\n2. Chặn bug cũ: chưa chạy.'
check 1 "bulleted heading '- 1. Đã fix gì'" $'CHƯA XONG\n- 1. Đã fix gì (lỗi, nguyên nhân gốc): đang tìm'
check 0 "a real claim in the report body still counts" $'CHƯA XONG\n1. Đã fix gì: đã fix lỗi A.'
check 0 "plain 'Đã fix lỗi A' without the heading still counts" $'CHƯA XONG\nĐã fix lỗi A, còn B.'
[ "$FAILS" -eq 0 ] && echo "outcome report labels: all checks passed" || { echo "outcome report labels: $FAILS FAILED"; exit 1; }
