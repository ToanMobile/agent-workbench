#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 5b + 6): đo lọt lưới của heavy gate dựng lại lượt --scoped của commit ứng viên bằng ĐÚNG
# scoped_gate.cap_selection, nên test bị hoãn tới heavy gate (deferred_to_heavy) tính là KHÔNG chạy ở PR. Test hoãn mà đỏ được báo là
# "deferred", không phải lọt lưới (không thẻ bug của bộ chọn). escape_check chỉ đếm đỏ MỚI (run.info["new_red"]); đỏ kinh niên bỏ qua.
# Repo giả: c1 sửa bin/x.py; tests/test_x.sh và tests/test_y.sh đều nhắc x.py — cap giữ test hạng đầu (test_x.sh: trùng tên), hoãn test_y.sh.
#   d1. REG-X-01 (test_x.sh) chạy ở c1: không lọt, không deferred;
#   d2. REG-Y-01 (test_y.sh) bị hoãn ở c1: nằm trong escape.deferred, không trong escaped, không thẻ;
#   d3. REG-Z-01 (test_z.sh, không ai chọn) đỏ kinh niên (không trong new_red): không vào mẫu, không thẻ; checked = 2;
#   d4. không có new_red (người gọi cũ): REG-Z-01 vào mẫu và lọt (một thẻ).
# Thẻ giả qua DEVKIT_GATE_FULL_CARD_CMD; slug rỗng (escape_check chỉ gọi gh khi `shutil.which("gh") and slug`). Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-heavy-esc.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

R="$T/repo"; K="$R/universal-agent-devkit"
g init -q "$R"
mkdir -p "$K/tests" "$K/bin" "$R/.agents"
printf '#!/bin/sh\n# chạy bin/x.py\nexit 0\n' >"$K/tests/test_x.sh"
printf '#!/bin/sh\n# cũng chạy bin/x.py\nexit 0\n' >"$K/tests/test_y.sh"
printf '#!/bin/sh\nexit 0\n' >"$K/tests/test_z.sh"
printf '#!/bin/sh\nexit 0\n' >"$K/tests/test_s.sh"
printf 'print("x1")\n' >"$K/bin/x.py"
printf '[core]\n[smoke]\n[core-smoke]\nuniversal-agent-devkit/tests/test_s.sh\n' >"$R/.agents/gate-core.txt"
printf '{"rules": []}\n' >"$R/matrix.json"
g -C "$R" add -A && g -C "$R" commit -qm base
printf 'print("x2")\n' >"$K/bin/x.py"; g -C "$R" commit -qam "🐛 [fix] x (#41)"
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
repo, scratch, c1, logdir, mode = sys.argv[1:6]
run = gate_full.Run(logdir)
run.info.update({"result": "red", "ref": "origin/main", "sha": c1, "red": ["REG-X-01", "REG-Y-01", "REG-Z-01"], "group_b": []})
if mode == "new":
    run.info["new_red"] = ["REG-X-01", "REG-Y-01"]
k = "universal-agent-devkit/tests/"
cand = [{"sha": c1, "pr": 41, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]
run.info["trace"] = {"last_green": "", "range": "r", "commits": [], "tests": [
    {"id": i, "files": [k + f], "candidates": cand} for i, f in (("REG-X-01", "test_x.sh"), ("REG-Y-01", "test_y.sh"), ("REG-Z-01", "test_z.sh"))]}
gate_full.escape_check(run, repo, scratch, c1, os.path.join(repo, "matrix.json"), "")
run.finish()
print(json.dumps(run.info["escape"], ensure_ascii=False))
PY
drive() { CARD_LOG="$T/cards-$1.log" DEVKIT_GATE_FULL_CARD_CMD="$T/card.sh" BIN="$DEVKIT_DIR/bin" \
  python3 "$T/drive.py" "$R" "$T/scratch" "$C1" "$T/log-$1" "$1" 2>"$T/err-$1.txt" | tail -1; }
j() { printf '%s' "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)" 2>/dev/null; }

OUT="$(drive new)"
[ -n "$OUT" ] || { echo "✖ escape_check không chạy được: $(tail -5 "$T/err-new.txt")"; exit 1; }
chk "d1. REG-X-01 chạy ở c1: không lọt, không deferred" \
  '[ "$(j "[e[\"id\"] for e in d[\"escaped\"] + d.get(\"deferred\", []) if e[\"id\"] == \"REG-X-01\"]")" = "[]" ]' "$OUT"
chk "d2. REG-Y-01 bị hoãn ở c1: trong escape.deferred, không trong escaped" \
  '[ "$(j "[e[\"id\"] for e in d.get(\"deferred\", [])]")" = "['"'"'REG-Y-01'"'"']" ] && [ "$(j "[e[\"id\"] for e in d[\"escaped\"]]")" = "[]" ]' "$OUT"
chk "d3. REG-Z-01 kinh niên (không trong new_red): ngoài mẫu, checked 2, không thẻ" \
  '[ "$(j "d[\"checked\"]")" = 2 ] && [ ! -s "$T/cards-new.log" ]' "$OUT $(cat "$T/cards-new.log" 2>/dev/null)"
chk "d2b. summary ghi deferred" 'grep -q "deferred" "$T/log-new/summary-latest.md"' "$(tail -5 "$T/log-new/summary-latest.md")"
OUT="$(drive all)"
chk "d4. không new_red: REG-Z-01 vào mẫu và lọt, đúng một thẻ" \
  '[ "$(j "(d[\"checked\"], [e[\"id\"] for e in d[\"escaped\"]])")" = "(3, ['"'"'REG-Z-01'"'"'])" ] && [ "$(grep -c -- "^---$" "$T/cards-all.log")" = 1 ]' "$OUT"

echo
[ "$fails" -eq 0 ] && { echo "PASS test_gate_full_heavy_escape_deferred"; exit 0; }
echo "FAIL test_gate_full_heavy_escape_deferred ($fails)"; exit 1
