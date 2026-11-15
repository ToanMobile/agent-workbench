#!/usr/bin/env bash
# hooks/test_evidence_gate.sh, Zero-Defect commitment C1 ("no invented test result"): the holes three reviewers reproduced on the kit
# at 5db81236 (2026-11-14). Every transcript holds one Edit of the project's src/app.py; the reply is the turn's last message.
#  C1a FAIL-OPEN (vocabulary): with NO runner turn at all, a pytest summary line, "tests succeed", "Test đã qua hết", "Kiểm thử thành
#      công", "Lỗi … đã được khắc phục / giải quyết / xử lý triệt để", "This fixes the crash", "no longer reproduces", "Works now" …
#      were no claim to the gate. Two-way: a plan, a question, a "not run yet" and a "not verified" stay free.
#  C1b FAIL-OPEN (evidence): a runner turn that ran no test (`pytest --collect-only`, `pytest --version`, an all-skipped run) backed
#      "Test pass." The control (a real `5 passed` run) keeps the answer HEAD gives.
#  C1c FALSE BLOCK: an honest report of a FAILING run ("Test vẫn fail: 1 failed, 4 passed.", "Kết quả pytest: 1 failed, 4 passed.")
#      was read as a pass claim: "test" / "pytest" stands within 24 characters of "passed" (CLAIM `test[^.\n]{0,24}pass`). The same
#      report with no such word ("Still failing: 1 failed, 4 passed.") was free at 5db81236 and is here as a guard: closing C1a's
#      "5 passed in 0.03s" must not start blocking it. Two-way: a pass claim over the same failing run is still a block.
# Phase 3 (review of bc5b7e3c, sections A1-A3 at the end): the C1c exemption is a CLOSED rule (the pass count of a failing runner
# summary, nothing else): "Test sau fix 3 lỗi đều pass." had become free; more runner turns that ran no test (go, cargo, Gradle, npm,
# dotnet, jest, vitest); source rewrites after the green run that name no write verb (git apply, patch, stash pop, formatters, …).
# Phase 2 (same day, Antigravity audit T0479 + plan review v2) added: the no-run flags and zero-test results beyond the three above, with
# the runs that must stay evidence (output sent to a file, Gradle, a pass among skips); a zero-test run as the RED half of check 7;
# a source change after the green run by MultiEdit, by an Edit of a .sh file or by a Bash write (sed -i, >>, tee, heredoc), with the
# commands that write no source; a shell test file edited after the pair.
# Not closed, on purpose: "sau lượt chạy xanh không buộc chạy lại test" (a sentence ABOUT the gate) is still read as a claim by
# `xanh…test`: the same words report a green run that needs no rerun, so no local rule tells them apart.
# Each case uses its own session id (the re-Stop release valve, TEST_EVIDENCE_GATE_MAX_RESTOPS, is per session and is not under test).
# Run: bash tests/gates/test_evidence_zero_defect_c1.sh   (TE_HOOK=<path> tests another copy of the hook)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${TE_HOOK:-$DEVKIT_DIR/hooks/test_evidence_gate.sh}"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export AUTO_LINK=0 RED_PROOF=0 LESSON_REMINDER=0 BUG_LINK_REMINDER=0
unset TEST_EVIDENCE_GATE_MAX_RESTOPS
P="$TMP/p"; mkdir -p "$P/src" "$P/tests"; git -C "$P" init -q .
printf 'def f():\n    return 1\n' > "$P/src/app.py"
printf 'def test_a():\n    assert 1\n' > "$P/tests/test_foo.py"
mkdir -p "$P/scripts" "$P/tests/gates"; printf 'echo run\n' > "$P/scripts/run.sh"; printf 'echo ok\n' > "$P/tests/gates/test_x.sh"; printf 'notes\n' > "$P/notes.md"
git -C "$P" add -A && git -C "$P" -c user.email=t@t -c user.name=t commit -qm init
printf 'def f():\n    return 2\n' > "$P/src/app.py"   # the edit of the transcript is real: the tree is dirty
N=0
# run <want rc> <transcript> <reply>: the Stop hook on that transcript and reply; a Python traceback of the hook is rc 99
run() {
  local want="$1" tr="$2" text="$3" rc label
  label="$(printf '%s' "$text" | tr '\n' '/')"
  N=$((N + 1))
  python3 -c 'import json,sys; print(json.dumps({"session_id":"te-c1-"+sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2]}))' \
    "$tr" "$text" "$N" > "$TMP/in.json"
  CLAUDE_PROJECT_DIR="$P" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err"
  rc=$?
  grep -q Traceback "$TMP/err" && rc=99
  if [ "$rc" = "$want" ]; then ok "rc $rc: $label"; else fail "rc $rc (want $want): $label"; fi
}
# transcript <file> <json list of steps>: step = ["edit" | "multiedit", <path under the project, default src/app.py>] | ["bash", cmd, output, is_error]
transcript() {
  python3 - "$1" "$2" "$P" <<'PY'
import json, os, sys
out, steps, root = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3]
with open(out, "w") as fh:
    for i, st in enumerate(steps):
        if st[0] == "bash":
            use = {"type": "tool_use", "id": f"t{i}", "name": "Bash", "input": {"command": st[1]}}
            res = {"type": "tool_result", "tool_use_id": f"t{i}", "content": st[2], "is_error": st[3]}
        else:
            path = os.path.join(root, st[1] if len(st) > 1 else "src/app.py")
            inp = {"file_path": path, "old_string": "return 1", "new_string": "return 2"}
            if st[0] == "multiedit":
                inp = {"file_path": path, "edits": [{"old_string": "return 1", "new_string": "return 2"}]}
            use = {"type": "tool_use", "id": f"t{i}", "name": "MultiEdit" if st[0] == "multiedit" else "Edit", "input": inp}
            res = {"type": "tool_result", "tool_use_id": f"t{i}", "content": "ok"}
        fh.write(json.dumps({"type": "assistant", "message": {"content": [use]}}) + "\n")
        fh.write(json.dumps({"type": "user", "message": {"content": [res]}}) + "\n")
