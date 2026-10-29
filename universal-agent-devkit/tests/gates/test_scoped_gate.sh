#!/usr/bin/env bash
# Test hồi quy (#644): bin/scoped_gate.py chọn test theo đồ thị tham chiếu BẮC CẦU và leo "full" khi không chắc (fail closed).
#   a. diff chỉ docs ⇒ scoped, tests rỗng, smoke có;
#   b. sửa lib/b.py, tests/x/test_a.sh chỉ gọi a.py (a.py `import b`) ⇒ chọn test_a.sh (bắc cầu, không nhắc tên b.py);
#   c. sửa file khớp [core] ⇒ full; repo không có gate-core.txt: lõi mặc định (package.json) ⇒ full; bao đóng không đi xuyên lõi;
#   d. code không test nào phủ (chỉ luật ma trận bắt-tất-cả `lib/*` khớp) ⇒ full, reasons nêu unmapped;
#   e. đột biến: làm vỡ hàm trong b.py, chạy đúng các test decide chọn ⇒ có test ĐỎ (trước đột biến: XANH);
#   f. fan-in ≥ 5 file không phải test ⇒ lõi (full); 5 test cùng tham chiếu một file KHÔNG làm nó thành lõi;
#   g. base sai ⇒ full;
#   h. file chỉ có luật ma trận cụ thể (không bắt-tất-cả) phủ ⇒ scoped, không unmapped;
#   i. file code bị xoá ⇒ full;
#   j. test bị sửa tự chọn chính nó; tests/impact_map.txt của kit thêm cạnh test→file;
#   k. CLI: `decide --json` và `gen --write-core` (giữ [core] + [smoke], viết [core:auto] có file fan-in ≥ 5).
# Chưa có bin/scoped_gate.py thì ĐỎ. Python stdlib, tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SG="$DEVKIT_DIR/bin/scoped_gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SB="$TMP/repo"
mkdir -p "$SB" && cd "$SB" || exit 2
git init -q -b main . && git config user.email t@t && git config user.name t

