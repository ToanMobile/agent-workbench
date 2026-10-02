#!/usr/bin/env bash
# Regression test: bin/post-fix-gate.py when a change MOVES a test file the matrix names.
# The change under audit cannot be trusted with its own matrix, so the gate runs the BASE matrix. But
# once the change moves a test, that base command names a path the change removed: exit 127, REJECT, and
# nothing could rename a matrix test (2026-10-02: tests/ regrouped into tests/<group>/). git's own rename
# record re-points the base command; the matrix edit counts as a pure rename (no human-review problem)
# only when it is EXACTLY that re-pointing — any other edit stays the review problem.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# mk <dir> <exit code of tests/t1.sh>: a repo whose matrix runs tests/t1.sh; sets BASE to its commit
mk() {
  mkdir -p "$1/src" "$1/tests" "$1/.agents"
  ( cd "$1" && git init -q . && git config user.email t@t && git config user.name t
    echo "x = 1" > src/a.py
    printf '#!/bin/sh\nexit %s\n' "$2" > tests/t1.sh
    cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"A","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-R","name":"a","command":"sh tests/t1.sh"}]}]}
JSON
    cp matrix.json .agents/regression_matrix.active.json
    git add -A && git commit -qm init )
  BASE="$(git -C "$1" rev-parse HEAD)"
}
# gate <dir> → $TMP/out, $RC; the matrix is the one in the repo (--matrix), the audited range is BASE..worktree
gate() {
  ( cd "$1" && CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --matrix "$1/matrix.json" --lang en --json --run-tests --diff "$BASE" ) >"$TMP/out" 2>&1
  RC=$?
}
# field <python expr over d>: the gate's last JSON line
field() { python3 - "$TMP/out" "$1" <<'PY'
import json, sys
line = [l for l in open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines() if l.startswith("{")][-1]
d = json.loads(line)
t = {x["id"]: x for x in d["regression_tests"]}
print(eval(sys.argv[2]))
PY
}
move() { # <dir>: git mv the test into tests/grp/ and re-point the command in matrix.json
  ( cd "$1" && mkdir -p tests/grp && git mv tests/t1.sh tests/grp/t1.sh && echo "x = 2" > src/a.py )
}

# ── A. the matrix edit IS the rename: the moved test is what runs, no review problem ──────────────
R="$TMP/a"; mk "$R" 0; move "$R"
( cd "$R" && sed -i.bak 's#sh tests/t1.sh#sh tests/grp/t1.sh#' matrix.json && rm matrix.json.bak && git add -A && git commit -qm "move" )
gate "$R"
[ "$RC" = 0 ] && [ "$(field "t['REG-R']['status']")" = PASS ] \
  && ok "A pure rename of a matrix test: the moved test runs and passes (exit 0)" \
  || fail "A rename of a matrix test rejected: rc=$RC status=$(field "t['REG-R']['status']") exit=$(field "t['REG-R'].get('exit_code')") problem=$(field "d.get('matrix_problem')")"
[ -z "$(field "d.get('matrix_problem') or ''")" ] && ok "A the pure rename is not a matrix-review problem" \
  || fail "A pure rename still flagged: $(field "d.get('matrix_problem')")"

# ── B. the rename must not launder a weakened matrix: `exit 1` -> `true` shape ────────────────────
R="$TMP/b"; mk "$R" 1; move "$R"
( cd "$R" && sed -i.bak 's#sh tests/t1.sh#true#' matrix.json && rm matrix.json.bak && git add -A && git commit -qm "move + weaken" )
gate "$R"
[ "$RC" != 0 ] && [ "$(field "t['REG-R']['status']")" != PASS ] && [ "$(field "t['REG-R'].get('exit_code')")" = 1 ] \
  && ok "B weakened matrix + rename: the BASE command still runs (re-pointed to the moved test) and fails" \
  || fail "B weakened matrix escaped or ran the missing path: rc=$RC status=$(field "t['REG-R']['status']") exit=$(field "t['REG-R'].get('exit_code')")"
[ -n "$(field "d.get('matrix_problem') or ''")" ] && ok "B the matrix edit stays a review problem" || fail "B no matrix problem"

# ── C. a rename plus any other matrix edit is still the review problem ────────────────────────────
R="$TMP/c"; mk "$R" 0; move "$R"
( cd "$R" && sed -i.bak 's#sh tests/t1.sh#sh tests/grp/t1.sh \&\& true#' matrix.json && rm matrix.json.bak && git add -A && git commit -qm "move + extra" )
gate "$R"
[ -n "$(field "d.get('matrix_problem') or ''")" ] && [ "$RC" != 0 ] \
  && ok "C rename + an extra edit: the review problem stays (exit $RC)" || fail "C mixed edit accepted: rc=$RC"

# ── D. the matrix was NOT updated for the move: say so (it would break after the push) ────────────
R="$TMP/d"; mk "$R" 0; move "$R"
( cd "$R" && git add -A && git commit -qm "move only" )
gate "$R"
printf '%s' "$(field "d.get('matrix_problem') or ''")" | grep -qi "renam" && [ "$RC" != 0 ] \
  && ok "D matrix still names the old path: the problem says the change renames it" \
  || fail "D stale matrix not reported: rc=$RC problem=$(field "d.get('matrix_problem')") exit=$(field "t['REG-R'].get('exit_code')")"

# ── E. a COPY is not a rename: the old path is still there, the edit is a plain matrix edit ───────
R="$TMP/e"; mk "$R" 0
( cd "$R" && mkdir -p tests/grp && cp tests/t1.sh tests/grp/t1.sh && echo "x = 2" > src/a.py \
  && sed -i.bak 's#sh tests/t1.sh#sh tests/grp/t1.sh#' matrix.json && rm matrix.json.bak && git add -A && git commit -qm "copy" )
gate "$R"
[ -n "$(field "d.get('matrix_problem') or ''")" ] && ok "E a copy (old path kept) is not followed: the matrix edit stays a review problem" \
  || fail "E a copy was treated as a rename"

# ── F. the pre-commit path: staged rename + staged matrix edit, commands read from HEAD ──────────
R="$TMP/f"; mk "$R" 0; move "$R"
( cd "$R" && sed -i.bak 's#sh tests/t1.sh#sh tests/grp/t1.sh#' .agents/regression_matrix.active.json && rm .agents/regression_matrix.active.json.bak \
  && git add -A )
res="$(cd "$R" && CLAUDE_PROJECT_DIR="$R" DEVKIT_DIR="$DEVKIT_DIR" python3 - <<'PY'
import importlib.util, os
spec = importlib.util.spec_from_file_location("pfg", os.environ["DEVKIT_DIR"] + "/bin/post-fix-gate.py")
pfg = importlib.util.module_from_spec(spec); spec.loader.exec_module(pfg)
os.environ["DEVKIT_PRECOMMIT_TESTS"] = "all"
ran, failed, skipped, untested = pfg.run_precommit_tests(["tests/grp/t1.sh", "src/a.py"])
print("ran=%s failed=%s" % (ran, [(f[0], f[1]) for f in failed]))
PY
)"
printf '%s' "$res" | tail -1 | grep -q "ran=\['REG-R'\] failed=\[\]" \
  && ok "F pre-commit: a staged rename runs the moved test and passes" || fail "F pre-commit: $(printf '%s' "$res" | tail -1)"

[ "$FAILS" -eq 0 ] && echo "gate matrix rename: all checks passed" || { echo "gate matrix rename: $FAILS FAILED"; exit 1; }
