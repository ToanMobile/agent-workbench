#!/usr/bin/env bash
# super-board-scratch-config.sh <repo-path> <scratch-worktree>
# Merge gate verify chạy trong worktree sạch, nơi config cục bộ bị git ignore (google-services.json,
# local.properties, .env…) không có: build Android đỏ, thẻ đã review kẹt (OfficeReader #73, 2026-10-16).
# Chép các file đó từ main checkout bằng đúng hàm DevKit dùng khi tạo worktree (worktree.py copy_local_config):
# chỉ file bị git ignore ở cả hai phía, nên không bao giờ commit nhầm được. Làm hết sức: lỗi chỉ được báo.
set -u
REPO_PATH="${1:?repo path}"; SCRATCH="${2:?scratch worktree}"
SELF_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WT_PY=""
for c in "$REPO_PATH/universal-agent-devkit" "$REPO_PATH/.agents/devkit" "$SELF_ROOT/universal-agent-devkit" "$SELF_ROOT/.agents/devkit"; do
  [ -f "$c/scripts/git/worktree.py" ] && { WT_PY="$c/scripts/git/worktree.py"; break; }
done
[ -n "$WT_PY" ] || { echo "[scratch-config] DevKit worktree.py not found: local config not copied" >&2; exit 0; }
python3 - "$WT_PY" "$REPO_PATH" "$SCRATCH" <<'PY' || echo "[scratch-config] copy failed: local config not copied" >&2
import importlib.util, sys
spec = importlib.util.spec_from_file_location("devkit_worktree", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
copied = mod.copy_local_config(sys.argv[2], sys.argv[3])
print("[scratch-config] local config copied: " + (", ".join(copied) or "none"), file=sys.stderr)
PY
exit 0
