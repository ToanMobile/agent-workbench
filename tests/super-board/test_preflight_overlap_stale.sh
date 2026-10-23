#!/usr/bin/env bash
# Test hồi quy #280 (23/10 04:52): preflight câu 3 (chồng file) chuyển #237 sang Blocked với blocked-by 137, 188, 190, 232, 233
# (thẻ nằm Backlog, không bao giờ đóng khi backlog_pull tắt) dù #237 đã có PR riêng #244 (bị review trả về build lại). Luật:
#  A  PR mở đóng một thẻ KHÔNG đang chạy (Backlog/Blocked/không trên board, theo --inflight) chạm cùng file -> không chặn (blockedBy rỗng).
#  B  PR mở đóng một thẻ đang Building (có trong --inflight) chạm cùng file -> vẫn sequence sau thẻ đó.
#  C  Thẻ đã có PR mở của chính nó (nhánh issue-<n>-*) -> không sequence, dù PR khác đang Building chạm cùng file.
#  D  Không truyền --inflight -> hành vi cũ: PR nào đóng issue nào chạm cùng file cũng chặn.
# gh giả, chạy offline. Tương thích bash 3.2.
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

# A: PR #50 đóng #901, #901 không trong inflight (nằm Backlog).
run "[$(pr 50 issue-901-x 901)]" '[{"number":900,"title":"runner worker exit diagnostics","status":"Ready"}]'
[ "$(blocked)" = "[]" ] && ok "A: an open PR of a Backlog card does not block (blockedBy empty)" \
  || fail "A: blockedBy=$(blocked) err=$(tail -1 "$TMP/err")"

# B: #901 đang Building -> vẫn chặn.
run "[$(pr 50 issue-901-x 901)]" '[{"number":900,"title":"runner worker exit diagnostics","status":"Ready"},{"number":901,"title":"other","status":"Building"}]'
[ "$(blocked)" = "[901]" ] && ok "B: an open PR of a Building card still sequences the card" \
  || fail "B: blockedBy=$(blocked), want [901]"

# C: thẻ đã có PR riêng #60 (issue-900-*); #901 đang Building chạm cùng file -> không sequence.
run "[$(pr 60 issue-900-own 900),$(pr 50 issue-901-x 901)]" '[{"number":900,"title":"runner worker exit diagnostics","status":"Ready"},{"number":901,"title":"other","status":"Building"}]'
v=$(jq -r '.["900"].verdict' "$TMP/out.json" 2>/dev/null)
[ "$v" = proceed ] && [ "$(blocked)" = "[]" ] && ok "C: a card that already has its own PR is not sequenced again" \
  || fail "C: verdict=$v blockedBy=$(blocked), want proceed / []"

# D: không --inflight -> hành vi cũ.
run "[$(pr 50 issue-901-x 901)]" ""
[ "$(blocked)" = "[901]" ] && ok "D: without --inflight every overlapping PR still sequences (old behaviour)" \
  || fail "D: blockedBy=$(blocked), want [901]"

# E: --inflight là [] (board không có thẻ đang chạy nào, hoặc runner lọc hỏng) -> vẫn là "có --inflight": PR không chặn.
run "[$(pr 50 issue-901-x 901)]" '[]'
[ "$(blocked)" = "[]" ] && ok "E: an empty --inflight list still means no PR of a non-running card blocks" \
  || fail "E: blockedBy=$(blocked), want []"

# F: thẻ #901 nằm Blocked trong inflight -> không phải thẻ đang chạy.
run "[$(pr 50 issue-901-x 901)]" '[{"number":901,"title":"other","status":"Blocked"}]'
[ "$(blocked)" = "[]" ] && ok "F: a Blocked card in --inflight does not block" || fail "F: blockedBy=$(blocked), want []"

# G: một PR đóng #901 (Building) và #902 (Backlog) -> chỉ #901 chặn.
jq -n '[{number:50,title:"unrelated change 50",body:"Closes #901\nCloses #902",url:"u",headRefName:"issue-901-x",files:[{path:".claude/bin/super-board-run.sh"}]}]' > "$TMP/g.json"
run "$(cat "$TMP/g.json")" '[{"number":901,"title":"other","status":"Building"}]'
[ "$(blocked)" = "[901]" ] && ok "G: only the running card among a PR's closed issues blocks" || fail "G: blockedBy=$(blocked), want [901]"

# H: kiểm cùng lô #899 và #900 cùng tên file; #900 đã có PR riêng -> #900 không bị sequence sau #899.
jq -n --arg b "$body" '{number:899,title:"alpha cache warm start",body:$b}' > "$TMP/issue-899.json"
# PR riêng của #900 chạm file KHÁC, để #899 không bị sequence sau nó và luật peer là thứ duy nhất có thể chặn #900.
jq -n '[{number:60,title:"own change 60",body:"Closes #900",url:"u",headRefName:"issue-900-own",files:[{path:"docs/other.md"}]}]' > "$TMP/open.json"
printf '%s' '[{"number":899,"title":"alpha cache warm start","status":"Ready"},{"number":900,"title":"runner worker exit diagnostics","status":"Ready"}]' > "$TMP/inflight.json"
SB_OPEN="$TMP/open.json" bash "$PREFLIGHT" --repo o/r --issues 899,900 --inflight "$TMP/inflight.json" > "$TMP/out.json" 2> "$TMP/err"
v=$(jq -r '.["900"].verdict' "$TMP/out.json" 2>/dev/null)
[ "$v" = proceed ] && ok "H: a card with its own PR is not sequenced behind a lower-numbered peer" \
  || fail "H: verdict=$v blockedBy=$(blocked), want proceed"

[ "$FAILS" -eq 0 ] && echo "✅ test_preflight_overlap_stale: all passed" || { echo "❌ $FAILS failed"; exit 1; }
