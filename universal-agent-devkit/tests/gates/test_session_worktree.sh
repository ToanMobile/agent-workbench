#!/usr/bin/env bash
# hooks/session_worktree.py (W1 R1/R2/R7 v6, docs/workflow-improvements.md I.0): trunk mode is a per-repo opt-in read from the git config
# (`devkit.trunkMode`), WORKTREE_TRUNK_MODE=0 turns it off everywhere, and anything unreadable means the old behaviour; the worktree a
# session ENTERED (EnterWorktree) is recorded by the PostToolUse hook and project() hands it to the gates, because CLAUDE_PROJECT_DIR keeps
# naming the main checkout after EnterWorktree (code.claude.com docs, 14/10) and the gates then checked a clean main instead of the work.
# A record is honoured only for a registered linked worktree of the SAME repo: a forged one (another repo, a plain folder, a sub-folder,
# a session id with a slash) never moves the gates.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SW="$DEVKIT_DIR/hooks/session_worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset WORKTREE_TRUNK_MODE
M="$TMP/main"; W="$M/.claude/worktrees/s1"; O="$TMP/other"
for r in "$M" "$O"; do
  mkdir -p "$r" && git -C "$r" init -q -b main && git -C "$r" config user.email t@t && git -C "$r" config user.name t \
    && echo x > "$r/a.txt" && git -C "$r" add -A && git -C "$r" commit -qm i
done
git -C "$M" worktree add -q --detach "$W" HEAD && git -C "$O" worktree add -q --detach "$TMP/other-wt" HEAD && git -C "$M" worktree add -q --detach "$TMP/main-w2" HEAD
mkdir -p "$TMP/plain" "$W/sub"

# 1 trunk mode: off by default, on with `git config devkit.trunkMode true` (seen from main AND from a linked worktree), off again with
#   WORKTREE_TRUNK_MODE=0, false, a garbage value or an unreadable config; git's own forms count (bare key, any case, a trailing comment)
tm() { (cd "$1" && python3 -I "$SW" trunk-mode "$1" >/dev/null 2>&1); echo $?; }
[ "$(tm "$M")" = 1 ] && ok "no devkit.trunkMode: off" || fail "trunk mode on with no config"
git -C "$M" config devkit.trunkMode true
[ "$(tm "$M")" = 0 ] && [ "$(tm "$W")" = 0 ] && ok "devkit.trunkMode true: on, from main and from its worktree" || fail "trunk mode not seen (main $(tm "$M"), worktree $(tm "$W"))"
[ "$(WORKTREE_TRUNK_MODE=0 python3 -I "$SW" trunk-mode "$M" >/dev/null 2>&1; echo $?)" = 1 ] && ok "  … WORKTREE_TRUNK_MODE=0: off (R7)" || fail "WORKTREE_TRUNK_MODE=0 did not turn it off"
f0=$FAILS; for v in false 0 no garbage; do
  git -C "$M" config devkit.trunkMode "$v"; [ "$(tm "$M")" = 1 ] || fail "devkit.trunkMode=$v read as on"
done; [ "$FAILS" = "$f0" ] && ok "  … false / 0 / no / a garbage value: off"
git -C "$M" config --unset-all devkit.trunkMode
printf '[DevKit]\n\tTrunkMode = TRUE ; a trailing comment\n' >> "$M/.git/config"
a="$(tm "$M")"; [ "$(git -C "$M" config --bool devkit.trunkMode)" = true ] || fail "fixture: git itself does not read the line as true"
git -C "$M" config --unset-all devkit.trunkMode; printf '[devkit]\n\ttrunkmode\n' >> "$M/.git/config"
b="$(tm "$M")"; [ "$(git -C "$M" config --bool devkit.trunkMode)" = true ] || fail "fixture: git itself does not read the bare key as true"
[ "$a" = 0 ] && [ "$b" = 0 ] && ok "  … [DevKit] TrunkMode = TRUE ; comment, and a bare key: on, as git reads them" || fail "git's boolean forms not read ($a, $b)"
git -C "$M" config --unset-all devkit.trunkMode; git -C "$M" config devkit.trunkMode true
if [ "$(id -u)" = 0 ]; then echo "• root reads a mode-000 file: the unreadable-config case is skipped"; else
  chmod 000 "$M/.git/config"; r="$(tm "$M")"; chmod 644 "$M/.git/config"
  [ "$r" = 1 ] && ok "  … an unreadable config: off, never an error" || fail "unreadable config read as on ($r)"
