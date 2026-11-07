#!/usr/bin/env python3
"""Fingerprint of a project's code state, shared by post-fix-gate.py (which records it in
the full-run receipt) and hooks/proof_gate.sh (which compares it on XONG).

It covers the content of every tracked and untracked, non-ignored file — so an edit made
after the gate ran changes it, while committing that same content does not. One exception (#691): HEAD_PINNED files
(.claude/settings.json, which the kit install edits locally and never commits) count as HEAD holds them, so an uncommitted
edit of them leaves the fingerprint alone while a committed change still moves it. Files the gate and the proof step write themselves
are left out, otherwise running the gate or taking the screenshot would invalidate the
receipt: the checklist/status files, audit-gate logs, evidence, and reports/ (proof PNGs).

CLI: tree_fp.py <project_dir>  → prints the fingerprint (empty output outside git).
100% standard library.
"""
import hashlib
import os
import subprocess
import sys

EXCLUDE = (".claude/audit-gate", ".agents/regression_status.json", ".agents/regression_checklist.md",
           ".agents/CHECKLIST.md", ".agents/INBOX.md", ".agents/evidence", ".agents/archive", ".agents/instincts.md", "reports",
           "docs/super-board/runs",   # QA-lane evidence committed after the gate PASSed: not code (agent-workbench#248)
           ".agents/local/memory/claude-auto",   # the agent's own notes: not code (memory/voice is, GeelyEx2 tests read it)
           # the temp file of regression_checklist.save(): tempfile.mkstemp(dir=".agents", prefix=".regression_status.") = that prefix + exactly 8
           # characters of [a-z0-9_], in .agents/ until os.replace. The gate releases test_run.lock before the save, so a run that wins the lock
           # meanwhile fingerprinted a tree that holds it and refused the receipt of the run it waited for (tests/gates/test_tree_fp_checklist_temp.sh).
           # A git pathspec (the throw-away index `rm --cached` below and in push_gate.py): nothing else matches it, and the plain-string tests on
           # EXCLUDE (path == entry or startswith(entry + "/")) never do, which is harmless for a file that no commit holds.
           # The other mkstemp prefixes of that module need no entry: ".tmp." is written inside .agents/regression_journal/ (its own .gitignore
           # is "*") and ".worktree_checklist." inside the git dir.
           ".agents/.regression_status." + "[a-z0-9_]" * 8)
# #691: file bản cài kit sửa cục bộ trong mỗi worktree; tree_fingerprint() chỉ tính bản đã commit của chúng (xem trong hàm), và biên nhận
# gate (post-fix-gate head_and_dirty) không ghi chúng vào `dirty`. Không nằm trong EXCLUDE: EXCLUDE bỏ cả nội dung đã commit.
HEAD_PINNED = (".claude/settings.json",)


def head_pinned(path, prefix=""):
    """True when `path` is a HEAD_PINNED entry or lies under one (same convention as EXCLUDE); `prefix` = the project's path in the repo."""
    return any(path == prefix + p or path.startswith(prefix + p + "/") for p in HEAD_PINNED)
RECEIPT = "full_pass.json"
# #644: biên nhận của lượt gate scoped (chỉ test liên quan diff, tự leo --full khi đụng file lõi), cạnh full_pass.json, cùng các trường
# cộng "scope": "scoped"; bản theo cây ở <git common dir>/postfix-gate/scoped_receipts/<fp>.json (đối xứng tree_receipts/)
SCOPED_RECEIPT = "scoped_pass.json"
SCOPED_STORE_DIR = "scoped_receipts"
# #105: the --full exit-0 receipts again, one per tree fingerprint, in the git COMMON dir: they outlive the worktree that wrote them.
TREE_RECEIPT_MAX_AGE_S = 24 * 3600
TREE_RECEIPT_MAX = 64


def _git(project_dir, *args):
    return subprocess.run(["git", "-C", str(project_dir), *args], capture_output=True)


_STATIC = {}


