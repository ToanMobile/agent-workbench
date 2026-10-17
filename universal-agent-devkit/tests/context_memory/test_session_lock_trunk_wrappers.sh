#!/usr/bin/env bash
# Trunk mode (bin/session_lock.py): lớp bọc `nohup …`, `time …`, `bash -c '<một lệnh>'` quanh lệnh được phép ở main, và `sed` chỉ đọc.
# Lỗi đo thật 17/10 ở GeelyEx2 và Goods: `nohup agent-kit worktree finish <wt> > log 2>&1 &` (chạy nền một lần finish 5–10 phút), `time …` và
# `nohup bash -c '…finish…'` bị chặn vì _TRUNK_ALLOWED chỉ khớp khi segment MỞ ĐẦU bằng agent-kit; `sed -n 3260,3300p …/post-fix-gate.py` bị
# chặn vì GATE khớp tên file và _gate_run không coi sed là lệnh đọc. Gỡ lớp bọc rồi xét lệnh bên trong theo luật cũ; mọi ghi vào main vẫn bị chặn.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_ALLOW_SHARED_CHECKOUT
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SL="$DEVKIT_DIR/bin/session_lock.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
M="$TMP/main"; W="$M/.claude/worktrees/s1"
mkdir -p "$M/bin" && git -C "$M" init -q -b main && git -C "$M" config user.email t@t && git -C "$M" config user.name t
printf '/.claude/worktrees/\n' > "$M/.gitignore"
echo a > "$M/file" && echo r > "$M/README.md" && echo 'print(1)' > "$M/bin/post-fix-gate.py" && git -C "$M" add -A && git -C "$M" commit -qm i
git -C "$M" worktree add -q --detach "$W" HEAD
git -C "$M" config devkit.trunkMode true

# 1 unit: trunk_write với lớp bọc và sed
python3 - "$DEVKIT_DIR" "$M" "$W" "$TMP" > "$TMP/unit" 2>&1 <<'PY'
import sys
dk, m, w, tmp = sys.argv[1:5]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
main, sw = sl.trunk_main(m)
assert main and sw, "trunk mode not seen"
g = f"{m}/bin/post-fix-gate.py"
cases = [   # (want, label, cwd, command) - True: một lần ghi vào main (bị chặn)
    (False, "cd main && nohup finish > log 2>&1 & (từ main)", m, f"cd {m} && nohup agent-kit worktree finish {w} > {tmp}/x.log 2>&1 &"),
    (False, "cd main && nohup finish > log 2>&1 & (từ worktree)", w, f"cd {m} && nohup agent-kit worktree finish {w} > {tmp}/x.log 2>&1 &"),
    (False, "time agent-kit worktree finish", m, f"time agent-kit worktree finish {w}"),
    (False, "time -p agent-kit worktree finish", m, f"time -p agent-kit worktree finish {w}"),
    (False, "nohup bash -c 'agent-kit worktree finish'", m, f"nohup bash -c 'agent-kit worktree finish {w}'"),
    (False, "nohup bash -c '…finish…' > log 2>&1 &", m, f"nohup bash -c 'agent-kit worktree finish {w}' > {tmp}/x.log 2>&1 &"),
    (False, "time git push origin main (sync)", m, "time git push origin main"),
    (False, "sed -n 1,5p <main>/file", m, f"sed -n 1,5p {m}/file"),
    (False, "sed -n 1,5p <main>/bin/post-fix-gate.py (đọc file của gate)", m, f"sed -n 1,5p {g}"),
    (False, "sed -n 3260,3300p bin/post-fix-gate.py (tương đối, ở main)", m, "sed -n 3260,3300p bin/post-fix-gate.py"),
    (True, "nohup bash -c 'echo x > <main>/file'", m, f"nohup bash -c 'echo x > {m}/file'"),
    (True, "time git commit -m x ở main", m, "time git commit -m x"),
    (True, "sed -i s/a/b/ <main>/file", m, f"sed -i s/a/b/ {m}/file"),
    (True, "sed -i trên file của gate", m, f"sed -i s/a/b/ {g}"),
    (True, "sed -ni trên file của gate", m, f"sed -ni s/a/b/ {g}"),
    (True, "sed --in-place=.bak trên file của gate", m, f"sed --in-place=.bak s/a/b/ {g}"),
    (True, "bash -c '<finish> && git commit' (nhiều lệnh)", m, f"nohup bash -c 'agent-kit worktree finish {w} && git commit -qm x'"),
    (True, "bash -c '<finish>; echo x > README.md'", m, f"nohup bash -c 'agent-kit worktree finish {w}; echo x > README.md'"),
    (True, "bash -c '<finish> $(git commit)' (substitution trong nháy đơn)", m, f"nohup bash -c 'agent-kit worktree finish $(git commit -qm x)'"),
    (True, "nohup git fetch -u . HEAD:main", m, "nohup git fetch -u . HEAD:main"),
    (True, "bash -c 'git fetch . HEAD:main --update-head-ok'", w, "bash -c 'git fetch . HEAD:main --update-head-ok'"),
    (True, "time git pull --no-rebase origin main", m, "time git pull --no-rebase origin main"),
    (True, "nohup agent-kit worktree list > README.md", m, "nohup agent-kit worktree list > README.md"),
    (True, "nohup bash -c '<finish>' > README.md", m, f"nohup bash -c 'agent-kit worktree finish {w}' > README.md"),
    (True, "time python3 bin/post-fix-gate.py (chạy gate ở main)", m, "time python3 bin/post-fix-gate.py --run-tests"),
]
bad = 0
for want, label, cwd, cmd in cases:
    got = sl.trunk_write("Bash", {"command": cmd}, cmd, cwd, main, sw, "s")
    if got != want:
        bad += 1
        print(f"✖ {label}: want {want}, got {got}")
