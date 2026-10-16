#!/usr/bin/env bash
# stop-runner.sh — Dừng an toàn Super-Board Runner cho repo này từ bất kỳ đâu
set -euo pipefail

REPO_DIR="/Volumes/Data/Toan/agent-workbench"
cd "$REPO_DIR"

bash "$REPO_DIR/.claude/bin/super-board-stop.sh" agent-workbench
