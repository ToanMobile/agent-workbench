#!/usr/bin/env bash
# Regression #1384: set_card_status — after recover_read_halt releases a first read halt (79), a SECOND 79 from
# project_node_id must exit 79 (callers swallow a plain `return 79`); a non-79 second failure still returns its rc.
# Bash 3.2 compatible.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-second-halt-1384.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_GITHUB_READ_STRICT SB_READ_SKIP_MAX
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
log() { echo "$*" >> "$TMP/log"; }
tick_sleep() { :; }
export SB_HALT_RECOVER_DELAY=1 SB_HALT_RECOVER_MAX=3
# fake github-read: --resume always releases (removes the halt file)
GH="$TMP/ghread"
printf '#!/usr/bin/env python3\nimport os,sys\nif "--resume" in sys.argv:\n    p=os.environ["HALT_FILE"]\n    os.path.exists(p) and os.remove(p)\nsys.exit(0)\n' > "$GH"; chmod +x "$GH"
export SB_GITHUB_READ="$GH" HALT_FILE="$TMP/halted"
resolve_status_field() { return 0; }; status_option_id() { echo opt; }; gh_checkpoint() { :; }
gh_write_once() { echo write >> "$TMP/writes"; return 0; }
# project_node_id stub: call 1 -> 79; call 2 -> $SECOND_RC (counter in a file: it runs in a $( ) subshell)
project_node_id() {
  local n; n=$(cat "$TMP/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$TMP/n"
  if [ "$n" -eq 1 ]; then return 79; fi
  [ "$SECOND_RC" = 0 ] && { echo PID; return 0; }
  return "$SECOND_RC"
}
reset() { rm -f "$TMP/n" "$TMP/writes"; : > "$TMP/halted"; HALT_RECOVERS=0; : > "$TMP/log"; }

# A: second 79 after a successful release -> the runner exits 79 (not a plain return)
reset; SECOND_RC=79
( set_card_status item1 Blocked; echo survived ) > "$TMP/a.out" 2>/dev/null; rc=$?
[ "$rc" = 79 ] && ! grep -q survived "$TMP/a.out" && [ ! -e "$TMP/writes" ] \
  && ok "A: second read halt 79 after --resume exits 79" || fail "A: rc=$rc out=$(tr '\n' ' ' < "$TMP/a.out")"
# B: second failure with another rc (10) -> still returns 10, no exit
reset; SECOND_RC=10
( set_card_status item1 Blocked; echo "rc=$?" ) > "$TMP/b.out" 2>/dev/null
grep -q '^rc=10$' "$TMP/b.out" && ok "B: non-79 second failure returns its rc" || fail "B: $(tr '\n' ' ' < "$TMP/b.out")"
# C: second read succeeds -> write goes through
reset; SECOND_RC=0
( set_card_status item1 Blocked; echo "rc=$?" ) > "$TMP/c.out" 2>/dev/null
grep -q '^rc=0$' "$TMP/c.out" && [ -e "$TMP/writes" ] && ok "C: released halt then clean read writes" || fail "C: $(tr '\n' ' ' < "$TMP/c.out")"
[ "$FAILS" = 0 ] && echo "ALL PASS" && exit 0
exit 1
