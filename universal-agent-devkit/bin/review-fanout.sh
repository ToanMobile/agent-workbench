#!/usr/bin/env bash
# review-fanout.sh — THE code review, 4-way unanimous: Claude Code (Opus) + Antigravity + Grok + Alibaba OpenCodeReview,
# in parallel; all 4 must pass.
#
#   review-fanout.sh [--base REF|verified|merge-base] [--repo DIR] [--skip grok,ocr] [--depth deep] [--background] [--status] [--hash] [--force]
#   review-fanout.sh --full [--repo DIR] [review-full.py options: --list --chunk-lines N --jobs N --max-usd X ...]
#     whole-solution scan (not a diff) by the same 4 reviewers, chunked by module, report only — bin/review-full.py
#
# Rule (user 31/10/2026: "3 agent phải cùng thống nhất kết quả thì mới gọi là pass", widened the same day to 4 equal reviewers:
# Claude Code pinned to Opus, Antigravity, Grok, OCR full LLM mode): PASS only when all 4 reviewers ran on the required model,
# finished, and each says pass, no unrefuted P0/P1 is left, no known bug pattern (.agents/instincts.md) recurs, cost is logged
# and every accepted P0/P1 of an earlier run is fixed with a linked regression test. Missing / failed / timed-out /
# unavailable reviewer = FAIL with the reason. There is no fallback that counts as a reviewer's pass.
#
# Flow (one run dir per code state, shared by every worktree: <git-common-dir>/review-fanout/<code-hash>/):
#   1. meta.json (base, depth, files, runtime, pinned models) + context.md (known bug patterns for these files, same text for all)
#   2. registry.json  — bin/known_patterns.py scan: added lines that match a `detect` regex = P0 recurring bug (deterministic)
#   3. in parallel, each bounded by its own timeout (bin/review_runner.py):
#        claude.json (claude -p --model opus, read-only; a non-Opus run = FAIL) · antigravity.json (pm audit) ·
#        grok.json (grok -p headless, read-only sandbox, pinned model) · ocr.json (ocr-review --strict, OCR's own LLM)
#        + security.json (Claude security reviewer) when depth=deep
#   4. review-merge.py --pre → candidates.json (cited P0/P1) → verifier.json (Claude tries to refute each)
#   5. review-merge.py --record-bugs → summary.json / summary.md (verdict + reasons + deduped findings + inline comments),
#      accepted P0/P1 → OPEN bug rows BUG-REV-<id> in the regression checklist, outcome → .claude/audit-gate/review_outcomes.jsonl
# Depth: >= REVIEW_DEEP_LINES (50) changed lines, or a path that looks like auth / payment / schema / migration / secrets → deep
# (security reviewer + verifier required, both Claude Opus); smaller → light prompts, still all 4 reviewers.
# REVIEW_REGRESSION_STATUS=<absolute path OUTSIDE the repo> (B2 of #742, decision 31/10 17:32): the BUG-REV rows' status is read from
# that checklist JSON instead of the tracked .agents/regression_status.json (never committed for the review); its bytes are part of
# the code hash, a FAIL records its rows there too. Relative, missing or inside the repo = usage error (exit 2).
# --depth deep (or a marker <git-common-dir>/review-fanout/deep-heads/<HEAD sha>, written by the merge gate for a machine-gated PR
# whose review came out light — r14d BUG-REV-37b922ce04) forces a deep run; a forced run is its own code state in the hash.
# A PASS answers only for the reviewer executables that made it (r23c, BUG-REV 2ff4519b9f): meta.json records where claude, grok,
# ocr, node (+ REVIEW_AGY_CLI / ANTIGRAVITY_PM_AGY when set, a raised REVIEW_DEEP_LINES) resolve (review_runner.reviewer_runtime);
# --status reads a sealed PASS made with other ones as NONE (exit 4) and a run reviews again. Not in the code hash: the run dir stays
# the same code state, a FAIL answers FAIL whoever asks, and a CLI self-update (same PATH entry) keeps the verdict.
# A verdict answers only for the code state it names (r14d): --status reads summary.json once, checks the seal on those bytes and its
# meta.code_hash == this code hash; the tree is hashed again before the verdict is sealed (changed during the review = FAIL, no bug
# rows); a FAIL whose bug rows moved the hash (a linked worktree writes .agents/regression_status.json) is sealed under the new hash too.
# Env: REVIEW_TIMEOUT_CLAUDE (900) REVIEW_TIMEOUT_OCR (900) REVIEW_TIMEOUT_AGY (1500) REVIEW_TIMEOUT_GROK (900)
#      REVIEW_TIMEOUT_VERIFY (600) seconds;
#      cost is logged in summary.json (usage), never a FAIL condition (user 31/10/2026: no cost limit);
#      REVIEW_VERIFIER_BATCH (1): P0/P1 candidates per verifier call, REVIEW_VERIFIER_JOBS (8) calls in parallel;
#      REVIEW_CLAUDE_BIN / REVIEW_CLAUDE_MODEL (opus; anything that is not an Opus model is refused) / REVIEW_AGY_CLI /
#      REVIEW_GROK_BIN (grok on PATH, else ~/.grok/bin/grok) / REVIEW_GROK_MODEL (grok-4.7).
# Per-run override (user 31/10/2026): --skip grok,ocr or REVIEW_SKIP_REVIEWERS=grok,ocr drops those reviewers from THIS run
# only (never claude or antigravity). The run is then a REDUCED 2/3-way run: the summary lists each skipped reviewer as
# "skipped by user override", and the skip list is part of the code hash so a reduced PASS never answers a 4-way --status.
# The cache key leaves out the files the review itself writes (the regression checklist rows, the outcome log).
# A finished code state is cached: the same code is never reviewed (or billed) twice; --force reruns it.
# --status prints PASS|FAIL|RUNNING|NONE for the current code (exit 0 PASS, 1 FAIL, 3 RUNNING, 4 NONE); --hash prints the hash.
# --background starts the review detached and returns (exit 3). Exit 0 PASS, 1 FAIL, 2 usage error.
# --verify-summary PATH: exit 0 when the summary.json carries a valid HMAC seal, 1 when not (first argument only).
set -u
HERE="$(cd "$(dirname "$0")" && pwd -P)"
BASE="" REPO="" MODE="run" FORCE=0 SKIP="${REVIEW_SKIP_REVIEWERS:-}" DEPTH_FORCE=""
if [ "${1:-}" = "--full" ]; then shift; exec python3 -I "$HERE/review-full.py" "$@"; fi
# --verify-summary PATH: exit 0 only when PATH (a summary.json) carries a valid HMAC seal from this machine's review key
# (bin/review_sign.py); 1 unsigned / tampered, 2 usage. Prints "<verdict> <code_hash>" when valid (merge gate, 31/10).
if [ "${1:-}" = "--verify-summary" ]; then
  [ $# -eq 2 ] && [ -n "$2" ] || { echo "review-fanout: --verify-summary needs exactly one summary.json path" >&2; exit 2; }
  python3 -I - "$HERE" "$2" <<'PY' || { echo "UNSIGNED $2" >&2; exit 1; }
import importlib.util, json, os, sys
sp = importlib.util.spec_from_file_location("review_sign", os.path.join(sys.argv[1], "review_sign.py"))
rs = importlib.util.module_from_spec(sp); sp.loader.exec_module(rs)
data = rs._sealed_bytes(sys.argv[2])   # one read: the bytes checked are the bytes printed
if data is None:
    sys.exit(1)
try:
    d = json.loads(data.decode("utf-8"))
except ValueError:
    d = {}
d = d if isinstance(d, dict) else {}
print(d.get("verdict", "?"), (d.get("meta") or {}).get("code_hash", "") if isinstance(d.get("meta"), dict) else "")
PY
  exit 0
fi
while [ $# -gt 0 ]; do
  case "$1" in
    --full) echo "review-fanout: --full must be the first argument" >&2; exit 2 ;;
    --base|--repo|--skip|--depth)
      [ $# -ge 2 ] || { echo "review-fanout: $1 needs a value" >&2; exit 2; }
      case "$1" in --base) BASE="$2" ;; --repo) REPO="$2" ;; --skip) SKIP="$2" ;;
        --depth) [ "$2" = deep ] || { echo "review-fanout: --depth takes only 'deep' (a run is never forced lighter)" >&2; exit 2; }
                 DEPTH_FORCE=deep ;; esac
      shift 2 ;;
    --background) MODE="background"; shift ;;
    --status) MODE="status"; shift ;;
    --hash) MODE="hash"; shift ;;
    --force) FORCE=1; shift ;;
    --child) MODE="child"; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "review-fanout: unknown argument $1" >&2; exit 2 ;;
  esac
