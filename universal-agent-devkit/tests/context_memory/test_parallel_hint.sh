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
    ("sao chép hooks mới sang 3 repo", True),
    ("sao lưu config của tất cả repo", True),
    ("làm 3 thẻ đang Ready trên https://github.com/org/board", True),
    ("fix issues #12, #15 and #18", True),
    ("làm thẻ 41, 42, 43 trên board", True),
    ("fix every project's README", True),
    ("sửa hooks/x.sh ở cả 4 repo", True),
    ("dùng nhiều agent: sửa hook A, viết test cho B", True),
    ("Việc hôm nay ...\n- sửa login\n- thêm test export", True),
    ("dùng nhiều agent: sửa login / thêm export", True),
    # round 2 (OCR + reviewer 18/10)
    ("làm 3 thẻ đang Ready trên github.com/org/board", True),
    ("fix issues #12, #15 and #18 in github.com/org/repo", True),
    ("để tôi xem, sửa 4 repo đi", True),
    ("có 3 bug cần sửa: login, export, sync", True),
    ("What to do:\n1. fix the login\n2. add tests for export", True),
    # silent: questions, one file, chit-chat, a single task
    ("song song là gì?", False),
    ("có nên chạy 4 repo song song không?", False),
    ("chạy song song cho 4 repo luôn được chứ?", False),
    ("tại sao lanes plan lại chậm như vậy", False),
    ("giải thích giúp 2 repo này khác nhau thế nào", False),
    ("giải thích giúp cách 4 repo dùng chung một bản kit", False),
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
    # review 18/10: a list, a plural or a word that is the topic of the request, not a split
    ("Steps to reproduce:\n1. run the app\n2. update the profile name\n3. it crashes. Fix it.", False),
    ("commit các việc còn lại rồi push", False),
    ("merge các PR đã duyệt", False),
    ("đọc các issue và tóm tắt cho tôi", False),
    ("thêm nút xoá, hiện 3 lỗi đỏ trong log", False),
    ("add retry with 3 tasks max in the queue", False),
    ("xem log:\n- run 1 failed\n- run 2 passed", False),
    ("dán log:\n```\n1. fix A\n2. fix B\n```\nlỗi gì đây", False),
    ("sửa lỗi multi-agent bị treo trong hooks/session_lock.sh", False),
    ("fix parallel test flakiness in test_merge_gate.sh", False),
    ("tối ưu để test chạy song song", False),
    ("Error: fan-out failed at step 3", False),
    ("sửa lỗi khi nhiều agent cùng ghi một file", False),
    ("tests fail when run in parallel, fix that", False),
    ("sửa lỗi treo khi review 2 PR cùng lúc", False),
    ("crash when you fix 3 bugs in a row", False),
    ("make the test runner run in parallel", False),
    ("sửa crash ở dòng #12, #15 của log", False),
    # #75: the one file named is a LIST of work (Markdown / txt), not the file to edit: the count still splits
    ("fix hết 5 bug trong docs/issues-bugs.md", True),
    ("làm 3 việc trong TODO.md", True),
    ("fix all 4 issues listed in notes/backlog.txt", True),
    # …but a source file named with several steps, or a count of edits inside one non-list file, stays one lane
    ("sửa hooks/proof_gate.sh:\n1. đổi regex của XONG\n2. thêm log khi chặn", False),
    ("sửa 3 lỗi trong hooks/proof_gate.sh", False),
    ("sửa lỗi 3 chỗ trong README.md", False),
    ("fix hết 5 bug trong docs/issues-bugs.md: tại sao lại đỏ?", False),
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
chk(per_call_ms < 10.0, "detector costs %.3f ms a prompt (budget 10 ms: a busy runner must not flake it)" % per_call_ms)
# review 18/10: a search for "?\W*$" over "(?, ?)" placeholders took 20 s on 40 KB (past the hook's 10 s timeout)
BIG = [("list + words", ("1. sửa " + "x" * 200 + "\n") * 500 + "song song " * 2000),
       ("question marks", "? " * 20000 + "sửa đi"),
       ("SQL placeholders", "INSERT INTO t VALUES " + "(?, ?), " * 3000 + "(1, 2) sửa giúp"),
       ("unclosed fences", "```\n" * 5000 + "sửa đi")]
