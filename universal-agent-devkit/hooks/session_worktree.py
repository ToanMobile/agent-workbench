"""The worktree a Claude Code session works in, and whether a repo runs in trunk mode (W1 R1/R2/R7, docs/workflow-improvements.md I.0, v6).

Trunk mode, ON by default (`git config devkit.trunkMode false` / `agent-kit worktree trunk off` opts a repo out; WORKTREE_TRUNK_MODE=0 in the environment turns it off everywhere): the
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
import subprocess
import sys
import time

RECORD_DIR = os.path.join(".claude", "audit-gate", "session_worktree")
_SID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")   # first char alphanumeric: a dotted temp name (write_record) is never a session id
_PID_LINE = re.compile(r"pid ([0-9]{1,10})")
_START_LINE = re.compile(r"start (\S{1,128})")   # line 3 of a record: the start time of the pid on line 2 (pid_start_token form)
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


def _config_bool(config_path, section, key, default=None):
    """[section] key from one git config file, as git reads a boolean (`key` alone = true); `default` (None) when the file was read and has no
    such key, None when it cannot be read. Section and
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
    return default if value is None else value


def trunk_mode(path, env=None):
    """True when the repo holding `path` runs in trunk mode. It is the DEFAULT (user, 2026-10-15): a repo with no `devkit.trunkMode` key is
    on; `git config devkit.trunkMode false` (agent-kit worktree trunk off) turns it off, and so does WORKTREE_TRUNK_MODE=0 (R7: the user's
    switch back to the old behaviour). A config git cannot read: False (old behaviour, never a guess). Only the repo's own `<common>/config`
    counts (the file is read, no git process: a hook runs on every tool call): `git config --global devkit.trunkMode false` or a key in an
    included file is NOT seen, so a missing key there still means ON."""
    env = os.environ if env is None else env
    if env.get("WORKTREE_TRUNK_MODE", "1") == "0":
        return False
    t = tree_of(path)
    if not t:
        return False
    common = t[2]
    # no key = ON, but only for a normal repo (common dir `.git`, not core.bare): a bare repo or an odd layout has no checkout to merge into,
    # and that includes `git clone --bare URL proj/.git`, whose parent `proj` is no checkout. A config that cannot be read gives None -> False
    cfg = os.path.join(common, "config")
    normal = os.path.basename(common) == ".git" and not _config_bool(cfg, "core", "bare")
    return bool(_config_bool(cfg, "devkit", "trunkmode", default=normal))


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


def raw_pid_start(main, sid):
    """The start time of the record's pid (a `start <token>` line after the path, #413): tells a pid the OS has handed to another process from the
    session it was written under. None when the record has none (older kit, start time unknown)."""
    p = _record_path(main, sid)
    for l in (_read_small(p) or "").splitlines()[2:] if p else []:
        m = _START_LINE.fullmatch(l.strip())
        if m:
            return m.group(1)
    return None


def raw_visit(main, sid):
    """True when the session's record says it only visited its worktree (a `visit` line after the path), not created it (#428)."""
    p = _record_path(main, sid)
    return "visit" in [l.strip() for l in (_read_small(p) or "").splitlines()[1:]] if p else False


def record_age(main, sid, now=None):
    """Seconds since a session's record was last written, None when unreadable (a symlink or FIFO there counts as unreadable)."""
    p = _record_path(main, sid)
    try:
        st = os.lstat(p) if p else None
    except OSError:
        return None
    return (time.time() if now is None else now) - st.st_mtime if st and stat.S_ISREG(st.st_mode) else None


def _session_lock():
    """bin/session_lock.py as a module (after the stdlib on sys.path: nothing there may shadow it); raises when it cannot be loaded."""
    bindir = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "bin")
    if bindir not in sys.path:
        sys.path.append(bindir)
    import session_lock
    return session_lock


def holder_pid():
    """The claude process this hook runs under (bin/session_lock.holder_pid, which skips the short-lived sh of dash systems), None when that module
    cannot be loaded: a record then carries no pid and is never taken over on a pid."""
    try:
        return _session_lock().holder_pid()
    except Exception:  # noqa: BLE001 - no pid recorded is the safe side: the owner then reads as alive until the record is a day old
        return None


