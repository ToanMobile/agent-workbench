#!/usr/bin/env bash
# hooks/devkit_harness.py tree_fingerprint (the regression_gate.sh reuse key), agent notes in .agents/local/memory/claude-auto/
# (Dot 20 review, 2026-10-12): bin/tree_fp.EXCLUDE already names the folder, so the full-pass receipt survives a note, but
# devkit_harness.OWN did not, so the Stop hook's reuse key still moved with every note and the suites ran again. Same rule as
# test_tree_fp_claude_auto.sh: only that folder is excluded; memory/voice, a sibling whose name starts with claude-auto and
# a file directly under memory/ still move the fingerprint.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="${HARNESS_DIR:-$DEVKIT_DIR/hooks}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
M=".agents/local/memory"
mkdir -p "$R/src" "$R/$M/claude-auto" "$R/$M/voice" "$R/$M/claude-autoX"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
printf 'fun ok() = 1\n' > "$R/src/Core.kt"
printf 'note one\n' > "$R/$M/claude-auto/n1.md"
printf 'rule one\n' > "$R/$M/voice/VOICE-RULES.md"
printf 'sibling one\n' > "$R/$M/claude-autoX/s.md"
git -C "$R" add -A && git -C "$R" commit -qm init
fp() { PYTHONPATH="$HOOKS" python3 -c 'import sys, devkit_harness; print(devkit_harness.tree_fingerprint(sys.argv[1]))' "$R"; }
BASE="$(fp)"
[ -n "$BASE" ] && ok "fingerprint computed" || { bad "no fingerprint"; exit 1; }

printf 'note one, edited and longer\n' > "$R/$M/claude-auto/n1.md"
[ "$(fp)" = "$BASE" ] && ok "tracked claude-auto note edited: fingerprint unchanged" || bad "edit of a tracked claude-auto note moved the fingerprint"
printf 'a brand new note\n' > "$R/$M/claude-auto/n2.md"
[ "$(fp)" = "$BASE" ] && ok "new untracked claude-auto note: fingerprint unchanged" || bad "a new claude-auto note moved the fingerprint"
printf '{"a":1}\n' > "$R/$M/claude-auto/reviewer-log.jsonl"
[ "$(fp)" = "$BASE" ] && ok "reviewer-log.jsonl in claude-auto: fingerprint unchanged" || bad "a non-.md file in claude-auto moved the fingerprint"
rm -f "$R/$M/claude-auto/n1.md"
[ "$(fp)" = "$BASE" ] && ok "claude-auto note deleted: fingerprint unchanged" || bad "deleting a claude-auto note moved the fingerprint"

printf 'rule one, changed\n' > "$R/$M/voice/VOICE-RULES.md"
[ "$(fp)" != "$BASE" ] && ok "a voice rule (memory/voice) changed: fingerprint moves" || bad "memory/voice change did not move the fingerprint (too wide an exclude)"
git -C "$R" checkout -q -- "$M/voice/VOICE-RULES.md"
printf 'sibling one, changed\n' > "$R/$M/claude-autoX/s.md"
[ "$(fp)" != "$BASE" ] && ok "folder named claude-autoX changed: fingerprint moves" || bad "claude-autoX change did not move the fingerprint"
git -C "$R" checkout -q -- "$M/claude-autoX/s.md"
printf 'fun ok() = 22\n' > "$R/src/Core.kt"
[ "$(fp)" != "$BASE" ] && ok "source file changed: fingerprint moves" || bad "a source change did not move the fingerprint"
git -C "$R" checkout -q -- src/Core.kt
printf 'x\n' > "$R/$M/top-level.md"
[ "$(fp)" != "$BASE" ] && ok "file directly under memory/: fingerprint moves" || bad "memory/top-level.md change did not move the fingerprint"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
