#!/usr/bin/env bash
# Regression (GeelyEx2 sessions 2026-09-27): gate findings that stopped a finished agent
# or pushed it to rewrite a correct test — the "agent asks the human for nothing" class.
#  1. assertion_lint: a test whose assertion sits in a same-file helper is not vacuous.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# ── 1. assertion in a helper ──────────────────────────────────────────────────
out="$(DK="$DEVKIT_DIR" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.path.join(os.environ["DK"], "scripts", "linters"))
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
sys.path.insert(0, os.path.join(os.environ["DK"], "scripts", "linters"))
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

# A backtick or $( inside SINGLE quotes is literal text, not a command: grep for a CHANGELOG
# line was blocked as "restore (trong lệnh có $(...)/backtick)" (agent-workbench 2026-09-28).
guard_rc() {
  ( cd "$RD" && python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" \
    | CLAUDE_PROJECT_DIR="$RD" bash "$DEVKIT_DIR/hooks/block-dangerous-git.sh" >/dev/null 2>&1 )
  echo $?
}
BT='`'
rc="$(guard_rc "grep -n 'block-dangerous-git${BT}: ${BT}git restore' CHANGELOG.md | head -1")"
[ "$rc" = 0 ] && ok "grep whose single-quoted pattern holds a backtick + 'git restore': allowed" || fail "quoted grep pattern blocked (rc=$rc)"
rc="$(guard_rc "grep -c 'git reset --hard \$(pwd)' notes.md")"
[ "$rc" = 0 ] && ok "grep for a quoted 'git reset --hard \$(…)' text: allowed" || fail "quoted \$( pattern blocked (rc=$rc)"
rc="$(guard_rc "bash -c 'echo \$(git reset --hard)'")"
[ "$rc" = 2 ] && ok "bash -c '…\$(git reset --hard)…' (executed): still blocked" || fail "bash -c subst allowed (rc=$rc)"
rc="$(guard_rc "echo \"\$(git reset --hard)\"")"
[ "$rc" = 2 ] && ok "\"\$(git reset --hard)\" in double quotes (executed): still blocked" || fail "double-quoted subst allowed (rc=$rc)"
NL='
'
rc="$(guard_rc "git commit -q -F - -- a.kt <<'MSG'${NL}fix: ${BT}grep 'x${BT}git restore'${BT} was blocked; ${BT}bash -c${BT} stays checked${NL}MSG")"
[ "$rc" = 0 ] && ok "commit message in a quoted heredoc (<<'MSG') mentioning backticks + git restore: allowed" || fail "quoted heredoc body blocked (rc=$rc)"
rc="$(guard_rc "git commit -m \"\$(cat <<'EOF'${NL}fix: ${BT}git restore${BT} no longer blocked${NL}EOF${NL})\"")"
[ "$rc" = 0 ] && ok "git commit -m \"\$(cat <<'EOF' …)\" mentioning git restore: allowed" || fail "commit -m heredoc blocked (rc=$rc)"
rc="$(guard_rc "bash <<'EOF'${NL}git reset --hard${NL}EOF")"
[ "$rc" = 2 ] && ok "bash <<'EOF' body is run by a shell: still blocked" || fail "bash heredoc allowed (rc=$rc)"
rc="$(guard_rc "cat <<'EOF' | sh${NL}git reset --hard${NL}EOF")"
[ "$rc" = 2 ] && ok "cat <<'EOF' | sh: body piped into a shell: still blocked" || fail "piped heredoc allowed (rc=$rc)"
rc="$(guard_rc "cat <<EOF${NL}\$(git reset --hard)${NL}EOF")"
[ "$rc" = 2 ] && ok "unquoted heredoc (<<EOF) runs \$(git reset --hard): still blocked" || fail "unquoted heredoc subst allowed (rc=$rc)"
rc="$(guard_rc "x=${BT}git clean -fd${BT}")"
[ "$rc" = 2 ] && ok "real backtick git clean -fd: still blocked" || fail "backtick clean allowed (rc=$rc)"

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
_wt="$DEVKIT_DIR/scripts/git/worktree.py"; [ -f "$_wt" ] || _wt="$DEVKIT_DIR/scripts/worktree.py"
( cd "$TMP/wt5" && python3 "$_wt" heal >/dev/null 2>&1 ); rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/wt5/.agents/devkit/bin/post-fix-gate.py" ] && [ -f "$TMP/wt5/app/google-services.json" ] \
  && [ -z "$(git -C "$TMP/wt5" status --porcelain)" ] \
  && ok "heal: DevKit link + ignored local config in a host-made worktree, nothing to commit" \
  || fail "heal (rc=$rc): devkit=$(ls "$TMP/wt5/.agents" 2>&1) config=$(ls "$TMP/wt5/app" 2>&1) status=$(git -C "$TMP/wt5" status --porcelain)"
( cd "$M5" && python3 "$_wt" heal >/dev/null 2>&1 ); rc=$?
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
# Security (check 4c, 2026-09-28): a clone has its own .git/info/exclude. A secret the source
# checkout ignores only there would land in the clone NOT ignored — one `git add` from a push.
M10="$TMP/main10"; mkdir -p "$M10/app"; git -C "$M10" init -q
git -C "$M10" config user.email t@t; git -C "$M10" config user.name t
echo x > "$M10/README.md"; git -C "$M10" add -A; git -C "$M10" commit -qm init
echo 'app/google-services.json' >> "$M10/.git/info/exclude"; echo '{}' > "$M10/app/google-services.json"
git clone -q "$M10" "$TMP/clone10" 2>/dev/null
mkdir -p "$GH/.grok/sessions/x/s10"; printf '{"source_workspace_dir": "%s"}' "$M10" > "$GH/.grok/sessions/x/s10/summary.json"
_wt="$DEVKIT_DIR/scripts/git/worktree.py"; [ -f "$_wt" ] || _wt="$DEVKIT_DIR/scripts/worktree.py"
( cd "$TMP/clone10" && HOME="$GH" python3 "$_wt" heal --session=s10 >/dev/null 2>&1 )
[ ! -e "$TMP/clone10/app/google-services.json" ] && [ -z "$(git -C "$TMP/clone10" status --porcelain)" ] \
  && ok "heal never copies a file the clone would not ignore (source ignores it only in .git/info/exclude)" \
  || fail "secret copied un-ignored into the clone: $(git -C "$TMP/clone10" status --porcelain)"

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

# ── 7. run_impacted skips what this gate already ran (O2) ────────────────────
# post-fix-gate lists every test script it has run in DEVKIT_GATE_DONE; REG-DK-ALL-01
# (run_impacted.sh) re-ran test_proof_gate.sh, test_postfix_gate.sh, hook_contract_test.sh.
DKP="$(cd "$DEVKIT_DIR" && pwd -P)"
lst="$(DEVKIT_GATE_DONE="$DKP/tests/verification/test_repo_consistency.sh" bash "$DEVKIT_DIR/tests/run_impacted.sh" --list)"
printf '%s\n' "$lst" | grep -q 'test_repo_consistency.sh' \
  && fail "run_impacted re-selects a suite the gate already ran: $lst" \
  || ok "run_impacted leaves out the suites in DEVKIT_GATE_DONE"
lst="$(bash "$DEVKIT_DIR/tests/run_impacted.sh" --list)"
printf '%s\n' "$lst" | grep -q 'test_repo_consistency.sh' && ok "without DEVKIT_GATE_DONE: unchanged selection" \
  || fail "selection changed without DEVKIT_GATE_DONE: $lst"

# ── 8. rules-index: the path once per file, not on every line (O5) ────────────
# OfficeReader's index was 17.7 KB, most of it `sed -n 'a,bp' .agents/local/rules/<file>` repeated
# on each of 152 lines — loaded at every session start. Every line stays (a bold lead is a rule).
R8="$TMP/r8"; mkdir -p "$R8/.agents/local/rules" "$R8/.agents/context"
printf '# Luật voice\n\n1. **Xe im còn hơn làm sai** khi không chắc lệnh.\n2. **Không đoán ESC là điều hoà** trong mọi trường hợp.\n\n## Bluetooth A2DP\nĐổi bài qua A2DP.\n' \
  > "$R8/.agents/local/rules/voice.md"
_ri="$DEVKIT_DIR/scripts/context/rules_index.py"; [ -f "$_ri" ] || _ri="$DEVKIT_DIR/scripts/rules_index.py"
idx="$(python3 "$_ri" "$R8")"
printf '%s' "$idx" > "$R8/.agents/context/rules-index.md"
[ "$(printf '%s' "$idx" | grep -c '\.agents/local/rules/voice\.md')" = 1 ] && printf '%s' "$idx" | grep -q 'Xe im còn hơn làm sai — L3–3' \
  && printf '%s' "$idx" | grep -q "sed -n 'a,bp'" \
  && ok "index: path once in the heading, each rule line keeps its lead + L a–b, header says how to open it" \
  || fail "index format: $(printf '%s' "$idx" | tail -5 | tr '\n' '|')"
_rc="$DEVKIT_DIR/scripts/context/rule_context.py"; [ -f "$_rc" ] || _rc="$DEVKIT_DIR/scripts/rule_context.py"
out="$(printf '{"prompt":"sửa lỗi xe đoán ESC là điều hoà"}' | CLAUDE_PROJECT_DIR="$R8" python3 "$_rc")"
printf '%s' "$out" | grep -q "sed -n '4,5p' .agents/local/rules/voice.md" \
  && ok "rule_context: a matching rule comes back as a runnable sed command (new format)" \
  || fail "rule_context new format: $out"
printf '# Rules index\n- Bluetooth và đổi bài hát A2DP — `sed -n '"'"'1,20p'"'"' .agents/local/rules/audio.md`\n' > "$R8/.agents/context/rules-index.md"
out="$(printf '{"prompt":"lỗi bluetooth đổi bài hát a2dp"}' | CLAUDE_PROJECT_DIR="$R8" python3 "$_rc")"
printf '%s' "$out" | grep -q "sed -n '1,20p' .agents/local/rules/audio.md" \
  && ok "rule_context: an index not yet re-synced (old format) still works" || fail "rule_context old format: $out"

# ── 9. the same Stop block twice: items kept, long command + advice not repeated (O4) ──
# GeelyEx2 session 2bcee73a: regression_gate blocked 31 times, 32 k characters of feedback, the
# 600-character Gradle command of REG-CAR-VOICE on every block. Antigravity review: never drop the
# items (id, status, exit, log) — the earlier block may have been compacted away.
M9="$TMP/m9"; mkdir -p "$M9/src" "$M9/.agents"; git -C "$M9" init -q; git -C "$M9" config user.email t@t; git -C "$M9" config user.name t
echo "fun ok() = 1" > "$M9/src/Core.kt"
LONGCMD="true && true && true && true && true && true && true && true && true && true && true && true && true && true && true && echo voice-funnel-failed && exit 3"
python3 -c 'import json,sys; json.dump({"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
  "mandatory_regression_tests":[{"id":"REG-LONG","name":"voice funnel","command":sys.argv[1]}]}]}, open(sys.argv[2],"w"))' "$LONGCMD" "$M9/.agents/regression_matrix.active.json"
git -C "$M9" add -A; git -C "$M9" commit -qm init; echo "fun ok() = 2" > "$M9/src/Core.kt"
o4stop() { printf '{"session_id":"s-o4","hook_event_name":"Stop"}' | CLAUDE_PROJECT_DIR="$M9" FLAKY_RETRY=0 bash "$DEVKIT_DIR/hooks/regression_gate.sh" >/dev/null 2>"$1"; }
o4stop "$TMP/e1"; r1=$?; sleep 1; o4stop "$TMP/e2"; r2=$?   # a new evidence-log stamp, as between real stops
[ "$r1" = 2 ] && [ "$r2" = 2 ] && grep -q 'REG-LONG' "$TMP/e2" && grep -q 'exit 3' "$TMP/e2" && grep -q 'log:' "$TMP/e2" \
  && [ "$(wc -c < "$TMP/e2")" -lt "$(( $(wc -c < "$TMP/e1") * 70 / 100 ))" ] && ! grep -q 'Sửa code/test' "$TMP/e2" \
  && ok "repeat block: same items (id, exit, log), long command cut, advice not repeated" \
  || fail "repeat block (rc $r1/$r2, $(wc -c < "$TMP/e1")→$(wc -c < "$TMP/e2") B): $(head -3 "$TMP/e2" | tr '\n' '|')"
