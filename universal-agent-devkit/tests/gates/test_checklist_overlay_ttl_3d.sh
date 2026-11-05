#!/usr/bin/env bash
# Test hồi quy #992 (P3 review PR #995): hạn PASS dùng lại đã thành 3 ngày (DEVKIT_GATE_CACHE_MAX_S mặc định 259200 ở post-fix-gate.py
# và suite_cache.py) nhưng regression_checklist._overlay_fresh vẫn mặc định 21600 (6 h) ⇒ worktree linked có biên nhận 6 h–3 ngày bị
# STALE, --full chạy lại. Nay cùng 3 ngày:
#  O1. không đặt biến: bản ghi 2 ngày tuổi còn tin được (code cũ: không)
#  O2. không đặt biến: bản ghi 4 ngày tuổi hết hạn
#  O3. DEVKIT_GATE_CACHE_MAX_S=3600 vẫn ghi đè: 2 giờ tuổi hết hạn; giá trị rác rơi về mặc định 3 ngày
#  O4. tương lai (> +60 s) và bool vẫn bị từ chối
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
probe() {   # probe <tuổi giây, âm = tương lai | bool> [giá trị DEVKIT_GATE_CACHE_MAX_S]
  env -u DEVKIT_GATE_CACHE_MAX_S ${2:+DEVKIT_GATE_CACHE_MAX_S="$2"} python3 -c '
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("rc", sys.argv[1] + "/bin/regression_checklist.py")
m = importlib.util.module_from_spec(spec); sys.path.insert(0, sys.argv[1] + "/bin"); spec.loader.exec_module(m)
a = sys.argv[2]
print(m._overlay_fresh(True if a == "bool" else time.time() - float(a)))' "$DEVKIT_DIR" "$1"
}
[ "$(probe 172800)" = True ] && ok "O1. mặc định: 2 ngày tuổi còn tin được" || fail "O1. mặc định: 2 ngày tuổi bị coi là cũ (vẫn 6 h?)"
[ "$(probe 345600)" = False ] && ok "O2. mặc định: 4 ngày tuổi hết hạn" || fail "O2. mặc định: 4 ngày tuổi vẫn được tin"
[ "$(probe 7200 3600)" = False ] && ok "O3. DEVKIT_GATE_CACHE_MAX_S=3600 ghi đè: 2 giờ tuổi hết hạn" || fail "O3. biến không ghi đè được"
[ "$(probe 172800 rac)" = True ] && ok "O3. giá trị rác: rơi về mặc định 3 ngày" || fail "O3. giá trị rác không rơi về 3 ngày"
[ "$(probe -3600)" = False ] && [ "$(probe bool)" = False ] && ok "O4. tương lai và bool bị từ chối" || fail "O4. nhận dấu thời gian tương lai/bool"
[ "$FAILS" = 0 ] && { echo "test_checklist_overlay_ttl_3d: PASS"; exit 0; }
echo "test_checklist_overlay_ttl_3d: FAIL ($FAILS)"; exit 1
