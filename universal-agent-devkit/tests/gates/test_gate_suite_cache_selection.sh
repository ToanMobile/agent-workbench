#!/usr/bin/env bash
# Test hồi quy (#377 / #344): suite chọn test theo lịch sử git (run_impacted.sh — REG-DK-ALL-01 của workbench, trung vị 407 s, 224 lượt
# 23–24/10 dùng lại 0) được cache theo KHOÁ CẢ CÂY + tập test mà `run_impacted.sh --list` chọn. Cùng cây và cùng tập chọn ⇒ PASS cũ dùng lại;
# đổi một file (kể cả trong tập chọn) ⇒ chạy lại. Chỉ script của chính DevKit (có dấu `devkit-selection-list`) được hỏi `--list`: một script
# khác tên run_impacted.sh có thể chạy test ngay khi bị hỏi. Suite này KHÔNG vào phần cached-full thêm vào (mọi --full sẽ phải chạy nó lần
# đầu). Gate đỏ thì không ghi PASS của nó (script bỏ qua các test suite khác đã chạy trong lượt, DEVKIT_GATE_DONE: PASS đó mượn kết quả đỏ).
# Mỗi ca chạy ở worktree ĐÃ từng chạy gate (biên nhận anh em không cho mượn): chỉ cache theo khoá giải thích được một suite không chạy.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SENTINEL_MAX_S CI FLAKY_RETRY DEVKIT_GATE_PARALLEL \
  DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE DEVKIT_TEST_JOBS
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1 DEVKIT_SENTINEL_MAX_S=999999999
mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n() { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }

