"""devkit_harness — which agent harness runs this hook, and a loop guard that cannot trap it.

The DevKit's hooks are written for Claude Code, but other agents run them too:
  * Grok (xAI CLI) loads the Claude hooks from .claude/settings.json (no DevKit adapter).
    Its hook envelope is camelCase (`hookEventName`, `sessionId`, `workspaceRoot`,
    `permissionMode`, `promptId`, `stopHookActive`, `lastAssistantMessage`, `subagentType`)
    next to a few snake_case aliases (`hook_event_name`, `session_id`, `transcript_path`),
    and the runner sets GROK_HOOK_EVENT / GROK_HOOK_NAME / GROK_SESSION_ID /
    GROK_WORKSPACE_ROOT on every hook process (Grok 1.0.41 hooks guide). Its
    `transcript_path` is Grok's own `updates.jsonl` ({"timestamp","method","params"} per
    line), which no Claude-transcript parser can read. It also fires an observe-only Stop
    at session end (`reason`: "channel_closed" / "shutdown"; a real stop is "end_turn").
  * Codex / Gemini / Cursor reach the hooks through agent_bridge.sh, which sets
    DEVKIT_AGENT=<platform> and sends no transcript.
Observed 2026-09-25 (OfficeReader): under Grok, testsourceset_gate compiled every test
source set on every stop, regression_gate blocked 11 times in one morning (its loop guard
counted per diff fingerprint and Grok's diff changed each turn), and the prompt hook
recorded Grok's sub-agent prompts as REPORTED bugs.

detect(payload) → {"agent": "claude"|"grok"|<DEVKIT_AGENT>|"unknown",
                   "transcript": "claude"|"empty"|"foreign"|"missing"|"unreadable",
                   "degraded": bool,       # not Claude, or no usable Claude transcript
                   "session": str,         # loop-guard key, never empty
                   "terminal_stop": bool,  # Grok's session-end Stop (not a turn end)
                   "subagent": bool}
A positive marker (payload key or env var) wins over the transcript; Claude is the
agent only when there is no marker and the transcript is a Claude one (or empty).

SessionGuard(state_file, session) — per-session state for a Stop gate in degraded mode:
the last result per tree fingerprint (so heavy work runs once per unchanged tree) and a
total block count per session (reset by a pass), written atomically.

CLI: `python3 devkit_harness.py detect` reads the hook payload on stdin, prints detect().
Stdlib only; every function fails soft (a broken detector must never break a hook).
"""
import contextlib
import hashlib
import json
import os
import re
import subprocess
import tempfile

GROK_KEYS = ("hookEventName", "workspaceRoot", "permissionMode", "promptId", "stopHookActive",
             "lastAssistantMessage", "subagentType", "toolUseId")
GROK_ENV = ("GROK_HOOK_EVENT", "GROK_HOOK_NAME")
CLAUDE_TYPES = {"user", "assistant", "system", "summary", "attachment", "progress",
                "file-history-snapshot", "queue-operation"}


def transcript_kind(path, probe_lines=40):
    """What the transcript at `path` is. "claude": Claude Code JSONL (records carry a
    `message` object or a Claude record `type`); "empty": exists, nothing in it yet;
    "foreign": readable but another tool's format (Grok's {"method","params"} stream,
    non-JSON text); "missing": no path / no file; "unreadable": cannot be opened."""
    if not isinstance(path, str) or not path:
        return "missing"
    if not os.path.isfile(path):
        return "missing"
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return "unreadable"
    claude = foreign = 0
    try:
        with fh:
            for n, line in enumerate(fh):
                if n >= probe_lines:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    foreign += 1
                    continue
                if not isinstance(rec, dict):
                    foreign += 1
                elif "method" in rec or "jsonrpc" in rec:
                    foreign += 1
                elif isinstance(rec.get("message"), dict) or rec.get("type") in CLAUDE_TYPES:
                    claude += 1
                else:
                    foreign += 1
    except OSError:
        return "unreadable"
    if claude:
        return "claude"
    return "foreign" if foreign else "empty"


def _clean(value, limit=64):
    return re.sub(r"[^A-Za-z0-9_-]", "_", str(value))[:limit]


