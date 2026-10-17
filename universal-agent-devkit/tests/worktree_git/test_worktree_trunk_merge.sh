#!/usr/bin/env bash
# W1 R3 (docs/workflow-improvements.md I.0): `worktree finish` / `automerge` merges main INTO the worktree, then runs the gate on what the
# worktree brings (`post-fix-gate --run-tests --diff <main it merged>`) BEFORE main moves: a merge with no textual conflict can still
# break (main renamed a function a new caller in the worktree uses). A regression test FAIL keeps main where it was and the worktree
# with its merge commit. Main moving while the gate runs: merge again, gate again, at most 3 rounds. `--keep` merges and keeps the
# worktree (a session's mid-way merge). WORKTREE_TRUNK_MODE=0: the old behaviour (no gate). A project with no regression matrix: no gate.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export GIT_CONFIG_GLOBAL=/dev/null   # no user template / hooks of this machine in the fixture repos

repo() {   # repo <name>: lib.sh greet(), app.sh calls it, check.sh = the matrix suite (every app*.sh prints ok), the matrix committed
  local p="$TMP/$1"; mkdir -p "$p/.agents" && G "$p" init -q -b main . && G "$p" config user.email t@t && G "$p" config user.name t   # the merges worktree.py makes need it
  printf 'greet() { echo ok; }\n' > "$p/lib.sh"
  printf '. ./lib.sh\ngreet\n' > "$p/app.sh"
  printf '[ -n "${GATE_COUNT:-}" ] && echo run >> "$GATE_COUNT"\n[ -n "${FAIL_ONCE:-}" ] && [ ! -f "$FAIL_ONCE" ] && { : > "$FAIL_ONCE"; echo "✖ app2.sh (flaky first run)"; exit 1; }\n[ -n "${DURING_GATE:-}" ] && bash "$DURING_GATE"\nfor f in app*.sh; do [ "$(bash "$f" 2>/dev/null)" = ok ] || { echo "FAIL $f"; exit 1; }; done\necho "all apps ok"\n' > "$p/check.sh"
  printf '{"project":"t","rules":[{"component":"App","watch_files":["*.sh"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"every app prints ok","command":"bash check.sh"}]}]}\n' \
    > "$p/.agents/regression_matrix.active.json"
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/evidence/\n.agents/regression_journal/\n.claude/\n' > "$p/.gitignore"
  G "$p" add -A && G "$p" commit -qm base
}
wtadd() { (cd "$TMP/$1" && python3 "$WT" add "$TMP/$1-$2" --no-init >/dev/null 2>&1) || fail "setup: worktree add $1-$2"; }
fin() { (cd "$TMP/$1" && env "${@:3}" python3 "$WT" finish "$TMP/$1-$2" > "$TMP/out" 2>&1); }
newcaller() {   # the worktree adds app2.sh, a new caller of greet
  printf '. ./lib.sh\ngreet\n' > "$TMP/$1-$2/app2.sh" && G "$TMP/$1-$2" add app2.sh && G "$TMP/$1-$2" commit -qm "app2 calls greet"
}
rename_on_main() {   # main renames greet -> hello and updates its own caller: no textual conflict with app2.sh
  printf 'hello() { echo ok; }\n' > "$TMP/$1/lib.sh" && printf '. ./lib.sh\nhello\n' > "$TMP/$1/app.sh" && G "$TMP/$1" commit -qam "rename greet to hello"
}

# 1 the merge has no conflict but breaks: the gate fails, main does not move, the worktree keeps its merge commit
repo a; wtadd a w; newcaller a w; rename_on_main a; before="$(G "$TMP/a" rev-parse HEAD)"
fin a w; rc=$?
if [ "$rc" = 1 ] && [ "$(G "$TMP/a" rev-parse HEAD)" = "$before" ] && [ -d "$TMP/a-w" ] && grep -q "REG-APP-01" "$TMP/out" \
    && G "$TMP/a-w" merge-base --is-ancestor "$before" HEAD; then
  ok "a clean merge that breaks a regression test: refused, main unmoved, the worktree holds the merge (main merged in)"
