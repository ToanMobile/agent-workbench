#!/usr/bin/env python3
"""PreToolUse(Edit|Write|MultiEdit|NotebookEdit|Bash|Read|Grep|Glob) guard: an agent may not write or delete what decides its own
review, nor read or drive the seal that makes a verdict count.

Audit 31/10/2026 (P0c): the 4-way review gate is only as strong as the files behind it. An agent could rewrite a run's
summary.json, its settings (the hook registrations), the hooks, the review scripts or the CI workflow and pass its own gate.
Denied for agent tool calls:
  .git/review-fanout/**         review runs, verdicts, override tokens and log
  .claude/settings*.json        hook registration / permissions
  hooks/** (any DevKit hooks dir and the dir itself: universal-agent-devkit/hooks, .agents/devkit/hooks, hooks/)
  bin/review*  (review-fanout.sh, review-merge.py, review_runner.py, review-full.py, review_sign.py)
  .github/workflows/**          CI
  ~/.config/agent-workbench/**  the summary seal key: not written, and (r14d, BUG-REV-592ad1528c / 738b4fa129) not READ either —
                                Read / Grep / Glob on it or on a folder above it, a Bash line naming it
Bash: write targets through hooks/shell_writes.py with heredoc / `bash -c` bodies scanned (run_bodies); paths resolved through
symlinks; a line it cannot tokenise, an unparsed body, or a relative write after `cd "$VAR"` is denied when the line points at the
machinery (fail-closed, r14d BUG-REV-c23bc3cb6d / 5f7bee1cb0). An interpreter given inline code (python -I -c, /usr/bin/python3 -c,
node --x -e, perl -w -e, bash <<EOF, …; options before -c/-e are skipped, BUG-REV-4a3ec3ef82) that names a protected path is denied
too (its writes cannot be read statically). The signer is never driven by an agent: a Bash line running an interpreter that names
review_sign / load_key (except a line that is only `python3 [-I] …/review_sign.py verify <file>`), and a Write/Edit of a
non-document file whose text names review_sign, load_key or the key path, are denied.
Residual (same uid, no privilege separation): a script that hides those names (string building, encoding) is not seen; the
code_hash binding of the seal (bin/review_sign.py) and the write ban on .git/review-fanout keep a forged verdict out of the run dir.
Reading the code stays allowed. DEVKIT_ALLOW_GATE_EDIT=1 in the hook process environment (the operator's shell / launchd, never a
prefix on the command: the agent cannot set it for its own hooks) turns the guard off for a maintenance session.
Its own errors never block (it reports them on stderr); a shell_writes failure denies a line that names the machinery.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

PROTECTED = re.compile(
    r"(?:^|/)\.git/review-fanout(?:/|$)"
    r"|(?:^|/)\.claude/settings[^/]*\.json$"
    r"|(?:^|/)hooks(?:/|$)"
    r"|(?:^|/)bin/review[^/]*$"
    r"|(?:^|/)\.github/workflows(?:/|$)"
    r"|(?:^|/)\.config/agent-workbench(?:/|$)")
SECRET_DIR = os.path.join("~", ".config", "agent-workbench")
_INTERP = r"(?:[\w.~/-]*/)?(?:python[\d.]*|node|deno|bun|ruby|perl|php)"
_SHELL = r"(?:[\w.~/-]*/)?(?:bash|sh|zsh|dash|ksh)"
_OPT = r"(?:\s+-{1,2}[A-Za-z][\w.=-]*(?:\s+(?![-<])[^\s;&|<>]+)??)*?"
INLINE = re.compile(r"(?:^|[\s;&|(`])(?:" + _INTERP + _OPT + r"\s+(?:-[A-Za-z]*[cer][A-Za-z]*\b|-(?=\s|$)|<<|<\s*\S)"
                    r"|" + _SHELL + _OPT + r"\s+(?:-[A-Za-z]*c[A-Za-z]*\b|-s\b|-(?=\s|$)|<<|<\s*\S))")
RUNS_INTERP = re.compile(r"(?:^|[\s;&|(`])" + _INTERP + r"(?=\s|$)")
PATH_WORD = re.compile(r"[\w.~/-]*(?:\.git/review-fanout|\.claude/settings[\w.-]*\.json|hooks(?:/[\w.-]+)?|bin/review[\w.-]*"
                       r"|\.github/workflows|\.config/agent-workbench)[\w./-]*")
# a computed cd target or a relative write that points at the machinery (used only after `cd "$VAR"` / an unparsed line)
MACHINERY_HINT = re.compile(r"review-fanout|git-(?:common-)?dir|\.git\b|\.claude|\bhooks\b|workflows|\.config|summary\.json|settings[^/\s]*\.json")
KEY_WORD = re.compile(r"\.config/agent-workbench|review\.key")
SIGNER_WORD = re.compile(r"\breview_sign\b|\bload_key\b|review-fanout-summary-v1")
# lệnh bộ ký duy nhất agent được chạy (ac772c846b): CẢ dòng là `python3 [-I] [<path>/]review_sign.py verify <file>` — không nối
# lệnh, thế lệnh, redirect, comment, dòng thứ hai hay code inline đi kèm (search không neo cho lọt `-c '…load_key…' # …`)
VERIFY_ONLY = re.compile(r"[ \t]*(?:[\w.~/-]*/)?python[\d.]*(?:[ \t]+-I)?[ \t]+(?:[\w.~/-]*/)?review_sign\.py[ \t]+verify"
                         r"[ \t]+[\w.~/@+=:-]+[ \t]*")
DOC_EXT = (".md", ".rst", ".txt", ".adoc")
REASON = ("Blocked by guard-review-tamper: agents may not write or delete the review machinery ({}). The 4-way review gate "
          "decides on these files; change them through a reviewed PR by the operator (DEVKIT_ALLOW_GATE_EDIT=1 in the hook "
          "environment for a maintenance session).")
SEAL_REASON = ("Blocked by guard-review-tamper: the review seal ({}) is neither read nor driven by an agent — a verdict counts "
               "only when review-fanout.sh signs it. Run the review with review-fanout.sh; check a seal with "
               "`review-fanout.sh --verify-summary <summary.json>`.")


def _real(p):
    """realpath of the deepest existing ancestor + the rest: a write through a symlink lands where the link points."""
    head, tail = p, []
    while head and not os.path.lexists(head):
        nxt = os.path.dirname(head)
        if nxt == head:
            break
        tail.append(os.path.basename(head))
        head = nxt
    try:
        base = os.path.realpath(head) if head else head
    except OSError:
        return p
    return os.path.join(base, *reversed(tail)) if tail else base


def _norm(p, cwd):
    p = os.path.expanduser(str(p))
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    return os.path.normpath(p)


def protected(p, cwd):
    if not p:
        return False
    n = _norm(p, cwd)
    return bool(PROTECTED.search(n) or PROTECTED.search(_real(n)))


def _secret_reach(p, cwd):
    """True when a read of p (a file, or a folder searched recursively) reaches the seal key's folder."""
    if not p:
        return False
    secret = _real(os.path.normpath(os.path.expanduser(SECRET_DIR)))
    for n in {_norm(p, cwd), _real(_norm(p, cwd))}:
        n = n.rstrip("/") or "/"
        if n == secret or n.startswith(secret + "/") or secret.startswith(n.rstrip("/") + "/") or KEY_WORD.search(n):
            return True
    return False


