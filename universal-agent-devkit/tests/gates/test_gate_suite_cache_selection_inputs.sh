#!/usr/bin/env bash
# Test hồi quy #851 (F1): suite run_impacted.sh có dấu `devkit-selection-inputs:` (runner thật của DevKit) được khoá CHÍNH XÁC theo input của
# tập test chọn (đồ thị tham chiếu của bin/scoped_gate.py: test được chọn, file chúng đọc/nhắc tên, import bắc cầu, file dữ liệu test nhắc,
# runner, impact_map.txt, danger list), không theo nội dung cả cây. Merge gate (lượt --scoped) trên H+main dùng lại shard khi main chỉ đổi file
# ngoài các input đó; đổi một input (hay tập chọn đổi) thì chạy lại.
#   U. SuiteCache.keys() trên repo nháp (kit nhỏ, run_impacted.sh THẬT): HIT / MISS hai chiều theo từng loại input; runner không dấu ⇒ như cũ.
#   E. gate thật `--run-tests --scoped --diff main`: lane PASS shard; main thêm commit chạm bin/other.py ⇒ merge H+main không chạy lại shard;
#      main chạm bin/lib_c.py (lib_a.py import) ⇒ chạy lại.
# Trước #851: lượt scoped không khoá suite run_impacted.sh và khoá của nó là khoá cả cây ⇒ U1–U3 và E1 ĐỎ. Python stdlib, bash 3.2.
# #994 (fail-closed, 05/11): khoá chính xác theo tập chọn bị TẮT (đồ thị tĩnh không thấy file test liệt kê lúc chạy ⇒ PASS sai) — khoá
# chính xác = khoá cả cây. U1–U3, U15, U16, U18 nay khẳng định MISS (file không liên quan đổi vẫn đổi khoá) và E1 khẳng định shard CHẠY LẠI;
# các ca MISS khác giữ nguyên. Bật lại #851 (khi có vết input lúc chạy) thì đảo lại 7 ca này.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SUITE_CACHE DEVKIT_SENTINEL_MAX_S CI FLAKY_RETRY \
      DEVKIT_GATE_PARALLEL DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE DEVKIT_IMPACTED_DIRS DEVKIT_SCOPED_TESTS \
      DEVKIT_TEST_JOBS DEVKIT_SLOT_PRIORITY GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK DEVKIT_PER_TEST_CACHE \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1 DEVKIT_SENTINEL_MAX_S=999999999   # khoá slot riêng, không đụng gate thật
mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n()    { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }
SHARD='DEVKIT_IMPACTED_DIRS=gates bash universal-agent-devkit/tests/run_impacted.sh'

# repo <dir> <tag>: kit nhỏ với run_impacted.sh THẬT; test_a nguồn helper + chạy "$DK/bin/lib_a.py" (lib_a import lib_c), test_b đọc file
# dữ liệu, test_z không được chọn; bin/other.py không test nào nhắc; ma trận một shard (watch_files cả kit như ma trận workbench).
repo() {
  local r="$1" k="$1/universal-agent-devkit"
  mkdir -p "$k/tests/gates" "$k/tests/verification" "$k/tests/lib" "$k/bin" "$k/fixtures" "$r/docs"
  git -C "$r" init -q -b main . && git -C "$r" config user.email t@t && git -C "$r" config user.name t
  cp "$DEVKIT_DIR/tests/run_impacted.sh" "$k/tests/run_impacted.sh"; echo '# trống' > "$k/tests/impact_map.txt"
  echo 'true' > "$k/tests/verification/test_repo_consistency.sh"
  printf 'h() { :; }\n' > "$k/tests/lib/helper.sh"
  printf 'DK="$(cd "$(dirname "$0")/../.." && pwd)"\n. "$DK/tests/lib/helper.sh"\necho a >> %s/count.%s\npython3 "$DK/bin/lib_a.py"\n' \
    "$TMP" "$2" > "$k/tests/gates/test_a.sh"
  printf 'DK="$(cd "$(dirname "$0")/../.." && pwd)"\ngrep -q x "$DK/fixtures/data_b.json"\n' > "$k/tests/gates/test_b.sh"
  printf 'true\n' > "$k/tests/gates/test_z.sh"
  printf 'import os, sys\nsys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))\nimport lib_c\n' > "$k/bin/lib_a.py"
  echo 'C = 1' > "$k/bin/lib_c.py"; echo 'O = 1' > "$k/bin/other.py"; echo '{"x": 1}' > "$k/fixtures/data_b.json"
  echo 'ghi chú' > "$r/docs/note.md"; printf '.claude/\n' > "$r/.gitignore"
  python3 - "$r/matrix.json" "$SHARD" <<'PY'
import json, sys
json.dump({"project": "t", "rules": [{"component": "K", "watch_files": ["universal-agent-devkit/*"],
           "mandatory_regression_tests": [{"id": "REG-SHARD", "name": "shard", "command": sys.argv[2]}]}]}, open(sys.argv[1], "w"))
PY
  git -C "$r" add -A && git -C "$r" commit -qm init
}

