#!/usr/bin/env bash
# Security regression test: a stdlib-named file in the hook process cwd must not change any hook decision.
#
# Hooks run inline python (python3 -c / heredoc / stdin) with cwd = the project. For those forms Python puts the cwd FIRST on
# sys.path, so a json.py / shlex.py / re.py ... in the project root replaces the stdlib module the hook imports: a json.py
# holding `raise SystemExit(0)` made hooks/hardware_safety_gate.sh (recursive rm outside the project) and
# hooks/block-dangerous-git.sh (reset --hard, force push ...) exit 0 instead of 2, so the blocked command RAN. A freshly
# cloned repo that ships such a file, or an agent that writes it, switched the gates off. The fix is `python3 -I` (isolated
# mode: no cwd / script dir, no PYTHON* env, no user site on sys.path) on every inline launch.
#
# For every hook that decides something this builds a payload the hook acts on (a block = rc 2 for the gates, or an allow /
# an output for the allow controls and context hooks), runs it with a CLEAN cwd and again with a cwd that holds shadow modules
# (variant "exit0": each module is `raise SystemExit(0)`; variant "raise": each is `raise RuntimeError`), and asserts the
# decision (rc + the full hook message) is IDENTICAL. Every run gets a fresh fixture and its own session id: the hooks keep
# per-session state (block-once, loop guards, locks) that must not leak from one variant to the next.
# Prints the table (rc and first message line per variant) and lists the hooks that can be bypassed.
#
# Round 2 (2026-10-05):
#  * the matrix runs the hook with a cwd that is NOT the project root (a scratch dir holding the shadows); a second section puts the shadow
#    where an attacker would, IN the project root with cwd = the project, for the gates and for two launchers the matrix cannot reach:
#    proof_gate in a COPY-mode install (PROOF_BIN is empty there, and `sys.path.insert(0, "")` put the cwd back first, undoing -I; a
#    tree_fp.py in the project made XONG pass) and the game profile hook validate-assets.sh (two python launches without -I);
#  * the shadow set also names kit modules (tree_fp, devkit_harness, ...);
#  * three cases (session_lock, testsourceset_gate, prompt_context) cannot be RED on the unpatched kit (the python is a script file / a failed
#    scope falls back to the stricter check / only a log is written): they are marked [guard] = regression checks, NOT evidence of the fix.
#
#   HP_KIT=<devkit dir>   run the same checks against another copy of the kit (e.g. the unpatched one: RED).
# bash 3.2 compatible wrapper; the checks are python3 (stdlib only).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${HP_KIT:-$DEVKIT_DIR}"
export PYTHONDONTWRITEBYTECODE=1
python3 -I - "$KIT" <<'PY'
import json, os, re, shutil, subprocess, sys, tempfile, time

KIT = os.path.realpath(sys.argv[1])
HOOKS = os.path.join(KIT, "hooks")
TMP = os.path.realpath(tempfile.mkdtemp(prefix="hookiso."))
MODULES = ("json", "re", "shlex", "subprocess", "shutil", "fnmatch", "time", "tempfile", "datetime", "hashlib", "glob",
           "math", "signal", "contextlib", "io", "os", "pathlib", "textwrap", "importlib", "xml", "difflib", "stat",
           "tree_fp", "devkit_harness", "devkit_profile", "session_authorship", "regression_checklist", "worktree", "session_lock")
VARIANTS = {"clean": None, "exit0": "raise SystemExit(0)\n", "raise": 'raise RuntimeError("shadowed stdlib module")\n'}
SHADOW_CWD = {}
for name, body in VARIANTS.items():
    d = os.path.join(TMP, "cwd_" + name)
    os.makedirs(d)
    SHADOW_CWD[name] = d
    if body:
        for m in MODULES:
            with open(os.path.join(d, m + ".py"), "w") as fh:
                fh.write(body)

NOW = time.time()


def git(root, *a):
    subprocess.run(["git", "-C", root, "-c", "user.email=t@t", "-c", "user.name=t"] + list(a), check=True,
                   capture_output=True, stdin=subprocess.DEVNULL)


