#!/usr/bin/env python3
"""PreToolUse(Bash) guard: block destructive pushes to a protected base branch.

A non-force update of main/master is allowed. The agent runs that push. Force
(`-f`, `--force`, `--force-with-lease`, a `+` refspec, a short cluster such as
`-uf`, and a unique long prefix such as `--forc`), `--delete`, `--prune`, and
`--mirror` stay denied. `--no-verify` is denied when the destination is protected.
Those are the extremely dangerous updates that need a confirmation first.

Protected: main, master, every `base_branch` in .claude/super-board/configs/*.json, and
any name in SB_PROTECTED_BRANCHES (comma-separated).

SB_ALLOW_PROTECTED_PUSH=1 in the hook process environment turns the guard off.
A prefix on the command does not. Its own errors never block a tool call.
"""
import glob
import json
import os
import re
import subprocess
import sys

GIT_VALUE_OPTS = {"-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
PUSH_VALUE_OPTS = {"--repo", "--receive-pack", "--exec", "-o", "--push-option", "--signed"}
# Thứ tự quyết định tiền tố nào thắng. Cờ an toàn phải có, nếu không `--dry-run`
# thành `--delete` và `--follow-tags` thành `--force`.
DANGER_LONG = (
    "--force",
    "--force-with-lease",
    "--force-if-includes",
    "--delete",
    "--mirror",
    "--prune",
    "--no-verify",
)
SAFE_LONG = (
    "--dry-run",
    "--follow-tags",
    "--no-verbose",
    "--progress",
    "--porcelain",
    "--atomic",
    "--thin",
    "--no-thin",
)
EVERY_LONG = ("--all", "--branches")


def expand_long(flag):
    """`--forc` thành `--force`. Tên đủ, hoặc tiền tố trùng một cờ an toàn, giữ nguyên.

    Git nhận tiền tố dài khi không mơ hồ. Khớp cờ nguy hiểm đầu tiên, và chỉ khi
    không có cờ an toàn nào cũng bắt đầu bằng tiền tố đó.
    """
    name, eq, val = flag.partition("=")
    if not name.startswith("--") or len(name) < 3:
        return flag
    if name in DANGER_LONG or name in SAFE_LONG or name in EVERY_LONG:
        return flag
    hit = next((d for d in DANGER_LONG + EVERY_LONG if d.startswith(name)), None)
    if hit and not any(s.startswith(name) for s in SAFE_LONG):
        return hit + eq + val
    return flag


def short_cluster(flag):
    """`f` trong cụm một gạch là force, `d` là delete. Dừng ở `o` vì `-o<giá trị>` dính liền."""
    force = deleting = False
    if not (flag.startswith("-") and not flag.startswith("--") and len(flag) > 1):
        return force, deleting
    for ch in flag[1:]:
        if ch == "o":
            break
        if ch == "f":
            force = True
        elif ch == "d":
            deleting = True
    return force, deleting


def segments(command):
    """Split a shell command into simple-command token lists. Quotes are honoured; nothing runs."""
    out, tokens, cur, has, quote = [], [], "", False, None
    i = 0

    def push_token():
        nonlocal cur, has
        if has:
            tokens.append(cur)
        cur, has = "", False

    while i < len(command):
        c = command[i]
        if quote:
            if c == quote:
                quote = None
            elif c == "\\" and quote == '"' and i + 1 < len(command):
                i += 1
                cur += command[i]
            else:
                cur += c
        elif c in "'\"":
            quote, has = c, True
        elif c == "\\" and i + 1 < len(command):
            i += 1
            cur += command[i]
            has = True
        elif c in " \t":
            push_token()
        elif c in ";\n|&()":
            push_token()
            if tokens:
                out.append(tokens)
            tokens = []
        else:
            cur += c
            has = True
        i += 1
    push_token()
    if tokens:
        out.append(tokens)
    return out


def branch_name(ref):
    ref = ref.lstrip("+")
    return ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref


def pushes(command, cwd):
    """[(git_dir, flags, positional)] for every `git push` in the command."""
    found, d = [], cwd
    for tokens in segments(command):
        while tokens and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[0]):
            tokens = tokens[1:]
        if tokens and tokens[0] in ("sudo", "command", "env"):
            tokens = tokens[1:]
        if not tokens:
            continue
        cmd, args = tokens[0], tokens[1:]
        if cmd == "cd" and args and "$" not in args[0]:
            d = os.path.normpath(os.path.join(d, os.path.expanduser(args[0])))
            continue
        if os.path.basename(cmd) != "git":
            continue
        git_dir, i = d, 0
        while i < len(args) and args[i].startswith("-"):
            if args[i] == "-C" and i + 1 < len(args):
                git_dir = os.path.normpath(os.path.join(git_dir, os.path.expanduser(args[i + 1])))
                i += 2
            elif args[i] in GIT_VALUE_OPTS:
                i += 2
            else:
                i += 1
        if i >= len(args) or args[i] != "push":
            continue
        flags, positional, j = [], [], i + 1
        while j < len(args):
            a = args[j]
            if a == "--":
                positional += args[j + 1:]
                break
            if a in PUSH_VALUE_OPTS:
                j += 1
            elif a.startswith("-"):
                flags.append(a)
            elif not re.match(r"^\d*[<>]", a):
                positional.append(a)
            j += 1
        found.append((git_dir, flags, positional))
    return found


