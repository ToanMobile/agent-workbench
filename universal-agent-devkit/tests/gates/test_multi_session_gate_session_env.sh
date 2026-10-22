#!/usr/bin/env bash
# Test hồi quy (#240, 22/10): các suite của merge gate phải xanh khi chạy TRONG phiên/verify của máy thật.
# post-fix-gate chọn id phiên theo thứ tự --session, DEVKIT_SESSION_ID, CLAUDE_CODE_SESSION_ID, CLAUDE_SESSION_ID; phiên Claude hay worker
# board export các biến đó. test_multi_session_gate.sh (ca 7: "phiên của chính mình qua CLAUDE_CODE_SESSION_ID không bị đếm là phiên khác") và
# test_gate_stop_reuse_race.sh (ca K1: gate đổi nhánh theo id phiên) đọc id của máy thật và đỏ oan ở merge gate.
# Ca này chạy từng suite với đúng các biến đó rò vào: ai gỡ dòng `unset` khỏi một suite thì ca này đỏ ngay ở gate thường.
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
for suite in test_multi_session_gate.sh test_gate_stop_reuse_race.sh; do
  OUT="$(DEVKIT_SESSION_ID=leaked-real-session CLAUDE_SESSION_ID=leaked-real-session CLAUDE_CODE_SESSION_ID=leaked-real-session \
    bash "$DEVKIT_DIR/tests/gates/$suite" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "✔ $suite xanh khi id phiên của máy thật rò vào môi trường"
  else
    printf '%s\n' "$OUT" | grep -E "^(✖|❌)" | head -10
    echo "✖ $suite exit $rc khi id phiên thật rò vào"
    FAILS=$((FAILS + 1))
  fi
done
if [ "$FAILS" -eq 0 ]; then echo "✅ test_multi_session_gate_session_env: all passed"; else echo "❌ test_multi_session_gate_session_env: $FAILS suite đỏ"; exit 1; fi
