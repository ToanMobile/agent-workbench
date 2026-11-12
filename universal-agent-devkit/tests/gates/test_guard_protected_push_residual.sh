#!/usr/bin/env bash
# #880 (residual review of #871): guard-protected-push.py phải chặn (a) lệnh có >= 992 từ `-S` sau `env` (RecursionError
# không được fail-open), (b) force push có `\<newline>` nối dòng (như shell), (c) base_branch đọc từ config
# .claude/super-board/configs/*.json là symlink. Mỗi ca chặn có ca đối chứng không force vẫn ALLOW (INSTINCT-045).
# ĐỎ trên main 3ab51868 (cả ba dạng trả ALLOW); XANH sau khi sửa guard.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
unset SB_ALLOW_PROTECTED_PUSH SB_PROTECTED_BRANCHES
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DK/hooks/guard-protected-push.py"
FAILS=0

judge() {
  local name="$1" cmd="$2" want="$3" got
  got="$(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gpp", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
try:
    reason = mod.check(sys.argv[2], "/repo", {"main", "master"}, lambda d: "feat")
except RecursionError:
    reason = None
print("ALLOW" if reason is None else "BLOCK")
' "$HOOK" "$cmd" 2>&1)"
  if [ "$got" = "$want" ]; then echo "✔ $name"; else echo "✖ $name: got $got, want $want"; FAILS=$((FAILS + 1)); fi
}

P="push"
envs="env $(python3 -c 'print("-S -i " * 1200, end="")')"
judge "(a) 1200 x env -S words then force $P main" "${envs}true; git $P -f origin main" BLOCK
judge "control (a): same prefix, no force" "${envs}true; git $P origin main" ALLOW
judge "(b) backslash-newline glued to the flag" "git $P \\
--force origin main" BLOCK
judge "(b) backslash-newline inside the git command" "git \\
$P -f origin main" BLOCK
judge "(b) backslash-newline glued to the branch" "git $P -f origin \\
main" BLOCK
judge "control (b): backslash-newline, no force" "git $P \\
origin main" ALLOW

# (c) end to end through main(): config symlink with base_branch release
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.claude/super-board/configs" "$T/real"
printf '{"base_branch":"release"}' > "$T/real/cfg.json"
ln -s "$T/real/cfg.json" "$T/.claude/super-board/configs/x.json"
run_main() {
  python3 -c '
import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}, "cwd": sys.argv[2]}))
' "$1" "$T" | CLAUDE_PROJECT_DIR="$T" python3 "$HOOK" 2>/dev/null
}
out="$(run_main "git $P -f origin release")"
case "$out" in *deny*|*Blocked*) echo "✔ (c) symlinked config: force $P release blocked" ;;
  *) echo "✖ (c) symlinked config: force $P release not blocked: $out"; FAILS=$((FAILS + 1)) ;; esac
out="$(run_main "git $P origin release")"
case "$out" in *deny*|*Blocked*) echo "✖ control (c): plain $P release blocked: $out"; FAILS=$((FAILS + 1)) ;;
  *) echo "✔ control (c): plain $P release allowed" ;; esac
[ "$FAILS" -eq 0 ]
