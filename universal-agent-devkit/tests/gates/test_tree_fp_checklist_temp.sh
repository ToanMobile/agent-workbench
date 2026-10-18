#!/usr/bin/env bash
# Regression test (A15 lane, third round, 2026-10-15): the temp file of the checklist save is not part of the tree fingerprint.
# bin/regression_checklist.py save() writes .agents/regression_status.json through tempfile.mkstemp(dir=.agents, prefix=".regression_status."): a
# file named ".regression_status." + 8 random characters of [a-z0-9_] that sits in .agents/ until os.replace. bin/post-fix-gate.py releases test_run.lock
# BEFORE it saves the checklist, so on a loaded machine a run B that wins the lock meanwhile fingerprints the tree with that file in it: another
# fingerprint than the receipt of run A, B refuses the receipt and runs every suite again (wasted work, never a false PASS; tests/gates/test_gate_lock_
# receipt_gap.sh failed one run in a few under load: "suite executions 2, B reused=False"). Reviewer probe: a temp file held 3 s -> 2 of 2 red; the same
# hold at an excluded path -> 3 of 3 green. bin/tree_fp.py EXCLUDE now names exactly that shape and nothing wider.
# The other two mkstemp prefixes of the file are not tree content either: ".tmp." (_write_bytes) lands in .agents/regression_journal/, whose own
# .gitignore ("*") hides it from `git add -A`, and ".worktree_checklist." lands in the git dir.
#   T1  a temp-shaped file (digits, underscore, letters) in .agents/: the fingerprint does not move
#   T2  near misses MUST move it: 7 or 9 characters, upper case (not mkstemp's alphabet), a suffix, no leading dot, another folder, the ".tmp." prefix
#       at the top of .agents/, and a real edit of a file in .agents/
#   T3  the journal folder's ".tmp." file: unmoved (git-ignored, so no entry is needed)
#   T4  the REAL writer: save() with os.replace held open: the temp file exists, is named as T1 says, and the fingerprint taken at that moment is the
#       one taken before (a writer whose prefix or name length drifts from the exclusion is caught here)
# bash 3.2 and Python 3.9 compatible. TFP_SCRIPT=<bin/tree_fp.py of another copy of the kit> tests that copy (a mutant must go red).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TFP="${TFP_SCRIPT:-$DEVKIT_DIR/bin/tree_fp.py}"
BIN="$(dirname "$TFP")"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
mkdir -p "$R/src" "$R/.agents/sub"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
printf 'fun ok() = 1\n' > "$R/src/Core.kt"
printf 'rule one\n' > "$R/.agents/rules.md"
printf 'sub one\n' > "$R/.agents/sub/s.md"
git -C "$R" add -A && git -C "$R" commit -qm init
fp() { python3 -I "$TFP" "$R"; }
BASE="$(fp)"
[ -n "$BASE" ] && ok "fingerprint computed" || { bad "no fingerprint"; exit 1; }

# T1: what mkstemp(prefix=".regression_status.") can produce
for name in abcd1234 a1_b2c3d zzzzzzzz 00000000 _______x; do
  printf '{}' > "$R/.agents/.regression_status.$name"
  [ "$(fp)" = "$BASE" ] && ok "T1: .agents/.regression_status.$name (mkstemp shape): fingerprint unchanged" || bad "T1: .agents/.regression_status.$name moved the fingerprint"
  rm -f "$R/.agents/.regression_status.$name"
done

