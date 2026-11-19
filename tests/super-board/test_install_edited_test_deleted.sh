#!/usr/bin/env bash
# #1323: comment duyệt tay `approved-head` + `edited-tests` phủ được test ĐÃ XOÁ bằng mục `"sha256": "deleted"`. Mục đó chỉ được nhận khi
# đủ ba điều (INSTINCT-086: chuỗi tự khai không thành cửa sau): file VẮNG ở cây scratch, VẮNG ở head được duyệt, CÓ ở merge-base(base, head).
#  H1: mục deleted hợp lệ (tests/old.sh xoá trong PR) -> ghi vào approved_tests.json với sha256 "deleted".
#  H2: mục deleted cho file còn ở head (tests/t.sh) -> loại, không ghi.
#  H3: mục deleted cho file không có ở merge-base (thêm rồi xoá trong PR, hoặc tên bịa) -> loại.
#  H4: không truyền --base -> mục deleted bị loại (fail closed).
#  H5: file vắng ở head nhưng có ở cây scratch -> loại. H6: ở merge-base là thư mục, không phải file -> loại.
#  E1: --edited-unchanged nhận mục deleted hợp lệ khi main không đổi file (exit 0); E2: main sửa file đó sau fork -> exit 1;
#  E3: mục deleted cho file còn ở head -> exit 1; E4: file không có ở merge-base -> exit 1.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
INS="$ROOT/.claude/bin/super-board-install-edited-test-approval.sh"
TASK=T1323-deleted-test
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-et-deleted.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"   # biên bản giả dưới $TMP
export DEVKIT_PM_HOME_TEST=1

IR="$TMP/repo"
g() { git -C "$IR" "$@"; }
git init -q -b main "$IR"
g config user.email t@example.invalid; g config user.name t; g config commit.gpgsign false
mkdir -p "$IR/tests"
printf '#!/bin/sh\ntrue\n' > "$IR/tests/t.sh"
printf '#!/bin/sh\ntrue # old\n' > "$IR/tests/old.sh"
mkdir -p "$IR/tests/dir.sh"; printf 'x\n' > "$IR/tests/dir.sh/inner.txt"   # H6: thư mục mang tên test
g add tests && g commit -qm M0
g switch -q -c feat
printf '#!/bin/sh\ntrue # ghost\n' > "$IR/tests/ghost.sh"
g add tests/ghost.sh && g commit -qm "thêm ghost"
g rm -q -r tests/old.sh tests/ghost.sh tests/dir.sh && g commit -qm "xoá old + ghost + dir"
HEAD_SHA=$(g rev-parse HEAD)
g switch -q main
g worktree add -q --detach "$TMP/scr" "$HEAD_SHA"
SCR="$TMP/scr"
DEST="$SCR/.claude/audit-gate/approved_tests.json"

mkdir -p "$TMP/pm/projects/p-$TASK/tasks/$TASK"
python3 -c '
import json, sys
json.dump({"id": sys.argv[1], "project": sys.argv[2], "verdicts": {"audit": {
    "verdict": "pass", "round": 1, "reviewer": "pm", "notes": "audit ok\nauditedHead: %s" % sys.argv[3]}}}, open(sys.argv[4], "w"))
' "$TASK" "$IR" "$HEAD_SHA" "$TMP/pm/projects/p-$TASK/tasks/$TASK/task.json"

meta() {   # meta <out> <path> <sha256>: comment OWNER approved-head + approved-by + edited-tests một mục
  python3 -c '
import json, sys
out, sha, task, path, digest = sys.argv[1:6]
item = {"path": path, "sha256": digest, "reviewer": "antigravity", "author": "claude-lane", "task_id": task, "reason": "xoá test cũ"}
body = ("approved-head:%s\napproved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp\"}\n"
        "edited-tests: %s\n") % (sha, task, json.dumps([item]))
json.dump({"comments": [{"authorAssociation": "OWNER", "body": body}]}, open(out, "w"))
' "$1" "$HEAD_SHA" "$TASK" "$2" "$3"
}
install() {   # install <meta> [--base REF]
  rm -f "$DEST"
  bash "$INS" --scratch "$SCR" --sha "$HEAD_SHA" --meta "$1" --top "$IR" "${@:2}" 2>"$TMP/err" >/dev/null
}
written() {   # written <path>: approved_tests.json có mục path với sha256 "deleted"
  [ -f "$DEST" ] && python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if any(e.get("path") == sys.argv[2] and e.get("sha256") == "deleted" for e in d.get("approvals", [])) else 1)
