#!/usr/bin/env bash
# #1127 AC1: hook prompt trên runner macOS đo 133 ms CPU (trần 110) dù regex đã lười (#1157). Prompt tả bug lặp lại (4/5 lượt của
# test_budgets.sh) tốn thêm: `git rev-parse` của in_linked_worktree (~11 ms CPU cả tiến trình con) dù checkout chính có `.git` là
# thư mục thì câu trả lời luôn là False, và regression_checklist nạp tempfile (~7 ms) / argparse chỉ để ghi file và chạy CLI.
# Luồng lặp trên checkout chính: không spawn tiến trình nào, không nạp tempfile / argparse, vẫn báo dòng bug đã ghi.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="${DEVKIT_DIR_UNDER_TEST:-$(cd "$(dirname "$0")/../.." && pwd)}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/p"; mkdir -p "$P/.agents"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t
echo '{"version": 1, "items": {}}' > "$P/.agents/regression_status.json"
git -C "$P" add -A && git -C "$P" commit -qm init
python3 -c 'import json; print(json.dumps({"prompt": "App bị crash khi mở màn hình bản đồ lần thứ hai", "session_id": "b", "transcript_path": "/nonexistent/claude-tr.jsonl"}))' > "$TMP/prompt.json"
export CLAUDE_PROJECT_DIR="$P" STALE_RERUN=0 RED_PROOF=0
# Lượt 1: ghi dòng REPORTED (lượt này được spawn: trunk mode đọc HEAD của main bằng git show).
python3 -I -B "$DEVKIT_DIR/scripts/context/enrich_context.py" --hook < "$TMP/prompt.json" > "$TMP/first" 2>&1
# Lượt 2 (lặp): PROMPT_DEDUPE=0 để dòng "Bug đã ghi" được in lại — bằng chứng luồng bug chạy, không phải lượt bị bỏ qua.
PROMPT_DEDUPE=0 python3 -I -B - "$DEVKIT_DIR/scripts/context/enrich_context.py" "$TMP/prompt.json" <<'PY'
import io, runpy, sys
enrich, prompt = sys.argv[1], sys.argv[2]
spawns = []
sys.addaudithook(lambda ev, args: spawns.append(f"{ev} {str(args)[:120]}") if ev in (
    "subprocess.Popen", "os.posix_spawn", "os.exec", "os.system", "os.fork", "os.spawn") else None)
sys.stdin = io.TextIOWrapper(io.BytesIO(open(prompt, "rb").read()), encoding="utf-8")
sys.argv = [enrich, "--hook"]
out, real = io.StringIO(), sys.stdout
sys.stdout = out
try:
    runpy.run_path(enrich, run_name="__main__")
except SystemExit:
    pass
sys.stdout = real
fails = 0
if "Bug đã ghi vào checklist" not in out.getvalue():
    fails += 1; print("✖ the bug path did not run (no 'Bug đã ghi vào checklist' line): the checks below would prove nothing")
    print(out.getvalue()[:600])
if spawns:
    fails += 1; print(f"✖ repeat bug prompt in a main checkout spawned {len(spawns)} process(es):"); [print("   ", s) for s in spawns]
else:
    print("✔ repeat bug prompt in a main checkout: no subprocess")
loaded = [m for m in ("tempfile", "argparse") if m in sys.modules]
if loaded:
    fails += 1; print(f"✖ the hook path imported {', '.join(loaded)} (only writes / the CLI need them)")
else:
    print("✔ tempfile and argparse not imported on the hook path")
sys.exit(1 if fails else 0)
PY
rc=$?
# Hook thật qua prompt_context.sh: enrich_context chạy như module từ pyc trong thư mục cache của hook ($TMPDIR/devkit-pycache-<uid>),
# không compile lại từ nguồn ở mỗi prompt (file đưa tên trên dòng lệnh không bao giờ có pyc: ~6 ms CPU mỗi lần).
mkdir -p "$TMP/tmpdir"
TMPDIR="$TMP/tmpdir" PROMPT_DEDUPE=0 bash "$DEVKIT_DIR/hooks/prompt_context.sh" < "$TMP/prompt.json" > "$TMP/hook_out" 2>&1
if [ -n "$(find "$TMP/tmpdir" -name 'enrich_context*.pyc' 2>/dev/null)" ]; then
  echo "✔ prompt hook runs enrich_context from its cached bytecode"
else
  echo "✖ prompt hook compiled enrich_context.py from source (no enrich_context*.pyc under the hook's pycache prefix)"; rc=1
fi
grep -q "Bug đã ghi vào checklist" "$TMP/hook_out" || { echo "✖ prompt hook output lost the bug line: $(head -c 300 "$TMP/hook_out")"; rc=1; }
exit $rc
