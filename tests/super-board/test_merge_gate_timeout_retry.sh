#!/usr/bin/env bash
# Issue #142 (18/10): verify `post-fix-gate.py --force-full` đỏ CHỈ vì một suite hồi quy quá giới hạn thời gian (REG-DK-ALL-01 900 s
# TIMEOUT khi máy tải cao; PR 12/12 AC bị đánh trượt) không được merge gate chạy lại, vì is_verify_timeout() trả "không phải timeout"
# ngay khi log có dòng KẾT LUẬN — mà post-fix-gate luôn in dòng đó. Luật:
#   - gate REJECT (exit 1), lớp tĩnh "đạt", mọi dòng suite đỏ `[ ] <TRẠNG THÁI> |` đều là TIMEOUT → chạy lại đúng 1 lần; lần 2 quyết định.
#   - có ít nhất một suite FAIL thật (kể cả kèm TIMEOUT), hoặc lớp tĩnh có phát hiện → không chạy lại, exit 11.
#   - exit 124 của chính lệnh verify vẫn được chạy lại 1 lần.
# Log giả theo đúng định dạng post-fix-gate.py (mã màu ANSI, dòng `[ ] TIMEOUT | ID : tên`, dòng đuôi output `           | …`).
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-timeout-retry-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Slot nặng riêng của test: slot toàn máy có thể đang bị merge gate thật giữ (chờ tới 3600 s).
export SB_HEAVY_SLOT_DIR="$TMP/slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/review-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x

