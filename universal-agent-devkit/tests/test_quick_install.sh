#!/usr/bin/env bash
# Regression test: bin/quick-install.sh — a second run updates in place (git pull) instead
# of nesting a new copy inside the old one; an old non-git copy is moved aside; offline
# and unreachable cases. Uses a local "agent-workbench" repo as the remote, no network.
set -u

SRC_DEVKIT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# The "remote": a monorepo with the DevKit in universal-agent-devkit/ next to other projects.
REMOTE="$TMP/remote"
mkdir -p "$REMOTE/universal-agent-devkit" "$REMOTE/other-project"
(cd "$SRC_DEVKIT" && tar --exclude=./node_modules --exclude=./.git -cf - .) | (cd "$REMOTE/universal-agent-devkit" && tar -xf -)
echo "not the devkit" > "$REMOTE/other-project/README.md"
(cd "$REMOTE" && git init -q -b main && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init) || { echo "cannot build the test remote"; exit 1; }

export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/cwd"
export DEVKIT_REPO_URL="file://$REMOTE"
INSTALLER="$REMOTE/universal-agent-devkit/bin/quick-install.sh"
run() { (cd "$TMP/cwd" && bash "$INSTALLER") > "$TMP/out" 2>&1; }
INSTALL="$HOME/.universal-agent-devkit"
REPO="$HOME/.agent-workbench"

run; rc=$?
[ "$rc" = 0 ] && [ -d "$REPO/.git" ] && [ -L "$INSTALL" ] && [ -f "$INSTALL/bin/agent-kit" ] \
  && ok "first run: git checkout + stable link to the DevKit" || { fail "first run (rc=$rc)"; cat "$TMP/out"; }
[ ! -e "$REPO/other-project" ] && ok "sparse checkout: only universal-agent-devkit/ is checked out" || fail "whole monorepo checked out"
bash "$HOME/.local/bin/agent-kit" help >/dev/null 2>&1 && ok "~/.local/bin/agent-kit runs" || fail "agent-kit link broken"

# The remote moves on; the second run must pull it — not nest a copy inside the old one.
echo "# v2 marker" >> "$REMOTE/universal-agent-devkit/README.md"
(cd "$REMOTE" && git commit -qam v2)
run; rc=$?
[ "$rc" = 0 ] && grep -q "v2 marker" "$INSTALL/README.md" && ok "second run updates in place (git pull)" \
  || { fail "second run did not update (rc=$rc)"; cat "$TMP/out"; }
[ ! -e "$INSTALL/universal-agent-devkit" ] && [ ! -e "$REPO/universal-agent-devkit/universal-agent-devkit" ] \
  && ok "no nested universal-agent-devkit/universal-agent-devkit" || fail "nested copy created"

# Local edits in the checkout are never overwritten.
echo "my local edit" >> "$REPO/universal-agent-devkit/AGENTS.md"
echo "# v3 marker" >> "$REMOTE/universal-agent-devkit/README.md"
(cd "$REMOTE" && git commit -qam v3)
run; rc=$?
[ "$rc" = 0 ] && grep -q "my local edit" "$INSTALL/AGENTS.md" && grep -q "local changes" "$TMP/out" \
  && ok "local changes: update skipped with a warning, edit kept" || fail "local edit handling (rc=$rc)"
git -C "$REPO" checkout -q -- .

# An old installer left a plain copy (no .git) at ~/.universal-agent-devkit.
rm -rf "$REPO" "$INSTALL"
mkdir -p "$INSTALL/bin" && echo "old" > "$INSTALL/bin/agent-kit"
run; rc=$?
[ "$rc" = 0 ] && [ -L "$INSTALL" ] && grep -q "v3 marker" "$INSTALL/README.md" \
  && ls -d "$INSTALL".old-* >/dev/null 2>&1 && ok "old non-git copy kept aside as .old-*, replaced by the link" \
  || { fail "legacy copy migration (rc=$rc)"; cat "$TMP/out"; }

# Offline: DEVKIT_LOCAL_SOURCE is used in place, nothing is copied.
rm -rf "$REPO" "$INSTALL" "$INSTALL".old-*
DEVKIT_REPO_URL="file://$TMP/nowhere" DEVKIT_LOCAL_SOURCE="$REMOTE" run; rc=$?
[ "$rc" = 0 ] && [ "$(cd "$INSTALL" && pwd -P)" = "$(cd "$REMOTE/universal-agent-devkit" && pwd -P)" ] \
  && ok "DEVKIT_LOCAL_SOURCE: linked to the local checkout's DevKit dir" || { fail "local source (rc=$rc)"; cat "$TMP/out"; }

# Unreachable remote, no local source: fails and leaves nothing half-made.
rm -rf "$REPO" "$INSTALL"
DEVKIT_REPO_URL="file://$TMP/nowhere" run; rc=$?
[ "$rc" != 0 ] && [ ! -e "$REPO" ] && [ ! -e "$INSTALL" ] && ok "unreachable remote: exit $rc, nothing left behind" \
  || fail "unreachable remote (rc=$rc)"

if [ "$FAILS" -ne 0 ]; then
  echo "quick-install: $FAILS FAILED"; exit 1
fi
echo "quick-install: all checks passed"
