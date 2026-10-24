#!/usr/bin/env bash
# Test (#229, gap 4 của #226): runner chạy dài tự nạp lại code mới khi super-board-run.sh trên origin/<base> đổi.
#  - rảnh (không worker) + origin có bản script khác bản đang chạy + main fast-forward được → ff rồi exec lại chính nó;
#  - main có commit local không đụng runner (#308) → gộp origin qua đường finish (stub: git merge) rồi exec; gộp xung đột/hỏng → notify một lần cho mỗi bản origin, KHÔNG exec;
#  - bản mới sai cú pháp → notify, không exec; còn worker → không đụng gì; origin cùng bản đang chạy → im lặng.
# Chạy offline: runner source ở lib mode, git origin là repo bare trong thư mục tạm, exec/notify/log là stub. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-self-reload.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
log() { echo "$*" >> "$TMP/log"; }
board_notify() { echo "$*" >> "$TMP/notify"; }
reload_exec() { echo "$1" >> "$TMP/exec"; }
runner_state_write() { :; }
reload_finish_main() {   # stub của worktree finish: gộp origin vào main, xung đột thì trả lại nguyên trạng và khác 0
  echo x >> "$TMP/finish"; git merge -q --no-edit "origin/${BASE_BRANCH}" >/dev/null 2>&1 || { git merge --abort >/dev/null 2>&1; return 3; }
}
CONFIG_SLUG="board"; BASE_BRANCH="main"; ACTIVE_WORKERS=0; SB_RELOAD_EVERY=0

REL=".claude/bin/super-board-run.sh"
CASE=0
mkrepo() {   # mỗi ca một thư mục riêng: origin bare + repo (checkout đang chạy) + other (nơi đẩy bản mới), cùng lịch sử v1
  CASE=$((CASE + 1)); C="$TMP/c$CASE"; mkdir -p "$C"
  git init -q --bare -b main "$C/origin.git"
  git clone -q "$C/origin.git" "$C/repo" 2>/dev/null
  ( cd "$C/repo" && mkdir -p .claude/bin && printf '#!/usr/bin/env bash\necho v1\n' > "$REL" \
    && echo base > other.txt && git add -A && git commit -qm v1 && git push -q origin HEAD:main 2>/dev/null )
  git clone -q "$C/origin.git" "$C/other" 2>/dev/null
  : > "$TMP/log"; : > "$TMP/notify"; : > "$TMP/exec"
  cd "$C/repo" || exit 1
  RELOAD_SELF="$C/repo/$REL"; RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF"); RELOAD_WARNED=""; RELOAD_NEXT_CHECK=0; ACTIVE_WORKERS=0
}
push_other() {   # push_other <nội dung script>: đẩy bản mới của script lên origin từ clone khác
  ( cd "$C/other" && git pull -q origin main 2>/dev/null; printf '%s\n' "$1" > "$REL" && git add -A && git commit -qm next && git push -q origin HEAD:main 2>/dev/null )
}
execs() { wc -l < "$TMP/exec" | tr -d ' '; }
notes() { wc -l < "$TMP/notify" | tr -d ' '; }

# ── 1. origin cùng bản đang chạy: im lặng, không exec, không notify
mkrepo; self_reload_tick
[ "$(execs)" = 0 ] && [ "$(notes)" = 0 ] && ok "origin has the running script: no exec, no notice" || fail "unchanged origin: exec=$(execs) notify=$(notes)"

# ── 2. origin có bản mới, main sạch và đứng sau origin: ff rồi exec đúng file đó
mkrepo; push_other $'#!/usr/bin/env bash\necho v2'; self_reload_tick
[ "$(execs)" = 1 ] && [ "$(cat "$TMP/exec")" = "$RELOAD_SELF" ] && ok "new script on origin, main fast-forwardable: exec'd itself" || fail "exec=$(execs) ($(cat "$TMP/exec"))"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && grep -q v2 "$RELOAD_SELF" && ok "  … main checkout was fast-forwarded to origin first" || fail "HEAD not at origin/main or file not v2"

# ── 3. (#379) còn worker sống: vẫn nạp bản mới (exec giữ PID, runner mới adopt lại worker), không chờ tới lúc rảnh
mkrepo; push_other $'#!/usr/bin/env bash\necho v2'; ACTIVE_WORKERS=2; self_reload_tick
[ "$(execs)" = 1 ] && [ "$(cat "$TMP/exec")" = "$RELOAD_SELF" ] && grep -q v2 "$RELOAD_SELF" && ok "workers alive: still reloads the new script (adopt picks them up)" || fail "busy: exec=$(execs)"

# ── 4. main có commit local KHÔNG đụng runner (#308): gộp origin qua finish rồi exec, commit local còn nguyên
mkrepo; ( cd "$C/repo" && echo local >> other.txt && git commit -qam local ); : > "$TMP/finish"
push_other $'#!/usr/bin/env bash\necho v2'; self_reload_tick
[ "$(execs)" = 1 ] && [ "$(cat "$TMP/exec")" = "$RELOAD_SELF" ] && grep -q v2 "$RELOAD_SELF" && ok "main has a local commit, origin changed the runner: merged through finish and exec'd" || fail "diverged-clean: exec=$(execs)"
[ "$(wc -l < "$TMP/finish" | tr -d ' ')" = 1 ] && git log --format=%s | grep -qx local && [ "$(notes)" = 0 ] && ok "  … local commit kept, finish used once, no notice" || fail "diverged-clean: finish/local/notice wrong"

