#!/usr/bin/env bash
# Regression test: `agent-kit githooks` — the git pre-commit hook runs the gate's
# static checks on every commit and never clobbers a project's own hook.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset CLAUDE_PROJECT_DIR TARGET_DIR

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

new_repo() {
  rm -rf "$TMP/repo" && mkdir -p "$TMP/repo" && cd "$TMP/repo" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > a.kt && git add a.kt && git commit -qm init --no-verify
}
commits() { git rev-list --count HEAD; }

new_repo
bash "$KIT" githooks install >/dev/null 2>&1 || fail "install exited non-zero"
HOOK="$(git rev-parse --path-format=absolute --git-path hooks)/pre-commit"
[ -x "$HOOK" ] && grep -q 'universal-agent-devkit:githook' "$HOOK" && ok "install writes a marked, executable hook" \
  || fail "hook missing / unmarked / not executable"
bash "$KIT" githooks status | grep -q 'installed (DevKit)' && ok "status reports it" || fail "status does not report it"

echo "fun ok() = 2" > a.kt && git add a.kt
# Descriptive subjects: the commit-msg rule (vague subjects on code) must not be what blocks here.
git commit -qm "feat: add the ok function" >/dev/null 2>&1 && ok "clean commit goes through" || fail "clean commit was blocked"

n="$(commits)"
printf '%s = "%s"\n' "api_""key" "ABCDEFGHIJKLMNOP" > leak.py && git add leak.py
out="$(git commit -qm "feat: add the api client" 2>&1)"
[ "$(commits)" = "$n" ] && ok "commit with a secret is blocked" || fail "commit with a secret went through"
printf '%s' "$out" | grep -q -- '--no-verify' && ok "block message names the escape hatch" || fail "no --no-verify hint"
git rm -q --cached leak.py && rm leak.py

printf 'KEY=1\n' > .env && git add -f .env
git commit -qm "chore: add the local env file" >/dev/null 2>&1; [ "$(commits)" = "$n" ] && ok ".env is blocked" || fail ".env was committed"
git rm -q --cached .env && rm .env

printf 'dependencies { implementation "a:b:1.+" }\n' > build.gradle && git add build.gradle
git commit -qm "build: add the http dependency" >/dev/null 2>&1; [ "$(commits)" = "$n" ] && ok "floating dependency is blocked" || fail "floating dependency committed"
git rm -q --cached build.gradle && rm build.gradle

printf '%s = "%s"\n' "api_""key" "ABCDEFGHIJKLMNOP" > leak.py && git add leak.py
DEVKIT_PRECOMMIT=0 git commit -qm "chore: skip the hook once" >/dev/null 2>&1 && ok "DEVKIT_PRECOMMIT=0 disables the hook" || fail "DEVKIT_PRECOMMIT=0 ignored"
git reset -q --soft HEAD~1 && git rm -q --cached leak.py && rm leak.py

# Fail closed: a gate that gives no verdict must not let the commit through.
n="$(commits)"
echo "fun ok() = 3" > a.kt && git add a.kt
mkdir -p "$TMP/nopy" && printf '#!/bin/sh\nexit 1\n' > "$TMP/nopy/python3" && chmod +x "$TMP/nopy/python3"
PATH="$TMP/nopy:$PATH" git commit -qm "feat: commit with python missing" >/dev/null 2>&1
[ "$(commits)" = "$n" ] && ok "broken python3 -> commit blocked (fail closed)" || fail "commit went through without a verdict"
git reset -q

bash "$KIT" githooks uninstall >/dev/null && [ ! -e "$HOOK" ] && ok "uninstall removes the DevKit hook" || fail "uninstall left the hook"

# A project's own hook is never overwritten or removed.
new_repo
HOOK="$(git rev-parse --path-format=absolute --git-path hooks)/pre-commit"
printf '#!/bin/sh\necho mine\n' > "$HOOK" && chmod +x "$HOOK"
out="$(bash "$KIT" githooks install 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'echo mine' "$HOOK" && ok "foreign hook: install refuses and keeps it" || fail "foreign hook overwritten (rc=$rc)"
printf '%s' "$out" | grep -q 'git-pre-commit.sh' && ok "refusal prints the chaining line" || fail "no chaining line"
printf '%s' "$out" | grep -qi 'after the first\|NGAY SAU' && ! printf '%s' "$out" | grep -qi 'append this line' \
  && ok "chaining advice says: insert after the shebang (an appended line can sit after 'exit 0')" || fail "chaining advice still says append"
cp "$HOOK" "$HOOK.own"; printf '#!/bin/sh\nbash %s "$@" || exit 1\necho mine\nexit 0\n' "$DEVKIT_DIR/scripts/git-pre-commit.sh" > "$HOOK"
bash "$KIT" githooks status 2>&1 | grep -q "chaining the DevKit gate\|có gọi cổng DevKit" \
  && ok "status recognises a project hook that chains the DevKit gate" || fail "chained hook not recognised: $(bash "$KIT" githooks status 2>&1)"
mv "$HOOK.own" "$HOOK"
bash "$KIT" githooks uninstall >/dev/null; grep -q 'echo mine' "$HOOK" && ok "uninstall keeps a foreign hook" || fail "uninstall removed a foreign hook"

# core.hooksPath (husky, lefthook, …) is honoured.
new_repo
git config core.hooksPath .githooks
bash "$KIT" githooks install >/dev/null 2>&1
[ -f .githooks/pre-commit ] && [ ! -f .git/hooks/pre-commit ] && ok "installs into core.hooksPath" || fail "core.hooksPath ignored"

# agent-kit uninstall removes the stub too.
new_repo
bash "$KIT" githooks install >/dev/null 2>&1
python3 "$DEVKIT_DIR/scripts/devkit_uninstall.py" "$TMP/repo" --apply >/dev/null 2>&1
[ ! -e .git/hooks/pre-commit ] && ok "agent-kit uninstall removes the hook" || fail "agent-kit uninstall left the hook"

if [ "$FAILS" -ne 0 ]; then
  echo "githooks: $FAILS FAILED"; exit 1
fi
echo "githooks: all checks passed"