# Mỗi ca một PR riêng (nhánh issue-N-x từ main, một file mới) để các ca tách rời nhau.
mkpr() {
  local n="$1" h
  git -C "$R" branch -q --no-track "issue-$n-x" main
  git -C "$WT" checkout -q "issue-$n-x"
  echo "$n" > "$WT/f$n"; git -C "$WT" add "f$n"; git -C "$WT" commit -qm "card$n"
  git -C "$R" push -q origin "issue-$n-x"
  h=$(git -C "$R" rev-parse "issue-$n-x")
  git -C "$R" diff "$h~1" "$h" > "$TMP/pr$n.diff"
  printf '{"files":[{"path":"f%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$n" > "$TMP/pr$n.meta"
  echo "$h" > "$TMP/pr$n.head"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0

# ---- log giả theo định dạng post-fix-gate.py (--brief giữ dòng `[ ] <không PASS>` và mọi dòng từ KẾT LUẬN trở đi) ----
E=$(printf '\033')
row() { printf '    %s[91m[ ] %s%s[0m | %s[1m%-15s%s[0m : %s\n' "$E" "$1" "$E" "$E" "$2" "$E" "$3"; }
tail_line() { printf '           %s[2m| %s%s[0m\n' "$E" "$1" "$E"; }
reject() {   # $1 = dòng lớp tĩnh: đạt | CÓ PHÁT HIỆN
  printf '  %s[1mKẾT LUẬN CỔNG POST-FIX AUDIT:%s[0m %s[91m%s[1mREJECT — CẦN KHẮC PHỤC CÁC ĐIỂM CHƯA ĐẠT%s[0m\n' "$E" "$E" "$E" "$E" "$E"
  printf '  • Test hồi quy đạt: 11/12\n'
  printf '  • Lớp tĩnh (bí mật, lười biếng, dependency, hiệu năng, nuốt lỗi, log): %s\n' "$1"
}
green_log() {
  printf '  %s[1mKẾT LUẬN CỔNG POST-FIX AUDIT:%s[0m %s[92m%s[1mPASS — ĐỦ ĐIỀU KIỆN NGHIỆM THU & BÀN GIAO%s[0m\n' "$E" "$E" "$E" "$E" "$E"
  printf '  • Test hồi quy đạt: 12/12\n'
  printf '  • Lớp tĩnh (bí mật, lười biếng, dependency, hiệu năng, nuốt lỗi, log): đạt\n'
}
# Đỏ chỉ vì TIMEOUT; dòng đuôi output của chính suite có chữ "[ ] FAIL" (REG-DK-ALL-01 chạy test của post-fix-gate) — không phải dòng suite.
{ row TIMEOUT REG-DK-ALL-01 "DevKit full suite"
  printf '           %s[2mLệnh chạy: bash universal-agent-devkit/tests/run_all.sh (900.01s)%s[0m\n' "$E" "$E"
  tail_line "    [ ] FAIL | REG-FAKE-01 : decoy row inside a test fixture"
  tail_line "✖ tests/verification/test_slow.sh"
  reject "đạt"; } > "$TMP/red-timeout.log"
{ row TIMEOUT REG-DK-ALL-01 "DevKit full suite"; row FAIL REG-SB-01 "super-board suite"
  tail_line "AssertionError: expected 11"; reject "đạt"; } > "$TMP/red-mixed.log"
{ row TIMEOUT REG-DK-ALL-01 "DevKit full suite"; reject "CÓ PHÁT HIỆN"; } > "$TMP/red-static.log"
{ row TIMEOUT REG-DK-ALL-01 "DevKit full suite"; row UNTESTED REG-AND-01 "android suite"; reject "đạt"; } > "$TMP/red-untested.log"
green_log > "$TMP/green.log"

# Lệnh verify giả: lần gọi thứ k in file thứ k trong danh sách và thoát với mã tương ứng; đếm số lần gọi.
# $1 = số PR, $2.. = cặp "<file log> <exit>" theo lượt gọi.
run_case() {
  local n="$1"; shift
  local cnt="$TMP/runs$n" cfg="$TMP/cfg$n.json" script="$TMP/verify$n.sh" k=1
  rm -f "$cnt"
  { echo '#!/usr/bin/env bash'
    echo "c=\$(cat '$cnt' 2>/dev/null || echo 0); c=\$((c + 1)); echo \$c > '$cnt'"
    while [ "$#" -ge 2 ]; do
      # File .sh = lượt gọi chạy script đó (nó tự in log) thay cho cat một log cố định.
      case "$1" in
        *.sh) echo "if [ \$c -eq $k ]; then bash '$1' || exit \$?; exit $2; fi" ;;
        *)    echo "if [ \$c -eq $k ]; then cat '$1'; exit $2; fi" ;;
      esac
      k=$((k + 1)); shift 2
    done
    echo "echo 'unexpected extra verify call'; exit 99"; } > "$script"
  printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["bash %s"]}' "$script" > "$cfg"
  ( cd "$WT" && bash "$GATE" --config "$cfg" --pr "$n" --expect-head "$(cat "$TMP/pr$n.head")" ) >"$TMP/gate$n.log" 2>&1
  CASE_RC=$?
  CASE_RUNS=$(cat "$cnt" 2>/dev/null || echo 0)
}
why() { grep "merge-gate" "$TMP/gate$1.log" | tail -4; }

# Ca 1: chỉ TIMEOUT (lần 1 đỏ), lần 2 xanh → chạy lại đúng 1 lần, merge (exit 0).
mkpr 11
run_case 11 "$TMP/red-timeout.log" 1 "$TMP/green.log" 0
[ "$CASE_RC" -eq 0 ] && [ "$CASE_RUNS" -eq 2 ] && grep -q "retrying once" "$TMP/gate11.log" \
  && ok "timeout-only red verify: retried once, green on retry, merged (exit 0, runs=2)" \
  || fail "timeout-only red verify (rc=$CASE_RC runs=$CASE_RUNS, want 0 and 2): $(why 11)"

# Ca 2: chỉ TIMEOUT cả hai lần → đúng 1 lần chạy lại, lần 2 quyết định: exit 11, không lần thứ 3.
mkpr 12
run_case 12 "$TMP/red-timeout.log" 1 "$TMP/red-timeout.log" 1
[ "$CASE_RC" -eq 11 ] && [ "$CASE_RUNS" -eq 2 ] \
  && ok "timeout-only red twice: one retry only, second result stands (exit 11, runs=2)" \
  || fail "timeout-only red twice (rc=$CASE_RC runs=$CASE_RUNS, want 11 and 2): $(why 12)"

