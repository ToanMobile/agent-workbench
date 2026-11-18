#!/usr/bin/env bash
# Test #1328: merge queue nhận nguồn duyệt `claude-verify` (biên bản universal-agent-devkit/bin/claude_verify.py) ngoài antigravity-pm.
#  a  approved-by reviewer claude-verify + biên bản pass đúng head → jq ra `cv:<id>`, queue xếp train
#  b  queue loại: biên bản phiên builder, head khác, tree lệch, verdict fail, reviewer ngoài sổ, nhánh của thẻ khác; seal mode bật
#     (pubkey fixture trong thư mục tạm): không ký / chữ ký giả → loại, chữ ký đúng → nhận
#  c  đường antigravity cũ (`task:` + biên bản PM pass) vẫn nhận
#  d  `seal` từ chối: finding thiếu dòng, ngoài hunk, ngoài diff, snippet sai, severity lạ, head sai, base sai, nhánh không trỏ head,
#     phiên rỗng, phiên builder; (B) builder giả env phiên khác; (C) worktree build đã xoá mà builder tự seal; sổ builder rỗng;
#     reviewer không có trong sổ reviewers; git lỗi; kit thiếu push_gate.py → exit 3 không traceback; hai lần seal cùng giây không đè
#  e  run.sh review_approved_head và queue-label.sh chạy thật nhánh `cv:`; runner gán --session-id cho worker và ghi sổ trước khi chạy
#  f  hook guard merge-queue tính claude_verify.py là phụ thuộc của helper; SKILL.md nêu giới hạn của claude-verify
# Queue thật + jq thật + audit-check thật (symlink), gh giả, train/card stub. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
KIT="$ROOT/universal-agent-devkit/bin"
CV="$KIT/claude_verify.py"
JQF="$ROOT/.claude/bin/super-board-approved-head.jq"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
F="$TMP/fake"; R="$TMP/repo"; Q="$TMP/qbin"
mkdir -p "$F/labeled" "$Q" "$TMP/path" "$TMP/pm"
export CLAUDE_VERIFY_HOME="$TMP/cv" DEVKIT_PM_HOME_TEST=1 ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
unset DEVKIT_VERDICT_SEAL_PUB CLAUDE_CODE_SESSION_ID
CVRE='^CV[0-9]{8}T[0-9]{6}-[0-9a-f]{12}-[0-9a-f]{6}$'

# ── repo: main có src.py; mỗi thẻ N là nhánh issue-N-x sửa src.py. Worktree build của thẻ 21 giữ lock của phiên builder-sess.
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t; git -C "$R" config commit.gpgsign false
printf '.claude/\n' > "$R/.gitignore"; printf 'a = 1\nb = 2\nc = 3\n' > "$R/src.py"
git -C "$R" add .gitignore src.py; git -C "$R" commit -qm init
BASE=$(git -C "$R" rev-parse HEAD)
mkpr() {   # mkpr <N> <dòng thêm>: commit trên nhánh issue-N-x từ main, in sha
  git -C "$R" checkout -q -b "issue-$1-x" main
  printf 'a = 1\n%s\nb = 2\nc = 3\n' "$2" > "$R/src.py"; git -C "$R" commit -qam "pr $1"
  git -C "$R" rev-parse HEAD; git -C "$R" checkout -q main
}
H1=$(mkpr 21 'x = danger(1)'); H2=$(mkpr 22 'y = 2'); H3=$(mkpr 23 'z = 3'); H4=$(mkpr 24 'w = 4'); H5=$(mkpr 25 'v = 5')
H6=$(mkpr 26 'u = 6'); H7=$(mkpr 27 't = 7'); H8=$(mkpr 28 's = 8'); H9=$(mkpr 29 'r = 9'); H30=$(mkpr 30 'q = 30')
H31=$(mkpr 31 'p = 31')
git -C "$R" worktree add -q "$TMP/wt1" issue-21-x
printf '{"session_id":"builder-sess","heartbeat":0}' > "$(git -C "$TMP/wt1" rev-parse --absolute-git-dir)/devkit-session.lock"
# Sổ phiên do runner ghi lúc giao việc: thẻ 21..29, 31 có builder + reviewer; thẻ 30 chỉ có reviewer (sổ builder rỗng).
reg() { python3 "$CV" register --lane "$1" --repo "$R" --issue "$2" --session "$3"; }
REGRC=0
for n in 21 22 23 24 25 26 27 28 29 31; do reg build "$n" builder-sess || REGRC=$?; reg review "$n" reviewer-sess || REGRC=$?; done
reg review 30 reviewer-sess || REGRC=$?
[ "$REGRC" = 0 ] && ok "d-reg register ghi sổ builder/reviewer" || fail "d-reg register exit $REGRC"

