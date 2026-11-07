#!/usr/bin/env bash
# Hồi quy (07/11): Board #1 chứa thẻ #91 của repo khác; runner đọc `issue view 91` trong repo mình, trúng PR #91 và dừng rc=79.
# Khi có SB_CARD_HOME_REPO, `super-board-card.sh items` chỉ trả thẻ của repo nhà. gh giả, chạy offline.
# SB_CARD=<file> chạy bản cũ để thấy ĐỎ. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CARD="${SB_CARD:-$ROOT/.claude/bin/super-board-card.sh}"
unset SB_CARD_HOME_REPO SB_CONFIG
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-card-home.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

node() { printf '{"id":"I%s","fieldValueByName":{"name":"Ready"},"content":{"__typename":"Issue","number":%s,"title":"t","url":"u","repository":{"nameWithOwner":"%s"},"labels":{"nodes":[]}}}' "$1" "$1" "$2"; }
draft='{"id":"D1","fieldValueByName":{"name":"Backlog"},"content":{"__typename":"DraftIssue","title":"d"}}'
page() { printf '[{"data":{"repositoryOwner":{"projectV2":{"items":{"totalCount":%s,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[%s]}}}}}]' "$1" "$2"; }
page 3 "$(node 7 Own/Home),$(node 91 Own/Other),$draft" > "$TMP/mixed.json"
page 2 "$(node 7 own/HOME),$(node 8 Own/Home)" > "$TMP/case.json"
page 2 "$(node 91 Own/Other),$(node 19 Own/Third)" > "$TMP/foreign.json"

cat > "$TMP/bin/gh" <<'SH'
#!/bin/sh
cat "$GH_PAGE"
SH
chmod +x "$TMP/bin/gh"

run() {  # $1 = trang gh giả, $2 = SB_CARD_HOME_REPO (rỗng = không đặt); stdout JSON, stderr ở $TMP/err
  (
    [ -z "$2" ] || export SB_CARD_HOME_REPO="$2"
    GH_PAGE="$TMP/$1.json" SB_GITHUB_HALT_FILE="$TMP/halt.json" PATH="$TMP/bin:$PATH" \
      "$CARD" --owner Own --number 1 items 2>"$TMP/err"
  )
}
nums() { jq -c '[.items[] | .content.number // "draft"]'; }
check() { [ "$2" = "$3" ] && ok "$1" || fail "$1: mong $3, được $2"; }

out=$(run mixed Own/Home)
check "lọc thẻ repo khác, giữ draft" "$(printf '%s' "$out" | nums)" '[7,"draft"]'
check "totalCount theo số còn lại" "$(printf '%s' "$out" | jq .totalCount)" 2
check "skippedForeign ghi số thẻ bị lọc" "$(printf '%s' "$out" | jq -c .skippedForeign)" '[91]'

out=$(run case Own/Home)
check "khác hoa thường vẫn là repo nhà" "$(printf '%s' "$out" | nums)" '[7,8]'

for remote in https://github.com/Own/Home https://github.com/Own/Home.git git@github.com:Own/Home.git \
    ssh://git@github.com/Own/Home https://github.com/Own/Home/ https://tok@github.com/Own/Home.git/; do
  out=$(run mixed "$remote")
  check "chuẩn hoá remote $remote" "$(printf '%s' "$out" | nums)" '[7,"draft"]'
done

out=$(run mixed "")
check "không đặt env thì giữ nguyên board" "$(printf '%s' "$out" | nums)" '[7,91,"draft"]'
check "không đặt env thì totalCount giữ nguyên" "$(printf '%s' "$out" | jq .totalCount)" 3

out=$(run foreign Own/Home)
check "board chỉ có thẻ repo khác: vẫn lọc, không đọc lại theo số" "$(printf '%s' "$out" | nums)" '[]'
check "board chỉ có thẻ repo khác: skippedForeign đủ" "$(printf '%s' "$out" | jq -c .skippedForeign)" '[91,19]'
grep -q 'SB_CARD_HOME_REPO' "$TMP/err" && ok "không còn thẻ repo nhà thì cảnh báo stderr" || fail "không còn thẻ repo nhà mà không cảnh báo"

# --config: mọi nơi gọi có config (waiting-on, watchdog) nhận luật lọc mà không truyền env.
printf '{"project":{"owner":"Own","number":1},"repo":{"remote":"https://github.com/Own/Home"}}' > "$TMP/cfg.json"
out=$(GH_PAGE="$TMP/mixed.json" SB_GITHUB_HALT_FILE="$TMP/halt.json" PATH="$TMP/bin:$PATH" "$CARD" --config "$TMP/cfg.json" items 2>/dev/null)
check "--config tự lọc theo repo.remote" "$(printf '%s' "$out" | nums)" '[7,"draft"]'

