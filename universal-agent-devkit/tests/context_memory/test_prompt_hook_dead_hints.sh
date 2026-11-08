#!/usr/bin/env bash
# Regression test (chủ repo 08/11, rà token: "cái nào không đáng thì gỡ cho nhẹ token").
# Đo 30 ngày trên transcript thật (.agents/local/memory/token-trim/hints.py, items.py):
#   - "Skill phù hợp": skill được gợi ý được dùng trong cùng lượt 12/6014 lần (0,2 %); dòng còn gợi ý tên chuẩn
#     (fixbugs, tdd-workflow…) mà danh sách skill của Claude không có (Claude gộp command trùng nội dung về alias fix, tdd…).
#   - "Yêu cầu ngầm định": tỉ lệ sửa code có từ khoá NFR khi CÓ dòng ≈ khi KHÔNG có (2,9/2,9 % game, 2,6/2,5 % office…),
#     và nội dung đã nằm sẵn trong AGENTS.md (Engineering musts) nạp mọi phiên.
# Hook prompt (hooks/prompt_context.sh) không in hai dòng này nữa; phần còn lại giữ nguyên: Loại việc, RED→GREEN,
# khối ZERO-SLOP nhiều dòng, Bẫy đã gặp.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không GIT_* thừa kế, không config user
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unset PROMPT_CONTEXT DEVKIT_ROOT PROMPT_DEDUPE DEVKIT_AGENT
mkdir -p "$TMP/home" "$TMP/tmpdir" "$TMP/proj/.agents"
export HOME="$TMP/home" TMPDIR="$TMP/tmpdir" GIT_CONFIG_GLOBAL=/dev/null
export ANTIGRAVITY_PM_GLOBAL_CONFIG="$TMP/home/.antigravity-pm.json"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
cd "$TMP/proj" && git init -q . || exit 1
printf '{"profile": "android"}\n' > .agents/active-profile.json
export CLAUDE_PROJECT_DIR="$TMP/proj"
run() { printf '{"prompt":"%s","session_id":"s%s"}' "$1" "$RANDOM$RANDOM" | bash "$HOOK" 2>&1; }   # phiên mới mỗi lần: không bị dedupe

# 1. Prompt sửa lỗi UI: trước đây có cả hai dòng; giờ không còn dòng nào, phần có ích vẫn còn.
o="$(run "sửa lỗi nút đăng nhập bị bấm nhiều lần làm crash app, thêm timeout cho API login")"
printf '%s\n' "$o" | grep -q '^- Skill phù hợp: ' && fail "1: hook còn in 'Skill phù hợp': $o" || ok "1: không còn dòng 'Skill phù hợp'"
printf '%s\n' "$o" | grep -q '^- Yêu cầu ngầm định: ' && fail "1: hook còn in 'Yêu cầu ngầm định': $o" || ok "1: không còn dòng 'Yêu cầu ngầm định'"
printf '%s\n' "$o" | grep -q '^- Loại việc: .*BUG_FIX' && ok "1: vẫn có dòng Loại việc (BUG_FIX)" || fail "1: mất dòng Loại việc: $o"
printf '%s\n' "$o" | grep -q '^- Bắt buộc: chạy test tái hiện lỗi' && ok "1: vẫn có luật RED→GREEN" || fail "1: mất luật RED→GREEN: $o"
printf '%s\n' "$o" | grep -qF 'ZERO-SLOP UI MANDATE' && ok "1: khối ZERO-SLOP vẫn còn với prompt UI" || fail "1: mất khối ZERO-SLOP: $o"
[ "$(printf '%s\n' "$o" | grep -c '^• ')" = 6 ] && ok "1: ZERO-SLOP còn đủ 6 gạch đầu dòng" || fail "1: ZERO-SLOP thiếu gạch: $o"

# 2. Prompt mạng (trước đây mang dòng NFR timeout/backoff): dòng đó không quay lại.
o="$(run "thêm timeout và retry có backoff cho lời gọi mạng")"
printf '%s\n' "$o" | grep -q '^- Loại việc: .*NETWORK_AND_RESILIENCE' && ok "2: hook vẫn nói, có Loại việc NETWORK" \
  || fail "2: hook im lặng hoặc mất Loại việc: $o"
