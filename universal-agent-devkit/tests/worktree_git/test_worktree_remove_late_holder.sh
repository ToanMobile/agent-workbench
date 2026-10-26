#!/usr/bin/env bash
# `worktree.py remove` (gỡ thường, không --merged) hỏi lại phiên sống ngay trước khi gỡ (#427 vòng 3). _iter_blockers chạy git (có thể
# lâu); một phiên nhận worktree giữa chừng (khoá checkout của pid sống) trước đây vẫn bị gỡ từ dưới chân. Mô phỏng race thật: một `git`
# giả đặt trước trên PATH ghi khoá đó ngay lần `git status` đầu tiên của _iter_blockers.
#   WTL_KIT=<devkit dir>   chạy bản kit khác (bản chưa sửa: RED).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="${WTL_KIT:-$DEVKIT_DIR}/scripts/git/worktree.py"
TMP="$(mktemp -d)"; SL=""
trap '[ -n "$SL" ] && kill "$SL" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
REALGIT="$(command -v git)"

R="$TMP/repo"; mkdir -p "$R" && G "$R" init -q -b main . && echo a > "$R/a.txt" && G "$R" add -A && G "$R" commit -qm base
H="$R/.claude/worktrees"; mkdir -p "$H"
sleep 300 & SL=$!

# fakegit <dir> <gitdir của worktree>: git giả, lần `status` đầu tiên ghi khoá checkout của pid sống SL rồi chạy git thật
fakegit() {
  mkdir -p "$1"
  cat > "$1/git" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *" status "*) [ -e "$1.hit" ] || { printf '{"session_id":"late-holder","pid":$SL,"gitdir":"$2"}\n' > "$2/devkit-session.lock"; touch "$1.hit"; } ;;
esac
exec "$REALGIT" "\$@"
EOF
  chmod +x "$1/git"
}

# 1. phiên nhận worktree trong lúc _iter_blockers chạy: giữ, exit 1, dòng ✖ nêu phiên
G "$R" worktree add -q --detach "$H/late" main
GDL="$(G "$H/late" rev-parse --absolute-git-dir)"
fakegit "$TMP/fake1" "$GDL"
(cd "$R" && PATH="$TMP/fake1:$PATH" python3 "$WT" remove "$H/late" > "$TMP/r1.out" 2>&1); rc=$?
[ -e "$TMP/fake1.hit" ] || fail "setup: the fake git never wrote the late lock"
[ "$rc" -eq 1 ] && [ -d "$H/late" ] && grep -q "✖.*late-holder" "$TMP/r1.out" \
  && ok "remove asks who holds the worktree right before removing it: a session that took it during the checks keeps it (✖, exit 1)" \
  || { fail "remove rc=$rc: a worktree a live session took during the checks was $([ -d "$H/late" ] && echo kept without the reason || echo REMOVED)"; cat "$TMP/r1.out"; }

# 2. đối chứng: không ai nhận worktree: vẫn gỡ như trước
G "$R" worktree add -q --detach "$H/free" main
(cd "$R" && python3 "$WT" remove "$H/free" > "$TMP/r2.out" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ ! -d "$H/free" ] && ok "control: an unheld, clean worktree is still removed" \
  || { fail "control remove rc=$rc"; cat "$TMP/r2.out"; }

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_remove_late_holder: all passed" || { echo "❌ test_worktree_remove_late_holder: $FAILS failed"; exit 1; }
