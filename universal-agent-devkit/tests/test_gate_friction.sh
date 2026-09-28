#!/usr/bin/env bash
# Regression (GeelyEx2 sessions 2026-09-27): gate findings that stopped a finished agent
# or pushed it to rewrite a correct test — the "agent asks the human for nothing" class.
#  1. assertion_lint: a test whose assertion sits in a same-file helper is not vacuous.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# ── 1. assertion in a helper ──────────────────────────────────────────────────
out="$(DK="$DEVKIT_DIR" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.path.join(os.environ["DK"], "scripts"))
import assertion_lint as al
kt = '''
class HoTroLaiTraLoiTest {
    private fun kiem(cau: String, mongDoi: String) {
        assertEquals(mongDoi, VoiceQueryAnswerer.traLoi(cau))
    }
    private fun kiemIm(cau: String) = kiem(cau, "")
    private fun khongLamGi(cau: String) { println(cau) }
    private fun viec(cau: String) { assertTrue(true) }

    @Test fun `esc bat`() { kiem("bật esc", "ESC đang bật") }
    @Test fun `esc im`() = kiemIm("tắt esc")
    @Test fun `khong assert`() { khongLamGi("x") }
    @Test fun `helper rong`() { viec("x") }
}
'''
lines = sorted(l for l, _ in al.findings(kt))
print(lines)
py = '''
def kiem(x, want):
    assert f(x) == want

def test_via_helper():
    kiem(1, 2)

def test_nothing():
    f(1)
'''
print(sorted(l for l, _ in al.findings(py)))
PY
)"
# Kotlin: only `khong assert` (line 12) and `helper rong` (line 13) are vacuous.
# Python: only test_nothing (line 8).
[ "$out" = "$(printf '[12, 13]\n[8]')" ] && ok "helper assertion counts; empty/vacuous helper does not" \
  || fail "assertion_lint helper: got $(echo "$out" | tr '\n' ' ')"

# The expected exception, fail(…) and Kotlin's assert(…) are assertions too (GeelyEx2 tree:
# QuickInstallPortTest, AcProgramStoreTest, HashUtilTest were called vacuous).
out="$(DK="$DEVKIT_DIR" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.path.join(os.environ["DK"], "scripts"))
import assertion_lint as al
kt = """
class T {
    @Test(expected = IllegalArgumentException::class)
    fun `link hong thi nem`() { DownloadLink.toDirect("x") }
    @Test fun `du lieu hong`() {
        runCatching { decode("x") }.onSuccess { fail("expected exception") }
    }
    @Test fun `hash khac`() { assert(a != b) }
    @Test fun `assert rong`() { assert(true) }
    @Test(timeout = 20_000) fun `chi timeout`() { chay() }
}
"""
print(sorted(l for l, _ in al.findings(kt)))
PY
)"
# Only `assert rong` (line 9) and `chi timeout` (line 10) stay vacuous.
[ "$out" = "[9, 10]" ] && ok "expected=, fail(), Kotlin assert() count as assertions" \
  || fail "assertion_lint expected/fail/assert: got $out"

