#!/usr/bin/env bash
# Regression test: hooks/session_context.sh (SessionStart) runs its network fetch only when it can matter.
# The SessionStart payload carries "source": startup | resume | clear | compact (| fork). A new session always
# fetches. A resumed, cleared or compacted one skips the fetch ONLY while the last fetch is recent (FETCH_HEAD
# younger than SESSION_FETCH_MAX_AGE_S, default 1800 s) and reports ahead/behind from those refs, same wording;
# FETCH_HEAD absent, unreadable, in the future or older than the limit, and a missing, malformed or unknown
# source, keep the old behaviour (fetch). Measured 2026-10-04: the fetch over ssh is 3.6 s of a 4.4 s
# SessionStart, paid again on every resume, /clear and compaction.
#
# A fake `git` shim first in PATH logs every fetch / ls-remote / pull the hook starts, then runs the real git.
# Needs no network: the remote is a local bare repository, the "unreachable" one an ssh command that hangs.
#
# Fast and safe in a parallel pool: the scenarios are independent GROUPS that run at the same time, each in its own
# directory under one mktemp -d root (no fixed path or port; the hang script and every pgrep/pkill pattern carry that
# root), so the hanging-remote scenarios wait out their 6 s bound together, not one after the other. Assertions are
# about HOW MANY fetches were started (counted by the shim), never about seconds, except "the hook answers within its
# 6 s bound" (hang script sleeps 60 s, limit 40 s: a broken bound cannot pass, a loaded host cannot fail it).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/session_context.sh"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; }
BOUND_MAX=40   # seconds: the wide limit for "the hook answered within its own 6 s fetch bound"

REAL_GIT="$(command -v git)"
SHIM="$ROOT/shim"
mkdir -p "$SHIM"
cat > "$SHIM/git" <<'SHIM'
#!/bin/sh
# Log the git subcommand when it can touch the network, then run the real git unchanged.
sub=""; skip=0
for a in "$@"; do
  if [ "$skip" = 1 ]; then skip=0; continue; fi
  case "$a" in
    -C|-c|--git-dir|--work-tree|--namespace) skip=1 ;;
    -*) ;;
    *) sub="$a"; break ;;
  esac
done
case "$sub" in fetch|ls-remote|pull) echo "$sub" >> "$GIT_SHIM_LOG" ;; esac
exec "$GIT_SHIM_REAL" "$@"
SHIM
chmod +x "$SHIM/git"

# Monotonic milliseconds: the wall clock jumps when the host stalls or sleeps.
now_ms() { python3 -c 'import time; print(int(time.monotonic() * 1000))'; }

# TMP and LOG are per group (set by group()); run <repo> <stdin payload> [ENV=VALUE ...] -> OUT, CALLS, SECS
run() {
  local repo="$1" payload="$2"; shift 2
  : > "$LOG"
  local t0; t0=$(now_ms)
  OUT="$(printf '%s' "$payload" | env "$@" CLAUDE_PROJECT_DIR="$repo" PATH="$SHIM:$PATH" \
         GIT_SHIM_REAL="$REAL_GIT" GIT_SHIM_LOG="$LOG" bash "$HOOK" 2>/dev/null)"
  SECS=$(( ($(now_ms) - t0) / 1000 ))
  CALLS="$(wc -l < "$LOG" | tr -d ' ')"
}
payload() { printf '{"session_id":"sc","hook_event_name":"SessionStart","source":"%s"}' "$1"; }