fi

# 2 the record: EnterWorktree (PostToolUse) records the worktree, project() hands it to the gates; ExitWorktree clears it
rec() {   # rec <tool> <session> [extra json fields as k=v pairs handled below]: the PostToolUse payload on stdin of `record`
  python3 -c 'import json,sys; t,s,cwd,wt=sys.argv[1:5]; d={"hook_event_name":"PostToolUse","session_id":s,"cwd":cwd,"tool_name":t,"tool_input":{},"tool_response":({"worktreePath":wt,"message":"Entered worktree at "+wt} if wt else {"message":"left"})}; print(json.dumps(d))' "$@" \
    | CLAUDE_PROJECT_DIR="$M" python3 -I "$SW" record 2>/dev/null
}
proj() {   # proj <session> [agent_id] [transcript]: what project() answers for a Stop / tool call of that session
  python3 -c 'import json,sys; s,a,tp=sys.argv[1:4]; d={"session_id":s,"cwd":sys.argv[4],"transcript_path":tp}; a and d.update(agent_id=a); print(json.dumps(d))' "$1" "${2:-}" "${3:-}" "${4:-$M}" \
    | CLAUDE_PROJECT_DIR="$M" python3 -I "$SW" project
}
[ "$(proj s1)" = "$M" ] && ok "no record: project = CLAUDE_PROJECT_DIR (as before)" || fail "no record: $(proj s1)"
rec EnterWorktree s1 "$W" "$W"
[ "$(proj s1)" = "$W" ] && ok "after EnterWorktree: project = the session's worktree (gates check the work, not a clean main)" || fail "entered: $(proj s1)"
[ "$(sed -n 2p "$M/.claude/audit-gate/session_worktree/s1")" = "pid $$" ] && ok "  … the record carries the pid of the process the hook ran under (its parent: here this shell), what the merge gate judges the owner dead by" \
  || fail "record pid: '$(sed -n 2p "$M/.claude/audit-gate/session_worktree/s1")' (want pid $$)"
[ "$(proj s2)" = "$M" ] && ok "  … another session is not moved by it" || fail "another session moved: $(proj s2)"
git -C "$M" config devkit.trunkMode false
[ "$(proj s1 "" "" "$W/sub")" = "$W" ] && [ "$(proj s1)" = "$M" ] && ok "  … trunk mode off: the record holds only while the session is in that worktree (in main: main - a record cannot steer a session working in main)" \
  || fail "trunk off: in worktree $(proj s1 "" "" "$W/sub"), in main $(proj s1)"
git -C "$M" config devkit.trunkMode true
[ "$(proj s1 "" "" "$TMP/main-w2")" = "$M" ] && ok "  … trunk mode: not while the session is in ANOTHER worktree of the repo" || fail "trunk, other worktree: $(proj s1 "" "" "$TMP/main-w2")"
rec ExitWorktree s1 "$M" ""
[ "$(proj s1)" = "$M" ] && ok "after ExitWorktree: project = main again" || fail "exit: $(proj s1)"

# 3 a forged or stale record never moves the gates: another repo's worktree, a plain folder, a sub-folder, a removed worktree,
#   a session id that is a path
mkdir -p "$M/.claude/audit-gate/session_worktree"
mkdir -p "$TMP/decoy" && printf 'gitdir: %s\n' "$(git -C "$W" rev-parse --absolute-git-dir)" > "$TMP/decoy/.git"   # a .git file copied from a real worktree
f0=$FAILS; for bad in "$TMP/other-wt" "$TMP/plain" "$W/sub" "relative/path" "$TMP/decoy" "$M"; do
  printf '%s\n' "$bad" > "$M/.claude/audit-gate/session_worktree/s3"
  [ "$(proj s3)" = "$M" ] || fail "a record naming $bad moved the gates to $(proj s3)"
