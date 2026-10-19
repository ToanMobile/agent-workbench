#!/usr/bin/env bash
# super-board-scratch-config.sh <repo-path> <scratch-worktree>
# Merge gate verify chạy trong worktree sạch, nơi config cục bộ bị git ignore (google-services.json,
# local.properties, .env…) không có: build Android đỏ, thẻ đã review kẹt (OfficeReader #73, 2026-10-16).
# Chép các file đó từ main checkout bằng đúng hàm DevKit dùng khi tạo worktree (worktree.py copy_local_config,
# copy_build_inputs cho libs/*.aar|jar, *.jks…): chỉ file bị git ignore ở cả hai phía, nên không bao giờ commit
# nhầm được. Làm hết sức: lỗi chỉ được báo.
set -u
REPO_PATH="${1:?repo path}"; SCRATCH="${2:?scratch worktree}"
SELF_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# repo.path là "." trong mọi config board và merge gate có thể chạy từ worktree của Reviewer: nguồn chép là
# main checkout (dòng đầu của `git worktree list`), như super-board-post-merge-clean.sh.
MAIN=$(git -C "$REPO_PATH" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
[ -n "$MAIN" ] || MAIN="$REPO_PATH"
# Lượt 1 cần DevKit có cả hai hàm; bản cũ (chưa có copy_build_inputs) hoặc hỏng thì sang ứng viên kế tiếp. Không ứng
# viên nào đủ thì lượt 2 vẫn chép config cục bộ bằng bản cũ, như trước khi có copy_build_inputs (thiếu
# google-services.json là OfficeReader #73 quay lại).
for mode in full config; do
  for c in "$MAIN/universal-agent-devkit" "$MAIN/.agents/devkit" "$SELF_ROOT/universal-agent-devkit" "$SELF_ROOT/.agents/devkit"; do
    [ -f "$c/scripts/git/worktree.py" ] || continue
    python3 - "$c/scripts/git/worktree.py" "$MAIN" "$SCRATCH" "$mode" <<'PY' && exit 0
import importlib.util, sys
spec = importlib.util.spec_from_file_location("devkit_worktree", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
# Lấy đủ các hàm trước khi chép gì: bản DevKit thiếu một hàm thì hỏng ngay, không chép nửa chừng.
steps = (mod.copy_local_config, mod.copy_build_inputs) if sys.argv[4] == "full" else (mod.copy_local_config,)
# Hook bị ignore mà settings đăng ký (guard-*.py, cleanup-wt.py): thiếu thì `agent-kit health` của verify FAIL (agent-workbench #12,
# PR #87). DevKit cũ chưa có copy_local_hooks (#93) thì bỏ qua, phần còn lại vẫn chép như trước.
has_hooks = hasattr(mod, "copy_local_hooks")
steps += (mod.copy_local_hooks,) if has_hooks else ()
copied = [rel for step in steps for rel in step(sys.argv[2], sys.argv[3])]
what = "local config and build inputs" if sys.argv[4] == "full" else "local config only (old DevKit, no build inputs)"
what += " + ignored hooks" if has_hooks else " (old DevKit: ignored hooks not copied)"
print(f"[scratch-config] {what} copied: " + (", ".join(copied) or "none"), file=sys.stderr)
PY
    echo "[scratch-config] $c/scripts/git/worktree.py failed ($mode); trying the next DevKit" >&2
  done
done
echo "[scratch-config] no working DevKit worktree.py: local config not copied" >&2
exit 0
