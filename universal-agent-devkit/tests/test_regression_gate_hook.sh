#!/usr/bin/env bash
# Regression test: hooks/regression_gate.sh (Stop hook) blocks finishing while a
# related regression test fails or a changed source file has no test — only for a
# project that adopted its own matrix — and never traps the session.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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
        {"type": "tool_use", "id": "m1", "name": "Bash", "input": {"command": "git status"}}]}}]))
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

if [ "$FAILS" -ne 0 ]; then echo "regression gate hook: $FAILS FAILED"; exit 1; fi
echo "regression gate hook: all checks passed"
