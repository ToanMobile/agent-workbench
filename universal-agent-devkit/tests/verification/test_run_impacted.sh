#!/usr/bin/env bash
# Regression test: tests/run_impacted.sh picks the tests that name a changed file — from the
# working tree, new files, AND commits not pushed yet (a commit made inside the turn must not
# leave the gate testing nothing), plus helpers under tests/ through the tests that source them.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TOK="$(basename "$TMP" | tr -cd 'A-Za-z0-9')"   # this run's token: the slow tests below carry it, so test_budgets' pgrep sees only this run's own
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

K="$TMP/kit"; mkdir -p "$K/tests/verification" "$K/scripts"
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$K/tests/"
echo 'echo ok' > "$K/tests/verification/test_repo_consistency.sh"
echo 'x = 1' > "$K/scripts/foo.py"
echo 'y = 1' > "$K/scripts/bar.py"
printf '. tests/lib_helper.sh\npython3 scripts/foo.py\n' > "$K/tests/verification/test_foo.sh"
echo 'python3 scripts/bar.py' > "$K/tests/verification/test_bar.sh"
echo 'helper() { :; }' > "$K/tests/lib_helper.sh"
( cd "$K" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init
  git clone -q --bare . "$TMP/origin.git" && git remote add origin "$TMP/origin.git" && git fetch -q origin && git branch -q -u origin/main 2>/dev/null || git branch -q -u origin/master )
list() { (cd "$K" && bash tests/run_impacted.sh --list); }

[ "$(list)" = "tests/verification/test_repo_consistency.sh" ] && ok "nothing changed: repo consistency only" || fail "clean: $(list | tr '\n' ' ')"

echo 'x = 2' > "$K/scripts/foo.py"
list | grep -qx "tests/verification/test_foo.sh" && ! list | grep -qx "tests/verification/test_bar.sh" && ok "working-tree change selects the test that names it" || fail "worktree: $(list | tr '\n' ' ')"

(cd "$K" && git commit -qam "fix inside the turn")
list | grep -qx "tests/verification/test_foo.sh" && ok "committed but not pushed: still selected" || fail "unpushed commit lost: $(list | tr '\n' ' ')"

(cd "$K" && git push -q origin HEAD 2>/dev/null)
[ "$(list)" = "tests/verification/test_repo_consistency.sh" ] && ok "pushed: no longer selected" || fail "pushed still selected: $(list | tr '\n' ' ')"

mkdir -p "$K/templates"; echo 'block' > "$K/templates/block.md"; echo 'cat templates/block.md' > "$K/tests/verification/test_block.sh"
(cd "$K" && git add -A && git commit -qm tpl && git push -q origin HEAD 2>/dev/null)
echo 'block v2' > "$K/templates/block.md"
list | grep -qx "tests/verification/test_block.sh" && ok "a changed template (not code) selects the test that reads it" || fail "template: $(list | tr '\n' ' ')"
echo 'block' > "$K/templates/block.md"

echo 'helper() { true; }' > "$K/tests/lib_helper.sh"
list | grep -qx "tests/verification/test_foo.sh" && ok "changed helper under tests/ selects the tests that source it" || fail "helper: $(list | tr '\n' ' ')"

# A test that reaches a script through a command names only its stem ("agent-kit githooks
# install" for scripts/githooks.sh): 2026-09-26 test_githooks went red on a githooks.sh change
# and the gate did not run it.
echo 'echo tool' > "$K/scripts/tool.sh"; echo 'bash bin/kit tool install' > "$K/tests/verification/test_tool_cmd.sh"
echo 'echo toolbox' > "$K/tests/verification/test_toolbox.sh"
(cd "$K" && git add -A && git commit -qm "tool" && git push -q origin HEAD 2>/dev/null)
echo 'echo tool v2' > "$K/scripts/tool.sh"
list | grep -qx "tests/verification/test_tool_cmd.sh" && ok "a test naming only the script's stem (kit tool install) is selected" \
  || fail "stem: $(list | tr '\n' ' ')"
! list | grep -qx "tests/verification/test_toolbox.sh" && ok "  … as a whole word only (toolbox is not tool)" || fail "stem matched inside a word"
(cd "$K" && git checkout -q -- scripts/tool.sh)

