#!/usr/bin/env bash
# Test hồi quy #1321: thẻ nhãn `session` (hook session_card.sh) vào Ready không có AC bị preflight_gate chuyển Blocked ❓ kèm
# comment [blocker] chờ người (#1131, #1182). Luật:
#  A  thẻ Ready nhãn `session`, preflight nói hold/unclear → không dispatch (trả 1), thẻ về Backlog, KHÔNG comment.
#  B  thẻ Ready không nhãn `session`, cùng verdict → vẫn Blocked + comment [blocker] như cũ.
# Runner THẬT của checkout chứa file test (ROOT từ $0). Offline, gh giả. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-pf-session.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/sbin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
line="$*"; printf '%s\n' "${line//$'\n'/⏎}" >> "$GH_LOG"
exit 0
SH
printf 'import sys\nsys.exit(0)\n' > "$TMP/sbin/super-board-github-read.py"
cat > "$TMP/sbin/preflight.sh" <<'SH'
#!/usr/bin/env bash
echo '{"501":{"verdict":"hold","tag":"unclear","reason":"no AC","evidence":["issue #501 body"]},"502":{"verdict":"hold","tag":"unclear","reason":"no AC","evidence":["issue #502 body"]}}'
SH
chmod +x "$TMP/bin/gh" "$TMP/sbin/"*
echo '{"repo":{"remote":"o/r"}}' > "$TMP/config.json"
ITEMS='{"items":[{"id":"I501","status":"Ready","labels":["session"],"content":{"type":"Issue","number":501,"title":"session card","labels":["session"]}},
 {"id":"I502","status":"Ready","labels":[],"content":{"type":"Issue","number":502,"title":"plain card"}}]}'

run_case() {
  rm -f "$TMP/gh.log"
  OUT=$( ( SB_LIB_ONLY=1 . "$RUNNER" >/dev/null 2>&1 || exit 99
      set +e; cd "$TMP" || exit 98
      log() { echo "$*" >> "$TMP/log"; }
      PATH="$TMP/bin:$PATH"; export GH_LOG="$TMP/gh.log"
      SB_GITHUB_READ="$TMP/sbin/super-board-github-read.py"; SB_PREFLIGHT="$TMP/sbin/preflight.sh"; RUN_MANIFEST=/dev/null
      CONFIG_PATH="$TMP/config.json"; STATUS_FIELD_ID=F; PROJECT_NODE_ID=P
      STATUS_OPTIONS_JSON='[{"name":"Backlog","id":"OBACK"},{"name":"Ready","id":"OREADY"},{"name":"Blocked","id":"OBLOCKED"}]'
      PROJECT_ITEMS_JSON="$ITEMS"
      preflight_gate "$1"; echo "rc=$?" ) 2>/dev/null )
}
gh_has() { grep -qF -- "$1" "$TMP/gh.log" 2>/dev/null; }

run_case 501
printf '%s\n' "$OUT" | grep -qx 'rc=1' && ok "A: session card not dispatched" || fail "A: out=$OUT"
gh_has 'single-select-option-id OBACK' && ok "A: moved to Backlog" || fail "A: no Backlog move: $(cut -c1-100 "$TMP/gh.log" 2>/dev/null)"
gh_has 'issue comment 501' && fail "A: blocker comment posted" || ok "A: no comment"
gh_has 'OBLOCKED' && fail "A: moved to Blocked" || ok "A: not Blocked"

run_case 502
gh_has 'single-select-option-id OBLOCKED' && gh_has 'issue comment 502 --body [orchestrator] [blocker]' \
  && ok "B: plain card still Blocked + comment" || fail "B: $(cut -c1-100 "$TMP/gh.log" 2>/dev/null)"

echo "pass=$PASS fail=$FAIL"; [ "$FAIL" -eq 0 ]
