#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# worktree_guard.sh — PreToolUse hook on Bash and Edit|Write|MultiEdit|NotebookEdit: a session or agent
# that works in a git WORKTREE must not write into the MAIN checkout of that repo.
#
# WHY (2026-09-25). A subagent told to work in a worktree issued commands without
# `cd`; its shell was in the main checkout and it overwrote files there. Nothing
# stopped it: every other gate asks WHAT is written, none asks WHERE.
#
# WHO HAS A WORKTREE ("declared"), strongest signal first:
#   1. DEVKIT_WORKTREE=<path> in the hook environment (explicit, any agent).
#   2. A subagent (`agent_id` in the hook input) that the harness started in a
#      worktree: its meta file <transcript dir>/<session>/subagents/agent-<id>.meta.json
#      has "worktreePath", or its own transcript's first `cwd` is a linked worktree.
#   3. The SESSION STARTED inside a linked worktree: the first record that carries a `cwd`
#      in the main transcript (`transcript_path`). Not the hook input `cwd`: that one follows
#      every `cd` inside the project (measured on real transcripts), and M/.claude/worktrees/*
#      is inside the project, so a leader that `cd`s into a worktree to look at it would be
#      taken as working there and blocked on the merge-back into M.
#   4. The session ENTERED a worktree mid-session with the Claude Code tool EnterWorktree and
#      has not left it with ExitWorktree: in the main transcript, the last Enter/Exit call whose
#      tool_result is not an error (`is_error`) is an Enter → its worktree is declared (taken from
#      input.path, an absolute path in the result that is a linked worktree, or
#      M/.claude/worktrees/<input.name>). A failed call changes nothing. Checked before 3, so it
#      overrides where the session started. Names from the tool list; no real call was on disk
#      to copy (2026-09-25), so the block shape is that of other tools:
#      {"type":"tool_use","id":…,"name":…,"input":…} / {"type":"tool_result","tool_use_id":…,"is_error":…}.
#      The fast path greps `"name":"EnterWorktree","input"` (a call, not the tool's schema text).
#   These four BLOCK (exit 2). A fifth signal only WARNS: a subagent whose first
#   prompt names exactly one worktree made by `agent-kit worktree add` (it carries
#   <git dir>/devkit-worktree.json). A prompt can mention a worktree without the agent
#   being meant to stay in it, so that is a hint, not a declaration: the model gets an
#   additionalContext reminder and the call goes through.
#
# WHAT IS BLOCKED, with W = the declared worktree and M = the main checkout of its repo
# (W ≠ M): an Edit/Write whose file lies in M, and a Bash command that writes into M —
# a redirection, cp/mv/install/rsync/ln destination, rm/touch/truncate/tee/sed -i/perl -i
# operand, `dd of=`, a git write (add, commit, checkout, reset, stash push/pop/…), a build
# tool (gradle, make, npm, cargo, …) run with M as its working directory — also through an
# interpreter (`sh ./gradlew …`, `python3 -m pytest|mypy|black|pip …`) —, an interpreter
# (python, node, …) given an existing file of M as an operand after its script, and the
# same checks inside `bash|sh|zsh -c '…'`. The working directory of a Bash command is the
# hook `cwd` (where the shell is), moved by any `cd`/`pushd` in the command. "In M" means
# the nearest enclosing git tree is M itself, so M/.claude/worktrees/<other> is NOT M.
# Reads of M (cat, grep, ls, git status/diff/log/stash list, cp FROM M, scp to host:…)
# are never blocked, and neither is state that exists only in the main checkout:
# M/.claude/agent-memory and M/.claude/audit-gate (not its wg_scan/, this guard's own scan
# cache) unless git TRACKS the file, and
# M/.agents/local/memory where M's git ignores it, plus its claude-auto/ (Claude Code
# auto-memory) always. A tracked or not-ignored file there (bugs/*.md) is in W too: blocked.
#
# NOT AFFECTED: a session with no declared worktree — the common single-tree case exits
# in bash before python starts (no agent_id, no DEVKIT_WORKTREE, the session did not start
# in a linked worktree and its transcript has no EnterWorktree call). The leader that started
# in M and never called EnterWorktree has no declared worktree, also after `cd W` to look: it
# may edit M, `git merge` or `git apply` the worktree's work there.
#
# WHAT IT CANNOT SEE: a script that decides its own output path (`python3 gen.py` or
# `python3 -c "open('src/a.kt','w')…"` run in M — ponytail: interpreters are judged by their
# operands only, since blocking every one run in M stopped `python3 -c 'print(1)'`; upgrade
# to an allowlist of read-only scripts if a script write into M is ever seen), variables it
# cannot expand (`> "$OUT"`), the real shell cwd when the harness reports a different
# `cwd` than the shell uses, and `claude --resume` of a session from another directory (the
# transcript does not mark the resume, and a later `cwd` is indistinguishable from a `cd`).
#
# Escape hatch: WORKTREE_GUARD=0 (logged). Fail-open on internal error or no python3.
# PreToolUse protocol: stdin JSON; exit 2 blocks (stderr → Claude); exit 0 allows.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

