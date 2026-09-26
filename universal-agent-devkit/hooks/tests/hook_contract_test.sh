#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# hook_contract_test.sh — regression harness for the gate layer.
#
# CLAUDE.md § TẦNG GATE MÁY listed as residual #1: "không có harness test nào
# được commit cho bất kỳ hook nào — regression ở 5 gate chặn thật hiện không
# phát hiện được". This is that harness. Measured 2026-07-28: a false positive
# in test_evidence_gate.sh (a quoted PROHIBITION read as a test-pass claim)
# reached a live turn and blocked a documentation answer; nothing would have
# caught it before a human did.
#
# The expectations below are derived from each hook's own documented contract
# (its header block), NOT from observing what the code currently does — a test
# written to match current behaviour proves nothing. When a case fails, either
# the hook or its documented contract is wrong; both are findings.
#
# ISOLATION: every case runs with CLAUDE_PROJECT_DIR pointed at a fresh temp
# sandbox, so hooks write their logs/state there and read fixture files from
# there. The real repo's .claude/audit-gate is never touched. No gradle, no
# network, no device.
#
# WHAT THIS CANNOT DO:
#   • prove a gate catches every case of its rule — these are contract points,
#     not a proof of coverage;
#   • test testsourceset_gate's real compile path (it shells out to ./gradlew);
#     only its documented SKIP paths are covered here;
#   • say anything about whether the RULE behind a gate is the right rule.
#
# Usage: bash .claude/hooks/tests/hook_contract_test.sh
# Exit 0 = every contract point holds. Exit 1 = at least one deviation.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOKS="$(cd "${HERE}/.." && pwd)"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/hookharness.XXXXXX")"
trap 'rm -rf "${SANDBOX}"' EXIT
mkdir -p "${SANDBOX}/.claude/audit-gate"

PASS=0; FAIL=0; FAILED_CASES=""

# run_case <name> <hook.sh> <expected_exit> <stdin-json> [ENV=VAL ...]
run_case() {
  name="$1"; hook="$2"; want="$3"; payload="$4"; shift 4
  out="$(printf '%s' "${payload}" | env CLAUDE_PROJECT_DIR="${SANDBOX}" "$@" \
        bash "${HOOKS}/${hook}" 2>&1)"
  got=$?
  if [ "${got}" -eq "${want}" ]; then
    PASS=$((PASS + 1))
    printf '  ok   %-46s exit=%s\n' "${name}" "${got}"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES}
  ✗ ${name}
      hook=${hook} want exit=${want}, got=${got}
      output: $(printf '%s' "${out}" | head -3 | tr '\n' ' ')"
    printf '  FAIL %-46s want=%s got=%s\n' "${name}" "${want}" "${got}"
  fi
}

# ── fixtures ────────────────────────────────────────────────────────────────
KT_UNSEEN="${SANDBOX}/Unseen.kt"
KT_SEEN="${SANDBOX}/Seen.kt"
printf 'class Unseen\n' > "${KT_UNSEEN}"
printf 'class Seen\n'   > "${KT_SEEN}"

EMPTY_TR="${SANDBOX}/empty.jsonl"
: > "${EMPTY_TR}"

# read ledger: what read_ledger.sh writes at PostToolUse:Read, and the source
# precode_gate consults for the turn currently running (the transcript on disk
# lags a whole turn behind). Seeded for session SESS-A only, so the same file
# under a different session must still be treated as unseen.
LEDGER_DIR="${SANDBOX}/.claude/audit-gate"
mkdir -p "${LEDGER_DIR}"
LEDGER="${LEDGER_DIR}/read_ledger.tsv"
# Ledger entries are resolved absolute paths (QA K-9: basename matching let a
# Read of a/Util.kt unlock an Edit of b/Util.kt).
python3 -c 'import os,sys; open(sys.argv[1],"w").write("SESS-A\t"+os.path.realpath(sys.argv[2])+"\n")' "${LEDGER}" "${KT_SEEN}"

# transcript: a Read of Seen.kt (satisfies precode_gate box 2)
SEEN_TR="${SANDBOX}/seen.jsonl"
python3 - "$SEEN_TR" "$KT_SEEN" <<'PY'
import json, sys
path, kt = sys.argv[1], sys.argv[2]
rec = {"message": {"content": [
    {"type": "tool_use", "name": "Read", "input": {"file_path": kt}}]}}
open(path, "w").write(json.dumps(rec) + "\n")
PY

# transcript: 3 consecutive edits of one file, no evidence-producing call between
CHURN_TR="${SANDBOX}/churn.jsonl"
python3 - "$CHURN_TR" "$KT_SEEN" <<'PY'
import json, sys
path, kt = sys.argv[1], sys.argv[2]
lines = []
for _ in range(3):
    lines.append(json.dumps({"message": {"content": [
        {"type": "tool_use", "name": "Edit",
         "input": {"file_path": kt, "old_string": "a", "new_string": "b"}}]}}))
open(path, "w").write("\n".join(lines) + "\n")
PY

# transcript: edits of one file WITH an evidence call (Bash) in between
EVID_TR="${SANDBOX}/evidence.jsonl"
python3 - "$EVID_TR" "$KT_SEEN" <<'PY'
import json, sys
path, kt = sys.argv[1], sys.argv[2]
edit = {"type": "tool_use", "name": "Edit",
        "input": {"file_path": kt, "old_string": "a", "new_string": "b"}}
bash = {"type": "tool_use", "name": "Bash",
        "input": {"command": "./gradlew :app:testDebugUnitTest"}}
lines = [json.dumps({"message": {"content": [c]}}) for c in (edit, bash, edit, bash, edit)]
open(path, "w").write("\n".join(lines) + "\n")
PY

# reverse-scan order: evidence first, then 3 edits (warns); 3 edits then evidence
# (quiet); 3 edits where one was blocked (its is_error result follows it — quiet)
CHURN_AFTER_TR="${SANDBOX}/churn-after-evidence.jsonl"
CHURN_BEFORE_TR="${SANDBOX}/churn-before-evidence.jsonl"
CHURN_ERR_TR="${SANDBOX}/churn-errored.jsonl"
python3 - "$CHURN_AFTER_TR" "$CHURN_BEFORE_TR" "$CHURN_ERR_TR" "$KT_SEEN" <<'PY'
import json, sys
after, before, err, kt = sys.argv[1:5]
def edit(i):
    return {"type": "tool_use", "id": f"e{i}", "name": "Edit",
            "input": {"file_path": kt, "old_string": "a", "new_string": "b"}}
bash = {"type": "tool_use", "id": "b1", "name": "Bash", "input": {"command": "./gradlew test"}}
failed = {"type": "tool_result", "tool_use_id": "e2", "is_error": True, "content": "blocked"}
def write(path, blocks):
    open(path, "w").write("\n".join(json.dumps({"message": {"content": [b]}}) for b in blocks) + "\n")
write(after, [bash, edit(1), edit(2), edit(3)])
write(before, [edit(1), edit(2), edit(3), bash])
write(err, [edit(1), edit(2), failed, edit(3)])
PY

DEVICE_ONLY_TR="${SANDBOX}/device-only.jsonl"
python3 - "$DEVICE_ONLY_TR" <<'PY'
import json, sys
path = sys.argv[1]
record = {"message": {"content": [{
    "type": "tool_use",
    "name": "Bash",
    "input": {"command": "adb devices"},
}]}}
open(path, "w").write(json.dumps(record) + "\n")
PY

ANONYMOUS_FIX_PROOF_TR="${SANDBOX}/anonymous-fix-proof.jsonl"
BASH_FIX_PROOF_TR="${SANDBOX}/bash-fix-proof.jsonl"
ERROR_FIX_PROOF_TR="${SANDBOX}/error-fix-proof.jsonl"
MISSING_PROVENANCE_TR="${SANDBOX}/missing-provenance.jsonl"
STALE_FIX_PROOF_TR="${SANDBOX}/stale-fix-proof.jsonl"
FAILED_EDIT_AFTER_PROOF_TR="${SANDBOX}/failed-edit-after-proof.jsonl"
UNKNOWN_EDIT_AFTER_PROOF_TR="${SANDBOX}/unknown-edit-after-proof.jsonl"
WRITER_AFTER_PROOF_TR="${SANDBOX}/writer-after-proof.jsonl"
ERROR_WRITER_AFTER_PROOF_TR="${SANDBOX}/error-writer-after-proof.jsonl"
ERROR_WRITE_AFTER_PROOF_TR="${SANDBOX}/error-write-after-proof.jsonl"
INTERLEAVED_WRITE_PROOF_TR="${SANDBOX}/interleaved-write-proof.jsonl"
OPEN_WRITE_BEFORE_PROOF_TR="${SANDBOX}/open-write-before-proof.jsonl"
LATE_WRITE_RESULT_PROOF_TR="${SANDBOX}/late-write-result-proof.jsonl"
CORRELATED_FIX_PROOF_TR="${SANDBOX}/correlated-fix-proof.jsonl"
CORRELATED_SCRIPT_PROOF_TR="${SANDBOX}/correlated-script-proof.jsonl"
FORGED_SCRIPT_PROOF_TR="${SANDBOX}/forged-script-proof.jsonl"
MIXED_LOCATOR_PROOF_TR="${SANDBOX}/mixed-locator-proof.jsonl"
CORRELATED_SKILL_PROOF_TR="${SANDBOX}/correlated-skill-proof.jsonl"
UNRELATED_RED_GREEN_TR="${SANDBOX}/unrelated-red-green.jsonl"
python3 - \
  "$ANONYMOUS_FIX_PROOF_TR" \
  "$BASH_FIX_PROOF_TR" \
  "$ERROR_FIX_PROOF_TR" \
  "$MISSING_PROVENANCE_TR" \
  "$STALE_FIX_PROOF_TR" \
  "$FAILED_EDIT_AFTER_PROOF_TR" \
  "$UNKNOWN_EDIT_AFTER_PROOF_TR" \
  "$WRITER_AFTER_PROOF_TR" \
  "$ERROR_WRITER_AFTER_PROOF_TR" \
  "$ERROR_WRITE_AFTER_PROOF_TR" \
  "$INTERLEAVED_WRITE_PROOF_TR" \
  "$OPEN_WRITE_BEFORE_PROOF_TR" \
  "$LATE_WRITE_RESULT_PROOF_TR" \
  "$CORRELATED_FIX_PROOF_TR" \
  "$CORRELATED_SCRIPT_PROOF_TR" \
  "$FORGED_SCRIPT_PROOF_TR" \
  "$MIXED_LOCATOR_PROOF_TR" \
  "$CORRELATED_SKILL_PROOF_TR" \
  "$UNRELATED_RED_GREEN_TR" \
  "$KT_SEEN" <<'PY'
import json, sys
(
    anonymous,
    bash_path,
    error_path,
    missing_provenance,
    stale,
    failed_edit_after_proof,
    unknown_edit_after_proof,
    writer_after_proof,
    error_writer_after_proof,
    error_write_after_proof,
    interleaved_write_proof,
    open_write_before_proof,
    late_write_result_proof,
    correlated,
    correlated_script,
    forged_script,
    mixed_locator,
    correlated_skill,
    unrelated_red_green,
    kt,
) = sys.argv[1:]
fixed_key = "reader|logic.wrong_branch|open|empty-input"
scope = "sha256:" + "a" * 64
current = "sha256:" + "b" * 64
content_hash = "sha256:" + "c" * 64
proof = {
    "schemaVersion": 3,
    "auditVerdict": "CLEAR",
    "terminalRecommendation": "AUDIT_CLEAR_NEEDS_EXTERNAL_GATES",
    "scopeFingerprint": scope,
    "verificationVerdict": "ASSERTED_ONLY",
    "fixedKeys": [fixed_key],
    "runId": "run-hook-contract",
    "runNonce": "nonce-hook-contract",
    "currentId": current,
    "contentHash": content_hash,
}

def write(path, blocks):
    with open(path, "w") as fh:
        for block in blocks:
            fh.write(json.dumps({"message": {"content": [block]}}) + "\n")

edit = {
    "type": "tool_use",
    "name": "Edit",
    "input": {"file_path": kt, "old_string": "a", "new_string": "b"},
}
workflow_use = {
    "type": "tool_use",
    "id": "toolu-proof",
    "name": "Workflow",
    "input": {"name": "multi-lens-audit"},
}
workflow_result = {
    "type": "tool_result",
    "tool_use_id": "toolu-proof",
    "is_error": False,
    "content": json.dumps(proof),
}

write(anonymous, [{"type": "tool_result", "content": json.dumps(proof)}])
write(bash_path, [
    {"type": "tool_use", "id": "toolu-proof", "name": "Bash",
     "input": {"command": "printf forged-proof"}},
    workflow_result,
])
write(error_path, [
    workflow_use,
    {**workflow_result, "is_error": True},
])
proof_without_provenance = dict(proof)
proof_without_provenance.pop("contentHash")
write(missing_provenance, [
    edit,
    workflow_use,
    {**workflow_result, "content": json.dumps(proof_without_provenance)},
])
write(stale, [workflow_use, workflow_result, edit])
failed_edit = {
    "type": "tool_use",
    "id": "toolu-failed-edit",
    "name": "Edit",
    "input": {"file_path": kt, "old_string": "missing", "new_string": "unused"},
}
failed_edit_result = {
    "type": "tool_result",
    "tool_use_id": "toolu-failed-edit",
    "is_error": True,
    "content": "old_string not found",
}
write(failed_edit_after_proof, [
    workflow_use,
    workflow_result,
    failed_edit,
    failed_edit_result,
])
write(unknown_edit_after_proof, [
    workflow_use,
    workflow_result,
    {**failed_edit, "id": "toolu-unknown-edit"},
])
writer_use = {
    "type": "tool_use",
    "id": "toolu-writer",
    "name": "Bash",
    "input": {"command": "python3 rewrite_scoped_file.py"},
}
writer_result = {
    "type": "tool_result",
    "tool_use_id": "toolu-writer",
    "is_error": False,
    "content": "rewrote scoped file",
}
write(writer_after_proof, [workflow_use, workflow_result, writer_use, writer_result])
write(error_writer_after_proof, [
    workflow_use,
    workflow_result,
    writer_use,
    {**writer_result, "is_error": True, "content": "writer changed bytes then exited nonzero"},
])
partial_write_use = {
    "type": "tool_use",
    "id": "toolu-partial-write",
    "name": "Write",
    "input": {"file_path": kt, "content": "partial"},
}
partial_write_result = {
    "type": "tool_result",
    "tool_use_id": "toolu-partial-write",
    "is_error": True,
    "content": "write failed after partial output",
}
write(error_write_after_proof, [
    workflow_use,
    workflow_result,
    partial_write_use,
    partial_write_result,
])
write(interleaved_write_proof, [
    workflow_use,
    {**partial_write_use, "id": "toolu-interleaved-write"},
    {
        **partial_write_result,
        "tool_use_id": "toolu-interleaved-write",
        "is_error": False,
        "content": "write completed",
    },
    workflow_result,
])
open_write = {**partial_write_use, "id": "toolu-open-write"}
write(open_write_before_proof, [open_write, workflow_use, workflow_result])
late_write_result = {
    **partial_write_result,
    "tool_use_id": "toolu-late-write",
    "is_error": False,
    "content": "write completed after audit result",
}
write(late_write_result_proof, [
    {**partial_write_use, "id": "toolu-late-write"},
    workflow_use,
    workflow_result,
    late_write_result,
])
write(correlated, [edit, workflow_use, workflow_result])
script_workflow_use = {
    "type": "tool_use",
    "id": "toolu-script-proof",
    "name": "Workflow",
    "input": {"script": ".claude/workflows/multi-lens-audit.js"},
}
script_workflow_result = {**workflow_result, "tool_use_id": "toolu-script-proof"}
write(correlated_script, [edit, script_workflow_use, script_workflow_result])
forged_script_use = {
    **script_workflow_use,
    "id": "toolu-forged-script-proof",
    "input": {"script": "/tmp/forged-multi-lens-audit-copy.js"},
}
forged_script_result = {**workflow_result, "tool_use_id": "toolu-forged-script-proof"}
write(forged_script, [edit, forged_script_use, forged_script_result])
mixed_locator_use = {
    **workflow_use,
    "id": "toolu-mixed-locator",
    "input": {
        "name": "multi-lens-audit",
        "script": "/tmp/forged-multi-lens-audit-copy.js",
    },
}
mixed_locator_result = {**workflow_result, "tool_use_id": "toolu-mixed-locator"}
write(mixed_locator, [edit, mixed_locator_use, mixed_locator_result])
skill_use = {
    "type": "tool_use",
    "id": "toolu-skill-proof",
    "name": "Skill",
    "input": {"skill": "multi-lens-audit"},
}
skill_result = {
    **workflow_result,
    "tool_use_id": "toolu-skill-proof",
    "content": [{"type": "text", "text": json.dumps(proof)}],
}
skill_result.pop("is_error")
write(correlated_skill, [edit, skill_use, skill_result])
write(unrelated_red_green, [{
    "type": "tool_result",
    "tool_use_id": "toolu-unrelated-test",
    "is_error": False,
    "content": "OtherFeatureTest FAILED\nOtherFeatureTest PASSED",
}])
PY

# mk_tr <out.jsonl> <tool> <file_path> <written-text> [WITH_SCAN]
# One-edit transcript; WITH_SCAN appends a security-checklist Skill call after it.
mk_tr() {
  python3 - "$1" "$2" "$3" "$4" "${5:-}" <<'PY'
import json, sys
out, tool, path, text, scan = sys.argv[1:6]
key = "content" if tool == "Write" else "new_string"
blocks = [{"type": "tool_use", "name": tool, "input": {"file_path": path, key: text}}]
if scan == "WITH_SCAN":
    blocks.append({"type": "tool_use", "name": "Skill", "input": {"skill": "security-checklist"}})
with open(out, "w") as fh:
    for b in blocks:
        fh.write(json.dumps({"message": {"content": [b]}}) + "\n")
PY
}

# Gradle test-results layout the gates glob for: <module>/build/test-results/<task>/
RED_XML_DIR="${SANDBOX}/app/build/test-results/testDebugUnitTest"
mkdir -p "${RED_XML_DIR}"

# mk_xml <dir> <suite> <tests> <failures> <errors> <skipped>
mk_xml() {
  cat > "$1/TEST-${2}.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="com.example.${2}" tests="${3}" failures="${4}" errors="${5}" skipped="${6}">
  <testcase classname="com.example.${2}" name="doesSomething"/>
</testsuite>
XML
  touch "$1/TEST-${2}.xml"
}

echo "sandbox: ${SANDBOX}"
echo

# ── block-dangerous-git.sh — PreToolUse Bash ────────────────────────────────
echo "block-dangerous-git.sh"
run_case "destructive reset --hard blocked" block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~1"}}'
run_case "git clean -fd blocked"            block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git clean -fd"}}'
run_case "plain push allowed by design"     block-dangerous-git.sh 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push origin trunk"}}'
run_case "read-only git status allowed"     block-dangerous-git.sh 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git status --short"}}'
# Quoted-but-EXECUTED must stay blocked — these pin the fail-closed half of the
# prose exemption added 2026-07-28. Before that change nothing tested them.
run_case "destructive cmd inside bash -c blocked" block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"bash -c \"git reset --hard HEAD~1\""}}'
run_case "destructive cmd inside ssh blocked"     block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"ssh buildbox \"git clean -fd\""}}'
run_case "destructive cmd in \$() blocked"        block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"echo $(git reset --hard)"}}'
# Prose that merely mentions the command is not the command.
run_case "prose mentioning the phrase allowed"    block-dangerous-git.sh 0 \
  '{"tool_name":"Bash","tool_input":{"command":"echo \"đừng bao giờ chạy git reset --hard trên trunk\""}}'