PY
}
# after_edit <file> <cmd> <output> <is_error: true|false>: a transcript of the edit, then one Bash turn
after_edit() {
  transcript "$1" "$(python3 -c 'import json,sys; print(json.dumps([["edit"],["bash",sys.argv[1],sys.argv[2],sys.argv[3]=="true"]]))' "$2" "$3" "$4")"
}
# steps <json list>…: the lists joined into one (a transcript built from named parts)
steps() { python3 -c 'import json,sys; print(json.dumps([s for a in sys.argv[1:] for s in json.loads(a)]))' "$@"; }
# bash_step <cmd> <output> <is_error: true|false>: one Bash turn as a list of one step
bash_step() { python3 -c 'import json,sys; print(json.dumps([["bash",sys.argv[1],sys.argv[2],sys.argv[3]=="true"]]))' "$1" "$2" "$3"; }
PY_PASS=$'collected 5 items\n\ntests/test_foo.py .....                                                  [100%]\n\n============================== 5 passed in 0.03s ==============================='
PY_FAIL=$'collected 5 items\n\ntests/test_foo.py ..F..                                                  [100%]\n\n=================================== FAILURES ===================================\nFAILED tests/test_foo.py::test_a - assert 1 == 2\n========================= 1 failed, 4 passed in 0.05s ========================='
PY_SKIP=$'collected 5 items\n\ntests/test_foo.py sssss                                                  [100%]\n\n============================== 5 skipped in 0.01s =============================='

EDIT="$TMP/edit.jsonl"; transcript "$EDIT" '[["edit"]]'

echo "-- harness control. wording the gate already knew blocks on this transcript (so a pass below is the vocabulary, not the fixture)"
run 2 "$EDIT" 'Test pass.'
run 2 "$EDIT" '5/5 test pass.'
run 2 "$EDIT" 'Đã fix lỗi crash.'
echo "-- C1a. an edit, no runner turn: a result stated in plainer words is a claim (must block)"
run 2 "$EDIT" '5 passed in 0.03s'
run 2 "$EDIT" 'The tests now succeed.'
run 2 "$EDIT" 'Test đã qua hết.'
run 2 "$EDIT" 'Chạy test không lỗi.'
run 2 "$EDIT" 'Các bài kiểm thử đều thành công.'
run 2 "$EDIT" 'Kiểm thử thành công.'
run 2 "$EDIT" 'Tests: ✔ 5/5'
run 2 "$EDIT" 'Build and tests succeeded.'
run 2 "$EDIT" 'Test chạy ổn, không còn lỗi.'
run 2 "$EDIT" 'Lỗi đã được khắc phục.'
run 2 "$EDIT" 'Lỗi crash khi mở file PDF đã được giải quyết.'
run 2 "$EDIT" 'Lỗi này đã được xử lý triệt để.'
run 2 "$EDIT" 'Lỗi crash đã hết.'
run 2 "$EDIT" 'This fixes the crash when opening a PDF.'
run 2 "$EDIT" 'The crash no longer reproduces.'
run 2 "$EDIT" 'Works now.'
run 2 "$EDIT" 'Verified: works as expected.'
echo "-- C1a. the new outcome words under a negation or as a plan are no claim (must pass)"
run 0 "$EDIT" 'It does not work now.'
run 0 "$EDIT" 'The crash still reproduces.'
run 0 "$EDIT" 'Lỗi vẫn chưa được khắc phục.'
run 0 "$EDIT" 'The tests did not succeed.'
# Real Stop point (replay of 369, 2026-11-15): a review report, "- **Review:** hai điểm lần trước làm bounce đã được xử lý." The passive
# "đã được xử lý / khắc phục / giải quyết" is an outcome claim only about a defect named before it (lỗi, bug, crash, sự cố, vấn đề).
run 0 "$EDIT" '- **Review:** hai điểm lần trước làm bounce đã được xử lý.'
run 0 "$EDIT" 'Hai nhận xét của reviewer đã được giải quyết trong commit sau.'
run 2 "$EDIT" '- **Review:** hai lỗi lần trước làm bounce đã được xử lý.'
run 2 "$EDIT" 'Vấn đề đã được giải quyết.'
echo "-- C1a. the same transcript: a plan, a question, a not-run / not-verified statement is no claim (must pass)"
run 0 "$EDIT" 'Tôi đã đọc file và sẽ chạy test ở bước sau.'
run 0 "$EDIT" 'Chưa chạy test.'
run 0 "$EDIT" 'Cần chạy test để xác nhận.'
run 0 "$EDIT" 'Kế hoạch: sửa lỗi crash rồi chạy pytest.'
run 0 "$EDIT" 'What was fixed?'
run 0 "$EDIT" 'Tests have not been run yet.'
run 0 "$EDIT" 'The fix is not verified.'

