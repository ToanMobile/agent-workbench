#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# test_evidence_gate.sh — Stop hook: CLAUDE.md `check 2` + `6.4`.
#
# Closes the hole `claim_check.sh` documents but does not cover: its Check B only
# LOGS "test pass" phrases and defers to "the gradle Stop gate" for the real
# verification. That gate did not exist. This is it.
#
# ── check 2: a test-PASS claim must match the XML ──
# BLOCK when the final message claims tests pass and the counts in
# `**/build/test-results/**/TEST-*.xml` (unit tests) or
# `**/build/outputs/androidTest-results/connected/**/TEST-*.xml` (instrumented)
# do not back it:
#   • no XML at all                          → the tests never ran
#   • every XML older than the last code edit → the run predates the code
#   • tests == 0                             → nothing executed
#   • failures > 0 or errors > 0             → not a pass
#   • skipped > 0 not mentioned in the message → a skip is not a pass
#
# ── 6.4: two failed fixes on the same root cause ──
# Proxy, since "root cause" has no machine definition: the SAME testcase id
# (classname#name) failing across two distinct test RUNS, with code edited in
# between. Two attempts, same test still red = two failed fixes at the same
# thing. State per session in audit-gate/failcycle_<session>.json.
#
# WHAT THIS CANNOT DO — do not read more into a pass than this:
#   • RED-check (`check 2` mutation testing). Nothing here proves a green test
#     would go red without the fix. A green run with no paired red is still
#     BLOCKED by the rule, and only you can honour that.
#   • Whether the tests that ran are the ones covering your change: it compares
#     timestamps and counts, not coverage of the diff.
# ── RED-check outside the JVM: a test file (*.test.ts, test_*.py, *_test.go,
#   *Tests.swift …) written this session that ran GREEN must have been seen RED by a
#   runner after its last edit and before that green run (jest/vitest/pytest output
#   must name the file; go/cargo/swift output names none, so any red run counts).
#
# ── lesson reminder: a proven fix ("đã fix" + RED→GREEN or workflow proof) with no
#   `agent-kit learn` / `--record-lesson` / edit of .agents/instincts.md in the
#   session holds the stop ONCE per session with the command. LESSON_REMINDER=0 off.
# ── bug-link reminder: the same proven fix while a bug row this session registered (a
#   bug prompt → REPORTED) or touched (agent-kit bugs add/link) has no test linked holds
#   the stop ONCE with `agent-kit bugs link <BUG-ID> <test>`; merged with the lesson
#   reminder into one block. BUG_LINK_REMINDER=0 off.
# ── RED-proof: the same proven fix starts scripts/red_proof.py in the background for this
#   session's linked bugs (sandbox: RED without the fix, GREEN with it); a bug of this
#   session whose test came out VACUOUS holds the stop once. RED_PROOF=0 off.
#
# ── check 7: an outcome claim ("đã fix") needs one of two proofs from THIS session:
#   • a paired RED→GREEN test run — a runner result that FAILED before the last
#     source edit and one that PASSED after it (npm/jest/pytest/cargo/go/gradle…), or
#   • a scoped multi-lens-audit workflow result bound to the claim.
#   It cannot tell whether the red test reproduced THIS bug — only that a red→green
#   cycle around the fix happened.
#   • Understand every natural-language paraphrase. The vocabulary classifier is
#     best-effort; a message not blocked here is NOT evidence that its claim is
#     true. The no-fabrication and paired-oracle rules remain authoritative.
#
# Non-Gradle repos (no gradlew/build.gradle*): with no XML, a successful test
# runner call (npm/jest/vitest/pytest/cargo/go/swift/dotnet/… test) after the last
# source edit, whose output shows no failure, backs the claim (QA K-10).
# Unity counts too: unity-batch.sh editmode|playmode, scripts/unity-test.sh, the Editor
# with -runTests, or mcp__antigravity-pm__pm_run kind=test (`exit=N`). Their NUnit 3
# XML (Logs/agent-kit/tests_*.xml) is read like TEST-*.xml: `<test-run failed="N">`,
# red only when N > 0, stale when older than the last .cs edit.
#
# Escape hatch: TEST_EVIDENCE_GATE=0 (logged). Fail-open on internal error.
# Stop hook protocol: stdin JSON; exit 2 blocks (stderr→Claude); exit 0 allows.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"
mkdir -p "${LOG_DIR}"
[ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true

INPUT="$(cat)"

if [ "${TEST_EVIDENCE_GATE:-1}" = "0" ]; then
  echo "[$(date +%Y-%m-%dT%H:%M:%S)] TEST_EVIDENCE_GATE=0 — gate bypassed" >> "${LOG_DIR}/test_evidence_gate.log" 2>/dev/null
  exit 0
fi

# QA K-4: without python3 this gate cannot run — say so instead of passing silently.
if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ test_evidence_gate: python3 không có — gate này KHÔNG chạy, kết quả không được kiểm." >&2
  exit 0
fi
TE_INPUT="${INPUT}" TE_LOG="${LOG_DIR}/test_evidence_gate.log" TE_DIR="${LOG_DIR}" \
TE_TS="$(date +%Y-%m-%dT%H:%M:%S)" TE_REPO="${REPO_ROOT}" TE_SELF="$0" \
python3 <<'PY'
import os, sys, json, re, glob, time
import xml.etree.ElementTree as ET

raw    = os.environ.get("TE_INPUT", "")
log    = os.environ.get("TE_LOG", "/dev/null")
state_dir = os.environ.get("TE_DIR", "/tmp")
ts     = os.environ.get("TE_TS", "?")
repo   = os.environ.get("TE_REPO", ".")

def logline(s):
    try:
        with open(log, "a") as fh:
            fh.write(s + "\n")
    except Exception:
        pass

try:
    d = json.loads(raw)
except Exception as e:
    logline(f"[{ts}] stdin parse fail: {e!r} — fail-open")
    sys.exit(0)

# Loop guard (QA K-12, 2026-09-23). This is a REMINDER gate, not fail-closed:
# Claude Code sets stop_hook_active on the Stop that follows a block, and a gate
# that blocks forever wedges the session. Previously the very first re-Stop was
# released silently. Now the chain is counted per session: the gate may block
# TEST_EVIDENCE_GATE_MAX_RESTOPS (default 1) more time(s) on re-Stop, then releases — loudly, to
# stderr and the log — and the unverified claim becomes the model's duty.
_sid = re.sub(r"[^A-Za-z0-9_-]", "_", str(d.get("session_id") or "default"))[:64] or "default"
_chain = os.path.join(os.path.dirname(log) or ".", f"test_evidence_gate_stopchain_{_sid}")
try:
    _extra = int(os.environ.get("TEST_EVIDENCE_GATE_MAX_RESTOPS", "1") or "1")
except ValueError:
    _extra = 1
_chain_n = 0
if d.get("stop_hook_active"):
    try:
        _chain_n = int(open(_chain).read().strip() or "0") + 1
    except Exception:
        _chain_n = 1
    try:
        open(_chain, "w").write(str(_chain_n))
    except Exception:
        pass
else:
    try:
        os.remove(_chain)
    except Exception:
        pass
_real_exit = sys.exit
def _guarded_exit(code=0):
    if code == 2 and _chain_n > _extra:
        logline(f"[{ts}] RELEASED on re-Stop #{_chain_n} — claim still unverified")
        sys.stderr.write("⚠ test_evidence_gate: đã nhắc lại {} lần — THẢ Stop để tránh kẹt vòng lặp. "
                         "Claim ở trên vẫn CHƯA được kiểm chứng.\n".format(_chain_n))
        _real_exit(0)
    _real_exit(code)
sys.exit = _guarded_exit

msg = d.get("last_assistant_message")
if not isinstance(msg, str):
    msg = ""

# ── is there a test-PASS claim? (cheap, decided BEFORE any XML parsing) ─────
# Keep quoted/inline-code text in the classification view: typography cannot
# turn `Result: "12/12 tests passed"` or ``Status: `fixed` `` into a bypass.
# Explicit prohibition/plan/metalinguistic grammar below exempts non-claims.
# The binding view removes delimiters but keeps identifiers/hashes available.
scan = re.sub(r"```.*?```", " ", msg, flags=re.DOTALL)
scan = scan.replace("**", "")
binding_scan = re.sub(r"[`\"“”]", "", scan)
# A dot inside a symbol/key (`logic.wrong_branch`) is not a sentence boundary.
# Split terminal punctuation only when it is followed by whitespace/end.
sentences = re.split(r"(?:\n|[!?](?=\s|$)|\.(?=\s|$))", scan)
binding_sentences = re.split(r"(?:\n|[!?](?=\s|$)|\.(?=\s|$))", binding_scan)

CLAIM = re.compile(
    r"(test[^.\n]{0,24}(?:pass|xanh|green|thành công)"
    r"|(?:pass|xanh|green)[^.\n]{0,24}test"
    r"|\d+\s*/\s*\d+\s+test"
    r"|tests?\s+passed"
    r"|(?:toàn\s+bộ|tất\s+cả)\s+(?:kiểm\s+thử|tests?)[^.\n]{0,16}(?:đều\s+)?đạt)", re.I)
# A PROHIBITION is not a result. Quoting the rule it enforces ("cấm sửa test cho
# xanh", "đừng gọi là pass") puts the trigger words in the sentence with the
# meaning inverted, and bold `**…**` is not scrubbed the way backticks/quotes are.
# Measured 2026-07-28: this gate blocked a documentation-audit response whose only
# match was the phrase `test cho xanh` inside `**cấm sửa test cho xanh**` — zero
# test claims in the whole message. Positional as with the other markers, so a
# prohibition AFTER a real claim ("Test pass 6/6, cấm sửa test cho xanh") still fires.
# `chạy lại` was in this list and let a REAL claim through: "Đã chạy lại, 12/12
# test pass" disarmed itself, because the marker sits before the claim and the
# check is positional. Past tense is an assertion, not a hypothesis. Removed
# 2026-07-28 — the advice forms it was meant to cover ("cần chạy lại test",
# "nên chạy lại") already carry cần/nên, and "chạy lại test thì pass" is caught
# by the trailing-`thì` rule.
GOVERNING_PREFIX = re.compile(
    r"(?:\b(?:nếu|if|giả sử|khi)\s*$"
    r"|\b(?:cấm|đừng|không được|never|must not)\s+(?:(?:nói|viết|gọi|claim|sửa)\s+)?$"
    r"|\bkhông được đoán và nói\s*$)",
    re.I,
)
TEST_GUIDANCE_PREFIX = re.compile(
    r"(?:\b(?:nên|cần)\s+(?:chạy lại\s+)?$|\bshould\s+(?:rerun\s+)?$)",
    re.I,
)
OUTCOME_GUIDANCE_PREFIX = re.compile(
    r"\b(?:nên|cần)\s+(?:được\s+)?$|\b(?:should|must)\s+(?:be\s+)?$",
    re.I,
)
PLAN_PREFIX = re.compile(r"^\s*(?:verify\s*(?::|that\b)|acceptance\s*:)", re.I)
VERIFY_PREFIX = re.compile(r"\bverify\s*:\s*$", re.I)
META_QUOTE_PREFIX = re.compile(
    r"\b(?:cụm(?:\s+từ)?|chuỗi|từ\s+khóa|ví\s+dụ)\s*$",
    re.I,
)
def is_nonassertive(sentence, match, kind):
    """Only explicit grammar may exempt a matched result/outcome phrase.

    Default is ASSERTION. Generic `chưa/không/thì` elsewhere in the sentence
    cannot erase an independent claim.
    """
    prefix = re.sub(r"[`\"“”]", "", sentence[:match.start()])
    matched_text = match.group(0)
    if GOVERNING_PREFIX.search(prefix):
        return True
    plan_prefix = PLAN_PREFIX.search(sentence)
    plan_boundary = None
    if plan_prefix:
        boundary = re.search(
            r"[,;—–]|\s-\s|\n|\b(?:and\s+in\s+fact|và\s+thực\s+tế"
            r"|nhưng|but|tuy\s+nhiên|song|mà|rồi)\b",
            sentence[plan_prefix.end():],
            re.I,
        )
        if boundary:
            plan_boundary = plan_prefix.end() + boundary.start()
    if ((plan_prefix and (plan_boundary is None or match.start() < plan_boundary))
            or VERIFY_PREFIX.search(prefix)):
        return True
    if META_QUOTE_PREFIX.search(prefix):
        return True
    if kind == "test":
        suffix = sentence[match.end():]
        return bool(
            TEST_GUIDANCE_PREFIX.search(prefix)
            or re.search(r"\b(?:should|must)\b", matched_text, re.I)
            or (
                sentence.lstrip().lower().startswith("test")
                and re.match(r"\s+thì\b", suffix, re.I)
            )
            # "RED" joined directly by "/" or "-" to the match (the compound
            # "RED/GREEN test" this rulebook's own vocabulary uses for the TDD
            # cycle name) is not an assertion that green/pass happened. Measured
            # 2026-07-31: "không thể chạy RED/GREEN test" (an incapacity claim)
            # false-positived because GOVERNING_PREFIX's negation words require
            # zero-gap adjacency to the match, and "RED/" sits in that gap.
            # MUST stay this narrow (literal "red" + "/" or "-", zero gap) —
            # an 8-char free-form window was tried first and adversarial-tested
            # 2026-07-31 to falsely exempt genuine claims: "RED test giờ pass
            # 12/12", "RED test bây giờ green hết" (a real named RED-suffixed
            # test — e.g. DOCXBidiMetadataRedTest — actually passing is exactly
            # the claim this gate must catch). Do not widen the join character
            # class or the gap without re-running that adversarial set.
            or bool(re.search(r"\bred[/-]\s*$", prefix, re.I))
        )
    return bool(OUTCOME_GUIDANCE_PREFIX.search(prefix))

claimed = False
for sent in sentences:
    for m in CLAIM.finditer(sent):
        if is_nonassertive(sent, m, "test"):
            continue
        claimed = True
        break
    if claimed:
        break

# An outcome claim is separate from a test-pass claim. This must be classified
# before the cheap early exit below; otherwise plain "đã fix bug" bypasses the
# entire outcome-evidence check when no new XML exists.
OUTCOME = re.compile(
    r"(đã\s+fix\b|đã\s+sửa\s+xong|đã\s+(?:được\s+)?sửa\s+(?:xong\s+)?(?:bug|lỗi)"
    r"|(?:bug|lỗi)[^.\n]{0,32}đã\s+(?:được\s+)?sửa\b"
    r"|đã\s+khắc\s+phục|đã\s+xử\s+lý"
    r"|đã\s+giải\s+quyết(?:\s+xong)?|hết\s+bug"
    r"|(?:the\s+)?fix\s+(?:works?|worked|has\s+worked|(?:đã\s+)?có\s+tác\s+dụng)"
    r"|bug\s+đã\s+(?:được\s+)?fix|(?:lỗi|bug)[^.\n]{0,48}không\s+(?:còn\s+)?tái\s+hiện(?:\s+nữa)?"
    r"|\bfixed\b|\bresolved\b)", re.I)

outcome_claims = []
for sent_idx, sent in enumerate(sentences):
    bound_sent = binding_sentences[sent_idx] if sent_idx < len(binding_sentences) else sent
    clauses = re.split(r";", sent)
    bound_clauses = re.split(r";", bound_sent)
    sentence_start = len(outcome_claims)
    for clause_idx, clause in enumerate(clauses):
        bound_clause = bound_clauses[clause_idx] if clause_idx < len(bound_clauses) else clause
        matches = []
        for m in OUTCOME.finditer(clause):
            if is_nonassertive(clause, m, "outcome"):
                continue
            matches.append(m)
        for _ in matches:
            # A pending/residual marker does not erase a definite outcome claim
            # in the same or a neighbouring clause. Every occurrence remains a
            # separately authorized claim.
            outcome_claims.append({
                "clause": bound_clause,
                "sentence": bound_sent,
                "occurrences": len(matches),
            })
    sentence_occurrences = len(outcome_claims) - sentence_start
    for claim in outcome_claims[sentence_start:]:
        claim["sentenceOccurrences"] = sentence_occurrences
outcome_claimed = bool(outcome_claims)

# ── collect XML evidence ────────────────────────────────────────────────────
# stat is cheap, ET.parse is not: this runs on EVERY Stop, and a gate that taxes
# every turn for nothing is the fastest way to get itself switched off. Measured
# 2026-07-27: parsing all 157 suites unconditionally cost ~1.0s per Stop.
# So: stat everything, parse only the subset a live question depends on.
# Bounded globs, NOT `**` recursive: a recursive walk of the whole repo costs
# ~1s per Stop here because it descends every build/ and .gradle/ tree. Gradle
# modules in this project sit at depth 1 (`app/`) or 2 (`core/analytics/`), so
# two fixed-depth patterns cover them and cost milliseconds. Add a depth-3
# pattern here if a module is ever nested deeper.
xmls = []
for pat in ("*/build/test-results/*/TEST-*.xml",
            "*/*/build/test-results/*/TEST-*.xml",
            "*/*/*/build/test-results/*/TEST-*.xml",
            # connectedAndroidTest writes to build/outputs/androidTest-results/,
            # NOT build/test-results/. Without these three the gate is blind to
            # every instrumented run — the exact oracle the release QA lane
            # depends on — and blocks device-backed claims as "never ran".
            # Measured 2026-08-07: a green run at
            # app/build/outputs/androidTest-results/connected/release/TEST-*.xml
            # matched none of the patterns above.
            "*/build/outputs/androidTest-results/connected/TEST-*.xml",
            "*/build/outputs/androidTest-results/connected/*/TEST-*.xml",
            "*/*/build/outputs/androidTest-results/connected/*/TEST-*.xml",
            # Unity writes NUnit 3 XML, not JUnit: profiles/game/scripts/unity-batch.sh
            # puts it at Logs/agent-kit/tests_<EditMode|PlayMode>.xml, a project's own
            # scripts/unity-test.sh (run by pm_run) at .antigravity-pm/logs/tests_*.xml.
            # Without these a Unity repo had no result file the gate could see.
            "Logs/agent-kit/tests_*.xml",
            ".antigravity-pm/logs/tests_*.xml"):
    xmls.extend(glob.glob(os.path.join(repo, pat)))
mtimes = {}
for p in xmls:
    try:
        mtimes[p] = os.path.getmtime(p)
    except Exception:
        pass

def parse_suites(path):
    """One dict per <testsuite> in the file; [] if the file is not test results.

    Gradle unit-test XML puts <testsuite> at the ROOT. connectedAndroidTest
    wraps one or more suites in a <testsuites> root instead. Until 2026-08-07
    this returned None for anything but a bare <testsuite>, so every
    instrumented run parsed to nothing and the gate reported "tests never ran"
    for device-backed claims — measured against a real green run whose root was
    <testsuites tests="1" failures="0" errors="0" skipped="0">.

    Counts are read PER SUITE, never from the <testsuites> wrapper, so the
    per-suite scoping below (red inside vs outside the touched module) keeps
    working: a wrapper total cannot be attributed to a module.
    """
    try:
        root = ET.parse(path).getroot()
        mtime = os.path.getmtime(path)
    except Exception:
        return []
    if root.tag == "test-run":
        # NUnit 3 (Unity Test Framework): the <test-run> totals are the run's own
        # verdict. `failed` counts only when non-zero; errors are folded into it.
        def a(k):
            try:
                return int(root.attrib.get(k, "0") or 0)
            except ValueError:
                return 0
        cases = list(root.iter("test-case"))
        failing = [f"{tc.attrib.get('classname','?')}#{tc.attrib.get('name','?')}"
                   for tc in cases if tc.attrib.get("result") == "Failed"]
        return [{
            "path": path, "mtime": mtime, "name": "",
            "tests": a("total") if "total" in root.attrib else len(cases),
            "failures": a("failed") if "failed" in root.attrib else len(failing),
            "errors": 0, "skipped": a("skipped"),
            "failing": failing,
        }]
    if root.tag == "testsuite":
        nodes = [root]
    elif root.tag == "testsuites":
        nodes = list(root.findall("testsuite"))
    else:
        return []
    out = []
    for node in nodes:
        failing = []
        for tc in node.iter("testcase"):
            if tc.find("failure") is not None or tc.find("error") is not None:
                failing.append(f"{tc.attrib.get('classname','?')}#{tc.attrib.get('name','?')}")
        def g(k, _n=node):
            return int(_n.attrib.get(k, "0") or 0)
        out.append({
            "path": path, "mtime": mtime,
            "name": node.attrib.get("name", ""),
            "tests": g("tests"), "failures": g("failures"),
            "errors": g("errors"), "skipped": g("skipped"),
            "failing": failing,
        })
    return out

# ── load 6.4 state, decide whether anything needs parsing at all ────────────
sid = re.sub(r"[^A-Za-z0-9_-]", "_", str(d.get("session_id", "default")))[:64] or "default"
state_path = os.path.join(state_dir, f"failcycle_{sid}.json")
state = {"last_run": 0.0, "streak": {}}
try:
    if os.path.exists(state_path):
        state.update(json.load(open(state_path)))
except Exception:
    pass

newest = max(mtimes.values(), default=0.0)
new_run = newest > state.get("last_run", 0.0)

if not claimed and not outcome_claimed and not new_run:
    logline(f"[{ts}] no test claim, no new run ({len(mtimes)} xml) — pass")
    sys.exit(0)

# ── one transcript pass: edits, RED history, structured scoped proof ─────────
last_edit_mtime = 0.0
authored_tests = {}      # simple class name -> mtime of that test file
touched_modules = set()  # module roots ("core/data") holding a .kt/.java edited this session
structured_fix_proofs = []
blk_idx = 0
tool_uses = {}
tool_results = {}
# Non-Gradle projects (QA K-10, 2026-09-23): npm/jest/pytest/cargo/go/swift runs
# write no TEST-*.xml, so the gate also accepts a runner's own tool_result as
# evidence — only in repos with no Gradle build and no XML at all.
TEST_RUNNER_RX = re.compile(
    r"\b(npm|yarn|pnpm|bun)\s+(run\s+)?test|\b(npx\s+)?(jest|vitest|mocha)\b|\bpytest\b|"
    r"python\S*\s+-m\s+(pytest|unittest)|\b(cargo|go|swift|dotnet|flutter|deno)\s+test\b|"
    r"\bnode\s+--test\b|\bxcodebuild\b.*\btest\b|\bmvn\s+(test|verify)\b|\bmake\s+(test|check)\b|"
    r"\bctest\b|\brspec\b|\bphpunit\b|\bgradlew?\b[^\n|;&]*\b\w*[tT]est\w*\b|"
    # Unity: the DevKit's unity-batch.sh test modes (not `compile`/`execute`), a
    # project's scripts/unity-test.sh, or the Editor itself with -runTests.
    r"\bunity-batch\.sh\b[^\n|;&]*\b(edit|play)mode\b|\bunity-test\.sh\b|(?<![\w-])-runTests\b", re.I)
# Failure markers. Counts only when non-zero ("fail 0", "0 failed" are green), and the
# bare words only in the capitals runners print (FAIL, FAILED, ERROR) — a passing test
# named "shows error message" or node's "ℹ fail 0" summary must not read as red.
# NUnit 3 (Unity) prints its verdict as `<test-run … failed="N">`: red only when N > 0.
RUNNER_FAIL_RX = re.compile(
    r"(?i:\b[1-9]\d*\s+(failed|failing|failures?|errors?)\b)|(?i:\btests?:\s+[1-9]\d*\s+failed)|"
    r"(?i:^\s*(?:[#ℹ*•-]\s*)?(fail|failures?|errors?)\s*[:=]?\s*[1-9]\d*\b)|"
    r"<test-run\b[^>\n]*\sfailed=\"[1-9]\d*\"|"
    r"\bFAIL(ED)?\b|test result: FAILED|^not ok\b|\bpanicked\b|\bERRORS?\b|--- FAIL", re.M)
# mcp__antigravity-pm__pm_run kind=test runs the project's test command and prints
# `exit=N` per command (a timeout adds "(QUA HAN)"; "CHUA TINH" = exit 0 that its own
# evidence check did not accept as green). No `exit=` line = the tool refused before
# running anything, which is neither red nor green.
PM_RUN_EXIT_RX = re.compile(r"^exit=(-?\d+|null)", re.M)

def runner_state(is_error, txt, pm_run=False):
    """"red", "green", or None (not a verdict) for one runner tool_result."""
    if pm_run:
        codes = PM_RUN_EXIT_RX.findall(txt)
        if not codes:
            return None
        if any(c != "0" for c in codes) or "(QUA HAN)" in txt:
            return "red"
        # The acceptance-gate lines after the run output are about the task, not the run.
        run_txt = txt.split("CONG NGHIEM THU")[0]
        if is_error or "CHUA TINH" in run_txt or RUNNER_FAIL_RX.search(run_txt):
            return None
        return "green"
    return "red" if (is_error or RUNNER_FAIL_RX.search(txt)) else "green"
SRC_EXT = (".kt", ".kts", ".java", ".swift", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".py",
           ".go", ".rs", ".dart", ".cs", ".c", ".cc", ".cpp", ".h", ".hpp", ".m", ".mm")
runner_results = []        # (result_idx, use_idx, is_error, text, command, "red"|"green")
# Bug rows this session registered or changed from the shell (agent-kit bugs add/link,
# regression_checklist.py add/bug-link): the ids their output printed.
BUGS_CMD_RX = re.compile(r"agent-kit[\"']?\s+(?:bugs|req)\s+(?:add|link)\b"
                         r"|regression_checklist\.py[\"']?\s+(?:.*\s)?(?:add|bug-link|req-add|req-link)\b")
BUG_ID_RX = re.compile(r"\b(?:BUG-[A-Za-z0-9_.-]*[A-Za-z0-9]|REQ-\d+)")
bugs_touched = set()
# Test files outside the JVM (jest/vitest/pytest/go/swift…): the RED-check reads
# runner output instead of TEST-*.xml for them.
SCRIPT_TEST_RX = re.compile(
    r"(\.(test|spec)\.(m|c)?[jt]sx?$|(^|/)test_[^/]*\.py$|_test\.(py|go|dart)$|Tests?\.swift$|_spec\.rb$)")
SCRIPT_TEST_DIR_RX = re.compile(r"(^|/)(tests?|__tests__|spec)/[^/]+\.(py|[jt]sx?|mjs|cjs|rb|swift|dart|rs)$")
TEST_FILE_IN_OUTPUT = re.compile(
    r"[\w./-]+\.(test|spec)\.(m|c)?[jt]sx?\b|\btest_\w+\.py\b|\b\w+_test\.(go|py|dart)\b|\b\w+Tests?\.swift\b")
script_test_idx = {}      # test file path -> transcript position of its last edit
script_pending = {}       # test file path -> LIFO of (old, new) edits not yet undone
script_idx_before = {}    # test file path -> [script_test_idx before each edit]
last_src_edit_idx = -1
edit_log = []             # (transcript position, file path) of every Edit/Write/NotebookEdit
no_id_tool_indices = []
test_edit_idx = {}       # simple class name -> transcript position of its last edit
red_idx = {}             # suite name -> transcript position where it was seen RED
# Per test file, a LIFO stack of edits not yet undone, and the test_edit_idx value each one
# displaced. Used to recognise a mutate/restore pair — see the rollback below.
pending_edits = {}       # file path -> [(old_string, new_string), ...]
edit_idx_before = {}     # file path -> [test_edit_idx value in force before that edit, ...]

# A full RED→GREEN cycle inside ONE turn is invisible to the Stop-time snapshot:
# the green run overwrites the red XML before any Stop happens, so the gate
# accuses the person who did the RED-check properly of never having done one
# (measured 2026-07-27 — it blocked exactly that). The evidence is still in the
# transcript though: the failing run was printed there. Read it from that side too.
#
# The negated classes exclude \n on purpose. A <testsuite> tag is one line, but
# [^>] matches newlines, so on a block holding SEVERAL suites the greedy run
# crossed line boundaries and backtracked to the LAST name= in the block — every
# suite but the final one was silently dropped. Measured 2026-07-28: a RED-check
# that printed two failing suites in one tool_result registered only the second,
# and the gate accused the first of never having been red.
RED_XML = re.compile(r'<testsuite[^>\n]*name="([^"\n]+)"[^>\n]*(?:failures|errors)="([1-9]\d*)"')
RED_XML2 = re.compile(r'<testsuite[^>\n]*(?:failures|errors)="([1-9]\d*)"[^>\n]*name="([^"\n]+)"')
RED_GRADLE = re.compile(r'([\w.]*\b\w*Test)\b[^\n]{0,80}\bFAILED\b')

def canonical_workflow_script(value):
    if not isinstance(value, str) or not value:
        return False
    candidate = value if os.path.isabs(value) else os.path.join(repo, value)
    expected = os.path.join(repo, ".claude", "workflows", "multi-lens-audit.js")
    return os.path.realpath(candidate) == os.path.realpath(expected)

def workflow_producer(use):
    if not use or use["name"] != "Workflow":
        return False
    inp = use["input"]
    if "name" in inp and inp.get("name") != "multi-lens-audit":
        return False
    if "script" in inp and not canonical_workflow_script(inp.get("script")):
        return False
    return inp.get("name") == "multi-lens-audit" or canonical_workflow_script(inp.get("script"))

tp = d.get("transcript_path")
if tp and os.path.exists(tp):
    try:
        with open(tp) as fh:
            for rawline in fh:
                rawline = rawline.strip()
                if not rawline:
                    continue
                try:
                    rec = json.loads(rawline)
                except Exception:
                    continue
                content = (rec.get("message") or {}).get("content")
                if not isinstance(content, list):
                    continue
                for blk in content:
                    if not isinstance(blk, dict):
                        continue
                    blk_idx += 1
                    if blk.get("type") == "tool_result":
                        c = blk.get("content")
                        if isinstance(c, str):
                            txt = c
                        elif isinstance(c, list):
                            txt = "\n".join(
                                part.get("text", "")
                                for part in c
                                if isinstance(part, dict) and isinstance(part.get("text"), str)
                            )
                        else:
                            txt = json.dumps(c, ensure_ascii=False)
                        try:
                            proof = json.loads(txt)
                        except Exception:
                            proof = None
                        use = tool_uses.get(blk.get("tool_use_id"))
                        result_id = blk.get("tool_use_id")
                        if isinstance(result_id, str):
                            tool_results[result_id] = {
                                "index": blk_idx,
                                "isError": blk.get("is_error") is True,
                            }
                        if (use and use["name"] == "Bash"
                                and BUGS_CMD_RX.search(str(use["input"].get("command", "")))):
                            bugs_touched.update(BUG_ID_RX.findall(txt))
                        if (use and use["name"] == "Bash"
                                and TEST_RUNNER_RX.search(str(use["input"].get("command", "")))):
                            runner_results.append((blk_idx, use["index"], blk.get("is_error") is True, txt,
                                                   str(use["input"].get("command", "")),
                                                   runner_state(blk.get("is_error") is True, txt)))
                        elif (use and use["name"].endswith("__pm_run")
                                and use["input"].get("kind") == "test"):
                            st = runner_state(blk.get("is_error") is True, txt, pm_run=True)
                            if st:
                                runner_results.append((blk_idx, use["index"], blk.get("is_error") is True, txt,
                                                       str(use["input"].get("command") or "pm_run kind=test"), st))
                        producer_ok = bool(
                            use
                            and (
                                workflow_producer(use)
                                or
                                (use["name"] == "Skill"
                                 and use["input"].get("skill") == "multi-lens-audit")
                            )
                        )
                        if (producer_ok
                                and blk.get("is_error") is not True
                                and isinstance(proof, dict)
                                and proof.get("schemaVersion") == 3
                                and proof.get("auditVerdict") == "CLEAR"
                                and proof.get("terminalRecommendation") == "AUDIT_CLEAR_NEEDS_EXTERNAL_GATES"
                                and proof.get("verificationVerdict") == "ASSERTED_ONLY"
                                and isinstance(proof.get("runId"), str)
                                and len(proof["runId"]) > 0
                                and isinstance(proof.get("runNonce"), str)
                                and len(proof["runNonce"]) > 0
                                and isinstance(proof.get("fixedKeys"), list)
                                and len(proof["fixedKeys"]) > 0
                                and all(isinstance(key, str) and key for key in proof["fixedKeys"])
                                and re.fullmatch(r"sha256:[0-9a-f]{64}", str(proof.get("scopeFingerprint", "")))
                                and re.fullmatch(r"sha256:[0-9a-f]{64}", str(proof.get("currentId", "")))
                                and re.fullmatch(r"sha256:[0-9a-f]{64}", str(proof.get("contentHash", "")))):
                            structured_fix_proofs.append({
                                "index": blk_idx,
                                "useIndex": use["index"],
                                "toolUseId": result_id,
                                "fixedKeys": proof["fixedKeys"],
                                "scopeFingerprint": proof["scopeFingerprint"],
                                "currentId": proof["currentId"],
                                "contentHash": proof["contentHash"],
                            })
                        for m in RED_XML.finditer(txt):
                            red_idx[m.group(1)] = blk_idx
                        for m in RED_XML2.finditer(txt):
                            red_idx[m.group(2)] = blk_idx
                        for m in RED_GRADLE.finditer(txt):
                            red_idx[m.group(1)] = blk_idx
                        continue
                    if blk.get("type") != "tool_use":
                        continue
                    nm = blk.get("name", "")
                    binp = blk.get("input") or {}
                    use_id = blk.get("id")
                    if isinstance(use_id, str) and isinstance(binp, dict):
                        tool_uses[use_id] = {"name": nm, "input": binp, "index": blk_idx}
                    elif not isinstance(use_id, str):
                        # With no correlation id there is no later result that
                        # can prove failure. Treat the tool as successful/unknown
                        # so a prior proof cannot authorize a later outcome.
                        no_id_tool_indices.append(blk_idx)
                    if nm not in ("Edit", "Write", "NotebookEdit"):
                        continue
                    fp = binp.get("file_path") or ""
                    if isinstance(fp, str) and fp:
                        edit_log.append((blk_idx, fp))
                    if isinstance(fp, str) and fp.endswith(SRC_EXT):
                        last_src_edit_idx = blk_idx
                    if isinstance(fp, str) and (SCRIPT_TEST_RX.search(fp) or SCRIPT_TEST_DIR_RX.search(fp)) \
                            and not fp.endswith((".kt", ".java")):
                        # Same mutate/restore rule as the JVM branch below: an Edit that is the
                        # exact inverse of the last un-undone edit rolls the marker back.
                        o_s, n_s = binp.get("old_string"), binp.get("new_string")
                        stk = script_pending.get(fp) or []
                        if stk and isinstance(o_s, str) and isinstance(n_s, str) and stk[-1] == (n_s, o_s):
                            stk.pop()
                            script_test_idx[fp] = script_idx_before[fp].pop()
                        else:
                            script_pending.setdefault(fp, []).append((o_s, n_s))
                            script_idx_before.setdefault(fp, []).append(script_test_idx.get(fp, -1))
                            script_test_idx[fp] = blk_idx
                    # Unity C#: the NUnit XML is judged against the last .cs edit, as TEST-*.xml
                    # is against .kt/.java — else a run from before the fix would still back it.
                    if isinstance(fp, str) and fp.endswith(".cs") and os.path.exists(fp):
                        last_edit_mtime = max(last_edit_mtime, os.path.getmtime(fp))
                    if not (isinstance(fp, str) and fp.endswith((".kt", ".java")) and os.path.exists(fp)):
                        continue
                    mt = os.path.getmtime(fp)
                    last_edit_mtime = max(last_edit_mtime, mt)
                    # Module root of the edited file, so a red suite somewhere else in the
                    # repo cannot veto a truthful claim about the module actually touched.
                    rel = os.path.relpath(fp, repo)
                    if "/src/" in rel:
                        touched_modules.add(rel.split("/src/")[0])
                    if "/src/test/" in fp or "/src/androidTest/" in fp:
                        cls = os.path.basename(fp).rsplit(".", 1)[0]
                        authored_tests[cls] = max(authored_tests.get(cls, 0.0), mt)
                        # A mutate/restore pair must not expire the red it exists to produce.
                        # check 2's RED-check REQUIRES mutating a load-bearing line, running it red,
                        # then putting the line back — so the restore is ALWAYS the last edit, and
                        # counting it moved the expiry marker past the red every time. The better
                        # someone followed the protocol, the surer this gate was to reject them
                        # (measured 2026-08-09: it rejected a fix whose mutant had just gone red
                        # 3 runs out of 4). When an edit is the EXACT inverse of the most recent
                        # un-undone edit to the same file, roll the marker back to where it stood
                        # before the mutation instead of advancing it.
                        #
                        # Deliberately LIFO and exact: a real edit between the mutation and the
                        # restore leaves the stack top unmatched, so the verdict still expires.
                        # `Write` carries no old_string/new_string and so never matches — only an
                        # Edit that literally swaps a previous Edit's two strings qualifies.
                        old_s = binp.get("old_string")
                        new_s = binp.get("new_string")
                        stack = pending_edits.get(fp) or []
                        undoes_last = (
                            bool(stack)
                            and isinstance(old_s, str)
                            and isinstance(new_s, str)
                            and stack[-1] == (new_s, old_s)
                        )
                        if undoes_last:
                            stack.pop()
                            test_edit_idx[cls] = edit_idx_before[fp].pop()
                        else:
                            pending_edits.setdefault(fp, []).append((old_s, new_s))
                            edit_idx_before.setdefault(fp, []).append(test_edit_idx.get(cls, -1))
                            test_edit_idx[cls] = blk_idx
    except Exception as e:
        logline(f"[{ts}] transcript scan fail: {e!r}")

# Anchor for "fresh". With no .kt/.java edited this session last_edit_mtime is 0,
# and then EVERY xml in the tree counts as fresh — including results from months
# ago. Measured 2026-07-27: the repo held 2 red suites from an earlier run, so any
# turn saying "test pass" without a Kotlin edit was blocked, and the message called
# a January file "tươi" — a gate blocking valid work AND naming the wrong cause.
# With no edit to anchor on, judge the LATEST run only, not the whole history.
RUN_WINDOW = 300.0
anchor = last_edit_mtime if last_edit_mtime else (newest - RUN_WINDOW if newest else 0.0)

# Parse only the suites a live question actually depends on.
need = set()
if claimed:
    need |= {p for p, mt in mtimes.items() if mt >= anchor}
if new_run:
    need |= {p for p, mt in mtimes.items() if mt > state.get("last_run", 0.0)}
# Keyed by (path, index): one file can hold several suites under a <testsuites>
# root. Only the VALUES are read below, so the key shape is free to change.
parsed = {(p, i): s for p in need for i, s in enumerate(parse_suites(p))}

fresh_all = [s for p, s in parsed.items() if s["mtime"] >= anchor] if claimed else []

# Scope the arithmetic to the modules edited this session. A repo can hold suites that are
# red for reasons this turn did not cause and cannot fix (measured 2026-07-28: :app's
# Roborazzi suites fail on any machine without the gitignored baselines, while the three
# modules under change were green), and summing across all of them made every truthful,
# per-suite report unstatable — a gate that no honest sentence can satisfy teaches people to
# switch it off. Red OUTSIDE the touched modules is not silently forgiven: it still blocks
# unless the response names the failing suite, so "green" can never be claimed over a hidden
# red. With no .kt/.java edited there is nothing to scope by, so judge everything, exactly as
# before.
def module_of(path):
    rel = os.path.relpath(path, repo)
    return rel.split("/build/")[0] if "/build/" in rel else ""

if claimed and touched_modules:
    fresh = [s for s in fresh_all if module_of(s["path"]) in touched_modules]
    outside_red = [s for s in fresh_all
                   if module_of(s["path"]) not in touched_modules and (s["failures"] or s["errors"])]
else:
    fresh = fresh_all
    outside_red = []

# Naming the suite IS the disclosure — a claim that stays silent about it still blocks.
undisclosed_red = [s for s in outside_red
                   if s["name"].rsplit(".", 1)[-1] not in msg]

# ── 6.4 — same testcase red across two runs with edits in between ───────────
# Whose test run produced this XML? build/ is shared: another agent's red suite lands in the
# same tree and used to be counted as one of OUR failed fixes (OfficeReader, 2026-09-10: four
# accusations over suites this session never ran). A run sits inside the Bash window of the
# session that ran it (.claude/audit-gate/bash_write_ledger.tsv, written by
# hooks/bash_write_ledger.sh: session \t start|end \t <ts> \t <tool_use_id>); the narrowest
# containing window wins. Fail-closed: no ledger, no containing window, or a tie between
# sessions → ours. A background command (start, no end) stays open until now. Audit G5.
def _load_windows():
    path = os.path.join(repo, ".claude", "audit-gate", "bash_write_ledger.tsv")
    wins, opens = [], {}
    try:
        if not os.path.isfile(path):
            return []
        with open(path) as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) != 4:
                    continue
                sid_, kind, stamp, tuid = parts
                try:
                    stamp = float(stamp)
                except ValueError:
                    continue
                if kind == "start":
                    opens[(sid_, tuid)] = stamp
                elif kind == "end":
                    st = opens.pop((sid_, tuid), None)
                    if st is not None:
                        wins.append((st, stamp, sid_))
        now_ = time.time()
        for (sid_, _tuid), st in opens.items():
            wins.append((st, now_, sid_))
    except Exception:
        return []
    return wins

