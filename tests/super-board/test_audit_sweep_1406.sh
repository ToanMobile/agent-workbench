#!/usr/bin/env bash
# Test hồi quy #1406 (Oracle 1 & Oracle 2):
#  1. Sweep mở lại thẻ đóng COMPLETED còn AC `- [ ]` chưa tick và không có PR merged liên kết (+ nhãn ac-open, comment, Done -> Ready).
#     Không mở lại thẻ NOT_PLANNED, thẻ có PR merged liên kết, thẻ đã tick hết `- [x]`, hay `- [ ]` nằm trong code fence.
#  2. PR merged vào base trong 7 ngày không có biên nhận merge gate -> ghi cảnh báo một lần lên thẻ liên kết (chạy lại không lặp)
#     và đếm theo ngày vào báo cáo; PR có biên nhận hoặc > 7 ngày không bị tính.
#  3. Nối dây trong super-board-run.sh (sweep_audit sau sweep_closed_cards) và BIN của super-board-setup.py.
# Offline; gh và git giả. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SWEEP="$ROOT/.claude/bin/super-board-audit-sweep.py"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
SETUP="$ROOT/.claude/bin/super-board-setup.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

T="$(mktemp -d "${TMPDIR:-/tmp}/sb-audit-sweep-1406.XXXXXX")"
trap 'rm -rf "$T"' EXIT

if [ ! -f "$SWEEP" ]; then
  echo "✖ RED: $SWEEP chưa tồn tại"
  exit 1
fi

# Repo git giả với common dir chứa postfix-gate/merge_receipts
R="$T/repo"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid
git -C "$R" config user.name t
echo init > "$R/README.md"
git -C "$R" add README.md
git -C "$R" commit -qm init
COMMON="$(cd "$R" && git rev-parse --path-format=absolute --git-common-dir)"
RECEIPTS="$COMMON/postfix-gate/merge_receipts"
mkdir -p "$RECEIPTS"

cat > "$T/cfg.json" <<JSON
{
  "project": {"owner": "o", "number": 1, "title": "Test"},
  "repo": {"path": "$R", "remote": "https://github.com/o/r"},
  "base_branch": "main",
  "timezone": "Asia/Ho_Chi_Minh"
}
JSON

NOW_ISO="$(python3 -c 'import datetime as dt; print((dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=3)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
OLD_ISO="$(python3 -c 'import datetime as dt; print((dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=10)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
TODAY_VN="$(python3 -c 'import datetime as dt, zoneinfo; t = dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=3); print(t.astimezone(zoneinfo.ZoneInfo("Asia/Ho_Chi_Minh")).strftime("%Y-%m-%d"))')"

H201="1111111111111111111111111111111111111111"
H202="2222222222222222222222222222222222222222"
H203="3333333333333333333333333333333333333333"
H103="4444444444444444444444444444444444444444"

# PR #202 có biên nhận hợp lệ; PR #201 không có; PR #203 quá 7 ngày
printf '{"pr":202,"head":"%s","base":"main","verified_tree":"%s","squash":"%s","time":1}\n' "$H202" "$H202" "$H202" > "$RECEIPTS/202-$H202.json"

cat > "$T/items.json" <<JSON
{
  "items": [
    {"id": "I101", "status": "Done", "labels": ["bug"], "content": {"type": "Issue", "number": 101}},
    {"id": "I102", "status": "Done", "labels": ["bug"], "content": {"type": "Issue", "number": 102}},
    {"id": "I103", "status": "Done", "labels": ["bug"], "content": {"type": "Issue", "number": 103}},
    {"id": "I104", "status": "Done", "labels": ["bug"], "content": {"type": "Issue", "number": 104}},
    {"id": "I105", "status": "Done", "labels": ["bug"], "content": {"type": "Issue", "number": 105}},
    {"id": "I106", "status": "Done", "labels": ["bug"], "content": {"type": "Issue", "number": 106}}
  ],
  "totalCount": 6
}
JSON

