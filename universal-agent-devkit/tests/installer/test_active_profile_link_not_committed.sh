#!/usr/bin/env bash
# Hồi quy (13/11, audit prompt cài đặt): `agent-kit init -m copy` là chế độ để commit bản cài, nhưng `.agents/active-profile` là symlink
# tới profiles/<id> của kit trên MÁY NÀY và không bị git ignore (chế độ symlink loại nó qua .git/info/exclude, chế độ copy thì không).
# Đo thật: `agent-kit health` cảnh báo "1 link DevKit chưa bị loại khỏi git"; `git add -A` commit luôn link đó và bản clone nhận link treo.
# Nay bước 6b của install.sh (ghi các link vào kit vào .git/info/exclude) chạy ở cả chế độ copy. Không sửa khối .gitignore của kit:
# khối đó phải khớp .gitignore đã commit của từng repo, lệch một dòng là mọi worktree có ` M .gitignore` (K7).
# Review 13/11 (principal-code-reviewer): cách thử đầu tiên chép profile vào .agents/devkit rồi link tương đối vẫn để link được commit
# trong khi đích bị ignore, nên bản clone vẫn treo — test này kiểm đúng bản clone.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unset CLAUDE_PROJECT_DIR TARGET_DIR
export DEVKIT_LANG=en
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mk() { P="$TMP/$1"; mkdir -p "$P" && git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t
       echo "# app" > "$P/README.md" && git -C "$P" add README.md && git -C "$P" commit -qm init; }
install() { bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a claude -m "$1" --no-githooks > "$TMP/i.out" 2>&1 \
              || fail "install -m $1 failed: $(tail -3 "$TMP/i.out" | tr '\n' ' ' | cut -c1-200)"; }
dangling() {  # symlink có đích không tồn tại trong cây $1 (trừ .git)
  (cd "$1" && find . -path ./.git -prune -o -type l -print | while read -r l; do [ -e "$l" ] || echo "$l"; done | tr '\n' ' ')
}

for MODE in copy symlink; do
  mk "$MODE"; install "$MODE"
  L="$P/.agents/active-profile"
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id"))' "$L/profile.json" 2>/dev/null)" = "universal" ] \
    && ok "[$MODE] the profile link works on the machine that installed" || fail "[$MODE] $L/profile.json is not readable"
  git -C "$P" check-ignore -q .agents/active-profile && ok "[$MODE] .agents/active-profile is git-ignored" \
    || fail "[$MODE] .agents/active-profile is not ignored: git add would commit a link to this machine's kit"
  git -C "$P" add -A && git -C "$P" commit -qm "install" 2>/dev/null
  git -C "$P" ls-files --error-unmatch -- .agents/active-profile >/dev/null 2>&1 \
    && fail "[$MODE] 'git add -A' committed .agents/active-profile ($(readlink "$L" | cut -c1-80))" \
    || ok "[$MODE] 'git add -A' does not commit the link"
  # Clone sâu hơn bản gốc: link tương đối tới kit không còn đúng, như ở máy khác.
  mkdir -p "$TMP/deeper/$MODE/x" && git clone -q "$P" "$TMP/deeper/$MODE/x/clone" 2>/dev/null
  d="$(dangling "$TMP/deeper/$MODE/x/clone")"
  if [ "$MODE" = copy ]; then   # chế độ symlink commit cả link tuyệt đối của kit là điều install.sh đã cảnh báo: không kiểm ở đây
    [ -z "$d" ] && ok "[copy] a clone of the committed install has no dangling symlink" || fail "[copy] dangling symlinks in a clone: $(printf '%s' "$d" | cut -c1-200)"
  fi
  python3 "$DEVKIT/bin/agent-health.py" -t "$P" > "$TMP/h.out" 2>&1
  grep -q 'DevKit links not excluded from git' "$TMP/h.out" && fail "[$MODE] health reports a machine link: $(grep 'not excluded from git' "$TMP/h.out" | cut -c1-160)" \
    || ok "[$MODE] health reports no DevKit link left out of git's ignore list"
  install "$MODE"   # cài lại: .git/info/exclude không nhân đôi dòng; .gitignore đã commit không bị đụng (K7: không ` M .gitignore`)
  n="$(grep -c '^/\.agents/active-profile$' "$P/.git/info/exclude" 2>/dev/null)"
  [ "$n" = 1 ] && git -C "$P" diff --quiet -- .gitignore && ok "[$MODE] re-init keeps one exclude line and leaves the committed .gitignore alone" \
    || fail "[$MODE] after re-init: $n exclude line(s) for the link, .gitignore $(git -C "$P" diff --quiet -- .gitignore && echo unchanged || echo CHANGED)"
done

[ "$FAILS" -eq 0 ] && echo "✅ test_active_profile_link_not_committed: all passed" || { echo "❌ test_active_profile_link_not_committed: $FAILS failed"; exit 1; }
