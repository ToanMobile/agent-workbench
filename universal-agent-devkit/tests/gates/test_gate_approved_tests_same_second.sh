#!/usr/bin/env bash
# #485: approved_tests.json đóng dấu duyệt bằng int(time.time()) -> test sửa trong cùng giây bị coi là chưa duyệt,
# và test sửa SAU khi duyệt vẫn được duyệt mãi (S01-P2-02). Gọi thẳng split_user_approved, mtime đặt bằng os.utime
# nên kết quả không phụ thuộc thời điểm chạy.
# #605: chỉ dạng duyệt chéo {"approvals": [{path, sha256, reviewer, author, task_id, reason}]} còn duyệt; dạng cũ list và
# {path: sha256} (không nguồn duyệt) luôn chặn.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR
export HOME="$TMP/home"   # HOME riêng: không quét transcript / log Antigravity thật
mkdir -p "$HOME/.claude/projects"

python3 - "$GATE" "$TMP" <<'PY'
import hashlib, importlib.util, json, os, sys, time
gate, tmp = sys.argv[1], sys.argv[2]
fails = 0

def case(name, test_dt, appr_dt, edit_after, want_ok, fmt="approvals"):
    """test_dt / appr_dt: mtime của file test / approved_tests.json so với lúc này (giây, có phần lẻ).
    fmt: "approvals" (duyệt chéo, sha256 nội dung lúc duyệt), "dict" ({path: sha256}, dạng cũ) hoặc "list" (dạng cũ)."""
    global fails
    root = os.path.join(tmp, name)
    os.makedirs(os.path.join(root, "tests"))
    os.makedirs(os.path.join(root, ".claude", "audit-gate"))
    test_f = os.path.join(root, "tests", "test_old.sh")
    appr_f = os.path.join(root, ".claude", "audit-gate", "approved_tests.json")
    with open(test_f, "w") as fh:
        fh.write("#!/bin/sh\ntrue\n")
    with open(appr_f, "w") as fh:
        with open(test_f, "rb") as tfh:
            sha = hashlib.sha256(tfh.read()).hexdigest()
        if fmt == "approvals":
            fh.write(json.dumps({"approvals": [{"path": "tests/test_old.sh", "sha256": sha, "reviewer": "antigravity",
                                                "author": "claude", "task_id": "T605", "reason": "không nới assertion"}]}))
        elif fmt == "dict":
            fh.write('{"tests/test_old.sh": "%s"}\n' % sha)
        else:
            fh.write('["tests/test_old.sh"]\n')
    if edit_after:   # nội dung đổi sau khi duyệt
        with open(test_f, "w") as fh:
            fh.write("#!/bin/sh\nexit 0\n")
    now = time.time()
    os.utime(test_f, (now + test_dt, now + test_dt))
    os.utime(appr_f, (now + appr_dt, now + appr_dt))
    os.environ["CLAUDE_PROJECT_DIR"] = root
    spec = importlib.util.spec_from_file_location("pfg_" + name, gate)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)   # nạp lại mỗi ca: get_project_dir() nhớ thư mục theo tiến trình
    blocking, ok = m.split_user_approved(["tests/test_old.sh"], None)
    got = ok == ["tests/test_old.sh"]
    if got == want_ok:
        print("✔ %s: %s" % (name, "duyệt" if got else "chặn"))
    else:
        print("✖ %s: muốn %s, được %s (blocking=%s ok=%s)" % (name, "duyệt" if want_ok else "chặn",
              "duyệt" if got else "chặn", blocking, ok))
        fails += 1

# A: sửa test rồi duyệt chéo trong CÙNG giây (mtime test có phần lẻ, duyệt sau 0,1 s) -> phải duyệt
case("same_second", 3.5, 3.6, False, True)
# B (đối chứng): duyệt lúc -10 s, nội dung test đổi lúc -5 s -> phải chặn
case("edit_after_approval", -5, -10, True, False)
# C: duyệt lúc -5 s, test sửa lúc -20 s, không đổi gì sau đó -> phải duyệt
case("unchanged_since_approval", -20, -5, False, True)
# D: nội dung khớp sha256 -> duyệt dù test có mtime mới hơn file duyệt (mtime không quyết định)
case("hash_match", -5, -10, False, True)
# E (đối chứng): nội dung đổi sau khi duyệt, file duyệt ghi lại SAU đó (mtime mới hơn) -> vẫn chặn
case("hash_content_changed_rewritten", -10, -1, True, False)
# F, G (#605): dạng cũ không nguồn duyệt, nội dung khớp, file duyệt mới hơn test -> vẫn chặn
case("legacy_list", -20, -5, False, False, fmt="list")
case("legacy_dict", -5, -10, False, False, fmt="dict")
print("PASS" if fails == 0 else "FAIL: %d" % fails)
sys.exit(1 if fails else 0)
PY
