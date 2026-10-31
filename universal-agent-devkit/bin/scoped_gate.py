#!/usr/bin/env python3
"""Bộ quyết định "scoped" của gate (#644): chọn đúng các test chạm tới diff theo đồ thị tham chiếu BẮC CẦU, leo "full" khi không chắc.

Đồ thị dựng trên file của repo (`git ls-files` + file mới chưa ignore; bỏ vendor/node_modules/build, `.agents/local/`, link, file > 2 MB):
cạnh A→B khi A tham chiếu B —
  Python `import x` / `from x import y` / `from . import y` (cả trong heredoc của .sh) giải về .py trong repo (cùng thư mục, package,
  gốc repo; không giải được thì mọi file trùng tên);
  shell `source X` / `. X`;
  nhắc tên nguyên từ (basename) của file code `.sh .py .bash .mjs .js` hoặc script không đuôi có shebang (luật nhắc tên của
  run_impacted, nhưng bắc cầu); test còn khớp stem như run_impacted (lệnh con của dispatcher gọi tên script theo stem);
  dòng `<glob> <test…>` của `<kit>/tests/impact_map.txt` (glob tương đối thư mục kit) → cạnh test→file.
Chỉ file code (và test) là NGUỒN cạnh: tài liệu, ma trận, checklist nhắc tên hàng chục script — tính chúng thì fan-in ≥ 5 phủ nửa kit và
bao đóng nuốt mọi thứ. Tài liệu / dữ liệu (không phải code) mà test nhắc basename như chuỗi con (`grep -F` của run_impacted, "$P/DESIGN.md"):
ngoài đồ thị, một bước — 1–4 test đọc ⇒ đúng các test đó; ≥ 5 ⇒ lõi (test-read-by, live + [core:auto]).

decide() PHÂN LOẠI: (1) base sai / dựng đồ thị lỗi ⇒ full; (2) khớp lõi (`.agents/gate-core.txt` [core] ∪ [core:auto] ∪ fan-in live ≥ 5)
⇒ full; (3) needs_no_test ⇒ docs (vẫn cộng test trên map nếu có: bản chép super-board của post-fix-gate là "không cần test" nhưng có test
thật); (4) có test trên map ⇒ tests; (5) không test nhưng khớp watch_files cụ thể của ma trận (không phải `*` / `<thư mục cấp 1>/*`) ⇒ ma
trận phủ; (6) còn lại ⇒ unmapped ⇒ full. File code bị xoá ⇒ full.
no_full() (#741, anh Đạt 31/10): phạm vi gate PR / merge gate / post-fix-gate --scoped KHÔNG BAO GIỜ là full — test chạm tới diff (cả test
của file lõi) + [smoke]; file không có test riêng (lõi không test, unmapped, code bị xoá) hay đồ thị lỗi ⇒ thêm [core-smoke]. Cả bộ suite
chỉ chạy ở gate-full đêm 00:00 (bin/gate_full.py).

  scoped_gate.py decide --base REF [--project DIR] [--json]
  scoped_gate.py gen [--project DIR] [--write-core]    ghi <git common dir>/postfix-gate/gate-test-map.json; --write-core viết lại
                                                       riêng mục [core:auto] của .agents/gate-core.txt
  scoped_gate.py explain FILE [--project DIR]
Stdlib, import được từ bin/."""
import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
import time

CORE_FILE = ".agents/gate-core.txt"
MATRIX_FILE = ".agents/regression_matrix.active.json"
MAP_NAME = "gate-test-map.json"
# trạng thái agent / chỉ git đọc (như AGENT_STATE_FILES + .gitignore của post-fix-gate): đi kèm commit fix chứ không làm vỡ test; worktree
# của phiên có .claude/settings.json bẩn (thấy 29/10) — để vào [core:auto] thì lượt nào của worktree đó cũng thành full
AGENT_STATE = {".claude/settings.json", ".claude/settings.local.json", ".gitignore", ".antigravity-pm.json", ".adb-denylist"}
FAN_IN_CORE = 5
MAX_BYTES = 2 * 1024 * 1024
CACHE_AFTER_S = 3.0
CACHE_KEEP = 4
SCAN_VER = "v2"                                             # đổi khi _scan đổi cách đọc (v2: import nhiều dòng): cache cũ bỏ
CODE_EXT = (".sh", ".py", ".bash", ".mjs", ".js")          # đích của luật nhắc tên (như run_impacted)
SOURCE_EXT = CODE_EXT + (".cjs", ".ts", ".tsx", ".jsx", ".zsh", ".jq")
PY_SCAN_EXT = (".py", ".sh", ".bash")                       # import Python, kể cả heredoc `python3 - <<'PY'`
SKIP_DIRS = ("vendor", "node_modules", "build")
SKIP_PREFIX = (".agents/local/",)                           # dữ liệu của DevKit (red-patches, memory), không phải code
# lõi khi repo chưa có .agents/gate-core.txt: lockfile/dependency/config của test runner, helper test dùng chung, hook
DEFAULT_CORE = ["*.lock", "package*.json", "*/package*.json", "*pnpm-lock.yaml", "pyproject.toml", "*/pyproject.toml",
                "requirements*.txt", "*/requirements*.txt", "go.mod", "*/go.mod", "go.sum", "*/go.sum", "*.gradle*",
                "conftest.py", "*/conftest.py", "tests/lib/*", "*/tests/lib/*", ".githooks/*", ".claude/hooks/*", CORE_FILE]

