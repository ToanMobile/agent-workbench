#!/usr/bin/env bash
# docs/issues-bugs.md A.1b #12 (Neighbours-From-Hell, 2026-10-12): a signing keystore and its key.properties generated IN a worktree are
# git-ignored, so `worktree finish` / the Stop hook's automerge never brought them back and the removal deleted them with the folder (the
# user believed main had "the original keystore"; it never had one). Now (scripts/git/worktree.py), before the folder goes, a git-ignored
# secret-like file (_secret_like) that only the worktree holds is copied to the same path in main: mode kept, at most 0600; main's
# .git/info/exclude gains it when main's own rules do not ignore it; read back byte for byte. The same file in main: dropped. A DIFFERENT
# file at that path in main: the removal is refused, nothing overwritten. `worktree gc` does the same for a leftover folder git no longer knows.
# Each case has a main checkout of its own.
#   1 automerge: keystore/upload.jks (0644) + keystore/key.properties (0640) only in the worktree -> in main, same bytes, 0600, ignored
#   2 main does not ignore the path (the worktree's own self-ignoring signing/.gitignore did): an anchored line in .git/info/exclude
#   3 control: the same file already in main (copied in by `worktree add`): dropped, main's copy untouched
#   4 a DIFFERENT file at that path in main: merged, but the removal is refused, both files intact; once settled, removed
#   5 an untracked key.properties git does NOT ignore is never committed (the merge stops, as for .env)
#   6 control: a secret-like file under a rebuildable folder (node_modules/) and a symlink are not carried, the removal goes on
#   7 gc: a leftover folder (admin dir gone) whose only unique file is a secret -> copied to main, the folder deleted; --dry-run copies nothing
#   8 gc: a different file at that path in main -> the folder is kept, the reason names it, main's file intact
#   11 a deep secret path: every folder the carry creates in main is 0700
#   13 a key under .agents/local/ is carried by finish and by gc; finish carries an ordinary note there too, not one elsewhere
#   12 `worktree remove` / hook-remove refuse a worktree holding an ignored secret main lacks (or holds differently); finish still carries it
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export DEVKIT_LANG=en WORKTREE_GC_MIN_AGE_S=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WTPY="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
mode() { python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"; }

new_main() {   # new_main <name> [ignore lines]: a main checkout of its own
  P="$TMP/$1"; mkdir -p "$P" && G "$P" init -q -b main . || return 1
  printf '%s\n' "${2:-*.jks
key.properties
node_modules/}" > "$P/.gitignore"; echo a > "$P/a.txt"
  G "$P" add -A && G "$P" commit -qm init
}
wt() { (cd "$P" && python3 "$WTPY" add "$1" --no-init >/dev/null 2>&1) || fail "setup: worktree add $1"; }
# finish never commits real work (#366): the plain work of a case (the top-level *.txt files) is committed by hand first; secrets and the
# other files are left as they are, so the checks on them still see what they saw before.
fin() {
  if [ -d "${1:-}" ]; then
    for f in "$1"/*.txt; do [ -f "$f" ] && G "$1" add -- "$(basename "$f")"; done
    G "$1" diff --cached --quiet || G "$1" commit -qm "work by hand"
  fi
  (cd "$P" && python3 "$WTPY" finish "$@" >"$TMP/out" 2>&1); return $?
}
clean_status() { [ -z "$(G "$P" status --porcelain)" ]; }

# 1: the Neighbours case
new_main m1; W="$TMP/sc-a"; wt "$W"
mkdir -p "$W/keystore" && printf 'JKS\0binary\001' > "$W/keystore/upload.jks" && chmod 644 "$W/keystore/upload.jks"
printf 'storePassword=s3cr3t-Passw0rd\nkeyAlias=upload\n' > "$W/keystore/key.properties" && chmod 640 "$W/keystore/key.properties"
echo feat > "$W/feature.txt"; cp "$W/keystore/upload.jks" "$TMP/exp-upload.jks"; cp "$W/keystore/key.properties" "$TMP/exp-key.properties"
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && [ -f "$P/feature.txt" ] && ok "1: the work is merged and the worktree removed" || fail "1: (rc=$rc): $(cat "$TMP/out")"
cmp -s "$TMP/exp-upload.jks" "$P/keystore/upload.jks" && cmp -s "$TMP/exp-key.properties" "$P/keystore/key.properties" \
  && ok "  … its keystore and key.properties are in main, byte for byte" || fail "  … the secrets did not reach main: $(ls -la "$P/keystore" 2>&1)"
[ "$(mode "$P/keystore/upload.jks" 2>/dev/null)" = 0o600 ] && [ "$(mode "$P/keystore/key.properties" 2>/dev/null)" = 0o600 ] && [ "$(mode "$P/keystore" 2>/dev/null)" = 0o700 ] \
  && ok "  … mode 0600 (folder 0700)" || fail "  … modes: $(mode "$P/keystore/upload.jks" 2>&1) $(mode "$P/keystore/key.properties" 2>&1) dir $(mode "$P/keystore" 2>&1)"
clean_status && [ -z "$(G "$P" ls-files keystore)" ] && ok "  … git-ignored in main, never committed" || fail "  … visible to git in main: $(G "$P" status --porcelain)"
grep -q "keystore/upload.jks" "$TMP/out" && ok "  … and the report names them" || fail "  … the report does not name them: $(cat "$TMP/out")"

# 2: main's rules do not ignore it (only the worktree's own self-ignoring signing/.gitignore did)
new_main m2; W="$TMP/sc-b"; wt "$W"
mkdir -p "$W/signing" && echo '*' > "$W/signing/.gitignore" && echo "KEYSTORE" > "$W/signing/upload.keystore"; echo b > "$W/b.txt"
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && [ "$(cat "$P/signing/upload.keystore" 2>/dev/null)" = KEYSTORE ] && ok "2: a secret main does not ignore yet reaches main" \
  || fail "2: (rc=$rc): $(cat "$TMP/out")"
grep -qx '/signing/upload.keystore' "$P/.git/info/exclude" 2>/dev/null && clean_status && [ ! -e "$P/signing/.gitignore" ] \
  && ok "  … with an anchored line in .git/info/exclude (git status clean; the worktree's .gitignore is not carried)" \
  || fail "  … exclude: $(cat "$P/.git/info/exclude" 2>&1) / status: $(G "$P" status --porcelain)"

# 3: control: main already has the very same file (worktree add copied it in): dropped, main's copy untouched
new_main m3; mkdir -p "$P/keystore" && echo "SAME" > "$P/keystore/upload.jks" && chmod 600 "$P/keystore/upload.jks"
INO3="$(python3 -c 'import os,sys;s=os.stat(sys.argv[1]);print(s.st_ino,s.st_mtime_ns)' "$P/keystore/upload.jks")"
W="$TMP/sc-c"; wt "$W"; echo c > "$W/c.txt"
[ "$(cat "$W/keystore/upload.jks" 2>/dev/null)" = SAME ] || fail "setup 3: worktree add did not copy main's keystore in"
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && [ "$INO3" = "$(python3 -c 'import os,sys;s=os.stat(sys.argv[1]);print(s.st_ino,s.st_mtime_ns)' "$P/keystore/upload.jks")" ] \
  && ok "3: the same file already in main: dropped, main's copy untouched" || fail "3: (rc=$rc): $(cat "$TMP/out")"

# 4: a DIFFERENT file at that path in main: never overwritten, the removal refused
new_main m4; mkdir -p "$P/keystore" && echo "MAIN-KEY" > "$P/keystore/upload.jks"
W="$TMP/sc-d"; wt "$W"; echo "WORKTREE-KEY" > "$W/keystore/upload.jks"; echo d > "$W/d.txt"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ -d "$W" ] && [ "$(cat "$W/keystore/upload.jks")" = WORKTREE-KEY ] && [ "$(cat "$P/keystore/upload.jks")" = MAIN-KEY ] \
  && ok "4: a different file in main: the removal is refused (exit 1), both files intact" || fail "4: (rc=$rc, exists=$([ -d "$W" ] && echo y || echo n)): $(cat "$TMP/out")"
grep -q "keystore/upload.jks" "$TMP/out" && [ -f "$P/d.txt" ] && ok "  … the work is merged, the reason names the file" || fail "  … $(cat "$TMP/out")"
if [ -d "$W" ]; then
  rm -f "$W/keystore/upload.jks"   # settled: the worktree's key was not needed
  fin "$W"; rc=$?; [ "$rc" = 0 ] && [ ! -d "$W" ] && [ "$(cat "$P/keystore/upload.jks")" = MAIN-KEY ] && ok "  … once settled, the next finish removes it" || fail "  … retry (rc=$rc): $(cat "$TMP/out")"
fi

# 5: an untracked key.properties that git does NOT ignore: never committed
new_main m5 '*.jks'; W="$TMP/sc-e"; wt "$W"
mkdir -p "$W/android" && printf 'storePassword=s3cr3t-Passw0rd\n' > "$W/android/key.properties"; echo e > "$W/e.txt"; G "$W" add e.txt && G "$W" commit -qm "e by hand"   # (so the worktree's HEAD is the same before and after fin)
H5="$(G "$P" rev-parse HEAD)"; WH5="$(G "$W" rev-parse HEAD)"
fin "$W"; rc=$?
[ "$rc" = 1 ] && grep -q "android/key.properties" "$TMP/out" && [ "$(G "$P" rev-parse HEAD)" = "$H5" ] && [ "$(G "$W" rev-parse HEAD 2>&1)" = "$WH5" ] \
  && [ -z "$(G "$P" ls-files android/key.properties)" ] && ok "5: an untracked, unignored key.properties stops the merge, nothing committed" \
  || fail "5: (rc=$rc): $(cat "$TMP/out") / main tracks: $(G "$P" ls-files android)"

# 6: control: a secret-like file under a rebuildable folder and a symlink are not carried
new_main m6; W="$TMP/sc-f"; wt "$W"
mkdir -p "$W/node_modules/x" "$W/keystore" && echo pem > "$W/node_modules/x/test.pem" && echo k > "$TMP/elsewhere.jks" && ln -s "$TMP/elsewhere.jks" "$W/keystore/link.jks"
echo f > "$W/f.txt"
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && [ ! -e "$P/node_modules" ] && [ ! -e "$P/keystore/link.jks" ] && [ ! -L "$P/keystore/link.jks" ] \
  && ok "6: node_modules/x/test.pem and a symlinked .jks are not carried; the worktree is removed" || fail "6: (rc=$rc): $(cat "$TMP/out") / $(ls -la "$P")"

# 7: gc: a leftover folder (its admin dir is gone) whose only unique file is a secret
new_main g7; O="$TMP/g7-orphan"; G "$P" worktree add -q --detach "$O" && rm -rf "$P/.git/worktrees/g7-orphan"
mkdir -p "$O/keystore" && echo "ORPHAN-ONLY" > "$O/keystore/only.jks" && chmod 640 "$O/keystore/only.jks"
(cd "$P" && python3 "$WTPY" gc --dry-run) > "$TMP/gc.out" 2>&1
[ -d "$O" ] && [ ! -e "$P/keystore/only.jks" ] && ok "7: gc --dry-run deletes and copies nothing" || fail "7: dry-run touched something: $(cat "$TMP/gc.out")"
grep -q "would copy into main first" "$TMP/gc.out" && ! grep -q "copied into main first" "$TMP/gc.out" \
  && ok "  … and its report says would copy (a user must not delete the folder believing the key is already in main)" || fail "  … dry-run wording: $(cat "$TMP/gc.out")"
(cd "$P" && python3 "$WTPY" gc --log="$TMP/gc.log") > "$TMP/gc.out" 2>&1
[ "$(cat "$P/keystore/only.jks" 2>/dev/null)" = ORPHAN-ONLY ] && [ "$(mode "$P/keystore/only.jks" 2>/dev/null)" = 0o600 ] && clean_status \
  && ok "  … gc copies the secret into main (0600, ignored)" || fail "  … not in main: $(cat "$TMP/gc.out")"
[ ! -d "$O" ] && grep -q "keystore/only.jks" "$TMP/gc.log" 2>/dev/null && ok "  … then deletes the folder, and the log records the copy" \
  || fail "  … folder exists=$([ -d "$O" ] && echo y || echo n), log: $(cat "$TMP/gc.log" 2>&1) / $(cat "$TMP/gc.out")"

# 8: gc: a different file at that path in main: kept, named, main's file intact
new_main g8; mkdir -p "$P/keystore" && echo "MAIN" > "$P/keystore/dup.jks"
O="$TMP/g8-orphan"; G "$P" worktree add -q --detach "$O" && rm -rf "$P/.git/worktrees/g8-orphan"
mkdir -p "$O/keystore" && echo "ORPHAN" > "$O/keystore/dup.jks"
(cd "$P" && python3 "$WTPY" gc) > "$TMP/gc.out" 2>&1
[ -d "$O" ] && [ "$(cat "$P/keystore/dup.jks")" = MAIN ] && grep -q "g8-orphan.*keystore/dup.jks" "$TMP/gc.out" \
  && ok "8: gc keeps a folder whose secret differs from main's, names it, main's file intact" || fail "8: $(cat "$TMP/gc.out")"

# 9 (OpenCodeReview): the scan of the ignored folders stops at WORKTREE_SECRET_SCAN_MAX files; what it did not read may hold a key, so
#   the worktree is KEPT (merged, not removed) and the message says which folder and what to do
new_main m9 '*.jks
cache-data/'; W="$TMP/sc-i"; wt "$W"; mkdir -p "$W/cache-data"
for n in 1 2 3 4 5 6 7 8; do echo "$n" > "$W/cache-data/f$n.bin"; done; echo k > "$W/cache-data/late.jks"; echo i > "$W/i.txt"
WORKTREE_SECRET_SCAN_MAX=4 fin "$W"; rc=$?
[ "$rc" = 1 ] && [ -d "$W" ] && [ -f "$P/i.txt" ] && grep -q "cache-data" "$TMP/out" && grep -q "WORKTREE_SECRET_SCAN_MAX" "$TMP/out" \
  && ok "9: a scan cut short keeps the worktree (merged, not removed), naming the folder and the knob" || fail "9: (rc=$rc, exists=$([ -d "$W" ] && echo y || echo n)): $(cat "$TMP/out")"
if [ -d "$W" ]; then
  fin "$W"; rc=$?   # the default cap reads it all: the key is carried, the worktree removed
  [ "$rc" = 0 ] && [ ! -d "$W" ] && [ "$(cat "$P/cache-data/late.jks" 2>/dev/null)" = k ] && ok "  … read in full, the key reaches main and the worktree goes" || fail "  … (rc=$rc): $(cat "$TMP/out")"
fi

# 10 (OpenCodeReview): gc judges a name only _secret_like knows (not GC_SECRETS) as before: a package's fixture under node_modules/
#    (ignored, rebuildable) and a committed fixture main has changed since (its content is in a kept commit) are not unique
new_main g10 'node_modules/'; mkdir -p "$P/fixtures" && echo "v1" > "$P/fixtures/credentials-test.json" && G "$P" add fixtures && G "$P" commit -qm fixture
echo "v2" > "$P/fixtures/credentials-test.json" && G "$P" commit -qam "fixture v2"
O="$TMP/g10-orphan"; G "$P" worktree add -q --detach "$O" && rm -rf "$P/.git/worktrees/g10-orphan"
mkdir -p "$O/node_modules/pkg/test" && echo '{"type":"x"}' > "$O/node_modules/pkg/test/credentials-ci.json" && echo "v1" > "$O/fixtures/credentials-test.json"
(cd "$P" && python3 "$WTPY" gc) > "$TMP/gc.out" 2>&1
[ ! -d "$O" ] && [ ! -e "$P/node_modules" ] && [ "$(cat "$P/fixtures/credentials-test.json")" = v2 ] \
  && ok "10: gc deletes an orphan whose only such files are a node_modules fixture and a committed fixture (nothing copied into main)" \
  || fail "10: kept or copied: $(cat "$TMP/gc.out")"

# 11 (OpenCodeReview A1): the secret's path needs SEVERAL new folders in main (no android/ there): every folder the carry creates is 0700, not only the
#     last one (os.makedirs applies its mode to the leaf; the parents got 0777 & ~umask, world-listable)
new_main m11; W="$TMP/sc-k"; wt "$W"
mkdir -p "$W/android/app/keystore" && echo "DEEP" > "$W/android/app/keystore/upload.jks"; echo k > "$W/k.txt"
(umask 022; fin "$W"); rc=$?
[ "$rc" = 0 ] && [ "$(cat "$P/android/app/keystore/upload.jks" 2>/dev/null)" = DEEP ] && ok "11: a deep secret path is carried" || fail "11: (rc=$rc): $(cat "$TMP/out")"
[ "$(mode "$P/android")" = 0o700 ] && [ "$(mode "$P/android/app")" = 0o700 ] && [ "$(mode "$P/android/app/keystore")" = 0o700 ] \
  && ok "  … and every new folder on the way is 0700 (umask 022)" || fail "  … modes: android $(mode "$P/android" 2>&1) app $(mode "$P/android/app" 2>&1) keystore $(mode "$P/android/app/keystore" 2>&1)"

# 12 (principal review A1): the removal itself - `worktree remove` and the WorktreeRemove hook (ExitWorktree "remove", a finished isolated
#     subagent) both end in cmd_remove, which only the automerge and gc paths had taught about git-ignored secrets: an ignored keystore only the
#     worktree holds went with the folder, rc 0. It is a blocker now, like an uncommitted change: nothing removed, the file named, `finish` advised
rem() { (cd "$P" && python3 "$WTPY" remove "$@" >"$TMP/out" 2>&1); return $?; }
hookrem() { printf '{"worktree_path":"%s"}' "$1" | (cd / && python3 -I "$WTPY" hook-remove >"$TMP/out" 2>&1); return $?; }
new_main m12; W="$TMP/sc-l"; wt "$W"; mkdir -p "$W/android/app" && echo "ONLY-HERE" > "$W/android/app/upload.jks"
rem "$W"; rc=$?
[ "$rc" != 0 ] && [ -d "$W" ] && [ "$(cat "$W/android/app/upload.jks" 2>/dev/null)" = ONLY-HERE ] && grep -q "android/app/upload.jks" "$TMP/out" && grep -q "worktree finish" "$TMP/out" \
  && ok "12: worktree remove refuses a worktree holding an ignored keystore main lacks: kept, the file named, finish advised" \
  || fail "12: (rc=$rc, exists=$([ -d "$W" ] && echo y || echo n)): $(cat "$TMP/out")"
hookrem "$W"; rc=$?
[ "$rc" != 0 ] && [ -f "$W/android/app/upload.jks" ] && ok "  … the WorktreeRemove hook refuses it too (Claude keeps the worktree, the Stop hook's merge carries the key)" \
  || fail "  … hook-remove (rc=$rc): $(cat "$TMP/out")"
echo "OTHER" > "$P/android/app/upload.jks" 2>/dev/null || { mkdir -p "$P/android/app" && echo "OTHER" > "$P/android/app/upload.jks"; }
rem "$W"; rc=$?
[ "$rc" != 0 ] && [ -d "$W" ] && ok "  … a DIFFERENT file at that path in main refuses it as well" || fail "  … different file in main (rc=$rc): $(cat "$TMP/out")"
echo "ONLY-HERE" > "$P/android/app/upload.jks"
rem "$W"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && ok "  … main holding the very same bytes: the removal goes through" || fail "  … same bytes in main (rc=$rc): $(cat "$TMP/out")"
new_main m12b; W="$TMP/sc-m"; wt "$W"; mkdir -p "$W/android/app" && echo "FINISHED" > "$W/android/app/upload.jks"
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && [ "$(cat "$P/android/app/upload.jks" 2>/dev/null)" = FINISHED ] && ok "  … finish still carries it and removes the worktree (the blocker does not stand in its way)" \
  || fail "  … finish (rc=$rc): $(cat "$TMP/out")"

# 13 (principal review A1): .agents/ is not a rebuildable folder - .agents/local/ is where the kit keeps long-lived files - so a key there is
#     carried like any other (the skip list was build_inputs.SKIP_WALK, which also names .agents, .claude, .idea, Logs): automerge and gc agree.
#     OCR r2 (26/10): an ordinary ignored note under .agents/local/ is the kit's long-lived work too: finish carries it as well (before, it
#     went with the folder); the secret NAME filter still holds for an ordinary ignored file anywhere else (build/out.txt: not copied)
new_main m13 '*.jks
.agents/local/
build/'; W="$TMP/sc-n"; wt "$W"
mkdir -p "$W/.agents/local/signing" "$W/build" && echo "SIGN" > "$W/.agents/local/signing/release.jks" && echo "just a note" > "$W/.agents/local/notes.txt"
echo "built" > "$W/build/out.txt"; echo n > "$W/n.txt"
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && [ "$(cat "$P/.agents/local/signing/release.jks" 2>/dev/null)" = SIGN ] && ok "13: .agents/local/signing/release.jks is carried into main by finish" \
  || fail "13: (rc=$rc, exists=$([ -d "$W" ] && echo y || echo n)): $(cat "$TMP/out") / main: $(ls -R "$P/.agents" 2>&1 | head -5)"
[ "$(cat "$P/.agents/local/notes.txt" 2>/dev/null)" = "just a note" ] && ok "  … an ordinary ignored note under .agents/local/ is carried too (no longer lost)" || fail "  … notes.txt was not carried into main"
[ ! -e "$P/build/out.txt" ] && ok "  … an ordinary ignored file elsewhere is not copied (the name filter stays)" || fail "  … build/out.txt was copied into main"
new_main g13 '*.jks
.agents/local/'; O="$TMP/g13-orphan"; G "$P" worktree add -q --detach "$O" && rm -rf "$P/.git/worktrees/g13-orphan"
mkdir -p "$O/.agents/local/signing" && echo "ORPHAN-SIGN" > "$O/.agents/local/signing/rel.jks"
(cd "$P" && python3 "$WTPY" gc) > "$TMP/gc.out" 2>&1
[ ! -d "$O" ] && [ "$(cat "$P/.agents/local/signing/rel.jks" 2>/dev/null)" = ORPHAN-SIGN ] && ok "  … and gc carries the same file, then deletes the folder (it kept it as unique before)" \
  || fail "  … gc (exists=$([ -d "$O" ] && echo y || echo n)): $(cat "$TMP/gc.out")"

# 14 (principal review A1): a config `worktree add` copied in is main's copy, not a key made in the worktree. Main deleting a revoked .env (or
#     editing it) after the add must not bring the old bytes back / strand the worktree: `add` records a sha256 of each secret-like file it copied
#     (state: copied_sha) and a file whose bytes still equal it is neither carried nor a blocker. A worktree without the field keeps the old rule.
new_main m14 '.env
*.jks'; echo "API_KEY=old-revoked" > "$P/.env"; W="$TMP/sc-o"; wt "$W"; echo o > "$W/o.txt"
[ "$(cat "$W/.env" 2>/dev/null)" = "API_KEY=old-revoked" ] || fail "setup 14: worktree add did not copy main's .env in"
rm "$P/.env"   # main revoked and deleted it after the add
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && [ ! -e "$P/.env" ] && ok "14: main deleted .env after the add: the stale copy is not carried back, the worktree is removed" \
  || fail "14: (rc=$rc, exists=$([ -d "$W" ] && echo y || echo n), main's .env: $(cat "$P/.env" 2>&1)): $(cat "$TMP/out")"
new_main m14b '.env
*.jks'; echo "API_KEY=v1" > "$P/.env"; W="$TMP/sc-p"; wt "$W"; echo p > "$W/p.txt"
echo "API_KEY=v2-rotated" > "$P/.env"   # main rotated it after the add: other bytes in main
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && [ "$(cat "$P/.env")" = "API_KEY=v2-rotated" ] && ok "  … main edited .env after the add: not refused as 'different', main's edit untouched, the worktree is removed" \
  || fail "  … (rc=$rc, exists=$([ -d "$W" ] && echo y || echo n)): $(cat "$TMP/out")"
new_main m14c '.env
*.jks'; echo "API_KEY=v1" > "$P/.env"; W="$TMP/sc-q"; wt "$W"; echo q > "$W/q.txt"
echo "API_KEY=made-in-the-worktree" > "$W/.env"; rm "$P/.env"   # the worktree changed it: its bytes no longer equal the copy, so it is a key made here
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$W" ] && [ "$(cat "$P/.env" 2>/dev/null)" = "API_KEY=made-in-the-worktree" ] && ok "  … a .env the worktree CHANGED is still carried (control)" \
  || fail "  … control (rc=$rc): $(cat "$TMP/out")"
new_main m14d '.env
*.jks'; echo "API_KEY=old-revoked" > "$P/.env"; W="$TMP/sc-r"; wt "$W"; echo r > "$W/r.txt"
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d.pop("copied_sha", None); json.dump(d, open(f, "w"))' "$(G "$W" rev-parse --absolute-git-dir)/devkit-worktree.json"
rm "$P/.env"
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$P/.env" 2>/dev/null)" = "API_KEY=old-revoked" ] && ok "  … a worktree whose state has no copied_sha keeps the old rule (carried back)" || fail "  … legacy state (rc=$rc): $(cat "$TMP/out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_secret_carry: all passed" || { echo "❌ test_worktree_secret_carry: $FAILS failed"; exit 1; }
