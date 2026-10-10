#!/usr/bin/env bash
# Regression test: how hooks/regression_gate.sh writes the state file that every session of a project shares
# (.claude/audit-gate/regression_gate.state.json). DevKit backlog #2, 2026-10-10. The file is read at the start of a Stop and written
# minutes later, so the session that wrote last erased the entries of the one that wrote first. save_state() is now a read-merge-write
# under fcntl.flock: only what THIS process changed since it last read or wrote the file (a three-way merge against _base) is put onto
# what is on disk. A fresh-context review found that the end-to-end test alone left 12 of 15 mutants of this code alive; this file tests
# the functions themselves: _merge_into and save_state are cut out of the hook source and run on their own, with a second process.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${MERGE_HOOK:-$DEVKIT_DIR/hooks/regression_gate.sh}"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# The helpers of the hook: from "_GONE = object()" to the comment that opens the next block. The Python of the hook sits in a bash
# string, so the text is plain Python and can be run as it is.
cat > "$TMP/lib.py" <<'PYX'
import copy, errno, fcntl, json, os, sys, tempfile, time

def load_helpers(hook, state, state_file, note=None, slow_merge=0.0, flock=None):
    """Run the helpers of the hook on `state` (what this process read at its start) and return their namespace."""
    src = open(hook, encoding="utf-8").read()
    body = src[src.index("_GONE = object()"):src.index("# Degraded mode: the last result")]
    fl = type("FL", (), {"LOCK_EX": fcntl.LOCK_EX, "LOCK_NB": fcntl.LOCK_NB, "flock": staticmethod(flock or fcntl.flock)})
    ns = {"copy": copy, "errno": errno, "fcntl": fl, "json": json, "os": os, "tempfile": tempfile, "time": time,
          "state": state, "state_file": state_file, "note": note or (lambda m: None)}
    exec(body, ns)
    if slow_merge:
        real = ns["_merge_into"]
        def slow(disk, mine, base):
            time.sleep(slow_merge)
            return real(disk, mine, base)
        ns["_merge_into"] = slow
    return ns

def disk(path):
    try:
        return json.load(open(path, encoding="utf-8"))
    except Exception:
        return None
PYX

run_py() { python3 -I - "$@"; }
SF="$TMP/state.json"

# (1) a deletion by this process reaches the disk, and what another session added meanwhile survives (no resurrection, no loss).
rm -f "$SF"; echo '{"repeat":{"A":1,"B":2}}' > "$SF"
run_py "$HOOK" "$SF" "$TMP" <<'PYX' && ok "(1) three-way merge: my deletion lands, the other session's new entry stays" || fail "(1) deletion or concurrent entry lost"
import sys, json, copy
sys.path.insert(0, sys.argv[3]); import lib
hook, sf = sys.argv[1], sys.argv[2]
state = lib.disk(sf)
ns = lib.load_helpers(hook, state, sf)
state["repeat"].pop("A")
json.dump({"repeat": {"A": 1, "B": 2, "C": 3}}, open(sf, "w"))      # another session wrote C after my read
ns["save_state"]()
assert lib.disk(sf) == {"repeat": {"B": 2, "C": 3}}, lib.disk(sf)
PYX

# (2) _base follows my own save: an entry I wrote earlier is not written again over a newer value of another session.
rm -f "$SF"; echo '{"attempts":{"f":0}}' > "$SF"
run_py "$HOOK" "$SF" "$TMP" <<'PYX' && ok "(2) after a save the base is refreshed: my old change does not overwrite a newer value" || fail "(2) stale base re-applied an old change"
import sys, json
sys.path.insert(0, sys.argv[3]); import lib
hook, sf = sys.argv[1], sys.argv[2]
state = lib.disk(sf)
ns = lib.load_helpers(hook, state, sf)
state["attempts"]["f"] = 1; ns["save_state"]()
json.dump({"attempts": {"f": 2}}, open(sf, "w"))                    # another session counted a second block
state.setdefault("shown", {})["s"] = "digest"; ns["save_state"]()   # I only changed something else
d = lib.disk(sf)
assert d["attempts"] == {"f": 2} and d["shown"] == {"s": "digest"}, d
PYX

# (3) a scalar I did not change keeps the value another session wrote; one I changed is written.
rm -f "$SF"; echo '{"pass_fp":"x","untested_fp":"u"}' > "$SF"
run_py "$HOOK" "$SF" "$TMP" <<'PYX' && ok "(3) scalars: unchanged keeps the newer disk value, changed is written" || fail "(3) scalar merge wrong"
import sys, json
sys.path.insert(0, sys.argv[3]); import lib
hook, sf = sys.argv[1], sys.argv[2]
state = lib.disk(sf)
ns = lib.load_helpers(hook, state, sf)
json.dump({"pass_fp": "y", "untested_fp": "u"}, open(sf, "w"))     # another session passed on other content
state["untested_fp"] = "u2"; ns["save_state"]()
d = lib.disk(sf)
assert d["pass_fp"] == "y" and d["untested_fp"] == "u2", d
PYX