cat > "$T/closed_issues.json" <<JSON
[
  {"number": 101, "title": "t101", "stateReason": "COMPLETED", "labels": [], "closedAt": "$NOW_ISO", "closedByPullRequestsReferences": [],
   "body": "## Acceptance Criteria\n- [ ] AC1 chưa chứng minh\n- [x] AC2 đã xong\n"},
  {"number": 102, "title": "t102", "stateReason": "NOT_PLANNED", "labels": [], "closedAt": "$NOW_ISO", "closedByPullRequestsReferences": [],
   "body": "## Acceptance Criteria\n- [ ] AC1 tách sang thẻ con #200\n"},
  {"number": 103, "title": "t103", "stateReason": "COMPLETED", "labels": [], "closedAt": "$NOW_ISO", "closedByPullRequestsReferences": [{"number": 501}],
   "body": "## Acceptance Criteria\n- [ ] AC1 trong issue body\n"},
  {"number": 104, "title": "t104", "stateReason": "COMPLETED", "labels": [], "closedAt": "$NOW_ISO", "closedByPullRequestsReferences": [],
   "body": "## Acceptance Criteria\n- [x] AC1 đã tick đủ\n"},
  {"number": 105, "title": "t105", "stateReason": "COMPLETED", "labels": [], "closedAt": "$NOW_ISO", "closedByPullRequestsReferences": [],
   "body": "## Acceptance Criteria\n\`\`\`markdown\n- [ ] mẫu trong code block\n\`\`\`\n- [x] AC thật đã tick\n"},
  {"number": 106, "title": "t106", "stateReason": "COMPLETED", "labels": [], "closedAt": "$NOW_ISO", "closedByPullRequestsReferences": [{"number": 201}],
   "body": "## Acceptance Criteria\n- [ ] AC1 qua PR 201\n"}
]
JSON

cat > "$T/merged_prs.json" <<JSON
[
  {"number": 201, "title": "manual merge", "headRefName": "issue-106-fix", "headRefOid": "$H201", "baseRefName": "main", "mergeCommit": {"oid": "$H201"}, "mergedAt": "$NOW_ISO", "closingIssuesReferences": [{"number": 106}], "url": "https://github.com/o/r/pull/201"},
  {"number": 202, "title": "gated merge", "headRefName": "issue-107-ok", "headRefOid": "$H202", "baseRefName": "main", "mergeCommit": {"oid": "$H202"}, "mergedAt": "$NOW_ISO", "closingIssuesReferences": [{"number": 107}], "url": "https://github.com/o/r/pull/202"},
  {"number": 203, "title": "old merge", "headRefName": "issue-108-old", "headRefOid": "$H203", "baseRefName": "main", "mergeCommit": {"oid": "$H203"}, "mergedAt": "$OLD_ISO", "closingIssuesReferences": [{"number": 108}], "url": "https://github.com/o/r/pull/203"},
  {"number": 501, "title": "linked pr", "headRefName": "issue-103-x", "headRefOid": "$H103", "baseRefName": "main", "mergeCommit": {"oid": "$H103"}, "mergedAt": "$NOW_ISO", "closingIssuesReferences": [{"number": 103}], "url": "https://github.com/o/r/pull/501"}
]
JSON
# PR #501 cũng có biên nhận để không làm nhiễu số đếm PR ngoài gate
printf '{"pr":501,"head":"%s","base":"main","verified_tree":"%s","squash":"%s","time":1}\n' "$H103" "$H103" "$H103" > "$RECEIPTS/501-$H103.json"

: > "$T/calls.log"
: > "$T/comments_106.json"
printf '[]' > "$T/comments_106.json"

cat > "$T/gh" <<'SH'
#!/usr/bin/env bash
set -u
echo "gh $*" >> "$FAKE_DIR/calls.log"
case "$*" in
  *"issue list"*"--state closed"*)
    cat "$FAKE_DIR/closed_issues.json"
    ;;
  *"pr list"*"--state merged"*"head:issue-"*)
    echo '[]'
    ;;
  *"pr list"*"--state merged"*)
    cat "$FAKE_DIR/merged_prs.json"
    ;;
  *"api graphql"*)
    if [ "${GQL_ERRORS:-0}" = "1" ]; then
      echo '{"data":null,"errors":[{"message":"bad token"}]}'
    else
      cat "$FAKE_DIR/gql_items.json"
    fi
    ;;
  *"api "*"/issues/106/comments"*)
    printf '[%s]\n' "$(cat "$FAKE_DIR/comments_106.json")"
    ;;
  *"api "*"/issues/"*"/comments"*)
    echo '[[]]'
    ;;
  *"issue comment 106"*)
    # Lưu lại marker nếu có để kiểm lần chạy lại không trùng
    body=""
    prev=""
    for a in "$@"; do
      if [ "$prev" = "--body" ]; then body="$a"; break; fi
      if [ "$prev" = "--body-file" ]; then body="$(cat "$a")"; break; fi
      prev="$a"
    done
    python3 -c 'import json, sys; print(json.dumps([{"id": 1, "body": sys.argv[1]}]))' "$body" > "$FAKE_DIR/comments_106.json"
    ;;
  *"label create"*|*"issue edit"*|*"issue reopen"*|*"issue comment"*)
    exit 0
    ;;
  *)
    echo "unexpected gh: $*" >&2
    exit 1
    ;;