done
REPO="$(git -C "${REPO:-.}" rev-parse --show-toplevel 2>/dev/null)" || { echo "review-fanout: not a git repo" >&2; exit 2; }
SKIP="$(python3 -I - "$HERE" "skip=$SKIP" <<'PY'
import importlib.util, os, sys
sp = importlib.util.spec_from_file_location("rm", os.path.join(sys.argv[1], "review-merge.py"))
rm = importlib.util.module_from_spec(sp); sp.loader.exec_module(rm)
names, err = rm.parse_skip(sys.argv[2][5:])
if err:
    print(err, file=sys.stderr); sys.exit(2)
print(",".join(names))
PY
)" || { echo "review-fanout: bad --skip / REVIEW_SKIP_REVIEWERS" >&2; exit 2; }
export REVIEW_SKIP_REVIEWERS="$SKIP"
skipped() { case ",$SKIP," in *",$1,"*) return 0 ;; esac; return 1; }
cd "$REPO" || exit 2
if [ -n "${REVIEW_REGRESSION_STATUS:-}" ]; then
  python3 -I - "$REPO" "$REVIEW_REGRESSION_STATUS" <<'PY' || exit 2
import os, sys
repo, p = os.path.realpath(sys.argv[1]), sys.argv[2]
real = os.path.realpath(p)
if not os.path.isabs(p) or not os.path.isfile(real) or real == repo or real.startswith(repo + os.sep):
    print(f"review-fanout: REVIEW_REGRESSION_STATUS must be an existing absolute file outside the repo (got {p})", file=sys.stderr)
    sys.exit(1)
