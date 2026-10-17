#!/usr/bin/env bash
# Trunk mode (bin/session_lock.py), lỗi K9 đo thật 17/10: ở main checkout, lệnh chỉ ĐỌC bị chặn như một lần ghi.
# - `pgrep -fl "post-fix-gate" | head -3`: GATE khớp tên gate trong đối số của pgrep, _gate_run không coi pgrep là lệnh đọc -> "chạy gate ở main".
# - `git -C $w log … -- …/post-fix-gate.py` (đích là biến): _gate_run chỉ xem chữ ngay sau `git` có phải verb đọc không, gặp `-C` thì coi là
#   chạy gate. git -C <dir> <verb đọc> là lệnh đọc. (Vòng lặp `git -C $w log` không nhắc tên gate thì vốn đã qua: các ca dưới giữ điều đó.)
# Vẫn bị chặn: chạy gate thật ở main, `git -C $W commit` khi không biết $W ở đâu, `echo x > $F`.
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
echo a > "$M/file" && echo 'print(1)' > "$M/bin/post-fix-gate.py" && git -C "$M" add -A && git -C "$M" commit -qm i
git -C "$M" worktree add -q --detach "$W" HEAD
git -C "$M" config devkit.trunkMode true

# 1 unit: trunk_write ở main (cwd = main)
python3 - "$DEVKIT_DIR" "$M" > "$TMP/unit" 2>&1 <<'PY'
import sys
dk, m = sys.argv[1:3]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
main, sw = sl.trunk_main(m)
assert main and sw, "trunk mode not seen"
cases = [   # (want, command) - True: một lần ghi vào main (bị chặn)
    (False, 'pgrep -fl "post-fix-gate" | head -3'),
    (False, "pgrep -fl post-fix-gate"),
    (False, "grep -n post-fix-gate file"),
    (False, "git -C $W log --oneline -1"),
    (False, "git -C $W status --short"),
    (False, "git -C $W show --stat HEAD"),
    (False, "git -C $W diff HEAD~1"),
    (False, "git -C $W rev-parse HEAD"),
    (False, "git -C $W rev-list --count HEAD"),
    (False, "git -C $W branch --list"),
    (False, "git -C $W worktree list"),
    (False, "for a in x y; do w=.claude/worktrees/$a; git -C $w log --oneline -1; done"),
    (False, "git log --oneline -3"),
    (False, 'for a in x y; do w=.claude/worktrees/$a; git -C "$w" log --oneline -1; done'),
    (False, "for a in x y; do\n  w=.claude/worktrees/$a\n  git -C $w log --oneline -1\ndone"),
    (False, 'for a in s1; do w=.claude/worktrees/$a; echo "== $a"; git -C $w log --oneline -1; git -C $w status --short | head -5; done 2>&1'),
    (False, 'for w in .claude/worktrees/*; do git -C "$w" log --oneline -1 2>/dev/null; done'),
    (False, "W=.claude/worktrees/s1; git -C $W log --oneline main..HEAD; git -C $W diff --stat main"),
    (False, "for a in s1; do w=$PWD/.claude/worktrees/$a; git -C $w log --oneline -1; done"),
    (False, "git -C $W log --oneline -1 -- bin/post-fix-gate.py"),   # tên gate trong đối số của git -C <biến> <verb đọc>
    (False, "git -C $W log --grep=post-fix-gate -1"),
    (False, "for a in s1; do w=.claude/worktrees/$a; git -C $w log --oneline -1 -- bin/post-fix-gate.py; done"),
    (False, "git -C $W --no-pager show --stat HEAD -- bin/post-fix-gate.py"),
    (False, "git -C $W branch --list post-fix-gate"),
    (False, "git -C $W worktree list | grep post-fix-gate"),
    (True, "python3 .agents/devkit/bin/post-fix-gate.py --run-tests"),
    (True, "bash bin/post-fix-gate.py"),
    (True, "bin/post-fix-gate.py --run-tests"),
    (True, "timeout 600 python3 bin/post-fix-gate.py --run-tests"),   # lớp bọc lạ: vẫn coi là chạy gate (fail closed)
    (True, "pgrep x; python3 bin/post-fix-gate.py"),
    (True, "git -c core.pager=bin/post-fix-gate.py -C $W log"),   # -c chạy được lệnh (pager): không miễn
    (True, "git -C $W worktree add ../post-fix-gate"),   # worktree không phải list: không miễn như lệnh đọc
    (True, "git -C $W commit -m x"),
    (True, "git -C $W status > out.txt"),
    (True, "echo x > $F"),
    (True, "git commit -m x"),
]
bad = 0
for want, cmd in cases:
    got = sl.trunk_write("Bash", {"command": cmd}, cmd, m, main, sw, "s")
    if got != want:
        bad += 1
        print(f"✖ {cmd!r}: want {want}, got {got}")
print(f"unit-bad={bad} of {len(cases)}")
PY
grep -q "unit-bad=0 " "$TMP/unit" && ok "trunk_write: $(grep -o 'of [0-9]*' "$TMP/unit") ca (lệnh đọc qua, ghi / chạy gate ở main vẫn chặn)" \
  || { fail "trunk_write read cases"; grep "✖\|Error\|assert" "$TMP/unit" | head -30; }

# 2 hook thật (PreToolUse) ở main
hook() {   # hook <cwd> <command>: exit code của hook; stderr ở $TMP/err
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","session_id":"sess-a","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$1" "$2" \
    | python3 -I "$SL" 2> "$TMP/err"
}
hook "$M" 'pgrep -fl "post-fix-gate" | head -3'; r1=$?
hook "$M" 'for a in s1; do w=.claude/worktrees/$a; git -C $w log --oneline -1; done'; r2=$?
hook "$M" 'for a in s1; do w=.claude/worktrees/$a; git -C $w log --oneline -1 -- bin/post-fix-gate.py; done'; r2b=$?
[ "$r1" = 0 ] && [ "$r2" = 0 ] && [ "$r2b" = 0 ] && ok "hook: pgrep tên gate, git -C \$w log (cả khi nhắc tên gate) ở main -> exit 0" \
  || fail "hook allowed cases: $r1 $r2 $r2b $(head -c 300 "$TMP/err")"
hook "$M" "python3 bin/post-fix-gate.py --run-tests"; r3=$?
hook "$M" 'git -C $W commit -m x'; r4=$?
hook "$M" 'echo x > $F'; r5=$?
[ "$r3" = 2 ] && [ "$r4" = 2 ] && [ "$r5" = 2 ] && grep -q "Trunk mode" "$TMP/err" && ok "hook: chạy gate, git -C \$W commit, echo > \$F ở main -> exit 2 (Trunk mode)" \
  || fail "hook blocked cases: $r3 $r4 $r5 $(head -c 300 "$TMP/err")"

[ "$FAILS" -eq 0 ] && echo "✅ test_session_lock_trunk_reads: all passed" || { echo "❌ test_session_lock_trunk_reads: $FAILS failed"; exit 1; }