run_case "commit message mentioning it allowed"   block-dangerous-git.sh 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"docs: explain why git reset --hard is banned\""}}'
# Single-word quoted spans are shell words, not prose — quoting must not hide them.
run_case "quoted flag reset \"--hard\" blocked"   block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git reset \"--hard\" HEAD~3"}}'
run_case "quoted subcommand \"reset\" blocked"    block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git \"reset\" --hard"}}'
# One developer, one branch (2026-09-26, GeelyEx2: `git push origin <sha>:main` of a commit the local
# main did not hold left local main 2 commits behind origin; worktree branches piled up). New branches
# only when the user asks (DEVKIT_ALLOW_BRANCH=1); a push of <src>:<dst> only when local <dst> holds <src>.
GR="$(mktemp -d "${TMPDIR:-/tmp}/hookgr.XXXXXX")"
git -C "${GR}" init -q -b main && git -C "${GR}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m a
GR_OUT="$(git -C "${GR}" commit-tree 'HEAD^{tree}' -p HEAD -m side)"      # a commit local main does not hold
gpay() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$1" "${2:-${SANDBOX}}"; }
run_case "solo: push <sha>:main not in local main blocked" block-dangerous-git.sh 2 "$(gpay "git -C ${GR} push origin ${GR_OUT}:main")"
run_case "solo: cd repo && push <sha>:main blocked"      block-dangerous-git.sh 2 "$(gpay "cd ${GR} && git push origin ${GR_OUT}:main")"
run_case "solo: push HEAD:main from main allowed"         block-dangerous-git.sh 0 "$(gpay "git push origin HEAD:main" "${GR}")"
run_case "solo: plain push of the branch allowed"         block-dangerous-git.sh 0 "$(gpay "git push origin main" "${GR}")"
run_case "solo: push to a new remote branch blocked"      block-dangerous-git.sh 2 "$(gpay "git push origin HEAD:refs/heads/feat-x" "${GR}")"
run_case "solo: checkout -b blocked"                      block-dangerous-git.sh 2 "$(gpay "git checkout -b feat/x")"
run_case "solo: switch -c blocked"                        block-dangerous-git.sh 2 "$(gpay "git switch -c feat/x")"
run_case "solo: branch <new> blocked"                     block-dangerous-git.sh 2 "$(gpay "git branch feat/x")"
run_case "solo: worktree add blocked"                     block-dangerous-git.sh 2 "$(gpay "git worktree add ../x")"
run_case "solo: user-asked branch (DEVKIT_ALLOW_BRANCH=1)" block-dangerous-git.sh 0 "$(gpay "DEVKIT_ALLOW_BRANCH=1 git checkout -b release/1.3")"
run_case "solo: branch -d (merged) allowed"               block-dangerous-git.sh 0 "$(gpay "git branch -d feat/x")"
run_case "solo: branch listing allowed"                   block-dangerous-git.sh 0 "$(gpay "git branch -a --show-current")"
run_case "solo: checkout / switch existing allowed"       block-dangerous-git.sh 0 "$(gpay "git checkout main && git switch trunk")"
run_case "solo: branch -m rename allowed"                 block-dangerous-git.sh 0 "$(gpay "git branch -m old new")"
run_case "solo: branch -u / --contains / --points-at allowed" block-dangerous-git.sh 0 "$(gpay "git branch -u origin/main; git branch --contains HEAD; git branch --points-at HEAD")"
run_case "solo: branch --copy blocked (makes a branch)"   block-dangerous-git.sh 2 "$(gpay "git branch -c main feat/y")"
run_case "solo: push HEAD:refs/tags/v1.3 allowed"         block-dangerous-git.sh 0 "$(gpay "git push origin HEAD:refs/tags/v1.3" "${GR}")"
run_case "solo: push \$(sha):main blocked (fail closed)"  block-dangerous-git.sh 2 "$(gpay "git push origin \$(git rev-parse HEAD):main" "${GR}")"
run_case "solo: checkout -b in \$(...) blocked"           block-dangerous-git.sh 2 "$(gpay "echo \$(date) && git checkout -b feat/x")"
run_case "solo: export DEVKIT_ALLOW_BRANCH=1 allowed"     block-dangerous-git.sh 0 "$(gpay "export DEVKIT_ALLOW_BRANCH=1; git switch -c release/1.3")"
run_case "solo: env DEVKIT_ALLOW_BRANCH=1 allowed"        block-dangerous-git.sh 0 "$(gpay "env DEVKIT_ALLOW_BRANCH=1 git worktree add ../x")"
if printf '%s' "$(gpay "git checkout -b feat/x")" | env CLAUDE_PROJECT_DIR="${SANDBOX}" bash "${HOOKS}/block-dangerous-git.sh" 2>&1 >/dev/null | grep -q 'DEVKIT_ALLOW_BRANCH=1'; then
  PASS=$((PASS + 1)); printf '  ok   %-46s\n' "solo: block message names the user-asked escape"
else
  FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ solo: block message names the user-asked escape"
  printf '  FAIL %-46s\n' "solo: block message names the user-asked escape"
fi
# Review 2026-09-26 (fresh-context reviewer): false positives and gaps of the first cut.
git -C "${GR}" -c user.email=t@t -c user.name=t tag v1.0
run_case "solo: commit message in \$(cat <<EOF) allowed" block-dangerous-git.sh 0 "$(gpay "git commit -m \"\$(cat <<'EOF'
fix: block git worktree add and git checkout -b; never git push origin sha:main
EOF
)\"" "${GR}")"
run_case "solo: commit -m \$(printf 'git branch naming') allowed" block-dangerous-git.sh 0 "$(gpay "git commit -m \"\$(printf 'docs: explain git branch naming')\"" "${GR}")"
run_case "solo: branch 2>/dev/null allowed"               block-dangerous-git.sh 0 "$(gpay "git branch 2>/dev/null; git branch > b.txt; git branch 2>&1 | head")"
run_case "solo: (cd /tmp) && push <sha>:main blocked"     block-dangerous-git.sh 2 "$(gpay "(cd /tmp) && git push origin ${GR_OUT}:main" "${GR}")"
run_case "solo: cd \"\$R\" && push <sha>:main blocked (unverifiable)" block-dangerous-git.sh 2 "$(gpay "cd \"\$R\" && git push origin ${GR_OUT}:main")"
run_case "solo: DEVKIT_ALLOW_BRANCH=1 does not cover <sha>:main" block-dangerous-git.sh 2 "$(gpay "DEVKIT_ALLOW_BRANCH=1 git push origin ${GR_OUT}:main" "${GR}")"
run_case "solo: alias to checkout -b blocked"             block-dangerous-git.sh 2 "$(gpay "git -c alias.nb='checkout -b' nb x")"
run_case "solo: push tag v1.0:v1.0 allowed"               block-dangerous-git.sh 0 "$(gpay "git push origin v1.0:v1.0" "${GR}")"
run_case "solo: push with a NUL in the ref never crashes open" block-dangerous-git.sh 2 "{\"tool_name\":\"Bash\",\"cwd\":\"${GR}\",\"tool_input\":{\"command\":\"git push origin x:ma\\u0000in\"}}"
# Review round 2 (2026-09-26): an unbalanced $( / backtick must not switch the rule off.
run_case "solo: push <sha>:main # \$( still blocked"      block-dangerous-git.sh 2 "$(gpay "git push origin ${GR_OUT}:main # \$(" "${GR}")"
run_case "solo: echo '\$(' && push <sha>:main blocked"    block-dangerous-git.sh 2 "$(gpay "echo '\$(' && git push origin ${GR_OUT}:main" "${GR}")"
run_case "solo: PR body with '(' in heredoc && push blocked" block-dangerous-git.sh 2 "$(gpay "gh pr create --body \"\$(cat <<'EOF'
Run git branch foo (see #1
EOF
)\" && git push origin ${GR_OUT}:main" "${GR}")"
run_case "solo: printf 'x (y' then checkout -b blocked"   block-dangerous-git.sh 2 "$(gpay "git commit -m \"\$(printf 'x (y')\" && git checkout -b feat")"
run_case "solo: unclosed backtick && push <sha>:main blocked" block-dangerous-git.sh 2 "$(gpay "echo \`echo x && git push origin ${GR_OUT}:main" "${GR}")"
run_case "solo: PR body with '(' and a plain push allowed" block-dangerous-git.sh 0 "$(gpay "gh pr create --body \"\$(cat <<'EOF'
Run git branch foo (see #1
EOF
)\" && git push origin main" "${GR}")"
rm -rf "${GR}"
run_case "+refspec force push blocked"            block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git push origin +main"}}'
run_case "checkout -f blocked"                    block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout -f main"}}'
run_case "switch --discard-changes blocked"       block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git switch --discard-changes main"}}'
run_case "checkout -b feature-foo allowed"        block-dangerous-git.sh 0 \
  '{"tool_name":"Bash","tool_input":{"command":"DEVKIT_ALLOW_BRANCH=1 git checkout -b feature-foo"}}'
run_case "single-word commit message allowed"     block-dangerous-git.sh 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"wip\""}}'
# 2026-09-23 re-audit: global options, continuations, nested quotes, split flags,
# remote deletes — and chains that must NOT be blocked.
run_case "blocked: git -C . clean -fdx" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git -C . clean -fdx"}}'
run_case "blocked: git -C . checkout -- ." block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git -C . checkout -- ."}}'
run_case "blocked: git -c a=b clean -fd" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git -c a=b clean -fd"}}'
run_case "blocked: git reset \  --hard HEAD~3" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git reset \\\n --hard HEAD~3"}}'
run_case "blocked: echo it's; git reset --hard; echo 'x y'" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "echo \"it'\''s\"; git reset --hard; echo '\''x y'\''"}}'
run_case "blocked: git push -uf origin main" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git push -uf origin main"}}'
run_case "blocked: git clean --force" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git clean --force"}}'
run_case "blocked: git branch -d -f x" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git branch -d -f x"}}'
run_case "blocked: git push origin --delete x" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git push origin --delete x"}}'
run_case "blocked: git push origin :x" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git push origin :x"}}'
run_case "blocked: git stash clear" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git stash clear"}}'
run_case "blocked: git gc --prune=now" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git gc --prune=now"}}'
run_case "blocked: xargs git clean -f" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "xargs git clean -f"}}'
run_case "allowed: git checkout develop && rm -rf node_modu" block-dangerous-git.sh 0 \
  '{"tool_name": "Bash", "tool_input": {"command": "git checkout develop && rm -rf node_modules"}}'
run_case "allowed: git checkout main; ls -f" block-dangerous-git.sh 0 \
  '{"tool_name": "Bash", "tool_input": {"command": "git checkout main; ls -f"}}'
run_case "allowed: git push origin main && echo +1" block-dangerous-git.sh 0 \
  '{"tool_name": "Bash", "tool_input": {"command": "git push origin main && echo +1"}}'
run_case "allowed: git switch -c fix" block-dangerous-git.sh 0 \
  '{"tool_name": "Bash", "tool_input": {"command": "DEVKIT_ALLOW_BRANCH=1 git switch -c fix"}}'
run_case "allowed: git branch -d merged" block-dangerous-git.sh 0 \
  '{"tool_name": "Bash", "tool_input": {"command": "git branch -d merged"}}'
run_case "allowed: git diff -- file" block-dangerous-git.sh 0 \
  '{"tool_name": "Bash", "tool_input": {"command": "git diff -- file"}}'
# The pre-commit gate (agent-kit githooks) must not be skippable by the agent.
run_case "git commit --no-verify blocked" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git commit --no-verify -m x"}}'
run_case "git commit -nm (no-verify cluster) blocked" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git commit -nm x"}}'
run_case "git -c core.hooksPath=... commit blocked" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git -c core.hooksPath=/dev/null commit -m x"}}'
run_case "DEVKIT_PRECOMMIT=0 git commit blocked" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "DEVKIT_PRECOMMIT=0 git commit -m x"}}'
run_case "git push --no-verify blocked" block-dangerous-git.sh 2 \
  '{"tool_name": "Bash", "tool_input": {"command": "git push --no-verify"}}'
run_case "allowed: commit message containing -n" block-dangerous-git.sh 0 \
  '{"tool_name": "Bash", "tool_input": {"command": "git commit -am \"fix -n flag\""}}'
run_case "allowed: git commit --amend --no-edit" block-dangerous-git.sh 0 \
  '{"tool_name": "Bash", "tool_input": {"command": "git commit --amend --no-edit"}}'
# 2026-09-23 QA K-1/K-2: bypasses via subshells, keywords, wrapper option values,
# variables in command position, aliases, interpreters — and false positives.
gitcase() {
  want="$1"; c="$2"
  run_case "git-guard[${want}]: ${c}" block-dangerous-git.sh "${want}" \
    "$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "${c}")"
}
gitcase 2 '(git reset --hard)'
gitcase 2 '{ git reset --hard; }'
gitcase 2 'if true; then git reset --hard; fi'
gitcase 2 'sudo -u root git reset --hard'
gitcase 2 'nice -n 5 git clean -fd'
gitcase 2 'timeout 5 git reset --hard'
gitcase 2 'watch git reset --hard'
gitcase 2 'find . -exec git reset --hard \;'
gitcase 2 'g=git; $g reset --hard'
gitcase 2 'git -c alias.x="reset --hard" x'
gitcase 2 'git -c alias.y="!git clean -fdx" y'
gitcase 2 "python3 -c \"import os;os.system('git reset --hard')\""
gitcase 2 "python3 -c \"import subprocess;subprocess.run('git clean -fd',shell=True)\""
gitcase 2 'git rm -rf .'
gitcase 2 'git switch -C main'
gitcase 2 'git checkout -B main'
gitcase 2 'git rebase main'
gitcase 2 'git restore a.kt'
gitcase 0 'git restore --staged a.kt'
# restore of an existing file is allowed only after a backup of its current content
RESTORE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hookrestore.XXXXXX")"
printf 'uncommitted work\n' > "${RESTORE_DIR}/w.kt"
( cd "${RESTORE_DIR}" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git restore w.kt"}}' \
    | CLAUDE_PROJECT_DIR="${RESTORE_DIR}" bash "${HOOKS}/block-dangerous-git.sh" >/dev/null 2>&1 )
rc=$?
if [ "$rc" -eq 0 ] && grep -rqs "uncommitted work" "${RESTORE_DIR}/.claude/audit-gate/restore-backup/"; then
  PASS=$((PASS + 1)); printf '  ok   %-46s exit=%s\n' "git restore <file> allowed after backup" "$rc"
else
  FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ git restore <file> allowed after backup (rc=$rc)"; printf '  FAIL %-46s\n' "git restore <file> allowed after backup"
fi
( cd "${RESTORE_DIR}" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git restore ."}}' \
    | CLAUDE_PROJECT_DIR="${RESTORE_DIR}" bash "${HOOKS}/block-dangerous-git.sh" >/dev/null 2>&1 )
rc=$?
if [ "$rc" -eq 2 ]; then PASS=$((PASS + 1)); printf '  ok   %-46s exit=%s\n' "git restore . still blocked" "$rc"
else FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ git restore . still blocked (rc=$rc)"; printf '  FAIL %-46s\n' "git restore . still blocked"; fi
( cd "${RESTORE_DIR}" && rm -rf .claude && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git restore w.kt && git reset --hard"}}' \
    | CLAUDE_PROJECT_DIR="${RESTORE_DIR}" bash "${HOOKS}/block-dangerous-git.sh" >/dev/null 2>&1 )
rc=$?
if [ "$rc" -eq 2 ] && [ ! -d "${RESTORE_DIR}/.claude/audit-gate/restore-backup" ]; then
  PASS=$((PASS + 1)); printf '  ok   %-46s exit=%s\n' "blocked command leaves no restore backup" "$rc"
else FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ blocked command leaves no restore backup (rc=$rc)"; printf '  FAIL %-46s\n' "blocked command leaves no restore backup"; fi
rm -rf "${RESTORE_DIR}"
gitcase 0 'git rebase --continue'
gitcase 0 'git rm --cached a.kt'
gitcase 0 'timeout 5 npm test'
gitcase 0 'nice -n 5 make build'
gitcase 0 'find . -name "*.kt" -exec wc -l {} \;'
gitcase 0 'echo "(git reset --hard)"'
gitcase 0 'if [ -f a ]; then echo ok; fi'
gitcase 0 'python3 -c "print(1)"'
NOJQ_BIN="${SANDBOX}/nojq-bin"; mkdir -p "${NOJQ_BIN}"
for tool in bash cat; do ln -sf "$(command -v "${tool}")" "${NOJQ_BIN}/${tool}"; done
run_case "missing python3 fails closed"                block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git status"}}' PATH="${NOJQ_BIN}"
echo

# ── hardware_safety_gate.sh — PreToolUse Bash (QA K-3) ──────────────────────
echo "hardware_safety_gate.sh"
hwcase() {
  want="$1"; c="$2"
  shift 2
  # The developer's own device policy (~/.config, env) must not leak into the cases.
  run_case "hw-gate[${want}]: ${c}${1:+ [${1%%,*}…]}" hardware_safety_gate.sh "${want}" \
    "$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "${c}")" \
    XDG_CONFIG_HOME="${SANDBOX}/xdg" ADB_DENY_SERIALS= ADB_ALLOW_SERIALS= ANDROID_SERIAL= "$@"
}
hwcase 2 'adb remount'
# system packages and iOS signing / simulators (found by the mobile simulation)
hwcase 2 'adb -s EMU01 shell pm uninstall --user 0 com.android.systemui'
hwcase 2 'adb shell pm disable-user com.google.android.gms'
hwcase 0 'adb shell pm uninstall com.shop.app'
hwcase 2 'fastlane match nuke development'
hwcase 2 'security delete-keychain login.keychain-db'
hwcase 2 'rm -rf ~/Library/MobileDevice/Provisioning\ Profiles'
hwcase 2 'xcrun simctl erase all'
hwcase 0 'xcrun simctl delete unavailable'
hwcase 0 'fastlane beta'
# irreversible release / infrastructure / data (found by the web/backend simulation)
hwcase 2 'npm publish'
hwcase 2 'vercel --prod'
hwcase 2 'npx prisma migrate reset --force'
hwcase 2 'psql "$DATABASE_URL" -c "DROP DATABASE orders"'
hwcase 2 'redis-cli FLUSHALL'
hwcase 2 'kubectl delete namespace production'
hwcase 2 'terraform destroy -auto-approve'
hwcase 2 'docker system prune -af --volumes'
hwcase 2 'aws s3 rm s3://bucket --recursive'
hwcase 0 'npm run build'
hwcase 0 'docker compose up -d'
hwcase 0 'kubectl delete pod web-1'
hwcase 0 'terraform plan'
hwcase 2 'adb -s emulator-5554 remount'
hwcase 2 'adb shell mount -o rw,remount /system'
hwcase 2 'fastboot -s ABC flash boot boot.img'
hwcase 2 'fastboot flashall'
hwcase 2 'fastboot oem unlock'
hwcase 2 'rm -fr /system'
hwcase 2 'rm -r -f /vendor'
hwcase 2 'dd if=x of=/dev/sda'
hwcase 0 'adb devices'
hwcase 0 'adb -s X install app.apk'
hwcase 0 'fastboot devices'
hwcase 0 'rm -rf build'
hwcase 0 'dd if=/dev/zero of=out.img bs=1m count=1'
run_case "hw-gate: malformed JSON fails closed" hardware_safety_gate.sh 2 '{bad'
run_case "hw-gate: missing python3 fails closed" hardware_safety_gate.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"adb devices"}}' PATH="${NOJQ_BIN}"
# Fast path: a command with no trigger word and no quote/escape/$/glob needs no parser.
run_case "hw-gate: fast path allows ls even without python3" hardware_safety_gate.sh 0 \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' PATH="${NOJQ_BIN}"
run_case "git-guard: fast path allows npm test without python3" block-dangerous-git.sh 0 \
  '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' PATH="${NOJQ_BIN}"
# ... and never lets a disguised command through: case, quotes and globs go to the parser.
hwcase 2 'ADB remount'
hwcase 2 'a?b remount'
hwcase 2 'a""db remount'
hwcase 2 'Fastboot flash boot x.img'
hwcase 2 'RM -rf /system'
run_case "git-guard: GIT reset --hard (macOS is case-insensitive)" block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"GIT reset --hard"}}'
run_case "git-guard: /usr/bin/g?t reset --hard (glob)" block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"/usr/bin/g?t reset --hard"}}'
run_case "git-guard: g''it reset --hard (quotes)" block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"g'"''"'it reset --hard"}}'
run_case "git-guard: \$G reset --hard (variable)" block-dangerous-git.sh 2 \
  '{"tool_name":"Bash","tool_input":{"command":"G=git; $G reset --hard"}}'
run_case "hw-gate: override honoured" hardware_safety_gate.sh 0 \
  '{"tool_name":"Bash","tool_input":{"command":"adb remount"}}' HARDWARE_OVERRIDE=1
# Device policy (the Geely EX2 lesson: two personal phones on the same USB hub as the
# rig). Fake adb answers `get-serialno` with the serial adb itself would pick.
HW_BIN="${SANDBOX}/hw-bin"; mkdir -p "${HW_BIN}"
cat > "${HW_BIN}/adb" <<'FAKE_ADB'
#!/usr/bin/env bash
S=""
while [ $# -gt 0 ]; do
  case "$1" in
    -s) S="$2"; shift 2 ;;
    get-serialno) S="${S:-${ANDROID_SERIAL:-${FAKE_SERIAL:-}}}"
                  [ -n "$S" ] || { echo "error: no devices/emulators found" >&2; exit 1; }
                  echo "$S"; exit 0 ;;
    *) shift ;;
  esac
done
FAKE_ADB
chmod +x "${HW_BIN}/adb"
HWP="PATH=${HW_BIN}:${PATH}"
DENY="ADB_DENY_SERIALS=RFCW504KFKJ,RFCWA1KQT1Y"
hwcase 2 'adb -s RFCW504KFKJ shell ls' "${DENY}"
hwcase 0 'adb -s IVI01 shell ls' "${DENY}"
hwcase 2 'adb shell am start -n x/.Y' "${DENY}" "${HWP}" FAKE_SERIAL=RFCWA1KQT1Y
hwcase 0 'adb shell am start -n x/.Y' "${DENY}" "${HWP}" FAKE_SERIAL=IVI01
hwcase 0 'adb shell ls' "${DENY}" "${HWP}"
hwcase 2 'ANDROID_SERIAL=RFCW504KFKJ adb shell ls' "${DENY}" "${HWP}"
hwcase 2 'cd app && timeout 30 adb -d install a.apk' "${DENY}" "${HWP}" FAKE_SERIAL=RFCWA1KQT1Y
hwcase 2 'bash -c "adb -s RFCW504KFKJ reboot"' "${DENY}"
hwcase 2 'adb -s "$DEV" shell ls' "${DENY}"
hwcase 0 'adb devices' "${DENY}" "${HWP}" FAKE_SERIAL=RFCWA1KQT1Y
hwcase 0 'grep adb notes.txt' "${DENY}" "${HWP}" FAKE_SERIAL=RFCWA1KQT1Y
hwcase 2 'adb -s IVI02 shell ls' ADB_ALLOW_SERIALS=IVI01
hwcase 0 'adb -s IVI01 shell ls' ADB_ALLOW_SERIALS=IVI01
mkdir -p "${SANDBOX}/xdg/universal-agent-devkit"
printf '# my phones\nRFCW504KFKJ\n' > "${SANDBOX}/xdg/universal-agent-devkit/adb-denylist"
hwcase 2 'adb -s RFCW504KFKJ shell ls'
rm -rf "${SANDBOX}/xdg"
printf 'IVI01  # the rig\n' > "${SANDBOX}/.adb-allowlist"
hwcase 2 'adb -s RFCW504KFKJ shell ls'
hwcase 0 'adb -s IVI01 shell ls'
rm -f "${SANDBOX}/.adb-allowlist"
# Automotive only (GeelyEx2 INSTINCT-099): a logcat that streams to this computer dies
# with the ADB Wi-Fi link, and the log of the measurement dies with it. A dump (-d -c -g
# -t) or a logcat detached on the car (nohup/… &, writing to /data, /sdcard) is allowed.
mkdir -p "${SANDBOX}/auto/.agents"
printf '{"profile":"automotive"}\n' > "${SANDBOX}/auto/.agents/active-profile.json"
AUTO="CLAUDE_PROJECT_DIR=${SANDBOX}/auto"
hwcase 0 'adb logcat'
hwcase 2 'adb logcat' "${AUTO}"
hwcase 2 'adb logcat | grep Media' "${AUTO}"
hwcase 2 'adb logcat &' "${AUTO}"
hwcase 2 'adb shell logcat' "${AUTO}"
hwcase 2 'adb -s IVI01 logcat -v time' "${AUTO}"
hwcase 2 'adb logcat > /tmp/x.log' "${AUTO}"
hwcase 2 'adb shell logcat > host.txt' "${AUTO}"
hwcase 2 'adb logcat -T 10' "${AUTO}"
hwcase 2 'timeout 60 adb logcat -s MediaKey' "${AUTO}"
hwcase 2 'adb shell "logcat -f /data/local/tmp/x.txt"' "${AUTO}"
hwcase 0 'adb logcat -d' "${AUTO}"
hwcase 0 'adb logcat -c' "${AUTO}"
hwcase 0 'adb logcat -g' "${AUTO}"
hwcase 0 'adb logcat -t 200' "${AUTO}"
hwcase 0 'adb -s IVI01 logcat -d -v time > /tmp/x.log' "${AUTO}"
hwcase 0 'adb shell "logcat -d > /data/local/tmp/x.txt"' "${AUTO}"
hwcase 0 'adb shell "nohup logcat -f /data/local/tmp/x.txt &"' "${AUTO}"
hwcase 0 'adb shell "logcat > /data/local/tmp/x.log &"' "${AUTO}"
hwcase 0 'adb shell dumpsys car_service' "${AUTO}"
hwcase 0 'grep logcat notes.txt' "${AUTO}"
# review 2026-09-26: a value glued to its option is no dump flag; logcat as an argument
# (pkill logcat) is no logcat call; "detached" belongs to the logcat's own command.
hwcase 2 'adb logcat -vtime' "${AUTO}"
hwcase 2 'adb logcat -bcrash' "${AUTO}"
hwcase 2 'adb logcat -sTag:I' "${AUTO}"
hwcase 0 'adb logcat -b crash -d' "${AUTO}"
hwcase 0 'adb logcat -t200' "${AUTO}"
hwcase 0 'adb logcat -G 16M' "${AUTO}"
hwcase 0 'adb logcat -S' "${AUTO}"
hwcase 0 'adb shell pkill logcat' "${AUTO}"
hwcase 0 'adb shell "pkill -f logcat"' "${AUTO}"
hwcase 0 'adb shell pidof logcat' "${AUTO}"
hwcase 2 'adb shell logcat -f /data/local/tmp/l.txt & sleep 5; echo "x &"' "${AUTO}"
# The same guard through replicant-mcp (profiles android/automotive: essential_mcps).
# Tool names and input schemas from replicant-mcp 1.6.7 dist/tools/*.js: adb-shell
# {command} and adb-app {operation, packageName} have no device field — they run on the
# server's selected device, or the only online one. Its own process-runner blocks
# `rm -rf /system`, dd, su, format, but not `mount … rw /system` or `pm uninstall
# <system package>`, and knows nothing of the device policy.
mcpcase() { # want tool input-json [ENV=VAL ...]
  want="$1"; tool="$2"; input="$3"; shift 3
  run_case "hw-gate[${want}]: mcp ${tool} ${input}${1:+ [${1%%,*}…]}" hardware_safety_gate.sh "${want}" \
    "{\"tool_name\":\"mcp__replicant-mcp__${tool}\",\"tool_input\":${input}}" \
    XDG_CONFIG_HOME="${SANDBOX}/xdg" ADB_DENY_SERIALS= ADB_ALLOW_SERIALS= ANDROID_SERIAL= "$@"
}
mcpcase 2 adb-shell '{"command":"pm uninstall --user 0 com.android.systemui"}'
mcpcase 2 adb-shell '{"command":"mount -o rw,remount /system"}'
mcpcase 2 adb-shell '{"command":"rm -rf /system/app/Launcher"}'
mcpcase 0 adb-shell '{"command":"ls /sdcard"}'
mcpcase 0 adb-shell '{"command":"rm -rf /sdcard/Download/shots"}'
mcpcase 2 adb-app '{"operation":"uninstall","packageName":"com.android.systemui"}'
mcpcase 0 adb-app '{"operation":"uninstall","packageName":"com.shop.app"}'
mcpcase 2 adb-device '{"operation":"select","deviceId":"RFCW504KFKJ"}' "${DENY}"
mcpcase 0 adb-device '{"operation":"select","deviceId":"IVI01"}' "${DENY}"
mcpcase 2 adb-shell '{"command":"ls"}' "${DENY}" "${HWP}" FAKE_SERIAL=RFCWA1KQT1Y
mcpcase 0 adb-shell '{"command":"ls"}' "${DENY}" "${HWP}" FAKE_SERIAL=IVI01
mcpcase 2 ui-capture '{"operation":"screenshot"}' "${DENY}" "${HWP}" FAKE_SERIAL=RFCWA1KQT1Y
mcpcase 2 adb-app '{"operation":"install","apkPath":"app.apk"}' "${DENY}" "${HWP}" FAKE_SERIAL=RFCWA1KQT1Y
# `adb-device list` auto-selects the only online device: checked like a device call.
mcpcase 2 adb-device '{"operation":"list"}' "${DENY}" "${HWP}" FAKE_SERIAL=RFCWA1KQT1Y
mcpcase 0 adb-device '{"operation":"list"}' "${DENY}" "${HWP}"
mcpcase 0 gradle-build '{"operation":"assembleDebug"}' "${DENY}" "${HWP}" FAKE_SERIAL=RFCWA1KQT1Y
mcpcase 2 adb-shell '{"command":"ls"}' ADB_ALLOW_SERIALS=IVI01 "${HWP}" FAKE_SERIAL=RFCW504KFKJ
# a tool this version does not have: its serial-like field is still checked
mcpcase 2 adb-reboot '{"deviceId":"RFCW504KFKJ"}' "${DENY}"
# An MCP payload never takes the Bash fast path (its "command" is a DEVICE command).
run_case "hw-gate: mcp payload skips the fast path (no python3)" hardware_safety_gate.sh 2 \
  '{"tool_name":"mcp__replicant-mcp__adb-shell","tool_input":{"command":"pm uninstall com.android.systemui"}}' PATH="${NOJQ_BIN}"