# ── d. seal
report() {   # report <file> <head> <base> <findings JSON>
  jq -n --arg h "$2" --arg b "$3" --argjson f "$4" '{head:$h, base:$b, findings:$f, reviewed_at:"2026-11-19T00:00:00Z"}' > "$1"
}
seal() {   # seal <session> <head> <report> <branch> [repo]
  ( cd "$R" && CLAUDE_CODE_SESSION_ID="$1" python3 "$CV" seal --repo "${5:-$R}" --head "$2" --report "$3" --branch "$4" ) \
    > "$TMP/seal.out" 2> "$TMP/seal.err"
  SRC=$?; SID=$(sed -n 's/^task_id=\(CV[^ ]*\) .*/\1/p' "$TMP/seal.out")
}
refused() {   # refused <tên> <mã> <mẫu lời báo>
  { [ "$SRC" = "$2" ] && [ -z "$SID" ] && grep -q -- "$3" "$TMP/seal.err" && ! grep -q Traceback "$TMP/seal.err"; } \
    && ok "$1 (exit $2: $(head -c 100 "$TMP/seal.err"))" || fail "$1 rc=$SRC out=$(cat "$TMP/seal.out") err=$(head -c 300 "$TMP/seal.err")"
}
NIT='[{"id":"f1","severity":"nit","file":"src.py","line":2,"snippet":"danger(1)","class":"naming"}]'
report "$TMP/r-ok.json" "$H1" "$BASE" "$NIT"; seal reviewer-sess "$H1" "$TMP/r-ok.json" issue-21-x
{ [ "$SRC" = 0 ] && printf '%s' "$SID" | grep -Eq "$CVRE"; } \
  && ok "d0 seal: báo cáo đúng (nit trong hunk) → exit 0, task_id $SID" || fail "d0 rc=$SRC out=$(cat "$TMP/seal.out") err=$(cat "$TMP/seal.err")"
CV1="$SID"
seal reviewer-sess "$H1" "$TMP/r-ok.json" issue-21-x; CV1B="$SID"
{ [ "$SRC" = 0 ] && [ -n "$CV1B" ] && [ "$CV1B" != "$CV1" ] && [ -f "$CLAUDE_VERIFY_HOME/records/$CV1.json" ] && [ -f "$CLAUDE_VERIFY_HOME/records/$CV1B.json" ]; } \
  && ok "d-dup hai lần seal liền nhau (cùng giây) ra hai task_id, không đè biên bản" || fail "d-dup $CV1 / $CV1B rc=$SRC"
for c in 'noline|[{"id":"f1","severity":"nit","file":"src.py","snippet":"danger(1)"}]' \
         'outhunk|[{"id":"f1","severity":"important","file":"src.py","line":3,"snippet":"b = 2"}]' \
         'nofile|[{"id":"f1","severity":"nit","file":"other.py","line":1,"snippet":"x"}]' \
         'badsnip|[{"id":"f1","severity":"nit","file":"src.py","line":2,"snippet":"not there"}]' \
         'badsev|[{"id":"f1","severity":"blocker","file":"src.py","line":2,"snippet":"danger"}]'; do
  name=${c%%|*}; report "$TMP/r-bad.json" "$H1" "$BASE" "${c#*|}"; seal reviewer-sess "$H1" "$TMP/r-bad.json" issue-21-x
  refused "d-$name seal từ chối" 2 "finding"
