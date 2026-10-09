#!/usr/bin/env bash
# `agent-kit worktree finish` / the merge gate's automerge, a REFUSED commit (2026-10-09, GeelyEx2: giao-tichhop-09-10 and base-hoiquy-09-10
# stayed unmerged, held 3 times, then left behind). The repo's pre-commit gate refuses the worktree's commit; the message kept only the
# last 500 characters of its output — the gate prints its findings ABOVE a long list of passed checks and a footer, so the hold text
# ("…sửa rồi commit ở worktree…: g: 0 phát hiện ✔ Nuốt lỗi … KẾT LUẬN: REJECT") never said WHY and nobody could act on it.
# The message now carries the lines that name the refusal (✖ / REJECT / BLOCK / error, colour codes dropped) plus the last lines.
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
# a gate-like hook: colour codes, the finding near the top, 40 passed checks, a footer
mkdir -p "$P/.git/hooks"
cat > "$P/.git/hooks/pre-commit" <<'HOOK'
#!/bin/sh
printf '\033[1m[1/8] secrets\033[0m\n'
printf '  \033[91m✖\033[0m leaked key in src/x.py:3 (AKIA…)\n'
i=0; while [ $i -lt 40 ]; do printf '  \033[92m✔\033[0m check %s: 0 findings\n' "$i"; i=$((i+1)); done
printf '  KẾT LUẬN: REJECT — fix the points above, then commit again\n'
exit 1
HOOK
chmod +x "$P/.git/hooks/pre-commit"
out="$(cd "$P" && bash "$KIT" worktree finish ../am-r 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ -f "$TMP/am-r/r.txt" ] && ok "a refused commit holds it (exit 1) and the work stays in the worktree" || fail "hold: rc=$rc"
printf '%s' "$out" | grep -q "leaked key in src/x.py:3" && ok "  … and the message says WHAT the gate refused (the finding above the long list)" || fail "the reason is missing: $(printf '%s' "$out" | tail -c 400)"
printf '%s' "$out" | grep -q $'\033' && fail "colour codes in the message" || ok "  … without colour codes"
printf '%s' "$out" | grep -q "KẾT LUẬN: REJECT" && ok "  … and the gate's verdict line" || fail "verdict line missing"
[ "$(printf '%s' "$out" | wc -c)" -lt 2500 ] && ok "  … in a bounded message" || fail "message too long: $(printf '%s' "$out" | wc -c)"
json="$(cd "$P" && bash "$KIT" worktree automerge ../am-r 2>/dev/null | grep '^{' | tail -1)"
printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("status")=="blocked" and "leaked key in src/x.py:3" in d.get("message","") else 1)' \
  && ok "automerge (the Stop gate) reports the same reason in its JSON line" || fail "automerge JSON: $json"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_automerge_reason: all passed" || { echo "❌ test_worktree_automerge_reason: $FAILS failed"; exit 1; }