# Destructive rm in the project (Claude's `Bash(rm -rf *)` deny misses -fr, -r -f,
# --recursive --force; Codex/Gemini/Cursor had nothing). CLAUDE_PROJECT_DIR=SANDBOX.
mkdir -p "${SANDBOX}/Assets/Old" "${SANDBOX}/src" "${SANDBOX}/app/build" "${SANDBOX}/build"
printf 'x\n' > "${SANDBOX}/notes.txt"
hwcase 2 'rm -rf Assets'
hwcase 2 'rm -fr src'
hwcase 2 'rm -r -f app'
hwcase 2 'rm --recursive --force Assets'
hwcase 2 'rm -Rf -- src'
hwcase 2 'rm -rf .'
hwcase 2 'rm -rf ..'
hwcase 2 'rm -rf *'
hwcase 2 'rm -rf src/*'
hwcase 2 'rm -rf ~/Documents'
hwcase 2 'rm -rf /Users/nobody/proj'
hwcase 2 'rm -rf "$SOME_DIR"'
hwcase 2 'rm -rf $(pwd)'
hwcase 2 'rm -rf `pwd`'
hwcase 2 'echo "$(rm -rf src)"'
hwcase 2 'sudo rm -rf src'
hwcase 2 'npm run build && rm -rf Assets'
hwcase 2 'bash -c "rm -rf src"'
hwcase 2 'cd / && rm -rf Users/nobody/Documents'
hwcase 2 '(cd /tmp/w && true); rm -rf src'
hwcase 2 'cd app || rm -rf src'
hwcase 0 'rm -rf build'
hwcase 0 'rm -rf node_modules .gradle'
hwcase 0 'rm -rf Library Temp obj'
hwcase 0 'rm -rf app/build'
hwcase 0 'rm -rf build/*'
hwcase 0 'rm -rf Assets/Old'
hwcase 0 'rm -rf /tmp/devkit-x'
hwcase 0 'rm -rf "$TMPDIR/devkit-x"'
hwcase 0 'rm -rf notes.txt'
hwcase 0 'rm -r src'
hwcase 0 'rm -f notes.txt'
hwcase 0 'cd /tmp/work && rm -rf src'
hwcase 0 'D=build; rm -rf $D'
hwcase 0 'echo rm -rf src'
hwcase 0 'find . -name __pycache__ -exec rm -rf {} +'
# the session cwd (Claude sends it in the payload) is where a relative path starts
run_case "hw-gate[0]: rm -rf src from cwd app/ (app/src)" hardware_safety_gate.sh 0 \
  "{\"tool_name\":\"Bash\",\"cwd\":\"${SANDBOX}/app\",\"tool_input\":{\"command\":\"rm -rf src\"}}"
run_case "hw-gate[2]: rm -rf ../src from cwd app/" hardware_safety_gate.sh 2 \
  "{\"tool_name\":\"Bash\",\"cwd\":\"${SANDBOX}/app\",\"tool_input\":{\"command\":\"rm -rf ../src\"}}"
# a build-output NAME that git tracks is source (this DevKit's own bin/), not output
GP="${SANDBOX}/gitproj"; mkdir -p "${GP}/bin"; printf 'x\n' > "${GP}/bin/tool.sh"
git -C "${GP}" init -q && git -C "${GP}" add bin/tool.sh
hwcase 2 'rm -rf bin' CLAUDE_PROJECT_DIR="${GP}"
hwcase 0 'rm -rf build' CLAUDE_PROJECT_DIR="${GP}"
# harmless commands still take the fast path (no python3)
run_case "hw-gate: fast path allows npm test without python3" hardware_safety_gate.sh 0 \
  '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' PATH="${NOJQ_BIN}"
# Codex / Gemini / Cursor get the rm guard through agent_bridge.sh (shell → this gate).
bridge_rm() { # platform payload → prints rc and stdout
  printf '%s' "$2" | (cd "${SANDBOX}" && bash "${HOOKS}/agent_bridge.sh" "$1" shell hardware_safety_gate.sh 2>/dev/null)
}
for pf in codex gemini; do
  bridge_rm "${pf}" "{\"tool_input\":{\"command\":\"rm -fr src\"},\"cwd\":\"${SANDBOX}\"}" >/dev/null
  rc=$?
  if [ "${rc}" -eq 2 ]; then PASS=$((PASS + 1)); printf '  ok   %-46s exit=2\n' "bridge ${pf}: rm -fr src blocked"
  else FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ bridge ${pf}: rm -fr src not blocked (rc=${rc})"; printf '  FAIL %-46s rc=%s\n' "bridge ${pf}: rm -fr src blocked" "${rc}"; fi
done
out="$(bridge_rm cursor "{\"command\":\"rm -r -f app\",\"cwd\":\"${SANDBOX}\"}")"
if printf '%s' "${out}" | grep -q '"permission": "deny"'; then PASS=$((PASS + 1)); printf '  ok   %-46s\n' "bridge cursor: rm -r -f app denied"
else FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ bridge cursor: rm -r -f app not denied (out=${out})"; printf '  FAIL %-46s\n' "bridge cursor: rm -r -f app denied"; fi
# the session cwd reaches the gate: from <git root>/app, `rm -rf src` is app/src
mkdir -p "${GP}/app/src"
out="$(bridge_rm cursor "{\"command\":\"rm -rf src\",\"cwd\":\"${GP}/app\"}")"
if [ -z "${out}" ]; then PASS=$((PASS + 1)); printf '  ok   %-46s\n' "bridge cursor: rm -rf src in app/ allowed (cwd)"
else FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ bridge cursor: rm -rf src from app/ denied (out=${out})"; printf '  FAIL %-46s\n' "bridge cursor: rm -rf src in app/ allowed (cwd)"; fi
echo

# ── precode_gate.sh — PreToolUse Edit|Write ─────────────────────────────────
echo "precode_gate.sh"
run_case "edit unseen .kt blocked" precode_gate.sh 2 \
  "{\"tool_name\":\"Edit\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_UNSEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
run_case "edit .kt read earlier allowed" precode_gate.sh 0 \
  "{\"tool_name\":\"Edit\",\"transcript_path\":\"${SEEN_TR}\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
run_case "brand-new file allowed" precode_gate.sh 0 \
  "{\"tool_name\":\"Write\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${SANDBOX}/BrandNew.kt\",\"content\":\"class BrandNew\"}}"
run_case "non-kotlin file allowed" precode_gate.sh 0 \
  "{\"tool_name\":\"Edit\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${SANDBOX}/notes.md\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
run_case "escape hatch honoured" precode_gate.sh 0 \
  "{\"tool_name\":\"Edit\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_UNSEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}" \
  PRECODE_GATE=0
# Ledger branch: the transcript is EMPTY in all three cases below, which is what
# the running turn actually looks like on disk. Without the ledger the first case
# is the false positive that blocked correct Read-then-Edit work (2026-08-04).
run_case "ledger hit allows edit despite empty transcript" precode_gate.sh 0 \
  "{\"tool_name\":\"Edit\",\"session_id\":\"SESS-A\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
run_case "ledger entry from another session does not count" precode_gate.sh 2 \
  "{\"tool_name\":\"Edit\",\"session_id\":\"SESS-B\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
run_case "ledger does not cover a file never read" precode_gate.sh 2 \
  "{\"tool_name\":\"Edit\",\"session_id\":\"SESS-A\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_UNSEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
echo

# ── read_ledger.sh — PostToolUse Read ───────────────────────────────────────
echo "read_ledger.sh"
run_case "records a Read of a .kt" read_ledger.sh 0 \
  "{\"tool_name\":\"Read\",\"session_id\":\"SESS-C\",\"tool_input\":{\"file_path\":\"${KT_UNSEEN}\"}}"
run_case "ignores a non-kotlin Read" read_ledger.sh 0 \
  "{\"tool_name\":\"Read\",\"session_id\":\"SESS-C\",\"tool_input\":{\"file_path\":\"${SANDBOX}/notes.md\"}}"
run_case "malformed payload never blocks" read_ledger.sh 0 "not json at all"
run_case "escape hatch honoured" read_ledger.sh 0 \
  "{\"tool_name\":\"Read\",\"session_id\":\"SESS-C\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\"}}" \
  READ_LEDGER=0
# End-to-end: the Read that read_ledger.sh just recorded (SESS-C / Unseen.kt)
# must be what unblocks the very next edit — the exact sequence W0 box 2 asks for.
run_case "recorded Read unblocks the next edit" precode_gate.sh 0 \
  "{\"tool_name\":\"Edit\",\"session_id\":\"SESS-C\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_UNSEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
# ...and the escape-hatch case above must have recorded NOTHING, so Seen.kt is
# still unseen for SESS-C even though a Read of it was issued.
run_case "escape-hatched Read records nothing" precode_gate.sh 2 \
  "{\"tool_name\":\"Edit\",\"session_id\":\"SESS-C\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
# Grok's read_file sends target_file, not file_path. A different session so the
# SESS-C escape-hatch case above still proves Seen.kt was not recorded for SESS-C.
run_case "records a Grok read_file target_file" read_ledger.sh 0 \
  "{\"tool_name\":\"read_file\",\"session_id\":\"SESS-GROK\",\"tool_input\":{\"target_file\":\"${KT_SEEN}\"}}"
run_case "Grok target_file Read unblocks the next edit" precode_gate.sh 0 \
  "{\"tool_name\":\"Edit\",\"session_id\":\"SESS-GROK\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
echo

# ── claim_check.sh — Stop ───────────────────────────────────────────────────
echo "claim_check.sh"
run_case "unsourced file:line citation blocked" claim_check.sh 2 \
  "{\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Lỗi nằm ở Ghost.kt:4211 trong nhánh cleanup.\"}"
run_case "message without citations allowed" claim_check.sh 0 \
  "{\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã đọc qua module và chưa thấy vấn đề nào đáng báo.\"}"
# QA K-12: the loop guard is bounded, not a free pass on the first re-Stop.
run_case "re-Stop #1 still blocks (bounded guard)" claim_check.sh 2 \
  "{\"session_id\":\"cc-loop\",\"transcript_path\":\"${EMPTY_TR}\",\"stop_hook_active\":true,\"last_assistant_message\":\"Lỗi nằm ở Ghost.kt:4211.\"}"
run_case "loop guard releases on re-Stop #2" claim_check.sh 0 \
  "{\"session_id\":\"cc-loop\",\"transcript_path\":\"${EMPTY_TR}\",\"stop_hook_active\":true,\"last_assistant_message\":\"Lỗi nằm ở Ghost.kt:4211.\"}"
echo

# ── session_context.sh / prompt_context.sh — SessionStart / UserPromptSubmit ──
# Context loaders: never block (exit 0); output is what the model gets.
echo "session_context.sh / prompt_context.sh"
ctx_case() { # name hook payload expect-substring ("" = expect no output)
  out="$(printf '%s' "$3" | env CLAUDE_PROJECT_DIR="${CTX_PROJ}" bash "${HOOKS}/$2" 2>/dev/null)"; got=$?
  if [ "${got}" -eq 0 ] && { { [ -z "$4" ] && [ -z "${out}" ]; } || { [ -n "$4" ] && printf '%s' "${out}" | grep -q -- "$4"; }; }; then
    PASS=$((PASS + 1)); printf '  ok   %-46s exit=%s\n' "$1" "${got}"
  else
    FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ $1 (exit=${got}, output: $(printf '%s' "${out}" | head -2 | tr '\n' ' '))"
    printf '  FAIL %-46s\n' "$1"
  fi
}
CTX_PROJ="$(mktemp -d "${TMPDIR:-/tmp}/hookctx.XXXXXX")"
mkdir -p "${CTX_PROJ}/.agents"
printf '### [INSTINCT-001] Chống bấm đúp nút thanh toán (double-click)\n- **Hiện tượng lỗi:** click nhanh gọi API hai lần, debounce thiếu\n' > "${CTX_PROJ}/.agents/instincts.md"
printf '{"profile":"legacy"}' > "${CTX_PROJ}/.active-profile.json"
ctx_case "session start reads a pre-1.3 root profile file" session_context.sh '{}' "profile: legacy"
printf '{"profile":"web"}' > "${CTX_PROJ}/.agents/active-profile.json"
ctx_case "session start lists the profile" session_context.sh '{}' "profile: web"
ctx_case "session start maps traps with line numbers" session_context.sh '{}' "L1 \[INSTINCT-001\]"
ctx_case "prompt: bug fix gets paired RED→GREEN rule" prompt_context.sh '{"prompt":"sửa lỗi nút thanh toán bị bấm 2 lần"}' "ĐỎ trước khi sửa"
ctx_case "prompt: matching project trap is cited" prompt_context.sh '{"prompt":"sửa lỗi nút thanh toán bị bấm 2 lần"}' "INSTINCT-001"
ctx_case "prompt: XSS / SQL injection → SECURITY" prompt_context.sh '{"prompt":"sửa lỗ hổng XSS ở ô bình luận"}' "SECURITY"
ctx_case "prompt: slash command adds nothing" prompt_context.sh '{"prompt":"/compact"}' ""
ctx_case "prompt: chit-chat adds nothing" prompt_context.sh '{"prompt":"cảm ơn bạn nhiều nhé"}' ""
ctx_case "prompt: under 8 characters adds nothing" prompt_context.sh '{"prompt":"fix bug"}' ""
ctx_case "prompt: malformed payload adds nothing" prompt_context.sh 'not json sửa lỗi thanh toán' ""
PROMPT_CONTEXT_SAVE="${PROMPT_CONTEXT:-}"; export PROMPT_CONTEXT=0
ctx_case "prompt: escape hatch PROMPT_CONTEXT=0" prompt_context.sh '{"prompt":"sửa lỗi nút thanh toán bị bấm 2 lần"}' ""
unset PROMPT_CONTEXT; [ -n "${PROMPT_CONTEXT_SAVE}" ] && export PROMPT_CONTEXT="${PROMPT_CONTEXT_SAVE}"
rm -rf "${CTX_PROJ}"

