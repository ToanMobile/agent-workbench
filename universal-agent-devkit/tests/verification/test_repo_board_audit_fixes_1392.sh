#!/usr/bin/env bash
# #1392 audit (Antigravity, 21/11/2026): two minor findings in the kit part of PR #1394.
# (a) shims/gh resolved a RELATIVE symlink wrongly when invoked by a bare name (`bash gh` in the symlink's
#     directory): `${self%/*}` of "gh" is "gh", so self became "gh/<target>", the shim dir did not exist and the
#     shim exited 2 instead of running the real gh. shims/adb already handles it (bare-name case + 40-hop cap).
# (b) completions/agent-kit.bash did not offer the new `board` subcommand.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)" || exit 1
trap 'rm -rf "$T"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# (a) a fake real gh on PATH, the shim reached through a relative symlink and run by its bare name
mkdir -p "$T/real" "$T/w"
printf '#!/bin/sh\necho real-gh "$@"\n' > "$T/real/gh"; chmod +x "$T/real/gh"
ln -s "$DK" "$T/w/kit"
ln -s kit/shims/gh "$T/w/gh"
out="$(cd "$T/w" && PATH="$T/real:/usr/bin:/bin" bash gh --version 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "real-gh --version" ] \
  && ok "(a) gh shim via a relative symlink run by bare name execs the real gh" \
  || fail "(a) gh shim via a relative symlink run by bare name: rc=$rc out=$out"
grep -q '_hops -lt 40' "$DK/shims/gh" && ok "(a) gh shim caps symlink hops like shims/adb" || fail "(a) gh shim has no symlink hop cap"

# (b) tab completion offers `board`
grep -A2 'words="init' "$DK/completions/agent-kit.bash" | grep -qw board \
  && ok "(b) completion offers board" || fail "(b) completion does not offer board"

[ "$FAILS" -eq 0 ] && { echo "✅ test_repo_board_audit_fixes_1392"; exit 0; }
echo "❌ test_repo_board_audit_fixes_1392: $FAILS failure(s)"; exit 1
