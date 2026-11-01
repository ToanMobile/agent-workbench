#!/usr/bin/env bash
# #740 + #775: merge train dựng chuỗi scratch bằng `git merge … >/dev/null 2>&1`. Từ PR thứ hai (hay PR chậm hơn base) git phải tạo
# commit gộp và hook commit-msg của repo chạy trên nó (GeelyEx2 guard-check). Hook từ chối thì train xếp PR là `deferred` / `conflict`
# mà không in lý do nào: Train D của GeelyEx2 (31/10) chỉ gộp được PR đầu.
# Luật (chỉ đạo trên #740: KHÔNG tắt hook trong train/gate):
#   - hook vẫn chạy trên commit gộp của scratch; hook kiểu guard-check đã sửa (GeelyEx2 #181: commit gộp chỉ xét file khác MỌI cha)
#     cho cả hai PR đụng file guard khác nhau cùng merge, và PR chậm hơn base vẫn dựng được chuỗi + verify (AC #740);
#   - hook từ chối mà không có file xung đột: không ghi `conflict`; PR một mình bị từ chối → `gate-exit-5` (đúng mã merge gate thoát
#     trong cùng tình huống) kèm lời hook ở `train-detail:`; chỉ bị từ chối trong chuỗi → `deferred`, log ghi lời hook (AC #775);
#   - xung đột thật vẫn `conflict` / exit 5, log ghi tên file xung đột.
# Chạy offline với `gh` giả và origin bare (cùng khung với test_merge_train.sh). Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-train-hook-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Không đọc config git của máy (core.hooksPath, commit.gpgsign…): kết quả chỉ do fixture
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP/xdg"
export SB_HEAVY_SLOT_DIR="$TMP/heavy-slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main

# Hook commit-msg dùng chung mọi worktree (core.hooksPath tuyệt đối). Chế độ đọc từ $FAKE_DIR/hook.mode:
#   guard        như guard-check.py của GeelyEx2 sau #181: commit đụng file guard-* thiếu `Bug:` bị chặn; commit gộp chỉ xét file khác MỌI cha
#   refuse-merge như guard-check trước #181: mọi commit gộp bị chặn (lý do ở dòng ĐẦU, rồi 6 dòng hướng dẫn)
#   (không có)   cho qua
# Mỗi lần chạy ghi một dòng vào hook.calls: chứng minh train KHÔNG tắt hook.
mkdir -p "$TMP/hooks"
cat > "$TMP/hooks/commit-msg" <<'SH'
#!/bin/sh
mode=$(cat "$FAKE_DIR/hook.mode" 2>/dev/null)
merge=0; git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && merge=1
echo "merge=$merge mode=$mode dir=$(pwd -P)" >> "$FAKE_DIR/hook.calls"
grep -q '^Bug:' "$1" && exit 0
case "$mode" in
  refuse-merge)
    [ "$merge" = 1 ] || exit 0
    echo "guard-check: commit gop bi tu choi (HOOK-REF""USED)" >&2
    echo "auth token=$FAKE_TOK" >&2
    for i in 1 2 3 4 5 6; do echo "huong dan $i" >&2; done
    exit 1 ;;
  silent-merge)
    # như guard-check thoát 1 mà không in gì (audit Antigravity T0002)
    [ "$merge" = 1 ] && exit 1
    exit 0 ;;
  need-fa)
    # chỉ cho commit gộp khi HEAD đã có file fa (từ chối chuỗi thiếu PR #10 trong `solve`)
    [ "$merge" = 1 ] || exit 0
    git cat-file -e HEAD:fa 2>/dev/null && exit 0
    echo "guard-check: chain without fa (HOOK-NEED""-FA)" >&2; exit 1 ;;
  guard)
    for f in $(git diff --cached --name-only HEAD 2>/dev/null); do
      case "$f" in guard-*) ;; *) continue ;; esac
      if [ "$merge" = 1 ] && [ "$(git rev-parse ":$f" 2>/dev/null)" = "$(git rev-parse "MERGE_HEAD:$f" 2>/dev/null)" ]; then continue; fi
      echo "guard-check: $f thieu trailer Bug: (GUARD-BLOCK""ED)" >&2; exit 1
    done ;;