P10="$TMP/p10"; mkdir -p "$P10"; : > "$P10/tr.jsonl"
te10() { printf '{"session_id":"s-o4te","transcript_path":"%s/tr.jsonl","last_assistant_message":"Đã fix lỗi đăng nhập."}' "$P10" \
  | CLAUDE_PROJECT_DIR="$P10" LESSON_REMINDER=0 BUG_LINK_REMINDER=0 bash "$DEVKIT_DIR/hooks/test_evidence_gate.sh" >/dev/null 2>"$1"; }
te10 "$TMP/t1"; r1=$?; te10 "$TMP/t2"; r2=$?
[ "$r1" = 2 ] && [ "$r2" = 2 ] && grep -q 'CHECK 7' "$TMP/t2" && grep -q 'RED→GREEN' "$TMP/t2" \
  && [ "$(wc -c < "$TMP/t2")" -lt "$(( $(wc -c < "$TMP/t1") * 60 / 100 ))" ] \
  && ok "test_evidence_gate repeat: the requirement kept, the explanation not repeated" \
  || fail "test_evidence repeat (rc $r1/$r2, $(wc -c < "$TMP/t1")→$(wc -c < "$TMP/t2") B)"

# ── 10. a long context gets one reminder per threshold (O7) ──────────────────
# GeelyEx2 session 2bcee73a: 214 M cache-read tokens — every call re-reads the whole context.
P11="$TMP/p11"; mkdir -p "$P11/.agents"
ctx() { python3 -c 'import json,sys; print(json.dumps({"type":"assistant","message":{"id":"m"+sys.argv[1],"usage":{"input_tokens":10,
  "cache_read_input_tokens":int(sys.argv[1]),"cache_creation_input_tokens":0,"output_tokens":5},"content":[{"type":"text","text":"ok"}]}}))' "$1" >> "$P11/tr.jsonl"; }
pc() { printf '{"session_id":"s-o7","transcript_path":"%s/tr.jsonl","prompt":"sửa lỗi nút thanh toán bấm hai lần"}' "$P11" \
  | CLAUDE_PROJECT_DIR="$P11" CONTEXT_WARN_TOKENS=150000 bash "$DEVKIT_DIR/hooks/prompt_context.sh" 2>/dev/null; }
: > "$P11/tr.jsonl"; ctx 90000; o1="$(pc)"
ctx 170000; o2="$(pc)"; o3="$(pc)"
! printf '%s' "$o1" | grep -q 'Context phiên' && printf '%s' "$o2" | grep -q 'Context phiên' && printf '%s' "$o2" | grep -q '/compact' \
  && printf '%s' "$o2" | grep -q 'vẫn mở' && ! printf '%s' "$o3" | grep -q 'Context phiên' \
  && ok "context over the threshold: one reminder (/compact suggested, rules still opened), not repeated" \
  || fail "context reminder: under=$(printf '%s' "$o1" | grep -c 'Context phiên') over=$(printf '%s' "$o2" | grep -c 'Context phiên') again=$(printf '%s' "$o3" | grep -c 'Context phiên')"

# ── 11. a suite run from a git hook does not write into the commit's index ────
# agent-workbench 2026-09-28: the pre-commit ran a suite that builds scratch repos with git; it
# inherited GIT_INDEX_FILE, its `git add` landed in the commit's temporary index with objects of
# another repo, and `git commit` died: "invalid object … Error building trees".
R12="$TMP/r12"; mkdir -p "$R12/.agents"; git -C "$R12" init -q; git -C "$R12" config user.email t@t; git -C "$R12" config user.name t
echo a > "$R12/a.txt"
python3 -c 'import json,sys; json.dump({"project":"t","rules":[{"component":"A","watch_files":["a.txt"],
  "mandatory_regression_tests":[{"id":"REG-GIT","name":"scratch repo","command":sys.argv[1]}]}]}, open(sys.argv[2],"w"))' \
  "rm -rf $TMP/inner12; git init -q $TMP/inner12 && touch $TMP/inner12/zz_foreign && git -C $TMP/inner12 add zz_foreign" "$R12/.agents/regression_matrix.active.json"
