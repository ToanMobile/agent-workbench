"""The worktree a Claude Code session works in, and whether a repo runs in trunk mode (W1 R1/R2/R7, docs/workflow-improvements.md I.0, v6).

Trunk mode, opt-in per repo (`git config devkit.trunkMode true`; WORKTREE_TRUNK_MODE=0 in the environment turns it off everywhere): the
main checkout is merge-only. Every session works in its own worktree under <main>/.claude/worktrees/ (the Claude Code tool EnterWorktree;
the WorktreeCreate hook sets it up), and only `agent-kit worktree finish` / `automerge` moves main. Nobody holds main, so a finished
worktree is merged whenever its session stops instead of waiting for the session that held main (root cause 14/10: a holder in a 17 h
turn left every other session's worktree unmerged until the cap blocked them all).

What this rests on (code.claude.com docs, checked 14/10/2026): after EnterWorktree CLAUDE_PROJECT_DIR still names the main checkout and
the hooks still run from it, while the hook input `cwd` is the worktree root. A gate that reads CLAUDE_PROJECT_DIR therefore checks main,
not the session's work (issues-bugs.md A.4). The worktree a session ENTERED is recorded by the PostToolUse hook on EnterWorktree /
ExitWorktree (`record`), one small file per session under <main>/.claude/audit-gate/session_worktree/, and project() reads it: O(1),
no transcript scan on the hot path. A subagent started in a worktree by the harness (isolation: "worktree") is told by its meta file.
Line 2 of the record is `pid <n>`, the claude process it was written under: the merge gate adopts a dead session's worktree (merge, then
remove) only on proof of death - that pid gone (bin/session_lock.py owner_gone) - and /clear keeps the process, so the record follows it.

The record is agent-writable state (INSTINCT-027): it only chooses which tree a session's own Stop gates check, and it is honoured only
for a registered linked worktree of the same repo. Nothing reaches main without the merge gate of `worktree finish` / `automerge` (W1 R3)
and the final --full on main, which never read it.

Standard library only: hooks import it with `python3 -I`.
"""
import json
import os
import re
import stat
import sys
import time

RECORD_DIR = os.path.join(".claude", "audit-gate", "session_worktree")
_SID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")   # first char alphanumeric: a dotted temp name (write_record) is never a session id
_PID_LINE = re.compile(r"pid ([0-9]{1,10})")
_TRUE = {"true", "yes", "on", "1"}


def tree_of(path):
    """(top dir, is a linked worktree, git common dir) of the git tree holding `path`, or None - read from the files, no git process."""
    cur = os.path.realpath(path or ".")
    while not os.path.exists(cur):
        up = os.path.dirname(cur)
        if up == cur:
            return None
        cur = up
    if os.path.isfile(cur):
        cur = os.path.dirname(cur)
    while True:
        dotgit = os.path.join(cur, ".git")
        if os.path.isdir(dotgit):
            return cur, False, dotgit
        if os.path.isfile(dotgit):
            line = ((_read_small(dotgit) or "").splitlines() or [""])[0].strip()   # (never a plain open(): a FIFO there hangs every gate, INSTINCT-040)
            if not line.startswith("gitdir:"):
                return None
            gdir = line[len("gitdir:"):].strip()
            gdir = os.path.realpath(gdir if os.path.isabs(gdir) else os.path.join(cur, gdir))
            common = _read_small(os.path.join(gdir, "commondir"))
            if common is None:
                return cur, False, gdir   # a submodule (no commondir): its own tree - a FIFO or a symlink there reads the same
            common = common.strip()
            common = os.path.realpath(common if os.path.isabs(common) else os.path.join(gdir, common))
            return cur, True, common
        up = os.path.dirname(cur)
        if up == cur:
            return None
        cur = up


def main_of(path):
    """The main checkout of the repo holding `path` (the folder of its common .git dir), or None (bare repo, not a git tree)."""
    t = tree_of(path)
    if not t:
        return None
    if not t[1]:
        return t[0]
    return os.path.dirname(t[2]) if os.path.basename(t[2]) == ".git" else None


