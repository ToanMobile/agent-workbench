#!/usr/bin/env bash
# hooks/test_evidence_gate.sh: the false blocks of session f294e5d9 (2026-10-25 DevKit audit, FINDINGS A.1-A.2) and the fail-open found
# next to them. Every reply and tool result below is a real one from transcripts of 10/2026, or the shape of one.
#  A. FALSE BLOCK (classifier): the TDD cycle name "test RED→GREEN" / "test ĐỎ→XANH" in a proposal, a prohibition of running it, or a
#     step list joined by ", rồi <verb>" ("then") was read as a pass claim: CYCLE_PLAN had no proposal / prohibition, CYCLE_DONE took
#     the sequencing "rồi" for "already".
#  B. FALSE BLOCK (evidence): a kit suite run as `bash tests/…/test_x.sh > log 2>&1; echo "rc=$?"` printed its exit code, but
#     runner_state() read neither it (two segments: not a direct run) nor `✘` as red.
#  C. FAIL-OPEN: a call a hook or the harness REFUSED (is_error, "PreToolUse:… hook error" / "Refusing to run it") was counted as a
#     RED run, so it could be the RED half of check 7's pair.
#  E. FALSE BLOCK (classifier): a negated assertion verb before the outcome / result ("Tôi chưa chốt đã fix", "I'm not claiming a test
#     pass") was read as the claim itself.
# Each exemption has a "must still block" set: the audit's first patch (word anywhere in the sentence, unanchored negation, any
# "rồi <word>") let every one of them through, the stock hook blocks them all.
# The audit's option D (the gate's full-pass receipt backs a claim) is left out on purpose (leader, 2026-10-25), so it has no case.
# The review of that fix (2026-10-25) added must-still-block cases to A, B and E (fail-opens of the first version) and P: a tool result
# of 30 000 blank lines must be read in ≤ 2 s (a `^\s*` line anchor made it 4-68 s, the Stop hook is cut at 30 s).
# Run: bash tests/gates/test_evidence_false_blocks.sh   (TE_HOOK=<path> tests another copy of the hook)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${TE_HOOK:-$DEVKIT_DIR/hooks/test_evidence_gate.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export AUTO_LINK=0 RED_PROOF=0 LESSON_REMINDER=0 BUG_LINK_REMINDER=0
P="$TMP/p"; mkdir -p "$P/src" "$P/tests/a"; git -C "$P" init -q .
printf 'x = 1\n' > "$P/src/a.py"
git -C "$P" add -A && git -C "$P" -c user.email=t@t -c user.name=t commit -qm init
N=0
# run <want rc> <transcript> <reply> [label: what the line prints instead of the reply]
run() {
  local want="$1" tr="$2" text="$3" label="${4:-${3:0:110}}" rc
  N=$((N + 1))
  python3 -c 'import json,sys; print(json.dumps({"session_id":"te-fb-"+sys.argv[3],"transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2]}))' \
    "$tr" "$text" "$N" > "$TMP/in.json"
  CLAUDE_PROJECT_DIR="$P" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err"
  rc=$?
  grep -q Traceback "$TMP/err" && rc=99
  if [ "$rc" = "$want" ]; then ok "rc $rc: $label"; else fail "rc $rc (want $want): $label"; fi
}
EMPTY="$TMP/empty.jsonl"; : > "$EMPTY"
# transcript <file> <json list of steps>: step = ["bash", cmd, output, is_error] | ["edit", path]
transcript() {
  python3 - "$1" "$2" <<'PY'
import json, sys
out, steps = sys.argv[1], json.loads(sys.argv[2])
with open(out, "w") as fh:
    for i, st in enumerate(steps):
        if st[0] == "bash":
            fh.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": f"t{i}", "name": "Bash", "input": {"command": st[1]}}]}}) + "\n")
            fh.write(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": st[2], "is_error": st[3]}]}}) + "\n")
        else:
            fh.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": f"t{i}", "name": "Edit", "input": {"file_path": st[1], "old_string": "x = 1", "new_string": "x = 2"}}]}}) + "\n")
            fh.write(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": "ok"}]}}) + "\n")
PY
}

echo "-- A. the cycle name in a plan / proposal / prohibition is no result (real replies, f294e5d9 L297, L318, L1094)"
# L297 as written ("Sửa ở template của kit, kèm test RED→GREEN, rồi đồng bộ sang các repo.") carries no plan marker, and a bare ", rồi"
# cannot tell it from a done report (leader, 2026-10-25): the plan sentence below states it is the next step.
run 0 "$EMPTY" 'Bước tiếp theo: sửa ở template của kit, kèm test RED→GREEN, rồi đồng bộ sang các repo.'
run 0 "$EMPTY" 'Lý do không cài nguyên gói Cloudflare: đó là 22 file kèm validator Node, nó trùng trigger với `security-checklist`, và luật sandbox của nó chặn luôn việc chạy test ĐỎ→XANH trên macOS.'
run 0 "$EMPTY" 'Tôi đề xuất làm tiếp theo thứ tự: 2 → 1 → 5 → 3, mỗi việc một commit có test ĐỎ→XANH riêng.'
echo "-- A. must still block: the cycle name WITH a done word, a count or a result (real replies of 13/10, 17/10, 24/10)"
run 2 "$EMPTY" 'Đã chạy test RED→GREEN.'
run 2 "$EMPTY" 'Test RED→GREEN, 12/12 pass.'
run 2 "$EMPTY" 'Mỗi sửa có test ĐỎ→XANH, có công tắc tắt và RED-proof.'
run 2 "$EMPTY" 'Tests are green, with a RED→GREEN pair for the new validator check.'
run 2 "$EMPTY" 'Mọi ca test mới đều có cặp RED→GREEN: 5 ca đỏ trước bản sửa đầu, thêm ca 11 đỏ trước từng bản sửa sau.'
run 2 "$EMPTY" 'Đã sửa xong, test ĐỎ→XANH rồi.'
echo "-- A. must still block: a prohibition / proposal word that does not govern the cycle name, a particle after rồi"
run 2 "$EMPTY" 'Guard chặn push có test ĐỎ→XANH.'
run 2 "$EMPTY" 'Hook mới block push lên main, có test RED→GREEN.'
run 2 "$EMPTY" 'Sửa theo đề xuất của reviewer, có test ĐỎ→XANH.'
run 2 "$EMPTY" 'Test ĐỎ→XANH rồi nhé.'
echo "-- A. must still block: a proposal that does not open the sentence or does not govern the name, a done report joined by \", rồi\""
echo "   (2026-10-25 review of af339645: Vietnamese has no tense, \", rồi <verb>\" is a plan only next to an explicit plan marker)"
run 2 "$EMPTY" 'Sửa theo đúng những gì tôi đề xuất, có test ĐỎ→XANH.'
run 2 "$EMPTY" 'Như tôi đề xuất hôm qua, mỗi bước có test ĐỎ→XANH riêng.'
run 2 "$EMPTY" 'Tôi đề xuất merge luôn: mỗi sửa đều có test ĐỎ→XANH.'
run 2 "$EMPTY" 'Tôi đề xuất merge luôn vì mỗi sửa đều có test ĐỎ→XANH.'
run 2 "$EMPTY" 'I recommend merging now: every fix comes with its test RED→GREEN.'
run 2 "$EMPTY" 'Test ĐỎ→XANH, rồi anh ạ.'
run 2 "$EMPTY" 'Test ĐỎ→XANH, rồi sếp.'
run 2 "$EMPTY" 'Test ĐỎ→XANH, rồi nè.'
run 2 "$EMPTY" 'Test ĐỎ→XANH, rồi á.'
run 2 "$EMPTY" 'Test ĐỎ→XANH, rồi thôi.'
run 2 "$EMPTY" 'Viết test ĐỎ→XANH cho bug X, rồi push lên main.'
run 2 "$EMPTY" 'Mỗi sửa có test ĐỎ→XANH, rồi merge vào main.'
run 2 "$EMPTY" 'Mỗi sửa có test ĐỎ→XANH, rồi merge vào main, chưa push.'
run 2 "$EMPTY" 'Sau khi gỡ luật chặn chạy test ĐỎ→XANH thì mọi ca đều qua.'
echo "-- A. the real claim of f294e5d9 L1107 stays a claim with no evidence"
CLAIM='Lần này lộ thêm một lỗi của chính hook: hai script kiểm tra tôi đã chạy và thấy xanh (`test_repo_consistency.sh` và `test_agents_md_block_size.sh`) đều là script bash.'
run 2 "$EMPTY" "$CLAIM"

echo "-- B. a kit suite with its exit echoed by the next segment (f294e5d9 use#412 / use#349)"
transcript "$TMP/b1.jsonl" '[["bash","bash universal-agent-devkit/tests/verification/test_repo_consistency.sh > /tmp/rc3.log 2>&1; echo \"rc_exit=$?\"; grep -E \"✘|R5 removed\" /tmp/rc3.log","rc_exit=0\n✔ R5 removed deprecated aliases stay removed\n✔ R5 every alias in sync_commands.sh is a link",false]]'
run 0 "$TMP/b1.jsonl" "$CLAIM"
transcript "$TMP/b2.jsonl" '[["bash","bash universal-agent-devkit/tests/verification/test_repo_consistency.sh > /tmp/rc1.log 2>&1; echo \"exit=$?\"; grep -E \"✖|R5\" /tmp/rc1.log","exit=1\n✔ R5 every documented /command exists\n✘ R5 removed deprecated aliases stay removed",false]]'
run 2 "$TMP/b2.jsonl" "$CLAIM"
echo "-- B. must still block: \$? of a pipe, an unbound suite, a loop"
transcript "$TMP/b3.jsonl" '[["bash","bash tests/a/test_x.sh 2>&1 | tail -3; echo \"rc=$?\"","rc=0",false]]'
run 2 "$TMP/b3.jsonl" "$CLAIM"
transcript "$TMP/b4.jsonl" '[["bash","bash tests/a/test_x.sh; bash tests/a/test_y.sh > /tmp/y.log 2>&1; echo \"rc=$?\"","something\nrc=0",false]]'
run 2 "$TMP/b4.jsonl" "$CLAIM"
transcript "$TMP/b5.jsonl" '[["bash","for f in tests/a/test_x.sh tests/a/test_y.sh; do bash \"$f\" > /dev/null 2>&1; done; echo \"rc=$?\"","rc=0",false]]'
run 2 "$TMP/b5.jsonl" "$CLAIM"
PASSCLAIM='Đã chạy lại bộ test: 12/12 test pass.'
FIXCLAIM='Đã fix bug X trong src/a.py.'
# steps_after_edit <cmd> <output>: an edit of src/a.py, then the command. pair <cmd> <red output> <green output>: run, edit, run again.
steps_after_edit() { python3 -c 'import json,sys; print(json.dumps([["edit",sys.argv[1]],["bash",sys.argv[2],sys.argv[3],False]]))' "$P/src/a.py" "$1" "$2"; }
pair() { python3 -c 'import json,sys; c=sys.argv[2]; print(json.dumps([["bash",c,sys.argv[3],False],["edit",sys.argv[1]],["bash",c,sys.argv[4],False]]))' "$P/src/a.py" "$1" "$2" "$3"; }
echo "-- B. must still block: the echoed \$? of a segment that names a test file but runs no test (2026-10-25 review of af339645, P1)"
for c in 'bash -n tests/a/test_x.sh; echo "rc=$?"' \
         'shellcheck tests/a/test_x.sh; echo "sc=$?"' \
         '[ -f tests/a/test_x.sh ]; echo "rc=$?"' \
         'test -x tests/a/test_x.sh; echo "rc=$?"' \
         'chmod +x tests/a/test_x.sh; echo "rc=$?"' \
         'bash -c "bash tests/a/test_x.sh || true" > /tmp/l 2>&1; echo "rc=$?"' \
         'eval "bash tests/a/test_x.sh; true" > /tmp/l 2>&1; echo "rc=$?"' \
         '! bash tests/a/test_x.sh > /tmp/l 2>&1; echo "rc=$?"'; do
  out='rc=0'; case "$c" in *sc=*) out='sc=0';; esac
  transcript "$TMP/b6.jsonl" "$(steps_after_edit "$c" "$out")"
  run 2 "$TMP/b6.jsonl" "$PASSCLAIM" "$out after \`$c\`: $PASSCLAIM"
done
echo "-- B. must still block: a RED→GREEN pair for check 7 made of two such non-runs"
transcript "$TMP/b7.jsonl" "$(pair '[ -f tests/a/test_x.sh ]; echo "rc=$?"' 'rc=1' 'rc=0')"
run 2 "$TMP/b7.jsonl" "$FIXCLAIM" "pair rc=1 / rc=0 of \`[ -f tests/a/test_x.sh ]\`: $FIXCLAIM"
transcript "$TMP/b8.jsonl" "$(pair 'bash -n tests/a/test_x.sh; echo "rc=$?"' $'tests/a/test_x.sh: line 3: syntax error\nrc=2' 'rc=0')"
run 2 "$TMP/b8.jsonl" "$FIXCLAIM" "pair rc=2 / rc=0 of \`bash -n tests/a/test_x.sh\`: $FIXCLAIM"
echo "-- B. a direct kit run with its echoed exit still is the evidence (green after an edit, and both halves of check 7's pair)"
transcript "$TMP/b9.jsonl" "$(steps_after_edit 'bash tests/a/test_x.sh > /tmp/l 2>&1; echo "rc=$?"' 'rc=0')"
run 0 "$TMP/b9.jsonl" "$PASSCLAIM" "rc=0 after \`bash tests/a/test_x.sh > /tmp/l 2>&1; echo \"rc=\$?\"\`: $PASSCLAIM"
transcript "$TMP/b10.jsonl" "$(pair 'bash tests/a/test_x.sh > /tmp/l 2>&1; echo "rc=$?"' 'rc=1' 'rc=0')"
run 0 "$TMP/b10.jsonl" "$FIXCLAIM" "pair rc=1 / rc=0 of \`bash tests/a/test_x.sh > /tmp/l 2>&1\`: $FIXCLAIM"

echo "-- C. a refused call is not the RED half of check 7"
transcript "$TMP/c1.jsonl" "[[\"bash\",\"bash tests/a/test_x.sh\",\"PreToolUse:Bash hook error: [bash \\\"x/.claude/hooks/session_lock.sh\\\"]: ⛔ blocked\",true],[\"edit\",\"$P/src/a.py\"],[\"bash\",\"bash tests/a/test_x.sh\",\"✔ case 1\nall passed\",false]]"
run 2 "$TMP/c1.jsonl" 'Đã fix bug X trong src/a.py.'
transcript "$TMP/c2.jsonl" "[[\"bash\",\"bash tests/a/test_x.sh\",\"This session is isolated in the worktree /w, but this command is too complex to verify. Refusing to run it — a worktree-isolated session.\",true],[\"edit\",\"$P/src/a.py\"],[\"bash\",\"bash tests/a/test_x.sh\",\"✔ case 1\nall passed\",false]]"
run 2 "$TMP/c2.jsonl" 'Đã fix bug X trong src/a.py.'
transcript "$TMP/c3.jsonl" "[[\"bash\",\"bash tests/a/test_x.sh\",\"This agent is isolated in the worktree /w, but this command runs bash inside a construct too complex to verify; Refusing to run it — a worktree-isolated agent.\",true],[\"edit\",\"$P/src/a.py\"],[\"bash\",\"bash tests/a/test_x.sh\",\"✔ case 1\nall passed\",false]]"
run 2 "$TMP/c3.jsonl" 'Đã fix bug X trong src/a.py.'
echo "-- C. a real red run still is the RED half"
transcript "$TMP/c4.jsonl" "[[\"bash\",\"bash tests/a/test_x.sh\",\"Exit code 1\n✖ case 1\n1 failed\",true],[\"edit\",\"$P/src/a.py\"],[\"bash\",\"bash tests/a/test_x.sh\",\"✔ case 1\nall passed\",false]]"
run 0 "$TMP/c4.jsonl" 'Đã fix bug X trong src/a.py.'

echo "-- E. a negated assertion verb before the outcome / result is no claim (real check-7 / check-2 blocks, 10/2026)"
run 0 "$EMPTY" 'Tôi không gọi chúng là đã fix.'
run 0 "$EMPTY" 'Tôi chưa chốt đã fix cho toàn card.'
run 0 "$EMPTY" 'Chưa xong và chưa có bằng chứng đủ để nói đã fix.'
run 0 "$EMPTY" 'Tôi không sửa code và không tuyên bố đã fix cái gì trong phiên này.'
run 0 "$EMPTY" 'Chưa có kết luận xong hay đã fix.'
run 0 "$EMPTY" "I'm not claiming a test pass this turn."
echo "-- E. must still block: a claim in its own clause after the negation"
run 2 "$EMPTY" 'Đã fix bug X.'
run 2 "$EMPTY" 'Không còn lỗi, đã fix bug X.'
run 2 "$EMPTY" 'Tôi không nói dối: đã fix bug X.'
run 2 "$EMPTY" 'Chưa push nhưng đã fix bug X.'
run 2 "$EMPTY" 'Not claiming anything else, but the crash is fixed.'
run 2 "$EMPTY" 'Tôi không nói nhiều; 12/12 test pass.'
echo "-- E. must still block: the verb does not govern the result, or a reason clause carries the claim"
run 2 "$EMPTY" 'Không ai gọi API này nữa vì đã fix bug X.'
run 2 "$EMPTY" "We don't call the old API since the crash is fixed."
run 2 "$EMPTY" "I'm not claiming victory yet since 12/12 tests pass."
run 2 "$EMPTY" 'Không cần nói nhiều đã fix bug X.'
run 2 "$EMPTY" 'I did not run the old suite because 12/12 tests pass in the new one.'
echo "-- E. must still block: an emphatic or double-negative assertion (\"no need to say\", \"not an overstatement\"; 2026-10-25 review, P2)"
run 2 "$EMPTY" 'Không cần phải nói là đã fix bug X.'
run 2 "$EMPTY" 'Không ngoa khi nói rằng đã fix bug X.'
run 2 "$EMPTY" 'Không sai khi nói là đã fix bug X.'
run 2 "$EMPTY" 'Tôi không ngần ngại khẳng định đã fix bug X.'
run 2 "$EMPTY" "It's not an overstatement to say 12/12 tests pass."
run 2 "$EMPTY" "I'm not exaggerating when I say that tests pass on every platform."
run 2 "$EMPTY" "We don't hesitate to call it fixed."
run 2 "$EMPTY" "Never have I been more confident to say that 12/12 tests pass."

echo "-- P. a long blank run in a tool result is read in linear time (2026-10-25 review, P3: 30k blank lines took 4.5 s; Stop hook cap 30 s)"
# blank_run <cmd> <last line>: one Bash call whose output is 30 000 blank lines, then the line.
blank_run() { python3 -c 'import json,sys; print(json.dumps([["bash",sys.argv[1],"\n" * 30000 + sys.argv[2],False]]))' "$1" "$2"; }
now() { python3 -c 'import time; print(time.time())'; }
for c in 'bash tests/a/test_x.sh > /tmp/l 2>&1; echo "rc=$?"|rc=0' 'bash tests/a/test_x.sh|ok: done' 'python3 -m pytest tests|1 passed in 0.10s'; do
  transcript "$TMP/p1.jsonl" "$(blank_run "${c%%|*}" "${c#*|}")"
  t0="$(now)"
  run 0 "$TMP/p1.jsonl" 'Đã chạy lại: 12/12 test pass.' "30k blank lines + ${c#*|} from \`${c%%|*}\`"
  t1="$(now)"
  if python3 -c 'import sys; sys.exit(0 if float(sys.argv[2]) - float(sys.argv[1]) <= 2.0 else 1)' "$t0" "$t1"; then
    ok "≤ 2 s: \`${c%%|*}\`"
  else
    fail "> 2 s ($(python3 -c 'import sys; print(round(float(sys.argv[2]) - float(sys.argv[1]), 1))' "$t0" "$t1") s): \`${c%%|*}\`"
  fi
done

[ "$FAILS" -eq 0 ] && { echo "all passed ($N)"; exit 0; }
echo "$FAILS failed of $N"; exit 1
