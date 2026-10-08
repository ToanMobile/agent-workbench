#!/usr/bin/env bash
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0

ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

approval_tr() {
  local tr_path="$1" file="$2" q="$3" label="$4" off="$5"
  mkdir -p "$(dirname "$tr_path")"
  python3 - "$tr_path" "$file" "$q" "$label" "$off" <<'PY'
import json, sys, time
out, file, q, label, off = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], float(sys.argv[5])
ts = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() + off))
rec = {"type": "user", "sessionId": "s-me", "timestamp": ts,
       "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "q1", "content": "answered"}]},
       "toolUseResult": {"questions": [{"question": q, "header": "Test", "options": [
           {"label": "Duyệt", "description": "giữ diff"}, {"label": "Không", "description": "đổi hướng"}]}],
           "answers": {q: label}}}
with open(out, "w") as fh:
    fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
PY
}

agent_approval() {
  local tr_path="$1" file="$2" off="$3"
  mkdir -p "$(dirname "$tr_path")"
  python3 - "$tr_path" "$file" "$off" <<'PY'
import json, sys, time
out, file, off = sys.argv[1], sys.argv[2], float(sys.argv[3])
ts = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() + off))
rec = {"type": "assistant", "sessionId": "s-me", "created_at": ts,
       "content": f"Agent tự duyệt {file}"}
with open(out, "w") as fh:
    fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
PY
}

export HOME="$TMP/home"
mkdir -p "$HOME/.claude/projects" "$HOME/.gemini/antigravity/brain"

B="$TMP/repo"; mkdir -p "$B/tests" && cd "$B" || exit 1
git init -q
mkdir -p .claude/audit-gate
echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/test_old.sh"}]}]}
JSON

# MUST commit test_old.sh so test_change_is_append_only returns False
mkdir -p src tests
echo 'fun ok()=1' > src/Core.kt
printf '#!/bin/sh\ncommitted\n' > tests/test_old.sh
git add -A && git commit -qm init

# Modify test_old.sh
printf '#!/bin/sh\ninitial\n' > tests/test_old.sh
echo 'fun ok()=2' > src/Core.kt
Q="Duyệt diff test tests/test_old.sh?"
TR="$TMP/tr/session.jsonl"
run_gate() { touch "$TR" 2>/dev/null || true; CLAUDE_PROJECT_DIR="$B" python3 "$GATE" --matrix "$B/matrix.json" --lang vi --run-tests --transcript "$TR" "$@" 2>&1; }

# Initial user approval (off = 0)
approval_tr "$TR" "tests/test_old.sh" "$Q" "Duyệt" 0
touch -t 200001010000 tests/test_old.sh src/Core.kt
touch "$TR"; out="$(run_gate)"
if printf '%s' "$out" | grep -q 'người dùng đã duyệt'; then
  ok "Approved correctly initially"
else
  fail "Initial approval failed. Out: $out"
fi

# 1. Touch with identical content (newer mtime)
sleep 1
touch tests/test_old.sh
touch "$TR"; out="$(run_gate)"
echo "CASE 1 OUT: $out"
echo "CASE 1 HASHES: $(cat .claude/audit-gate/approved_hashes.json 2>/dev/null)"
if printf '%s' "$out" | grep -q 'người dùng đã duyệt'; then
  ok "1: Still user-approved after touch (hash matches)"
else
  fail "1: Not user-approved after touch. Out: $out"
fi

# 2. Change 1 byte (different hash)
sleep 1
printf '#!/bin/sh\nfalse \n' > tests/test_old.sh
touch "$TR"; out="$(run_gate)"
echo "CASE 2 OUT: $out"
echo "CASE 2 HASHES: $(cat .claude/audit-gate/approved_hashes.json 2>/dev/null)"
if ! printf '%s' "$out" | grep -q 'người dùng đã duyệt'; then
  ok "2: Asks again after content changed"
else
  fail "2: Did not ask again after content changed. Out: $out"
fi

# 3. Restore byte (hash matches)
sleep 1
printf '#!/bin/sh\ninitial\n' > tests/test_old.sh
touch "$TR"; out="$(run_gate)"
echo "CASE 3 OUT: $out"
echo "CASE 3 HASHES: $(cat .claude/audit-gate/approved_hashes.json 2>/dev/null)"
if printf '%s' "$out" | grep -q 'người dùng đã duyệt'; then
  ok "3: Approved again after content restored"
