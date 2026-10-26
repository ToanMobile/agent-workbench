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
# XML of ANOTHER project counts too when this session's own Bash commands named it (its
# build/test-results path, the XML, or the project dir it ran the tests in) and one of this
# session's own Bash windows (bash_write_ledger.tsv) wrote it. A sentence that only attributes
# the result to another hook/session/person/user, or says the tests were not run / did not pass,
# is not a claim.
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
# source edit, whose output shows no failure, backs the claim (QA K-10). A script under tests/
# named or run through a $VAR (`for t in …; do bash "$K/tests/gates/$t.sh"`, `$py tests/…/test-x.py`)
# counts like a literal path; the DevKit gate `post-fix-gate.py --run-tests|--full` counts when ITS
# verdict is PASS with N/N suites, N ≥ 1 (a green like any runner: a test file written this session still
# needs a RED seen before it; for check 7 it is the GREEN half of the pair, the RED half is still a real runner run).
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

INPUT="$(cat)"

# The project (2026-10-09): CLAUDE_PROJECT_DIR, else the git tree of the payload cwd (of the process cwd when the payload has
# none). Outside a git tree there is no project and nothing is written (tests/gates/test_hook_log_dir.sh): a run at /
# created /.claude/audit-gate/.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "${REPO_ROOT}" ]; then
  RX_CWD='"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'   # a JSON-escaped cwd too (é sent escaped, \", \\): tests/gates/test_hook_payload_cwd_escaped.sh
  [[ ${INPUT} =~ ${RX_CWD} ]] && _PCWD="${BASH_REMATCH[1]}" || _PCWD="."
  case "${_PCWD}" in *\\*) _PCWD="$(python3 -I -c 'import json,sys; sys.stdout.buffer.write(json.loads("\"%s\"" % sys.argv[1]).encode())' "${_PCWD}" 2>/dev/null)" || _PCWD="." ;; esac
  REPO_ROOT="$(git -C "${_PCWD}" rev-parse --show-toplevel 2>/dev/null)"
fi
BASE_ROOT="${REPO_ROOT}"   # bash_write_ledger.sh writes bash_write_ledger.tsv under it, whatever tree is judged below
# W1 v6 (hooks/session_worktree.py): a session that ENTERED a worktree (EnterWorktree: CLAUDE_PROJECT_DIR still names main) or a subagent
# the harness started in one is judged in that worktree, not in a clean main. Python only when the payload or a session record can need it.
_SW_SID='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9][A-Za-z0-9._-]*)"'
_SW_CWD='"cwd"[[:space:]]*:[[:space:]]*"[^"]*/\.claude/worktrees/'   # the cwd FIELD, not any text of the payload (a file read, a subagent)
if [ -n "${REPO_ROOT}" ] && { [[ ${INPUT} =~ ${_SW_CWD} ]] \
     || { [[ ${INPUT} =~ ${_SW_SID} ]] && [ -f "${REPO_ROOT}/.claude/audit-gate/session_worktree/${BASH_REMATCH[1]}" ]; }; }; then
  if _SW_ROOT="$(python3 -I -c 'import json,os,sys
_d = os.path.dirname(os.path.realpath(sys.argv[1]))
if os.path.isabs(_d): sys.path.append(_d)
import session_worktree as s; print(s.project(json.loads(sys.stdin.read() or "{}")) or "")' "$0" <<<"${INPUT}" 2>/dev/null)"; then
    [ -n "${_SW_ROOT}" ] && REPO_ROOT="${_SW_ROOT}"
  else   # never silent: this gate then judges what CLAUDE_PROJECT_DIR names, possibly a clean main (OCR 14/10)
    echo "⚠ DevKit $(basename "$0"): the session's worktree could not be resolved (hooks/session_worktree.py next to the real hook) - judging ${REPO_ROOT}" >&2
  fi
fi
[ -n "${REPO_ROOT}" ] || exit 0
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"
mkdir -p "${LOG_DIR}"
for _fifo in "${LOG_DIR}"/* "${LOG_DIR}"/.[!.]*; do [ ! -p "${_fifo}" ] || rm -f -- "${_fifo}"; done   # a FIFO here (never one of ours) would hang the next open of a log or lock: drop it
[ -e "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true

if [ "${TEST_EVIDENCE_GATE:-1}" = "0" ]; then
  echo "[$(date +%Y-%m-%dT%H:%M:%S)] TEST_EVIDENCE_GATE=0 — gate bypassed" >> "${LOG_DIR}/test_evidence_gate.log" 2>/dev/null
  exit 0
fi

# QA K-4: without python3 this gate cannot run — say so instead of passing silently.
if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ test_evidence_gate: python3 không có — gate này KHÔNG chạy, kết quả không được kiểm." >&2
  exit 0
fi
# The payload goes to python on fd 3, not in an env var (2026-10-09): a reply past the OS limit for one variable could not
# start python and the gate passed it unchecked (tests/gates/test_hook_large_payload.sh).
TE_LOG="${LOG_DIR}/test_evidence_gate.log" TE_DIR="${LOG_DIR}" \
TE_TS="$(date +%Y-%m-%dT%H:%M:%S)" TE_REPO="${REPO_ROOT}" TE_BASE_REPO="${BASE_ROOT}" TE_SELF="$0" \
python3 -I <<'PY' 3<<<"${INPUT}"
import os, sys, json, re, glob, time, shlex, tempfile
import xml.etree.ElementTree as ET

try:
    with os.fdopen(3, encoding="utf-8", errors="replace") as _fh:
        raw = _fh.read()
except OSError:
    raw = ""
log    = os.environ.get("TE_LOG", "/dev/null")
state_dir = os.environ.get("TE_DIR", "/tmp")
ts     = os.environ.get("TE_TS", "?")
repo   = os.environ.get("TE_REPO", ".")
ledger_root = os.environ.get("TE_BASE_REPO") or repo   # where the hooks write bash_write_ledger.tsv: main when `repo` is a session's worktree

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
    r"|(?:toàn\s+bộ|tất\s+cả)\s+(?:kiểm\s+thử|tests?)[^.\n]{0,16}(?:đều\s+)?đạt"
    # 2026-09-28: plainer wording slipped through ("Tests OK (12)", "The suite is green: 12/12
    # passed", "everything passes", "chạy lại thấy ổn").
    r"|\btests?\s+(?:are\s+|all\s+)?ok(?:ay)?\b|\bsuites?\s+(?:is\s+|are\s+)?(?:green|xanh)\b"
    r"|\d+\s*/\s*\d+\s+(?:pass(?:ed|es|ing)?|green|xanh|đạt)\b|\beverything\s+(?:now\s+)?pass(?:es|ed)?\b"
    r"|chạy\s+lại[,:]?\s+(?:thì\s+|đều\s+)?(?:thấy\s+)?(?:ổn|ok|tốt)\b)", re.I)
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
# A reply that QUOTES evidence someone else produced, or says the tests were NOT run / did NOT
# pass, makes no pass claim (2026-09-25: "the evidence logs written by another hook at 08:41 say
# status PASS" and "chưa chạy test" were blocked as unbacked claims). Both exemptions are
# positional and local, so they cannot reach across a contrast to an independent claim:
#   • ATTRIBUTED — a different actor names the source in the same stretch of text before the
#     match: another/other/a different hook|session|person|user, hook|phiên|người khác,
#     written/produced/reported by someone, the user said. Not an agent, not an earlier run.
#     A contrast or sequence word (nhưng, but, and, và, còn, mà, giờ, now, …) or `;`/dash
#     between them ends it ("Hook khác báo fail, nhưng giờ 13/13 test pass" is still a claim). Plain "the XML shows 13/13" is NOT attribution:
#     that claim is checked against the XML on disk.
#   • NEGATED — the negator sits right before the result word ("tests did not pass", "test chưa
#     xanh", "not fixed"), or the same clause says the tests were not run / the result is not
#     known ("chưa chạy test", "chưa biết test có pass"). A clause break (comma, nhưng, so, nên, …)
#     ends it, so "Không chạy smoke, nhưng unit tests passed" stays a claim.
# "vì / bởi vì / since / because" open a reason clause (2026-10-25): "I did not run the old suite because 12/12 tests pass" is a claim.
_CONTRAST = (r"\b(?:nhưng|but|and|và|còn|mà|however|tuy\s+nhiên|song|so|nên|vì\s+vậy|therefore|while"
             r"|whereas|rồi|then|giờ|bây\s+giờ|now|bởi\s+vì|vì|since|because)\b")
# A comma or ": " also ends the attributed part: "User reported X, fixed it" — the report is
# theirs, the claim after the comma is the agent's own ("08:41" has no space, it stays).
# Not a ":" right after the reporting verb, which opens the quote ("The user said: …", "Phiên
# khác báo: …"), unless the agent speaks after it ("reports: I fixed it"); nor ", at 08:41, that"
# (review 2026-09-25). A bare comma after the verb still ends it: "User reported, fixed it".
ATTR_BREAK = re.compile(r"[,;—–]|:\s|\s-\s|\n|" + _CONTRAST, re.I)
REPORT_PUNCT = re.compile(
    r"\b(said|says|say|reported|reports|wrote|writes|báo|nói|kể|ghi)"
    r"(?:\s*:(?!\s*(?:I|I'?ve|I'?m|I'?ll|tôi|mình|em|we)\b)\s*|\s*,\s*(?:at|lúc)\s+[\d:.hH]+\s*,\s*(?=(?:that|rằng)\b))",
    re.I)
CLAUSE_BREAK = re.compile(r"[,;:—–()]|\s-\s|\n|" + _CONTRAST, re.I)
# Only a DIFFERENT actor counts: another hook/session/person/user. The agent's own earlier run,
# job or session ("Previous run: 13/13 tests pass", "Lần chạy trước …", "Previous session fixed
# bug A") is its own claim, and an agent's word is not evidence either: a leader relaying a
# subagent's unverified "13/13 tests pass" ("The other agent ran the suite: …", "Agent khác báo
# đã fix") is checked like any claim (2026-09-25 review P1).
ATTRIBUTION = re.compile(
    r"\b(?:another|other|a\s+different)\s+(?:[\w-]+\s+)?(?:hooks?|sessions?|person|people|users?)\b"
    r"|\b(?:hook|phiên|người)\s+khác\b"
    r"|\b(?:written|produced|reported|recorded|logged|generated|claimed|posted)\s+by\s+someone\b"
    r"|\b(?:the\s+)?user\s+(?:said|says|reported|reports|claims?)\b|\b(?:người\s+dùng|user)\s+(?:nói|báo|kể)\b",
    re.I)
_NEG = r"(?:\b(?:chưa|không|chẳng|never|not|no|none\s+of\s+the|zero|did\s+not|does\s+not|do\s+not|failed\s+to)|n't)"
# "chưa phải đã fix" (2026-10-14) is the negation too. Not "không phải" / "chẳng phải": "Không phải đã fix lỗi X rồi sao?" is a rhetorical
# question that asserts, and "không phải A mà B" asserts B (OCR + principal-code-reviewer 14/10).
NEG_BEFORE_RESULT = re.compile(r"(?:\bchưa\s+phải(?:\s+là)?|" + _NEG + r")\s+(?:(?:có|được|hề|all|yet|been|tất\s+cả|the)\s+)*$", re.I)
NEG_IN_MATCH = re.compile(_NEG + r"\s+(?:(?:có|được|hề|yet|been)\s+)*(?:pass|xanh|green|thành\s+công|đạt)", re.I)
NEG_RUN = re.compile(
    r"(?:\b(?:chưa|không|chẳng|never|not|did\s+not|have\s+not|has\s+not|cannot|không\s+thể|chưa\s+thể)|n't)"
    r"\s+(?:(?:được|hề|yet|been|thể)\s+)?"
    r"(?:chạy|run|ran|running|execute[sd]?|biết|know|khẳng\s+định|claim|say|nói|xác\s+nhận|confirm|chắc)\b", re.I)
# A negated ASSERTION verb right before the result disowns it ("chưa chốt đã fix", "chưa có bằng chứng đủ để nói đã fix", "I'm not
# claiming a test pass"; 2026-10-25 audit: 46 check-7 blocks; cases in tests/gates/test_evidence_false_blocks.sh, section E). Anchored at
# the END of the clause before the match, with only a closed filler between the verb and the match, so "gọi" / "call" exempt only as
# "gọi chúng là …" / "call it …": "Không ai gọi API này nữa vì đã fix", "I'm not claiming victory yet since 12/12 tests pass" stay claims.
# The gap between the negator and the verb is a closed list too (2026-10-25 review of af339645): any word there let an emphatic or
# double-negative ASSERTION through ("Không cần phải nói là đã fix", "It's not an overstatement to say 12/12 tests pass").
NEG_ASSERT = re.compile(
    r"(?:\b(?:không|chưa|chẳng|not|never)\b|n't)\s+"
    r"(?:(?:có|đủ|để|bằng\s+chứng|cơ\s+sở|thể|dám|được|hề|yet|going\s+to|able\s+to|ready\s+to)\s+){0,6}?"
    r"(?:gọi|nói|tuyên\s+bố|khẳng\s+định|chốt|kết\s+luận|claim(?:s|ed|ing)?|call(?:s|ed|ing)?|say(?:s|ing)?)"
    r"(?:\s+(?:chúng|nó|họ|là|rằng|it|them|this|that|a|an|the|[^\s,;:]+\s+(?:hay|or)))*\s*$", re.I)

def _tail(prefix, breaker):
    cut = 0
    for m in breaker.finditer(prefix):
        cut = m.end()
    return prefix[cut:]

def attributed_or_negated(prefix, matched_text):
    if ATTRIBUTION.search(_tail(REPORT_PUNCT.sub(r"\1 ", prefix), ATTR_BREAK)):
        return True
    if NEG_BEFORE_RESULT.search(prefix) or NEG_IN_MATCH.search(matched_text):
        return True
    clause = _tail(prefix, CLAUSE_BREAK)
    return bool(NEG_RUN.search(clause) or NEG_ASSERT.search(clause))

# "test RED→GREEN" in a plan names the TDD cycle the rules demand, it reports no run (2026-09-27:
# an audit reply that only planned one was blocked twice). Exempt only when the sentence says it
# is a plan / not done yet, says nothing is done, and no result word or N/N count follows the
# compound: "Test RED→GREEN ✅", "Đã chạy test RED→GREEN", "Test RED→GREEN, 12/12 pass" are claims.
RED_GREEN_NAME = re.compile(r"\b(?:red|đỏ)\s*(?:→|->|=>)\s*(?:green|xanh)\b", re.I)   # đỏ: the Vietnamese name, 2026-10-12
CYCLE_PLAN = re.compile(r"\b(?:sẽ|kế\s+hoạch|cần|nên|phải|chưa|will|plan(?:ned)?|need|must|should"
                        r"|not\s+yet|before)\b|trước\s+khi", re.I)
