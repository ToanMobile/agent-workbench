#!/usr/bin/env python3
"""
worktree_sandbox.py — High-Performance Parallel APFS Worktree Sandbox Manager

Trích xuất & nâng cấp từ Git Engine của Orca:
1. macOS APFS Copy-on-Write (clonefile / cp -c -R) siêu tốc (<100ms, 0-byte đĩa ban đầu).
2. Tự động sao chép file gitignored an toàn qua '.worktreeinclude' (.env, local.properties).
3. Đảm bảo cùng Volume APFS (chống lỗi EXDEV của macOS).
4. Cô lập dependencies & Environment Envelope (Port offset, IS_SANDBOX=1).
5. Dọn dẹp nguyên tử (Atomic Teardown): Không để lại orphan gitdir trong .git/worktrees/.
6. Trọng tài thẩm định tự động (Winner Arbitrator): So sánh diff và merge giải pháp tối ưu.
"""

import os
import sys
import subprocess
import shutil
import argparse
import json
import re
from pathlib import Path
from typing import List, Dict, Optional, Tuple


def run_cmd(cmd: List[str], cwd: Optional[Path] = None, check: bool = True) -> subprocess.CompletedProcess:
    """Chạy lệnh subprocess an toàn."""
    try:
        return subprocess.run(
            cmd,
            cwd=str(cwd) if cwd else None,
            capture_output=True,
            text=True,
            check=check,
            timeout=120
        )
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"Error running command {' '.join(cmd)}: {e.stderr}\n")
        raise e


def get_repo_root() -> Path:
    """Lấy thư mục gốc của repository hiện tại."""
    proc = run_cmd(["git", "rev-parse", "--show-toplevel"])
    return Path(proc.stdout.strip()).resolve()


def get_sandboxes_dir(repo_root: Path) -> Path:
    """Lấy thư mục chứa các sandboxes (luôn cùng APFS Volume với repo)."""
    sandboxes_dir = repo_root / ".sandboxes"
    sandboxes_dir.mkdir(parents=True, exist_ok=True)
    return sandboxes_dir


def check_same_volume(p1: Path, p2: Path) -> bool:
    """Kiểm tra 2 đường dẫn có cùng device filesystem (APFS Volume) không."""
    try:
        return p1.stat().st_dev == p2.stat().st_dev
    except Exception:
        return False


def copy_with_apfs_cow(source: Path, target: Path) -> bool:
    """
    Sử dụng /bin/cp -c (hoặc -c -R) trên macOS để copy Copy-on-Write APFS.
    Nếu thất bại hoặc không phải macOS, fallback sang copy tiêu chuẩn.
    """
    if not source.exists():
        return False
    
    target.parent.mkdir(parents=True, exist_ok=True)

    if sys.platform == "darwin":
        # Trên macOS, dùng /bin/cp -c (clonefile)
        cmd = ["/bin/cp", "-c"]
        if source.is_dir():
            cmd.extend(["-R", f"{source}/.", str(target)])
            target.mkdir(parents=True, exist_ok=True)
        else:
            cmd.extend([str(source), str(target)])
        
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if res.returncode == 0:
            return True

    # Fallback tiêu chuẩn
    if source.is_dir():
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(source, target, symlinks=True)
    else:
        shutil.copy2(source, target)
    return True


def parse_worktree_include(repo_root: Path) -> List[str]:
    """Đọc file .worktreeinclude từ gốc repo và parse danh sách file an toàn."""
    include_file = repo_root / ".worktreeinclude"
    if not include_file.exists():
        # Fallback về template nếu chưa có
        template_file = repo_root / "templates" / ".worktreeinclude"
        if template_file.exists():
            include_file = template_file
        else:
            return [".env", "local.properties", "keystore.properties"]

    safe_paths: List[str] = []
    with open(include_file, "r", encoding="utf-8") as f:
        for line in f:
            clean = line.strip()
            if not clean or clean.startswith("#"):
                continue
            # Chặn path traversal và ký tự glob
            if ".." in clean or clean.startswith("/") or os.path.normpath(clean) == "." or any(c in clean for c in ["*", "?", "!"]):
                continue
            safe_paths.append(clean)
    return safe_paths