remote_ref() { "$REAL_GIT" -C "$1" rev-parse -q --verify refs/remotes/origin/main; }
# stale <name>: a clone whose origin has one commit it has not fetched (origin/main is behind by one).
stale() {
  local n="$1"
  "$REAL_GIT" init -q --bare -b main "$TMP/$n-origin.git"
  "$REAL_GIT" init -q -b main "$TMP/$n-seed"
  ( cd "$TMP/$n-seed" && "$REAL_GIT" config user.email t@t && "$REAL_GIT" config user.name t \
    && "$REAL_GIT" remote add origin "$TMP/$n-origin.git" && "$REAL_GIT" commit -q --allow-empty -m init \
    && "$REAL_GIT" push -q origin HEAD:main 2>/dev/null )
  "$REAL_GIT" clone -q -b main "$TMP/$n-origin.git" "$TMP/$n" 2>/dev/null
  mkdir -p "$TMP/$n/.agents"
  ( cd "$TMP/$n-seed" && "$REAL_GIT" commit -q --allow-empty -m remote1 && "$REAL_GIT" push -q origin HEAD:main 2>/dev/null )
  # fixture sanity: the clone has an upstream and its origin/main is one commit behind the real origin
  [ -n "$(remote_ref "$TMP/$n")" ] && [ "$(remote_ref "$TMP/$n")" != "$("$REAL_GIT" -C "$TMP/$n-origin.git" rev-parse main)" ] \
    || fail "fixture $n is not stale"
}
# fh_path <repo>: where git itself writes FETCH_HEAD for that checkout (per worktree).
fh_path() { "$REAL_GIT" -C "$1" rev-parse --path-format=absolute --git-path FETCH_HEAD; }
# set_age <file> <seconds> [empty]: set the file's mtime to <seconds> ago (negative: in the future). A file that is
# absent or empty gets the one line a successful fetch leaves in it, unless "empty" asks for 0 bytes (what a FAILED
# fetch leaves: it truncates FETCH_HEAD and still bumps its mtime).
set_age() { python3 -c 'import os,sys,time
p=sys.argv[1]
if len(sys.argv) > 3: open(p,"w").close()
elif not os.path.exists(p) or os.path.getsize(p) == 0: open(p,"w").write("0123456789abcdef0123456789abcdef01234567\t\tbranch main of origin\n")
t=time.time()-float(sys.argv[2]); os.utime(p,(t,t))' "$@"; }
# check_calls <label> <repo> <payload> <want-calls> [ENV=VALUE ...]: run the hook, assert the number of fetches
check_calls() {
  local label="$1" repo="$2" pl="$3" want="$4"; shift 4
  run "$repo" "$pl" "$@"
  [ "$CALLS" = "$want" ] && ok "$label: $CALLS fetch(es)" || fail "$label: calls=$CALLS (want $want)"
}
# orphan_check: no ssh stand-in of THIS group is left running (the hook kills the whole group at its bound)
orphan_check() { if pgrep -f "$HANG" >/dev/null; then pkill -f "$HANG"; echo yes; else echo no; fi; }
# mk_hang: a repo whose remote never answers (its ssh command sleeps 60 s)
mk_hang() {
  HANG="$TMP/hang-ssh"
  printf '#!/bin/sh\nsleep 60\n' > "$HANG" && chmod +x "$HANG"
  "$REAL_GIT" init -q "$TMP/hang" && mkdir -p "$TMP/hang/.agents"
  ( cd "$TMP/hang" && "$REAL_GIT" config user.email t@t && "$REAL_GIT" config user.name t \
    && "$REAL_GIT" commit -q --allow-empty -m init && "$REAL_GIT" branch -M main \
    && "$REAL_GIT" remote add origin ssh://git@example.invalid/hang.git && "$REAL_GIT" update-ref refs/remotes/origin/main HEAD \
    && "$REAL_GIT" branch -q -u origin/main && "$REAL_GIT" config core.sshCommand "$HANG" )
  HANGFH="$(fh_path "$TMP/hang")"
}

# The text every "fetched, behind 1" session must print: a startup on a stale clone (a startup always fetches).
TMP="$ROOT/ref"; mkdir -p "$TMP"; LOG="$TMP/git-calls.log"
stale ref
run "$TMP/ref" "$(payload startup)"
STARTUP_OUT="$OUT"
printf '%s' "$STARTUP_OUT" | grep -q "main sau origin/main 1 commit" && printf '%s' "$STARTUP_OUT" | grep -q "git pull --ff-only" \
  || { echo "✖ reference startup did not report 'behind 1': $STARTUP_OUT"; echo "session fetch source: FAILED"; exit 1; }

# ── the groups: independent scenarios, each its own directory, LOG and output file ─────────────────────────
GRP_NAMES=""
group() {   # group <name>: run grp_<name> in the background, output to $ROOT/out.<name>
  local name="$1"
  GRP_NAMES="$GRP_NAMES $name"
  ( TMP="$ROOT/$name"; mkdir -p "$TMP"; LOG="$TMP/git-calls.log"; "grp_$name"; echo "__done__" ) > "$ROOT/out.$name" 2>&1 &
}

# 1-3. resume / clear / compact right after a fetch: no fetch and refs untouched; a startup fetches once; after
# that fetch the three report byte-identical text from the refs with 0 fetches.
grp_after_fetch() {
  stale s1
  set_age "$(fh_path "$TMP/s1")" 60
  local before; before="$(remote_ref "$TMP/s1")"
  for src in resume clear compact; do
    run "$TMP/s1" "$(payload "$src")"
    [ "$CALLS" = 0 ] && [ "$(remote_ref "$TMP/s1")" = "$before" ] \
      && ok "source=$src, FETCH_HEAD 1 min old: no fetch started, remote-tracking refs untouched" || fail "source=$src: calls=$CALLS (want 0)"
    ! printf '%s' "$OUT" | grep -q "sau origin/main" \
      && ok "source=$src, FETCH_HEAD 1 min old: reports from the existing refs (nothing new to say)" \
      || fail "source=$src: unexpected behind text: $OUT"
  done
  run "$TMP/s1" "$(payload startup)"
  [ "$CALLS" = 1 ] && ok "source=startup: one fetch" || fail "source=startup: calls=$CALLS (want 1)"
  printf '%s' "$OUT" | grep -q "main sau origin/main 1 commit" && printf '%s' "$OUT" | grep -q "git pull --ff-only" \
    && ok "source=startup: behind 1 reported, cure = pull --ff-only" || fail "source=startup output: $OUT"
  [ "$(remote_ref "$TMP/s1")" != "$before" ] && ok "source=startup: remote-tracking ref advanced" || fail "source=startup: ref not advanced"
  local startup_out="$OUT"
  for src in resume clear compact; do
    run "$TMP/s1" "$(payload "$src")"
    [ "$CALLS" = 0 ] && ok "source=$src after a fetch: 0 calls" || fail "source=$src after a fetch: calls=$CALLS"
    [ "$OUT" = "$startup_out" ] && ok "source=$src after a fetch: output byte-identical to the startup output" \
      || fail "source=$src after a fetch: output differs: $(diff <(printf '%s' "$startup_out") <(printf '%s' "$OUT"))"
  done
}

# 3b. FETCH_HEAD old, absent, in the future or unreadable: fetch as before, output identical to a startup
grp_old_fetch_head() {
  local n=0
  refetch() {  # <label> <age-seconds | none> <src>: a stale clone; a resume-like source must fetch AND say "behind 1"
    n=$((n + 1)); stale "a$n"
    case "$2" in
      none) rm -f "$(fh_path "$TMP/a$n")" ;;
      *) set_age "$(fh_path "$TMP/a$n")" "$2" ;;
    esac
    run "$TMP/a$n" "$(payload "$3")"
    [ "$CALLS" = 1 ] && [ "$OUT" = "$STARTUP_OUT" ] \
      && ok "source=$3, FETCH_HEAD $1: fetches, output identical to a startup (drift line included)" \
      || fail "source=$3, FETCH_HEAD $1: calls=$CALLS, identical=$([ "$OUT" = "$STARTUP_OUT" ] && echo yes || echo no)"
  }
  for src in resume clear compact; do
    refetch "2 h old" 7200 "$src"
    refetch "absent" none "$src"
  done
  refetch "31 min old (just past the default limit)" 1860 resume
  refetch "in the future (clock skew)" -3600 resume
  # unreadable (a dangling symlink: git cannot even write it, so only the attempt is asserted, not the refs)
  stale a99; ln -sf "$TMP/no-such-dir/FETCH_HEAD" "$(fh_path "$TMP/a99")"
  check_calls "source=resume, FETCH_HEAD a dangling symlink (unreadable)" "$TMP/a99" "$(payload resume)" 1
}

