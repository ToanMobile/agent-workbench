#!/usr/bin/env bash
# review-fanout.sh — THE code review: Claude Code + Alibaba OpenCodeReview + Antigravity, in parallel, unanimous.
#
#   review-fanout.sh [--base REF|verified] [--repo DIR] [--background] [--status] [--hash] [--force]
#
# Rule (user 31/10/2026: "3 agent phải cùng thống nhất kết quả thì mới gọi là pass"): PASS only when all 3 reviewers ran,
# finished, and each says pass, no unrefuted P0/P1 is left, no known bug pattern (.agents/instincts.md) recurs, the budget
# holds and every accepted P0/P1 of an earlier run is fixed with a linked regression test. Missing / failed / timed-out /
# unavailable reviewer = FAIL with the reason. There is no fallback that counts as a reviewer's pass.
#
# Flow (one run dir per code state, shared by every worktree: <git-common-dir>/review-fanout/<code-hash>/):
#   1. meta.json (base, depth, files, budget) + context.md (known bug patterns for these files, same text for all 3)
#   2. registry.json  — bin/known_patterns.py scan: added lines that match a `detect` regex = P0 recurring bug (deterministic)
#   3. in parallel, each bounded by its own timeout (bin/review_runner.py):
#        claude.json (claude -p, read-only) · ocr.json (ocr-review --strict, OCR's own LLM) · antigravity.json (pm audit)
#        + security.json (Claude security reviewer) when depth=deep
#   4. review-merge.py --pre → candidates.json (cited P0/P1) → verifier.json (Claude tries to refute each)
#   5. review-merge.py --record-bugs → summary.json / summary.md (verdict + reasons + deduped findings + inline comments),
#      accepted P0/P1 → OPEN bug rows BUG-REV-<id> in the regression checklist, outcome → .claude/audit-gate/review_outcomes.jsonl
# Depth: >= REVIEW_DEEP_LINES (50) changed lines, or a path that looks like auth / payment / schema / migration / secrets → deep
# (security reviewer + verifier required); smaller → light prompts, still all 3 reviewers.
# Env: REVIEW_TIMEOUT_CLAUDE (900) REVIEW_TIMEOUT_OCR (900) REVIEW_TIMEOUT_AGY (1500) REVIEW_TIMEOUT_VERIFY (600) seconds;
#      REVIEW_MAX_TOKENS (3000000) REVIEW_MAX_USD (15) for the whole review — over budget = FAIL;
#      REVIEW_CLAUDE_BIN / REVIEW_CLAUDE_MODEL / REVIEW_AGY_CLI.
# A finished code state is cached: the same code is never reviewed (or billed) twice; --force reruns it.
# --status prints PASS|FAIL|RUNNING|NONE for the current code (exit 0 PASS, 1 FAIL, 3 RUNNING, 4 NONE); --hash prints the hash.
# --background starts the review detached and returns (exit 3). Exit 0 PASS, 1 FAIL, 2 usage error.
set -u
HERE="$(cd "$(dirname "$0")" && pwd -P)"
BASE="" REPO="" MODE="run" FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --background) MODE="background"; shift ;;
    --status) MODE="status"; shift ;;
    --hash) MODE="hash"; shift ;;
    --force) FORCE=1; shift ;;
    --child) MODE="child"; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "review-fanout: unknown argument $1" >&2; exit 2 ;;
  esac
done
REPO="$(git -C "${REPO:-.}" rev-parse --show-toplevel 2>/dev/null)" || { echo "review-fanout: not a git repo" >&2; exit 2; }
cd "$REPO" || exit 2
if [ "$BASE" = "verified" ]; then   # hooks/review_gate.sh: the DevKit's verified head (hooks/devkit_harness.py), else HEAD
  BASE="$(python3 -I - "$HERE/../hooks" "$REPO" <<'PY' 2>/dev/null
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import devkit_harness as dh
print(dh.verified_head(sys.argv[2], write=False)[0] or "")
PY
)"
  git rev-parse -q --verify "${BASE:-x}^{commit}" >/dev/null 2>&1 || BASE="HEAD"
fi
if [ -z "$BASE" ]; then
  if git rev-parse -q --verify origin/main >/dev/null 2>&1; then BASE="$(git merge-base HEAD origin/main)"; else BASE="HEAD"; fi
fi
BASE_SHA="$(git rev-parse -q --verify "${BASE}^{commit}" 2>/dev/null)" || { echo "review-fanout: base $BASE is not a commit" >&2; exit 2; }

