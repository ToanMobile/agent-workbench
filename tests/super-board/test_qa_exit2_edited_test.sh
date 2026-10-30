#!/usr/bin/env bash
# #643: QA exit 2 chỉ vì test đã có bị sửa thì đi Review (không Blocked, không needs-you),
# rồi merge nhờ duyệt chéo. Chạy offline với gh giả. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export ROOT
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

CLS="$ROOT/.claude/bin/super-board-qa-exit2.sh"
INS="$ROOT/.claude/bin/super-board-install-edited-test-approval.sh"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
TRAIN="$ROOT/.claude/bin/super-board-merge-train.sh"
TASK=T0643-qa-exit2-edited

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qa-exit2.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
export DEVKIT_PM_HOME_TEST=1

BASEJ="$TMP/base.json"
cat > "$BASEJ" <<'JSON'
{"exit_code":2,"test_mode":"full","tests_touched":["tests/t.sh"],"matrix_problem":null,"unreadable":[],"uncovered":[],"orphan_tests":[],"findings":[],"regression_tests":[{"matrix_added":false,"status":"UNTESTED","label":"EDITED","mode":"edited"}],"busy":false,"budget_exhausted":false}
JSON

classify() {
  local root="${1:-}"
  if [ -n "$root" ]; then bash "$CLS" --root "$root"; else bash "$CLS"; fi
}

# mut <mã python sửa object o> — in JSON một dòng
mut() {
  python3 -c '
import json, sys
o = json.load(open(sys.argv[1]))
exec(sys.argv[2])
json.dump(o, sys.stdout)
' "$BASEJ" "$1"
}

want() {
  local exp="$1" label="$2" code="$3" root="${4:-}" got
  got=$(mut "$code" | classify "$root" 2>/dev/null) || true
  [ "$got" = "$exp" ] && ok "$label" || fail "$label: muốn $exp được '${got:-<rỗng>}'"
}

# ── 1. Phân loại JSON ────────────────────────────────────────────────────
if [ ! -f "$CLS" ]; then
  fail "thiếu $CLS"
else
  rc=0
  printf '%s\n' '{"exit_code":0}' | bash "$CLS" >/dev/null || rc=$?
  [ "$rc" -eq 0 ] && ok "script phân loại luôn thoát 0" || fail "script phân loại thoát $rc (muốn 0)"

  want review 'test_mode full + suite edited → review' 'pass'
  want review 'test_mode impacted → review' 'o["test_mode"]="impacted"'
  want qa-fail 'test_mode none → qa-fail' 'o["test_mode"]="none"'
  want qa-fail 'uncovered không rỗng → qa-fail' 'o["uncovered"]=["src/a"]'
  want qa-fail 'orphan không rỗng → qa-fail' 'o["orphan_tests"]=["tests/x.sh"]'
  want qa-fail 'findings không rỗng → qa-fail' 'o["findings"]=[{"id":"x"}]'
  want qa-fail 'unreadable không rỗng → qa-fail' 'o["unreadable"]=["a"]'
  want qa-fail 'SLOT (UNTESTED, label khác EDITED) → qa-fail' 'o["regression_tests"]=[{"matrix_added":False,"status":"UNTESTED","label":"SLOT"}]'
  want pass 'exit 0 → pass kể cả thiếu khoá khác' 'o.clear(); o["exit_code"]=0'
  want qa-fail 'exit 1 → qa-fail' 'o["exit_code"]=1'
  want qa-fail 'thiếu exit_code → qa-fail' 'del o["exit_code"]'
  want qa-fail 'thiếu tests_touched khi exit 2 → qa-fail' 'del o["tests_touched"]'
  want review 'matrix_problem chuỗi rỗng → review' 'o["matrix_problem"]=""'
  want qa-fail 'matrix_problem có chữ → qa-fail' 'o["matrix_problem"]="x"'
  want qa-fail 'busy true → qa-fail' 'o["busy"]=True'
  want qa-fail 'budget_exhausted true → qa-fail' 'o["budget_exhausted"]=True'
  want qa-fail 'regression_tests rỗng → qa-fail' 'o["regression_tests"]=[]'
  want qa-fail 'mọi matrix_added đúng true → qa-fail' 'o["regression_tests"]=[{"matrix_added":True,"status":"UNTESTED","label":"EDITED"}]'
  want review 'thiếu matrix_added tính là không true → review' 'o["regression_tests"]=[{"status":"UNTESTED","label":"EDITED"}]'

  mkdir -p "$TMP/root/tests"
  printf '#!/bin/sh\ntrue\n' > "$TMP/root/tests/t.sh"
  want review 'path còn file dưới --root → review' 'pass' "$TMP/root"
  want qa-fail 'test bị xoá (--root không -f) → qa-fail' 'o["tests_touched"]=["tests/gone.sh"]' "$TMP/root"

  got=$( { echo "dòng chữ trước JSON"; cat "$BASEJ"; } | classify 2>/dev/null) || true
  [ "$got" = review ] && ok "vẫn lấy dòng JSON sau lời văn" || fail "lời văn trước JSON: muốn review được '${got:-<rỗng>}'"

  # Ca thật: mini-repo chỉ sửa một test đã commit. Không nới luật phân loại.
  RG="$TMP/real"
  mkdir -p "$RG/tests" "$RG/.agents"
  git init -q -b main "$RG"
  git -C "$RG" config user.email t@example.invalid
  git -C "$RG" config user.name t
  git -C "$RG" config commit.gpgsign false
  cat > "$RG/.agents/regression_matrix.active.json" <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["tests/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/test_old.sh","parallel_safe":true}]}]}
