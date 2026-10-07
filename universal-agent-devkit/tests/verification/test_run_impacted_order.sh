#!/usr/bin/env bash
# Regression test: tests/run_impacted.sh starts the LONGEST tests first (from tests/lib/test_durations.txt) and sizes
# its default parallelism from the core count — without changing what runs or what is reported.
# 2026-10-04 `agent-kit test` (`--all`) took 301 s on a 12-core machine: 4 jobs, alphabetical start, so a 137 s test could start
# last and become the tail. The order and the job count are performance only; they must never change (a) the SET of
# tests run, (b) the order the results are printed in, (c) the exit code, (d) `--list`, (e) which tests run alone.
# Every check runs a COPY of run_impacted.sh in a fixture kit of fake tests (never the real suite).
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
unset DEVKIT_GATE_DONE DEVKIT_TEST_JOBS DEVKIT_TEST_CORES DEVKIT_IMPACT_TEST_CHANGED   # the fixtures must not inherit these
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

RUN_N=0
# Every fake test appends "<name> <tests running right now, itself included>" to $RUN_LOG when it STARTS, so the log is
# the start order and its second column is the concurrency seen at that moment.
mk_test() { # <kit> <relative path> <sleep seconds> [exit code]
  local f="$1/$2" body
  mkdir -p "$(dirname "$f")"
  body='mkdir "$CONC_DIR/$$"; n=$(ls "$CONC_DIR" | wc -l | tr -d " "); echo "NAME $n" >> "$RUN_LOG"; sleep SECS; rmdir "$CONC_DIR/$$"; exit RC'
  body="${body//NAME/$(basename "$2" .sh)}"; body="${body//SECS/$3}"; body="${body//RC/${4:-0}}"
  printf '%s\n' "$body" > "$f"
}
mk_kit() { # <dir> : an empty kit with a copy of the runner
  mkdir -p "$1/tests/lib" "$1/tests/gates" "$1/tests/verification" "$1/tests/context_memory"
  cp "$DEVKIT_DIR/tests/run_impacted.sh" "$1/tests/"; : > "$1/tests/impact_map.txt"   # the runner reads the map on every changed file
  ( cd "$1" && git init -q . )   # a scratch repo of its own: never the repo this test lives in
}
run_kit() { # <kit> <jobs or ""> [run_impacted args] -> OUT, RC, and a fresh $RUN_LOG / $CONC_DIR
  local kit="$1" jobs="$2"; shift 2
  RUN_N=$((RUN_N + 1)); export RUN_LOG="$TMP/run.$RUN_N.log" CONC_DIR="$TMP/conc.$RUN_N"; mkdir -p "$CONC_DIR"; : > "$RUN_LOG"
  if [ -n "$jobs" ]; then OUT="$(cd "$kit" && DEVKIT_TEST_JOBS="$jobs" bash tests/run_impacted.sh "$@" 2>&1)"; RC=$?
  else OUT="$(cd "$kit" && bash tests/run_impacted.sh "$@" 2>&1)"; RC=$?; fi
}
started() { cut -d' ' -f1 "$RUN_LOG" | tr '\n' ' '; }   # the names, in start order

# ── fixture 1: order, set, exit code, results order ─────────────────────────────
K="$TMP/order"; mk_kit "$K"
mk_test "$K" tests/gates/test_a_quick.sh 0
mk_test "$K" tests/gates/test_b_mid.sh 0
mk_test "$K" tests/gates/test_c_long.sh 0
mk_test "$K" tests/verification/test_d_fail.sh 0 3
mk_test "$K" tests/verification/test_e_unknown1.sh 0
mk_test "$K" tests/verification/test_f_unknown2.sh 0
mk_test "$K" tests/verification/test_g_longest.sh 0
mk_test "$K" tests/verification/test_h_tie.sh 0
mk_test "$K" tests/context_memory/test_budgets.sh 0
mk_test "$K" tests/verification/test_session_context.sh 0
cat > "$K/tests/lib/test_durations.txt" <<'EOF'
# comment line, then a blank line and some garbage: none of them may matter