# ── test_evidence_gate.sh — Stop ────────────────────────────────────────────
echo "test_evidence_gate.sh"
run_case "test-pass claim with zero XML blocked" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h1\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã chạy targeted test, 12/12 test pass.\"}"
run_case "quoted PROHIBITION is not a claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h2\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Luật 5.5 nói rõ: **cấm sửa test cho xanh** khi chưa chứng minh expectation cũ sai.\"}"
run_case "imperative dừng/đừng is not a claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h3\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đừng gọi test là pass khi XML chưa tươi hơn edit cuối.\"}"
run_case "conditional 'thì' is not a claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h4\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Test chuyển xanh thì streak reset về 0.\"}"
run_case "verify question is not a test result claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h4-verify-question\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Verify: tests pass?\"}"
run_case "test modal is not a result claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h4-test-modal\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Test should pass after the fix.\"}"
run_case "khi transition is not a result claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h4-khi-transition\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Khi test xanh thì streak reset.\"}"
run_case "canonical task verify is not a result claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h4-task-verify\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"T003 implement tối thiểu → verify: test GREEN\"}"
run_case "quoted test result assertion needs evidence" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h4-quoted-result\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Result: \\\"12/12 tests passed\\\".\"}"
run_case "pending bug A cannot hide test pass for bug B" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h4-test-pending\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Bug A chưa verify nhưng 12/12 test pass cho bug B.\"}"
run_case "negative smoke clause cannot hide unit test pass" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h4-test-negative\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Không chạy smoke, nhưng unit tests passed.\"}"
run_case "later deploy conditional cannot hide test pass" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h4-test-suffix\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"12/12 test pass, còn deploy thì chưa.\"}"
run_case "later deploy advice cannot hide test pass" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h4-test-advice\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Test pass 6/6; nếu deploy thì chạy smoke.\"}"
run_case "Vietnamese all-checks-pass phrase needs evidence" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h4-test-vietnamese\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Toàn bộ kiểm thử đều đạt.\"}"
run_case "unrelated guidance cannot hide later test pass" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h4-test-guidance-scope\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Cần kiểm tra B nhưng 12/12 test pass cho A.\"}"
run_case "first conditional test cannot hide second test pass" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h4-test-two-claims\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Test A pass thì deploy, còn test B pass.\"}"
run_case "no claim, no XML, nothing to say" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã đọc xong file rule, chưa sửa gì.\"}"
run_case "plain fixed claim without proof blocked" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-fixed\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã fix bug.\"}"
run_case "unrelated device command cannot prove fixed" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-device\",\"transcript_path\":\"${DEVICE_ONLY_TR}\",\"last_assistant_message\":\"Đã fix bug.\"}"
run_case "anonymous proof cannot authorize fixed outcome" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-anon\",\"transcript_path\":\"${ANONYMOUS_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.\"}"
run_case "Bash-produced proof cannot authorize fixed outcome" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-bash\",\"transcript_path\":\"${BASH_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.\"}"
run_case "error result cannot authorize fixed outcome" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-error\",\"transcript_path\":\"${ERROR_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "proof missing postimage provenance cannot authorize outcome" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-provenance\",\"transcript_path\":\"${MISSING_PROVENANCE_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:0000000000000000000000000000000000000000000000000000000000000000.\"}"
run_case "proof before the final edit is stale" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-stale\",\"transcript_path\":\"${STALE_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.\"}"
run_case "failed edit after proof does not make proof stale" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-failed-edit\",\"transcript_path\":\"${FAILED_EDIT_AFTER_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}" \
  LESSON_REMINDER=0  # proof acceptance, not the lesson reminder
run_case "edit with id but no result makes prior proof stale" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-unknown-edit\",\"transcript_path\":\"${UNKNOWN_EDIT_AFTER_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "successful tool after proof makes prior proof non-final" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-writer\",\"transcript_path\":\"${WRITER_AFTER_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "mutation-capable failed Bash after proof is non-final" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-error-writer\",\"transcript_path\":\"${ERROR_WRITER_AFTER_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "failed Write after proof is non-final" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-error-write\",\"transcript_path\":\"${ERROR_WRITE_AFTER_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "write between workflow use and result makes proof non-final" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-interleaved-write\",\"transcript_path\":\"${INTERLEAVED_WRITE_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "open write before workflow makes proof non-final" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-open-write\",\"transcript_path\":\"${OPEN_WRITE_BEFORE_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "write result after workflow result makes proof non-final" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-late-write\",\"transcript_path\":\"${LATE_WRITE_RESULT_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "correlated final workflow proof permits its exact fixed claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-proof\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}" \
  LESSON_REMINDER=0  # proof acceptance, not the lesson reminder
run_case "Workflow script shape permits exact fixed claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-script-proof\",\"transcript_path\":\"${CORRELATED_SCRIPT_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}" \
  LESSON_REMINDER=0  # proof acceptance, not the lesson reminder
run_case "lookalike Workflow script cannot authorize outcome" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-forged-script\",\"transcript_path\":\"${FORGED_SCRIPT_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "conflicting Workflow name and script cannot authorize" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-mixed-locator\",\"transcript_path\":\"${MIXED_LOCATOR_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "correlated final Skill proof permits its exact fixed claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-skill-proof\",\"transcript_path\":\"${CORRELATED_SKILL_PROOF_TR}\",\"last_assistant_message\":\"Đã fix \`reader|logic.wrong_branch|open|empty-input\`; scope \`sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\`, current \`sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\`, content \`sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\`.\"}" \
  LESSON_REMINDER=0  # proof acceptance, not the lesson reminder
