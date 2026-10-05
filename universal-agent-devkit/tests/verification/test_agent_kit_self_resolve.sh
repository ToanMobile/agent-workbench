#!/usr/bin/env bash
# Regression test: bin/agent-kit finds the kit it belongs to when it is called through a symlink chain (~/.local/bin/agent-kit,
# agent-install, a link of the user's own). The first lines follow the links of ${BASH_SOURCE[0]}; two flaws, the same kind as the
# one fixed in hooks/session_lock.sh:
#   (a) `LINK="$(readlink "$SELF")"` strips a trailing NEWLINE of the link target, so a target `agent-kit<newline>` was followed as the
#       DIFFERENT file `agent-kit` (here a link to another kit: the wrong DEVKIT_ROOT);
#   (b) the loop had NO bound: a readlink that keeps answering with a link made it spin forever (a hang, not an error).
# Now: readlink -n + a sentinel keeps the target exact, at most 32 hops, and anything unexpected (a loop, a longer chain, an empty or
# newline-bearing target, no readlink) falls back to python's realpath of the original path. When that fails too (no python3, or a
# loop it cannot end), agent-kit says so on stderr (one line) and exits 1 instead of going on with the folder of the LINK as the kit
# (the old code died there as well: `set -e` on a failing readlink, or an endless loop; it never ran the wrong kit quietly).
# Every check runs a COPY of bin/agent-kit in a fixture kit (skills/ with 2 folders: `agent-kit list` prints "(2)"; a decoy kit prints "(1)"),
# so which kit was found is visible in the output. A runaway loop is caught by COUNTING readlink calls (a shim kills the run after 80),
# not by a clock. Groups (1) must hold for the old code too: they are what the fix must not change.
# bash 3.2 compatible; python3 (stdlib only, 3.9 compatible) makes the odd links.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkkit() { # <dir> <number of skill folders>: a kit around a copy of the real agent-kit
  mkdir -p "$1/bin" "$1/skills"; cp "$DEVKIT_DIR/bin/agent-kit" "$1/bin/agent-kit"
  local i=0; while [ "$i" -lt "$2" ]; do i=$((i + 1)); mkdir -p "$1/skills/s$i"; done
}
# run <cmd...> in its own session (a kill of its group cannot reach this test), at most 30 s -> RC, OUT, ERR ("124" when it ran over).
# PY is the python found before any check puts a stand-in python3 first on the PATH of the command under test.
PY="$(command -v python3)"
run() {
  OUT="$("$PY" -I -c '
import subprocess, sys
try:
    p = subprocess.run(sys.argv[1:], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30, start_new_session=True)
    sys.stdout.write("%d\n%s" % (p.returncode, p.stdout))
    sys.stderr.write(p.stderr)
except subprocess.TimeoutExpired:
    sys.stdout.write("124\n")
' "$@" 2>"$TMP/run.err")"
  RC="${OUT%%
*}"; OUT="${OUT#*
}"; ERR="$(cat "$TMP/run.err")"
}
count() { printf '%s' "$1" | head -1; }   # "Available Skills in Universal Agent DevKit (N):"
want2="Available Skills in Universal Agent DevKit (2):"

# ── 1: what must not change ─────────────────────────────────────────────────────────────────────────────────────
K="$TMP/kit"; mkkit "$K" 2
run bash "$K/bin/agent-kit" list
[ "$(count "$OUT")" = "$want2" ] && ok "1a called directly: finds its own kit" || fail "1a direct: rc=$RC '$(count "$OUT")'"

mkdir -p "$TMP/l1" "$TMP/l2/deep"
ln -s "$K/bin/agent-kit" "$TMP/l1/hop2"; ln -s "$TMP/l1/hop2" "$TMP/l1/hop1"
run bash "$TMP/l1/hop1" list
[ "$(count "$OUT")" = "$want2" ] && ok "1b a chain of absolute links" || fail "1b absolute chain: rc=$RC '$(count "$OUT")'"

ln -s "../../kit/bin/agent-kit" "$TMP/l2/deep/rel2"; ln -s "deep/rel2" "$TMP/l2/rel1"
run bash "$TMP/l2/rel1" list
[ "$(count "$OUT")" = "$want2" ] && ok "1c a chain of relative links across folders" || fail "1c relative chain: rc=$RC '$(count "$OUT")'"

S="$TMP/with space/ünï kit"; mkkit "$S" 2; mkdir -p "$TMP/with space/links"; ln -s "../ünï kit/bin/agent-kit" "$TMP/with space/links/my link"
run bash "$TMP/with space/links/my link" list
[ "$(count "$OUT")" = "$want2" ] && ok "1d spaces and unicode in every path" || fail "1d spaces: rc=$RC '$(count "$OUT")'"

( cd "$TMP/l2" && run bash ./rel1 list )
[ "$(count "$OUT")" = "$want2" ] && ok "1e a relative call (./link) from its own folder" || fail "1e ./link: rc=$RC '$(count "$OUT")'"

# ── 2: the link target ends in a NEWLINE ────────────────────────────────────────────────────────────────────────
# R/bin/"agent-kit<nl>" is the real kit (2 skills). R/bin/agent-kit (no newline) is a link to ANOTHER kit (1 skill): following the
# stripped name ends in the wrong kit.
R="$TMP/nl/R"; DECOY="$TMP/nl/decoy"; mkkit "$DECOY" 1; mkdir -p "$R/bin" "$R/skills/s1" "$R/skills/s2" "$TMP/nl/L"
python3 -I - "$R" "$DECOY" "$TMP/nl/L" "$DEVKIT_DIR/bin/agent-kit" <<'PY'
import os, shutil, sys
r, decoy, links, src = sys.argv[1:5]
shutil.copy(src, os.path.join(r, "bin", "agent-kit\n"))
os.chmod(os.path.join(r, "bin", "agent-kit\n"), 0o755)
os.symlink(os.path.join(decoy, "bin", "agent-kit"), os.path.join(r, "bin", "agent-kit"))
os.symlink("../R/bin/agent-kit\n", os.path.join(links, "lnk"))
PY
run bash "$TMP/nl/L/lnk" list
[ "$(count "$OUT")" = "$want2" ] && ok "2 a link target ending in a newline is followed exactly (the real kit, not the decoy of the stripped name)" \
  || fail "2 newline target: rc=$RC '$(count "$OUT")' (the decoy kit says (1))"

