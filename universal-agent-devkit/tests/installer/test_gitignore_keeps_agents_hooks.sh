#!/usr/bin/env bash
# Kiểm thử hồi quy K7 (đo thật 17/10): mỗi worktree mới do `agent-kit worktree add` / hook WorktreeCreate dựng đều chạy
# bin/install.sh, và install.sh viết lại cả khối `universal-agent-devkit:start/end` trong .gitignore từ heredoc của nó.
# Heredoc thiếu dòng `.agents/hooks/` (repo tự thêm dòng đó vào khối ở 4a344d6), nên mỗi lần cài dòng đó bị xoá: ` M .gitignore`,
# rồi 7 link `.agents/hooks/*` hiện ra là file mới và worktree_merge_gate.sh / finish từ chối gộp.
# Khẳng định: cài lại trên repo có khối giống hệt workbench HEAD thì .gitignore không đổi (kể cả thứ tự dòng),
# và các link cầu nối ở .agents/hooks/ vẫn bị ignore. bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
P="$(mktemp -d -t devkit-gi-hooks-XXXXXX)"
trap 'rm -rf "$P"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

git -C "$P" init -q .
# Khối DevKit chép nguyên văn từ .gitignore của agent-workbench HEAD, kèm dòng riêng của repo trước và sau khối.
cat > "$P/.gitignore" <<'GI'
node_modules/

# universal-agent-devkit:start
# Local DevKit install state & *_old conflict backups (review/merge them, don't commit)
.claude/audit-gate/
.agents/context/
.agents/devkit
.agents/hooks/
.agents/regression_matrix.generated.json
.devkit_backups.log
.devkit-files
*_old
*_old.*
*_old_*
# universal-agent-devkit:end

# dòng riêng của repo, phải còn nguyên
.claude/agent-memory/
GI
git -C "$P" add .gitignore
git -C "$P" -c user.name=t -c user.email=t@t commit -q -m init || fail "commit fixture failed"

# Đúng lệnh scripts/git/worktree.py init_command() chạy cho một worktree (symlink, gemini kéo theo .agents/hooks/).
bash "$DEVKIT_ROOT/bin/install.sh" --target="$P" --domain=auto --mode=symlink -y --no-githooks -p backend -a claude,gemini \
  >"$P.log" 2>&1 || { fail "install exited non-zero: $(tail -3 "$P.log")"; }
rm -f "$P.log"

[ -e "$P/.agents/hooks/agent_bridge.sh" ] && ok "install placed the bridge hooks in .agents/hooks/" \
  || fail "install did not place .agents/hooks/agent_bridge.sh (the test no longer reaches the K7 path)"
if git -C "$P" diff --quiet -- .gitignore; then
  ok "install leaves the committed .gitignore unchanged"
else
  fail "install changed .gitignore:"; git -C "$P" diff -- .gitignore | sed 's/^/    /'
fi
grep -qx '.claude/agent-memory/' "$P/.gitignore" && grep -qx 'node_modules/' "$P/.gitignore" \
  && ok "the repo's own lines outside the block are kept" || fail "a line of the repo outside the block was lost"
st="$(git -C "$P" status --porcelain --untracked-files=all -- .gitignore .agents/hooks)"
[ -z "$st" ] && ok "git status is clean for .gitignore and .agents/hooks/" || { fail "git status not clean:"; printf '%s\n' "$st" | sed 's/^/    /'; }

# Repo mới chưa có khối: lần cài đầu cũng phải ghi .agents/hooks/ vào .gitignore (không chỉ dựa vào .git/info/exclude
# của bước 6b: trong worktree đó là file chung của main, và copy mode không ghi nó).
Q="$(mktemp -d -t devkit-gi-hooks-new-XXXXXX)"
git -C "$Q" init -q .
bash "$DEVKIT_ROOT/bin/install.sh" -t "$Q" -y -p backend -a claude,gemini -m symlink >/dev/null 2>&1 || fail "fresh install exited non-zero"
grep -qx '.agents/hooks/' "$Q/.gitignore" && git -C "$Q" check-ignore -q .agents/hooks/agent_bridge.sh \
  && ok "fresh install writes .agents/hooks/ into the .gitignore block" || fail "fresh install does not list .agents/hooks/ in .gitignore"
rm -rf "$Q"

if [ $FAILS -gt 0 ]; then echo "FAILED: $FAILS errors"; exit 1; fi
echo "ALL TESTS PASSED"
