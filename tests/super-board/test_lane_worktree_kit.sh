#!/usr/bin/env bash
# Test hồi quy (agent-workbench#93, 19/10): lane super-board (build / qa / review) tự tạo worktree bằng `git worktree add` trần
# (prompt chỉ nói "create your own worktree under .claude/worktrees/", runner export DEVKIT_ALLOW_BRANCH=1 nên git guard không chặn).
# Worktree như vậy thiếu .agents/devkit, link .agents/active-profile và các hook bị git ignore mà settings đăng ký -> health FAIL,
# NFH #18 (lệnh ma trận exit 127, 5 thẻ Blocked); repo Unity import lại cả Library mỗi worktree (đĩa 99 % ngày 19/10).
# Luật ở đây:
#  1. runner claude-p: prompt của cả 3 lane bảo tạo worktree bằng `agent-kit worktree add .claude/worktrees/issue-<N>-<lane> … --lane=<lane>`
#     (review: detached), cấm `git worktree add` trần; dạng prompt mà startup_orphan_workers dò vẫn giữ.
#  2. runner: đĩa dưới sàn của DevKit (WORKTREE_DISK_MIN_GIB) thì không nhận thẻ, không mở worker (lane nào cũng sẽ dừng ở exit 4).
#  3. wave workflow, super-build-dispatch.sh và SKILL của 3 lane: cùng lệnh kit; không còn chỗ nào hướng dẫn `git worktree add` trần.
# Chạy offline: runner source ở lib mode, gh/claude là stub. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-lane-wt.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl" "$TMP/repo/.agents"
git -C "$TMP/repo" init -q -b main   # worktree_disk_room runs the DevKit's worktree gc there under the warning line
ln -s "$ROOT/universal-agent-devkit" "$TMP/repo/.agents/devkit"   # worktree_disk_room đọc sàn đĩa từ chính DevKit
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/launched"
SH
chmod +x "$TMP/bin/super-board-github-read.py" "$TMP/path/claude"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH"

unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"
BOT_LOGIN=""
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
try_claim_assignee() { echo claim >> "$TMP/claims"; return 0; }
issue_is_open() { return 0; }
resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
cd "$TMP/repo" || exit 1

launch() {   # launch <lane> <issue>: dispatch one lane, wait for the stub worker, its argv in $TMP/launched
  : > "$TMP/launched"; rm -f "$INFLIGHT_DIR/$2"
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$2\",\"status\":\"Ready\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$2,\"assignees\":[]}}]}"
  ( dispatch_lane "$1" "$2" ) >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/launched" ] && break; sleep 0.3; done
}

# ── 1. prompt của runner (sàn đĩa tắt: kết quả không phụ thuộc dung lượng trống của máy chạy test)
export WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
for lane in build qa review; do
  launch "$lane" 5
  p="$(cat "$TMP/launched")"
  case "$p" in *"agent-kit worktree add .claude/worktrees/issue-5-$lane "*"--lane=$lane"*) ok "runner $lane prompt: worktree from agent-kit worktree add --lane=$lane" ;;
    *) fail "runner $lane prompt has no kit worktree command: ${p:0:300}" ;; esac
  case "$p" in *"never plain git worktree add"*) ok "  … and forbids a plain git worktree add" ;; *) fail "runner $lane prompt does not forbid a plain git worktree add" ;; esac
  case "$p" in *"--root '$PWD'"*"for super-board run"*) ok "  … and keeps the form startup_orphan_workers matches" ;;
    *) fail "runner $lane prompt lost the --root '…' … for super-board run form: $(printf '%s' "$p" | grep -o "root '[^']*'" | head -1)" ;; esac
done
case "$p" in *"--lane=review --base=origin/<PR branch>"*) ok "review lane: a detached checkout of the PR branch" ;; *) fail "review prompt is not detached at origin/<PR branch>" ;; esac

# ── 2. dưới sàn đĩa: không nhận thẻ, không giao
rm -f "$TMP/claims"
( export WORKTREE_DISK_MIN_GIB=100000 WORKTREE_DISK_WARN_GIB=0; launch build 6 )
if [ ! -s "$TMP/launched" ] && [ ! -e "$TMP/claims" ] && [ ! -e "$INFLIGHT_DIR/6" ] && grep -q "disk under the DevKit worktree floor" "$TMP/log"; then
  ok "disk under the DevKit floor: no claim, no worker, the reason logged"