# ── 2. git restore followed by a cd ──────────────────────────────────────────
# A `cd` AFTER the restore cannot change the paths the restore resolves; one BEFORE it can.
RD="$TMP/restore"; mkdir -p "$RD/sub"; git -C "$RD" init -q; echo a > "$RD/w.kt"
restore_rc() {
  ( cd "$RD" && python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" \
    | CLAUDE_PROJECT_DIR="$RD" bash "$DEVKIT_DIR/hooks/block-dangerous-git.sh" >/dev/null 2>&1 )
  echo $?
}
rc="$(restore_rc 'git diff --stat -- w.kt && git restore -- w.kt && cd sub && ls')"
[ "$rc" = 0 ] && ok "restore then cd: allowed (backup taken)" || fail "restore then cd blocked (rc=$rc)"
rc="$(restore_rc 'cd sub && git restore -- w.kt')"
[ "$rc" = 2 ] && ok "cd then restore: still blocked" || fail "cd then restore not blocked (rc=$rc)"

# ── 3. a plain script test is a test runner ──────────────────────────────────
# GeelyEx2 2026-09-27: a real RED→GREEN of `python3 tests/scripts/test-admin-….py` (a
# regression-matrix command) was not seen as a runner; CHECK 7 held the stop 7 times.
# $1 = project dir, $2 = test command, $3 = red run is_error
c7_case() {
  local proj="$1" cmd="$2" red_err="$3"
  python3 - "$proj" "$cmd" "$red_err" <<'PY'
import json, os, sys
proj, cmd, red_err = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
src = os.path.join(proj, "tools", "admin.py")
blocks = [
    {"type": "tool_use", "id": "r0", "name": "Bash", "input": {"command": cmd}},
    {"type": "tool_result", "tool_use_id": "r0", "is_error": red_err,
     "content": "ca 10: FAIL\nExit code 1" if red_err else "14/14 ca OK"},
    {"type": "tool_use", "id": "e1", "name": "Edit", "input": {"file_path": src, "old_string": "a", "new_string": "b"}},
    {"type": "tool_use", "id": "g1", "name": "Bash", "input": {"command": cmd}},
    {"type": "tool_result", "tool_use_id": "g1", "is_error": False, "content": "14/14 ca OK"},
]
with open(os.path.join(proj, "tr.jsonl"), "w") as fh:
    for b in blocks:
        fh.write(json.dumps({"message": {"content": [b]}}) + "\n")
PY
  printf '{"session_id":"c7-%s","transcript_path":"%s/tr.jsonl","last_assistant_message":"Đã fix nút Ép bản này: ca 10 hết lỗi."}' \
    "$RANDOM" "$proj" \
    | CLAUDE_PROJECT_DIR="$proj" LESSON_REMINDER=0 BUG_LINK_REMINDER=0 bash "$DEVKIT_DIR/hooks/test_evidence_gate.sh" >/dev/null 2>&1
  echo $?
}
P3="$TMP/c7"; mkdir -p "$P3/tools" "$P3/tests/scripts" "$P3/.agents"; echo a > "$P3/tools/admin.py"
rc="$(c7_case "$P3" "python3 tests/scripts/test-admin-force-update-behaviour.py" 1)"
[ "$rc" = 0 ] && ok "python3 tests/scripts/test-*.py RED→GREEN backs 'đã fix'" || fail "script test RED→GREEN not accepted (rc=$rc)"
# A matrix command whose script name has no "test" in it counts too (Gradle repo).
touch "$P3/gradlew"
printf '{"rules":[{"component":"A","watch_files":["tools/admin.py"],"mandatory_regression_tests":[{"id":"R","command":"STRICT_DEPS=1 python3 scripts/verify/check-admin.py"}]}]}' \
  > "$P3/.agents/regression_matrix.active.json"
rc="$(c7_case "$P3" "python3 scripts/verify/check-admin.py" 1)"
[ "$rc" = 0 ] && ok "regression-matrix command RED→GREEN backs 'đã fix' (Gradle repo)" || fail "matrix command not a runner (rc=$rc)"
# Control: no red before the fix -> still held.
rc="$(c7_case "$P3" "python3 tests/scripts/test-admin-force-update-behaviour.py" 0)"
[ "$rc" = 2 ] && ok "green-only script run: 'đã fix' still held" || fail "green-only accepted (rc=$rc)"

# ── 4. a redirected Gradle run that prints the XML summary is RED ─────────────
# GeelyEx2 2026-09-28: `./gradlew … > red.log; echo exit=$?; python3 <print xml>` printed
# `failures="5"` with is_error=False; RUNNER_FAIL_RX has no failures="N" form, so every real
# red counted GREEN — CHECK 7 held twice, and a failing run could pass as green.
# $1 = failures in the first run
xml_case() {
  local proj="$TMP/xml$1"; mkdir -p "$proj/src"; echo a > "$proj/src/Foo.kt"
  python3 - "$proj" "$1" <<'PY'
import json, os, sys
proj, n = sys.argv[1], sys.argv[2]
cmd = "cd app && ./gradlew :app:testDebugUnitTest --tests '*FooTest' > /tmp/x.log 2>&1; echo exit=$?; python3 xml.py"
xml = '<testsuite name="com.x.FooTest" tests="2" skipped="0" failures="%s" errors="0">'
blocks = [
    {"type": "tool_use", "id": "r0", "name": "Bash", "input": {"command": cmd}},
    {"type": "tool_result", "tool_use_id": "r0", "is_error": False,
     "content": ("exit=1\n" if n != "0" else "exit=0\n") + xml % n},
    {"type": "tool_use", "id": "e1", "name": "Edit",
     "input": {"file_path": os.path.join(proj, "src", "Foo.kt"), "old_string": "a", "new_string": "b"}},
    {"type": "tool_use", "id": "g1", "name": "Bash", "input": {"command": cmd}},
    {"type": "tool_result", "tool_use_id": "g1", "is_error": False, "content": "exit=0\n" + xml % "0"},
]
with open(os.path.join(proj, "tr.jsonl"), "w") as fh:
    for b in blocks:
        fh.write(json.dumps({"message": {"content": [b]}}) + "\n")
PY
  printf '{"session_id":"xml-%s","transcript_path":"%s/tr.jsonl","last_assistant_message":"Đã fix bug đăng nhập."}' "$1" "$proj" \
    | CLAUDE_PROJECT_DIR="$proj" LESSON_REMINDER=0 BUG_LINK_REMINDER=0 bash "$DEVKIT_DIR/hooks/test_evidence_gate.sh" >/dev/null 2>&1
  echo $?
}
rc="$(xml_case 1)"
[ "$rc" = 0 ] && ok "redirected Gradle run with failures=\"1\" counts as RED (paired RED→GREEN)" || fail "failures=\"1\" not red (rc=$rc)"
rc="$(xml_case 0)"
[ "$rc" = 2 ] && ok "failures=\"0\" first run: still no RED, claim held" || fail "failures=\"0\" read as red (rc=$rc)"

# ── 5. a worktree the host made itself is set up at session start ─────────────
# OfficeReader 2026-09-28: Grok opened its session in its own `git worktree` — no
# .agents/devkit (git-ignored link), no google-services.json. `post-fix-gate` did not exist,
# a core test failed on the missing config, and Grok linked both by hand.
M5="$TMP/main5"; mkdir -p "$M5/app" "$M5/.agents"; git -C "$M5" init -q
git -C "$M5" config user.email t@t; git -C "$M5" config user.name t
printf '.agents/devkit\napp/google-services.json\n' > "$M5/.gitignore"
echo '{}' > "$M5/app/google-services.json"; ln -s "$DEVKIT_DIR" "$M5/.agents/devkit"
echo x > "$M5/README.md"; git -C "$M5" add -A; git -C "$M5" commit -qm init
git -C "$M5" worktree add -q --detach "$TMP/wt5" 2>/dev/null
( cd "$TMP/wt5" && python3 "$DEVKIT_DIR/scripts/worktree.py" heal >/dev/null 2>&1 ); rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/wt5/.agents/devkit/bin/post-fix-gate.py" ] && [ -f "$TMP/wt5/app/google-services.json" ] \
  && [ -z "$(git -C "$TMP/wt5" status --porcelain)" ] \
  && ok "heal: DevKit link + ignored local config in a host-made worktree, nothing to commit" \
  || fail "heal (rc=$rc): devkit=$(ls "$TMP/wt5/.agents" 2>&1) config=$(ls "$TMP/wt5/app" 2>&1) status=$(git -C "$TMP/wt5" status --porcelain)"
( cd "$M5" && python3 "$DEVKIT_DIR/scripts/worktree.py" heal >/dev/null 2>&1 ); rc=$?
[ "$rc" = 0 ] && ok "heal in the main checkout: no-op, exit 0" || fail "heal in main checkout rc=$rc"
git -C "$M5" worktree add -q --detach "$TMP/wt6" 2>/dev/null
out="$(printf '{"session_id":"s6","hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$TMP/wt6" SESSION_FETCH=0 \
  bash "$DEVKIT_DIR/hooks/session_context.sh" 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/wt6/.agents/devkit/bin/post-fix-gate.py" ] && printf '%s' "$out" | grep -q 'worktree' \
  && ok "SessionStart in a host-made worktree sets it up and says so" \
  || fail "session_context heal (rc=$rc): $(ls "$TMP/wt6/.agents" 2>&1) | $(printf '%s' "$out" | head -3)"
