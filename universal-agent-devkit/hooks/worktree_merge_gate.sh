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
WMG_INPUT="${INPUT}" WMG_REPO="${REPO_ROOT}" WMG_DEVKIT="${DEVKIT}" python3 -I <<'PY'
import datetime, glob, hashlib, json, os, re, shlex, signal, subprocess, sys, time

def fail_open(*_):
    os._exit(0)   # not SystemExit: worktree.py catches that around git calls, and the alarm fires once

signal.signal(signal.SIGALRM, fail_open)
signal.alarm(13)
try:
    d = json.loads(os.environ.get("WMG_INPUT") or "{}")
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

for path in paths:
    real = os.path.realpath(path)
    if real not in live or real in running:
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
            if res.get("status") in ("merged", "nothing"):
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
    if r.get("reason"):
        return f"  - {r['path']} [?] không kiểm tra được ({r['reason']})"
    return f"  - {r['path']} [{where}] ahead={'?' if r['ahead'] is None else r['ahead']} dirty={'?' if r['dirty'] is None else r['dirty']}{lost}"

listing = "\n".join(line(r) for r in pending)
could_not_run = any(r.get("reason") for r in pending)
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
