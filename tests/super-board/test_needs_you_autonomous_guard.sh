#!/usr/bin/env bash
# Kiểm thử rào chắn tự chủ cho super-board-needs-you.py và quy tắc Reviewer/Block:
# Đảm bảo needs-you từ chối (exit 64) các việc agent tự làm được (test PR trên máy/máy ảo,
# chạy lại gate, dọn worktree, tách thẻ <400 dòng, tự duyệt ma trận test, tự chốt UI/kỹ thuật)
# và chỉ chấp nhận (exit 0 với --dry-run) các việc bắt buộc cần con người (mật khẩu, API key,
# tài khoản Play Console/App Store/Supabase, pháp lý, lái xe thật, 5 người chơi thật).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NEEDS_YOU="$REPO_ROOT/.claude/bin/super-board-needs-you.py"
REVIEW_SKILL="$REPO_ROOT/.claude/skills/super-review/SKILL.md"
RUN_REF="$REPO_ROOT/.claude/skills/super-board/references/run.md"
BLOCK_TPL="$REPO_ROOT/.claude/skills/super-board/references/block-template.md"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

# Mock gh cho --dry-run để test chạy tức thì, không gọi mạng thật
TMP_BIN="$(mktemp -d)"
trap 'rm -rf "$TMP_BIN"' EXIT
cat > "$TMP_BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"labels/needs-you"* ]]; then
  echo '{"color":"D93F0B","description":"🙋 Cần người thực hiện bước chỉ con người được làm"}'
elif [[ "$*" == *"/comments"* ]]; then
  echo '[]'
else
  echo '{"labels":[],"body":""}'
fi
EOF
chmod +x "$TMP_BIN/gh"
export PATH="$TMP_BIN:$PATH"

# 1. Các tác vụ agent tự làm được PHẢI bị super-board-needs-you.py mark từ chối với mã thoát 64
reject_actions=(
  "Thử PR #168 trên máy: áp font .ttf, lật trang một lần, xem có bị kéo lùi không; lỗi thì giao lại Builder"
  "Chạy lại gate --full trong worktree .claude/worktrees/issue-23-build khi máy rảnh; exit 0 thì commit 2 file"
  "Xem 3 file chưa commit ở .claude/worktrees/issue-28-qa rồi gỡ worktree đó"
  "Dừng gradle/java của project khác, chờ load 1 phút < 2 và không chạy gate/playtester"
  "Thu body #98 về một lát dưới 400 dòng hoặc tách thẻ con (/to-tickets)"
  "Trả lời approve matrix fix trên issue và thu hẹp AC2"
  "Duyệt thêm 3 guard VOICE-1013, VOICE-1015, REG-OPS-18 vào ma trận hồi quy GeelyEx2"
  "Chốt vị trí nút Lưu cho form PDF trong reader: menu Thêm hay chip nổi"
  "Chọn A cho PR #41: giữ phạm vi dữ liệu + sim, sửa chữ AC3 thành UfoField.Hash"
  "Actions -> Roborazzi Baseline Record -> Run workflow trên main với reference DEC-02"
  # 24/10: lọt qua bộ chặn, #319 nằm Blocked chờ người dù gốc là một test treo (REG-DK-ALL-01 TIMEOUT, #353)
  "Nâng giới hạn 900s của REG-DK-ALL-01 hoặc xác nhận bằng chứng thay gate exit 0"
  "Raise the REG-DK-ALL-01 timeout or accept the evidence above instead of a gate exit 0"
  "Nâng giới hạn thời gian của suite REG-DK-ALL-01 lên 1800s"
  "Raise the timeout of REG-DK-ALL-01 to 1800s"
  "Raise the REG-DK-ALL-01 suite timeout"
  "Tăng timeout của REG-DK-ALL-01 lên 1800s"
  "Nâng giới hạn của suite REG-DK-ALL-01"
  "Chấp nhận kết quả của Builder thay cho exit 0 của gate"
  "REG-DK-ALL-01 timeout should be increased to 1800s"
  "Chấp nhận TIMEOUT của REG-DK-ALL-01 như PASS"
  # một từ billing/thanh toán trong câu không biến việc test/chốt của agent thành việc của người
  "Thử PR #12 luồng billing trên máy ảo"
)