# The run is parallel (DEVKIT_TEST_JOBS, default min(cores + cores/3, 16) with a floor of 4; this test pins 4): the DevKit suite took 740 s of the 900 s
# gate limit on 2026-09-26. Output stays in list order; one failing test still fails the run;
# test_budgets (timings) runs alone after the others.
# #430: "ran in parallel" is proved by a rendezvous, not by seconds (a wall-clock ceiling failed at machine load 100+): each slow test drops its marker
# and waits until all three exist, so only tests that run at the SAME TIME get through; one after another the first waits out its 60 s ceiling and fails.
barrier_test() { # <marker dir> <name> -> the script body
  printf 'M=%s; mkdir -p "$M"; touch "$M/%s"; w=0\nwhile [ ! -e "$M/a" ] || [ ! -e "$M/b" ] || [ ! -e "$M/c" ]; do sleep 0.2; w=$((w + 1)); [ "$w" -gt 300 ] && { echo never-overlapped; exit 1; }; done\necho %s-done\n' "$1" "$2" "$2"
}
R="$TMP/par"; mkdir -p "$R/tests/verification" "$R/tests/context_memory"; cp "$DEVKIT_DIR/tests/run_impacted.sh" "$R/tests/"
echo 'echo ok' > "$R/tests/verification/test_repo_consistency.sh"
for n in a b c; do barrier_test "$R/mark" "$n" > "$R/tests/verification/test_slow_${TOK}_$n.sh"; done
printf 'echo broken; exit 3\n' > "$R/tests/verification/test_broken.sh"
printf 'for f in tests/verification/test_slow_*.sh; do [ -e "$f" ]; done; [ -z "$(pgrep -f "tests/verification/test_slow_%s_" | head -1)" ] && echo alone || { echo "not alone"; exit 1; }\n' "$TOK" > "$R/tests/context_memory/test_budgets.sh"
( cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init )
( cd "$R" && echo "# x" >> tests/verification/test_slow_${TOK}_a.sh && echo "# x" >> tests/verification/test_slow_${TOK}_b.sh && echo "# x" >> tests/verification/test_slow_${TOK}_c.sh \
  && echo "# x" >> tests/verification/test_broken.sh && echo "# x" >> tests/context_memory/test_budgets.sh )
t0=$(date +%s); out="$(cd "$R" && DEVKIT_TEST_JOBS=4 bash tests/run_impacted.sh 2>&1)"; rc=$?; t1=$(date +%s)
[ "$(printf '%s\n' "$out" | grep -cE "^✔ tests/verification/test_slow_${TOK}_[abc].sh")" = 3 ] && ok "3 tests that wait for each other all got through: they ran in parallel" || fail "not parallel: $out"
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q "✖ tests/verification/test_broken.sh" && ok "a failing test still fails the run, named" || fail "rc=$rc: $out"
printf '%s' "$out" | grep -q "✔ tests/context_memory/test_budgets.sh" && ok "test_budgets runs alone, after the others" || fail "budgets not alone: $out"
# #430: tests that assert an absolute number of seconds fail in the pool under load (25-26/10); each runs alone, like test_budgets
for t in test_run_impacted test_relink test_worktree_merge_gate_owner; do
  grep -E '^ *case "\$t" in .*\*/'"$t"'\.sh' "$DEVKIT_DIR/tests/run_impacted.sh" | grep -q 'alone=' && ok "$t is on the run-alone list" || fail "$t (asserts seconds) is not on the run-alone list"
done
# (✔|✖), not [✔✖]: under a POSIX locale (Linux, LANG unset) grep reads a multibyte bracket class byte by byte and matches nothing
[ "$(printf '%s\n' "$out" | grep -E '^(✔|✖) ' | sed 's/^[^ ]* //' | tr '\n' ' ')" = "$(printf '%s\n' "$out" | grep -E '^(✔|✖) ' | sed 's/^[^ ]* //' | sort | tr '\n' ' ')" ] \
  && ok "results are printed in list order" || fail "order: $out"

