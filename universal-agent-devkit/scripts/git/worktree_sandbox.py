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
import tempfile
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


def _setup_copy(rel: str, s_path: Path, repo_root: Path, included: List[str]) -> bool:
    """An untracked file create_sandbox put in the sandbox and nobody changed (disposable): the recorded setup file .sandbox-env.sh, or a
    byte-identical copy of a .worktreeinclude file."""
    under_include = any(rel == i or rel.startswith(i + "/") for i in included)
    src, dst = Path(repo_root) / rel, Path(s_path) / rel
    return rel == ".sandbox-env.sh" or (under_include and src.is_file() and dst.is_file() and filecmp.cmp(src, dst, shallow=False))


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
        if line.startswith("??") and not rel.startswith('"') and _setup_copy(rel, s_path, repo_root, included):   # a quoted (odd) name never is
            continue
        left.append(line)
    # Review #12: file bị git ignore không hiện ở `status` trên, rmtree xoá mất bản duy nhất. Theo luật `worktree remove` / gc: file bí
    # mật bị ignore (`_ignored_secrets`, bỏ qua thư mục build/dependency) và file .worktreeinclude bị ignore là việc riêng khi khác bản ở
    # main; file ignore khác (build output, cache) vẫn bỏ được như trước.
    try:
        secrets, cut = _worktree_module()._ignored_secrets(str(s_path))
        inc = run_cmd(["git", "--literal-pathspecs", "ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--", *included],
                      cwd=s_path, check=False) if included else None
    except (Exception, SystemExit) as e:  # noqa: BLE001 - worktree.git(check=True) raises SystemExit
        return f"  (không liệt kê được file bị ignore của sandbox: {e})"
    if inc is not None and inc.returncode != 0:
        return f"  (git ls-files --ignored lỗi rc={inc.returncode}: {inc.stderr.strip()})"
    if cut:
        left.append(f"!! {cut} (thư mục bị ignore quá lớn, chưa đọc hết)")
    for rel in sorted({r for r, _p in secrets} | set(filter(None, (inc.stdout if inc else "").split("\0")))):
        src, dst = Path(repo_root) / rel, Path(s_path) / rel
        if not (src.is_file() and not src.is_symlink() and dst.is_file() and not dst.is_symlink() and filecmp.cmp(src, dst, shallow=False)):
            left.append(f"!! {rel} (bị ignore, khác bản ở main hoặc main không có)")
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
      automerge gộp HEAD đó về main, commit rời HEAD còn trong reflog mà `worktree remove` canh (review R1). Trade-off: worktree đó
      `checkout --detach sandbox/<x>` để xem thì sandbox cũng được dọn (cùng hình dạng với merge-winner fast-forward, không phân biệt
      được trừ khi tin subject reflog — agent ghi được); commit vẫn nằm trên HEAD của worktree đó, được gộp về main như mọi việc của nó.
    - Checkout chính tách rời: nhánh trunk (origin/HEAD, rồi main / master / trunk) phải có bản local, không theo HEAD —
      `checkout --detach sandbox/<x>` để xem thì HEAD chứa commit mà trunk chưa có, `git checkout main` là mất (QA SW6)."""
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
    if run_cmd(["git", "show-ref", "--verify", "-q", f"refs/heads/{trunk}"], cwd=repo_root, check=False).returncode != 0:
        return None, f"checkout chính đang ở HEAD tách rời và nhánh trunk {trunk} (origin/HEAD) không có bản local"
    return f"refs/heads/{trunk}", f"nhánh {trunk}"


def sandbox_unmerged_commits(s_path: Path, repo_root: Path, branch_name: str, branch_sha: Optional[str]) -> Optional[str]:
    """Vì sao chưa được xoá sandbox: nhánh của nó, HEAD riêng của nó, hoặc commit chỉ reflog HEAD của nó còn nêu tên, có commit mà
    `merged_into` (nhánh checkout đang đứng / HEAD của linked worktree tách rời / trunk khi checkout chính tách rời) chưa có; None khi không còn.
    - HEAD riêng và reflog HEAD của sandbox được đếm vì commit làm trên HEAD tách rời rồi quay lại nhánh, hay bị `reset --hard` bỏ đi, chỉ
      reflog đó còn giữ; gỡ đăng ký xoá reflog theo thư mục, `branch -d` xoá reflog của nhánh (QA F2: `worktree._reflog_only`
      với attached=False, vì reflog nhánh sandbox không sống sót qua cleanup). Thư mục đã mất mà đăng ký còn: HEAD và reflog đọc từ
      admin dir (#38).
    Fail closed: git không đọc/đếm được thì coi như còn việc, không bao giờ hiểu thành 0 (issue #12)."""
    base_ref, base_name = merged_into(repo_root)
    if not base_ref:
        return f"{base_name} — coi như còn commit chưa merge (chuyển checkout về nhánh rồi chạy lại)"
    if base_ref == f"refs/heads/{branch_name}":   # so nhánh với chính nó thì luôn "đã merge" (review)
        return f"checkout chạy lệnh đang đứng trên chính nhánh {branch_name}, không có mốc để so — coi như còn commit chưa merge (chuyển về nhánh khác rồi chạy lại)"
    revs = []
    if branch_sha:   # đúng SHA mà cleanup sẽ xoá (compare-and-delete), không đọc lại tên nhánh
        revs.append((f"nhánh {branch_name}", branch_sha))
    head_sha, admin = None, None
    if s_path.exists():
        head = run_cmd(["git", "rev-parse", "--verify", "HEAD"], cwd=s_path, check=False)
        if head.returncode != 0:
            return f"không đọc được HEAD của sandbox, không biết còn commit chưa merge không: {head.stderr.strip()}"
        head_sha = head.stdout.strip()
        revs.append(("HEAD của sandbox", head_sha))
    else:
        # #38: thư mục bị xoá tay mà git còn giữ đăng ký: HEAD và reflog HEAD trong admin dir vẫn có thể là thứ duy nhất giữ commit
        try:
            admin = _worktree_module()._admin_dir(str(repo_root), str(s_path))
        except (Exception, SystemExit) as e:  # noqa: BLE001 - worktree.git(check=True) raises SystemExit
            return f"không xác định được đăng ký worktree của sandbox (thư mục đã mất): {e}"
        if admin is None:
            return "không xác định được đăng ký worktree của sandbox (thư mục đã mất), không biết còn commit chưa merge không"
        if admin:
            head = run_cmd(["git", f"--git-dir={admin}", "rev-parse", "--verify", "HEAD"], cwd=repo_root, check=False)
            if head.returncode != 0:
                return f"không đọc được HEAD của sandbox (thư mục đã mất), không biết còn commit chưa merge không: {head.stderr.strip()}"
            head_sha = head.stdout.strip()
            revs.append(("HEAD của sandbox (thư mục đã mất)", head_sha))
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
            # thư mục đã mất: đọc reflog từ admin dir, mọi phép kiểm khác chỉ đọc object/ref chung nên chạy ở checkout chính
            lost = worktree._reflog_only(str(repo_root) if admin else str(s_path), head_sha, base_tip, sorted(set(refs)),
                                         attached=False, admin=admin or None)
        except (Exception, SystemExit) as e:  # noqa: BLE001 - worktree.git(check=True) raises SystemExit
            return f"không đọc được reflog HEAD của sandbox, không biết còn commit chưa merge không: {e}"
        if lost is None:
            return "không đọc được reflog HEAD của sandbox (hoặc repo có ref hỏng: chạy `git fsck`), không biết còn commit chưa merge không"
        if lost:
            return f"reflog HEAD của sandbox giữ {len(lost)} commit chưa merge mà không nhánh nào giữ (vd. {lost[0][:12]})"
    return None


def _head_reflog(s_path: Path) -> Optional[bytes]:
    """Nội dung file reflog HEAD của sandbox (đọc thẳng file: không cần HEAD còn trỏ commit — nhánh bị xoá giữa chừng thì HEAD
    unborn mà file vẫn đọc được); None khi thư mục / file không còn hoặc không đọc được (so bằng nhau vẫn đúng)."""
    if not s_path.exists():
        return None
    r = run_cmd(["git", "rev-parse", "--path-format=absolute", "--git-path", "logs/HEAD"], cwd=s_path, check=False)
    try:
        return Path(r.stdout.strip()).read_bytes() if r.returncode == 0 else None
    except OSError:
        return None


def _unregister(s_path: Path, repo_root: Path, force: bool) -> Optional[str]:
    """Gỡ đúng đăng ký worktree của sandbox (thư mục đã xoá: `git worktree remove` khi thư mục mất chỉ gỡ đăng ký). Không bao giờ
    `git worktree prune` toàn repo: nó xoá cả admin dir (reflog HEAD) của sandbox / worktree KHÁC đã mất thư mục, kể cả cái vừa bị từ
    chối, nên commit chỉ reflog đó giữ thành unreachable rồi bị gc (issue #12 / #38). None khi đã gỡ hoặc vốn không đăng ký; lý do khi còn."""
    try:
        wt = _worktree_module()
        if wt._admin_dir(str(repo_root), str(s_path)) == "":
            return None
        res = run_cmd(["git", "worktree", "remove", *(["--force", "--force"] if force else []), str(s_path)], cwd=repo_root, check=False)
        left = wt._admin_dir(str(repo_root), str(s_path))
    except (Exception, SystemExit) as e:  # noqa: BLE001 - worktree.git(check=True) raises SystemExit
        return f"không gỡ được đăng ký worktree của nó: {e}"
    if left == "":
        return None
    return f"đăng ký worktree của nó còn ({(res.stderr or '').strip() or 'không xác định được'}): kiểm rồi `git worktree remove {s_path}`"


def _ref_gone(repo_root: Path, ref: str) -> Optional[bool]:
    """True: `ref` đã mất; False: còn, kể cả symref treo (`rev-parse --verify` bỏ qua nó, #41); None: git không trả lời được.
    git < 2.43 không có `show-ref --exists` (rc 129): hỏi `symbolic-ref -q` rồi `rev-parse --verify --quiet`."""
    rc = run_cmd(["git", "show-ref", "--exists", ref], cwd=repo_root, check=False).returncode
    if rc in (0, 2):
        return rc == 2
    sym = run_cmd(["git", "symbolic-ref", "-q", ref], cwd=repo_root, check=False).returncode
    if sym != 1:
        return False if sym == 0 else None
    return {0: False, 1: True}.get(run_cmd(["git", "rev-parse", "--verify", "--quiet", ref], cwd=repo_root, check=False).returncode)


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
        tip = run_cmd(["git", "rev-parse", "--verify", "--quiet", f"refs/heads/{branch_name}^{{commit}}"], cwd=repo_root, check=False)
        branch_sha = tip.stdout.strip() if tip.returncode == 0 else None
        print(f"🧹 Dọn dẹp sandbox '{t}'...")
        reflog = _head_reflog(s_path)   # mốc để phát hiện commit / checkout chen vào trong lúc kiểm (review #12)
        if s_path.exists():
            unsaved = sandbox_unsaved_work(s_path, repo_root)
            if unsaved and not force:
                print(f"   ⚠ '{t}' còn việc chưa commit hoặc không đọc được trạng thái — giữ nguyên (thêm --force để xoá hẳn):\n{unsaved}")
                continue
        unmerged = None if force else sandbox_unmerged_commits(s_path, repo_root, branch_name, branch_sha)
        if unmerged:
            print(f"   ⚠ '{t}': {unmerged} — giữ nguyên sandbox và nhánh (merge trước, hoặc thêm --force để xoá hẳn).")
            continue
        if not force:   # cả khi nhánh đã mất: đăng ký bị khoá vẫn phải chặn (OCR)
            # update-ref không tự từ chối nhánh worktree khác đang checkout như `branch -d/-D` (HEAD đó thành unborn, OCR): kiểm TRƯỚC
            # rmtree để không còn thư mục mất mà nhánh còn (review). Đọc theo từng record (cách nhau dòng trống): `locked` / `prunable`
            # đứng SAU dòng `branch`. Đăng ký của chính sandbox bị khoá thì prune không gỡ → từ chối như `git worktree remove`;
            # đăng ký khác đã mất thư mục (prunable) không chặn.
            wl = run_cmd(["git", "worktree", "list", "--porcelain"], cwd=repo_root, check=False)
            blocked = None if wl.returncode == 0 else f"không đọc được danh sách worktree (rc={wl.returncode})"
            for rec in wl.stdout.split("\n\n"):
                lines = rec.splitlines()
                path = next((l[len("worktree "):] for l in lines if l.startswith("worktree ")), "")
                own = os.path.realpath(path) == os.path.realpath(str(s_path))
                inside = os.path.realpath(path).startswith(os.path.realpath(str(s_path)) + os.sep)
                flag = lambda name: any(l == name or l.startswith(name + " ") for l in lines)  # noqa: E731
                if own and flag("locked"):
                    blocked = "đăng ký worktree của sandbox đang bị khoá (`git worktree unlock` trước)"
                elif not own and f"branch refs/heads/{branch_name}" in lines and not flag("prunable"):
                    blocked = f"một worktree khác đang checkout nhánh {branch_name}"
                elif inside and not flag("prunable"):
                    # #41: worktree lồng dưới đường dẫn bị ignore thì `git status` của sandbox không thấy, rmtree xoá luôn việc của nó
                    blocked = f"worktree khác đăng ký lồng bên trong sandbox: {path} (gỡ nó trước)"
            if blocked:
                print(f"   ⚠ '{t}': {blocked} — giữ nguyên sandbox và nhánh.")
                continue
        if s_path.exists() and not force:
            # Review #12: các phép kiểm trên chậm (reflog, cherry, worktree list): kiểm lại ngay trước rmtree, để file / commit một agent
            # khác vừa thêm trong lúc đó không bị xoá theo thư mục
            # (nhánh vừa bị xoá thì HEAD unborn và `status` liệt kê mọi file là "A": bỏ phép kiểm file, reflog HEAD vẫn kiểm)
            head_ok = run_cmd(["git", "rev-parse", "-q", "--verify", "HEAD"], cwd=s_path, check=False).returncode == 0
            late = (sandbox_unsaved_work(s_path, repo_root) if head_ok else None) \
                or (None if _head_reflog(s_path) == reflog else "HEAD / reflog HEAD vừa đổi")
            if late:
                print(f"   ⚠ '{t}' vừa đổi trong lúc kiểm — giữ nguyên sandbox và nhánh:\n{late}")
                continue
        if s_path.exists():
            # Only the recorded setup files and disposable ignored files (or an explicit --force) are deleted here.
            try:
                shutil.rmtree(s_path)
            except OSError as e:
                print(f"   ✖ không xoá được {s_path}: {e} — giữ nguyên.")
                continue
        left = _unregister(s_path, repo_root, force)
        if left:
            print(f"   ⚠ đã xoá thư mục {t} nhưng {left} — giữ nhánh {branch_name}.")
            continue
        ref = f"refs/heads/{branch_name}"
        if force and branch_sha:
            res = run_cmd(["git", "branch", "-D", branch_name], cwd=repo_root, check=False)
        elif branch_sha:
            # Xoá đúng SHA đã kiểm theo merged_into: `-d` xét HEAD, lệch mốc khi checkout chính tách rời sau trunk (OCR); `-D` xoá luôn
            # commit agent khác vừa thêm vào nhánh sau bước kiểm (review) — nhánh đã đổi thì update-ref từ chối, nhánh được giữ.
            # --no-deref: nhánh sandbox là symref (vd. trỏ main) thì xoá chính symref, không xoá main qua nó (review).
            res = run_cmd(["git", "update-ref", "--no-deref", "-d", f"refs/heads/{branch_name}", branch_sha], cwd=repo_root, check=False)
            if res.returncode == 0:
                run_cmd(["git", "config", "--remove-section", f"branch.{branch_name}"], cwd=repo_root, check=False)   # upstream, nếu có
        else:
            # tên nhánh không trỏ commit nào: hoặc không có nhánh (chỉ có thư mục), hoặc symref treo / ref hỏng — xoá chính ref đó (#41)
            res = None if _ref_gone(repo_root, ref) is True else run_cmd(["git", "update-ref", "--no-deref", "-d", ref], cwd=repo_root, check=False)
        # Lỗi xoá chỉ tính là đã sạch khi nhánh chắc chắn đã mất; còn (kể cả symref treo) hay git không trả lời được thì giữ trong danh
        # sách chưa dọn (review, #41)
        if res is not None and res.returncode != 0 and _ref_gone(repo_root, ref) is not True:
            print(f"   ⚠ đã gỡ {t} nhưng giữ nhánh {branch_name} (nhánh đổi sau bước kiểm, hoặc git từ chối): {(res.stderr or '').strip()}")
            continue
        print(f"   ✓ Đã gỡ bỏ {t} và xoá nhánh {branch_name}.")
        done.append(t)

    kept = [t for t in targets if t not in done]
    if kept:
        # review R2: vừa từ chối thì không chốt "đã dọn"; exit code vẫn 0 (giữ hợp đồng CLI), danh sách này là kết quả
        print(f"⚠ Còn sandbox chưa dọn: {', '.join(kept)} (lý do ở dòng ⚠ / ✖ phía trên).")
    else:
        print("✅ Đã dọn dẹp hoàn tất toàn bộ rác Git worktree.")
    return kept


def _trunk_main(repo_root: Path, head_ref: str) -> bool:
    """U1 (audit 25/10): merge-winner would move the trunk branch of a repo in trunk mode (worktree.py `_trunk_mode`, the default) — the
    checkout it runs from (head_ref: its `git symbolic-ref HEAD`) stands on that branch, whichever checkout it is (review 25/10: a linked
    worktree on main merged straight into it; the main checkout on `feat` was sent to finish, which refuses any branch but the trunk).
    Main is merge-only: it moves through `worktree.py finish` alone. Another branch, or a detached HEAD (a session worktree): merged into
    as before. No trunk branch can be told (`_trunk_branch` None): the main checkout's branch is the trunk, as finish judges it."""
    wm = _worktree_module()
    main = wm.main_checkout(str(repo_root))
    if not wm._trunk_mode(main):
        return False
    trunk = wm._trunk_branch(main)
    if trunk:
        return head_ref == f"refs/heads/{trunk}"
    return bool(head_ref) and wm._same_path(main, str(repo_root))


def _finish_into_main(name: str, s_path: Path, repo_root: Path) -> None:
    """U1: hand the sandbox to `worktree.py finish <sandbox> --keep` (the merge gate on what it brings, then a fast-forward of main under
    finish's lock): reused, not rewritten. finish refuses any untracked file, and the setup files create_sandbox wrote are no work
    (_setup_copy): they are moved aside for that run and put back after it, whatever it answered. finish refusing raises (main unchanged)."""
    included = [i.rstrip("/") for i in parse_worktree_include(repo_root)]
    status = run_cmd(["git", "status", "--porcelain", "-uall"], cwd=s_path, check=False)
    if status.returncode != 0:
        raise RuntimeError(f"Không merge sandbox '{name}': git status lỗi rc={status.returncode}: {status.stderr.strip()}")
    setup = [l[3:].strip() for l in status.stdout.splitlines()
             if l.startswith("??") and not l[3:].strip().startswith('"') and _setup_copy(l[3:].strip(), s_path, repo_root, included)]
    hold = Path(tempfile.mkdtemp(prefix=f"sandbox-{name}-setup."))
    moved = []
    try:
        for rel in setup:
            (hold / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(s_path / rel), str(hold / rel))
            moved.append(rel)
        finish = subprocess.run([sys.executable, str(Path(__file__).resolve().parent / "worktree.py"), "finish", str(s_path), "--keep"],
                                cwd=str(repo_root), capture_output=True, text=True)
    finally:
        for rel in moved:   # back in place: cleanup judges them disposable, and a sandbox finish refused stays whole
            (s_path / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(hold / rel), str(s_path / rel))
        shutil.rmtree(hold, ignore_errors=True)
    said = (finish.stdout + finish.stderr).strip()
    if said:
        print("   " + said.replace("\n", "\n   "))
    if finish.returncode != 0:
        raise RuntimeError(f"Không merge sandbox '{name}': trunk mode — main chỉ đi qua `agent-kit worktree finish`, và finish từ chối "
                           f"(lý do ở dòng trên, rc={finish.returncode}). Main không đổi, sandbox giữ nguyên: sửa trong sandbox rồi chạy lại.")


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
       - Gỡ đúng đăng ký của sandbox được dọn trong .git/worktrees/ — không `git worktree prune` toàn repo (issue #12 / #38).
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

    # Merge vào đúng mốc cleanup sẽ xét (merged_into): checkout chính tách rời thì merge chỉ nằm trên HEAD tách rời (`git checkout main`
    # là bỏ rơi), cleanup giữ sandbox rồi gợi ý --force → từ chối trước khi đổi gì (review rebuild 2).
    base_ref, base_name = merged_into(repo_root)
    head_ref = run_cmd(["git", "symbolic-ref", "-q", "HEAD"], cwd=repo_root, check=False).stdout.strip()
    if head_ref == f"refs/heads/{branch_name}":   # merge vào chính nó: không gì vào nhánh chính (review)
        raise RuntimeError(f"Không merge sandbox '{name}': checkout đang đứng trên chính nhánh {branch_name}. Chuyển về nhánh chính rồi chạy lại.")
    if base_ref not in ("HEAD", head_ref):
        why = base_name if not base_ref else f"checkout chính đang ở HEAD tách rời, merge sẽ chỉ nằm trên HEAD đó, không vào {base_name}"
        raise RuntimeError(f"Không merge sandbox '{name}': {why}. Chuyển checkout về nhánh (`git checkout <nhánh>`) rồi chạy lại.")

    # U1 (audit 25/10): trunk mode, the checkout stands on the trunk branch — main is merge-only, `worktree finish` is its one door (merge
    # gate, then a fast-forward). The sandbox is handed to it instead of `git merge` here. Not known whether trunk mode is on: nothing is merged.
    try:
        trunk_main = _trunk_main(repo_root, head_ref)
    except (Exception, SystemExit) as e:  # noqa: BLE001 - worktree.git(check=True) raises SystemExit
        raise RuntimeError(f"Không merge sandbox '{name}': không xác định được checkout này có phải main ở trunk mode không ({e}); không đổi gì.")
    if trunk_main and squash:
        raise RuntimeError(f"Không merge sandbox '{name}' với --squash: trunk mode — main chỉ đi qua `agent-kit worktree finish`, mà finish không "
                           f"squash. Chạy lại không có --squash (hoặc tự gộp commit trong sandbox trước).")

    # 2. Merge vào main repo
    if trunk_main:
        print(f"🔄 [1/3] Trunk mode: giao sandbox '{name}' cho `agent-kit worktree finish {sandbox_path}` (gate gộp, rồi fast-forward main)...")
        _finish_into_main(name, sandbox_path, repo_root)
    else:
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
