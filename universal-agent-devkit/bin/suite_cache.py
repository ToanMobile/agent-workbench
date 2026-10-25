#!/usr/bin/env python3
"""Cache PASS theo KHOÁ NỘI DUNG của từng suite hồi quy (P2, 20/10), dùng chung mọi worktree của một repo.

Khoá = sha256 của: định dạng cache + cách gate đọc kết quả (RESULT_FORMAT), id, lệnh, untested_exit, mục ma trận của CHÍNH suite (mọi
rule có id đó, nguyên văn; covers; version của ma trận — B8 25/10, không còn digest cả file ma trận), nội dung (blob sha) của mọi
input của suite, trạng thái cục bộ (local_state_sha của gate), biến môi trường chọn test, môi trường máy (OS, phiên bản công cụ lệnh
dùng). Input (bảo thủ — thừa thì chỉ giảm số lần dùng lại, thiếu mới hạ chất lượng):
  a. file khớp watch_files + covers của mọi rule có suite này;
  b. file lệnh nêu tên (theo `cd` của nó); `cd D &&` ⇒ mọi file dưới D;
  c. bao đóng tĩnh ≤ 3 cấp / ≤ 2000 file của các script đó: đường dẫn nhắc tới (chính xác, theo thư mục file, hoặc theo đuôi đường dẫn),
     `import X` của python ⇒ mọi X.py;
  d. đường dẫn đi qua symlink ra ngoài cây (.agents/devkit, .agents/active-profile) ⇒ băm bytes của đích thật;
  e. input học được ở P3 (learned_inputs.json, chỉ thêm);
  f. danger list: đổi một file trong đó là đổi mọi khoá.
Kho: <git common dir>/postfix-gate/suite_cache/<khoá>.json {pass_n, fail_n, …}. HIT ⇔ pass_n ≥ 1, fail_n = 0, chưa quá tuổi, đúng id
và lệnh, id không bị cách ly. FAIL là vĩnh viễn với khoá đó (một PASS chạy đua không bao giờ xoá được nó). Chỉ một lượt chạy THẬT lệnh
đầy đủ của suite mới được ghi. Thư viện chuẩn, không phụ thuộc gate (post-fix-gate.py và stale_rerun.py cùng dùng).
"""

from __future__ import annotations

import bisect
import contextlib
import errno
import fcntl
import fnmatch
import hashlib
import json
import os
import platform
import re
import stat
import subprocess
import sys
import tempfile
import time

SUITE_CACHE_FORMAT = 1
MATRIX_KEY_FORMAT = 1            # cách phần ma trận vào khoá (B8 25/10: mục của chính suite, không digest cả file); đổi cách đó thì tăng số
MAX_AGE_S = 6 * 3600             # DEVKIT_SUITE_CACHE_MAX_S: tuổi tối đa của một PASS được dùng lại (= DEVKIT_GATE_CACHE_MAX_S của biên nhận)
PRUNE_EVERY_S = 3600             # dọn kho tối đa một lần mỗi giờ (mốc prune.stamp)
STORE_MAX = 4000                 # bản ghi giữ lại tối đa; cũ hơn STORE_MAX_AGE_S thì xoá khi dọn
STORE_MAX_AGE_S = 7 * 86400
FAIL_MAX_AGE_S = 30 * 86400      # bản ghi có FAIL không bị dọn theo số lượng, chỉ theo tuổi này (FAIL là vĩnh viễn với khoá đó)
QUARANTINE_S = 7 * 86400         # DEVKIT_FLAKY_QUARANTINE_S
CLOSURE_DEPTH = 3
CLOSURE_MAX_FILES = 2000
DIR_EXPAND_MAX = 200             # token chỉ tới thư mục: lấy mọi file dưới nó khi không quá số này
SCAN_MAX_BYTES = 1_000_000
BIG_FILE_BYTES = 8 << 20         # như tree_fp: file lớn hơn thì băm theo kích thước + mtime
# Đổi một file khớp danger list là đổi khoá của MỌI suite (bảo thủ: thư viện test dùng chung, mã của gate/hook, ma trận).
DANGER = ("**/tests/lib/**", "tests/lib/**", "**/clean_git_env.sh",
          "universal-agent-devkit/bin/post-fix-gate.py", "universal-agent-devkit/bin/heavy_slot.py",
          "universal-agent-devkit/bin/capacity.py",   # mặc định song song / ngưỡng tải của gate, heavy_slot và run_impacted (T0052)
          "universal-agent-devkit/bin/suite_cache.py", "universal-agent-devkit/bin/tree_fp.py",
          "universal-agent-devkit/bin/regression_checklist.py", "universal-agent-devkit/hooks/**",
          # config mà công cụ đọc ngầm, không lệnh nào nêu tên (review 20/10)
          "**/conftest.py", "conftest.py", "pyproject.toml", "**/pyproject.toml", "pytest.ini", "setup.cfg", "tox.ini",
          "**/package.json", "package.json", "**/tsconfig*.json", "tsconfig*.json", "**/*.gradle", "**/*.gradle.kts", "*.gradle",
          "*.gradle.kts", "gradle.properties", "**/gradle.properties", "gradle/libs.versions.toml",
          # lockfile, config runner và pin phiên bản: công cụ đọc ngầm, không lệnh nào nêu tên (issue #151)
          "**/package-lock.json", "**/npm-shrinkwrap.json", "**/yarn.lock", "**/pnpm-lock.yaml", "**/uv.lock", "**/poetry.lock",
          "**/Pipfile.lock", "**/Cargo.lock", "**/go.sum", "**/requirements*.txt",
          "**/jest.config.*", "**/vitest.config.*", "**/vitest.workspace.*", "**/babel.config.*", "**/.babelrc*", "**/.mocharc*",
          "**/.nvmrc", "**/.node-version", "**/.python-version", "**/.tool-versions")
# Khớp DANGER mà không phải input của suite nào: chỉ xếp thứ tự test cho run_impacted.sh (suite đó không cache theo khoá),
# mỗi test DevKit mới thêm một dòng ⇒ đổi khoá của MỌI suite (issue #315).
DANGER_EXEMPT = ("tests/lib/test_durations.txt",)
# Suite không cache theo khoá: chọn test theo lịch sử git / đồng hồ (run_impacted.sh), hoặc đọc mạng ngay trong lệnh.
DIFF_DEPENDENT = re.compile(r"(?:^|[\s/;&|(])run_impacted\.sh\b")
# Ngoại lệ có điều kiện (#344): đúng `bash <đường dẫn>/run_impacted.sh [--all]` của CHÍNH DevKit (script có dòng SELECTION_MARK: `--list` chỉ in
# tập test được chọn, không chạy gì) được cache theo khoá cả cây + tập `--list` in ra. Script trùng tên của dự án khác có thể chạy test ngay
# khi bị hỏi `--list`: không dấu thì không hỏi, không cache.
SELECTION_CMD = re.compile(r"^\s*bash\s+(?:\./)?((?:[\w.-]+/)*run_impacted\.sh)(?:\s+--all)?\s*$")
SELECTION_MARK = "devkit-selection-list:"
SELECTION_TIMEOUT_S = 60
NETWORK = re.compile(r"\b(?:curl|wget)\b[^\n;|&]*\bhttps?://|\bnpx\s+(?:-y|--yes)\b|\bnpm\s+(?:i|install|ci)\b|\bpip3?\s+install\b"
                     r"|\buv\b[^\n;|&]*\s--with\b|\bgit\s+(?:clone|fetch|ls-remote|pull)\b[^\n;|&]*(?:https?://|git@|ssh://)")
