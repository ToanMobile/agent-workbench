#!/usr/bin/env bash
# Test hồi quy #1404: scratch của merge gate và merge train phải được dựng với cùng tập agent như checkout chính
# (kể cả khi `.agents/hooks.json` được track hoặc PR mới thêm nó) để `.agents/hooks/` có mặt,
# không làm REG-WB-CONFIG-01 (`agent-kit health -t .`) đỏ oan với `thiếu hoặc hỏng .agents/hooks.json`.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
TRAIN="$ROOT/.claude/bin/super-board-merge-train.sh"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-ag-hooks-1404.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP/xdg"
export SB_HEAVY_SLOT_DIR="$TMP/heavy-slots" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
export DEVKIT_LANG=vi
mkdir -p "$SB_HEAVY_SLOT_DIR"

# Gh giả offline cho cả merge-gate (--dry-run) và merge-train (preflight -> verify -> merge)
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files,comments"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"title"*) printf 'fix something\n' ;;
  *" pr view "*"body"*) printf '\n' ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr comment "*) exit 0 ;;
  *" pr merge "*)
    git -C "$FAKE_REPO" fetch -q origin main "issue-$n-x"
    tree=$(git -C "$FAKE_REPO" merge-tree --write-tree origin/main "$head") || exit 1
    c=$(git -C "$FAKE_REPO" commit-tree "$tree" -p origin/main -m "squash #$n")
    git -C "$FAKE_REPO" push -q origin "$c:refs/heads/main" && echo "$n" >> "$FAKE_DIR/merged" && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"

# Dựng fixture repo có `.agents/hooks.json` được track (như agent-workbench từ c303386e)
init_fixture() {
  local name="$1" agents="$2" track_ag="$3" ignore_gem="${4:-0}"
  local o="$TMP/$name-origin.git" r="$TMP/$name-repo"
  git init -q --bare -b main "$o"
  git init -q -b main "$r"
  git -C "$r" config user.email t@example.invalid
  git -C "$r" config user.name t
  git -C "$r" config commit.gpgsign false
  printf '/.claude/worktrees/\n' > "$r/.gitignore"
  # Như agent-workbench (.gitignore:55): cấu hình Gemini cục bộ bị ignore, không track.
  [ "$ignore_gem" -eq 0 ] || printf '.gemini/settings.json\n' >> "$r/.gitignore"
  echo 'VALUE = 1' > "$r/app.py"
  git -C "$r" add .gitignore app.py
  git -C "$r" commit -qm init

  bash "$ROOT/universal-agent-devkit/bin/install.sh" -t "$r" -a "$agents" -p backend -y >/dev/null 2>&1 || {
    fail "setup $name: install.sh failed"
    return 1
  }
  mkdir -p "$r/.agents" "$r/.claude/super-board/configs"
  cat > "$r/.agents/regression_matrix.active.json" <<'JSON'
{"version":1,"rules":[{"component":"app","watch_files":["app.py"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"app","command":"true"}]}]}
JSON
  echo '{}' > "$r/.claude/super-board/configs/x.json"

  # Track đúng các file cấu hình giống agent-workbench (AGENTS.md, .gitignore, .claude/settings.json, .agents/active-profile.json, và .agents/hooks.json nếu track_ag=1)
  git -C "$r" add -f .gitignore AGENTS.md DESIGN.md .agents/instincts.md .agents/active-profile.json .agents/regression_matrix.active.json .claude/settings.json .claude/super-board/configs/x.json
  if [ "$track_ag" -eq 1 ]; then
    git -C "$r" add -f .agents/hooks.json
  fi
  git -C "$r" commit -qm "devkit tracked"
  git -C "$r" remote add origin "$o"
  git -C "$r" push -q origin main
}

