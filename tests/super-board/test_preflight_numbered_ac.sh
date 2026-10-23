#!/usr/bin/env bash
# Test hồi quy #283 (23/10): #202 và #227 nằm Blocked "pre-flight hold (unclear): no ## Acceptance Criteria bullets" dù mục
# ## Acceptance Criteria ghi 1) 2) 3) 4). has_acs của super-board-preflight.sh và luật kéo Backlog của super-board-run.sh chỉ
# nhận dòng "- " / "* ". Luật:
#  A  AC đánh số "1)" -> preflight không hold "unclear".
#  B  AC đánh số "1." -> preflight không hold "unclear".
#  C  Mục AC chỉ có văn xuôi / trống, hoặc dòng văn xuôi bắt đầu bằng năm ("2026.") -> vẫn hold "unclear".
#  D  backlog_ticket_gaps (runner) nhận AC đánh số; AC văn xuôi vẫn báo thiếu.
# gh giả, chạy offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PREFLIGHT="$ROOT/.claude/bin/super-board-preflight.sh"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-preflight-ac.XXXXXX")"
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

paren=$'## Problem\nx\n\n## Fix\ny\n\n## Acceptance Criteria\n1) Test RED rồi GREEN ở tick runner thật.\n2) Gate --full exit 0.\n\n## Risk\nthấp\n'
dot=$'## Problem\nx\n\n## Fix\ny\n\n## Acceptance Criteria\n1. Test RED rồi GREEN.\n2. Gate --full exit 0.\n'
prose=$'## Problem\nx\n\n## Fix\ny\n\n## Acceptance Criteria\nChạy đúng là được.\n\n## Risk\nthấp\n'
year=$'## Problem\nx\n\n## Fix\ny\n\n## Acceptance Criteria\n2026. Ra mắt bản mới là đủ.\n\n## Risk\nthấp\n'
mk() { jq -n --argjson n "$1" --arg t "$2" --arg b "$3" '{number:$n,title:$t,body:$b}' > "$TMP/issue-$1.json"; }
mk 701 "alpha numbered paren ac" "$paren"
mk 702 "beta numbered dot ac" "$dot"
mk 703 "gamma prose ac" "$prose"
mk 704 "delta year prose ac" "$year"
bash "$PREFLIGHT" --repo o/r --issues 701,702,703,704 > "$TMP/out.json" 2> "$TMP/err" || fail "preflight exit $? ($(tail -1 "$TMP/err"))"
tag() { jq -r --arg n "$1" '.[$n].tag // "none"' "$TMP/out.json" 2>/dev/null; }

[ "$(tag 701)" = clean ] && ok "A: AC numbered '1)' is accepted (clean)" || fail "A: #701 tag=$(tag 701)"
[ "$(tag 702)" = clean ] && ok "B: AC numbered '1.' is accepted (clean)" || fail "B: #702 tag=$(tag 702)"
[ "$(tag 703)" = unclear ] && ok "C: AC as prose only is still 'unclear'" || fail "C: #703 tag=$(tag 703)"
[ "$(tag 704)" = unclear ] && ok "C2: a prose line starting with a year ('2026.') is not an AC item" || fail "C2: #704 tag=$(tag 704)"

# D: luật kéo Backlog của runner.
unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
g1=$(printf '%s' "$paren" | backlog_ticket_gaps); g2=$(printf '%s' "$dot" | backlog_ticket_gaps); g3=$(printf '%s' "$prose" | backlog_ticket_gaps); g4=$(printf '%s' "$year" | backlog_ticket_gaps)
[ -z "$g1" ] && [ -z "$g2" ] && [ "$g3" = "Acceptance Criteria" ] && [ "$g4" = "Acceptance Criteria" ] \
  && ok "D: backlog pull accepts numbered AC, still flags prose AC" \
  || fail "D: gaps paren='$g1' dot='$g2' prose='$g3' year='$g4'"

[ "$FAILS" -eq 0 ] && echo "✅ test_preflight_numbered_ac: all passed" || { echo "❌ $FAILS failed"; exit 1; }
