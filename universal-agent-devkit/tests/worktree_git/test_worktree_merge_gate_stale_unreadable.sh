#!/usr/bin/env bash
# #831: `worktree finish` không fast-forward main khi gate trả exit 4 có suite nhãn STALE (PASS dùng lại đã mất
# hiệu lực, chưa kiểm lại), hoặc exit 2 có danh sách `unreadable` (FIFO, socket, file biến mất lúc quét).
# Hai đường vẫn gộp như cũ: exit 4 chỉ vì thiếu thiết bị, và exit 2 no_match (không file code nào khớp test).
# Gate là stub in JSON theo FAKE_GATE_JSON; mỗi ca một repo fixture trong mktemp, không đụng repo thật.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export GIT_CONFIG_GLOBAL=/dev/null
export DEVKIT_LANG=en

repo() {
  local p="$TMP/$1"; mkdir -p "$p/.agents" && G "$p" init -q -b main . && G "$p" config user.email t@t && G "$p" config user.name t
  printf 'greet() { echo ok; }\n' > "$p/lib.sh"
  printf '. ./lib.sh\ngreet\n' > "$p/app.sh"
  printf 'echo "all apps ok"\n' > "$p/check.sh"
  printf '{"project":"t","rules":[{"component":"App","watch_files":["*.sh"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"every app prints ok","command":"bash check.sh"}]}]}\n' \
    > "$p/.agents/regression_matrix.active.json"
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.claude/\n' > "$p/.gitignore"
  G "$p" add -A && G "$p" commit -qm base
}
wtadd() { (cd "$TMP/$1" && python3 "$WT" add "$TMP/$1-$2" --no-init >/dev/null 2>&1) || fail "setup: worktree add $1-$2"; }
ahead() { printf '. ./lib.sh\ngreet\n' > "$TMP/$1-$2/app2.sh" && G "$TMP/$1-$2" add app2.sh && G "$TMP/$1-$2" commit -qm "app2 calls greet"; }

# Kit giả: bin/post-fix-gate.py là stub, scripts/ trỏ về worktree.py thật (DEVKIT của nó = $FK)
FK="$TMP/kit"; mkdir -p "$FK/bin" "$FK/profiles" && ln -s "$DEVKIT_DIR/scripts" "$FK/scripts"
printf '%s\n' 'import os, sys' 'if __name__ == "__main__":' '    print("some output")' \
  '    print(os.environ.get("FAKE_GATE_JSON", "null"))' '    sys.exit(int(os.environ.get("FAKE_GATE_CODE", "0")))' \
  > "$FK/bin/post-fix-gate.py"

fin() { # fin <repo> ; FAKE_GATE_CODE và FAKE_GATE_JSON do ca gọi đặt
  (cd "$TMP/$1" && python3 "$FK/scripts/git/worktree.py" finish "$TMP/$1-w" > "$TMP/out" 2>&1)
}
# mỗi ca một repo mới: finish qua được thì worktree bị gỡ
prepare() { repo "$1"; wtadd "$1" w; ahead "$1" w; }
same() { [ "$(G "$TMP/$1" rev-parse HEAD)" = "$2" ] && echo yes || echo no; }
crash() { grep -q "Traceback" "$TMP/out"; }   # stub không bao giờ ném: Traceback là worktree.py sập (sập = cho qua)

# 1 exit 4, suite duy nhất UNTESTED nhãn STALE, busy=false: từ chối, main giữ nguyên. Gate thật hiện cũng đặt busy=true khi có
#   STALE (post-fix-gate.py _gate_busy) nên đã bị chặn ở bước busy; ca này giữ cho _untested_for_device tự đúng (phòng thủ thêm)
prepare a; before="$(G "$TMP/a" rev-parse HEAD)"
FAKE_GATE_CODE=4 FAKE_GATE_JSON='{"busy":false,"regression_tests":[{"id":"REG-APP-01","status":"UNTESTED","label":"STALE"}]}' fin a; rc=$?
if [ "$rc" = 1 ] && [ "$(same a "$before")" = yes ] && [ ! -f "$TMP/a/app2.sh" ] && [ -d "$TMP/a-w" ] \
    && grep -q "exit 4" "$TMP/out" && ! crash; then
  ok "exit 4 STALE only: refused, main unmoved, worktree kept"
else
  fail "exit 4 STALE only: rc=$rc main_same=$(same a "$before") $(tail -3 "$TMP/out")"
fi

