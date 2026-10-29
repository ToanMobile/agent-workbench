#!/usr/bin/env bash
# #629 (review PR #631): push_gate.AUDITED_HEAD và regex của pm_verdict (mcp-servers/antigravity-pm-mcp/src/tools.js) phải khớp
# cùng một tập chuỗi. `\s` của Python (str) khớp cả \x1c-\x1f và \x85, `\s` của JS thì không: notes `auditedHead:\x1f<sha>` lọt
# qua kiểm audit-agent.json của pm_verdict (JS không thấy head) nhưng push_gate.audited_head lại nhận sha đó -> duyệt test bị sửa
# mà không auditor nào audit. Đối chứng: `auditedHead: <sha>` (dấu cách thường) vẫn được nhận.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"   # biên bản giả dưới $TMP, không bao giờ ~/.antigravity-pm thật
export DEVKIT_PM_HOME_TEST=1
FAILS=0
mkdir -p "$TMP/repo" && cd "$TMP/repo" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
echo a > f && git add f && git commit -qm c1
SHA="$(git rev-parse HEAD)"
check() {   # check <tên> <phân cách giữa "auditedHead:" và sha (printf)> <kỳ vọng: sha|None>
  local tid="T0001-$1" sep
  sep="$(printf "$2")"
  mkdir -p "$TMP/pm/projects/p-$tid/tasks/$tid"
  python3 - "$TMP/pm/projects/p-$tid/tasks/$tid/task.json" "$tid" "$TMP/repo" "auditedHead:${sep}${SHA}" <<'PY'
import json, os, sys
path, tid, project, notes = sys.argv[1:5]
json.dump({"id": tid, "project": os.path.realpath(project),
           "verdicts": {"audit": {"verdict": "pass", "notes": "audit ok\n" + notes}}}, open(path, "w"))
PY
  local got
  got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(p.audited_head(sys.argv[2], sys.argv[3]))' \
    "$DEVKIT_DIR/bin" "$TMP/repo" "$tid" 2>&1)"
  local want="$3"; [ "$want" = sha ] && want="$SHA"
  if [ "$got" = "$want" ]; then echo "✔ $1: $got"; else echo "✖ $1: muốn $want, được $got"; FAILS=$((FAILS + 1)); fi
}
check space ' ' sha            # đối chứng: dấu cách thường vẫn duyệt
check tab '\t' sha             # tab: JS \s cũng khớp
check us '\037' None           # \x1f: JS \s không khớp -> gate không được nhận
check fs '\034' None           # \x1c
check nel '\302\205' None      # U+0085 (NEL)
[ "$FAILS" -eq 0 ] && echo "ALL OK" || { echo "FAILS=$FAILS"; exit 1; }
