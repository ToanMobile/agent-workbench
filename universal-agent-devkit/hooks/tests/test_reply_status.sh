#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# test_reply_status.sh — how the Stop hooks read a reply's completion status.
#
# A. One classifier (hooks/devkit_harness.py reply_status → DONE | NOT_DONE | NONE) reads the
#    first non-empty line with markdown, leading emoji/symbols and a leading label
#    (Status: / Trạng thái: / Line 1:) stripped, case-insensitive. proof_gate must treat
#    `✅ XONG`, `**XONG**`, `Xong.`, `Status: XONG`, `Trạng thái: XONG` like plain XONG (blocked
#    with no full-gate receipt and no image); `CHƯA XONG`, `Chưa xong nha`, `CHỜ DUYỆT` are never
#    done, and a progress reply with no status word is NONE. work_in_progress (regression_gate,
#    review_gate) skips on NOT_DONE only.
# B. test_evidence_gate: after a source edit and no test run, a pass/outcome claim in plainer
#    wording is blocked like `12/12 tests passed.`; ordinary progress text is not.
#
# Usage: bash hooks/tests/test_reply_status.sh   Exit 0 = all hold. bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/replystatus.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

# ── A1: the classifier itself (CLI: reply text on stdin) ────────────────────────
echo "reply_status (devkit_harness.py status)"
cls() { # <want> <reply>
  got="$(printf '%s' "$2" | python3 "$HOOKS/devkit_harness.py" status 2>/dev/null)"
  [ "$got" = "$1" ] && ok "$(printf '%s' "$2" | head -1) -> $1" || fail "$(printf '%s' "$2" | head -1): want $1, got '${got}'"
}
cls DONE "XONG"
cls DONE "✅ XONG"
cls DONE "**XONG**"
cls DONE "Xong."
cls DONE "Status: XONG"
cls DONE "Trạng thái: XONG"
cls DONE "## ✅ **Status:** XONG
more"
cls DONE "

Line 1: XONG"
cls NOT_DONE "CHƯA XONG"
cls NOT_DONE "Chưa xong nha"
cls NOT_DONE "CHỜ DUYỆT"
cls NOT_DONE "⏳ Status: WIP"
cls NOT_DONE "BLOCKED: no device"
cls NOT_DONE "chua xong"
cls NONE "I am reading the hook now, next I run the tests."
cls NONE "Status: reading the hooks (no edit yet)."
cls NONE ""
cls DONE "XONG việc nhỏ"
cls DONE "XONG — đã sửa lỗi X"
cls DONE "XONG."
cls DONE "xong!"
cls NONE "xong — đã sửa lỗi X"
cls NONE "Xong bước 1. Tiếp tục bước 2."
cls NONE "Xong phần A, còn B"
cls NONE "Xong việc nhỏ."   # a sentence, not a status word (tests/gates/test_proof_gate.sh false-push cases)

# ── A2: proof_gate — a DONE reply with no receipt and no image is blocked ───────
echo "proof_gate.sh"
REPO="$TMP/repo"; mkdir -p "$REPO/src"
( cd "$REPO" && git init -q . && git config user.email t@t && git config user.name t
  echo '{"profile":"android"}' > profile.json && echo "fun ok() = 1" > src/Core.kt
  git add -A && git commit -qm init && echo "fun ok() = 2" > src/Core.kt )
TR="$TMP/transcript.jsonl"
python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X"}}))' > "$TR"
REPORT="1. Đã fix: lỗi X.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
N=0
proof() { # <want rc> <status line>
  N=$((N + 1))
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[3],"hook_event_name":"Stop",
    "transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2],"stop_hook_active":False}))' \
    "$TR" "$2
Đã sửa lỗi X.
$REPORT" "rs-$N" | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOKS/proof_gate.sh" >/dev/null 2>"$TMP/err"
  rc=$?
  [ "$rc" = "$1" ] && ok "proof_gate '$2' -> exit $rc" || fail "proof_gate '$2': want exit $1, got $rc ($(head -1 "$TMP/err"))"
}
proof 2 "XONG"
proof 2 "✅ XONG"
proof 2 "**XONG**"
proof 2 "Xong."
proof 2 "Status: XONG"
proof 2 "Trạng thái: XONG"
proof 0 "CHƯA XONG"
proof 0 "Chưa xong nha"
proof 0 "CHỜ DUYỆT"
proof 0 "Đang đọc code, chưa sửa gì."
proof 0 "Xong bước 1. Tiếp tục bước 2."
proof 0 "Xong phần A, còn B"

# ── A3: work_in_progress (regression_gate / review_gate skip) — NOT_DONE only ────
echo "work_in_progress (regression_gate, review_gate)"
wip() { # <want True|False> <reply>
  got="$(python3 - "$HOOKS" "$TR" "$2" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import devkit_harness
print(devkit_harness.work_in_progress({"transcript_path": sys.argv[2], "last_assistant_message": sys.argv[3]}, env={}))
PY
)"
  [ "$got" = "$1" ] && ok "wip '$(printf '%s' "$2" | head -1)' -> $got" || fail "wip '$(printf '%s' "$2" | head -1)': want $1, got $got"
}
wip True  "CHƯA XONG
Đang chạy test."
wip True  "Chưa xong nha
Còn phần B."
wip True  "CHỜ DUYỆT
Cần người dùng duyệt test."
wip True  "**Trạng thái:** CHƯA XONG
Còn phần B."
wip False "✅ XONG
Đã sửa."
wip False "Status: XONG
Đã sửa."
wip False "Đang đọc code."

# ── B: test_evidence_gate — plainer pass/outcome wording after a source edit ─────
echo "test_evidence_gate.sh"
SB="$TMP/sb"; mkdir -p "$SB/.claude/audit-gate"
echo "module.exports = 1" > "$SB/app.js"
ETR="$TMP/edit.jsonl"
python3 - "$ETR" "$SB/app.js" <<'PY'
import json, sys
path, js = sys.argv[1], sys.argv[2]
recs = [
    {"type": "user", "message": {"role": "user", "content": "fix the parser bug"}},
    {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": "tu1", "name": "Edit",
         "input": {"file_path": js, "old_string": "1", "new_string": "2"}}]}},
    {"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "tu1", "content": "The file has been updated."}]}},
]
open(path, "w").write("\n".join(json.dumps(r) for r in recs) + "\n")
PY
M=0
te() { # <want rc> <reply>
  M=$((M + 1))
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[3],"transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$ETR" "$2" "te-$M" \
  | CLAUDE_PROJECT_DIR="$SB" LESSON_REMINDER=0 BUG_LINK_REMINDER=0 RED_PROOF=0 \
    bash "$HOOKS/test_evidence_gate.sh" >/dev/null 2>"$TMP/err"
  rc=$?
  [ "$rc" = "$1" ] && ok "test_evidence '$2' -> exit $rc" || fail "test_evidence '$2': want exit $1, got $rc"
}
te 2 "12/12 tests passed."
te 2 "Tests OK (12)."
te 2 "The suite is green: 12/12 passed."
te 2 "Bug is gone; patched app.js and everything passes."
te 2 "Đã sửa hàm parse, chạy lại thấy ổn."
te 0 "I will run the tests next."
te 0 "Đã sửa hàm parse, chưa chạy test."
te 0 "Patched app.js; running npm test next to see if everything is fine."
te 0 "Chạy lại sau khi sửa hàm parse."

echo ""
echo "reply_status: ${PASS} ok, ${FAIL} failed"
[ "$FAIL" = 0 ]
