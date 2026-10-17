#!/usr/bin/env bash
# Hồi quy K2 (Goods 17/10, Unity): worktree mới chỉ có file được track, nên thiếu những file bị git ignore (`*.dll.mdb`) mà
# `<file>.meta` của chúng LẠI được track. Unity xoá các `.meta` đó (và sinh `.vscode/`, `<tên>.slnx`); `worktree finish` báo
# "worktree đổi trong lúc gate chạy (chưa commit: …DOTween.dll.mdb.meta…)" và lần chạy sau có thể commit rác đó vào main.
# Sửa tận gốc: `worktree add` chép từ main những file bị ignore có `<file>.meta` được track.
#   1 sau add: x.dll.mdb có trong worktree, đúng nội dung của main; file bị ignore KHÔNG có .meta thì không chép
#   2 finish: không có gì để gộp (file chép vẫn bị ignore), worktree bị gỡ, main không track x.dll.mdb
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

P="$TMP/main"; mkdir -p "$P/Assets/Plugins" && G "$P" init -q -b main . && cd "$P" || exit 1
printf '*.dll.mdb\n*.log\n' > "$P/.gitignore"
printf 'mdb-bytes\n' > "$P/Assets/Plugins/x.dll.mdb"
printf 'guid: 1\n' > "$P/Assets/Plugins/x.dll.mdb.meta"
printf 'log\n' > "$P/Assets/other.log"   # bị ignore, không có .meta: không phải việc của add
G "$P" add -A && G "$P" commit -qm init
[ -z "$(G "$P" ls-files Assets/Plugins/x.dll.mdb)" ] && [ -n "$(G "$P" ls-files Assets/Plugins/x.dll.mdb.meta)" ] || fail "fixture: x.dll.mdb must be ignored, its .meta tracked"

W="$TMP/um"
bash "$KIT" worktree add ../um --no-init >"$TMP/add" 2>&1 || fail "add um: $(cat "$TMP/add")"
cmp -s "$P/Assets/Plugins/x.dll.mdb" "$W/Assets/Plugins/x.dll.mdb" \
  && ok "1: the ignored x.dll.mdb whose .meta is tracked is in the new worktree, same bytes as main's" || fail "1: x.dll.mdb missing in the worktree: $(cat "$TMP/add")"
[ ! -e "$W/Assets/other.log" ] && ok "  … an ignored file with no tracked .meta is not copied" || fail "  … other.log was copied"

(cd "$P" && bash "$KIT" worktree finish ../um >"$TMP/out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && [ -z "$(G "$P" ls-files Assets/Plugins/x.dll.mdb)" ] && [ -z "$(G "$P" status --porcelain --untracked-files=no)" ] \
  && ok "2: finish: the copy is no work of the worktree (nothing committed into main), the worktree is removed" || fail "2: (rc=$rc): $(cat "$TMP/out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_meta_ignored: all passed" || { echo "❌ test_worktree_meta_ignored: $FAILS failed"; exit 1; }
