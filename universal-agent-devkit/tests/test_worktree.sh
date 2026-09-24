#!/usr/bin/env bash
# Regression test: `agent-kit worktree` — a worktree set up like the main checkout
# (ignored local config copied, DevKit installed with the same profile), a diff that
# carries the agent's work but not the DevKit setup and applies to the main checkout,
# and a remove that refuses while uncommitted work would be lost.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

M="$TMP/main"
mkdir -p "$M/src" "$M/app"
cd "$M" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
printf '{"name":"x","scripts":{"test":"node -e 0"}}\n' > package.json
printf 'export const a = 1;\n' > src/a.js
printf 'export const gone = 1;\n' > src/gone.js
printf 'node_modules\n.env\napp/google-services.json\n' > .gitignore
git add -A && git commit -qm init
echo "API_KEY=local" > .env && echo '{"k":1}' > app/google-services.json
bash "$KIT" init "$M" -y -a claude -p web --no-githooks >/dev/null 2>&1 || { echo "cannot install into the main checkout"; exit 1; }
main_status="$(git status --porcelain)"

# --- add ------------------------------------------------------------------------------
out="$(bash "$KIT" worktree add ../wt-a 2>&1)"; rc=$?
W="$TMP/wt-a"
[ "$rc" = 0 ] && [ "$(git -C "$W" branch --show-current)" = "feat/wt-a" ] \
  && ok "add: worktree on feat/<folder>" || { fail "add (rc=$rc)"; echo "$out"; }
[ "$(cat "$W/.env" 2>/dev/null)" = "API_KEY=local" ] && [ -f "$W/app/google-services.json" ] \
  && ok "add: git-ignored local config copied (.env, app/google-services.json)" || fail "local config not copied"
grep -q '"profile": *"web"' "$W/.agents/active-profile.json" 2>/dev/null && [ -f "$W/.claude/settings.json" ] && [ -L "$W/.agents/devkit" ] \
  && ok "add: DevKit installed with the main checkout's profile" || fail "DevKit not installed like main"
[ -f "$(git -C "$W" rev-parse --absolute-git-dir)/devkit-worktree.json" ] \
  && ok "add: setup recorded in the worktree's own git dir" || fail "no state file"
[ "$(git status --porcelain)" = "$main_status" ] && ok "add: main checkout untouched" || fail "main checkout changed"
bash "$KIT" worktree add ../wt-a >/dev/null 2>&1; [ $? != 0 ] && ok "add: existing non-empty folder refused" || fail "re-add accepted"

# --- diff: nothing but the setup yet --------------------------------------------------
[ -z "$(bash "$KIT" worktree diff ../wt-a 2>&1)" ] && ok "diff: fresh worktree → empty patch (setup left out)" \
  || fail "diff of a fresh worktree is not empty"

# --- remove: a fresh worktree goes, its branch stays ------------------------------------
bash "$KIT" worktree remove ../wt-a >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$W" ] && git rev-parse --verify -q refs/heads/feat/wt-a >/dev/null \
  && ok "remove: setup-only worktree removed, branch kept" || fail "remove of a fresh worktree (rc=$rc)"

# --- work in a worktree ------------------------------------------------------------------
bash "$KIT" worktree add ../wt-b fix/b >/dev/null 2>&1 || fail "add wt-b"
W="$TMP/wt-b"
printf 'export const a = 2;\n' > "$W/src/a.js"
printf 'export const b = 1;\n' > "$W/src/b.js"
rm "$W/src/gone.js"
echo "note" > "$W/.agents/agent-note.md"          # new file inside a DevKit folder is work too
patch="$(bash "$KIT" worktree diff ../wt-b 2>&1)"
for f in src/a.js src/b.js src/gone.js .agents/agent-note.md; do
  printf '%s' "$patch" | grep -q "^diff --git a/$f " || fail "diff misses $f"
done
printf '%s' "$patch" | grep -qE '^diff --git a/(AGENTS\.md|CLAUDE\.md|\.claude/|\.gitignore|\.active-profile|\.agents/(context|devkit|active-profile))' \
  && fail "diff carries DevKit setup files" || ok "diff: agent's edits, new, deleted files — no DevKit setup"
[ -z "$(git -C "$W" diff --cached --name-only)" ] && ok "diff: the worktree's index is not touched" || fail "diff staged files"

bash "$KIT" worktree remove ../wt-b >"$TMP/rm.out" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$W" ] && grep -q "src/b.js" "$TMP/rm.out" \
  && ok "remove: refused while work is not in the main checkout (lists it)" || fail "remove dropped work (rc=$rc)"

bash "$KIT" worktree diff ../wt-b | git apply --3way >/dev/null 2>&1 \
  && grep -q "a = 2" src/a.js && [ -f src/b.js ] && [ ! -e src/gone.js ] && [ -f .agents/agent-note.md ] \
  && ok "diff | git apply --3way brings the work into the main checkout" || fail "patch did not apply"

bash "$KIT" worktree remove ../wt-b >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$W" ] && ok "remove: allowed once every change is in the main checkout" || fail "remove after bring-back (rc=$rc)"

# --- committed work stays on the branch --------------------------------------------------
bash "$KIT" worktree add ../wt-c >/dev/null 2>&1
W="$TMP/wt-c"
printf 'export const c = 1;\n' > "$W/src/c.js"
git -C "$W" add src/c.js && git -C "$W" commit -qm c
bash "$KIT" worktree diff ../wt-c | grep -q "^diff --git a/src/c.js " && ok "diff: includes commits since the base" || fail "diff misses committed work"
bash "$KIT" worktree remove ../wt-c >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && git show feat/wt-c:src/c.js >/dev/null 2>&1 \
  && ok "remove: committed work is safe on the branch" || fail "remove with commits (rc=$rc)"

# --- guards ------------------------------------------------------------------------------
mkdir -p "$TMP/other" && git -C "$TMP/other" init -q
bash "$KIT" worktree remove "$TMP/other" >/dev/null 2>&1; [ $? != 0 ] && ok "remove: a folder not made by worktree add is refused" || fail "foreign remove"
bash "$KIT" worktree bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown action → exit 2" || fail "unknown action"
(cd "$TMP" && bash "$KIT" worktree list >/dev/null 2>&1); [ $? = 2 ] && ok "outside a git repo → exit 2" || fail "outside a repo"

if [ "$FAILS" -ne 0 ]; then echo "worktree: $FAILS FAILED"; exit 1; fi
echo "worktree: all checks passed"