# --- sandbox: mọi thứ nằm trong commit gốc, mỗi ca chỉ đổi cây làm việc rồi decide(base="HEAD")
mkdir -p lib hub tool svc docs tests/x tests/y .agents universal-agent-devkit/lib universal-agent-devkit/tests/x
printf 'import b\nprint(b.double(21))\n' > lib/a.py
printf 'def double(x):\n    return x * 2\n' > lib/b.py
printf 'import leaf\nX = leaf.Y\n' > lib/core_x.py
printf 'Y = 1\n' > lib/leaf.py
printf '#!/usr/bin/env bash\npython3 lib/core_x.py\n' > tests/x/test_core.sh
mkdir -p bin
printf '# chạy kèm f2.py như lệnh con (chỉ nhắc tên)\nfrom lib import f\n' > bin/corehub.py
printf 'def g():\n    return 1\n' > lib/f.py
printf 'def h():\n    return 1\n' > lib/f2.py
printf '#!/usr/bin/env bash\npython3 bin/corehub.py\n' > tests/x/test_corehub.sh
printf '#!/usr/bin/env bash\npython3 lib/f2.py\n' > tests/x/test_f2.sh
printf 'Y = 1\n' > lib/orphan.py
printf 'Z = 1\n' > lib/gone.py
printf 'def f():\n    return 1\n' > hub/hub.py
for i in 1 2 3 4 5; do printf 'import hub\nhub.f()\n' > "hub/m$i.py"; done
printf '#!/usr/bin/env bash\necho tool\n' > tool/tool.sh
printf 'PORT = 1\n' > svc/server.py
printf '# docs\n' > docs/x.md
# l. test đọc tài liệu qua biến (không nhắc đường dẫn đầy đủ): cạnh nhắc tên basename tới mọi file, như grep -F của run_impacted
mkdir -p profiles/x && printf '# design\nmàu: x\n' > profiles/x/DESIGN.md
printf '#!/usr/bin/env bash\nP=profiles/x\ngrep -q "màu" "$P/DESIGN.md"\n' > tests/x/test_design.sh
# l2. tài liệu ≥ 5 test đọc ⇒ lõi (test-read-by), như fan-in
printf '# chung\n' > docs/shared.md
mkdir -p tests/z && for i in 1 2 3 4 5; do printf '#!/usr/bin/env bash\ngrep -q chung docs/shared.md\nfor d in skills/*; do test -f "$d/SKILL.md"; done\n' > "tests/z/test_r$i.sh"; done
# l3. */SKILL.md như run_impacted: theo tên thư mục skill nguyên từ, không theo basename "SKILL.md" (5 test trên nhắc nó)
mkdir -p skills/foo-bar && printf '# foo\n' > skills/foo-bar/SKILL.md
printf '#!/usr/bin/env bash\nS=skills/foo-bar\ngrep -q foo "$S/SKILL.md"\n' > tests/x/test_foo.sh
cat > tests/x/test_a.sh <<'SH'
#!/usr/bin/env bash
# chạy a.py, kỳ vọng 42
D="$(cd "$(dirname "$0")/../.." && pwd)"
[ "$(python3 "$D/lib/a.py")" = 42 ] || { echo "✖ a.py không ra 42"; exit 1; }
echo "✔ a.py ra 42"
SH
printf '#!/usr/bin/env bash\nexit 0\n' > tests/x/test_smoke.sh
printf '#!/usr/bin/env bash\nbash "$(dirname "$0")/../../hub/m1.py" 2>/dev/null; grep -q f hub/hub.py\n' > tests/x/test_hub.sh
for i in 1 2 3 4 5; do printf '#!/usr/bin/env bash\nbash ../../tool/tool.sh\n' > "tests/y/test_t$i.sh"; done
printf 'D=1\n' > universal-agent-devkit/lib/hidden.py
printf '#!/usr/bin/env bash\nexit 0\n' > universal-agent-devkit/tests/x/test_hidden.sh
printf '# glob tương đối kit   test\nlib/hidden.py   tests/x/test_hidden.sh\n' > universal-agent-devkit/tests/impact_map.txt
cat > .agents/gate-core.txt <<'TXT'
# lõi thử nghiệm
[core]
lib/core_*.py   # lõi viết tay
bin/corehub.py
[core:auto]
[smoke]
tests/x/test_smoke.sh
TXT
cat > .agents/regression_matrix.active.json <<'JSON'
{"rules": [
  {"component": "bat-tat-ca", "watch_files": ["lib/*"], "mandatory_regression_tests": [{"id": "REG-ALL", "command": "true"}]},
  {"component": "svc", "watch_files": ["svc/server.py"], "mandatory_regression_tests": [{"id": "REG-SVC", "command": "true"}]}
]}
JSON
git add -A && git commit -qm base || exit 2
cd "$TMP" || exit 2

# repo thứ hai: không có .agents/gate-core.txt (lõi mặc định trong code)
SB2="$TMP/repo2"
mkdir -p "$SB2" && cd "$SB2" || exit 2
git init -q -b main . && git config user.email t@t && git config user.name t
printf '{"name": "x"}\n' > package.json && printf 'X = 1\n' > app.py
git add -A && git commit -qm base || exit 2
cd "$TMP" || exit 2

python3 -I - "$SG" "$SB" "$SB2" <<'PY'
import fnmatch, json, os, subprocess, sys

SG, SB, SB2 = sys.argv[1], sys.argv[2], sys.argv[3]
fails = 0


def chk(cond, name, why=""):
    global fails
    print(("✔ " if cond else "✖ ") + name + ("" if cond or not why else " — " + str(why)), flush=True)
    if not cond:
        fails += 1


if not os.path.isfile(SG):
    print("✖ không có bin/scoped_gate.py: chưa có bộ chọn test theo đồ thị", flush=True)
    sys.exit(1)
