#!/usr/bin/env bash
# Test ĐỎ cho đợt tăng tốc gate (#472, mục 5) — XFAIL: mặc định in SKIP và thoát 0; GATE_SPEED_NEXT=1 chạy thật.
# Mỗi dòng runs.jsonl của post-fix-gate cần đủ dữ liệu để đo theo task và theo tải máy (scripts/governance/gate_speed_report.py):
#   task (giá trị --task), load1 (số), ncpu (số nguyên > 0), changed_files (list đường dẫn tương đối của repo), ran_suites (list id suite có chạy).
# Gate thật trong repo tạm, một suite. Bỏ dòng skip khi #472 xong và test XANH.
if [ "${GATE_SPEED_NEXT:-0}" != 1 ]; then echo "SKIP (xfail #472): runs.jsonl chưa có task/load1/ncpu/changed_files/ran_suites — GATE_SPEED_NEXT=1 để chạy thật"; exit 0; fi
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL CI DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE DEVKIT_PER_TEST_CACHE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$HOME" "$SB_HEAVY_SLOT_DIR"

R="$TMP/work"
mkdir -p "$R/src" && git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}\n' > "$R/matrix.json"
echo 'fun ok()=1' > "$R/src/Core.kt"
git -C "$R" add -A && git -C "$R" commit -qm init
echo 'fun ok()=2' > "$R/src/Core.kt"
OUT="$(cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --no-checklist --task T-472 2>&1)"; RC=$?

python3 -I - "$R/.git/postfix-gate/runs.jsonl" "$RC" <<'PY'
import json, sys
path, rc = sys.argv[1], sys.argv[2]
fails = 0
def chk(cond, msg):
    global fails
    print(("✔ " if cond else "✖ ") + msg)
    fails += 0 if cond else 1
try:
    line = open(path).read().splitlines()[-1]
    r = json.loads(line)
except (OSError, IndexError, ValueError) as e:
    print("✖ không đọc được dòng runs.jsonl (gate rc=%s): %s" % (rc, e)); sys.exit(1)
num = lambda x: isinstance(x, (int, float)) and not isinstance(x, bool)
chk(r.get("task") == "T-472", "task = giá trị --task (có: %r)" % r.get("task"))
chk(num(r.get("load1")) and r["load1"] >= 0, "load1 là số >= 0 (có: %r)" % r.get("load1"))
chk(isinstance(r.get("ncpu"), int) and not isinstance(r.get("ncpu"), bool) and r["ncpu"] > 0, "ncpu là số nguyên > 0 (có: %r)" % r.get("ncpu"))
chk(r.get("changed_files") == ["src/Core.kt"], "changed_files = [src/Core.kt] (có: %r)" % r.get("changed_files"))
chk(r.get("ran_suites") == ["REG-1"], "ran_suites = [REG-1] (có: %r)" % r.get("ran_suites"))
print("PASS" if not fails else "FAIL: %d" % fails)
sys.exit(1 if fails else 0)
PY