not a duration line
abc tests/gates/test_a_quick.sh
1 tests/gates/test_a_quick.sh
5 tests/gates/test_b_mid.sh
9 tests/gates/test_c_long.sh
3 tests/verification/test_d_fail.sh
5 tests/verification/test_h_tie.sh
20 tests/verification/test_g_longest.sh
99 tests/gates/test_ghost_not_in_the_kit.sh
9999 tests/context_memory/test_budgets.sh
9999 tests/verification/test_session_context.sh
EOF
ALL="$(cd "$K" && ls tests/*/test_*.sh)"
ALL_NAMES="$(printf '%s\n' "$ALL" | sed 's#.*/##; s#\.sh$##' | tr '\n' ' ')"

# (a) longest first, unknown (not in the file) first of all, the timing tests alone and last
run_kit "$K" 1 --all
want="test_e_unknown1 test_f_unknown2 test_g_longest test_c_long test_b_mid test_h_tie test_d_fail test_a_quick test_budgets test_session_context "
[ "$(started)" = "$want" ] && ok "a: start order = unknown first, then longest first (tie keeps list order), timing tests alone last" \
  || fail "a: start order '$(started)' not '$want'"

# (b) the printed results keep LIST order whatever the start order was
shown="$(printf '%s\n' "$OUT" | grep -E '^[✔✖] tests/' | sed 's/^. //')"
[ "$shown" = "$ALL" ] && ok "b: results are printed in list order, not start order" || fail "b: printed order: $(printf '%s' "$shown" | tr '\n' ' ')"