else
  fail "broken merge: rc=$rc main moved=$([ "$(G "$TMP/a" rev-parse HEAD)" = "$before" ] && echo no || echo yes): $(tail -5 "$TMP/out")"
fi
[ -f "$TMP/a/app2.sh" ] && fail "  … app2.sh reached main" || ok "  … nothing of the worktree reached main"
# … and running finish again (main is already merged in, nothing left to merge) never lets the red result through (OCR 14/10);
#   nothing changed since the refusal, so it is given again at once, the gate not re-run (review: the Stop hook waits 9 s, then
#   reports a background merge as running — a red merge that is re-gated on every Stop never reached the session)
: > "$TMP/a.count"
fin a w GATE_COUNT="$TMP/a.count"; rc=$?
[ ! -s "$TMP/a.count" ] && ok "  … unchanged since the refusal: refused again at once, the gate not re-run" || fail "the gate re-ran on an unchanged refused merge ($(wc -l < "$TMP/a.count") runs)"
# … but a kept verdict expires (a machine under load can fail a timing test twice in a row): past the TTL the gate runs again
sleep 2; : > "$TMP/a.count"
fin a w GATE_COUNT="$TMP/a.count" WORKTREE_MERGE_GATE_RESULT_TTL_S=1; rc=$?
[ "$rc" = 1 ] && [ -s "$TMP/a.count" ] && ok "  … a kept verdict older than WORKTREE_MERGE_GATE_RESULT_TTL_S: the gate runs again" || fail "an expired verdict was replayed (rc $rc, runs $(wc -l < "$TMP/a.count"))"
[ "$rc" = 1 ] && [ "$(G "$TMP/a" rev-parse HEAD)" = "$before" ] && [ ! -f "$TMP/a/app2.sh" ] && grep -q "REG-APP-01" "$TMP/out" \
  && ok "  … finish run again on the refused merge: still refused by the gate" || fail "second finish let the red merge in (rc $rc): $(tail -3 "$TMP/out")"
# … nor does a commit made after the refusal that is still red
printf '. ./lib.sh\ngreet\n# still calls greet\n' > "$TMP/a-w/app2.sh" && G "$TMP/a-w" commit -qam "a fix that fixes nothing"
fin a w; rc=$?
[ "$rc" = 1 ] && [ ! -f "$TMP/a/app2.sh" ] && ok "  … a later commit that is still red: refused" || fail "a red follow-up commit got in (rc $rc)"
# … and a real fix goes through
printf '. ./lib.sh\nhello\n' > "$TMP/a-w/app2.sh" && G "$TMP/a-w" commit -qam "call hello"
fin a w; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/a/app2.sh" ] && [ ! -d "$TMP/a-w" ] && ok "  … the real fix: merged and removed" || fail "the fixed worktree did not merge (rc $rc): $(tail -3 "$TMP/out")"

# 2 the merged result passes: main fast-forwards, the worktree is removed
repo b; wtadd b w; newcaller b w; echo note > "$TMP/b/notes.txt" && G "$TMP/b" add notes.txt && G "$TMP/b" commit -qm "unrelated on main"
fin b w; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/b/app2.sh" ] && [ -f "$TMP/b/notes.txt" ] && [ ! -d "$TMP/b-w" ] \
  && ok "main moved, the merged result passes the gate: main fast-forwarded, the worktree removed" || fail "passing merge: rc=$rc $(tail -5 "$TMP/out")"

# 3 --keep: merged into main, the worktree stays (until the Stop hook's next run removes it; W1 R1 keeps a session's own to its end)
repo c; wtadd c w; newcaller c w; echo note > "$TMP/c/notes.txt" && G "$TMP/c" add notes.txt && G "$TMP/c" commit -qm "unrelated on main"
(cd "$TMP/c" && python3 "$WT" finish "$TMP/c-w" --keep > "$TMP/out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/c/app2.sh" ] && [ -d "$TMP/c-w" ] && G "$TMP/c" worktree list | grep -q "c-w" \
  && ok "--keep: merged into main, the worktree kept and still registered" || fail "--keep: rc=$rc dir=$([ -d "$TMP/c-w" ] && echo kept || echo gone) $(tail -3 "$TMP/out")"

