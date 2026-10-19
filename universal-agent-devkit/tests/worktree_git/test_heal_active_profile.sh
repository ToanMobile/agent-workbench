#!/usr/bin/env bash
# scripts/git/worktree.py heal, .agents/active-profile (19/10, Neighbours-From-Hell #18 + 5 thẻ chờ nó): lane super-board tự tạo worktree
# bằng `git worktree add`, chép link TƯƠNG ĐỐI `.agents/active-profile` của main y nguyên (`../../../agent-workbench/…`). Sâu thêm 3 cấp
# trong .claude/worktrees/<x>/ thì link đó trỏ vào hư không: lệnh ma trận `bash .agents/active-profile/scripts/unity-batch.sh` exit 127,
# post-fix-gate REJECT, thẻ Blocked. `agent-kit worktree heal` chỉ tạo .agents/devkit (và bỏ qua link gãy) nên không cứu được.
# Luật: heal tạo hoặc sửa .agents/active-profile (thiếu hoặc gãy) theo đích link của main; link đang chạy được thì để yên; không gì
# hiện ra trong git status.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en WORKTREE_TRUNK_MODE=0
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P" && cd "$P" && git init -q -b main . && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false
echo x > a && git add a && git commit -qm init
bash "$DEVKIT_DIR/bin/install.sh" -t "$P" -a claude -p backend -y >/dev/null 2>&1
[ -f .agents/active-profile/profile.json ] || { fail "install did not link .agents/active-profile (fixture)"; exit 1; }
git add -A >/dev/null 2>&1; git commit -qm devkit >/dev/null 2>&1
WT="$P/.claude/worktrees/issue-18-build"
git worktree add -q --detach "$WT" HEAD
heal() { ( cd "$WT" && python3 "$DEVKIT_DIR/scripts/git/worktree.py" heal --devkit="$DEVKIT_DIR" >/dev/null 2>&1 ); }

# 1. worktree có link tương đối của main chép y nguyên: gãy
rm -rf "$WT/.agents/active-profile"; mkdir -p "$WT/.agents"
ln -s "$(readlink "$P/.agents/active-profile")" "$WT/.agents/active-profile"
[ ! -e "$WT/.agents/active-profile" ] || { fail "fixture: copied relative link should dangle in the nested worktree"; }
heal
[ -f "$WT/.agents/active-profile/profile.json" ] && ok "heal repairs a dangling .agents/active-profile (main's relative link copied as-is)" \
  || fail "heal left .agents/active-profile dangling: $(readlink "$WT/.agents/active-profile")"

# 2. worktree không có link nào
rm -f "$WT/.agents/active-profile"
heal
[ -f "$WT/.agents/active-profile/profile.json" ] && ok "heal creates a missing .agents/active-profile" \
  || fail "heal did not create .agents/active-profile"
[ -z "$(git -C "$WT" status --porcelain -- .agents/active-profile)" ] && ok "the link stays out of git status" \
  || fail "the link shows in git status: $(git -C "$WT" status --porcelain -- .agents/active-profile)"

# 3. .agents/devkit gãy cũng được sửa (trước đây heal bỏ qua mọi đường dẫn đã lexists)
rm -rf "$WT/.agents/devkit"; ln -s "$TMP/nowhere" "$WT/.agents/devkit"
heal
[ -f "$WT/.agents/devkit/bin/post-fix-gate.py" ] && ok "heal repairs a dangling .agents/devkit" || fail "heal left .agents/devkit dangling"

# 4. link đang chạy được (người dùng trỏ sang profile khác) thì để yên
rm -f "$WT/.agents/active-profile"; ln -s "$DEVKIT_DIR/profiles/game" "$WT/.agents/active-profile"
heal
[ "$(readlink "$WT/.agents/active-profile")" = "$DEVKIT_DIR/profiles/game" ] && ok "a working link is left alone" \
  || fail "heal rewrote a working link: $(readlink "$WT/.agents/active-profile")"

git worktree remove --force "$WT" >/dev/null 2>&1
[ "$FAILS" -eq 0 ] && echo "✅ test_heal_active_profile: all passed" || { echo "❌ test_heal_active_profile: $FAILS failed"; exit 1; }
