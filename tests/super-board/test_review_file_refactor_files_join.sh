#!/usr/bin/env bash
# super-review-file-refactor.sh: dòng **Files:** nối các file bằng ", " (PR #1407 R7, lớp lỗi BSD paste).
# `paste -sd ', '` trên macOS coi ", " là hai dấu phân cách luân phiên nên 3 file ra `a`,`b` `c`.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REFACTOR="$ROOT/.claude/bin/super-review-file-refactor.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-refactor-files.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/cfg.json" <<'JSON'
{
  "project": {"owner": "o", "number": 1},
  "repo": {"remote": "https://github.com/o/r.git"},
  "verify_commands": ["true"],
  "usage_fallback": "codex"
}
JSON
cat > "$TMP/body.md" <<'MD'
## Problem
Shallow seam.

## Context
- **Where:** `src/cart.py`

## Fix
Deepen module.
MD

cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" graphql "*) echo '[{"data":{"repository":{"issues":{"totalCount":0,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}]' ;;
  *" issue view "*) echo '{"number":7,"title":"t","body":"b","labels":[{"name":"bug"}]}' ;;
  *" label create "*) exit 0 ;;
  *" issue create "*)
    while [ $# -gt 0 ]; do
      if [ "$1" = "--body-file" ]; then cp "$2" "$FAKE_DIR/last_body.md"; break; fi
      shift
    done
    echo "https://github.com/o/r/issues/42"
    ;;
  *" project item-add "*) echo '{"id":"PVTI_1"}' ;;
  *" project view "*) echo '{"id":"PVT_1"}' ;;
  *" project field-list "*) echo '{"fields":[{"name":"Status","id":"PVTF_1","options":[{"name":"Backlog","id":"OPT_1"},{"name":"Ready","id":"OPT_2"}]}]}' ;;
  *" project item-edit "*) exit 0 ;;
  *) echo "unexpected gh: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0

bash "$REFACTOR" --config "$TMP/cfg.json" --title "extract checkout seam" \
  --body-file "$TMP/body.md" --fingerprint "cart|seam-files" \
  --files "src/a.ts,src/b.ts,src/c.ts" >/dev/null 2>"$TMP/err.txt"

line="$(grep -F '**Files:**' "$TMP/last_body.md" 2>/dev/null || true)"
want='**Files:** `src/a.ts`, `src/b.ts`, `src/c.ts`'
if [ "$line" = "$want" ]; then
  ok "ba file được nối bằng ', '"
else
  fail "dòng Files sai: '${line}' (stderr: $(head -c 200 "$TMP/err.txt"))"
fi

[ "$FAILS" -eq 0 ] && { echo "✅ test_review_file_refactor_files_join: all passed"; exit 0; }
echo "❌ test_review_file_refactor_files_join: $FAILS failed"; exit 1
