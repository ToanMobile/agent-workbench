#!/usr/bin/env bash
# #1311: GitHub's secondary rate limit refuses GraphQL while `rate_limit` still shows quota. The runner counted 3 refusals as
# 3 failed reads and wrote github-halt.json (18/11, twice), and a probe like `super-board-card.sh status` did the same.
# A rate-limit refusal is temporary: back off and ask again, never halt; a permanent error still halts at once.
# GHR_READ runs the cases against another copy (RED on the old one). Bash 3.2 compatible.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="${GHR_READ:-$ROOT/.claude/bin/super-board-github-read.py}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-ghread-rl.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(( $(cat "$GH_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$GH_COUNT"
case "$GH_MODE" in
  limit-then-ok) [ "$n" -le "$GH_FAILS" ] && { echo 'GraphQL: API rate limit already exceeded for user ID 1. (graphql_rate_limit)' >&2; exit 1; }
                 echo '{"number":5,"title":"t","body":"b"}' ;;
  limit-always)  echo 'You have exceeded a secondary rate limit.' >&2; exit 1 ;;
  gql-limit-then-ok) [ "$n" -le "$GH_FAILS" ] && { echo '{"data":null,"errors":[{"type":"RATE_LIMITED","message":"API rate limit already exceeded for user ID 1."}]}'; exit 0; }
                     echo '{"number":5,"title":"t","body":"b"}' ;;
  gql-limit-always)  echo '{"data":null,"errors":[{"type":"RATE_LIMITED","message":"You have exceeded a secondary rate limit."}]}'; exit 0 ;;
  gql-perm-data-rl)  echo '{"data":{"issue":{"body":"see rate limit docs"}},"errors":[{"message":"Cannot query field x on type Query"}]}'; exit 0 ;;
  gql-bad-data-rl)   echo '{"data":{"note":"already exceeded rate limit"}}'; exit 0 ;;
  permanent)     echo 'HTTP 401: requires authentication' >&2; exit 1 ;;
  perm-stdout)   echo 'HTTP 401: requires authentication' >&2; echo '{"message":"see the rate limit docs"}'; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
HALT="$TMP/halt.json"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$HALT" SB_GITHUB_RETRY_DELAY=0 SB_GITHUB_RATE_DELAY=0 GH_COUNT="$TMP/count"
run() {   # $1 mode, $2 fails before success; STRICT like the runner and card.sh
  rm -f "$HALT" "$GH_COUNT"
  GH_MODE="$1" GH_FAILS="$2" SB_GITHUB_READ_STRICT=1 python3 "$READ" --kind issue -- issue view 5 --json number,title,body >"$TMP/out" 2>"$TMP/err"
  echo $?
}

rc=$(run limit-then-ok 3)
{ [ "$rc" = 0 ] && [ ! -e "$HALT" ] && [ "$(cat "$GH_COUNT")" = 4 ]; } \
  && ok "3 rate-limit refusals in a row (STRICT): backs off, 4th read passes, no halt" \
  || fail "limit x3 then ok: rc=$rc halt=$([ -e "$HALT" ] && echo yes || echo no) calls=$(cat "$GH_COUNT") ($(tail -1 "$TMP/err"))"

rc=$(SB_GITHUB_RATE_RETRIES=2 run limit-always 0)
{ [ "$rc" = 68 ] && [ ! -e "$HALT" ] && [ "$(cat "$GH_COUNT")" = 3 ]; } \
  && ok "rate limit that never lifts (card.sh status probe): error to the caller (68) after bounded backoff, no github-halt.json" \
  || fail "limit always: rc=$rc halt=$([ -e "$HALT" ] && echo yes || echo no) calls=$(cat "$GH_COUNT")"

rc=$(run permanent 0)
{ [ "$rc" = 79 ] && [ -s "$HALT" ] && [ "$(cat "$GH_COUNT")" = 1 ]; } \
  && ok "permanent error (HTTP 401) still halts on the first read" \
  || fail "permanent: rc=$rc halt=$([ -e "$HALT" ] && echo yes || echo no) calls=$(cat "$GH_COUNT")"

