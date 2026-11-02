#!/usr/bin/env bash
# Regression test (PLAN parallel-merge-gate, PR1): a PR no longer has to edit tests/lib/test_durations.txt (merge=union is local only,
# so the tracked file conflicted on GitHub: #883, #911). Measured durations live in an UNTRACKED file
# `<git common dir>/devkit/test_durations.measured.txt` (same `<seconds> <path>` format; DEVKIT_DURATIONS_MEASURED_FILE overrides the
# path, empty = none).
#  a. bin/heavy_slot.py selection_seconds: tracked file, then the measured file (measured wins and fills a test the tracked file lacks);
#     a test in neither file keeps the old answer, None (cpu: tests/gates/test_gate_slot_classes.sh case 20).
#  c. run_impacted.sh orders by the tracked file, then the measured one (measured wins).
#  d. run_impacted.sh --all with DEVKIT_RECORD_DURATIONS=1 (set only by the nightly bin/gate_full.py for `agent-kit test`) merges the real
#     seconds of every PASS test into the measured file (a failing test keeps its old value), never passes the switch to the tests it runs;
#     without it, or with the measured file disabled, it writes nothing.
#  e. scripts/git/check-test-durations.sh no longer tells the author to edit and stage the tracked file.
# Every fixture is a scratch repo in mktemp -d (never the real kit, never the real measured file). bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
unset DEVKIT_GATE_DONE DEVKIT_TEST_JOBS DEVKIT_TEST_CORES DEVKIT_IMPACT_TEST_CHANGED DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_DIRS \
      DEVKIT_PER_TEST_CACHE DEVKIT_RECORD_DURATIONS
unset DEVKIT_DURATIONS_MEASURED_FILE                  # the default path (git common dir of each fixture) from here on
export DEVKIT_CAPACITY_LOAD=0 DEVKIT_LANG=en
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# ── a. heavy_slot.selection_seconds ────────────────────────────────────────────────────────────────
FK="$TMP/fk"; mkdir -p "$FK/kit/tests/lib" "$FK/kit/tests/gates"
printf '3 tests/gates/test_known.sh\n9 tests/gates/test_other.sh\n' > "$FK/kit/tests/lib/test_durations.txt"
( cd "$FK" && git init -q . ) || { echo "✖ setup: fk"; exit 1; }
MEAS="$FK/.git/devkit/test_durations.measured.txt"
res="$(python3 - "$DEVKIT_DIR/bin" "$FK" "$MEAS" "$TMP/other.measured.txt" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import heavy_slot as hs
fk, meas, other = sys.argv[2], sys.argv[3], sys.argv[4]
cmd = "bash kit/tests/run_impacted.sh"
known, new = "tests/gates/test_known.sh", "tests/gates/test_new.sh"
out = [hs.selection_seconds(cmd, fk, [known, new])]               # tracked only, new unlisted: None (as before)
os.makedirs(os.path.dirname(meas), exist_ok=True)
with open(meas, "w", encoding="utf-8") as f:
    f.write("7 tests/gates/test_known.sh\n6 tests/gates/test_new.sh\n")
out.append(hs.selection_seconds(cmd, fk, [known, new]))           # measured fills new and wins for known: 7 + 6 = 13
out.append(hs.selection_seconds(cmd, fk, [known]))                # measured wins: 7
out.append(hs.selection_seconds(cmd, fk, ["tests/gates/test_x.sh", known]))   # a test in neither file: None
with open(other, "w", encoding="utf-8") as f:
    f.write("2 tests/gates/test_known.sh\n")