def bash_hits(cmd, cwd):
    hits = []
    named = [w for w in PATH_WORD.findall(cmd) if protected(w, cwd)]
    if KEY_WORD.search(cmd):
        return ["seal:" + KEY_WORD.search(cmd).group(0)]
    if SIGNER_WORD.search(cmd) and RUNS_INTERP.search(cmd) and not VERIFY_ONLY.fullmatch(cmd):
        return ["seal:" + SIGNER_WORD.search(cmd).group(0)]
    try:
        import shell_writes
        got = shell_writes.targets(cmd, cwd, run_bodies=True)
        if got is None:   # bash runs lines shlex cannot tokenise ($'..', odd quoting): fail closed when it points at the machinery
            hits += named or ([cmd.strip()[:60]] if MACHINERY_HINT.search(cmd) else [])
            got = []
        cd_unknown = ""
        for kind, target, here in got:
            if kind == "cdvar":   # `cd "$VAR"`: later relative targets are relative to a directory nobody can read statically
                cd_unknown = str(target)
                continue
            if kind == "unparsed":
                hits += named or ([cmd.strip()[:60]] if MACHINERY_HINT.search(cmd) else [])
                continue
            if kind in ("redirect", "file", "interp") and target:
                if protected(target, here or cwd):
                    hits.append(target)
                elif cd_unknown and not os.path.isabs(os.path.expanduser(str(target))) and \
                        (MACHINERY_HINT.search(cd_unknown) or MACHINERY_HINT.search(str(target))):
                    hits.append(f"{cd_unknown}/{target}")
    except Exception as e:   # noqa: BLE001 — fail closed on a line that names the machinery
        sys.stderr.write(f"guard-review-tamper: shell_writes unavailable ({e.__class__.__name__}) — textual check only\n")
        hits += named
    if INLINE.search(cmd):
        hits += named
    return hits


def _content(tool, ti):
    if tool == "Write":
        return str(ti.get("content") or "")
    if tool == "Edit":
        return str(ti.get("new_string") or "")
    if tool == "MultiEdit":
        return "\n".join(str(e.get("new_string") or "") for e in (ti.get("edits") or []) if isinstance(e, dict))
    if tool == "NotebookEdit":
        return str(ti.get("new_source") or "")
    return ""


def judge(payload):
    if not isinstance(payload, dict):
        return None
    tool = str(payload.get("tool_name") or payload.get("toolName") or "")
    ti = next((v for v in (payload.get(k) for k in ("tool_input", "toolInput", "input")) if isinstance(v, dict)), {})
    cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) and payload.get("cwd") else os.getcwd()
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        p = ti.get("file_path") or ti.get("filePath") or ti.get("notebook_path") or ti.get("path") or ""
        if protected(p, cwd):
            return REASON.format(p)
        text = _content(tool, ti)
        if not str(p).lower().endswith(DOC_EXT):
            m = KEY_WORD.search(text) or SIGNER_WORD.search(text)
            if m:
                return SEAL_REASON.format(m.group(0))
        return None
    if tool in ("Read", "Grep", "Glob", "NotebookRead"):
        for p in (ti.get("file_path"), ti.get("path"), ti.get("notebook_path")):
            if p and _secret_reach(p, cwd):
                return SEAL_REASON.format(p)
        pat = str(ti.get("pattern") or "") if tool == "Glob" else ""
        if pat and (KEY_WORD.search(pat) or (os.path.isabs(os.path.expanduser(pat)) and _secret_reach(pat.split("*")[0], cwd))):
            return SEAL_REASON.format(pat)
        return None
    if tool == "Bash":
        hits = bash_hits(str(ti.get("command") or ""), cwd)
        seal = [h[5:] for h in hits if h.startswith("seal:")]
        if seal:
            return SEAL_REASON.format(seal[0])
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
