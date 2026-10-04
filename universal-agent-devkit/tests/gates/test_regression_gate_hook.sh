#!/usr/bin/env bash
# Regression test: hooks/regression_gate.sh (Stop hook) blocks finishing while a
# related regression test fails or a changed source file has no test — only for a
# project that adopted its own matrix — and never traps the session.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REPO="$TMP/repo"
stop() { printf '{"session_id":"s-1","hook_event_name":"Stop"}' \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }

mkdir -p "$REPO/src" "$REPO/templates" && cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
echo 'exit 0' > result.sh
git add -A && git commit -qm init

stop; [ $? = 0 ] && ok "clean tree: allowed" || fail "clean tree blocked"

# A DevKit SAMPLE matrix is not an adopted one: never enforced (placeholder tests).
cp "$DEVKIT_DIR/templates/regression_matrix.json" templates/regression_matrix.json
git add -A && git commit -qm sample
echo "fun ok() = 2" > src/Core.kt
stop; rc=$?
[ "$rc" = 0 ] && ok "sample matrix: not enforced" || fail "sample matrix enforced"
# ... but not silently: the user is told once per session that the gate is off.
grep -q systemMessage "$TMP/out" && grep -q 'agent-kit matrix' "$TMP/out" \
  && ok "sample matrix: gate-off warning shown (names agent-kit matrix)" || fail "sample matrix skipped silently: out='$(cat "$TMP/out")'"
echo "fun ok() = 22" > src/Core.kt
stop; rc=$?
[ "$rc" = 0 ] && [ ! -s "$TMP/out" ] && grep -q 'not adopted' .claude/audit-gate/regression_gate.log \
  && ok "sample matrix: warning once per session, still logged" || fail "sample warning repeated (rc=$rc out='$(cat "$TMP/out")')"

# The project's own committed matrix, with a failing related test => block.
cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core flow","command":"sh result.sh"}]}]}
JSON
echo 'exit 1' > result.sh
git add -A && git commit -qm "own matrix"
echo "fun ok() = 3" > src/Core.kt
stop; rc=$?
[ "$rc" = 2 ] && grep -q "REG-1" "$TMP/err" && ok "failing related test blocks the stop (reason names REG-1)" || fail "failing test not blocked (rc=$rc)"
grep -q '❌ FAIL | REG-1' .agents/regression_checklist.md && ok "checklist records the real FAIL" || fail "checklist not updated"

# Loop guard: same change blocks MAX_ATTEMPTS(2) times, then releases with a visible warning.
stop; rc2=$?
stop; rc3=$?
[ "$rc2" = 2 ] && [ "$rc3" = 0 ] && grep -q systemMessage "$TMP/out" && ok "loop guard releases after 2 blocks with a user-visible warning" \
  || fail "loop guard wrong (rc2=$rc2 rc3=$rc3)"

# Fixed => allowed, and the result is cached for the same diff (no re-run).
echo 'exit 0' > result.sh
git add result.sh && git commit -qm "fix test"
echo "fun ok() = 4" > src/Core.kt
stop; [ $? = 0 ] && ok "green related test: allowed" || fail "green test still blocked"
runs_before="$(grep -c ' pass ' .claude/audit-gate/regression_gate.log)"
stop
[ "$(grep -c ' pass ' .claude/audit-gate/regression_gate.log)" = "$runs_before" ] && ok "same diff not re-tested (cached)" || fail "cache not used"

# A changed source file no test watches => block with UNCOVERED.
echo "fun other() = 1" > src/Other.kt
stop; rc=$?
[ "$rc" = 2 ] && grep -q "UNCOVERED:src/Other.kt" "$TMP/err" && ok "uncovered source file blocks the stop" || fail "uncovered not blocked (rc=$rc)"

# Escape hatch.
REGRESSION_GATE=0 bash -c "printf '{}' | CLAUDE_PROJECT_DIR='$REPO' bash '$HOOK'"; [ $? = 0 ] && ok "REGRESSION_GATE=0 skips" || fail "escape hatch ignored"

# The matrix `agent-kit profile` writes (.agents/regression_matrix.active.json) is found.
REPO="$TMP/repo2"; mkdir -p "$REPO/src" "$REPO/.agents" && cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt && echo 'exit 1' > result.sh
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-A","name":"core","command":"sh result.sh"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
stop; rc=$?
[ "$rc" = 2 ] && grep -q "REG-A" "$TMP/err" && ok ".agents/regression_matrix.active.json is enforced" || fail "active matrix ignored (rc=$rc)"

# A profile matrix marked enforce_as_is (web: auto-detects the project's runner) is
# enforced exactly as installed — here it fails because there is no package.json.
REPO="$TMP/repo3"; mkdir -p "$REPO/src" "$REPO/.agents" && cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "export const a = 1" > src/app.ts
cp "$DEVKIT_DIR/profiles/web/regression_matrix.json" .agents/regression_matrix.active.json
git add -A && git commit -qm init
echo "export const a = 2" > src/app.ts
stop; rc=$?
[ "$rc" = 2 ] && grep -q "REG-WEB-01" "$TMP/err" && ok "web profile matrix (enforce_as_is) is enforced as installed" || fail "web matrix not enforced (rc=$rc)"

# Undetected runner (Unity): `agent-kit profile game` keeps the profile's SAMPLE matrix
# as .agents/regression_matrix.active.json — gate off, never blocks, but said so.
REPO="$TMP/repo4"; mkdir -p "$REPO/Assets" "$REPO/.agents" && cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "class P {}" > Assets/P.cs
cp "$DEVKIT_DIR/profiles/game/regression_matrix.json" .agents/regression_matrix.active.json
git add -A && git commit -qm init
echo "class P { int a; }" > Assets/P.cs
stop; rc=$?
[ "$rc" = 0 ] && grep -q systemMessage "$TMP/out" && grep -q 'agent-kit matrix' "$TMP/out" \
  && ok "game sample matrix (no runner detected): allowed, gate-off warning shown" || fail "game sample silent (rc=$rc out='$(cat "$TMP/out")')"

# Gate missing (copy-mode hook, no DevKit reachable): allowed, but said once per session.
mkdir -p "$TMP/copyhooks" && cp "$HOOK" "$TMP/copyhooks/regression_gate.sh"
nostop() { printf '{"session_id":"s-copy","hook_event_name":"Stop"}' | HOME="$TMP/nohome" DEVKIT_ROOT= PATH="/usr/bin:/bin" \
  CLAUDE_PROJECT_DIR="$REPO" bash "$TMP/copyhooks/regression_gate.sh" 2>/dev/null; }
out1="$(nostop)"; rc1=$?; out2="$(nostop)"
[ "$rc1" = 0 ] && printf '%s' "$out1" | grep -q systemMessage && [ -z "$out2" ] \
  && ok "gate not found: visible warning once per session, never blocks" || fail "gate-not-found handling (rc=$rc1, out2='$out2')"