JSON
  printf '#!/bin/sh\ntrue\n' > "$RG/tests/test_old.sh"
  chmod +x "$RG/tests/test_old.sh"
  git -C "$RG" add -A
  git -C "$RG" commit -qm init
  printf '#!/bin/sh\nexit 0\n' > "$RG/tests/test_old.sh"
  GATE_OUT="$TMP/real-gate.out"
  (
    cd "$RG" || exit 1
    unset TARGET_DIR DEVKIT_AGENT_ID DEVKIT_AUTO_APPROVE_TESTS GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK
    unset ANTIGRAVITY_PM_STATE_HOME DEVKIT_PM_HOME_TEST
    export CLAUDE_PROJECT_DIR="$RG" HOME="$TMP/home-gate"
    mkdir -p "$HOME"
    python3 "$ROOT/universal-agent-devkit/bin/post-fix-gate.py" --run-tests --brief --json
  ) >"$GATE_OUT" 2>&1 || true
  got=$(classify "$RG" <"$GATE_OUT" 2>/dev/null) || true
  if [ "$got" = review ]; then
    ok "gate thật trên test đã sửa → review"
  else
    fail "gate thật: muốn review được '${got:-<rỗng>}'"
    echo "---- JSON gate thật ----" >&2
    grep -a 'exit_code' "$GATE_OUT" | tail -3 >&2 || true
    echo "---- đuôi log ----" >&2
    tail -25 "$GATE_OUT" >&2 || true
  fi
fi

# ── 2. --has-edited-tests ────────────────────────────────────────────────
SHA_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
SHA_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
DIGEST=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

has_et() {
  # $1 meta $2 sha → in "rc word"
  local out rc=0
  out=$(bash "$INS" --has-edited-tests "$1" "$2" 2>/dev/null) || rc=$?
  printf '%s %s' "$rc" "$out"
}

if [ ! -f "$INS" ]; then
  fail "thiếu $INS"
else
  # true: MEMBER, đúng sha, mảng khác rỗng, trường 3 là task:
  python3 - "$TMP/m.json" "$SHA_A" "$DIGEST" "$TASK" <<'PY'
import json, sys
path, sha, digest, task = sys.argv[1:5]
body = (
    "approved-head:%s\n"
    "approved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp643\"}\n"
    "edited-tests: [{\"path\":\"tests/t.sh\",\"sha256\":\"%s\",\"reviewer\":\"antigravity\",\"author\":\"claude-lane\",\"task_id\":\"%s\",\"reason\":\"chỉ sửa test cũ\"}]\n"
) % (sha, task, digest, task)
json.dump({"comments": [{"authorAssociation": "MEMBER", "body": body}]}, open(path, "w"))
PY
  got=$(has_et "$TMP/m.json" "$SHA_A")
  [ "$got" = "0 true" ] && ok "comment thắng cuộc đúng sha → true" || fail "comment thắng cuộc: muốn '0 true' được '$got'"

  # comment cũ bị comment sau (không có edited-tests) thế chỗ
  python3 - "$TMP/m.json" "$SHA_A" "$SHA_B" "$DIGEST" "$TASK" <<'PY'
import json, sys
path, old, new, digest, task = sys.argv[1:6]
def full(sha):
    return (
        "approved-head:%s\n"
        "approved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp643\"}\n"
        "edited-tests: [{\"path\":\"tests/t.sh\",\"sha256\":\"%s\",\"reviewer\":\"antigravity\",\"author\":\"claude-lane\",\"task_id\":\"%s\",\"reason\":\"chỉ sửa test cũ\"}]\n"
    ) % (sha, task, digest, task)
later = (
    "approved-head:%s\n"
    "approved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp643\"}\n"
) % (new, task)
json.dump({"comments": [
    {"authorAssociation": "OWNER", "body": full(old)},
    {"authorAssociation": "OWNER", "body": later},
]}, open(path, "w"))
PY
  got=$(has_et "$TMP/m.json" "$SHA_A")
  [ "$got" = "1 false" ] && ok "comment mới không có edited-tests → false" || fail "comment bị thế: muốn '1 false' được '$got'"

  # thảo luận NONE đứng sau không thắng
  python3 - "$TMP/m.json" "$SHA_A" "$DIGEST" "$TASK" <<'PY'
import json, sys
path, sha, digest, task = sys.argv[1:5]
body = (
    "approved-head:%s\n"
    "approved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp643\"}\n"
    "edited-tests: [{\"path\":\"tests/t.sh\",\"sha256\":\"%s\",\"reviewer\":\"antigravity\",\"author\":\"claude-lane\",\"task_id\":\"%s\",\"reason\":\"chỉ sửa test cũ\"}]\n"
) % (sha, task, digest, task)
json.dump({"comments": [
    {"authorAssociation": "OWNER", "body": body},
    {"authorAssociation": "NONE", "body": "approved-head:%s\nthảo luận" % sha},
]}, open(path, "w"))
PY
  got=$(has_et "$TMP/m.json" "$SHA_A")
  [ "$got" = "0 true" ] && ok "comment thảo luận không thắng → true" || fail "thảo luận: muốn '0 true' được '$got'"

  # mảng rỗng
  python3 - "$TMP/m.json" "$SHA_A" "$TASK" <<'PY'