def pid_start_token(pid):
    """The start time of `pid` (bin/session_lock.pid_start: /proc on Linux, `ps -o lstart=` in UTC elsewhere) with no blank, as a devkit-kept
    lock records it; None when unknown. #406: the OS hands a dead session's pid to another process later - only the start time tells them apart."""
    try:
        s = _session_lock().pid_start(pid)
    except Exception as e:  # noqa: BLE001 - unknown start time: the lock is written without one and read as before (pid only)
        print(f"session_worktree: start time of pid {pid} unknown ({e!r}): pid reuse is not detected", file=sys.stderr)
        return None
    return re.sub(r"\s+", "_", s.strip()) if isinstance(s, str) and s.strip() else None


def read_record(main, sid):
    """The worktree session `sid` entered (EnterWorktree, not left with ExitWorktree), if it is still a registered linked worktree of this repo."""
    wt = raw_record(main, sid)
    return _same_repo_worktree(main, wt) if wt else None


def write_record(main, sid, wt, pid=None, start=None, visit=False):
    """Record that session `sid` works in worktree `wt`. pid: the claude process of that session (holder_pid), line 2 - what the merge gate
    judges the owner dead by. start: that pid's start time (pid_start_token), a `start` line, only beside a valid pid (#413: a pid the OS reused is
    told apart from the session). visit: the session only stepped into an existing worktree (EnterWorktree `path`), a `visit` line (#428). Never the pid of the process writing here when that is a hook's child (the merge gate's python): it dies at once."""
    p = _record_path(main, sid)
    if not p or not _same_repo_worktree(main, wt):
        return False
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = os.path.join(os.path.dirname(p), f".{os.path.basename(p)}.{os.getpid()}.tmp")   # a leading "." never matches _SID: no reader takes it for a record
    if os.path.lexists(tmp):
        os.unlink(tmp)   # (a leftover of a killed hook with this pid, or a symlink planted there: never written through)
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o644)
    pid_ok = isinstance(pid, int) and not isinstance(pid, bool) and pid > 1
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(os.path.realpath(wt) + "\n" + (f"pid {int(pid)}\n" if pid_ok else "")
                 + (f"start {start}\n" if pid_ok and isinstance(start, str) and _START_LINE.fullmatch(f"start {start}") else "")
                 + ("visit\n" if visit else ""))
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
        rec_pid, rec_start = raw_pid(main, osid), raw_pid_start(main, osid)
        # Trade-off (OCR2 5): a /resume gets a new pid, so only "the owner is gone" tells it from a bystander; a session with no record that merely
        # stands (cd) in a dead peer's worktree takes it over too. It then merges that worktree with --keep and keeps it - the work is never lost.
        if not is_alive(osid) or (me and rec_pid == me):
            if write_record(main, sid, rp, pid=rec_pid, start=rec_start, visit=raw_visit(main, osid)):
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
        pid = holder_pid()
        # #428: a visit to a worktree the session did not create (EnterWorktree `path`) leaves no keep lock behind when the session moves on
        prev = read_record(main, sid) if raw_visit(main, sid) else None
        inp = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
        if prev and t and os.path.realpath(prev) != os.path.realpath(t[0]):
            _kept_lock(main, prev, sid, pid, unlock=True)
        if t and t[1] and write_record(main, sid, t[0], pid=pid, start=pid_start_token(pid) if pid else None, visit=bool(inp.get("path"))):
            if trunk_mode(main, env):
                # 25/10: cleanup-wt (mọi bản đã cài chỉ chừa worktree bị khoá) gỡ worktree đã gộp ngay lúc phiên đang chạy gate trong đó.
                # Khoá devkit-kept suốt lúc phiên ở trong: ExitWorktree remove đi qua WorktreeRemove -> `worktree remove` của kit, lệnh
                # này mở khoá của chính phiên gọi; pid chết thì khoá vô hiệu (automerge / remove mở như K11).
                if not _kept_lock(main, t[0], sid, pid):   # nói ra, không im lặng (OCR 25/10): cleanup-wt có thể gỡ nó giữa chừng
                    return "entered " + t[0] + "; NOT LOCKED (no pid / git refused): cleanup-wt may remove it while the session works"
            else:   # trunk mode tắt: harness tự `git worktree remove` khi ExitWorktree remove, khoá sẽ chặn nó (như trước)
                _kept_lock(main, t[0], sid, None, unlock=True)
            return "entered " + t[0]
        return ""
    if tool == "ExitWorktree":
        wt = read_record(main, sid)
        inp = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
        visited = raw_visit(main, sid)
        clear_record(main, sid)
        if wt and visited:
            # #428: the session only visited this worktree (not its creator): its devkit-kept lock goes, keep or remove; other locks stay
            _kept_lock(main, wt, sid, holder_pid(), unlock=True)
            return "left"
        if wt and inp.get("action") == "keep":
            if _kept_lock(main, wt, sid, holder_pid()):
                return "left, kept " + wt
            return "left; KEEP NOT RECORDED (no lock): the Stop may merge and remove " + wt   # nói ra, không im lặng (OCR 18/10)
        if wt and trunk_mode(main, env):
            # review 25/10: rời không "keep" mà worktree còn đó (WorktreeRemove từ chối: việc chưa vào main) -> mở khoá Enter của phiên này
            # (theo sid, hay theo pid sau /clear), để Stop gộp rồi gỡ nó như worktree mồ côi thay vì báo "kept by a live session" mãi
            _kept_lock(main, wt, sid, holder_pid(), unlock=True)
        return "left"
    return ""


