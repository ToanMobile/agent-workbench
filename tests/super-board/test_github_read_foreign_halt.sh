#!/usr/bin/env bash
# Regression test (24/10): a GitHub read for ANOTHER repository must never write the shared board halt.
# Tests run from a linked worktree resolve halt_path() through `git rev-parse --git-common-dir` to the MAIN checkout;
# three approval tests read `o/r` PR 7 against the real gh and wrote .claude/super-board/github-halt.json there twice
# (05:21 and 07:45), halting the real board for hours. github-read now refuses to write a halt whose operation names a
# repository other than the checkout's origin; a read of the checkout's own repository still halts as before.
# Bash 3.2 compatible.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-foreign-halt.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
R="$TMP/home"
mkdir -p "$R"
git -C "$R" init -q -b main . && git -C "$R" remote add origin https://github.com/ToanMobile/home.git
unset SB_GITHUB_HALT_FILE SB_REPO_PATH

halt_with() {   # $1 = operation args as JSON list → prints the exception type halt() raised
  ( cd "$R" && python3 - "$READ" "$1" <<'PY' 2>&1 )
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('gr', sys.argv[1]); mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
try:
    mod.halt('test', 1, {'args': json.loads(sys.argv[2]), 'kind': 'approval', 'meta': None})
except mod.ReadHalted:
    print('ReadHalted')
PY
}
HALT="$R/.claude/super-board/github-halt.json"

out=$(halt_with '["api","graphql","-F","owner=o","-F","repo=r","-F","pr=7"]')
printf '%s\n' "$out" | grep -qx ReadHalted && ok "foreign read still raises ReadHalted for its caller" || fail "foreign read: $out"
printf '%s\n' "$out" | grep -q "HALT not recorded" && ok "foreign read says why no halt was recorded" || fail "no notice: $out"
[ ! -e "$HALT" ] && ok "foreign read (o/r) writes no shared board halt" || fail "foreign read wrote $HALT: $(head -c 160 "$HALT")"
rm -f "$HALT"

for form in '"--repo","other/repo"' '"-R","other/repo"' '"--repo=other/repo"'; do
  out=$(halt_with "[\"pr\",\"view\",\"7\",$form]")
  { [ ! -e "$HALT" ] && printf '%s\n' "$out" | grep -qx ReadHalted; } \
    && ok "foreign $form writes no shared board halt and still raises ReadHalted" || fail "foreign $form: halt=$([ -e "$HALT" ] && echo written || echo none) out=$out"
  rm -f "$HALT"
done

out=$(halt_with '["api","graphql","-F","owner=ToanMobile","-F","repo=home","-F","pr=7"]')
[ -s "$HALT" ] && ok "a read of the checkout's own repository still halts the board" || fail "home read wrote no halt"
rm -f "$HALT"

for home_form in "https://github.com/ToanMobile/home" "github.com/ToanMobile/home" "https://github.com/toanmobile/HOME.git"; do
  out=$(halt_with "[\"pr\",\"view\",\"7\",\"--repo\",\"$home_form\"]")
  [ -s "$HALT" ] && ok "home repo written as $home_form still halts (no fail-open)" || fail "$home_form was treated as foreign"
  rm -f "$HALT"
done

out=$(halt_with '["project","item-list","1","--owner","ToanMobile"]')
[ -s "$HALT" ] && ok "a read that names no repository still halts the board (fail closed)" || fail "repo-less read wrote no halt"

[ "$FAILS" -eq 0 ] && echo "test_github_read_foreign_halt: PASS" || { echo "test_github_read_foreign_halt: FAIL ($FAILS)"; exit 1; }
