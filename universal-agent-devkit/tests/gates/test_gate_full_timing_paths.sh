#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 9): nhãn timing theo TỪNG đường test kit. Suite run_impacted.sh (REG-DK-ALL-*) và `agent-kit test` gom
# nhiều test kit vào một mã; nhãn "timing": true (gate_full.timing_ids) gắn cho cả mã suite. Ma trận có khoá gốc
# "timing_paths": {"tests/…": "<bằng chứng>"}; collect_red xếp suite vào nhóm b chỉ khi MỌI đường đỏ của nó có nhãn kèm bằng chứng.
# Nhãn đọc ở ma trận của commit mốc (dòng history green/red/red-env là tổ tiên), không mốc thì cha đầu của đỉnh, KHÔNG ở đỉnh: PR thêm
# nhãn cho test của chính nó (ma trận chỉ-thêm giữ khoá gốc) không được tự miễn chia đôi / lọt lưới.
# Repo giả (scratch): c0 nhãn a (bằng chứng), c (rỗng); c1 thêm nhãn b; c2 (đỉnh) thêm nhãn d.
#   Không history (mốc = cha đỉnh = c1):
#   p1. suite run_impacted đỏ ở tests/a.sh (có nhãn): nhóm b;
#   p2. đỏ ở tests/a.sh + tests/e.sh (e không nhãn): không nhóm b;
#   p3. tests/c.sh có nhãn nhưng bằng chứng rỗng: không nhóm b;
#   p4. agent-kit test đỏ chỉ ở tests/a.sh: nhóm b; thêm tests/e.sh: không;
#   p5. ma trận không có khoá timing_paths: không nhóm b;
#   p6. tests/d.sh chỉ có nhãn ở ĐỈNH: không nhóm b; tests/b.sh có nhãn ở cha: nhóm b;
#   Có history, mốc c0:
#   p7. tests/b.sh (nhãn thêm sau mốc): không nhóm b; tests/a.sh: nhóm b.
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
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }
S="$T/scratch"
g init -q "$S"
mkdir -p "$S/kit/tests" "$T/pg/nightly"
for n in a b c d e; do printf '#!/bin/sh\nexit 1\n' >"$S/kit/tests/$n.sh"; done
EV='"tests/a.sh": "watchdog 7 s dưới tải, nightly 01-03/11", "tests/c.sh": " "'
printf '{"rules": [], "timing_paths": {%s}}\n' "$EV" >"$S/m.json"
printf '{"rules": []}\n' >"$S/m0.json"
g -C "$S" add -A && g -C "$S" commit -qm c0
C0="$(g -C "$S" rev-parse HEAD)"
printf '{"rules": [], "timing_paths": {%s, "tests/b.sh": "flaky"}}\n' "$EV" >"$S/m.json"
g -C "$S" commit -qam c1
printf '{"rules": [], "timing_paths": {%s, "tests/b.sh": "flaky", "tests/d.sh": "flaky"}}\n' "$EV" >"$S/m.json"
g -C "$S" commit -qam c2
C2="$(g -C "$S" rev-parse HEAD)"
cat >"$T/drive.py" <<'PY'
import inspect, json, os, sys
sys.path.insert(0, os.environ["BIN"])
import gate_full
scratch, matrix, logdir, suite_paths, kit_paths, pg, sha = sys.argv[1:8]
lines = lambda s: ["✖ %s" % p for p in s.split(",") if p]
rows = []
if suite_paths:
    rows.append({"id": "REG-DK-ALL-01", "status": "FAIL", "command": "bash kit/tests/run_impacted.sh --all",
                 "fail_lines": lines(suite_paths), "output_tail": ""})
gate_out = json.dumps({"verdict": "FAIL", "exit_code": 1, "matrix_path": matrix, "regression_tests": rows})
run = gate_full.Run(logdir)
kit_out = "\n".join(lines(kit_paths))
kw = {}
if "timing_ref" in inspect.signature(gate_full.collect_red).parameters:   # cmd_run tính ref như vậy
    kw["timing_ref"] = gate_full.timing_ref(pg, scratch, sha)
gate_full.collect_red(run, scratch, "kit", 1, gate_out, 1 if kit_paths else None, kit_out, **kw)
print(json.dumps({"red": run.info["red"], "group_b": run.info["group_b"]}))
PY
drive() { BIN="$DEVKIT_DIR/bin" python3 "$T/drive.py" "$S" "$S/$1" "$T/log" "$2" "$3" "$T/pg" "$C2" 2>"$T/err.txt" | tail -1; }
gb() { printf '%s' "$1" | python3 -c "import json,sys; print(json.load(sys.stdin)['group_b'])" 2>/dev/null; }
SUITE="['REG-DK-ALL-01']"

OUT="$(drive m.json tests/a.sh "")"
[ -n "$OUT" ] || { echo "✖ collect_red không chạy được: $(tail -5 "$T/err.txt")"; exit 1; }
chk "p1. suite đỏ chỉ ở đường có nhãn: nhóm b" '[ "$(gb "$OUT")" = "$SUITE" ]' "$OUT"
OUT="$(drive m.json tests/a.sh,tests/e.sh "")"
chk "p2. thêm một đường không nhãn: không nhóm b" '[ "$(gb "$OUT")" = "[]" ]' "$OUT"
OUT="$(drive m.json tests/c.sh "")"
chk "p3. nhãn bằng chứng rỗng: không nhóm b" '[ "$(gb "$OUT")" = "[]" ]' "$OUT"
OUT="$(drive m.json "" tests/a.sh)"
chk "p4a. agent-kit test đỏ chỉ ở đường có nhãn: nhóm b" '[ "$(gb "$OUT")" = "['"'"'agent-kit test'"'"']" ]' "$OUT"
OUT="$(drive m.json "" tests/a.sh,tests/e.sh)"
chk "p4b. agent-kit test thêm đường không nhãn: không nhóm b" '[ "$(gb "$OUT")" = "[]" ]' "$OUT"
OUT="$(drive m0.json tests/a.sh "")"
chk "p5. ma trận không có timing_paths: không nhóm b" '[ "$(gb "$OUT")" = "[]" ]' "$OUT"
OUT="$(drive m.json tests/d.sh "")"
chk "p6a. nhãn chỉ có ở đỉnh (PR tự gắn): không nhóm b" '[ "$(gb "$OUT")" = "[]" ]' "$OUT"
OUT="$(drive m.json tests/b.sh "")"
chk "p6b. nhãn có ở cha đỉnh (không mốc): nhóm b" '[ "$(gb "$OUT")" = "$SUITE" ]' "$OUT"
printf '{"result": "red", "sha": "%s", "red_tests": {}}\n' "$C0" >"$T/pg/nightly/history.jsonl"
OUT="$(drive m.json tests/b.sh "")"
chk "p7a. mốc c0: nhãn b thêm sau mốc không tính" '[ "$(gb "$OUT")" = "[]" ]' "$OUT"
OUT="$(drive m.json tests/a.sh "")"
chk "p7b. mốc c0: nhãn a có ở mốc: nhóm b" '[ "$(gb "$OUT")" = "$SUITE" ]' "$OUT"

echo
[ "$fails" -eq 0 ] && { echo "PASS test_gate_full_timing_paths"; exit 0; }
echo "FAIL test_gate_full_timing_paths ($fails)"; exit 1