KEPT_PREFIX = "devkit-kept session="
KEPT_RE = re.compile(r"devkit-kept session=(\S+) pid=([0-9]{1,10})")
# #406: thời điểm khởi động của pid khoá nằm CẠNH khoá, trong git dir của worktree ("<pid> <start>"), không trong lý do khoá: lý do giữ đúng
# dạng cũ vì .claude/bin/super-board-post-merge-clean.sh của mọi repo board (kit được symlink sang đó) đọc nó bằng regex neo cuối.
KEPT_START = "devkit-kept.start"


def _admin_dir(wt):
    """The linked worktree's own git dir (<main>/.git/worktrees/<name>), from its `.git` file; None when that cannot be read."""
    raw = (_read_small(os.path.join(wt, ".git"), 4096) or "").strip()
    if not raw.startswith("gitdir: "):
        return None
    d = raw[len("gitdir: "):].strip()
    d = d if os.path.isabs(d) else os.path.normpath(os.path.join(wt, d))
    return d if os.path.isdir(d) else None


def kept_start(wt, pid):
    """The start time recorded beside the devkit-kept lock of `wt` for `pid`; None when there is none (an older kit's lock, a file another
    pid's lock left)."""
    d = _admin_dir(wt)
    parts = (_read_small(os.path.join(d, KEPT_START), 256) or "").split() if d else []
    return parts[1] if len(parts) == 2 and parts[0] == str(pid) else None


def _write_kept_start(wt, pid, start):
    """Record `pid`'s start time beside the lock about to be taken on `wt`. The older file goes FIRST, whatever happens next: its pid may be
    the one the OS has handed to this very process, and a new lock beside that older start time would read dead (OCR 25/10). A failure is
    said on stderr: the lock then reads as before, by its pid alone."""
    d = _admin_dir(wt)
    if not d:
        return
    p = os.path.join(d, KEPT_START)
    tmp = f"{p}.{os.getpid()}.tmp"
    for old in (p, tmp):   # p first, each on its own: an entry stuck at the temp name must not keep the older start time (OCR 25/10)
        try:
            if os.path.lexists(old):
                os.unlink(old)
        except OSError as e:
            print(f"session_worktree: {old} not removed ({e!r})", file=sys.stderr)
    try:
        if start:
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o644)
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(f"{pid} {start}\n")
            os.replace(tmp, p)
    except OSError as e:
        print(f"session_worktree: start time of the lock not recorded ({e!r})", file=sys.stderr)
        if os.path.lexists(tmp):
            try:
                os.unlink(tmp)
            except OSError as e2:
                print(f"session_worktree: temp file left behind: {tmp} ({e2!r})", file=sys.stderr)


def _pid_alive(pid):
    """Như scripts/git/worktree.py kept_lock: pid ≤ 1 không phải pid của phiên (không sống); không đủ quyền = còn sống."""
    if pid <= 1:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except (OSError, OverflowError):
        return True


def lock_pid_alive(pid, start=None):
    """The process a devkit-kept lock names is still that session: the pid answers and, when the lock recorded a start time, the pid's start
    time is that one (#406: a different one = the OS reused the pid). A start time that cannot be read now, or one read another way than
    it was written (/proc vs ps), reads alive (fail closed: a worktree kept too long, never one removed from under a live session)."""
    if not _pid_alive(pid):
        return False
    now = pid_start_token(pid) if start else None
    return now is None or now.startswith("proc:") != start.startswith("proc:") or now == start


