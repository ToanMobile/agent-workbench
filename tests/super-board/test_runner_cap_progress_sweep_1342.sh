#!/usr/bin/env bash
# #1342 part B (19/11): run.md says "a different root-cause hash resets the counter" but a card Blocked at rebuild_cap stayed Blocked even when each
# round found NEW findings (#1318, #1328, #1333). `sweep_cap_progress` releases such a card:
#  - Blocked + loop:rebuild-N >= cap + the last two refusals (reviewer / merge-queue / orchestrator comments) hash differently
#    -> label lowered to loop:rebuild-(cap-1), card Ready, one comment; once per distinct latest hash;
#  - same hash twice                      -> stays Blocked;
#  - per-card ceiling SB_CAP_PROGRESS_MAX -> stays Blocked;
#  - needs-you / human-gated labels, or a 💳 🔐 🧑 🙋 blocker -> never swept;
#  - comments unreadable                  -> skipped, no halt.
# Offline: the comment reader `cap_progress_comments` is a seam the test overrides. bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-cap-progress-1342.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_GITHUB_READ_STRICT SB_CAP_PROGRESS_MAX
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
REBUILD_CAP=2
SWEPT_CARDS=""
log() { echo "$*" >> "$TMP/log"; }
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; return 0; }

# cap_progress_comments <issue>: JSON array of {body} oldest first, from $TMP/c-<issue>.json (a missing file = unreadable).
cap_progress_comments() { cat "$TMP/c-$1.json" 2>/dev/null; }

card() {   # card <number> <labels-json>
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"Blocked\",\"labels\":$2,\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"c\"}}]}"
}
comments() {   # comments <number> <body1> <body2> ...: write the issue's comment list
  local n="$1"; shift
  python3 -c 'import json,sys; print(json.dumps([{"body": b} for b in sys.argv[1:]]))' "$@" > "$TMP/c-$n.json"
}
reset() { : > "$TMP/writes"; : > "$TMP/log"; SWEPT_CARDS=""; : > "$INFLIGHT_DIR/swept-cards"; }

B1=$'[merge-queue] [blocker] 🛑 blocked · 🛡 rebuild_cap 2 reached\nEvidence: tests/foo.sh:12 AssertionError boom\ntests/foo.sh:30 AssertionError again'
B2=$'[reviewer] [blocker] 🛑 blocked · 🛡 rebuild_cap 2 đã đạt\nEvidence: .claude/skills/super-review/SKILL.md:111 là 20207 byte\n.claude/bin/x.sh:5 sai'

# 1) different hashes -> released
reset; card 7 '["bug","loop:rebuild-2"]'; comments 7 "$B1" "$B2"
sweep_cap_progress; rc=$?
[ "$rc" -eq 0 ] && ok "progress: returns 0 (a card moved)" || fail "progress: rc=$rc"
grep -q "move PVTI_7 Ready" "$TMP/writes" && ok "progress: card #7 -> Ready" || fail "not moved: $(tr '\n' ';' < "$TMP/writes")"
grep -q -- "--add-label loop:rebuild-1" "$TMP/writes" && grep -q -- "--remove-label loop:rebuild-2" "$TMP/writes" \
  && ok "progress: loop:rebuild-2 -> loop:rebuild-1" || fail "label not lowered: $(tr '\n' ';' < "$TMP/writes")"
grep -q "issue comment 7" "$TMP/writes" && ok "progress: one comment" || fail "no comment"

# 2) the same refusal twice -> stays
reset; card 7 '["bug","loop:rebuild-2"]'; comments 7 "$B1" "$B1"
sweep_cap_progress; rc=$?
grep -q "move PVTI_7" "$TMP/writes" && fail "same hash twice was released" || ok "same hash twice: stays Blocked"

# 3) once per distinct latest hash: a second sweep with the same latest comment does nothing
reset; card 7 '["bug","loop:rebuild-2"]'; comments 7 "$B1" "$B2"
sweep_cap_progress; : > "$TMP/writes"; sweep_cap_progress
grep -q "move PVTI_7" "$TMP/writes" && fail "released twice for one hash" || ok "once per distinct latest hash"

# 4) ceiling
reset; card 7 '["bug","loop:rebuild-2"]'; comments 7 "$B1" "$B2"
printf '7:cap:aaaaaaaaaaaa\n7:cap:bbbbbbbbbbbb\n7:cap:cccccccccccc\n' > "$INFLIGHT_DIR/swept-cards"
sweep_cap_progress
grep -q "move PVTI_7" "$TMP/writes" && fail "ceiling ignored" || ok "ceiling SB_CAP_PROGRESS_MAX (3): stays Blocked"

# 5) human-owned cards are never swept
reset; card 7 '["bug","loop:rebuild-2","needs-you"]'; comments 7 "$B1" "$B2"
sweep_cap_progress
grep -q "move PVTI_7" "$TMP/writes" && fail "needs-you card swept" || ok "needs-you: never swept"
reset; card 7 '["bug","loop:rebuild-2"]'; comments 7 "$B1" $'[reviewer] [blocker] 🛑 blocked · 🙋 cần người quyết\nEvidence: a.sh:1 x'
sweep_cap_progress
grep -q "move PVTI_7" "$TMP/writes" && fail "🙋 blocker swept" || ok "🙋 blocker: never swept"

# 6) below the cap -> not a candidate
reset; card 7 '["bug","loop:rebuild-1"]'; comments 7 "$B1" "$B2"
sweep_cap_progress
grep -q "move PVTI_7" "$TMP/writes" && fail "below-cap card swept" || ok "below the cap: not a candidate"

# 7) unreadable comments -> skipped, no halt, no move
reset; card 7 '["bug","loop:rebuild-2"]'; rm -f "$TMP/c-7.json"
sweep_cap_progress; rc=$?
{ [ "$rc" -ne 0 ] && ! grep -q "move PVTI_7" "$TMP/writes"; } && ok "unreadable comments: skipped" || fail "unreadable comments: rc=$rc"

echo
[ "$FAILS" -eq 0 ] && { echo "test_runner_cap_progress_sweep_1342: PASS"; exit 0; } || { echo "test_runner_cap_progress_sweep_1342: FAIL ($FAILS)"; exit 1; }
