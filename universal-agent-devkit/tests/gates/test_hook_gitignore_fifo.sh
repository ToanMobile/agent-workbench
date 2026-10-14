#!/usr/bin/env bash
# Every hook writes <project>/.claude/audit-gate/.gitignore when it is missing: `[ -f X ] || printf '*\n' > X`. A FIFO planted
# there is not a regular file, so the redirect opened it and blocked until the hook was killed at its timeout - and a Stop hook
# killed by its timeout lets the Stop through (issues-bugs.md A.4, FIFO class; the subagent fix of post-fix-gate/proof_gate/push_gate,
# 14/10, named these 15 hooks as left). Now `[ -e X ]`: anything already there is kept as it is.
# Dynamic: each hook runs with a FIFO at that path and must end within 10 s. Static: no hook keeps the `-f` form.
# The fixture ignores .claude/audit-gate/ in the project's .gitignore, as all 5 repos do (checked 14/10): git itself opens every
# .gitignore of a folder it walks, so a FIFO .gitignore in a folder git DOES walk hangs `git status` / `ls-files` - git's limit, not a
# hook's write (the hooks bound their git calls; ponytail: guard it if a planted FIFO is ever seen in a tracked folder).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 - "$DEVKIT_DIR" "$TMP" <<'PY'
import glob, json, os, re, subprocess, sys

dk, tmp = sys.argv[1:3]
fails = 0
hooks = sorted(h for h in glob.glob(os.path.join(dk, "hooks", "*.sh"))
               if '/.gitignore" ] || printf' in open(h, encoding="utf-8", errors="replace").read())
if len(hooks) < 15:
    print(f"✖ only {len(hooks)} hooks write .gitignore (expected 15+): the scan has gone blind"); fails += 1
for h in hooks:
    name = os.path.basename(h)
    for n, line in enumerate(open(h, encoding="utf-8", errors="replace"), 1):
        if re.search(r'\[ -f "\$\{LOG_DIR\}/\.gitignore" \] \|\| printf', line):
            print(f"✖ {name}:{n}: still `[ -f …/.gitignore ] || printf >` (a FIFO there blocks the redirect)"); fails += 1
    p = os.path.join(tmp, name.replace(".sh", ""))
    os.makedirs(os.path.join(p, ".claude", "audit-gate"))
    subprocess.run(["git", "init", "-q", p], check=True)
    with open(os.path.join(p, ".gitignore"), "w") as fh:
        fh.write(".claude/audit-gate/\n")
    os.mkfifo(os.path.join(p, ".claude", "audit-gate", ".gitignore"))
    payload = {"session_id": "s", "cwd": p, "hook_event_name": "Stop", "transcript_path": "/dev/null",
               "tool_name": "Bash", "tool_input": {"command": "ls"}, "prompt": "hi"}
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env["CLAUDE_PROJECT_DIR"] = p
    try:
        subprocess.run(["bash", h], input=json.dumps(payload).encode(), capture_output=True, env=env, cwd=p, timeout=10)
        print(f"✔ {name}: ends with a FIFO at .claude/audit-gate/.gitignore")
    except subprocess.TimeoutExpired:
        print(f"✖ {name}: HUNG on a FIFO at .claude/audit-gate/.gitignore (killed after 10 s)"); fails += 1
sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" = 0 ] && echo "hook .gitignore FIFO: all checks passed" || { echo "hook .gitignore FIFO: FAILED"; exit 1; }