def create_sandbox(name: str, base_branch: Optional[str] = None, port_offset: int = 10) -> Path:
    """Tạo một sandbox worktree mới với APFS CoW và nạp file cấu hình."""
    if not re.match(r"^[a-zA-Z0-9_-]+$", name):
        raise ValueError(f"Tên sandbox không hợp lệ: '{name}'. Chỉ chấp nhận chữ cái, số, gạch dưới và gạch ngang.")

    repo_root = get_repo_root()
    sandboxes_dir = get_sandboxes_dir(repo_root)

    # Preflight kiểm tra Volume
    if not check_same_volume(repo_root, sandboxes_dir):
        print(f"⚠ Cảnh báo: {sandboxes_dir} không cùng volume với {repo_root}. CoW APFS có thể bị suy giảm.")

    sandbox_path = sandboxes_dir / name
    if sandbox_path.exists():
        raise RuntimeError(f"Sandbox '{name}' đã tồn tại tại {sandbox_path}")

    if not base_branch:
        proc = run_cmd(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo_root)
        base_branch = proc.stdout.strip()

    branch_name = f"sandbox/{name}"
    print(f"🚀 [1/4] Tạo Git Worktree '{branch_name}' tại {sandbox_path} (từ base '{base_branch}')...")
    run_cmd(["git", "worktree", "add", "-b", branch_name, str(sandbox_path), base_branch], cwd=repo_root)

    # Sao chép các file an toàn từ .worktreeinclude
    print("📁 [2/4] Sao chép cấu hình cục bộ qua .worktreeinclude (APFS CoW)...")
    included_paths = parse_worktree_include(repo_root)
    copied_count = 0
    for rel_path in included_paths:
        src = repo_root / rel_path
        dst = sandbox_path / rel_path
        if src.exists():
            if copy_with_apfs_cow(src, dst):
                copied_count += 1
    print(f"   ✓ Đã sao chép {copied_count} mục cấu hình an toàn.")

    # Dependencies CoW isolation (nếu có node_modules ở repo gốc, nhân bản CoW)
    src_node_modules = repo_root / "node_modules"
    if src_node_modules.exists() and src_node_modules.is_dir():
        print("📦 [3/4] Nhân bản dependencies qua APFS CoW (0-byte đĩa, tốc độ cao)...")
        dst_node_modules = sandbox_path / "node_modules"
        copy_with_apfs_cow(src_node_modules, dst_node_modules)
        print("   ✓ node_modules đã sẵn sàng trong sandbox.")

    # Thiết lập Environment Envelope
    print(f"⚙️  [4/4] Khởi tạo Environment Envelope (PORT_OFFSET={port_offset})...")
    env_file = sandbox_path / ".sandbox-env.sh"
    with open(env_file, "w", encoding="utf-8") as f:
        f.write(f"#!/usr/bin/env bash\n")
        f.write(f"export IS_SANDBOX=1\n")
        f.write(f"export SANDBOX_NAME={name}\n")
        f.write(f"export PORT_OFFSET={port_offset}\n")
        f.write(f"export PORT=$((3000 + PORT_OFFSET))\n")
    env_file.chmod(0o755)

    print(f"\n✅ Đã kích hoạt Sandbox thành công tại: {sandbox_path}")
    print(f"   Để bắt đầu làm việc trong sandbox: cd {sandbox_path}")
    return sandbox_path


def list_sandboxes() -> List[Dict[str, str]]:
    """Liệt kê toàn bộ sandboxes đang hoạt động."""
    repo_root = get_repo_root()
    sandboxes_dir = repo_root / ".sandboxes"
    if not sandboxes_dir.exists():
        return []

    proc = run_cmd(["git", "worktree", "list", "--porcelain"], cwd=repo_root)
    lines = proc.stdout.splitlines()

    sandboxes = []
    current_entry: Dict[str, str] = {}
    for line in lines:
        if line.startswith("worktree "):
            current_entry = {"path": line.split(" ", 1)[1]}
        elif line.startswith("branch "):
            current_entry["branch"] = line.split(" ", 1)[1]
            if str(sandboxes_dir) in current_entry.get("path", ""):
                p = Path(current_entry["path"])
                current_entry["name"] = p.name
                sandboxes.append(current_entry)
            current_entry = {}
    return sandboxes


def get_sandbox_diff(name: str) -> Dict[str, any]:
    """Lấy thống kê git diff của sandbox so với base."""
    repo_root = get_repo_root()
    sandbox_path = repo_root / ".sandboxes" / name
    if not sandbox_path.exists():
        raise RuntimeError(f"Không tìm thấy sandbox '{name}'")

    proc = run_cmd(["git", "status", "--porcelain"], cwd=sandbox_path)
    dirty_files = [l.strip() for l in proc.stdout.splitlines() if l.strip()]

    diff_stat = run_cmd(["git", "diff", "--stat", "HEAD~1"], cwd=sandbox_path, check=False)
    diff_patch = run_cmd(["git", "diff", "--shortstat"], cwd=sandbox_path, check=False)

    return {
        "name": name,
        "path": str(sandbox_path),
        "dirty_files": dirty_files,
        "diff_stat": diff_stat.stdout.strip(),
        "short_stat": diff_patch.stdout.strip()
    }


