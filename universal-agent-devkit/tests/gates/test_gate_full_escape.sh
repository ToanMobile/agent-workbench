#!/usr/bin/env bash
# Test hồi quy (đo lọt lưới, 03/11): lượt gate-full đêm đỏ kiểm, với mỗi suite đỏ có commit ứng viên trong truy vết (#759), gate scoped
# của commit đó (scoped_gate.decide + no_full tại chính commit, base = cha) có chọn test ấy không. Không chọn ⇒ "lọt lưới": mở thẻ bug
# (mã test + file đổi) và ghi escape_rate vào summary + trace-latest.json. Chỉ đo và báo: không đổi verdict, exit hay thẻ đỏ của lượt.
# Repo giả: base → c1 "(#21)" sửa bin/a.py (tests/test_a.sh nhắc tên a.py: đồ thị chọn nó) → c2 "(#22)" sửa bin/b.py (không test nào nhắc).
#   t1. REG-A-01 (test_a.sh, ứng viên c1): được chọn — không lọt;
#   t2. REG-B-01 (test_b.sh, ứng viên c2): không chọn — lọt lưới, kèm PR 22 và file đổi bin/b.py;
#   t3. REG-D-01 (lệnh thường, watch_files khớp bin/b.py của c2): luật ma trận chọn cả suite — không lọt;
#   t4. REG-C-01 (ứng viên "không rõ"): không tính vào mẫu (rate cả bộ: xem t4/t9/t10);
#   t5. đúng một thẻ bug cho mỗi suite lọt, có mã test + file đổi; scratch quay về đỉnh;
#   t6. summary-latest.md có mục "Lọt lưới", trace-latest.json có khối escape;
#   t7. không ứng viên nào kiểm được ⇒ không thẻ, rate null.
#   (review 03/11) c3 "(#23)" sửa bin/c.py, tests/test_c.py nhắc tên nó nhưng không luật ma trận nào chạy test py ⇒ gate PR bỏ (skip, #741):
#   t8. REG-E-01 (test_c.py) lọt lưới dù decide chọn file;
#   t9. suite nhóm b (group_b) và ứng viên chỉ là nghi vấn chia đôi không đụng file (hit false) không vào mẫu;
#   t10. commit gốc (không có cha) không tái dựng được: không vào mẫu.
#   (review Grok 03/11)
#   t11. REG-F-01: luật watch khớp FILE TEST scoped chọn (test_a.sh) chạy cả lệnh suite (scoped_suites) — không lọt;
#   t12. REG-J-01: suite không có file test (lệnh pytest) mà luật không khớp — vẫn vào mẫu, lọt;
#   t13. REG-K-01: luật chỉ có trong ma trận SAU commit ứng viên c2 (thêm ở c3) — gate của PR #22 không có luật đó ⇒ lọt.
#   (review OCR 03/11)
#   t14. REG-L-01: test py bị bỏ ở c3 kéo [core-smoke] tests/test_s.sh; luật watch test_s.sh (lệnh pytest) được gate thêm ở lần gọi
#        scoped_suites thứ hai — không lọt;
#   t15. decide ném lỗi ở một commit ⇒ chỉ commit đó không vào mẫu, các suite khác vẫn đo, có ghi chú.
#   (review Claude 03/11) t16. REG-M-01 (test_b.sh, ứng viên c1): ở c1 luật F chạy cả lệnh `bash …/test_b.sh` — file đó ĐÃ chạy dù mang
#   mã suite khác ⇒ không lọt. Cả bộ: checked 9, lọt 4 (B E J K), rate 0.444.
#   (03/11) t17–t19 trên repo giả thứ hai: luật cha + luật chỉ-thêm (như gate PR), thứ tự `ran - skipped` (xem khối cuối).
# Thẻ giả qua DEVKIT_GATE_FULL_CARD_CMD; slug rỗng nên không gọi gh (PATH giữ nguyên: python3 mặc định như gate). Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-escape.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