def rev_parse_static(project_dir, *args):
    """stdout (bytes, stripped) of `git -C project_dir rev-parse <args>`, or None on a git error. Only for answers that cannot move while
    this process lives (git dir, top level, prefix, common dir, object path): one spawn per distinct question, where one gate run spawned
    `--absolute-git-dir` 8 times (tests/gates/test_gate_git_spawn_budget.sh). A failure is never cached (the repo may appear later);
    never use it for HEAD or anything else a commit changes. OSError / TimeoutExpired reach the caller as before."""
    key = (str(project_dir), args)
    if key not in _STATIC or not os.path.isdir(str(project_dir)):   # a folder removed mid-run is asked again: git fails, no admin dir is re-created (tests/gates/test_gate_project_removed_midrun.sh)
        res = subprocess.run(["git", "-C", str(project_dir), "rev-parse", *args], capture_output=True, timeout=30)
        if res.returncode != 0:
            return None
        _STATIC[key] = res.stdout.strip()
    return _STATIC[key]


def receipt_path(project_dir):
    """.git/postfix-gate/full_pass.json of the repo holding project_dir, or .agents/audit-gate/full_pass.json for non-git."""
    gitdir = rev_parse_static(project_dir, "--absolute-git-dir")
    if gitdir is None:
        return os.path.join(str(project_dir), ".agents", "audit-gate", RECEIPT)
    return os.path.join(gitdir.decode(errors="surrogateescape"), "postfix-gate", RECEIPT)   # a non-UTF-8 folder name (2026-10-09)


def scoped_receipt_path(project_dir):
    """<git dir>/postfix-gate/scoped_pass.json (cạnh receipt_path), hoặc .agents/audit-gate/scoped_pass.json ngoài git."""
    return os.path.join(os.path.dirname(receipt_path(project_dir)), SCOPED_RECEIPT)


def tree_receipt_dir(project_dir):
    """<git common dir>/postfix-gate/tree_receipts (<fingerprint>.json each), shared by every worktree of the repo; None outside git."""
    common = rev_parse_static(project_dir, "--path-format=absolute", "--git-common-dir")
    if common is None:
        return None
    return os.path.join(common.decode(errors="surrogateescape"), "postfix-gate", "tree_receipts")


def _non_git_fingerprint(project_dir):
    h = hashlib.sha256()
    try:
        from pathlib import Path
        proj = Path(project_dir)
        for root, dirs, files in os.walk(project_dir):
            dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("node_modules", "build", "dist", "reports", "__pycache__")]
            for f in sorted(files):
                if f.startswith("."):
                    continue
                p = Path(root) / f
                try:
                    rel = str(p.relative_to(proj)).replace("\\", "/")
                except ValueError:
                    continue
                if any(rel == ex or rel.startswith(ex + "/") for ex in EXCLUDE):
                    continue
                try:
                    st = p.stat()
                    h.update(f"{rel}:{st.st_size}:{st.st_mtime_ns}".encode())
                except OSError:
                    continue
        return h.hexdigest()[:24]
    except Exception:
        return ""