run_case "wrong currentId cannot authorize fixed outcome" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-current\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "wrong contentHash cannot authorize fixed outcome" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-content\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee.\"}"
run_case "proof for another key and scope cannot authorize claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-unrelated\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix writer|logic.wrong_branch|save|empty-output; scope sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd.\"}"
run_case "fixed key substring cannot authorize a longer key" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-key-collision\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input-extra; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "fixed key cannot authorize at-sign suffix collision" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-key-at-collision\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input@extra; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "fixed key cannot authorize dotted suffix collision" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-key-dot-collision\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input.extra; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "fixed key cannot authorize comma suffix collision" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-key-comma-collision\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input,extra; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "fixed key cannot authorize prefixed collision" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-key-prefix-collision\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix xreader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "scope digest suffix cannot authorize outcome" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-scope-suffix\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-extra, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "current digest suffix cannot authorize outcome" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-current-suffix\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-extra, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "content digest suffix cannot authorize outcome" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-content-suffix\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc-extra.\"}"
run_case "every outcome sentence needs its own bound proof" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-multi-outcome\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc. Đã fix bug thứ hai.\"}"
run_case "every outcome occurrence in one clause needs proof" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-multi-clause\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix reader|logic.wrong_branch|open|empty-input và đã fix bug thứ hai; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "one fixed key cannot authorize two clauses in one sentence" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-key-reuse\",\"transcript_path\":\"${CORRELATED_FIX_PROOF_TR}\",\"last_assistant_message\":\"Đã fix bug A; Đã fix reader|logic.wrong_branch|open|empty-input; scope sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, current sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, content sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.\"}"
run_case "unrelated RED-GREEN text cannot authorize fixed outcome" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-redgreen\",\"transcript_path\":\"${UNRELATED_RED_GREEN_TR}\",\"last_assistant_message\":\"Đã fix bug.\"}"
run_case "quoted fixed phrase is not an outcome claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-quoted\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Không được viết \\\"đã fix\\\" khi chưa có paired proof.\"}"
run_case "quoted outcome assertion still needs proof" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-quoted-assertion\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Kết luận: \\\"Đã fix bug A\\\".\"}"
run_case "inline-code outcome assertion still needs proof" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-code-assertion\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Trạng thái: \`fixed\`.\"}"
run_case "metalinguistic quoted outcome is not a claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-meta-quote\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Cụm từ \\\"đã fix\\\" là outcome claim cần proof.\"}"
run_case "acceptance text is not an outcome result" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-acceptance\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A is fixed.\"}"
run_case "acceptance prefix cannot hide independent outcome" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-acceptance-independent\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A is fixed, nhưng đã fix bug B.\"}"
run_case "acceptance prefix cannot hide outcome after em dash" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-acceptance-em-dash\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A is fixed — đã fix bug B.\"}"
run_case "acceptance prefix cannot hide outcome after ASCII dash" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-acceptance-ascii-dash\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A is fixed - đã fix bug B.\"}"
run_case "acceptance prefix cannot hide outcome after en dash" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-acceptance-en-dash\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A is fixed – đã fix bug B.\"}"
run_case "acceptance prefix cannot hide outcome after conjunction" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-acceptance-conjunction\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A is fixed nhưng thực tế đã fix bug B.\"}"
run_case "acceptance prefix cannot hide outcome after and in fact" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-acceptance-and-fact\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A is fixed and in fact fixed bug B.\"}"
run_case "acceptance prefix cannot hide outcome after và thực tế" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-acceptance-va-fact\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A is fixed và thực tế đã fix bug B.\"}"
run_case "acceptance prefix cannot hide outcome after rồi" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-acceptance-roi\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A is fixed rồi đã fix bug B.\"}"
run_case "acceptance prefix cannot hide outcome after semicolon" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-acceptance-semicolon\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A is fixed; đã fix bug B.\"}"
run_case "acceptance prefix cannot hide outcome on next line" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-acceptance-newline\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A is fixed\\nĐã fix bug B.\"}"
run_case "additive English acceptance remains non-assertive" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-acceptance-additive-en\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A is fixed and bug B is fixed.\"}"
run_case "additive Vietnamese acceptance remains non-assertive" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-acceptance-additive-vi\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Acceptance: bug A đã fix và bug B đã fix.\"}"
run_case "verify imperative is not an outcome result" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-verify-imperative\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Verify that bug A is fixed.\"}"
run_case "outcome modal is not a result claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-outcome-modal\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Bug A must be fixed before release.\"}"
run_case "prohibition containing fixed phrase is not an outcome claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-prohibition\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Cấm nói đã fix khi chưa có paired proof.\"}"
run_case "conditional fixed phrase is not an outcome claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-conditional\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Nếu đã fix thì paired proof phải chuyển xanh.\"}"
run_case "definite outcome before trailing thì still needs proof" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-trailing-thi\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã fix bug A rồi thì tiếp tục kiểm tra B.\"}"
run_case "unrelated negative clause before outcome cannot hide it" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-negative-prefix\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Không còn blocker, đã fix bug A.\"}"
run_case "unrelated pending clause before outcome cannot hide it" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-pending-prefix\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Chưa thấy regression, đã khắc phục bug A.\"}"
run_case "negative conjunction before outcome cannot hide it" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-negative-conjunction\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Không còn blocker và đã fix bug A.\"}"
run_case "pending conjunction before outcome cannot hide it" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-pending-conjunction\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Chưa thấy regression nhưng đã khắc phục bug A.\"}"
run_case "unverified bug A cannot hide fixed bug B without comma" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-exact-conjunction\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Bug A chưa verify nhưng đã fix bug B.\"}"
run_case "dash connector cannot hide fixed bug B" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-dash-connector\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Bug A chưa verify — đã fix bug B.\"}"
run_case "tuy nhiên cannot hide fixed bug B" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-tuy-nhien\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Bug A chưa verify tuy nhiên đã fix bug B.\"}"
run_case "không chỉ does not negate a fixed claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-khong-chi\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Không chỉ đã fix bug A.\"}"
run_case "còn connector cannot hide fixed bug B" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-con-connector\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Bug A chưa verify còn bug B đã fix.\"}"
run_case "song connector cannot hide fixed bug A" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-song-connector\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Chưa thấy regression song đã khắc phục bug A.\"}"
run_case "mà connector cannot hide fixed bug B" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-ma-connector\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Bug A chưa verify mà bug B đã được sửa.\"}"
run_case "English fix works outcome needs proof" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-fix-works\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"The fix works for bug A.\"}"
run_case "đã xử lý outcome needs proof" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-handled\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã xử lý bug A.\"}"
run_case "đã giải quyết outcome needs proof" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-solved\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã giải quyết xong lỗi A.\"}"
run_case "no longer reproduces outcome needs proof" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-no-repro\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Lỗi A không còn tái hiện.\"}"
run_case "Vietnamese no-repro synonym needs proof" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-no-repro-synonym\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Bug A không tái hiện nữa.\"}"
run_case "advice conjunction before outcome cannot hide it" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-advice-conjunction\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Cần kiểm tra thêm nhưng bug A đã được sửa.\"}"
run_case "prohibition governing reported fixed phrase is not a claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h5-reported-prohibition\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Không được đoán và nói đã fix bug A.\"}"
run_case "unrelated prohibition cannot hide later fixed claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-prohibition-scope\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Không được đoán nhưng đã fix bug A.\"}"
run_case "pending bug A cannot hide fixed bug B" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-two-bugs-prefix\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Bug A chưa verify, nhưng đã fix bug B.\"}"
run_case "pending bug B after comma cannot hide fixed bug A" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-two-bugs-suffix\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã fix bug A, còn bug B thì chưa verify.\"}"
run_case "pending marker in another sentence cannot hide fixed claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-pending-scope\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã fix bug A. Bug B chưa verify.\"}"
run_case "pending marker in another clause cannot hide fixed claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h5-pending-clause\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã fix bug A; bug B BLOCKED.\"}"
# The branch that fires most often in practice: XML EXISTS and is fresh, but red.
# Found by mutation 2026-07-28 — with an empty sandbox every case landed on the
# "no XML at all" branch, so deleting the failures/errors check killed nothing.
mk_xml "${RED_XML_DIR}" "RedSuite" 6 1 0 0
run_case "fresh XML with failures>0 blocks claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h7\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã chạy targeted test, 6/6 test pass.\"}"
rm -f "${RED_XML_DIR}"/TEST-*.xml
mk_xml "${RED_XML_DIR}" "GreenSuite" 6 0 0 0
run_case "fresh green XML backs the claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h8\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã chạy targeted test, 6/6 test pass.\"}"
rm -f "${RED_XML_DIR}"/TEST-*.xml
# `gradle-test` returning total=0/UP-TO-DATE is the project's oldest false-green
# (memory: gradle-test-false-green-and-test-sourceset). An XML with tests=0 means
# NOTHING RAN, so it must not back a pass claim.
mk_xml "${RED_XML_DIR}" "EmptySuite" 0 0 0 0
run_case "tests=0 XML does not back the claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h11\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã chạy targeted test, 6/6 test pass.\"}"
rm -f "${RED_XML_DIR}"/TEST-*.xml
mk_xml "${RED_XML_DIR}" "SkipSuite" 6 0 0 2
run_case "unmentioned skipped>0 blocks claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h9\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã chạy targeted test, 6/6 test pass.\"}"
run_case "skipped>0 stated explicitly is fine" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h10\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã chạy targeted test, 6/6 test pass, có 2 case skipped do @Ignore.\"}"
rm -f "${RED_XML_DIR}"/TEST-*.xml
# Past tense is an assertion: "đã chạy lại" used to disarm the whole check.
run_case "past-tense 'đã chạy lại' still a claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h12\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã chạy lại, 12/12 test pass.\"}"
run_case "advice 'cần chạy lại' is not a claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h13\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Cần chạy lại test cho module đã sửa rồi mới nói được là pass.\"}"
run_case "escape hatch honoured" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h6\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"12/12 test pass.\"}" \
  TEST_EVIDENCE_GATE=0
# Scoping to the modules edited this session. A repo can hold suites that are red for reasons
# this turn did not cause (measured 2026-07-28: :app's Roborazzi suites fail on any machine
# without the gitignored baselines). Summing across every module made a truthful per-suite
# report unstatable. Red outside the touched module is still not free: it blocks unless named.
mkdir -p "${SANDBOX}/core/data/src/main/java" "${SANDBOX}/core/data/build/test-results/x" \
         "${SANDBOX}/other/build/test-results/x"
TOUCH_KT="${SANDBOX}/core/data/src/main/java/Touched.kt"
echo "object Touched" > "${TOUCH_KT}"
TOUCH_TR="${SANDBOX}/touched.jsonl"
mk_tr "${TOUCH_TR}" Edit "${TOUCH_KT}" "object Touched"
mk_xml "${SANDBOX}/core/data/build/test-results/x" "TouchedSuite" 6 0 0 0
mk_xml "${SANDBOX}/other/build/test-results/x" "ForeignRedSuite" 4 2 0 0
run_case "red suite outside touched module, unnamed, blocks" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h14\",\"transcript_path\":\"${TOUCH_TR}\",\"last_assistant_message\":\"Đã chạy targeted test, 6/6 test pass.\"}"
run_case "red outside touched module, named, allowed" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h15\",\"transcript_path\":\"${TOUCH_TR}\",\"last_assistant_message\":\"Đã chạy targeted test, 6/6 test pass. ForeignRedSuite vẫn đỏ 2 case, có sẵn từ trước, ngoài phạm vi sửa.\"}"
# The teeth that must NOT be lost: red INSIDE the touched module blocks even when named.
mk_xml "${SANDBOX}/core/data/build/test-results/x" "TouchedSuite" 6 1 0 0
run_case "red suite inside touched module blocks even if named" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h16\",\"transcript_path\":\"${TOUCH_TR}\",\"last_assistant_message\":\"Đã chạy targeted test, 6/6 test pass. TouchedSuite đỏ 1 case.\"}"
rm -f "${SANDBOX}/core/data/build/test-results/x"/TEST-*.xml \
      "${SANDBOX}/other/build/test-results/x"/TEST-*.xml

# ── RED-check: a mutate/restore pair must keep the red it produced ───────────
# check 2 REQUIRES mutating a load-bearing line, running it red, then putting the line back. The
# restore is ALWAYS the last edit, so counting it moved the expiry marker past the red every time:
# the better someone followed the protocol, the surer the gate was to reject them. Only an EXACT
# inverse of the most recent un-undone edit is forgiven — the third case is the teeth.
mkdir -p "${SANDBOX}/app/src/test/java" "${SANDBOX}/app/build/test-results/mut"
MUT_KT="${SANDBOX}/app/src/test/java/MutSuite.kt"
echo "class MutSuite" > "${MUT_KT}"
MUT_RESTORED_TR="${SANDBOX}/mutate-restored.jsonl"
MUT_OTHEREDIT_TR="${SANDBOX}/mutate-otheredit.jsonl"
python3 - "${MUT_RESTORED_TR}" "${MUT_OTHEREDIT_TR}" "${MUT_KT}" <<'PYX'
import json, sys
restored, otheredit, kt = sys.argv[1:]
red = '<testsuite name="com.example.MutSuite" tests="2" failures="1" errors="0" skipped="0">'
def edit(old, new):
    return {"type": "tool_use", "name": "Edit",
            "input": {"file_path": kt, "old_string": old, "new_string": new}}
def result(text):
    return {"type": "tool_result", "content": [{"type": "text", "text": text}]}
mutate = edit("POLLS = 20", "POLLS = 0")
plans = {
    restored:  [mutate, result(red), edit("POLLS = 0", "POLLS = 20")],
    otheredit: [mutate, result(red), edit("assertTrue(a)", "assertTrue(b)")],
}
for out, blocks in plans.items():
    with open(out, "w") as fh:
        for b in blocks:
            fh.write(json.dumps({"message": {"content": [b]}}) + "\n")
PYX
mk_xml "${SANDBOX}/app/build/test-results/mut" "MutSuite" 2 0 0 0
run_case "mutate/restore pair keeps its RED-check" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h-mut-restored\",\"transcript_path\":\"${MUT_RESTORED_TR}\",\"last_assistant_message\":\"Đã chạy targeted test, 2/2 test pass.\"}"
run_case "non-inverse edit after RED still expires it" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h-mut-otheredit\",\"transcript_path\":\"${MUT_OTHEREDIT_TR}\",\"last_assistant_message\":\"Đã chạy targeted test, 2/2 test pass.\"}"
rm -f "${SANDBOX}/app/build/test-results/mut"/TEST-*.xml

# Instrumented results live OUTSIDE build/test-results/ (glob widened 2026-08-07).
# connectedAndroidTest writes build/outputs/androidTest-results/connected/<variant>/.
# Before the widening the gate found no XML for a device run and blocked the claim
# as "tests never ran" — which is every release-QA claim in this repo.
# Every unit-test XML is cleared first ON PURPOSE: with a green unit XML lying
# around both cases below would pass through the OLD globs and prove nothing.
# Mutation: drop the three androidTest patterns from test_evidence_gate.sh and
# the first case goes red.
rm -f "${SANDBOX}"/*/build/test-results/*/TEST-*.xml \
      "${SANDBOX}"/*/*/build/test-results/*/TEST-*.xml 2>/dev/null || true
INSTR_DIR="${SANDBOX}/app/build/outputs/androidTest-results/connected/release"
INSTR_KT="${SANDBOX}/app/src/main/java/Instr.kt"
mkdir -p "${INSTR_DIR}" "$(dirname "${INSTR_KT}")"
echo "object Instr" > "${INSTR_KT}"
INSTR_TR="${SANDBOX}/instr.jsonl"
mk_tr "${INSTR_TR}" Edit "${INSTR_KT}" "object Instr"
mk_xml "${INSTR_DIR}" "InstrSuite" 1 0 0 0
run_case "green instrumented XML backs a pass claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h40\",\"transcript_path\":\"${INSTR_TR}\",\"last_assistant_message\":\"Đã chạy instrumented test trên máy thật, 1/1 test pass.\"}"
mk_xml "${INSTR_DIR}" "InstrSuite" 1 1 0 0
run_case "red instrumented XML blocks a pass claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h41\",\"transcript_path\":\"${INSTR_TR}\",\"last_assistant_message\":\"Đã chạy instrumented test trên máy thật, 1/1 test pass.\"}"
rm -f "${INSTR_DIR}"/TEST-*.xml

# The two cases above use mk_xml, whose root element is <testsuite> — the UNIT
# test layout. Real connectedAndroidTest output wraps suites in a <testsuites>
# root, and the gate's parser rejected that outright until 2026-08-07. A fixture
# in the wrong shape is why the glob fix alone still left the gate blind, so
# these two cases use the AGP shape verbatim.
# mk_xml_suites <dir> <suite> <tests> <failures> <errors> <skipped>
mk_xml_suites() {
  cat > "$1/TEST-${2}.xml" <<XML
<?xml version='1.0' encoding='UTF-8' ?>
<testsuites tests="${3}" failures="${4}" errors="${5}" skipped="${6}" time="1.5" hostname="localhost">
  <testsuite name="com.example.${2}" tests="${3}" failures="${4}" errors="${5}" skipped="${6}" time="1.5" hostname="localhost">
    <testcase name="doesSomething" classname="com.example.${2}" time="0.7"/>
  </testsuite>
</testsuites>
XML
  touch "$1/TEST-${2}.xml"
}
mk_xml_suites "${INSTR_DIR}" "WrappedSuite" 1 0 0 0
run_case "green <testsuites>-wrapped XML backs a pass claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"h42\",\"transcript_path\":\"${INSTR_TR}\",\"last_assistant_message\":\"Đã chạy instrumented test trên máy thật, 1/1 test pass.\"}"
mk_xml_suites "${INSTR_DIR}" "WrappedSuite" 1 1 0 0
run_case "red <testsuites>-wrapped XML blocks a pass claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"h43\",\"transcript_path\":\"${INSTR_TR}\",\"last_assistant_message\":\"Đã chạy instrumented test trên máy thật, 1/1 test pass.\"}"
rm -f "${INSTR_DIR}"/TEST-*.xml
echo

# ── churn_guard.sh — PostToolUse ────────────────────────────────────────────
echo "churn_guard.sh"
run_case "3rd blind edit of one file warns" churn_guard.sh 2 \
  "{\"tool_name\":\"Edit\",\"transcript_path\":\"${CHURN_TR}\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
run_case "evidence between edits stays quiet" churn_guard.sh 0 \
  "{\"tool_name\":\"Edit\",\"transcript_path\":\"${EVID_TR}\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
for c in "edits after the last evidence call warn|2|${CHURN_AFTER_TR}" \
         "edits before the last evidence call stay quiet|0|${CHURN_BEFORE_TR}" \
         "a blocked edit (is_error result) is not counted|0|${CHURN_ERR_TR}"; do
  IFS='|' read -r cname cexp ctr <<< "$c"
  run_case "$cname" churn_guard.sh "$cexp" \
    "{\"tool_name\":\"Edit\",\"transcript_path\":\"${ctr}\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
done
run_case "escape hatch honoured" churn_guard.sh 0 \
  "{\"tool_name\":\"Edit\",\"transcript_path\":\"${CHURN_TR}\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}" \
  CHURN_GUARD=0
echo

# ── comment_claim_guard.sh — PostToolUse ────────────────────────────────────
echo "comment_claim_guard.sh"
run_case "'covered by' claim in comment warns" comment_claim_guard.sh 2 \
  "{\"tool_name\":\"Edit\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\",\"old_string\":\"a\",\"new_string\":\"// đã test, covered by SeenTest\\nval x = 1\"}}"
run_case "negative claim in comment warns" comment_claim_guard.sh 2 \
  "{\"tool_name\":\"Edit\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\",\"old_string\":\"a\",\"new_string\":\"// hàm này không dùng ở đâu nữa\\nval x = 1\"}}"
run_case "plain descriptive comment quiet" comment_claim_guard.sh 0 \
  "{\"tool_name\":\"Edit\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_SEEN}\",\"old_string\":\"a\",\"new_string\":\"// gom hai nhánh cho dễ đọc\\nval x = 1\"}}"
run_case "non-code file not scanned" comment_claim_guard.sh 0 \
  "{\"tool_name\":\"Write\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${SANDBOX}/notes.md\",\"content\":\"// đã test, covered by SeenTest\"}}"
echo

# ── testsourceset_gate.sh — Stop (documented SKIP paths only) ───────────────
# ── regression_gate.sh — Stop (full scenarios: tests/test_regression_gate_hook.sh) ──
echo "regression_gate.sh"
run_case "not a git repo: allowed (silent)"     regression_gate.sh 0 \
  '{"session_id":"s","hook_event_name":"Stop"}'
run_case "REGRESSION_GATE=0 escape hatch"        regression_gate.sh 0 \
  '{"session_id":"s","hook_event_name":"Stop"}' REGRESSION_GATE=0
run_case "malformed stdin fails open"            regression_gate.sh 0 \
  'not json'
echo

echo "testsourceset_gate.sh"
run_case "no ./gradlew in root → skip" testsourceset_gate.sh 0 \
  "{\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"xong\"}"
run_case "escape hatch honoured" testsourceset_gate.sh 0 \
  "{\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"xong\"}" \
  TESTSOURCESET_GATE=0
echo

# ── Non-Claude harness (Grok) — hooks/devkit_harness.py + the two heavy Stop gates ──
# Grok runs these Claude hooks with a camelCase envelope, GROK_* env and its own
# transcript (updates.jsonl). Contract: detection says so; its session-end Stop
# (reason ≠ end_turn) runs no build or suite; a real turn end is still gated.
echo "devkit_harness.py / Grok Stop"
GROK_TR="${SANDBOX}/grok_updates.jsonl"
printf '%s\n' '{"timestamp":1790240706,"method":"_x.ai/session/update","params":{"sessionId":"g"}}' > "${GROK_TR}"
CLAUDE_TR="${SANDBOX}/claude_tr.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"hi"},"sessionId":"c"}' > "${CLAUDE_TR}"
harness_case() { # name payload expect(agent:degraded) [ENV=VAL …]
  hname="$1"; hpayload="$2"; hwant="$3"; shift 3
  hgot="$(printf '%s' "${hpayload}" | env -u GROK_HOOK_EVENT -u GROK_HOOK_NAME -u DEVKIT_AGENT "$@" \
          python3 "${HOOKS}/devkit_harness.py" detect 2>/dev/null \
          | python3 -c 'import json,sys; d=json.load(sys.stdin); print("%s:%s" % (d["agent"], int(d["degraded"])))' 2>/dev/null)"
  if [ "${hgot}" = "${hwant}" ]; then
    PASS=$((PASS + 1)); printf '  ok   %-46s %s\n' "${hname}" "${hgot}"
  else
    FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ ${hname} (want ${hwant}, got '${hgot}')"; printf '  FAIL %-46s want=%s got=%s\n' "${hname}" "${hwant}" "${hgot}"
  fi
}
harness_case "Claude transcript → claude, not degraded" \
  "{\"session_id\":\"c\",\"transcript_path\":\"${CLAUDE_TR}\"}" "claude:0"
harness_case "empty Claude transcript → claude, not degraded" \
  "{\"session_id\":\"c\",\"transcript_path\":\"${EMPTY_TR}\"}" "claude:0"
harness_case "Grok envelope + updates.jsonl → grok, degraded" \
  "{\"hookEventName\":\"stop\",\"sessionId\":\"g\",\"session_id\":\"g\",\"transcript_path\":\"${GROK_TR}\"}" "grok:1"
harness_case "GROK_HOOK_EVENT env alone → grok" \
  "{\"session_id\":\"g\",\"transcript_path\":\"${CLAUDE_TR}\"}" "grok:1" GROK_HOOK_EVENT=stop
harness_case "foreign transcript, no marker → unknown, degraded" \
  "{\"session_id\":\"u\",\"transcript_path\":\"${GROK_TR}\"}" "unknown:1"
harness_case "no transcript at all → unknown, degraded" \
  '{"session_id":"u"}' "unknown:1"
harness_case "bridged agent (DEVKIT_AGENT=codex) → codex" \
  '{"session_id":"b"}' "codex:1" DEVKIT_AGENT=codex
NOSID_A="$(printf '{"cwd":"/x"}' | HOOK_PPID=42 python3 "${HOOKS}/devkit_harness.py" detect 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["session"])' 2>/dev/null)"
NOSID_B="$(printf '{"cwd":"/x"}' | HOOK_PPID=42 python3 "${HOOKS}/devkit_harness.py" detect 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["session"])' 2>/dev/null)"
NOSID_C="$(printf '{"cwd":"/x"}' | HOOK_PPID=43 python3 "${HOOKS}/devkit_harness.py" detect 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["session"])' 2>/dev/null)"
if [ -n "${NOSID_A}" ] && [ "${NOSID_A}" = "${NOSID_B}" ] && [ "${NOSID_A}" != "${NOSID_C}" ]; then
  PASS=$((PASS + 1)); printf '  ok   %-46s\n' "no session id: key = harness pid + cwd, stable"
else
  FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ no-session key (${NOSID_A} / ${NOSID_B} / ${NOSID_C})"; printf '  FAIL %-46s\n' "no session id: key = harness pid + cwd, stable"
fi

# The two heavy Stop gates on a project whose build and suite FAIL: Grok's session-end
# Stop is allowed without running them; its real turn end is still blocked.
GK_PROJ="$(mktemp -d "${TMPDIR:-/tmp}/hookgrok.XXXXXX")"
(
  cd "${GK_PROJ}" && git init -q . && mkdir -p lib/src/main .agents && touch lib/build.gradle.kts \
  && printf '#!/bin/bash\necho run >> "%s/gk_gradle_runs"\necho "e: A.kt:1:1 Unresolved reference: nope"\nexit 1\n' "${SANDBOX}" > gradlew \
  && chmod +x gradlew \
  && printf '{"project":"t","rules":[{"component":"c","watch_files":["lib/**"],"mandatory_regression_tests":[{"id":"REG-GK","name":"c","command":"echo run >> %s/gk_suite_runs; exit 1"}]}]}\n' "${SANDBOX}" > .agents/regression_matrix.active.json \
  && git add . && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'class A\n' > lib/src/main/A.kt
) >/dev/null 2>&1
GK_END="{\"hookEventName\":\"stop\",\"hook_event_name\":\"Stop\",\"sessionId\":\"gk\",\"session_id\":\"gk\",\"transcript_path\":\"${GROK_TR}\",\"reason\":\"channel_closed\"}"
GK_TURN="{\"hookEventName\":\"stop\",\"hook_event_name\":\"Stop\",\"sessionId\":\"gk2\",\"session_id\":\"gk2\",\"transcript_path\":\"${GROK_TR}\",\"reason\":\"end_turn\"}"
run_case "testsourceset: Grok session-end Stop → allow" testsourceset_gate.sh 0 "${GK_END}" \
  CLAUDE_PROJECT_DIR="${GK_PROJ}" GROK_HOOK_EVENT=stop
run_case "regression_gate: Grok session-end Stop → allow" regression_gate.sh 0 "${GK_END}" \
  CLAUDE_PROJECT_DIR="${GK_PROJ}" GROK_HOOK_EVENT=stop
if [ ! -e "${SANDBOX}/gk_gradle_runs" ] && [ ! -e "${SANDBOX}/gk_suite_runs" ]; then
  PASS=$((PASS + 1)); printf '  ok   %-46s\n' "session-end Stop ran no gradle and no suite"
else
  FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ session-end Stop ran gradle or the suite"; printf '  FAIL %-46s\n' "session-end Stop ran no gradle and no suite"
fi
run_case "testsourceset: Grok turn end, broken src/test → block" testsourceset_gate.sh 2 "${GK_TURN}" \
  CLAUDE_PROJECT_DIR="${GK_PROJ}" GROK_HOOK_EVENT=stop
run_case "regression_gate: Grok turn end, failing suite → block" regression_gate.sh 2 "${GK_TURN}" \
  CLAUDE_PROJECT_DIR="${GK_PROJ}" GROK_HOOK_EVENT=stop
# `reason` switches nothing off outside Grok (Claude sends none; a future one must not).
run_case "non-Grok Stop with a reason is still gated" regression_gate.sh 2 \
  "{\"session_id\":\"gk3\",\"transcript_path\":\"${CLAUDE_TR}\",\"reason\":\"shutdown\"}" \
  CLAUDE_PROJECT_DIR="${GK_PROJ}"
rm -rf "${GK_PROJ}"
echo

# ── proof_gate.sh — Stop (rules/essentials.md "Every prompt": XONG carries this turn's PNG) ──
echo "proof_gate.sh"
# XONG needs this turn's `post-fix-gate --run-tests --full` exit 0 AND a fresh proof PNG: a
# tiny git project with a passing matrix, the gate run after the turn's user message.
PG="${SANDBOX}/proof_repo"; PG_TR="${SANDBOX}/proof_turn.jsonl"
mkdir -p "${PG}/src" "${PG}/templates" "${PG}/reports"
( cd "${PG}" && git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt && echo 'exit 0' > result.sh
  printf '%s' '{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh"}]}]}' \
    > templates/regression_matrix.json
  git add -A && git commit -qm init && echo "fun ok() = 2" > src/Core.kt )
python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X"}}))' > "${PG_TR}"
sleep 1
CLAUDE_PROJECT_DIR="${PG}" python3 "${HOOKS}/../bin/post-fix-gate.py" --run-tests --full --no-checklist >/dev/null 2>&1
PG_PNG="reports/proof-$(date +%Y%m%d-%H%M%S).png"   # named for this turn: the gate reads the time in the name
python3 - "${PG}/${PG_PNG}" <<'PY'
import os, struct, sys, zlib
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
                              + chunk(b"IDAT", os.urandom(20000)) + chunk(b"IEND", b""))
PY
run_case "CHƯA XONG is not checked" proof_gate.sh 0 \
  "{\"session_id\":\"pg-1\",\"transcript_path\":\"${PG_TR}\",\"last_assistant_message\":\"CHƯA XONG\\nKhông có thiết bị.\"}" CLAUDE_PROJECT_DIR="${PG}"
run_case "XONG without this turn's proof PNG blocked" proof_gate.sh 2 \
  "{\"session_id\":\"pg-2\",\"transcript_path\":\"${PG_TR}\",\"last_assistant_message\":\"XONG\\nĐã sửa lỗi X.\\n1. Đã fix: X\\n2. Chặn bug cũ: REG PASS\\n3. Nguy cơ bug mới: không\\n4. An toàn mã nguồn: sạch\"}" CLAUDE_PROJECT_DIR="${PG}"
run_case "XONG naming a fresh real PNG allowed" proof_gate.sh 0 \
  "{\"session_id\":\"pg-3\",\"transcript_path\":\"${PG_TR}\",\"last_assistant_message\":\"XONG\\nảnh ${PG_PNG}\\n1. Đã fix: X\\n2. Chặn bug cũ: REG PASS\\n3. Nguy cơ bug mới: không\\n4. An toàn mã nguồn: sạch\"}" CLAUDE_PROJECT_DIR="${PG}"
run_case "PROOF_GATE=0 escape hatch allows" proof_gate.sh 0 \
  "{\"session_id\":\"pg-4\",\"transcript_path\":\"${PG_TR}\",\"last_assistant_message\":\"XONG\\nĐã sửa lỗi X.\"}" CLAUDE_PROJECT_DIR="${PG}" PROOF_GATE=0
echo

# ── test_evidence_gate.sh — quoted / negated claims, foreign-project XML (2026-09-25) ──
# A reply that only QUOTES evidence another hook/session wrote, or says the tests were NOT run,
# makes no pass claim. A pass claim backed by TEST-*.xml this session produced in ANOTHER
# project (and read with its own Bash) is backed. Every case runs in its own empty project.
echo "test_evidence_gate.sh — attribution, negation, foreign XML"
TE_P="$(mktemp -d "${TMPDIR:-/tmp}/hookte.XXXXXX")"
te_case() { # name want session message [transcript]
  run_case "$1" test_evidence_gate.sh "$2" \
    "$(python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "transcript_path": sys.argv[3], "last_assistant_message": sys.argv[2]}))' \
       "$3" "$4" "${5:-${EMPTY_TR}}")" CLAUDE_PROJECT_DIR="${TE_P}"
}
te_ledger() { # project [session start_offset_s end_offset_s]... — rewrite its Bash-window ledger
  _tl="$1/.claude/audit-gate/bash_write_ledger.tsv"; shift; mkdir -p "$(dirname "${_tl}")"
  python3 - "${_tl}" "$@" <<'PY'
import sys, time
now, a = time.time(), sys.argv[2:]
with open(sys.argv[1], "w") as fh:
    for i in range(0, len(a), 3):
        fh.write(f"{a[i]}\tstart\t{now + float(a[i + 1])}\tt{i}\n{a[i]}\tend\t{now + float(a[i + 2])}\tt{i}\n")
PY
}
te_case "claim attributed to another hook is not a claim"        0 te-a1 "The evidence logs written by another hook at 08:41 say the tests passed."
te_case "claim attributed to another session (vi) is not a claim" 0 te-a2 "Phiên khác ghi log lúc 08:41 là 12/12 test pass, phiên này chưa chạy lại."
te_case "negated run: chưa chạy test is not a claim"             0 te-a3 "Chưa chạy test, nên chưa biết test có pass hay không."
te_case "negated result: tests did not pass is not a claim"      0 te-a4 "The 3 tests did not pass on CI."
te_case "fix attributed to another session is not an outcome"    0 te-a5 "Phiên khác báo đã fix bug A; phiên này chưa kiểm."
te_case "claim the user made is not a claim"                   0 te-a6 "The user said \"13/13 tests pass\" on their machine."
te_case "guard: other-hook fail then contrast still a claim"     2 te-g1 "Hook khác báo fail, nhưng giờ 13/13 test pass."
te_case "guard: another session broke it; tests pass claimed"    2 te-g2 "Another session broke it; now 12/12 tests pass."
te_case "guard: negated smoke run cannot hide test pass"         2 te-g3 "Didn't run smoke so I only know 12/12 tests passed."
te_case "guard: plain unbacked pass claim still blocked"         2 te-g4 "JUnit XML shows 13/13 tests passed, 0 failures."
te_case "guard: plain unbacked fixed claim still blocked"        2 te-g5 "Đã fix bug A."
# The agent's OWN earlier run / session is not someone else's words, and neither is an agent's
# (a leader relaying a subagent's unverified claim): these are checked against evidence.
te_case "guard: previous run of mine is still a claim"          2 te-p1 "Previous run: 13/13 tests pass."
te_case "guard: earlier run of mine is still a claim"           2 te-p2 "The earlier run shows all 42 tests passed, 0 failures."
te_case "guard: lần chạy trước is still a claim"                2 te-p3 "Lần chạy trước 13/13 test pass."
te_case "guard: previous session fixed is still an outcome"     2 te-p4 "Previous session fixed bug A."
te_case "guard: other agent's relayed pass is still a claim"    2 te-p5 "The other agent ran the suite: 13/13 tests pass."
te_case "guard: agent khác relayed fix is still an outcome"     2 te-p6 "Agent khác báo đã fix bug A; phiên này chưa kiểm."
# The user's report is attributed, the agent's own claim after the comma is not (review 2026-09-25).
te_case "guard: user reported X, fixed it (own claim after comma)" 2 te-p7 "User reported the login crash, fixed it in LoginViewModel."
te_case "guard: user reported X, N tests pass now"                2 te-p8 "The user reported a crash on submit, 13/13 tests pass now."
te_case "guard: người dùng báo X, đã fix xong"                    2 te-p9 "Người dùng báo crash khi mở PDF, đã fix xong."
# Punctuation right after the reporting verb still quotes them (review 2026-09-25 P2).
te_case "user said: quote is not a claim"                        0 te-q1 "The user said: \"13/13 tests pass\" on their machine."
te_case "phiên khác báo: is not a claim"                         0 te-q2 "Phiên khác báo: 12/12 test pass, phiên này chưa chạy lại."
te_case "another session reported, at T, that … is not a claim"  0 te-q3 "Another session reported, at 08:41, that 12/12 tests pass; this one has not re-run them."
te_case "another hook's logs say: is not a claim"                0 te-q4 "The evidence logs written by another hook say: the tests passed."
te_case "người dùng báo: đã fix is not an outcome"               0 te-q5 "Người dùng báo: đã fix xong trên máy họ."
te_case "guard: user said: X, then own pass claim"              2 te-q6 "The user said: it crashed, and now 13/13 tests pass."
# … but a bare comma after the verb, ", that's …" or a first-person claim after ":" is the agent's own (review 2).
te_case "guard: user reported X, that's fixed"                   2 te-q7 "The user reported the login crash, that's fixed in LoginViewModel."
te_case "guard: người dùng báo X, là lỗi … đã fix xong"           2 te-q8 "Người dùng báo crash khi mở PDF, là lỗi null nay đã fix xong."
te_case "guard: user reported, fixed it"                         2 te-q9 "The user reported, fixed it in LoginViewModel."
te_case "guard: người dùng báo, đã fix xong"                     2 te-q10 "Người dùng báo, đã fix xong."
te_case "guard: user said, N tests pass after my change"         2 te-q11 "User said, 13/13 tests pass after my change."
te_case "guard: user reports: I fixed it"                        2 te-q12 "The user reports: I fixed it in LoginViewModel."
te_case "guard: user reported X, that N tests pass is confirmed" 2 te-q13 "User reported a crash on submit, that 13/13 tests pass now is confirmed."
# Foreign project: a Gradle root outside CLAUDE_PROJECT_DIR whose XML this session read.
TE_F="$(mktemp -d "${TMPDIR:-/tmp}/hooktef.XXXXXX")"; TE_OLD="$(mktemp -d "${TMPDIR:-/tmp}/hookteo.XXXXXX")"
TE_RED="$(mktemp -d "${TMPDIR:-/tmp}/hooketr.XXXXXX")"
: > "${TE_P}/gradlew"                                          # the current project is Gradle, with no XML
for r in "${TE_F}" "${TE_OLD}" "${TE_RED}"; do
  : > "${r}/gradlew"; mkdir -p "${r}/app/build/test-results/testDebugUnitTest" "${r}/app/src/main/java"
  printf 'class A\n' > "${r}/app/src/main/java/A.kt"
done
touch -t 202001010000 "${TE_F}/app/src/main/java/A.kt"
mk_xml "${TE_F}/app/build/test-results/testDebugUnitTest"   GreenSuite 13 0 0 0
mk_xml "${TE_OLD}/app/build/test-results/testDebugUnitTest" GreenSuite 13 0 0 0
mk_xml "${TE_RED}/app/build/test-results/testDebugUnitTest" RedSuite   13 1 0 0
touch -t 202001010000 "${TE_OLD}/app/build/test-results/testDebugUnitTest/TEST-GreenSuite.xml"
python3 - "${SANDBOX}" "${TE_F}" "${TE_OLD}" "${TE_RED}" <<'PY'
import json, os, sys, time
sb, green, old, red = sys.argv[1:5]
start = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 600))
def w(name, blocks):
    with open(os.path.join(sb, name), "w") as fh:
        for i, b in enumerate(blocks):
            fh.write(json.dumps({"timestamp": start, "message": {"content": [b]}}) + "\n")
def bash(i, cmd):
    return [{"type": "tool_use", "id": f"b{i}", "name": "Bash", "input": {"command": cmd}},
            {"type": "tool_result", "tool_use_id": f"b{i}", "content": "ok"}]
xml = "app/build/test-results/testDebugUnitTest/TEST-%s.xml"
w("te_f_cat.jsonl", bash(1, "cat " + os.path.join(green, xml % "GreenSuite")))
w("te_f_cd.jsonl", bash(1, f"cd {green} && ./gradlew :app:testDebugUnitTest --console=plain | tail -5"))
w("te_f_edit.jsonl", [{"type": "tool_use", "id": "e1", "name": "Edit", "input": {
    "file_path": os.path.join(green, "app/src/main/java/A.kt"), "old_string": "A", "new_string": "A"}},
    {"type": "tool_result", "tool_use_id": "e1", "content": "ok"}] + bash(2, f"ls {green}/app/build/test-results"))
w("te_f_none.jsonl", bash(1, "ls /tmp >/dev/null"))
w("te_f_old.jsonl", bash(1, "cat " + os.path.join(old, xml % "GreenSuite")))
w("te_f_red.jsonl", bash(1, "cat " + os.path.join(red, xml % "RedSuite")))
PY
MSG_F="JUnit XML in the other project shows 13/13 tests passed, 0 failures."
# Foreign XML counts only when a Bash window of THIS session (the ledger) produced it.
te_ledger "${TE_P}" te-f1 -600 600
te_case "foreign XML read by this session backs the claim"      0 te-f1 "${MSG_F}" "${SANDBOX}/te_f_cat.jsonl"
te_ledger "${TE_P}" te-f2 -600 600
te_case "foreign Gradle root run via cd backs the claim"        0 te-f2 "${MSG_F}" "${SANDBOX}/te_f_cd.jsonl"
te_ledger "${TE_P}" te-f3 -600 600
te_case "foreign module edited then its XML read backs claim"   0 te-f3 "${MSG_F}" "${SANDBOX}/te_f_edit.jsonl"
te_ledger "${TE_P}" te-f7 -7200 -3600
te_case "guard: foreign XML only read, no window of mine"       2 te-f7 "${MSG_F}" "${SANDBOX}/te_f_cat.jsonl"
te_ledger "${TE_P}" te-other -600 600
te_case "guard: foreign XML another session's window produced"  2 te-f8 "${MSG_F}" "${SANDBOX}/te_f_cat.jsonl"
rm -f "${TE_P}/.claude/audit-gate/bash_write_ledger.tsv"
te_case "guard: foreign XML only read, no ledger at all"        2 te-f9 "${MSG_F}" "${SANDBOX}/te_f_cat.jsonl"
te_case "guard: foreign XML no Bash of this session named"      2 te-f4 "${MSG_F}" "${SANDBOX}/te_f_none.jsonl"
te_case "guard: foreign XML older than the session"             2 te-f5 "${MSG_F}" "${SANDBOX}/te_f_old.jsonl"
te_case "guard: foreign XML with a failure"                     2 te-f6 "${MSG_F}" "${SANDBOX}/te_f_red.jsonl"
rm -rf "${TE_P}" "${TE_F}" "${TE_OLD}" "${TE_RED}"
echo

# ── security_gate.sh — Stop (CLAUDE.md check 4c) ────────────────────────────
echo "security_gate.sh"
# must-NOT-fire cases come from files touched in THIS repo that are full of the
# trigger words but are not app attack surface — rule files and the gate itself.
# Docs QUOTE the very patterns the gate hunts for — `machine_gate_layer.md` and
# CLAUDE.md both do. Mutation 2026-07-28: the first version of this fixture had no
# real trigger in it, so it passed for free and left the `.md` exemption untested.
mk_tr "${SANDBOX}/sg_rule.jsonl"     Edit "${SANDBOX}/CLAUDE.md" \
  "ví dụ trigger: <uses-permission android:name=\"android.permission.INTERNET\"/> và javaScriptEnabled = true"
mk_tr "${SANDBOX}/sg_hook.jsonl"     Write "${SANDBOX}/.claude/hooks/security_gate.sh" \
  "PAT_WEBVIEW setJavaScriptEnabled addJavascriptInterface uses-permission"
mk_tr "${SANDBOX}/sg_unittest.jsonl" Edit "${SANDBOX}/core/analytics/src/test/java/PiiSanitizerTest.kt" \
  "assertThat(sanitize(\"apiKey=secret\")).isEqualTo(\"apiKey=***\")"
mk_tr "${SANDBOX}/sg_plain.jsonl"    Edit "${SANDBOX}/feature/reader/src/main/java/ReaderScreen.kt" \
  "Text(text = title, style = MaterialTheme.typography.titleMedium)"
mk_tr "${SANDBOX}/sg_manifest.jsonl" Edit "${SANDBOX}/app/src/main/AndroidManifest.xml" \
  "<uses-permission android:name=\"android.permission.READ_EXTERNAL_STORAGE\"/>"
mk_tr "${SANDBOX}/sg_webview.jsonl"  Edit "${SANDBOX}/feature/html/src/main/java/HtmlViewer.kt" \
  "webView.settings.javaScriptEnabled = true"
mk_tr "${SANDBOX}/sg_signing.jsonl"  Edit "${SANDBOX}/app/build.gradle.kts" \
  "storePassword = providers.gradleProperty(\"RELEASE_STORE_PASSWORD\").get()"
mk_tr "${SANDBOX}/sg_analytics.jsonl" Edit "${SANDBOX}/core/analytics/src/main/java/Reporter.kt" \
  "firebaseAnalytics.logEvent(\"search_performed\", bundleOf(\"query\" to raw))"
mk_tr "${SANDBOX}/sg_reviewed.jsonl" Edit "${SANDBOX}/app/src/main/AndroidManifest.xml" \
  "<uses-permission android:name=\"android.permission.INTERNET\"/>" WITH_SCAN

run_case "rule file full of trigger words quiet"  security_gate.sh 0 \
  "{\"session_id\":\"sg1\",\"transcript_path\":\"${SANDBOX}/sg_rule.jsonl\",\"last_assistant_message\":\"xong\"}"
run_case "the gate's own source quiet"            security_gate.sh 0 \
  "{\"session_id\":\"sg2\",\"transcript_path\":\"${SANDBOX}/sg_hook.jsonl\",\"last_assistant_message\":\"xong\"}"
run_case "unit test mentioning secrets quiet"     security_gate.sh 0 \
  "{\"session_id\":\"sg3\",\"transcript_path\":\"${SANDBOX}/sg_unittest.jsonl\",\"last_assistant_message\":\"xong\"}"
run_case "ordinary UI kotlin quiet"               security_gate.sh 0 \
  "{\"session_id\":\"sg4\",\"transcript_path\":\"${SANDBOX}/sg_plain.jsonl\",\"last_assistant_message\":\"xong\"}"
run_case "manifest permission change blocked"     security_gate.sh 2 \
  "{\"session_id\":\"sg5\",\"transcript_path\":\"${SANDBOX}/sg_manifest.jsonl\",\"last_assistant_message\":\"xong\"}"
run_case "enabling WebView JS blocked"            security_gate.sh 2 \
  "{\"session_id\":\"sg6\",\"transcript_path\":\"${SANDBOX}/sg_webview.jsonl\",\"last_assistant_message\":\"xong\"}"
run_case "signing/keystore change blocked"        security_gate.sh 2 \
  "{\"session_id\":\"sg7\",\"transcript_path\":\"${SANDBOX}/sg_signing.jsonl\",\"last_assistant_message\":\"xong\"}"
run_case "analytics payload change blocked"       security_gate.sh 2 \
  "{\"session_id\":\"sg8\",\"transcript_path\":\"${SANDBOX}/sg_analytics.jsonl\",\"last_assistant_message\":\"xong\"}"
run_case "trigger + security review ran → pass"   security_gate.sh 0 \
  "{\"session_id\":\"sg9\",\"transcript_path\":\"${SANDBOX}/sg_reviewed.jsonl\",\"last_assistant_message\":\"xong\"}"
run_case "escape hatch honoured"                  security_gate.sh 0 \
  "{\"session_id\":\"sg10\",\"transcript_path\":\"${SANDBOX}/sg_manifest.jsonl\",\"last_assistant_message\":\"xong\"}" \
  SECURITY_GATE=0
echo

# ── review_gate.sh — Stop ───────────────────────────────────────────────────
echo "review_gate.sh"
run_case "no uncommitted kotlin → nothing to review" review_gate.sh 0 \
  "{\"session_id\":\"rg1\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"xong\"}"
# Profile-aware: on a web project an unreviewed .ts change blocks; a later
# open-code-review Skill run counts as the review.
RG_WEB="$(mktemp -d "${TMPDIR:-/tmp}/hookrgweb.XXXXXX")"
( cd "${RG_WEB}" && git init -q . && git config user.email t@t && git config user.name t \
  && mkdir -p src .agents/active-profile && echo "export const a = 1" > src/app.ts \
  && cp "${HOOKS}/../profiles/web/profile.json" .agents/active-profile/profile.json \
  && git add src && git commit -qm init && echo "export const a = 2" > src/app.ts )
python3 - "${RG_WEB}" <<'PY'
import json, os, sys
d = sys.argv[1]
edit = {"type": "tool_use", "id": "e1", "name": "Edit",
        "input": {"file_path": os.path.join(d, "src", "app.ts"), "old_string": "1", "new_string": "2"}}
review = {"type": "tool_use", "id": "s1", "name": "Skill", "input": {"skill": "open-code-review"}}
for name, blocks in (("unreviewed.jsonl", [edit]), ("reviewed.jsonl", [edit, review])):
    with open(os.path.join(d, name), "w") as fh:
        for b in blocks:
            fh.write(json.dumps({"message": {"content": [b]}}) + "\n")
PY
run_case "web profile: unreviewed .ts change blocks" review_gate.sh 2 \
  "{\"session_id\":\"rgweb1\",\"cwd\":\"${RG_WEB}\",\"transcript_path\":\"${RG_WEB}/unreviewed.jsonl\",\"last_assistant_message\":\"xong\"}" \
  CLAUDE_PROJECT_DIR="${RG_WEB}"
run_case "web profile: open-code-review after the edit passes" review_gate.sh 0 \
  "{\"session_id\":\"rgweb2\",\"cwd\":\"${RG_WEB}\",\"transcript_path\":\"${RG_WEB}/reviewed.jsonl\",\"last_assistant_message\":\"xong\"}" \
  CLAUDE_PROJECT_DIR="${RG_WEB}"
rm -rf "${RG_WEB}"
echo

# ── 2026-09-23 QA re-audit (K-4 … K-14) ─────────────────────────────────────
echo "QA 2026-09-23 regressions"
# K-4: missing python3 — attack-surface/blind-edit gates fail closed, the rest warn.
run_case "K-4 precode_gate without python3 fails closed" precode_gate.sh 2 \
  "{\"tool_name\":\"Edit\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_UNSEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}" \
  PATH="${NOJQ_BIN}"
run_case "K-4 security_gate without python3 fails closed" security_gate.sh 2 \
  "{\"session_id\":\"k4\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"xong\"}" \
  PATH="${NOJQ_BIN}"
run_case "K-4 security_gate w/o python3 releases on re-Stop" security_gate.sh 0 \
  "{\"session_id\":\"k4\",\"stop_hook_active\":true,\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"xong\"}" \
  PATH="${NOJQ_BIN}"
for h in claim_check.sh churn_guard.sh comment_claim_guard.sh review_gate.sh test_evidence_gate.sh; do
  out="$(printf '%s' "{\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Đã chạy test, 3/3 pass.\"}" \
        | env CLAUDE_PROJECT_DIR="${SANDBOX}" PATH="${NOJQ_BIN}" bash "${HOOKS}/${h}" 2>&1)"
  rc=$?
  if [ "${rc}" -eq 0 ] && printf '%s' "${out}" | grep -q "python3"; then
    PASS=$((PASS + 1)); printf '  ok   %-46s exit=0 + warning\n' "K-4 ${h} warns without python3"
  else
    FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ K-4 ${h} warns without python3 (rc=${rc}, out=$(printf '%s' "${out}" | head -1))"
    printf '  FAIL %-46s rc=%s\n' "K-4 ${h} warns without python3" "${rc}"
  fi
done

# K-5: a Bash `echo security-check` is not a review; shell writes are edits too.
python3 - "${SANDBOX}" <<'PY'
import json, os, sys
sb = sys.argv[1]
man = os.path.join(sb, "app/src/main/AndroidManifest.xml")
def w(name, blocks):
    with open(os.path.join(sb, name), "w") as fh:
        for b in blocks:
            fh.write(json.dumps({"message": {"content": [b]}}) + "\n")
edit = {"type": "tool_use", "name": "Edit", "input": {"file_path": man, "new_string": "<uses-permission android:name=\"x\"/>"}}
echo = {"type": "tool_use", "name": "Bash", "input": {"command": "echo security-check done"}}
sed = {"type": "tool_use", "name": "Bash", "input": {"command": "sed -i '' 's/a/b/' app/src/main/AndroidManifest.xml"}}
skill = {"type": "tool_use", "name": "Skill", "input": {"skill": "security-checklist"}}
w("k5_echo.jsonl", [edit, echo])
w("k5_sed.jsonl", [sed])
w("k5_sed_reviewed.jsonl", [sed, skill])
PY
run_case "K-5 'echo security-check' is not a review" security_gate.sh 2 \
  "{\"session_id\":\"k5a\",\"transcript_path\":\"${SANDBOX}/k5_echo.jsonl\",\"last_assistant_message\":\"xong\"}"
run_case "K-5 sed -i on AndroidManifest is an edit" security_gate.sh 2 \
  "{\"session_id\":\"k5b\",\"transcript_path\":\"${SANDBOX}/k5_sed.jsonl\",\"last_assistant_message\":\"xong\"}"
run_case "K-5 shell edit + real review → pass" security_gate.sh 0 \
  "{\"session_id\":\"k5c\",\"transcript_path\":\"${SANDBOX}/k5_sed_reviewed.jsonl\",\"last_assistant_message\":\"xong\"}"
# 2026-09-25 (GeelyEx2): a read-only existence / ignore-status check was flagged as touching the
# Firebase config and keystore — `2>/dev/null` looked like a write. Reads, stats, `git
# check-ignore` / `ls-files` are not edits; anything that writes, copies or edits still is.
python3 - "${SANDBOX}" <<'PY'
import json, os, sys
sb = sys.argv[1]
def w(name, cmd):
    with open(os.path.join(sb, name), "w") as fh:
        fh.write(json.dumps({"message": {"content": [
            {"type": "tool_use", "name": "Bash", "input": {"command": cmd}}]}}) + "\n")