TOKEN = re.compile(r"[A-Za-z0-9_.+-]+")
# `from x import (a,\n    b,  # chú thích\n)` nhiều dòng: nhóm 3 là cả danh sách trong ngoặc (tới `)`), nhóm 4 là danh sách một dòng
PY_FROM = re.compile(r"^[ \t]*from[ \t]+(\.*)([\w.]*)[ \t]+import[ \t]+(?:\(([^)]*)\)|([^\n#]+))", re.M)
PY_COMMENT = re.compile(r"#[^\n]*")
PY_IMPORT = re.compile(r"^[ \t]*import[ \t]+([\w.]+(?:[ \t]*,[ \t]*[\w.]+)*)", re.M)
SH_SOURCE = re.compile(r"(?:^[ \t]*|[;&|({][ \t]*)(?:source|\.)[ \t]+([^\n;&|)]+)", re.M)
TEST_RE = [re.compile(p) for p in (
    r"(^|/)tests/(.+/)?test_[^/]*\.(sh|py)$",
    r"(^|/)hooks/tests/[^/]+\.sh$",
    r"_test\.(py|go|sh|js|mjs|ts)$",                         # .js/.ts: mcp-servers/agent-office/tests/*_test.js
    r"\.test\.(js|ts|mjs|jsx|tsx)$",
    r"\.spec\.[^/]+$",
    r"(^|/)src/test/",
    r"(^|/)src/androidTest/",
)]


def is_test(path):
    return any(r.search(path) for r in TEST_RE)


def default_needs_no_test(path):
    p = path.replace("\\", "/")
    return (p.lower().endswith(".md") or p.startswith(("docs/", "reports/")) or os.path.basename(p).startswith("LICENSE")
            or p == ".agents/instincts.md")


def match_pattern(path, pat):
    """Như post-fix-gate.match_pattern: fnmatch (`*` khớp cả `/`) + tiền tố `**/`."""
    return fnmatch.fnmatch(path, pat) or (pat.startswith("**/") and fnmatch.fnmatch(path, pat[3:]))


def _git(project, *args, check=True):
    r = subprocess.run(["git", "-C", project] + list(args), capture_output=True, timeout=120)
    if check and r.returncode != 0:
        raise RuntimeError("git %s: %s" % (" ".join(args[:3]), r.stderr.decode("utf-8", "replace").strip()[:300]))
    return r


def _z(out):
    return [p for p in out.decode("utf-8", "surrogateescape").split("\0") if p]


def common_dir(project):
    return os.path.abspath(os.path.join(project, _git(project, "rev-parse", "--git-common-dir").stdout.decode().strip()))


# --- gate-core.txt ---------------------------------------------------------------------------------------------------------

def _sections(text):
    out, cur = {}, None
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            cur = s[1:-1].strip()
            out.setdefault(cur, [])
            continue
        if cur is None or not s or s.startswith("#"):
            continue
        out[cur].append(s.split()[0])                      # bỏ `  # lý do`
    return out


def load_core(project):
    """{"core": [glob], "smoke": [path], "core_smoke": [path]} từ .agents/gate-core.txt ([core] ∪ [core:auto], [smoke], [core-smoke]);
    thiếu file → DEFAULT_CORE."""
    try:
        with open(os.path.join(project, CORE_FILE), encoding="utf-8") as f:
            sec = _sections(f.read())
    except OSError:
        return {"core": list(DEFAULT_CORE), "smoke": [], "core_smoke": []}
    core = sec.get("core", []) + [g for g in sec.get("core:auto", []) if g not in sec.get("core", [])]
    if CORE_FILE not in core:
        core.append(CORE_FILE)                              # sửa chính danh sách lõi luôn là lõi
    return {"core": core, "smoke": list(sec.get("smoke", [])), "core_smoke": list(sec.get("core-smoke", []))}


# --- quét file -------------------------------------------------------------------------------------------------------------

def list_files(project):
    """File tracked + mới chưa ignore, còn trên đĩa, không phải link, ≤ 2 MB, ngoài vendor/node_modules/build và .agents/local/."""
    out = []
    for p in sorted(set(_z(_git(project, "ls-files", "-z", "-co", "--exclude-standard").stdout))):
        if p.startswith(SKIP_PREFIX) or any(seg in SKIP_DIRS for seg in p.split("/")[:-1]):
            continue
        full = os.path.join(project, p)
        try:
            if os.path.islink(full) or not os.path.isfile(full) or os.path.getsize(full) > MAX_BYTES:
                continue
        except OSError:
            continue
        out.append(p)
    return out