import json, sys
path, sha, task = sys.argv[1:4]
body = (
    "approved-head:%s\n"
    "approved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp643\"}\n"
    "edited-tests: []\n"
) % (sha, task)
json.dump({"comments": [{"authorAssociation": "OWNER", "body": body}]}, open(path, "w"))
PY
  got=$(has_et "$TMP/m.json" "$SHA_A")
  [ "$got" = "1 false" ] && ok "mảng rỗng → false" || fail "mảng rỗng: muốn '1 false' được '$got'"

  # lệch sha
  got=$(has_et "$TMP/m.json" "$SHA_B")
  # file hiện là empty-array của SHA_A; viết lại full rồi hỏi SHA_B
  python3 - "$TMP/m.json" "$SHA_A" "$DIGEST" "$TASK" <<'PY'
import json, sys
path, sha, digest, task = sys.argv[1:5]
body = (
    "approved-head:%s\n"
    "approved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp643\"}\n"
    "edited-tests: [{\"path\":\"tests/t.sh\",\"sha256\":\"%s\",\"reviewer\":\"antigravity\",\"author\":\"claude-lane\",\"task_id\":\"%s\",\"reason\":\"x\"}]\n"
) % (sha, task, digest, task)
json.dump({"comments": [{"authorAssociation": "OWNER", "body": body}]}, open(path, "w"))
PY
  got=$(has_et "$TMP/m.json" "$SHA_B")
  [ "$got" = "1 false" ] && ok "lệch sha → false" || fail "lệch sha: muốn '1 false' được '$got'"

  # approved-head không có dòng edited-tests
  python3 - "$TMP/m.json" "$SHA_A" "$TASK" <<'PY'
import json, sys
path, sha, task = sys.argv[1:4]
body = "approved-head:%s\napproved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp643\"}\n" % (sha, task)
json.dump({"comments": [{"authorAssociation": "OWNER", "body": body}]}, open(path, "w"))
PY
  got=$(has_et "$TMP/m.json" "$SHA_A")
  [ "$got" = "1 false" ] && ok "không có dòng edited-tests → false" || fail "không dòng: muốn '1 false' được '$got'"

  # bare OWNER dù có edited-tests: trường 3 là owner
  python3 - "$TMP/m.json" "$SHA_A" "$DIGEST" "$TASK" <<'PY'
import json, sys
path, sha, digest, task = sys.argv[1:5]
body = "approved-head:%s\nedited-tests: [{\"path\":\"tests/t.sh\",\"sha256\":\"%s\",\"reviewer\":\"antigravity\",\"author\":\"claude-lane\",\"task_id\":\"%s\",\"reason\":\"x\"}]\n" % (sha, digest, task)
json.dump({"comments": [{"authorAssociation": "OWNER", "body": body}]}, open(path, "w"))
PY
  got=$(has_et "$TMP/m.json" "$SHA_A")
  [ "$got" = "1 false" ] && ok "bare owner → false" || fail "bare owner: muốn '1 false' được '$got'"

  # một comment cũ vẫn là comment thắng cuộc
  python3 - "$TMP/m.json" "$SHA_A" "$DIGEST" "$TASK" <<'PY'
import json, sys
path, sha, digest, task = sys.argv[1:5]
body = (
    "approved-head:%s\n"
    "approved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp643\"}\n"
    "edited-tests: [{\"path\":\"tests/t.sh\",\"sha256\":\"%s\",\"reviewer\":\"antigravity\",\"author\":\"claude-lane\",\"task_id\":\"%s\",\"reason\":\"chỉ sửa test cũ\"}]\n"
) % (sha, task, digest, task)
json.dump({"comments": [{"authorAssociation": "COLLABORATOR", "body": body}]}, open(path, "w"))
PY
  got=$(has_et "$TMP/m.json" "$SHA_A")
  [ "$got" = "0 true" ] && ok "một comment cũ vẫn thắng → true" || fail "comment cũ đơn: muốn '0 true' được '$got'"
fi

# ── 3. Cài duyệt vào linked worktree ─────────────────────────────────────
pm_task() { # $1 project $2 sha
  mkdir -p "$TMP/pm/projects/p-$TASK/tasks/$TASK"
  python3 -c '
import json, sys
json.dump({"id": sys.argv[1], "project": sys.argv[2], "verdicts": {"audit": {
    "verdict": "pass", "round": 1, "reviewer": "pm", "notes": "audit ok\nauditedHead: %s" % sys.argv[3]
}}}, open(sys.argv[4], "w"))
' "$TASK" "$1" "$2" "$TMP/pm/projects/p-$TASK/tasks/$TASK/task.json"
}