# P2: only stderr says "rate limit"; a permanent error whose stdout merely mentions it must still halt at once.
rc=$(run perm-stdout 0)
{ [ "$rc" = 79 ] && [ -s "$HALT" ] && [ "$(cat "$GH_COUNT")" = 1 ]; } \
  && ok "permanent error whose stdout mentions 'rate limit': halts on the first read" \
  || fail "perm-stdout: rc=$rc halt=$([ -e "$HALT" ] && echo yes || echo no) calls=$(cat "$GH_COUNT")"

# #1311 R2: gh api graphql exits 0 with rate-limit JSON errors -> back off, do not halt; permanent error or bad data still halts.
rc=$(run gql-limit-then-ok 3)
{ [ "$rc" = 0 ] && [ ! -e "$HALT" ] && [ "$(cat "$GH_COUNT")" = 4 ]; } \
  && ok "exit 0 GraphQL errors rate limit x3 then ok: backs off, 4th read passes, no halt" \
  || fail "gql-limit-then-ok: rc=$rc halt=$([ -e "$HALT" ] && echo yes || echo no) calls=$(cat "$GH_COUNT") ($(tail -1 "$TMP/err"))"

rc=$(SB_GITHUB_RATE_RETRIES=2 run gql-limit-always 0)
{ [ "$rc" = 68 ] && [ ! -e "$HALT" ] && [ "$(cat "$GH_COUNT")" = 3 ]; } \
  && ok "exit 0 GraphQL errors rate limit never lifts: exit 68 after bounded backoff, no halt" \
  || fail "gql-limit-always: rc=$rc halt=$([ -e "$HALT" ] && echo yes || echo no) calls=$(cat "$GH_COUNT")"

rc=$(run gql-perm-data-rl 0)
{ [ "$rc" = 79 ] && [ -s "$HALT" ] && [ "$(cat "$GH_COUNT")" = 1 ]; } \
  && ok "exit 0 GraphQL permanent error with 'rate limit' in data: halts on first read" \
  || fail "gql-perm-data-rl: rc=$rc halt=$([ -e "$HALT" ] && echo yes || echo no) calls=$(cat "$GH_COUNT")"

rc=$(run gql-bad-data-rl 0)
{ [ "$rc" = 79 ] && [ -s "$HALT" ] && [ "$(cat "$GH_COUNT")" = 3 ]; } \
  && ok "exit 0 malformed payload with 'rate limit' outside errors: not treated as rate limit, halts after 3 shape fails" \
  || fail "gql-bad-data-rl: rc=$rc halt=$([ -e "$HALT" ] && echo yes || echo no) calls=$(cat "$GH_COUNT")"

# #1311 R7: complete_pr_files() REST /files call for PR >= 100 files under rate limit -> backs off and passes (or exits 68, no halt).
cat > "$TMP/bin/gh-rest" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
cf = os.environ['REST_COUNT']
n = int(open(cf).read()) + 1 if os.path.exists(cf) else 1
open(cf, 'w').write(str(n))
if a[:2] == ['pr', 'view']:
    files = [{'path': f'f{i}.py', 'additions': 1, 'deletions': 0} for i in range(100)]
    print(json.dumps({'labels': [], 'files': files, 'additions': 105, 'deletions': 0, 'changedFiles': 105, 'body': ''}))
elif a[0] == 'api' and '/files' in a[1]:
    fc = os.environ['REST_API_COUNT']
    k = int(open(fc).read()) + 1 if os.path.exists(fc) else 1
    open(fc, 'w').write(str(k))
    if k <= int(os.environ.get('REST_FAILS', '0')):
        sys.stderr.write('You have exceeded a secondary rate limit.\n')
        sys.exit(1)
    files = [{'filename': f'f{i}.py', 'additions': 1, 'deletions': 0} for i in range(105)]
    print(json.dumps([files]))
else:
    sys.stderr.write('unexpected gh: ' + ' '.join(a) + '\n')
    sys.exit(1)
PY
chmod +x "$TMP/bin/gh-rest"
mkdir -p "$TMP/restbin"; cp "$TMP/bin/gh-rest" "$TMP/restbin/gh"
rm -f "$HALT" "$TMP/rcount" "$TMP/racount"
rc=$(PATH="$TMP/restbin:$PATH" REST_COUNT="$TMP/rcount" REST_API_COUNT="$TMP/racount" REST_FAILS=3 SB_GITHUB_READ_STRICT=1 \
  python3 "$READ" --kind metadata -- pr view 5 --repo o/r --json labels,files,additions,deletions,changedFiles,body >"$TMP/rout" 2>"$TMP/rerr"; echo $?)
{ [ "$rc" = 0 ] && [ ! -e "$HALT" ] && [ "$(jq '.files | length' "$TMP/rout" 2>/dev/null)" = 105 ]; } \
  && ok "R7 complete_pr_files REST rate limit x3 then ok: backs off, returns 105 files, no halt" \
  || fail "R7 complete_pr_files x3: rc=$rc halt=$([ -e "$HALT" ] && echo yes || echo no) files=$(jq '.files | length' "$TMP/rout" 2>/dev/null) err=$(tail -2 "$TMP/rerr")"