# ── 2b: a newline-bearing target is handed to python, not followed by the shell ──────────────────────────────────────
# The guard `*$'\n'*` in the loop sends a target with a newline to python's realpath. 2 passes without it (a target is read exactly), so
# this is the case only the guard saves: the link sits in a folder whose NAME ends in a newline, and its relative target holds one too. The
# shell builds the next path from `$(dirname ...)`, which strips that folder's trailing newline (".../L" for ".../L<nl>"): a folder that
# does not exist, a kit not found. Python's realpath of the original path is exact.
R2="$TMP/nl2/R"; mkdir -p "$R2/bin" "$R2/skills/s1" "$R2/skills/s2"
python3 -I - "$R2" "$TMP/nl2" "$DEVKIT_DIR/bin/agent-kit" <<'PY'
import os, shutil, sys
r, base, src = sys.argv[1:4]
dst = os.path.join(r, "bin", "agent-kit\n")
shutil.copy(src, dst); os.chmod(dst, 0o755)
d = os.path.join(base, "L\n"); os.makedirs(d)
os.symlink("../R/bin/agent-kit\n", os.path.join(d, "lnk"))
PY
run bash "$TMP/nl2/L
/lnk" list
[ "$(count "$OUT")" = "$want2" ] && ok "2b a newline-bearing target in a folder named with a trailing newline: python finds the real kit" \
  || fail "2b newline target in a newline-named folder: rc=$RC '$(count "$OUT")' err='$(printf '%s' "$ERR" | head -2 | tr '\n' '|')'"

# ── 3: a loop with no end (readlink keeps answering with a link) ────────────────────────────────────────────────
# The shim readlink answers every call with `lnk`, a real link in the same folder: the old loop never ends. It counts its calls and kills
# its whole run (the session `run` started) after 80. The fix stops after 32 hops and asks python for the real path.
SH="$TMP/shim"; mkdir -p "$SH" "$TMP/loop"; ln -s "$K/bin/agent-kit" "$TMP/loop/lnk"
cat > "$SH/readlink" <<'SH'
#!/bin/sh
n=$(( $(cat "$RL_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$RL_COUNT"
[ "$n" -gt 80 ] && kill -KILL 0
case "$1" in -n) shift; printf 'lnk' ;; *) echo lnk ;; esac
SH
chmod +x "$SH/readlink"; RL_COUNT="$TMP/rl.count"; : > "$RL_COUNT"; export RL_COUNT
PATH="$SH:$PATH" run bash "$TMP/loop/lnk" list
calls="$(cat "$RL_COUNT")"
if [ "$(count "$OUT")" = "$want2" ] && [ "${calls:-0}" -le 40 ]; then ok "3 a loop with no end is cut after 32 hops ($calls readlink calls) and the real kit is still found"
else fail "3 loop: rc=$RC '$(count "$OUT")' after ${calls:-0} readlink calls (80+ = never ended, the shim killed it)"; fi

# ── 4: nothing can resolve the chain (the loop of 3, and python3 cannot give the real path either) ─────────────────────────
# The link sits in the folder of a DECOY kit (1 skill) and leads to the real kit K (2 skills). The old fallback ended with SELF still the
# link, so the decoy's folder became the kit: `list` printed "(1)" and exited 0, a wrong kit used quietly. The old code before this patch
# never did that (a failing readlink stopped it under `set -e`, a loop never ended). Now: one line on stderr, exit 1, nothing run.
DC="$TMP/decoy4"; mkkit "$DC" 1; ln -s "$K/bin/agent-kit" "$DC/bin/lnk"
for variant in "exit 1" "exit 0"; do   # python3 failing, and python3 answering with nothing
  S4="$TMP/shim4"; rm -rf "$S4"; mkdir -p "$S4"
  printf '#!/bin/sh\n%s\n' "$variant" > "$S4/python3"; chmod +x "$S4/python3"
  cp "$SH/readlink" "$S4/readlink"; : > "$RL_COUNT"
  PATH="$S4:$PATH" run bash "$DC/bin/lnk" list
  calls="$(cat "$RL_COUNT")"
  if [ "$RC" != 0 ] && [ "$RC" != 124 ] && [ "$(printf '%s\n' "$ERR" | grep -c .)" = 1 ] && printf '%s' "$ERR" | grep -q '^agent-kit: ' \
     && ! printf '%s' "$OUT" | grep -q 'Available Skills' && [ "${calls:-0}" -le 40 ]; then
    ok "4 [python3: $variant] an unresolvable link chain: exit $RC, one line on stderr, no kit used ('$ERR')"
  else fail "4 [python3: $variant] unresolvable chain: rc=$RC out='$(count "$OUT")' err='$(printf '%s' "$ERR" | tr '\n' '|')' ($calls readlink calls); want rc!=0, one 'agent-kit: ...' line, no output"; fi
done

echo
[ "$FAILS" = 0 ] && echo "agent-kit self resolve: all checks passed" || echo "agent-kit self resolve: $FAILS FAILED"
exit $((FAILS > 0))