_WINDOWS = _load_windows()
_MY_SID = str(d.get("session_id") or "")

def ran_here(mtime):
    if not _WINDOWS or not _MY_SID:
        return True
    best_w, best_sid = None, None
    for st, en, sid_ in _WINDOWS:
        if st <= mtime <= en:
            w = en - st
            if best_w is None or w < best_w:
                best_w, best_sid = w, sid_
            elif w == best_w and sid_ != best_sid:
                best_sid = None
    return True if best_sid is None else best_sid == _MY_SID

# `red-check` is deliberately NOT a marker: agents write it constantly and this hook prints
# it itself, so quoting the warning back would silence the gate by accident.
MUTATION_DISCLOSED = re.compile(r"\b(?:mutation|mutant)\b|đột biến|deliberate[-_\s]*red", re.I)
# Split only at a sentence end followed by whitespace, and at line breaks: a bare [.;] split
# cuts `com.example.PaymentSuite` and `12.5` and strands the marker in another segment.
SENTENCE_SPLIT = re.compile(r"(?<=[.;!?])\s+|\n+")
ANCHOR = "\x00SUITE\x00"

def deliberate_red(testcase, other_failing_simples):
    """Did the reply explain THIS suite's red as a deliberate mutation? The suite name is
    replaced by a marker-free anchor BEFORE splitting (a dotted name would otherwise never be
    whole inside one segment); the test name's own words are stripped, so a test called
    `mutationGuard` cannot disclose itself; a sentence that also names another failing suite
    cannot pin the marker to this one."""
    cls, _, tname = testcase.partition("#")
    simple = cls.rsplit(".", 1)[-1]
    if not simple:
        return False
    text = (msg or "").replace(cls, ANCHOR).replace(simple, ANCHOR)
    for word in re.findall(r"\w+", tname):
        if MUTATION_DISCLOSED.search(word):
            text = re.sub(r"\b%s\b" % re.escape(word), " ", text, flags=re.I)
    for seg in SENTENCE_SPLIT.split(text):
        if ANCHOR not in seg or any(o in seg for o in other_failing_simples):
            continue
        if MUTATION_DISCLOSED.search(seg):
            return True
    return False

