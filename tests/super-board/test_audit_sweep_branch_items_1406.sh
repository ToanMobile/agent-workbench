#!/usr/bin/env bash
# Test hồi quy #1406 (review R4 của PR #1413) cho super-board-audit-sweep.py:
#  B. Nhánh của thẻ theo đúng quy ước CARD_FROM_BRANCH của super-board-ac-check.py (`(?:^|/)issue-(\d+)(?:\D|$)`): nhánh `issue-<N>`
#     không có hậu tố, hoặc có tiền tố thư mục (`claude/issue-<N>-x`), vẫn là PR merged liên kết của thẻ <N> ⇒ thẻ đóng COMPLETED còn
#     AC chưa tick KHÔNG bị mở lại; `issue-3010-…` / `reissue-301-…` không bị nhận nhầm cho thẻ 301 khác.
#  I. File --items có thẻ của repo khác (content.repository != repo nhà) trùng SỐ với thẻ đã đóng của repo nhà ⇒ không tính là thẻ
#     trên board (như fetch_board_items): không mở lại, không chuyển cột.
# Offline; gh giả. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SWEEP="$ROOT/.claude/bin/super-board-audit-sweep.py"
AC_CHECK="$ROOT/.claude/bin/super-board-ac-check.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

T="$(mktemp -d "${TMPDIR:-/tmp}/sb-audit-sweep-branch-1406.XXXXXX")"
trap 'rm -rf "$T"' EXIT

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

# Thẻ 301..305 (305 ghi "O/R"), 307, 308 thuộc repo nhà; 306 là thẻ của repo khác trùng số với một thẻ đã đóng của repo nhà.
# 307: repository dạng URL; 308: repository dạng object {nameWithOwner} — vẫn là repo nhà (không lọc nhầm).
cat > "$T/items.json" <<'JSON'
{
  "items": [
    {"id": "I301", "status": "Done", "content": {"type": "Issue", "number": 301, "repository": "o/r"}},
    {"id": "I302", "status": "Done", "content": {"type": "Issue", "number": 302, "repository": "o/r"}},
    {"id": "I303", "status": "Done", "content": {"type": "Issue", "number": 303}},
    {"id": "I304", "status": "Done", "content": {"type": "Issue", "number": 304, "repository": "o/r"}},
    {"id": "I305", "status": "Done", "content": {"type": "Issue", "number": 305, "repository": "O/R"}},
    {"id": "I306", "status": "Done", "content": {"type": "Issue", "number": 306, "repository": "o/other"}},
    {"id": "I307", "status": "Done", "content": {"type": "Issue", "number": 307, "repository": "https://github.com/o/r"}},
    {"id": "I308", "status": "Done", "content": {"type": "Issue", "number": 308, "repository": {"nameWithOwner": "o/r"}}}
  ],
  "totalCount": 8
}
JSON

python3 - "$T/closed_issues.json" "$NOW_ISO" <<'PY'
import json, sys
rows = [{"number": n, "title": "t%d" % n, "stateReason": "COMPLETED", "labels": [], "closedAt": sys.argv[2],
         "closedByPullRequestsReferences": [], "body": "## Acceptance Criteria\n- [ ] AC chưa tick\n"}
        for n in (301, 302, 303, 304, 305, 306, 307, 308)]
json.dump(rows, open(sys.argv[1], "w"))
PY

# PR merged (đều có biên nhận, không nhiễu phần cảnh báo ngoài gate); KHÔNG PR nào có closingIssuesReferences:
#   issue-301            -> thẻ 301 (không hậu tố)
#   claude/issue-302-fix -> thẻ 302 (tiền tố thư mục)
#   issue-3030-x, reissue-303-y -> KHÔNG phải thẻ 303
#   thẻ 304: không có trong danh sách chung, chỉ truy vấn dự phòng theo nhánh mới thấy (nhánh `issue-304`)
python3 - "$T" "$NOW_ISO" "$RECEIPTS" <<'PY'
import json, sys
t, now, receipts = sys.argv[1:4]
def pr(num, branch):
    oid = "%040x" % num
    json.dump({"pr": num, "head": oid, "base": "main", "verified_tree": oid, "squash": oid, "time": 1},
              open("%s/%d-%s.json" % (receipts, num, oid), "w"))
    return {"number": num, "title": "pr", "headRefName": branch, "headRefOid": oid, "baseRefName": "main",
            "mergeCommit": {"oid": oid}, "mergedAt": now, "closingIssuesReferences": [], "url": "https://github.com/o/r/pull/%d" % num}
json.dump([pr(901, "issue-301"), pr(902, "claude/issue-302-fix"), pr(903, "issue-3030-x"), pr(904, "reissue-303-y")],
          open(t + "/merged_prs.json", "w"))
json.dump([pr(905, "issue-304")], open(t + "/fallback_304.json", "w"))
PY