_SCAN_EXT = {".sh", ".bash", ".zsh", ".py", ".js", ".mjs", ".cjs", ".ts", ""}
_PATH_TOKEN = re.compile(r"[\w.@+-]+(?:/[\w.@+-]+)+|[\w@+-][\w.@+-]*\.[A-Za-z][A-Za-z0-9]{0,5}\b")
_PY_IMPORT = re.compile(r"^\s*(?:from\s+([\w.]+)\s+import\b|import\s+([\w., ]+))", re.M)
_TOOLS = {"python": ("python3", "--version"), "node": ("node", "--version"), "npm": ("node", "--version"),
          "npx": ("node", "--version"), "uv": ("uv", "--version"), "gradle": ("java", "-version"), "gradlew": ("java", "-version"),
          "go": ("go", "version"), "cargo": ("cargo", "--version")}
_TOOL_VERSIONS = {}


def _env_float(name, default):
    try:
        v = float(os.environ.get(name, "") or default)
    except ValueError:
        return float(default)
    return v if v == v and 0 <= v != float("inf") else float(default)


def match(path, pat):
    """Cùng luật với post-fix-gate.match_pattern: fnmatch; `**/x` khớp cả `x` ở gốc."""
    pat = pat.replace("\\", "/")
    return fnmatch.fnmatch(path, pat) or (pat.startswith("**/") and fnmatch.fnmatch(path, pat[3:]))


def _git(project_dir, *args, input_=None):
    return subprocess.run(["git", "-C", str(project_dir), *args], capture_output=True, input=input_, timeout=120)


def _blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


_SIBLINGS = []


def _sibling(name):
    """Module anh em trong bin/ (tree_fp, regression_checklist), nạp một lần; bin/ vào sys.path đúng một lần."""
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)
    return __import__(name)


def _excluded(rel):
    """Đường dẫn tree_fp bỏ khỏi dấu vân tay (sổ của gate, evidence, reports/): không phải input của suite."""
    if not _SIBLINGS:
        ex = _sibling("tree_fp").EXCLUDE
        _SIBLINGS.append(([e for e in ex if "[" not in e], [e for e in ex if "[" in e]))
    plain, globs = _SIBLINGS[0]
    return any(rel == e or rel.startswith(e + "/") for e in plain) or any(fnmatch.fnmatch(rel, e) for e in globs)


def content_map(project_dir) -> dict:
    """{đường dẫn tương đối project_dir: "mode sha"} của nội dung đang có: file của HEAD (blob sha của git) cộng file sửa / chưa track
    (blob sha tính lại từ bytes đang có, cùng công thức của git: cùng nội dung ⇒ cùng giá trị dù đã commit hay chưa). File bị
    ignore và EXCLUDE của tree_fp (sổ của gate, evidence, reports/) không có. None khi git không trả lời."""
    out = _ls_tree(project_dir, "HEAD")
    if out is None:
        return None
    changed = _git(project_dir, "diff", "--name-only", "-z", "--relative", "--no-renames", "HEAD")
    others = _git(project_dir, "ls-files", "-z", "--others", "--exclude-standard")
    if changed.returncode != 0 or others.returncode != 0:
        return None
    names = {p for blob in (changed.stdout, others.stdout) for p in blob.decode("utf-8", "surrogateescape").split("\0") if p}
    for rel in names:
        full = os.path.join(str(project_dir), rel)
        try:
            st = os.lstat(full)
        except OSError:
            out.pop(rel, None)   # xoá khỏi cây
            continue
        if os.path.islink(full):
            out[rel] = "120000 " + _blob_sha(os.fsencode(os.readlink(full)))
        elif not os.path.isfile(full):
            out[rel] = "dir ?"   # submodule / repo lồng có thay đổi: giá trị không bao giờ trùng nội dung đã PASS
        elif st.st_size >= BIG_FILE_BYTES:
            out[rel] = f"big {st.st_size}:{st.st_mtime_ns}"
        else:
            try:
                with open(full, "rb") as f:
                    out[rel] = f"{'100755' if st.st_mode & 0o111 else '100644'} {_blob_sha(f.read())}"
            except OSError:
                out[rel] = "unreadable ?"
    return {p: v for p, v in out.items() if not _excluded(p)}


def _ls_tree(project_dir, ref):
    """{đường dẫn: "mode sha"} của nội dung đã commit ở ref; None khi git không trả lời."""
    tree = _git(project_dir, "ls-tree", "-r", "-z", ref)
    if tree.returncode != 0:
        return None
    out = {}
    for rec in tree.stdout.decode("utf-8", "surrogateescape").split("\0"):
        if "\t" not in rec:
            continue
        meta, rel = rec.split("\t", 1)
        mode, _typ, sha = meta.split()
        out[rel] = f"{mode} {sha}"
    return out


def content_map_at(project_dir, ref):
    """content_map của nội dung ĐÃ COMMIT ở ref (không có file sửa / chưa track), cùng định dạng và cùng bỏ EXCLUDE: khoá cả cây tính
    trên nó trùng khoá cả cây của một lượt chạy trên checkout sạch ở ref. None khi git không trả lời."""
    out = _ls_tree(project_dir, ref)
    return None if out is None else {p: v for p, v in out.items() if not _excluded(p)}


def tree_digest(cmap) -> str:
    """sha256 của content_map (mọi file của cây, đã bỏ EXCLUDE): gate so trước/sau các suite để biết cây có đổi trong lúc chạy."""
    t = hashlib.sha256()
    for p in sorted(cmap):
        t.update(os.fsencode(p) + b"\0" + cmap[p].encode() + b"\0")
    return t.hexdigest()