def write(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    if mode:
        os.chmod(path, mode)


def jl(path, recs):
    write(path, "".join(json.dumps(r, separators=(",", ":"), ensure_ascii=False) + "\n" for r in recs))


def tool(name, inp, i=0):
    return {"type": "assistant", "message": {"id": "m%d" % i, "content": [{"type": "tool_use", "id": "t%d" % i, "name": name, "input": inp}]}}


def repo(root):
    os.makedirs(root, exist_ok=True)
    git(root, "init", "-q", ".")
    return root


# ── fixtures: each returns dict(hook, args, payload (dict or str), env, effect (optional callable -> str)) ──────────────
def bash_payload(root, cmd, sid="iso"):
    return {"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": root, "session_id": sid, "hook_event_name": "PreToolUse"}


def c_bash(hook, cmd):
    def f(root, v):
        os.makedirs(root, exist_ok=True)
        return dict(hook=hook, payload=bash_payload(root, cmd, "s-" + v), env={"CLAUDE_PROJECT_DIR": root})
    return f


def c_bridge(platform, hook, cmd):
    def f(root, v):
        os.makedirs(root, exist_ok=True)
        return dict(hook="agent_bridge.sh", args=[platform, "shell", hook], env={},
                    payload={"tool_input": {"command": cmd}, "command": cmd, "cwd": root})
    return f


def c_worktree_guard(root, v):
    main, wt = os.path.join(root, "main"), os.path.join(root, "wt")
    repo(main)
    write(os.path.join(main, "src", "a.kt"), "a\n")
    write(os.path.join(main, ".gitignore"), ".claude/audit-gate/\n")
    git(main, "add", "-A"); git(main, "commit", "-qm", "init")
    git(main, "worktree", "add", "-q", wt, "-b", "wt")
    write(os.path.join(subprocess.run(["git", "-C", wt, "rev-parse", "--absolute-git-dir"], capture_output=True, text=True).stdout.strip(),
                       "devkit-worktree.json"), json.dumps({"branch": "wt", "main": main}) + "\n")
    tr = os.path.join(root, "S1.jsonl")
    write(tr, '{"type":"mode"}\n{"type":"user","cwd":"%s"}\n' % main)
    return dict(hook="worktree_guard.sh", env={"CLAUDE_PROJECT_DIR": main, "DEVKIT_WORKTREE": wt},
                payload={"session_id": "S1", "transcript_path": tr, "cwd": main, "hook_event_name": "PreToolUse", "tool_name": "Edit",
                         "tool_input": {"file_path": os.path.join(main, "src", "a.kt"), "old_string": "a", "new_string": "b"}})


def c_session_lock(root, v):
    r = repo(os.path.join(root, "repo"))
    write(os.path.join(r, ".git", "devkit-session.lock"),
          json.dumps({"session_id": "holder", "started": NOW, "heartbeat": time.time(), "cwd": r, "pid": os.getpid()}))   # a live pid: a dead one counts as free
    return dict(hook="session_lock.sh", env={"CLAUDE_PROJECT_DIR": r},
                payload={"session_id": "other", "hook_event_name": "PreToolUse", "cwd": r, "tool_name": "Edit",
                         "tool_input": {"file_path": os.path.join(r, "a.kt")}})


def c_precode(root, v):
    os.makedirs(root)
    kt = os.path.join(root, "Unseen.kt")
    write(kt, "class Unseen\n")
    tr = os.path.join(root, "empty.jsonl"); write(tr, "")
    return dict(hook="precode_gate.sh", env={"CLAUDE_PROJECT_DIR": root},
                payload={"tool_name": "Edit", "session_id": "s-" + v, "transcript_path": tr,
                         "tool_input": {"file_path": kt, "old_string": "a", "new_string": "b"}})


def c_security(root, v):
    os.makedirs(root)
    man = os.path.join(root, "app/src/main/AndroidManifest.xml")
    tr = os.path.join(root, "t.jsonl")
    jl(tr, [tool("Edit", {"file_path": man, "new_string": '<uses-permission android:name="x"/>'}, 1),
            tool("Bash", {"command": "echo security-check done"}, 2)])
    return dict(hook="security_gate.sh", env={"CLAUDE_PROJECT_DIR": root},
                payload={"session_id": "s-" + v, "transcript_path": tr, "last_assistant_message": "xong"})


def c_claim(root, v):
    os.makedirs(root)
    tr = os.path.join(root, "empty.jsonl"); write(tr, "")
    return dict(hook="claim_check.sh", env={"CLAUDE_PROJECT_DIR": root},
                payload={"session_id": "s-" + v, "transcript_path": tr,
                         "last_assistant_message": "Lỗi nằm ở Ghost.kt:4211 trong nhánh cleanup."})


def c_test_evidence(root, v):
    os.makedirs(root)
    tr = os.path.join(root, "empty.jsonl"); write(tr, "")
    return dict(hook="test_evidence_gate.sh", env={"CLAUDE_PROJECT_DIR": root},
                payload={"session_id": "s-" + v, "transcript_path": tr, "last_assistant_message": "Đã chạy targeted test, 12/12 test pass."})


def c_review_web(root, v):
    repo(root)
    write(os.path.join(root, "src", "app.ts"), "export const a = 1\n")
    os.makedirs(os.path.join(root, ".agents", "active-profile"))
    shutil.copy(os.path.join(KIT, "profiles", "web", "profile.json"), os.path.join(root, ".agents", "active-profile", "profile.json"))
    git(root, "add", "src"); git(root, "commit", "-qm", "init")
    write(os.path.join(root, "src", "app.ts"), "export const a = 2\n")
    tr = os.path.join(root, "unreviewed.jsonl")
    jl(tr, [{"message": {"content": [{"type": "tool_use", "id": "e1", "name": "Edit",
                                      "input": {"file_path": os.path.join(root, "src", "app.ts"), "old_string": "1", "new_string": "2"}}]}}])
    return dict(hook="review_gate.sh", env={"CLAUDE_PROJECT_DIR": root},
                payload={"session_id": "s-" + v, "cwd": root, "transcript_path": tr, "last_assistant_message": "xong"})


def c_churn(root, v):
    os.makedirs(root)
    kt = os.path.join(root, "Seen.kt"); write(kt, "class Seen\n")
    tr = os.path.join(root, "churn.jsonl")
    jl(tr, [{"message": {"content": [{"type": "tool_use", "name": "Edit", "input": {"file_path": kt, "old_string": "a", "new_string": "b"}}]}}] * 3)
    return dict(hook="churn_guard.sh", env={"CLAUDE_PROJECT_DIR": root},
                payload={"tool_name": "Edit", "transcript_path": tr, "tool_input": {"file_path": kt, "old_string": "a", "new_string": "b"}})


def c_comment(root, v):
    os.makedirs(root)
    kt = os.path.join(root, "Seen.kt"); write(kt, "class Seen\n")
    tr = os.path.join(root, "empty.jsonl"); write(tr, "")
    return dict(hook="comment_claim_guard.sh", env={"CLAUDE_PROJECT_DIR": root},
                payload={"tool_name": "Edit", "transcript_path": tr,
                         "tool_input": {"file_path": kt, "old_string": "a", "new_string": "// đã test, covered by SeenTest\nval x = 1"}})


def c_foreign(root, v):
    for n in ("proj", "goods"):
        repo(os.path.join(root, n)); write(os.path.join(root, n, "src", "A.kt"), "x\n")
    os.makedirs(os.path.join(root, "goods", ".agents", "devkit"))
    tr = os.path.join(root, "tr.jsonl")
    jl(tr, [tool("Edit", {"file_path": os.path.join(root, "goods", "src", "A.kt"), "old_string": "a", "new_string": "b"})])
    return dict(hook="foreign_repo_gate.sh", env={"CLAUDE_PROJECT_DIR": os.path.join(root, "proj")},
                payload={"session_id": "s-" + v, "hook_event_name": "Stop", "transcript_path": tr})


def c_merge_gate(root, v):
    p = os.path.join(root, "proj")
    repo(p); write(os.path.join(p, "a.txt"), "a\n"); git(p, "add", "a.txt"); git(p, "commit", "-qm", "init")
    tr = os.path.join(root, "tr.jsonl")
    ts = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 120))   # the session started 2 minutes ago
    wt = os.path.join(root, "wt-new")
    jl(tr, [{"type": "user", "timestamp": ts, "message": {"content": "go"}}, tool("Bash", {"command": "git worktree add -b feat %s" % wt})])
    git(p, "worktree", "add", "-q", "-b", "feat", wt)
    write(os.path.join(wt, "n.txt"), "n\n"); git(wt, "add", "n.txt"); git(wt, "commit", "-qm", "new")
    return dict(hook="worktree_merge_gate.sh", env={"CLAUDE_PROJECT_DIR": p},
                payload={"session_id": "s-" + v, "hook_event_name": "Stop", "transcript_path": tr})


