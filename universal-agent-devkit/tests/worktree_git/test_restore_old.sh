#!/usr/bin/env bash
# test_restore_old.sh — `agent-kit restore-old` puts recorded *_old backups back, and only
# when the original location holds nothing but DevKit content. Dry-run by default.
set -u

DEVKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/restore-old-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { echo "✔ $1"; PASS=$((PASS + 1)); }
bad() { echo "✘ $1"; FAIL=$((FAIL + 1)); }

# shellcheck source=/dev/null
_bc="$DEVKIT/scripts/git/backup_conflict.sh"; [ -f "$_bc" ] || _bc="$DEVKIT/scripts/backup_conflict.sh"
DEVKIT_ROOT="$DEVKIT" source "$_bc" >/dev/null
export DEVKIT_ROOT="$DEVKIT"

P="$TMP/proj"
mkdir -p "$P/.claude/commands" "$P/rules"

# 1. a user file replaced by a DevKit symlink
echo "my notes" > "$P/CLAUDE.md"
backup_conflict "$P/CLAUDE.md" "$DEVKIT" >/dev/null
ln -s "$DEVKIT/AGENTS.md" "$P/CLAUDE.md"
# 2. a user command inside .claude/commands (moved to the project tier .agents/local/commands/)
echo "mine" > "$P/.claude/commands/fix.md"
backup_conflict "$P/.claude/commands/fix.md" "$DEVKIT" >/dev/null
ln -s "$DEVKIT/commands/fix.md" "$P/.claude/commands/fix.md"
# 3. a user file whose location the user has since filled with their own content again
echo "v1" > "$P/.cursorrules"
backup_conflict "$P/.cursorrules" "$DEVKIT" >/dev/null
echo "user edited after install" > "$P/.cursorrules"
# 4. a location backed up twice: the oldest backup (the original) wins
echo "original" > "$P/rules/x.md"
backup_conflict "$P/rules/x.md" "$DEVKIT" >/dev/null
echo "second" > "$P/rules/x.md"
backup_conflict "$P/rules/x.md" "$DEVKIT" >/dev/null

[ -f "$P/CLAUDE_old.md" ] && [ -f "$P/.agents/local/commands/fix.md" ] && [ -f "$P/rules/x_old.md" ] \
  && ok "setup: backups recorded" || bad "setup: backups recorded"

# dry-run changes nothing
before="$(cd "$P" && find . | LC_ALL=C sort | shasum)"
out="$(bash "$DEVKIT/bin/agent-kit" restore-old "$P" 2>&1)"; rc=$?
after="$(cd "$P" && find . | LC_ALL=C sort | shasum)"
[ "$before" = "$after" ] && ok "dry-run leaves the project untouched" || bad "dry-run leaves the project untouched"
echo "$out" | grep -q "would    CLAUDE_old.md -> CLAUDE.md" && ok "dry-run lists the CLAUDE.md restore" || bad "dry-run lists the CLAUDE.md restore: $out"
echo "$out" | grep -q "SKIP     .cursorrules" && ok "dry-run reports the location holding user content" || bad "dry-run reports .cursorrules skip: $out"
[ "$rc" -ne 0 ] && ok "a skipped restore makes the exit status non-zero" || bad "exit status with a skipped restore (rc=$rc)"

bash "$DEVKIT/bin/agent-kit" restore-old "$P" --bogus >/dev/null 2>&1
[ $? -eq 2 ] && ok "unknown option -> exit 2" || bad "unknown option -> exit 2"

out="$(bash "$DEVKIT/bin/agent-kit" restore-old "$P" --apply 2>&1)"
[ -f "$P/CLAUDE.md" ] && [ ! -L "$P/CLAUDE.md" ] && [ "$(cat "$P/CLAUDE.md")" = "my notes" ] \
  && ok "apply: CLAUDE.md is the user's file again" || bad "apply: CLAUDE.md restored: $out"
[ ! -e "$P/CLAUDE_old.md" ] && ok "apply: CLAUDE_old.md consumed" || bad "apply: CLAUDE_old.md consumed"
[ "$(cat "$P/.claude/commands/fix.md" 2>/dev/null)" = "mine" ] && [ ! -L "$P/.claude/commands/fix.md" ] \
  && ok "apply: .claude/commands/fix.md restored from .agents/local/commands/" || bad "apply: command restored: $out"
[ "$(cat "$P/.cursorrules")" = "user edited after install" ] && [ -f "$P/.cursorrules_old" ] \
  && ok "apply: user content is never overwritten" || bad "apply: .cursorrules untouched"
[ "$(cat "$P/rules/x.md" 2>/dev/null)" = "original" ] && ok "apply: oldest backup of a twice-backed-up file wins" \
  || bad "apply: oldest backup wins (got '$(cat "$P/rules/x.md" 2>/dev/null)')"
