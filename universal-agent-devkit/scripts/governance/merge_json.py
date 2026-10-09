#!/usr/bin/env python3
"""
merge_json.py — Additively merge a DevKit JSON template into a user's JSON file.
Usage: python3 merge_json.py <source_json> <target_json>

Rules (user data always wins):
  - dicts merge recursively; a key the user already has keeps the user's value
  - lists union; hook groups ({"matcher", "hooks": [...]}) are deduplicated by
    each hook's `command`, so re-running the installer never duplicates a hook
  - except inside `mcpServers`: a list the user already has there (`args`, a
    command array) is positional argv, not a set — it is kept exactly as the user
    wrote it. A union would append the template's items (`["-y", "pkg",
    "pkg@1.0.1"]`) and npx would run the package with a stray argument. The lists
    that must union are set-like: settings.json `permissions.allow/deny` (strings)
    and `hooks` (dicts) — see adapters/setup_claude.sh and setup_gemini.sh, the only
    callers, which merge exactly these two template shapes
  - an unparseable target (e.g. JSONC with comments) aborts with exit 1 and is
    never overwritten
  - when a merge changes an existing file whose `<stem>_old<ext>` backup is
    already taken by a different version, a timestamped `<stem>_old.<ts><ext>`
    backup is written first
"""
import json
import os
import re
import shutil
import sys
import tempfile
import time


def _matcher_set(group):
    m = group.get("matcher") or ""
    return None if m in ("", "*") else set(m.split("|"))  # None = matches every tool


def _overlap(a, b):
    return a is None or b is None or bool(a & b)


def _hook_key(hook):
    """Identity of a hook = the script PATH it runs, with quoting and the leading
    project-dir variable normalised away, so `"$DIR"/.claude/hooks/x.sh` and
    `bash "$DIR/.claude/hooks/x.sh"` (older template spelling) are the same hook and
    never installed twice — while a user's own `scripts/x.sh` that merely shares the
    file name is a different hook and is kept."""
    cmd = hook.get("command", "") if isinstance(hook, dict) else ""
    unquoted = cmd.replace('"', "").replace("'", "")
    m = re.search(r"(\S*[\w.-]+\.(?:sh|py|js|mjs))\b", unquoted)
    if not m:
        return cmd
    path = re.sub(r"^(?:\$\{[^}]*\}|\$\w+)", "", m.group(1))
    path = path.lstrip("/")
    while path.startswith("./"):
        path = path[2:]
    # .claude/hooks/X links to .agents/devkit/hooks/X: one DevKit hook, however it is wired
    # (all 3 real projects had proof_gate both ways on 2026-09-27 — every block showed twice).
    return re.sub(r"^(?:\.agents/devkit/hooks|\.claude/hooks)/", DEVKIT_HOOK, path)


DEVKIT_HOOK = "devkit-hook:"


def _rewire_through_claude_hooks(groups, devkit_keys):
    """A DevKit hook wired as .agents/devkit/hooks/X runs through .claude/hooks/X instead (the
    link the installer makes next to every DevKit hook). .agents/devkit is git-ignored, so a
    worktree the host creates (Grok, OfficeReader 2026-09-28) has no such path: the Stop hook
    died with exit 127 and the host skipped it — the proof gate never ran."""
    for g in groups:
        if not (isinstance(g, dict) and isinstance(g.get("hooks"), list)):
            continue
        for h in g["hooks"]:
            if isinstance(h, dict) and isinstance(h.get("command"), str) \
                    and _hook_key(h) in devkit_keys and ".agents/devkit/hooks/" in h["command"]:
                h["command"] = h["command"].replace(".agents/devkit/hooks/", ".claude/hooks/")


