#!/usr/bin/env bash
# hooks/shell_writes.py - #427 vòng 3: số fd dính liền phép chuyển hướng (`2>/dev/null`, `2>&1`, `>/dev/null 2>&1`, `1>log`) bị shlex tách
# thành `2` + `>`, nên `2` được đọc là đối số: đích của cp / ln / install / rsync / scp (toán hạng cuối) thành `2` (tương đối, ở cwd), đích
# thật mất - `cp x <checkout anh em bị giữ>/f 2>/dev/null` lọt session_lock; cùng lỗi ở luật checkout của chính phiên, trunk_write và
# worktree_guard; `2>/dev/null cp …` (chuyển hướng đứng đầu) thì động từ là `2`, không xét gì. Mỗi ca chạy qua người dùng thật của scanner:
#   1. bin/session_lock.py qua hook PreToolUse (như tests/gates/test_session_lock_round3_427.sh): đích ở worktree anh em bị giữ.
#   2. bin/session_lock.py bash_collides (như tests/context_memory/test_session_lock_file_writes.sh): checkout bị giữ `top` (hits_top).
#   3. bin/session_lock.py trunk_write (như tests/context_memory/test_session_lock_trunk.sh): ghi vào main của trunk mode.
#   4. hooks/worktree_guard.sh (như tests/gates/test_worktree_guard_shell_writes.sh): ghi vào checkout main của agent ở worktree.
#   5. shell_writes.targets trực tiếp: đích redirect vẫn là đích ghi (`2>/tmp/log`), và các dạng shell đọc `2` là ĐỐI SỐ (đo trên bash và zsh):
#      `2 >f` (có cách), `'2'>f`, `\2>f`, `a\ 2>f`.
# Mỗi ca nới (trước chặn, nay qua: `2` không còn là đích giả ở cwd) có ca đối nghịch phải-chặn; mỗi ca phải-chặn có ca đối chứng phải-qua.
#   SWFD_KIT=<thư mục kit>   chạy cùng bảng trên một bản kit khác (bản chưa sửa: ĐỎ).
# bash 3.2 compatible wrapper; the checks are python3 (stdlib only). Không lệnh nào được chạy thật: test chỉ đưa payload cho hook.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_ALLOW_SHARED_CHECKOUT CLAUDE_PROJECT_DIR WORKTREE_GUARD
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${SWFD_KIT:-$DEVKIT_DIR}"
export PYTHONDONTWRITEBYTECODE=1
python3 -I - "$KIT" <<'PY'
import json, os, shutil, subprocess, sys, tempfile, time

KIT = os.path.realpath(sys.argv[1])
SCRIPT = os.path.join(KIT, "bin", "session_lock.py")
GUARD = os.path.join(KIT, "hooks", "worktree_guard.sh")
sys.path.insert(0, os.path.join(KIT, "bin"))
import session_lock as sl   # noqa: E402 - (nó tự nạp hooks/shell_writes.py của chính KIT)
sw_mod = sl._hook_module("shell_writes")
tmp = os.path.realpath(tempfile.mkdtemp(prefix="swfd_"))
S = os.path.join(tmp, "scratch")
os.makedirs(S)
bad = 0


def sh(*a):
    r = subprocess.run(list(a), capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"setup failed: {a}: {r.stderr[:200]}")
    return r.stdout


def repo(name):
    d = os.path.join(tmp, name)
    os.makedirs(d)
    sh("git", "init", "-q", "-b", "main", d)
    with open(os.path.join(d, "AGENTS.md"), "w") as f:
        f.write("x\n")
    sh("git", "-C", d, "add", "-A")
    sh("git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init")
    return d


def gitdir(d):
    return sh("git", "-C", d, "rev-parse", "--absolute-git-dir").strip()


def hold(gdir, sid, cwd, pid=None):   # khoá của một phiên khác còn sống (pid của chính tiến trình test)
    with open(os.path.join(gdir, "devkit-session.lock"), "w", encoding="utf-8") as f:
        json.dump({"session_id": sid, "started": time.time(), "heartbeat": time.time(), "cwd": cwd, "pid": pid or os.getpid(), "gitdir": gdir}, f)