PY
fi
if [ "$BASE" = "merge-base" ]; then   # hooks/review_gate.sh: merge-base(HEAD, origin/<base>) — the SAME base super-board-merge-gate.sh
  # queries, so the hook's review and the gate's verdict lookup hash one code state (BUG-REV: base mismatch -> gate exit 6 forever)
  _mb_br="${REVIEW_BASE_BRANCH:-$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')}"
  BASE=""
  if git rev-parse -q --verify "origin/${_mb_br:-main}^{commit}" >/dev/null 2>&1; then BASE="$(git merge-base HEAD "origin/${_mb_br:-main}" 2>/dev/null)"; fi
  [ -n "$BASE" ] || BASE="verified"   # no remote base (fresh local repo): fall back to the verified head
fi
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

COMMON="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
# a machine-gated PR's head (marker from super-board-merge-gate.sh) is always reviewed deep
[ -f "$COMMON/review-fanout/deep-heads/$(git rev-parse -q --verify HEAD 2>/dev/null)" ] && DEPTH_FORCE=deep
code_hash() { python3 -I - "$BASE_SHA" "skip=$SKIP" "depth=$DEPTH_FORCE" <<'PY'
import hashlib, os, stat, subprocess, sys
base, skip, depth_force = sys.argv[1], sys.argv[2][5:], sys.argv[3][6:]
# files the review writes itself (the rendered checklist, outcome log): hashing them would make every review change the code
# state it just judged. .agents/regression_status.json DOES count (audit 31/10): dropping or editing a BUG-REV row is a change
# the review must see; the merge writes it only on a FAIL (blocking findings -> bug rows), never on a PASS.
SELF = (".agents/CHECKLIST.md", ".claude/audit-gate/")
EXCL = [f":(exclude){p}" for p in SELF]
h = hashlib.sha256(b"4way-review-v3\0" + base.encode() + b"\0")
# the pinned models and the override are part of the code state: a review by another model, or a reduced run, is a different review
h.update(("%s\0%s\0%s\0skip=%s\0" % (os.environ.get("REVIEW_CLAUDE_MODEL", "opus"), os.environ.get("REVIEW_GROK_MODEL", "grok-4.7"),
                                      os.environ.get("REVIEW_AGY_MODEL", "gemini-4-argon-high"), skip)).encode())
_st = os.environ.get("REVIEW_REGRESSION_STATUS", "")
if _st:   # the out-of-tree status the verdict reads (B2) is part of the code state it answers for
    try:
        with open(_st, "rb") as fh:
            h.update(b"status=" + hashlib.sha256(fh.read()).hexdigest().encode() + b"\0")
    except OSError:
        h.update(b"status=?\0")
if depth_force:   # a forced deep run is another review than the light one of the same code (only then: earlier hashes stay valid)
    h.update(b"depth=" + depth_force.encode() + b"\0")
h.update(subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True).stdout)
h.update(subprocess.run(["git", "diff", "--binary", "--no-ext-diff", base, "--", ".", *EXCL], capture_output=True).stdout)
for p in sorted(x for x in subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "-z"],
                                         capture_output=True).stdout.decode("utf-8", "replace").split("\0") if x):
    if p.startswith(SELF):
        continue
    h.update(p.encode() + b"\0")
    try:
        st = os.lstat(p)
        if stat.S_ISLNK(st.st_mode):
            h.update(os.readlink(p).encode())
        elif stat.S_ISREG(st.st_mode):   # never open a FIFO / device an agent left in the tree: it would hang the hash
            fd = os.open(p, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0))
            with os.fdopen(fd, "rb") as fh:
                h.update(fh.read())
        else:
            h.update(b"special:%o" % stat.S_IFMT(st.st_mode))
    except OSError:
        h.update(b"?")