# `agent-kit test` runs the WHOLE suite through `run_impacted.sh --all`: one test after another took ~19 min,
# past the 900 s `agent-kit health --run-tests` allows (2026-10-02: score 96/100, "Test suite: timed out").
# --all selects every tests/*/test_*.sh whatever changed, in parallel, and finding none is an error, not a pass.
A="$TMP/all"; mkdir -p "$A/tests/verification" "$A/tests/context_memory"; cp "$DEVKIT_DIR/tests/run_impacted.sh" "$A/tests/"
echo 'echo ok' > "$A/tests/verification/test_repo_consistency.sh"
for n in a b c; do barrier_test "$A/mark" "$n" > "$A/tests/verification/test_slow_$n.sh"; done
printf 'echo broken; exit 3\n' > "$A/tests/verification/test_broken.sh"
echo 'echo budgets' > "$A/tests/context_memory/test_budgets.sh"
( cd "$A" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init
  git clone -q --bare . "$TMP/origin_all.git" && git remote add origin "$TMP/origin_all.git" && git fetch -q origin \
    && { git branch -q -u origin/main 2>/dev/null || git branch -q -u origin/master; } )   # clean and pushed: nothing "changed"
[ "$(cd "$A" && bash tests/run_impacted.sh --list)" = "tests/verification/test_repo_consistency.sh" ] || fail "setup: the --all fixture is not clean"
t0=$(date +%s); out="$(cd "$A" && DEVKIT_TEST_JOBS=4 bash tests/run_impacted.sh --all 2>&1)"; rc=$?; t1=$(date +%s)
n_ran="$(printf '%s\n' "$out" | grep -cE '^(✔|✖) tests/')"
[ "$n_ran" = 6 ] && ok "--all on a clean tree selects every test ($n_ran)" || fail "--all selected $n_ran tests, not 6: $out"
[ "$(printf '%s\n' "$out" | grep -cE '^✔ tests/verification/test_slow_[abc].sh')" = 3 ] && ok "--all: the 3 tests that wait for each other all got through: they ran in parallel" || fail "--all not parallel: $out"
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q "✖ tests/verification/test_broken.sh" && ok "--all: a failing test fails the run, named" || fail "--all rc=$rc: $out"
E="$TMP/none"; mkdir -p "$E/tests"; cp "$DEVKIT_DIR/tests/run_impacted.sh" "$E/tests/"; ( cd "$E" && git init -q . )
out="$(cd "$E" && bash tests/run_impacted.sh --all 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q "no tests found" && ok "--all with no tests is an error (exit 2), never a silent pass" || fail "--all with no tests: rc=$rc out=$out"

# #427 / log trống khi quá 900 s (27/10): ✔/✖ chỉ in ở vòng cuối, sau khi MỌI test xong; gate giết suite ở trần 900 s thì log bằng chứng
# trống ("(no output)"), không biết test nào đã xong. Nay mỗi test xong in ngay một dòng tiến độ ra stderr. Kit riêng KHÔNG có run_bounded.py:
# test chạy trần trong nhóm tiến trình của runner, một kill nhóm dừng hết (như gate). Dừng theo sự kiện (marker, dòng tiến độ), không theo
# đồng hồ (#430: trần giây đỏ oan khi tải 100+); chỉ khi ĐỎ mới chờ hết trần 20 s.
G="$TMP/prog"; mkdir -p "$G/tests/verification" "$G/tests/gates" "$G/tmp"; cp "$DEVKIT_DIR/tests/run_impacted.sh" "$G/tests/"; : > "$G/tests/impact_map.txt"
echo 'echo ok' > "$G/tests/verification/test_repo_consistency.sh"
printf 'touch "%s/fast.ended"\n' "$G" > "$G/tests/gates/test_fast_${TOK}.sh"
printf 'exit 3\n' > "$G/tests/gates/test_bad_${TOK}.sh"
printf 'w=0; while [ ! -e "%s/release" ]; do sleep 0.2; w=$((w + 1)); [ "$w" -gt 600 ] && exit 1; done\n' "$G" > "$G/tests/gates/test_held_${TOK}.sh"
( cd "$G" && git init -q . )
TMPDIR="$G/tmp" DEVKIT_TEST_JOBS=4 python3 -c 'import os, sys; os.setpgrp(); os.execvp("bash", ["bash", sys.argv[1], "--all"])' "$G/tests/run_impacted.sh" \
  >"$TMP/prog_cut.out" 2>&1 & gp=$!
