#!/usr/bin/env python3
"""review_runner.py — run ONE reviewer of the 4-way review and always leave its envelope (bin/review-fanout.sh calls it).

  review_runner.py claude|security|verifier|ocr|antigravity|grok --repo ROOT --run RUN_DIR --timeout SEC

Writes RUN_DIR/<name>.json = {"reviewer", "status": ok|failed|timeout|error|unavailable, "verdict": pass|fail, "reason",
"findings", "usage": {"tokens","usd"}, "model", "models"}. Every failure path writes a non-ok status — the merge treats anything but ok+pass as
a FAIL of the whole review, so this file never needs to guess. Exit 0 when status is ok, 1 otherwise.

Claude Code (claude, security, verifier): `claude -p` read-only (Read/Grep/Glob and read-only git; Edit/Write denied),
--output-format json (cost + usage are counted against REVIEW_MAX_TOKENS / REVIEW_MAX_USD). REVIEW_CLAUDE_BIN overrides the
binary. The model is PINNED to Opus (`--model opus`, REVIEW_CLAUDE_MODEL may name another Opus id, never a non-Opus one); the
model that really answered is read from the result's modelUsage (the one with the most output tokens) and recorded as
"model": not Opus, or not reported = status failed (user rule 31/10/2026).
Grok: `grok --prompt-file … --output-format json` headless, --sandbox read-only, read tools only, pinned -m REVIEW_GROK_MODEL
(grok-4.7); the model is checked the same way from modelUsage. REVIEW_GROK_BIN overrides the binary.
OCR: bin/ocr-review --strict (its own LLM; the delegation fallback is refused) over the commits since base and over the
uncommitted change. Antigravity: mcp-servers/antigravity-pm-mcp/bin/pm-review-audit.js (pm_task_create + pm_dispatch audit).
Standard library only.
"""
import argparse
import json
import os
import re
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
READ_TOOLS = ("Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(git blame:*),Bash(git grep:*),"
              "Bash(git ls-files:*),Bash(git status:*)")
DENY_TOOLS = "Edit,Write,MultiEdit,NotebookEdit"
OCR_SEV_FAIL = {"critical", "high", "blocker", "major", "p0", "p1"}
GROK_TOOLS = "read_file,grep,list_dir,run_terminal_cmd"
GROK_DENY = "write,search_replace,web_search,web_fetch,task"


def models_used(res):
    """(main model, all models) from a headless result's modelUsage: the main one wrote the most output tokens."""
    mu = res.get("modelUsage") if isinstance(res, dict) else None
    if not isinstance(mu, dict) or not mu:
        return "", []
    def out_tokens(k):
        v = mu.get(k) or {}
        return int(v.get("outputTokens") or v.get("output_tokens") or 0) if isinstance(v, dict) else 0
    names = sorted(mu, key=lambda k: (-out_tokens(k), k))
    return names[0], names


def claude_model():
    m = (os.environ.get("REVIEW_CLAUDE_MODEL") or "opus").strip()
    return m


def model_problem(kind, model, pinned):
    """None when `model` is the one the rule requires, else the reason."""
    if not model:
        return f"the {kind} run did not report which model answered (modelUsage missing) — cannot prove {pinned}"
    if kind == "claude" and "opus" not in model.lower():
        return f"Claude ran {model}, the review requires Opus"
    if kind == "grok" and not model.lower().startswith(pinned.lower()):
        return f"Grok ran {model}, the review pins {pinned}"
    return None


def env_out(run, name, **kw):
    env = {"reviewer": name, "status": "error", "verdict": "fail", "reason": "", "findings": [],
           "usage": {"tokens": 0, "usd": 0.0}}
    env.update(kw)
    path = os.path.join(run, f"{name}.json")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(env, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, path)
    return 0 if env["status"] == "ok" else 1


def run_bounded(cmd, timeout, cwd, env=None, stdin_text=None):
    """(rc, out, err, timed_out); the whole process group is killed on timeout."""
    p = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.PIPE if stdin_text is not None else subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        out, err = p.communicate(stdin_text, timeout=timeout)
        return p.returncode, out, err, False
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        out, err = p.communicate()
        return 124, out, err, True


def read(path, default=""):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return default