# ── U. SuiteCache.keys(): khoá chính xác theo input của tập chọn ─────────────────────────────────────────────────────────────────
U="$TMP/u"; repo "$U" U
OUT_U="$(python3 - "$DEVKIT_DIR/bin" "$U" "$SHARD" <<'PY' 2>&1
import json, os, subprocess, sys
bindir, repo, shard = sys.argv[1:]
sys.path.insert(0, bindir)
import suite_cache as m   # bản của checkout đang kiểm (INSTINCT-057)
SEL = "tests/gates/test_a.sh\ntests/gates/test_b.sh"
RULES = json.load(open(os.path.join(repo, "matrix.json")))["rules"]
K = "universal-agent-devkit/"

def keys(sel=SEL, cmd=shard, learned=None):
    os.environ["DEVKIT_SCOPED_TESTS"] = sel
    sc = m.SuiteCache(repo, RULES, os.path.join(repo, "matrix.json"), {}, "local", 1, {"DEVKIT_SCOPED_TESTS": sel}, learned=learned or {})
    return sc.keys({"id": "REG-SHARD", "command": cmd}), sc.selections.get(("REG-SHARD", cmd))

def write(rel, text):
    with open(os.path.join(repo, rel), "a", encoding="utf-8") as f:
        f.write(text)

def reset():
    subprocess.run(["git", "-C", repo, "checkout", "-q", "--", "."], check=True)
    subprocess.run(["git", "-C", repo, "clean", "-qfd", "-e", ".claude"], check=True)

(k0, t0), sel0 = keys()
print("sel", " ".join(sel0 or []))
cases = [  # (nhãn, file đổi, mong HIT?)
    ("U1 bin/other.py (không test nào đọc) — #994 khoá cả cây ⇒ MISS", K + "bin/other.py", False),
    ("U2 test không được chọn (test_z.sh) — #994 khoá cả cây ⇒ MISS", K + "tests/gates/test_z.sh", False),
    ("U3 file ngoài kit (docs/note.md) — #994 khoá cả cây ⇒ MISS", "docs/note.md", False),
    ("U4 test được chọn (test_a.sh)", K + "tests/gates/test_a.sh", False),
    ("U5 file test đọc qua \"$DK/bin/lib_a.py\"", K + "bin/lib_a.py", False),
    ("U6 file lib_a.py import (lib_c.py)", K + "bin/lib_c.py", False),
    ("U7 file dữ liệu test nhắc (data_b.json)", K + "fixtures/data_b.json", False),
    ("U8 runner run_impacted.sh", K + "tests/run_impacted.sh", False),
    ("U9 impact_map.txt", K + "tests/impact_map.txt", False),
    ("U10 helper tests/lib (danger)", K + "tests/lib/helper.sh", False),
    ("U11 danger list (pyproject.toml mới ở gốc)", "pyproject.toml", False),
]
for label, rel, want_hit in cases:
    write(rel, "\n# đổi\n")
    (k1, t1), _ = keys()
    reset()
    hit = bool(k0) and k1 == k0
    print(("OK " if hit == want_hit and t1 != t0 else "BAD ") + label + f": HIT={hit} (mong {want_hit}), khoá cả cây đổi={t1 != t0}")
