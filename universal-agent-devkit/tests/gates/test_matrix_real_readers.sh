#!/usr/bin/env bash
# Test canh (P6, gate kẹt và chậm 02/11): scoped_gate.decide coi PR chỉ nối rule ma trận là "chỉ chạy test đọc ma trận THẬT" = test trong
# lệnh mandatory_regression_tests của mọi rule có .agents/regression_matrix.active.json trong watch_files. Test mở ma trận thật của gốc repo
# (biến gốc repo dựng từ dirname $0 + đường dẫn ma trận: "$ROOT/.agents/…", root + "/.agents/…", os.path.join(root, ".agents/…"))
# mà không nằm trong danh sách đó thì PR nối rule bỏ sót nó ⇒ ĐỎ. Test chỉ dựng ma trận giả trong fixture ("$TMP/.agents/…") không tính.
# Repo không có ma trận ở gốc (kit cài vào app qua .agents/devkit) ⇒ bỏ qua. Python stdlib, tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
[ -f "$ROOT/.agents/regression_matrix.active.json" ] || { echo "skip: $ROOT không có .agents/regression_matrix.active.json"; exit 0; }
python3 -I - "$DEVKIT_DIR/bin" "$ROOT" "$ROOT/.agents/regression_matrix.active.json" <<'PY'
import json, os, posixpath, re, shlex, subprocess, sys

BIN, ROOT, MATRIX = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path.insert(0, BIN)
from scoped_gate import MATRIX_FILE, is_test  # noqa: E402

MX = re.compile(r"\.agents(?:/|[\"']\s*[,/]\s*[\"'])regression_matrix\.active\.json")
# VAR="$(cd "$(dirname "$0")/../.." && pwd)" (cả ${BASH_SOURCE[0]})
DEF = re.compile(r"\b([A-Za-z_]\w*)=\"?\$\(\s*cd\s+\"?\$\(dirname\s+\"?\$\{?(?:0|BASH_SOURCE(?:\[0\])?)\}?\"?\)([^\"&)\s]*)")
# VAR=$(git rev-parse --show-toplevel) ⇒ gốc repo
TOP = re.compile(r"\b([A-Za-z_]\w*)=\"?\$\(\s*git\b[^)\n]*rev-parse\b[^)\n]*--show-toplevel")
# VAR = Path(__file__)[.resolve()].parents[N] ⇒ lên N cấp từ thư mục của test
PARENTS = re.compile(r"\b([A-Za-z_]\w*)\s*=\s*(?:pathlib\.)?Path\(\s*__file__\s*\)(?:\.resolve\(\))?\.parents\[(\d+)\]")
# phần trước đường dẫn ma trận (bỏ nháy, khoảng trắng): $VAR/  ${VAR}/..  VAR+/  VAR,  Path(VAR)/
PRE = re.compile(r"(?:\$\{?(\w+)\}?|(?<![\w$])(\w+)\)?(?:\+|,|/))((?:/?\.\.)*)/?$")


def real_reader(rel, text):
    """True khi test `rel` (đường dẫn từ gốc repo) mở ma trận ở gốc repo qua biến dựng từ dirname $0."""
    roots = {}
    for m in DEF.finditer(text):
        d = posixpath.normpath(posixpath.join(posixpath.dirname(rel), m.group(2).lstrip("/")))
        roots.setdefault(m.group(1), d)               # định nghĩa đầu tiên của biến thắng
        roots.setdefault(m.group(1).lower(), d)       # root trong heredoc Python nhận "$ROOT"
    for m in TOP.finditer(text):
        roots.setdefault(m.group(1), ".")
        roots.setdefault(m.group(1).lower(), ".")
    for m in PARENTS.finditer(text):
        d = posixpath.normpath(posixpath.join(posixpath.dirname(rel), *([".."] * int(m.group(2)))))
        roots.setdefault(m.group(1), d)
        roots.setdefault(m.group(1).lower(), d)
    for line in text.splitlines():
        for m in MX.finditer(line):
            p = PRE.search(re.sub(r"[\"'\s]", "", line[:m.start()]))
            name = p and (p.group(1) or p.group(2))
            if name in roots and posixpath.normpath(posixpath.join(roots[name], p.group(3).lstrip("/"))) == ".":
                return True
    return False


