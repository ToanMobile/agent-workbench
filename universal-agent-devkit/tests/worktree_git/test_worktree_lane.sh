#!/usr/bin/env bash
# scripts/git/worktree.py add --lane (19/10, agent-workbench#93): lane super-board (build / qa / review) tạo worktree bằng `git worktree add`
# trần nên thiếu .agents/devkit, .agents/active-profile, hook DevKit và các hook cục bộ bị git ignore mà settings đăng ký (guard-*.py,
# cleanup-wt.py: settings của dự án VÀ của người dùng gọi chúng theo $CLAUDE_PROJECT_DIR) -> `agent-kit health` FAIL trong worktree, phiên
# Claude khởi động ở đó bị chặn mọi Bash/Read (python3 file-không-có exit 2); repo Unity import lại cả Library (Goods ~9,9 GB mỗi worktree).
# Luật ở đây:
#  1. `add` chép các file bị ignore, chưa track ở .claude/hooks/ của main (file thường chép, link tạo lại theo đích thật); worktree mới
#     qua health không còn "registered hooks missing"; `heal` sau một `git worktree add` trần cũng sửa được các hook đó.
#  2. `add` không làm bẩn file được track: lang của main giữ nguyên dù DEVKIT_LANG khác.
#  3. `--lane=<build|qa|review>` (chỉ đường dẫn worktree của board): không bị WORKTREE_MAX chặn và không chiếm chỗ; worktree detached tạo
#     bằng --lane là worktree của board (board_worktree), một worktree detached cùng tên tạo không có --lane vẫn là nợ (K7).
#  4. --lane: nhánh chỉ có trên origin thì đi từ origin/<nhánh>, không phải từ HEAD; worktree đã đăng ký ở đúng đường dẫn thì dùng lại.
#  5. --lane với đường dẫn không phải của board bị từ chối; sàn đĩa vẫn áp dụng (exit 4, không thư mục, không đăng ký).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }
add() { (cd "$P" && env WORKTREE_DISK_WARN_GIB=0 WORKTREE_DISK_MIN_GIB=0 "$@" > "$TMP/out" 2>&1); }   # add <env/argv…>: output in $TMP/out
linked() { G "$P" worktree list --porcelain | grep -c '^worktree ' | awk '{print $1 - 1}'; }
py() { python3 - "$WT" "$@" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("w", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fn = sys.argv[2]
if fn == "board":
    print(m.board_worktree(sys.argv[3]))
elif fn == "live":
    print(len(m._live_worktrees(sys.argv[3])))
PY
}

# fixture: DevKit (symlink mode, lang vi) + a git-ignored local guard hook that the project settings register, like the 5 app repos
P="$TMP/app"; mkdir -p "$P" && G "$P" init -q -b main . && echo x > "$P/a" && G "$P" add a && G "$P" commit -qm init
bash "$DEVKIT_DIR/bin/install.sh" -t "$P" -a claude -p backend -y --lang=vi >/dev/null 2>&1 || { fail "install (fixture)"; exit 1; }
printf 'import sys\nsys.exit(0)\n' > "$P/.claude/hooks/guard-secrets.py"; chmod +x "$P/.claude/hooks/guard-secrets.py"
ln -s "../../a" "$P/.claude/hooks/rel-link.sh"   # a RELATIVE link: copied as-is it would dangle one folder deeper (NFH #18)
python3 - "$P/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s.setdefault("hooks", {}).setdefault("PreToolUse", []).append(
    {"matcher": "Bash", "hooks": [{"type": "command", "command": 'python3 "$CLAUDE_PROJECT_DIR"/.claude/hooks/guard-secrets.py'}]})
json.dump(s, open(sys.argv[1], "w"), indent=2)
PY
printf '/.claude/hooks/guard-*.py\n/.claude/hooks/rel-link.sh\n' >> "$P/.git/info/exclude"
G "$P" add -A >/dev/null 2>&1; G "$P" commit -qm devkit >/dev/null 2>&1
G "$P" check-ignore -q .claude/hooks/guard-secrets.py && grep -q '"lang": "vi"' "$P/.agents/active-profile.json" \
  || { fail "fixture: guard hook not ignored or lang not vi"; exit 1; }