CYCLE_DONE = re.compile(r"\b(?:đã|rồi|xong|done|ran|passed)\b|✅|✔|✓", re.I)
# Three more plan signals (2026-10-25 audit, real blocked plans). Each must GOVERN the cycle name, a word elsewhere in the sentence does
# not: "Guard chặn push có test ĐỎ→XANH", "Sửa theo đề xuất của reviewer, có test ĐỎ→XANH" stay claims.
#   • a prohibition of RUNNING it, right before the name: "luật sandbox chặn luôn việc chạy test ĐỎ→XANH";
#   • the agent's own proposal verb before the name: "Tôi đề xuất …, mỗi việc có test ĐỎ→XANH", "I suggest …", a leading "Đề xuất:";
#   • a sequencing ", rồi <verb>" after the name: "kèm test RED→GREEN, rồi đồng bộ sang các repo". That "rồi" is "then", not
#     "already", so it is no done word; a particle after it ("rồi nhé", "rồi đó") and every other "rồi" still are.
# Tightened by the review of af339645 (2026-10-25; must-block cases in tests/gates/test_evidence_false_blocks.sh, section A):
#   • the prohibition does not count once lifted: "Sau khi gỡ luật chặn chạy test ĐỎ→XANH thì mọi ca đều qua" reports a run;
#   • the proposal opens the sentence ("Sửa theo đúng những gì tôi đề xuất, có test ĐỎ→XANH" reports a done fix), and what follows a
#     ":" / ";" / dash or a reason word after it may be its justification ("Tôi đề xuất merge luôn: mỗi sửa đều có test ĐỎ→XANH"), so
#     it needs a plan marker then;
#   • Vietnamese has no tense: a bare ", rồi <verb>" reads the same in a done report ("Mỗi sửa có test ĐỎ→XANH, rồi merge vào main"),
#     so it is a plan only next to an explicit plan marker (leader's decision), and only then is its "rồi" no done word.
CYCLE_PROHIBIT_RUN = re.compile(r"\b(?:chặn|ngăn|cấm|block(?:s|ed|ing)?|prevent(?:s|ed|ing)?|forbid(?:s|den)?)\s+"
                                r"(?:(?:luôn|cả|việc|the|from)\s+)*(?:chạy|run(?:s|ning)?)\s*$", re.I)
CYCLE_PROHIBIT_LIFTED = re.compile(r"\b(?:gỡ|bỏ|tắt|xoá|xóa|hủy|huỷ|remov(?:e[sd]?|ing)|lift(?:s|ed|ing)?|disabl(?:e[sd]?|ing)"
                                   r"|drop(?:s|ped|ping)?)\s+(?:[^\s,;:]+\s+){0,3}$", re.I)
CYCLE_PROPOSE = re.compile(r"^[\s>*•+#-]*(?:(?:tôi|mình|em|chúng\s+(?:tôi|ta|mình)|I|we)(?:'d|\s+(?:would|xin|muốn))?\s+"
                           r"(?:đề\s+xuất|propose|suggest|recommend)\b|(?:đề\s+xuất|proposal|suggestion|recommendation)\s*:)", re.I)
CYCLE_PROPOSE_BREAK = re.compile(r"[:;—–]|\s-\s|\b(?:vì|bởi\s+vì|since|because|nhưng|but|tuy\s+nhiên|however)\b", re.I)
CYCLE_THEN = re.compile(r",\s*rồi(?=\s+(?!(?:nhé|nha|nhá|nhỉ|đó|đấy|đây|ạ|à|á|mà|ha|hen|nè|vậy|thôi|luôn|hết|chứ"
                        r"|anh|chị|em|sếp|bạn|ông|bà|cô|chú)\b)\w)", re.I)
# "định" only as "dự định" / "<tôi> định": alone it is also "ổn định", "xác định", "khẳng định".
CYCLE_PLAN_MARK = re.compile(r"\b(?:sẽ|cần|nên|dự\s+định|(?:tôi|mình|em|ta)\s+định|kế\s+hoạch|bước\s+tiếp|tiếp\s+theo"
                             r"|will|should|plan(?:s|ned)?|next)\b", re.I)

def cycle_name_only(sentence, match):
    if not RED_GREEN_NAME.search(match.group(0)):
        return False
    before, after = sentence[:match.start()], sentence[match.end():]
    marked = CYCLE_PLAN_MARK.search(sentence)
    prohibit, proposal = CYCLE_PROHIBIT_RUN.search(before), CYCLE_PROPOSE.search(before)
    then = bool(marked and CYCLE_THEN.search(after))
    planned = (CYCLE_PLAN.search(sentence)
               or (prohibit and not CYCLE_PROHIBIT_LIFTED.search(before, 0, prohibit.start()))
               or (proposal and (marked or not CYCLE_PROPOSE_BREAK.search(before, proposal.end())))
               or then)
    if not planned or CYCLE_DONE.search(sentence[:match.end()] + (CYCLE_THEN.sub(" ", after) if then else after)):
        return False
    rest = RED_GREEN_NAME.sub(" ", sentence[match.start():])
    return not re.search(r"pass|xanh|green|thành\s+công|đạt|\d+\s*/\s*\d+", rest, re.I)

# A sentence that MENTIONS the trigger words quotes them after a word that says so (chữ "test" đứng gần "xanh", cụm
# "test ĐỎ→XANH", mẫu `test…xanh`; 2026-10-12: four blocks in one session of replies that only talked about this gate).
# Both ends of the match must sit inside quotes or backticks, so a quoted RESULT with no such word (Kết quả: "12/12 test
# pass") or a result outside the quotes (Chữ "test" thì 12/12 test pass) is still a claim.
MENTION_WORD = re.compile(r"\b(?:chữ|từ|cụm|mẫu|chuỗi|câu|words?|phrases?|patterns?|regex|terms?)\b", re.I)
# The same rule for an OUTCOME phrase (`có chữ "đã xử lý"`, 2026-10-14), narrower on purpose: the naming word stands RIGHT BEFORE the
# opening quote, after a space (`\s+$`: an odd quote cannot shift the pairs), and it is a word that ONLY names a quote: not `từ` ("from"),
# `câu`, `claim` (the agent's OWN assertion), nor `mẫu` / `regex` / `pattern` / `term` / `chuỗi` (nouns of the sentence: `Lỗi regex "đã fix"`),
# and not the connective of "in other words". A naming word further back in the clause is a noun too ("Theo mẫu báo cáo lỗi crash "…"").
OUTCOME_MENTION_WORD = re.compile(r"\b(?:chữ|cụm(?:\s+từ)?|words?|phrases?)\s+$", re.I)
CONNECTIVE_WORDS = re.compile(r"\bother\s+words?\s+$", re.I)   # "In other words "fixed"": the connective, not a naming word
QUOTED_SPAN = re.compile(r"\"[^\"\n]*\"|“[^”\n]*”|`[^`\n]*`")

import bisect
_QUOTES = {}     # sentence -> (end of its first mention word or None, quoted span starts, spans): once per sentence, not per match

def outcome_mention(sentence, match):
    """An outcome phrase that is the SUBJECT of its quote: the whole match inside ONE pair of quotes or backticks, the quote holding
    nothing but the phrase (a quote that goes on with the object of the fix is a claim; an odd quote cannot shift the pairs under a
    claim), and the naming word right before that opening quote."""
    for x in QUOTED_SPAN.finditer(sentence):
        if (match.start() == x.start() + 1 and match.end() < x.end()
                and re.fullmatch(r"[\s.,;:!?…]*", sentence[match.end():x.end() - 1])
                and not re.match(r"(?:bug|lỗi|issue|crash|error)\b", match.group(0), re.I)):   # these branches of OUTCOME carry the object
            return bool(OUTCOME_MENTION_WORD.search(sentence[:x.start()]) and not CONNECTIVE_WORDS.search(sentence[:x.start()]))
    return False

def quoted_mention(sentence, match):
    q = _QUOTES.get(sentence)
    if q is None:
        mw = MENTION_WORD.search(sentence)
        spans = [(x.start(), x.end()) for x in QUOTED_SPAN.finditer(sentence)]
        q = _QUOTES[sentence] = (mw.end() if mw else None, [a for a, _ in spans], spans)
    first_end, starts, spans = q
    if first_end is None or first_end > match.start():
        return False
    def inside(i):
        k = bisect.bisect_right(starts, i) - 1
        return k >= 0 and spans[k][0] < i < spans[k][1] - 1
    return inside(match.start()) and inside(match.end() - 1)

# Each match re-reads its sentence (the prefix regexes, the cycle-name and quote checks), so N matches in one long clause cost N × its
# length: 1 340 negated phrases in one 40 KB sentence took 8-13 s of CPU (2026-10-25), and a Stop hook past its 30 s cap lets the Stop
# through. A reply gets _EXEMPT_BUDGET characters of that re-reading (~0.1 s); past it every further match is an ASSERTION (fail-closed).
# ponytail: a reply that only holds exempt phrases past the budget (hundreds in one clause) now blocks; make the per-match checks local
# to a window if a real reply ever does.
_EXEMPT_BUDGET = 500_000
_exempt_spent = 0

def is_nonassertive(sentence, match, kind):
    """Only explicit grammar may exempt a matched result/outcome phrase.

    Default is ASSERTION. Generic `chưa/không/thì` elsewhere in the sentence
    cannot erase an independent claim.
    """
    global _exempt_spent
    _exempt_spent += len(sentence)
    if _exempt_spent > _EXEMPT_BUDGET:
        if _exempt_spent - len(sentence) <= _EXEMPT_BUDGET:
            logline(f"[{ts}] exemption budget of {_EXEMPT_BUDGET} chars spent: every further match is a claim")
        return False
    prefix = re.sub(r"[`\"“”]", "", sentence[:match.start()])
    matched_text = match.group(0)
    if GOVERNING_PREFIX.search(prefix):
        return True
    if attributed_or_negated(prefix, matched_text):
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
    if (quoted_mention if kind == "test" else outcome_mention)(sentence, match):   # `có chữ "đã xử lý"` (outcome: 2026-10-14)
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
            or cycle_name_only(sentence, match)
        )
    return bool(OUTCOME_GUIDANCE_PREFIX.search(prefix))

claimed = False
def _claim_matches(sent):
    """CLAIM matches; after one that crosses a clause break the scan resumes at the last break inside it, so an exempted
    match cannot hide a claim of its own clause (2026-10-12 fail-open: "Không có test nào fail, 12/12 test pass." - the
    negator exempted the match running from the first test to the last pass). A match with no break inside resumes after
    it, as finditer did (a rescan from every character made a long reply 3 times slower)."""
    pos = 0
    while True:
        m = CLAIM.search(sent, pos)
        if not m:
            return
        yield m
        cut = None
        for b in CLAUSE_BREAK.finditer(sent, m.start(), m.end()):
            cut = b.end()
        pos = cut if cut is not None and m.start() < cut < m.end() else m.end()

for sent in sentences:
    for m in _claim_matches(sent):
        if is_nonassertive(sent, m, "test"):
            continue
        claimed = True
        break
    if claimed:
        break

# An outcome claim is separate from a test-pass claim. This must be classified
# before the cheap early exit below; otherwise plain "đã fix bug" bypasses the
# entire outcome-evidence check when no new XML exists.
# "đã fix gì" / "đã fix được gì" (the wording of core-rules 2.3) / "what was fixed" are interrogative — the acceptance-report
# headings proof_gate.sh REPORT_ITEMS accepts — never a claim; a claim written after them is matched on its own (2026-09-29).
OUTCOME = re.compile(
    r"(đã\s+fix\b(?!\s+gì\b|\s+được\s+gì\s*(?:[:?(]|$))|đã\s+sửa\s+xong|đã\s+(?:được\s+)?sửa\s+(?:xong\s+)?(?:bug|lỗi)"
    r"|(?:bug|lỗi)[^.\n]{0,32}đã\s+(?:được\s+)?sửa\b"
    r"|đã\s+khắc\s+phục|đã\s+xử\s+lý"
    r"|đã\s+giải\s+quyết(?:\s+xong)?|hết\s+bug"
    r"|(?:the\s+)?fix\s+(?:works?|worked|has\s+worked|(?:đã\s+)?có\s+tác\s+dụng)"
    r"|bug\s+đã\s+(?:được\s+)?fix|(?:lỗi|bug)[^.\n]{0,48}không\s+(?:còn\s+)?tái\s+hiện(?:\s+nữa)?"
    r"|(?<!\bwhat\swas\s)\bfixed\b|\bresolved\b|\b(?:bug|issue|crash|error)\s+(?:is|was|has)\s+(?:now\s+)?gone\b)", re.I)

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
XML_PATTERNS = ("*/build/test-results/*/TEST-*.xml",
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
            ".antigravity-pm/logs/tests_*.xml")
xmls = []
for pat in XML_PATTERNS:
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
            # #427: số đếm hỏng (`failures="x"`, 5 000 chữ số) từng ném ValueError ra ngoài, hook thoát 1 và cho qua. Nay đóng: tests
            # hỏng là 0 (chưa chạy), failures / errors / skipped hỏng là 1 (không phải pass).
            try:
                return int(_n.attrib.get(k, "0") or 0)
            except ValueError:
                return 0 if k == "tests" else 1
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
first_ts = None            # the session's first transcript timestamp (foreign XML freshness floor)
bash_cmds = []             # every Bash command of this session (foreign XML roots)
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
    r"\bunity-batch\.sh\b[^\n|;&]*\b(edit|play)mode\b|\bunity-test\.sh\b|(?<![\w-])-runTests\b|"
    # The DevKit's own bash suites (tests/*/test_*.sh, the hook contract suites, run_impacted,
    # `agent-kit test`): judged by their summary line (DEVKIT_SUITE_* below).
    r"\btests/(?:[\w-]+/)?(?:test_[\w.-]+|\$\{?\w+\}?)\.sh\b|\b\w*contract_test\.sh\b|\brun_impacted\.sh\b|\bagent-kit\s+test\b", re.I)
# Plain script tests (python3/node/bash …/tests/…/test-*.py|js|sh) and every command the
# project's regression matrix declares are test runners too (GeelyEx2 2026-09-27: a real
# RED→GREEN of `python3 tests/scripts/test-admin-….py` was not seen; CHECK 7 held 7 stops).
SCRIPT_RUNNER_RX = re.compile(
    r"(?:\b(?:python\d?(?:\.\d+)?|node|bash|sh)|\"?\$\{?\w+\}?\"?)\s+(?:\S*/)?tests?/(?:\S*/)?test[-_]?[\w.${}-]*\.(?:py|m?js|sh)\b", re.I)
def _matrix_commands():
    try:
        with open(os.path.join(repo, ".agents", "regression_matrix.active.json"), encoding="utf-8") as fh:
            m = json.load(fh)
    except (OSError, ValueError):
        return []
    out = []
    for rule in (m.get("rules") or []) if isinstance(m, dict) else []:
        for t in rule.get("mandatory_regression_tests") or []:
            c = re.sub(r"^(?:\s*[A-Za-z_]\w*=\S*\s+)+", "", str(t.get("command") or "")).strip()
            if len(c) >= 12:          # never a bare `true` / `make`
                out.append(c)
    return out
MATRIX_CMDS = _matrix_commands()
# The DevKit gate itself (`python… post-fix-gate.py --run-tests|--full|--force-full`, or `./…/post-fix-gate.py …`; its name inside `pgrep -f "…"`
# or `grep` is a process lookup, not a run): the one runner every DevKit project has, and the one
# the rules name ("only exit 0 counts"). It prints no TEST-*.xml and its tool_result is often a grep of the log, so the verdict is read
# from ITS text: every verdict line PASS and every "N/M suites" line N == M ≥ 1 (a PASS that ran 0 suites proves nothing). Its result is
# "gate-green": a green for check 2 and for the RED-check of a test file written this session (so a green gate with no RED before it is
# still blocked there), and the GREEN half of check 7's pair (issue #4); a gate has no RED of its own here, so the RED half is a real runner run.
GATE_RUN_RX = re.compile(r"(?:\bpython\S*\s+(?:-\S+\s+)*|(?<![\w\"'./-])(?=\.?/))\S*post-fix-gate\.py\b[^\n|;&]*?(?:--run-tests|--full|--force-full)\b")
GATE_VERDICT_RX = re.compile(r"(?:KẾT LUẬN CỔNG POST-FIX AUDIT|POST-FIX AUDIT GATE VERDICT)\s*:\s*(\S+)")
GATE_COUNT_RX = re.compile(r"(?:Test hồi quy đạt|Regression tests passed)\s*:\s*([1-9]\d*)\s*/\s*([1-9]\d*)\b")
ANSI_RX = re.compile(r"\x1b\[[0-9;]*m")
def is_test_runner(cmd):
    return _is_test_runner(cmd)