# (c) same set, same pass/fail, same exit code: the one fake that exits 3 fails the run and is named
ran_set="$(cut -d' ' -f1 "$RUN_LOG" | sort | tr '\n' ' ')"; want_set="$(printf '%s\n' $ALL_NAMES | sort | tr '\n' ' ')"
[ "$ran_set" = "$want_set" ] && ok "c: exactly the same set of tests runs, each once (a ghost entry in the file runs nothing)" || fail "c: ran '$ran_set' of '$want_set'"
[ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q "✖ tests/verification/test_d_fail.sh" && [ "$(printf '%s\n' "$OUT" | grep -c '^✖ ')" = 1 ] \
  && ok "c: the failing test still fails the run (exit 1) and only it is named" || fail "c: rc=$RC: $OUT"
mk_test "$K" tests/verification/test_d_fail.sh 0 0
run_kit "$K" 1 --all
[ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^✔ ')" = 10 ] && ok "c: all green stays exit 0" || fail "c: all green rc=$RC: $OUT"
mk_test "$K" tests/verification/test_d_fail.sh 0 3

# the selection (--list) does not depend on the durations file either
( cd "$K" && git add -A && git -c user.email=t@t -c user.name=t commit -qm init && for t in $ALL; do echo "# x" >> "$t"; done )
list_with="$(cd "$K" && bash tests/run_impacted.sh --list)"
mv "$K/tests/lib/test_durations.txt" "$TMP/dur.keep"
list_without="$(cd "$K" && bash tests/run_impacted.sh --list)"
[ "$list_with" = "$list_without" ] && [ -n "$list_with" ] && ok "--list prints the same selection with and without the durations file" || fail "--list differs: with '$list_with' without '$list_without'"

# (d) no durations file: exactly the old (alphabetical) order
run_kit "$K" 1 --all
want="test_a_quick test_b_mid test_c_long test_d_fail test_e_unknown1 test_f_unknown2 test_g_longest test_h_tie test_budgets test_session_context "
[ "$(started)" = "$want" ] && ok "d: no durations file = the old alphabetical order" || fail "d: no file: '$(started)' not '$want'"
# an unreadable file, an empty one and one with only garbage behave the same way
: > "$K/tests/lib/test_durations.txt"; run_kit "$K" 1 --all
[ "$(started)" = "$want" ] && ok "d: an empty durations file = the old order" || fail "d: empty file: '$(started)'"
printf 'garbage\n# 5 tests/gates/test_c_long.sh\nx y z\n' > "$K/tests/lib/test_durations.txt"; run_kit "$K" 1 --all
[ "$(started)" = "$want" ] && ok "d: a file with only comments/garbage = the old order (a commented-out entry does not count)" || fail "d: garbage file: '$(started)'"
cp "$TMP/dur.keep" "$K/tests/lib/test_durations.txt"; chmod 000 "$K/tests/lib/test_durations.txt"
if [ ! -r "$K/tests/lib/test_durations.txt" ]; then
  run_kit "$K" 1 --all
  [ "$(started)" = "$want" ] && [ "$RC" = 1 ] && ok "d: an unreadable durations file = the old order, same exit" || fail "d: unreadable: '$(started)' rc=$RC"
else ok "d: (running as a user that reads everything: the unreadable-file case is skipped)"; fi
chmod 644 "$K/tests/lib/test_durations.txt"
# a broken sorter (here an awk that drops every test but one) must never drop or add a test: the reordered list is used
# only when it holds exactly the same tests, else the old order runs
SHIM="$TMP/shim"; mkdir -p "$SHIM"; printf '#!/bin/sh\ncat >/dev/null\necho "5 1 tests/gates/test_a_quick.sh"\n' > "$SHIM/awk"; chmod +x "$SHIM/awk"
OLDPATH="$PATH"; PATH="$SHIM:$PATH"; run_kit "$K" 1 --all; PATH="$OLDPATH"
[ "$(started)" = "$want" ] && [ "$RC" = 1 ] && ok "d: a sorter that returns the wrong set of tests is ignored: all tests run in the old order" || fail "d: broken awk: '$(started)' rc=$RC"

# ── fixture 2: real concurrency (sleeps): the job cap, longest-first under it, timing tests alone ──────────────
C="$TMP/conc"; mk_kit "$C"
for n in a b c d; do mk_test "$C" "tests/gates/test_$n.sh" 1; done
mk_test "$C" tests/verification/test_e_long.sh 3
mk_test "$C" tests/context_memory/test_budgets.sh 0
printf '3 tests/verification/test_e_long.sh\n1 tests/gates/test_a.sh\n1 tests/gates/test_b.sh\n1 tests/gates/test_c.sh\n1 tests/gates/test_d.sh\n99 tests/context_memory/test_budgets.sh\n' > "$C/tests/lib/test_durations.txt"
t0=$(date +%s); run_kit "$C" 2 --all; t1=$(date +%s)
first_two="$(head -2 "$RUN_LOG" | cut -d' ' -f1 | sort | tr '\n' ' ')"
rest="$(sed -n '3,$p' "$RUN_LOG" | cut -d' ' -f1 | tr '\n' ' ')"
[ "$first_two" = "test_a test_e_long " ] && [ "$rest" = "test_b test_c test_d test_budgets " ] \
  && ok "2 jobs: the 3 s test starts in the first wave next to a short one, the rest follow in order, budgets last" || fail "2 jobs start order: first two '$first_two', rest '$rest'"
peak="$(grep -v '^test_budgets ' "$RUN_LOG" | cut -d' ' -f2 | sort -n | tail -1)"
[ "$peak" = 2 ] && ok "e: DEVKIT_TEST_JOBS=2 caps the concurrency at 2 (peak seen $peak)" || fail "e: DEVKIT_TEST_JOBS=2 peak concurrency $peak"
[ "$(grep '^test_budgets ' "$RUN_LOG")" = "test_budgets 1" ] && ok "the timing test (test_budgets) runs alone, after everything else" || fail "test_budgets not alone: $(grep '^test_budgets ' "$RUN_LOG")"
[ "$RC" = 0 ] && ok "fixture 2 passes (exit 0) in $((t1 - t0)) s" || fail "fixture 2 rc=$RC: $OUT"

# ── (f) the default job count: min(cores-2, 10), floor 4 (a small machine keeps the old default of 4); DEVKIT_TEST_JOBS overrides; --jobs prints what a run uses ─
J="$TMP/jobs"; mk_kit "$J"
jobs_of() { (cd "$J" && env "$@" bash tests/run_impacted.sh --jobs 2>&1); }
bad=""
for pair in 1:4 2:4 3:4 4:4 5:4 6:4 8:6 11:9 12:10 13:10 64:10; do
  c="${pair%%:*}"; w="${pair##*:}"; g="$(jobs_of DEVKIT_TEST_CORES="$c")"
  [ "$g" = "$w" ] || bad="$bad ${c}cores->'$g'(want $w)"
done
[ -z "$bad" ] && ok "f: default jobs = min(cores-2, 10), floor 4 = the old default (1,2,3,4,5,6,8,11,12,13,64 cores)" || fail "f: formula:$bad"
# on THIS machine: the formula applied to a core count the machine itself reports
exp=""; for c in "$(sysctl -n hw.ncpu 2>/dev/null)" "$(nproc 2>/dev/null)" "$(python3 -c 'import os; print(os.cpu_count() or 0)' 2>/dev/null)"; do
  case "$c" in ''|*[!0-9]*|0) continue ;; esac
  j=$((c - 2)); [ "$j" -gt 10 ] && j=10; [ "$j" -lt 4 ] && j=4; exp="$exp $j"
done
real="$(jobs_of A=1)"
case "$real:$exp " in [0-9]*:*" $real "*) ok "f: on this machine the default is $real jobs (formula candidates:$exp)" ;; *) fail "f: this machine's default is '$real', formula says:$exp" ;; esac
[ "$(jobs_of DEVKIT_TEST_JOBS=3 DEVKIT_TEST_CORES=12)" = 3 ] && [ "$(jobs_of DEVKIT_TEST_JOBS=40 DEVKIT_TEST_CORES=12)" = 40 ] \
  && ok "e: DEVKIT_TEST_JOBS overrides the formula (3 and 40 on 12 cores)" || fail "e: override: '$(jobs_of DEVKIT_TEST_JOBS=3 DEVKIT_TEST_CORES=12)' '$(jobs_of DEVKIT_TEST_JOBS=40 DEVKIT_TEST_CORES=12)'"
