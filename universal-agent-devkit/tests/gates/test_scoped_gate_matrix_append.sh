#!/usr/bin/env bash
# Test hồi quy (P6, gate kẹt và chậm 02/11): PR chỉ NỐI rule vào .agents/regression_matrix.active.json bị scoped_gate.decide coi ma trận là
# lõi ([core]) và cộng mọi test nhắc tên ma trận (test-read-by: ~100 test dựng ma trận giả trong fixture), dù chỉ vài test đọc ma trận THẬT.
#   a. nối 1 rule (kèm sửa lib/a.py và thêm test mới) ⇒ ma trận không vào core_hits, vào matrix_covered; tests = test đọc thật (rule có
#      ma trận trong watch_files) + test do file khác kéo; không test chỉ-nhắc-tên nào;
#   a2. project là thư mục con của repo (git show <ref>:./…) ⇒ như a;
#   b. sửa 1 rule cũ / rule mới trùng id / trùng component / có covered_by / đổi khoá top-level / JSON hỏng / chỉ đổi định dạng ⇒ như cũ:
#      ma trận vào core_hits, mọi test nhắc tên ma trận được chọn;
#   c. changed do caller truyền (from_tree=False), base đi tiếp sau merge-base và ma trận ở base khác ⇒ như cũ (so cả merge-base lẫn base);
#   d. không rule nào theo dõi ma trận (danh sách đọc-thật rỗng) ⇒ như cũ.
# Python stdlib, tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SG="$DEVKIT_DIR/bin/scoped_gate.py"
echo "scoped_gate: $SG"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# mkrepo <thư mục project>: ma trận trong [core], 6 test chỉ nhắc tên ma trận (dựng ma trận giả), 1 test đọc ma trận thật của gốc project
mkrepo() {
  mkdir -p "$1/lib" "$1/tests/x" "$1/tests/m" "$1/tests/r" "$1/.agents" && (
    cd "$1" || exit 2
    printf 'X = 1\n' > lib/a.py
    printf '#!/usr/bin/env bash\npython3 lib/a.py\n' > tests/x/test_a.sh
    for i in 1 2 3 4 5 6; do
      printf '#!/usr/bin/env bash\nT="$(mktemp -d)"; mkdir -p "$T/.agents"\necho "{}" > "$T/.agents/regression_matrix.active.json"\n' > "tests/m/test_m$i.sh"
    done
    cat > tests/r/test_reader.sh <<'SH'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$ROOT/.agents/regression_matrix.active.json"
SH
    printf '[core]\n.agents/regression_matrix.active.json\n' > .agents/gate-core.txt
    cat > .agents/regression_matrix.active.json <<'JSON'
{
  "project": "t",
  "rules": [
    {"component": "a", "watch_files": ["lib/a.py"], "mandatory_regression_tests": [{"id": "REG-A", "command": "bash tests/x/test_a.sh"}]},
    {"component": "readers", "watch_files": [".agents/regression_matrix.active.json"],
     "mandatory_regression_tests": [{"id": "REG-R", "command": "bash tests/r/test_reader.sh"}]}
  ]
}
JSON
  )
}
SB="$TMP/repo"
mkrepo "$SB" && cd "$SB" && git init -q -b main . && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm base || exit 2
SB3="$TMP/repo3"
mkrepo "$SB3/proj" && cd "$SB3" && git init -q -b main . && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm base || exit 2
cd "$TMP" || exit 2

python3 -I - "$SG" "$SB" "$SB3/proj" <<'PY'
import json, os, subprocess, sys

SG, SB, SUB = sys.argv[1], sys.argv[2], sys.argv[3]
MX = ".agents/regression_matrix.active.json"
MENTION = {"tests/m/test_m%d.sh" % i for i in range(1, 7)}
fails = 0


def chk(cond, name, why=""):
    global fails
    print(("✔ " if cond else "✖ ") + name + ("" if cond or not why else " — " + str(why)), flush=True)
    if not cond:
        fails += 1


sys.path.insert(0, os.path.dirname(SG))
import scoped_gate as sg  # noqa: E402
chk(os.path.realpath(sg.__file__) == os.path.realpath(SG), "nạp đúng scoped_gate.py đang test", sg.__file__)


def git(*a, cwd=SB):
    return subprocess.run(["git", "-C", cwd] + list(a), capture_output=True, text=True, timeout=60)


def reset(cwd=SB):
    git("checkout", "-q", "-f", "HEAD", cwd=cwd)
    git("clean", "-fdq", cwd=cwd)


def edit(fn, root=SB, raw=None):
    p = os.path.join(root, MX)
    if raw is not None:
        open(p, "w").write(raw)
        return
    m = json.load(open(p))
    fn(m)
    json.dump(m, open(p, "w"), indent=2)


NEW = {"component": "c", "watch_files": ["lib/c.py"], "mandatory_regression_tests": [{"id": "REG-C", "command": "bash tests/x/test_c.sh"}]}