ls "$P/rules" | grep -q "x_old_" && ok "apply: the later backup is kept" || bad "apply: later backup kept"
[ -e "$DEVKIT/AGENTS.md" ] && [ -e "$DEVKIT/commands/fix.md" ] && ok "apply: DevKit sources untouched" || bad "apply: DevKit sources untouched"

# a ledger line pointing outside the project is ignored
mkdir -p "$TMP/outside"
echo "keep" > "$TMP/outside/a_old.md"
echo "2026-01-01 00:00:00 | $TMP/outside/a.md -> $TMP/outside/a_old.md" >> "$P/.devkit_backups.log"
bash "$DEVKIT/bin/agent-kit" restore-old "$P" --apply >/dev/null 2>&1
[ -f "$TMP/outside/a_old.md" ] && [ ! -e "$TMP/outside/a.md" ] && ok "ledger entries outside the project are ignored" \
  || bad "ledger entries outside the project are ignored"

# a symlinked parent folder that points into the DevKit: the restore must not write through it
FK="$TMP/fakekit"; mkdir -p "$FK/commands"
Q="$TMP/proj2"; mkdir -p "$Q"
ln -s "$FK/commands" "$Q/cmds"
echo "mine" > "$Q/zz_old.md"
echo "2026-01-01 00:00:00 | $Q/cmds/zz.md -> $Q/zz_old.md" > "$Q/.devkit_backups.log"
DEVKIT_ROOT="$FK" bash -c 'source "$1" >/dev/null; restore_old_backups "$2" --apply' _ "$_bc" "$Q" >/dev/null 2>&1
[ ! -e "$FK/commands/zz.md" ] && [ -f "$Q/zz_old.md" ] && ok "restore never writes through a symlinked parent into the DevKit" \
  || bad "restore wrote through a symlinked parent into the DevKit"

# Kiểm tra cha-symlink phải chạy TRƯỚC rm/mkdir (chỉ đọc), và cả ở dry-run để bản xem trước khớp --apply
FK3="$TMP/fakekit3"; mkdir -p "$FK3/commands"; echo kit > "$FK3/AGENTS.md"
ln -s "$FK3/AGENTS.md" "$FK3/commands/zz.md"   # link của DevKit sau cha-symlink: restore coi chỗ này là "trống"
Q3="$TMP/proj3"; mkdir -p "$Q3"; ln -s "$FK3/commands" "$Q3/cmds"; echo plain > "$Q3/afile"
echo a > "$Q3/zz_old.md"; echo b > "$Q3/nn_old.md"; echo c > "$Q3/ff_old.md"
{ echo "2026-01-01 00:00:00 | $Q3/cmds/zz.md -> $Q3/zz_old.md"
  echo "2026-01-01 00:00:00 | $Q3/cmds/newdir/nn.md -> $Q3/nn_old.md"
  echo "2026-01-01 00:00:00 | $Q3/afile/ff.md -> $Q3/ff_old.md"; } > "$Q3/.devkit_backups.log"
rs3() { DEVKIT_ROOT="$FK3" bash -c 'source "$1" >/dev/null; restore_old_backups "$2" $3' _ "$_bc" "$Q3" "${1:-}" 2>/dev/null; }
out="$(rs3)"
! echo "$out" | grep -q "^  would" && [ "$(echo "$out" | grep -c "^  SKIP")" = 3 ] \
  && ok "dry-run reports SKIP (on stdout), never 'would', for targets --apply will skip" || bad "dry-run preview differs from --apply: $out"
out="$(rs3 --apply)"
[ -L "$FK3/commands/zz.md" ] && ok "apply: a DevKit file behind a symlinked parent is not deleted" || bad "apply deleted the DevKit file through a symlinked parent"
[ ! -e "$FK3/commands/newdir" ] && ok "apply: no folder is created through a symlinked parent" || bad "apply created a folder inside the DevKit"
[ -f "$Q3/zz_old.md" ] && [ -f "$Q3/nn_old.md" ] && [ -f "$Q3/ff_old.md" ] && ok "apply: skipped backups are kept" || bad "apply lost a skipped backup"
[ "$(echo "$out" | grep -c "^  SKIP")" = 3 ] && ok "apply: every SKIP goes to stdout" || bad "apply: SKIP not on stdout: $out"
echo "$out" | grep "afile/ff.md" | grep -q "symlink" && bad "apply: a file in the parent path is reported as a symlink: $out" \
  || { echo "$out" | grep -q "SKIP     afile/ff.md" && ok "apply: a file in the parent path gets its own message" || bad "apply: afile/ff.md not skipped: $out"; }