git -C "$R12" add -A; git -C "$R12" commit -qm init; echo b > "$R12/a.txt"; git -C "$R12" add a.txt
( cd "$R12" && GIT_INDEX_FILE="$R12/.git/index" CLAUDE_PROJECT_DIR="$R12" python3 "$DEVKIT_DIR/bin/post-fix-gate.py" --staged --json >/dev/null 2>&1 )
git -C "$R12" ls-files | grep -q zz_foreign && fail "a pre-commit suite wrote into the commit's index (GIT_INDEX_FILE inherited)" \
  || ok "suites run by the gate get no GIT_INDEX_FILE / GIT_DIR of the commit"

# ── 12. heavy Stop gates only at the handover turn (T0003) ────────────────────
# GeelyEx2: regression_gate blocked 204 times in ~4 days, mostly progress replies — each block a
# model round re-reading the whole context. Skip ONLY when the reply says it is unfinished,
# claims nothing and ran no git commit/push; everything else keeps the gate (fail closed).
M13="$TMP/m13"; mkdir -p "$M13/src" "$M13/.agents"; git -C "$M13" init -q; git -C "$M13" config user.email t@t; git -C "$M13" config user.name t
echo "fun ok() = 1" > "$M13/src/Core.kt"
python3 -c 'import json,sys; json.dump({"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
  "mandatory_regression_tests":[{"id":"REG-RED","name":"red","command":"echo red-suite; exit 1"}]}]}, open(sys.argv[1],"w"))' "$M13/.agents/regression_matrix.active.json"
git -C "$M13" add -A; git -C "$M13" commit -qm init; sleep 2; echo "fun ok() = 2" > "$M13/src/Core.kt"
tr13() { python3 - "$TMP/tr13.jsonl" "$@" <<'PY'
import json, sys, time
iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(t))
now = time.time(); recs = [{"type": "user", "sessionId": "s13", "timestamp": iso(now - 1), "message": {"role": "user", "content": "làm tiếp"}}]
for i, cmd in enumerate(sys.argv[2:]):
    recs.append({"type": "assistant", "sessionId": "s13", "timestamp": iso(now + i), "message": {"content": [
        {"type": "tool_use", "id": "b%d" % i, "name": "Bash", "input": {"command": cmd}}]}})
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in recs))
PY
}
rg13() { python3 -c 'import json,sys; print(json.dumps({"session_id":"s13","hook_event_name":"Stop","transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2]}))' "$TMP/tr13.jsonl" "$1" \
  | CLAUDE_PROJECT_DIR="$M13" REGRESSION_GATE_MAX_ATTEMPTS=100 FLAKY_RETRY=0 ${2:+env $2} bash "$DEVKIT_DIR/hooks/regression_gate.sh" >/dev/null 2>&1; echo $?; }
tr13 "ls"
r_wip="$(rg13 "CHƯA XONG — còn sửa tiếp")"; r_md="$(rg13 "**CHƯA XONG**
Đang làm bước 2.")"; r_claim="$(rg13 "CHƯA XONG — nhưng đã fix lỗi A")"; r_xong="$(rg13 "XONG")"
r_empty="$(rg13 "")"; r_every="$(rg13 "CHƯA XONG — còn sửa" DEVKIT_GATE_EVERY_STOP=1)"
tr13 "ls" "git push origin main"; r_commit="$(rg13 "CHƯA XONG — còn sửa")"   # a push is a handover
[ "$r_wip" = 0 ] && [ "$r_md" = 0 ] && ok "progress reply (CHƯA XONG, markdown too) with red tests: no test run, no block" \
  || fail "WIP skip: plain=$r_wip markdown=$r_md"
[ "$r_claim" = 2 ] && [ "$r_xong" = 2 ] && [ "$r_empty" = 2 ] && [ "$r_every" = 2 ] && [ "$r_commit" = 2 ] \
  && ok "claim / XONG / no reply / EVERY_STOP=1 / push this turn: still blocked" \
  || fail "fail-closed: claim=$r_claim xong=$r_xong empty=$r_empty every=$r_every commit=$r_commit"