CODE_HASH="$(python3 -I - "$BASE_SHA" <<'PY'
import hashlib, os, subprocess, sys
base = sys.argv[1]
h = hashlib.sha256(b"3way-review-v1\0" + base.encode() + b"\0")
h.update(subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True).stdout)
h.update(subprocess.run(["git", "diff", "--binary", "--no-ext-diff", base, "--"], capture_output=True).stdout)
for p in sorted(x for x in subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "-z"],
                                         capture_output=True).stdout.decode("utf-8", "replace").split("\0") if x):
    h.update(p.encode() + b"\0")
    try:
        if os.path.islink(p):
            h.update(os.readlink(p).encode())
        elif os.path.isfile(p):
            with open(p, "rb") as fh:
                h.update(fh.read())
    except OSError:
        h.update(b"?")
print(h.hexdigest())
PY
)" || { echo "review-fanout: could not hash the change" >&2; exit 2; }
[ "$MODE" = "hash" ] && { echo "$CODE_HASH"; exit 0; }

COMMON="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
RUN="$COMMON/review-fanout/$CODE_HASH"
mkdir -p "$COMMON/review-fanout" && chmod 700 "$COMMON/review-fanout"

running() { [ -f "$RUN/pid" ] && kill -0 "$(cat "$RUN/pid" 2>/dev/null)" 2>/dev/null; }
cached_verdict() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verdict",""))' "$RUN/summary.json" 2>/dev/null; }

if [ "$MODE" = "status" ]; then
  v="$(cached_verdict)"
  if [ "$v" = "PASS" ]; then echo "PASS $RUN"; exit 0; fi
  if [ "$v" = "FAIL" ]; then echo "FAIL $RUN"; exit 1; fi
  if running; then echo "RUNNING $RUN"; exit 3; fi
  echo "NONE $RUN"; exit 4
fi

if [ "$FORCE" = 0 ] && [ "$MODE" != "child" ]; then
  v="$(cached_verdict)"
  if [ -n "$v" ]; then cat "$RUN/summary.md" 2>/dev/null; echo "(cached: $RUN)"; [ "$v" = "PASS" ] && exit 0 || exit 1; fi
fi
if running && [ "$MODE" != "child" ]; then
  echo "review-fanout: a review of this code is already running ($RUN, pid $(cat "$RUN/pid")) — wait for it:"
  echo "  $0 --status --base $BASE_SHA   (or run again without --background when it ends)"
  exit 3
fi

if [ "$MODE" = "background" ]; then
  mkdir -p "$RUN" && chmod 700 "$RUN"
  nohup bash "$0" --child --force --base "$BASE_SHA" --repo "$REPO" > "$RUN/fanout.log" 2>&1 < /dev/null &
  echo $! > "$RUN/pid"
  echo "review-fanout: started in the background (pid $!), results in $RUN/summary.md"
  exit 3
fi

# ── foreground / child run ────────────────────────────────────────────────────────────────────────────────────────────────
[ "$FORCE" = 1 ] && [ "$MODE" != "child" ] && rm -rf "$RUN"
mkdir -p "$RUN" && chmod 700 "$RUN"
echo $$ > "$RUN/pid"
rm -f "$RUN"/{claude,ocr,antigravity,security,verifier,registry}.json "$RUN/summary.json" "$RUN/candidates.json"
trap 'rm -f "$RUN/pid"' EXIT

python3 -I - "$REPO" "$BASE_SHA" "$CODE_HASH" "$RUN" "$HERE" <<'PY' || { echo "review-fanout: meta failed" >&2; exit 2; }
import json, os, re, subprocess, sys
repo, base, code_hash, run, here = sys.argv[1:6]
def git(*a):
    return subprocess.run(["git", *a], capture_output=True, text=True).stdout
files, lines = [], 0
for l in git("diff", "--numstat", base, "--").splitlines():
    p = l.split("\t")
    if len(p) == 3:
        files.append(p[2]); lines += sum(int(x) for x in p[:2] if x.isdigit())
untracked = [x for x in git("ls-files", "--others", "--exclude-standard").splitlines() if x]
for u in untracked:
    try:
        with open(u, encoding="utf-8", errors="replace") as fh:
            lines += sum(1 for _ in fh)
    except OSError:
        pass