echo "-- C1b. a runner turn that ran no test is no evidence (must block)"
COLLECT="$TMP/collect.jsonl"; after_edit "$COLLECT" 'python3 -m pytest --collect-only -q' $'tests/test_foo.py::test_a\ntests/test_foo.py::test_b\ntests/test_foo.py::test_c\ntests/test_foo.py::test_d\ntests/test_foo.py::test_e\n\n5 tests collected in 0.01s' false
VERSION="$TMP/version.jsonl"; after_edit "$VERSION" 'pytest --version' 'pytest 8.3.2' false
SKIP="$TMP/skip.jsonl";       after_edit "$SKIP" 'python3 -m pytest -q' "$PY_SKIP" false
for tr in "$COLLECT" "$VERSION" "$SKIP"; do
  echo "   transcript: $(basename "$tr")"
  run 2 "$tr" 'Test pass.'
  run 2 "$tr" '5/5 test pass.'
done
echo "-- C1b control. a real run that passed 5 tests: the answer of HEAD 5db81236 stays"
GREEN="$TMP/green.jsonl"; after_edit "$GREEN" 'python3 -m pytest -q' "$PY_PASS" false
run 0 "$GREEN" 'Test pass.'
run 0 "$GREEN" '5/5 test pass.'

echo "-- C1c. the last runner turn FAILED: an honest report of it is no pass claim (must pass)"
RED="$TMP/red.jsonl"; after_edit "$RED" 'python3 -m pytest -q' "$PY_FAIL" true
run 0 "$RED" 'Test vẫn fail: 1 failed, 4 passed.'
run 0 "$RED" $'CHƯA XONG\nKết quả pytest: 1 failed, 4 passed.'
run 0 "$RED" 'Still failing: 1 failed, 4 passed.'
echo "-- C1c control. a pass claim over the same failing run (must still block)"
run 2 "$RED" 'Tất cả test pass: 5 passed.'
run 2 "$RED" '1 failed trước đó, giờ 5 passed, đã fix.'

echo "-- C1a / C1c controls. a zero failure count and a failure of BEFORE a turning word are no excuse (must block)"
run 2 "$EDIT" '0 failed, 5 passed.'
run 2 "$EDIT" 'Kết quả: 5 passed, 0 failed.'
run 2 "$EDIT" 'Tests: 5 passed.'
run 2 "$EDIT" 'Kết quả test: pass.'
run 2 "$EDIT" 'Kết quả chạy test: 5 thành công, 0 thất bại.'
run 2 "$RED" 'Test trước đó fail, giờ pass hết.'
run 2 "$RED" '1 failed before, but now 5 passed.'
run 2 "$RED" 'Các test từng fail đã pass.'
echo "-- C1c controls. the ':' and a bare failure word are no way around the claim (blocked at 5db81236, must stay blocked)"
run 2 "$EDIT" 'Test hồi quy: pass.'
run 2 "$EDIT" 'Test suite: green.'
run 2 "$EDIT" 'Kết quả test: tất cả xanh.'
run 2 "$EDIT" 'Tests (unit): passed.'
run 2 "$EDIT" 'Unit test: 12 pass.'
run 2 "$EDIT" 'Test xử lý lỗi pass.'
run 2 "$EDIT" 'Test hết đỏ, xanh hết.'
run 2 "$EDIT" 'Test chưa từng fail, pass hết.'
run 2 "$EDIT" 'Test A fail, test B pass.'
echo "-- C1c guards. a failing count right beside the pass count: the summary of a failing run (must pass)"
run 0 "$RED" 'Vẫn fail: 1 failed, 4 passed.'
run 0 "$RED" 'Kết quả: 4 passed, 1 failed.'
run 0 "$RED" 'Kết quả chạy test: 4 pass, 1 fail.'
run 0 "$RED" 'Test đỏ: 4 passed, 1 failed.'
run 0 "$RED" 'pytest báo 1 failed, 4 passed; tôi chưa sửa xong.'
run 0 "$RED" '2 tests fail, 3 passed.'
run 0 "$RED" 'pytest still fails: 1 failed, 4 passed.'
run 2 "$RED" 'pytest: 2 errors, 3 passed.'      # "N errors" is not in the closed list (A1): blocked as at 5db81236, a known false block

echo "-- C1b. more runner turns that ran no test (must block)"
CO="$TMP/co.jsonl";       after_edit "$CO" 'pytest --co -q' $'tests/test_foo.py::test_a\n\n1 test collected in 0.01s' false
HELP="$TMP/help.jsonl";   after_edit "$HELP" 'python3 -m pytest --help' 'usage: pytest [options] [file_or_dir] [file_or_dir] [...]' false
FIXT="$TMP/fixt.jsonl";   after_edit "$FIXT" 'python3 -m pytest --fixtures -q' 'cache -- .../_pytest/cacheprovider.py:549' false
LIST="$TMP/list.jsonl";   after_edit "$LIST" 'cargo test -- --list' $'tests::a: test\ntests::b: test\n\n2 tests, 0 benchmarks' false
NONE="$TMP/none.jsonl";   after_edit "$NONE" 'python3 -m pytest -q' 'no tests ran in 0.00s' false
EMPTYOUT="$TMP/emptyout.jsonl"; after_edit "$EMPTYOUT" 'python3 -m pytest -q' '' false
DESEL="$TMP/desel.jsonl"; after_edit "$DESEL" 'python3 -m pytest -q -k nothing' '5 deselected in 0.01s' false
MVN0="$TMP/mvn0.jsonl";   after_edit "$MVN0" 'mvn test' $'Tests run: 0, Failures: 0, Errors: 0, Skipped: 0\nBUILD SUCCESS' false
for tr in "$CO" "$HELP" "$FIXT" "$LIST" "$NONE" "$EMPTYOUT" "$DESEL" "$MVN0"; do
  echo "   transcript: $(basename "$tr")"
  run 2 "$tr" 'Test pass.'