# Ca 3: FAIL thật kèm TIMEOUT → không chạy lại, exit 11.
mkpr 13
run_case 13 "$TMP/red-mixed.log" 1 "$TMP/green.log" 0
[ "$CASE_RC" -eq 11 ] && [ "$CASE_RUNS" -eq 1 ] \
  && ok "real FAIL mixed with TIMEOUT: not retried (exit 11, runs=1)" \
  || fail "mixed FAIL+TIMEOUT (rc=$CASE_RC runs=$CASE_RUNS, want 11 and 1): $(why 13)"

# Ca 4: lớp tĩnh có phát hiện + suite TIMEOUT → exit 1 không chỉ vì timeout: không chạy lại.
mkpr 14
run_case 14 "$TMP/red-static.log" 1 "$TMP/green.log" 0
[ "$CASE_RC" -eq 11 ] && [ "$CASE_RUNS" -eq 1 ] \
  && ok "static findings + TIMEOUT: not retried (exit 11, runs=1)" \
  || fail "static findings + TIMEOUT (rc=$CASE_RC runs=$CASE_RUNS, want 11 and 1): $(why 14)"

# Ca 5: suite UNTESTED kèm TIMEOUT → không phân loại được là "chỉ timeout": không chạy lại.
mkpr 15
run_case 15 "$TMP/red-untested.log" 1 "$TMP/green.log" 0
[ "$CASE_RC" -eq 11 ] && [ "$CASE_RUNS" -eq 1 ] \
  && ok "UNTESTED + TIMEOUT: not retried (exit 11, runs=1)" \
  || fail "UNTESTED + TIMEOUT (rc=$CASE_RC runs=$CASE_RUNS, want 11 and 1): $(why 15)"

# Ca 6: log chỉ TIMEOUT nhưng gate thoát khác 1 (exit 2 = CHƯA XÁC MINH, không phải REJECT) → không chạy lại.
mkpr 16
run_case 16 "$TMP/red-timeout.log" 2 "$TMP/green.log" 0
[ "$CASE_RC" -eq 11 ] && [ "$CASE_RUNS" -eq 1 ] \
  && ok "timeout rows but exit 2 (not REJECT): not retried (exit 11, runs=1)" \
  || fail "timeout rows with exit 2 (rc=$CASE_RC runs=$CASE_RUNS, want 11 and 1): $(why 16)"

# Ca 7: chính lệnh verify thoát 124, không có dòng kết luận → vẫn chạy lại 1 lần.
printf 'killed by the wall clock\n' > "$TMP/plain124.log"
mkpr 17
run_case 17 "$TMP/plain124.log" 124 "$TMP/green.log" 0
[ "$CASE_RC" -eq 0 ] && [ "$CASE_RUNS" -eq 2 ] \
  && ok "verify command exit 124: retried once, green on retry (exit 0, runs=2)" \
  || fail "plain exit 124 (rc=$CASE_RC runs=$CASE_RUNS, want 0 and 2): $(why 17)"

# ---- review 20/10 (OCR + principal-code-reviewer) ----
reject_en() {
  printf '  %s[1mPOST-FIX AUDIT GATE VERDICT:%s[0m %s[91m%s[1mREJECT — FIX THE FAILED CHECKS%s[0m\n' "$E" "$E" "$E" "$E" "$E"
  printf '  • Regression tests passed: 11/12\n'
  printf '  • Static checks (secrets, laziness, dependencies, performance, swallowed errors, logging): passed\n'
}
{ row TIMEOUT REG-DK-ALL-01 "DevKit full suite"; reject_en; } > "$TMP/red-timeout-en.log"
{ row TIMEOUT REG-DK-ALL-01 "DevKit full suite"
  printf '  KẾT LUẬN CỔNG POST-FIX AUDIT: REJECT — CẦN KHẮC PHỤC CÁC ĐIỂM CHƯA ĐẠT\n'; } > "$TMP/red-nostatic.log"
{ row TIMEOUT REG-DK-ALL-01 "DevKit full suite"; row "NOT RUN" REG-SB-01 "super-board suite"; reject "đạt"; } > "$TMP/red-notrun.log"
{ row TIMEOUT REG-DK-ALL-01 "DevKit full suite"
  printf '  KẾT LUẬN CỔNG POST-FIX AUDIT: CHƯA XÁC MINH — thư mục project đã bị gỡ trong lúc gate chạy (worktree finish/remove)\n'
  printf '  • Lớp tĩnh (bí mật, lười biếng, dependency, hiệu năng, nuốt lỗi, log): đạt\n'; } > "$TMP/red-gone.log"
{ row TIMEOUT REG-DK-ALL-01 "DevKit full suite"; row FAIL_INFRA REG-SB-01 "super-board suite"; reject "đạt"; } > "$TMP/red-odd.log"
{ row TIMEOUT REG-DK-ALL-01 "DevKit full suite"; reject "đạt"; } > "$TMP/red-timeout-124.log"