make_pr() {
  # add_ag: 1 = thêm .agents/hooks.json · codex / cursor = thêm marker cầu nối của agent đó (file do install.sh sinh, ở $TMP/gen).
  # Đối số 4: file PR sửa (mặc định app.py; hai PR cùng một train phải sửa hai file khác nhau để không xung đột).
  local name="$1" n="$2" add_ag="$3" pr_file="${4:-app.py}"
  local r="$TMP/$name-repo"
  local wt="$r/.claude/worktrees/issue-$n-build"
  git -C "$r" branch -q --no-track "issue-$n-x" origin/main
  git -C "$r" worktree add -q "$wt" "issue-$n-x"
  echo "VALUE = $n" > "$wt/$pr_file"
  if [ "$add_ag" = codex ] || [ "$add_ag" = cursor ]; then
    mkdir -p "$wt/.$add_ag"
    cp "$TMP/gen/.$add_ag/hooks.json" "$wt/.$add_ag/hooks.json"
    git -C "$wt" add -f ".$add_ag/hooks.json"
  fi
  if [ "$add_ag" = 1 ]; then
    mkdir -p "$wt/.agents"
    cat > "$wt/.agents/hooks.json" <<'JSON'
{
  "universal-agent-devkit": {
    "PreToolUse": [
      {
        "matcher": "run_command|send_command_input|shell_exec",
        "hooks": [
          {"type": "command", "command": "bash hooks/agent_bridge.sh antigravity shell block-dangerous-git.sh", "timeout": 10},
          {"type": "command", "command": "bash hooks/agent_bridge.sh antigravity shell hardware_safety_gate.sh", "timeout": 10}
        ]
      }
    ]
  }
}
JSON
    git -C "$wt" add -f .agents/hooks.json
  fi
  git -C "$wt" add "$pr_file"
  git -C "$wt" commit -qm "feat(app): update value to $n" || { fail "make_pr $name $n: commit failed"; return 1; }
  git -C "$r" push -q origin "issue-$n-x"
  local h
  h=$(git -C "$r" rev-parse "issue-$n-x")
  echo "$h" > "$TMP/pr$n.head"
  git -C "$r" diff origin/main "issue-$n-x" > "$TMP/pr$n.diff"
  python3 - "$r" "origin/main" "issue-$n-x" "$TMP/pr$n.meta" <<'PY'
import json, subprocess, sys
repo, base, head, out = sys.argv[1:5]
num = subprocess.check_output(["git", "-C", repo, "diff", "--numstat", base, head], text=True).splitlines()
files, adds, dels = [], 0, 0
for line in num:
    a, d, path = line.split("\t", 2)
    files.append({"path": path})
    adds += int(a) if a.isdigit() else 0
    dels += int(d) if d.isdigit() else 0
json.dump({"files": files, "labels": [], "body": "", "additions": adds, "deletions": dels, "changedFiles": len(files), "comments": []}, open(out, "w"))
PY
  git -C "$r" worktree remove --force "$wt"
}

# ── Ca 1: Repo track `.agents/hooks.json` trên main (như agent-workbench) — merge gate + merge train ──
init_fixture f1 "claude,gemini" 1
make_pr f1 11 0
CFG1="$TMP/cfg1.json"
cat > "$CFG1" <<JSON
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["python3 .agents/devkit/bin/agent-health.py -t . && s=\$(git status --porcelain --untracked-files=all) && [ -z \"\$s\" ]"]}
JSON
export FAKE_REPO="$TMP/f1-repo"

# 1a. Merge gate (--dry-run)
( cd "$TMP/f1-repo" && bash "$GATE" --config "$CFG1" --pr 11 --expect-head "$(cat "$TMP/pr11.head")" --dry-run ) >"$TMP/g11.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && ! grep -q "thiếu hoặc hỏng" "$TMP/g11.log"; then
  ok "1a merge-gate: scratch có .agents/hooks/, agent-health -t . XANH và git status sạch"
else
  fail "1a merge-gate (exit=$rc): $(grep -E 'FAIL|thiếu hoặc hỏng|missing scripts|UNTRACKED|verification' "$TMP/g11.log" | head -3 | tr '\n' ' ') | tail: $(tail -5 "$TMP/g11.log" | tr '\n' ' ')"
fi

# 1b. Merge train (thật qua gate giả hay gate thật — dùng gate thật!)
: > "$TMP/merged"
( cd "$TMP/f1-repo" && bash "$TRAIN" --config "$CFG1" --prs "11:$(cat "$TMP/pr11.head")" ) >"$TMP/t11.log" 2>&1
trc=$?
if [ "$trc" -eq 0 ] && grep -q "^train-result: 11 merged$" "$TMP/t11.log" && ! grep -q "thiếu hoặc hỏng" "$TMP/t11.log"; then
  ok "1b merge-train: scratch có .agents/hooks/, agent-health -t . XANH, PR #11 merged"