w=0; while [ ! -e "$G/fast.ended" ] && [ "$w" -lt 300 ]; do sleep 0.2; w=$((w + 1)); done
w=0; while [ -e "$G/fast.ended" ] && ! grep -qE "^· done rc=[0-9]+ [0-9]+s tests/gates/test_fast_${TOK}\.sh$" "$TMP/prog_cut.out" && [ "$w" -lt 100 ]; do sleep 0.2; w=$((w + 1)); done
kill -TERM -- "-$gp" 2>/dev/null
for _ in 1 2 3 4 5; do kill -0 -- "-$gp" 2>/dev/null || break; sleep 0.1; done
touch "$G/release"; kill -KILL -- "-$gp" 2>/dev/null; wait "$gp" 2>/dev/null
if [ ! -e "$G/fast.ended" ]; then fail "setup: the fast test never ran: $(cat "$TMP/prog_cut.out")"
else
  grep -qE "^· done rc=0 [0-9]+s tests/gates/test_fast_${TOK}\.sh$" "$TMP/prog_cut.out" \
    && ok "a run killed mid-way already printed the progress line of the test that had ended" || fail "killed run left no progress line: '$(cat "$TMP/prog_cut.out")'"
  ! grep -qE '^(✔|✖) ' "$TMP/prog_cut.out" && ok "  … and it was cut before the ✔/✖ summary (the line is the only trace)" || fail "killed run reached the summary: $(cat "$TMP/prog_cut.out")"
fi
# Lượt bình thường trên cùng kit: stdout (✔/✖, thứ tự, mã thoát) y như trước; dòng tiến độ chỉ ở stderr, mỗi test chạy một dòng,
# không khớp FAIL_LINE của gate (dòng hỏng) và khớp HANG_TEST_LINE (gate gọi tên test cuối khi quá giờ).
so="$(cd "$G" && TMPDIR="$G/tmp" DEVKIT_TEST_JOBS=4 bash tests/run_impacted.sh --all 2>"$TMP/prog.err")"; rc=$?
[ "$rc" = 1 ] && [ "$so" = "$(printf '✖ tests/gates/test_bad_%s.sh\n✔ tests/gates/test_fast_%s.sh\n✔ tests/gates/test_held_%s.sh\n✔ tests/verification/test_repo_consistency.sh' "$TOK" "$TOK" "$TOK")" ] \
  && ok "normal run: stdout is the same ✔/✖ list in list order, exit 1 (one red test)" || fail "normal run stdout changed (rc=$rc): '$so'"
[ "$(grep -c '^· done ' "$TMP/prog.err")" = 4 ] && grep -qE "^· done rc=3 [0-9]+s tests/gates/test_bad_${TOK}\.sh$" "$TMP/prog.err" \
  && ok "normal run: one progress line per test on stderr, with its exit code" || fail "progress lines on stderr: '$(cat "$TMP/prog.err")'"
# #473: the two regexes are read from post-fix-gate.py itself (ast, no hand copy that can drift), and every progress line — `· start` before the
# test runs, `· done` after — must read as a test line and never as a failure line. Each test's start line comes before its done line.
python3 -I -c '
import ast, re, sys
want = {"FAIL_LINE": None, "HANG_TEST_LINE": None, "HANG_START_RE": None, "HANG_DONE_RE": None}
for node in ast.parse(open(sys.argv[2], encoding="utf-8").read()).body:
    if isinstance(node, ast.Assign) and len(node.targets) == 1 and getattr(node.targets[0], "id", "") in want:
        want[node.targets[0].id] = re.compile(ast.literal_eval(node.value.args[0]))
if not all(want.values()):
    print("FAIL_LINE / HANG_TEST_LINE not found in post-fix-gate.py"); sys.exit(2)
