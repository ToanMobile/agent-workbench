#!/usr/bin/env bash
# Hồi quy (#526 QA bị chặn 28/10): `git branch -m` trong worktree ghi vào reflog HEAD một dòng `<sha> 0000…` mà `git log -g` bỏ qua,
# nên số dòng file > số mục git in ra và `worktree remove` báo UNREACHABLE ("reflog không đọc được") cho một worktree sạch, đã đẩy.
#   n1. nhánh đổi tên, đã đẩy, cây sạch: gỡ được
#   n2. (âm) sau đổi tên, một commit chỉ còn trong reflog: vẫn từ chối UNREACHABLE
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

git init -q --bare -b main "$TMP/origin.git"
R="$TMP/rd"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
G "$R" config devkit.trunkMode true; G "$R" remote add origin "$TMP/origin.git"
printf 'a1\n' > a.txt; G "$R" add -A && G "$R" commit -qm init && G "$R" push -q origin main
mk() { bash "$KIT" worktree add "../$1" "$2" >/dev/null 2>&1 || fail "add $1"; }

mk w-rn issue-1-old
printf 'x\n' > "$TMP/w-rn/x.txt"; G "$TMP/w-rn" add x.txt; G "$TMP/w-rn" commit -qm fix
G "$TMP/w-rn" branch -m issue-1-old issue-1-new && G "$TMP/w-rn" push -q origin issue-1-new
bash "$KIT" worktree remove ../w-rn >"$TMP/n1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/w-rn" ] && ok "n1 remove of a clean, pushed worktree whose branch was renamed (rc=$rc)" \
  || { fail "n1 renamed-branch worktree refused (rc=$rc)"; cat "$TMP/n1.out"; }

mk w-lo issue-2-old
G "$TMP/w-lo" branch -m issue-2-old issue-2-new && G "$TMP/w-lo" checkout -q --detach
printf 'e\n' > "$TMP/w-lo/e.txt"; G "$TMP/w-lo" add e.txt; G "$TMP/w-lo" commit -qm only-here
G "$TMP/w-lo" checkout -q issue-2-new
bash "$KIT" worktree remove ../w-lo >"$TMP/n2.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-lo" ] && grep -q 'only-here' "$TMP/n2.out" && ok "n2 remove still refuses a reflog-only commit after a rename (rc=$rc)" \
  || { fail "n2 reflog-only commit dropped after a rename (rc=$rc)"; cat "$TMP/n2.out"; }

# n3 (âm): một dòng reflog hỏng (cắt cụt, `<sha> 0 …`) vẫn đếm, remove vẫn từ chối ("could not be read") chứ không bỏ qua
for bad in garbage short0; do
  mk "w-$bad" "issue-3-$bad"
  printf 'y\n' > "$TMP/w-$bad/y.txt"; G "$TMP/w-$bad" add y.txt; G "$TMP/w-$bad" commit -qm fix
  G "$TMP/w-$bad" push -q origin "issue-3-$bad"
  log="$(G "$TMP/w-$bad" rev-parse --git-path logs/HEAD)"; case "$log" in /*) ;; *) log="$TMP/w-$bad/$log" ;; esac
  case "$bad" in garbage) printf 'garbagegarbage\n' >> "$log" ;; short0) printf '%s 0 t <t@t> 1 +0000\tjunk\n' "$(G "$TMP/w-$bad" rev-parse HEAD)" >> "$log" ;; esac
  bash "$KIT" worktree remove "../w-$bad" >"$TMP/n3-$bad.out" 2>&1; rc=$?
  [ "$rc" != 0 ] && [ -e "$TMP/w-$bad" ] && grep -q 'UNREACHABLE' "$TMP/n3-$bad.out" && ok "n3 a corrupt reflog line ($bad) still fails closed (rc=$rc)" \
    || { fail "n3 corrupt reflog line ($bad) was skipped (rc=$rc)"; cat "$TMP/n3-$bad.out"; }
done

[ "$FAILS" = 0 ] && echo "ALL PASS" || { echo "$FAILS FAILED"; exit 1; }
