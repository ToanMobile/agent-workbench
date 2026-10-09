#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# foreign_repo_gate.sh — Stop hook: the gates ran for the wrong project.
#
# Every DevKit hook works on CLAUDE_PROJECT_DIR, the project the session STARTED in. A session
# that edits another repo (a PM session in agent-workbench driving Goods, 2026-09-25) is gated
# for the workbench only: none of its Stops ever checked Goods, and half-done work reached HEAD.
#
# STOPS ONCE (exit 2) per session when this session's Edit/Write/MultiEdit/NotebookEdit calls
# touched files of ANOTHER git repo that has the DevKit (.agents/devkit), naming each repo and
# its gate command; later stops of the session pass. Edits inside the project, and repos
# without the DevKit, are not its business. It does not run the other repo's gate itself (a
# Unity or Gradle suite would hold every Stop for minutes) — the agent runs it there.
#
# Fail-open on any error (no transcript, unreadable state). Off: FOREIGN_REPO_GATE=0.
# ─────────────────────────────────────────────────────────────────────────────
INPUT="$(cat)"
[ "${FOREIGN_REPO_GATE:-1}" = "0" ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# The payload goes to python on fd 3, not in an env var (2026-10-09): past the OS limit for one variable (Linux 128 KiB,
# macOS ~1 MiB for args + env) python could not start and the gate passed (tests/gates/test_hook_large_payload.sh).
FRG_REPO="${REPO_ROOT}" python3 -I <<'PY' 3<<<"${INPUT}"
import json, os, sys

try:
    with os.fdopen(3, encoding="utf-8", errors="replace") as _fh:
        _raw = _fh.read()
except OSError:
    _raw = ""
try:
    d = json.loads(_raw.strip() or "{}")
except ValueError:
    sys.exit(0)
tp = d.get("transcript_path") or ""
sid = str(d.get("session_id") or "")
repo = os.path.realpath(os.environ.get("FRG_REPO") or ".")
if not tp or not os.path.isfile(tp) or not sid:
    sys.exit(0)

def top_of(path):
    """The git top-level holding path (a .git dir or file), or None."""
    p = os.path.dirname(path)
    while p and p != os.path.dirname(p):
        if os.path.exists(os.path.join(p, ".git")):
            return p
        p = os.path.dirname(p)
    return None

foreign = {}
try:
    with open(tp, encoding="utf-8", errors="replace") as f:
        for raw in f:
            if '"file_path"' not in raw and '"notebook_path"' not in raw:
                continue
            try:
                e = json.loads(raw)
            except ValueError:
                continue
            if e.get("type") != "assistant":
                continue
            for c in (e.get("message") or {}).get("content") or []:
                if not (isinstance(c, dict) and c.get("type") == "tool_use"
                        and c.get("name") in ("Edit", "Write", "MultiEdit", "NotebookEdit")):
                    continue
                inp = c.get("input") or {}
                fp = inp.get("file_path") or inp.get("notebook_path") or ""
                if not isinstance(fp, str) or not os.path.isabs(fp):
                    continue
                real = os.path.realpath(fp)
                if real == repo or real.startswith(repo + os.sep):
                    continue
                top = top_of(real)
                if top and os.path.realpath(top) != repo and os.path.exists(os.path.join(top, ".agents", "devkit")):
                    foreign.setdefault(top, os.path.relpath(real, top))
except OSError:
    sys.exit(0)
if not foreign:
    sys.exit(0)

state_path = os.path.join(repo, ".claude", "audit-gate", "foreign_repo_gate.state")
try:
    state = json.load(open(state_path, encoding="utf-8"))
    if not isinstance(state, dict):
        state = {}
except (OSError, ValueError):
    state = {}
told = set(state.get(sid) or [])
new = sorted(t for t in foreign if t not in told)
if not new:
    sys.exit(0)
state[sid] = sorted(told | set(new))
state = dict(list(state.items())[-50:])   # the last 50 sessions are plenty
try:
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    tmp = state_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f)
    os.replace(tmp, state_path)
except OSError:
    sys.exit(0)   # cannot remember having told it: do not risk blocking every stop

lines = ["⛔ FOREIGN-REPO GATE: phiên này đã sửa file của repo KHÁC, nhưng mọi cổng Stop chỉ kiểm "
         + repo + " (thư mục phiên bắt đầu):"]
for t in new:
    lines.append("  - " + t + " (vd " + foreign[t] + ") — chạy cổng của repo đó trước khi báo xong:")
    lines.append("      cd " + t + " && CLAUDE_PROJECT_DIR=\"$PWD\" python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full")
lines.append("Chặn 1 lần mỗi phiên; lần dừng sau sẽ qua. Không chạy được (thiếu công cụ, repo đang có phiên khác) → nói rõ cho người dùng.")
sys.stderr.write("\n".join(lines) + "\n")
sys.exit(2)
PY
rc=$?
[ "${rc}" -eq 2 ] && exit 2
exit 0
