#!/usr/bin/env bash
# hooks/test_evidence_gate.sh, check 2 on a READ-ONLY turn (#649): a turn that only read a log (runs.jsonl) and quoted its PASS/FAIL
# counts was blocked twice on 29/10. The turn wrote no file and ran no test, so the counts are a quotation, not a claim.
#  1. read-only turn (Read, Grep, a Bash `jq`/`cat`) quoting counts: passes.
#  2. must still block: the same reply after an edit of code with no test run (old behaviour); a Bash write; a test runner
#     command that failed; an EMPTY transcript (no tool at all = unknown).
#  3. a test runner command that succeeded backs the claim (old behaviour, nothing changed).
# Run: bash tests/gates/test_evidence_readonly_turn.sh   (TE_HOOK=<path> tests another copy of the hook)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${TE_HOOK:-$DEVKIT_DIR/hooks/test_evidence_gate.sh}"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0; N=0
export AUTO_LINK=0 RED_PROOF=0 LESSON_REMINDER=0 BUG_LINK_REMINDER=0
P="$TMP/p"; mkdir -p "$P/src"; git -C "$P" init -q .
printf 'x = 1\n' > "$P/src/a.py"
git -C "$P" add -A && git -C "$P" -c user.email=t@t -c user.name=t commit -qm init
run() {   # run <want rc> <transcript> <reply> <label>
  N=$((N + 1))
  python3 -c 'import json,sys; print(json.dumps({"session_id":"te-ro-"+sys.argv[3],"transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2]}))' "$2" "$3" "$N" > "$TMP/in.json"
  CLAUDE_PROJECT_DIR="$P" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err"; local rc=$?
  grep -q Traceback "$TMP/err" && rc=99
  if [ "$rc" = "$1" ]; then echo "✔ rc $rc: $4"; else echo "✖ rc $rc (want $1): $4"; FAILS=$((FAILS + 1)); fi
}
transcript() {   # transcript <file> <json steps>: ["read", path] | ["tool", name] | ["bash", cmd, output, is_error] | ["edit", path]
  python3 - "$1" "$2" <<'PY'
import json, sys
out, steps = sys.argv[1], json.loads(sys.argv[2])
with open(out, "w") as fh:
    for i, st in enumerate(steps):
        inp = {"bash": {"command": st[1] if len(st) > 1 else ""}, "edit": {"file_path": st[1] if len(st) > 1 else "", "old_string": "x = 1", "new_string": "x = 2"},
               "read": {"file_path": st[1] if len(st) > 1 else ""},
               "grep": {"path": st[1] if len(st) > 1 else "", "pattern": "PASS"}}.get(st[0], {})
        if st[0] == "baddict":
            inp = "not-a-dict"
        name = {"bash": "Bash", "edit": "Edit", "read": "Read", "grep": "Grep", "baddict": "Bash"}.get(st[0], st[1] if st[0] == "tool" else "Read")
        fh.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": f"t{i}", "name": name, "input": inp}]}}) + "\n")
        res = st[2] if st[0] == "bash" else "ok"
        err = bool(st[3]) if st[0] == "bash" and len(st) > 3 else False
        fh.write(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": res, "is_error": err}]}}) + "\n")
PY
}
REPLY='Trong runs.jsonl có 12/12 test pass ở lần chạy cuối, 3 suite fail ở lần trước.'
EMPTY="$TMP/empty.jsonl"; : > "$EMPTY"
echo "-- read-only turn quoting counts passes"
transcript "$TMP/r1.jsonl" '[["read","/tmp/runs.jsonl"]]'
run 0 "$TMP/r1.jsonl" "$REPLY" "Read of a log"
transcript "$TMP/r2.jsonl" '[["bash","jq -c . .agents/runs.jsonl | tail -5","{\"status\":\"PASS\"}",false],["tool","Grep"]]'
run 0 "$TMP/r2.jsonl" "$REPLY" "Bash jq + Grep"
transcript "$TMP/r3.jsonl" '[["bash","rg \"PASS|FAIL\" runs.jsonl","PASS",false]]'
run 0 "$TMP/r3.jsonl" "$REPLY" "rg of a quoted PASS|FAIL"
transcript "$TMP/r4.jsonl" "[[\"bash\",\"jq '.a | .b' runs.jsonl\",\"{}\",false]]"
run 0 "$TMP/r4.jsonl" "$REPLY" "jq pipe inside quotes"
transcript "$TMP/r5.jsonl" "[[\"bash\",\"jq 'select(.x > 0)' runs.jsonl\",\"{}\",false]]"
run 0 "$TMP/r5.jsonl" "$REPLY" "jq greater-than inside quotes"
transcript "$TMP/r6.jsonl" '[["bash","jq \"select(.x > 0)\" runs.jsonl","",false]]'
run 0 "$TMP/r6.jsonl" "$REPLY" "jq greater-than inside double quotes, then a path"
transcript "$TMP/r7.jsonl" '[["bash","jq \"select(.x > 0)\"","",false]]'
run 0 "$TMP/r7.jsonl" "$REPLY" "jq greater-than inside double quotes at end of command"
echo "-- must still block"
transcript "$TMP/b1.jsonl" "[[\"edit\",\"$P/src/a.py\"]]"
run 2 "$TMP/b1.jsonl" "$REPLY" "edit of code, no test run"
run 2 "$EMPTY" "$REPLY" "empty transcript"
transcript "$TMP/b2.jsonl" '[["read","/tmp/runs.jsonl"],["bash","echo x > src/a.py","",false]]'
run 2 "$TMP/b2.jsonl" "$REPLY" "read then a Bash write"
transcript "$TMP/b3.jsonl" '[["read","/tmp/runs.jsonl"],["bash","python3 -m pytest tests","FAILED tests/test_a.py::test_x - assert 1 == 2\n1 failed in 0.12s",true]]'
run 2 "$TMP/b3.jsonl" "$REPLY" "read then a failing test run"
transcript "$TMP/b4.jsonl" '[["read","/tmp/runs.jsonl"],["tool","Agent"]]'
run 2 "$TMP/b4.jsonl" "$REPLY" "read then a tool that is not a read"
transcript "$TMP/b5.jsonl" '[["bash","cat runs.jsonl 1> src/a.py","",false]]'
run 2 "$TMP/b5.jsonl" "$REPLY" "redirect 1> writes a file"
transcript "$TMP/b5b.jsonl" '[["bash","ls &> src/a.py","",false]]'
run 2 "$TMP/b5b.jsonl" "$REPLY" "redirect &> writes a file"
transcript "$TMP/b5c.jsonl" '[["bash","cat runs.jsonl 2> src/a.py","",false]]'
run 2 "$TMP/b5c.jsonl" "$REPLY" "redirect 2> writes a file"
transcript "$TMP/b5d.jsonl" '[["bash","cat runs.jsonl 1<> src/a.py","",false]]'
run 2 "$TMP/b5d.jsonl" "$REPLY" "redirect 1<> writes a file"
transcript "$TMP/b6.jsonl" '[["bash","ls & patch -p0","",false]]'
run 2 "$TMP/b6.jsonl" "$REPLY" "background & then another command"
transcript "$TMP/b7.jsonl" '[["bash","cat <(./fix.sh)","",false]]'
run 2 "$TMP/b7.jsonl" "$REPLY" "process substitution runs a command"
transcript "$TMP/b8.jsonl" '[["bash","sort -o src/a.py src/a.py","",false]]'
run 2 "$TMP/b8.jsonl" "$REPLY" "sort -o writes a file"
transcript "$TMP/b9.jsonl" '[["bash","uniq src/a.py src/b.py","",false]]'
run 2 "$TMP/b9.jsonl" "$REPLY" "uniq with two paths writes the second"
transcript "$TMP/b10.jsonl" '[["read","TEST-results.xml"]]'
run 2 "$TMP/b10.jsonl" "$REPLY" "Read of a TEST xml"
transcript "$TMP/b11.jsonl" '[["grep","build/TEST-results.xml"]]'
run 2 "$TMP/b11.jsonl" "$REPLY" "Grep of a TEST xml"
transcript "$TMP/b12.jsonl" '[["read","/tmp/runs.jsonl"],["baddict"]]'
run 2 "$TMP/b12.jsonl" "$REPLY" "Bash input that is not a dict"
transcript "$TMP/b13.jsonl" '[["bash","cat \"$(rm src/a.py)\" x","",false]]'
run 2 "$TMP/b13.jsonl" "$REPLY" "command substitution inside double quotes, then a word"
transcript "$TMP/b14.jsonl" '[["bash","cat \"$(rm src/a.py)\"","",false]]'
run 2 "$TMP/b14.jsonl" "$REPLY" "command substitution inside double quotes at end"
transcript "$TMP/b15.jsonl" '[["bash","cat \"`rm src/a.py`\" x","",false]]'
run 2 "$TMP/b15.jsonl" "$REPLY" "backtick inside double quotes, then a word"
echo "-- 19/11 audit session: a read-only research turn (ToolSearch, WebFetch, chained reads, gh api GET) was held by check 2 and check 7"
OUTCOME_REPLY='Lane review đánh dấu R1 fixed ở merge-queue.sh:210; hook bắt cặp ĐỎ→XANH.'
RS='[["tool","ToolSearch"],["tool","WebFetch"],["bash","cd /x; echo == a; ls a b 2>/dev/null | head -5; git ls-files | grep -iE x | head","",false],["bash","echo == p; gh api repos/o/r/branches/main/protection --jq .x 2>&1 | head -12; wc -l AGENTS.md 2>/dev/null","",false],["bash","sed -n 1,40p hooks/x.sh; git log --oneline -3","",false]]'
transcript "$TMP/r8.jsonl" "$RS"
run 0 "$TMP/r8.jsonl" "$REPLY" "research turn: chained reads, gh api GET, WebFetch, ToolSearch (check 2)"
run 0 "$TMP/r8.jsonl" "$OUTCOME_REPLY" "research turn quoting a reviewer's 'fixed' (check 7)"
transcript "$TMP/b16.jsonl" '[["bash","cd /x; gh api -X PATCH repos/o/r/issues/1 -f body=x | head","",false]]'
run 2 "$TMP/b16.jsonl" "$REPLY" "gh api write in a chain"
transcript "$TMP/b17.jsonl" '[["bash","cd /x; echo a; python3 fix.py","",false]]'
run 2 "$TMP/b17.jsonl" "$REPLY" "interpreter run in a chain"
transcript "$TMP/b18.jsonl" "[[\"edit\",\"$P/src/a.py\"]]"
run 2 "$TMP/b18.jsonl" "$OUTCOME_REPLY" "outcome claim after a code edit, no RED→GREEN (check 7 unchanged)"
transcript "$TMP/b19.jsonl" '[["tool","ToolSearch"],["tool","Agent"]]'
run 2 "$TMP/b19.jsonl" "$OUTCOME_REPLY" "outcome claim after a subagent ran (it may have edited code)"
echo "-- #1342 review R1: write forms that look like reads must still block; plain listings still pass"
i=0
for cmd in 'gh api -XPOST repos/o/r/issues -fbody=x' 'gh api repos/o/r/issues -Fbody=@x' 'gh api --method=POST repos/o/r/issues' \
           'git branch -D old' 'git branch -m a b' 'git branch newbranch' 'git worktree remove x' 'git remote add o u' 'git remote set-url o u' \
           'git diff --output=src/a.py' 'git log --output=src/a.py' 'git show --output=src/a.py' \
           "sed 's/x/y/w out.txt' f" "sed -n '1w out.txt' f" "sed -n 1p -i f" "sed -n -f s.sed f" "sed -e 1p f" "sed '1e id' f" "sed -n '1p;2w o' f" \
           'git grep -Ots x' 'git grep --open-files-in-pager=sh x' 'git diff --ext-diff' 'git show --textconv HEAD:f' 'git log -p --ext-diff'; do
  i=$((i + 1))
  python3 -c 'import json,sys; print(json.dumps([["bash",sys.argv[1],"",False]]))' "$cmd" > "$TMP/s.json"
  transcript "$TMP/w$i.jsonl" "$(cat "$TMP/s.json")"
  run 2 "$TMP/w$i.jsonl" "$REPLY" "write form is not a read: $cmd"
done
i=0
for cmd in 'git branch -a' 'git branch --show-current' 'git branch -vv' 'git branch --list' 'git worktree list' 'git remote -v' 'git remote' \
           'git diff --stat' 'git log --oneline -3' 'gh api repos/o/r --jq .x --paginate' 'gh api -H Accept:x repos/o/r' \
           "sed -n '1,40p' f" "sed -n 5p f" "sed -n '10,\$p' f | head" 'git grep -n x'; do
  i=$((i + 1))
  python3 -c 'import json,sys; print(json.dumps([["bash",sys.argv[1],"",False]]))' "$cmd" > "$TMP/s.json"
  transcript "$TMP/p$i.jsonl" "$(cat "$TMP/s.json")"
  run 0 "$TMP/p$i.jsonl" "$REPLY" "read form stays a read: $cmd"
done
echo "-- a successful run still backs the claim"
transcript "$TMP/g1.jsonl" '[["bash","python3 -m pytest tests","12 passed in 0.30s",false]]'
run 0 "$TMP/g1.jsonl" "$REPLY" "pytest run green"
[ "$FAILS" = 0 ] && echo "ALL OK" || echo "$FAILS FAILED"
exit $((FAILS > 0))