# `tests/a/test_$t.sh` (tên ghép từ biến vòng lặp) cũng là suite kit (#427 P1-4): vòng `for t in x y; do bash tests/a/test_$t.sh; done`
# phải theo luật đếm dòng tóm tắt bên dưới, không đi nhánh runner thường (xanh khi không thấy dấu hỏng).
DEVKIT_SUITE_RX = re.compile(r"\btests/(?:[\w-]+/)*(?:test_[\w.${}-]+|\$\{?\w+\}?)\.sh\b|\b\w*contract_test\.sh\b|\brun_impacted\.sh\b|\bagent-kit\s+test\b")
# Their check names may carry FAIL / REJECT / ERROR in capitals ("✔ REJECT on secrets"), so
# the verdict is the summary: red on "N failed/FAILED", "N deviating" (N > 0), "❌" or a "✖"
# line ("✘" too: test_repo_consistency, test_uninstall, test_restore_old print their failures with it);
# green only on an explicit pass summary; anything else is not a verdict.
# A line-start anchor under re.M takes `[^\S\n]*`, never `\s*`: `\s*` runs on across blank lines from every line start, so a tool result
# with 30 000 blank lines took 18-68 s, past the Stop hook's 30 s cap (2026-10-25 review of af339645, P3; section P of the test).
DEVKIT_SUITE_RED = re.compile(r"\b[1-9]\d*\s+(failed|FAILED|deviating)\b|❌|^[^\S\n]*[✖✘] ", re.M)
# "not all tests passed in $d" is no pass summary (2026-10-26 review of 9c1a3cb3, R2-M1): `(?<!not )` before the two "all … passed" forms.
# `ALL … PASSED` có trần 200 ký tự (#427 R4): `[\w ,-]*` không trần chạy từ mỗi chữ "all" tới cuối dòng, một dòng 200 KB "all all …" là bậc
# hai. Dòng tóm tắt thật ngắn; dài hơn thì không còn là tóm tắt (chặn thêm, không mở).
DEVKIT_SUITE_GREEN = re.compile(r"(?<!not )(?:all (checks )?passed|ALL [\w ,-]{0,200}PASSED)|\b0 deviating\b|: all passed", re.I)
# A command is a runner only in the segment that actually runs it. `&&` / `||` / `;` / a newline split segments
# (not inside quotes, or inside for/while/until/if/case … done/fi/esac). A reader (echo, grep, git,
# python -c, …) that merely names a suite or the gate is not a run. `cd` / a `$VAR` expansion still
# says where a real run happens. ponytail: `echo done` inside a for-loop can close the compound early.
_READERS = frozenset({
    "echo", "printf", "grep", "egrep", "fgrep", "rg", "pgrep", "pkill", "cat", "ls", "head", "tail",
    "sed", "awk", "find", "wc", "file", "stat", "less", "more", "nl", "cut", "sort", "uniq", "tr", "tee",
    "true", "false", "cd", "pushd", "popd", "pwd", "which", "type", "command", "export", "git", "ps",
    "sleep", "date", "basename", "dirname", "realpath", "readlink",
})
_ASSIGN_RX = re.compile(r"(?:^|[\s;&|(])([A-Za-z_]\w*)=(?:\"([^\"\n]*)\"|'([^'\n]*)'|([^\s;&|]+))")
_GATE_FLAG = ("--run-tests", "--full", "--force-full")

def _argv0(word):
    base = word.replace("\\", "/").split("/")[-1]
    return base[2:] if base.startswith("./") else base

def _collect_assigns(text):
    env = {}
    for m in _ASSIGN_RX.finditer(text or ""):
        val = m.group(2) if m.group(2) is not None else (m.group(3) if m.group(3) is not None else (m.group(4) or ""))
        env[m.group(1)] = val
    return env

def _expand_vars(text, env):
    def repl(m):
        name = m.group(1) or m.group(2)
        return env.get(name, m.group(0))
    return re.sub(r"\$\{([A-Za-z_]\w*)\}|\$([A-Za-z_]\w*)", repl, text or "")

# The variables of EVERY earlier Bash command of the session, a later assignment winning. bash_cmds only grows (append), so the
# table is extended with the commands added since the last call instead of rebuilt from the first command for each command: that
# rebuild was quadratic (OfficeReader, 58 MB transcript: 1.43 million regex scans, 25 of the 26 s of a Stop; backlog #4, 2026-10-10).
_env_all = {}
_env_seen = 0

def _env_for(cmd):
    global _env_seen
    for earlier in bash_cmds[_env_seen:]:
        _env_all.update(_collect_assigns(earlier))
    _env_seen = len(bash_cmds)
    env = dict(_env_all)
    env.update(_collect_assigns(cmd))
    return env

# `<<WORD`, `<<-WORD`, `<<'WORD'`, `<<"WORD"`, `<<\WORD` (not `<<<`, not `1 << 2`): its body follows the line and is data, never commands.
_HEREDOC_RX = re.compile(r"<<(-?)[^\S\n]*\\?(['\"]?)([A-Za-z_][\w.-]*)\2")

