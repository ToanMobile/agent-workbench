#!/usr/bin/env bash
# Test hồi quy cho .claude/bin/super-board-merge-train.sh (#110), chạy offline với `gh` giả và origin bare.
# Verify của config đếm số lần chạy vào $TMP/verify.count và đỏ khi cây scratch có file `bad`.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TRAIN="$ROOT/.claude/bin/super-board-merge-train.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-train-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main

# card_branch <N> <file>: nhánh issue-<N>-x thêm file <file>, đã đẩy lên origin; ghi diff + metadata cho gh giả.
card_branch() {
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$1-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$1-build" "issue-$1-x"
  echo "$1" > "$W/issue-$1-build/$2"
  git -C "$W/issue-$1-build" add "$2"; git -C "$W/issue-$1-build" commit -qm "card $1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  git -C "$R" diff "origin/main" "issue-$1-x" > "$TMP/pr$1.diff"
  printf '{"files":[{"path":"%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$2" > "$TMP/pr$1.meta"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
# gh giả: trạng thái PR từ $FAKE_DIR/pr<N>.*; `pr merge` mô phỏng squash: một commit một cha trên main của origin, cây = merge(main, head).
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) if [ -e "$FAKE_DIR/fail_head$n" ]; then echo "boom: HTTP 502" >&2; exit 1; fi; echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*)
    git -C "$FAKE_REPO" fetch -q origin main "issue-$n-x"
    tree=$(git -C "$FAKE_REPO" merge-tree --write-tree origin/main "$head") || exit 1
    c=$(git -C "$FAKE_REPO" commit-tree "$tree" -p origin/main -m "squash #$n")
    git -C "$FAKE_REPO" push -q origin "$c:refs/heads/main" && echo "$n" >> "$FAKE_DIR/merged" && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo x >> %s/verify.count; test ! -e bad"]}\n' "$TMP" > "$CFG"
runs() { if [ -f "$TMP/verify.count" ]; then wc -l < "$TMP/verify.count" | tr -d ' '; else echo 0; fi; }
reset_run() { rm -f "$TMP/verify.count" "$TMP/merged"; }
origin_has() { git -C "$O" cat-file -e "main:$1" 2>/dev/null; }
merged_list() { sort "$TMP/merged" 2>/dev/null | tr '\n' ' '; }

# ── 1. Ba PR sẵn sàng cùng lúc: đúng một lần verify, cả ba merge.
card_branch 1 f1; card_branch 2 f2; card_branch 3 f3
git -C "$R" worktree add -q --detach "$W/review" origin/main
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 1,2,3 ) >"$TMP/t1.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "3 PRs: train exit 0" || fail "3 PRs: exit $rc: $(tail -8 "$TMP/t1.log")"
[ "$(runs)" = 1 ] && ok "3 PRs: verify ran exactly once" || fail "3 PRs: verify ran $(runs) times"
[ "$(merged_list)" = "1 2 3 " ] && ok "3 PRs: all merged" || fail "3 PRs: merged $(merged_list)"
if origin_has f1 && origin_has f2 && origin_has f3; then ok "3 PRs: origin/main holds all three files"; else fail "3 PRs: files missing on origin/main"; fi

# ── 2. Một PR làm đỏ (#5 thêm file `bad`): chia đôi tìm đúng nó, hai PR còn lại vẫn merge.
card_branch 4 g4; card_branch 5 bad; card_branch 6 g6
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 4,5,6 ) >"$TMP/t2.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && ok "1 red PR: train exit 11 (back to Build)" || fail "1 red PR: exit $rc: $(tail -8 "$TMP/t2.log")"
[ "$(merged_list)" = "4 6 " ] && ok "1 red PR: the two good PRs merged, #5 did not" || fail "1 red PR: merged $(merged_list)"
grep -q "train-red: 5" "$TMP/t2.log" && ok "1 red PR: culprit named (#5)" || fail "1 red PR: culprit not named: $(grep train "$TMP/t2.log")"
if origin_has bad; then fail "1 red PR: bad file reached origin/main"; else ok "1 red PR: red change never reached origin/main"; fi

# ── 3. Một PR: chạy như hiện tại (gate thường, một lần verify của chính nó).
card_branch 7 h7
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 7 ) >"$TMP/t3.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(merged_list)" = "7 " ] && ok "1 PR: merged through the plain gate" || fail "1 PR: exit $rc merged=$(merged_list)"
[ "$(runs)" = 1 ] && ok "1 PR: gate verified once" || fail "1 PR: verify ran $(runs) times"
if grep -qE "\[merge-train\]|train-result" "$TMP/t3.log"; then fail "1 PR: train path taken"; else ok "1 PR: no train output"; fi

# ── 4. Biên nhận sai cây (QA #110): gate phải verify như thường, biên nhận không bao giờ nới tiêu chuẩn.
card_branch 8 k8
printf '%s %s\n' "$(cat "$TMP/pr8.head")" "0000000000000000000000000000000000000000" > "$TMP/bad.receipt"
reset_run
( cd "$W/review" && bash "$ROOT/.claude/bin/super-board-merge-gate.sh" --config "$CFG" --pr 8 --expect-head "$(cat "$TMP/pr8.head")" --train-receipt "$TMP/bad.receipt" ) >"$TMP/t4.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(merged_list)" = "8 " ] && ok "wrong-tree receipt: PR still merged" || fail "wrong-tree receipt: exit $rc merged=$(merged_list): $(tail -6 "$TMP/t4.log")"
[ "$(runs)" = 1 ] && ok "wrong-tree receipt: gate verified (receipt did not skip)" || fail "wrong-tree receipt: verify ran $(runs) times"

