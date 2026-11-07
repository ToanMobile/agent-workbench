#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 6): heavy gate chỉ báo đỏ MỚI. Mốc = dòng history cuối có result green / red / red-env mà sha là tổ
# tiên của sha hiện tại; so đường test và dòng ✖ đã chuẩn hoá (pid, đường tạm, số, sha). Chia đôi RIÊNG từng đỏ mới (≤ 5) từ sha của mốc;
# thẻ riêng mỗi suite mới; ca mới của suite kinh niên ⇒ comment vào thẻ mở của nó nêu ca đó; gh lỗi / thẻ lỗi ⇒ unreported, lượt sau báo lại;
# mốc dạng cũ (không red_tests) chỉ gieo mốc.
# Repo giả, first-parent thẳng: base → c1 → c2 (a.bad: REG-A-01 đỏ, dòng ✖ có pid + đường tạm đổi mỗi lần) → c3 → c4 (b.bad: REG-B-01 đỏ)
# → c5 (a2.bad: ca mới "ca A2" trong REG-A-01) → c6 (c.bad: REG-C-01 đỏ). Gate giả chạy tests/{a,b,c}.sh; thẻ giả; gh giả theo $T/gh.mode.
#   n1. base xanh rồi c3: REG-A-01 đỏ mới ⇒ chia đôi ra c2, một thẻ REG-A-01, history new_red + red_tests;
#   n2. c3 lần nữa: REG-A-01 kinh niên (dòng ✖ khác pid/đường tạm vẫn là cùng ca) ⇒ không thẻ, không chạy lại, exit 1;
#   n3. c4: REG-A-01 kinh niên + REG-B-01 mới ⇒ đúng một thẻ (REG-B-01), nghi vấn riêng của REG-B-01 = c4, REG-A-01 không chia đôi;
#   n4. c5 + thẻ mở của REG-A-01: ca mới "ca A2" ⇒ comment vào thẻ đó nêu "ca A2", không thẻ mới; nghi vấn của REG-A-01 = c5 (khớp ca);
#   n5. c6, gh lỗi: REG-C-01 mới nhưng không mở thẻ, history unreported, red_tests không có REG-C-01; lượt sau gh ổn ⇒ thẻ REG-C-01;
#   n6. hai đỏ mới cùng lượt (không history, last_full_green_sha = base): REG-A-01 ⇒ c2, REG-B-01 ⇒ c4 (mỗi test một nghi vấn);
#   n7. mốc là dòng history dạng cũ (red, không red_tests): không thẻ, có ghi chú gieo mốc.
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GF="$DEVKIT_DIR/bin/gate_full.py"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-new-red.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

g init -q --bare "$T/origin.git"
g init -q "$T/seed"
mkdir -p "$T/seed/tests"
for t in a b c; do
  printf '#!/bin/sh\nr=0\n[ -e %s.bad ] && { echo "✖ ca %s: hỏng pid $$ ở /tmp/x.$$"; r=1; }\n' "$t" "$(printf %s "$t" | tr a-c A-C)" >"$T/seed/tests/$t.sh"
done
printf '[ -e a2.bad ] && { echo "✖ ca A2: hỏng"; r=1; }\n' >>"$T/seed/tests/a.sh"
for t in a b c; do printf 'exit $r\n' >>"$T/seed/tests/$t.sh"; done
g -C "$T/seed" add -A && g -C "$T/seed" commit -qm base
BASE="$(g -C "$T/seed" rev-parse HEAD)"
g -C "$T/seed" remote add origin "$T/origin.git"
g -C "$T/seed" push -q origin main
commit() { [ -n "$1" ] && : >"$T/seed/$1"; printf '%s\n' "$2" >>"$T/seed/log.txt"; g -C "$T/seed" add -A; g -C "$T/seed" commit -qm "$2"; g -C "$T/seed" rev-parse HEAD; }
g clone -q "$T/origin.git" "$T/repo"
COMMON="$(cd "$T/repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
HIST="$COMMON/postfix-gate/nightly/history.jsonl"

cat >"$T/fakegate.py" <<'PY'
import json, os, subprocess, sys
tests, red = [], False
for t in ("a", "b", "c"):
    p = subprocess.run(["sh", "tests/%s.sh" % t], capture_output=True, text=True)
    sid = "REG-%s-01" % t.upper()
    if p.returncode:
        red = True
        tests.append({"id": sid, "status": "FAIL", "command": "sh tests/%s.sh" % t, "fail_lines": p.stdout.splitlines(), "output_tail": p.stdout})
    else:
        tests.append({"id": sid, "status": "PASS", "command": "sh tests/%s.sh" % t})
if not red:
    d = subprocess.run(["git", "rev-parse", "--absolute-git-dir"], capture_output=True, text=True).stdout.strip() + "/postfix-gate"
    os.makedirs(d, exist_ok=True)
    open(d + "/full_pass.json", "w").write("{}")
