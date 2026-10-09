#!/usr/bin/env bash
# Regression test: bin/post-fix-gate.py must not crash, hang on or leave behind what it starts (audit 2026-10-09).
#  A3  a dirty submodule or an untracked nested git repo (vendor/tool/) was "1 file could not be read": exit 2 for ever.
#  A8  a non-UTF-8 file name crashed the gate AFTER it printed PASS (UnicodeDecodeError in head_and_dirty), exit 1 with
#      a traceback; --brief lost the whole output (run_brief caught only SystemExit).
#  A9  a SIGTERM / SIGHUP / SIGINT left the suites running: they run in their own session (start_new_session) and only
#      the vacuity re-run was killed. The gate must still die by that signal.
#  A10 no git on PATH: FileNotFoundError traceback, exit 1 (reads as REJECT) instead of a clear UNVERIFIED (exit 2).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
GATE_PID=""
cleanup() {
  [ -n "$GATE_PID" ] && kill -KILL "$GATE_PID" 2>/dev/null
  for f in "$TMP"/*.pid; do [ -f "$f" ] && kill -KILL -- "-$(cat "$f")" 2>/dev/null; done   # the suite's whole group
  rm -rf "$TMP"
}
trap cleanup EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
PY="$(python3 -c 'import sys; print(sys.executable)')"

mk() {
  local d="$TMP/$1"
  mkdir -p "$d/src" "$d/tests" && cd "$d" || exit 1
  git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf 'def f():\n    return 1\n' > src/core.py
  printf '#!/bin/sh\ngrep -q return src/core.py\n' > tests/test_core.sh
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*","data/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/test_core.sh"}]}]}
JSON
  git add -A && git commit -qm init
}
gate() {
  OUT="$(CLAUDE_PROJECT_DIR="$PWD" POSTFIX_GATE_FORCE_FULL=1 "$PY" "$GATE" --matrix "$PWD/matrix.json" --lang en "$@" 2>&1)"; RC=$?
}
expect_rc() {
  if [ "$RC" = "$2" ]; then ok "$1 (exit $RC)"
  else bad "$1: exit $RC, want $2"; printf '%s\n' "$OUT" | grep -v '^{' | grep -E '✖|VERDICT|Could not|Traceback|Error' | head -8; fi
}

# ── A3: a nested repository is a note, not an unreadable file ────────────────────────────────────────────────
mk nested
mkdir -p vendor/tool && (cd vendor/tool && git init -q . && printf 'x\n' > a && git add a \
  && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm x)
printf 'def f():\n    return 2\n' > src/core.py
gate --run-tests --full
expect_rc "A3: an untracked nested git repo (vendor/tool/) does not make the run UNVERIFIED" 0
printf '%s\n' "$OUT" | grep -q "vendor/tool" && ok "A3: vendor/tool/ is still named in the output" \
  || bad "A3: vendor/tool/ is not named at all"

mk submodule
git init -q "$TMP/subsrc" && (cd "$TMP/subsrc" && printf 'x\n' > a && git add a \
  && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm x)
git -c protocol.file.allow=always submodule add -q "$TMP/subsrc" libs/sub >/dev/null 2>&1 && git commit -qm sub
printf 'y\n' > libs/sub/a
printf 'def f():\n    return 2\n' > src/core.py
gate --run-tests --full
expect_rc "A3: a dirty submodule (libs/sub) does not make the run UNVERIFIED" 0

mk unreadable_control
printf 'X = 1\n' > src/pipe.py && git add -A && git commit -qm pipe
printf 'def f():\n    return 2\n' > src/core.py
rm src/pipe.py && mkfifo src/pipe.py      # git lists it as modified; it is neither a file nor a directory
gate --run-tests --full
expect_rc "A3 control: a tracked file replaced by a FIFO is still a file that could not be read" 2

# ── A8: a non-UTF-8 path never crashes the gate (git index route: works where the filesystem refuses the name) ──
mk latin1
blob="$(printf 'x\n' | git hash-object -w --stdin)"
git update-index --add --cacheinfo "100644,$blob,$(printf 'data/caf\351.txt')" && git commit -qm "latin-1 name"
printf 'def f():\n    return 2\n' > src/core.py      # the latin-1 file is absent from the tree: a deletion
gate --run-tests --full
expect_rc "A8: a deleted Latin-1 path: the run ends with its verdict" 0
printf '%s\n' "$OUT" | grep -q Traceback && bad "A8: a traceback was printed" || ok "A8: no traceback"
[ -f .git/postfix-gate/full_pass.json ] && ok "A8: the full-pass receipt was written" || bad "A8: no full-pass receipt"
gate --run-tests --full --brief
printf '%s\n' "$OUT" | grep -q "VERDICT" && ok "A8: --brief shows the verdict" || bad "A8: --brief lost the verdict"
if printf 'x = 1\n' > "$(printf 'lib_\351.py')" 2>/dev/null; then   # code no rule watches: an UNCOVERED checklist row
  gate --run-tests --full
  expect_rc "A8: an untracked Latin-1 code file: the run ends with its verdict (uncovered: UNVERIFIED)" 2
  printf '%s\n' "$OUT" | grep -q Traceback && bad "A8: a traceback for the untracked Latin-1 file" || ok "A8: no traceback for it"
else
  ok "A8: (this filesystem refuses non-UTF-8 names: the untracked-file case cannot occur here)"
fi
# --brief keeps the output when main() raises (any exception, not only SystemExit)
res="$("$PY" - "$GATE" <<'EOF' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gate", sys.argv[1])
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
def boom():
    print("  ✖ before the crash")
    print("  POST-FIX AUDIT GATE VERDICT: PASS")
    raise RuntimeError("late crash")
g.main = boom
try:
    g.run_brief()
except RuntimeError:
    print("RERAISED")
EOF
)"
printf '%s\n' "$res" | grep -q "VERDICT: PASS" && ok "A8: --brief prints the kept output when main() raises" \
  || bad "A8: --brief lost the output when main() raised: $(printf '%s' "$res" | tail -3)"
printf '%s\n' "$res" | grep -q "RERAISED" && ok "A8: --brief re-raises the exception (exit status unchanged)" \
  || bad "A8: --brief swallowed the exception"

# ── A10: no git on PATH ─────────────────────────────────────────────────────────────────────────────────────────
mk nogit
printf 'def f():\n    return 2\n' > src/core.py
mkdir -p "$TMP/nogit-bin"
for mode in "" "--brief"; do
  OUT="$(PATH="$TMP/nogit-bin" CLAUDE_PROJECT_DIR="$PWD" "$PY" "$GATE" --matrix "$PWD/matrix.json" --lang en --run-tests --full $mode 2>&1)"; RC=$?
  expect_rc "A10: no git on PATH ${mode:-(plain)}: UNVERIFIED" 2
  printf '%s\n' "$OUT" | grep -q Traceback && bad "A10 ${mode:-(plain)}: a traceback was printed" \
    || { printf '%s\n' "$OUT" | grep -qi "git" && ok "A10 ${mode:-(plain)}: a clear message names git" || bad "A10 ${mode:-(plain)}: no message about git"; }
done

# ── A9: a signal to the gate kills the suites it started, and the gate dies by that signal ─────────────────────
# Start python with SIGINT at its default (a background job of a script inherits SIGINT ignored); it execs the gate, so
# $! is the gate's own pid (a shell function run with & would be a subshell: the signal would never reach the gate).
LAUNCH='import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execv(sys.argv[1], sys.argv[1:])'
mk signals
cat > tests/slow.sh <<EOF
#!/bin/sh
echo \$\$ > "$TMP/\$1.pid"
sleep 60
EOF
for kind in alone grouped; do
  if [ "$kind" = alone ]; then
    cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-S","name":"slow","command":"sh tests/slow.sh s1"}]}]}
JSON
  else
    cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"sh tests/slow.sh s1","parallel_safe":true},
                               {"id":"REG-B","name":"b","command":"sh tests/slow.sh s2","parallel_safe":true}]}]}
JSON
  fi
  git add -A && git commit -qm "$kind" && printf 'def f():\n    return 3\n' > src/core.py
  for SIG in TERM HUP INT; do
    rm -f "$TMP"/s1.pid "$TMP"/s2.pid
    CLAUDE_PROJECT_DIR="$PWD" POSTFIX_GATE_FORCE_FULL=1 FLAKY_RETRY=0 "$PY" -c "$LAUNCH" "$PY" "$GATE" \
      --matrix "$PWD/matrix.json" --lang en --run-tests --full >"$TMP/gate.out" 2>&1 &
    GATE_PID=$!
    want="$TMP/s1.pid"; [ "$kind" = grouped ] && want="$TMP/s2.pid"
    for _ in $(seq 1 300); do [ -s "$TMP/s1.pid" ] && [ -s "$want" ] && break; sleep 0.1; done
    if [ ! -s "$TMP/s1.pid" ] || [ ! -s "$want" ]; then
      bad "A9 $kind SIG$SIG: the suite never started"; sed -n '1,20p' "$TMP/gate.out"; kill -KILL "$GATE_PID"; GATE_PID=""; continue
    fi
    kill -"$SIG" "$GATE_PID"
    for _ in $(seq 1 100); do kill -0 "$GATE_PID" 2>/dev/null || break; sleep 0.1; done
    kill -0 "$GATE_PID" 2>/dev/null && { bad "A9 $kind SIG$SIG: the gate is still running 10 s after the signal"; kill -KILL "$GATE_PID"; }
    wait "$GATE_PID" 2>/dev/null; st=$?
    GATE_PID=""
    case "$SIG" in TERM) n=15 ;; HUP) n=1 ;; INT) n=2 ;; esac
    [ "$st" = "$((128 + n))" ] && ok "A9 $kind SIG$SIG: the gate died by SIG$SIG (status $st)" \
      || bad "A9 $kind SIG$SIG: gate exit status $st, want $((128 + n))"
    sleep 0.3
    for f in "$TMP"/s1.pid "$TMP"/s2.pid; do
      [ -s "$f" ] || continue
      p="$(cat "$f")"; stat_p="$(ps -o stat= -p "$p" 2>/dev/null)"
      # a killed suite whose new parent does not reap it stays a zombie (a container without an init): dead
      if [ -n "$stat_p" ] && [ "${stat_p#Z}" = "$stat_p" ]; then
        bad "A9 $kind SIG$SIG: the suite (pid $p) outlived the gate"; kill -KILL -- "-$p" 2>/dev/null
      else
        ok "A9 $kind SIG$SIG: the suite $(basename "$f" .pid) did not outlive the gate"
      fi
    done
  done
  git checkout -q -- src/core.py
done

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_robustness: all tests passed" || { echo "❌ test_gate_robustness: $FAILS failed"; exit 1; }