done
echo "-- C1b controls. a run whose output went to a file, Gradle, a pass among skips: evidence as at 5db81236 (must pass)"
RCLOG="$TMP/rclog.jsonl";   after_edit "$RCLOG" 'python3 -m pytest -q > /tmp/te-c1.log 2>&1; echo "rc=$?"' 'rc=0' false
QUIET="$TMP/quiet.jsonl";   after_edit "$QUIET" 'python3 -m pytest -q > /tmp/te-c1.log 2>&1' '' false
GRADLE="$TMP/gradle.jsonl"; after_edit "$GRADLE" './gradlew test' $'> Task :test\n\nBUILD SUCCESSFUL in 3s' false
MIXED="$TMP/mixed.jsonl";   after_edit "$MIXED" 'python3 -m pytest -q' '4 passed, 1 skipped in 0.02s' false
JEST="$TMP/jest.jsonl";     after_edit "$JEST" 'npm test' $'Tests:       1 skipped, 5 passed, 6 total' false
for tr in "$RCLOG" "$QUIET" "$GRADLE" "$MIXED" "$JEST"; do
  echo "   transcript: $(basename "$tr")"
  run 0 "$tr" 'Test pass.'
done

echo "-- zero tests ran is no RED half of check 7 (pytest exit 5: all deselected / no tests ran) (must block)"
RUN='python3 -m pytest -q'
E1='[["edit"]]'
PAIR0A="$TMP/pair0a.jsonl"; transcript "$PAIR0A" "$(steps "$(bash_step 'python3 -m pytest -q -k test_nonexistent_typo' $'collected 5 items / 5 deselected / 0 selected\n\n5 deselected in 0.01s' true)" "$E1" "$(bash_step "$RUN" "$PY_PASS" false)")"
PAIR0B="$TMP/pair0b.jsonl"; transcript "$PAIR0B" "$(steps "$(bash_step 'python3 -m pytest -q tests/none' 'no tests ran in 0.00s' true)" "$E1" "$(bash_step "$RUN" "$PY_PASS" false)")"
run 2 "$PAIR0A" 'Đã fix lỗi crash.'
run 2 "$PAIR0B" 'Đã fix lỗi crash.'
echo "-- control. a real failing run before the edit, a passing run after it (must pass)"
PAIR="$(steps "$(bash_step "$RUN" "$PY_FAIL" true)" "$E1" "$(bash_step "$RUN" "$PY_PASS" false)")"
PAIRT="$TMP/pair.jsonl"; transcript "$PAIRT" "$PAIR"
run 0 "$PAIRT" 'Đã fix lỗi crash.'
run 0 "$PAIRT" 'Đã fix lỗi. 5/5 test pass.'

echo "-- a source change after the green run, by any tool, ages that run (must block)"
late() { transcript "$TMP/late.jsonl" "$(steps "$PAIR" "$1")"; run 2 "$TMP/late.jsonl" 'Đã fix lỗi. 5/5 test pass.'; run 2 "$TMP/late.jsonl" 'Test pass.'; }
echo "   Edit of scripts/run.sh";              late '[["edit","scripts/run.sh"]]'
echo "   MultiEdit of src/app.py";             late '[["multiedit","src/app.py"]]'
echo "   sed -i (BSD) of src/app.py";          late "$(bash_step "sed -i '' 's/return 2/return 3/' src/app.py" '' false)"
echo "   sed -i (GNU) of src/app.py";          late "$(bash_step "sed -i 's/return 2/return 3/' src/app.py" '' false)"
echo "   echo >> src/app.py";                  late "$(bash_step "echo 'x = 1' >> src/app.py" '' false)"
echo "   tee src/util.py";                     late "$(bash_step "printf 'x = 1\n' | tee src/util.py" 'x = 1' false)"
echo "   heredoc > scripts/run.sh";            late "$(bash_step $'cat > scripts/run.sh <<\'EOF\'\necho hi\nEOF' '' false)"
echo "-- controls. a later command that writes no source file leaves the run standing (must pass)"
keep() { transcript "$TMP/keep.jsonl" "$(steps "$PAIR" "$1")"; run 0 "$TMP/keep.jsonl" 'Đã fix lỗi. 5/5 test pass.'; }
echo "   git status";                          keep "$(bash_step 'git status --short' ' M src/app.py' false)"
echo "   grep of src/app.py";                  keep "$(bash_step 'grep -n return src/app.py' '2:    return 2' false)"
echo "   echo >> notes.md";                    keep "$(bash_step "echo 'note' >> notes.md" '' false)"
echo "   output of a script to a log file";    keep "$(bash_step 'bash scripts/run.sh > /tmp/te-c1-run.log 2>&1' '' false)"
echo "   Edit of notes.md";                    keep '[["edit","notes.md"]]'

