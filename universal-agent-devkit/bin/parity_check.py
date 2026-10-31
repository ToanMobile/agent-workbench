#!/usr/bin/env python3
"""parity_check.py — repo đã cài DevKit có còn giống kit không (#773). Chỉ đọc, trừ --fix. Chỉ dùng stdlib.

    parity_check.py [repo] [--fix]          (agent-kit parity [repo] [--fix]; repo mặc định: gốc git của thư mục hiện tại)

Mỗi chỗ lệch in một dòng `<loại>: <đường dẫn> — <chi tiết>`, dòng cuối là tổng. Thoát 0 khi khớp kit, 1 khi còn lệch, 2 khi dùng sai.
  forbidden-flag     verify_commands của .claude/super-board/configs/*.json còn --full / --force-full / --auto-approve-tests
                     (#741/#764: --full chỉ chạy ở gate-full đêm; --auto-approve-tests không còn duyệt test)
  broken-link        symlink dưới .agents .claude .gemini .githooks .codex .cursor (hoặc ở gốc repo) không trỏ tới đâu
  foreign-kit-link   symlink trỏ vào một thư mục universal-agent-devkit khác bản kit đang chạy (worktree, bản sao cũ)
  copied-hook        cài symlink mà .claude/hooks/<tên> là file thường trùng tên hook kit: kit cập nhật không tới được
  hook-missing       hook kit (hooks/hooks.json) chưa đăng ký trong .claude/settings.json
  hook-dangling      .claude/settings.json đăng ký .claude/hooks/<tên> mà file không có
  super-board-drift  bản sao super-board khác bản nguồn (.claude/bin/super-board-drift.py của repo chứa kit, #368)
--fix chỉ sửa forbidden-flag: bỏ cờ khỏi chuỗi lệnh, giữ nguyên phần còn lại của file. Chỗ lệch khác cần `agent-kit init` hoặc sửa ở repo.
"""
import json
import os
import re
import subprocess
import sys

KIT = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
FORBIDDEN = ("full", "force-full", "auto-approve-tests")
FLAG_RE = re.compile(r"(?<![\w-])--(" + "|".join(re.escape(f) for f in FORBIDDEN) + r")(?![\w-])")
DROP_RE = re.compile(r"[ \t]+--(" + "|".join(re.escape(f) for f in FORBIDDEN) + r")(?![\w-])")
LINK_DIRS = (".agents", ".claude", ".gemini", ".githooks", ".codex", ".cursor")
SKIP_DIRS = {".git", "node_modules", "__pycache__", "worktrees", "Library", "build"}
HOOK_REF_RE = re.compile(r"\.claude/hooks/([A-Za-z0-9_.-]+)")