else
  fail "3: Not approved after content restored. Out: $out"
fi

# 4. Agent auto-approve
out="$(run_gate --auto-approve-tests)"
if printf '%s' "$out" | grep -q 'agent tự duyệt'; then
  ok "4: Agent approval with --auto-approve-tests shows Tự động duyệt"
else
  fail "4: Agent approval --auto-approve-tests failed. Out: $out"
fi

# 5. Corrupted state file
bad_json_vals=('{' '[]' '"x"' 'null' '{"tests/test_old.sh": 5}')
all_5_ok=true
for bad_json in "${bad_json_vals[@]}"; do
  echo "$bad_json" > "$B/.claude/audit-gate/approved_hashes.json"
  touch "$TR"; out="$(run_gate)"
  if printf '%s' "$out" | grep -q 'Traceback' || printf '%s' "$out" | grep -q 'người dùng đã duyệt'; then
    fail "5: Corrupted state file failed for '$bad_json'. Out: $out"
    all_5_ok=false
  fi
done
if $all_5_ok; then ok "5: Corrupted state files ignored safely without traceback or false approval"; fi

# 6. Fallback to mtime if no hash file
rm -f "$B/.claude/audit-gate/approved_hashes.json"
approval_tr "$TR" "tests/test_old.sh" "$Q" "Duyệt" 0
touch -t 200001010000 tests/test_old.sh src/Core.kt
touch "$TR"; out="$(run_gate)"
if printf '%s' "$out" | grep -q 'người dùng đã duyệt'; then
  ok "6: Approved by mtime without state file"
else
  fail "6: Not approved without state file. Out: $out"
fi

# 7. Agent approval via transcript does not become user approval
rm -f "$B/.claude/audit-gate/approved_hashes.json"
touch -t 200001010000 tests/test_old.sh src/Core.kt
agent_approval "$TR" "tests/test_old.sh" 0
touch "$TR"; out="$(run_gate)"
if printf '%s' "$out" | grep -q 'người dùng đã duyệt'; then
  fail "7: Agent approval became user approval. Out: $out"
elif [ -f "$B/.claude/audit-gate/approved_hashes.json" ] && grep -q "tests/test_old.sh" "$B/.claude/audit-gate/approved_hashes.json"; then
  fail "7: Hash saved for agent approval $(cat "$B/.claude/audit-gate/approved_hashes.json")"
else
  ok "7: Agent approval never becomes user approval"
fi


# 8. UnboundLocalError when mkdir/mkstemp fails (readonly dir)
rm -f "$B/.claude/audit-gate/approved_hashes.json"
chmod 555 "$B/.claude/audit-gate"
touch -t 200001010000 tests/test_old.sh src/Core.kt
# need a user approval so it tries to write hashes
approval_tr "$TR" "tests/test_old.sh" "$Q" "Duyệt" 0
touch "$TR"; out="$(run_gate)"
chmod 755 "$B/.claude/audit-gate"
if printf '%s' "$out" | grep -q 'Traceback'; then
  fail "8: Traceback printed when directory is readonly. Out: $out"
else
  ok "8: Gracefully handled readonly audit-gate dir"
fi


# 7. F2 Scenario: Hash matches but no user approval in transcript
rm -f "$TR"
touch "$TR"
touch "$TR"; out="$(run_gate)"
if ! printf '%s' "$out" | grep -q 'người dùng đã duyệt'; then
  ok "7.0: Hash match does not exempt missing user approval"
else
  fail "7.0: Hash match exempted missing user approval! Out: $out"
fi

# 7.1 Agent approval present but no user approval
agent_approval "$TR" "tests/test_old.sh" 0
touch "$TR"; out="$(run_gate)"
if printf '%s' "$out" | grep -q 'agent tự duyệt'; then
  ok "7.1: Agent approval is used when user approval is missing, even if hash matches"
else
  fail "7.1: Agent approval not respected or showed user approval. Out: $out"
fi

[ $FAILS -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }

