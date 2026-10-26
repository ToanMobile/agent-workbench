#!/usr/bin/env bash
# bin/session_lock.py - backlog session_lock của issue #427 (vòng 3). Mỗi ca phải-chặn có một ca đối chứng vô hại phải-qua:
#   1. cp / mv / tee / install / rsync / ln / dd of= / touch vào checkout anh em CÙNG repo mà phiên khác còn sống giữ không được xét:
#      _file_write_hits chỉ xét checkout của chính phiên; vòng 2 (mục 5) chỉ xét redirect tuyệt đối. Nay đích ghi file (hooks/shell_writes.py
#      "file") được xét theo khoá các checkout cùng họ như redirect (_held_at); cwd không phải repo: theo khoá mọi repo.
#   2. đích tương đối `../<anh em>/f` (redirect và các lệnh mục 1) được tính từ thư mục mà cd (chữ) dẫn tới rồi mới xét khoá:
#      `echo x > ../<anh em bị giữ>/f` phải chặn, `echo x > ../<worktree rảnh của chính nó>/f` qua.
#   SLT_KIT=<thư mục kit>   chạy cùng bảng trên một bản kit khác (bản chưa sửa: ĐỎ).
# bash 3.2 compatible wrapper; the checks are python3 (stdlib only).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_ALLOW_SHARED_CHECKOUT CLAUDE_PROJECT_DIR
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${SLT_KIT:-$DEVKIT_DIR}"
export PYTHONDONTWRITEBYTECODE=1
python3 -I - "$KIT" <<'PY'
import json, os, shutil, subprocess, sys, tempfile, time