def _shebang(full):
    try:
        with open(full, "rb") as f:
            return f.read(2) == b"#!"
    except OSError:
        return False


def _scan(project, path):
    """Dữ liệu thô của một file nguồn: token (nhắc tên), import Python, đích `source`. Đọc lỗi / nhị phân → rỗng."""
    try:
        with open(os.path.join(project, path), "rb") as f:
            raw = f.read(MAX_BYTES)
    except OSError:
        return {"tok": [], "imp": [], "src": []}
    if b"\0" in raw[:8192]:
        return {"tok": [], "imp": [], "src": []}
    text = raw.decode("utf-8", "replace")
    toks = sorted({t.rstrip(".-") for t in TOKEN.findall(text)} - {""})
    imps = []
    if path.endswith(PY_SCAN_EXT) or "." not in os.path.basename(path):
        for dots, mod, paren, line in PY_FROM.findall(text):
            names = PY_COMMENT.sub("", paren) if paren else line
            imps.append([len(dots), mod, [n.split()[0] for n in names.replace("(", "").replace(")", "").split(",") if n.split()]])
        for group in PY_IMPORT.findall(text):
            for mod in group.split(","):
                if mod.strip():
                    imps.append([0, mod.strip(), []])
    srcs = []
    if not path.endswith((".py", ".js", ".mjs", ".ts")):
        for rest in SH_SOURCE.findall(text):
            words = TOKEN.findall(rest)
            if words:
                srcs.append(words[-1].rstrip(".-"))
    return {"tok": toks, "imp": imps, "src": srcs}


def _is_source(project, path):
    base = os.path.basename(path)
    return path.endswith(SOURCE_EXT) or is_test(path) or ("." not in base and _shebang(os.path.join(project, path)))


def _scan_all(project, files):
    """Quét mọi file nguồn; > 3 s thì cache phần tracked sạch theo cây HEAD:./ của project (file bẩn / mới luôn quét lại)."""
    sources = [p for p in files if _is_source(project, p)]
    tree, cache, cdir = None, {}, None
    try:
        # cây của CHÍNH thư mục project (HEAD:./): khoá theo HEAD^{tree} thì hai project thư mục con của một repo dùng chung một cache
        tree = _git(project, "rev-parse", "HEAD:./").stdout.decode().strip()
        cdir = os.path.join(common_dir(project), "postfix-gate")
        with open(os.path.join(cdir, "scoped-scan-%s-%s.json" % (SCAN_VER, tree)), encoding="utf-8") as f:
            cache = json.load(f)
    except (RuntimeError, OSError, ValueError):
        cache = {}
    dirty = set()
    if tree:
        # đường dẫn tương đối project như ls-files (git status in từ gốc repo: project thư mục con thì file bẩn bị coi là sạch)
        dirty = set(_z(_git(project, "diff", "--name-only", "-z", "--no-renames", "--relative", "HEAD", "--", check=False).stdout))
        dirty |= set(_z(_git(project, "ls-files", "-z", "-o", "--exclude-standard", check=False).stdout))
    t0 = time.monotonic()
    scans, fresh = {}, {}
    for p in sources:
        if p in cache and p not in dirty:
            scans[p] = cache[p]
            continue
        scans[p] = _scan(project, p)
        if p not in dirty:
            fresh[p] = scans[p]
    took = time.monotonic() - t0
    if tree and cdir and fresh and took > CACHE_AFTER_S:
        try:
            os.makedirs(cdir, exist_ok=True)
            keep = {p: s for p, s in scans.items() if p not in dirty}
            tmp = os.path.join(cdir, ".scoped-scan-%d.tmp" % os.getpid())
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(keep, f)
            os.replace(tmp, os.path.join(cdir, "scoped-scan-%s-%s.json" % (SCAN_VER, tree)))
            old = sorted((os.path.getmtime(os.path.join(cdir, n)), n) for n in os.listdir(cdir) if n.startswith("scoped-scan-"))
            for _, n in old[:-CACHE_KEEP]:
                os.remove(os.path.join(cdir, n))
        except OSError as e:                               # cache hỏng không làm hỏng quyết định
            print("scoped_gate: không ghi được cache (%s)" % e, file=sys.stderr)
    return scans