else
  fail "disk floor: launched='$(head -c 120 "$TMP/launched")' claims=$([ -e "$TMP/claims" ] && echo yes || echo no) log=$(tail -1 "$TMP/log")"
fi
( export WORKTREE_DISK_MIN_GIB=0; launch build 7 )
[ -s "$TMP/launched" ] && ok "  … and the floor off (0): dispatched as before" || fail "floor 0 still skipped the dispatch"
mkdir -p "$TMP/repo/.claude/worktrees/issue-8-build"   # the lane's worktree is there already: add --lane reuses it, no new disk
( export WORKTREE_DISK_MIN_GIB=100000 WORKTREE_DISK_WARN_GIB=0; launch build 8 )
[ -s "$TMP/launched" ] && ok "  … and under the floor a lane whose worktree exists is still dispatched (reuse needs no disk)" \
  || fail "under the floor, a lane with its worktree already there was skipped"

# ── 3. wave workflow, dispatch của super-build, SKILL của 3 lane
WAVE="$ROOT/.claude/workflows/super-board-wave.js"
if command -v node >/dev/null 2>&1; then
  node -e 'const fs=require("fs");const s=fs.readFileSync(process.argv[1],"utf8").replace(/^export const meta/m,"const meta");new (Object.getPrototypeOf(async function(){}).constructor)(s)' "$WAVE" \
    && ok "wave workflow still parses" || fail "wave workflow does not parse"
fi
grep -q 'WORKTREE_STEP(lane, card.number)' "$WAVE" && grep -q 'agent-kit worktree add .claude/worktrees/issue-${n}-${lane} issue-${n}-<slug> --lane=${lane}' "$WAVE" \
  && grep -q 'agent-kit worktree add .claude/worktrees/issue-${n}-review --lane=review' "$WAVE" \
  && ! grep -q 'create your own worktree under .claude/worktrees/' "$WAVE" \
  && ok "wave lane prompt: the kit command for every lane" || fail "wave lane prompt does not route worktree creation through the kit"
DISPATCH="$ROOT/.claude/skills/super-build/scripts/super-build-dispatch.sh"
grep -q 'ls-remote --exit-code --heads origin "$WORKER_BRANCH"' "$DISPATCH" && ok "super-build-dispatch.sh refuses a loop/issue-N origin already has (always a fresh start)" \
  || fail "super-build-dispatch.sh would resume a remote leftover branch through --lane"
grep -q 'WT_PY="$REPO_DIR/.agents/devkit/scripts/git/worktree.py"' "$DISPATCH" \
  && grep -q 'python3 "$WT_PY" add "$WORKTREE_DIR" "$WORKER_BRANCH" --lane=build' "$DISPATCH" && ok "super-build-dispatch.sh creates the worktree with the kit" \
  || fail "super-build-dispatch.sh does not use the kit"
for f in .claude/skills/super-build/SKILL.md .claude/skills/super-qa/SKILL.md .claude/skills/super-review/SKILL.md; do
  grep -q -- "--lane=" "$ROOT/$f" && ok "$f names the kit command" || fail "$f has no kit worktree command"
done
# a plain `git worktree add` may still be NAMED, only as what not to do
bad=""
for f in "$WAVE" "$RUNNER" "$DISPATCH" "$ROOT/.claude/skills/super-build/SKILL.md" "$ROOT/.claude/skills/super-qa/SKILL.md" "$ROOT/.claude/skills/super-review/SKILL.md"; do
  hits=$(grep -n 'git worktree add' "$f" | grep -viE 'never|not |instead of|lacked|thiếu|trần|plain' || true)
  [ -z "$hits" ] || bad="$bad ${f#$ROOT/}:$hits"
done
[ -z "$bad" ] && ok "no lane file tells a lane to run a plain git worktree add" || fail "plain git worktree add instructions left:$bad"

[ "$FAILS" -eq 0 ] && echo "✅ test_lane_worktree_kit: all passed" || { echo "❌ test_lane_worktree_kit: $FAILS failed"; exit 1; }
