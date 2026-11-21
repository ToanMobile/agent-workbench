#!/usr/bin/env bash
# Test hồi quy #1406 (review R1 của PR #1413): thẻ flaky còn giữ mở vì chưa đủ chuỗi đêm xanh (1/3, 2/3) thì lượt xanh KHÔNG được
# ghi last_full_green_sha — nếu ghi, repo ít commit sẽ bỏ lượt mọi đêm sau (skip_reason no-new-commit) và chuỗi 3 đêm không bao giờ đủ.
# cmd_run chạy thật trong tiến trình (repo + origin tạm, gate giả luôn xanh); chỉ close_proven_cards bị thay để báo "còn thẻ giữ mở"
# (HELD=1) hay không (HELD=0) — phần đọc GitHub của nó đã có test riêng ở test_gate_full_flaky_streak_1406.sh (ca 7).
#   s1. đêm 1 xanh, còn thẻ giữ mở: gate chạy, KHÔNG có last_full_green_sha, history vẫn ghi dòng green;
#   s2. đêm 2 cùng sha + cùng kit, còn thẻ giữ mở: gate VẪN chạy (không skip no-new-commit);
#   s3. đêm 3 thẻ đã đóng: gate chạy, last_full_green_sha = sha;
#   s4. đêm 4 không còn thẻ giữ mở: skip no-new-commit như cũ;
#   s5. file last_full_green_sha cũ + lượt --force xanh mà còn thẻ giữ mở: file cũ bị gỡ, lượt sau chạy thật.
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-flaky-skip.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

# kit trong repo git riêng: hash cây kit ổn định giữa các lượt (điều kiện của skip no-new-commit)
K="$T/kitrepo"
mkdir -p "$K/universal-agent-devkit/bin"
cp "$DEVKIT_DIR/bin/gate_full.py" "$DEVKIT_DIR/bin/capacity.py" "$K/universal-agent-devkit/bin/"
g init -q "$K" && g -C "$K" add -A && g -C "$K" commit -qm kit

g init -q --bare "$T/origin.git"
g init -q "$T/seed"
printf 'a\n' >"$T/seed/a.txt"
g -C "$T/seed" add -A && g -C "$T/seed" commit -qm base
g -C "$T/seed" remote add origin "$T/origin.git"
g -C "$T/seed" push -q origin main
g clone -q "$T/origin.git" "$T/repo"
COMMON="$(cd "$T/repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
PG="$COMMON/postfix-gate"
HIST="$PG/nightly/history.jsonl"
SHA="$(git -C "$T/repo" rev-parse origin/main)"

cat >"$T/fakegate.sh" <<'SH'
#!/bin/sh
echo x >>"$FAKE_CALLS"
d="$(git rev-parse --absolute-git-dir)/postfix-gate"; mkdir -p "$d"; echo '{"fake": "pass"}' >"$d/full_pass.json"
echo '{"verdict": "PASS", "exit_code": 0, "regression_tests": [{"id": "REG-FLAKY-01", "status": "PASS", "command": "true"}]}'
SH
chmod +x "$T/fakegate.sh"
export FAKE_CALLS="$T/gate.calls" DEVKIT_GATE_FULL_CMD="sh $T/fakegate.sh" DEVKIT_GATE_FULL_LOG_DIR="$T/logs"
export DEVKIT_GATE_FULL_POLL_S=1 DEVKIT_CAPACITY_LOAD=0 DEVKIT_GATE_FULL_GLOBAL_LOCK="$T/global.lock"

cat >"$T/drive.py" <<'PY'
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import gate_full as g

seen = []

def fake_close(run, slug, sha, pg="", repo=""):
    seen.append(sha)
    return os.environ.get("HELD") == "1"   # True = còn thẻ flaky giữ mở vì chưa đủ chuỗi

g.close_proven_cards = fake_close
rc = g.main(["run"] + sys.argv[2:])
print("close_calls=%d" % len(seen))
sys.exit(rc)
PY

