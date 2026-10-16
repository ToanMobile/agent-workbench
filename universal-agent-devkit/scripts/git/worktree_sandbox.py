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
import filecmp
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

    if not source.is_dir():
        # A file (.env, keystore.properties, ...): shutil.copy keeps content + mode only. cp -c (clonefile) and copy2 keep macOS user flags,
        # so a keystore the user locked with `chflags uchg` became a copy the sandbox could never delete (tests/worktree_git/test_worktree_immutable_copy.sh)
        old_umask = os.umask(0o077)   # shutil.copy creates the file with the umask's mode and fixes it afterwards: a secret is never readable by others in between
        try:
            shutil.copy(source, target)
        finally:
            os.umask(old_umask)
        return True

    if sys.platform == "darwin":
        # Trên macOS, dùng /bin/cp -c (clonefile)
        target.mkdir(parents=True, exist_ok=True)
        res = subprocess.run(["/bin/cp", "-c", "-R", f"{source}/.", str(target)], capture_output=True, text=True, timeout=120)
        if res.returncode == 0:
            # cp -c -R keeps the user flags too (a jks locked with `chflags uchg` inside a signing/ folder): clear them or the sandbox can never be cleaned.
            # -R does not follow links; a failure shows up at cleanup, which names the file it cannot delete
            subprocess.run(["chflags", "-R", "nouchg,nouappnd", str(target)], capture_output=True, text=True, timeout=120)
            return True

    # Fallback tiêu chuẩn
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, symlinks=True, copy_function=shutil.copy)   # not the default copy2: it keeps the flags
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


def sandbox_unsaved_work(s_path: Path, repo_root: Path) -> Optional[str]:
    """Why this sandbox must not be deleted silently, or None when only disposable setup files are left.
    Fail closed: an unreadable status (broken worktree admin dir, a folder that is not a worktree) is unsaved work."""
    top = run_cmd(["git", "rev-parse", "--show-toplevel"], cwd=s_path, check=False)
    if top.returncode != 0 or os.path.realpath(top.stdout.strip()) != os.path.realpath(str(s_path)):
        return "  (không đọc được git status của sandbox này: không phải worktree hợp lệ)"
    proc = run_cmd(["git", "status", "--porcelain", "-uall"], cwd=s_path, check=False)
    if proc.returncode != 0:
        return f"  (git status lỗi rc={proc.returncode}: {proc.stderr.strip()})"
    included = [i.rstrip("/") for i in parse_worktree_include(repo_root)]   # copied in by create_sandbox
    left = []
    for line in proc.stdout.splitlines():
        rel = line[3:].strip()
        if line.startswith("??") and not rel.startswith('"'):   # a quoted (odd) name is never assumed disposable
            under_include = any(rel == i or rel.startswith(i + "/") for i in included)
            src, dst = Path(repo_root) / rel, Path(s_path) / rel
            # Disposable only when it is the recorded setup file, or a byte-identical copy of an included file.
            if rel == ".sandbox-env.sh" or (under_include and src.is_file() and dst.is_file()
                                            and filecmp.cmp(src, dst, shallow=False)):
                continue
        left.append(line)
    return "\n".join(left) or None


def _worktree_module():
    """worktree.py nằm cạnh file này (scripts/git/): tái dùng `_reflog_only`, `_trunk_branch` thay vì viết lại."""
    here = str(Path(__file__).resolve().parent)
    if here not in sys.path:
        sys.path.insert(0, here)
    import worktree  # noqa: PLC0415
    return worktree


