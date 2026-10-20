#!/usr/bin/env bash
# Push thẳng main/master không còn bị chặn khi không force và không xoá nhánh.
# Force, mirror và delete vẫn bị chặn: đó là việc cực kỳ nguy hiểm, agent phải hỏi.
# ĐỎ trên bản hook cũ (mọi direct push đều Blocked).
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DK/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh (ratchet test_git_env_isolation.sh)
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
judge "short -f is force" "git push -f origin main" main BLOCK
judge "force-if-includes to main" "git push --force-if-includes origin main" main BLOCK
judge "force-with-lease to main" "git push --force-with-lease origin main" main BLOCK
judge "plus refspec is force" "git push origin +HEAD:main" main BLOCK
judge "delete protected branch" "git push origin --delete main" main BLOCK
judge "empty refspec deletes main" "git push origin :main" main BLOCK
judge "mirror is dangerous" "git push --mirror origin" main BLOCK
judge "feature checkout is not protected" "git push origin feature/x" feature ALLOW
# Viết tắt và cụm cờ: git nhận tiền tố duy nhất và chữ trong cụm một gạch.
judge "clustered -uf is force" "git push -uf origin main" main BLOCK
judge "clustered -fu is force" "git push -fu origin main" main BLOCK
judge "abbreviated --forc is force" "git push --forc origin main" main BLOCK
judge "abbreviated --for is force" "git push --for origin main" main BLOCK
judge "abbreviated --forc=main is force" "git push --forc=main origin main" main BLOCK
judge "abbreviated --force-with-leas is force" "git push --force-with-leas origin main" main BLOCK
judge "prune deletes remote refs" "git push --prune origin" main BLOCK
judge "prune after the remote" "git push origin --prune" main BLOCK
judge "prune from a feature checkout" "git push --prune origin" feature BLOCK
judge "abbreviated --prun is prune" "git push --prun origin" main BLOCK
judge "clustered -ud deletes" "git push -ud origin main" main BLOCK
judge "no-verify on a protected dest" "git push --no-verify origin main" main BLOCK
judge "abbreviated --no-veri is no-verify" "git push --no-veri origin main" main BLOCK
judge "abbreviated --mirro is mirror" "git push --mirro origin" main BLOCK
judge "dry-run stays allowed" "git push --dry-run origin main" main ALLOW
judge "follow-tags stays allowed" "git push --follow-tags origin main" main ALLOW
judge "progress stays allowed" "git push --progress origin main" main ALLOW
judge "porcelain stays allowed" "git push --porcelain origin main" main ALLOW
judge "ambiguous --fo is not force" "git push --fo origin main" main ALLOW
judge "ambiguous --d is not delete" "git push --d origin main" main ALLOW
judge "ambiguous --pr is not prune" "git push --pr origin main" main ALLOW
judge "negation --no-force stays allowed" "git push --no-force origin main" main ALLOW
judge "ambiguous --no-v stays allowed" "git push --no-v origin main" main ALLOW
judge "glued push-option is not force" "git push -ofoo origin main" main ALLOW
judge "set-upstream alone stays allowed" "git push -u origin main" main ALLOW
judge "tags alone stay allowed" "git push --tags" main ALLOW
judge "all without force stays allowed" "git push --all" main ALLOW
judge "all with force from a feature checkout" "git push --all --force" feature BLOCK
judge "abbreviated --branche with force" "git push --branche --force" feature BLOCK
judge "abbreviated --branche without force stays allowed" "git push --branche" feature ALLOW
judge "force to a feature branch stays allowed" "git push -uf origin feature/x" feature ALLOW
judge "no-verify of a feature branch stays allowed" "git push --no-verify origin feature/x" feature ALLOW

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
out="$(feed "git push -uf origin main")"
case "$out" in
  *Force\ push*) echo "✔ hook denies a clustered force push" ;;
  *) echo "✖ clustered force was not denied: $out"; FAILS=$((FAILS + 1)) ;;
esac
case "$out" in
  *ask\ the\ user\ to\ run\ it*|*SB_ALLOW_PROTECTED_PUSH=1*)
    echo "✖ clustered deny text hands the user a command"; FAILS=$((FAILS + 1)) ;;
  *) echo "✔ clustered deny text does not hand the user a shell command" ;;
esac

[ "$FAILS" = 0 ] && exit 0
echo "$FAILS failure(s)"
exit 1
