#!/usr/bin/env bash
# Test #536: helper `.claude/bin/super-board-queue-label.sh <pr> [--repo R] [--check]` — nhãn merge-queue chỉ gắn khi PR có
# `approved-head:<sha40>` hợp lệ (luật chung super-board-approved-head.jq: OWNER/MEMBER/COLLABORATOR, comment mới nhất thắng,
# bare chỉ của OWNER, approved-by đủ trường + audit pass) khớp headRefOid hiện tại.
#  h1 không có duyệt → exit 3, lý do nêu PR, head, "approved-head: không có", bước đúng; không gắn nhãn
#  h2 OWNER bare khớp head → exit 0 và `gh pr edit 5 --add-label merge-queue`
#  h3 --check → exit 0, không ghi gì
#  h4 approved-head của head cũ → exit 3 nêu cả hai sha
#  h5 approved-head của CONTRIBUTOR/NONE → không tính (exit 3)
#  h6 MEMBER + approved-by: audit-check pass → 0, fail → 3
#  h7 đọc GitHub hỏng → exit 69, không gắn nhãn; gắn nhãn hỏng → 69
#  h6d nguồn approved-by: repo của PR (url) phải là origin của repo chứa biên bản
#  h8 --repo truyền cho cả đọc lẫn ghi; h9 không có PR → PR của nhánh hiện tại; h9b sai cách gọi → 64
# Helper + jq THẬT của checkout chứa test (ROOT từ $0), chép vào thư mục tạm cạnh audit-check giả. gh giả. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-queue-label.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Helper nằm trong một repo git tạm có origin acme/widgets (repo của biên bản audit); PR_JSON.url quyết định repo của PR.
git init -q "$TMP/repo" && git -C "$TMP/repo" remote add origin https://github.com/acme/widgets.git
mkdir -p "$TMP/repo/.claude/bin" "$TMP/path"; ln -s "$TMP/repo/.claude/bin" "$TMP/bin"
cp "$ROOT/.claude/bin/super-board-queue-label.sh" "$ROOT/.claude/bin/super-board-approved-head.jq" "$TMP/bin/" 2>/dev/null \
  || { echo "✖ helper or jq missing under $ROOT/.claude/bin"; exit 1; }
# audit-check giả: ghi argv, exit theo $AUDIT_RC
cat > "$TMP/bin/super-board-audit-check.py" <<'PY'
import os, sys, time
import json  # module thuần Python: h12 che nó bằng json.py chưa track cạnh audit-check
open(os.environ["AUDIT_LOG"], "a").write(" ".join(sys.argv[1:]) + "\n")
time.sleep(float(os.environ.get("AUDIT_SLEEP", "0")))
sys.exit(int(os.environ.get("AUDIT_RC", "0")))
PY
# gh giả: pr view → $PR_JSON (VIEW_RC khác 0 thì hỏng); pr edit → ghi log, EDIT_RC
cat > "$TMP/path/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "pr view") [ "${VIEW_RC:-0}" = 0 ] || { echo "HTTP 502: Bad Gateway" >&2; exit 1; }; printf '%s\n' "$PR_JSON" ;;
  "pr edit") exit "${EDIT_RC:-0}" ;;
esac
SH
chmod +x "$TMP/path/gh" "$TMP/bin/super-board-queue-label.sh"
export PATH="$TMP/path:$PATH" GH_LOG="$TMP/gh.log" AUDIT_LOG="$TMP/audit.log"
HEAD=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222
BY='{"reviewer":"antigravity","builder":"claude-builder","task_id":"T0001-x","gate_receipt":"r1"}'
pr() {   # pr <comments JSON array> [state] [repo của url]
  PR_JSON=$(jq -nc --arg h "$HEAD" --argjson c "$1" --arg s "${2:-OPEN}" --arg r "${3:-acme/widgets}" \
    '{number: 5, state: $s, url: "https://github.com/\($r)/pull/5", headRefOid: $h, comments: $c}'); export PR_JSON
}
cmt() { jq -nc --arg a "$1" --arg b "$2" '{author: {login: "u"}, authorAssociation: $a, body: $b}'; }
run() { rm -f "$TMP/gh.log" "$TMP/audit.log"; ( cd "$TMP/repo" && bash "$TMP/repo/.claude/bin/super-board-queue-label.sh" "$@" ) > "$TMP/out" 2> "$TMP/err"; RC=$?; }
edited() { grep -q '^pr edit' "$TMP/gh.log" 2>/dev/null; }
reset() { export VIEW_RC=0 EDIT_RC=0 AUDIT_RC=0; }