for act in "${reject_actions[@]}"; do
  set +e
  out=$(python3 "$NEEDS_YOU" mark --repo ToanMobile/OfficeReader --issue 114 --action "$act" --dry-run 2>&1)
  rc=$?
  set -e
  if [[ "$rc" -eq 64 ]]; then
    pass "needs-you từ chối (exit 64) việc agent tự làm được: ${act:0:55}..."
  else
    fail "needs-you KHÔNG từ chối (exit $rc, mong đợi 64): $act (out: $out)"
  fi
done

# 2. Các tác vụ thật sự cần con người (API key, tài khoản store/console, pháp lý, 5 người chơi thật, lái xe thật) PHẢI được cho phép (exit 0 hoặc gọi gh)
allow_actions=(
  "Đổi Gemini API key (khóa cũ lộ 18/10), supabase secrets set GEMINI_API_KEY; làm Play Console"
  "Chạy supabase login, supabase link --project-ref <ref>, rồi supabase db pull vào supabase/migrations"
  "Tạo 3 product ID Play Billing trên Play Console (1 tháng, 1 năm, trọn đời)"
  "Tìm 5 người chơi thật, cho chơi APK từ HEAD theo production/qa/playtest-2026-10.md"
  "Tạo/xác nhận tài khoản Google Play và Apple Developer, nộp hồ sơ phát hành VN theo NĐ 147/2024"
  # 24/10 review: mẫu "nâng giới hạn" của gate không được chặn nhầm việc billing/quota thật
  "Nâng giới hạn chi tiêu (spending limit) tài khoản OpenAI trong trang billing"
  "Raise the spending limit on the Anthropic console billing page"
  "Nâng giới hạn quota Google Maps API trên Cloud Console"
  "Xác nhận bằng chứng minh nhân dân cho tài khoản Stripe"
  "Raise the Lambda timeout in the AWS console"
  "Nâng giới hạn timeout của Cloudflare Worker trên dashboard"
  "Nâng giới hạn thời gian dùng thử trên App Store Connect"
  "Xác nhận bằng chứng chuyển khoản của khách hàng"
  "Chấp nhận bằng chứng sở hữu tên miền"
  "Tăng giới hạn người dùng G Suite"
  "Raise the Office suite license limit"
  "Raise the GitHub Actions spending limit so the gate can run"
  "Tăng giới hạn chi tiêu GitHub Actions để gate CI chạy được"
  "Nâng giới hạn kết nối Postgres production để test suite tải chạy được"
)

for act in "${allow_actions[@]}"; do
  set +e
  out=$(python3 "$NEEDS_YOU" mark --repo ToanMobile/OfficeReader --issue 154 --action "$act" --dry-run 2>&1)
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    pass "needs-you cho phép (exit 0) việc thật sự cần người: ${act:0:55}..."
  else
    fail "needs-you từ chối nhầm (exit $rc, mong đợi 0): $act (out: $out)"
  fi
done

# 3. super-review/SKILL.md và references/run.md phải định tuyến truth_gate < threshold về Ready/QA (loop:rebuild-N), không đẩy thẳng sang Blocked + needs-you cho lỗi code/test
if grep -q "loop:rebuild-N" "$REVIEW_SKILL" && grep -q "NEVER.*needs-you" "$BLOCK_TPL"; then
  pass "super-review/SKILL.md và block-template.md đã khóa quy tắc tự chủ không đẩy lỗi code/test sang needs-you"
else
  fail "super-review/SKILL.md hoặc block-template.md chưa cập nhật quy tắc định tuyến truth_gate / cấm needs-you cho việc agent làm được"
fi

echo ""
echo "Summary: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
