#!/usr/bin/env python3
"""super-review-removed-names.py — tên bị xoá/đổi trong diff mà head vẫn còn dùng (#980).

Dùng:  super-review-removed-names.py [--base REF] [--head REF] [--max-files N]
Chạy ở gốc repo. Với diff `merge-base(base, head)..head`:
  1. lấy các định danh (tên hàm, id rule, hằng, tên file bị xoá/đổi) có ở dòng '-' nhiều hơn ở dòng '+' (xoá thật, không phải
     chỉ di chuyển);
  2. `git grep` từng tên trên head; mỗi tên còn chỗ dùng in MỘT dòng: `<tên> (-a/+b): file:dòng, …`.
Chỉ tính file diff KHÔNG chạm. Reviewer đọc danh sách: chỗ dùng mà không còn đúng ý là finding Gap (review-flow.md bước 2). Chỉ in, không sửa gì;
exit 0 kể cả khi có dòng (không có gì để in = không có tên nào bị bỏ rơi). Lỗi git ⇒ exit 64.
Chỉ lấy định danh "dạng id" (có `_`, `-`, `.`+đuôi, chữ số hoặc camelCase, dài ≥ 6): từ tiếng thường như `function` bị bỏ để không nhiễu.
Không quét CHANGELOG, nhật ký chạy của board và kho trí nhớ: nhắc tên cũ ở đó là lịch sử, không phải chỗ dùng.
"""
import argparse
import collections
import re
import subprocess
import sys

TOKEN = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]*[A-Za-z0-9_]")
SKIP_PATHS = (
    ":(exclude)**/CHANGELOG*.md",
    ":(exclude)docs/super-board/runs/**",
    ":(exclude).agents/local/**",
    ":(exclude).agents/CHECKLIST.md",
    ":(exclude).agents/instincts*.md",
    ":(exclude).agents/regression_status.json",
    ":(exclude).agents/regression_journal/**",
    ":(exclude).claude/agent-memory/**",
)


def git(*args):
    p = subprocess.run(("git",) + args, capture_output=True, text=True, errors="replace", timeout=120)
    if p.returncode != 0:
        print("removed-names: git %s: %s" % (" ".join(args[:2]), p.stderr.strip()), file=sys.stderr)
        sys.exit(64)
    return p.stdout


def idlike(tok):
    """Định danh dạng id: bỏ chữ thường thuần, số thuần, sha."""
    if len(tok) < 6 or tok[0].isdigit() or re.fullmatch(r"[0-9a-f]{7,40}", tok):
        return False
    if re.search(r"[0-9_]", tok) or re.match(r"[a-z]+[A-Z]", tok) or re.search(r"[a-z][A-Z].*[a-z][A-Z]", tok) or re.search(r"[A-Z]-[A-Z]", tok):
        return True
    # `a-b-c` toàn chữ thường là từ ghép tiếng thường; tên file (`x.sh`, `x-y.py`) mới là định danh.
    return bool(re.search(r"\.[A-Za-z0-9]{1,5}$", tok)) and "-" in tok


def tokens(line):
    return [t.rstrip(".-") for t in TOKEN.findall(line)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--max-files", type=int, default=12)
    ap.add_argument("--max-names", type=int, default=2, help="số dòng tối đa (PR gỡ hàng loạt không làm ngập reviewer)")
    a = ap.parse_args()

    mb = git("merge-base", a.base, a.head).strip()
    diff = git("diff", "-U0", "--no-color", "-M", mb, a.head, "--", ".", *SKIP_PATHS)
    minus, plus = collections.Counter(), collections.Counter()
    for ln in diff.splitlines():
        if ln.startswith("---") or ln.startswith("+++"):
            continue
        if ln[:1] in "-+":
            c = minus if ln[0] == "-" else plus
            for t in tokens(ln[1:]):
                if idlike(t):
                    c[t] += 1
    # file bị xoá hoặc đổi tên: tên cũ (basename) cũng là một định danh.
    for ln in git("diff", "--name-status", "-M", mb, a.head).splitlines():
        f = ln.split("\t")
        if f[0][:1] in "DR":
            base = f[1].rsplit("/", 1)[-1]
            if len(base) >= 6:
                minus[base] += 1

    # chỗ dùng TRONG file diff đã chạm thì reviewer đọc ngay trong diff; chỉ chỗ dùng ngoài diff mới là thứ dễ sót.
    out = []
    touched = set(git("diff", "--name-only", mb, a.head).splitlines())
    for tok in sorted(minus):
        if minus[tok] <= plus.get(tok, 0):
            continue
        p = subprocess.run(("git", "grep", "-n", "-F", "-w", "-I", "-e", tok, a.head, "--", ".", *SKIP_PATHS),
                           capture_output=True, text=True, errors="replace", timeout=120)
        hits = collections.OrderedDict()
        for ln in p.stdout.splitlines():
            parts = ln.split(":", 3)  # <head>:<file>:<dòng>:<nội dung>
            if len(parts) >= 3 and parts[1] not in hits and parts[1] not in touched:
                hits[parts[1]] = parts[2]
        if not hits:
            continue
        # mã nguồn trước, test và tài liệu sau: reviewer cần thấy chỗ chạy thật trước khi danh sách bị cắt.
        order = sorted(hits.items(), key=lambda kv: ("test" in kv[0], kv[0].endswith(".md"), kv[0]))
        shown = ["%s:%s" % kv for kv in order[: a.max_files]]
        more = len(hits) - len(shown)
        out.append((minus[tok] - plus.get(tok, 0), len(hits), "%s (-%d/+%d): %s%s" % (
            tok, minus[tok], plus.get(tok, 0), ", ".join(shown), " (+%d file nữa)" % more if more > 0 else "")))
    out.sort(key=lambda r: (-r[0], -r[1], r[2]))
    for _, _, line in out[: a.max_names]:
        print(line)
    if len(out) > a.max_names:
        print("(+%d tên nữa, chạy lại với --max-names %d để xem hết)" % (len(out) - a.max_names, len(out)))


if __name__ == "__main__":
    main()