done; [ "$FAILS" = "$f0" ] && ok "a record naming another repo's worktree / a plain folder / a sub-folder / a relative path / a decoy with a copied .git file / the main checkout itself: ignored"
ln -s "$W" "$TMP/link-to-w"; printf '%s\n' "$TMP/link-to-w" > "$M/.claude/audit-gate/session_worktree/s3"   # (OCR2 11) a symlink to a real worktree of this repo is no forgery
[ "$(proj s3)" = "$W" ] && ok "  … a symlink to a real worktree of the repo resolves to that worktree (accepted)" || fail "a symlink to the real worktree: project = $(proj s3), want $W"
rm -f "$M/.claude/audit-gate/session_worktree/s3" "$TMP/link-to-w"
rec EnterWorktree s4 "$W" "$W"; git -C "$M" worktree add -q --detach "$M/.claude/worktrees/gone" HEAD
printf '%s\n' "$M/.claude/worktrees/gone" > "$M/.claude/audit-gate/session_worktree/s4"; git -C "$M" worktree remove "$M/.claude/worktrees/gone"
[ "$(proj s4)" = "$M" ] && ok "  … a worktree removed since: ignored" || fail "a removed worktree still moved the gates: $(proj s4)"
rec EnterWorktree "../../escape" "$W" "$W"
[ ! -e "$M/.claude/escape" ] && [ ! -e "$M/.claude/audit-gate/escape" ] && ok "  … a session id that is a path writes nothing" || fail "a session id with a slash wrote outside the record folder"

# 4 subagents: one the harness started in a worktree (meta worktreePath) is judged there; any other works where its session does
TP="$TMP/proj/s5.jsonl"; mkdir -p "$TMP/proj/s5/subagents" && : > "$TP"
printf '{"worktreePath": "%s"}\n' "$W" > "$TMP/proj/s5/subagents/agent-a1.meta.json"
[ "$(proj s5 a1 "$TP")" = "$W" ] && ok "a harness subagent in a worktree: project = its worktree" || fail "subagent meta: $(proj s5 a1 "$TP")"
[ "$(proj s5 a2 "$TP")" = "$M" ] && ok "  … another subagent of that session, no record: main" || fail "subagent without meta: $(proj s5 a2 "$TP")"
rec EnterWorktree s5 "$W" "$W"
[ "$(proj s5 a2 "$TP")" = "$W" ] && ok "  … with the session in a worktree: the subagent works there too" || fail "subagent of an entered session: $(proj s5 a2 "$TP")"
printf '{"worktreePath": "%s"}\n' "$TMP/other-wt" > "$TMP/proj/s5/subagents/agent-a3.meta.json"; rec ExitWorktree s5 "$M" ""
[ "$(proj s5 a3 "$TP")" = "$M" ] && ok "  … a meta naming another repo's worktree: ignored" || fail "foreign subagent meta: $(proj s5 a3 "$TP")"
# 4b INSTINCT-040 (OCR2 16): the subagent's meta file sits in a folder the agent can write; a FIFO planted there used to hang every gate that
#    asks project() (a plain open()). Bounded child: a hang prints HANG, a failure is a line, not a stuck test. The FIFO is skipped, and the
#    next place the meta can be (next to the transcript) is still read.
mkfifo "$TMP/proj/s5/subagents/agent-a4.meta.json" "$TMP/proj/s5/subagents/agent-a5.meta.json"
printf '{"worktreePath": "%s"}\n' "$W" > "$TMP/proj/agent-a5.meta.json"
fifo_proj() {   # fifo_proj <agent id>: "<rc> <project()>" of a bounded child, or HANG
  python3 -I -c 'import json, os, subprocess, sys
sw, m, tp, a = sys.argv[1:5]
d = json.dumps({"session_id": "s5", "agent_id": a, "cwd": m, "transcript_path": tp})
try:
    r = subprocess.run([sys.executable, "-I", sw, "project"], input=d, timeout=5, capture_output=True, text=True, env=dict(os.environ, CLAUDE_PROJECT_DIR=m))
except subprocess.TimeoutExpired:
    print("HANG"); sys.exit(0)
print(r.returncode, r.stdout.strip())' "$SW" "$M" "$TP" "$1"
}
[ "$(fifo_proj a4)" = "0 $M" ] && ok "a FIFO as a subagent's meta file: no hang, no tree taken (project = main)" || fail "FIFO meta (a4): '$(fifo_proj a4)'"
[ "$(fifo_proj a5)" = "0 $W" ] && ok "  … skipped, and the meta next to the transcript is still read (project = its worktree)" || fail "FIFO meta, then a real one (a5): '$(fifo_proj a5)'"