# Grok's "worktree" is really a separate clone (own .git) — `git worktree list` does not know
# its source. The source comes from Grok's session summary (source_workspace_dir); the DevKit
# link from the running hook itself.
git clone -q "$M5" "$TMP/clone7" 2>/dev/null
GH="$TMP/home7"; mkdir -p "$GH/.grok/sessions/x/s7"
printf '{"source_workspace_dir": "%s"}' "$M5" > "$GH/.grok/sessions/x/s7/summary.json"
out="$(printf '{"session_id":"s7","hook_event_name":"SessionStart"}' | HOME="$GH" CLAUDE_PROJECT_DIR="$TMP/clone7" SESSION_FETCH=0 \
  bash "$DEVKIT_DIR/hooks/session_context.sh" 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/clone7/.agents/devkit/bin/post-fix-gate.py" ] && [ -f "$TMP/clone7/app/google-services.json" ] \
  && [ -z "$(git -C "$TMP/clone7" status --porcelain)" ] \
  && ok "SessionStart in Grok's clone: DevKit link + source checkout's ignored config" \
  || fail "grok clone heal (rc=$rc): $(ls -a "$TMP/clone7/.agents" "$TMP/clone7/app" 2>&1 | tr '\n' ' ')"
git clone -q "$M5" "$TMP/clone8" 2>/dev/null
printf '{"session_id":"s8","hook_event_name":"SessionStart"}' | HOME="$GH" CLAUDE_PROJECT_DIR="$TMP/clone8" SESSION_FETCH=0 \
  bash "$DEVKIT_DIR/hooks/session_context.sh" >/dev/null 2>&1