def _impact_map_edges(project, files, fileset):
    """Cạnh test→file từ mọi `<kit>/tests/impact_map.txt` (glob tương đối thư mục kit)."""
    edges = []
    for mp in files:
        if not (mp == "tests/impact_map.txt" or mp.endswith("/tests/impact_map.txt")):
            continue
        kit = mp[: -len("tests/impact_map.txt")]
        try:
            with open(os.path.join(project, mp), encoding="utf-8") as f:
                lines = f.read().splitlines()
        except OSError:
            continue
        for line in lines:
            parts = line.split()
            if not parts or parts[0].startswith("#"):
                continue
            glob = kit + parts[0]
            targets = [p for p in files if fnmatch.fnmatch(p, glob)]
            for t in parts[1:]:
                if kit + t in fileset:
                    edges.extend((kit + t, x) for x in targets)
    return edges


NO_READERS = re.compile(r"(?:README[^/]*|CHANGELOG)\.md$")   # run_impacted bỏ chúng khỏi tập file đổi
_WORD_SEP = re.compile(r"([^A-Za-z0-9_]+)")


def _word_runs(token):
    """Mọi đoạn con của token bắt đầu và kết thúc ở ranh giới từ (như `grep -w`): "x-devkit-audit" → x, x-devkit, devkit-audit, …"""
    parts = _WORD_SEP.split(token)
    for i in range(0, len(parts), 2):
        if not parts[i]:
            continue
        for j in range(i, len(parts), 2):
            if parts[j]:
                yield "".join(parts[i:j + 1])


def build_graph(project, _files=None, _code=None, _reads=None):
    """{file: set(file)}: A→B khi A tham chiếu B. Mọi file trong danh sách đều là khoá. `_code` (dict) nhận thêm riêng cạnh CODE thật
    (Python import, shell `source` / `.`), không có cạnh nhắc tên / stem / impact_map: dùng cho luật dep-of-core. `_reads` (dict) nhận
    {file tài liệu / dữ liệu: set(test nhắc basename của nó)} — một bước, ngoài đồ thị (test_readers)."""
    files = _files if _files is not None else list_files(project)
    fileset = set(files)
    graph = {p: set() for p in files}
    code = _code if _code is not None else {}
    code.update({p: set() for p in files})
    by_base, by_stem, by_py = {}, {}, {}
    for p in files:
        base = os.path.basename(p)
        by_base.setdefault(base, []).append(p)
        if p.endswith(CODE_EXT):
            by_stem.setdefault(base.rsplit(".", 1)[0], []).append(p)
        if p.endswith(".py"):
            mod = p[:-3]
            by_py.setdefault(mod.rsplit("/", 1)[-1], []).append(p)
            if mod.endswith("/__init__"):
                by_py.setdefault(mod[: -len("/__init__")].rsplit("/", 1)[-1], []).append(p)
    named = {}                                              # tên nhắc được → file code (có đuôi code, hoặc script không đuôi có shebang)
    for base, ps in by_base.items():
        hit = [p for p in ps if p.endswith(CODE_EXT) or ("." not in base and _shebang(os.path.join(project, p)))]
        if hit and not base.startswith("__"):               # `__init__.py` / `__main__.py` nhắc tên không chỉ file nào (import đã giải)
            named[base] = hit
    scans = _scan_all(project, files)

    def py_targets(src, level, mod, names):
        d = os.path.dirname(src)
        if level:
            for _ in range(level - 1):
                d = os.path.dirname(d)
            roots = [d]
        else:
            roots = [d, ""]
        parts = [x for x in mod.split(".") if x]
        found = []
        for root in roots:
            stem = "/".join(([root] if root else []) + parts)
            cands = ([stem + ".py", stem + "/__init__.py"] if parts else []) + \
                    [(stem + "/" if stem else "") + n + ".py" for n in names]
            found = [c for c in cands if c in fileset]
            if found:
                return found
        if level or not parts:
            return found
        # không giải được theo thư mục: mọi file trùng tên (`import capacity` sau sys.path.insert(…/bin))
        suffix = "/".join(parts)
        return [p for p in by_py.get(parts[-1], []) if p[:-3].endswith(suffix) or p.endswith(suffix + "/__init__.py")]

    # file KHÔNG phải code (tài liệu, dữ liệu) theo basename: test đọc nó khi basename là chuỗi con của một token ("$P/DESIGN.md", VERSION,
    # *.json), như `grep -F` của run_impacted. Không phải cạnh của đồ thị (không bắc cầu): `_reads` nhận {file: test đọc trực tiếp}
    # Như run_impacted: README*.md / CHANGELOG.md không chọn test nào; */SKILL.md theo TÊN thư mục skill nguyên từ (27 test nhắc "SKILL.md")
    by_data, skills = {}, {}
    for base, ps in by_base.items():
        rest = [p for p in ps if p not in named.get(base, ())]
        if base == "SKILL.md":
            for p in rest:
                skills.setdefault(os.path.basename(os.path.dirname(p)), []).append(p)
        elif rest and not NO_READERS.match(base):
            by_data[base] = rest
    lens = sorted({len(b) for b in by_data}) if _reads is not None else []
    skills = skills if _reads is not None else {}
    for src, sc in scans.items():
        out = graph[src]
        test_src = is_test(src)
        for t in sc["tok"]:
            out.update(named.get(t, ()))
            if test_src:                                    # stem nguyên từ, như run_impacted (chỉ test)
                for piece in t.split("."):
                    out.update(by_stem.get(piece, ()))
                for n in lens:
                    if n > len(t):
                        break
                    for i in range(len(t) - n + 1):
                        for p in by_data.get(t[i:i + n], ()):
                            _reads.setdefault(p, set()).add(src)
                if skills:
                    for w in _word_runs(t):
                        for p in skills.get(w, ()):
                            _reads.setdefault(p, set()).add(src)
        dep = code[src]
        for level, mod, names in sc["imp"]:
            dep.update(py_targets(src, level, mod, names))
        for s in sc["src"]:
            dep.update(by_base.get(s, ()))
        dep.discard(src)
        out.update(dep)
        out.discard(src)
    for a, b in _impact_map_edges(project, files, fileset):
        if a != b:
            graph[a].add(b)
    return graph