def gradle_project(root):
    """A project whose build and suite FAIL (as hooks/tests/hook_contract_test.sh): the two heavy Stop gates block a real turn end."""
    repo(root)
    os.makedirs(os.path.join(root, "lib", "src", "main")); os.makedirs(os.path.join(root, ".agents"))
    write(os.path.join(root, "lib", "build.gradle.kts"), "")
    write(os.path.join(root, "gradlew"), '#!/bin/bash\necho "e: A.kt:1:1 Unresolved reference: nope"\nexit 1\n', 0o755)
    write(os.path.join(root, ".agents", "regression_matrix.active.json"), json.dumps(
        {"project": "t", "rules": [{"component": "c", "watch_files": ["lib/**"],
                                    "mandatory_regression_tests": [{"id": "REG-GK", "name": "c", "command": "exit 1"}]}]}) + "\n")
    git(root, "add", "."); git(root, "commit", "-qm", "init")
    write(os.path.join(root, "lib", "src", "main", "A.kt"), "class A\n")
    tr = os.path.join(root, "..", "grok_updates.jsonl")
    write(tr, '{"timestamp":1790240706,"method":"_x.ai/session/update","params":{"sessionId":"g"}}\n')
    return os.path.realpath(tr)


def c_heavy(hook):
    def f(root, v):
        os.makedirs(root)
        p = os.path.join(root, "p")
        tr = gradle_project(p)
        return dict(hook=hook, env={"CLAUDE_PROJECT_DIR": p, "GROK_HOOK_EVENT": "stop"},
                    payload={"hookEventName": "stop", "hook_event_name": "Stop", "sessionId": "gk-" + v, "session_id": "gk-" + v,
                             "transcript_path": tr, "reason": "end_turn"})
    return f