# 1 + 2: a lane worktree made by the kit has the local hook, a working copy of the relative link, a clean status and health without
# "registered hooks missing" — under another DEVKIT_LANG than main's
B="$P/.claude/worktrees/issue-5-build"
add env DEVKIT_LANG=en python3 "$WT" add "$B" issue-5-fix --lane=build; rc=$?
[ "$rc" = 0 ] || fail "add --lane=build failed (rc $rc): $(tail -5 "$TMP/out")"
if [ -f "$B/.claude/hooks/guard-secrets.py" ] && cmp -s "$P/.claude/hooks/guard-secrets.py" "$B/.claude/hooks/guard-secrets.py" \
    && [ -x "$B/.claude/hooks/guard-secrets.py" ]; then
  ok "add copies a git-ignored local hook of main (same bytes, executable)"
else
  fail "the local hook is missing or differs in the kit worktree"
fi
[ -e "$B/.claude/hooks/rel-link.sh" ] && ok "  … and recreates a relative hook link so it resolves" || fail "relative hook link missing or dangling: $(readlink "$B/.claude/hooks/rel-link.sh" 2>&1)"
[ -d "$B" ] && [ -z "$(G "$B" status --porcelain)" ] && ok "add leaves no tracked file changed (main's lang kept under DEVKIT_LANG=en)" \
  || fail "add dirtied tracked files: $(G "$B" status --porcelain | tr '\n' ' ')"
(cd "$B" && python3 "$DEVKIT_DIR/bin/agent-health.py" > "$TMP/health" 2>&1)
{ ! grep -qE "Score|Điểm" "$TMP/health" || grep -q "Registered hooks with no file\|hook đăng ký nhưng thiếu file" "$TMP/health"; } \
  && fail "health in the kit worktree still lists missing hooks: $(grep -m1 'Registered hooks' "$TMP/health")" \
  || ok "health in the kit worktree: no registered hook missing"
grep -q "Score: 100/100" "$TMP/health" && ok "  … and health scores 100/100 (#93 AC)" || fail "health in the kit worktree: $(grep -m1 'Result' "$TMP/health")"
[ "$(G "$B" symbolic-ref --short HEAD)" = issue-5-fix ] && ok "the lane worktree is on its named branch" || fail "lane worktree not on issue-5-fix"

# 1b: a plain `git worktree add` then `heal` gets the DevKit hook links and the local hook too
H="$P/.claude/worktrees/issue-6-build"
G "$P" worktree add -q -b issue-6-x "$H" HEAD
(cd "$H" && python3 "$WT" heal --devkit="$DEVKIT_DIR" > "$TMP/out" 2>&1)
if [ -f "$H/.claude/hooks/guard-secrets.py" ] && [ -f "$H/.claude/hooks/block-dangerous-git.sh" ] && [ -e "$H/.claude/hooks/rel-link.sh" ]; then
  ok "heal after a plain git worktree add: DevKit hook links and the local hook are there"
else
  fail "heal left hooks missing: $(ls "$H/.claude/hooks" 2>&1 | tr '\n' ' ' | cut -c1-200)"
fi
[ -d "$H/.claude/hooks" ] && [ -z "$(G "$H" status --porcelain)" ] && ok "  … and nothing shows in git status" || fail "heal dirtied status: $(G "$H" status --porcelain | tr '\n' ' ')"
G "$P" worktree remove --force "$H" >/dev/null 2>&1

# 3: the cap. One ordinary worktree with WORKTREE_MAX=1 fills it; lane worktrees still get made and take no slot
add env WORKTREE_MAX=1 python3 "$WT" add "$TMP/side" --no-init || fail "setup: side worktree ($(cat "$TMP/out"))"
add env WORKTREE_MAX=1 python3 "$WT" add "$P/.claude/worktrees/issue-7-qa" issue-7-x --lane=qa --no-init; rc=$?
[ "$rc" = 0 ] && ok "add --lane=qa is not refused by a full WORKTREE_MAX" || fail "lane add refused at the cap (rc $rc): $(tail -3 "$TMP/out")"
R="$P/.claude/worktrees/issue-7-review"
add env WORKTREE_MAX=1 python3 "$WT" add "$R" --lane=review --base=issue-5-fix --no-init; rc=$?
[ "$rc" = 0 ] && [ -z "$(G "$R" symbolic-ref -q --short HEAD)" ] && ok "a detached review checkout (--lane=review --base=<branch>) is made at the cap" \
  || fail "detached review add: rc $rc: $(tail -3 "$TMP/out")"