def _config_bool(config_path, section, key):
    """[section] key from one git config file, as git reads a boolean (`key` alone = true); None when absent or unreadable. Section and
    key names are case-insensitive; subsections ([devkit "x"]) and include files are not read."""
    try:
        with open(config_path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return None
    cur, value = None, None
    for raw in lines:
        line = raw.strip()
        if not line or line[0] in "#;":
            continue
        m = re.match(r"\[\s*([A-Za-z0-9.-]+)\s*\]", line)
        if line.startswith("["):
            cur = m.group(1).lower() if m else None
            line = line[m.end():].strip() if m else ""
            if not line:
                continue
        if cur != section:
            continue
        m = re.match(r"([A-Za-z][A-Za-z0-9-]*)\s*(?:=\s*(.*))?$", line)
        if not m or m.group(1).lower() != key:
            continue
        v = m.group(2)
        v = "true" if v is None else re.split(r"\s[#;]", v, maxsplit=1)[0].strip().strip('"').lower()
        value = v in _TRUE   # the last one wins, as in git
    return value


def trunk_mode(path, env=None):
    """True when the repo holding `path` runs in trunk mode: `devkit.trunkMode` true in its common config (git config devkit.trunkMode
    true), and WORKTREE_TRUNK_MODE is not 0 (R7: the user's switch back to the old behaviour). Anything unreadable: False (old behaviour)."""
    env = os.environ if env is None else env
    if env.get("WORKTREE_TRUNK_MODE", "1") == "0":
        return False
    t = tree_of(path)
    if not t:
        return False
    common = t[2]
    return bool(_config_bool(os.path.join(common, "config"), "devkit", "trunkmode"))


def _record_path(main, sid):
    if not main or not isinstance(sid, str) or not _SID.fullmatch(sid):
        return None
    return os.path.join(main, RECORD_DIR, sid)


def _read_small(path, limit=65536):
    """A small regular file's text, or None - never a hang on a FIFO an agent planted there (INSTINCT-040), never a symlink followed."""
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0))
    except (OSError, ValueError):
        return None
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return None
        return os.read(fd, limit).decode("utf-8", "replace")
    except OSError:
        return None
    finally:
        os.close(fd)


def _same_repo_worktree(main, wt):
    """`wt` when it is an existing linked worktree REGISTERED in the repo whose main checkout is `main`: its .git file names an admin dir
    under main's .git/worktrees/ AND that admin dir's `gitdir` names this folder back. A folder can carry any .git file (an agent can write
    one pointing at a real worktree's admin dir); git's back-link it cannot fake without moving the real worktree (OCR 14/10). Else None."""
    if not isinstance(wt, str) or not os.path.isabs(wt):
        return None
    t = tree_of(wt)
    if not t or not t[1] or os.path.realpath(t[0]) != os.path.realpath(wt):
        return None
    m = os.path.dirname(t[2]) if os.path.basename(t[2]) == ".git" else None
    if not m or os.path.realpath(m) != os.path.realpath(main):
        return None
    line = (_read_small(os.path.join(t[0], ".git")) or "").strip()
    gdir = line[len("gitdir:"):].strip() if line.startswith("gitdir:") else ""
    gdir = os.path.realpath(gdir if os.path.isabs(gdir) else os.path.join(t[0], gdir)) if gdir else ""
    back = (_read_small(os.path.join(gdir, "gitdir")) or "").strip() if gdir else ""
    if not back or os.path.realpath(back) != os.path.realpath(os.path.join(t[0], ".git")):
        return None
    return t[0]


def raw_record(main, sid):
    """The absolute path a session's record names, whatever is there now (None: no record, unreadable, not absolute)."""
    p = _record_path(main, sid)
    wt = (_read_small(p) or "").strip().splitlines()[0:1] if p else []
    return wt[0] if wt and os.path.isabs(wt[0]) else None


def raw_pid(main, sid):
    """The pid on line 2 of a session's record (`pid <n>`): the claude process the record was written under, None when there is none. Line 1 stays
    the worktree path, so a reader that knows only the path still works."""
    p = _record_path(main, sid)
    lines = (_read_small(p) or "").splitlines()[1:2] if p else []
    m = _PID_LINE.fullmatch(lines[0].strip()) if lines else None
    return int(m.group(1)) if m and int(m.group(1)) > 1 else None


def record_age(main, sid, now=None):
    """Seconds since a session's record was last written, None when unreadable (a symlink or FIFO there counts as unreadable)."""
    p = _record_path(main, sid)
    try:
        st = os.lstat(p) if p else None
    except OSError:
        return None
    return (time.time() if now is None else now) - st.st_mtime if st and stat.S_ISREG(st.st_mode) else None


def holder_pid():
    """The claude process this hook runs under (bin/session_lock.holder_pid, which skips the short-lived sh of dash systems), None when that module
    cannot be loaded: a record then carries no pid and is never taken over on a pid."""
    try:
        bindir = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "bin")
        if bindir not in sys.path:
            sys.path.append(bindir)
        import session_lock
        return session_lock.holder_pid()
    except Exception:  # noqa: BLE001 - no pid recorded is the safe side: the owner then reads as alive until the record is a day old
        return None