print(h.hexdigest())
PY
}
CODE_HASH="$(code_hash)" && [ -n "$CODE_HASH" ] || { echo "review-fanout: could not hash the change" >&2; exit 2; }
[ "$MODE" = "hash" ] && { echo "$CODE_HASH"; exit 0; }

RUN="$COMMON/review-fanout/$CODE_HASH"
mkdir -p "$COMMON/review-fanout" && chmod 700 "$COMMON/review-fanout"

running() { [ -f "$RUN/pid" ] && kill -0 "$(cat "$RUN/pid" 2>/dev/null)" 2>/dev/null; }
# a verdict counts only with a valid HMAC seal (bin/review_sign.py, key in ~/.config/agent-workbench/review.key): a summary.json
# written by anyone else (an agent: {"verdict":"PASS"}) is UNSIGNED, never a verdict
# one read: the seal is checked on the bytes the verdict is taken from, and the summary must name THIS code state (r14d, F12)
# and a PASS made by other reviewer executables than this environment's (meta.runtime) is FOREIGN; a summary from before the runtime
# was recorded (or a test fixture) carries none
cached_verdict() {
  [ -f "$RUN/summary.json" ] || return 0
  python3 -I - "$HERE" "$RUN/summary.json" "$CODE_HASH" "${SKIP:-none}" <<'PY' 2>/dev/null
import importlib.util, os, sys
def _load(name):
    sp = importlib.util.spec_from_file_location(name, os.path.join(sys.argv[1], name + ".py"))
    m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m); return m
d = _load("review_sign").load_verified(sys.argv[2], sys.argv[3])
v = d.get("verdict", "") if isinstance(d, dict) else ""
meta = d.get("meta") if isinstance(d, dict) else None
rt = meta.get("runtime") if isinstance(meta, dict) else None
skipped = [] if sys.argv[4] == "none" else [x for x in sys.argv[4].split(",") if x]
print("FOREIGN" if v in ("PASS", "PASS_REDUCED") and rt is not None and rt != _load("review_runner").reviewer_runtime(skipped) else v)
PY
}

if [ "$MODE" = "status" ]; then
  v="$(cached_verdict)"
  if [ "$v" = "PASS" ]; then echo "PASS $RUN"; exit 0; fi
  if [ "$v" = "FAIL" ]; then echo "FAIL $RUN"; exit 1; fi
  if [ "$v" = "PASS_REDUCED" ]; then echo "PASS_REDUCED $RUN"; exit 6; fi   # never the default gate's PASS
  if [ "$v" = "FOREIGN" ] && ! running; then
    echo "review-fanout: the sealed PASS in $RUN was made by other reviewer executables than this environment runs — no verdict here" >&2
    echo "NONE $RUN"; exit 4
  fi
  if [ -z "$v" ] && [ -f "$RUN/summary.json" ] && ! running; then echo "UNSIGNED $RUN"; exit 5; fi
  if running; then echo "RUNNING $RUN"; exit 3; fi
  echo "NONE $RUN"; exit 4
