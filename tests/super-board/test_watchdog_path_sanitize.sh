#!/usr/bin/env bash
# Test hồi quy: super-board-watchdog.sh làm sạch đường dẫn đọc từ bản ghi <slug>.state (worker ghi được) trước khi đưa
# vào runner launchd khởi động không người giám sát.
#
# Lỗi (OCR HIGH, 19/10): safe_path so tiền tố chuỗi `case "$d/" in "$ROOT"/*)`, nên `$ROOT/./x`, `$ROOT/sub/../x` và
# đường dẫn qua symlink (ROOT dưới /private/tmp, mục PATH viết /tmp/..., hoặc ngược lại) lọt qua: thư mục worker tạo
# trong repo đứng đầu PATH của runner. runner_log cùng kiểu: LOG là symlink trong thư mục log của board trỏ ra ngoài
# repo thì runner ghi nối vào file đích.
#
# Quan sát hộp đen qua `check`: runner chết (STATE=crashed), không marker. Thư mục công cụ rỗng → verdict missing-tools
# ghi PATH đã làm sạch vào watchdog.log. Ca LOG: đủ công cụ (stub) → watchdog khởi động lại một super-board-run.sh giả,
# xem nó ghi vào file nào. Repo giả trong thư mục tạm, không chạm repo thật. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[ "$(uname -s)" = Darwin ] || { echo "• skip test_watchdog_path_sanitize: macOS only (launchd)"; exit 0; }
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# pwd -P: TMP là đường dẫn vật lý; LINK là bí danh symlink của repo giả (tương đương /tmp ↔ /private/tmp).
TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/sb-wd-path.XXXXXX")" && pwd -P)"
trap '[ -n "${KEEP:-}" ] && echo "kept $TMP" || rm -rf "$TMP"' EXIT
R="$TMP/repo"; LINK="$TMP/link"
mkdir -p "$R/.claude/bin" "$R/.claude/super-board/runner" "$R/.claude/worktrees/evil" "$R/sub" "$R/docs/super-board" \
  "$TMP/outside" "$TMP/tools"
cp "$ROOT/.claude/bin/super-board-watchdog.sh" "$R/.claude/bin/"
ln -s "$R" "$LINK"
ln -s "$R/.claude/worktrees/notyet" "$TMP/dangling"            # symlink treo trỏ vào repo (worker tạo đích sau)
ln -s "$TMP/outside" "$R/.claude/worktrees/evil/out"            # symlink trong repo trỏ ra ngoài (worker đổi đích sau)

RUNDIR="$R/.claude/super-board/runner"
STATE="$RUNDIR/t.state"; WD="$RUNDIR/t.watchdog"; WLOG="$RUNDIR/t.watchdog.log"
field() { sed -n "s/^$1=//p" "$2" 2>/dev/null | head -1; }
sleep 0 & DEAD=$!; wait "$DEAD" 2>/dev/null   # PID vừa chết, tự thoát

# check_path <bí danh gọi watchdog: R|LINK> <ENV_PATH>: in PATH watchdog đã làm sạch (dòng missing-tools cuối).
check_path() {
  local base="$R"
  [ "$1" = LINK ] && base="$LINK"
  printf 'PID=%s\nSLUG=t\nSTARTED=1\nDAEMON=0\nLOG=\nSTATE=crashed\nRC=143\nENV_PATH=%s\n' "$DEAD" "$2" > "$STATE"
  rm -f "$WD" "$WLOG"   # verdict chỉ ghi log khi kết luận đổi
  ( cd "$base" && bash "$base/.claude/bin/super-board-watchdog.sh" check t ) >/dev/null 2>&1
  sed -n 's/.*lacks:.*(PATH=\(.*\)) — not restarted$/\1/p' "$WLOG" 2>/dev/null | tail -1
}
# expect_dropped <mô tả> <R|LINK> <mục độc>: mục độc bị bỏ, mục hợp lệ ngoài repo vẫn giữ.
expect_dropped() {
  local got
  got=$(check_path "$2" "$3:$TMP/outside")
  if [ "$got" = "$TMP/outside" ]; then ok "safe_path drops $1"
  else fail "safe_path kept $1: PATH='$got' (want '$TMP/outside')"; fi
}

