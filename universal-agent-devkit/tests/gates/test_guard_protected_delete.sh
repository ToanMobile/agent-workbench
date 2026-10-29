#!/usr/bin/env bash
# hooks/block-dangerous-git.sh: luật chủ repo 28/10 (#605) — DevKit tự động hoàn toàn, chỉ hỏi người khi:
#   1. force push (--force, -f, --force-with-lease, --force-if-includes, +ref) — mục A;
#   2. xoá nhánh/tag trên remote (push --delete, -d, push origin :ref, --mirror, --prune) — mục A;
#   3. xoá file quan trọng (danh sách mặc định + khoá "protected_delete" trong .antigravity-pm.json) bằng
#      rm / unlink / git rm / find -delete / find -exec rm — mục B, D, E.
# Xoá file thường vẫn qua, không thêm lời hỏi nào (mục C). Chỉ chạy hook, không bao giờ chạy lệnh.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset DEVKIT_ALLOW_BRANCH
P="$TMP/proj"
mkdir -p "$P"
git -C "$P" init -q -b feat .
mkdir -p "$P/app" "$P/.agents/local/stage" "$P/.agents/local/memory" "$P/.agents/local/rules" "$P/node_modules/x" "$P/build" "$P/.claude/worktrees/w1" "$P/src"
touch "$P/.env" "$P/.env.local" "$P/app/google-services.json" "$P/release.keystore" "$P/upload.jks" \
      "$P/.agents/local/stage/a.txt" "$P/.agents/local/memory/m.md" "$P/.agents/local/rules/00.md" "$P/.agents/regression_matrix.active.json" "$P/build/x.log" "$P/src/a.kt"
echo "gitdir: $P/.git/worktrees/w1" > "$P/.claude/worktrees/w1/.git"

