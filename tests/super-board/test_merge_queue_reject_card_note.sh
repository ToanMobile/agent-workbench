#!/usr/bin/env bash
# Test #536 (mục 3): hàng đợi merge loại PR vì approved-head thiếu / lệch head / duyệt không hợp lệ (reject) thì ngoài comment trên
# PR còn comment lên thẻ mà PR đóng — 28/10 PR #517 rời hàng lúc 07:49 mà các thẻ phụ thuộc đứng im ~3 giờ không ai được báo.
#   R1 nhánh issue-<K>- thiếu approved-head → comment PR + gỡ nhãn như cũ, thêm comment `[merge-queue] [report] ⚠ PR #N left the
#      queue` lên thẻ K kèm lý do
#   R2 nhánh fix-… với closingIssuesReferences đúng một issue trên board → comment lên issue đó
#   R3 issue không nằm trên board (card.sh item-id exit 3) → chỉ comment PR
#   R4 approved-head của head cũ → comment thẻ nêu lý do lệch head
#   R5 đối chứng: PR duyệt đúng → vào train, không comment rời hàng
#   R6 --dry-run → không ghi gì
#   R7 lần tra thẻ (card.sh) gặp halt → không để lại github-halt.json thật, lượt sau vẫn chạy
# Harness chép từ test_merge_queue_route_rows.sh (gh python giả, card.sh / train stub, github-read thật). Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mq-route.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
F="$TMP/fake"; R="$TMP/repo"; Q="$TMP/qbin"
mkdir -p "$F/labeled" "$Q" "$TMP/path"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"; git -C "$R" add .gitignore; git -C "$R" commit -qm init
COMMON="$(cd "$R" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
ATT="$COMMON/super-board/merge-queue.attempts"