(k2, _), sel2 = keys(SEL + "\ntests/gates/test_z.sh")
print(("OK " if k2 != k0 and sel2 != sel0 else "BAD ") + f"U12 tập chọn đổi (thêm test_z): MISS={k2 != k0}")
# runner không có dấu devkit-selection-inputs (run_impacted.sh trùng tên của dự án khác): như trước #851 — khoá chính xác = khoá cả cây
p = os.path.join(repo, K + "tests/run_impacted.sh")
src = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write("\n".join(l for l in src.split("\n") if "devkit-selection-inputs:" not in l))
(k3, t3), _ = keys()
reset()
print(("OK " if k3 and k3 == t3 else "BAD ") + f"U13 runner không dấu: khoá chính xác = khoá cả cây ({k3 == t3})")
# input học được (learned_inputs.json, P3) vẫn vào khoá theo tập chọn: bin/other.py học được ⇒ đổi nó là MISS
LEARN = {"REG-SHARD": [K + "bin/other.py"]}
(k4, _), _ = keys(learned=LEARN)
write(K + "bin/other.py", "\n# đổi\n")
(k5, _), _ = keys(learned=LEARN)
reset()
print(("OK " if k4 and k5 != k4 else "BAD ") + f"U14 input học được (bin/other.py) đổi: MISS={k5 != k4}")

def pair(label, setup, change, want_hit, sel=SEL, cmd=shard, sel2=None):
    """setup() dựng trạng thái A (cùng có ở cả hai lượt), change() đổi một thứ ⇒ so khoá chính xác A / B."""
    setup()
    (ka, _), _ = keys(sel, cmd)
    change()
    (kb, _), _ = keys(sel2 or sel, cmd)
    reset()
    hit = bool(ka) and ka == kb
    print(("OK " if hit == want_hit else "BAD ") + label + f": HIT={hit} (mong {want_hit})")

OUTK = os.path.join(os.path.dirname(repo), "outside-kit")   # checkout ngoài cây (như .agents/devkit của worktree thật)
os.makedirs(os.path.join(OUTK, "bin"), exist_ok=True)
open(os.path.join(OUTK, "bin/x.py"), "w").write("X = 1\n")
def link_devkit():
    os.makedirs(os.path.join(repo, ".agents"), exist_ok=True)
    os.symlink(OUTK, os.path.join(repo, ".agents/devkit"))
def outside_change():
    open(os.path.join(OUTK, "bin/x.py"), "a").write("# đổi\n")
# B1: công cụ / đích ngoài cây của khoá tập chọn chỉ lấy từ file của tập chọn, không từ watch_files `kit/*`
pair("U15 bin/other.py (ngoài tập chọn) nhắc công cụ cargo — #994 khoá cả cây ⇒ MISS", lambda: None,
     lambda: write(K + "bin/other.py", "\n# cargo build\n"), False)
pair("U16 đích ngoài cây chỉ bin/other.py nhắc (.agents/devkit/bin/x.py) đổi — #994 khoá cả cây ⇒ MISS",
     lambda: (link_devkit(), write(K + "bin/other.py", "\n# .agents/devkit/bin/x.py\n")), outside_change, False)
pair("U17 đích ngoài cây lib_a.py (tập chọn) nhắc đổi",
     lambda: (link_devkit(), write(K + "bin/lib_a.py", "\n# .agents/devkit/bin/x.py\n")), outside_change, False)
# M1: DEVKIT_SCOPED_TESTS gộp mọi shard — đổi phần của shard khác (tập chọn shard này giữ nguyên) không đổi khoá
pair("U18 DEVKIT_SCOPED_TESTS thêm test shard khác (tập chọn giữ nguyên) — #994 khoá cả cây ⇒ MISS", lambda: None, lambda: None, False,
     sel2=SEL + "\ntests/verification/test_repo_consistency.sh")
# B2: test runner khai ở `devkit-selection-tree:` (quét cả kit) trong tập chọn ⇒ shard chỉ khoá cả cây
REST = "DEVKIT_IMPACTED_DIRS=!gates bash universal-agent-devkit/tests/run_impacted.sh"
(k6, t6), sel6 = keys(cmd=REST)
print(("OK " if sel6 and "tests/verification/test_repo_consistency.sh" in sel6 and k6 == t6 else "BAD ")
      + f"U19 shard có test_repo_consistency.sh: khoá chính xác = khoá cả cây ({k6 == t6}, sel={sel6})")