def c_proof(root, v):
    repo(root); write(os.path.join(root, "src", "Core.kt"), "fun ok() = 1\n"); git(root, "add", "-A"); git(root, "commit", "-qm", "init")
    write(os.path.join(root, "src", "Core.kt"), "fun ok() = 2\n")
    tr = os.path.join(root, "turn.jsonl")
    ts = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 5))
    jl(tr, [{"type": "user", "timestamp": ts, "message": {"role": "user", "content": "sửa lỗi X"}}])
    msg = "XONG\nĐã sửa lỗi X.\n1. Đã fix: X\n2. Chặn bug cũ: REG PASS\n3. Nguy cơ bug mới: không\n4. An toàn mã nguồn: sạch"
    return dict(hook="proof_gate.sh", env={"CLAUDE_PROJECT_DIR": root},
                payload={"session_id": "s-" + v, "transcript_path": tr, "last_assistant_message": msg})


def c_read_ledger(root, v):
    os.makedirs(root)
    kt = os.path.join(root, "Seen.kt"); write(kt, "class Seen\n")
    led = os.path.join(root, ".claude", "audit-gate", "read_ledger.tsv")
    return dict(hook="read_ledger.sh", env={"CLAUDE_PROJECT_DIR": root},
                payload={"tool_name": "Read", "session_id": "SESS-A", "hook_event_name": "PostToolUse", "tool_input": {"file_path": kt}},
                effect=lambda: open(led).read() if os.path.exists(led) else "(no ledger)")


