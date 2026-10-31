#!/usr/bin/env python3
"""review-merge.py — merge the 4-way review (Claude Code Opus + Antigravity + Grok + Alibaba OpenCodeReview) into ONE verdict.

  review-merge.py --dir RUN_DIR [--repo ROOT] [--pre] [--record-bugs] [--outcomes FILE]

RUN_DIR (written by bin/review-fanout.sh) holds meta.json and one envelope per reviewer:
  meta.json   {"required": ["claude","antigravity","grok","ocr","registry", (+"security","verifier" when depth=deep)],
               "models": {"claude": "opus", "grok": "grok-4.7"},
               "depth": "light|deep", "base": REF, "code_hash": H, "max_tokens": N|null, "max_usd": X|null}
  <name>.json {"reviewer", "status": ok|failed|timeout|error|unavailable, "verdict": pass|fail, "reason",
               "findings": [...], "usage": {"tokens", "usd"}, "model": <model that answered>, "models": [...]}
  verifier.json {"reviewer":"verifier","status":"ok", "verifications": [{"id","refuted":bool,"reason"}]}

THE RULE (user, 31/10: "3 agent phải cùng thống nhất thì mới gọi là pass", the same day: 4 equal reviewers — Claude Code
pinned to Opus, Antigravity, Grok, OCR full LLM mode): PASS only when
  1. every required reviewer has an envelope, status ok and verdict pass — missing, failed, timed out, errored, unavailable
     or a "fail" verdict is an overall FAIL (no fail-open, no fallback that counts as a pass); every Claude envelope
     (claude, security, verifier) must record an Opus model and grok the pinned Grok model — another or no model = FAIL;
  2. no blocking finding is left: a P0/P1 that passed cite-check (file:line exists, snippet is really there) and that the
     verifier did not refute; a finding that matches a known bug pattern (.agents/instincts.md) is a P0 recurring bug, and a
     deterministic `detect` hit can never be refuted;
  3. the token / USD budget is not exceeded;
  4. every accepted P0/P1 of an earlier run (a BUG-REV-<id> bug row of the regression checklist, .agents/regression_status.json)
     is fixed WITH a linked regression test that last passed (regression_checklist.py bug-link BUG-REV-<id> <test>).
Anything else is FAIL with the reasons listed.

Severity: P0 blocker/critical · P1 major/high · P2 medium/minor/should-fix · P3 low/nit. Findings of different reviewers on
the same file, lines within 3 and the same category (or similar text) are one finding, "consensus" when >= 2 reviewers.

--pre        write candidates.json (P0/P1 for the verifier) and exit 0 — no verdict.
--record-bugs  add every blocking P0/P1 as an OPEN bug row BUG-REV-<id> (regression_checklist.py add --id REV-<id>) so the fix needs a test.
Output: RUN_DIR/summary.json (verdict, reasons, reviewers, findings, inline_comments) + summary.md; one line appended to
.claude/audit-gate/review_outcomes.jsonl. Exit 0 PASS, 1 FAIL, 2 usage error. Standard library only.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import known_patterns  # noqa: E402

CORE = ("claude", "antigravity", "grok", "ocr")
OPUS_REVIEWERS = ("claude", "security", "verifier")
SEV_MAP = {"p0": "P0", "blocker": "P0", "critical": "P0", "crash": "P0",
           "p1": "P1", "major": "P1", "high": "P1", "error": "P1",
           "p2": "P2", "medium": "P2", "minor": "P2", "should fix": "P2", "should-fix": "P2", "warning": "P2",
           "p3": "P3", "low": "P3", "nit": "P3", "info": "P3", "suggestion": "P3", "style": "P3"}
SEV_RANK = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
BLOCKING = ("P0", "P1")
CAT_MAP = (("recurring", "recurring-bug"), ("secur", "security"), ("vuln", "security"), ("auth", "security"),
           ("inject", "security"), ("secret", "security"), ("perf", "performance"), ("test", "test"),
           ("verif", "test"), ("style", "style"), ("nit", "style"), ("doc", "docs"), ("concurr", "bug"),
           ("race", "bug"), ("logic", "bug"), ("bug", "bug"), ("correct", "bug"), ("error", "bug"), ("regress", "bug"))
# reviewers whose prompt requires a verbatim snippet: a finding without one is not cited
NEEDS_SNIPPET = {"claude", "security", "antigravity", "grok"}
REV_BAD = {"OPEN", "NEEDS_TEST", "NOT_IN_MATRIX", "NOT_RUN", "FAIL", "TIMEOUT", "VACUOUS", "STALE", "FLAKY", "REPORTED"}


def norm_sev(v):
    s = str(v or "").strip().lower()
    return SEV_MAP.get(s) or SEV_MAP.get(s.split()[0] if s else "", "P2")


def norm_cat(v, text=""):
    s = (str(v or "") + " " + (text if not v else "")).lower()
    for k, c in CAT_MAP:
        if k in s:
            return c
    return "bug" if not v else re.sub(r"[^a-z0-9-]+", "-", str(v).lower()).strip("-")[:30] or "bug"


def _int(v):
    try:
        return int(str(v).strip())
    except (TypeError, ValueError):
        return None


def normalize(reviewer, raw):
    """One reviewer's finding, any of the 3 native shapes, as {reviewer, severity P0-P3, category, file, line, end_line,
    snippet, problem, why, fix, known_pattern}."""
    f = dict(raw or {})
    path = str(f.get("file") or f.get("path") or f.get("filename") or "").strip()
    line = _int(f.get("line") if f.get("line") is not None else f.get("start_line"))
    m = re.match(r"^(.*?):(\d+)(?:-(\d+))?$", path)
    if m and not os.path.splitext(path)[1].lstrip(".").isdigit():
        path, line = m.group(1), line or int(m.group(2))
        f.setdefault("end_line", m.group(3))
    end = _int(f.get("end_line")) or line
    problem = " ".join(str(f.get("problem") or f.get("content") or f.get("message") or f.get("title") or "").split())
    sev = norm_sev(f.get("severity") or f.get("priority"))
    out = {"reviewer": reviewer, "severity": sev, "category": norm_cat(f.get("category") or f.get("class") or f.get("type"), problem),
           "file": path.lstrip("./") if path.startswith("./") else path, "line": line, "end_line": max(end or 0, line or 0) or None,
           "snippet": str(f.get("snippet") or f.get("code") or "")[:400], "problem": problem[:600],
           "why": str(f.get("why") or "")[:600], "fix": str(f.get("fix") or f.get("suggestion") or "")[:600],
           "known_pattern": str(f.get("known_pattern") or ""), "deterministic": bool(f.get("deterministic"))}
    return out


def _ws(s):
    return " ".join(str(s).split())


def cite_check(repo, f):
    """(ok, why): the file is inside the repo, the line exists, and the snippet (when given or required) is really within 3
    lines of it. Same machine check antigravity-pm runs on Antigravity's findings (src/cite-check.js), applied to every
    reviewer."""
    path = f.get("file") or ""
    if not path:
        return False, "no file"
    full = os.path.realpath(os.path.join(repo, path))
    if not full.startswith(os.path.realpath(repo) + os.sep):
        return False, "file outside the repo"
    if not os.path.isfile(full):
        return False, "file does not exist"
    if not f.get("line") or f["line"] < 1:
        return False, "no line"
    try:
        with open(full, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError as e:
        return False, f"unreadable: {e}"
    if f["line"] > len(lines) + 1:
        return False, f"line {f['line']} past the end ({len(lines)} lines)"
    snip = _ws(f.get("snippet") or "")
    if not snip:
        return (False, "no snippet") if f["reviewer"] in NEEDS_SNIPPET else (True, "")
    lo, hi = max(0, f["line"] - 4), min(len(lines), (f.get("end_line") or f["line"]) + 3)
    window = _ws(" ".join(lines[lo:hi]))
    probe = snip.strip(" .…")
    if probe and (probe in window or all(_ws(p) in window for p in snip.split("…") if _ws(p))):
        return True, ""
    return False, "snippet not found at that line"


def _tokens(s):
    return set(re.findall(r"[a-z0-9_]{3,}", str(s).lower()))


def _similar(a, b):
    ta, tb = _tokens(a), _tokens(b)
    return bool(ta and tb) and len(ta & tb) / len(ta | tb) >= 0.25


def cluster_id(f):
    key = "|".join((f["file"], f["category"], " ".join(sorted(_tokens(f["problem"]))[:12])))
    return hashlib.sha1(key.encode()).hexdigest()[:10]


def dedupe(findings):
    clusters = []
    for f in sorted(findings, key=lambda x: (SEV_RANK[x["severity"]], x["file"], x["line"] or 0)):
        for c in clusters:
            h = c["head"]
            if h["file"] == f["file"] and abs((h["line"] or 0) - (f["line"] or 0)) <= 3 and \
                    (h["category"] == f["category"] or _similar(h["problem"], f["problem"])):
                c["members"].append(f)
                break
        else:
            clusters.append({"head": f, "members": [f]})
    out = []
    for c in clusters:
        ms = c["members"]
        head = dict(min(ms, key=lambda x: SEV_RANK[x["severity"]]))
        head["reviewers"] = sorted({m["reviewer"] for m in ms})
        head["consensus"] = len(head["reviewers"]) >= 2
        head["unanimous"] = all(r in head["reviewers"] for r in CORE)
        head["known_pattern"] = next((m["known_pattern"] for m in ms if m["known_pattern"]), "")
        head["deterministic"] = any(m["deterministic"] for m in ms)
        head["cited"] = any(m.get("cited") for m in ms)
        head["cite_why"] = "" if head["cited"] else "; ".join(sorted({m.get("cite_why", "") for m in ms}))
        snip = next((m["snippet"] for m in ms if m.get("cited") and m["snippet"]), head["snippet"])
        head["snippet"] = snip
        head["id"] = cluster_id(head)
        head.pop("reviewer", None)
        out.append(head)
    return out


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def load_run(run_dir):
    meta = load_json(os.path.join(run_dir, "meta.json"))
    envs = {}
    for name in set(meta.get("required") or []) | set(CORE) | {"registry", "security", "verifier"}:
        p = os.path.join(run_dir, f"{name}.json")
        if os.path.isfile(p):
            try:
                envs[name] = load_json(p)
            except (OSError, ValueError) as e:
                envs[name] = {"reviewer": name, "status": "error", "reason": f"unreadable envelope: {e}"}
    return meta, envs


def analyse(repo, meta, envs, ents=None):
    """Normalize + cite-check + known-pattern flag + dedupe. Returns clusters (no verifier applied)."""
    ents = known_patterns.entries(repo) if ents is None else ents
    raw = []
    for name, env in envs.items():
        if name == "verifier" or env.get("status") != "ok":
            continue
        for fr in env.get("findings") or []:
            f = normalize(name, fr)
            ok, why = cite_check(repo, f)
            f["cited"], f["cite_why"] = ok, why
            hit = known_patterns.match_finding(ents, f) if ok else None
            if hit or (ok and f["known_pattern"]):
                f["known_pattern"] = hit[0] if hit else f["known_pattern"]
                f["severity"], f["category"] = "P0", "recurring-bug"
                f["deterministic"] = f["deterministic"] or bool(hit and hit[1] == "detect")
            raw.append(f)
    return dedupe(raw)


def apply_verifications(clusters, verifier_env):
    ver = {}
    if verifier_env and verifier_env.get("status") == "ok":
        for v in verifier_env.get("verifications") or []:
            if isinstance(v, dict) and v.get("id"):
                ver[str(v["id"])] = v
    for c in clusters:
        v = ver.get(c["id"])
        c["verified"] = v is not None
        if not c["cited"]:
            c["state"] = "uncited"
        elif c["severity"] in BLOCKING and v and v.get("refuted") is True and not c["deterministic"]:
            c["state"] = "refuted"
            c["refuted_reason"] = str(v.get("reason") or "")[:400]
            c["original_severity"], c["severity"] = c["severity"], "P3"
        elif c["severity"] in BLOCKING:
            c["state"] = "blocking"
        else:
            c["state"] = "advisory"
    return clusters


def candidates(clusters):
    return [{k: c[k] for k in ("id", "severity", "category", "file", "line", "end_line", "snippet", "problem", "why",
                                 "reviewers", "known_pattern")}
            for c in clusters if c["cited"] and c["severity"] in BLOCKING and not c["deterministic"]]


def rev_rows(repo):
    """{BUG-REV-id: status} of the review-born bug rows in the regression checklist — load_view: the tracked
    .agents/regression_status.json plus the rows main-in-trunk-mode keeps in <git common dir>/postfix-gate/pending_rows.json and a
    linked worktree's overlay, exactly what regression_gate / test_evidence_gate read."""
    try:
        import regression_checklist as rc
    except Exception as e:   # the checklist module is the only judge of a row's status: no module, no pass
        return None, f"regression_checklist unavailable: {e!r}"
    try:
        data = rc.load_view(repo)
    except Exception as e:
        return None, f"regression checklist unreadable: {e!r}"
    rows = {}
    for iid, item in (data.get("items") or {}).items():
        if (iid.startswith("BUG-REV-") or iid.startswith("REV-")) and item.get("kind") == "bug":
            try:
                rows[iid] = rc.effective_status(data, item)
            except Exception as e:
                rows[iid] = f"ERROR {e!r}"
    return rows, ""


