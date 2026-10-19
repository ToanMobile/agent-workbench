import sys, os, subprocess, tempfile, shutil
dk = sys.argv[1]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_") and k != "WORKTREE_TRUNK_MODE"}
t = os.path.realpath(tempfile.mkdtemp(prefix="qa13m-"))
try:
    m = t + "/main"; w = t + "/main-w"
    os.makedirs(m)
    g = lambda *a: subprocess.run(["git", "-C", m, *a], check=True, capture_output=True, env=env)
    g("init", "-q", "-b", "main"); g("config", "user.email", "t@t"); g("config", "user.name", "t")
    open(m + "/README.md", "w").write("r"); open(m + "/.gitignore", "w").write("/.claude/worktrees/\n")
    g("add", "-A"); g("commit", "-qm", "i"); g("worktree", "add", "-q", "--detach", w, "HEAD"); g("config", "devkit.trunkMode", "true")
    open(m + "/only.txt", "w").write("r")   # exists in main only, not in the worktree
    os.makedirs(w + "/sub")
    main, sw = sl.trunk_main(m)
    M = m
    cases = [
        (w, f'M={M}; cd "$M" && sed -i s/r/x/ only.txt'),
        (w, f'M={M}; cd "$M" && perl -pi -e s/r/x/ only.txt'),
        (w, f'cd $(echo {M}) && sed -i s/r/x/ only.txt'),
        (w + "/sub", f'M={M}; cd "$M" && sed -i s/r/x/ README.md'),
        (w, f'M={M}; cd "$M" && echo x > only.txt'),
    ]
    for cwd, c in cases:
        print("BLOCKED" if sl.trunk_write("Bash", {"command": c}, c, cwd, main, sw, "s") else "ALLOWED(leak)", "::", c.replace(m, "<main>"), "| cwd", "sub" if cwd.endswith("sub") else "wt")
finally:
    shutil.rmtree(t, ignore_errors=True)