# ── 4b. gộp xung đột (commit local cũng sửa runner): giữ code cũ, notify MỘT lần cho hai tick, HEAD giữ nguyên; bản origin mới → notify lại
mkrepo; ( cd "$C/repo" && echo '# local' >> "$REL" && git commit -qam local-runner ); before=$(git rev-parse HEAD); RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF")
push_other $'#!/usr/bin/env bash\necho v2'; self_reload_tick; self_reload_tick
[ "$(execs)" = 0 ] && [ "$(git rev-parse HEAD)" = "$before" ] && ok "conflicting merge: no blind restart, HEAD untouched" || fail "conflict: exec=$(execs)"
[ "$(notes)" = 1 ] && ok "  … one notice for two ticks on the same origin version" || fail "notices: $(notes)"
push_other $'#!/usr/bin/env bash\necho v3'; self_reload_tick
[ "$(notes)" = 2 ] && ok "  … a newer origin version notifies again" || fail "notices after v3: $(notes)"

# ── 4c. main checkout đang ở nhánh khác: không gộp, notify, không exec
mkrepo; ( cd "$C/repo" && git checkout -q -b other-branch ); : > "$TMP/finish"
push_other $'#!/usr/bin/env bash\necho v2'; self_reload_tick
[ "$(execs)" = 0 ] && [ "$(wc -l < "$TMP/finish" | tr -d ' ')" = 0 ] && [ "$(notes)" = 1 ] && ok "main checkout on another branch: finish not called, notified" || fail "other-branch: exec=$(execs) notify=$(notes)"

# ── 5. file trên đĩa đã là bản origin (phiên khác đã ff main): exec ngay, không cần merge
mkrepo; push_other $'#!/usr/bin/env bash\necho v2'; ( cd "$C/repo" && git pull -q --ff-only origin main 2>/dev/null )
self_reload_tick
[ "$(execs)" = 1 ] && ok "main already fast-forwarded by someone else: exec'd" || fail "already-ff: exec=$(execs)"

# ── 6. bản mới sai cú pháp: notify, không exec
mkrepo; push_other $'#!/usr/bin/env bash\nif then fi((('; self_reload_tick
[ "$(execs)" = 0 ] && [ "$(notes)" = 1 ] && ok "new script fails bash -n: notified, not exec'd" || fail "syntax: exec=$(execs) notify=$(notes)"

# ── 7. thay đổi local chưa commit chặn ff: notify, không exec
mkrepo; echo dirty >> "$RELOAD_SELF"; push_other $'#!/usr/bin/env bash\necho v2'; self_reload_tick
[ "$(execs)" = 0 ] && [ "$(notes)" = 1 ] && ok "uncommitted edit blocks the fast-forward: notified, not exec'd" || fail "dirty: exec=$(execs) notify=$(notes)"

# ── 8. finish THẬT (không stub) trên main lệch origin (QA v1 #308): main nhận commit của origin, commit local còn nguyên, worktree tạm bị gỡ;
#    xung đột thật: trả khác 0, main giữ nguyên.
WTPY="$ROOT/universal-agent-devkit/scripts/git/worktree.py"; [ -f "$WTPY" ] || WTPY="$ROOT/.agents/devkit/scripts/git/worktree.py"
real_finish() {   # chạy reload_finish_main thật (nạp lại runner trong subshell, bỏ stub) trong $C/repo
  ( here=$PWD; SB_LIB_ONLY=1 . "$RUNNER"; cd "$here" || exit 1; log() { echo "$*" >> "$TMP/log"; }; BASE_BRANCH=main; SB_WORKTREE_CMD="python3 $WTPY"; reload_finish_main )
}
mkrepo; ( cd "$C/repo" && echo local >> other.txt && git add -A && git commit -qm local )
push_other $'#!/usr/bin/env bash\necho v2'
git fetch -q origin; real_finish; rc=$?
[ "$rc" = 0 ] && grep -q v2 "$RELOAD_SELF" && git log --format=%s | grep -qx local && git merge-base --is-ancestor origin/main HEAD \
  && ok "real finish on diverged main: origin merged in, local commit kept" || fail "real finish: rc=$rc ($(tail -3 "$TMP/log" | tr '\n' ' '))"
[ -z "$(git -C "$C/repo" worktree list --porcelain | grep worktrees/self-reload-)" ] && ok "  … temporary worktree removed" || fail "worktree left behind"
mkrepo; ( cd "$C/repo" && echo '# local' >> "$REL" && git commit -qam local-runner ); before=$(git rev-parse HEAD)
push_other $'#!/usr/bin/env bash\necho v2'; git fetch -q origin; real_finish; rc=$?
[ "$rc" != 0 ] && [ "$(git rev-parse HEAD)" = "$before" ] && [ -z "$(git status --porcelain)" ] && ok "real finish with a conflict: non-zero, main untouched" || fail "real conflict: rc=$rc"

# ── 9. (#325) finish thành công đã gỡ worktree: không log cảnh báo giả "worktree remove failed"; worktree cũ cùng PID không chặn lần sau
mkrepo; ( cd "$C/repo" && echo local >> other.txt && git add -A && git commit -qm local )
( cd "$C/repo" && python3 "$WTPY" add ".claude/worktrees/self-reload-$$" >/dev/null 2>&1 )   # bản mồ côi của lần reload trước (cùng PID)
push_other $'#!/usr/bin/env bash\necho v2'; git fetch -q origin; : > "$TMP/log"; real_finish; rc=$?
[ "$rc" = 0 ] && grep -q v2 "$RELOAD_SELF" && ok "stale self-reload-PID worktree does not block the next reload" || fail "stale worktree blocked reload: rc=$rc ($(tail -2 "$TMP/log" | tr '\n' ' '))"
! grep -q "worktree remove" "$TMP/log" && ok "  … no false 'worktree remove failed' after a successful finish" || fail "false warning: $(cat "$TMP/log")"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
