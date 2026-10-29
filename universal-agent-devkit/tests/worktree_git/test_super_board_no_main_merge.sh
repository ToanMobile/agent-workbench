#!/usr/bin/env bash
# #576 (28/10): on a repo with a super-board config (.claude/super-board/configs/*.json) work reaches main by PR + merge gate only.
# The Stop hook's auto-merge (`worktree automerge` / `finish`) and `agent-kit integrate` merged / pushed card commits (#546-#548) into
# main with no PR. Now: S1 auto-merge refuses on a super-board repo, main HEAD unchanged, the work stays in its worktree, the message
# says to open a PR · S2 integrate refuses (exit 2): no gate, no push, advice to open a PR · S3 no super-board config: auto-merge still
# fast-forwards main (trunk-merge behaviour unchanged).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${WM_KIT:-$DEVKIT_DIR/bin/agent-kit}"
TMP="$(mktemp -d)"; TMP="$(cd -P "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
export DEVKIT_GATE_SLOTS=0 SB_HEAVY_SLOT_DIR="$TMP/slots" WORKTREE_AUTO_MERGE=1

mkrepo() {   # $1 name, $2 "sb" = with a super-board config; main + bare origin, one pending commit on a worktree
  local P="$TMP/$1" O="$TMP/$1-origin.git"
  git init -q --bare -b main "$O"; mkdir -p "$P" && G "$P" init -q -b main . && G "$P" remote add origin "$O"
  printf '1\n' > "$P/a.txt"
  if [ "${2:-}" = sb ]; then mkdir -p "$P/.claude/super-board/configs"; printf '{"base_branch":"main"}\n' > "$P/.claude/super-board/configs/x.json"; fi
  G "$P" add -A && G "$P" commit -qm init && G "$P" push -q origin main
  (cd "$P" && bash "$KIT" worktree add "../$1-wt" --no-init >/dev/null 2>&1) || fail "$1: worktree add"
  echo work > "$TMP/$1-wt/w.txt"; G "$TMP/$1-wt" add -A && G "$TMP/$1-wt" commit -qm "card work"
}

# S1 + S2: super-board repo
mkrepo sb sb; P="$TMP/sb"; BEFORE="$(G "$P" rev-parse HEAD)"
json="$(cd "$P" && bash "$KIT" worktree automerge "../sb-wt" 2>/dev/null | grep '^{' | tail -1)"
printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); m=d.get("message","").lower(); sys.exit(0 if d.get("status")=="blocked" and "open a pr" in m else 1)' \
  && ok "S1 super-board repo: automerge is blocked and the message names the PR route" || fail "S1 automerge JSON: $json"
[ "$(G "$P" rev-parse HEAD)" = "$BEFORE" ] && [ ! -e "$P/w.txt" ] && [ -f "$TMP/sb-wt/w.txt" ] \
  && ok "S1 … main HEAD unchanged, the work is still in its worktree" || fail "S1 main moved or the work was lost"
G "$P" commit -q --allow-empty -m "pending on main"
out="$(cd "$P" && bash "$KIT" integrate 2>&1)"; rc=$?
REMOTE="$(git -C "$TMP/sb-origin.git" rev-parse main)"
[ "$rc" = 2 ] && [ "$REMOTE" = "$BEFORE" ] && printf '%s' "$out" | grep -qi "open a PR" \
  && ok "S2 super-board repo: integrate refuses (exit 2), nothing pushed, advice to open a PR" || fail "S2 rc=$rc remote=$REMOTE out: $(printf '%s' "$out" | tail -c 300)"

# S3: no super-board config: trunk-merge unchanged
mkrepo plain; P="$TMP/plain"
json="$(cd "$P" && bash "$KIT" worktree automerge "../plain-wt" 2>/dev/null | grep '^{' | tail -1)"
printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("status")=="merged" else 1)' && [ -f "$P/w.txt" ] \
  && ok "S3 no super-board config: automerge still merges into main" || fail "S3 automerge JSON: $json"

[ "$FAILS" -eq 0 ] && echo "✅ test_super_board_no_main_merge: all passed" || { echo "❌ test_super_board_no_main_merge: $FAILS failed"; exit 1; }