def c_ctx(hook, payload):
    def f(root, v):
        os.makedirs(os.path.join(root, ".agents"))
        write(os.path.join(root, ".agents", "instincts.md"),
              "### [INSTINCT-001] Chống bấm đúp nút thanh toán (double-click)\n- **Hiện tượng lỗi:** click nhanh gọi API hai lần, debounce thiếu\n")
        write(os.path.join(root, ".agents", "active-profile.json"), '{"profile":"web"}')
        return dict(hook=hook, env={"CLAUDE_PROJECT_DIR": root}, payload=dict(payload, session_id="s-" + v, cwd=root))
    return f


# (name, builder, expected rc in the clean run, kind) — kind: gate = a block / allow decision, ctx = context output
HSG = "hardware_safety_gate.sh"
CASES = [
    ("block-dangerous-git: reset --hard", c_bash("block-dangerous-git.sh", "git reset --hard HEAD~3"), 2),
    ("block-dangerous-git: push --force", c_bash("block-dangerous-git.sh", "git push --force origin main"), 2),
    ("block-dangerous-git: reset inside $(…)", c_bash("block-dangerous-git.sh", "echo $(git reset --hard HEAD~1)"), 2),
    ("block-dangerous-git: allow (full parser)", c_bash("block-dangerous-git.sh", 'git log --oneline -3 "$PWD"'), 0),
    ("block-dangerous-git: allow (no git word)", c_bash("block-dangerous-git.sh", 'echo "$HOME" | wc -c'), 0),
    ("hardware_safety_gate: rm -rf outside project", c_bash(HSG, "rm -rf /opt/hsg-iso-target"), 2),
    ("hardware_safety_gate: adb remount", c_bash(HSG, "adb remount"), 2),
    ("hardware_safety_gate: fastboot flash", c_bash(HSG, "fastboot flash boot x.img"), 2),
    ("hardware_safety_gate: allow rm -rf /tmp/x", c_bash(HSG, "rm -rf /tmp/hsg-iso-ok-target"), 0),
    ("hardware_safety_gate: allow (full parser)", c_bash(HSG, 'ls "$HOME/Library" | head -3'), 0),
    ("agent_bridge gemini -> block-dangerous-git", c_bridge("gemini", "block-dangerous-git.sh", "git reset --hard HEAD~3"), 2),
    ("agent_bridge codex -> hardware_safety_gate", c_bridge("codex", HSG, "rm -rf /opt/hsg-iso-target"), 2),
    ("agent_bridge cursor -> hardware_safety_gate", c_bridge("cursor", HSG, "rm -rf /opt/hsg-iso-target"), 0),
    ("worktree_guard: Edit of MAIN from a worktree session", c_worktree_guard, 2),
    ("session_lock: other live session's Edit", c_session_lock, 2, "guard"),
    ("precode_gate: Edit of an unseen file", c_precode, 2),
    ("security_gate: manifest edit without review", c_security, 2),
    ("claim_check: unsourced file:line", c_claim, 2),
    ("test_evidence_gate: pass claim without XML", c_test_evidence, 2),
    ("review_gate: unreviewed web change", c_review_web, 2),
    ("churn_guard: 3rd blind edit", c_churn, 2),
    ("comment_claim_guard: claim in a comment", c_comment, 2),
    ("foreign_repo_gate: edit in another DevKit repo", c_foreign, 2),
    ("worktree_merge_gate: unmerged session worktree", c_merge_gate, 2),
    ("testsourceset_gate: broken build at turn end", c_heavy("testsourceset_gate.sh"), 2, "guard"),
    ("regression_gate: failing suite at turn end", c_heavy("regression_gate.sh"), 2),
    ("proof_gate: XONG without gate/proof", c_proof, 2),
    ("read_ledger: row written", c_read_ledger, 0),
    ("prompt_context: context text", c_ctx("prompt_context.sh", {"prompt": "sửa lỗi nút thanh toán bị bấm 2 lần", "hook_event_name": "UserPromptSubmit"}), 0, "guard"),
    ("session_context: context text", c_ctx("session_context.sh", {"hook_event_name": "SessionStart", "source": "startup"}), 0),
]