def extract_json(text):
    """The last fenced ```json block, else the outermost {...} of the text."""
    blocks = re.findall(r"```(?:json)?\s*(\{.*?\})\s*```", text or "", re.S)
    for cand in reversed(blocks):
        try:
            return json.loads(cand)
        except ValueError:
            continue
    i, j = (text or "").find("{"), (text or "").rfind("}")
    if i >= 0 and j > i:
        return json.loads(text[i:j + 1])
    raise ValueError("no JSON object in the reviewer's answer")


FINDING_CONTRACT = """Answer with ONE JSON object and nothing else:
{"verdict": "pass" | "fail",
 "findings": [{"severity": "P0|P1|P2|P3", "category": "bug|security|performance|test|docs|recurring-bug",
               "file": "<repo-relative path>", "line": <int>, "end_line": <int>,
               "snippet": "<ONE line copied VERBATIM from the file at that line>",
               "problem": "<what breaks>", "why": "<how it fails / who is hit>", "fix": "<smallest correct fix>",
               "known_pattern": "<INSTINCT-id when this repeats a known bug, else empty>"}]}
Severity: P0 = data loss, security hole, crash, wrong result on a main path, or a repeated known bug; P1 = real bug on a
reachable path; P2 = should fix; P3 = nit. "verdict" is "pass" ONLY when there is no P0 and no P1.
Every file:line and snippet is machine-checked against the code: a citation that is not really there is thrown away."""


def full_scope(meta):
    """The whole-solution scan (bin/review-full.py): these files are reviewed in full, not a diff."""
    return (f"You are an independent code reviewer (read-only: never edit, never commit). Repository: {meta['repo']}.\n"
            f"WHOLE-SOLUTION AUDIT (not a diff) of module {meta.get('chunk') or '?'}: review these files IN FULL:\n"
            + "\n".join(f"- {f}" for f in meta.get("files") or []) + "\n\n"
            "For each file, read its callers, callees and tests elsewhere in the repo (git grep the names) to judge real "
            "behaviour. Report real defects in THESE files only (bugs, security holes, swallowed errors, races, resource "
            "leaks, broken contracts, dead guards), not style. Read CLAUDE.md / AGENTS.md for repo rules.\n\n")


def claude_prompt(kind, meta, ctx):
    base, depth = meta["base"], meta["depth"]
    if meta.get("mode") == "full":
        common = full_scope(meta)
    else:
        common = (f"You are an independent code reviewer (read-only: never edit, never commit). Repository: {meta['repo']}.\n"
              f"The change under review: `git diff {base}` (commits since {base} plus uncommitted edits) and these untracked "
              f"files, read whole: {', '.join(meta.get('untracked') or []) or 'none'}.\n"
              f"Changed files: {', '.join(meta.get('files') or [])}\n\n"
              "Before judging a changed function, class or symbol, read its callers, its callees and its tests "
              "(git grep the name). Defects often sit where the change meets code it did not touch. Findings stay scoped to "
              "the change: no findings about untouched code.\nRead CLAUDE.md / AGENTS.md for repo rules.\n\n")
    if kind == "claude":
        focus = ("Review depth: LIGHT (small change) — correctness, error handling and security of the changed lines and "
                 "their direct callers.\n" if depth == "light" else
                 "Review depth: DEEP — hunt bugs in parallel lenses: logic and edge cases, error handling / swallowed "
                 "failures, concurrency and resource leaks, API contract and backward compatibility, tests that do not "
                 "prove the behaviour, removed or weakened guards.\n")
    else:
        focus = ("You are the SECURITY reviewer: injection (shell, SQL, path), authn/authz bypass, secrets in code or logs, "
                 "unsafe deserialization, SSRF, insecure temp files and permissions, TOCTOU, crypto misuse, payment / money "
                 "integrity, destructive schema or data migrations. Report security findings only (category security).\n")
    return common + focus + "\n" + ctx + "\n" + FINDING_CONTRACT


def verifier_prompt(meta, cands):
    scope = ("This is a whole-solution audit (files reviewed in full)." if meta.get("mode") == "full"
             else f"The change is `git diff {meta['base']}`.")
    return (f"You are the VERIFIER of a code review in {meta['repo']} (read-only). {scope}\n"
            "Below are P0/P1 findings other reviewers reported. For EACH, try hard to REFUTE it: open the file, read the "
            "lines, the callers and the tests; check whether the failure can really happen. Refute only with concrete "
            "evidence (a guard, a type, a caller contract, a test that shows it cannot happen). If you cannot refute it, "
            "it stands.\n\nFindings:\n" + json.dumps(cands, ensure_ascii=False, indent=1) +
            '\n\nAnswer with ONE JSON object and nothing else: {"verifications": [{"id": "<id>", "refuted": true|false, '
            '"reason": "<evidence, file:line>"}]} — one entry per id.')


