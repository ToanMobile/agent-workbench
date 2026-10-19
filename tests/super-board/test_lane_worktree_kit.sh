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
if [ ! -s "$TMP/launched" ] && [ ! -e "$TMP/claims" ] && [ ! -e "$INFLIGHT_DIR/6" ] && grep -q "disk under the DevKit worktree floor" "$TMP/log" \
    && grep -q "worktree_disk_room: .*GiB" "$TMP/log"; then
  ok "disk under the DevKit floor: no claim, no worker, the reason logged"
else
  fail "disk floor: launched='$(head -c 120 "$TMP/launched")' claims=$([ -e "$TMP/claims" ] && echo yes || echo no) log=$(tail -1 "$TMP/log")"
fi
( export WORKTREE_DISK_MIN_GIB=0; launch build 7 )
[ -s "$TMP/launched" ] && ok "  … and the floor off (0): dispatched as before" || fail "floor 0 still skipped the dispatch"
git -C "$TMP/repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "$TMP/repo" worktree add -q --detach .claude/worktrees/issue-8-build   # the lane's worktree is there: add --lane reuses it
( export WORKTREE_DISK_MIN_GIB=100000 WORKTREE_DISK_WARN_GIB=0; launch build 8 )
[ -s "$TMP/launched" ] && ok "  … and under the floor a lane whose worktree exists is still dispatched (reuse needs no disk)" \
  || fail "under the floor, a lane with its worktree already there was skipped"
mkdir -p "$TMP/repo/.claude/worktrees/issue-11-build"   # a .git pointing at an admin dir git pruned: no worktree any more
echo "gitdir: $TMP/repo/.git/worktrees/gone" > "$TMP/repo/.claude/worktrees/issue-11-build/.git"
( export WORKTREE_DISK_MIN_GIB=100000 WORKTREE_DISK_WARN_GIB=0; launch build 11 )
[ ! -s "$TMP/launched" ] && ok "  … but a stale .git git no longer knows does not count either" || fail "a stale .git let a dispatch through under the floor"
mkdir -p "$TMP/repo/.claude/worktrees/issue-9-build"   # an empty leftover folder is no worktree: add would still need the disk
( export WORKTREE_DISK_MIN_GIB=100000 WORKTREE_DISK_WARN_GIB=0; launch build 9 )
[ ! -s "$TMP/launched" ] && ok "  … but an empty leftover folder does not count as the lane's worktree" || fail "an empty folder let a dispatch through under the floor"
# the check itself failing (no DevKit here): dispatched as before, and said in the log, never silently
mv "$TMP/repo/.agents/devkit" "$TMP/repo/.agents/devkit.off"; : > "$TMP/log"
( export WORKTREE_DISK_MIN_GIB=100000 WORKTREE_DISK_WARN_GIB=0; launch build 10 )
[ -s "$TMP/launched" ] && grep -q "DevKit disk check failed" "$TMP/log" && ok "a failing disk check is logged, the dispatch goes on" \
  || fail "failing disk check: launched=$([ -s "$TMP/launched" ] && echo yes || echo no) log=$(tail -1 "$TMP/log")"
mv "$TMP/repo/.agents/devkit.off" "$TMP/repo/.agents/devkit"

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
# super-build-dispatch.sh, run for real up to its early refusals (no gh, no claude reached)
D="$TMP/disp"; G() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }
mkdir -p "$D/main" && G "$D/main" init -q -b main && echo x > "$D/main/a" && G "$D/main" add a && G "$D/main" commit -qm init
(cd "$D/main" && BASE_BRANCH=main bash "$DISPATCH" 5 > "$TMP/disp.out" 2>&1); rc=$?
[ "$rc" = 64 ] && grep -q "DevKit missing" "$TMP/disp.out" && ok "dispatch without the DevKit: refused before any network call" \
  || fail "dispatch without the DevKit: rc $rc: $(tail -1 "$TMP/disp.out")"
mkdir -p "$D/broken/scripts/git" "$D/main/.agents" && echo 'raise ImportError("half-installed")' > "$D/broken/scripts/git/worktree.py"
ln -s "$D/broken" "$D/main/.agents/devkit"
git init -q --bare "$D/origin.git" && G "$D/main" remote add origin "$D/origin.git"
(cd "$D/main" && BASE_BRANCH=main bash "$DISPATCH" 5 > "$TMP/disp.out" 2>&1); rc=$?
[ "$rc" = 64 ] && grep -q "repair the DevKit" "$TMP/disp.out" && grep -q "half-installed" "$TMP/disp.out" \
  && ok "dispatch with a broken DevKit: refused with its reason, not as an origin fault" || fail "dispatch with a broken DevKit: rc $rc: $(tail -1 "$TMP/disp.out")"
