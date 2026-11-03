#!/usr/bin/env bash
# Rào chắn needs-you v2: các ca OCR review tìm ra ngày 03/11, sau #924.
#   E1: chữ "production"/"deploy" trong đường dẫn hay tên file (production/qa/…, deploy.sh) không được miễn
#       cho câu nhắm việc của agent.
#   E2: bước của người trên GitHub settings (vd. bật auto-approve cho Dependabot) không bị chặn nhầm.
#   E3: env SB_NEEDS_YOU_GUARD_V2 thắng flags.json (env=0 mà flags.json true thì vẫn là tắt).
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

# E1: chữ thuộc danh sách hỏi người nằm trong đường dẫn hay tên file thì không được miễn.
for act in \
  "Sửa AC thẻ #14 theo production/qa/playtest-2026-10.md" \
  "Viết lại thẻ #12 cho script deploy.sh" \
  "Viết lại thẻ #12 cho .claude/settings.json" \
  "Sửa AC thẻ #14 sửa file settings.gradle" \
  "Sửa AC thẻ #14 về bước cài đặt hook DevKit" \
  "gõ tay AUTO-APPROVE cho tests/x.sh trong settings PR"; do
  rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  [ "$rc" = 64 ] && pass || fail "E1 cờ bật phải từ chối (exit $rc, cần 64): $act"
done
# E1 chiều ngược: deploy/production là chữ thường (không phải đường dẫn) thì vẫn được miễn. Mỗi câu chỉ có một vế:
# có "rồi/và/," thì one_line tách vế và vế "sửa AC" vẫn bị chặn, đúng thiết kế.
for act in \
  "Sửa AC thẻ #14 khi deploy production bản 2.3" \
  "Viết lại thẻ #12 sau khi deploy lên store" \
  "Sửa AC thẻ #14 sau khi deploy." \
  "Sửa AC thẻ #14 sau khi deploy/rollback bản 2.3" \
  "Bật auto-approve cho environment production/staging trên GitHub"; do
  rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  [ "$rc" = 0 ] && pass || fail "E1 cờ bật chặn nhầm bước deploy thật (exit $rc): $act"
done

# E2: bước trên GitHub settings là việc của người.
for act in \
  "Chủ repo duyệt auto-approve cho Dependabot trên GitHub settings" \
  "Bật auto-approve trong cài đặt repo"; do
  rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  [ "$rc" = 0 ] && pass || fail "E2 cờ bật chặn nhầm bước settings (exit $rc): $act"
done
rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "gõ tay AUTO-APPROVE cho tests/super-board/test_x.sh trên PR #606")"
[ "$rc" = 64 ] && pass || fail "E2 AUTO-APPROVE cho test vẫn phải bị từ chối (exit $rc, cần 64)"

# E3: env thắng flags.json.
probe="Sửa AC thẻ #200 cho khớp 5 PR đang mở"
mkdir -p "$TMP/repo/.agents/local"
echo '{"needs_you_guard_v2": true}' > "$TMP/repo/.agents/local/flags.json"
rc="$(SB_NEEDS_YOU_GUARD_V2=0 mark_rc "$probe")"
[ "$rc" = 0 ] && pass || fail "E3 env=0 phải thắng flags.json true (exit $rc)"
echo '{"needs_you_guard_v2": false}' > "$TMP/repo/.agents/local/flags.json"
rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$probe")"
[ "$rc" = 64 ] && pass || fail "E3 env=1 phải thắng flags.json false (exit $rc, cần 64)"

echo "needs-you guard v2 exempt: $PASS pass, $FAIL fail"
[ "$FAIL" = 0 ]
