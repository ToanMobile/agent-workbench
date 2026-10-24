#!/usr/bin/env bash
# Test hồi quy cho bước đồng bộ base local sau merge của .claude/bin/super-board-merge-gate.sh, chạy offline với `gh` giả.
# 2026-10-17: gate merge bằng `gh pr merge --squash`, còn trunk mode đã đưa chính các commit của PR vào main local
# (worktree finish): sau squash origin/main có một commit MỚI (cùng nội dung, khác sha), main local và origin/main lệch
# nhau, `merge --ff-only` thất bại mãi ("local base is stale") và người dùng phải đồng bộ tay sau mỗi PR.
#   1 base local chỉ giữ commit của PR (cây giống origin sau squash): dời về origin/<base> bằng `reset --keep` (không merge
#     commit: luật "main chỉ ff"), không còn cảnh báo
#   2 base local còn commit riêng chưa đẩy (việc của phiên khác): để nguyên đúng sha, vẫn cảnh báo, không mất commit
#   3 main đang dở một merge của phiên khác với phần xung đột đã giải tay + stage: gate không đụng (MERGE_HEAD và phần giải
#     tay còn nguyên; review 17/10: `merge --abort` vô điều kiện huỷ cả chúng)
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-squash-sync.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main
# gh giả dựng cây squash bằng `merge-tree --write-tree` (git >= 2.38): git cũ hơn thì bỏ qua cả file, có thông báo.
git -C "$R" merge-tree --write-tree HEAD HEAD >/dev/null 2>&1 || { echo "skip: git < 2.38 has no merge-tree --write-tree"; exit 0; }

# gh giả: `pr merge` mô phỏng SQUASH: origin/main nhận một commit mới cùng tree với head, cha là origin/main.
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
  *" pr merge "*) git -C "$FAKE_REPO" fetch -q origin main \
                    && tree=$(git -C "$FAKE_REPO" merge-tree --write-tree origin/main "$head") \
                    && sq=$(git -C "$FAKE_REPO" commit-tree "$tree" -p origin/main -m "squash #$n") \
                    && git -C "$FAKE_REPO" push -q origin "$sq:refs/heads/main" && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["true"]}' > "$CFG"

# branch <N> <file> <content>: nhánh issue-<N>-x có một commit ghi <file>, đã push, gh giả biết nó. main local chưa đổi.
branch() {
  git -C "$R" fetch -q origin
  git -C "$R" checkout -q -b "issue-$1-x" origin/main
  printf '%s\n' "$3" > "$R/$2"; git -C "$R" add "$2"; git -C "$R" commit -qm "card $1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  git -C "$R" diff "origin/main" "issue-$1-x" > "$TMP/pr$1.diff"
  printf '{"files":[{"path":"%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$2" > "$TMP/pr$1.meta"
  git -C "$R" checkout -q main
}
land() { git -C "$R" merge -q --ff-only "issue-$1-x"; }   # trunk mode: worktree finish đã ff các commit của PR vào main local
# Reviewer chạy gate từ worktree liên kết của nó (cwd khác main checkout, repo.path "."): mọi ca chạy từ đó.
git -C "$R" worktree add -q --detach "$TMP/lw" main
gate() { ( cd "$TMP/lw" && bash "$GATE" --config "$CFG" --pr "$1" --expect-head "$(cat "$TMP/pr$1.head")" ) >"$TMP/gate$1.log" 2>&1; }

# ── 1. main local chỉ giữ commit của PR: sau squash cây giống hệt origin/main.
branch 7 b seven; land 7
echo wip > "$R/dirty.txt"                       # sửa chưa commit của phiên khác (file không bị đụng)
gate 7; rc=$?
[ "$rc" -eq 0 ] && ok "1: gate squash merge succeeded (exit 0)" || fail "1: gate exit $rc: $(tail -5 "$TMP/gate7.log")"
[ "$(git -C "$R" rev-parse main)" = "$(git -C "$R" rev-parse origin/main)" ] && ok "1: main local moved to origin/main (same tree, no merge commit)" \
  || fail "1: main $(git -C "$R" rev-parse --short main) != origin/main $(git -C "$R" rev-parse --short origin/main)"
[ "$(git -C "$R" rev-list --merges --count origin/main..main)" = 0 ] && ok "1: no merge commit made on main (AGENTS §7.1: main only fast-forwards)" || fail "1: a merge commit on main"
[ "$(cat "$R/dirty.txt" 2>/dev/null)" = wip ] && ok "1: another session's uncommitted file kept" || fail "1: uncommitted file lost"
! grep -q "local base is stale" "$TMP/gate7.log" && ok "1: no stale-base warning" || fail "1: warning although main was synced: $(grep stale "$TMP/gate7.log")"
grep -q "moved to origin/main" "$TMP/gate7.log" && ok "1: the note says main was moved to origin/main" || fail "1: no 'moved to origin/main' note"
rm -f "$R/dirty.txt"

