#!/usr/bin/env python3
"""PreToolUse(Edit|Write|MultiEdit|NotebookEdit|Bash) guard: an agent may not write or delete what decides its own review.

Audit 31/10/2026 (P0c): the 4-way review gate is only as strong as the files behind it. An agent could rewrite a run's
summary.json, its settings (the hook registrations), the hooks, the review scripts or the CI workflow and pass its own gate.
Denied for agent tool calls:
  .git/review-fanout/**         review runs, verdicts, override tokens and log
  .claude/settings*.json        hook registration / permissions
  hooks/** (any DevKit hooks dir: universal-agent-devkit/hooks, .agents/devkit/hooks, hooks/)
  bin/review*  (review-fanout.sh, review-merge.py, review_runner.py, review-full.py, review_sign.py)
  .github/workflows/**          CI
  ~/.config/agent-workbench/**  the summary seal key
Bash: write targets through hooks/shell_writes.py (redirects, cp/mv/rm/tee/sed -i, …); an interpreter one-liner (python -c,
node -e, perl -e, …) that names a protected path is denied too (its writes cannot be read statically).
Reading stays allowed. DEVKIT_ALLOW_GATE_EDIT=1 in the hook process environment (the operator's shell / launchd, never a
prefix on the command: the agent cannot set it for its own hooks) turns the guard off for a maintenance session.
Its own errors never block (it reports them on stderr).
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

PROTECTED = re.compile(
    r"(?:^|/)\.git/review-fanout(?:/|$)"
    r"|(?:^|/)\.claude/settings[^/]*\.json$"
    r"|(?:^|/)hooks/[^/]"
    r"|(?:^|/)bin/review[^/]*$"
    r"|(?:^|/)\.github/workflows(?:/|$)"
    r"|(?:^|/)\.config/agent-workbench(?:/|$)")
INLINE = re.compile(r"(?:^|[\s;&|(])(?:python[\d.]*|node|deno|bun|ruby|perl|php)\s+(?:-[A-Za-z]*[ce]\b|-\s|<<)")
PATH_WORD = re.compile(r"[\w.~/-]*(?:\.git/review-fanout|\.claude/settings[\w.-]*\.json|hooks/[\w.-]+|bin/review[\w.-]*"
                       r"|\.github/workflows|\.config/agent-workbench)[\w./-]*")
REASON = ("Blocked by guard-review-tamper: agents may not write or delete the review machinery ({}). The 4-way review gate "
          "decides on these files; change them through a reviewed PR by the operator (DEVKIT_ALLOW_GATE_EDIT=1 in the hook "
          "environment for a maintenance session).")


def _norm(p, cwd):
    p = os.path.expanduser(str(p))
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    return os.path.normpath(p)


def protected(p, cwd):
    return bool(p) and bool(PROTECTED.search(_norm(p, cwd)))


def bash_hits(cmd, cwd):
    hits = []
    try:
        import shell_writes
        for kind, target, here in shell_writes.targets(cmd, cwd) or []:
            if kind in ("redirect", "file", "interp", "unparsed") and target and protected(target, here or cwd):
                hits.append(target)
    except Exception as e:   # noqa: BLE001 — the textual rule below still runs
        sys.stderr.write(f"guard-review-tamper: shell_writes unavailable ({e.__class__.__name__}) — textual check only\n")
    if INLINE.search(cmd):
        hits += [w for w in PATH_WORD.findall(cmd) if protected(w, cwd)]
    return hits


def judge(payload):
    if not isinstance(payload, dict):
        return None
    tool = str(payload.get("tool_name") or payload.get("toolName") or "")
    ti = next((v for v in (payload.get(k) for k in ("tool_input", "toolInput", "input")) if isinstance(v, dict)), {})
    cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) and payload.get("cwd") else os.getcwd()
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        p = ti.get("file_path") or ti.get("filePath") or ti.get("notebook_path") or ti.get("path") or ""
        return REASON.format(p) if protected(p, cwd) else None
    if tool == "Bash":
        hits = bash_hits(str(ti.get("command") or ""), cwd)
        return REASON.format(", ".join(sorted(set(hits))[:3])) if hits else None
    return None


def main():
    if os.environ.get("DEVKIT_ALLOW_GATE_EDIT") == "1":
        return
    try:
        reason = judge(json.loads(sys.stdin.read() or "{}"))
    except Exception as e:   # noqa: BLE001 — never block unrelated work on a guard error, but say so
        sys.stderr.write(f"guard-review-tamper: skipped ({e.__class__.__name__}: {str(e)[:160]})\n")
        return
    if reason:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                                 "permissionDecisionReason": reason}}))


if __name__ == "__main__":
    main()
