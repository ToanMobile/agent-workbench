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

[ "$FAILS" -eq 0 ] && { echo "OK"; exit 0; } || { echo "$FAILS failed"; exit 1; }
