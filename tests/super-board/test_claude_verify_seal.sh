#!/usr/bin/env bash
# Test #1328: merge queue nhận nguồn duyệt `claude-verify` (biên bản universal-agent-devkit/bin/claude_verify.py) ngoài antigravity-pm.
#  a  approved-by reviewer claude-verify + biên bản pass đúng head → jq ra `cv:<id>`, queue xếp train (ĐỎ trên mã cũ:
#     "not an antigravity-pm task id")
#  b  biên bản của chính phiên builder, của head khác, tree lệch, verdict fail → queue loại; seal mode bật (pubkey fixture trong thư
#     mục tạm): biên bản không ký / chữ ký giả → loại, chữ ký đúng → nhận
#  c  đường antigravity cũ (`task:` + biên bản PM pass) vẫn nhận
#  d  `claude_verify.py seal` từ chối: finding thiếu dòng, dòng ngoài hunk, snippet sai, head sai, base sai, phiên rỗng, phiên builder
#  e  run.sh (review_approved_head) và queue-label.sh có nhánh `cv:`
# Queue thật + jq thật + audit-check thật (symlink), gh giả, train/card stub. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
CV="$ROOT/universal-agent-devkit/bin/claude_verify.py"
JQF="$ROOT/.claude/bin/super-board-approved-head.jq"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
F="$TMP/fake"; R="$TMP/repo"; Q="$TMP/qbin"
mkdir -p "$F/labeled" "$Q" "$TMP/path" "$TMP/pm"
export CLAUDE_VERIFY_HOME="$TMP/cv" DEVKIT_PM_HOME_TEST=1 ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
unset DEVKIT_VERDICT_SEAL_PUB

# ── repo: main có src.py; mỗi PR là một nhánh sửa src.py. Worktree build của PR 1 giữ lock của phiên builder-sess.
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t; git -C "$R" config commit.gpgsign false
printf '.claude/\n' > "$R/.gitignore"; printf 'a = 1\nb = 2\nc = 3\n' > "$R/src.py"
git -C "$R" add .gitignore src.py; git -C "$R" commit -qm init
BASE=$(git -C "$R" rev-parse HEAD)
mkpr() {   # mkpr <branch> <dòng thêm>: commit trên nhánh mới từ main, in sha
  git -C "$R" checkout -q -b "$1" main
  printf 'a = 1\n%s\nb = 2\nc = 3\n' "$2" > "$R/src.py"; git -C "$R" commit -qam "$1"
  git -C "$R" rev-parse HEAD; git -C "$R" checkout -q main
}
H1=$(mkpr issue-21-a 'x = danger(1)'); H2=$(mkpr issue-22-b 'y = 2'); H3=$(mkpr issue-23-c 'z = 3')
H4=$(mkpr issue-24-d 'w = 4'); H5=$(mkpr issue-25-e 'v = 5'); H6=$(mkpr issue-26-f 'u = 6')
H7=$(mkpr issue-27-g 't = 7'); H8=$(mkpr issue-28-h 's = 8'); H9=$(mkpr issue-29-i 'r = 9')
git -C "$R" worktree add -q "$TMP/wt1" issue-21-a
printf '{"session_id":"builder-sess","heartbeat":0}' > "$(git -C "$TMP/wt1" rev-parse --absolute-git-dir)/devkit-session.lock"

# ── d. seal từ chối báo cáo sai; ghi biên bản cho báo cáo đúng.
report() {   # report <file> <head> <base> <findings JSON>
  jq -n --arg h "$2" --arg b "$3" --argjson f "$4" '{head:$h, base:$b, findings:$f, reviewed_at:"2026-11-19T00:00:00Z"}' > "$1"
}
seal() {   # seal <session> <head> <report>
  ( cd "$R" && CLAUDE_CODE_SESSION_ID="$1" python3 "$CV" seal --repo "$R" --head "$2" --report "$3" ) > "$TMP/seal.out" 2> "$TMP/seal.err"
  SRC=$?; SID=$(sed -n 's/^task_id=\(CV[^ ]*\) .*/\1/p' "$TMP/seal.out")
}
NIT='[{"id":"f1","severity":"nit","file":"src.py","line":2,"snippet":"danger(1)","class":"naming"}]'
report "$TMP/r-ok.json" "$H1" "$BASE" "$NIT"; seal reviewer-sess "$H1" "$TMP/r-ok.json"
{ [ "$SRC" = 0 ] && [ -n "$SID" ] && printf '%s' "$SID" | grep -Eq '^CV[0-9]{8}T[0-9]{6}-[0-9a-f]{12}$'; } \
  && ok "d0 seal: báo cáo đúng (nit trong hunk) → exit 0, task_id $SID" || fail "d0 rc=$SRC out=$(cat "$TMP/seal.out") err=$(cat "$TMP/seal.err")"
