#!/usr/bin/env bash
# Regression test (2026-10-09): an install through the stable alias of quick-install.sh (~/.universal-agent-devkit -> the checkout)
# writes its links through the alias, so a moved checkout only needs the alias re-pointed. scripts/governance/relink_check.py (the
# post-merge / post-checkout repair) re-created a missing link with the REAL path, so after one repair that project broke again on
# the next move. It now links through the path the installer wrote into .agents/devkit when that is the same DevKit.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset DEVKIT_RELINK
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
ALIAS="$TMP/alias-kit"; ln -s "$DEVKIT_DIR" "$ALIAS"
P="$TMP/p"; mkdir -p "$P" && cd "$P" && git init -q -b main . && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false
echo x > a && git add a && git commit -qm init
bash "$ALIAS/bin/install.sh" -t "$P" -a claude -p backend -y >/dev/null 2>&1
case "$(readlink .claude/hooks/precode_gate.sh)" in
  "$ALIAS"/*) ok "install through the alias links through it" ;;
  *) fail "install did not link through the alias: $(readlink .claude/hooks/precode_gate.sh)" ;;
esac
rm -f .claude/hooks/precode_gate.sh
python3 "$DEVKIT_DIR/scripts/governance/relink_check.py" "$P" --quiet
case "$(readlink .claude/hooks/precode_gate.sh 2>/dev/null)" in
  "$ALIAS"/*) ok "relink re-creates the link through the alias" ;;
  "") fail "relink did not re-create the link" ;;
  *) fail "relink used another path: $(readlink .claude/hooks/precode_gate.sh)" ;;
esac
[ "$FAILS" -eq 0 ] && echo "✅ test_relink_alias: all passed" || { echo "❌ test_relink_alias: $FAILS failed"; exit 1; }
