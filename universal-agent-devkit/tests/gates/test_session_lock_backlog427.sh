#!/usr/bin/env bash
# bin/session_lock.py - backlog session_lock của issue #427 (vòng 2). Mỗi ca phải-chặn có một ca đối chứng vô hại phải-qua; ca "đơn điệu"
# chặn ở cả bản cũ lẫn bản mới (chỗ bản mới nới ra không được mở lỗ):
#   1. cwd không phải repo: hook trả 0 trước mọi phép xét (`git -C <checkout bị giữ> commit`, redirect, Edit từ một thư mục thường).
#   2. phép gán / cd trong thân heredoc chạy ở shell con (`bash <<EOF`, `cat <<EOF | bash`) lọt ra shell cha: biến thành "không biết",
#      repo khác bị giữ thì lọt (walk); trunk mode lấy luôn giá trị trong thân (_expand_static_vars).
#   3. `cat <<EOF | bash # c` (comment làm bash có toán hạng) và `# … <<EOF` / `echo "<<EOF"` mà dòng `EOF` về sau biến các dòng giữa
#      thành thân dữ liệu: lệnh ở đó không được xét.
#   4. `_ps` thử lại: mỗi tiến trình hook một hạn tổng cho mọi lần gọi ps (ps giả chậm trên PATH).
#   5. bash_collides chỉ xét redirect vào checkout của phiên: `echo x > <worktree anh em bị giữ>/f` lọt.
#   6. (chặn nhầm) heredoc dữ liệu xoá luôn giá trị thật gán trước đó (trunk mode) - giữ khi delimiter trong nháy và lệnh là cat > f / tee f /
#      git commit -F -.
#   7. (chặn nhầm) thân S2 có for / if làm mọi biến thành không biết: `git -C "$W"` với W = worktree của chính nó bị chặn.
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
tmp = os.path.realpath(tempfile.mkdtemp(prefix="slb427_"))
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
    sh("git", "init", "-q", d)
    sh("git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
    return d


def gitdir(d):
    return sh("git", "-C", d, "rev-parse", "--absolute-git-dir").strip()


def hold(gdir, sid, cwd):   # khoá của một phiên khác còn sống (pid của chính tiến trình test)
    with open(os.path.join(gdir, "devkit-session.lock"), "w", encoding="utf-8") as f:
        json.dump({"session_id": sid, "started": time.time(), "heartbeat": time.time(), "cwd": cwd, "pid": os.getpid(), "gitdir": gdir}, f)


def hook(cmd, cwd, sid="me", env_extra=None, tool="Bash", ti=None):
    env = {k: v for k, v in os.environ.items() if k not in ("DEVKIT_ALLOW_SHARED_CHECKOUT", "CLAUDE_PROJECT_DIR")}
    env["WORKTREE_TRUNK_MODE"] = "0"   # luật một-checkout-một-phiên (trunk mode xét ở unit bên dưới)
    env.update(env_extra or {})
    p = {"hook_event_name": "PreToolUse", "session_id": sid, "cwd": cwd, "tool_name": tool, "tool_input": ti or {"command": cmd}}
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
FM = repo("family")   # FW: worktree rảnh của phiên; FW2: worktree anh em phiên khác giữ
FW, FW2 = os.path.join(tmp, "family-wt"), os.path.join(tmp, "family-wt2")
sh("git", "-C", FM, "worktree", "add", "-q", "--detach", FW)
sh("git", "-C", FM, "worktree", "add", "-q", "--detach", FW2)
hold(gitdir(FW2), "holder2", FW2)
fromB = lambda c: hook(c, B)
fam = lambda c: hook(c, FW)
edit = lambda path, cwd: hook("", cwd, tool="Edit", ti={"file_path": path, "old_string": "a", "new_string": "b"})

print("1. cwd không phải repo (thư mục thường PLAIN): đích ghi vẫn được xét")
plain = lambda c, **kw: hook(c, PLAIN, **kw)
check("git -C <A bị giữ> commit", plain(f"git -C {A} commit -qm x"), 2)
check("  đối chứng: git -C <B rảnh> commit", plain(f"git -C {B} commit -qm x"), 0)
check("cd <A> && git commit", plain(f"cd {A} && git commit -qm x"), 2)
check("  đối chứng: cd <B> && git commit", plain(f"cd {B} && git commit -qm x"), 0)
check("echo x > <A>/f.txt", plain(f"echo x > {A}/f.txt"), 2)
check("  đối chứng: echo x > <scratch>/f.txt; ls 2>/dev/null", plain(f"echo x > {S}/f.txt; ls 2>/dev/null"), 0)
check("Edit <A>/f.txt", edit(f"{A}/f.txt", PLAIN), 2)
check("  đối chứng: Edit <B>/f.txt", edit(f"{B}/f.txt", PLAIN), 0)
PM = repo("project")   # project của phiên, đăng ký ở đó (SessionStart), main bị giữ
os.makedirs(os.path.join(PM, ".git", "devkit-sessions"))
with open(os.path.join(PM, ".git", "devkit-sessions", "me.json"), "w", encoding="utf-8") as f:
    json.dump({"session_id": "me", "pid": os.getpid(), "heartbeat": time.time(), "cwd": PM, "status": "working"}, f)
hold(os.path.join(PM, ".git"), "holder3", PM)
check("đích không biết (cd $X && git commit), project PM bị giữ", plain("cd $X && git commit -qm x", env_extra={"CLAUDE_PROJECT_DIR": PM}), 2)
check("  đối chứng: phiên không đăng ký ở project", plain("cd $X && git commit -qm x", sid="stranger", env_extra={"CLAUDE_PROJECT_DIR": PM}), 0)

print("2. phép gán / cd trong thân chạy ở shell con không tới shell cha (từ B; A bị giữ)")
check("M=<A>; bash <<'EOF' M=<B> EOF; git -C \"$M\" commit", fromB(f"M={A}; bash <<'EOF'\nM={B}\nEOF\ngit -C \"$M\" commit -qm x"), 2)
check("M=<A>; cat <<'EOF' | bash  M=<B> EOF; git -C \"$M\" commit", fromB(f"M={A}; cat <<'EOF' | bash\nM={B}\nEOF\ngit -C \"$M\" commit -qm x"), 2)
check("cd <A> <nl> bash <<'EOF' cd <B> EOF <nl> git commit", fromB(f"cd {A}\nbash <<'EOF'\ncd {B}\nEOF\ngit commit -qm x"), 2)
check("  đối chứng: M=<B>; bash <<'EOF' echo hi EOF; git -C \"$M\" commit", fromB(f"M={B}; bash <<'EOF'\necho hi\nEOF\ngit -C \"$M\" commit -qm x"), 0)
check("  đối chứng: M=<B>; bash <<'EOF' M=<A> EOF; git -C \"$M\" commit (M của shell cha là B)",
      fromB(f"M={B}; bash <<'EOF'\nM={A}\nEOF\ngit -C \"$M\" commit -qm x"), 0)
check("đơn điệu: M=<FW2>; bash <<'EOF' M=<FW> EOF; git -C \"$M\" commit (từ FW)", fam(f"M={FW2}; bash <<'EOF'\nM={FW}\nEOF\ngit -C \"$M\" commit -qm x"), 2)

print("3. comment: `| bash # c`, `# … <<EOF`, `<<EOF` trong nháy (từ B; A bị giữ)")
check("cat <<'EOF' | bash # c  git -C <A> commit", fromB(f"cat <<'EOF' | bash # chạy\ngit -C {A} commit -m x\nEOF"), 2)
check("  đối chứng: cat <<'EOF' | wc -l # c  (thân là dữ liệu)", fromB(f"cat <<'EOF' | wc -l # đếm\ngit -C {A} commit -m x\nEOF"), 0)
check("cat <<'EOF' | # c <nl> … EOF <nl> bash (ống nối qua comment)", fromB(f"cat <<'EOF' | # c\ngit -C {A} commit -m x\nEOF\nbash"), 2)
check("  đối chứng: cat <<'EOF' | # c <nl> … EOF <nl> wc -l", fromB(f"cat <<'EOF' | # c\ngit -C {A} commit -m x\nEOF\nwc -l"), 0)
check("# dùng cat <<EOF <nl> git -C <A> commit <nl> EOF", fromB(f"# dùng cat <<EOF\ngit -C {A} commit -m x\nEOF"), 2)
check("echo x # <<EOF <nl> git -C <A> commit <nl> EOF", fromB(f"echo x # <<EOF\ngit -C {A} commit -m x\nEOF"), 2)
check("echo \"<<EOF\" <nl> git -C <A> commit <nl> EOF (<< trong nháy)", fromB(f"echo \"<<EOF\"\ngit -C {A} commit -m x\nEOF"), 2)
check("W=<B> <nl> # x <<EOF <nl> W=<A> <nl> EOF <nl> git -C \"$W\" commit (dòng giữa là lệnh)", fromB(f"W={B}\n# x <<EOF\nW={A}\nEOF\ngit -C \"$W\" commit -qm x"), 2)
check("  đối chứng: cat <<EOF <nl> git -C <A> commit <nl> EOF (thân dữ liệu)", fromB(f"cat <<EOF\ngit -C {A} commit -m x\nEOF"), 0)
check("  đối chứng: gh pr create --title \"x (#427)\" --body \"$(cat <<'EOF' … EOF )\"",
      fromB(f"gh pr create --title \"x (#427)\" --body \"$(cat <<'EOF'\ngit -C {A} commit -m x\nEOF\n)\""), 0)
check("đơn điệu: W=<A> <nl> # x <<EOF <nl> W=<B> <nl> EOF <nl> git -C \"$W\" commit (cách đọc: heredoc dữ liệu)",
      fromB(f"W={A}\n# x <<EOF\nW={B}\nEOF\ngit -C \"$W\" commit -qm x"), 2)

print("5. redirect vào checkout khác cùng repo mà phiên khác giữ (từ FW; FW2 bị giữ)")
check("echo x > <FW2>/f.txt", fam(f"echo x > {FW2}/f.txt"), 2)
check("git commit -qm x; echo x >> \"<FW2>/f.txt\" (sau một git ghi ở FW)", fam(f"git commit -qm x; echo x >> \"{FW2}/f.txt\""), 2)
check("echo x > <FW2>/new/dir/f.txt (thư mục chưa có: cha gần nhất quyết)", fam(f"mkdir -p {FW2}/new/dir && echo x > {FW2}/new/dir/f.txt"), 2)
check("  đối chứng: echo x > <FW>/f.txt (worktree của chính nó)", fam(f"echo x > {FW}/f.txt"), 0)
check("  đối chứng: echo x > <scratch>/f.txt 2>/dev/null", fam(f"echo x > {S}/f.txt 2>/dev/null"), 0)
NM = repo("nest")   # main bị giữ; worktree của phiên nằm TRONG thư mục main (.claude/worktrees/w)
NW = os.path.join(NM, ".claude", "worktrees", "w")
sh("git", "-C", NM, "worktree", "add", "-q", "--detach", NW)
hold(os.path.join(NM, ".git"), "holder4", NM)
check("echo x > <main bị giữ>/f.txt (từ worktree lồng trong main)", hook(f"echo x > {NM}/f.txt", NW), 2)
check("  đối chứng: echo x > <worktree lồng của chính nó>/f.txt", hook(f"echo x > {NW}/f.txt", NW), 0)

print("7. thân S2 có for / if (từ FW; FW2 bị giữ)")
S2 = lambda w, body, head=None: fam(f"W={w}\n" + (head or f"cat <<'EOF' | tee {S}/log | bash") + f"\n{body}\nEOF\ngit -C \"$W\" commit -qm x")
check("W=<FW> … cat <<'EOF' | tee log | bash  for … done  EOF; git -C \"$W\" commit", S2(FW, "for f in a b; do echo $f; done"), 0)
check("W=<FW> … thân có if … fi", S2(FW, "if true; then echo y; fi"), 0)
check("  phải chặn: W=<FW2> … for … done", S2(FW2, "for f in a b; do echo $f; done"), 2)
check("đơn điệu: if trong shell cha: W=<FW> <nl> if true; then W=<FW2>; fi <nl> S2 … git -C \"$W\"",
      fam(f"W={FW}\nif true; then W={FW2}; fi\ncat <<'EOF' | tee {S}/log | bash\nfor f in a; do :; done\nEOF\ngit -C \"$W\" commit -qm x"), 2)
check("`<<EOF` trong nháy không mở heredoc: echo \"<<EOF\" | tee log | bash <nl> for … W=<FW2> … done (dòng của shell cha)",
      S2(FW, f"for x in a; do W={FW2}; done", head=f"echo \"<<EOF\" | tee {S}/log | bash"), 2)
check("đơn điệu: thân nạp cho source: source /dev/stdin <<'EOF' for … W=<FW2> … done",
      S2(FW, f"for x in a; do W={FW2}; done", head="source /dev/stdin <<'EOF'"), 2)

print("2 + 3 + 6 trunk mode: trunk_write (main TM chỉ để gộp, phiên ở worktree TW)")
TM = os.path.join(tmp, "tmain")
os.makedirs(TM)
sh("git", "init", "-q", "-b", "main", TM)
with open(os.path.join(TM, "README.md"), "w", encoding="utf-8") as f:
    f.write("r\n")
sh("git", "-C", TM, "add", "-A")
sh("git", "-C", TM, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "i")
TW = os.path.join(tmp, "tmain-wt")
sh("git", "-C", TM, "worktree", "add", "-q", "--detach", TW)
sh("git", "-C", TM, "config", "devkit.trunkMode", "true")
UNIT = r'''
import json, os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "bin"))
import session_lock as sl
main, sw = sl.trunk_main(sys.argv[2])
assert main and sw, "trunk mode not seen"
print(json.dumps([bool(sl.trunk_write("Bash", {"command": c}, c, sys.argv[3], main, sw)) for c in json.loads(sys.argv[4])]))
'''
rows = [   # (want, label, command)
    (True, "2: M=<TM>; bash <<'EOF' M=/tmp/x EOF <nl> echo > $M/README.md", f"M={TM}; bash <<'EOF'\nM=/tmp/x\nEOF\necho evil > $M/README.md"),
    (True, "2: M=<TM>; cat <<'EOF' | bash  M=/tmp/x EOF <nl> echo > $M/README.md", f"M={TM}; cat <<'EOF' | bash\nM=/tmp/x\nEOF\necho evil > $M/README.md"),
    (False, "  đối chứng: bash <<'EOF' O=<scratch>; echo > $O/f EOF (thân dùng biến của chính nó)", f"bash <<'EOF'\nO={S}\necho ok > $O/f.txt\nEOF"),
    (False, "  đối chứng: M=<scratch>; bash <<'EOF' echo hi EOF <nl> echo > $M/f", f"M={S}; bash <<'EOF'\necho hi\nEOF\necho ok > $M/f.txt"),
    (True, "2: M=<TM> <nl> true <<A; bash <<B <nl> A <nl> M=/tmp/x <nl> B <nl> echo > $M/README.md (S3: shell con ở heredoc thứ hai)",
     f"M={TM}\ntrue <<A; bash <<B\nA\nM=/tmp/x\nB\necho evil > $M/README.md"),
    (False, "  đối chứng: S=<scratch>; python3 - <<'EOF' S='<scratch>' EOF <nl> echo > \"$S/f\" (thân python: không phải phép gán shell)",
     f"S={S}; python3 - <<'EOF'\nS='{S}'\nprint(S)\nEOF\necho ok > \"$S/f.txt\""),
    (True, "3: cat <<'EOF' | bash # c  echo > <TM>/README.md  EOF", f"cat <<'EOF' | bash # c\necho evil > {TM}/README.md\nEOF"),
    (True, "3: cat <<'EOF' | bash # c  git -C <TM> commit  EOF", f"cat <<'EOF' | bash # c\ngit -C {TM} commit -qm x\nEOF"),
    (True, "3: # dùng cat <<EOF <nl> git -C <TM> commit <nl> EOF", f"# dùng cat <<EOF\ngit -C {TM} commit -qm x\nEOF"),
    (False, "  đối chứng: cat <<'EOF' | bash # c  echo > <scratch>/o.txt  EOF", f"cat <<'EOF' | bash # c\necho ok > {S}/o.txt\nEOF"),
    (True, "3: W=<TW> <nl> # x <<EOF <nl> W=<TM> <nl> EOF <nl> git -C \"$W\" commit (dòng giữa là lệnh)",
     f"W={TW}\n# x <<EOF\nW={TM}\nEOF\ngit -C \"$W\" commit -qm x"),
    (True, "đơn điệu: W=<TM> <nl> # x <<EOF <nl> W=<TW> <nl> EOF <nl> git -C \"$W\" commit (cách đọc: heredoc dữ liệu)",
     f"W={TM}\n# x <<EOF\nW={TW}\nEOF\ngit -C \"$W\" commit -qm x"),
    (False, "  đối chứng: W=<TW> <nl> # x <<EOF <nl> echo hi <nl> EOF <nl> git -C \"$W\" commit", f"W={TW}\n# x <<EOF\necho hi\nEOF\ngit -C \"$W\" commit -qm x"),
    (False, "6: S=<scratch> <nl> cat > \"$S/run.sh\" <<'EOF' S=/tmp/other EOF <nl> echo > \"$S/log\"",
     f"S={S}\ncat > \"$S/run.sh\" <<'EOF'\nS=/tmp/other\nEOF\necho ok > \"$S/log\""),
    (False, "6: … cat >> \"$S/run.sh\" <<'EOF'", f"S={S}\ncat >> \"$S/run.sh\" <<'EOF'\nS=/tmp/other\nEOF\necho ok > \"$S/log\""),
    (False, "6: … tee \"$S/a.txt\" <<'EOF'", f"S={S}\ntee \"$S/a.txt\" <<'EOF'\nS=/tmp/other\nEOF\necho ok > \"$S/log\""),
    (False, "6: … git commit -qF - <<'EOF'", f"S={S}\ngit commit -qF - <<'EOF'\nS=/tmp/other\nEOF\necho ok > \"$S/log\""),
    (True, "  phải chặn: M=<TM> <nl> cat > <scratch>/n <<'EOF' M=/tmp/x EOF <nl> echo > $M/README.md (giá trị trước là main)",
     f"M={TM}\ncat > {S}/n <<'EOF'\nM=/tmp/x\nEOF\necho evil > $M/README.md"),
    (True, "đơn điệu: delimiter không nháy: S=<scratch> <nl> cat > f <<EOF S=/tmp/other EOF <nl> echo > \"$S/log\"",
     f"S={S}\ncat > \"$S/run.sh\" <<EOF\nS=/tmp/other\nEOF\necho ok > \"$S/log\""),
    (True, "đơn điệu: lệnh không phải đích chép: sort <<'EOF' …", f"S={S}\nsort <<'EOF'\nS=/tmp/other\nEOF\necho ok > \"$S/log\""),
    (True, "đơn điệu: cat là hàm: cat() { . /dev/stdin; } … cat > f <<'EOF' …",
     f"cat() {{ . /dev/stdin; }}\nS={S}\ncat > \"$S/run.sh\" <<'EOF'\nS={TM}\nEOF\necho evil > \"$S/README.md\""),
    (True, "đơn điệu: cat > f <<'EOF' … | bash (ống vào shell)", f"S={S}\ncat <<'EOF' > \"$S/x\" | bash\nS={TM}\nEOF\necho evil > \"$S/README.md\""),
]
env = {k: v for k, v in os.environ.items() if k not in ("WORKTREE_TRUNK_MODE", "CLAUDE_PROJECT_DIR")}
r = subprocess.run([sys.executable, "-I", "-c", UNIT, KIT, TM, TW, json.dumps([c for _w, _l, c in rows])], capture_output=True, text=True, env=env, timeout=120)
got = json.loads(r.stdout) if r.returncode == 0 else [None] * len(rows)
if r.returncode != 0:
    print(r.stderr[-800:])
for (want, label, _c), g in zip(rows, got):
    check(label, g, want)

print("4. ps chậm: một hạn tổng cho mọi lần gọi ps của một tiến trình hook (ps giả trên PATH)")
FAKE = os.path.join(tmp, "fakebin")
os.makedirs(FAKE)


def fake_ps(delay, out):
    with open(os.path.join(FAKE, "ps"), "w", encoding="utf-8") as f:
        f.write(f"#!{sys.executable} -I\nimport time\ntime.sleep({delay})\nprint({out!r})\n")
    os.chmod(os.path.join(FAKE, "ps"), 0o755)


PROBE = r'''
import json, os, sys, time
sys.path.insert(0, os.path.join(sys.argv[1], "bin"))
import session_lock as sl
t0, res = time.monotonic(), [sl.is_pid_alive(os.getpid(), "Mon Jan  1 00:00:00 2001") for _ in range(int(sys.argv[2]))]
print(json.dumps([res, time.monotonic() - t0]))
'''


def probe(calls):
    env = dict(os.environ, PATH=FAKE + os.pathsep + os.environ.get("PATH", ""))
    r = subprocess.run([sys.executable, "-I", "-c", PROBE, KIT, str(calls)], capture_output=True, text=True, env=env, timeout=60)
    return json.loads(r.stdout) if r.returncode == 0 else [[r.stderr[-300:]], 99]


fake_ps(30, "Thu Oct 26 10:00:00 2026")   # ps treo: mỗi lần quá giờ
res, took = probe(6)
check("ps treo, 6 lần gọi: tổng < 5.5 s (bản cũ 1 + 3 + 4 x 1 = 8 s)", took < 5.5, True)
check("  … và vẫn coi là còn sống (không biết: fail closed)", res, [True] * 6)
fake_ps(1.5, "Thu Oct 26 10:00:00 2026")
check("  đối chứng: ps 1.5 s, start khác: lần thử lại còn trong hạn - pid đã tái dùng", probe(1)[0], [False])

shutil.rmtree(tmp, ignore_errors=True)
print(f"session_lock.py backlog #427: {'all checks passed' if not bad else str(bad) + ' FAILED'}")
sys.exit(1 if bad else 0)
PY
