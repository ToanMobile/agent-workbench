#!/usr/bin/env bash
# Regression test: `agent-kit worktree` — a worktree set up like the main checkout
# (ignored local config copied, DevKit installed with the same profile), a diff that
# carries the agent's work but not the DevKit setup and applies to the main checkout,
# and a remove that refuses while uncommitted work would be lost. A worktree is DETACHED unless a branch is
# named (one developer, one branch: the project rule). Its Claude auto-memory stays its OWN folder unless `--share-memory` is given.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

M="$TMP/main"
mkdir -p "$M/src" "$M/app" "$M/.agents/local/memory/claude-auto"   # a project that has used Claude auto-memory: the folder exists
cd "$M" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
git config core.excludesFile /dev/null   # not the user's global ignore: Claude Code adds .claude/settings.local.json to it, which would hide it from the fresh-worktree diff check below
printf '{"name":"x","scripts":{"test":"node -e 0"}}\n' > package.json
printf 'export const a = 1;\n' > src/a.js
printf 'export const gone = 1;\n' > src/gone.js
printf 'node_modules\n.env\napp/google-services.json\nCarConnect/app/libs/\nCarConnect/keys/\nCarConnect/app/src/main/assets/overlay/\n.agents/local/\n' > .gitignore
git add -A && git commit -qm init
echo "API_KEY=local" > .env && echo '{"k":1}' > app/google-services.json
# Ignored build inputs red_proof.py already knows (DEFAULT_INPUTS: **/libs/*.aar, **/*.jks) and
# the project's own list (.agents/local/red_proof.json "copy") — GeelyEx2, 2026-09-24.
mkdir -p CarConnect/app/libs CarConnect/keys/release CarConnect/app/src/main/assets/overlay/fonts .agents/local stray/libs
printf 'AAR' > CarConnect/app/libs/vendor-sdk.aar
printf 'JKS' > CarConnect/keys/release/app.jks
printf 'alias=x\n' > CarConnect/keys/signing.txt
printf 'FNT' > CarConnect/app/src/main/assets/overlay/fonts/a.ttf
printf '{"copy": ["CarConnect/keys/**", "CarConnect/app/src/main/assets/overlay/**"]}\n' > .agents/local/red_proof.json
printf 'NOT-IGNORED' > stray/libs/loose.aar     # matches a pattern but is NOT ignored: never copied
bash "$KIT" init "$M" -y -a claude -p web --no-githooks >/dev/null 2>&1 || { echo "cannot install into the main checkout"; exit 1; }
main_status="$(git status --porcelain)"
heads_before="$(git for-each-ref --format='%(refname)' refs/heads)"

# --- add ------------------------------------------------------------------------------
out="$(bash "$KIT" worktree add ../wt-a 2>&1)"; rc=$?
W="$TMP/wt-a"
[ "$rc" = 0 ] && [ -z "$(git -C "$W" branch --show-current)" ] && [ "$(git for-each-ref --format='%(refname)' refs/heads)" = "$heads_before" ] \
  && ok "add: no branch named -> a DETACHED worktree, no branch created" || { fail "add (rc=$rc): branch='$(git -C "$W" branch --show-current)'"; echo "$out"; }
mem_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("autoMemoryDirectory", ""))' "$1/.claude/settings.local.json" 2>/dev/null; }
own_mem() { printf '%s' "$(cd "$1" && pwd -P)/.agents/local/memory/claude-auto"; }   # the folder the installer gives a checkout
# default: NOT shared (several agents writing at once would overwrite ONE MEMORY.md, and what one saves would reach every later session)
[ -n "$(mem_of "$M")" ] && [ "$(mem_of "$W")" != "$(mem_of "$M")" ] && [ "$(mem_of "$W")" = "$(own_mem "$W")" ] \
  && ok "add: by default the worktree's Claude auto-memory stays its OWN folder (not the main checkout's)" \
  || fail "default worktree memory dir '$(mem_of "$W")' (main's '$(mem_of "$M")', own '$(own_mem "$W")')"
printf '%s' "$out" | grep -qi "auto-memory shared" && fail "add: the default run claims shared memory" || ok "add: the default run does not claim shared memory"
# --share-memory: the old expectation, under the flag
out_m="$(bash "$KIT" worktree add ../wt-m --share-memory 2>&1)"; rc_m=$?
[ "$rc_m" = 0 ] && [ -n "$(mem_of "$M")" ] && [ "$(mem_of "$TMP/wt-m")" = "$(mem_of "$M")" ] \
  && ok "add --share-memory: the worktree's Claude auto-memory is the main checkout's (autoMemoryDirectory)" \
  || fail "--share-memory (rc=$rc_m): worktree memory dir '$(mem_of "$TMP/wt-m")' is not the main checkout's '$(mem_of "$M")'"
printf '%s' "$out_m" | grep -qi "auto-memory shared" && ok "add --share-memory: the shared memory is reported" || fail "--share-memory not reported: $out_m"
bash "$KIT" worktree remove ../wt-m >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/wt-m" ] && [ -d "$M/.agents/local/memory/claude-auto" ] && ok "remove: a worktree that shared the memory goes; the main checkout's folder stays" || fail "remove of the --share-memory worktree (rc=$rc)"
# --share-memory but the main checkout has no folder of its own: nothing to share, the worktree keeps its own, and says so
mv "$M/.agents/local/memory/claude-auto" "$TMP/claude-auto-away"
out_n="$(bash "$KIT" worktree add ../wt-n --share-memory 2>&1)"; rc_n=$?
mv "$TMP/claude-auto-away" "$M/.agents/local/memory/claude-auto"
[ "$rc_n" = 0 ] && [ "$(mem_of "$TMP/wt-n")" = "$(own_mem "$TMP/wt-n")" ] && printf '%s' "$out_n" | grep -qi "not shared" \
  && ok "add --share-memory: no claude-auto/ folder in the main checkout -> left alone, the output says not shared" || fail "--share-memory without a main folder (rc=$rc_n): '$(mem_of "$TMP/wt-n")' / $out_n"
bash "$KIT" worktree remove ../wt-n >/dev/null 2>&1
bash "$KIT" worktree add ../wt-x --bogus-flag >/dev/null 2>&1; [ $? = 2 ] && ok "add: an unknown option is still refused" || fail "unknown add option accepted"
grep -q -e "--share-memory" "$DEVKIT_DIR/completions/agent-kit.bash" && ok "completion: worktree add offers --share-memory" || fail "bash completion lacks --share-memory"
# a note saved in the worktree's OWN claude-auto folder goes with it: remove WARNS (it does not refuse) when main's folder lacks it
bash "$KIT" worktree add ../wt-w >/dev/null 2>&1; WW="$TMP/wt-w"; mkdir -p "$WW/.agents/local/memory/claude-auto"
printf 'lesson\n' > "$WW/.agents/local/memory/claude-auto/note.md"
out_w="$(bash "$KIT" worktree remove ../wt-w 2>&1)"; rc_w=$?
[ "$rc_w" = 0 ] && [ ! -e "$WW" ] && printf '%s' "$out_w" | grep -q "1 memory note" && printf '%s' "$out_w" | grep -q "share-memory" && printf '%s' "$out_w" | grep -q "claude-auto" \
  && ok "remove: a note only in the worktree's own claude-auto folder -> WARNING (count + both cures), the worktree is still removed" || fail "memory note warning (rc=$rc_w): $out_w"
bash "$KIT" worktree add ../wt-w2 >/dev/null 2>&1; WW="$TMP/wt-w2"; mkdir -p "$WW/.agents/local/memory/claude-auto"
printf 'lesson\n' > "$WW/.agents/local/memory/claude-auto/note.md"; cp "$WW/.agents/local/memory/claude-auto/note.md" "$M/.agents/local/memory/claude-auto/note.md"
out_w="$(bash "$KIT" worktree remove ../wt-w2 2>&1)"; rc_w=$?
[ "$rc_w" = 0 ] && ! printf '%s' "$out_w" | grep -qi "memory note" && ok "remove: the same note already in the main checkout's folder -> no warning" || fail "warned about a note main has (rc=$rc_w): $out_w"
rm -f "$M/.agents/local/memory/claude-auto/note.md"
bash "$KIT" worktree add ../wt-w4 >/dev/null 2>&1; WW="$TMP/wt-w4"; mkdir -p "$WW/.agents/local/memory/claude-auto"
printf 'main version\n' > "$M/.agents/local/memory/claude-auto/MEMORY.md"; printf 'worktree version, edited\n' > "$WW/.agents/local/memory/claude-auto/MEMORY.md"
out_w="$(bash "$KIT" worktree remove ../wt-w4 2>&1)"; rc_w=$?
[ "$rc_w" = 0 ] && printf '%s' "$out_w" | grep -q "1 memory note" && ok "remove: a note of the same name with OTHER bytes in main is also warned about" || fail "edited note not warned (rc=$rc_w): $out_w"
rm -f "$M/.agents/local/memory/claude-auto/MEMORY.md"
bash "$KIT" worktree add ../wt-w3 --share-memory >/dev/null 2>&1
out_w="$(bash "$KIT" worktree remove ../wt-w3 2>&1)"; rc_w=$?
[ "$rc_w" = 0 ] && ! printf '%s' "$out_w" | grep -qi "memory note" && ok "remove: a --share-memory worktree -> no warning (its notes are in main's folder)" || fail "warned for a shared-memory worktree (rc=$rc_w): $out_w"
[ "$(cat "$W/.env" 2>/dev/null)" = "API_KEY=local" ] && [ -f "$W/app/google-services.json" ] \
  && ok "add: git-ignored local config copied (.env, app/google-services.json)" || fail "local config not copied"