esac
SH
chmod +x "$T/gh"

cat > "$T/card.sh" <<'SH'
#!/usr/bin/env bash
echo "card $*" >> "$FAKE_DIR/calls.log"
exit 0
SH
chmod +x "$T/card.sh"

export FAKE_DIR="$T" SB_GH="$T/gh" SB_CARD="$T/card.sh"

out1="$(python3 "$SWEEP" sweep --config "$T/cfg.json" --items "$T/items.json" 2>"$T/err1.log")"
rc1=$?
[ "$rc1" -eq 0 ] && ok "sweep lần 1 exit 0" || { fail "sweep lần 1 exit $rc1: $(cat "$T/err1.log")"; }

# Kiểm Oracle 1: #101 mở lại + ac-open + comment + move Ready; #102..#106 không bị mở lại
grep -q "gh issue reopen 101 " "$T/calls.log" && ok "Oracle 1: #101 đã mở lại" || fail "Oracle 1: #101 chưa mở lại ($(cat "$T/calls.log"))"
grep -q "gh issue edit 101 .*--add-label ac-open" "$T/calls.log" && ok "Oracle 1: #101 được gắn nhãn ac-open" || fail "Oracle 1: #101 thiếu ac-open"
grep -q "gh issue comment 101 " "$T/calls.log" && ok "Oracle 1: #101 có comment lý do" || fail "Oracle 1: #101 thiếu comment"
grep -q "card .*move 101 Ready" "$T/calls.log" && ok "Oracle 1: #101 chuyển Done -> Ready" || fail "Oracle 1: #101 chưa chuyển Ready"

for skip_n in 102 103 104 105 106; do
  if grep -q "gh issue reopen $skip_n " "$T/calls.log"; then
    fail "Oracle 1: #$skip_n không được phép mở lại"
  else
    ok "Oracle 1: #$skip_n giữ nguyên đóng"
  fi
done

# Kiểm Oracle 2: PR #201 cảnh báo lên #106 một lần, PR #202/#203/#501 không cảnh báo
grep -q "gh issue comment 106 " "$T/calls.log" && ok "Oracle 2: #106 được cảnh báo PR #201 merge ngoài gate" || fail "Oracle 2: thiếu cảnh báo lên #106"
for no_warn in 107 108 103; do
  if grep -q "gh issue comment $no_warn " "$T/calls.log"; then
    fail "Oracle 2: #$no_warn không được phép cảnh báo"
  fi
done

# Kiểm đếm theo ngày & JSON đầu ra
python3 - "$out1" "$TODAY_VN" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
day = sys.argv[2]
assert 101 in d["reopened"], f"reopened={d['reopened']}"
assert d["ungated_total_7d"] == 1, f"ungated_total_7d={d['ungated_total_7d']}"
assert d["ungated_by_date"].get(day) == 1, f"by_date={d['ungated_by_date']} day={day}"
assert [x["pr"] for x in d["ungated_prs"]] == [201], f"prs={d['ungated_prs']}"
PY
[ $? -eq 0 ] && ok "Oracle 2: JSON trả reopened=[101], ungated_total_7d=1, đếm đúng theo ngày $TODAY_VN" || fail "JSON sai: $out1"

# Chạy lại sweep (lần 2), xoá sổ local để kiểm tra chống lặp dựa trên comment GitHub
rm -f "$COMMON/super-board/ungated-merges-warned.json"
: > "$T/calls.log"
out2="$(python3 "$SWEEP" sweep --config "$T/cfg.json" --items "$T/items.json" 2>"$T/err2.log")"
rc2=$?
[ "$rc2" -eq 0 ] && ok "sweep lần 2 exit 0" || fail "sweep lần 2 exit $rc2"
! grep -q "gh issue comment 106 " "$T/calls.log" && ok "Oracle 2: chạy lại không lặp cảnh báo trên #106" || fail "Oracle 2: chạy lại vẫn comment lặp vào #106"

# Kiểm nối dây trong runner (chạy thật hàm sweep_audit) và BIN của super-board-setup.py
grep -q 'sweep_audit' "$RUNNER" && awk '/if sweep_closed_cards;/{a=NR} /if sweep_audit;/{b=NR} END{exit !(a&&b&&a<b)}' "$RUNNER" \
  && ok "runner: gọi sweep_audit sau sweep_closed_cards" || fail "runner: thiếu nối dây sweep_audit"
