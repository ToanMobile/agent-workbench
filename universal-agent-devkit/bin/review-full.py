#!/usr/bin/env python3
"""review-full.py — the 4-way review over the WHOLE solution, not a diff (bin/review-fanout.sh --full calls it).

  review-full.py --repo ROOT [--out DIR] [--chunk-lines N] [--jobs N] [--max-usd X] [--max-tokens N]
                 [--reviewers claude,antigravity,grok,ocr] [--list] [--no-verify]

Same reviewers and the same contract as the diff review (Claude Code pinned to Opus, Antigravity, Grok pinned, Alibaba OCR
full LLM mode; known-bug registry from .agents/instincts.md; read callers/callees/tests; JSON findings with file:line +
verbatim snippet, cite-checked), but every tracked source file is reviewed in full:
  * files: `git ls-files`, minus the separate clones (mcp-servers/rea, mcp-servers/super-board), node_modules, vendored /
    generated / build output, lockfiles, minified files, binaries, files > 300 KB and prose (*.md, *.txt, docs/);
  * chunks: grouped by module (product code is reviewed before tests, so a budget stop skips tests first) (top folder, two levels for the DevKit, mcp-servers, .claude, .agents and tests), packed up to
    --chunk-lines (6000) source lines; Claude, Antigravity and Grok review each chunk (in parallel, --jobs chunks at once);
  * OCR reviews the whole selection once, in a scratch git repo where every selected file is a new file (OCR chunks itself);
  * registry: every line of the selection is checked against the `detect` patterns (P0 recurring bug, deterministic);
  * merge: bin/review-merge.py analyse (normalize P0-P3, cite-check, dedupe, consensus) + the Opus verifier tries to refute
    every cited P0/P1 (--no-verify skips it).
Budget: --max-usd (REVIEW_FULL_MAX_USD, 40) / --max-tokens (REVIEW_FULL_MAX_TOKENS, 20000000) for the whole scan — once
spent, no further chunk starts (the report says which chunks were skipped). REPORT ONLY: nothing is fixed, no bug row is
recorded. Output: OUT/full-summary.md + full-summary.json (default OUT = <git-common-dir>/review-fanout/full-<HEAD12>-<ts>).
Exit 0 when every reviewer ran everywhere and nothing blocking was found, 1 otherwise, 2 usage error.
"""
import argparse
import concurrent.futures as cf
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import known_patterns  # noqa: E402

_spec = importlib.util.spec_from_file_location("review_merge", os.path.join(HERE, "review-merge.py"))
rm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rm)

EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
EXCLUDE = re.compile(
    r"(^|/)(node_modules|vendor|vendored|third_party|dist|build|out|coverage|generated|__generated__|\.next|\.venv|venv|"
    r"__pycache__|Pods|DerivedData)(/|$)|^mcp-servers/(rea|super-board)(/|$)|^docs/|"
    r"(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|poetry\.lock|\.min\.(js|css)|\.map|\.lock)$|"
    r"\.(md|mdx|txt|rst|png|jpe?g|gif|webp|svg|ico|pdf|zip|gz|tgz|jar|apk|aab|so|dylib|a|o|class|woff2?|ttf|otf|mp[34]|mov|"
    r"sqlite|db|bin|pyc|csv|tsv|jsonl|ndjson|snap)$", re.I)
DATA_JSON_MAX_LINES = 1500   # a bigger .json is data (catalogs, fixtures), not logic
TEST_RX = re.compile(r"(^|/)(tests?|__tests__|spec|fixtures?)(/|$)|(^|/)test_[^/]*$|\.(test|spec)\.[jt]sx?$")


def priority(chunk):
    """Order of review when the budget may run out: product code first, tests last."""
    tests = sum(1 for p in chunk["files"] if TEST_RX.search(p))
    return (1 if tests * 2 > len(chunk["files"]) else 0, chunk["id"])
TWO_LEVEL = ("universal-agent-devkit", "mcp-servers", ".claude", ".agents", "tests")
MAX_BYTES = 300_000