sys.path.insert(0, os.path.dirname(SG))
import scoped_gate as sg  # noqa: E402


def git(*a, cwd=SB):
    return subprocess.run(["git", "-C", cwd] + list(a), capture_output=True, text=True, timeout=60)


def reset():
    git("checkout", "-q", "-f", "HEAD")
    git("clean", "-fdq")


def edit(path, text, cwd=SB):
    with open(os.path.join(cwd, path), "w") as f:
        f.write(text)


def decide(**kw):
    return sg.decide(SB, "HEAD", **kw)


# a. chỉ docs
reset()
edit("docs/x.md", "# docs đổi\n")
d = decide()
chk(d["mode"] == "scoped" and d["tests"] == [] and d["docs"] == ["docs/x.md"] and d["smoke"] == ["tests/x/test_smoke.sh"],
    "a. diff chỉ docs ⇒ scoped, tests rỗng, smoke có", d)

# b. bắc cầu: test_a.sh → a.py → b.py
reset()
edit("lib/b.py", "def double(x):\n    # chú thích\n    return x * 2\n")
d = decide()
chk(d["mode"] == "scoped" and "tests/x/test_a.sh" in d["tests"] and not d["unmapped"],
    "b. sửa lib/b.py ⇒ chọn tests/x/test_a.sh qua a.py (import b)", d)
chk("tests/y/test_t1.sh" not in d["tests"], "b2. không chọn test không liên quan", d["tests"])

# e. đột biến: test decide chọn phải ĐỎ khi b.py vỡ, XANH khi chưa vỡ
sel = d["tests"] + d["smoke"]
before = [subprocess.run(["bash", os.path.join(SB, t)], cwd=SB, capture_output=True, timeout=60).returncode for t in sel]
edit("lib/b.py", "def double(x):\n    return x * 3\n")
d2 = decide()
sel2 = d2["tests"] + d2["smoke"]
after = [subprocess.run(["bash", os.path.join(SB, t)], cwd=SB, capture_output=True, timeout=60).returncode for t in sel2]
chk(before and all(rc == 0 for rc in before), "e1. trước đột biến: mọi test được chọn XANH", list(zip(sel, before)))
chk(d2["mode"] == "scoped" and any(rc != 0 for rc in after), "e2. đột biến b.py: có test được chọn ĐỎ", list(zip(sel2, after)))

# c. lõi viết tay
reset()
edit("lib/core_x.py", "X = 2\n")
d = decide()
chk(d["mode"] == "full" and "lib/core_x.py" in d["core_hits"], "c. sửa file khớp [core] ⇒ full", d)
# c2. không có gate-core.txt: lõi mặc định
d = sg.decide(SB2, "HEAD", changed=["package.json"])
chk(d["mode"] == "full" and "package.json" in d["core_hits"], "c2. không có gate-core.txt: package.json là lõi mặc định ⇒ full", d)
lc2 = sg.load_core(SB2)
chk(any(fnmatch.fnmatch("package.json", g) for g in lc2["core"]) and any(fnmatch.fnmatch("tests/lib/x.sh", g) for g in lc2["core"]),
    "c3. load_core mặc định có package*.json và tests/lib/*", lc2)

# c4. file mà file lõi import (bắc cầu) cũng là lõi: dep-of-core ⇒ full
reset()
edit("lib/leaf.py", "Y = 2\n")
d = decide()
chk(d["mode"] == "full" and "lib/leaf.py" in d["core_hits"] and any(r.startswith("dep-of-core: lib/leaf.py") for r in d["reasons"]),
    "c4. lõi import leaf.py ⇒ leaf.py là dep-of-core ⇒ full", d)
# c5. hub lõi import lib/f.py, test chỉ gọi hub ⇒ sửa f.py ⇒ full (fail closed, không còn hở qua lớp chặn)
reset()
edit("lib/f.py", "def g():\n    return 2\n")
d = decide()
chk(d["mode"] == "full" and any(r == "dep-of-core: lib/f.py ← bin/corehub.py" for r in d["reasons"]),
    "c5. test chỉ chạm f.py qua hub lõi (import) ⇒ full, lý do dep-of-core", d)