# ── 1c. như 1 nhưng phiên khác SỬA (chưa stage) một file đã theo dõi mà squash không đổi: `reset --keep` giữ nguyên sửa đổi đó.
branch 14 i fourteen; land 14
echo "tracked edit" >> "$R/a"
gate 14; rc=$?
[ "$rc" -eq 0 ] && ok "1c: the PR still merged (exit 0)" || fail "1c: gate exit $rc: $(tail -5 "$TMP/gate14.log")"
[ "$(git -C "$R" rev-parse main)" = "$(git -C "$R" rev-parse origin/main)" ] && grep -q "tracked edit" "$R/a" \
  && ok "1c: main caught up and another session's unstaged edit of a tracked file is kept" \
  || fail "1c: main $(git -C "$R" rev-parse --short main) vs origin $(git -C "$R" rev-parse --short origin/main), a: $(tail -1 "$R/a")"
git -C "$R" checkout -q -- a

# ── 1d. origin nhận thêm một commit đổi CHÍNH file `a` mà phiên khác đang sửa dở: `reset --keep` từ chối, main để nguyên + cảnh báo.
branch 15 j fifteen; land 15
git -C "$R" checkout -q -b unrelated-a origin/main; echo "origin change" >> "$R/a"; git -C "$R" commit -qam "origin edits a"
git -C "$R" push -q origin unrelated-a:refs/heads/main; git -C "$R" checkout -q main; git -C "$R" fetch -q origin
echo "my wip" >> "$R/a"
BEFORE1D=$(git -C "$R" rev-parse main)
gate 15; rc=$?
[ "$rc" -eq 0 ] && ok "1d: the PR still merged (exit 0)" || fail "1d: gate exit $rc: $(tail -5 "$TMP/gate15.log")"
[ "$(git -C "$R" rev-parse main)" = "$BEFORE1D" ] && grep -q "my wip" "$R/a" && ok "1d: main not moved and the unfinished edit is intact" \
  || fail "1d: main moved or the edit was lost: $(tail -2 "$R/a" | tr '\n' ';')"
grep -q "refused too" "$TMP/gate15.log" && ok "1d: the warning says the reset was refused" || fail "1d: no 'refused too' warning: $(grep warning "$TMP/gate15.log" | cut -c1-200)"
git -C "$R" checkout -q -- a; git -C "$R" fetch -q origin; git -C "$R" reset -q --hard origin/main

# ── 1b. như 1 nhưng phiên khác đã STAGE một file trong main: `reset --keep` đặt lại cả index (file rơi thành untracked, OCR 17/10),
#    nên gate không dời, để nguyên main + file đã stage, và cảnh báo.
branch 13 h thirteen; land 13
echo staged > "$R/staged.txt"; git -C "$R" add staged.txt
BEFORE1B=$(git -C "$R" rev-parse main)
gate 13; rc=$?
[ "$rc" -eq 0 ] && ok "1b: the PR still merged (exit 0)" || fail "1b: gate exit $rc: $(tail -5 "$TMP/gate13.log")"
git -C "$R" diff --cached --name-only | grep -qx staged.txt && [ "$(git -C "$R" rev-parse main)" = "$BEFORE1B" ] \
  && ok "1b: another session's staged file survives in the index, main not moved" \
  || fail "1b: staged file dropped or main moved: $(git -C "$R" status --short | tr '\n' ';')"
grep -q "staged changes" "$TMP/gate13.log" && ok "1b: the warning says why main was left alone" || fail "1b: no warning about the staged changes"
git -C "$R" rm -q --cached -f staged.txt >/dev/null 2>&1; rm -f "$R/staged.txt"; git -C "$R" fetch -q origin; git -C "$R" reset -q --hard origin/main

# ── 2. main local = commit del PR + một commit riêng chưa đẩy: không được mất, để nguyên và cảnh báo.
branch 8 c eight; land 8
echo local > "$R/l"; git -C "$R" add l; git -C "$R" commit -qm "local only"
BEFORE2=$(git -C "$R" rev-parse main)
gate 8; rc=$?
[ "$rc" -eq 0 ] && ok "2: the PR still merged (exit 0)" || fail "2: gate exit $rc: $(tail -5 "$TMP/gate8.log")"
[ "$(git -C "$R" rev-parse main)" = "$BEFORE2" ] && ok "2: local-only commit kept: main left exactly where it was" || fail "2: main moved from $BEFORE2"
grep -q "local base is stale" "$TMP/gate8.log" && ok "2: the stale-base warning is printed" || fail "2: no warning, the stale base is hidden"
[ ! -e "$R/.git/MERGE_HEAD" ] && ok "2: no merge state left" || fail "2: MERGE_HEAD left"
git -C "$R" reset -q --hard "$BEFORE2"; git -C "$R" fetch -q origin