if [ -f "$INS" ]; then
  IR="$TMP/irepo"
  git init -q -b main "$IR"
  git -C "$IR" config user.email t@example.invalid
  git -C "$IR" config user.name t
  git -C "$IR" config commit.gpgsign false
  mkdir -p "$IR/tests"
  printf '#!/bin/sh\ntrue\n' > "$IR/tests/t.sh"
  printf '#!/bin/sh\ntrue\n' > "$IR/tests/other.sh"
  git -C "$IR" add tests
  git -C "$IR" commit -qm init
  ISHA=$(git -C "$IR" rev-parse HEAD)
  IDIG=$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$IR/tests/t.sh")
  ODIG=$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$IR/tests/other.sh")
  git -C "$IR" worktree add -q --detach "$TMP/iscratch" "$ISHA"
  SCR="$TMP/iscratch"
  pm_task "$IR" "$ISHA"
  GP=$(git -C "$SCR" rev-parse --path-format=absolute --git-path info/exclude)
  AGD=$(git -C "$SCR" rev-parse --absolute-git-dir)
  [ "$GP" != "$AGD/info/exclude" ] && ok "linked worktree: git-path khác absolute-git-dir" \
    || fail "fixture không tách git-path ($GP vs $AGD)"

  mkdir -p "$AGD/info" "$SCR/.claude/audit-gate"
  printf '%s\n' '.claude/audit-gate/' > "$AGD/info/exclude"
  printf '{}\n' > "$SCR/.claude/audit-gate/approved_tests.json"
  if git -C "$SCR" check-ignore -q -- .claude/audit-gate/approved_tests.json; then
    fail "đối chứng: absolute-git-dir/info/exclude đã che file (không được)"
  else
    ok "đối chứng: absolute-git-dir/info/exclude không che file"
  fi
  git -C "$SCR" status --porcelain --untracked-files=all | grep -q 'approved_tests.json' \
    && ok "đối chứng: status vẫn thấy file" || fail "đối chứng: status không thấy file"
  rm -f "$SCR/.claude/audit-gate/approved_tests.json"
  printf '\n' > "$AGD/info/exclude"

  entry() {
    python3 -c '
import json, sys
path, digest, reviewer, author, task, reason = sys.argv[1:7]
print(json.dumps({"path": path, "sha256": digest, "reviewer": reviewer, "author": author, "task_id": task, "reason": reason}))
' "$1" "$2" "$3" "$4" "$5" "$6"
  }
  make_meta() {
    # $1 out  $2 sha  $3 json-array
    python3 -c '
import json, sys
out, sha, task, arr = sys.argv[1:5]
body = "approved-head:%s\napproved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp643\"}\nedited-tests: %s\n" % (sha, task, arr)
json.dump({"comments": [{"authorAssociation": "OWNER", "body": body}]}, open(out, "w"))
' "$1" "$2" "$TASK" "$3"
  }

  # audit lệch → không tạo file, thoát 0
  pm_task "$IR" "$SHA_A"
  make_meta "$TMP/bad-audit.json" "$ISHA" "[$(entry tests/t.sh "$IDIG" antigravity claude-lane "$TASK" 'chỉ sửa test cũ')]"
  rc=0
  bash "$INS" --scratch "$SCR" --sha "$ISHA" --meta "$TMP/bad-audit.json" --pr 7 --top "$IR" || rc=$?
  [ "$rc" -eq 0 ] && [ ! -f "$SCR/.claude/audit-gate/approved_tests.json" ] \
    && ok "audit lệch: không ghi, thoát 0" || fail "audit lệch: rc=$rc file=$( [ -f "$SCR/.claude/audit-gate/approved_tests.json" ] && echo có || echo không )"

  # toàn mục sai, file chưa có → không tạo
  pm_task "$IR" "$ISHA"
  bad=$(entry ../x "$IDIG" antigravity claude-lane "$TASK" 'x')
  make_meta "$TMP/allbad.json" "$ISHA" "[$bad]"
  rc=0
  bash "$INS" --scratch "$SCR" --sha "$ISHA" --meta "$TMP/allbad.json" --top "$IR" || rc=$?
  [ "$rc" -eq 0 ] && [ ! -f "$SCR/.claude/audit-gate/approved_tests.json" ] \
    && ok "mục sai hết: không tạo file, thoát 0" || fail "mục sai hết: rc=$rc"

  good=$(entry tests/t.sh "$IDIG" antigravity claude-lane "$TASK" 'chỉ sửa test cũ')
  badsha=$(entry tests/t.sh 0000000000000000000000000000000000000000000000000000000000000000 antigravity claude-lane "$TASK" 'x')
  same=$(entry tests/other.sh "$ODIG" claude-lane claude-lane "$TASK" 'tự duyệt')
  wrongtask=$(entry tests/other.sh "$ODIG" antigravity claude-lane T0643-khac 'x')
  make_meta "$TMP/mix.json" "$ISHA" "[$good,$bad,$badsha,$same,$wrongtask]"
  rc=0
  bash "$INS" --scratch "$SCR" --sha "$ISHA" --meta "$TMP/mix.json" --pr 7 --top "$IR" || rc=$?
  [ "$rc" -eq 0 ] && ok "cài lần một thoát 0" || fail "cài lần một thoát $rc"
  python3 -c '
