#!/usr/bin/env python3
"""devkit_uninstall.py — remove what the DevKit installer put into a project.

Usage: devkit_uninstall.py <project_dir> [--apply]      (dry-run unless --apply)
       (normally called as `agent-kit uninstall [path] [--apply]`)

Only DevKit content is removed; anything that is (or has become) the user's stays:
  * symlinks that point into the DevKit (.agents/devkit, and the 1.2 root rules/ skills/
    commands/ AGENTS.md,
    .claude/{hooks,commands,agents}/*, .agents/skills/*, .agents/active-profile)
  * copy-mode files still identical to what the installer recorded in `.devkit-files`,
    and copy-mode directories still matching their `.devkit-copy` manifest
  * DevKit hooks merged into .claude/settings.json — only entries whose command runs a
    DevKit hook script under .claude/hooks/; the user's own hooks and settings stay
  * DevKit MCP servers in .mcp.json / mcp_config.json — only while their value is still
    identical to the DevKit template
  * the DevKit marker blocks in CLAUDE.md, AGENTS.md, GEMINI.md, Agent.md, CODEX.md,
    .cursorrules and .gitignore (a file left empty was created by the installer)
  * DESIGN.md / .agents/instincts.md still identical to the DevKit templates,
    .agents/active-profile.json, the generated .agents/context/ and an unmodified .agents/regression_matrix.active.json
  * the git pre-commit hook written by `agent-kit githooks install` (marker-checked)

A JSON file is backed up as `<stem>_old.uninstall-<timestamp><ext>` before it is
changed, and every write is atomic. *_old backups and .devkit_backups.log ledgers are
kept: run `agent-kit restore-old --apply` afterwards to put the user's originals back.
"""

import copy
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEVKIT = os.path.realpath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

from devkit_i18n import tr  # noqa: E402
from merge_json import _hook_key, deep_merge  # noqa: E402

MARKER = "universal-agent-devkit"
FILE_LEDGER = ".devkit-files"
DIR_MANIFEST = ".devkit-copy"


class Plan:
    def __init__(self, project, apply):
        self.project = project
        self.apply = apply
        self.removed = 0
        self.kept = []

    def rel(self, p):
        return os.path.relpath(p, self.project)

    def say(self, verb_vi, verb_en, path, extra=""):
        verb = tr(verb_vi, verb_en)
        print(f"  {verb:<9} {self.rel(path)}{extra}")

    def remove(self, path, what_vi="gỡ", what_en="remove"):
        if self.apply:
            if os.path.islink(path) or os.path.isfile(path):
                os.unlink(path)
            else:
                subprocess.run(["rm", "-rf", "--", path], check=True)
            self.say("đã gỡ", "removed", path)
        else:
            self.say(f"sẽ {what_vi}", f"would {what_en}", path)
        self.removed += 1

    def keep(self, path, why_vi, why_en):
        self.kept.append(path)
        self.say("GIỮ", "KEEP", path, " — " + tr(why_vi, why_en))


# ---------------------------------------------------------------- ownership tests

def link_is_devkit_owned(path):
    """Same rule as backup_conflict.sh: the link's own target lies inside the DevKit."""
    if not os.path.islink(path):
        return False
    t = os.readlink(path)
    if not os.path.isabs(t):
        t = os.path.join(os.path.dirname(path), t)
    d = os.path.realpath(os.path.dirname(t)) if os.path.exists(os.path.dirname(t)) else os.path.dirname(t)
    t = os.path.join(d, os.path.basename(t))
    return t == DEVKIT or t.startswith(DEVKIT + os.sep)


def sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def ledger_entries(directory):
    entries = {}
    try:
        with open(os.path.join(directory, FILE_LEDGER), encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                sha, sep, name = line.partition("  ")
                if sep:
                    entries[name] = sha  # the last record for a name wins
    except OSError:
        pass
    return entries


def is_recorded_devkit_file(path):
    if os.path.islink(path) or not os.path.isfile(path):
        return False
    want = ledger_entries(os.path.dirname(path)).get(os.path.basename(path))
    return bool(want) and want == sha1(path)


def forget_recorded(path, apply):
    if not apply:
        return
    directory = os.path.dirname(path)
    entries = ledger_entries(directory)
    if os.path.basename(path) not in entries:
        return
    del entries[os.path.basename(path)]
    ledger = os.path.join(directory, FILE_LEDGER)
    if entries:
        write_atomic(ledger, "".join(f"{s}  {n}\n" for n, s in entries.items()))
    else:
        os.unlink(ledger)


def is_unmodified_devkit_copy(path):
    if os.path.islink(path) or not os.path.isdir(path) or not os.path.isfile(os.path.join(path, DIR_MANIFEST)):
        return False
    r = subprocess.run(
        ["bash", "-c", 'source "$1/scripts/backup_conflict.sh" >/dev/null 2>&1; is_unmodified_devkit_copy "$2"',
         "_", DEVKIT, path], capture_output=True)
    return r.returncode == 0


def write_atomic(path, text):
    directory = os.path.dirname(os.path.abspath(path)) or "."
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".devkit-uninstall.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, (os.stat(path).st_mode & 0o7777) if os.path.exists(path) else 0o644)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def backup_before_edit(path):
    stem, ext = os.path.splitext(path)
    dst = f"{stem}_old.uninstall-{time.strftime('%Y%m%d-%H%M%S')}{ext}"
    n = 1
    while os.path.exists(dst):
        n += 1
        dst = f"{stem}_old.uninstall-{time.strftime('%Y%m%d-%H%M%S')}-{n}{ext}"
    with open(path, "rb") as src, open(dst, "wb") as out:
        out.write(src.read())
    return dst


# ---------------------------------------------------------------- DevKit items

def devkit_item(plan, path, label_vi="mục DevKit", label_en="DevKit item"):
    """Remove one installed item if it is still the DevKit's; report it when modified."""
    if not (os.path.exists(path) or os.path.islink(path)):
        return
    if os.path.islink(path):
        if link_is_devkit_owned(path):
            plan.remove(path)
        # a link elsewhere is the user's (dotfile manager) — silently theirs
        return
    if os.path.isdir(path):
        if is_unmodified_devkit_copy(path):
            plan.remove(path)
        elif os.path.isfile(os.path.join(path, DIR_MANIFEST)):
            plan.keep(path, "bản copy DevKit đã bị sửa", "DevKit copy was edited")
        return
    if is_recorded_devkit_file(path):
        plan.remove(path)
        forget_recorded(path, plan.apply)
    elif os.path.basename(path) in ledger_entries(os.path.dirname(path)):
        plan.keep(path, "file DevKit đã bị sửa", "DevKit file was edited")


def devkit_names(*subdirs):
    names = set()
    for sub in subdirs:
        d = os.path.join(DEVKIT, sub)
        if os.path.isdir(d):
            names.update(os.listdir(d))
    return names


def profile_hook_names():
    names = set()
    pdir = os.path.join(DEVKIT, "profiles")
    for p in sorted(os.listdir(pdir)) if os.path.isdir(pdir) else []:
        h = os.path.join(pdir, p, "hooks")
        if os.path.isdir(h):
            names.update(n for n in os.listdir(h) if os.path.isfile(os.path.join(h, n)))
    return names


# ---------------------------------------------------------------- JSON configs

def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def pre_install_backup(path):
    """merge_json.py saved the pre-install file as <stem>_old<ext> the first time it changed it."""
    stem, ext = os.path.splitext(path)  # same naming as merge_json._backup_if_needed
    old = f"{stem}_old{ext}"
    return old if os.path.isfile(old) else None


def settings_template():
    base = json.load(open(os.path.join(DEVKIT, "templates", "claude_settings.json"), encoding="utf-8"))
    plugin = json.load(open(os.path.join(DEVKIT, "hooks", "hooks.json"), encoding="utf-8"))
    hooks = json.dumps(plugin.get("hooks", plugin))
    hooks = hooks.replace("${CLAUDE_PLUGIN_ROOT}/hooks/", "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/")
    base["hooks"] = json.loads(hooks)
    return base


def strip_template(cur, tmpl, old):
    """Remove from `cur` what the template added: keys/list items absent from the
    pre-install `old` (None = no backup, the key was not there before)."""
    for key, tval in tmpl.items():
        if key not in cur:
            continue
        oval = old.get(key) if isinstance(old, dict) else None
        had = isinstance(old, dict) and key in old
        cval = cur[key]
        if isinstance(tval, dict) and isinstance(cval, dict):
            strip_template(cval, tval, oval if isinstance(oval, dict) else None)
            if not cval and not had:
                del cur[key]
        elif isinstance(tval, list) and isinstance(cval, list):
            keep_items = oval if isinstance(oval, list) else []
            cur[key] = [i for i in cval if i not in tval or i in keep_items]
            if not cur[key] and not had:
                del cur[key]
        elif not had and cval == tval:
            del cur[key]


def strip_devkit_hooks(cur, hook_names):
    hooks = cur.get("hooks")
    if not isinstance(hooks, dict):
        return
    wanted = {f".claude/hooks/{n}" for n in hook_names}
    for event in list(hooks):
        groups = hooks[event]
        if not isinstance(groups, list):
            continue
        new_groups = []
        for g in groups:
            if isinstance(g, dict) and isinstance(g.get("hooks"), list):
                g = dict(g)
                g["hooks"] = [h for h in g["hooks"] if _hook_key(h) not in wanted]
                if not g["hooks"]:
                    continue
            new_groups.append(g)
        if new_groups:
            hooks[event] = new_groups
        else:
            del hooks[event]


def json_config(plan, path, template, hook_names=None):
    if not os.path.isfile(path) or os.path.islink(path) and link_is_devkit_owned(path):
        return
    cur = load_json(path)
    if not isinstance(cur, dict):
        plan.keep(path, "không đọc được JSON — không động vào", "unparseable JSON — left untouched")
        return
    old_path = pre_install_backup(path)
    old = load_json(old_path) if old_path else None

    # Untouched since install: current == merge(template, pre-install) → put the original back.
    expected = deep_merge(copy.deepcopy(template), copy.deepcopy(old) if isinstance(old, dict) else {})
    if cur == expected:
        if isinstance(old, dict):
            new_text = open(old_path, encoding="utf-8").read()
        else:
            new_text = None  # the installer created the file
    else:
        new = copy.deepcopy(cur)
        if hook_names:
            strip_devkit_hooks(new, hook_names)
        tmpl = {k: v for k, v in template.items() if k != "hooks"} if hook_names else template
        if "mcpServers" in tmpl and isinstance(new.get("mcpServers"), dict):
            old_srv = old.get("mcpServers", {}) if isinstance(old, dict) else {}
            for name, val in tmpl["mcpServers"].items():
                if new["mcpServers"].get(name) == val and old_srv.get(name) != val:
                    del new["mcpServers"][name]
                elif name in new["mcpServers"] and name not in old_srv:
                    plan.keep(path, f"MCP `{name}` đã bị sửa — giữ nguyên", f"MCP `{name}` was edited — kept")
            if not new["mcpServers"] and not (isinstance(old, dict) and "mcpServers" in old):
                del new["mcpServers"]
            tmpl = {k: v for k, v in tmpl.items() if k != "mcpServers"}
        strip_template(new, tmpl, old)
        if new == cur:
            return
        if isinstance(old, dict) and new == old:
            new_text = open(old_path, encoding="utf-8").read()
        elif not new and old is None:
            new_text = None
        else:
            new_text = json.dumps(new, indent=2, ensure_ascii=False) + "\n"

    if new_text is None:
        if plan.apply:
            bak = backup_before_edit(path)
            os.unlink(path)
            plan.say("đã gỡ", "removed", path, f" ({tr('bản lưu', 'backup')}: {plan.rel(bak)})")
        else:
            plan.say("sẽ gỡ", "would remove", path)
    else:
        if plan.apply:
            bak = backup_before_edit(path)
            write_atomic(path, new_text)
            plan.say("đã sửa", "cleaned", path, f" ({tr('bản lưu', 'backup')}: {plan.rel(bak)})")
        else:
            plan.say("sẽ sửa", "would clean", path)
    plan.removed += 1


# ---------------------------------------------------------------- marker blocks

def strip_block(plan, path, style="html"):
    if not os.path.exists(path):
        return
    if os.path.islink(path):
        if link_is_devkit_owned(path):
            return  # handled as a DevKit item
        path = os.path.realpath(path)
    if not os.path.isfile(path):
        return
    start, end = ((f"# {MARKER}:start", f"# {MARKER}:end") if style == "hash"
                  else (f"<!-- {MARKER}:start -->", f"<!-- {MARKER}:end -->"))
    text = open(path, encoding="utf-8").read()
    i = text.find(start)
    j = text.find(end, i + len(start)) if i >= 0 else -1
    if i < 0 or j < 0:
        return
    pre, post = text[:i].rstrip("\n"), text[j + len(end):].lstrip("\n")
    new = pre
    if post.strip():
        new = (pre + "\n\n" + post) if pre else post
    elif pre:
        new = pre + "\n"
    if not new.strip() or (os.path.basename(path) == "AGENTS.md"
                           and new.strip() == f"# {os.path.basename(os.path.dirname(os.path.abspath(path)))}"):
        plan.remove(path)               # empty, or the heading-only AGENTS.md the installer wrote
        return
    if plan.apply:
        write_atomic(path, new)
        plan.say("đã sửa", "cleaned", path, " (" + tr("gỡ khối DevKit", "DevKit block removed") + ")")
    else:
        plan.say("sẽ sửa", "would clean", path, " (" + tr("gỡ khối DevKit", "DevKit block") + ")")
    plan.removed += 1


FOLD_RE = re.compile(r"<!-- moved from (CLAUDE\.md|GEMINI\.md|Agent\.md) on [0-9-]+ \(AGENTS\.md is the only instruction file\) -->\n"
                     r"(.*?)\n\n(?=<!-- moved from |<!-- " + re.escape(MARKER) + r":start -->|\Z)", re.S)


def unfold_agent_files(plan, project):
    """Put CLAUDE.md / GEMINI.md / Agent.md back from what the installer folded into AGENTS.md:
    the <name>_old.md backup when there is one (the exact original), else the folded text.
    A name that exists again is left alone (the user re-created it)."""
    agents = os.path.join(project, "AGENTS.md")
    if not os.path.isfile(agents) or os.path.islink(agents):
        return
    text = open(agents, encoding="utf-8").read()
    pieces = list(FOLD_RE.finditer(text))
    if not pieces:
        return
    new = text
    for m in pieces:
        name, own = m.group(1), m.group(2)
        dst = os.path.join(project, name)
        if os.path.exists(dst) or os.path.islink(dst):
            plan.keep(dst, "đã có lại — không khôi phục từ AGENTS.md", "exists again — not restored from AGENTS.md")
            continue
        backup = os.path.join(project, name[:-3] + "_old.md")
        body = open(backup, encoding="utf-8").read() if os.path.isfile(backup) else own + "\n"
        body = re.sub(r"<!-- " + re.escape(MARKER) + r":start -->.*?<!-- " + re.escape(MARKER) + r":end -->\n?", "", body, flags=re.S)
        if plan.apply:
            write_atomic(dst, body)
        plan.say("đã khôi phục" if plan.apply else "sẽ khôi phục", "restored" if plan.apply else "would restore", dst,
                 tr(" (từ phần đã gộp vào AGENTS.md)", " (from its part folded into AGENTS.md)"))
        plan.removed += 1
        new = new.replace(m.group(0), "", 1)
    if plan.apply and new != text:
        write_atomic(agents, new)


def same_bytes(a, b):
    try:
        with open(a, "rb") as x, open(b, "rb") as y:
            return x.read() == y.read()
    except OSError:
        return False


def remove_if_empty_dir(plan, path):
    if os.path.isdir(path) and not os.path.islink(path):
        leftover = [n for n in os.listdir(path) if n != FILE_LEDGER]
        if not leftover:
            if plan.apply:
                if os.path.exists(os.path.join(path, FILE_LEDGER)):
                    os.unlink(os.path.join(path, FILE_LEDGER))
                os.rmdir(path)
            # empty directories are not worth a line of output


# ---------------------------------------------------------------- main

def main(argv):
    args = [a for a in argv[1:] if a != "--apply"]
    apply = "--apply" in argv[1:]
    unknown = [a for a in args if a.startswith("-")]
    if unknown or len(args) > 1:
        sys.stderr.write(__doc__.split("\n\n")[0] + "\n")
        return 2
    project = os.path.realpath(args[0] if args else os.getcwd())
    if not os.path.isdir(project):
        sys.stderr.write(f"uninstall: {tr('không có thư mục', 'no such directory')}: {project}\n")
        return 2
    if project == DEVKIT:
        sys.stderr.write(tr("uninstall: không gỡ chính DevKit.\n", "uninstall: refusing to uninstall the DevKit from itself.\n"))
        return 2

    plan = Plan(project, apply)
    print(f"uninstall: {project} ({'apply' if apply else tr('chạy thử — thêm --apply để gỡ thật', 'dry-run — add --apply to remove')})")

    # 1. JSON configs first (they name the hooks that are about to disappear).
    hook_names = devkit_names("hooks") | profile_hook_names()
    settings = os.path.join(project, ".claude", "settings.json")
    json_config(plan, settings, settings_template(), hook_names)
    for tmpl_rel, target_rel in (("mcp/.mcp.json", ".mcp.json"), ("mcp/mcp_config.json", "mcp_config.json")):
        tmpl = load_json(os.path.join(DEVKIT, tmpl_rel))
        if isinstance(tmpl, dict):
            json_config(plan, os.path.join(project, target_rel), tmpl)

    # 2. Marker blocks. First the agent files the installer folded into AGENTS.md
    #    (fold_agent_file.py): each goes back to its own file, its piece leaves AGENTS.md.
    unfold_agent_files(plan, project)
    for name in ("CLAUDE.md", "AGENTS.md", "GEMINI.md", "Agent.md", "CODEX.md", ".cursorrules"):
        strip_block(plan, os.path.join(project, name))
    strip_block(plan, os.path.join(project, ".gitignore"), style="hash")
    # The always-applied Cursor rule setup_cursor.sh writes: its block goes; a file left
    # with only the DevKit's own front matter goes too.
    mdc = os.path.join(project, ".cursor", "rules", "universal-agent-devkit.mdc")
    if os.path.isfile(mdc) and not os.path.islink(mdc):
        text = open(mdc, encoding="utf-8").read()
        i, j = text.find(f"<!-- {MARKER}:start -->"), text.find(f"<!-- {MARKER}:end -->")
        rest = (text[:i] + text[j + len(f"<!-- {MARKER}:end -->"):]) if 0 <= i < j else text
        if re.fullmatch(r"\s*---\ndescription: Universal Agent DevKit[^\n]*\nalwaysApply: true\n---\s*", rest):
            plan.remove(mdc)
        else:
            strip_block(plan, mdc)
    # Gemini: the DevKit folder added to context.includeDirectories (symlink mode) and
    # AGENTS.md as its context file (context.fileName).
    gset = os.path.join(project, ".gemini", "settings.json")
    gdata = load_json(gset)
    names = (gdata or {}).get("context", {}).get("fileName") if isinstance(gdata, dict) else None
    if names == ["AGENTS.md"] or names == "AGENTS.md":
        del gdata["context"]["fileName"]
        if not gdata["context"]:
            del gdata["context"]
        if plan.apply:
            if gdata:
                write_atomic(gset, json.dumps(gdata, indent=2, ensure_ascii=False) + "\n")
            else:
                os.unlink(gset)
        plan.say("đã sửa" if plan.apply else "sẽ sửa", "cleaned" if plan.apply else "would clean", gset,
                 tr(" (bỏ context.fileName = AGENTS.md)", " (context.fileName = AGENTS.md removed)"))
        plan.removed += 1
    dirs = (gdata or {}).get("context", {}).get("includeDirectories") if isinstance(gdata, dict) else None
    if isinstance(dirs, list) and any(os.path.realpath(str(d)) == os.path.realpath(DEVKIT) for d in dirs):
        dirs[:] = [d for d in dirs if os.path.realpath(str(d)) != os.path.realpath(DEVKIT)]
        if not dirs:
            del gdata["context"]["includeDirectories"]
            if not gdata["context"]:
                del gdata["context"]
        if plan.apply:
            if gdata:
                write_atomic(gset, json.dumps(gdata, indent=2, ensure_ascii=False) + "\n")
            else:
                os.unlink(gset)
        plan.say("đã sửa" if plan.apply else "sẽ sửa", "cleaned" if plan.apply else "would clean", gset,
                 tr(" (bỏ thư mục DevKit khỏi includeDirectories)", " (DevKit folder removed from includeDirectories)"))
        plan.removed += 1

    # Claude Code auto-memory pointed into the project by claude_memory.py: the setting
    # goes (a settings.local.json left empty goes too); the notes stay — they are data.
    slocal = os.path.join(project, ".claude", "settings.local.json")
    sdata = load_json(slocal)
    ours = os.path.join(os.path.realpath(project), ".agents", "local", "memory", "claude-auto")
    if isinstance(sdata, dict) and isinstance(sdata.get("autoMemoryDirectory"), str) \
            and os.path.realpath(sdata["autoMemoryDirectory"]) == os.path.realpath(ours):
        del sdata["autoMemoryDirectory"]
        if plan.apply:
            if sdata:
                write_atomic(slocal, json.dumps(sdata, indent=2, ensure_ascii=False) + "\n")
            else:
                os.unlink(slocal)
        plan.say("đã sửa" if plan.apply else "sẽ sửa", "cleaned" if plan.apply else "would clean", slocal,
                 tr(" (bỏ autoMemoryDirectory)", " (autoMemoryDirectory removed)"))
        plan.removed += 1

    # A matrix generated from the project's test runner is recognised by regenerating it,
    # which reads the active profile — decide now, before step 3 removes that link.
    import matrix_detect  # noqa: E402,PLC0415 - sibling module in scripts/
    generated_matrices = set()
    for rel_path in (".agents/regression_matrix.active.json", "templates/regression_matrix.active.json"):
        p = os.path.join(project, rel_path)
        if os.path.isfile(p) and not os.path.islink(p):
            with open(p, "rb") as f:
                if matrix_detect.is_generated_unchanged(project, f.read()):
                    generated_matrices.add(p)

    # 3. Items placed by the installer / adapters / agent-config.
    for name in ("rules", "skills", "commands", "AGENTS.md"):
        devkit_item(plan, os.path.join(project, name))
    # A root rules/ skills/ commands/ that is the project's source code: the installer
    # placed DevKit items inside it one by one — remove those, keep the project's files.
    for name in ("rules", "skills", "commands"):
        d = os.path.join(project, name)
        if os.path.isdir(d) and not os.path.islink(d) and not os.path.isfile(os.path.join(d, DIR_MANIFEST)):
            for n in sorted(devkit_names(name)):
                devkit_item(plan, os.path.join(d, n))
    for sub, names in ((".claude/hooks", hook_names),
                       (".claude/commands", devkit_names("commands")),
                       (".claude/agents", devkit_names("agents")),
                       (".agents/skills", devkit_names("skills")),
                       (".agents/hooks", devkit_names("hooks"))):
        d = os.path.join(project, sub)
        if os.path.isdir(d) and not os.path.islink(d):
            for n in sorted(names):
                devkit_item(plan, os.path.join(d, n))
        elif os.path.islink(d) and link_is_devkit_owned(d):
            plan.remove(d)
    devkit_item(plan, os.path.join(project, ".agents", "active-profile"))
    devkit_item(plan, os.path.join(project, ".agents", "devkit"))               # the DevKit link (symlink mode)
    for n in ("AGENTS.md", "rules", "bin"):                                      # copy mode; 1.2: AGENTS.md link
        devkit_item(plan, os.path.join(project, ".agents", "devkit", n))
    ctx = os.path.join(project, ".agents", "context")                           # generated by context_sync.py
    if os.path.isdir(ctx) and not os.path.islink(ctx):
        plan.remove(ctx)
    side = os.path.join(project, ".agents", "regression_matrix.generated.json")  # comparison copy only
    if os.path.isfile(side) and not os.path.islink(side):
        plan.remove(side)

    # 4. Files created from DevKit templates / by agent-config, while still unmodified.
    pdir = os.path.join(DEVKIT, "profiles")
    designs = ["templates/DESIGN.md"] + [os.path.join("profiles", d, "DESIGN.md") for d in sorted(os.listdir(pdir))]
    for rel_path, tmpls in (("DESIGN.md", designs),   # the template or a profile's copy
                            (".agents/instincts.md", ["templates/instincts.template.md"])):
        p = os.path.join(project, rel_path)
        if os.path.isfile(p) and not os.path.islink(p):
            if any(os.path.isfile(os.path.join(DEVKIT, t)) and same_bytes(p, os.path.join(DEVKIT, t)) for t in tmpls):
                plan.remove(p)
    known = [os.path.join(DEVKIT, "templates", "regression_matrix.json")]
    pdir = os.path.join(DEVKIT, "profiles")
    known += [os.path.join(pdir, p, "regression_matrix.json") for p in sorted(os.listdir(pdir))]
    for rel_path in (".agents/regression_matrix.active.json", "templates/regression_matrix.active.json"):
        p = os.path.join(project, rel_path)
        if os.path.islink(p) and link_is_devkit_owned(p):
            plan.remove(p)
        elif os.path.isfile(p):
            if p in generated_matrices or any(same_bytes(p, k) for k in known if os.path.isfile(k)):
                plan.remove(p)
            else:
                plan.keep(p, "ma trận đã bị sửa", "matrix was edited")
    for ap in (os.path.join(project, ".agents", "active-profile.json"),
               os.path.join(project, ".active-profile.json")):          # before DevKit 1.3
        data = load_json(ap)
        if isinstance(data, dict) and os.path.isdir(os.path.join(pdir, str(data.get("profile", "")))):
            plan.remove(ap)

    # 4a. DevKit gates registered for Codex / Gemini CLI / Cursor (agent_hooks.py):
    #     only entries running agent_bridge.sh; a config left with nothing else is removed.
    import agent_hooks  # noqa: E402 - sibling module in scripts/
    for platform in sorted(agent_hooks.PLATFORMS):
        try:
            path, action = agent_hooks.uninstall(platform, project, apply=apply)
        except (OSError, ValueError) as e:
            plan.keep(os.path.join(project, agent_hooks.PLATFORMS[platform]["file"]),
                      f"không đọc được JSON ({e})", f"cannot read as JSON ({e})")
            continue
        if action == "remove-file":
            plan.say("đã gỡ" if apply else "sẽ gỡ", "removed" if apply else "would remove", path)
            plan.removed += 1
        elif action == "strip":
            plan.say("đã sửa" if apply else "sẽ sửa", "cleaned" if apply else "would clean", path,
                     tr(" (bỏ hook DevKit)", " (DevKit hooks removed)"))
            plan.removed += 1

    # 4b. The git pre-commit stub from `agent-kit githooks install` (marked; a project's
    #     own hook never carries the marker and is left alone).
    res = subprocess.run(["git", "-C", project, "rev-parse", "--path-format=absolute", "--git-path",
                          "hooks/pre-commit"], capture_output=True, text=True)
    hook = res.stdout.strip() if res.returncode == 0 else ""
    if hook and os.path.isfile(hook):
        try:
            with open(hook, encoding="utf-8", errors="replace") as f:
                if f"{MARKER}:githook" in f.read():
                    plan.remove(hook)
        except OSError:
            pass

    # 5. Directories the installer created and that are now empty.
    if apply:
        for sub in (".claude/hooks", ".claude/commands", ".claude/agents", ".claude",
                    ".agents/skills", ".agents/hooks", ".agents/devkit", ".agents", "templates",
                    ".cursor/rules", ".cursor", ".gemini"):
            remove_if_empty_dir(plan, os.path.join(project, sub))

    verb = tr("đã gỡ/sửa", "removed/cleaned") if apply else tr("sẽ gỡ/sửa", "would remove/clean")
    print(f"uninstall: {plan.removed} {verb}, {len(plan.kept)} {tr('giữ lại', 'kept')}")
    print("  → " + tr("Chạy `agent-kit restore-old --apply` để đưa các bản gốc *_old của bạn về chỗ cũ.",
                      "Run `agent-kit restore-old --apply` to put your original *_old backups back."))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