INPUT="$(cat 2>/dev/null)" || INPUT=""

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"

if [ "${WORKTREE_GUARD:-1}" = "0" ]; then
  mkdir -p "${LOG_DIR}" 2>/dev/null && \
    echo "[$(date +%Y-%m-%dT%H:%M:%S)] WORKTREE_GUARD=0 — guard bypassed" >> "${LOG_DIR}/worktree_guard.log" 2>/dev/null
  exit 0
fi

RX_TOOL='"tool_name"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
[[ ${INPUT} =~ ${RX_TOOL} ]] || exit 0
case "${BASH_REMATCH[1]}" in Bash|Edit|Write|MultiEdit|NotebookEdit) ;; *) exit 0 ;; esac

# ── fast path: nothing declares a worktree → exit before python ──────────────
if [ -z "${DEVKIT_WORKTREE:-}" ]; then
  RX_AGENT='"agent_id"[[:space:]]*:[[:space:]]*"[^"]'
  if ! [[ ${INPUT} =~ ${RX_AGENT} ]]; then
    # Where the SESSION STARTED: the first transcript record that carries a cwd.
    RX_TP='"transcript_path"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
    [[ ${INPUT} =~ ${RX_TP} ]] || exit 0
    tp="${BASH_REMATCH[1]}"
    [ -f "${tp}" ] || exit 0
    # An EnterWorktree CALL (tool_use block, not the tool's schema text) → let python decide.
    # Scanned incrementally: .claude/audit-gate/wg_scan/<path> keeps "<bytes scanned> <found>", so
    # a call greps only what the transcript gained, plus 4 KB for a record cut mid-write (review
    # 2026-09-25: a full grep of a 50 MB transcript cost ~0.25 s on every tool call). A shorter
    # file than recorded (rewritten) is scanned again from the start.
    linked=0
    size="$(wc -c < "${tp}" 2>/dev/null | tr -d ' ')"
    cache="${LOG_DIR}/wg_scan/${tp//\//_}"
    off=0; seen=0
    [ -f "${cache}" ] && read -r off seen < "${cache}" 2>/dev/null
    case "${size}" in ''|*[!0-9]*) size=0 ;; esac
    case "${off}" in ''|*[!0-9]*) off=0 ;; esac
    [ "${size}" -ge "${off}" ] || { off=0; seen=0; }
    if [ "${seen}" = "1" ]; then
      linked=1
    else
      from=$(( off > 4096 ? off - 4096 : 0 ))
      tail -c +$((from + 1)) "${tp}" 2>/dev/null \
        | grep -qE '"name":[[:space:]]*"EnterWorktree"[[:space:]]*,[[:space:]]*"input"' && linked=1
      if [ "${size}" -gt 0 ]; then
        [ -d "${LOG_DIR}/wg_scan" ] || mkdir -p "${LOG_DIR}/wg_scan" 2>/dev/null
        [ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null
        printf '%s %s\n' "${size}" "${linked}" > "${cache}.$$" 2>/dev/null && mv -f "${cache}.$$" "${cache}" 2>/dev/null
      fi
    fi
    first="$(grep -m1 -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"\\]*"' "${tp}" 2>/dev/null)"
    RX_CWD='"cwd"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
    d=""
    [ "${linked}" = "0" ] && [[ ${first} =~ ${RX_CWD} ]] && d="${BASH_REMATCH[1]}"
    while [ -n "${d}" ] && [ "${d}" != "/" ]; do
      if [ -d "${d}/.git" ]; then break; fi
      if [ -f "${d}/.git" ]; then
        case "$(head -1 "${d}/.git" 2>/dev/null)" in *"/worktrees/"*) linked=1 ;; esac
        break
      fi
      d="$(dirname "${d}")"
    done
    [ "${linked}" = "1" ] || exit 0
  fi
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ worktree_guard: python3 không có — guard này KHÔNG chạy (ghi vào main checkout không bị chặn)." >&2
  exit 0