fails = 0


def chk(cond, name, why=""):
    global fails
    print(("✔ " if cond else "✖ ") + name + ("" if cond or not why else " — " + str(why)), flush=True)
    if not cond:
        fails += 1


# bộ dò không rỗng: mẫu dương (3 dạng đang có) và âm (ma trận giả trong fixture, sao profile vào cwd)
D2 = 'ROOT="$(cd "$(dirname "$0")/../.." && pwd)"\n'
chk(all(real_reader("tests/a/test_x.sh", D2 + s) for s in (
    'cat "$ROOT/.agents/regression_matrix.active.json"\n',
    'python3 - "$ROOT" <<P\nroot = sys.argv[1]\ncur = json.load(open(root + "/.agents/regression_matrix.active.json"))\nP\n',
    'p = os.path.join(root, ".agents", "regression_matrix.active.json")\n',
    'D="$(cd "$(dirname "$0")/.." && pwd)"\ncat "$D/../.agents/regression_matrix.active.json"\n',
    'TOP="$(git rev-parse --show-toplevel)"\ncat "$TOP/.agents/regression_matrix.active.json"\n',
    'import pathlib\nrepo = Path(__file__).resolve().parents[2]\nopen(repo / ".agents/regression_matrix.active.json")\n',
    'repo = Path(__file__).parents[2]\nopen(os.path.join(repo, ".agents", "regression_matrix.active.json"))\n')),
    "bộ dò bắt test đọc ma trận ở gốc repo")
chk(not any(real_reader("tests/a/test_x.sh", D2 + s) for s in (
    'cat > "$TMP/.agents/regression_matrix.active.json" <<J\n{}\nJ\n',
    'cp "$ROOT/templates/regression_matrix.json" .agents/regression_matrix.active.json\n',
    'D="$(cd "$(dirname "$0")/.." && pwd)"\ncat "$D/.agents/regression_matrix.active.json"\n',
    'repo = Path(__file__).resolve().parents[1]\nopen(repo / ".agents/regression_matrix.active.json")\n')),
    "bộ dò bỏ qua ma trận giả trong fixture / thư mục không phải gốc repo")

cur = json.load(open(MATRIX, encoding="utf-8"))
listed, bad = set(), []
for r in cur.get("rules", []):
    if MATRIX_FILE in (r.get("watch_files") or []):
        for t in r.get("mandatory_regression_tests") or []:
            got = [w for w in shlex.split(t.get("command") or "") if is_test(w) and os.path.isfile(os.path.join(ROOT, w))]
            listed |= set(got)
            if not got:
                bad.append(t.get("id"))
chk(not bad, "mọi lệnh của rule theo dõi ma trận chỉ ra một file test có thật", bad)

ls = subprocess.run(["git", "-C", ROOT, "ls-files", "-z", "-co", "--exclude-standard"], capture_output=True)
chk(ls.returncode == 0, "git ls-files ở gốc repo", ls.stderr.decode("utf-8", "replace")[:200])
found = set()
for rel in sorted({p for p in ls.stdout.decode("utf-8", "surrogateescape").split("\0") if p}):
    if not is_test(rel) or os.path.islink(os.path.join(ROOT, rel)):
        continue
    try:
        with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        continue
    if "regression_matrix.active.json" in text and real_reader(rel, text):
        found.add(rel)
chk(found, "tìm thấy ít nhất một test đọc ma trận thật (chính test này)", sorted(found))
miss = sorted(found - listed)
chk(not miss, "mọi test đọc ma trận thật nằm trong rule có %s trong watch_files (%d test)" % (MATRIX_FILE, len(found)), miss)
print("PASS" if not fails else "FAIL: %d" % fails)
sys.exit(1 if fails else 0)
PY