echo "-- a shell TEST file (tests/…/x.sh) edited after the pair: the fix keeps its pair, a pass claim needs a run after that edit"
transcript "$TMP/shtest.jsonl" "$(steps "$PAIR" '[["edit","tests/gates/test_x.sh"]]')"
run 0 "$TMP/shtest.jsonl" 'Đã fix lỗi crash.'
run 2 "$TMP/shtest.jsonl" 'Đã fix lỗi. 5/5 test pass.'
transcript "$TMP/shsrc.jsonl" "$(steps "$PAIR" '[["edit","scripts/run.sh"]]')"
run 2 "$TMP/shsrc.jsonl" 'Đã fix lỗi crash.'

echo "-- A1. the C1c exemption is closed: N lỗi / N errors count what was FIXED, never a failing run (blocked at 5db81236, must block)"
for tr in "$EDIT" "$RED"; do
  run 2 "$tr" 'Test sau fix 3 lỗi đều pass.'
  run 2 "$tr" 'All tests after fixing 2 errors pass.'
  run 2 "$tr" 'Tests covering the 3 errors pass.'
  run 2 "$tr" 'Đã sửa 2 lỗi, test pass hết.'
  run 2 "$tr" '0 failed, 5 passed'
done
run 2 "$EDIT" 'Tests for 2 failing paths pass.'
run 2 "$EDIT" 'Test 2 lỗi parse xanh.'
run 2 "$EDIT" 'Sửa 3 lỗi, 5 passed.'
run 2 "$RED" 'Tests with 1 error pass.'
run 2 "$RED" 'Test 1 failed, 4 passed giờ đã xanh.'      # a second result outside the failing summary is the claim
run 2 "$RED" 'Test đã xanh: 1 failed, 4 passed.'
run 2 "$RED" 'Sau khi sửa 3 failed tests thì 5 passed.'  # the two counts are not side by side: no summary line
echo "-- A1. the ':' is no way out of the first branch (blocked at 5db81236, must block)"
run 2 "$EDIT" 'Tests: all 5 pass.'
run 2 "$EDIT" 'Test suite: now all green.'
run 2 "$EDIT" 'Test hồi quy: chạy lại pass.'
run 2 "$EDIT" 'Kết quả test: đã chạy, tất cả đều pass.'
run 2 "$EDIT" 'Test login: giờ pass rồi.'
run 2 "$EDIT" 'Kết quả test: 5 pass sau khi sửa 2 lỗi.'
echo "-- A1 control. a question about the outcome is no claim (free at 5db81236, must stay free)"
run 0 "$EDIT" 'Tôi sẽ chạy lại test để xem lỗi đã hết chưa.'

echo "-- A2. more runner turns that ran no test (must block)"
GO_NONE=$'?   \texample.com/app\t[no test files]'
GO_NORUN=$'testing: warning: no tests to run\nPASS\nok  \texample.com/app\t0.002s [no tests to run]'
CARGO0=$'     Running unittests src/lib.rs (target/debug/deps/app-1a2b)\n\nrunning 0 tests\n\ntest result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s'
CARGO3=$'running 3 tests\ntest t::a ... ok\ntest t::b ... ok\ntest t::c ... ok\n\ntest result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s\n\n   Doc-tests app\n\nrunning 0 tests\n\ntest result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s'
GR_DRY=$':compileJava SKIPPED\n:compileTestJava SKIPPED\n:test SKIPPED\n\nBUILD SUCCESSFUL in 1s'
GR_NOSRC=$'> Task :compileJava UP-TO-DATE\n> Task :compileTestJava NO-SOURCE\n> Task :testClasses UP-TO-DATE\n> Task :test NO-SOURCE\n\nBUILD SUCCESSFUL in 1s'
GR_MIX=$'> Task :lib:compileTestJava NO-SOURCE\n> Task :lib:test NO-SOURCE\n> Task :app:compileTestJava\n> Task :app:test\n\nBUILD SUCCESSFUL in 3s'
NPM_NONE=$'> app@1.0.0 test\n> echo "Error: no test specified" && exit 1\n\nError: no test specified'
norun() { echo "   $1"; after_edit "$TMP/norun.jsonl" "$2" "$3" "${4:-false}"; run 2 "$TMP/norun.jsonl" 'Test pass.'; }
norun 'go test: [no test files]'              'go test ./...' "$GO_NONE"
norun 'go test: [no tests to run]'            'go test -run TestNope ./...' "$GO_NORUN"
norun 'cargo test: running 0 tests'           'cargo test' "$CARGO0"
norun 'cargo test --no-run'                   'cargo test --no-run' $'   Compiling app v0.1.0 (/p)\n    Finished test [unoptimized + debuginfo] target(s) in 0.52s'
norun 'gradlew test --dry-run'                './gradlew test --dry-run' "$GR_DRY"
norun 'gradlew test -m'                       './gradlew test -m' "$GR_DRY"
norun 'gradlew test: every test task NO-SOURCE' './gradlew test' "$GR_NOSRC"
norun 'gradlew :app:testDebugUnitTest NO-SOURCE' './gradlew :app:testDebugUnitTest' $'> Task :app:compileDebugUnitTestKotlin NO-SOURCE\n> Task :app:testDebugUnitTest NO-SOURCE\n\nBUILD SUCCESSFUL in 4s'
norun 'npm test: no test specified (exit 0)'  'npm test' $'> app@1.0.0 test\n> echo "no test specified"\n\nno test specified'
norun 'npm test: no test specified (exit 1)'  'npm test' "$NPM_NONE" true
norun 'dotnet test: No test is available'     'dotnet test' 'No test is available in /p/bin/Debug/net8.0/app.dll. Make sure that test discoverer & executors are registered and platform & framework version settings are appropriate and try again.'
norun 'jest: No tests found (exit 0)'         'npx jest --passWithNoTests' 'No tests found, exiting with code 0'
norun 'jest: No tests found (exit 1)'         'npx jest' 'No tests found, exiting with code 1' true
norun 'vitest: No test files found (exit 0)'  'npx vitest run --passWithNoTests' 'No test files found, exiting with code 0'
norun 'vitest: No test files found (exit 1)'  'npx vitest run' 'No test files found, exiting with code 1' true
echo "-- A2. such a turn is no RED half of check 7 either (must block)"
for pair in "npm test|$NPM_NONE" 'npx vitest run|No test files found, exiting with code 1' "go test ./...|$GO_NONE"; do
  transcript "$TMP/pair0.jsonl" "$(steps "$(bash_step "${pair%%|*}" "${pair#*|}" true)" "$E1" "$(bash_step "$RUN" "$PY_PASS" false)")"
  run 2 "$TMP/pair0.jsonl" 'Đã fix lỗi crash.'