ls = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.startswith(("· done ", "· start "))]
starts = [l.split(" ", 2)[2] for l in ls if l.startswith("· start ")]
dones = [l.split(" ", 4)[4] for l in ls if l.startswith("· done ")]
order = all(next(i for i, l in enumerate(ls) if l == "· start " + t) < next(i for i, l in enumerate(ls) if l.startswith("· done ") and l.endswith(" " + t)) for t in dones if t in starts)
ms = [want["HANG_START_RE"].match(l) for l in ls if l.startswith("· start ")]
md = [want["HANG_DONE_RE"].match(l) for l in ls if l.startswith("· done ")]
fmt = all(ms) and all(md) and sorted(m.group(1) for m in ms) == sorted(starts) and sorted(m.group(1) for m in md) == sorted(dones)   # the gate parses the real lines
sys.exit(0 if len(starts) == 4 and sorted(starts) == sorted(dones) and order and fmt
         and all(not want["FAIL_LINE"].search(l) and want["HANG_TEST_LINE"].search(l) for l in ls) else 1)' "$TMP/prog.err" "$DEVKIT_DIR/bin/post-fix-gate.py" \
  && ok "progress lines: a start and a done per test (start first), never a gate failure line, always a test line (regexes from the gate's source)" \
  || fail "progress lines (4 start + 4 done, start first, test lines, no failure lines): $(cat "$TMP/prog.err")"

# #473: SIGPIPE oracle. A gate that is gone leaves stderr a pipe nobody reads: the progress printf then dies of SIGPIPE, so the PASS of the per-test
# cache must already be written BEFORE it (the order in run_one). A stub per_test_cache.py writes a marker when `record` runs; the test waits until the
# reader has closed the pipe (after the `· start` line), so the `· done` printf is certain to meet a closed pipe. Printf before record: no marker.
S="$TMP/sigpipe"; mkdir -p "$S/tests/gates" "$S/tests/lib" "$S/tmp"; cp "$DEVKIT_DIR/tests/run_impacted.sh" "$S/tests/"
printf 'import sys\nif sys.argv[1] == "record":\n    open(%s, "a").write(" ".join(sys.argv[2:]) + "\\n")\n' "\"$S/recorded\"" > "$S/tests/lib/per_test_cache.py"
printf 'w=0; while [ ! -e "%s/closed" ]; do sleep 0.1; w=$((w + 1)); [ "$w" -gt 300 ] && exit 1; done\n' "$S" > "$S/tests/gates/test_pipe_${TOK}.sh"
( cd "$S" && git init -q . )
python3 -I - "$S" <<'PY'
import os, select, subprocess, sys, time
s = sys.argv[1]
r, w = os.pipe()
p = subprocess.Popen(["bash", s + "/tests/run_impacted.sh", "--all"], cwd=s, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=w,
                     env=dict(os.environ, DEVKIT_PER_TEST_CACHE="record", DEVKIT_TEST_JOBS="1", TMPDIR=s + "/tmp"))
os.close(w)
buf, end = b"", time.time() + 60
while b"\xc2\xb7 start " not in buf and time.time() < end:   # "· start " (UTF-8)
    if select.select([r], [], [], 1)[0]:
        chunk = os.read(r, 4096)
        if not chunk:
            break
        buf += chunk
os.close(r)                                                  # nobody reads stderr from here on
open(s + "/closed", "w").close()
try:
    p.wait(timeout=60)
except subprocess.TimeoutExpired:
    p.kill()
PY
grep -qE "test_pipe_${TOK}\.sh 0$" "$S/recorded" 2>/dev/null \
  && ok "run_one: stderr closed (SIGPIPE at the progress printf) and the PASS of the per-test cache was already recorded" \
  || fail "run_one: no per-test cache record after SIGPIPE: the progress printf runs before the record"