fi

if [ "$FORCE" = 0 ] && [ "$MODE" != "child" ]; then
  v="$(cached_verdict)"
  if [ -n "$v" ] && [ "$v" != FOREIGN ]; then cat "$RUN/summary.md" 2>/dev/null; echo "(cached: $RUN)"; case "$v" in PASS|PASS_REDUCED) exit 0 ;; *) exit 1 ;; esac; fi
fi
if running && [ "$MODE" != "child" ]; then
  echo "review-fanout: a review of this code is already running ($RUN, pid $(cat "$RUN/pid")) — wait for it:"
  echo "  $0 --status --base $BASE_SHA   (or run again without --background when it ends)"
  exit 3
fi

# Per-run override token (audit 31/10): a skip is honoured only through a one-shot token that THIS command line (--skip /
# REVIEW_SKIP_REVIEWERS given to review-fanout itself) creates, bound to the code hash, valid 6 h, logged in override.log;
# the run consumes it. review_gate.sh strips REVIEW_SKIP_REVIEWERS from the environment it starts review-fanout with.
TOKDIR="$COMMON/review-fanout/skip-tokens"
if [ -n "$SKIP" ] && [ "$MODE" != "child" ]; then
  mkdir -p "$TOKDIR" && chmod 700 "$TOKDIR"
  python3 -I - "$TOKDIR/$CODE_HASH.json" "$SKIP" "$CODE_HASH" "$COMMON/review-fanout/override.log" <<'PY' || { echo "review-fanout: could not write the skip token" >&2; exit 2; }
import json, os, sys, time
tok, skip, h, log = sys.argv[1:5]
rec = {"skip": skip, "code_hash": h, "created": time.time(), "expires": time.time() + 6 * 3600, "pid": os.getppid(),
       "user": os.environ.get("USER", "")}
with open(tok + ".tmp", "w") as fh:
    json.dump(rec, fh)
os.replace(tok + ".tmp", tok)
with open(log, "a") as fh:
    fh.write(json.dumps(dict(rec, event="token_created")) + "\n")
PY
fi

if [ "$MODE" = "background" ]; then
  mkdir -p "$RUN" && chmod 700 "$RUN"
  nohup bash "$0" --child --force --base "$BASE_SHA" --repo "$REPO" --skip "$SKIP" ${DEPTH_FORCE:+--depth "$DEPTH_FORCE"} > "$RUN/fanout.log" 2>&1 < /dev/null &
  echo $! > "$RUN/pid"
  echo "review-fanout: started in the background (pid $!), results in $RUN/summary.md"
  exit 3
fi

# ── foreground / child run ────────────────────────────────────────────────────────────────────────────────────────────────
if [ -n "$SKIP" ]; then   # consume the one-shot token: missing, expired, another hash or another skip list = refused
  python3 -I - "$TOKDIR/$CODE_HASH.json" "$SKIP" "$CODE_HASH" "$COMMON/review-fanout/override.log" <<'PY' || exit 2
import json, os, sys, time
tok, skip, h, log = sys.argv[1:5]
try:
    used = tok + ".used.%d" % os.getpid()
    os.rename(tok, used)   # one shot: a second run cannot reuse it
    with open(used) as fh:
        rec = json.load(fh)
except (OSError, ValueError) as e:
    print(f"review-fanout: skip refused — no valid override token for this code ({e.__class__.__name__}); "
          "only `review-fanout.sh --skip grok,ocr` creates one", file=sys.stderr)
    sys.exit(1)
bad = (rec.get("code_hash") != h and "code hash") or (rec.get("skip") != skip and "skip list") or \
      (time.time() > float(rec.get("expires") or 0) and "expired")
with open(log, "a") as fh:
    fh.write(json.dumps({"event": "token_refused" if bad else "token_used", "why": bad or "", "skip": skip, "code_hash": h,
                         "ts": time.time()}) + "\n")