reset; pr '[]'; run 5
{ [ "$RC" = 3 ] && ! edited && grep -q 'PR #5' "$TMP/err" && grep -q '1111111' "$TMP/err" && grep -qi 'approved-head: không có' "$TMP/err" \
  && grep -qi 'Review' "$TMP/err"; } && ok "h1 no approval → exit 3 with PR, head, missing approval and the right step; no label" \
  || fail "h1 rc=$RC edited=$(edited && echo y || echo n) err=$(head -c 300 "$TMP/err")"

reset; pr "[$(cmt OWNER "approved-head:$HEAD")]"; run 5
{ [ "$RC" = 0 ] && grep -q '^pr edit 5 --add-label merge-queue' "$TMP/gh.log"; } && ok "h2 OWNER bare approved-head at head → labelled" \
  || fail "h2 rc=$RC gh=$(tr '\n' '|' < "$TMP/gh.log") err=$(head -c 200 "$TMP/err")"

reset; pr "[$(cmt OWNER "approved-head:$HEAD")]"; run --check 5
{ [ "$RC" = 0 ] && ! edited; } && ok "h3 --check → exit 0, nothing written" || fail "h3 rc=$RC edited=$(edited && echo y || echo n)"

reset; pr "[$(cmt OWNER "approved-head:$OLD")]"; run 5
{ [ "$RC" = 3 ] && ! edited && grep -q '2222222' "$TMP/err" && grep -q '1111111' "$TMP/err"; } \
  && ok "h4 approved-head of an older head → exit 3 naming both shas" || fail "h4 rc=$RC err=$(head -c 300 "$TMP/err")"
! grep -q "$OLD" "$TMP/err" && ok "h4b the seen approval is shown as sha7, not the full sha" || fail "h4b full approved sha printed: $(head -c 300 "$TMP/err")"
reset; pr "[$(cmt OWNER "approved-head:$HEAD")]" MERGED; run 5
{ [ "$RC" = 3 ] && ! edited && grep -q 'MERGED' "$TMP/err"; } && ok "h4c merged PR with a matching approval → exit 3 (only open PRs queue)" || fail "h4c rc=$RC err=$(head -c 200 "$TMP/err")"

reset; pr "[$(cmt CONTRIBUTOR "approved-head:$HEAD"),$(cmt NONE "approved-head:$HEAD")]"; run 5
{ [ "$RC" = 3 ] && ! edited; } && ok "h5 approved-head from CONTRIBUTOR/NONE is not counted" || fail "h5 rc=$RC edited=$(edited && echo y || echo n)"

reset; pr "[$(cmt MEMBER "approved-head:$HEAD
approved-by: $BY")]"; run 5
{ [ "$RC" = 0 ] && edited && grep -q -- "--pr 5 T0001-x $HEAD" "$TMP/audit.log"; } && ok "h6 MEMBER approved-by + audit pass → labelled (audit-check called with --pr, task, head)" \
  || fail "h6 rc=$RC audit=$(cat "$TMP/audit.log" 2>/dev/null) err=$(head -c 200 "$TMP/err")"