os.environ["DEVKIT_DURATIONS_MEASURED_FILE"] = other
out.append(hs.selection_seconds(cmd, fk, [known]))                # override path: 2
os.environ["DEVKIT_DURATIONS_MEASURED_FILE"] = ""
out.append(hs.selection_seconds(cmd, fk, [known]))                # disabled: tracked 3
print(" ".join(repr(x) for x in out))
PY
)"
set -- $res
[ "${1:-}" = None ] && ok "a. tracked file only, a selected test unlisted: still unknown (None = cpu, as before)" || fail "a. want None, got '${1:-}'"
[ "${2:-}" = 13.0 ] && ok "a. heavy_slot reads <git common dir>/devkit/test_durations.measured.txt: it fills the unlisted test and wins (7 + 6)" \
  || fail "a. measured file not read: want 13.0, got '${2:-}' (None = the new test still needs a tracked line)"
[ "${3:-}" = 7.0 ] && ok "a. the measured value replaces the tracked one (7, not 3)" || fail "a. want 7.0, got '${3:-}'"
[ "${4:-}" = None ] && ok "a. a test in neither file: None" || fail "a. want None, got '${4:-}'"
[ "${5:-}" = 2.0 ] && ok "a. DEVKIT_DURATIONS_MEASURED_FILE overrides the path (2)" || fail "a. override: want 2.0, got '${5:-}'"
[ "${6:-}" = 3.0 ] && ok "a. DEVKIT_DURATIONS_MEASURED_FILE empty: no measured file, tracked 3" || fail "a. disabled: want 3.0, got '${6:-}'"

# ── c/d. run_impacted.sh: reads the measured file for the start order, --all records it (opt-in) ─────────────────
mk_test() { # <kit> <relative path> <sleep seconds> [exit code]: appends its name to $RUN_LOG at START, and what it inherited
  local f="$1/$2" n; n="$(basename "$2" .sh)"; mkdir -p "$(dirname "$f")"
  printf 'echo "%s ${DEVKIT_RECORD_DURATIONS:-unset}" >> "$RUN_LOG"; sleep %s; exit %s\n' "$n" "$3" "${4:-0}" > "$f"
}
mk_kit() { # <dir>: a scratch repo with a copy of the runner
  mkdir -p "$1/tests/lib" "$1/tests/gates" "$1/bin"
  cp "$DEVKIT_DIR/tests/run_impacted.sh" "$1/tests/"; : > "$1/tests/impact_map.txt"
  cp "$DEVKIT_DIR/bin/capacity.py" "$1/bin/"
  ( cd "$1" && git init -q . )
}
RUN_N=0
run_kit() { # <kit> [env assignments...] <command...>: OUT, RC, fresh $RUN_LOG
  local kit="$1"; shift
  RUN_N=$((RUN_N + 1)); export RUN_LOG="$TMP/run.$RUN_N.log"; : > "$RUN_LOG"
  OUT="$(cd "$kit" && env DEVKIT_TEST_JOBS=1 "$@" 2>&1)"; RC=$?
}
started() { cut -d' ' -f1 "$RUN_LOG" | tr '\n' ' '; }

K="$TMP/order"; mk_kit "$K"
mk_test "$K" tests/gates/test_a.sh 0
mk_test "$K" tests/gates/test_b.sh 0
printf '99 tests/gates/test_a.sh\n1 tests/gates/test_b.sh\n' > "$K/tests/lib/test_durations.txt"
run_kit "$K" bash tests/run_impacted.sh --all
[ "$(started)" = "test_a test_b " ] && ok "c. tracked file only: longest first (a, b)" || fail "c. tracked order: '$(started)'"
mkdir -p "$K/.git/devkit"; printf '1 tests/gates/test_a.sh\n50 tests/gates/test_b.sh\n' > "$K/.git/devkit/test_durations.measured.txt"
run_kit "$K" bash tests/run_impacted.sh --all
[ "$(started)" = "test_b test_a " ] && ok "c. the measured file (git common dir) wins over the tracked file: b (50) before a" \
  || fail "c. measured file ignored by the start order: '$(started)' (want 'test_b test_a ')"
run_kit "$K" DEVKIT_DURATIONS_MEASURED_FILE= bash tests/run_impacted.sh --all
[ "$(started)" = "test_a test_b " ] && ok "c. DEVKIT_DURATIONS_MEASURED_FILE empty: the measured file is ignored (tracked order)" \
  || fail "c. disabled measured file still read: '$(started)'"