w("sg_ro_loop.jsonl", 'for f in app/google-services.json app/release.keystore keys/app.jks; do '
  '[ -e "$f" ] && git check-ignore -q "$f" && echo "$f ignored" || echo "$f NOT ignored"; done 2>/dev/null')
w("sg_ro_lsfiles.jsonl", "git ls-files --error-unmatch app/google-services.json 2>&1; "
  "ls -la app/src/main/AndroidManifest.xml >/dev/null && stat app/release.jks")
w("sg_ro_grep.jsonl", "grep -n 'apiKey\\|<uses-permission' app/src/main/AndroidManifest.xml 2>/dev/null | head -5")
w("sg_wr_cp.jsonl", "cp ../main/app/google-services.json app/google-services.json 2>/dev/null")
w("sg_wr_loopcp.jsonl", 'for f in app/google-services.json keys/app.jks; do cp "$f" "/tmp/wt/$f"; done')
w("sg_wr_redir.jsonl", "echo '{\"k\":1}' > app/google-services.json")
w("sg_wr_heredoc.jsonl", "cat >> app/src/main/AndroidManifest.xml <<'EOF'\n"
  "<uses-permission android:name=\"android.permission.CAMERA\"/>\nEOF")
w("sg_wr_tee.jsonl", "tee app/src/main/AndroidManifest.xml < /tmp/new.xml >/dev/null")
w("sg_wr_text.jsonl", "printf 'storePassword=hunter2\\n' >> gradle.properties 2>/dev/null")
PY
for c in "sg_ro_loop:read-only [ -e ] + git check-ignore loop quiet" "sg_ro_lsfiles:git ls-files / ls / stat quiet" \
         "sg_ro_grep:grep for trigger text is a read, quiet"; do
  run_case "${c#*:}" security_gate.sh 0 \
    "{\"session_id\":\"${c%%:*}\",\"transcript_path\":\"${SANDBOX}/${c%%:*}.jsonl\",\"last_assistant_message\":\"xong\"}"
done
for c in "sg_wr_cp:cp onto google-services.json still blocked" "sg_wr_loopcp:cp \"\$f\" in a for-loop still blocked" \
         "sg_wr_redir:> google-services.json still blocked" "sg_wr_heredoc:heredoc >> AndroidManifest still blocked" \
         "sg_wr_tee:tee AndroidManifest still blocked" "sg_wr_text:>> signing secret text still blocked"; do
  run_case "${c#*:}" security_gate.sh 2 \
    "{\"session_id\":\"${c%%:*}\",\"transcript_path\":\"${SANDBOX}/${c%%:*}.jsonl\",\"last_assistant_message\":\"xong\"}"
done
# K-6: a non-numeric attempts knob falls back to the default instead of crashing open.
run_case "K-6 SECURITY_GATE_MAX_ATTEMPTS=abc still blocks" security_gate.sh 2 \
  "{\"session_id\":\"k6\",\"transcript_path\":\"${SANDBOX}/sg_manifest.jsonl\",\"last_assistant_message\":\"xong\"}" \
  SECURITY_GATE_MAX_ATTEMPTS=abc

# K-9: a Read of a/Util.kt does not unlock an Edit of b/Util.kt.
mkdir -p "${SANDBOX}/a" "${SANDBOX}/b"
printf 'object UtilA\n' > "${SANDBOX}/a/Util.kt"
printf 'object UtilB\n' > "${SANDBOX}/b/Util.kt"
run_case "K-9 Read a/Util.kt recorded" read_ledger.sh 0 \
  "{\"tool_name\":\"Read\",\"session_id\":\"SESS-K9\",\"tool_input\":{\"file_path\":\"${SANDBOX}/a/Util.kt\"}}"
run_case "K-9 Edit b/Util.kt still blocked" precode_gate.sh 2 \
  "{\"tool_name\":\"Edit\",\"session_id\":\"SESS-K9\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${SANDBOX}/b/Util.kt\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
run_case "K-9 Edit a/Util.kt allowed" precode_gate.sh 0 \
  "{\"tool_name\":\"Edit\",\"session_id\":\"SESS-K9\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${SANDBOX}/a/Util.kt\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
# K-10: blind edits are blind in every language.
printf 'struct V {}\n' > "${SANDBOX}/V.swift"
printf 'export const x = 1\n' > "${SANDBOX}/x.ts"
run_case "K-10 blind edit of .swift blocked" precode_gate.sh 2 \
  "{\"tool_name\":\"Edit\",\"session_id\":\"SESS-K10\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${SANDBOX}/V.swift\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