# User 2026-10-09 ("Stop hooks… cứ chạy hoài mà lâu vậy?", chose "chỉ test khi bàn giao"): 15 h of Stop-hook gate runs in 3 days,
# most on mid-work turns. A reply with NO status line that claims nothing and committed/pushed nothing is mid-work too: no test run.
# A claim or a push this turn is a handover and is still tested — over verified_head..HEAD, so a mid-work commit is tested there
# (pre-commit runs the light suites, push_gate refuses an ungated push); review_gate keeps the old rule (status line required).
tr13 "ls"
r_none="$(rg13 "Đang chờ Antigravity phản biện kế hoạch.")"
r_none_claim="$(rg13 "Gate chạy lại: PASS 5/5.")"
r_none_every="$(rg13 "Đang chờ Antigravity phản biện kế hoạch." DEVKIT_GATE_EVERY_STOP=1)"
tr13 "ls" "git push origin main"; r_none_push="$(rg13 "Đang chờ Antigravity phản biện kế hoạch.")"
tr13 "ls"
[ "$r_none" = 0 ] && ok "no status line, no claim, no commit/push: mid-work, no test run" || fail "no-status mid-work reply still gated (rc=$r_none)"
# Review 2026-10-09 (P1): OUTCOME was case-sensitive, so a no-status reply claiming the work done in ordinary sentence case
# ("Đã fix …", "Fixed …", "Done.", "Xong: …", "Hoàn tất …", a later "Xong." line) read as mid-work and skipped the suites.
claims_ok=1; for claim in "Đã fix lỗi crash ở parser; test hồi quy chạy lại xanh." "Fixed the crash in the parser; tests pass." \
    "Done. The parser no longer crashes." "Vừa sửa xong parser." "Xong: parser đã ổn." "Hoàn tất: parser đã ổn." \
    "Tóm tắt thay đổi:

Xong. Gate pass."; do
  rc="$(rg13 "$claim")"; [ "$rc" = 2 ] || { claims_ok=0; fail "no-status claim skipped the suites (rc=$rc): $claim"; }
done
[ "$claims_ok" = 1 ] && ok "  … a no-status claim in sentence case (Đã fix / Fixed / Done / Xong: / Hoàn tất / a later Xong line) still runs the tests"
r_notdone="$(rg13 "NOT DONE — still fixing the parser")"
[ "$r_notdone" = 0 ] && ok "  … while 'NOT DONE — …' stays mid-work (done inside 'not done' is no claim)" || fail "NOT DONE read as a claim (rc=$r_notdone)"
[ "$r_none_claim" = 2 ] && [ "$r_none_every" = 2 ] && [ "$r_none_push" = 2 ] \
  && ok "  … but a claim / DEVKIT_GATE_EVERY_STOP=1 / a push this turn still runs the tests" \
  || fail "no-status handover not gated: claim=$r_none_claim every=$r_none_every push=$r_none_push"
# A turn that committed the red change leaves a clean tree: the gate tests the commit.
sleep 2; tr13 "git commit -qm red"; git -C "$M13" add -A; git -C "$M13" commit -qm "red change"
r_clean="$(rg13 "XONG")"
[ "$r_clean" = 2 ] && ok "clean tree after a commit this turn: the committed change is still tested" \
  || fail "committed red change passed the stop (rc=$r_clean)"
# Antigravity review: a commit made outside the transcript's words (alias, script, subagent) and a
# commit from an EARLIER progress turn are still gated — HEAD past the last verified one.
M15="$TMP/m15"; mkdir -p "$M15/src" "$M15/.agents"; git -C "$M15" init -q; git -C "$M15" config user.email t@t; git -C "$M15" config user.name t
echo "fun ok() = 1" > "$M15/src/Core.kt"; cp "$M13/.agents/regression_matrix.active.json" "$M15/.agents/"
git -C "$M15" add -A; git -C "$M15" commit -qm init
rg15() { python3 -c 'import json,sys; print(json.dumps({"session_id":"s15","hook_event_name":"Stop","transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2]}))' "$TMP/tr13.jsonl" "$1" \
  | CLAUDE_PROJECT_DIR="$M15" REGRESSION_GATE_MAX_ATTEMPTS=100 FLAKY_RETRY=0 bash "$DEVKIT_DIR/hooks/regression_gate.sh" >/dev/null 2>&1; echo $?; }
