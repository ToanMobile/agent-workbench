#!/usr/bin/env bash
# Test hồi quy #740: super-board-merge-train.sh dựng chuỗi trong scratch bằng `git merge`; từ PR thứ hai (hay PR chưa chứa base mới)
# git phải tạo commit merge và hook commit-msg / pre-merge-commit của repo (GeelyEx2: guard-check đòi trailer `Bug:`) từ chối nó →
# train coi là "không merge được": PR sạch bị `deferred` / `conflict`. Scratch không bao giờ được push: merge ở đó không chạy hook.
# Xung đột thật vẫn ra deferred / conflict như cũ, log ghi lý do (file xung đột).
# Offline: `gh` giả, origin bare, merge gate giả (đối tượng test là train; gate thật có test riêng). Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-train-hook.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"; echo a > "$R/a"
# Hook của repo, commit vào base như .githooks của GeelyEx2 (core.hooksPath tương đối = theo gốc worktree, nên scratch cũng có).
# Mỗi hook từ chối mọi commit merge và ghi `<tên hook> <gốc worktree>` vào $FAKE_DIR/hook.fired.
mkdir -p "$R/.githooks-msg" "$R/.githooks-pmc"
cat > "$R/.githooks-msg/commit-msg" <<'SH'
#!/usr/bin/env bash
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 || grep -q '^Merge ' "$1"; then
  echo "commit-msg $(pwd -P)" >> "$FAKE_DIR/hook.fired"
  echo "guard-check: a merge commit touches a guarded file without a 'Bug: <id>' trailer" >&2
  exit 1
fi
exit 0
SH
cat > "$R/.githooks-pmc/pre-merge-commit" <<'SH'
#!/usr/bin/env bash
echo "pre-merge-commit $(pwd -P)" >> "$FAKE_DIR/hook.fired"
echo "pre-merge-commit: merge commits are refused here" >&2
exit 1
SH
chmod +x "$R/.githooks-msg/commit-msg" "$R/.githooks-pmc/pre-merge-commit"
git -C "$R" add .gitignore a .githooks-msg .githooks-pmc; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main

# card_branch <N> <file>: nhánh issue-<N>-x từ origin/main thêm file <file> (nội dung N), đã đẩy lên origin; metadata cho gh giả.
card_branch() {
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$1-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$1-build" "issue-$1-x"
  echo "$1" > "$W/issue-$1-build/$2"
  git -C "$W/issue-$1-build" add "$2"; git -C "$W/issue-$1-build" commit -qm "card $1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  printf '{"files":[{"path":"%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$2" > "$TMP/pr$1.meta"
}
# main_moves <file> <nội dung>: main trên origin đi tiếp một commit (thường, không phải merge: hook cho qua).
main_moves() {
  git -C "$R" fetch -q origin; git -C "$R" worktree add -q --detach "$W/adv" origin/main
  echo "$2" > "$W/adv/$1"; git -C "$W/adv" add "$1"; git -C "$W/adv" commit -qm "main moves on"; git -C "$W/adv" push -q origin HEAD:main
  git -C "$R" worktree remove --force "$W/adv"
}

mkdir -p "$TMP/bin" "$TMP/sbbin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
# gh giả: `pr merge` mô phỏng squash của GitHub (một commit một cha trên main của origin, cây = merge(main, head), không chạy hook).
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr merge "*)
    git -C "$FAKE_REPO" fetch -q origin main "issue-$n-x"
    tree=$(git -C "$FAKE_REPO" merge-tree --write-tree origin/main "$head") || exit 1
    c=$(git -C "$FAKE_REPO" commit-tree "$tree" -p origin/main -m "squash #$n")
    git -C "$FAKE_REPO" push -q origin "$c:refs/heads/main" && echo "$n" >> "$FAKE_DIR/merged" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
