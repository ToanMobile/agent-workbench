#!/usr/bin/env bash
# #582: gate chạy trong worktree (slug transcript khác) phải thấy lời duyệt AskUserQuestion nằm ở thư mục transcript
# của checkout chính (suy từ git common dir). Không nới điều kiện: test sửa sau lời duyệt, nhãn không phải duyệt,
# hoặc transcript của dự án khác vẫn bị chặn.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$TMP"' EXIT
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR
export HOME="$TMP/home"
mkdir -p "$HOME/.claude/projects"

python3 - "$GATE" "$TMP" <<'PY'
import importlib.util, json, os, re, subprocess, sys, time
gate, tmp = sys.argv[1], sys.argv[2]
fails = 0
slug = lambda p: re.sub(r"[^A-Za-z0-9]", "-", p)

def git(cwd, *a):
    subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", *a], cwd=cwd, check=True, capture_output=True)

def case(name, label, test_after_answer, where, want_ok, sid="sess-aaaa-1111", file_sid="sess-aaaa-1111", nested=False):
    """where: 'main' = transcript in the main checkout's folder, 'other' = another project's folder.
    sid: phiên đang chạy gate; file_sid: phiên viết transcript. nested: project là thư mục con thường của repo cha."""
    main = os.path.join(tmp, name, "main"); wt = os.path.join(tmp, name, "wt")
    os.makedirs(os.path.join(main, "tests"))
    git(main, "init", "-q", "-b", "main")
    open(os.path.join(main, "tests", "test_old.sh"), "w").write("true\n")
    git(main, "add", "-A"); git(main, "commit", "-qm", "init")
    if nested:
        wt = os.path.join(main, "sub"); os.makedirs(os.path.join(wt, "tests"))
        open(os.path.join(wt, "tests", "test_old.sh"), "w").write("true\n")
    else:
        git(main, "worktree", "add", "-q", "--detach", wt)
    test_f = os.path.join(wt, "tests", "test_old.sh")
    open(test_f, "w").write("exit 0\n")
    ans_t = time.time() - 20
    os.utime(test_f, (ans_t - 10, ans_t - 10) if not test_after_answer else (ans_t + 10, ans_t + 10))
    folder = os.path.join(os.environ["HOME"], ".claude", "projects", slug(main) if where == "main" else slug(main + "-other"))
    os.makedirs(folder)
    q = "Duyệt sửa tests/test_old.sh?"
    rec = {"type": "user", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(ans_t)) + ".000Z",
           "toolUseResult": {"questions": [{"question": q, "header": "tests/test_old.sh"}], "answers": {q: label}}}
    open(os.path.join(folder, file_sid + ".jsonl"), "w").write(json.dumps(rec, ensure_ascii=False) + "\n")
    os.environ["CLAUDE_PROJECT_DIR"] = wt
    os.environ["CLAUDE_CODE_SESSION_ID"] = sid
    spec = importlib.util.spec_from_file_location("pfg_" + name, gate)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    _b, ok = m.split_user_approved(["tests/test_old.sh"], None)
    got = ok == ["tests/test_old.sh"]
    print(("✔ " if got == want_ok else "✖ ") + "%s: muốn %s, được %s" % (name, want_ok, got))
    global fails
    fails += got != want_ok

case("main_transcript_approves", "Duyệt", False, "main", True)
case("edit_after_answer", "Duyệt", True, "main", False)
case("not_an_approve_label", "Không duyệt", False, "main", False)
case("other_session_in_main_folder", "Duyệt", False, "main", False, file_sid="sess-bbbb-2222")
case("subdir_of_parent_repo", "Duyệt", False, "main", False, nested=True)
case("other_project_transcript", "Duyệt", False, "other", False)
print("PASS" if fails == 0 else "FAIL: %d" % fails)
sys.exit(1 if fails else 0)
PY
