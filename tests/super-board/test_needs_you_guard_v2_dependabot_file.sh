#!/usr/bin/env bash
# Rào chắn needs-you v2: miễn "dependabot" (bước bật auto-approve cho Dependabot là cấu hình GitHub của chủ repo) không áp cho
# tên file, như deploy/production/settings (_NOT_FILE). Review r1 đợt 2 (03/11, principal-code-reviewer + OCR): `.github/dependabot.yml`
# hay `test-dependabot-*.sh` từng được miễn, nên câu nhắm việc agent ("Sửa AC thẻ #14 theo .github/dependabot.yml") lọt v2.
#   D1: chữ dependabot trong tên file có đuôi → không miễn (exit 64).
#   D2: chữ Dependabot thường (bước của người) → vẫn miễn (exit 0).
set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR  # cờ đọc qua git: không để biến git của gate trỏ vào repo thật

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NEEDS_YOU="$REPO_ROOT/.claude/bin/super-board-needs-you.py"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/repo"
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
if [[ "$*" == *"labels/needs-you"* ]]; then
  echo '{"color":"D93F0B","description":"🙋 Cần người thực hiện bước chỉ con người được làm"}'
elif [[ "$*" == *"/comments"* ]]; then
  echo '[]'
else
  echo '{"labels":[],"body":""}'
fi
GH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
git -C "$TMP/repo" init -q

mark_rc() {   # mark_rc <action> -> exit code của mark --dry-run, chạy trong $TMP/repo
  local rc
  set +e
  (cd "$TMP/repo" && python3 "$NEEDS_YOU" mark --repo ToanMobile/agent-workbench --issue 1 --action "$1" --dry-run >/dev/null 2>&1)
  rc=$?
  set -e
  echo "$rc"
}

# D1: dependabot trong tên file có đuôi không được miễn.
for act in \
  "Viết lại thẻ #12 cho .github/dependabot.yml" \
  "Sửa AC thẻ #14 theo .github/dependabot.yml" \
  "Viết lại thẻ #12 cho tests/super-board/test-dependabot-merge.sh"; do
  rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  [ "$rc" = 64 ] && pass || fail "D1 cờ bật phải từ chối (exit $rc, cần 64): $act"
done
# D2: chữ Dependabot thường vẫn là bước của người.
for act in \
  "Bật auto-approve cho Dependabot với PR chỉ sửa tests/" \
  "Bật auto-approve cho PR Dependabot đổi tests/package.json"; do
  rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  [ "$rc" = 0 ] && pass || fail "D2 cờ bật chặn nhầm bước Dependabot (exit $rc): $act"
done

echo "needs-you guard v2 dependabot file: $PASS pass, $FAIL fail"
[ "$FAIL" = 0 ]