reset; export AUDIT_RC=1; run 5
{ [ "$RC" = 3 ] && ! edited; } && ok "h6b approved-by whose audit does not match → exit 3" || fail "h6b rc=$RC"
reset; pr "[$(cmt MEMBER "approved-head:$HEAD")]"; run 5
{ [ "$RC" = 3 ] && ! edited; } && ok "h6c bare approved-head from a MEMBER (not OWNER) → exit 3" || fail "h6c rc=$RC"
reset; pr "[$(cmt MEMBER "approved-head:$HEAD
approved-by: $BY")]" OPEN other/repo; run https://github.com/other/repo/pull/5
{ [ "$RC" = 3 ] && ! edited && [ ! -s "$TMP/audit.log" ] && grep -q 'other/repo' "$TMP/err"; } \
  && ok "h6d approved-by audited in acme/widgets does not count for a PR of other/repo (selected by URL, no --repo)" || fail "h6d rc=$RC err=$(head -c 200 "$TMP/err")"

reset; export VIEW_RC=1; pr "[$(cmt OWNER "approved-head:$HEAD")]"; run 5
{ [ "$RC" = 69 ] && ! edited; } && ok "h7 GitHub read fails → exit 69, no label" || fail "h7 rc=$RC"
reset; export EDIT_RC=1; run 5
[ "$RC" = 69 ] && ok "h7b label write fails → exit 69" || fail "h7b rc=$RC"

reset; run 5 --repo acme/widgets
{ [ "$RC" = 0 ] && grep -q '^pr view 5 --repo acme/widgets' "$TMP/gh.log" && grep -q '^pr edit 5 --repo acme/widgets --add-label merge-queue' "$TMP/gh.log"; } \
  && ok "h8 --repo passed to the read and the write" || fail "h8 rc=$RC gh=$(tr '\n' '|' < "$TMP/gh.log")"

reset; pr "[$(cmt OWNER "approved-head:$HEAD")]"; run --check
{ [ "$RC" = 0 ] && grep -q '^pr view --json number,state,url,headRefOid,comments' "$TMP/gh.log"; } \
  && ok "h9 no PR selector → the PR of the current branch (gh pr view without a selector)" || fail "h9 rc=$RC gh=$(tr '\n' '|' < "$TMP/gh.log")"
reset; run 5 --bogus; [ "$RC" = 64 ] && ok "h9b unknown option → exit 64" || fail "h9b rc=$RC"
# OCR #826: thời hạn 0 s (communicate(timeout=0) hết giờ ngay) làm mọi lần gắn nhãn exit 69 → coi là giá trị sai, dùng mặc định 6 s
reset; pr "[$(cmt OWNER "approved-head:$HEAD")]"; SB_QUEUE_LABEL_GH_TIMEOUT=0 run --check 5
[ "$RC" = 0 ] && ok "h10 SB_QUEUE_LABEL_GH_TIMEOUT=0 → default timeout, valid approval passes" || fail "h10 rc=$RC err=$(head -c 200 "$TMP/err")"
# OCR final: audit-check hết giờ (fetch refs/pull chậm) là "không kiểm được" (69), không phải "chưa duyệt" (3, bảo quay về lane Review)
reset; pr "[$(cmt MEMBER "approved-head:$HEAD
approved-by: $BY")]"; AUDIT_SLEEP=3 SB_QUEUE_LABEL_GH_TIMEOUT=1 run 5
{ [ "$RC" = 69 ] && ! edited; } && ok "h11 audit-check timeout → exit 69 (unknown), not 3 (not approved)" || fail "h11 rc=$RC err=$(head -c 200 "$TMP/err")"
# review #826 P2: audit-check chạy với python3 -I — file chưa track cạnh nó (json.py) không được che module stdlib để đổi verdict
printf 'raise SystemExit(0)\n' > "$TMP/bin/json.py"
reset; export AUDIT_RC=1; pr "[$(cmt MEMBER "approved-head:$HEAD
approved-by: $BY")]"; run 5
{ [ "$RC" = 3 ] && ! edited; } && ok "h12 untracked json.py next to audit-check does not turn a failed audit into a pass" || fail "h12 rc=$RC edited=$(edited && echo y || echo n)"
rm -f "$TMP/bin/json.py"

[ "$FAILS" -eq 0 ] && echo "PASS test_queue_label" || { echo "FAIL test_queue_label ($FAILS)"; exit 1; }
