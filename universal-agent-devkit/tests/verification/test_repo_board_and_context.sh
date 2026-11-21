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
  shim_off_err="$TMP/shim_off.err"
  shim_off_out="$(cd "$OR" && env GH_SHIM=0 PATH="$OR/.agents/devkit/shims:$TMP/bin:$PATH" gh project item-list 1 --owner ToanMobile 2>"$shim_off_err")"; rc_3e=$?
  if [ "$rc_3e" = 0 ] && [ ! -s "$shim_off_err" ] && printf '%s' "$shim_off_out" | grep -q '"totalCount"'; then
    ok "3e shims/gh thoát nhanh sang gh thật khi GH_SHIM=0"
  else
    fail "3e shims/gh không bỏ qua khi GH_SHIM=0: rc=$rc_3e err=$(cat "$shim_off_err") out=$shim_off_out"
  fi
  if [ ! -d "$OR/.agents/devkit/scripts/governance/__pycache__" ]; then
    ok "3f shims/gh (python3 -I) không tạo __pycache__ trong cây kit"
  else
    fail "3f shims/gh tạo __pycache__ trong cây kit: $(ls -A "$OR/.agents/devkit/scripts/governance/__pycache__")"
  fi
  # 3g. (#1402, audit PR #1394) gh thật thoát mã khác 0 khi sai board: shim vẫn cảnh báo và trả đúng mã đó, giữ stdout/stderr của gh
  mkdir -p "$TMP/bin_rc4"
  printf '#!/bin/sh\necho gh-rc4-out\necho gh-rc4-err >&2\nexit 4\n' > "$TMP/bin_rc4/gh"; chmod +x "$TMP/bin_rc4/gh"
  shim_rc4_err="$TMP/shim_rc4.err"
  shim_rc4_out="$(cd "$OR" && env PATH="$OR/.agents/devkit/shims:$TMP/bin_rc4:$PATH" gh project item-list 1 --owner ToanMobile 2>"$shim_rc4_err")"; rc_3g=$?
  if [ "$rc_3g" = 4 ] && [ "$shim_rc4_out" = "gh-rc4-out" ] && grep -q "#2" "$shim_rc4_err" && grep -q "gh-rc4-err" "$shim_rc4_err"; then
    ok "3g shims/gh trả đúng mã thoát 4 của gh thật khi sai board (vẫn cảnh báo, giữ stdout/stderr)"
  else
    fail "3g shims/gh không giữ mã thoát của gh thật: rc=$rc_3g (muốn 4) err=$(cat "$shim_rc4_err") out=$shim_rc4_out"
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
if [ -s "$EF_SHIM" ] && [ "$rc_4c" = 0 ] && grep -q "#2" "$shim4c_err" && [ -z "$adb_cmd" ] && ! grep -q "devkit-adb-shim" "$EF_SHIM"; then
  ok "4c session_context.sh giữ shims/gh khi ADB_SHIM=0 mà không bật shim adb"
else
  fail "4c ADB_SHIM=0 làm tắt shims/gh hoặc vẫn bật adb: env=$(cat "$EF_SHIM") err=$(cat "$shim4c_err") adb=$adb_cmd"
fi