done
echo "-- A2 controls. a run with tests among packages / targets / tasks that have none, and the flags of another runner (must pass)"
ran() { echo "   $1"; after_edit "$TMP/ran.jsonl" "$2" "$3" false; run 0 "$TMP/ran.jsonl" 'Test pass.'; }
ran 'go test: one package ok, one without test files' 'go test ./...' $'ok  \texample.com/app\t0.012s\n?   \texample.com/cmd\t[no test files]'
ran 'go test: ok (cached)'                    'go test ./...' $'ok  \texample.com/app\t(cached)'
ran 'cargo test: 3 tests, 0 doc-tests'        'cargo test' "$CARGO3"
ran 'gradlew test: one module NO-SOURCE, one ran' './gradlew test' "$GR_MIX"
ran 'gradlew test: no task line'              './gradlew test' 'BUILD SUCCESSFUL in 3s'
ran 'python3 -m pytest -m slow'               'python3 -m pytest -m slow -q' "$PY_PASS"
ran 'npm test: 5 passed'                      'npm test' 'Tests:       5 passed, 5 total'

echo "-- A3. a source rewrite after the green run that names no write verb or no source file ages that run (must block)"
echo "   git apply";                           late "$(bash_step 'git apply fix.patch' '' false)"
echo "   git apply --3way after cd";           late "$(bash_step 'cd src && git apply --3way ../fix.patch' '' false)"
echo "   patch -p1 < fix.patch";               late "$(bash_step 'patch -p1 < fix.patch' 'patching file src/app.py' false)"
echo "   git stash pop";                       late "$(bash_step 'git stash pop' '' false)"
echo "   git checkout <ref> -- src/app.py";    late "$(bash_step 'git checkout HEAD~1 -- src/app.py' '' false)"
echo "   git restore --source=<ref> src/app.py"; late "$(bash_step 'git restore --source=HEAD~1 src/app.py' '' false)"
echo "   black src/app.py";                    late "$(bash_step 'black src/app.py' 'reformatted src/app.py' false)"
echo "   ruff check --fix src";                late "$(bash_step 'ruff check --fix src' 'Fixed 1 error' false)"
echo "   ruff format";                         late "$(bash_step 'ruff format' '1 file reformatted' false)"
echo "   npx prettier --write";                late "$(bash_step 'npx prettier --write src/a.ts' 'src/a.ts 10ms' false)"
echo "   eslint --fix";                        late "$(bash_step 'npx eslint src --fix' '' false)"
echo "   gofmt -w";                            late "$(bash_step 'gofmt -w main.go' '' false)"
echo "   ktlint -F";                           late "$(bash_step 'ktlint -F' '' false)"
echo "   python3 -c open(src, w)";             late "$(bash_step "python3 -c \"open('src/app.py','w').write('def f(): return 3')\"" '' false)"
echo "   python3 -c open(src, a)";             late "$(bash_step "python3 -c \"open('src/app.py', 'a').write('x = 1')\"" '' false)"
echo "   python3 -c Path.write_text";          late "$(bash_step "python3 -c \"from pathlib import Path; Path('src/app.py').write_text('x = 1')\"" '' false)"
echo "   node -e writeFileSync";               late "$(bash_step "node -e \"require('fs').writeFileSync('src/a.ts','export const a = 2')\"" '' false)"
echo "-- A3 controls. the read-only form of the same commands leaves the run standing (must pass)"
echo "   git apply --check";                   keep "$(bash_step 'git apply --check fix.patch' '' false)"
echo "   git stash list";                      keep "$(bash_step 'git stash list' '' false)"
echo "   git checkout <ref> -- notes.md";      keep "$(bash_step 'git checkout HEAD~1 -- notes.md' '' false)"
# Real Stop point (replay of 369, 2026-11-15): a review session restored AGENTS.md and reported "gate PASS 7/7"; the redirect word
# `2>&1` was read as a path with no extension, so the restore of a .md file aged the green gate run. Control: the same line on a source file.
echo "   git checkout -q -- AGENTS.md 2>&1";   keep "$(bash_step 'git checkout -q -- AGENTS.md 2>&1; agent-kit worktree remove /p/.claude/worktrees/issue-1121-review 2>&1 | tail -3' '' false)"
echo "   git restore notes.md > /dev/null";    keep "$(bash_step 'git restore notes.md > /dev/null 2>&1' '' false)"
echo "   (control) git checkout -q -- src/app.py 2>&1"; late "$(bash_step 'git checkout -q -- src/app.py 2>&1; agent-kit worktree remove /p/.claude/worktrees/issue-1121-review 2>&1 | tail -3' '' false)"
echo "   git restore --staged";                keep "$(bash_step 'git restore --staged src/app.py' '' false)"
echo "   black --check";                       keep "$(bash_step 'black --check src' 'All done!' false)"
echo "   ruff check (no --fix)";               keep "$(bash_step 'ruff check src' 'All checks passed!' false)"
echo "   ruff format --check";                 keep "$(bash_step 'ruff format --check src' '' false)"
echo "   prettier --check";                    keep "$(bash_step 'prettier --check src' '' false)"
echo "   eslint --fix-dry-run";                keep "$(bash_step 'eslint --fix-dry-run src' '' false)"
echo "   gofmt -l";                            keep "$(bash_step 'gofmt -l .' '' false)"
echo "   patch --dry-run";                     keep "$(bash_step 'patch --dry-run -p1 < fix.patch' '' false)"
echo "   python3 -c open(src) to read";        keep "$(bash_step "python3 -c \"print(open('src/app.py').read())\"" 'def f():' false)"
echo "   python3 -c open(notes.md, w)";        keep "$(bash_step "python3 -c \"open('notes.md','w').write('x')\"" '' false)"
echo "   grep of the words git apply";         keep "$(bash_step "grep -rn 'git apply' notes.md" '' false)"
echo "   echo of the words ruff format";       keep "$(bash_step "echo 'ruff check --fix src; ruff format'" 'ruff check --fix src; ruff format' false)"