# Ca 8: log tiếng Anh (DEVKIT_LANG=en), chỉ TIMEOUT → chạy lại 1 lần, xanh → merge.
mkpr 18
run_case 18 "$TMP/red-timeout-en.log" 1 "$TMP/green.log" 0
[ "$CASE_RC" -eq 0 ] && [ "$CASE_RUNS" -eq 2 ] \
  && ok "English timeout-only red: retried once (exit 0, runs=2)" \
  || fail "English timeout-only red (rc=$CASE_RC runs=$CASE_RUNS, want 0 and 2): $(why 18)"

# Ca 9: có dòng kết luận nhưng thiếu dòng lớp tĩnh → không phân loại được → không chạy lại.
mkpr 19
run_case 19 "$TMP/red-nostatic.log" 1 "$TMP/green.log" 0
[ "$CASE_RC" -eq 11 ] && [ "$CASE_RUNS" -eq 1 ] \
  && ok "verdict without a static-checks line: not retried (exit 11, runs=1)" \
  || fail "verdict without static line (rc=$CASE_RC runs=$CASE_RUNS, want 11 and 1): $(why 19)"

# Ca 10: NOT RUN kèm TIMEOUT → không chạy lại.
mkpr 20
run_case 20 "$TMP/red-notrun.log" 1 "$TMP/green.log" 0
[ "$CASE_RC" -eq 11 ] && [ "$CASE_RUNS" -eq 1 ] \
  && ok "NOT RUN + TIMEOUT: not retried (exit 11, runs=1)" \
  || fail "NOT RUN + TIMEOUT (rc=$CASE_RC runs=$CASE_RUNS, want 11 and 1): $(why 20)"

# Ca 11: exit 124 dù log đã có dòng kết luận → vẫn chạy lại 1 lần (124 kiểm trước kết luận).
mkpr 21
run_case 21 "$TMP/red-timeout-124.log" 124 "$TMP/green.log" 0
[ "$CASE_RC" -eq 0 ] && [ "$CASE_RUNS" -eq 2 ] \
  && ok "exit 124 with a verdict line: retried once (exit 0, runs=2)" \
  || fail "exit 124 with verdict (rc=$CASE_RC runs=$CASE_RUNS, want 0 and 2): $(why 21)"

# Ca 12: exit 1 nhưng kết luận là CHƯA XÁC MINH (project_gone), không phải REJECT → không chạy lại.
mkpr 22
run_case 22 "$TMP/red-gone.log" 1 "$TMP/green.log" 0
[ "$CASE_RC" -eq 11 ] && [ "$CASE_RUNS" -eq 1 ] \
  && ok "exit 1 with a non-REJECT verdict: not retried (exit 11, runs=1)" \
  || fail "exit 1 non-REJECT verdict (rc=$CASE_RC runs=$CASE_RUNS, want 11 and 1): $(why 22)"

# Ca 13: dòng suite đỏ có trạng thái lạ (FAIL_INFRA) kèm TIMEOUT → đếm là đỏ khác (fail-closed), không chạy lại.
mkpr 23
run_case 23 "$TMP/red-odd.log" 1 "$TMP/green.log" 0
[ "$CASE_RC" -eq 11 ] && [ "$CASE_RUNS" -eq 1 ] \
  && ok "unknown red status shape + TIMEOUT: not retried (exit 11, runs=1)" \
  || fail "unknown red status + TIMEOUT (rc=$CASE_RC runs=$CASE_RUNS, want 11 and 1): $(why 23)"