class Index:
    """Tra cứu đường dẫn trong content_map: chính xác, theo basename (cho khớp theo đuôi đường dẫn), theo pattern (nhớ kết quả)."""

    def __init__(self, cmap):
        self.cmap = cmap
        self.by_base = {}
        self.dirs = set()
        for p in cmap:
            self.by_base.setdefault(os.path.basename(p), []).append(p)
            d = os.path.dirname(p)
            while d and d not in self.dirs:
                self.dirs.add(d)
                d = os.path.dirname(d)
        self._pat = {}
        self._sorted = sorted(cmap)
        self.skips = 0   # số lần resolve bỏ một thư mục lớn hơn DIR_EXPAND_MAX: khoá chính xác thiếu input
        self.refs_memo = {}   # _file_refs theo Index này (không theo id(): id được cấp lại sau GC — OCR 20/10)

    def glob(self, pat):
        if pat not in self._pat:
            stop = min([i for i in (pat.find("*"), pat.find("?"), pat.find("[")) if i >= 0] or [len(pat)])
            prefix = pat[:stop] if not pat.startswith("**/") else ""
            lo = bisect.bisect_left(self._sorted, prefix)
            hi = bisect.bisect_left(self._sorted, prefix + "\U0010ffff") if prefix else len(self._sorted)
            self._pat[pat] = frozenset(p for p in self._sorted[lo:hi] if match(p, pat))
        return self._pat[pat]

    def under(self, d):
        d = d.rstrip("/") + "/"
        return self.glob(d + "*")

    def resolve(self, tok, here):
        """Đường dẫn trong cây mà token có thể chỉ tới (thừa còn hơn thiếu)."""
        tok = tok.strip("'\"`")
        while tok.startswith("./"):   # đúng tiền tố "./": lstrip("./") từng xoá luôn dấu chấm của .claude/…, .agents/… (Antigravity 20/10)
            tok = tok[2:]
        if not tok or tok.startswith(("/", "~")) or "$" in tok:
            return set()
        if all(part in ("", ".", "..") for part in tok.split("/")):
            return set()   # "../.." là chuyển thư mục, không phải input: resolve ra thư mục gốc quá lớn ⇒ cắt oan khoá chính xác (issue #151)
        found = set()
        stems = [tok] + ([tok + e for e in (".sh", ".py", ".js", ".mjs", ".ts")] if not os.path.splitext(tok)[1] else [])
        for s in stems:
            for cand in (os.path.normpath(os.path.join(here, s)), os.path.normpath(s)):
                if cand in self.cmap:
                    found.add(cand)
                elif cand in self.dirs and cand not in (".", ""):
                    # thư mục (fixtures/…): mọi file dưới nó. ponytail: thư mục > DIR_EXPAND_MAX file thường là gốc (đo 20/10:
                    # "universal-agent-devkit" kéo 1183 file vào khoá của mọi suite DevKit) — bỏ qua; sentinel bắt phần sót.
                    under = self.under(cand)
                    if len(under) <= DIR_EXPAND_MAX:
                        found |= under
                    else:
                        self.skips += 1
            for p in self.by_base.get(os.path.basename(s), ()):
                # đuôi khớp cả hai chiều: "lib/x.sh" ⇒ "tests/lib/x.sh"; "ROOT/.claude/bin/x.sh" (sau $ROOT) ⇒ ".claude/bin/x.sh"
                if p == s or p.endswith("/" + s) or ("/" in p and s.endswith("/" + p)):
                    found.add(p)
        return found


_LINK_MEMO = {}
_ROOT_MEMO = {}


def _external(project_dir, tok, here):
    """(token, đường dẫn thật) khi token tương đối đi qua symlink ra ngoài cây và trỏ tới một file; None nếu không. Chỉ gọi
    realpath khi một tiền tố của token là symlink (lstat có nhớ): đo 20/10, realpath cho mọi token tốn 4,4 s / 8 suite."""
    tok = tok.strip("'\"`")
    if not tok or tok.startswith(("/", "~")) or "$" in tok:
        return None
    proj = str(project_dir)
    root = _ROOT_MEMO.get(proj) or _ROOT_MEMO.setdefault(proj, os.path.realpath(proj))
    for base in ((here, "") if here else ("",)):
        rel = os.path.normpath(os.path.join(base, tok))
        if rel.startswith(".."):
            continue
        parts = rel.split("/")
        linked = False
        for i in range(1, len(parts) + 1):
            pre = os.path.join(proj, *parts[:i])
            if pre not in _LINK_MEMO:
                _LINK_MEMO[pre] = os.path.islink(pre)
            if _LINK_MEMO[pre]:
                linked = True
                break
        if not linked:
            continue
        try:
            real = os.path.realpath(os.path.join(proj, rel))
            if os.path.isfile(real) and not (real == root or real.startswith(root + os.sep)):
                return rel, real
        except (OSError, ValueError):
            continue
    return None


def _matrix_version(path):
    """Trường "version" (định dạng) của file ma trận, phần của khoá mỗi suite; "none" khi không có file, "unreadable" khi không đọc được
    (cùng giá trị ⇒ cùng khoá: không bao giờ làm một khoá khớp sai, chỉ bớt dùng lại)."""
    if not path or not os.path.isfile(path):   # FIFO / socket: open() chặn mãi (#353)
        return "none"
    try:
        if os.path.getsize(path) > 4 * SCAN_MAX_BYTES:
            return "unreadable"
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError, RecursionError):
        return "unreadable"
    return str(data.get("version")) if isinstance(data, dict) else "unreadable"


def _file_digest(path):
    try:
        st = os.stat(path)
        if not os.path.isfile(path):   # a FIFO/socket/device blocks open() forever (#353)
            return "unreadable"
        if st.st_size >= BIG_FILE_BYTES:
            return f"big {st.st_size}:{st.st_mtime_ns}"
        with open(path, "rb") as f:
            return _blob_sha(f.read())
    except OSError:
        return "unreadable"


def _read_text(path):
    try:
        if not os.path.isfile(path) or os.path.getsize(path) > SCAN_MAX_BYTES:   # a FIFO blocks open() forever (#353)
            return None
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return None
    return None if "\0" in text[:4096] else text


def _rc():
    return _sibling("regression_checklist")


def command_files(project_dir, idx, command):
    """(file trong cây lệnh nêu tên, thư mục `cd` của lệnh). Từ nào là đường dẫn có trong cây thì tính."""
    rc = _rc()
    files, dirs = set(), set()
    for cwd, seg in rc._segments(command or ""):
        if cwd:
            dirs.add(cwd)
        for w in seg.split():
            files |= idx.resolve(w, cwd)
    return files, dirs


_FILE_MEMO = {}


def _file_tokens(full, rel):
    """(token đường dẫn, công cụ được nhắc) của một file, nhớ theo (đường dẫn, mtime, kích thước): một script dùng chung bởi nhiều
    suite chỉ quét một lần mỗi lượt. None khi không đọc được / nhị phân / quá lớn."""
    try:
        st = os.stat(full)
    except OSError:
        return None
    memo_key = (full, st.st_mtime_ns, st.st_size)
    if memo_key in _FILE_MEMO:
        return _FILE_MEMO[memo_key]
    text = _read_text(full)
    if text is None:
        _FILE_MEMO[memo_key] = None
        return None
    toks = set(_PATH_TOKEN.findall(text))
    if rel.endswith(".py"):
        for a, b in _PY_IMPORT.findall(text):
            for item in (a or b).split(","):
                words = item.split()   # "helpers as h" → helpers (bí danh từng thành "helpersash", OCR 20/10)
                mod = words[0] if words else ""
                toks.update(part + ".py" for part in mod.split(".") if part)
    tools = _tools_in(text)
    _FILE_MEMO[memo_key] = (toks, tools)
    return _FILE_MEMO[memo_key]


def _file_refs(project_dir, idx, full, rel, here):
    """(file trong cây, [(token, đích ngoài cây)], công cụ) mà một file nhắc tới; nhớ theo file + thư mục của nó: một script dùng
    chung bởi nhiều suite chỉ phân giải một lần mỗi lượt (đo 20/10: 82k lần gọi _external cho 34 suite khi không nhớ)."""
    info = _file_tokens(full, rel)
    if info is None:
        return None
    memo = idx.refs_memo
    memo_key = (full, here, id(info))   # info sống trong _FILE_MEMO suốt tiến trình: id của nó không bị cấp lại
    if memo_key not in memo:
        toks, tools = info
        refs, outs = set(), []
        skips0 = idx.skips
        for tok in toks:
            hits = idx.resolve(tok, here)
            refs |= hits
            if not hits:
                hit = _external(project_dir, tok, here)
                if hit:
                    outs.append(hit)
        memo[memo_key] = (refs, outs, tools, idx.skips > skips0)
    return memo[memo_key]


