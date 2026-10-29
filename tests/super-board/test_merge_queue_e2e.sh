#!/usr/bin/env bash
# Test đầu-cuối (Pha 2, lớp bảo đảm 2, lane I) cho hàng đợi merge: đi qua luồng THẬT, không dựng sẵn trạng thái "đã duyệt".
#
# VÌ SAO: merge train (#110/#228) chạy 0 lần trên 73 PR từ 23/10 trong khi test đơn vị của nó vẫn xanh, vì test tự dựng "≥2 thẻ Review
# có approved-head" rồi chỉ kiểm hàm runner. Ở đây trạng thái đó chỉ sinh ra từ các bước thật: runner phóng reviewer → reviewer (stub
# claude, làm đúng bước mới của skill) ghi approved-head + gh pr ready + nhãn merge-queue + comment Issue rồi thoát → tick sau runner
# gọi super-board-merge-queue.sh (không gom đợt, không --if-due) → train → merge gate → gh pr merge.
#
# Script thật: super-board-run.sh (SB_LIB_ONLY=1, các hàm tick theo đúng thứ tự vòng lặp chính), super-board-merge-queue.sh,
# super-board-merge-train.sh, super-board-merge-gate.sh, super-board-card.sh, super-board-github-read.py, super-board-worker-wrap.sh.
# Stub: `gh` (python, trạng thái trong file; `pr merge` squash thật lên origin bare như test_merge_train.sh), `claude` (reviewer làm
# theo prompt: prompt "vào hàng" → bước mới; prompt còn câu merge gate → gọi gate như skill cũ), post-fix-gate.py (đếm lượt verify theo
# thư mục chạy: .train-scratch-* = verify của train, .merge-scratch-* = verify lẻ của gate). Ngoài luồng merge: super-board-skills-ready.py
# (kiểm skill của host claude) là stub `ok` như mọi test runner khác.
#
# Kịch bản: config merge_queue.enabled=true; 3 PR vào hàng LỆCH NHỊP: thẻ #7 (PR 70) vào Review trước trong khi thẻ #8 (PR 71) còn đang
# build; PR tương tác 72 (nhánh feature-z, không thẻ) do người duyệt tay; thẻ #8 vào Review sau cùng. Khẳng định:
#  (a) runner không phóng lại reviewer cho thẻ đã vào hàng; không phóng merge-only / merge-train;
#  (b) không gom đợt: mỗi PR đã duyệt vào train ở tick kế tiếp dù worker khác còn sống (PR 70 → 1 train, PR 72 → 1 train, PR 71 → 1 train);
#      mỗi train verify (post-fix-gate giả) ĐÚNG 1 lần (trong .train-scratch-*), 0 lần verify lẻ của gate; cả 3 PR merged; thẻ board
#      sang Done, issue đóng;
#  (c) một lane worker (do runner phóng) gọi thẳng super-board-merge-gate.sh khi queue bật → exit 13, không verify, không merge;
#  (d) đường lùi SB_MERGE_QUEUE=0 (config bật): ca cuối file khẳng định manifest không có dòng [merge-queue], không có merge-queue.lock,
#      và reviewer tự merge qua gate với một verify lẻ trong .merge-scratch-*.
#
# Chạy với bin khác (vd. bản origin/main để chứng minh test ĐỎ trên code cũ): SB_TEST_BIN=<thư mục .claude/bin>. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
BIN_SRC="${SB_TEST_BIN:-$ROOT/.claude/bin}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mq-e2e.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
OWN_PIDS=""
# Chỉ giết PID test này tự chạy (builder giả, stub claude ghi PID của nó vào stub-pids); không bao giờ pkill theo tên.
cleanup() {
  for p in $OWN_PIDS $(cat "$TMP"/*/fake/stub-pids 2>/dev/null); do kill "$p" 2>/dev/null; done
  cd / && if [ -n "${SB_E2E_KEEP:-}" ]; then echo "kept: $TMP"; else rm -rf "$TMP"; fi
}
trap cleanup EXIT
mkdir -p "$TMP/home" "$TMP/path" "$TMP/slots"
# Môi trường riêng: không đọc account pool / Agent Office / slot của máy thật; không tải máy chặn verify.
export HOME="$TMP/home" SB_HEAVY_SLOT_DIR="$TMP/slots" DEVKIT_SLOT_LOAD_MAX=100000 SB_ACCOUNT_POOL="$TMP/no-pool"
export SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1 SB_FETCH_RETRY_DELAYS="" SB_CARD_RETRY_SLEEP=0
unset SB_MERGE_CALLER SB_MERGE_QUEUE SB_GITHUB_READ_STRICT SB_REVIEW_TRAIN SB_BUILD_LOAD_MAX SB_GLOBAL_SLOT_DIR

# ── gh giả: một file trạng thái $FAKE/state.json (PR, issue, cột board), khoá fcntl; lệnh lạ → $FAKE/gh.unexpected + exit 1.
cat > "$TMP/path/gh" <<'PY'
#!/usr/bin/env python3
import fcntl, json, os, subprocess, sys, time
F = os.environ['FAKE']; a = sys.argv[1:]
open(F + '/gh.calls', 'a').write(' '.join(a)[:300] + '\n')
lk = open(F + '/state.lock', 'a'); fcntl.flock(lk, fcntl.LOCK_EX)
S = json.load(open(F + '/state.json'))
def save():
    json.dump(S, open(F + '/state.tmp', 'w')); os.replace(F + '/state.tmp', F + '/state.json')
# Như GitHub: head của PR mở là đầu nhánh trên origin lúc đọc (merge gate tự đẩy merge commit của main lên nhánh PR khi nhánh chậm hơn base).
for _p in S['prs'].values():
    if _p['state'] == 'OPEN':
        _h = subprocess.run(['git', '--git-dir', os.environ['FAKE_ORIGIN'], 'rev-parse', '--verify', '-q', 'refs/heads/' + _p['headRefName']],
                            capture_output=True, text=True).stdout.strip()
        if _h: _p['headRefOid'] = _h
def opt(*names):
    for n in names:
        if n in a and a.index(n) + 1 < len(a): return a[a.index(n) + 1]
        for x in a:
            if x.startswith(n + '='): return x.split('=', 1)[1]
    return None
def opts(name):
    return [a[i + 1] for i, x in enumerate(a) if x == name and i + 1 < len(a)]
def fval(name):   # -f/-F name=value of gh api
    for i, x in enumerate(a):
        if x in ('-f', '-F', '--raw-field', '--field') and i + 1 < len(a) and a[i + 1].startswith(name + '='):
            return a[i + 1].split('=', 1)[1]
    return None
def num():
    return next(x for x in a[2:] if x.isdigit())
def emit(obj):
    q = opt('-q', '--jq')
    text = json.dumps(obj)
    if q is not None:
        r = subprocess.run(['jq', '-r', q], input=text, capture_output=True, text=True)
        sys.stdout.write(r.stdout); sys.exit(r.returncode)
    print(text)
def body():
    b = opt('--body', '-b')
    if b is None and opt('--body-file', '-F'):
        b = open(opt('--body-file', '-F')).read()
    return b or ''
def unexpected():
    open(F + '/gh.unexpected', 'a').write(' '.join(a)[:400] + '\n')
    sys.stderr.write('fake gh: unexpected ' + ' '.join(a)[:200] + '\n'); sys.exit(1)
def now():
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
def card_status(k):
    return S['board'].get(str(k))
OPTS = ['Backlog', 'Ready', 'Building', 'QA', 'Review', 'Blocked', 'Done']
if a[:2] == ['pr', 'list']:
    lab = opt('--label')
    prs = [p for p in S['prs'].values() if p['state'] == 'OPEN' and (lab is None or any(l['name'] == lab for l in p['labels']))]
    emit(prs)
elif a[:2] == ['pr', 'view']:
    emit(S['prs'][num()])
elif a[:2] == ['pr', 'diff']:
    sys.stdout.write(S['prs'][num()]['diff'])
elif a[:2] == ['pr', 'ready']:
    S['prs'][num()]['isDraft'] = False; save()
elif a[:2] == ['pr', 'edit']:
    p = S['prs'][num()]
    for l in opts('--add-label'):
        if not any(x['name'] == l for x in p['labels']):
            p['labels'].append({'name': l}); p.setdefault('labeled', {})[l] = now()
    for l in opts('--remove-label'):
        p['labels'] = [x for x in p['labels'] if x['name'] != l]
    if opt('--body-file'):
        p['body'] = open(opt('--body-file')).read()
    save()
elif a[:2] == ['pr', 'comment']:
    S['prs'][num()]['comments'].append({'authorAssociation': 'OWNER', 'author': {'login': 'bot'}, 'body': body(), 'createdAt': now()}); save()
elif a[:2] == ['pr', 'merge']:
    n = num(); p = S['prs'][n]; R = os.environ['FAKE_REPO']
    want = opt('--match-head-commit')
    if p['state'] != 'OPEN' or (want and want != p['headRefOid']):
        sys.stderr.write('fake gh: merge refused\n'); sys.exit(1)
    g = lambda *c: subprocess.run(['git', '-C', R, *c], capture_output=True, text=True)
    g('fetch', '-q', 'origin', 'main', p['headRefName'])
    tree = g('merge-tree', '--write-tree', 'origin/main', p['headRefOid'])
    if tree.returncode: sys.stderr.write('fake gh: merge conflict\n'); sys.exit(1)
    c = g('commit-tree', tree.stdout.split()[0], '-p', 'origin/main', '-m', 'squash #' + n).stdout.strip()
    if g('push', '-q', 'origin', c + ':refs/heads/main').returncode: sys.stderr.write('fake gh: push failed\n'); sys.exit(1)
    p['state'] = 'MERGED'; p['mergeCommit'] = {'oid': c}; S['merged'].append(int(n)); save()
    print('merged #' + n)
elif a[:2] == ['issue', 'view']:
    emit(S['issues'][num()])
elif a[:2] == ['issue', 'edit']:
    i = S['issues'][num()]
    for x in opts('--add-assignee'):
        if x not in [y['login'] for y in i['assignees']]: i['assignees'].append({'login': x})
    for x in opts('--remove-assignee'):
        i['assignees'] = [y for y in i['assignees'] if y['login'] != x]
    for l in opts('--add-label'):
        if not any(x['name'] == l for x in i['labels']): i['labels'].append({'name': l})
    for l in opts('--remove-label'):
        i['labels'] = [x for x in i['labels'] if x['name'] != l]
    save()
elif a[:2] == ['issue', 'comment']:
    S['issues'][num()]['comments'].append({'authorAssociation': 'OWNER', 'author': {'login': 'bot'}, 'body': body()}); save()
elif a[:2] in (['issue', 'close'], ['issue', 'reopen']):
    i = S['issues'][num()]; i['state'] = 'CLOSED' if a[1] == 'close' else 'OPEN'
    i['stateReason'] = 'COMPLETED' if a[1] == 'close' else 'REOPENED'; save()
elif a[:2] == ['label', 'create']:
    pass
elif a[:1] == ['api'] and a[1] == 'graphql':
    q = fval('query') or ''
    if 'updateProjectV2ItemFieldValue' in q:
        k = fval('i').split('_', 1)[1]; name = fval('o').split('_', 1)[1]
        S['board'][k] = name; S['moves'].append(k + ' ' + name); save()
        emit({'data': {'updateProjectV2ItemFieldValue': {'projectV2Item': {'id': fval('i')}}}})
    elif 'issueOrPullRequest' in q:
        k = fval('issue'); st = card_status(k)
        nodes = [] if st is None else [{'id': 'PVTI_' + k, 'project': {'number': 1, 'owner': {'login': 'o'}},
                                        'fieldValueByName': {'name': st}}]
        emit({'data': {'repository': {'issueOrPullRequest': {'projectItems': {'nodes': nodes}}}}})
    elif 'items(first:100' in q:
        nodes = []
        for k, st in sorted(S['board'].items(), key=lambda kv: int(kv[0])):
            i = S['issues'][k]
            nodes.append({'id': 'PVTI_' + k, 'fieldValueByName': {'name': st},
                          'content': {'__typename': 'Issue', 'number': int(k), 'title': i['title'], 'url': 'https://github.com/o/r/issues/' + k,
                                      'repository': {'nameWithOwner': 'o/r'}, 'labels': {'nodes': i['labels']}}})
        page = {'data': {'repositoryOwner': {'projectV2': {'items': {'totalCount': len(nodes),
                'pageInfo': {'hasNextPage': False, 'endCursor': None}, 'nodes': nodes}}}}}
        emit([page] if '--slurp' in a else page)
    elif 'field(name:"Status")' in q:
        emit({'data': {'repositoryOwner': {'projectV2': {'id': 'PVT_1', 'field': {'id': 'PVTSSF_1',
              'options': [{'id': 'OPT_' + o, 'name': o} for o in OPTS]}}}}})
    else:
        unexpected()
elif a[:1] == ['api'] and '/timeline' in a[1]:
    n = a[1].split('/issues/')[1].split('/')[0]
    ev = [{'event': 'labeled', 'label': {'name': l}, 'created_at': t} for l, t in S['prs'][n].get('labeled', {}).items()]
    emit([ev] if '--slurp' in a else ev)
elif a[:1] == ['api'] and '/issues/' in a[1] and a[1].rstrip('/').split('/')[-1].isdigit():
    k = a[1].rstrip('/').split('/')[-1]
    emit({'number': int(k), 'comments': len(S['issues'][k]['comments'])})
else:
    unexpected()
PY
# claude giả: reviewer làm theo prompt. "add-label merge-queue" → bước mới của skill; còn câu merge gate → gọi gate như skill cũ.
# Ghi PID của chính nó (exec giữ PID) để cleanup; giữ tiến trình sống tới khi test thả ($FAKE/release-<issue>) để tick biết chắc còn worker.
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
F="$FAKE"; echo $$ >> "$F/stub-pids"
p=""; while [ $# -gt 0 ]; do [ "$1" = -p ] && { p="${2:-}"; break; }; shift; done
cfg=$(printf '%s' "$p" | sed -n 's/.*Config: \([^ ]*\)\. .*/\1/p' | head -1); cfg=${cfg:-$STUB_CFG}
issue=$(printf '%s' "$p" | grep -o 'super-review on issue #[0-9]*' | head -1 | tr -dc 0-9)
kind=review
case "$p" in *"merge-train worker"*) kind=merge-train ;; *"Run merge-only"*) kind=merge-only ;; esac
[ -n "$issue" ] || issue=$(printf '%s' "$p" | grep -o 'issues\{0,1\} #[0-9]*' | head -1 | tr -dc 0-9)
echo "$kind ${issue:-?}" >> "$F/claude.calls"
hold() { : > "$F/held-$issue"; i=0; while [ ! -e "$F/release-$issue" ] && [ "$i" -lt 900 ]; do sleep 0.1; i=$((i + 1)); done; exit 0; }
[ "$kind" = review ] && [ -n "$issue" ] || hold
row=$(gh pr list --state open --json number,headRefName,headRefOid -q ".[] | select(.headRefName | startswith(\"issue-$issue-\")) | \"\(.number) \(.headRefOid)\"" | head -1)
read -r pr sha <<EOF
$row
EOF
[ -n "${pr:-}" ] || hold
if [ -e "$F/direct-gate-$issue" ]; then   # (c): một lane worker còn giữ câu cũ "gọi merge gate" (Fast-Track / skill sót chữ)
  rc=0; bash .claude/bin/super-board-merge-gate.sh --config "$cfg" --pr "$pr" --expect-head "$sha" >"$F/direct-gate-$issue.out" 2>&1 || rc=$?
  echo "$rc" > "$F/direct-gate-$issue.rc"
