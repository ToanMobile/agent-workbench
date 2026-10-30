#!/usr/bin/env bash
# Regression test (#696): the gate-full tree ran at nice 10 TWICE and with ProcessType=Background — the same suite ran 4.9-7.3x slower
# than in a normal full run. The level is now set in ONE place, the plist (`/usr/bin/nice -n 10`); no ProcessType=Background, and
# bin/gate_full.py has no os.nice call of its own.
#   a. the plist written by `gate-full-schedule.sh install` has no ProcessType=Background and still starts with /usr/bin/nice -n 10;
#   b. bin/gate_full.py contains no os.nice call (checked on the AST: a comment or docstring does not count).
# Fake launchctl + temp LaunchAgents dir: nothing touches launchd or ~/Library. Bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GF="$DEVKIT_DIR/bin/gate_full.py"
SCHED="$DEVKIT_DIR/bin/gate-full-schedule.sh"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-nice-once.XXXXXX")" || { echo "✖ mktemp failed"; exit 2; }
T="$(cd "$T" && pwd)"
trap 'rm -rf "$T"' EXIT
for f in "$GF" "$SCHED"; do [ -f "$f" ] || { echo "✖ missing ${f#$DEVKIT_DIR/}"; exit 1; }; done

# a. plist — kit copy outside git (a kit in a linked worktree makes install take gate_full.py from the main checkout)
mkdir -p "$T/kit/bin" "$T/la" "$T/repo" && cp "$SCHED" "$GF" "$T/kit/bin/"
git init -q "$T/repo"
printf '#!/bin/sh\nexit 0\n' >"$T/fakelaunchctl"; chmod +x "$T/fakelaunchctl"
export DEVKIT_LAUNCH_AGENTS_DIR="$T/la" DEVKIT_LAUNCHCTL="$T/fakelaunchctl"
bash "$T/kit/bin/gate-full-schedule.sh" install --repo "$T/repo" >"$T/sched.out" 2>&1; rc=$?
PL="$(ls "$T/la"/com.toanmobile.devkit.gate-full.*.plist 2>/dev/null | head -1)"; PL="${PL:-$T/la/none.plist}"
px() { plutil -extract "$1" raw -o - "$PL" 2>/dev/null; }
chk "a0. install exit 0 and a plist exists" '[ "$rc" = 0 ] && [ -f "$PL" ]' "rc=$rc $(tail -3 "$T/sched.out")"
chk "a1. plist has no ProcessType=Background" '[ "$(px ProcessType)" != Background ]' "ProcessType=$(px ProcessType)"
chk "a2. plist still starts with /usr/bin/nice -n 10" \
  '[ "$(px ProgramArguments.0)" = /usr/bin/nice ] && [ "$(px ProgramArguments.1)" = -n ] && [ "$(px ProgramArguments.2)" = 10 ]'

# b. no os.nice call in gate_full.py (AST, so comments and docstrings do not match)
python3 -I - "$GF" <<'PY' >"$T/nice.out" 2>&1; brc=$?
import ast, sys
src = open(sys.argv[1], encoding="utf-8").read()
hits = [n.lineno for n in ast.walk(ast.parse(src)) if isinstance(n, ast.Call)
        and ((isinstance(n.func, ast.Attribute) and n.func.attr == "nice") or (isinstance(n.func, ast.Name) and n.func.id == "nice"))]
print("os.nice calls at lines: %s" % hits)
sys.exit(1 if hits else 0)
PY
chk "b1. bin/gate_full.py has no os.nice call" '[ "$brc" = 0 ]' "$(cat "$T/nice.out")"

[ "$fails" = 0 ] && { echo "OK"; exit 0; }
echo "FAIL: $fails"
exit 1
