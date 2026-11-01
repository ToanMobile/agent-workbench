#!/usr/bin/env bash
# Test hồi quy #813: ngân sách CPU của prompt hook (hooks/prompt_context.sh, ca bắt bug) trong ĐÚNG môi trường gate chạy test.
#
# Cơ chế lỗi (đo 01/11): tests/run_impacted.sh:243 cho mỗi bài TMPDIR mới + PYTHONPYCACHEPREFIX="$TMPDIR/pyc" (thư mục rỗng),
# còn Claude Code xuất PYTHONDONTWRITEBYTECODE=1 cho mọi hook/lệnh. Prefix rỗng mà không được ghi ⇒ python3 của hook compile lại
# TOÀN BỘ module (stdlib + regression_checklist.py 3517 dòng) ở MỌI lần chạy: ~180–230 ms CPU ở load 7–14, trong khi chạy tay
# (stdlib có pyc sẵn) chỉ ~100 ms. Ca "prompt hook with bug capture" của test_budgets.sh vì vậy đỏ ở mọi gate có chọn nó
# (PR thêm rule ma trận là file lõi nên luôn chọn nó), không phải do ma trận to (ma trận 12 / 146 / 145 / 149 / 584 rule đo
# như nhau).
#
# Fixture: ma trận cỡ PR #742 (145 rule, 179 test, 495 glob) + checklist 179 test + 167 bug (~ checklist thật của workbench).
# Ngân sách giữ nguyên test_budgets.sh: trung vị CPU 5 lần ≤ 150 ms, wall ≤ 5×. Thêm 2 ý không phụ thuộc tải:
#   - sau lần chạy đầu, bytecode của regression_checklist được giữ trong TMPDIR (lần sau không compile lại), ở cả env gate
#     lẫn env hook của Claude Code (PYTHONDONTWRITEBYTECODE=1, không prefix);
#   - không một .pyc nào được ghi vào cây kit (lý do của sys.dont_write_bytecode trong enrich_context.py).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export STALE_RERUN=0 RED_PROOF=0
STAMP="$TMP/stamp"; : > "$STAMP"

P="$TMP/p"; mkdir -p "$P/.agents" "$P/src"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
python3 - "$P" <<'PY'
import json, os, sys, time
P = sys.argv[1]
for m in range(30):
    os.makedirs(f"{P}/src/m{m}", exist_ok=True)
    for f in range(100):
        open(f"{P}/src/m{m}/F{f}.kt", "w").write(f"class F{f}\n")
# Cỡ ma trận của PR #742 @f693b753: 145 rule, 179 test bắt buộc, 495 glob watch_files.
rules, tests = [], []
for r in range(145):
    globs = [f"src/m{(r + k) % 30}/F{(r * 7 + k) % 100}.kt" for k in range(4 if r < 60 else 3)]
    mrt = [{"id": f"REG-{r}-{k}", "name": f"r{r} t{k}", "command": "true"} for k in range(2 if r < 34 else 1)]
    rules.append({"component": f"C{r}", "watch_files": globs, "mandatory_regression_tests": mrt})
    tests += [(t["id"], f"C{r}", globs) for t in mrt]
assert (len(rules), len(tests), sum(len(x["watch_files"]) for x in rules)) == (145, 179, 495)
json.dump({"adopted": True, "rules": rules}, open(f"{P}/.agents/regression_matrix.active.json", "w"))
now = time.time(); at = time.strftime("%Y-%m-%d %H:%M:%S")
items = {}
for tid, comp, globs in tests:
    items[tid] = {"id": tid, "kind": "test", "title": tid, "component": comp, "command": "true", "watch_files": globs,
                  "history": [], "last": {"status": "PASS", "at": at, "ts": now, "commit": None, "duration": "1s", "exit_code": 0}}
for b in range(167):
    items[f"BUG-{b}"] = {"id": f"BUG-{b}", "kind": "bug", "title": f"Lỗi số {b} khi mở màn hình {b}", "component": f"C{b % 145}",
                         "created_at": at, "tests": [tests[b % 179][0]] if b % 3 else [], "fixed": True,
                         "last": None, "history": [], "evidence": "x" * 200}
json.dump({"version": 1, "items": items}, open(f"{P}/.agents/regression_status.json", "w"))
PY
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
python3 -c 'import json; print(json.dumps({"prompt": "App bị crash khi mở màn hình bản đồ lần thứ hai", "session_id": "b", "transcript_path": "/nonexistent/claude-tr.jsonl"}))' > "$TMP/prompt.json"