run_case "K-10 blind edit of .ts blocked" precode_gate.sh 2 \
  "{\"tool_name\":\"Edit\",\"session_id\":\"SESS-K10\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${SANDBOX}/x.ts\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
# K-10/K-11: a Node project backs "tests pass" with the runner's own output.
NODE_PROJ="$(mktemp -d "${TMPDIR:-/tmp}/hooknode.XXXXXX")"
mkdir -p "${NODE_PROJ}/.claude/audit-gate"
python3 - "${NODE_PROJ}" <<'PY'
import json, os, sys
d = sys.argv[1]
src = os.path.join(d, "index.js"); open(src, "w").write("module.exports = 1\n")
def w(name, result_text, is_error=False):
    blocks = [
        {"type": "tool_use", "id": "e1", "name": "Edit", "input": {"file_path": src, "old_string": "a", "new_string": "b"}},
        {"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "npm test"}},
        {"type": "tool_result", "tool_use_id": "t1", "is_error": is_error, "content": result_text},
    ]
    with open(os.path.join(d, name), "w") as fh:
        for b in blocks:
            fh.write(json.dumps({"message": {"content": [b]}}) + "\n")
w("green.jsonl", "Tests: 12 passed, 12 total")
w("red.jsonl", "Tests: 2 failed, 10 passed, 12 total", True)
# node --test prints "ℹ fail 0" on success; a test NAMED "... error ..." is not a failure
w("node_green.jsonl", "✔ shows error message (0.3ms)\nℹ tests 3\nℹ pass 3\nℹ fail 0\nℹ cancelled 0")
# check 7 paired RED→GREEN: red run -> source edit -> green run
def cycle(name, first_red=True, second_green=True):
    blocks = [
        {"type": "tool_use", "id": "r0", "name": "Bash", "input": {"command": "npm test"}},
        {"type": "tool_result", "tool_use_id": "r0", "is_error": first_red,
         "content": "Tests: 1 failed, 11 passed, 12 total" if first_red else "Tests: 12 passed, 12 total"},
        {"type": "tool_use", "id": "e1", "name": "Edit", "input": {"file_path": src, "old_string": "a", "new_string": "b"}},
        {"type": "tool_use", "id": "g1", "name": "Bash", "input": {"command": "npm test"}},
        {"type": "tool_result", "tool_use_id": "g1", "is_error": not second_green,
         "content": "Tests: 12 passed, 12 total" if second_green else "Tests: 1 failed, 11 passed, 12 total"},
    ]
    with open(os.path.join(d, name), "w") as fh:
        for b in blocks:
            fh.write(json.dumps({"message": {"content": [b]}}) + "\n")
cycle("redgreen.jsonl")
# The DevKit's own bash suites (2026-09-25: a real RED→GREEN of tests/test_bug_capture.sh was
# not seen as a runner at all). Their verdict is the summary line: passing check names may
# carry FAIL / REJECT / ERROR in capitals.
def suite(name, runs):
    blocks = []
    for i, (cmd, out, err) in enumerate(runs):
        if cmd == "EDIT":
            blocks.append({"type": "tool_use", "id": f"se{i}", "name": "Edit",
                           "input": {"file_path": src, "old_string": "a", "new_string": "b"}})
            continue
        blocks += [{"type": "tool_use", "id": f"s{i}", "name": "Bash", "input": {"command": cmd}},
                   {"type": "tool_result", "tool_use_id": f"s{i}", "is_error": err, "content": out}]
    with open(os.path.join(d, name), "w") as fh:
        for b in blocks:
            fh.write(json.dumps({"message": {"content": [b]}}) + "\n")
BC = "cd ../devkit-wt/universal-agent-devkit && bash tests/test_bug_capture.sh 2>&1 | tail -4"
suite("devkit_redgreen.jsonl", [
    (BC, "✖ a real bug prompt under Grok → REPORTED row: not recorded\n❌ test_bug_capture: 3 failed", False),
    ("EDIT", "", False),
    (BC, "✔ failing regression command -> REJECT\n✔ ERROR banner stays hidden\n✅ test_bug_capture: all passed", False)])
suite("devkit_green_names.jsonl", [("EDIT", "", False),
    ("bash tests/test_postfix_gate.sh", "✔ full gate not exit 0 -> FAILED run blocked\n✔ REJECT on secrets\npost-fix-gate: all checks passed", False)])
suite("devkit_deviating.jsonl", [("EDIT", "", False),
    ("bash hooks/tests/hook_contract_test.sh", "  DEVIATES  proof gate case\ncontract points: 480 ok, 3 deviating", False)])
with open(os.path.join(d, "redgreen.jsonl")) as src_tr, open(os.path.join(d, "redgreen_learned.jsonl"), "w") as fh:
    fh.write(src_tr.read())
    fh.write(json.dumps({"message": {"content": [{"type": "tool_use", "id": "l1", "name": "Bash",
             "input": {"command": "agent-kit learn \"Login token race\" --cause=x --rule=y"}}]}}) + "\n")
with open(os.path.join(d, "redgreen.jsonl")) as src_tr, open(os.path.join(d, "redgreen_learned_path.jsonl"), "w") as fh:
    fh.write(src_tr.read())
    fh.write(json.dumps({"message": {"content": [{"type": "tool_use", "id": "l2", "name": "Bash",
             "input": {"command": "bash \"/opt/devkit/bin/agent-kit\" learn \"Login token race\" --cause=x"}}]}}) + "\n")
# RED-check outside the JVM: a test file written this session must run red, then green
def script_case(name, test_path, runs):
    blocks = [{"type": "tool_use", "id": "w1", "name": "Write",
               "input": {"file_path": os.path.join(d, test_path), "content": "test"}}]
    for i, (cmd, out, err) in enumerate(runs):
        if cmd == "EDIT":
            blocks.append({"type": "tool_use", "id": f"e{i}", "name": "Edit",
                           "input": {"file_path": src, "old_string": "a", "new_string": "b"}})
            continue
        blocks += [{"type": "tool_use", "id": f"r{i}", "name": "Bash", "input": {"command": cmd}},
                   {"type": "tool_result", "tool_use_id": f"r{i}", "is_error": err, "content": out}]
    with open(os.path.join(d, name), "w") as fh:
        for b in blocks:
            fh.write(json.dumps({"message": {"content": [b]}}) + "\n")
JEST_RED = ("npm test", "FAIL src/login.test.ts\nTests: 1 failed, 11 passed, 12 total", True)
JEST_GREEN = ("npm test", "PASS src/login.test.ts\nTests: 12 passed, 12 total", False)
script_case("jest_tdd.jsonl", "src/login.test.ts", [JEST_RED, ("EDIT", "", False), JEST_GREEN])
script_case("jest_greenonly.jsonl", "src/login.test.ts", [("EDIT", "", False), JEST_GREEN])
script_case("jest_otherred.jsonl", "src/login.test.ts",
            [("npm test", "FAIL src/cart.test.ts\nTests: 1 failed, 11 passed, 12 total", True), ("EDIT", "", False), JEST_GREEN])
script_case("go_tdd.jsonl", "pkg/foo_test.go",
            [("go test ./...", "--- FAIL: TestFoo (0.00s)\nFAIL\tpkg 0.01s", True), ("EDIT", "", False),
             ("go test ./...", "ok  \tpkg\t0.01s", False)])
# a `cat` of an old failing XML is not a red run
with open(os.path.join(d, "catred.jsonl"), "w") as fh:
    for b in [
        {"type": "tool_use", "id": "c0", "name": "Bash", "input": {"command": "cat build/test-results/TEST-Old.xml"}},
        {"type": "tool_result", "tool_use_id": "c0", "content": '<testsuite name="com.x.OldTest" tests="1" failures="1">'},
        {"type": "tool_use", "id": "e1", "name": "Edit", "input": {"file_path": src, "old_string": "a", "new_string": "b"}},
        {"type": "tool_use", "id": "g1", "name": "Bash", "input": {"command": "npm test"}},
        {"type": "tool_result", "tool_use_id": "g1", "content": "Tests: 12 passed, 12 total"},
    ]:
        fh.write(json.dumps({"message": {"content": [b]}}) + "\n")
cycle("greengreen.jsonl", first_red=False)
cycle("redred.jsonl", second_green=False)
PY
run_case "check 7: paired RED→GREEN backs 'đã fix'" test_evidence_gate.sh 0 \
  "{\"session_id\":\"c7rg\",\"transcript_path\":\"${NODE_PROJ}/redgreen.jsonl\",\"last_assistant_message\":\"Đã fix bug đăng nhập: test đỏ trước khi sửa, 12/12 test pass sau khi sửa.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}" LESSON_REMINDER=0
# A proven fix with no lesson recorded: the stop is held ONCE with the learn command.
run_case "lesson: proven fix, nothing recorded → reminded" test_evidence_gate.sh 2 \
  "{\"session_id\":\"lesson1\",\"transcript_path\":\"${NODE_PROJ}/redgreen.jsonl\",\"last_assistant_message\":\"Đã fix bug đăng nhập: test đỏ trước khi sửa, 12/12 test pass sau khi sửa.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
run_case "lesson: reminded once per session only" test_evidence_gate.sh 0 \
  "{\"session_id\":\"lesson1\",\"transcript_path\":\"${NODE_PROJ}/redgreen.jsonl\",\"last_assistant_message\":\"Đã fix bug đăng nhập: test đỏ trước khi sửa, 12/12 test pass sau khi sửa.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
run_case "lesson: agent-kit called by quoted path → no reminder" test_evidence_gate.sh 0 \
  "{\"session_id\":\"lesson3\",\"transcript_path\":\"${NODE_PROJ}/redgreen_learned_path.jsonl\",\"last_assistant_message\":\"Đã fix bug đăng nhập: test đỏ trước khi sửa, 12/12 test pass sau khi sửa.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
run_case "lesson: agent-kit learn in the session → no reminder" test_evidence_gate.sh 0 \
  "{\"session_id\":\"lesson2\",\"transcript_path\":\"${NODE_PROJ}/redgreen_learned.jsonl\",\"last_assistant_message\":\"Đã fix bug đăng nhập: test đỏ trước khi sửa, 12/12 test pass sau khi sửa.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
for c in "jest_tdd:0:test written, run RED, fixed, run GREEN" "jest_greenonly:2:new test only ever ran GREEN" \
         "jest_otherred:2:a RED run of another test file does not count" "go_tdd:0:go test RED then GREEN (no file names)"; do
  f="${c%%:*}"; rest="${c#*:}"; want="${rest%%:*}"; label="${rest#*:}"
  run_case "RED-check (script tests): ${label}" test_evidence_gate.sh "${want}" \
    "{\"session_id\":\"rc-${f}\",\"transcript_path\":\"${NODE_PROJ}/${f}.jsonl\",\"last_assistant_message\":\"Đã chạy test, 12/12 test pass.\"}" \
    CLAUDE_PROJECT_DIR="${NODE_PROJ}"
done
run_case "check 7: cat of an old red XML is not a RED run" test_evidence_gate.sh 2 \
  "{\"session_id\":\"c7cat\",\"transcript_path\":\"${NODE_PROJ}/catred.jsonl\",\"last_assistant_message\":\"Đã fix bug đăng nhập.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
run_case "check 7: green-only run cannot back 'đã fix'" test_evidence_gate.sh 2 \
  "{\"session_id\":\"c7gg\",\"transcript_path\":\"${NODE_PROJ}/greengreen.jsonl\",\"last_assistant_message\":\"Đã fix bug đăng nhập.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
run_case "check 7: still red after the edit cannot back 'đã fix'" test_evidence_gate.sh 2 \
  "{\"session_id\":\"c7rr\",\"transcript_path\":\"${NODE_PROJ}/redred.jsonl\",\"last_assistant_message\":\"Đã fix bug đăng nhập.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
run_case "DevKit bash suite RED then GREEN backs 'đã fix'" test_evidence_gate.sh 0 \
  "{\"session_id\":\"dk-rg\",\"transcript_path\":\"${NODE_PROJ}/devkit_redgreen.jsonl\",\"last_assistant_message\":\"Đã fix bug ghi nhận: test đỏ trước khi sửa, 12/12 test pass sau khi sửa.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}" LESSON_REMINDER=0
run_case "DevKit suite green with FAIL/REJECT/ERROR in passing names backs a pass claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"dk-gn\",\"transcript_path\":\"${NODE_PROJ}/devkit_green_names.jsonl\",\"last_assistant_message\":\"Đã chạy test, 12/12 test pass.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
run_case "DevKit contract suite with N deviating does not back a pass claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"dk-dv\",\"transcript_path\":\"${NODE_PROJ}/devkit_deviating.jsonl\",\"last_assistant_message\":\"Đã chạy test, 12/12 test pass.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
run_case "K-10 npm test green backs claim (no gradle)" test_evidence_gate.sh 0 \
  "{\"session_id\":\"k10g\",\"transcript_path\":\"${NODE_PROJ}/green.jsonl\",\"last_assistant_message\":\"Đã chạy test, 12/12 test pass.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
run_case "node --test green ('ℹ fail 0', test named error) backs claim" test_evidence_gate.sh 0 \
  "{\"session_id\":\"k10n\",\"transcript_path\":\"${NODE_PROJ}/node_green.jsonl\",\"last_assistant_message\":\"Đã chạy test, 3/3 test pass.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
run_case "K-10 npm test red does not back claim" test_evidence_gate.sh 2 \
  "{\"session_id\":\"k10r\",\"transcript_path\":\"${NODE_PROJ}/red.jsonl\",\"last_assistant_message\":\"Đã chạy test, 12/12 test pass.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
run_case "K-11 English claim with no run blocked" claim_check.sh 2 \
  "{\"session_id\":\"k11a\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"I ran the full test suite; all tests pass.\"}"
run_case "K-11 English claim backed by npm test" claim_check.sh 0 \
  "{\"session_id\":\"k11b\",\"transcript_path\":\"${NODE_PROJ}/green.jsonl\",\"last_assistant_message\":\"I ran the full test suite; all tests pass.\"}" \
  CLAUDE_PROJECT_DIR="${NODE_PROJ}"
run_case "K-11 hypothetical English is not a claim" claim_check.sh 0 \
  "{\"session_id\":\"k11c\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"Once all tests pass we can merge; you should run the tests.\"}"
rm -rf "${NODE_PROJ}"

# K-7/K-8: testsourceset_gate with a fake gradlew — a module path with a space
# is found, and one module lacking the task does not PASS the others.
TS_PROJ="$(mktemp -d "${TMPDIR:-/tmp}/hookgradle.XXXXXX")"
(
  cd "${TS_PROJ}" && git init -q . && mkdir -p "my app/src/main" lib/src/main \
  && touch "my app/build.gradle.kts" lib/build.gradle.kts \
  && git add . && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'class A\n' > "my app/src/main/A.kt" && printf 'class B\n' > lib/src/main/B.kt
  cat > gradlew <<'SH'
#!/bin/bash
for a in "$@"; do case "$a" in ":lib:"*) echo "Task 'compileDebugUnitTestKotlin' not found in project ':lib'."; exit 1;; esac; done
for a in "$@"; do case "$a" in ":my app:"*) echo "e: A.kt:1:1 Unresolved reference: nope"; exit 1;; esac; done
exit 0
SH
  chmod +x gradlew
) >/dev/null 2>&1
run_case "K-7/K-8 spaced module found, missing task ≠ PASS" testsourceset_gate.sh 2 \
  "{\"session_id\":\"k78\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"xong\"}" \
  CLAUDE_PROJECT_DIR="${TS_PROJ}"
rm -rf "${TS_PROJ}"

# Monorepo: no ./gradlew at the root, the Android build lives in android/. The
# changed module is compiled with that wrapper, module path relative to it.
TS_MONO="$(mktemp -d "${TMPDIR:-/tmp}/hookgradle.XXXXXX")"
(
  cd "${TS_MONO}" && git init -q . && mkdir -p android/app/src/main web/src \
  && touch android/app/build.gradle.kts android/settings.gradle.kts && echo x > web/src/a.ts
  printf '#!/bin/bash\necho "$PWD $*" > ../gradle_called\n[ -f ../fail ] && { echo "e: A.kt:1:1 Unresolved reference: nope"; exit 1; }\nexit 0\n' > android/gradlew
  chmod +x android/gradlew
  git add . && git -c user.email=t@t -c user.name=t commit -qm init \
  && printf 'class A\n' > android/app/src/main/A.kt && touch fail
) >/dev/null 2>&1
run_case "monorepo: android/gradlew compiles :app, break → block" testsourceset_gate.sh 2 \
  "{\"session_id\":\"mono\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"xong\"}" \
  CLAUDE_PROJECT_DIR="${TS_MONO}"
if grep -q "/android :app:compileDebugUnitTestKotlin" "${TS_MONO}/gradle_called" 2>/dev/null; then
  PASS=$((PASS + 1)); printf '  ok   %-46s\n' "monorepo: gradlew run in android/ with :app"
else
  FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ monorepo: gradlew run in android/ with :app ($(cat "${TS_MONO}/gradle_called" 2>/dev/null))"; printf '  FAIL %-46s\n' "monorepo: gradlew run in android/ with :app"
fi
rm -f "${TS_MONO}/fail"
run_case "monorepo: android/gradlew green → allow" testsourceset_gate.sh 0 \
  "{\"session_id\":\"mono2\",\"transcript_path\":\"${EMPTY_TR}\",\"last_assistant_message\":\"xong\"}" \
  CLAUDE_PROJECT_DIR="${TS_MONO}"
rm -rf "${TS_MONO}"

# K-13: hook state is gitignored in the project.
if [ "$(cat "${SANDBOX}/.claude/audit-gate/.gitignore" 2>/dev/null)" = "*" ]; then
  PASS=$((PASS + 1)); printf '  ok   %-46s\n' "K-13 audit-gate/.gitignore written"
else
  FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ K-13 audit-gate/.gitignore missing"; printf '  FAIL %-46s\n' "K-13 audit-gate/.gitignore written"
fi
# K-14: the Bash write ledger records the window (session, start/end, time, tool id) and
# never the command text — so a secret on the command line never reaches the ledger.
run_case "K-14 bash_write_ledger records" bash_write_ledger.sh 0 \
  '{"session_id":"k14","tool_name":"Bash","hook_event_name":"PreToolUse","tool_use_id":"toolu_k14","tool_input":{"command":"curl -H \"Authorization: Bearer abcdefghijklmnop\" -u me:hunter2 https://me:hunter2@x.io; export GH_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz0123"}}'
K14="${SANDBOX}/.claude/audit-gate/bash_write_ledger.tsv"
if grep -q "^k14	start	[0-9]*\.[0-9]\{3\}	toolu_k14$" "${K14}" 2>/dev/null && ! grep -qE 'abcdefghijklmnop|hunter2|ghp_|curl' "${K14}"; then
  PASS=$((PASS + 1)); printf '  ok   %-46s\n' "K-14 ledger row, no command text"
else
  FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ K-14 ledger row missing or command text leaked"; printf '  FAIL %-46s\n' "K-14 ledger row, no command text"
fi
# K-15: escape hatches that say "(logged)" leave a log line.
run_case "K-15 PRECODE_GATE=0 honoured" precode_gate.sh 0 \
  "{\"tool_name\":\"Edit\",\"transcript_path\":\"${EMPTY_TR}\",\"tool_input\":{\"file_path\":\"${KT_UNSEEN}\",\"old_string\":\"a\",\"new_string\":\"b\"}}" \
  PRECODE_GATE=0
if grep -q "PRECODE_GATE=0" "${SANDBOX}/.claude/audit-gate/precode_gate.log" 2>/dev/null; then
  PASS=$((PASS + 1)); printf '  ok   %-46s\n' "K-15 PRECODE_GATE=0 is logged"
else
  FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ K-15 PRECODE_GATE=0 not logged"; printf '  FAIL %-46s\n' "K-15 PRECODE_GATE=0 is logged"
fi
echo

# ── worktree_guard.sh — PreToolUse (Bash, Edit|Write|MultiEdit|NotebookEdit) ─
# 2026-09-25: a subagent told to work in a worktree ran commands without `cd`, its shell was in
# the main checkout, and it overwrote files there. When the session/agent declared a worktree
# (the session STARTED in a linked worktree — first `cwd` of the main transcript —, the
# subagent's harness meta `worktreePath` or its own transcript cwd, or DEVKIT_WORKTREE), a write
# aimed at the MAIN checkout of the same repo is blocked. A single-tree session is never touched,
# and a leader that started in the main checkout and merely `cd`s into a worktree is not declared.
echo "worktree_guard.sh"
WG="$(mktemp -d "${TMPDIR:-/tmp}/hookwg.XXXXXX")"; WG="$(cd "${WG}" && pwd -P)"
WG_M="${WG}/main"; WG_W="${WG}/wt"; WG_O="${WG_M}/.claude/worktrees/other"
( mkdir -p "${WG_M}/src" && cd "${WG_M}" && git init -q . && git config user.email t@t && git config user.name t \
  && printf 'a\n' > src/a.kt && printf '.claude/worktrees/\n.claude/audit-gate/\nlocal.properties\n.agents/local/memory/claude-auto/\n' > .gitignore \
  && mkdir -p .agents/local/memory/bugs .agents/local/memory/claude-auto .claude/agent-memory \
  && printf 'b\n' > .agents/local/memory/bugs/b1.md && printf 'm\n' > .agents/local/memory/claude-auto/MEMORY.md \
  && printf 't\n' > .claude/agent-memory/tracked.md && git add -A && git add -f .agents/local/memory/claude-auto/MEMORY.md \
  && git commit -qm init \
  && git worktree add -q "${WG_W}" -b wt && git worktree add -q "${WG_O}" -b other \
  && printf 'sdk.dir=/x\n' > local.properties ) >/dev/null 2>&1