if bad:
    print(f"review-fanout: skip refused — override token {bad} mismatch", file=sys.stderr)
    sys.exit(1)
PY
fi
[ "$FORCE" = 1 ] && [ "$MODE" != "child" ] && rm -rf "$RUN"
mkdir -p "$RUN" && chmod 700 "$RUN"
echo $$ > "$RUN/pid"
rm -f "$RUN"/{claude,ocr,antigravity,grok,security,verifier,registry}.json "$RUN/summary.json" "$RUN/summary.json.sig" "$RUN/candidates.json" "$RUN/review.diff"
PIDS=""
# an interrupted review stops its reviewers too (each runner kills its own CLI process group on SIGTERM) instead of
# leaving them billing in the background with no pid file pointing at them
on_signal() { for p in $PIDS; do kill -TERM "$p" 2>/dev/null; done; for p in $PIDS; do wait "$p" 2>/dev/null; done; exit 130; }
trap 'rm -f "$RUN/pid"' EXIT
trap on_signal INT TERM HUP

python3 -I - "$REPO" "$BASE_SHA" "$CODE_HASH" "$RUN" "$HERE" "${SKIP:-none}" "${DEPTH_FORCE:-auto}" "$COMMON" <<'PY' || { echo "review-fanout: meta failed" >&2; exit 2; }
import importlib.util, json, os, re, stat, subprocess, sys
repo, base, code_hash, run, here, skip, depth_force, common_dir = sys.argv[1:9]
skipped = [] if skip == "none" else [x for x in skip.split(",") if x]
if depth_force == "auto":
    depth_force = ""
_rr_sp = importlib.util.spec_from_file_location("review_runner", os.path.join(here, "review_runner.py"))
_rr = importlib.util.module_from_spec(_rr_sp); _rr_sp.loader.exec_module(_rr)
runtime = _rr.reviewer_runtime(skipped)
def git(*a):
    return subprocess.run(["git", "-c", "core.quotePath=false", *a], capture_output=True, text=True).stdout
files, lines = [], 0
# -z: a path with a tab, newline or non-ASCII byte stays one exact path (no C-quoting); a rename is "n\tn\0old\0new\0"
toks = git("diff", "--numstat", "-z", "--no-renames", base, "--").split("\0")
for t in toks:
    p = t.split("\t")
    if len(p) == 3 and p[2]:
        files.append(p[2]); lines += sum(int(x) for x in p[:2] if x.isdigit())