import json, sys
p=sys.argv[1]
d=json.load(open(p))
a=d["approvals"]
assert len(a)==1 and a[0]["path"]=="tests/t.sh" and a[0]["sha256"]==sys.argv[2]
assert a[0]["reviewer"]=="antigravity" and a[0]["task_id"]==sys.argv[3]
' "$SCR/.claude/audit-gate/approved_tests.json" "$IDIG" "$TASK" \
    && ok "chỉ mục hợp lệ được ghi" || fail "file duyệt không chỉ còn tests/t.sh"
  git -C "$SCR" check-ignore -q -- .claude/audit-gate/approved_tests.json \
    && ok "check-ignore thấy file duyệt" || fail "check-ignore không thấy file duyệt"
  grep -qxF '.claude/audit-gate/' "$GP" && ok "dòng exclude nằm ở git-path" || fail "git-path exclude thiếu dòng ($GP)"
  if [ -f "$AGD/info/exclude" ] && grep -qxF '.claude/audit-gate/' "$AGD/info/exclude"; then
    fail "installer ghi nhầm absolute-git-dir/info/exclude"
  else
    ok "absolute-git-dir/info/exclude không có dòng exclude"
  fi
  if git -C "$SCR" status --porcelain --untracked-files=all | grep -q 'approved_tests.json'; then
    fail "git status scratch vẫn thấy file duyệt"
  else
    ok "git status scratch không thấy file duyệt"
  fi

  # gộp lần hai theo path
  other=$(entry tests/other.sh "$ODIG" antigravity claude-lane "$TASK" 'file thứ hai')
  upd=$(entry tests/t.sh "$IDIG" antigravity claude-lane "$TASK" 'cập nhật lý do')
  make_meta "$TMP/mix2.json" "$ISHA" "[$upd,$other]"
  bash "$INS" --scratch "$SCR" --sha "$ISHA" --meta "$TMP/mix2.json" --pr 7 --top "$IR"
  python3 -c '
import json, sys
a=json.load(open(sys.argv[1]))["approvals"]
paths=[x["path"] for x in a]
assert paths.count("tests/t.sh")==1 and "tests/other.sh" in paths, paths
t=[x for x in a if x["path"]=="tests/t.sh"][0]
assert t["reason"]=="cập nhật lý do"
' "$SCR/.claude/audit-gate/approved_tests.json" \
    && ok "lần hai gộp theo path, không nhân đôi" || fail "gộp lần hai sai"
fi

# ── 4 + 5. merge-gate và merge-train ─────────────────────────────────────
O="$TMP/origin.git"
R="$TMP/repo"
W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid
git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false
printf '#!/bin/sh\ntrue\n' > "$TMP/t.sh.body"
mkdir -p "$R/tests"
cp "$TMP/t.sh.body" "$R/tests/t.sh"
printf '/.claude/worktrees/\n' > "$R/.gitignore"
echo a > "$R/a"
git -C "$R" add .gitignore a tests/t.sh
git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main
TDIG=$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$R/tests/t.sh")
mkdir -p "$W"
git -C "$R" worktree add -q --detach "$W/review" origin/main

pm_for() { pm_task "$R" "$1"; }

write_pr_meta() {
  # $1 n  $2 file  $3 head  $4 edited(1|0)
  # Đếm đúng dòng +/- của diff: sau khi merge, sửa file cũ không còn là file mới (additions 1, deletions 0).
  python3 -c '
import json, sys
n, file, sha, edited, digest, task, dest, diffp = sys.argv[1:9]
added = removed = 0
for line in open(diffp, encoding="utf-8", errors="surrogateescape"):
    if line.startswith("+++ ") or line.startswith("--- "):
        continue
    if line.startswith("+"):
        added += 1
    elif line.startswith("-"):
        removed += 1
meta = {"files": [{"path": file}], "labels": [], "body": "", "additions": added, "deletions": removed, "changedFiles": 1, "author": {"login": "builder"}}
if edited == "1":
    body = (
        "approved-head:%s\n"
        "approved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp643\"}\n"
        "edited-tests: [{\"path\":\"tests/t.sh\",\"sha256\":\"%s\",\"reviewer\":\"antigravity\",\"author\":\"claude-lane\",\"task_id\":\"%s\",\"reason\":\"chỉ sửa test cũ\"}]\n"
    ) % (sha, task, digest, task)
    meta["comments"] = [{"authorAssociation": "OWNER", "body": body}]
json.dump(meta, open(dest, "w"))
' "$1" "$2" "$3" "$4" "$TDIG" "$TASK" "$TMP/pr$1.meta" "$TMP/pr$1.diff"
}

card_branch() {
  # $1 n  $2 file  $3 edited(optional)
  local n="$1" file="$2" edited="${3:-0}"
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$n-x" origin/main 2>/dev/null || git -C "$R" branch -q -f "issue-$n-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$n-build" "issue-$n-x"
  echo "$n" > "$W/issue-$n-build/$file"
  git -C "$W/issue-$n-build" add "$file"
  git -C "$W/issue-$n-build" commit -qm "card $n"
  git -C "$R" push -q origin "issue-$n-x"
  git -C "$R" rev-parse "issue-$n-x" > "$TMP/pr$n.head"
  git -C "$R" diff "origin/main" "issue-$n-x" > "$TMP/pr$n.diff"
  write_pr_meta "$n" "$file" "$(cat "$TMP/pr$n.head")" "$edited"
  [ "$edited" = 1 ] && pm_for "$(cat "$TMP/pr$n.head")"
}