def norm(text, root):
    for r in (root, os.path.realpath(root)):
        text = text.replace(r, "<R>")
    text = text.replace(TMP, "<T>")
    text = re.sub(r"\d{4}-\d\d-\d\dT[\d:.]+Z?", "<ts>", text)
    text = re.sub(r"\b\d{8}-\d{6}\b", "<stamp>", text)   # evidence log names
    text = re.sub(r"\b\d{9,}(?:\.\d+)?\b", "<n>", text)
    return text.strip()


def run_case(idx, name, build, v):
    root = os.path.join(TMP, "c%02d" % idx, v)
    spec = build(root, v)
    payload = spec["payload"] if isinstance(spec["payload"], str) else json.dumps(spec["payload"])
    env = dict(os.environ)
    for k in [k for k in env if k.startswith("GIT_") or k.startswith("PYTHON") or k in ("CLAUDE_PROJECT_DIR", "DEVKIT_AGENT")]:
        env.pop(k)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env.update(spec["env"])
    cmd = ["bash", os.path.join(HOOKS, spec["hook"])] + spec.get("args", [])
    try:
        r = subprocess.run(cmd, input=payload, capture_output=True, text=True, timeout=120, cwd=SHADOW_CWD[v], env=env)
        rc, out = r.returncode, (r.stdout + "\n--stderr--\n" + r.stderr)
    except subprocess.TimeoutExpired:
        rc, out = 124, "TIMEOUT"
    eff = spec["effect"]() if "effect" in spec else ""
    text = norm(out + ("\n--effect--\n" + eff if eff else ""), root)
    if spec["hook"] == "session_context.sh":      # the one hook whose text carries the machine / clock: keep the structure only
        text = "\n".join(l for l in text.splitlines() if not re.search(r"(?i)\b(\d+ ?ms|branch|worktree|git |load)\b", l))
    return rc, text, spec["hook"]


fails = []
bypass = []
rows = []
for idx, case in enumerate(CASES):
    name, build, want = case[:3]
    guard = len(case) > 3
    res = {}
    for v in VARIANTS:
        try:
            res[v] = run_case(idx, name, build, v)
        except Exception as e:   # a fixture that cannot be built is a test bug, not a pass
            res[v] = (-1, "FIXTURE ERROR %s: %r" % (name, e), name)
    base_rc, base_text, hook_of = res["clean"]
    first = lambda t: next((l for l in t.splitlines() if l.strip() and not l.startswith("--")), "")[:70]
    ok_fixture = base_rc == want
    verdicts = []
    for v in ("exit0", "raise"):
        same = res[v] == res["clean"]
        verdicts.append("%s rc=%s%s" % (v, res[v][0], "" if same else " DIFF"))
        if not same:
            bypass.append((hook_of, v))
    rows.append("%-52s clean rc=%-3s %-34s | %s" % (name + (" [guard]" if guard else ""), base_rc, first(base_text), " | ".join(verdicts)))
    if not ok_fixture:
        fails.append("fixture: %s expected rc=%s in a clean cwd, got %s: %s" % (name, want, base_rc, first(base_text)))
    for v in ("exit0", "raise"):
        if res[v] != res["clean"]:
            fails.append("BYPASS: %s | shadow=%s | rc %s -> %s | %s -> %s" % (name, v, base_rc, res[v][0], first(base_text), first(res[v][1])))
            if res[v][0] == base_rc:   # same rc, other text: show where
                import difflib
                d = [l for l in difflib.unified_diff(base_text.splitlines(), res[v][1].splitlines(), "clean", v, n=0, lineterm="")][:8]
                fails.extend("      " + l[:200] for l in d)

# ── shadow IN the project root, cwd = the project (where Claude Code runs the hook) ──────────────────────────────────────────────
def p_gate(hook, cmd):
    def f(root, v):
        proj = os.path.join(root, "proj")
        os.makedirs(proj)
        return dict(proj=proj, hook=os.path.join(HOOKS, hook), env={"CLAUDE_PROJECT_DIR": proj}, payload=bash_payload(proj, cmd, "s-" + v))
    return f


