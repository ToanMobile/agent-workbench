#!/usr/bin/env bash
# Test hồi quy (16/11, #1201 nằm Ready 15 giờ): preflight câu 3 với --inflight chỉ chờ PR đóng thẻ đang chạy; PR không đóng
# thẻ nào đang chạy (PR tay không "Closes", PR của thẻ Backlog/Blocked) không có ai để chờ nên không giữ thẻ (verdict proceed,
# không phải "sequence" blockedBy rỗng mà không gì thả ra). gh giả, chạy offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PREFLIGHT="${SB_PREFLIGHT:-$ROOT/.claude/bin/super-board-preflight.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-preflight-stale.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
# gh giả: PR mở đọc từ $SB_OPEN; merged/closed rỗng; `issue view` đọc $TMP/issue-<n>.json.
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" api rate_limit "*) echo '{"resources":{"graphql":{"remaining":5000,"reset":0},"core":{"remaining":5000,"reset":0}}}' ;;
  *" pr list "*"--state open"*) cat "$SB_OPEN" ;;
  *" pr list "*|*" issue list "*) echo '[]' ;;
  *" issue view "*)
    n=""; prev=""
    for a in "$@"; do [ "$prev" = view ] && n="$a"; prev="$a"; done
    cat "$SB_DIR/issue-$n.json" ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_DIR="$TMP" \
  SB_GH_GUARD_STATE_FILE="$TMP/budget"

body=$'## Problem\nrunner chết\n\n## Context\n- **Where:** `.claude/bin/super-board-run.sh`\n\n## Fix\nsửa\n\n## Acceptance Criteria\n- [ ] test đỏ rồi xanh\n'
jq -n --arg b "$body" '{number:900,title:"runner worker exit diagnostics",body:$b}' > "$TMP/issue-900.json"
# pr <number> <branch> <closes-issue> -> một PR mở chạm .claude/bin/super-board-run.sh
pr() { jq -n --argjson n "$1" --arg h "$2" --arg c "$3" \
  '{number:$n,title:"unrelated change \($n)",body:"Closes #\($c)",url:"u",headRefName:$h,files:[{path:".claude/bin/super-board-run.sh"}]}'; }
run() {  # $1 = open PRs json array, $2 = inflight json or "" -> verdict of #900 in $TMP/out.json
  printf '%s' "$1" > "$TMP/open.json"
  if [ -n "$2" ]; then printf '%s' "$2" > "$TMP/inflight.json"
    SB_OPEN="$TMP/open.json" bash "$PREFLIGHT" --repo o/r --issues 900 --inflight "$TMP/inflight.json" > "$TMP/out.json" 2> "$TMP/err"
  else SB_OPEN="$TMP/open.json" bash "$PREFLIGHT" --repo o/r --issues 900 > "$TMP/out.json" 2> "$TMP/err"; fi
}
blocked() { jq -c '.["900"].blockedBy // []' "$TMP/out.json" 2>/dev/null; }

ago() { python3 -c 'import sys,datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(days=float(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
prd() { jq -n --argjson n "$1" --argjson d "$2" --arg u "$(ago "$3")" \
  '{number:$n,title:"unrelated change \($n)",body:"Closes #901",url:"u",headRefName:"issue-901-x",isDraft:$d,updatedAt:$u,files:[{path:".claude/bin/super-board-run.sh"}]}'; }
INF='[{"number":900,"title":"runner worker exit diagnostics","status":"Ready"},{"number":901,"title":"other","status":"Building"}]'
# K (16/11, #1201 stuck in Ready for 15 h): with --inflight a PR that closes no running card (hand PR with no "Closes", or
# a card in Backlog/Blocked) can never be waited on, so it must not hold the card: verdict proceed, not an empty-blockedBy
# "sequence" that nothing ever releases. A PR that closes a Building card still sequences (B, G).
verdict() { jq -r '.["900"].verdict' "$TMP/out.json" 2>/dev/null; }
jq -n '[{number:90,title:"hand kit change 90",body:"no card ref",url:"u",headRefName:"fix-kit",isDraft:false,files:[{path:".claude/bin/super-board-run.sh"}]}]' > "$TMP/k.json"
run "$(cat "$TMP/k.json")" "$INF"
[ "$(verdict)" = proceed ] && ok "K: a card-less non-draft PR on the same file does not hold the card" || fail "K: verdict=$(verdict), want proceed"
run "[$(pr 50 issue-902-x 902)]" "$INF"
[ "$(verdict)" = proceed ] && ok "K2: a PR of a non-running card does not hold the card" || fail "K2: verdict=$(verdict), want proceed"
run "[$(prd 84 false 1)]" "$INF"
[ "$(verdict)" = sequence ] && ok "K3: a PR of a Building card still holds the card" || fail "K3: verdict=$(verdict), want sequence"
run "$(cat "$TMP/k.json")" ""
[ "$(verdict)" = sequence ] && ok "K4: without --inflight a card-less PR still sequences (old behaviour)" || fail "K4: verdict=$(verdict), want sequence"

[ "$FAILS" -eq 0 ] && echo "✅ test_preflight_overlap_cardless: all passed" || { echo "❌ $FAILS failed"; exit 1; }