# M2: symlink kit (list_files của đồ thị bỏ link) mà file tập chọn nhắc tên, và đích của nó; file dữ liệu code của tập chọn nhắc
def link_run():
    os.symlink("bin/other.py", os.path.join(repo, K + "run_x.py"))
    write(K + "tests/gates/test_a.sh", 'python3 "$DK/run_x.py"\n')
def retarget():
    os.remove(os.path.join(repo, K + "run_x.py"))
    os.symlink("bin/lib_c.py", os.path.join(repo, K + "run_x.py"))
pair("U20 symlink kit test_a nhắc (run_x.py) đổi đích", link_run, retarget, False)
pair("U21 đích của symlink kit test_a nhắc (bin/other.py) đổi", link_run, lambda: write(K + "bin/other.py", "\n# đổi\n"), False)
def data_a():
    write(K + "bin/lib_a.py", '\nDATA = os.path.join(os.path.dirname(__file__), "../fixtures/data_a.json")\n')
    write(K + "fixtures/data_a.json", '{"a": 1}\n')
pair("U22 file dữ liệu chỉ lib_a.py (code tập chọn) nhắc đổi", data_a, lambda: write(K + "fixtures/data_a.json", " "), False)
# B1 chiều ngược: công cụ test của tập chọn nhắc (python3 trong test_a.sh) vẫn vào khoá — phiên bản python đổi ⇒ MISS
pair("U23 phiên bản python (test_a.sh nhắc python3) đổi", lambda: m._TOOL_VERSIONS.__setitem__("python", "Python 3.0.0"),
     lambda: m._TOOL_VERSIONS.__setitem__("python", "Python 9.9.9"), False)
# P1 review 02/11: file lõi chỉ được VÀO (_reach không mở tiếp, chống nổ tập chọn) — script mà hub lõi tập chạm tới chạy theo tên
# (install.sh → adapters/setup_claude.sh) vẫn là input của khoá; chuỗi hub → script → hub2 → script2 cũng vậy (điểm bất động)
def hub(*names):
    os.makedirs(os.path.join(repo, ".agents"), exist_ok=True)
    with open(os.path.join(repo, ".agents/gate-core.txt"), "w", encoding="utf-8") as f:
        f.write("[core]\n" + "".join(K + "bin/" + n + "\n" for n in names))
    write(K + "bin/hub.sh", 'DK="$(cd "$(dirname "$0")/.." && pwd)"\nbash "$DK/bin/sub.sh"\n')
    write(K + "bin/sub.sh", 'DK="$(cd "$(dirname "$0")/.." && pwd)"\nbash "$DK/bin/hub2.sh"\n')
    write(K + "bin/hub2.sh", 'DK="$(cd "$(dirname "$0")/.." && pwd)"\nbash "$DK/bin/sub2.sh"\n')
    write(K + "bin/sub2.sh", "true\n")
    write(K + "tests/gates/test_a.sh", 'bash "$DK/bin/hub.sh"\n')
pair("U24 script hub lõi (hub.sh) tập chạm tới chạy theo tên (sub.sh) đổi", lambda: hub("hub.sh", "hub2.sh"),
     lambda: write(K + "bin/sub.sh", "\n# đổi\n"), False)
pair("U25 chuỗi hub.sh → sub.sh → hub2.sh (lõi) → sub2.sh: sub2.sh đổi", lambda: hub("hub.sh", "hub2.sh"),
     lambda: write(K + "bin/sub2.sh", "\n# đổi\n"), False)
# OCR review 02/11: `--all` chạy mọi test nhưng `--list --all` của runner in tập chọn scoped ⇒ lệnh `--all` không có khoá theo tập chọn
(k7, t7), _ = keys(cmd=shard + " --all")
print(("OK " if k7 and k7 == t7 else "BAD ") + f"U26 lệnh runner --all: khoá chính xác = khoá cả cây ({k7 == t7})")
PY
)"
printf '%s\n' "$OUT_U" | grep -E '^(sel|OK|BAD)' | sed 's/^/    /'
if ! printf '%s\n' "$OUT_U" | grep -q '^sel tests/gates/test_a.sh tests/gates/test_b.sh$'; then
  fail "U0. tập chọn của fixture không phải {test_a, test_b}"; printf '%s\n' "$OUT_U" | tail -5