def p_proof_copy(root, v):
    """proof_gate in a copy-mode install: the hooks are copies in <project>/.claude/hooks, `../bin` does not exist, PROOF_BIN is empty."""
    proj = os.path.join(root, "proj")
    repo(proj)
    write(os.path.join(proj, "src", "Core.kt"), "fun ok() = 1\n")
    git(proj, "add", "-A"); git(proj, "commit", "-qm", "init")
    write(os.path.join(proj, "src", "Core.kt"), "fun ok() = 2\n")
    hd = os.path.join(proj, ".claude", "hooks")
    os.makedirs(hd)
    for f in ("proof_gate.sh", "devkit_harness.py"):
        shutil.copy(os.path.join(HOOKS, f), hd)
    os.makedirs(os.path.join(proj, ".agents", "devkit"))
    shutil.copytree(os.path.join(KIT, "bin"), os.path.join(proj, ".agents", "devkit", "bin"), symlinks=True)
    tr = os.path.join(root, "turn.jsonl")
    ts = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 5))
    jl(tr, [{"type": "user", "timestamp": ts, "message": {"role": "user", "content": "sửa lỗi X"}}])
    msg = "XONG\nĐã sửa lỗi X.\n1. Đã fix: X\n2. Chặn bug cũ: REG PASS\n3. Nguy cơ bug mới: không\n4. An toàn mã nguồn: sạch"
    return dict(proj=proj, hook=os.path.join(hd, "proof_gate.sh"), env={"CLAUDE_PROJECT_DIR": proj},
                payload={"session_id": "s-" + v, "transcript_path": tr, "last_assistant_message": msg})


def p_assets(root, v):
    """The game profile PostToolUse hook: a document written into Assets/ is refused (exit 2)."""
    proj = os.path.join(root, "proj")
    for d in ("Assets", "ProjectSettings"):
        os.makedirs(os.path.join(proj, d))
    subprocess.run(["git", "init", "-q", proj], check=True, capture_output=True)
    return dict(proj=proj, hook=os.path.join(KIT, "profiles", "game", "hooks", "validate-assets.sh"), env={"CLAUDE_PROJECT_DIR": proj},
                payload={"tool_name": "Write", "tool_input": {"file_path": os.path.join(proj, "Assets", "notes.md"), "content": "x"}})


# (name, builder, expected rc, shadow modules to try — each is `raise SystemExit(0)` placed in the project root)
INPROJECT = [
    ("block-dangerous-git (shadow in the project)", p_gate("block-dangerous-git.sh", "git reset --hard HEAD~3"), 2, ("json", "shlex")),
    ("hardware_safety_gate (shadow in the project)", p_gate(HSG, "rm -rf /opt/hsg-iso-target"), 2, ("json", "shlex")),
    ("proof_gate, copy-mode install (PROOF_BIN empty)", p_proof_copy, 2, ("tree_fp", "json")),
    ("game profile validate-assets.sh", p_assets, 2, ("json",)),
]
for idx, (name, build, want, mods) in enumerate(INPROJECT):
    res = {}
    for v in ("clean",) + tuple(mods):
        root = os.path.join(TMP, "ip%02d" % idx, v)
        try:
            spec = build(root, v)
            if v != "clean":
                write(os.path.join(spec["proj"], v + ".py"), "raise SystemExit(0)\n")
            env = {k: x for k, x in os.environ.items() if not k.startswith(("GIT_", "PYTHON", "CLAUDE_", "DEVKIT_AGENT"))}
            env.update(spec["env"], PYTHONDONTWRITEBYTECODE="1")
            r = subprocess.run(["bash", spec["hook"]], input=json.dumps(spec["payload"]), capture_output=True, text=True, timeout=120,
                               cwd=spec["proj"], env=env)
            res[v] = (r.returncode, norm(r.stdout + "\n--stderr--\n" + r.stderr, root))
        except Exception as e:
            res[v] = (-1, "FIXTURE ERROR %s: %r" % (name, e))
    first = lambda t: next((l for l in t.splitlines() if l.strip() and not l.startswith("--")), "")[:70]
    if res["clean"][0] != want:
        fails.append("fixture: %s expected rc=%s in a clean project, got %s: %s" % (name, want, res["clean"][0], first(res["clean"][1])))
    verdicts = []
    for v in mods:
        verdicts.append("%s.py rc=%s%s" % (v, res[v][0], "" if res[v] == res["clean"] else " DIFF"))
        if res[v] != res["clean"]:
            bypass.append((name.split(" (")[0].split(",")[0], v))
            fails.append("BYPASS (in the project root): %s | shadow=%s.py | rc %s -> %s | %s -> %s" % (name, v, res["clean"][0], res[v][0],
                                                                                                   first(res["clean"][1]), first(res[v][1])))
    rows.append("%-52s clean rc=%-3s %-34s | %s" % (name, res["clean"][0], first(res["clean"][1]), " | ".join(verdicts)))