# Train chạy từ bản bin liên kết với merge gate giả: preflight → "preflight: ok"; --dry-run → 0; lượt merge chép biên nhận train đưa sang
# ($FAKE_DIR/receipt.<N>) rồi gộp qua `gh pr merge` giả.
for f in "$ROOT"/.claude/bin/*; do ln -s "$f" "$TMP/sbbin/$(basename "$f")"; done
rm -f "$TMP/sbbin/super-board-merge-gate.sh"
cat > "$TMP/sbbin/super-board-merge-gate.sh" <<'SH'
#!/usr/bin/env bash
mode=merge; n=""; rcpt=""; prev=""
for a in "$@"; do
  case "$a" in --preflight) mode=preflight ;; --dry-run) mode=dry ;; esac
  [ "$prev" = --pr ] && n="$a"; [ "$prev" = --train-receipt ] && rcpt="$a"
  prev="$a"
done
echo "$mode $n" >> "$FAKE_DIR/gate.calls"
case "$mode" in
  preflight) echo "preflight: ok" ;;
  merge) [ -z "$rcpt" ] || cp "$rcpt" "$FAKE_DIR/receipt.$n"; gh pr merge "$n" --squash || exit 1 ;;
esac
exit 0
SH
chmod +x "$TMP/sbbin/super-board-merge-gate.sh"
TRAIN="$TMP/sbbin/super-board-merge-train.sh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
# Hàng heavy_slot riêng của test (như test_merge_queue_e2e.sh): verify của train không chờ tải máy, không chen vé vào hàng thật.
export SB_HEAVY_SLOT_DIR="$TMP/slots" DEVKIT_SLOT_LOAD_MAX=100000
unset SB_MERGE_CALLER SB_MERGE_QUEUE SB_BOARD_WORKER
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo x >> %s/verify.count; ls >> %s/verify.files"]}\n' "$TMP" "$TMP" > "$CFG"
git -C "$R" worktree add -q --detach "$W/review" origin/main
runs() { if [ -f "$TMP/verify.count" ]; then wc -l < "$TMP/verify.count" | tr -d ' '; else echo 0; fi; }
reset_run() { rm -f "$TMP/verify.count" "$TMP/verify.files" "$TMP/merged" "$TMP/gate.calls" "$TMP/hook.fired" "$TMP"/receipt.*; }
origin_has() { git -C "$O" cat-file -e "main:$1" 2>/dev/null; }
merged_list() { sort -n "$TMP/merged" 2>/dev/null | tr '\n' ' '; }
run_train() { ( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs "$1" ) >"$TMP/$2.log" 2>"$TMP/$2.err"; }
# hook_refuses <hooksPath> <head A> <head B>: tiền đề — với hook này, merge B sau A ngoài train thật sự bị từ chối (fixture không rỗng).
hook_refuses() {
  local p="$TMP/probe" r=0
  git -C "$R" config core.hooksPath "$1"; rm -f "$TMP/hook.fired"
  git -C "$R" worktree add -q --detach "$p" "$2"
  git -C "$p" merge --no-edit -q "$3" >/dev/null 2>&1 && r=1
  git -C "$p" merge --abort >/dev/null 2>&1
  git -C "$R" worktree remove --force "$p"
  [ "$r" -eq 0 ] && [ -s "$TMP/hook.fired" ]
}

# ── 1. AC1 (GeelyEx2 Train D): hook commit-msg chặn commit merge. Hai PR cùng chứa base, đụng file khác nhau: cả hai merged, một verify.
card_branch 1 f1; card_branch 2 f2
hook_refuses .githooks-msg "$(cat "$TMP/pr1.head")" "$(cat "$TMP/pr2.head")" \
  && ok "fixture: the commit-msg hook refuses a merge commit outside the train" || fail "fixture: the commit-msg hook did not refuse a merge commit"
reset_run
run_train 1,2 t1; rc=$?
[ "$rc" -eq 0 ] && ok "commit-msg hook: train exit 0" || fail "commit-msg hook: exit $rc: $(grep train- "$TMP/t1.log") $(tail -4 "$TMP/t1.err")"
grep -q "^train-result: 1 merged$" "$TMP/t1.log" && grep -q "^train-result: 2 merged$" "$TMP/t1.log" \
  && ok "commit-msg hook: both PRs merged" || fail "commit-msg hook: $(grep train-result "$TMP/t1.log")"
grep -qE "^train-result: [0-9]+ (deferred|conflict)$" "$TMP/t1.log" && fail "commit-msg hook: a clean PR was deferred/conflict" || ok "commit-msg hook: no PR deferred or conflict"
[ "$(runs)" = 1 ] && grep -qx f1 "$TMP/verify.files" && grep -qx f2 "$TMP/verify.files" \
  && ok "commit-msg hook: one verify on the chain holding both PRs" || fail "commit-msg hook: verify ran $(runs) times; files: $(tr '\n' ' ' < "$TMP/verify.files" 2>/dev/null)"
origin_has f1 && origin_has f2 && ok "commit-msg hook: origin/main holds f1 and f2" || fail "commit-msg hook: origin/main misses a file"
# Biên nhận (dựng lại chuỗi trước khi merge): cây sau head #1 = main sau squash #1, cây sau head #2 = main sau squash #2.
T1=$(awk -v h="$(cat "$TMP/pr1.head")" '$1 == h { print $2 }' "$TMP/receipt.2" 2>/dev/null)
T2=$(awk -v h="$(cat "$TMP/pr2.head")" '$1 == h { print $2 }' "$TMP/receipt.2" 2>/dev/null)
[ -n "$T1" ] && [ "$T1" = "$(git -C "$O" rev-parse 'main~1^{tree}')" ] && [ -n "$T2" ] && [ "$T2" = "$(git -C "$O" rev-parse 'main^{tree}')" ] \
  && ok "commit-msg hook: the receipt holds the chain tree after each head" || fail "commit-msg hook: receipt $(cat "$TMP/receipt.2" 2>/dev/null || echo '<none>')"
grep -q "train-scratch" "$TMP/hook.fired" 2>/dev/null && fail "commit-msg hook: the hook ran in the train scratch: $(cat "$TMP/hook.fired")" \
  || ok "commit-msg hook: no hook ran in the train scratch"

# ── 2. Hook pre-merge-commit chặn commit merge: cũng không chạy trong scratch, cả hai PR merged.
card_branch 3 f3; card_branch 4 f4
hook_refuses .githooks-pmc "$(cat "$TMP/pr3.head")" "$(cat "$TMP/pr4.head")" \
  && ok "fixture: the pre-merge-commit hook refuses a merge commit outside the train" || fail "fixture: the pre-merge-commit hook did not refuse"
reset_run
run_train 3,4 t2; rc=$?
[ "$rc" -eq 0 ] && grep -q "^train-result: 3 merged$" "$TMP/t2.log" && grep -q "^train-result: 4 merged$" "$TMP/t2.log" \
  && ok "pre-merge-commit hook: both PRs merged (exit 0)" || fail "pre-merge-commit hook: exit $rc: $(grep train-result "$TMP/t2.log") $(tail -4 "$TMP/t2.err")"
grep -q "train-scratch" "$TMP/hook.fired" 2>/dev/null && fail "pre-merge-commit hook: it ran in the train scratch" || ok "pre-merge-commit hook: no hook ran in the train scratch"

# ── 3. AC2: PR chưa chứa base mới nhất (main đi tiếp sau khi #5 rẽ ra) nhưng merge sạch: chuỗi dựng được (commit merge), verify, merged.
git -C "$R" config core.hooksPath .githooks-msg
card_branch 5 f5; main_moves adv adv; card_branch 6 f6
reset_run
run_train 5,6 t3; rc=$?
[ "$rc" -eq 0 ] && grep -q "^train-result: 5 merged$" "$TMP/t3.log" && grep -q "^train-result: 6 merged$" "$TMP/t3.log" \
  && ok "behind base: #5 (behind) and #6 merged, exit 0" || fail "behind base: exit $rc: $(grep train-result "$TMP/t3.log") $(tail -4 "$TMP/t3.err")"
grep -qE "^train-result: 5 (deferred|conflict)$" "$TMP/t3.log" && fail "behind base: #5 deferred/conflict" || ok "behind base: #5 not deferred or conflict"
[ "$(runs)" = 1 ] && grep -qx f5 "$TMP/verify.files" && grep -qx adv "$TMP/verify.files" \
  && ok "behind base: verified once on base + #5 + #6" || fail "behind base: verify ran $(runs) times; files: $(tr '\n' ' ' < "$TMP/verify.files" 2>/dev/null)"

# ── 4. AC3: xung đột thật vẫn như cũ, log ghi lý do. 4a: #8 sạch với base, xung đột với #7 đứng trước (cùng thêm `shared`) → deferred.
card_branch 7 shared; card_branch 8 shared
reset_run
run_train 7,8 t4; rc=$?
[ "$rc" -eq 0 ] && grep -q "^train-result: 7 merged$" "$TMP/t4.log" && grep -q "^train-result: 8 deferred$" "$TMP/t4.log" \
  && ok "chain-only conflict: #7 merged, #8 deferred (exit 0)" || fail "chain-only conflict: exit $rc: $(grep train-result "$TMP/t4.log")"
grep -q "PR #8 .*conflicts: shared.*deferred" "$TMP/t4.err" && ok "chain-only conflict: the log names the conflicting file" \
  || fail "chain-only conflict: no reason in the log: $(grep -i -e 'PR #8' "$TMP/t4.err" | head -3)"
# 4b: #9 xung đột với chính base (main thêm `cfile` khác nội dung sau khi #9 rẽ ra) → conflict, exit 5.
card_branch 9 cfile; main_moves cfile main-side
reset_run
run_train 9 t5; rc=$?
[ "$rc" -eq 5 ] && grep -q "^train-result: 9 conflict$" "$TMP/t5.log" && [ -z "$(merged_list)" ] \
  && ok "base conflict: #9 conflict, exit 5, nothing merged" || fail "base conflict: exit $rc: $(grep train-result "$TMP/t5.log") merged=$(merged_list)"
grep -q "PR #9 .*conflicts: cfile.*conflict" "$TMP/t5.err" && ok "base conflict: the log names the conflicting file" \
  || fail "base conflict: no reason in the log: $(grep -i -e 'PR #9' "$TMP/t5.err" | head -3)"

[ "$FAILS" -eq 0 ] && { echo "PASS test_merge_train_hook_chain"; exit 0; }
echo "FAIL test_merge_train_hook_chain: $FAILS"; exit 1