def hook(cmd, cwd, sid="me"):
    env = {k: v for k, v in os.environ.items() if k not in ("DEVKIT_ALLOW_SHARED_CHECKOUT", "CLAUDE_PROJECT_DIR")}
    env["WORKTREE_TRUNK_MODE"] = "0"
    p = {"hook_event_name": "PreToolUse", "session_id": sid, "cwd": cwd, "tool_name": "Bash", "tool_input": {"command": cmd}}
    try:
        return subprocess.run([sys.executable, "-I", SCRIPT], input=json.dumps(p), capture_output=True, text=True, env=env, timeout=30).returncode
    except subprocess.TimeoutExpired:
        return 124


def check(label, got, want):
    global bad
    ok = got == want
    bad += 0 if ok else 1
    print(f"  {'ok  ' if ok else 'FAIL'} {label}: {got!r} (want {want!r})")


print("1. session_lock (hook): đích ở worktree anh em bị giữ, có số fd dính liền phép chuyển hướng (từ FW; FW2 bị giữ, FW3 khoá đã chết)")
FM = repo("family")
FW, FW2, FW3 = (os.path.join(tmp, n) for n in ("family-wt", "family-wt2", "family-wt3"))
for w in (FW, FW2, FW3):
    sh("git", "-C", FM, "worktree", "add", "-q", "--detach", w)
hold(gitdir(FW2), "holder2", FW2)
dead = subprocess.Popen([sys.executable, "-c", "pass"])
dead.wait()
hold(gitdir(FW3), "gone", FW3, pid=dead.pid)
B = repo("other")   # repo rảnh
fam = lambda c: hook(c, FW)
for label, c in (("cp … <FW2>/f 2>/dev/null", f"cp /etc/hosts {FW2}/f.txt 2>/dev/null"),
                 ("cp … <FW2>/f 2>&1 | tail -1", f"cp /etc/hosts {FW2}/f.txt 2>&1 | tail -1"),
                 ("cp … <FW2>/f >/dev/null 2>&1", f"cp /etc/hosts {FW2}/f.txt >/dev/null 2>&1"),
                 ("cp … <FW2>/f 1><scratch>/log", f"cp /etc/hosts {FW2}/f.txt 1>{S}/log.txt"),
                 ("cp … <FW2>/f 2>>/tmp/e", f"cp /etc/hosts {FW2}/f.txt 2>>/tmp/e"),
                 ("ln -sf … <FW2>/l 2>&1", f"ln -sf /etc/hosts {FW2}/l 2>&1"),
                 ("install -m 644 … <FW2>/f 2>/dev/null", f"install -m 644 /etc/hosts {FW2}/f.txt 2>/dev/null"),
                 ("rsync -a … <FW2>/ 2>/dev/null", f"rsync -a /etc/hosts {FW2}/ 2>/dev/null"),
                 ("scp … <FW2>/f 2>/dev/null", f"scp /etc/hosts {FW2}/f.txt 2>/dev/null"),
                 ("cp … ../family-wt2/f 2>/dev/null (đích tương đối)", "cp /etc/hosts ../family-wt2/f.txt 2>/dev/null"),
                 ("2>/dev/null cp … <FW2>/f (chuyển hướng đứng đầu: động từ từng là `2`)", f"2>/dev/null cp /etc/hosts {FW2}/f.txt"),
                 ("echo; 2>/dev/null cp … <FW2>/f", f"echo; 2>/dev/null cp /etc/hosts {FW2}/f.txt"),
                 ("bash -c 'cp … <FW2>/f 2>/dev/null'", f"bash -c 'cp /etc/hosts {FW2}/f.txt 2>/dev/null'")):
    check(label, fam(c), 2)
