#!/usr/bin/env bash
# #190 R1: gh_write_once gắn marker DUY NHẤT cho mỗi lần comment; comment cố định lặp trên cùng issue không được làm
# reconcile báo "đã áp dụng" nhầm (resume mù).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

# Trích đúng hàm thật từ runner (không chép công thức vào test).
sed -n '/^gh_write_once() {/,/^}/p' "$ROOT/.claude/bin/super-board-run.sh" > "$TMP/fn.sh"
[ -s "$TMP/fn.sh" ] || { echo "không trích được gh_write_once"; exit 1; }

cat > "$TMP/read.py" <<'PY'
#!/usr/bin/env python3
import os, sys
if '--halt' in sys.argv:
    open(os.environ['HALT_LOG'], 'a').write(sys.argv[sys.argv.index('--verify') + 1] + '\n')
PY
cat > "$TMP/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
exit 1
SH
chmod +x "$TMP/gh"
export PATH="$TMP:$PATH" GH_LOG="$TMP/gh.log" HALT_LOG="$TMP/halt.log"
SB_GITHUB_READ="$TMP/read.py"
gh_checkpoint() { :; }
. "$TMP/fn.sh"

BODY='[orchestrator] [report] ↩️ back to Ready · stranded in Building
Did: x'
for i in 1 2; do ( gh_write_once issue comment 190 --body "$BODY" ) >/dev/null 2>&1 || true; sleep 1; done
[ "$(wc -l < "$HALT_LOG" 2>/dev/null | tr -d ' ')" = 2 ] || fail "expected 2 halt records, got: $(cat "$HALT_LOG" 2>/dev/null)"
m1=$(sed -n 1p "$HALT_LOG" | jq -r .marker); m2=$(sed -n 2p "$HALT_LOG" | jq -r .marker)
[ -n "$m1" ] && [ "$m1" != "$m2" ] && ok "same fixed comment twice → two different markers" || fail "markers repeat: '$m1' vs '$m2'"
grep -qF -- "$m1" "$GH_LOG" && ok "the posted body carries the marker it will be verified by" || fail "marker '$m1' absent from the posted body"
grep -q 'back to Ready' "$GH_LOG" && ok "the original comment text is still posted" || fail "original text lost"
echo "pass=$PASS fail=$FAIL"; [ "$FAIL" = 0 ]