: > "$T/calls.log"
cat > "$T/gh" <<'SH'
#!/usr/bin/env bash
set -u
echo "gh $*" >> "$FAKE_DIR/calls.log"
case "$*" in
  *"issue list"*"--state closed"*) cat "$FAKE_DIR/closed_issues.json" ;;
  *"pr list"*"--state merged"*"head:issue-304"*) cat "$FAKE_DIR/fallback_304.json" ;;
  *"pr list"*"--state merged"*"head:issue-"*) echo '[]' ;;
  *"pr list"*"--state merged"*) cat "$FAKE_DIR/merged_prs.json" ;;
  *"api "*"/issues/"*"/comments"*) echo '[[]]' ;;
  *"issue view"*) echo "CLOSED" ;;
  *"label create"*|*"issue edit"*|*"issue reopen"*|*"issue comment"*) exit 0 ;;
  *) echo "unexpected gh: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$T/gh"
printf '#!/usr/bin/env bash\necho "card $*" >> "$FAKE_DIR/calls.log"\nexit 0\n' > "$T/card.sh"
chmod +x "$T/card.sh"
export FAKE_DIR="$T" SB_GH="$T/gh" SB_CARD="$T/card.sh"

out="$(python3 "$SWEEP" sweep --config "$T/cfg.json" --items "$T/items.json" 2>"$T/err.log")"; rc=$?
[ "$rc" -eq 0 ] && ok "sweep exit 0" || fail "sweep exit $rc: $(cat "$T/err.log")"
reopened() { grep -q "gh issue reopen $1 " "$T/calls.log"; }

reopened 301 && fail "B1 thẻ 301 bị mở lại dù có PR merged trên nhánh 'issue-301' (không hậu tố)" \
  || ok "B1 nhánh 'issue-301' (không hậu tố) là PR liên kết của thẻ 301: không mở lại"
reopened 302 && fail "B2 thẻ 302 bị mở lại dù có PR merged trên nhánh 'claude/issue-302-fix' (tiền tố thư mục)" \
  || ok "B2 nhánh 'claude/issue-302-fix' (tiền tố thư mục) là PR liên kết của thẻ 302: không mở lại"
reopened 303 && ok "B3 nhánh 'issue-3030-x' / 'reissue-303-y' không bị nhận nhầm cho thẻ 303: thẻ 303 được mở lại" \
  || fail "B3 thẻ 303 không được mở lại (nhánh của thẻ khác bị nhận nhầm?)"
reopened 304 && fail "B4 thẻ 304 bị mở lại dù truy vấn dự phòng theo nhánh thấy PR trên 'issue-304'" \
  || ok "B4 truy vấn dự phòng theo nhánh nhận 'issue-304' (không hậu tố): không mở lại"
grep -q 'pr list.*head:issue-304-' "$T/calls.log" && fail "B4b truy vấn dự phòng còn đòi dấu '-' sau số thẻ (head:issue-304-)" \
  || ok "B4b truy vấn dự phòng không đòi dấu '-' sau số thẻ"
reopened 305 && ok "B5 (mốc) thẻ 305 không có PR liên kết vẫn được mở lại (repository 'O/R' khác hoa/thường vẫn là repo nhà)" \
  || fail "B5 thẻ 305 không được mở lại"

reopened 306 && fail "I1 thẻ 306 của repo khác (o/other) trong file --items bị coi là thẻ repo nhà và mở lại" \
  || ok "I1 thẻ của repo khác trong file --items bị lọc: #306 không bị mở lại"
grep -q "card .*move 306 " "$T/calls.log" && fail "I1b thẻ 306 của repo khác bị chuyển cột" || ok "I1b thẻ của repo khác không bị chuyển cột"
reopened 307 && reopened 308 && ok "I2 repository dạng URL / object {nameWithOwner} của repo nhà không bị lọc nhầm (#307, #308 mở lại)" \
  || fail "I2 thẻ repo nhà (repository dạng URL / object) bị lọc nhầm"

# Quy ước nhánh trùng nguyên văn với CARD_FROM_BRANCH của super-board-ac-check.py
python3 - "$SWEEP" "$AC_CHECK" <<'PY'
import importlib.util, sys
def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
sys.dont_write_bytecode = True
a, b = load(sys.argv[1], "sb_sweep"), load(sys.argv[2], "sb_ac")
sys.exit(0 if a.BRANCH_CARD_RE.pattern == b.CARD_FROM_BRANCH.pattern else 1)
PY
[ $? -eq 0 ] && ok "B6 BRANCH_CARD_RE trùng nguyên văn CARD_FROM_BRANCH của super-board-ac-check.py" \
  || fail "B6 BRANCH_CARD_RE lệch CARD_FROM_BRANCH của super-board-ac-check.py"

[ "$FAILS" -eq 0 ] && { echo "✅ test_audit_sweep_branch_items_1406: all passed"; exit 0; }
echo "❌ test_audit_sweep_branch_items_1406: $FAILS failed"; exit 1
