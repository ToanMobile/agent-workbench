#!/usr/bin/env bash
# Test hồi quy (#788): bin/scoped_gate.py thu hẹp cạnh tài liệu/dữ liệu đa vị trí (by_data) theo đường dẫn tĩnh có kiểm chứng:
#   1. dirA/AGENTS.md + dirB/AGENTS.md: test_a.sh nhắc tĩnh dirA/AGENTS.md, test_b.sh nhắc tĩnh dirB/AGENTS.md, test_bare.sh nhắc trần
#      AGENTS.md (tất cả ∈ N): sửa dirB/AGENTS.md chọn test_b.sh + test_bare.sh, KHÔNG chọn test_a.sh;
#   2. hỗn hợp (OCR4-3): test_mix.sh nhắc tĩnh dirA/AGENTS.md VÀ `cd "$ROOT/dirB" && grep … AGENTS.md` ⇒ sửa dirB/AGENTS.md vẫn chọn;
#   3. động (AG2-P0, OCR2-H1, P1-AG2): a/sub/AGENTS.md + b/AGENTS.md; 5 dạng động (`$(…)/sub/AGENTS.md`, `"${ROOT}/sub/AGENTS.md"`,
#      `"$REPO_DIR"/sub/AGENTS.md`, Python `f"{repo}/sub/AGENTS.md"`, `../sub/AGENTS.md`) ⇒ sửa b/AGENTS.md vẫn chọn cả 5;
#      test_two.sh nhắc tĩnh .claude/settings.json khi có .claude/settings.json + kit/.claude/settings.json ⇒ sửa file nào cũng chọn;
#      test_miss.sh nhắc tĩnh a/sub/AGENTS.md + c/AGENTS.md (không tồn tại) ⇒ giữ mọi cạnh cũ;
#   4. mồ côi & fail-closed (P1-3, AG2-P2, CL2-P2-4): test ngoài N (tests/super-board/test_orph.sh, hoặc matrix chỉ ghi basename) giữ cạnh cũ;
#      ma trận hỏng JSON ⇒ N rỗng ⇒ giữ cạnh cũ; basename có symlink tracked (mode 120000) ⇒ không thu hẹp base đó;
#   5. ranh giới subproject (#776): mcp-servers/pkgA/AGENTS.md + universal-agent-devkit/tests/gates/test_dk.sh ghi `"$TMP/AGENTS.md"`
#      ⇒ sửa mcp-servers/pkgA/AGENTS.md không chọn test_dk.sh, vẫn chọn tests/super-board/test_root.sh;
#   6. explain trên repo thật: scoped_gate.py explain chọn chính test_scoped_gate_path_data.sh khi sửa scoped_gate.py.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -uo pipefail

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPO_ROOT="$(cd "$DEVKIT_DIR/.." && pwd)"
SG="$DEVKIT_DIR/bin/scoped_gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DEVKIT_DIR="$DEVKIT_DIR" REPO_ROOT="$REPO_ROOT" SG="$SG" TMP="$TMP" python3 - <<'PY'
import importlib.util
import json
import os
import subprocess
import sys

DEVKIT_DIR = os.environ["DEVKIT_DIR"]
REPO_ROOT = os.environ["REPO_ROOT"]
SG = os.environ["SG"]
TMP = os.environ["TMP"]

spec = importlib.util.spec_from_file_location("scoped_gate", SG)
sg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sg)

fails = 0


def chk(cond, msg, detail=None):
    global fails
    if cond:
        print("✔ " + msg)
    else:
        fails += 1
        print("✖ " + msg + (" — %r" % (detail,) if detail is not None else ""))


def git(cwd, *args):
    r = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise RuntimeError("git %s: %s" % (" ".join(args), r.stderr))
    return r


def write(root, rel, content, mode=0o644):
    full = os.path.join(root, rel)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as f:
        f.write(content)
    os.chmod(full, mode)


def init_repo(name):
    d = os.path.join(TMP, name)
    os.makedirs(d, exist_ok=True)
    git(d, "init", "-q", "-b", "main", ".")
    git(d, "config", "user.email", "t@t")
    git(d, "config", "user.name", "t")
    return d