rm -f "$K/tests/lib/test_durations.txt"
run_kit "$K" bash tests/run_impacted.sh --all
[ "$(started)" = "test_b test_a " ] && ok "c. no tracked file: the measured file alone orders the run" || fail "c. measured only: '$(started)'"

R="$TMP/rec"; mk_kit "$R"
mk_test "$R" tests/gates/test_pass_slow.sh 2
mk_test "$R" tests/gates/test_pass_quick.sh 0
mk_test "$R" tests/gates/test_red.sh 0 3
printf '4 tests/gates/test_pass_slow.sh\n' > "$R/tests/lib/test_durations.txt"
M="$R/.git/devkit/test_durations.measured.txt"
# d. without the switch, or with the measured file disabled: nothing is written
run_kit "$R" bash tests/run_impacted.sh --all
[ "$RC" = 1 ] && [ ! -e "$M" ] && ok "d. --all without DEVKIT_RECORD_DURATIONS: no measured file written" || fail "d. rc=$RC, file exists: $([ -e "$M" ] && cat "$M")"
run_kit "$R" DEVKIT_RECORD_DURATIONS=1 DEVKIT_DURATIONS_MEASURED_FILE= bash tests/run_impacted.sh --all
[ "$RC" = 1 ] && [ ! -e "$M" ] && ok "d. DEVKIT_RECORD_DURATIONS=1 with the measured file disabled: nothing written" \
  || fail "d. disabled measured file written: rc=$RC $([ -e "$M" ] && cat "$M")"
# d. with the switch: PASS tests merged in, the red test keeps its old value, unrelated lines kept, exit code unchanged
mkdir -p "$(dirname "$M")"; printf '77 tests/gates/test_red.sh\n42 tests/gates/test_ghost.sh\n88 tests/gates/test_pass_quick.sh\n' > "$M"
run_kit "$R" DEVKIT_RECORD_DURATIONS=1 bash tests/run_impacted.sh --all
slow="$(awk '$2 == "tests/gates/test_pass_slow.sh" { print $1 }' "$M" 2>/dev/null)"
quick="$(awk '$2 == "tests/gates/test_pass_quick.sh" { print $1 }' "$M" 2>/dev/null)"
red="$(awk '$2 == "tests/gates/test_red.sh" { print $1 }' "$M" 2>/dev/null)"
ghost="$(awk '$2 == "tests/gates/test_ghost.sh" { print $1 }' "$M" 2>/dev/null)"
[ "$RC" = 1 ] && ok "d. recording does not change the exit code (a red test still fails the run)" || fail "d. rc=$RC: $OUT"
case "$slow" in ''|*[!0-9]*) fail "d. PASS test not recorded: '$slow' ($(cat "$M" 2>/dev/null | tr '\n' '|'))" ;;
  *) [ "$slow" -ge 2 ] && [ "$slow" -le 30 ] && ok "d. a PASS test is recorded with its real seconds ($slow s for a 2 s sleep)" || fail "d. slow test recorded as $slow s" ;; esac
case "$quick" in ''|*[!0-9]*) fail "d. quick PASS test not recorded: '$quick'" ;;
  *) [ "$quick" -lt 88 ] && ok "d. a PASS test's old measured value is replaced ($quick s, was 88)" || fail "d. quick kept its stale 88 s" ;; esac
[ "$red" = 77 ] && ok "d. a red test keeps its old measured value (77)" || fail "d. red test value '$red' (want 77)"
[ "$ghost" = 42 ] && ok "d. lines for tests not run are kept (42)" || fail "d. unrelated line lost: '$ghost'"
bad="$(grep -vE '^[0-9]+(\.[0-9]+)? [^ ]+\.sh$' "$M" 2>/dev/null | head -3)"
[ -z "$bad" ] && ok "d. the measured file keeps the '<seconds> <path>' format" || fail "d. malformed lines: $bad"
grep -q ' 1$' "$RUN_LOG" && fail "d. DEVKIT_RECORD_DURATIONS leaked into the tests the runner started" \
  || ok "d. the tests the runner starts do not inherit DEVKIT_RECORD_DURATIONS (nested runners record nothing)"