# c6. f2.py chỉ được hub NHẮC TÊN trong chú thích: không phải lõi ⇒ scoped với test riêng của nó, không chọn qua hub
reset()
edit("lib/f2.py", "def h():\n    return 2\n")
d = decide()
chk(d["mode"] == "scoped" and "lib/f2.py" not in d["core_hits"] and d["tests"] == ["tests/x/test_f2.sh"],
    "c6. f2.py chỉ được hub lõi nhắc tên ⇒ vẫn scoped, chỉ test_f2.sh", d)

# d. không test nào phủ, chỉ luật bắt-tất-cả lib/* khớp
reset()
edit("lib/orphan.py", "Y = 2\n")
d = decide()
chk(d["mode"] == "full" and "lib/orphan.py" in d["unmapped"] and any("unmapped" in r for r in d["reasons"]),
    "d. code không test nào phủ (chỉ luật bắt-tất-cả) ⇒ full, reasons nêu unmapped", d)

# f. fan-in
g = sg.build_graph(SB)
fi = sg.fan_in(g)
chk(fi.get("hub/hub.py", 0) >= 5, "f1. hub.py có fan-in ≥ 5 từ file không phải test", fi.get("hub/hub.py"))
chk(fi.get("tool/tool.sh", 0) == 0, "f2. tool.sh chỉ được 5 test tham chiếu ⇒ fan-in 0 (test không tính)", fi.get("tool/tool.sh"))
reset()
edit("hub/hub.py", "def f():\n    return 2\n")
d = decide()
chk(d["mode"] == "full" and "hub/hub.py" in d["core_hits"], "f3. sửa file fan-in ≥ 5 ⇒ lõi ⇒ full", d)
reset()
edit("tool/tool.sh", "#!/usr/bin/env bash\necho tool2\n")
d = decide()
chk(d["mode"] == "scoped" and all("tests/y/test_t%d.sh" % i in d["tests"] for i in range(1, 6)),
    "f4. sửa tool.sh ⇒ scoped, chọn 5 test tham chiếu nó", d)

# g. base sai
d = sg.decide(SB, "khong-co-ref-nay")
chk(d["mode"] == "full" and d["reasons"], "g. base sai ⇒ full", d)

# h. luật ma trận cụ thể
reset()
edit("svc/server.py", "PORT = 2\n")
d = decide()
chk(d["mode"] == "scoped" and not d["unmapped"], "h. file chỉ có luật ma trận cụ thể phủ ⇒ scoped", d)
d = decide(matrix_rules=[])
chk(d["mode"] == "full" and "svc/server.py" in d["unmapped"], "h2. matrix_rules=[] ⇒ cùng file đó unmapped ⇒ full", d)

# i. xoá file code
reset()
os.remove(os.path.join(SB, "lib/gone.py"))
d = decide()
chk(d["mode"] == "full" and any("lib/gone.py" in r for r in d["reasons"]), "i. file code bị xoá ⇒ full", d)
chk("lib/gone.py" in sg.changed_files(SB, "HEAD"), "i2. changed_files có file bị xoá", sg.changed_files(SB, "HEAD"))

# j. test bị sửa chọn chính nó; impact_map của kit
reset()
edit("tests/x/test_a.sh", open(os.path.join(SB, "tests/x/test_a.sh")).read() + "# thêm\n")
d = decide()
chk(d["mode"] == "scoped" and d["tests"] == ["tests/x/test_a.sh"], "j1. test bị sửa tự chọn chính nó", d)
reset()
edit("universal-agent-devkit/lib/hidden.py", "D=2\n")
d = decide()
chk(d["mode"] == "scoped" and "universal-agent-devkit/tests/x/test_hidden.sh" in d["tests"],
    "j2. tests/impact_map.txt của kit: cạnh test→file", d)
