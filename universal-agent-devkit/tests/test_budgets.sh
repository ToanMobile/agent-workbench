#!/usr/bin/env bash
# Regression test: time budgets of the hooks, on a checklist the size of the largest real one
# (≈180 rows, a git repo with a few thousand files). Median of 5 runs, so one slow run on a busy
# machine does not fail it:
#   prompt hook (bug prompt → REPORTED row written)  ≤ 150 ms  (plan: 100 ms of our own work;
#                                                               python start-up is ~40 ms of it)
#   SessionStart (STALE, auto-close, counts)          ≤ 2 s
#   Stop evidence gate on a proven fix (no test run)  ≤ 5 s
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export STALE_RERUN=0 RED_PROOF=0

P="$TMP/p"; mkdir -p "$P/.agents" "$P/src"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
python3 - "$P" <<'PY'
import json, os, sys, time
P = sys.argv[1]
for m in range(30):
    os.makedirs(f"{P}/src/m{m}", exist_ok=True)
    for f in range(100):
        open(f"{P}/src/m{m}/F{f}.kt", "w").write(f"class F{f}\n")
rules = [{"component": f"M{m}", "watch_files": [f"src/m{m}/*"],
          "mandatory_regression_tests": [{"id": f"REG-{m}", "name": f"m{m}", "command": "true"}]} for m in range(12)]
json.dump({"adopted": True, "rules": rules}, open(f"{P}/.agents/regression_matrix.active.json", "w"))
now = time.time(); at = time.strftime("%Y-%m-%d %H:%M:%S")
items = {}
for m in range(12):
    items[f"REG-{m}"] = {"id": f"REG-{m}", "kind": "test", "title": f"m{m}", "component": f"M{m}", "command": "true",
                         "watch_files": [f"src/m{m}/*"], "history": [],
                         "last": {"status": "PASS", "at": at, "ts": now, "commit": None, "duration": "1s", "exit_code": 0}}
for b in range(167):
    items[f"BUG-{b}"] = {"id": f"BUG-{b}", "kind": "bug", "title": f"Lỗi số {b} khi mở màn hình {b}", "component": f"M{b % 12}",
                         "created_at": at, "tests": [f"REG-{b % 12}"] if b % 3 else [], "fixed": True,
                         "last": None, "history": [], "evidence": "x" * 200}
json.dump({"version": 1, "items": items}, open(f"{P}/.agents/regression_status.json", "w"))
PY
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"

median_ms() {  # median_ms <cmd…> (stdin from $STDIN_FILE)
  python3 - "$@" <<'PY'
import os, statistics, subprocess, sys, time
ts = []
for i in range(5):
    data = open(os.environ["STDIN_FILE"], "rb").read() if os.environ.get("STDIN_FILE") else b""
    t = time.perf_counter(); subprocess.run(sys.argv[1:], input=data, capture_output=True); ts.append((time.perf_counter() - t) * 1000)
print(int(statistics.median(ts)))
PY
}

python3 -c 'import json; print(json.dumps({"prompt": "App bị crash khi mở màn hình bản đồ lần thứ hai", "session_id": "b"}))' > "$TMP/prompt.json"
ms="$(STDIN_FILE="$TMP/prompt.json" median_ms bash "$DEVKIT_DIR/hooks/prompt_context.sh")"
[ "$ms" -le 150 ] && ok "prompt hook with bug capture: ${ms} ms (≤ 150)" || fail "prompt hook: ${ms} ms > 150"
echo '{}' > "$TMP/empty.json"
ms="$(STDIN_FILE="$TMP/empty.json" median_ms bash "$DEVKIT_DIR/hooks/session_context.sh")"
[ "$ms" -le 2000 ] && ok "SessionStart with STALE check: ${ms} ms (≤ 2000)" || fail "SessionStart: ${ms} ms > 2000"
python3 - "$P" <<'PY'
import json, sys
P = sys.argv[1]
steps = [("Bash", {"command": "python3 -m pytest tests"}, "FAILED tests/test_a.py::t\n1 failed", True),
         ("Edit", {"file_path": f"{P}/src/m0/F0.kt", "old_string": "F0", "new_string": "F0 "}, "ok", False),
         ("Bash", {"command": "python3 -m pytest tests"}, "1 passed", False)]
lines = []
for i, (n, inp, res, err) in enumerate(steps):
    lines.append(json.dumps({"message": {"content": [{"type": "tool_use", "id": f"t{i}", "name": n, "input": inp}]}}))
    lines.append(json.dumps({"message": {"content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": res, "is_error": err}]}}))
open(f"{P}/tr.jsonl", "w").write("\n".join(lines) + "\n")
json.dump({"session_id": "b", "transcript_path": f"{P}/tr.jsonl", "last_assistant_message": "Đã fix lỗi, test RED→GREEN."},
          open(f"{P}/stop.json", "w"))
PY
ms="$(LESSON_REMINDER=0 STDIN_FILE="$P/stop.json" median_ms bash "$DEVKIT_DIR/hooks/test_evidence_gate.sh")"
[ "$ms" -le 5000 ] && ok "Stop evidence gate on a proven fix: ${ms} ms (≤ 5000)" || fail "Stop gate: ${ms} ms > 5000"

[ "$FAILS" -eq 0 ] && echo "✅ test_budgets: all passed" || { echo "❌ test_budgets: $FAILS failed"; exit 1; }
