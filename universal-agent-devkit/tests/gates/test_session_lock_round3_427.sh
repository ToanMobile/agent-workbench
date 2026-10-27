#!/usr/bin/env bash
# bin/session_lock.py - backlog session_lock của issue #427 (vòng 3). Mỗi ca phải-chặn có một ca đối chứng vô hại phải-qua:
#   1. cp / mv / tee / install / rsync / ln / dd of= / touch vào checkout anh em CÙNG repo mà phiên khác còn sống giữ không được xét:
#      _file_write_hits chỉ xét checkout của chính phiên; vòng 2 (mục 5) chỉ xét redirect tuyệt đối. Nay đích ghi file (hooks/shell_writes.py
#      "file") được xét theo khoá các checkout cùng họ như redirect (_held_at); cwd không phải repo: theo khoá mọi repo.
#   2. đích tương đối `../<anh em>/f` (redirect và các lệnh mục 1) được tính từ thư mục mà cd (chữ) dẫn tới rồi mới xét khoá:
#      `echo x > ../<anh em bị giữ>/f` phải chặn, `echo x > ../<worktree rảnh của chính nó>/f` qua.
#   3. phiên chưa đăng ký ở project (không có <main>/.git/devkit-sessions/<id>.json) không có luật project / trunk: sau /clear từ cwd ngoài
#      repo, SessionEnd / SessionStart trả 0 trước khi gỡ / đăng ký - id mới không ở đâu cả, id cũ (SessionStart ghi, agent "claude") vẫn
#      ở project với pid của chính tiến trình claude. Nay: một mục agent "claude" của project có pid = tiến trình giữ hook (holder_pid,
#      start time khớp) thì phiên là của project. Test thừa hưởng CLAUDE_PROJECT_DIR không vấp: cha của hook là tiến trình test.
#   4. review vòng 3: (a) đích có NUL sau `~` (`~a<NUL>b`) làm expanduser văng ngoài try - hook exit 1 = cho qua cả dòng, cả luật trunk;
#      (b) redirect TUYỆT ĐỐI trong `bash -c "…"` / `sh -c` vào anh em bị giữ lọt (luật redirect của bash_collides không thấy `>` trong
#      nháy, _family_write_held bỏ mọi redirect tuyệt đối); (c) shell_writes giữ thư mục của cd sau khi `)` đóng subshell và sau `popd`:
#      `(cd ../<anh em bị giữ> && ls); echo x > out.txt` bị chặn nhầm - mỗi ca nới có ca đối nghịch phải-chặn; (d) đích chỉ là chữ số
#      (`cd <anh em bị giữ> && cp a 2`) bị bỏ qua dù shell_writes không còn đọc số fd của `2>` là đích.
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
                 ("đích rảnh đứng trước: touch <FW3>/a.txt <FW2>/b.txt (mỗi thư mục một lần hỏi git)", f"touch {FW3}/a.txt {FW2}/b.txt"),
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
                 ("cd \"$X\" && echo; cp … ../family-wt2/f.txt (đích tuyệt đối sau cd không biết vẫn xét: cp … <FW2>/f)",
                  f"cd \"$X\" && echo; cp /etc/hosts {FW2}/f.txt"),
                 ("mkdir -p ../family-wt2/n/d && echo x > ../family-wt2/n/d/f.txt", "mkdir -p ../family-wt2/n/d && echo x > ../family-wt2/n/d/f.txt")):
    check(label, fam(c), 2)
for label, c in (("echo x > ../family-wt/f.txt (worktree của chính nó)", "echo x > ../family-wt/f.txt"),
                 ("echo x > f.txt", "echo x > f.txt"),
                 ("echo x > ../scratch/f.txt", "echo x > ../scratch/f.txt"),
                 ("echo \"a > ../family-wt2/f\" (trong nháy: không phải redirect)", "echo \"a > ../family-wt2/f\""),
                 ("bash -c 'echo x > ../family-wt/f.txt' (worktree của chính nó)", "bash -c 'echo x > ../family-wt/f.txt'"),
                 ("grep x ../family-wt2/f.txt > ../family-wt/out.txt (đọc anh em)", "grep x ../family-wt2/f.txt > ../family-wt/out.txt"),
                 ("cat ../family-wt2/f.txt > ../scratch/x; ls ../family-wt2", "cat ../family-wt2/f.txt > ../scratch/x; ls ../family-wt2"),
                 ("cd ../family-wt3 && echo x > f.txt (khoá cũ)", "cd ../family-wt3 && echo x > f.txt"),
                 ("cd ../family-wt2 && cp -R . \"$M/k\" 2>/dev/null (`2>` là số fd, không phải đích; đích sau $M không xét)",
                  "cd ../family-wt2 && cp -R . \"$M/k\" 2>/dev/null")):
    check("  đối chứng: " + label, fam(c), 0)
