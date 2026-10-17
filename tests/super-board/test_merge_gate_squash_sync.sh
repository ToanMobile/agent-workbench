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
                    && tree=$(git -C "$FAKE_REPO" rev-parse "$head^{tree}") \
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
gate() { ( cd "$R" && bash "$GATE" --config "$CFG" --pr "$1" --expect-head "$(cat "$TMP/pr$1.head")" ) >"$TMP/gate$1.log" 2>&1; }

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
rm -f "$R/dirty.txt"

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
grep -q "merge is in progress" "$TMP/gate9.log" && ok "3: the warning says a merge is in progress" || fail "3: no warning about the merge in progress"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_gate_squash_sync: all passed" || { echo "❌ test_merge_gate_squash_sync: $FAILS failed"; exit 1; }
