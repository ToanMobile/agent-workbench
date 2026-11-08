#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 10, review P3 lane F): điểm gộp = đường dẫn scratch (.merge-scratch-* / .train-scratch-* /
# .integrate-scratch-*) VÀ dấu DEVKIT_MERGE_POINT=1 do chính merge gate / merge train / integrate đặt. Gate lồng trong một suite có fixture
# nằm dưới .merge-scratch-* (đường dẫn khớp) không được nhận độ rộng 6 / sàn slot / guard tiêm của điểm gộp.
#   a  đường dẫn khớp, không dấu: không phải điểm gộp; merge_wide_parallel giữ cap
#   b  đường dẫn khớp + dấu: điểm gộp
#   c  dấu mà đường dẫn không khớp: không phải điểm gộp
#   d  suite_env() bỏ DEVKIT_MERGE_POINT: gate lồng trong suite không thừa hưởng dấu của gate cha
#   e  ba điểm gộp thật đặt dấu cho lệnh verify
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_MERGE_POINT DEVKIT_GATE_PARALLEL DEVKIT_MERGE_PARALLEL DEVKIT_MERGE_WIDE_LOAD_MAX
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="$(cd "$DEVKIT_DIR/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# độ rộng bật tường minh (mặc định tắt từ lượt đo tải 08/11): ca a vẫn chứng minh thiếu dấu thì không rộng ra
OUT="$(DEVKIT_CAPACITY_LOAD=0 DEVKIT_MERGE_WIDE_LOAD_MAX=24 python3 - "$GATE" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("pfg_mp", sys.argv[1]); m = importlib.util.module_from_spec(spec)
sys.modules["pfg_mp"] = m; spec.loader.exec_module(m)
nested = "/tmp/x/.merge-scratch-7/repo/tests/fixture"
os.environ.pop("DEVKIT_MERGE_POINT", None)
a = (m.at_merge_point(nested), m.merge_wide_parallel(4, nested))
os.environ["DEVKIT_MERGE_POINT"] = "1"
b = m.at_merge_point(nested)
c = m.at_merge_point("/tmp/x/repo")
d = "DEVKIT_MERGE_POINT" in m.suite_env()
print("a=%s,%s b=%s c=%s d=%s" % (a[0], a[1], b, c, d))
PY
)"
case "$OUT" in *"a=False,4 "*) ok "a. đường dẫn khớp, không dấu: không phải điểm gộp, độ rộng giữ cap" ;; *) fail "a. $OUT" ;; esac
case "$OUT" in *" b=True "*) ok "b. đường dẫn khớp + dấu: điểm gộp" ;; *) fail "b. $OUT" ;; esac
case "$OUT" in *" c=False "*) ok "c. dấu mà đường dẫn không khớp: không phải điểm gộp" ;; *) fail "c. $OUT" ;; esac
case "$OUT" in *" d=False"*) ok "d. suite_env bỏ DEVKIT_MERGE_POINT" ;; *) fail "d. $OUT" ;; esac

n=$(grep -c 'DEVKIT_MERGE_POINT=1' "$ROOT/.claude/bin/super-board-merge-gate.sh" 2>/dev/null); n=${n:-0}
t=$(grep -c 'DEVKIT_MERGE_POINT=1' "$ROOT/.claude/bin/super-board-merge-train.sh" 2>/dev/null); t=${t:-0}
i=$(grep -c 'DEVKIT_MERGE_POINT="1"' "$DEVKIT_DIR/scripts/git/integrate.py" 2>/dev/null); i=${i:-0}
if [ ! -f "$ROOT/.claude/bin/super-board-merge-gate.sh" ]; then
  ok "e. (kit ngoài agent-workbench: chỉ kiểm integrate.py)"; [ "$i" -ge 1 ] || fail "e. integrate.py không đặt dấu"
else
  [ "$n" -ge 3 ] && [ "$t" -ge 1 ] && [ "$i" -ge 1 ] && ok "e. merge gate, train, integrate đặt dấu" || fail "e. merge-gate=$n train=$t integrate=$i"
fi

echo
[ "$FAILS" -eq 0 ] && { echo "test_gate_merge_point_marker: PASS"; exit 0; } || { echo "test_gate_merge_point_marker: FAIL ($FAILS)"; exit 1; }
