#!/usr/bin/env bash
# Q5 (pha2 merge queue, v4 mục 1): `agent-kit integrate [--if-due] [--dry-run]` — điểm gộp của repo trunk-push (không đi PR).
# Commit trên main local chưa có trên origin là hàng đợi. Tới hạn (số commit ≥ devkit.integrate.batchMax, commit cũ nhất ≥
# devkit.integrate.maxWaitMin phút, hoặc máy rảnh: không test_run.lock nào của các worktree bị giữ) thì: khoá fcntl
# <common>/devkit-integrate.lock (bận → exit 0), fetch, origin/<base> phải là tổ tiên của HEAD (không thì dừng, không chạy gate),
# gate --full MỘT lần trong worktree scratch tách rời ở HEAD (không trong checkout main), xanh + push_gate nhận biên nhận → push;
# đỏ → không push, in các commit của đợt. Gate là post-fix-gate THẬT (ma trận một suite `bash check.sh`) qua một kit giả chỉ
# bọc nó để đếm lượt gọi; push_gate là bản thật, nên ca "push" chứng minh push_gate nhận biên nhận của cây scratch.
#  I1 chưa tới hạn → không gate, không push · I2 nothing pending → exit 0 · I3 tới hạn (batchMax) + gate xanh → push đúng HEAD,
#  scratch đã gỡ · I4 gate đỏ → không push, in commit của đợt, exit 1 · I5 origin phân kỳ → exit ≠ 0, không gate ·
#  I6 khoá bận → exit 0, không gate · I7 gate exit 0 nhưng không có biên nhận → push_gate từ chối, không push ·
#  I8 --dry-run: tới hạn theo tuổi / máy rảnh, không gate · I9 _TRUNK_ALLOWED cho `agent-kit integrate` ở trunk mode ·
#  I10 help + completion có integrate · I11 (#463) hook bị ignore mà settings.json đăng ký có trong scratch: health xanh, push.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; TMP="$(cd -P "$TMP" && pwd -P)"
HOLDER=""
cleanup() { [ -z "$HOLDER" ] || kill "$HOLDER" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
export DEVKIT_GATE_SLOTS=0 SB_HEAVY_SLOT_DIR="$TMP/slots"   # hàng đợi gate toàn máy / khe nặng: không dính máy thật
export INTEGRATE_GATE_LOG="$TMP/gate.log"

# Kit giả: bin/ = link tới mọi file thật, trừ post-fix-gate.py là lớp bọc ghi một dòng mỗi lượt gọi rồi chạy gate thật
# (FAKE_GATE_EXIT đặt: thoát ngay với mã đó, không chạy gì, không biên nhận). scripts/ và profiles/ là link tới bản thật.
FK="$TMP/kit"; mkdir -p "$FK/bin"
for f in "$DEVKIT_DIR"/bin/*; do [ "$(basename "$f")" = post-fix-gate.py ] || ln -s "$f" "$FK/bin/$(basename "$f")"; done
rm -f "$FK/bin/agent-kit" && cp "$DEVKIT_DIR/bin/agent-kit" "$FK/bin/agent-kit"   # bản chép: agent-kit đi theo link về kit thật
ln -s "$DEVKIT_DIR/scripts" "$FK/scripts"; ln -s "$DEVKIT_DIR/profiles" "$FK/profiles"; ln -s "$DEVKIT_DIR/hooks" "$FK/hooks"
ln -s "$DEVKIT_DIR/completions" "$FK/completions"
cat > "$FK/bin/post-fix-gate.py" <<PY
import os, sys
REAL = "$DEVKIT_DIR/bin/post-fix-gate.py"
if __name__ != "__main__":   # push_gate nạp gate như module (needs_no_test): đưa đúng module thật, không đếm
    __file__ = REAL
    exec(compile(open(REAL, encoding="utf-8").read(), REAL, "exec"))
else:
    with open(os.environ["INTEGRATE_GATE_LOG"], "a") as f:
        f.write(os.getcwd() + " " + " ".join(sys.argv[1:]) + "\n")
    if os.environ.get("FAKE_GATE_EXIT"):
        sys.exit(int(os.environ["FAKE_GATE_EXIT"]))
    os.execv(sys.executable, [sys.executable, REAL] + sys.argv[1:])
PY
AK="$FK/bin/agent-kit"

M="$TMP/main"; O="$TMP/origin.git"
newrepo() {   # main (nhánh main, theo dõi origin/main) + origin trần; ma trận một suite: bash check.sh
  rm -rf "$M" "$O" "$TMP/other"; : > "$INTEGRATE_GATE_LOG"
  mkdir -p "$M/.agents" && G "$M" init -q -b main . && G "$M" config user.email t@t && G "$M" config user.name t
  printf 'exit 0\n' > "$M/check.sh"
  printf '{"project":"t","rules":[{"component":"App","watch_files":["*.sh","*.txt"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"check","command":"bash check.sh"}]}]}\n' \
    > "$M/.agents/regression_matrix.active.json"
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/evidence/\n.agents/regression_journal/\n.claude/\n' > "$M/.gitignore"
  G "$M" add -A && G "$M" commit -qm base
  git init -q --bare "$O" && G "$M" remote add origin "$O" && G "$M" push -q -u origin main 2>/dev/null
  G "$M" config devkit.trunkMode true
}
work() { echo "$1" >> "$M/work.txt" && G "$M" add work.txt && G "$M" commit -qm "$1"; }   # một commit chưa push
origin_head() { git --git-dir="$O" rev-parse main; }
gate_runs() { [ -f "$INTEGRATE_GATE_LOG" ] && wc -l < "$INTEGRATE_GATE_LOG" | tr -d ' ' || echo 0; }
integrate() { (cd "$M" && env "$@" bash "$AK" integrate ${ARGS:-} > "$TMP/out" 2>&1); }
hold_test_lock() {   # giữ flock test_run.lock của main (một gate đang chạy): máy không rảnh
  mkdir -p "$M/.claude/audit-gate"
  python3 -c 'import fcntl,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(120)' \
    "$M/.claude/audit-gate/test_run.lock" "$TMP/held" & HOLDER=$!
  for _ in $(seq 50); do [ -f "$TMP/held" ] && break; sleep 0.1; done
}
release_test_lock() { [ -z "$HOLDER" ] || { kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null; }; HOLDER=""; rm -f "$TMP/held"; }

# I1 chưa tới hạn: 1 commit mới (< batchMax 6, < 60 phút), một gate đang giữ test_run.lock → không làm gì
newrepo; work a; o0="$(origin_head)"; hold_test_lock
ARGS="--if-due" integrate; rc=$?
[ "$rc" = 0 ] && [ "$(gate_runs)" = 0 ] && [ "$(origin_head)" = "$o0" ] && grep -qi "chưa tới hạn\|not due" "$TMP/out" \
  && ok "I1 chưa tới hạn: exit 0, không gate, không push" || fail "I1 chưa tới hạn: rc $rc, gate $(gate_runs), out: $(tail -3 "$TMP/out")"
release_test_lock

# I2 không có commit chờ: exit 0, không gate
newrepo
ARGS="" integrate; rc=$?
[ "$rc" = 0 ] && [ "$(gate_runs)" = 0 ] && grep -qi "không có commit nào chờ\|nothing to integrate" "$TMP/out" \
  && ok "I2 không có commit chờ: exit 0, không gate" || fail "I2: rc $rc, gate $(gate_runs), out: $(tail -3 "$TMP/out")"

# I3 tới hạn theo batchMax (=2) dù máy bận + gate xanh → push đúng HEAD, gate chạy 1 lần trong scratch (không ở main), scratch gỡ
# Scratch tên .integrate-scratch-* (batch_canary không đếm là merge gate lẻ); gate --full, không --force-full (không còn hoãn để cưỡng).
newrepo; G "$M" config devkit.integrate.batchMax 2; work a; work b; hold_test_lock
ARGS="--if-due" integrate; rc=$?
gate_cwd="$(head -1 "$INTEGRATE_GATE_LOG" 2>/dev/null | cut -d' ' -f1)"
[ "$rc" = 0 ] && [ "$(origin_head)" = "$(G "$M" rev-parse HEAD)" ] && [ "$(gate_runs)" = 1 ] \
  && [ -n "$gate_cwd" ] && [ "$gate_cwd" != "$M" ] && grep -q -- "--run-tests --full --brief --diff refs/remotes/origin/main" "$INTEGRATE_GATE_LOG" \
  && ! grep -q -- "--force-full" "$INTEGRATE_GATE_LOG" && case "$(basename "$gate_cwd")" in .integrate-scratch-*) true ;; *) false ;; esac \
  && [ ! -d "$gate_cwd" ] && [ "$(G "$M" worktree list | wc -l | tr -d ' ')" = 1 ] \
  && ok "I3 tới hạn (batchMax) + gate xanh: push đúng HEAD, 1 gate --full trong scratch, scratch đã gỡ" \
  || fail "I3: rc $rc, origin $(origin_head | cut -c1-8) HEAD $(G "$M" rev-parse --short HEAD), gate $(gate_runs) cwd '$gate_cwd', worktrees $(G "$M" worktree list | wc -l), out: $(tail -5 "$TMP/out")"
release_test_lock

# I4 gate đỏ: không push, in commit của đợt, exit 1, scratch gỡ
newrepo; work a; printf 'exit 1\n' > "$M/check.sh" && G "$M" commit -qam "break check"; o0="$(origin_head)"
ARGS="" integrate; rc=$?
[ "$rc" = 1 ] && [ "$(origin_head)" = "$o0" ] && [ "$(gate_runs)" = 1 ] && grep -q "gate ĐỎ (exit 1)" "$TMP/out" \
  && grep -q "break check" "$TMP/out" && grep -q " a$" "$TMP/out" \
  && [ "$(G "$M" worktree list | wc -l | tr -d ' ')" = 1 ] \
  && ok "I4 gate đỏ: không push, in các commit của đợt, exit 1, scratch gỡ" \
  || fail "I4: rc $rc, gate $(gate_runs), out: $(tail -6 "$TMP/out")"

# I5 origin phân kỳ (origin có commit main local chưa có): dừng, exit ≠ 0, không gate, không push
newrepo; work a
git clone -q -b main "$O" "$TMP/other" && echo x > "$TMP/other/x.txt" && G "$TMP/other" add x.txt && G "$TMP/other" commit -qm theirs && G "$TMP/other" push -q origin main 2>/dev/null
o0="$(origin_head)"
ARGS="" integrate; rc=$?
[ "$rc" != 0 ] && [ "$(gate_runs)" = 0 ] && [ "$(origin_head)" = "$o0" ] && grep -qi "phân kỳ\|diverge" "$TMP/out" \
  && ok "I5 origin phân kỳ: exit $rc, không gate, không push" || fail "I5: rc $rc, gate $(gate_runs), out: $(tail -3 "$TMP/out")"

# I6 khoá devkit-integrate.lock đang bị giữ: exit 0, không gate, không push
newrepo; work a; o0="$(origin_head)"
LOCK="$(G "$M" rev-parse --path-format=absolute --git-common-dir)/devkit-integrate.lock"
python3 -c 'import fcntl,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(120)' "$LOCK" "$TMP/held" & HOLDER=$!
for _ in $(seq 50); do [ -f "$TMP/held" ] && break; sleep 0.1; done
ARGS="" integrate; rc=$?
[ "$rc" = 0 ] && [ "$(gate_runs)" = 0 ] && [ "$(origin_head)" = "$o0" ] && grep -qi "bận\|busy" "$TMP/out" \
  && ok "I6 khoá bận: exit 0, không gate" || fail "I6: rc $rc, gate $(gate_runs), out: $(tail -3 "$TMP/out")"
release_test_lock

# I7 gate exit 0 mà không để lại biên nhận (gate giả): push_gate từ chối → không push, exit 1
newrepo; work a; o0="$(origin_head)"
ARGS="" integrate FAKE_GATE_EXIT=0; rc=$?
[ "$rc" = 1 ] && [ "$(gate_runs)" = 1 ] && [ "$(origin_head)" = "$o0" ] && grep -q "push_gate" "$TMP/out" \
  && ok "I7 gate exit 0 không biên nhận: push_gate từ chối, không push" || fail "I7: rc $rc, gate $(gate_runs), out: $(tail -3 "$TMP/out")"

# I7b gate bận (exit 4: hàng đợi gate / khoá dự án): không phải đỏ — exit 0, không push, không liệt kê đợt như lượt đỏ
newrepo; work a; o0="$(origin_head)"
ARGS="" integrate FAKE_GATE_EXIT=4; rc=$?
[ "$rc" = 0 ] && [ "$(gate_runs)" = 1 ] && [ "$(origin_head)" = "$o0" ] && grep -qi "bận\|busy" "$TMP/out" && ! grep -q "ĐỎ" "$TMP/out" \
  && ok "I7b gate bận: exit 0, không push, không báo đỏ" || fail "I7b: rc $rc, gate $(gate_runs), out: $(tail -3 "$TMP/out")"

# I8 --dry-run: tới hạn theo tuổi (commit 2 giờ trước) và theo máy rảnh; không gate, không push
newrepo; GIT_COMMITTER_DATE="$(date -u -v-2H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)" work old; o0="$(origin_head)"
hold_test_lock
ARGS="--if-due --dry-run" integrate; rc=$?
[ "$rc" = 0 ] && [ "$(gate_runs)" = 0 ] && [ "$(origin_head)" = "$o0" ] && grep -q "maxWaitMin" "$TMP/out" \
  && ok "I8a --dry-run tới hạn theo tuổi: không gate, không push" || fail "I8a: rc $rc, gate $(gate_runs), out: $(tail -3 "$TMP/out")"
release_test_lock
newrepo; work a; o0="$(origin_head)"
ARGS="--if-due --dry-run" integrate; rc=$?
[ "$rc" = 0 ] && [ "$(gate_runs)" = 0 ] && [ "$(origin_head)" = "$o0" ] && grep -qi "rảnh\|idle" "$TMP/out" \
  && ok "I8b --dry-run tới hạn vì máy rảnh: không gate, không push" || fail "I8b: rc $rc, gate $(gate_runs), out: $(tail -3 "$TMP/out")"

# I9 trunk mode: `agent-kit integrate` ở main được _TRUNK_ALLOWED cho qua; redirect của nó vào main vẫn bị chặn
python3 - "$DEVKIT_DIR" "$M" > "$TMP/unit" 2>&1 <<'PY'
import sys
dk, m = sys.argv[1:3]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
main, sw = sl.trunk_main(m)
assert main and sw, "trunk mode not seen"
bad = []
for want, cmd in [(True, "agent-kit integrate"), (True, "agent-kit integrate --if-due"), (True, "/x/bin/agent-kit integrate --dry-run"),
                  (True, "agent-kit wt list"), (True, "agent-kit worktree"), (False, "agent-kit integrated"), (False, "agent-kit gate")]:
    if bool(sl._TRUNK_ALLOWED.search(cmd)) != want:
        bad.append(f"_TRUNK_ALLOWED({cmd!r}) != {want}")
for want, cmd in [(False, "agent-kit integrate --if-due"), (True, "agent-kit integrate > README.md")]:
    if bool(sl.trunk_write("Bash", {"command": cmd}, cmd, m, main, sw)) != want:
        bad.append(f"trunk_write({cmd!r}) != {want}")
print("\n".join(bad) or "OK")
PY
[ "$(tail -1 "$TMP/unit")" = OK ] && ok "I9 _TRUNK_ALLOWED cho agent-kit integrate; redirect vào main vẫn chặn" || fail "I9: $(cat "$TMP/unit")"

# I11 (#463) hook bị git ignore mà settings.json đăng ký (.claude/hooks/guard-x.py): scratch phải có nó, như scratch của merge train
# (super-board-scratch-config.sh → copy_local_hooks). Suite duy nhất là `agent-kit health` trong scratch, chỉ đỏ vì đúng lý do
# "hook đăng ký nhưng thiếu file" (REG-WB-CONFIG-01); thiếu hook → gate đỏ, không push.
newrepo
printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/evidence/\n.agents/regression_journal/\n.claude/*\n!.claude/settings.json\n' > "$M/.gitignore"
mkdir -p "$M/.claude/hooks" && printf 'import sys\nsys.exit(0)\n' > "$M/.claude/hooks/guard-x.py"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"python3 \\"$CLAUDE_PROJECT_DIR\\"/.claude/hooks/guard-x.py"}]}]}}\n' > "$M/.claude/settings.json"
cat > "$M/check.sh" <<SH
out="\$(bash "$AK" health -t . 2>&1)"
if printf '%s\n' "\$out" | grep -q "registered hooks missing\|hook đăng ký nhưng thiếu file"; then
  printf '%s\n' "\$out" | grep -i "hook"; exit 1
fi
exit 0
SH
G "$M" add -A && G "$M" commit -qm "settings + health check" && G "$M" push -q origin main 2>/dev/null
G "$M" check-ignore -q .claude/hooks/guard-x.py && ! G "$M" check-ignore -q .claude/settings.json \
  && (cd "$M" && bash check.sh > "$TMP/h_main" 2>&1) \
  && ok "I11 tiền đề: hook ignored, settings tracked, health ở main không báo thiếu hook" || fail "I11 tiền đề: $(tail -3 "$TMP/h_main")"
work a
ARGS="" integrate; rc=$?
[ "$rc" = 0 ] && [ "$(origin_head)" = "$(G "$M" rev-parse HEAD)" ] && [ "$(gate_runs)" = 1 ] && ! grep -q "registered hooks missing\|thiếu file" "$TMP/out" \
  && ok "I11 hook ignored có trong scratch: health xanh, gate xanh, push" \
  || fail "I11 scratch thiếu hook ignored: rc $rc, gate $(gate_runs), out: $(grep -i "hook\|ĐỎ" "$TMP/out" | tail -6)"

# I12 (#477) cài DevKit vào scratch hỏng (profile lạ → install.sh exit 2): scratch thiếu kit nên gate chạy trên cây không đại diện cho HEAD;
# integrate phải báo lỗi cài, không chạy gate, không push (trước đây chỉ báo rồi vẫn gate + push).
newrepo
mkdir -p "$M/.agents" && printf '{"profile":"nonexistent-zzz"}\n' > "$M/.agents/active-profile.json"
G "$M" add -A && G "$M" commit -qm "profile lạ" && G "$M" push -q origin main 2>/dev/null
work a; o0="$(origin_head)"
ARGS="" integrate; rc=$?
[ "$rc" = 1 ] && [ "$(gate_runs)" = 0 ] && [ "$(origin_head)" = "$o0" ] && grep -q "cài DevKit vào scratch" "$TMP/out" \
  && [ "$(G "$M" worktree list | wc -l | tr -d ' ')" = 1 ] \
  && ok "I12 cài DevKit vào scratch hỏng: báo lỗi cài, không gate, không push, scratch gỡ" \
  || fail "I12: rc $rc, gate $(gate_runs), origin $(origin_head | cut -c1-8), out: $(tail -4 "$TMP/out")"

# I13 (#477) một chỗ định nghĩa danh sách copy_*: worktree.copy_ignored chép config + hook bị ignore; integrate.py và
# super-board-scratch-config.sh gọi nó, không liệt kê lại từng hàm copy_*.
mkdir -p "$TMP/c/m/.claude/hooks" "$TMP/c/w" && G "$TMP/c/m" init -q -b main . && printf 'local.properties\n.claude/hooks/\n' > "$TMP/c/m/.gitignore"
G "$TMP/c/m" add .gitignore && G "$TMP/c/m" commit -qm i && G "$TMP/c/m" worktree add -q --detach "$TMP/c/w/s" main
echo 'sdk.dir=/x' > "$TMP/c/m/local.properties"; printf 'import sys\n' > "$TMP/c/m/.claude/hooks/guard-y.py"
python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import worktree; worktree.copy_ignored(sys.argv[2], sys.argv[3])' \
  "$DEVKIT_DIR/scripts/git" "$TMP/c/m" "$TMP/c/w/s" > "$TMP/unit13" 2>&1
[ -f "$TMP/c/w/s/local.properties" ] && [ -f "$TMP/c/w/s/.claude/hooks/guard-y.py" ] \
  && ! grep -q "copy_local_hooks\|copy_build_inputs\|copy_unity_library" "$DEVKIT_DIR/scripts/git/integrate.py" "$DEVKIT_DIR/../.claude/bin/super-board-scratch-config.sh" \
  && ok "I13 worktree.copy_ignored là chỗ duy nhất liệt kê copy_*; integrate và merge train dùng chung" \
  || fail "I13: $(tail -3 "$TMP/unit13"); copy_*: $(grep -c "copy_local_hooks\|copy_build_inputs\|copy_unity_library" "$DEVKIT_DIR/scripts/git/integrate.py" "$DEVKIT_DIR/../.claude/bin/super-board-scratch-config.sh" | tr '\n' ' ')"

# I14 (#481) test đã có bị sửa, được duyệt theo tên ở main checkout (.claude/audit-gate/approved_tests.json): lời duyệt phải tới gate trong
# scratch (nó đọc approved_tests.json của PROJECT = scratch) mà không cần --auto-approve-tests / DEVKIT_AUTO_APPROVE_TESTS. Đối chứng: test
# sửa khác không được duyệt vẫn chặn (exit 2, không push); duyệt xong rồi sửa tiếp nội dung (dạng list gắn mtime) cũng vẫn chặn.
edited_test_repo() {   # newrepo + tests/t_a.sh, tests/t_b.sh đã có trên origin; một commit chưa push sửa cả hai
  newrepo; mkdir -p "$M/tests"; printf 'exit 0\n' > "$M/tests/t_a.sh"; printf 'exit 0\n' > "$M/tests/t_b.sh"
  G "$M" add -A && G "$M" commit -qm "tests" && G "$M" push -q origin main 2>/dev/null
  printf 'exit 0 # sửa\n' > "$M/tests/t_a.sh"; printf 'exit 0 # sửa\n' > "$M/tests/t_b.sh"
  G "$M" commit -qam "sửa test"
}
edited_test_repo; o0="$(origin_head)"
ARGS="" integrate DEVKIT_AUTO_APPROVE_TESTS=0; rc=$?
[ "$rc" != 0 ] && [ "$(origin_head)" = "$o0" ] \
  && ok "I14 tiền đề: test sửa chưa được duyệt → integrate dừng, không push" || fail "I14 tiền đề: rc $rc, out: $(tail -4 "$TMP/out")"
edited_test_repo; sleep 1; mkdir -p "$M/.claude/audit-gate"; printf '["tests/t_a.sh","tests/t_b.sh"]\n' > "$M/.claude/audit-gate/approved_tests.json"
ARGS="" integrate DEVKIT_AUTO_APPROVE_TESTS=0; rc=$?
[ "$rc" = 0 ] && [ "$(origin_head)" = "$(G "$M" rev-parse HEAD)" ] \
  && ok "I14 cả hai test sửa được duyệt theo tên ở main: integrate push, không cờ duyệt hàng loạt" || fail "I14 duyệt theo tên: rc $rc, out: $(tail -5 "$TMP/out")"
edited_test_repo; o0="$(origin_head)"; sleep 1; mkdir -p "$M/.claude/audit-gate"; printf '["tests/t_a.sh"]\n' > "$M/.claude/audit-gate/approved_tests.json"
ARGS="" integrate DEVKIT_AUTO_APPROVE_TESTS=0; rc=$?
[ "$rc" != 0 ] && [ "$(origin_head)" = "$o0" ] \
  && ok "I14 đối chứng: chỉ duyệt t_a, t_b sửa mà chưa duyệt vẫn chặn, không push" || fail "I14 đối chứng: rc $rc, out: $(tail -4 "$TMP/out")"
edited_test_repo; o0="$(origin_head)"; sleep 1; mkdir -p "$M/.claude/audit-gate"; printf '["tests/t_a.sh","tests/t_b.sh"]\n' > "$M/.claude/audit-gate/approved_tests.json"
sleep 1; printf 'exit 0 # sửa lần hai\n' > "$M/tests/t_b.sh"; G "$M" commit -qam "sửa tiếp sau khi duyệt"
ARGS="" integrate DEVKIT_AUTO_APPROVE_TESTS=0; rc=$?
[ "$rc" != 0 ] && [ "$(origin_head)" = "$o0" ] \
  && ok "I14 đối chứng: test sửa tiếp SAU lời duyệt không được chép sang scratch, vẫn chặn" || fail "I14 sửa sau duyệt: rc $rc, out: $(tail -4 "$TMP/out")"

# I10 help + completion
bash "$AK" help | grep -q "integrate \[--if-due\] \[--dry-run\]" && bash "$AK" completion bash | grep -q "integrate" \
  && ok "I10 help và completion có integrate" || fail "I10 help/completion thiếu integrate"

[ "$FAILS" = 0 ] && echo "ALL OK" && exit 0
echo "$FAILS FAILED"; exit 1