def tree_fingerprint(project_dir):
    """Hash of the CONTENT of project_dir as it stands (tracked + untracked, ignores and EXCLUDE
    left out, HEAD_PINNED files as HEAD holds them), built in a throw-away index so the real one is never touched. It does not
    include the HEAD commit id: committing exactly the gated code keeps the receipt valid,
    any content change voids it."""
    import shutil
    import tempfile
    if _git(project_dir, "rev-parse", "HEAD").returncode != 0:
        return _non_git_fingerprint(project_dir)
    gitdir, prefix, objects = (
        (rev_parse_static(project_dir, *q) or b"").decode() for q in
        (("--absolute-git-dir",), ("--show-prefix",), ("--path-format=absolute", "--git-path", "objects")))
    tree_fingerprint.error = ""
    with tempfile.TemporaryDirectory() as tmp:
        index = os.path.join(tmp, "index")
        if os.path.isfile(os.path.join(gitdir, "index")):
            # copy2, not copyfile: the copy must keep the index mtime, or git stops treating entries written in that same
            # second as "racily clean" and trusts their stat, so a same-size edit in that second is not seen
            shutil.copy2(os.path.join(gitdir, "index"), index)
        # New blobs go to a throw-away object store that reads the real one as an alternate:
        # the real .git/objects never grows because the gate or the Stop hook looked.
        os.makedirs(os.path.join(tmp, "objects", "info"))
        os.makedirs(os.path.join(tmp, "objects", "pack"))
        env = dict(os.environ, GIT_INDEX_FILE=index, GIT_OBJECT_DIRECTORY=os.path.join(tmp, "objects"),
                   GIT_ALTERNATE_OBJECT_DIRECTORIES=objects)
        run = lambda *a: subprocess.run(["git", "-C", str(project_dir), *a], capture_output=True, env=env)
        big_files, excludes = _big_untracked(project_dir)
        # Exclude after adding: an exclude pathspec naming an ignored path makes `add` fail (the big
        # files excluded here are untracked and NOT ignored, so their exclude is safe).
        added = run("add", "-A", "--", ".", *excludes)
        if added.returncode != 0:
            tree_fingerprint.error = added.stderr.decode(errors="replace").strip()[:300]
            return ""
        run("rm", "-r", "--cached", "-q", "--ignore-unmatch", "--", *EXCLUDE)
        # #691: bản cài kit sửa .claude/settings.json cục bộ và không commit; đưa path ghim về blob của HEAD để sửa chưa commit không
        # đổi fp, còn nội dung đã commit vẫn tính (KHÔNG đưa vào EXCLUDE). HEAD không có file thì bỏ khỏi index tạm. Git lỗi thì
        # fail-closed như `add -A` ở trên: không đoán một fp khác rỗng (ls-tree lỗi từng rơi vào nhánh xoá file khỏi index).
        for pin in HEAD_PINNED:
            ls = run("ls-tree", "--full-name", "HEAD", "--", pin)
            rows = ls.stdout.decode(errors="surrogateescape").splitlines()
            if ls.returncode != 0 or any(not r.startswith(("100644 blob ", "100755 blob ", "120000 blob ")) for r in rows):
                tree_fingerprint.error = ("ls-tree HEAD " + pin + ": " + ls.stderr.decode(errors="replace").strip() if ls.returncode != 0
                                          else "HEAD giữ " + pin + " không phải blob/symlink")[:300]
                return ""
            # -r: path ghim có thể là thư mục chưa track (con của nó) trong index tạm; không xoá hết thì update-index đụng file/thư mục
            cleared = run("rm", "-r", "--cached", "-q", "--ignore-unmatch", "--", pin)
            put = subprocess.run(["git", "-C", str(project_dir), "update-index", "--index-info"], input=ls.stdout, capture_output=True, env=env) if rows else None
            bad = cleared if cleared.returncode != 0 else put if put is not None and put.returncode != 0 else None
            if bad is not None:
                tree_fingerprint.error = (pin + ": " + bad.stderr.decode(errors="replace").strip())[:300]
                return ""
        tree = run("write-tree").stdout.decode().strip()
        if prefix and tree:
            tree = run("rev-parse", f"{tree}:{prefix.rstrip('/')}").stdout.decode().strip()
    if not tree:
        return ""
    # without big untracked files the value is the one it always was (receipts taken before stay valid)
    return hashlib.sha256((tree + "".join("\n" + b for b in big_files)).encode(errors="surrogateescape")).hexdigest()[:24]