# 3b'. an EMPTY FETCH_HEAD is what a failed fetch leaves (and its mtime is fresh): not a fetch, fetch again
grp_empty_fetch_head() {
  local n=0
  for src in resume clear compact; do
    n=$((n + 1)); stale "e$n"
    set_age "$(fh_path "$TMP/e$n")" 60 empty
    run "$TMP/e$n" "$(payload "$src")"
    [ "$CALLS" = 1 ] && [ "$OUT" = "$STARTUP_OUT" ] \
      && ok "source=$src, FETCH_HEAD 0 bytes and 1 min old: fetches, output identical to a startup (drift line included)" \
      || fail "source=$src, empty FETCH_HEAD: calls=$CALLS, identical=$([ "$OUT" = "$STARTUP_OUT" ] && echo yes || echo no)"
  done
  stale e9
  set_age "$(fh_path "$TMP/e9")" 60
  check_calls "FETCH_HEAD non-empty and 1 min old: no fetch" "$TMP/e9" "$(payload resume)" 0
  # end to end: a startup while the remote is unreachable (fast failure), then the remote is back: the resume must
  # still say "behind 1", exactly as a startup would.
  stale f1
  local good; good="$("$REAL_GIT" -C "$TMP/f1" remote get-url origin)"
  "$REAL_GIT" -C "$TMP/f1" remote set-url origin "$TMP/no-such-remote.git"
  run "$TMP/f1" "$(payload startup)"
  [ "$CALLS" = 1 ] && [ ! -s "$(fh_path "$TMP/f1")" ] && [ -e "$(fh_path "$TMP/f1")" ] \
    && ok "e2e: startup with the remote gone: one failed fetch, FETCH_HEAD left empty" || fail "e2e step 1: calls=$CALLS"
  "$REAL_GIT" -C "$TMP/f1" remote set-url origin "$good"
  run "$TMP/f1" "$(payload resume)"
  [ "$CALLS" = 1 ] && [ "$OUT" = "$STARTUP_OUT" ] && printf '%s' "$OUT" | grep -q "main sau origin/main 1 commit" \
    && ok "e2e: resume once the remote is back fetches and reports 'main sau origin/main 1 commit' like a startup" \
    || fail "e2e step 2: calls=$CALLS: $OUT"
  check_calls "e2e: the next resume (that fetch succeeded, FETCH_HEAD non-empty) skips" "$TMP/f1" "$(payload resume)" 0
}