# 4 WORKTREE_TRUNK_MODE=0: the old behaviour, no gate (the broken merge of case 1 goes through)
repo d; wtadd d w; newcaller d w; rename_on_main d
fin d w WORKTREE_TRUNK_MODE=0; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/d/app2.sh" ] && ok "WORKTREE_TRUNK_MODE=0: no gate, merged as before" || fail "TRUNK_MODE=0: rc=$rc $(tail -3 "$TMP/out")"

# 5 main moves while the gate runs (once): a second round merges it in, gates again, fast-forwards
repo e; wtadd e w; newcaller e w; echo note > "$TMP/e/notes.txt" && G "$TMP/e" add notes.txt && G "$TMP/e" commit -qm "unrelated on main"
printf '[ -f "%s/moved" ] && exit 0; : > "%s/moved"; echo m > "%s/e/moved1.txt"; git -C "%s/e" -c user.email=t@t -c user.name=t add moved1.txt; git -C "%s/e" -c user.email=t@t -c user.name=t commit -qm "main moves during the gate"\n' \
  "$TMP" "$TMP" "$TMP" "$TMP" "$TMP" > "$TMP/move-once.sh"
fin e w DURING_GATE="$TMP/move-once.sh"; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/e/app2.sh" ] && [ -f "$TMP/e/moved1.txt" ] && [ ! -d "$TMP/e-w" ] \
  && ok "main moved during the gate: merged again, gated again, fast-forwarded (both changes in main)" || fail "moved once: rc=$rc $(tail -5 "$TMP/out")"

# 6 main moves during every gate (a watched *.sh each time, so no gate result is reused): refused after 3 rounds
repo f; wtadd f w; newcaller f w; echo note > "$TMP/f/notes.txt" && G "$TMP/f" add notes.txt && G "$TMP/f" commit -qm "unrelated on main"
printf 'n=$(cat "%s/n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "%s/n"; echo $n > "%s/f/moved$n.sh"; git -C "%s/f" -c user.email=t@t -c user.name=t add "moved$n.sh"; git -C "%s/f" -c user.email=t@t -c user.name=t commit -qm "main moves again"\n' \
  "$TMP" "$TMP" "$TMP" "$TMP" "$TMP" > "$TMP/move-always.sh"
fin f w DURING_GATE="$TMP/move-always.sh" WORKTREE_FINISH_RETRIES=0; rc=$?   # finish's own retry (test_worktree_finish_retry.sh) off: this case counts one round set
[ "$rc" = 1 ] && [ ! -f "$TMP/f/app2.sh" ] && [ "$(cat "$TMP/n" 2>/dev/null)" = 3 ] && [ -d "$TMP/f-w" ] && grep -qE "đi tiếp 3 lần|moved on 3 times" "$TMP/out" \
  && ok "main moves during every gate: refused after 3 rounds (3 gate runs), nothing of the worktree in main" || fail "always moving: rc=$rc runs=$(cat "$TMP/n" 2>/dev/null) $(tail -3 "$TMP/out")"

# 7 nothing net left to bring (the work came back by hand, or was reverted): the gate has nothing to audit (exit 3, no JSON) — that is
#   no refusal, the merge finishes (review: it was refused on every run, the worktree stuck for good)
repo g; wtadd g w; newcaller g w; G "$TMP/g-w" revert --no-edit HEAD >/dev/null; echo note > "$TMP/g/notes.txt" && G "$TMP/g" add notes.txt && G "$TMP/g" commit -qm "unrelated on main"
fin g w; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/g-w" ] && ok "nothing net to bring: finished (no 'gate gave no result' refusal)" || fail "empty net diff stuck: rc=$rc $(tail -3 "$TMP/out")"

# 8 an uncommitted edit made while the gate runs makes the gate green while the COMMIT stays red: main never gets the commit
repo h; wtadd h w; newcaller h w; rename_on_main h; hb="$(G "$TMP/h" rev-parse HEAD)"
printf 'printf ". ./lib.sh\\nhello\\n" > app2.sh\n' > "$TMP/fix-uncommitted.sh"   # runs in the worktree, inside the gate's suite
fin h w DURING_GATE="$TMP/fix-uncommitted.sh"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$TMP/h" rev-parse HEAD)" = "$hb" ] && [ ! -f "$TMP/h/app2.sh" ] \
  && ok "the worktree changed (uncommitted) while the gate ran: refused, main unmoved" || fail "uncommitted fix during the gate let the red commit in (rc $rc): $(tail -3 "$TMP/out")"