CV1="$SID"
for c in 'noline|[{"id":"f1","severity":"nit","file":"src.py","snippet":"danger(1)"}]' \
         'outhunk|[{"id":"f1","severity":"important","file":"src.py","line":3,"snippet":"b = 2"}]' \
         'nofile|[{"id":"f1","severity":"nit","file":"other.py","line":1,"snippet":"x"}]' \
         'badsnip|[{"id":"f1","severity":"nit","file":"src.py","line":2,"snippet":"not there"}]' \
         'badsev|[{"id":"f1","severity":"blocker","file":"src.py","line":2,"snippet":"danger"}]'; do
  name=${c%%|*}; report "$TMP/r-bad.json" "$H1" "$BASE" "${c#*|}"; seal reviewer-sess "$H1" "$TMP/r-bad.json"
  [ "$SRC" = 2 ] && [ -z "$SID" ] && ok "d-$name seal từ chối (exit 2: $(head -c 90 "$TMP/seal.err"))" || fail "d-$name rc=$SRC out=$(cat "$TMP/seal.out")"
done
report "$TMP/r-pre.json" "$H1" "$BASE" '[{"id":"p1","severity":"pre-existing","file":"src.py","line":3,"snippet":"b = 2"}]'
seal reviewer-sess "$H1" "$TMP/r-pre.json"; [ "$SRC" = 0 ] && ok "d-pre finding pre-existing ngoài hunk được nhận" || fail "d-pre rc=$SRC $(cat "$TMP/seal.err")"
report "$TMP/r-h.json" "$H2" "$BASE" '[]'; seal reviewer-sess "$H1" "$TMP/r-h.json"
[ "$SRC" = 2 ] && ok "d-head báo cáo head khác --head → từ chối" || fail "d-head rc=$SRC"
report "$TMP/r-b.json" "$H1" "$H2" '[]'; seal reviewer-sess "$H1" "$TMP/r-b.json"
[ "$SRC" = 2 ] && ok "d-base base không phải merge-base(trunk, head) → từ chối" || fail "d-base rc=$SRC"
seal "" "$H1" "$TMP/r-ok.json"; [ "$SRC" = 2 ] && ok "d-sess CLAUDE_CODE_SESSION_ID rỗng → từ chối" || fail "d-sess rc=$SRC"
seal builder-sess "$H1" "$TMP/r-ok.json"
{ [ "$SRC" = 2 ] && grep -q builder "$TMP/seal.err"; } && ok "d-self phiên builder tự niêm phong head của mình → từ chối" || fail "d-self rc=$SRC $(cat "$TMP/seal.err")"
report "$TMP/r-imp.json" "$H5" "$BASE" '[{"id":"i1","severity":"important","file":"src.py","line":2,"snippet":"v = 5"}]'
seal reviewer-sess "$H5" "$TMP/r-imp.json"; CV5="$SID"
[ "$SRC" = 4 ] && [ -n "$CV5" ] && ok "d-imp finding important → biên bản verdict fail (exit 4)" || fail "d-imp rc=$SRC"

