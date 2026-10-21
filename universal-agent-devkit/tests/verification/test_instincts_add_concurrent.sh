#!/usr/bin/env bash
# Issue #14: `instincts.py add` copied the template onto a missing target OUTSIDE the file lock (cmd_add): a concurrent writer that had
# already appended its lesson was truncated by the second writer's copyfile. The race window is microseconds, so the oracle is the
# invariant that closes it: when the lock on the target is taken, cmd_add has not created or filled the target yet (seeding is inside the
# flock), and the lesson still lands after the template. A concurrent burst then checks nothing is lost.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
mkdir -p "$D/p1" "$D/p2"
export DEVKIT_LANG=en
FAIL=0

CLAUDE_PROJECT_DIR="$D/p1" python3 - "$DEVKIT_ROOT" "$D/p1/.agents/instincts.md" <<'PY' || FAIL=1
import fcntl, os, sys, types
sys.path.insert(0, os.path.join(sys.argv[1], "bin"))
import instincts
target = sys.argv[2]
sizes = []
real = fcntl.flock
def spy(f, op):
    if op == fcntl.LOCK_EX and not sizes:
        sizes.append(os.path.getsize(target) if os.path.exists(target) else 0)
    return real(f, op)
instincts.fcntl = types.SimpleNamespace(flock=spy, LOCK_EX=fcntl.LOCK_EX)
args = types.SimpleNamespace(file=target, title="Seed under lock", cause=None, rule="r", symptom=None, check=None,
                             force=False, dry_run=False, generic=False)
rc = instincts.cmd_add(args)
text = open(target).read()
ok = rc == 0 and sizes == [0] and "Seed under lock" in text and text.startswith(open(os.path.join(sys.argv[1], "templates", "instincts.template.md")).readline())
print(("✔" if ok else "✖") + f" seeded inside the flock (rc={rc}, target size at lock time={sizes})")
sys.exit(0 if ok else 1)
PY

# `add --from-json` (cmd_import) cũng phải seed trong flock: lúc lấy khoá file đích vẫn rỗng, template đứng trước bài học
mkdir -p "$D/p3"
printf '[{"verdict": "INSTINCT", "title": "Imported under lock", "rule": "r"}]' > "$D/p3/items.json"
CLAUDE_PROJECT_DIR="$D/p3" python3 - "$DEVKIT_ROOT" "$D/p3/.agents/instincts.md" "$D/p3/items.json" <<'PY' || FAIL=1
import fcntl, os, sys, types
sys.path.insert(0, os.path.join(sys.argv[1], "bin"))
import instincts
target = sys.argv[2]
sizes = []
real = fcntl.flock
def spy(f, op):
    if op == fcntl.LOCK_EX and not sizes:
        sizes.append(os.path.getsize(target) if os.path.exists(target) else 0)
    return real(f, op)
instincts.fcntl = types.SimpleNamespace(flock=spy, LOCK_EX=fcntl.LOCK_EX)
args = types.SimpleNamespace(file=target, from_json=sys.argv[3], force=False, dry_run=False)
rc = instincts.cmd_import(args)
text = open(target).read()
ok = rc == 0 and sizes == [0] and "Imported under lock" in text and text.startswith(open(os.path.join(sys.argv[1], "templates", "instincts.template.md")).readline())
print(("✔" if ok else "✖") + f" import seeded inside the flock (rc={rc}, target size at lock time={sizes})")
sys.exit(0 if ok else 1)
PY

# Người thua cuộc đua (file đã được người khác seed + ghi trước khi nó lấy được khoá) không được in "Created … from the template"
mkdir -p "$D/p4"
CLAUDE_PROJECT_DIR="$D/p4" python3 - "$DEVKIT_ROOT" "$D/p4/.agents/instincts.md" <<'PY' || FAIL=1
import contextlib, fcntl, io, os, sys, types
sys.path.insert(0, os.path.join(sys.argv[1], "bin"))
import instincts
target = sys.argv[2]
real = fcntl.flock
won = []
def spy(f, op):
    if op == fcntl.LOCK_EX and not won:   # người thắng ghi xong ngay trước khi ta lấy khoá
        won.append(1)
        with open(target, "a", encoding="utf-8") as w:
            w.write("# Winner header\n\n### [INSTINCT-001] Winner lesson\n")
    return real(f, op)
instincts.fcntl = types.SimpleNamespace(flock=spy, LOCK_EX=fcntl.LOCK_EX)
args = types.SimpleNamespace(file=target, title="Loser lesson", cause=None, rule="r", symptom=None, check=None,
                             force=False, dry_run=False, generic=False)
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = instincts.cmd_add(args)
text = open(target).read()
ok = rc == 0 and "Created" not in buf.getvalue() and "Winner lesson" in text and "Loser lesson" in text
print(("✔" if ok else "✖") + f" no 'Created' when another writer seeded first (rc={rc}, out={buf.getvalue().strip()!r})")
sys.exit(0 if ok else 1)
PY

N=24
for i in $(seq 1 $N); do CLAUDE_PROJECT_DIR="$D/p2" python3 "$DEVKIT_ROOT/bin/instincts.py" add "Concurrent trap number $i" --rule "r$i" >/dev/null 2>&1 & done
wait
F="$D/p2/.agents/instincts.md"
got=$(grep -c '^### .*Concurrent trap number' "$F" 2>/dev/null)
ids=$(grep -o '^### \[INSTINCT-[0-9]*\]' "$F" | sort | uniq -d | wc -l | tr -d ' ')
[ "$got" = "$N" ] && [ "$ids" = 0 ] || { echo "✖ burst: $got of $N lessons, $ids duplicate ids"; FAIL=1; }
[ "$FAIL" = 0 ] && echo "✅ test_instincts_add_concurrent: passed" || { echo "❌ test_instincts_add_concurrent: failed"; exit 1; }