def run_claude(name, a, meta, ctx):
    bin_ = os.environ.get("REVIEW_CLAUDE_BIN", "claude")
    if name == "verifier":
        cands = json.loads(read(os.path.join(a.run, "candidates.json"), "[]") or "[]")
        if not cands:
            return env_out(a.run, name, status="ok", verdict="pass", verifications=[], reason="no P0/P1 candidate",
                           skipped=True, model="")
        prompt = verifier_prompt(meta, cands)
    else:
        prompt = claude_prompt(name, meta, ctx)
    want = claude_model()
    if "opus" not in want.lower():
        return env_out(a.run, name, status="error", model="", reason=f"REVIEW_CLAUDE_MODEL={want} is not an Opus model — refused")
    cmd = [bin_, "-p", "--output-format", "json", "--model", want, "--allowedTools", READ_TOOLS, "--disallowedTools", DENY_TOOLS]
    rc, out, err, to = run_bounded(cmd, a.timeout, a.repo, env=dict(os.environ, REVIEW_FANOUT_CHILD="1"), stdin_text=prompt)
    if to:
        return env_out(a.run, name, status="timeout", reason=f"claude -p exceeded {a.timeout}s")
    try:
        res = json.loads(out)
    except ValueError:
        return env_out(a.run, name, status="error", reason=f"claude -p rc={rc}: not JSON: {(err or out)[-400:]}")
    u = res.get("usage") or {}
    usage = {"tokens": sum(int(u.get(k) or 0) for k in ("input_tokens", "output_tokens", "cache_creation_input_tokens")),
             "usd": float(res.get("total_cost_usd") or res.get("cost_usd") or 0)}
    model, models = models_used(res)
    mk = {"model": model, "models": models}
    if rc != 0 or res.get("is_error"):
        return env_out(a.run, name, status="failed", usage=usage, reason=f"claude -p rc={rc}: {str(res.get('result'))[:400]}", **mk)
    bad = model_problem("claude", model, want)
    if bad:
        return env_out(a.run, name, status="failed", usage=usage, reason=bad, **mk)
    try:
        ans = extract_json(str(res.get("result") or ""))
    except ValueError as e:
        return env_out(a.run, name, status="error", usage=usage, reason=f"unparseable answer: {e}", **mk)
    if name == "verifier":
        v = ans.get("verifications")
        if not isinstance(v, list):
            return env_out(a.run, name, status="error", usage=usage, reason="no verifications list", **mk)
        return env_out(a.run, name, status="ok", verdict="pass", usage=usage, verifications=v, **mk)
    if ans.get("verdict") not in ("pass", "fail") or not isinstance(ans.get("findings", []), list):
        return env_out(a.run, name, status="error", usage=usage, reason="answer lacks verdict/findings", **mk)
    return env_out(a.run, name, status="ok", verdict=ans["verdict"], findings=ans.get("findings") or [], usage=usage, **mk)


def grok_bin():
    b = os.environ.get("REVIEW_GROK_BIN")
    if b:
        return b
    from shutil import which
    return which("grok") or os.path.expanduser("~/.grok/bin/grok")