# 8b … and the other way: a GREEN commit, an uncommitted edit during the gate breaks it — refused for the edit, the FAIL is NOT kept
#    for those commits: with the edit gone the next run gates again and merges (OCR 14/10)
repo h2; wtadd h2 w; newcaller h2 w; echo note > "$TMP/h2/notes.txt" && G "$TMP/h2" add notes.txt && G "$TMP/h2" commit -qm "unrelated on main"
printf 'printf "greet() { echo no; }\\n" > lib.sh\n' > "$TMP/break-uncommitted.sh"
fin h2 w DURING_GATE="$TMP/break-uncommitted.sh"; rc=$?
[ "$rc" = 1 ] && grep -qE "đổi trong lúc gate chạy|changed while the gate ran" "$TMP/out" || fail "8b setup: the edit during the gate was not reported (rc $rc): $(tail -2 "$TMP/out")"
G "$TMP/h2-w" checkout -q -- lib.sh
fin h2 w; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/h2/app2.sh" ] && ok "a temporary edit that made a green commit look red: not kept, the next run merges" \
  || fail "a FAIL caused by a temporary edit was kept for green commits (rc $rc): $(tail -2 "$TMP/out")"

# 9 a gate past its time is stopped with SIGTERM (it kills its suites and puts back what it reverted), then SIGKILL; refused
repo k; wtadd k w; newcaller k w; rename_on_main k; kb="$(G "$TMP/k" rev-parse HEAD)"
printf 'exec -a "%s/slow-sleep" sleep 30\n' "$TMP" > "$TMP/slow.sh"   # the sleeping process itself carries a unique name (a wrapper's command line may hold any fixed string)
fin k w DURING_GATE="$TMP/slow.sh" WORKTREE_MERGE_GATE_TIMEOUT_S=4; rc=$?
for _ in 1 2 3 4 5; do pgrep -f "$TMP/slow-sleep" >/dev/null 2>&1 || break; sleep 1; done   # the group may take a moment to go
orphans="its suite stopped"; command -v pgrep >/dev/null || orphans="orphan check skipped: no pgrep"
[ "$rc" = 1 ] && [ "$(G "$TMP/k" rev-parse HEAD)" = "$kb" ] && grep -qE "không chạy xong|did not finish" "$TMP/out" && { ! command -v pgrep >/dev/null || ! pgrep -f "$TMP/slow-sleep" >/dev/null; } \
  && [ -z "$(G "$TMP/k-w" status --porcelain -- lib.sh app.sh app2.sh check.sh)" ] \
  && ok "a gate past WORKTREE_MERGE_GATE_TIMEOUT_S: refused, $orphans, no file left reverted" \
  || fail "gate timeout: rc=$rc leftover=$(pgrep -f "$TMP/slow-sleep" | tr '\n' ' ') status=$(G "$TMP/k-w" status --porcelain | tr '\n' ' ') $(tail -2 "$TMP/out")"
pkill -f "$TMP/slow-sleep" 2>/dev/null
# … a refusal that is no verdict (the gate did not finish) is not kept: the next run gates again, and gets the real answer
: > "$TMP/k.count"
fin k w GATE_COUNT="$TMP/k.count"; rc=$?
[ "$rc" = 1 ] && [ -s "$TMP/k.count" ] && grep -q "REG-APP-01" "$TMP/out" && ok "  … after a timeout the next run gates again (not replayed) and refuses on the real FAIL" \
  || fail "after a timeout: rc=$rc runs=$(wc -l < "$TMP/k.count") $(tail -2 "$TMP/out")"