def session_key(payload, env=None, ppid=None):
    """session_id / sessionId / GROK_SESSION_ID; without one, the harness pid plus the
    transcript path (or cwd) — stable for one agent process, distinct across agents."""
    env = os.environ if env is None else env
    payload = payload if isinstance(payload, dict) else {}
    for v in (payload.get("session_id"), payload.get("sessionId"), payload.get("conversation_id"),
              env.get("GROK_SESSION_ID")):
        if isinstance(v, str) and v.strip():
            return _clean(v.strip())
    where = (payload.get("transcript_path") or payload.get("transcriptPath") or payload.get("cwd")
             or env.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    ppid = ppid if ppid is not None else env.get("HOOK_PPID") or os.getppid()
    return "anon-" + hashlib.sha1(f"{ppid}|{where}".encode("utf-8", "replace")).hexdigest()[:16]


def detect(payload, env=None, ppid=None):
    env = os.environ if env is None else env
    payload = payload if isinstance(payload, dict) else {}
    agent = None
    if any(k in payload for k in GROK_KEYS) or any(env.get(k) for k in GROK_ENV):
        agent = "grok"
    elif env.get("DEVKIT_AGENT") and env.get("DEVKIT_AGENT") != "claude":
        agent = _clean(env["DEVKIT_AGENT"], 20)
    tp = payload.get("transcript_path") or payload.get("transcriptPath")
    kind = transcript_kind(tp)
    if agent is None:
        agent = "claude" if kind in ("claude", "empty") else "unknown"
    reason = payload.get("reason")
    return {
        "agent": agent,
        "transcript": kind,
        "degraded": agent != "claude" or kind not in ("claude", "empty"),
        "session": session_key(payload, env, ppid),
        # Grok only: Claude sends no Stop `reason`, and a future one must not switch gates off.
        "terminal_stop": agent == "grok" and isinstance(reason, str) and reason not in ("", "end_turn"),
        "subagent": bool(payload.get("subagentType") or payload.get("subagent_type")),
    }


def non_claude(payload, env=None):
    """True only on a POSITIVE marker of another harness (payload keys, GROK_* env,
    DEVKIT_AGENT). A payload that merely lacks a transcript is not proof of anything."""
    env = os.environ if env is None else env
    payload = payload if isinstance(payload, dict) else {}
    return (any(k in payload for k in GROK_KEYS) or any(env.get(k) for k in GROK_ENV)
            or bool(env.get("DEVKIT_AGENT") and env.get("DEVKIT_AGENT") != "claude"))


# ── tree fingerprint ─────────────────────────────────────────────────────────
OWN = (".claude/audit-gate", ".agents/regression_status.json", ".agents/regression_checklist.md",
       ".agents/CHECKLIST.md", ".agents/INBOX.md", ".agents/evidence", ".agents/archive")


def tree_fingerprint(repo, exclude=OWN, max_untracked=2000, max_bytes=8 << 20):
    """HEAD + status + tracked diff + untracked contents, minus the DevKit's own
    bookkeeping: equal fingerprints = the same tree to build and test."""
    def git(*args):
        try:
            return subprocess.run(["git", "-C", repo, *args], capture_output=True, timeout=60).stdout
        except Exception:  # noqa: BLE001
            return b""
    spec = ["--", "."] + [":(exclude)" + e for e in exclude]
    h = hashlib.sha256()
    h.update(git("rev-parse", "HEAD"))
    h.update(git("status", "--porcelain=v1", "-z", "-uall", *spec))
    h.update(git("diff", "HEAD", "--binary", *spec))
    for rel in git("ls-files", "--others", "--exclude-standard", "-z", *spec).split(b"\0")[:max_untracked]:
        if not rel:
            continue
        p = os.path.join(repo, rel.decode("utf-8", "replace"))
        h.update(rel)
        try:
            if os.path.getsize(p) <= max_bytes:
                with open(p, "rb") as fh:
                    h.update(hashlib.sha256(fh.read()).digest())
            else:
                h.update(str(os.path.getmtime(p)).encode())
        except OSError:
            h.update(b"?")     # vanished or unreadable: still part of the tree's shape
    return h.hexdigest()[:20]


# ── per-session loop guard ───────────────────────────────────────────────────
def write_json(path, data):
    """Atomic: concurrent sessions share the state file, and a torn write read back as
    {} used to reset every counter (two sessions racing on regression_gate.state.json)."""
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False)
        os.replace(tmp, path)
    except Exception:  # noqa: BLE001 — state is best effort; a failed write keeps the old file
        with contextlib.suppress(OSError):
            os.unlink(tmp)


def read_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:  # noqa: BLE001
        return {}


class SessionGuard:
    """State of one Stop gate for one session: {"fp", "result", "payload", "blocks"}."""

    def __init__(self, state_file, session):
        self.path, self.session = state_file, session
        self.state = read_json(state_file)

    def cached(self, fp):
        """The last result recorded for this tree fingerprint, or None."""
        return self.state if self.state.get("fp") == fp and "result" in self.state else None

    def store(self, fp, result, payload=None):
        self.state.update({"session": self.session, "fp": fp, "result": result, "payload": payload})
        if result == "pass":
            self.state["blocks"] = 0
        self.save()

    @property
    def blocks(self):
        try:
            return int(self.state.get("blocks", 0))
        except (TypeError, ValueError):
            return 0

    def add_block(self):
        self.state["blocks"] = self.blocks + 1
        self.save()
        return self.state["blocks"]

    def save(self):
        write_json(self.path, self.state)


def _cli(argv, stdin):
    """Shell entry points (bash hooks). Prints the answer; never raises."""
    cmd = argv[0] if argv else ""
    if cmd in ("detect", "fields"):
        try:
            data = json.loads(stdin.read() or "{}")
        except ValueError:
            data = {}
        info = detect(data)
        if cmd == "detect":
            return json.dumps(info)
        return "\t".join([info["session"], info["agent"], info["transcript"], "1" if info["degraded"] else "0",
                          "1" if info["terminal_stop"] else "0",
                          _clean(data.get("reason") or "", 32) if isinstance(data, dict) else ""])
    if cmd == "fingerprint" and len(argv) > 1:
        return tree_fingerprint(argv[1])
    if cmd == "sysmsg" and len(argv) > 1:
        return json.dumps({"systemMessage": argv[1]}, ensure_ascii=False)
    if cmd == "guard" and len(argv) > 2:
        g = SessionGuard(argv[1], "")
        op = argv[2]
        if op == "get" and len(argv) > 3:
            hit = g.cached(argv[3])
            return hit["result"] if hit else ""
        if op == "store" and len(argv) > 4:
            g.store(argv[3], argv[4])
            return ""
        if op == "blocks":
            return str(g.blocks)
        if op == "add-block":
            return str(g.add_block())
    return ""


if __name__ == "__main__":
    import sys
    try:
        out = _cli(sys.argv[1:], sys.stdin)
    except Exception:  # noqa: BLE001 — a broken helper must never break the hook
        out = ""
    if out:
        print(out)