# A static finding (secret) blocks with its file:line in the reason, not just a count.
F2="$TMP/finding"; mkdir -p "$F2/src" "$F2/templates"
( cd "$F2" && git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
  git add -A && git commit -qm init
  printf 'fun ok() = 2\nval token = "%s"\n' "hf_$(python3 -c 'print("z"*34, end="")')" > src/Core.kt )
printf '{"session_id":"s-f","hook_event_name":"Stop"}' | CLAUDE_PROJECT_DIR="$F2" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 2 ] && grep -q "secrets src/Core.kt:2" "$TMP/err" && ok "block reason names the secret's file:line" || fail "finding location missing (rc=$rc): $(head -4 "$TMP/err")"

# Deleting the committed matrix must not silently switch the gate off: block once, then warn.
D="$TMP/deleted"; mkdir -p "$D/src" "$D/.agents"
( cd "$D" && git init -q . && git config user.email t@t && git config user.name t && echo "fun ok() = 1" > src/Core.kt
  printf '{"rules":[{"component":"c","watch_files":["src/*.kt"],"mandatory_regression_tests":[{"id":"R","name":"r","command":"true"}]}]}\n' > .agents/regression_matrix.active.json
  git add -A && git commit -qm init && rm .agents/regression_matrix.active.json && echo "fun ok() = 2" > src/Core.kt )