done
report "$TMP/r-pre.json" "$H1" "$BASE" '[{"id":"p1","severity":"pre-existing","file":"src.py","line":3,"snippet":"b = 2"}]'
seal reviewer-sess "$H1" "$TMP/r-pre.json" issue-21-x; [ "$SRC" = 0 ] && ok "d-pre finding pre-existing ngoài hunk được nhận" || fail "d-pre rc=$SRC $(cat "$TMP/seal.err")"
report "$TMP/r-h.json" "$H2" "$BASE" '[]'; seal reviewer-sess "$H1" "$TMP/r-h.json" issue-21-x; refused "d-head báo cáo head khác --head" 2 "head"
report "$TMP/r-b.json" "$H1" "$H2" '[]'; seal reviewer-sess "$H1" "$TMP/r-b.json" issue-21-x; refused "d-base base không phải merge-base" 2 "merge-base"
seal reviewer-sess "$H1" "$TMP/r-ok.json" issue-22-x; refused "d-branch nhánh khai báo không trỏ tới head" 2 "issue-22-x"
seal "" "$H1" "$TMP/r-ok.json" issue-21-x; refused "d-sess CLAUDE_CODE_SESSION_ID rỗng" 2 "CLAUDE_CODE_SESSION_ID"
seal builder-sess "$H1" "$TMP/r-ok.json" issue-21-x; refused "d-self phiên builder tự niêm phong" 2 "builder"
report "$TMP/r-e.json" "$H2" "$BASE" '[]'
seal fake-sess "$H2" "$TMP/r-e.json" issue-22-x; refused "d-B builder đặt CLAUDE_CODE_SESSION_ID giả (không có trong sổ reviewers) → từ chối" 2 "reviewers"
report "$TMP/r-30.json" "$H30" "$BASE" '[]'
seal reviewer-sess "$H30" "$TMP/r-30.json" issue-30-x; refused "d-empty sổ builder của thẻ rỗng → từ chối (fail closed)" 2 "builder"
# git lỗi: shim làm `git worktree list` hỏng
mkdir -p "$TMP/gitshim"; REALGIT=$(command -v git)
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = worktree ] && { echo "boom" >&2; exit 128; }; done\nexec "%s" "$@"\n' "$REALGIT" > "$TMP/gitshim/git"
chmod +x "$TMP/gitshim/git"
( cd "$R" && PATH="$TMP/gitshim:$PATH" CLAUDE_CODE_SESSION_ID=reviewer-sess python3 "$CV" seal --repo "$R" --head "$H2" --report "$TMP/r-e.json" --branch issue-22-x ) \
  > "$TMP/seal.out" 2> "$TMP/seal.err"; SRC=$?; SID=""
refused "d-git git worktree list lỗi → từ chối, không coi là không có builder" 3 "git"
# kit thiếu push_gate.py: lỗi nạp ra exit 3, không traceback
mkdir -p "$TMP/kit"; cp "$CV" "$KIT/verdict_seal.py" "$KIT/session_lock.py" "$TMP/kit/"
( cd "$R" && CLAUDE_CODE_SESSION_ID=reviewer-sess python3 "$TMP/kit/claude_verify.py" seal --repo "$R" --head "$H2" --report "$TMP/r-e.json" --branch issue-22-x ) \
  > "$TMP/seal.out" 2> "$TMP/seal.err"; SRC=$?; SID=""
refused "d-kit kit thiếu push_gate.py → exit 3, không traceback" 3 "push_gate"
# (C) worktree build đã xoá (luồng thường: dọn trước QA/Review), lock mất: builder vẫn bị chặn nhờ sổ runner.
git -C "$R" worktree remove --force "$TMP/wt1"
seal builder-sess "$H1" "$TMP/r-ok.json" issue-21-x; refused "d-C worktree build đã xoá: builder tự seal vẫn bị chặn (sổ builder)" 2 "builder"
seal reviewer-sess "$H1" "$TMP/r-ok.json" issue-21-x; CV1="$SID"
[ "$SRC" = 0 ] && [ "$(python3 -c 'import json,sys; print(json.loads(json.load(open(sys.argv[1]))["payload"])["builder_session"])' "$CLAUDE_VERIFY_HOME/records/$CV1.json")" = builder-sess ] \
  && ok "d-C2 worktree đã xoá: reviewer seal được, biên bản ghi builder từ sổ" || fail "d-C2 rc=$SRC $(cat "$TMP/seal.err")"