# --- Ca 1, 2, 4, 5: repo R1 ---
R1 = init_repo("r1")
write(R1, "AGENTS.md", "# root\n")
write(R1, "dirA/AGENTS.md", "# dirA\n")
write(R1, "dirB/AGENTS.md", "# dirB\n")
write(R1, "mcp-servers/pkgA/AGENTS.md", "# pkgA\n")
write(R1, "universal-agent-devkit/AGENTS.md", "# dk\n")
write(R1, "universal-agent-devkit/bin/agent-kit", "#!/usr/bin/env bash\nexit 0\n", 0o755)
write(R1, "skills/my-skill/SKILL.md", "# skill\n")
write(R1, "skills/other-skill/SKILL.md", "# other\n")
write(R1, "tests/g/test_skill.sh", '#!/usr/bin/env bash\ngrep -q skill "$S/my-skill/SKILL.md"\n', 0o755)

# Ca 1: tĩnh dirA, tĩnh dirB (kèm ./dirB), nhắc trần AGENTS.md
write(R1, "tests/g/test_a.sh", '#!/usr/bin/env bash\ngrep -q dirA "dirA/AGENTS.md"\n', 0o755)
write(R1, "tests/g/test_b.sh", '#!/usr/bin/env bash\ngrep -q dirB ./dirB/AGENTS.md\n', 0o755)
write(R1, "tests/g/test_bare.sh", '#!/usr/bin/env bash\ncd dirB && grep -q dirB AGENTS.md\n', 0o755)

# Ca 2: hỗn hợp tĩnh dirA/AGENTS.md + nhắc trần AGENTS.md
write(R1, "tests/g/test_mix.sh", '#!/usr/bin/env bash\ntest -f dirA/AGENTS.md\ncd "$ROOT/dirB" && grep -q dirB AGENTS.md\n', 0o755)

# Ca 4: test mồ côi + chỉ gọi basename (AG2-P2) + có covered_by / untested_exit / adb (CL3-P2-8)
write(R1, "tests/super-board/test_orph.sh", '#!/usr/bin/env bash\ngrep -q dirA dirA/AGENTS.md\n', 0o755)
write(R1, "tests/super-board/test_base_only.sh", '#!/usr/bin/env bash\ngrep -q dirA dirA/AGENTS.md\n', 0o755)
write(R1, "tests/super-board/test_covby.sh", '#!/usr/bin/env bash\ngrep -q dirA dirA/AGENTS.md\n', 0o755)
write(R1, "tests/super-board/test_adb.sh", '#!/usr/bin/env bash\ngrep -q dirA dirA/AGENTS.md\n', 0o755)

# Ca 5: ranh giới subproject mcp-servers/<pkg>/ vs universal-agent-devkit/
write(R1, "universal-agent-devkit/tests/gates/test_dk.sh", '#!/usr/bin/env bash\ngrep -q x "$TMP/AGENTS.md"\n', 0o755)
write(R1, "universal-agent-devkit/hooks/tests/test_hk.sh", '#!/usr/bin/env bash\ngrep -q x "$TMP/AGENTS.md"\n', 0o755)
write(R1, "tests/super-board/test_root.sh", '#!/usr/bin/env bash\ngrep -q x "$TMP/AGENTS.md"\n', 0o755)

# Ca 4b (CL2-P2-4): basename có symlink tracked (mode 120000) ⇒ không thu hẹp base đó
write(R1, "realA/RULES.md", "rule A\n")
write(R1, "realB/RULES.md", "rule B\n")
os.makedirs(os.path.join(R1, "linkdir"), exist_ok=True)
os.symlink("../realA/RULES.md", os.path.join(R1, "linkdir/RULES.md"))
write(R1, "tests/g/test_sym_rule.sh", '#!/usr/bin/env bash\ngrep -q A realA/RULES.md\n', 0o755)

write(R1, ".agents/gate-core.txt", "[core]\n[smoke]\n")
matrix_r1 = {
    "rules": [
        {
            "component": "g",
            "watch_files": ["dirA/*"],
            "mandatory_regression_tests": [
                {"id": "R-A", "command": "bash tests/g/test_a.sh && bash ./tests/g/test_b.sh"},
                {"id": "R-BARE", "command": "bash tests/g/test_bare.sh"},
                {"id": "R-MIX", "command": "bash tests/g/test_mix.sh"},
                {"id": "R-ROOT", "command": "bash tests/super-board/test_root.sh"},
                {"id": "R-BASEONLY", "command": "cd tests/super-board && bash test_base_only.sh"},
                {"id": "R-COVBY", "command": "bash tests/super-board/test_covby.sh", "covered_by": "R-A"},
                {"id": "R-ADB", "command": "adb devices && bash tests/super-board/test_adb.sh"},
                {"id": "R-SYM", "command": "bash tests/g/test_sym_rule.sh"},
                {"id": "R-SKILL", "command": "bash tests/g/test_skill.sh"},
            ],
        }
    ]
}
write(R1, ".agents/regression_matrix.active.json", json.dumps(matrix_r1, indent=2) + "\n")
git(R1, "add", "-A")
git(R1, "commit", "-qm", "base-r1")

