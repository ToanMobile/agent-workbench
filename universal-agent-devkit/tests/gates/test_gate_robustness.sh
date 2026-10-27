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
# 24/10: mỗi lần chạy gate ở đây có hạn giờ (tests/lib/run_bounded.py). Gate kẹt (ca A3 control: open() một FIFO) thì bài FAIL với
# exit 124, không treo mãi và không để post-fix-gate.py mồ côi (hai tiến trình như vậy từng sống 18h).
# Hạn mỗi lần gọi: 120 s (một lần gate ở đây ~5 s, máy tải cao ~30 s). Giá trị lạ thì dùng 120: helper lỗi cách dùng thoát 64, và
# một giá trị hỏng không bao giờ được biến thành exit 2 mà các ca A3/A8/A10 chờ (xanh giả khi gate chưa hề chạy).
case "${GATE_ROBUSTNESS_DEADLINE_S:-}" in ''|*[!0-9]*) GATE_ROBUSTNESS_DEADLINE_S=120 ;; esac
[ "$((10#$GATE_ROBUSTNESS_DEADLINE_S))" -gt 0 ] || GATE_ROBUSTNESS_DEADLINE_S=120   # 0, 00, 000 = "no deadline" in the helper: refused
BOUND=("$PY" -I "$DEVKIT_DIR/tests/lib/run_bounded.py" "$GATE_ROBUSTNESS_DEADLINE_S" --)

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
  OUT="$(CLAUDE_PROJECT_DIR="$PWD" POSTFIX_GATE_FORCE_FULL=1 "${BOUND[@]}" "$PY" "$GATE" --matrix "$PWD/matrix.json" --lang en "$@" 2>&1)"; RC=$?
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
  OUT="$(PATH="$TMP/nogit-bin" CLAUDE_PROJECT_DIR="$PWD" "${BOUND[@]}" "$PY" "$GATE" --matrix "$PWD/matrix.json" --lang en --run-tests --full $mode 2>&1)"; RC=$?
  expect_rc "A10: no git on PATH ${mode:-(plain)}: UNVERIFIED" 2
  printf '%s\n' "$OUT" | grep -q Traceback && bad "A10 ${mode:-(plain)}: a traceback was printed" \
    || { printf '%s\n' "$OUT" | grep -qi "git" && ok "A10 ${mode:-(plain)}: a clear message names git" || bad "A10 ${mode:-(plain)}: no message about git"; }
done

# ── A9: a signal to the gate kills the suites it started, and the gate dies by that signal ─────────────────────
# Start python with SIGINT, SIGHUP and SIGTERM at their default (a background job of a script inherits SIGINT ignored, a
# nohup'd runner SIGHUP: the merge queue starts its train both ways, 27/10); it execs the gate, so
# $! is the gate's own pid (a shell function run with & would be a subshell: the signal would never reach the gate).
LAUNCH='import os, signal, sys; [signal.signal(s, signal.SIG_DFL) for s in (signal.SIGINT, signal.SIGHUP, signal.SIGTERM)]; os.execv(sys.argv[1], sys.argv[1:])'
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

# ── A11: a suite that times out gets SIGTERM first, so its EXIT trap removes its temp dir (2026-10-19: the timeout's bare
# SIGKILL skipped every trap; ~8 GiB of fixture dirs piled up in TMPDIR, the disk hit 99 %) ─────────────────────────────
mkdir -p "$TMP/a11"
cat > "$TMP/a11/suite.sh" <<'EOF'
#!/usr/bin/env bash
T="$(mktemp -d "$1/leak.XXXXXX")"
trap 'rm -rf "$T"' EXIT
echo started
sleep 60
EOF
res="$("$PY" - "$GATE" "$TMP/a11" <<'EOF' 2>&1
import importlib.util, os, sys, time
spec = importlib.util.spec_from_file_location("gate", sys.argv[1])
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
d = sys.argv[2]
t0 = time.monotonic()
rc, out, timed_out = g.run_in_group(f"bash {d}/suite.sh {d}", d, dict(os.environ), 2)
left = [n for n in os.listdir(d) if n.startswith("leak.")]
print(f"timed_out={timed_out} left={left} secs={time.monotonic() - t0:.1f} started={'started' in out}")
EOF
)"
printf '%s\n' "$res" | grep -q "timed_out=True left=\[\] .*started=True" \
  && ok "A11: a timed-out suite ran its EXIT trap (TERM before KILL): no temp dir left" \
  || bad "A11: a timed-out suite left its temp dir: $(printf '%s' "$res" | tail -2)"

# ── A12: killpg refused (EPERM — macOS refuses a signal to a process group that holds a zombie) while a suite times out: run_in_group
# must not raise. 20/10: the gate died with a PermissionError traceback, so the receipt of the same content was never dropped and the
# next --full re-used the PASS of before the hang (a false green). The suite's own shell still gets the signal. ─────────────────────
mkdir -p "$TMP/a12"
res="$("$PY" - "$GATE" "$TMP/a12" <<'EOF' 2>&1
import importlib.util, os, signal, sys, time
spec = importlib.util.spec_from_file_location("gate", sys.argv[1])
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
d = sys.argv[2]
real_killpg, refused = os.killpg, []
def killpg(pgid, sig):
    refused.append(sig)
    raise PermissionError(1, "Operation not permitted")