[ "$(py board "$R")" = True ] && ok "  … and is a board worktree (no debt of another session)" || fail "detached --lane worktree is not board_worktree"
[ "$(py live "$P")" = 1 ] && ok "lane worktrees take no WORKTREE_MAX slot (only the ordinary one counts)" || fail "live count = $(py live "$P"), want 1"
D="$P/.claude/worktrees/issue-8-review"
G "$P" worktree add -q --detach "$D" HEAD
[ "$(py board "$D")" = False ] && ok "a detached issue-8-review made without --lane stays a session's debt (K7)" || fail "detached non-lane worktree counted as board"
G "$P" worktree remove --force "$D" >/dev/null 2>&1

# 4: a branch only on origin is checked out from origin/<branch>, not from HEAD; a registered worktree at the path is reused
O="$TMP/origin.git"; G "$P" init -q --bare "$O" 2>/dev/null || git init -q --bare "$O"
G "$P" remote add origin "$O"
G "$P" switch -q -c issue-9-remote && echo remote > "$P/r.txt" && G "$P" add r.txt && G "$P" commit -qm remote && G "$P" push -q origin issue-9-remote
tip=$(G "$P" rev-parse HEAD); G "$P" switch -q main && G "$P" branch -q -D issue-9-remote
G "$P" update-ref -d refs/remotes/origin/issue-9-remote   # never fetched here: add must fetch it itself
add python3 "$WT" add "$P/.claude/worktrees/issue-9-qa" issue-9-remote --lane=qa --base=main --no-init; rc=$?
[ "$rc" = 0 ] && [ "$(G "$P/.claude/worktrees/issue-9-qa" rev-parse HEAD)" = "$tip" ] \
  && ok "--lane on a branch only origin has: the worktree starts at origin/<branch>, not --base / HEAD" \
  || fail "origin-only branch: rc $rc head $(G "$P/.claude/worktrees/issue-9-qa" rev-parse HEAD 2>/dev/null) want $tip: $(tail -3 "$TMP/out")"
n9=$(linked)
add python3 "$WT" add "$P/.claude/worktrees/issue-9-qa" issue-9-remote --lane=qa --no-init; rc=$?
[ "$rc" = 0 ] && [ "$(linked)" = "$n9" ] && [ "$(G "$P/.claude/worktrees/issue-9-qa" rev-parse HEAD)" = "$tip" ] && grep -qiE "reus|dùng lại" "$TMP/out" \
  && ok "a registered lane worktree at the path is reused (exit 0, nothing added, nothing moved)" \
  || fail "reuse: rc $rc: $(tail -3 "$TMP/out")"
add python3 "$WT" add "$P/.claude/worktrees/issue-9-qa" other-branch --lane=qa --no-init; rc=$?
[ "$rc" != 0 ] && ok "  … but not when it holds another branch (rc $rc)" || fail "reused a lane worktree on the wrong branch"
add python3 "$WT" add "$P/.claude/worktrees/issue-9-qa" --lane=qa --base=main --no-init; rc=$?
[ "$rc" != 0 ] && [ "$(G "$P/.claude/worktrees/issue-9-qa" symbolic-ref -q --short HEAD)" = issue-9-remote ] \
  && ok "  … nor moved off its branch when a detached checkout is asked at its path (rc $rc)" || fail "a branch worktree was moved off its branch"
# 4b: the Reviewer's detached checkout, reused: moved to --base (no stale PR head) and the board's; never when it holds work
echo more > "$B/more.txt" && G "$B" add more.txt && G "$B" commit -qm more && newtip=$(G "$B" rev-parse HEAD)
add python3 "$WT" add "$R" --lane=review --base=issue-5-fix --no-init; rc=$?
[ "$rc" = 0 ] && [ "$(G "$R" rev-parse HEAD)" = "$newtip" ] && [ "$(py board "$R")" = True ] \
  && ok "a reused detached review checkout moves to --base (the new PR head) and stays the board's" \
  || fail "detached reuse: rc $rc head $(G "$R" rev-parse --short HEAD) want ${newtip:0:7}: $(tail -3 "$TMP/out")"