print(json.dumps({"verdict": "FAIL" if red else "PASS", "exit_code": int(red), "regression_tests": tests}, ensure_ascii=False))
sys.exit(int(red))
PY
cat >"$T/fakecard.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >>"$CARD_LOG"; printf '%s\n' '---' >>"$CARD_LOG"
echo "Created https://github.com/fake/repo/issues/99"
SH
mkdir -p "$T/bin"
cat >"$T/bin/gh" <<SH
#!/bin/sh
echo "\$@" >>"$T/gh.calls"
mode="\$(cat "$T/gh.mode" 2>/dev/null)"
case "\$1 \$2" in
  "issue comment") exit 0 ;;
esac
[ "\$mode" = fail ] && exit 1
if [ "\$mode" = cardA ] && echo "\$@" | grep -q REG-A-01; then
  echo '[{"title": "🐛 [fix] P1 gate-full đêm 2026-01-01: REG-A-01 đỏ", "url": "https://github.com/fake/repo/issues/5", "body": ""}]'
  exit 0
fi
echo '[]'
SH
chmod +x "$T/fakecard.sh" "$T/bin/gh"
export PATH="$T/bin:$PATH" CARD_LOG="$T/cards.log"
export DEVKIT_GATE_FULL_CMD="python3 $T/fakegate.py" DEVKIT_GATE_FULL_CARD_CMD="sh $T/fakecard.sh"
export DEVKIT_GATE_FULL_LOG_DIR="$T/logs" DEVKIT_GATE_FULL_POLL_S=1 DEVKIT_CAPACITY_LOAD=0 DEVKIT_GATE_FULL_GLOBAL_LOCK="$T/global.lock"
unset DEVKIT_GATE_FULL_BISECT

push() { g -C "$T/seed" push -q origin main; }
run_gf() { rm -f "$T/cards.log" "$T/gh.calls"; python3 "$GF" run --repo "$T/repo" --slug fake/repo --timeout 30 >"$T/out" 2>&1; echo $?; }
cards() { if [ -f "$T/cards.log" ]; then grep -c -- '^---$' "$T/cards.log"; else echo 0; fi; }
row() { tail -1 "$HIST" | python3 -c "import json,sys; r=json.load(sys.stdin); print($1)" 2>/dev/null; }

rc=$(run_gf)
chk "n0. base xanh (mốc)" '[ "$rc" = 0 ] && [ "$(row "r[\"result\"]")" = green ]' "rc=$rc $(tail -3 "$T/out")"
C1=$(commit "" c1); C2=$(commit a.bad c2); C3=$(commit "" c3); push
rc=$(run_gf)
chk "n1. REG-A-01 đỏ mới: exit 1, nghi vấn c2, một thẻ REG-A-01" \
  '[ "$rc" = 1 ] && [ "$(row "r[\"suspects\"][\"REG-A-01\"][\"sha\"]")" = "$C2" ] && [ "$(cards)" = 1 ] && grep -q "P1 gate-full đêm .*: REG-A-01 đỏ" "$T/cards.log"' \
  "rc=$rc cards=$(cards) $(tail -1 "$HIST" | cut -c1-600)"
chk "n1b. history: new_red [REG-A-01], red_tests có REG-A-01 với dòng ✖ chuẩn hoá" \
  '[ "$(row "r[\"new_red\"]")" = "['"'"'REG-A-01'"'"']" ] && row "r[\"red_tests\"][\"REG-A-01\"][\"cases\"]" | grep -q "pid <n>"' "$(tail -1 "$HIST" | cut -c1-600)"
rc=$(run_gf)
chk "n2. c3 lần nữa: REG-A-01 kinh niên ⇒ không thẻ, không chia đôi, exit 1" \
  '[ "$rc" = 1 ] && [ "$(cards)" = 0 ] && [ "$(row "r[\"new_red\"]")" = "[]" ] && ! grep -q "chia đôi đỏ mới" "$T/out" && grep -q "kinh niên" "$T/logs/summary-latest.md"' \
  "rc=$rc cards=$(cards) $(tail -1 "$HIST" | cut -c1-400)"
C4=$(commit b.bad c4); push
rc=$(run_gf)
chk "n3. c4: REG-B-01 mới ⇒ đúng một thẻ REG-B-01, nghi vấn c4; REG-A-01 không chia đôi" \
  '[ "$rc" = 1 ] && [ "$(cards)" = 1 ] && grep -q ": REG-B-01 đỏ" "$T/cards.log" && ! grep -q ": REG-A-01 đỏ" "$T/cards.log" \
   && [ "$(row "r[\"suspects\"][\"REG-B-01\"][\"sha\"]")" = "$C4" ] && [ "$(row "sorted(r[\"suspects\"])")" = "['"'"'REG-B-01'"'"']" ]' \
  "rc=$rc cards=$(cards) $(tail -1 "$HIST" | cut -c1-500)"
