#!/usr/bin/env bash
# Test hồi quy cho bước đồng bộ base local sau merge của .claude/bin/super-board-merge-gate.sh, chạy offline với `gh` giả.
# 2026-10-17: gate merge bằng `gh pr merge --squash`, còn trunk mode đã đưa chính các commit của PR vào main local
# (worktree finish) và phiên khác còn đẩy thêm commit local: sau squash origin/main có một commit MỚI (cùng nội dung,
# khác sha), main local và origin/main lệch nhau, `merge --ff-only` thất bại mãi ("local base is stale") và người dùng
# phải đồng bộ tay sau mỗi PR. Khi ff không được, gate phải merge origin/<base> vào main checkout (như
# `git pull --no-rebase` của luật push) mà KHÔNG làm mất commit local; xung đột hoặc sửa chưa commit chồng lên thì
# để nguyên main (không để lại MERGE_HEAD) và vẫn báo cảnh báo.
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

# card <N> <file> <content>: nhánh issue-<N>-x có một commit ghi <file>, đã push; main local ff tới đó (như worktree finish).
card() {
  git -C "$R" fetch -q origin
  git -C "$R" checkout -q -b "issue-$1-x" origin/main
  printf '%s\n' "$3" > "$R/$2"; git -C "$R" add "$2"; git -C "$R" commit -qm "card $1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  git -C "$R" diff "origin/main" "issue-$1-x" > "$TMP/pr$1.diff"
  printf '{"files":[{"path":"%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$2" > "$TMP/pr$1.meta"
  git -C "$R" checkout -q main
  git -C "$R" merge -q --ff-only "issue-$1-x"
}

# ── 1. main local = commit của PR + một commit local khác (phiên khác); squash làm hai bên lệch nhau.
card 7 b seven
echo local > "$R/l"; git -C "$R" add l; git -C "$R" commit -qm "local only"
LOCAL_BEFORE=$(git -C "$R" rev-parse main); H7=$(cat "$TMP/pr7.head")
( cd "$R" && bash "$GATE" --config "$CFG" --pr 7 --expect-head "$H7" ) >"$TMP/gate7.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "gate: squash merge succeeded (exit 0)" || fail "gate exit $rc: $(tail -5 "$TMP/gate7.log")"
git -C "$R" merge-base --is-ancestor origin/main main && ok "main local now contains origin/main (squash commit)" \
  || fail "main local does not contain origin/main: still diverged ($(git -C "$R" rev-list --left-right --count main...origin/main | tr '\t' ' '))"
git -C "$R" merge-base --is-ancestor "$LOCAL_BEFORE" main && ok "no local commit lost: the old main tip is still in main" \
  || fail "the old local main tip $LOCAL_BEFORE is gone from main"
[ -f "$R/l" ] && [ -f "$R/b" ] && ok "tree has the PR's file and the local-only file" || fail "tree lost a file (l: $([ -f "$R/l" ] && echo y || echo n), b: $([ -f "$R/b" ] && echo y || echo n))"
! grep -q "local base is stale" "$TMP/gate7.log" && ok "no stale-base warning once main is synced" || fail "stale-base warning although the merge synced main: $(grep 'stale' "$TMP/gate7.log")"
[ ! -e "$R/.git/MERGE_HEAD" ] && ok "no merge left open" || fail "MERGE_HEAD left in the main checkout"

# ── 2. un conflict: main local sửa cùng file khác nội dung → để nguyên main, không để MERGE_HEAD, vẫn cảnh báo.
card 8 c eight
echo different > "$R/c"; git -C "$R" add c; git -C "$R" commit -qm "local edit of c"
BEFORE2=$(git -C "$R" rev-parse main); H8=$(cat "$TMP/pr8.head")
( cd "$R" && bash "$GATE" --config "$CFG" --pr 8 --expect-head "$H8" ) >"$TMP/gate8.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "conflicting local edit: the PR still merged (exit 0)" || fail "gate exit $rc: $(tail -5 "$TMP/gate8.log")"
[ "$(git -C "$R" rev-parse main)" = "$BEFORE2" ] && ok "conflict: main left exactly where it was" || fail "conflict moved main from $BEFORE2"
[ ! -e "$R/.git/MERGE_HEAD" ] && [ -z "$(git -C "$R" status --porcelain --untracked-files=no)" ] && ok "conflict: no MERGE_HEAD and a clean tree" \
  || fail "conflict left merge state or dirt: $(git -C "$R" status --porcelain | head -3)"
grep -q "local base is stale" "$TMP/gate8.log" && ok "conflict: the stale-base warning is still printed" || fail "conflict: no warning, the stale base is hidden"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_gate_squash_sync: all passed" || { echo "❌ test_merge_gate_squash_sync: $FAILS failed"; exit 1; }
