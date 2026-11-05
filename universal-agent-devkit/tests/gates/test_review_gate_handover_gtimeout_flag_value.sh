#!/usr/bin/env bash
# Test hồi quy #992 (P3, review PR #999): hooks/review_gate.sh _handover_cmd —
#  G1. `gtimeout N …/super-board-merge-gate.sh` (GNU coreutils trên macOS) là bàn giao như `timeout N …` (trước: tên lệnh là gtimeout ⇒
#      không nhận ⇒ reply CHƯA XONG bỏ qua review).
#  V1. `--dry-run` / `--preflight` chỉ tính khi là CỜ của chính merge gate; làm GIÁ TRỊ của option nhận tham số (`--subject --dry-run`,
#      `--body-file --preflight`, `--expect-head --dry-run`) thì lệnh vẫn là merge thật ⇒ bàn giao (trước: coi là dry-run ⇒ bỏ qua review).
#  D. đối chứng: `gtimeout … --dry-run`, `--subject x --dry-run`, `--pr 12 --preflight` vẫn KHÔNG là bàn giao.
# Không sửa tests/gates/test_review_gate_handover*.sh (ca cũ). bash 3.2 compatible.
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
case_ 2 "G1. gtimeout N bash …merge-gate.sh: là bàn giao" "gtimeout 3600 bash $MG --pr 12"
case_ 2 "G1. gtimeout -k 5 N …merge-gate.sh (gọi trực tiếp): là bàn giao" "gtimeout -k 5 3600 $MG --pr 12"
case_ 2 "V1. --subject --dry-run (--dry-run là giá trị của --subject): là bàn giao" "bash $MG --pr 12 --subject --dry-run"
case_ 2 "V1. --body-file --preflight (giá trị của --body-file): là bàn giao" "bash $MG --pr 12 --body-file --preflight"
case_ 2 "V1. --expect-head --dry-run --standalone: là bàn giao" "bash $MG --config c.json --pr 12 --expect-head --dry-run --standalone"
case_ 0 "D. gtimeout + merge gate --dry-run: không phải bàn giao" "gtimeout 3600 bash $MG --pr 12 --dry-run"
case_ 0 "D. --subject x --dry-run: cờ thật, không phải bàn giao" "bash $MG --pr 12 --subject x --dry-run"
case_ 0 "D. --pr 12 --preflight: cờ thật, không phải bàn giao" "$MG --pr 12 --preflight"

[ "$FAILS" = 0 ] && { echo "test_review_gate_handover_gtimeout_flag_value: PASS"; exit 0; }
echo "test_review_gate_handover_gtimeout_flag_value: FAIL ($FAILS)"; exit 1
