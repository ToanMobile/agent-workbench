#!/usr/bin/env bash
# bin/session_lock.py - lỗ dư sau audit DevKit 25-26/10 (issue #427). Mỗi ca phải-chặn có một ca đối chứng vô hại phải-qua:
#   1. _expand_static_vars đọc cả thân heredoc DỮ LIỆU: commit message có dòng `M=/tmp/x` lái đích ghi `$M` ra khỏi main (trunk mode).
#   2. S2: heredoc vào ống nhiều chặng (`cat <<EOF | tee /dev/null | bash`, dòng mở kết thúc `|`, `|&`): thân bị coi là dữ liệu.
#   3. S3: nhiều heredoc trên một dòng (`a <<A; b <<B`, `a <<A <<B`): chỉ cái đầu được xét, thân thứ hai thành dòng của shell cha.
#   4. Từ repo không liên quan, đích ghi không xác định (`git -C "$(cat /tmp/p)" commit`) lọt vào checkout bị giữ của project của phiên.
#   5. B5: `_ps` quá 1 s dưới tải trả None, is_pid_alive coi pid đã tái dùng (holder đã chết) là còn sống.
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
tmp = os.path.realpath(tempfile.mkdtemp(prefix="sl427_"))
os.makedirs(os.path.join(tmp, "scratch"))
bad = 0


def sh(*a, cwd=None):
    r = subprocess.run(list(a), cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"setup failed: {a}: {r.stderr[:200]}")
    return r.stdout


