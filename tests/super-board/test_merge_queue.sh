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
cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
F="$TMP/fake"; R="$TMP/repo"; Q="$TMP/qbin"
mkdir -p "$F/labeled" "$Q" "$TMP/path"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"; git -C "$R" add .gitignore; git -C "$R" commit -qm init
INF="$R/.claude/super-board/inflight"; mkdir -p "$INF"
COMMON="$(cd "$R" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
STATE="$COMMON/super-board/merge-queue.state"

# Bộ gom thật + github-read thật (symlink: HERE của script là $Q), các helper khác là stub.
ln -s "$ROOT/.claude/bin/super-board-merge-queue.sh" "$Q/super-board-merge-queue.sh"
ln -s "$ROOT/.claude/bin/super-board-github-read.py" "$Q/super-board-github-read.py"
QUEUE="$Q/super-board-merge-queue.sh"
cat > "$Q/super-board-merge-train.sh" <<'SH'
#!/usr/bin/env bash
echo "train caller=${SB_MERGE_CALLER:-<unset>} $*" >> "$FAKE/calls"
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
    prs = json.load(open(F + '/prs.json'))
    if opt('--label') == 'merge-queue':
        prs = [p for p in prs if os.path.exists(f"{F}/labeled/{p['number']}")]
    print(json.dumps(prs))
elif a[:2] == ['pr', 'view'] and opt('--json') == 'comments':
    p = f'{F}/comments-{num()}.json'
    print(open(p).read() if os.path.exists(p) else '{"comments":[]}')
elif a[:2] == ['pr', 'view'] and 'state' in (opt('--json') or ''):
    n = num(); m = f'{F}/merged-{n}'
    if os.path.exists(m):
        print(json.dumps({'state': 'MERGED', 'mergeCommit': {'oid': open(m).read().strip()}, 'headRefOid': 'a' * 40}))
    else:
        print(json.dumps({'state': 'OPEN', 'mergeCommit': None, 'headRefOid': 'a' * 40}))
elif a[0] == 'api' and '/timeline' in a[1]:
    n = a[1].split('/issues/')[1].split('/')[0]; p = f'{F}/labeled/{n}'
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
export PATH="$TMP/path:$PATH" FAKE="$F" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_QUEUE SB_MERGE_CALLER SB_GITHUB_READ_STRICT

cfg() {   # cfg <enabled> <batch_max> [max_wait_min]
  printf '{"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"rebuild_cap":2,"verify_commands":["true"],"merge_queue":{"enabled":%s,"enabled_at":null,"batch_max":%s,"max_wait_min":%s}}\n' "$1" "$2" "${3:-60}" > "$TMP/cfg.json"
}
ago() { python3 -c 'import datetime,sys;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
sha() { printf '%040d' "$1" | tr 0 "${2:-a}"; }
# pr <N> <branch> <minutes since labeled> [draft]: PR mở có nhãn, head = sha(N).
PRS_ROWS=""
pr() {
  PRS_ROWS="${PRS_ROWS}${PRS_ROWS:+,}{\"number\":$1,\"headRefName\":\"$2\",\"headRefOid\":\"$(sha "$1")\",\"isDraft\":${4:-false}}"
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
  rm -f "$INF"/[0-9]* "$STATE"; rm -rf "$INF/merge.lock"
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

# ── 2. Chọn PR: 3 hợp lệ → MỘT train, cũ nhất trước; approved-head lệch / người ngoài → gỡ nhãn + comment; draft → bỏ qua, giữ nhãn.
reset; cfg true 6
pr 1 issue-11-a 10; pr 2 issue-12-b 30; pr 3 feature-x 20; pr 4 issue-14-d 40; pr 5 issue-15-e 50; pr 6 issue-16-f 60 true
approve 1 OWNER "$(sha 1)"; approve 2 MEMBER "$(sha 2)"; approve 3 COLLABORATOR "$(sha 3)"
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
sleep 60 & LIVE=$!; PIDS="$PIDS $LIVE"
printf 'PID=%s\nLANE=build\n' "$LIVE" > "$INF/77"
run_q --if-due; rc=$?
[ "$rc" -eq 0 ] && [ "$(calls)" = 0 ] && ok "--if-due: 2 PRs, 5 min old, a worker alive → not due" || fail "--if-due busy: rc=$rc calls=$(calls): $(cat "$TMP/err")"
ago 61 > "$F/labeled/2"
run_q --if-due
[ "$(calls)" = 1 ] && ok "--if-due: oldest waited 61 min ≥ max_wait_min → due" || fail "--if-due age: calls=$(calls): $(cat "$TMP/err")"
: > "$F/calls"; ago 5 > "$F/labeled/2"; cfg true 2 60
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

# ── 6. Đợt sau một đợt đỏ: gom tối đa batch_max/2; đợt xanh trả lại batch_max.
reset; cfg true 4
echo '{"last_red":true}' > "$STATE"
for n in 51 52 53 54; do pr "$n" "issue-$((n + 10))-x" $((60 - n)); approve "$n" OWNER "$(sha "$n")"; issue $((n + 10)); done
: > "$F/train.out"
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

# ── 8. --dry-run. Ca này khẳng định: file ghi của gh giả rỗng và số lời gọi train là 0.
reset; cfg true 6
pr 1 issue-11-a 5; approve 1 OWNER "$(sha 1)"; pr 4 issue-14-d 5; approve 4 OWNER "$(sha 4 b)"; issue 11; issue 14
run_q --dry-run; rc=$?
[ "$rc" -eq 0 ] && [ "$(calls)" = 0 ] && [ ! -s "$F/writes" ] && ok "--dry-run: no train, no write" || fail "dry-run: rc=$rc calls=$(calls) writes=$(cat "$F/writes")"
grep -q -- "1:$(sha 1)" "$TMP/out" "$TMP/err" && ok "  … prints the batch it would send" || fail "  … no batch printed: $(cat "$TMP/out" "$TMP/err")"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_queue: all passed" || { echo "❌ test_merge_queue: $FAILS failed"; exit 1; }
