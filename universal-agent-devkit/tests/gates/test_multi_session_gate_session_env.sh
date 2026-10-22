#!/usr/bin/env bash
# Test hồi quy (#240, 22/10): test_multi_session_gate.sh phải xanh khi chạy TRONG phiên/verify của máy thật.
# post-fix-gate chọn id phiên theo thứ tự --session, DEVKIT_SESSION_ID, CLAUDE_CODE_SESSION_ID, CLAUDE_SESSION_ID; phiên Claude hay worker
# board export các biến đó, nên ca 7 ("phiên của chính mình qua CLAUDE_CODE_SESSION_ID không bị đếm là phiên khác") đọc id của máy thật
# và đỏ oan ở merge gate. Ca này chạy suite với đúng các biến đó rò vào: ai gỡ dòng `unset` khỏi suite thì ca này đỏ ngay ở gate thường.
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(DEVKIT_SESSION_ID=leaked-real-session CLAUDE_SESSION_ID=leaked-real-session CLAUDE_CODE_SESSION_ID=leaked-real-session \
  bash "$DEVKIT_DIR/tests/gates/test_multi_session_gate.sh" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "✔ test_multi_session_gate xanh khi id phiên của máy thật rò vào môi trường"
  echo "✅ test_multi_session_gate_session_env: all passed"
else
  printf '%s\n' "$OUT" | grep -E "^(✖|❌)" | head -10
  echo "❌ test_multi_session_gate_session_env: test_multi_session_gate.sh exit $rc khi id phiên thật rò vào"
  exit 1
fi
