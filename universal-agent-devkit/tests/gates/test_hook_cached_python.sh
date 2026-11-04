#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh + hooks/block-dangerous-git.sh (#967): their python is a module beside each hook
# (hooks/hardware_safety_gate_main.py, hooks/block_dangerous_git_main.py), loaded by a short `python3 -I -c` loader, so its bytecode can be
# cached. Inline code never is: every Bash call compiled ~2.7k + ~2.3k lines and imported shell_norm.py uncached (~33 + ~35 ms CPU per call, 04/11).
#   a. the cache is the private directory of hooks/prompt_context.sh, $TMPDIR/devkit-pycache-$UID: after two runs of each hook it holds the
#      bytecode of both modules and of shell_norm.py, the second run reused it (same mtime), and no __pycache__ appears beside the hooks;
#   b. a cache directory that is group-writable, or a symlink, is not used: no bytecode there, the hook still answers (rc 0);
#   c. a hook whose module is missing, or does not compile, blocks: rc 2 with one line naming the module, no traceback (fail closed);
#   d. the verdict is unchanged: dangerous commands rc 2, harmless ones rc 0, through the real hooks.
# HCP_HOOKS=<hooks dir> runs a and c against another copy (the inline hooks of origin/main: RED). Only runs the hooks, never a command.
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${HCP_HOOKS:-$DEVKIT_DIR/hooks}"
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset HARDWARE_SAFETY_GATE HARDWARE_OVERRIDE DEVKIT_ALLOW_BRANCH CDPATH
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
ME="$(id -u)"

P="$TMP/proj"
mkdir -p "$P/src"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'x\n' > "$P/src/a.kt" && git -C "$P" add -A && git -C "$P" commit -qm init