for label, c in (("cp … <FW của chính nó>/f 2>/dev/null", f"cp /etc/hosts {FW}/f.txt 2>/dev/null"),
                 ("cp <FW2>/f <scratch>/x 2>/dev/null (đọc anh em bị giữ)", f"cp {FW2}/f.txt {S}/x 2>/dev/null"),
                 ("cp … <FW3 khoá đã chết>/f 2>&1", f"cp /etc/hosts {FW3}/f.txt 2>&1"),
                 ("cp … <repo rảnh khác>/f >/dev/null 2>&1", f"cp /etc/hosts {B}/f.txt >/dev/null 2>&1"),
                 ("ln -s <FW2>/f <FW>/l 2>/dev/null (link ở chính nó)", f"ln -s {FW2}/f.txt {FW}/l 2>/dev/null"),
                 ("2>/dev/null cp … <scratch>/f", f"2>/dev/null cp /etc/hosts {S}/f.txt")):
    check("  đối chứng: " + label, fam(c), 0)

print("2. session_lock bash_collides: checkout bị giữ `top` (hits_top)")
TOP, OTHER = repo("held"), repo("free")
hits = lambda c, cwd=TOP: sl.bash_collides(c, TOP, cwd, "me")[0]
for label, c in (("từ OTHER: cp … <top>/x 2>/dev/null", f"cp /tmp/a {TOP}/x.txt 2>/dev/null"),
                 ("từ OTHER: ln -sf … <top>/l 2>&1", f"ln -sf /tmp/a {TOP}/l 2>&1"),
                 ("từ OTHER: 2>/dev/null cp … <top>/x", f"2>/dev/null cp /tmp/a {TOP}/x.txt")):
    check(label, hits(c, OTHER), True)
check("ở top: cp … <OTHER>/x; 2>/dev/null cp … y.txt (lệnh sau: động từ từng là `2`)", hits(f"cp /tmp/a {OTHER}/x.txt; 2>/dev/null cp /tmp/b y.txt"), True)
# nới: `2` không còn là đích giả trong top - các ca này trước bị chặn nhầm
for label, c in (("ở top: cp <top>/AGENTS.md /tmp/out 2>/dev/null", f"cp {TOP}/AGENTS.md /tmp/out.txt 2>/dev/null"),
                 ("ở top: rm -f <OTHER>/x 2>/dev/null", f"rm -f {OTHER}/x.txt 2>/dev/null"),
                 ("ở top: cp … <OTHER>/x 2>&1 | tail -1", f"cp /tmp/a {OTHER}/x.txt 2>&1 | tail -1"),
                 ("ở top: mkdir -p <OTHER>/d 2>/dev/null", f"mkdir -p {OTHER}/d 2>/dev/null")):
    check("  đối chứng (nới): " + label, hits(c), False)
# ... và các ca đối nghịch của mục nới: vẫn phải chặn
for label, c in (("ở top: cp … x.txt 2>/dev/null (đích tương đối trong top)", "cp /tmp/a x.txt 2>/dev/null"),
                 ("ở top: rm -f x.txt 2>/dev/null", "rm -f x.txt 2>/dev/null"),
                 ("ở top: cp … <OTHER>/x 2 >/dev/null (có cách: `2` là đích thật, ở top)", f"cp /tmp/a {OTHER}/x.txt 2 >/dev/null"),
                 ("ở top: cp … <OTHER>/x '2'>/dev/null (`2` trong nháy là đối số)", f"cp /tmp/a {OTHER}/x.txt '2'>/dev/null"),
                 ("ở top: cp … <OTHER>/x \\2>/dev/null (`2` thoát là đối số)", f"cp /tmp/a {OTHER}/x.txt \\2>/dev/null"),
                 ("ở top: cp … <OTHER>/x 2>err.log (đích redirect trong top)", f"cp /tmp/a {OTHER}/x.txt 2>err.log"),
                 ("ở top: cp … <OTHER>/x 2>><top>/err.log", f"cp /tmp/a {OTHER}/x.txt 2>>{TOP}/err.log")):
    check(label, hits(c), True)
