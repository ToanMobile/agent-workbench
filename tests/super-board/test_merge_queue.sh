#!/usr/bin/env bash
# Test (Pha 2) cho .claude/bin/super-board-merge-queue.sh — bộ gom đứng riêng: PR mở, không draft, có nhãn merge-queue + approved-head
# hợp lệ khớp head → MỘT lượt super-board-merge-train.sh; route từng `train-result:`; --if-due; khoá chạy chồng; đợt sau đỏ thu nhỏ.
# Chạy offline: gh (python giả), train / card.sh / needs-you.py là stub ghi lại lời gọi; github-read.py là bản thật. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mq-test.XXXXXX")"
PIDS=""
# Chỉ giết đúng PID test này tự chạy (không bao giờ pkill theo tên).
cleanup() { for p in $PIDS $(cat "$TMP/train.pids" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
F="$TMP/fake"; R="$TMP/repo"; Q="$TMP/qbin"
mkdir -p "$F/labeled" "$Q" "$TMP/path"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"; git -C "$R" add .gitignore; git -C "$R" commit -qm init
INF="$R/.claude/super-board/inflight"; mkdir -p "$INF"
COMMON="$(cd "$R" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
STATE="$COMMON/super-board/merge-queue.state"
ATT="$COMMON/super-board/merge-queue.attempts"

# Bộ gom thật + github-read thật (symlink: HERE của script là $Q), các helper khác là stub.
ln -s "$ROOT/.claude/bin/super-board-merge-queue.sh" "$Q/super-board-merge-queue.sh"
ln -s "$ROOT/.claude/bin/super-board-github-read.py" "$Q/super-board-github-read.py"
ln -s "$ROOT/.claude/bin/super-board-approved-head.jq" "$Q/super-board-approved-head.jq"
QUEUE="$Q/super-board-merge-queue.sh"
cat > "$Q/super-board-merge-train.sh" <<'SH'
#!/usr/bin/env bash
echo "train caller=${SB_MERGE_CALLER:-<unset>} $*" >> "$FAKE/calls"
echo "$$" >> "$TRAIN_PIDS"
if [ -e "$FAKE/train.hold" ]; then
  : > "$FAKE/train.started"; i=0
  while [ -e "$FAKE/train.hold" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
fi
[ -f "$FAKE/train.out" ] && cat "$FAKE/train.out"
exit "$(cat "$FAKE/train.rc" 2>/dev/null || echo 0)"
SH
cat > "$Q/super-board-card.sh" <<'SH'
#!/usr/bin/env bash
while [ "${1#--}" != "$1" ]; do shift 2; done
echo "card $*" >> "$FAKE/writes"
exit "$(cat "$FAKE/card.rc" 2>/dev/null || echo 0)"
SH
cat > "$Q/super-board-needs-you.py" <<'PY'
import os, sys
open(os.environ['FAKE'] + '/writes', 'a').write('needs-you ' + ' '.join(sys.argv[1:]) + '\n')
PY
cat > "$Q/super-board-notify.py" <<'PY'
import os, sys
open(os.environ['FAKE'] + '/writes', 'a').write('notify ' + ' '.join(sys.argv[1:]) + '\n')
PY
chmod +x "$Q"/*.sh "$Q/super-board-needs-you.py"
# gh giả. PR: $FAKE/prs.json; nhãn merge-queue = $FAKE/labeled/<N> (nội dung = mốc gắn nhãn ISO); comment: $FAKE/comments-<N>.json;
# issue: $FAKE/issue-<K>.json; PR đã merge: $FAKE/merged-<N>. Mọi lệnh ghi một dòng vào $FAKE/writes.
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
    open(F + '/reads', 'a').write('list ' + ' '.join(a[2:]) + '\n')
    st = (opt('--state') or 'open').upper()
    prs = [p for p in json.load(open(F + '/prs.json')) if p.get('state', 'OPEN') == st]
    for p in prs:
        p.pop('state', None)
    if opt('--label') == 'merge-queue':
        prs = [p for p in prs if os.path.exists(f"{F}/labeled/{p['number']}")]
    print(json.dumps(prs))
elif a[:2] == ['pr', 'view'] and opt('--json') == 'comments':
    open(F + '/reads', 'a').write(f'comments {num()}\n')
    p = f'{F}/comments-{num()}.json'
    print(open(p).read() if os.path.exists(p) else '{"comments":[]}')
elif a[:2] == ['pr', 'view'] and opt('--json') == 'title':
    print('title of PR ' + num())
elif a[:2] == ['pr', 'view'] and 'state' in (opt('--json') or ''):
    n = num(); m = f'{F}/merged-{n}'
    if os.path.exists(m):
        print(json.dumps({'state': 'MERGED', 'mergeCommit': {'oid': open(m).read().strip()}, 'headRefOid': 'a' * 40}))
    else:
        print(json.dumps({'state': 'OPEN', 'mergeCommit': None, 'headRefOid': 'a' * 40}))
elif a[0] == 'api' and '/timeline' in a[1]:
    n = a[1].split('/issues/')[1].split('/')[0]; p = f'{F}/labeled/{n}'
    open(F + '/reads', 'a').write(f'timeline {n}\n')
    ev = [{'event': 'commented', 'created_at': '2020-01-01T00:00:00Z'}]
    if os.path.exists(p):
        ev.append({'event': 'labeled', 'label': {'name': 'merge-queue'}, 'created_at': open(p).read().strip()})
    print(json.dumps([ev]))
elif a[:2] == ['issue', 'view']:
    print(json.dumps(issue(num())))
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
export PATH="$TMP/path:$PATH" FAKE="$F" TRAIN_PIDS="$TMP/train.pids" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_QUEUE SB_MERGE_CALLER SB_GITHUB_READ_STRICT

cfg() {   # cfg <enabled> <batch_max> [max_wait_min]
  printf '{"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"worker_backend":"claude-p","rebuild_cap":2,"verify_commands":["true"],"merge_queue":{"enabled":%s,"enabled_at":null,"batch_max":%s,"max_wait_min":%s}}\n' "$1" "$2" "${3:-60}" > "$TMP/cfg.json"
}
ago() { python3 -c 'import datetime,sys;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
sha() { printf '%040d' "$1" | tr 0 "${2:-a}"; }
# pr <N> <branch> <minutes since labeled> [draft] [state]: PR có nhãn (mặc định mở), head = sha(N).
PRS_ROWS=""
pr() {
  PRS_ROWS="${PRS_ROWS}${PRS_ROWS:+,}{\"number\":$1,\"headRefName\":\"$2\",\"headRefOid\":\"$(sha "$1")\",\"isDraft\":${4:-false},\"state\":\"${5:-OPEN}\"}"
  printf '[%s]\n' "$PRS_ROWS" > "$F/prs.json"
  ago "$3" > "$F/labeled/$1"
}
approve() {   # approve <N> <assoc> <sha>
  printf '{"comments":[{"authorAssociation":"%s","body":"[reviewer] [report] ✅ pass"},{"authorAssociation":"%s","body":"approved-head:%s"}]}' "$2" "$2" "$3" > "$F/comments-$1.json"
}
issue() {   # issue <K> [labels comma]
  local labs="" l
  for l in $(echo "${2:-}" | tr ',' ' '); do labs="${labs}${labs:+,}{\"name\":\"$l\"}"; done
  printf '{"number":%s,"title":"card %s","body":"","state":"OPEN","labels":[%s]}' "$1" "$1" "$labs" > "$F/issue-$1.json"
}
reset() {
  rm -rf "$F"; mkdir -p "$F/labeled"; PRS_ROWS=""; printf '[]\n' > "$F/prs.json"; : > "$F/writes"; : > "$F/calls"
  rm -f "$INF"/[0-9]* "$STATE" "$COMMON/super-board/merge-queue.labeled" "$ATT" "$COMMON/super-board/merge-queue.lock.pid" "$COMMON/super-board/merge-queue.pending"; rm -rf "$INF/merge.lock"
}
run_q() { ( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" "$@" ) >"$TMP/out" 2>"$TMP/err"; }
calls() { grep -c '^train ' "$F/calls" 2>/dev/null | tr -d ' '; }
has_w() { grep -qF -- "$1" "$F/writes"; }

# ── 1. Tắt theo config (mặc định), SB_MERGE_QUEUE ghi đè hai chiều.
reset; cfg false 6; pr 1 issue-11-a 5; approve 1 OWNER "$(sha 1)"; issue 11
run_q; rc=$?
[ "$rc" -eq 0 ] && [ "$(calls)" = 0 ] && ok "disabled by config: exit 0, no train" || fail "disabled: rc=$rc calls=$(calls): $(cat "$TMP/err")"
( export SB_MERGE_QUEUE=1; run_q ); rc=$?
[ "$rc" -eq 0 ] && [ "$(calls)" = 1 ] && ok "SB_MERGE_QUEUE=1 turns it on over the config" || fail "SB_MERGE_QUEUE=1: rc=$rc calls=$(calls): $(cat "$TMP/err")"
reset; cfg true 6; pr 1 issue-11-a 5; approve 1 OWNER "$(sha 1)"; issue 11
( export SB_MERGE_QUEUE=0; run_q ); rc=$?
[ "$rc" -eq 0 ] && [ "$(calls)" = 0 ] && ok "SB_MERGE_QUEUE=0 turns it off over the config" || fail "SB_MERGE_QUEUE=0: rc=$rc calls=$(calls)"
# fix-round1-contract: bật cần thêm worker_backend "claude-p" (thiếu = workflow); backend khác = tắt, cả khi SB_MERGE_QUEUE=1.
jq '.worker_backend = "workflow"' "$TMP/cfg.json" > "$TMP/cfg.tmp" && mv "$TMP/cfg.tmp" "$TMP/cfg.json"
( export SB_MERGE_QUEUE=1; run_q ); rc=$?
[ "$rc" -eq 0 ] && [ "$(calls)" = 0 ] && ok "worker_backend workflow: off even with SB_MERGE_QUEUE=1" || fail "workflow backend: rc=$rc calls=$(calls)"
jq 'del(.worker_backend)' "$TMP/cfg.json" > "$TMP/cfg.tmp" && mv "$TMP/cfg.tmp" "$TMP/cfg.json"
run_q; rc=$?
[ "$rc" -eq 0 ] && [ "$(calls)" = 0 ] && ok "no worker_backend (= workflow): off with merge_queue.enabled true" || fail "no backend: rc=$rc calls=$(calls)"

# ── 2. Chọn PR: 3 hợp lệ → MỘT train, cũ nhất trước; approved-head lệch / người ngoài → gỡ nhãn + comment; draft → bỏ qua, giữ nhãn.
reset; cfg true 6
pr 1 issue-11-a 10; pr 2 issue-12-b 30; pr 3 feature-x 20; pr 4 issue-14-d 40; pr 5 issue-15-e 50; pr 6 issue-16-f 60 true
# #605 Lane H: approved-head trơn chỉ của OWNER; MEMBER/COLLABORATOR trơn bị loại (ca riêng ở cuối file).
approve 1 OWNER "$(sha 1)"; approve 2 OWNER "$(sha 2)"; approve 3 OWNER "$(sha 3)"
approve 4 OWNER "$(sha 4 b)"; approve 5 CONTRIBUTOR "$(sha 5)"; approve 6 OWNER "$(sha 6)"
issue 11; issue 12 ac-open; issue 14; issue 15; issue 16
printf '%s\n' "$(sha 1 c)" > "$F/merged-1"; printf '%s\n' "$(sha 2 c)" > "$F/merged-2"; printf '%s\n' "$(sha 3 c)" > "$F/merged-3"
printf 'train-result: 1 merged\ntrain-result: 2 merged\ntrain-result: 3 merged\n' > "$F/train.out"
run_q; rc=$?
[ "$rc" -eq 0 ] && ok "3 valid PRs: exit 0" || fail "3 valid PRs: rc=$rc: $(tail -5 "$TMP/err")"
[ "$(calls)" = 1 ] && ok "3 valid PRs: exactly one train" || fail "3 valid PRs: $(calls) trains"
grep -q -- "--prs 2:$(sha 2),3:$(sha 3),1:$(sha 1)\$" "$F/calls" && ok "  … oldest labelled first, each pinned to its approved head" || fail "  … wrong --prs: $(cat "$F/calls")"
grep -q "caller=queue" "$F/calls" && ok "  … SB_MERGE_CALLER=queue for the train" || fail "  … caller: $(cat "$F/calls")"
has_w "pr-unlabel 4 merge-queue" && has_w "pr-comment 4 " && ok "approved-head off the head: unlabelled + commented" || fail "PR 4 not rejected: $(cat "$F/writes")"
has_w "pr-unlabel 5 merge-queue" && has_w "pr-comment 5 " && ok "approved-head by an outsider: unlabelled + commented" || fail "PR 5 not rejected: $(cat "$F/writes")"
has_w "pr-unlabel 6" && fail "draft PR was unlabelled" || ok "draft PR skipped, label kept"
grep -q -- "6:" "$F/calls" && fail "draft PR went into the train" || ok "draft PR not in the train"
has_w "issue-close 11" && has_w "card move 11 Done" && has_w "issue-comment 11 [merge-queue] [report] ✅ merged" \
  && ok "merged card: issue closed, card Done, merged comment" || fail "merged card #11: $(cat "$F/writes")"
has_w "issue-close 12" || has_w "card move 12 Done" && fail "ac-open card #12 was closed / moved to Done" || ok "merged card with ac-open: left open (gate moved it to Ready)"
has_w "pr-unlabel 1 merge-queue" && has_w "pr-unlabel 3 merge-queue" && ok "merged PRs: label removed" || fail "merged PRs keep the label: $(cat "$F/writes")"
# Chạy lại: PR đã bị loại không bị comment lần hai (idempotent).
: > "$F/train.out"; run_q
[ "$(grep -c '^pr-comment 4 ' "$F/writes")" = 1 ] && ok "second run: a rejected PR is not commented again" || fail "second run re-commented PR 4"

# ── 3. --if-due.
reset; cfg true 6 60
pr 1 issue-11-a 5; pr 2 issue-12-b 5; approve 1 OWNER "$(sha 1)"; approve 2 OWNER "$(sha 2)"; issue 11; issue 12
# Train giả ở ca này in `deferred` (không kết thúc, giữ nhãn); xoá số lần thử trước mỗi lượt để trần 3 lần (ca 9) không gỡ nhãn giữa ca.
printf 'train-result: 1 deferred\ntrain-result: 2 deferred\n' > "$F/train.out"
run_q() { rm -f "$ATT"; ( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" "$@" ) >"$TMP/out" 2>"$TMP/err"; }
sleep 60 & LIVE=$!; PIDS="$PIDS $LIVE"
printf 'PID=%s\nLANE=build\n' "$LIVE" > "$INF/77"
run_q --if-due; rc=$?
[ "$rc" -eq 0 ] && [ "$(calls)" = 0 ] && ok "--if-due: 2 PRs, 5 min old, a worker alive → not due" || fail "--if-due busy: rc=$rc calls=$(calls): $(cat "$TMP/err")"
grep -q '^comments' "$F/reads" 2>/dev/null && fail "--if-due not due: approval comments were read (GraphQL per PR per tick)" || ok "--if-due not due: no approval comment read"
: > "$F/reads"; run_q --if-due
grep -q '^timeline' "$F/reads" && fail "--if-due second tick re-read the timelines: $(cat "$F/reads")" || ok "--if-due second tick: labelled times come from the cache"
rm -f "$COMMON/super-board/merge-queue.labeled"   # mốc gắn nhãn đổi dưới đây: đọc lại timeline
ago 61 > "$F/labeled/2"
run_q --if-due
[ "$(calls)" = 1 ] && ok "--if-due: oldest waited 61 min ≥ max_wait_min → due" || fail "--if-due age: calls=$(calls): $(cat "$TMP/err")"
: > "$F/calls"; ago 5 > "$F/labeled/2"; cfg true 2 60; rm -f "$COMMON/super-board/merge-queue.labeled"
run_q --if-due
[ "$(calls)" = 1 ] && ok "--if-due: count reaches batch_max → due (worker still alive)" || fail "--if-due count: calls=$(calls)"
: > "$F/calls"; cfg true 6 60; rm -f "$INF/77"
printf 'PID=999999\nLANE=build\n' > "$INF/78"
run_q --if-due
[ "$(calls)" = 1 ] && ok "--if-due: no live worker (dead PID in inflight), no gate → idle → due" || fail "--if-due idle: calls=$(calls): $(cat "$TMP/err")"
# merge.lock của gate còn sống (holder sống, mới) → bận; holder chết + quá stale-after → không bận. Không bao giờ xoá khoá.
: > "$F/calls"; mkdir -p "$INF/merge.lock"
echo "$LIVE" > "$INF/merge.lock/pid"; ps -o pgid= -p "$LIVE" | tr -d ' ' > "$INF/merge.lock/pgid"; hostname > "$INF/merge.lock/host"; date +%s > "$INF/merge.lock/at"
run_q --if-due
[ "$(calls)" = 0 ] && ok "--if-due: a live merge.lock holder → busy" || fail "--if-due merge.lock live: calls=$(calls)"
echo 999999 > "$INF/merge.lock/pid"; echo 999999 > "$INF/merge.lock/pgid"; echo $(( $(date +%s) - 6000 )) > "$INF/merge.lock/at"
run_q --if-due
[ "$(calls)" = 1 ] && ok "--if-due: merge.lock of a dead holder past stale-after → idle" || fail "--if-due merge.lock dead: calls=$(calls): $(cat "$TMP/err")"
[ -d "$INF/merge.lock" ] && ok "  … the queue never reaps the gate's lock" || fail "  … merge.lock was removed"
# Busy = holder còn VÀ khoá chưa quá stale-after (cả hai): holder chết + khoá mới → rảnh; holder sống + khoá quá 6000 s → rảnh.
: > "$F/calls"; date +%s > "$INF/merge.lock/at"
run_q --if-due
[ "$(calls)" = 1 ] && ok "--if-due: merge.lock of a dead holder, fresh → idle" || fail "--if-due dead fresh: calls=$(calls)"
: > "$F/calls"; echo "$LIVE" > "$INF/merge.lock/pid"; ps -o pgid= -p "$LIVE" | tr -d ' ' > "$INF/merge.lock/pgid"; echo $(( $(date +%s) - 6000 )) > "$INF/merge.lock/at"
run_q --if-due
[ "$(calls)" = 1 ] && ok "--if-due: merge.lock of a live holder past stale-after → idle" || fail "--if-due live stale: calls=$(calls)"
rm -rf "$INF/merge.lock"
# test_run.lock của post-fix-gate trong một worktree đang bị giữ → bận.
: > "$F/calls"; git -C "$R" worktree add -q --detach "$TMP/wt1" HEAD
mkdir -p "$TMP/wt1/.claude/audit-gate"; : > "$TMP/wt1/.claude/audit-gate/test_run.lock"
python3 -c 'import fcntl,sys,time;f=open(sys.argv[1],"a");fcntl.flock(f,fcntl.LOCK_EX);open(sys.argv[2],"w").close();time.sleep(60)' \
  "$TMP/wt1/.claude/audit-gate/test_run.lock" "$TMP/held" & HOLD=$!; PIDS="$PIDS $HOLD"
i=0; while [ ! -e "$TMP/held" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
run_q --if-due
[ "$(calls)" = 0 ] && ok "--if-due: a held test_run.lock in a worktree → busy" || fail "--if-due test_run.lock: calls=$(calls): $(cat "$TMP/err")"
kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null
run_q --if-due
[ "$(calls)" = 1 ] && ok "--if-due: test_run.lock released → due" || fail "--if-due test_run.lock released: calls=$(calls)"
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null
run_q() { ( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" "$@" ) >"$TMP/out" 2>"$TMP/err"; }

# ── 4. Hai lượt chạy chồng. Ca này khẳng định: lượt sau thoát 0 ngay (khoá fcntl) và số lời gọi train vẫn là 1.
reset; cfg true 6
pr 1 issue-11-a 5; approve 1 OWNER "$(sha 1)"; issue 11
: > "$F/train.hold"
( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" ) >"$TMP/out1" 2>"$TMP/err1" & FIRST=$!; PIDS="$PIDS $FIRST"
i=0; while [ ! -e "$F/train.started" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
run_q; rc=$?
[ "$rc" -eq 0 ] && [ "$(calls)" = 1 ] && ok "overlapping run: exits 0 at once, no second train" || fail "overlap: rc=$rc calls=$(calls): $(cat "$TMP/err")"
grep -qi "lock\|another" "$TMP/err" && ok "  … and says the queue is held" || fail "  … no busy message: $(cat "$TMP/err")"
rm -f "$F/train.hold"; wait "$FIRST"; rc=$?
[ "$rc" -eq 0 ] && ok "  … the first run finishes normally" || fail "  … first run rc=$rc: $(cat "$TMP/err1")"

# ── 5. Route từng kết quả (rebuild_cap = 2).
reset; cfg true 10
for n in 21 22 23 24 25 26 27 28 29; do pr "$n" "issue-$((n + 10))-x" 5; approve "$n" OWNER "$(sha "$n")"; done
issue 31; issue 32; issue 33; issue 34; issue 35; issue 36; issue 37 loop:rebuild-2; issue 38; issue 39 loop:rebuild-1
cat > "$F/train.out" <<'EOF'
train-detail: 25 human-gate: money — label money
train-detail: 25 approval-request: req-25
train-result: 21 red
train-red: 21
train-result: 22 conflict
train-result: 23 timeout
train-result: 24 head-moved
train-result: 25 gate-exit-7
train-result: 26 gate-exit-3
train-result: 27 gate-exit-5
train-result: 28 deferred
train-result: 29 gate-exit-11
train-detail: 21 ac-check: the sb:ac block lists 1 of 3
train-detail: 21 FAILED tests/test_x.py::test_y
train-detail: 26 merge refused: required status check ci is expected
train-detail: 29 qa-report: proof line missing
EOF
echo 11 > "$F/train.rc"
run_q; rc=$?
[ "$rc" -eq 0 ] && ok "routing: exit 0 after a red train (routed)" || fail "routing: rc=$rc: $(tail -5 "$TMP/err")"
has_w "pr-unlabel 21 merge-queue" && has_w "issue-labels 31 loop:rebuild-1" && has_w "card move 31 Ready" && ok "red → unlabel, loop:rebuild-1, Ready" || fail "red #21: $(grep ' 2\?31\| 21 ' "$F/writes")"
has_w "pr-unlabel 22 merge-queue" && has_w "issue-labels 32 loop:rebase" && has_w "card move 32 Ready" && ok "conflict → unlabel, loop:rebase, Ready" || fail "conflict #22: $(cat "$F/writes")"
has_w "pr-unlabel 23" || has_w "card move 33" && fail "timeout touched #23/#33" || ok "timeout → label kept, card untouched"
has_w "pr-unlabel 28" || has_w "card move 38" && fail "deferred touched #28/#38" || ok "deferred → label kept, card untouched"
has_w "pr-unlabel 24 merge-queue" && ! has_w "card move 34" && ok "head-moved → unlabel, card stays in Review" || fail "head-moved #24: $(cat "$F/writes")"
has_w "pr-unlabel 25 merge-queue" && has_w "needs-you mark --repo o/r --issue 35" && has_w "card move 35 Blocked" && ok "gate-exit-7 → unlabel, needs-you mark, Blocked" || fail "exit 7 #25: $(cat "$F/writes")"
grep -q "^human-gate: money — label money$" "$F/issue-comment-35.txt" 2>/dev/null && grep -q "^approval-request: req-25$" "$F/issue-comment-35.txt" \
  && grep -q "^blocked-by: -$" "$F/issue-comment-35.txt" && ok "  … 🙋 issue comment copies the gate lines verbatim, ends with blocked-by" || fail "  … 🙋 comment: $(cat "$F/issue-comment-35.txt" 2>/dev/null)"
grep -q "train-detail" "$F/issue-comment-35.txt" 2>/dev/null && fail "  … the train-detail prefix leaked into the comment" || ok "  … no train-detail prefix in the comment"
has_w "pr-unlabel 26 merge-queue" && has_w "card move 36 Blocked" && ok "gate-exit-3 → unlabel, Blocked" || fail "exit 3 #26: $(cat "$F/writes")"
has_w "pr-unlabel 27 merge-queue" && has_w "card move 37 Blocked" && ! has_w "card move 37 Ready" && ok "gate-exit-5 at rebuild_cap → Blocked, not Ready" || fail "exit 5 cap #27: $(cat "$F/writes")"
has_w "pr-unlabel 29 merge-queue" && has_w "issue-labels 39 loop:rebuild-2" && has_w "card move 39 Ready" && ok "gate-exit-11 → loop:rebuild-1 becomes loop:rebuild-2, Ready" || fail "exit 11 #29: $(cat "$F/writes")"
[ "$(jq -r .last_red "$STATE" 2>/dev/null)" = true ] && ok "red batch recorded next to the lock" || fail "state after red: $(cat "$STATE" 2>/dev/null)"
# R1 mục 3: dòng train-detail của PR vào comment issue (red, exit 11, exit 3); exit 3 không còn câu cố định "branch protection".
grep -q "^ac-check: the sb:ac block lists 1 of 3$" "$F/issue-comment-31.txt" 2>/dev/null && grep -q "^FAILED tests/test_x.py::test_y$" "$F/issue-comment-31.txt" \
  && ok "red → the issue comment carries the train-detail lines (ac-check, verify tail)" || fail "red detail: $(cat "$F/issue-comment-31.txt" 2>/dev/null)"
grep -q "^qa-report: proof line missing$" "$F/issue-comment-39.txt" 2>/dev/null && ok "gate-exit-11 → the issue comment carries the qa-report detail" || fail "exit 11 detail: $(cat "$F/issue-comment-39.txt" 2>/dev/null)"
grep -q "merge refused: required status check ci is expected" "$F/issue-comment-36.txt" 2>/dev/null && grep -q "merge refused: required status check" "$F/pr-comment-26.txt" 2>/dev/null \
  && ok "gate-exit-3 → issue and PR comments carry the gate's own words" || fail "exit 3 detail: $(cat "$F/issue-comment-36.txt" "$F/pr-comment-26.txt" 2>/dev/null)"
grep -qi "branch protection" "$F/pr-comment-26.txt" "$F/issue-comment-36.txt" 2>/dev/null && fail "gate-exit-3 still guesses 'branch protection'" || ok "gate-exit-3: no fixed 'branch protection' guess"
# R1 mục 4: nhánh exit 7/8 gọi notify approve-button đúng một lần, cùng chữ ký merge gate dùng (--source = PR).
[ "$(grep -c '^notify approve-button' "$F/writes")" = 1 ] && has_w "notify approve-button --repo o/r --pr 25 --head $(sha 25) --source 25 --card PR #25 --title title of PR 25" \
  && ok "gate-exit-7 → one approve-button notify with the gate's arguments" || fail "notify: $(grep '^notify' "$F/writes")"

# ── 6. Đợt sau một đợt đỏ: gom tối đa batch_max/2; đợt xanh trả lại batch_max.
reset; cfg true 4
echo '{"last_red":true}' > "$STATE"
for n in 51 52 53 54; do pr "$n" "issue-$((n + 10))-x" $((60 - n)); approve "$n" OWNER "$(sha "$n")"; issue $((n + 10)); done
printf 'train-result: 51 deferred\ntrain-result: 52 deferred\ntrain-result: 53 deferred\ntrain-result: 54 deferred\n' > "$F/train.out"   # không đỏ, giữ nhãn
run_q
grep -q -- "--prs 51:$(sha 51),52:$(sha 52)\$" "$F/calls" && ok "after a red batch: at most batch_max/2 (the 2 oldest of 4)" || fail "halved batch: $(cat "$F/calls")"
[ "$(jq -r .last_red "$STATE" 2>/dev/null)" = false ] && ok "  … a green batch clears the red mark" || fail "  … state: $(cat "$STATE" 2>/dev/null)"
: > "$F/calls"; run_q
grep -q -- "--prs 51:$(sha 51),52:$(sha 52),53:$(sha 53),54:$(sha 54)\$" "$F/calls" && ok "  … and the next batch is full again" || fail "full batch: $(cat "$F/calls")"

# ── 7. Train exit 79: dừng, đi thẳng lên, không route. Exit 9: route các dòng đã in rồi thoát 9.
reset; cfg true 6
pr 1 issue-11-a 5; approve 1 OWNER "$(sha 1)"; issue 11
printf 'train-result: 1 merged\n' > "$F/train.out"; echo 79 > "$F/train.rc"; printf '%s\n' "$(sha 1 c)" > "$F/merged-1"
run_q; rc=$?
[ "$rc" -eq 79 ] && ! has_w "card move" && ok "train exit 79: queue exits 79, nothing routed" || fail "79: rc=$rc writes=$(cat "$F/writes")"
echo 9 > "$F/train.rc"; : > "$F/writes"
run_q; rc=$?
[ "$rc" -eq 9 ] && has_w "card move 11 Done" && ok "train exit 9: merged PRs routed, then exit 9" || fail "9: rc=$rc writes=$(cat "$F/writes")"
# Train hỏng mà không in kết quả nào (exit 1): không đụng trạng thái đỏ của đợt trước, nói rõ trong log.
echo '{"last_red":true}' > "$STATE"; : > "$F/train.out"; echo 1 > "$F/train.rc"; : > "$F/writes"; ago 5 > "$F/labeled/1"
run_q; rc=$?
[ "$(jq -r .last_red "$STATE" 2>/dev/null)" = true ] && ok "train exit 1 with no results: red mark kept" || fail "no results: state $(cat "$STATE")"
grep -q "no train-result" "$TMP/err" && ok "  … and the log says so" || fail "  … log: $(tail -3 "$TMP/err")"
[ ! -s "$F/writes" ] && ok "  … nothing routed" || fail "  … writes: $(cat "$F/writes")"

# ── 8. --dry-run. Ca này khẳng định: file ghi của gh giả rỗng và số lời gọi train là 0.
reset; cfg true 6
pr 1 issue-11-a 5; approve 1 OWNER "$(sha 1)"; pr 4 issue-14-d 5; approve 4 OWNER "$(sha 4 b)"; issue 11; issue 14
run_q --dry-run; rc=$?
[ "$rc" -eq 0 ] && [ "$(calls)" = 0 ] && [ ! -s "$F/writes" ] && ok "--dry-run: no train, no write" || fail "dry-run: rc=$rc calls=$(calls) writes=$(cat "$F/writes")"
grep -q -- "1:$(sha 1)" "$TMP/out" "$TMP/err" && ok "  … prints the batch it would send" || fail "  … no batch printed: $(cat "$TMP/out" "$TMP/err")"

# ── 9. R1 mục 1: số lần thử. Kết quả không kết thúc tăng n trong merge-queue.attempts (<PR> <head> <n> <epoch>); n ≥ 3 → gỡ nhãn,
#    comment, thẻ Blocked 🛡; kết quả kết thúc xoá dòng. Train không in train-result: mọi PR của đợt tăng n. gate-exit-64 = mã lạ (mục 7).
reset; cfg true 6
pr 1 issue-11-a 5; approve 1 OWNER "$(sha 1)"; issue 11
pr 2 issue-12-b 4; approve 2 OWNER "$(sha 2)"; issue 12
pr 3 feature-c 3; approve 3 OWNER "$(sha 3)"
printf 'train-result: 1 timeout\ntrain-result: 2 deferred\ntrain-result: 3 gate-exit-64\n' > "$F/train.out"; echo 12 > "$F/train.rc"
run_q
grep -q "^1 $(sha 1) 1 [0-9][0-9]*$" "$ATT" 2>/dev/null && grep -q "^2 $(sha 2) 1 " "$ATT" && grep -q "^3 $(sha 3) 1 " "$ATT" \
  && ok "attempts: timeout / deferred / gate-exit-64 each count 1 (<PR> <head> <n> <epoch>)" || fail "attempts after run 1: $(cat "$ATT" 2>/dev/null)"
has_w "pr-unlabel 3" && fail "gate-exit-64 dropped the label on the first try" || ok "gate-exit-64 (unknown exit): label kept, counted"
: > "$F/train.out"; echo 1 > "$F/train.rc"
run_q
grep -q "^1 $(sha 1) 2 " "$ATT" 2>/dev/null && grep -q "^3 $(sha 3) 2 " "$ATT" && ok "attempts: a train with no train-result counts for every PR of the batch" || fail "attempts after run 2: $(cat "$ATT" 2>/dev/null)"
# Train exit 4 không train-result = merge-train.lock bận (một train khác chạy): các PR chưa chạy, không tính lần thử.
cp "$ATT" "$TMP/att.before"; echo 4 > "$F/train.rc"
run_q
cmp -s "$ATT" "$TMP/att.before" && ok "attempts: train exit 4 with no result (train lock busy) counts nothing" || fail "attempts after busy train: $(cat "$ATT")"
# Antigravity audit (C): cả hai lần list (mở; merged còn nhãn) lọc theo base của board.
grep -q "^list .*--state open .*--base main" "$F/reads" && grep -q "^list .*--state merged .*--base main" "$F/reads" \
  && ok "pr list (open and merged) filters by --base main" || fail "pr list args: $(grep '^list' "$F/reads" | head -2)"
printf 'train-result: 1 timeout\ntrain-result: 2 merged\ntrain-result: 3 timeout\n' > "$F/train.out"; echo 12 > "$F/train.rc"; printf '%s\n' "$(sha 2 c)" > "$F/merged-2"
run_q
grep -q "^2 " "$ATT" 2>/dev/null && fail "attempts: a terminal result (merged) kept its row" || ok "attempts: a terminal result clears the row"
has_w "pr-unlabel 1 merge-queue" && has_w "card move 11 Blocked" && grep -q "🛡" "$F/issue-comment-11.txt" 2>/dev/null \
  && ok "attempts: 3rd non-final result → unlabel, 🛡 comment, card Blocked" || fail "attempts cap #1: $(cat "$F/writes")"
has_w "pr-unlabel 3 merge-queue" && has_w "pr-comment 3 " && ok "attempts: card-less PR at the cap → unlabel + PR comment" || fail "attempts cap #3: $(cat "$F/writes")"
grep -q "^1 \|^3 " "$ATT" 2>/dev/null && fail "attempts: rows of PRs taken off the queue are kept" || ok "attempts: rows of PRs taken off the queue are gone"
# Head mới = đếm lại từ đầu.
reset; cfg true 6; pr 1 issue-11-a 5; approve 1 OWNER "$(sha 1)"; issue 11
printf '1 %s 2 1\n' "$(sha 1 f)" > "$ATT"; printf 'train-result: 1 timeout\n' > "$F/train.out"; echo 12 > "$F/train.rc"
run_q
grep -q "^1 $(sha 1) 1 " "$ATT" && ! has_w "pr-unlabel 1" && ok "attempts: a new head starts a fresh count" || fail "attempts new head: $(cat "$ATT") $(cat "$F/writes")"

# ── 10. R1 mục 2: train đã merge rồi hàng chết trước khi route (PR không còn mở, nhãn còn): lượt sau list --state merged và route `merged`.
reset; cfg true 6
pr 5 issue-15-e 5 false MERGED; printf '%s\n' "$(sha 5 c)" > "$F/merged-5"; issue 15
run_q --dry-run
[ ! -s "$F/writes" ] && ok "merged recovery: --dry-run writes nothing" || fail "merged recovery dry-run wrote: $(cat "$F/writes")"
run_q --if-due; rc=$?
[ "$rc" -eq 0 ] && [ "$(calls)" = 0 ] && ok "merged recovery: exit 0, no train" || fail "merged recovery: rc=$rc calls=$(calls)"
has_w "issue-close 15" && has_w "card move 15 Done" && has_w "pr-unlabel 5 merge-queue" && ok "merged recovery: issue closed, card Done, label removed" || fail "merged recovery: $(cat "$F/writes")"
run_q
[ "$(grep -c '^issue-comment 15 .*merged' "$F/writes")" = 1 ] && ok "merged recovery: idempotent (one ✅ merged comment over two runs)" || fail "merged recovery not idempotent: $(cat "$F/writes")"
grep -q "state merged" "$QUEUE" && ok "header documents the merged recovery" || fail "header does not mention the merged recovery"

# ── 11. R1 mục 3: RED_NOW chỉ khi `red`; preflight gate-exit-11 (qa-report/AC) không thu nhỏ đợt sau.
reset; cfg true 6; pr 1 issue-11-a 5; approve 1 OWNER "$(sha 1)"; issue 11
printf 'train-result: 1 gate-exit-11\ntrain-detail: 1 ac-check: x\n' > "$F/train.out"; echo 11 > "$F/train.rc"
run_q
[ "$(jq -r .last_red "$STATE" 2>/dev/null)" = false ] && ok "gate-exit-11 alone: not a red batch (next batch not halved)" || fail "gate-exit-11 red mark: $(cat "$STATE" 2>/dev/null)"

# ── 12. R1 mục 5: queue bị giết giữa đợt (khoá đi theo nó), train mồ côi còn chạy: lượt sau KHÔNG dựng train thứ hai.
reset; cfg true 6; pr 1 issue-11-a 5; approve 1 OWNER "$(sha 1)"; issue 11
: > "$F/train.hold"; printf 'train-result: 1 merged\n' > "$F/train.out"
( cd "$R" && exec bash "$QUEUE" --config "$TMP/cfg.json" ) >"$TMP/out1" 2>"$TMP/err1" & QPID=$!; PIDS="$PIDS $QPID"
i=0; while [ ! -e "$F/train.started" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
grep -q "^train [0-9][0-9]*$" "$COMMON/super-board/merge-queue.lock.pid" 2>/dev/null && ok "lock.pid records the train pid" || fail "lock.pid: $(cat "$COMMON/super-board/merge-queue.lock.pid" 2>/dev/null)"
kill -9 "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
run_q; rc=$?
[ "$rc" -eq 0 ] && [ "$(calls)" = 1 ] && ok "orphan train alive: no second train" || fail "orphan train: rc=$rc calls=$(calls): $(cat "$TMP/err")"
grep -qi "train" "$TMP/err" && ok "  … and says a train is still running" || fail "  … log: $(cat "$TMP/err")"
grep -q "Train con kế thừa fd" "$QUEUE" && fail "the lock comment still says the train inherits fd 9" || ok "lock comment matches 9>&- (the train never holds the lock)"
rm -f "$F/train.hold"
i=0; while [ "$i" -lt 60 ]; do alive=0; for t in $(cat "$TMP/train.pids" 2>/dev/null); do kill -0 "$t" 2>/dev/null && alive=1; done; [ "$alive" = 0 ] && break; sleep 0.1; i=$((i + 1)); done

# ── 13. Antigravity audit (A): queue nhận TERM/INT/HUP giữa đợt → chuyển TERM xuống train con rồi thoát (không để train mồ côi).
reset; cfg true 6; pr 1 issue-11-a 5; approve 1 OWNER "$(sha 1)"; issue 11
: > "$TMP/train.pids"; : > "$F/train.hold"; printf 'train-result: 1 merged\n' > "$F/train.out"
( cd "$R" && exec bash "$QUEUE" --config "$TMP/cfg.json" ) >"$TMP/out1" 2>"$TMP/err1" & QPID=$!; PIDS="$PIDS $QPID"
i=0; while [ ! -e "$F/train.started" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
TP=$(head -1 "$TMP/train.pids")
kill -TERM "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
i=0; while kill -0 "$TP" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
kill -0 "$TP" 2>/dev/null && fail "TERM to the queue left its train running (pid $TP)" || ok "TERM to the queue is forwarded to the train"
rm -f "$F/train.hold"

# ── 14. Antigravity audit (C): nhãn chỉ gỡ khi các bước bắt buộc của route xong; card_move lỗi (khác 79) → nhãn giữ, lượt sau route lại.
reset; cfg true 6; pr 1 issue-11-a 5; approve 1 OWNER "$(sha 1)"; issue 11
printf '%s\n' "$(sha 1 c)" > "$F/merged-1"; printf 'train-result: 1 merged\n' > "$F/train.out"; echo 1 > "$F/card.rc"
run_q
has_w "pr-unlabel 1" && fail "card move failed but the label was removed" || ok "route step failed (card move exit 1): label kept"
rm -f "$F/card.rc"; run_q
has_w "pr-unlabel 1 merge-queue" && has_w "card move 11 Done" && ok "  … the next run routes it again and removes the label" || fail "  … rerun: $(cat "$F/writes")"
[ "$(grep -c '^issue-comment 11 .*merged' "$F/writes")" = 1 ] && ok "  … with one ✅ merged comment (the issue was already closed)" || fail "  … comments: $(grep '^issue-comment 11' "$F/writes")"
reset; cfg true 6; pr 2 issue-12-b 5; approve 2 OWNER "$(sha 2)"; issue 12
printf 'train-result: 2 gate-exit-7\n' > "$F/train.out"; echo 7 > "$F/train.rc"; echo 1 > "$F/card.rc"
run_q
has_w "pr-unlabel 2" && fail "exit 7 route: card move failed but the label was removed" || ok "exit 7 route with a failed card move: label kept"
# Lỗi kéo dài: lượt sau route lại từ merge-queue.pending (không train / verify lại, không notify / comment lại); lần thử thứ 3 → PR rời hàng.
run_q
has_w "pr-unlabel 2" && fail "exit 7 route: label removed after only 2 failed routes" || ok "  … 2nd failed route: label still kept"
run_q
[ "$(calls)" = 1 ] && ok "  … failed routes are retried from merge-queue.pending, no second train" || fail "  … trains: $(calls)"
[ "$(grep -c '^notify approve-button' "$F/writes")" = 1 ] && ok "  … approve-button sent once over 3 routes" || fail "  … notifies: $(grep -c '^notify approve-button' "$F/writes")"
[ "$(grep -c '^issue-comment 12 .*🙋' "$F/writes")" = 1 ] && ok "  … the 🙋 issue comment posted once" || fail "  … 🙋 comments: $(grep '^issue-comment 12' "$F/writes")"
has_w "pr-unlabel 2 merge-queue" && ok "  … 3rd failed route: the PR leaves the queue (no endless retry)" || fail "  … label kept forever: $(cat "$F/writes")"
rm -f "$F/card.rc"
# merged + card move lỗi rồi hết lỗi: route lại từ pending, không train lần hai.
reset; cfg true 6; pr 3 issue-13-c 5; approve 3 OWNER "$(sha 3)"; issue 13
printf '%s\n' "$(sha 3 c)" > "$F/merged-3"; printf 'train-result: 3 merged\n' > "$F/train.out"; echo 1 > "$F/card.rc"
run_q; rm -f "$F/card.rc"; run_q
[ "$(calls)" = 1 ] && has_w "card move 13 Done" && has_w "pr-unlabel 3 merge-queue" && ok "merged + failed card move: retried from pending without a second train" || fail "merged retry: calls=$(calls) $(cat "$F/writes")"
[ "$(grep -c '^issue-comment 13 .*merged' "$F/writes")" = 1 ] && ok "  … one ✅ merged comment" || fail "  … comments: $(grep '^issue-comment 13' "$F/writes")"
# Closes #K đã đóng issue lúc merge: comment ✅ merged vẫn có (lượt route đầu).
reset; cfg true 6; pr 4 issue-14-d 5; approve 4 OWNER "$(sha 4)"; issue 14
python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["state"]="CLOSED";json.dump(d,open(p,"w"))' "$F/issue-14.json"
printf '%s\n' "$(sha 4 c)" > "$F/merged-4"; printf 'train-result: 4 merged\n' > "$F/train.out"
run_q
has_w "issue-comment 14 [merge-queue] [report] ✅ merged" && ! has_w "issue-close 14" && ok "issue already closed by Closes #K: ✅ comment still posted, no second close" || fail "closed issue: $(cat "$F/writes")"

# #470: train-detail dài (>70000 ký tự) làm body comment vượt 65536 nên `gh pr comment` bị từ chối. Body bị chặn trần, vẫn giữ dòng kết luận + dòng suite đỏ.
reset; cfg true 6; pr 5 issue-15-e 5; approve 5 OWNER "$(sha 5)"; issue 15
{
  echo "train-result: 5 red"
  echo "train-detail: 5 FAILED tests/test_first.py::test_red"
  i=0; while [ "$i" -lt 12 ]; do printf 'train-detail: 5 %s\n' "$(head -c 6000 /dev/zero | tr '\0' x)"; i=$((i + 1)); done
} > "$F/train.out"; echo 11 > "$F/train.rc"
run_q
PC="$F/pr-comment-5.txt"; IC="$F/issue-comment-15.txt"
[ -s "$PC" ] && [ "$(wc -c < "$PC")" -lt 65536 ] && [ "$(wc -c < "$IC")" -lt 65536 ] && ok "#470 oversized train-detail: PR and issue comment bodies stay under 65536 chars" || fail "#470 sizes: pr=$(wc -c < "$PC" 2>/dev/null) issue=$(wc -c < "$IC" 2>/dev/null)"
grep -q "^\[merge-queue\] \[report\] ❌ red · red" "$PC" && grep -q "^FAILED tests/test_first.py::test_red$" "$PC" && ok "  … the verdict line and the red suite line survive" || fail "  … lost lines: $(head -c 400 "$PC")"
grep -q "^Next: back to Build" "$PC" && ok "  … the trailing Next line survives" || fail "  … no Next line"

# #605 Lane F: approved-head kèm nguồn duyệt chéo `approved-by: {json}` (reviewer khác builder, 4 trường không rỗng).
# Body có ngoặc kép nên dựng bằng jq (approve() dùng printf thô).
approve_body() {   # approve_body <N> <assoc> <body>
  jq -n --arg a "$2" --arg b "$3" '{comments:[{authorAssociation:$a,body:"[reviewer] [report] ✅ pass"},{authorAssociation:$a,body:$b}]}' > "$F/comments-$1.json"
}
by() {   # by <reviewer> <builder> [task_id] [gate_receipt]
  jq -cn --arg r "$1" --arg b "$2" --arg t "${3-task-605}" --arg g "${4-receipt-1}" '{reviewer:$r,builder:$b,task_id:$t,gate_receipt:$g}'
}
reset; cfg true 6
pr 1 issue-11-a 10; pr 2 issue-12-b 20; pr 3 issue-13-c 30; pr 4 issue-14-d 40; pr 5 issue-15-e 50; pr 6 issue-16-f 60; pr 7 issue-17-g 70; pr 8 issue-18-h 80; pr 9 issue-19-i 90; pr 10 issue-20-j 100
approve_body 1 COLLABORATOR "approved-head:$(sha 1)
approved-by: $(by antigravity claude-builder)
note: } trailing line"
approve_body 2 MEMBER "approved-head:$(sha 2)
approved-by: $(by Claude-Builder claude-builder)"
approve_body 3 MEMBER "approved-head:$(sha 3 b)
approved-by: $(by antigravity claude-builder)"
approve 4 OWNER "$(sha 4)"
approve_body 5 MEMBER "approved-head:$(sha 5)
approved-by: {not json"
approve_body 6 MEMBER "approved-head:$(sha 6)
approved-by: $(by antigravity claude-builder '' receipt-1)"
jq -n --arg h "$(sha 7)" --arg ok "$(by antigravity claude-builder)" --arg self "$(by claude claude)" \
  '{comments:[{authorAssociation:"MEMBER",body:("approved-head:"+$h+"\napproved-by: "+$ok)},{authorAssociation:"MEMBER",body:("approved-head:"+$h+"\napproved-by: "+$self)}]}' > "$F/comments-7.json"
# #605 Lane H: approved-head trơn của MEMBER / COLLABORATOR → loại, đòi approved-by; trường số (không phải chuỗi) → loại.
approve 8 MEMBER "$(sha 8)"; approve 9 COLLABORATOR "$(sha 9)"
approve_body 10 MEMBER "approved-head:$(sha 10)
approved-by: {\"reviewer\":1,\"builder\":2,\"task_id\":3,\"gate_receipt\":4}"
for k in 11 12 13 14 15 16 17 18 19 20; do issue "$k"; done
: > "$F/train.out"
( export SB_MERGE_QUEUE=1; run_q --dry-run ); rc=$?
OUT="$(cat "$TMP/out" "$TMP/err")"
printf '%s' "$OUT" | grep -q -- "--prs 4:$(sha 4),1:$(sha 1) " && ok "#605 cross-review marker (reviewer≠builder) and bare OWNER approved-head: both batched" || fail "#605 batch: rc=$rc $OUT"
printf '%s' "$OUT" | grep -q "drop PR #2 .*self-review" && ok "#605 reviewer == builder (case-insensitive): rejected as self-review" || fail "#605 self-review not rejected: $OUT"
printf '%s' "$OUT" | grep -q "drop PR #3 .*not the PR head" && ok "#605 marker on another head: rejected" || fail "#605 head mismatch: $OUT"
printf '%s' "$OUT" | grep -q "drop PR #5 .*approved-by" && ok "#605 malformed approved-by: rejected (no fallback to bare)" || fail "#605 malformed: $OUT"
printf '%s' "$OUT" | grep -q "drop PR #6 .*approved-by" && ok "#605 empty task_id: rejected" || fail "#605 empty field: $OUT"
printf '%s' "$OUT" | grep -q "drop PR #7 .*self-review" && ok "#605 newer self-review marker voids an older valid one" || fail "#605 newest wins: $OUT"
printf '%s' "$OUT" | grep -q "drop PR #8 .*approved-by required" && ok "#605 bare approved-head from a MEMBER: rejected (approved-by required)" || fail "#605 bare MEMBER honoured: $OUT"
printf '%s' "$OUT" | grep -q "drop PR #9 .*approved-by required" && ok "#605 bare approved-head from a COLLABORATOR: rejected (approved-by required)" || fail "#605 bare COLLABORATOR honoured: $OUT"
printf '%s' "$OUT" | grep -q "drop PR #10 .*approved-by needs non-empty" && ok "#605 numeric approved-by fields: rejected (strings only)" || fail "#605 numeric fields honoured: $OUT"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_queue: all passed" || { echo "❌ test_merge_queue: $FAILS failed"; exit 1; }