def git_root(path):
    r = subprocess.run(["git", "-C", path, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def under(path, root):
    return path == root or path.startswith(root + os.sep)


def configs(repo):
    d = os.path.join(repo, ".claude", "super-board", "configs")
    return sorted(os.path.join(d, n) for n in os.listdir(d) if n.endswith(".json")) if os.path.isdir(d) else []


def check_flags(repo, fix):
    out, fixed = [], []
    for p in configs(repo):
        cfg = load_json(p)
        cmds = cfg.get("verify_commands") if isinstance(cfg, dict) else None
        if not isinstance(cmds, list):
            continue
        bad = [c for c in cmds if isinstance(c, str) and FLAG_RE.search(c)]
        if not bad:
            continue
        rel = os.path.relpath(p, repo)
        if fix and fix_config(p, cfg, cmds):
            fixed.append(f"fixed: {rel} — removed " + ", ".join(sorted({"--" + m for c in bad for m in FLAG_RE.findall(c)})))
            continue
        for c in bad:
            flags = ", ".join("--" + m for m in FLAG_RE.findall(c))
            out.append(f"forbidden-flag: {rel} — verify_commands has {flags}: {c}")
    return out, fixed


def fix_config(path, cfg, cmds):
    """Thay đúng chuỗi lệnh trong văn bản gốc (diff chỉ một dòng); không tìm được chuỗi đã mã hoá thì ghi lại cả file. Đọc lại phải ra
    đúng danh sách mới, sai thì không ghi gì."""
    new = [DROP_RE.sub("", c) if isinstance(c, str) else c for c in cmds]
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    text = raw
    for old, cur in zip(cmds, new):
        if old == cur:
            continue
        for ascii_only in (False, True):
            enc = json.dumps(old, ensure_ascii=ascii_only)
            if enc in text:
                text = text.replace(enc, json.dumps(cur, ensure_ascii=ascii_only))
                break
        else:
            text = None
            break
    if text is None:
        cfg = dict(cfg, verify_commands=new)
        text = json.dumps(cfg, indent=2, ensure_ascii=False) + "\n"
    try:
        ok = json.loads(text).get("verify_commands") == new
    except ValueError:
        ok = False
    if not ok:
        return False
    tmp = path + ".parity.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)
    return True


def walk_links(repo):
    """Symlink ở gốc repo và dưới LINK_DIRS (sâu tối đa 4); không đi vào thư mục là link (.agents/devkit là cả kit)."""
    found = [os.path.join(repo, n) for n in sorted(os.listdir(repo)) if os.path.islink(os.path.join(repo, n))]
    for top in LINK_DIRS:
        base = os.path.join(repo, top)
        if os.path.islink(base) or not os.path.isdir(base):
            continue
        for dirpath, dirs, names in os.walk(base):
            depth = os.path.relpath(dirpath, base).count(os.sep)
            keep = []
            for d in sorted(dirs):
                full = os.path.join(dirpath, d)
                if os.path.islink(full):
                    found.append(full)
                elif d not in SKIP_DIRS and depth < 3:
                    keep.append(d)
            dirs[:] = keep
            found += [os.path.join(dirpath, n) for n in sorted(names) if os.path.islink(os.path.join(dirpath, n))]
    return found


def check_links(repo):
    out = []
    for p in walk_links(repo):
        rel = os.path.relpath(p, repo)
        if not os.path.exists(p):
            out.append(f"broken-link: {rel} — points to {os.readlink(p)}, which does not exist")
            continue
        real = os.path.realpath(p)
        if "universal-agent-devkit" in real.split(os.sep) and not under(real, KIT):
            out.append(f"foreign-kit-link: {rel} — points into {real}, not the kit {KIT}")
    return out


def symlink_install(repo):
    return os.path.islink(os.path.join(repo, ".agents", "devkit"))


def check_copied_hooks(repo):
    hooks = os.path.join(repo, ".claude", "hooks")
    if not symlink_install(repo) or not os.path.isdir(hooks):
        return []
    out = []
    for name in sorted(os.listdir(hooks)):
        p, kit_hook = os.path.join(hooks, name), os.path.join(KIT, "hooks", name)
        if os.path.isfile(p) and not os.path.islink(p) and os.path.isfile(kit_hook):
            with open(p, "rb") as a, open(kit_hook, "rb") as b:
                same = a.read() == b.read()
            out.append(f"copied-hook: .claude/hooks/{name} — a regular file, not a link to the kit"
                       + ("" if same else " (content differs from the kit)"))
    return out


def flat_hooks(hooks):
    rows = set()
    for event, entries in (hooks or {}).items():
        for e in entries if isinstance(entries, list) else []:
            for h in e.get("hooks", []) if isinstance(e, dict) else []:
                if isinstance(h, dict) and h.get("command"):
                    rows.add((event, e.get("matcher", "") or "", h["command"]))
    return rows


def check_settings(repo):
    path = os.path.join(repo, ".claude", "settings.json")
    if not os.path.isfile(path):
        return []
    settings = load_json(path)
    if not isinstance(settings, dict):
        return ["hook-missing: .claude/settings.json — not valid JSON, no DevKit hook can run"]
    plugin = load_json(os.path.join(KIT, "hooks", "hooks.json")) or {}
    # Cùng phép thay đường dẫn như adapters/setup_claude.sh khi sinh settings.json từ hooks.json
    kit_hooks = json.loads(json.dumps(plugin.get("hooks", plugin)).replace(
        "${CLAUDE_PLUGIN_ROOT}/hooks/", "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/"))
    have = flat_hooks(settings.get("hooks"))
    out = [f"hook-missing: .claude/settings.json — {ev}{' ' + m if m else ''}: {cmd}"
           for ev, m, cmd in sorted(flat_hooks(kit_hooks) - have)]
    for ev, m, cmd in sorted(have):
        for name in HOOK_REF_RE.findall(cmd):
            if not os.path.exists(os.path.join(repo, ".claude", "hooks", name)):
                out.append(f"hook-dangling: .claude/settings.json — {ev}{' ' + m if m else ''} runs .claude/hooks/{name}, which does not exist")
    return out


def check_drift(repo):
    source = os.path.dirname(KIT)
    script = os.path.join(source, ".claude", "bin", "super-board-drift.py")
    if not configs(repo) or not os.path.isfile(script) or os.path.realpath(repo) == os.path.realpath(source):
        return []
    try:
        r = subprocess.run([sys.executable, script, "--source", source, "--target", repo],
                           capture_output=True, text=True, timeout=60)
        res = json.loads(r.stdout)["targets"][repo]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as exc:
        return [f"super-board-drift: .claude — drift check could not run ({type(exc).__name__})"]
    return ([f"super-board-drift: {p} — missing (the kit's super-board has it)" for p in res.get("missing", [])]
            + [f"super-board-drift: {p} — differs from the kit's copy" for p in res.get("changed", [])])


def main(argv):
    args = [a for a in argv if not a.startswith("-")]
    opts = [a for a in argv if a.startswith("-")]
    if [o for o in opts if o not in ("--fix",)] or len(args) > 1:
        print("usage: parity_check.py [repo] [--fix]", file=sys.stderr)
        return 2
    repo = git_root(args[0] if args else os.getcwd()) or (os.path.abspath(args[0]) if args else None)
    if not repo or not os.path.isdir(repo):
        print(f"parity: {args[0] if args else os.getcwd()} is not a directory", file=sys.stderr)
        return 2
    if os.path.realpath(repo) == KIT:
        print("parity: this is the kit itself — nothing to compare")
        return 0
    flags, fixed = check_flags(repo, "--fix" in opts)
    findings = flags + check_links(repo) + check_copied_hooks(repo) + check_settings(repo) + check_drift(repo)
    for line in fixed + findings:
        print(line)
    if findings:
        print(f"parity: {len(findings)} deviation(s) from the kit {KIT} in {repo}")
        return 1
    print(f"parity: {repo} matches the kit {KIT}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
