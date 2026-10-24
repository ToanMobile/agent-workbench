#!/usr/bin/env bash
# Hồi quy (24/10, lỗi nghiêm trọng): run_impacted.sh chạy từng test bằng `bash "$1"` KHÔNG hạn giờ. Một test kẹt (ca A3 control của
# test_gate_robustness.sh: gate mở một FIFO không có bên ghi, kẹt trong open() của nhân) làm cả lượt treo, và khi tiến trình cha chết
# thì gate con thành mồ côi: hai tiến trình post-fix-gate.py sống 18h51 và 18h26, giữ khoá/tải, các gate khác báo BUSY và chờ tải.
# Nay mọi test chạy qua tests/lib/run_bounded.py: hết hạn, caller chết, Ctrl-C/TERM tới nhóm, hay chính helper bị SIGKILL thì cả
# nhóm tiến trình của lệnh (cả cháu chắt) bị giết — không bao giờ để mồ côi.
#   b1 lệnh quá giờ bị giết đúng hạn, exit 124, tiến trình cháu cũng chết · b2 lệnh xong sớm: đúng exit code, không chờ hết hạn
#   b3 helper bị SIGTERM giữa chừng: nhóm lệnh chết · b4 test_gate_robustness.sh thật sự gọi gate qua helper
#   b5 tiến trình gọi helper bị SIGKILL: nhóm lệnh chết · b6 run_impacted.sh thật với một bài treo: bài bị cắt, lượt chạy kết thúc
#   b7 bài kết thúc bình thường mà để lại tiến trình nền: dọn · b8 chính helper bị SIGKILL: watchdog dọn
#   b9 lỗi cách dùng thoát 64 (không bao giờ 2) · b10 Ctrl-C tới nhóm của caller vẫn dừng được bài
#   b11 nhóm của caller nhận TERM rồi KILL ngay (timeout của post-fix-gate, vacuity, `agent-kit test` stop) và bài bỏ qua TERM:
#       watchdog vẫn giết bài sau ân hạn · b12 INT/HUP bị caller bỏ qua (nohup) vẫn bị bỏ qua ở lệnh
# Máy quá tải đến mức tiến trình không kịp ghi pid (W2b): ⚠ "not judged", không bao giờ ✖ giả.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RB="$DEVKIT_DIR/tests/lib/run_bounded.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }; skip() { echo "⚠ $1: machine busy, not judged"; }
alive() { [ "${1:-0}" -gt 1 ] 2>/dev/null && kill -0 "$1" 2>/dev/null; }   # pid 0 / rỗng = nhóm của chính test: không bao giờ kill
pidof_file() { # <file>: in pid ghi trong file (chờ tối đa 10 s), rỗng khi không kịp
  local i=0; while [ ! -s "$1" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; cat "$1" 2>/dev/null
}
gone_within() { # <pid> <tenths>: chờ pid chết, tối đa <tenths>/10 s
  local i=0; while alive "$1" && [ "$i" -lt "$2" ]; do sleep 0.1; i=$((i + 1)); done; ! alive "$1"
}
hang_script() { # <file> <pidfile> [trap-TERM]: một bash ghi pid của nó rồi chờ 300 s (bỏ qua TERM nếu có đối số 3)
  { echo '#!/bin/bash'; [ -n "${3:-}" ] && echo "trap '' TERM"; echo "echo \$\$ > '$2'"; echo 'sleep 300 & wait'; } > "$1"
}

# b1: một lệnh treo + một tiến trình cháu cũng treo; hạn 2 s
printf '#!/bin/bash\nsleep 300 &\necho $! > "%s/grandchild.pid"\nsleep 300\n' "$TMP" > "$TMP/hang.sh"
start=$(date +%s)
python3 -I "$RB" 2 -- bash "$TMP/hang.sh" >"$TMP/b1.out" 2>&1; rc=$?
took=$(( $(date +%s) - start ))
gc=$(cat "$TMP/grandchild.pid" 2>/dev/null)
if [ -z "$gc" ]; then skip "b1 hung command"
elif [ "$rc" = 124 ] && [ "$took" -le 15 ] && gone_within "$gc" 20 && grep -q "killed after 2s" "$TMP/b1.out"; then
  ok "b1 a hung command is killed at its deadline (rc=124, ${took}s), its grandchild dies too"
else bad "b1 hung command (rc=$rc, ${took}s, grandchild alive=$(alive "$gc" && echo yes || echo no))"; cat "$TMP/b1.out"; fi
if alive "$gc"; then kill -KILL "$gc" 2>/dev/null; fi

# b2: xong sớm trả đúng exit code, không chờ hết hạn
start=$(date +%s)
python3 -I "$RB" 60 -- bash -c 'echo hi; exit 7' >"$TMP/b2.out" 2>&1; rc=$?
took=$(( $(date +%s) - start ))
[ "$rc" = 7 ] && [ "$took" -le 10 ] && grep -q '^hi$' "$TMP/b2.out" && ok "b2 a command that ends early keeps its exit code and output (rc=7)" \
  || { bad "b2 early exit (rc=$rc, ${took}s)"; cat "$TMP/b2.out"; }

# b3: helper bị SIGTERM giữa chừng: nhóm lệnh không ở lại
hang_script "$TMP/h3.sh" "$TMP/c3.pid"
python3 -I "$RB" 120 -- bash "$TMP/h3.sh" >/dev/null 2>&1 & hp=$!
c=$(pidof_file "$TMP/c3.pid")
kill -TERM "$hp" 2>/dev/null; wait "$hp" 2>/dev/null
if [ -z "$c" ]; then skip "b3 helper SIGTERM"
elif gone_within "$c" 80; then ok "b3 a helper killed by SIGTERM mid-run takes the command's group with it (no orphan)"
else bad "b3 the command $c outlived its SIGTERMed helper"; kill -KILL -- "-$c" "$c" 2>/dev/null; fi

# b4: test_gate_robustness.sh gọi gate qua helper ở cả gate() lẫn ca không có git (đúng lời gọi, không phải chữ trong comment)
n=$(grep -c '"\${BOUND\[@\]}" "\$PY" "\$GATE"' "$DEVKIT_DIR/tests/gates/test_gate_robustness.sh")
[ "${n:-0}" -ge 2 ] && ok "b4 test_gate_robustness.sh runs its synchronous gate calls through the helper ($n calls)" \
  || bad "b4 test_gate_robustness.sh: $n bounded gate call(s), want 2 (a FIFO hang would leave orphans)"

# b5: tiến trình GỌI helper bị SIGKILL (không trap nào chạy): helper thấy cha đổi và giết nhóm lệnh.
#     `; true` để bash -c không exec thẳng helper (khi đó SIGKILL trúng chính helper: ca b8).
hang_script "$TMP/h5.sh" "$TMP/c5.pid"
bash -c "python3 -I '$RB' 0 -- bash '$TMP/h5.sh'; true" >/dev/null 2>&1 & wp=$!
c=$(pidof_file "$TMP/c5.pid")
kill -KILL "$wp" 2>/dev/null; wait "$wp" 2>/dev/null
if [ -z "$c" ]; then skip "b5 caller SIGKILL"
elif gone_within "$c" 80; then ok "b5 the caller SIGKILLed: the helper notices and ends the command's group"
else bad "b5 command $c outlived its SIGKILLed caller"; kill -KILL -- "-$c" "$c" 2>/dev/null; fi

# b6: run_impacted.sh thật (bản sao trong một kit giả) với một bài treo: bài bị cắt ở DEVKIT_TEST_TIMEOUT_S, lượt chạy kết thúc,
#     bài kia vẫn PASS, log nêu lý do. Lượt này chạy trong nhóm riêng, có hạn 60 s: runner hỏng thì b6 FAIL và cả nhóm bị dọn.
K="$TMP/kit"; mkdir -p "$K/tests/lib" "$K/tests/zz"
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$K/tests/" && cp "$RB" "$K/tests/lib/"
printf '#!/bin/bash\nsleep 300 &\necho $! > "%s/grand6.pid"\nsleep 300\n' "$TMP" > "$K/tests/zz/test_hang.sh"
printf '#!/bin/bash\necho fine\n' > "$K/tests/zz/test_ok.sh"
DEVKIT_TEST_TIMEOUT_S=3 DEVKIT_TEST_JOBS=2 RUN_BOUNDED_GRACE_S=1 \
  python3 -c 'import os, sys; os.setpgrp(); os.execvp("bash", ["bash", sys.argv[1], "--all"])' "$K/tests/run_impacted.sh" \
  >"$TMP/b6.out" 2>&1 & rp=$!
if ! gone_within "$rp" 600; then
  kill -KILL -- "-$rp" 2>/dev/null; wait "$rp" 2>/dev/null; bad "b6 run_impacted.sh still running after 60 s: a hung test is not bounded"
else
  wait "$rp"; rc6=$?
  g6=$(cat "$TMP/grand6.pid" 2>/dev/null)
  if [ "$rc6" = 1 ] && grep -q "✖ tests/zz/test_hang.sh" "$TMP/b6.out" && grep -q "✔ tests/zz/test_ok.sh" "$TMP/b6.out" \
     && grep -q "killed after 3s" "$TMP/b6.out" && { [ -z "$g6" ] || gone_within "$g6" 20; }; then
    ok "b6 run_impacted.sh cuts a hung test at DEVKIT_TEST_TIMEOUT_S, says why, kills its grandchild, the other test still passes"
  else bad "b6 run_impacted.sh with a hung test (rc=$rc6)"; cat "$TMP/b6.out"; fi
  if alive "$g6"; then kill -KILL "$g6" 2>/dev/null; fi
fi

# b7: bài kết thúc BÌNH THƯỜNG nhưng để lại tiến trình nền (quên dọn): exit code giữ nguyên, tiến trình nền vẫn bị dọn
printf '#!/bin/bash\nsleep 300 &\necho $! > "%s/left7.pid"\nexit 0\n' "$TMP" > "$TMP/leave.sh"
python3 -I "$RB" 60 -- bash "$TMP/leave.sh" >"$TMP/b7.out" 2>&1; rc=$?
l7=$(cat "$TMP/left7.pid" 2>/dev/null)
if [ -z "$l7" ]; then skip "b7 leftover background process"
elif [ "$rc" = 0 ] && gone_within "$l7" 30; then ok "b7 a command that ends normally keeps rc=0 and its leftover background process is reaped"
else bad "b7 leftover background process $l7 outlived a normal exit (rc=$rc)"; kill -KILL "$l7" 2>/dev/null; fi

# b8: chính helper bị SIGKILL (không bắt được): watchdog ở session riêng thấy helper mất và giết nhóm lệnh
hang_script "$TMP/h8.sh" "$TMP/c8.pid"
RUN_BOUNDED_GRACE_S=1 python3 -I "$RB" 0 -- bash "$TMP/h8.sh" >/dev/null 2>&1 & hp8=$!
c=$(pidof_file "$TMP/c8.pid")
kill -KILL "$hp8" 2>/dev/null; wait "$hp8" 2>/dev/null
if [ -z "$c" ]; then skip "b8 helper SIGKILL"
elif gone_within "$c" 80; then ok "b8 the helper itself SIGKILLed: its watchdog ends the command's group"
else bad "b8 command $c outlived a SIGKILLed helper (no watchdog)"; kill -KILL -- "-$c" "$c" 2>/dev/null; fi

# b9: lỗi cách dùng thoát 64, không bao giờ 2 (2 = UNVERIFIED của gate: một hạn giờ hỏng không được thành "gate trả 2")
python3 -I "$RB" 5m -- true >/dev/null 2>&1; r1=$?
python3 -I "$RB" -1 -- true >/dev/null 2>&1; r2=$?
python3 -I "$RB" 5 true >/dev/null 2>&1; r3=$?
[ "$r1" = 64 ] && [ "$r2" = 64 ] && [ "$r3" = 64 ] && ok "b9 a bad deadline or a missing -- exits 64 (never the gate's UNVERIFIED 2)" \
  || bad "b9 usage errors exit $r1/$r2/$r3, want 64"

# b10: Ctrl-C = SIGINT tới cả nhóm tiền cảnh của caller: helper ở trong nhóm đó nên nhận được và dừng lệnh.
#      Job nền của một script có SIGINT bị bỏ qua (bash), còn job tiền cảnh thật thì không: trả SIGINT về mặc định như tiền cảnh.
hang_script "$TMP/h10.sh" "$TMP/c10.pid"
python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.setpgrp(); os.execvp("bash", ["bash", "-c", sys.argv[1]])' \
  "python3 -I '$RB' 0 -- bash '$TMP/h10.sh'; true" >/dev/null 2>&1 & gp=$!
c=$(pidof_file "$TMP/c10.pid")
kill -INT -- "-$gp" 2>/dev/null
if [ -z "$c" ]; then skip "b10 Ctrl-C"
elif gone_within "$c" 80; then ok "b10 Ctrl-C (SIGINT to the caller's process group) reaches the helper and stops the command"
else bad "b10 Ctrl-C did not stop the command $c (the helper left the caller's group?)"; kill -KILL -- "-$c" "$c" 2>/dev/null; fi
kill -KILL -- "-$gp" 2>/dev/null; wait "$gp" 2>/dev/null

# b11: nhóm của caller nhận TERM rồi KILL ngay (run_in_group của post-fix-gate khi suite quá giờ, vacuity, stop của agent-kit) và
#      bài bỏ qua TERM: helper chết theo KILL trước khi kịp làm gì, watchdog vẫn giết bài sau ân hạn
hang_script "$TMP/h11.sh" "$TMP/c11.pid" trap
RUN_BOUNDED_GRACE_S=1 python3 -c 'import os, sys; os.setpgrp(); os.execvp("bash", ["bash", "-c", sys.argv[1]])' \
  "python3 -I '$RB' 0 -- bash '$TMP/h11.sh'; true" >/dev/null 2>&1 & gp=$!
c=$(pidof_file "$TMP/c11.pid")
kill -TERM -- "-$gp" 2>/dev/null; kill -KILL -- "-$gp" 2>/dev/null; wait "$gp" 2>/dev/null
if [ -z "$c" ]; then skip "b11 group TERM+KILL"
elif gone_within "$c" 80; then ok "b11 the caller's group gets TERM then KILL and the command ignores TERM: the watchdog still kills it"
else bad "b11 command $c (ignores TERM) outlived a TERM+KILL of its caller's group"; kill -KILL -- "-$c" "$c" 2>/dev/null; fi

# b12: caller bỏ qua INT/HUP (nohup): lệnh cũng vẫn bỏ qua chúng — helper không lặng lẽ đổi ý định đó
got12=$(bash -c "trap '' INT HUP; python3 -I '$RB' 30 -- python3 -c 'import signal as s; print(s.getsignal(s.SIGINT) == s.SIG_IGN, s.getsignal(s.SIGHUP) == s.SIG_IGN)'" 2>&1)
[ "$got12" = "True True" ] && ok "b12 an INT / HUP the caller ignores (nohup) stays ignored for the command" \
  || bad "b12 the command's INT/HUP disposition changed under the helper: $got12"

# b13: stderr của helper là một pipe mà bên đọc chết cùng đợt tín hiệu (đúng gate() của test_gate_robustness.sh: OUT="$(… 2>&1)").
#      Python bỏ qua SIGPIPE nên một print ra stderr ném BrokenPipeError: dòng log đó không được làm hỏng việc giết nhóm lệnh.
#      Ca TERM (đường của helper) và ca KILL (đường của watchdog).
for how in TERM KILL; do
  hang_script "$TMP/h13$how.sh" "$TMP/c13$how.pid"
  python3 -c 'import os, sys; os.setpgrp(); os.execvp("bash", ["bash", "-c", sys.argv[1]])' \
    "OUT=\"\$(RUN_BOUNDED_GRACE_S=1 python3 -I '$RB' 0 -- bash '$TMP/h13$how.sh' 2>&1)\"; true" >/dev/null 2>&1 & gp=$!
  disown "$gp" 2>/dev/null   # its death by our signal is the point: no "Terminated" job notice in the test output
  c=$(pidof_file "$TMP/c13$how.pid")
  kill -"$how" -- "-$gp" 2>/dev/null; sleep 0.5; kill -KILL -- "-$gp" 2>/dev/null
  if [ -z "$c" ]; then skip "b13 $how with a dead stderr reader"
  elif gone_within "$c" 80; then ok "b13 $how to a group whose stderr reader dies too: the command is still killed (no BrokenPipe orphan)"
  else bad "b13 $how: command $c survived because logging to a dead stderr pipe aborted the cleanup"; kill -KILL -- "-$c" "$c" 2>/dev/null; fi
done

[ "$FAILS" -eq 0 ] && echo "run_bounded: all checks passed" || { echo "run_bounded: $FAILS FAILED"; exit 1; }