# 3c. the limit: default 1800 s, SESSION_FETCH_MAX_AGE_S overrides it
grp_limit() {
  stale m1
  local fh; fh="$(fh_path "$TMP/m1")"
  set_age "$fh" 1500; check_calls "FETCH_HEAD 25 min old, default limit" "$TMP/m1" "$(payload resume)" 0
  set_age "$fh" 60;   check_calls "FETCH_HEAD 1 min old, SESSION_FETCH_MAX_AGE_S=30" "$TMP/m1" "$(payload resume)" 1 SESSION_FETCH_MAX_AGE_S=30
  set_age "$fh" 7200; check_calls "FETCH_HEAD 2 h old, SESSION_FETCH_MAX_AGE_S=86400" "$TMP/m1" "$(payload resume)" 0 SESSION_FETCH_MAX_AGE_S=86400
  set_age "$fh" 60;   check_calls "FETCH_HEAD 1 min old, SESSION_FETCH_MAX_AGE_S=0 (always fetch)" "$TMP/m1" "$(payload resume)" 1 SESSION_FETCH_MAX_AGE_S=0
  set_age "$fh" 7200; check_calls "SESSION_FETCH=0, FETCH_HEAD 2 h old, resume" "$TMP/m1" "$(payload resume)" 0 SESSION_FETCH=0
}
# 3c'. an invalid limit means the default 1800 s
grp_limit_invalid() {
  stale m2
  local fh; fh="$(fh_path "$TMP/m2")"
  for bad in abc "" -5 1.5 "1 2"; do
    set_age "$fh" 60;   check_calls "FETCH_HEAD 1 min old, invalid limit '$bad' -> default 1800" "$TMP/m2" "$(payload resume)" 0 "SESSION_FETCH_MAX_AGE_S=$bad"
    set_age "$fh" 7200; check_calls "FETCH_HEAD 2 h old, invalid limit '$bad' -> default 1800" "$TMP/m2" "$(payload resume)" 1 "SESSION_FETCH_MAX_AGE_S=$bad"
  done
}
# a new session (or an unknown source) fetches whatever the age of FETCH_HEAD
grp_new_session() {
  stale m3
  local fh; fh="$(fh_path "$TMP/m3")"
  for pl in "$(payload startup)" '{"session_id":"sc"}' "$(payload fork)" "$(payload bogus)"; do
    set_age "$fh" 60; check_calls "FETCH_HEAD 1 min old, payload $pl" "$TMP/m3" "$pl" 1
  done
}