dstop() { printf '{"session_id":"s-d","hook_event_name":"Stop"}' | CLAUDE_PROJECT_DIR="$D" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
dstop; rc=$?; [ "$rc" = 2 ] && grep -q "XOÁ" "$TMP/err" && ok "committed matrix deleted: the stop is blocked with the restore command" || fail "deleted matrix not caught (rc=$rc)"
dstop; rc=$?; [ "$rc" = 0 ] && grep -q systemMessage "$TMP/out" && ok "deleted matrix: blocked once per session, then a warning" || fail "deleted matrix traps the session (rc=$rc)"

# UNTESTED (gate exit 4): the test cannot run on this machine (untested_exit) — the stop
# goes through with a warning (blocking would trap every session there), once per change.
U="$TMP/untested"; mkdir -p "$U/src" "$U/templates"
( cd "$U" && git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-U","name":"unity","command":"exit 2","untested_exit":2}]}]}
JSON
  git add -A && git commit -qm init && echo "fun ok() = 2" > src/Core.kt )
ustop() { printf '{"session_id":"s-u","hook_event_name":"Stop"}' | CLAUDE_PROJECT_DIR="$U" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
ustop; rc=$?
[ "$rc" = 0 ] && grep -q "UNTESTED" "$TMP/out" && grep -q "REG-U" "$TMP/out" && grep -q "KHÔNG phải PASS" "$TMP/out" \
  && ok "UNTESTED test: stop allowed with a 'not a PASS' warning naming it" || fail "UNTESTED handling (rc=$rc out='$(cat "$TMP/out")' err='$(head -3 "$TMP/err")')"
ustop; rc=$?
[ "$rc" = 0 ] && [ ! -s "$TMP/out" ] && ok "UNTESTED warning once per change" || fail "UNTESTED warning repeated"

# A test that FAILs because the machine cannot provision its tools (Gradle cannot download
# the JDK toolchain, no Android SDK) — no test ran and no code change can fix it: like
# UNTESTED, a warning once per change instead of blocking the stop. A compile error in the
# change itself still blocks.
E="$TMP/envblocked"; mkdir -p "$E/src" "$E/templates"
( cd "$E" && git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf 'echo "* What went wrong:"\necho "Unable to download toolchain matching the requirements"\nexit 1\n' > env.sh
  printf 'echo "e: src/Core.kt:1:12 Unresolved reference: nope"\nexit 1\n' > compile.sh
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-E","name":"gradle","command":"sh env.sh"}]}]}
JSON
  git add -A && git commit -qm init && echo "fun ok() = 2" > src/Core.kt )
estop() { printf '{"session_id":"s-e","hook_event_name":"Stop"}' | CLAUDE_PROJECT_DIR="$E" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
estop; rc=$?
[ "$rc" = 0 ] && grep -q "REG-E" "$TMP/out" && grep -q "KHÔNG phải PASS" "$TMP/out" \
  && ok "environment-blocked test: stop allowed with a 'not a PASS' warning naming it" || fail "env-blocked handling (rc=$rc out='$(cat "$TMP/out")' err='$(head -3 "$TMP/err")')"
estop; rc=$?
[ "$rc" = 0 ] && [ ! -s "$TMP/out" ] && ok "environment-blocked warning once per change" || fail "env-blocked warning repeated (rc=$rc)"
( cd "$E" && sed -i.bak 's/sh env.sh/sh compile.sh/' templates/regression_matrix.json && rm -f templates/regression_matrix.json.bak && git commit -qam compile && echo "fun ok() = 3" > src/Core.kt )
estop; rc=$?
[ "$rc" = 2 ] && grep -q "REG-E" "$TMP/err" && ok "compile error in the change: still blocks" || fail "compile error not blocked (rc=$rc)"

# Matrix not trusted because it is UNCOMMITTED (the only problem): the cure is to commit
# it — not "fix code/test" — and the files it watches are not UNCOVERED. Zero tests ran
# and the agent cannot make the matrix trusted itself, so the stop goes through with a
# user-visible warning once per change (like UNTESTED) instead of blocking every stop.
M5="$TMP/uncommitted"; mkdir -p "$M5/src" && cd "$M5" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt && echo "fun o() = 1" > src/Other.kt
git add -A && git commit -qm init
mkdir -p .agents && cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-C","name":"core","command":"true"}]}]}
JSON
echo "fun ok() = 2" > src/Core.kt
mstop() { printf '{"session_id":"s-m","hook_event_name":"Stop"}' | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
mstop "$M5"; rc=$?
[ "$rc" = 0 ] && grep -q systemMessage "$TMP/out" && grep -q 'commit .agents/regression_matrix.active.json' "$TMP/out" \
  && grep -q 'agent-kit matrix' "$TMP/out" && ok "uncommitted matrix only: allowed, message says commit .agents/regression_matrix.active.json" \
  || fail "uncommitted matrix (rc=$rc out='$(cat "$TMP/out")' err='$(head -5 "$TMP/err")')"
! grep -q 'UNCOVERED:src/Core.kt' "$TMP/out" "$TMP/err" && ! grep -q 'Sửa code/test' "$TMP/out" "$TMP/err" \
  && ok "uncommitted matrix: a watched file is not listed UNCOVERED, no 'fix code/test' cure" || fail "wrong cure / watched file listed UNCOVERED"
mstop "$M5"; rc=$?
[ "$rc" = 0 ] && [ ! -s "$TMP/out" ] && [ ! -s "$TMP/err" ] && ok "uncommitted matrix: warning once per change" || fail "uncommitted-matrix warning repeated (rc=$rc)"
echo "fun o() = 2" > src/Other.kt
mstop "$M5"; rc=$?
[ "$rc" = 0 ] && grep -q 'src/Other.kt' "$TMP/out" && ! grep -q 'src/Core.kt' "$TMP/out" \
  && ok "uncommitted matrix: a file no rule of it watches is still named (Core.kt is not)" || fail "unwatched file not named (rc=$rc out='$(cat "$TMP/out")')"

# An uncommitted matrix that SHADOWS a committed one (candidate order) must not switch
# the committed tests off: still blocked, and the reason names both files.
cd "$M5" && git checkout -q -- src && mkdir -p templates && cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-T","name":"core","command":"exit 1"}]}]}
JSON
git add templates && git commit -qm "committed matrix" && echo "fun ok() = 3" > src/Core.kt
mstop "$M5"; rc=$?
[ "$rc" = 2 ] && grep -q 'templates/regression_matrix.json' "$TMP/err" && grep -q 'regression_matrix.active.json' "$TMP/err" \
  && ok "uncommitted matrix shadowing a committed one: blocked, both named" || fail "shadowing matrix (rc=$rc err='$(head -5 "$TMP/err")')"

# A COMMITTED matrix edited in the change (`exit 1` -> `true` shape): still blocks, and
# the cure is a human review of the matrix edit, not "add a test".
M6="$TMP/edited"; mkdir -p "$M6/src" "$M6/.agents" && cd "$M6" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-E","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init
sed -i.bak 's/"true"/"true; true"/' .agents/regression_matrix.active.json && rm -f .agents/regression_matrix.active.json.bak
echo "fun ok() = 2" > src/Core.kt
mstop "$M6"; rc=$?
[ "$rc" = 2 ] && grep -q 'review' "$TMP/err" && ! grep -q 'regression_matrix.json hoặc' "$TMP/err" && ! grep -q 'UNCOVERED' "$TMP/err" \
  && ok "edited committed matrix: blocked, cure = review the matrix edit (no 'add a test', no UNCOVERED)" \
  || fail "edited matrix (rc=$rc err='$(cat "$TMP/err")')"

# Explicit adoption: "adopted": true makes a matrix enforced even when it is byte-identical
# to a DevKit sample (a sample that gains the project's only difference must not silently
# turn the gate off). Fake DevKit whose sample carries the key, so the copy is identical.
FK="$TMP/fakekit"; mkdir -p "$FK/hooks" "$FK/bin" "$FK/profiles/x"
cp "$HOOK" "$FK/hooks/regression_gate.sh" && ln -s "$DEVKIT_DIR/bin/post-fix-gate.py" "$FK/bin/post-fix-gate.py"
cat > "$FK/profiles/x/regression_matrix.json" <<'JSON'
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-AD","name":"core","command":"exit 1"}]}]}
JSON
M7="$TMP/adopted"; mkdir -p "$M7/src" "$M7/.agents" && cd "$M7" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt && cp "$FK/profiles/x/regression_matrix.json" .agents/regression_matrix.active.json
git add -A && git commit -qm init && echo "fun ok() = 2" > src/Core.kt
printf '{"session_id":"s-ad","hook_event_name":"Stop"}' | CLAUDE_PROJECT_DIR="$M7" bash "$FK/hooks/regression_gate.sh" >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 2 ] && grep -q 'REG-AD' "$TMP/err" && ok "\"adopted\": true: enforced although byte-identical to a sample" \
  || fail "adopted matrix not enforced (rc=$rc out='$(cat "$TMP/out")')"
python3 - "$FK/profiles/x/regression_matrix.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d.pop("adopted"); json.dump(d, open(p, "w"))
PY
cp "$FK/profiles/x/regression_matrix.json" .agents/regression_matrix.active.json && git add -A && git commit -qm sample -q
echo "fun ok() = 3" > src/Core.kt
printf '{"session_id":"s-ad2","hook_event_name":"Stop"}' | CLAUDE_PROJECT_DIR="$M7" bash "$FK/hooks/regression_gate.sh" >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && grep -q 'adopted' "$TMP/out" && ok "sample copy without the key: gate off, the message names \"adopted\"" \
  || fail "sample without adopted (rc=$rc out='$(cat "$TMP/out")')"

# ── Non-Claude agent / no usable transcript: the gate can never trap the agent ──────
# Grok (2026-09-25, OfficeReader) runs the Claude Stop hooks: its diff changed every turn,
# so the per-fingerprint guard never released and the gate blocked it 11 times in a
# morning. Degraded mode (not Claude, or no Claude transcript): a total block cap per
# session (REGRESSION_GATE_MAX_SESSION_BLOCKS, default 3; a pass resets it), the last
# result reused for an unchanged tree, and Grok's session-end Stop is not a turn end.
G="$TMP/grok"; mkdir -p "$G/src" "$G/.agents" && cd "$G" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
printf 'echo x >> "%s"\nexit "$(cat "%s")"\n' "$TMP/g_runs" "$TMP/g_exit" > result.sh
echo 1 > "$TMP/g_exit"; : > "$TMP/g_runs"
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-G","name":"core","command":"sh result.sh"}]}]}
JSON
git add -A && git commit -qm init
printf '%s\n' '{"timestamp":1790240706,"method":"_x.ai/session/update","params":{"sessionId":"g","update":{"sessionUpdate":"hook_execution"}}}' > "$TMP/updates.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"c-1"}' > "$TMP/claude.jsonl"
runs() { grep -c x "$TMP/g_runs" | tr -d ' '; }
# gstop <session> [reason] — a Grok-shaped Stop (camelCase envelope, GROK_* env, its own transcript)
gstop() { printf '{"hookEventName":"stop","hook_event_name":"Stop","sessionId":"%s","session_id":"%s","workspaceRoot":"%s","transcript_path":"%s","reason":"%s","stopHookActive":false}' \
    "$1" "$1" "$G" "$TMP/updates.jsonl" "${2:-end_turn}" \
  | GROK_HOOK_EVENT=stop GROK_SESSION_ID="$1" CLAUDE_PROJECT_DIR="$G" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
cstop() { printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "$TMP/claude.jsonl" \
  | CLAUDE_PROJECT_DIR="$G" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }

echo "fun ok() = 2" > src/Core.kt
gstop g-0 channel_closed; rc=$?
[ "$rc" = 0 ] && [ "$(runs)" = 0 ] && ok "Grok session-end Stop (reason channel_closed): allowed, no test run" \
  || fail "session-end Stop ran the gate (rc=$rc runs=$(runs))"

gstop g-1; rc1=$?; n1="$(runs)"; gstop g-1; rc2=$?; n2="$(runs)"
[ "$rc1" = 2 ] && [ "$rc2" = 2 ] && [ "$n1" -gt 0 ] && [ "$n2" = "$n1" ] && grep -q "REG-G" "$TMP/err" \
  && ok "degraded: same tree twice in a session → tests run once, the cached REJECT is re-used" \
  || fail "result not reused (rc1=$rc1 rc2=$rc2 runs ${n1} then ${n2})"
echo "x" > src/NewTest.kt; gstop g-1; n3="$(runs)"; echo "y" > src/NewTest.kt; gstop g-1; n4="$(runs)"; rm -f src/NewTest.kt
[ "$n3" -gt "$n2" ] && [ "$n4" -gt "$n3" ] && ok "degraded: a new or edited untracked file is a new tree (suite re-runs)" \
  || fail "untracked content ignored by the reuse key (runs ${n2} then ${n3} then ${n4})"

CAP_RCS=""; for v in 1 2 3 4; do echo "fun ok() = 1$v" > src/Core.kt; gstop g-2; CAP_RCS="$CAP_RCS$?"; done
[ "$CAP_RCS" = 2220 ] && grep -q systemMessage "$TMP/out" && grep -q "g-2" "$TMP/out" && grep -q "KHÔNG phải PASS" "$TMP/out" \
  && ok "degraded: new tree every stop → 3 blocks, then released with a systemMessage naming the session" \
  || fail "session cap (rcs=$CAP_RCS out='$(cat "$TMP/out")')"
echo "fun ok() = 99" > src/Core.kt; gstop g-2; rc=$?
[ "$rc" = 0 ] && grep -q systemMessage "$TMP/out" && ok "degraded: stays released for the rest of the session (still said)" \
  || fail "released session blocked again (rc=$rc)"

echo 0 > "$TMP/g_exit"; echo "fun ok() = 100" > src/Core.kt; gstop g-2; rc=$?
echo 1 > "$TMP/g_exit"; echo "fun ok() = 101" > src/Core.kt; gstop g-2; rc2=$?
[ "$rc" = 0 ] && [ "$rc2" = 2 ] && ok "degraded: a pass resets the session count — the next failure blocks again" \
  || fail "pass did not reset the session cap (pass rc=$rc, next rc=$rc2)"

CAP_RCS=""; for v in 1 2 3 4; do echo "fun ok() = 20$v" > src/Core.kt; cstop c-1; CAP_RCS="$CAP_RCS$?"; done
[ "$CAP_RCS" = 2222 ] && ok "Claude session (readable transcript): no session cap — every new failing tree blocks" \
  || fail "Claude session capped (rcs=$CAP_RCS)"

CAP_RCS=""; for v in 1 2 3 4; do echo "fun ok() = 30$v" > src/Core.kt
  printf '{"session_id":"n-1","hook_event_name":"Stop"}' | CLAUDE_PROJECT_DIR="$G" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; CAP_RCS="$CAP_RCS$?"; done
[ "$CAP_RCS" = 2220 ] && grep -q systemMessage "$TMP/out" && ok "no transcript at all (bridge / unknown agent): session cap applies too" \
  || fail "no-transcript session not capped (rcs=$CAP_RCS)"
CAP_RCS=""; for v in 1 2; do echo "fun ok() = 40$v" > src/Core.kt
  printf '{"session_id":"n-2","hook_event_name":"Stop"}' | REGRESSION_GATE_MAX_SESSION_BLOCKS=1 CLAUDE_PROJECT_DIR="$G" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; CAP_RCS="$CAP_RCS$?"; done
[ "$CAP_RCS" = 20 ] && ok "REGRESSION_GATE_MAX_SESSION_BLOCKS sets the cap" || fail "cap knob ignored (rcs=$CAP_RCS)"
# An existing test edited by ANOTHER session must not block this one (2026-09-25: session Y was
# blocked on every Stop by two tests session X had edited). The hook hands the gate its session
# id and transcript; another session's edit → the stop goes through with a warning (once per
# change); the same edit made by this session → still blocked.
X="$TMP/xsession"; mkdir -p "$X/src/test" "$X/.agents" && cd "$X" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt && echo "assert(true)" > src/test/CoreTest.kt
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt","src/test/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-X","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt && echo "// weakened" > src/test/CoreTest.kt
python3 - "$X" "$TMP/y.jsonl" <<'PY'
import json, os, sys, time
repo, tp = sys.argv[1], sys.argv[2]
now = time.time()
iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(t))
os.utime(os.path.join(repo, "src/test/CoreTest.kt"), (now - 300, now - 300))   # written by session X…
os.makedirs(os.path.join(repo, ".claude/audit-gate"), exist_ok=True)
with open(os.path.join(repo, ".claude/audit-gate/bash_write_ledger.tsv"), "w") as f:
    f.write("s-x\tstart\t%.3f\tb1\ns-x\tend\t%.3f\tb1\n" % (now - 305, now - 295))    # …inside X's Bash window
    f.write("s-y\tstart\t%.3f\tm1\ns-y\tend\t%.3f\tm1\n" % (now - 590, now - 589))    # Y's own Bash window
open(tp, "w").write("".join(json.dumps(r) + "\n" for r in [
    {"type": "user", "timestamp": iso(now - 600), "message": {"role": "user", "content": "fix it"}},
    {"type": "assistant", "timestamp": iso(now - 590), "message": {"content": [
        {"type": "tool_use", "id": "m1", "name": "Bash", "input": {"command": "git status"}},
        {"type": "tool_use", "id": "e0", "name": "Edit", "input": {"file_path": os.path.join(repo, "src/Core.kt"),
                                                                   "old_string": "1", "new_string": "2"}}]}}]))
PY
ystop() { printf '{"session_id":"s-y","hook_event_name":"Stop","transcript_path":"%s"}' "$1" \
  | CLAUDE_PROJECT_DIR="$X" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
ystop "$TMP/y.jsonl"; rc=$?
[ "$rc" = 0 ] && grep -q systemMessage "$TMP/out" && grep -q "src/test/CoreTest.kt" "$TMP/out" \
  && ok "existing test edited by another session: stop allowed, warning names the file" \
  || fail "another session's test edit blocked this one (rc=$rc out='$(cat "$TMP/out")' err='$(head -3 "$TMP/err")')"
ystop "$TMP/y.jsonl"; rc=$?
[ "$rc" = 0 ] && [ ! -s "$TMP/out" ] && ok "another session's test edit: warned once per change" || fail "warning repeated (rc=$rc)"
python3 - "$X" "$TMP/y2.jsonl" <<'PY'
import json, sys, time
repo, tp = sys.argv[1], sys.argv[2]
open(tp, "w").write("".join(json.dumps(r) + "\n" for r in [
    {"type": "user", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 600)),
     "message": {"role": "user", "content": "fix it"}},
    {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "e1", "name": "Edit",
        "input": {"file_path": repo + "/src/test/CoreTest.kt", "old_string": "a", "new_string": "b"}}]}}]))
