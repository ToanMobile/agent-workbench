#!/usr/bin/env bash
# Test hồi quy (#1392): đánh dấu board từng repo trong AGENTS.md, `agent-kit board`,
# `create_task.py`, `super-board-status.py`, `prompt_context.sh` và cảnh báo `gh project item-list` sai board.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
unset CLAUDE_PROJECT_DIR
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT_DIR="$(cd "$DEVKIT_DIR/.." && pwd)"
TMP="$(mktemp -d)"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

KIT_CLI="$DEVKIT_DIR/bin/agent-kit"
SYNC_PY="$DEVKIT_DIR/scripts/governance/context_sync.py"
CT_PY="$DEVKIT_DIR/scripts/governance/create_task.py"
BDG_HOOK="$DEVKIT_DIR/hooks/block-dangerous-git.sh"
SESSION_HOOK="$DEVKIT_DIR/hooks/session_context.sh"
PROMPT_HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"
GH_SHIM="$DEVKIT_DIR/shims/gh"
SB_STATUS="$ROOT_DIR/.claude/bin/super-board-status.py"

make_repo() {
  local name="$1" slug="$2" owner="$3" num="$4" title="$5" remote_repo="$6" is_kit="${7:-0}"
  local p="$TMP/$name"
  mkdir -p "$p/.claude/super-board/configs" "$p/.agents" "$p/sub/dir"
  if [ "$is_kit" = "1" ]; then
    mkdir -p "$p/universal-agent-devkit"
  fi
  (cd "$p" && git init -q -b main && git config user.email t@t && git config user.name t)
  if [ -n "$remote_repo" ]; then
    git -C "$p" remote add origin "https://github.com/$remote_repo.git"
  fi
  cat > "$p/.claude/super-board/configs/$slug.json" <<JSON
{
  "version": 1,
  "project": {
    "owner": "$owner",
    "title": "$title",
    "number": $num
  },
  "repo": {
    "path": ".",
    "remote": "https://github.com/${remote_repo:-ToanMobile/$name}"
  },
  "base_branch": "main"
}
JSON
  {
    echo "# $name"
    echo "<!-- universal-agent-devkit:start -->"
    cat "$DEVKIT_DIR/templates/agents_injection_block.md"
    echo "<!-- universal-agent-devkit:end -->"
  } > "$p/AGENTS.md"
  git -C "$p" add -A && git -C "$p" commit -qm init
  printf '%s' "$p"
}

# 1. `agent-kit board` trên cả 5 repo app và repo kit
APPS=(
  "OfficeReader|officereader|ToanMobile|2|OfficeReader|ToanMobile/OfficeReader|0"
  "Goods|goods-triple-shelf-match-3d|ToanMobile|3|Goods Triple Shelf Match 3D|ToanMobile/Goods-Triple-Shelf-Match-3D|0"
  "GeelyEx2|geelyex2|ToanMobile|4|GeelyEx2|ToanMobile/GeelyEx2|0"
  "Idle|idle-plaza-3d|ToanMobile|5|Idle Plaza 3D|ToanMobile/Idle-Plaza-3D|0"
  "Humans|humans-vs-ufos|ToanMobile|6|Humans vs. UFOs|ToanMobile/Humans-vs.-UFOs|0"
  "agent-workbench|agent-workbench|ToanMobile|1|Agent Workbench|ToanMobile/agent-workbench|1"
)

for row in "${APPS[@]}"; do
  IFS='|' read -r name slug owner num title remote is_kit <<<"$row"
  P="$(make_repo "$name" "$slug" "$owner" "$num" "$title" "$remote" "$is_kit")"
  out="$(cd "$P/sub/dir" && bash "$KIT_CLI" board --json 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && python3 - "$out" "$owner" "$num" "$title" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["owner"] == sys.argv[2], d
assert str(d["number"]) == sys.argv[3], d
assert d["title"] == sys.argv[4], d
assert f"/projects/{sys.argv[3]}" in d["url"], d
PY
  then
    ok "1a agent-kit board ($name #$num) từ subdir"
  else
    fail "1a agent-kit board ($name #$num): rc=$rc out=$out"
  fi

  python3 "$SYNC_PY" "$P" --quiet; rc=$?
  want_line="Board của repo này: $owner/projects/$num ($title)"
  if [ "$rc" = 0 ] && grep -qF "$want_line" "$P/AGENTS.md"; then
    if [ "$is_kit" = "1" ]; then
      grep -q "chỉ chứa việc của kit" "$P/AGENTS.md" && ok "1b AGENTS.md ($name) ghi rõ #1 chỉ chứa việc của kit" \
        || fail "1b AGENTS.md ($name) thiếu ghi chú #1 chỉ chứa việc của kit"
    else
      ! grep -q "chỉ chứa việc của kit" "$P/AGENTS.md" && ok "1b AGENTS.md ($name) ghi đúng #$num" \
        || fail "1b AGENTS.md ($name) lại có ghi chú của kit"
    fi
  else
    fail "1b context_sync ($name): rc=$rc, không thấy '$want_line'"
  fi