report "$TMP/r-imp.json" "$H5" "$BASE" '[{"id":"i1","severity":"important","file":"src.py","line":2,"snippet":"v = 5"}]'
seal reviewer-sess "$H5" "$TMP/r-imp.json" issue-25-x; CV5="$SID"
[ "$SRC" = 4 ] && [ -n "$CV5" ] && ok "d-imp finding important → biên bản verdict fail (exit 4)" || fail "d-imp rc=$SRC"

# Biên bản viết tay (giả mạo / lệch) theo đúng dạng file của claude_verify.py.
record() {   # record <task_id> <head> <tree> <verdict> <reviewer> <issue> [seed hex ký]
  python3 - "$KIT" "$CLAUDE_VERIFY_HOME/records" "$@" <<'PY'
import base64, json, os, sys
sys.path.insert(0, sys.argv[1]); import verdict_seal as vs
d, tid, head, tree, verdict, rv, issue = sys.argv[2:9]
p = {"v": 1, "kind": "claude-verify", "task_id": tid, "head": head, "tree": tree, "base": "0" * 40, "verdict": verdict,
     "findings": [], "reviewer_session": rv, "builder_session": None, "issue": int(issue), "branch": f"issue-{issue}-x",
     "ts": "2026-11-19T00:00:00+00:00"}
s = json.dumps(p, sort_keys=True)
sig = base64.b64encode(vs.sign(bytes.fromhex(sys.argv[9]), s.encode())).decode() if len(sys.argv) > 9 else None
os.makedirs(d, exist_ok=True); json.dump({"payload": s, "sig": sig}, open(os.path.join(d, tid + ".json"), "w"))
PY
}
tree() { git -C "$R" rev-parse "$1^{tree}"; }
cvid() { printf 'CV20261119T0000%02d-%s-abcdef' "$1" "$(printf '%s' "$2" | cut -c1-12)"; }
CV2=$(cvid 2 "$H1"); record "$CV2" "$H1" "$(tree "$H1")" pass builder-sess 21      # biên bản do chính phiên builder viết
CV3=$(cvid 3 "$H3"); record "$CV3" "$H2" "$(tree "$H2")" pass reviewer-sess 22     # biên bản của head khác
CV4=$(cvid 4 "$H4"); record "$CV4" "$H4" "$(tree "$H3")" pass reviewer-sess 24     # tree lệch
CV10=$(cvid 10 "$H2"); record "$CV10" "$H2" "$(tree "$H2")" pass fake-sess 22      # reviewer không có trong sổ
CV11=$(cvid 11 "$H31"); record "$CV11" "$H31" "$(tree "$H31")" pass reviewer-sess 31   # đúng, nhưng PR khai nhánh thẻ khác

