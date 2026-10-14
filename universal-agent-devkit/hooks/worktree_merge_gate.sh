#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# worktree_merge_gate.sh — Stop hook: a worktree's work never reached trunk.
#
# OfficeReader and GeelyEx2, 2026-10-01: agents made worktrees (subagents with isolation:
# worktree, EnterWorktree, `agent-kit worktree add`), finished, and the session ended with the
# commits and files still in the worktree. Trunk silently lacked the code and tasks were redone.
#
# HOLDS the Stop (exit 2) while a linked worktree THIS session is responsible for still holds work
# that is not in the main checkout: commits not in its HEAD (patch-aware: work brought back with
# `diff | git apply` counts as integrated), uncommitted files, or detached commits no ref keeps —
# all from scripts/worktree.py inventory(). Responsible = created after the session started
# (mtime of the worktree's admin `commondir`, written once by `git worktree add`), or named in this
# session's transcript / subagent meta as a `worktreePath` (a subagent's isolated worktree).
# Not its business: older unnamed worktrees, a worktree another live session holds
# (bin/session_lock.py rules), and a session that itself runs in a linked worktree (a worker:
# its leader brings the work back). Read-only: it prints the bring-back commands, never merges.
#
# AUTOMATIC (user, 2026-10-08: "it creates a worktree and leaves it there"; "I sit here making you run it 20 times"): before it holds
# anything, this hook MERGES each worktree the session is responsible for - `worktree.py automerge <path>` in its own process group
# (it outlives the alarm below): the worktree's uncommitted work is committed in the worktree, main is merged INTO the worktree, main
# only fast-forwards (another session's uncommitted or staged files are never touched), the worktree is removed. It holds only when
# that cannot finish: a CONFLICT (left open in the worktree, a folder of its own: the agent resolves it there, the next Stop finishes
# the job), main edited uncommitted on the same files, a pre-commit refusal. Not when another live session holds the main checkout
# (their Stop does it), nor with WORKTREE_AUTO_MERGE=0. A worktree is owed to every later session of the repo - but never while the
# session that owns it (made, named or was last held on it: state "owners") is alive and working; once it has ended the next session adopts it.
# The rule is MERGE, THEN REMOVE: a worktree whose work is integrated but that still exists also
# holds the Stop (`agent-kit worktree remove` refuses while work is left, so nothing is lost).
# A worktree a session was held on is OWED (.claude/audit-gate/worktree_merge_gate.state) until it
# is gone: every later session of the repo is held on it too, not only the one that made it.
# At most 3 holds per session and pending set, then the Stop passes with a systemMessage (a merge
# conflict that needs the user must never trap the session); the debt stays for the next session,
# and session_context.sh names each unintegrated worktree at every start.
# Fail-open after 13 s (the alarm below; the Stop timeout is 15 s) and whenever there is NOTHING to protect (no worktree this session is responsible for).
# An internal error while there IS something to protect HOLDS the Stop instead of passing it: inventory() raising, worktree.py or
# session_lock.py not importable, or a responsible worktree whose git dir cannot be determined. Those holds go through the same
# cap as every other (3 per session and pending set), so a persistent error never traps a session; after the cap the Stop passes
# with a systemMessage that says the gate could not run. Off: WORKTREE_MERGE_GATE=0.
# ─────────────────────────────────────────────────────────────────────────────
INPUT="$(cat)"
[ "${WORKTREE_MERGE_GATE:-1}" = "0" ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0
SELF="$0"
while [ -L "${SELF}" ]; do
  LINK="$(readlink "${SELF}")"
  case "${LINK}" in /*) SELF="${LINK}" ;; *) SELF="$(dirname "${SELF}")/${LINK}" ;; esac
done
DEVKIT="$(cd -P "$(dirname "${SELF}")/.." 2>/dev/null && pwd)"
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# The payload goes to python on fd 3, not in an env var (2026-10-09): past the OS limit for one variable (Linux 128 KiB,
# macOS ~1 MiB for args + env) python could not start and the gate passed (tests/gates/test_hook_large_payload.sh).
WMG_REPO="${REPO_ROOT}" WMG_DEVKIT="${DEVKIT}" python3 -I <<'PY' 3<<<"${INPUT}"
import datetime, glob, hashlib, json, os, re, shlex, signal, subprocess, sys, time

def fail_open(*_):
    os._exit(0)   # not SystemExit: worktree.py catches that around git calls, and the alarm fires once

signal.signal(signal.SIGALRM, fail_open)
signal.alarm(13)
try:
    with os.fdopen(3, encoding="utf-8", errors="replace") as _fh:
        _raw = _fh.read()
except OSError:
    _raw = ""
try:
    d = json.loads(_raw.strip() or "{}")
except ValueError:
    sys.exit(0)
tp, sid = d.get("transcript_path") or "", str(d.get("session_id") or "")
repo, devkit = os.environ.get("WMG_REPO") or ".", os.environ.get("WMG_DEVKIT") or ""
if not tp or not os.path.isfile(tp) or not sid or not devkit:
    sys.exit(0)

def git(*args, cwd=repo):
    try:
        r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None   # a hung or missing git reads as "cannot say": that worktree is skipped (fail-open)
    return r.stdout.strip() if r.returncode == 0 else None

gdir, common = git("rev-parse", "--absolute-git-dir"), git("rev-parse", "--path-format=absolute", "--git-common-dir")
if not gdir or not common or os.path.realpath(gdir) != os.path.realpath(common):
    sys.exit(0)   # not a git checkout, or a linked worktree (a worker: its leader brings the work back)

# Session start; the worktree-related transcript lines (a worktree the session never mentioned is someone
# else's: the user's, Codex's, a parallel session's); subagent worktrees reported back in a completion
# (<worktreePath>) versus still running (only in subagents/*.meta.json — never pull those in).
start, finished, mentions, enter_ids = None, set(), [], set()

def added_paths(cmd):
    """Path arguments of every 'worktree add' in a shell command, absolute (relative ones from the repo)."""
    try:
        words = shlex.split(cmd.replace("&&", " ; ").replace("||", " ; "), posix=True)
    except ValueError:
        return []
    out = []
    for i in range(len(words) - 1):
        if words[i] != "worktree" or words[i + 1] != "add":
            continue
        rest, j = words[i + 2:], 0
        while j < len(rest) and rest[j] not in (";", "|"):
            w = rest[j]
            if w in ("-b", "-B", "--reason", "--orphan"):
                j += 2
                continue
            if not w.startswith("-"):
                out.append(os.path.normpath(os.path.join(repo, os.path.expandvars(os.path.expanduser(w)))))
                break
            j += 1
    return out
with open(tp, encoding="utf-8", errors="replace") as f:
    for raw in f:
        if start is None and '"timestamp"' in raw:
            try:
                ts = json.loads(raw).get("timestamp")
                start = datetime.datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp()
            except (ValueError, TypeError, AttributeError):
                pass
        if "orktree" not in raw:
            continue
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        content = (e.get("message") or {}).get("content") or []
        if e.get("type") == "user":
            # <worktreePath> counts in what the USER side said (a subagent's completion notice arrives as text), never inside a tool_result: the
            # same tag in a tool's output is data the agent read, not a worktree the session made (and the gate now merges what it owns)
            for tx in [content] if isinstance(content, str) else [c if isinstance(c, str) else c.get("text", "") for c in content
                                                                 if isinstance(c, str) or (isinstance(c, dict) and c.get("type") == "text")]:
                finished.update(m.strip() for m in re.findall(r"<worktreePath>([^<]+)</worktreePath>", str(tx)))
            # Tool OUTPUT (a 'git worktree list') names everyone's worktrees; only EnterWorktree's own result counts.
            for c in content if isinstance(content, list) else []:
                if isinstance(c, dict) and c.get("type") == "tool_result" and c.get("tool_use_id") in enter_ids:
                    mentions.append(json.dumps(c.get("content"), ensure_ascii=False))
            continue
        if e.get("type") != "assistant":
            continue
        for c in content if isinstance(content, list) else []:
            if not (isinstance(c, dict) and c.get("type") == "tool_use"):
                continue
            inp = c.get("input") or {}
            if c.get("name") == "EnterWorktree":
                enter_ids.add(c.get("id"))
                where = inp.get("path") or (os.path.join(".claude", "worktrees", inp["name"]) if inp.get("name") else "")
                if where:
                    mentions.append(os.path.normpath(os.path.join(repo, where)))
            elif c.get("name") == "Bash" and "worktree add" in str(inp.get("command") or ""):
                mentions.extend(added_paths(str(inp.get("command"))))
mentions = "\n".join(mentions)

def mentioned(path, real):
    forms = {path, real, real[len("/private"):] if real.startswith("/private/") else real}
    return any(re.search(re.escape(f) + r"(?![\w.-])", mentions) for f in forms)   # whole path: wt-ne is not wt-new
meta_paths = set()
for meta in glob.glob(os.path.join(os.path.splitext(tp)[0], "subagents", "*.meta.json")):
    try:
        with open(meta, encoding="utf-8") as mf:
            wp = json.load(mf).get("worktreePath")
    except (OSError, ValueError, AttributeError):
        continue
    if isinstance(wp, str) and wp:
        meta_paths.add(os.path.realpath(wp))
finished = {os.path.realpath(p) for p in finished}
running = meta_paths - finished

sys.path[:0] = [os.path.join(devkit, "scripts", "git"), os.path.join(devkit, "scripts", "governance"), os.path.join(devkit, "scripts"), os.path.join(devkit, "bin")]
# An import that fails is not a reason to pass before we know whether there is anything to protect: responsibility is computed first,
# and the failure is raised at the inventory call below, where it holds the Stop only when a responsible worktree exists.
wt, session_lock, import_error, lock_error = None, None, None, None
try:
    import worktree as wt
except (Exception, SystemExit) as e:
    wt, import_error = None, e
try:
    import session_lock
except (Exception, SystemExit) as e:
    session_lock, lock_error = None, e   # without it a lock held by another live session is not seen: more worktrees count as ours (held, capped), and the hold text says so

state_path = os.path.join(repo, ".claude", "audit-gate", "worktree_merge_gate.state")
try:
    with open(state_path, encoding="utf-8") as sf:
        state = json.load(sf)
    state = state if isinstance(state, dict) else {}
except (OSError, ValueError):
    state = {}
sessions = state.get("sessions") if isinstance(state.get("sessions"), dict) else {}
owners = {p: o for p, o in state["owners"].items() if isinstance(p, str) and isinstance(o, str)} if isinstance(state.get("owners"), dict) else {}
listed = git("worktree", "list", "--porcelain")
if listed is None:
    # A failed or timed-out list is not "there are no worktrees". Filtering owed by an empty
    # live set used to save owed: [] and the next Stop had nothing left to hold.
    paths, live = [], set()
    owed = {p for p in (state.get("owed") or []) if isinstance(p, str)}
else:
    paths = [l[len("worktree "):] for l in listed.splitlines() if l.startswith("worktree ")][1:]
    live = {os.path.realpath(p) for p in paths if os.path.isdir(p)}
    owed = {p for p in (state.get("owed") or []) if isinstance(p, str) and p in live}   # a held worktree stays owed until removed

# Decide responsibility first (cheap), then inventory only those worktrees (git status per worktree is the cost).
here = os.path.realpath(str(d.get("cwd") or repo))
now, pending, want = time.time(), [], []

def session_alive(owner):
    """True when session `owner` is registered here and still working (same staleness rules as session_lock.get_active_sessions).
    Anything unknown reads as not alive: the debt then falls to the session asking, as it always did."""
    if session_lock is None or not owner or os.sep in owner:
        return False
    try:
        sdir, _top = session_lock.sessions_dir(repo)
        info = session_lock.read_lock(os.path.join(sdir, owner + ".json")) if sdir else None
        if not info:
            return False
        pid = info.get("pid")
        if pid and not session_lock.is_pid_alive(pid):
            return False
        return now - float(info.get("heartbeat") or 0) <= (600.0 if pid else 180.0)
    except (Exception, SystemExit):
        return False

def unknown_row(path, reason, kind):
    """A worktree the gate could not judge: it counts as holding work (held), listed with the reason. kind: gitdir | error."""
    return {"path": path, "branch": None, "detached": False, "dirty": None, "ahead": None, "reflog": None, "busy": None,
            "unreachable": False, "unintegrated": True, "reason": reason, "kind": kind}

def gone(path):
    """The folder is missing AND git no longer lists the worktree (worktree remove takes both): another merge finished it. Unsure: not gone."""
    if os.path.isdir(path):
        return False
    now_listed = git("worktree", "list", "--porcelain")
    if now_listed is None:
        return False   # cannot say: keep the hold
    reg = [l[len("worktree "):] for l in now_listed.splitlines() if l.startswith("worktree ")]
    return path not in reg and os.path.realpath(path) not in {os.path.realpath(p) for p in reg}

def in_main(sha):
    """The commit is in the main checkout's HEAD (the trunk). No sha, a git error or a timeout: False (keep the hold)."""
    if not sha:
        return False
    try:
        return subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", sha, "HEAD"], capture_output=True, timeout=5).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False

def work_in_main(r, base):
    """The commits a gone worktree could still give back are in main: no commit only its reflog names (inventory `reflog`: [] = none,
    None = cannot say) and the HEAD seen before (`base`) is in main. A merge only adds commits on top of `base`, so a landed worktree
    always has `base` in main; a branch tip is never looked at (a rewound branch's tip can be in main while its commit is not). Commits
    not in main keep the Stop held (the hold says to bring them back). Uncommitted files of a folder that is gone cannot be brought back
    by any hold."""
    return r.get("reflog") == [] and in_main(base)

def landed(r):
    """Another merge finished this worktree: folder AND registration gone, and its work is in main (HEAD read just before this Stop's
    merge). Anything less is no proof the work reached trunk (an rm -rf + prune of unmerged commits): keep the hold."""
    return gone(r["path"]) and work_in_main(r, r.get("_head"))

# HEAD of each worktree as `git worktree list` read it before the inventory: what must be in main if its folder is gone afterwards
listed_heads, listed_branch, _cur = {}, {}, None
for _l in (listed or "").splitlines():
    if _l.startswith("worktree "):
        _cur = _l[len("worktree "):]
    elif _l.startswith("HEAD ") and _cur:
        listed_heads[_cur] = listed_heads[os.path.realpath(_cur)] = _l[len("HEAD "):]
    elif _l.startswith("branch refs/heads/") and _cur:
        listed_branch[_cur] = listed_branch[os.path.realpath(_cur)] = _l[len("branch refs/heads/"):]

def vanished_done(r):
    """A row whose folder vanished after the inventory is done when it was integrated already, or its work is in main (work_in_main,
    from the HEAD `git worktree list` showed before the inventory)."""
    if not r.get("unintegrated"):
        return True
    return work_in_main(r, listed_heads.get(r["path"]) or listed_heads.get(os.path.realpath(r["path"])))

if listed is None:
    # Keep the debt and anything this session named. Do not save an empty list over a debt we could not re-read.
    named = list(finished)
    named.extend(re.findall(r"(/[^\s\"'<>]+)", mentions))
    hold, seen = [], set()
    for p in list(owed) + named:
        rp = os.path.realpath(p) if p else ""
        if rp and rp not in seen:
            seen.add(rp)
            hold.append(rp)
    if not hold:
        sys.exit(0)
    pending = [unknown_row(p, "git worktree list failed", "error") for p in hold]
    owed = set(hold)
    paths = []

def gone_admin_dir(path):
    """The admin dir (<common>/worktrees/<id>) git keeps for a registered worktree until a prune; None when not found."""
    try:
        names = os.listdir(os.path.join(common, "worktrees"))
    except OSError:
        return None
    for d in names:
        adm = os.path.join(common, "worktrees", d)
        try:
            with open(os.path.join(adm, "gitdir"), encoding="utf-8") as fh:
                wt_dir = os.path.dirname(os.path.normpath(os.path.join(adm, fh.read().strip())))   # --relative-paths stores ../../..
        except OSError:
            continue
        if wt_dir == path or os.path.realpath(wt_dir) == os.path.realpath(path):
            return adm
    return None

gone_rows = []   # [{realpath: inventory row} or None], filled once by gone_reflog

def gone_reflog(path):
    """The commits only the HEAD reflog of a registered worktree whose folder is gone names (inventory() reads that reflog from the admin
    dir git keeps until a prune: docs/issues-bugs.md A.2 #3): [] none, None cannot say. ONE inventory, at the first call, for every deleted
    folder this session made, named or owes (the main loop's test; another session's or an old registration never spends this hook's
    alarm) and always for `path` (an empty `only` would mean every worktree); budget 0: the checks that clear a worktree are
    gone_folder_reason's own. No row while a fresh listing still shows the path is "cannot say"; only its absence there proves it
    unregistered (its reflog went with it)."""
    if not gone_rows:
        rows = None
        if wt is not None:
            mine = [p for p in paths if not os.path.exists(p)
                    and (os.path.realpath(p) in finished or os.path.realpath(p) in raw_owed or mentioned(p, os.path.realpath(p)))]
            try:
                rows = {os.path.realpath(r["path"]): r for r in wt.inventory(repo, only=mine + ([] if path in mine else [path]), budget=0)}
            except (Exception, SystemExit):
                rows = None
        gone_rows.append(rows)
    if gone_rows[0] is None:
        return None
    row = gone_rows[0].get(os.path.realpath(path))
    if row is None:
        return [] if gone(path) else None
    return row.get("reflog")

def gone_folder_reason(path):
    """A registered worktree whose folder is gone (rm -rf from outside, no prune): '' when the HEAD `git worktree list` showed is in
    main, or main holds the same patches (brought back with diff | git apply, cherry-picked, amended and merged), and no commit is named
    only by its HEAD reflog (gone_reflog); else why it is held, naming the commit to bring back. A git error, or worktree.py not
    importable, is "cannot say", which holds."""
    base = listed_heads.get(path) or listed_heads.get(os.path.realpath(path))
    if not base:
        return "thư mục đã bị xoá và git không còn biết HEAD của nó: không biết commit đã về main chưa"
    lost = gone_reflog(path)
    if lost is None:
        return "thư mục đã bị xoá và không đọc được reflog của nó: không biết còn commit nào chỉ reflog đó giữ"
    if lost:
        return (f"thư mục đã bị xoá nhưng {len(lost)} commit chỉ còn trong reflog của nó (không nhánh nào giữ, main chưa có), "
                f"mới nhất {lost[0][:10]}: giữ bằng nhánh `git -C {shlex.quote(repo)} branch rescue/<tên> {lost[0][:10]}` rồi đem về")
    if in_main(base):
        return ""
    out = git("rev-list", "--cherry-pick", "--right-only", "--no-merges", "HEAD..." + base)
    if out is None:
        return "thư mục đã bị xoá và git không so được commit của nó với main"
    if not out:
        return ""
    if wt is not None:   # several commits brought back as ONE squashed diff: the same checks inventory uses for a live worktree
        try:
            mh = git("rev-parse", "HEAD")
            if mh and not wt._empty_commit_between(repo, mh, base) and (
                    wt._patch_already_in_main(repo, mh, base) or wt._adds_nothing_to_main(repo, mh, base)):
                return ""
        except (Exception, SystemExit):   # cannot say: keep the hold below
            pass
    sha = out.split()[0]
    branch = listed_branch.get(path) or listed_branch.get(os.path.realpath(path))
    how = f"merge nhánh {branch}" if branch else f"git cherry-pick {sha[:10]}"
    return f"thư mục đã bị xoá nhưng commit {sha[:10]} chưa có trong main: đem về ({how})"

raw_owed = {os.path.realpath(p) for p in (state.get("owed") or []) if isinstance(p, str)}   # owed before the live filter
for path in paths:
    real = os.path.realpath(path)
    if real in running:
        continue
    if real not in live:
        # Registered, folder gone before this Stop (Antigravity T0035 round 4: it was skipped and dropped from the debt, and the Stop
        # passed with its commit not in main; tests/gates/test_worktree_merge_gate_vanished.sh cases 8-8d). Same owner rules as a live one.
        if os.path.exists(path) or not (real in finished or real in raw_owed or mentioned(path, real)):
            continue
        if owners.get(real) not in (None, sid) and session_alive(owners[real]):
            owed.add(real)   # kept in the debt (the live filter dropped it): its owner or a later session still sees it
            continue   # another live session's worktree: not a bystander's to hold on or take over
        adm = gone_admin_dir(path)
        if adm and session_lock is not None and not session_lock.is_free_for(session_lock.read_lock(os.path.join(adm, session_lock.LOCK)),
                                                                             sid, now, idle_frees=False):
            owed.add(real)
            continue
        why = gone_folder_reason(path)
        if why:
            owners[real] = sid   # a dead or no owner: this session is held on it, so it is its debt now (a live other owner left above)
            owed.add(real)
            row = unknown_row(path, why, "gone")
            row["branch"] = listed_branch.get(path) or listed_branch.get(real)
            pending.append(row)
        continue
    admin = git("rev-parse", "--absolute-git-dir", cwd=path)
    if not admin:
        # no git dir, so no creation time and no lock to read: responsible when the session made, named or owes it. Held, never skipped.
        if real in finished or real in owed or mentioned(path, real):
            pending.append(unknown_row(path, "cannot determine its git dir", "gitdir"))
        continue
    try:
        created = os.path.getmtime(os.path.join(admin, "commondir"))
    except OSError:
        created = None
    made_here = (start is not None and created is not None and created >= start
                 and mentioned(path, real))
    if real not in finished and real not in owed and not made_here:
        continue   # not made, named or owed by this session: not its work
    if real in finished or made_here:
        owners[real] = sid   # this session made or named it: its debt
    elif owners.get(real) not in (None, sid) and session_alive(owners[real]):
        continue   # owed because ANOTHER session was held on it, and that session is still working: not a bystander's to merge or remove
    if session_lock is not None and not session_lock.is_free_for(session_lock.read_lock(os.path.join(admin, session_lock.LOCK)), sid, now,
                                                                  idle_frees=False):
        continue   # another live session works there (an idle one too: it is alive and may come back to it)
    if here == real or here.startswith(real + os.sep):
        owed.add(real)   # the session is in it right now (EnterWorktree, or a cd to look): owed, held once it leaves
        continue
    owners[real] = sid   # held now: it is this session's to bring back (a dead owner's debt is adopted)
    want.append(path)
try:   # ONE inventory for all of them (the ref tips are read once, not once per worktree)
    if want:
        if wt is None:
            raise import_error or ImportError("worktree.py")
        pending += wt.inventory(repo, only=want)   # unintegrated → bring it back; integrated but still there → remove it
except (Exception, SystemExit) as e:
    # something to protect and the gate cannot judge it: HOLD (through the same counter and cap below), never pass
    if isinstance(e, SystemExit):   # die() = exit 2, a failing git = exit 1 with a message: say what happened
        why = "worktree.py called exit(" + str(e.code)[:120].replace(chr(10), " ") + ")"
    else:
        why = type(e).__name__ + ": " + str(e)[:160].replace(chr(10), " ")
    pending += [unknown_row(w, "gate error: " + why, "error") for w in want]
# A worktree whose folder is gone by now was removed since the inventory: the background merge of the last Stop finished its last step
# while this Stop was reading it (tests/gates/test_worktree_merge_gate_vanished.sh). That is what this gate asks for, so its row is
# done, not a hold ("merged, remove it" for a path that no longer exists). A row with a reason (the gate could not judge it) stays, and so
# does one whose work is not provably in main (vanished_done: an rm -rf from outside must not pass the Stop; same test, case 4).
vanished = [r for r in pending if not r.get("reason") and not os.path.isdir(r["path"]) and vanished_done(r)]
if vanished:
    pending = [r for r in pending if r not in vanished]
    for r in vanished:
        owed.discard(os.path.realpath(r["path"]))
        owners.pop(os.path.realpath(r["path"]), None)

am_done, am_running = [], []
if pending and wt is not None and os.environ.get("WORKTREE_AUTO_MERGE", "1") != "0":
    cand = [r for r in pending if not r.get("reason") and r.get("busy") in (None, "merge") and os.path.isdir(r["path"])]
    main_free = session_lock is not None and session_lock.is_free_for(session_lock.read_lock(os.path.join(gdir, session_lock.LOCK)), sid, now,
                                                                      idle_frees=False)   # an idle holder of main is still there
    if cand and not main_free:
        for r in cand:
            r["am"] = "main checkout đang do phiên khác giữ: phiên đó (hoặc phiên sau) sẽ tự gộp; phiên này không ghi vào main"
    elif cand:
        script = os.path.join(devkit, "scripts", "git", "worktree.py")
        runs = []
        for r in cand:
            r["_head"] = git("rev-parse", "HEAD", cwd=r["path"])   # for landed(): what must be in main if the folder is gone afterwards
            out_path = os.path.join(gdir, "devkit-automerge-" + hashlib.sha1(r["path"].encode()).hexdigest()[:10] + ".out")
            try:
                with open(out_path, "w", encoding="utf-8") as fh:
                    proc = subprocess.Popen([sys.executable, script, "automerge", r["path"]], cwd=repo, stdout=fh, stderr=subprocess.STDOUT,
                                            stdin=subprocess.DEVNULL, start_new_session=True)
                runs.append((r, proc, out_path))
            except OSError as e:
                r["am"] = "không chạy được tự gộp: " + str(e)[:120]
        try:
            wait = float(os.environ.get("WORKTREE_AUTO_MERGE_WAIT_S", "9"))
        except ValueError:
            wait = 9.0
        deadline = time.time() + max(0.5, min(wait, signal.getitimer(signal.ITIMER_REAL)[0] - 1.5))   # never past the alarm (it would pass the Stop silently)
        while runs and any(p.poll() is None for _r, p, _o in runs) and time.time() < deadline:
            time.sleep(0.2)
        for r, proc, out_path in runs:
            real_path = os.path.realpath(r["path"])
            if proc.poll() is None:
                am_running.append(r["path"])
                pending.remove(r)
                owed.add(real_path)   # still owed: a conflict it ends in must be found by the next Stop
                continue
            tail = []
            try:
                with open(out_path, encoding="utf-8", errors="replace") as fh:
                    tail = fh.read().strip().splitlines()
                res = json.loads(next(l for l in reversed(tail) if l.startswith("{")))
            except (OSError, ValueError, StopIteration):
                res = {"status": "blocked", "message": "tự gộp không trả kết quả: " + " | ".join(tail[-3:])[:300]}
            if res.get("running"):   # another process is merging this very worktree: not a failure, not a hold
                am_running.append(r["path"])
                pending.remove(r)
                owed.add(real_path)
                continue
            # landed(): the previous Stop's background merge landed this worktree and removed it while this run read it, so this run
            # died on the missing folder (tests/gates/test_worktree_merge_gate_vanished.sh, cases 2 and 3): done, not a hold
            if res.get("status") in ("merged", "nothing") or landed(r):
                am_done.append(r["path"])
                pending.remove(r)
                owed.discard(real_path)
                owners.pop(real_path, None)
            else:
                r["am"] = str(res.get("message") or res.get("status"))
                r["am_status"] = res.get("status")

def save():
    try:
        os.makedirs(os.path.dirname(state_path), exist_ok=True)
        tmp = f"{state_path}.{os.getpid()}.tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"owed": sorted(owed), "sessions": dict(list(sessions.items())[-50:]),
                       "owners": {p: o for p, o in owners.items() if p in owed}}, f)
        os.replace(tmp, state_path)
        return True
    except OSError:
        return False

if not pending:
    if set(state.get("owed") or []) != owed or am_done:
        save()   # removed worktrees leave the debt list
    notes = ["✔ đã tự gộp vào main và gỡ: " + p for p in am_done] + ["… đang tự gộp ở nền (kết quả: lần dừng sau; log trong git dir): " + p for p in am_running]
    if notes:
        print(json.dumps({"systemMessage": "WORKTREE-MERGE GATE:\n" + "\n".join(notes)}, ensure_ascii=False))
    sys.exit(0)
owed |= {os.path.realpath(r["path"]) for r in pending}

fp = hashlib.sha1(json.dumps(sorted(r["path"] for r in pending)).encode()).hexdigest()   # the paths only: neither the counts nor the CAUSE (an error row, a merged-but-present row) may reset the cap, so 3 holds bound any mix of causes
mine = sessions.get(sid) if isinstance(sessions.get(sid), dict) else {}
held = mine.get("n", 0) if mine.get("fp") == fp else 0

def line(r):
    where = r["branch"] or "(detached)"
    if r.get("am"):
        return f"  - {r['path']} [{where}]: {r['am']}"
    if not r["unintegrated"]:
        return f"  - {r['path']} [{where}] đã gộp xong — XOÁ: agent-kit worktree remove {r['path']}"
    lost = "  ⚠ commit không nằm trên nhánh nào — xoá worktree là MẤT" if r["unreachable"] else ""
    if r.get("kind") == "gone":
        return f"  - {r['path']} [{where}] {r['reason']}"
    if r.get("reason"):
        return f"  - {r['path']} [?] không kiểm tra được ({r['reason']})"
    return f"  - {r['path']} [{where}] ahead={'?' if r['ahead'] is None else r['ahead']} dirty={'?' if r['dirty'] is None else r['dirty']}{lost}"

listing = "\n".join(line(r) for r in pending)
could_not_run = any(r.get("reason") and r.get("kind") != "gone" for r in pending)   # "gone": checked, a commit is missing
lock_note = ("⚠ session_lock.py không import được (" + type(lock_error).__name__ + "): khóa của phiên khác không thấy được, nên worktree của phiên khác có thể bị tính nhầm là của phiên này.\n"
             if session_lock is None else "")
if held >= 3:
    save()   # the debt survives the cap: the next session is held on it
    head = ("⚠ WORKTREE-MERGE GATE: cổng KHÔNG chạy được (lỗi nội bộ / không đọc được git dir) nên không biết worktree còn việc CHƯA về trunk hay không:\n"
            if could_not_run else "⚠ WORKTREE-MERGE GATE: phiên dừng khi worktree vẫn còn việc CHƯA về trunk:\n")
    advice = "`git worktree list` (kiểm tra bằng tay)" if could_not_run else "`agent-kit worktree finish <path>` (tự gộp + gỡ) hoặc `agent-kit worktree status`"
    print(json.dumps({"systemMessage": head + listing + "\n" + lock_note + "Đem về trước khi làm tiếp: " + advice + "."}, ensure_ascii=False))
    sys.exit(0)
sessions[sid] = {"fp": fp, "n": held + 1}
if not save():
    sys.exit(0)   # cannot count the holds: never risk blocking every stop

# What to do now: a CONFLICT is resolved in the worktree (its own folder: safe), then the next Stop finishes the merge by itself.
conflicts = [r for r in pending if r.get("am_status") == "conflict"]
finish_cmds = "".join(f"  agent-kit worktree finish {shlex.quote(r['path'])}\n" for r in pending if r["unintegrated"] and not r.get("reason"))
if conflicts:
    how_to = ("XUNG ĐỘT khi tự gộp: sửa NGAY trong worktree (thư mục riêng, không ảnh hưởng ai): bỏ dấu <<<<<<< ======= >>>>>>> giữ đúng ý cả hai bên, "
              "`git -C <worktree> add <file>`. Rồi dừng lại: cổng tự kết thúc merge, fast-forward main và gỡ worktree. Không cần chạy lệnh nào khác "
              "(muốn chạy ngay: lệnh dưới đây).\n" + finish_cmds)
elif finish_cmds:
    how_to = "Tự gộp chưa chạy/không xong (lý do ở trên). Chạy lại bằng một lệnh, từ main checkout:\n" + finish_cmds
else:
    how_to = ""
# A detached worktree (the `agent-kit worktree add` default) has no branch to merge: only the diff | apply way.
merge_hint = "     (hoặc: git merge --no-edit <branch>)" if any(r["branch"] for r in pending) else ""
detached_note = ("  (worktree [(detached)] không có nhánh để merge: dùng diff | git apply --3way rồi commit ở main checkout)\n"
                 if any(not r["branch"] and not r.get("reason") for r in pending) else "")
error_note = lock_note
if any(r.get("kind") == "gone" for r in pending):
    error_note += ("⚠ Worktree bị xoá thư mục khi commit chưa về main: đem commit đó về trước. ĐỪNG chạy `git worktree prune` trước khi đem về "
                   "(với worktree detached, prune xoá luôn reflog đang giữ commit; gc sau đó xoá hẳn).\n")
if could_not_run:
    error_note += "⚠ Cổng KHÔNG chạy được cho các worktree có lý do ở trên."
    if any(r.get("kind") == "error" for r in pending):
        error_note += " Lỗi git/cài đặt: sửa rồi dừng lại."
    if any(r.get("kind") == "gitdir" for r in pending):
        error_note += (" Worktree có con trỏ .git hỏng hoặc mất (agent-kit worktree remove từ chối vì không đọc được trạng thái của nó): người dùng chạy `git worktree prune` "
                       "SAU KHI kiểm tra thư mục đó đã mất hoặc không còn cần.")
    error_note += (" WORKTREE_MERGE_GATE=0 phải đặt trong môi trường TRƯỚC khi khởi động phiên (không đặt được cho một lần dừng của phiên đang chạy); "
                   "sau 3 lần giữ cổng vẫn cho qua.\n")
sys.stderr.write(
    "⛔ WORKTREE-MERGE GATE: worktree phải được GỘP vào nhánh chính rồi XOÁ trước khi dừng — để lại là trunk thiếu code:\n"
    + listing + "\n" + error_note +
    how_to +
    "Làm tay nếu cần, từ main checkout:\n"
    "  agent-kit worktree diff <path> | git apply --3way" + merge_hint + "\n" + detached_note +
    "  agent-kit worktree remove <path>\n"
    f"Lần giữ {held + 1}/3 cho cùng danh sách; WORKTREE_MERGE_GATE=0 (đặt TRƯỚC khi khởi động phiên) để tắt.\n")
sys.exit(2)
PY
rc=$?
[ "${rc}" -eq 2 ] && exit 2
exit 0