# Kiểm tra Ca 1, 2, 4 trên dirB/AGENTS.md
write(R1, "dirB/AGENTS.md", "# dirB changed\n")
d1 = sg.decide(R1, "HEAD")
tset1 = set(d1["tests"])
chk("tests/g/test_b.sh" in tset1 and "tests/g/test_bare.sh" in tset1 and "tests/g/test_a.sh" not in tset1,
    "1. sửa dirB/AGENTS.md chọn test_b.sh + test_bare.sh, loại test_a.sh (nhắc tĩnh dirA/AGENTS.md)", d1["tests"])
chk("tests/g/test_mix.sh" in tset1,
    "2. hỗ trợ hỗn hợp (OCR4-3): test_mix.sh vừa nhắc tĩnh dirA vừa nhắc trần AGENTS.md vẫn được chọn", d1["tests"])
chk("tests/super-board/test_orph.sh" in tset1,
    "4a. mồ côi (P1-3): tests/super-board/test_orph.sh ngoài N vẫn giữ cạnh cũ khi sửa dirB/AGENTS.md", d1["tests"])
chk("tests/super-board/test_base_only.sh" in tset1,
    "4b. AG2-P2: command ma trận chỉ ghi basename (không phải đường dẫn đầy đủ) ⇒ không vào N ⇒ giữ cạnh cũ", d1["tests"])
chk("tests/super-board/test_covby.sh" in tset1 and "tests/super-board/test_adb.sh" in tset1,
    "4f. CL3-P2-8: suite có covered_by / DEVICE_SUITE không đưa test vào N ⇒ giữ cạnh cũ", d1["tests"])

# Ngược lại sửa dirA/AGENTS.md chọn test_a.sh, không chọn test_b.sh
git(R1, "checkout", "-q", "--", ".")
write(R1, "dirA/AGENTS.md", "# dirA changed\n")
d1_rev = sg.decide(R1, "HEAD")
chk("tests/g/test_a.sh" in d1_rev["tests"] and "tests/g/test_b.sh" not in d1_rev["tests"],
    "1b. sửa dirA/AGENTS.md chọn test_a.sh, loại test_b.sh", d1_rev["tests"])

# Kiểm tra CL2-P2-4: sửa realB/RULES.md vẫn chọn test_sym_rule.sh vì RULES.md có symlink tracked (120000)
git(R1, "checkout", "-q", "--", ".")
write(R1, "realB/RULES.md", "rule B changed\n")
d_sym = sg.decide(R1, "HEAD")
chk("tests/g/test_sym_rule.sh" in d_sym["tests"],
    "4c. CL2-P2-4: RULES.md có symlink tracked (mode 120000) ⇒ không thu hẹp, sửa realB/RULES.md vẫn chọn test_sym_rule.sh", d_sym["tests"])

# Kiểm tra Ca 5: sửa mcp-servers/pkgA/AGENTS.md không chọn test_dk.sh / test_hk.sh, vẫn chọn test_root.sh + test_orph.sh
git(R1, "checkout", "-q", "--", ".")
write(R1, "mcp-servers/pkgA/AGENTS.md", "# pkgA changed\n")
d5 = sg.decide(R1, "HEAD")
tset5 = set(d5["tests"])
chk("universal-agent-devkit/tests/gates/test_dk.sh" not in tset5
    and "universal-agent-devkit/hooks/tests/test_hk.sh" not in tset5
    and "tests/super-board/test_root.sh" in tset5
    and "tests/super-board/test_orph.sh" in tset5,
    "5. subproject (#776): sửa mcp-servers/pkgA/AGENTS.md loại test_dk.sh/test_hk.sh (∈ N dưới kit), giữ test_root.sh + test_orph.sh",
    d5["tests"])