done

# 2. create_task.py trong repo app KHÔNG có git remote (hoặc local path): đọc từ config, KHÔNG rơi về #1
mkdir -p "$TMP/bin"
export FAKE_LOG="$TMP/calls.jsonl"
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"gh": a}, ensure_ascii=False) + "\n")
if a[:2] == ["issue", "create"]:
    print("https://github.com/ToanMobile/OfficeReader/issues/77"); sys.exit(0)
if a[:2] == ["project", "item-add"]:
    print(json.dumps({"id": "PVTI_77"})); sys.exit(0)
if a[:2] == ["project", "view"]:
    print(json.dumps({"id": "PVT_CUSTOM"})); sys.exit(0)
if a[:2] == ["project", "field-list"]:
    print(json.dumps({"fields": [{"id": "F1", "name": "Status", "options": [{"id": "O1", "name": "Backlog"}]}]})); sys.exit(0)
if a[:2] == ["project", "item-edit"]:
    sys.exit(0)
if a[:2] == ["project", "item-list"]:
    print(json.dumps({"items": [], "totalCount": 0})); sys.exit(0)
if a[:2] == ["label", "create"]:
    sys.exit(0)
sys.exit(0)
PY
chmod +x "$TMP/bin/gh"

NO_REMOTE="$(make_repo "OfficeNoRemote" "officereader" "ToanMobile" "2" "OfficeReader" "" "0")"
: > "$FAKE_LOG"
out="$(cd "$NO_REMOTE/sub/dir" && PATH="$TMP/bin:$PATH" python3 "$CT_PY" --title "🐛 [bug] pdf: crash" --problem "p" --ac "- [ ] ok" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q '"project", "item-add", "2"' "$FAKE_LOG" && ! grep -q '"project", "item-add", "1"' "$FAKE_LOG"; then
  ok "2a create_task.py từ subdir repo không remote vẫn đẩy vào board #2"
else
  fail "2a create_task.py: rc=$rc log=$(cat "$FAKE_LOG") out=$out"
fi

# 2b. Skill createTask, create-task.md và create-task/SKILL.md không ghi cứng #1; docstring create_task.py đủ 6 repo
if ! grep -q "projects/1/views/2" "$DEVKIT_DIR/commands/createTask.md" "$DEVKIT_DIR/skills/create-task/SKILL.md" \
   && ! grep -q "Project #1" "$DEVKIT_DIR/commands/create-task.md" \
   && grep -q "Humans-vs.-UFOs" <(head -n 15 "$CT_PY"); then
  ok "2b createTask.md, create-task.md, create-task/SKILL.md và docstring create_task.py đủ 6 repo, không ghi cứng #1"
else
  fail "2b còn ghi cứng #1 hoặc thiếu #6 trong commands/skills/docstring create_task.py"
fi

# 2c. R2: đặt tường minh CLAUDE_PROJECT_DIR=<agent-workbench> không được đè CWD ở agent-kit board và create_task.py
AW="$TMP/agent-workbench"
OR="$TMP/OfficeReader"
out_cwd="$(cd "$OR/sub/dir" && CLAUDE_PROJECT_DIR="$AW" bash "$KIT_CLI" board --json 2>&1)"; rc=$?
if [ "$rc" = 0 ] && python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["number"]==2, d' "$out_cwd" 2>/dev/null; then
  ok "2c agent-kit board ưu tiên repo ở CWD (#2) thay vì CLAUDE_PROJECT_DIR (#1)"
else
  fail "2c agent-kit board bị CLAUDE_PROJECT_DIR đè: rc=$rc out=$out_cwd"
fi

out_fb="$(cd "$TMP" && CLAUDE_PROJECT_DIR="$AW" bash "$KIT_CLI" board --json 2>&1)"; rc=$?
if [ "$rc" = 0 ] && python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["number"]==1, d' "$out_fb" 2>/dev/null; then
  ok "2d agent-kit board ở thư mục ngoài repo rơi về CLAUDE_PROJECT_DIR (#1)"
