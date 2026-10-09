#!/usr/bin/env bash
# Regression (2026-10-09): bin/push_gate.py decoded git's output strictly (text=True), so a repository holding a file whose
# name is not valid UTF-8 (cfg_<byte 0xE9>.py) made `git push` die with a UnicodeDecodeError traceback (exit 1) instead of a
# verdict; a refusal that names such a file also crashed printing it on a strict UTF-8 stdout (macOS, LANG=en_US.UTF-8).
# Each step runs twice, once with an ASCII name and once with the non-UTF-8 one; push_gate must exit 0 or 2 (never 1 with a
# Traceback) and give the same verdict for both:
#   1. a code file committed in the pushed range, no receipt: blocked (2)
#   2. a full gate PASS, then that file committed again: blocked (2), and the refusal names the file
#   3. (a file system that accepts the name: Linux; APFS refuses it) the file and a second new one dirty at gate time, the
#      first committed: covered (0) — the second is left uncommitted (push_gate.py ponytail)
#   4. `git push --tags` with such a tag on a commit the remote lacks: blocked (2), the tag named. Step 2 alone could not
#      catch a printing crash: untestable_only() imports post-fix-gate.py, which switches stdout to errors="replace".
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; PG="$DEVKIT_DIR/bin/push_gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
LATIN="$(printf '\351')"   # é in Latin-1: one byte that is not valid UTF-8
# A file system that refuses the name (APFS: "Illegal byte sequence") still gets it through git (steps 1-2, update-index).
CAN=0; ( printf 'x' > "$TMP/probe_$LATIN" ) 2>/dev/null && CAN=1

commit_file() { # path content message
  if [ "$CAN" = 1 ]; then printf '%s\n' "$2" > "$1" && git add -- "$1"
  else git update-index --add --cacheinfo "100644,$(printf '%s\n' "$2" | git hash-object -w --stdin),$1"; fi
  git commit -qm "$3"
}
run_gate() { CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --run-tests --full --brief >/dev/null 2>&1; }
# PYTHONIOENCODING=utf-8:strict: stdout as on macOS with a UTF-8 locale (a POSIX locale turns on UTF-8 mode, whose
# surrogateescape stdout would hide the printing crash on Linux)
VERDICTS_ascii=""; VERDICTS_latin=""
expect() { # kind step expected text-the-output-must-hold ("" = none) push_gate-args...
  local kind="$1" step="$2" want="$3" text="$4" out rc; shift 4
  out="$(PYTHONIOENCODING=utf-8:strict python3 "$PG" "$@" 2>&1)"; rc=$?
  if [ "$kind" = ascii ]; then VERDICTS_ascii="$VERDICTS_ascii $rc"; else VERDICTS_latin="$VERDICTS_latin $rc"; fi
  case "$out" in *Traceback*) bad "$kind $step: crashed (exit $rc): $(printf '%s' "$out" | tail -n 1)"; return ;; esac
  if [ "$rc" != "$want" ]; then bad "$kind $step: exit $rc, expected $want — $out"; return; fi
  if [ -n "$text" ]; then case "$out" in *"$text"*) ;; *) bad "$kind $step: exit $rc but the reason does not name $text — $out"; return ;; esac; fi
  ok "$kind $step (exit $rc)"
}

for kind in ascii latin; do
  if [ "$kind" = ascii ]; then N="cfg_e"; D="new_e"; T="v_e"; else N="cfg_$LATIN"; D="new_$LATIN"; T="v_$LATIN"; fi
  R="$TMP/repo_$kind"
  mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  echo "fun ok() = 1" > src/Core.kt
  cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
  git add -A && git commit -qm init
  git init -q --bare "$TMP/origin_$kind.git" && git remote add origin "$TMP/origin_$kind.git" && git push -q -u origin HEAD 2>/dev/null

  commit_file "src/$N.py" "x = 1" "add a config module"
  expect "$kind" "1: a code file committed in the pushed range, no receipt: blocked" 2 "" "$R"

  if run_gate "$R"; then ok "$kind setup: --full gate exit 0"; else bad "$kind setup: --full gate exit $?"; fi
  commit_file "src/$N.py" "x = 2" "changed after the gate"
  expect "$kind" "2: the file committed again after the gate PASS: blocked, named" 2 "cfg_" "$R"
  # packed-refs: a ref's name is file content there, so this works where the file system refuses the name
  printf '%s refs/tags/%s\n' "$(git rev-parse HEAD)" "$T" >> "$(git rev-parse --git-dir)/packed-refs"
  expect "$kind" "4: --tags with a tag on a commit the remote lacks: blocked, named" 2 "v_" "$R" --all-tags origin

  if [ "$CAN" = 1 ]; then
    printf 'x = 3\n' > "src/$N.py"; printf 'y = 1\n' > "src/$D.py"
    if run_gate "$R"; then ok "$kind setup: --full gate exit 0 with both files dirty"; else bad "$kind setup: --full gate exit $? with both files dirty"; fi
    git commit -qm "the tested content" -- "src/$N.py"
    expect "$kind" "3: dirty at gate time and committed (another left dirty): covered" 0 "" "$R"
  fi
done
[ "$CAN" = 1 ] || echo "note: this file system refuses a non-UTF-8 file name, step 3 (dirty files) skipped"
[ "$VERDICTS_ascii" = "$VERDICTS_latin" ] && ok "the non-UTF-8 name gets the ASCII name's verdicts ($VERDICTS_ascii )" \
  || bad "verdicts differ: ASCII$VERDICTS_ascii, non-UTF-8$VERDICTS_latin"

# The repository folder itself with a non-UTF-8 name: tree_fp.receipt_path decoded git's answer strictly and crashed (2026-10-09).
if [ "$CAN" = 1 ]; then
  RD="$TMP/$(printf 'repo_\351')"; mkdir -p "$RD" && git -C "$RD" init -q .
  if out="$(python3 -c 'import os, sys; sys.path.insert(0, sys.argv[1]); import tree_fp
p = tree_fp.receipt_path(os.fsdecode(os.fsencode(sys.argv[2])))
print(os.path.exists(os.path.dirname(os.path.dirname(p))))' "$DEVKIT_DIR/bin" "$RD" 2>&1)" && [ "$out" = True ]; then
    ok "a repository folder with a non-UTF-8 name: the receipt path is found"
  else
    bad "a repository folder with a non-UTF-8 name: $(printf '%s' "$out" | tail -1)"
  fi
fi

[ "$FAILS" -eq 0 ] && echo "push gate non-UTF-8 names: all checks passed" || { echo "push gate non-UTF-8 names: $FAILS FAILED"; exit 1; }