def _reverse(graph):
    rev = {p: set() for p in graph}
    for a, bs in graph.items():
        for b in bs:
            rev.setdefault(b, set()).add(a)
    return rev


def fan_in(graph):
    """{file: số file KHÔNG phải test tham chiếu trực tiếp}."""
    n = {}
    for a, bs in graph.items():
        if is_test(a):
            continue
        for b in bs:
            n[b] = n.get(b, 0) + 1
    return n


def core_deps(code, roots):
    """{file: file lõi gốc}: file mà một file lõi phụ thuộc THẬT (bao đóng theo cạnh code: import / source), không tính test và chính
    các file lõi. Lấp chỗ hở của lớp chặn trong _reach: test chỉ chạm F qua hub lõi thì sửa F phải full (fail closed)."""
    out = {}
    for r in sorted(roots):
        stack = [r]
        while stack:
            for nxt in code.get(stack.pop(), ()):
                if nxt not in roots and nxt not in out and not is_test(nxt):
                    out[nxt] = r
                    stack.append(nxt)
    return out


def core_nodes(project, graph, core=None, code=None):
    """File lõi trong đồ thị: khớp glob lõi, hoặc fan-in ≥ 5 không phải test (hook nhắc tên test trong chú thích: test không thành lõi),
    và (khi có `code`) mọi file mà file lõi phụ thuộc thật (core_deps)."""
    globs = (core or load_core(project))["core"]
    fi = fan_in(graph)
    roots = {p for p in graph if any(match_pattern(p, g) for g in globs) or (fi.get(p, 0) >= FAN_IN_CORE and not is_test(p))}
    return roots | set(core_deps(code, roots)) if code else roots


def _reach(start, adj, barrier=()):
    """Bao đóng từ start, KHÔNG đi xuyên file lõi (vào được, không mở tiếp): gần mọi test nhắc tên gate / dispatcher của kit, và các
    hub đó nhắc hàng trăm file trong chú thích — đi xuyên thì sửa bộ đọc runs.jsonl của governance chọn 662/676 test (đo 29/10). Sửa
    chính file lõi đã là full; đường gián tiếp qua lõi do gate-full đêm phủ. (Chú thích này cố ý không nêu tên file: nhắc tên là cạnh.)
    F mà file lõi import / source (bắc cầu) thì chính F là lõi (core_deps) ⇒ full. ponytail: F chỉ được hub lõi NHẮC TÊN (chạy như
    lệnh con, không import) mà test chỉ chạm F qua hub đó thì không được chọn; nâng cấp khi gate-full đêm bisect ra commit đỏ sửa file
    không lõi mà lượt scoped của nó XANH."""
    seen, stack = {start}, [start]
    while stack:
        cur = stack.pop()
        if cur != start and cur in barrier:
            continue
        for nxt in adj.get(cur, ()):
            if nxt not in seen:
                seen.add(nxt)
                stack.append(nxt)
    return seen


def test_map(project, graph=None, barrier=None):
    """{file: sorted [test]}: T phủ F khi F trong bao đóng bắc cầu tham chiếu của T (T phủ chính nó; không đi xuyên file lõi)."""
    code = None
    if graph is None:
        code = {}
        graph = build_graph(project, _code=code)
    barrier = core_nodes(project, graph, code=code) if barrier is None else barrier
    out = {}
    for t in graph:
        if is_test(t):
            for f in _reach(t, graph, barrier):
                out.setdefault(f, set()).add(t)
    return {f: sorted(ts) for f, ts in sorted(out.items())}


# --- diff + quyết định -----------------------------------------------------------------------------------------------------