else
  fail "2d agent-kit board không rơi về CLAUDE_PROJECT_DIR khi CWD ngoài repo: rc=$rc out=$out_fb"
fi

: > "$FAKE_LOG"
out_ct="$(cd "$NO_REMOTE/sub/dir" && CLAUDE_PROJECT_DIR="$AW" PATH="$TMP/bin:$PATH" python3 "$CT_PY" --title "🐛 [bug] pdf: crash2" --problem "p" --ac "- [ ] ok" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q '"project", "item-add", "2"' "$FAKE_LOG" && ! grep -q '"project", "item-add", "1"' "$FAKE_LOG"; then
  ok "2e create_task.py với CLAUDE_PROJECT_DIR=<agent-workbench> từ OfficeNoRemote vẫn đẩy vào #2"
else
  fail "2e create_task.py bị CLAUDE_PROJECT_DIR kéo về #1: rc=$rc log=$(cat "$FAKE_LOG") out=$out_ct"
fi

if ! grep -qE '^[[:space:]]*import glob\b' "$DEVKIT_DIR/scripts/governance/repo_board.py"; then
  ok "2f repo_board.py không còn import glob thừa"
else
  fail "2f repo_board.py vẫn còn import glob thừa"
fi

# 3. Hook block-dangerous-git.sh & shim gh cảnh báo 1 dòng khi `gh project item-list` sai board
OR="$TMP/OfficeReader"
err_wrong="$TMP/bdg_wrong.err"
out_wrong="$(printf '{"tool_name":"Bash","tool_input":{"command":"gh project item-list 1 --owner ToanMobile"},"cwd":"%s"}' "$OR" \
  | CLAUDE_PROJECT_DIR="$OR" bash "$BDG_HOOK" 2>"$err_wrong")"; rc=$?
if [ "$rc" = 0 ] && { grep -q "#2" "$err_wrong" || printf '%s' "$out_wrong" | grep -q "#2"; }; then
  ok "3a block-dangerous-git.sh cảnh báo khi chạy gh project item-list 1 trong OfficeReader (#2)"
else
  fail "3a hook không cảnh báo sai board: rc=$rc err=$(cat "$err_wrong") out=$out_wrong"
fi

err_ok="$TMP/bdg_ok.err"
out_ok="$(printf '{"tool_name":"Bash","tool_input":{"command":"gh project item-list 2 --owner ToanMobile"},"cwd":"%s"}' "$OR" \
  | CLAUDE_PROJECT_DIR="$OR" bash "$BDG_HOOK" 2>"$err_ok")"; rc=$?
if [ "$rc" = 0 ] && [ ! -s "$err_ok" ] && [ -z "$out_ok" ]; then
  ok "3b block-dangerous-git.sh im lặng khi chạy đúng board #2"
else
  fail "3b hook cảnh báo nhầm khi đúng board: rc=$rc err=$(cat "$err_ok") out=$out_ok"
fi

if [ -x "$GH_SHIM" ]; then
  mkdir -p "$OR/.agents/devkit/shims" "$OR/.agents/devkit/scripts/governance"
  cp "$GH_SHIM" "$OR/.agents/devkit/shims/gh" && chmod +x "$OR/.agents/devkit/shims/gh"
  cp "$DEVKIT_DIR/scripts/governance/repo_board.py" "$OR/.agents/devkit/scripts/governance/repo_board.py"
  shim_err="$TMP/shim.err"
  shim_out="$(cd "$OR" && env PATH="$OR/.agents/devkit/shims:$TMP/bin:$PATH" gh project item-list 1 --owner ToanMobile 2>"$shim_err")"; rc=$?
  if [ "$rc" = 0 ] && grep -q "#2" "$shim_err" && printf '%s' "$shim_out" | grep -q '"totalCount"'; then
    ok "3c shims/gh cảnh báo sai board trên stderr, giữ nguyên stdout & exit 0"
  else
    fail "3c shims/gh sai: rc=$rc err=$(cat "$shim_err") out=$shim_out"
  fi
  shim_ok_err="$TMP/shim_ok.err"
  (cd "$OR" && env PATH="$OR/.agents/devkit/shims:$TMP/bin:$PATH" gh project item-list 2 --owner ToanMobile >/dev/null 2>"$shim_ok_err")
  if [ ! -s "$shim_ok_err" ]; then
    ok "3d shims/gh im lặng khi chạy đúng board #2"
  else
    fail "3d shims/gh cảnh báo nhầm khi đúng board: $(cat "$shim_ok_err")"
  fi