# check <want rc> <reason fragment for a block> <command> [cwd]
check() {
  local want="$1" frag="$2" c="$3" cwd="${4:-$P}"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$cwd" > "$TMP/in.json"
  ( cd "$cwd" && CLAUDE_PROJECT_DIR="$P" bash "$GG" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$? s="${c//$'\n'/ ⏎ }"
  # một lần chặn phải đúng luật này (hook crash cũng thoát 2)
  if [ "$rc" = 2 ] && [ "$want" = 2 ] && ! grep -q -- "$frag" "$TMP/err"; then rc="2 (other reason)"; fi
  if [ "$rc" = "$want" ]; then echo "✔ rc $rc: ${s:0:100}"
  else echo "✖ rc $rc (want $want): ${s:0:100} — $(head -c 200 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; FAILS=$((FAILS + 1)); fi
}

echo "A. force push / xoá ref trên remote: luôn chặn, cả nhánh feature"
check 2 'ghi đè hoặc xoá trên remote' 'git push --force origin feat'
check 2 'ghi đè hoặc xoá trên remote' 'git push -f origin feat'
check 2 'ghi đè hoặc xoá trên remote' 'git push -uf origin feat'
check 2 'ghi đè hoặc xoá trên remote' 'git push --force-with-lease origin feat'
check 2 'ghi đè hoặc xoá trên remote' 'git push --force-with-lease=feat:abc123 origin feat'
check 2 'ghi đè hoặc xoá trên remote' 'git push --force-if-includes origin feat'
check 2 'ghi đè hoặc xoá trên remote' 'git push origin +HEAD:feat'
check 2 'ghi đè hoặc xoá trên remote' 'git push origin +feat'
check 2 'ghi đè hoặc xoá trên remote' 'git push origin feat --force'
check 2 'ghi đè hoặc xoá trên remote' 'git push --delete origin feat'
check 2 'ghi đè hoặc xoá trên remote' 'git push origin --delete v1.0'
check 2 'ghi đè hoặc xoá trên remote' 'git push -d origin feat'
check 2 'ghi đè hoặc xoá trên remote' 'git push origin :feat'
check 2 'ghi đè hoặc xoá trên remote' 'git push origin :refs/tags/v1'
check 2 'ghi đè hoặc xoá trên remote' 'git push --mirror origin'
check 2 'ghi đè hoặc xoá trên remote' 'git push --prune origin'
check 2 'ghi đè hoặc xoá trên remote' 'git -C . push -f origin feat'
check 2 'ghi đè hoặc xoá trên remote' 'env X=1 git push -f origin feat'
check 2 'ghi đè hoặc xoá trên remote' 'bash -c "git push --force origin feat"'
check 0 '' 'git push --dry-run origin feat'

echo "B. xoá file quan trọng (danh sách mặc định): chặn, người phải làm/duyệt"
check 2 'file quan trọng' 'rm .env'
check 2 'file quan trọng' 'rm -f .env.local'
check 2 'file quan trọng' 'rm -rf app/google-services.json'
check 2 'file quan trọng' 'rm release.keystore'
check 2 'file quan trọng' 'unlink upload.jks'
check 2 'file quan trọng' "rm \"$P/.env\""
check 2 'file quan trọng' 'rm .agents/regression_matrix.active.json'
check 2 'file quan trọng' 'rm -rf .agents/local/memory'
check 2 'file quan trọng' 'rm .agents/local/rules/00.md'
check 2 'file quan trọng' 'rm -rf .agents/local'
check 2 'file quan trọng' 'rm -rf .agents'
check 2 'file quan trọng' 'rm -rf .agents/*'
check 2 'file quan trọng' 'rm -rf .git'
check 2 'file quan trọng' 'rm -rf .git/refs'
check 2 'file quan trọng' 'rm -rf .'
check 2 'file quan trọng' 'rm .env*'
check 2 'file quan trọng' 'cd app && rm google-services.json'
check 2 'file quan trọng' 'sudo rm -f .env'
check 2 'file quan trọng' 'bash -c "rm -f .env"'
check 2 'file quan trọng' 'git rm .env'
check 2 'file quan trọng' 'git rm -r .agents'
check 2 'file quan trọng' 'find . -name .env -delete'
check 2 'file quan trọng' 'find . -name "*.jks" -exec rm {} \;'
check 2 'file quan trọng' 'find .agents/local/memory -type f -delete'
check 2 'file quan trọng' 'find . -delete'
check 2 'file quan trọng' 'find . -path "./.git/*" -delete'
check 2 'file quan trọng' 'find build -name ".env*" -delete'
check 2 'file quan trọng' 'rm -rf ./.agents/local/memory/'

echo "C. xoá file thường: vẫn qua, không hỏi"
check 0 '' 'rm -rf node_modules'
check 0 '' 'rm -rf .agents/local/stage'
check 0 '' 'rm .agents/local/stage/a.txt'
check 0 '' 'rm build/x.log'
check 0 '' 'rm -f src/a.kt'
check 0 '' 'rm -rf .claude/worktrees/w1'
check 0 '' 'git rm src/a.kt'
check 0 '' 'git rm --cached .env'
check 0 '' 'find . -name "*.log" -delete'
check 0 '' 'find build -type f -delete'
check 0 '' 'find . -path "./build/*" -delete'
check 0 '' 'rm -rf build/*'
check 0 '' 'rm -rf .agents/skills-old'
check 0 '' 'docker run --rm img'
check 0 '' 'echo rm .env'
check 0 '' 'grep -n ".env" README.md'
check 0 '' 'rm -rf "$TMPDIR/x"'

echo "D. danh sách thêm trong .antigravity-pm.json (protected_delete)"
printf '{"protected_delete": ["docs/keep/**", "*.sqlite"]}\n' > "$P/.antigravity-pm.json"
mkdir -p "$P/docs/keep"; touch "$P/docs/keep/a.md" "$P/data.sqlite"
check 2 'file quan trọng' 'rm -rf docs/keep'
check 2 'file quan trọng' 'rm data.sqlite'
check 2 'file quan trọng' 'rm .env'
check 0 '' 'rm -rf docs/other'
printf 'not json' > "$P/.antigravity-pm.json"
check 2 'file quan trọng' 'rm .env'
rm -f "$P/.antigravity-pm.json"

echo "E. gốc là git toplevel của cwd (worktree lồng trong project)"
W="$P/.claude/worktrees/w2"
mkdir -p "$W"
git -C "$W" init -q -b feat .
mkdir -p "$W/.agents/local/memory"; touch "$W/.env" "$W/.agents/local/memory/h.md"
check 2 'file quan trọng' 'rm -rf .agents/local/memory' "$W"
check 2 'file quan trọng' 'rm -rf .git' "$W"
check 2 'file quan trọng' 'rm .env' "$W"
check 0 '' 'rm -rf build' "$W"

echo "F. (#605 Lane H) xoá qua interpreter -c/-e với path literal được bảo vệ: chặn"
check 2 'file quan trọng' "python3 -c \"import os; os.remove('app/google-services.json')\""
check 2 'file quan trọng' "python -c \"import os; os.unlink('.env')\""
check 2 'file quan trọng' "python3 -c \"from pathlib import Path; Path('release.keystore').unlink()\""
check 2 'file quan trọng' "python3 -c \"import shutil; shutil.rmtree('.agents/local/memory')\""
check 2 'file quan trọng' "node -e \"require('fs').unlinkSync('.env')\""
check 2 'file quan trọng' "node -e \"fs.rmSync('.agents', {recursive: true})\""
check 2 'file quan trọng' "perl -e \"unlink('upload.jks')\""
check 2 'file quan trọng' "ruby -e \"File.unlink('.env.local')\""
check 0 '' "python3 -c \"import os; os.remove('build/x.log')\""
check 0 '' "python3 -c \"print(open('.env').read())\""
check 0 '' "node -e \"fs.unlinkSync('src/a.kt')\""

echo "G. (#605 Lane H) rm -r <thư mục có thật>: quét nông, chặn khi bên trong có file được bảo vệ"
check 2 'file quan trọng' 'rm -rf app'
check 2 'file quan trọng' 'rm -r app/'
check 2 'file quan trọng' 'rm -Rf ./app'
check 2 'file quan trọng' 'rm --recursive --force app'
mkdir -p "$P/deep/a/b"; touch "$P/deep/a/b/.env"
check 2 'file quan trọng' 'rm -rf deep'
mkdir -p "$P/huge"; ( cd "$P/huge" && for i in $(seq 1 2100); do : > "f$i"; done )
check 2 'file quan trọng' 'rm -rf huge'
check 0 '' 'rm -rf build'
check 0 '' 'rm -rf src'
check 0 '' 'rm app/missing.txt'
mkdir -p "$P/linkdir"; ln -s "$P/app" "$P/linkdir/app-link"
check 0 '' 'rm -rf linkdir'

echo "H. (#605 audit T0066 vòng 2) git rm -r <thư mục> quét bên trong; cây sâu hơn trần thì chặn (fail closed)"
check 2 'file quan trọng' 'git rm -r app'
check 2 'file quan trọng' 'git rm -rq app/'
check 2 'file quan trọng' 'git rm --recursive app'
check 2 'file quan trọng' 'git rm -R app'
check 0 '' 'git rm -r src'
check 0 '' 'git rm -r --cached app'
check 0 '' 'git rm app'
mkdir -p "$P/android/app/src/debug"; touch "$P/android/app/src/debug/google-services.json"
check 2 'file quan trọng' 'rm -rf android'
check 2 'file quan trọng' 'git rm -r android'
mkdir -p "$P/deeptree/1/2/3/4/5/6/7/8/9"; touch "$P/deeptree/1/2/3/4/5/6/7/8/9/x.txt"
check 2 'file quan trọng' 'rm -rf deeptree'
mkdir -p "$P/okdeep/1/2/3/4/5/6"; touch "$P/okdeep/1/2/3/4/5/6/x.txt"
check 0 '' 'rm -rf okdeep'

if [ "$FAILS" -ne 0 ]; then echo "FAIL: $FAILS case(s)"; exit 1; fi
echo "PASS"
