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
echo "-- C1c guards. a failing count in the same clause as the pass count (free at 5db81236, must stay free)"
run 0 "$RED" 'Vẫn fail: 1 failed, 4 passed.'
run 0 "$RED" 'Kết quả: 4 passed, 1 failed.'
run 0 "$RED" 'Kết quả chạy test: 4 pass, 1 fail.'
run 0 "$RED" 'Test đỏ: 4 passed, 1 failed.'
run 0 "$RED" 'pytest báo 1 failed, 4 passed; tôi chưa sửa xong.'
run 0 "$RED" 'pytest: 2 errors, 3 passed.'      # this one was a false block at 5db81236 ("pytest" near "passed"), like the two of C1c

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

echo "cases: $N"
[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
