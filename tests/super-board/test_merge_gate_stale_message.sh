#!/usr/bin/env bash
# 18/10: merge gate in "the branch is stale against main — send it back to Build for a rebase pass" cho MỌI verify đỏ, kể cả khi nhánh
# chậm hơn main 0 commit. 17/10 câu này làm ba phiên repo đi rebase vô ích (lý do thật: post-fix-gate exit 2). Luật: chỉ nói "stale"
# khi `git rev-list --count <head>..origin/<base>` > 0; nếu không, in dòng KẾT LUẬN cuối của log verify và mã thoát của lệnh verify.
# 18/10 (sau PR #70): hai ca còn chung exit 2 nên lane vẫn đẩy nhánh đã cập nhật đi rebase. Luật: chậm hơn base → exit 2 (rebase pass);
# không chậm hơn base → exit 11 (về Build sửa verify đỏ, không rebase).
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-behindmsg-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/deploy-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm card
git -C "$R" push -q origin issue-5-x
H=$(git -C "$R" rev-parse issue-5-x)
git -C "$R" diff origin/main issue-5-x > "$TMP/pr5.diff"
printf '{"files":[{"path":"b"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr5.meta"
echo "$H" > "$TMP/pr5.head"

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
  *" pr merge "*) echo "fake gh: must not merge on a red verify" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
# Verify đỏ kiểu post-fix-gate: hai dòng KẾT LUẬN (dòng cuối là lý do thật), thoát 3.
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo \"KẾT LUẬN: cũ\"; echo \"KẾT LUẬN: FAIL — không có test hồi quy nào khớp\"; exit 3"]}' > "$CFG"

# Chỉ dòng kết luận của gate: bỏ dòng "verify: <lệnh>" / "FAILED: <lệnh>" vì chúng lặp lại chính văn bản lệnh (không chứng minh gì).
verdict() { grep "merge-gate" "$1" | grep -v "\] verify: " | grep -v "\] FAILED: "; }

# Ca 1: nhánh không chậm hơn main (0 commit) → không được nói stale; phải nêu KẾT LUẬN cuối và mã thoát.
( cd "$WT" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/gate1.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && ok "up-to-date branch, red verify: exit 11 (not the rebase-pass exit 2)" || fail "gate exit $rc (want 11): $(tail -5 "$TMP/gate1.log")"
grep -qi "stale" "$TMP/gate1.log" \
  && fail "up-to-date branch is called stale: $(grep -i stale "$TMP/gate1.log")" || ok "up-to-date branch: no 'stale' message"
verdict "$TMP/gate1.log" | grep -q "KẾT LUẬN: FAIL — không có test hồi quy nào khớp" \
  && ok "the gate's own message names the last KẾT LUẬN line" || fail "no KẾT LUẬN in the gate message: $(verdict "$TMP/gate1.log" | tail -3)"
verdict "$TMP/gate1.log" | grep -q "exit 3" \
  && ok "the gate's own message names the verify exit code" || fail "no 'exit 3' in the gate message: $(verdict "$TMP/gate1.log" | tail -3)"

# Ca 1b: post-fix-gate in KẾT LUẬN có mã màu ANSI → gate trích dòng đã bỏ màu (không còn byte ESC).
CFG_C="$TMP/cfg-color.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["printf \"  \\033[1mKẾT LUẬN:\\033[0m \\033[91mREJECT màu\\033[0m\\n\"; exit 2"]}' > "$CFG_C"
( cd "$WT" && bash "$GATE" --config "$CFG_C" --pr 5 --expect-head "$H" ) >"$TMP/gate1b.log" 2>&1; rc=$?
ESC=$(printf '\033')
V1B=$(verdict "$TMP/gate1b.log" | grep "verify failed (exit 2")
[ "$rc" -eq 11 ] && ok "coloured verdict, up-to-date branch: exit 11" || fail "coloured verdict: gate exit $rc (want 11)"
case "$V1B" in
  *"$ESC"*) fail "ANSI codes left in the gate message: $V1B" ;;
  *"KẾT LUẬN: REJECT màu"*) ok "coloured KẾT LUẬN line is quoted without ANSI codes" ;;
  *) fail "coloured verdict not quoted (rc $rc): $(verdict "$TMP/gate1b.log" | tail -3)" ;;
esac