# 5 the record hook never fails the tool call: garbage payload, no session, a subagent's EnterWorktree (not the session's) records nothing
f0=$FAILS; for p in 'not json' '{}' '{"tool_name":"EnterWorktree"}' '[1,2]'; do
  printf '%s' "$p" | CLAUDE_PROJECT_DIR="$M" python3 -I "$SW" record >/dev/null 2>&1 || fail "record exited non-zero on: $p"
done; [ "$FAILS" = "$f0" ] && ok "record: garbage payloads exit 0"
python3 -c 'import json,sys; print(json.dumps({"session_id":"s6","agent_id":"x","cwd":sys.argv[1],"tool_name":"EnterWorktree","tool_response":{"worktreePath":sys.argv[1]}}))' "$W" \
  | CLAUDE_PROJECT_DIR="$M" python3 -I "$SW" record 2>/dev/null
[ ! -e "$M/.claude/audit-gate/session_worktree/s6" ] && ok "  … a subagent's EnterWorktree is not recorded as the session's" || fail "subagent EnterWorktree recorded for the session"

# 6 reown (/clear, /resume): a session that already HAS a record keeps it - its own worktree is never swapped for a dead session's one it
#   happens to stand in (R3 review 14/10, P1-2); a session with no record still takes over the dead one's
reown() {   # reown <session> <here>: prints the worktree re-owned (empty: none)
  python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import session_worktree as sw
m, sid, here = sys.argv[2:5]; print(sw.reown(m, sid, here, lambda o: False) or "")' "$DEVKIT_DIR/hooks" "$M" "$1" "$2"
}
python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import session_worktree as sw
m, a, b = sys.argv[2:5]; assert sw.write_record(m, "cur", a) and sw.write_record(m, "dead", b)' "$DEVKIT_DIR/hooks" "$M" "$W" "$TMP/main-w2"
r="$(reown cur "$TMP/main-w2")"
[ -z "$r" ] && [ "$(cat "$M/.claude/audit-gate/session_worktree/cur")" = "$W" ] && [ -e "$M/.claude/audit-gate/session_worktree/dead" ] \
  && ok "reown: a session that has its own record keeps it (the dead one's record is not taken)" || fail "reown overwrote the session's own record (re-owned '$r', cur=$(cat "$M/.claude/audit-gate/session_worktree/cur"))"
r="$(reown fresh "$TMP/main-w2")"
[ "$r" = "$TMP/main-w2" ] && [ ! -e "$M/.claude/audit-gate/session_worktree/dead" ] && [ "$(cat "$M/.claude/audit-gate/session_worktree/fresh")" = "$TMP/main-w2" ] \
  && ok "  … a session with no record takes over the dead one's (the /clear case)" || fail "reown for a record-less session ('$r')"
# the same process (/clear keeps the claude process, so the old id's pid answers): a record written under pid `me` is taken, one under another
# live pid is not; the record's pid travels with it (OCR 13 / R1 review 14/10)
python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import session_worktree as sw
m, a, b = sys.argv[2:5]; assert sw.write_record(m, "mine", a, pid=4242) and sw.write_record(m, "peer", b, pid=4343)
alive = lambda o: True   # both ids read alive: only the pid of the process asking can tell the same process from a peer
assert sw.reown(m, "new1", b, alive, me=4242) is None and sw.raw_record(m, "new1") is None, "a record of another live pid was taken"
assert sw.reown(m, "new2", a, alive, me=4242), "a record written under my own pid was not taken"
assert sw.raw_pid(m, "new2") == 4242 and sw.raw_pid(m, "mine") is None, "the pid did not travel with the record"' "$DEVKIT_DIR/hooks" "$M" "$W" "$TMP/main-w2" \
  && ok "  … reown with me=<pid>: the record written under that process is taken (pid carried over), another live pid's is not" || fail "reown me=pid"

