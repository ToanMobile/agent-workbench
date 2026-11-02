#!/usr/bin/env bash
# Test hồi quy (#849): bin/lane_lock.py — gate scoped NHỎ không chờ ngưỡng tải, việc nặng giữ luật cũ (tải giả DEVKIT_SLOT_LOAD_FILE):
#   0. lane_lock.py chạy là bản trong CHÍNH checkout chứa test này (worktree), không phải bản của main checkout (INSTINCT-057)
#   1. tải 40: post-fix-gate --scoped 3 test được nhận ngay (cả dạng `env K=V python3 …`)   2. tải 40: gate --scoped 40 test vẫn chờ
#   3. tải 40: --scoped --full vẫn chờ          4. tải 40: lệnh không phải gate vẫn chờ
#   5. tải 40: hai gate nhỏ giữ đủ 2 slot ⇒ gate nhỏ thứ ba chờ (không bao giờ 3 người giữ)
#   6. tải 15: việc nặng giữ slot 1 ⇒ gate nhỏ lấy slot 2 chạy song song   7. tải 15: gate nhỏ đang giữ ⇒ việc nặng chờ nó xong
#   8. bộ thăm dò lỗi / quá giờ ⇒ coi là nặng (chờ)   9. tải thấp: không gọi bộ thăm dò   10. không file khoá / marker mới
# Fixture: repo git tạm với kit/bin/post-fix-gate.py giả (là chính việc chạy) và kit/bin/scoped_gate.py giả (số test đọc từ file).
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LL_PY="${DEVKIT_DIR}/bin/lane_lock.py"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lanelocklight.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
TMP="$(cd "${TMP}" && pwd -P)"
cleanup() {
  local f
  printf '5\n' > "${TMP}/load" 2>/dev/null
  for f in "${TMP}"/*.pid; do [ -f "${f}" ] && kill "$(cat "${f}")" 2>/dev/null; done
  rm -rf "${TMP}"
}
trap cleanup EXIT
for v in $(env | sed -n 's/^\(LANE_LOCK_[A-Z_]*\)=.*/\1/p'); do unset "${v}"; done   # núm của người gọi không lọt vào ca
unset DEVKIT_SLOT_LOAD_MAX SB_HEAVY_SLOT_HELD CLAUDE_PROJECT_DIR TARGET_DIR
export LANE_LOCK_DIR="${TMP}/locks" SB_HEAVY_SLOT_DIR="${TMP}/heavy" LANE_LOCK_POLL_S=0.1 LANE_LOCK_GRACE_S=0.2 DEVKIT_SLOT_LOAD_FILE="${TMP}/load"
mkdir -p "${SB_HEAVY_SLOT_DIR}"
load() { printf '%s\n' "$1" > "${TMP}/load"; }
now() { python3 -c 'import time; print(repr(time.time()))'; }
lt() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$1" "$2"; }   # $1 < $2
val() { cat "${TMP}/$1" 2>/dev/null || echo 0; }

# 0. đúng bản lane_lock.py: file nằm trong cùng checkout với test, và Python nạp đúng đường dẫn đó (không qua sys.path / main checkout)
top="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
if [ -n "${top}" ]; then top="$(cd "${top}" 2>/dev/null && pwd -P)"; fi
[ -n "${top}" ] || top="/không-có-checkout"   # test ngoài git: không được rơi về cwd
loaded="$(python3 -c 'import importlib.util as u, os, sys
s = u.spec_from_file_location("lane_lock_probe", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
print(os.path.realpath(m.__file__))' "${LL_PY}" 2>/dev/null)"
case "${loaded}" in
  "${top}"/*) ok "0. lane_lock.py của checkout chứa test: ${loaded}" ;;
  *) bad "0. lane_lock.py không thuộc checkout của test" "nạp ${loaded:-?}, checkout ${top:-?}" ;;
esac

# fixture: repo git tạm; post-fix-gate.py giả = việc (ghi giờ bắt đầu/kết thúc theo JOB_P, ngủ JOB_DUR); scoped_gate.py giả
REPO="${TMP}/repo"
mkdir -p "${REPO}/kit/bin" "${REPO}/tests"
cat > "${REPO}/kit/bin/post-fix-gate.py" <<'PY'
import json, os, sys, time
from pathlib import Path
# hàm bộ thăm dò nạp từ gate (như post-fix-gate.py thật); ma trận đọc ở cây làm việc của cwd
def needs_no_test(p): return p.endswith(".md")
def checklist_covers(): return {}
def rule_watch(rule, covers): return list(rule.get("watch_files", []))
def find_matrix_path(_m=None):
    p = Path(os.getcwd()) / ".agents" / "regression_matrix.active.json"
    return p if p.exists() else None
def load_active_matrix(_m=None, _base="HEAD"): return {}, None
if __name__ == "__main__":
    p, dur = os.environ["JOB_P"], float(os.environ.get("JOB_DUR", "0.2"))
    open(p + ".start", "w").write(repr(time.time()))
    time.sleep(dur)
    open(p + ".end", "w").write(repr(time.time()))
PY
cat > "${REPO}/kit/bin/scoped_gate.py" <<'PY'
import fnmatch, os, time
_D = os.path.dirname(os.path.abspath(__file__))
def _mode():
    try:
        return open(os.path.join(_D, "mode")).read().strip()
    except OSError:
        return "ok"
open(os.path.join(_D, "probed"), "a").write("1\n")
def decide(project, base, **_kw):
    m = _mode()
    if m == "raise":
        raise RuntimeError("stub hỏng")
    if m == "sleep":
        time.sleep(30)
    spec = open(os.path.join(_D, "ntests")).read().strip()
    changed = ["src/a.sh"]
    if spec == "diff":   # như decide thật: merge-base(base, HEAD) + cây làm việc; mỗi file src/ đổi = một test
        import subprocess
        git = lambda *a: subprocess.run(["git", "-C", project] + list(a), capture_output=True, text=True).stdout.split()
        mb = git("merge-base", base, "HEAD")
        changed = sorted(f for f in set(git("diff", "--name-only", mb[0]) if mb else []) | set(git("ls-files", "-o", "--exclude-standard"))
                         if f.startswith("src/"))
        n = len(changed)
    else:
        n = int(spec)
    return {"mode": "scoped", "tests": ["tests/test_%d.sh" % i for i in range(n)], "smoke": [], "changed": changed,
            "graph_error": None, "reasons": [], "core_hits": []}
def no_full(res, project):
    return dict(res)
def match_pattern(path, pat):
    return fnmatch.fnmatch(path, pat)
def _load_matrix(project):
    return []
PY
GATE="${REPO}/kit/bin/post-fix-gate.py"
ntests() { printf '%s\n' "$1" > "${REPO}/kit/bin/ntests"; }
stub_mode() { printf '%s\n' "$1" > "${REPO}/kit/bin/mode"; }
git -C "${REPO}" init -q && git -C "${REPO}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init || { echo "✖ git init"; exit 2; }
cat > "${TMP}/job.py" <<'PY'
import os, sys, time
p = os.environ["JOB_P"]
open(p + ".start", "w").write(repr(time.time()))
time.sleep(float(os.environ.get("JOB_DUR", "0.2")))
open(p + ".end", "w").write(repr(time.time()))
PY

# gate <tên> <giây> [cờ gate…]: gate giả dưới lane lock (cwd = repo fixture), nền; heavy <tên> <giây>: lệnh không phải gate
gate() {
  local n="$1" d="$2"; shift 2
  ( cd "${REPO}" && JOB_P="${TMP}/${n}" JOB_DUR="${d}" exec python3 "${LL_PY}" "${n}" -- python3 "${GATE}" "$@" ) > "${TMP}/${n}.log" 2>&1 &
  echo $! > "${TMP}/${n}.pid"
}
heavy() {
  ( cd "${REPO}" && JOB_P="${TMP}/$1" JOB_DUR="$2" exec python3 "${LL_PY}" "$1" python3 "${TMP}/job.py" ) > "${TMP}/$1.log" 2>&1 &
  echo $! > "${TMP}/$1.pid"
}
wait_job() { local p; p="$(cat "${TMP}/$1.pid" 2>/dev/null)"; [ -n "${p}" ] && wait "${p}" 2>/dev/null; echo $? > "${TMP}/$1.rc"; rm -f "${TMP}/$1.pid"; }
started_in() { local i=0 lim; lim="$(python3 -c "print(int(float('$2') * 20))")"   # $1 đã bắt đầu trong $2 giây?
  while [ ! -s "${TMP}/$1.start" ] && [ "${i}" -lt "${lim}" ]; do sleep 0.05; i=$((i + 1)); done; [ -s "${TMP}/$1.start" ]; }
release_all() { load 5; local f n; for f in "${TMP}"/*.pid; do [ -f "${f}" ] || continue; n="$(basename "${f}" .pid)"; wait_job "${n}"; done; }
stub_mode ok

# 1. tải 40: gate --scoped 3 test nhận ngay; dạng `env K=V python3 gate` cũng nhận
load 40; ntests 3
gate L1 0.3 --run-tests --scoped --brief
( cd "${REPO}" && exec python3 "${LL_PY}" L1e -- env JOB_P="${TMP}/L1e" JOB_DUR=0.3 python3 "${GATE}" --run-tests --scoped --brief ) > "${TMP}/L1e.log" 2>&1 &
echo $! > "${TMP}/L1e.pid"
if started_in L1 6 && started_in L1e 6; then ok "1. tải 40: gate scoped 3 test được nhận ngay (cả dạng env K=V)"
else bad "1. tải 40: gate scoped nhỏ vẫn chờ ngưỡng tải" "L1 $(val L1.start) L1e $(val L1e.start); log: $(tr '\n' ' ' < "${TMP}/L1.log" | cut -c1-200)"; fi
release_all
if grep -q 'nhẹ' "${TMP}/L1.log"; then ok "1b. log [lock] ghi gate được xếp nhẹ"
else bad "1b. log không ghi nhẹ" "$(tr '\n' ' ' < "${TMP}/L1.log" | cut -c1-200)"; fi

# 2. tải 40: gate --scoped 40 test (vượt ngưỡng nhẹ) vẫn chờ tải xuống
load 40; ntests 40; gate H2 0.2 --run-tests --scoped --brief
if started_in H2 2.5; then bad "2. tải 40: gate 40 test chạy khi tải còn cao"; else ok "2. tải 40: gate scoped 40 test vẫn chờ"; fi
release_all

# 3. tải 40: --scoped --full không bao giờ nhẹ
load 40; ntests 3; gate H3 0.2 --run-tests --scoped --full --brief
if started_in H3 2.5; then bad "3. tải 40: gate --full chạy khi tải còn cao"; else ok "3. tải 40: gate --full vẫn chờ"; fi
release_all

# 4. tải 40: lệnh không phải gate vẫn chờ
load 40; heavy H4 0.2
if started_in H4 2.5; then bad "4. tải 40: lệnh không phải gate chạy khi tải còn cao"; else ok "4. tải 40: lệnh không phải gate vẫn chờ"; fi
release_all

# 5. tải 40: hai gate nhỏ giữ đủ 2 slot ⇒ gate nhỏ thứ ba chỉ bắt đầu sau khi một gate xong
load 40; ntests 3; gate L5a 2.5 --run-tests --scoped; gate L5b 2.5 --run-tests --scoped
if started_in L5a 6 && started_in L5b 6; then
  gate L5c 0.2 --run-tests --scoped
  started_in L5c 8 >/dev/null
  first_end="$(python3 -c 'import sys; print(min(float(sys.argv[1]), float(sys.argv[2])))' "$(val L5a.end)" "$(val L5b.end)")"
  if [ "$(val L5c.start)" != 0 ] && [ "$(val L5a.end)" != 0 ] && [ "$(val L5b.end)" != 0 ] && ! lt "$(val L5c.start)" "${first_end}"; then
    ok "5. tải 40: gate nhỏ thứ ba chờ slot (không vượt 2 slot)"
  else bad "5. tải 40: gate nhỏ thứ ba chạy khi đủ 2 slot đang giữ" "L5c start $(val L5c.start), slot trống sớm nhất ${first_end}"; fi
else bad "5. tải 40: hai gate nhỏ không được nhận" "L5a $(val L5a.start) L5b $(val L5b.start)"; fi
release_all

# 6. tải 15 (1 slot cho việc nặng): việc nặng giữ slot 1 ⇒ gate nhỏ lấy slot 2, chạy song song
load 15; ntests 3; heavy H6 3; started_in H6 6 >/dev/null; gate L6 0.2 --run-tests --scoped
started_in L6 6 >/dev/null; wait_job H6
if [ "$(val L6.start)" != 0 ] && [ "$(val H6.end)" != 0 ] && lt "$(val L6.start)" "$(val H6.end)"; then ok "6. tải 15: gate nhỏ chạy song song với việc nặng (slot 2)"
else bad "6. tải 15: gate nhỏ chờ việc nặng xong" "H6 end $(val H6.end), L6 start $(val L6.start)"; fi
release_all

# 7. tải 15: gate nhỏ đang giữ slot ⇒ việc nặng chờ nó xong (luật 1 slot của việc nặng không đổi)
load 15; ntests 3; gate L7 2 --run-tests --scoped; started_in L7 6 >/dev/null; heavy H7 0.2
started_in H7 8 >/dev/null
if [ "$(val H7.start)" != 0 ] && [ "$(val L7.end)" != 0 ] && ! lt "$(val H7.start)" "$(val L7.end)"; then ok "7. tải 15: việc nặng chờ gate nhỏ nhả slot"
else bad "7. tải 15: việc nặng chạy chồng gate nhỏ" "L7 $(val L7.start)–$(val L7.end), H7 start $(val H7.start)"; fi
release_all

# 8. bộ thăm dò lỗi (raise) hay quá giờ (LANE_LOCK_LIGHT_PROBE_S=1, stub ngủ 30 s) ⇒ coi là nặng, chờ tải
load 40; ntests 3; stub_mode raise; gate H8a 0.2 --run-tests --scoped
if started_in H8a 2.5; then bad "8a. thăm dò lỗi mà gate vẫn được nhận"; else ok "8a. thăm dò lỗi ⇒ gate chờ như việc nặng"; fi
release_all
load 40; stub_mode sleep; t8="$(now)"
( cd "${REPO}" && LANE_LOCK_LIGHT_PROBE_S=1 JOB_P="${TMP}/H8b" JOB_DUR=0.2 exec python3 "${LL_PY}" H8b -- python3 "${GATE}" --run-tests --scoped ) \
  > "${TMP}/H8b.log" 2>&1 &
echo $! > "${TMP}/H8b.pid"
if started_in H8b 3.5; then bad "8b. thăm dò quá giờ mà gate vẫn được nhận"; else ok "8b. thăm dò quá giờ ⇒ gate chờ như việc nặng"; fi
release_all
if [ "$(val H8b.start)" != 0 ] && lt "$(val H8b.start)" "$(python3 -c "print(${t8} + 15)")"; then ok "8c. thăm dò bị cắt ở giới hạn (không treo 30 s)"
else bad "8c. thăm dò không bị cắt ở LANE_LOCK_LIGHT_PROBE_S" "bắt đầu $(val H8b.start), gọi lúc ${t8}"; fi
stub_mode ok

# 9. tải thấp: ca này kiểm stub không bị nạp (decide thật đo 0.9–1.2 s ngày 02/11, chỉ tốn khi tải buộc phải chờ)
rm -f "${REPO}/kit/bin/probed"; load 3; gate L9 0.1 --run-tests --scoped; wait_job L9
if [ "$(val L9.start)" != 0 ] && [ ! -e "${REPO}/kit/bin/probed" ]; then ok "9. tải 3: chạy ngay, không gọi bộ thăm dò"
else bad "9. tải thấp vẫn gọi bộ thăm dò hoặc không chạy" "start $(val L9.start), probed=$([ -e "${REPO}/kit/bin/probed" ] && echo có || echo không)"; fi

# 11. nhánh phụ đã commit, cây sạch, @{upstream} == HEAD: base là nhánh đích (origin/main) như task_trunk của gate, không phải upstream
#     (phản biện plan Antigravity 02/11) — 20 file src/ ⇒ nặng, chờ; đối chứng 3 file ⇒ nhẹ
G() { git -C "${REPO}" -c user.email=t@t -c user.name=t "$@"; }
G update-ref refs/remotes/origin/main HEAD && G remote add origin "${TMP}/nowhere.git" || bad "11. dựng fixture origin/main"
on_branch() { # tên số_file: nhánh từ main, commit số_file file src/, upstream origin/<tên> = HEAD
  G checkout -q main 2>/dev/null || G checkout -q master; G checkout -q -b "$1"; mkdir -p "${REPO}/src"
  local i=0; while [ "${i}" -lt "$2" ]; do echo "${i}" > "${REPO}/src/$1_${i}.sh"; i=$((i + 1)); done
  G add src && G commit -q -m "$1" && G update-ref "refs/remotes/origin/$1" HEAD && G config "branch.$1.remote" origin \
    && G config "branch.$1.merge" "refs/heads/$1"
}
ntests diff
on_branch big 20; load 40; gate H11 0.2 --run-tests --scoped
if started_in H11 2.5; then bad "11a. nhánh 20 file đã commit (upstream == HEAD) bị xếp nhẹ"; else ok "11a. nhánh 20 file đã commit: base origin/main ⇒ nặng, chờ"; fi
release_all
on_branch small 3; load 40; gate L11 0.2 --run-tests --scoped
if started_in L11 6; then ok "11b. nhánh 3 file đã commit: nhẹ, nhận ngay"; else bad "11b. nhánh 3 file đã commit vẫn chờ tải"; fi
release_all

# 12. ma trận: file JSON hỏng ⇒ nặng; luật Gradle khớp file đổi ⇒ nặng (heavy_slot.classify, bản của lane_lock khi kit gate thiếu)
mkdir -p "${REPO}/.agents"; echo '{"rules": [' > "${REPO}/.agents/regression_matrix.active.json"
load 40; gate H12a 0.2 --run-tests --scoped
if started_in H12a 2.5; then bad "12a. ma trận hỏng mà gate vẫn nhẹ"; else ok "12a. ma trận JSON hỏng ⇒ nặng, chờ"; fi
release_all
printf '%s\n' '{"rules": [{"component": "app", "watch_files": ["src/**"], "mandatory_regression_tests": [{"id": "G1", "command": "./gradlew testDebugUnitTest"}]}]}' \
  > "${REPO}/.agents/regression_matrix.active.json"
load 40; gate H12b 0.2 --run-tests --scoped
if started_in H12b 2.5; then bad "12b. luật Gradle khớp mà gate vẫn nhẹ"; else ok "12b. luật Gradle khớp file đổi ⇒ nặng, chờ"; fi
release_all
if grep -q 'suite gradle:' "${TMP}/H12b.log"; then ok "12c. log nêu lý do: classify ra suite gradle"
else bad "12c. log không nêu suite gradle" "$(tr '\n' ' ' < "${TMP}/H12b.log" | cut -c1-200)"; fi
rm -rf "${REPO}/.agents"
ntests 3

# 13. nhận dạng lệnh (gate_call): chỉ dạng chạy thẳng post-fix-gate.py --run-tests --scoped với cờ trong danh sách cho phép
if python3 - "${LL_PY}" <<'PY'
import importlib.util as u, sys
s = u.spec_from_file_location("lane_lock_t13", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
g = "/x/post-fix-gate.py"
yes = [["python3", g, "--run-tests", "--scoped"], ["/usr/bin/python3.12", g, "--scoped", "--run-tests", "--brief"],
       ["env", "A=1", "python3", g, "--run-tests", "--scoped", "--diff=origin/main"], [g, "--run-tests", "--scoped", "--timeout", "60"]]
no = [["python3", g, "--scoped"], ["python3", g, "--run-tests", "--scoped", "--full"], ["python3", g, "--run-tests", "--scoped", "--ful"],
      ["python3", g, "--run-tests", "--scoped", "--tree=HEAD"], ["python3", g, "--run-tests", "--scoped", "--diff", "a..b"],
      ["python3", g, "--run-tests", "--scoped", "--matrix", "m.json"], ["python3", g, "--run-tests", "--scoped", "--since", "HEAD~1"],
      ["python3", g, "--run-tests", "--scoped", "--timeout"], ["python3", g, "--run-tests=1", "--scoped"], ["python3", "-u", g, "--run-tests", "--scoped"],
      ["env", "GIT_DIR=/y", "python3", g, "--run-tests", "--scoped"], ["bash", "-c", "python3 %s --run-tests --scoped" % g],
      ["python3", "/x/post-fix-gate.sh", "--run-tests", "--scoped"], ["python3", g, "--run-tests", "--scoped", "extra"]]
bad = [a for a in yes if m.gate_call(a) is None] + [a for a in no if m.gate_call(a) is not None]
base = m.gate_call(yes[2])[1] if m.gate_call(yes[2]) else None
if bad or base != "origin/main":
    print("sai:", bad, "base:", base); sys.exit(1)
PY
then ok "13. nhận dạng gate: 4 dạng nhận, 14 dạng từ chối (--full, viết tắt, --tree=, A..B, --matrix, GIT_DIR=, bash -c…)"
else bad "13. nhận dạng gate sai"; fi

# 14. bộ thăm dò với post-fix-gate.py + scoped_gate.py THẬT của kit này (OCR 02/11): phân loại bằng hàm của gate, không chép lại
#     a. file chỉ nối với luật Gradle qua covers của checklist (rule_watch) ⇒ nặng    b. docs/tool.py: needs_no_test của gate coi là code ⇒
#     unmapped ⇒ [core-smoke] 16 test > 15 ⇒ nặng    c. đối chứng docs/readme.md ⇒ nhẹ
R2="${TMP}/real"; mkdir -p "${R2}/.agents" "${R2}/t" "${R2}/tools" "${R2}/docs"
{ echo "[core-smoke]"; i=0; while [ "${i}" -lt 16 ]; do echo "t/test_${i}.sh"; printf 'exit 0\n' > "${R2}/t/test_${i}.sh"; i=$((i + 1)); done; } \
  > "${R2}/.agents/gate-core.txt"
printf '%s\n' '{"rules": [{"component": "tools", "watch_files": ["tools/*.py"], "mandatory_regression_tests": [{"id": "L1", "command": "true"}]},' \
  '{"component": "app", "watch_files": ["app/**"], "mandatory_regression_tests": [{"id": "G1", "command": "./gradlew testDebugUnitTest"}]}]}' \
  > "${R2}/.agents/regression_matrix.active.json"
printf '%s\n' '{"items": {"G1": {"kind": "test", "covers": ["tools/x.py"]}}}' > "${R2}/.agents/regression_status.json"
echo 'print(1)' > "${R2}/tools/base.py"
git -C "${R2}" init -q && git -C "${R2}" add -A && git -C "${R2}" -c user.email=t@t -c user.name=t commit -q -m init \
  && git -C "${R2}" update-ref refs/remotes/origin/main HEAD || bad "14. dựng fixture repo thật"
probe() { ( cd "${R2}" && python3 - "${LL_PY}" "${DEVKIT_DIR}/bin/post-fix-gate.py" <<'PY'
import importlib.util as u, sys
s = u.spec_from_file_location("lane_lock_t14", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
light, why = m.light_job(["python3", sys.argv[2], "--run-tests", "--scoped", "--brief"])
print(("LIGHT " if light else "HEAVY ") + why)
PY
) 2>&1 | tail -1; }
echo 'print(2)' > "${R2}/tools/x.py"; v14a="$(probe)"; rm -f "${R2}/tools/x.py"
case "${v14a}" in "HEAVY suite gradle:"*) ok "14a. covers của checklist nối file với luật Gradle ⇒ nặng (${v14a})" ;;
  *) bad "14a. file nối luật Gradle qua covers bị xếp nhẹ" "${v14a}" ;; esac
echo 'print(3)' > "${R2}/docs/tool.py"; v14b="$(probe)"; rm -f "${R2}/docs/tool.py"
case "${v14b}" in "HEAVY 16 test"*) ok "14b. docs/tool.py là code theo needs_no_test của gate ⇒ [core-smoke] ⇒ nặng (${v14b})" ;;
  *) bad "14b. docs/tool.py bị coi là tài liệu" "${v14b}" ;; esac
echo '# x' > "${R2}/docs/readme.md"; v14c="$(probe)"; rm -f "${R2}/docs/readme.md"
case "${v14c}" in "LIGHT "*) ok "14c. đối chứng: chỉ đổi tài liệu ⇒ nhẹ (${v14c})" ;; *) bad "14c. đổi tài liệu bị xếp nặng" "${v14c}" ;; esac

# 10. không file khoá / marker mới: thư mục lane chỉ còn lane-1.lock, lane-2.lock; thư mục heavy_slot không có gì (gate_busy đếm gate-*.lock.held)
left="$(cd "${LANE_LOCK_DIR}" && ls -A | tr '\n' ' ')"; heavy_left="$(ls -A "${SB_HEAVY_SLOT_DIR}" | tr '\n' ' ')"
if [ "${left}" = "lane-1.lock lane-2.lock " ] && [ -z "${heavy_left}" ]; then ok "10. không file khoá / marker mới (lane: ${left}; heavy: rỗng)"
else bad "10. có file lạ trong thư mục khoá" "lane: ${left}; heavy: ${heavy_left}"; fi

echo
if [ "${fails}" -eq 0 ]; then echo "test_lane_lock_light: tất cả XANH"; exit 0; fi
echo "test_lane_lock_light: ${fails} FAIL"; exit 1