check("  đối chứng: từ OTHER: cp … <OTHER>/x 2>/dev/null", hits(f"cp /tmp/a {OTHER}/x.txt 2>/dev/null", OTHER), False)

print("3. session_lock trunk_write: ghi vào main của trunk mode (W: worktree lồng trong main)")
M = repo("tmain")
W = os.path.join(M, ".claude", "worktrees", "s1")
with open(os.path.join(M, ".gitignore"), "w") as f:
    f.write("/.claude/worktrees/\n")
os.makedirs(os.path.join(M, "src"))
with open(os.path.join(M, "src", "a.py"), "w") as f:
    f.write("a\n")
sh("git", "-C", M, "add", "-A")
sh("git", "-C", M, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "src")
sh("git", "-C", M, "worktree", "add", "-q", "--detach", W)
sh("git", "-C", M, "config", "devkit.trunkMode", "true")
main, swk = sl.trunk_main(M)
if not (main and swk):
    raise SystemExit("setup failed: trunk mode not seen")
tw = lambda c, cwd: sl.trunk_write("Bash", {"command": c}, c, cwd, main, swk, "s")
for label, c in (("từ W: cp … <main>/src/a.py 2>/dev/null", f"cp /tmp/a {M}/src/a.py 2>/dev/null"),
                 ("từ W: ln -sf … <main>/README.md 2>&1", f"ln -sf /tmp/a {M}/README.md 2>&1"),
                 ("từ W: cp … <main>/src/a.py >/dev/null 2>&1 | tail -1", f"cp /tmp/a {M}/src/a.py >/dev/null 2>&1 | tail -1")):
    check(label, tw(c, W), True)
for label, c in (("từ W: cp … <W>/x.py 2>/dev/null", f"cp /tmp/a {W}/x.py 2>/dev/null"),
                 ("từ W: cp … src/x.py 2>&1", "cp /tmp/a src/x.py 2>&1")):
    check("  đối chứng: " + label, tw(c, W), False)
check("  đối chứng (nới): ở main: cp src/a.py /tmp/out.py 2>/dev/null", tw("cp src/a.py /tmp/out.py 2>/dev/null", M), False)
for label, c in (("ở main: cp … src/b.py 2>/dev/null", "cp /tmp/a src/b.py 2>/dev/null"),
                 ("ở main: cp src/a.py /tmp/out.py 2 >/dev/null (có cách: `2` ở main)", "cp src/a.py /tmp/out.py 2 >/dev/null"),
                 ("ở main: cp src/a.py /tmp/out.py 2>src/err.log (đích redirect ở main)", "cp src/a.py /tmp/out.py 2>src/err.log")):
    check(label, tw(c, M), True)

print("4. worktree_guard: agent đã vào worktree GW ghi vào checkout main GM")
GM = repo("gmain")
GW = os.path.join(tmp, "gwt")
os.makedirs(os.path.join(GM, "src"))
with open(os.path.join(GM, "src", "a.kt"), "w") as f:
    f.write("x\n")