rm -f "$HALT" "$TMP/rcount" "$TMP/racount"
rc=$(PATH="$TMP/restbin:$PATH" REST_COUNT="$TMP/rcount" REST_API_COUNT="$TMP/racount" REST_FAILS=99 SB_GITHUB_RATE_RETRIES=2 SB_GITHUB_READ_STRICT=1 \
  python3 "$READ" --kind metadata -- pr view 5 --repo o/r --json labels,files,additions,deletions,changedFiles,body >"$TMP/rout" 2>"$TMP/rerr"; echo $?)
{ [ "$rc" = 68 ] && [ ! -e "$HALT" ]; } \
  && ok "R7 complete_pr_files REST rate limit never lifts: exit 68, no halt" \
  || fail "R7 complete_pr_files always: rc=$rc halt=$([ -e "$HALT" ] && echo yes || echo no) err=$(tail -2 "$TMP/rerr")"

# P1 (runner): issue_is_open must pass exit 68 through, never turn it into 79 (a RUNNER_HALT_CODES halt).
RUN="${GHR_RUN:-$ROOT/.claude/bin/super-board-run.sh}"
printf 'import sys\nsys.exit(68)\n' > "$TMP/fake-read"
sed -n '/^issue_is_open() {/,/^}/p' "$RUN" > "$TMP/fn.sh"
rc=$(SB_GITHUB_READ_FAKE="$TMP/fake-read" bash -c 'SB_GITHUB_READ="$SB_GITHUB_READ_FAKE"; PROJECT_ITEMS_JSON=; . "$1"; issue_is_open 7 >/dev/null 2>&1; echo $?' _ "$TMP/fn.sh")
[ "$rc" = 68 ] && ok "runner issue_is_open: read exit 68 stays 68 (not the halt code 79)" \
  || fail "issue_is_open rc=$rc (want 68)"

# P1 (approval): a rate-limited read ends with exit 68 and a message, not a traceback.
AP="${GHR_APPROVAL:-$ROOT/.claude/bin/super-board-approval.py}"
rm -f "$HALT" "$GH_COUNT"
GH_MODE=limit-always SB_GITHUB_RATE_RETRIES=1 python3 "$AP" --repo o/r --pr 1 --head abc --plan '{}' >"$TMP/aout" 2>"$TMP/aerr"; rc=$?
{ [ "$rc" = 68 ] && ! grep -q Traceback "$TMP/aerr" && [ ! -e "$HALT" ]; } \
  && ok "approval.py check under rate limit: exit 68, no traceback, no halt" \
  || fail "approval rc=$rc ($(tail -1 "$TMP/aerr"))"

# P1 (merge-gate): approval.py exit 68 must stop the gate with 68, never become approved:false (a human button / Blocked).
MG="${GHR_MERGE_GATE:-$ROOT/.claude/bin/super-board-merge-gate.sh}"
sed -n '/^approval_check() {/,/^}/p' "$MG" > "$TMP/ac.sh"
mkdir -p "$TMP/here"; printf 'import sys\nsys.exit(68)\n' > "$TMP/here/super-board-approval.py"
rc=$(bash -c 'say(){ :; }; HERE="$1"; REPO=o/r; REPO_PATH=/nonexistent; HEAD_REF=x; PR=1; HEAD_SHA=abc; PLAN={}; APPROVED_HEAD=; GITHUB_READ=/bin/true; . "$2"; approval_check' _ "$TMP/here" "$TMP/ac.sh" >/dev/null 2>&1; echo $?)
[ "$rc" = 68 ] && ok "merge-gate approval_check: approval exit 68 stops the gate with 68" \
  || fail "merge-gate approval_check rc=$rc (want 68)"