# T2: anything else is content and moves it
t2() { # $1 = path under the repo
  mkdir -p "$(dirname "$R/$1")"; printf 'x' > "$R/$1"
  [ "$(fp)" != "$BASE" ] && ok "T2: $1 moves the fingerprint (not a checklist temp file)" || bad "T2: $1 did NOT move the fingerprint (the exclusion is too wide)"
  rm -f "$R/$1"
}
t2 .agents/.regression_status.abcd123          # 7 characters
t2 .agents/.regression_status.abcd12345        # 9 characters
t2 .agents/.regression_status.ABCD1234         # upper case: not in tempfile's alphabet
t2 .agents/.regression_status.abcd-234         # a dash: not in tempfile's alphabet
t2 .agents/.regression_status.json.bak
t2 .agents/regression_status.abcd1234          # no leading dot
t2 .agents/sub/.regression_status.abcd1234     # another folder
t2 src/.regression_status.abcd1234
t2 .agents/.tmp.abcd1234                       # the _write_bytes prefix, not at its real place
printf 'rule one, edited\n' > "$R/.agents/rules.md"
[ "$(fp)" != "$BASE" ] && ok "T2: a real edit of .agents/rules.md moves the fingerprint" || bad "T2: an edit of .agents/rules.md did not move the fingerprint"
printf 'rule one\n' > "$R/.agents/rules.md"
[ "$(fp)" = "$BASE" ] && ok "T2 control: the file put back: the fingerprint is the base again" || bad "T2 control: the fingerprint did not return to the base"

# T3: the journal folder hides its own temp files (its .gitignore is "*", written by regression_checklist._jdir)
mkdir -p "$R/.agents/regression_journal/snapshots"
printf '*\n' > "$R/.agents/regression_journal/.gitignore"
BASE3="$(fp)"
printf '{}' > "$R/.agents/regression_journal/.tmp.abcd1234"; printf '{}' > "$R/.agents/regression_journal/snapshots/.tmp.wxyz9876"
[ "$(fp)" = "$BASE3" ] && [ "$BASE3" = "$BASE" ] && ok "T3: .tmp.* in .agents/regression_journal (git-ignored): fingerprint unchanged, no entry needed" || bad "T3: a journal temp file moved the fingerprint"
rm -rf "$R/.agents/regression_journal"

# T4: the real writer, os.replace held open: the temp file is there, the fingerprint is not different
T4="$(python3 -I - "$BIN" "$R" <<'PY' 2>&1
import os, re, sys
bin_dir, root = sys.argv[1:3]
sys.path.insert(0, bin_dir)
import regression_checklist as rc
import tree_fp
data = {"version": 1, "items": {}}
rc.save(root, data, stale=False)            # once, so that every file a save creates for the first time (inbox, journal, view) already exists
before = tree_fp.tree_fingerprint(root)
seen = []
real_replace = os.replace
def replace(src, dst, *a, **k):
    if os.path.basename(str(dst)) == "regression_status.json":
        temps = [n for n in os.listdir(os.path.join(root, ".agents")) if n.startswith(".regression_status.")]
        seen.append((temps, tree_fp.tree_fingerprint(root)))
    return real_replace(src, dst, *a, **k)
os.replace = replace
rc.save(root, dict(data, meta={"t4": 1}), stale=False)   # nội dung đổi thật: save() cùng byte không ghi lại nữa (18/10)
os.replace = real_replace
temps, during = seen[0] if seen else ([], None)
print("temps=%s" % ",".join(temps))
print("shape=%s" % ("ok" if len(temps) == 1 and re.fullmatch(r"\.regression_status\.[a-z0-9_]{8}", temps[0]) else "BAD"))
print("fp=%s" % ("same" if during == before else "DIFFERENT"))
PY
)"
if printf '%s\n' "$T4" | grep -q '^shape=ok$' && printf '%s\n' "$T4" | grep -q '^fp=same$'; then
  ok "T4: save() with os.replace held open: one temp file shaped .regression_status.<8 of [a-z0-9_]> exists and the fingerprint is the one before the save"
else
  bad "T4: the real writer: $(printf '%s' "$T4" | tr '\n' ' ')"
fi

echo
[ "$FAILS" -eq 0 ] && echo "tree_fp checklist temp: all checks passed" || { echo "tree_fp checklist temp: $FAILS FAILED"; exit 1; }
