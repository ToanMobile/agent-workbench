#!/usr/bin/env bash
# Test cho .claude/bin/super-board-merge-queue.sh — lượt route (#762, #637, #639):
#   A. #762: card_of / head_of / cache của load_rows không được trả lỗi khi dữ liệu lớn hơn bộ đệm ống (awk thoát ở dòng khớp
#      trong khi printf còn ghi ⇒ EPIPE ⇒ pipefail ⇒ set -e giết hàng đợi giữa lượt route). Dữ liệu > 64 KB làm lỗi tất định; trên
#      máy tải nặng cùng lỗi đó xảy ra chập chờn với vài dòng (REG-SB-MERGE-QUEUE-01 đỏ mỗi lần một assertion).
#   B. #637: PR nhánh không theo mẫu issue-<N>- được nhận thẻ qua closingIssuesReferences (đúng một issue của repo này); nhánh
#      issue-<N>- vẫn thắng; 0 / ≥ 2 issue hay issue repo khác thì không nhận.
#   C. #637: đọc GitHub hỏng khi route một PR không cắt dở các PR còn lại và merge-queue.attempts; halt (79) thoát 79 sau khi route xong.
#   D. #639: gate-exit-11 (preflight qa-report) không bị ghi là verify đỏ; `red` thật vẫn ghi verify đỏ.
#   E. #637 (audit Antigravity): thẻ của PR đã merge đọc hỏng ⇒ như chưa route (nhãn giữ, không pending, không tính lần thử);
#      lượt sau recover_merged route lại và comment ✅ merged trên thẻ.
#   F. #637 (audit Antigravity): halt giữa lượt route: thẻ của PR red đọc hỏng, card_move của PR gate-exit-3 nhận 79, PR deferred
#      đứng sau vẫn được đếm; exit 79 không tính lần thử; lượt sau comment trên thẻ còn thiếu, không comment trùng trên PR.
#   G. #637 (review Claude): issue lấy qua closingIssuesReferences mà không nằm trên board (card.sh exit 3) ⇒ PR như không có thẻ
#      (hành vi cũ: gỡ nhãn sạch), không pending, không tính lần thử, không comment / đóng issue đó.
#   H. Train không in train-result, PR ở lần thử thứ 3: card_move Blocked nhận 79 ⇒ hàng đợi vẫn thoát 79 (hợp đồng header), PR giữ
#      nhãn và dòng attempts, không comment "left the queue" (thẻ chưa Blocked) — như bản cũ thoát 79 ngay tại card_move.
#   I. Như H nhưng PR có train-result `deferred` (đường route_one).
# Chạy offline: gh (python giả), train / card.sh / needs-you.py / notify.py là stub; github-read.py là bản thật. Tương thích bash 3.2.
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
run_q() { ( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" ) >"$TMP/out" 2>"$TMP/err"; }
has_w() { grep -qF -- "$1" "$F/writes"; }

# ── A. #762: hàng route lớn hơn bộ đệm ống. PR 1 gắn nhãn sớm nhất (dòng đầu, awk khớp ngay), PR 2 và 3 mang nhánh ~400 KB.
LONG=$(head -c 400000 /dev/zero | tr '\0' x)
reset
pr 1 issue-11-a 30; pr 2 "b-$LONG" 20; pr 3 "c-$LONG" 10; issue 11
printf 'train-result: 1 red\ntrain-result: 2 deferred\ntrain-result: 3 deferred\n' > "$F/train.out"; echo 11 > "$F/train.rc"
run_q; rc=$?
[ "$rc" -eq 0 ] && ok "#762 route rows > pipe buffer: exit 0" || fail "#762 route rows > pipe buffer: rc=$rc: $(tail -c 300 "$TMP/err")"
has_w "issue-labels 11 loop:rebuild-1" && has_w "card move 11 Ready" && ok "  … card_of found card #11 on the first row (red → loop:rebuild-1, Ready)" || fail "  … card #11 not routed: $(head -c 300 "$F/writes")"
grep -q "^2 $(sha 2) 1 " "$ATT" 2>/dev/null && grep -q "^3 $(sha 3) 1 " "$ATT" && ok "  … head_of: deferred PRs 2 and 3 counted once each" || fail "  … attempts: $(cut -c1-80 "$ATT" 2>/dev/null)"
# Lượt 2: merge-queue.labeled (cache của load_rows) giờ chứa hai dòng ~400 KB; tra PR 2 khớp dòng giữa, phần sau còn > bộ đệm ống.
: > "$F/writes"
run_q; rc=$?
[ "$rc" -eq 0 ] && grep -q "^2 $(sha 2) 2 " "$ATT" 2>/dev/null && ok "#762 load_rows cache > pipe buffer: exit 0, PR 2 counted again" || fail "#762 cache: rc=$rc att=$(cut -c1-80 "$ATT" 2>/dev/null) err=$(tail -c 300 "$TMP/err")"

# ── B. #637: thẻ qua closingIssuesReferences khi nhánh không theo mẫu issue-<N>-.
reset
pr 4 fix-foo 50 "[$(ref 14)]"
pr 5 issue-15-x 40 "[$(ref 99)]"
pr 6 fix-two 30 "[$(ref 16),$(ref 17)]"
pr 7 fix-none 20
pr 8 fix-other 10 "[$(ref 18 other repo)]"
for k in 14 15 16 17 18 99; do issue "$k"; done
for n in 4 5 6 7 8; do sha "$n" c > "$F/merged-$n"; done
printf 'train-result: 4 merged\ntrain-result: 5 merged\ntrain-result: 6 merged\ntrain-result: 7 merged\ntrain-result: 8 merged\n' > "$F/train.out"; echo 0 > "$F/train.rc"
run_q; rc=$?
[ "$rc" -eq 0 ] && ok "#637 batch of merged PRs: exit 0" || fail "#637 batch: rc=$rc: $(tail -5 "$TMP/err")"
has_w "card move 14 Done" && has_w "issue-close 14" && has_w "issue-comment 14 [merge-queue] [report] ✅ merged" \
  && ok "#637 branch fix-foo closing #14: card #14 closed, Done, ✅ comment" || fail "#637 fix-foo: $(cat "$F/writes")"
has_w "card move 15 Done" && ! has_w "card move 99" && ok "#637 branch issue-15-… wins over closingIssuesReferences #99" || fail "#637 branch wins: $(cat "$F/writes")"
has_w "card move 16" || has_w "card move 17" && fail "#637 a PR closing 2 issues was mapped to a card" || ok "#637 PR closing 2 issues: no card"
grep -q "^card move 18\|^issue-close 18" "$F/writes" && fail "#637 a PR closing an issue of another repo was mapped to a card" || ok "#637 closing ref in another repository: no card"
has_w "pr-unlabel 7 merge-queue" && has_w "pr-unlabel 6 merge-queue" && ok "#637 card-less merged PRs: label removed as before" || fail "#637 card-less: $(cat "$F/writes")"

# ── C. #637: trạng thái PR 2 đọc ra sai dạng (github-read thử 3 lần, halt) giữa lượt route: PR 3 vẫn được route, thoát 79 sau cùng.
reset
pr 1 issue-11-a 30; pr 2 issue-12-b 20; pr 3 issue-13-c 10; issue 11; issue 12; issue 13
: > "$F/state-broken-2"; sha 2 c > "$F/merged-2"
printf 'train-result: 1 deferred\ntrain-result: 2 merged\ntrain-result: 3 timeout\n' > "$F/train.out"; echo 12 > "$F/train.rc"
run_q; rc=$?
grep -q "^1 $(sha 1) 1 " "$ATT" 2>/dev/null && grep -q "^3 $(sha 3) 1 " "$ATT" \
  && ok "#637 read failure on PR 2 mid-route: PR 1 and PR 3 still counted in merge-queue.attempts" || fail "#637 cut mid-route: rc=$rc att=$(cat "$ATT" 2>/dev/null) err=$(tail -3 "$TMP/err")"
[ "$rc" -eq 79 ] && ok "  … github-read halted: exit 79 after routing the rest" || fail "  … rc=$rc (want 79): $(tail -3 "$TMP/err")"
has_w "pr-unlabel 2" && fail "  … PR 2 (state unreadable) lost its label" || ok "  … PR 2 keeps its label"
grep -q "PR #2: reading its merge state failed" "$TMP/err" && ok "  … the log names the PR and the failed read" || fail "  … log: $(tail -3 "$TMP/err")"

# ── D. #639: gate-exit-11 của preflight (qa-report) ≠ verify đỏ.
reset
pr 9 issue-19-a 20; pr 10 issue-20-b 10; issue 19; issue 20
printf 'train-result: 9 gate-exit-11\ntrain-detail: 9 qa-report: proof line missing\ntrain-result: 10 red\ntrain-detail: 10 FAILED tests/test_x.py::test_y\n' > "$F/train.out"; echo 11 > "$F/train.rc"
run_q; rc=$?
[ "$rc" -eq 0 ] && has_w "issue-labels 19 loop:rebuild-1" && has_w "card move 19 Ready" && ok "#639 gate-exit-11: still back to Build (loop:rebuild-1, Ready)" || fail "#639 route: rc=$rc $(cat "$F/writes")"
grep -qi "verify red\|turns it red" "$F/pr-comment-9.txt" "$F/issue-comment-19.txt" 2>/dev/null && fail "#639 preflight exit 11 is still called a red verify: $(cat "$F/pr-comment-9.txt" "$F/issue-comment-19.txt" 2>/dev/null)" \
  || ok "#639 preflight exit 11: no 'verify red' in the PR or issue comment"
grep -q "preflight" "$F/pr-comment-9.txt" 2>/dev/null && grep -q "qa-report" "$F/pr-comment-9.txt" && grep -q "preflight qa-report" "$F/issue-comment-19.txt" 2>/dev/null \
  && ok "#639 the comments name the preflight source (qa-report)" || fail "#639 source: $(cat "$F/pr-comment-9.txt" "$F/issue-comment-19.txt" 2>/dev/null)"
grep -q "verify red with this PR in the batch" "$F/issue-comment-20.txt" 2>/dev/null && grep -q "this PR is the one that turns it red" "$F/pr-comment-10.txt" 2>/dev/null \
  && ok "#639 a real red verify still says 'verify red with this PR in the batch'" || fail "#639 red text: $(cat "$F/pr-comment-10.txt" "$F/issue-comment-20.txt" 2>/dev/null)"

PEND="$COMMON/super-board/merge-queue.pending"
cnt() { grep -c -- "$2" "$1" 2>/dev/null || true; }   # cnt <file> <chuỗi>: số dòng chứa chuỗi (file thiếu → 0)

# ── E. Thẻ #11 của PR 1 (train báo merged) đọc ra sai dạng ⇒ halt. PR 2 deferred đứng sau.
reset
pr 1 issue-11-a 30; pr 2 issue-12-b 20; issue 11; issue 12
sha 1 c > "$F/merged-1"; : > "$F/issue-broken-11"
printf 'train-result: 1 merged\ntrain-result: 2 deferred\n' > "$F/train.out"; echo 12 > "$F/train.rc"
run_q; rc=$?
[ "$rc" -eq 79 ] && grep -q "^2 $(sha 2) 1 " "$ATT" 2>/dev/null && ok "E card of a merged PR unreadable: exit 79, PR 2 after it still counted" || fail "E rc=$rc att=$(cat "$ATT" 2>/dev/null) err=$(tail -3 "$TMP/err")"
grep -q "^1 " "$ATT" 2>/dev/null && fail "E the halted card read was counted as a try for PR 1: $(cat "$ATT")" || ok "  … PR 1 not counted (a halt is not a try)"
grep -q "^1 " "$PEND" 2>/dev/null && fail "E PR 1 went to merge-queue.pending, so the next run would skip its ✅ comment: $(cat "$PEND")" || ok "  … PR 1 not in merge-queue.pending (nothing was written for it)"
has_w "pr-unlabel 1" && fail "  … PR 1 lost its label" || ok "  … PR 1 keeps its label"
# Lượt sau: GitHub đã ghi PR 1 MERGED, halt gỡ (--resume), thẻ đọc được ⇒ recover_merged route PR 1.
rm -f "$TMP/halt.json" "$F/issue-broken-11"; : > "$F/writes"
PRS_ROWS=""; pr 1 issue-11-a 30 "[]" MERGED; pr 2 issue-12-b 20
printf 'train-result: 2 deferred\n' > "$F/train.out"
run_q; rc=$?
[ "$rc" -eq 0 ] && has_w "issue-comment 11 [merge-queue] [report] ✅ merged" && has_w "card move 11 Done" && has_w "pr-unlabel 1 merge-queue" \
  && ok "E next run: card #11 gets its ✅ merged comment, Done, PR 1 unlabelled" || fail "E next run: rc=$rc $(cat "$F/writes") err=$(tail -3 "$TMP/err")"

# ── F. PR 1 red: thẻ #11 đọc hỏng ⇒ halt. PR 2 gate-exit-3: comment xong, card_move nhận 79 (halt). PR 3 deferred đứng sau.
reset
pr 1 issue-11-a 30; pr 2 issue-12-b 20; pr 3 issue-13-c 10; issue 11; issue 12; issue 13
: > "$F/issue-broken-11"
printf 'train-result: 1 red\ntrain-result: 2 gate-exit-3\ntrain-result: 3 deferred\n' > "$F/train.out"; echo 12 > "$F/train.rc"
run_q; rc=$?
[ "$rc" -eq 79 ] && grep -q "^3 $(sha 3) 1 " "$ATT" 2>/dev/null && ok "F halt mid-route (card read, then card_move 79): exit 79, PR 3 after them still counted" || fail "F rc=$rc att=$(cat "$ATT" 2>/dev/null) err=$(tail -3 "$TMP/err")"
grep -q "^[12] " "$ATT" 2>/dev/null && fail "F a halted route was counted as a try: $(cat "$ATT")" || ok "  … PR 1 and PR 2 not counted (a halt is not a try)"
grep -q "^1 $(sha 1) red " "$PEND" 2>/dev/null && grep -q "^2 $(sha 2) gate-exit-3 " "$PEND" && ok "  … PR 1 and PR 2 wait in merge-queue.pending (no second verify)" || fail "  … pending: $(cat "$PEND" 2>/dev/null)"
has_w "pr-unlabel 1" || has_w "pr-unlabel 2" && fail "  … a PR whose route did not finish lost its label: $(cat "$F/writes")" || ok "  … PR 1 and PR 2 keep their labels"
# Lượt sau: halt gỡ, thẻ đọc được ⇒ route lại từ pending.
rm -f "$TMP/halt.json" "$F/issue-broken-11"; : > "$F/writes"
printf 'train-result: 3 deferred\n' > "$F/train.out"; echo 0 > "$F/train.rc"
run_q; rc=$?
[ "$rc" -eq 0 ] && has_w "issue-labels 11 loop:rebuild-1" && has_w "card move 11 Ready" && has_w "card move 12 Blocked" \
  && ok "F next run: PR 1 back to Build (loop:rebuild-1, Ready), card #12 Blocked" || fail "F next run: rc=$rc $(cat "$F/writes") err=$(tail -3 "$TMP/err")"
[ "$(cnt "$F/issue-comment-11.txt" '❌ red · PR #1 back to Build')" = 1 ] && ok "  … card #11 gets the ❌ red comment it never got" || fail "  … card #11 comments: $(cat "$F/issue-comment-11.txt" 2>/dev/null)"
[ "$(cnt "$F/pr-comment-1.txt" '❌ red · red')" = 1 ] && [ "$(cnt "$F/issue-comment-12.txt" 'blocked · 🔑')" = 1 ] \
  && ok "  … no second PR 1 comment, no second blocker on card #12" || fail "  … duplicates: pr1=$(cnt "$F/pr-comment-1.txt" '❌ red · red') card12=$(cnt "$F/issue-comment-12.txt" 'blocked · 🔑')"
has_w "pr-unlabel 1 merge-queue" && has_w "pr-unlabel 2 merge-queue" && ok "  … PR 1 and PR 2 leave the queue" || fail "  … labels: $(cat "$F/writes")"

# ── G. PR 4 nhánh fix-bar đóng #21; #21 không nằm trên board.
reset
pr 4 fix-bar 20 "[$(ref 21)]"; issue 21; : > "$F/offboard-21"; sha 4 c > "$F/merged-4"
printf 'train-result: 4 merged\n' > "$F/train.out"; echo 0 > "$F/train.rc"
run_q; rc=$?
[ "$rc" -eq 0 ] && has_w "pr-unlabel 4 merge-queue" && ok "G closing issue not on the board: PR 4 leaves the queue as a card-less PR" || fail "G rc=$rc $(cat "$F/writes") err=$(tail -3 "$TMP/err")"
grep -q "^4 " "$PEND" "$ATT" 2>/dev/null && fail "G PR 4 went to pending / attempts: $(cat "$PEND" "$ATT" 2>/dev/null)" || ok "  … no pending row, no try counted"
has_w "issue-comment 21" || has_w "issue-close 21" || has_w "card move 21" && fail "  … issue #21 (not a card) was routed: $(cat "$F/writes")" || ok "  … issue #21 untouched (not a card)"

# ── H. Train thoát 1, không train-result; PR 1 đã 2 lần thử cùng head; card_move Blocked ở trần nhận 79.
reset
pr 1 issue-11-a 20; issue 11
mkdir -p "$COMMON/super-board"; echo "1 $(sha 1) 2 $(date +%s)" > "$ATT"
: > "$F/train.out"; echo 1 > "$F/train.rc"; : > "$F/card-halt"
run_q; rc=$?
[ "$rc" -eq 79 ] && ok "H no train-result, card_move at the cap halted: exit 79" || fail "H rc=$rc (want 79): $(tail -3 "$TMP/err")"
has_w "pr-unlabel 1" || has_w "pr-comment 1 [merge-queue] [blocker] 🛑 left the queue" && fail "  … PR 1 left the queue although card #11 was not moved: $(cat "$F/writes")" \
  || ok "  … PR 1 keeps its label, no 'left the queue' comment"
grep -q "^1 $(sha 1) " "$ATT" 2>/dev/null && ok "  … its attempts row is kept (the next run retries the cap)" || fail "  … attempts row gone: $(cat "$ATT" 2>/dev/null)"

# ── I. Như H, PR 1 có train-result deferred.
reset
pr 1 issue-11-a 20; issue 11
mkdir -p "$COMMON/super-board"; echo "1 $(sha 1) 2 $(date +%s)" > "$ATT"
printf 'train-result: 1 deferred\n' > "$F/train.out"; echo 0 > "$F/train.rc"; : > "$F/card-halt"
run_q; rc=$?
[ "$rc" -eq 79 ] && ! has_w "pr-unlabel 1" && ! has_w "left the queue" && grep -q "^1 $(sha 1) " "$ATT" 2>/dev/null \
  && ok "I deferred at the cap, card_move halted: exit 79, label and attempts row kept, no 'left the queue'" || fail "I rc=$rc att=$(cat "$ATT" 2>/dev/null) writes=$(cat "$F/writes")"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_queue_route_rows: all passed" || { echo "❌ test_merge_queue_route_rows: $FAILS failed"; exit 1; }
