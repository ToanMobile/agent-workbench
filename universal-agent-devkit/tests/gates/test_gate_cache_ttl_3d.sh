#!/usr/bin/env bash
# Test hồi quy (05/11, lệnh chủ repo "tăng 6h lên 3 ngày"): hạn tuổi mặc định của PASS được dùng lại là 3 ngày (259200 s), không còn 6 h,
# ở cả ba chỗ đọc DEVKIT_GATE_CACHE_MAX_S khi biến không đặt:
#   T1/T2. SuiteCache.hit (khoá nội dung, bin/suite_cache.py MAX_AGE_S): PASS 2 ngày tuổi dùng lại được; 4 ngày tuổi thì không.
#   T3/T4. post-fix-gate cached_full_pass (biên nhận --full): biên nhận 2 ngày tuổi còn hiệu lực; 4 ngày tuổi thì không.
#   T5/T6. post-fix-gate _scoped_reuse_max_s (biên nhận scoped): mặc định 259200; biến ghi đè vẫn thắng (3600).
# Trước khi đổi: mặc định 21600 ⇒ T1, T3, T5 ĐỎ. Python stdlib, bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SUITE_CACHE DEVKIT_GATE_CACHE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R/src"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
echo 'x = 1' > "$R/src/a.py"
printf '{"project":"t","rules":[{"component":"A","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"a","command":"true"}]}]}\n' > "$R/matrix.json"
git -C "$R" add -A && git -C "$R" commit -qm init

OUT="$(python3 - "$DEVKIT_DIR/bin" "$R" <<'PY' 2>&1
import hashlib, importlib.util, json, os, sys, time
bindir, repo = sys.argv[1:]
sys.path.insert(0, bindir)
import suite_cache as sc_mod   # bản của checkout đang kiểm
import tree_fp
DAY = 86400
now = time.time()

# T1/T2: SuiteCache.hit theo tuổi last_pass_at
rules = json.load(open(os.path.join(repo, "matrix.json")))["rules"]
sc = sc_mod.SuiteCache(repo, rules, os.path.join(repo, "matrix.json"), {}, "L1", 1, {})
test = {"id": "REG-1", "command": "true"}
for label, age, want in (("T1 PASS 2 ngày tuổi (khoá nội dung): dùng lại", 2 * DAY, True),
                         ("T2 PASS 4 ngày tuổi (khoá nội dung): không dùng lại", 4 * DAY, False)):
    key = hashlib.sha256(label.encode()).hexdigest()
    sc.record(key, test, "PASS", at=now - age)
    got = sc.hit(key, test, now=now) is not None
    print(("OK " if got == want else "BAD ") + label + f": hit={got} (mong {want})")

# T3/T4: cached_full_pass theo tuổi tested_at (băm cây / trạng thái cục bộ giả như tests/gates/test_gate_cache_order.sh)
gate = os.path.join(bindir, "post-fix-gate.py")
spec = importlib.util.spec_from_file_location("pfg_ttl", gate)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
mod.local_state_sha = lambda project_dir: "L1"
tree_fp.tree_fingerprint = lambda project_dir: "FP"
matrix = os.path.join(repo, "matrix.json")
path = tree_fp.receipt_path(repo)
os.makedirs(os.path.dirname(path), exist_ok=True)
good = {"exit": 0, "result_format": mod.RESULT_FORMAT, "matrix_sha": mod._sha_file(mod.find_matrix_path(matrix)), "local_sha": "L1",
        "fingerprint": "FP", "tests": [{"id": "REG-1", "status": "PASS"}]}
for label, age, want in (("T3 biên nhận --full 2 ngày tuổi: còn hiệu lực", 2 * DAY, True),
                         ("T4 biên nhận --full 4 ngày tuổi: hết hạn", 4 * DAY, False)):
    json.dump(dict(good, tested_at=now - age), open(path, "w"))
    got = mod.cached_full_pass(repo, matrix, fp="FP") is not None
    print(("OK " if got == want else "BAD ") + label + f": dùng lại={got} (mong {want})")

# T5/T6: hạn của biên nhận scoped
v = mod._scoped_reuse_max_s()
print(("OK " if v == 3 * DAY else "BAD ") + f"T5 hạn biên nhận scoped mặc định: {v} (mong {3 * DAY})")
os.environ["DEVKIT_GATE_CACHE_MAX_S"] = "3600"
v = mod._scoped_reuse_max_s()
print(("OK " if v == 3600 else "BAD ") + f"T6 DEVKIT_GATE_CACHE_MAX_S=3600 vẫn ghi đè: {v}")
PY
)"
for c in T1 T2 T3 T4 T5 T6; do
  line="$(printf '%s\n' "$OUT" | grep -E "^(OK|BAD) $c " | head -1)"
  case "$line" in OK*) ok "${line#OK }" ;; BAD*) fail "${line#BAD }" ;; *) fail "$c: không có kết quả"; printf '%s\n' "$OUT" | tail -5 ;; esac
done

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_cache_ttl_3d: all passed" || { echo "❌ test_gate_cache_ttl_3d: $FAILS failed"; exit 1; }