check("từ worktree lồng: echo x > ../../../f.txt (vào main bị giữ)", hook("echo x > ../../../f.txt", NW), 2)
check("từ worktree lồng: rm -rf <main bị giữ> (đích là thư mục của checkout)", hook(f"rm -rf {NM}", NW), 2)
check("  đối chứng: echo x > ../w/f.txt (worktree lồng của chính nó)", hook("echo x > ../w/f.txt", NW), 0)
check("  đối chứng: cp … . (thư mục gốc của worktree lồng của chính nó, không phải main chứa nó)", hook("cp /etc/hosts .", NW), 0)
check("  đối chứng: cd \"$B\" && bash t.sh > ../base.log (cd không biết: đích tương đối không xét, corpus chặn nhầm)",
      hook("cd \"$B\" && bash t.sh > ../base.log", NW), 0)

print("3. phiên chưa đăng ký ở project: tiến trình claude của nó (holder_pid) đã đăng ký ở đó dưới id khác (sau /clear ngoài repo)")
PS_TOOL = r'''
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "bin"))
import session_lock as sl
print(sl.pid_start(int(sys.argv[2])) or "")
'''
my_start = subprocess.run([sys.executable, "-I", "-c", PS_TOOL, KIT, str(os.getpid())], capture_output=True, text=True).stdout.strip()
other = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(120)"])   # một pid khác còn sống


def register(top, name, **fields):   # mục registry ở main `top` của project (SessionStart ghi agent "claude")
    d = os.path.join(gitdir(top), "devkit-sessions")
    os.makedirs(d, exist_ok=True)
    rec = {"session_id": name, "pid": os.getpid(), "heartbeat": time.time(), "cwd": top, "status": "working"}
    rec.update(fields)
    with open(os.path.join(d, name + ".json"), "w", encoding="utf-8") as f:
        json.dump({k: v for k, v in rec.items() if v is not None}, f)


def unregister(top, name):
    os.remove(os.path.join(gitdir(top), "devkit-sessions", name + ".json"))


PM = repo("project")   # project của phiên, main bị giữ
hold(os.path.join(PM, ".git"), "holder3", PM, pid=other.pid)   # người giữ là tiến trình khác (không phải chính tiến trình giữ hook)
proj = lambda c, cwd=PLAIN: hook(c, cwd, sid="new", env_extra={"CLAUDE_PROJECT_DIR": PM})
register(PM, "old", agent="claude", pid_start=my_start or None)
check("cwd không phải repo: cd $X && git commit (PM bị giữ)", proj("cd $X && git commit -qm x"), 2)
check("từ repo khác B: cd $X && git commit (PM bị giữ)", proj("cd $X && git commit -qm x", cwd=B), 2)
check("  đối chứng: cd <B> && git commit (đích đã biết, rảnh)", proj(f"cd {B} && git commit -qm x"), 0)
unregister(PM, "old")
for label, fields in (("mục không có agent (ghi bởi heartbeat / test cũ)", {"agent": None}),
                      ("pid đúng nhưng start time khác (pid tái dùng)", {"agent": "claude", "pid_start": "Mon Jan  1 00:00:00 2001"}),
                      ("pid khác còn sống", {"agent": "claude", "pid": other.pid}),
                      ("pid là bool (True)", {"agent": "claude", "pid": True})):
    register(PM, "old", **fields)
    check("  đối chứng: " + label + ": cd $X && git commit", proj("cd $X && git commit -qm x"), 0)
    unregister(PM, "old")
