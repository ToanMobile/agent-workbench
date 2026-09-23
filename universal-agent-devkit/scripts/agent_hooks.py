#!/usr/bin/env python3
"""agent_hooks.py — register the DevKit gates with OpenAI Codex, Gemini CLI and Cursor.

Usage: agent_hooks.py install|uninstall <codex|gemini|cursor> <project_dir>

Each platform's hook config gets entries that run hooks/agent_bridge.sh from the
project's .agents/hooks/ (placed there by the adapter), which translates the
platform's hook protocol to the DevKit's Claude Code hooks:

  codex   .codex/hooks.json      SessionStart, UserPromptSubmit, PreToolUse(Bash), Stop
  gemini  .gemini/settings.json  SessionStart, BeforeAgent, BeforeTool(run_shell_command), AfterAgent
  cursor  .cursor/hooks.json     sessionStart, beforeShellExecution, stop

Only entries whose command runs agent_bridge.sh are DevKit-owned: install replaces
exactly those (idempotent) and uninstall removes exactly those; the project's own
hooks and every other setting stay. A file that does not parse as JSON (e.g. JSONC
with comments) is never overwritten — exit 1 with a message. Writes are atomic.
"""

import json
import os
import sys
import tempfile

BRIDGE = ".agents/hooks/agent_bridge.sh"
# Codex / Gemini run the command in a shell from the session's cwd: resolve the
# project root first so a session started in a subdirectory still finds the bridge.
ROOTED = 'bash "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/' + BRIDGE + '"'

# (kind, hook script, timeout seconds)
SESSION = ("session", "session_context.sh", 20)
PROMPT = ("prompt", "prompt_context.sh", 10)
GIT = ("shell", "block-dangerous-git.sh", 10)
HW = ("shell", "hardware_safety_gate.sh", 10)
STOP = ("stop", "regression_gate.sh", 1800)

PLATFORMS = {
    "codex": {"file": ".codex/hooks.json",
              "events": [("SessionStart", "", [SESSION]), ("UserPromptSubmit", "", [PROMPT]),
                         ("PreToolUse", "Bash", [GIT, HW]), ("Stop", "", [STOP])]},
    "gemini": {"file": ".gemini/settings.json",
               "events": [("SessionStart", None, [SESSION]), ("BeforeAgent", None, [PROMPT]),
                          ("BeforeTool", "run_shell_command", [GIT, HW]), ("AfterAgent", None, [STOP])]},
    "cursor": {"file": ".cursor/hooks.json",
               "events": [("sessionStart", None, [SESSION]), ("beforeShellExecution", None, [GIT, HW]),
                          ("stop", None, [STOP])]},
}


def command(platform, kind, hook):
    if platform == "cursor":  # Cursor runs project hooks from the project root
        return f"bash {BRIDGE} cursor {kind} {hook}"
    return f"{ROOTED} {platform} {kind} {hook}"


def is_ours(entry):
    return isinstance(entry, dict) and BRIDGE in str(entry.get("command", ""))


def strip(cfg, platform):
    """Remove every DevKit bridge entry; drop groups/events left empty."""
    hooks = cfg.get("hooks")
    if not isinstance(hooks, dict):
        return cfg
    for event in list(hooks):
        entries = hooks[event]
        if not isinstance(entries, list):
            continue
        kept = []
        for e in entries:
            if platform != "cursor" and isinstance(e, dict) and isinstance(e.get("hooks"), list):
                inner = [h for h in e["hooks"] if not is_ours(h)]
                if inner:
                    kept.append({**e, "hooks": inner})
            elif not is_ours(e):
                kept.append(e)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    return cfg


def add(cfg, platform):
    hooks = cfg.setdefault("hooks", {})
    for event, matcher, specs in PLATFORMS[platform]["events"]:
        if platform == "cursor":
            hooks.setdefault(event, []).extend(
                {"command": command(platform, k, h), "timeout": t} for k, h, t in specs)
            continue
        entry = {"type": "command"}
        group = {"hooks": [{**entry, "command": command(platform, k, h),
                            # Gemini timeouts are milliseconds, Codex seconds
                            "timeout": t * 1000 if platform == "gemini" else t} for k, h, t in specs]}
        if matcher is not None:
            group = {"matcher": matcher, **group}
        hooks.setdefault(event, []).append(group)
    if platform == "cursor":
        cfg.setdefault("version", 1)
    return cfg


def load(path):
    if not os.path.exists(path):
        return {}, False
    with open(path, encoding="utf-8") as f:
        data = json.load(f)  # ValueError → caller refuses to touch the file
    if not isinstance(data, dict):
        raise ValueError("top level is not a JSON object")
    return data, True


def write_atomic(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".agent_hooks.")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def install(platform, project):
    path = os.path.join(project, PLATFORMS[platform]["file"])
    cfg, _ = load(path)
    write_atomic(path, add(strip(cfg, platform), platform))
    return path


def uninstall(platform, project, apply=True):
    """Returns (path, action) with action None | "remove-file" | "strip"."""
    path = os.path.join(project, PLATFORMS[platform]["file"])
    cfg, existed = load(path)
    if not existed:
        return path, None
    before = json.dumps(cfg, sort_keys=True)
    cfg = strip(cfg, platform)
    if json.dumps(cfg, sort_keys=True) == before:
        return path, None
    leftover = {k: v for k, v in cfg.items() if not (k == "hooks" and not v) and not (platform == "cursor" and k == "version")}
    action = "strip" if leftover else "remove-file"
    if apply:
        if action == "remove-file":
            os.unlink(path)
            try:
                os.rmdir(os.path.dirname(path))
            except OSError:
                pass
        else:
            write_atomic(path, cfg)
    return path, action


def main(argv):
    if len(argv) != 4 or argv[1] not in ("install", "uninstall") or argv[2] not in PLATFORMS:
        sys.stderr.write(__doc__.split("\n\n")[1] + "\n")
        return 2
    action, platform, project = argv[1], argv[2], os.path.abspath(argv[3])
    try:
        if action == "install":
            print(f"  - {platform}: DevKit gates registered in {os.path.relpath(install(platform, project), project)}")
        else:
            path, done = uninstall(platform, project)
            if done:
                print(f"  - {platform}: DevKit gates removed from {os.path.relpath(path, project)}")
    except (OSError, ValueError) as e:
        sys.stderr.write(f"  ✖ {platform}: {PLATFORMS[platform]['file']} not changed — cannot read it as JSON ({e}). "
                         f"Add the DevKit hooks by hand (see hooks/agent_bridge.sh).\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