def merged_into(repo_root: Path) -> Tuple[Optional[str], str]:
    """(ref, tên) mà commit của sandbox phải nằm trong mới tính là đã merge; (None, lý do) khi không biết (fail closed).
    - Checkout chạy lệnh đang ở nhánh: nhánh đó (nhánh merge-winner merge vào).
    - Linked worktree tách rời (worktree phiên, trunk mode mặc định): HEAD của nó — git gc giữ HEAD mọi worktree, `worktree finish` /
      automerge gộp HEAD đó về main, commit rời HEAD còn trong reflog mà `worktree remove` canh (review R1).
    - Checkout chính tách rời: nhánh trunk (origin/HEAD, rồi main / master / trunk), không theo HEAD — `checkout --detach sandbox/<x>`
      để xem thì HEAD chứa commit mà trunk chưa có, `git checkout main` là mất (QA SW6)."""
    head = run_cmd(["git", "symbolic-ref", "-q", "HEAD"], cwd=repo_root, check=False)
    ref = head.stdout.strip()
    if head.returncode == 0 and ref.startswith("refs/heads/"):
        return ref, f"nhánh {ref[len('refs/heads/'):]}"
    dirs = run_cmd(["git", "rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir"], cwd=repo_root, check=False)
    paths = dirs.stdout.splitlines()
    if dirs.returncode != 0 or len(paths) != 2:
        return None, f"không đọc được git-dir của checkout này (rc={dirs.returncode}: {dirs.stderr.strip()})"
    if os.path.realpath(paths[0]) != os.path.realpath(paths[1]):
        return "HEAD", "HEAD của worktree này"
    try:
        trunk = _worktree_module()._trunk_branch(str(repo_root))
    except (Exception, SystemExit) as e:  # noqa: BLE001 - worktree.git(check=True) raises SystemExit
        return None, f"checkout chính đang ở HEAD tách rời, không xác định được nhánh trunk: {e}"
    if not trunk:
        return None, "checkout chính đang ở HEAD tách rời và không có nhánh trunk (origin/HEAD, main, master, trunk)"
    return f"refs/heads/{trunk}", f"nhánh {trunk}"


def sandbox_unmerged_commits(s_path: Path, repo_root: Path, branch_name: str) -> Optional[str]:
    """Vì sao chưa được xoá sandbox: nhánh của nó, HEAD riêng của nó, hoặc commit chỉ reflog HEAD của nó còn nêu tên, có commit mà
    `merged_into` (nhánh checkout đang đứng / HEAD của linked worktree tách rời / trunk khi checkout chính tách rời) chưa có; None khi không còn.
    - HEAD riêng và reflog HEAD của sandbox được đếm vì commit làm trên HEAD tách rời rồi quay lại nhánh, hay bị `reset --hard` bỏ đi, chỉ
      reflog đó còn giữ; `git worktree prune` xoá reflog theo thư mục, `branch -d` xoá reflog của nhánh (QA F2: `worktree._reflog_only`
      với attached=False, vì reflog nhánh sandbox không sống sót qua cleanup).
    Fail closed: git không đọc/đếm được thì coi như còn việc, không bao giờ hiểu thành 0 (issue #12)."""
    base_ref, base_name = merged_into(repo_root)
    if not base_ref:
        return f"{base_name} — coi như còn commit chưa merge (chuyển checkout về nhánh rồi chạy lại)"
    revs = []
    if run_cmd(["git", "rev-parse", "--verify", "--quiet", f"refs/heads/{branch_name}"], cwd=repo_root, check=False).returncode == 0:
        revs.append((f"nhánh {branch_name}", branch_name))
    head_sha = None
    if s_path.exists():
        head = run_cmd(["git", "rev-parse", "--verify", "HEAD"], cwd=s_path, check=False)
        if head.returncode != 0:
            return f"không đọc được HEAD của sandbox, không biết còn commit chưa merge không: {head.stderr.strip()}"
        head_sha = head.stdout.strip()
        revs.append(("HEAD của sandbox", head_sha))
    for label, rev in revs:
        proc = run_cmd(["git", "rev-list", "--count", f"{base_ref}..{rev}"], cwd=repo_root, check=False)
        count = proc.stdout.strip()
        if proc.returncode != 0 or not count.isdigit():
            return f"không đếm được commit chưa merge của {label} (rc={proc.returncode}: {proc.stderr.strip()})"
        if count != "0":
            return f"{label} giữ {count} commit chưa merge vào {base_name}"
    if head_sha:
        try:
            worktree = _worktree_module()
            base_tip = run_cmd(["git", "rev-parse", "--verify", f"{base_ref}^{{commit}}"], cwd=repo_root).stdout.strip()
            refs = run_cmd(["git", "for-each-ref", "--format=%(objectname)", "refs/heads", "refs/remotes", "refs/tags"], cwd=repo_root).stdout.split()
            lost = worktree._reflog_only(str(s_path), head_sha, base_tip, sorted(set(refs)), attached=False)
        except (Exception, SystemExit) as e:  # noqa: BLE001 - worktree.git(check=True) raises SystemExit
            return f"không đọc được reflog HEAD của sandbox, không biết còn commit chưa merge không: {e}"
        if lost is None:
            return "không đọc được reflog HEAD của sandbox (hoặc repo có ref hỏng: chạy `git fsck`), không biết còn commit chưa merge không"
        if lost:
            return f"reflog HEAD của sandbox giữ {len(lost)} commit chưa merge mà không nhánh nào giữ (vd. {lost[0][:12]})"
    return None