else
  fail "1b merge-train (exit=$trc): $(grep -E 'train-result|FAIL|thiếu hoặc hỏng|missing scripts' "$TMP/t11.log" | head -5 | tr '\n' ' ') | tail: $(tail -5 "$TMP/t11.log" | tr '\n' ' ')"
fi

# ── Ca 2: Main chỉ cài claude, nhưng PR mới thêm `.agents/hooks.json` ──
init_fixture f2 "claude" 0
make_pr f2 21 1
make_pr f2 22 1
CFG2="$TMP/cfg2.json"
cat > "$CFG2" <<JSON
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["python3 .agents/devkit/bin/agent-health.py -t ."]}
JSON
export FAKE_REPO="$TMP/f2-repo"

( cd "$TMP/f2-repo" && bash "$GATE" --config "$CFG2" --pr 21 --expect-head "$(cat "$TMP/pr21.head")" --dry-run ) >"$TMP/g21.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && ! grep -q "thiếu hoặc hỏng" "$TMP/g21.log"; then
  ok "2a merge-gate: PR mới thêm .agents/hooks.json cũng dựng đủ .agents/hooks/"
else
  fail "2a merge-gate (exit=$rc): $(tail -5 "$TMP/g21.log" | tr '\n' ' ')"
fi

( cd "$TMP/f2-repo" && bash "$TRAIN" --config "$CFG2" --prs "22:$(cat "$TMP/pr22.head")" ) >"$TMP/t22.log" 2>&1
trc=$?
if [ "$trc" -eq 0 ] && grep -q "^train-result: 22 merged$" "$TMP/t22.log"; then
  ok "2b merge-train: PR mới thêm .agents/hooks.json cũng dựng đủ .agents/hooks/"
else
  fail "2b merge-train (exit=$trc): $(tail -5 "$TMP/t22.log" | tr '\n' ' ')"
fi

# ── Ca 3: Repo chỉ dùng claude (không .agents/hooks.json, không .gemini/settings.json) không bị thêm .agents/hooks/ hay .gemini/ ──
init_fixture f3 "claude" 0
make_pr f3 31 0
CFG3="$TMP/cfg3.json"
cat > "$CFG3" <<JSON
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["[ ! -e .agents/hooks ] && [ ! -e .gemini/settings.json ] && python3 .agents/devkit/bin/agent-health.py -t ."]}
JSON
export FAKE_REPO="$TMP/f3-repo"

( cd "$TMP/f3-repo" && bash "$GATE" --config "$CFG3" --pr 31 --expect-head "$(cat "$TMP/pr31.head")" --dry-run ) >"$TMP/g31.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  ok "3 merge-gate: repo claude-only vẫn giữ đúng tập agent claude"
else
  fail "3 merge-gate claude-only (exit=$rc): $(tail -5 "$TMP/g31.log" | tr '\n' ' ')"
fi

# ── Ca 4: Optimistic retry của merge-gate khi base dời và thêm `.agents/hooks.json` trong lúc đang verify ──
init_fixture f4 "claude" 0
make_pr f4 41 0
CFG4="$TMP/cfg4.json"
MOVED4="$TMP/f4-moved"
cat > "$TMP/advance_f4.sh" <<'SH'
#!/usr/bin/env bash
set -eu
flag="$1"; repo="$2"
if [ ! -e "$flag" ]; then
  : > "$flag"
  wt="$repo/.claude/worktrees/adv-main"
  git -C "$repo" worktree add -q --detach "$wt" origin/main
  mkdir -p "$wt/.agents"
  cat > "$wt/.agents/hooks.json" <<'JSON'
{
  "universal-agent-devkit": {
    "PreToolUse": [
      {
        "matcher": "run_command|send_command_input|shell_exec",
        "hooks": [
          {"type": "command", "command": "bash hooks/agent_bridge.sh antigravity shell block-dangerous-git.sh", "timeout": 10},
          {"type": "command", "command": "bash hooks/agent_bridge.sh antigravity shell hardware_safety_gate.sh", "timeout": 10}
        ]
      }
    ]
  }
}
JSON
  git -C "$wt" add -f .agents/hooks.json
  git -C "$wt" commit -qm "chore(hooks): add antigravity hooks config"
  git -C "$wt" push -q origin HEAD:refs/heads/main
  git -C "$repo" worktree remove --force "$wt"
