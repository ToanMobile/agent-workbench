#!/usr/bin/env bash
# Test hồi quy #472 mục B: test đã commit bị sửa (không chỉ thêm) và chưa ai duyệt: gate (lượt CLI) trả UNTESTED (exit_reason
# edited_test) TRƯỚC khi lấy khoá dự án và chạy suite nào. Baseline 24-27/10: 29/55 lượt edited_test đã chạy suite rồi mới bị loại.
# Suite ghi một dòng vào marker khi chạy. Đối chứng: cùng thay đổi mà test đã được duyệt (duyệt chéo, #605) thì suite vẫn chạy.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL CI DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE DEVKIT_PER_TEST_CACHE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$HOME/.claude/projects" "$SB_HEAVY_SLOT_DIR"
# #605: test sửa chỉ được duyệt chéo — ghi mục {path, sha256, reviewer, author, task_id, reason} do "agent khác" duyệt
cross_approve() {   # cross_approve <repo> <path>...
  # Audit T0066 (#605): mục duyệt chỉ tính khi task_id có biên bản audit pass của antigravity-pm (ngoài repo, ở đây dưới $TMP)
  # ghi `auditedHead: <sha>` của cây chứa đúng nội dung test hiện tại. `git stash create`: commit của cây làm việc, không đổi
  # index/HEAD/refs; task_id riêng theo cây để lần duyệt sau không ghi đè biên bản của lần trước.
  export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm-state"
  python3 - "$@" <<'PY'
import hashlib, json, os, subprocess, sys
root, paths = sys.argv[1], sys.argv[2:]
def git(*a):
    return subprocess.run(["git", "-C", root, *a], capture_output=True, text=True).stdout.strip()
head = git("stash", "create") or git("rev-parse", "HEAD")
tid = "T-fixture-" + head[:12]
td = os.path.join(os.environ["ANTIGRAVITY_PM_STATE_HOME"], "projects", "fixture", "tasks", tid); os.makedirs(td, exist_ok=True)
with open(os.path.join(td, "task.json"), "w") as fh:
    json.dump({"id": tid, "project": os.path.realpath(root),
               "verdicts": {"audit": {"verdict": "pass", "reviewer": "pm", "notes": "fixture\nauditedHead: " + head}}}, fh)
d = os.path.join(root, ".claude", "audit-gate"); os.makedirs(d, exist_ok=True)
ap = [{"path": p, "sha256": hashlib.sha256(open(os.path.join(root, p), "rb").read()).hexdigest(), "reviewer": "antigravity",
       "author": "claude", "task_id": tid, "reason": "fixture: diff test đã được agent khác đọc"} for p in paths]
with open(os.path.join(d, "approved_tests.json"), "w") as fh:
    json.dump({"approvals": ap}, fh)
PY
}

R="$TMP/work"
mkdir -p "$R/src" "$R/tests" && git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> %s/ran; sh tests/test_old.sh"}]}]}\n' "$TMP" > "$R/matrix.json"
echo 'fun ok()=1' > "$R/src/Core.kt"
printf '#!/bin/sh\nexit 0\n' > "$R/tests/test_old.sh"
git -C "$R" add -A && git -C "$R" commit -qm init
echo 'fun ok()=2' > "$R/src/Core.kt"
printf '#!/bin/sh\ntrue\n' > "$R/tests/test_old.sh"   # sửa một dòng có sẵn: không phải chỉ thêm
: > "$TMP/empty.jsonl"                                 # transcript rỗng: không ai duyệt
OUT="$(cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --no-checklist --transcript "$TMP/empty.jsonl" 2>&1)"; RC=$?

FAILS=0
LAST="$(tail -n 1 "$R/.git/postfix-gate/runs.jsonl" 2>/dev/null)"
V="$(printf '%s' "$LAST" | python3 -c 'import json,sys
try: r=json.loads(sys.stdin.read())
except ValueError: r={}
print(r.get("verdict",""), r.get("exit_reason",""))')"
# điều kiện tiền đề (đúng cả hôm nay): gate nhận ra test sửa chưa duyệt — không thì ca dưới không chứng minh gì
if [ "$V" = "UNTESTED edited_test" ] && [ "$RC" = 2 ]; then echo "✔ gate trả UNTESTED edited_test (rc=$RC)"
else echo "✖ tiền đề: gate không trả UNTESTED edited_test (rc=$RC, log: $V): $(printf '%s' "$OUT" | tail -3)"; FAILS=$((FAILS + 1)); fi
if [ ! -f "$TMP/ran" ]; then echo "✔ không suite nào chạy trước khi trả UNTESTED"
else echo "✖ suite đã chạy ($(wc -l < "$TMP/ran" | tr -d ' ') lần) rồi mới trả UNTESTED"; FAILS=$((FAILS + 1)); fi
if [ ! -e "$R/.claude/audit-gate/test_run.lock" ]; then echo "✔ không lấy khoá dự án (test_run.lock chưa từng được tạo)"
else echo "✖ gate đã mở khoá dự án test_run.lock dù kết luận chắc chắn là UNTESTED"; FAILS=$((FAILS + 1)); fi
# đối chứng: test sửa đã được duyệt thì suite chạy bình thường (không xanh nhờ bỏ suite)
cross_approve "$R" tests/test_old.sh
OUT="$(cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --no-checklist --transcript "$TMP/empty.jsonl" 2>&1)"; RC=$?
if [ -f "$TMP/ran" ] && [ "$RC" = 0 ]; then echo "✔ đối chứng: test sửa đã duyệt chéo thì suite chạy, exit 0"
else echo "✖ đối chứng: test sửa đã duyệt mà suite không chạy hoặc không exit 0 (rc=$RC): $(printf '%s' "$OUT" | tail -3)"; FAILS=$((FAILS + 1)); fi
[ "$FAILS" = 0 ] && echo "PASS" || echo "FAIL: $FAILS"
exit $(( FAILS > 0 ))