# 3d. a linked worktree: FETCH_HEAD is per worktree, the remote-tracking refs are shared
grp_worktree() {
  stale w1
  "$REAL_GIT" -C "$TMP/w1" worktree add -q -b wtb "$TMP/w1-wt" origin/main 2>/dev/null
  mkdir -p "$TMP/w1-wt/.agents"
  run "$TMP/w1-wt" "$(payload startup)"
  [ "$CALLS" = 1 ] && [ -e "$(fh_path "$TMP/w1-wt")" ] && [ "$(fh_path "$TMP/w1-wt")" != "$(fh_path "$TMP/w1")" ] \
    && ok "worktree: startup fetches and writes the worktree's own FETCH_HEAD" || fail "worktree startup: calls=$CALLS"
  check_calls "worktree: resume right after its own fetch" "$TMP/w1-wt" "$(payload resume)" 0
  set_age "$(fh_path "$TMP/w1-wt")" 7200
  check_calls "worktree: resume, its FETCH_HEAD 2 h old, main checkout never fetched" "$TMP/w1-wt" "$(payload resume)" 1
  set_age "$(fh_path "$TMP/w1-wt")" 7200; set_age "$(fh_path "$TMP/w1")" 60
  check_calls "worktree: resume, its FETCH_HEAD old but the main checkout fetched 1 min ago (refs are shared)" "$TMP/w1-wt" "$(payload resume)" 0
}

# 4. missing / malformed / unknown source: the old behaviour (fetch)
grp_unknown_source() {
  local n=0
  fetches() {  # <label> <payload>
    n=$((n + 1)); stale "u$n"
    run "$TMP/u$n" "$2"
    [ "$CALLS" = 1 ] && printf '%s' "$OUT" | grep -q "main sau origin/main 1 commit" \
      && ok "$1: fetches (old behaviour)" || fail "$1: calls=$CALLS, output: $OUT"
  }
  fetches "no source field"          '{"session_id":"sc","hook_event_name":"SessionStart"}'
  fetches "empty stdin"              ''
  fetches "stdin is not JSON"        'not json at all'
  fetches "stdin is a JSON list"     '["resume"]'
  fetches "source is null"           '{"source":null}'
  fetches "source is a list"         '{"source":["resume"]}'
  fetches "source is empty"          '{"source":""}'
  fetches "source is unknown"        '{"source":"bogus"}'
  fetches "source is fork (new session forked from another)" "$(payload fork)"
  fetches "stdin is nested JSON deeper than the parser allows" "$(python3 -c 'print("["*5000 + "]"*5000)')"
  fetches "source is Resume (case differs: unknown, not trusted)" "$(payload Resume)"
}