fi
python3 .agents/devkit/bin/agent-health.py -t .
SH
chmod +x "$TMP/advance_f4.sh"
cat > "$CFG4" <<JSON
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["bash '$TMP/advance_f4.sh' '$MOVED4' '$TMP/f4-repo'"]}
JSON
export FAKE_REPO="$TMP/f4-repo"
( cd "$TMP/f4-repo" && bash "$GATE" --config "$CFG4" --pr 41 --expect-head "$(cat "$TMP/pr41.head")" --dry-run ) >"$TMP/g41.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -e "$MOVED4" ] && ! grep -q "thiếu hoặc hỏng" "$TMP/g41.log"; then
  ok "4 merge-gate optimistic retry: base dời thêm .agents/hooks.json vẫn cài đủ .agents/hooks/"
else
  fail "4 merge-gate optimistic retry (exit=$rc): $(tail -8 "$TMP/g41.log" | tr '\n' ' ')"
fi

# ── Ca 5 (review R1, blocker): repo trong git chỉ dùng claude, .gitignore bỏ qua .gemini/settings.json, nhưng checkout chính có
# .gemini/settings.json + .agents/hooks.json CỤC BỘ (chưa track). Scratch phải lấy tập agent từ chính cây scratch (claude), không từ
# checkout chính: nếu không, .gemini/settings.json (bị ignore) ở lại, .agents/hooks.json (không ignore) bị dọn, agent-health fatal. ──
init_fixture f5 "claude" 0 1
bash "$ROOT/universal-agent-devkit/bin/install.sh" -t "$TMP/f5-repo" -a "claude,antigravity" -p backend -y --no-githooks >/dev/null 2>&1 \
  || fail "setup f5: install.sh (claude,antigravity) vào checkout chính hỏng"
if [ -e "$TMP/f5-repo/.gemini/settings.json" ] && [ -e "$TMP/f5-repo/.agents/hooks.json" ] \
   && [ -z "$(git -C "$TMP/f5-repo" ls-files -- .gemini/settings.json .agents/hooks.json)" ]; then
  ok "5 setup: checkout chính có .gemini/settings.json và .agents/hooks.json cục bộ, git không track file nào"
else
  fail "5 setup: checkout chính thiếu marker cục bộ hoặc git đang track chúng"
fi
make_pr f5 51 0
make_pr f5 52 0 other.py
CFG5="$TMP/cfg5.json"
cat > "$CFG5" <<JSON
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["[ ! -e .gemini/settings.json ] && [ ! -e .agents/hooks ] && python3 .agents/devkit/bin/agent-health.py -t ."]}
JSON
export FAKE_REPO="$TMP/f5-repo"
( cd "$TMP/f5-repo" && bash "$GATE" --config "$CFG5" --pr 51 --expect-head "$(cat "$TMP/pr51.head")" --dry-run ) >"$TMP/g51.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && ! grep -q "thiếu hoặc hỏng" "$TMP/g51.log"; then
  ok "5a merge-gate: marker cục bộ của checkout chính không lọt vào scratch, agent-health -t . không fatal"
else
  fail "5a merge-gate R1 (exit=$rc): $(grep -E 'thiếu hoặc hỏng|missing' "$TMP/g51.log" | head -2 | tr '\n' ' ') | tail: $(tail -4 "$TMP/g51.log" | tr '\n' ' ')"
fi
( cd "$TMP/f5-repo" && bash "$TRAIN" --config "$CFG5" --prs "52:$(cat "$TMP/pr52.head")" ) >"$TMP/t52.log" 2>&1
trc=$?
if [ "$trc" -eq 0 ] && grep -q "^train-result: 52 merged$" "$TMP/t52.log" && ! grep -q "thiếu hoặc hỏng" "$TMP/t52.log"; then
  ok "5b merge-train: marker cục bộ của checkout chính không lọt vào scratch, PR #52 merged"