files += untracked
sensitive = re.compile(r"(auth|login|session|token|oauth|passw|payment|billing|money|wallet|invoice|price|checkout|"
                       r"migrat|schema|\.sql$|secur|crypt|secret|permission|acl)", re.I)
deep_lines = int(os.environ.get("REVIEW_DEEP_LINES", "50") or 50)
hot = [f for f in files if sensitive.search(f)]
depth = "deep" if lines >= deep_lines or hot else "light"
required = ["claude", "ocr", "antigravity", "registry"] + (["security", "verifier"] if depth == "deep" else [])
def num(name, d, cast):
    v = os.environ.get(name, d)
    try:
        return cast(v) if str(v).strip() else None
    except ValueError:
        return cast(d)
meta = {"repo": repo, "base": base, "code_hash": code_hash, "depth": depth, "changed_lines": lines, "sensitive_paths": hot,
        "files": files, "untracked": untracked, "dirty": bool(git("status", "--porcelain", "--untracked-files=all").strip()),
        "commits_since_base": bool(git("rev-list", "--max-count=1", f"{base}..HEAD").strip()), "required": required,
        "max_tokens": num("REVIEW_MAX_TOKENS", "3000000", int), "max_usd": num("REVIEW_MAX_USD", "15", float)}
with open(os.path.join(run, "meta.json"), "w") as fh:
    json.dump(meta, fh, indent=1)
ctx = subprocess.run([sys.executable, "-I", os.path.join(here, "known_patterns.py"), "--repo", repo, "context", "--files", *files],
                     capture_output=True, text=True)
with open(os.path.join(run, "context.md"), "w") as fh:
    fh.write(ctx.stdout)
print(f"review-fanout: base {base[:12]} · {len(files)} file(s) · {lines} changed line(s) · depth {depth}"
      + (f" (sensitive: {', '.join(hot[:5])})" if hot else ""))
PY

if [ "$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["files"]))' "$RUN/meta.json")" = "0" ]; then
  python3 -I -c 'import json,sys,time; json.dump({"verdict":"PASS","reasons":[],"note":"nothing to review","ts":time.time()}, open(sys.argv[1],"w"))' "$RUN/summary.json"
  printf '# 3-way review: ✅ PASS\n\nNothing to review: no change since %s.\n' "$BASE_SHA" > "$RUN/summary.md"
  cat "$RUN/summary.md"; exit 0
fi
DEPTH="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["depth"])' "$RUN/meta.json")"

python3 -I "$HERE/known_patterns.py" --repo "$REPO" scan --base "$BASE_SHA" --out "$RUN/registry.json" >/dev/null
[ -f "$RUN/registry.json" ] || python3 -I -c 'import json,sys; json.dump({"reviewer":"registry","status":"error","reason":"known_patterns scan failed"}, open(sys.argv[1],"w"))' "$RUN/registry.json"

R="$HERE/review_runner.py"
python3 -I "$R" claude      --repo "$REPO" --run "$RUN" --timeout "${REVIEW_TIMEOUT_CLAUDE:-900}" & P1=$!
python3 -I "$R" ocr         --repo "$REPO" --run "$RUN" --timeout "${REVIEW_TIMEOUT_OCR:-900}"    & P2=$!
python3 -I "$R" antigravity --repo "$REPO" --run "$RUN" --timeout "${REVIEW_TIMEOUT_AGY:-1500}"   & P3=$!
PIDS="$P1 $P2 $P3"
if [ "$DEPTH" = "deep" ]; then
  python3 -I "$R" security --repo "$REPO" --run "$RUN" --timeout "${REVIEW_TIMEOUT_CLAUDE:-900}" & PIDS="$PIDS $!"
fi
echo "review-fanout: reviewers running in parallel (pids $PIDS)"
for p in $PIDS; do wait "$p"; done

python3 -I "$HERE/review-merge.py" --dir "$RUN" --repo "$REPO" --pre >/dev/null || echo "review-fanout: candidate pass failed" >&2
if python3 -I -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])) else 1)' "$RUN/candidates.json" 2>/dev/null \
   || [ "$DEPTH" = "deep" ]; then
  python3 -I "$R" verifier --repo "$REPO" --run "$RUN" --timeout "${REVIEW_TIMEOUT_VERIFY:-600}"
fi

python3 -I "$HERE/review-merge.py" --dir "$RUN" --repo "$REPO" --record-bugs
rc=$?
echo "(run: $RUN)"
exit "$rc"
