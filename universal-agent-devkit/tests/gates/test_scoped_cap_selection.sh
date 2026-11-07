#!/usr/bin/env bash
# Test hồi quy (gate speed v17, mục 5b): cap_selection chỉ giữ test kit trực tiếp, phần còn lại vào deferred_to_heavy và không chạy.
#   a  hạng: tên khớp đứng đầu (test_postfix_gate.sh cho post-fix-gate.py), rồi chạy file (kể cả qua VAR=…file), rồi impact_map, rồi cạnh khác; chú thích không tính
#   b  mỗi file code đổi giữ đúng một test hạng đầu, kit hay không; tài liệu không giữ
#   c  test đổi trong diff và suite nêu tên nó ở lại; [core-smoke] ở lại; [smoke] rời
#   d  suite không kit ở lại; suite kit có watch khớp file ngoài kit, configs, settings ở lại; suite kit khác đi, vào deferred
#   e  file code không test, không suite phủ ⇒ [core-smoke]; có suite ở lại phủ ⇒ không
#   f  thời lượng: chỉ file đã track, không đọc file đo; không có trong file đứng sau; rồi theo đường dẫn
#   g  test không suite nào chạy được không được chọn làm hạng đầu khi còn test khác
#   h  runner kit chỉ ở lại khi còn test; shard của ma trận cũ không bị bỏ
#   i  by_file của decide: file còn trên đĩa và file bị xoá mà test nêu tên
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
OUT="$(python3 - "$DEVKIT_DIR/bin" "$TMP" <<'PY' 2>&1
import json, os, subprocess, sys
sys.path.insert(0, sys.argv[1]); import scoped_gate as g
P = sys.argv[2]
K = "universal-agent-devkit/"
def w(path, body=""):
    full = os.path.join(P, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    open(full, "w").write(body)
def run(decision, selected, rules, changed, added=(), **kw):
    calls = []
    def rebuild(d, sel):
        calls.append(list(d.get("tests") or []))
        kit = [t[len(K):] for t in list(d.get("tests") or []) + list(d.get("smoke") or []) if t.startswith(K)]
        return list(added), kit
    return g.cap_selection(P, decision, selected, list(added), rules, changed, rebuild, **kw)
def show(label, ok, extra=""):
    print(("✔ " if ok else "✖ ") + label + ("" if ok else " :: " + str(extra)))

# a. hạng
w(K + "tests/gates/test_postfix_gate.sh", "echo\n")
w(K + "tests/gates/test_postfix_gate_more.sh", "echo\n")
w(K + "tests/gates/test_runs_it.sh", 'bash "$K/bin/post-fix-gate.py"\n')
w(K + "tests/gates/test_var.sh", 'GATE="$K/bin/post-fix-gate.py"\nbash "$GATE" --x\n')
w(K + "tests/gates/test_comment.sh", '# bash post-fix-gate.py\nX=1\n')
w(K + "tests/gates/test_mapped.sh", "echo\n")
w(K + "tests/impact_map.txt", "bin/post-fix-gate.py tests/gates/test_mapped.sh\n")
f = K + "bin/post-fix-gate.py"
m = {}
r = lambda t: g._test_rank(P, K + "tests/gates/" + t, f, m)
show("a. tên trùng hẳn đứng đầu", r("test_postfix_gate.sh") == (1, 0), r("test_postfix_gate.sh"))
show("a. tên khớp một phần sau đó", r("test_postfix_gate_more.sh") == (1, 1), r("test_postfix_gate_more.sh"))
show("a. chạy file: hạng 2", r("test_runs_it.sh")[0] == 2, r("test_runs_it.sh"))
show("a. VAR=…file dùng làm lệnh: hạng 2", r("test_var.sh")[0] == 2, r("test_var.sh"))
show("a. impact_map: hạng 3", r("test_mapped.sh")[0] == 3, r("test_mapped.sh"))
show("a. chỉ nhắc trong chú thích: hạng 4", r("test_comment.sh")[0] == 4, r("test_comment.sh"))
show("a. super-board- bỏ khi so tên", g._test_rank(P, "tests/super-board/test_merge_gate.sh", ".claude/bin/super-board-merge-gate.sh", {}) == (1, 0))

# b. mỗi file code một test; tài liệu không giữ
A, B = K + "tests/gates/test_a.sh", K + "tests/gates/test_b.sh"
AX, BX = K + "tests/gates/test_a_extra.sh", K + "tests/gates/test_other.sh"
for t in (A, B, AX, BX):
    w(t, "echo\n")
D = {"tests": sorted([A, B, AX, BX, "mcp/tests/test_m.sh"]), "smoke": [K + "tests/gates/test_smoke.sh"], "core_smoke": [],
     "by_file": {K + "bin/a.py": [A, AX, BX], "lib/b.js": [B, BX, "mcp/tests/test_m.sh"], "docs/x.md": [BX]}}
o = run(D, [], [], [K + "bin/a.py", "lib/b.js", "docs/x.md"])
show("b. giữ test hạng đầu của từng file code, cả file ngoài kit", set(D["tests"]) == {A, B, "mcp/tests/test_m.sh"}, D["tests"])
show("b. phần còn lại vào deferred", o["deferred_to_heavy"]["tests"] == sorted([AX, BX]), o["deferred_to_heavy"])
show("c. [smoke] rời", D["smoke"] == [], D["smoke"])

# c. test đổi trong diff, [core-smoke]
T, C = K + "tests/gates/test_changed.sh", K + "tests/gates/test_cs.sh"
D = {"tests": [T, AX, C], "smoke": [C], "core_smoke": [C], "by_file": {T: [T, AX]}}
sel = [{"id": "S-T", "command": "bash " + T}, {"id": "S-AX", "command": "bash " + AX}]
o = run(D, sel, [], [T])
show("c. test đổi trong diff ở lại", T in D["tests"], D["tests"])
show("c. [core-smoke] ở lại", C in D["tests"] and D["smoke"] == [C], D)
show("c. suite nêu test đổi ở lại, suite kit khác đi", [t["id"] for t in o["selected"]] == ["S-T"] and o["deferred_to_heavy"]["suites"] == ["S-AX"], o)

# d. luật giữ suite
rules = [{"watch_files": [".gitignore", K + "x"], "mandatory_regression_tests": [{"id": "S-IGN"}]},
         {"watch_files": [".claude/super-board/configs/*.json"], "mandatory_regression_tests": [{"id": "S-CFG"}]},
         {"watch_files": [".claude/settings*.json"], "mandatory_regression_tests": [{"id": "S-SET"}]},
         {"watch_files": [".claude/bin/x.sh"], "mandatory_regression_tests": [{"id": "S-BIN"}]}]
Z = "tests/super-board/test_z.sh"
sel = [{"id": i, "command": "bash " + Z} for i in ("S-IGN", "S-CFG", "S-SET", "S-BIN")] + [{"id": "S-APP", "command": "cd mcp && npm test"}]
for name, changed, want in (("file ngoài kit", ".gitignore", "S-IGN"), ("configs", ".claude/super-board/configs/a.json", "S-CFG"), ("settings", ".claude/settings.json", "S-SET")):
    o = run({"tests": [], "smoke": [], "core_smoke": [], "by_file": {}}, sel, rules, [changed, ".claude/bin/x.sh"])
    ids = [t["id"] for t in o["selected"]]
    show("d. suite kit có watch khớp %s ở lại" % name, want in ids and "S-BIN" not in ids, ids)
    show("d. suite không kit không bị cắt (%s)" % name, "S-APP" in ids, ids)
    show("d. suite kit khác vào deferred (%s)" % name, "S-BIN" in o["deferred_to_heavy"]["suites"], o["deferred_to_heavy"])

# e. file code không test
w(".agents/gate-core.txt", "[core]\n\n[smoke]\n" + K + "tests/gates/test_smoke.sh\n\n[core-smoke]\n" + C + "\n")
w(K + "tests/gates/test_smoke.sh", "echo\n"); w(C, "echo\n")
D = {"tests": [], "smoke": [], "core_smoke": [], "by_file": {}}
o = run(D, [], [], [K + "bin/lonely.py"])
show("e. không test, không suite phủ ⇒ [core-smoke], không kèm [smoke]", D["core_smoke"] == [C] and D["smoke"] == [C], D)
D = {"tests": [], "smoke": [], "core_smoke": [], "by_file": {}}
o = run(D, [{"id": "S-APP", "command": "cd app && make"}], [{"watch_files": ["app/*"], "mandatory_regression_tests": [{"id": "S-APP"}]}], ["app/x.py"])
show("e. có suite ở lại phủ ⇒ không [core-smoke]", D["core_smoke"] == [], D)
D = {"tests": [], "smoke": [], "core_smoke": [], "by_file": {}}
o = run(D, [], [], ["docs/x.md"])
show("e. tài liệu không kéo [core-smoke]", D["core_smoke"] == [], D)

# f. thời lượng
L1, L2, UN = K + "tests/gates/test_q1.sh", K + "tests/gates/test_q2.sh", K + "tests/gates/test_q0.sh"
for t in (L1, L2, UN):
    w(t, "echo\n")
w(K + "tests/lib/test_durations.txt", "9 tests/gates/test_q1.sh\n3 tests/gates/test_q2.sh\n")
D = {"tests": [L1, L2, UN], "smoke": [], "core_smoke": [], "by_file": {K + "bin/nomatch.py": [L1, L2, UN]}}
run(D, [], [], [K + "bin/nomatch.py"])
show("f. cùng hạng: ngắn nhất trong file đã track", D["tests"] == [L2], D["tests"])
D = {"tests": [L1, UN], "smoke": [], "core_smoke": [], "by_file": {K + "bin/nomatch.py": [UN, L1]}}
run(D, [], [], [K + "bin/nomatch.py"])
show("f. không có trong file đứng sau", D["tests"] == [L1], D["tests"])
sg_src = open(os.path.join(sys.argv[1], "scoped_gate.py"), encoding="utf-8").read()
body = sg_src[sg_src.index("def _tracked_durations"):sg_src.index("def _test_rank")]
show("f. không đọc file đo", "open(os.path.join(project, kit, \"tests/lib/test_durations.txt\")" in body and "git-common-dir" not in body.replace("git common dir", "") and "measured.txt" not in body)

# g. không chạy được
PY1, SH1 = K + "tests/gates/test_u.py", K + "tests/gates/test_v.sh"
w(PY1, "print(1)\n"); w(SH1, "echo\n")
D = {"tests": [PY1, SH1], "smoke": [], "core_smoke": [], "by_file": {K + "bin/u.py": [PY1, SH1]}}
run(D, [], [], [K + "bin/u.py"], unrunnable=[PY1])
show("g. bỏ qua test không chạy được khi còn test khác", D["tests"] == [SH1], D["tests"])

# h. runner
RUN = "bash " + K + "tests/run_impacted.sh"
D = {"tests": [], "smoke": [], "core_smoke": [C], "by_file": {}}
o = run(dict(D, core_smoke=[], tests=[]), [{"id": "KIT", "command": RUN}], [], ["docs/x.md"])
show("h. hàng KIT đi khi hết test", o["selected"] == [], o["selected"])
o = run(dict(D, core_smoke=[], tests=[A], by_file={K + "bin/a.py": [A]}), [{"id": "KIT", "command": RUN}], [], [K + "bin/a.py"])
show("h. hàng KIT ở lại khi còn test", [t["id"] for t in o["selected"]] == ["KIT"], o["selected"])
SH = "DEVKIT_IMPACTED_DIRS=gates " + RUN
o = run({"tests": [], "smoke": [], "core_smoke": [], "by_file": {}}, [{"id": "G", "command": SH}], [], ["docs/x.md"])
show("h. shard của ma trận cũ không bị bỏ", [t["id"] for t in o["selected"]] == ["G"], o["selected"])

# i. decide
R = os.path.join(P, "repo")
os.makedirs(R + "/tests/gates"); os.makedirs(R + "/src")
open(R + "/src/mod.py", "w").write("x = 1\n"); open(R + "/src/gone.py", "w").write("y = 1\n")
open(R + "/tests/gates/test_mod.sh", "w").write("python3 src/mod.py\n")
open(R + "/tests/gates/test_gone.sh", "w").write("python3 src/gone.py\n")
for c in (["init", "-q", "-b", "main", "."], ["config", "user.email", "t@t"], ["config", "user.name", "t"], ["add", "-A"], ["commit", "-qm", "i"]):
    subprocess.run(["git", "-C", R] + c, check=True)
os.remove(R + "/src/gone.py"); open(R + "/src/mod.py", "a").write("z = 2\n")
d = g.decide(R, "HEAD", changed=["src/mod.py", "src/gone.py"], matrix_rules=[])
show("i. by_file có file còn trên đĩa", "tests/gates/test_mod.sh" in d["by_file"].get("src/mod.py", []), d["by_file"])
show("i. by_file có file bị xoá mà test nêu tên", "tests/gates/test_gone.sh" in d["by_file"].get("src/gone.py", []), d["by_file"])
PY
)"
echo "$OUT"
case "$OUT" in *"✖"*|*Traceback*) echo "failures"; exit 1 ;; esac
case "$OUT" in *"✔"*) echo PASS; exit 0 ;; esac
exit 1
