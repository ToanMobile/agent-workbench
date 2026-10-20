#!/usr/bin/env bash
# Push thẳng main/master không còn bị chặn khi không force và không xoá nhánh.
# Force, mirror và delete vẫn bị chặn: đó là việc cực kỳ nguy hiểm, agent phải hỏi.
# ĐỎ trên bản hook cũ (mọi direct push đều Blocked).
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DK/hooks/guard-protected-push.py"
FAILS=0

judge() {
  local name="$1" cmd="$2" branch="$3" want="$4" got
  got="$(python3 -c '
import importlib.util, sys
path, cmd, branch = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("gpp", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
reason = mod.check(cmd, "/repo", {"main", "master"}, lambda d: branch)
print("ALLOW" if reason is None else "BLOCK")
' "$HOOK" "$cmd" "$branch")"
  if [ "$got" = "$want" ]; then
    echo "✔ $name"
  else
    echo "✖ $name: got $got, want $want"
    FAILS=$((FAILS + 1))
  fi
}

judge "fast-forward git push origin main" "git push origin main" main ALLOW
judge "bare git push while on main" "git push" main ALLOW
judge "push a feature branch" "git push -u origin feature/x" main ALLOW
judge "non-force refspec onto main" "git push origin feature/x:main" main ALLOW
judge "force push to main" "git push --force origin main" main BLOCK
judge "force-with-lease to main" "git push --force-with-lease origin main" main BLOCK
judge "plus refspec is force" "git push origin +HEAD:main" main BLOCK
judge "delete protected branch" "git push origin --delete main" main BLOCK
judge "empty refspec deletes main" "git push origin :main" main BLOCK
judge "mirror is dangerous" "git push --mirror origin" main BLOCK
judge "feature checkout is not protected" "git push origin feature/x" feature ALLOW

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git init -q -b main "$TMP/repo"
git -C "$TMP/repo" config user.email t@t
git -C "$TMP/repo" config user.name t
git -C "$TMP/repo" commit -q --allow-empty -m init
feed() {
  python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$TMP/repo" \
    | CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$HOOK"
}
out="$(feed "git push origin main")"
if [ -z "$out" ]; then echo "✔ hook stdout empty for a normal main push"; else
  echo "✖ hook denied a normal main push: $out"; FAILS=$((FAILS + 1))
fi
out="$(feed "git push --force origin main")"
case "$out" in
  *Force\ push*) echo "✔ hook denies force push to main" ;;
  *) echo "✖ force push was not denied: $out"; FAILS=$((FAILS + 1)) ;;
esac
case "$out" in
  *ask\ the\ user\ to\ run\ it*|*SB_ALLOW_PROTECTED_PUSH=1*)
    echo "✖ deny text still hands the user a command"; FAILS=$((FAILS + 1)) ;;
  *) echo "✔ deny text does not hand the user a shell command" ;;
esac

[ "$FAILS" = 0 ] && exit 0
echo "$FAILS failure(s)"
exit 1