def _split_segments(cmd, seps=None):
    """Top-level && / || / ; / newline pieces. Not inside quotes, a heredoc body, or a for/while/until/if/case compound; a newline after
    a `|` continues the pipe (2026-10-26 review of 322b19db, D4: `pytest > log 2>&1` then `echo "rc=$?"` on the next line was one piece).
    seps, when given, receives the separator after each piece but the last ("&&", "||", ";", "\\n")."""
    parts, buf, word, heredocs = [], [], [], []
    i, n, quote, paren, compound, last = 0, len(cmd), None, 0, 0, ""

    def cut(sep):
        seg = "".join(buf).strip()
        if seg:
            parts.append(seg)
            if seps is not None:
                seps.append(sep)
        buf.clear()

    def end_word():
        nonlocal compound
        if not word:
            return
        w = "".join(word)
        word.clear()
        if w in ("for", "while", "until", "if", "case"):
            compound += 1
        elif w in ("done", "fi", "esac") and compound:
            compound -= 1

    while i < n:
        c = cmd[i]
        if c not in " \t\r\n":
            last = c
        if quote:
            buf.append(c)
            word.append(c)
            if c == "\\" and i + 1 < n:
                buf.append(cmd[i + 1])
                word.append(cmd[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c in "\"'":
            quote = c
            buf.append(c)
            word.append(c)
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            buf.append(c)
            buf.append(cmd[i + 1])
            word.append(cmd[i + 1])
            i += 2
            continue
        if c == "(":
            paren += 1
            end_word()
            buf.append(c)
            i += 1
            continue
        if c == ")":
            paren = max(0, paren - 1)
            end_word()
            buf.append(c)
            i += 1
            continue
        if c == "<" and cmd.startswith("<<", i) and not cmd.startswith("<<<", i) and (i == 0 or cmd[i - 1] != "<"):
            m = _HEREDOC_RX.match(cmd, i)
            if m:
                end_word()
                heredocs.append((m.group(3), m.group(1) == "-"))
                buf.append(m.group(0))
                i = m.end()
                continue
        if c == "\n":
            end_word()
            buf.append(c)
            i += 1
            # The heredoc bodies of this line follow it, in order, whatever the depth: kept in this piece, never split or parsed.
            for delim, tabs in heredocs:
                while i < n:
                    j = cmd.find("\n", i)
                    j = n if j < 0 else j + 1
                    line = cmd[i:j].rstrip("\r\n")
                    buf.append(cmd[i:j])
                    i = j
                    if (line.lstrip("\t") if tabs else line) == delim:
                        break
            heredocs.clear()
            if paren == 0 and compound == 0 and last != "|":
                cut("\n")
            continue
        if c in " \t\r\n":
            end_word()
            buf.append(c)
            i += 1
            continue
        if paren == 0 and compound == 0 and (cmd.startswith("&&", i) or cmd.startswith("||", i) or c == ";"):
            end_word()
            sep = ";" if c == ";" else cmd[i:i + 2]
            cut(sep)
            i += len(sep)
            continue
        buf.append(c)
        word.append(c)
        i += 1
    end_word()
    seg = "".join(buf).strip()
    if seg:
        parts.append(seg)
    if seps is not None:
        del seps[max(len(parts) - 1, 0):]     # a trailing `;` / newline separates nothing
    return parts or ([cmd.strip()] if cmd.strip() else [])

def _words(seg):
    try:
        return shlex.split(seg, posix=True)
    except ValueError:
        return seg.split()

def _strip_assigns(words):
    i = 0
    while i < len(words) and re.match(r"^[A-Za-z_]\w*=", words[i]):
        i += 1
    return words[i:]

def _is_reader(words):
    return bool(words) and _argv0(words[0]) in _READERS

def _is_python_c(words):
    if not words or not re.match(r"^python\d?(?:\.\d+)?$", _argv0(words[0])):
        return False
    return any(w == "-c" or (w.startswith("-c") and w != "-c") for w in words[1:4]) or "-c" in words[1:4]

def _has_gate_flag(words):
    return any(w.split("=", 1)[0] in _GATE_FLAG for w in words)

def _invokes_gate_words(words):
    return any(_argv0(w) == "post-fix-gate.py" for w in words) and _has_gate_flag(words)

# File kit chạy thẳng bằng bash/sh: tests/**/test_*.sh hoặc hooks/tests/*.sh.
# bash -c và cat không phải lần chạy (issue #74). ponytail: vòng for vẫn cần dòng tóm tắt.
_KIT_BASH_FILE = re.compile(
    r"(?:^|/)(?:tests(?:/[\w.-]+)*/test_[\w.-]+\.sh|hooks/tests/[\w.-]+\.sh)$")

def _bash_runs_command_string(words):
    """True when bash/sh does not run the file as a test: -c (command string) or -n/--noexec (syntax check only, exit 0).
    Only bash's OWN options count: they end at the first word that is not an option (the script), and what follows is the script's
    arguments (`bash tests/a/test_x.sh -n 3` runs the test; `bash -n tests/a/test_x.sh` does not)."""
    args = words[1:]
    i = 0
    while i < len(args):
        w = args[i]
        if w == "--" or not (w.startswith("-") or w.startswith("+")):
            break
        if w in ("-o", "+o"):   # `set -o NAME`: the next word is an option NAME, not the script
            if i + 1 < len(args) and args[i + 1] == "noexec":
                return True
            i += 2
            continue
        if w in ("-O", "+O", "--rcfile", "--init-file"):   # takes a value (shopt name / file): that word is not the script
            i += 2
            continue
        if w == "--noexec":
            return True
        if w == "-c" or (w.startswith("-") and not w.startswith("--") and ("c" in w[1:] or "n" in w[1:])):
            return True
        i += 1
    return False

def _direct_bash_kit(seg):
    words = _strip_assigns(_words(seg))
    if len(words) < 2 or _argv0(words[0]) not in ("bash", "sh"):
        return False
    if _bash_runs_command_string(words):
        return False
    # | và & làm exit của tool không còn là exit của file test (; && || đã tách segment).
    if any(w in ("|", "|&", "&") for w in words):
        return False
    script = next((w for w in words[1:] if not w.startswith("-")), "")
    return bool(_KIT_BASH_FILE.search(script))

def _subshell_body(seg):
    """Phần trong của `( … )` mở đầu segment (subshell), hoặc None."""
    s = seg.lstrip()
    if not s.startswith("("):
        return None
    depth, quote, i = 0, None, 0
    while i < len(s):
        c = s[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "\\":
            i += 2
            continue
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return s[1:i]
        i += 1
    return None

_INTERP = re.compile(r"(?:ba|z)?sh|python\d?(?:\.\d+)?|node")
# File test: dưới tests/; hay tên test_* / *_test ở một thư mục nhóm test (`runtests.sh gates/test_x.sh`) hoặc không thư mục. Không phải
# `hooks/test_evidence_gate.sh` (một hook mang tên test_). Chỉ xét trong segment mà _base_runner đã thấy.
_TEST_ARG = re.compile(r"(?:^|/)tests?/(?:[^/\s]+/)*[^/\s]*test[^/\s]*\.(?:sh|py|m?js)$"
                       r"|(?:(?:^|/)(?:gates|verification|context_memory|worktree_git|installer|super-board|spec|__tests__)/|^)"
                       r"(?:test[-_][^/\s]*|[^/\s]*[_.]test)\.(?:sh|py|m?js)$")

def _argv_test_run(words):
    """Một trình thông dịch (bash/sh/zsh/python/node, không phải -c / -n / -m / stdin) hay một script chạy theo đường dẫn nhận một file
    test làm đối số, ở bất kỳ vị trí nào của argv: `bash universal-agent-devkit/tests/x/test_y.sh | tail -5`, `bash "$K/tests/gates/$t.sh"`,
    `bash $S/run.sh tests/x/test_y.sh 80`, `python3 runtests.py r3 tests/gates/test_x.sh`, `perl -e 'alarm 400; exec @ARGV' bash
    tests/…/test_x.sh`. Chỉ để phân loại (như trước #427 với dạng này), không gắn mã thoát. `pip install`, `touch`, `chmod`, `cp`,
    `shellcheck`, `[ -f … ]` không có trình thông dịch nên không thuộc đây."""
    for k, w in enumerate(words):
        a = _argv0(w)
        if not (_INTERP.fullmatch(a) or (k == 0 and re.match(r"[\w.$~/{}-]*/[^/]+\.(?:sh|py)$", w) and not w.startswith("-"))):
            continue
        if a in ("bash", "sh", "zsh") and _bash_runs_command_string(words[k:]):
            continue
        if a.startswith("python") and any(x in ("-", "-m") or x.startswith("-c") for x in words[k + 1:k + 4]):
            continue
        if a == "node" and any(x in ("-", "-e", "-p", "--eval", "--print") for x in words[k + 1:k + 4]):
            continue
        if any(_TEST_ARG.search(x) or DEVKIT_SUITE_RX.search(x) for x in words[k + 1:]):
            return True
    return False

def _command_string(words):
    """Chuỗi lệnh của `bash -c '…'` / `sh -lc "…"` / `zsh -c …`, hoặc None."""
    if not words or _argv0(words[0]) not in ("bash", "sh", "zsh"):
        return None
    for j, w in enumerate(words[1:], 1):
        if not w.startswith("-") or w == "--":
            return None
        if not w.startswith("--") and "c" in w[1:]:
            return words[j + 1] if j + 1 < len(words) else None
    return None

def _wrapped_runner(words):
    """`uv run --frozen --extra dev pytest -q`, `npx -y vitest run`: runner sau option (và giá trị option) của wrapper, mà _head_starts
    không bỏ qua. Chỉ để phân loại."""
    a = _argv0(words[0]) if words else ""
    i = (2 if (a in ("uv", "poetry", "pipenv", "pdm", "hatch") and words[1:2] == ["run"]) or (a == "pnpm" and words[1:2] == ["exec"])
         else 1 if a in ("npx", "bunx") else 0)
    if not i:
        return False
    for j in range(i, len(words)):
        w = words[j]
        if not w.startswith("-") and TEST_RUNNER_RX.match(" ".join([_argv0(w)] + words[j + 1:])):
            return True
        if not w.startswith("-") and not (j > i and words[j - 1].startswith("-")):
            return False       # w is no option and no option's value: the command proper starts at w, and it is no runner
    return False

def _base_runner(seg):
    """Luật phân loại trước #427 (tên runner ở bất kỳ đâu trong segment): tập runner mới là tập con của nó."""
    words = _strip_assigns(_words(seg))
    if not words or _is_reader(words) or _is_python_c(words):
        return False
    return bool(_direct_bash_kit(seg) or TEST_RUNNER_RX.search(seg) or SCRIPT_RUNNER_RX.search(seg) or GATE_RUN_RX.search(seg)
                or _invokes_gate_words(words) or any(c in seg for c in MATRIX_CMDS))

def _simple_runner(seg):
    # P1-2 (#427): runner chỉ là runner khi nó LÀ lệnh của segment (neo đầu lệnh, sau wrapper: _runs_as_command), không phải khi tên nó
    # nằm đâu đó trong segment. `pip install -q pytest`, `touch pytest.ini`, thân heredoc nhắc pytest không chạy test nào: trước đây là
    # lần chạy XANH (kèm một dòng "N passed" ở đâu đó) hoặc nửa ĐỎ của check 7 (khi lệnh lỗi). Thân heredoc là dữ liệu: chỉ đọc dòng lệnh.
    # Đo trên 148 182 lệnh Bash thật (30 ngày): các dạng dưới đây giữ lại những lần chạy thật mà neo đầu lệnh làm mất. Chỉ thu hẹp: một
    # segment là runner khi luật cũ (_base_runner, tìm ở bất kỳ đâu) cũng nói vậy; lần chạy thật mà luật cũ không thấy (`bash test_x.sh`
    # trong tests/gates, `bash -x tests/…`) vẫn không thấy.
    if not _base_runner(seg):
        return False
    line0 = seg.split("\n", 1)[0]
    if _HEREDOC_RX.search(line0):
        seg = line0
    seg = re.sub(r"^\s*time(?:\s+-p)?\s+", "", seg)       # từ khoá `time` của shell: `time (bash …)`, `time VAR=x cmd`
    # `caffeinate -dimsu env UNITY_TIMEOUT=1200 bash …/unity-batch.sh playmode`, `nohup …`: chỉ để phân loại (mã thoát vẫn coi là bị che)
    seg = re.sub(r"^\s*(?:(?:caffeinate(?:\s+-[a-zA-Z]+(?:\s+\d+)?)*|nohup)\s+)+", "", seg)
    words = _strip_assigns(_words(seg))
    if not words or _is_reader(words) or _is_python_c(words):
        return False
    if _direct_bash_kit(seg) or GATE_RUN_RX.search(seg) or _invokes_gate_words(words):
        return True
    if _runs_as_command(seg) or _argv_test_run(words) or _wrapped_runner(words):
        return True
    if any(re.sub(r"^(?:\s*[A-Za-z_]\w*=\S*\s+)+", "", seg.lstrip()).startswith(c) for c in MATRIX_CMDS):
        return True
    # `(cd sub && python3 -m pytest -q)`, `bash -c 'cd x && pytest'`: xét lại từng segment bên trong
    inner = _subshell_body(seg)
    if inner is None:
        inner = _command_string(words)
    return inner is not None and any(_segment_is_runner(p) for p in _split_segments(inner))

def _compound_body(seg):
    m = re.search(r"\bdo\b(.*)\bdone\b", seg, re.S) or re.search(r"\bthen\b(.*)\bfi\b", seg, re.S)
    return m.group(1) if m else ""

def _segment_is_runner(seg):
    if re.match(r"(?:for|while|until|if|case)\b", seg.lstrip()):
        body = _compound_body(seg)
        if any(_segment_is_runner(p) for p in _split_segments(body)):
            return True
        # The suite path sits in the header (`for f in tests/gates/test_*.sh`) and the body only has bash "$f".
        return bool(re.search(r"\b(?:bash|sh)\b", body) and re.search(
            r"(?:^|[\s\"'])tests/(?:[\w.-]+/)?test_[\w*.${}-]*\.sh|\$\w+/tests/", seg))
    return _simple_runner(seg)

def _segment_invokes_gate(seg):
    if re.match(r"(?:for|while|until|if|case)\b", seg.lstrip()):
        return any(_segment_invokes_gate(p) for p in _split_segments(_compound_body(seg)))
    words = _strip_assigns(_words(seg))
    if not words or _is_reader(words) or _is_python_c(words):
        return False
    return _invokes_gate_words(words) or bool(GATE_RUN_RX.search(seg))

def _command_segments(cmd):
    return _split_segments(_expand_vars(cmd, _env_for(cmd)))

def _is_test_runner(cmd):
    return any(_segment_is_runner(seg) for seg in _command_segments(cmd))

def _command_invokes_gate(cmd):
    return any(_segment_invokes_gate(seg) for seg in _command_segments(cmd))

def _command_is_direct_bash_kit(cmd):
    segs = [s for s in _command_segments(cmd) if s.strip()]
    # Một segment: exit của tool là exit của file. ; true / || true không được tính xanh.
    return len(segs) == 1 and _direct_bash_kit(segs[0])

_HOOKS_TESTS_FILE = re.compile(r"(?:^|/)hooks/tests/[\w.-]+\.sh$")

def _direct_hooks_tests(seg):
    """hooks/tests/*.sh chạy thẳng. tests/** đã là suite hoặc script runner, không phân loại lại."""
    words = _strip_assigns(_words(seg))
    if len(words) < 2 or _argv0(words[0]) not in ("bash", "sh") or _bash_runs_command_string(words):
        return False
    script = next((w for w in words[1:] if not w.startswith("-")), "")
    return bool(_HOOKS_TESTS_FILE.search(script.replace("\\", "/")))

def _is_suite_seg(seg):
    return _segment_is_runner(seg) and bool(DEVKIT_SUITE_RX.search(seg) or _direct_hooks_tests(seg))

def _command_is_suite(cmd):
    return any(_is_suite_seg(seg) for seg in _command_segments(cmd))
# Failure markers. Counts only when non-zero ("fail 0", "0 failed" are green), and the
# bare words only in the capitals runners print (FAIL, FAILED, ERROR) — a passing test
# named "shows error message" or node's "ℹ fail 0" summary must not read as red.
# NUnit 3 (Unity) prints its verdict as `<test-run … failed="N">`: red only when N > 0.
# Thuộc tính của thẻ không chứa `<` (#427 R4): `[^>\n]*` từ mỗi `<test-run` của một dòng `<test-run <test-run …` chạy tới cuối dòng.
RUNNER_FAIL_RX = re.compile(
    r"(?i:\b[1-9]\d*\s+(failed|failing|failures?|errors?)\b)|(?i:\btests?:\s+[1-9]\d*\s+failed)|"
    r"(?i:^[^\S\n]*(?:[#ℹ*•-]\s*)?(fail|failures?|errors?)\s*[:=]?\s*[1-9]\d*\b)|"
    r"<test-run\b[^<>\n]*\sfailed=\"[1-9]\d*\"|"
    # JUnit XML summary printed by the agent (`<testsuite … failures="5">`) after sending the
    # runner's own output to a log (GeelyEx2 2026-09-28: every real red read as green).
    r"\b(?:failures|errors)=\"[1-9]\d*\"|"
    r"\bFAIL(ED)?\b|test result: FAILED|^not ok\b|\bpanicked\b|\bERRORS?\b|--- FAIL", re.M)
# mcp__antigravity-pm__pm_run kind=test runs the project's test command and prints
# `exit=N` per command (a timeout adds "(QUA HAN)"; "CHUA TINH" = exit 0 that its own
# evidence check did not accept as green). No `exit=` line = the tool refused before
# running anything, which is neither red nor green.
PM_RUN_EXIT_RX = re.compile(r"^exit=(-?\d+|null)", re.M)
# `bash tests/…/test_x.sh > log 2>&1; echo "rc=$?"`: the segment right after a run prints that run's exit code (2026-10-25 audit: the
# kit suite runs of f294e5d9 printed rc=0 and still read as no verdict). A runner segment is bound to its code only when it is ONE simple
# command (no pipe, `&`, `;` or loop: `$?` would be the pipe's last command, the background launch or the last iteration), the NEXT
# segment is `echo "<label>=$?"`, and the label is printed exactly once.
_ECHO_RC_RX = re.compile(r"""echo\s+(["']?)([A-Za-z_][\w.-]*)=\$\?\1\s*$""")
# #427: hai cách in mã thoát nữa, chỉ dùng cho ĐỎ (mã 0 của chúng không là xanh: một dòng "rc=0" sau `pytest | tail -1` không nói gì về
# tóm tắt mà kết quả đang đưa ra). `run | tail -N; echo "rc=${PIPESTATUS[0]}"` (zsh: `${pipestatus[1]}`) in mã của chặng ĐẦU của pipe;
# `run > log 2>&1; echo $?` không nhãn, là segment CUỐI, in mã ở dòng không trống cuối cùng.
_ECHO_PS_RX = re.compile(r"""echo\s+(["']?)([A-Za-z_][\w.-]*)=\$\{(?:PIPESTATUS\[0\]|pipestatus\[1\])\}\1\s*$""")
_BARE_ECHO_RC = re.compile(r"""echo\s+(["']?)\$(?:\?|\{\?\})\1\s*$""")
# A positive pass summary of a common runner (pytest / jest / vitest "N passed", mocha "N passing", cargo, go, unittest, XCTest, rspec,
# phpunit, dotnet, xcodebuild): what a masked run below needs for a green when its exit code cannot be bound.
RUNNER_PASS_RX = re.compile(r"\b[1-9]\d*\s+(?:tests?\s+)?(?:passed|passing)\b|\btest result: ok\b"
                            r"|^ok[^\S\n]+\S+[^\S\n]+(?:[\d.]+s|\(cached\))|\bRan [1-9]\d* tests? in [\d.]+s\s+OK\b"
                            r"|\bExecuted [1-9]\d* tests?, with 0 failures\b|\b[1-9]\d* examples?, 0 failures\b"
                            r"|^OK \([1-9]\d* tests?\b|^Passed!\s|\*\* TEST SUCCEEDED \*\*", re.M)
# Pass summaries one RUNNER_PASS_RX match cannot judge (2026-10-26 review of 322b19db, P2): node --test's `ℹ pass N` with `ℹ fail 0` on the
# next line; Maven's `Tests run: N, Failures: 0, Errors: 0`, only with no `Tests run:` line that carries a failure or an error and no BUILD
# FAILURE (RUNNER_FAIL_RX does not read those mid-line counts); Gradle's BUILD SUCCESSFUL, only when every runner it must speak for is Gradle.
NODE_PASS_RX = re.compile(r"^[^\S\n]*ℹ pass [1-9]\d*[^\S\n]*\n[^\S\n]*ℹ fail 0[^\S\n]*$", re.M)
MVN_PASS_RX = re.compile(r"\bTests run: [1-9]\d*, Failures: 0, Errors: 0\b")
MVN_RED_RX = re.compile(r"\bTests run: \d+, Failures: (?:[1-9]|\d+, Errors: [1-9])|\bBUILD FAILURE\b")
GRADLE_PASS_RX = re.compile(r"^[^\S\n]*BUILD SUCCESSFUL\b", re.M)
_GRADLE_RX = re.compile(r"(?:^|[\s/])gradlew?(?=\s|$)")
# NUnit 3 (Unity) `<test-run … passed="N" failed="0" …>` printed after the run (`Unity … -runTests …; cat results.xml`).
NUNIT_PASS_RX = re.compile(r"<test-run\b(?=[^<>\n]*\spassed=\"[1-9]\d*\")(?=[^<>\n]*\sfailed=\"0\")")   # `<`: như RUNNER_FAIL_RX (#427 R4)

def _late_blocks(txt, segs, idxs):
    """#427 item 8: một runner trong idxs là mocha / node --test / go test qua `tail` mà kết quả thiếu thứ thay được kết luận đã bị cắt:
    `go test ./... | tail -N` cho thấy vài package 'ok', không phải mọi package, nên cần segment sau in `${PIPESTATUS[0]}` = 0;
    `node --test | tail -N` cần đúng tóm tắt của node ('ℹ pass N' rồi 'ℹ fail 0'). mocha: 'N passing' của nó đứng ngay trước 'M failing'
    nên thấy được là đủ; khi có segment khác sau nó thì _hides đã chặn. Kết quả ít hơn N dòng: tail không cắt gì."""
    for i in idxs:
        for p in (_runner_pieces(segs[i]) or [segs[i]]):
            kind = _tail_cut(p, txt)
            if (kind == "go" and not (p is segs[i] and _ps_zero(segs, i, txt))) or (kind == "node" and not NODE_PASS_RX.search(txt)):
                return True
    return False

def _pass_summary(txt, segs, idxs):
    """txt holds a pass summary that can speak for the runner segments idxs, whose exit codes are not bound."""
    if _late_blocks(txt, segs, idxs):
        return False
    if (RUNNER_PASS_RX.search(txt) or NODE_PASS_RX.search(txt) or NUNIT_PASS_RX.search(txt)
            or (MVN_PASS_RX.search(txt) and not MVN_RED_RX.search(txt))):
        return True
    # Gradle: each runner PIECE (every runner in a loop / if, 2026-10-26 OCR review round 2, P1-3: `for m in a b; do pytest > /dev/null;
    # ./gradlew :$m:test; done` was judged by the whole loop text) is Gradle run as the command of its piece.
    pieces = [p for i in idxs for p in (_runner_pieces(segs[i]) or [segs[i]])]
    return (bool(pieces) and all(_GRADLE_RX.search(p) and _runs_as_command(p) for p in pieces)
            and bool(GRADLE_PASS_RX.search(txt)))

# A kit suite's own lines: its check lines (✔ ✓ ✅ ✖ ✘ ❌) and its summary ("all passed (3)", "uninstall: 9 passed, 0 failed", "contract
# points: 3 ok, 0 deviating"). What is left is all another runner of the command can have printed (2026-10-26 review of 9c1a3cb3, P1).
_KIT_LINE_RX = re.compile(r"^[^\S\n]*[✔✓✅✖✘❌]|" + DEVKIT_SUITE_GREEN.pattern
                          + r"|^[\w ./-]+:[^\S\n]+\d+[^\S\n]+(?:passed|ok),[^\S\n]+\d+[^\S\n]+(?:failed|deviating)\b", re.I)

def _not_kit_lines(txt):
    return "\n".join(line for line in txt.splitlines() if not _KIT_LINE_RX.search(line))
_STATUS_READ = re.compile(r"\$\?|\$\{\?\}|PIPESTATUS")
_COMPOUND = re.compile(r"\s*(?:for|while|until|if|case)\b")
# A redirection of stdout to a file (`>`, `1>`, `>>`, `&>`): not `2>…`, not `>&2` / `2>&1`.
_STDOUT_AWAY = re.compile(r"(?:^|[^\d&>])(?:1?>>?|&>>?)(?!&)"
                          r"|(?:^|[^\d&>])>&[ \t]*(?![\d-])\S")   # `>& file` (stdout and stderr; not `>&2`, `>&-`): OCR round 3, E2

def _single_command(seg):
    s = re.sub(r"\"[^\"]*\"|'[^']*'", "", seg)     # quoted text is data
    s = re.sub(r"\d*>&\d+|&>>?|>&", " ", s)         # 2>&1, &>log: redirections, not job control
    return not re.match(r"\s*(?:for|while|until|if|case)\b", s) and not re.search(r"[;|&\n]", s)

def _head_starts(words):
    """Where the command proper may start: 0, and after each leading wrapper that hands back the wrapped command's own exit code
    (timeout, env, time, nice, `uv|poetry|pipenv|pdm|hatch run`, npx, bunx, yarn, `pnpm exec`)."""
    out, i = [0], 0
    while i < len(words):
        a = _argv0(words[i])
        if a in ("timeout", "gtimeout", "env", "time", "nice"):
            i += 1
            while i < len(words) and (words[i].startswith("-") or (a == "env" and re.match(r"[A-Za-z_]\w*=", words[i]))):
                i += 2 if words[i] in ("-s", "-k", "-n", "-u") else 1
            i += 1 if a in ("timeout", "gtimeout") else 0     # the duration
        elif a in ("uv", "poetry", "pipenv", "pdm", "hatch") and words[i + 1:i + 2] == ["run"]:
            i += 2
        elif a in ("npx", "bunx", "yarn"):
            i += 1
        elif a == "pnpm" and words[i + 1:i + 2] == ["exec"]:
            i += 2
        elif a in ("bash", "sh") and not _bash_runs_command_string(words[i:]):
            # `bash scripts/unity-test.sh`: bash runs the script file, whose exit is bash's. Not `bash -c` / `bash -n`.
            i += 1
            while i < len(words) and words[i].startswith(("-", "+")) and words[i] != "--":
                i += 2 if words[i] in ("-o", "+o", "-O", "+O", "--rcfile", "--init-file") else 1
        else:
            break
        out.append(i)
    return out

def _runs_as_command(seg):
    """The runner IS the command of this segment (2026-10-25, fail-open of a pytest run sent to a log, then `echo "rc=$?"`): its words,
    from the start or after wrappers, match a runner pattern anchored at the head. `! pytest`, `eval "pytest"`, `bash -c "pytest || true"`,
    `pip install pytest` only name a runner: their exit code is not a test run's."""
    words = _strip_assigns(_words(seg))
    for i in _head_starts(words):
        head = words[i:]
        if not head:
            break
        if re.fullmatch(r"(?i)unity(?:\.exe)?", _argv0(head[0])) and "-runTests" in head:   # the Editor binary with -runTests
            return True
        for w0 in {head[0][2:] if head[0].startswith("./") else head[0], _argv0(head[0])}:
            text = " ".join([w0] + head[1:])
            if TEST_RUNNER_RX.match(text) or SCRIPT_RUNNER_RX.match(text) or any(text.startswith(c) for c in MATRIX_CMDS):
                return True
    return False

def _hidden(segs, i, txt):
    """Runner segment i may hide its result, so the absence of a failure marker says nothing of it: a segment from it on reads `$?`
    (the tool's exit is then the reader's; the code counts only when bound, _echoed_codes), or it is a compound (for/while/until/if/case:
    the tool's exit is the last iteration's) that left blank output or sent its stdout to a file. A compound whose output is in the
    result keeps the plain rule."""
    s = segs[i]
    return bool(any(_STATUS_READ.search(t) for t in segs[i:])
                or (_COMPOUND.match(s) and (not txt.strip() or _compound_stdout_away(s))))

_CLOSE_KW = re.compile(r"\b(?:done|fi|esac)\b")
_PART_KW = re.compile(r"^(?:(?:do|then|else|elif)\b\s*)+")
_QUOTED = re.compile(r"\"[^\"]*\"|'[^']*'")
# Option toàn cục của git trước subcommand (#427 item 9): `git -C <repo> commit -q`, `git -c k=v commit -q` vẫn là commit im lặng.
_GIT_GLOBAL = r"(?:\s+(?:-[Cc]\s+\S+|--[\w-]+(?:=\S+)?|-[pP]))*"
_QUIET_COMMIT = re.compile(r"\s*git" + _GIT_GLOBAL + r"\s+commit\b[^|;&]*\s-(?:-quiet\b|[a-zA-Z]*q)")   # `git commit -q` / `-qam` / `--quiet`: no output
# Lệnh in subject của commit ra kết quả: `git commit -q -m "12 passing"; git log --oneline -1` in lại chữ pass đó (#427 item 9).
_PRINTS_LOG = re.compile(r"\s*git" + _GIT_GLOBAL + r"\s+(?:log|show|reflog|shortlog|whatchanged)\b")
_GIT_COMMIT = re.compile(r"\s*git" + _GIT_GLOBAL + r"\s+commit\b")
# Lệnh ghi lên GitHub, chỉ in URL chứ không in --body: `gh pr comment 5 --body "… 12 passed"`. `gh pr view` in body nên không thuộc đây.
_GH_WRITE = re.compile(r"\s*gh\s+(?:pr|issue)\s+(?:comment|create|edit)\b")
_DEV_OUT = re.compile(r">>?[ \t]*/dev/(?:stdout|stderr|tty|fd/\d+)\b")   # ghi vào file nhưng file đó lại là kết quả

def _silent(t):
    """Segment t không in gì vào kết quả (#427 item 9): dòng lệnh của nó đẩy stdout ra file hay /dev/null (`cat > f <<EOF … EOF`,
    `printf … > /dev/null`; thân heredoc là dữ liệu, không xét), hoặc là `gh pr|issue comment|create|edit`. Không tính: `>&2`,
    `> /dev/stderr`, `/dev/tty`, `/dev/fd/N` (vẫn vào kết quả), lệnh nhiều dòng không phải heredoc."""
    head = _heredoc_head(t)
    if head is None:
        return False
    h = _QUOTED.sub("", head)
    return not _DEV_OUT.search(h) and bool(_STDOUT_AWAY.search(h) or _GH_WRITE.match(h))

def _heredoc_head(t):
    """Dòng lệnh của segment t: cả t khi nó một dòng; khi nhiều dòng, dòng đầu nếu phần còn lại đúng là thân của MỘT heredoc mở trên dòng
    đó (dòng cuối là dấu kết), else None. INSTINCT-045: máy quét không phải shell, nghi ngờ thì không bỏ phần nào."""
    head = t.split("\n", 1)[0]
    if "\n" not in t.strip():
        return head
    hd = _HEREDOC_RX.findall(head)
    last = t.rstrip("\n").rsplit("\n", 1)[-1]
    if len(hd) != 1 or (last.lstrip("\t") if hd[0][0] else last) != hd[0][2]:
        return None
    return head

def _pipe_head(seg):
    """Chặng đầu của một pipe đơn (`run 2>&1 | tail -3`), cả lệnh khi nó là một lệnh đơn; None khi có `;`, `&`, xuống dòng, vòng lặp."""
    flat = _QUOTED.sub(lambda q: "x" * len(q.group(0)), seg)
    flat = re.sub(r"\|[ \t]*\n", lambda q: q.group(0).replace("\n", " "), flat)     # `run |` xuống dòng `tail -3`: vẫn là một pipe
    if _COMPOUND.match(flat) or re.search(r"[;\n]|&", re.sub(r"\d*>&\d+|&>>?|>&", lambda q: " " * len(q.group(0)), flat)):
        return None
    k = flat.find("|")
    return seg[:k].strip() if k > 0 else (seg if k < 0 else None)

def _late_summary(stage):
    """mocha / node --test / go test (#427 item 8): in chi tiết lỗi SAU dòng 'N failing' / 'ℹ fail N', go test nhiều package không có
    tóm tắt chung, nên `| tail -N` của chúng không giữ được kết luận. Trả về loại runner hoặc None. go test chỉ khi nhiều package
    (`./...`): một package in dòng `ok` / `FAIL <pkg>` của nó ở CUỐI (`go test -count=1 . | tail -2`: dạng thường gặp nhất trong lệnh thật)."""
    words = _strip_assigns(_words(stage))
    for i in _head_starts(words):
        h = words[i:]
        if not h:
            break
        a = _argv0(h[0])
        if a == "mocha":
            return "mocha"
        if a == "node" and "--test" in [w.split("=", 1)[0] for w in h[1:]]:
            return "node"
        if a == "go" and h[1:2] == ["test"]:
            return "go" if any("..." in w for w in h[2:]) else None
    return None

_TAIL_N = re.compile(r"\|\s*tail\b(?:\s+(?:-n\s*|-)(\d+))?")

def _tail_cut(seg, txt=None):
    """Loại runner (mocha / node / go) khi segment là pipe đơn chạy nó qua `tail -N`, else None. Với txt: kết quả có ít hơn N dòng thì
    tail không cắt gì (cả output đã hiện), không tính."""
    head = _pipe_head(seg)
    m = _TAIL_N.search(_QUOTED.sub("", seg)) if head is not None and head is not seg else None
    if m is None or (txt is not None and len(txt.splitlines()) < int((m.group(1) or "10")[:7])):
        return None
    return _late_summary(head)

# `trap … EXIT` (#427 E4): mã thoát của tool là của trap, không phải của runner, theo cả hai chiều (`trap 'exit 0' EXIT` giấu ĐỎ,
# `trap 'exit 1' EXIT` làm giả ĐỎ). Ở vị trí lệnh, đâu cũng được trong lệnh; chữ trong ngoặc là dữ liệu, thân heredoc cũng vậy khi
# _heredoc_head chắc chắn về nó (`cat > t.sh <<'EOF'` chép một test có `trap 'rm -rf "$TMP"' EXIT`, rồi chạy nó: lệnh thật, 30 ngày qua).
# Có trap mà tool lỗi: không ĐỎ, cũng không XANH (None).
_EXIT_TRAP = re.compile(r"(?:^|[;&|({\n]|\b(?:do|then|else)\b)[^\S\n]*trap[^\S\n]+[^;&|\n]*?(?<![\w-])(?:SIG)?(?:EXIT|0)(?![\w-])", re.I)

def _exit_trapped(cmd):
    return any(_EXIT_TRAP.search(_QUOTED.sub("", _heredoc_head(s) or s)) for s in _command_segments(cmd))

def _compound_parts(seg, seps=None):
    """(pieces, tail) of a compound: the pieces of its condition and body with do / then / else / elif cut (a nested compound stays one
    piece), and the text after its closing keyword. A keyword inside quotes is data. seps: as for _split_segments."""
    flat = _QUOTED.sub(lambda m: m.group(0)[0] + "x" * (len(m.group(0)) - 2) + m.group(0)[-1], seg)   # same length, keywords blanked
    head = _COMPOUND.match(flat)
    close = None
    for close in _CLOSE_KW.finditer(flat):
        pass
    inner = seg[head.end() if head else 0:close.start() if close else len(seg)]
    return [_PART_KW.sub("", p) for p in _split_segments(inner, seps)], (seg[close.end():] if close else "")

def _compound_stdout_away(seg):
    """The compound sends stdout to a file: a redirection after its closing keyword (`done > all.log`), or in a piece of its condition or
    body that is not a reader such as echo / printf (each nested compound by the same rule). `echo "== $f" >> ran.txt` next to the run
    is not the run's output (2026-10-26 review of 322b19db, D6: the redirection was looked for in the whole loop text)."""
    pieces, tail = _compound_parts(seg)
    if _STDOUT_AWAY.search(_QUOTED.sub("", tail)):
        return True
    for p in pieces:
        if _COMPOUND.match(p):
            if _compound_stdout_away(p):
                return True
        elif not _is_reader(_strip_assigns(_words(p))) and _STDOUT_AWAY.search(_QUOTED.sub("", p)):
            return True
    return False

def _runner_pieces(seg):
    """The runners a segment runs: itself, or each runner piece of a compound's condition and body, nested compounds included."""
    if _COMPOUND.match(seg):
        return [q for p in _compound_parts(seg)[0] for q in _runner_pieces(p)]
    return [seg] if _segment_is_runner(seg) else []

def _away(seg):
    """The run sends its stdout to a file (a loop or if: any of its runs, _compound_stdout_away), so no summary in the result is its own:
    `pytest > log; echo "5 passed"`, `pytest a > log; pytest b`, `pytest > log; bash tests/…/test_x.sh` read as green from another
    command's summary (2026-10-26 principal review round 2, B2). Its exit code still counts when bound (`echo "rc=$?"`) or when the tool's
    exit is its own (_exit_is_the_runs)."""
    if _COMPOUND.match(seg):
        return _compound_stdout_away(seg)
    # #427 E3: `Unity … -runTests -testResults <f>` ghi kết quả ra file như stdout ra file, và không xoá file đó lúc bắt đầu (Editor chết
    # trước khi ghi thì `; cat <f>` in XML của lần trước): chỉ XANH khi mã thoát được gắn (`&& cat <f>`, _exit_is_the_runs).
    return bool(_STDOUT_AWAY.search(_QUOTED.sub("", seg)) or _UNITY_RESULTS.search(_QUOTED.sub("", seg)))

_UNITY_RESULTS = re.compile(r"(?<![\w-])-testResults\b")

def _compound_masks(seg):
    """A run in the loop / if that may hide its result: not one simple command run as the command (`pytest $d | head -1`,
    `pytest $d 2>&1 | grep -c passed`), or followed by `||` (`pytest $d || true`); nested compounds by the same rule (2026-10-26 OCR
    review round 3, E1: a compound was spared the exit check of _exit_is_the_runs)."""
    seps = []
    pieces = _compound_parts(seg, seps)[0]
    for k, p in enumerate(pieces):
        if _COMPOUND.match(p):
            if _compound_masks(p):
                return True
        elif _segment_is_runner(p) and (not (_single_command(p) and _runs_as_command(p)) or seps[k:k + 1] == ["||"]):
            return True
    return False

_STATUS_ECHO = re.compile(r"\s*(?:echo|printf)\b")
_ZSH_PIPESTATUS = re.compile(r"\$\{?pipestatus\b")      # zsh's ${pipestatus[1]}; _STATUS_READ (bash) is left as it is
# A pipe stage that passes the run's last lines on unchanged: `tail`, `tail -N`, `tail -n N` (N >= 1), `tee [-a] FILE…`, `cat`.
_KEEPS_TAIL = re.compile(r"\s*(?:tail(?:\s+(?:-n\s*|-)[1-9]\d*)?|tee(?:\s+-a)?(?:\s+[^\s|;&]+)*|cat)\s*")

def _cuts_summary(seg):
    """The run's own last lines (its summary) may not reach the result: it is not one simple command, and it is sent to the background
    or piped through a stage other than _KEEPS_TAIL (`| grep -c FAILED`, `| head -1`, `| tail -0`)."""
    if _single_command(seg):
        return False
    body = re.sub(r"\d*>&\d+|&>>?\s*\S+|\d?>>?\s*\S+", " ", _QUOTED.sub("", seg))     # redirections out, quoted text out
    return (bool(re.search(r"[;&\n]", body)) or not all(_KEEPS_TAIL.fullmatch(x) for x in body.split("|")[1:])
            or bool(_tail_cut(seg)))      # #427 item 8: `tail -N` của mocha / node --test / go test không giữ kết luận

def _hides(segs, i):
    """Runner segment i printed no summary of its own into the result: its stdout went to a file (_away), or its summary may have been
    cut (_cuts_summary; in a loop / if: one of its runs) and a later segment that is not the echo of an exit code may have printed one
    (2026-10-26 OCR review round 3, E2: `pytest a 2>&1 | grep -c FAILED; pytest b`, `pytest | tail -0; echo "5 passed"`). A run piped
    only through `tail -N` / `tee` / `cat` shows its own summary, so `pytest 2>&1 | tail -3 && git status` stays readable (final OCR
    review: 12 of 60 real runner commands were blocked)."""
    s = segs[i]
    if _away(s):
        return True
    cut = any(_cuts_summary(p) for p in _runner_pieces(s)) if _COMPOUND.match(s) else _cuts_summary(s)
    piped = (any(not _single_command(p) for p in _runner_pieces(s)) if _COMPOUND.match(s) else not _single_command(s))
    # Uncut pipe: any later segment that is not a runner and carries a pass word stands in for it (`mocha | tail -3; echo / print /
    # python -c … "12 passing"`, `&& git commit -am "… 12 passing"`: git prints the subject). Another runner after it prints its own
    # summary (`a | tail -3; b | tail -3`: 18 of 40 real kit commands were blocked); `git commit -q` prints nothing.
    # #427 item 9: một segment im lặng (_silent: ghi ra file, /dev/null, `gh pr comment`) không đứng thay được; `git log` / `git show` sau
    # một commit trong cùng lệnh mà message có chữ pass in lại subject đó nên đứng thay, kể cả khi commit là `-q`. Khi tóm tắt bị cắt (cut)
    # mọi segment sau vẫn tính.
    later = segs[i + 1:]
    return piped and any(not (_STATUS_ECHO.match(t) and (_STATUS_READ.search(t) or _ZSH_PIPESTATUS.search(t)))
                         and (cut or (not _silent(t)
                                      and ((_PRINTS_LOG.match(_QUOTED.sub('', t))
                                            and any(_GIT_COMMIT.match(_QUOTED.sub('', u)) and (RUNNER_PASS_RX.search(u) or NODE_PASS_RX.search(u)
                                                                                               or DEVKIT_SUITE_GREEN.search(u))
                                                    for u in later[:k]))
                                           or ((RUNNER_PASS_RX.search(t) or NODE_PASS_RX.search(t)) and not _segment_is_runner(t)
                                               and not _QUIET_COMMIT.match(_QUOTED.sub('', t))))))
                         for k, t in enumerate(later))

def _exit_is_the_runs(cmd, segs, res):
    """The tool's exit code is the runs' own: every runner segment is one simple command run as the command (no pipe, `&`, `!`, or a
    wrapper that only names it), only `&&` follows the first of them, and no `||` stands right before it (`true || pytest` may skip it).
    Else `pytest > log || true`, `pytest > log; echo done`, `pytest | head -1`, `pytest > log &`, `! pytest`, `pytest > log` then a
    second line read as green with no failure marker in sight (2026-10-26 OCR review round 2, P1-1)."""
    if not res:
        return False
    seps = _seps(cmd)
    first = res[0][0]
    return (all(_single_command(segs[i]) and _runs_as_command(segs[i]) for i, _ in res)
            and all(s == "&&" for s in seps[first:]) and (first == 0 or seps[first - 1] != "||")
            and not _exit_trapped(cmd))          # #427 E4

def _seps(cmd):
    seps = []
    _split_segments(_expand_vars(cmd, _env_for(cmd)), seps)
    return seps

def _own_exit(cmd, segs, i, seps):
    """Mã thoát của tool mang được lỗi của runner segment i (#427 R1 / P1-4): một lệnh đơn chạy runner như lệnh của nó, sau nó chỉ `&&`,
    ngay trước nó không là `||`, không có trap EXIT. Còn lại (`pytest || true; bash kit`, `bash x; bash y`, `x | tail -3`) là bị che."""
    return (_single_command(segs[i]) and (_runs_as_command(segs[i]) or _direct_bash_kit(segs[i])) and all(s == "&&" for s in seps[i:])
            and (i == 0 or seps[i - 1] != "||") and not _exit_trapped(cmd))

_FOR_LIST = re.compile(r"\s*for\s+[A-Za-z_]\w*\s+in\s+([^;\n]*?)\s*[;\n]\s*do\b")
# Dòng tóm tắt của một suite kit khi đếm (#427 P1-4), ngoài DEVKIT_SUITE_GREEN: "uninstall: 9 passed, 0 failed", "PASS test_x", "ALL PASS",
# "ALL OK", "pass=5 fail=0", "✅ test_x: passed", "test_x: PASS". Không phải dòng của từng ca: "ok: …", "✅ ca 1", "OK", "PASS: ca 1".
# Chỉ để đếm, không là xanh.
_KIT_SUMMARY_EXTRA = re.compile(r"^[\w ./-]+:[^\S\n]+[1-9]\d*[^\S\n]+(?:passed|ok),[^\S\n]+0[^\S\n]+(?:failed|deviating)\b"
                                r"|^[^\S\n]*ALL[^\S\n]+(?:PASS(?:ED)?|OK)\b|^[^\S\n]*PASS[^\S\n]+test[\w.-]*[^\S\n]*$|\bpass=[1-9]\d*[^\S\n]+fail=0\b"
                                r"|^[^\S\n]*✅[^\n]*:[^\S\n]+passed\b|:[^\S\n]+PASS(?:ED)?[^\S\n]*$", re.M)
_PS_LABEL = re.compile(r"([A-Za-z_][\w.-]*)=\$\{(?:PIPESTATUS\[0\]|pipestatus\[1\])\}")

def _runs_kit_file(seg):
    """Segment chạy CHÍNH một file suite kit (`bash tests/a/test_x.sh 2>&1 | tail -3`, `./tests/a/test_x.sh`, `agent-kit test`), hay là vòng
    lặp: thứ in ra dòng tóm tắt kit của riêng nó. Script trợ giúp nhận đường dẫn test làm đối số (`python3 patch.py tests/…/test_x.sh`,
    `bash $S/run.sh tests/…`) thì không: không đòi nó một dòng tóm tắt. ponytail: script trợ giúp chết im lặng vẫn mượn được tóm tắt của
    suite kit khác; muốn chặt thì phải biết script đó chạy gì."""
    if _COMPOUND.match(seg):
        return True
    head = _pipe_head(seg)
    words = _strip_assigns(_words(re.sub(r"^\s*time(?:\s+-p)?\s+", "", head if head is not None else seg)))
    if words[:2] == ["agent-kit", "test"] or (words and DEVKIT_SUITE_RX.search(words[0])):
        return True
    for k, w in enumerate(words):
        if _argv0(w) in ("bash", "sh", "zsh") and not _bash_runs_command_string(words[k:]):
            script = next((x for x in words[k + 1:] if not x.startswith(("-", "+"))), "")
            return bool(DEVKIT_SUITE_RX.search(script))
    return False

def _kit_count(seg):
    """Số dòng tóm tắt kit mà segment kit nợ kết quả (#427 P1-4): 1; vòng `for t in a b c; do … done` với danh sách chữ trơn thì một dòng
    cho mỗi chữ × mỗi lần chạy kit trong thân. ponytail: glob, $VAR, $( ), while / until / if / case không biết số vòng nên tính 1; muốn
    chặt hơn thì phải đếm file khớp glob trên đĩa."""
    if not _COMPOUND.match(seg):
        return 1
    m = _FOR_LIST.match(seg)
    if not m or not m.group(1).strip() or re.search(r"[*?\[$`{(]", m.group(1)):
        return 1
    body = sum(_kit_count(p) for p in _compound_parts(seg)[0] if _is_suite_seg(p) and _runs_kit_file(p))
    return len(_words(m.group(1))) * max(1, body)

def _label_code(m, txt, segs, ran=False):
    """0 / 1 (không 0) / None: dòng `<label>=N` của echo m in ra đúng một lần, và chỉ một echo của lệnh in nhãn đó ở đầu dòng (#427: hai
    `echo "exit=…"`, một in mã của lệnh khác, một in rỗng vì `${PIPESTATUS[0]}` của zsh, đã gắn nhầm mã). ran: mã 126 / 127 (lệnh không
    chạy được, `timeout: command not found`) không phải mã của runner: None."""
    if not m or sum(len(re.findall(r"\b(?:echo|printf)\s+[\"']?" + re.escape(m.group(2)) + r"=", s)) for s in segs) != 1:
        return None
    hits = re.findall(r"(?m)^[^\S\n]*" + re.escape(m.group(2)) + r"=(\d+)\s*$", txt)
    # Zero or not, read as text: int() of a 5 000-digit `rc=111…` raised past Python's 4 300-digit limit and ended the transcript
    # scan (2026-10-26 review of 9c1a3cb3, P3a). Only 0 / not 0 is used.
    if len(hits) != 1 or (ran and hits[0].lstrip("0") in ("126", "127")):
        return None
    return 0 if hits[0].strip("0") == "" else 1

def _ps_zero(segs, i, txt):
    """Segment i là pipe của một runner chạy như lệnh, segment sau in `<label>=${PIPESTATUS[0]}` = 0 (#427 item 8)."""
    head = _pipe_head(segs[i])
    return (i + 1 < len(segs) and head is not None and _runs_as_command(head)
            and _label_code(_ECHO_PS_RX.match(segs[i + 1]), txt, segs) == 0)

def _echoed_codes(cmd, txt, binds):
    """(segments, [(i, code)]) for each runner segment i: the exit code its next segment `echo "<label>=$?"` printed when it binds, else
    None. binds(seg): may this runner segment be bound at all. #427: a non-zero code of `echo "<label>=${PIPESTATUS[0]}"` (the pipe's first
    stage) or of a bare `echo $?` that ends the command binds too, as red only."""
    segs = _command_segments(cmd)
    out = []
    for i, seg in enumerate(segs):
        if not _segment_is_runner(seg):
            continue
        nxt = segs[i + 1] if i + 1 < len(segs) else None
        code = None
        if nxt is not None and _single_command(seg) and binds(seg):
            code = _label_code(_ECHO_RC_RX.match(nxt), txt, segs)
            if code is None and i + 2 == len(segs) and _BARE_ECHO_RC.match(nxt):
                last = next((l.strip() for l in reversed(txt.splitlines()) if l.strip()), "")
                code = 1 if re.fullmatch(r"[0-9]*[1-9][0-9]*", last) and last.lstrip("0") not in ("126", "127") else None
        if code is None and nxt is not None:
            head = _pipe_head(seg)
            if head is not None and _single_command(head) and binds(head) and _label_code(_ECHO_PS_RX.match(nxt), txt, segs, ran=True) == 1:
                code = 1
        out.append((i, code))
    return segs, out

def _echoed_verdict(res):
    """"red" when a bound code is not 0, "green" when EVERY runner segment is bound to 0, else None."""
    if any(c not in (None, 0) for _, c in res):
        return "red"
    return "green" if res and all(c == 0 for _, c in res) else None

def _suite_binds(seg):
    """In a kit-suite command: a kit segment binds only as a direct `bash|sh <kit test file>` run (2026-10-25 review of af339645, P1:
    `bash -n`, `shellcheck`, `[ -f … ]`, `chmod +x`, `bash -c "…"`, `eval`, `! bash …` name a test file and run no test, so their rc=0 is no
    green, their rc=1 no RED); any other runner binds as the command of its segment (_runs_as_command)."""
    return _direct_bash_kit(seg) if _is_suite_seg(seg) else _runs_as_command(seg)

def runner_state(is_error, txt, pm_run=False, command=""):
    """"red", "green", "gate-green" (the DevKit gate: a green for checks 2 and 7, not for auto_link), or None (not a verdict) for one runner tool_result."""
    if command and _command_invokes_gate(command):
        clean = ANSI_RX.sub("", txt)
        verdicts, counts = GATE_VERDICT_RX.findall(clean), GATE_COUNT_RX.findall(clean)
        if (not is_error and verdicts and all(v == "PASS" for v in verdicts)
                and counts and all(a == b for a, b in counts)):
            return "gate-green"
        return None
    if command and _command_is_suite(command):
        trapped = _exit_trapped(command)
        if (is_error and not trapped) or DEVKIT_SUITE_RED.search(txt):
            return "red"
        if is_error:
            return None          # #427 E4: lỗi của tool là của trap, không là ĐỎ của test, càng không là XANH
        segs, res = _echoed_codes(command, txt, _suite_binds)
        echoed = _echoed_verdict(res)
        if echoed:
            return echoed
        if any(c is None and _hides(segs, i) for i, c in res) and not _exit_is_the_runs(command, segs, res):
            return None          # B2: a run (kit or not) whose output went to a file; the summary in the result is another run's
                                 # (`bash tests/…/test_x.sh > log && tail log`: the tool's exit is the run's, the tail its own log)
        seps = _seps(command)
        # R3 (#427): runner không phải kit in lỗi ra kết quả (`FAILED tests/…`, `--- FAIL`, `panicked`): dòng 'all passed' của kit ở
        # segment khác không gỡ được lỗi đó. Chỉ đọc các dòng không phải của kit, và chỉ khi lệnh có runner không phải kit.
        if any(not _is_suite_seg(segs[i]) for i, _ in res) and RUNNER_FAIL_RX.search(_not_kit_lines(txt)):
            return None
        # Another runner of the command that hides its result (`bash tests/…/test_x.sh; pytest > log; echo $?`): the kit summary
        # says nothing of it, only its own pass summary can, on a line that is not the kit's ("uninstall: 9 passed, 0 failed" and a
        # check line "✔ … 5 passed …" are the kit's: 2026-10-26 review of 9c1a3cb3, P1); and the kit part needs its own summary.
        # R1 (#427): cả runner mà mã thoát của tool không mang (`pytest -q || true; bash kit`, `pytest; bash kit`) cũng cần tóm tắt riêng.
        hidden = [i for i, c in res if c is None and not _is_suite_seg(segs[i])
                  and (_hidden(segs, i, txt) or not _own_exit(command, segs, i, seps))]
        # P1-4 (#427): một suite kit bị che (không cuối, sau nó `;` / `||`, qua pipe, trong vòng lặp) mượn được 'all passed' của suite khác
        # (`bash x; bash y` khi x chết im lặng). Khi có suite bị che, mỗi lần chạy kit chưa gắn mã (trừ cái đẩy stdout ra file) phải có
        # dòng tóm tắt của riêng nó, hoặc dòng `<nhãn>=${PIPESTATUS[0]}` = 0 của chính nó: đếm dòng (lấy số lớn hơn của hai loại, không
        # cộng: một lần chạy in cả hai không được che cho lần chạy khác). Một mã khác 0 như vậy là không xanh.
        kits = [i for i, c in res if c is None and _is_suite_seg(segs[i]) and _runs_kit_file(segs[i])]
        if any(not _own_exit(command, segs, i, seps) for i in kits):
            need = sum(_kit_count(segs[i]) for i in kits if not _away(segs[i]))
            labels = {lab for i in kits for lab in _PS_LABEL.findall(segs[i] + "\n" + (segs[i + 1] if i + 1 < len(segs) else ""))}
            codes = [c for lab in labels for c in re.findall(r"(?m)(?:^|\s)" + re.escape(lab) + r"=(\d+)(?!\S)", txt)]
            if any(c.strip("0") for c in codes):
                return None
            lines = txt.splitlines()
            summaries = sum(1 for line in lines if DEVKIT_SUITE_GREEN.search(line) or _KIT_SUMMARY_EXTRA.search(line))
            if max(summaries, len(codes)) < need:
                return None
        if hidden:
            return "green" if (DEVKIT_SUITE_GREEN.search(txt) and _pass_summary(_not_kit_lines(txt), segs, hidden)) else None
        if DEVKIT_SUITE_GREEN.search(txt):
            return "green"
        # Exit 0 của tool là xanh khi bash/sh chạy thẳng file kit, dù không có "all passed".
        # A kit test that exits 0 on its skip path ("skip: no scripts here") or prints nothing checked nothing (OCR 24/10): empty output, or output
        # whose every line is a `skip` line, is no run. Any other output counts, whatever its summary style (✔, `ok: …`, `pass=5 fail=0`, `ALL OK`:
        # 21 kit tests print none of ✔ / "all passed"), and a run with a skipped optional case among passes is still a run.
        if not is_error and _command_is_direct_bash_kit(command):
            clean = ANSI_RX.sub("", txt)
            lines = [l for l in clean.splitlines() if l.strip()]
            # Its own failure SUMMARY is a RED verdict (the RED of a RED→GREEN pair; `None` would drop it): `pass=2 fail=1`, a line that STARTS with
            # `failed: 3` / `errors=2`, a TAP `not ok` (indented too), an uppercase FAIL line. Anchored on purpose (OCR R1/R5): a passing test may print
            # `Error: 401 key rejected` (singular, a diagnostic), `ok: linter reports errors=2 on bad fixture`, or echo another tool's `ERROR: x`.
            if re.search(r"(?i:^[^\S\n]*(?:[#ℹ*•-]\s*)?(?:fail(?:ed|ures?|ing)?|errors)\s*[:=]\s*[1-9]\d*\b)"
                         r"|(?i:\bpass(?:ed)?\s*[:=]\s*\d+\s+fail(?:ed|ures?)?\s*[:=]\s*[1-9]\d*\b)"
                         r"|^[^\S\n]*FAIL(?:ED)?\b|(?i:^[^\S\n]*not ok\b)", clean, re.M):
                return "red"
            if lines and not all(re.match(r"\s*skip(?:ped|ping)?\b", l, re.I) for l in lines):
                return "green"
        return None
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
    segs, res = _echoed_codes(command, txt, _runs_as_command) if command else ([], [])
    compound = any(_COMPOUND.match(segs[i]) for i, _ in res)
    trapped = bool(command) and _exit_trapped(command)     # #427 E4: mã thoát của tool là của trap, không tin theo chiều nào
    masked = (trapped or any(_hidden(segs, i, txt) for i, _ in res) or (not compound and not _exit_is_the_runs(command, segs, res))
              or any(_compound_masks(segs[i]) for i, _ in res if _COMPOUND.match(segs[i])))
    if (is_error and not trapped) or RUNNER_FAIL_RX.search(txt) or ((compound or masked) and DEVKIT_SUITE_RED.search(txt)):
        return "red"
    if is_error:
        return None              # #427 E4: như nhánh suite kit
    if masked:
        # 2026-10-25 fail-opens: `python3 -m pytest > log 2>&1; echo "rc=$?"` printing rc=1, and a glob loop `for f in tests/a/test_*.sh;
        # do bash "$f" > /dev/null; done`, read as green (no failure marker in the result). A bound non-zero code is red; green needs every
        # runner bound to 0, or a pass summary in the result. Also masked: a run whose exit is not the tool's (_exit_is_the_runs).
        echoed = _echoed_verdict(res)
        if echoed:
            return echoed
        unbound = [i for i, c in res if c is None]
        if any(_hides(segs, i) for i in unbound) or _late_blocks(txt, segs, unbound):
            return None          # B2 / E2: its summary went to a file or a pipe, what the result holds is another command's
        return "green" if (_pass_summary(txt, segs, unbound) or DEVKIT_SUITE_GREEN.search(txt)) else None
    return "green"
SRC_EXT = (".kt", ".kts", ".java", ".swift", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".py",
           ".go", ".rs", ".dart", ".cs", ".c", ".cc", ".cpp", ".h", ".hpp", ".m", ".mm")
# A file the session wrote in a TEMP dir that is not the project itself (the scratchpad the harness tells every agent to use, /tmp,
# $TMPDIR) is a helper, not the code a test claim is about: it must not age a green run or ask for its RED-check. Measured 2026-10-10 over
# 1227 real transcripts: 62 of 171 blocks of this gate came right after the last source file written lay in such a dir. A project that
# itself sits under a temp dir (every test project) keeps counting: the project root is checked first.
# Only absolute roots count (a relative TMPDIR is the directory the hook happens to run in). A root of "/" becomes "//" below and matches no path.
_TMP_ROOTS = tuple(sorted({os.path.realpath(d) + os.sep for d in
                           ("/tmp", "/var/tmp", "/dev/shm", tempfile.gettempdir(), os.environ.get("TMPDIR") or "/tmp")
                           if d and os.path.isabs(d)}))
_REPO_REAL = os.path.realpath(repo) + os.sep


def _is_scratch(path):
    try:
        rp = os.path.realpath(path)
    except (OSError, ValueError):
        return False
    return rp.startswith(_TMP_ROOTS) and not rp.startswith(_REPO_REAL)


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
def is_test_path(fp):
    return bool(SCRIPT_TEST_RX.search(fp) or SCRIPT_TEST_DIR_RX.search(fp)
                or "/src/test/" in fp or "/src/androidTest/" in fp or re.search(r"/Tests?/.*\.cs$|Tests?\.cs$", fp))

# #427 R4: `[\w./-]+\.(test|spec)…` không neo, nên từ MỖI vị trí của một dải `a/a/a/…` 200 KB nó chạy tới cuối dải: bậc hai, hook bị giết
# sau 60 s = cho qua. Chỉ dùng search() (có hay không), nên lookbehind một ký tự là tương đương và tuyến tính. Không cắt input: thiếu một
# lần khớp làm `not TEST_FILE_IN_OUTPUT.search(…)` đúng, nới RED-check.
TEST_FILE_IN_OUTPUT = re.compile(
    r"(?<=[\w./-])\.(test|spec)\.(m|c)?[jt]sx?\b|\btest_\w+\.py\b|\b\w+_test\.(go|py|dart)\b|\b\w+Tests?\.swift\b")
script_test_idx = {}      # test file path -> transcript position of its last edit
script_pending = {}       # test file path -> LIFO of (old, new) edits not yet undone
script_idx_before = {}    # test file path -> [script_test_idx before each edit]
last_src_edit_idx = -1
last_scratch_src_idx = -1   # the last source file written in a temp dir: the fallback marker of CHECK 7 when no source edit is in the project
# Chỉ CHECK 7 dùng (issue #4): hai marker trên nhưng bỏ qua file test, để sửa file test sau cặp RED→GREEN không làm mất cặp.
# Check 2 vẫn dùng last_src_edit_idx: claim "test pass" vẫn cần một lần chạy sau lần sửa file test cuối.
last_fix_edit_idx = -1
last_scratch_fix_idx = -1
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
# #427 R4: thuộc tính của một thẻ không chứa `<` (XML cấm) và có trần 2 000 ký tự: `[^>\n]*` từ mỗi `<testsuite` của một dòng 200 KB
# `<testsuite <testsuite …` (hay một thẻ hàng nghìn `name="…"`) chạy tới cuối dòng, bậc hai (22-28 s CPU đo 26/10). Thẻ thật ngắn hơn
# nhiều; thẻ dài hơn chỉ không được tính là ĐỎ ở đây, RED-check chặt hơn.
RED_XML = re.compile(r'<testsuite[^<>\n]{0,2000}name="([^"\n]+)"[^<>\n]{0,2000}(?:failures|errors)="([1-9]\d*)"')
RED_XML2 = re.compile(r'<testsuite[^<>\n]{0,2000}(?:failures|errors)="([1-9]\d*)"[^<>\n]{0,2000}name="([^"\n]+)"')
# Gradle prints "<Class> > <test name> FAILED"; a test name may be long (Vietnamese, backticks),
# so after " > " the gap runs to the end of the line (GeelyEx2 2026-09-26: a 90-char name was missed).
# #427 R4: tên lớp chỉ bắt đầu ở đầu một dải [\w.] (`(?<![\w.])`): không neo thì mọi vị trí trong một dải 200 KB đều thử lại cả dải (bậc
# hai). Mỗi lần khớp đứng trước FAILED trên cùng dòng, nên chỉ đọc dòng có FAILED, cắt sau chữ FAILED cuối (red_gradle_lines): ` > [^\n]*?`
# của mỗi ứng viên luôn gặp một FAILED, không quét tới cuối một dòng dài vô ích. Thiếu một lần khớp chỉ làm RED-check chặt hơn.
RED_GRADLE = re.compile(r'(?<![\w.])([\w.]*\b\w*Test)\b(?: > [^\n]*?|[^\n]{0,80}?)\bFAILED\b')
_FAILED_WORD = re.compile(r"\bFAILED\b")

def red_gradle_lines(txt):
    for line in txt.splitlines():
        if "FAILED" not in line:
            continue
        last = None
        for last in _FAILED_WORD.finditer(line):
            pass
        if last is not None:
            yield from RED_GRADLE.finditer(line, 0, last.end())

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

# A call a hook, the permission system or the worktree isolation REFUSED never ran: it is no red and no green, so never the RED half of
# check 7's pair (2026-10-25 audit: such results were recorded as RED runs, a fail-open). The pattern of hooks/security_gate.sh
# (NOT_RUN_RX, anchored: a command's own failing output starts "Exit code N"), plus the subagent wording "This agent is isolated …".
NOT_RUN_RX = re.compile(r"(PreToolUse:\S+ hook error|Permission to use \S[\s\S]*? has been denied"
                        r"|Permission for this action was denied by the Claude Code auto mode classifier"
                        r"|This (?:session|agent) is isolated in the worktree [^\n]* Refusing to run it)")

tp = d.get("transcript_path")
if tp and os.path.exists(tp):
    try:
        with open(tp) as fh:
            for lineno, rawline in enumerate(fh, 1):
                rawline = rawline.strip()
                if not rawline:
                    continue
                try:
                    rec = json.loads(rawline)
                except Exception:
                    continue
                if first_ts is None and isinstance(rec.get("timestamp"), str):
                    first_ts = rec["timestamp"]
                content = (rec.get("message") or {}).get("content")
                if not isinstance(content, list):
                    continue
                for blk in content:
                    if not isinstance(blk, dict):
                        continue
                    blk_idx += 1
                    try:
                        if blk.get("type") == "tool_use" and blk.get("name") == "Bash" \
                                and isinstance(blk.get("input"), dict):
                            bash_cmds.append(str(blk["input"].get("command", "")))
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
                            if blk.get("is_error") is True and NOT_RUN_RX.match(txt.lstrip()):
                                pass    # refused: never ran (NOT_RUN_RX)
                            elif (use and use["name"] == "Bash"
                                    and is_test_runner(str(use["input"].get("command", "")))):
                                cmd = str(use["input"].get("command", ""))
                                st = runner_state(blk.get("is_error") is True, txt, command=cmd)
                                if st:
                                    runner_results.append((blk_idx, use["index"], blk.get("is_error") is True, txt, cmd, st))
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
                            for m in red_gradle_lines(txt):      # #427 R4: chỉ dòng có FAILED, tuyến tính
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
                        if isinstance(fp, str) and fp and _is_scratch(fp):
                            if fp.endswith(SRC_EXT):
                                last_scratch_src_idx = blk_idx
                                if not is_test_path(fp):
                                    last_scratch_fix_idx = blk_idx
                            continue
                        if isinstance(fp, str) and fp:
                            edit_log.append((blk_idx, fp))
                        if isinstance(fp, str) and fp.endswith(SRC_EXT):
                            last_src_edit_idx = blk_idx
                            if not is_test_path(fp):
                                last_fix_edit_idx = blk_idx
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
                        # One block the scan cannot read is skipped and logged, never the rest of the transcript (2026-10-26 review of
                        # 9c1a3cb3, P3a: an exception here ended the scan, so a later edit was never seen and an older green backed the
                        # claim). Per block, not per line: one record carries parallel tool calls. A skipped edit call still counts as a
                        # source edit (fail-closed).
                        logline(f"[{ts}] transcript line {lineno} block {blk_idx} skipped ({blk.get('type')} "
                                f"{blk.get('name') or blk.get('tool_use_id') or ''}): {e!r}")
                        if blk.get("type") == "tool_use" and blk.get("name") in ("Edit", "Write", "NotebookEdit"):
                            last_src_edit_idx = last_fix_edit_idx = blk_idx
    except Exception as e:
        logline(f"[{ts}] transcript scan fail: {e!r}")

# Whose test run produced this XML? build/ is shared: another agent's red suite lands in the
# same tree and used to be counted as one of OUR failed fixes (OfficeReader, 2026-09-10: four
# accusations over suites this session never ran). A run sits inside the Bash window of the
# session that ran it (.claude/audit-gate/bash_write_ledger.tsv, written by
# hooks/bash_write_ledger.sh: session \t start|end \t <ts> \t <tool_use_id>); the narrowest
# containing window wins. Fail-closed: no ledger, no containing window, or a tie between
# sessions → ours. A background command (start, no end) stays open until now. Audit G5.
LEDGER_REL = os.path.join(".claude", "audit-gate", "bash_write_ledger.tsv")

def _load_windows(path=None):
    path = path or os.path.join(ledger_root, LEDGER_REL)
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

_WINDOWS = _load_windows()   # open windows reach now: the rule that CREDITS a window to this session (ran_in_my_window)
_MY_SID = str(d.get("session_id") or "")

def _authorship():
    """bin/session_authorship.py of this kit, or None."""
    me = os.environ.get("TE_SELF", "")
    if not me:
        return None
    try:
        sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(me))), "bin"))   # after the stdlib, never before it
        sys.dont_write_bytecode = True
        import session_authorship
        return session_authorship
    except Exception as e:   # anything, an import error included: the old rule stays in force, never "allow"
        logline(f"[{ts}] session_authorship unavailable ({e!r}): open windows reach now")
        return None

