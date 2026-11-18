#!/usr/bin/env bash
# Test (#1281, kitbug7d37f60a577e): runner trên đĩa bị sửa tay chưa commit, nhưng đúng phần sửa đó đã nằm trong bản origin
# (phiên khác sửa tay trước khi PR merge) ⇒ ff bị chặn mãi mãi và cảnh báo "uncommitted edits in the way?". Kỳ vọng: nạp bản origin, không cảnh báo.
# Sửa tay KHÁC với origin vẫn được giữ (ca 7d của test_runner_self_reload.sh).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-self-reload-abs.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
log() { echo "$*" >> "$TMP/log"; }
board_notify() { echo "$*" >> "$TMP/notify"; }
reload_exec() { echo "$1" >> "$TMP/exec"; }
runner_state_write() { :; }
CONFIG_SLUG="board"; BASE_BRANCH="main"; ACTIVE_WORKERS=0; SB_RELOAD_EVERY=0
REL=".claude/bin/super-board-run.sh"
mkrepo() {
  C="$TMP/c$1"; mkdir -p "$C"; unset SB_RELOAD_SWAPPED_SUM
  git init -q --bare -b main "$C/origin.git"; git clone -q "$C/origin.git" "$C/repo" 2>/dev/null
  ( cd "$C/repo" && git checkout -q -b main 2>/dev/null; mkdir -p .claude/bin && printf '#!/usr/bin/env bash\nmodel=argon\necho tail\n' > "$REL" && chmod 755 "$REL" \
    && echo base > other.txt && git add -A && git commit -qm v1 && git push -q origin main 2>/dev/null )
  git clone -q "$C/origin.git" "$C/other" 2>/dev/null
  : > "$TMP/log"; : > "$TMP/notify"; : > "$TMP/exec"
  cd "$C/repo" || exit 1
  RELOAD_SELF="$C/repo/$REL"; RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF"); RELOAD_WARNED=""; RELOAD_NEXT_CHECK=0
}
push_other() {   # push_other <model>: origin nhận bản có thêm một dòng cuối
  ( cd "$C/other" && printf '#!/usr/bin/env bash\nmodel=%s\necho tail\necho more\n' "$1" > "$REL" && git add -A && git commit -qm n && git push -q origin main 2>/dev/null )
}
execs() { wc -l < "$TMP/exec" | tr -d ' '; }
notes() { wc -l < "$TMP/notify" | tr -d ' '; }

# 1. sửa tay (model=hydrogen) đã có trên origin cùng một thay đổi khác ⇒ nạp, không cảnh báo, đĩa = origin
mkrepo 1; sed -i.bak 's/argon/hydrogen/' "$REL"; rm -f "$REL.bak"; RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF")
push_other hydrogen
self_reload_tick
new=$(git rev-parse "origin/main:$REL")
[ "$(execs)" = 1 ] && [ "$(notes)" = 0 ] && [ "$(git hash-object "$RELOAD_SELF")" = "$new" ] \
  && ok "hand edit already on origin: reloaded, no warning" || fail "absorbed: exec=$(execs) notify=$(notes) log=$(cat "$TMP/log")"

# 2. sửa tay chưa có trên origin ⇒ giữ nguyên, cảnh báo (không mất việc của người)
mkrepo 2; sed -i.bak 's/argon/mine/' "$REL"; rm -f "$REL.bak"; RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF")
push_other argon
self_reload_tick
[ "$(execs)" = 0 ] && [ "$(notes)" = 1 ] && grep -q 'model=mine' "$RELOAD_SELF" \
  && ok "different hand edit: kept and warned" || fail "foreign edit: exec=$(execs) notify=$(notes)"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