tr13 "ls"; r_base="$(rg15 "CHƯA XONG — bắt đầu")"                        # records the baseline
echo "fun ok() = 2" > "$M15/src/Core.kt"; git -C "$M15" commit -qam "via alias"   # not in the transcript
r_alias="$(rg15 "CHƯA XONG — còn làm")"; r_later="$(rg15 "XONG")"
[ "$r_base" = 0 ] && [ "$r_alias" = 0 ] && [ "$r_later" = 2 ] \
  && ok "a local commit mid-work is not gated; the handover turn still tests it (made outside the transcript)" \
  || fail "unverified commit: base=$r_base wip=$r_alias later=$r_later"
# …but once unverified commits are on the upstream (pushed by any path), a progress reply is gated.
git init -q --bare "$TMP/up15.git"; git -C "$M15" remote add origin "$TMP/up15.git"
git -C "$M15" push -q -u origin HEAD 2>/dev/null
r_pushed="$(rg15 "CHƯA XONG — còn làm")"
[ "$r_pushed" = 2 ] && ok "unverified commits already on the upstream: gated even on a progress reply" \
  || fail "pushed unverified commit passed a progress reply (rc=$r_pushed)"
# An amend/reset with no upstream must not re-baseline to HEAD (Antigravity review v4): the
# rewritten commit is tested from the last point both histories share.
M17="$TMP/m17"; mkdir -p "$M17/src" "$M17/.agents"; git -C "$M17" init -q; git -C "$M17" config user.email t@t; git -C "$M17" config user.name t
echo "fun ok() = 1" > "$M17/src/Core.kt"; cp "$M13/.agents/regression_matrix.active.json" "$M17/.agents/"
git -C "$M17" add -A; git -C "$M17" commit -qm init; echo "fun ok() = 2" > "$M17/src/B.kt"; git -C "$M17" add -A; git -C "$M17" commit -qm "B"
rg17() { python3 -c 'import json,sys; print(json.dumps({"session_id":"s17","hook_event_name":"Stop","transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2]}))' "$TMP/tr13.jsonl" "$1" \
  | CLAUDE_PROJECT_DIR="$M17" REGRESSION_GATE_MAX_ATTEMPTS=100 FLAKY_RETRY=0 bash "$DEVKIT_DIR/hooks/regression_gate.sh" >/dev/null 2>&1; echo $?; }
r0="$(rg17 "XONG")"                                  # baseline = B (clean tree)
echo "fun ok() = 9" > "$M17/src/Core.kt"; git -C "$M17" commit -q -a --amend -m "B amended"   # rewrites B, touches Core.kt
r_amend="$(rg17 "XONG")"
[ "$r0" = 0 ] && [ "$r_amend" = 2 ] && ok "amend with no upstream: the rewritten commit is still tested" \
  || fail "amend slipped through (base=$r0 amend=$r_amend)"
# A teammate's push to the shared upstream is not "our unverified commits on the remote".
git clone -q "$TMP/up15.git" "$TMP/mate15" 2>/dev/null; git -C "$TMP/mate15" config user.email m@m; git -C "$TMP/mate15" config user.name m
echo mate > "$TMP/mate15/mate.txt"; git -C "$TMP/mate15" add -A; git -C "$TMP/mate15" commit -qm mate; git -C "$TMP/mate15" push -q 2>/dev/null
M18="$TMP/m18"; git clone -q "$TMP/up15.git" "$M18" 2>/dev/null
git -C "$M18" reset -q --hard HEAD~1   # our clone (tracking its upstream), one behind the mate
git -C "$M18" rev-parse -q --verify '@{u}' >/dev/null || fail "fixture: m18 has no upstream"
python3 -c 'import json,sys,os; os.makedirs(sys.argv[1]+"/.claude/audit-gate",exist_ok=True); json.dump({"verified_head":sys.argv[2]},open(sys.argv[1]+"/.claude/audit-gate/regression_gate.state.json","w"))' "$M18" "$(git -C "$M18" rev-parse HEAD)"
printf '*\n' > "$M18/.claude/audit-gate/.gitignore"; echo "fun ok() = 5" > "$M18/src/Core.kt"
r_mate="$(python3 -c 'import json,sys; print(json.dumps({"session_id":"s18","hook_event_name":"Stop","transcript_path":sys.argv[1],"last_assistant_message":"CHƯA XONG — đang làm"}))' "$TMP/tr13.jsonl" \
  | CLAUDE_PROJECT_DIR="$M18" REGRESSION_GATE_MAX_ATTEMPTS=100 FLAKY_RETRY=0 bash "$DEVKIT_DIR/hooks/regression_gate.sh" >/dev/null 2>&1; echo $?)"