# kit <dir> [skip-glob]: a copy of the hooks (the .sh and .py files) in <dir>/hooks, without the files matching skip-glob
kit() {
  local f
  mkdir -p "$1/hooks"
  for f in "$SRC"/*.sh "$SRC"/*.py; do
    case "$(basename "$f")" in ${2:-/}) continue ;; esac
    cp "$f" "$1/hooks/"
  done
}
# run <hooks dir> <hook> <tmpdir> <command>: the hook's rc for a Bash call of <command>; stderr in $TMP/err
run() {
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$4" "$P" > "$TMP/in.json"
  ( cd "$P" && TMPDIR="$3" CLAUDE_PROJECT_DIR="$P" XDG_CONFIG_HOME="$TMP/xdg" ADB_DENY_SERIALS= ADB_ALLOW_SERIALS= ANDROID_SERIAL= \
      bash "$1/$2" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
}
# the harmless command of each hook that reaches its python (git: the word git; hardware: a $ keeps it off the bash fast path)
HARMLESS_GG='git status'
HARMLESS_HW='ls "$HOME"'
# pycs <dir>: "<name> <mtime ns>" of every .pyc under <dir>, sorted
pycs() { find "$1" -name '*.pyc' -exec python3 -I -c 'import os,sys
for p in sys.argv[1:]: print(os.path.basename(p), os.stat(p).st_mtime_ns)' {} + 2>/dev/null | sort; }
side_pycache() { find "$1/hooks" -name __pycache__ -o -name '*.pyc' | head -1; }

echo "── a. bytecode cached in \$TMPDIR/devkit-pycache-\$UID, reused, never beside the hooks"
kit "$TMP/ka"
T="$TMP/ta"; mkdir -p "$T"
C="$T/devkit-pycache-$ME"
for n in 1 2; do
  run "$TMP/ka/hooks" block-dangerous-git.sh "$T/" "$HARMLESS_GG"; r1=$?
  run "$TMP/ka/hooks" hardware_safety_gate.sh "$T/" "$HARMLESS_HW"; r2=$?
  [ "$r1$r2" = 00 ] && ok "run $n: both hooks rc 0 on a harmless command" || fail "run $n: rc git=$r1 hw=$r2 — $(head -c 200 "$TMP/err" | LC_ALL=C tr '\n' ' ')"
  pycs "$C" > "$TMP/pyc$n"
done
for m in block_dangerous_git_main hardware_safety_gate_main shell_norm; do
  grep -q "^$m\.[^ ]*\.pyc " "$TMP/pyc2" && ok "$m bytecode in the private cache" || fail "no $m bytecode under $C: $(tr '\n' ' ' < "$TMP/pyc2" | head -c 200)"
done
[ -s "$TMP/pyc1" ] && cmp -s "$TMP/pyc1" "$TMP/pyc2" && ok "the second run reused the bytecode of the first (same files, same mtime)" \
  || fail "the second run rewrote or added bytecode: $(diff "$TMP/pyc1" "$TMP/pyc2" | head -4 | tr '\n' ' ')"
s="$(side_pycache "$TMP/ka")"; [ -z "$s" ] && ok "no __pycache__ / .pyc beside the hooks" || fail "bytecode beside the hooks: $s"
[ -d "$C" ] && [ ! -L "$C" ] && [ "$(ls -ld "$C" | cut -c1-10)" = drwx------ ] && ok "the cache directory was made 0700" \
  || fail "cache directory mode: $(ls -ld "$C" 2>&1)"

echo "── b. a cache directory others can write, or a symlink, is not used"
kit "$TMP/kb"
T="$TMP/tb1"; mkdir -p "$T/devkit-pycache-$ME" && chmod 775 "$T/devkit-pycache-$ME"
run "$TMP/kb/hooks" block-dangerous-git.sh "$T" "$HARMLESS_GG"; r1=$?
run "$TMP/kb/hooks" hardware_safety_gate.sh "$T" "$HARMLESS_HW"; r2=$?
[ "$r1$r2" = 00 ] && ok "group-writable cache: both hooks still rc 0" || fail "group-writable cache: rc git=$r1 hw=$r2 — $(head -c 200 "$TMP/err")"
[ -z "$(pycs "$T")" ] && ok "group-writable cache: no bytecode written into it" || fail "bytecode written into a group-writable cache: $(pycs "$T" | head -3 | tr '\n' ' ')"
T="$TMP/tb2"; mkdir -p "$T" "$TMP/elsewhere" && chmod 700 "$TMP/elsewhere" && ln -s "$TMP/elsewhere" "$T/devkit-pycache-$ME"
run "$TMP/kb/hooks" block-dangerous-git.sh "$T" "$HARMLESS_GG"; r1=$?
run "$TMP/kb/hooks" hardware_safety_gate.sh "$T" "$HARMLESS_HW"; r2=$?
[ "$r1$r2" = 00 ] && ok "symlinked cache: both hooks still rc 0" || fail "symlinked cache: rc git=$r1 hw=$r2 — $(head -c 200 "$TMP/err")"
[ -z "$(pycs "$TMP/elsewhere")" ] && ok "symlinked cache: no bytecode written through the link" || fail "bytecode written through a symlinked cache"
s="$(side_pycache "$TMP/kb")"; [ -z "$s" ] && ok "unsafe caches: no __pycache__ / .pyc beside the hooks either" || fail "bytecode beside the hooks: $s"

echo "── c. a module that cannot be loaded blocks (fail closed)"
kit "$TMP/kc" '*_main.py'
for pair in "block-dangerous-git.sh|block_dangerous_git_main.py|$HARMLESS_GG" "hardware_safety_gate.sh|hardware_safety_gate_main.py|$HARMLESS_HW"; do
  h="${pair%%|*}"; rest="${pair#*|}"; m="${rest%%|*}"; c="${rest#*|}"
  for state in missing broken; do
    rm -f "$TMP/kc/hooks/$m"
    [ "$state" = broken ] && printf 'import sys\nthis is not python (\n' > "$TMP/kc/hooks/$m"
    run "$TMP/kc/hooks" "$h" "$TMP/tc" "$c"; rc=$?
    lines="$(grep -c . "$TMP/err")"
    if [ "$rc" = 2 ] && grep -q "không nạp được hooks/$m" "$TMP/err" && [ "$lines" = 1 ] && ! grep -q Traceback "$TMP/err"; then
      ok "$h, $m $state: rc 2, one line naming the module"
    else fail "$h, $m $state: rc $rc ($lines lines) — $(head -c 240 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; fi
  done
done

echo "── d. verdicts unchanged (the real hooks, the usual cache)"
H="$DEVKIT_DIR/hooks"
python3 -I - <<'PY' > "$TMP/cases"
# want<TAB>hook<TAB>command (the dangerous ones live here, in the test, never on a command line)
rows = [
    (2, "block-dangerous-git.sh", "git reset --hard"),
    (2, "block-dangerous-git.sh", "git push --force origin main"),
    (2, "block-dangerous-git.sh", "git clean -fdx"),
    (2, "block-dangerous-git.sh", "cd src && git checkout -- ."),
    (0, "block-dangerous-git.sh", "git status"),
    (0, "block-dangerous-git.sh", "git log --oneline -3"),
    (0, "block-dangerous-git.sh", "git diff --stat HEAD"),
    (2, "hardware_safety_gate.sh", "rm -rf ~"),
    (2, "hardware_safety_gate.sh", "adb shell rm -rf /sdcard/../system"),
    (2, "hardware_safety_gate.sh", "adb remount"),
    (2, "hardware_safety_gate.sh", "fastboot flash boot boot.img"),
    (0, "hardware_safety_gate.sh", 'ls "$HOME"'),
    (0, "hardware_safety_gate.sh", "adb devices"),
    (0, "hardware_safety_gate.sh", 'echo "$PWD" | wc -c'),
]
for want, hook, cmd in rows:
    print("%d\t%s\t%s" % (want, hook, cmd))
PY
while IFS="$(printf '\t')" read -r want h c; do
  run "$H" "$h" "${TMPDIR:-/tmp}" "$c"; rc=$?
  if [ "$rc" = "$want" ] && ! grep -q -E 'Traceback|lỗi nội bộ|không nạp được' "$TMP/err"; then ok "$h rc $rc: $c"
  else fail "$h rc $rc (want $want): $c — $(head -c 200 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; fi
done < "$TMP/cases"

echo
if [ "$FAILS" -eq 0 ]; then echo "✅ test_hook_cached_python: all checks passed"; exit 0; fi
echo "❌ test_hook_cached_python: $FAILS failed"; exit 1
