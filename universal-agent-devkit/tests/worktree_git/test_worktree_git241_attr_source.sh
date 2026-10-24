#!/usr/bin/env bash
# Hồi quy (#330 mục 3, #358): `git --attr-source` không có ở git 2.40/2.41 (exit 129 "unknown option"), nhưng worktree.py coi merge-tree dùng được từ
# 2.40: _merge_tree (_merges_to, _adds_nothing_to_main) trả False im lặng, nên `worktree prune-branch` từ chối một nhánh mà PR đã squash vào trunk.
# Ca dùng một `git` giả trên PATH: tự nhận là 2.41.0 và từ chối --attr-source như git thật 2.41; mọi lệnh khác chuyển cho git thật.
#   g1. đối chứng: git thật, nhánh đã squash vào trunk → prune-branch xoá được
#   g2. git giả 2.41: cùng ca → vẫn xoá được (merge-tree thử lại không --attr-source)
#   g3. (âm) git giả 2.41 + nhánh còn commit mà trunk chưa có → vẫn từ chối (không vì hết lỗi mà nhận bừa)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
REAL_GIT="$(command -v git)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { "$REAL_GIT" -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

mkdir -p "$TMP/stub"
cat > "$TMP/stub/git" <<STUB
#!/bin/sh
case "\$1" in version|--version) echo "git version 2.41.0"; exit 0 ;; esac
for a in "\$@"; do
  case "\$a" in --attr-source*) echo "unknown option: \$a" >&2; echo "usage: git [-v | --version] [-h | --help]" >&2; exit 129 ;; esac
done
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$TMP/stub/git"

"$REAL_GIT" init -q -b main "$TMP/rd"
R="$TMP/rd"; cd "$R" || exit 1
printf 'a1\n' > a.txt; printf 'b1\n' > b.txt
G "$R" add -A && G "$R" commit -qm init
for b in feat-ok feat-stub feat-neg; do
  G "$R" checkout -q -b "$b" main
  printf 'a2\n' > a.txt; G "$R" commit -qam c1
  printf 'b2\n' > b.txt; G "$R" commit -qam c2
done
printf 'e\n' > e.txt; G "$R" add e.txt; G "$R" commit -qm c3-only-here
G "$R" checkout -q main
printf 'a2\n' > a.txt; printf 'b2\n' > b.txt; G "$R" commit -qam "squash #1"   # PR vào trunk bằng MỘT commit khác patch-id

prune() { bash "$KIT" worktree prune-branch "$1" 2>&1; }
G "$R" branch --list feat-ok | grep -q feat-ok || fail "setup: branch feat-ok missing"
out=$(prune feat-ok); rc=$?
[ "$rc" = 0 ] && ! G "$R" rev-parse -q --verify refs/heads/feat-ok >/dev/null && ok "g1 real git: prune-branch deletes the squashed branch" || { fail "g1 control (rc=$rc)"; echo "$out"; }

out=$(PATH="$TMP/stub:$PATH" prune feat-stub); rc=$?
[ "$rc" = 0 ] && ! G "$R" rev-parse -q --verify refs/heads/feat-stub >/dev/null && ok "g2 git 2.41 (no --attr-source): prune-branch still deletes the squashed branch" || { fail "g2 git 2.41 refused a squashed branch (rc=$rc)"; echo "$out"; }

out=$(PATH="$TMP/stub:$PATH" prune feat-neg); rc=$?
[ "$rc" != 0 ] && G "$R" rev-parse -q --verify refs/heads/feat-neg >/dev/null && printf '%s' "$out" | grep -q "holds commits the trunk lacks and no PR merged into the trunk at that tip: kept" && ok "g3 git 2.41: a branch with a commit the trunk lacks is still refused, with the real reason (rc=$rc)" || { fail "g3 git 2.41 deleted an unintegrated branch (rc=$rc)"; echo "$out"; }

[ "$FAILS" = 0 ] && echo "ALL PASS" || { echo "$FAILS FAILED"; exit 1; }
