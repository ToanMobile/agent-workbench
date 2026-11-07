#!/usr/bin/env bash
# Regression test: tests/lib/clean_git_env.sh isolates a test from the user's GLOBAL git config. Heavy gate 06/11:
# push.followTags=true in ~/.gitconfig made tests/gates/test_push_gate_hook.sh give 11 reds (the push gate refuses any push whose
# destination a config like that could change). The identity must still resolve without the global config (INSTINCT-043).
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DEVKIT_DIR/tests/lib/clean_git_env.sh"
LIB="$DEVKIT_DIR/tests/lib/clean_git_env.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/home" "$TMP/repo"
printf '[push]\n\tfollowTags = true\n[user]\n\temail = global@example.invalid\n' > "$TMP/home/.gitconfig"
cp "$TMP/home/.gitconfig" "$TMP/global.cfg"
git init -q "$TMP/repo"

# 1. ~/.gitconfig of the caller (HOME) is not read after sourcing
got="$(cd "$TMP/repo" && env -u GIT_CONFIG_GLOBAL HOME="$TMP/home" bash -c '. "$1"; git config --get push.followTags' _ "$LIB")"
[ -z "$got" ] && ok "HOME/.gitconfig push.followTags is not seen after sourcing" || fail "HOME/.gitconfig leaked: push.followTags='$got'"

# 2. a caller's GIT_CONFIG_GLOBAL is replaced, not kept
got="$(cd "$TMP/repo" && env GIT_CONFIG_GLOBAL="$TMP/global.cfg" bash -c '. "$1"; git config --get push.followTags' _ "$LIB")"
[ -z "$got" ] && ok "caller's GIT_CONFIG_GLOBAL push.followTags is not seen after sourcing" || fail "GIT_CONFIG_GLOBAL leaked: push.followTags='$got'"

# 3. identity still resolves with no user.email anywhere but EMAIL (fallback ranked below a fixture's user.email)
id="$(cd "$TMP/repo" && env -u EMAIL HOME="$TMP/home" bash -c '. "$1"; git var GIT_COMMITTER_IDENT' _ "$LIB" 2>&1)"
case "$id" in *"<devkit-test@localhost>"*) ok "identity falls back to EMAIL=devkit-test@localhost";; *) fail "identity without global config: '$id'";; esac
git -C "$TMP/repo" config user.email fixture@t
id="$(cd "$TMP/repo" && env -u EMAIL bash -c '. "$1"; git var GIT_COMMITTER_IDENT' _ "$LIB" 2>&1)"
case "$id" in *"<fixture@t>"*) ok "a fixture's own user.email still wins over the EMAIL fallback";; *) fail "fixture identity overridden: '$id'";; esac

[ "$FAILS" -eq 0 ] && echo "git env global config: all checks passed" || { echo "git env global config: $FAILS FAILED"; exit 1; }