# 10 WORKTREE_TRUNK_MODE=0 is still the way out after a refusal: the kept red verdict is not replayed when there is no gate (OCR 14/10)
repo m; wtadd m w; newcaller m w; rename_on_main m
fin m w; rc=$?; [ "$rc" = 1 ] || fail "setup: m-w should be refused first (rc $rc)"
fin m w WORKTREE_TRUNK_MODE=0; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/m/app2.sh" ] && ok "WORKTREE_TRUNK_MODE=0 after a refusal: no gate, no replayed verdict, merged" || fail "TRUNK_MODE=0 after a refusal still refused (rc $rc): $(tail -2 "$TMP/out")"

# 11 a worktree that dropped its own regression matrix is gated with main's (and one whose main has no matrix is not gated: case 13)
repo q; wtadd q w; newcaller q w; G "$TMP/q-w" rm -q .agents/regression_matrix.active.json && G "$TMP/q-w" commit -qm "drop the matrix"; rename_on_main q
qb="$(G "$TMP/q" rev-parse HEAD)"
fin q w; rc=$?
[ "$rc" = 1 ] && [ "$(G "$TMP/q" rev-parse HEAD)" = "$qb" ] && grep -q "REG-APP-01" "$TMP/out" && ok "a worktree that deleted its matrix: gated with main's, refused" || fail "matrix dropped in the worktree skipped the gate (rc $rc): $(tail -2 "$TMP/out")"

# 12 … nor one that WEAKENED its matrix (the test command made `true`): main's matrix is the one that protects main (OCR 14/10)
repo r; wtadd r w; newcaller r w
python3 -c 'import sys; p=sys.argv[1]; s=open(p).read(); assert "bash check.sh" in s; open(p,"w").write(s.replace("bash check.sh","true"))' "$TMP/r-w/.agents/regression_matrix.active.json" \
  && G "$TMP/r-w" commit -qam "weaken the matrix" && grep -q '"command":"true"' "$TMP/r-w/.agents/regression_matrix.active.json" || fail "setup: the worktree matrix was not weakened"
rename_on_main r
rb="$(G "$TMP/r" rev-parse HEAD)"
fin r w; rc=$?
[ "$rc" = 1 ] && [ "$(G "$TMP/r" rev-parse HEAD)" = "$rb" ] && grep -q "REG-APP-01" "$TMP/out" && ok "a worktree that weakened its matrix: gated with main's, refused" || fail "a weakened worktree matrix let the red merge in (rc $rc): $(tail -2 "$TMP/out")"

# 13 main has no matrix (no mandatory test protects it yet): no gate, even when the worktree brings one — the merge goes through
repo s; G "$TMP/s" rm -q .agents/regression_matrix.active.json && G "$TMP/s" commit -qm "no matrix on main"
wtadd s w; newcaller s w; mkdir -p "$TMP/s-w/.agents" && printf '{"project":"t","rules":[{"component":"App","watch_files":["*.sh"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"x","command":"bash check.sh"}]}]}\n' \
  > "$TMP/s-w/.agents/regression_matrix.active.json" && G "$TMP/s-w" add -A && G "$TMP/s-w" commit -qm "the first matrix" || fail "setup: the worktree's first matrix"; rename_on_main s
: > "$TMP/s.count"
fin s w GATE_COUNT="$TMP/s.count"; rc=$?
[ "$rc" = 0 ] && [ ! -s "$TMP/s.count" ] && [ -f "$TMP/s/.agents/regression_matrix.active.json" ] && ok "main without a matrix: no gate, merged (the worktree's first matrix comes in)" \
  || fail "main without a matrix: rc=$rc runs=$(wc -l < "$TMP/s.count") $(tail -2 "$TMP/out")"

# 14 the gate's time budget ran out before the mandatory suites ran (budget_exhausted): no pass, main unmoved (OCR 14/10)
#    (the budget only stops the NEXT suite from starting: main's matrix gets a second suite, the first one is slowed past the budget)
repo u; printf '{"project":"t","rules":[{"component":"App","watch_files":["*.sh"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"x","command":"bash check.sh"},{"id":"REG-APP-02","name":"y","command":"true"}]}]}\n' \
  > "$TMP/u/.agents/regression_matrix.active.json" && G "$TMP/u" commit -qam "a second suite"
