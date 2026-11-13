#!/usr/bin/env bash
# super-board-scratch-config.sh <repo-path> <scratch-worktree>
# Merge gate verify chạy trong worktree sạch, nơi config cục bộ bị git ignore (google-services.json,
# local.properties, .env…) không có: build Android đỏ, thẻ đã review kẹt (OfficeReader #73, 2026-10-16).
# Chép các file đó từ main checkout bằng đúng hàm DevKit dùng khi tạo worktree (worktree.py copy_ignored: config cục bộ,
# build input như libs/*.aar|jar, *.jks…, Unity Library, hook): chỉ file bị git ignore ở cả hai phía, nên không bao giờ commit
# nhầm được. Làm hết sức: lỗi chỉ được báo.
set -u
REPO_PATH="${1:?repo path}"; SCRATCH="${2:?scratch worktree}"
SELF_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# repo.path là "." trong mọi config board và merge gate có thể chạy từ worktree của Reviewer: nguồn chép là
# main checkout (dòng đầu của `git worktree list`), như super-board-post-merge-clean.sh.
MAIN=$(git -C "$REPO_PATH" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
[ -n "$MAIN" ] || MAIN="$REPO_PATH"
# GeelyEx2 (10/11/2026, PR #328): build_inputs bỏ qua node_modules (SKIP_WALK) nên scratch không có tools/landing-page/node_modules và
# REG-WEB-01 luôn exit 2 = UNTESTED. Mỗi package.json đã track: node_modules thật (không phải link) của main được clone APFS (cp -Rc:
# ~0 dung lượng, symlink pnpm bên trong giữ dạng link) CHỈ khi package.json + lockfile giống hệt main. PR đổi dependency thì không chép:
# module cũ của main sẽ cho xanh giả, exit 2 đúng hơn. Chạy trước vòng DevKit bên dưới vì heredoc ở đó `exit 0` khi thành công.
# ponytail: bản sửa tại chỗ của file đồng bộ từ agent-workbench — lần đồng bộ sau phải mang theo (hoặc đưa lên copy_ignored của DevKit).
clone_node_modules() {
  [ "$(uname)" = Darwin ] || return 0
  local pj dir src dst f same done_list=""
  while IFS= read -r -d '' pj; do
    [ "$(basename "$pj")" = package.json ] || continue
    dir=$(dirname "$pj"); src="$MAIN/$dir/node_modules"; dst="$SCRATCH/$dir/node_modules"
    { [ -d "$src" ] && [ ! -L "$src" ] && [ ! -e "$dst" ] && [ ! -L "$dst" ]; } || continue
    same=1
    for f in package.json pnpm-lock.yaml package-lock.json yarn.lock; do
      if [ -e "$MAIN/$dir/$f" ] || [ -e "$SCRATCH/$dir/$f" ]; then cmp -s "$MAIN/$dir/$f" "$SCRATCH/$dir/$f" || { same=0; break; }; fi
    done
    if [ "$same" != 1 ]; then echo "[scratch-config] $dir/node_modules not cloned: package.json/lockfile differ from main" >&2; continue; fi
    # Khác volume thì cp -c lặng lẽ chép từng byte (như copy_unity_library): không chép.
    if [ "$(stat -f %d "$src")" != "$(stat -f %d "$SCRATCH/$dir")" ]; then
      echo "[scratch-config] $dir/node_modules not cloned: scratch is on another volume" >&2; continue
    fi
    if ! cp -Rc "$src" "$dst" 2>/dev/null; then rm -rf "$dst"; echo "[scratch-config] $dir/node_modules clone failed" >&2; continue; fi
    chflags -R nouchg,nouappnd "$dst" 2>/dev/null || true
    # Scratch phải ignore nó y như main: git thấy được là có thể bị tính vào PR, gỡ ngay.
    if [ -n "$(git -C "$SCRATCH" status --porcelain -- "$dir/node_modules" 2>/dev/null)" ]; then
      rm -rf "$dst"; echo "[scratch-config] $dir/node_modules removed: not git-ignored in the scratch tree" >&2; continue
    fi
    done_list="$done_list $dir/node_modules"
  done < <(git -C "$SCRATCH" ls-files -z -- package.json '*/package.json' 2>/dev/null)
  [ -z "$done_list" ] || echo "[scratch-config] node_modules cloned (lockfile = main):$done_list" >&2
}
clone_node_modules || true
# Lượt 1 cần DevKit có worktree.copy_ignored (danh sách copy_* duy nhất, dùng chung với `agent-kit integrate`, #477); bản cũ (chưa có)
# hoặc hỏng thì sang ứng viên kế tiếp. Không ứng viên nào đủ thì lượt 2 vẫn chép config cục bộ bằng bản cũ, như trước khi có
# build input (thiếu google-services.json là OfficeReader #73 quay lại).
for mode in full config; do
  for c in "$MAIN/universal-agent-devkit" "$MAIN/.agents/devkit" "$SELF_ROOT/universal-agent-devkit" "$SELF_ROOT/.agents/devkit"; do
    [ -f "$c/scripts/git/worktree.py" ] || continue
    python3 - "$c/scripts/git/worktree.py" "$MAIN" "$SCRATCH" "$mode" <<'PY' && exit 0
import importlib.util, sys
spec = importlib.util.spec_from_file_location("devkit_worktree", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
# Lấy hàm trước khi chép gì: bản DevKit thiếu copy_ignored thì hỏng ngay (AttributeError), không chép nửa chừng.
step = mod.copy_ignored if sys.argv[4] == "full" else mod.copy_local_config
copied = step(sys.argv[2], sys.argv[3])
what = "local config, build inputs, Unity Library and ignored hooks" if sys.argv[4] == "full" else "local config only (old DevKit, no copy_ignored)"
print(f"[scratch-config] {what} copied: " + (", ".join(copied) or "none"), file=sys.stderr)
PY
    echo "[scratch-config] $c/scripts/git/worktree.py failed ($mode); trying the next DevKit" >&2
  done
done
echo "[scratch-config] no working DevKit worktree.py: local config not copied" >&2
exit 0
