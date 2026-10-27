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
# Two older fail-opens closed next (2026-10-25): F. a non-suite runner whose output went to a log (`python3 -m pytest > l 2>&1;
# echo "rc=$?"` printing rc=1) read as green, so it backed a pass claim and was the GREEN half of check 7's pair; G. a loop or other
# compound (`for f in tests/a/test_*.sh; do bash "$f"; done`) read as green whenever its output carried no failure marker. Q: a long
# reply whose one clause holds many exempt phrases took 8-13 s of CPU (each exempt match re-read the whole clause before it).
# Time bounds count the CPU seconds of the hook process tree (getrusage), not wall-clock: run_impacted.sh runs suites in parallel at a
# load near 70, where a wall bound fails a fast hook. A 30 s wall timeout only ends a hang.
# The review of 9c1a3cb3 (2026-10-26) added: H. a kit summary or a kit "N passed" line backing another runner whose result is hidden (P1);
# I. one transcript record the scan cannot read (int() of a 5 000-digit `rc=`, a malformed Edit) ending the whole scan, so an older green
# backed the claim (P3a); M. a reply of 8 570 outcome claims in one clause taking 1.1 GB (P3b, a bound on max RSS); D. honest runs blocked
# by 322b19db: Gradle / node --test / Maven summaries behind `| tail`, `echo "rc=$?"` on the next line, `echo … >> ran.txt` beside the run
# in a loop (P2); N. "not all tests passed" read as a kit pass summary (R2-M1).
# OCR review round 2 (2026-10-26) added R: a run whose exit is not the tool's (`|| true`, `| head -1`, `&`, `!`, `; echo done`, a second
# line, `true || pytest`) read as green with no failure marker (P1-1), and Gradle's BUILD SUCCESSFUL backing a loop / if that also hides a
# pytest run (P1-3, a regression of 8c1c695d); the principal review of the same round added B2: a run whose stdout went to a file, then
# another command's pass summary (`pytest > log; echo "5 passed"`, `pytest a > log; pytest b`, a kit test after it) read as green.
# OCR review round 3 added S: a loop whose run pipes its result away (`pytest $d | head -1`) or swallows its exit (`|| true`) read as green
# (E1), and a run piped away (`| grep -c FAILED`, `| tail -0`) or sent to a file by `>&`, then another command's summary (E2).
# The final OCR review added T: S blocked a run piped through `tail -N` / `tee` followed by any command (`pytest | tail -3 && git status`,
# 12 of 60 real runner commands) and did not read zsh's `${pipestatus[1]}` as the echo of an exit code.
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
# run_cpu <want rc> <transcript> <reply> <label> <cpu cap s> [max RSS cap MB]: run(), plus a bound on the CPU seconds (user + sys) of the
# hook and every process it waited for, and optionally on the largest RSS among them. A hook still running after 30 s of wall time is
# killed with its process group and counts as a fail.
run_cpu() {
  local want="$1" tr="$2" text="$3" label="$4" cap="$5" rss_cap="${6:-}" out rc cpu rss
  N=$((N + 1))
  out="$(CLAUDE_PROJECT_DIR="$P" python3 - "$HOOK" "$tr" "$text" "$N" <<'PY'
import json, os, resource, signal, subprocess, sys
hook, tr, text, n = sys.argv[1:5]
data = json.dumps({"session_id": "te-fb-" + n, "transcript_path": tr, "last_assistant_message": text})
r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
p = subprocess.Popen(["bash", hook], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                     text=True, start_new_session=True)
try:
    _, err = p.communicate(data, timeout=30)
    rc = 99 if "Traceback" in err else p.returncode
except subprocess.TimeoutExpired:
    os.killpg(p.pid, signal.SIGKILL)
    p.communicate()
    rc = "timeout"
r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
rss_mb = r1.ru_maxrss / (1048576 if sys.platform == "darwin" else 1024)   # ru_maxrss: bytes on macOS, KiB on Linux
print(rc, f"{r1.ru_utime - r0.ru_utime + r1.ru_stime - r0.ru_stime:.2f}", f"{rss_mb:.0f}")
PY
)"
  rc="${out%% *}"; rss="${out##* }"; cpu="${out% *}"; cpu="${cpu##* }"
  [ "$rc" = timeout ] && cpu=999   # killed: its CPU was never reaped
  if [ "$rc" = "$want" ]; then ok "rc $rc: $label"; else fail "rc $rc (want $want): $label"; fi
  if python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= float(sys.argv[2]) else 1)' "$cpu" "$cap" 2>/dev/null; then
    ok "CPU ${cpu} s ≤ ${cap} s: $label"
  else
    fail "CPU ${cpu} s > ${cap} s: $label"
  fi
  [ -n "$rss_cap" ] || return 0
  if [ "$rc" != timeout ] && [ "$rss" -le "$rss_cap" ] 2>/dev/null; then
    ok "max RSS ${rss} MB ≤ ${rss_cap} MB: $label"
  else
    fail "max RSS ${rss} MB > ${rss_cap} MB: $label"
  fi
}
EMPTY="$TMP/empty.jsonl"; : > "$EMPTY"
# transcript <file> <json list of steps>: step = ["bash", cmd, output, is_error] | ["edit", path] | ["raw", transcript record]
transcript() {
  python3 - "$1" "$2" <<'PY'
import json, sys
out, steps = sys.argv[1], json.loads(sys.argv[2])
with open(out, "w") as fh:
    for i, st in enumerate(steps):
        if st[0] == "bash":
            fh.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": f"t{i}", "name": "Bash", "input": {"command": st[1]}}]}}) + "\n")
            fh.write(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": st[2], "is_error": st[3]}]}}) + "\n")
        elif st[0] == "raw":
            fh.write(json.dumps(st[1]) + "\n")
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

# pair2 <red cmd> <red output> <green cmd> <green output>: a FAILING run (is_error), an edit of src/a.py, then the second command.
pair2() { python3 -c 'import json,sys; a=sys.argv; print(json.dumps([["bash",a[2],a[3],True],["edit",a[1]],["bash",a[4],a[5],False]]))' "$P/src/a.py" "$1" "$2" "$3" "$4"; }
PYRED=$'FAILED tests/test_a.py::test_x - assert 1 == 2\n1 failed in 0.12s'
KITRED=$'✖ case 1\n1 failed of 3'
echo "-- F. a non-suite runner whose output went to a log: its echoed exit code decides (fail-open: rc=1 read as green)"
for c in 'python3 -m pytest > /tmp/l 2>&1; echo "rc=$?"' 'npm test > /tmp/l 2>&1; echo "rc=$?"'; do
  transcript "$TMP/f1.jsonl" "$(steps_after_edit "$c" 'rc=1')"
  run 2 "$TMP/f1.jsonl" "$PASSCLAIM" "rc=1 after \`$c\`: $PASSCLAIM"
done
transcript "$TMP/f2.jsonl" "$(pair2 'python3 -m pytest' "$PYRED" 'python3 -m pytest > /tmp/l 2>&1; echo "rc=$?"' 'rc=1')"
run 2 "$TMP/f2.jsonl" "$FIXCLAIM" "real red, edit, then rc=1 of \`python3 -m pytest > /tmp/l 2>&1\` (no GREEN half): $FIXCLAIM"
echo "-- F. must block: an echoed \$? that cannot be bound to the runner gives no green (the P1 list of section B, for pytest)"
for c in 'python3 -m pytest 2>&1 | tail -3; echo "rc=$?"@@rc=0' \
         'python3 -m pytest > /tmp/l 2>&1; true; echo "rc=$?"@@rc=0' \
         'python3 -m pytest > /tmp/l 2>&1; echo $?@@0' \
         'python3 -m pytest > /tmp/l 2>&1; echo "exit: $?"@@exit: 0' \
         'python3 -m pytest > /tmp/l 2>&1; printf "%s\n" $?@@0' \
         'python3 -m pytest > /tmp/l 2>&1 || echo "rc=$?"@@' \
         '! python3 -m pytest > /tmp/l 2>&1; echo "rc=$?"@@rc=0' \
         'bash -c "python3 -m pytest || true" > /tmp/l 2>&1; echo "rc=$?"@@rc=0' \
         'eval "python3 -m pytest; true" > /tmp/l 2>&1; echo "rc=$?"@@rc=0' \
         'pip install pytest > /tmp/l 2>&1; echo "rc=$?"@@rc=0' \
         'go test ./... > /tmp/l 2>&1; echo "rc=${PIPESTATUS[0]}"@@rc=1' \
         'python3 -m pytest a > /tmp/l 2>&1; python3 -m pytest b > /tmp/m 2>&1; echo "rc=$?"@@rc=0'; do
  transcript "$TMP/f3.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 2 "$TMP/f3.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
transcript "$TMP/f4.jsonl" "$(pair '! python3 -m pytest > /tmp/l 2>&1; echo "rc=$?"' 'rc=1' 'rc=0')"
run 2 "$TMP/f4.jsonl" "$FIXCLAIM" "pair rc=1 / rc=0 of \`! python3 -m pytest\`: $FIXCLAIM"
echo "-- F. a runner bound to its echoed 0, or a visible pass summary, still is the evidence"
for c in 'python3 -m pytest > /tmp/l 2>&1; echo "rc=$?"@@rc=0' \
         'npm test > /tmp/l 2>&1; echo "rc=$?"@@rc=0' \
         'PYTHONPATH=src timeout 600 python3 -m pytest -q > /tmp/l 2>&1; echo "rc=$?"@@rc=0' \
         'python3 -m pytest -q 2>&1 | tail -3; echo "rc=$?"@@5 passed in 0.10s
rc=0' \
         'go test ./... 2>&1 | tail -3; echo "rc=${PIPESTATUS[0]}"@@ok  	example.com/pkg	0.12s
rc=0' \
         'python3 -m pytest -q@@5 passed in 0.10s'; do
  transcript "$TMP/f5.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 0 "$TMP/f5.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
transcript "$TMP/f6.jsonl" "$(pair 'python3 -m pytest > /tmp/l 2>&1; echo "rc=$?"' 'rc=1' 'rc=0')"
run 0 "$TMP/f6.jsonl" "$FIXCLAIM" "pair rc=1 / rc=0 of \`python3 -m pytest > /tmp/l 2>&1; echo \"rc=\$?\"\`: $FIXCLAIM"
echo "-- F. the same next to a kit suite in one command: the kit's summary says nothing of the other runner"
for c in 'bash tests/a/test_x.sh; python3 -m pytest > /tmp/l 2>&1; echo "rc=$?"@@all passed (3)
rc=1' \
         'bash tests/a/test_x.sh; python3 -m pytest > /tmp/l 2>&1; echo $?@@all passed (3)
1' \
         'bash tests/a/test_x.sh; for d in a b; do python3 -m pytest -q $d > /dev/null 2>&1; done@@all passed (3)'; do
  transcript "$TMP/f7.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 2 "$TMP/f7.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
transcript "$TMP/f8.jsonl" "$(steps_after_edit 'bash tests/a/test_x.sh; python3 -m pytest > /tmp/l 2>&1; echo "rc=$?"' $'all passed (3)\nrc=0')"
run 0 "$TMP/f8.jsonl" "$PASSCLAIM" "'all passed (3) / rc=0' after \`bash tests/a/test_x.sh; python3 -m pytest > /tmp/l 2>&1; echo \"rc=\$?\"\`: $PASSCLAIM"

echo "-- G. a loop / compound runner gives no green from the absence of a failure marker (fail-open: glob loop always green)"
for c in 'for f in tests/a/test_*.sh; do bash "$f"; done@@' \
         'for f in tests/a/test_*.sh; do bash "$f" > /dev/null 2>&1; done@@' \
         'for f in tests/a/test_*.sh; do bash "$f"; done@@✔ case 1
✖ case 2' \
         'for f in $KIT/tests/gates/test_*.sh; do bash "$f" > /dev/null 2>&1; done@@' \
         'for t in $(ls tests/a/test_*.sh); do bash $t > /dev/null; done@@' \
         'for d in a b; do (cd $d && python3 -m pytest -q > /dev/null 2>&1); done@@' \
         'if [ -d tests ]; then python3 -m pytest -q > /dev/null 2>&1; fi@@'; do
  transcript "$TMP/g1.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 2 "$TMP/g1.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
transcript "$TMP/g2.jsonl" "$(pair2 'bash tests/a/test_x.sh' "$KITRED" 'for f in tests/a/test_*.sh; do bash "$f" > /dev/null 2>&1; done' '')"
run 2 "$TMP/g2.jsonl" "$FIXCLAIM" "real red, edit, then a silent glob loop (no GREEN half): $FIXCLAIM"
echo "-- G. a loop that prints a recognised summary still counts by it"
for c in 'for f in tests/a/test_*.sh; do bash "$f" | tail -1; done@@all passed (5)
all passed (7)' \
         'for d in a b; do python3 -m pytest -q $d; done@@3 passed in 0.10s
2 passed in 0.09s'; do
  transcript "$TMP/g3.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 0 "$TMP/g3.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
transcript "$TMP/g4.jsonl" "$(pair2 'bash tests/a/test_x.sh' "$KITRED" 'for f in tests/a/test_*.sh; do bash "$f" | tail -1; done' 'all passed (3)')"
run 0 "$TMP/g4.jsonl" "$FIXCLAIM" "real red, edit, then a glob loop printing 'all passed': $FIXCLAIM"

echo "-- P. a long blank run in a tool result is read in linear time (2026-10-25 review, P3: 30k blank lines took 4.5 s; Stop hook cap 30 s)"
# blank_run <cmd> <last line>: one Bash call whose output is 30 000 blank lines, then the line.
blank_run() { python3 -c 'import json,sys; print(json.dumps([["bash",sys.argv[1],"\n" * 30000 + sys.argv[2],False]]))' "$1" "$2"; }
for c in 'bash tests/a/test_x.sh > /tmp/l 2>&1; echo "rc=$?"|rc=0' 'bash tests/a/test_x.sh|ok: done' 'python3 -m pytest tests|1 passed in 0.10s'; do
  transcript "$TMP/p1.jsonl" "$(blank_run "${c%%|*}" "${c#*|}")"
  run_cpu 0 "$TMP/p1.jsonl" 'Đã chạy lại: 12/12 test pass.' "30k blank lines + ${c#*|} from \`${c%%|*}\`" 2.0
done

echo "-- Q. a long reply whose clause holds many exempt phrases ends well inside the Stop cap and still blocks the claim in it"
# ~40 KB, one sentence: 1 340 negated phrases took 8-13 s of CPU (each re-read the whole clause before it). A reply that is ONLY such
# phrases may block (fail-closed budget); it is no case here on purpose.
long() { python3 -c 'import sys; print(sys.argv[1] + sys.argv[2] * int(sys.argv[3]) + sys.argv[4], end="")' "$1" "$2" "$3" "$4"; }
run_cpu 2 "$EMPTY" "$(long '' 'Tôi không gọi chúng là đã fix ' 1340 'Đã fix bug X.')" '1 340 × "Tôi không gọi chúng là đã fix " + "Đã fix bug X."' 2.0
run_cpu 2 "$EMPTY" "$(long 'Đã fix bug X ' 'Tôi không gọi chúng là đã fix ' 1340 '')" '"Đã fix bug X " + 1 340 × "Tôi không gọi chúng là đã fix "' 2.0
run_cpu 2 "$EMPTY" "$(long '' 'Tôi không nói 12/12 test pass ' 1340 ', 12/12 test pass.')" '1 340 × "Tôi không nói 12/12 test pass " + ", 12/12 test pass."' 2.0
run_cpu 2 "$EMPTY" "$(long '' 'Kế hoạch: viết test ĐỎ→XANH ' 1340 '. Đã chạy test ĐỎ→XANH.')" '1 340 × "Kế hoạch: viết test ĐỎ→XANH ", then "Đã chạy test ĐỎ→XANH."' 2.0
run_cpu 2 "$EMPTY" "$(long "$(python3 -c 'print("lorem ipsum dolor " * 2400, end="")')" 'Tôi không gọi chúng là đã fix ' 300 'Đã fix bug X.')" '40 KB of plain words, 300 exempt phrases, then "Đã fix bug X."' 2.0

echo "-- H. a kit summary says nothing of another runner whose result is hidden (2026-10-26 review of 9c1a3cb3, P1: any \"N passed\" counted)"
# B1 B3 B6 B8 of the review, then two the review's own fix (kit summary AND any \"N passed\") still let through: a kit check line that
# quotes a runner summary (this very suite prints them) and a second kit's \"name: N passed, 0 failed\" summary.
for c in 'bash tests/a/test_x.sh > /dev/null 2>&1; python3 -m pytest -q; echo $?@@5 passed in 0.10s
0' \
         '[ -f tests/a/test_x.sh ]; python3 -m pytest > /tmp/l 2>&1; echo $?; echo "5 passed"@@1
5 passed' \
         'bash tests/installer/test_uninstall.sh; python3 -m pytest > /tmp/l 2>&1; echo $?@@uninstall: 9 passed, 0 failed
1' \
         'bash tests/installer/test_uninstall.sh; for d in a b; do python3 -m pytest -q $d > /dev/null 2>&1; done@@uninstall: 9 passed, 0 failed' \
         'bash tests/gates/test_evidence_false_blocks.sh; python3 -m pytest > /tmp/l 2>&1; echo $?@@✔ rc 0: '"'"'5 passed in 0.10s'"'"' after `python3 -m pytest -q`
all passed (120)
1' \
         'bash tests/a/test_x.sh; bash tests/installer/test_uninstall.sh; python3 -m pytest > /tmp/l 2>&1; echo $?@@all passed (3)
uninstall: 9 passed, 0 failed
1'; do
  transcript "$TMP/h1.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 2 "$TMP/h1.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
echo "-- H. the kit's summary and the other runner's own summary, both in the result, still are the evidence"
transcript "$TMP/h2.jsonl" "$(steps_after_edit 'bash tests/a/test_x.sh; python3 -m pytest -q 2>&1 | tail -3; echo "rc=${PIPESTATUS[0]}"' $'all passed (3)\n5 passed in 0.10s\nrc=0')"
run 0 "$TMP/h2.jsonl" "$PASSCLAIM" "'all passed (3) / 5 passed / rc=0' after \`bash tests/a/test_x.sh; python3 -m pytest -q 2>&1 | tail -3; echo \"rc=\${PIPESTATUS[0]}\"\`: $PASSCLAIM"

echo "-- I. one transcript record the scan cannot read is skipped, not the rest of the transcript (2026-10-26 review, P3a)"
# int() of the 5 000-digit `rc=111…` raised (Python's 4 300-digit limit) inside the scan's single try: the scan ended, the edit after it was
# never seen, and the green run before it backed the claim.
i_steps() { python3 -c 'import json,sys; print(json.dumps([["bash","python3 -m pytest -q","5 passed in 0.10s",False],["bash",sys.argv[2],"xrc=1\nrc="+"1"*5000,False],["edit",sys.argv[1]]]))' "$P/src/a.py" "$1"; }
transcript "$TMP/i1.jsonl" "$(i_steps 'printf x; python3 -m pytest > /tmp/l 2>&1; echo "rc=$?"; python3 -c '"'"'print("rc="+"1"*5000)'"'"'')"
run 2 "$TMP/i1.jsonl" "$PASSCLAIM" "green, then rc=<5 000 digits> of \`python3 -m pytest > /tmp/l\`, then an edit: $PASSCLAIM"
BADEDIT='["raw",{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tbad","name":"Edit","input":["not a dict"]}]}}]'
GREEN1='["bash","python3 -m pytest -q","5 passed in 0.10s",false]'
transcript "$TMP/i2.jsonl" "[$GREEN1,$BADEDIT,[\"edit\",\"$P/src/a.py\"]]"
run 2 "$TMP/i2.jsonl" "$PASSCLAIM" "green, an Edit record the scan cannot read, then an edit: $PASSCLAIM"
if grep -q "transcript line [0-9]* block [0-9]* skipped (tool_use Edit)" "$P/.claude/audit-gate/test_evidence_gate.log" 2>/dev/null; then
  ok "the skipped record is logged with its line, block and tool"
else
  fail "the skipped record is not in $P/.claude/audit-gate/test_evidence_gate.log"
fi
transcript "$TMP/i3.jsonl" "[$GREEN1,$BADEDIT]"
run 2 "$TMP/i3.jsonl" "$PASSCLAIM" "green, then an Edit record the scan cannot read (still a source edit: fail-closed): $PASSCLAIM"

echo "-- M. one clause of many outcome claims keeps memory flat (2026-10-26 review, P3b: 8 570 × \" đã fix\" took 1.1 GB of RSS)"
run_cpu 2 "$EMPTY" "$(long '' ' đã fix' 8570 '')" '8 570 × " đã fix" (60 KB, one clause)' 2.0 300

echo "-- D. honest runs whose code is read through PIPESTATUS or on the next line still are the evidence (2026-10-26 review, P2 of 322b19db)"
transcript "$TMP/d1.jsonl" "$(pair2 './gradlew test' $'FAILED\nBUILD FAILED in 2s' './gradlew test 2>&1 | tail -5; echo "exit=${PIPESTATUS[0]}"' $'BUILD SUCCESSFUL in 3s\nexit=0')"
run 0 "$TMP/d1.jsonl" "$FIXCLAIM" "Gradle red, edit, then BUILD SUCCESSFUL of \`./gradlew test 2>&1 | tail -5; echo \"exit=\${PIPESTATUS[0]}\"\`: $FIXCLAIM"
for c in 'node --test 2>&1 | tail -8; echo "rc=${PIPESTATUS[0]}"@@ℹ tests 5
ℹ pass 5
ℹ fail 0
rc=0' \
         'mvn test | tail -5; echo "rc=${PIPESTATUS[0]}"@@Tests run: 5, Failures: 0, Errors: 0, Skipped: 0
BUILD SUCCESS
rc=0' \
         'python3 -m pytest -q > /tmp/l 2>&1
echo "rc=$?"@@rc=0' \
         'cat > /tmp/x.py <<'"'"'EOF'"'"'
# don'"'"'t
EOF
python3 -m pytest -q > /tmp/l 2>&1; echo "rc=$?"@@rc=0' \
         'for f in tests/a/test_*.sh; do echo "== $f" >> /tmp/ran.txt; bash "$f"; done@@✔ case 1
ok: done
✔ case 2
all passed (2)'; do
  transcript "$TMP/d2.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 0 "$TMP/d2.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
echo "-- D. must still block: those summaries for another runner or a red run, a next line that is not the run's echo, a heredoc body,"
echo "   a loop whose run (or the whole loop) writes stdout to a file, a glob loop over kit suites with no summary line (#427 round 3)"
for c in './gradlew test 2>&1 | tail -3; echo "g=${PIPESTATUS[0]}"; python3 -m pytest > /tmp/l 2>&1; echo $?@@BUILD SUCCESSFUL in 3s
g=0
1' \
         'python3 -m pytest 2>&1 | tail -1; echo "rc=${PIPESTATUS[0]}"@@BUILD SUCCESSFUL in 3s
rc=0' \
         'mvn test | tail -5; echo "rc=${PIPESTATUS[0]}"@@Tests run: 3, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.1 s - in a.ATest
Tests run: 5, Failures: 1, Errors: 0, Skipped: 0
BUILD FAILURE
rc=1' \
         'mvn test | tail -3; echo "rc=${PIPESTATUS[0]}"@@Tests run: 3, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.1 s - in a.ATest
Tests run: 5, Failures: 0, Errors: 2, Skipped: 0
rc=1' \
         'node --test 2>&1 | tail -1; echo "rc=${PIPESTATUS[0]}"@@ℹ pass 5
rc=1' \
         'python3 -m pytest > /tmp/l 2>&1
cd /tmp
echo "rc=$?"@@rc=0' \
         'python3 -m pytest > /tmp/l 2>&1 || true
echo "rc=$?"@@rc=0' \
         'cat > /tmp/t.sh <<'"'"'EOF'"'"'
python3 -m pytest > /tmp/l 2>&1
echo "rc=$?"
EOF
echo "rc=0"@@rc=0' \
         'for f in tests/a/test_*.sh; do echo "== $f" >> /tmp/ran.txt; bash "$f"; done@@✔ case 1
ok: done
✔ case 2' \
         'for f in tests/a/test_*.sh; do bash "$f" > /dev/null; done@@warning: x' \
         'for f in tests/a/test_*.sh; do echo "== $f"; bash "$f" > /dev/null; done@@== tests/a/test_x.sh' \
         'for f in tests/a/test_*.sh; do bash "$f"; done > /tmp/all.log@@warning: x' \
         'for d in a b; do if [ -d $d ]; then python3 -m pytest -q $d > /tmp/$d.log; fi; done@@warning: x'; do
  transcript "$TMP/d3.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 2 "$TMP/d3.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done

echo "-- N. \"not all tests passed\" is no pass summary (2026-10-26 review, R2-M1)"
transcript "$TMP/n1.jsonl" "$(steps_after_edit 'for d in a b; do python3 -m pytest -q $d > /dev/null 2>&1 || echo "not all tests passed in $d"; done' 'not all tests passed in a')"
run 2 "$TMP/n1.jsonl" "$PASSCLAIM" "'not all tests passed in a' after a loop of \`python3 -m pytest -q \$d > /dev/null 2>&1 || echo …\`: $PASSCLAIM"

echo "-- R. OCR review round 2 (2026-10-26): a run whose exit is not the tool's (P1-1), Gradle's summary for a loop that also hides pytest (P1-3)"
for c in 'for m in a b; do python3 -m pytest -q $m > /dev/null 2>&1; ./gradlew :$m:test; done@@BUILD SUCCESSFUL in 3s
BUILD SUCCESSFUL in 2s' \
         'if ./gradlew test; then python3 -m pytest -q > /dev/null 2>&1; fi@@BUILD SUCCESSFUL in 3s' \
         '(python3 -m pytest -q > /dev/null 2>&1; ./gradlew test)@@BUILD SUCCESSFUL in 3s' \
         'python3 -m pytest -q > /tmp/l 2>&1 || true@@' \
         'python3 -m pytest -q 2>&1 | head -1@@..F.........  [100%]' \
         'python3 -m pytest -q > /dev/null 2>&1 &@@' \
         '! python3 -m pytest -q > /tmp/l 2>&1@@' \
         'python3 -m pytest -q > /tmp/l 2>&1; echo done@@done' \
         'python3 -m pytest -q > /tmp/l 2>&1 | true@@' \
         'python3 -m pytest -q > /tmp/l 2>&1
echo ok@@ok' \
         'true || python3 -m pytest -q > /tmp/l 2>&1 && echo ok@@ok' \
         'for m in a b; do python3 -m pytest -q $m | grep -c FAILED; ./gradlew :$m:test 2>&1 | tail -1; done; echo "rc=$?"@@2
BUILD SUCCESSFUL in 3s
0
BUILD SUCCESSFUL in 2s
rc=0' \
         '(python3 -m pytest -q | grep -c FAILED; ./gradlew test 2>&1 | tail -1); echo "rc=$?"@@2
BUILD SUCCESSFUL in 3s
rc=0'; do
  transcript "$TMP/r1.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 2 "$TMP/r1.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
transcript "$TMP/r2.jsonl" "$(pair2 'python3 -m pytest -q' '1 failed in 0.1s' 'python3 -m pytest -q > /tmp/l 2>&1 || true' '')"
run 2 "$TMP/r2.jsonl" "$FIXCLAIM" "real red, edit, then a silent \`python3 -m pytest -q > /tmp/l 2>&1 || true\` (no GREEN half): $FIXCLAIM"
transcript "$TMP/r3.jsonl" "$(pair2 'python3 -m pytest -q' '1 failed in 0.1s' 'for m in a b; do python3 -m pytest -q $m > /dev/null 2>&1; ./gradlew :$m:test; done' $'BUILD SUCCESSFUL in 3s\nBUILD SUCCESSFUL in 2s')"
run 2 "$TMP/r3.jsonl" "$FIXCLAIM" "real red, edit, then BUILD SUCCESSFUL of a loop that hides pytest (no GREEN half): $FIXCLAIM"
echo "-- R. a run whose output went to a file, then another command's pass summary (principal review round 2, B2)"
# The last case was an OCR round-2 control ("Gradle-only loop to logs"): module a's log is never shown and the loop's exit is the last
# iteration's, so BUILD SUCCESSFUL of g.b says nothing of a.
for c in 'python3 -m pytest > /tmp/l 2>&1; echo "5 passed"@@5 passed' \
         'python3 -m pytest tests/a > /tmp/l 2>&1; python3 -m pytest tests/b@@== 3 passed in 0.10s ==' \
         'python3 -m pytest > /tmp/l 2>&1; bash tests/a/test_x.sh@@✔ x1
all passed (1)' \
         'bash tests/a/test_y.sh > /tmp/y.log 2>&1; bash tests/a/test_x.sh@@✔ x1
all passed (1)' \
         'for f in tests/a/test_*.sh; do bash "$f" > /dev/null; done; bash tests/a/test_x.sh@@✔ x1
all passed (1)' \
         'for m in a b; do ./gradlew :$m:test > /tmp/g.$m 2>&1; done; tail -1 /tmp/g.b@@BUILD SUCCESSFUL in 2s' \
         'bash tests/a/test_x.sh > /tmp/l 2>&1; tail -3 /tmp/l@@✔ x1
all passed (3)' \
         'for d in a b; do python3 -m pytest -q $d; done; python3 -m pytest -q c > /tmp/l 2>&1 || true@@3 passed in 0.10s
2 passed in 0.10s'; do
  transcript "$TMP/r5.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 2 "$TMP/r5.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
echo "-- R. still the evidence: a pass summary behind a pipe, \`&&\` after the run (also \`&& tail\` of its log), a run after \`cd … &&\`, two runs"
echo "   joined by \`&&\`, a Gradle loop that shows each module's summary"
for c in 'python3 -m pytest -q 2>&1 | tail -5@@........ [100%]
5 passed in 0.10s' \
         'python3 -m pytest -q > /tmp/l 2>&1 && echo ok@@ok' \
         'python3 -m pytest -q > /tmp/l 2>&1 && tail -3 /tmp/l@@5 passed in 0.10s' \
         'bash tests/a/test_x.sh > /tmp/l 2>&1 && tail -3 /tmp/l@@✔ x1
all passed (3)' \
         'cd /tmp && python3 -m pytest -q > /tmp/l 2>&1@@' \
         'python3 -m pytest -q a && python3 -m pytest -q b > /tmp/l 2>&1@@3 passed in 0.10s' \
         'for m in a b; do ./gradlew :$m:test 2>&1 | tail -1; done@@BUILD SUCCESSFUL in 3s
BUILD SUCCESSFUL in 2s'; do
  transcript "$TMP/r4.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 0 "$TMP/r4.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done

echo "-- S. OCR review round 3 (2026-10-26): a loop's run that pipes its result away or swallows its exit (E1), a run piped away or sent"
echo "   to a file by \`>&\`, then another command's summary (E2)"
for c in 'for d in a b; do python3 -m pytest -q $d | head -1; done@@..F......  [100%]
.........  [100%]' \
         'for d in a b; do python3 -m pytest -q $d 2>&1 | grep -c passed; done@@1
1' \
         'for d in a; do python3 -m pytest -q $d || true; done@@..F..' \
         'while true; do python3 -m pytest -q | tail -0; break; done; echo checked@@checked' \
         'python3 -m pytest -q tests/a 2>&1 | grep -c FAILED; python3 -m pytest -q tests/b@@3
10 passed in 0.50s' \
         'python3 -m pytest -q tests/a 2>&1 | tail -0; echo "5 passed"@@5 passed' \
         'python3 -m pytest -q >& /tmp/l; echo "5 passed"@@5 passed' \
         'python3 -m pytest -q tests/a >& /tmp/l; python3 -m pytest -q tests/b@@3 passed in 0.10s' \
         'bash tests/a/test_y.sh 2>&1 | tail -0; bash tests/a/test_x.sh@@✔ x1
all passed (1)'; do
  transcript "$TMP/s1.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 2 "$TMP/s1.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
echo "-- T. final OCR review (2026-10-26): a run piped only through tail -N / tee keeps its summary in the result, then any command"
echo "   (12 of 60 real runner commands were blocked by S), zsh's \${pipestatus[1]} is the echo of an exit code"
for c in 'python3 -m pytest -q 2>&1 | tail -3 && git status --short@@12 passed in 0.50s' \
         'pytest -q 2>&1 | tail -3; git status --short@@12 passed in 0.50s
 M src/a.py' \
         'npm test 2>&1 | tail -20 && npm run lint@@Tests:       12 passed, 12 total
> lint
> eslint .' \
         'cargo test 2>&1 | tail -3; cargo clippy@@test result: ok. 12 passed; 0 failed; 0 ignored
    Checking a v0.1.0
    Finished dev' \
         'pytest | tee /tmp/log; echo ok@@12 passed in 0.50s
ok' \
         'bash tests/a/test_x.sh 2>&1 | tail -3; git status --short@@✔ x3
all passed (3)
 M src/a.py' \
         'bash tests/super-board/test_github_read.sh 2>&1 | tail -6; echo "rc=${pipestatus[1]}"@@✔ read 1
all passed (6)
rc=0' \
         'python3 -m pytest -q 2>&1 | grep -E "passed|failed"; echo "rc=${pipestatus[1]}"@@12 passed in 0.50s
rc=0' \
         'python3 -m pytest -q 2>&1 | tail -3 && python3 -m pytest -q tests/b 2>&1 | tail -3@@12 passed in 0.50s
4 passed in 0.10s' \
         'bash tests/a/test_x.sh 2>&1 | tail -3; echo "exit=${pipestatus[1]}"; bash tests/a/test_y.sh 2>&1 | tail -3; echo "exit=${pipestatus[1]}"@@✔ x3
all passed (3)
exit=0
✔ y1
all passed (1)
exit=0' \
         'python3 -m pytest -q 2>&1 | tail -3 && git commit -qam "fix parser: 12 tests passed"@@12 passed in 0.50s
[main abc1234] fix parser: 12 tests passed'; do
  transcript "$TMP/t1.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 0 "$TMP/t1.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
echo "-- T. must still block: a stage that cuts the summary (\`| head -1\`, \`| grep -c\`, \`| tail -0\`), then a command that prints a pass"
for c in 'python3 -m pytest -q 2>&1 | head -1; echo "12 passed"@@..F.........  [100%]
12 passed' \
         'python3 -m pytest -q 2>&1 | grep -c passed; echo "12 passed"@@0
12 passed' \
         'python3 -m pytest -q 2>&1 | tail -n 0; echo "12 passed"@@12 passed'; do
  transcript "$TMP/t2.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 2 "$TMP/t2.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
echo "-- U. OCR check of T (2026-10-26): \`tail -N\` keeps no summary of mocha / node --test, so a pass word echoed after it must not"
echo "   stand in for it; a bare word 'pipestatus' is no exit-code echo. (A multi-package go test or mocha run cut by tail -N and"
echo "   followed by another runner is a known hole, the same as go test | tail -2 alone: Backlog #427.)"
for c in 'npx mocha 2>&1 | tail -3; echo "12 passing"@@      at Context.<anonymous> (test/a.js:5:9)
      at process.processImmediate (node:internal/timers:476:21)

12 passing' \
         'python3 -m pytest -q 2>&1 | head -1; echo "12 passed pipestatus"@@..F.........  [100%]
12 passed pipestatus' \
         'npx mocha 2>&1 | tail -3; print "12 passing"@@      at Context.<anonymous> (test/a.js:5:9)
      at process.processImmediate (node:internal/timers:476:21)

12 passing' \
         'npx mocha 2>&1 | tail -3 && git commit -am "fix parser: 12 passing"@@      at Context.<anonymous> (test/a.js:5:9)
      at process.processImmediate (node:internal/timers:476:21)

[main abc1234] fix parser: 12 passing'; do
  transcript "$TMP/u1.jsonl" "$(steps_after_edit "${c%%@@*}" "${c#*@@}")"
  run 2 "$TMP/u1.jsonl" "$PASSCLAIM" "'${c#*@@}' after \`${c%%@@*}\`: $PASSCLAIM"
done
echo "-- S. still the evidence: \`>&2\` keeps the output in the result"
transcript "$TMP/s2.jsonl" "$(steps_after_edit 'python3 -m pytest -q tests/a >&2; python3 -m pytest -q tests/b' $'4 passed in 0.10s\n3 passed in 0.10s')"
run 0 "$TMP/s2.jsonl" "$PASSCLAIM" "'4 passed / 3 passed' after \`python3 -m pytest -q tests/a >&2; python3 -m pytest -q tests/b\`: $PASSCLAIM"

[ "$FAILS" -eq 0 ] && { echo "all passed ($N)"; exit 0; }
echo "$FAILS failed of $N"; exit 1