# Ca 14: trước lần chạy lại mốc `at` của merge lock phải được làm mới, để gate khác không coi khoá của verify + retry dài là bỏ
# quên (STALE_AFTER) và chiếm khoá giữa lúc retry. Lần 1 ghi mốc 0 (không phụ thuộc đồng hồ); lần 2 phải thấy mốc khác 0.
LOCK_AT="$WT/.claude/super-board/inflight/merge.lock/at"
LOCK_PID="$WT/.claude/super-board/inflight/merge.lock/pid"
cat > "$TMP/zero-stamp-red.sh" <<SH
echo 0 > '$LOCK_AT'; cat '$TMP/red-timeout.log'
SH
cat > "$TMP/stamp-green.sh" <<SH
cat '$LOCK_AT' > '$TMP/stamp-seen'; cat '$TMP/green.log'
SH
mkpr 24
run_case 24 "$TMP/zero-stamp-red.sh" 1 "$TMP/stamp-green.sh" 0
SEEN=$(cat "$TMP/stamp-seen" 2>/dev/null || echo none)
[ "$CASE_RC" -eq 0 ] && [ "$CASE_RUNS" -eq 2 ] && [ "$SEEN" != 0 ] && [ "$SEEN" != none ] \
  && ok "merge lock stamp refreshed before the retry (stamp ${SEEN})" \
  || fail "merge lock stamp not refreshed before the retry (stamp ${SEEN}, rc=$CASE_RC runs=$CASE_RUNS): $(why 24)"

# Ca 15: lần 1 bị giết giữa chừng để lại file đã track bị sửa VÀ đã `git add` trong scratch; lần chạy lại phải thấy cây và index
# đúng commit đã merge (`checkout -- .` chép index ra cây nên không gỡ được phần đã add).
cat > "$TMP/dirty-red.sh" <<SH
echo dirty > a; git add a; cat '$TMP/red-timeout.log'
SH
cat > "$TMP/clean-green.sh" <<SH
if git diff --quiet HEAD; then cat '$TMP/green.log'; else echo "scratch still dirty"; exit 7; fi
SH
mkpr 25
run_case 25 "$TMP/dirty-red.sh" 1 "$TMP/clean-green.sh" 0
[ "$CASE_RC" -eq 0 ] && [ "$CASE_RUNS" -eq 2 ] \
  && ok "scratch tree and index reset to the merged commit before the retry (exit 0, runs=2)" \
  || fail "scratch tree not reset before the retry (rc=$CASE_RC runs=$CASE_RUNS, want 0 and 2): $(why 25)"

# Ca 16: lần 1 sửa file đã track rồi để lại index.lock → không trả scratch về commit đã merge được → giữ kết quả đỏ, không chạy
# lại trên một cây không còn là MERGED_SHA (fail-closed).
cat > "$TMP/locked-red.sh" <<SH
echo dirty > a; touch "\$(git rev-parse --git-dir)/index.lock"; cat '$TMP/red-timeout.log'
SH
mkpr 26
run_case 26 "$TMP/locked-red.sh" 1 "$TMP/green.log" 0
[ "$CASE_RC" -eq 11 ] && [ "$CASE_RUNS" -eq 1 ] \
  && ok "scratch reset failed: first red result kept, no retry (exit 11, runs=1)" \
  || fail "scratch reset failed (rc=$CASE_RC runs=$CASE_RUNS, want 11 and 1): $(why 26)"