R="$T/repo"
g init -q "$R"
K="$R/universal-agent-devkit"
mkdir -p "$K/tests" "$K/bin" "$R/.agents"
printf '#!/bin/sh\n# chạy bin/a.py\nexit 0\n' >"$K/tests/test_a.sh"
printf '#!/bin/sh\nexit 0\n' >"$K/tests/test_b.sh"
printf '#!/bin/sh\nexit 0\n' >"$K/tests/test_d.sh"
printf 'print("a1")\n' >"$K/bin/a.py"
printf 'print("b1")\n' >"$K/bin/b.py"
printf '#!/bin/sh\nexit 0\n' >"$K/tests/test_s.sh"
printf '[core]\n[smoke]\n[core-smoke]\nuniversal-agent-devkit/tests/test_s.sh\n' >"$R/.agents/gate-core.txt"
cat >"$R/matrix.json" <<'JSON'
{"rules": [
 {"component": "B", "watch_files": ["docs/**"], "mandatory_regression_tests": [{"id": "REG-B-01", "command": "bash universal-agent-devkit/tests/test_b.sh"}]},
 {"component": "D", "watch_files": ["universal-agent-devkit/bin/b.py"], "mandatory_regression_tests": [{"id": "REG-D-01", "command": "bash universal-agent-devkit/tests/test_d.sh"}]},
 {"component": "F", "watch_files": ["universal-agent-devkit/tests/test_a.sh"], "mandatory_regression_tests": [{"id": "REG-F-01", "command": "bash universal-agent-devkit/tests/test_b.sh"}]},
 {"component": "J", "watch_files": ["docs/**"], "mandatory_regression_tests": [{"id": "REG-J-01", "command": "pytest -q pkg"}]},
 {"component": "L", "watch_files": ["universal-agent-devkit/tests/test_s.sh"], "mandatory_regression_tests": [{"id": "REG-L-01", "command": "pytest -q lpkg"}]}
]}
JSON
g -C "$R" add -A && g -C "$R" commit -qm base
printf 'print("a2")\n' >"$K/bin/a.py"; g -C "$R" commit -qam "🐛 [fix] a (#21)"
C1="$(g -C "$R" rev-parse HEAD)"
printf 'print("b2")\n' >"$K/bin/b.py"; g -C "$R" commit -qam "🐛 [fix] b (#22)"
C2="$(g -C "$R" rev-parse HEAD)"
printf '# chạy bin/c.py\nprint(1)\n' >"$K/tests/test_c.py"; printf 'print("c1")\n' >"$K/bin/c.py"
python3 - "$R/matrix.json" <<'PYM'
import json, sys
d = json.load(open(sys.argv[1]))
d["rules"].append({"component": "K", "watch_files": ["universal-agent-devkit/bin/b.py"],
                   "mandatory_regression_tests": [{"id": "REG-K-01", "command": "bash universal-agent-devkit/tests/test_b.sh"}]})
json.dump(d, open(sys.argv[1], "w"))
PYM
g -C "$R" add -A; g -C "$R" commit -qm "🧪 [test] c + luật K"   # luật K sau PR #22; c3 chỉ sửa bin/c.py
printf 'print("c2")\n' >"$K/bin/c.py"; g -C "$R" commit -qam "🐛 [fix] c (#23)"
C3="$(g -C "$R" rev-parse HEAD)"
C0="$(g -C "$R" rev-list --max-parents=0 HEAD)"
g -C "$R" worktree add -q --detach "$T/scratch" "$C3"

cat >"$T/card.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >>"$CARD_LOG"
printf '%s\n' '---' >>"$CARD_LOG"
echo "https://github.com/o/r/issues/99"
SH
chmod +x "$T/card.sh"

cat >"$T/drive.py" <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["BIN"])
import gate_full
repo, scratch, c1, c2, c3, c0, logdir, mode = sys.argv[1:9]
run = gate_full.Run(logdir)
run.info.update({"result": "red", "ref": "origin/main", "sha": c3, "red": ["REG-A-01", "REG-B-01", "REG-C-01", "REG-D-01", "REG-E-01", "REG-G-01", "REG-H-01", "REG-I-01"],
                 "group_b": ["REG-G-01"]})
run.info["red"] += ["REG-F-01", "REG-J-01", "REG-K-01", "REG-L-01", "REG-M-01"]
k = "universal-agent-devkit/tests/"
if mode == "none":
    tests = [{"id": "REG-C-01", "files": [k + "test_b.sh"], "candidates": [{"confidence": "không rõ", "why": "-"}]}]
