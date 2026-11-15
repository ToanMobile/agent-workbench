#!/usr/bin/env bash
# #632 B (AC 1-3), at the gate: post-fix-gate --run-tests on a PR that weakens an existing test, approved only through the
# antigravity-pm record (source 3, _pm_audit_cross_review). Seal mode on (test pubkey):
#  E1 hand-written record (verdict pass, reviewer antigravity, auditedHead = PR head), no seal -> exit 2;
#  E2 the same record + a valid seal of the PR head -> exit 0 (duyệt chéo bởi antigravity);
#  E3 seal signed by another key -> exit 2;  E4 valid seal for another head only -> exit 2;
#  E5 valid seal whose signed base is the weakening commit (helper pointed at a fake trunk) -> exit 2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_MERGE_CHECK CI
unset CLAUDECODE GROK_SESSION_ID GROK_WORKSPACE_ROOT GROK_HOOK_EVENT
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/projects"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
export DEVKIT_PM_HOME_TEST=1
export GIT_CONFIG_GLOBAL=/dev/null
export DEVKIT_VERDICT_SEAL_PUB="$TMP/seal.pub"
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
R="$TMP/r"; mkdir -p "$R/src" "$R/tests" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf '.claude/audit-gate/\n' > .gitignore
mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/t.sh"}]}]}
JSON
echo 'fun ok()=1' > src/Core.kt; printf '#!/bin/sh\ngrep -q "ok" src/Core.kt\ngrep -q "fun" src/Core.kt\n' > tests/t.sh
git add -A && git commit -qm M0
git checkout -q -b feat
printf '#!/bin/sh\ngrep -q "ok" src/Core.kt\n' > tests/t.sh; echo 'fun ok()=2' > src/Core.kt; git commit -qam weaken
WEAK="$(git rev-parse HEAD)"
echo 'fun ok()=3' > src/Core.kt; git commit -qam harmless
HEAD_SHA="$(git rev-parse HEAD)"
python3 - "$DEVKIT_DIR/bin" "$TMP" "$R" "$HEAD_SHA" <<'PY'
import base64, json, os, subprocess, sys
sys.path.insert(0, sys.argv[1]); import verdict_seal as vs
tmp, repo, head = sys.argv[2:5]
open(os.path.join(tmp, "seal.pub"), "w").write(base64.b64encode(vs.public_key(b"\x05" * 32)).decode())
g = lambda *a: subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True).stdout.strip()
mb = g("merge-base", "main", head)
d = os.path.join(tmp, "pm", "projects", "p", "tasks", "T0001-e2e"); os.makedirs(d)
json.dump({"id": "T0001-e2e", "project": os.path.realpath(repo),
           "dispatches": [{"kind": "audit", "agent": "antigravity", "at": "2026-11-15T00:00:00Z", "auditedHead": head,
                           "verdict": "pass", "auditBase": mb, "edited": ["tests/t.sh", "src/Core.kt"]}],
           "verdicts": {"audit": {"verdict": "pass", "round": 1, "reviewer": "antigravity", "notes": "ok", "auditedHead": head},
                        "auditHistory": [{"auditedHead": head, "reviewer": "antigravity", "at": "2026-11-15T00:00:01Z"}]}},
          open(os.path.join(d, "task.json"), "w"))
PY
seal() {   # seal <head> <key byte> <base>
  python3 - "$DEVKIT_DIR/bin" "$R" "$1" "$2" "$3" <<'PY'
import base64, json, os, subprocess, sys
sys.path.insert(0, sys.argv[1]); import verdict_seal as vs
repo, head, kb, base = sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
tree = subprocess.run(["git", "-C", repo, "rev-parse", head + "^{tree}"], capture_output=True, text=True).stdout.strip()
p = json.dumps({"v": 1, "head": head, "tree": tree, "base": base, "edited": ["src/Core.kt", "tests/t.sh"], "verdict": "pass",
                "ts": "t", "nonce": "n"}, sort_keys=True, separators=(",", ":"))
os.makedirs(os.path.dirname(vs.seal_path(head)), exist_ok=True)
json.dump({"payload": p, "sig": base64.b64encode(vs.sign(bytes([kb]) * 32, p.encode())).decode()}, open(vs.seal_path(head), "w"))
PY
}
run_gate() { OUT="$(cd "$R" && CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?; }
accepted() { [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qF "duyệt chéo bởi antigravity (task T0001-e2e)"; }
MB="$(git merge-base main "$HEAD_SHA")"
rm -rf "$TMP/pm/seals"; run_gate
[ "$RC" = 2 ] && ok "E1 hand-written record, no seal -> exit 2" || bad "E1 rc=$RC"
seal "$HEAD_SHA" 5 "$MB"; run_gate
accepted && ok "E2 valid seal -> exit 0" || { bad "E2 rc=$RC"; printf '%s' "$OUT" | tail -8; }
seal "$HEAD_SHA" 6 "$MB"; run_gate
[ "$RC" = 2 ] && ok "E3 seal signed by another key -> exit 2" || bad "E3 rc=$RC"
rm -rf "$TMP/pm/seals"; seal "$WEAK" 5 "$MB"; run_gate
[ "$RC" = 2 ] && ok "E4 seal for another head only -> exit 2" || bad "E4 rc=$RC"
rm -rf "$TMP/pm/seals"; seal "$HEAD_SHA" 5 "$WEAK"; run_gate
[ "$RC" = 2 ] && ok "E5 signed base = weakening commit -> exit 2" || bad "E5 rc=$RC"
[ "$FAILS" -eq 0 ] && echo "ALL OK" || { echo "FAILS=$FAILS"; exit 1; }