# _backup_assert_safe_dir: 0 = trong dự án (kể cả thư mục chưa tạo), 1 = ra ngoài, 2 = một phần đường dẫn là file
_backup_assert_safe_dir "$Q3/sub/deeper" "$Q3"; r1=$?
_backup_assert_safe_dir "$Q3/cmds/x" "$Q3"; r2=$?
_backup_assert_safe_dir "$Q3/cmds" "$Q3"; r3=$?
_backup_assert_safe_dir "$Q3/afile/x" "$Q3"; r4=$?
# `..` trong ledger: bước leo tổ tiên theo chuỗi không được để `nope/../..` (nope chưa có) dẫn mkdir/mv ra ngoài dự án;
# cha thiếu nhưng nằm trong dự án thì được tạo lại và bản sao lưu về chỗ cũ
Q4="$TMP/proj4"; mkdir -p "$Q4"; echo d > "$Q4/dd_old.md"; echo e > "$Q4/ee_old.md"
{ echo "2026-01-01 00:00:00 | $Q4/nope/../../outside4/dd.md -> $Q4/dd_old.md"
  echo "2026-01-01 00:00:00 | $Q4/newsub/deep/ee.md -> $Q4/ee_old.md"; } > "$Q4/.devkit_backups.log"
out="$(DEVKIT_ROOT="$FK3" bash -c 'source "$1" >/dev/null; restore_old_backups "$2" --apply' _ "$_bc" "$Q4" 2>/dev/null)"
[ ! -e "$TMP/outside4" ] && [ ! -e "$Q4/nope" ] && [ -f "$Q4/dd_old.md" ] && echo "$out" | grep "SKIP     nope/../../outside4/dd.md" | grep -q "segment" \
  && ok "apply: a '..' ledger target never reaches outside the project" || bad "apply followed '..' out of the project: $out"
[ "$(cat "$Q4/newsub/deep/ee.md" 2>/dev/null)" = e ] && ok "apply: a missing parent inside the project is recreated and the backup restored" \
  || bad "apply: missing parent not recreated: $out"
Q5="$TMP/proj5"; mkdir -p "$Q5"; echo g > "$Q5/gg_old.md"
echo "2026-01-01 00:00:00 | $Q5/gone/.. -> $Q5/gg_old.md" > "$Q5/.devkit_backups.log"
out="$(DEVKIT_ROOT="$FK3" bash -c 'source "$1" >/dev/null; restore_old_backups "$2" --apply' _ "$_bc" "$Q5" 2>/dev/null)"
[ ! -e "$Q5/gone" ] && [ -f "$Q5/gg_old.md" ] && echo "$out" | grep "SKIP     gone/.." | grep -q "segment" \
  && ok "apply: a '..' as the LAST segment of the target is refused too" || bad "apply: last-segment '..' not refused: $out"
# phía BACKUP cũng vậy: ledger (có thể đến từ repo clone về) không được kéo một file ngoài dự án vào trong rồi xoá bản gốc
mkdir -p "$TMP/outside5"; echo secret > "$TMP/outside5/hh_old.md"; echo secret2 > "$TMP/outside5/ii_old.md"
Q6="$TMP/proj6"; mkdir -p "$Q6"; ln -s "$TMP/outside5" "$Q6/lnk"
{ echo "2026-01-01 00:00:00 | $Q6/hh.md -> $Q6/../outside5/hh_old.md"
  echo "2026-01-01 00:00:00 | $Q6/ii.md -> $Q6/lnk/ii_old.md"; } > "$Q6/.devkit_backups.log"
out="$(DEVKIT_ROOT="$FK3" bash -c 'source "$1" >/dev/null; restore_old_backups "$2" --apply' _ "$_bc" "$Q6" 2>/dev/null)"
[ -f "$TMP/outside5/hh_old.md" ] && [ -f "$TMP/outside5/ii_old.md" ] && [ ! -e "$Q6/hh.md" ] && [ ! -e "$Q6/ii.md" ] \
  && [ "$(echo "$out" | grep -c "^  SKIP")" = 2 ] \
  && ok "apply: a backup path outside the project ('..' or a symlinked parent) is never moved in" || bad "apply moved a file from outside the project: $out"
_backup_assert_safe_dir "$Q3/nope/../.." "$Q3"; r5=$?
[ "$r1$r2$r3$r4$r5" = 01123 ] && ok "_backup_assert_safe_dir: missing dir inside=0, under a symlink out=1, symlink=1, under a file=2, a .. segment=3" \
  || bad "_backup_assert_safe_dir codes: got $r1$r2$r3$r4$r5, want 01123"

# Codex and Cursor adapters place the skills in .agents/skills like the other adapters
for ad in codex cursor; do
  R="$TMP/proj-$ad"; mkdir -p "$R"
  bash "$DEVKIT/adapters/setup_$ad.sh" "$R" symlink >/dev/null 2>&1
  [ -n "$(ls -A "$R/.agents/skills" 2>/dev/null)" ] && ok "setup_$ad.sh places .agents/skills" || bad "setup_$ad.sh places .agents/skills"
done

echo
echo "restore-old: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && echo "restore-old: all checks passed"
[ "$FAIL" -eq 0 ]
