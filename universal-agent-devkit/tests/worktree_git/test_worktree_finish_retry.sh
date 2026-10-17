#!/usr/bin/env bash
# 17/10 (audit 20 phiên song song): `worktree finish` bỏ cuộc (exit 1) sau 3 vòng "main đi tiếp" dù chạy lại là xong — khi nhiều phiên gộp
# cùng lúc, mỗi phiên phải tự chạy lại bằng tay. Nay finish tự chạy lại (WORKTREE_FINISH_RETRIES, mặc định 4, chờ có jitter); gate không đổi.
#   1 main đi tiếp trong 3 lần gate đầu: finish vẫn xong (lần chạy lại thứ 2)   2 WORKTREE_FINISH_RETRIES=0: vẫn bỏ cuộc sau 3 vòng như cũ
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export GIT_CONFIG_GLOBAL=/dev/null

repo() {
  local p="$TMP/$1"; mkdir -p "$p/.agents" && G "$p" init -q -b main . && G "$p" config user.email t@t && G "$p" config user.name t
  printf 'echo ok\n' > "$p/app.sh"
  printf '[ -n "${DURING_GATE:-}" ] && bash "$DURING_GATE"\necho "all apps ok"\n' > "$p/check.sh"
  printf '{"project":"t","rules":[{"component":"App","watch_files":["*.sh"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"check","command":"bash check.sh"}]}]}\n' \
    > "$p/.agents/regression_matrix.active.json"
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/evidence/\n.agents/regression_journal/\n.claude/\n' > "$p/.gitignore"
  G "$p" add -A && G "$p" commit -qm base
}
# main commits a new watched file during each of the first $2 gates
mover() { printf 'n=$(cat "%s/n" 2>/dev/null || echo 0); [ "$n" -ge %s ] && exit 0; n=$((n + 1)); echo $n > "%s/n"; echo $n > "%s/%s/m$n.sh"; git -C "%s/%s" -c user.email=t@t -c user.name=t add "m$n.sh"; git -C "%s/%s" -c user.email=t@t -c user.name=t commit -qm "main moves"\n' \
  "$TMP" "$2" "$TMP" "$TMP" "$1" "$TMP" "$1" "$TMP" "$1" > "$TMP/mover-$1.sh"; }
try() {   # try <repo> <retries>
  (cd "$TMP/$1" && python3 "$WT" add "$TMP/$1-w" --no-init >/dev/null 2>&1) || fail "setup add $1"
  echo x > "$TMP/$1-w/app2.sh" && G "$TMP/$1-w" add app2.sh && G "$TMP/$1-w" commit -qm "work"
  rm -f "$TMP/n"; mover "$1" 4
  (cd "$TMP/$1" && env DURING_GATE="$TMP/mover-$1.sh" WORKTREE_FINISH_RETRIES="$2" WORKTREE_FINISH_RETRY_WAIT_S=0.2 python3 "$WT" finish "$TMP/$1-w" > "$TMP/out" 2>&1)
}

repo a; try a 4; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/a/app2.sh" ] && [ ! -d "$TMP/a-w" ] && ok "1 main moved during 4 gates: finish retried by itself and merged" || fail "1 rc=$rc $(tail -3 "$TMP/out")"
repo b; try b 0; rc=$?
[ "$rc" = 1 ] && [ ! -f "$TMP/b/app2.sh" ] && [ -d "$TMP/b-w" ] && ok "2 WORKTREE_FINISH_RETRIES=0: refused after 3 rounds as before" || fail "2 rc=$rc $(tail -3 "$TMP/out")"
[ "$FAILS" = 0 ]