def model_reason(name, env, meta):
    """Why this envelope's model breaks the rule (Claude = Opus, Grok = the pinned model), or None."""
    if name == "verifier" and env.get("skipped"):
        return None   # nothing to verify: it never ran
    model = str(env.get("model") or "")
    if name in OPUS_REVIEWERS:
        if not model:
            return "model not recorded — cannot prove the review ran on Opus"
        if "opus" not in model.lower():
            return f"ran {model}, the review requires Claude Opus"
    elif name == "grok":
        want = str((meta.get("models") or {}).get("grok") or "grok")
        if not model:
            return "model not recorded — cannot prove which Grok model reviewed"
        if not model.lower().startswith(want.lower()):
            return f"ran {model}, the review pins {want}"
    return None


def decide(meta, envs, clusters, rev=None, rev_err=""):
    """The unanimous rule. Returns (verdict, reasons)."""
    reasons = []
    required = list(dict.fromkeys(list(CORE) + list(meta.get("required") or [])))
    for name in required:
        env = envs.get(name)
        if env is None:
            reasons.append(f"{name}: missing — the reviewer produced no result")
            continue
        st = env.get("status")
        if st != "ok":
            reasons.append(f"{name}: {st or 'no status'} — {str(env.get('reason') or '')[:300]}")
            continue
        bad_model = model_reason(name, env, meta)
        if bad_model:
            reasons.append(f"{name}: {bad_model}")
            continue
        if name != "verifier" and env.get("verdict") != "pass":
            reasons.append(f"{name}: verdict {env.get('verdict') or 'missing'} (not pass)")
    for name in OPUS_REVIEWERS:   # an extra Claude run (e.g. a verifier at light depth) must be Opus too: it can refute findings
        if name not in required and name in envs:
            bad_model = model_reason(name, envs[name], meta)
            if bad_model:
                reasons.append(f"{name}: {bad_model}")
    blocking = [c for c in clusters if c.get("state") == "blocking"]
    if blocking:
        reasons.append(f"{len(blocking)} unrefuted P0/P1 finding(s): "
                       + "; ".join(f"[{c['severity']}] {c['file']}:{c['line']} {c['problem'][:80]}" for c in blocking[:5]))
    tok = sum(int((e.get("usage") or {}).get("tokens") or 0) for e in envs.values())
    usd = sum(float((e.get("usage") or {}).get("usd") or 0) for e in envs.values())
    if meta.get("max_tokens") and tok > int(meta["max_tokens"]):
        reasons.append(f"budget: {tok} tokens > REVIEW_MAX_TOKENS={meta['max_tokens']}")
    if meta.get("max_usd") and usd > float(meta["max_usd"]):
        reasons.append(f"budget: ${usd:.2f} > REVIEW_MAX_USD={meta['max_usd']}")
    if rev is None:
        reasons.append(f"regression checklist: {rev_err or 'not read'}")
    else:
        live = {f"BUG-REV-{c['id']}" for c in blocking} | {f"REV-{c['id']}" for c in blocking}
        for iid, st in sorted(rev.items()):
            if iid not in live and st in REV_BAD | {s for s in [st] if str(s).startswith("ERROR")}:
                reasons.append(f"{iid}: accepted finding is {st} — a fixed P0/P1 needs a linked regression test that passed "
                               f"(regression_checklist.py bug-link {iid} <test>, then post-fix-gate --run-tests; "
                               f"not a bug: regression_checklist.py drop {iid}, logged)")
    return ("PASS" if not reasons else "FAIL"), reasons, {"tokens": tok, "usd": round(usd, 4)}


