#!/usr/bin/env bash
# Test hồi quy (#709): lượt gate-full bị SIGTERM không bao giờ ghi result "?" vào nightly/history.jsonl:
#   1. gate đã exit 1 với một suite đỏ rồi nhận SIGTERM trong bước agent-kit test ⇒ result = aborted (thuộc aborted|red),
#      red chứa đúng mã suite đó, summary ghi suite đỏ, scratch gỡ, khoá nhả, tiến trình con không mồ côi;
#   2. SIGTERM trước khi gate trả kết quả ⇒ result = aborted, red = [], không bao giờ ghi "?", scratch gỡ, khoá nhả;
#   3. gate đã exit 0 (xanh) nhưng nhận SIGTERM trong bước agent-kit test ⇒ result = aborted (không ghi nhầm green),
#      không cập nhật last_full_green_sha hay nightly/full_pass.json, xoá .full_pass.pending.
# Đồng bộ bằng ready-file (không sleep mù), cô lập hoàn toàn trong thư mục tạm, tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GF="$DEVKIT_DIR/bin/gate_full.py"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-sigterm.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
GF_PID=""
cleanup() {
  if [ -n "$GF_PID" ]; then
    kill -TERM "$GF_PID" 2>/dev/null
    wait "$GF_PID" 2>/dev/null
  fi
  rm -rf "$T"
}
trap cleanup EXIT