advance_main() {
  git -C "$R" fetch -q origin
  git -C "$R" worktree add -q --detach "$W/adv" origin/main
  echo adv >> "$W/adv/a"
  git -C "$W/adv" add a
  git -C "$W/adv" commit -qm "main moves"
  git -C "$W/adv" push -q origin HEAD:main
  git -C "$R" worktree remove --force "$W/adv"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *"--json labels,files,comments"*)
    if [ -e "$FAKE_DIR/no_comments_api" ]; then echo "fake gh: comments unsupported" >&2; exit 1; fi
    cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr view "*"title"*) printf 'card\n' ;;
  *" pr view "*"body"*) printf '\n' ;;
  *" pr comment "*) exit 0 ;;
  *" pr merge "*)
    git -C "$FAKE_REPO" fetch -q origin main "issue-$n-x"
    tree=$(git -C "$FAKE_REPO" merge-tree --write-tree origin/main "$head") || exit 1
    c=$(git -C "$FAKE_REPO" commit-tree "$tree" -p origin/main -m "squash #$n")
    git -C "$FAKE_REPO" push -q origin "$c:refs/heads/main" && echo "$n" >> "$FAKE_DIR/merged" && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_CALLER SB_MERGE_QUEUE GH_TOKEN
export GH_TOKEN=fake-token

cat > "$TMP/verify.sh" <<SH
#!/bin/sh
echo x >> "$TMP/verify.count"
if [ -e need-approval ]; then
  python3 -c '
import hashlib, json, sys
want = hashlib.sha256(open("tests/t.sh","rb").read()).hexdigest()
try:
    data = json.load(open(".claude/audit-gate/approved_tests.json"))
except Exception:
    sys.exit(1)
ok = any(isinstance(a, dict) and a.get("path")=="tests/t.sh" and a.get("sha256")==want for a in (data.get("approvals") or []))
sys.exit(0 if ok else 1)
'
fi
SH
chmod +x "$TMP/verify.sh"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["sh %s/verify.sh"]}\n' "$TMP" > "$TMP/cfg.json"

runs() { if [ -f "$TMP/verify.count" ]; then wc -l < "$TMP/verify.count" | tr -d ' '; else echo 0; fi; }
reset_run() { rm -f "$TMP/verify.count" "$TMP/merged" "$TMP/halt.json"; }
branch_sha() { git -C "$O" rev-parse "refs/heads/$1"; }
merged_list() { sort "$TMP/merged" 2>/dev/null | tr '\n' ' '; }

run_gate() {
  # $1 pr  $2 extra args
  ( cd "$W/review" && bash "$GATE" --config "$TMP/cfg.json" --pr "$1" --expect-head "$(cat "$TMP/pr$1.head")" \
      --subject card --lock-timeout 20 $2 ) >"$TMP/gate.log" 2>&1
}

# Không duyệt, head chứa base → exit 11
card_branch 1 need-approval 0
reset_run
run_gate 1 ""
rc=$?
[ "$rc" -eq 11 ] && ok "không duyệt → exit 11" || fail "không duyệt: exit $rc (muốn 11): $(tail -8 "$TMP/gate.log")"
[ -z "$(merged_list)" ] && ok "không duyệt: không merge" || fail "không duyệt: đã merge"

# Duyệt hợp lệ, head chứa base → dry-run exit 0, không exit 11
card_branch 2 need-approval 1
reset_run
run_gate 2 "--dry-run"
rc=$?
[ "$rc" -eq 0 ] && ok "duyệt hợp lệ dry-run exit 0" || fail "duyệt hợp lệ: exit $rc (muốn 0): $(tail -12 "$TMP/gate.log")"
grep -q "verified green" "$TMP/gate.log" && ok "duyệt hợp lệ: verified green" || fail "duyệt hợp lệ: không thấy verified green: $(tail -8 "$TMP/gate.log")"

# Audit cũ hơn base, TRAIN_PROVED=0, không dry-run → exit 2, không fast-forward
card_branch 3 need-approval 1
advance_main
before=$(branch_sha issue-3-x)
reset_run
run_gate 3 ""
rc=$?
after=$(branch_sha issue-3-x)
[ "$rc" -eq 2 ] && ok "audit hết hạn TRAIN_PROVED=0 → exit 2" || fail "audit hết hạn: exit $rc (muốn 2): $(tail -12 "$TMP/gate.log")"
[ "$before" = "$after" ] && ok "exit 2 không fast-forward" || fail "exit 2 đã đẩy nhánh $before → $after"
grep -q "edited-test review is stale before fast-forward" "$TMP/gate.log" \
  && ok "exit 2 có câu stale" || fail "exit 2 thiếu câu stale"