check("  đối chứng: không có mục nào của tiến trình này", proj("cd $X && git commit -qm x"), 0)
TM = repo("tmain")   # repo trunk mode: main chỉ để gộp, phiên ở worktree TW
TW = os.path.join(tmp, "tmain-wt")
sh("git", "-C", TM, "worktree", "add", "-q", "--detach", TW)
sh("git", "-C", TM, "config", "devkit.trunkMode", "true")
tplain = lambda c: hook(c, PLAIN, sid="new", env_extra={"CLAUDE_PROJECT_DIR": TW}, trunk="1")
register(TM, "old", agent="claude", pid_start=my_start or None)
check("trunk mode, cwd không phải repo: git -C <TM main> commit", tplain(f"git -C {TM} commit -qm x"), 2)
check("trunk mode, cwd không phải repo: echo x > <TM main>/README.md", tplain(f"echo x > {TM}/README.md"), 2)
check("  đối chứng: git -C <TW worktree> commit", tplain(f"git -C {TW} commit -qm x"), 0)
check("  đối chứng: echo x > <scratch>/f.txt", tplain(f"echo x > {S}/f.txt"), 0)
unregister(TM, "old")
register(TM, "old", agent="claude", pid=other.pid)
check("  đối chứng: mục của tiến trình khác: git -C <TM main> commit (như trước: phiên không thuộc project)", tplain(f"git -C {TM} commit -qm x"), 0)
other.kill()
other.wait()

print("4a. review vòng 3: đích có NUL sau ~ không làm hook văng (exit 1 = cho qua cả dòng); các đích khác của dòng vẫn được xét")
N = "\x00"
own = lambda c: hook(c, FW2)   # checkout của chính phiên do holder2 giữ, có anh em (FM, FW, FW3): _family_write_held có chạy
for d in (FW, FW2):
    with open(os.path.join(d, "s.txt"), "w", encoding="utf-8") as f:
        f.write("a\n")
for label, c in (("ở FW2 bị giữ: echo pwn > src.txt; echo > \"~a<NUL>b\" (từng văng ở _family_write_held)", f'echo pwn > src.txt; echo > "~a{N}b"'),
                 ("ở FW2 bị giữ: touch \"~<NUL>\" src.txt (từng văng ở _file_write_hits)", f'touch "~{N}" src.txt'),
                 ("ở FW2 bị giữ: echo > \"/tmp/a<NUL>b\"; echo pwn > src.txt (từng văng ở luật redirect)", f'echo > "/tmp/a{N}b"; echo pwn > src.txt'),
                 ("ở FW2 bị giữ: cd \"~a<NUL>b\"; cp … src.txt (shell_writes từng văng: luật ghi file tắt)", f'cd "~a{N}b"; cp /etc/hosts src.txt'),
                 ("ở FW2 bị giữ: sed -i s/a/b/ \"~a<NUL>b\" s.txt", f'sed -i s/a/b/ "~a{N}b" s.txt')):
    check(label, own(c), 2)
check("từ FW: touch \"~a<NUL>b\" <FW2>/f.txt", fam(f'touch "~a{N}b" {FW2}/f.txt'), 2)
for label, c in (("echo > \"~a<NUL>b\"", f'echo > "~a{N}b"'), ("touch \"~<NUL>\" src.txt", f'touch "~{N}" src.txt'),
                 ("echo > \"/tmp/a<NUL>b\"", f'echo > "/tmp/a{N}b"'), ("cd \"~a<NUL>b\"; cp … src.txt", f'cd "~a{N}b"; cp /etc/hosts src.txt'),
                 ("sed -i s/a/b/ \"~a<NUL>b\" s.txt", f'sed -i s/a/b/ "~a{N}b" s.txt')):
    check("  đối chứng: từ FW rảnh: " + label, fam(c), 0)
unregister(TM, "old")
register(TM, "old", agent="claude", pid_start=my_start or None)
check("trunk mode, cwd không phải repo: git -C <TM main> commit -qm x; touch \"~a<NUL>b\"", tplain(f'git -C {TM} commit -qm x; touch "~a{N}b"'), 2)
check("  đối chứng: trunk mode, cwd không phải repo: touch \"~a<NUL>b\"", tplain(f'touch "~a{N}b"'), 0)
tw = lambda c: hook(c, TW, sid="tw", trunk="1")
check("trunk mode, từ TW: cd <TM main> && touch \"~a<NUL>b\" x", tw(f'cd {TM} && touch "~a{N}b" x'), 2)
check("trunk mode, từ TW: X=\"~a<NUL>b\"; cd \"$X\"; touch x (thư mục không biết: fail closed)", tw(f'X="~a{N}b"; cd "$X"; touch x'), 2)
check("  đối chứng: trunk mode, từ TW: cd <TW> && touch \"~a<NUL>b\" x", tw(f'cd {TW} && touch "~a{N}b" x'), 0)
check("  đối chứng: trunk mode, từ TW: X=/tmp; cd \"$X\"; touch x", tw('X=/tmp; cd "$X"; touch x'), 0)