for name, big in BIG:
    t0 = time.perf_counter()
    split(big)
    big_ms = (time.perf_counter() - t0) * 1000
    # 2 s: idle ~15 ms, 220-245 ms at load 145 (18/10), the quadratic search 3.7-18 s: the budget still catches it on a busy runner
    chk(big_ms < 2000, "a %d KB prompt (%s) is judged in %.1f ms (budget 2 s: linear, not quadratic)" % (len(big) // 1000, name, big_ms))

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
# the triage rule (user 18/10: "nào cực quan trọng thì làm còn ko quan trọng thì đưa vô backlog xử lý sau"): a new defect found mid-batch is
# fixed now only when it is critical, anything else becomes a Backlog card through createTask
chk("cực quan trọng" in out and "mất dữ liệu" in out and "gate báo xanh sai" in out and "createTask" in out and "Backlog" in out,
    "hook: the line carries the triage rule (critical now, the rest a Backlog card via createTask)", out)
rc, out, _ = hook("cảm ơn, làm tốt lắm")
chk(rc == 0 and out == "", "hook: chit-chat stays silent", repr(out))
rc, out, _ = hook("có nên chạy 4 repo song song không?")
chk(rc == 0 and "- Song song" not in out, "hook: a question gets no parallel line", out)
rc, out, _ = hook("sửa lỗi typo trong README.md")
chk(rc == 0 and "- Song song" not in out, "hook: a one-file edit gets no parallel line", out)
# a second split request in the same session still gets it: each big request is a new decision
rc, out, _ = hook("Làm giúp:\n1. Thêm cờ --json cho lanes slots\n2. Sửa lỗi timeout trong merge gate")
chk(rc == 0 and "- Song song" in out, "hook: a second split request in the session gets the line again", out)

# the very same split request again (the user had to ask again): the dedupe must not turn the line into "như lượt trước"
rc, out, _ = hook("sửa bug proof_gate ở 4 repo GeelyEx2, OfficeReader, Goods, Neighbours", "ph-same")
rc, out, _ = hook("sửa bug proof_gate ở 4 repo GeelyEx2, OfficeReader, Goods, Neighbours", "ph-same")
chk(rc == 0 and "- Song song" in out, "hook: the same split request twice in a session still gets the line", out)

# hook wall time, with and without the detector's line (median of 5 runs, reported; the budget is the detector's own cost above)
pos = sorted(hook("làm 3 thẻ đang Ready trên super-board", "lat-%d" % i)[2] for i in range(5))[2]
neg = sorted(hook("cảm ơn, làm tốt lắm", "lat-n-%d" % i)[2] for i in range(5))[2]
print("ℹ hook wall time (median of 5): split request %.0f ms, chit-chat %.0f ms" % (pos, neg), flush=True)

# #231: the measured table (real prompts, masked) stays true to the detector: its "actual" column is what parallel_split says today,
# it has >=100 rows, and no row carries a path, URL, mention, key or hash.
import re
rows = [l.rstrip("\n").split("\t", 2) for l in open(os.path.join(KIT, "tests", "context_memory", "data", "parallel_split_eval.tsv"),
                                                    encoding="utf-8") if not l.startswith("#") and l.strip()]
chk(len(rows) >= 100, "eval table: at least 100 prompts (%d)" % len(rows))
stale = [r[2][:40] for r in rows if int(r[1]) != (1 if split(r[2]) else 0)]
chk(not stale, "eval table: the 'actual' column matches parallel_split today", "; ".join(stale[:3]))
leak = [r[2][:40] for r in rows if re.search(r"https?://|/Volumes/|/Users/|@\w|sk-|\b[0-9a-f]{7,40}\b", r[2])]
chk(not leak, "eval table: no path, URL, mention, key or hash in a prompt", "; ".join(leak[:3]))

sys.exit(1 if fails else 0)
PY
exit $?