def _drop_twins(groups, devkit_keys):
    """A DevKit hook — one the source (DevKit template) wires — wired twice under overlapping
    matchers keeps its first wiring (the project's placement); a group only this emptied goes.
    The user's own hooks are never touched, even a script of theirs under .claude/hooks/ wired
    twice (review 2026-09-27)."""
    seen = []
    for g in groups:
        if not (isinstance(g, dict) and isinstance(g.get("hooks"), list)):
            continue
        m, keep = _matcher_set(g), []
        for h in g["hooks"]:
            k = _hook_key(h)
            if k in devkit_keys and any(k == sk and _overlap(m, sm) for sk, sm in seen):
                continue
            seen.append((k, m))
            keep.append(h)
        if len(keep) != len(g["hooks"]):
            g["hooks"] = keep
            g["_emptied"] = not keep
    groups[:] = [g for g in groups if not (isinstance(g, dict) and g.pop("_emptied", False))]


def _merge_list(source, target):
    """Union of lists. Hook groups: a hook is skipped only when the same script is
    already wired under an OVERLAPPING matcher (Edit|Write vs Edit|Write|NotebookEdit);
    the same script under a disjoint matcher (Edit vs Write) is a different hook."""
    for item in source:
        if isinstance(item, dict) and isinstance(item.get("hooks"), list):
            src_m = _matcher_set(item)
            present = {_hook_key(h) for t in target
                       if isinstance(t, dict) and isinstance(t.get("hooks"), list)
                       and _overlap(_matcher_set(t), src_m)
                       for h in t["hooks"]}
            # A DevKit hook already wired keeps the user's matcher and placement; its timeout
            # becomes the larger of the user's and the DevKit's current one — a re-init must
            # not leave an old, too short one (180 s vs 600 s for the test-source-set
            # compile), and a timeout the user raised stays.
            for h in item["hooks"]:
                if isinstance(h, dict) and "timeout" in h and _hook_key(h) in present:
                    for t in target:
                        if isinstance(t, dict) and isinstance(t.get("hooks"), list) and _overlap(_matcher_set(t), src_m):
                            for th in t["hooks"]:
                                if isinstance(th, dict) and _hook_key(th) == _hook_key(h):
                                    cur = th.get("timeout")
                                    if not isinstance(cur, (int, float)) or cur < h["timeout"]:
                                        th["timeout"] = h["timeout"]
            # A DevKit hook wired under a NARROWER overlapping matcher (Edit|Write, template now
            # Edit|Write|MultiEdit|NotebookEdit) never saw the new tools: add it for the missing
            # tools only, in their own group — the user's group stays as it is.
            for h in item["hooks"]:
                key = _hook_key(h)
                if key not in present or src_m is None:
                    continue
                cover = set()
                for t in target:
                    if isinstance(t, dict) and isinstance(t.get("hooks"), list) \
                            and any(_hook_key(th) == key for th in t["hooks"]):
                        m = _matcher_set(t)
                        cover = None if m is None or cover is None else cover | m
                missing = set() if cover is None else src_m - cover
                if missing:
                    _merge_list([{**item, "matcher": "|".join(sorted(missing)), "hooks": [h]}], target)
            # A DevKit hook still wired with the plain spelling older templates wrote
            # (`bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/X"`) takes the template's current
            # command, so a re-sync brings a changed wiring (2026-10-09: SessionStart says when
            # the hook files are missing instead of exiting 127). Any other command is the user's.
            for h in item["hooks"]:
                key = _hook_key(h)
                if not (isinstance(h, dict) and key.startswith(DEVKIT_HOOK) and key in present):
                    continue
                plain = 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/' + key[len(DEVKIT_HOOK):] + '"'
                for t in target:
                    for th in (t.get("hooks") if isinstance(t, dict) and isinstance(t.get("hooks"), list) else []):
                        if isinstance(th, dict) and th.get("command") == plain and h.get("command") != plain:
                            th["command"] = h["command"]
            new_hooks = [h for h in item["hooks"] if _hook_key(h) not in present]
            if not new_hooks:
                continue
            same = next((t for t in target if isinstance(t, dict)
                         and isinstance(t.get("hooks"), list)
                         and (t.get("matcher") or "") == (item.get("matcher") or "")), None)
            if same is not None:
                same["hooks"].extend(new_hooks)
            else:
                target.append({**item, "hooks": new_hooks})
        elif isinstance(item, dict) and isinstance(item.get("command"), str):
            if not any(isinstance(t, dict) and t.get("command") == item["command"] for t in target):
                target.append(item)
        elif item not in target:
            target.append(item)
    devkit_keys = {_hook_key(h) for i in source if isinstance(i, dict) and isinstance(i.get("hooks"), list)
                   for h in i["hooks"]}
    devkit_keys = {k for k in devkit_keys if k.startswith(DEVKIT_HOOK)}
    if devkit_keys and any(isinstance(t, dict) and isinstance(t.get("hooks"), list) for t in target):
        _rewire_through_claude_hooks(target, devkit_keys)
        _drop_twins(target, devkit_keys)