fi
case "$p" in
  *"add-label merge-queue"*)
    gh pr comment "$pr" --body "[reviewer] [report] ✅ pass
approved-head:$sha"
    gh pr ready "$pr"
    gh pr edit "$pr" --add-label merge-queue
    gh issue comment "$issue" --body "[reviewer] [report] ✅ merge-ready · queued PR #$pr @ $(printf '%s' "$sha" | cut -c1-7)"
    echo "queued $issue $pr" >> "$F/claude.calls" ;;
  *super-board-merge-gate.sh*)
    gh pr comment "$pr" --body "approved-head:$sha"
    gh pr ready "$pr"
    rc=0; bash .claude/bin/super-board-merge-gate.sh --expect-head "$sha" --config "$cfg" --pr "$pr" >>"$F/reviewer-gate-$issue.out" 2>&1 || rc=$?
    echo "gate $issue $pr rc=$rc" >> "$F/claude.calls"
    if [ "$rc" = 0 ]; then gh issue close "$issue"; bash .claude/bin/super-board-card.sh --config "$cfg" move "$issue" Done >/dev/null; fi ;;
esac
hold
SH
chmod +x "$TMP/path/gh" "$TMP/path/claude"
# post-fix-gate giả: ghi thư mục chạy (scratch của train hay của gate) + đối số, xanh.
mkdir -p "$TMP/pfg"
printf 'import os, sys\nopen(os.environ["FAKE"] + "/pfg.log", "a").write(os.getcwd() + " " + " ".join(sys.argv[1:]) + "\\n")\n' > "$TMP/pfg/post-fix-gate.py"
export PATH="$TMP/path:$PATH"