def changed_files(project, base):
    """`git diff --name-only $(git merge-base base HEAD)` (gồm cây làm việc, đổi tên = xoá + thêm) ∪ file mới chưa ignore."""
    mb = _git(project, "merge-base", base, "HEAD").stdout.decode().strip()
    if not mb:
        raise RuntimeError("không có merge-base giữa %s và HEAD" % base)
    diff = _z(_git(project, "diff", "--name-only", "-z", "--no-renames", "--relative", mb, "--").stdout)
    new = _z(_git(project, "ls-files", "-z", "-o", "--exclude-standard").stdout)
    return sorted(set(diff) | set(new))


def _load_matrix(project):
    try:
        with open(os.path.join(project, MATRIX_FILE), encoding="utf-8") as f:
            rules = json.load(f).get("rules", [])
        return rules if isinstance(rules, list) else []
    except (OSError, ValueError, AttributeError):
        return []


def _catch_all(pat):
    return pat in ("*", "**", "**/*") or re.fullmatch(r"[^/*?\[]+/\*\*?(/\*)?", pat) is not None


def _matrix_covers(path, rules):
    """Luật ma trận nào có watch_files CỤ THỂ khớp (post-fix-gate chỉ đọc watch_files, không đọc trigger_files)."""
    for r in rules:
        if not isinstance(r, dict):
            continue
        for pat in r.get("watch_files") or []:
            if isinstance(pat, str) and not _catch_all(pat) and match_pattern(path, pat):
                return True
    return False


def decide(project, base, needs_no_test=None, matrix_rules=None, changed=None):
    t0 = time.monotonic()
    project = os.path.abspath(project)
    nnt = needs_no_test or default_needs_no_test
    res = {"mode": "full", "reasons": [], "core_hits": [], "changed": [], "docs": [], "tests": [], "smoke": [],
           "unmapped": [], "expanded": [], "matrix_covered": [], "deleted": [], "no_own_test": [], "graph_error": None, "elapsed_s": 0.0}
    core = load_core(project)
    res["smoke"] = [p for p in core["smoke"] if os.path.isfile(os.path.join(project, p))]

    def done():
        res["elapsed_s"] = round(time.monotonic() - t0, 3)
        return res

    try:
        if changed is None:
            if not base:
                raise RuntimeError("thiếu base")
            changed = changed_files(project, base)
        changed = sorted({c.replace("\\", "/") for c in changed if c})
        res["changed"] = changed
        code, reads = {}, {}
        graph = build_graph(project, _code=code, _reads=reads)
    except (RuntimeError, OSError, subprocess.SubprocessError, ValueError) as e:
        res["reasons"].append("base/đồ thị lỗi ⇒ full: %s" % e)
        res["graph_error"] = str(e)[:300]
        return done()
    rules = _load_matrix(project) if matrix_rules is None else matrix_rules
    fi = fan_in(graph)
    rev = _reverse(graph)
    roots = core_nodes(project, graph, core)
    deps = core_deps(code, roots)
    barrier = roots | set(deps)
    tests, expanded = set(), set(changed)
    for f in changed:
        hit = True
        # trạng thái agent (.claude/settings.json bẩn ở mọi worktree, 38 test nhắc "settings.json"): không thành lõi theo fan-in /
        # test-read-by, chỉ cộng đúng các test đọc nó; [core] viết tay vẫn thắng
        state = f in AGENT_STATE
        if any(match_pattern(f, g) for g in core["core"]):
            res["core_hits"].append(f)
        elif fi.get(f, 0) >= FAN_IN_CORE and not is_test(f) and not state:   # hook nhắc tên test trong chú thích: test không thành lõi
            res["core_hits"].append(f)
            res["reasons"].append("fan-in %d ≥ %d: %s" % (fi[f], FAN_IN_CORE, f))
        elif len(reads.get(f, ())) >= FAN_IN_CORE and not state:   # tài liệu / dữ liệu ≥ 5 test đọc (AGENTS.md…): lõi như fan-in
            res["core_hits"].append(f)
            res["reasons"].append("test-read-by: %d test: %s" % (len(reads[f]), f))
        elif f in deps:
            res["core_hits"].append(f)
            res["reasons"].append("dep-of-core: %s ← %s" % (f, deps[f]))
        else:
            hit = False
        if not os.path.lexists(os.path.join(project, f)):
            res["deleted"].append(f)
            if not nnt(f):
                res["reasons"].append("file code bị xoá ⇒ full: %s" % f)
                res["no_own_test"].append(f)
            continue
        up = _reach(f, rev, barrier) if f in rev else {f}
        expanded |= up
        mine = {t for t in up if is_test(t)} | reads.get(f, set())   # 1–4 test đọc tài liệu / dữ liệu: đúng các test đó, không bắc cầu
        tests |= mine
        if nnt(f) or state:
            res["docs"].append(f)
        elif mine or hit:                                   # lõi đã là full: không kể thêm là unmapped
            if not mine:
                res["no_own_test"].append(f)                # lõi không test nào chạm: no_full bù bằng [core-smoke]
            continue
        elif _matrix_covers(f, rules):
            res["matrix_covered"].append(f)
        else:
            res["unmapped"].append(f)
    if res["core_hits"]:
        res["reasons"].insert(0, "khớp lõi ⇒ full: %s" % ", ".join(res["core_hits"][:10]))
    if res["unmapped"]:
        res["reasons"].append("unmapped (không test nào phủ, không luật ma trận cụ thể) ⇒ full: %s" % ", ".join(res["unmapped"][:10]))
    res["tests"] = sorted(tests)
    res["expanded"] = sorted(expanded)
    res["mode"] = "full" if res["reasons"] else "scoped"
    return done()