[ -f "$GF" ] || { echo "✖ thiếu bin/gate_full.py"; exit 1; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

# Dựng repo giả có universal-agent-devkit/bin/{post-fix-gate.py,agent-kit} (không có install.sh để vào thẳng bước chạy gate + agent-kit test)
g init -q --bare "$T/origin.git"
g init -q "$T/seed"
mkdir -p "$T/seed/universal-agent-devkit/bin"

cat >"$T/seed/universal-agent-devkit/bin/post-fix-gate.py" <<'PY'
#!/usr/bin/env python3
# Gate giả phục vụ kiểm thử xử lý SIGTERM (#709)
import json
import os
import subprocess
import sys
import time

mode = os.environ.get("FAKE_GATE_MODE", "red")
ready = os.environ.get("FAKE_GATE_READY", "")
if mode == "block":
    if ready:
        with open(ready, "w", encoding="utf-8") as fh:
            fh.write("%d\n" % os.getpid())
    time.sleep(30)
    sys.exit(0)
if mode == "green":
    gd = subprocess.check_output(["git", "rev-parse", "--absolute-git-dir"], text=True).strip()
    pg = os.path.join(gd, "postfix-gate")
    os.makedirs(pg, exist_ok=True)
    with open(os.path.join(pg, "full_pass.json"), "w", encoding="utf-8") as fh:
        fh.write('{"fake": "pass"}\n')
    print(json.dumps({
        "verdict": "PASS",
        "exit_code": 0,
        "accepted": True,
        "regression_tests": [{"id": "REG-AUTO-FAKE-01", "status": "PASS", "command": "true"}],
    }))
    sys.exit(0)
print(json.dumps({
    "verdict": "FAIL",
    "exit_code": 1,
    "accepted": False,
    "regression_tests": [{"id": "REG-AUTO-FAKE-01", "status": "FAIL", "command": "false"}],
}))
sys.exit(1)
PY

cat >"$T/seed/universal-agent-devkit/bin/agent-kit" <<'SH'
#!/usr/bin/env bash
# agent-kit giả: báo PID qua ready-file rồi chờ nhận SIGTERM từ nhóm tiến trình của gate_full.py
if [ -n "${FAKE_KIT_READY:-}" ]; then
  printf '%s\n' "$$" >"$FAKE_KIT_READY"
fi
sleep 30
SH

chmod +x "$T/seed/universal-agent-devkit/bin/post-fix-gate.py" "$T/seed/universal-agent-devkit/bin/agent-kit"
g -C "$T/seed" add -A && g -C "$T/seed" commit -qm "seed fake kit"
HEAD_SHA="$(git -C "$T/seed" rev-parse HEAD)"
g -C "$T/seed" remote add origin "$T/origin.git"
g -C "$T/seed" push -q origin main:main
g clone -q "$T/origin.git" "$T/repo"
COMMON="$(cd "$T/repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
HIST="$COMMON/postfix-gate/nightly/history.jsonl"

mkdir -p "$T/bin"
printf '#!/bin/sh\necho "[]"\n' >"$T/bin/gh"
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"
export DEVKIT_GATE_FULL_LOG_DIR="$T/logs" DEVKIT_GATE_FULL_POLL_S=1 DEVKIT_CAPACITY_LOAD=0
unset DEVKIT_GATE_FULL_CMD DEVKIT_GATE_FULL_CARD_CMD

wait_file() {   # chờ file $1 có nội dung (tối đa ~10 s, bước 50 ms)
  local f="$1" n=0
  while [ ! -s "$f" ] && [ "$n" -lt 200 ]; do
    python3 -c 'import time; time.sleep(0.05)'
    n=$((n + 1))
  done
  [ -s "$f" ]
}

wait_dead() {   # chờ PID $1 thoát hẳn (tối đa ~3 s)
  local p="$1" n=0
  while kill -0 "$p" 2>/dev/null && [ "$n" -lt 60 ]; do
    python3 -c 'import time; time.sleep(0.05)'
    n=$((n + 1))
  done
  ! kill -0 "$p" 2>/dev/null
}

no_scratch() {
  ! ls -d "$COMMON"/postfix-gate/gate-full-scratch-* >/dev/null 2>&1 \
    && ! git -C "$T/repo" worktree list --porcelain | grep -q gate-full-scratch \
    && [ ! -e "$COMMON/postfix-gate/gate-full.lock" ]
}

last_hist_check() {   # kiểm dòng cuối của history.jsonl bằng biểu thức python $1
  python3 - "$HIST" "$1" <<'PY'
import json, sys
lines = [ln.strip() for ln in open(sys.argv[1], encoding="utf-8") if ln.strip()]
assert lines, "history.jsonl rỗng"
row = json.loads(lines[-1])
ok = bool(eval(sys.argv[2], {"row": row}))
if not ok:
    print("row=", row)
sys.exit(0 if ok else 1)
PY
}

# --- Ca 1: gate exit 1 với REG-AUTO-FAKE-01, gửi SIGTERM trong bước agent-kit test -------------------------------------------
rm -f "$T/kit.ready"
FAKE_GATE_MODE=red FAKE_KIT_READY="$T/kit.ready" python3 "$GF" run --repo "$T/repo" >"$T/out1" 2>&1 &
GF_PID=$!
chk "1a. bước agent-kit test khởi chạy sau khi gate trả exit 1" 'wait_file "$T/kit.ready"' "$(tail -10 "$T/out1" 2>/dev/null)"
KIT_PID="$(cat "$T/kit.ready" 2>/dev/null || true)"
kill -TERM "$GF_PID" 2>/dev/null
wait "$GF_PID"; rc1=$?; GF_PID=""

chk "1b. nhận SIGTERM thoát mã 143" '[ "$rc1" = 143 ]' "rc=$rc1"
chk "1c. history.jsonl ghi result thuộc aborted|red (không phải '?') và red chứa REG-AUTO-FAKE-01" \
  'last_hist_check "row.get(\"result\") in (\"aborted\", \"red\") and row.get(\"red\") == [\"REG-AUTO-FAKE-01\"] and row.get(\"sha\") == \"$HEAD_SHA\""' \
  "$(tail -1 "$HIST" 2>/dev/null)"
chk "1d. summary-latest.md ghi suite đỏ REG-AUTO-FAKE-01 và không ghi '?'" \
  'grep -q "REG-AUTO-FAKE-01" "$T/logs/summary-latest.md" && ! grep -q "\*\*?\*\*" "$T/logs/summary-latest.md"' \
  "$(cat "$T/logs/summary-latest.md" 2>/dev/null)"
chk "1e. scratch gỡ sạch, khoá nhả, tiến trình con agent-kit đã tắt" \
  'no_scratch && [ -n "$KIT_PID" ] && wait_dead "$KIT_PID"'

# --- Ca 2: SIGTERM ngay khi gate đang chạy (trước khi gate trả kết quả) ------------------------------------------------------
rm -f "$T/gate.ready"
FAKE_GATE_MODE=block FAKE_GATE_READY="$T/gate.ready" python3 "$GF" run --repo "$T/repo" >"$T/out2" 2>&1 &
GF_PID=$!
chk "2a. gate bắt đầu chạy trong scratch" 'wait_file "$T/gate.ready"' "$(tail -10 "$T/out2" 2>/dev/null)"
GATE_PID="$(cat "$T/gate.ready" 2>/dev/null || true)"
kill -TERM "$GF_PID" 2>/dev/null
wait "$GF_PID"; rc2=$?; GF_PID=""

chk "2b. nhận SIGTERM trước khi gate xong thoát mã 143" '[ "$rc2" = 143 ]' "rc=$rc2"
chk "2c. history.jsonl ghi result == 'aborted' và red == []" \
  'last_hist_check "row.get(\"result\") == \"aborted\" and row.get(\"red\") == [] and row.get(\"sha\") == \"$HEAD_SHA\""' \
  "$(tail -1 "$HIST" 2>/dev/null)"
chk "2d. summary-latest.md không ghi '?'; scratch gỡ, khoá nhả, gate con đã tắt" \
  '! grep -q "\*\*?\*\*" "$T/logs/summary-latest.md" && no_scratch && [ -n "$GATE_PID" ] && wait_dead "$GATE_PID"'

# --- Ca 3: gate xanh (exit 0 + full_pass.json) nhưng bị SIGTERM trong bước agent-kit test ------------------------------------
rm -f "$T/kit3.ready"
FAKE_GATE_MODE=green FAKE_KIT_READY="$T/kit3.ready" python3 "$GF" run --repo "$T/repo" >"$T/out3" 2>&1 &
GF_PID=$!
chk "3a. bước agent-kit test khởi chạy sau khi gate xanh" 'wait_file "$T/kit3.ready"' "$(tail -10 "$T/out3" 2>/dev/null)"
KIT3_PID="$(cat "$T/kit3.ready" 2>/dev/null || true)"
kill -TERM "$GF_PID" 2>/dev/null
wait "$GF_PID"; rc3=$?; GF_PID=""

chk "3b. bị SIGTERM giữa agent-kit test: result == 'aborted' (không ghi nhầm green), red == []" \
  '[ "$rc3" = 143 ] && last_hist_check "row.get(\"result\") == \"aborted\" and row.get(\"red\") == []"' \
  "rc=$rc3 $(tail -1 "$HIST" 2>/dev/null)"
chk "3c. không ghi last_full_green_sha, không để lại full_pass.json hay .full_pass.pending" \
  '[ ! -e "$COMMON/postfix-gate/last_full_green_sha" ] && [ ! -e "$COMMON/postfix-gate/nightly/full_pass.json" ] && [ ! -e "$COMMON/postfix-gate/nightly/.full_pass.pending" ] && no_scratch && [ -n "$KIT3_PID" ] && wait_dead "$KIT3_PID"'

# --- Chốt chặn toàn cục: không dòng nào trong history.jsonl có result == "?" -------------------------------------------------
chk "4. toàn bộ history.jsonl không bao giờ xuất hiện result == '?'" \
  'python3 -c "import json,sys; rows=[json.loads(l) for l in open(sys.argv[1], encoding=\"utf-8\") if l.strip()]; sys.exit(0 if len(rows)==3 and all(r.get(\"result\")!=\"?\" for r in rows) else 1)" "$HIST"' \
  "$(cat "$HIST" 2>/dev/null)"

echo
if [ "$fails" -eq 0 ]; then echo "test_gate_full_sigterm_result: PASS"; exit 0; fi
echo "test_gate_full_sigterm_result: $fails FAIL"; exit 1