tm = sg.test_map(SB)
chk("tests/x/test_a.sh" in tm.get("lib/b.py", []), "j3. test_map: lib/b.py ← tests/x/test_a.sh", tm.get("lib/b.py"))

# l. tài liệu đọc qua biến "$P/DESIGN.md": sửa nó chọn test đọc nó (docs vẫn cộng test trên map)
reset()
edit("profiles/x/DESIGN.md", "# design\nmàu: y\n")
d = decide()
chk(d["mode"] == "scoped" and d["tests"] == ["tests/x/test_design.sh"], "l. sửa profiles/x/DESIGN.md ⇒ chọn đúng test đọc \"$P/DESIGN.md\"", d)
reset()
edit("docs/shared.md", "# chung đổi\n")
d = decide()
chk(d["mode"] == "full" and "docs/shared.md" in d["core_hits"] and any(r == "test-read-by: 5 test: docs/shared.md" for r in d["reasons"]),
    "l2. tài liệu 5 test đọc ⇒ lõi (test-read-by: 5 test) ⇒ full", d)
reset()
edit("skills/foo-bar/SKILL.md", "# foo đổi\n")
d = decide()
chk(d["mode"] == "scoped" and d["tests"] == ["tests/x/test_foo.sh"],
    "l3. */SKILL.md theo tên skill (foo-bar): chỉ test nhắc tên đó, 5 test nhắc \"SKILL.md\" không làm nó thành lõi", d)

# k. CLI
reset()
edit("lib/b.py", "def double(x):\n    return x + x\n")
r = subprocess.run([sys.executable, SG, "decide", "--base", "HEAD", "--project", SB, "--json"], capture_output=True, text=True, timeout=120)
try:
    j = json.loads(r.stdout)
except ValueError:
    j = {}
chk(r.returncode == 0 and j.get("mode") == "scoped" and "tests/x/test_a.sh" in j.get("tests", []) and "elapsed_s" in j,
    "k1. CLI decide --json", (r.returncode, r.stdout[-300:], r.stderr[-300:]))
reset()
r = subprocess.run([sys.executable, SG, "gen", "--project", SB, "--write-core"], capture_output=True, text=True, timeout=120)
core_txt = open(os.path.join(SB, ".agents/gate-core.txt")).read()
common = git("rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip()
chk(r.returncode == 0 and os.path.isfile(os.path.join(common, "postfix-gate", "gate-test-map.json")),
    "k2. gen ghi <git common dir>/postfix-gate/gate-test-map.json", (r.returncode, r.stderr[-300:]))
auto = core_txt.split("[core:auto]", 1)[-1].split("[smoke]", 1)[0]
chk("lib/core_*.py   # lõi viết tay" in core_txt and "tests/x/test_smoke.sh" in core_txt and "hub/hub.py" in auto
    and "tool/tool.sh" not in auto, "k3. gen --write-core: giữ [core] + [smoke], [core:auto] có hub.py, không có tool.sh", core_txt)
chk("docs/shared.md" in auto and "test-read-by: 5 test" in auto and "profiles/x/DESIGN.md" not in auto,
    "k3b. [core:auto] có tài liệu ≥ 5 test đọc (test-read-by), không có tài liệu 1 test đọc", auto)
lc = sg.load_core(SB)
chk("hub/hub.py" in lc["core"] and "lib/core_*.py" in lc["core"] and lc["smoke"] == ["tests/x/test_smoke.sh"],
    "k4. load_core đọc lại [core] ∪ [core:auto] và [smoke] (bỏ `# lý do`)", lc)
r = subprocess.run([sys.executable, SG, "explain", "lib/b.py", "--project", SB], capture_output=True, text=True, timeout=120)
chk(r.returncode == 0 and "tests/x/test_a.sh" in r.stdout, "k5. CLI explain lib/b.py nêu test phủ nó", (r.returncode, r.stdout[-300:]))

print("---")
print("FAIL: %d" % fails if fails else "PASS")
sys.exit(1 if fails else 0)
PY