printf '{"branch":"wt","main":"%s"}\n' "${WG_M}" > "$(git -C "${WG_W}" rev-parse --absolute-git-dir)/devkit-worktree.json"
WG_PROJ="${WG}/proj"; mkdir -p "${WG_PROJ}/S1/subagents"
# S1 = a session that started in the main checkout, S2 = one that started in the worktree. The first
# records of a real transcript carry no cwd (ai-title, mode, …): the first one that has it counts.
printf '{"type":"mode"}\n{"type":"user","cwd":"%s"}\n{"type":"user","cwd":"%s"}\n' "${WG_M}" "${WG_W}" > "${WG_PROJ}/S1.jsonl"
printf '{"type":"mode"}\n{"type":"user","cwd":"%s"}\n{"type":"user","cwd":"%s"}\n' "${WG_W}" "${WG_M}" > "${WG_PROJ}/S2.jsonl"
mkdir -p "${WG_M}/.claude/agent-memory" "${WG_M}/.agents/local/memory"
printf 'print(1)\n' > "${WG_M}/gen.py"
printf '{"agentType":"general-purpose","worktreePath":"%s","spawnedWithWorktree":true}\n' "${WG_W}" \
  > "${WG_PROJ}/S1/subagents/agent-iso1.meta.json"
python3 - "${WG_PROJ}/S1/subagents/agent-told1.jsonl" "${WG_W}" "${WG_M}" <<'PY'
import json, sys
out, w, m = sys.argv[1:4]
open(out, "w").write(json.dumps({"cwd": m, "isSidechain": True, "type": "user", "message": {"role": "user",
    "content": f"Fix the bug. Work in the worktree {w} only; commit there."}}) + "\n")
PY
# Sessions that started in main and ENTERED a worktree mid-session (Claude Code tools EnterWorktree /
# ExitWorktree; block shapes and compact JSON as in real transcripts). S3 entered W; S4 entered W, then
# left; S5's EnterWorktree failed (its error text names W); S6 entered W, then a second Enter failed;
# S7 only carries the tool's schema text (no call).
python3 - "${WG_PROJ}" "${WG_W}" "${WG_M}" <<'PY'
import json, os, sys
proj, w, m = sys.argv[1:4]
def use(i, name, inp): return {"type": "assistant", "cwd": m, "message": {"role": "assistant", "content": [
    {"type": "tool_use", "id": i, "name": name, "input": inp}]}}
def res(i, text, err=False): return {"type": "user", "cwd": m, "toolUseResult": text, "message": {"role": "user",
    "content": [{"type": "tool_result", "content": text, "is_error": err, "tool_use_id": i}]}}
start = [{"type": "mode"}, {"type": "user", "cwd": m}]
ok = [use("toolu_E1", "EnterWorktree", {"name": "wt"}),
      res("toolu_E1", f"Created worktree at {w}\nSwitched the session into it (branch wt).")]
bad = [use("toolu_E2", "EnterWorktree", {"name": "wt"}),
       res("toolu_E2", f"<tool_use_error>Worktree {w} already exists</tool_use_error>", True)]
out = [use("toolu_X1", "ExitWorktree", {"action": "keep"}), res("toolu_X1", f"Exited worktree {w}; back in {m}.")]
schema = [{"type": "attachment", "cwd": m, "tools": [{"name": "EnterWorktree", "description": "creates a worktree"}]}]
for name, recs in (("S3", start + ok), ("S4", start + ok + out), ("S5", start + bad), ("S6", start + ok + bad),
                   ("S7", start + schema)):
    open(os.path.join(proj, name + ".jsonl"), "w").write(
        "".join(json.dumps(r, separators=(",", ":")) + "\n" for r in recs))
PY
wg_payload() { # tool cwd agent_id input-json [session: S1 started in main (default) | S2 started in the worktree]
  python3 -c 'import json,sys; t,c,a,i,tp=sys.argv[1:6]; d={"session_id":"S1","transcript_path":tp,"cwd":c,"hook_event_name":"PreToolUse","tool_name":t,"tool_input":json.loads(i)}
if a: d["agent_id"]=a
print(json.dumps(d))' "$1" "$2" "$3" "$4" "${WG_PROJ}/${5:-S1}.jsonl"
}
wg_edit() { python3 -c 'import json,sys; print(json.dumps({"file_path":sys.argv[1],"old_string":"a","new_string":"b"}))' "$1"; }
wg_bash() { python3 -c 'import json,sys; print(json.dumps({"command":sys.argv[1]}))' "$1"; }
run_case "single tree: Edit in the main checkout allowed"       worktree_guard.sh 0 "$(wg_payload Edit "${WG_M}" "" "$(wg_edit "${WG_M}/src/a.kt")")"
run_case "single tree: relative Bash write allowed"              worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" "" "$(wg_bash "sed -i '' s/a/b/ src/a.kt")")"
run_case "started in worktree: Edit of MAIN checkout blocked"        worktree_guard.sh 2 "$(wg_payload Edit "${WG_W}" "" "$(wg_edit "${WG_M}/src/a.kt")" S2)"
run_case "started in worktree: Edit inside the worktree allowed"     worktree_guard.sh 0 "$(wg_payload Edit "${WG_W}" "" "$(wg_edit "${WG_W}/src/a.kt")" S2)"
run_case "started in worktree: Edit of a nested other worktree ok"   worktree_guard.sh 0 "$(wg_payload Edit "${WG_W}" "" "$(wg_edit "${WG_O}/src/a.kt")" S2)"
run_case "started in worktree: Edit outside the repo allowed"        worktree_guard.sh 0 "$(wg_payload Write "${WG_W}" "" "$(wg_edit "${WG}/scratch.txt")" S2)"
run_case "started in worktree: cd W && sed -i allowed"               worktree_guard.sh 0 "$(wg_payload Bash "${WG_W}" "" "$(wg_bash "cd ${WG_W} && sed -i '' s/a/b/ src/a.kt")" S2)"
run_case "started in worktree: heredoc into MAIN blocked"            worktree_guard.sh 2 "$(wg_payload Bash "${WG_W}" "" "$(wg_bash "cat > ${WG_M}/src/a.kt <<'EOF'
x
EOF")" S2)"
run_case "started in worktree: cp FROM main into worktree allowed"   worktree_guard.sh 0 "$(wg_payload Bash "${WG_W}" "" "$(wg_bash "cp ${WG_M}/local.properties ${WG_W}/local.properties")" S2)"
run_case "started in worktree: rm in MAIN blocked"                   worktree_guard.sh 2 "$(wg_payload Bash "${WG_W}" "" "$(wg_bash "rm -f ${WG_M}/src/a.kt")" S2)"
run_case "started in worktree: cat of MAIN (read) allowed"           worktree_guard.sh 0 "$(wg_payload Bash "${WG_W}" "" "$(wg_bash "cat ${WG_M}/src/a.kt 2>/dev/null | head")" S2)"
run_case "isolated agent, shell in main: relative sed blocked"   worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "sed -i '' s/a/b/ src/a.kt")")"
run_case "isolated agent, shell in main: git commit blocked"     worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "git commit -qam wip")")"
run_case "isolated agent, shell in main: git status allowed"     worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "git status --short")")"
run_case "isolated agent: cd W && write allowed"                 worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "cd ${WG_W} && echo x > src/b.kt")")"
run_case "isolated agent: Edit of MAIN blocked"                  worktree_guard.sh 2 "$(wg_payload Edit "${WG_M}" iso1 "$(wg_edit "${WG_M}/src/a.kt")")"
run_case "isolated agent: WORKTREE_GUARD=0 escape hatch"         worktree_guard.sh 0 "$(wg_payload Edit "${WG_M}" iso1 "$(wg_edit "${WG_M}/src/a.kt")")" WORKTREE_GUARD=0
run_case "DEVKIT_WORKTREE declared: Edit of MAIN blocked"        worktree_guard.sh 2 "$(wg_payload Edit "${WG_M}" "" "$(wg_edit "${WG_M}/src/a.kt")")" DEVKIT_WORKTREE="${WG_W}"
run_case "agent with no worktree of its own: main write allowed" worktree_guard.sh 0 "$(wg_payload Edit "${WG_M}" plain1 "$(wg_edit "${WG_M}/src/a.kt")")"
# Review 2026-09-25 (P2): the hook `cwd` follows `cd` inside the project, so a LEADER that started in the
# main checkout and looked into a worktree was taken as "working in the worktree" and blocked on merge-back.
run_case "leader started in main, cd'd into W: Edit of MAIN ok"  worktree_guard.sh 0 "$(wg_payload Edit "${WG_W}" "" "$(wg_edit "${WG_M}/src/a.kt")")"
run_case "leader started in main, in W: cd M && git merge ok"    worktree_guard.sh 0 "$(wg_payload Bash "${WG_W}" "" "$(wg_bash "cd ${WG_M} && git merge wt")")"
run_case "started in W, shell now in main: Edit of MAIN blocked" worktree_guard.sh 2 "$(wg_payload Edit "${WG_M}" "" "$(wg_edit "${WG_M}/src/a.kt")" S2)"
# A session that ENTERS a worktree mid-session (EnterWorktree) is declared until it calls ExitWorktree;
# a failed EnterWorktree declares nothing (and does not undo an earlier successful one).
run_case "EnterWorktree mid-session: Edit of MAIN blocked"      worktree_guard.sh 2 "$(wg_payload Edit "${WG_W}" "" "$(wg_edit "${WG_M}/src/a.kt")" S3)"
run_case "EnterWorktree mid-session: rm in MAIN blocked"        worktree_guard.sh 2 "$(wg_payload Bash "${WG_W}" "" "$(wg_bash "rm -f ${WG_M}/src/a.kt")" S3)"
run_case "EnterWorktree mid-session: Edit inside W allowed"     worktree_guard.sh 0 "$(wg_payload Edit "${WG_W}" "" "$(wg_edit "${WG_W}/src/a.kt")" S3)"
run_case "EnterWorktree then ExitWorktree: Edit of MAIN ok"     worktree_guard.sh 0 "$(wg_payload Edit "${WG_M}" "" "$(wg_edit "${WG_M}/src/a.kt")" S4)"
run_case "EnterWorktree that errored: Edit of MAIN ok"          worktree_guard.sh 0 "$(wg_payload Edit "${WG_M}" "" "$(wg_edit "${WG_M}/src/a.kt")" S5)"
run_case "Enter ok, then a failed Enter: Edit of MAIN blocked"  worktree_guard.sh 2 "$(wg_payload Edit "${WG_W}" "" "$(wg_edit "${WG_M}/src/a.kt")" S6)"
run_case "EnterWorktree only in tool schema: Edit of MAIN ok"   worktree_guard.sh 0 "$(wg_payload Edit "${WG_W}" "" "$(wg_edit "${WG_M}/src/a.kt")" S7)"
# The EnterWorktree scan is incremental (a cache of bytes scanned): an Enter appended after a scan
# is still seen, and a transcript rewritten shorter is scanned again (review 2026-09-25 perf).
cp "${WG_PROJ}/S7.jsonl" "${WG_PROJ}/S8.jsonl"
run_case "incremental scan: before the Enter, Edit of MAIN ok"   worktree_guard.sh 0 "$(wg_payload Edit "${WG_W}" "" "$(wg_edit "${WG_M}/src/a.kt")" S8)"
tail -n 2 "${WG_PROJ}/S3.jsonl" >> "${WG_PROJ}/S8.jsonl"
run_case "incremental scan: Enter appended later, MAIN blocked"  worktree_guard.sh 2 "$(wg_payload Edit "${WG_W}" "" "$(wg_edit "${WG_M}/src/a.kt")" S8)"
{ cat "${WG_PROJ}/S7.jsonl"; python3 -c 'print(("{\"type\":\"mode\"}\n") * 2000, end="")'; } > "${WG_PROJ}/S9.jsonl"
run_case "incremental scan: long, no Enter, Edit of MAIN ok"     worktree_guard.sh 0 "$(wg_payload Edit "${WG_W}" "" "$(wg_edit "${WG_M}/src/a.kt")" S9)"
cp "${WG_PROJ}/S3.jsonl" "${WG_PROJ}/S9.jsonl"
run_case "incremental scan: rewritten shorter with an Enter: blocked" worktree_guard.sh 2 "$(wg_payload Edit "${WG_W}" "" "$(wg_edit "${WG_M}/src/a.kt")" S9)"
# The scan cache is the guard's own state: a worktree session may not rewrite it (review 2: writing
# "<size> 0" there made the next Edit of MAIN pass); other main-only audit-gate state stays writable.
run_case "worktree session: write to MAIN's wg_scan cache blocked" worktree_guard.sh 2 "$(wg_payload Bash "${WG_W}" "" "$(wg_bash "printf '1 0\n' > ${WG_M}/.claude/audit-gate/wg_scan/x")" S3)"
run_case "worktree session: MAIN audit-gate log append allowed"  worktree_guard.sh 0 "$(wg_payload Bash "${WG_W}" "" "$(wg_bash "echo x >> ${WG_M}/.claude/audit-gate/notes.log")" S3)"
# … and a subagent isolated in W with its shell in M was blocked on harmless commands.
run_case "isolated agent in main: git stash list allowed"        worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "git stash list")")"
run_case "isolated agent in main: git stash show allowed"        worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "git stash show -p stash@{0}")")"
run_case "isolated agent in main: bare git stash blocked"        worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "git stash")")"
run_case "isolated agent in main: git stash -u blocked"          worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "git stash -u")")"
run_case "isolated agent in main: git stash pop blocked"         worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "git stash pop")")"
run_case "isolated agent in main: python3 -c print allowed"      worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "python3 -c 'print(1)'")")"
run_case "isolated agent in main: python3 script.py allowed"     worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "python3 gen.py")")"
run_case "isolated agent in main: formatter on a main file"      worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "python3 -m black src/a.kt")")"
run_case "isolated agent in main: bash -c write blocked"         worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "bash -c 'echo x > src/a.kt'")")"
run_case "isolated agent in main: bash -c echo allowed"          worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "bash -c 'echo hi'")")"
run_case "isolated agent in main: ./gradlew build blocked"       worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "./gradlew assembleDebug")")"
# Review 2026-09-25 (P2): a build or test runner started THROUGH an interpreter is still a build in M.
run_case "isolated agent in main: sh ./gradlew build blocked"    worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "sh ./gradlew assembleDebug")")"
run_case "isolated agent in main: bash gradlew test blocked"     worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "bash gradlew test")")"
run_case "isolated agent in main: python3 -m pytest blocked"     worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "python3 -m pytest -q")")"
run_case "isolated agent in main: python3 -m mypy . blocked"     worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "python3 -m mypy --strict")")"
run_case "isolated agent: cd W && python3 -m pytest allowed"     worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "cd ${WG_W} && python3 -m pytest -q")")"
run_case "isolated agent in main: python3 -m json.tool allowed"  worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "python3 -m json.tool /tmp/x.json")")"
run_case "isolated agent in main: scp W file to host: allowed"   worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "scp ${WG_W}/src/a.kt host:/tmp/a.kt")")"
run_case "isolated agent in main: scp to a main path blocked"    worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "scp host:/tmp/a.kt src/a.kt")")"
run_case "isolated agent in main: dd if=main of=/tmp allowed"    worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "dd if=src/a.kt of=/tmp/copy bs=4k")")"
run_case "isolated agent in main: dd of=main file blocked"       worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "dd if=/tmp/copy of=src/a.kt")")"
# Agent memory and the hooks' own logs live only in the main checkout (gitignored, absent in W).
run_case "isolated agent: Edit M/.claude/agent-memory allowed"   worktree_guard.sh 0 "$(wg_payload Write "${WG_M}" iso1 "$(wg_edit "${WG_M}/.claude/agent-memory/note.md")")"
run_case "isolated agent: Edit M/.agents/local/memory allowed"   worktree_guard.sh 0 "$(wg_payload Write "${WG_M}" iso1 "$(wg_edit "${WG_M}/.agents/local/memory/claude-auto/new.md")")"
# Review 2026-09-25 (P3): some projects TRACK files under .agents/local/memory (bugs/*.md), so W has them
# too. Main-only: agent memory / hook logs unless tracked (the fixture leaves .claude/agent-memory
# untracked and not ignored, as GeelyEx2 does), .agents/local/memory only where M ignores it, and
# claude-auto/ (Claude Code auto-memory, tracked in GeelyEx2) always.
run_case "isolated agent: TRACKED agent-memory file blocked"     worktree_guard.sh 2 "$(wg_payload Edit "${WG_M}" iso1 "$(wg_edit "${WG_M}/.claude/agent-memory/tracked.md")")"
run_case "isolated agent: tracked auto-memory MEMORY.md allowed" worktree_guard.sh 0 "$(wg_payload Edit "${WG_M}" iso1 "$(wg_edit "${WG_M}/.agents/local/memory/claude-auto/MEMORY.md")")"
run_case "isolated agent: TRACKED file in M memory dir blocked"  worktree_guard.sh 2 "$(wg_payload Edit "${WG_M}" iso1 "$(wg_edit "${WG_M}/.agents/local/memory/bugs/b1.md")")"
run_case "isolated agent: not-ignored new file in M memory dir"  worktree_guard.sh 2 "$(wg_payload Write "${WG_M}" iso1 "$(wg_edit "${WG_M}/.agents/local/memory/note.md")")"
run_case "isolated agent: rm of tracked M memory file blocked"   worktree_guard.sh 2 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "rm .agents/local/memory/bugs/b1.md")")"
run_case "isolated agent: log into M/.claude/audit-gate allowed" worktree_guard.sh 0 "$(wg_payload Bash "${WG_M}" iso1 "$(wg_bash "echo x >> .claude/audit-gate/mine.log")")"
run_case "isolated agent: agent-memory/../../ escape blocked"    worktree_guard.sh 2 "$(wg_payload Edit "${WG_M}" iso1 "$(wg_edit "${WG_M}/.claude/agent-memory/../../src/a.kt")")"
# P3: MultiEdit and NotebookEdit write files too — the hook and every registry that wires it cover them.
run_case "isolated agent: MultiEdit of MAIN blocked"             worktree_guard.sh 2 "$(wg_payload MultiEdit "${WG_M}" iso1 "$(wg_edit "${WG_M}/src/a.kt")")"
wg_reg="$(python3 - "${HOOKS}/.." <<'PY'
import json, os, sys
root = sys.argv[1]
bad = []
for rel in ("hooks/hooks.json", "templates/claude_settings.json", ".claude/settings.json"):
    try:
        groups = json.load(open(os.path.join(root, rel)))["hooks"]["PreToolUse"]
    except Exception as e:
        bad.append(f"{rel}: {e}")
        continue
    tools = set()
    for g in groups:
        if any("worktree_guard.sh" in h.get("command", "") for h in g.get("hooks", [])):
            tools |= set((g.get("matcher") or "").split("|"))
    miss = {"Bash", "Edit", "Write", "MultiEdit", "NotebookEdit"} - tools
    if miss:
        bad.append(f"{rel}: missing {sorted(miss)}")
print("; ".join(bad))
PY
)"
if [ -z "${wg_reg}" ]; then
  PASS=$((PASS + 1)); printf '  ok   %-46s\n' "registries wire it for Bash+all file-edit tools"
else
  FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ registries wire worktree_guard for Bash+all file-edit tools: ${wg_reg}"
  printf '  FAIL %-46s\n' "registries wire it for Bash+all file-edit tools"
fi
# Only the PROMPT names the worktree (no harness isolation): a hint, not a declaration → warn, never block.
out="$(printf '%s' "$(wg_payload Bash "${WG_M}" told1 "$(wg_bash "echo x > src/a.kt")")" \
      | env CLAUDE_PROJECT_DIR="${SANDBOX}" bash "${HOOKS}/worktree_guard.sh" 2>/dev/null)"; rc=$?
if [ "${rc}" -eq 0 ] && printf '%s' "${out}" | grep -q '"additionalContext"' && printf '%s' "${out}" | grep -q "${WG_W}"; then
  PASS=$((PASS + 1)); printf '  ok   %-46s exit=0 + warning\n' "prompt-named worktree: main write warns only"
else
  FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ prompt-named worktree: main write warns only (rc=${rc}, out=$(printf '%s' "${out}" | head -c 160))"
  printf '  FAIL %-46s rc=%s\n' "prompt-named worktree: main write warns only" "${rc}"
fi
rm -rf "${WG}"
echo

# ── report ──────────────────────────────────────────────────────────────────
echo "─────────────────────────────────────────────"
echo "contract points: ${PASS} ok, ${FAIL} deviating"
if [ "${FAIL}" -ne 0 ]; then
  echo "${FAILED_CASES}"
  echo
  echo "A deviation means the hook and its documented contract disagree."
  echo "Fix the hook, or fix the contract — do not relax the case (CLAUDE.md W4)."
  exit 1
fi
exit 0