for want, cmd in ((False, "sed -n 1,5p bin/post-fix-gate.py"), (True, "sed -i s/a/b/ bin/post-fix-gate.py"), (True, "sed -Ei s/a/b/ bin/post-fix-gate.py")):
    if sl._gate_run(cmd) != want:   # luật khoá thường (bash_collides) cũng dùng _gate_run
        bad += 1
        print(f"✖ _gate_run({cmd!r}): want {want}")
print(f"unit-bad={bad} of {len(cases) + 3}")
PY
grep -q "unit-bad=0 " "$TMP/unit" && ok "trunk_write + _gate_run: $(grep -o 'of [0-9]*' "$TMP/unit") ca (lớp bọc được gỡ, ghi vào main vẫn bị chặn)" \
  || { fail "trunk_write wrapper cases"; grep "✖\|Error\|assert" "$TMP/unit" | head -30; }

# 2 hook thật (PreToolUse): exit 0 cho finish chạy nền và sed -n, exit 2 cho commit có time
hook() {   # hook <cwd> <command>: exit code của hook; stderr ở $TMP/err
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","session_id":"sess-a","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$1" "$2" \
    | python3 -I "$SL" 2> "$TMP/err"
}
hook "$M" "cd $M && nohup agent-kit worktree finish $W > $TMP/x.log 2>&1 &"; r1=$?
hook "$M" "nohup bash -c 'agent-kit worktree finish $W' > $TMP/x.log 2>&1 &"; r2=$?
hook "$M" "sed -n 1,5p $M/bin/post-fix-gate.py"; r3=$?
[ "$r1" = 0 ] && [ "$r2" = 0 ] && [ "$r3" = 0 ] && ok "hook: nohup finish nền, nohup bash -c finish, sed -n file gate ở main -> exit 0" \
  || fail "hook allowed cases: $r1 $r2 $r3 $(head -c 200 "$TMP/err")"
hook "$M" "time git commit -m x"; r4=$?
hook "$M" "nohup bash -c 'echo x > $M/file'"; r5=$?
[ "$r4" = 2 ] && [ "$r5" = 2 ] && grep -q "Trunk mode" "$TMP/err" && ok "hook: time git commit, nohup bash -c 'echo > main' -> exit 2 (Trunk mode)" \
  || fail "hook blocked cases: $r4 $r5 $(head -c 200 "$TMP/err")"

[ "$FAILS" -eq 0 ] && echo "✅ test_session_lock_trunk_wrappers: all passed" || { echo "❌ test_session_lock_trunk_wrappers: $FAILS failed"; exit 1; }
