#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 6 + 7): đo lọt lưới của heavy gate dựng lại lượt --scoped của commit ứng viên. Commit lên main đã qua
# điểm gộp, nơi gate tiêm guard [merge-guard] (∪ của base) SAU cap_selection, nên guard và test nó nêu tên tính là ĐÃ CHẠY: guard đỏ
# không phải lọt lưới, cũng không phải deferred. _scoped_pick dùng scoped_gate.merge_guards như post-fix-gate.
# Repo giả: c1 sửa bin/x.py và xoá REG-H-01 khỏi [merge-guard] (base vẫn có).
#   g1. REG-G-01 (guard, watch_files không khớp, test_g.sh không nhắc x.py): không lọt, không deferred;
#   g2. REG-D-01 (guard, test_d.sh nhắc x.py nên cap hoãn nó): không deferred, không lọt;
#   g3. REG-H-01 chỉ có trong [merge-guard] của base (c1 xoá nó): vẫn tính đã chạy;
#   g4. đối chứng: REG-Z-01 (không phải guard, không ai chọn) vẫn lọt, đúng một thẻ; checked = 4.
# Thẻ giả qua DEVKIT_GATE_FULL_CARD_CMD; slug rỗng. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-heavy-guard.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

R="$T/repo"; K="$R/universal-agent-devkit"; k="universal-agent-devkit/tests"
g init -q "$R"
mkdir -p "$K/tests" "$K/bin" "$R/.agents"
printf '#!/bin/sh\n# chạy bin/x.py\nexit 0\n' >"$K/tests/test_x.sh"
printf '#!/bin/sh\n# cũng chạy bin/x.py\nexit 0\n' >"$K/tests/test_d.sh"
for n in g h z s; do printf '#!/bin/sh\nexit 0\n' >"$K/tests/test_$n.sh"; done
printf 'print("x1")\n' >"$K/bin/x.py"
core() { printf '[core]\n[smoke]\n[core-smoke]\n%s/test_s.sh\n[merge-guard]\n%s\n' "$k" "$1" >"$R/.agents/gate-core.txt"; }
core "$(printf 'REG-G-01\nREG-D-01\nREG-H-01')"
cat >"$R/matrix.json" <<JSON
{"rules": [{"component": "Guards", "watch_files": ["nothing/**"], "mandatory_regression_tests": [
  {"id": "REG-G-01", "command": "bash $k/test_g.sh"},
  {"id": "REG-D-01", "command": "bash $k/test_d.sh"},
  {"id": "REG-H-01", "command": "bash $k/test_h.sh"}]}]}
JSON
g -C "$R" add -A && g -C "$R" commit -qm base
printf 'print("x2")\n' >"$K/bin/x.py"
core "$(printf 'REG-G-01\nREG-D-01')"
g -C "$R" commit -qam "🐛 [fix] x (#41)"
C1="$(g -C "$R" rev-parse HEAD)"
g -C "$R" worktree add -q --detach "$T/scratch" "$C1"
cat >"$T/card.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >>"$CARD_LOG"; printf '%s\n' '---' >>"$CARD_LOG"
echo "https://github.com/o/r/issues/77"
SH
chmod +x "$T/card.sh"
cat >"$T/drive.py" <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["BIN"])
import gate_full
repo, scratch, c1, logdir = sys.argv[1:5]
run = gate_full.Run(logdir)
ids = [("REG-G-01", "test_g.sh"), ("REG-D-01", "test_d.sh"), ("REG-H-01", "test_h.sh"), ("REG-Z-01", "test_z.sh")]
run.info.update({"result": "red", "ref": "origin/main", "sha": c1, "red": [i for i, _ in ids], "group_b": [],
                 "new_red": [i for i, _ in ids]})
k = "universal-agent-devkit/tests/"
cand = [{"sha": c1, "pr": 41, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]
run.info["trace"] = {"last_green": "", "range": "r", "commits": [], "tests": [
    {"id": i, "files": [k + f], "candidates": cand} for i, f in ids]}
gate_full.escape_check(run, repo, scratch, c1, os.path.join(repo, "matrix.json"), "")
run.finish()
print(json.dumps(run.info["escape"], ensure_ascii=False))
PY
OUT="$(CARD_LOG="$T/cards.log" DEVKIT_GATE_FULL_CARD_CMD="$T/card.sh" BIN="$DEVKIT_DIR/bin" \
  python3 "$T/drive.py" "$R" "$T/scratch" "$C1" "$T/log" 2>"$T/err.txt" | tail -1)"
[ -n "$OUT" ] || { echo "✖ escape_check không chạy được: $(tail -5 "$T/err.txt")"; exit 1; }
j() { printf '%s' "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)" 2>/dev/null; }
hit() { j "[e[\"id\"] for e in d[\"escaped\"] + d.get(\"deferred\", []) if e[\"id\"] == \"$1\"]"; }

chk "g1. guard REG-G-01 (không ai chọn ở PR): không lọt, không deferred" '[ "$(hit REG-G-01)" = "[]" ]' "$OUT"
chk "g2. guard REG-D-01 (cap hoãn test của nó): không deferred, không lọt" '[ "$(hit REG-D-01)" = "[]" ]' "$OUT"
chk "g3. REG-H-01 chỉ trong [merge-guard] của base: vẫn tính đã chạy" '[ "$(hit REG-H-01)" = "[]" ]' "$OUT"
chk "g4. đối chứng REG-Z-01 (không phải guard) vẫn lọt, checked 4, một thẻ" \
  '[ "$(j "(d[\"checked\"], [e[\"id\"] for e in d[\"escaped\"]])")" = "(4, ['"'"'REG-Z-01'"'"'])" ] && [ "$(grep -c -- "^---$" "$T/cards.log")" = 1 ]' \
  "$OUT"

echo
[ "$fails" -eq 0 ] && { echo "PASS test_gate_full_heavy_escape_guard"; exit 0; }
echo "FAIL test_gate_full_heavy_escape_guard ($fails)"; exit 1
