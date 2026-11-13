#!/usr/bin/env bash
# Hồi quy (13/11, audit prompt cài đặt): `agent-kit init -m copy` là chế độ để commit bản cài cho nhiều người/CI, nhưng
# `.agents/active-profile` vẫn là symlink leo ra ngoài dự án tới profiles/<id> của kit trên MÁY NÀY. Đo thật trên repo thử:
# readlink = ../../…/agent-workbench/universal-agent-devkit/profiles/universal, không bị git ignore, `agent-kit health` cảnh báo
# "1 link DevKit chưa bị loại khỏi git". Commit vào thì máy khác nhận link treo. Nay chế độ copy chép profile đang dùng vào
# .agents/devkit/active-profile và link trỏ vào đó (tương đối, trong dự án). Chế độ symlink không đổi.
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
              || { fail "install -m $1 failed: $(tail -3 "$TMP/i.out" | tr '\n' ' ' | cut -c1-200)"; }; }
outside_links() {  # symlink trong dự án (trừ .git) có đích nằm NGOÀI dự án
  python3 - "$P" <<'PY'
import os, sys
root = os.path.realpath(sys.argv[1])
for d, dirs, files in os.walk(root):
    dirs[:] = [x for x in dirs if not (d == root and x == ".git")]
    for n in dirs + files:
        p = os.path.join(d, n)
        if os.path.islink(p) and not (os.path.realpath(p) + os.sep).startswith(root + os.sep):
            print(os.path.relpath(p, root))
PY
}

mk copy; install copy
L="$P/.agents/active-profile"
[ -L "$L" ] && [ "$(readlink "$L")" = "devkit/active-profile" ] && ok "B1: copy mode links .agents/active-profile to the copy inside the project" \
  || fail "B1: .agents/active-profile → '$(readlink "$L" 2>/dev/null | cut -c1-120)' (expected devkit/active-profile)"
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id"))' "$L/profile.json" 2>/dev/null)" = "universal" ] \
  && ok "B2: the profile is readable through the link (profile.json id = universal)" || fail "B2: $L/profile.json is not the universal profile"
[ -f "$L/RULES.md" ] && ok "B2b: the profile's own relative link (RULES.md) resolves inside the copy" || fail "B2b: $L/RULES.md does not resolve"
out="$(outside_links)"
[ -z "$out" ] && ok "B3: no symlink of a copy-mode install points outside the project" || fail "B3: links leaving the project: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
python3 "$DEVKIT/bin/agent-health.py" -t "$P" > "$TMP/h.out" 2>&1
grep -q 'DevKit links not excluded from git' "$TMP/h.out" && fail "B4: health still reports a machine link: $(grep 'not excluded from git' "$TMP/h.out" | cut -c1-160)" \
  || ok "B4: health no longer reports a DevKit link that is not excluded from git"
install copy   # cài lại: không sinh bản *_old, link giữ nguyên
left="$(cd "$P" && find . -path ./.git -prune -o \( -name 'active-profile_old*' -o -name 'devkit_old*' \) -print | tr '\n' ' ')"
[ -z "$left" ] && [ "$(readlink "$L")" = "devkit/active-profile" ] && ok "B5: a second init keeps the link and leaves no *_old copy" \
  || fail "B5: after re-init link='$(readlink "$L" 2>/dev/null)' leftovers='$left'"
bash "$DEVKIT/bin/agent-kit" uninstall "$P" --apply > "$TMP/u.out" 2>&1 || fail "uninstall --apply failed: $(tail -2 "$TMP/u.out" | tr '\n' ' ' | cut -c1-160)"
{ [ ! -e "$L" ] && [ ! -L "$L" ] && [ ! -e "$P/.agents/devkit/active-profile" ]; } && ok "B6: uninstall removes the link and the profile copy" \
  || fail "B6: after uninstall: link $( [ -L "$L" ] && echo present || echo gone ), copy $( [ -e "$P/.agents/devkit/active-profile" ] && echo present || echo gone )"

mk link; install symlink
want="$(cd "$DEVKIT/profiles/universal" && pwd -P)"
[ -L "$P/.agents/active-profile" ] && [ "$(cd "$P/.agents/active-profile" && pwd -P)" = "$want" ] \
  && ok "B7: symlink mode is unchanged (the link still resolves to the kit's profiles/universal)" \
  || fail "B7: symlink mode link → '$(readlink "$P/.agents/active-profile" 2>/dev/null | cut -c1-120)'"
[ ! -e "$P/.agents/devkit/active-profile/.devkit-copy" ] && ok "B7b: symlink mode makes no profile copy in the project" || fail "B7b: symlink mode copied the profile"

[ "$FAILS" -eq 0 ] && echo "✅ test_copy_mode_profile_in_project: all passed" || { echo "❌ test_copy_mode_profile_in_project: $FAILS failed"; exit 1; }