PY
echo "fun ok() = 3" > src/Core.kt
printf '{"session_id":"s-y2","hook_event_name":"Stop","transcript_path":"%s"}' "$TMP/y2.jsonl" \
  | CLAUDE_PROJECT_DIR="$X" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 2 ] && grep -q "src/test/CoreTest.kt" "$TMP/err" && ok "the same edit made by this session (Edit): still blocked" \
  || fail "own test edit not blocked (rc=$rc err='$(head -3 "$TMP/err")')"
# Only a person can clear "an existing test was edited" (review the diff, or commit it): the
# agent is told once per change; later stops of the same change go through with a reminder
# instead of blocking every turn (2026-09-25: one session was blocked on 6 consecutive stops).
y2stop() { printf '{"session_id":"s-y2","hook_event_name":"Stop","transcript_path":"%s"}' "$TMP/y2.jsonl" \
  | CLAUDE_PROJECT_DIR="$X" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
y2stop; rc=$?
[ "$rc" = 0 ] && grep -q "src/test/CoreTest.kt" "$TMP/out" && ok "own test edit awaiting human review: second stop allowed with a reminder" \
  || fail "human-review-only block repeated (rc=$rc err='$(head -2 "$TMP/err")')"
echo "fun ok() = 4" > src/Core.kt; y2stop; rc=$?
[ "$rc" = 2 ] && ok "a new change with the test edit still pending: blocked once again" || fail "new change not blocked (rc=$rc)"

# The same edit made by this session with a write-capable MCP tool (no Edit/Write, no Bash
# window): the gate cannot see the write, so it cannot call it "other" — blocked (fail closed).
python3 - "$X" "$TMP/y3.jsonl" <<'PY'
import json, os, sys, time
repo, tp = sys.argv[1], sys.argv[2]
now = time.time()
iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(t))
os.utime(os.path.join(repo, "src/test/CoreTest.kt"), (now - 120, now - 120))
with open(os.path.join(repo, ".claude/audit-gate/bash_write_ledger.tsv"), "a") as f:
    f.write("s-y3\tstart\t%.3f\tm1\ns-y3\tend\t%.3f\tm1\n" % (now - 590, now - 589))