sh("git", "-C", GM, "add", "-A")
sh("git", "-C", GM, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "src")
sh("git", "-C", GM, "worktree", "add", "-q", "--detach", GW)
TR = os.path.join(tmp, "t.jsonl")
rec = lambda **kw: json.dumps(kw, separators=(",", ":"))
with open(TR, "w") as f:
    f.write(rec(type="user", cwd=GM, message={"role": "user", "content": "hi"}) + "\n")
    f.write(rec(type="assistant", cwd=GM, message={"role": "assistant", "content": [
        {"type": "tool_use", "id": "toolu_1", "name": "EnterWorktree", "input": {"path": GW}}]}) + "\n")
    f.write(rec(type="user", cwd=GM, message={"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "toolu_1", "content": "Switched to worktree " + GW}]}) + "\n")


def guard(cwd, cmd):
    env = {k: v for k, v in os.environ.items() if k != "WORKTREE_GUARD"}
    env["CLAUDE_PROJECT_DIR"] = GM
    p = {"session_id": "s", "transcript_path": TR, "cwd": cwd, "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": cmd}}
    try:
        return subprocess.run(["bash", GUARD], input=json.dumps(p), capture_output=True, text=True, env=env, timeout=60).returncode
    except subprocess.TimeoutExpired:
        return 124


for label, c in (("từ GW: cp … <GM>/src/b.kt 2>/dev/null", f"cp /tmp/x {GM}/src/b.kt 2>/dev/null"),
                 ("từ GW: cp … <GM>/src/b.kt >/dev/null 2>&1", f"cp /tmp/x {GM}/src/b.kt >/dev/null 2>&1"),
                 ("từ GW: 2>/dev/null cp … <GM>/src/b.kt", f"2>/dev/null cp /tmp/x {GM}/src/b.kt")):
    check(label, guard(GW, c), 2)
check("  đối chứng: từ GW: cp … src/b.kt 2>/dev/null (trong worktree của nó)", guard(GW, "cp /tmp/x src/b.kt 2>/dev/null"), 0)
check("  đối chứng (nới): ở GM: cp src/a.kt /tmp/out.kt 2>/dev/null", guard(GM, "cp src/a.kt /tmp/out.kt 2>/dev/null"), 0)
for label, c in (("ở GM: cp src/a.kt /tmp/out.kt 2 >/dev/null (có cách: `2` ở main)", "cp src/a.kt /tmp/out.kt 2 >/dev/null"),
                 ("ở GM: cp … src/b.kt 2>/dev/null", "cp /tmp/x src/b.kt 2>/dev/null"),
                 ("ở GM: cp src/a.kt /tmp/out.kt 2>src/err.log (đích redirect ở main)", "cp src/a.kt /tmp/out.kt 2>src/err.log")):
    check(label, guard(GM, c), 2)

print("5. shell_writes.targets trực tiếp")
T = lambda c: sw_mod.targets(c, "/w")
check("cp a b 2>&1 | tail -1: đích b", T("cp a b 2>&1 | tail -1"), [("file", "b", "/w")])
check("cp a b 2>/tmp/log: redirect /tmp/log vẫn là đích ghi, đích cp là b", T("cp a b 2>/tmp/log"), [("redirect", "/tmp/log", "/w"), ("file", "b", "/w")])
check("echo x 2>>/tmp/e: redirect", T("echo x 2>>/tmp/e"), [("redirect", "/tmp/e", "/w")])
check("cd 2>/dev/null && rm a: cd không đối số về ~ (không phải /w/2)", T("cd 2>/dev/null && rm a"), [("file", "a", os.path.expanduser("~"))])
check("cp a b;2>x cp c d: không gộp `;>` (đích b, redirect x, đích d)", T("cp a b;2>x cp c d"), [("file", "b", "/w"), ("redirect", "x", "/w"), ("file", "d", "/w")])
check("(2>/dev/null cp a /h/f): không gộp `(>`", T("(2>/dev/null cp a /h/f)"), [("file", "/h/f", "/w")])
for label, c, want in (("cp a b 2 >x (có cách)", "cp a b 2 >x", "2"), ("cp a b '2'>x (trong nháy)", "cp a b '2'>x", "2"),
                       ("cp a b \\2>x (thoát)", "cp a b \\2>x", "2"), ("cp a b\\ 2>x (cách được thoát)", "cp a b\\ 2>x", "b 2"),
                       ("cp a b2>x (chữ số giữa từ)", "cp a b2>x", "b2"), ("cp a b 2&>x (bash: `2` là đối số của cp)", "cp a b 2&>x", "2")):
    check("đối số giữ nguyên: " + label, [t for k, t, _ in T(c) if k == "file"], [want])
check("env -S 'cp a b 2>x': env không chuyển hướng - `2>x` là đối số", T("env -S 'cp a b 2>x'"), [("file", "2>x", "/w")])

shutil.rmtree(tmp, ignore_errors=True)
print(f"shell_writes.py fd #427 vòng 3: {'all checks passed' if not bad else str(bad) + ' FAILED'}")
sys.exit(1 if bad else 0)
PY
