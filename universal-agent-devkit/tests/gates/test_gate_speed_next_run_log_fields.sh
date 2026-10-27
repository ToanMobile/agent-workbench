#!/usr/bin/env bash
# Test hồi quy #472 mục C: mỗi dòng runs.jsonl của post-fix-gate có đủ dữ liệu để đo theo task, theo tải máy và theo lý do chạy full
# (scripts/governance/gate_speed_report.py): task (giá trị --task), load1 (số), ncpu (số nguyên > 0), changed_files (list đường dẫn
# tương đối của repo), ran_suites (list id suite có chạy), force_reason ("" khi impacted, "--full" khi --full), merge_point (bool).
# Gate thật trong repo tạm, một suite: lượt impacted rồi lượt --full.
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
cp "$R/.git/postfix-gate/runs.jsonl" "$TMP/impacted.jsonl" 2>/dev/null
OUT2="$(cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --full --no-cache --no-checklist 2>&1)"

python3 -I - "$TMP/impacted.jsonl" "$RC" "$R/.git/postfix-gate/runs.jsonl" <<'PY'
import json, sys
path, rc, path2 = sys.argv[1], sys.argv[2], sys.argv[3]
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
chk(r.get("force_reason") == "" and r.get("mode") == "impacted", "lượt impacted: force_reason rỗng (có: %r, mode %r)" % (r.get("force_reason"), r.get("mode")))
chk(r.get("merge_point") is False, "repo tạm không phải điểm gộp: merge_point false (có: %r)" % r.get("merge_point"))
try:
    r2 = json.loads(open(path2).read().splitlines()[-1])
except (OSError, IndexError, ValueError) as e:
    r2 = {}
chk(r2.get("force_reason") == "--full" and r2.get("mode") == "full", "lượt --full: force_reason = --full (có: %r, mode %r)" % (r2.get("force_reason"), r2.get("mode")))
print("PASS" if not fails else "FAIL: %d" % fails)
sys.exit(1 if fails else 0)
PY