[ -f "$TMP/clone8/.agents/devkit/bin/post-fix-gate.py" ] && [ ! -e "$TMP/clone8/app/google-services.json" ] \
  && ok "clone with no known source: DevKit link only, no config guessed" \
  || fail "clone8: $(ls -a "$TMP/clone8/.agents" "$TMP/clone8/app" 2>&1 | tr '\n' ' ')"

# ── 6. a file this session created is not "never looked at" ──────────────────
# OfficeReader 2026-09-28: Grok created PdfViewportRestore.kt (search_replace, empty
# old_string), then its next edit of it was blocked "phiên này CHƯA HỀ xem nó": only a Read
# reached the ledger, and Grok's transcript is not in Claude's format.
P9="$TMP/p9"; mkdir -p "$P9/src"; : > "$P9/empty.jsonl"; echo 'class Old' > "$P9/src/Old.kt"
pg() { printf '{"session_id":"s9","transcript_path":"%s","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"%s","new_string":"x"}}' \
  "$P9/empty.jsonl" "$1" "$2" | CLAUDE_PROJECT_DIR="$P9" bash "$DEVKIT_DIR/hooks/precode_gate.sh" >/dev/null 2>&1; echo $?; }
rc1="$(pg "$P9/src/New.kt" "")"; echo 'class New' > "$P9/src/New.kt"
rc2="$(pg "$P9/src/New.kt" "class New")"
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] && ok "edit of a file this session just created: allowed" || fail "created-then-edited blocked (create=$rc1 edit=$rc2)"
rc="$(pg "$P9/src/Old.kt" "class Old")"
[ "$rc" = 2 ] && ok "existing file never read: still blocked" || fail "blind edit allowed (rc=$rc)"

echo
[ "$FAILS" -eq 0 ] && echo "test_gate_friction: all checks passed" || echo "test_gate_friction: $FAILS failed"
exit "$FAILS"
