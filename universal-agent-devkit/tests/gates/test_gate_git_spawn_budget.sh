#!/usr/bin/env bash
# Regression test (2026-10-22, suite speed-up): one run of bin/post-fix-gate.py asks git the same static question once, not eight times.
# `git rev-parse --absolute-git-dir`, `--show-prefix`, `--show-toplevel`, `--git-common-dir` and `--git-path objects` cannot change while a gate
# process lives, yet bin/post-fix-gate.py and bin/tree_fp.py spawned each of them from several places: 8 x --absolute-git-dir and 18 rev-parse in
# all, in a run of 37 git spawns. Over the 264 cases of tests/gates/test_postfix_gate.sh that was 3800 of 7200 git spawns, ~7 ms each. They go
# through tree_fp.rev_parse_static now (one spawn per distinct question and process).
#   T1  a dirty-tree `--run-tests` run: no identical `git rev-parse <args>` more than once per process (HEAD-dependent queries and
#       in_linked_worktree's 3-argument query are exempt); a missing spawn log fails instead of passing blind
#   T2  the verdict is unchanged by the cache: exit 0 and a report that records REG-1 PASS
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/heavy-slots"
mkdir -p "$SB_HEAVY_SLOT_DIR" "$TMP/sc" "$TMP/repo/src"

FAILS=0
ok() { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# sitecustomize: log every `git rev-parse` a python process of the gate spawns (argv after the -C <dir>), one per line.
cat > "$TMP/sc/sitecustomize.py" <<'PY'
import os
import subprocess

_orig = subprocess.Popen.__init__
_log = os.environ.get("SPAWN_LOG")


def _init(self, args, *a, **k):
    _orig(self, args, *a, **k)
    if _log and not isinstance(args, str) and len(args) > 3 and args[0] == "git":
        rest = [str(x) for x in args[1:]]
        while rest and rest[0] in ("-C", "-c"):
            rest = rest[2:]
        if rest and rest[0] == "rev-parse":
            with open(_log, "a") as f:
                f.write("%d %s\n" % (os.getpid(), " ".join(rest)))   # per process: a child may ask once itself


subprocess.Popen.__init__ = _init
PY

cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt

SPAWN_LOG="$TMP/spawns.txt" PYTHONPATH="$TMP/sc" CLAUDE_PROJECT_DIR="$TMP/repo" \
  python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests > "$TMP/out.txt" 2>&1
rc=$?

# T1: a repeated static query. HEAD / --short HEAD / -q --verify answer what the commit is, not where the repo is: not cached, not counted.
# Exempt: HEAD / --verify, and in_linked_worktree's 3-argument form (regression_checklist.py asks it fresh on purpose: its test plants a
# commondir between two calls in one process, tests/worktree_git/test_worktree_checklist.sh).
dups="$(grep -v -E 'HEAD|--verify|--show-toplevel --absolute-git-dir --git-common-dir' "$TMP/spawns.txt" 2>/dev/null | sort | uniq -c | awk '$1 > 1 {print}')"
if ! grep -q -- '--absolute-git-dir' "$TMP/spawns.txt" 2>/dev/null; then
  bad "spawn log missing or without rev-parse lines: the sitecustomize hook did not run, T1 would pass blind"
elif [ -z "$dups" ]; then
  ok "no static git rev-parse question is asked twice in one gate run"
else
  bad "a static git rev-parse question was asked more than once:"; echo "$dups"
fi

# T2: same verdict
[ "$rc" -eq 0 ] && ok "gate exit 0" || { bad "gate exit $rc"; tail -5 "$TMP/out.txt"; }
grep -q 'REG-1.*`PASS`' "$TMP/repo/.git/postfix-gate/last_report.md" 2>/dev/null \
  && ok "report records REG-1 PASS" || bad "report missing REG-1 PASS"

[ "$FAILS" -eq 0 ] || { echo "FAILS=$FAILS"; exit 1; }
echo "ALL PASS"