# TRAIN_PROVED=1: không exit 2, dry-run, sha origin không đổi
card_branch 4 need-approval 1
advance_main
H4=$(cat "$TMP/pr4.head")
B4=$(git -C "$R" rev-parse "origin/main^{commit}")
tree=$(git -C "$R" merge-tree --write-tree "$B4" "$H4")
printf '%s %s\n' "$H4" "$tree" > "$TMP/receipt4"
before=$(branch_sha issue-4-x)
reset_run
run_gate 4 "--dry-run --train-receipt $TMP/receipt4"
rc=$?
after=$(branch_sha issue-4-x)
[ "$rc" -eq 0 ] && ok "TRAIN_PROVED=1 dry-run exit 0" || fail "TRAIN_PROVED=1: exit $rc (muốn 0): $(tail -12 "$TMP/gate.log")"
[ "$before" = "$after" ] && ok "TRAIN_PROVED=1 không đẩy nhánh" || fail "TRAIN_PROVED=1 đã đẩy nhánh"
if grep -q "edited-test review is stale before fast-forward" "$TMP/gate.log"; then
  fail "TRAIN_PROVED=1 vẫn in câu exit 2"
else
  ok "TRAIN_PROVED=1 không in câu exit 2"
fi

# Train: gh không hiểu comments → exit 0, merge, không 79
card_branch 10 f10 0
card_branch 11 f11 0
reset_run
touch "$TMP/no_comments_api"
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg.json" --prs 10,11 --lock-timeout 20 ) >"$TMP/t-nocmt.log" 2>&1
rc=$?
rm -f "$TMP/no_comments_api"
[ "$rc" -eq 0 ] && ok "gh không hiểu comments: train exit 0" || fail "gh không hiểu comments: exit $rc (muốn 0, không 79): $(tail -10 "$TMP/t-nocmt.log")"
[ "$(merged_list)" = "10 11 " ] && ok "gh không hiểu comments: cả hai merge" || fail "gh không hiểu comments: merged $(merged_list)"

# Một PR có duyệt: không đỏ vì test sửa
card_branch 12 need-approval 1
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg.json" --prs 12 --lock-timeout 20 ) >"$TMP/t-ok.log" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "một PR có duyệt: train exit 0" || fail "một PR có duyệt: exit $rc: $(tail -12 "$TMP/t-ok.log")"
if grep -q "train-red: 12" "$TMP/t-ok.log"; then fail "một PR có duyệt bị train-red"; else ok "một PR có duyệt không đỏ"; fi
[ "$(merged_list)" = "12 " ] && ok "một PR có duyệt đã merge" || fail "một PR có duyệt: merged $(merged_list)"

# Không duyệt → đỏ
card_branch 13 need-approval 0
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg.json" --prs 13 --lock-timeout 20 ) >"$TMP/t-red.log" 2>&1
rc=$?
[ "$rc" -eq 11 ] && ok "không duyệt trên train → exit 11" || fail "train không duyệt: exit $rc (muốn 11): $(tail -10 "$TMP/t-red.log")"
grep -q "train-red: 13" "$TMP/t-red.log" && ok "không duyệt: train-red" || fail "không duyệt: thiếu train-red"

# Hai PR, head chứa base hiện tại: một lần verify, cả hai merge
card_branch 14 f14 0
card_branch 15 need-approval 1
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg.json" --prs 14,15 --lock-timeout 20 ) >"$TMP/t-two.log" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "hai PR: train exit 0" || fail "hai PR: exit $rc: $(tail -12 "$TMP/t-two.log")"
[ "$(merged_list)" = "14 15 " ] && ok "hai PR: cả hai merge" || fail "hai PR: merged $(merged_list)"
[ "$(runs)" = 1 ] && ok "hai PR: verify đúng một lần" || fail "hai PR: verify $(runs) lần (muốn 1)"

# Audit edited-test cũ hơn base, trước chuỗi
card_branch 16 need-approval 1
advance_main
reset_run
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg.json" --prs 16 --lock-timeout 20 ) >"$TMP/t-stale.log" 2>&1
rc=$?
[ "$rc" -eq 2 ] && ok "train audit hết hạn → exit 2" || fail "train audit hết hạn: exit $rc (muốn 2): $(tail -12 "$TMP/t-stale.log")"
grep -q "^train-result: 16 gate-exit-2$" "$TMP/t-stale.log" && ok "train-result gate-exit-2" || fail "thiếu train-result gate-exit-2: $(grep train- "$TMP/t-stale.log")"
[ "$(runs)" = 0 ] && ok "audit hết hạn: chưa verify" || fail "audit hết hạn: verify đã chạy $(runs) lần"

# ── 6. Tài liệu + ma trận ────────────────────────────────────────────────
extract_pipe() {
  # Dừng ở marker end đầu tiên: file generator còn hai dòng regex chứa cả start lẫn end sau khối thật.
  awk '
    index($0, "<!-- universal-agent-devkit-workflow:start -->") && !on { on = 1 }
    on { print }
    index($0, "<!-- universal-agent-devkit-workflow:end -->") && on { exit }
  ' "$1"
}
P1="$TMP/pipe-run.md"
P2="$TMP/pipe-preamble.md"
P3="$TMP/pipe-factory.md"
extract_pipe "$ROOT/.claude/skills/super-board/references/run.md" > "$P1"
extract_pipe "$ROOT/.claude/skills/super-build/references/worker-preamble.md" > "$P2"
extract_pipe "$ROOT/universal-agent-devkit/docs/init_board/ai-factory-superboard-workflow.md" > "$P3"
cmp -s "$P1" "$P2" && ok "pipeline run.md khớp worker-preamble" || fail "pipeline run.md lệch worker-preamble"
cmp -s "$P1" "$P3" && ok "pipeline run.md khớp generator" || fail "pipeline run.md lệch generator"
grep -q 'Edited tests (await cross-review):' "$ROOT/.claude/skills/super-board/references/run.md" \
  && ok "run.md có câu Edited tests" || fail "run.md thiếu câu Edited tests (await cross-review):"
