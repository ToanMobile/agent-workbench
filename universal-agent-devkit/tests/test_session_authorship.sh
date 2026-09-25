#!/usr/bin/env bash
# Regression test: bin/session_authorship.py decides which files a Bash command of this
# session may have written. Review 2026-09-25 (real transcripts, 30 days): ordinary commands
# named EVERY file — `cd <repo> && rm -f /tmp/x.log`, `grep -rn … .`, `git diff --patch` — so
# testsourceset_gate blocked on other sessions' broken modules again and another session's test
# edit was taken as this session's. A write verb only names the paths of its own segment.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src/test" && touch "$R/src/test/FooTest.kt"

python3 - "$DEVKIT_DIR/bin" "$R" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); import session_authorship as sa
root, rel = sys.argv[2], "src/test/FooTest.kt"
names = lambda cmd: sa.names_path(sa.shell_named([cmd]), root, rel)
fails = 0
def check(cmd, want):
    global fails
    got = names(cmd)
    print(("✔" if got == want else "✖") + (" names the test: " if want else " does not name the test: ") + cmd.replace("\n", "⏎"))
    fails += got != want
# Not a write of the test (each measured on real transcripts).
for cmd in (f"cd {root} && rm -f /tmp/x.log", 'grep -rn "install" .', "git diff --patch -- hooks/",
            f"ls -la {root}/", "find . -name '*.kt' | head", 'echo "cp and rm are verbs" > /tmp/o.txt',
            "python3 - <<'EOF'\nimport os\nos.system('rm x')\nEOF", "cat src/test/FooTest.kt | tee /tmp/copy.kt",
            "rm -rf /nonexistent-dir/*", f"cd {root}/src && ls",
            # a lone "/" (a sed expression, `>/` inside quotes) is not "every file" (review 2 P2-1)
            "grep '^sonatype.user' f | sed 's/=.*/=<hidden>/'", "sed -i '' 's/Run 294+ tests / Run all suites /' Makefile"):
    check(cmd, False)
# Review 2 P1-1: writes the old whole-command rule caught must not be lost to the segment rule —
# shell keywords, wrappers, `sh -c`, `$(…)`, a heredoc fed to a shell, flags with values.
for cmd in ("if true; then cp -p /tmp/a.kt src/test/FooTest.kt; fi", "for f in /tmp/bk/*.kt; do cp -p \"$f\" src/test/; done",
            "{ cp /tmp/a.kt src/test/FooTest.kt; }", "! cp /tmp/a.kt src/test/FooTest.kt",
            "ls src/test/*.kt | while read f; do sed -i '' s/a/b/ $f; done",
            "bash -c 'cp /tmp/a.kt src/test/FooTest.kt'", "sh -c \"rm src/test/FooTest.kt\"", "eval \"rm src/test/FooTest.kt\"",
            "x=$(cp /tmp/a.kt src/test/FooTest.kt)", "timeout 30 cp /tmp/a.kt src/test/FooTest.kt",
            "nice -n 5 cp /tmp/a.kt src/test/FooTest.kt", "sudo -u me cp /tmp/a.kt src/test/FooTest.kt",
            "echo src/test/FooTest.kt | xargs -n 1 rm", "\\cp /tmp/a.kt src/test/FooTest.kt",
            "bash <<'EOF'\nrm src/test/FooTest.kt\nEOF", "sed --in-place=.bak s/a/b/ src/test/FooTest.kt",
            "find src -name '*.kt' -exec perl -pi -e s/a/b/ {} +", "cd src/test && rm *.kt", "rm -rf src/*",
            "rm src/**/FooTest.kt"):
    check(cmd, True)
# Writes of the test, however they are spelled.
for cmd in ("rsync -a /tmp/backup/src/ src/", "sed -i '' s/assertEquals/println/ src/test/*.kt",
            "cp -p /tmp/backup/FooTest.kt src/test/", "touch -t 202001010000 src/test/FooTest.kt",
            "git archive HEAD~3 src/test | tar -x", f"rm {root}/src/test/FooTest.kt",
            "echo x > src/test/FooTest.kt", "cd /x && git checkout HEAD~1 -- src/test/FooTest.kt",
            "git checkout -- .", "find src -name '*.kt' -delete", "git ls-files src | xargs rm",
            "git -C . restore src/test/FooTest.kt", "FOO=1 sudo cp /tmp/a.kt src/test/FooTest.kt",
            "cat > src/test/FooTest.kt <<'EOF'\nclass FooTest\nEOF"):
    check(cmd, True)
sys.exit(1 if fails else 0)
PY
rc=$?