def appended(root):
    edit(lambda m: m["rules"].append(json.loads(json.dumps(NEW))), root)
    open(os.path.join(root, "lib/a.py"), "a").write("Y = 2\n")
    open(os.path.join(root, "tests/x/test_c.sh"), "w").write("#!/usr/bin/env bash\nexit 0\n")


# a. nối 1 rule + sửa lib/a.py + test mới
reset()
appended(SB)
d = sg.decide(SB, "HEAD")
chk(MX not in d["core_hits"], "a. nối rule: ma trận không vào core_hits", d["core_hits"])
chk(MX in d["matrix_covered"], "a. nối rule: ma trận vào matrix_covered", d["matrix_covered"])
chk(set(d["tests"]) == {"tests/r/test_reader.sh", "tests/x/test_a.sh", "tests/x/test_c.sh"},
    "a. nối rule: tests = test đọc thật + test do file khác kéo", d["tests"])
chk(not (MENTION & set(d["tests"])), "a. nối rule: không test chỉ-nhắc-tên ma trận nào", sorted(MENTION & set(d["tests"])))
chk(d["mode"] == "scoped" and not d["unmapped"], "a. nối rule: scoped, không unmapped", (d["mode"], d["reasons"]))

# a2. project là thư mục con của repo
reset(os.path.dirname(SUB))
appended(SUB)
d = sg.decide(SUB, "HEAD")
chk(MX not in d["core_hits"] and set(d["tests"]) == {"tests/r/test_reader.sh", "tests/x/test_a.sh", "tests/x/test_c.sh"},
    "a2. project thư mục con: nối rule ⇒ chỉ test đọc thật + test do file khác kéo", (d["core_hits"], d["tests"]))
reset(os.path.dirname(SUB))


def as_before(name, fn=None, raw=None):
    reset()
    edit(fn, raw=raw)
    d = sg.decide(SB, "HEAD")
    chk(MX in d["core_hits"] and MENTION <= set(d["tests"]) and MX not in d["matrix_covered"],
        "b. %s ⇒ như cũ: lõi, mọi test nhắc tên ma trận" % name, (d["core_hits"], d["tests"], d["matrix_covered"]))


def dup(key, val):
    def f(m):
        r = json.loads(json.dumps(NEW))
        if key == "component":
            r["component"] = val
        else:
            r["mandatory_regression_tests"][0][key] = val
        m["rules"].append(r)
    return f


as_before("sửa 1 rule cũ", lambda m: m["rules"][0]["mandatory_regression_tests"][0].update(command="bash tests/x/test_a.sh -v"))
as_before("rule mới trùng id", dup("id", "REG-A"))
as_before("rule mới trùng component", dup("component", "a"))
as_before("rule mới có covered_by", dup("covered_by", "REG-A"))
as_before("đổi khoá top-level + nối rule", lambda m: (m.update(project="u"), m["rules"].append(json.loads(json.dumps(NEW)))))
as_before("JSON hỏng", raw='{"rules": [\n')
as_before("chỉ đổi định dạng (không rule mới)", lambda m: None)

# c. changed do caller truyền, base (nhánh main) đi tiếp sau merge-base với ma trận khác ⇒ như cũ
reset()
git("checkout", "-q", "-b", "feat")
git("checkout", "-q", "main")
edit(lambda m: m["rules"].append({"component": "x", "watch_files": ["lib/x.py"],
                                  "mandatory_regression_tests": [{"id": "REG-X", "command": "bash tests/x/test_a.sh"}]}))
git("commit", "-qam", "main nối rule x")
git("checkout", "-q", "feat")
edit(lambda m: m["rules"].append(json.loads(json.dumps(NEW))))
d = sg.decide(SB, "main", changed=[MX])
chk(MX in d["core_hits"] and MENTION <= set(d["tests"]), "c. base đi tiếp, ma trận ở base khác ⇒ như cũ", (d["core_hits"], d["tests"]))
d = sg.decide(SB, "main")
chk(MX not in d["core_hits"] and d["tests"] == ["tests/r/test_reader.sh"],
    "c2. cùng cây, changed tự tính theo merge-base ⇒ chỉ-nối so với merge-base: chỉ test đọc thật", (d["core_hits"], d["tests"]))
git("checkout", "-q", "-f", "main")

# d. không rule nào theo dõi ma trận (danh sách đọc-thật rỗng) ⇒ như cũ, không chọn 0 test (review vòng 1)
reset()
edit(lambda m: [r.__setitem__("watch_files", [w for w in r.get("watch_files") or [] if w != MX]) for r in m["rules"]])
git("commit", "-qam", "bỏ ma trận khỏi watch_files")
as_before("không rule nào theo dõi ma trận + nối rule", lambda m: m["rules"].append(json.loads(json.dumps(NEW))))

print("PASS" if not fails else "FAIL: %d" % fails)
sys.exit(1 if fails else 0)
PY