esac
exit 0
SH
chmod +x "$TMP/hooks/commit-msg"
git -C "$R" config core.hooksPath "$TMP/hooks"

# card_branch <N> <file> [nội dung]: nhánh issue-<N>-x thêm file <file> (commit có trailer Bug:), đã đẩy lên origin; metadata cho gh giả.
card_branch() {
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$1-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$1-build" "issue-$1-x"
  echo "${3:-$1}" > "$W/issue-$1-build/$2"
  git -C "$W/issue-$1-build" add "$2"; git -C "$W/issue-$1-build" commit -qm "card $1" -m "Bug: T-$1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  git -C "$R" diff "origin/main" "issue-$1-x" > "$TMP/pr$1.diff"
  printf '{"files":[{"path":"%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$2" > "$TMP/pr$1.meta"
}
# main_moves <file> [nội dung]: main của origin đi tiếp một commit (không đụng file guard) — nhánh PR đã rẽ ra trở thành chậm hơn base.
main_moves() {
  git -C "$R" fetch -q origin; git -C "$R" worktree add -q --detach "$W/adv" origin/main
  echo "${2:-adv}" > "$W/adv/$1"; git -C "$W/adv" add "$1"; git -C "$W/adv" commit -qm "main moves: $1"; git -C "$W/adv" push -q origin HEAD:main
  git -C "$R" worktree remove --force "$W/adv"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
# gh giả: trạng thái PR từ $FAKE_DIR/pr<N>.*; `pr merge` mô phỏng squash (commit-tree trên origin, không chạy hook như GitHub).
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
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
# Train chạy từ bản bin liên kết để thay gate bằng shim: shim tự trả lời --preflight, mọi lời gọi khác exec gate thật.
mkdir -p "$TMP/sbbin"
for f in "$ROOT"/.claude/bin/*; do ln -s "$f" "$TMP/sbbin/$(basename "$f")"; done
rm -f "$TMP/sbbin/super-board-merge-gate.sh"
cat > "$TMP/sbbin/super-board-merge-gate.sh" <<SH
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = --preflight ] && { echo "preflight: ok"; exit 0; }; done
exec bash "$ROOT/.claude/bin/super-board-merge-gate.sh" "\$@"
SH
chmod +x "$TMP/sbbin/super-board-merge-gate.sh"
TRAIN="$TMP/sbbin/super-board-merge-train.sh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_CALLER SB_MERGE_QUEUE
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo x >> %s/verify.count"]}\n' "$TMP" > "$CFG"
runs() { if [ -f "$TMP/verify.count" ]; then wc -l < "$TMP/verify.count" | tr -d ' '; else echo 0; fi; }
reset_run() { rm -f "$TMP/verify.count" "$TMP/merged" "$TMP/hook.calls"; }
merged_list() { sort "$TMP/merged" 2>/dev/null | tr '\n' ' '; }
git -C "$R" worktree add -q --detach "$W/review" origin/main
train() {  # train <log-prefix> <prs> [config]: stdout → <prefix>.out, stderr → <prefix>.err, $RC
  RC=0; ( cd "$W/review" && bash "$TRAIN" --config "${3:-$CFG}" --prs "$2" ) >"$TMP/$1.out" 2>"$TMP/$1.err" || RC=$?
}
# Token giả ghép lúc chạy (không có nguyên văn trong file: bộ quét secret đọc diff); hook refuse-merge in nó ra stderr.
FAKE_TOK="gh""p_$(printf 'Q%.0s' $(seq 1 30))"; export FAKE_TOK

# ── A. AC #740: hai PR cùng chứa main, mỗi PR đụng một file guard khác nhau, repo có hook guard-check (đã sửa): cả hai merged,
#    verify một lần, và hook THẬT SỰ chạy trên commit gộp của chuỗi (không tắt hook).
echo guard > "$TMP/hook.mode"
card_branch 1 guard-a; card_branch 2 guard-b
reset_run; train a 1,2
[ "$RC" -eq 0 ] && [ "$(merged_list)" = "1 2 " ] && ok "guard hook, 2 PRs on different guarded files: both merged (exit 0)" \
  || fail "guard hook 2 PRs: exit $RC merged=$(merged_list): $(grep train- "$TMP/a.out") $(tail -4 "$TMP/a.err")"
[ "$(runs)" = 1 ] && ok "  … one verify for the batch" || fail "  … verify ran $(runs) times"
# Dòng của chính chuỗi train (thư mục .train-scratch-), không phải lượt merge của gate (.merge-scratch-): review Claude P3.
grep -q "merge=1 mode=guard dir=.*/\.train-scratch-" "$TMP/hook.calls" 2>/dev/null && ok "  … the commit-msg hook ran on the train chain's merge commit (hooks not bypassed)" \
  || fail "  … the hook never ran on a merge commit: $(cat "$TMP/hook.calls" 2>/dev/null)"

# ── B. AC #740: PR chưa chứa main mới nhất nhưng merge sạch vào base: dựng được chuỗi và verify, không conflict / deferred.
card_branch 3 guard-c; main_moves m1
reset_run; train b 3
[ "$RC" -eq 0 ] && [ "$(merged_list)" = "3 " ] && grep -q "^train-result: 3 merged$" "$TMP/b.out" \
  && ok "guard hook, PR behind base: chain built, verified, merged" || fail "behind base: exit $RC merged=$(merged_list): $(grep train- "$TMP/b.out") $(tail -4 "$TMP/b.err")"
[ "$(runs)" = 1 ] && ok "  … verified once" || fail "  … verify ran $(runs) times"

# ── C1. AC #775: hook từ chối commit gộp của PR chậm hơn base (không có file xung đột): không `conflict`; kết quả gate-exit-5, lời hook
#    (dòng lý do ĐẦU) ở train-detail và ở log; exit 5; không verify, không merge.
echo refuse-merge > "$TMP/hook.mode"
card_branch 4 f4; main_moves m2
reset_run; train c1 4
[ "$RC" -eq 5 ] && ok "hook refuses the merge commit: train exit 5" || fail "hook refusal: exit $RC (want 5): $(tail -4 "$TMP/c1.err")"
grep -q "^train-result: 4 conflict$" "$TMP/c1.out" && fail "hook refusal reported as conflict (no file conflicts)" || ok "  … not reported as conflict"
grep -q "^train-result: 4 gate-exit-5$" "$TMP/c1.out" && ok "  … train-result: 4 gate-exit-5 (what the merge gate exits here)" \
  || fail "  … result: $(grep train-result "$TMP/c1.out")"
grep -q "^train-detail: 4 merge-refused: .*HOOK-REFUSED" "$TMP/c1.out" && ok "  … the hook's reason line is a train-detail of #4" \
  || fail "  … no hook reason in train-detail: $(grep train-detail "$TMP/c1.out")"
grep -q "HOOK-REFUSED" "$TMP/c1.err" && ok "  … and in the train log" || fail "  … hook reason missing from the log: $(tail -4 "$TMP/c1.err")"
grep -q "Not committing merge" "$TMP/c1.out" && fail "  … git's 'Not committing merge' line leaked into train-detail" || ok "  … git's own 'Not committing merge' line dropped"
[ "$(runs)" = 0 ] && [ -z "$(merged_list)" ] && ok "  … nothing verified or merged" || fail "  … runs=$(runs) merged=$(merged_list)"
# Lời hook là dữ liệu tuỳ ý: token trong đó bị che ở CẢ train-detail (comment issue công khai) lẫn log của train (manifest run).
if grep -q "$FAKE_TOK" "$TMP/c1.out" "$TMP/c1.err"; then fail "  … a token printed by the hook reached the train output/log"
else ok "  … a token printed by the hook is redacted in train-detail and in the log"; fi

# ── C3. Hook từ chối mà KHÔNG in gì: vẫn có dòng `train-detail: N merge-refused: …` để queue ghi "merge refused" (audit Antigravity).
echo silent-merge > "$TMP/hook.mode"
card_branch 13 f13; main_moves m3
reset_run; train c3 13
grep -q "^train-result: 13 gate-exit-5$" "$TMP/c3.out" && grep -q "^train-detail: 13 merge-refused: " "$TMP/c3.out" \
  && ok "silent hook refusal: gate-exit-5 with a merge-refused detail line" || fail "silent hook refusal: $(grep train- "$TMP/c3.out" | tr '\n' ';')"
echo refuse-merge > "$TMP/hook.mode"

# ── C2. AC #775: hai PR cùng chứa main; #6 chỉ bị hook từ chối khi gộp vào chuỗi sau #5 (một mình fast-forward): deferred như cũ,
#    nhưng log ghi lời hook; #5 vẫn merge.
card_branch 5 f5; card_branch 6 f6
reset_run; train c2 5,6
grep -q "^train-result: 5 merged$" "$TMP/c2.out" && grep -q "^train-result: 6 deferred$" "$TMP/c2.out" \
  && ok "hook refuses only the chain merge: #5 merged, #6 deferred" || fail "chain refusal: $(grep train- "$TMP/c2.out") $(tail -4 "$TMP/c2.err")"
grep -q "#6.*HOOK-REFUSED\|HOOK-REFUSED.*#6" "$TMP/c2.err" && ok "  … the log says why #6 left the chain (the hook's reason)" \
  || fail "  … no reason for #6 in the log: $(grep -i '#6' "$TMP/c2.err" | tail -3)"
[ "$RC" -eq 0 ] && ok "  … train exit 0" || fail "  … exit $RC"

# ── E. Hook từ chối trong `solve` (OCR): chuỗi ứng viên 10+11+12 dựng được (hook chỉ cho commit gộp khi HEAD có fa của #10); #10 đỏ
#    (verify đỏ khi có fa) nên chia đôi dựng 11+12 thiếu fa ⇒ hook từ chối #12 trong chuỗi. #12 một mình fast-forward ⇒ deferred, đúng
#    MỘT train-result (không thêm `timeout`), không gate-exit-5; #11 merged, #10 red, exit 11.
echo need-fa > "$TMP/hook.mode"
card_branch 10 fa; card_branch 11 f11; card_branch 12 f12
CFG_E="$TMP/cfg-e.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo x >> %s/verify.count; test ! -e fa"]}\n' "$TMP" > "$CFG_E"
reset_run; train e 10,11,12 "$CFG_E"
[ "$(grep -c '^train-result: 12 ' "$TMP/e.out")" = 1 ] && grep -q "^train-result: 12 deferred$" "$TMP/e.out" \
  && ok "refusal inside solve: #12 deferred, exactly one train-result" || fail "refusal inside solve: $(grep train-result "$TMP/e.out" | tr '\n' ';') $(tail -3 "$TMP/e.err")"