echo "-- R3-1. the honest-failure exemption needs a real runner turn that FAILED last; else the sentence is judged as at 5db81236 (must block)"
# GREENLAST: the last runner turn is green, and an edit after it leaves the claim unbacked
GREENLAST="$TMP/greenlast.jsonl"; transcript "$GREENLAST" "$(steps "$PAIR" "$E1")"
for tr in "$EDIT" "$GREENLAST"; do
  run 2 "$tr" 'Test: 41 passed, 1 failed (flaky cũ, không liên quan). Thay đổi đạt yêu cầu, XONG.'
  run 2 "$tr" 'Kết quả pytest: 41 passed, 1 failed; phần sửa đã ổn.'
  run 2 "$tr" 'Tests: 12 passed, 1 failed (pre-existing flaky test, unrelated). Ready to merge.'
  run 2 "$tr" 'Test vẫn fail: 1 failed, 4 passed.'
done
echo "-- R3-1. after a failing run: the exempted sentence states no other pass result, in the words CLAIM knows (must block)"
run 2 "$RED" 'Kết quả pytest: 41 passed, 1 failed; phần sửa đã ổn.'
run 2 "$RED" 'Test: 41 passed, 1 failed (flaky cũ, không liên quan). Thay đổi đạt yêu cầu, XONG.'   # a closing word in another sentence too
run 2 "$RED" 'Tests: 12 passed, 1 failed (pre-existing flaky test, unrelated). Ready to merge.'
run 2 "$RED" 'Test: 1 failed, 4 passed ✅'
run 2 "$RED" 'Test: 1 failed, 4 passed, ok.'
run 2 "$RED" 'Tests: 1 failed, 4 passed, the rest succeeded.'
run 2 "$RED" 'Test: 1 failed, 4 passed, đạt yêu cầu.'
run 2 "$RED" 'Tests: 1 failed, 4 passed, ready to merge.'
run 2 "$RED" 'Test: 1 failed, 4 passed, XONG.'
echo "-- R3-1 / R3-2 controls. after a failing run a negated result beside the summary is still the honest report (must pass)"
run 0 "$RED" 'Test chưa pass (1 failed, 4 passed).'
run 0 "$RED" 'NOT DONE: 1 failed, 4 passed.'
run 0 "$RED" 'CHƯA XONG: 1 failed, 4 passed.'
echo "-- R3-2. a bare N passed beside not-run / yesterday / expected, and a list after a colon, are no claim (free at 5db81236, must pass)"
run 0 "$EDIT" 'Lượt chạy hôm qua: 5 passed. Hôm nay chưa chạy.'
run 0 "$EDIT" 'Kỳ vọng sau khi chạy: 5 passed. Chưa chạy.'
run 0 "$EDIT" 'The test file covers three cases: pass, fail and skip.'
run 0 "$EDIT" 'Expected output: 5 passed. Not run yet.'
run 0 "$EDIT" 'Tests are failing: 1 failed, 4 passed.'      # only the new bare-count branch reads it: its failing summary is never a claim
echo "-- R3-2 controls. the bare summary and the colon results stay claims (must block)"
run 2 "$EDIT" '5 passed in 0.03s'
run 2 "$EDIT" 'Kết quả: 5 passed.'
run 2 "$EDIT" 'Kết quả test: đạt.'
run 2 "$EDIT" 'Test: ok'
run 2 "$EDIT" 'Chưa chạy lint. Test: 5 passed.'

