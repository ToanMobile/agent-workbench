#!/usr/bin/env bash
# hooks/shell_writes.py - T4 (#844, lane r31writes): shlex không biết $'…' (ANSI-C) và $"…" (locale): `touch $'<main>/a.txt'` cho đích
# `$<main>/a.txt`, và mọi caller bỏ qua đích có `$` (coi là biến) - worktree_guard.sh, session_lock.py (_file_write_hits,
# _family_write_held, trunk_write) cho qua lệnh ghi vào checkout bị cấm. targets() nay đọc THÊM dòng đã giải mã (shell_norm.drop_comments,
# ansi_c_to_single, locale_to_double) và nối đích mới sau đích của cách đọc cũ. Mỗi ca phải-chặn có ca đối chứng phải-qua (cùng lệnh vào
# worktree của chính nó, lệnh tìm kiếm rg / grep -E / git grep / sed có đường dẫn trong $'…').
#   1. hooks/worktree_guard.sh: DEVKIT_WORKTREE = worktree GW, đích trong main checkout GM (3 dạng tái hiện có tên của thẻ ở đầu).
#   2. bin/session_lock.py qua hook PreToolUse: đích ở worktree anh em bị giữ.
#   3. bin/session_lock.py bash_collides (checkout bị giữ) và trunk_write (main của trunk mode).
#   4. targets() trực tiếp: đích của cách đọc cũ đứng trước và còn nguyên; None giữ None; $$'…', \$'…', "$'…'" không bị giải mã;
#      shell_writes.py không có shell_norm.py cạnh: chỉ cách đọc cũ, không văng.
#   SWDQ_KIT=<thư mục kit>   chạy cùng bảng trên một bản kit khác (bản chưa sửa: ĐỎ).
# bash 3.2 compatible wrapper; the checks are python3 (stdlib only). Không lệnh nào được chạy thật: test chỉ đưa payload cho hook.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_ALLOW_SHARED_CHECKOUT CLAUDE_PROJECT_DIR WORKTREE_GUARD DEVKIT_WORKTREE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${SWDQ_KIT:-$DEVKIT_DIR}"
export PYTHONDONTWRITEBYTECODE=1
python3 -I - "$KIT" <<'PY'
import json, os, shutil, subprocess, sys, tempfile, time

KIT = os.path.realpath(sys.argv[1])
SCRIPT = os.path.join(KIT, "bin", "session_lock.py")
GUARD = os.path.join(KIT, "hooks", "worktree_guard.sh")
sys.path.insert(0, os.path.join(KIT, "bin"))
import session_lock as sl   # noqa: E402 - (nó tự nạp hooks/shell_writes.py của chính KIT)
sw = sl._hook_module("shell_writes")
tmp = os.path.realpath(tempfile.mkdtemp(prefix="swdq_"))
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


def run(argv, payload, env):
    try:
        r = subprocess.run(argv, input=json.dumps(payload), capture_output=True, text=True, env=env, timeout=60)
    except subprocess.TimeoutExpired:
        return 124
    return 99 if "Traceback" in r.stderr else r.returncode   # hook văng là cho qua: không bao giờ tính là đúng


def hook(cmd, cwd, sid="me"):
    env = {k: v for k, v in os.environ.items() if k not in ("DEVKIT_ALLOW_SHARED_CHECKOUT", "CLAUDE_PROJECT_DIR")}
    env["WORKTREE_TRUNK_MODE"] = "0"
    p = {"hook_event_name": "PreToolUse", "session_id": sid, "cwd": cwd, "tool_name": "Bash", "tool_input": {"command": cmd}}
    return run([sys.executable, "-I", SCRIPT], p, env)


def check(label, got, want):
    global bad
    ok = got == want
    bad += 0 if ok else 1
    print(f"  {'ok  ' if ok else 'FAIL'} {label}: {got!r} (want {want!r})")