def cleanup_sandbox(name: Optional[str] = None, cleanup_all: bool = False, force: bool = False) -> List[str]:
    """Dọn dẹp worktree an toàn. Sandbox còn file chưa commit, hoặc nhánh / HEAD của nó còn commit chưa merge, được GIỮ NGUYÊN cả thư mục
    lẫn nhánh trừ khi force=True: cả hai đều được kiểm TRƯỚC khi xoá thư mục. Trả về tên các sandbox chưa dọn xong (đã in lý do)."""
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
        return []

    done = []
    for t in targets:
        s_path = sandboxes_dir / t
        branch_name = f"sandbox/{t}"
        print(f"🧹 Dọn dẹp sandbox '{t}'...")
        if s_path.exists():
            unsaved = sandbox_unsaved_work(s_path, repo_root)
            if unsaved and not force:
                print(f"   ⚠ '{t}' còn việc chưa commit hoặc không đọc được trạng thái — giữ nguyên (thêm --force để xoá hẳn):\n{unsaved}")
                continue
        unmerged = None if force else sandbox_unmerged_commits(s_path, repo_root, branch_name)
        if unmerged:
            print(f"   ⚠ '{t}': {unmerged} — giữ nguyên sandbox và nhánh (merge trước, hoặc thêm --force để xoá hẳn).")
            continue
        if s_path.exists():
            # Only the recorded setup files and ignored files (or an explicit --force) are deleted here.
            try:
                shutil.rmtree(s_path)
            except OSError as e:
                print(f"   ✖ không xoá được {s_path}: {e} — giữ nguyên.")
                continue
        run_cmd(["git", "worktree", "prune"], cwd=repo_root, check=False)
        # -D: sandbox_unmerged_commits ở trên đã kiểm theo merged_into; `-d` xét HEAD, lệch base khi checkout chính tách rời
        # ở commit khác trunk → thư mục đã xoá mà nhánh còn (OCR)
        res = run_cmd(["git", "branch", "-D", branch_name], cwd=repo_root, check=False)
        if res.returncode != 0 and "not found" not in (res.stderr or ""):
            print(f"   ⚠ đã gỡ {t} nhưng chưa xoá được nhánh {branch_name}: {(res.stderr or '').strip()}")
            continue
        print(f"   ✓ Đã gỡ bỏ {t} và xoá nhánh {branch_name}.")
        done.append(t)

    run_cmd(["git", "worktree", "prune"], cwd=repo_root, check=False)
    kept = [t for t in targets if t not in done]
    if kept:
        # review R2: vừa từ chối thì không chốt "đã dọn"; exit code vẫn 0 (giữ hợp đồng CLI), danh sách này là kết quả
        print(f"⚠ Còn sandbox chưa dọn: {', '.join(kept)} (lý do ở dòng ⚠ / ✖ phía trên).")
    else:
        print("✅ Đã dọn dẹp hoàn tất toàn bộ rác Git worktree.")
    return kept