# 1b exit 4, STALE lẫn một suite thiếu thiết bị: STALE vẫn chặn
prepare a2; before="$(G "$TMP/a2" rev-parse HEAD)"
FAKE_GATE_CODE=4 FAKE_GATE_JSON='{"busy":false,"regression_tests":[{"id":"REG-DEV-01","status":"UNTESTED","label":"missing_tool"},{"id":"REG-APP-01","status":"UNTESTED","label":"STALE"}]}' fin a2; rc=$?
if [ "$rc" = 1 ] && [ "$(same a2 "$before")" = yes ] && [ ! -f "$TMP/a2/app2.sh" ] && [ -d "$TMP/a2-w" ] && ! crash; then
  ok "exit 4 STALE + missing device: refused, main unmoved"
else
  fail "exit 4 STALE + missing device: rc=$rc main_same=$(same a2 "$before") $(tail -3 "$TMP/out")"
fi

# 2 exit 4 chỉ vì thiếu thiết bị (UNTESTED, nhãn không thuộc SLOT/BUSY/BUDGET/STALE): vẫn gộp
prepare b
FAKE_GATE_CODE=4 FAKE_GATE_JSON='{"busy":false,"regression_tests":[{"id":"REG-APP-01","status":"PASS"},{"id":"REG-DEV-01","status":"UNTESTED","label":"missing_tool"}]}' fin b; rc=$?
if [ "$rc" = 0 ] && [ -f "$TMP/b/app2.sh" ] && [ ! -d "$TMP/b-w" ]; then
  ok "exit 4 missing device: merged"
else
  fail "exit 4 missing device: rc=$rc $(tail -3 "$TMP/out")"
fi

# 3 exit 2, suite PASS nhưng một file không đọc được để quét (FIFO): từ chối, nêu tên file (tiếng Anh)
prepare c; before="$(G "$TMP/c" rev-parse HEAD)"
FAKE_GATE_CODE=2 FAKE_GATE_JSON='{"regression_tests":[{"id":"REG-APP-01","status":"PASS"}],"unreadable":["pipe.fifo"]}' fin c; rc=$?
if [ "$rc" = 1 ] && [ "$(same c "$before")" = yes ] && [ ! -f "$TMP/c/app2.sh" ] && [ -d "$TMP/c-w" ] \
    && grep -q "pipe.fifo" "$TMP/out" && grep -q "could not be read" "$TMP/out" && ! crash; then
  ok "exit 2 unreadable: refused, main unmoved, the file is named (en)"
else
  fail "exit 2 unreadable (en): rc=$rc main_same=$(same c "$before") $(tail -3 "$TMP/out")"
fi

# 3b cùng ca, DEVKIT_LANG=vi: thông báo tiếng Việt (tr song ngữ)
prepare c2; before="$(G "$TMP/c2" rev-parse HEAD)"
DEVKIT_LANG=vi FAKE_GATE_CODE=2 FAKE_GATE_JSON='{"regression_tests":[{"id":"REG-APP-01","status":"PASS"}],"unreadable":["sock.s"]}' fin c2; rc=$?
if [ "$rc" = 1 ] && [ "$(same c2 "$before")" = yes ] && [ ! -f "$TMP/c2/app2.sh" ] \
    && grep -q "sock.s" "$TMP/out" && grep -q "không đọc được" "$TMP/out" && ! crash; then
  ok "exit 2 unreadable: refused, the file is named (vi)"
else
  fail "exit 2 unreadable (vi): rc=$rc main_same=$(same c2 "$before") $(tail -3 "$TMP/out")"
fi

# 4 exit 2 no_match (không test, không file chưa có test, unreadable rỗng): vẫn gộp như test_worktree_trunk_merge ca 5
prepare d
FAKE_GATE_CODE=2 FAKE_GATE_JSON='{"regression_tests":[],"unreadable":[],"tests_touched":[],"uncovered":[],"orphan_tests":[],"matrix_problem":null}' fin d; rc=$?
if [ "$rc" = 0 ] && [ -f "$TMP/d/app2.sh" ] && [ ! -d "$TMP/d-w" ]; then
  ok "exit 2 no_match: merged"
else
  fail "exit 2 no_match: rc=$rc $(tail -3 "$TMP/out")"
fi

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_merge_gate_stale_unreadable: PASS"; exit 0; }
echo "test_worktree_merge_gate_stale_unreadable: FAIL ($FAILS)"; exit 1
