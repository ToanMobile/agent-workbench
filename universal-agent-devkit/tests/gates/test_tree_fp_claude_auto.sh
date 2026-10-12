#!/usr/bin/env bash
# bin/tree_fp.py, agent notes in .agents/local/memory/claude-auto/ (2026-10-11 audit, OfficeReader): the folder is the agent's own
# auto-memory, tracked in git by three repos (Office 326 files, Geely 88, Goods 19). A note written after the green gate changed the
# fingerprint, so the full-pass receipt no longer matched and the next Stop / push ran the whole gate again (117.6 s at Office
# 11:57:45, after a commit that only touched a memory note). The notes are not code: tree_fp.EXCLUDE now names the folder.
# Only that folder: GeelyEx2 keeps voice rules in .agents/local/memory/voice/ and verify-voice-intent.sh reads them, so a change
# there must still change the fingerprint; so must a sibling folder whose name merely starts with claude-auto.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TFP="${TFP_SCRIPT:-$DEVKIT_DIR/bin/tree_fp.py}"
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
fp() { python3 -I "$TFP" "$R"; }
BASE="$(fp)"
[ -n "$BASE" ] && ok "fingerprint computed" || { bad "no fingerprint"; exit 1; }

# 1. notes in claude-auto: tracked edit, new untracked note, nested note, deleted note -> the fingerprint does not move
printf 'note one, edited and longer\n' > "$R/$M/claude-auto/n1.md"
[ "$(fp)" = "$BASE" ] && ok "tracked claude-auto note edited: fingerprint unchanged" || bad "edit of a tracked claude-auto note moved the fingerprint"
printf 'a brand new note\n' > "$R/$M/claude-auto/n2.md"
[ "$(fp)" = "$BASE" ] && ok "new untracked claude-auto note: fingerprint unchanged" || bad "a new claude-auto note moved the fingerprint"
mkdir -p "$R/$M/claude-auto/sub" && printf 'deep\n' > "$R/$M/claude-auto/sub/deep.md"
[ "$(fp)" = "$BASE" ] && ok "note in a sub-folder of claude-auto: fingerprint unchanged" || bad "a nested claude-auto note moved the fingerprint"
rm -f "$R/$M/claude-auto/n1.md"
[ "$(fp)" = "$BASE" ] && ok "claude-auto note deleted: fingerprint unchanged" || bad "deleting a claude-auto note moved the fingerprint"
# the real folder holds more than .md notes: reviewer-log.jsonl (review_log.py) and json state files
printf '{"a":1}\n' > "$R/$M/claude-auto/reviewer-log.jsonl"
printf '{"b":2}\n' > "$R/$M/claude-auto/state.json"
[ "$(fp)" = "$BASE" ] && ok "reviewer-log.jsonl and a .json file in claude-auto: fingerprint unchanged" || bad "a non-.md file in claude-auto moved the fingerprint"
printf '{"a":1}\n{"a":2}\n' > "$R/$M/claude-auto/reviewer-log.jsonl"
[ "$(fp)" = "$BASE" ] && ok "reviewer-log.jsonl appended: fingerprint unchanged" || bad "appending to reviewer-log.jsonl moved the fingerprint"

# 2. everything else still counts
printf 'rule one, changed\n' > "$R/$M/voice/VOICE-RULES.md"
[ "$(fp)" != "$BASE" ] && ok "a voice rule (memory/voice) changed: fingerprint moves" || bad "memory/voice change did not move the fingerprint (too wide an exclude)"
git -C "$R" checkout -q -- "$M/voice/VOICE-RULES.md"
[ "$(fp)" = "$BASE" ] && ok "voice rule restored: fingerprint back to the base" || bad "fingerprint did not return to the base after the restore"
printf 'sibling one, changed\n' > "$R/$M/claude-autoX/s.md"
[ "$(fp)" != "$BASE" ] && ok "folder named claude-autoX changed: fingerprint moves (prefix is a whole path part)" || bad "claude-autoX change did not move the fingerprint"
git -C "$R" checkout -q -- "$M/claude-autoX/s.md"
printf 'fun ok() = 22\n' > "$R/src/Core.kt"
[ "$(fp)" != "$BASE" ] && ok "source file changed: fingerprint moves" || bad "a source change did not move the fingerprint"
git -C "$R" checkout -q -- src/Core.kt
printf 'x\n' > "$R/$M/top-level.md"
[ "$(fp)" != "$BASE" ] && ok "file directly under memory/ (not claude-auto): fingerprint moves" || bad "memory/top-level.md change did not move the fingerprint"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