rm "$D/main/.agents/devkit" && ln -s "$ROOT/universal-agent-devkit" "$D/main/.agents/devkit"
G "$D/main" worktree add -q --detach "$D/side" main
(cd "$D/side" && BASE_BRANCH=main bash "$DISPATCH" 5 > "$TMP/disp.out" 2>&1); rc=$?
[ "$rc" = 64 ] && grep -q "run from the main checkout" "$TMP/disp.out" && ok "dispatch from a linked worktree: refused early, the main checkout named" \
  || fail "dispatch from a linked worktree: rc $rc: $(tail -1 "$TMP/disp.out")"
G "$D/main" push -q origin main:refs/heads/loop/issue-5
(cd "$D/main" && BASE_BRANCH=main bash "$DISPATCH" 5 > "$TMP/disp.out" 2>&1); rc=$?
[ "$rc" = 64 ] && grep -q "already exists on origin" "$TMP/disp.out" && ok "dispatch with loop/issue-N on origin: refused (always a fresh start)" \
  || fail "dispatch with a remote leftover branch: rc $rc: $(tail -1 "$TMP/disp.out")"
G "$D/main" remote set-url origin "$D/missing.git"
(cd "$D/main" && BASE_BRANCH=main bash "$DISPATCH" 5 > "$TMP/disp.out" 2>&1); rc=$?
[ "$rc" = 64 ] && grep -q "cannot reach origin.*missing.git" "$TMP/disp.out" && ok "dispatch with origin unreachable: refused with git's own reason" \
  || fail "dispatch with origin unreachable: rc $rc: $(tail -1 "$TMP/disp.out")"
mkdir -p "$D/main/sub"
(cd "$D/main/sub" && BASE_BRANCH=main bash "$DISPATCH" 5 > "$TMP/disp.out" 2>&1); rc=$?
[ "$rc" = 64 ] && grep -q "run from the repository root" "$TMP/disp.out" && ok "dispatch from a subfolder: refused, the repository root named" \
  || fail "dispatch from a subfolder: rc $rc: $(tail -1 "$TMP/disp.out")"
grep -q 'WT_PY="$REPO_DIR/.agents/devkit/scripts/git/worktree.py"' "$DISPATCH" \
  && grep -q 'python3 "$WT_PY" add "$WORKTREE_DIR" "$WORKER_BRANCH" --lane=build' "$DISPATCH" && ok "super-build-dispatch.sh creates the worktree with the kit" \
  || fail "super-build-dispatch.sh does not use the kit"
RUNMD=.claude/skills/super-board/references/run.md   # the lifecycle every lane prompt says to follow EXACTLY
for f in .claude/skills/super-build/SKILL.md .claude/skills/super-qa/SKILL.md .claude/skills/super-review/SKILL.md "$RUNMD"; do
  grep -q -- "--lane=" "$ROOT/$f" && ok "$f names the kit command" || fail "$f has no kit worktree command"
done
for l in build qa review; do
  grep -q -- "--lane=$l" "$ROOT/$RUNMD" || fail "run.md: no kit command for the $l lane"
done
grep -q 'Pull `issue-<N>-<slug>` into the review worktree' "$ROOT/$RUNMD" "$ROOT/.claude/skills/super-review/SKILL.md" \
  && fail "a detached review worktree is still told to git pull the branch" || ok "the detached review worktree is refreshed by checkout --detach, not pull"
# a plain `git worktree add` may still be NAMED, only as what not to do
bad=""
for f in "$WAVE" "$RUNNER" "$DISPATCH" "$ROOT/.claude/skills/super-build/SKILL.md" "$ROOT/.claude/skills/super-qa/SKILL.md" "$ROOT/.claude/skills/super-review/SKILL.md" "$ROOT/$RUNMD"; do
  hits=$(grep -n 'git worktree add' "$f" | grep -viE 'never|not |instead of|lacked|thiếu|trần|plain' || true)
  [ -z "$hits" ] || bad="$bad ${f#$ROOT/}:$hits"
done
[ -z "$bad" ] && ok "no lane file tells a lane to run a plain git worktree add" || fail "plain git worktree add instructions left:$bad"

[ "$FAILS" -eq 0 ] && echo "✅ test_lane_worktree_kit: all passed" || { echo "❌ test_lane_worktree_kit: $FAILS failed"; exit 1; }