# Open windows of sessions that are gone are cut (bin/session_authorship.py: open_windows). They only ever
# decide "another session ran it" (ran_here, below, together with _WINDOWS: block_owner's rule); crediting
# a window to this session (ran_in_my_window, own and foreign ledger) keeps the old rule.
_SA = _authorship()
try:
    _WINDOWS_CUT = _SA.bash_windows(ledger_root, _MY_SID) if _SA is not None and _MY_SID else _WINDOWS
except Exception as e:   # a crash here would exit 1 and this hook then exits 0: fall back to the old rule instead
    logline(f"[{ts}] cut windows unavailable ({e!r}): the old rule decides")
    _WINDOWS_CUT = _WINDOWS

def _window_owner(mtime, windows=None):
    """Session of the narrowest ledger window containing mtime; None when none or a tie."""
    best_w, best_sid = None, None
    for st, en, sid_ in (_WINDOWS if windows is None else windows):
        if st <= mtime <= en:
            w = en - st
            if best_w is None or w < best_w:
                best_w, best_sid = w, sid_
            elif w == best_w and sid_ != best_sid:
                best_sid = None
    return best_sid

def ran_here(mtime):
    if not _WINDOWS or not _MY_SID:
        return True
    old = _window_owner(mtime)
    try:
        cut = _window_owner(mtime, _WINDOWS_CUT)
    except Exception:    # malformed windows from the module: the old rule decides
        cut = old
    # another session's run only when BOTH rules say so: a window cut narrower never takes the run from a wider window of mine
    return not (old is not None and cut is not None and old != _MY_SID and cut != _MY_SID)