repeat_failures = []
if new_run:
    now_failing = set()
    for p, s in parsed.items():
        if s["mtime"] > state.get("last_run", 0.0) and ran_here(s["mtime"]):
            now_failing.update(s["failing"])
    streak = dict(state.get("streak", {}))
    for t in list(streak):
        if t not in now_failing:
            streak.pop(t, None)          # went green (or not re-run) → reset
    # A DELIBERATE mutation red is not a failed fix (check 2's RED-check produces one:
    # fix → green → mutate → red → restore, often inside one turn, so the green never
    # reaches a Stop sample). What a machine can check is DISCLOSURE, per testcase: the
    # reply names THIS suite and says "mutation"/"mutant"/"đột biến" in the same sentence.
    # Ported from OfficeReader's hook (audit G4, 2026-09-24) — the earlier global switch
    # silenced ANTI-LOOP for every failing test whenever the reply quoted this hook's own
    # "RED-check" warning, disclosed a DIFFERENT suite, or the session edited any test file.
    # A disclosed red is skipped (no increment) but the streak is not reset: a genuine failed
    # fix afterwards still trips the gate.
    failing_simples = {tc.partition("#")[0].rsplit(".", 1)[-1] for tc in now_failing}
    for t in now_failing:
        own = t.partition("#")[0].rsplit(".", 1)[-1]
        if deliberate_red(t, failing_simples - {own}):
            logline(f"[{ts}] Anti-Loop: disclosed mutation red skipped: {t} (streak={streak.get(t, 0)})")
            continue
        streak[t] = streak.get(t, 0) + 1
        if streak[t] >= 2:
            repeat_failures.append((t, streak[t]))

    # Per-suite red/green history. XML files are OVERWRITTEN by the next run, so
    # a green run erases the red that came before it — the only way to know a
    # test was ever red is to remember it here, Stop by Stop.
    cls_hist = dict(state.get("cls", {}))
    for p, s in parsed.items():
        if s["mtime"] <= state.get("last_run", 0.0) or not s["name"]:
            continue
        h = dict(cls_hist.get(s["name"], {}))
        h["red" if (s["failures"] or s["errors"]) else "green"] = s["mtime"]
        cls_hist[s["name"]] = h
    state = {"last_run": newest, "streak": streak, "cls": cls_hist}
    try:
        json.dump(state, open(state_path, "w"))
    except Exception:
        pass