untracked = [x for x in git("ls-files", "--others", "--exclude-standard", "-z").split("\0") if x]
for u in untracked:
    try:
        if not stat.S_ISREG(os.lstat(u).st_mode):   # a FIFO / socket / symlink is never opened (it could block forever)
            continue
        fd = os.open(u, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(fd, encoding="utf-8", errors="replace") as fh:
            lines += sum(1 for _ in fh)
    except OSError:
        pass
files += untracked
sensitive = re.compile(r"(auth|login|session|token|oauth|passw|payment|billing|money|wallet|invoice|price|checkout|"
                       r"migrat|schema|\.sql$|secur|crypt|secret|permission|acl)", re.I)
deep_lines = int(os.environ.get("REVIEW_DEEP_LINES", "50") or 50)
# the review machinery, hooks, CI and agent/tool config are always sensitive (audit 31/10)
machinery = re.compile(r"(^|/)(hooks/|bin/review|\.github/workflows/|\.claude/|\.mcp\.json$|mcp_config\.json$|AGENTS\.md$|CLAUDE\.md$|"
                       r"\.agents/(instincts|regression_)|package(-lock)?\.json$|requirements[^/]*\.txt$|pyproject\.toml$)")
hot = [f for f in files if sensitive.search(f) or machinery.search(f)]
# the diff is untrusted data: hidden unicode (bidi controls, zero-width, tag characters) or text that talks to the reviewer
# forces a deep review (security reviewer + verifier) and is named in meta (audit 31/10)
_dt = subprocess.run(["git", "diff", "--no-ext-diff", base, "--"], capture_output=True).stdout.decode("utf-8", "replace")
for _u in untracked[:200]:
    try:
        if not stat.S_ISREG(os.lstat(_u).st_mode):   # never follow a symlink out of the repo, never block on a FIFO (OCR #742)
            continue
        _fd = os.open(_u, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(_fd, encoding="utf-8", errors="replace") as _fh:
            _dt += _fh.read(1 << 20)
    except OSError:
        pass
HIDDEN = re.compile("[\u202a-\u202e\u2066-\u2069\u200b-\u200f\u2060\u00ad]|[\U000e0000-\U000e007f]|(?<!^)\ufeff")
INJECT = re.compile(r"ignore (?:all |any )?(?:previous|prior|above) instructions|disregard (?:the|all) (?:above|instructions)|"
                    r"you are now|system prompt|as an ai (?:reviewer|model)|\"verdict\"\s*:\s*\"pass\"|reviewer[s]?:? (?:must|should) (?:pass|approve)|"
                    r"approve this (?:change|pr)|no findings? (?:needed|required)", re.I)
signals = (["hidden unicode"] if HIDDEN.search(_dt) else []) + sorted({m.group(0).lower()[:60] for m in INJECT.finditer(_dt)})[:5]
depth = "deep" if depth_force == "deep" or lines >= deep_lines or hot or signals else "light"
required = [r for r in ("claude", "antigravity", "grok", "ocr") if r not in skipped] + ["registry"] \
    + (["security", "verifier"] if depth == "deep" else [])
def num(name, d, cast):
    v = os.environ.get(name, d)
    try:
        return cast(v) if str(v).strip() else None
    except ValueError:
        return cast(d)
meta = {"repo": repo, "common_dir": common_dir, "base": base, "code_hash": code_hash, "depth": depth, "depth_forced": depth_force == "deep",
        "regression_status": os.environ.get("REVIEW_REGRESSION_STATUS") or ".agents/regression_status.json", "changed_lines": lines, "sensitive_paths": hot, "injection_signals": signals,
        "files": files, "untracked": untracked, "dirty": bool(git("status", "--porcelain", "--untracked-files=all").strip()),
        "commits_since_base": bool(git("rev-list", "--max-count=1", f"{base}..HEAD").strip()), "required": required,
        "skipped_by_override": skipped, "reduced": bool(skipped), "runtime": runtime,
        "models": {"claude": os.environ.get("REVIEW_CLAUDE_MODEL") or "opus",
                   "grok": os.environ.get("REVIEW_GROK_MODEL") or "grok-4.7",
                   "antigravity": os.environ.get("REVIEW_AGY_MODEL") or "gemini-4-argon-high"}}
with open(os.path.join(run, "meta.json"), "w") as fh:
    json.dump(meta, fh, indent=1)
ctx = subprocess.run([sys.executable, "-I", os.path.join(here, "known_patterns.py"), "--repo", repo, "context", "--files", *files],
                     capture_output=True, text=True)
with open(os.path.join(run, "context.md"), "w") as fh:
    fh.write(ctx.stdout)
print(f"review-fanout: base {base[:12]} · {len(files)} file(s) · {lines} changed line(s) · depth {depth}"
      + (f" (sensitive: {', '.join(hot[:5])})" if hot else "")
      + (f" · REDUCED run: {', '.join(skipped)} skipped by user override" if skipped else ""))
PY

if [ "$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["files"]))' "$RUN/meta.json")" = "0" ]; then
  python3 -I -c 'import json,sys,time; m=json.load(open(sys.argv[2])); json.dump({"verdict":"PASS","reasons":[],"note":"nothing to review","meta":m,"ts":time.time()}, open(sys.argv[1],"w"))' "$RUN/summary.json" "$RUN/meta.json"
  python3 -I "$HERE/review_sign.py" sign "$RUN/summary.json" || echo "review-fanout: summary not signed" >&2
  printf '# 4-way review: ✅ PASS\n\nNothing to review: no change since %s.\n' "$BASE_SHA" > "$RUN/summary.md"
  cat "$RUN/summary.md"; exit 0
fi
DEPTH="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["depth"])' "$RUN/meta.json")"

# the diff every reviewer reads, written ONCE before any reviewer starts (audit 31/10: each runner wrote it while others read it)
git diff --no-ext-diff "$BASE_SHA" -- > "$RUN/review.diff" 2>/dev/null || : > "$RUN/review.diff"
R="$HERE/review_runner.py"
# the known-pattern scan is a reviewer like the others: it runs alongside them, not before them (speed 31/10)
( python3 -I "$HERE/known_patterns.py" --repo "$REPO" scan --base "$BASE_SHA" --out "$RUN/registry.json" >/dev/null
  [ -f "$RUN/registry.json" ] || python3 -I -c 'import json,sys; json.dump({"reviewer":"registry","status":"error","reason":"known_patterns scan failed"}, open(sys.argv[1],"w"))' "$RUN/registry.json" ) & PIDS="$!"
python3 -I "$R" claude      --repo "$REPO" --run "$RUN" --timeout "${REVIEW_TIMEOUT_CLAUDE:-900}" & PIDS="$PIDS $!"
python3 -I "$R" antigravity --repo "$REPO" --run "$RUN" --timeout "${REVIEW_TIMEOUT_AGY:-1500}"   & PIDS="$PIDS $!"
for opt in ocr grok; do
  if skipped "$opt"; then
    python3 -I -c 'import json,sys; json.dump({"reviewer":sys.argv[2],"status":"skipped","verdict":"skipped","findings":[],"usage":{"tokens":0,"usd":0.0},"reason":"skipped by user override (REVIEW_SKIP_REVIEWERS / --skip) — reduced run"}, open(sys.argv[1],"w"))' "$RUN/$opt.json" "$opt"
    continue
  fi
  case "$opt" in
    ocr)  python3 -I "$R" ocr  --repo "$REPO" --run "$RUN" --timeout "${REVIEW_TIMEOUT_OCR:-900}"  & PIDS="$PIDS $!" ;;
    grok) python3 -I "$R" grok --repo "$REPO" --run "$RUN" --timeout "${REVIEW_TIMEOUT_GROK:-900}" & PIDS="$PIDS $!" ;;
  esac
