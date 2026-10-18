#!/usr/bin/env bash
# Regression test: the parallel-split detector of the prompt hook (scripts/context/enrich_context.py parallel_split / parallel_hint,
# through hooks/prompt_context.sh). 18/10: the user had to ask "tạo nhiều agent chạy cho nhanh" several times because the leading agent
# split a big request late or never. A request that can be split (several repos, several issues or cards, "song song" / "nhiều agent",
# a numbered list or a list of actions) gets one "- Song song" line; a question, a one-file edit and chit-chat get nothing (INSTINCT-026:
# no new always-on block in the prompt hook).
#   PH_KIT=<devkit dir>   test another copy of the kit (a mutant must go red)
# bash 3.2 compatible; python stdlib only.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${PH_KIT:-$DEVKIT_DIR}"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
unset PROMPT_CONTEXT PROMPT_DEDUPE
mkdir -p "$TMP/proj/.agents" && git -C "$TMP/proj" init -q . || { echo "✖ git init failed"; exit 1; }
printf '{"profile":"universal"}' > "$TMP/proj/.agents/active-profile.json"
python3 -I - "$KIT" "$TMP/proj" <<'PY'
import importlib.util, json, os, subprocess, sys, time

KIT, PROJ = sys.argv[1], sys.argv[2]
fails = 0


def chk(cond, good, why=""):
    global fails
    if cond:
        print("✔ " + good, flush=True)
    else:
        fails += 1
        print("✖ " + good + (" — " + why if why else ""), flush=True)


src = os.path.join(KIT, "scripts", "context", "enrich_context.py")
spec = importlib.util.spec_from_file_location("enrich_under_test", src)
ec = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ec)
split = getattr(ec, "parallel_split", None)
if split is None:
    print("✖ enrich_context.py has no parallel_split: nothing to test", flush=True)
    sys.exit(1)

# (prompt, expected): True = a request that can be split
CASES = [
    ("sửa bug proof_gate ở 4 repo GeelyEx2, OfficeReader, Goods, Neighbours", True),
    ("cập nhật README cho cả ba repo", True),
    ("update the hook docs in all repos", True),
    ("fix hết các issue #12, #15 và #18 trên board", True),
    ("làm 3 thẻ đang Ready trên super-board", True),
    ("fix 3 bugs: login crash, export lỗi, sync chậm", True),
    ("tạo nhiều agent chạy cho nhanh: sửa hook A, viết test cho B", True),
    ("chạy song song giúp tôi: refactor lane_plan và thêm test cho merge gate", True),
    ("run these in parallel: refactor the planner and add tests for the gate", True),
    ("Làm giúp:\n1. Thêm cờ --json cho lanes slots\n2. Sửa lỗi timeout trong merge gate\n3. Cập nhật README", True),
    ("làm hai việc: (1) thêm log cho worktree finish (2) sửa help của agent-kit", True),
    ("Việc hôm nay:\n- sửa hooks/review_gate.sh cho khỏi chặn nhầm\n- thêm test cho scripts/governance/lane_plan.py", True),
    # silent: questions, one file, chit-chat, a single task
    ("song song là gì?", False),
    ("có nên chạy 4 repo song song không?", False),
    ("chạy song song cho 4 repo luôn được chứ?", False),
    ("tại sao lanes plan lại chậm như vậy", False),
    ("giải thích giúp 2 repo này khác nhau thế nào", False),
    ("4 repo đã đồng bộ kit chưa", False),
    ("sửa lỗi typo trong README.md", False),
    ("sửa hooks/proof_gate.sh:\n1. đổi regex của XONG\n2. thêm log khi chặn", False),
    ("cảm ơn, làm tốt lắm", False),
    ("ok tiếp đi nhé", False),
    ("sửa lỗi nút thanh toán bị bấm 2 lần", False),
    ("viết test cho hàm overlaps_of", False),
    ("gọi 2 agent review chéo cái diff này", False),
    ("PR #69 sửa lỗi mà #68 để lại, merge nó đi", False),
    ("bump version lên 1.2.0\nrồi tag lại", False),
    ("Bước tiếp:\n1. chạy lại gate cho worktree này", False),
    ("- sửa lời chào cho thân thiện hơn", False),
    ("sửa 1 lỗi ở màn login", False),
]
for prompt, want in CASES:
    got = split(prompt)
    shown = prompt.replace("\n", " / ")[:70]
    chk(bool(got) == want, ("split (%s): " % got if want else "silent: ") + shown, "got %r" % (got,))