# 4d. R6: đặt GH_SHIM=0 khi ADB_SHIM=1 phải giữ shim adb (chặn đúng denylist của repo) nhưng KHÔNG đưa shims/gh lên PATH
EF_GH0="$TMP/env_gh0"
: > "$EF_GH0"
printf 'FORBIDDEN_SERIAL\n' > "$OR/.adb-denylist"
cat > "$TMP/bin/adb" <<'SH'
#!/usr/bin/env bash
echo "REAL_ADB_EXECUTED $*"
exit 0
SH
chmod +x "$TMP/bin/adb"
(cd "$OR" && env TMPDIR="$TMP" CLAUDE_ENV_FILE="$EF_GH0" CLAUDE_PROJECT_DIR="$OR" WORKTREE_GC=0 ADB_SHIM=1 GH_SHIM=0 bash "$SESSION_HOOK" </dev/null >/dev/null 2>&1)
shim4d_err="$TMP/shim4d.err"
shim4d_out="$(cd "$OR/sub/dir" && env PATH="$TMP/bin:$PATH" bash -c ". '$EF_GH0'; gh project item-list 1 --owner ToanMobile" 2>"$shim4d_err")"; rc_4d=$?
gh_cmd4d="$(env PATH="$TMP/bin:/usr/bin:/bin" bash -c ". '$EF_GH0'; command -v gh || true")"
adb_cmd4d="$(env PATH="$TMP/bin:/usr/bin:/bin" bash -c ". '$EF_GH0'; command -v adb || true")"
adb_deny_err="$TMP/adb4d_deny.err"
adb_deny_out="$(cd "$OR/sub/dir" && env -u ADB_DENY_SERIALS -u ADB_ALLOW_SERIALS -u ANDROID_SERIAL PATH="$TMP/bin:/usr/bin:/bin" bash -c ". '$EF_GH0'; adb -s FORBIDDEN_SERIAL shell echo hi" 2>"$adb_deny_err")"; rc_adb_deny=$?
adb_ok_out="$(cd "$OR/sub/dir" && env -u ADB_DENY_SERIALS -u ADB_ALLOW_SERIALS -u ANDROID_SERIAL PATH="$TMP/bin:/usr/bin:/bin" bash -c ". '$EF_GH0'; adb -s emulator-5554 shell echo hi" 2>/dev/null)"; rc_adb_ok=$?
if [ -s "$EF_GH0" ] && [ "$rc_4d" = 0 ] && [ ! -s "$shim4d_err" ] && [ "$gh_cmd4d" = "$TMP/bin/gh" ] && [ -n "$adb_cmd4d" ] && printf '%s' "$shim4d_out" | grep -q '"totalCount"' \
   && [ "$rc_adb_deny" = 2 ] && ! printf '%s' "$adb_deny_out" | grep -q 'REAL_ADB_EXECUTED' && grep -q 'denylist' "$adb_deny_err" \
   && [ "$rc_adb_ok" = 0 ] && printf '%s' "$adb_ok_out" | grep -q 'REAL_ADB_EXECUTED'; then
  ok "4d session_context.sh giữ shim adb khi GH_SHIM=0 và ADB_SHIM=1 (chặn đúng denylist repo) mà không đưa shims/gh lên PATH"
else
  fail "4d GH_SHIM=0 với ADB_SHIM=1 sai: rc=$rc_4d rc_deny=$rc_adb_deny deny_out=$adb_deny_out deny_err=$(cat "$adb_deny_err") rc_ok=$rc_adb_ok ok_out=$adb_ok_out gh=$gh_cmd4d adb=$adb_cmd4d"
fi

# 4e. R7: session_context.sh (python3 -I) và enrich_context.py (--hook -> board_hint) không tạo __pycache__ trong cây kit
KIT_R7="$TMP/kit_r7"
mkdir -p "$KIT_R7/hooks" "$KIT_R7/scripts/governance" "$KIT_R7/scripts/context"
cp "$SESSION_HOOK" "$KIT_R7/hooks/session_context.sh"
cp "$DEVKIT_DIR/scripts/governance/repo_board.py" "$KIT_R7/scripts/governance/repo_board.py"
cp "$DEVKIT_DIR/scripts/context/enrich_context.py" "$KIT_R7/scripts/context/enrich_context.py"
cat > "$KIT_R7/hooks/regression_gate.sh" <<'SH'
#!/usr/bin/env bash
echo '{"state":"none"}'
SH
chmod +x "$KIT_R7/hooks/session_context.sh" "$KIT_R7/hooks/regression_gate.sh"
sess_r7="$(printf '{"session_id":"s_r7","hook_event_name":"SessionStart"}' | env -u PYTHONPYCACHEPREFIX CLAUDE_PROJECT_DIR="$OR" WORKTREE_GC=0 SESSION_FETCH=0 bash "$KIT_R7/hooks/session_context.sh" 2>/dev/null)"
hook_r7="$(printf '{"prompt":"check board","session_id":"s_r7_hook"}' | env -u PYTHONPYCACHEPREFIX CLAUDE_PROJECT_DIR="$OR" DEVKIT_ROOT="$KIT_R7" python3 "$KIT_R7/scripts/context/enrich_context.py" --hook 2>/dev/null)"
if printf '%s' "$sess_r7" | grep -q "ToanMobile/projects/2 (OfficeReader)" \
   && printf '%s' "$hook_r7" | grep -q "ToanMobile/projects/2 (OfficeReader)" \
   && [ ! -d "$KIT_R7/scripts/governance/__pycache__" ]; then
  ok "4e session_context.sh và enrich_context.py (--hook) không tạo __pycache__ khi nạp repo_board"
else
  fail "4e enrich_context/session_context sai hoặc tạo __pycache__: hook_r7=$hook_r7 pycache=$(ls -A "$KIT_R7/scripts/governance/__pycache__" 2>/dev/null || echo none)"
fi