missing=""
for f in CarConnect/app/libs/vendor-sdk.aar CarConnect/keys/release/app.jks CarConnect/keys/signing.txt \
         CarConnect/app/src/main/assets/overlay/fonts/a.ttf; do
  cmp -s "$M/$f" "$W/$f" || missing="$missing $f"
done
[ -z "$missing" ] && ok "add: ignored build inputs copied (red_proof defaults + .agents/local/red_proof.json)" \
  || fail "build inputs not copied:$missing"
[ ! -e "$W/stray/libs/loose.aar" ] && ok "add: a matching file git does NOT ignore is not copied" || fail "non-ignored file copied"
printf '%s' "$out" | grep -q "CarConnect/app/libs/vendor-sdk.aar" && ok "add: copied build inputs are listed" \
  || fail "copied build inputs not reported"
[ -z "$(git -C "$W" status --porcelain --ignored=no -- CarConnect)" ] && ok "add: copied build inputs stay ignored (never committed)" \
  || fail "copied build inputs show up in git status"
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
[ "$rc" = 0 ] && [ ! -e "$W" ] && [ "$(git for-each-ref --format='%(refname)' refs/heads)" = "$heads_before" ] \
  && ok "remove: setup-only worktree removed, no branch left behind" || fail "remove of a fresh worktree (rc=$rc)"

# --- work in a worktree ------------------------------------------------------------------
bash "$KIT" worktree add ../wt-b fix/b >/dev/null 2>&1 || fail "add wt-b"
W="$TMP/wt-b"
[ "$(git -C "$W" branch --show-current)" = "fix/b" ] && ok "add: an explicit branch argument still gives that branch" || fail "explicit branch not used"
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

# --- committed work: on a named branch it stays there; on a detached worktree it is brought back first ---------
bash "$KIT" worktree add ../wt-c >/dev/null 2>&1
W="$TMP/wt-c"
printf 'export const c = 1;\n' > "$W/src/c.js"
git -C "$W" add src/c.js && git -C "$W" commit -qm c
bash "$KIT" worktree diff ../wt-c | grep -q "^diff --git a/src/c.js " && ok "diff: includes commits since the base" || fail "diff misses committed work"
bash "$KIT" worktree remove ../wt-c >"$TMP/rm.out" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$W" ] && grep -q "UNREACHABLE" "$TMP/rm.out" && ! grep -q "switch -c" "$TMP/rm.out" \
  && ok "remove: a detached worktree's commits are on no branch -> refused, and the advice is not a new branch (the git guard blocks those)" \
  || { fail "remove of a detached worktree with commits (rc=$rc)"; cat "$TMP/rm.out"; }
bash "$KIT" worktree diff ../wt-c | git apply --3way >/dev/null 2>&1 && git add src/c.js && git commit -qm "c, brought back" \
  && bash "$KIT" worktree remove ../wt-c >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$W" ] && git show HEAD:src/c.js >/dev/null 2>&1 \
  && ok "remove: allowed once the commits' content is committed in main" || fail "remove after bring-back (rc=$rc)"
bash "$KIT" worktree add ../wt-d feat/d >/dev/null 2>&1
W="$TMP/wt-d"
printf 'export const d = 1;\n' > "$W/src/d.js"
git -C "$W" add src/d.js && git -C "$W" commit -qm d
bash "$KIT" worktree remove ../wt-d >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && git show feat/d:src/d.js >/dev/null 2>&1 \
  && ok "remove: committed work on a NAMED branch is safe on the branch" || fail "remove with commits on a branch (rc=$rc)"

# --- auto-memory: only the installer's own default (the worktree's empty folder) is repointed ----------------
python3 - "$DEVKIT_DIR/scripts/git" "$TMP" >"$TMP/mem.out" 2>&1 <<'PY'
import json, os, subprocess, sys
sys.path.insert(0, sys.argv[1])
import worktree as w
root = os.path.join(sys.argv[2], "mem"); os.makedirs(root)
def repo(name, ignore_local=True):
    d = os.path.join(root, name); os.makedirs(os.path.join(d, ".claude"))
    subprocess.run(["git", "init", "-q", d], check=True)
    subprocess.run(["git", "-C", d, "config", "core.excludesFile", os.devnull], check=True)   # not the user's global ignore (Claude Code adds settings.local.json to it)
    if ignore_local:
        open(os.path.join(d, ".gitignore"), "w").write(".claude/settings.local.json\n")
    return d
