#!/usr/bin/env bash
# Test hồi quy cho .claude/bin/super-board-merge-train.sh (#110), chạy offline với `gh` giả và origin bare.
# Verify của config đếm số lần chạy vào $TMP/verify.count và đỏ khi cây scratch có file `bad`.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
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
# Train chạy từ một bản bin liên kết (symlink) để thay merge gate bằng shim: shim ghi lại SB_MERGE_CALLER + đối số, tự trả lời
# `--preflight` (cờ của lane E; ca nào cần thì đặt $FAKE_DIR/preflight<N>.rc/.out), mọi lời gọi khác exec gate thật.
mkdir -p "$TMP/sbbin"
for f in "$ROOT"/.claude/bin/*; do ln -s "$f" "$TMP/sbbin/$(basename "$f")"; done
rm -f "$TMP/sbbin/super-board-merge-gate.sh"
cat > "$TMP/sbbin/super-board-merge-gate.sh" <<SH
#!/usr/bin/env bash
echo "\${SB_MERGE_CALLER:-<unset>} \$*" >> "\$FAKE_DIR/gate.calls"
pre=0; n=""; prev=""
for a in "\$@"; do
  [ "\$a" = --preflight ] && pre=1
  [ "\$prev" = --pr ] && n="\$a"
  prev="\$a"
done
dry=0; for a in "\$@"; do [ "\$a" = --dry-run ] && dry=1; done
# gatered<N>: lượt merge thật của gate (không preflight, không --dry-run) đỏ verify riêng: đuôi log ra stderr như gate thật, exit 11.
if [ "\$pre" = 0 ] && [ "\$dry" = 0 ] && [ -f "\$FAKE_DIR/gatered\$n" ]; then
  printf 'gate verify line %s\n' 1 2 3 >&2; echo "[merge-gate #\$n] verify failed (exit 1)" >&2
  exit 11
fi
if [ "\$pre" = 1 ]; then
  # Hợp đồng lane E: qua preflight = exit 0 + dòng "preflight: ok"; exit 0 không có dòng đó = PR đã MERGED.
  [ -f "\$FAKE_DIR/preflight\$n.out" ] && cat "\$FAKE_DIR/preflight\$n.out"
  [ -f "\$FAKE_DIR/preflight\$n.err" ] && cat "\$FAKE_DIR/preflight\$n.err" >&2
  [ -f "\$FAKE_DIR/preflight\$n.rc" ] && exit "\$(cat "\$FAKE_DIR/preflight\$n.rc")"
  echo "preflight: ok"
  exit 0
fi
exec bash "$ROOT/.claude/bin/super-board-merge-gate.sh" "\$@"
SH
chmod +x "$TMP/sbbin/super-board-merge-gate.sh"
TRAIN="$TMP/sbbin/super-board-merge-train.sh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_CALLER SB_MERGE_QUEUE
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo x >> %s/verify.count; test ! -e bad"]}\n' "$TMP" > "$CFG"
runs() { if [ -f "$TMP/verify.count" ]; then wc -l < "$TMP/verify.count" | tr -d ' '; else echo 0; fi; }
reset_run() { rm -f "$TMP/verify.count" "$TMP/merged" "$TMP/gate.calls" "$TMP/verify.files"; }
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

# ── 3. Một PR (Pha 2, hàng đợi merge): đi đúng đường train như mọi kích thước — preflight, verify_set một lần, dòng `train-result`.
card_branch 7 h7
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 7 ) >"$TMP/t3.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(merged_list)" = "7 " ] && ok "1 PR: merged" || fail "1 PR: exit $rc merged=$(merged_list)"
[ "$(runs)" = 1 ] && ok "1 PR: verified once" || fail "1 PR: verify ran $(runs) times"
grep -q "train-result: 7 merged" "$TMP/t3.log" && ok "1 PR: train path taken (train-result: 7 merged)" || fail "1 PR: no train-result line: $(tail -5 "$TMP/t3.log")"
grep -q -- "--pr 7 .*--preflight" "$TMP/gate.calls" && ok "1 PR: preflight ran before verify" || fail "1 PR: no preflight call: $(cat "$TMP/gate.calls" 2>/dev/null)"

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
#    Antigravity audit (B): chỉ PR hỏng rời đợt (`train-result: 19 gate-exit-6`), PR còn lại vẫn verify + merge.
card_branch 18 f18; card_branch 19 f19
echo 1111111111111111111111111111111111111111 > "$TMP/pr19.head"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 18,19 ) >"$TMP/t9.log" 2>&1; rc=$?
[ "$rc" -eq 6 ] && ok "missing pinned head: exit 6 (head moved)" || fail "missing pinned head: exit $rc (want 6): $(tail -4 "$TMP/t9.log")"
grep -q "^train-result: 19 gate-exit-6$" "$TMP/t9.log" && ok "missing pinned head: #19 leaves with gate-exit-6" || fail "missing pinned head: $(grep train- "$TMP/t9.log")"
[ "$(merged_list)" = "18 " ] && grep -q "^train-result: 18 merged$" "$TMP/t9.log" && ok "missing pinned head: #18 still verified and merged" || fail "missing pinned head: merged $(merged_list)"

# ── 10. #228 R1: `--prs N:sha` ghim head đã duyệt; PR có head đã dời khỏi sha đó rời đợt (exit 6), không bao giờ merge head chưa ai review.
card_branch 20 p20; card_branch 21 p21; card_branch 22 p22
OLD20=$(cat "$TMP/pr20.head"); OLD21=$(cat "$TMP/pr21.head"); OLD22=$(cat "$TMP/pr22.head")
echo more > "$W/issue-21-build/p21b"; git -C "$W/issue-21-build" add p21b; git -C "$W/issue-21-build" commit -qm "card 21 moved"
git -C "$W/issue-21-build" push -q origin issue-21-x
git -C "$R" rev-parse issue-21-x > "$TMP/pr21.head"
git -C "$R" diff origin/main issue-21-x > "$TMP/pr21.diff"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs "20:$OLD20,21:$OLD21,22:$OLD22" ) >"$TMP/t10.log" 2>&1; rc=$?
[ "$(merged_list)" = "20 22 " ] && ok "pinned heads: #21 (head moved after approval) did not merge, #20 #22 did" || fail "pinned heads: merged $(merged_list): $(tail -6 "$TMP/t10.log")"
grep -q "train-result: 21 head-moved" "$TMP/t10.log" && ok "pinned heads: #21 reported head-moved" || fail "pinned heads: no head-moved line: $(grep train "$TMP/t10.log")"
[ "$rc" -eq 6 ] && ok "pinned heads: train exit 6" || fail "pinned heads: exit $rc (want 6)"
if origin_has p21b; then fail "pinned heads: the unreviewed head reached origin/main"; else ok "pinned heads: the unreviewed head never reached origin/main"; fi
# Mọi PR dời head: không merge gì, exit 6.
card_branch 23 p23; card_branch 24 p24
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs "23:$OLD20,24:$OLD21" ) >"$TMP/t11.log" 2>&1; rc=$?
[ "$rc" -eq 6 ] && [ -z "$(merged_list)" ] && ok "every head moved: exit 6, nothing merged" || fail "every head moved: exit $rc merged=$(merged_list)"
# Một PR có ghim: đường gate thường với --expect-head; head dời thì gate từ chối (exit 6) và không merge.
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs "21:$OLD21" ) >"$TMP/t12.log" 2>&1; rc=$?
[ "$rc" -eq 6 ] && [ -z "$(merged_list)" ] && ok "single pinned PR with a moved head: gate refuses (exit 6)" || fail "single pinned PR: exit $rc merged=$(merged_list): $(tail -4 "$TMP/t12.log")"

# ── 11. #288: nhánh chậm hơn base (main đi tiếp sau khi #30 rẽ ra) + biên nhận đúng: một lần verify cho cả đợt, gate không verify lại.
card_branch 30 q30
git -C "$R" fetch -q origin; git -C "$R" worktree add -q --detach "$W/adv" origin/main
echo adv > "$W/adv/adv"; git -C "$W/adv" add adv; git -C "$W/adv" commit -qm "main moves on"; git -C "$W/adv" push -q origin HEAD:main
git -C "$R" worktree remove --force "$W/adv"
card_branch 31 q31
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 30,31 ) >"$TMP/t13.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(merged_list)" = "30 31 " ] && ok "branch behind base: both PRs merged" || fail "behind base: exit $rc merged=$(merged_list): $(tail -6 "$TMP/t13.log")"
[ "$(runs)" = 1 ] && ok "  … one verify for the batch (the receipt skipped the gates' own)" || fail "behind base: verify ran $(runs) times"
grep -q "verify skipped" "$TMP/t13.log" && ok "  … and the gate says it skipped verify" || fail "behind base: no 'verify skipped' line"
grep -q "verified green against main (0 command(s) run here" "$TMP/t13.log" \
  && ok "  … without claiming it ran a command" || fail "behind base: $(grep 'verified green' "$TMP/t13.log" | head -2)"

# ── 13. Pha 2: preflight rẻ của gate (policy/qa-report/AC) chạy cho từng PR TRƯỚC khi dựng cây. PR rớt preflight (exit 7) rời đợt trước
#    verify (cây verify không có file của nó), có `train-result: N gate-exit-7` và các dòng human-gate/approval-request thành `train-detail:`.
#    Mọi lời gọi gate mang SB_MERGE_CALLER=train.
card_branch 40 f40; card_branch 41 f41
printf '7\n' > "$TMP/preflight41.rc"
printf 'human-gate: money — label money\napproval-request: req-41 head\nunrelated line\nac-check: card #41 has 3 criteria\nqa-report: no proof line\n' > "$TMP/preflight41.out"
printf 'verification-readiness: the scratch tree has no post-fix-gate.py\n' > "$TMP/preflight41.err"
CFG_SEEN="$TMP/cfg-seen.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo x >> %s/verify.count; ls >> %s/verify.files; test ! -e bad"]}\n' "$TMP" "$TMP" > "$CFG_SEEN"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG_SEEN" --prs 40,41 ) >"$TMP/t14.log" 2>"$TMP/t14.err"; rc=$?
[ "$rc" -eq 7 ] && ok "preflight drop: train exit 7 (the gate's exit for #41)" || fail "preflight drop: exit $rc (want 7): $(tail -5 "$TMP/t14.err")"
grep -q "^train-result: 41 gate-exit-7$" "$TMP/t14.log" && ok "preflight drop: train-result: 41 gate-exit-7" || fail "preflight drop: $(grep train "$TMP/t14.log")"
grep -q "^train-detail: 41 human-gate: money — label money$" "$TMP/t14.log" && grep -q "^train-detail: 41 approval-request: req-41 head$" "$TMP/t14.log" \
  && ok "preflight drop: gate lines copied as train-detail" || fail "preflight drop: train-detail missing: $(grep train "$TMP/t14.log")"
grep -q "train-detail: 41 unrelated" "$TMP/t14.log" && fail "preflight drop: a non-detail gate line became train-detail" || ok "preflight drop: only approval/human-gate/needs-you lines are details"
# R1 mục 3: ac-check / qa-report (stdout của gate) và verification-readiness (stderr của gate) cũng thành train-detail.
grep -q "^train-detail: 41 ac-check: card #41 has 3 criteria$" "$TMP/t14.log" && grep -q "^train-detail: 41 qa-report: no proof line$" "$TMP/t14.log" \
  && grep -q "^train-detail: 41 verification-readiness: the scratch tree has no post-fix-gate.py$" "$TMP/t14.log" \
  && ok "preflight drop: ac-check / qa-report / verification-readiness copied as train-detail" || fail "preflight drop: detail lines: $(grep train-detail "$TMP/t14.log")"
grep -q "verification-readiness: the scratch tree" "$TMP/t14.err" && ok "  … the gate's stderr still reaches the train's stderr" || fail "  … gate stderr lost: $(tail -3 "$TMP/t14.err")"
[ "$(merged_list)" = "40 " ] && ok "preflight drop: #40 merged, #41 did not" || fail "preflight drop: merged $(merged_list)"
[ "$(runs)" = 1 ] && ok "preflight drop: one verify" || fail "preflight drop: verify ran $(runs) times"
grep -q "^f41$" "$TMP/verify.files" && fail "preflight drop: #41 was inside the verified tree" || ok "preflight drop: #41 left before any tree was built"
grep -q -- "--pr 40 .*--preflight" "$TMP/gate.calls" && ok "preflight drop: #40 preflighted too" || fail "preflight drop: no preflight for #40"
if grep -qv "^train " "$TMP/gate.calls"; then fail "SB_MERGE_CALLER: a gate call without SB_MERGE_CALLER=train: $(grep -v '^train ' "$TMP/gate.calls" | head -2)"; else ok "SB_MERGE_CALLER=train on every gate call"; fi
rm -f "$TMP/preflight41.rc" "$TMP/preflight41.out" "$TMP/preflight41.err"
# R1 mục 7: gate nào cũng có --preflight; exit 64 của preflight là lỗi thật (cú pháp): PR rời đợt với gate-exit-64, không verify, không merge.
card_branch 42 f42; printf '64\n' > "$TMP/preflight42.rc"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 42 ) >"$TMP/t15.log" 2>&1; rc=$?
[ "$rc" -eq 64 ] && [ -z "$(merged_list)" ] && grep -q "^train-result: 42 gate-exit-64$" "$TMP/t15.log" && [ "$(runs)" = 0 ] \
  && ok "preflight exit 64: the PR leaves with gate-exit-64, nothing verified or merged" || fail "preflight 64: exit $rc merged=$(merged_list) runs=$(runs): $(tail -4 "$TMP/t15.log")"
grep -q "has no --preflight" "$TRAIN" && fail "the dead 'gate has no --preflight' branch is still in the train" || ok "no dead 'gate has no --preflight' branch"
rm -f "$TMP/preflight42.rc"
# Preflight exit 0 KHÔNG có dòng "preflight: ok" = PR đã merge (lane E): rời chuỗi trước khi dựng cây, kết quả `merged`, gate không merge lại.
card_branch 43 f43; card_branch 44 f44; printf '0\n' > "$TMP/preflight43.rc"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG_SEEN" --prs 43,44 ) >"$TMP/t16.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q "^train-result: 43 merged$" "$TMP/t16.log" && grep -q "^train-result: 44 merged$" "$TMP/t16.log" \
  && ok "preflight says already merged: train-result merged, exit 0" || fail "already merged: exit $rc: $(grep train "$TMP/t16.log")"
[ "$(merged_list)" = "44 " ] && ok "  … the gate did not merge #43 again" || fail "  … merged $(merged_list)"
grep -q "^f43$" "$TMP/verify.files" && fail "  … #43 was inside the verified tree" || ok "  … #43 left before any tree was built"
rm -f "$TMP/preflight43.rc"

# ── 14. R1 mục 3: đuôi verify đỏ (≤ 20 dòng, bỏ mã màu) của chính PR thủ phạm thành `train-detail: <PR> <dòng>`; PR xanh không có dòng nào.
card_branch 46 f46; card_branch 47 bad
CFG_RED="$TMP/cfg-red.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo x >> %s/verify.count; for i in $(seq 1 30); do echo noise-$i; done; if [ -e bad ]; then printf \\"\\\\033[31mFAILED test_bad\\\\033[0m\\\\n\\"; exit 1; fi"]}\n' "$TMP" > "$CFG_RED"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG_RED" --prs 46,47 ) >"$TMP/t17.log" 2>"$TMP/t17.err"; rc=$?
[ "$rc" -eq 11 ] && grep -q "^train-result: 47 red$" "$TMP/t17.log" && ok "red tail: #47 red (exit 11)" || fail "red tail: exit $rc: $(grep train "$TMP/t17.log") $(tail -3 "$TMP/t17.err")"
grep -q "^train-detail: 47 FAILED test_bad$" "$TMP/t17.log" && ok "red tail: the failing line is a train-detail of #47 (colour codes stripped)" || fail "red tail: $(grep train-detail "$TMP/t17.log" | tail -3)"
n47=$(grep -c "^train-detail: 47 " "$TMP/t17.log"); [ "$n47" -ge 1 ] && [ "$n47" -le 20 ] && ok "red tail: at most 20 detail lines ($n47)" || fail "red tail: $n47 detail lines"
grep -q "^train-detail: 46 " "$TMP/t17.log" && fail "red tail: the green PR #46 got detail lines" || ok "red tail: no detail for the green PR"
# 14b. Bảo mật: queue chép train-detail vào comment issue CÔNG KHAI → token / khoá trong log verify phải bị che (redact_secrets của kit).
#     Token giả ghép lúc chạy (không có nguyên văn trong file: bộ quét secret đọc diff).
FAKE_TOK="gh""p_$(printf 'Z%.0s' $(seq 1 30))"
PEM_HDR="-----BEGIN PRIV""ATE KEY-----"; PEM_BODY="MIIE$(printf 'K%.0s' $(seq 1 40))"   # khối khoá PEM, đuôi log cắt mất dòng END
card_branch 49 bad
CFG_LEAK="$TMP/cfg-leak.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo x >> %s/verify.count; if [ -e bad ]; then echo leaked token=%s; echo auth %s; echo %s; echo %s; exit 1; fi"]}\n' "$TMP" "$FAKE_TOK" "$FAKE_TOK" "$PEM_HDR" "$PEM_BODY" > "$CFG_LEAK"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG_LEAK" --prs 49 ) >"$TMP/t19.log" 2>"$TMP/t19.err"; rc=$?
[ "$rc" -eq 11 ] && grep -q "^train-result: 49 red$" "$TMP/t19.log" && ok "secret tail: #49 red (exit 11)" || fail "secret tail: exit $rc: $(grep train "$TMP/t19.log")"
if grep -q "$FAKE_TOK" "$TMP/t19.log"; then fail "secret tail: a token from the verify log reached train-detail (public issue comment)"
else ok "secret tail: no token in train-detail"; fi
grep -q "^train-detail: 49 .*«redacted»" "$TMP/t19.log" && ok "secret tail: the leaked lines are kept, the values redacted" || fail "secret tail: no «redacted» line: $(grep train-detail "$TMP/t19.log" | tail -3)"
if grep -q "$PEM_BODY" "$TMP/t19.log"; then fail "secret tail: a private-key body reached train-detail (the tail must be redacted as one text, not line by line)"
else ok "secret tail: a multi-line private key block is redacted whole"; fi
# Verify riêng của gate đỏ ở lượt merge (exit 11 → `red`): đuôi stderr của gate thành train-detail.
card_branch 48 f48; touch "$TMP/gatered48"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 48 ) >"$TMP/t18.log" 2>"$TMP/t18.err"; rc=$?
[ "$rc" -eq 11 ] && grep -q "^train-result: 48 red$" "$TMP/t18.log" && grep -q "^train-detail: 48 gate verify line 3$" "$TMP/t18.log" \
  && ok "gate red at merge: train-result red + the gate's verify tail as train-detail" || fail "gate red: exit $rc: $(grep train "$TMP/t18.log")"
rm -f "$TMP/gatered48"

# ── 15. R1 mục 6 (F4): queue bật (merge_queue.enabled + worker_backend claude-p) + SB_BOARD_WORKER=1 + SB_MERGE_CALLER khác `queue`
#    → train thoát 13 kèm dòng merge-queue:, trước mọi lời gọi gate (fix-round1-contract.md, "Cờ worker board").
card_branch 49 f49; printf '7\n' > "$TMP/preflight49.rc"
CFG_Q="$TMP/cfg-q.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"worker_backend":"claude-p","merge_queue":{"enabled":true},"verify_commands":["true"]}\n' > "$CFG_Q"
CFG_QW="$TMP/cfg-qw.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"worker_backend":"workflow","merge_queue":{"enabled":true},"verify_commands":["true"]}\n' > "$CFG_QW"
reset_run
( cd "$W/review" && SB_BOARD_WORKER=1 bash "$TRAIN" --config "$CFG_Q" --prs 49 ) >"$TMP/t19.log" 2>&1; rc=$?
[ "$rc" -eq 13 ] && grep -q "^merge-queue: label the PR merge-queue instead of calling the gate directly$" "$TMP/t19.log" && [ ! -s "$TMP/gate.calls" ] \
  && ok "F4: a board worker calling the train with the queue on → exit 13, no gate call" || fail "F4: exit $rc: $(tail -3 "$TMP/t19.log")"
reset_run
( cd "$W/review" && SB_BOARD_WORKER=1 SB_MERGE_CALLER=queue bash "$TRAIN" --config "$CFG_Q" --prs 49 ) >"$TMP/t20.log" 2>&1; rc=$?
[ "$rc" -eq 7 ] && ok "F4: SB_MERGE_CALLER=queue runs (preflight exit 7 here)" || fail "F4 queue caller: exit $rc: $(tail -3 "$TMP/t20.log")"
reset_run
( cd "$W/review" && SB_BOARD_WORKER=1 bash "$TRAIN" --config "$CFG_QW" --prs 49 ) >"$TMP/t21.log" 2>&1; rc=$?
[ "$rc" -eq 7 ] && ok "F4: worker_backend workflow = queue off, the train runs" || fail "F4 workflow backend: exit $rc"
reset_run
( cd "$W/review" && SB_BOARD_WORKER=1 SB_MERGE_QUEUE=0 bash "$TRAIN" --config "$CFG_Q" --prs 49 ) >"$TMP/t22.log" 2>&1; rc=$?
[ "$rc" -eq 7 ] && ok "F4: SB_MERGE_QUEUE=0 = queue off, the train runs" || fail "F4 SB_MERGE_QUEUE=0: exit $rc"
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG_Q" --prs 49 ) >"$TMP/t23.log" 2>&1; rc=$?
[ "$rc" -eq 7 ] && ok "F4: outside a board worker (no SB_BOARD_WORKER) the train runs" || fail "F4 no worker flag: exit $rc"
rm -f "$TMP/preflight49.rc"

# ── 16. R1 mục 8: CLAUDE_PROJECT_DIR / TARGET_DIR của môi trường (cây chính) không được lọt vào verify: post-fix-gate ưu tiên biến này
#    (get_project_dir), nên verify sẽ kiểm nhầm cây chính thay cho scratch. Verify giả chọn thư mục y như get_project_dir rồi ghi lại.
card_branch 50 f50
CFG_PD="$TMP/cfg-pd.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo \\"${CLAUDE_PROJECT_DIR:-${TARGET_DIR:-$(pwd -P)}}\\" >> %s/pd.log"]}\n' "$TMP" > "$CFG_PD"
reset_run; rm -f "$TMP/pd.log"
( cd "$W/review" && CLAUDE_PROJECT_DIR="$R" TARGET_DIR="$R" bash "$TRAIN" --config "$CFG_PD" --prs 50 ) >"$TMP/t24.log" 2>&1; rc=$?
grep -q "\.train-scratch-" "$TMP/pd.log" 2>/dev/null && ! grep -qx "$R" "$TMP/pd.log" && ok "verify audits the train scratch, not CLAUDE_PROJECT_DIR=<main tree>" || fail "verify project dir: $(cat "$TMP/pd.log" 2>/dev/null) (exit $rc)"

# ── 17. Antigravity audit (B): nhánh PR không còn trên origin (fork / nhánh bị xoá) không giết cả đợt; mọi PR đã nhận có train-result,
#    kể cả PR rớt preflight trước đó.
card_branch 51 f51; card_branch 52 f52; card_branch 53 f53; printf '7\n' > "$TMP/preflight51.rc"
git -C "$R" push -q origin --delete issue-52-x
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 51,52,53 ) >"$TMP/t25.log" 2>&1; rc=$?
[ "$rc" -ne 128 ] && grep -q "^train-result: 51 gate-exit-7$" "$TMP/t25.log" && grep -q "^train-result: 52 " "$TMP/t25.log" && grep -q "^train-result: 53 merged$" "$TMP/t25.log" \
  && ok "branch gone from origin: every PR still gets a train-result (exit $rc), #53 merged" || fail "branch gone: exit $rc: $(grep train- "$TMP/t25.log") $(tail -3 "$TMP/t25.log")"
rm -f "$TMP/preflight51.rc"

# ── 18. Antigravity audit (A): train giữ fcntl LOCK_EX trên <common>/super-board/merge-train.lock cả lượt; train thứ hai → exit 4, không
#    train-result, 0 lời gọi gate cho #55 (các assert dưới kiểm). Ca cuối: train bị kill -9 giữa verify (verify mồ côi còn chạy) → train sau
#    vẫn lấy được khoá.
card_branch 54 f54; card_branch 55 f55
CFG_HOLD="$TMP/cfg-hold.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["if [ -e %s/hold ] && [ ! -e %s/hold.started ]; then : > %s/hold.started; while [ -e %s/hold ]; do sleep 0.1; done; fi"]}\n' "$TMP" "$TMP" "$TMP" "$TMP" > "$CFG_HOLD"
reset_run; rm -f "$TMP/hold.started"; : > "$TMP/hold"
( cd "$W/review" && exec bash "$TRAIN" --config "$CFG_HOLD" --prs 54 ) >"$TMP/t26a.log" 2>&1 & T1=$!
i=0; while [ ! -e "$TMP/hold.started" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
( cd "$W/review" && bash "$TRAIN" --config "$CFG_HOLD" --prs 55 ) >"$TMP/t26b.log" 2>&1; rc=$?
[ "$rc" -eq 4 ] && ! grep -q "^train-result:" "$TMP/t26b.log" && ! grep -q -- "--pr 55" "$TMP/gate.calls" 2>/dev/null \
  && ok "second train while one runs: exit 4, no train-result, no gate call" || fail "second train: exit $rc: $(tail -3 "$TMP/t26b.log")"
kill -9 "$T1" 2>/dev/null; wait "$T1" 2>/dev/null
( cd "$W/review" && bash "$TRAIN" --config "$CFG_HOLD" --prs 55 ) >"$TMP/t26c.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q "^train-result: 55 merged$" "$TMP/t26c.log" && ok "train killed mid-verify: its orphan verify does not hold the lock" || fail "after kill -9: exit $rc: $(tail -3 "$TMP/t26c.log")"
rm -f "$TMP/hold"

# ── 12. #288: ghi chú ponytail đầu file mô tả đúng hành vi: PR bị gate chặn đã ra khỏi chuỗi trước khi verify (R11), không "vẫn nằm trong chuỗi".
grep -q "vẫn nằm trong chuỗi verify" "$TRAIN" && fail "the ponytail note at the top still says a gate-blocked PR stays in the verify chain" \
  || ok "ponytail note matches R11 (blocked PRs leave the chain before verify)"

# ── 13. #579: verify_timed_out chạy dưới `set -euo pipefail` của train; log lớn (> bộ đệm pipe) làm `grep -q` thoát sớm → printf SIGPIPE → 141.
#    Hàm được trích nguyên văn từ script rồi chạy dưới pipefail, VLOG > 128 KB, dòng kết luận ở đầu log.
VT_FN="$TMP/verify_timed_out.fn"
awk '/^verify_timed_out\(\) [{(]/ { on = 1 } on { print } on && /^[})]/ { exit }' "$TRAIN" > "$VT_FN"
vt_log() { # vt_log <file> <đầu log>: đầu log + ~200 KB đệm
  printf '%b' "$2" > "$1"; head -c 200000 /dev/zero | tr '\0' 'x' >> "$1"; printf '\n' >> "$1"
}
vt_run() { # vt_run <file> <rc>: in rc của verify_timed_out dưới pipefail + stderr
  ( set -euo pipefail; VLOG="$1"; . "$VT_FN"; verify_timed_out "$2"; ) 2>"$TMP/vt.err"; echo $?
}
vt_log "$TMP/vt1.log" 'KẾT LUẬN: đỏ\n  [ ] TIMEOUT | suite-a\n  [ ] TIMEOUT | suite-b\n'
vt_log "$TMP/vt2.log" 'KẾT LUẬN: đỏ\n  [ ] TIMEOUT | suite-a\n  [ ] FAIL | suite-b\n'
vt_log "$TMP/vt3.log" 'chạy lệnh khác\nTIMEOUT after 900s\n'
vt_log "$TMP/vt4.log" 'chạy lệnh khác\nlỗi thật\n'
[ "$(vt_run "$TMP/vt1.log" 1)" -eq 0 ] && ok "big VLOG, KẾT LUẬN + only TIMEOUT suites → timed out (0)" || fail "big VLOG all-TIMEOUT: want 0"
grep -q "Broken pipe" "$TMP/vt.err" && fail "verify_timed_out printed 'Broken pipe'" || ok "no 'Broken pipe' on a big VLOG"
[ "$(vt_run "$TMP/vt2.log" 1)" -ne 0 ] && ok "big VLOG, KẾT LUẬN + a FAIL suite → real red (non-zero)" || fail "big VLOG with FAIL suite: want non-zero"
[ "$(vt_run "$TMP/vt3.log" 1)" -eq 0 ] && ok "big VLOG, no KẾT LUẬN, 'TIMEOUT after' → timed out (0)" || fail "big VLOG 'TIMEOUT after': want 0"
[ "$(vt_run "$TMP/vt4.log" 1)" -ne 0 ] && ok "big VLOG, no KẾT LUẬN, no timeout text → non-zero" || fail "big VLOG plain red: want non-zero"
[ "$(vt_run "$TMP/vt4.log" 124)" -eq 0 ] && ok "rc=124 → timed out (0)" || fail "rc 124: want 0"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_train: all passed" || { echo "❌ test_merge_train: $FAILS failed"; exit 1; }