# 4f. Bảo mật _shim_env_add (CWE-377/CWE-426): không rơi về /tmp dùng chung khi TMPDIR trống, tạo 0700 dưới HOME/.cache
HOME_4F="$TMP/home_4f"
EF_4F="$TMP/env_4f"
mkdir -p "$HOME_4F"
: > "$EF_4F"
(cd "$OR" && env -u TMPDIR -u XDG_CACHE_HOME HOME="$HOME_4F" CLAUDE_ENV_FILE="$EF_4F" CLAUDE_PROJECT_DIR="$OR" WORKTREE_GC=0 SESSION_FETCH=0 ADB_SHIM=0 GH_SHIM=1 bash "$SESSION_HOOK" </dev/null >/dev/null 2>&1)
iso_4f="$(find "$HOME_4F/.cache" -maxdepth 1 -type d -name 'devkit-gh-shim-*' -user "$(id -u)" ! -perm -020 ! -perm -002 -print 2>/dev/null | head -n 1)"
if [ -n "$iso_4f" ] && grep -qF "$iso_4f" "$EF_4F"; then
  ok "4f _shim_env_add dùng HOME/.cache với quyền 0700 khi TMPDIR trống"
else
  fail "4f _shim_env_add không tạo 0700 dưới HOME/.cache khi TMPDIR trống: env=$(cat "$EF_4F") iso=$iso_4f"
fi

# 4g. Bảo mật _shim_env_add: từ chối thư mục 0777, symlink và env rỗng (không rơi về /tmp)
sum_or="$(printf '%s' "$OR/.agents/devkit/shims" | cksum | awk '{print $1}')"
uid_now="$(id -u)"
BAD_777="$TMP/bad_777"; mkdir -p "$BAD_777"
mkdir -m 777 "$BAD_777/devkit-gh-shim-${uid_now}-${sum_or}"
EF_4G1="$TMP/env_4g1"; : > "$EF_4G1"
(cd "$OR" && env TMPDIR="$BAD_777" CLAUDE_ENV_FILE="$EF_4G1" CLAUDE_PROJECT_DIR="$OR" WORKTREE_GC=0 SESSION_FETCH=0 ADB_SHIM=0 GH_SHIM=1 bash "$SESSION_HOOK" </dev/null >/dev/null 2>&1)

BAD_LNK="$TMP/bad_lnk"; mkdir -p "$BAD_LNK/target"
ln -s "$BAD_LNK/target" "$BAD_LNK/devkit-gh-shim-${uid_now}-${sum_or}"
EF_4G2="$TMP/env_4g2"; : > "$EF_4G2"
(cd "$OR" && env TMPDIR="$BAD_LNK" CLAUDE_ENV_FILE="$EF_4G2" CLAUDE_PROJECT_DIR="$OR" WORKTREE_GC=0 SESSION_FETCH=0 ADB_SHIM=0 GH_SHIM=1 bash "$SESSION_HOOK" </dev/null >/dev/null 2>&1)

EF_4G3="$TMP/env_4g3"; : > "$EF_4G3"
(cd "$OR" && env -u TMPDIR -u XDG_CACHE_HOME -u HOME CLAUDE_ENV_FILE="$EF_4G3" CLAUDE_PROJECT_DIR="$OR" WORKTREE_GC=0 SESSION_FETCH=0 ADB_SHIM=0 GH_SHIM=1 bash "$SESSION_HOOK" </dev/null >/dev/null 2>&1)

if [ ! -s "$EF_4G1" ] && [ ! -s "$EF_4G2" ] && [ ! -e "$BAD_LNK/target/gh" ] && [ ! -s "$EF_4G3" ]; then
  ok "4g _shim_env_add từ chối thư mục 0777, symlink và không fallback /tmp khi thiếu env"
else
  fail "4g _shim_env_add chấp nhận đường dẫn không an toàn: 777=$(cat "$EF_4G1") lnk=$(cat "$EF_4G2") noenv=$(cat "$EF_4G3")"
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
else
  fail "5 thiếu $SB_STATUS"
fi