def add_core_smoke(res, project):
    """Thêm [core-smoke] (file còn trên đĩa) vào res["smoke"] và res["core_smoke"]; một lần."""
    core = load_core(project)
    have = [p for p in core["smoke"] + core["core_smoke"] if os.path.isfile(os.path.join(project, p))]
    res["core_smoke"] = [p for p in core["core_smoke"] if p in have]
    res["smoke"] = list(dict.fromkeys(list(res.get("smoke") or []) + have))
    return res


def no_full(res, project):
    """#741: quyết định của decide() → phạm vi chạy ở PR / merge gate, mode luôn "scoped". Giữ test chạm tới diff (test-reach, test-read-by
    của cả file lõi) + [smoke]; file không có test riêng (no_own_test), unmapped hay đồ thị lỗi ⇒ thêm [core-smoke]. Lý do leo full cũ vào
    would_full, file lõi vào core_touched (verdict ghi "core-touched" để review 2/2 soi kỹ); reasons rỗng. ponytail: test chỉ chạm file
    lõi qua một file lõi khác (_reach dừng ở barrier) không được chọn — gate-full đêm phủ; nâng cấp khi đêm bisect ra commit lõi xanh ở PR."""
    out = dict(res)
    out["would_full"] = list(res.get("reasons") or [])
    out["core_touched"] = list(res.get("core_hits") or [])
    out["core_smoke"] = []
    if res.get("no_own_test") or res.get("unmapped") or res.get("graph_error"):
        add_core_smoke(out, project)
    else:
        out["smoke"] = list(dict.fromkeys(list(res.get("smoke") or []) + [p for p in load_core(project)["smoke"]
                                                                          if os.path.isfile(os.path.join(project, p))]))
    out["reasons"] = []
    out["mode"] = "scoped"
    return out


# --- gen: map + [core:auto] ------------------------------------------------------------------------------------------------

def _fragile(project, graph, days=60, min_commits=3):
    """{file: n}: file nằm trong ≥ 3 commit `🐛 [fix]` (60 ngày) mà commit đó sửa test ở thư mục KHÁC thư mục các test tham chiếu
    trực tiếp file đó (file không test nào tham chiếu: test nào cũng là "khác")."""
    r = _git(project, "log", "--since=%d.days" % days, "-F", "--grep=🐛 [fix]", "--no-renames", "--name-only",
             "--format=%x01%s", "--relative", check=False)
    rev = _reverse(graph)
    count = {}
    for block in r.stdout.decode("utf-8", "replace").split("\x01")[1:]:
        lines = block.splitlines()
        if not lines or not lines[0].startswith("🐛 [fix]"):
            continue
        files = [x for x in lines[1:] if x]
        tdirs = {os.path.dirname(x) for x in files if is_test(x)}
        if not tdirs:
            continue
        for f in files:
            if is_test(f) or default_needs_no_test(f) or f not in graph:
                continue
            own = {os.path.dirname(t) for t in rev.get(f, ()) if is_test(t)}
            if tdirs - own:
                count[f] = count.get(f, 0) + 1
    return {f: n for f, n in count.items() if n >= min_commits}


def core_auto(project, graph, reads=None):
    """[(path, lý do)]: fan-in ≥ 5 (không tính test) + "hay làm vỡ chỗ khác" + tài liệu / dữ liệu ≥ 5 test đọc (`reads`, test-read-by);
    bỏ file đã khớp [core] viết tay, test, trạng thái agent; tài liệu chỉ vào khi do test-read-by."""
    try:
        with open(os.path.join(project, CORE_FILE), encoding="utf-8") as f:
            manual = _sections(f.read()).get("core", [])
    except OSError:
        manual = list(DEFAULT_CORE)
    fi = fan_in(graph)
    reasons, read_core = {}, set()
    for f, n in fi.items():
        if n >= FAN_IN_CORE and f in graph:
            reasons.setdefault(f, []).append("fan-in %d" % n)
    for f, n in _fragile(project, graph).items():
        reasons.setdefault(f, []).append("%d commit 🐛 [fix]/60 ngày sửa test ở thư mục khác" % n)
    for f, ts in (reads or {}).items():
        if len(ts) >= FAN_IN_CORE:
            reasons.setdefault(f, []).append("test-read-by: %d test" % len(ts))
            read_core.add(f)
    return [(f, "; ".join(rs)) for f, rs in sorted(reasons.items())
            if not is_test(f) and (f in read_core or not default_needs_no_test(f)) and f not in AGENT_STATE
            and not any(match_pattern(f, g) for g in manual)]