bad=""; for v in abc 0 00 -3 1.5 ""; do g="$(jobs_of DEVKIT_TEST_JOBS="$v" DEVKIT_TEST_CORES=12)"; [ "$g" = 10 ] || bad="$bad '$v'->'$g'"; done
[ -z "$bad" ] && ok "e: an invalid DEVKIT_TEST_JOBS (abc, 0, 00, -3, 1.5, empty) falls back to the default, never to 0 = unlimited" || fail "e: invalid override:$bad"
# no way to count cores (no nproc, sysctl or python3 on PATH): the old default 4
STUB="$TMP/stub"; mkdir -p "$STUB"; ln -s "$(command -v dirname)" "$STUB/dirname"
g="$(cd "$J" && env PATH="$STUB" "$(command -v bash)" tests/run_impacted.sh --jobs 2>&1)"
[ "$g" = 4 ] && ok "f: no way to count the cores: the old default 4" || fail "f: no probe available: '$g'"

# ── the shipped durations file is well formed (an entry for a test that no longer exists only warns) ──────────────
DUR="$DEVKIT_DIR/tests/lib/test_durations.txt"
if [ -r "$DUR" ]; then
  badl="$(grep -vE '^[[:space:]]*(#.*)?$' "$DUR" | grep -vE '^[0-9]+(\.[0-9]+)? [^ ]+\.sh$' | head -3)"
  nent="$(grep -cE '^[0-9]+(\.[0-9]+)? [^ ]+\.sh$' "$DUR")"
  [ -z "$badl" ] && [ "$nent" -gt 50 ] && ok "tests/lib/test_durations.txt: $nent entries '<seconds> <test path>', no malformed line" || fail "tests/lib/test_durations.txt malformed (entries $nent): $badl"
  gone="$(grep -E '^[0-9]' "$DUR" | cut -d' ' -f2 | while read -r p; do [ -f "$DEVKIT_DIR/$p" ] || echo "$p"; done | tr '\n' ' ')"
  [ -z "$gone" ] || echo "  warn: tests/lib/test_durations.txt names tests that no longer exist (harmless, refresh the file): $gone"
  missing=""
  for p in "$DEVKIT_DIR"/tests/*/test_*.sh; do
    rel="${p#"$DEVKIT_DIR"/}"
    grep -qE "^[0-9]+(\\.[0-9]+)? ${rel}$" "$DUR" || missing="$missing $rel"
  done
  [ -z "$missing" ] && ok "every tests/*/test_*.sh has a measured duration (an unlisted test would start first)" \
    || fail "unlisted tests start first:$missing"
else fail "tests/lib/test_durations.txt is missing or unreadable"; fi

if [ "$FAILS" -ne 0 ]; then echo "run_impacted_order: $FAILS FAILED"; exit 1; fi
echo "run_impacted_order: all checks passed"