# Nhưng sửa universal-agent-devkit/AGENTS.md VẪN chọn test_dk.sh và test_hk.sh
git(R1, "checkout", "-q", "--", ".")
write(R1, "universal-agent-devkit/AGENTS.md", "# dk changed\n")
d5_dk = sg.decide(R1, "HEAD")
chk("universal-agent-devkit/tests/gates/test_dk.sh" in d5_dk["tests"]
    and "universal-agent-devkit/hooks/tests/test_hk.sh" in d5_dk["tests"],
    "5b. sửa universal-agent-devkit/AGENTS.md vẫn chọn test_dk.sh và test_hk.sh", d5_dk["tests"])

# Kiểm tra fail-closed khi ma trận lỗi JSON ⇒ N rỗng ⇒ không thu hẹp gì
git(R1, "checkout", "-q", "--", ".")
write(R1, ".agents/regression_matrix.active.json", "{broken json\n")
write(R1, "dirB/AGENTS.md", "# dirB changed\n")
d_bad = sg.decide(R1, "HEAD")
chk("tests/g/test_a.sh" in d_bad["tests"] and "universal-agent-devkit/tests/gates/test_dk.sh" in d_bad["tests"],
    "4d. fail-closed: ma trận hỏng JSON ⇒ N rỗng ⇒ không thu hẹp test_a.sh hay test_dk.sh", d_bad["tests"])

# Kiểm tra NEW-P2-3 & V4-8: decide(..., matrix_rules=...) lấy giao N(matrix_rules) ∩ N(trên đĩa), và thiếu agent-kit thì bỏ phần kit của N
git(R1, "checkout", "-q", "--", ".")
write(R1, "dirB/AGENTS.md", "# dirB changed\n")
d_moverride = sg.decide(R1, "HEAD", matrix_rules=[])
chk("tests/g/test_a.sh" in d_moverride["tests"],
    "4e. AG3-P2-3/V4-8: decide(..., matrix_rules=[]) ⇒ giao N rỗng với ma trận ⇒ test_a.sh giữ cạnh cũ", d_moverride["tests"])

git(R1, "checkout", "-q", "--", ".")
write(R1, ".agents/regression_matrix.active.json", '{"rules": []}\n')
write(R1, "dirB/AGENTS.md", "# dirB changed\n")
d_disk_empty = sg.decide(R1, "HEAD", matrix_rules=matrix_r1["rules"])
chk("tests/g/test_a.sh" in d_disk_empty["tests"],
    "4g. V4-8: ma trận trên đĩa xoá rule (dù matrix_rules còn) ⇒ N = giao hai phía ⇒ test_a.sh giữ cạnh cũ", d_disk_empty["tests"])

git(R1, "checkout", "-q", "--", ".")
os.remove(os.path.join(R1, "universal-agent-devkit/bin/agent-kit"))
write(R1, "mcp-servers/pkgA/AGENTS.md", "# pkgA changed\n")
d_no_ak = sg.decide(R1, "HEAD")
chk("universal-agent-devkit/tests/gates/test_dk.sh" in d_no_ak["tests"],
    "4h. V4-8: không có universal-agent-devkit/bin/agent-kit ⇒ test kit không vào N ⇒ giữ cạnh cũ", d_no_ak["tests"])

git(R1, "checkout", "-q", "--", ".")
write(R1, "skills/my-skill/SKILL.md", "# skill changed\n")
d_sk = sg.decide(R1, "HEAD")
chk("tests/g/test_skill.sh" in d_sk["tests"],
    "5c. V4-9: nhánh skills (SKILL.md theo tên thư mục) không bị luật 2.2 can thiệp", d_sk["tests"])


# --- Ca 3: repo R2 kiểm chứng 5 dạng động + hậu tố đa khớp + đường dẫn tĩnh trượt 0 file + hậu tố .tmp ---
R2 = init_repo("r2")
write(R2, "a/sub/AGENTS.md", "# a/sub\n")
write(R2, "b/AGENTS.md", "# b\n")
write(R2, ".claude/settings.json", '{"a": 1}\n')
write(R2, "kit/.claude/settings.json", '{"b": 2}\n')
write(R2, "subA/settings.json", '{"sa": 1}\n')
write(R2, "subB/settings.json", '{"sb": 2}\n')