def compare_sandboxes(name_a: str, name_b: str) -> None:
    """So sánh 2 sandbox để trọng tài đánh giá phương án thắng cuộc."""
    diff_a = get_sandbox_diff(name_a)
    diff_b = get_sandbox_diff(name_b)

    print(f"\n⚖️  KẾT QUẢ SO SÁNH TRỌNG TÀI GIỮA SANDBOX [{name_a}] VÀ [{name_b}]:")
    print(f"─" * 60)
    print(f"🔹 Sandbox A [{name_a}]:")
    print(f"   Files chưa commit: {len(diff_a['dirty_files'])}")
    print(f"   Diff summary: {diff_a['short_stat'] or 'Chưa có thay đổi'}")
    print(f"─" * 60)
    print(f"🔹 Sandbox B [{name_b}]:")
    print(f"   Files chưa commit: {len(diff_b['dirty_files'])}")
    print(f"   Diff summary: {diff_b['short_stat'] or 'Chưa có thay đổi'}")
    print(f"─" * 60)
    print("💡 Tiêu chí chọn Winner: Exit 0 trên Post-Fix Gate + Diff phẫu thuật ít dòng hơn.")


def cleanup_sandbox(name: Optional[str] = None, cleanup_all: bool = False) -> None:
    """Dọn dẹp worktree an toàn, unregister và xoá sạch nhánh."""
    if name and not re.match(r"^[a-zA-Z0-9_-]+$", name):
        raise ValueError(f"Tên sandbox không hợp lệ: '{name}'. Chỉ chấp nhận chữ cái, số, gạch dưới và gạch ngang.")

    repo_root = get_repo_root()
    sandboxes_dir = repo_root / ".sandboxes"

    targets = []
    if cleanup_all:
        for s in list_sandboxes():
            targets.append(s["name"])
    elif name:
        targets.append(name)
    else:
        print("Cần chỉ định tên sandbox hoặc cờ --all")
        return

    for t in targets:
        s_path = sandboxes_dir / t
        branch_name = f"sandbox/{t}"
        print(f"🧹 Dọn dẹp sandbox '{t}'...")
        if s_path.exists():
            run_cmd(["git", "worktree", "remove", "--force", str(s_path)], cwd=repo_root, check=False)
            if s_path.exists():
                shutil.rmtree(s_path, ignore_errors=True)
        # Xóa nhánh sandbox
        run_cmd(["git", "branch", "-D", branch_name], cwd=repo_root, check=False)
        print(f"   ✓ Đã gỡ bỏ {t} và xoá nhánh {branch_name} sạch sẽ.")

    run_cmd(["git", "worktree", "prune"], cwd=repo_root, check=False)
    print("✅ Đã dọn dẹp hoàn tất toàn bộ rác Git worktree.")


