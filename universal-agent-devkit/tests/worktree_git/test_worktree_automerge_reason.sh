#!/usr/bin/env bash
# `agent-kit worktree finish` / the merge gate's automerge, a REFUSED commit (2026-10-09, GeelyEx2: giao-tichhop-09-10 and base-hoiquy-09-10
# stayed unmerged, held 3 times, then left behind). The repo's pre-commit gate refuses the worktree's commit; the message kept only the
# last 500 characters of its output — the gate prints its findings ABOVE a long list of passed checks and a footer, so the hold text
# ("…sửa rồi commit ở worktree…: g: 0 phát hiện ✔ Nuốt lỗi … KẾT LUẬN: REJECT") never said WHY and nobody could act on it.
# The message now carries the lines that name the refusal (✖ / REJECT / BLOCK / error, colour codes dropped) plus the last lines.
# #366: finish no longer commits the worktree's work at all (it used to make a `wip(...)` commit that went into main without review), so no
# commit hook runs inside it and there is no hook output to lose: the refusal names the uncommitted files, and that is what is checked here.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${WM_KIT:-$DEVKIT_DIR/bin/agent-kit}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

P="$TMP/main"; mkdir -p "$P" && G "$P" init -q -b main . && cd "$P" || exit 1
printf '1\n' > "$P/a.txt"; G "$P" add -A && G "$P" commit -qm init
bash "$KIT" worktree add "../am-r" --no-init >/dev/null 2>&1 || fail "add am-r"
echo work > "$TMP/am-r/r.txt"
WHEAD="$(G "$TMP/am-r" rev-parse HEAD)"
# a gate-like hook that must NOT run: finish makes no commit, so it never reaches the repo's pre-commit gate
mkdir -p "$P/.git/hooks"
printf '#!/bin/sh\ntouch "%s/hook-ran"\nexit 1\n' "$TMP" > "$P/.git/hooks/pre-commit"
chmod +x "$P/.git/hooks/pre-commit"
out="$(cd "$P" && bash "$KIT" worktree finish ../am-r 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ -f "$TMP/am-r/r.txt" ] && ok "uncommitted work holds it (exit 1) and the work stays in the worktree" || fail "hold: rc=$rc"
printf '%s' "$out" | grep -q "r.txt" && printf '%s' "$out" | grep -qi "uncommitted" && ok "  … and the message names the uncommitted file" || fail "the file is not named: $(printf '%s' "$out" | tail -c 400)"
[ "$(G "$TMP/am-r" rev-parse HEAD)" = "$WHEAD" ] && ! G "$TMP/am-r" log --format=%s | grep -q "^wip" && [ ! -e "$TMP/hook-ran" ] && ok "  … no commit was made (no wip, HEAD unchanged, no commit hook ran)" || fail "a commit was made or a hook ran"
json="$(cd "$P" && bash "$KIT" worktree automerge ../am-r 2>/dev/null | grep '^{' | tail -1)"
printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("status")=="blocked" and "r.txt" in d.get("message","") and "r.txt" in d.get("files",[]) else 1)' \
  && ok "automerge (the Stop gate) reports the same refusal in its JSON line" || fail "automerge JSON: $json"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_automerge_reason: all passed" || { echo "❌ test_worktree_automerge_reason: $FAILS failed"; exit 1; }