_FOREIGN_LEDGERS = {}

def _foreign_windows(xml_path):
    """Windows of the ledger of the project holding xml_path (nearest ancestor with one); [] when
    there is none or it is this repo's own (already in _WINDOWS)."""
    own = os.path.realpath(os.path.join(ledger_root, LEDGER_REL))
    cur = os.path.dirname(os.path.abspath(xml_path))
    while True:
        cand = os.path.join(cur, LEDGER_REL)
        if os.path.isfile(cand):
            if os.path.realpath(cand) == own:
                return []
            if cand not in _FOREIGN_LEDGERS:
                _FOREIGN_LEDGERS[cand] = _load_windows(cand)
            return _FOREIGN_LEDGERS[cand]
        up = os.path.dirname(cur)
        if up == cur:
            return []
        cur = up

def ran_in_my_window(mtime, xml_path=None):
    """Foreign XML only, fail-CLOSED: the narrowest window holding the write is THIS session's.
    No ledger, no containing window, or a tie → not ours. A green XML another agent left in a
    project this session only `cat`ed is not our run (2026-09-25 review P3). The foreign project's
    own ledger counts too (2026-09-29): its sessions log their Bash windows there, so a long window
    of this session (a 10-min gate) no longer "owns" XML another session wrote in that project."""
    windows = _WINDOWS + (_foreign_windows(xml_path) if xml_path else [])
    return bool(_WINDOWS and _MY_SID) and _window_owner(mtime, windows) == _MY_SID