open(tp, "w").write("".join(json.dumps(r) + "\n" for r in [
    {"type": "user", "timestamp": iso(now - 600), "message": {"role": "user", "content": "fix it"}},
    {"type": "assistant", "timestamp": iso(now - 590), "message": {"content": [
        {"type": "tool_use", "id": "m1", "name": "Bash", "input": {"command": "git status"}}]}},
    {"type": "assistant", "timestamp": iso(now - 120), "message": {"content": [
        {"type": "tool_use", "id": "j1", "name": "mcp__jetbrains__replace_text_in_file",
         "input": {"pathInProject": "src/test/CoreTest.kt", "oldText": "a", "newText": "b"}}]}}]))
PY
echo "fun ok() = 5" > src/Core.kt
printf '{"session_id":"s-y3","hook_event_name":"Stop","transcript_path":"%s"}' "$TMP/y3.jsonl" \
  | CLAUDE_PROJECT_DIR="$X" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 2 ] && grep -q "src/test/CoreTest.kt" "$TMP/err" && ok "existing test edited by this session via an MCP write tool: blocked" \
  || fail "MCP-tool test edit let through (rc=$rc out='$(cat "$TMP/out")' err='$(head -3 "$TMP/err")')"

# ── Another run holds the project's test-run lock (BUSY) ──────────────────────────────
# The Stop hook hands the gate a short lock wait (TEST_RUN_LOCK_WAIT_S=120 unless set: 900
# plus the suites could pass the hook's own 1800 s timeout), says the real cause — not
# "missing tool" — and caches nothing: the next stop runs the suite.
B="$TMP/busy"; mkdir -p "$B/src" "$B/.agents" && cd "$B" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
printf 'printf %%s "${TEST_RUN_LOCK_WAIT_S:-unset}" > "%s"\n' "$TMP/b_wait" > wait.sh
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-B","name":"core","command":"sh wait.sh"}]}]}
JSON
git add -A && git commit -qm init
printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"b-1"}' > "$TMP/b.jsonl"
hold_lock() { rm -f "$TMP/b_held"
  python3 - "$B" "$TMP/b_held" <<'PY' &
import fcntl, os, sys, time
os.makedirs(sys.argv[1] + "/.claude/audit-gate", exist_ok=True)
with open(sys.argv[1] + "/.claude/audit-gate/test_run.lock", "w") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    time.sleep(60)
PY
  b_holder=$!
  for _ in $(seq 1 50); do [ -f "$TMP/b_held" ] && break; sleep 0.1; done; }
bstop() { printf '{"session_id":"b-1","hook_event_name":"Stop","transcript_path":"%s"}' "$TMP/b.jsonl" \
  | CLAUDE_PROJECT_DIR="$B" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
no_untested_fp() { python3 -c 'import json,os,sys
d = json.load(open(sys.argv[1])) if os.path.exists(sys.argv[1]) else {}
sys.exit(1 if d.get("untested_fp") or any(s.get("result") == "untested" for s in d.get("sessions", {}).values()) else 0)' \
  "$B/.claude/audit-gate/regression_gate.state.json"; }
BUSY_MSG="một lượt chạy test khác đang giữ khoá dự án — chạy lại sau"
echo "fun ok() = 2" > src/Core.kt; rm -f "$TMP/b_wait"
hold_lock
TEST_RUN_LOCK_WAIT_S=1 bstop; rc=$?
[ "$rc" = 0 ] && grep -q "$BUSY_MSG" "$TMP/out" && ! grep -q "thiếu công cụ" "$TMP/out" && [ ! -f "$TMP/b_wait" ] \
  && ok "lock held by another run: stop allowed, says the lock is held (not a missing tool)" \
  || fail "BUSY message (rc=$rc out='$(cat "$TMP/out")' err='$(head -3 "$TMP/err")')"
no_untested_fp && ok "BUSY is not cached as UNTESTED for the tree" || fail "BUSY cached: $(cat "$B/.claude/audit-gate/regression_gate.state.json")"
TEST_RUN_LOCK_WAIT_S=1 bstop; rc=$?
[ "$rc" = 0 ] && grep -q "$BUSY_MSG" "$TMP/out" && ok "BUSY again on the same tree: said again (not once-per-change)" \
  || fail "second BUSY stop silent (rc=$rc out='$(cat "$TMP/out")')"
kill "$b_holder" 2>/dev/null; wait "$b_holder" 2>/dev/null
bstop; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$TMP/b_wait" 2>/dev/null)" = 120 ] \
  && ok "lock free: the same tree's suite runs on the next stop, with TEST_RUN_LOCK_WAIT_S=120 from the hook" \
  || fail "suite not re-run after BUSY, or wrong wait (rc=$rc wait='$(cat "$TMP/b_wait" 2>/dev/null)')"
# Degraded mode (Grok-shaped Stop) reuses the last result per tree: BUSY must not be that result.
kstop() { printf '{"hookEventName":"stop","hook_event_name":"Stop","sessionId":"k-1","session_id":"k-1","workspaceRoot":"%s","transcript_path":"%s","reason":"end_turn","stopHookActive":false}' \
    "$B" "$TMP/updates.jsonl" \
  | GROK_HOOK_EVENT=stop GROK_SESSION_ID=k-1 CLAUDE_PROJECT_DIR="$B" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
echo "fun ok() = 3" > src/Core.kt; rm -f "$TMP/b_wait"
hold_lock
TEST_RUN_LOCK_WAIT_S=1 kstop; rc=$?
[ "$rc" = 0 ] && grep -q "$BUSY_MSG" "$TMP/out" && no_untested_fp \
  && ok "degraded: BUSY said, not stored as the session's result for the tree" \
  || fail "degraded BUSY (rc=$rc out='$(cat "$TMP/out")' state=$(cat "$B/.claude/audit-gate/regression_gate.state.json"))"
kill "$b_holder" 2>/dev/null; wait "$b_holder" 2>/dev/null
kstop; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/b_wait" ] && ok "degraded: the same tree runs its suite once the lock is free" \
  || fail "degraded: BUSY result reused, suite not run (rc=$rc)"

# ── UNTESTED (untested_exit) advances verified_head; the same content is not re-run ─────
# 2026-09-29 (GeelyEx2: REG-QC-05 "test on the real car" always exits 2): exit 4 left
# verified_head stuck, so every Stop re-ran every suite for the growing --since range (4-5 min,
# 16 times). Now: the range counts as verified for what can run here, the next Stop of the same
# content runs nothing, the UNTESTED warning is still said once per change. BUSY caches nothing.
V="$TMP/untested_range"; mkdir -p "$V/src" "$V/.agents" && cd "$V" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
printf 'echo x >> "%s"\nexit 0\n' "$TMP/v_runs" > ok.sh; : > "$TMP/v_runs"
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-OK","name":"core","command":"sh ok.sh"},
  {"id":"REG-CAR","name":"real car","command":"echo x && exit 2","untested_exit":2}]}]}