def git(repo, *a):
    return subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True)


def select_files(repo):
    """[(path, lines)] of the tracked source files in scope, and the count excluded."""
    allf = [p for p in git(repo, "ls-files", "-z").stdout.split("\0") if p]
    keep, skipped = [], 0
    for p in allf:
        fp = os.path.join(repo, p)
        if EXCLUDE.search(p) or os.path.islink(fp) or not os.path.isfile(fp) or os.path.getsize(fp) > MAX_BYTES:
            skipped += 1
            continue
        try:
            with open(fp, "rb") as fh:
                data = fh.read()
        except OSError:
            skipped += 1
            continue
        if b"\0" in data[:8192]:
            skipped += 1
            continue
        n = data.count(b"\n") + (0 if data.endswith(b"\n") or not data else 1)
        if p.endswith(".json") and n > DATA_JSON_MAX_LINES:
            skipped += 1
            continue
        keep.append((p, n))
    return keep, skipped


def module_of(path):
    parts = path.split("/")
    if len(parts) == 1:
        return "(root)"
    if parts[0] in TWO_LEVEL and len(parts) > 2:
        return "/".join(parts[:2])
    return parts[0]


def make_chunks(files, budget):
    """Group by module, pack consecutive modules of the same top folder up to `budget` lines; split a module bigger than it."""
    mods = {}
    for p, n in sorted(files):
        mods.setdefault(module_of(p), []).append((p, n))
    chunks, cur, cur_n, cur_top = [], [], 0, None
    def flush():
        nonlocal cur, cur_n
        if cur:
            chunks.append(cur)
        cur, cur_n = [], 0
    for mod in sorted(mods):
        top = mod.split("/")[0]
        items = mods[mod]
        size = sum(n for _, n in items)
        if cur and (top != cur_top or cur_n + size > budget):
            flush()
        cur_top = top
        for p, n in items:
            if cur and cur_n + n > budget:
                flush()
            cur.append((p, n))
            cur_n += n
    flush()
    out = []
    for i, ch in enumerate(chunks, 1):
        ms = sorted({module_of(p) for p, _ in ch})
        label = ms[0] if len(ms) == 1 else f"{ms[0]} (+{len(ms) - 1})"
        out.append({"id": f"{i:02d}", "label": label, "modules": ms, "files": [p for p, _ in ch], "lines": sum(n for _, n in ch)})
    return out


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, ensure_ascii=False, indent=1)


def read_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def run_chunk(repo, out, ch, reviewers, timeouts, models):
    d = os.path.join(out, "chunks", f"{ch['id']}")
    os.makedirs(d, exist_ok=True)
    meta = {"mode": "full", "repo": repo, "base": "HEAD", "depth": "deep", "files": ch["files"], "untracked": [],
            "chunk": ch["label"], "required": list(reviewers), "models": models}
    write_json(os.path.join(d, "meta.json"), meta)
    ctx = known_patterns.context(known_patterns.entries(repo), files=ch["files"])
    with open(os.path.join(d, "context.md"), "w", encoding="utf-8") as fh:
        fh.write(ctx)
    procs = {}
    for r in reviewers:
        procs[r] = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "review_runner.py"), r, "--repo", repo, "--run", d,
                                     "--timeout", str(timeouts[r])], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    for r, p in procs.items():
        _, err = p.communicate()
        if not os.path.isfile(os.path.join(d, f"{r}.json")):
            write_json(os.path.join(d, f"{r}.json"), {"reviewer": r, "status": "error", "verdict": "fail",
                                                       "reason": f"runner rc={p.returncode}: {(err or '')[-300:]}", "findings": []})
    return {r: read_json(os.path.join(d, f"{r}.json"), {}) for r in reviewers}