# Biên bản viết tay (giả mạo / lệch) theo đúng dạng file của claude_verify.py.
record() {   # record <task_id> <head> <tree> <verdict> <reviewer> [seed hex ký]
  python3 - "$ROOT/universal-agent-devkit/bin" "$CLAUDE_VERIFY_HOME/records" "$@" <<'PY'
import base64, json, os, sys
sys.path.insert(0, sys.argv[1]); import verdict_seal as vs
d, tid, head, tree, verdict, rv = sys.argv[2:8]
p = {"v": 1, "kind": "claude-verify", "task_id": tid, "head": head, "tree": tree, "base": "0" * 40, "verdict": verdict,
     "findings": [], "reviewer_session": rv, "builder_session": None, "ts": "2026-11-19T00:00:00+00:00"}
s = json.dumps(p, sort_keys=True)
sig = base64.b64encode(vs.sign(bytes.fromhex(sys.argv[8]), s.encode())).decode() if len(sys.argv) > 8 else None
os.makedirs(d, exist_ok=True); json.dump({"payload": s, "sig": sig}, open(os.path.join(d, tid + ".json"), "w"))
PY
}
tree() { git -C "$R" rev-parse "$1^{tree}"; }
CV2="CV20261119T000002-${H2:0:12}"; record "$CV2" "$H1" "$(tree "$H1")" pass builder-sess   # PR 2 (head H1): biên bản do chính phiên builder viết
CV3="CV20261119T000003-${H3:0:12}"; record "$CV3" "$H2" "$(tree "$H2")" pass reviewer-sess   # biên bản của head khác
CV4="CV20261119T000004-${H4:0:12}"; record "$CV4" "$H4" "$(tree "$H3")" pass reviewer-sess   # tree lệch