ls "$(dirname "$M")" | grep -v '^test_durations.measured.txt$' | grep -q . && fail "d. temp file left beside the measured file: $(ls "$(dirname "$M")")" \
  || ok "d. no temp file left beside the measured file (tmp + mv)"
grep -q 'test_pass_quick' "$R/tests/lib/test_durations.txt" && fail "d. the tracked file was edited" || ok "d. the tracked tests/lib/test_durations.txt is never written"
# d. an unwritable measured dir: the run still reports normally, exit code unchanged
chmod 500 "$(dirname "$M")"
if [ ! -w "$(dirname "$M")" ]; then
  run_kit "$R" DEVKIT_RECORD_DURATIONS=1 bash tests/run_impacted.sh --all
  [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '✔ tests/gates/test_pass_slow.sh' && ok "d. a write error does not change the run (exit 1 from the red test only)" \
    || fail "d. write error changed the run: rc=$RC $OUT"
else ok "d. (running as a user that writes everywhere: the unwritable case is skipped)"; fi
chmod 700 "$(dirname "$M")"
# d. wiring: only the nightly gate-full asks for recording (its `agent-kit test` call), and agent-kit hands it to the pool alone
grep -A3 'sh(\["bash", ak, "test"\]' "$DEVKIT_DIR/bin/gate_full.py" | grep -q 'DEVKIT_RECORD_DURATIONS="1"' \
  && ok "d. bin/gate_full.py runs agent-kit test with DEVKIT_RECORD_DURATIONS=1" || fail "d. gate_full.py does not ask agent-kit test to record durations"
grep 'run_impacted.sh" --all' "$DEVKIT_DIR/bin/agent-kit" | grep -q 'DEVKIT_RECORD_DURATIONS="$REC_DUR"' \
  && grep -q 'REC_DUR="${DEVKIT_RECORD_DURATIONS:-}"; unset DEVKIT_RECORD_DURATIONS' "$DEVKIT_DIR/bin/agent-kit" \
  && ok "d. agent-kit passes DEVKIT_RECORD_DURATIONS to the pool only (unset for the suites beside it)" || fail "d. agent-kit does not hand the switch to the pool"

# ── e. pre-commit hint: no instruction to edit and stage the tracked file ─────────────────────────────
D="$TMP/pc"; mkdir -p "$D/kit/tests/lib" "$D/kit/tests/gates"
( cd "$D" && git init -q . && git config user.email t@t && git config user.name t )
printf '3 tests/gates/test_old.sh\n' > "$D/kit/tests/lib/test_durations.txt"; echo 'exit 0' > "$D/kit/tests/gates/test_old.sh"
( cd "$D" && git add -A && git commit -qm init ); echo 'exit 0' > "$D/kit/tests/gates/test_new.sh"; ( cd "$D" && git add -A )
POUT="$(cd "$D" && DEVKIT_ROOT="$D/kit" bash "$DEVKIT_DIR/scripts/git/check-test-durations.sh" 2>&1)"; PRC=$?
[ "$PRC" = 0 ] && printf '%s' "$POUT" | grep -qi 'warning' && ! printf '%s' "$POUT" | grep -q 'stage it' \
  && printf '%s' "$POUT" | grep -q 'gate-full' && ok "e. pre-commit hint: no 'stage it' instruction, says gate-full measures it" \
  || fail "e. pre-commit hint still asks to edit/stage the file (rc=$PRC): $POUT"

if [ "$FAILS" -ne 0 ]; then echo "durations_measured_default: $FAILS FAILED"; exit 1; fi
echo "durations_measured_default: all checks passed"
