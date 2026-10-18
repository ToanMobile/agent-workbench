#!/usr/bin/env bash
# Test hồi quy: push một nhánh PR (đích không phải trunk) không cần biên nhận gate --full — `--full` chạy đúng một lần ở merge
# gate ngay trước khi gộp vào main (người dùng 18/10: mỗi PR GeelyEx2 chạy --full HAI lần trên cùng nội dung). Push lên trunk
# (main/master/trunk/develop/release/*/hotfix/*, nhánh mặc định của remote) hoặc không rõ đích vẫn đòi biên nhận như cũ.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PG="$DEVKIT_DIR/bin/push_gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
expect() { # tên exit-mong-đợi đối-số-push_gate...
  local name="$1" want="$2" out rc; shift 2
  out="$(python3 "$PG" "$TMP/repo" "$@" 2>&1)"; rc=$?
  [ "$rc" = "$want" ] && echo "✔ $name (exit $rc)" || { echo "✖ $name: exit $rc, expected $want — $out"; FAILS=$((FAILS + 1)); }
}
git init -q --bare -b main "$TMP/remote.git"
mkdir -p "$TMP/repo/src" "$TMP/repo/.agents" && cd "$TMP/repo" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git remote add origin "$TMP/remote.git"
echo "fun ok() = 1" > src/Core.kt
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init && git push -q -u origin main 2>/dev/null
git remote set-head origin main >/dev/null 2>&1
echo "fun ok() = 2" > src/Core.kt && git commit -qam "code, never gated"

expect "nhánh PR feat/x, chưa có biên nhận: cho push" 0 HEAD --dst origin feat/x
expect "nhánh PR dạng refs/heads/fix-y: cho push" 0 HEAD --dst origin refs/heads/fix-y
expect "không có --dst (đích không rõ): vẫn chặn" 2 HEAD
expect "đích main: vẫn chặn" 2 HEAD --dst origin main
expect "đích refs/heads/main: vẫn chặn" 2 HEAD --dst origin refs/heads/main
for b in master trunk develop release/1.2 hotfix/crash; do
  expect "đích $b: vẫn chặn" 2 HEAD --dst origin "$b"
done
for d in heads/main HEADS/Master tags/v1 remotes/origin/main refs/tags/x HEAD head; do
  expect "đích $d (DWIM / namespace ref): vẫn chặn" 2 HEAD --dst origin "$d"
done
expect "--all-tags thiếu remote kèm --dst: luật cũ, chặn" 2 --all-tags --dst origin feat/x
expect "hai --dst: luật cũ, chặn" 2 HEAD --dst origin feat/x --dst origin main
expect "--tag-remote kèm --dst: luật cũ, chặn" 2 HEAD --tag-remote origin --dst origin feat/x
git symbolic-ref --delete refs/remotes/origin/HEAD
expect "remote không có ref HEAD (ponytail): nhánh feat/x cho push" 0 HEAD --dst origin feat/x
expect "remote không có ref HEAD: main vẫn chặn" 2 HEAD --dst origin main
git update-ref refs/remotes/origin/prod HEAD
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/Prod
expect "ref HEAD viết hoa khác (origin/Prod), đích prod: vẫn chặn" 2 HEAD --dst origin prod
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/prod
expect "đích là nhánh mặc định của remote (prod): vẫn chặn" 2 HEAD --dst origin prod
expect "đích MAIN (APFS không phân biệt hoa thường): vẫn chặn" 2 HEAD --dst origin MAIN
expect "nhánh không phải mặc định (feat/x) sau khi đổi mặc định: cho push" 0 HEAD --dst origin feat/x
git update-ref refs/heads/origin/prod HEAD   # một nhánh local tên origin/prod: --short của symbolic-ref đổi thành remotes/origin/prod
expect "nhánh mặc định prod khi có nhánh local origin/prod: vẫn chặn" 2 HEAD --dst origin prod
git update-ref -d refs/heads/origin/prod
git remote set-url --push origin "$TMP/other.git"
expect "pushurl khác URL fetch (không biết nhánh mặc định): vẫn chặn" 2 HEAD --dst origin feat/x
git config --unset remote.origin.pushurl
expect "remote là URL, không phải tên: vẫn chặn" 2 HEAD --dst "$TMP/remote.git" feat/x
expect "đích rỗng: vẫn chặn" 2 HEAD --dst origin ""
expect "--dst thiếu giá trị: vẫn chặn" 2 HEAD --dst origin
[ "$FAILS" -eq 0 ] && echo "push gate PR branch: all checks passed" || { echo "push gate PR branch: $FAILS FAILED"; exit 1; }
