#!/usr/bin/env bash
# Test hồi quy (29/10): #616 và #618 nằm Blocked "pre-flight hold (unclear): no `## Acceptance Criteria` items" dù thẻ có
# mục `## AC` với các dòng "- [ ] …". Ba chỗ đọc mục AC của thẻ (preflight has_acs, luật kéo Backlog của runner,
# super-board-ac-check.py ở merge gate) chỉ nhận heading `## Acceptance Criteria`. Luật:
#  A  `## AC` có mục -> preflight không hold "unclear".
#  B  `## AC` văn xuôi -> vẫn hold "unclear"; `## ACL` / `## ACK` không phải heading AC.
#  C  backlog_ticket_gaps (runner) nhận `## AC`.
#  D  super-board-ac-check.py đếm mục dưới `## AC` của thẻ.
# gh giả, chạy offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PREFLIGHT="$ROOT/.claude/bin/super-board-preflight.sh"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
ACCHECK="$ROOT/.claude/bin/super-board-ac-check.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-preflight-ac-short.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" api rate_limit "*) echo '{"resources":{"graphql":{"remaining":5000,"reset":0},"core":{"remaining":5000,"reset":0}}}' ;;
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

short=$'## Problem\nx\n\n## Fix\ny\n\n## AC\n- [ ] New test RED on the old code, GREEN after\n- [ ] old tests still pass\n\n## Risk\nthấp\n'
prose=$'## Problem\nx\n\n## Fix\ny\n\n## AC\nChạy đúng là được.\n\n## Risk\nthấp\n'
acl=$'## Problem\nx\n\n## Fix\ny\n\n## ACL\n- [ ] quyền đọc\n\n## Risk\nthấp\n'
mk() { jq -n --argjson n "$1" --arg t "$2" --arg b "$3" '{number:$n,title:$t,body:$b}' > "$TMP/issue-$1.json"; }
mk 801 "alpha short heading ac" "$short"
mk 802 "beta short heading prose" "$prose"
mk 803 "gamma acl heading" "$acl"
bash "$PREFLIGHT" --repo o/r --issues 801,802,803 > "$TMP/out.json" 2> "$TMP/err" || fail "preflight exit $? ($(tail -1 "$TMP/err"))"
tag() { jq -r --arg n "$1" '.[$n].tag // "none"' "$TMP/out.json" 2>/dev/null; }

[ "$(tag 801)" = clean ] && ok "A: '## AC' with items is accepted (clean)" || fail "A: #801 tag=$(tag 801)"
[ "$(tag 802)" = unclear ] && ok "B: '## AC' with prose only is still 'unclear'" || fail "B: #802 tag=$(tag 802)"
[ "$(tag 803)" = unclear ] && ok "B2: '## ACL' is not an AC heading" || fail "B2: #803 tag=$(tag 803)"

# C: luật kéo Backlog của runner.
unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
g1=$(printf '%s' "$short" | backlog_ticket_gaps); g2=$(printf '%s' "$prose" | backlog_ticket_gaps)
[ -z "$g1" ] && [ "$g2" = "Acceptance Criteria" ] \
  && ok "C: backlog pull accepts '## AC', still flags prose AC" \
  || fail "C: gaps short='$g1' prose='$g2'"

# D: merge gate đếm AC của thẻ.
printf '%s' "$short" > "$TMP/issue.md"
printf '%s\n' '<!-- sb:ac -->' '- [x] New test RED on the old code, GREEN after' '- [x] old tests still pass' '<!-- /sb:ac -->' > "$TMP/pr.md"
n=$(python3 "$ACCHECK" --issue-body "$TMP/issue.md" --pr-body "$TMP/pr.md" --branch issue-801-x 2>/dev/null | jq -r '.issue_ac // empty')
[ "$n" = 2 ] && ok "D: ac-check counts the 2 items under '## AC'" || fail "D: ac-check issue_ac='$n'"

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "FAIL ($FAILS)"; exit 1