C5=$(commit a2.bad c5); push
echo cardA >"$T/gh.mode"
rc=$(run_gf)
chk "n4. ca mới 'ca A2' trong REG-A-01: comment vào thẻ #5 nêu ca đó, không thẻ mới, nghi vấn c5" \
  '[ "$(cards)" = 0 ] && grep "issue comment https://github.com/fake/repo/issues/5" "$T/gh.calls" | grep -q "ca A2" \
   && [ "$(row "r[\"suspects\"][\"REG-A-01\"][\"sha\"]")" = "$C5" ]' \
  "rc=$rc cards=$(cards) gh=$(cat "$T/gh.calls" 2>/dev/null | cut -c1-300) $(tail -1 "$HIST" | cut -c1-500)"
C6=$(commit c.bad c6); push
echo fail >"$T/gh.mode"
rc=$(run_gf)
chk "n5. gh lỗi: REG-C-01 mới không mở thẻ, history unreported, red_tests không có REG-C-01" \
  '[ "$(cards)" = 0 ] && [ "$(row "r.get(\"unreported\")")" = "['"'"'REG-C-01'"'"']" ] && [ "$(row "\"REG-C-01\" in r[\"red_tests\"]")" = False ]' \
  "rc=$rc cards=$(cards) $(tail -1 "$HIST" | cut -c1-500)"
: >"$T/gh.mode"
rc=$(run_gf)
chk "n5b. lượt sau gh ổn: REG-C-01 vẫn là đỏ mới ⇒ thẻ REG-C-01" '[ "$(cards)" = 1 ] && grep -q ": REG-C-01 đỏ" "$T/cards.log"' \
  "rc=$rc cards=$(cards) $(tail -1 "$HIST" | cut -c1-500)"

# n6: hai đỏ mới cùng lượt ở c4, không history, mốc last_full_green_sha = base
g -C "$T/seed" push -q -f origin "$C4:refs/heads/at4"
rm -f "$HIST"; printf '%s\n' "$BASE" >"$COMMON/postfix-gate/last_full_green_sha"
rm -f "$T/cards.log"; python3 "$GF" run --repo "$T/repo" --ref origin/at4 --slug fake/repo --timeout 30 >"$T/out" 2>&1; rc=$?
chk "n6. hai đỏ mới: REG-A-01 ⇒ c2, REG-B-01 ⇒ c4, hai thẻ" \
  '[ "$(row "r[\"suspects\"][\"REG-A-01\"][\"sha\"]")" = "$C2" ] && [ "$(row "r[\"suspects\"][\"REG-B-01\"][\"sha\"]")" = "$C4" ] && [ "$(cards)" = 2 ]' \
  "rc=$rc cards=$(cards) $(tail -1 "$HIST" | cut -c1-600)"
# n7: mốc dạng cũ
printf '{"at": "x", "result": "red", "ref": "origin/main", "sha": "%s", "red": ["REG-A-01"], "group_b": [], "suspect": ""}\n' "$C6" >"$HIST"
rc=$(run_gf)
chk "n7. mốc dạng cũ: không thẻ, không chia đôi, ghi chú gieo mốc" \
  '[ "$(cards)" = 0 ] && [ "$(row "r[\"new_red\"]")" = "[]" ] && grep -q "dạng cũ" "$T/logs/summary-latest.md"' \
  "rc=$rc cards=$(cards) $(tail -1 "$HIST" | cut -c1-400)"
# chuẩn hoá: pid, đường tạm, số, sha không làm thành ca mới
chk "n8. norm_line: cùng ca khác pid / đường tạm / sha / số là một" \
  'BIN="$DEVKIT_DIR/bin" python3 -c "import os,sys; sys.path.insert(0, os.environ[\"BIN\"]); import gate_full as g; a=g.norm_line(\"  ✖ ca X pid 12 /tmp/a.Xy12Zq/f sha 0a1b2c3d4e lần 3\"); b=g.norm_line(\"✖ ca X pid 999 /tmp/q.AAbbCC/f sha ffeeddcc00 lần 7\"); sys.exit(0 if a == b and \"ca X\" in a else 1)"'
chk "n8b. norm_line: tên ca có số (t1. / t2., A2) không bị gộp" \
  'BIN="$DEVKIT_DIR/bin" python3 -c "import os,sys; sys.path.insert(0, os.environ[\"BIN\"]); import gate_full as g; sys.exit(0 if g.norm_line(\"✖ t1. x\") != g.norm_line(\"✖ t2. x\") and \"A2\" in g.norm_line(\"✖ ca A2: y\") else 1)"'

echo
[ "$fails" -eq 0 ] && { echo "PASS test_gate_full_heavy_new_red"; exit 0; }
echo "FAIL test_gate_full_heavy_new_red ($fails)"; exit 1