write(R2, "tests/d/test_dyn1.sh", '#!/usr/bin/env bash\nS="$(cd "$D" && pwd)/sub/AGENTS.md"\ntest -f "$S"\n', 0o755)
write(R2, "tests/d/test_dyn2.sh", '#!/usr/bin/env bash\ntest -f "${ROOT}/sub/AGENTS.md"\n', 0o755)
write(R2, "tests/d/test_dyn3.sh", '#!/usr/bin/env bash\ntest -f "$REPO_DIR"/sub/AGENTS.md\n', 0o755)
write(R2, "tests/d/test_dyn4.sh", '#!/usr/bin/env bash\npython3 - <<\'EOF\'\np = f"{repo}/sub/AGENTS.md"\nEOF\n', 0o755)
write(R2, "tests/d/test_dyn5.sh", '#!/usr/bin/env bash\ntest -f ../sub/AGENTS.md\n', 0o755)
write(R2, "tests/d/test_dyn6.sh", '#!/usr/bin/env bash\npython3 - <<\'EOF\'\np = "%s/sub/AGENTS.md" % root\nEOF\n', 0o755)
write(R2, "tests/d/test_two.sh", '#!/usr/bin/env bash\ngrep -q 1 .claude/settings.json\n', 0o755)
write(R2, "tests/d/test_miss.sh", '#!/usr/bin/env bash\ntest -f a/sub/AGENTS.md\ntest -f c/AGENTS.md\n', 0o755)
write(R2, "tests/d/test_tmp.sh", '#!/usr/bin/env bash\ntest -f subA/settings.json\ncp subB/settings.json.tmp out\n', 0o755)

write(R2, ".agents/gate-core.txt", "[core]\n[smoke]\n")
matrix_r2 = {
    "rules": [
        {
            "component": "d",
            "watch_files": ["a/*"],
            "mandatory_regression_tests": [
                {"id": "D-%d" % i, "command": "bash tests/d/test_dyn%d.sh" % i} for i in range(1, 7)
            ] + [
                {"id": "D-TWO", "command": "bash tests/d/test_two.sh"},
                {"id": "D-MISS", "command": "bash tests/d/test_miss.sh"},
                {"id": "D-TMP", "command": "bash tests/d/test_tmp.sh"},
            ],
        }
    ]
}
write(R2, ".agents/regression_matrix.active.json", json.dumps(matrix_r2, indent=2) + "\n")
git(R2, "add", "-A")
git(R2, "commit", "-qm", "base-r2")

write(R2, "b/AGENTS.md", "# b changed\n")
d3 = sg.decide(R2, "HEAD")
tset3 = set(d3["tests"])
for i in range(1, 7):
    tname = "tests/d/test_dyn%d.sh" % i
    chk(tname in tset3, "3.%d. động: sửa b/AGENTS.md vẫn chọn %s (không nhận nhầm sub/AGENTS.md là tĩnh)" % (i, tname), d3["tests"])
chk("tests/d/test_miss.sh" in tset3,
    "3.7. AG2-P0(iii): test_miss.sh có c/AGENTS.md khớp 0 file ⇒ giữ mọi cạnh cũ (chọn khi sửa b/AGENTS.md)", d3["tests"])

git(R2, "checkout", "-q", "--", ".")
write(R2, ".claude/settings.json", '{"a": 9}\n')
d_two_a = sg.decide(R2, "HEAD")
git(R2, "checkout", "-q", "--", ".")
write(R2, "kit/.claude/settings.json", '{"b": 9}\n')
d_two_b = sg.decide(R2, "HEAD")
chk("tests/d/test_two.sh" in d_two_a["tests"] and "tests/d/test_two.sh" in d_two_b["tests"],
    "3.8. P1-AG2(iii): hậu tố .claude/settings.json khớp 2 file ⇒ giữ cả hai (không tie-break)",
    (d_two_a["tests"], d_two_b["tests"]))

git(R2, "checkout", "-q", "--", ".")
write(R2, "subB/settings.json", '{"sb": 9}\n')
d_tmp_b = sg.decide(R2, "HEAD")
chk("tests/d/test_tmp.sh" in d_tmp_b["tests"],
    "3.9. AG3-P1-2: S_base chứa subB/settings.json.tmp (basename != settings.json) ⇒ fail-closed, vẫn chọn test_tmp.sh",
    d_tmp_b["tests"])


# --- Ca 6: explain trên repo thật chọn test_scoped_gate_path_data.sh ---
exp = sg.explain(REPO_ROOT, "universal-agent-devkit/bin/scoped_gate.py")
chk("universal-agent-devkit/tests/gates/test_scoped_gate_path_data.sh" in exp.get("tests", []),
    "6. explain universal-agent-devkit/bin/scoped_gate.py chọn test_scoped_gate_path_data.sh", exp.get("tests", [])[:10])

print("---")
print("FAIL: %d" % fails if fails else "PASS")
sys.exit(1 if fails else 0)
PY