try:
    print("1. worktree_guard: DEVKIT_WORKTREE = GW, đích trong main checkout GM")
    GM = repo("gmain")
    GW = os.path.join(tmp, "gwt")
    os.makedirs(os.path.join(GM, "src"))
    with open(os.path.join(GM, "src", "a.kt"), "w") as f:
        f.write("x\n")
    sh("git", "-C", GM, "add", "-A")
    sh("git", "-C", GM, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "src")
    sh("git", "-C", GM, "worktree", "add", "-q", "--detach", GW)

    def guard(cmd, cwd=GW):
        env = {k: v for k, v in os.environ.items() if k != "WORKTREE_GUARD"}
        env.update(DEVKIT_WORKTREE=GW, CLAUDE_PROJECT_DIR=GM)
        p = {"session_id": "s", "cwd": cwd, "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": cmd}}
        return run(["bash", GUARD], p, env)

    for label, c in (("[thẻ] touch $'<GM>/a.txt'", f"touch $'{GM}/a.txt'"),
                     ("[thẻ] echo hi > $'<GM>/a.txt'", f"echo hi > $'{GM}/a.txt'"),
                     ("[thẻ] touch $\"<GM>/a.txt\"", f'touch $"{GM}/a.txt"'),
                     ("touch <GM>/a.txt (không nháy: main cũng chặn)", f"touch {GM}/a.txt"),
                     ("cp … $'<GM>/b.txt' (đích cuối)", f"cp /etc/hosts $'{GM}/b.txt'"),
                     ("echo hi >> $\"<GM>/a.txt\"", f'echo hi >> $"{GM}/a.txt"'),
                     ("tee $\"<GM>/a.txt\" < /dev/null", f'tee $"{GM}/a.txt" < /dev/null'),
                     ("$'touch' <GM>/a.txt (động từ trong $'…')", f"$'touch' {GM}/a.txt"),
                     ("$\"rm\" -f <GM>/src/a.kt (động từ trong $\"…\")", f'$"rm" -f {GM}/src/a.kt'),
                     ("bash -c $'touch <GM>/a.txt'", f"bash -c $'touch {GM}/a.txt'"),
                     ("cd $'<GM>' && touch a.txt", f"cd $'{GM}' && touch a.txt"),
                     ("rm -f $'<GM>/src/a\\x2ekt' (\\xHH giải mã)", f"rm -f $'{GM}/src/a\\x2ekt'"),
                     ("comment có nháy đơn rồi touch $'<GM>/a.txt'", f"echo hi # don't\ntouch $'{GM}/a.txt'"),
                     ("touch $'a\\' #x' <GM>/a.txt (`#` trong $'…' không mở comment)", f"touch $'a\\' #x' {GM}/a.txt"),
                     ("bash <<EOF với touch $'<GM>/a.txt' trong thân", f"bash <<EOF\ntouch $'{GM}/a.txt'\nEOF")):
        check(label, guard(c), 2)
    for label, c in (("touch $'<GW>/a.txt'", f"touch $'{GW}/a.txt'"),
                     ("echo hi > $'<GW>/a.txt'", f"echo hi > $'{GW}/a.txt'"),
                     ("touch $\"<GW>/a.txt\"", f'touch $"{GW}/a.txt"'),
                     ("cd $'<GW>' && touch a.txt", f"cd $'{GW}' && touch a.txt"),
                     ("bash -c $'touch <GW>/a.txt'", f"bash -c $'touch {GW}/a.txt'"),
                     ("touch $'a\\'b' # it's (nháy thoát trong $'…', comment có nháy)", "touch $'a\\'b' # it's"),
                     ("rg $'<GM>/a.txt' . (tìm kiếm)", f"rg $'{GM}/a.txt' ."),
                     ("rg -n $'adb|git reset|rm -rf' <GM>", f"rg -n $'adb|git reset|rm -rf' {GM}"),
                     ("grep -E $'touch|rm -rf' <GM>/src/a.kt", f"grep -E $'touch|rm -rf' {GM}/src/a.kt"),
                     ("git grep $'echo hi > <GM>/x'", f"git grep $'echo hi > {GM}/x'"),
                     ("git grep -n $\"touch <GM>\"", f'git grep -n $"touch {GM}"'),
                     ("sed -n $'1p' <GM>/src/a.kt (sed không -i chỉ đọc)", f"sed -n $'1p' {GM}/src/a.kt"),
                     ("echo $'<GM>/a.txt'", f"echo $'{GM}/a.txt'"),
                     ("printf '%s\\n' $\"<GM>/a.txt\"", f"printf '%s\\n' $\"{GM}/a.txt\""),
                     ("cat $'<GM>/src/a.kt' > <GW>/out.txt", f"cat $'{GM}/src/a.kt' > {GW}/out.txt")):
        check("  đối chứng: " + label, guard(c), 0)

    print("2. session_lock (hook): đích ở worktree anh em bị giữ (từ FW; FW2 bị giữ, FW3 khoá đã chết)")
    FM = repo("family")
    FW, FW2, FW3 = (os.path.join(tmp, n) for n in ("family-wt", "family-wt2", "family-wt3"))
    for w in (FW, FW2, FW3):
        sh("git", "-C", FM, "worktree", "add", "-q", "--detach", w)
    hold(gitdir(FW2), "holder2", FW2)
    dead = subprocess.Popen([sys.executable, "-c", "pass"])
    dead.wait()
    hold(gitdir(FW3), "gone", FW3, pid=dead.pid)
    for label, c in (("touch $'<FW2>/f.txt'", f"touch $'{FW2}/f.txt'"),
                     ("cp … $\"<FW2>/f.txt\"", f'cp /etc/hosts $"{FW2}/f.txt"'),
                     ("echo x > $'<FW2>/f.txt'", f"echo x > $'{FW2}/f.txt'"),
                     ("bash -c $'touch <FW2>/f.txt'", f"bash -c $'touch {FW2}/f.txt'")):
        check(label, hook(c, FW), 2)
    for label, c in (("touch $'<FW>/f.txt' (chính nó)", f"touch $'{FW}/f.txt'"),
                     ("touch $'<FW3 khoá đã chết>/f.txt'", f"touch $'{FW3}/f.txt'"),
                     ("rg $'<FW2>/f.txt' . (tìm kiếm)", f"rg $'{FW2}/f.txt' ."),
                     ("cat $'<FW2>/AGENTS.md' (đọc anh em bị giữ)", f"cat $'{FW2}/AGENTS.md'")):
        check("  đối chứng: " + label, hook(c, FW), 0)

    print("3. session_lock bash_collides (checkout bị giữ TOP) và trunk_write (main của trunk mode)")
    # bash_collides: OTHER là checkout rảnh ngang hàng TOP (không lồng); chỉ dạng ghi file không có `>` tầng ngoài - luật redirect riêng của
    # bash_collides đọc `> $'<x>'` là đích không tuyệt đối và đã chặn từ trước (plan_review v1, minor)
    TOP, OTHER = repo("held"), repo("free")
    hits = lambda c, cwd: sl.bash_collides(c, TOP, cwd, "me")[0]
    for label, c in (("touch $'<TOP>/x.txt'", f"touch $'{TOP}/x.txt'"), ("cp … $\"<TOP>/x.txt\"", f'cp /tmp/a $"{TOP}/x.txt"'),
                     ("$'touch' <TOP>/x.txt", f"$'touch' {TOP}/x.txt"), ("bash -c $'touch <TOP>/x.txt'", f"bash -c $'touch {TOP}/x.txt'")):
        check("bash_collides từ OTHER: " + label, hits(c, OTHER), True)
    for label, c in (("touch $'<OTHER>/x.txt'", f"touch $'{OTHER}/x.txt'"), ("$'touch' <OTHER>/x.txt", f"$'touch' {OTHER}/x.txt"),
                     ("bash -c $'touch <OTHER>/x.txt'", f"bash -c $'touch {OTHER}/x.txt'")):
        check("  đối chứng: bash_collides từ OTHER: " + label, hits(c, OTHER), False)
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
    tw = lambda c, cwd, unknown=None: sl.trunk_write("Bash", {"command": c}, c, cwd, main, swk, "s", unknown)
    # ở W (cwd trong repo): đích còn `$` đã fail closed từ trước (_expand_static_vars không mở được) - hai ca đầu xanh cả ở main, giữ để không
    # lỏng đi; động từ / script trong $'…' thì cách đọc cũ không có đích: ĐỎ ở main
    for label, c in (("touch $'<main>/src/a.py'", f"touch $'{M}/src/a.py'"), ("cp … $\"<main>/src/b.py\"", f'cp /tmp/a $"{M}/src/b.py"'),
                     ("$'touch' <main>/src/a.py", f"$'touch' {M}/src/a.py"), ("bash -c $'touch <main>/src/a.py'", f"bash -c $'touch {M}/src/a.py'")):
        check("trunk_write từ W: " + label, tw(c, W), True)
    for label, c in (("$'touch' <W>/x.py", f"$'touch' {W}/x.py"), ("bash -c $'touch <W>/x.py'", f"bash -c $'touch {W}/x.py'"),
                     ("rg $'<main>/src/a.py' . (tìm kiếm)", f"rg $'{M}/src/a.py' ."),
                     ("cat $'<main>/src/a.py' > out.txt (đọc main, ghi ở W)", f"cat $'{M}/src/a.py' > out.txt")):
        check("  đối chứng: trunk_write từ W: " + label, tw(c, W), False)
    # cwd không phải repo (unknown={}: đích `$` không biết thì bỏ qua): đích $'…' / $"…" vào main nay thấy được
    PLAIN = os.path.join(tmp, "plain")
    os.makedirs(PLAIN)
    for label, c in (("touch $'<main>/src/a.py'", f"touch $'{M}/src/a.py'"), ("echo hi > $'<main>/src/a.py'", f"echo hi > $'{M}/src/a.py'"),
                     ("touch $\"<main>/src/a.py\"", f'touch $"{M}/src/a.py"'), ("cd $'<main>' && touch a.py", f"cd $'{M}' && touch a.py")):
        check("trunk_write từ cwd không phải repo: " + label, tw(c, PLAIN, {}), True)
    for label, c in (("touch $'<PLAIN>/a.py'", f"touch $'{PLAIN}/a.py'"), ("touch $'<W>/a.py'", f"touch $'{W}/a.py'"),
                     ("cd $'<W>' && touch a.py", f"cd $'{W}' && touch a.py")):
        check("  đối chứng: trunk_write từ cwd không phải repo: " + label, tw(c, PLAIN, {}), False)

    print("4. targets() trực tiếp")
    t = lambda c, rb=False: sw.targets(c, "/w", 0, rb)
    check("cách đọc cũ đứng trước, đích giải mã nối sau: touch $'/x/a' b.txt", t("touch $'/x/a' b.txt"),
          [("file", "$/x/a", "/w"), ("file", "b.txt", "/w"), ("file", "/x/a", "/w")])
    check("không trùng: touch $'/x/a' /x/a", t("touch $'/x/a' /x/a"), [("file", "$/x/a", "/w"), ("file", "/x/a", "/w")])
    check("$\"…\": echo x > $\"/x/a\"", t('echo x > $"/x/a"'), [("redirect", "$/x/a", "/w"), ("redirect", "/x/a", "/w")])
    check("thân heredoc cho shell (run_bodies): bash <<EOF / touch $'/x/a'", ("file", "/x/a", "/w") in (t("bash <<EOF\ntouch $'/x/a'\nEOF", True) or ()), True)
    check("None giữ None: touch \"hở nháy $'/x/a'", t("touch \"hở nháy $'/x/a'"), None)
    check("None giữ None (như main) cả khi cách đọc giải mã tách được: touch $'it\\'s'", t("touch $'it\\'s'"), None)
    for label, c in (("$$'…' (PID rồi nháy thường)", "touch $$'/x/a'"), ("\\$'…' (thoát)", "touch \\$'/x/a'"),
                     ("\"$'…'\" (trong nháy kép là chữ)", "touch \"$'/x/a'\""), ("'$\"…\"' (trong nháy đơn là chữ)", "touch '$\"/x/a\"'")):
        check("  không giải mã: " + label, ("file", "/x/a", "/w") in (t(c) or ()), False)
    solo = os.path.join(tmp, "solo")
    os.makedirs(solo)
    shutil.copy(os.path.join(KIT, "hooks", "shell_writes.py"), solo)
    r = subprocess.run([sys.executable, "-I", "-c", "import json, sys; sys.path.append(sys.argv[1]); import shell_writes as s; "
                        "print(json.dumps(s.targets(sys.argv[2], '/w', 0, True)))", solo, "touch $'/x/a'"], capture_output=True, text=True, timeout=60)
    check("không có shell_norm.py cạnh: chỉ cách đọc cũ, rc 0, không Traceback",
          (r.returncode, r.stdout.strip(), "Traceback" in r.stderr), (0, json.dumps([["file", "$/x/a", "/w"]]), False))
finally:
    shutil.rmtree(tmp, ignore_errors=True)
if bad:
    print(f"shell_writes.py $'…' / $\"…\" (T4 #844): {bad} FAILED")
    sys.exit(1)
print("shell_writes.py $'…' / $\"…\" (T4 #844): all checks passed")
PY