else
  fail "3c thiếu shims/gh"
fi

# 4. Hỏi "check board" trong repo app -> prompt_context.sh & session_context.sh nêu đúng board #2
sess_out="$(printf '{"session_id":"s1","hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$OR" WORKTREE_GC=0 bash "$SESSION_HOOK" 2>/dev/null)"
if printf '%s' "$sess_out" | grep -q "ToanMobile/projects/2 (OfficeReader)"; then
  ok "4a session_context.sh nêu board #2 cho OfficeReader"
else
  fail "4a session_context.sh thiếu board #2: $sess_out"
fi

prompt_out="$(printf '{"prompt":"check board","session_id":"p1"}' | CLAUDE_PROJECT_DIR="$OR" bash "$PROMPT_HOOK" 2>/dev/null)"
if printf '%s' "$prompt_out" | grep -q "ToanMobile/projects/2 (OfficeReader)" && printf '%s' "$prompt_out" | grep -q "super-board-status.py"; then
  ok "4b prompt_context.sh khi hỏi 'check board' chỉ đúng board #2 và lệnh kiểm tra"
else
  fail "4b prompt_context.sh thiếu board #2: $prompt_out"
fi

# 4c. R4: đặt ADB_SHIM=0 không được tắt shims/gh trong session_context.sh, đồng thời không bật shim adb
EF_SHIM="$TMP/env_shim"
: > "$EF_SHIM"
cp "$DEVKIT_DIR/shims/adb" "$OR/.agents/devkit/shims/adb" && chmod +x "$OR/.agents/devkit/shims/adb"
(cd "$OR" && env TMPDIR="$TMP" CLAUDE_ENV_FILE="$EF_SHIM" CLAUDE_PROJECT_DIR="$OR" WORKTREE_GC=0 ADB_SHIM=0 bash "$SESSION_HOOK" </dev/null >/dev/null 2>&1)
shim4c_err="$TMP/shim4c.err"
shim4c_out="$(cd "$OR/sub/dir" && env PATH="$TMP/bin:$PATH" bash -c ". '$EF_SHIM'; gh project item-list 1 --owner ToanMobile" 2>"$shim4c_err")"; rc_4c=$?
adb_cmd="$(env PATH="$TMP/bin:/usr/bin:/bin" bash -c ". '$EF_SHIM'; command -v adb || true")"
if [ -s "$EF_SHIM" ] && [ "$rc_4c" = 0 ] && grep -q "#2" "$shim4c_err" && [ "$adb_cmd" != "$OR/.agents/devkit/shims/adb" ]; then
  ok "4c session_context.sh giữ shims/gh khi ADB_SHIM=0 mà không bật shim adb"
else
  fail "4c ADB_SHIM=0 làm tắt shims/gh hoặc vẫn bật adb: env=$(cat "$EF_SHIM") err=$(cat "$shim4c_err") adb=$adb_cmd"
fi

# 5. super-board-status.py chạy được từ thư mục con của repo app
if [ -f "$SB_STATUS" ]; then
  mkdir -p "$TMP/fake_status_bin"
  cat > "$TMP/fake_status_bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
if a[:2] == ["api", "graphql"]:
    # verify -F number=2
    assert "number=2" in a, f"wrong number in graphql: {a}"
    print(json.dumps({"data": {"repositoryOwner": {"projectV2": {"items": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": [
        {"id": "I1", "content": {"number": 10, "title": "Test Card", "repository": {"nameWithOwner": "ToanMobile/OfficeReader"}, "labels": {"nodes": []}}, "fieldValues": {"nodes": [{"field": {"name": "Status"}, "name": "Ready"}]}}
    ]}}}}}))
    sys.exit(0)
sys.exit(0)
PY
  chmod +x "$TMP/fake_status_bin/gh"
  st_out="$(cd "$OR/sub/dir" && PATH="$TMP/fake_status_bin:$PATH" python3 "$SB_STATUS" 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && printf '%s' "$st_out" | grep -q "OfficeReader (#2)" && printf '%s' "$st_out" | grep -q "#10"; then
    ok "5 super-board-status.py chạy từ subdir đọc đúng OfficeReader (#2)"
  else
    fail "5 super-board-status.py từ subdir: rc=$rc out=$st_out"
  fi
fi

if [ "$FAILS" -ne 0 ]; then
  echo "test_repo_board_and_context: $FAILS FAILED"
  exit 1
fi
echo "test_repo_board_and_context: all checks passed"