def write_core_auto(project, entries):
    """Viết lại RIÊNG thân mục [core:auto] của gate-core.txt; mục khác giữ nguyên từng byte."""
    path = os.path.join(project, CORE_FILE)
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines(True)
    except OSError:
        lines = ["[core]\n"] + [g + "\n" for g in DEFAULT_CORE] + ["\n[smoke]\n"]
    width = max([len(p) for p, _ in entries] + [0]) + 2
    body = ["%s# %s\n" % (p.ljust(width), why) for p, why in entries] + ["\n"]
    start = next((i for i, l in enumerate(lines) if l.strip() == "[core:auto]"), None)
    if start is None:
        at = next((i for i, l in enumerate(lines) if l.strip() == "[smoke]"), len(lines))
        new = lines[:at] + ["[core:auto]\n"] + body + lines[at:]
    else:
        end = next((i for i in range(start + 1, len(lines)) if lines[i].strip().startswith("[")), len(lines))
        new = lines[: start + 1] + body + lines[end:]
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("".join(new))
    os.replace(tmp, path)


def gen(project, write_core=False):
    code, reads = {}, {}
    graph = build_graph(project, _code=code, _reads=reads)
    tm = test_map(project, graph, core_nodes(project, graph, code=code))
    auto = core_auto(project, graph, reads)
    out = os.path.join(common_dir(project), "postfix-gate")
    os.makedirs(out, exist_ok=True)
    head = _git(project, "rev-parse", "HEAD", check=False).stdout.decode().strip()
    data = {"generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "head": head, "fan_in": fan_in(graph),
            "core_auto": [p for p, _ in auto], "test_map": tm}
    tmp = os.path.join(out, ".%s.%d.tmp" % (MAP_NAME, os.getpid()))
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1, sort_keys=True)
    os.replace(tmp, os.path.join(out, MAP_NAME))
    if write_core:
        write_core_auto(project, auto)
    return os.path.join(out, MAP_NAME), auto, tm


def explain(project, path):
    code, reads = {}, {}
    graph = build_graph(project, _code=code, _reads=reads)
    rev = _reverse(graph)
    core = load_core(project)
    tm = test_map(project, graph, core_nodes(project, graph, core, code))
    fi = fan_in(graph)
    return {"file": path, "in_graph": path in graph, "is_test": is_test(path), "test_read_by": sorted(reads.get(path, ())),
            "core_glob": [g for g in core["core"] if match_pattern(path, g)], "fan_in": fi.get(path, 0),
            "dep_of_core": core_deps(code, core_nodes(project, graph, core)).get(path),
            "references": sorted(graph.get(path, ())), "referenced_by": sorted(rev.get(path, ())),
            "tests": tm.get(path, []), "matrix_covered": _matrix_covers(path, _load_matrix(project)),
            "needs_no_test": default_needs_no_test(path)}


def main(argv=None):
    ap = argparse.ArgumentParser(prog="scoped_gate.py", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("decide")
    d.add_argument("--base", required=True)
    d.add_argument("--project", default=".")
    d.add_argument("--json", action="store_true")
    g = sub.add_parser("gen")
    g.add_argument("--project", default=".")
    g.add_argument("--write-core", action="store_true")
    e = sub.add_parser("explain")
    e.add_argument("file")
    e.add_argument("--project", default=".")
    a = ap.parse_args(argv)
    project = os.path.abspath(a.project)
    if a.cmd == "decide":
        res = decide(project, a.base)
        if a.json:
            print(json.dumps(res, ensure_ascii=False, indent=1))
        else:
            print("mode: %s (%d file đổi, %d test, %d smoke, %.2f s)" % (res["mode"], len(res["changed"]), len(res["tests"]),
                                                                         len(res["smoke"]), res["elapsed_s"]))
            for r in res["reasons"]:
                print("  lý do: " + r)
            for t in res["tests"] + res["smoke"]:
                print("  " + t)
        return 0
    try:
        if a.cmd == "gen":
            path, auto, tm = gen(project, a.write_core)
            print("đã ghi %s (%d file có test, %d lõi tự sinh)" % (path, len(tm), len(auto)))
            for p, why in auto:
                print("  %s  # %s" % (p, why))
            return 0
        print(json.dumps(explain(project, a.file.replace("\\", "/")), ensure_ascii=False, indent=1))
        return 0
    except (RuntimeError, OSError, subprocess.SubprocessError) as ex:
        print("scoped_gate: %s" % ex, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
