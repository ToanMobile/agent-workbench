#!/usr/bin/env bash
# Hai thẻ chưa chạy cùng file thì gộp (verdict merge), không sequence.
# Thẻ đã có PR mở head issue-<n>- thì thẻ kia sequence. File chỉ nằm ở ma trận hồi quy không tính là chồng.
# gh giả, offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PREFLIGHT="$ROOT/.claude/bin/super-board-preflight.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-preflight-merge.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/syn"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" api rate_limit "*) echo '{"resources":{"graphql":{"remaining":5000,"reset":0},"core":{"remaining":5000,"reset":0}}}' ;;
  *" api graphql "*) exit 1 ;;
  *" pr list "*)
    if [ -n "${SB_OPEN_PRS:-}" ]; then cat "$SB_OPEN_PRS"; else echo '[]'; fi ;;
  *" issue list "*) echo '[]' ;;
  *" issue view "*)
    n=""; prev=""
    for a in "$@"; do [ "$prev" = view ] && n="$a"; prev="$a"; done
    cat "$SB_SYN/$n.json" ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
body() {
  jq -n --argjson n "$1" --arg t "$2" --arg b "$3" \
    '{number:$n,title:$t,body:$b,labels:[{name:"bug"}],state:"OPEN"}' > "$TMP/syn/$1.json"
}
AC=$'## Acceptance Criteria\n- [ ] test đỏ rồi xanh\n'
body 801 "fix alpha parser crash" "## Problem"$'\n'"x"$'\n\n'"## Context"$'\n'"- **Where:** \`src/core/parser.ts\`"$'\n\n'"## Fix"$'\n'"sửa"$'\n\n'"$AC"
body 802 "tune beta renderer timeout" "## Problem"$'\n'"y"$'\n\n'"## Context"$'\n'"- **Where:** \`src/core/parser.ts\`"$'\n\n'"## Fix"$'\n'"sửa"$'\n\n'"$AC"
body 810 "fold gamma parser too" "## Problem"$'\n'"g"$'\n\n'"## Context"$'\n'"- **Where:** \`src/core/parser.ts\`"$'\n\n'"## Fix"$'\n'"sửa"$'\n\n'"$AC"
body 811 "only the shared matrix" "## Problem"$'\n'"m"$'\n\n'"## Context"$'\n'"- **Where:** \`.agents/regression_matrix.active.json\`"$'\n\n'"## Fix"$'\n'"sửa"$'\n\n'"$AC"
body 812 "matrix plus its own file" "## Problem"$'\n'"m"$'\n\n'"## Context"$'\n'"- **Where:** \`.agents/regression_matrix.active.json\`"$'\n'"- **Where:** \`src/only/mine.ts\`"$'\n\n'"## Fix"$'\n'"sửa"$'\n\n'"$AC"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 \
  SB_SYN="$TMP/syn" SB_GH_GUARD_STATE_FILE="$TMP/budget"

run_pf() {
  bash "$PREFLIGHT" --repo ToanMobile/Synthetic --issues "$1" >"$TMP/out.json" 2>"$TMP/err" || {
    fail "preflight $1 exit $? ($(tail -1 "$TMP/err"))"
    return 1
  }
}

# Không PR: 801 giữ proceed và nhận 802; 802 là merge vào 801, blockedBy rỗng.
unset SB_OPEN_PRS
run_pf 801,802 || true
if [ "$(jq -r '.["801"].verdict' "$TMP/out.json" 2>/dev/null)" = proceed ] \
   && jq -e '.["801"].absorb == [802]' "$TMP/out.json" >/dev/null 2>&1 \
   && [ "$(jq -r '.["802"].verdict' "$TMP/out.json" 2>/dev/null)" = merge ] \
   && [ "$(jq -r '.["802"].mergeInto' "$TMP/out.json" 2>/dev/null)" = 801 ] \
   && jq -e '.["802"].blockedBy == []' "$TMP/out.json" >/dev/null 2>&1; then
  ok "801/802 chưa chạy, cùng parser.ts: 801 absorb 802, 802 merge vào 801"
else
  fail "801/802: $(jq -c '[.["801"]|{verdict,absorb},.["802"]|{verdict,mergeInto,blockedBy}]' "$TMP/out.json" 2>/dev/null)"
fi

# Ba thẻ cùng file: cả hai số lớn gộp vào số nhỏ nhất.
run_pf 801,802,810 || true
if jq -e '.["801"].verdict == "proceed" and (.["801"].absorb | sort) == [802,810]
          and .["802"].verdict == "merge" and .["802"].mergeInto == 801
          and .["810"].verdict == "merge" and .["810"].mergeInto == 801' "$TMP/out.json" >/dev/null 2>&1; then
  ok "ba thẻ cùng file: 802 và 810 merge vào 801"
else
  fail "ba thẻ: $(jq -c '[.["801"]|{verdict,absorb},.["802"]|{verdict,mergeInto},.["810"]|{verdict,mergeInto}]' "$TMP/out.json" 2>/dev/null)"
fi

# 801 đã có PR của chính nó (file PR không đụng parser.ts): 802 sequence, không merge.
printf '%s\n' '[{"number":50,"title":"wip","body":"","url":"u","headRefName":"issue-801-wip","files":[{"path":"src/other/note.ts"}],"isDraft":false,"updatedAt":"2026-10-29T00:00:00Z"}]' > "$TMP/prs.json"
export SB_OPEN_PRS="$TMP/prs.json"
run_pf 801,802 || true
if [ "$(jq -r '.["801"].verdict' "$TMP/out.json" 2>/dev/null)" = proceed ] \
   && [ "$(jq -r '.["802"].verdict' "$TMP/out.json" 2>/dev/null)" = sequence ] \
   && [ "$(jq -r '.["802"].mergeInto // empty' "$TMP/out.json" 2>/dev/null)" = "" ] \
   && jq -e '.["802"].blockedBy == [801]' "$TMP/out.json" >/dev/null 2>&1; then
  ok "801 đã có PR issue-801-*: 802 sequence, không merge"
else
  fail "801 có PR: $(jq -c '[.["801"].verdict,.["802"]|{verdict,mergeInto,blockedBy}]' "$TMP/out.json" 2>/dev/null)"
fi

# Chỉ chung file ma trận: cả hai proceed.
unset SB_OPEN_PRS
run_pf 811,812 || true
if [ "$(jq -r '.["811"].verdict' "$TMP/out.json" 2>/dev/null)" = proceed ] \
   && [ "$(jq -r '.["812"].verdict' "$TMP/out.json" 2>/dev/null)" = proceed ]; then
  ok "chỉ chung regression_matrix: cả hai proceed"
else
  fail "ma trận: $(jq -c '[.["811"].verdict,.["812"].verdict]' "$TMP/out.json" 2>/dev/null)"
fi

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