# 4h. Symlinked .agents/devkit dir với GH_SHIM=0 ADB_SHIM=1 vẫn giữ root repo cho .adb-denylist
SYMLINK_APP="$TMP/SymlinkApp"
mkdir -p "$SYMLINK_APP/.agents" "$SYMLINK_APP/sub"
(cd "$SYMLINK_APP" && git init -q -b main && git config user.email t@t && git config user.name t)
ln -s "$DEVKIT_DIR" "$SYMLINK_APP/.agents/devkit"
printf 'FORBIDDEN_SYMLINK\n' > "$SYMLINK_APP/.adb-denylist"
EF_4H="$TMP/env_4h"; : > "$EF_4H"
(cd "$SYMLINK_APP" && env TMPDIR="$TMP" CLAUDE_ENV_FILE="$EF_4H" CLAUDE_PROJECT_DIR="$SYMLINK_APP" WORKTREE_GC=0 SESSION_FETCH=0 ADB_SHIM=1 GH_SHIM=0 bash "$SESSION_HOOK" </dev/null >/dev/null 2>&1)
err_4h="$TMP/adb4h.err"
out_4h="$(cd "$SYMLINK_APP/sub" && env -u ADB_DENY_SERIALS -u ADB_ALLOW_SERIALS -u ANDROID_SERIAL PATH="$TMP/bin:/usr/bin:/bin" bash -c ". '$EF_4H'; adb -s FORBIDDEN_SYMLINK shell echo hi" 2>"$err_4h")"; rc_4h=$?
if [ -s "$EF_4H" ] && [ "$rc_4h" = 2 ] && ! printf '%s' "$out_4h" | grep -q 'REAL_ADB_EXECUTED' && grep -q 'denylist' "$err_4h"; then
  ok "4h shims/adb qua symlink .agents/devkit khi GH_SHIM=0 vẫn chặn đúng denylist repo"
else
  fail "4h symlink .agents/devkit không chặn denylist: rc=$rc_4h out=$out_4h err=$(cat "$err_4h")"
fi

# 5b. Multi-config repo: origin matching và .claude/super-board/active ở repo_board.py & super-board-status.py
MULTI_REPO="$TMP/MultiCfgRepo"
mkdir -p "$MULTI_REPO/.claude/super-board/configs" "$MULTI_REPO/sub"
(cd "$MULTI_REPO" && git init -q -b main && git config user.email t@t && git config user.name t && git remote add origin https://github.com/ToanMobile/BetaApp.git)
cat > "$MULTI_REPO/.claude/super-board/configs/alpha.json" <<'JSON'
{"version": 1, "project": {"owner": "ToanMobile", "title": "Alpha", "number": 11}, "repo": {"remote": "https://github.com/ToanMobile/AlphaApp"}, "base_branch": "main"}
JSON
cat > "$MULTI_REPO/.claude/super-board/configs/beta.json" <<'JSON'
{"version": 1, "project": {"owner": "ToanMobile", "title": "Beta", "number": 22}, "repo": {"remote": "https://github.com/ToanMobile/BetaApp"}, "base_branch": "main"}
JSON
multi_rb="$(cd "$MULTI_REPO/sub" && bash "$KIT_CLI" board --json 2>&1)"; rc_mrb=$?
cat > "$TMP/fake_status_bin/gh" <<'PY'
#!/usr/bin/env python3
import json, sys
a = sys.argv[1:]
if a[:2] == ["api", "graphql"]:
    assert "number=22" in a, f"wrong number in graphql: {a}"
    print(json.dumps({"data": {"repositoryOwner": {"projectV2": {"items": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": [
        {"id": "I22", "content": {"number": 99, "title": "Multi Card", "repository": {"nameWithOwner": "ToanMobile/BetaApp"}, "labels": {"nodes": []}}, "fieldValues": {"nodes": [{"field": {"name": "Status"}, "name": "Ready"}]}}
    ]}}}}}))
    sys.exit(0)
sys.exit(0)
PY
chmod +x "$TMP/fake_status_bin/gh"
multi_st="$(cd "$MULTI_REPO/sub" && PATH="$TMP/fake_status_bin:$PATH" python3 "$SB_STATUS" 2>&1)"; rc_mst=$?
printf 'alpha\n' > "$MULTI_REPO/.claude/super-board/active"
multi_act="$(cd "$MULTI_REPO/sub" && bash "$KIT_CLI" board --json 2>&1)"; rc_mact=$?
if [ "$rc_mrb" = 0 ] && python3 -c 'import json,sys; assert json.loads(sys.argv[1])["number"]==22' "$multi_rb" 2>/dev/null \
   && [ "$rc_mst" = 0 ] && printf '%s' "$multi_st" | grep -q "Beta (#22)" && printf '%s' "$multi_st" | grep -q "#99" \
   && [ "$rc_mact" = 0 ] && python3 -c 'import json,sys; assert json.loads(sys.argv[1])["number"]==11' "$multi_act" 2>/dev/null; then
  ok "5b multi-config origin matching (#22) và file active (#11) hoạt động đúng ở repo_board.py & super-board-status.py"
else
  fail "5b multi-config sai: mrb=$rc_mrb($multi_rb) mst=$rc_mst($multi_st) mact=$rc_mact($multi_act)"
fi

if [ "$FAILS" -ne 0 ]; then
  echo "test_repo_board_and_context: $FAILS FAILED"
  exit 1
fi
echo "test_repo_board_and_context: all checks passed"