# ── XML this session produced in ANOTHER project ─────────────────────────────
# (2026-09-25) A session working on two projects ran/read the tests of the other one
# ("JUnit XML in /…/GeelyEx2/… shows 13/13, 0 failures") and was blocked: only this repo was
# globbed. A foreign root counts when one of THIS session's Bash commands names it — a path under
# <module>/build/test-results|outputs/androidTest-results/, a result XML itself, or a directory
# (or one of its 3 parents) holding a Gradle/Unity project, e.g. `cd /other && ./gradlew test`.
# The XML file on DISK is read, never XML printed in a tool result (an `echo` could forge that).
# It must have been written during this session: mtime ≥ the session's first transcript
# timestamp (else the transcript's birth time), and by this session's own Bash: the narrowest
# ledger window containing it is one of THIS session's (ran_in_my_window; no ledger → not ours).
# Only the check-2 evidence uses it; the 6.4 anti-loop state stays repo-only.
FOREIGN_SKIP = ("/dev/", "/usr/", "/bin/", "/sbin/", "/etc/", "/System/", "/Library/", "/opt/homebrew/", "/proc/")
ABS_PATH_RX = re.compile(r"(?<![\w.~$-])/[^\s'\"`;|&<>()$*?\[\]{}]+")
MODULE_XML = ("build/test-results/*/TEST-*.xml", "build/outputs/androidTest-results/connected/TEST-*.xml",
              "build/outputs/androidTest-results/connected/*/TEST-*.xml")
