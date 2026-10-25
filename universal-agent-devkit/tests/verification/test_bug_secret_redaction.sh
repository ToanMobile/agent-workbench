#!/usr/bin/env bash
# bin/regression_checklist.py register_bug + scripts/context/enrich_context.py capture_bug, secrets in a bug title
# (2026-10-13, workbench): a user pasted an API key in a message the prompt hook read as a bug report; BUG_CAPTURE made a REPORTED
# row whose TITLE held the whole message and whose ID held the start of the key, in .agents/regression_status.json and
# .agents/CHECKLIST.md — files the gate rewrites and every session commits. Removed by hand before any commit.
# The bug title (and cause / evidence) is now redacted where every path meets, register_bug, and the prompt hook redacts its
# title before it dedupes: a key, token or password never reaches the checklist, the id or the context line.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
export WORKTREE_TRUNK_MODE=0   # checklist kiểu cũ: ở trunk mode (mặc định) lệnh bugs/req ở main ghi sổ chờ ngoài git (tests/worktree_git/test_trunk_main_pending_writers.sh kiểm đường đó)
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
PROMPT_HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset PROMPT_CONTEXT BUG_CAPTURE GROK_HOOK_EVENT GROK_HOOK_NAME GROK_SESSION_ID GROK_WORKSPACE_ROOT DEVKIT_AGENT

P="$TMP/p"; mkdir -p "$P/src" "$P/tests" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
echo "def total(): return 1" > src/cart.py
cat > .agents/regression_matrix.active.json <<'JSON'
{"rules":[{"component":"Cart","watch_files":["src/*.py"],
 "mandatory_regression_tests":[{"id":"REG-CART","name":"cart","command":"python3 -m pytest tests"}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"

# fake secrets, built at run time so this file holds none
K1="sk-""ant-usr-1tUY3SSfake""Zz9_0jfZVjDSqqOfPnqQsbbSHXpJBgsk9IsAt"
K2="ghp_""FAKEfake1234567890abcdefABCDEF1234"
K3="AKIA""FAKEFAKE12345678"
leaks() { grep -rli -e "${K1:11:12}" -e "${K2:4:16}" -e "${K3:4:12}" "$P/.agents" 2>/dev/null; }   # -i: the bug id is a lower-case slug

# 1. agent-kit bugs add with keys in the title and the evidence
out="$(bash "$KIT" bugs add "app crash khi đăng nhập, key $K1 token=$K2 aws $K3" --evidence "Bearer $K2" --module auth 2>&1)"
[ -z "$(leaks)" ] && ok "bugs add: no secret in the checklist files" || fail "bugs add leaked into: $(leaks | tr '\n' ' ')"
printf '%s' "$out" | grep -qi -e "${K1:11:12}" -e "${K2:4:16}" -e "${K3:4:12}" && fail "bugs add printed a secret" || ok "bugs add: no secret printed"
printf '%s' "$out" | grep -q 'BUG-' && ok "bugs add still records the bug (id printed)" || fail "no bug id: $out"

# 2. the prompt hook (BUG_CAPTURE) on a pasted message holding a key
out="$(python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "session_id": "s1", "transcript_path": sys.argv[2]}))' \
  "config key $K1 cho tôi, đăng nhập bị lỗi crash" "$TMP/tr.jsonl" | bash "$PROMPT_HOOK" 2>&1)"
printf '%s' "$out" | grep -q 'Bug đã ghi vào checklist' && ok "prompt hook: the bug was captured (the check below tests something)" \
  || fail "prompt hook captured nothing: $out"
[ -z "$(leaks)" ] && ok "prompt hook: no secret in the checklist files" || fail "prompt hook leaked into: $(leaks | tr '\n' ' ')"
printf '%s' "$out" | grep -qi -e "${K1:11:12}" && fail "prompt hook context line holds the key" || ok "prompt hook: no key in its context line"

# 2b. a long first line: the title is cut at 120 characters; a key across the cut must not survive as a stub the pattern misses
pad="ứng dụng bị crash khi đăng nhập lần đầu sau khi cập nhật bản mới, màn hình trắng rồi văng ra ngoài"   # 98 chars: the cut at 119 lands inside the key
out="$(python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "session_id": "s2", "transcript_path": sys.argv[2]}))' \
  "$pad key $K1 thử lại" "$TMP/tr2.jsonl" | bash "$PROMPT_HOOK" 2>&1)"
printf '%s' "$out" | grep -q 'Bug đã ghi vào checklist' && ok "long prompt: the bug was captured" || fail "long prompt captured nothing: $out"
! grep -rqi -e "${K1:11:5}" "$P/.agents" && ! printf '%s' "$out" | grep -qi -e "${K1:11:5}" && ok "long prompt: no piece of the key in the checklist or the context line" \
  || fail "a cut key survived: $(grep -rhoi -e "sk-[^ ]*" "$P/.agents" | head -2 | tr '\n' ' ')"

# 3. the other ways in: a REQ (title + criterion) and a bug table import
bash "$KIT" req add "đăng nhập bằng key $K1" --criterion "không log $K2" --module auth >/dev/null 2>&1
grep -q '"REQ-' "$P/.agents/regression_status.json" && ok "req add recorded the REQ (the leak check covers it)" || fail "req add recorded nothing"
printf 'bug_id\ttitle\tseverity\tfixed?\tmodule\ttest_id_or_NONE\tevidence\n' > "$TMP/bugs.tsv"
printf 'B9\tcrash with key %s\tP1\tyes\tauth\tNONE\tlog shows Bearer %s\n' "$K1" "$K2" >> "$TMP/bugs.tsv"
bash "$KIT" bugs import "$TMP/bugs.tsv" >/dev/null 2>&1
grep -q '"BUG-B9"' "$P/.agents/regression_status.json" && ok "the import still records the bug" || fail "import did not record BUG-B9"
[ -z "$(leaks)" ] && ok "req add and bugs import: no secret in the checklist files" || fail "req/import leaked into: $(leaks | tr '\n' ' ')"

# 4. ordinary titles are left alone
out="$(bash "$KIT" bugs add "Tổng giỏ hàng sai khi có mã giảm giá" --module cart 2>&1)"
grep -q 'Tổng giỏ hàng sai khi có mã giảm giá' "$P/.agents/regression_status.json" && ok "a title without a secret is kept as written" \
  || fail "ordinary title changed"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