wtadd u w; newcaller u w; echo note > "$TMP/u/notes.txt" && G "$TMP/u" add notes.txt && G "$TMP/u" commit -qm "unrelated on main"
ub="$(G "$TMP/u" rev-parse HEAD)"; printf 'sleep 6\n' > "$TMP/slow2.sh"   # wide margins: a busy machine must not change which path runs
fin u w GATE_TOTAL_BUDGET_S=2 DURING_GATE="$TMP/slow2.sh"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$TMP/u" rev-parse HEAD)" = "$ub" ] && grep -q "GATE_TOTAL_BUDGET_S" "$TMP/out" && ok "a gate out of its time budget: refused, main unmoved" \
  || fail "budget-cut gate let the merge in (rc $rc): $(tail -2 "$TMP/out")"

# 15 a flaky FAIL (failed, then passed on the gate's own retry) refuses this run but is never kept: the next run gates again and merges
repo v; wtadd v w; newcaller v w; echo note > "$TMP/v/notes.txt" && G "$TMP/v" add notes.txt && G "$TMP/v" commit -qm "unrelated on main"
fin v w FAIL_ONCE="$TMP/v.failed-once" FLAKY_RETRY=1 FLAKY_RETRY_MAX_S=600; rc=$?   # the gate's own retry, whatever the caller exported (FLAKY_RETRY=0 kept the FAIL)
[ "$rc" = 1 ] && grep -q "REG-APP-01 FAIL" "$TMP/out" || fail "15 setup: the flaky run should be refused (rc $rc): $(tail -2 "$TMP/out")"
: > "$TMP/v.count"
fin v w GATE_COUNT="$TMP/v.count" FAIL_ONCE="$TMP/v.failed-once" FLAKY_RETRY=1 FLAKY_RETRY_MAX_S=600; rc=$?
[ "$rc" = 0 ] && [ -s "$TMP/v.count" ] && [ -f "$TMP/v/app2.sh" ] && ok "a flaky FAIL is not kept: the next run gates again and merges" \
  || fail "a flaky FAIL was replayed (rc $rc, runs $(wc -l < "$TMP/v.count")): $(tail -2 "$TMP/out")"

# 16 a gate whose last line is JSON but no usable result (`null`, `3`, a list, a test entry that is no object, tests that are no list: it
#    died early, or something else printed last) is NO result: refused, in automerge's one JSON line, never a traceback (OCR 14/10:
#    res.get / x.get on a non-object raised AttributeError, so the Stop hook got no JSON line). The kit is this one with a fake gate.
FK="$TMP/kit"; mkdir -p "$FK/bin" "$FK/profiles" && ln -s "$DEVKIT_DIR/scripts" "$FK/scripts"
printf 'import os\nif __name__ == "__main__":\n    print("some output")\n    print(os.environ.get("FAKE_GATE_LAST", "null"))\n' > "$FK/bin/post-fix-gate.py"
repo x; wtadd x w; newcaller x w; xb="$(G "$TMP/x" rev-parse HEAD)"
for last in null 3 '[]' '{"regression_tests": [null]}' '{"regression_tests": "FAIL"}'; do
  (cd "$TMP/x" && FAKE_GATE_LAST="$last" python3 "$FK/scripts/git/worktree.py" automerge "$TMP/x-w" > "$TMP/out" 2> "$TMP/err"); rc=$?
  python3 -c 'import json,sys; d = json.loads(sys.argv[1]); sys.exit(0 if isinstance(d, dict) and d.get("status") == "blocked" and any(s in d.get("message", "") for s in ("không trả kết quả", "gave no result")) else 1)' \
      "$(tail -1 "$TMP/out")" 2>/dev/null && [ "$rc" = 1 ] && [ "$(G "$TMP/x" rev-parse HEAD)" = "$xb" ] && [ -d "$TMP/x-w" ] && ! grep -q Traceback "$TMP/err" \
    && ok "a gate whose last line is $last: no result, refused in one JSON line, main unmoved" \
    || fail "gate last line $last: rc $rc, out '$(tail -1 "$TMP/out" | cut -c1-160)', err '$(tail -1 "$TMP/err" | cut -c1-160)'"
done

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_trunk_merge: PASS"; exit 0; } || { echo "test_worktree_trunk_merge: FAIL ($FAILS)"; exit 1; }