# #546: mỗi bài test được cấp TMPDIR riêng đường dẫn ngắn /tmp/dk-XXXXXX (< 25 byte cho AF_UNIX socket trên macOS) và được xoá sạch
# ngay sau khi run_bounded.py kết thúc (kể cả khi bài test tạo mktemp -d trần, thư mục 000 + uchg, hay treo quá giờ bị giết trước trap EXIT).
# Tách riêng bài test runner lồng nhau (timeout rộng 30s tránh flake #430 khi tải cao) và bài test treo quá giờ (timeout ngắn 2s).
TD="$TMP/dk_tmp"; mkdir -p "$TD/tests/verification" "$TD/tests/context_memory" "$TD/tests/lib" "$TD/inner/tests/verification" "$TD/inner/tests/lib" "$TD/out_probe"
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$TD/tests/"
cp "$DEVKIT_DIR/tests/lib/run_bounded.py" "$TD/tests/lib/"
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$TD/inner/tests/"
cp "$DEVKIT_DIR/tests/lib/run_bounded.py" "$TD/inner/tests/lib/"
: > "$TD/tests/impact_map.txt"
: > "$TD/inner/tests/impact_map.txt"
echo 'X = 1' > "$TD/pymod.py"
printf 'mkdir -p rel_sub\nrel_d="$(CDPATH=/tmp TMPDIR=rel_sub mktemp -d)"\nprintf "%%s" "$rel_d" > "%s/rel_mktemp"\ndt_d="$(mktemp -dt mypref)"\nprintf "%%s" "$dt_d" > "%s/dt_mktemp"\nd="$(mktemp -d)"\nprintf "%%s" "$d" > "%s/inner_mktemp"\nrm -rf "$rel_d" "$dt_d" "$d" rel_sub\n' "$TD" "$TD" "$TD" > "$TD/inner/tests/verification/test_repo_consistency.sh"
printf 'printf "%%s" "$TMPDIR" > "%s/seen_tmpdir"\nPYTHONPATH="%s" python3 -c "import pymod; assert pymod.X == 1"\nmkdir -p "$TMPDIR/locked_sub"\necho x > "$TMPDIR/locked_sub/imm"\nchflags uchg "$TMPDIR/locked_sub/imm" 2>/dev/null || true\nchmod 000 "$TMPDIR/locked_sub"\nDEVKIT_TEST_JOBS=1 DEVKIT_TEST_TIMEOUT_S=30 bash "%s/inner/tests/run_impacted.sh" --all > "%s/nested.out" 2>&1\necho "$?" > "%s/nested.rc"\n' "$TD" "$TD" "$TD" "$TD" "$TD" > "$TD/tests/verification/test_repo_consistency.sh"
printf 'dirname "$SB_HEAVY_SLOT_DIR" > "%s/seen_out"\n' "$TD" > "$TD/tests/context_memory/test_budgets.sh"
( cd "$TD" && git init -q . )
( cd "$TD/inner" && git init -q . )
( cd "$TD" && TMPDIR="$TD/out_probe" DEVKIT_REAL_MKTEMP=/tmp DEVKIT_TEST_JOBS=2 DEVKIT_TEST_TIMEOUT_S=30 bash tests/run_impacted.sh --all >/dev/null 2>&1 )
seen_td="$(cat "$TD/seen_tmpdir" 2>/dev/null || true)"
seen_out="$(tr -d '\n' < "$TD/seen_out" 2>/dev/null || true)"
nested_rc="$(cat "$TD/nested.rc" 2>/dev/null || echo missing)"
inner_mk="$(cat "$TD/inner_mktemp" 2>/dev/null || true)"
rel_mk="$(cat "$TD/rel_mktemp" 2>/dev/null || true)"
dt_mk="$(cat "$TD/dt_mktemp" 2>/dev/null || true)"
inner_real="$(cd "$TD/inner" && pwd -P)"
out_left="$(ls -A "$TD/out_probe" 2>/dev/null || true)"
case "$seen_td" in
  /tmp/dk-*)
    td_exists="$([ -e "$seen_td" ] && echo y || echo n)"
    if [ "${#seen_td}" -lt 25 ] && [ "$td_exists" = "n" ]; then
      ok "TMPDIR per test is short (/tmp/dk-*, ${#seen_td} bytes < 25) and removed even with 000+uchg subdirs"
    else
      [ -d "$seen_td" ] && { chmod -R u+rwX "$seen_td" 2>/dev/null; chflags -R nouchg "$seen_td" 2>/dev/null; chmod -R u+rwX "$seen_td" 2>/dev/null; rm -rf "$seen_td" 2>/dev/null || true; }
      fail "TMPDIR length/cleanup failed: '$seen_td' (len=${#seen_td}, exists=$td_exists)"
    fi
    ;;
  *) fail "TMPDIR was not /tmp/dk-*: '$seen_td'" ;;
esac
if [ -n "$seen_out" ] && [ ! -e "$seen_out" ] && [ -z "$out_left" ]; then
  ok "runner cleans up its own \$out dir ('$seen_out') even after running \$alone tests"
