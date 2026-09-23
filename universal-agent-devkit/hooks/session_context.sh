#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# session_context.sh — SessionStart hook: what the model must know before the first
# edit of a session, loaded by the harness instead of left to "read AGENTS.md".
#
# Prints (added to the model's context), in a few dozen lines at most:
#   • the active profile (.active-profile.json)
#   • the MAP of the project's failure memory (.agents/instincts.md): one line per
#     trap with its line number — not the whole file, so a large memory never floods
#     the context. Over 20 KB the index (.agents/instincts-index.md, from
#     scripts/index_memory.py) is regenerated when stale and pointed to instead.
#   • the regression checklist state (FAIL / UNCOVERED counts) and whether the
#     regression matrix and the git pre-commit gate are active
#   • the gates that will actually run, so the model does not have to guess
#
# Never blocks: always exit 0. Escape hatch: SESSION_CONTEXT=0.
# Protocol: stdin JSON; stdout is added to the context.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

[ "${SESSION_CONTEXT:-1}" = "0" ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0
cat >/dev/null  # stdin is not needed

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SELF="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null)"
INDEXER=""
for cand in "$(dirname "$(dirname "${SELF}")")/scripts/index_memory.py" \
            "${DEVKIT_ROOT:-}/scripts/index_memory.py" \
            "${HOME}/.universal-agent-devkit/scripts/index_memory.py"; do
  [ -f "${cand}" ] && { INDEXER="${cand}"; break; }
done
HOOK_FILE="$(git -C "${REPO_ROOT}" rev-parse --path-format=absolute --git-path hooks/pre-commit 2>/dev/null || true)"

REPO_ROOT="${REPO_ROOT}" INDEXER="${INDEXER}" HOOK_FILE="${HOOK_FILE}" python3 - <<'PY' 2>/dev/null
import json, os, re, subprocess, sys

root = os.environ["REPO_ROOT"]
out = []

prof = "none"
try:
    with open(os.path.join(root, ".active-profile.json"), encoding="utf-8") as f:
        prof = json.load(f).get("profile") or "none"
except (OSError, ValueError, AttributeError):
    pass
out.append(f"[DevKit] Phiên mới — profile: {prof}. DevKit là core; bộ riêng của dự án ở .agents/local/.")

# Failure memory map
inst = os.path.join(root, ".agents", "instincts.md")
if os.path.isfile(inst):
    text = open(inst, encoding="utf-8", errors="replace").read()
    visible = re.sub(r"<!--.*?-->", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.DOTALL)
    heads = [(i + 1, l[4:].strip()) for i, l in enumerate(visible.splitlines())
             if l.startswith("### [INSTINCT-") and "XXX" not in l.split("]")[0]]
    size_kb = os.path.getsize(inst) / 1024
    if size_kb > 20:
        index = os.path.join(root, ".agents", "instincts-index.md")
        indexer = os.environ.get("INDEXER")
        if indexer and (not os.path.exists(index) or os.path.getmtime(index) < os.path.getmtime(inst)):
            subprocess.run([sys.executable, indexer, inst], capture_output=True, timeout=20)
        out.append(f"Bài học của dự án: .agents/instincts.md ({len(heads)} mục, {size_kb:.0f} KB — KHÔNG đọc cả file). "
                   f"Tra mục lục .agents/instincts-index.md rồi đọc đúng mục bằng `sed -n 'a,bp'`.")
    elif heads:
        out.append(f"Bài học của dự án (.agents/instincts.md, {len(heads)} mục) — trước khi sửa code chạm vào "
                   f"chủ đề nào, đọc đúng mục đó: `sed -n '<dòng>,+12p' .agents/instincts.md`")
        for line, title in heads[:40]:
            out.append(f"  L{line} {title}")
        if len(heads) > 40:
            out.append(f"  … và {len(heads) - 40} mục nữa")

# Regression state
matrix = os.path.join(root, ".agents", "regression_matrix.active.json")
status = os.path.join(root, ".agents", "regression_status.json")
parts = []
parts.append("ma trận hồi quy: " + (".agents/regression_matrix.active.json" if os.path.isfile(matrix) else "chưa có"))
try:
    indexer = os.environ.get("INDEXER") or ""
    counts = {}
    if indexer and os.path.isfile(status):
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(indexer)), "bin"))
        sys.dont_write_bytecode = True
        import regression_checklist as rc  # the same status rules the checklist view uses
        counts = rc.summary(rc.load(root))
    bad = {k: v for k, v in counts.items() if k in ("FAIL", "TIMEOUT", "UNCOVERED", "NEEDS_TEST")}
    if bad:
        parts.append("checklist còn " + ", ".join(f"{v} {k}" for k, v in sorted(bad.items()))
                     + " (.agents/regression_checklist.md)")
except Exception:
    pass  # a corrupt checklist must not break session start
hook = os.environ.get("HOOK_FILE") or ""
try:
    pre = "universal-agent-devkit:githook" in open(hook, encoding="utf-8", errors="replace").read()
except OSError:
    pre = False
parts.append("git pre-commit: " + ("bật" if pre else "chưa cài (agent-kit githooks install)"))
out.append("Trạng thái: " + "; ".join(parts) + ".")

out.append("Gate chạy tự động: Bash chặn git nguy hiểm/--no-verify; Edit cần Read trước; khi dừng: test hồi quy "
           "theo ma trận, 'test pass' phải có kết quả runner và test mới phải từng ĐỎ, 'đã fix' phải có cặp test "
           "ĐỎ→XANH trong phiên, sửa bug xong được nhắc ghi bài học (agent-kit learn).")
print("\n".join(out))
PY
exit 0