PROJECT_MARKERS = ("gradlew", "settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts",
                   "ProjectSettings/ProjectVersion.txt")

# Where a test command RUNS, not every path it mentions: the `cd`/`pushd` target, the value of -p / -C / --project-dir / --project / --prefix /
# --manifest-path / -projectPath / --cwd, the runner executable itself (…/gradlew, mvnw) and the script handed to an interpreter. A path that
# is only an argument of ls / cat / grep / a smoke script in the same command as a test run is no run there (2026-10-07: a command that ran the
# kit's suites and read the state of four repos made one of them "a project this session ran tests in", and its fresh XML, written by another
# agent, was credited to the session).
_RUN_PATH = r"""[\"']?(/[^\s\"'`;|&<>()$*?\[\]{}]+)"""
RUN_TARGET_RXS = (
    re.compile(r"(?:^|[\s;&|(])(?:cd|pushd)\s+" + _RUN_PATH),
    re.compile(r"(?:^|\s)(?:-p|-C|--project-dir|--project|--prefix|--manifest-path|-projectPath|--cwd)(?:=|\s+)" + _RUN_PATH),
    re.compile(r"(?<![\w.~$-])(/[^\s\"'`;|&<>()$*?\[\]{}]*/(?:gradlew|gradle|mvnw|mvn))(?![\w.-])"),
    re.compile(r"\b(?:bash|sh|zsh|python\d?(?:\.\d+)?|node|ruby)\s+" + _RUN_PATH),
)

def run_targets(cmd):
    out = []
    for rx in RUN_TARGET_RXS:
        for tok in rx.findall(cmd):
            tok = tok.rstrip("/.,:")
            if tok and not tok.startswith(FOREIGN_SKIP) and tok not in out:
                out.append(tok)
    return out

def _session_start():
    if first_ts:
        try:
            from datetime import datetime
            return datetime.fromisoformat(first_ts.replace("Z", "+00:00")).timestamp()
        except Exception:
            pass
    if tp and os.path.exists(tp):
        return getattr(os.stat(tp), "st_birthtime", None)
    return None

def _resolve_dir(tok, cwd):
    tok = (tok or "").strip().strip("\"'").rstrip("/.,:")
    if not tok or tok.startswith(FOREIGN_SKIP):
        return None
    if not os.path.isabs(tok):
        tok = os.path.normpath(os.path.join(cwd or repo, tok))
    else:
        tok = os.path.normpath(tok)
    return tok

def _note_project(tok, roots):
    if not tok or str(tok).startswith(FOREIGN_SKIP):
        return
    cur = tok if os.path.isdir(tok) else os.path.dirname(tok)
    for _ in range(4):
        if not cur or str(cur).startswith(FOREIGN_SKIP):
            return
        if any(os.path.exists(os.path.join(cur, m)) for m in PROJECT_MARKERS):
            roots.append(("project", cur))
            return
        up = os.path.dirname(cur)
        if up == cur:
            return
        cur = up

def foreign_xmls():
    start = _session_start()
    if start is None or not bash_cmds:
        return {}
    roots, files = [], set()
    for cmd in bash_cmds:
        for tok in ABS_PATH_RX.findall(cmd):
            tok = tok.rstrip("/.,:")
            if not tok or tok.startswith(FOREIGN_SKIP):
                continue
            for marker in ("/build/test-results", "/build/outputs/androidTest-results"):
                if marker in tok:
                    roots.append(("module", tok.split(marker)[0]))
            if re.search(r"(?:^|/)(?:TEST-[^/]*|tests_[^/]*)\.xml$", tok) and os.path.isfile(tok):
                files.add(tok)
        # Only the segment that runs the tests contributes a root. `git -C <other>` later in the
        # same command does not. A relative `cd` and a `$VAR` expand against this repo.
        cwd = repo
        for seg in _command_segments(cmd):
            words = _strip_assigns(_words(seg))
            if words and _argv0(words[0]) in ("cd", "pushd") and len(words) > 1 and not words[1].startswith("-"):
                dest = _resolve_dir(words[1], cwd)
                if dest:
                    cwd = dest
                continue
            if not _segment_is_runner(seg):
                continue
            noted = False
            for tok in run_targets(seg):
                dest = tok if os.path.isabs(tok) else _resolve_dir(tok, cwd)
                if dest:
                    _note_project(dest, roots)
                    noted = True
            if not noted:
                _note_project(cwd, roots)
    seen_roots = []
    for kind, root in roots:
        if (kind, root) not in seen_roots:
            seen_roots.append((kind, root))
    cands = set(files)
    for kind, root in seen_roots[:12]:
        for pat in (MODULE_XML if kind == "module" else XML_PATTERNS):
            cands.update(glob.glob(os.path.join(root, pat)))
    # Keyed by the path as the session wrote it (not realpath: /var vs /private/var on macOS), so
    # module_of() lines up with the module roots of this session's edits; deduped on realpath.
    seen = {os.path.realpath(p) for p in mtimes}
    out = {}
    for pth in sorted(cands):
        rp = os.path.realpath(pth)
        if rp in seen:
            continue
        seen.add(rp)
        try:
            mt = os.path.getmtime(pth)
        except OSError:
            continue
        if mt >= start and ran_in_my_window(mt, pth):
            out[pth] = mt
    return out

foreign = foreign_xmls() if claimed else {}
if foreign:
    logline(f"[{ts}] foreign XML from this session's Bash: {len(foreign)} file(s)")
    mtimes.update(foreign)
newest_claim = max(mtimes.values(), default=0.0)

# Anchor for "fresh". With no .kt/.java edited this session last_edit_mtime is 0,
# and then EVERY xml in the tree counts as fresh — including results from months
# ago. Measured 2026-07-27: the repo held 2 red suites from an earlier run, so any
# turn saying "test pass" without a Kotlin edit was blocked, and the message called
# a January file "tươi" — a gate blocking valid work AND naming the wrong cause.
# With no edit to anchor on, judge the LATEST run only, not the whole history.
RUN_WINDOW = 300.0
anchor = last_edit_mtime if last_edit_mtime else (newest_claim - RUN_WINDOW if newest_claim else 0.0)

# Parse only the suites a live question actually depends on.
need = set()
if claimed:
    need |= {p for p, mt in mtimes.items() if mt >= anchor}
if new_run:
    need |= {p for p, mt in mtimes.items() if mt > state.get("last_run", 0.0) and p not in foreign}
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
        if s["mtime"] > state.get("last_run", 0.0) and s["path"] not in foreign and ran_here(s["mtime"]):
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
        if s["mtime"] <= state.get("last_run", 0.0) or not s["name"] or s["path"] in foreign:
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
                 if r[1] > last_src_edit_idx and r[5] in ("green", "gate-green")]
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

    # Only whether ONE claim has no bound proof is used: a flag and a stop at the first, never a copy of each claim's clause (2026-10-26
    # review of 9c1a3cb3, P3b: 8 570 claims in one 60 KB clause made 8 570 stripped copies, 1.1 GB).
    unbound_claims = False
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
            unbound_claims = True
            break
    # Second accepted proof — the paired executable oracle AGENTS.md makes mandatory,
    # observed in this session's own tool results: a test run that FAILED before the
    # last source edit and one that PASSED after it. A green run alone (no red before
    # the fix) or prose in the message does not count.
    def paired_red_green():
        # The marker is the last source edit in the project; a session whose every source edit lay in a temp dir (a fix made in a stage copy
        # and installed after) is judged by the last of those, as before the temp-dir rule.
        # Issue #4: trong tầng đó (project, hay thư mục tạm khi project không có lần sửa source nào), marker là lần sửa source cuối
        # KHÔNG phải file test: sửa file test sau cặp RED→GREEN không làm mất cặp, và một lần ĐỎ chỉ xuất hiện sau bản sửa không được
        # tính. Tầng chỉ có sửa file test (test flaky, conftest) xét theo lần sửa đó như trước. Không xét thư mục tạm trước project:
        # một file probe .py trong scratchpad sẽ chiếm marker.
        tier = ((last_fix_edit_idx, last_src_edit_idx) if last_src_edit_idx >= 0
                else (last_scratch_fix_idx, last_scratch_src_idx))
        marker = next((m for m in tier if m >= 0), -1)
        if marker < 0:
            return False
        # Only a test RUNNER's own result counts as red: `cat` of an old TEST-*.xml
        # prints the same failure markup and must not stand in for a real run.
        red = any(r[1] < marker and r[5] == "red"
                  for r in runner_results)
        green = any(r[1] > marker and r[5] in ("green", "gate-green")
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
        items = {}   # (as in session_bug_rows)
    items = with_overlay(items)   # a linked worktree: the auto-link and the REPORTED rows its hooks kept in its own state
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
_linked_wt = []          # [bool]: this repo is a LINKED worktree (its tracked checklist files are not written)

def linked_worktree():
    if not _linked_wt:
        try:
            sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(os.environ.get("TE_SELF", "")))), "bin"))
            sys.dont_write_bytecode = True
            import regression_checklist as rc
            _linked_wt.append(bool(getattr(rc, "skip_bookkeeping", lambda p: False)(repo)))
        except Exception:  # noqa: BLE001 — unknown: write as before
            _linked_wt.append(False)
    return _linked_wt[0]

def with_overlay(items):
    """In a LINKED worktree the rows its hooks kept in the worktree's own state (an auto-link, a RED-proof, a REPORTED bug) join the
    tracked ones, so the reminders and the VACUOUS hold below behave as in the main checkout. Ở mọi checkout: cả các dòng REPORTED
    main trunk mode giữ ngoài git (regression_checklist.apply_pending), như load_view thấy."""
    linked = linked_worktree()   # (cũng đưa bin/ của kit vào sys.path)
    view = {"items": dict(items)}
    try:
        import regression_checklist as rc
    except Exception:  # noqa: BLE001 — no kit module: the tracked rows alone
        return items
    try:   # sổ chờ và overlay đọc riêng (như load_view): một cái hỏng không làm mất cái kia
        getattr(rc, "apply_pending", lambda _d, _p: None)(view, repo)
    except Exception:  # noqa: BLE001 — unreadable pending store: without it
        pass
    if linked:
        try:
            rc.apply_overlay(view, repo)
        except Exception:  # noqa: BLE001 — unreadable overlay: without it
            pass
    return view["items"]

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
            data = getattr(rc, "load_view", rc.load)(_P(repo))
            mf = _P(repo) / ".agents" / "regression_matrix.active.json"
            if mf.is_file():
                rc.sync_from_matrix(data, json.loads(mf.read_text(encoding="utf-8")))
            in_matrix, _ = rc.link_bug(data, unlinked[0], rel, project=_P(repo))
            data["items"][unlinked[0]]["linked_by"] = "auto"
            if linked_worktree():
                rc.overlay_save_rows(repo, data, [unlinked[0]])   # the worktree's own state, read back by with_overlay
            else:   # đúng dòng vừa link, không bao giờ cả sổ chờ của view (main trunk mode: vào sổ chờ, file track không đổi)
                getattr(rc, "save_view_rows", lambda p, dd, _ids: rc.save(p, dd))(_P(repo), data, [unlinked[0]])
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
        items = {}   # no tracked checklist (or unreadable): the worktree's own state and the pending store still count
    raw_sid = str(d.get("session_id") or "")
    items = with_overlay(items)
    return {bid: it for bid, it in items.items() if isinstance(it, dict) and it.get("kind") in ("bug", "req")
            and (bid in bugs_touched or (raw_sid and raw_sid in (it.get("sessions") or [])))}

def red_proof_actions():
    rows = session_bug_rows()
    if fix_proven and os.environ.get("RED_PROOF", "1") != "0":
        todo = [bid for bid, it in rows.items() if it.get("tests") and it.get("fixed") is not False
                and (it.get("red_proof") or {}).get("status") in (None, "PENDING", "OUTDATED")]
        _te_root = os.path.dirname(os.path.dirname(os.path.realpath(os.environ.get("TE_SELF", ""))))
        script = os.path.join(_te_root, "scripts", "testing", "red_proof.py")
        if not os.path.isfile(script):
            script = os.path.join(_te_root, "scripts", "red_proof.py")
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
# The same block again in this session (O4, 2026-09-28): the headers (they carry the requirement)
# and the items stay, the explanation is not repeated. Compared without time stamps.
import hashlib as _hl
_shown = os.path.join(state_dir, f"test_evidence_gate_shown_{_sid}")
_digest = _hl.sha256(re.sub(r"\d{8}-\d{6}|\d{2}:\d{2}:\d{2}", "#", "\n".join(out)).encode()).hexdigest()[:16]
try:
    _again = open(_shown).read().strip() == _digest
except OSError:
    _again = False
try:
    with open(_shown, "w") as _fh:
        _fh.write(_digest)
except OSError:
    pass
if _again:
    out = [l for l in out if l.startswith("⛔") or l.lstrip().startswith(("•", "- ", "python3 "))] + \
          ["(Như lần chặn trước trong phiên — phần giải thích không lặp lại.)"]
sys.stderr.write("\n".join(out) + "\n")
sys.exit(2)
PY
rc=$?
[ "${rc}" -eq 2 ] && exit 2
exit 0