grep -q "^train-result: 11 merged$" "$TMP/e.out" && grep -q "^train-result: 10 red$" "$TMP/e.out" && [ "$RC" -eq 11 ] \
  && ok "  … #11 merged, #10 red, exit 11" || fail "  … exit $RC: $(grep train-result "$TMP/e.out" | tr '\n' ';')"

# ── D. Xung đột thật (không hook): vẫn `conflict`, exit 5, log ghi tên file xung đột.
rm -f "$TMP/hook.mode"
card_branch 7 shared pr7; main_moves shared main
reset_run; train d 7
[ "$RC" -eq 5 ] && grep -q "^train-result: 7 conflict$" "$TMP/d.out" && ok "real conflict: conflict, exit 5" \
  || fail "real conflict: exit $RC: $(grep train- "$TMP/d.out")"
grep -q "#7.*shared" "$TMP/d.err" && ok "  … the log names the conflicting file" || fail "  … conflicting file not named: $(tail -4 "$TMP/d.err")"
grep -q "^train-detail: 7 " "$TMP/d.out" && fail "  … a conflict got hook train-detail lines" || ok "  … no hook detail for a real conflict"
# Xung đột chỉ với PR đứng trước: deferred như cũ, log ghi tên file.
card_branch 8 shared2 pr8; card_branch 9 shared2 pr9
reset_run; train d2 8,9
grep -q "^train-result: 9 deferred$" "$TMP/d2.out" && grep -q "#9.*shared2" "$TMP/d2.err" \
  && ok "chain-only conflict: #9 deferred, the log names the file" || fail "chain-only conflict: $(grep train- "$TMP/d2.out") $(grep '#9' "$TMP/d2.err" | tail -2)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_train_hook_refusal: PASS"; exit 0; } || { echo "test_merge_train_hook_refusal: FAIL ($FAILS)"; exit 1; }