def closure(project_dir, idx, seeds, ext_seeds=()):
    """Bao đóng tĩnh: (file trong cây, {token ngoài cây: digest}, công cụ được nhắc, bị cắt?). Bị cắt (quá CLOSURE_MAX_FILES, hay một
    token chỉ tới thư mục quá DIR_EXPAND_MAX file): danh sách input không đủ — người gọi không được dùng nó làm khoá chính xác."""
    seen, ext, tools, cut = set(seeds), {}, set(), False
    level = [(p, os.path.join(str(project_dir), p), os.path.dirname(p)) for p in sorted(seeds)]
    level += [(tok, real, os.path.dirname(tok)) for tok, real in ext_seeds]
    for tok, real in ext_seeds:
        ext[tok] = _file_digest(real)
    for _depth in range(CLOSURE_DEPTH):
        nxt = []
        for rel, full, here in level:
            if os.path.splitext(rel)[1] not in _SCAN_EXT:
                continue
            info = _file_refs(project_dir, idx, full, rel, here)
            if info is None:
                # file thường mà không đọc được / nhị phân / > SCAN_MAX_BYTES: không biết nó nguồn gì ⇒ không có khoá chính xác
                # (thư mục, symlink thư mục, link gãy không phải file để đọc: không cắt — issue #151)
                cut = cut or os.path.isfile(full)
                continue
            refs, outs, found_tools, skipped = info
            tools |= found_tools
            cut = cut or skipped
            for p in refs:
                if p not in seen:
                    if len(seen) >= CLOSURE_MAX_FILES:
                        cut = True
                        break
                    seen.add(p)
                    nxt.append((p, os.path.join(str(project_dir), p), os.path.dirname(p)))
            for tok, real in outs:
                if tok not in ext:
                    if len(ext) >= CLOSURE_MAX_FILES:
                        cut = True
                        break
                    ext[tok] = _file_digest(real)
                    nxt.append((tok, real, os.path.dirname(tok)))
        level = nxt
        if not level:
            break
    else:
        cut = cut or bool(level)   # còn cấp sâu hơn CLOSURE_DEPTH chưa đọc
    return seen, ext, tools, cut


def _tool_version(tool):
    if tool not in _TOOL_VERSIONS:
        exe, flag = _TOOLS[tool]
        try:
            r = subprocess.run([exe, flag], capture_output=True, text=True, timeout=10)
            _TOOL_VERSIONS[tool] = (r.stdout + r.stderr).strip().splitlines()[0][:120] if (r.stdout + r.stderr).strip() else "?"
        except (OSError, subprocess.SubprocessError):
            _TOOL_VERSIONS[tool] = "missing"
    return _TOOL_VERSIONS[tool]


_TOOL_RE = re.compile(r"(?<![\w.-])(%s)(?:\d[\w.]*)?(?![\w-])" % "|".join(sorted(map(re.escape, _TOOLS), key=len, reverse=True)))


def _tools_in(text):
    return {m.group(1) for m in _TOOL_RE.finditer(text or "")}


def env_fingerprint(tools):
    """OS / kiến trúc / bản phát hành + phiên bản của công cụ mà lệnh hay bao đóng của nó nhắc tên."""
    return {"os": platform.system(), "arch": platform.machine(), "release": platform.release(),
            "tools": {t: _tool_version(t) for t in sorted(tools)}}


def cacheable(test, device):
    """(được cache theo khoá?, lý do khi không)."""
    cmd = test.get("command") or ""
    if test.get("cache") is False:
        return False, 'ma trận khai "cache": false'
    if device:
        return False, "suite thiết bị / engine Unity"
    if DIFF_DEPENDENT.search(cmd):
        return False, "chọn test theo lịch sử git (run_impacted.sh)"
    if NETWORK.search(cmd):
        return False, "lệnh đọc mạng"
    return True, ""


def void_needed(status, *, flaky=False, vacuous=False, tree_unchanged=True, recorded=True) -> bool:
    """Một lần chạy THẬT vừa xong có vô hiệu mọi PASS cũ của id (mọi khoá) không (#344). PASS: không. FAIL thật — xác định (không
    chập chờn, không VACUOUS), trên cây không đổi trong lúc chạy, và đã dính vào một khoá (fail_n): không — nó chỉ nói về nội dung đó, một
    nội dung khác từng PASS vẫn đúng (khoá khác ⇒ HIT như cũ). Mọi thứ còn lại (TIMEOUT, hạ tầng, chập chờn, cây đổi, FAIL không ghi
    được khoá nào): có — khoá nào cũng không còn tin được."""
    if status == "PASS":
        return False
    return not (status == "FAIL" and not flaky and not vacuous and tree_unchanged and recorded)


def selection_keyable(test) -> bool:
    """True khi suite là run_impacted.sh chuẩn của DevKit (SELECTION_CMD) mà ma trận không tắt cache: được cache theo khoá cả cây + tập
    chọn, nhưng KHÔNG vào phần cached-full thêm vào của gate (cacheable() vẫn False: mọi --full sẽ phải chạy nó lần đầu)."""
    return test.get("cache") is not False and bool(SELECTION_CMD.match(test.get("command") or ""))


def selection_list(project_dir, command):
    """Tập test (đã sắp) mà `run_impacted.sh --list` chọn lúc này trong project_dir; None khi không hỏi được: lệnh không đúng dạng chuẩn,
    script không có SELECTION_MARK, không nằm trong cây, `--list` lỗi hay quá SELECTION_TIMEOUT_S. Hỏi không kèm DEVKIT_GATE_DONE (tập
    chọn đầy đủ, chưa trừ suite đã chạy trong lượt) và không kèm DEVKIT_IMPACT_TEST_CHANGED (móc test: giả vờ file đổi)."""
    m = SELECTION_CMD.match(command or "")
    if not m:
        return None
    script = os.path.normpath(os.path.join(str(project_dir), m.group(1)))
    root = os.path.realpath(str(project_dir))
    real = os.path.realpath(script)
    if not (real.startswith(root + os.sep) and os.path.isfile(real)):
        return None
    try:
        with open(real, encoding="utf-8", errors="replace") as f:
            if SELECTION_MARK not in f.read(4096):
                return None
        env = {k: v for k, v in os.environ.items() if k not in ("DEVKIT_GATE_DONE", "DEVKIT_IMPACT_TEST_CHANGED")}
        arg = ["--all"] if "--all" in command.split() else []
        r = subprocess.run(["bash", real, "--list", *arg], cwd=str(project_dir), capture_output=True, text=True, env=env,
                           timeout=SELECTION_TIMEOUT_S)
    except (OSError, subprocess.SubprocessError):
        return None
    return sorted(set(r.stdout.split())) if r.returncode == 0 else None