else
  [ -n "$seen_out" ] && rm -rf "$seen_out" 2>/dev/null || true
  rm -rf "$TD/out_probe"/* 2>/dev/null || true
  fail "runner leaked \$out dir after \$alone phase: seen_out='$seen_out' (exists=$([ -e "${seen_out:-/nonexistent}" ] && echo y || echo n)) left='$out_left'"
fi
if [ "$nested_rc" = "0" ] && [ -n "$inner_mk" ]; then
  ok "nested run_impacted.sh under parent mktemp shim completes without recursion (rc=0)"
else
  fail "nested run_impacted.sh failed or hung under parent mktemp shim (rc=$nested_rc, inner='$inner_mk', out='$(cat "$TD/nested.out" 2>/dev/null || true)')"
fi
case "$rel_mk" in
  "$inner_real"/rel_sub/*) [ "$(printf '%s\n' "$rel_mk" | wc -l | tr -d ' ')" = "1" ] \
    && ok "mktemp shim returns single-line resolved absolute path under relative TMPDIR ('$rel_mk')" \
    || fail "mktemp shim printed extra lines under CDPATH: '$rel_mk'" ;;
  *) fail "mktemp shim returned wrong path for relative TMPDIR (want '$inner_real/rel_sub/*'): '$rel_mk'" ;;
esac
case "$dt_mk" in
  /tmp/dk-*/mypref.*) ok "mktemp shim supports clustered -dt <prefix> inside short TMPDIR ('$dt_mk')" ;;
  *) fail "mktemp shim mishandled clustered -dt <prefix>: '$dt_mk'" ;;
esac
if [ ! -d "$TD/__pycache__" ]; then
  ok "runner routes PYTHONPYCACHEPREFIX into short /tmp/dk-* so imports leave no __pycache__ in repo tree"
else
  fail "runner leaked __pycache__ into repo tree during test import"
fi

# Bài riêng kiểm tra bài test treo quá giờ bị run_bounded.py giết vẫn dọn sạch thư mục mktemp -d trần bên trong /tmp/dk-*
TD_HANG="$TMP/dk_hang"; mkdir -p "$TD_HANG/tests/verification" "$TD_HANG/tests/lib"
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$TD_HANG/tests/"
cp "$DEVKIT_DIR/tests/lib/run_bounded.py" "$TD_HANG/tests/lib/"
: > "$TD_HANG/tests/impact_map.txt"
echo 'echo ok' > "$TD_HANG/tests/verification/test_repo_consistency.sh"
printf 'd="$(mktemp -d)"\nprintf "%%s" "$d" > "%s/leaked_dir"\nsleep 30\n' "$TD_HANG" > "$TD_HANG/tests/verification/test_hang_${TOK}.sh"
( cd "$TD_HANG" && git init -q . )
( cd "$TD_HANG" && RUN_BOUNDED_GRACE_S=0.5 DEVKIT_TEST_JOBS=1 DEVKIT_TEST_TIMEOUT_S=2 bash tests/run_impacted.sh --all >/dev/null 2>&1 )
leaked_td="$(cat "$TD_HANG/leaked_dir" 2>/dev/null || true)"
if [ -n "$leaked_td" ] && [ ! -e "$leaked_td" ] && [ ! -e "$(dirname "$leaked_td")" ]; then
  ok "timed-out test killed by run_bounded.py leaves no leaked mktemp -d directory"
else
  [ -n "$leaked_td" ] && rm -rf "$leaked_td" "$(dirname "$leaked_td")" 2>/dev/null || true
  fail "timed-out test leaked mktemp -d directory: '$leaked_td'"
fi
python3 -I - "$DEVKIT_DIR/scripts/governance" <<'PY' && ok "scratch_cleanup TEST_TMP_PREFIXES includes dk-" || fail "TEST_TMP_PREFIXES missing dk-"
import sys
sys.path.insert(0, sys.argv[1])
import scratch_cleanup as sc
sys.exit(0 if "dk-" in sc.TEST_TMP_PREFIXES else 1)
PY

if [ "$FAILS" -ne 0 ]; then echo "run_impacted: $FAILS FAILED"; exit 1; fi
echo "run_impacted: all checks passed"
