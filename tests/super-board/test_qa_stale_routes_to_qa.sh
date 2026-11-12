#!/usr/bin/env bash
# #979: QA cũ (qa-report: stale) đưa thẻ Review → QA, không về Build.
#   A. checker: report QA nêu sha cũ mà head còn code sau đó in dòng `qa-report: stale: …` (mã riêng); lỗi AC khác (❌ Not done) thì không có `stale`.
#   B. merge queue: gate-exit-11 mà MỌI lý do là `qa-report: stale` ⇒ card move QA, không nhãn loop:rebuild-N, không về Ready.
#   B2. đối chứng: gate-exit-11 có thêm lý do không-stale (qa-report khác / ac-check) ⇒ vẫn về Build (loop:rebuild-1, Ready).
# Chạy offline: gh / train / card.sh là stub (cùng giao kèo với test_merge_queue_route_rows.sh). Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
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
ln -s "$ROOT/.claude/bin/super-board-ac-check.py" "$Q/super-board-ac-check.py"   # #531: merged-PR routing reads the sb:ac block
QUEUE="$Q/super-board-merge-queue.sh"
cat > "$Q/super-board-merge-train.sh" <<'SH'
#!/usr/bin/env bash
echo "train $*" >> "$FAKE/calls"
# #676: một train cho MỘT PR — stub chỉ in dòng train-* của PR trong --prs; mã thoát train.rc.<N> nếu có, không thì train.rc
n=""; prev=""; for a in "$@"; do [ "$prev" = --prs ] && n="${a%%:*}"; prev="$a"; done
[ -f "$FAKE/train.out" ] && grep -E "^train-(result|detail|red): ${n}( |\$)" "$FAKE/train.out"
exit "$(cat "$FAKE/train.rc.$n" 2>/dev/null || cat "$FAKE/train.rc" 2>/dev/null || echo 0)"
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
    print(json.dumps({'comments': [{'authorAssociation': 'OWNER', 'body': 'approved-head:' + open(f'{F}/head-{num()}').read().strip()}]}))
elif a[:2] == ['pr', 'view'] and opt('--json') == 'body,headRefOid':   # #531: PR body for the sb:ac check (no block = nothing unproven)
    print(json.dumps({'body': '', 'headRefOid': 'a' * 40}))
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
printf '{"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"worker_backend":"claude-p","rebuild_cap":2,"verify_commands":["true"],"merge_queue":{"enabled":true,"max_trains":50}}\n' > "$TMP/cfg.json"

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
run_q() { ( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >"$TMP/out" 2>"$TMP/err"; }
has_w() { grep -qF -- "$1" "$F/writes"; }

# ── A. checker
QA="$ROOT/.claude/bin/super-board-qa-report.py"
G="$TMP/g"; git init -q -b main "$G"; git -C "$G" config user.email t@t; git -C "$G" config user.name t; git -C "$G" config commit.gpgsign false
echo a > "$G/a"; git -C "$G" add -A; git -C "$G" commit -qm M0
git -C "$G" checkout -q -b br; echo b > "$G/c"; git -C "$G" add c; git -C "$G" commit -qm build; Q1=$(git -C "$G" rev-parse HEAD)
echo more >> "$G/c"; git -C "$G" commit -qam "code after QA"; H=$(git -C "$G" rev-parse HEAD)
python3 -c 'import json,sys; print(json.dumps({"body":"","author":{"login":"o"},"comments":[{"body":"[qa] [report] ✅ pass @ "+sys.argv[1]+"\nDid: ran\n✅ Done: AC1","authorAssociation":"OWNER","author":{"login":"o"}}]}))' "${Q1:0:10}" > "$TMP/meta.json"
OUT=$(python3 "$QA" --meta "$TMP/meta.json" --head "$H" --repo "$G" --base main 2>/dev/null); RC=$?
[ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q '^qa-report: stale: ' && ok "A stale QA report prints 'qa-report: stale: …'" || fail "A (rc=$RC): $OUT"

# ── B. queue
reset
pr 9 issue-19-a 20; pr 10 issue-20-b 10; issue 19; issue 20
printf 'train-result: 9 gate-exit-11\ntrain-detail: 9 qa-report: stale: report QA mới nhất kiểm abc, head def còn 1 commit code sau đó: QA phải chạy lại trên head\ntrain-result: 10 gate-exit-11\ntrain-detail: 10 qa-report: stale: x\ntrain-detail: 10 ac-check: AC2 chưa chứng minh\n' > "$F/train.out"; echo 11 > "$F/train.rc"
run_q; rc=$?
has_w "card move 19 QA" && ok "B stale-only exit 11: card #19 moves to QA" || fail "B route: rc=$rc $(cat "$F/writes")"
has_w "card move 19 Ready" && fail "B stale-only: card went back to Ready (Build)" || ok "B stale-only: not moved to Ready"
has_w "issue-labels 19 loop:rebuild" && fail "B stale-only: loop:rebuild-N was added" || ok "B stale-only: no loop:rebuild-N label"
grep -q "stale" "$F/issue-comment-19.txt" 2>/dev/null && ok "B the issue comment names the stale QA" || fail "B comment: $(cat "$F/issue-comment-19.txt" 2>/dev/null)"
# B2
has_w "issue-labels 20 loop:rebuild-1" && has_w "card move 20 Ready" && ok "B2 stale + ac-check: still back to Build" || fail "B2: $(cat "$F/writes")"

[ "$FAILS" -eq 0 ] && echo "✅ test_qa_stale_routes_to_qa: all passed" || { echo "$FAILS FAILED"; exit 1; }