def record_bugs(repo, clusters):
    """Every blocking P0/P1 becomes (or stays) an OPEN bug row BUG-REV-<id>: the fix then needs `bug-link` to a regression test."""
    errs = []
    rc_bin = os.path.join(HERE, "regression_checklist.py")
    for c in clusters:
        if c.get("state") != "blocking":
            continue
        title = f"[review {c['severity']}] {c['file']}:{c['line']} {c['problem'][:140]}"
        r = subprocess.run([sys.executable, rc_bin, "add", title, "--id", f"REV-{c['id']}", "--severity", c["severity"],
                            "--module", c["file"], "--evidence", f"4-way review ({', '.join(c['reviewers'])})"],
                           cwd=repo, env=dict(os.environ, CLAUDE_PROJECT_DIR=repo), capture_output=True, text=True, timeout=120)
        if r.returncode != 0 and "đã có" not in (r.stdout + r.stderr) and "already" not in (r.stdout + r.stderr):
            errs.append(f"REV-{c['id']}: {(r.stderr or r.stdout).strip()[:200]}")
    return errs


def inline_comments(clusters):
    out = []
    for c in clusters:
        if c.get("state") in ("blocking", "advisory") or (c.get("state") == "refuted"):
            tag = "🔁 recurring bug " + c["known_pattern"] if c["known_pattern"] else c["category"]
            body = f"**[{c['severity']}] {tag}** ({', '.join(c['reviewers'])}{' · consensus' if c['consensus'] else ''})\n{c['problem']}"
            if c.get("why"):
                body += f"\n\nWhy: {c['why']}"
            if c.get("fix"):
                body += f"\n\nFix: {c['fix']}"
            if c.get("state") == "refuted":
                body += f"\n\n_Refuted by the verifier (was {c.get('original_severity')}): {c.get('refuted_reason', '')}_"
            out.append({"path": c["file"], "line": c["line"], "end_line": c.get("end_line") or c["line"],
                        "severity": c["severity"], "id": c["id"], "body": body})
    return out


