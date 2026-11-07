#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 9): nhãn timing theo TỪNG đường test kit. Suite run_impacted.sh (REG-DK-ALL-*) và `agent-kit test` gom
# nhiều test kit vào một mã; nhãn "timing": true (gate_full.timing_ids) gắn cho cả mã suite. Ma trận có khoá gốc
# "timing_paths": {"tests/…": "<bằng chứng>"}; collect_red xếp suite vào nhóm b chỉ khi MỌI đường đỏ của nó có nhãn kèm bằng chứng.
#   p1. suite run_impacted đỏ ở tests/a.sh (có nhãn): nhóm b;
#   p2. đỏ ở tests/a.sh + tests/b.sh (b không nhãn): không nhóm b;
#   p3. tests/c.sh có nhãn nhưng bằng chứng rỗng: không nhóm b;
#   p4. agent-kit test đỏ chỉ ở tests/a.sh: nhóm b; thêm tests/b.sh: không;
#   p5. không có khoá timing_paths: như cũ (không nhóm b).
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-timing-paths.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scratch/kit/tests"
for n in a b c; do printf '#!/bin/sh\nexit 1\n' >"$T/scratch/kit/tests/$n.sh"; done
printf '{"rules": [], "timing_paths": {"tests/a.sh": "watchdog 7 s dưới tải, nightly 01-03/11", "tests/c.sh": " "}}\n' >"$T/m.json"
printf '{"rules": []}\n' >"$T/m0.json"
cat >"$T/drive.py" <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["BIN"])
import gate_full
scratch, matrix, logdir, suite_paths, kit_paths = sys.argv[1:6]
lines = lambda s: ["✖ %s" % p for p in s.split(",") if p]
rows = []
if suite_paths:
    rows.append({"id": "REG-DK-ALL-01", "status": "FAIL", "command": "bash kit/tests/run_impacted.sh --all",
                 "fail_lines": lines(suite_paths), "output_tail": ""})
gate_out = json.dumps({"verdict": "FAIL", "exit_code": 1, "matrix_path": matrix, "regression_tests": rows})
run = gate_full.Run(logdir)
kit_out = "\n".join(lines(kit_paths))
gate_full.collect_red(run, scratch, "kit", 1, gate_out, 1 if kit_paths else None, kit_out)
print(json.dumps({"red": run.info["red"], "group_b": run.info["group_b"]}))
PY
drive() { BIN="$DEVKIT_DIR/bin" python3 "$T/drive.py" "$T/scratch" "$T/$1" "$T/log" "$2" "$3" 2>"$T/err.txt" | tail -1; }
gb() { printf '%s' "$1" | python3 -c "import json,sys; print(json.load(sys.stdin)['group_b'])" 2>/dev/null; }

OUT="$(drive m.json tests/a.sh "")"
[ -n "$OUT" ] || { echo "✖ collect_red không chạy được: $(tail -5 "$T/err.txt")"; exit 1; }
chk "p1. suite đỏ chỉ ở đường có nhãn: nhóm b" '[ "$(gb "$OUT")" = "['"'"'REG-DK-ALL-01'"'"']" ]' "$OUT"
OUT="$(drive m.json tests/a.sh,tests/b.sh "")"
chk "p2. thêm một đường không nhãn: không nhóm b" '[ "$(gb "$OUT")" = "[]" ]' "$OUT"
OUT="$(drive m.json tests/c.sh "")"
chk "p3. nhãn bằng chứng rỗng: không nhóm b" '[ "$(gb "$OUT")" = "[]" ]' "$OUT"
OUT="$(drive m.json "" tests/a.sh)"
chk "p4a. agent-kit test đỏ chỉ ở đường có nhãn: nhóm b" '[ "$(gb "$OUT")" = "['"'"'agent-kit test'"'"']" ]' "$OUT"
OUT="$(drive m.json "" tests/a.sh,tests/b.sh)"
chk "p4b. agent-kit test thêm đường không nhãn: không nhóm b" '[ "$(gb "$OUT")" = "[]" ]' "$OUT"
OUT="$(drive m0.json tests/a.sh "")"
chk "p5. ma trận không có timing_paths: không nhóm b" '[ "$(gb "$OUT")" = "[]" ]' "$OUT"

echo
[ "$fails" -eq 0 ] && { echo "PASS test_gate_full_timing_paths"; exit 0; }
echo "FAIL test_gate_full_timing_paths ($fails)"; exit 1