def commit_fingerprint(project_dir, rev="HEAD", timeout=None):
    """The fingerprint tree_fingerprint gives a clean checkout of commit `rev` (#105: main's HEAD next to other sessions' uncommitted
    files), built from the commit alone in a throw-away index and object store. "" on a git error. An untracked file of
    TREE_FP_BIG_MB or more counts by its signature in tree_fingerprint and by content here, so such a tree never matches (fail closed).
    timeout: seconds for the WHOLE call (one deadline over its six git calls; a hook that runs past its own deadline is killed and its
    Stop goes through): subprocess.TimeoutExpired once it is spent."""
    import tempfile
    import time
    end = time.monotonic() + timeout if timeout else None
    rest = lambda: None if end is None else max(0.05, end - time.monotonic())
    git = lambda *a, env=None: subprocess.run(["git", "-C", str(project_dir), *a], capture_output=True, env=env, timeout=rest())
    objects = git("rev-parse", "--path-format=absolute", "--git-path", "objects").stdout.decode().strip()
    prefix = git("rev-parse", "--show-prefix").stdout.decode().strip()
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "objects", "info"))
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tmp, "index"), GIT_OBJECT_DIRECTORY=os.path.join(tmp, "objects"),
                   GIT_ALTERNATE_OBJECT_DIRECTORIES=objects, GIT_NO_REPLACE_OBJECTS="1")
        run = lambda *a: git(*a, env=env)
        if not objects or run("read-tree", rev + "^{commit}").returncode:
            return ""
        run("rm", "-r", "-f", "--cached", "-q", "--ignore-unmatch", "--", *EXCLUDE)   # -f: the work tree (main's dirty files) is not this index
        tree = run("write-tree").stdout.decode().strip()
        if prefix and tree:
            tree = run("rev-parse", f"{tree}:{prefix.rstrip('/')}").stdout.decode().strip()
    return hashlib.sha256(tree.encode()).hexdigest()[:24] if tree else ""


def _big_untracked(project_dir):
    """Untracked, not ignored files of TREE_FP_BIG_MB MiB or more (default 8, the bound devkit_harness uses): (signatures
    "path<NUL>size<NUL>mtime_ns", sorted; exclude pathspecs for `git add`). GeelyEx2 2026-10-13: `git add -A` hashed 319 MB of
    untracked recordings on every fingerprint (6.5-7.3 s). Such a file counts by path, size and mtime, its content is never
    read. ponytail: a same-size edit that keeps mtime is not seen; content-hash big files only if a writer ever does that.
    TREE_FP_BIG_MB=0 hashes every file by content."""
    try:
        limit = int(float(os.environ.get("TREE_FP_BIG_MB", "8")) * (1 << 20))
    except ValueError:
        limit = 8 << 20
    if limit <= 0:
        return [], []
    listed = _git(project_dir, "ls-files", "-z", "--others", "--exclude-standard", "--", ".")
    if listed.returncode != 0:
        return [], []
    sigs, excludes = [], []
    for rel in listed.stdout.decode(errors="surrogateescape").split("\0"):
        if not rel or any(rel == ex or rel.startswith(ex + "/") for ex in EXCLUDE) or head_pinned(rel):   # #691: path ghim không tính, kể cả file lớn
            continue
        try:
            st = os.lstat(os.path.join(str(project_dir), rel))
        except OSError:
            continue
        if st.st_size >= limit:
            sigs.append(f"{rel}\0{st.st_size}\0{st.st_mtime_ns}")
            excludes.append(":(exclude,literal)" + rel)
    return sorted(sigs), excludes


tree_fingerprint.error = ""   # why the last call returned "" (git's stderr), for the gate to print


# Gate speed v26 mục 1: Stop hook không chạy suite nữa, nó chỉ hỏi "cây này có biên nhận exit 0 không". Một hàm cho cả ba loại biên nhận
# (full, scoped, task), cùng luật kiểm với post-fix-gate (result_format, gate_sha, matrix_sha, local_sha), không nạp post-fix-gate.py.
TASK_RECEIPT = "task_pass.json"
TASK_STORE_DIR = "task_receipts"
RECEIPT_JSON_MAX = 1 << 20
_MATRIX_CANDIDATES = (".agents/regression_matrix.active.json", "templates/regression_matrix.active.json",
                      ".agents/active-profile/regression_matrix.json", "templates/regression_matrix.json")


def _sha256_file(path):
    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except (OSError, TypeError):
        return ""


def _result_format(gate):
    """RESULT_FORMAT của post-fix-gate.py ở `gate` (đọc dòng gán, không exec file 9 k dòng); None khi không đọc được."""
    import re
    try:
        with open(gate, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"RESULT_FORMAT = (\d+)\b", line)
                if m:
                    return int(m.group(1))
    except (OSError, UnicodeDecodeError):
        return None
    return None