KIT = os.path.realpath(sys.argv[1])
SCRIPT = os.path.join(KIT, "bin", "session_lock.py")
tmp = os.path.realpath(tempfile.mkdtemp(prefix="slr3_"))
S = os.path.join(tmp, "scratch")
PLAIN = os.path.join(tmp, "plain")
os.makedirs(S)
os.makedirs(PLAIN)
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
    sh("git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
    return d


def gitdir(d):
    return sh("git", "-C", d, "rev-parse", "--absolute-git-dir").strip()


def hold(gdir, sid, cwd, pid=None):   # khoá của một phiên khác còn sống (pid của chính tiến trình test)
    with open(os.path.join(gdir, "devkit-session.lock"), "w", encoding="utf-8") as f:
        json.dump({"session_id": sid, "started": time.time(), "heartbeat": time.time(), "cwd": cwd, "pid": pid or os.getpid(), "gitdir": gdir}, f)


def hook(cmd, cwd, sid="me", env_extra=None, trunk="0"):
    env = {k: v for k, v in os.environ.items() if k not in ("DEVKIT_ALLOW_SHARED_CHECKOUT", "CLAUDE_PROJECT_DIR")}
    env["WORKTREE_TRUNK_MODE"] = trunk
    env.update(env_extra or {})
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


A = repo("locked")   # checkout của repo khác, phiên khác đang giữ
B = repo("other")    # repo rảnh
hold(gitdir(A), "holder", A)
FM = repo("family")   # FW: worktree rảnh của phiên; FW2: worktree anh em phiên khác giữ; FW3: khoá của phiên đã chết (rảnh)
FW, FW2, FW3 = (os.path.join(tmp, n) for n in ("family-wt", "family-wt2", "family-wt3"))
for w in (FW, FW2, FW3):
    sh("git", "-C", FM, "worktree", "add", "-q", "--detach", w)
hold(gitdir(FW2), "holder2", FW2)
dead = subprocess.Popen([sys.executable, "-c", "pass"])
dead.wait()
hold(gitdir(FW3), "gone", FW3, pid=dead.pid)
fam = lambda c: hook(c, FW)
NUL = "/tmp/a\x00b"

print("1. cp / mv / tee / install / rsync / ln / dd / touch vào worktree anh em bị giữ (từ FW; FW2 bị giữ)")
for label, c in (("cp", f"cp /etc/hosts {FW2}/f.txt"), ("cp -t DIR", f"cp -t {FW2} /etc/hosts"),
                 ("install", f"install -m 644 /etc/hosts {FW2}/f.txt"), ("rsync", f"rsync -a /etc/hosts {FW2}/"),
                 ("ln -s", f"ln -s /etc/hosts {FW2}/l"), ("mv", f"mv {FW}/a.txt {FW2}/b.txt"), ("tee", f"echo x | tee -a {FW2}/log.txt"),
                 ("dd of=", f"dd if=/dev/zero of={FW2}/z bs=1 count=1"), ("touch", f"touch {FW2}/f.txt"),
                 ("sau một git ghi ở FW: git commit -qm x; cp", f"git commit -qm x; cp /etc/hosts {FW2}/f.txt"),
                 ("bash -c 'cp …'", f"bash -c 'cp /etc/hosts {FW2}/f.txt'"),
                 ("cd <tmp> && cp … family-wt2/f.txt (cd chữ)", f"cd {tmp} && cp /etc/hosts family-wt2/f.txt"),
                 ("đích có NUL đứng trước: touch \"/tmp/a<NUL>b\" <FW2>/f.txt (không văng)", f"touch \"{NUL}\" {FW2}/f.txt"),
                 ("thư mục chưa có: mkdir -p <FW2>/new/d && cp … <FW2>/new/d/f", f"mkdir -p {FW2}/new/d && cp /etc/hosts {FW2}/new/d/f.txt")):
    check(label, fam(c), 2)
for label, c in (("cp vào worktree của chính nó", f"cp /etc/hosts {FW}/f.txt"),
                 ("cp đọc từ anh em bị giữ: cp <FW2>/f <scratch>/x", f"cp {FW2}/f.txt {S}/x"),
                 ("ln -s <FW2>/f <FW>/l (đích link ở anh em, link ở chính nó)", f"ln -s {FW2}/f.txt {FW}/l"),
                 ("rsync -a <FW2>/ <scratch>/copy/ (nguồn bị giữ)", f"rsync -a {FW2}/ {S}/copy/"),
                 ("dd if=<FW2>/f of=<scratch>/f", f"dd if={FW2}/f.txt of={S}/f.txt"),
                 ("tee <scratch>/log.txt", f"echo x | tee {S}/log.txt"),
                 ("cp vào worktree khoá cũ (phiên đã chết)", f"cp /etc/hosts {FW3}/f.txt"),
                 ("đích chỉ có NUL: touch \"/tmp/a<NUL>b\"", f"touch \"{NUL}\""),
                 ("cp vào repo rảnh khác", f"cp /etc/hosts {B}/f.txt")):
    check("  đối chứng: " + label, fam(c), 0)
NM = repo("nest")   # main bị giữ; worktree của phiên nằm TRONG thư mục main (.claude/worktrees/w)
NW = os.path.join(NM, ".claude", "worktrees", "w")
sh("git", "-C", NM, "worktree", "add", "-q", "--detach", NW)
hold(os.path.join(NM, ".git"), "holder4", NM)
check("cp … <main bị giữ>/f.txt (từ worktree lồng trong main)", hook(f"cp /etc/hosts {NM}/f.txt", NW), 2)
check("  đối chứng: cp … <worktree lồng của chính nó>/f.txt", hook(f"cp /etc/hosts {NW}/f.txt", NW), 0)
check("  đối chứng: cp … <git dir của chính nó, trong .git của main bị giữ>/info/x", hook(f"cp /etc/hosts {gitdir(NW)}/info/x", NW), 0)
check("rm -rf ../family-wt2 (xoá worktree anh em bị giữ)", fam("rm -rf ../family-wt2"), 2)
plain = lambda c: hook(c, PLAIN)
check("cwd không phải repo: cp … <A bị giữ>/f.txt", plain(f"cp /etc/hosts {A}/f.txt"), 2)
check("cwd không phải repo: echo x | tee <FW2>/log.txt", plain(f"echo x | tee {FW2}/log.txt"), 2)
check("  đối chứng: cwd không phải repo: cp … <B rảnh>/f.txt", plain(f"cp /etc/hosts {B}/f.txt"), 0)
check("  đối chứng: cwd không phải repo: cp … <scratch>/f.txt", plain(f"cp /etc/hosts {S}/f.txt"), 0)

print("2. đích tương đối ../<anh em> tính từ thư mục mà cd dẫn tới (từ FW; FW2 bị giữ)")
for label, c in (("echo x > ../family-wt2/f.txt", "echo x > ../family-wt2/f.txt"),
                 ("echo x >> \"../family-wt2/f.txt\"", "echo x >> \"../family-wt2/f.txt\""),
                 ("echo x 2> ../family-wt2/err.txt", "echo x 2> ../family-wt2/err.txt"),
                 ("cp … ../family-wt2/f.txt", "cp /etc/hosts ../family-wt2/f.txt"),
                 ("echo x | tee ../family-wt2/log.txt", "echo x | tee ../family-wt2/log.txt"),
                 ("cd .. && echo x > family-wt2/f.txt", "cd .. && echo x > family-wt2/f.txt"),
                 ("bash -c 'echo x > ../family-wt2/f.txt' (redirect của shell con)", "bash -c 'echo x > ../family-wt2/f.txt'"),
                 ("(cd .. && cp … family-wt2/f.txt)", "(cd .. && cp /etc/hosts family-wt2/f.txt)"),
                 ("cd \"$X\" && cp … ../family-wt2/f.txt (cd không biết: tính từ cwd, fail closed)", "cd \"$X\" && cp /etc/hosts ../family-wt2/f.txt"),
                 ("mkdir -p ../family-wt2/n/d && echo x > ../family-wt2/n/d/f.txt", "mkdir -p ../family-wt2/n/d && echo x > ../family-wt2/n/d/f.txt")):
    check(label, fam(c), 2)
for label, c in (("echo x > ../family-wt/f.txt (worktree của chính nó)", "echo x > ../family-wt/f.txt"),
                 ("echo x > f.txt", "echo x > f.txt"),
                 ("echo x > ../scratch/f.txt", "echo x > ../scratch/f.txt"),
                 ("echo \"a > ../family-wt2/f\" (trong nháy: không phải redirect)", "echo \"a > ../family-wt2/f\""),
                 ("bash -c 'echo x > ../family-wt/f.txt' (worktree của chính nó)", "bash -c 'echo x > ../family-wt/f.txt'"),
                 ("grep x ../family-wt2/f.txt > ../family-wt/out.txt (đọc anh em)", "grep x ../family-wt2/f.txt > ../family-wt/out.txt"),
                 ("cat ../family-wt2/f.txt > ../scratch/x; ls ../family-wt2", "cat ../family-wt2/f.txt > ../scratch/x; ls ../family-wt2"),
                 ("cd ../family-wt3 && echo x > f.txt (khoá cũ)", "cd ../family-wt3 && echo x > f.txt")):
    check("  đối chứng: " + label, fam(c), 0)
check("từ worktree lồng: echo x > ../../../f.txt (vào main bị giữ)", hook("echo x > ../../../f.txt", NW), 2)
check("  đối chứng: echo x > ../w/f.txt (worktree lồng của chính nó)", hook("echo x > ../w/f.txt", NW), 0)

shutil.rmtree(tmp, ignore_errors=True)
print(f"session_lock.py round 3 #427: {'all checks passed' if not bad else str(bad) + ' FAILED'}")
sys.exit(1 if bad else 0)
PY