JSON
git add -A && git commit -qm init
printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"v-1"}' > "$TMP/v.jsonl"
vstop() { printf '{"session_id":"v-1","hook_event_name":"Stop","transcript_path":"%s"}' "$TMP/v.jsonl" \
  | CLAUDE_PROJECT_DIR="$V" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
vruns() { grep -c x "$TMP/v_runs" | tr -d ' '; }
vhead() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verified_head") or "")' \
  "$V/.claude/audit-gate/regression_gate.state.json" 2>/dev/null; }
vstop   # clean tree: records verified_head = HEAD (the regression baseline)
base="$(git rev-parse HEAD)"; [ "$(vhead)" = "$base" ] || fail "setup: baseline not recorded ($(vhead))"
echo "fun ok() = 2" > src/Core.kt && git commit -qam "mid-work commit"
# BUSY control: another run holds the test lock — nothing cached, verified_head not advanced.
rm -f "$TMP/v_held"
python3 - "$V" "$TMP/v_held" <<'PY' &
import fcntl, os, sys, time
os.makedirs(sys.argv[1] + "/.claude/audit-gate", exist_ok=True)
with open(sys.argv[1] + "/.claude/audit-gate/test_run.lock", "w") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    time.sleep(60)
PY
v_holder=$!
for _ in $(seq 1 50); do [ -f "$TMP/v_held" ] && break; sleep 0.1; done
TEST_RUN_LOCK_WAIT_S=1 vstop; rc=$?
[ "$rc" = 0 ] && grep -q "$BUSY_MSG" "$TMP/out" && [ "$(vhead)" = "$base" ] && [ "$(vruns)" = 0 ] \
  && ok "BUSY on a --since range: verified_head not advanced, nothing ran" \
  || fail "BUSY advanced or ran (rc=$rc vh=$(vhead) base=$base runs=$(vruns) out='$(cat "$TMP/out")')"
kill "$v_holder" 2>/dev/null; wait "$v_holder" 2>/dev/null
vstop; rc=$?; n1="$(vruns)"
[ "$rc" = 0 ] && grep -q "UNTESTED" "$TMP/out" && grep -q "REG-CAR" "$TMP/out" && grep -q "KHÔNG phải PASS" "$TMP/out" \
  && [ "$n1" = 1 ] && ok "UNTESTED on a --since range: stop allowed, warning names REG-CAR, runnable suite ran once" \
  || fail "UNTESTED range stop (rc=$rc runs=$n1 out='$(cat "$TMP/out")' err='$(head -3 "$TMP/err")')"
[ "$(vhead)" = "$(git rev-parse HEAD)" ] && ok "UNTESTED advances verified_head to HEAD (like a PASS)" \
  || fail "UNTESTED left verified_head stuck at $(vhead) (HEAD $(git rev-parse HEAD))"
vstop; rc=$?; n2="$(vruns)"
[ "$rc" = 0 ] && [ "$n2" = "$n1" ] && [ ! -s "$TMP/out" ] \
  && ok "UNTESTED, same content next Stop: gate not re-run, warning not repeated" \
  || fail "UNTESTED same content re-ran the gate (rc=$rc runs ${n1} then ${n2} out='$(cat "$TMP/out")')"
echo "fun ok() = 3" > src/Core.kt; vstop; rc=$?; n3="$(vruns)"
[ "$rc" = 0 ] && [ "$n3" -gt "$n2" ] && grep -q "UNTESTED" "$TMP/out" \
  && ok "UNTESTED, new content: the gate runs again and says UNTESTED again" \
  || fail "UNTESTED new content not re-run/said (rc=$rc runs ${n2} then ${n3} out='$(cat "$TMP/out")')"

# The hook never ends a Stop on a bare full_pass.json: reusing a full PASS is post-fix-gate's
# job (cached_full_pass: tree_fp fingerprint, result format, matrix, local config, age) and the
# run keeps --session/--since. Audit 2026-09-29: a shortcut compared the receipt with
# devkit_harness.tree_fingerprint (another fingerprint) and skipped the gate on any receipt with
# exit 0 — dead only because the two fingerprints never matched.
REPO="$TMP/repo_receipt"; mkdir -p "$REPO/src" "$REPO/.agents" && cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt && echo 'exit 1' > result.sh
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core flow","command":"sh result.sh"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
python3 - "$DEVKIT_DIR/hooks" "$REPO" <<'PY'
import json, os, subprocess, sys
sys.path.insert(0, sys.argv[1])
import devkit_harness
repo = sys.argv[2]
gd = subprocess.run(["git", "-C", repo, "rev-parse", "--absolute-git-dir"], capture_output=True, text=True).stdout.strip()
os.makedirs(os.path.join(gd, "postfix-gate"), exist_ok=True)
json.dump({"exit": 0, "fingerprint": devkit_harness.tree_fingerprint(repo)}, open(os.path.join(gd, "postfix-gate", "full_pass.json"), "w"))
PY
stop; rc=$?
[ "$rc" = 2 ] && grep -q "REG-1" "$TMP/err" \
  && ok "a bare exit-0 full_pass.json does not end the Stop: the gate runs and the failing REG-1 blocks" \
  || fail "the hook trusted a bare full_pass.json and skipped the gate (rc=$rc)"

# The skip keys (pass_fp / untested_fp) must cover the CONTENT of untracked files: fp hashes
# status + `git diff HEAD`, so an edit inside a new untracked file left the key unchanged and the
# next Stop skipped the suites (review 2026-09-29). Both the PASS and the UNTESTED path.
for kind in pass untested; do
  REPO="$TMP/repo_ukey_$kind"; mkdir -p "$REPO/src" "$REPO/.agents" && cd "$REPO" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf '! grep -rq BUG src\n' > ok.sh
  if [ "$kind" = untested ]; then
    extra=',{"id":"REG-CAR","name":"on the car","command":"exit 2","untested_exit":2}'
  else extra=''; fi
  cat > .agents/regression_matrix.active.json <<JSON
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-OK","name":"no BUG in src","command":"sh ok.sh"}$extra]}]}
JSON
  echo "fun ok() = 1" > src/Core.kt; git add -A && git commit -qm init
  echo "fun n() = 1" > src/New.kt          # untracked, clean
  stop; rc1=$?
  echo "fun n() = BUG" > src/New.kt        # same untracked file, content now fails REG-OK
  stop; rc2=$?
  [ "$rc1" = 0 ] && [ "$rc2" = 2 ] && grep -q "REG-OK" "$TMP/err" \
    && ok "$kind: an edit inside an untracked file is not skipped — REG-OK runs and blocks" \
    || fail "$kind: untracked content edit skipped the suites (rc $rc1 then $rc2)"
done
# ── A session that wrote nothing here is not gated for another agent's change ────────────
# 2026-10-02 (agent-workbench): every Stop re-ran the whole matrix (~11 min a run, 27 min seen) for
# a 301-file diff another agent had made while this session only read. Evidence that a session
# wrote a changed file: its Edit/Write paths, a write verb naming it (or a path held in a variable),
# the file's mtime inside one of its own Bash windows (bash_write_ledger.tsv). A tool that may
# write unseen, or no usable transcript, keeps the gate (fail closed). REGRESSION_GATE_ALL_SESSIONS=1
# turns the shortcut off.
W="$TMP/readonly"; mkdir -p "$W/src" "$W/.agents" && cd "$W" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
printf 'echo x >> "%s"\nexit 1\n' "$TMP/w_runs" > result.sh; : > "$TMP/w_runs"
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-W","name":"core","command":"sh result.sh"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt            # another agent's uncommitted change
wruns() { grep -c x "$TMP/w_runs" | tr -d ' '; }
# wtrace <name> <tool_use json>…: a Claude transcript whose assistant turn made these calls (@REPO@ = $W)
wtrace() { python3 - "$TMP/$1.jsonl" "$W" "${@:2}" <<'PY'
import json, sys, time
tp, repo, uses = sys.argv[1], sys.argv[2], sys.argv[3:]
blocks = [dict(json.loads(u.replace("@REPO@", repo)), type="tool_use", id="t%d" % i) for i, u in enumerate(uses)]
iso = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 600))
open(tp, "w").write(json.dumps({"type": "user", "timestamp": iso, "message": {"role": "user", "content": "look"}}) + "\n"
                    + json.dumps({"type": "assistant", "timestamp": iso, "message": {"content": blocks}}) + "\n")