def _devkit_scripts_on_path():
    scripts = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "scripts")
    for sub in ("git", "governance", "context", ""):
        p = os.path.join(scripts, sub) if sub else scripts
        if p not in sys.path:
            sys.path.insert(0, p)


def local_state_sha(project_dir, skip=()):
    """Cùng công thức post-fix-gate local_state_sha (LOCAL_CONFIG bị git ignore + build_inputs, ngoài SKIP_WALK); "?" khi không liệt kê được."""
    import fnmatch
    try:
        _devkit_scripts_on_path()
        from worktree import LOCAL_CONFIG  # noqa: PLC0415
        from build_inputs import SKIP_WALK, build_inputs  # noqa: PLC0415
        specs = []
        for p in LOCAL_CONFIG:
            specs.extend([p, "**/" + p])
        out = subprocess.run(["git", "-C", str(project_dir), "ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--"] + specs,
                             capture_output=True, text=True, errors="surrogateescape").stdout
        files = {r for r in out.split("\0") if r and not r.endswith("/")
                 and any(fnmatch.fnmatch(os.path.basename(r), p) for p in LOCAL_CONFIG) and not SKIP_WALK.intersection(r.split("/")[:-1])}
        files |= set(build_inputs(project_dir))
        sums = {rel: _sha256_file(os.path.join(str(project_dir), rel)) for rel in files}
    except Exception:   # như post-fix-gate: không liệt kê được thì không có biên nhận dùng được
        return "?"
    h = hashlib.sha256()
    for rel in sorted(set(sums) - set(skip)):
        h.update(os.fsencode(rel) + b"\0" + sums[rel].encode() + b"\0")
    return h.hexdigest()


def _regen_allowed(paths):
    """post-fix-gate regen_allowed: local config và build input mặc định không bao giờ được bỏ khỏi local_sha."""
    import fnmatch
    _devkit_scripts_on_path()
    from worktree import LOCAL_CONFIG  # noqa: PLC0415
    from build_inputs import DEFAULT_INPUTS  # noqa: PLC0415
    pats = [q for p in DEFAULT_INPUTS for q in (p, p[3:] if p.startswith("**/") else p)]
    return sorted(rel for rel in paths if not any(fnmatch.fnmatch(os.path.basename(rel), p) for p in LOCAL_CONFIG)
                  and not any(fnmatch.fnmatch(rel, p) for p in pats))


def _load_receipt(path):
    import json
    import stat
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0))
        with os.fdopen(fd, encoding="utf-8") as fh:
            st = os.fstat(fh.fileno())
            if not stat.S_ISREG(st.st_mode) or st.st_size > RECEIPT_JSON_MAX:
                return None
            data = json.load(fh)
    except (OSError, ValueError, RecursionError):
        return None
    return data if isinstance(data, dict) else None