def repo(name):
    d = os.path.join(tmp, name)
    os.makedirs(d)
    sh("git", "init", "-q", d)
    sh("git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
    return d


def hold(gdir, sid, cwd, **extra):   # khoá của một phiên khác còn sống (pid của chính tiến trình test)
    with open(os.path.join(gdir, "devkit-session.lock"), "w", encoding="utf-8") as f:
        json.dump(dict({"session_id": sid, "started": time.time(), "heartbeat": time.time(), "cwd": cwd, "pid": os.getpid()}, **extra), f)


def hook(cmd, cwd, sid="me", env_extra=None):
    env = {k: v for k, v in os.environ.items() if k not in ("DEVKIT_ALLOW_SHARED_CHECKOUT", "CLAUDE_PROJECT_DIR")}
    env["WORKTREE_TRUNK_MODE"] = "0"   # các ca 2-4 xét luật một-checkout-một-phiên (trunk mode xét ở unit bên dưới)
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


A = repo("locked")   # checkout phiên khác đang giữ
B = repo("other")    # repo rảnh, phiên được thử chạy ở đây
hold(os.path.join(A, ".git"), "holder", A)
S = os.path.join(tmp, "scratch")

print("2. S2: heredoc vào ống nhiều chặng (từ B, A bị giữ)")
fromB = lambda c: hook(c, B)
check("cat <<EOF | tee /dev/null | bash  git -C A commit", fromB(f"cat <<'EOF' | tee /dev/null | bash\ngit -C {A} commit -m x\nEOF"), 2)
check("  đối chứng: cat <<EOF | tee <scratch> | wc -l  (thân là dữ liệu)", fromB(f"cat <<'EOF' | tee {S}/n.txt | wc -l\ngit -C {A} commit -m x\nEOF"), 0)
check("cat <<EOF | grep -v x | timeout 60 bash  git -C A commit", fromB(f"cat <<'EOF' | grep -v '^#' | timeout 60 bash\ngit -C {A} commit -m x\nEOF"), 2)
check("  đối chứng: cat <<EOF | tee /dev/null | bash <script>  (bash đọc script, thân là stdin)", fromB(f"cat <<'EOF' | tee /dev/null | bash {S}/s.sh\ngit -C {A} commit -m x\nEOF"), 0)
check("dòng mở kết thúc '|': cat <<EOF | <nl> git -C A commit <nl> EOF <nl> bash", fromB(f"cat <<'EOF' |\ngit -C {A} commit -m x\nEOF\nbash"), 2)
check("  đối chứng: cat <<EOF | <nl> … <nl> EOF <nl> wc -l", fromB(f"cat <<'EOF' |\ngit -C {A} commit -m x\nEOF\nwc -l"), 0)
check("dòng mở kết thúc '|', ống tiếp hai dòng: EOF <nl> tee /dev/null | <nl> bash", fromB(f"cat <<'EOF' |\ngit -C {A} commit -m x\nEOF\ntee /dev/null |\nbash"), 2)
check("cat <<EOF |& bash  git -C A commit", fromB(f"cat <<'EOF' |& bash\ngit -C {A} commit -m x\nEOF"), 2)
check("  đối chứng: cat <<EOF | tee /dev/null | bash  git -C B commit (repo rảnh của chính nó)", fromB(f"cat <<'EOF' | tee /dev/null | bash\ngit -C {B} commit -m x\nEOF"), 0)
# đơn điệu: thân mới thành code không được che phần lệnh sau nó (bản giữ thân nguyên văn để nháy lẻ `it's` nuốt redirect sau EOF: bản cũ chặn, bản đó cho qua)
fromA = lambda c: hook(c, A)
check("đơn điệu: từ A bị giữ, thân có nháy lẻ, sau EOF redirect tương đối vào A", fromA(f"cat <<'EOF' | tee /dev/null | bash\necho it's\nEOF\necho x > notes.txt"), 2)
check("  đối chứng: cùng thân, sau EOF redirect ra scratch", fromA(f"cat <<'EOF' | tee /dev/null | bash\necho it's\nEOF\necho x > {S}/notes.txt"), 0)
# thân chạy ở tiến trình con: `cd B` trong thân không dời shell cha - commit sau EOF vẫn ở A (đích đã biết, không thành "không biết")
check("cd <A> <nl> cat <<EOF | tee /dev/null | bash <nl> cd <B> <nl> EOF <nl> git commit (từ B)",
      fromB(f"cd {A}\ncat <<'EOF' | tee /dev/null | bash\ncd {B}\nEOF\ngit commit -m x"), 2)
check("cd <A> <nl> true <<X; bash <<Y <nl> X <nl> cd <B> <nl> Y <nl> git commit (S3, từ B)", fromB(f"cd {A}\ntrue <<X; bash <<Y\nX\ncd {B}\nY\ngit commit -m x"), 2)
check("  đối chứng: cd <B> <nl> true <<X; cat <<Y <nl> X <nl> hello <nl> Y <nl> git commit (S3, từ B)",
      fromB(f"cd {B}\ntrue <<X; cat <<Y\nX\nhello\nY\ngit commit -m x"), 0)
# đơn điệu (S3): bản cũ đọc dòng `cd A` của thân dữ liệu thứ hai như lệnh của shell này và chặn; vẫn chặn (phán thêm một lần như cũ)
check("đơn điệu: cd <B> <nl> true <<X; cat <<Y <nl> X <nl> cd <A> <nl> Y <nl> git commit (từ B)", fromB(f"cd {B}\ntrue <<X; cat <<Y\nX\ncd {A}\nY\ngit commit -m x"), 2)

print("3. S3: nhiều heredoc trên một dòng (từ worktree FW rảnh; worktree anh em FW2 bị giữ)")
FM = repo("family")
FW, FW2 = os.path.join(tmp, "family-wt"), os.path.join(tmp, "family-wt2")
sh("git", "-C", FM, "worktree", "add", "-q", "--detach", FW)
sh("git", "-C", FM, "worktree", "add", "-q", "--detach", FW2)
FW2GD = sh("git", "-C", FW2, "rev-parse", "--absolute-git-dir").strip()
hold(FW2GD, "holder5", FW2, gitdir=FW2GD)
fam = lambda c: hook(c, FW)
check("W=<FW2> <nl> true <<A; bash <<B <nl> A <nl> W=<FW> <nl> B <nl> git -C $W commit (thân B chạy ở tiến trình con)",
      fam(f"W={FW2}\ntrue <<A; bash <<B\nA\nW={FW}\nB\ngit -C $W commit -m x"), 2)
check("W=<FW2> <nl> true <<A; cat <<B <nl> A <nl> W=<FW> <nl> B <nl> git -C $W commit (thân B là dữ liệu)",
      fam(f"W={FW2}\ntrue <<A; cat <<B\nA\nW={FW}\nB\ngit -C $W commit -m x"), 2)
check("W=<FW2> <nl> bash <<A <<B <nl> A <nl> W=<FW> <nl> B <nl> git -C $W commit", fam(f"W={FW2}\nbash <<A <<B\nA\nW={FW}\nB\ngit -C $W commit -m x"), 2)
check("cd <FW2> <nl> true <<A; bash <<B <nl> A <nl> cd <FW> <nl> B <nl> git commit (cd ở tiến trình con)",
      fam(f"cd {FW2}\ntrue <<A; bash <<B\nA\ncd {FW}\nB\ngit commit -m x"), 2)
check("  đối chứng: W=<FW> <nl> true <<A; cat <<B … hello … B <nl> git -C $W commit", fam(f"W={FW}\ntrue <<A; cat <<B\nA\nhello\nB\ngit -C $W commit -m x"), 0)
check("  đối chứng: W=<FW> <nl> true <<A; bash <<B … echo hi … B <nl> git -C $W commit", fam(f"W={FW}\ntrue <<A; bash <<B\nA\necho hi\nB\ngit -C $W commit -m x"), 0)
check("  đối chứng: git -C <FW> commit (worktree rảnh của chính nó)", fam(f"git -C {FW} commit -m x"), 0)
# đơn điệu (S2): `)` trong thân không được đóng sớm `$(` của dòng mở - cd FW sau EOF vẫn ở trong subshell, commit chạy ở FW2
check("đơn điệu: cd <FW2> <nl> x=$(cat <<EOF | tee /dev/null | bash <nl> ) <nl> EOF <nl> cd <FW> <nl> ) <nl> git commit",
      fam(f"cd {FW2}\nx=$(cat <<'EOF' | tee /dev/null | bash\n)\nEOF\ncd {FW}\n)\ngit commit -m x"), 2)

print("4. đích không xác định từ repo không liên quan C; project P của phiên có checkout bị giữ")
PM = repo("project")
PW = os.path.join(tmp, "project-wt")
sh("git", "-C", PM, "worktree", "add", "-q", "--detach", PW)
C = repo("unrelated")
os.makedirs(os.path.join(PM, ".git", "devkit-sessions"))
with open(os.path.join(PM, ".git", "devkit-sessions", "me.json"), "w", encoding="utf-8") as f:   # SessionStart đăng ký phiên ở project của nó
    json.dump({"session_id": "me", "pid": os.getpid(), "heartbeat": time.time(), "cwd": PW, "status": "working"}, f)
hold(os.path.join(PM, ".git"), "holder6", PM)
with open(os.path.join(tmp, "p"), "w", encoding="utf-8") as f:
    f.write(PM)
C2 = repo("unrelated2")   # cho phiên "stranger": các ca của "me" đã nhận khoá của C
fromC = lambda c, proj=PW, sid="me": hook(c, C2 if sid == "stranger" else C, sid=sid, env_extra={"CLAUDE_PROJECT_DIR": proj})
check("from C: git -C \"$(cat /tmp/p)\" commit (project PW, main PM bị giữ)", fromC(f'git -C "$(cat {tmp}/p)" commit -m x'), 2)
check("from C: cd $X && git commit", fromC("cd $X && git commit -m x"), 2)
check("from C: project là chính checkout bị giữ (PM)", fromC(f'git -C "$(cat {tmp}/p)" commit -m x', proj=PM), 2)
check("  đối chứng: from C: git -C <C> commit (đích rõ, repo rảnh)", fromC(f"git -C {C} commit -m x"), 0)
check("  đối chứng: from C: git commit (cwd C rảnh)", fromC("git commit -m x"), 0)
check("  đối chứng: phiên không đăng ký ở project (biến thừa hưởng từ nơi khác)", fromC("cd $X && git commit -m x", sid="stranger"), 0)
check("  đối chứng: project chính là C (repo của cwd)", fromC("cd $X && git commit -m x", proj=C), 0)
hold(os.path.join(PM, ".git"), "holder6", PM, idle_since=time.time())
check("  đối chứng: holder của project đang rảnh (idle)", fromC("cd $X && git commit -m x"), 0)
hold(os.path.join(PM, ".git"), "holder6", PM)

print("1 + S2/S3 trunk mode: trunk_write (main TM chỉ để gộp, phiên ở worktree TW)")
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
    (True, "M=<TM> <nl> git commit -F - <<'EOF' … M=/tmp/x … EOF <nl> echo > $M/README.md",
     f"M={TM}\ngit commit -F - <<'EOF'\nfix: x\n\nM=/tmp/x\nEOF\necho evil > $M/README.md"),
    (False, "  đối chứng: M=<scratch> <nl> git commit -F - <<'EOF' msg EOF <nl> echo > $M/f", f"M={S}\ngit commit -F - <<'EOF'\nmsg\nEOF\necho ok > $M/f.txt"),
    (True, "export M=<TM>; git commit -qF - <<'EOF' M=/tmp/x EOF <nl> cd \"$M\" && echo > README.md",
     f"export M={TM}; git commit -qF - <<'EOF'\nM=/tmp/x\nEOF\ncd \"$M\" && echo evil > README.md"),
    (True, "M=<TM>/README.md <nl> cat <<'EOF' > <scratch> M=/tmp/x EOF <nl> echo > \"$M\"",
     f"M={TM}/README.md\ncat <<'EOF' > {S}/n.txt\nM=/tmp/x\nEOF\necho evil > \"$M\""),
    (False, "  đối chứng: D=<scratch> <nl> git commit -F - <<'EOF' M=/tmp/x EOF <nl> echo > $D/f (biến khác)",
     f"D={S}\ngit commit -F - <<'EOF'\nM=/tmp/x\nEOF\necho ok > $D/f.txt"),
    (False, "  đối chứng: bash <<'EOF' O=<scratch>; echo > $O/f EOF (thân code: như trước)", f"bash <<'EOF'\nO={S}\necho ok > $O/f.txt\nEOF"),
    (True, "M=<TM> <nl> true <<A; cat <<B <nl> A <nl> M=/tmp/x <nl> B <nl> echo > $M/README.md (S3: thân dữ liệu thứ hai)",
     f"M={TM}\ntrue <<A; cat <<B\nA\nM=/tmp/x\nB\necho evil > $M/README.md"),
    (True, "cat <<'EOF' | tee /dev/null | bash  echo > <TM>/README.md  EOF (S2)", f"cat <<'EOF' | tee /dev/null | bash\necho evil > {TM}/README.md\nEOF"),
    (False, "  đối chứng: cat <<'EOF' | tee /dev/null | bash  echo > <scratch>/o.txt  EOF", f"cat <<'EOF' | tee /dev/null | bash\necho ok > {S}/o.txt\nEOF"),
    (True, "true <<A; cat <<B | bash <nl> A <nl> echo > <TM>/README.md <nl> B (S3: heredoc thứ hai vào bash)",
     f"true <<A; cat <<B | bash\nA\necho evil > {TM}/README.md\nB"),
]
env = {k: v for k, v in os.environ.items() if k not in ("WORKTREE_TRUNK_MODE", "CLAUDE_PROJECT_DIR")}
r = subprocess.run([sys.executable, "-I", "-c", UNIT, KIT, TM, TW, json.dumps([c for _w, _l, c in rows])], capture_output=True, text=True, env=env, timeout=120)
got = json.loads(r.stdout) if r.returncode == 0 else [None] * len(rows)
if r.returncode != 0:
    print(r.stderr[-800:])