printf '%s\n' "$o" | grep -q 'Yêu cầu ngầm định\|Skill phù hợp' && fail "2: còn dòng đã gỡ: $o" || ok "2: không còn dòng đã gỡ"

# 3. Ngõ cụt phần cứng đã đo (.agents/context/hardware-boundaries.json) là lưới an toàn: trước đây đi chung dòng
#    "Yêu cầu ngầm định" nên bị gỡ theo (Antigravity audit PR #1057). Nó phải còn, trên dòng riêng, mỗi phiên một lần.
mkdir -p .agents/context
cat > .agents/context/hardware-boundaries.json <<'EOF'
{"boundaries": [{"id": "ECU-TEST-ONLY", "title": "ECU chỉ nhận lệnh qua TBOX", "symptoms": ["peps không hoạt động"],
  "measured": "Đo 3 lần: lệnh trực tiếp bị bỏ.", "rescue": "gửi qua TBOX."}]}
EOF
sid="s$RANDOM$RANDOM"
o="$(printf '{"prompt":"%s","session_id":"%s"}' "sửa lỗi PEPS không hoạt động" "$sid" | bash "$HOOK" 2>&1)"
printf '%s\n' "$o" | grep -q '^- Ngõ cụt phần cứng: DỪNG: ECU-TEST-ONLY .*Cứu hộ: gửi qua TBOX' \
  && ok "3: cảnh báo ngõ cụt phần cứng còn, trên dòng riêng" || fail "3: mất cảnh báo phần cứng: $o"
printf '%s\n' "$o" | grep -q 'Yêu cầu ngầm định' && fail "3: dòng NFR quay lại: $o" || ok "3: không kéo dòng NFR theo"
o2="$(printf '{"prompt":"%s","session_id":"%s"}' "vẫn lỗi PEPS không hoạt động ở xe 2" "$sid" | bash "$HOOK" 2>&1)"
printf '%s\n' "$o2" | grep -q 'Ngõ cụt phần cứng' && fail "3: cảnh báo gửi lại trong cùng phiên: $o2" || ok "3: cùng phiên không gửi lại"
# 3b. Dữ liệu catalog có xuống dòng: cảnh báo vẫn là MỘT dòng, in một lần, không gửi lại mảnh nào trong phiên.
cat > .agents/context/hardware-boundaries.json <<'EOF'
{"boundaries": [{"id": "ECU-ML", "title": "ECU chỉ nhận lệnh qua TBOX", "symptoms": ["peps không hoạt động"],
  "measured": "Đo 3 lần:\nlệnh trực tiếp bị bỏ.", "rescue": "gửi qua TBOX."}]}
EOF
sid="s$RANDOM$RANDOM"
o="$(printf '{"prompt":"%s","session_id":"%s"}' "sửa lỗi PEPS không hoạt động" "$sid" | bash "$HOOK" 2>&1)"
[ "$(printf '%s\n' "$o" | grep -c 'ECU-ML')" = 1 ] && printf '%s\n' "$o" | grep -q '^- Ngõ cụt phần cứng: DỪNG: ECU-ML .*Đo 3 lần: lệnh trực tiếp' \
  && ok "3b: cảnh báo nhiều dòng in đúng một lần, trên một dòng" || fail "3b: cảnh báo nhiều dòng lặp hoặc vỡ dòng: $o"
o2="$(printf '{"prompt":"%s","session_id":"%s"}' "vẫn lỗi PEPS không hoạt động ở xe 2" "$sid" | bash "$HOOK" 2>&1)"
printf '%s\n' "$o2" | grep -q 'ECU-ML\|lệnh trực tiếp bị bỏ' && fail "3b: mảnh cảnh báo gửi lại trong cùng phiên: $o2" || ok "3b: cùng phiên không gửi lại mảnh nào"
rm -f .agents/context/hardware-boundaries.json

[ "$FAILS" = 0 ] && echo "PASS test_prompt_hook_dead_hints" || { echo "FAIL test_prompt_hook_dead_hints ($FAILS)"; exit 1; }
