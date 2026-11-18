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
{ [ "$rc" = 69 ] && [ ! -e "$HALT" ] && [ "$(cat "$GH_COUNT")" = 3 ]; } \
  && ok "rate limit that never lifts (card.sh status probe): error to the caller (69) after bounded backoff, no github-halt.json" \
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

# P1 (runner): issue_is_open must pass exit 69 through, never turn it into 79 (a RUNNER_HALT_CODES halt).
RUN="${GHR_RUN:-$ROOT/.claude/bin/super-board-run.sh}"
printf 'import sys\nsys.exit(69)\n' > "$TMP/fake-read"
sed -n '/^issue_is_open() {/,/^}/p' "$RUN" > "$TMP/fn.sh"
rc=$(SB_GITHUB_READ_FAKE="$TMP/fake-read" bash -c 'SB_GITHUB_READ="$SB_GITHUB_READ_FAKE"; PROJECT_ITEMS_JSON=; . "$1"; issue_is_open 7 >/dev/null 2>&1; echo $?' _ "$TMP/fn.sh")
[ "$rc" = 69 ] && ok "runner issue_is_open: read exit 69 stays 69 (not the halt code 79)" \
  || fail "issue_is_open rc=$rc (want 69)"

# P1 (approval): a rate-limited read ends with exit 69 and a message, not a traceback.
AP="${GHR_APPROVAL:-$ROOT/.claude/bin/super-board-approval.py}"
rm -f "$HALT" "$GH_COUNT"
GH_MODE=limit-always SB_GITHUB_RATE_RETRIES=1 python3 "$AP" --repo o/r --pr 1 --head abc --plan '{}' >"$TMP/aout" 2>"$TMP/aerr"; rc=$?
{ [ "$rc" = 69 ] && ! grep -q Traceback "$TMP/aerr" && [ ! -e "$HALT" ]; } \
  && ok "approval.py check under rate limit: exit 69, no traceback, no halt" \
  || fail "approval rc=$rc ($(tail -1 "$TMP/aerr"))"

# P1 (merge-gate): approval.py exit 69 must stop the gate with 69, never become approved:false (a human button / Blocked).
MG="${GHR_MERGE_GATE:-$ROOT/.claude/bin/super-board-merge-gate.sh}"
sed -n '/^approval_check() {/,/^}/p' "$MG" > "$TMP/ac.sh"
mkdir -p "$TMP/here"; printf 'import sys\nsys.exit(69)\n' > "$TMP/here/super-board-approval.py"
rc=$(bash -c 'say(){ :; }; HERE="$1"; REPO=o/r; REPO_PATH=/nonexistent; HEAD_REF=x; PR=1; HEAD_SHA=abc; PLAN={}; APPROVED_HEAD=; GITHUB_READ=/bin/true; . "$2"; approval_check' _ "$TMP/here" "$TMP/ac.sh" >/dev/null 2>&1; echo $?)
[ "$rc" = 69 ] && ok "merge-gate approval_check: approval exit 69 stops the gate with 69" \
  || fail "merge-gate approval_check rc=$rc (want 69)"

# P1 (preflight): exit 69 from preflight must not dispatch the card (return 1, stays Ready), not "dispatching without it".
RUN2="${GHR_RUN:-$ROOT/.claude/bin/super-board-run.sh}"
sed -n '/^preflight_gate() {/,/^}/p' "$RUN2" > "$TMP/pg.sh"
printf '#!/usr/bin/env bash\nexit 69\n' > "$TMP/pf.sh"; printf '{"repo":{"remote":"o/r"}}' > "$TMP/cfg.json"
out=$(bash -c 'log(){ echo "$*"; }; SB_PREFLIGHT="$1"; CONFIG_PATH="$2"; PROJECT_ITEMS_JSON="{\"items\":[]}"; RUN_MANIFEST=/dev/null; SB_GITHUB_READ=/x/y; WAITING_ON_JQ=; . "$3"; preflight_gate 7; echo "rc=$?"' _ "$TMP/pf.sh" "$TMP/cfg.json" "$TMP/pg.sh" 2>&1)
case "$out" in *"rc=1"*) ok "runner preflight_gate: exit 69 is not dispatched (rc=1)" ;; *) fail "preflight_gate 69: $out" ;; esac

# P3 (reconcile): a rate-limited verifying read is 69 (retry later), not 11 (unknown -> hold + notify).
mkdir -p "$TMP/rc"; printf '{"verify":{"kind":"pr-merged","pr":3}}' > "$TMP/rc/halt.json"
rc=$(GH_MODE=limit-always SB_GITHUB_HALT_FILE="$TMP/rc/halt.json" python3 "$READ" --reconcile >/dev/null 2>&1; echo $?)
{ [ "$rc" = 69 ] && [ -s "$TMP/rc/halt.json" ]; } && ok "--reconcile under rate limit: exit 69, halt kept" \
  || fail "reconcile rc=$rc (want 69)"

# P3 (AC2): the real card.sh status under rate limit hands the error to the caller and writes no halt.
CARD="${GHR_CARD:-$ROOT/.claude/bin/super-board-card.sh}"
rm -f "$HALT" "$GH_COUNT"
GH_MODE=limit-always SB_GITHUB_RATE_RETRIES=1 bash "$CARD" --config "$ROOT/.claude/super-board/configs/agent-workbench.json" status 1 >"$TMP/cout" 2>"$TMP/cerr"; rc=$?
{ [ "$rc" != 0 ] && [ ! -e "$HALT" ]; } && ok "card.sh status under rate limit: error rc=$rc, no github-halt.json" \
  || fail "card.sh status rc=$rc halt=$([ -e "$HALT" ] && echo yes || echo no) ($(tail -1 "$TMP/cerr"))"

[ "$FAILS" -eq 0 ] && { echo "OK"; exit 0; } || { echo "$FAILS failed"; exit 1; }
