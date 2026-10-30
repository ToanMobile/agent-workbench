#!/usr/bin/env bash
# #628 AC2: lời duyệt của người dùng gắn với sha256 của file, không với mtime. Worktree mới checkout ra có `.claude/audit-gate/`
# (git-ignored) trống và test mới hơn lời duyệt; lời duyệt đã ghi ở checkout chính (approved_hashes.json) phải còn hiệu lực
# khi nội dung file đúng bằng bản đã duyệt, và không hiệu lực khi nội dung đã đổi.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

export HOME="$TMP/home"
mkdir -p "$HOME/.claude/projects"
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR CLAUDE_CODE_SESSION_ID

B="$TMP/repo"; mkdir -p "$B/tests" "$B/src" && cd "$B" || exit 1
git init -q
git config user.email t@t && git config user.name t
mkdir -p .claude/audit-gate
echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/test_old.sh"}]}]}
JSON
echo 'fun ok()=1' > src/Core.kt
printf '#!/bin/sh\ncommitted\n' > tests/test_old.sh
printf '.claude/audit-gate/\n' > .gitignore
git add -A && git commit -qm init

printf '#!/bin/sh\ninitial\n' > tests/test_old.sh
Q="Duyệt diff test tests/test_old.sh?"
TR="$TMP/tr/session.jsonl"; mkdir -p "$TMP/tr"
python3 - "$TR" "$Q" <<'PY'
import json, sys, time
out, q = sys.argv[1:3]
ts = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time()))
rec = {"type": "user", "sessionId": "s-me", "timestamp": ts,
       "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "q1", "content": "answered"}]},
       "toolUseResult": {"questions": [{"question": q, "header": "Test", "options": [
           {"label": "Duyệt", "description": "giữ diff"}, {"label": "Không", "description": "đổi hướng"}]},],
           "answers": {q: "Duyệt"}}}
open(out, "w").write(json.dumps(rec, ensure_ascii=False) + "\n")
PY
run_gate() { # <project dir>
  touch "$TR"; CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --matrix "$1/matrix.json" --lang vi --run-tests --transcript "$TR" 2>&1
}

# Bước 0: người dùng duyệt ở checkout chính, gate ghi approved_hashes.json (mtime test cũ hơn lời duyệt)
touch -t 200001010000 tests/test_old.sh src/Core.kt
out="$(run_gate "$B")"
if printf '%s' "$out" | grep -q 'người dùng đã duyệt' && grep -q 'tests/test_old.sh' .claude/audit-gate/approved_hashes.json; then
  ok "0: duyệt ở checkout chính, hash được ghi"
else
  fail "0: không dựng được lời duyệt ở checkout chính. Out: $out"
fi

# Worktree mới: file test chép sang có mtime MỚI HƠN lời duyệt, .claude/audit-gate/ không có gì (git-ignored)
W="$TMP/wt"
git worktree add -q --detach "$W" HEAD
cp "$B/tests/test_old.sh" "$W/tests/test_old.sh"; cp "$B/src/Core.kt" "$W/src/Core.kt"
cp "$B/matrix.json" "$W/matrix.json"; mkdir -p "$W/.claude"; cp "$B/.claude/config.json" "$W/.claude/config.json"
sleep 1; touch "$W/tests/test_old.sh"
out="$(run_gate "$W")"
if printf '%s' "$out" | grep -q 'người dùng đã duyệt'; then
  ok "1: worktree mới, cùng sha256, mtime mới hơn lời duyệt: vẫn được duyệt"
else
  fail "1: lời duyệt mất khi checkout worktree mới. Out: $out"
fi

# Đối chứng: nội dung đổi 1 byte thì phải hỏi lại, kể cả khi hash của checkout chính còn đó
printf '#!/bin/sh\ninitial \n' > "$W/tests/test_old.sh"
out="$(run_gate "$W")"
if printf '%s' "$out" | grep -q 'người dùng đã duyệt'; then
  fail "2: nội dung đã đổi mà vẫn được duyệt. Out: $out"
else
  ok "2: nội dung đổi thì không được duyệt (fail closed)"
fi

[ $FAILS -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
