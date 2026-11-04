#!/usr/bin/env bash
# Test hồi quy #992 (P3): hooks/review_gate.sh — lệnh super-board-merge-gate.sh nào là BÀN GIAO (reply CHƯA XONG không còn bỏ qua
# review khi code chưa review lúc bàn giao):
#  M1. `super-board-merge-gate.sh … --dry-run` / `--preflight` chỉ kiểm thử, không merge ⇒ KHÔNG phải bàn giao: reply CHƯA XONG bỏ qua
#      (trước: chặn — essentials bước 3 bảo chạy merge gate --dry-run nền ngay sau push, lượt giữa chừng bị đòi review sớm).
#  M2. `timeout N bash …/super-board-merge-gate.sh 12` (lane chạy merge gate có trần giờ) LÀ bàn giao: chặn (trước: bỏ qua — từ đầu
#      lệnh là `timeout`, không phải tên script); cả dạng `timeout -k 5 3600 …` và gọi script trực tiếp sau timeout.
#  M3. đối chứng: `bash …/super-board-merge-gate.sh 12 --head abc` vẫn là bàn giao (chặn), `echo '… --dry-run'` không phải.
# Không sửa tests/gates/test_review_gate_handover.sh (ca cũ). bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo x > a && git add a && git commit -qm i)
P="$(cd "$P" && pwd -P)"
echo "def f(x): return 1 / x" > "$P/app.py"

TR="$TMP/t.jsonl"
cat > "$TMP/ev.py" <<'PY'
import json, sys, time, datetime
kind, tr, at = sys.argv[1], sys.argv[2], float(sys.argv[3]); a = sys.argv[4:]
stamp = datetime.datetime.fromtimestamp(time.time() + at, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
tu = lambda b: {"type": "assistant", "message": {"role": "assistant", "content": [dict(b, type="tool_use")]}}
if kind == "user":
    rec = {"type": "user", "message": {"role": "user", "content": a[0]}}
elif kind == "edit":
    rec = tu({"id": a[0], "name": "Write", "input": {"file_path": a[1], "content": "x"}})
elif kind == "bash":
    rec = tu({"id": a[0], "name": "Bash", "input": {"command": a[1]}})
else:
    rec = {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": a[0], "is_error": False, "content": a[1]}]}}
rec["timestamp"] = stamp
open(tr, "a").write(json.dumps(rec) + "\n")
PY
ev() { python3 "$TMP/ev.py" "$1" "$TR" "${@:2}"; }
fresh() { : > "$TR"; python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$P/.claude/audit-gate"; }
WIP="CHƯA XONG — đang chờ CI và review."
# case_ <want rc> <label> <command>: edit chưa review → <command> trong lượt → Stop với reply CHƯA XONG
case_() {
  local want="$1" label="$2" c="$3" rc
  fresh; ev user -100 "làm tiếp"; ev edit -50 t1 "$P/app.py"; ev bash -40 h1 "$c"; ev result -39 h1 "ok"
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"transcript_path":sys.argv[2],"hook_event_name":"Stop","cwd":sys.argv[3],"last_assistant_message":sys.argv[4]}))' \
      "m-$RANDOM" "$TR" "$P" "$WIP" \
    | env CLAUDE_PROJECT_DIR="$P" REVIEW_GATE_OCR=0 REVIEW_GATE_REQUIRE_OCR=0 bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"
  rc=$?
  [ "$rc" = "$want" ] && ok "$label (rc $rc)" || fail "$label: rc $rc (want $want) — '$c'"
}
MG=".claude/bin/super-board-merge-gate.sh"
case_ 0 "M1. merge gate --dry-run (nền, sau push): không phải bàn giao" "bash $MG 12 --dry-run > /tmp/mg.log 2>&1 &"
case_ 0 "M1. merge gate --preflight: không phải bàn giao" "$MG --preflight 12"
case_ 0 "M1. timeout + merge gate --dry-run: không phải bàn giao" "timeout 3600 bash $MG 12 --dry-run"
case_ 2 "M2. timeout N bash …merge-gate.sh: là bàn giao" "timeout 3600 bash $MG 12 --head abc"
case_ 2 "M2. timeout -k 5 N …merge-gate.sh (gọi trực tiếp): là bàn giao" "timeout -k 5 3600 $MG 12"
case_ 2 "M2. timeout --kill-after=5 N bash …merge-gate.sh: là bàn giao" "timeout --kill-after=5 900 bash $MG 12"
case_ 2 "M3. đối chứng: bash …merge-gate.sh 12 --head abc vẫn là bàn giao" "bash $MG 12 --head abc"
case_ 0 "M3. đối chứng: chỉ nhắc tên lệnh trong chuỗi: không phải bàn giao" "echo 'bash $MG 12'"

[ "$FAILS" = 0 ] && { echo "test_review_gate_handover_merge_gate_forms: PASS"; exit 0; }
echo "test_review_gate_handover_merge_gate_forms: FAIL ($FAILS)"; exit 1