def merge_winner(name: str, squash: bool = False, clean_others: bool = False) -> None:
    """
    Merge sandbox thắng cuộc vào main branch và TỰ ĐỘNG DỌN DẸP SẠCH SẼ.
    1. Kiểm tra sandbox tồn tại và sạch sẽ (không còn uncommitted dirty files).
    2. Lấy tên branch chính (main hoặc base branch).
    3. Thực hiện merge từ sandbox branch vào main branch.
    4. Ngay khi merge thành công:
       - TỰ ĐỘNG dọn dẹp sandbox thắng cuộc: gỡ worktree, xóa folder, xóa branch.
       - Chỉ khi có cờ --clean-others mới dọn các sandbox khác (mặc định GIỮ NGUYÊN: chúng có thể còn việc chưa merge); kể cả khi đó,
         sandbox còn việc chưa commit hoặc commit chưa merge vẫn được giữ (xoá hẳn: `cleanup --name <x> --force` sau khi tự kiểm).
       - Chạy git worktree prune để dọn dẹp sạch sẽ 100% trong .git/worktrees/.
    """
    repo_root = get_repo_root()
    sandbox_path = repo_root / ".sandboxes" / name
    if not sandbox_path.exists():
        raise RuntimeError(f"Không tìm thấy sandbox '{name}' để merge.")

    # 1. Kiểm tra việc chưa commit (file tracked sửa, file mới chưa add) hoặc trạng thái không đọc được
    unsaved = sandbox_unsaved_work(sandbox_path, repo_root)
    if unsaved:
        raise RuntimeError(
            f"Sandbox '{name}' đang có việc chưa commit. Hãy commit (git add cả file mới) hoặc bỏ đi trước khi merge:\n{unsaved}"
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
    winner_kept = bool(cleanup_sandbox(name=name))

    if clean_others:
        remaining = list_sandboxes()
        if remaining:
            print(f"   Đang dọn tiếp {len(remaining)} sandbox thua cuộc còn lại...")
            cleanup_sandbox(cleanup_all=True)

    if squash:
        # A squash merge leaves the change staged (not committed) and creates no ancestry, so the
        # sandbox and its branch still look unmerged and are kept.
        print(f"⚠ Squash: thay đổi mới ở trạng thái staged. Commit nó rồi chạy `cleanup --name {name} --force` để xoá sandbox và nhánh {branch_name}.")
    elif winner_kept:
        # cleanup vừa từ chối (lý do in ở dòng ⚠ phía trên): merge xong không có nghĩa là đã dọn
        print(f"⚠ Đã merge {branch_name} nhưng chưa dọn sandbox '{name}' (xem lý do phía trên); tự kiểm rồi `cleanup --name {name} --force` nếu muốn xoá hẳn.")
    else:
        print("🎉 Đã merge và dọn sandbox thắng cuộc." + ("" if clean_others else " Sandbox khác (nếu có) được giữ nguyên."))


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
    p_merge.add_argument("--clean-others", action="store_true", help="Dọn luôn các sandbox khác sau khi merge (mặc định giữ nguyên; sandbox còn việc chưa commit / commit chưa merge vẫn được giữ)")
    p_merge.add_argument("--keep-others", action="store_true", help=argparse.SUPPRESS)  # cũ: giữ nguyên là mặc định, cờ này không còn tác dụng

    # Cleanup
    p_clean = subparsers.add_parser("cleanup", help="Dọn dẹp sandbox")
    p_clean.add_argument("--name", help="Tên sandbox cần dọn")
    p_clean.add_argument("--all", action="store_true", help="Dọn sạch toàn bộ sandboxes")
    p_clean.add_argument("--force", action="store_true", help="Xoá cả sandbox còn thay đổi chưa commit và nhánh chưa merge (mất việc)")

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
        cleanup_sandbox(args.name, args.all, args.force)


if __name__ == "__main__":
    main()