def read_record(main, sid):
    """The worktree session `sid` entered (EnterWorktree, not left with ExitWorktree), if it is still a registered linked worktree of this repo."""
    wt = raw_record(main, sid)
    return _same_repo_worktree(main, wt) if wt else None


def write_record(main, sid, wt, pid=None):
    """Record that session `sid` works in worktree `wt`. pid: the claude process of that session (holder_pid), line 2 - what the merge gate
    judges the owner dead by. Never the pid of the process writing here when that is a hook's child (the merge gate's python): it dies at once."""
    p = _record_path(main, sid)
    if not p or not _same_repo_worktree(main, wt):
        return False
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = os.path.join(os.path.dirname(p), f".{os.path.basename(p)}.{os.getpid()}.tmp")   # a leading "." never matches _SID: no reader takes it for a record
    if os.path.lexists(tmp):
        os.unlink(tmp)   # (a leftover of a killed hook with this pid, or a symlink planted there: never written through)
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(os.path.realpath(wt) + "\n" + (f"pid {int(pid)}\n" if isinstance(pid, int) and not isinstance(pid, bool) and pid > 1 else ""))
    os.replace(tmp, p)
    return True


def clear_record(main, sid):
    p = _record_path(main, sid)
    if p and os.path.lexists(p):
        try:
            os.unlink(p)
        except FileNotFoundError:
            return   # removed meanwhile by another hook: the same outcome


def records(main):
    """{session id: worktree} of every session record of this repo (worktrees that no longer exist left out)."""
    d = os.path.join(main, RECORD_DIR)
    try:
        names = os.listdir(d)
    except OSError:
        return {}
    out = {}
    for sid in names:
        if _SID.fullmatch(sid):
            wt = read_record(main, sid)
            if wt:
                out[sid] = wt
    return out


def registered(main, wt):
    """`wt` is still registered in the repo (git lists it), its folder there or not: an admin dir under main's .git/worktrees/ names
    <wt>/.git back. A folder removed from outside while git still lists it is not "gone": its commits may be in no other place."""
    want = os.path.realpath(os.path.join(wt, ".git"))
    adm = os.path.join(main, ".git", "worktrees")
    try:
        names = os.listdir(adm)
    except OSError:
        return False
    return any(os.path.realpath((_read_small(os.path.join(adm, n, "gitdir")) or "").strip() or "/") == want for n in names)


def prune_records(main):
    """Drop the records whose worktree git no longer lists (merged and removed): they would name nothing. A record whose folder is gone
    while git still lists the worktree is KEPT: it is the trace the merge gate holds on (OCR 14/10)."""
    try:
        names = os.listdir(os.path.join(main, RECORD_DIR))
    except OSError:
        return
    for sid in names:
        if not _SID.fullmatch(sid) or read_record(main, sid):
            continue
        wt = raw_record(main, sid)
        if not wt or not registered(main, wt):
            clear_record(main, sid)


def reown(main, sid, here, is_alive, me=None):
    """/clear and /resume give the same Claude process a new session id while it stays in its worktree: the record of a session that is
    no longer alive, naming the worktree `here` lies in, becomes `sid`'s - else the next Stop would adopt (merge and remove) the worktree
    the session still works in, and the gates would check main again. A session that already has a record keeps it: its own worktree is
    never swapped for a dead session's one it happens to stand in. me: the claude pid of the session asking - a record written under that
    very process is this session's own under its old id (the old id's registry entry is gone, its pid is alive: it is no peer). The
    record's pid is carried over. Returns the worktree re-owned, or None."""
    if not _record_path(main, sid) or not here or raw_record(main, sid):
        return None
    here = os.path.realpath(here)
    for osid, wt in records(main).items():
        rp = os.path.realpath(wt)
        if osid == sid or not (here == rp or here.startswith(rp + os.sep)):
            continue
        rec_pid = raw_pid(main, osid)
        if not is_alive(osid) or (me and rec_pid == me):
            if write_record(main, sid, rp, pid=rec_pid):
                clear_record(main, osid)
                return rp
    return None


def _entered_path(payload):
    """The worktree an EnterWorktree call entered: the tool response names it (`worktreePath`); else its input `path`; else the hook cwd
    (the worktree root once the call succeeded)."""
    resp = payload.get("tool_response")
    if isinstance(resp, str):
        try:
            resp = json.loads(resp)
        except ValueError:
            resp = {}
    if isinstance(resp, dict) and isinstance(resp.get("worktreePath"), str):
        return resp["worktreePath"]
    inp = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
    if isinstance(inp.get("path"), str) and inp["path"]:
        return inp["path"]
    return payload.get("cwd")