# "Another session edited it" rests on a sibling transcript. Review 2026-09-25: a transcript this
# session wrote itself (Write tool, or a detached script after the fact) or one of a `claude -p`
# it spawned turned its own test edit into a warning. Timestamps are in the future so the real
# control transcript exists before its edit, like a live one.
python3 - "$DEVKIT_DIR" "$TMP/authorship" <<'PY' || rc=1
import importlib.util, json, os, sys, time
dk, B = sys.argv[1], sys.argv[2]
proj, tx = B + "/proj", B + "/tx"
os.makedirs(proj + "/app/src/test"); os.makedirs(proj + "/.claude/audit-gate"); os.makedirs(tx)
test = proj + "/app/src/test/FooTest.kt"; rel = "app/src/test/FooTest.kt"
os.environ["CLAUDE_PROJECT_DIR"] = proj
spec = importlib.util.spec_from_file_location("pfg", dk + "/bin/post-fix-gate.py")
m = importlib.util.module_from_spec(spec); sys.argv = ["x"]; spec.loader.exec_module(m)
iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int((t % 1) * 1000)
def w(path, recs): open(path, "w").write("".join(json.dumps(r) + "\n" for r in recs))
def use(sid, t, name, inp, tid): return {"sessionId": sid, "timestamp": iso(t), "type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": tid, "name": name, "input": inp}]}}
def res(sid, t, tid): return {"sessionId": sid, "timestamp": iso(t), "type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "content": "ok"}]}}
now = time.time(); start = now - 60; te = now + 30
open(proj + "/.claude/audit-gate/bash_write_ledger.tsv", "w").write(f"me\tstart\t{start:.3f}\tm1\nme\tend\t{start+1:.3f}\tm1\n")
open(test, "w").write("x\n"); os.utime(test, (te, te))
fails = 0
def case(name, me_recs, siblings, want_other):
    global fails
    for f in os.listdir(tx): os.remove(os.path.join(tx, f))
    for fname, recs in siblings.items(): w(os.path.join(tx, fname), recs)
    w(tx + "/me.jsonl", me_recs)
    blocking, other = m.split_tests_by_author([rel], "me", tx + "/me.jsonl")
    ok = (other == [rel]) == want_other
    print(("✔ " if ok else "✖ ") + name + (": other" if other else ": blocking"))
    fails += not ok
edit = lambda sid, t: [use(sid, t - 0.2, "Edit", {"file_path": test}, sid + "1"), res(sid, t + 0.2, sid + "1")]
detached = [use("me", start, "Bash", {"command": "nohup python3 gen.py >/dev/null 2>&1 &"}, "m1"), res("me", start + 1, "m1")]
# control: a real other session, its transcript alive before its edit -> other (a warning)
case("real other session", detached, {"real.jsonl": [use("real", now, "Read", {"file_path": test}, "r0")] + edit("real", te)}, True)
# forged with the Write tool into the transcript folder -> blocking
case("sibling written by this session's Write", detached + [use("me", now, "Write", {"file_path": tx + "/fake.jsonl", "content": "…"}, "m2"), res("me", now + 0.1, "m2")],
     {"fake.jsonl": [use("ghost", now, "Read", {"file_path": test}, "g0")] + edit("ghost", te)}, False)
# forged through Bash (a redirect into the transcript folder) -> blocking
case("sibling written by this session's Bash", detached + [use("me", now, "Bash", {"command": f"cat /tmp/x > {tx}/fake.jsonl"}, "m2"), res("me", now + 0.1, "m2")],
     {"fake.jsonl": [use("ghost", now, "Read", {"file_path": test}, "g0")] + edit("ghost", te)}, False)
# Review 2 P2-2: its own auto-memory (<transcript dir>/memory/) and agent-CLI management
# commands are not a forged transcript or a spawned session -> the real one stays other.
real = {"real.jsonl": [use("real", now, "Read", {"file_path": test}, "r0")] + edit("real", te)}
case("auto-memory Write in the transcript folder", detached + [use("me", now, "Write", {"file_path": tx + "/memory/note.md", "content": "…"}, "m2"), res("me", now + 0.1, "m2")], real, True)
case("echo >> <tx>/memory/MEMORY.md", detached + [use("me", now, "Bash", {"command": f"echo x >> {tx}/memory/MEMORY.md"}, "m2"), res("me", now + 0.1, "m2")], real, True)
for mgmt in ("claude mcp list", "codex --version", "claude plugin list"):
    case(mgmt, [use("me", start, "Bash", {"command": mgmt}, "m1"), res("me", start + 1, "m1")], real, True)
# and a forgery or a spawn spelled another way is still caught (review 2 P2-3)
case("cd <tx> && cp … fake.jsonl", detached + [use("me", now, "Bash", {"command": f"cd {tx} && cp /tmp/f fake.jsonl"}, "m2"), res("me", now + 0.1, "m2")],
     {"fake.jsonl": [use("ghost", now, "Read", {"file_path": test}, "g0")] + edit("ghost", te)}, False)
for spawn in ("timeout 900 claude -p 'fix it'", "for i in 1; do claude -p 'fix it'; done", "npx @anthropic-ai/claude-code -p 'fix it'",
              "bash -c 'claude -p fix' &"):
    case(spawn, [use("me", start, "Bash", {"command": spawn}, "m1"), res("me", start + 1, "m1")],
         {"child.jsonl": [use("child", now, "Read", {"file_path": test}, "c0")] + edit("child", te)}, False)
# a `claude -p` this session spawned is this session's work -> blocking
case("session spawned by this session", [use("me", start, "Bash", {"command": "nohup claude -p 'make FooTest pass' >/dev/null 2>&1 &"}, "m1"), res("me", start + 1, "m1")],
     {"child.jsonl": [use("child", now, "Read", {"file_path": test}, "c0")] + edit("child", te)}, False)
sys.exit(1 if fails else 0)
PY
[ "$rc" = 0 ] && echo "session_authorship: all checks passed" || { echo "session_authorship: FAILED"; exit 1; }