def receipt_for_tree(project_dir, gate=None, matrix=None, fp=None, max_age_s=None, why=None):
    """Biên nhận exit 0 của post-fix-gate cho CÂY hiện tại của project_dir (full, scoped hay task), hoặc None. Trả bản sao dict của biên
    nhận, thêm "_kind" (full | scoped | task), "_path" và "_base" (sha mà lượt gate kiểm từ đó tới cây; "" với full: cả cây).
    Kiểm: exit 0, dấu vân tay = fp của cây, result_format = RESULT_FORMAT của `gate`, gate_sha = sha256(gate) (khi có gate), matrix_sha =
    sha256 ma trận của dự án (matrix, hoặc cùng thứ tự dò như post-fix-gate), local_sha = local_state_sha (trừ local_regen được phép),
    tested_at trong DEVKIT_GATE_CACHE_MAX_S, không suite FAIL / TIMEOUT. tests rỗng chỉ nhận ở biên nhận scoped không có test liên quan
    (scoped_tests, smoke, core_smoke đều rỗng) và ở biên nhận task (lượt không có suite nào). why: list nhận lý do từ chối (log)."""
    import time
    def no(msg):
        if isinstance(why, list):
            why.append(msg)
        return None
    fp = fp or tree_fingerprint(project_dir)
    if not fp:
        return no("fp")
    own = receipt_path(project_dir)
    common = tree_receipt_dir(project_dir)
    if not own or not common:
        return no("git")
    own_dir, store = os.path.dirname(own), os.path.dirname(common)
    if max_age_s is None:
        try:
            max_age_s = float(os.environ.get("DEVKIT_GATE_CACHE_MAX_S", "259200"))
        except ValueError:
            max_age_s = 0.0
    if matrix is None:
        matrix = next((os.path.join(str(project_dir), c) for c in _MATRIX_CANDIDATES if os.path.exists(os.path.join(str(project_dir), c))), "")
    fmt = _result_format(gate) if gate else None
    gate_sha = _sha256_file(gate) if gate else None
    matrix_sha = _sha256_file(matrix) if matrix else ""
    local_cache = {}
    cands = (("full", os.path.join(own_dir, RECEIPT)), ("full", os.path.join(store, "tree_receipts", fp + ".json")),
             ("scoped", os.path.join(own_dir, SCOPED_RECEIPT)), ("scoped", os.path.join(store, SCOPED_STORE_DIR, fp + ".json")),
             ("task", os.path.join(own_dir, TASK_RECEIPT)), ("task", os.path.join(store, TASK_STORE_DIR, fp + ".json")))
    now = time.time()
    for kind, path in cands:
        r = _load_receipt(path)
        if r is None:
            continue
        scope = r.get("scope", "full")
        if scope != kind:
            no("%s: scope %s" % (path, scope))
            continue
        if r.get("exit") != 0 or isinstance(r.get("exit"), bool):
            no("%s: exit" % path)
            continue
        if r.get("fp" if kind == "task" else "fingerprint") != fp:
            no("%s: fp" % path)
            continue
        if gate and (fmt is None or r.get("result_format") != fmt):
            no("%s: result_format" % path)
            continue
        if gate and r.get("gate_sha") != gate_sha:
            no("%s: gate_sha" % path)
            continue
        if r.get("matrix_sha") != matrix_sha:
            no("%s: matrix_sha" % path)
            continue
        t = r.get("tested_at")
        if isinstance(t, bool) or not isinstance(t, (int, float)) or not (-1e15 < t < 1e15) or t > now + 60 or now - t > max_age_s:
            no("%s: tested_at" % path)
            continue
        tests = r.get("tests")
        if kind == "task" and tests is None:
            tests = []
        if not isinstance(tests, list) or not all(isinstance(x, dict) for x in tests) \
                or any(x.get("status") in ("FAIL", "TIMEOUT") for x in tests):
            no("%s: tests" % path)
            continue
        if not tests and kind == "full":
            no("%s: tests empty" % path)
            continue
        if not tests and kind == "scoped" and any(r.get(k) for k in ("scoped_tests", "smoke", "core_smoke")):
            no("%s: tests empty with related tests" % path)
            continue
        regen = r.get("local_regen") or []
        if not isinstance(regen, list) or not all(isinstance(p, str) for p in regen):
            no("%s: local_regen" % path)
            continue
        try:
            skip = tuple(_regen_allowed(regen)) if regen else ()
        except Exception:
            no("%s: local_regen" % path)
            continue
        if skip not in local_cache:
            local_cache[skip] = local_state_sha(project_dir, skip)
        if r.get("local_sha") in (None, "?") or r.get("local_sha") != local_cache[skip]:
            no("%s: local_sha" % path)
            continue
        base = "" if kind == "full" else r.get("diff_base" if kind == "task" else "base")
        if kind != "full" and not (isinstance(base, str) and base):
            no("%s: base" % path)
            continue
        return dict(r, _kind=kind, _path=path, _base=base)
    return no("none")


# Proof image scope (rules/essentials.md step 4). The image is waived only for a change that
# surely never reaches a screen; anything else, of any extension at any depth, needs it.
NO_SCREEN_PROFILES = {"backend"}
PROFILE_FILES = (".agents/active-profile.json", ".active-profile.json")
OFF_SCREEN_TOP = {".agents", ".claude", ".gemini", ".github", ".githooks", ".codebase-memory",
                  "docs", "reports", "scripts", "bin", "tools"}      # first path component only
