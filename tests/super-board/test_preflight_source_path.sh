#!/usr/bin/env bash
# Test hồi quy câu 3 (chồng file) của .claude/bin/super-board-preflight.sh với `gh` giả (offline).
# 2026-10-19: thẻ kế hoạch OfficeReader đều có dòng "- **Nguồn:** docs/plans/OfficeReader_Plan.md …"; preflight coi
# đường dẫn đó là file thẻ sẽ sửa, nên trong một lô chỉ thẻ số nhỏ nhất được build, các thẻ còn lại bị sequence.
# Fixture là body thật của OfficeReader #94, #99, #100 (lấy bằng `gh issue view`). Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PREFLIGHT="$ROOT/.claude/bin/super-board-preflight.sh"
FIX="$ROOT/tests/super-board/fixtures/preflight-source-path"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-preflight-src.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
# gh giả: không PR/issue đóng nào; `issue view` đọc fixture OfficeReader-<n>.json, hoặc body tổng hợp S<n> trong $SB_SYN.
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" api rate_limit "*) echo '{"resources":{"graphql":{"remaining":5000,"reset":0},"core":{"remaining":5000,"reset":0}}}' ;;
  *" api graphql "*) exit 1 ;;
  *" pr list "*|*" issue list "*) echo '[]' ;;
  *" issue view "*)
    n=""; prev=""
    for a in "$@"; do [ "$prev" = view ] && n="$a"; prev="$a"; done
    if [ -f "$SB_FIXTURES/OfficeReader-$n.json" ]; then cat "$SB_FIXTURES/OfficeReader-$n.json"
    else cat "$SB_SYN/$n.json"; fi ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
mkdir -p "$TMP/syn"
# Hai thẻ tổng hợp cùng ghi một file mã trong Where (phải vẫn bị sequence) và một thẻ trích Source: bằng tiếng Anh.
mk() { jq -n --argjson n "$1" --arg t "$2" --arg b "$3" '{number:$n,title:$t,body:$b,labels:[{name:"bug"}],state:"OPEN"}' > "$TMP/syn/$1.json"; }
mk 801 "fix alpha parser crash" $'## Problem\nx\n\n## Context\n- **Where:** `src/core/parser.ts`\n\n## Fix\nsửa\n\n## Acceptance Criteria\n- [ ] test đỏ rồi xanh\n'
mk 802 "tune beta renderer timeout" $'## Problem\ny\n\n## Context\n- **Where:** `src/core/parser.ts`\n\n## Fix\nsửa\n\n## Acceptance Criteria\n- [ ] test đỏ rồi xanh\n'
mk 803 "adjust gamma exporter retry" $'## Problem\nz\n\n## Context\n- Source: docs/plans/Plan.md\n- **Where:** `src/other/exporter.ts`\n\n## Fix\nsửa\n\n## Acceptance Criteria\n- [ ] test đỏ rồi xanh\n'
mk 804 "extend delta importer cache" $'## Problem\nz\n\n## Context\n- Source: docs/plans/Plan.md\n- **Where:** `src/other/importer.ts`\n\n## Fix\nsửa\n\n## Acceptance Criteria\n- [ ] test đỏ rồi xanh\n'
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_FIXTURES="$FIX" SB_SYN="$TMP/syn" \
  SB_GH_GUARD_STATE_FILE="$TMP/budget"

bash "$PREFLIGHT" --repo ToanMobile/OfficeReader --issues 94,99,100 >"$TMP/office.json" 2>"$TMP/office.err" \
  || fail "OfficeReader: preflight exit $? ($(tail -1 "$TMP/office.err"))"
bash "$PREFLIGHT" --repo ToanMobile/Synthetic --issues 801,802,803,804 >"$TMP/syn.json" 2>"$TMP/syn.err" \
  || fail "Synthetic: preflight exit $? ($(tail -1 "$TMP/syn.err"))"

# Không thẻ nào bị sequence vì file kế hoạch chỉ được trích làm nguồn (#100 vẫn có thể bị hold "too big" vì lý do khác).
for n in 94 99 100; do
  if jq -e --arg n "$n" '.[$n] | (.tag != "sequence") and ((.evidence // []) | any(test("docs/plans")) | not)' \
       "$TMP/office.json" >/dev/null 2>&1; then
    ok "OfficeReader #$n: không bị sequence vì docs/plans"
  else
    fail "OfficeReader #$n: bị sequence vì docs/plans ($(jq -c --arg n "$n" '.[$n]|[.verdict,.tag,.evidence]' "$TMP/office.json" 2>/dev/null))"
  fi
done
# Hai thẻ khác nhau chỉ chung dòng Source: vẫn proceed cả hai.
for n in 803 804; do
  got=$(jq -r --arg n "$n" '.[$n].verdict' "$TMP/syn.json" 2>/dev/null)
  if [ "$got" = proceed ]; then ok "Synthetic #$n: proceed (Source: không tính là file sửa)"
  else fail "Synthetic #$n: muốn proceed, được $got"; fi
done
# Hành vi cũ: hai thẻ cùng file mã trong Where thì thẻ số lớn bị sequence.
if [ "$(jq -r '.["801"].verdict' "$TMP/syn.json" 2>/dev/null)" = proceed ] \
   && [ "$(jq -r '.["802"].verdict' "$TMP/syn.json" 2>/dev/null)" != proceed ] \
   && jq -e '.["802"].evidence | any(test("src/core/parser.ts"))' "$TMP/syn.json" >/dev/null 2>&1; then
  ok "Synthetic #802: vẫn bị sequence sau #801 vì cùng src/core/parser.ts trong Where"
else
  fail "Synthetic #801/#802: muốn #801 proceed, #802 sequence theo src/core/parser.ts ($(jq -c '[.["801"].verdict,.["802"].verdict]' "$TMP/syn.json" 2>/dev/null))"
fi

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