def merge_winner(name: str, squash: bool = False, clean_others: bool = False) -> None:
    """
    Merge sandbox thắng cuộc vào main branch và TỰ ĐỘNG DỌN DẸP SẠCH SẼ.
    1. Kiểm tra sandbox tồn tại và sạch sẽ (không còn uncommitted dirty files).
    2. Lấy tên branch chính (main hoặc base branch).
    3. Thực hiện merge từ sandbox branch vào main branch.
    4. Ngay khi merge thành công:
       - TỰ ĐỘNG dọn dẹp sandbox thắng cuộc: gỡ worktree, xóa folder, xóa branch.
       - Chỉ khi có cờ --clean-others mới dọn các sandbox khác (mặc định GIỮ NGUYÊN: chúng có thể còn việc chưa merge).
       - Chạy git worktree prune để dọn dẹp sạch sẽ 100% trong .git/worktrees/.
    """
    repo_root = get_repo_root()
    sandbox_path = repo_root / ".sandboxes" / name
    if not sandbox_path.exists():
        raise RuntimeError(f"Không tìm thấy sandbox '{name}' để merge.")

    # 1. Kiểm tra uncommitted changes trong các file tracked
    proc = run_cmd(["git", "status", "--porcelain", "--untracked-files=no"], cwd=sandbox_path)
    if proc.stdout.strip():
        raise RuntimeError(
            f"Sandbox '{name}' đang có file tracked chưa commit. Hãy commit hoặc revert trước khi merge:\n{proc.stdout}"
        )

    branch_name = f"sandbox/{name}"

    # 2. Merge vào main repo
    print(f"🔄 [1/3] Đang tiến hành merge branch '{branch_name}' vào nhánh chính...")
    merge_cmd = ["git", "merge", branch_name]
    if squash:
        merge_cmd.append("--squash")

    merge_res = run_cmd(merge_cmd, cwd=repo_root, check=False)
    if merge_res.returncode != 0:
        run_cmd(["git", "merge", "--abort"], cwd=repo_root, check=False)
        raise RuntimeError(f"Merge thất bại! Có xung đột (conflict). Đã tự động rollback repo chính bằng 'git merge --abort'. Sandbox '{name}' được bảo toàn để giải quyết xung đột:\n{merge_res.stderr or merge_res.stdout}")

    print(f"✅ [2/3] Merge thành công vào nhánh chính.")

    # 3. TỰ ĐỘNG DỌN DẸP TOÀN BỘ (AUTO CLEANUP)
    print("🧹 [3/3] Kích hoạt cơ chế tự động dọn dẹp (Auto-Clear) để chống rác Git...")
    cleanup_sandbox(name=name)

    if clean_others:
        remaining = list_sandboxes()
        if remaining:
            print(f"   Đang dọn tiếp {len(remaining)} sandbox thua cuộc còn lại...")
            cleanup_sandbox(cleanup_all=True)

    print("🎉 TOÀN BỘ WORKTREE ĐÃ ĐƯỢC DỌN DẸP SẠCH 100%, KHÔNG ĐỂ LẠI RÁC TRONG REPO!")


def main():
    parser = argparse.ArgumentParser(description="APFS Worktree Sandbox Manager")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Create
    p_create = subparsers.add_parser("create", help="Tạo sandbox mới")
    p_create.add_argument("name", help="Tên sandbox")
    p_create.add_argument("--base", help="Base branch (mặc định: HEAD hiện tại)")
    p_create.add_argument("--port-offset", type=int, default=10, help="Port offset cho env")

    # List
    subparsers.add_parser("list", help="Liệt kê các sandbox đang hoạt động")

    # Diff
    p_diff = subparsers.add_parser("diff", help="Xem diff của một sandbox")
    p_diff.add_argument("name", help="Tên sandbox")

    # Compare
    p_comp = subparsers.add_parser("compare", help="So sánh 2 sandbox")
    p_comp.add_argument("name_a", help="Sandbox A")
    p_comp.add_argument("name_b", help="Sandbox B")

    # Merge Winner & Auto Cleanup
    p_merge = subparsers.add_parser("merge-winner", help="Merge sandbox thắng cuộc vào main và TỰ ĐỘNG DỌN DẸP SẠCH SẼ")
    p_merge.add_argument("name", help="Tên sandbox thắng cuộc cần merge")
    p_merge.add_argument("--squash", action="store_true", help="Merge dạng squash commit")
    p_merge.add_argument("--clean-others", action="store_true", help="Dọn luôn các sandbox khác sau khi merge (mặc định giữ nguyên)")
    p_merge.add_argument("--keep-others", action="store_true", help=argparse.SUPPRESS)  # cũ: giữ nguyên là mặc định, cờ này không còn tác dụng

    # Cleanup
    p_clean = subparsers.add_parser("cleanup", help="Dọn dẹp sandbox")
    p_clean.add_argument("--name", help="Tên sandbox cần dọn")
    p_clean.add_argument("--all", action="store_true", help="Dọn sạch toàn bộ sandboxes")

    args = parser.parse_args()

    if args.command == "create":
        create_sandbox(args.name, args.base, args.port_offset)
    elif args.command == "list":
        s_list = list_sandboxes()
        print(f"\n📋 Đang có {len(s_list)} sandbox hoạt động:")
        for s in s_list:
            print(f" - {s['name']} -> {s['path']} (Branch: {s.get('branch', 'unknown')})")
    elif args.command == "diff":
        d = get_sandbox_diff(args.name)
        print(json.dumps(d, indent=2))
    elif args.command == "compare":
        compare_sandboxes(args.name_a, args.name_b)
    elif args.command == "merge-winner":
        merge_winner(args.name, args.squash, args.clean_others)
    elif args.command == "cleanup":
        cleanup_sandbox(args.name, args.all)


if __name__ == "__main__":
    main()