def run_grok(a, meta, ctx):
    bin_ = grok_bin()
    want = (os.environ.get("REVIEW_GROK_MODEL") or "grok-4.7").strip()
    if not (os.path.isfile(bin_) and os.access(bin_, os.X_OK)):
        return env_out(a.run, "grok", status="unavailable", reason=f"Grok CLI not found at {bin_}")
    # Grok gets read tools and a read-only shell (git grep/log/show), not edits: the diff is handed over as a file.
    tail = ""
    if meta.get("mode") != "full":
        diff = os.path.join(a.run, "review.diff")
        with open(diff, "wb") as fh:
            fh.write(subprocess.run(["git", "diff", "--no-ext-diff", meta["base"], "--"], cwd=a.repo, capture_output=True).stdout)
        tail = f"\n\nThe full diff is in {diff} (read it first)."
    pf = os.path.join(a.run, "grok-prompt.md")
    with open(pf, "w", encoding="utf-8") as fh:
        fh.write(claude_prompt("claude", meta, ctx).replace(
            "You are an independent code reviewer", "You are Grok, one of four independent code reviewers", 1) + tail)
    cmd = [bin_, "--prompt-file", pf, "--output-format", "json", "-m", want, "--cwd", a.repo, "--sandbox", "read-only",
           "--tools", GROK_TOOLS, "--disallowed-tools", GROK_DENY, "--disable-web-search", "--no-subagents",
           "--always-approve", "--max-turns", os.environ.get("REVIEW_GROK_MAX_TURNS", "60")]
    rc, out, err, to = run_bounded(cmd, a.timeout, a.repo, env=dict(os.environ, REVIEW_FANOUT_CHILD="1"))
    if to:
        return env_out(a.run, "grok", status="timeout", reason=f"grok exceeded {a.timeout}s")
    res = None
    for cand in (out.strip(), (out.strip().splitlines() or [""])[-1]):   # one object, pretty-printed or on the last line
        try:
            res = json.loads(cand)
            break
        except ValueError:
            continue
    if res is None:
        return env_out(a.run, "grok", status="error", reason=f"grok rc={rc}: not JSON: {(err or out)[-400:]}")
    if not isinstance(res, dict):
        return env_out(a.run, "grok", status="error", reason="grok answered a non-object")
    model, models = models_used(res)
    mk = {"model": model, "models": models}
    u = res.get("usage") or {}
    usage = {"tokens": int(u.get("total_tokens") or 0) or sum(int(u.get(k) or 0) for k in ("input_tokens", "output_tokens")),
             "usd": float(res.get("total_cost_usd") or 0)}
    if rc != 0 or res.get("type") == "error" or res.get("is_error"):
        return env_out(a.run, "grok", status="failed", usage=usage,
                       reason=f"grok rc={rc}: {str(res.get('message') or res.get('text') or err)[:400]}", **mk)
    bad = model_problem("grok", model, want)
    if bad:
        return env_out(a.run, "grok", status="failed", usage=usage, reason=bad, **mk)
    try:
        ans = extract_json(str(res.get("text") or res.get("result") or ""))
    except ValueError as e:
        return env_out(a.run, "grok", status="error", usage=usage, reason=f"unparseable answer: {e}", **mk)
    if ans.get("verdict") not in ("pass", "fail") or not isinstance(ans.get("findings", []), list):
        return env_out(a.run, "grok", status="error", usage=usage, reason="answer lacks verdict/findings", **mk)
    return env_out(a.run, "grok", status="ok", verdict=ans["verdict"], findings=ans.get("findings") or [], usage=usage, **mk)


def run_ocr(a, meta, ctx):
    helper = os.path.join(HERE, "ocr-review")
    bg = ("4-way review (Claude Opus + Antigravity + Grok + OCR, unanimous). Read callers/callees/tests of every changed symbol; findings "
          "only on the change.\n" + ctx)[:3500]
    scopes = []
    if meta.get("commits_since_base"):
        scopes.append(("range", ["--from", meta["base"]]))
    if meta.get("dirty"):
        scopes.append(("workspace", []))
    if not scopes:
        return env_out(a.run, "ocr", status="ok", verdict="pass", reason="nothing to review")
    findings, tokens, deadline = [], 0, time.time() + a.timeout
    for label, rng in scopes:
        out_dir = os.path.join(a.run, f"ocr-{label}")
        left = max(30, int(deadline - time.time()))
        rc, out, err, to = run_bounded([sys.executable, "-I", helper, "--strict", "-b", bg, "--out", out_dir, *rng], left, a.repo)
        if to:
            return env_out(a.run, "ocr", status="timeout", reason=f"ocr review ({label}) exceeded the budget")
        if rc == 3:
            return env_out(a.run, "ocr", status="unavailable", reason="ocr is not installed")
        if rc != 0:
            return env_out(a.run, "ocr", status="failed", reason=f"ocr review ({label}) rc={rc}: {(err or out).strip()[-400:]}")
        try:
            rep = json.loads(read(os.path.join(out_dir, "ocr-review.json")))
        except ValueError as e:
            return env_out(a.run, "ocr", status="error", reason=f"ocr report ({label}) unreadable: {e}")
        cov = (rep.get("manifest") or {}).get("coverage") or {}
        if rep.get("status") in ("failed", "error") or cov.get("failed"):
            return env_out(a.run, "ocr", status="failed",
                           reason=f"ocr review ({label}) status={rep.get('status')} failed_files={len(cov.get('failed') or [])}")
        tokens += int((rep.get("summary") or {}).get("total_tokens") or 0)
        findings += [c for c in rep.get("comments") or [] if isinstance(c, dict)]
    verdict = "fail" if any(str(c.get("severity", "")).lower() in OCR_SEV_FAIL for c in findings) else "pass"
    return env_out(a.run, "ocr", status="ok", verdict=verdict, findings=findings, usage={"tokens": tokens, "usd": 0.0})


