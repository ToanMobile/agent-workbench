#!/usr/bin/env bash
# Test hồi quy (#240, 22/10): các suite của merge gate phải xanh khi chạy TRONG phiên/verify của máy thật.
# post-fix-gate chọn id phiên theo thứ tự --session, DEVKIT_SESSION_ID, CLAUDE_CODE_SESSION_ID, CLAUDE_SESSION_ID; phiên Claude hay worker
# board export các biến đó. test_multi_session_gate.sh (ca 7: "phiên của chính mình qua CLAUDE_CODE_SESSION_ID không bị đếm là phiên khác") và
# test_gate_stop_reuse_race.sh (ca K1: gate đổi nhánh theo id phiên) đọc id của máy thật và đỏ oan ở merge gate.
# multi_session_gate (nhanh): chạy thật với id rò vào. reuse_race (~2 phút, đỏ ngẫu nhiên khi máy tải cao): chỉ kiểm dòng `unset` còn đó,
# vì chạy thật hai lần trong gate sẽ tự gây đúng thứ đỏ oan mà ca này chặn; gỡ dòng đó thì ca này đỏ (đã chứng minh bằng chạy thật 22/10).
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
OUT="$(DEVKIT_SESSION_ID=leaked-real-session CLAUDE_SESSION_ID=leaked-real-session CLAUDE_CODE_SESSION_ID=leaked-real-session \
  bash "$DEVKIT_DIR/tests/gates/test_multi_session_gate.sh" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "✔ test_multi_session_gate.sh xanh khi id phiên của máy thật rò vào môi trường"
else
  printf '%s\n' "$OUT" | grep -E "^(✖|❌)" | head -10
  echo "✖ test_multi_session_gate.sh exit $rc khi id phiên thật rò vào"
  FAILS=$((FAILS + 1))
fi
if grep -q '^unset .*DEVKIT_SESSION_ID.*CLAUDE_SESSION_ID.*CLAUDE_CODE_SESSION_ID' "$DEVKIT_DIR/tests/gates/test_gate_stop_reuse_race.sh"; then
  echo "✔ test_gate_stop_reuse_race.sh gỡ id phiên của máy thật khỏi môi trường"
else
  echo "✖ test_gate_stop_reuse_race.sh thiếu dòng unset DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID"
  FAILS=$((FAILS + 1))
fi
if [ "$FAILS" -eq 0 ]; then echo "✅ test_multi_session_gate_session_env: all passed"; else echo "❌ test_multi_session_gate_session_env: $FAILS ca đỏ"; exit 1; fi