# 7 the record: a pid on line 2 (the claude process), a temp name no reader takes for a session, a planted symlink never written through
python3 -I -c 'import os, sys; sys.path.insert(0, sys.argv[1]); import session_worktree as sw
m, w = sys.argv[2:4]; rd = os.path.join(m, sw.RECORD_DIR)
assert sw.write_record(m, "p1", w, pid=777) and sw.raw_record(m, "p1") == w and sw.raw_pid(m, "p1") == 777
assert sw.write_record(m, "p2", w) and sw.raw_pid(m, "p2") is None, "a record without a pid reads none"
for bad in (True, 1, 0, -5, "9", None): assert sw.write_record(m, "p3", w, pid=bad) and sw.raw_pid(m, "p3") is None, f"pid {bad!r} was recorded"
open(os.path.join(rd, "p4"), "w").write(w + "\npid 12 extra\n"); assert sw.raw_pid(m, "p4") is None
assert sw.record_age(m, "p1") is not None and sw.record_age(m, "nobody") is None
# a write killed between the temp file and os.replace (the hook timeout): the leftover is no record
real = os.replace
def die(*a): raise KeyboardInterrupt
os.replace = die
try: sw.write_record(m, "p5", w, pid=1234)
except KeyboardInterrupt: pass
os.replace = real
left = [n for n in os.listdir(rd) if n.endswith(".tmp")]
assert left and not any(sw._SID.fullmatch(n) for n in left), f"a temp name matches _SID: {left}"
assert "p5" not in sw.records(m) and not [n for n in sw.records(m) if n.endswith(".tmp")], "the temp file of a killed write is read as a session record"
# a symlink planted at the temp path: replaced, never written through
victim = os.path.join(os.path.dirname(rd), "victim.txt"); open(victim, "w").write("keep")
os.symlink(victim, os.path.join(rd, f".p6.{os.getpid()}.tmp"))
assert sw.write_record(m, "p6", w) and open(victim).read() == "keep", "write_record followed a symlink at its temp path"' "$DEVKIT_DIR/hooks" "$M" "$W" \
  && ok "record: pid on line 2 (a flag, 0, a string, a bad line: none), a killed write leaves no session record, a planted symlink is not written through" \
  || fail "record format / temp name"

# 8 INSTINCT-040: tree_of reads a folder's .git file and its admin dir's commondir; a FIFO planted at either must not hang every gate that asks
#   which tree it is in (OCR 4). Run in a child with a timeout: a hang is a failure, not a stuck test.
mkdir -p "$TMP/fifo-gdir" "$TMP/fifo-wt/sub"; mkfifo "$TMP/fifo-gdir/commondir"; printf 'gitdir: %s\n' "$TMP/fifo-gdir" > "$TMP/fifo-wt/.git"
#   The child's exit code and what it printed are asserted too (OCR2 10): a traceback from a FIFO tree_of did not expect would not hang either.
fifo_tree() {   # fifo_tree <expected stdout> <folder>...: every folder, in a bounded child, must exit 0 and print exactly that
  python3 -I -c 'import subprocess, sys
want = sys.argv[2]
for what in sys.argv[3:]:
    try:
        r = subprocess.run([sys.executable, "-I", "-c", "import sys; sys.path.insert(0, sys.argv[1]); import session_worktree as sw; print(sw.tree_of(sys.argv[2]))", sys.argv[1], what],
                           timeout=5, capture_output=True, text=True)
    except subprocess.TimeoutExpired:
        print("HANG on " + what); sys.exit(1)
    if r.returncode != 0 or r.stdout.strip() != want:
        print("bad result on " + what + ": rc " + str(r.returncode) + " out=" + r.stdout.strip() + " err=" + r.stderr.strip()[-200:]); sys.exit(1)' "$DEVKIT_DIR/hooks" "$@"
}
fifo_tree "('$TMP/fifo-wt', False, '$TMP/fifo-gdir')" "$TMP/fifo-wt" "$TMP/fifo-wt/sub" > "$TMP/out" 2>&1 \
  && ok "tree_of: a FIFO at <admin dir>/commondir does not hang it, and it reads the folder as a tree of its own (like a submodule)" || fail "tree_of with a FIFO commondir: $(cat "$TMP/out")"
rm -f "$TMP/fifo-gdir/commondir" "$TMP/fifo-wt/.git"; mkfifo "$TMP/fifo-wt/.git.fifo" && mv "$TMP/fifo-wt/.git.fifo" "$TMP/fifo-wt/.git"
fifo_tree "None" "$TMP/fifo-wt/sub" "$TMP/fifo-wt" > "$TMP/out" 2>&1 \
  && ok "  … and a FIFO as the .git file itself: no hang, no tree (None)" || fail "tree_of with a FIFO .git: $(cat "$TMP/out")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_session_worktree: PASS"; exit 0; } || { echo "test_session_worktree: FAIL ($FAILS)"; exit 1; }