def on_tool_use(payload, env=None):
    """PostToolUse hook on EnterWorktree / ExitWorktree (the main session only: a subagent's worktree is its harness meta's business).
    Returns what it did, for the log and the tests: 'entered <path>', 'left', or ''."""
    env = os.environ if env is None else env
    if payload.get("agent_id"):
        return ""
    sid = str(payload.get("session_id") or "")
    tool = str(payload.get("tool_name") or "")
    base = env.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or ""
    main = main_of(base) if base else None
    if not main or not _record_path(main, sid):
        return ""
    if tool == "EnterWorktree":
        wt = _entered_path(payload)
        t = tree_of(wt) if isinstance(wt, str) and wt else None
        if t and t[1] and write_record(main, sid, t[0], pid=holder_pid()):
            return "entered " + t[0]
        return ""
    if tool == "ExitWorktree":
        clear_record(main, sid)
        return "left"
    return ""


def _agent_worktree(payload, main):
    """A subagent started in a worktree by the harness: its meta file's worktreePath (hooks/worktree_guard.sh reads the same files)."""
    agent, tp, sid = str(payload.get("agent_id") or ""), str(payload.get("transcript_path") or ""), str(payload.get("session_id") or "")
    if not (agent and tp):
        return None
    base, name = os.path.splitext(tp)[0], f"agent-{agent}.meta.json"
    for meta in (os.path.join(base, "subagents", name), os.path.join(os.path.dirname(tp), name),
                 os.path.join(os.path.dirname(tp), sid, "subagents", name)):
        try:
            with open(meta, encoding="utf-8") as fh:
                wp = json.load(fh).get("worktreePath")
        except (OSError, ValueError, AttributeError):
            continue
        wt = _same_repo_worktree(main, wp)
        if wt:
            return wt
    return None


def project(payload, env=None):
    """The tree a hook should judge for this tool call / Stop: the session's (or subagent's) worktree when it works in one of THIS repo,
    else what the hooks used before - CLAUDE_PROJECT_DIR, else the git tree of the payload cwd. None outside a git tree."""
    env = os.environ if env is None else env
    base = env.get("CLAUDE_PROJECT_DIR") or ""
    if not base:
        t = tree_of(payload.get("cwd") or ".")
        base = t[0] if t else ""
    if not base:
        return None
    main = main_of(base)
    if main:
        # a subagent the harness started in a worktree works there; any other subagent works where its session does
        wt = _agent_worktree(payload, main) if payload.get("agent_id") else None
        if not wt:
            rec = read_record(main, str(payload.get("session_id") or ""))
            wt = rec if rec and _record_applies(rec, payload.get("cwd"), main, env) else None
        if wt:
            return wt
    return base


def _record_applies(rec, cwd, main, env):
    """A record moves the gates only where it agrees with where the session is. Trunk mode off: the hook cwd must be inside the recorded
    worktree (after EnterWorktree it is its root), so a record written in a repo where the session works in main never points its gates at
    a clean tree (OCR 14/10). Trunk mode: main is merge-only, so the record holds unless the cwd is inside ANOTHER worktree of the repo."""
    here = os.path.realpath(cwd) if isinstance(cwd, str) and cwd else ""
    r = os.path.realpath(rec)
    if here and (here == r or here.startswith(r + os.sep)):
        return True
    if not trunk_mode(main, env):
        return False
    t = tree_of(here) if here else None
    return not (t and t[1] and os.path.realpath(t[0]) != r)


def _payload():
    """The hook payload: on fd 3 when the caller passed it there (big payloads, hooks/*.sh), else stdin."""
    try:
        with os.fdopen(3, encoding="utf-8", errors="replace") as fh:
            raw = fh.read()
    except OSError:
        raw = sys.stdin.read()
    try:
        d = json.loads(raw or "{}")
    except ValueError:
        return {}
    return d if isinstance(d, dict) else {}


def main(argv):
    cmd = argv[0] if argv else ""
    if cmd == "trunk-mode":   # exit 0 = on, 1 = off (bash callers)
        on = trunk_mode(argv[1] if len(argv) > 1 else os.getcwd())
        print("on" if on else "off")
        return 0 if on else 1
    if cmd == "project":
        p = project(_payload())
        if p:
            print(p)
        return 0
    if cmd == "record":   # PostToolUse EnterWorktree|ExitWorktree: never blocks
        try:
            did = on_tool_use(_payload())
        except Exception as e:  # noqa: BLE001 - a hook that records state must never fail the tool call; said on stderr
            print(f"session_worktree: record failed ({type(e).__name__}: {e})", file=sys.stderr)
            return 0
        if did:
            print(f"session_worktree: {did}", file=sys.stderr)
        return 0
    print("usage: session_worktree.py trunk-mode [path] | project | record   (payload JSON on fd 3 or stdin)", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