G "$B" commit -q --amend -m "more, amended"; amended=$(G "$B" rev-parse HEAD)   # the Builder rewrites the PR head (rebase/amend + force-push)
add python3 "$WT" add "$R" --lane=review --base=issue-5-fix --no-init; rc=$?
[ "$rc" = 0 ] && [ "$(G "$R" rev-parse HEAD)" = "$amended" ] \
  && ok "  … also after the PR head was rewritten (the old head, now unreferenced, is no work of the review)" \
  || fail "reuse after a rewritten PR head: rc $rc: $(tail -2 "$TMP/out")"
newtip="$amended"
D2="$P/.claude/worktrees/issue-13-review"
G "$P" worktree add -q --detach "$D2" main
add python3 "$WT" add "$D2" --lane=review --base=issue-5-fix --no-init; rc=$?
[ "$rc" = 0 ] && [ "$(py board "$D2")" = True ] && [ "$(G "$D2" rev-parse HEAD)" = "$newtip" ] \
  && ok "a plain detached checkout at a lane path, reused with --lane: moved and marked the board's" \
  || fail "plain detached reuse: rc $rc board $(py board "$D2"): $(tail -3 "$TMP/out")"
echo work > "$D2/notes.txt"
add python3 "$WT" add "$D2" --lane=review --base=main --no-init; rc=$?
[ "$rc" != 0 ] && [ -f "$D2/notes.txt" ] && [ "$(G "$D2" rev-parse HEAD)" = "$newtip" ] \
  && ok "  … but a detached checkout holding uncommitted work is neither moved nor marked (rc $rc)" \
  || fail "detached reuse with work: rc $rc, HEAD $(G "$D2" rev-parse --short HEAD)"

# 4b2: the Tester behind a Builder's leftover worktree: refused with the way out named, nothing made
add python3 "$WT" add "$P/.claude/worktrees/issue-5-qa" issue-5-fix --lane=qa --no-init; rc=$?
[ "$rc" = 1 ] && [ ! -e "$P/.claude/worktrees/issue-5-qa" ] && grep -q "git worktree remove [^\`]*/issue-5-build\`" "$TMP/out" \
  && ok "a branch another lane worktree holds: exit 1 naming the worktree to remove" || fail "held branch: rc $rc: $(tail -2 "$TMP/out")"
# 4c (review 19/10): a board lane worktree never reaches main by itself — not detached, not on an issue branch not yet pushed
mainhead=$(G "$P" rev-parse main)
for w in "$R" "$B"; do
  out=$(cd "$P" && python3 "$WT" automerge "$w" 2>&1)
  if printf '%s' "$out" | grep -q '"status": *"blocked"' && [ "$(G "$P" rev-parse main)" = "$mainhead" ]; then
    ok "automerge refuses the lane worktree ${w##*/} (main untouched)"
  else
    fail "automerge on ${w##*/}: $(printf '%s' "$out" | tail -c 300) / main $(G "$P" rev-parse --short main)"
  fi
done
# 4d: a NEW issue branch off origin/<base> gets no upstream (a bare push/pull would hit main); one from origin/<branch> tracks it
G "$P" push -q origin main
add python3 "$WT" add "$P/.claude/worktrees/issue-14-build" issue-14-new --lane=build --base=origin/main --no-init; rc=$?
up=$(G "$P/.claude/worktrees/issue-14-build" rev-parse --abbrev-ref '@{u}' 2>/dev/null)
[ "$rc" = 0 ] && [ -z "$up" ] && ok "a new issue branch off origin/main has no upstream" || fail "new lane branch: rc $rc upstream '$up'"
up=$(G "$P/.claude/worktrees/issue-9-qa" rev-parse --abbrev-ref '@{u}' 2>/dev/null)
[ "$up" = origin/issue-9-remote ] && ok "  … and the branch taken from origin/<branch> tracks it" || fail "origin branch upstream: '$up'"
# 4d2: a remote-tracking ref origin no longer has (PR branch merged and deleted, issue picked up again): the lane starts off --base
G "$P" update-ref refs/remotes/origin/issue-19-old "$tip"
add python3 "$WT" add "$P/.claude/worktrees/issue-19-build" issue-19-old --lane=build --base=origin/main --no-init; rc=$?
[ "$rc" = 0 ] && [ "$(G "$P/.claude/worktrees/issue-19-build" rev-parse HEAD)" = "$(G "$P" rev-parse origin/main)" ] \
  && ok "a stale origin/<branch> origin no longer holds is not used: the lane starts off --base" \
  || fail "stale remote-tracking ref: rc $rc head $(G "$P/.claude/worktrees/issue-19-build" rev-parse --short HEAD 2>/dev/null)"