' "$DEST" "$1"
}

# H1
meta "$TMP/h1.json" tests/old.sh deleted
install "$TMP/h1.json" --base main
written tests/old.sh && ok "H1: mục deleted hợp lệ -> ghi sha256 deleted" || fail "H1: không ghi mục deleted hợp lệ ($(tail -1 "$TMP/err"))"

# H2
meta "$TMP/h2.json" tests/t.sh deleted
install "$TMP/h2.json" --base main
[ ! -f "$DEST" ] && grep -q "còn ở cây scratch" "$TMP/err" && ok "H2: deleted cho file còn ở head -> loại" || fail "H2: file còn ở head vẫn ghi / không báo"
rm -f "$SCR/tests/t.sh"   # H2b: vắng ở cây scratch nhưng còn ở head -> vẫn loại (luật head, không chỉ luật scratch)
install "$TMP/h2.json" --base main
[ ! -f "$DEST" ] && grep -q "file còn ở head" "$TMP/err" && ok "H2b: deleted cho file còn ở head dù scratch không có -> loại" || fail "H2b: file còn ở head vẫn ghi"
git -C "$SCR" restore --source=HEAD --worktree tests/t.sh

# H3
meta "$TMP/h3.json" tests/ghost.sh deleted
install "$TMP/h3.json" --base main
[ ! -f "$DEST" ] && grep -q "không có ở merge-base" "$TMP/err" && ok "H3a: deleted cho file không có ở merge-base -> loại" || fail "H3a: file thêm rồi xoá vẫn ghi"
meta "$TMP/h3b.json" tests/bia.sh deleted
install "$TMP/h3b.json" --base main
[ ! -f "$DEST" ] && grep -q "không có ở merge-base" "$TMP/err" && ok "H3b: deleted cho tên bịa -> loại" || fail "H3b: tên bịa vẫn ghi"

meta "$TMP/h6.json" tests/dir.sh deleted   # H6: ở merge-base là thư mục (tree), không phải test đã có
install "$TMP/h6.json" --base main
[ ! -f "$DEST" ] && grep -q "không có ở merge-base" "$TMP/err" && ok "H6: deleted cho thư mục ở merge-base -> loại" || fail "H6: thư mục vẫn ghi"

# H4
install "$TMP/h1.json"
[ ! -f "$DEST" ] && grep -q "cần --top và --base" "$TMP/err" && ok "H4: thiếu --base -> mục deleted bị loại" || fail "H4: thiếu --base vẫn ghi"

# H5
printf '#!/bin/sh\ntrue # old\n' > "$SCR/tests/old.sh"
install "$TMP/h1.json" --base main
[ ! -f "$DEST" ] && grep -q "còn ở cây scratch" "$TMP/err" && ok "H5: file có ở cây scratch -> loại" || fail "H5: file có ở scratch vẫn ghi"
rm -f "$SCR/tests/old.sh"

# E1-E3: --edited-unchanged
rc=0; bash "$INS" --edited-unchanged "$TMP/h1.json" "$HEAD_SHA" --top "$IR" --base main >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "E1: --edited-unchanged nhận mục deleted khi main không đổi file" || fail "E1: rc=$rc"
rc=0; bash "$INS" --edited-unchanged "$TMP/h2.json" "$HEAD_SHA" --top "$IR" --base main >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "E3: --edited-unchanged từ chối deleted cho file còn ở head" || fail "E3: rc=$rc"
rc=0; bash "$INS" --edited-unchanged "$TMP/h3.json" "$HEAD_SHA" --top "$IR" --base main >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "E4: --edited-unchanged từ chối deleted cho file không có ở merge-base" || fail "E4: rc=$rc"
printf '#!/bin/sh\ntrue # main sửa\n' > "$IR/tests/old.sh"; g commit -qam "main sửa old.sh"
rc=0; bash "$INS" --edited-unchanged "$TMP/h1.json" "$HEAD_SHA" --top "$IR" --base main >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "E2: main sửa file sau fork -> --edited-unchanged exit 1" || fail "E2: rc=$rc"

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