# Ca 1c: log không có dòng KẾT LUẬN/VERDICT → vẫn không nói stale, nói rõ là không có dòng kết luận.
CFG_N="$TMP/cfg-noverdict.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo boom; exit 1"]}' > "$CFG_N"
( cd "$WT" && bash "$GATE" --config "$CFG_N" --pr 5 --expect-head "$H" ) >"$TMP/gate1c.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && ! grep -qi "stale" "$TMP/gate1c.log" && verdict "$TMP/gate1c.log" | grep -q "verify failed (exit 1: no KẾT LUẬN/VERDICT line" \
  && ok "no verdict line: says so with the exit code, not stale" || fail "no-verdict case (rc $rc): $(verdict "$TMP/gate1c.log" | tail -3)"

# Ca 2: main tiến thêm 1 commit (không xung đột, merge scratch sạch) + verify đỏ → exit 11 (không còn exit 2 / câu rebase ping-pong).
git -C "$R" checkout -q main; echo c > "$R/c"; git -C "$R" add c; git -C "$R" commit -qm main-moves; git -C "$R" push -q origin main
( cd "$WT" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/gate2.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && ! grep -qi "send it back to Build for a rebase pass" "$TMP/gate2.log" \
  && verdict "$TMP/gate2.log" | grep -q "exit 3: KẾT LUẬN: FAIL — không có test hồi quy nào khớp" \
  && ok "behind-base branch, clean merge in scratch + red verify: exit 11 (no rebase pass bounce), with verify reason" \
  || fail "behind branch clean merge (rc $rc): $(grep merge-gate "$TMP/gate2.log" | tail -3)"

# Ca 3: merge trong SCRATCH là fast-forward lên đỉnh base là một merge commit (merge sạch) + verify đỏ → exit 11, không còn câu rebase.
git -C "$R" branch -q --no-track issue-6-x main
git -C "$R" checkout -q issue-6-x; echo d > "$R/d"; git -C "$R" add d; git -C "$R" commit -qm card6; git -C "$R" push -q origin issue-6-x
H6=$(git -C "$R" rev-parse issue-6-x)
git -C "$R" checkout -q main; echo e > "$R/e"; git -C "$R" add e; git -C "$R" commit -qm main-e
git -C "$R" merge -q --no-ff --no-edit issue-6-x; git -C "$R" push -q origin main
git -C "$R" diff "$H6~1" "$H6" > "$TMP/pr6.diff"
printf '{"files":[{"path":"d"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr6.meta"
echo "$H6" > "$TMP/pr6.head"
( cd "$WT" && bash "$GATE" --config "$CFG" --pr 6 --expect-head "$H6" ) >"$TMP/gate3.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && ! grep -qi "send it back to Build for a rebase pass" "$TMP/gate3.log" \
  && verdict "$TMP/gate3.log" | grep -q "exit 3: KẾT LUẬN: FAIL — không có test hồi quy nào khớp" \
  && ok "fast-forward onto a merge-commit base tip + red verify: exit 11 (no rebase pass bounce)" \
  || fail "ff onto merge tip (rc $rc): $(grep merge-gate "$TMP/gate3.log" | tail -3)"

# Ca 4: xung đột thật khi merge BASE_SHA vào scratch → giữ nguyên exit 5.
git -C "$R" checkout -q main
git -C "$R" branch -q --no-track issue-7-x main
git -C "$R" checkout -q issue-7-x; echo "branch-side" > "$R/a"; git -C "$R" add a; git -C "$R" commit -qm card7; git -C "$R" push -q origin issue-7-x
H7=$(git -C "$R" rev-parse issue-7-x)
git -C "$R" checkout -q main; echo "main-side" > "$R/a"; git -C "$R" add a; git -C "$R" commit -qm main-conflict; git -C "$R" push -q origin main
git -C "$R" diff "$H7~1" "$H7" > "$TMP/pr7.diff"
printf '{"files":[{"path":"a"}],"labels":[],"body":"","additions":1,"deletions":1,"changedFiles":1}' > "$TMP/pr7.meta"
echo "$H7" > "$TMP/pr7.head"
( cd "$WT" && bash "$GATE" --config "$CFG" --pr 7 --expect-head "$H7" ) >"$TMP/gate4.log" 2>&1; rc=$?
[ "$rc" -eq 5 ] && grep -q "does not merge in cleanly" "$TMP/gate4.log" \
  && ok "real merge conflict in scratch: exit 5" \
  || fail "real merge conflict (rc $rc, want 5): $(grep merge-gate "$TMP/gate4.log" | tail -3)"

# Ca 5: timeout (lần 1 exit 124 / TIMEOUT, lần 2 exit 0) → chạy lại đúng 1 lần và đi tiếp, đồng thời kiểm tra scratch nằm dưới main .claude/worktrees.
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
COUNT_FILE="$TMP/timeout_runs"
SCRATCH_PWD_FILE="$TMP/scratch_pwd"
rm -f "$COUNT_FILE" "$SCRATCH_PWD_FILE"
CFG_T="$TMP/cfg-timeout.json"
cat > "$CFG_T" <<JSON
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[
  "c=\$(cat '$COUNT_FILE' 2>/dev/null || echo 0); c=\$((c + 1)); echo \$c > '$COUNT_FILE'; pwd -P > '$SCRATCH_PWD_FILE'; if [ \$c -eq 1 ]; then echo 'TIMEOUT after 900s'; exit 124; fi; exit 0"
]}
JSON
( cd "$WT" && bash "$GATE" --config "$CFG_T" --pr 5 --expect-head "$H" ) >"$TMP/gate5.log" 2>&1; rc=$?
runs=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
spwd=$(cat "$SCRATCH_PWD_FILE" 2>/dev/null || echo "")
R_ABS=$(cd "$R" && pwd -P)
[ "$rc" -eq 0 ] && [ "$runs" -eq 2 ] \
  && ok "timeout (exit 124) retried once and passed on second attempt (runs=$runs, exit 0)" \
  || fail "timeout retry failed (rc=$rc, runs=$runs): $(tail -5 "$TMP/gate5.log")"
case "$spwd" in
  "$R_ABS/.claude/worktrees/.merge-scratch-"*) ok "scratch worktree created under main checkout .claude/worktrees ($spwd)" ;;
  *) fail "scratch worktree not under $R_ABS/.claude/worktrees: '$spwd'" ;;
esac

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_stale_message: PASS"; exit 0; } || { echo "test_merge_gate_stale_message: FAIL ($FAILS)"; exit 1; }
