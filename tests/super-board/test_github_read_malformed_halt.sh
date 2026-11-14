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
          '["project","view","abc","--owner","ToanMobile"]'; do
  out=$(halt_with "$op")
  { printf '%s\n' "$out" | grep -qx ReadHalted && [ ! -e "$HALT" ]; } \
    && ok "malformed read $op raises ReadHalted and writes no board halt" \
    || fail "malformed read $op: halt=$([ -e "$HALT" ] && head -c 120 "$HALT" || echo none) out=$out"
  rm -f "$HALT"
done

for op in '["project","item-list","1","--owner","ToanMobile","--format","json"]' \
          '["project","item-list","--owner","ToanMobile","1","--format","json"]' \
          '["project","field-list","01","--owner","ToanMobile"]' \
          '["project","item-list","-L","100","--owner","ToanMobile","1"]'; do
  out=$(halt_with "$op")
  [ -s "$HALT" ] && ok "well-formed repo-less read $op still halts the board (fail closed)" || fail "well-formed read $op wrote no halt: $out"
  rm -f "$HALT"
done

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
{ [ "$rc" -eq 0 ] && [ ! -e "$HALT" ] && printf '%s\n' "$out" | grep -q "malformed.*kept at .*github-halt-malformed-"; } \
  && ok "--resume (watchdog) sets the malformed halt aside without replaying it" \
  || fail "--resume on malformed halt: rc=$rc halt=$([ -e "$HALT" ] && echo kept || echo gone) out=$out"
rm -f "$HALT"
# Race on the --resume path: a REAL halt replaces the malformed one between the read and the rename. It must go back
# into place, and --resume must report halted (79), not 0.
printf '%s' '{"reason":"x","attempts":3,"at":1,"operation":{"args":["project","field-list","0","--owner","","--format","json"],"kind":"fields","meta":null}}' > "$HALT"
race_resume() {
  ( cd "$R" && PATH="/nonexistent:/usr/bin:/bin" "$PY" - "$READ" "$HALT" <<'PY' 2>&1 )
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location('gr', sys.argv[1]); mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
real_replace, done, halt_file = os.replace, [], sys.argv[2]
def racing_replace(src, dst):
    if not done:
        done.append(1)
        open(halt_file, 'w').write('{"reason":"real","attempts":3,"at":2,"operation":{"args":["project","field-list","1","--owner","ToanMobile"],"kind":"fields"}}')
    return real_replace(src, dst)
mod.os.replace = racing_replace
sys.argv = ['read', '--resume']
print('rc=%s' % mod.main())
PY
}
out=$(race_resume)
{ printf '%s\n' "$out" | grep -q "rc=79" && grep -q '"real"' "$HALT" 2>/dev/null; } \
  && ok "--resume race: a real halt written between read and rename is put back, rc=79" \
  || fail "--resume race: out=$out halt=$(head -c 60 "$HALT" 2>/dev/null)"
printf '%s\n' "$out" | grep -qi reconcil && fail "--resume race: stderr names reconcile (watchdog would take the write-halt path)" \
  || ok "--resume race: no reconcile wording, the watchdog keeps halt-wait"
rm -f "$HALT"

set_aside_with() {   # $1 = gone|unreadable → prints what _set_aside returned and whether the halt is in place
  ( cd "$R" && "$PY" - "$READ" "$HALT" "$1" <<'PY' 2>&1 )
import importlib.util, sys, pathlib
spec = importlib.util.spec_from_file_location('gr', sys.argv[1]); mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
path, mode = pathlib.Path(sys.argv[2]), sys.argv[3]
if mode == 'gone':
    print('ret=%r' % mod._set_aside(path, 'x', 'malformed'))
else:
    text = path.read_text()
    real_read = pathlib.Path.read_text
    def failing_read(self, *a, **k):
        if 'github-halt-malformed-' in self.name:
            raise PermissionError('denied')
        return real_read(self, *a, **k)
    pathlib.Path.read_text = failing_read
    print('ret=%r' % mod._set_aside(path, text, 'malformed'))
print('in_place=%s' % path.exists())
PY
}
rm -f "$HALT"
out=$(set_aside_with gone)
printf '%s\n' "$out" | grep -q "ret='already gone'" && ok "_set_aside: a record another check took first counts as gone" || fail "gone: $out"
printf '%s' '{"reason":"real","attempts":3,"at":2,"operation":{"args":["project","field-list","1","--owner","ToanMobile"],"kind":"fields"}}' > "$HALT"
out=$(set_aside_with unreadable)
{ printf '%s\n' "$out" | grep -q "ret=None" && printf '%s\n' "$out" | grep -q "in_place=True"; } \
  && ok "_set_aside: an error after the rename puts the record back (the board stays halted)" || fail "unreadable: $out"
rm -f "$HALT"
out=$(halt_with '["project","item-list","-3","--owner","ToanMobile"]')
{ printf '%s\n' "$out" | grep -qx ReadHalted && [ ! -e "$HALT" ]; } && ok "a negative project number is still malformed" || fail "-3: $out"
rm -f "$HALT"
printf '%s' '{"reason":"x","attempts":3,"at":1,"operation":{"args":["project","field-list","1","--owner","ToanMobile","--format","json"],"kind":"fields"}}' > "$HALT"
out=$(check_with)
printf '%s\n' "$out" | grep -qx ReadHalted && [ -e "$HALT" ] && ok "check_halt: a well-formed project read halt still stops the board" || fail "well-formed halt on read: out=$out"
rm -f "$HALT"

[ "$FAILS" -eq 0 ] && echo "test_github_read_malformed_halt: PASS" || { echo "test_github_read_malformed_halt: FAIL ($FAILS)"; exit 1; }