# an agent / harness prompt (role-play opening) never gets it: a lane's own brief must not fan out again
chk(not split("You are a reviewer. 1. read the diff 2. list findings in 4 repos"), "silent on a role-play agent prompt")

# speed: no LLM, regexes only; a long pasted text stays linear
corpus = [p for p, _ in CASES]
t0 = time.perf_counter()
for _ in range(200):
    for p in corpus:
        split(p)
per_call_ms = (time.perf_counter() - t0) * 1000 / (200 * len(corpus))
chk(per_call_ms < 2.0, "detector costs %.3f ms a prompt (budget 2 ms)" % per_call_ms)
big = ("1. " + "x" * 200 + "\n") * 500 + "song song " * 2000
t0 = time.perf_counter()
split(big)
big_ms = (time.perf_counter() - t0) * 1000
chk(big_ms < 100, "a 120 KB prompt is judged in %.1f ms (budget 100 ms)" % big_ms)

# end to end through the hook: the line for a split request, nothing more for chit-chat or a question
HOOK = os.path.join(KIT, "hooks", "prompt_context.sh")
env = dict((k, v) for k, v in os.environ.items() if not k.startswith(("PROMPT_", "CLAUDE_")))
env["CLAUDE_PROJECT_DIR"] = PROJ


def hook(prompt, session="ph-sess"):
    payload = json.dumps({"prompt": prompt, "session_id": session, "cwd": PROJ})
    t0 = time.perf_counter()
    r = subprocess.run(["bash", HOOK], input=payload, capture_output=True, text=True, env=env, cwd=PROJ, timeout=60)
    return r.returncode, r.stdout, (time.perf_counter() - t0) * 1000


rc, out, _ = hook("sửa bug proof_gate ở 4 repo GeelyEx2, OfficeReader, Goods, Neighbours")
chk(rc == 0 and "- Song song" in out and "lanes plan" in out and 'isolation: "worktree"' in out and "--full" in out,
    "hook: a split request gets the parallel line (lanes plan, worktree isolation, one --full)", out)
chk("phiên riêng" in out and "lane" in out, "hook: the line names a separate session for another repo and the no-refan rule for a lane", out)
rc, out, _ = hook("cảm ơn, làm tốt lắm")
chk(rc == 0 and out == "", "hook: chit-chat stays silent", repr(out))
rc, out, _ = hook("có nên chạy 4 repo song song không?")
chk(rc == 0 and "- Song song" not in out, "hook: a question gets no parallel line", out)
rc, out, _ = hook("sửa lỗi typo trong README.md")
chk(rc == 0 and "- Song song" not in out, "hook: a one-file edit gets no parallel line", out)
# a second split request in the same session still gets it: each big request is a new decision
rc, out, _ = hook("Làm giúp:\n1. Thêm cờ --json cho lanes slots\n2. Sửa lỗi timeout trong merge gate")
chk(rc == 0 and "- Song song" in out, "hook: a second split request in the session gets the line again", out)

# hook wall time, with and without the detector's line (median of 5 runs, reported; the budget is the detector's own cost above)
pos = sorted(hook("làm 3 thẻ đang Ready trên super-board", "lat-%d" % i)[2] for i in range(5))[2]
neg = sorted(hook("cảm ơn, làm tốt lắm", "lat-n-%d" % i)[2] for i in range(5))[2]
print("ℹ hook wall time (median of 5): split request %.0f ms, chit-chat %.0f ms" % (pos, neg), flush=True)

sys.exit(1 if fails else 0)
PY
exit $?