# Ca 17-19: trong lúc verify, gate khác coi khoá là bỏ quên và chiếm nó (ghi pid của nó). Gate này không được chạy lại, không
# merge (exit 4: chưa giữ được khoá, thẻ ở yên) và — ở mọi đường thoát — không xoá khoá đang sống của gate kia.
stolen_case() {   # $1 = số PR, $2 = pid lạ, $3 = log lần 1, $4 = exit lần 1, $5 = exit muốn, $6 = mô tả
  cat > "$TMP/stolen$1.sh" <<SH
echo $2 > '$LOCK_PID'; cat '$3'
SH
  mkpr "$1"
  run_case "$1" "$TMP/stolen$1.sh" "$4" "$TMP/green.log" 0
  LEFT=$(cat "$LOCK_PID" 2>/dev/null || echo gone)
  [ "$CASE_RC" -eq "$5" ] && [ "$CASE_RUNS" -eq 1 ] && [ "$LEFT" = "$2" ] \
    && ok "lock taken over during $6: no retry, no merge, other gate's lock kept (exit $5, runs=1)" \
    || fail "lock taken over during $6 (rc=$CASE_RC runs=$CASE_RUNS lock pid=$LEFT, want $5, 1, $2): $(why "$1")"
  rm -rf "$WT/.claude/super-board/inflight/merge.lock"
}
stolen_case 27 999999 "$TMP/red-timeout.log" 1 4 "a timeout-only red verify"
stolen_case 28 999998 "$TMP/green.log" 0 4 "a green verify"
stolen_case 29 999997 "$TMP/red-mixed.log" 1 11 "a real FAIL verify"

# Ca 20: không làm mới được mốc khoá (thư mục khoá chỉ đọc — như khi gate khác vừa rm -rf khoá sau lúc kiểm pid) → coi như mất
# khoá: không chạy lại, không merge (exit 4).
LOCK_D="$WT/.claude/super-board/inflight/merge.lock"
if [ "$(id -u)" -eq 0 ]; then
  echo "- skip: lock stamp refresh failure (root writes into a chmod 555 directory)"
else
  cat > "$TMP/ro-lock-red.sh" <<SH
chmod 555 '$LOCK_D'; cat '$TMP/red-timeout.log'
SH
  mkpr 30
  run_case 30 "$TMP/ro-lock-red.sh" 1 "$TMP/green.log" 0
  chmod 755 "$LOCK_D" 2>/dev/null; rm -rf "$LOCK_D"
  [ "$CASE_RC" -eq 4 ] && [ "$CASE_RUNS" -eq 1 ] \
    && ok "lock stamp cannot be refreshed: treated as a lost lock, no retry, no merge (exit 4, runs=1)" \
    || fail "lock stamp refresh failure (rc=$CASE_RC runs=$CASE_RUNS, want 4 and 1): $(why 30)"
fi

echo
# Ca HANG: post-fix-gate in `[ ] TIMEOUT (HANG) |` cho suite quá giờ lúc máy rảnh (#370); vẫn là chỉ-TIMEOUT nên chạy lại 1 lần.
{ row "TIMEOUT (HANG)" REG-DK-ALL-01 "DevKit full suite"; reject "đạt"; } > "$TMP/red-hang.log"
mkpr 41
run_case 41 "$TMP/red-hang.log" 1 "$TMP/green.log" 0
[ "$CASE_RC" -eq 0 ] && [ "$CASE_RUNS" -eq 2 ] && grep -q "retrying once" "$TMP/gate41.log" \
  && ok "HANG-labelled timeout-only red: retried once (exit 0, runs=2)" \
  || fail "HANG-labelled timeout-only red (rc=$CASE_RC runs=$CASE_RUNS, want 0 and 2): $(why 41)"
# HANG kèm một suite FAIL thật: không chạy lại.
{ row "TIMEOUT (HANG)" REG-DK-ALL-01 "DevKit full suite"; row FAIL REG-SB-01 "super-board suite"; reject "đạt"; } > "$TMP/red-hang-mixed.log"
mkpr 42
run_case 42 "$TMP/red-hang-mixed.log" 1 "$TMP/green.log" 0
[ "$CASE_RC" -eq 11 ] && [ "$CASE_RUNS" -eq 1 ] \
  && ok "HANG + real FAIL: not retried (exit 11, runs=1)" \
  || fail "HANG + real FAIL (rc=$CASE_RC runs=$CASE_RUNS, want 11 and 1): $(why 42)"

[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_timeout_retry: PASS"; exit 0; } || { echo "test_merge_gate_timeout_retry: FAIL ($FAILS)"; exit 1; }