def _worktree_locks(g):
    """{realpath of a linked worktree: its lock reason} from `git worktree list --porcelain` (g: the git runner); None on a git error."""
    listed = g("worktree", "list", "--porcelain")
    if listed is None or listed.returncode:
        return None
    out, cur = {}, None
    for line in listed.stdout.splitlines():
        if line.startswith("worktree "):
            cur = line[len("worktree "):]
        elif (line == "locked" or line.startswith("locked ")) and cur:
            out[os.path.realpath(cur)] = line[len("locked "):]
    return out


def _git_in(main):
    def g(*args):
        try:
            return subprocess.run(["git", "-C", main, *args], capture_output=True, text=True, timeout=5)
        except (OSError, subprocess.SubprocessError):
            return None
    return g


def _kept_lock(main, wt, sid, pid, unlock=False, locks=None):
    """K11 (18/10): ExitWorktree "keep" = phiên muốn giữ worktree. Khoá nó bằng `git worktree lock --reason "devkit-kept session=<sid> pid=<pid
    claude>"`: gộp vẫn được, nhưng automerge của Stop (scripts/git/worktree.py kept_lock) và cleanup-wt (bỏ qua worktree bị khoá) không gỡ nó
    khi pid đó còn sống; pid chết thì `worktree remove` mở khoá. unlock=True: mở khoá devkit-kept của chính phiên `sid` (EnterWorktree lại);
    không có pid hợp lệ khi khoá thì không làm gì (không bao giờ mở khoá ở nhánh này).
    Khoá do người khác đặt (không phải devkit-kept) không bao giờ bị đụng. Trả True khi đã khoá; lỗi git: False, không chặn tool."""
    g = _git_in(main)
    locks = _worktree_locks(g) if locks is None else locks   # locks: the caller listed them already (one `git worktree list` per hook run)
    if locks is None:
        return False
    reason = locks.get(os.path.realpath(wt))
    if unlock:   # khoá devkit-kept của chính phiên: cùng sid, hay (pid hợp lệ được truyền) cùng tiến trình claude — /clear đổi sid, giữ pid
        m = KEPT_RE.fullmatch(reason or "")
        mine_by_pid = isinstance(pid, int) and not isinstance(pid, bool) and pid > 1 and m is not None and int(m.group(2)) == pid
        if m and (m.group(1) == sid or mine_by_pid):
            g("worktree", "unlock", wt)
        return False
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 1:
        return False
    start = pid_start_token(pid)   # trước khi mở khoá (review 25/10): lần gọi ps không nới khoảng worktree không khoá giữa unlock và lock
    if reason is not None:
        if not reason.startswith(KEPT_PREFIX):
            return False   # khoá của người khác: để yên
        m = KEPT_RE.fullmatch(reason)
        if m and m.group(1) != sid and lock_pid_alive(int(m.group(2)), kept_start(wt, int(m.group(2)))):
            return True   # một phiên KHÁC còn sống đã giữ nó: khoá đó vẫn giữ worktree, không thay (OCR 18/10)
        g("worktree", "unlock", wt)   # khoá devkit-kept của chính phiên, hay của pid đã chết / đã bị cấp lại: thay bằng pid hiện tại
    _write_kept_start(wt, pid, start)   # trước khi khoá: không lúc nào khoá mới đứng cạnh thời điểm khởi động cũ của pid đó
    r = g("worktree", "lock", "--reason", f"{KEPT_PREFIX}{sid} pid={pid}", wt)
    return r is not None and r.returncode == 0


_BOARD_WT = re.compile(r"issue-[0-9]+(-(build|qa|review))?")


def _pid_holds_kept_lock(locks, pid, wt):
    """`pid` still holds a live devkit-kept lock (start time matching) on `wt`; `locks`: {path: reason}."""
    path = os.path.realpath(wt)
    m = KEPT_RE.fullmatch(locks.get(path) or "")
    return bool(m and int(m.group(2)) == pid and lock_pid_alive(pid, kept_start(path, pid)))


def _lock_or_report(main, wt, sid, pid, problems, locks):
    """Lock `wt` for the session; `locks`: {path: reason} listed once by the caller, None when git could not list them (then nothing more is
    run: each git call may take its 5 s and the SessionStart hook is killed at 10 s, before it could print). No lock (no pid, git refused or
    timed out; #413): a record of the session's own worktree is written, so a later compact / clear can lock it again (it has no other trace
    of where the session started - unlike a lock taken, it is the one case a record is written here, and the merge gate then adopts that
    worktree when the session is gone), and the failure goes to `problems` - SessionStart prints it, the model hears it. A worktree under
    someone else's lock is held already: nothing to say. Returns `wt` locked."""
    reason = (locks or {}).get(os.path.realpath(wt))
    if locks is not None and _kept_lock(main, wt, sid, pid, locks=locks):
        return wt
    if reason is not None and not reason.startswith(KEPT_PREFIX):
        return None
    rec = raw_record(main, sid)   # read once: a concurrent prune_records may delete the record between two reads
    write_record(main, sid, wt, pid=pid, start=pid_start_token(pid) if pid else None,
                 visit=bool(rec) and raw_visit(main, sid) and os.path.realpath(rec) == os.path.realpath(wt))
    if problems is not None:
        problems.append(f"NOT LOCKED: {wt} (no pid / git refused or timed out): cleanup-wt may remove it while this session works; "
                        "the next compact (or clear from inside it) tries to lock it again")
    return None