# ── a. jq ra cv:<id>
by() { jq -cn --arg r "$1" --arg t "$2" '{reviewer:$r,builder:"claude-builder",task_id:$t,gate_receipt:"receipt-1"}'; }
JQOUT=$(jq -n --arg b "approved-head:$H1
approved-by: $(by claude-verify "$CV1")" '{comments:[{authorAssociation:"MEMBER",body:$b}]}' | jq -r -f "$JQF")
[ "$JQOUT" = "$(printf 'ok\t%s\tcv:%s' "$H1" "$CV1")" ] && ok "a-jq approved-by claude-verify → ok <sha> cv:<id>" || fail "a-jq got: $JQOUT"
JQOUT=$(jq -n --arg b "approved-head:$H1
approved-by: $(by claude-verify "CV20261119T000000-${H1:0:12}")" '{comments:[{authorAssociation:"MEMBER",body:$b}]}' | jq -r -f "$JQF")
printf '%s' "$JQOUT" | grep -q "neither an antigravity-pm nor a claude-verify id" && ok "a-jq id CV dạng cũ (không hậu tố) → bad" || fail "a-jq bad id: $JQOUT"

# ── b9. check: mã exit và lời từ chối đúng
( cd "$R" && python3 "$CV" check "$CV1" "$H1" --top "$R" ) > /dev/null 2> "$TMP/chk.err"; CRC=$?
[ "$CRC" = 0 ] && ok "b0 check biên bản đúng → exit 0" || fail "b0 check rc=$CRC $(cat "$TMP/chk.err")"
( cd "$R" && DEVKIT_PM_HOME_TEST=0 python3 "$CV" check "$CV1" "$H1" --top "$R" ) > /dev/null 2> "$TMP/chk.err"; CRC=$?
{ [ "$CRC" = 1 ] && grep -q "CLAUDE_VERIFY_HOME" "$TMP/chk.err"; } && ok "b9 CLAUDE_VERIFY_HOME ngoài fixture → check exit 1, nêu lý do" \
  || fail "b9 rc=$CRC err=$(cat "$TMP/chk.err")"
( cd "$R" && python3 "$CV" check "$CV11" "$H31" --top "$R" --branch issue-29-x ) > /dev/null 2> "$TMP/chk.err"; CRC=$?
{ [ "$CRC" = 1 ] && grep -q "issue" "$TMP/chk.err"; } && ok "b10 check --branch của thẻ khác → exit 1" || fail "b10 rc=$CRC $(cat "$TMP/chk.err")"

# ── queue harness (rút gọn từ test_merge_queue.sh)
for f in super-board-merge-queue.sh super-board-github-read.py super-board-ac-check.py super-board-approved-head.jq super-board-audit-check.py; do
  ln -s "$ROOT/.claude/bin/$f" "$Q/$f"
done
printf '#!/usr/bin/env bash\necho "train $*" >> "$FAKE/calls"\n' > "$Q/super-board-merge-train.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$Q/super-board-card.sh"
printf 'import sys\n' > "$Q/super-board-needs-you.py"; printf 'import sys\n' > "$Q/super-board-notify.py"
chmod +x "$Q"/*.sh
cat > "$TMP/path/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
F = os.environ['FAKE']; a = sys.argv[1:]
def opt(n):
    return a[a.index(n) + 1] if n in a else None
def num():
    return next(x for x in a[2:] if x.isdigit())
if a[:2] == ['pr', 'list']:
    print(open(F + '/prs.json').read() if (opt('--state') or 'open') == 'open' else '[]')
elif a[:2] == ['pr', 'view'] and opt('--json') == 'comments':
    p = f'{F}/comments-{num()}.json'
    print(open(p).read() if os.path.exists(p) else '{"comments":[]}')
elif a[:2] == ['pr', 'view'] and 'url' in (opt('--json') or ''):
    n = num(); c = json.load(open(f'{F}/comments-{n}.json'))
    h = next(p['headRefOid'] for p in json.load(open(F + '/prs.json')) if str(p['number']) == n)
    print(json.dumps({'number': int(n), 'state': 'OPEN', 'url': f'https://github.com/acme/widgets/pull/{n}', 'headRefOid': h, **c}))
elif a[:2] == ['pr', 'view']:
    print(json.dumps({'body': '', 'headRefOid': 'a' * 40, 'title': 't', 'state': 'OPEN', 'mergeCommit': None}))
elif a[0] == 'api' and '/timeline' in a[1]:
    n = a[1].split('/issues/')[1].split('/')[0]
    print(json.dumps([[{'event': 'labeled', 'label': {'name': 'merge-queue'}, 'created_at': open(f'{F}/labeled/{n}').read().strip()}]]))
elif a[:2] == ['issue', 'view']:
    print(json.dumps({'number': int(num()), 'title': 'c', 'body': '', 'state': 'OPEN', 'labels': []}))
else:
    open(F + '/writes', 'a').write(' '.join(a) + '\n')
PY
chmod +x "$TMP/path/gh"
export PATH="$TMP/path:$PATH" FAKE="$F" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1 SB_MERGE_QUEUE=1
printf '{"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"worker_backend":"claude-p","rebuild_cap":2,"verify_commands":["true"],"merge_queue":{"enabled":true,"enabled_at":null,"max_trains":50}}\n' > "$TMP/cfg.json"
ROWS=""
pr() {   # pr <N> <head> <reviewer> <task_id> [nhánh]
  ROWS="${ROWS}${ROWS:+,}{\"number\":$1,\"headRefName\":\"${5:-issue-$((20 + $1))-x}\",\"headRefOid\":\"$2\",\"isDraft\":false,\"labels\":[{\"name\":\"merge-queue\"}],\"closingIssuesReferences\":[]}"
  printf '[%s]\n' "$ROWS" > "$F/prs.json"; echo "2026-11-19T00:00:00Z" > "$F/labeled/$1"
  jq -n --arg b "approved-head:$2
approved-by: $(by "$3" "$4")" '{comments:[{authorAssociation:"MEMBER",body:$b}]}' > "$F/comments-$1.json"
}
run_q() { ( cd "$R" && bash "$Q/super-board-merge-queue.sh" --config "$TMP/cfg.json" --wait --dry-run ) > "$TMP/out" 2>&1; OUT=$(cat "$TMP/out"); }
queued() { printf '%s' "$OUT" | grep -q -- "--prs $1:$2\$"; }
dropped() { printf '%s' "$OUT" | grep -q "drop PR #$1 "; }
mkdir -p "$TMP/pm/projects/p/tasks/T0006-agy"
jq -n --arg p "$R" --arg h "$H6" '{id:"T0006-agy",project:$p,verdicts:{audit:{verdict:"pass",reviewer:"pm",notes:("fixture\nauditedHead: "+$h)}}}' \
  > "$TMP/pm/projects/p/tasks/T0006-agy/task.json"

pr 1 "$H1" claude-verify "$CV1"; pr 2 "$H1" claude-verify "$CV2" issue-21-x; pr 3 "$H3" claude-verify "$CV3"
pr 4 "$H4" claude-verify "$CV4"; pr 5 "$H5" claude-verify "$CV5"; pr 6 "$H6" antigravity T0006-agy
pr 10 "$H2" claude-verify "$CV10" issue-22-x; pr 11 "$H31" claude-verify "$CV11" issue-29-x
run_q
queued 1 "$H1" && ok "a  queue: approved-by claude-verify + biên bản pass đúng head → xếp train" || fail "a  queue PR1: $OUT"
dropped 2 && ok "b1 queue: biên bản do phiên builder viết → loại" || fail "b1 PR2 not dropped: $OUT"
dropped 3 && ok "b2 queue: biên bản của head khác → loại" || fail "b2 PR3 not dropped: $OUT"
dropped 4 && ok "b3 queue: tree biên bản lệch tree(head) → loại" || fail "b3 PR4 not dropped: $OUT"
dropped 5 && ok "b4 queue: biên bản verdict fail → loại" || fail "b4 PR5 not dropped: $OUT"
dropped 10 && ok "b11 queue: reviewer của biên bản không có trong sổ reviewers → loại" || fail "b11 PR10 not dropped: $OUT"
dropped 11 && ok "b12 queue: nhánh PR thuộc thẻ khác thẻ của biên bản → loại" || fail "b12 PR11 not dropped: $OUT"
queued 6 "$H6" && ok "c  queue: đường antigravity cũ (task: + biên bản PM pass) vẫn nhận" || fail "c  PR6: $OUT"
printf '%s' "$OUT" | grep -q "drop PR #3 .*claude-verify" && ok "b  lời loại nêu claude-verify" || fail "b  reason: $(printf '%s' "$OUT" | grep 'PR #3')"

# ── e1. runner review_approved_head chạy thật nhánh cv:
cat > "$TMP/github-read.py" <<'PY'
import os, sys
a = sys.argv[sys.argv.index('--') + 1:]
F = os.environ['FAKE']
f = F + '/prs.json' if a[:2] == ['pr', 'list'] else F + '/comments-' + a[2] + '.json'
sys.stdout.write(open(f).read())
PY
E1=$(REPO_ROOT_T="$R" GR="$TMP/github-read.py" SB_LIB_ONLY=1 bash -c '. "$1" || exit 9; set +e; SB_GITHUB_READ="$GR"; REPO_ROOT="$REPO_ROOT_T"
  review_approved_head 21 merge-queue; echo " rc=$?"; review_approved_head 23 merge-queue; echo " rc=$?"' _ "$ROOT/.claude/bin/super-board-run.sh" 2>/dev/null)
printf '%s' "$E1" | grep -q "^1 $H1 rc=0" && printf '%s' "$E1" | grep -q "^ rc=1" \
  && ok "e1 run.sh review_approved_head: cv pass → chọn PR; cv sai head → không" || fail "e1 got: $E1"

# ── e2. queue-label chạy thật nhánh cv: (helper + jq chép, audit-check thật symlink)
mkdir -p "$R/.claude/bin"; git -C "$R" remote add origin https://github.com/acme/widgets.git
cp "$ROOT/.claude/bin/super-board-queue-label.sh" "$ROOT/.claude/bin/super-board-approved-head.jq" "$R/.claude/bin/"
ln -s "$ROOT/.claude/bin/super-board-audit-check.py" "$R/.claude/bin/super-board-audit-check.py"
( cd "$R" && bash .claude/bin/super-board-queue-label.sh --check 1 ) > /dev/null 2> "$TMP/ql.err"; QL1=$?
( cd "$R" && bash .claude/bin/super-board-queue-label.sh --check 3 ) > /dev/null 2> "$TMP/ql3.err"; QL3=$?
{ [ "$QL1" = 0 ] && [ "$QL3" = 3 ] && grep -q "claude-verify" "$TMP/ql3.err"; } \
  && ok "e2 queue-label: cv pass → exit 0; cv sai head → exit 3 nêu claude-verify" || fail "e2 rc=$QL1/$QL3 $(cat "$TMP/ql.err" "$TMP/ql3.err")"

# ── e3. runner gán --session-id cho worker và ghi sổ TRƯỚC khi chạy (không có Agent Office)
mkdir -p "$TMP/home0"
E3=$(HOME="$TMP/home0" REPO_ROOT_T="$R" SB_LIB_ONLY=1 bash -c '. "$1" || exit 9; set +e; REPO_ROOT="$REPO_ROOT_T"
  agent_office_args "$2"; worker_session_args build 40 "$2"; printf "%s|%s\n" "${#AO_ARGS[@]}" "${AO_ARGS[1]:-}"' _ "$ROOT/.claude/bin/super-board-run.sh" "$TMP/w.log" 2>&1)
SID40=${E3#*|}
{ [ "${E3%%|*}" = 2 ] && printf '%s' "$SID40" | grep -Eq '^[0-9a-f-]{36}$' && grep -rq "$SID40" "$CLAUDE_VERIFY_HOME/builders" 2>/dev/null; } \
  && ok "e3 runner: worker build nhận --session-id riêng, sổ builders ghi id đó" || fail "e3 got: $E3"
mkdir -p "$TMP/home1/.agent-office/app"; cp "$ROOT/mcp-servers/agent-office/inbox_hook.py" "$TMP/home1/.agent-office/app/inbox_hook.py"
E4=$(HOME="$TMP/home1" REPO_ROOT_T="$R" SB_LIB_ONLY=1 bash -c '. "$1" || exit 9; set +e; REPO_ROOT="$REPO_ROOT_T"
  agent_office_args "$2"; worker_session_args review 41 "$2"; printf "%s|%s\n" "${#AO_ARGS[@]}" "${AO_ARGS[1]:-}"' _ "$ROOT/.claude/bin/super-board-run.sh" "$TMP/w.log" 2>&1)
SID41=${E4#*|}
{ [ "${E4%%|*}" = 6 ] && grep -rq "$SID41" "$CLAUDE_VERIFY_HOME/reviewers" 2>/dev/null; } \
  && ok "e4 runner: có Agent Office → dùng chính sid của AO (không gán 2 lần), ghi sổ reviewers" || fail "e4 got: $E4"

# ── b5. seal mode bật (pubkey fixture dưới thư mục tạm): chỉ biên bản ký đúng mới tính.
SEED=$(printf '%064d' 7); BAD=$(printf '%064d' 9)
python3 -c 'import base64,sys; sys.path.insert(0,sys.argv[1]); import verdict_seal as v; print(base64.b64encode(v.public_key(bytes.fromhex(sys.argv[2]))).decode())' \
  "$KIT" "$SEED" > "$TMP/seal.pub"
export DEVKIT_VERDICT_SEAL_PUB="$TMP/seal.pub"
CV7=$(cvid 7 "$H7"); record "$CV7" "$H7" "$(tree "$H7")" pass reviewer-sess 27 "$BAD"
CV8=$(cvid 8 "$H8"); record "$CV8" "$H8" "$(tree "$H8")" pass reviewer-sess 28 "$SEED"
CV9=$(cvid 9 "$H9"); record "$CV9" "$H9" "$(tree "$H9")" pass reviewer-sess 29
ROWS=""; rm -f "$F"/labeled/* "$F"/comments-*.json
pr 7 "$H7" claude-verify "$CV7"; pr 8 "$H8" claude-verify "$CV8"; pr 9 "$H9" claude-verify "$CV9"
run_q
dropped 7 && ok "b5 seal mode bật: biên bản ký bằng khoá giả → loại" || fail "b5 PR7: $OUT"
queued 8 "$H8" && ok "b6 seal mode bật: biên bản ký bằng pubkey tin cậy → nhận" || fail "b6 PR8: $OUT"
dropped 9 && ok "b7 seal mode bật: biên bản không ký → loại" || fail "b7 PR9: $OUT"
report "$TMP/r-on.json" "$H9" "$BASE" '[]'; seal reviewer-sess "$H9" "$TMP/r-on.json" issue-29-x
refused "b8 seal mode bật: seal báo cần signer của chủ repo, không ghi biên bản" 3 "seal mode bật"
unset DEVKIT_VERDICT_SEAL_PUB

# ── f. hook guard + SKILL.md
python3 - "$ROOT/universal-agent-devkit/hooks/block_dangerous_git_main.py" <<'PY' && ok "f1 hook guard: claude_verify.py (kit + .agents/devkit) là phụ thuộc của helper merge-queue" || fail "f1 MQ_HELPER_DEPS thiếu claude_verify.py"
import ast, os, sys
# hook chạy main lúc import (đọc stdin): chỉ tính giá trị của phép gán MQ_HELPER_DEPS
node = next(n for n in ast.parse(open(sys.argv[1], encoding="utf-8").read()).body
            if isinstance(n, ast.Assign) and any(getattr(t, "id", "") == "MQ_HELPER_DEPS" for t in n.targets))
deps = eval(compile(ast.Expression(node.value), "deps", "eval"), {"os": os})
need = {os.path.join("universal-agent-devkit", "bin", "claude_verify.py"), os.path.join(".agents", "devkit", "bin", "claude_verify.py")}
sys.exit(0 if need <= set(deps) else 1)
PY
SK="$ROOT/.claude/skills/super-review/SKILL.md"
{ grep -q "edited_existing" "$SK" && grep -q "claude-verify only works for cards the board dispatched" "$SK" \
  && ! grep -q "the seal refuses the session holding the PR branch's worktree" "$SK"; } \
  && ok "f2 SKILL.md: test cũ bị sửa vẫn đi Antigravity; claude-verify chỉ cho thẻ board giao; bỏ lời hứa cũ" || fail "f2 SKILL.md"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