# ── 3. main đang dở merge của phiên khác, xung đột đã giải tay và stage.
branch 9 d nine
git -C "$R" checkout -q -b other-x origin/main; echo theirs > "$R/a"; git -C "$R" commit -qam "other a"; git -C "$R" checkout -q main
echo mine > "$R/a"; git -C "$R" commit -qam "main a"
git -C "$R" merge other-x >/dev/null 2>&1                 # conflict on a: merge left open
echo "RESOLVED BY HAND" > "$R/a"; git -C "$R" add a
[ -e "$R/.git/MERGE_HEAD" ] || fail "3: fixture: no merge in progress"
BEFORE3=$(git -C "$R" rev-parse main)
gate 9; rc=$?
[ "$rc" -eq 0 ] && ok "3: the PR still merged (exit 0)" || fail "3: gate exit $rc: $(tail -5 "$TMP/gate9.log")"
[ -e "$R/.git/MERGE_HEAD" ] && [ "$(cat "$R/a")" = "RESOLVED BY HAND" ] && ok "3: the other session's merge and its hand resolution survive" \
  || fail "3: gate destroyed the merge in progress (MERGE_HEAD: $([ -e "$R/.git/MERGE_HEAD" ] && echo kept || echo gone), a: $(cat "$R/a"))"
[ "$(git -C "$R" rev-parse main)" = "$BEFORE3" ] && ok "3: main not moved" || fail "3: main moved"
grep -q "MERGE_HEAD in progress" "$TMP/gate9.log" && ok "3: the warning says a merge is in progress" || fail "3: no warning about the merge in progress"

# ── 3b. main = commit del PR + một merge --no-commit KHÔNG xung đột của phiên khác: cây HEAD vẫn bằng origin sau squash, nên
#    `reset --keep` sẽ chạy và xoá MERGE_HEAD nếu gate không nhận ra merge đang dở (gate chạy từ worktree liên kết: cwd khác main).
git -C "$R" merge -q --abort >/dev/null 2>&1; git -C "$R" fetch -q origin; git -C "$R" reset -q --hard origin/main
branch 12 g twelve; land 12
git -C "$R" checkout -q -b side-x origin/main; echo s > "$R/s"; git -C "$R" add s; git -C "$R" commit -qm "side"; git -C "$R" checkout -q main
git -C "$R" merge --no-commit --no-ff side-x >/dev/null 2>&1
[ -e "$R/.git/MERGE_HEAD" ] || fail "3b: fixture: no clean merge in progress"
BEFORE3B=$(git -C "$R" rev-parse main)
gate 12; rc=$?
[ "$rc" -eq 0 ] && ok "3b: the PR still merged (exit 0)" || fail "3b: gate exit $rc: $(tail -5 "$TMP/gate12.log")"
[ -e "$R/.git/MERGE_HEAD" ] && [ -f "$R/s" ] && [ "$(git -C "$R" rev-parse main)" = "$BEFORE3B" ] && ok "3b: a clean --no-commit merge of another session survives the gate run from a linked worktree" \
  || fail "3b: gate destroyed the merge in progress (MERGE_HEAD: $([ -e "$R/.git/MERGE_HEAD" ] && echo kept || echo gone), s: $([ -f "$R/s" ] && echo kept || echo gone))"
git -C "$R" merge --abort >/dev/null 2>&1

# ── 4. main đang dở cherry-pick (CHERRY_PICK_HEAD): `reset --keep` sẽ xoá nó, nên gate không được đụng.
git -C "$R" merge --abort >/dev/null 2>&1; git -C "$R" reset -q --hard "$BEFORE3"; git -C "$R" fetch -q origin
git -C "$R" reset -q --hard origin/main
branch 10 e ten
git -C "$R" checkout -q -b pick-x origin/main; echo picked > "$R/a"; git -C "$R" commit -qam "pick a"; git -C "$R" checkout -q main
echo mainv2 > "$R/a"; git -C "$R" commit -qam "main a v2"
git -C "$R" cherry-pick pick-x >/dev/null 2>&1
[ -e "$R/.git/CHERRY_PICK_HEAD" ] || fail "4: fixture: no cherry-pick in progress"
BEFORE4=$(git -C "$R" rev-parse main)
gate 10; rc=$?
[ "$rc" -eq 0 ] && ok "4: the PR still merged (exit 0)" || fail "4: gate exit $rc: $(tail -5 "$TMP/gate10.log")"
[ -e "$R/.git/CHERRY_PICK_HEAD" ] && [ "$(git -C "$R" rev-parse main)" = "$BEFORE4" ] && ok "4: the other session's cherry-pick in progress survives, main not moved" \
  || fail "4: gate destroyed the cherry-pick in progress (CHERRY_PICK_HEAD: $([ -e "$R/.git/CHERRY_PICK_HEAD" ] && echo kept || echo gone))"