# 5. SESSION_FETCH=0 keeps skipping everything
grp_fetch_off() {
  stale z1
  for src in startup resume clear compact; do
    run "$TMP/z1" "$(payload "$src")" SESSION_FETCH=0
    [ "$CALLS" = 0 ] && ok "SESSION_FETCH=0, source=$src: 0 calls" || fail "SESSION_FETCH=0, source=$src: calls=$CALLS"
  done
  run "$TMP/z1" '{"session_id":"sc"}' SESSION_FETCH=0
  [ "$CALLS" = 0 ] && ok "SESSION_FETCH=0, no source: 0 calls" || fail "SESSION_FETCH=0, no source: calls=$CALLS"
}

# 6. a remote that never answers (each scenario in its own group, so the three 6 s bounds overlap)
grp_hang_startup() {
  mk_hang; set_age "$HANGFH" 7200
  run "$TMP/hang" "$(payload startup)"
  local o; o="$(orphan_check)"
  [ "$CALLS" = 1 ] && [ "$SECS" -le "$BOUND_MAX" ] && [ "$o" = no ] \
    && ok "startup, remote never answers: one fetch, answered within the bound (${SECS}s), no orphan ssh" \
    || fail "startup, hanging remote: calls=$CALLS secs=$SECS orphan=$o"
}
grp_hang_resume_old() {
  mk_hang; set_age "$HANGFH" 7200
  run "$TMP/hang" "$(payload resume)"
  local o; o="$(orphan_check)"
  [ "$CALLS" = 1 ] && [ "$SECS" -le "$BOUND_MAX" ] && [ "$o" = no ] \
    && ok "resume, FETCH_HEAD 2 h old, remote never answers: one fetch, answered within the bound (${SECS}s), no orphan ssh" \
    || fail "resume, old FETCH_HEAD, hanging remote: calls=$CALLS secs=$SECS orphan=$o"
}
grp_hang_resume_killed() {
  # the startup fetch was killed at the bound: whatever it left in FETCH_HEAD (0 bytes, fresh mtime) is not a fetch
  mk_hang; set_age "$HANGFH" 60 empty
  run "$TMP/hang" "$(payload resume)"
  local o; o="$(orphan_check)"
  [ "$CALLS" = 1 ] && [ "$SECS" -le "$BOUND_MAX" ] && [ "$o" = no ] \
    && ok "resume after a startup whose fetch was killed at the bound (FETCH_HEAD 0 bytes): fetches again, no orphan ssh" \
    || fail "resume, killed-fetch FETCH_HEAD, hanging remote: calls=$CALLS secs=$SECS orphan=$o"
}
grp_hang_no_fetch() {
  mk_hang
  for src in resume clear compact; do
    set_age "$HANGFH" 60
    run "$TMP/hang" "$(payload "$src")"
    local o; o="$(orphan_check)"
    [ "$CALLS" = 0 ] && [ "$o" = no ] \
      && ok "source=$src, FETCH_HEAD 1 min old, remote never answers: no fetch started, so nothing to wait for" \
      || fail "source=$src, hanging remote: calls=$CALLS orphan=$o"
  done
}

t0_all=$(now_ms)
for g in after_fetch old_fetch_head empty_fetch_head limit limit_invalid new_session worktree unknown_source fetch_off \
         hang_startup hang_resume_old hang_resume_killed hang_no_fetch; do group "$g"; done
wait
FAILS=0
for g in $GRP_NAMES; do
  grep -v "^__done__$" "$ROOT/out.$g"
  grep -q '^__done__$' "$ROOT/out.$g" || { echo "✖ group $g did not finish"; FAILS=$((FAILS + 1)); }
  FAILS=$((FAILS + $(grep -c '^✖' "$ROOT/out.$g")))
done
if [ "$FAILS" -ne 0 ]; then echo "session fetch source: $FAILS FAILED"; exit 1; fi
echo "session fetch source: all checks passed ($(( ($(now_ms) - t0_all) / 1000 )) s for the scenario groups)"