PY
}
# wstop <session> <transcript> [reply]: the reply defaults to a plain one that claims no outcome
wstop() { python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"hook_event_name":"Stop","transcript_path":sys.argv[2],"last_assistant_message":sys.argv[3]}))' \
    "$1" "$TMP/$2.jsonl" "${3-Đây là phần giải thích: gate chạy ba bước.}" \
  | CLAUDE_PROJECT_DIR="$W" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
# a blocking case needs a new tree each time: the loop guard releases the third block of one tree
newtree() { echo "fun ok() = $1" > "$W/src/Core.kt"; }

wtrace w_ro '{"name":"Read","input":{"file_path":"@REPO@/src/Core.kt"}}' '{"name":"Bash","input":{"command":"git status"}}'
wstop w-ro w_ro; rc=$?
[ "$rc" = 0 ] && [ "$(wruns)" = 0 ] && grep -q systemMessage "$TMP/out" && grep -q 'không ghi file' "$TMP/out" && grep -q 'KHÔNG phải PASS' "$TMP/out" \
  && ok "read-only session: the dirty tree is another agent's — suites not run, said (not a PASS)" \
  || fail "read-only session still gated (rc=$rc runs=$(wruns) out='$(cat "$TMP/out")' err='$(head -2 "$TMP/err")')"
wstop w-ro w_ro; rc=$?
[ "$rc" = 0 ] && [ ! -s "$TMP/out" ] && [ "$(wruns)" = 0 ] && ok "read-only session: said once per session" \
  || fail "read-only notice repeated or suites ran (rc=$rc runs=$(wruns) out='$(cat "$TMP/out")')"

wtrace w_out '{"name":"Write","input":{"file_path":"/tmp/elsewhere/x.md","content":"x"}}'
newtree 3; wstop w-out w_out; rc=$?
[ "$rc" = 0 ] && [ "$(wruns)" = 0 ] && ok "session that only wrote OUTSIDE this checkout: not gated" || fail "outside write gated (rc=$rc runs=$(wruns))"

wtrace w_ed '{"name":"Edit","input":{"file_path":"@REPO@/src/Core.kt","old_string":"a","new_string":"b"}}'
newtree 4; wstop w-ed w_ed; rc=$?
[ "$rc" = 2 ] && [ "$(wruns)" -gt 0 ] && grep -q REG-W "$TMP/err" && ok "session that edited a changed file (Edit): gated as before" || fail "Edit session not gated (rc=$rc runs=$(wruns))"

wtrace w_sed '{"name":"Bash","input":{"command":"sed -i s/a/b/ src/Core.kt"}}'
newtree 5; n0="$(wruns)"; wstop w-sed w_sed; rc=$?
[ "$rc" = 2 ] && [ "$(wruns)" -gt "$n0" ] && ok "write verb naming a changed file (sed -i): gated" || fail "sed -i session not gated (rc=$rc)"

wtrace w_var '{"name":"Bash","input":{"command":"F=src/Core.kt; sed -i s/a/b/ $F"}}'
newtree 6; n0="$(wruns)"; wstop w-var w_var; rc=$?
[ "$rc" = 2 ] && [ "$(wruns)" -gt "$n0" ] && ok "a path held in a shell variable cannot be matched to a file: gated (fail closed)" || fail "variable-path session skipped (rc=$rc)"

wtrace w_bw '{"name":"Bash","input":{"command":"python3 gen.py"}}'
mkdir -p .claude/audit-gate
python3 - "$W/.claude/audit-gate/bash_write_ledger.tsv" <<'PY'
import sys, time
now = time.time()
open(sys.argv[1], "a").write("w-bw\tstart\t%.3f\tb1\nw-bw\tend\t%.3f\tb1\n" % (now - 5, now + 60))
PY
newtree 7; n0="$(wruns)"; wstop w-bw w_bw; rc=$?
[ "$rc" = 2 ] && [ "$(wruns)" -gt "$n0" ] && ok "changed file written inside the session's own Bash window: gated" || fail "own-window write skipped (rc=$rc)"