# P1 (preflight): exit 68 from preflight must not dispatch the card (return 1, stays Ready), not "dispatching without it".
RUN2="${GHR_RUN:-$ROOT/.claude/bin/super-board-run.sh}"
sed -n '/^preflight_gate() {/,/^}/p' "$RUN2" > "$TMP/pg.sh"
printf '#!/usr/bin/env bash\nexit 68\n' > "$TMP/pf.sh"; printf '{"repo":{"remote":"o/r"}}' > "$TMP/cfg.json"
out=$(bash -c 'log(){ echo "$*"; }; SB_PREFLIGHT="$1"; CONFIG_PATH="$2"; PROJECT_ITEMS_JSON="{\"items\":[]}"; RUN_MANIFEST=/dev/null; SB_GITHUB_READ=/x/y; WAITING_ON_JQ=; . "$3"; preflight_gate 7; echo "rc=$?"' _ "$TMP/pf.sh" "$TMP/cfg.json" "$TMP/pg.sh" 2>&1)
case "$out" in *"rc=1"*) ok "runner preflight_gate: exit 68 is not dispatched (rc=1)" ;; *) fail "preflight_gate 68: $out" ;; esac

# P3 (reconcile): a rate-limited verifying read is 68 (retry later), not 11 (unknown -> hold + notify).
mkdir -p "$TMP/rc"; printf '{"verify":{"kind":"pr-merged","pr":3}}' > "$TMP/rc/halt.json"
rc=$(GH_MODE=limit-always SB_GITHUB_HALT_FILE="$TMP/rc/halt.json" python3 "$READ" --reconcile >/dev/null 2>&1; echo $?)
{ [ "$rc" = 68 ] && [ -s "$TMP/rc/halt.json" ]; } && ok "--reconcile under rate limit: exit 68, halt kept" \
  || fail "reconcile rc=$rc (want 68)"

# P3 (AC2): the real card.sh status under rate limit hands the error to the caller and writes no halt.
CARD="${GHR_CARD:-$ROOT/.claude/bin/super-board-card.sh}"
rm -f "$HALT" "$GH_COUNT"
GH_MODE=limit-always SB_GITHUB_RATE_RETRIES=1 bash "$CARD" --config "$ROOT/.claude/super-board/configs/agent-workbench.json" status 1 >"$TMP/cout" 2>"$TMP/cerr"; rc=$?
{ [ "$rc" = 68 ] && [ ! -e "$HALT" ]; } && ok "card.sh status under rate limit: error rc=68, no github-halt.json" \
  || fail "card.sh status rc=$rc halt=$([ -e "$HALT" ] && echo yes || echo no) ($(tail -1 "$TMP/cerr"))"