else:
    tests = [{"id": "REG-A-01", "files": [k + "test_a.sh"], "candidates": [{"sha": c1, "pr": 21, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]},
             {"id": "REG-B-01", "files": [k + "test_b.sh"], "candidates": [{"sha": c2, "pr": 22, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]},
             {"id": "REG-C-01", "files": [k + "test_b.sh"], "candidates": [{"confidence": "không rõ", "why": "-"}]},
             {"id": "REG-D-01", "files": [k + "test_d.sh"], "candidates": [{"sha": c2, "pr": 22, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]},
             {"id": "REG-E-01", "files": [k + "test_c.py"], "candidates": [{"sha": c3, "pr": 23, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]},
             {"id": "REG-G-01", "files": [k + "test_b.sh"], "candidates": [{"sha": c2, "pr": 22, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]},
             {"id": "REG-H-01", "files": [k + "test_b.sh"], "candidates": [{"sha": c1, "pr": 21, "issues": [], "confidence": "nghi", "why": "x", "hit": False}]},
             {"id": "REG-I-01", "files": [k + "test_b.sh"], "candidates": [{"sha": c0, "pr": None, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]},
             {"id": "REG-F-01", "files": [k + "test_b.sh"], "candidates": [{"sha": c1, "pr": 21, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]},
             {"id": "REG-J-01", "files": [], "candidates": [{"sha": c3, "pr": 23, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]},
             {"id": "REG-K-01", "files": [k + "test_b.sh"], "candidates": [{"sha": c2, "pr": 22, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]},
             {"id": "REG-L-01", "files": [], "candidates": [{"sha": c3, "pr": 23, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]},
             {"id": "REG-M-01", "files": [k + "test_b.sh"], "candidates": [{"sha": c1, "pr": 21, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]}]
if mode == "boom":   # decide ném lỗi ở c2: chỉ c2 rơi khỏi mẫu
    import scoped_gate
    real = scoped_gate.decide
    def decide(project, base, **kw):
        if base == c2 + "^":
            raise RuntimeError("đồ thị hỏng")
        return real(project, base, **kw)
    scoped_gate.decide = decide
run.info["trace"] = {"last_green": "", "range": "r", "commits": [], "tests": tests}
gate_full.escape_check(run, repo, scratch, c3, os.path.join(repo, "matrix.json"), "")   # slug rỗng: không tìm thẻ trùng bằng gh
run.finish()
print(json.dumps(run.info["escape"], ensure_ascii=False))
PY

run_drive() {   # $1 = mode, $2 = thư mục log
  CARD_LOG="$T/cards-$1.log" DEVKIT_GATE_FULL_CARD_CMD="$T/card.sh" BIN="$DEVKIT_DIR/bin" \
    python3 "$T/drive.py" "$R" "$T/scratch" "$C1" "$C2" "$C3" "$C0" "$2" "$1" 2>"$T/err-$1.txt" | tail -1
}
OUT="$(run_drive all "$T/log")"
[ -n "$OUT" ] || { echo "✖ escape_check không chạy được:"; tail -5 "$T/err-all.txt"; exit 1; }
j() { printf '%s' "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

chk "t1. REG-A-01 được chọn ở c1 (không lọt)" '[ "$(j "\"REG-A-01\" in [e[\"id\"] for e in d[\"escaped\"]]")" = False ]' "$OUT"
chk "t2. REG-B-01 lọt lưới ở PR 22, file đổi bin/b.py" \
  '[ "$(j "[(e[\"id\"], e[\"pr\"], e[\"files\"]) for e in d[\"escaped\"] if e[\"id\"] == \"REG-B-01\"]")" = "[('"'"'REG-B-01'"'"', 22, ['"'"'universal-agent-devkit/bin/b.py'"'"'])]" ]' "$OUT"
chk "t3. REG-D-01 do watch_files của luật chọn (không lọt)" '[ "$(j "\"REG-D-01\" in [e[\"id\"] for e in d[\"escaped\"]]")" = False ]' "$OUT"
chk "t4/t9/t10. REG-C/G/H/I-01 không tính; checked 9, rate 0.444" '[ "$(j "(d[\"checked\"], round(d[\"rate\"], 3))")" = "(9, 0.444)" ]' "$OUT"
chk "t16. REG-M-01: file test chạy dưới lệnh suite F ở c1 — không lọt" '[ "$(j "\"REG-M-01\" in [e[\"id\"] for e in d[\"escaped\"]]")" = False ]' "$OUT"
chk "t14. REG-L-01 do luật watch file [core-smoke] (lần gọi scoped_suites thứ hai) — không lọt" '[ "$(j "\"REG-L-01\" in [e[\"id\"] for e in d[\"escaped\"]]")" = False ]' "$OUT"
chk "t11. REG-F-01 do luật watch khớp file test đã chọn (không lọt)" '[ "$(j "\"REG-F-01\" in [e[\"id\"] for e in d[\"escaped\"]]")" = False ]' "$OUT"
chk "t12/t13. REG-J-01 (không file test) và REG-K-01 (luật mới sau PR) lọt" '[ "$(j "sorted(e[\"id\"] for e in d[\"escaped\"] if e[\"id\"] in (\"REG-J-01\", \"REG-K-01\"))")" = "['"'"'REG-J-01'"'"', '"'"'REG-K-01'"'"']" ]' "$OUT"
chk "t8. REG-E-01 (test py bị gate PR bỏ qua) lọt lưới" '[ "$(j "\"REG-E-01\" in [e[\"id\"] for e in d[\"escaped\"]]")" = True ]' "$OUT"
chk "t5. đúng bốn thẻ bug (REG-B/E/J/K-01) kèm file đổi" \
  '[ "$(grep -c -- "^---$" "$T/cards-all.log" 2>/dev/null)" = 4 ] && grep -q "REG-B-01" "$T/cards-all.log" && grep -q "^bug$" "$T/cards-all.log" && grep -q "universal-agent-devkit/bin/b.py" "$T/cards-all.log"' \
  "$(cat "$T/cards-all.log" 2>/dev/null | head -20)"
chk "t5b. scratch quay về đỉnh c3" '[ "$(g -C "$T/scratch" rev-parse HEAD)" = "$C3" ]'
chk "t6. summary có mục Lọt lưới, trace-latest.json có escape" \
  'grep -q "Lọt lưới" "$T/log/summary-latest.md" && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d[\"escape\"][\"checked\"] == 9 else 1)" "$T/log/trace-latest.json"' \
  "$(tail -8 "$T/log/summary-latest.md" 2>/dev/null)"
OUT="$(run_drive boom "$T/log3")"
chk "t15. decide lỗi ở c2: B/D/K (chỉ ứng viên c2) rơi khỏi mẫu, còn lại vẫn đo, có ghi chú" \
  '[ "$(j "(d[\"checked\"], sorted(e[\"id\"] for e in d[\"escaped\"]))")" = "(6, ['"'"'REG-E-01'"'"', '"'"'REG-J-01'"'"'])" ] && grep -q "đồ thị hỏng" "$T/log3/summary-latest.md"' "$OUT $(grep -i ghi "$T/log3/summary-latest.md" 2>/dev/null)"
OUT="$(run_drive none "$T/log2")"
chk "t7. không ứng viên kiểm được: không thẻ, rate null" '[ "$(j "(d[\"checked\"], d[\"rate\"], d[\"escaped\"])")" = "(0, None, [])" ] && [ ! -s "$T/cards-none.log" ]' "$OUT"

# Repo giả thứ hai (độ chính xác của bước đo, 03/11):
#   t17. c4 "(#31)" sửa bin/p.py VÀ sửa watch_files của luật P có sẵn (docs/** → bin/p.py): gate PR chạy ma trận của CHA (load_active_matrix
#        + trust_additive_matrix, sửa luật cũ không được tin) ⇒ luật cha không chọn REG-P-01 ⇒ lọt;
#   t18. c5 "(#32)" sửa bin/q.py và NỐI luật N (watch bin/q.py): luật chỉ-thêm của chính PR được tin ⇒ REG-N-01 không lọt;
#   t19. ở c5 tests/test_q.py bị bỏ (skip, không luật nào chạy py) nhưng luật W (watch test_w.sh, gate thêm cả lệnh) chạy
#        `python3 …/test_q.py` ⇒ file đó ĐÃ chạy, REG-Q-01 không lọt.
R2="$T/repo2"
g init -q "$R2"
K2="$R2/universal-agent-devkit"
mkdir -p "$K2/tests" "$K2/bin" "$R2/.agents"
printf '#!/bin/sh\nexit 0\n' >"$K2/tests/test_p.sh"
printf '#!/bin/sh\nexit 0\n' >"$K2/tests/test_n.sh"
printf '#!/bin/sh\n# chạy bin/q.py\nexit 0\n' >"$K2/tests/test_w.sh"
printf '# chạy bin/q.py\nprint(1)\n' >"$K2/tests/test_q.py"
printf 'print("p1")\n' >"$K2/bin/p.py"
printf 'print("q1")\n' >"$K2/bin/q.py"
cp "$R/.agents/gate-core.txt" "$R2/.agents/gate-core.txt"; cp "$K/tests/test_s.sh" "$K2/tests/test_s.sh"
cat >"$R2/matrix.json" <<'JSON'
{"rules": [
 {"component": "P", "watch_files": ["docs/**"], "mandatory_regression_tests": [{"id": "REG-P-01", "command": "bash universal-agent-devkit/tests/test_p.sh"}]},
 {"component": "W", "watch_files": ["universal-agent-devkit/tests/test_w.sh"], "mandatory_regression_tests": [{"id": "REG-W-01", "command": "python3 universal-agent-devkit/tests/test_q.py"}]}
]}
JSON
g -C "$R2" add -A && g -C "$R2" commit -qm base
printf 'print("p2")\n' >"$K2/bin/p.py"
python3 - "$R2/matrix.json" <<'PYM'
import json, sys
d = json.load(open(sys.argv[1]))
d["rules"][0]["watch_files"] = ["universal-agent-devkit/bin/p.py"]
json.dump(d, open(sys.argv[1], "w"))
PYM
g -C "$R2" commit -qam "🐛 [fix] p (#31)"
C4="$(g -C "$R2" rev-parse HEAD)"
printf 'print("q2")\n' >"$K2/bin/q.py"
python3 - "$R2/matrix.json" <<'PYM'
import json, sys
d = json.load(open(sys.argv[1]))
d["rules"].append({"component": "N", "watch_files": ["universal-agent-devkit/bin/q.py"],
                   "mandatory_regression_tests": [{"id": "REG-N-01", "command": "bash universal-agent-devkit/tests/test_n.sh"}]})
json.dump(d, open(sys.argv[1], "w"))
PYM
g -C "$R2" commit -qam "🐛 [fix] q (#32)"
C5="$(g -C "$R2" rev-parse HEAD)"
g -C "$R2" worktree add -q --detach "$T/scratch2" "$C5"
cat >"$T/drive2.py" <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["BIN"])
import gate_full
repo, scratch, c4, c5, logdir = sys.argv[1:6]
run = gate_full.Run(logdir)
run.info.update({"result": "red", "ref": "origin/main", "sha": c5, "red": ["REG-P-01", "REG-N-01", "REG-Q-01"], "group_b": []})
k = "universal-agent-devkit/tests/"
run.info["trace"] = {"last_green": "", "range": "r", "commits": [], "tests": [
    {"id": "REG-P-01", "files": [k + "test_p.sh"], "candidates": [{"sha": c4, "pr": 31, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]},
    {"id": "REG-N-01", "files": [k + "test_n.sh"], "candidates": [{"sha": c5, "pr": 32, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]},
    {"id": "REG-Q-01", "files": [k + "test_q.py"], "candidates": [{"sha": c5, "pr": 32, "issues": [], "confidence": "nghi", "why": "x", "hit": True}]}]}
gate_full.escape_check(run, repo, scratch, c5, os.path.join(repo, "matrix.json"), "")
run.finish()
print(json.dumps(run.info["escape"], ensure_ascii=False))
PY
OUT="$(CARD_LOG="$T/cards-edit.log" DEVKIT_GATE_FULL_CARD_CMD="$T/card.sh" BIN="$DEVKIT_DIR/bin" \
  python3 "$T/drive2.py" "$R2" "$T/scratch2" "$C4" "$C5" "$T/log4" 2>"$T/err-edit.txt" | tail -1)"
[ -n "$OUT" ] || { bad "t17–t19. escape_check repo 2 không chạy được" "$(tail -5 "$T/err-edit.txt")"; OUT='{"checked": -1, "escaped": []}'; }
chk "t17. PR sửa luật P có sẵn: luật CHA quyết ⇒ REG-P-01 lọt" '[ "$(j "\"REG-P-01\" in [e[\"id\"] for e in d[\"escaped\"]]")" = True ]' "$OUT"
chk "t18. luật N chỉ-thêm của chính PR được tin ⇒ REG-N-01 không lọt" '[ "$(j "\"REG-N-01\" in [e[\"id\"] for e in d[\"escaped\"]]")" = False ]' "$OUT"
chk "t19. test_q.py bị bỏ nhưng lệnh suite W chạy nó ⇒ REG-Q-01 không lọt" '[ "$(j "\"REG-Q-01\" in [e[\"id\"] for e in d[\"escaped\"]]")" = False ]' "$OUT"
chk "t17–t19. checked 3, đúng một lọt (REG-P-01)" '[ "$(j "(d[\"checked\"], [e[\"id\"] for e in d[\"escaped\"]])")" = "(3, ['"'"'REG-P-01'"'"'])" ]' "$OUT"

echo
[ "$fails" -eq 0 ] && { echo "PASS test_gate_full_escape"; exit 0; }
echo "FAIL test_gate_full_escape ($fails)"; exit 1