fi
mkdir -p "${LOG_DIR}" 2>/dev/null
[ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true

WG_INPUT="${INPUT}" WG_LOG="${LOG_DIR}/worktree_guard.log" WG_TS="$(date +%Y-%m-%dT%H:%M:%S)" \
python3 <<'PY'
import json, os, re, shlex, sys

log = os.environ.get("WG_LOG", "/dev/null")
ts = os.environ.get("WG_TS", "?")

def logline(s):
    try:
        with open(log, "a") as fh:
            fh.write(f"[{ts}] {s}\n")
    except Exception:
        pass

try:
    d = json.loads(os.environ.get("WG_INPUT", ""))
except Exception:
    sys.exit(0)
tool = d.get("tool_name", "")
inp = d.get("tool_input") or {}
cwd = d.get("cwd") or os.getcwd()
agent = str(d.get("agent_id") or "")
tp = str(d.get("transcript_path") or "")
sid = str(d.get("session_id") or "")

# ── git trees without a subprocess ──────────────────────────────────────────
def tree_of(path):
    """(top dir, is_linked_worktree, main checkout) of the git tree holding `path`, or None."""
    cur = os.path.realpath(path)
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
            return cur, False, cur
        if os.path.isfile(dotgit):
            try:
                line = open(dotgit).readline().strip()
            except OSError:
                return None
            if not line.startswith("gitdir:"):
                return None
            gdir = line[len("gitdir:"):].strip()
            gdir = os.path.realpath(gdir if os.path.isabs(gdir) else os.path.join(cur, gdir))
            if "/worktrees/" not in gdir:
                return cur, False, cur                      # a submodule: its own tree
            try:
                common = open(os.path.join(gdir, "commondir")).read().strip()
                common = os.path.realpath(common if os.path.isabs(common) else os.path.join(gdir, common))
            except OSError:
                common = gdir.split("/worktrees/")[0]
            main = os.path.dirname(common) if os.path.basename(common) == ".git" else None
            return cur, True, main
        up = os.path.dirname(cur)
        if up == cur:
            return None
        cur = up

# ── which worktree did this session / agent declare? ─────────────────────────
declared, source, strength = None, "", "block"
if os.environ.get("DEVKIT_WORKTREE"):
    declared, source = os.environ["DEVKIT_WORKTREE"], "DEVKIT_WORKTREE"

def agent_files(suffix):
    if not (agent and tp):
        return []
    base, name = os.path.splitext(tp)[0], f"agent-{agent}{suffix}"
    return [os.path.join(base, "subagents", name), os.path.join(os.path.dirname(tp), name),
            os.path.join(os.path.dirname(tp), sid, "subagents", name)]

agent_transcript = next((p for p in agent_files(".jsonl") if os.path.isfile(p)), None)
if not declared and agent:
    for meta in agent_files(".meta.json"):
        try:
            wp = json.load(open(meta)).get("worktreePath")
        except Exception:
            continue
        if isinstance(wp, str) and wp:
            declared, source = wp, "worktreePath (harness)"
            break
    if not declared and agent_transcript:
        try:
            with open(agent_transcript) as fh:
                for line in fh:
                    rc = json.loads(line).get("cwd")
                    if isinstance(rc, str) and rc:
                        t = tree_of(rc)
                        if t and t[1]:
                            declared, source = t[0], "agent transcript cwd"
                        break
        except Exception:
            pass
def first_cwd(path):
    """cwd of the first record that has one: where that session started."""
    try:
        with open(path) as fh:
            for line in fh:
                try:
                    rc = json.loads(line).get("cwd")
                except Exception:
                    continue
                if isinstance(rc, str) and rc:
                    return rc
    except OSError:
        pass
    return None

def entered_worktree(path):
    """Worktree of the last successful EnterWorktree/ExitWorktree call in `path` if it was an Enter."""
    calls, results = [], {}
    try:
        with open(path) as fh:
            for line in fh:                       # parse only lines that name the tool or one of its calls
                if "Worktree" not in line and not any(c["id"] in line for c in calls):
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                content = (rec.get("message") or {}).get("content")
                for b in content if isinstance(content, list) else []:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "tool_use" and b.get("name") in ("EnterWorktree", "ExitWorktree") \
                            and isinstance(b.get("id"), str) and b["id"]:
                        calls.append(b)
                    elif b.get("type") == "tool_result" and b.get("tool_use_id"):
                        results[b["tool_use_id"]] = (b, rec.get("toolUseResult"))
    except OSError:
        return None
    for call in reversed(calls):
        res = results.get(call.get("id"))
        if not res or res[0].get("is_error"):
            continue                              # no result yet, or it failed: changed nothing
        if call["name"] == "ExitWorktree":
            return None
        inp = call.get("input") if isinstance(call.get("input"), dict) else {}
        # The result names the worktree; its exact wording is not a contract, so every absolute
        # path in it is tried and only a linked worktree counts.
        text = json.dumps([res[0].get("content"), res[1]], ensure_ascii=False)
        cands = [inp.get("path")] + re.findall(r"/[^\s\"'`<>,;()\\]+", text)   # a backslash (JSON \n) ends a path
        here = tree_of(cwd)
        if isinstance(inp.get("name"), str) and here and here[2]:
            cands.append(os.path.join(here[2], ".claude", "worktrees", inp["name"]))
        for c in cands:
            if isinstance(c, str) and c:
                c = c.rstrip(".:")
                t = tree_of(c) if os.path.exists(c) else None
                if t and t[1]:
                    return t[0]
        return None
    return None

if not declared and tp:
    wp = entered_worktree(tp)
    if wp:
        declared, source = wp, "EnterWorktree"
if not declared and tp:
    # Not the hook `cwd`: it follows every `cd` inside the project, worktrees included.
    start = first_cwd(tp)
    t = tree_of(start) if start else None
    if t and t[1]:
        declared, source = t[0], "session start cwd"
if not declared and agent_transcript:
    # Warn-only hint: the agent's first prompt names exactly one `agent-kit worktree add` worktree.
    t = tree_of(cwd)
    if t and t[2]:
        prompt = ""
        try:
            with open(agent_transcript) as fh:
                for line in fh:
                    rec = json.loads(line)
                    msg = rec.get("message") or {}
                    if rec.get("type") == "user" or msg.get("role") == "user":
                        c = msg.get("content")
                        prompt = c if isinstance(c, str) else " ".join(
                            b.get("text", "") for b in (c or []) if isinstance(b, dict))
                        break
        except Exception:
            prompt = ""
        wt_root = os.path.join(t[2], ".git", "worktrees")
        named = []
        try:
            for name in os.listdir(wt_root):
                g = os.path.join(wt_root, name)
                if not os.path.isfile(os.path.join(g, "devkit-worktree.json")):
                    continue
                try:
                    wpath = os.path.dirname(open(os.path.join(g, "gitdir")).read().strip())
                except OSError:
                    continue
                if wpath and re.search(re.escape(wpath) + r"(?![\w.-])", prompt):
                    named.append(wpath)
        except OSError:
            pass
        if len(named) == 1:
            declared, source, strength = named[0], "agent prompt", "warn"
if not declared:
    sys.exit(0)

wt = tree_of(declared)
if not wt or not wt[1] or not wt[2]:
    sys.exit(0)                                   # not a linked worktree: nothing to guard
W, M = wt[0], os.path.realpath(wt[2])
if os.path.realpath(W) == M:
    sys.exit(0)

# Main-checkout-only state every agent of the repo shares, which W has no copy of. Some projects
# TRACK files under these dirs (.agents/local/memory/bugs/*.md): those are in W too, so they are
# ordinary files of M. Agent memory and hook logs: main-only unless tracked (GeelyEx2 leaves
# .claude/agent-memory untracked AND not ignored). .agents/local/memory: main-only only where M's
# git ignores it, except claude-auto/ — Claude Code's auto-memory dir, pointed at M by absolute path.
MAIN_ONLY_UNTRACKED = (".claude/agent-memory", ".claude/audit-gate")
MAIN_ONLY_IGNORED = (".agents/local/memory",)
MAIN_ONLY_ALWAYS = (".agents/local/memory/claude-auto",)

def git_ok(*args):
    """True/False from `git -C M <args>` (exit 0 / 1); None when git cannot answer."""
    try:
        import subprocess
        r = subprocess.run(["git", "-C", M] + list(args), stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    except Exception as e:
        logline(f"git {args[0]} failed: {e!r}")
        return None
    return {0: True, 1: False}.get(r.returncode)

def under(rel, dirs):
    return any(rel == d or rel.startswith(d + os.sep) for d in dirs)

def in_main(path, base):
    p = os.path.expanduser(path)
    p = p if os.path.isabs(p) else os.path.join(base, p)
    t = tree_of(p)
    if not t or os.path.realpath(t[0]) != M:
        return False
    rel = os.path.relpath(os.path.realpath(p), M)
    if under(rel, (".claude/audit-gate/wg_scan",)):   # this guard's own scan cache: never W's to write
        return True
    if under(rel, MAIN_ONLY_ALWAYS):
        return False
    if under(rel, MAIN_ONLY_UNTRACKED):           # git answers None → fail open (main-only)
        return git_ok("ls-files", "--error-unmatch", "--", rel) is True
    if under(rel, MAIN_ONLY_IGNORED):
        return git_ok("check-ignore", "-q", "--", rel) is False
    return True

# ── targets ─────────────────────────────────────────────────────────────────
hits = []
if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
    fp = inp.get("file_path") or inp.get("notebook_path") or ""
    if isinstance(fp, str) and fp and in_main(fp, cwd):
        hits.append(fp)
elif tool == "Bash":
    HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
    DEST_LAST = {"cp", "install", "rsync", "ln", "scp"}
    ALL_ARGS = {"mv", "rm", "touch", "truncate", "tee", "mkdir", "rmdir", "chmod", "unlink"}
    GIT_WRITE = {"add", "am", "apply", "checkout", "cherry-pick", "clean", "commit", "merge", "mv", "pull",
                 "rebase", "reset", "restore", "revert", "rm", "stash", "switch"}
    STASH_READ = {"list", "show", "create"}          # `git stash <these>` leaves the tree and refs alone
    # Build tools write build dirs / caches into the directory they run in, by construction.
    BUILDERS = re.compile(r"^(?:npm|npx|yarn|pnpm|bun|make|gradle|\./gradlew|gradlew|mvn|cargo|go|pytest|jest|"
                          r"vitest|dotnet|swift|flutter)$")
    # Interpreters write only what their script says: judged by the operands after the script —
    # unless the script is a build tool (`sh ./gradlew …`) or the module a builder / test runner
    # / formatter (`python3 -m pytest`), which writes caches and build dirs where it runs.
    INTERP = re.compile(r"^(?:python[\d.]*|node|deno|ruby|perl|php|bash|sh|zsh)$")
    MODULE_BUILDERS = {"pytest", "unittest", "black", "ruff", "mypy", "pip", "build", "isort", "coverage",
                       "tox", "nox", "setuptools", "pylint"}
    PREFIX = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "}", "time", "command",
              "builtin", "exec", "nohup", "sudo", "env", "done", "fi"}

    def exists(a, here):
        p = os.path.expanduser(a)
        return os.path.exists(p if os.path.isabs(p) else os.path.join(here, p))

    def scan(cmd, here, depth=0):
        """Write targets in M of a shell command run in `here`; None when it cannot be tokenised."""
        out, pos = [], 0
        while True:                               # heredoc bodies are data, not commands
            m = HEREDOC.search(cmd, pos)
            nl = cmd.find("\n", m.end()) if m else -1
            if not m or nl < 0:
                out.append(cmd[pos:])
                break
            e = re.compile(r"^[ \t]*" + re.escape(m.group(2)) + r"[ \t]*$", re.M).search(cmd, nl + 1)
            out.append(cmd[pos:nl + 1])
            pos = e.end() if e else len(cmd)
        try:
            lex = shlex.shlex("".join(out), posix=True, punctuation_chars=";&|<>()\n")
            lex.whitespace, lex.whitespace_split, lex.commenters = " \t\r", True, ""
            toks = list(lex)
        except ValueError:
            return None
        segs, cur = [], []
        for tok in toks:
            if tok and set(tok) <= set(";&|()\n"):
                if cur:
                    segs.append(cur)
                cur = []
            else:
                cur.append(tok)
        if cur:
            segs.append(cur)
        found = []
        for seg in segs:
            words, redirs, i = [], [], 0
            while i < len(seg):
                tok = seg[i]
                if tok and set(tok) <= set("<>&|"):
                    nxt = seg[i + 1] if i + 1 < len(seg) else ""
                    if ">" in tok and not tok.endswith("&") and nxt and nxt != "/dev/null" \
                            and not re.fullmatch(r"-|\d+", nxt):
                        redirs.append(nxt)
                    i += 2
                    continue
                words.append(tok)
                i += 1
            while words and (words[0] in PREFIX or re.fullmatch(r"[A-Za-z_]\w*=.*", words[0])):
                words = words[1:]
            verb = words[0] if words else ""
            args = [a for a in words[1:] if not a.startswith("-")]
            targets = list(redirs)
            if verb in ("cd", "pushd"):
                if args and "$" not in args[0]:
                    nd = os.path.expanduser(args[0])
                    here = nd if os.path.isabs(nd) else os.path.join(here, nd)
                elif not args:
                    here = os.path.expanduser("~")
                continue
            base = os.path.basename(verb)
            if base in DEST_LAST and args:
                dest = args[-1]
                if not (base in ("scp", "rsync") and re.match(r"[^/]*:", dest)):   # host:path is remote
                    targets.append(dest)
            elif base in ALL_ARGS:
                targets += args
            elif base == "dd":
                targets += [a[3:] for a in args if a.startswith("of=")]
            elif base == "sed" and any(re.fullmatch(r"-[A-Za-z]*i.*|--in-place.*", a) for a in words[1:]):
                targets += [a for a in args if exists(a, here)]
            elif base == "perl" and any(re.fullmatch(r"-[A-Za-z]*i.*", a) for a in words[1:]):
                targets += [a for a in args if exists(a, here)]
            elif base == "git":
                gdir, sub, skip, rest = here, "", None, []
                for k, a in enumerate(words[1:], 1):
                    if skip:
                        if skip == "-C":
                            gdir = a if os.path.isabs(a) else os.path.join(gdir, a)
                        skip = None
                    elif a in ("-C", "-c", "--git-dir", "--work-tree"):
                        skip = a
                    elif not a.startswith("-"):
                        sub, rest = a, words[k + 1:]
                        break
                if sub == "stash" and rest and rest[0] in STASH_READ:
                    sub = ""
                if sub in GIT_WRITE:
                    targets.append(gdir)
            elif BUILDERS.match(verb) or BUILDERS.match(base):
                targets.append(here)
            elif INTERP.match(base):
                code = next((words[k + 1] for k in range(1, len(words) - 1)
                             if base in ("bash", "sh", "zsh") and re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", words[k])), None)
                module = next((words[k + 1] for k in range(1, len(words) - 1) if words[k] == "-m"), None)
                if code is not None:
                    if depth < 3:
                        found += scan(code, here, depth + 1) or []
                elif (module and module.split(".")[0] in MODULE_BUILDERS) or \
                        (not module and args and BUILDERS.match(os.path.basename(args[0]))):
                    targets.append(here)
                else:
                    targets += [a for a in args[1:] if exists(a, here)]
            for t in targets:
                if "$" in t or "`" in t:
                    continue
                if in_main(t, here):
                    found.append(t if os.path.isabs(t) else f"{t} (in {here})")
        return found

    res = scan(str(inp.get("command", "")), cwd)
    if res is None:
        sys.exit(0)                               # untokenisable: fail open
    hits += res

if not hits:
    sys.exit(0)
where = ", ".join(sorted(set(hits))[:4])
if strength == "warn":
    msg = (f"WORKTREE GUARD (warning): your first prompt names the worktree {W}, but this {tool} call "
           f"writes into the MAIN checkout {M}: {where}. If you were told to work in that worktree, "
           f"stop and redo it there: `cd {W} && …`, or an absolute path under {W}.")
    logline(f"WARN agent={agent} source={source} W={W} hits={sorted(set(hits))[:4]}")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": msg}}))
    sys.exit(0)
logline(f"BLOCK agent={agent or '-'} source={source} W={W} tool={tool} hits={sorted(set(hits))[:4]}")
sys.stderr.write(
    f"⛔ WORKTREE GUARD: this {'agent' if agent else 'session'} works in the worktree\n"
    f"    {W}\n  (declared by {source}), but this {tool} call writes into the MAIN checkout\n"
    f"    {M}\n  target: {where}\n"
    f"  The shell may have started in the main checkout. Redo it inside the worktree: `cd {W} && …`,\n"
    f"  or use the absolute path under {W}. Bringing work back into the main checkout is the leader's\n"
    f"  step (agent-kit worktree diff … | git apply --3way), not this agent's. Off: WORKTREE_GUARD=0.\n")
sys.exit(2)
PY
rc=$?
[ "${rc}" -eq 2 ] && exit 2
exit 0