# ── check 2 — does the XML back the claim? ──────────────────────────────────
problems = []
if claimed:
    gradle_repo = any(os.path.exists(os.path.join(repo, f)) for f in
                      ("gradlew", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"))
    runner_ok = [r for r in runner_results
                 if r[1] > last_src_edit_idx and r[5] == "green"]
    if not mtimes and not gradle_repo and runner_ok:
        logline(f"[{ts}] non-Gradle repo: test runner result #{runner_ok[-1][0]} backs the claim")
    elif not mtimes and not gradle_repo:
        problems.append(
            "Không có TEST-*.xml và không có lần chạy test runner (npm/jest/pytest/cargo/go/"
            "swift test…) nào THÀNH CÔNG sau lần sửa code cuối trong phiên này.")
    elif not mtimes:
        problems.append("KHÔNG có TEST-*.xml nào trong repo — test chưa từng chạy.")
    elif not fresh:
        problems.append(
            f"Tất cả {len(mtimes)} XML đều CŨ hơn lần sửa code cuối — run này chưa "
            f"chạy code mới (check 2: XML phải mới hơn edit cuối).")
    else:
        tot   = sum(s["tests"] for s in fresh)
        fail  = sum(s["failures"] for s in fresh)
        err   = sum(s["errors"] for s in fresh)
        skip  = sum(s["skipped"] for s in fresh)
        if tot == 0:
            problems.append("XML có nhưng tests=0 — CHƯA CHẠY, cấm gọi là PASS.")
        if fail or err:
            problems.append(f"failures={fail}, errors={err} trong XML tươi — đây KHÔNG phải pass.")
        if skip and not re.search(r"skip|bỏ qua|@Ignore", msg, re.I):
            problems.append(
                f"skipped={skip} mà response không nêu — skip không phải pass, "
                f"check 2 bắt nêu tường minh.")
    if undisclosed_red:
        names = ", ".join(sorted(s["name"].rsplit(".", 1)[-1] for s in undisclosed_red))
        problems.append(
            f"có suite ĐỎ ngoài module đã sửa mà response không nêu tên: {names}. "
            f"Claim pass ở module khác vẫn hợp lệ, nhưng phải nói ra suite đang đỏ.")

# ── RED-check: a test I wrote this session must have been seen RED once ─────
# What a machine CAN check: whether red was ever observed for that suite in this
# session, and whether that red predates the last edit of the test file (the
# rule's expiry clause). What it CANNOT check: that the red came from mutating
# the right load-bearing part, or that it failed for the mechanism under test.
# So this catches the coarse failure the rule was written for — "green in both
# directions, worth zero" — and nothing finer.
cls_hist = state.get("cls", {})
def hist_for(simple_cls):
    for suite, h in cls_hist.items():
        if suite == simple_cls or suite.endswith("." + simple_cls):
            return h
    return None

def red_in_transcript(simple_cls):
    """Was this suite printed as FAILING after its test file was last edited?

    Second, independent source of red evidence — needed because the Stop-time XML
    snapshot cannot see a RED→GREEN cycle completed inside a single turn.
    Position-based, so it honours the same expiry rule: a red printed BEFORE the
    last edit of the test file does not count.
    """
    edit_at = test_edit_idx.get(simple_cls, -1)
    for suite, idx in red_idx.items():
        if (suite == simple_cls or suite.endswith("." + simple_cls)) and idx > edit_at:
            return True
    return False

redcheck = []
if claimed:
    for cls, edited_at in sorted(authored_tests.items()):
        h = hist_for(cls)
        if not h or not h.get("green"):
            continue                      # never ran green → check 2 above covers it
        if red_in_transcript(cls):
            continue                      # red observed in-turn
        red = h.get("red", 0.0)
        if not red:
            redcheck.append((cls, "chưa từng thấy ĐỎ trong phiên này"))
        elif red < edited_at:
            redcheck.append((cls, "lần đỏ gần nhất có TRƯỚC lần sửa test cuối → verdict hết hiệu lực"))

# RED-check for test files outside the JVM (no TEST-*.xml): a test file written this
# session that later ran GREEN must have been seen RED by a runner after its last edit
# and before that green run. When the runner output names test files (jest, vitest,
# pytest), the red run must name this one; when it names none (go, cargo, swift), any
# failing run counts.
if claimed:
    def failed(r):
        return r[5] == "red"
    for fp, edited_at in sorted(script_test_idx.items()):
        after = [r for r in runner_results if r[1] > edited_at]
        greens = [r for r in after if not failed(r)]
        if not greens:
            continue                      # never ran green after the edit → check 2 covers it
        base = os.path.basename(fp)
        stem = re.sub(r"\.(test|spec)$", "", base.rsplit(".", 1)[0])
        def names_this(r):
            return base in r[3] or base in r[4] or (len(stem) >= 4 and stem in r[4])
        reds = [r for r in after if failed(r)
                and (names_this(r) or not TEST_FILE_IN_OUTPUT.search(r[3]))]
        if not any(red[1] < green[1] for red in reds for green in greens):
            redcheck.append((base, "chưa thấy runner chạy ĐỎ file test này sau lần sửa cuối (trước lần XANH)"))

# ── check 7: an outcome claim needs scoped structured proof ─────────────────
check7 = None
fix_proven = False        # an outcome claim this session backed by real proof
if outcome_claimed:
    def cites_exact_value(text, value):
        # Values are whole fields, not prefixes. A terminal period is allowed
        # only at sentence end; `.extra`, `@extra`, `-extra`, Unicode, etc.
        # cannot inherit authority.
        return bool(re.search(
            rf"(?:^|[\s(\[{{,:;]){re.escape(value)}"
            rf"(?=$|[\s)\]}},;:!?]|\.(?=\s|$))",
            text,
        ))

    def proof_is_final(proof):
        for use_id, use in tool_uses.items():
            if use_id == proof["toolUseId"]:
                continue
            result = tool_results.get(use_id)
            if result and result["isError"] and use["name"] == "Edit":
                continue
            if result is None:
                return False
            if result["index"] > proof["useIndex"]:
                return False
        return not any(index > proof["useIndex"] for index in no_id_tool_indices)

    def cites_bound_key(sentence, key, scope):
        return bool(re.search(
            rf"(?:^|[\s(\[{{,:]){re.escape(key)}\s*;\s*scope\s+{re.escape(scope)}"
            rf"(?=$|[\s)\]}},;:!?]|\.(?=\s|$))",
            sentence,
            re.I,
        ))

    unbound_claims = []
    for claim in outcome_claims:
        bound_proof = None
        for proof in structured_fix_proofs:
            if not proof_is_final(proof):
                continue
            cited_keys = {
                key for key in proof["fixedKeys"]
                if cites_bound_key(claim["sentence"], key, proof["scopeFingerprint"])
            }
            if (cites_exact_value(claim["sentence"], proof["scopeFingerprint"])
                    and cites_exact_value(claim["sentence"], proof["currentId"])
                    and cites_exact_value(claim["sentence"], proof["contentHash"])
                    and len(cited_keys) >= claim["sentenceOccurrences"]):
                bound_proof = proof
                break
        if not bound_proof:
            unbound_claims.append(claim["clause"].strip())
    # Second accepted proof — the paired executable oracle AGENTS.md makes mandatory,
    # observed in this session's own tool results: a test run that FAILED before the
    # last source edit and one that PASSED after it. A green run alone (no red before
    # the fix) or prose in the message does not count.
    def paired_red_green():
        if last_src_edit_idx < 0:
            return False
        # Only a test RUNNER's own result counts as red: `cat` of an old TEST-*.xml
        # prints the same failure markup and must not stand in for a real run.
        red = any(r[1] < last_src_edit_idx and r[5] == "red"
                  for r in runner_results)
        green = any(r[1] > last_src_edit_idx and r[5] == "green"
                    for r in runner_results)
        return red and green

    if unbound_claims and paired_red_green():
        logline(f"[{ts}] check 7: outcome claim backed by a paired RED→GREEN test run")
        fix_proven = True
    elif not unbound_claims:
        fix_proven = True
    elif unbound_claims:
        check7 = ("claim OUTCOME ('đã fix'/'hết bug') nhưng phiên này không có bằng chứng: "
                  "cần một lần chạy test ĐỎ trước lần sửa code cuối và XANH sau đó (paired "
                  "RED→GREEN), hoặc kết quả multi-lens-audit bind đúng fixed key + scope.")

# ── lesson reminder: a PROVEN fix whose trap is not in the failure memory yet ─────
# Once per session: the stop is held one time with the command to record the lesson,
# so the next session's hooks can surface it. A second stop always passes — the model
# may judge the bug not worth a lesson (typo, one-off) and say so.
def lesson_reminder():
    if not fix_proven or os.environ.get("LESSON_REMINDER", "1") == "0":
        return None
    flag = os.path.join(state_dir, f"lesson_reminded_{sid}")
    if os.path.exists(flag):
        return None
    for use in tool_uses.values():
        inp = use.get("input") or {}
        if use["name"] == "Bash" and re.search(r"agent-kit[\"']?\s+learn|instincts\.py[\"']?\s+add|--record-lesson",
                                               str(inp.get("command", ""))):
            return None
        if use["name"] in ("Edit", "Write") and str(inp.get("file_path", "")).endswith(".agents/instincts.md"):
            return None
    try:
        open(flag, "w").close()
    except OSError:
        return None
    return ("📝 BÀI HỌC (nhắc 1 lần mỗi phiên): phiên này đã sửa bug có bằng chứng RED→GREEN nhưng chưa ghi\n"
            "bài học vào .agents/instincts.md. Nếu lỗi có thể tái diễn (bẫy chung, không phải lỗi đánh máy),\n"
            "ghi lại để các phiên sau hook tự nhắc đúng lúc:\n"
            "  agent-kit learn \"<tên bẫy>\" --cause=\"<nguyên nhân gốc>\" --rule=\"<cách phòng ngừa>\"\n"
            "Nếu không đáng ghi, nói rõ một câu vì sao rồi dừng — nhắc này không lặp lại.\n")

# ── bug-link reminder: a PROVEN fix while a bug row this session registered (bug prompt,
#   REPORTED) or touched (`agent-kit bugs add/link`) has no test linked. Once per session,
#   with the exact commands; merged with the lesson reminder into one block, because the
#   re-Stop loop guard allows a single extra block.
def bug_link_reminder():
    if not fix_proven or os.environ.get("BUG_LINK_REMINDER", "1") == "0":
        return None
    flag = os.path.join(state_dir, f"buglink_reminded_{sid}")
    if os.path.exists(flag):
        return None
    try:
        items = json.load(open(os.path.join(repo, ".agents", "regression_status.json"), encoding="utf-8"))["items"]
    except Exception:
        return None
    raw_sid = str(d.get("session_id") or "")
    def missing_test(it):
        if it.get("kind") == "req":   # a REQ needs a test for EVERY criterion
            return any(not c.get("tests") and not c.get("test_refs") for c in it.get("criteria") or [{}])
        return it.get("kind") == "bug" and not it.get("tests") and not it.get("test_refs")
    unlinked = [(bid, it) for bid, it in sorted(items.items())
                if isinstance(it, dict) and missing_test(it) and it.get("state") != "auto_closed"
                and (bid in bugs_touched or (raw_sid and raw_sid in (it.get("sessions") or [])))]
    if not unlinked:
        return None
    try:
        open(flag, "w").close()
    except OSError:
        return None
    out = ["🔗 BUG CHƯA LINK TEST (nhắc 1 lần mỗi phiên): phiên này đã sửa có bằng chứng RED→GREEN, nhưng bug",
           "trong checklist chưa gắn test nào — nó sẽ không được chặn tái phát. Link đúng test ĐỎ→XANH vừa chạy",
           "(id matrix, file hoặc class test; PASS chỉ có sau lần gate chạy thật):"]
    for bid, it in unlinked[:5]:
        out.append(f"  • {bid} — {str(it.get('title', ''))[:90]}")
        if it.get("kind") == "req":
            todo = [str(n) for n, c in enumerate(it.get("criteria") or [], 1) if not c.get("tests") and not c.get("test_refs")]
            out.append(f"      agent-kit req link {bid} <{'|'.join(todo) or 'all'}> <test>   (tiêu chí chưa có test: {', '.join(todo)})")
        else:
            out.append(f"      agent-kit bugs link {bid} <test>")
    out += ["  hoặc ghi bài học + bug cùng lúc sau gate xanh: postfix-gate --run-tests --record-lesson \"<tiêu đề>\"",
            f"  Không phải bug / đã trùng: agent-kit bugs drop {unlinked[0][0]}",
            "  Bug chưa sửa trong phiên này thì nói rõ một câu rồi dừng — nhắc này không lặp lại."]
    return "\n".join(out) + "\n"

# ── auto-link: a proven fix whose evidence is one-to-one links the bug to its test by
#   itself (linked_by=auto, 🤖 in the view): exactly one unlinked bug row of this session,
#   exactly one test file written/edited this session, a runner RED naming that test after
#   it was written and BEFORE the first source edit, a GREEN run after the last source edit.
#   Anything ambiguous → no link (the reminder below asks instead). AUTO_LINK=0 off.
def is_test_path(fp):
    return bool(SCRIPT_TEST_RX.search(fp) or SCRIPT_TEST_DIR_RX.search(fp)
                or "/src/test/" in fp or "/src/androidTest/" in fp or re.search(r"/Tests?/.*\.cs$|Tests?\.cs$", fp))

def auto_link():
    if not fix_proven or os.environ.get("AUTO_LINK", "1") == "0":
        return
    rows = session_bug_rows()
    unlinked = [bid for bid, it in rows.items() if not it.get("tests") and not it.get("test_refs")
                and it.get("state") != "auto_closed"]
    tests = {fp for _, fp in edit_log if is_test_path(fp)}
    src_idx = [i for i, fp in edit_log if fp.endswith(SRC_EXT) and not is_test_path(fp)]
    if len(unlinked) != 1 or len(tests) != 1 or not src_idx:
        return
    test = next(iter(tests))
    stem = os.path.basename(test).rsplit(".", 1)[0]
    written = min(i for i, fp in edit_log if fp == test)
    red = any(written < r[1] < min(src_idx) and r[5] == "red" and (stem in r[3] or stem in r[4])
              for r in runner_results)
    green = any(r[1] > max(src_idx) and r[5] == "green" for r in runner_results)
    if not (red and green):
        return
    rel = os.path.relpath(os.path.realpath(test), os.path.realpath(repo)) if os.path.isabs(test) else test
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(os.environ.get("TE_SELF", "")))), "bin"))
        sys.dont_write_bytecode = True
        import regression_checklist as rc
        from pathlib import Path as _P
        with rc.locked(repo):
            data = rc.load(_P(repo))
            mf = _P(repo) / ".agents" / "regression_matrix.active.json"
            if mf.is_file():
                rc.sync_from_matrix(data, json.loads(mf.read_text(encoding="utf-8")))
            in_matrix, _ = rc.link_bug(data, unlinked[0], rel, project=_P(repo))
            data["items"][unlinked[0]]["linked_by"] = "auto"
            rc.save(_P(repo), data)
        logline(f"[{ts}] auto-link {unlinked[0]} → {rel} ({in_matrix})")
    except Exception as e:  # noqa: BLE001 — never fail the Stop over the convenience link
        logline(f"[{ts}] auto-link failed: {e!r}")