# (4) the file cannot be read when I save (removed, cut short, or not an object): the whole state is written, nothing already read is lost.
for kind in missing cut notdict; do
  rm -f "$SF"; echo '{"verified_head":"h","pass_fp":"p","repeat":{"A":1}}' > "$SF"
  run_py "$HOOK" "$SF" "$TMP" "$kind" <<'PYX' && ok "(4 $kind) unreadable state at save time: the state this process read is written whole" || fail "(4 $kind) values read at the start were lost"
import sys, os, json
sys.path.insert(0, sys.argv[3]); import lib
hook, sf, kind = sys.argv[1], sys.argv[2], sys.argv[4]
state = lib.disk(sf)
ns = lib.load_helpers(hook, state, sf)
if kind == "missing": os.remove(sf)
elif kind == "cut": open(sf, "w").write('{"verified_head": "h", "rep')
else: open(sf, "w").write("[]")
state["repeat"]["B"] = 2; ns["save_state"]()
d = lib.disk(sf)
assert d == {"verified_head": "h", "pass_fp": "p", "repeat": {"A": 1, "B": 2}}, d
PYX
done

# (5) the size limits apply to what is written: 60 entries on disk, mine added, at most 50 kept, mine among them.
rm -f "$SF"; python3 -I -c 'import json,sys; json.dump({"repeat": {"s%02d" % i: {"k": i} for i in range(60)}}, open(sys.argv[1], "w"))' "$SF"
run_py "$HOOK" "$SF" "$TMP" <<'PYX' && ok "(5) trimming keeps at most 50 entries on disk and the one just written" || fail "(5) trim on the wrong copy"
import sys
sys.path.insert(0, sys.argv[3]); import lib
hook, sf = sys.argv[1], sys.argv[2]
state = lib.disk(sf)
ns = lib.load_helpers(hook, state, sf)
state["repeat"]["mine"] = {"k": "mine"}; ns["save_state"]()
d = lib.disk(sf)
assert len(d["repeat"]) <= 50 and "mine" in d["repeat"], (len(d["repeat"]), list(d["repeat"])[-3:])
PYX

# (6) two processes save at the same moment: the lock keeps the read-merge-write whole. The merge is slowed down (0.4 s) inside the
# critical section, so without the lock both read the same disk and the later write erases the first one's entry.
rm -f "$SF" "$SF.lock"; echo '{}' > "$SF"
cat > "$TMP/proc.py" <<'PYX'
import sys
sys.path.insert(0, sys.argv[1]); import lib
hook, sf, sid = sys.argv[2], sys.argv[3], sys.argv[4]
state = lib.disk(sf)
ns = lib.load_helpers(hook, state, sf, slow_merge=0.4)
state.setdefault("repeat", {})[sid] = {"key": sid}
ns["save_state"]()
PYX
python3 -I "$TMP/proc.py" "$TMP" "$HOOK" "$SF" pa & p1=$!
python3 -I "$TMP/proc.py" "$TMP" "$HOOK" "$SF" pb & p2=$!
wait "$p1" "$p2"
run_py "$SF" <<'PYX' && ok "(6) two processes saving at once: both entries are on disk (the lock works)" || fail "(6) a concurrent save erased the other one"
import json, sys
d = json.load(open(sys.argv[1]))
assert sorted(d.get("repeat", {})) == ["pa", "pb"], d
PYX

# (7) a filesystem without flock (SMB, NFS, FUSE: ENOTSUP) is not a lock held by someone: no 3 s wait per save, and the merge still happens.
rm -f "$SF"; echo '{"repeat":{"A":1}}' > "$SF"
run_py "$HOOK" "$SF" "$TMP" <<'PYX' && ok "(7) flock unsupported: no wait, the merge still runs" || fail "(7) waited on an unsupported flock or lost the merge"
import sys, time, errno, json
sys.path.insert(0, sys.argv[3]); import lib
hook, sf = sys.argv[1], sys.argv[2]
def no_flock(fd, op):
    raise OSError(errno.ENOTSUP, "not supported")
state = lib.disk(sf)
ns = lib.load_helpers(hook, state, sf, flock=no_flock)
state["repeat"]["B"] = 2
json.dump({"repeat": {"A": 1, "C": 3}}, open(sf, "w"))
t = time.time(); ns["save_state"](); took = time.time() - t
d = lib.disk(sf)
assert took < 1.0, took
assert d == {"repeat": {"A": 1, "B": 2, "C": 3}}, d
PYX

if [ "$FAILS" -ne 0 ]; then echo "regression gate state merge: $FAILS FAILED"; exit 1; fi
echo "regression gate state merge: all passed"
