#!/usr/bin/env bash
# Hồi quy #234: bước dựng DevKit trong worktree tạm (scratch của merge gate) viết lại khối devkit-essentials trong AGENTS.md ĐÃ TRACK;
# `worktree remove` / `discard` từ chối vì AGENTS.md là "file đã track bị sửa", thẻ kẹt tới khi người dùng hoàn tác bằng tay.
#   - chỉ khối devkit-essentials (do DevKit sinh) khác HEAD: remove và discard gỡ được (discard cất bản dự phòng refs/devkit/discarded)
#   - AGENTS.md sửa NGOÀI khối sinh: vẫn từ chối như cũ
#   - khối sinh sửa + một sửa ngoài khối: vẫn từ chối
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

R="$TMP/re"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
printf '# Project\nmine\n<!-- devkit-essentials:start — generated -->\nold line 1\nold line 2\n<!-- devkit-essentials:end -->\ntail\n' > AGENTS.md
printf '1\n' > f.txt
G "$R" add -A && G "$R" commit -qm init
wt() { bash "$KIT" worktree add "../re-$1" >/dev/null 2>&1 || fail "add re-$1"; }
rewrite_block() { python3 - "$1/AGENTS.md" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
i = t.index("old line 1"); j = t.index("<!-- devkit-essentials:end")
open(p, "w").write(t[:i] + "new line A\nnew line B\nnew line C\n" + t[j:])
PY
}

wt a; rewrite_block "$TMP/re-a"
bash "$KIT" worktree remove "../re-a" >"$TMP/a.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/re-a" ] && ok "remove: only the generated essentials block differs -> removed" \
  || { fail "remove with block-only change (rc=$rc)"; cat "$TMP/a.out"; }

wt b; rewrite_block "$TMP/re-b"
bash "$KIT" worktree discard "../re-b" >"$TMP/b.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/re-b" ] && ok "discard: only the generated essentials block differs -> removed" \
  || { fail "discard with block-only change (rc=$rc)"; cat "$TMP/b.out"; }

wt c; printf 'edited by a person\n' >> "$TMP/re-c/AGENTS.md"
bash "$KIT" worktree remove "../re-c" >"$TMP/c.out" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/re-c" ] && grep -q "AGENTS.md" "$TMP/c.out" \
  && ok "remove: AGENTS.md edited OUTSIDE the generated block -> still refused" \
  || { fail "edit outside the block (rc=$rc)"; cat "$TMP/c.out"; }

wt d; rewrite_block "$TMP/re-d"; sed -i.bak 's/^mine$/mine, changed/' "$TMP/re-d/AGENTS.md"; rm -f "$TMP/re-d/AGENTS.md.bak"
bash "$KIT" worktree remove "../re-d" >"$TMP/d.out" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/re-d" ] && grep -q "AGENTS.md" "$TMP/d.out" \
  && ok "remove: block rewritten AND an edit outside it -> still refused" \
  || { fail "block + outside edit (rc=$rc)"; cat "$TMP/d.out"; }

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_remove_essentials_block: PASS"; exit 0; } || { echo "test_worktree_remove_essentials_block: FAIL ($FAILS)"; exit 1; }