# fetch_project_items của runner thật: đây là chỗ đọc board trong sự cố rc=79 (super-board-run.sh).
RUNNER="${SB_RUNNER:-$ROOT/.claude/bin/super-board-run.sh}"
fetch() {  # $1 = chuỗi trang gh giả cho từng lần đọc; in "<số thẻ>" mỗi lần, log vào $TMP/log
  rm -f "$TMP/log"
  PAGES="$1" SB_LIB_ONLY=1 SB_GITHUB_HALT_FILE="$TMP/halt.json" PATH="$TMP/bin:$PATH" bash -c '
    R="$1" B="$2" T="$3"; set --
    . "$R" >/dev/null 2>&1
    SB_GITHUB_READ="$B/super-board-github-read.py"; PROJECT_OWNER=Own; PROJECT_NUMBER=1; CONFIG_PATH="$T/cfg.json"; SB_FETCH_RETRY_DELAYS=""
    log() { echo "$*" >> "$T/log"; }
    for p in $PAGES; do
      export GH_PAGE="$T/$p.json"
      fetch_project_items || { echo "rc=$?"; continue; }
      printf "%s\n" "$PROJECT_ITEMS_JSON" | jq -c "[.items[] | .content.number // \"draft\"]"
    done' _ "$RUNNER" "$ROOT/.claude/bin" "$TMP"
}
page 1 "$(node 7 Own/Home)" > "$TMP/home.json"
out=$(fetch "mixed mixed home" | tr '\n' ' ')
check "fetch_project_items bỏ thẻ repo khác" "$out" '[7,"draft"] [7,"draft"] [7] '
check "log thẻ bị lọc một lần, không lặp mỗi tick" "$(grep -c 'skipped' "$TMP/log" 2>/dev/null)" 1
grep -q 'skipped: \[\]' "$TMP/log" && fail "thẻ rời board mà log 'skipped: []'" || ok "thẻ rời board không log danh sách rỗng"

# super-board-status.py gọi gh trực tiếp, không qua card.sh: cũng không được tính thẻ repo khác.
STATUS="${SB_STATUS:-$ROOT/.claude/bin/super-board-status.py}"
mkdir -p "$TMP/st/.claude/super-board/configs" "$TMP/stbin"
printf '{"project":{"owner":"Own","number":1,"title":"t"},"repo":{"remote":"https://github.com/Own/Home"}}' > "$TMP/st/.claude/super-board/configs/s.json"
stnode() { printf '{"content":{"number":%s,"title":"%s","repository":{"nameWithOwner":"%s"},"labels":{"nodes":[]}},"fieldValues":{"nodes":[{"name":"Building","field":{"name":"Status"}}]}}' "$1" "$2" "$3"; }
printf '{"data":{"repositoryOwner":{"projectV2":{"items":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[%s,%s]}}}}}' \
  "$(stnode 7 HOMECARD Own/Home)" "$(stnode 91 FOREIGNCARD Own/Other)" > "$TMP/st.json"
cat > "$TMP/stbin/gh" <<SH
#!/bin/sh
case "\$*" in
  *"repository{nameWithOwner}"*) cat "$TMP/st.json" ;;
  *graphql*) jq 'del(.data.repositoryOwner.projectV2.items.nodes[].content.repository)' "$TMP/st.json" ;;
esac
exit 0
SH
chmod +x "$TMP/stbin/gh"
out=$(cd "$TMP/st" && PATH="$TMP/stbin:$PATH" PYTHONDONTWRITEBYTECODE=1 python3 "$STATUS" s 2>&1)
case "$out" in *HOMECARD*) ok "status vẫn tính thẻ repo nhà" ;; *) fail "status thiếu thẻ repo nhà: $(printf '%s' "$out" | tail -3)" ;; esac
case "$out" in *FOREIGNCARD*) fail "status tính cả thẻ repo khác" ;; *) ok "status bỏ thẻ repo khác" ;; esac
jq '.data.repositoryOwner.projectV2.items.nodes |= map(select(.content.number == 91))' "$TMP/st.json" > "$TMP/st2.json" && mv "$TMP/st2.json" "$TMP/st.json"
out=$(cd "$TMP/st" && PATH="$TMP/stbin:$PATH" PYTHONDONTWRITEBYTECODE=1 python3 "$STATUS" s 2>&1)
case "$out" in *"no card of"*) ok "status cảnh báo khi không còn thẻ repo nhà" ;; *) fail "status lọc hết thẻ mà không cảnh báo" ;; esac

# wave-plan đọc board live khi không có --items: đường đọc của backend workflow.
WAVE="${SB_WAVE:-$ROOT/.claude/bin/super-board-wave-plan.sh}"
printf '{"project":{"owner":"Own","number":1},"repo":{"path":".","remote":"https://github.com/Own/Home"},"verify_commands":["bash tests/check.sh"]}' > "$TMP/wavecfg.json"
printf '[]' > "$TMP/queued.json"
printf '{"7":{"runnable":true,"parseable":true,"blockers":[]},"91":{"runnable":true,"parseable":true,"blockers":[]}}' > "$TMP/deps.json"
out=$(cd "$ROOT" && GH_PAGE="$TMP/mixed.json" SB_GITHUB_HALT_FILE="$TMP/halt.json" PATH="$TMP/bin:$PATH" \
  bash "$WAVE" --config "$TMP/wavecfg.json" --deps "$TMP/deps.json" --queued "$TMP/queued.json" 2>"$TMP/wave.err" | jq -c '[.cards[].number]')
check "wave-plan chỉ xếp thẻ repo nhà" "$out" '[7]'

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "FAIL ($FAILS)"; exit 1