# Giống test_budgets.sh: CPU của hook và mọi tiến trình con (getrusage RUSAGE_CHILDREN), trung vị 5 lần; wall trần 5×.
median_ms() {  # median_ms <cmd…> (stdin from $STDIN_FILE): "<median CPU ms> <median wall ms>"
  python3 - "$@" <<'PY'
import os, resource, statistics, subprocess, sys, time
cpu, wall = [], []
for i in range(5):
    data = open(os.environ["STDIN_FILE"], "rb").read() if os.environ.get("STDIN_FILE") else b""
    r0, t = resource.getrusage(resource.RUSAGE_CHILDREN), time.perf_counter()
    subprocess.run(sys.argv[1:], input=data, capture_output=True)
    wall.append((time.perf_counter() - t) * 1000)
    r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu.append((r1.ru_utime + r1.ru_stime - r0.ru_utime - r0.ru_stime) * 1000)
print(int(statistics.median(cpu)), int(statistics.median(wall)))
PY
}
within() {  # within <label> <budget ms> "<cpu> <wall>"
  set -- "$1" "$2" $3
  if [ "$3" -le "$2" ] && [ "$4" -le $(( $2 * 5 )) ]; then ok "$1: ${3} ms CPU (≤ $2), ${4} ms wall (≤ $(( $2 * 5 )))"
  else fail "$1: ${3} ms CPU (budget $2), ${4} ms wall (cap $(( $2 * 5 )))"; fi
}
cached_rc() {  # cached_rc <dir>: số file bytecode của regression_checklist dưới <dir>
  find "$1" -name 'regression_checklist*.pyc' 2>/dev/null | wc -l | tr -d ' '
}

# 1) Env gate (run_impacted.sh:243): TMPDIR mới, PYTHONPYCACHEPREFIX rỗng trong đó, PYTHONDONTWRITEBYTECODE=1 của Claude Code.
G="$TMP/g"; mkdir -p "$G"
OUT="$(TMPDIR="$G" PYTHONPYCACHEPREFIX="$G/pyc" PYTHONDONTWRITEBYTECODE=1 bash "$DEVKIT_DIR/hooks/prompt_context.sh" < "$TMP/prompt.json" 2>&1)"
case "$OUT" in *"Bug đã ghi vào checklist: "*) ok "env gate: hook vẫn ghi bug vào checklist" ;;
  *) fail "env gate: hook không còn ghi bug (output: $(printf '%s' "$OUT" | head -c 300))" ;; esac
[ "$(cached_rc "$G")" -ge 1 ] && ok "env gate: bytecode regression_checklist được giữ trong TMPDIR sau lần chạy đầu" \
  || fail "env gate: không giữ bytecode nào của regression_checklist dưới $G — mỗi prompt compile lại 3517 dòng + stdlib"
within "env gate, ma trận cỡ #742: prompt hook with bug capture" 150 \
  "$(TMPDIR="$G" PYTHONPYCACHEPREFIX="$G/pyc" PYTHONDONTWRITEBYTECODE=1 STDIN_FILE="$TMP/prompt.json" median_ms bash "$DEVKIT_DIR/hooks/prompt_context.sh")"

# 2) Env hook của Claude Code: PYTHONDONTWRITEBYTECODE=1, không prefix — bytecode của kit vẫn phải được giữ ngoài cây kit.
H="$TMP/h"; mkdir -p "$H"
env -u PYTHONPYCACHEPREFIX TMPDIR="$H" PYTHONDONTWRITEBYTECODE=1 bash "$DEVKIT_DIR/hooks/prompt_context.sh" < "$TMP/prompt.json" >/dev/null 2>&1
[ "$(cached_rc "$H")" -ge 1 ] && ok "env hook: bytecode regression_checklist được giữ trong TMPDIR" \
  || fail "env hook: không giữ bytecode nào của regression_checklist dưới $H"

# 3) Không ghi .pyc / __pycache__ nào vào cây kit (lý do của sys.dont_write_bytecode trong enrich_context.py).
LEAK="$(find "$DEVKIT_DIR" -newer "$STAMP" \( -name '*.pyc' -o -name __pycache__ \) 2>/dev/null | head -3)"
[ -z "$LEAK" ] && ok "không có bytecode nào ghi vào cây kit" || fail "bytecode ghi vào cây kit: $LEAK"

[ "$FAILS" -eq 0 ] && echo "✅ test_prompt_hook_gate_env: all passed" || { echo "❌ test_prompt_hook_gate_env: $FAILS failed"; exit 1; }
