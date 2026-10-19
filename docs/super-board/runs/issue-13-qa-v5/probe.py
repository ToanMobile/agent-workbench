import sys, os, subprocess, tempfile
dk = sys.argv[1]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
t = os.path.realpath(tempfile.mkdtemp(prefix="qa13m-"))
m = t + "/main"; w = t + "/main-w"
os.makedirs(m)
g = lambda *a: subprocess.run(["git", "-C", m, *a], check=True, capture_output=True)
g("init", "-q", "-b", "main"); g("config", "user.email", "t@t"); g("config", "user.name", "t")
open(m + "/README.md", "w").write("r"); open(m + "/.gitignore", "w").write("/.claude/worktrees/\n")
g("add", "-A"); g("commit", "-qm", "i"); g("worktree", "add", "-q", "--detach", w, "HEAD"); g("config", "devkit.trunkMode", "true")
main, sw = sl.trunk_main(m)
def chk(cmd):
    return sl.trunk_write("Bash", {"command": cmd}, cmd, w, main, sw, "s")
M = m
cases = [
 (True, f'M={M}; tee "$M/README.md" <<<x'),
 (True, f'M={M}; cp /etc/hosts "$M/README.md"'),
 (True, f'M={M}; mv x "$M/README.md"'),
 (True, f'M={M}; rm "$M/README.md"'),
 (True, f'M={M}; touch "$M"/new'),
 (True, f'M={M}; ln -sf /etc/hosts "$M/README.md"'),
 (True, f'M={M}; pushd "$M" && echo x > README.md'),
 (True, f'M={M}; cd ${{M}} && echo x > README.md'),
 (True, f'M={M}; cd "$M" && sed -i s/r/x/ README.md'),
 (True, f'M={M}; cd "$M" && perl -pi -e s/r/x/ README.md'),
 (True, f'M={M}; cd "$M" && touch new'),
 (True, f'cd $(echo {M}) && echo x > README.md'),
 (True, f'cd `echo {M}` && echo x > README.md'),
 (True, f'for d in {M}; do echo x > "$d/README.md"; done'),
 (True, f'for d in {M}; do cd "$d"; echo x > README.md; done'),
 (True, f'M={M}; sed -i.bak s/r/x/ "$M/README.md"'),
 (True, f"M={M}; sed -i '' s/r/x/ \"$M/README.md\""),
 (True, f'M={M}; sed -i -e s/r/x/ "$M"'),
 (True, f'M={M}; sed --in-place s/r/x/ "$M/README.md"'),
 (True, f'M={M}; sed -i -e s/r/x/ -e s/a/b/ "$M/README.md"'),
 (True, f'M={M}; sed -ni p "$M/README.md"'),
 (True, f'M={M}; perl -i.bak -pe s/r/x/ "$M/README.md"'),
 (True, f'M={M}; perl -p -i -e s/r/x/ "$M/README.md"'),
 (True, f'M={M}; sed -i s/r/x/ "$M/README.md" "$M/b"'),
 (True, f'M={M}; sed -s -i -f script.sed "$M/README.md"'),
 (True, f'M={M}; sed -i -- s/r/x/ "$M/README.md"'),
 (True, f'M={M}; sed -i s/r/x/ $M/README.md'),
 (True, f'M={M}; sed -i s/r/x/ ${{M}}'),
 (True, f'M={M}; sed -i "s/r/x/" "$M/README.md"'),
 (True, f'M={M}; sed -i "$M/README.md" -e s/r/x/'),
 (True, f'M={M}; install -m644 x "$M/README.md"'),
 (True, f'M={M}; truncate -s0 "$M"'),
 (True, f'M={M}; echo x | tee -a "$M"'),
 (True, f'M={M}; cat > "$M"'),
 (True, f'M={M}; : >"$M"'),
 (True, f'M={M}; exec 3>"$M"'),
 (True, f'cd {M} && cd . && echo x > README.md'),
 (True, f'M={M}; cd "$M"; cd "$PWD"; echo x > README.md'),
 (True, f'cd "$(git rev-parse --git-common-dir)/.." && echo x > README.md'),
 (True, f'M={M}; (cd "$M" && echo x > README.md)'),
 (True, f'M={M}; {{ cd "$M"; echo x > README.md; }}'),
 (True, f'M={M}; cd "$M" || true; echo x > README.md'),
 (True, f'M={M}; cd "$M"\necho x > README.md'),
 (False, 'O=/tmp/o; sed -i s/r/x/ "$O/f"'),
 (False, 'O=/tmp/o; cd "$O" && echo x > f'),
 (False, 'O=/tmp/o; cd "$O" && sed -i s/r/x/ f'),
 (False, 'O=/tmp/o; sed -i s/r/x/ "$O"'),
 (False, "sed -i '$d' /tmp/qa13file"),
 (False, f'M={M}; cd "$M" && git status'),
 (False, f'M={M}; cat "$M/README.md" > /tmp/out'),
 (False, f'M={M}; cd /tmp && echo x > f'),
 (False, f'M={M}; cd "$M"; cd /tmp; echo x > f'),
 (False, f'M={M}; cd "$M"; cd /tmp/o; sed -i s/r/x/ f'),
]
bad = 0
for want, c in cases:
    try: got = chk(c)
    except Exception as e: got = f"EXC {e!r}"
    if got != want:
        bad += 1; print("MISMATCH want=%s got=%s :: %s" % ("BLOCK" if want else "ALLOW", got, c.replace(m, "<main>").replace("\n", "\\n")))
print(len(cases), "probes,", bad, "mismatch")
