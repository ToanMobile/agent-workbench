#!/usr/bin/env bash
# Test hồi quy: khoá TOÀN MÁY của bin/gate_full.py — mỗi lúc chỉ một lượt gate-full trên cả máy, mọi repo (lịch đêm 00:00 của nhiều
# repo cùng nổ, nút "Chạy gate full" của Agent Office). Hai repo giả, gate giả chậm (DEVKIT_GATE_FULL_CMD) ghi lúc bắt đầu / kết thúc:
#   a. hai lượt ở hai repo khởi động cùng lúc ⇒ cả hai chạy xong, khoảng [bắt đầu, kết thúc] KHÔNG chồng nhau, lượt sau ghi "chờ khoá
#      toàn máy"; khoá repo đã nhả, file khoá toàn máy còn đó nhưng không ai giữ;
#   b. khoá toàn máy bị giữ quá DEVKIT_GATE_FULL_GLOBAL_WAIT_S ⇒ "skip", exit 0, gate không chạy, khoá repo đã nhả, log ghi lý do.
# DEVKIT_GATE_FULL_GLOBAL_LOCK trỏ vào thư mục tạm: không chạm ~/Library/Caches. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GF="$DEVKIT_DIR/bin/gate_full.py"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-global.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd)"
HOLD_PID=""
cleanup() { [ -n "$HOLD_PID" ] && kill "$HOLD_PID" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }
for r in a b; do
  g init -q --bare "$T/$r-origin.git"
  g init -q "$T/$r-seed"
  echo ok >"$T/$r-seed/x.txt"
  g -C "$T/$r-seed" add -A && g -C "$T/$r-seed" commit -qm base
  g -C "$T/$r-seed" push -q "$T/$r-origin.git" main:main
  g clone -q "$T/$r-origin.git" "$T/$r"
done

cat >"$T/fakegate.sh" <<'SH'
#!/bin/sh
python3 -c 'import time,sys; print("start", sys.argv[1], repr(time.time()))' "$FAKE_NAME" >>"$FAKE_CALLS"
sleep "${FAKE_SLEEP:-2}"
python3 -c 'import time,sys; print("end", sys.argv[1], repr(time.time()))' "$FAKE_NAME" >>"$FAKE_CALLS"
echo '{"verdict": "PASS", "exit_code": 0, "regression_tests": [{"id": "REG-FAKE-01", "status": "PASS", "command": "true"}]}'
SH
export FAKE_CALLS="$T/gate.calls" DEVKIT_GATE_FULL_CMD="sh $T/fakegate.sh" DEVKIT_GATE_FULL_CARD_CMD="true"
export DEVKIT_GATE_FULL_POLL_S=1 DEVKIT_CAPACITY_LOAD=0
export DEVKIT_GATE_FULL_GLOBAL_LOCK="$T/global.lock" DEVKIT_GATE_FULL_GLOBAL_POLL_S=0.2
common() { (cd "$T/$1" && cd "$(git rev-parse --git-common-dir)" && pwd -P); }

# a. hai repo cùng lúc ----------------------------------------------------------------------------------------------------------
FAKE_NAME=a DEVKIT_GATE_FULL_LOG_DIR="$T/logs-a" python3 "$GF" run --repo "$T/a" >"$T/out-a" 2>&1 & PA=$!
FAKE_NAME=b DEVKIT_GATE_FULL_LOG_DIR="$T/logs-b" python3 "$GF" run --repo "$T/b" >"$T/out-b" 2>&1 & PB=$!
wait $PA; RA=$?; wait $PB; RB=$?
chk "a1. hai lượt exit 0" '[ "$RA" = 0 ] && [ "$RB" = 0 ]' "ra=$RA rb=$RB $(tail -3 "$T/out-a" "$T/out-b")"
chk "a2. gate chạy đủ hai lần" '[ "$(grep -c "^start" "$T/gate.calls" 2>/dev/null)" = 2 ] && [ "$(grep -c "^end" "$T/gate.calls")" = 2 ]' "$(cat "$T/gate.calls" 2>/dev/null)"
overlap="$(python3 - "$T/gate.calls" <<'PY'
import sys
ev = [l.split() for l in open(sys.argv[1]).read().splitlines()]
iv = {}
for k, n, t in ev:
    iv.setdefault(n, {})[k] = float(t)
(a, b) = sorted(iv.values(), key=lambda d: d["start"])
print("chong" if b["start"] < a["end"] else "khong")
PY
)"
chk "a3. hai lượt không chồng nhau (khoá toàn máy)" '[ "$overlap" = khong ]' "$(cat "$T/gate.calls")"
chk "a4. lượt sau ghi chờ khoá toàn máy" 'cat "$T"/logs-a/*.log "$T"/logs-b/*.log | grep -q "chờ khoá toàn máy"'
chk "a5. cả hai summary XANH" 'grep -q "XANH" "$T/logs-a/summary-latest.md" && grep -q "XANH" "$T/logs-b/summary-latest.md"'
chk "a6. khoá repo đã nhả" '[ ! -e "$(common a)/postfix-gate/gate-full.lock" ] && [ ! -e "$(common b)/postfix-gate/gate-full.lock" ]'
free="$(python3 -c 'import fcntl,os,sys; fd=os.open(sys.argv[1],os.O_RDWR); fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB); print("free")' "$T/global.lock" 2>/dev/null)"
chk "a7. khoá toàn máy không còn ai giữ" '[ "$free" = free ]'

# b. khoá toàn máy bị giữ lâu ⇒ skip sau GLOBAL_WAIT_S ----------------------------------------------------------------------------
: >"$T/gate.calls"
python3 -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT); fcntl.flock(fd,fcntl.LOCK_EX); os.ftruncate(fd,0); os.write(fd,b"{\"pid\": 1, \"repo\": \"/x/khac\"}"); open(sys.argv[2],"w").close(); time.sleep(60)' "$T/global.lock" "$T/held" & HOLD_PID=$!
for _ in $(seq 1 50); do [ -e "$T/held" ] && break; sleep 0.1; done
FAKE_NAME=a DEVKIT_GATE_FULL_LOG_DIR="$T/logs-skip" DEVKIT_GATE_FULL_GLOBAL_WAIT_S=1 python3 "$GF" run --repo "$T/a" >"$T/out-skip" 2>&1; RS=$?
chk "b1. chờ quá hạn: exit 0" '[ "$RS" = 0 ]' "rc=$RS $(tail -3 "$T/out-skip")"
chk "b2. gate không chạy" '[ ! -s "$T/gate.calls" ]' "$(cat "$T/gate.calls")"
chk "b3. log ghi skip vì khoá toàn máy + ai giữ" 'cat "$T"/logs-skip/*.log | grep -q "skip: chờ khoá toàn máy" && cat "$T"/logs-skip/*.log | grep -q "/x/khac"'
chk "b4. khoá repo đã nhả" '[ ! -e "$(common a)/postfix-gate/gate-full.lock" ]'
chk "b5. skip không đè summary-latest" '[ ! -e "$T/logs-skip/summary-latest.md" ]'
kill "$HOLD_PID" 2>/dev/null; wait "$HOLD_PID" 2>/dev/null; HOLD_PID=""

[ "$fails" = 0 ] && echo "✔ test_gate_full_global_lock: XANH" || { echo "✖ test_gate_full_global_lock: $fails ca đỏ"; exit 1; }
