#!/usr/bin/env bash
# #859: a PR that edits an existing test needs no approved-head / edited-tests comment from another session: the gate reads the
# antigravity-pm verdict (auditedHead) itself. Offline: scratch repos, fake pm home under a temp dir, real post-fix-gate.py + installer.
#  V1 verdict at the PR head, no comment, no json -> approved (gate exit 0, "duyệt chéo bởi antigravity (task ...)"), installer says pm.
#  R1 verdict for an OLDER head, PR moved on  -> refused.      R2 file approved_tests.json names a task id with no PM record -> refused.
#  R3 session agent == verdict reviewer       -> refused.      R4 agent-written approved_tests.json (valid sha, fake task) -> refused.
#  R5 verdict recorded for another task id than the one in the file -> never approves under that id.
#  C1 comment branch unchanged: installer --has-edited-tests with an OWNER approved-head comment still prints "true".
set -u
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_MERGE_CHECK CI CLAUDECODE GROK_SESSION_ID GROK_WORKSPACE_ROOT GROK_HOOK_EVENT
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.agents/devkit/bin/post-fix-gate.py"
INS="$ROOT/.claude/bin/super-board-install-edited-test-approval.sh"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/projects"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm" DEVKIT_PM_HOME_TEST=1 GIT_CONFIG_GLOBAL=/dev/null
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
pm_ag() {   # pm_ag <task-id> <repo> <auditedHead>: Antigravity audit pass with the full scope PM records
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  python3 - "$TMP/pm/projects/p-$1/tasks/$1/task.json" "$1" "$(cd "$2" && pwd -P)" "$3" <<'PY'
import json, subprocess, sys
dest, tid, proj, head = sys.argv[1:5]
g = lambda *a: subprocess.run(["git", "-C", proj, *a], capture_output=True, text=True).stdout.strip()
mb = g("merge-base", "main", head)
ns = g("diff", "--name-status", "--no-renames", mb, head).splitlines()
edited = [l.split("\t", 1)[1] for l in ns if l[:1] in "MDT"]
disp = {"kind": "audit", "agent": "antigravity", "at": "2026-11-04T00:00:00Z", "auditedHead": head, "verdict": "pass",
        "auditBase": mb, "edited": edited}
json.dump({"id": tid, "project": proj, "dispatches": [disp], "verdicts": {
    "audit": {"verdict": "pass", "round": 1, "reviewer": "antigravity", "notes": "ok", "auditedHead": head},
    "auditHistory": [{"auditedHead": head, "reviewer": "antigravity", "at": "2026-11-04T00:00:01Z"}]}}, open(dest, "w"))
PY
}
V0='#!/bin/sh\ngrep -q "ok" src/Core.kt\ngrep -q "fun" src/Core.kt\n'
V1='#!/bin/sh\ngrep -q "ok()" src/Core.kt\ngrep -q "fun" src/Core.kt\n'
mk() {
  mkdir -p "$1/src" "$1/tests" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf '.claude/audit-gate/\n' > .gitignore
  mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/t.sh"}]}]}
JSON
  echo 'fun ok()=1' > src/Core.kt; printf "$V0" > tests/t.sh
  git add -A && git commit -qm "M0" && git checkout -q -b feat
}
pr_commit() { printf "$1" > tests/t.sh; echo "fun ok()=$RANDOM" > src/Core.kt; git commit -qam "$2"; git rev-parse HEAD; }
run_gate() { local d="$1"; shift; OUT="$(cd "$d" && env "$@" CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?; }
accepted() { [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity (task $1)"; }
refused()  { [ "$RC" = 2 ] && ! has "duyệt chéo bởi"; }
tailout()  { printf '%s' "$OUT" | grep -E "Duyệt test|duyệt chéo|Test đã có|CHƯA XÁC MINH|exit" | tail -3 | cut -c1-200; }
write_json() {   # write_json <repo> <task> <reviewer>: agent-written approved_tests.json with the file's real sha256
  mkdir -p "$1/.claude/audit-gate"
  python3 - "$1" "$2" "$3" <<'PY'
import hashlib, json, sys
r, task, rv = sys.argv[1:4]
d = hashlib.sha256(open(r + "/tests/t.sh", "rb").read()).hexdigest()
json.dump({"approvals": [{"path": "tests/t.sh", "sha256": d, "reviewer": rv, "author": "claude", "task_id": task, "reason": "r"}]},
          open(r + "/.claude/audit-gate/approved_tests.json", "w"))
PY
}
echo '{"comments":[]}' > "$TMP/meta0.json"

# V1: no comment, no json, real verdict at the PR head
mk "$TMP/v1"; X="$(pr_commit "$V1" "PR edits test")"; pm_ag T5901-v1 "$TMP/v1" "$X"; run_gate "$TMP/v1"
if accepted T5901-v1 && [ ! -e "$TMP/v1/.claude/audit-gate/approved_tests.json" ]; then ok "V1: verdict at the PR head, no comment/json -> approved"
else bad "V1: rc=$RC $(tailout)"; fi
got="$(bash "$INS" --has-edited-tests "$TMP/meta0.json" "$X" --top "$TMP/v1" --base main 2>/dev/null)"
[ "$got" = pm ] && ok "V1b: merge-gate installer reads the verdict (pm) with no comment" || bad "V1b: installer said '$got' (want pm)"

# R1: verdict is for the older head; the PR moved on with another commit touching the test
mk "$TMP/r1"; X="$(pr_commit "$V1" "PR edits test")"; pm_ag T5902-r1 "$TMP/r1" "$X"
printf '%s\ngrep -q "=" src/Core.kt\n' "$(printf "$V1")" > tests/t.sh; git commit -qam "later edit"
run_gate "$TMP/r1"
if refused; then ok "R1: verdict at an older head, PR head moved -> refused"; else bad "R1: rc=$RC $(tailout)"; fi

# R2 / R4: agent-written approved_tests.json naming a task id that has no PM record
mk "$TMP/r2"; X="$(pr_commit "$V1" "PR edits test")"; write_json "$TMP/r2" T5999-fake antigravity; run_gate "$TMP/r2"
if refused; then ok "R2/R4: agent-written file, task id with no verdict -> refused"; else bad "R2/R4: rc=$RC $(tailout)"; fi

# R5: a real verdict exists, but the file names a different task id
mk "$TMP/r5"; X="$(pr_commit "$V1" "PR edits test")"; pm_ag T5905-real "$TMP/r5" "$X"; write_json "$TMP/r5" T5906-other antigravity
run_gate "$TMP/r5" DEVKIT_AGENT_ID=claude
if ! has "(task T5906-other)"; then ok "R5: file naming another task id never approves under that id"; else bad "R5: rc=$RC $(tailout)"; fi

# R3: the running session is the verdict's reviewer (builder == reviewer)
mk "$TMP/r3"; X="$(pr_commit "$V1" "PR edits test")"; pm_ag T5903-r3 "$TMP/r3" "$X"; run_gate "$TMP/r3" DEVKIT_AGENT_ID=antigravity
if refused; then ok "R3: session agent == verdict reviewer -> refused"; else bad "R3: rc=$RC $(tailout)"; fi

# C1: comment branch unchanged
mk "$TMP/c1"; X="$(pr_commit "$V1" "PR edits test")"
python3 - "$TMP/meta1.json" "$X" <<'PY'
import json, sys
dest, sha = sys.argv[1:3]
body = ("approved-head:%s\napproved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude\",\"task_id\":\"T5907-c1\",\"gate_receipt\":\"fp\"}\n"
        "edited-tests: [{\"path\":\"tests/t.sh\",\"sha256\":\"%s\",\"reviewer\":\"antigravity\",\"author\":\"claude\",\"task_id\":\"T5907-c1\",\"reason\":\"r\"}]\n" % (sha, "0" * 64))
json.dump({"comments": [{"authorAssociation": "OWNER", "body": body}]}, open(dest, "w"))
PY
got="$(bash "$INS" --has-edited-tests "$TMP/meta1.json" "$X" --top "$TMP/c1" --base main 2>/dev/null)"
[ "$got" = true ] && ok "C1: comment branch still yields true" || bad "C1: installer said '$got' (want true)"

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