# 4e: offline (origin unreachable): no new branch is started off the base while it is unknown whether origin has the PR branch
G "$P" remote set-url origin "$TMP/nowhere.git"
n1=$(linked)
add python3 "$WT" add "$P/.claude/worktrees/issue-15-qa" issue-15-x --lane=qa --base=main --no-init; rc=$?
[ "$rc" = 1 ] && [ "$(linked)" = "$n1" ] && ! G "$P" rev-parse -q --verify refs/heads/issue-15-x >/dev/null \
  && ok "origin unreachable: refused (exit 1), no worktree, no branch" || fail "offline add: rc $rc: $(tail -2 "$TMP/out")"
G "$P" remote set-url origin "$O"
# 4f: --lane only right in the MAIN checkout's .claude/worktrees (not nested in another worktree, not the legacy .worktrees/)
(cd "$B" && env WORKTREE_DISK_WARN_GIB=0 WORKTREE_DISK_MIN_GIB=0 python3 "$WT" add .claude/worktrees/issue-16-build issue-16-x --lane=build --no-init > "$TMP/out" 2>&1); rc=$?
[ "$rc" = 2 ] && [ ! -e "$B/.claude/worktrees/issue-16-build" ] && ok "--lane from inside another worktree (relative path) is refused, nothing nested" \
  || fail "nested lane add: rc $rc"
add python3 "$WT" add "$P/.worktrees/issue-17" issue-17-x --lane=build --no-init; rc=$?
[ "$rc" = 2 ] && [ ! -e "$P/.worktrees/issue-17" ] && ok "--lane in the legacy .worktrees/ is refused" || fail "legacy .worktrees lane add: rc $rc"
# 4g: reusing a checkout an old plain `git worktree add` made installs the DevKit too: health 100/100 there
D3="$P/.claude/worktrees/issue-18-review"
G "$P" worktree add -q --detach "$D3" main
add python3 "$WT" add "$D3" --lane=review --base=main; rc=$?
(cd "$D3" && python3 "$DEVKIT_DIR/bin/agent-health.py" > "$TMP/health3" 2>&1)
[ "$rc" = 0 ] && grep -q "Score: 100/100" "$TMP/health3" && ok "a reused plain checkout gets the DevKit installed: health 100/100" \
  || fail "reused plain checkout: rc $rc, $(grep -m1 'Result' "$TMP/health3")"

# 5: --lane only for board paths; the disk floor still refuses with nothing half-made
n0=$(linked)
add python3 "$WT" add "$TMP/not-a-lane" issue-10-x --lane=build --no-init; rc=$?
[ "$rc" = 2 ] && [ ! -e "$TMP/not-a-lane" ] && [ "$(linked)" = "$n0" ] && ok "--lane on a path that is no board worktree is refused (exit 2, nothing made)" \
  || fail "--lane outside .claude/worktrees/issue-N-*: rc $rc"
add python3 "$WT" add "$P/.claude/worktrees/issue-11-build" issue-11-x --lane=bogus --no-init; rc=$?
[ "$rc" = 2 ] && ok "--lane with an unknown lane is refused (exit 2)" || fail "--lane=bogus: rc $rc"
(cd "$P" && env WORKTREE_DISK_MIN_GIB=100000 WORKTREE_DISK_WARN_GIB=0 python3 "$WT" add "$P/.claude/worktrees/issue-12-build" issue-12-x --lane=build --no-init > "$TMP/out" 2>&1); rc=$?
if [ "$rc" = 4 ] && [ ! -e "$P/.claude/worktrees/issue-12-build" ] && [ "$(linked)" = "$n0" ] && grep -q "GiB" "$TMP/out" \
    && ! G "$P" rev-parse -q --verify refs/heads/issue-12-x >/dev/null; then
  ok "--lane under the disk floor: exit 4 with the free space named, no folder, no registration, no branch"
else
  fail "disk floor with --lane: rc $rc: $(cat "$TMP/out")"
fi

for w in $(G "$P" worktree list --porcelain | sed -n 's/^worktree //p' | tail -n +2); do G "$P" worktree remove --force "$w" >/dev/null 2>&1; done
echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_lane: PASS"; exit 0; } || { echo "test_worktree_lane: FAIL ($FAILS)"; exit 1; }