run_gf() { : >"$T/gate.calls"; HELD="$HELD" python3 "$T/drive.py" "$K/universal-agent-devkit/bin" --repo "$T/repo" "$@" >"$T/out" 2>&1; echo $?; }
ran() { [ -s "$T/gate.calls" ]; }
last() { tail -1 "$HIST" 2>/dev/null | python3 -c "import json,sys; r=json.load(sys.stdin); print($1)" 2>/dev/null; }

HELD=1; rc=$(run_gf)
chk "s1. đêm 1 xanh, còn thẻ flaky giữ mở: gate chạy, không ghi last_full_green_sha" \
  '[ "$rc" = 0 ] && ran && grep -q "close_calls=1" "$T/out" && [ ! -e "$PG/last_full_green_sha" ]' \
  "rc=$rc last_full_green_sha=$(cat "$PG/last_full_green_sha" 2>/dev/null) $(tail -2 "$T/out")"
chk "s1b. history vẫn ghi dòng green có passed (chuỗi đêm xanh đếm từ đây)" \
  '[ "$(last "r[\"result\"] + \" \" + \",\".join(r.get(\"passed\") or [])")" = "green REG-FLAKY-01" ]' "$(tail -1 "$HIST" 2>/dev/null)"
chk "s1c. nightly/full_pass.json vẫn được chép (lượt xanh thật)" '[ -s "$PG/nightly/full_pass.json" ]'

HELD=1; rc=$(run_gf)
chk "s2. đêm 2 cùng sha + cùng kit, còn thẻ giữ mở: gate VẪN chạy (không skip no-new-commit)" \
  '[ "$rc" = 0 ] && ran && [ "$(last "r[\"result\"] + \" \" + str(r.get(\"skip_reason\") or \"\")")" = "green " ]' \
  "rc=$rc $(tail -1 "$HIST" 2>/dev/null)"

HELD=0; rc=$(run_gf)
chk "s3. đêm 3 thẻ đã đóng: gate chạy, last_full_green_sha = sha của lượt" \
  '[ "$rc" = 0 ] && ran && [ "$(cat "$PG/last_full_green_sha" 2>/dev/null)" = "$SHA" ]' \
  "rc=$rc last_full_green_sha=$(cat "$PG/last_full_green_sha" 2>/dev/null) $(tail -1 "$HIST" 2>/dev/null)"

HELD=0; rc=$(run_gf)
chk "s4. đêm 4 không còn thẻ giữ mở: skip no-new-commit như cũ" \
  '[ "$rc" = 0 ] && ! ran && [ "$(last "r[\"result\"] + \" \" + str(r.get(\"skip_reason\") or \"\")")" = "skip no-new-commit" ]' \
  "rc=$rc $(tail -1 "$HIST" 2>/dev/null)"

HELD=1; rc=$(run_gf --force)
chk "s5. file last_full_green_sha cũ + lượt --force xanh còn thẻ giữ mở: file cũ bị gỡ" \
  '[ "$rc" = 0 ] && ran && [ ! -e "$PG/last_full_green_sha" ]' "rc=$rc last_full_green_sha=$(cat "$PG/last_full_green_sha" 2>/dev/null)"
chk "s5b. summary ghi lý do không ghi mốc xanh" 'grep -q "last_full_green_sha" "$T/logs/summary-latest.md"' "$(tail -5 "$T/logs/summary-latest.md" 2>/dev/null)"
HELD=1; rc=$(run_gf)
chk "s5c. lượt kế tiếp (không --force) chạy thật" '[ "$rc" = 0 ] && ran' "rc=$rc $(tail -1 "$HIST" 2>/dev/null)"

echo
[ "$fails" -eq 0 ] && { echo "PASS test_gate_full_flaky_streak_skip_1406"; exit 0; }
echo "FAIL test_gate_full_flaky_streak_skip_1406 ($fails)"; exit 1