# ── a. jq ra cv:<id> (mã cũ: "not an antigravity-pm task id")
by() { jq -cn --arg r "$1" --arg t "$2" '{reviewer:$r,builder:"claude-builder",task_id:$t,gate_receipt:"receipt-1"}'; }
JQOUT=$(jq -n --arg b "approved-head:$H1
approved-by: $(by claude-verify "$CV1")" '{comments:[{authorAssociation:"MEMBER",body:$b}]}' | jq -r -f "$JQF")
[ "$JQOUT" = "$(printf 'ok\t%s\tcv:%s' "$H1" "$CV1")" ] && ok "a-jq approved-by claude-verify → ok <sha> cv:<id>" || fail "a-jq got: $JQOUT"
JQOUT=$(jq -n --arg b "approved-head:$H1
approved-by: $(by claude-verify CVnot-an-id)" '{comments:[{authorAssociation:"MEMBER",body:$b}]}' | jq -r -f "$JQF")
printf '%s' "$JQOUT" | grep -q "neither an antigravity-pm nor a claude-verify id" && ok "a-jq task_id lạ → bad, nêu cả hai dạng id" || fail "a-jq bad id: $JQOUT"

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
    prs = [p for p in json.load(open(F + '/prs.json')) if (opt('--state') or 'open').upper() == 'OPEN']
    print(json.dumps(prs))
elif a[:2] == ['pr', 'view'] and opt('--json') == 'comments':
    p = f'{F}/comments-{num()}.json'
    print(open(p).read() if os.path.exists(p) else '{"comments":[]}')
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
pr() {   # pr <N> <head> <reviewer> <task_id>
  ROWS="${ROWS}${ROWS:+,}{\"number\":$1,\"headRefName\":\"issue-$((20 + $1))-x\",\"headRefOid\":\"$2\",\"isDraft\":false}"
  printf '[%s]\n' "$ROWS" > "$F/prs.json"; echo "2026-11-19T00:00:00Z" > "$F/labeled/$1"
  jq -n --arg b "approved-head:$2
approved-by: $(by "$3" "$4")" '{comments:[{authorAssociation:"MEMBER",body:$b}]}' > "$F/comments-$1.json"
}
run_q() { : > "$F/calls"; ( cd "$R" && bash "$Q/super-board-merge-queue.sh" --config "$TMP/cfg.json" --wait --dry-run ) > "$TMP/out" 2>&1; OUT=$(cat "$TMP/out"); }
queued() { printf '%s' "$OUT" | grep -q -- "--prs $1:$2\$"; }
dropped() { printf '%s' "$OUT" | grep -q "drop PR #$1 "; }
# PM fixture cho đường antigravity (như test_merge_queue.sh)
mkdir -p "$TMP/pm/projects/p/tasks/T0006-agy"
jq -n --arg p "$R" --arg h "$H6" '{id:"T0006-agy",project:$p,verdicts:{audit:{verdict:"pass",reviewer:"pm",notes:("fixture\nauditedHead: "+$h)}}}' \
  > "$TMP/pm/projects/p/tasks/T0006-agy/task.json"

pr 1 "$H1" claude-verify "$CV1"; pr 2 "$H1" claude-verify "$CV2"; pr 3 "$H3" claude-verify "$CV3"; pr 4 "$H4" claude-verify "$CV4"
pr 5 "$H5" claude-verify "$CV5"; pr 6 "$H6" antigravity T0006-agy
run_q
queued 1 "$H1" && ok "a  queue: approved-by claude-verify + biên bản pass đúng head → xếp train" || fail "a  queue PR1: $OUT"
dropped 2 && ok "b1 queue: biên bản do phiên builder viết (reviewer == builder) → loại" || fail "b1 PR2 not dropped: $OUT"
dropped 3 && ok "b2 queue: biên bản của head khác → loại" || fail "b2 PR3 not dropped: $OUT"
dropped 4 && ok "b3 queue: tree biên bản lệch tree(head) → loại" || fail "b3 PR4 not dropped: $OUT"
dropped 5 && ok "b4 queue: biên bản verdict fail → loại" || fail "b4 PR5 not dropped: $OUT"
queued 6 "$H6" && ok "c  queue: đường antigravity cũ (task: + biên bản PM pass) vẫn nhận" || fail "c  PR6: $OUT"
printf '%s' "$OUT" | grep -q "drop PR #3 .*claude-verify" && ok "b  lời loại nêu claude-verify" || fail "b  reason: $(printf '%s' "$OUT" | grep 'PR #3')"

# ── b5. seal mode bật (pubkey fixture dưới thư mục tạm): chỉ biên bản ký đúng mới tính.
SEED=$(printf '%064d' 7); BAD=$(printf '%064d' 9)
python3 -c 'import base64,sys; sys.path.insert(0,sys.argv[1]); import verdict_seal as v; print(base64.b64encode(v.public_key(bytes.fromhex(sys.argv[2]))).decode())' \
  "$ROOT/universal-agent-devkit/bin" "$SEED" > "$TMP/seal.pub"
export DEVKIT_VERDICT_SEAL_PUB="$TMP/seal.pub"
CV7="CV20261119T000007-${H7:0:12}"; record "$CV7" "$H7" "$(tree "$H7")" pass reviewer-sess "$BAD"
CV8="CV20261119T000008-${H8:0:12}"; record "$CV8" "$H8" "$(tree "$H8")" pass reviewer-sess "$SEED"
CV9="CV20261119T000009-${H9:0:12}"; record "$CV9" "$H9" "$(tree "$H9")" pass reviewer-sess
ROWS=""; rm -f "$F"/labeled/* "$F"/comments-*.json
pr 7 "$H7" claude-verify "$CV7"; pr 8 "$H8" claude-verify "$CV8"; pr 9 "$H9" claude-verify "$CV9"
run_q
dropped 7 && ok "b5 seal mode bật: biên bản ký bằng khoá giả → loại" || fail "b5 PR7: $OUT"
queued 8 "$H8" && ok "b6 seal mode bật: biên bản ký bằng pubkey tin cậy → nhận" || fail "b6 PR8: $OUT"
dropped 9 && ok "b7 seal mode bật: biên bản không ký → loại" || fail "b7 PR9: $OUT"
report "$TMP/r-on.json" "$H9" "$BASE" '[]'; seal reviewer-sess "$H9" "$TMP/r-on.json"
{ [ "$SRC" = 3 ] && grep -q "seal mode bật" "$TMP/seal.err"; } && ok "b8 seal mode bật: seal báo cần signer của chủ repo, không ghi biên bản" || fail "b8 rc=$SRC $(cat "$TMP/seal.err")"
unset DEVKIT_VERDICT_SEAL_PUB

# ── b9. CLAUDE_VERIFY_HOME ngoài fixture (thiếu công tắc) → không tính.
( cd "$R" && DEVKIT_PM_HOME_TEST=0 python3 "$CV" check "$CV1" "$H1" --top "$R" ) 2>/dev/null && fail "b9 store lạ ngoài fixture vẫn được tính" \
  || ok "b9 CLAUDE_VERIFY_HOME ngoài fixture test → check từ chối"

# ── e. các consumer khác của jq có nhánh cv:
grep -q 'cv:?\*)' "$ROOT/.claude/bin/super-board-run.sh" && ok "e1 run.sh review_approved_head xử lý cv:" || fail "e1 run.sh thiếu nhánh cv:"
grep -q 'cv:?\*' "$ROOT/.claude/bin/super-board-queue-label.sh" && ok "e2 queue-label.sh xử lý cv:" || fail "e2 queue-label.sh thiếu nhánh cv:"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