[ "$r_mate" = 0 ] && ok "a teammate's push to the upstream does not turn our progress reply into a handover" \
  || fail "teammate push gated a progress reply (rc=$r_mate)"
# …nor does pulling it in (Antigravity review v5): HEAD now holds the mate's commit; ours are not pushed.
git -C "$M18" stash -q 2>/dev/null; git -C "$M18" pull -q --ff-only 2>/dev/null; git -C "$M18" stash pop -q 2>/dev/null
r_pull="$(python3 -c 'import json,sys; print(json.dumps({"session_id":"s18","hook_event_name":"Stop","transcript_path":sys.argv[1],"last_assistant_message":"CHƯA XONG — đang làm"}))' "$TMP/tr13.jsonl" \
  | CLAUDE_PROJECT_DIR="$M18" REGRESSION_GATE_MAX_ATTEMPTS=100 FLAKY_RETRY=0 bash "$DEVKIT_DIR/hooks/regression_gate.sh" >/dev/null 2>&1; echo $?)"
[ "$r_pull" = 0 ] && ok "after pulling a teammate's commit, a progress reply is still not a handover" \
  || fail "pulled teammate commit gated a progress reply (rc=$r_pull)"
# SessionStart records the baseline before the first turn can commit (Antigravity review v3).
M16="$TMP/m16"; mkdir -p "$M16"; git -C "$M16" init -q; git -C "$M16" config user.email t@t; git -C "$M16" config user.name t
echo x > "$M16/x"; git -C "$M16" add -A; git -C "$M16" commit -qm i
printf '{"session_id":"s16","hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$M16" SESSION_FETCH=0 bash "$DEVKIT_DIR/hooks/session_context.sh" >/dev/null 2>&1
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verified_head",""))' "$M16/.claude/audit-gate/regression_gate.state.json" 2>/dev/null)" = "$(git -C "$M16" rev-parse HEAD)" ] \
  && ok "SessionStart records verified_head" || fail "SessionStart baseline missing"
# review_gate: the fresh-context review is asked at the handover, not on a progress reply.
M14="$TMP/m14"; mkdir -p "$M14/src"; git -C "$M14" init -q; git -C "$M14" config user.email t@t; git -C "$M14" config user.name t
echo "fun a() = 1" > "$M14/src/A.kt"; git -C "$M14" add -A; git -C "$M14" commit -qm init; echo "fun a() = 2" > "$M14/src/A.kt"
python3 - "$TMP/tr13.jsonl" "$M14/src/A.kt" <<'PY'
import json, sys, time
iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(t)); now = time.time()
recs = [{"type": "user", "sessionId": "s14", "timestamp": iso(now - 20), "message": {"role": "user", "content": "sửa A"}},
        {"type": "assistant", "sessionId": "s14", "timestamp": iso(now - 10), "message": {"content": [
            {"type": "tool_use", "id": "e1", "name": "Edit", "input": {"file_path": sys.argv[2], "old_string": "1", "new_string": "2"}}]}}]
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in recs))
PY
rv14() { python3 -c 'import json,sys; print(json.dumps({"session_id":"s14","transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2],"cwd":sys.argv[3]}))' "$TMP/tr13.jsonl" "$1" "$M14" \
  | CLAUDE_PROJECT_DIR="$M14" bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>&1; echo $?; }
rv_wip="$(rv14 "CHƯA XONG — còn sửa")"; rv_x="$(rv14 "XONG")"
[ "$rv_wip" = 0 ] && [ "$rv_x" = 2 ] && ok "review_gate: progress reply not held, XONG still needs the fresh-context review" \
  || fail "review_gate: wip=$rv_wip xong=$rv_x"
rv_none="$(rv14 "Đang chờ Antigravity phản biện kế hoạch.")"
[ "$rv_none" = 2 ] && ok "review_gate: a reply with no status line is still held (only the regression gate skips it)" \
  || fail "review_gate loosened for a no-status reply (rc=$rv_none)"

echo
[ "$FAILS" -eq 0 ] && echo "test_gate_friction: all checks passed" || echo "test_gate_friction: $FAILS failed"
exit "$FAILS"