# ── 5. R1 (review #110): github-read không đọc được head của một PR → exit 79 của nó đi tới caller (không bị nuốt thành exit 1), không merge gì.
card_branch 9 f9; card_branch 10 f10
touch "$TMP/fail_head10"
reset_run; rm -f "$TMP/halt.json"
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 9,10 ) >"$TMP/t5.log" 2>&1; rc=$?
[ "$rc" -eq 79 ] && ok "head read outage: github-read exit 79 reaches the caller" || fail "head read outage: exit $rc (want 79): $(tail -5 "$TMP/t5.log")"
[ -z "$(merged_list)" ] && ok "head read outage: nothing merged" || fail "head read outage: merged $(merged_list)"
rm -f "$TMP/fail_head10" "$TMP/halt.json"

# ── 6. R2 (review #110): verify hết giờ (exit 124) không phải PR đỏ: thử lại đúng một lần, vẫn hết giờ thì dừng, không chia đôi, không `train-red`.
card_branch 11 f11; card_branch 12 slow; card_branch 13 f13
CFG_SLOW="$TMP/cfg-slow.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo x >> %s/verify.count; if [ -e slow ]; then exit 124; fi"]}\n' "$TMP" > "$CFG_SLOW"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG_SLOW" --prs 11,12,13 ) >"$TMP/t6.log" 2>&1; rc=$?
[ "$rc" -eq 12 ] && ok "timeout: train exit 12 (not 11)" || fail "timeout: exit $rc (want 12): $(tail -8 "$TMP/t6.log")"
if grep -q "train-red" "$TMP/t6.log"; then fail "timeout: a PR was blamed as red"; else ok "timeout: no PR blamed as red"; fi
[ "$(runs)" = 2 ] && ok "timeout: verify ran twice (one retry, no bisect)" || fail "timeout: verify ran $(runs) times (want 2)"
[ -z "$(merged_list)" ] && ok "timeout: nothing merged" || fail "timeout: merged $(merged_list)"
grep -q "train-result: 12 timeout" "$TMP/t6.log" && ok "timeout: PRs reported as timeout" || fail "timeout: no timeout result: $(grep train "$TMP/t6.log")"

# ── 7. R11 (review #110, blocker): PR sau bị policy chặn (nhãn money → exit 7) giữa đợt. Main không bao giờ dừng ở cây chưa verify:
#    verify chỉ xanh khi `bad` đi cùng `fix`; #14 thêm `bad`, #15 (money) thêm `fix`. Bỏ #15 khỏi chuỗi thì #14 một mình đỏ → không merge gì.
card_branch 14 bad; card_branch 15 fix
printf '{"files":[{"path":"fix"}],"labels":[{"name":"money"}],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr15.meta"
CFG_PAIR="$TMP/cfg-pair.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo x >> %s/verify.count; test ! -e bad || test -e fix"]}\n' "$TMP" > "$CFG_PAIR"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG_PAIR" --prs 14,15 ) >"$TMP/t7.log" 2>&1; rc=$?
if origin_has bad && ! origin_has fix; then fail "gate-blocked mid-train: origin/main stopped at an unverified tree (bad without fix)"; else ok "gate-blocked mid-train: origin/main never holds an unverified tree"; fi
[ "$rc" -ne 0 ] && ok "gate-blocked mid-train: train exit non-zero ($rc)" || fail "gate-blocked mid-train: exit 0"

# ── 8. R8: #17 sạch với base nhưng xung đột với #16 đứng trước (cùng sửa file `shared`): không phải conflict của PR, chờ wave sau (deferred), #16 vẫn merge.
git -C "$R" fetch -q origin
card_branch 16 shared; card_branch 17 shared
printf '{"files":[{"path":"shared"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr17.meta"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 16,17 ) >"$TMP/t8.log" 2>&1; rc=$?
grep -q "train-result: 17 deferred" "$TMP/t8.log" && ok "chain-only conflict: #17 deferred to the next wave" || fail "chain-only conflict: no deferred result: $(grep train "$TMP/t8.log")"
[ "$rc" -eq 0 ] && ok "chain-only conflict: train exit 0 (no rebase pass for #17)" || fail "chain-only conflict: exit $rc (want 0)"
[ "$(merged_list)" = "16 " ] && ok "chain-only conflict: #16 merged" || fail "chain-only conflict: merged $(merged_list)"

# ── 9. R9: head ghim không còn trong repo (nhánh bị force-push sau khi đọc): head đã dời (exit 6), không phải conflict.
card_branch 18 f18; card_branch 19 f19
echo 1111111111111111111111111111111111111111 > "$TMP/pr19.head"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 18,19 ) >"$TMP/t9.log" 2>&1; rc=$?
[ "$rc" -eq 6 ] && ok "missing pinned head: exit 6 (head moved)" || fail "missing pinned head: exit $rc (want 6): $(tail -4 "$TMP/t9.log")"
[ -z "$(merged_list)" ] && ok "missing pinned head: nothing merged" || fail "missing pinned head: merged $(merged_list)"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_train: all passed" || { echo "❌ test_merge_train: $FAILS failed"; exit 1; }