# ── thế giới: origin bare + checkout chính + bin thật (symlink) + config + trạng thái gh. new_world <tên> <merge_queue.enabled>
# Vòng sửa 1 (R3): hàng đợi chỉ bật với worker_backend "claude-p", nên config của thế giới ghim backend đó.
new_world() {
  W="$TMP/$1"; O="$W/origin.git"; R="$W/repo"; F="$W/fake"
  mkdir -p "$F"; : > "$F/stub-pids"; : > "$F/claude.calls"; : > "$F/gh.calls"
  git init -q --bare -b main "$O"; git init -q -b main "$R"
  git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
  printf '.claude/\ndocs/\n' > "$R/.gitignore"; echo a > "$R/a"
  git -C "$R" add .gitignore a; git -C "$R" commit -qm init
  git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
  mkdir -p "$R/.claude/bin" "$R/.claude/super-board/configs" "$R/.claude/worktrees"
  for f in "$BIN_SRC"/*; do ln -s "$f" "$R/.claude/bin/$(basename "$f")"; done
  rm -f "$R/.claude/bin/super-board-skills-ready.py"; printf 'print("ok")\n' > "$R/.claude/bin/super-board-skills-ready.py"
  CFG="$R/.claude/super-board/configs/e2e.json"
  printf '{"worker_backend":"claude-p","base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"project":{"owner":"o","number":1},"rebuild_cap":2,"verify_commands":["python3 %s/pfg/post-fix-gate.py --run-tests"],"merge_queue":{"enabled":%s,"enabled_at":null}}\n' "$TMP" "$2" > "$CFG"
  echo '{"prs":{},"issues":{},"board":{},"merged":[],"moves":[]}' > "$F/state.json"
  export FAKE="$F" FAKE_REPO="$R" FAKE_ORIGIN="$O" STUB_CFG="$CFG" SB_GITHUB_HALT_FILE="$W/halt.json" SB_CARD_CACHE_DIR="$W/card-cache"
  COMMON="$(cd "$R" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
  # Runner (đã source một lần) trỏ vào thế giới này: cwd = checkout chính, các script cạnh github-read là bin thật của thế giới.
  cd "$R" || exit 1
  SB_GITHUB_READ="$R/.claude/bin/super-board-github-read.py"; CONFIG_PATH="$CFG"; REPO_ROOT="$R"
  INFLIGHT_DIR=".claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
  WORKER_LOG_DIR="docs/super-board/runs/e2e-workers"; mkdir -p "$WORKER_LOG_DIR"; RUN_MANIFEST="$W/manifest.md"; : > "$RUN_MANIFEST"
  PROJECT_OWNER=o; PROJECT_NUMBER=1; BOT_LOGIN=bot; CONFIG_SLUG=e2e
  REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""; QA_PID=""; QA_ISSUE=""; QA_EXTRA=""; BUILD_PID=""; BUILD_ISSUE=""; BUILD_EXTRA=""
  MAX_WORKERS=5; ACTIVE_WORKERS=0; REVIEW_WORKERS=1; QA_WORKERS=1; BUILD_WORKERS=1; NOOP_CHECK=""; MQ_LOGGED=""; BACKOFF_LOGGED=""
  PROJECT_ITEMS_JSON='{"items":[]}'
}
# issue <K> <cột>: issue mở + thẻ ở cột đó.
issue() {
  python3 - "$F/state.json" "$1" "$2" <<'PY'
import json, sys
p, k, col = sys.argv[1:]; s = json.load(open(p))
s['issues'][k] = {'number': int(k), 'title': 'card ' + k, 'body': '', 'state': 'OPEN', 'stateReason': None, 'labels': [], 'assignees': [], 'comments': []}
s['board'][k] = col; json.dump(s, open(p, 'w'))
PY
}
# open_pr <PR> <nhánh> <file>: nhánh từ origin/main thêm <file>, đẩy lên origin; PR draft (builder mở draft), diff/metadata từ git.
open_pr() {
  local n="$1" br="$2" file="$3" wt="$R/.claude/worktrees/pr-$1"
  git -C "$R" fetch -q origin
  git -C "$R" worktree add -q -b "$br" "$wt" origin/main
  echo "$n" > "$wt/$file"; git -C "$wt" add "$file"; git -C "$wt" commit -qm "change $n"
  git -C "$R" push -q origin "$br"
  git -C "$R" diff origin/main "$br" > "$W/pr$n.diff"
  python3 - "$F/state.json" "$n" "$br" "$(git -C "$R" rev-parse "$br")" "$file" "$W/pr$n.diff" <<'PY'
import json, sys
p, n, br, sha, f, d = sys.argv[1:]; s = json.load(open(p))
s['prs'][n] = {'number': int(n), 'title': 'change ' + n, 'headRefName': br, 'headRefOid': sha, 'isDraft': True, 'state': 'OPEN',
               'mergeCommit': None, 'labels': [], 'comments': [], 'body': '', 'author': {'login': 'bot'}, 'url': 'https://github.com/o/r/pull/' + n,
               'files': [{'path': f}], 'additions': 1, 'deletions': 0, 'changedFiles': 1, 'diff': open(d).read()}
json.dump(s, open(p, 'w'))
PY
  git -C "$R" worktree remove --force "$wt"
}
head_of() { jq -r --arg n "$1" '.prs[$n].headRefOid' "$F/state.json"; }
st() { jq -r "$1" "$F/state.json"; }
set_col() { python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["board"][sys.argv[2]]=sys.argv[3]; json.dump(s,open(p,"w"))' "$F/state.json" "$1" "$2"; }
# builder giả đang chạy cho thẻ <K>: khoá inflight thật (PID sống, LANE=build), như runner ghi cho một worker build.
builder_on() { sleep 600 & BPID=$!; OWN_PIDS="$OWN_PIDS $BPID"; printf 'PID=%s\nLANE=build\nSTARTED=%s\nWORKER_LOG=x\n' "$BPID" "$(date -u +%FT%TZ)" > "$INFLIGHT_DIR/$1"; }
builder_off() { kill "$BPID" 2>/dev/null; wait "$BPID" 2>/dev/null; }
# hold_queue / free_queue: giữ flock của merge-queue.lock (như một lượt queue đang chạy dài): các tick trong lúc giữ không train được,
# nên thẻ đã vào hàng còn nằm ở Review với nhãn merge-queue (nhánh "skip … is in the merge queue" của runner có việc để làm).
hold_queue() {
  mkdir -p "$COMMON/super-board"; rm -f "$W/queue-held"
  python3 -I -c 'import fcntl,sys,time;f=open(sys.argv[1],"a");fcntl.flock(f,fcntl.LOCK_EX);open(sys.argv[2],"w").close();time.sleep(600)' \
    "$COMMON/super-board/merge-queue.lock" "$W/queue-held" & QHOLD=$!; OWN_PIDS="$OWN_PIDS $QHOLD"
  local i=0; while [ ! -e "$W/queue-held" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
}
free_queue() { kill "$QHOLD" 2>/dev/null; wait "$QHOLD" 2>/dev/null; }
# wait_held <K>: chờ stub reviewer của thẻ K làm xong các bước ghi và đứng ở điểm giữ (tối đa 60 s).
wait_held() { local i=0; while [ ! -e "$F/held-$1" ] && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done; }
# release_worker <K>: thả stub reviewer của thẻ K và chờ wrapper của nó thoát (tối đa 60 s).
release_worker() {
  local pid i=0
  : > "$F/release-$1"
  pid=$(sed -n 's/^PID=//p' "$INFLIGHT_DIR/$1" 2>/dev/null | head -1)
  [ -n "$pid" ] || return 0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
  wait "$pid" 2>/dev/null
}
# Một tick: đúng thứ tự hàm của vòng lặp chính (reap → đọc board → no-op → lane review → merge_queue_due cuối tick).
tick() {
  reap_finished_locks
  fetch_project_items || fail "board read failed (rc=$?)"
  NOOP_MOVED=0; block_noop_workers
  lane_dispatch_tick review Review
  if type merge_queue_due >/dev/null 2>&1; then merge_queue_due; else NO_MQ_DUE=1; fi
}
dispatches() { grep -c "^review $1\$" "$F/claude.calls" 2>/dev/null | tr -d ' '; }
trains() { grep -c '^\[merge-queue\] train of' "$RUN_MANIFEST" 2>/dev/null | tr -d ' '; }
pfg() { if [ -f "$F/pfg.log" ]; then grep -c -- "$1" "$F/pfg.log" | tr -d ' '; else echo 0; fi; }
no_halt() {
  if [ -e "$SB_GITHUB_HALT_FILE" ]; then fail "$1: github-read halted: $(head -c 400 "$SB_GITHUB_HALT_FILE")"; fi
  if [ -s "$F/gh.unexpected" ]; then fail "$1: unexpected gh calls: $(head -3 "$F/gh.unexpected" | tr '\n' '|')"; : > "$F/gh.unexpected"; fi
}

# ── nạp runner thật (một lần)
SB_LIB_ONLY=1 . "$BIN_SRC/super-board-run.sh" || { echo "✖ could not source $BIN_SRC/super-board-run.sh"; exit 1; }
set +e
type merge_queue_due >/dev/null 2>&1 || fail "runner has no merge_queue_due: a tick never calls super-board-merge-queue.sh"
[ -f "$BIN_SRC/super-board-merge-queue.sh" ] || fail "no super-board-merge-queue.sh in $BIN_SRC"
NO_MQ_DUE=0

# ════ Kịch bản chính: queue bật, 3 PR vào hàng lệch nhịp ════════════════════════════════════════════════════════════════════════════
new_world main true
issue 7 Review; issue 8 Building
open_pr 70 issue-7-x f7; open_pr 71 issue-8-x f8; open_pr 72 feature-z fz
H70=$(head_of 70); H71=$(head_of 71); H72=$(head_of 72)   # head lúc review (gate có thể đẩy merge commit lên nhánh sau đó)
builder_on 8                     # thẻ #8 còn đang build: máy chưa rảnh
: > "$F/direct-gate-7"            # (c): reviewer #7 thử gọi thẳng merge gate trước khi vào hàng

# tick 1: thẻ #7 ở Review → runner phóng reviewer; reviewer vào hàng (còn sống ở điểm giữ). Queue bị giữ khoá: chưa train được.
hold_queue
tick; no_halt "tick 1"; wait_held 7
[ "$(dispatches 7)" = 1 ] && ok "tick 1: the runner dispatched one reviewer for #7" || fail "tick 1: reviewer dispatches for #7 = $(dispatches 7): $(cat "$F/claude.calls")"
prompt7=$(sed -n 's/^prompt: //p' "$WORKER_LOG_DIR/worker-review-7.log" 2>/dev/null | head -1)
printf '%s' "$prompt7" | grep -q 'add-label merge-queue' && ok "  … its prompt tells it to enter the merge queue" || fail "  … reviewer prompt has no merge-queue step: $(printf '%s' "$prompt7" | cut -c1-300)"
grep -q '^queued 7 70$' "$F/claude.calls" && ok "  … and the reviewer queued PR 70 (approved-head, ready, label, issue comment)" || fail "  … reviewer did not queue PR 70: $(cat "$F/claude.calls")"
# (c) một lane worker gọi thẳng merge gate khi queue bật
rc7=$(cat "$F/direct-gate-7.rc" 2>/dev/null)
{ [ "$rc7" = 13 ] && grep -qxF 'merge-queue: label the PR merge-queue instead of calling the gate directly' "$F/direct-gate-7.out"; } \
  && ok "(c) a lane worker calling super-board-merge-gate.sh directly while the queue is on: exit 13 with the label line" \
  || fail "(c) direct gate call from a lane worker: rc=${rc7:-<none>} out=$(tail -3 "$F/direct-gate-7.out" 2>/dev/null | tr '\n' '|')"
[ "$(pfg .merge-scratch-)" = 0 ] && ok "(c)  … the gate itself verified nothing (no single-PR verify)" || fail "(c)  … gate verify ran $(pfg .merge-scratch-) time(s)"
{ [ "$(st '.prs["70"].state')" = OPEN ] && ! grep -q 'merged' "$F/direct-gate-7.out"; } && ok "(c)  … and PR 70 is still OPEN (the direct gate call merged nothing)" || fail "(c)  … PR 70 state $(st '.prs["70"].state'): $(cat "$F/direct-gate-7.out" 2>/dev/null | tail -3 | tr '\n' '|')"
# tick 2 (queue đang bị giữ khoá, reviewer #7 + builder #8 còn sống): chưa train, PR 70 còn OPEN, thẻ #7 còn ở Review.
tick; no_halt "tick 2"
[ "$(trains)" = 0 ] && [ "$(st '.prs["70"].state')" = OPEN ] && ok "tick 2: queue lock held by another run: no train, PR 70 still OPEN" || fail "tick 2: trains=$(trains) PR70=$(st '.prs["70"].state')"
release_worker 7

# tick 3: reviewer #7 đã thoát, thẻ #7 còn ở Review với nhãn merge-queue → runner KHÔNG phóng reviewer lần hai, không phạt no-op.
M0=$(wc -l < "$RUN_MANIFEST"); tick; no_halt "tick 3"
[ "$(dispatches 7)" = 1 ] && ok "(a) tick 3: queued card #7 (still in Review) is not dispatched again" || fail "(a) tick 3: #7 re-dispatched ($(dispatches 7) reviewers)"
tail -n +"$((M0 + 1))" "$RUN_MANIFEST" | grep -q 'skip #7 in Review: PR 70 is in the merge queue' && ok "(a)  … the runner says why: PR 70 is in the merge queue" || fail "(a)  … no 'is in the merge queue' skip line: $(tail -n +"$((M0 + 1))" "$RUN_MANIFEST" | tail -4 | tr '\n' '|')"
grep -q 'no-op' "$RUN_MANIFEST" && fail "(a)  … card #7 was judged a no-op" || ok "(a)  … and card #7 is not penalised as a no-op"
# tick 3b: khoá được thả → PR 70 vào train ngay dù builder #8 còn sống (không chờ đủ PR, không chờ máy rảnh).
free_queue; M1=$(wc -l < "$RUN_MANIFEST"); tick; no_halt "tick 3b"
[ "$(trains)" = 1 ] && grep '^\[merge-queue\] train of' "$RUN_MANIFEST" | tail -1 | grep -q -- "70:$H70\$" \
  && ok "(b) lock free: PR 70 went into a train at once (1 PR, builder #8 alive, no wait)" \
  || fail "(b) trains=$(trains): $(grep -i 'merge.queue' "$RUN_MANIFEST" | tail -3 | tr '\n' '|')"
[ "$(st '.prs["70"].state')" = MERGED ] && [ "$(pfg .train-scratch-)" = 1 ] && [ "$(pfg .)" = 1 ] && ok "(b)  … PR 70 merged with one verify (in the train scratch)" || fail "(b)  … PR 70 state $(st '.prs["70"].state') verifies: $(cat "$F/pfg.log" 2>/dev/null)"
tail -n +"$((M1 + 1))" "$RUN_MANIFEST" | grep -q 'not due' && fail "(b) a 'not due' line is still printed" || ok "(b)  … no 'not due' line (the gate for waiting is gone)"

# PR tương tác 72 (không thẻ): người duyệt tay vào hàng.
gh pr comment 72 --body "approved-head:$H72" && gh pr ready 72 && gh pr edit 72 --add-label merge-queue
tick; no_halt "tick 4"
[ "$(trains)" = 2 ] && grep '^\[merge-queue\] train of' "$RUN_MANIFEST" | tail -1 | grep -q -- "72:$H72\$" \
  && ok "(b) tick 4: interactive PR 72 went into its own train at once, builder #8 still alive" || fail "(b) tick 4: trains=$(trains): $(grep '^\[merge-queue\]' "$RUN_MANIFEST" | tail -3 | tr '\n' '|')"

# Builder #8 xong: thẻ sang Review, builder thoát. tick 5: reviewer #8 được phóng và vào hàng; tick 6: PR 71 vào train dù reviewer #8 còn sống.
set_col 8 Review; builder_off
hold_queue
tick; no_halt "tick 5"; wait_held 8
[ "$(dispatches 8)" = 1 ] && grep -q '^queued 8 71$' "$F/claude.calls" && ok "tick 5: #8 reached Review, its reviewer queued PR 71" || fail "tick 5: #8 reviewer: $(cat "$F/claude.calls")"
release_worker 8
M2=$(wc -l < "$RUN_MANIFEST"); tick; no_halt "tick 6"
[ "$(dispatches 7)" = 1 ] && [ "$(dispatches 8)" = 1 ] && ok "(a) tick 6: neither queued card is dispatched again" || fail "(a) tick 6: re-dispatch: $(cat "$F/claude.calls")"
tail -n +"$((M2 + 1))" "$RUN_MANIFEST" | grep -q 'skip #8 in Review: PR 71 is in the merge queue' && ok "(a)  … card #8 waits in Review with the merge-queue skip line" || fail "(a)  … no skip line for #8: $(tail -n +"$((M2 + 1))" "$RUN_MANIFEST" | tail -4 | tr '\n' '|')"
[ "$(trains)" = 2 ] && ok "tick 6: queue lock held, no train yet" || fail "tick 6: trains=$(trains)"
free_queue; tick; no_halt "tick 7"
[ "$(trains)" = 3 ] && grep '^\[merge-queue\] train of' "$RUN_MANIFEST" | tail -1 | grep -q -- "71:$H71\$" \
  && ok "(b) tick 6: PR 71 went into a train as soon as the queue lock was free" || fail "(b) tick 6: trains=$(trains): $(grep '^\[merge-queue\]' "$RUN_MANIFEST" | tail -3 | tr '\n' '|')"
[ "$(pfg .train-scratch-)" = 3 ] && ok "(b) three trains, one verify each (in the train scratch)" || fail "(b) train verifies: $(pfg .train-scratch-): $(cat "$F/pfg.log" 2>/dev/null)"
[ "$(pfg .)" = 3 ] && ok "(b)  … and 0 single-PR verifies by the merge gate" || fail "(b) total verifies $(pfg .): $(cat "$F/pfg.log" 2>/dev/null)"
[ "$(st '[.prs[] | select(.state == "MERGED") | .number] | sort | join(",")')" = "70,71,72" ] && ok "(b) PRs 70, 71, 72 merged" || fail "(b) merged: $(st '.merged')"
( git -C "$R" fetch -q origin && for f in f7 f8 fz; do git -C "$R" cat-file -e "origin/main:$f" || exit 1; done ) 2>/dev/null \
  && ok "(b)  … origin/main holds all three changes" || fail "(b) origin/main misses a change"
[ "$(st '.board["7"]')" = Done ] && [ "$(st '.board["8"]')" = Done ] && ok "(b) board cards #7 and #8 moved to Done (super-board-card.sh)" || fail "(b) board: $(st '.board')"
[ "$(st '.issues["7"].state')" = CLOSED ] && [ "$(st '.issues["8"].state')" = CLOSED ] && ok "(b)  … and their issues closed" || fail "(b) issues: 7=$(st '.issues["7"].state') 8=$(st '.issues["8"].state')"
[ "$(st '[.prs[].labels[] | select(.name == "merge-queue")] | length')" = 0 ] && ok "(b)  … merge-queue label removed from every merged PR" || fail "(b) labels left: $(st '[.prs[] | {n: .number, l: .labels}]')"

# tick 7: hàng trống → không train nữa, không phóng gì.
tick; no_halt "tick 8"
[ "$(trains)" = 3 ] && [ "$(pfg .)" = 3 ] && ok "tick 8: empty queue, no further train or verify" || fail "tick 8: trains=$(trains) verifies=$(pfg .)"
# (a) toàn kịch bản: mỗi thẻ đúng một reviewer; không worker merge-only / merge-train nào.
grep -qE '^(merge-only|merge-train) ' "$F/claude.calls" && fail "(a) a merge-only / merge-train worker was dispatched: $(cat "$F/claude.calls")" || ok "(a) no merge-only / merge-train worker in the whole run"
grep -q 'merge-train for\|merge-only, no fresh review' "$RUN_MANIFEST" && fail "(a) runner log has a merge-train / merge-only dispatch" || ok "(a)  … and no merge-train / merge-only line in the runner log"
[ "$(grep -c '^review ' "$F/claude.calls")" = 2 ] && ok "(a) two reviewers for two cards over the whole run" || fail "(a) reviewer dispatches: $(cat "$F/claude.calls")"
grep -q 'no-op' "$RUN_MANIFEST" && fail "a queued card was judged a no-op: $(grep 'no-op' "$RUN_MANIFEST" | head -2)" || ok "reviewers that queued their PR are not no-ops"
[ "$NO_MQ_DUE" = 0 ] || fail "the runner tick never called merge_queue_due"

# ════ (d) Đường lùi: SB_MERGE_QUEUE=0 với config bật → hành vi cũ ═══════════════════════════════════════════════════════════════════
new_world fallback true
export SB_MERGE_QUEUE=0
issue 9 Review; open_pr 73 issue-9-x f9
tick; no_halt "(d) tick"; wait_held 9
prompt9=$(sed -n 's/^prompt: //p' "$WORKER_LOG_DIR/worker-review-9.log" 2>/dev/null | head -1)
{ printf '%s' "$prompt9" | grep -q 'proceed directly to merge via .claude/bin/super-board-merge-gate.sh' && ! printf '%s' "$prompt9" | grep -q 'add-label merge-queue'; } \
  && ok "(d) SB_MERGE_QUEUE=0: the reviewer prompt keeps the old merge gate step" || fail "(d) prompt: $(printf '%s' "$prompt9" | cut -c1-300)"
grep -q '^gate 9 73 rc=0$' "$F/claude.calls" && [ "$(st '.prs["73"].state')" = MERGED ] && ok "(d)  … the reviewer merged PR 73 through the gate itself" || fail "(d) reviewer gate: $(cat "$F/claude.calls") $(tail -3 "$F/reviewer-gate-9.out" 2>/dev/null | tr '\n' '|')"
[ "$(pfg .merge-scratch-)" = 1 ] && [ "$(pfg .train-scratch-)" = 0 ] && ok "(d)  … one single-PR verify by the gate, no train" || fail "(d) verifies: $(cat "$F/pfg.log" 2>/dev/null)"
release_worker 9
tick; no_halt "(d) tick 2"
{ ! grep -q '^\[merge-queue\]' "$RUN_MANIFEST" && [ ! -e "$COMMON/super-board/merge-queue.lock" ]; } \
  && ok "(d) merge-queue.sh was never called" || fail "(d) merge-queue ran: $(grep '^\[merge-queue\]' "$RUN_MANIFEST" | head -3 | tr '\n' '|')"
unset SB_MERGE_QUEUE

# ════ (e) Backend workflow (Q-schedule, #453): không có runner; lịch launchd rút hàng ═══════════════════════════════════════════════════
# Reviewer (stub claude, bước "vào hàng" như skill) ghi approved-head + nhãn merge-queue; rồi CHẠY ĐÚNG ProgramArguments của plist do
# super-board-queue-schedule.sh cài (không gọi tay merge-queue.sh): một train cho cả 3 PR, một verify, 3 PR merged.
new_world sched true
jq '.worker_backend = "workflow"' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
unset SB_MERGE_QUEUE
cat > "$TMP/path/launchctl" <<'SH'
#!/usr/bin/env bash
echo "launchctl $*" >> "$FAKE/launchctl.calls"
case "$1" in print) [ -e "$FAKE/lc-loaded" ] && exit 0; exit 1 ;; bootstrap) : > "$FAKE/lc-loaded"; exit 0 ;; *) exit 0 ;; esac
SH
chmod +x "$TMP/path/launchctl"
export SB_LAUNCH_AGENTS_DIR="$W/agents"
for k in 11 12 13; do issue "$k" Review; open_pr "$((k + 70))" "issue-$k-x" "g$k"; done
RPIDS=""
for k in 11 12 13; do
  ( cd "$R" && exec claude -p "Run super-review on issue #$k. After the gate decision: add-label merge-queue. Config: $CFG. end" ) >/dev/null 2>&1 &
  RPIDS="$RPIDS $!"; OWN_PIDS="$OWN_PIDS $!"
done
for k in 11 12 13; do wait_held "$k"; done
for k in 11 12 13; do : > "$F/release-$k"; done
for p in $RPIDS; do wait "$p" 2>/dev/null; done
[ "$(st '[.prs[] | select(.labels | map(.name) | index("merge-queue"))] | length')" = 3 ] \
  && ok "(e) workflow: 3 reviewers put their PRs in the queue (label merge-queue)" || fail "(e) queued: $(st '[.prs[] | {n: .number, l: .labels}]')"
bash .claude/bin/super-board-queue-schedule.sh ensure e2e >"$W/ensure.out" 2>&1; bash .claude/bin/super-board-queue-schedule.sh ensure e2e >>"$W/ensure.out" 2>&1
PL=$(ls "$SB_LAUNCH_AGENTS_DIR"/com.superboard.mergequeue.e2e.*.plist 2>/dev/null | head -1)
{ [ -n "$PL" ] && [ "$(grep -c '^launchctl bootstrap' "$F/launchctl.calls")" = 1 ]; } \
  && ok "(e) the schedule is installed once (the second ensure is quiet)" || fail "(e) schedule: plist=$PL $(cat "$W/ensure.out") $(cat "$F/launchctl.calls" 2>/dev/null)"
# Chạy đúng lệnh lịch: ProgramArguments + WorkingDirectory đọc từ plist.
sched_run() {
  python3 -I - "$PL" > "$W/sched.out" 2>&1 <<'PY'
import plistlib, subprocess, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
print('interval', d['StartInterval'])
sys.exit(subprocess.run(d['ProgramArguments'], cwd=d['WorkingDirectory']).returncode)
PY
}
sched_run; rc=$?
[ "$rc" = 0 ] && [ "$(grep -c '^\[merge-queue\] train of' "$W/sched.out")" = 1 ] && ok "(e) the scheduled command ran ONE train" \
  || fail "(e) scheduled run rc=$rc: $(tail -8 "$W/sched.out" | tr '\n' '|')"
[ "$(sed -n 's/^interval //p' "$W/sched.out")" -le 60 ] && ok "(e)  … and the schedule fires at least every 60 s (the queue drains PRs the minute they are queued)" || fail "(e) interval: $(head -1 "$W/sched.out")"
[ "$(st '[.prs[] | select(.state == "MERGED") | .number] | sort | join(",")')" = "81,82,83" ] && [ "$(pfg .train-scratch-)" = 1 ] && [ "$(pfg .)" = 1 ] \
  && ok "(e)  … 3 PRs merged with exactly one verify (in the train scratch)" || fail "(e) merged: $(st '[.prs[] | {n: .number, s: .state}]') verifies: $(cat "$F/pfg.log" 2>/dev/null)"
[ "$(st '.board["11"]')" = Done ] && [ "$(st '.issues["13"].state')" = CLOSED ] && ok "(e)  … cards Done and issues closed" || fail "(e) board: $(st '.board')"
sched_run
[ "$(pfg .)" = 1 ] && ok "(e) the next scheduled tick finds the queue empty: no second train" || fail "(e) second tick verifies: $(pfg .)"
unset SB_LAUNCH_AGENTS_DIR

[ "$FAILS" -eq 0 ] && { echo "✅ test_merge_queue_e2e: all passed"; exit 0; } || { echo "❌ test_merge_queue_e2e: $FAILS failed"; exit 1; }