# repo <tên> [extra-rule]: bản sao nhỏ của một DevKit (run_impacted.sh THẬT, hai test, hai thư viện) và ma trận REG-ALL (+ rule thêm)
repo() {
  local r="$TMP/$1" kit; kit="$r/universal-agent-devkit"
  mkdir -p "$kit/tests/verification" "$kit/bin" "$r/other"
  git -C "$r" init -q -b main . && git -C "$r" config user.email t@t && git -C "$r" config user.name t
  cp "$DEVKIT_DIR/tests/run_impacted.sh" "$kit/tests/run_impacted.sh"; : > "$kit/tests/impact_map.txt"
  printf 'echo c >> %s/count.%s\n' "$TMP" "$1" > "$kit/tests/verification/test_repo_consistency.sh"
  printf '# names lib_a.py\necho a >> %s/count.%s\n' "$TMP" "$1" > "$kit/tests/verification/test_a.sh"
  echo 'a = 1' > "$kit/bin/lib_a.py"; echo 'b = 1' > "$kit/bin/lib_b.py"; echo 1 > "$r/other/o.txt"
  printf '{"project":"t","rules":[{"component":"K","watch_files":["universal-agent-devkit/bin/*.py"],"mandatory_regression_tests":[{"id":"REG-ALL","name":"all","command":"bash universal-agent-devkit/tests/run_impacted.sh"}]},{"component":"O","watch_files":["other/*"],"mandatory_regression_tests":[{"id":"REG-OTH","name":"oth","command":"echo o >> %s/count.%s.oth"}]}%s]}\n' \
    "$TMP" "$1" "${2:-}" > "$r/matrix.json"
  git -C "$r" add -A && git -C "$r" commit -qm init
}
# wt <repo> <worktree> <file> <nội dung> [rev]: worktree (ở rev, mặc định HEAD) đã từng chạy gate, một file đổi (chưa commit)
wt() {
  git -C "$TMP/$1" worktree add -q --detach "$TMP/$2" "${5:-HEAD}" || { echo "✖ setup: worktree $2"; exit 1; }
  mkdir -p "$TMP/$2/.claude/audit-gate"; : > "$TMP/$2/.claude/audit-gate/test_run.lock"
  echo "$4" > "$TMP/$2/$3"
}
gate() { local d="$1"; shift; ( cd "$d" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" \
  --run-tests --full --no-checklist "$@" >"$TMP/out" 2>&1 ); }
LIB=universal-agent-devkit/bin/lib_a.py

# S1. Hai lượt --full cùng cây, cùng tập chọn: lượt 2 dùng lại REG-ALL (không chạy lại test nào của nó).
repo s1
wt s1 s1a $LIB 'a = 2'; gate "$TMP/s1a"; r1=$?; c1=$(n s1)
wt s1 s1b $LIB 'a = 2'; gate "$TMP/s1b"; r2=$?; c2=$(n s1)
if [ "$r1 $r2" = "0 0" ] && [ "$c1" -ge 2 ] && [ "$c2" = "$c1" ]; then ok "S1. cùng cây + cùng tập chọn: lượt 2 dùng lại REG-ALL (test chạy $c1 → $c2)"
else fail "S1. exit $r1 $r2 (mong 0 0); test của REG-ALL chạy $c1 rồi $c2 (mong ≥2 rồi bằng nhau)"; grep -E "REG-ALL|suite_cache" "$TMP/out" | tail -3; fi

# S2. Đổi một file trong tập chọn (lib_a.py): khoá khác ⇒ chạy lại.
wt s1 s1c $LIB 'a = 3'; gate "$TMP/s1c"; r3=$?; c3=$(n s1)
if [ "$r3" = 0 ] && [ "$c3" -gt "$c2" ]; then ok "S2. đổi file trong tập chọn: REG-ALL chạy lại (test chạy $c2 → $c3)"
else fail "S2. exit $r3 (mong 0); test của REG-ALL chạy $c2 rồi $c3 (mong tăng)"; fi

# S3. Phần cached-full thêm vào không kéo REG-ALL: lượt --full không chọn nó (chỉ other/o.txt đổi) không bao giờ khởi động nó.
B=$(n s1)
wt s1 s1d other/o.txt 2; gate "$TMP/s1d"; r4=$?
if [ "$r4" = 0 ] && [ "$(n s1)" = "$B" ]; then ok "S3. --full không chọn REG-ALL không chạy nó (không vào cached-full thêm vào)"
else fail "S3. exit $r4 (mong 0); REG-ALL chạy thêm $(( $(n s1) - B )) test (mong 0)"; fi

# S4. Script run_impacted.sh KHÔNG phải của DevKit (không có dấu) không bị hỏi --list và không cache: hai lượt cùng cây đều chạy.
R4="$TMP/s4"; mkdir -p "$R4/tests" "$R4/src"
git -C "$R4" init -q -b main . && git -C "$R4" config user.email t@t && git -C "$R4" config user.name t
echo 'x = 1' > "$R4/src/x.py"
printf 'echo "$*" >> %s/count.s4\n' "$TMP" > "$R4/tests/run_impacted.sh"
printf '{"project":"t","rules":[{"component":"X","watch_files":["src/x.py"],"mandatory_regression_tests":[{"id":"REG-IMP","name":"imp","command":"bash tests/run_impacted.sh"}]}]}\n' > "$R4/matrix.json"
git -C "$R4" add -A && git -C "$R4" commit -qm init
wt s4 s4a src/x.py 'x = 2'; gate "$TMP/s4a"; wt s4 s4b src/x.py 'x = 2'; gate "$TMP/s4b"
if [ "$(n s4)" = 2 ] && ! grep -q -- '--list' "$TMP/count.s4"; then ok "S4. script không có dấu devkit-selection-list: không bị hỏi --list, không cache (2 lượt = 2 lần chạy)"
else fail "S4. count.s4 = $(n s4) dòng, nội dung: $(tr '\n' '|' < "$TMP/count.s4") (mong 2 dòng rỗng, không --list)"; fi

# S5 (cũng là review R5: khoá không chứa DEVKIT_GATE_DONE). Gate đỏ không ghi PASS của REG-ALL: lượt 1 REG-X FAIL (cờ ngoài cây) trong khi REG-ALL PASS; lượt 2 cùng cây, hết cờ: REG-ALL phải chạy lại.
repo s5 ',{"component":"X","watch_files":["universal-agent-devkit/bin/*.py"],"mandatory_regression_tests":[{"id":"REG-X","name":"x","command":"test ! -f '"$TMP"'/flag5"}]}'
: > "$TMP/flag5"
wt s5 s5a $LIB 'a = 2'; gate "$TMP/s5a"; r1=$?; c1=$(n s5)
rm -f "$TMP/flag5"
wt s5 s5b $LIB 'a = 2'; gate "$TMP/s5b"; r2=$?; c2=$(n s5)
if [ "$r1 $r2" = "1 0" ] && [ "$c2" -gt "$c1" ]; then ok "S5. gate đỏ không ghi PASS của REG-ALL: lượt sau chạy lại (test chạy $c1 → $c2)"
else fail "S5. exit $r1 $r2 (mong 1 0); test của REG-ALL chạy $c1 rồi $c2 (mong tăng)"; grep -E "REG-ALL|REG-X" "$TMP/out" | tail -3; fi

# S5m. Như S5 nhưng ở gate GỘP (DEVKIT_SLOT_PRIORITY=merge, đúng môi trường `worktree finish`): priority đổi thứ tự suite, REG-ALL có thể chạy xong TRƯỚC khi
#      REG-X đỏ. PASS của REG-ALL vẫn không được ghi (record_keyed chỉ ghi sau khi mọi suite đã có kết quả), lượt sau phải chạy lại.
repo s5m ',{"component":"X","watch_files":["universal-agent-devkit/bin/*.py"],"mandatory_regression_tests":[{"id":"REG-X","name":"x","command":"test ! -f '"$TMP"'/flag5m"}]}'
: > "$TMP/flag5m"
wt s5m s5ma $LIB 'a = 2'; DEVKIT_SLOT_PRIORITY=merge gate "$TMP/s5ma"; r1=$?; c1=$(n s5m)
rm -f "$TMP/flag5m"
wt s5m s5mb $LIB 'a = 2'; DEVKIT_SLOT_PRIORITY=merge gate "$TMP/s5mb"; r2=$?; c2=$(n s5m)
if [ "$r1 $r2" = "1 0" ] && [ "$c2" -gt "$c1" ]; then ok "S5m. gate gộp đỏ không ghi PASS của REG-ALL: lượt sau chạy lại (test chạy $c1 → $c2)"
else fail "S5m. exit $r1 $r2 (mong 1 0); test của REG-ALL chạy $c1 rồi $c2 (mong tăng)"; grep -E "REG-ALL|REG-X" "$TMP/out" | tail -3; fi

# S6. Cùng cây, khác tập chọn: tập chọn nằm trong khoá. Lượt 1 chọn {consistency} (đổi đã commit và main đã tiến tới commit đó: không còn gì "chưa
#     đẩy"), lượt 2 cùng nội dung nhưng chưa commit chọn {consistency, a}: một PASS của tập nhỏ không nói gì về tập lớn, lượt 2 phải chạy.
repo s6; old6=$(git -C "$TMP/s6" rev-parse HEAD)
wt s6 s6b $LIB 'a = 2' "$old6"; git -C "$TMP/s6b" commit -qam a2 && git -C "$TMP/s6" merge -q --ff-only "$(git -C "$TMP/s6b" rev-parse HEAD)"
gate "$TMP/s6b" --diff HEAD~1; r1=$?; c1=$(n s6)
wt s6 s6a $LIB 'a = 2' "$old6"; gate "$TMP/s6a"; r2=$?; c2=$(n s6)
if [ "$r1 $r2" = "0 0" ] && [ "$c2" -gt "$c1" ]; then ok "S6. cùng cây, tập chọn lớn hơn: không dùng lại PASS của tập nhỏ (test chạy $c1 → $c2)"
else fail "S6. exit $r1 $r2 (mong 0 0); test của REG-ALL chạy $c1 rồi $c2 (mong tăng)"; grep -E "REG-ALL|suite_cache" "$TMP/out" | tail -3; fi

# S7 (review R3). Tập chọn đọc LÚC TÍNH KHOÁ (`--list`), suite chạy SAU: cửa sổ `git log --since=6.hours` của run_impacted.sh trượt giữa hai lúc
#    đó (cây không đổi) thì suite đã chạy tập NHỎ hơn tập trong khoá — PASS ghi dưới khoá tập lớn là PASS giả. Ghi chỉ khi `--list` lúc ghi
#    vẫn bằng tập trong khoá. Repo thường (không worktree, không upstream ⇒ cửa sổ theo giờ), commit sửa lib_a.py mang ngày = mép cửa sổ + $2 giây;
#    test_a.sh ngủ $3 giây (> $2) nên lúc ghi commit đã ra khỏi cửa sổ. Ca đối chứng (commit mới, trong cửa sổ cả hai lúc) vẫn phải ghi.
# s7 <tên> <giây còn trong cửa sổ> <giây test ngủ>: chạy gate ở thư mục gốc repo, in số mục cache của REG-ALL
s7() {
  repo "$1"; local r="$TMP/$1" d; d=$(( $(date +%s) - 21600 + $2 ))
  printf '# names lib_a.py\nsleep %s\necho a >> %s/count.%s\n' "$3" "$TMP" "$1" > "$r/universal-agent-devkit/tests/verification/test_a.sh"
  echo 'a = 2' > "$r/$LIB"
  GIT_AUTHOR_DATE="$d +0000" GIT_COMMITTER_DATE="$d +0000" git -C "$r" commit -qam a2
  gate "$r" --diff HEAD~1; rc=$?
  n7=$(grep -l '"REG-ALL"' "$r"/.git/postfix-gate/suite_cache/*.json 2>/dev/null | wc -l | tr -d ' ')
}
s7 s7a 14 20
if [ "$rc" = 0 ] && [ "$n7" = 0 ]; then ok "S7. cửa sổ chọn trượt giữa khoá và lần chạy: PASS không ghi dưới khoá tập lớn hơn"
else fail "S7. exit $rc (mong 0); số mục cache của REG-ALL: $n7 (mong 0)"; grep -E "REG-ALL|suite_cache" "$TMP/out" | tail -3; fi
s7 s7b 3600 1
if [ "$rc" = 0 ] && [ "$n7" -ge 1 ]; then ok "S7b. đối chứng: tập chọn không đổi trong lúc chạy ⇒ PASS vẫn được ghi ($n7 mục)"
else fail "S7b. exit $rc (mong 0); số mục cache của REG-ALL: $n7 (mong ≥ 1)"; grep -E "REG-ALL|suite_cache" "$TMP/out" | tail -3; fi

# S8 (review R6). run_impacted.sh đọc LỊCH SỬ git (merge-base, `git log`), khoá cả cây chỉ băm NỘI DUNG + tập `--list`. Hai worktree cùng nội dung,
#    KHÁC lịch sử (HEAD khác nhau: c1 đổi other/o.txt rồi c2 trả về), cùng tập chọn ⇒ dùng lại PASS (kết quả của run_impacted.sh chỉ phụ thuộc
#    tập chọn + nội dung; S6 đã ghim chiều ngược lại: khác tập chọn ⇒ chạy lại).
repo s8; old8=$(git -C "$TMP/s8" rev-parse HEAD)
wt s8 s8a $LIB 'a = 2' "$old8"; gate "$TMP/s8a"; r1=$?; c1=$(n s8)
echo 2 > "$TMP/s8/other/o.txt"; git -C "$TMP/s8" commit -qam c1; echo 1 > "$TMP/s8/other/o.txt"; git -C "$TMP/s8" commit -qam c2
wt s8 s8b $LIB 'a = 2'; h8a=$(git -C "$TMP/s8a" rev-parse HEAD); h8b=$(git -C "$TMP/s8b" rev-parse HEAD)
gate "$TMP/s8b"; r2=$?; c2=$(n s8)
if [ "$r1 $r2" = "0 0" ] && [ "$h8a" != "$h8b" ] && [ "$c1" -ge 2 ] && [ "$c2" = "$c1" ]; then ok "S8. cùng nội dung, khác lịch sử, cùng tập chọn: dùng lại REG-ALL (test chạy $c1 → $c2)"
else fail "S8. exit $r1 $r2 (mong 0 0); HEAD $h8a / $h8b (mong khác nhau); test của REG-ALL chạy $c1 rồi $c2 (mong ≥2 rồi bằng nhau)"; grep -E "REG-ALL|suite_cache" "$TMP/out" | tail -3; fi

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_suite_cache_selection: all passed" || { echo "❌ test_gate_suite_cache_selection: $FAILS failed"; exit 1; }