# Mục bắt đầu đúng bằng "$ROOT/" thì cách so cũ đã bỏ; lọt qua là mục KHÔNG viết bằng tiền tố đó nhưng trỏ vào repo.
expect_dropped "a ./ component before the repo"          R    "$TMP/./repo/.claude/worktrees/evil"
expect_dropped "a dir/../ component before the repo"     R    "$TMP/outside/../repo/.claude/worktrees/evil"
expect_dropped "a doubled slash before the repo"         R    "$TMP//repo/.claude/worktrees/evil"
expect_dropped "\$ROOT/sub/../x inside the repo"          R    "$R/sub/../.claude/worktrees/evil"
expect_dropped "a symlink alias of the repo (entry via alias, ROOT physical)" R "$LINK/.claude/worktrees/evil"
expect_dropped "a physical entry when ROOT is the alias (watchdog run via the symlink)" LINK "$R/.claude/worktrees/evil"
expect_dropped "a dangling symlink that points into the repo" R "$TMP/dangling/bin"
got=$(check_path R "$R/.claude/worktrees/evil/out")
[ "$got" = "$TMP/outside" ] && ok "an in-repo symlink to an outside dir is passed resolved (worker cannot retarget it later)" \
  || fail "in-repo symlink to outside: PATH='$got' (want '$TMP/outside')"
got=$(check_path R "relative/bin:$TMP/outside:/usr/bin")
[ "$got" = "$TMP/outside:/usr/bin" ] && ok "valid outside entries are kept in order, relative entries dropped" \
  || fail "valid entries: PATH='$got' (want '$TMP/outside:/usr/bin')"

got=$(check_path R "$TMP/outside:/:/usr/bin")
case ":$got:" in *::*) fail "root entry '/' became an empty PATH entry (= cwd = repo root): PATH='$got'" ;;
  *) [ "$got" = "$TMP/outside:/:/usr/bin" ] && ok "a root entry '/' stays '/', never an empty entry (cwd = repo root)" \
       || fail "root entry: PATH='$got' (want '$TMP/outside:/:/usr/bin')" ;; esac

# ── LOG: symlink trong thư mục log của board trỏ ra ngoài repo ───────────────────────────────────────────────────────
for t in gh jq claude; do printf '#!/bin/sh\nexit 0\n' > "$TMP/tools/$t"; chmod +x "$TMP/tools/$t"; done
printf 'import sys\nsys.exit(0)\n' > "$R/.claude/bin/super-board-github-read.py"
printf '#!/usr/bin/env bash\necho STUB-RUNNER-RAN\n' > "$R/.claude/bin/super-board-run.sh"
: > "$TMP/victim"
ln -s "$TMP/victim" "$R/docs/super-board/evil.log"
printf 'PID=%s\nSLUG=t\nSTARTED=1\nDAEMON=0\nLOG=%s\nSTATE=crashed\nRC=143\nENV_PATH=%s\n' \
  "$DEAD" "$R/docs/super-board/evil.log" "$TMP/tools:$PATH" > "$STATE"
rm -f "$WD" "$WLOG"
( cd "$R" && bash "$R/.claude/bin/super-board-watchdog.sh" check t ) >/dev/null 2>&1
i=0; while [ "$i" -lt 50 ] && ! grep -q STUB-RUNNER-RAN "$TMP/victim" "$R/docs/super-board/runner.log" 2>/dev/null; do
  sleep 0.1; i=$((i + 1)); done
grep -q 'restarted the runner' "$WLOG" 2>/dev/null || fail "LOG case: watchdog did not restart the stub runner ($(tail -1 "$WLOG" 2>/dev/null))"
[ ! -s "$TMP/victim" ] && ok "a LOG that is a symlink out of the repo is refused (outside file untouched)" \
  || fail "restarted runner appended to the file a LOG symlink points at outside the repo"
grep -q STUB-RUNNER-RAN "$R/docs/super-board/runner.log" 2>/dev/null && ok "refused LOG falls back to docs/super-board/runner.log" \
  || fail "default runner.log did not get the restarted runner's output"

[ "$FAILS" -eq 0 ] && { echo "PASS test_watchdog_path_sanitize"; exit 0; }
echo "FAIL test_watchdog_path_sanitize: $FAILS failure(s)"; exit 1