os.killpg = killpg
t0 = time.monotonic()
try:
    rc, out, timed_out = g.run_in_group("echo started; exec sleep 30", d, dict(os.environ), 1)
    print(f"raised=no timed_out={timed_out} refused={len(refused)} secs={time.monotonic() - t0:.1f}")
except Exception as e:
    print(f"raised={type(e).__name__}")
EOF
)"
printf '%s\n' "$res" | grep -qE "raised=no timed_out=True refused=[1-9]" \
  && ok "A12: killpg refused (EPERM) on a timed-out suite: run_in_group returns TIMEOUT, no crash ($(printf '%s' "$res" | tail -1))" \
  || bad "A12: killpg refused (EPERM) on a timed-out suite crashed the gate: $(printf '%s' "$res" | tail -2)"
# under the 10 s TERM grace: the TERM fallback itself ended the suite (a broken TERM path still ends ~11 s later through KILL)
printf '%s\n' "$res" | grep -qE "secs=[0-4]\." \
  || bad "A12: the TERM fallback did not end the timed-out suite before the KILL grace: $(printf '%s' "$res" | tail -1)"

# ── A12b: killpg refused AND a grandchild keeps the output pipe open (it was not in the signalled process): run_in_group must still
# return soon after the KILL grace, not wait on the pipe for the grandchild's whole life (review 20/10).
res="$("$PY" - "$GATE" "$TMP/a12" <<'EOF' 2>&1
import importlib.util, os, signal, sys, time
spec = importlib.util.spec_from_file_location("gate", sys.argv[1])
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
g._SUITE_TERM_GRACE_S = 1
def killpg(pgid, sig):
    raise PermissionError(1, "Operation not permitted")
os.killpg = killpg
t0 = time.monotonic()
rc, out, timed_out = g.run_in_group("(sleep 25; echo late) & exec sleep 25", sys.argv[2], dict(os.environ), 1)
print(f"timed_out={timed_out} secs={time.monotonic() - t0:.1f}")
EOF
)"
printf '%s\n' "$res" | grep -qE "timed_out=True secs=([0-9]|1[0-4])\." \
  && ok "A12b: a grandchild holding the pipe does not hold run_in_group past the grace ($(printf '%s' "$res" | tail -1))" \
  || bad "A12b: run_in_group waited on the grandchild's pipe: $(printf '%s' "$res" | tail -2)"

# ── A13: stale_rerun._execute (nightly, STALE re-run) has the same killpg; EPERM there must not raise either (review 20/10)
res="$("$PY" - "$DEVKIT_DIR/scripts/testing" "$TMP/a12" <<'EOF' 2>&1
import os, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import stale_rerun as sr
def killpg(pgid, sig):
    raise PermissionError(1, "Operation not permitted")
os.killpg = killpg
try:
    st, code, out = sr._execute(Path(sys.argv[2]), "exec sleep 20", 1)
    print(f"raised=no status={st}")
except Exception as e:
    print(f"raised={type(e).__name__}")
EOF
)"
printf '%s\n' "$res" | grep -q "raised=no status=TIMEOUT" \
  && ok "A13: stale_rerun._execute with killpg refused (EPERM): TIMEOUT, no crash" \
  || bad "A13: stale_rerun._execute crashed on EPERM: $(printf '%s' "$res" | tail -1)"

# ── A14 (#370): a suite that times out while the machine is idle is a HANG, not "slow": the gate names the last test the suite printed
# and snapshots the suite's process group (ps) before it kills it. Under a busy machine the same timeout stays a plain TIMEOUT. ────
mk hang
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-H","name":"hang","command":"echo \"running tests/test_slow_$(echo thing).sh\"; exec sleep $((30+1))"}]}]}
JSON
git add -A && git commit -qm matrix
printf 'def f():\n    return 2\n' > src/core.py
DEVKIT_CAPACITY_LOAD=0.5 gate --run-tests --full --timeout 2
expect_rc "A14: a suite timed out on an idle machine fails the gate" 1
printf '%s\n' "$OUT" | grep -q "HANG" && ok "A14: low load: the timeout is reported as HANG" || bad "A14: low load: no HANG in the output"
printf '%s\n' "$OUT" | grep -q "tests/test_slow_thing.sh" && ok "A14: HANG names the last test the suite printed" || bad "A14: HANG does not name the last test"
printf '%s\n' "$OUT" | grep -q "sleep 31" && ok "A14: HANG carries the process snapshot (ps) of the stuck suite" || bad "A14: HANG has no process snapshot"
DEVKIT_CAPACITY_LOAD=9999 gate --run-tests --full --timeout 2
# the control must prove the suite really RAN and TIMED OUT (a BUSY / SLOT / early failure has no HANG either and would pass for the wrong reason)
printf '%s\n' "$OUT" | grep -qE "TIMEOUT.*REG-H" && ! printf '%s\n' "$OUT" | grep -qE "(BUSY|SLOT|BUDGET).*REG-H" && [ "$RC" = 1 ] \
  && ok "A14: control: heavy load, the suite ran and TIMED OUT (status TIMEOUT, exit 1)" || bad "A14: control: no TIMEOUT status for REG-H under heavy load (rc=$RC): $(printf '%s' "$OUT" | grep REG-H | head -3)"