def current_branch(d):
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    try:
        r = subprocess.run(["git", "-C", d, "symbolic-ref", "--short", "-q", "HEAD"],
                           capture_output=True, text=True, env=env, timeout=10)
        return r.stdout.strip() or None
    except (OSError, subprocess.TimeoutExpired):
        return None


def protected_branches(project_dir):
    names = {"main", "master"}
    for p in glob.glob(os.path.join(project_dir, ".claude", "super-board", "configs", "*.json")):
        try:
            base = json.load(open(p)).get("base_branch")
            if isinstance(base, str) and base:
                names.add(base)
        except (OSError, ValueError, AttributeError):
            pass
    names.update(n.strip() for n in os.environ.get("SB_PROTECTED_BRANCHES", "").split(",") if n.strip())
    return names


def check(command, cwd, protected, branch_of):
    """None when allowed, else the deny reason. branch_of(dir) -> checked-out branch or None.

    Push thường (không force, không xoá) được phép, kể cả khi đích là main. Bị chặn:
    force (cả cụm `-uf` và tiền tố `--forc`), xoá nhánh, `--prune`, `--mirror`, và
    `--no-verify` khi đích là nhánh được bảo vệ.
    """
    if not re.search(r"\bpush\b", command):
        return None
    for git_dir, flags, positional in pushes(command, cwd):
        flags = [expand_long(f) for f in flags]
        specs = positional[1:]
        force = deleting = mirror = prune = no_verify = False
        names = []
        for f in flags:
            name = f.split("=", 1)[0]
            names.append(name)
            clustered_force, clustered_delete = short_cluster(f)
            force = force or clustered_force or name in (
                "--force", "--force-with-lease", "--force-if-includes")
            deleting = deleting or clustered_delete or name == "--delete"
            mirror = mirror or name == "--mirror"
            prune = prune or name == "--prune"
            no_verify = no_verify or name == "--no-verify"
        # `+src:dst` là force. `:main` và `+:main` xoá nhánh mà không cần cờ --delete.
        force = force or any(p.startswith("+") for p in specs)
        deleting = deleting or any(
            (p[1:] if p.startswith("+") else p).startswith(":") for p in specs)
        hit = None
        # --prune xoá ref remote (kể cả main) dù không nêu tên nhánh và dù
        # checkout hiện tại không nằm trong danh sách được bảo vệ.
        if prune:
            hit = "prune"
        elif any(n in ("--all", "--mirror", "--branches") for n in names):
            which = next(n for n in names if n in ("--all", "--mirror", "--branches"))
            hit = "every branch (" + which + ")"
        elif len(positional) <= 1:
            if not deleting and "--tags" not in names:
                cur = branch_of(git_dir)
                if cur in protected:
                    hit = cur
        else:
            for spec in positional[1:]:
                dst = spec.split(":", 1)[1] if ":" in spec else spec
                if dst.lstrip("+") == "HEAD" or (":" not in spec and spec.lstrip("+") == "HEAD"):
                    dst = branch_of(git_dir) or dst
                name = branch_name(dst)
                if name in protected:
                    hit = name
                    break
        if hit and (force or deleting or mirror or prune or no_verify):
            if force:
                kind = "Force push"
            elif deleting or prune:
                kind = "Delete"
            elif mirror:
                kind = "Mirror"
            else:
                kind = "No-verify"
            return (
                "Blocked: %s to protected branch %s.\n"
                "Việc này cực kỳ nguy hiểm. Hỏi người dùng một lần bằng AskUserQuestion trước khi làm lại. "
                "Push fast-forward không --force và không xoá nhánh thì được phép, agent tự chạy.\n"
                "Protected here: %s." % (kind, hit, ", ".join(sorted(protected)))
            )
    return None


def main():
    try:
        if os.environ.get("SB_ALLOW_PROTECTED_PUSH") == "1":
            return
        payload = json.loads(sys.stdin.read() or "{}")
        command = (payload.get("tool_input") or {}).get("command")
        if not isinstance(command, str):
            return
        cwd = payload.get("cwd") or os.getcwd()
        project = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
        reason = check(command, cwd, protected_branches(project), current_branch)
        if reason:
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                     "permissionDecision": "deny",
                                                     "permissionDecisionReason": reason}}))
    except Exception:
        pass  # a broken guard must never block unrelated work


if __name__ == "__main__":
    main()
