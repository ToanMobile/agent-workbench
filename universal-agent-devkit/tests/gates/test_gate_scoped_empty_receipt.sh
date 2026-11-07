#!/usr/bin/env bash
# v26 mục 1 (audit PR #1046): cached_scoped_pass (bin/post-fix-gate.py) nhận biên nhận scoped `tests: []` CHỈ khi scope là scoped và
# scoped_tests, smoke, core_smoke đều rỗng (lượt không có test liên quan), như proof_gate.sh và tree_fp.receipt_for_tree. Không rộng hơn:
#   e1  tests [] + scoped_tests/smoke/core_smoke rỗng + quyết định rỗng ⇒ trả biên nhận
#   e2  tests [] + một trong scoped_tests / smoke / core_smoke có phần tử ⇒ malformed
#   e3  tests [] nhưng quyết định hiện tại có test ⇒ superset (không mượn)
#   e4  tests [] với scope khác scoped ⇒ malformed
#   e5  biên nhận có test như cũ vẫn nhận
# Gọi thẳng hàm (importlib), repo git tạm. Tương thích bash 3.2, chỉ Python stdlib.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
unset DEVKIT_GATE_CACHE_MAX_S
R="$TMP/repo"
mkdir -p "$R/.agents" && git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t \
  && git -C "$R" config commit.gpgsign false || exit 1
echo '{"project":"t","rules":[]}' > "$R/.agents/regression_matrix.active.json"
echo 'a = 1' > "$R/a.py" && git -C "$R" add -A && git -C "$R" commit -qm init || exit 1

cd "$R" && python3 - "$DEVKIT_DIR/bin/post-fix-gate.py" "$R" <<'PY'
import importlib.util, json, os, sys, time
gate, proj = sys.argv[1:]
spec = importlib.util.spec_from_file_location("pfg", gate)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
matrix = os.path.join(proj, ".agents", "regression_matrix.active.json")
fp, base = "f" * 64, "b" * 40
fails = 0

def receipt(**kw):
    r = {"scope": "scoped", "exit": 0, "project": proj, "tested_at": time.time(), "result_format": m.RESULT_FORMAT,
         "gate_sha": m._sha_file(m.__file__), "matrix_sha": m._sha_file(m.find_matrix_path(matrix)), "fingerprint": fp,
         "base": base, "local_sha": m.local_state_sha(proj), "tests": [], "scoped_tests": [], "smoke": [], "core_smoke": [],
         "not_run": []}
    r.update(kw)
    return r

def check(name, r, decision, want):
    global fails
    path = os.path.join(proj, name + ".json")
    with open(path, "w") as f:
        json.dump(r, f)
    why = []
    got = m.cached_scoped_pass(proj, matrix, fp, decision, path, why)
    res = "ok" if got is not None else (why[0] if why else "?")
    if res == want:
        print(f"✔ {name}: {res}")
    else:
        print(f"✖ {name}: want {want} got {res} why={why}"); fails += 1

empty = {"base_sha": base, "tests": [], "smoke": [], "core_smoke": [], "not_run": []}
check("e1_empty_scoped", receipt(), empty, "ok")
check("e2_scoped_tests", receipt(scoped_tests=["REG-A"]), empty, "malformed")
check("e2_smoke", receipt(smoke=["REG-S"]), empty, "malformed")
check("e2_core_smoke", receipt(core_smoke=["REG-C"]), empty, "malformed")
check("e3_decision_has_tests", receipt(), dict(empty, tests=["REG-A"]), "superset")
check("e4_not_scoped", receipt(scope="full"), empty, "malformed")
one = [{"id": "REG-A", "status": "PASS", "log": None, "duration": "1s", "full_command": "true", "ran_at": time.time()}]
check("e5_with_tests", receipt(tests=one, scoped_tests=["REG-A"]), dict(empty, tests=["REG-A"]), "ok")
sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" -eq 0 ] && { echo "PASS test_gate_scoped_empty_receipt"; exit 0; }
echo "FAIL test_gate_scoped_empty_receipt"; exit 1