print("4b. redirect tuyệt đối trong bash -c \"…\" / sh -c vào checkout bị giữ")
for label, c, cwd in (("bash -c \"echo x > <FW2>/f.txt\"", f'bash -c "echo x > {FW2}/f.txt"', FW),
                      ("sh -c 'echo x >> <FW2>/f.txt'", f"sh -c 'echo x >> {FW2}/f.txt'", FW),
                      ("bash -c \"echo x 2> <FW2>/err.txt\"", f'bash -c "echo x 2> {FW2}/err.txt"', FW),
                      ("zsh -c \"cd /tmp && echo x > <FW2>/f.txt\"", f'zsh -c "cd /tmp && echo x > {FW2}/f.txt"', FW),
                      ("cwd không phải repo: bash -c \"echo x > <FW2>/f.txt\"", f'bash -c "echo x > {FW2}/f.txt"', PLAIN),
                      ("cwd không phải repo: bash -c \"echo x > <A bị giữ>/f.txt\"", f'bash -c "echo x > {A}/f.txt"', PLAIN)):
    check(label, hook(c, cwd), 2)
for label, c, cwd in (("bash -c \"echo x > <FW của chính nó>/f.txt\"", f'bash -c "echo x > {FW}/f.txt"', FW),
                      ("bash -c \"echo x > <scratch>/f.txt\"", f'bash -c "echo x > {S}/f.txt"', FW),
                      ("bash -c \"echo x > /dev/null 2>&1\"", 'bash -c "echo x > /dev/null 2>&1"', FW),
                      ("bash -c \"echo x > <FW3 khoá cũ>/f.txt\"", f'bash -c "echo x > {FW3}/f.txt"', FW),
                      ("echo \"x > <FW2>/f.txt\" (không có shell con: chữ trong nháy)", f'echo "x > {FW2}/f.txt"', FW),
                      ("cwd không phải repo: bash -c \"echo x > <B rảnh>/f.txt\"", f'bash -c "echo x > {B}/f.txt"', PLAIN)):
    check("  đối chứng: " + label, hook(c, cwd), 0)

print("4c. `)` đóng subshell và popd đưa thư mục về (trước: giữ thư mục của cd - chặn nhầm); ca đối nghịch vẫn chặn")
for label, c in (("(cd ../family-wt2 && ls); echo x > out.txt", "(cd ../family-wt2 && ls); echo x > out.txt"),
                 ("pushd ../family-wt2 && ls && popd && echo x > out.txt", "pushd ../family-wt2 && ls && popd && echo x > out.txt"),
                 ("X=$(cd ../family-wt2 && pwd); echo x > out.txt", "X=$(cd ../family-wt2 && pwd); echo x > out.txt"),
                 ("pushd ../family-wt2 >/dev/null && ls && popd >/dev/null; cp … out.txt",
                  "pushd ../family-wt2 >/dev/null && ls && popd >/dev/null; cp /etc/hosts out.txt"),
                 ("(cd ../family-wt2 && ls) && echo \"$(date)\" > out.txt (\"$( )\" không nháy lồng)",
                  "(cd ../family-wt2 && ls) && echo \"$(date)\" > out.txt")):
    check("  đối chứng (nới): " + label, fam(c), 0)
