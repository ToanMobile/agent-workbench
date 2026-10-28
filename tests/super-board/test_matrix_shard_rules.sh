#!/usr/bin/env bash
# Test hồi quy #616 B: ba suite shard của REG-DK-ALL-01 (GATES, WORKTREE, REST) chỉ được THÊM ở cuối ma trận active — REG-DK-ALL-01 còn nguyên,
# gate tin ma trận (matrix_additions trả đúng ba id, không phải None = "cần người review", exit 2) — và ba lệnh chia đủ tập thư mục, không trùng.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
out="$(python3 -I - "$ROOT" <<'PY'
import importlib.util, json, sys
root = sys.argv[1]
spec = importlib.util.spec_from_file_location("pfg", root + "/universal-agent-devkit/bin/post-fix-gate.py")
sys.path.insert(0, root + "/universal-agent-devkit/bin")
pfg = importlib.util.module_from_spec(spec); spec.loader.exec_module(pfg)
cur = json.load(open(root + "/.agents/regression_matrix.active.json"))
ids = [t["id"] for r in cur["rules"] for t in r.get("mandatory_regression_tests", [])]
shard = ["REG-DK-ALL-GATES-01", "REG-DK-ALL-WORKTREE-01", "REG-DK-ALL-REST-01"]
tail = [i for i in ids if i in shard]
print("order", tail == shard)
first = ids.index("REG-DK-ALL-01"); print("all01_before", first < min(ids.index(i) for i in shard))
base = dict(cur); base["rules"] = [r for r in cur["rules"] if not any(t["id"] in shard for t in r["mandatory_regression_tests"])]
print("additions", pfg.matrix_additions(base, cur) == shard)
cmds = {t["id"]: t["command"] for r in cur["rules"] for t in r["mandatory_regression_tests"]}
print("cmds", [cmds[i] for i in shard])
print("all01_cmd", cmds["REG-DK-ALL-01"])
PY
)"
echo "$out" | grep -qx 'order True' && ok "ba shard có mặt, đúng thứ tự GATES, WORKTREE, REST" || fail "thứ tự shard: $out"
echo "$out" | grep -qx 'all01_before True' && ok "REG-DK-ALL-01 vẫn đứng trước các shard" || fail "ALL-01 không đứng trước: $out"
echo "$out" | grep -qx 'additions True' && ok "matrix_additions: chỉ-thêm, trả đúng ba id (gate tin ma trận)" || fail "matrix_additions không trả ba id shard: $out"
echo "$out" | grep -qx 'all01_cmd bash universal-agent-devkit/tests/run_impacted.sh' && ok "lệnh REG-DK-ALL-01 không đổi" || fail "lệnh ALL-01 đổi: $out"
echo "$out" | grep -qx "cmds \['DEVKIT_IMPACTED_DIRS=gates bash universal-agent-devkit/tests/run_impacted.sh', 'DEVKIT_IMPACTED_DIRS=worktree_git bash universal-agent-devkit/tests/run_impacted.sh', 'DEVKIT_IMPACTED_DIRS=!gates,!worktree_git bash universal-agent-devkit/tests/run_impacted.sh'\]" \
  && ok "ba lệnh chia gates / worktree_git / phần còn lại" || fail "lệnh shard: $out"
[ "$FAILS" -eq 0 ] && echo "✅ test_matrix_shard_rules: all passed" || { echo "❌ test_matrix_shard_rules: $FAILS failed"; exit 1; }
