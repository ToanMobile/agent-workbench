#!/usr/bin/env bash
# hooks/worktree_guard.sh now takes its Bash write targets from hooks/shell_writes.py (issues-bugs.md A.1 #3, 14/10: the scanner it had
# inline, shared with bin/session_lock.py). For a worker that entered a worktree (EnterWorktree in its transcript):
#  - a Bash write into the MAIN checkout is still blocked (cp, chmod -w whose mode starts with -, env -C <main> rm from the worktree);
#  - the same write inside its worktree is not;
#  - with shell_writes.py missing next to the hook (a partial install), the Bash call is BLOCKED with the reason: the inline scanner
#    always ran, so a missing module must not switch the check off without a word (OpenCodeReview 14/10).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
M="$TMP/main"; W="$TMP/wt"
mkdir -p "$M/src" && git -C "$M" init -q && git -C "$M" config user.email t@t && git -C "$M" config user.name t \
  && echo x > "$M/src/a.kt" && git -C "$M" add -A && git -C "$M" commit -qm i && git -C "$M" worktree add -q --detach "$W" HEAD
TR="$TMP/t.jsonl"
python3 - "$TR" "$M" "$W" <<'PY'
import json, sys
tr, main, wt = sys.argv[1:4]
rec = lambda **kw: json.dumps(kw, separators=(",", ":"))
with open(tr, "w") as f:
    f.write(rec(type="user", cwd=main, message={"role": "user", "content": "hi"}) + "\n")
    f.write(rec(type="assistant", cwd=main, message={"role": "assistant", "content": [
        {"type": "tool_use", "id": "toolu_1", "name": "EnterWorktree", "input": {"path": wt}}]}) + "\n")
    f.write(rec(type="user", cwd=main, message={"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "toolu_1", "content": "Switched to worktree " + wt}]}) + "\n")
PY
guard() {   # guard <hook> <cwd> <command>: the hook's exit code; stderr in $TMP/err
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":sys.argv[1],"cwd":sys.argv[2],
"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[3]}}))' "$TR" "$2" "$3" \
  | env -u WORKTREE_GUARD CLAUDE_PROJECT_DIR="$M" bash "$1" >/dev/null 2>"$TMP/err"
}
H="$DEVKIT_DIR/hooks/worktree_guard.sh"
guard "$H" "$M" "cp /tmp/x src/b.kt"; rc=$?
[ "$rc" = 2 ] && grep -q "WORKTREE GUARD" "$TMP/err" && ok "cp into the main checkout: blocked" || fail "cp into main: rc $rc"
guard "$H" "$M" "chmod -w src/a.kt"; rc=$?
[ "$rc" = 2 ] && ok "chmod -w (a mode starting with -) in the main checkout: blocked" || fail "chmod -w in main: rc $rc"
guard "$H" "$W" "env -C $M rm src/a.kt"; rc=$?
[ "$rc" = 2 ] && ok "env -C <main> rm from the worktree: blocked" || fail "env -C main: rc $rc"
guard "$H" "$W" "rm src/a.kt"; rc=$?
[ "$rc" = 0 ] && ok "rm inside its own worktree: allowed" || fail "rm in the worktree: rc $rc $(cat "$TMP/err")"
# env -S / --split-string holds a whole command line: env splits it into words, puts them first and runs them with the words after it
# appended. It was dropped as the option's value, so its writes were never seen (OpenCodeReview 14/10, issues-bugs.md A.4 (b)).
guard "$H" "$M" "env -S 'rm src/a.kt'"; rc=$?
[ "$rc" = 2 ] && ok "env -S '<rm …>' in the main checkout: blocked" || fail "env -S '<rm …>' in main: rc $rc"
guard "$H" "$M" "env -S'rm -f' src/a.kt"; rc=$?
[ "$rc" = 2 ] && ok "env -S'rm -f' src/a.kt (attached, the operand after it): blocked" || fail "env -S'rm -f' + operand in main: rc $rc"
guard "$H" "$M" "env --split-string 'FOO=1 rm src/a.kt'"; rc=$?
[ "$rc" = 2 ] && ok "env --split-string '<VAR=… rm …>' in the main checkout: blocked" || fail "env --split-string <line> in main: rc $rc"
guard "$H" "$M" "env -i --split-string='rm src/a.kt'"; rc=$?
[ "$rc" = 2 ] && ok "env -i --split-string='<rm …>' in the main checkout: blocked" || fail "env --split-string=<line> in main: rc $rc"
guard "$H" "$W" "env -S 'rm src/a.kt'"; rc=$?
[ "$rc" = 0 ] && ok "env -S '<rm …>' inside its own worktree: allowed" || fail "env -S in the worktree: rc $rc $(cat "$TMP/err")"
# env -S's own escapes (OpenCodeReview 14/10, measured on macOS env): an unquoted \_ separates words, so this is `rm src/a.kt`
guard "$H" "$M" "env -S 'rm\\_src/a.kt'"; rc=$?
[ "$rc" = 2 ] && ok "env -S 'rm\\_src/a.kt' (\\_ separates) in the main checkout: blocked" || fail "env -S 'rm\\_…' in main: rc $rc"
# ... and \' inside single quotes, which env honours and shlex cannot parse: the line's operands are still judged
guard "$H" "$M" "env -S \"rm 'f\\'g' src/a.kt\""; rc=$?
[ "$rc" = 2 ] && ok "env -S \"rm 'f\\'g' src/a.kt\" (\\' in single quotes) in the main checkout: blocked" || fail "env -S with \\' in main: rc $rc"
# ... and env's quote rules (OpenCodeReview shell_writes 14/10): inside '…' a \c is literal, so env runs `rm 'a\c' <main>/src/a.kt`;
# the scanner cut the line at that \c, never saw the main path, and the call went through from the worktree
guard "$H" "$W" "env -S \"rm 'a\\c' $M/src/a.kt\""; rc=$?
[ "$rc" = 2 ] && ok "env -S \"rm 'a\\c' <main>/src/a.kt\" (\\c literal in single quotes) from the worktree: blocked" || fail "env -S with \\c in single quotes: rc $rc"
# \c inside "…" is an env error (nothing runs): a line the scanner cannot read as env does is never waved through - its operands are judged
guard "$H" "$W" "env -S \"rm \\\"a\\c\\\" $M/src/a.kt\""; rc=$?
[ "$rc" = 2 ] && ok "env -S 'rm \"a\\c\" <main>/src/a.kt' (env refuses it) from the worktree: blocked, not waved through" || fail "env -S with \\c in double quotes: rc $rc"
# env -S expands ${VARNAME} outside single quotes (and refuses a bare $VARNAME): the word that comes out is not the text written, so a line with
# one is never read as text (OpenCodeReview delta 14/10: `rm ${HOME}/…` stayed a relative operand, resolved in the worktree, and passed)
guard "$H" "$M" "env -S 'rm \${HOME}/src/a.kt'"; rc=$?
[ "$rc" = 2 ] && ok "env -S 'rm \${HOME}/src/a.kt' (expanded by env) in the main checkout: blocked as unparsed" || fail "env -S with \${HOME} in main: rc $rc"
guard "$H" "$M" "env -S 'rm \$HOME/src/a.kt'"; rc=$?
[ "$rc" = 2 ] && ok "env -S 'rm \$HOME/src/a.kt' (a bare \$: env refuses it) in the main checkout: blocked as unparsed" || fail "env -S with a bare \$HOME in main: rc $rc"
# The oracle is env itself: the operands targets() reads from `env -S 'rm LINE'` are the words this machine's env makes of LINE; a line env
# refuses must come back as an "unparsed" hit (the callers' fail-closed kind), never as a cut-off word list. A line env EXPANDS (${VAR}) is
# unparsed on purpose too: what the variable holds is not known here.
env_oracle() { python3 -I - "$DEVKIT_DIR/hooks" > "$TMP/diff.out" <<'PY'
import shlex, subprocess, sys
sys.dont_write_bytecode = True
sys.path.append(sys.argv[1])
import shell_writes as sw
probe = subprocess.run(["env", "-S", "/usr/bin/printf x"], capture_output=True, text=True)
if probe.returncode or probe.stdout != "x":   # no -S (or no /usr/bin/printf) here: no oracle, and a failure of every line would be this host's
    print("SKIP env -S is not usable here")
    sys.exit(3)
PRINT = "/usr/bin/printf [%s] x "          # `x` first: a line of no words and one of an empty word print the same
LINES = [r"a b", r"'a\c' b", r'"a\c" b', r"a\c b", r"'a\_b' c", r'"a\_b" c', r"a\_b c", r"a\_\_b", r"\_a b\_", r"'f\'g' h",
         r"'a\\b' c", r"'a\xb' c", r"a\xb c", r'"a\"b" c', r"a\'b c", r"'a'b c", r"'' c", r"'ab c", r'"ab c', "a\\", r'"a\tb" c',
         r"a\nb c", "a\tb", r"a\$b c", r"'a\c'\_b", r'"a b" "c d"',
         r"${HOME} b", r"${} b", r"$HOME b", r"'${HOME}' b", r'"${HOME}" b', r"\${HOME} b", r"a$ b", r'"a$" b', r"${HOME b", r"${NOPE_UNSET}x b"]
EXPANDS = {r"${HOME} b", r'"${HOME}" b', r"${NOPE_UNSET}x b"}   # env accepts these and substitutes: the scanner must still call them unparsed
bad = 0
for line in LINES:
    real = subprocess.run(["env", "-S", PRINT + line], capture_output=True, text=True)
    got = sw.targets("env -S " + shlex.quote("rm " + line), "/w")
    unparsed = any(k == "unparsed" for k, _t, _h in got)
    ops = [t for k, t, _h in got if k == "file"]
    if real.returncode or line in EXPANDS:      # env refuses the line (nothing runs, any operand list is safe) or expands it: the scanner must say it could not read it
        ok, want = unparsed, "an unparsed hit"
    else:
        want = [w for w in real.stdout[1:-1].split("][")[1:] if w]    # (an empty word is no operand)
        ok = not unparsed and ops == want
    print(("PASS " if ok else "FAIL ") + repr(line) + ("" if ok else f": scanner gave {ops} unparsed={unparsed}, want {want}"))
    bad += not ok
sys.exit(1 if bad else 0)
PY
}
env_oracle; rc=$?
if [ "$rc" = 3 ]; then echo "- skipped: this env has no -S, so there is nothing to compare the env -S line splitting with"
elif [ "$rc" = 0 ]; then ok "env -S line splitting: $(grep -c '^PASS' "$TMP/diff.out") lines read as this machine's env reads them"
else fail "env -S line splitting differs from env: $(grep -c '^FAIL' "$TMP/diff.out") line(s)"; grep '^FAIL' "$TMP/diff.out" | head -8; fi
# on a host whose env has no -S (BusyBox / Alpine, coreutils < 8.30) every line would fail for the host's reason: the block says so and skips
mkdir -p "$TMP/noS" && printf '#!/bin/sh\ncase "$1" in -S*) echo "env: invalid option -- S" >&2; exit 125;; esac\nexec /usr/bin/env "$@"\n' > "$TMP/noS/env" && chmod +x "$TMP/noS/env"
PATH="$TMP/noS:$PATH" env_oracle; rc=$?
[ "$rc" = 3 ] && ok "  … with an env that has no -S the oracle block is skipped (exit 3), not failed line by line" \
  || fail "  … env without -S: rc $rc, $(grep -c '^FAIL' "$TMP/diff.out") FAIL line(s)"
# `git -C ~/x …`: the shell expands ~ before git sees it, the scanner joined `~/x` to the cwd (OpenCodeReview 14/10, issues-bugs.md
# A.4 (c)): a commit into the main checkout from the worktree went through, one into the worktree from the main checkout's cwd was
# blocked. HOME = the fixture dir, so ~/main is the main checkout and ~/wt the worktree.
HOME="$TMP" guard "$H" "$W" "git -C ~/main commit -qm x"; rc=$?
[ "$rc" = 2 ] && ok "git -C ~/<main> commit from the worktree: blocked" || fail "git -C ~/main commit from the worktree: rc $rc"
HOME="$TMP" guard "$H" "$M" "git -C ~/wt commit -qm x"; rc=$?
[ "$rc" = 0 ] && ok "git -C ~/<worktree> commit from the main checkout's cwd: allowed" || fail "git -C ~/wt commit from main's cwd: rc $rc $(cat "$TMP/err")"

mkdir -p "$TMP/partial" && cp "$H" "$TMP/partial/worktree_guard.sh"   # a partial install: no shell_writes.py beside it
guard "$TMP/partial/worktree_guard.sh" "$M" "cp /tmp/x src/b.kt"; rc=$?
[ "$rc" = 2 ] && grep -q "shell_writes.py could not be loaded" "$TMP/err" && ok "shell_writes.py missing: the Bash call is blocked with the reason" \
  || fail "missing module: rc $rc $(cat "$TMP/err")"

if [ "$FAILS" -ne 0 ]; then echo "worktree_guard shell_writes: $FAILS FAILED"; exit 1; fi
echo "worktree_guard shell_writes: all checks passed"