# ── RED-proof of this session's bugs: a proven fix starts scripts/red_proof.py in the
#   background (sandbox: the test must fail without the fix and pass with it); a bug of
#   this session whose test was found VACUOUS (green without the fix) holds the stop once.
def session_bug_rows():
    try:
        items = json.load(open(os.path.join(repo, ".agents", "regression_status.json"), encoding="utf-8"))["items"]
    except Exception:
        return {}
    raw_sid = str(d.get("session_id") or "")
    return {bid: it for bid, it in items.items() if isinstance(it, dict) and it.get("kind") in ("bug", "req")
            and (bid in bugs_touched or (raw_sid and raw_sid in (it.get("sessions") or [])))}

def red_proof_actions():
    rows = session_bug_rows()
    if fix_proven and os.environ.get("RED_PROOF", "1") != "0":
        todo = [bid for bid, it in rows.items() if it.get("tests") and it.get("fixed") is not False
                and (it.get("red_proof") or {}).get("status") in (None, "PENDING", "OUTDATED")]
        script = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(os.environ.get("TE_SELF", "")))),
                              "scripts", "red_proof.py")
        if todo and os.path.isfile(script):
            import subprocess
            subprocess.Popen([sys.executable, script, repo, "--bug", ",".join(sorted(todo)), "--wait"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            logline(f"[{ts}] red-proof started in background: {sorted(todo)}")
    vacuous = [(bid, it) for bid, it in sorted(rows.items()) if (it.get("red_proof") or {}).get("status") == "VACUOUS"]
    if not vacuous:
        return None
    out = ["🚫 TEST VÔ HIỆU: test của bug dưới đây vẫn XANH khi bỏ bản sửa trong sandbox —",
           "nó không bảo vệ bug khỏi tái phát. Sửa test cho nó ĐỎ trên code lỗi (assert đúng hành vi bị hỏng), rồi:"]
    for bid, it in vacuous[:5]:
        out.append(f"  • {bid} — {str(it.get('title', ''))[:90]}  (log: {(it.get('red_proof') or {}).get('log', '-')})")
    out.append(f"  python3 <devkit>/scripts/red_proof.py . --bug {vacuous[0][0]} --wait   # chứng minh lại")
    return "\n".join(out) + "\n"

if not problems and not repeat_failures and not redcheck and not check7:
    logline(f"[{ts}] claim={claimed} outcome={outcome_claimed} xml={len(mtimes)} "
            f"parsed={len(parsed)} fresh={len(fresh)} — pass")
    auto_link()
    notes = [n for n in (lesson_reminder(), bug_link_reminder(), red_proof_actions()) if n]
    if notes:
        logline(f"[{ts}] reminder (once per session): {len(notes)}")
        sys.stderr.write("\n".join(notes))
        sys.exit(2)
    sys.exit(0)

out = []
if problems:
    out += ["⛔ TEST-EVIDENCE (CLAUDE.md check 2): response claim test pass nhưng XML không chống lưng.", ""]
    for p in problems:
        out.append(f"  • {p}")
    if fresh:
        out += ["", "  XML tươi đã đọc:"]
        for s in sorted(fresh, key=lambda x: -x["mtime"])[:6]:
            out.append(f"    {os.path.relpath(s['path'], repo)} — tests={s['tests']} "
                       f"failures={s['failures']} errors={s['errors']} skipped={s['skipped']}")
    out += ["", "  → Chạy lại test cho module đã sửa rồi đọc số từ TEST-*.xml, hoặc sửa câu",
            "    thành 'chưa chạy test' / ghi BLOCKED kèm residual.",
            "  Nhắc: gate này KHÔNG kiểm RED-check. Xanh mà chưa có đỏ đi kèm vẫn là BLOCKED."]

if repeat_failures:
    if out:
        out.append("")
    out += ["⛔ ANTI-LOOP (CLAUDE.md 6.4): cùng testcase đỏ qua nhiều lần fix.", ""]
    for t, n in repeat_failures[:8]:
        out.append(f"  • {t} — đỏ ở {n} lần chạy liên tiếp")
    out += ["",
            "  2 lần fix thất bại cùng root cause → bỏ và đổi đường tấn công/hypothesis.",
            "  Đây KHÔNG phải lý do kết thúc task; tiếp tục mọi phần độc lập theo B9.",
            "  Nếu mỗi fix lại đẻ bug mới: nêu nghi vấn KIẾN TRÚC sai, không phải hypothesis sai",
            "  (6.4 + rulebook/44), rồi đặt lại câu hỏi thiết kế."]

if redcheck:
    if out:
        out.append("")
    out += ["⛔ RED-CHECK (CLAUDE.md check 2): test viết trong phiên này chưa từng đỏ.", ""]
    for cls, why in redcheck[:6]:
        out.append(f"  • {cls} — {why}")
    out += ["",
            "  Test xanh cả hai chiều phân biệt được 0 thứ. Trước khi gọi là PASS: giết RIÊNG",
            "  từng phần load-bearing của fix, chạy lại, xem test có đỏ ĐÚNG failure mechanism",
            "  đang test không. Mutant sống sót = phần đó chưa có coverage.",
            "  Chưa làm được → ghi BLOCKED kèm residual, đừng gọi là PASS."]

if check7:
    if out:
        out.append("")
    out += ["⛔ CHECK 7 (fix có tác dụng thật): " + check7, "",
            "  Test xanh KHÔNG phải bằng chứng bug đã fix — unit test cho pure function tách rời",
            "  vẫn xanh khi signal thật không bao giờ tới được nó.",
            "  Cần paired RED→GREEN ngay trong phiên: chạy test tái hiện bug thấy ĐỎ → sửa code →",
            "  chạy lại thấy XANH (hoặc multi-lens-audit proof). Device/runtime: adb-safe-exec.sh.",
            "  Thiếu proof → nói đúng phạm vi và ghi BLOCKED, không gọi outcome là đã fix."]

logline(f"[{ts}] BLOCK — problems={len(problems)} repeat={[t for t,_ in repeat_failures]} "
        f"redcheck={[c for c,_ in redcheck]} check7={bool(check7)}")
sys.stderr.write("\n".join(out) + "\n")
sys.exit(2)
PY
rc=$?
[ "${rc}" -eq 2 ] && exit 2
exit 0