# Top-level keys whose lists are ordered values (argv), never sets: the user's wins.
KEEP_USER_LISTS_UNDER = ("mcpServers",)


def deep_merge(source, target, _path=()):
    for key, val in source.items():
        if key not in target:
            target[key] = val
        elif isinstance(val, dict) and isinstance(target[key], dict):
            deep_merge(val, target[key], _path + (key,))
        elif isinstance(val, list) and isinstance(target[key], list):
            if not (_path and _path[0] in KEEP_USER_LISTS_UNDER):
                _merge_list(val, target[key])
        # else: the user already set this key — keep their value
    return target


def _load(path, role):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError, UnicodeDecodeError) as e:
        sys.stderr.write(f"merge_json: cannot parse {role} {path}: {e}\n"
                         f"merge_json: {role} left untouched — fix it (JSON has no comments) and re-run.\n")
        sys.exit(1)
    if not isinstance(data, dict):
        sys.stderr.write(f"merge_json: {role} {path} is not a JSON object — left untouched.\n")
        sys.exit(1)
    return data


def _backup_if_needed(target_file, original_text):
    stem, ext = os.path.splitext(target_file)
    first = f"{stem}_old{ext}"
    if os.path.exists(first):
        with open(first, "r", encoding="utf-8") as f:
            if f.read() == original_text:
                return
        backup = f"{stem}_old.{time.strftime('%Y%m%d-%H%M%S')}{ext}"
    else:
        backup = first
    fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(original_text)
    shutil.copymode(target_file, backup)  # backup is exactly as private as the original


def main(argv):
    if len(argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    source_file, target_file = argv[1], argv[2]
    # A symlinked target (dotfile managers) is merged into the real file; replacing
    # the link with a regular file would silently fork the user's config.
    target_file = os.path.realpath(target_file)
    if not os.path.exists(source_file):
        sys.stderr.write(f"merge_json: source {source_file} not found — nothing merged.\n")
        return 1
    source_data = _load(source_file, "source")

    original_text = None
    target_data = {}
    if os.path.exists(target_file):
        target_data = _load(target_file, "target")  # exits 1 on unreadable / non-UTF-8 / invalid
        with open(target_file, "r", encoding="utf-8") as f:
            original_text = f.read()

    merged = deep_merge(source_data, target_data)
    new_text = json.dumps(merged, indent=2, ensure_ascii=False) + "\n"
    if original_text is not None:
        if json.loads(original_text) == merged:
            return 0
        _backup_if_needed(target_file, original_text)

    target_dir = os.path.dirname(os.path.abspath(target_file))
    try:
        os.makedirs(target_dir, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=target_dir, prefix=".merge_json.")
    except OSError as e:
        sys.stderr.write(f"merge_json: cannot write next to {target_file}: {e}\n")
        return 1
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(new_text)
    # mkstemp creates 0600 — keep the user's mode, or a normal 0644 for a new file
    if original_text is not None:
        shutil.copymode(target_file, tmp)
    else:
        os.chmod(tmp, 0o644)
    os.replace(tmp, target_file)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