def store_dir(project_dir):
    r = _git(project_dir, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if r.returncode != 0:
        return None
    return os.path.join(os.fsdecode(r.stdout.strip()), "postfix-gate", "suite_cache")


def _open_regular(path, flags, mode=0o600):
    """fd của một FILE THƯỜNG: mở O_NONBLOCK|O_NOFOLLOW rồi fstat. Một FIFO đặt tại file phụ của kho (agent ghi được thư mục này)
    không chặn open() mãi; mọi thứ không phải file thường là OSError (người gọi coi như không có file)."""
    fd = os.open(path, flags | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0), mode)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise OSError(errno.EINVAL, "không phải file thường", path)
    except OSError:
        os.close(fd)
        raise
    return fd


class SuiteCache:
    """Khoá + kho của một lượt gate. Mọi lỗi đọc/ghi chỉ tắt việc dùng lại (suite chạy), không bao giờ thành PASS."""

    def __init__(self, project_dir, rules, matrix_path, covers, local_sha, result_format, selection_env, learned=None):
        _LINK_MEMO.clear()   # symlink có thể đổi giữa hai suite của một lượt nightly dài: đọc lại khi dựng kho mới (OCR 20/10)
        _ROOT_MEMO.clear()
        self.project_dir = str(project_dir)
        self.store = store_dir(project_dir)
        self.cmap = content_map(project_dir)
        self.ok = bool(self.store) and self.cmap is not None and local_sha not in (None, "?")
        self.rules, self.covers = rules or [], covers or {}
        self.local_sha, self.result_format, self.selection_env = local_sha, result_format, selection_env
        self.learned = learned if learned is not None else self.load_learned()
        self.idx = Index(self.cmap or {})
        self.matrix_digest = _file_digest(matrix_path) if matrix_path and os.path.isfile(matrix_path) else "none"
        self.matrix_version = _matrix_version(matrix_path)
        danger = sorted(p for pat in DANGER for p in self.idx.glob(pat) if not p.endswith(DANGER_EXEMPT))
        self.danger_files = danger
        self.matrix_path = matrix_path
        h = hashlib.sha256()
        for p in danger:
            h.update(os.fsencode(p) + b"\0" + self.cmap[p].encode() + b"\0")
        self.danger_digest = h.hexdigest()
        # nội dung CẢ CÂY: phần của khoá cả cây (suite mà luật chọn cũ vẫn chạy chỉ được dùng lại theo khoá này)
        self.tree_digest = tree_digest(self.cmap or {})
        self.inputs = {}   # id → số input của khoá gần nhất (cho log)
        self.input_values = {}   # (id, lệnh) → ({file: "mode sha"}, {token ngoài cây: digest}) lúc tính khoá
        self.key_parts = {}   # (id, lệnh) → (phần đầu, đích ngoài cây) của khoá: tính khoá cả cây trên nội dung khác (tree_key_at)
        self.selections = {}   # (id, lệnh) → tập `--list` đọc lúc tính khoá: phân lớp slot cùng lượt dùng lại (heavy_slot.classify)

    # ── khoá ──
    def key(self, test):
        """Khoá CHÍNH XÁC: sha256 của các phần liệt kê ở docstring module (input a–f, trạng thái cục bộ, môi trường). None khi self.ok
        sai: người gọi chạy suite như chưa có cache. Chỉ suite mà cached-full THÊM vào (luật chọn cũ không chạy) được dùng lại theo
        khoá này: bao đóng tĩnh không thấy đồ thị build ngầm (Gradle includeBuild / project(":feature")) — review 20/10, P0-2."""
        return self.keys(test)[0]

    def tree_key(self, test):
        """Khoá CẢ CÂY: như khoá chính xác nhưng input là nội dung mọi file của cây (+ đích ngoài cây của bao đóng). Suite mà luật chọn
        cũ vẫn chạy chỉ được dùng lại theo khoá này: đúng điều kiện của biên nhận full-pass, nhưng dùng chung mọi worktree."""
        return self.keys(test)[1]

    def keys(self, test):
        """(khoá chính xác, khoá cả cây); (None, None) khi self.ok sai."""
        if not self.ok:
            return None, None
        sid, cmd = test.get("id"), test.get("command") or ""
        files = set()
        own = []   # mọi rule có suite này, nguyên văn: phần ma trận của khoá (B8)
        for rule in self.rules:
            if any((t or {}).get("id") == sid for t in rule.get("mandatory_regression_tests") or []):
                own.append(rule)
                for pat in list(rule.get("watch_files") or []) + list(self.covers.get(sid) or []):
                    files |= self.idx.glob(pat)
        for pat in self.learned.get(sid) or []:   # đường dẫn học được là đường dẫn thật, không phải glob
            files |= {pat} if pat in self.cmap else self.idx.glob(pat)
        watched = set(files)   # watch_files / covers / learned: hạt giống bao đóng cùng file lệnh nêu tên (issue #151)
        skips0 = self.idx.skips
        named, dirs = command_files(self.project_dir, self.idx, cmd)
        for d in dirs:
            files |= self.idx.under(d)
        ext_seeds = []
        for w in cmd.split():
            hit = _external(self.project_dir, w, "")
            if hit:
                ext_seeds.append(hit)
        seen, ext, tools, cut = closure(self.project_dir, self.idx, named | watched, ext_seeds)
        cut = cut or self.idx.skips > skips0
        files |= seen
        sel = None
        if DIFF_DEPENDENT.search(cmd):   # tập test chọn theo lịch sử git: không có tập thì không có khoá; có thì chỉ khoá cả cây (ponytail: mọi
            # file đổi ⇒ chạy lại; khoá theo nội dung của riêng tập chọn cần biết test nào đọc file nào — nâng cấp khi đo tỉ lệ dùng lại thấp)
            sel = selection_list(self.project_dir, cmd)
            if sel is None:
                return None, None
            self.selections[(sid, cmd)] = sel
            cut = True
        head = json.dumps({
            "fmt": SUITE_CACHE_FORMAT, "rf": self.result_format, "id": sid, "command": cmd, "selection": sel,
            "untested_exit": test.get("untested_exit"), "local": self.local_sha, "sel": self.selection_env,
            "danger": self.danger_digest, "env": env_fingerprint(tools | _tools_in(cmd)),
            # B8 (audit 25/10): mục của CHÍNH suite (mọi rule có id, nguyên văn: lệnh, watch_files, untested_exit, cache, covered_by…), covers
            # của id và version của ma trận — không digest cả file: thêm một rule khác (ma trận chỉ-thêm) từng đổi khoá mọi suite.
            "matrix": {"fmt": MATRIX_KEY_FORMAT, "version": self.matrix_version, "rules": own, "covers": self.covers.get(sid)},
        }, sort_keys=True, default=str).encode()
        tail = b"".join(b"x\0" + os.fsencode(tok) + b"\0" + ext[tok].encode() + b"\0" for tok in sorted(ext))
        h = hashlib.sha256(b"precise\0" + head)
        for p in sorted(files):
            h.update(b"f\0" + os.fsencode(p) + b"\0" + (self.cmap.get(p) or "-").encode() + b"\0")
        h.update(tail)
        t = hashlib.sha256(b"tree\0" + head + b"\0" + self.tree_digest.encode() + b"\0" + tail)
        self.inputs[sid] = len(files) + len(ext)
        self.input_values[(sid, cmd)] = ({p: self.cmap.get(p) for p in files}, dict(ext))
        self.key_parts[(sid, cmd)] = (head, tail)
        if cut:   # danh sách input bị cắt: không có khoá chính xác — chỉ dùng lại khi CẢ CÂY trùng (review 20/10)
            return t.hexdigest(), t.hexdigest()
        return h.hexdigest(), t.hexdigest()

    def tree_key_at(self, sid, cmd, digest):
        """Khoá cả cây của suite (sid, cmd) trên một nội dung khác — digest = tree_digest(content_map_at(project_dir, ref)) — cùng phần đầu
        và đích ngoài cây đã tính ở keys(); None khi keys() chưa chạy cho suite này hay không có digest."""
        parts = self.key_parts.get((sid, cmd))
        if not parts or not digest:
            return None
        head, tail = parts
        return hashlib.sha256(b"tree\0" + head + b"\0" + digest.encode() + b"\0" + tail).hexdigest()

    # ── kho ──
    def _path(self, key, ext=".json"):
        return os.path.join(self.store, key + ext) if self.store and re.fullmatch(r"[0-9a-f]{64}", key or "") else None

    def read(self, key):
        path = self._path(key)
        if not path:
            return None
        try:
            fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
        except OSError:
            return None
        try:
            with os.fdopen(fd, encoding="utf-8") as f:
                rec = json.load(f)
        except (OSError, ValueError, RecursionError):
            return None
        return rec if isinstance(rec, dict) else None

    def hit(self, key, test, now=None):
        """Bản ghi khi khoá có PASS dùng lại được, None nếu không."""
        rec = self.read(key)
        now = now or time.time()
        if not rec or rec.get("id") != test.get("id") or rec.get("command") != (test.get("command") or ""):
            return None
        pass_n, fail_n, at = rec.get("pass_n"), rec.get("fail_n"), rec.get("last_pass_at")
        if not (isinstance(pass_n, int) and isinstance(fail_n, int) and isinstance(at, (int, float)) and not isinstance(at, bool)):
            return None
        # tuổi tối đa: DEVKIT_SUITE_CACHE_MAX_S, không bao giờ quá DEVKIT_GATE_CACHE_MAX_S của biên nhận (=0 ⇒ không PASS nào quá hạn được dùng lại)
        max_s = min(_env_float("DEVKIT_SUITE_CACHE_MAX_S", MAX_AGE_S), _env_float("DEVKIT_GATE_CACHE_MAX_S", MAX_AGE_S))
        if pass_n < 1 or fail_n != 0 or not (-60 < now - at <= max_s):
            return None
        if self.quarantined(test.get("id"), now):
            return None
        void_at = self._load_side("void.json").get(test.get("id"))
        if isinstance(void_at, (int, float)) and not isinstance(void_at, bool) and at <= void_at:
            return None   # PASS có trước một lần chạy thật không-PASS của suite này (FAIL, TIMEOUT, lỗi hạ tầng…) ở bất kỳ đâu
        return rec

    def void(self, sid, now=None):
        """Mọi PASS của suite sid ghi trước lúc này hết dùng lại được (mọi khoá): một lần chạy THẬT vừa ra không-PASS — FAIL, TIMEOUT,
        lỗi hạ tầng, hay FAIL trên một cây đã đổi trong lúc chạy (khoá lúc sau không phải khoá của nội dung đã kiểm). PASS ghi sau
        lúc này vẫn dùng được: chỉ tốn đúng một lần chạy lại (review 20/10)."""
        at = now or time.time()
        if sid and not self._update_side("void.json",
                                         lambda d: d.__setitem__(sid, max(at, d.get(sid) if isinstance(d.get(sid), (int, float)) else 0))):
            self._purge_pass(sid)   # void không ghi được: gỡ hẳn PASS cũ của suite này

    def blocked(self, key, sid, now=None):
        """True khi khoá này từng FAIL hoặc id bị cách ly: kể cả biên nhận cả cây cũng không được dùng lại suite đó."""
        rec = self.read(key) if key else None
        return bool(rec and isinstance(rec.get("fail_n"), int) and rec["fail_n"] > 0) or self.quarantined(sid, now)

    def record(self, key, test, status, meta=None, at=None):
        """Ghi kết quả một lượt chạy THẬT: PASS ⇒ pass_n+1, FAIL ⇒ fail_n+1 (vĩnh viễn), TIMEOUT ⇒ timeout_n+1 (#363: chỉ là bằng
        chứng base cho KNOWN-RED; không đụng pass_n/fail_n nên không bao giờ thành HIT hay làm khoá "blocked"). Đọc–sửa–ghi dưới flock
        của khoá kho (store.lock: một file cho cả kho, không bao giờ bị xoá — ghi hiếm, mỗi lượt chạy suite một lần)."""
        path = self._path(key)
        if not path or status not in ("PASS", "FAIL", "TIMEOUT"):
            return None
        try:
            os.makedirs(self.store, mode=0o700, exist_ok=True)
            with open(os.path.join(self.store, "store.lock"), "a+") as lk:
                fcntl.flock(lk.fileno(), fcntl.LOCK_EX)
                rec = self.read(key) or {}
                prev = dict(rec)
                # at: giờ suite CHẠY XONG (người gọi biết), không phải giờ ghi — một void giữa hai lúc đó chặn PASS này (review 20/10)
                now = at if isinstance(at, (int, float)) and not isinstance(at, bool) else time.time()
                void_at = self._load_side("void.json").get(test.get("id"))
                if status == "PASS" and isinstance(void_at, (int, float)) and not isinstance(void_at, bool) and now <= void_at:
                    return prev
                rec.update({"v": SUITE_CACHE_FORMAT, "id": test.get("id"), "command": test.get("command") or "",
                            "pass_n": int(rec.get("pass_n") or 0) + (status == "PASS"),
                            "fail_n": int(rec.get("fail_n") or 0) + (status == "FAIL")})
                if status == "TIMEOUT":
                    rec["timeout_n"] = int(rec.get("timeout_n") or 0) + 1
                rec["last_" + {"PASS": "pass", "FAIL": "fail", "TIMEOUT": "timeout"}[status] + "_at"] = now
                rec.update({k: v for k, v in (meta or {}).items() if k not in ("pass_n", "fail_n", "timeout_n", "id", "command")})
                fd, tmp = tempfile.mkstemp(prefix=".tmp_sc.", dir=self.store)
                try:
                    with os.fdopen(fd, "w", encoding="utf-8") as f:
                        json.dump(rec, f)
                    os.replace(tmp, path)
                except OSError:
                    with contextlib.suppress(OSError):
                        os.remove(tmp)
                    raise
            self.prune()
            return prev
        except OSError as exc:
            print(f"[suite-cache] không ghi được {path}: {exc}", file=sys.stderr)
            if status == "FAIL":
                self._purge_pass(test.get("id"))   # FAIL không ghi được (đĩa đầy…): PASS cũ của suite này không được đứng lại
        return None

    def _purge_pass(self, sid):
        """Gỡ mọi bản ghi PASS (fail_n == 0) của suite sid khỏi kho: đường lùi khi ghi FAIL / void thất bại — unlink không cần chỗ
        trống trên đĩa (review 20/10). Không bao giờ đụng bản ghi có FAIL."""
        if not sid or not self.store:
            return
        try:
            names = [e.path for e in os.scandir(self.store) if re.fullmatch(r"[0-9a-f]{64}\.json", e.name)]
        except OSError:
            return
        for p in names:
            rec = self.read(os.path.basename(p)[:-5]) or {}
            if (rec.get("id") == sid and not (isinstance(rec.get("fail_n"), int) and rec["fail_n"] > 0)
                    and not (isinstance(rec.get("timeout_n"), int) and rec["timeout_n"] > 0 and not rec.get("pass_n"))):   # hit() bỏ qua timeout_n: bản ghi còn pass_n > 0 vẫn là PASS dùng lại được, phải gỡ
                with contextlib.suppress(OSError):
                    os.remove(p)

    def inputs_unchanged(self, test, cmap=None):
        """True khi mọi input của khoá gần nhất của suite (file, đích ngoài cây, danger list, ma trận) vẫn đúng nội dung lúc tính khoá.
        File mới sinh ra trong lúc chạy không tính: nội dung được kiểm vẫn là nội dung trước khi chạy. So theo content_map dựng LẠI (cmap:
        người gọi đã có thì đưa vào): cùng cách biểu diễn với lúc tính khoá — đọc đĩa từng file thì file ≥ 8 MiB, LFS / eol, submodule
        không bao giờ khớp và PASS không bao giờ được ghi (OCR 20/10)."""
        snap = self.input_values.get((test.get("id"), test.get("command") or ""))
        if snap is None:
            return False
        files, ext = snap
        cmap = cmap if cmap is not None else content_map(self.project_dir)
        if cmap is None:
            return False
        for p, v in list(files.items()) + [(p, self.cmap.get(p)) for p in self.danger_files]:
            if cmap.get(p) != v:
                return False
        for tok, dig in ext.items():
            hit = _external(self.project_dir, tok, "")
            if not hit or _file_digest(hit[1]) != dig:
                return False
        return (_file_digest(self.matrix_path) if self.matrix_path and os.path.isfile(self.matrix_path) else "none") == self.matrix_digest

    def record_run(self, keys, test, status, flaky=False, meta=None, at=None, cmap=None):
        """Ghi một lượt chạy THẬT (gate và stale_rerun.run_one cùng dùng) dưới mọi khoá trong keys (chính xác, cả cây). PASS chỉ khi
        input của khoá vẫn y nguyên SAU khi chạy (suite tự sửa input của nó thì không ghi PASS); FAIL luôn ghi (chỉ làm khoá hẹp đi).
        FAIL trên khoá sổ đang nói PASS ⇒ contradiction (P3). Trả câu báo mâu thuẫn đầu tiên, None khi không có."""
        if status == "PASS" and not self.inputs_unchanged(test, cmap):
            return None
        msg = None
        for k in dict.fromkeys(k for k in keys if k):   # khoá chính xác lùi về khoá cả cây: một lần ghi, không hai
            prev = self.record(k, test, status, meta, at=at)
            if status == "FAIL" and msg is None:
                msg = self.contradiction(k, test, prev, flaky)
        return msg

    def prune(self, now=None):
        """Giữ STORE_MAX bản ghi PASS mới nhất, bỏ bản ghi PASS cũ hơn STORE_MAX_AGE_S; bản ghi có FAIL chỉ bỏ khi cũ hơn
        FAIL_MAX_AGE_S. Tối đa một lần mỗi PRUNE_EVERY_S (mốc prune.stamp). Marker .run và store.lock không bao giờ bị đụng."""
        now = now or time.time()
        stamp = os.path.join(self.store, "prune.stamp")
        try:
            if now - os.stat(stamp).st_mtime < PRUNE_EVERY_S:
                return
        except OSError:
            pass
        try:
            os.close(_open_regular(stamp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC))   # chỉ chạm mốc; FIFO thì OSError → bỏ lượt dọn
            entries = []
            for e in os.scandir(self.store):
                if re.fullmatch(r"[0-9a-f]{64}\.json", e.name):
                    with contextlib.suppress(FileNotFoundError):
                        entries.append((e.stat(follow_symlinks=False).st_mtime, e.path))
            if len(entries) <= STORE_MAX and all(now - m <= STORE_MAX_AGE_S for m, _ in entries):
                return
            kept = 0
            with open(os.path.join(self.store, "store.lock"), "a+") as lk:
                fcntl.flock(lk.fileno(), fcntl.LOCK_EX)   # như record(): không xoá một FAIL vừa được os.replace vào đúng file này
                for _mtime, p in sorted(entries, reverse=True):
                    try:
                        mtime = os.stat(p).st_mtime
                    except FileNotFoundError:
                        continue
                    rec = self.read(os.path.basename(p)[:-5]) or {}
                    failed = isinstance(rec.get("fail_n"), int) and rec["fail_n"] > 0
                    if failed:
                        drop = now - mtime > FAIL_MAX_AGE_S
                    else:
                        kept += 1
                        drop = kept > STORE_MAX or now - mtime > STORE_MAX_AGE_S
                    if drop:
                        with contextlib.suppress(FileNotFoundError):
                            os.remove(p)
        except OSError:
            return

    # ── gộp lượt chạy trùng khoá (coalescing) ──
    @contextlib.contextmanager
    def inflight(self, key, est_s=None):
        """Yields "run" (lượt này chạy suite) hoặc "recheck" (lượt khác cùng khoá vừa chạy xong: tra khoá lại trước khi chạy).
        Marker <khoá>.run tạo bằng O_EXCL; marker của PID đã chết hoặc quá hạn (est×1.5+60 s) bị bỏ."""
        path = self._path(key, ".run")
        if not path:
            yield "run"
            return
        limit = (float(est_s) if est_s else 600.0) * 1.5 + 60.0
        waited = False
        mine = False
        try:
            os.makedirs(self.store, mode=0o700, exist_ok=True)
            deadline = time.monotonic() + limit
            while True:
                try:
                    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0), 0o600)
                    with os.fdopen(fd, "w", encoding="utf-8") as f:
                        json.dump({"pid": os.getpid(), "started": time.time(), "est_s": est_s}, f)
                    mine = True
                    break
                except FileExistsError:
                    pass
                try:
                    age = time.time() - os.lstat(path).st_mtime   # tuổi tính trước khi đọc: marker FIFO/hỏng cũ quá 10 s thì bị bỏ, không chờ mãi
                except OSError:
                    age = 0.0
                try:
                    with os.fdopen(_open_regular(path, os.O_RDONLY), encoding="utf-8") as f:
                        other = json.load(f)
                except (OSError, ValueError):
                    other = None
                if not isinstance(other, dict):   # chủ vừa tạo, chưa ghi xong: còn sống trong 10 s đầu
                    if age > 10:
                        with contextlib.suppress(OSError):
                            os.remove(path)
                        continue
                    time.sleep(0.5)
                    continue
                started = other.get("started") if isinstance(other.get("started"), (int, float)) else 0
                try:
                    own_limit = float(other.get("est_s") or 600.0) * 1.5 + 60.0   # hạn theo thời lượng ước tính của CHỦ marker
                except (TypeError, ValueError):
                    own_limit = limit
                if not _pid_alive(other.get("pid")) or time.time() - started > max(own_limit, limit):
                    with contextlib.suppress(OSError):
                        os.remove(path)
                    continue
                if time.monotonic() >= deadline:
                    break   # chờ quá lâu: chạy luôn, không giữ marker
                waited = True
                time.sleep(0.5)
        except OSError as exc:
            print(f"[suite-cache] marker {path}: {exc}", file=sys.stderr)
        try:
            yield "recheck" if waited else "run"
        finally:
            if mine:   # chỉ xoá marker còn là của chính tiến trình này (một lượt khác có thể đã thay nó khi coi nó quá hạn)
                try:
                    with os.fdopen(_open_regular(path, os.O_RDONLY), encoding="utf-8") as f:
                        still = json.load(f).get("pid") == os.getpid()
                except (OSError, ValueError, AttributeError):
                    still = False
                if still:
                    with contextlib.suppress(OSError):
                        os.remove(path)

    # ── P3: cách ly và input học được ──
    def _side(self, name):
        return os.path.join(self.store, name) if self.store else None

    def _load_side(self, name):
        path = self._side(name)
        try:
            with os.fdopen(_open_regular(path, os.O_RDONLY), encoding="utf-8") as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError, TypeError):
            return {}

    def load_learned(self):
        data = self._load_side("learned_inputs.json")
        return {k: [p for p in v if isinstance(p, str)] for k, v in data.items() if isinstance(v, list)}

    def _update_side(self, name, fn):
        """Đọc–sửa–ghi một file JSON phụ của kho dưới flock riêng của nó (ghi nguyên tử). True khi đã ghi."""
        path = self._side(name)
        if not path:
            return False
        try:
            os.makedirs(self.store, mode=0o700, exist_ok=True)
            with open(path + ".lock", "a+") as lk:
                fcntl.flock(lk.fileno(), fcntl.LOCK_EX)
                data = self._load_side(name)
                fn(data)
                fd, tmp = tempfile.mkstemp(prefix=".tmp_side.", dir=self.store)
                try:
                    with os.fdopen(fd, "w", encoding="utf-8") as f:
                        json.dump(data, f, ensure_ascii=False)
                    os.replace(tmp, path)
                except OSError:
                    with contextlib.suppress(OSError):
                        os.remove(tmp)
                    raise
            return True
        except OSError as exc:
            print(f"[suite-cache] không ghi được {path}: {exc}", file=sys.stderr)
        return False

    def quarantine(self, sid, now=None):
        until = (now or time.time()) + _env_float("DEVKIT_FLAKY_QUARANTINE_S", QUARANTINE_S)
        self._update_side("quarantine.json", lambda d: d.__setitem__(sid, until))

    def learn(self, sid, paths):
        """Thêm (không bao giờ bớt) input học được cho suite: chỉ làm khoá rộng ra — không bao giờ sửa ma trận."""
        def add(d):
            have = [p for p in d.get(sid) or [] if isinstance(p, str)]
            d[sid] = have + [p for p in paths if p not in have]
        self._update_side("learned_inputs.json", add)

    # ── P3: sentinel ──
    def sentinel_due(self, now=None):
        """True khi lần chạy THẬT đủ mọi suite gần nhất của repo đã quá DEVKIT_SENTINEL_MAX_S (24 h); 0 = tắt sentinel."""
        max_s = _env_float("DEVKIT_SENTINEL_MAX_S", 24 * 3600)
        if max_s <= 0:
            return False
        at = self._load_side("sentinel.json").get("last_real_full_at")
        return not isinstance(at, (int, float)) or (now or time.time()) - at > max_s

    def stamp_sentinel(self, now=None):
        stamp = now or time.time()
        self._update_side("sentinel.json", lambda d: d.update({"last_real_full_at": stamp}))

    def contradiction(self, key, test, prev, flaky):
        """Một lượt chạy THẬT FAIL trên khoá mà sổ đang nói PASS (pass_n ≥ 1, fail_n = 0): cache đã sai. flaky (FAIL rồi PASS khi chạy
        lại) ⇒ cách ly id; FAIL lặp lại ⇒ input thiếu: file đổi từ HEAD của lần PASS đó mà chưa là input được học thêm cho suite (chỉ
        thêm); không tìm ra file nào ⇒ cách ly (trôi ngoài file: mạng, đồng hồ, máy). Trả câu báo, None khi không phải mâu thuẫn."""
        if not prev or not isinstance(prev.get("pass_n"), int) or prev["pass_n"] < 1 or prev.get("fail_n"):
            return None
        sid = test.get("id")
        if flaky:
            self.quarantine(sid)
            msg = f"{sid}: khoá từng PASS nay FAIL rồi PASS khi chạy lại (FLAKY) — cách ly, không cache"
            learned = []
        else:
            known = set((self.input_values.get((sid, test.get("command") or "")) or ({}, {}))[0])
            learned = self._changed_since(prev.get("head")) - known
            learned = sorted(p for p in learned if not _excluded(p))[:200]
            if learned:
                self.learn(sid, learned)
                msg = (f"{sid}: cache nói PASS nhưng chạy thật FAIL — thiếu input; học thêm {len(learned)} file "
                       f"({', '.join(learned[:5])}{' …' if len(learned) > 5 else ''}); nên thêm vào watch_files của suite này")
            else:
                self.quarantine(sid)
                msg = f"{sid}: cache nói PASS nhưng chạy thật FAIL, không file nào đổi — trôi ngoài file; cách ly, không cache"
        try:
            os.makedirs(self.store, mode=0o700, exist_ok=True)
            with os.fdopen(_open_regular(os.path.join(self.store, "sentinel_report.jsonl"), os.O_WRONLY | os.O_APPEND | os.O_CREAT),
                           "a", encoding="utf-8") as f:   # FIFO ở đây: OSError (ENXIO/EINVAL) → in lỗi, không treo
                f.write(json.dumps({"at": time.time(), "id": sid, "key": key, "flaky": bool(flaky), "learned": learned,
                                    "msg": msg}, ensure_ascii=False) + "\n")
        except OSError as exc:
            print(f"[suite-cache] sentinel_report: {exc}", file=sys.stderr)
        return msg

    def _changed_since(self, head):
        """File (tương đối project) khác giữa commit của lần PASS và nội dung đang có (commit sau đó + đang sửa + chưa track).
        Commit không còn: mọi file của cây (bảo thủ)."""
        if not head or not re.fullmatch(r"[0-9a-f]{7,64}", str(head)):
            return set(self.cmap or {})
        r = _git(self.project_dir, "diff", "--name-only", "-z", "--relative", "--no-renames", str(head))
        o = _git(self.project_dir, "ls-files", "-z", "--others", "--exclude-standard")
        if r.returncode != 0:
            return set(self.cmap or {})
        return {p for blob in (r.stdout, o.stdout) for p in blob.decode("utf-8", "surrogateescape").split("\0") if p}

    def quarantined(self, sid, now=None):
        until = self._load_side("quarantine.json").get(sid)
        return isinstance(until, (int, float)) and (now or time.time()) < until


def _pid_alive(pid):
    try:
        pid = int(pid)
        if pid <= 0:
            return False
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except (TypeError, ValueError, OSError):
        return False
    return True