wtrace w_op '{"name":"mcp__foo__do_thing","input":{}}'
newtree 8; n0="$(wruns)"; wstop w-op w_op; rc=$?
[ "$rc" = 2 ] && [ "$(wruns)" -gt "$n0" ] && ok "a tool that may write unseen (opaque MCP tool): gated (fail closed)" || fail "opaque-tool session skipped (rc=$rc)"

newtree 10; n0="$(wruns)"; wstop w-xong w_ro "XONG"; rc=$?
[ "$rc" = 2 ] && [ "$(wruns)" -gt "$n0" ] && ok "read-only session whose reply claims XONG: gated (a claim is verified)" || fail "XONG reply skipped (rc=$rc)"
newtree 11; n0="$(wruns)"; wstop w-empty w_ro ""; rc=$?
[ "$rc" = 2 ] && [ "$(wruns)" -gt "$n0" ] && ok "read-only session with no reply text: gated (fail closed)" || fail "empty reply skipped (rc=$rc)"
newtree 12; n0="$(wruns)"; wtrace w_push '{"name":"Bash","input":{"command":"git push origin main"}}'; wstop w-push w_push; rc=$?
[ "$rc" = 2 ] && [ "$(wruns)" -gt "$n0" ] && ok "read-only session that pushed this turn: gated (a push is a handover)" || fail "push turn skipped (rc=$rc)"
newtree 13; n0="$(wruns)"; DEVKIT_GATE_EVERY_STOP=1 wstop w-every w_ro; rc=$?
[ "$rc" = 2 ] && [ "$(wruns)" -gt "$n0" ] && ok "DEVKIT_GATE_EVERY_STOP=1: even a read-only session is gated" || fail "EVERY_STOP ignored (rc=$rc)"
newtree 9; n0="$(wruns)"; REGRESSION_GATE_ALL_SESSIONS=1 wstop w-all w_ro; rc=$?
[ "$rc" = 2 ] && [ "$(wruns)" -gt "$n0" ] && ok "REGRESSION_GATE_ALL_SESSIONS=1: even a read-only session is gated" || fail "opt-out ignored (rc=$rc)"
cd "$TMP" || exit 1

# ── A total time budget for one Stop run ─────────────────────────────────────────────────
# 2026-10-02 (agent-workbench): ~10 suites in a row, 600 s each and no total cap — a Stop ran 27 minutes
# until the hook's own 1800 s timeout cut it without a word. GATE_TOTAL_BUDGET_S (the hook passes
# REGRESSION_GATE_BUDGET_S, default 900) stops STARTING suites once the time is spent: the rest are
# UNTESTED (label BUDGET), never PASS, exit 4, and nothing is cached for the tree (the next Stop runs again).
BG="$TMP/budget"; mkdir -p "$BG/src" "$BG/.agents" && cd "$BG" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
for n in 1 2 3; do printf 'echo x >> "%s"\nsleep 2\nexit 0\n' "$TMP/bg_runs" > "s$n.sh"; done; : > "$TMP/bg_runs"
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-B1","name":"one","command":"sh s1.sh"},
  {"id":"REG-B2","name":"two","command":"sh s2.sh"},{"id":"REG-B3","name":"three","command":"sh s3.sh"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
bgruns() { grep -c x "$TMP/bg_runs" | tr -d ' '; }
bgstop() { printf '{"session_id":"bg-1","hook_event_name":"Stop"}' | CLAUDE_PROJECT_DIR="$BG" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }

# the gate itself: after the budget no new suite starts
CLAUDE_PROJECT_DIR="$BG" GATE_TOTAL_BUDGET_S=1 python3 "$DEVKIT_DIR/bin/post-fix-gate.py" --run-tests --json >"$TMP/bg_gate.out" 2>/dev/null; rc=$?
python3 - "$TMP/bg_gate.out" "$rc" <<'PY' && ok "gate: budget spent after the first suite — the other two are UNTESTED/BUDGET, exit 4, not a PASS" || fail "gate budget (see $TMP/bg_gate.out)"
import json, sys
rc = int(sys.argv[2])
last = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.startswith("{")][-1]
d = json.loads(last)
st = {t["id"]: (t["status"], t.get("label")) for t in d["regression_tests"]}
assert rc == 4 and d.get("exit_code") == 4, (rc, d.get("exit_code"))
assert d.get("budget_exhausted") is True, d.get("budget_exhausted")
assert st["REG-B1"][0] == "PASS", st
assert st["REG-B2"] == ("UNTESTED", "BUDGET") and st["REG-B3"] == ("UNTESTED", "BUDGET"), st
PY

# the Stop hook: says so, lets the stop through (nothing to fix in the change), caches nothing
: > "$TMP/bg_runs"; echo "fun ok() = 3" > src/Core.kt
REGRESSION_GATE_BUDGET_S=3 bgstop; rc=$?
[ "$rc" = 0 ] && [ "$(bgruns)" = 2 ] && grep -q systemMessage "$TMP/out" && grep -q 'ngân sách' "$TMP/out" && grep -q 'REG-B3' "$TMP/out" && grep -q 'KHÔNG phải PASS' "$TMP/out" \
  && ok "hook: budget spent mid-run — stop allowed, the message names the suite left, not a PASS" \
  || fail "hook budget (rc=$rc runs=$(bgruns) out='$(cat "$TMP/out")' err='$(head -2 "$TMP/err")')"
python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
sys.exit(1 if d.get("pass_fp") or d.get("untested_fp") or any(s.get("result") for s in d.get("sessions", {}).values()) else 0)' \
  "$BG/.claude/audit-gate/regression_gate.state.json" && ok "hook: a budget-cut run is cached as nothing (no pass_fp / untested_fp / session result)" \
  || fail "budget cut cached: $(cat "$BG/.claude/audit-gate/regression_gate.state.json")"
n0="$(bgruns)"; REGRESSION_GATE_BUDGET_S=3 bgstop
[ "$(bgruns)" -gt "$n0" ] && ok "hook: the same tree runs its suites again on the next stop" || fail "budget-cut tree not re-run (runs $n0 then $(bgruns))"

# without a budget in the way (default 900 s) every suite runs
: > "$TMP/bg_runs"; echo "fun ok() = 4" > src/Core.kt
bgstop; rc=$?
[ "$rc" = 0 ] && [ "$(bgruns)" = 3 ] && ! grep -q 'ngân sách' "$TMP/out" && ok "hook: default budget (900 s) does not cut a short run — all 3 suites ran" \
  || fail "default budget cut the run (rc=$rc runs=$(bgruns) out='$(cat "$TMP/out")')"
cd "$TMP" || exit 1

if [ "$FAILS" -ne 0 ]; then echo "regression gate hook: $FAILS FAILED"; exit 1; fi
echo "regression gate hook: all checks passed"