TEST_TOP = {"test", "tests", "__tests__", "spec", "Tests"}          # first path component, or *Tests
TEST_SOURCE_SETS = {"test", "androidTest", "androidUnitTest", "androidInstrumentedTest", "commonTest",
                    "jvmTest", "iosTest", "testDebug", "testRelease"}  # the segment right after src/
OFF_SCREEN_NAMES = {"LICENSE", "NOTICE", "AUTHORS", "CODEOWNERS", ".gitignore", ".editorconfig"}


def _off_screen(rel, profile=""):
    parts = rel.split("/")
    top = parts[0] if len(parts) > 1 else ""
    if top == "docs" and profile == "web":
        return False   # a web project's docs/ can be the site itself (Docusaurus, MkDocs)
    if top in OFF_SCREEN_TOP or top in TEST_TOP or top.endswith("Tests"):
        return True
    if rel.endswith(".log"):
        return True   # a log never reaches a screen, at any depth (GeelyEx2 artifacts/red-proof/*.log)
    if any(parts[i] == "src" and parts[i + 1] in TEST_SOURCE_SETS for i in range(len(parts) - 2)):
        return True
    if len(parts) == 1 and (rel.endswith((".md", ".rst", ".adoc")) or rel in OFF_SCREEN_NAMES):
        return True   # Markdown deeper down may be site content (Astro, Hugo, Docusaurus)
    return False


def _turn_base(project_dir, since):
    """Commit HEAD pointed at when the turn started (reflog), or None when unknown."""
    if not since:
        return "HEAD"
    res = _git(project_dir, "rev-parse", "-q", "--verify", f"HEAD@{{@{int(since)}}}")
    return res.stdout.decode().strip() or None if res.returncode == 0 else None


def _profile_at(project_dir, base, since):
    """(profile at the turn start, changed in the turn?). The committed file at `base`, else an
    uncommitted one (after `agent-kit init`, or an ignored .agents/) written before the turn."""
    import json
    parse = lambda raw: (json.loads(raw).get("profile") or "") if raw else ""
    for rel in PROFILE_FILES:
        res = _git(project_dir, "show", f"{base}:./{rel}")
        path = os.path.join(str(project_dir), rel)
        try:
            if res.returncode == 0:   # the profile VALUE: a re-init rewriting the same profile is no switch
                now = open(path, encoding="utf-8").read() if os.path.isfile(path) else ""
                return parse(res.stdout.decode()), parse(now) != parse(res.stdout.decode())
            if os.path.isfile(path):
                return parse(open(path, encoding="utf-8").read()), not since or os.path.getmtime(path) >= since
        except (OSError, ValueError, AttributeError):
            return "", True
    return "", False


def image_required(project_dir, since=None):
    """(required, reason). Changed = the working tree against the commit HEAD pointed at when
    the turn started (reflog, so commits, merges, pulls and resets of the turn all count) plus
    untracked files; renames show both paths. The profile is read at that commit, so switching
    it inside the turn waives nothing. Paths are relative to project_dir."""
    if _git(project_dir, "rev-parse", "HEAD").returncode != 0:
        return True, "git state unknown"
    base = _turn_base(project_dir, since)
    if not base:
        return True, "HEAD at the turn start unknown"
    names = _git(project_dir, "diff", base, "--name-only", "--relative", "--no-renames", "-z").stdout
    names += _git(project_dir, "ls-files", "-o", "--exclude-standard", "-z").stdout
    changed = {p.strip("\n") for p in names.decode(errors="replace").split("\0") if p.strip("\n")}
    prof, prof_changed = _profile_at(project_dir, base, since)
    if prof in NO_SCREEN_PROFILES and not prof_changed:
        return False, f"profile {prof} has no screen"
    for rel in sorted(changed):
        if not _off_screen(rel, prof):
            return True, f"may show on screen: {rel}"
    return False, "only tests, docs, scripts or agent files changed"


if __name__ == "__main__":
    print(tree_fingerprint(sys.argv[1] if len(sys.argv) > 1 else "."))