def put(d, data, raw=None):
    open(os.path.join(d, ".claude", "settings.local.json"), "w").write(raw if raw is not None else json.dumps(data))
def get(d):
    p = os.path.join(d, ".claude", "settings.local.json")
    return json.load(open(p)) if os.path.exists(p) else None
rel = os.path.join(".agents", "local", "memory", "claude-auto")
main = repo("main"); target = os.path.join(os.path.realpath(main), rel); put(main, {"autoMemoryDirectory": target}); os.makedirs(target)
ok = []
def check(name, cond): ok.append((name, bool(cond)))

wt = repo("wt1"); put(wt, {"autoMemoryDirectory": os.path.join(os.path.realpath(wt), rel), "keep": 1})
changed = w.share_main_memory(main, wt)
check("the worktree's own default is replaced by the main checkout's folder, other keys kept", changed is True and get(wt) == {"autoMemoryDirectory": target, "keep": 1})
check("running it again changes nothing", w.share_main_memory(main, wt) is False and get(wt)["autoMemoryDirectory"] == target)
wt = repo("wt2"); put(wt, {"autoMemoryDirectory": "/custom/mine"})
check("a custom autoMemoryDirectory of the user's is kept", w.share_main_memory(main, wt) is False and get(wt) == {"autoMemoryDirectory": "/custom/mine"})
wt = repo("wt3"); put(wt, {"autoMemoryDirectory": os.path.join(os.path.realpath(wt), rel)})
other = repo("main-without"); put(other, {"theme": "x"})
check("the main checkout has no autoMemoryDirectory: nothing to share", w.share_main_memory(other, wt) is False and get(wt)["autoMemoryDirectory"].startswith(os.path.realpath(wt)))
put(other, {"autoMemoryDirectory": "relative/dir"})
check("a relative path in the main checkout is not shared", w.share_main_memory(other, wt) is False)
wt = repo("wt4"); put(wt, None, raw="{not json")
check("an unreadable settings file is left alone", w.share_main_memory(main, wt) is False and open(os.path.join(wt, ".claude", "settings.local.json")).read() == "{not json")
wt = repo("wt5", ignore_local=True)
check("no settings file and the name is git-ignored: created, memory shared", w.share_main_memory(main, wt) is True and get(wt) == {"autoMemoryDirectory": target})
wt = repo("wt6", ignore_local=False)
check("no settings file and the name is NOT git-ignored: not created (one git add from a commit)", w.share_main_memory(main, wt) is False and get(wt) is None)
# the target must BE the main checkout's claude-auto/ folder (no traversal, no folder of someone else) and exist
for label, value, make in (("a folder outside the main checkout", "/elsewhere/memory", False),
                           ("a path that climbs out of claude-auto/ with ..", os.path.join(target, "..", "..", "x"), False)):
    m2 = repo("main-" + label.split()[1]); put(m2, {"autoMemoryDirectory": value})
    wt = repo("wtx-" + label.split()[1]); put(wt, {"autoMemoryDirectory": os.path.join(os.path.realpath(wt), rel)})
    check("main's autoMemoryDirectory is " + label + ": not shared", w.share_main_memory(m2, wt) is False and get(wt)["autoMemoryDirectory"].startswith(os.path.realpath(wt)))
m3 = repo("main-nodir"); put(m3, {"autoMemoryDirectory": os.path.join(os.path.realpath(m3), rel)})
wt = repo("wt-nodir"); put(wt, {"autoMemoryDirectory": os.path.join(os.path.realpath(wt), rel)})
check("main's claude-auto/ folder does not exist (yet): nothing to share", w.share_main_memory(m3, wt) is False)
for name, good in ok:
    print(("PASS " if good else "FAIL ") + name)
sys.exit(0 if all(g for _, g in ok) else 1)
PY
mem_rc=$?
while IFS= read -r l; do case "$l" in PASS*) ok "memory: ${l#PASS }" ;; FAIL*) fail "memory: ${l#FAIL }" ;; *) echo "$l" ;; esac; done < "$TMP/mem.out"
[ "$mem_rc" = 0 ] || fail "memory sharing checks exited $mem_rc"

# --- guards ------------------------------------------------------------------------------
mkdir -p "$TMP/other" && git -C "$TMP/other" init -q
bash "$KIT" worktree remove "$TMP/other" >/dev/null 2>&1; [ $? != 0 ] && ok "remove: a folder not made by worktree add is refused" || fail "foreign remove"
bash "$KIT" worktree bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown action → exit 2" || fail "unknown action"
(cd "$TMP" && bash "$KIT" worktree list >/dev/null 2>&1); [ $? = 2 ] && ok "outside a git repo → exit 2" || fail "outside a repo"

if [ "$FAILS" -ne 0 ]; then echo "worktree: $FAILS FAILED"; exit 1; fi
echo "worktree: all checks passed"