printf '%s\n' "$OUT" | grep -q "HANG" && bad "A14: control: a timeout under heavy load must not be called HANG" || ok "A14: control: heavy load, the timeout is not called HANG"

# ── A15 (#370 sau dda818bb): run_impacted.sh chạy mỗi bài qua tests/lib/run_bounded.py, lệnh của bài nằm trong session / process group
# RIÊNG. Ảnh chụp ps lúc quá giờ lọc theo pgid của suite thì chỉ còn shell và helper, mất đúng tiến trình lá đang kẹt. Ảnh phải đi theo
# cây tiến trình (ppid). Số 307 chỉ được tính trong tiến trình lá ($((300+7))), nên "sleep 307" không có trong argv của tổ tiên nào.
mk hangleaf
"$PY" - "$PY" "$DEVKIT_DIR/tests/lib/run_bounded.py" > matrix.json <<'EOF'
import json, shlex, sys
cmd = 'echo "running tests/test_stuck_leaf.sh"; ' + shlex.join([sys.argv[1], "-I", sys.argv[2], "300", "--", "sh", "-c", "exec sleep $((300+7))"])
print(json.dumps({"project": "t", "rules": [{"component": "Core", "watch_files": ["src/*"],
                  "mandatory_regression_tests": [{"id": "REG-L", "name": "leaf", "command": cmd}]}]}))
EOF
git add -A && git commit -qm matrix
printf 'def f():\n    return 2\n' > src/core.py
DEVKIT_CAPACITY_LOAD=0.5 gate --run-tests --full --timeout 3
expect_rc "A15: a suite whose stuck process sits in its own session fails the gate" 1
printf '%s\n' "$OUT" | grep -q "HANG" && printf '%s\n' "$OUT" | grep -q "tests/test_stuck_leaf.sh" \
  && ok "A15: the timeout is reported as HANG with the last test line" || bad "A15: no HANG / last test line: $(printf '%s' "$OUT" | grep REG-L | head -3)"
printf '%s\n' "$OUT" | grep -q "sleep 307" && ok "A15: the snapshot carries the stuck leaf in its own session (process tree, not pgid)" \
  || bad "A15: the snapshot lost the stuck leaf in its own session: $(printf '%s' "$OUT" | grep -A8 'HANG\|PPID' | head -12)"

# ── A16 (#427 / hang giả 27/10): tải thấp KHÔNG đủ để gọi là HANG. REG-DK-ALL-01 hết 900 s đúng lúc đang chạy đuôi tuần tự (tải ~15 < 36)
# trong khi suite vẫn tiến triển (test đang chạy mới 6 s, tiến trình lá mới sinh) mà vẫn bị dán nhãn HANG. Suite ở đây liên tục sinh
# tiến trình mới: quá giờ là TIMEOUT thường, không phải HANG. `sleep 1 &` chồng lên nhau để lúc ps chụp luôn có một tiến trình trẻ
# (một vòng `sleep 0.3` trơn có khe giữa hai lần sleep, khi đó chỉ còn shell 3 s tuổi). A14 / A15 (treo thật, `exec sleep`) vẫn là HANG.
mk busy
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-B","name":"busy","command":"echo \"running tests/test_busy_$(echo tail).sh\"; while :; do sleep 1 & sleep 0.2; done"}]}]}
JSON
git add -A && git commit -qm matrix
printf 'def f():\n    return 2\n' > src/core.py
DEVKIT_CAPACITY_LOAD=0.5 gate --run-tests --full --timeout 3
# phải chứng minh suite THẬT SỰ chạy và quá giờ (BUSY / SLOT / lỗi sớm cũng không có HANG, sẽ xanh sai lý do)
printf '%s\n' "$OUT" | grep -qE "TIMEOUT.*REG-B" && ! printf '%s\n' "$OUT" | grep -qE "(BUSY|SLOT|BUDGET).*REG-B" && [ "$RC" = 1 ] \
  && ok "A16: low load, a suite still starting processes ran and TIMED OUT (status TIMEOUT, exit 1)" \
  || bad "A16: no TIMEOUT status for REG-B (rc=$RC): $(printf '%s' "$OUT" | grep REG-B | head -3)"
printf '%s\n' "$OUT" | grep -q "HANG" && bad "A16: a suite still making progress (fresh processes) must not be called HANG: $(printf '%s' "$OUT" | grep HANG | head -3)" \
  || ok "A16: low load but fresh processes: the timeout is not called HANG"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_robustness: all tests passed" || { echo "❌ test_gate_robustness: $FAILS failed"; exit 1; }