def summary_md(verdict, reasons, meta, envs, clusters, usage):
    L = [f"# 4-way review: {'✅ PASS' if verdict == 'PASS' else '⛔ FAIL'}", "",
         f"base `{meta.get('base')}` · depth {meta.get('depth')} · code `{str(meta.get('code_hash', ''))[:12]}` · "
         f"{usage['tokens']} tokens · ${usage['usd']:.2f}", "", "| reviewer | status | verdict | model | findings |", "|---|---|---|---|---|"]
    for name in list(dict.fromkeys(list(CORE) + list(meta.get("required") or []))):
        e = envs.get(name) or {}
        L.append(f"| {name} | {e.get('status', 'MISSING')} | {e.get('verdict', '-')} | {e.get('model') or '-'} | "
                 f"{len(e.get('findings') or e.get('verifications') or [])} |")
    if reasons:
        L += ["", "## Why not PASS"] + [f"- {r}" for r in reasons]
    shown = [c for c in clusters if c.get("state") != "uncited"]
    if shown:
        L += ["", "## Findings", "| id | sev | state | where | reviewers | problem |", "|---|---|---|---|---|---|"]
        for c in sorted(shown, key=lambda x: (SEV_RANK[x["severity"]], x["file"])):
            L.append(f"| {c['id']} | {c['severity']} | {c['state']}{' 🔁' + c['known_pattern'] if c['known_pattern'] else ''} | "
                     f"{c['file']}:{c['line']} | {', '.join(c['reviewers'])} | {c['problem'][:140].replace('|', '/')} |")
    unc = [c for c in clusters if c.get("state") == "uncited"]
    if unc:
        L += ["", f"_{len(unc)} finding(s) dropped by cite-check (file:line/snippet not in the code) — logged in summary.json._"]
    return "\n".join(L) + "\n"


