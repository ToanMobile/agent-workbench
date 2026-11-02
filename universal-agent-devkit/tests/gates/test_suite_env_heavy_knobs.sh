#!/usr/bin/env bash
# Test hồi quy (PR 1 gate kẹt và chậm, P3): ba núm pool heavy (bin/heavy_slot.py: DEVKIT_SLOT_HEAVY_MAX, DEVKIT_SLOT_HEAVY_WAIT_S,
# DEVKIT_SLOT_HEAVY_BUDGET_S) là núm của MỘT lần gate, như DEVKIT_GATE_SLOTS: suite_env() (bin/post-fix-gate.py) không cho chúng lọt
# xuống suite — gate lồng trong suite (test_gate_slot_classes.sh…) đọc trần / thời gian chờ của lượt cha ⇒ merge gate FAIL oan
# REG-DK-SLOT-CLASSES-01 (02/11 17:46). DEVKIT_GATE_SLOT_HELD vẫn truyền xuống (T0056, INSTINCT-046), biến khác của người gọi cũng vậy.
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"   # bản của checkout đang kiểm (INSTINCT-057)
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# probe <NAME=value>… → tên biến suite_env() giữ lại, mỗi dòng một tên
probe() {
  env "$@" python3 - "$GATE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("post_fix_gate", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
print("\n".join(sorted(mod.suite_env())))
PY
}

kept="$(probe DEVKIT_SLOT_HEAVY_MAX=1 DEVKIT_SLOT_HEAVY_WAIT_S=5 DEVKIT_SLOT_HEAVY_BUDGET_S=5 DEVKIT_GATE_SLOT_HELD=1 DEVKIT_PROBE_KEEP=1)" \
  || { echo "✖ could not import $GATE"; exit 1; }
printf '%s\n' "$kept" | grep -qx DEVKIT_PROBE_KEEP || { echo "✖ suite_env probe returned nothing"; exit 1; }
for v in DEVKIT_SLOT_HEAVY_MAX DEVKIT_SLOT_HEAVY_WAIT_S DEVKIT_SLOT_HEAVY_BUDGET_S; do
  printf '%s\n' "$kept" | grep -qx "$v" && fail "suite_env keeps $v" || ok "suite_env drops $v"
done
printf '%s\n' "$kept" | grep -qx DEVKIT_GATE_SLOT_HELD && ok "suite_env keeps DEVKIT_GATE_SLOT_HELD (T0056)" \
  || fail "suite_env drops DEVKIT_GATE_SLOT_HELD (T0056: gate lồng phải biết slot đã giữ)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_suite_env_heavy_knobs: PASS"; exit 0; }
echo "test_suite_env_heavy_knobs: FAIL ($FAILS)"
exit 1