ln -s "$ROOT/.claude/bin/super-board-merge-queue.sh" "$Q/super-board-merge-queue.sh"
ln -s "$ROOT/.claude/bin/super-board-github-read.py" "$Q/super-board-github-read.py"
ln -s "$ROOT/.claude/bin/super-board-approved-head.jq" "$Q/super-board-approved-head.jq"
ln -s "$ROOT/.claude/bin/super-board-audit-check.py" "$Q/super-board-audit-check.py"
QUEUE="$Q/super-board-merge-queue.sh"
cat > "$Q/super-board-merge-train.sh" <<'SH'
#!/usr/bin/env bash
echo "train $*" >> "$FAKE/calls"
[ -f "$FAKE/train.out" ] && cat "$FAKE/train.out"
exit "$(cat "$FAKE/train.rc" 2>/dev/null || echo 0)"
SH
cat > "$Q/super-board-card.sh" <<'SH'
#!/usr/bin/env bash
while [ "${1#--}" != "$1" ]; do shift 2; done
# Như bản thật: move / item-id đọc thẻ qua github-read, mà github-read từ chối khi file halt đã có; $FAKE/card-halt: chính lần đọc
# của card.sh hỏng (ghi file halt, 79); $FAKE/offboard-<K>: issue K không nằm trên board (exit 3).
[ ! -f "$SB_GITHUB_HALT_FILE" ] || exit 79
[ ! -f "$FAKE/card-halt" ] || { : > "$SB_GITHUB_HALT_FILE"; exit 79; }
[ ! -f "$FAKE/card-err-$2" ] || exit 69
[ ! -f "$FAKE/offboard-$2" ] || exit 3
echo "card $*" >> "$FAKE/writes"
SH
printf 'import os, sys\nopen(os.environ["FAKE"] + "/writes", "a").write("needs-you " + " ".join(sys.argv[1:]) + "\\n")\n' > "$Q/super-board-needs-you.py"
printf 'import os, sys\nopen(os.environ["FAKE"] + "/writes", "a").write("notify " + " ".join(sys.argv[1:]) + "\\n")\n' > "$Q/super-board-notify.py"
chmod +x "$Q"/*.sh
# gh giả (cùng giao kèo với test_merge_queue.sh). PR: $FAKE/prs.json (giữ nguyên mọi trường, kể cả closingIssuesReferences);
# nhãn merge-queue = $FAKE/labeled/<N>; issue: $FAKE/issue-<K>.json; PR đã merge: $FAKE/merged-<N>; $FAKE/state-broken-<N>: trạng
# thái PR đọc ra sai dạng (github-read thử 3 lần rồi halt); $FAKE/issue-broken-<K>: issue K đọc ra sai dạng (cũng halt). Mọi lệnh
# ghi một dòng vào $FAKE/writes.
cat > "$TMP/path/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
F = os.environ['FAKE']; a = sys.argv[1:]
def opt(name):
    return a[a.index(name) + 1] if name in a else None
def num():
    return next(x for x in a[2:] if x.isdigit())
def w(line):
    open(F + '/writes', 'a').write(line + '\n')
def issue(k):
    return json.load(open(f'{F}/issue-{k}.json'))
if a[:2] == ['pr', 'list']:
    st = (opt('--state') or 'open').upper()
    prs = [p for p in json.load(open(F + '/prs.json')) if p.get('state', 'OPEN') == st]
    for p in prs:
        p.pop('state', None)
    if opt('--label') == 'merge-queue':
        prs = [p for p in prs if os.path.exists(f"{F}/labeled/{p['number']}")]
    print(json.dumps(prs))
elif a[:2] == ['pr', 'view'] and opt('--json') == 'comments':
    h = f'{F}/head-{num()}'   # #536: không có file head-<N> = PR không có comment duyệt nào
    print(json.dumps({'comments': [{'authorAssociation': 'OWNER', 'body': 'approved-head:' + open(h).read().strip()}] if os.path.exists(h) else []}))
elif a[:2] == ['pr', 'view'] and 'state' in (opt('--json') or ''):
    n = num(); m = f'{F}/merged-{n}'
    if os.path.exists(f'{F}/state-broken-{n}'):
        print('{}')
    elif os.path.exists(m):
        print(json.dumps({'state': 'MERGED', 'mergeCommit': {'oid': open(m).read().strip()}, 'headRefOid': 'a' * 40}))
    else:
        print(json.dumps({'state': 'OPEN', 'mergeCommit': None, 'headRefOid': 'a' * 40}))
elif a[0] == 'api' and '/timeline' in a[1]:
    n = a[1].split('/issues/')[1].split('/')[0]; p = f'{F}/labeled/{n}'
    ev = [{'event': 'labeled', 'label': {'name': 'merge-queue'}, 'created_at': open(p).read().strip()}] if os.path.exists(p) else []
    print(json.dumps([ev]))
elif a[:2] == ['issue', 'view']:
    k = num()
    print('{}' if os.path.exists(f'{F}/issue-broken-{k}') else json.dumps(issue(k)))
elif a[:2] == ['pr', 'edit']:
    n = num(); lab = opt('--remove-label'); w(f'pr-unlabel {n} {lab}')
    if lab == 'merge-queue' and os.path.exists(f'{F}/labeled/{n}'):
        os.remove(f'{F}/labeled/{n}')
elif a[:2] in (['pr', 'comment'], ['issue', 'comment']):
    n = num(); body = opt('--body')
    w(f'{a[0]}-comment {n} ' + body.splitlines()[0])
    open(f'{F}/{a[0]}-comment-{n}.txt', 'a').write(body + '\n----\n')
elif a[:2] == ['issue', 'close']:
    k = num(); d = issue(k); d['state'] = 'CLOSED'; json.dump(d, open(f'{F}/issue-{k}.json', 'w')); w(f'issue-close {k}')
elif a[:2] == ['issue', 'edit']:
    k = num(); d = issue(k); names = [l['name'] for l in d['labels']]
    for i, x in enumerate(a):
        if x == '--add-label' and a[i + 1] not in names:
            names.append(a[i + 1])
        if x == '--remove-label':
            names = [y for y in names if y != a[i + 1]]
    d['labels'] = [{'name': y} for y in names]; json.dump(d, open(f'{F}/issue-{k}.json', 'w'))
    w(f'issue-labels {k} ' + ','.join(sorted(names)))
elif a[:2] == ['label', 'create']:
    w('label-create ' + a[2])
else:
    sys.stderr.write('fake gh: unexpected ' + ' '.join(a) + '\n'); sys.exit(1)
PY
chmod +x "$TMP/path/gh"
export PATH="$TMP/path:$PATH" FAKE="$F" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_QUEUE SB_MERGE_CALLER SB_GITHUB_READ_STRICT
printf '{"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"worker_backend":"claude-p","rebuild_cap":2,"verify_commands":["true"],"merge_queue":{"enabled":true}}\n' > "$TMP/cfg.json"

ago() { python3 -c 'import datetime,sys;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
sha() { printf '%040d' "$1" | tr 0 "${2:-a}"; }
PRS_ROWS=""
# pr <N> <nhánh> <phút từ lúc gắn nhãn> [closingIssuesReferences JSON] [state]: PR có nhãn + approved-head khớp head = sha(N).
pr() {
  PRS_ROWS="${PRS_ROWS}${PRS_ROWS:+,}{\"number\":$1,\"headRefName\":\"$2\",\"headRefOid\":\"$(sha "$1")\",\"isDraft\":false,\"state\":\"${5:-OPEN}\",\"closingIssuesReferences\":${4:-[]}}"
  printf '[%s]\n' "$PRS_ROWS" > "$F/prs.json"
  ago "$3" > "$F/labeled/$1"; sha "$1" > "$F/head-$1"
}
ref() { printf '{"number":%s,"repository":{"name":"%s","owner":{"login":"%s"}}}' "$1" "${3:-r}" "${2:-o}"; }   # ref <issue> [owner] [name]
issue() { printf '{"number":%s,"title":"card %s","body":"","state":"OPEN","labels":[]}' "$1" "$1" > "$F/issue-$1.json"; }
reset() {
  rm -rf "$F"; mkdir -p "$F/labeled"; PRS_ROWS=""; printf '[]\n' > "$F/prs.json"; : > "$F/writes"; : > "$F/calls"
  rm -f "$TMP/halt.json" "$ATT" "$COMMON"/super-board/merge-queue.*
}
run_q() { ( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" "$@" ) >"$TMP/out" 2>"$TMP/err"; }
has_w() { grep -qF -- "$1" "$F/writes"; }
note() { cat "$F/issue-comment-$1.txt" 2>/dev/null; }

# ── R1. nhánh issue-17-… thiếu approved-head
reset; pr 7 issue-17-x 30; issue 17; rm -f "$F/head-7"
run_q; rc=$?
{ [ "$rc" -eq 0 ] && has_w "pr-comment 7 [merge-queue] [report] ⚠ left the queue" && has_w "pr-unlabel 7 merge-queue"; } \
  && ok "R1 no approval → PR comment + label removed as before" || fail "R1 rc=$rc writes=$(cat "$F/writes") err=$(tail -c 200 "$TMP/err")"
{ has_w "issue-comment 17 [merge-queue] [report] ⚠ PR #7 left the queue" && note 17 | grep -q 'approved-head'; } \
  && ok "R1 card #17 told why PR #7 left the queue" || fail "R1 no card note: writes=$(cat "$F/writes")"

# ── R2. nhánh fix-… đóng đúng một issue trên board
reset; pr 8 fix-foo 30 "[$(ref 18)]"; issue 18; rm -f "$F/head-8"
run_q
has_w "issue-comment 18 [merge-queue] [report] ⚠ PR #8 left the queue" && ok "R2 card via closingIssuesReferences gets the note" \
  || fail "R2 writes=$(cat "$F/writes")"

# ── R3. issue ngoài board
reset; pr 9 fix-bar 30 "[$(ref 19)]"; issue 19; touch "$F/offboard-19"; rm -f "$F/head-9"
run_q
{ has_w "pr-comment 9 [merge-queue] [report] ⚠ left the queue" && ! has_w "issue-comment 19"; } \
  && ok "R3 issue not on the board → only the PR comment" || fail "R3 writes=$(cat "$F/writes")"

# ── R4. approved-head của head cũ
reset; pr 10 issue-20-y 30; issue 20; sha 99 b > "$F/head-10"
run_q
{ has_w "issue-comment 20 [merge-queue] [report] ⚠ PR #10 left the queue" && note 20 | grep -q 'not the PR head'; } \
  && ok "R4 stale approval → card note names the head mismatch" || fail "R4 writes=$(cat "$F/writes") note=$(note 20)"

# ── R5. đối chứng: duyệt đúng → train, không comment rời hàng
reset; pr 11 issue-21-z 30; issue 21
printf 'train-result: 11 deferred\n' > "$F/train.out"; echo 0 > "$F/train.rc"
run_q
{ grep -q '^train ' "$F/calls" && ! has_w "left the queue"; } && ok "R5 control — approved PR goes to the train, no left-the-queue note" \
  || fail "R5 calls=$(cat "$F/calls") writes=$(cat "$F/writes")"

# ── R6. --dry-run không ghi gì
reset; pr 12 issue-22-w 30; issue 22; rm -f "$F/head-12"
run_q --dry-run
[ ! -s "$F/writes" ] && ok "R6 --dry-run writes nothing" || fail "R6 writes=$(cat "$F/writes")"

# ── R7. lần tra thẻ của ghi chú gặp halt (card.sh ghi file halt rồi exit 79) → không để lại file halt thật của board/hàng đợi,
#        hàng đợi chạy hết lượt, PR vẫn rời hàng, không ghi lên thẻ chưa xác minh
reset; pr 13 issue-23-v 30; issue 23; rm -f "$F/head-13"; touch "$F/card-halt"
run_q; rc=$?
{ [ "$rc" -eq 0 ] && [ ! -e "$TMP/halt.json" ] && has_w "pr-comment 13 [merge-queue] [report] ⚠ left the queue" && ! has_w "issue-comment 23"; } \
  && ok "R7 card lookup halts → no real halt file left, queue finishes, PR still leaves, card untouched" \
  || fail "R7 rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo LEFT || echo none) writes=$(cat "$F/writes")"
run_q; rc=$?
[ "$rc" -eq 0 ] && ok "R7 next run is not halted" || fail "R7 next run rc=$rc err=$(tail -c 200 "$TMP/err")"

[ "$FAILS" -eq 0 ] && echo "PASS test_merge_queue_reject_card_note" || { echo "FAIL test_merge_queue_reject_card_note ($FAILS)"; exit 1; }
