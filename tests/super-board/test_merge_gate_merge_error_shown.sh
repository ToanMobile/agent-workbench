#!/usr/bin/env bash
# 01/11 (GeelyEx2 PR #179): merge gate gộp base vào scratch bằng `git merge … 2>/dev/null`. Hook commit-msg của repo (guard-check.py)
# từ chối commit gộp, `git merge` thất bại mà không có file xung đột nào, và gate chỉ in "conflicts: " rỗng: người đọc không biết vì sao.
# Luật: `git merge` thất bại mà không có file xung đột thì gate in stderr thật của git (lời từ chối của hook), không in "conflicts:" rỗng
# và không bảo rebase; xung đột thật vẫn in tên file xung đột. Mã thoát 5 giữ nguyên (hợp đồng với lane/train). Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mergeerr-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/heavy-slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/deploy-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
mkdir -p "$R/.claude/super-board/configs" && echo '{}' > "$R/.claude/super-board/configs/x.json"
echo a > "$R/a"; echo s > "$R/shared"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" branch -q --no-track issue-6-x main
git -C "$R" worktree add -q "$WT" issue-5-x
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm card5
git -C "$R" push -q origin issue-5-x
# PR 6: sửa cùng dòng với main ⇒ xung đột nội dung thật
git -C "$WT" checkout -q issue-6-x; echo pr6 > "$WT/shared"; git -C "$WT" commit -qam card6
git -C "$R" push -q origin issue-6-x
git -C "$WT" checkout -q issue-5-x
for n in 5 6; do
  git -C "$R" rev-parse "issue-$n-x" > "$TMP/pr$n.head"
  git -C "$R" diff origin/main "issue-$n-x" > "$TMP/pr$n.diff"
done
printf '{"files":[{"path":"b"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr5.meta"
printf '{"files":[{"path":"shared"}],"labels":[],"body":"","additions":1,"deletions":1,"changedFiles":1}' > "$TMP/pr6.meta"
# main tiến: nhánh PR chậm hơn base, gate phải tạo commit gộp trong scratch
git -C "$R" checkout -q main; echo c > "$R/c"; echo main > "$R/shared"; git -C "$R" add c shared; git -C "$R" commit -qm main-moves
git -C "$R" push -q origin main
# Hook commit-msg của repo (dùng chung cho mọi worktree) từ chối commit gộp, như guard-check.py của GeelyEx2
mkdir -p "$R/.git/hooks"
printf '#!/bin/sh\necho "guard-check: thieu trailer Bug: <id> (HOOK-REJ""ECTED)" >&2\nexit 1\n' > "$R/.git/hooks/commit-msg"
chmod +x "$R/.git/hooks/commit-msg"

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
  *" pr merge "*) echo "fake gh: must not merge" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo ran; exit 0"]}' > "$CFG"

# 1) hook từ chối commit gộp: không có file xung đột
( cd "$WT" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$(cat "$TMP/pr5.head")" --dry-run ) >"$TMP/hook.log" 2>&1; rc=$?
[ "$rc" -eq 5 ] && ok "git merge thất bại: exit 5 như cũ" || fail "gate exit $rc (want 5): $(tail -3 "$TMP/hook.log")"
grep -q "HOOK-REJECTED" "$TMP/hook.log" && ok "gate in stderr thật của git merge (lời từ chối của hook)" \
  || fail "gate nuốt stderr của git merge: $(grep 'merge-gate' "$TMP/hook.log" | tail -3)"
grep -qE "conflicts: *$" "$TMP/hook.log" && fail "gate vẫn in 'conflicts:' rỗng" || ok "không in 'conflicts:' rỗng"
grep -q "this is a rebase pass" "$TMP/hook.log" && fail "gate bảo rebase dù không có xung đột" || ok "không bảo rebase khi không có xung đột"

# 2) xung đột thật: vẫn in tên file xung đột và bảo rebase
rm -f "$R/.git/hooks/commit-msg"
( cd "$WT" && bash "$GATE" --config "$CFG" --pr 6 --expect-head "$(cat "$TMP/pr6.head")" --dry-run ) >"$TMP/conf.log" 2>&1; rc=$?
[ "$rc" -eq 5 ] && grep -q "conflicts: shared" "$TMP/conf.log" && grep -q "this is a rebase pass" "$TMP/conf.log" \
  && ok "xung đột thật: exit 5, in 'conflicts: shared' và bảo rebase" \
  || fail "xung đột thật: gate exit $rc: $(grep 'merge-gate' "$TMP/conf.log" | tail -3)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_merge_error_shown: PASS"; exit 0; } || { echo "test_merge_gate_merge_error_shown: FAIL ($FAILS)"; exit 1; }