grep -q "CHERRY_PICK_HEAD" "$TMP/gate10.log" && ok "4: the warning names the cherry-pick" || fail "4: no warning naming CHERRY_PICK_HEAD"
git -C "$R" cherry-pick --abort >/dev/null 2>&1; git -C "$R" reset -q --hard origin/main

# ── 5. origin nhận thêm một commit KHÁC (PR khác) trước khi squash: base local chỉ giữ commit của PR này, vẫn phải bắt kịp.
branch 11 f eleven; land 11
git -C "$R" checkout -q -b unrelated origin/main; echo u > "$R/u"; git -C "$R" add u; git -C "$R" commit -qm "unrelated PR"
git -C "$R" push -q origin unrelated:refs/heads/main; git -C "$R" checkout -q main; git -C "$R" fetch -q origin
gate 11; rc=$?
[ "$rc" -eq 0 ] && ok "5: the PR still merged (exit 0)" || fail "5: gate exit $rc: $(tail -5 "$TMP/gate11.log")"
[ "$(git -C "$R" rev-parse main)" = "$(git -C "$R" rev-parse origin/main)" ] && ok "5: origin got another PR first: main still caught up with origin/main" \
  || fail "5: main $(git -C "$R" rev-parse --short main) != origin/main $(git -C "$R" rev-parse --short origin/main)"
[ -f "$R/u" ] && [ -f "$R/f" ] && ok "5: both the other PR's file and this PR's file are in main" || fail "5: tree lost a file"

# ── 6. #358 mục 4: git 2.38-2.41 có merge-tree --write-tree nhưng không có `--attr-source` (exit 129). Như ca 5 (origin nhận PR khác trước, cây
#    main local khác cây origin nên so cây thuần không đủ) với một `git` giả tự nhận 2.41.0 và từ chối --attr-source: gate vẫn phải nhận ra
#    main local đã tích hợp và đưa nó về origin/main.
mkdir -p "$TMP/git241"
REAL_GIT="$(command -v git)"
cat > "$TMP/git241/git" <<STUB
#!/bin/sh
case "\$1" in version|--version) echo "git version 2.41.0"; exit 0 ;; esac
for a in "\$@"; do
  case "\$a" in --attr-source*) : > "$TMP/git241/attr-rejected"; echo "unknown option: \$a" >&2; exit 129 ;; esac
done
# Mô phỏng merge driver bị giết (#309): lần merge-tree thử lại sau khi --attr-source bị từ chối để lại .merge_file_* ở cwd hiệu lực của nó
# (cwd, hay đích của -C). Lệnh merge-tree khác của gate (dự đoán cây ở đầu gate) chạy trước nên không có dấu attr-rejected.
case " \$* " in *" merge-tree "*) [ -e "$TMP/git241/attr-rejected" ] || exec "$REAL_GIT" "\$@"
  d="\$PWD"; [ "\$1" = "-C" ] && d="\$2"
  : > "\$d/.merge_file_stub\$\$" ;;
esac
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$TMP/git241/git"
git -C "$R" fetch -q origin; git -C "$R" reset -q --hard origin/main
branch 16 k sixteen; land 16
git -C "$R" checkout -q -b unrelated2 origin/main; echo u2 > "$R/u2"; git -C "$R" add u2; git -C "$R" commit -qm "unrelated PR 2"
git -C "$R" push -q origin unrelated2:refs/heads/main; git -C "$R" checkout -q main; git -C "$R" fetch -q origin
( cd "$TMP/lw" && PATH="$TMP/git241:$PATH" bash "$GATE" --config "$CFG" --pr 16 --expect-head "$(cat "$TMP/pr16.head")" ) >"$TMP/gate16.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "6: the PR merged under git 2.41 (exit 0)" || fail "6: gate exit $rc: $(tail -5 "$TMP/gate16.log")"
[ "$(git -C "$R" rev-parse main)" = "$(git -C "$R" rev-parse origin/main)" ] && ok "6: git 2.41: main local, already integrated, still moved to origin/main" \
  || fail "6: git 2.41 refused an integrated main: $(grep -i warning "$TMP/gate16.log" | cut -c1-200)"
# #309: ngay cả đường lùi cho git cũ cũng không được để .merge_file_* trong checkout main của người dùng.
[ -z "$(ls -A "$R" "$R/.git" 2>/dev/null | grep '^\.merge_file_')" ] && ok "6: no .merge_file_* left in the main checkout" \
  || fail "6: merge-driver leftovers in the main checkout: $(ls -A "$R" "$R/.git" | grep '^\.merge_file_' | tr '\n' ' ')"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_gate_squash_sync: all passed" || { echo "❌ test_merge_gate_squash_sync: $FAILS failed"; exit 1; }