fi
for c in U1 U2 U3 U4 U5 U6 U7 U8 U9 U10 U11 U12 U13 U14 U15 U16 U17 U18 U19 U20 U21 U22 U23 U24 U25 U26; do
  line="$(printf '%s\n' "$OUT_U" | grep -E "^(OK|BAD) $c " | head -1)"
  case "$line" in OK*) ok "${line#OK }" ;; BAD*) fail "${line#BAD }" ;; *) fail "$c: không có kết quả"; printf '%s\n' "$OUT_U" | tail -3 ;; esac
done

# ── E. gate thật, lượt --scoped: lane rồi merge H+main ────────────────────────────────────────────────────────────────────────
E="$TMP/e"; repo "$E" E
git -C "$E" worktree add -q -b feat "$TMP/lane" main || { echo "✖ setup: worktree lane"; exit 1; }
echo 'A = 2' >> "$TMP/lane/universal-agent-devkit/bin/lib_a.py"; git -C "$TMP/lane" commit -qam "lane: lib_a"
# merge <dir>: worktree tách rời ở main hiện tại, gộp feat (cây merge gate chạy: H + main)
merge() {
  git -C "$E" worktree add -q --detach "$1" main && git -C "$1" merge -q --no-edit feat >/dev/null || { echo "✖ setup: merge $1"; exit 1; }
}
gate() { ( cd "$1" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --matrix "$1/matrix.json" --run-tests --scoped \
  --diff main --no-checklist >"$TMP/out" 2>&1 ); }
for d in lane; do mkdir -p "$TMP/$d/.claude/audit-gate"; : > "$TMP/$d/.claude/audit-gate/test_run.lock"; done   # worktree đã từng chạy gate

gate "$TMP/lane"; r0=$?; c0=$(n E)
if [ "$r0" = 0 ] && [ "$c0" = 1 ]; then ok "E0. lane --scoped: shard chạy, PASS (test_a chạy $c0 lần)"
else fail "E0. lane exit $r0 (mong 0), test_a chạy $c0 lần (mong 1)"; grep -E "REG-SHARD|scoped|suite_cache" "$TMP/out" | tail -5; fi

echo 'O = 2' >> "$E/universal-agent-devkit/bin/other.py"; git -C "$E" commit -qam "main: other.py"
merge "$TMP/m1"; mkdir -p "$TMP/m1/.claude/audit-gate"; : > "$TMP/m1/.claude/audit-gate/test_run.lock"
gate "$TMP/m1"; r1=$?; c1=$(n E)
if [ "$r1" = 0 ] && [ "$c1" -gt "$c0" ]; then ok "E1. merge H+main (main đổi bin/other.py): #994 khoá cả cây ⇒ shard chạy lại ($c0 → $c1), PASS"
else fail "E1. merge exit $r1 (mong 0), test_a chạy $c0 → $c1 (mong tăng: #994 không dùng lại theo tập chọn)"; grep -E "REG-SHARD|scoped|suite_cache" "$TMP/out" | tail -5; fi

echo 'C = 2' >> "$E/universal-agent-devkit/bin/lib_c.py"; git -C "$E" commit -qam "main: lib_c.py"
merge "$TMP/m2"; mkdir -p "$TMP/m2/.claude/audit-gate"; : > "$TMP/m2/.claude/audit-gate/test_run.lock"
gate "$TMP/m2"; r2=$?; c2=$(n E)
if [ "$r2" = 0 ] && [ "$c2" -gt "$c1" ]; then ok "E2. merge H+main (main đổi bin/lib_c.py mà lib_a.py import): shard chạy lại ($c1 → $c2)"
else fail "E2. merge exit $r2 (mong 0), test_a chạy $c1 → $c2 (mong tăng)"; grep -E "REG-SHARD|scoped|suite_cache" "$TMP/out" | tail -5; fi

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_suite_cache_selection_inputs: all passed" || { echo "❌ test_gate_suite_cache_selection_inputs: $FAILS failed"; exit 1; }