done
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

# the tree is hashed again before the verdict is sealed: cite-check and the verifier read the live files, so a change made during
# the review (r14d, BUG-REV-d5a4fc3b03) makes it a FAIL for this hash with no bug rows, never a PASS of code nobody reviewed
NOW="$(code_hash)"
if [ "$NOW" = "$CODE_HASH" ]; then
  python3 -I "$HERE/review-merge.py" --dir "$RUN" --repo "$REPO" --record-bugs ${REVIEW_REGRESSION_STATUS:+--status-file "$REVIEW_REGRESSION_STATUS"}
else
  python3 -I "$HERE/review-merge.py" --dir "$RUN" --repo "$REPO" --tree-changed "${NOW:-unknown}" ${REVIEW_REGRESSION_STATUS:+--status-file "$REVIEW_REGRESSION_STATUS"}
fi
rc=$?
# a FAIL's bug rows land in the tracked .agents/regression_status.json of a linked worktree and move the hash (r14d,
# BUG-REV-49df56afb6: --status then said NONE and the Stop hook started the same billed review again). The code is the same and the
# rows only add blockers, so the sealed FAIL answers for the new state too: same summary, meta.code_hash = the new hash.
AFTER="$(code_hash)"
if [ "$rc" = 1 ] && [ -n "$AFTER" ] && [ "$AFTER" != "$CODE_HASH" ] && [ "$NOW" = "$CODE_HASH" ]; then
  ALIAS="$COMMON/review-fanout/$AFTER"
  mkdir -p "$ALIAS" && chmod 700 "$ALIAS"
  python3 -I - "$RUN/summary.json" "$ALIAS/summary.json" "$AFTER" "$CODE_HASH" <<'PY' \
    && python3 -I "$HERE/review_sign.py" sign "$ALIAS/summary.json" && cp "$RUN/summary.md" "$ALIAS/summary.md" 2>/dev/null \
    || echo "review-fanout: FAIL not re-filed under the post-bug-row hash" >&2
import json, sys
src, dst, new, old = sys.argv[1:5]
s = json.load(open(src, encoding="utf-8"))
if s.get("verdict") != "FAIL":
    sys.exit(1)
s["meta"] = dict(s.get("meta") or {}, code_hash=new, recorded_from=old)
json.dump(s, open(dst, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
PY
fi
echo "(run: $RUN)"
exit "$rc"
