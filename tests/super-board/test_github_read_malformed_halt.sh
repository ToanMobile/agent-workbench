#!/usr/bin/env bash
# Regression test (14/11 07:00): a read with an empty `--owner` or a project number that is not a positive integer
# (`project field-list 0 --owner ""`, a fixture or unset config) names no repository, so the foreign-read guard let it
# write the shared board halt; the watchdog then replayed the same malformed read every minute and the real board stayed
# halted for 2 h. Such a read is a caller bug, not a GitHub failure: it still raises ReadHalted for its caller, but never
# writes the board halt, and a malformed halt already on disk is set aside instead of stopping the board.
# A well-formed repo-less read (`project item-list 1 --owner ToanMobile`) still halts (fail closed). Bash 3.2 compatible.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-malformed-halt.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
R="$TMP/home"
mkdir -p "$R"
git -C "$R" init -q -b main . && git -C "$R" remote add origin https://github.com/ToanMobile/home.git
unset SB_GITHUB_HALT_FILE SB_REPO_PATH
HALT="$R/.claude/super-board/github-halt.json"

halt_with() {   # $1 = operation args as JSON list
  ( cd "$R" && python3 - "$READ" "$1" <<'PY' 2>&1 )
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('gr', sys.argv[1]); mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
try:
    mod.halt('test', 3, {'args': json.loads(sys.argv[2]), 'kind': 'fields', 'meta': None})
except mod.ReadHalted:
    print('ReadHalted')
PY
}

for op in '["project","field-list","0","--owner","","--format","json"]' \
          '["project","item-list","null","--owner","null","--format","json"]' \
          '["project","field-list","1","--owner","","--format","json"]' \
          '["project","item-list","-3","--owner","ToanMobile"]'; do
  out=$(halt_with "$op")
  { printf '%s\n' "$out" | grep -qx ReadHalted && [ ! -e "$HALT" ]; } \
    && ok "malformed read $op raises ReadHalted and writes no board halt" \
    || fail "malformed read $op: halt=$([ -e "$HALT" ] && head -c 120 "$HALT" || echo none) out=$out"
  rm -f "$HALT"
done

out=$(halt_with '["project","item-list","1","--owner","ToanMobile","--format","json"]')
[ -s "$HALT" ] && ok "a well-formed repo-less read still halts the board (fail closed)" || fail "well-formed read wrote no halt: $out"
rm -f "$HALT"

check_with() {
  ( cd "$R" && python3 - "$READ" <<'PY' 2>&1 )
import importlib.util, sys
spec = importlib.util.spec_from_file_location('gr', sys.argv[1]); mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
try:
    mod.check_halt(); print('ok')
except mod.ReadHalted:
    print('ReadHalted')
PY
}
mkdir -p "$(dirname "$HALT")"
printf '%s' '{"reason":"GitHub required read failed; stopped after 3 failed attempts","attempts":3,"at":1794614405,"operation":{"args":["project","field-list","0","--owner","","--format","json"],"kind":"fields","meta":null}}' > "$HALT"
out=$(check_with)
{ printf '%s\n' "$out" | grep -qx ok && [ ! -e "$HALT" ] && ls "$(dirname "$HALT")"/github-halt-malformed-*.json >/dev/null 2>&1; } \
  && ok "check_halt: the 14/11 malformed halt is set aside, the board is not stopped" \
  || fail "malformed halt on read: out=$out halt=$([ -e "$HALT" ] && echo kept || echo gone)"
# The watchdog restarts a halted runner through `--resume`, which replays the saved read: a malformed one never passes.
printf '%s' '{"reason":"x","attempts":3,"at":1,"operation":{"args":["project","field-list","0","--owner","","--format","json"],"kind":"fields","meta":null}}' > "$HALT"
PY="$(command -v python3)"   # no gh on PATH: a replay attempt fails instead of reaching GitHub
out=$( cd "$R" && PATH="/nonexistent:/usr/bin:/bin" "$PY" "$READ" --resume 2>&1 ); rc=$?
{ [ "$rc" -eq 0 ] && [ ! -e "$HALT" ] && printf '%s\n' "$out" | grep -q "malformed"; } \
  && ok "--resume (watchdog) sets the malformed halt aside without replaying it" \
  || fail "--resume on malformed halt: rc=$rc halt=$([ -e "$HALT" ] && echo kept || echo gone) out=$out"
rm -f "$HALT"
printf '%s' '{"reason":"x","attempts":3,"at":1,"operation":{"args":["project","field-list","1","--owner","ToanMobile","--format","json"],"kind":"fields"}}' > "$HALT"
out=$(check_with)
printf '%s\n' "$out" | grep -qx ReadHalted && [ -e "$HALT" ] && ok "check_halt: a well-formed project read halt still stops the board" || fail "well-formed halt on read: out=$out"
rm -f "$HALT"

[ "$FAILS" -eq 0 ] && echo "test_github_read_malformed_halt: PASS" || { echo "test_github_read_malformed_halt: FAIL ($FAILS)"; exit 1; }