else
  fail "5b merge-train R1 (exit=$trc): $(grep -E 'train-result|thiếu hoặc hỏng' "$TMP/t52.log" | head -3 | tr '\n' ' ') | tail: $(tail -4 "$TMP/t52.log" | tr '\n' ' ')"
fi

# ── Ca 6: marker cầu nối .codex/hooks.json (merge gate) và .cursor/hooks.json (merge train) do PR thêm cũng dựng đủ .agents/hooks/ ──
mkdir -p "$TMP/gen"
git init -q -b main "$TMP/gen"
bash "$ROOT/universal-agent-devkit/bin/install.sh" -t "$TMP/gen" -a "claude,codex,cursor" -p backend -y --no-githooks >/dev/null 2>&1
if [ -f "$TMP/gen/.codex/hooks.json" ] && [ -f "$TMP/gen/.cursor/hooks.json" ]; then
  init_fixture f6 "claude" 0
  make_pr f6 61 codex
  make_pr f6 62 cursor other.py
  CFG6="$TMP/cfg6.json"
  cat > "$CFG6" <<JSON
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["[ -e .agents/hooks/agent_bridge.sh ] && python3 .agents/devkit/bin/agent-health.py -t ."]}
JSON
  export FAKE_REPO="$TMP/f6-repo"
  ( cd "$TMP/f6-repo" && bash "$GATE" --config "$CFG6" --pr 61 --expect-head "$(cat "$TMP/pr61.head")" --dry-run ) >"$TMP/g61.log" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "6a merge-gate: PR thêm .codex/hooks.json có .agents/hooks/agent_bridge.sh trong scratch"
  else
    fail "6a merge-gate codex (exit=$rc): $(tail -5 "$TMP/g61.log" | tr '\n' ' ')"
  fi
  ( cd "$TMP/f6-repo" && bash "$TRAIN" --config "$CFG6" --prs "62:$(cat "$TMP/pr62.head")" ) >"$TMP/t62.log" 2>&1
  trc=$?
  if [ "$trc" -eq 0 ] && grep -q "^train-result: 62 merged$" "$TMP/t62.log"; then
    ok "6b merge-train: PR thêm .cursor/hooks.json có .agents/hooks/agent_bridge.sh trong scratch"
  else
    fail "6b merge-train cursor (exit=$trc): $(grep -E 'train-result' "$TMP/t62.log" | tr '\n' ' ') | tail: $(tail -5 "$TMP/t62.log" | tr '\n' ' ')"
  fi
else
  fail "6 setup: install.sh không sinh .codex/hooks.json / .cursor/hooks.json mẫu"
fi

# ── Ca 7 (bisect của merge train): PR #71 thêm .agents/hooks.json và ĐỎ; PR #72 không có marker nào. Sau khi chia đôi, scratch của
# nửa [#72] không được còn .agents/hooks/ hay .gemini/settings.json (bị ignore, `git clean -qfd` không dọn) của nửa trước. ──
init_fixture f7 "claude" 0 1
make_pr f7 71 1
make_pr f7 72 0 other.py
CFG7="$TMP/cfg7.json"
cat > "$CFG7" <<JSON
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["if [ -e .agents/hooks.json ]; then [ -e .agents/hooks/agent_bridge.sh ] || echo no-bridge; exit 1; fi; [ ! -e .agents/hooks ] && [ ! -e .gemini/settings.json ] && python3 .agents/devkit/bin/agent-health.py -t ."]}
JSON
export FAKE_REPO="$TMP/f7-repo"
: > "$TMP/merged"
( cd "$TMP/f7-repo" && bash "$TRAIN" --config "$CFG7" --prs "71:$(cat "$TMP/pr71.head"),72:$(cat "$TMP/pr72.head")" ) >"$TMP/t7.log" 2>&1
trc=$?
if grep -q "^train-result: 72 merged$" "$TMP/t7.log" && grep -q "^train-result: 71 red$" "$TMP/t7.log" && ! grep -qx "no-bridge" "$TMP/t7.log"; then
  ok "7 merge-train bisect: nửa không có marker cầu nối không còn .agents/hooks/ sót lại, PR #72 merged, PR #71 đỏ"