for label, c in (("(cd ../family-wt2 && echo x > out.txt)", "(cd ../family-wt2 && echo x > out.txt)"),
                 ("cd ../family-wt2; (ls); echo x > out.txt", "cd ../family-wt2; (ls); echo x > out.txt"),
                 ("{ cd ../family-wt2; }; echo x > out.txt (nhóm { } không phải subshell)", "{ cd ../family-wt2; }; echo x > out.txt"),
                 ("pushd ../family-wt2 && pushd /tmp && popd && echo x > out.txt", "pushd ../family-wt2 && pushd /tmp && popd && echo x > out.txt"),
                 ("(cd ../family-wt2 && cat <(ls) > out.txt) (`)` của <( ) không đóng subshell ngoài)", "(cd ../family-wt2 && cat <(ls) > out.txt)"),
                 ("popd; echo x > ../family-wt2/f.txt (ngăn rỗng: popd không đổi thư mục)", "popd; echo x > ../family-wt2/f.txt"),
                 ("cd ../family-wt2 && popd; echo x > out.txt", "cd ../family-wt2 && popd; echo x > out.txt"),
                 ("cd ../family-wt2 && (pushd /tmp) && popd; echo x > out.txt (pushd trong subshell mất khi nó đóng)",
                  "cd ../family-wt2 && (pushd /tmp) && popd; echo x > out.txt"),
                 ("(cd ../family-wt2 && case a in a) echo x > out.txt;; esac) (`a)` không đóng subshell)",
                  "(cd ../family-wt2 && case a in a) echo x > out.txt;; esac)"),
                 ("(cd ../family-wt2; echo \")\"; echo x > out.txt) (`)` trong nháy)", "(cd ../family-wt2; echo \")\"; echo x > out.txt)"),
                 ("(cd ../family-wt2; echo \\); echo x > out.txt) (`)` bị thoát)", "(cd ../family-wt2; echo \\); echo x > out.txt)"),
                 ("(cd ../family-wt2; echo \")\" \"(\"; echo x > out.txt) (ngoặc trong nháy cân nhau)",
                  "(cd ../family-wt2; echo \")\" \"(\"; echo x > out.txt)"),
                 ("(cd ../family-wt2; echo $'\\')' \\' $'\\'(' \\'; echo x > out.txt) (`$'…'`: shlex đọc nháy khác shell)",
                  "(cd ../family-wt2; echo $'\\')' \\' $'\\'(' \\'; echo x > out.txt)"),
                 ("(cd ../family-wt2; echo \"$(echo \")(\") x\"; echo x > out.txt) (nháy lồng trong \"$( )\")",
                  "(cd ../family-wt2; echo \"$(echo \")(\") x\"; echo x > out.txt)"),
                 ("cd ../family-wt2 && (cd .. && pushd /tmp); popd; echo x > out.txt (ngăn của subshell mất: popd lỗi)",
                  "cd ../family-wt2 && (cd .. && pushd /tmp); popd; echo x > out.txt"),
                 ("pushd ../family-wt2 && eval \"pushd /tmp\" && popd && echo x > out.txt (eval đổi ngăn)",
                  "pushd ../family-wt2 && eval \"pushd /tmp\" && popd && echo x > out.txt"),
                 ("pushd ../family-wt2 && dirs -c && popd; echo x > out.txt (dirs -c xoá ngăn)",
                  "pushd ../family-wt2 && dirs -c && popd; echo x > out.txt")):
    check(label, fam(c), 2)
# siết: thư mục về checkout của chính phiên (bị giữ) - trước tính ở /tmp, lọt
check("ở FW2 bị giữ: (cd /tmp && ls); cp … out.txt", own("(cd /tmp && ls); cp /etc/hosts out.txt"), 2)
check("ở FW2 bị giữ: pushd /tmp && popd && cp … out.txt", own("pushd /tmp && popd && cp /etc/hosts out.txt"), 2)
check("  đối chứng: ở FW2 bị giữ: (cd /tmp && cp … out.txt)", own("(cd /tmp && cp /etc/hosts out.txt)"), 0)

print("4d. đích chỉ là chữ số là đích thật (shell_writes không còn đọc số fd của `2>` là đích)")
check("cd ../family-wt2 && cp … 2", fam("cd ../family-wt2 && cp /etc/hosts 2"), 2)
check("cd ../family-wt2 && cp … b.txt 2 >/dev/null (có cách: `2` là đích thật)", fam("cd ../family-wt2 && cp /etc/hosts b.txt 2 >/dev/null"), 2)
check("  đối chứng: cp … 2 (ở FW của chính nó)", fam("cp /etc/hosts 2"), 0)
check("  đối chứng: cd ../family-wt3 && cp … 2 (khoá cũ)", fam("cd ../family-wt3 && cp /etc/hosts 2"), 0)
check("  đối chứng: cd ../family-wt2 && ls 2>/dev/null (`2>` là số fd, không phải đích)", fam("cd ../family-wt2 && ls 2>/dev/null"), 0)

shutil.rmtree(tmp, ignore_errors=True)
print(f"session_lock.py round 3 #427: {'all checks passed' if not bad else str(bad) + ' FAILED'}")
sys.exit(1 if bad else 0)
PY