def run_ocr_full(repo, out, files, timeout_s, max_tokens):
    """OCR over the whole selection: a scratch repo where each selected file is new, `ocr review` of the workspace."""
    env_path = os.path.join(out, "ocr.json")
    def env(**kw):
        e = {"reviewer": "ocr", "status": "error", "verdict": "fail", "findings": [], "usage": {"tokens": 0, "usd": 0.0}}
        e.update(kw)
        write_json(env_path, e)
        return e
    if not shutil.which("ocr"):
        return env(status="unavailable", reason="ocr (OpenCodeReview) is not installed")
    scratch = tempfile.mkdtemp(prefix="ocr-full-")
    try:
        for p in files:
            dst = os.path.join(scratch, p)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(os.path.join(repo, p), dst)
        subprocess.run(["git", "init", "-q"], cwd=scratch, check=True)
        subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "empty", "--no-verify"], cwd=scratch, check=True,
                       env=dict(os.environ, GIT_AUTHOR_NAME="r", GIT_AUTHOR_EMAIL="r@r", GIT_COMMITTER_NAME="r",
                                GIT_COMMITTER_EMAIL="r@r"))
        rep = os.path.join(out, "ocr-review.json")
        cmd = ["ocr", "review", "--audience", "agent", "--format", "json", "-o", rep, "--timeout", str(max(1, timeout_s // 60)),
               "-b", "Whole-solution audit (not a diff): every file is shown as new. Report real defects: bugs, security, "
                     "error handling, resource leaks. Read callers/callees/tests in this tree."]
        if max_tokens:
            cmd += ["--max-tokens-budget", str(int(max_tokens))]
        try:
            r = subprocess.run(cmd, cwd=scratch, capture_output=True, text=True, timeout=timeout_s + 120)
        except subprocess.TimeoutExpired:
            return env(status="timeout", reason=f"ocr review exceeded {timeout_s}s")
        data = read_json(rep)
        if r.returncode != 0 or not isinstance(data, dict):
            return env(status="failed", reason=f"ocr review rc={r.returncode}: {(r.stderr or r.stdout).strip()[-400:]}")
        cov = (data.get("manifest") or {}).get("coverage") or {}
        tokens = int((data.get("summary") or {}).get("total_tokens") or 0)
        failed = cov.get("failed") or []
        comments = [c for c in data.get("comments") or [] if isinstance(c, dict)]
        if data.get("status") in ("failed", "error") or (failed and not cov.get("completed")):
            return env(status="failed", usage={"tokens": tokens, "usd": 0.0},
                       reason=f"ocr review status={data.get('status')} failed_files={len(failed)} (LLM endpoint rejected / quota?)")
        verdict = "fail" if any(str(c.get("severity", "")).lower() in ("critical", "high") for c in comments) else "pass"
        e = env(status="ok", verdict=verdict, findings=comments, usage={"tokens": tokens, "usd": 0.0},
                reason=f"{len(failed)} file(s) failed in OCR" if failed else "", partial_failed=len(failed))
        return e
    except (OSError, subprocess.CalledProcessError) as e:
        return env(status="error", reason=f"scratch repo for OCR failed: {e!r}")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def run_registry(repo, files):
    sel = set(files)
    env = known_patterns.scan(repo, EMPTY_TREE)
    env["findings"] = [f for f in env["findings"] if f["file"] in sel]
    env["verdict"] = "fail" if env["findings"] else "pass"
    return env


def main(argv=None):
    ap = argparse.ArgumentParser(prog="review-full.py")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--out")
    ap.add_argument("--chunk-lines", type=int, default=int(os.environ.get("REVIEW_FULL_CHUNK_LINES", "6000")))
    ap.add_argument("--jobs", type=int, default=int(os.environ.get("REVIEW_FULL_JOBS", "2")))
    ap.add_argument("--max-usd", type=float, default=float(os.environ.get("REVIEW_FULL_MAX_USD", "40")))
    ap.add_argument("--max-tokens", type=int, default=int(os.environ.get("REVIEW_FULL_MAX_TOKENS", "20000000")))
    ap.add_argument("--reviewers", default="claude,antigravity,grok,ocr")
    ap.add_argument("--list", action="store_true", help="print the chunks and exit (no LLM)")
    ap.add_argument("--no-verify", action="store_true")
    a = ap.parse_args(argv)
    repo = os.path.realpath(git(a.repo, "rev-parse", "--show-toplevel").stdout.strip() or a.repo)
    reviewers = [r for r in a.reviewers.split(",") if r]
    if not set(reviewers) <= {"claude", "antigravity", "grok", "ocr"}:
        print("review-full: --reviewers takes claude,antigravity,grok,ocr", file=sys.stderr)
        return 2
    files, skipped = select_files(repo)
    chunks = make_chunks(files, max(500, a.chunk_lines))
    if a.list:
        for c in chunks:
            print(f"{c['id']}  {c['lines']:>6} lines  {len(c['files']):>4} files  {c['label']}")
        print(f"{len(files)} files in scope, {skipped} excluded, {len(chunks)} chunks")
        return 0
    head = git(repo, "rev-parse", "HEAD").stdout.strip()
    common = git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip()
    out = a.out or os.path.join(common, "review-fanout", f"full-{head[:12]}-{time.strftime('%Y%m%d-%H%M%S')}")
    os.makedirs(out, exist_ok=True)
    os.chmod(out, 0o700)
    models = {"claude": os.environ.get("REVIEW_CLAUDE_MODEL") or "opus", "grok": os.environ.get("REVIEW_GROK_MODEL") or "grok-4.7"}
    timeouts = {"claude": int(os.environ.get("REVIEW_TIMEOUT_CLAUDE", "1500")), "grok": int(os.environ.get("REVIEW_TIMEOUT_GROK", "1500")),
                "antigravity": int(os.environ.get("REVIEW_TIMEOUT_AGY", "2400")), "security": 1500, "verifier": 1500}
    write_json(os.path.join(out, "plan.json"), {"repo": repo, "head": head, "files": len(files), "excluded": skipped,
                                                "chunks": chunks, "reviewers": reviewers, "models": models})
    print(f"review-full: {len(files)} files ({skipped} excluded) in {len(chunks)} chunks → {out}", flush=True)

    spent = {"usd": 0.0, "tokens": 0}
    results, skipped_chunks = {}, []
    chunk_revs = [r for r in reviewers if r != "ocr"]
    ocr_future = None
    with cf.ThreadPoolExecutor(max_workers=max(1, a.jobs) + 1) as ex:
        if "ocr" in reviewers:
            ocr_future = ex.submit(run_ocr_full, repo, out, [p for p, _ in files], int(os.environ.get("REVIEW_TIMEOUT_OCR", "3600")),
                                   a.max_tokens // 4)
        pending = sorted(chunks, key=priority)
        running = {}
        while pending or running:
            while pending and len(running) < max(1, a.jobs) and chunk_revs:
                if spent["usd"] > a.max_usd or spent["tokens"] > a.max_tokens:
                    skipped_chunks += [c["id"] for c in pending]
                    pending = []
                    break
                c = pending.pop(0)
                running[ex.submit(run_chunk, repo, out, c, chunk_revs, timeouts, models)] = c
            if not running:
                break
            done, _ = cf.wait(list(running), return_when=cf.FIRST_COMPLETED)
            for fu in done:
                c = running.pop(fu)
                try:
                    envs = fu.result()
                except Exception as e:   # a crashed chunk is recorded, never silently dropped
                    envs = {r: {"reviewer": r, "status": "error", "reason": f"chunk crashed: {e!r}", "findings": []} for r in chunk_revs}
                results[c["id"]] = envs
                for e in envs.values():
                    u = e.get("usage") or {}
                    spent["usd"] += float(u.get("usd") or 0)
                    spent["tokens"] += int(u.get("tokens") or 0)
                st = " ".join(f"{r}={e.get('status')}/{e.get('verdict', '-')}" for r, e in envs.items())
                print(f"  chunk {c['id']} {c['label']}: {st}  (spent ${spent['usd']:.2f}, {spent['tokens']} tok)", flush=True)
        ocr_env = ocr_future.result() if ocr_future else None

    # combine: one envelope per reviewer over the whole repo; status ok only when every chunk was ok
    combined = {}
    for r in chunk_revs:
        per = [(cid, envs.get(r) or {}) for cid, envs in sorted(results.items())]
        bad = [(cid, e) for cid, e in per if e.get("status") != "ok"]
        models_seen = sorted({str(e.get("model")) for _, e in per if e.get("model")})
        combined[r] = {"reviewer": r, "status": "ok" if per and not bad and not skipped_chunks else ("failed" if bad else "error"),
                       "verdict": "fail" if any(e.get("verdict") == "fail" for _, e in per) or bad else "pass",
                       "findings": [f for _, e in per if e.get("status") == "ok" for f in (e.get("findings") or [])],
                       "model": models_seen[0] if len(models_seen) == 1 else ", ".join(models_seen),
                       "reason": "; ".join(f"chunk {cid}: {e.get('status')} — {str(e.get('reason') or '')[:160]}" for cid, e in bad[:4])
                                 + (f" (+{len(bad) - 4} more)" if len(bad) > 4 else ""),
                       "chunks_ok": len(per) - len(bad), "chunks_total": len(chunks),
                       "usage": {"tokens": sum(int((e.get("usage") or {}).get("tokens") or 0) for _, e in per),
                                 "usd": sum(float((e.get("usage") or {}).get("usd") or 0) for _, e in per)}}
    if ocr_env is not None:
        combined["ocr"] = ocr_env
    combined["registry"] = run_registry(repo, [p for p, _ in files])
    meta = {"mode": "full", "repo": repo, "base": "HEAD", "depth": "deep", "required": reviewers + ["registry"],
            "models": models, "files": [p for p, _ in files], "code_hash": head}
    # partial results still count as evidence: analyse every reviewer that produced findings, even if some chunks failed
    analysable = {k: dict(v, status="ok") if v.get("findings") else v for k, v in combined.items()}
    clusters = rm.analyse(repo, meta, analysable)
    cands = rm.candidates(clusters)
    if cands and not a.no_verify:
        write_json(os.path.join(out, "candidates.json"), cands[:60])
        write_json(os.path.join(out, "meta.json"), meta)
        with open(os.path.join(out, "context.md"), "w", encoding="utf-8") as fh:
            fh.write("")
        subprocess.run([sys.executable, "-I", os.path.join(HERE, "review_runner.py"), "verifier", "--repo", repo, "--run", out,
                        "--timeout", str(timeouts["verifier"])], capture_output=True)
        combined["verifier"] = read_json(os.path.join(out, "verifier.json"), {"status": "error", "reason": "no verifier envelope"})
    rm.apply_verifications(clusters, combined.get("verifier"))
    verdict, reasons, usage = rm.decide(meta, combined, clusters, {}, "")
    if skipped_chunks:
        reasons.append(f"budget reached: chunks not reviewed: {', '.join(skipped_chunks)}")
        verdict = "FAIL"
    summary = {"verdict": verdict, "reasons": reasons, "usage": usage, "head": head, "files": len(files), "excluded": skipped,
               "chunks": [{k: c[k] for k in ("id", "label", "lines")} | {"files": len(c["files"])} for c in chunks],
               "skipped_chunks": skipped_chunks,
               "reviewers": {r: {k: e.get(k) for k in ("status", "verdict", "model", "reason", "chunks_ok", "chunks_total")}
                             for r, e in combined.items()},
               "per_chunk": {cid: {r: {k: e.get(k) for k in ("status", "verdict", "model", "reason")} for r, e in envs.items()}
                             for cid, envs in sorted(results.items())},
               "findings": clusters}
    write_json(os.path.join(out, "full-summary.json"), summary)
    md = rm.summary_md(verdict, reasons, meta, combined, clusters, usage).replace("# 4-way review", "# 4-way FULL-solution review", 1)
    with open(os.path.join(out, "full-summary.md"), "w", encoding="utf-8") as fh:
        fh.write(md)
    print(md)
    print(f"(run: {out})")
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