else
  fail "7 merge-train bisect (exit=$trc): $(grep -E '^train-result|no-bridge' "$TMP/t7.log" | tr '\n' ' ') | tail: $(tail -4 "$TMP/t7.log" | tr '\n' ' ')"
fi

# ── Ca 8 (optimistic retry, exit 9): base dời thêm .agents/hooks.json trong lúc verify nhưng không còn install.sh để cài bổ sung
# (.agents/devkit của checkout chính bị thay giữa chừng bằng bản thiếu bin/install.sh; agent-health.py vẫn chạy được): thiếu
# .agents/hooks/agent_bridge.sh là lỗi môi trường ⇒ exit 9 (verification-readiness), không verify lại rồi đỏ exit 11 oan cho PR. ──
init_fixture f8 "claude" 0
make_pr f8 81 0
CFG8="$TMP/cfg8.json"
MOVED8="$TMP/f8-moved"
cat > "$TMP/advance_f8.sh" <<'SH'
#!/usr/bin/env bash
set -eu
flag="$1"; repo="$2"
if [ ! -e "$flag" ]; then
  : > "$flag"
  wt="$repo/.claude/worktrees/adv-main"
  git -C "$repo" worktree add -q --detach "$wt" origin/main
  mkdir -p "$wt/.agents"
  printf '{"universal-agent-devkit":{"PreToolUse":[{"matcher":"run_command","hooks":[{"type":"command","command":"bash hooks/agent_bridge.sh antigravity shell block-dangerous-git.sh","timeout":10},{"type":"command","command":"bash hooks/agent_bridge.sh antigravity shell hardware_safety_gate.sh","timeout":10}]}]}}\n' > "$wt/.agents/hooks.json"
  git -C "$wt" add -f .agents/hooks.json
  git -C "$wt" commit -qm "chore(hooks): add antigravity hooks config"
  git -C "$wt" push -q origin HEAD:refs/heads/main
  git -C "$repo" worktree remove --force "$wt"
  rc=0; python3 .agents/devkit/bin/agent-health.py -t . || rc=$?
  # Sau lượt verify đầu: .agents/devkit của checkout chính (link tới kit) thành thư mục link từng mục, bỏ bin/install.sh.
  real=$(cd "$repo/.agents/devkit" && pwd -P)
  [ -L "$repo/.agents/devkit" ] || { echo "f8: .agents/devkit is not a link"; exit 1; }
  rm "$repo/.agents/devkit"
  mkdir -p "$repo/.agents/devkit/bin"
  for e in "$real"/*; do [ "${e##*/}" = bin ] || ln -s "$e" "$repo/.agents/devkit/${e##*/}"; done
  for e in "$real"/bin/*; do [ "${e##*/}" = install.sh ] || ln -s "$e" "$repo/.agents/devkit/bin/${e##*/}"; done
  exit "$rc"
fi
python3 .agents/devkit/bin/agent-health.py -t .
SH
chmod +x "$TMP/advance_f8.sh"
cat > "$CFG8" <<JSON
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["bash '$TMP/advance_f8.sh' '$MOVED8' '$TMP/f8-repo'"]}
JSON
export FAKE_REPO="$TMP/f8-repo"
( cd "$TMP/f8-repo" && bash "$GATE" --config "$CFG8" --pr 81 --expect-head "$(cat "$TMP/pr81.head")" --dry-run ) >"$TMP/g81.log" 2>&1
rc=$?
if [ "$rc" -eq 9 ] && [ -e "$MOVED8" ] && grep -q "^verification-readiness: .*agent_bridge.sh" "$TMP/g81.log"; then
  ok "8 merge-gate optimistic retry: thiếu .agents/hooks/agent_bridge.sh sau khi base dời ⇒ exit 9 (verification-readiness)"
else
  fail "8 merge-gate optimistic retry exit 9 (exit=$rc): $(tail -5 "$TMP/g81.log" | tr '\n' ' ')"
fi

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_scratch_antigravity_hooks_1404: PASS"; exit 0; } || { echo "test_merge_scratch_antigravity_hooks_1404: FAIL ($FAILS)"; exit 1; }
