#!/usr/bin/env bash
# Hồi quy K6 (17/10): thông báo xung đột của `agent-kit worktree finish` khuyên `git -C <wt> add <file>`, nhưng harness của Claude
# chặn `git -C` với đường dẫn tính lúc chạy, nên agent làm theo lời khuyên thì bị chặn. Lời khuyên giờ là
# `cd <wt> && git add <file> && git commit --no-edit`, rồi `agent-kit worktree finish <wt>`.
#   1 xung đột: exit 3, lời khuyên dạng mới (tiếng Anh và tiếng Việt), không còn `git -C`
#   2 làm đúng theo lời khuyên (cd, add, commit --no-edit) rồi finish: gộp xong, worktree bị gỡ
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(cd "$(mktemp -d)" && pwd -P)"   # đường dẫn thật (/private/var/...): đúng chữ finish in ra trong lời khuyên
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

P="$TMP/main"; mkdir -p "$P" && G "$P" init -q -b main . && cd "$P" || exit 1
G "$P" config user.email t@t; G "$P" config user.name t   # `git commit --no-edit` của bước 2 chạy đúng như lời khuyên, không -c
printf '1\n2\n3\n' > "$P/a.txt"; G "$P" add -A && G "$P" commit -qm init
W="$TMP/ca-x"
DEVKIT_LANG=en bash "$KIT" worktree add ../ca-x --no-init >/dev/null 2>&1 || fail "add ca-x"
printf '1\nW2\n3\n' > "$W/a.txt"; G "$W" commit -qam "w2"
printf '1\nM2\n3\n' > "$P/a.txt"; G "$P" commit -qam "m2"

# 1: xung đột, lời khuyên dạng mới ở cả hai ngôn ngữ
(cd "$P" && DEVKIT_LANG=en bash "$KIT" worktree finish ../ca-x >"$TMP/en" 2>&1); rc=$?
(cd "$P" && DEVKIT_LANG=vi bash "$KIT" worktree finish ../ca-x >"$TMP/vi" 2>&1); rc_vi=$?
for lang in en vi; do
  out="$TMP/$lang"
  grep -qF "cd $W && git add <file> && git commit --no-edit" "$out" && grep -qF "agent-kit worktree finish $W" "$out" && ! grep -q "git -C" "$out" \
    && ok "1 ($lang): the conflict advice is cd <wt> && git add <file> && git commit --no-edit, then finish; no git -C" \
    || fail "1 ($lang): advice: $(cat "$out")"
done
[ "$rc" = 3 ] && [ "$rc_vi" = 3 ] && ok "  … exit 3 both times (the conflict stays open in the worktree)" || fail "  … rc=$rc rc_vi=$rc_vi"

# 2: làm đúng theo lời khuyên rồi chạy lại finish
printf '1\nW2+M2\n3\n' > "$W/a.txt"
(cd "$W" && git add a.txt && git commit --no-edit -q) || fail "2: the advised commands failed"
(cd "$P" && DEVKIT_LANG=en bash "$KIT" worktree finish ../ca-x >"$TMP/out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && grep -q "^W2+M2$" "$P/a.txt" \
  && ok "2: following the advice word for word, then finish: merged, the worktree is removed" || fail "2: (rc=$rc): $(cat "$TMP/out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_conflict_advice: all passed" || { echo "❌ test_worktree_conflict_advice: $FAILS failed"; exit 1; }