for f in \
  "$ROOT/.claude/skills/super-board/references/run.md" \
  "$ROOT/.claude/skills/super-qa/references/findings-and-green.md" \
  "$ROOT/.claude/skills/super-build/references/worker-preamble.md" \
  "$ROOT/.claude/skills/super-review/SKILL.md" \
  "$ROOT/.claude/skills/super-review/references/review-flow.md" \
  "$ROOT/universal-agent-devkit/docs/init_board/ai-factory-superboard-workflow.md"
do
  if grep -q 'super-board-qa-exit2.sh' "$f" && grep -q 'Review for Antigravity' "$f"; then
    ok "doc $(basename "$f") nêu script và Review for Antigravity"
  else
    fail "doc $(basename "$f") thiếu script hoặc Review for Antigravity"
  fi
done
EXC=$(awk '/Exception: the DevKit gate/,/Tests green/' "$ROOT/.claude/skills/super-board/references/run.md")
printf '%s\n' "$EXC" | grep -q 'do not demand QA exit 0' \
  && ok "ngoại lệ không đòi exit 0 khi chỉ vì test sửa" || fail "ngoại lệ vẫn đòi exit 0 vô điều kiện"
printf '%s\n' "$EXC" | grep -q 'merge-base --is-ancestor' && printf '%s\n' "$EXC" | grep -q 'jq -r .fp' \
  && printf '%s\n' "$EXC" | grep -q 'does not commit' \
  && ok "ngoại lệ có ancestor, jq -r .fp, không commit" || fail "ngoại lệ thiếu ancestor / jq -r .fp / does not commit"
QON=$(awk '/In place of steps 2/,/super-board-merge-queue.sh batches/' "$ROOT/.claude/skills/super-board/references/run.md")
printf '%s\n' "$QON" | grep -q 'edited-tests:' && printf '%s\n' "$QON" | grep -q 'jq -r .fp' \
  && ok "bước 1 queue bật có edited-tests và receipt" || fail "bước 1 queue bật thiếu edited-tests hoặc jq -r .fp"
BEF=$(awk '/\*\*Before the gate, post the approval\*\*/,/The runner reads the latest/' "$ROOT/.claude/skills/super-board/references/run.md")
printf '%s\n' "$BEF" | grep -q 'edited-tests:' && printf '%s\n' "$BEF" | grep -q 'THEN the merge gate' \
  && ok "trước gate: audit rồi comment rồi merge gate" || fail "đoạn trước gate thiếu edited-tests hoặc THEN the merge gate"
grep -q 'super-board-qa-exit2.sh' "$ROOT/.claude/skills/super-review/references/review-flow.md" \
  && grep -q 'merge-base --is-ancestor' "$ROOT/.claude/skills/super-review/references/review-flow.md" \
  && grep -q 'jq -r .fp' "$ROOT/.claude/skills/super-review/references/review-flow.md" \
  && grep -q 'does not commit' "$ROOT/.claude/skills/super-review/references/review-flow.md" \
  && ok "review-flow: ancestor, không commit, jq -r .fp" || fail "review-flow thiếu ancestor / không commit / jq"
grep -q 'edited-tests:' "$ROOT/.claude/skills/super-review/SKILL.md" \
  && grep -q 'THEN the merge gate' "$ROOT/.claude/skills/super-review/SKILL.md" \
  && grep -q 'jq -r .fp' "$ROOT/.claude/skills/super-review/SKILL.md" \
  && ok "SKILL.md: edited-tests, receipt, rồi merge gate" || fail "SKILL.md thiếu edited-tests / receipt / THEN the merge gate"

if python3 - <<'PY'
import json, os, sys
root = os.environ["ROOT"]
p = os.path.join(root, ".agents/regression_matrix.active.json")
d = json.load(open(p))
rules = d["rules"]
ids = [r.get("component") for r in rules]
if ids.count("qa-exit2-edited-test-643") != 1:
    sys.exit("id xuất hiện %s lần" % ids.count("qa-exit2-edited-test-643"))
mine = rules[ids.index("qa-exit2-edited-test-643")]
cmd = mine["mandatory_regression_tests"][0]["command"]
if cmd != "bash tests/super-board/test_qa_exit2_edited_test.sh":
    sys.exit("command %s" % cmd)
PY
then
  ok "ma trận: đúng một component qa-exit2-edited-test-643"
else
  fail "ma trận: thiếu, lặp hoặc sai lệnh component qa-exit2-edited-test-643"
fi

[ "$FAILS" -eq 0 ] && { echo "test_qa_exit2_edited_test: PASS"; exit 0; }
echo "test_qa_exit2_edited_test: $FAILS FAILED"
exit 1
