#!/usr/bin/env bash
# Test hồi quy #616: ba suite shard REG-DK-ALL-GATES-01, REG-DK-ALL-WORKTREE-01, REG-DK-ALL-REST-01 THAY REG-DK-ALL-01 trong ma trận active.
# REG-DK-ALL-01 (rule devkit-all) đã bỏ — chạy song song với shard thì mỗi gate chạy phần REG-DK-ALL hai lần. Kiểm: ALL-01 vắng, ba shard
# có mặt đúng lệnh, mỗi shard theo dõi ít nhất các glob rule devkit-all cũ theo dõi (universal-agent-devkit/*), và chạy THẬT
# run_impacted.sh --list trên cây hiện tại: ba tập shard hợp lại đúng tập của lệnh không shard (lệnh cũ của ALL-01), không trùng nhau,
# với mọi test tests/<dir>/test_*.sh và hooks/tests/test_*.sh giả làm "đã đổi" (DEVKIT_IMPACT_TEST_CHANGED, chỉ có hiệu lực với --list).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
out="$(python3 -I - "$ROOT" <<'PY'
import glob, json, os, re, subprocess, sys
root = sys.argv[1]
cur = json.load(open(root + "/.agents/regression_matrix.active.json"))
rules = cur["rules"]
ids = [t["id"] for r in rules for t in r.get("mandatory_regression_tests", [])]
shard = ["REG-DK-ALL-GATES-01", "REG-DK-ALL-WORKTREE-01", "REG-DK-ALL-REST-01"]
print("all01_absent", "REG-DK-ALL-01" not in ids and not any(r.get("component") == "devkit-all" for r in rules))
print("order", [i for i in ids if i in shard] == shard)
cmds = {t["id"]: t["command"] for r in rules for t in r["mandatory_regression_tests"]}
print("cmds", [cmds.get(i) for i in shard])
watch = {t["id"]: set(r.get("watch_files", [])) for r in rules for t in r["mandatory_regression_tests"]}
print("watch", all("universal-agent-devkit/*" in watch.get(i, set()) for i in shard))
# Lệnh thật của từng shard trên cây hiện tại; tập đủ = lệnh không shard (lệnh của REG-DK-ALL-01 trước khi bỏ).
kit = root + "/universal-agent-devkit"
every = sorted(os.path.relpath(p, kit) for p in glob.glob(kit + "/tests/*/test_*.sh") + glob.glob(kit + "/hooks/tests/test_*.sh"))
env = {k: v for k, v in os.environ.items() if k not in ("DEVKIT_GATE_DONE", "DEVKIT_IMPACTED_DIRS", "DEVKIT_IMPACTED_SINCE")}
env["DEVKIT_IMPACT_TEST_CHANGED"] = "\n".join(every)
def listed(dirs):
    e = dict(env)
    if dirs is not None:
        e["DEVKIT_IMPACTED_DIRS"] = dirs
    r = subprocess.run(["bash", kit + "/tests/run_impacted.sh", "--list"], env=e, capture_output=True, text=True, timeout=120)
    return r.returncode, r.stdout.split()
rc0, full = listed(None)
parts, rcs = [], [rc0]
for i in shard:
    m = re.fullmatch(r"DEVKIT_IMPACTED_DIRS=(\S+) bash universal-agent-devkit/tests/run_impacted\.sh", cmds.get(i) or "")
    rc, sel = listed(m.group(1)) if m else (1, [])
    rcs.append(rc); parts.append(sel)
flat = [t for p in parts for t in p]
print("list_rc", rcs)
print("full_covers_every", len(every) > 0 and set(every) <= set(full))
print("union", sorted(flat) == sorted(full) and len(flat) == len(set(flat)))
print("dirs", sorted({t.split("/")[1] for t in full if t.startswith("tests/")}) == sorted({os.path.basename(os.path.dirname(p)) for p in glob.glob(kit + "/tests/*/test_*.sh")}))
PY
)"
echo "$out" | grep -qx 'all01_absent True' && ok "REG-DK-ALL-01 và rule devkit-all đã bỏ khỏi ma trận" || fail "REG-DK-ALL-01 còn trong ma trận: $out"
echo "$out" | grep -qx 'order True' && ok "ba shard có mặt, đúng thứ tự GATES, WORKTREE, REST" || fail "thứ tự shard: $out"
echo "$out" | grep -qx "cmds \['DEVKIT_IMPACTED_DIRS=gates bash universal-agent-devkit/tests/run_impacted.sh', 'DEVKIT_IMPACTED_DIRS=worktree_git bash universal-agent-devkit/tests/run_impacted.sh', 'DEVKIT_IMPACTED_DIRS=!gates,!worktree_git bash universal-agent-devkit/tests/run_impacted.sh'\]" \
  && ok "ba lệnh chia gates / worktree_git / phần còn lại" || fail "lệnh shard: $out"
echo "$out" | grep -qx 'watch True' && ok "mỗi shard theo dõi universal-agent-devkit/* (phủ như rule devkit-all cũ)" || fail "shard theo dõi thiếu: $out"
echo "$out" | grep -qx 'list_rc \[0, 0, 0, 0\]' && ok "run_impacted.sh --list chạy được cho lệnh đủ và cả ba shard" || fail "--list lỗi: $out"
echo "$out" | grep -qx 'full_covers_every True' && ok "lệnh không shard chọn mọi tests/<dir>/test_*.sh và hooks/tests/test_*.sh" || fail "tập đủ thiếu test: $out"
echo "$out" | grep -qx 'union True' && ok "ba shard hợp lại đúng tập của lệnh không shard, không trùng" || fail "hợp ba shard khác tập đủ: $out"
echo "$out" | grep -qx 'dirs True' && ok "mọi thư mục tests/<dir> có test đều được một shard phủ" || fail "thư mục tests/<dir> không được phủ: $out"
[ "$FAILS" -eq 0 ] && echo "✅ test_matrix_shard_rules: all passed" || { echo "❌ test_matrix_shard_rules: $FAILS failed"; exit 1; }