# #1311 R6/R8: all 6 issue_is_open callers + backlog_issue_body must NOT exit 68 (STATE=crashed); they set RATE_LIMITED_TICK=1 cleanly.
run_caller_check() {
  local label="$1" body="$2"
  local sub
  sub=$(SB_LIB_ONLY=1 RUN_SRC="$RUN" TMP_D="$TMP" bash -c '
    set -euo pipefail
    . "$RUN_SRC"
    log() { :; }; gh_checkpoint() { :; }; issue_locked() { return 1; }; early_backoff() { return 1; }
    review_wait_cooldown() { return 1; }; ready_card_held() { return 1; }; merge_queue_on() { return 1; }
    backlog_pull_enabled() { return 0; }
    issue_is_open() { return 68; }
    backlog_issue_body() { return 68; }
    RATE_LIMITED_TICK=0; PROJECT_OWNER=o; PROJECT_NUMBER=1; BOT_LOGIN=""
    '"$body"'
    printf "rl=%s\n" "${RATE_LIMITED_TICK:-0}"
  ' 2>"$TMP/caller.err")
  local rc=$?
  if [ "$rc" = 0 ] && [ "$sub" = "rl=1" ]; then
    ok "R6/R8 caller $label: no exit 68, sets RATE_LIMITED_TICK=1"
  else
    fail "R6/R8 caller $label: rc=$rc out='$sub' err=$(tail -1 "$TMP/caller.err")"
  fi
}

run_caller_check "top_card_in_column" '
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"I1\",\"status\":\"Ready\",\"content\":{\"type\":\"Issue\",\"number\":7,\"assignees\":[]}}]}"
  top_card_in_column Ready || true'
run_caller_check "review_train_batch" '
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"I1\",\"status\":\"Review\",\"content\":{\"type\":\"Issue\",\"number\":7,\"assignees\":[]}}]}"
  review_train_batch'
run_caller_check "dispatch_lane" '
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"I1\",\"status\":\"Ready\",\"content\":{\"type\":\"Issue\",\"number\":7,\"assignees\":[]}}]}"
  dispatch_lane build 7'
run_caller_check "reclaim_stranded_building" '
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"I1\",\"status\":\"Building\",\"content\":{\"type\":\"Issue\",\"number\":7,\"assignees\":[]}}]}"
  reclaim_stranded_building'
run_caller_check "sweep_closed_cards" '
  SWEEP_CLOSED_NEXT=0
  python3() { echo "[{\"number\":7,\"stateReason\":\"COMPLETED\"}]"; }
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"I1\",\"status\":\"Ready\",\"content\":{\"type\":\"Issue\",\"number\":7,\"assignees\":[]}}]}"
  sweep_closed_cards || true'
run_caller_check "pull_backlog_cards (issue_is_open)" '
  BUILD_COUNT=0; BUILD_WORKERS=2; READY=0
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"I1\",\"status\":\"Backlog\",\"content\":{\"type\":\"Issue\",\"number\":7,\"assignees\":[]}}]}"
  pull_backlog_cards || true'
run_caller_check "pull_backlog_cards (backlog_issue_body)" '
  BUILD_COUNT=0; BUILD_WORKERS=2; READY=0
  issue_is_open() { return 0; }
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"I1\",\"status\":\"Backlog\",\"content\":{\"type\":\"Issue\",\"number\":7,\"assignees\":[]}}]}"
  pull_backlog_cards || true'

# #1311 R6/R8: real super-board-run.sh loop survives > SB_READ_SKIP_MAX rate-limit ticks without multiplying backoff or STATE=crashed,
# and also survives issue_is_open rate limits inside the loop until GitHub recovers.
RR="$TMP/runrepo"
git init -q -b develop "$RR"
git -C "$RR" config user.email t@example.invalid; git -C "$RR" config user.name t
printf '.claude/\ndocs/\n' > "$RR/.gitignore"
git -C "$RR" add .gitignore; git -C "$RR" commit -qm init
mkdir -p "$RR/.claude/bin" "$RR/.claude/super-board/configs" "$RR/docs/super-board/runs" "$TMP/rbin"
for f in super-board-run.sh super-board-github-read.py super-board-card.sh super-board-gh-guard.sh super-board-approved-head.jq; do
  cp "$ROOT/.claude/bin/$f" "$RR/.claude/bin/$f"
done
printf '#!/usr/bin/env python3\nimport sys\nsys.exit(0)\n' > "$RR/.claude/bin/super-board-verification-ready.py"
printf '#!/usr/bin/env bash\nexit 0\n' > "$RR/.claude/bin/super-board-watchdog.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$RR/.claude/bin/super-board-post-merge-clean.sh"
printf '#!/usr/bin/env bash\necho "{}"\n' > "$RR/.claude/bin/super-board-preflight.sh"
printf '#!/usr/bin/env python3\nprint("{}")\n' > "$RR/.claude/bin/super-board-notify.py"
chmod +x "$RR/.claude/bin"/*.sh "$RR/.claude/bin"/*.py
cat > "$RR/.claude/super-board/configs/test.json" <<'JSON'
{
  "version": 1,
  "project": {"owner": "o", "number": 1},
  "repo": {"path": ".", "remote": "https://github.com/o/r"},
  "base_branch": "develop",
  "worker_backend": "claude-p",
  "tick_seconds": 0,
  "max_workers": 5,
  "no_progress_cycles": 6,
  "backlog_pull": false,
  "verify_commands": ["true"],
  "merge_queue": {"enabled": false}
}
JSON

cat > "$TMP/rbin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
mode = os.environ['LOOP_MODE']
def bump(name):
    p = os.environ['LOOP_STATE_DIR'] + '/' + name
    n = int(open(p).read()) + 1 if os.path.exists(p) else 1
    open(p, 'w').write(str(n))
    return n
if a[:2] == ['api', 'rate_limit']:
    if mode == 'quota-rl' and bump('quota_calls') <= 3:
        sys.stderr.write('You have exceeded a secondary rate limit.\n')
        sys.exit(1)
    print(json.dumps({'resources': {'core': {'remaining': 4500, 'reset': 9999999999}, 'graphql': {'remaining': 4500, 'reset': 9999999999}}}))
elif a[0] == 'api' and a[1] == 'graphql':
    q = ' '.join(a)
    if 'projectV2' in q and 'items(' in q:
        n = bump('items_calls')
        if mode == 'items-rl' and n <= 8:
            sys.stderr.write('You have exceeded a secondary rate limit.\n')
            sys.exit(1)
        if mode == 'issue-rl':
            # first reads (start-up + ticks 1-3) return Ready card #7; then an empty board
            if n <= 6:
                print(json.dumps([{'data': {'repositoryOwner': {'projectV2': {'items': {
                    'totalCount': 1,
                    'pageInfo': {'hasNextPage': False, 'endCursor': None},
                    'nodes': [{'id': 'PVTI_7', 'fieldValueByName': {'name': 'Ready'},
                               'content': {'__typename': 'Issue', 'number': 7, 'title': 't7', 'url': 'u',
                                           'repository': {'nameWithOwner': 'o/r'}, 'labels': {'nodes': [{'name': 'bug'}]}}}]
                }}}}}]))
            else:
                print(json.dumps([{'data': {'repositoryOwner': {'projectV2': {'items': {
                    'totalCount': 0, 'pageInfo': {'hasNextPage': False, 'endCursor': None}, 'nodes': []
                }}}}}]))
        else:
            print(json.dumps([{'data': {'repositoryOwner': {'projectV2': {'items': {
                'totalCount': 0, 'pageInfo': {'hasNextPage': False, 'endCursor': None}, 'nodes': []
            }}}}}]))
    else:
        print(json.dumps({'data': {}}))
elif a[:2] == ['issue', 'view']:
    bump('issue_calls')
    sys.stderr.write('You have exceeded a secondary rate limit.\n')
    sys.exit(1)
elif a[:2] == ['issue', 'list']:
    print('[]')
else:
    print('{}')
PY
chmod +x "$TMP/rbin/gh"

# The runner is a daemon (an empty board does not end it), so each scenario runs it in the background, waits for the evidence, then stops it.
# Pass = it was still alive and STATE=running while GitHub was rate limited (a crash would show STATE=crashed / a dead pid), no halt file.
run_loop_scenario() {  # $1 = LOOP_MODE, $2 = state dir, $3 = out, $4 = err, $5 = grep that proves the skip, $6 = tag
  local mode="$1" sd="$2" out="$3" err="$4" want="$5" tag="$6" pid n=0 alive=n st skips recovered=n
  mkdir -p "$sd"
  rm -f "$RR/.claude/super-board/github-halt.json" "$RR/.claude/super-board/runner/test.state"
  ( cd "$RR" && PATH="$TMP/rbin:$PATH" LOOP_MODE="$mode" LOOP_STATE_DIR="$sd" \
      SB_GITHUB_HALT_FILE="$RR/.claude/super-board/github-halt.json" \
      SB_GITHUB_RATE_RETRIES=1 SB_GITHUB_RATE_DELAY=0 SB_GITHUB_RETRY_DELAY=0 \
      SB_READ_SKIP_MAX=2 SB_FETCH_RETRY_DELAYS="1 1 1" SB_NOTIFY_SKIP=1 \
      bash "$RR/.claude/bin/super-board-run.sh" test >"$out" 2>"$err" ) &
  pid=$!
  while [ "$n" -lt 150 ]; do   # up to ~15 s
    skips=$(grep -c "$want" "$out" 2>/dev/null); skips=${skips:-0}
    if [ "$skips" -ge "${7:-3}" ] && grep -q '^\[[0-9:]*\] tick — Ready=0' "$out" 2>/dev/null; then recovered=y; break; fi
    sleep 0.1; n=$((n + 1))
  done
  ps -p "$pid" >/dev/null 2>&1 && alive=y
  st=$(sed -n 's/^STATE=//p' "$RR/.claude/super-board/runner/test.state" 2>/dev/null | head -1)
  pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null   # children first: the next scenario must not meet this runner's pid
  sleep 0.5
  RL_ALIVE=$alive; RL_STATE=$st; RL_RECOVERED=$recovered; RL_SKIPS=$skips
}

# R8a: board read rate limited for more than SB_READ_SKIP_MAX ticks (8 calls): the runner keeps going, never STATE=crashed, then recovers.
run_loop_scenario items-rl "$TMP/rstate1" "$TMP/r1.out" "$TMP/r1.err" "skipping this tick, runner keeps going" R8a
calls1=$(cat "$TMP/rstate1/items_calls" 2>/dev/null || echo 0)
if [ "$RL_ALIVE" = y ] && [ "$RL_STATE" = running ] && [ "$RL_RECOVERED" = y ] && [ ! -e "$RR/.claude/super-board/github-halt.json" ] && [ "$calls1" -ge 9 ]; then
  ok "R8a real runner loop (board read rate limited > SB_READ_SKIP_MAX): alive, STATE=running, recovered, no halt, backoff not multiplied"
else
  fail "R8a real runner loop items-rl: alive=$RL_ALIVE STATE=$RL_STATE recovered=$RL_RECOVERED skips=$RL_SKIPS calls=$calls1 tail=$(tail -4 "$TMP/r1.out" "$TMP/r1.err" | tr '\n' ' ')"
fi

# R8b: issue_is_open rate limited inside the tick (Ready card #7): that card is skipped, the runner neither exits nor halts, then GitHub recovers.
run_loop_scenario issue-rl "$TMP/rstate2" "$TMP/r2.out" "$TMP/r2.err" "skipping this tick for this card" R8b 1
if [ "$RL_ALIVE" = y ] && [ "$RL_STATE" = running ] && [ "$RL_SKIPS" -ge 1 ] && [ ! -e "$RR/.claude/super-board/github-halt.json" ]; then
  ok "R8b real runner loop (issue_is_open rate limited in the tick): card skipped, alive, STATE=running, no halt"
else
  fail "R8b real runner loop issue-rl: alive=$RL_ALIVE STATE=$RL_STATE skips=$RL_SKIPS halt=$([ -e "$RR/.claude/super-board/github-halt.json" ] && echo y || echo n) tail=$(tail -4 "$TMP/r2.out" "$TMP/r2.err" | tr '\n' ' ')"
fi

# R10: a rate-limited tick (RATE_LIMITED_TICK=1, no worker) is not a no-progress cycle; the same tick without the flag still counts.
r10=$(SB_LIB_ONLY=1 RUN_SRC="$RUN" bash -c '
  set -euo pipefail
  . "$RUN_SRC"
  log() { :; }; dispatch_paused() { return 1; }; board_only_file_wait() { return 1; }
  NO_PROGRESS_CYCLES=9; PREV_DONE_SIG=9; MQ_WAITING=0; ACTIVE_WORKERS=0; LOAD_HELD_TICK=0
  NO_PROGRESS_CYCLE_COUNT=0; RATE_LIMITED_TICK=1; record_cycle_progress 9 || true; a=$NO_PROGRESS_CYCLE_COUNT
  NO_PROGRESS_CYCLE_COUNT=0; RATE_LIMITED_TICK=0; record_cycle_progress 9 || true; b=$NO_PROGRESS_CYCLE_COUNT
  echo "a=$a b=$b"' 2>&1)
[ "$r10" = "a=0 b=1" ] && ok "R10 rate-limited tick not counted as no-progress (plain tick still is)" || fail "R10 got '$r10', want 'a=0 b=1'"

# R9: the quota read (gh_rate_guard) at start-up is rate limited past the backoff: startup_reconcile logs it and goes on, never dies (set -e => STATE=crashed).
run_loop_scenario quota-rl "$TMP/rstate3" "$TMP/r3.out" "$TMP/r3.err" "rate limit at start-up" R9 1
if [ "$RL_ALIVE" = y ] && [ "$RL_STATE" = running ] && [ "$RL_SKIPS" -ge 1 ] && [ ! -e "$RR/.claude/super-board/github-halt.json" ]; then
  ok "R9 real runner start-up (quota read rate limited): alive, STATE=running, no halt"
else
  fail "R9 real runner start-up quota-rl: alive=$RL_ALIVE STATE=$RL_STATE skips=$RL_SKIPS tail=$(tail -4 "$TMP/r3.out" "$TMP/r3.err" | tr '\n' ' ')"
fi

[ "$FAILS" -eq 0 ] && { echo "OK"; exit 0; } || { echo "$FAILS failed"; exit 1; }
