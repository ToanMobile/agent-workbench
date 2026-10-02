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
# The rule is MERGE, THEN REMOVE: a worktree whose work is integrated but that still exists also
# holds the Stop (`agent-kit worktree remove` refuses while work is left, so nothing is lost).
# A worktree a session was held on is OWED (.claude/audit-gate/worktree_merge_gate.state) until it
# is gone: every later session of the repo is held on it too, not only the one that made it.
# At most 3 holds per session and pending set, then the Stop passes with a systemMessage (a merge
# conflict that needs the user must never trap the session); the debt stays for the next session,
# and session_context.sh names each unintegrated worktree at every start.
# Fail-open on any error or after 8 s. Off: WORKTREE_MERGE_GATE=0.
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
WMG_INPUT="${INPUT}" WMG_REPO="${REPO_ROOT}" WMG_DEVKIT="${DEVKIT}" python3 <<'PY'
import datetime, glob, hashlib, json, os, re, shlex, signal, subprocess, sys, time

def fail_open(*_):
    os._exit(0)   # not SystemExit: worktree.py catches that around git calls, and the alarm fires once

signal.signal(signal.SIGALRM, fail_open)
signal.alarm(8)
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
        finished.update(m.strip() for m in re.findall(r"<worktreePath>([^<]+)</worktreePath>", raw))
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        content = (e.get("message") or {}).get("content") or []
        if e.get("type") == "user":
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
try:
    import worktree as wt
    import session_lock
except (Exception, SystemExit):
    sys.exit(0)

state_path = os.path.join(repo, ".claude", "audit-gate", "worktree_merge_gate.state")
try:
    with open(state_path, encoding="utf-8") as sf:
        state = json.load(sf)
    state = state if isinstance(state, dict) else {}
except (OSError, ValueError):
    state = {}
sessions = state.get("sessions") if isinstance(state.get("sessions"), dict) else {}
paths = [l[len("worktree "):] for l in (git("worktree", "list", "--porcelain") or "").splitlines()
         if l.startswith("worktree ")][1:]
live = {os.path.realpath(p) for p in paths if os.path.isdir(p)}
owed = {p for p in (state.get("owed") or []) if isinstance(p, str) and p in live}   # a held worktree stays owed until removed

# Decide responsibility first (cheap), then inventory only those worktrees (git status per worktree is the cost).
here = os.path.realpath(str(d.get("cwd") or repo))
now, pending = time.time(), []
for path in paths:
    real = os.path.realpath(path)
    if real not in live or real in running:
        continue
    admin = git("rev-parse", "--absolute-git-dir", cwd=path)
    if not admin:
        continue
    try:
        created = os.path.getmtime(os.path.join(admin, "commondir"))
    except OSError:
        created = None
    made_here = (start is not None and created is not None and created >= start
                 and mentioned(path, real))
    if real not in finished and real not in owed and not made_here:
        continue   # not made, named or owed by this session: not its work
    if not session_lock.is_free_for(session_lock.read_lock(os.path.join(admin, session_lock.LOCK)), sid, now):
        continue   # another live session works there
    if here == real or here.startswith(real + os.sep):
        owed.add(real)   # the session is in it right now (EnterWorktree, or a cd to look): owed, held once it leaves
        continue
    try:
        pending += wt.inventory(repo, only=path)   # unintegrated → bring it back; integrated but still there → remove it
    except (Exception, SystemExit):
        sys.exit(0)

def save():
    try:
        os.makedirs(os.path.dirname(state_path), exist_ok=True)
        tmp = f"{state_path}.{os.getpid()}.tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"owed": sorted(owed), "sessions": dict(list(sessions.items())[-50:])}, f)
        os.replace(tmp, state_path)
        return True
    except OSError:
        return False

if not pending:
    if set(state.get("owed") or []) != owed:
        save()   # removed worktrees leave the debt list
    sys.exit(0)
owed |= {os.path.realpath(r["path"]) for r in pending}

fp = hashlib.sha1(json.dumps(sorted((r["path"], r["unintegrated"]) for r in pending)).encode()).hexdigest()   # counts change while work goes on: not in the key
mine = sessions.get(sid) if isinstance(sessions.get(sid), dict) else {}
held = mine.get("n", 0) if mine.get("fp") == fp else 0

def line(r):
    where = r["branch"] or "(detached)"
    if not r["unintegrated"]:
        return f"  - {r['path']} [{where}] đã gộp xong — XOÁ: agent-kit worktree remove {r['path']}"
    lost = "  ⚠ commit không nằm trên nhánh nào — xoá worktree là MẤT" if r["unreachable"] else ""
    return f"  - {r['path']} [{where}] ahead={'?' if r['ahead'] is None else r['ahead']} dirty={'?' if r['dirty'] is None else r['dirty']}{lost}"

listing = "\n".join(line(r) for r in pending)
if held >= 3:
    save()   # the debt survives the cap: the next session is held on it
    print(json.dumps({"systemMessage": "⚠ WORKTREE-MERGE GATE: phiên dừng khi worktree vẫn còn việc CHƯA về trunk:\n"
                      + listing + "\nĐem về trước khi làm tiếp: `agent-kit worktree status`."}, ensure_ascii=False))
    sys.exit(0)
sessions[sid] = {"fp": fp, "n": held + 1}
if not save():
    sys.exit(0)   # cannot count the holds: never risk blocking every stop

sys.stderr.write(
    "⛔ WORKTREE-MERGE GATE: worktree phải được GỘP vào nhánh chính rồi XOÁ trước khi dừng — để lại là trunk thiếu code:\n"
    + listing + "\n"
    "Đem về từ main checkout, kiểm diff, commit, rồi dọn:\n"
    "  agent-kit worktree diff <path> | git apply --3way     (hoặc: git merge --no-edit <branch>)\n"
    "  agent-kit worktree remove <path>\n"
    f"Lần giữ {held + 1}/3 cho cùng danh sách; WORKTREE_MERGE_GATE=0 để tắt.\n")
sys.exit(2)
PY
rc=$?
[ "${rc}" -eq 2 ] && exit 2
exit 0