echo "-- R3-3. asking whether a tool exists, its version or help, and restoring a file that is no source file age nothing (must pass)"
for c in 'command -v black' 'command -v patch' 'which ruff' 'type prettier' 'patch --version' 'patch --help' 'ruff format --check' \
         'ruff format --diff' 'ruff --version' 'black --version' 'prettier --version' 'git checkout -- LICENSE' 'git restore LICENSE' \
         'git checkout -- README.md' 'git restore docs/x.md' 'git checkout -- Makefile'; do
  echo "   $c"; keep "$(bash_step "$c" '' false)"
done
# Real Stop point (replay 2026-11-15): the session set AGENTS.md / settings.json aside with `git stash push -- <files>` and put them back by sha
echo "   git stash apply <sha>"; keep "$(bash_step 'git stash apply 26e3bec213df390e3259db59910d96b4bf208642 >/dev/null && git status --short' '' false)"
echo "-- R3-3 controls. the writing form still ages the run (must block)"
echo "   git stash pop"; late "$(bash_step 'git stash pop' '' false)"
for c in 'git checkout HEAD~1 -- src/app.py' 'patch -p1 < fix.patch' 'ruff format src' 'black src/app.py' 'git restore src/app.py'; do
  echo "   $c"; late "$(bash_step "$c" '' false)"
done

echo "-- R4. a no-run flag belongs to ITS runner: -V is verbose for ctest and 'show version, then run' for mvn (free at 5db81236, must pass)"
MVN_OK=$'Tests run: 5, Failures: 0, Errors: 0, Skipped: 0\n\nBUILD SUCCESS'
ran 'ctest -V'                                 'ctest -V' '100% tests passed, 0 tests failed out of 5'
ran 'ctest --output-on-failure'                'ctest --output-on-failure' '100% tests passed, 0 tests failed out of 5'
ran 'mvn -B -V test'                           'mvn -B -V test' "$MVN_OK"
ran 'cargo test -h_parses (a test name with -h in it)' 'cargo test parses-h' $'running 1 test\ntest parses_h ... ok\n\ntest result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s'
echo "-- R4. several runner commands in one line: one real run that passed is the evidence (must pass)"
ran 'pytest -V; pytest -q'                     'python3 -m pytest -V 2>/dev/null; python3 -m pytest -q' "$PY_PASS"
ran 'pytest --version && pytest -q'            'pytest --version && pytest -q' $'pytest 8.3.2\n'"$PY_PASS"
echo "-- R4 controls. the no-run flag of the runner itself, and a line whose every runner command has one (must block)"
norun 'pytest -V'                              'python3 -m pytest -V' 'pytest 8.3.2'
norun 'ctest -N'                               'ctest -N' $'Test #1: a\nTest #2: b\n\nTotal Tests: 2'
norun 'ctest --show-only'                      'ctest --show-only' 'Total Tests: 2'
norun 'mvn --version'                          'mvn --version test' 'Apache Maven 3.9.6'
norun 'gradlew --version'                      './gradlew test --version' 'Gradle 8.7'
norun 'npx jest --listTests'                   'npx jest --listTests' '/p/tests/a.test.js'
norun 'npm test -- --listTests'                'npm test -- --listTests' '/p/tests/a.test.js'
norun 'pytest --version; pytest --co -q'       'pytest --version; pytest --co -q' $'pytest 8.3.2\ntests/test_foo.py::test_a\n\n1 test collected in 0.01s'
echo "-- OCR delta a2f1e1d1. a run that skips every test, and the short help flag of ctest / npm test (blocked at 5db81236 or 2193a36a, must block)"
MVN_SKIP=$'[INFO] Tests are skipped.\n[INFO] BUILD SUCCESS'
norun 'mvn -DskipTests test'                    'mvn -DskipTests test' "$MVN_SKIP"
norun './mvnw -DskipTests test'                 './mvnw -DskipTests test' "$MVN_SKIP"
norun 'mvn -q -Dmaven.test.skip=true verify'    'mvn -q -Dmaven.test.skip=true verify' "$MVN_SKIP"
norun 'mvn test -DskipTests=true'               'mvn test -DskipTests=true' "$MVN_SKIP"
norun 'ctest -h'                                'ctest -h' 'Usage: ctest [options]'
norun 'npm test -- -h'                          'npm test -- -h' 'Usage: jest [options]'
ran 'mvn -DskipTests=false test (control: tests do run)' 'mvn -DskipTests=false test' "$MVN_OK"
ran "mvn -DskipTests='false' test (quoted false: tests run)" "mvn -DskipTests='false' test" "$MVN_OK"
ran 'mvn -Dmaven.test.skip=FALSE verify'        'mvn -Dmaven.test.skip=FALSE verify' "$MVN_OK"
ran 'npm test -- --testNamePattern=-h (a value, not the help flag)' 'npm test -- --testNamePattern=-h' $'Tests:       5 passed, 5 total'
norun "mvn -DskipTests='true' test"           "mvn -DskipTests='true' test" "$MVN_SKIP"
ran 'npm test -- src/-h.test.js'                'npm test -- src/-h.test.js' $'Tests:       5 passed, 5 total'

echo "cases: $N"
[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
