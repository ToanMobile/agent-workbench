#!/usr/bin/env bash
# start-runner.sh — Khởi chạy Super-Board Runner chạy ngầm an toàn từ bất kỳ đâu
set -euo pipefail

REPO_DIR="/Volumes/Data/Toan/agent-workbench"
cd "$REPO_DIR"

# 1. Kiểm tra xem runner đã chạy chưa
EXISTING_PID=$(ps aux | grep -i "super-board-run.sh agent-workbench" | grep -v grep | awk '{print $2}' || true)
if [ -n "$EXISTING_PID" ]; then
  echo "⚠️  Super-Board Runner đang chạy sẵn rồi (PID: $EXISTING_PID)!"
  echo "    Xem log: tail -f $REPO_DIR/docs/super-board/runner.log"
  echo "    Dừng lại nếu cần: $REPO_DIR/stop-runner.sh"
  exit 0
fi

# 2. Tạo thư mục log
mkdir -p "$REPO_DIR/docs/super-board/runs" "$REPO_DIR/docs/super-board/inflight"
touch "$REPO_DIR/docs/super-board/runner.log" "$REPO_DIR/docs/super-board/current-worker.log"

# 3. Khởi động chạy ngầm 24/7 (SB_DAEMON=1)
SB_DAEMON=1 nohup "$REPO_DIR/.claude/bin/super-board-run.sh" agent-workbench > "$REPO_DIR/docs/super-board/runner.log" 2>&1 &
RUNNER_PID=$!

# 4. Hiển thị trực tiếp tiến trình Runner + từng bước gõ lệnh của Agent vào cửa sổ TUIOS
if command -v tuios >/dev/null 2>&1 && tuios list-windows -s factory 2>/dev/null | grep -q "agent-workbench"; then
  tuios send-keys -s factory -w agent-workbench ctrl+c >/dev/null 2>&1 || true
  tuios send-text -s factory -w agent-workbench $'python3 /Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/super_board_monitor.py /Volumes/Data/Toan/agent-workbench\n' >/dev/null 2>&1 || true
fi

echo "🚀 Đã khởi động Super-Board Runner chạy ngầm thành công!"
echo "   📌 PID : $RUNNER_PID"
echo "   📝 Log : $REPO_DIR/docs/super-board/runner.log"
echo "   🖥  TUIOS: tuios attach factory"
echo "   📋 Board: https://github.com/users/ToanMobile/projects/1/views/2"
echo ""
echo "💡 Bây giờ bạn chỉ việc lên web kéo thẻ từ Backlog ➔ Ready là máy sẽ tự động làm!"