def run_agy(a, meta, ctx):
    cli = os.environ.get("REVIEW_AGY_CLI") or os.path.join(meta["repo"], "mcp-servers", "antigravity-pm-mcp", "bin", "pm-review-audit.js")
    if not os.path.isfile(cli):
        return env_out(a.run, "antigravity", status="unavailable", reason=f"{cli} not found")
    msg = os.path.join(a.run, "antigravity-message.md")
    depth = ("Do sau: DEEP (thay doi lon hoac cham auth/payment/schema) — soi ca bao mat." if meta["depth"] == "deep"
             else "Do sau: LIGHT (thay doi nho) — tap trung dung/sai va xu ly loi cua dong bi doi.")
    full = meta.get("mode") == "full"
    with open(msg, "w", encoding="utf-8") as fh:
        if full:
            fh.write(f"AUDIT TOAN BO SOLUTION (khong phai diff), module {meta.get('chunk')}: doc TRON VEN cac file sau, "
                     "doc them caller/callee/test cua chung, bao loi THAT trong cac file nay (bug, bao mat, nuot loi, race, "
                     "ro ri tai nguyen), khong bao style:\n" + "\n".join(f"- {f}" for f in meta.get("files") or [])
                     + f"\nMoi finding phai co snippet chep NGUYEN VAN tai file:dong (may se kiem).\n\n{ctx}")
        else:
            fh.write(f"Thay doi can audit: `git diff {meta['base']}` + file chua track: {', '.join(meta.get('untracked') or []) or 'khong'}.\n"
                     f"{depth}\nMoi finding phai co snippet chep NGUYEN VAN tai file:dong (may se kiem).\n\n{ctx}")
    out = os.path.join(a.run, "antigravity.json")
    rc, so, se, to = run_bounded(["node", cli, "--project", meta["repo"], "--base", meta["base"], "--out", out,
                                  "--message-file", msg, "--timeout", str(max(30, a.timeout - 30)),
                                  *(["--scope", "full"] if full else [])], a.timeout, a.repo)
    if to:
        return env_out(a.run, "antigravity", status="timeout", reason=f"Antigravity audit exceeded {a.timeout}s")
    if not os.path.isfile(out):
        return env_out(a.run, "antigravity", status="error", reason=f"pm-review-audit rc={rc} wrote nothing: {(se or so)[-400:]}")
    return 0 if rc == 0 else 1


def main(argv=None):
    ap = argparse.ArgumentParser(prog="review_runner.py")
    ap.add_argument("name", choices=["claude", "security", "verifier", "ocr", "antigravity", "grok"])
    ap.add_argument("--repo", required=True)
    ap.add_argument("--run", required=True)
    ap.add_argument("--timeout", type=int, default=900)
    a = ap.parse_args(argv)
    try:
        meta = json.loads(read(os.path.join(a.run, "meta.json")))
        ctx = read(os.path.join(a.run, "context.md"))
        if a.name in ("claude", "security", "verifier"):
            return run_claude(a.name, a, meta, ctx)
        if a.name == "ocr":
            return run_ocr(a, meta, ctx)
        if a.name == "grok":
            return run_grok(a, meta, ctx)
        return run_agy(a, meta, ctx)
    except Exception as e:   # never leave the vote empty-handed: an error is a recorded failure, not a silence
        return env_out(a.run, a.name, status="error", reason=f"review_runner crashed: {e!r}")


if __name__ == "__main__":
    sys.exit(main())
