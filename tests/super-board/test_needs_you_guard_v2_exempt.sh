#!/usr/bin/env bash
# Rào chắn needs-you v2: các ca OCR review tìm ra ngày 03/11, sau #924.
#   E1: chữ "production"/"deploy" trong đường dẫn hay tên file (production/qa/…, deploy.sh) không được miễn
#       cho câu nhắm việc của agent.
#   E2: bước của người trên GitHub settings / cài đặt không bị chặn nhầm.
#   E3: env SB_NEEDS_YOU_GUARD_V2 thắng flags.json (env=0 mà flags.json true thì vẫn là tắt).
#   E4: bước bật auto-approve cho Dependabot là việc của người, kể cả khi câu nhắc tới tests/ (residual 03/11).
# Câu "phải nhận" của E1/E2 đều chạm một luật V2 (sửa AC thẻ #N, auto-approve … tests/): bỏ miễn trừ đang thử thì câu bị
# từ chối, nên test bắt được (wave 2, 03/11: các câu "Bật auto-approve …" không có tests/ đi qua dù không có miễn trừ nào).
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
  "Sửa AC thẻ #14 theo repo settings.yml" \
  "Viết lại thẻ #12 cho script deploy-prod.sh" \
  "Viết lại thẻ #12 cho production-checklist.md" \
  "Viết lại thẻ #12 cho .github/dependabot.yml" \
  "Sửa AC thẻ #14 theo .github/dependabot.yml" \
  "Viết lại thẻ #12 cho tests/super-board/test-dependabot-merge.sh"; do
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
  "Sửa AC thẻ #14 cho environment production/staging trên GitHub" \
  "Sửa AC thẻ #14 cho environment production/staging/canary" \
  "Sửa AC thẻ #14 cho deploy-v2.3" \
  "Sửa AC thẻ #14 cho production-v1.2"; do
  rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  [ "$rc" = 0 ] && pass || fail "E1 cờ bật chặn nhầm bước deploy thật (exit $rc): $act"
done

# E2: bước trên GitHub settings là việc của người. Câu nhắc tests/ để chạm luật auto-approve: chỉ miễn settings/cài đặt cứu được.
for act in \
  "Chủ repo duyệt auto-approve cho PR chỉ sửa tests/ trên GitHub settings" \
  "Bật auto-approve cho PR chỉ sửa tests/ trong cài đặt repo" \
  "Bật auto-approve cho PR chỉ sửa tests/ trong Settings của tổ chức GitHub" \
  "Bật auto-approve cho PR chỉ sửa tests/ trong repository settings" \
  "Bật auto-approve cho PR chỉ sửa tests/: Settings → Actions → General" \
  "Bật auto-approve cho PR chỉ sửa tests/ trong cài đặt tổ chức" \
  "Bật auto-approve cho PR chỉ sửa tests/ trong phần Cài đặt của kho"; do
  rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  [ "$rc" = 0 ] && pass || fail "E2 cờ bật chặn nhầm bước settings (exit $rc): $act"
done
# Luật auto-approve cần đường dẫn test: không có tests/ thì không chạm luật nào (như v1).
for act in \
  "Bật auto-approve trên GitHub" \
  "Bật auto-approve trong cấu hình repo trên GitHub"; do
  rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  [ "$rc" = 0 ] && pass || fail "E2 cờ bật chặn nhầm bước settings (exit $rc): $act"
done
rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "gõ tay AUTO-APPROVE cho tests/super-board/test_x.sh trên PR #606")"
[ "$rc" = 64 ] && pass || fail "E2 AUTO-APPROVE cho test vẫn phải bị từ chối (exit $rc, cần 64)"

# E4: bật auto-approve cho Dependabot là bước của người trên GitHub, kể cả khi câu nhắc tests/.
for act in \
  "Bật auto-approve cho Dependabot với PR chỉ sửa tests/" \
  "Bật auto-approve cho PR Dependabot đổi tests/package.json"; do
  rc="$(SB_NEEDS_YOU_GUARD_V2=1 mark_rc "$act")"
  [ "$rc" = 0 ] && pass || fail "E4 cờ bật chặn nhầm bước Dependabot (exit $rc): $act"
done

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
