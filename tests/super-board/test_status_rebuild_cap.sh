#!/usr/bin/env bash
# #982: super-board-status.py in `attempt N/<rebuild_cap của config>`, không cứng 3 (cap mặc định 2, runner chặn ở rebuild_cap).
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
out=$(python3 -I - "$ROOT/.claude/bin/super-board-status.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sbstatus", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
item = lambda n: {"labels": [f"loop:rebuild-{n}"] if n else []}
for cfg in ({"rebuild_cap": 2}, {"rebuild_cap": 4}, {}, {"rebuild_cap": 0}):
    m.REBUILD_CAP = m.rebuild_cap_of(cfg)
    print(cfg, [m.attempt_str(item(n)) for n in (0, 1, 2, 5)], m.rebuild_suffix(item(1)))
PY
)
FAILS=0
chk() { printf '%s\n' "$out" | grep -qF -- "$2" && echo "✔ $1" || { echo "✖ $1"; FAILS=$((FAILS + 1)); }; }
chk "cap 2: attempt N/2, clamped at the cap" "{'rebuild_cap': 2} ['1/2', '2/2', '2/2', '2/2'] ↻ 2/2"
chk "cap 4 from config" "{'rebuild_cap': 4} ['1/4', '2/4', '3/4', '4/4'] ↻ 2/4"
chk "unset cap: schema default 2" "{} ['1/2', '2/2', '2/2', '2/2'] ↻ 2/2"
chk "invalid cap 0: default 2" "{'rebuild_cap': 0} ['1/2', '2/2', '2/2', '2/2'] ↻ 2/2"
[ "$FAILS" -eq 0 ] && { echo "test_status_rebuild_cap: PASS"; exit 0; } || { echo "test_status_rebuild_cap: FAIL ($FAILS)"; exit 1; }
