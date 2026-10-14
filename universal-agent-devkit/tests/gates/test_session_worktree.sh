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
f0=$FAILS; for bad in "$TMP/other-wt" "$TMP/plain" "$W/sub" "relative/path" "$TMP/decoy"; do
  printf '%s\n' "$bad" > "$M/.claude/audit-gate/session_worktree/s3"
  [ "$(proj s3)" = "$M" ] || fail "a record naming $bad moved the gates to $(proj s3)"
done; [ "$FAILS" = "$f0" ] && ok "a record naming another repo's worktree / a plain folder / a sub-folder / a relative path / a decoy with a copied .git file: ignored"
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

# 5 the record hook never fails the tool call: garbage payload, no session, a subagent's EnterWorktree (not the session's) records nothing
f0=$FAILS; for p in 'not json' '{}' '{"tool_name":"EnterWorktree"}' '[1,2]'; do
  printf '%s' "$p" | CLAUDE_PROJECT_DIR="$M" python3 -I "$SW" record >/dev/null 2>&1 || fail "record exited non-zero on: $p"
done; [ "$FAILS" = "$f0" ] && ok "record: garbage payloads exit 0"
python3 -c 'import json,sys; print(json.dumps({"session_id":"s6","agent_id":"x","cwd":sys.argv[1],"tool_name":"EnterWorktree","tool_response":{"worktreePath":sys.argv[1]}}))' "$W" \
  | CLAUDE_PROJECT_DIR="$M" python3 -I "$SW" record 2>/dev/null
[ ! -e "$M/.claude/audit-gate/session_worktree/s6" ] && ok "  … a subagent's EnterWorktree is not recorded as the session's" || fail "subagent EnterWorktree recorded for the session"

echo
[ "$FAILS" -eq 0 ] && { echo "test_session_worktree: PASS"; exit 0; } || { echo "test_session_worktree: FAIL ($FAILS)"; exit 1; }