grep -q '"super-board-audit-sweep.py"' "$SETUP" && ok "setup.py BIN có super-board-audit-sweep.py" || fail "setup.py BIN thiếu super-board-audit-sweep.py"

# Kiểm move Ready hỏng trước khi reopen -> không mở lại #101 (tránh kẹt OPEN trong Done)
cat > "$T/card_fail.sh" <<'SH'
#!/usr/bin/env bash
echo "card-fail $*" >> "$FAKE_DIR/calls.log"
exit 1
SH
chmod +x "$T/card_fail.sh"
: > "$T/calls.log"
SB_CARD="$T/card_fail.sh" python3 "$SWEEP" sweep --config "$T/cfg.json" --items "$T/items.json" >/dev/null 2>"$T/err_mv.log"
rc_mv=$?
[ "$rc_mv" -eq 69 ] && ! grep -q "gh issue reopen 101 " "$T/calls.log" \
  && ok "move Ready hỏng -> exit 69, không reopen #101 để tránh kẹt OPEN trong Done" || fail "move fail check: rc=$rc_mv calls=$(cat "$T/calls.log")"

# Kiểm --items bỏ trống (GraphQL) + lỗi GraphQL -> exit 79
cat > "$T/gql_items.json" <<'JSON'
{"data":{"repositoryOwner":{"projectV2":{"items":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"id":"I109","content":{"number":109,"title":"open ac-open","repository":{"nameWithOwner":"o/r"},"labels":{"nodes":[{"name":"ac-open"}]}},
   "fieldValues":{"nodes":[{"name":"Done","field":{"name":"Status"}}]}}
]}}}}}
JSON
: > "$T/calls.log"
out_gql="$(python3 "$SWEEP" sweep --config "$T/cfg.json" 2>"$T/err_gql.log")"
rc_gql=$?
[ "$rc_gql" -eq 0 ] && grep -q "card .*move 109 Ready" "$T/calls.log" \
  && ok "GraphQL fallback + thẻ OPEN mang ac-open sót ở Done -> chuyển về Ready" || fail "gql check: rc=$rc_gql out=$out_gql"

GQL_ERRORS=1 python3 "$SWEEP" sweep --config "$T/cfg.json" >/dev/null 2>"$T/err_gqle.log"
[ "$?" -eq 79 ] && ok "GraphQL errors -> exit 79 (READ_FAILED)" || fail "GraphQL errors không trả 79"

# Chạy thật hàm sweep_audit của super-board-run.sh (SB_LIB_ONLY=1)
printf 'import sys\nsys.exit(3)\n' > "$T/helper_fail.py"
printf 'print("{\\"reopened\\":[101],\\"moved_ready\\":[101],\\"ungated_total_7d\\":1,\\"ungated_by_date\\":{\\"2026-11-21\\":1}}")\n' > "$T/helper_pass.py"
out_run="$(SB_LIB_ONLY=1 bash -c '
  R="$1"; D="$2"; set --
  . "$R" >/dev/null 2>&1
  set +e
  CONFIG_PATH="$D/cfg.json"; RUN_MANIFEST="$D/manifest.log"; : > "$RUN_MANIFEST"
  PROJECT_ITEMS_JSON="{\"items\":[]}"
  log() { echo "$*" >> "$D/run.log"; }
  audit_sweep_helper() { echo "$HELPER"; }
  HELPER="$D/helper_fail.py"; AUDIT_SWEEP_NEXT=0
  sweep_audit; echo "fail_rc=$? next_after_fail=${AUDIT_SWEEP_NEXT:-0}"
  HELPER="$D/helper_pass.py"; AUDIT_SWEEP_NEXT=0
  sweep_audit; echo "pass_rc=$? next_gt0=$([ "${AUDIT_SWEEP_NEXT:-0}" -gt 0 ] && echo 1 || echo 0)"
' _ "$RUNNER" "$T")"
echo "$out_run" | grep -q "fail_rc=1 next_after_fail=0" && echo "$out_run" | grep -q "pass_rc=0 next_gt0=1" \
  && ok "sweep_audit chạy thật: fail giữ cadence=0, reopened trả rc=0 và nâng cadence" || fail "sweep_audit live: $out_run"

[ "$FAILS" -eq 0 ] && { echo "✅ test_audit_sweep_1406: all passed"; exit 0; }
echo "❌ test_audit_sweep_1406: $FAILS failed"; exit 1
