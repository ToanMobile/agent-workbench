#!/usr/bin/env bash
# quick-install.sh — One-liner Remote Bootstrapper for Universal Agent DevKit
# Usage: curl -fsSL https://.../bin/quick-install.sh | bash
set -euo pipefail

# Layout — the DevKit lives in a subdirectory of the agent-workbench monorepo:
#   REPO_DIR     ~/.agent-workbench             sparse git checkout (only DEVKIT_SUBDIR),
#                                               so every re-run is a plain `git pull`
#   INSTALL_DIR  ~/.universal-agent-devkit  ->  $REPO_DIR/universal-agent-devkit
# INSTALL_DIR is a stable symlink: CLI links and project links made by earlier installs
# keep resolving. (Earlier versions moved the subdirectory out of a temp clone: no .git,
# so a second run `mv`-ed a new copy INSIDE the old one and never updated.)
INSTALL_DIR="${DEVKIT_INSTALL_DIR:-${HOME}/.universal-agent-devkit}"
REPO_DIR="${DEVKIT_REPO_DIR:-${HOME}/.agent-workbench}"
BIN_DIR="${HOME}/.local/bin"
REPO_URL="${DEVKIT_REPO_URL:-https://github.com/ToanMobile/agent-workbench.git}"
DEVKIT_SUBDIR="universal-agent-devkit"

echo "================================================================="
echo "  🚀 Bootstrapping Universal Agent DevKit"
echo "================================================================="

# 1. Clone or update the monorepo checkout
DEVKIT_DIR="$REPO_DIR/$DEVKIT_SUBDIR"
if [ -d "$REPO_DIR/.git" ]; then
  echo "Updating existing DevKit at $REPO_DIR..."
  # Never `reset --hard`: local edits (also made through project symlinks) would be lost.
  if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
    echo "⚠ $REPO_DIR has local changes — skipping update (commit/stash them, then re-run)." >&2
  else
    git -C "$REPO_DIR" pull --ff-only --quiet origin main \
      || echo "⚠ Could not fast-forward $REPO_DIR to origin/main — left as is." >&2
  fi
elif [ -n "${DEVKIT_LOCAL_SOURCE:-}" ]; then
  # Offline / development: use an existing checkout (the agent-workbench root or the
  # DevKit dir itself) in place — nothing is copied, so updates come from that checkout.
  if [ -f "$DEVKIT_LOCAL_SOURCE/$DEVKIT_SUBDIR/bin/agent-kit" ]; then
    DEVKIT_DIR="$(cd "$DEVKIT_LOCAL_SOURCE/$DEVKIT_SUBDIR" && pwd -P)"
  elif [ -f "$DEVKIT_LOCAL_SOURCE/bin/agent-kit" ]; then
    DEVKIT_DIR="$(cd "$DEVKIT_LOCAL_SOURCE" && pwd -P)"
  else
    echo "✖ DEVKIT_LOCAL_SOURCE=$DEVKIT_LOCAL_SOURCE holds no $DEVKIT_SUBDIR/bin/agent-kit — nothing installed." >&2
    exit 1
  fi
  echo "Using local DevKit checkout $DEVKIT_DIR"
else
  if [ -e "$REPO_DIR" ]; then
    echo "✖ $REPO_DIR exists but is not a git checkout — move it away, then re-run." >&2
    exit 1
  fi
  echo "Cloning Universal Agent DevKit into $REPO_DIR..."
  git clone --depth 1 --filter=blob:none --sparse --quiet "$REPO_URL" "$REPO_DIR" \
    || { echo "✖ Cannot clone $REPO_URL (offline? set DEVKIT_LOCAL_SOURCE=/path/to/agent-workbench) — nothing installed." >&2; rm -rf "$REPO_DIR"; exit 1; }
  git -C "$REPO_DIR" sparse-checkout set "$DEVKIT_SUBDIR" \
    || { echo "✖ git sparse-checkout failed (needs git >= 2.25) — nothing installed." >&2; rm -rf "$REPO_DIR"; exit 1; }
fi
[ -f "$DEVKIT_DIR/bin/agent-kit" ] \
  || { echo "✖ $DEVKIT_SUBDIR/ not found in $REPO_DIR — nothing linked." >&2; exit 1; }

# 1b. Point the stable INSTALL_DIR at it. A real directory there is a copy from an
#     earlier installer (it cannot be updated): kept aside as a dated backup, not deleted.
if [ -L "$INSTALL_DIR" ] || [ ! -e "$INSTALL_DIR" ]; then
  ln -sfn "$DEVKIT_DIR" "$INSTALL_DIR"
else
  if [ -d "$INSTALL_DIR/.git" ] && [ -n "$(git -C "$INSTALL_DIR" status --porcelain 2>/dev/null)" ]; then
    echo "✖ $INSTALL_DIR is an older DevKit checkout with local changes — commit/stash or move it, then re-run." >&2
    exit 1
  fi
  OLD_COPY="${INSTALL_DIR}.old-$(date +%Y%m%d-%H%M%S)"
  mv "$INSTALL_DIR" "$OLD_COPY"
  ln -sfn "$DEVKIT_DIR" "$INSTALL_DIR"
  echo "⚠ Previous copy at $INSTALL_DIR was not updatable — kept as $OLD_COPY (delete it when you no longer need it)." >&2
  echo "  Projects installed in symlink mode keep working through $INSTALL_DIR; re-run 'agent-kit init' in them to pick up new skills." >&2
fi

# 2. Link CLI to ~/.local/bin
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/bin/agent-kit" "$BIN_DIR/agent-kit"
ln -sf "$INSTALL_DIR/bin/install.sh" "$BIN_DIR/agent-install"
ln -sf "$INSTALL_DIR/bin/profile" "$BIN_DIR/agent-profile"
ln -sf "$INSTALL_DIR/bin/agent-health.py" "$BIN_DIR/agent-health"
ln -sf "$INSTALL_DIR/bin/postfix-gate" "$BIN_DIR/postfix-gate"

# 3. Ensure PATH contains ~/.local/bin
export PATH="$BIN_DIR:$PATH"

echo "✓ 'agent-kit' successfully installed to $BIN_DIR/agent-kit"
echo "✓ 'agent-profile' successfully installed to $BIN_DIR/agent-profile"
echo "✓ 'agent-health' successfully installed to $BIN_DIR/agent-health"
echo "✓ 'postfix-gate' successfully installed to $BIN_DIR/postfix-gate"
echo

# 4. If current directory is a project, launch agent setup
if [ -d ".git" ] || [ -f "package.json" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ] || [ -f "pyproject.toml" ]; then
  echo "Detected active project in current directory: $PWD"
  if (exec 3</dev/tty) 2>/dev/null; then
    bash "$INSTALL_DIR/bin/install.sh" --target="$PWD" < /dev/tty
  else
    bash "$INSTALL_DIR/bin/install.sh" --target="$PWD"
  fi
fi

echo
echo "================================================================="
echo "  ✨ Setup Complete! You can now run 'agent-kit init' anywhere."
echo "================================================================="