for (want, label, _c), g in zip(rows, got):
    check(label, g, want)

print("5. B5: ps chậm dưới tải (ps giả trên PATH)")
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


def probe(calls=1):
    env = dict(os.environ, PATH=FAKE + os.pathsep + os.environ.get("PATH", ""))
    r = subprocess.run([sys.executable, "-I", "-c", PROBE, KIT, str(calls)], capture_output=True, text=True, env=env, timeout=60)
    return json.loads(r.stdout) if r.returncode == 0 else [[r.stderr[-300:]], 0]


fake_ps(1.5, "Thu Oct 26 10:00:00 2026")   # 1.5 s: quá timeout 1 s cũ; khác thời điểm khởi động đã ghi -> pid đã bị tái dùng
check("ps 1.5 s, start khác: is_pid_alive = False (holder đã chết)", probe()[0], [False])
fake_ps(1.5, "Mon Jan  1 00:00:00 2001")
check("  đối chứng: ps 1.5 s, start trùng: is_pid_alive = True", probe()[0], [True])
fake_ps(30, "Thu Oct 26 10:00:00 2026")    # ps treo: không biết -> còn sống (như trước), và có giới hạn thời gian
res, took = probe(calls=2)
check("  đối chứng: ps treo, 2 lần gọi: vẫn coi là còn sống (fail closed)", res, [True, True])
check("  … và chỉ thử lại một lần cho cả tiến trình (< 7 s)", took < 7, True)

shutil.rmtree(tmp, ignore_errors=True)
print(f"session_lock.py issue #427: {'all checks passed' if not bad else str(bad) + ' FAILED'}")
sys.exit(1 if bad else 0)
PY