def log_outcome(path, meta, verdict, reasons, clusters, usage, envs=None):
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "code_hash": meta.get("code_hash"), "base": meta.get("base"),
           "depth": meta.get("depth"), "verdict": verdict, "reasons": reasons, "usage": usage,
           "reviewers": {n: {k: e.get(k) for k in ("status", "verdict", "model")} for n, e in sorted((envs or {}).items())},
           "findings": [{"id": c["id"], "severity": c["severity"], "state": c.get("state"), "reviewers": c["reviewers"],
                         "consensus": c["consensus"], "known_pattern": c["known_pattern"], "file": c["file"], "line": c["line"],
                         **({"refuted_reason": c.get("refuted_reason")} if c.get("state") == "refuted" else {}),
                         **({"cite_why": c.get("cite_why")} if c.get("state") == "uncited" else {})} for c in clusters]}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, ensure_ascii=False) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="review-merge.py")
    ap.add_argument("--dir", required=True)
    ap.add_argument("--repo")
    ap.add_argument("--pre", action="store_true")
    ap.add_argument("--record-bugs", action="store_true")
    ap.add_argument("--outcomes")
    a = ap.parse_args(argv)
    repo = os.path.realpath(a.repo or subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                                                     text=True).stdout.strip() or ".")
    try:
        meta, envs = load_run(a.dir)
    except (OSError, ValueError) as e:
        print(f"review-merge: cannot read {a.dir}: {e}", file=sys.stderr)
        return 2
    clusters = analyse(repo, meta, envs)
    if a.pre:
        cands = candidates(clusters)
        with open(os.path.join(a.dir, "candidates.json"), "w", encoding="utf-8") as fh:
            json.dump(cands, fh, ensure_ascii=False, indent=1)
        print(f"candidates: {len(cands)}")
        return 0
    apply_verifications(clusters, envs.get("verifier"))
    rev, rev_err = rev_rows(repo)
    verdict, reasons, usage = decide(meta, envs, clusters, rev, rev_err)
    if a.record_bugs:
        errs = record_bugs(repo, clusters)
        if errs:
            reasons.append("could not record accepted findings as bug rows: " + "; ".join(errs))
            verdict = "FAIL"
    out = {"verdict": verdict, "reasons": reasons, "meta": meta, "usage": usage,
           "reviewers": {n: {"status": e.get("status"), "verdict": e.get("verdict"), "reason": e.get("reason", ""),
                             "findings": len(e.get("findings") or []), "model": e.get("model")} for n, e in envs.items()},
           "findings": clusters, "inline_comments": inline_comments(clusters), "ts": time.time()}
    with open(os.path.join(a.dir, "summary.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1)
    md = summary_md(verdict, reasons, meta, envs, clusters, usage)
    with open(os.path.join(a.dir, "summary.md"), "w", encoding="utf-8") as fh:
        fh.write(md)
    try:
        log_outcome(a.outcomes or os.path.join(repo, ".claude", "audit-gate", "review_outcomes.jsonl"), meta, verdict, reasons,
                    clusters, usage, envs)
    except OSError as e:
        print(f"review-merge: outcome log not written: {e}", file=sys.stderr)
    sys.stdout.write(md)
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
