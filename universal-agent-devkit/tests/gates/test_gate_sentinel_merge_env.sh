#!/usr/bin/env bash
# Test hồi quy (#167, 22/10): test_gate_sentinel.sh phải xanh khi chạy TRONG verify của merge gate.
# Merge gate export DEVKIT_SLOT_PRIORITY=merge (và DEVKIT_SLOT_LOAD_WAIT_S=0 khi đã chờ tải) quanh lệnh verify; post-fix-gate lồng
# bên trong thấy merge ⇒ tắt sentinel ⇒ 6 ca 1a, 2b, 2b', 2c, 3a, 3b đỏ (PR #158 / thẻ #148 bị chặn 3 lần, exit 11). Ca này chạy suite
# với đúng hai biến đó rò vào: ai gỡ dòng `unset` khỏi test_gate_sentinel.sh thì ca này đỏ ngay ở gate thường, không phải đợi merge gate.
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(DEVKIT_SLOT_PRIORITY=merge DEVKIT_SLOT_LOAD_WAIT_S=0 bash "$DEVKIT_DIR/tests/gates/test_gate_sentinel.sh" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "✔ test_gate_sentinel xanh khi DEVKIT_SLOT_PRIORITY=merge rò từ merge gate"
  echo "✅ test_gate_sentinel_merge_env: all passed"
else
  printf '%s\n' "$OUT" | grep -E "^(✖|❌)" | head -10
  echo "❌ test_gate_sentinel_merge_env: test_gate_sentinel.sh exit $rc dưới biến môi trường của merge gate"
  exit 1
fi