def lock_started_worktree(main, here, sid, pid, env=None, source=None, problems=None):
    """SessionStart (bin/session_lock.py; review 25/10): a session that STARTS inside a linked worktree of a trunk-mode repo (a Desktop
    worktree session, `claude --worktree`, `claude --resume` there) never calls EnterWorktree, so it takes the same devkit-kept lock
    there. A super-board lane worktree (.claude/worktrees/issue-<N>[-build|-qa|-review]) is the board's: its runner removes it with a
    plain `git worktree remove`, which a lock left by a dead worker would block. Returns the worktree locked, None otherwise.
    #406: the payload cwd follows the session's `cd`. compact and /clear keep the same claude process, whose lock (taken at its start or
    at EnterWorktree) still holds - a new one there would lock whatever worktree the session merely stands in, another session's
    included. So only a new process (startup, resume, fork; no source: as before) locks from the cwd (compact / clear: #413 below).
    No veto beyond that (#415 had two - "another session owns this worktree", and "this pid already holds a lock elsewhere" for an
    in-session /resume after a `cd` - both reverted 25/10 after seven review rounds): owner identity at SessionStart rests on weak signals
    (state sid, lock sid, record pid, locks gc already opened), and every refinement left a session's real worktree unlocked - cleanup-wt
    then removes it mid-gate, the incident #406 is about. Without them a resumed session locks the worktree it stands in, a peer's
    included: that worktree is kept too long, nothing is lost. Accepted, fail-safe trade-off (#413).
    #413: compact / clear lock again the session's OWN starting worktree - the one its record names (reown moved it to the new id), never the
    cwd - when the startup lock failed and the pid holds no live devkit-kept lock on it. problems: a list that receives one line per lock that
    could not be taken, for the caller to print."""
    if not main or not trunk_mode(main, env):
        return None
    if source in ("compact", "clear"):
        wt = read_record(main, sid)
        if not wt:
            return None
        locks = _worktree_locks(_git_in(main))
        if locks is not None and _pid_holds_kept_lock(locks, pid, wt):
            return None
        return _lock_or_report(main, wt, sid, pid, problems, locks)
    if not here:
        return None
    t = tree_of(here)
    if not t or not t[1] or os.path.realpath(main_of(t[0]) or "") != os.path.realpath(main):
        return None
    if _BOARD_WT.fullmatch(os.path.basename(t[0])) and os.path.basename(os.path.dirname(t[0])) in ("worktrees", ".worktrees"):
        return None
    return _lock_or_report(main, t[0], sid, pid, problems, _worktree_locks(_git_in(main)))


def _agent_worktree(payload, main):
    """A subagent started in a worktree by the harness: its meta file's worktreePath (hooks/worktree_guard.sh reads the same files)."""
    agent, tp, sid = str(payload.get("agent_id") or ""), str(payload.get("transcript_path") or ""), str(payload.get("session_id") or "")
    if not (agent and tp):
        return None
    base, name = os.path.splitext(tp)[0], f"agent-{agent}.meta.json"
    for meta in (os.path.join(base, "subagents", name), os.path.join(os.path.dirname(tp), name),
                 os.path.join(os.path.dirname(tp), sid, "subagents", name)):
        try:   # (_read_small, not open(): the folder is the agent's - a FIFO there hangs every gate, INSTINCT-040)
            wp = json.loads(_read_small(meta) or "").get("worktreePath")
        except (ValueError, AttributeError):
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
            if "KEEP NOT RECORDED" in did or "NOT LOCKED" in did:   # stderr của hook thoát 0 không tới model: nói qua additionalContext (review 18/10)
                print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "session_worktree: " + did}}))
        return 0
    print("usage: session_worktree.py trunk-mode [path] | project | record   (payload JSON on fd 3 or stdin)", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
