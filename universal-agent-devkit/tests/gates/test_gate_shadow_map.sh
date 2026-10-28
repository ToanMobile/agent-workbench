#!/usr/bin/env bash
# #476: map suite → file nguồn sinh tự động từ lệnh + bao đóng + sổ learned (không từ watch_files), và chế độ shadow:
# lượt impacted ghi shadow_skip (suite cách chọn cũ chạy mà map bỏ) + shadow_miss (trong số đó, suite FAIL) vào runs.jsonl,
# không bao giờ đổi suite nào chạy. Case 1-3: SuiteCache.trace_map / shadow_select; case 4: gate thật.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL CI DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE DEVKIT_PER_TEST_CACHE DEVKIT_SHADOW_MAP
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$HOME" "$SB_HEAVY_SLOT_DIR"
FAILS=0

R="$TMP/work"
mkdir -p "$R/src" "$R/tests" && git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
echo 'x = 1' > "$R/src/a.py"; echo 'y = 1' > "$R/src/b.py"
printf '# reads src/a.py\nimport sys\nsys.exit(0)\n' > "$R/tests/t1.py"
cat > "$R/matrix.json" <<'JSON'
{"project":"t","rules":[
 {"component":"A","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"python3 tests/t1.py"}]},
 {"component":"B","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-B","name":"b","command":"true"}]}
]}
JSON
git -C "$R" add -A && git -C "$R" commit -qm init

python3 -I - "$DEVKIT_DIR/bin" "$R" <<'PY' || FAILS=$((FAILS + 1))
import json, sys
sys.path.insert(0, sys.argv[1])
import suite_cache as sc
R = sys.argv[2]
rules = json.load(open(R + "/matrix.json"))["rules"]
c = sc.SuiteCache(R, rules, R + "/matrix.json", {}, "abc", "fmt", {})
tests = [t for r in rules for t in r["mandatory_regression_tests"]]
bad = 0
def chk(cond, msg):
    global bad
    print(("✔ " if cond else "✖ ") + msg); bad += 0 if cond else 1
m = c.trace_map(tests)
chk(m.get("REG-A") is not None and "src/a.py" in m["REG-A"] and "tests/t1.py" in m["REG-A"], "1. map REG-A có tests/t1.py và src/a.py (bao đóng của lệnh): %r" % (m.get("REG-A"),))
chk("src/b.py" not in (m.get("REG-A") or []), "2. map không lấy src/b.py từ watch_files")
run, skip = c.shadow_select(tests, ["src/b.py"])
chk(skip == ["REG-A", "REG-B"] and not run, "3a. đổi src/b.py: map bỏ cả hai (run=%r skip=%r)" % (run, skip))
run, skip = c.shadow_select(tests, ["src/a.py"])
chk(run == ["REG-A"] and skip == ["REG-B"], "3b. đổi src/a.py: chỉ REG-A chạy (run=%r skip=%r)" % (run, skip))
sys.exit(1 if bad else 0)
PY

# 4. gate thật: impacted đổi src/b.py ⇒ runs.jsonl có shadow_skip, suite vẫn chạy như cũ
echo 'y = 2' > "$R/src/b.py"
( cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --no-checklist --task T-476 >"$TMP/out" 2>&1 )
python3 -I - "$R/.git/postfix-gate/runs.jsonl" <<'PY' || FAILS=$((FAILS + 1))
import json, sys
try:
    r = json.loads(open(sys.argv[1]).read().splitlines()[-1])
except (OSError, IndexError, ValueError) as e:
    print("✖ 4. không đọc được runs.jsonl: %s" % e); sys.exit(1)
ok = sorted(r.get("shadow_skip") or []) == ["REG-A", "REG-B"] and r.get("shadow_miss") == [] and sorted(r.get("ran_suites") or []) == ["REG-A", "REG-B"]
print(("✔" if ok else "✖") + " 4. shadow_skip=%r shadow_miss=%r ran_suites=%r (cách chọn cũ vẫn chạy cả hai)" % (r.get("shadow_skip"), r.get("shadow_miss"), r.get("ran_suites")))
sys.exit(0 if ok else 1)
PY
[ "$FAILS" = 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