# Fail closed on a CRASH (the two PreToolUse Bash gates promise it in their headers; an uncaught exception exits 1 and Claude Code
# lets exit 1 through). The fault is injected into a COPY of each hook in the scratch dir (no knob in the hook): the line that
# decides is replaced by a ZeroDivisionError. Expected: rc 2 and ONE line of reason, no traceback.
# The line also names the way out: the user runs the command through the ! prefix (both headers say so), or sets the variable the hook
# really reads (hardware_safety_gate: HARDWARE_OVERRIDE; block-dangerous-git has none).
for hook, marker, cmd, hint, proof in (("block-dangerous-git.sh", "reason = analyse(cmd)", 'git log "$PWD"', 'prefix "!"', "prefix `!`"),
                                       ("hardware_safety_gate.sh", "rm_why = None if (label or MCP) else rm_problem(cmd, [CWD])", 'ls "$HOME"',
                                        "HARDWARE_OVERRIDE", "HARDWARE_OVERRIDE:-0")):
    src = open(os.path.join(HOOKS, hook), encoding="utf-8").read()
    if src.count(marker) != 1:
        fails.append("crash injection point not found exactly once in %s: %r (the hook changed; update this test)" % (hook, marker))
        continue
    copy = os.path.join(TMP, "crash_" + hook)
    open(copy, "w", encoding="utf-8").write(src.replace(marker, marker.split("=")[0] + "= 1 / 0"))
    env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "PYTHON"))}
    env.update(CLAUDE_PROJECT_DIR=TMP, PYTHONDONTWRITEBYTECODE="1")
    r = subprocess.run(["bash", copy], input=json.dumps(bash_payload(TMP, cmd)), capture_output=True, text=True, timeout=60,
                       cwd=SHADOW_CWD["clean"], env=env)
    lines = [l for l in r.stderr.splitlines() if l.strip()]
    ok = r.returncode == 2 and len(lines) == 1 and "Traceback" not in r.stderr
    if ok and not (hint in r.stderr and proof in src):
        ok = False
        fails.append("the crash message of %s does not name an escape hatch the hook reads (%r / %r): %r" % (hook, hint, proof, r.stderr[:200]))
    rows.append("%-52s crash injected     rc=%s %s" % (hook + ": crash fails closed", r.returncode, (lines[0] if lines else "")[:60]))
    if not ok:
        fails.append("FAIL-OPEN CRASH: %s exits %s on an internal error (want 2 + one line): %r" % (hook, r.returncode, r.stderr[:160]))

print("\n".join(rows))
bypassable = sorted({h for h, _ in bypass})
if fails:
    print("\n".join("✖ " + f for f in fails))
    print("bypassable by a stdlib-named file in the cwd: " + (", ".join(bypassable) or "(none)"))
    print("❌ test_hook_python_isolation: %d failed" % sum(1 for f in fails if not f.startswith("      ")))
else:
    n_guard = sum(1 for c in CASES if len(c) > 3)
    print("✅ test_hook_python_isolation: %d cases (%d RED-capable + %d regression guards) and %d in-project cases give the same decision "
          "with shadowed stdlib / kit modules; 2 crash injections fail closed with a reason that names the way out"
          % (len(CASES), len(CASES) - n_guard, n_guard, len(INPROJECT)))
shutil.rmtree(TMP, ignore_errors=True)
sys.exit(1 if fails else 0)
PY
