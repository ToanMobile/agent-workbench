#!/usr/bin/env bash
# T0237 (03/11, replay of 1.248 trunk-mode refusals over 7 days): 204 calls were refused at bin/session_lock.py _bash_trunk_write only
# because a redirect / file target held a variable the line does not assign statically - `cat > "$TMPDIR/b.md"`, `> $S/$t.log` in a
# for loop, `> /tmp/r86/$f.png` - while every one of them lands outside main. Known-prefix rule: such a target is no write into main
# when the literal directory before its first unknown variable lies outside main and is not an ancestor of it (or lies in another
# checkout), and the rest holds no `..`; `$TMPDIR` / `$HOME` take the hook's environment value unless the line assigns them.
# Everything else stays fail closed: no prefix, an ancestor of main, main itself, a literal `..`, a cd the line cannot tell.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_ALLOW_SHARED_CHECKOUT
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0
M="$TMP/main"; W="$M/.claude/worktrees/s1"; O="$TMP/outside"
mkdir -p "$M/src" "$O" && git -C "$M" init -q -b main && git -C "$M" config user.email t@t && git -C "$M" config user.name t
printf '/.claude/worktrees/\n' > "$M/.gitignore"
echo a > "$M/src/a.py" && echo r > "$M/README.md" && git -C "$M" add -A && git -C "$M" commit -qm i
git -C "$M" worktree add -q --detach "$W" HEAD
git -C "$M" config devkit.trunkMode true

python3 - "$DEVKIT_DIR" "$M" "$W" "$O" > "$TMP/unit" 2>&1 <<'PY'
import os, sys
dk, m, w, o = sys.argv[1:5]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
main, sw = sl.trunk_main(m)
assert main and sw, "trunk mode not seen"
parent = os.path.dirname(m)
B = lambda c: ("Bash", {"command": c}, c)
cases = [   # (want, label, cwd, env TMPDIR, call)
    # must still refuse
    (True, "no literal prefix: \"$UNKNOWN/README.md\"", w, o, B('echo x > "$UNKNOWN/README.md"')),
    (True, "prefix is an ancestor of main: <parent>/$x/README.md", w, o, B(f'echo x > {parent}/$x/README.md')),
    (True, "prefix is main itself: <main>/src/$f", w, o, B(f'echo x > {m}/src/$f')),
    (True, "literal .. after the unknown variable", w, o, B(f'echo x > {o}/$f/../../main/README.md')),
    (True, "literal .. before the unknown variable", w, o, B(f'echo x > {o}/../main/$f')),
    (True, "TMPDIR assigned to main on the line", w, o, B(f'TMPDIR={m}; echo x > "$TMPDIR/README.md"')),
    (True, "environment TMPDIR inside main", w, m + "/src", B('cat > "$TMPDIR/$f" <<\'EOF\'\nx\nEOF')),
    (True, "TMPDIR reassigned from an unknown value", w, o, B('TMPDIR=$Q; echo x > "$TMPDIR/$f"')),
    (True, "cd to an unknown dir, then a relative target with a variable", w, o, B('cd "$Q" && echo x > out/$f')),
    (True, "relative prefix run in main", m, o, B('echo x > src/$f')),
    (True, "backtick before any literal directory", w, o, B('echo x > `pwd`/$f')),
    (True, "chained variable from main: B=$M; > \"$B/$f\"", w, o, B(f'M={m}; B=$M; echo x > "$B/$f"')),
    # clean-context review 03/11: each was a fail-open of the first cut
    (True, "nested script: the outer line sets HOME to main", w, o, B(f"echo 'echo x > $HOME/README.md' | HOME={m} sh")),
    (True, "cd - back to main, then a relative target", w, o, B(f'cd {m}; cd {o}; cd -; echo x > src/$f')),
    (True, "~- (OLDPWD) prefix after a cd from main", w, o, B(f'cd {m}; cd {o}; echo x > ~-/src/$f')),
    (True, "a glob in the literal head expands to main", w, o, B(f'cp a {m[:-1]}*/src/$f')),
    (True, "a ? glob in the literal head", w, o, B(f'echo x > {m[:-1]}?/src/$f')),
    (True, "a brace list in the literal head", w, o, B(f'cp a {{{m},/x}}/src/$f')),
    (True, "brace-built .. in the tail", w, o, B(f'cp a {o}/$x/.{{.,}}/main/README.md')),
    (True, "source before $TMPDIR keeps no seed", w, o, B(f'source {o}/env.sh; echo x > $TMPDIR/$f')),
    # Grok review 03/11 (round 2): values and shells the line itself builds
    (True, "assignment in a ( ) subshell does not reach the parent", w, o, B(f'D={m}; (D={o}/sub); echo x > "$D/$f"')),
    (True, "assignment in a pipeline stage does not reach the parent", w, o, B(f'D={m}; D={o}/sub | true; echo x > "$D/$f"')),
    (True, "assignment in $( ) does not reach the parent", w, o, B(f'D={m}; v=$(D={o}/sub; echo 1); echo x > "$D/$f"')),
    (True, "source then a relative prefix", w, o, B(f'source {o}/go.sh; echo x > src/$f')),
    (True, ". (dot) then a relative prefix", w, o, B(f'. {o}/go.sh; echo x > src/$f')),
    (True, "for loop value with ..", w, o, B(f'S={o}/sub; for t in ../../main/README.md; do echo x > "$S/$t"; done')),
    (True, "declare value with ..", w, o, B(f'declare f=../../main/README.md; echo x > "{o}/sub/$f"')),
    (True, "printf -v value with ..", w, o, B(f'printf -v f %s ../../main/README.md; echo x > "{o}/sub/$f"')),
    (True, "here-string read value with ..", w, o, B(f'while read f; do echo x > "{o}/sub/$f"; done <<< "../../main/README.md"')),
    (True, "quoted tilde is a folder named ~ in cwd", m, o, B('mkdir -p "~/notes" && echo x > "~/notes/$f"')),
    # must pass (all land outside main)
    (False, "environment TMPDIR outside main: cat > \"$TMPDIR/b.md\" heredoc", m, o, B('cat > "$TMPDIR/b.md" <<\'EOF\'\n[builder] blocked\nEOF')),
    (False, "static S outside main + loop variable: > $S/$t.log", m, o, B(f'S={o}/sc; for t in a b; do echo x > $S/$t.log; done')),
    (False, "literal prefix outside main + loop variable", m, o, B(f'for f in a; do echo x > {o}/r86/$f.png; done')),
    (False, "prefix inside the nested worktree", m, o, B(f'echo x > {w}/out/$f')),
    (False, "mkdir -p under a literal prefix outside main", m, o, B(f'mkdir -p {o}/x/$b')),
    (False, "partial last component: > <outside>/gf_$t.log", m, o, B(f'for t in a; do echo x > {o}/gf_$t.log; done')),
]
fails = 0
for want, label, cwd, tmpdir, (tool, ti, cmd) in cases:
    os.environ["TMPDIR"] = tmpdir
    got = sl.trunk_write(tool, ti, cmd, cwd, main, sw, "t")
    print(("✔" if bool(got) == want else "✖"), ("refused" if got else "allowed"), "-", label)
    fails += bool(got) != want
sys.exit(1 if fails else 0)
PY
rc=$?
cat "$TMP/unit"
[ "$rc" -eq 0 ] || FAILS=$((FAILS + 1))
if [ "$FAILS" -eq 0 ]; then echo "PASS test_session_lock_trunk_var_prefix"; exit 0; fi
echo "FAIL test_session_lock_trunk_var_prefix ($FAILS)"; exit 1
