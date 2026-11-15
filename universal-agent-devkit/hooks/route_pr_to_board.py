#!/usr/bin/env python3
"""Hook Bash (#1192): mọi PR của repo có super-board phải mở từ nhánh `issue-<N>-<slug>` và có thẻ ở board ngay khi mở.

PR mở bằng `gh pr create` ngoài board không vào lane nào, mà phiên tác giả bị cấm tự duyệt (#605), nên agent đẩy việc duyệt cho chủ
repo; PR trên nhánh không `issue-<N>-` thì lane builder không nhận ra là PR của thẻ (preflight giữ thẻ "already being built elsewhere").

- PreToolUse: `gh pr create|new` thật (theo segment/token, như guard-protected-push.py), không `-d/--draft`, nhánh (`--head`/`-H`,
  không thì nhánh đang checkout) không khớp `^issue-\\d+-` → exit 2 kèm cách sửa.
- PostToolUse: `gh pr create|new` in ra URL `…/pull/<n>` → chạy .claude/bin/super-board-route-pr.sh <n> (thẻ vào QA) và báo qua
  additionalContext. Luôn exit 0.
Hai sự kiện phân biệt bằng `hook_event_name` trong JSON stdin. Repo không có .claude/super-board/configs/*.json → không làm gì.
Lỗi của chính hook không bao giờ chặn lệnh (in stderr rồi cho qua).
"""
import glob
import importlib.util
import json
import os
import re
import subprocess
import sys

ISSUE_BRANCH = re.compile(r"^issue-\d+-")
PR_URL = re.compile(r"https://github\.com/[^/\s]+/[^/\s]+/pull/(\d+)")
# cờ của `gh pr create` nhận giá trị ở từ kế tiếp (pflag): đọc bỏ qua để giá trị như `--title -d` không thành cờ
VALUE_LONG = {"--assignee", "--base", "--body", "--body-file", "--head", "--label", "--milestone", "--project", "--reviewer",
              "--title", "--template", "--repo", "--recover"}
VALUE_SHORT = set("aBbFHlmprtTR")
GH_GLOBAL_VALUE = {"-R", "--repo", "--hostname"}


def _load_parser():
    """segments()/program() của guard-protected-push.py: một cách đọc dòng lệnh chung cho các guard."""
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "guard-protected-push.py")
    spec = importlib.util.spec_from_file_location("_gpp_for_route_pr", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def pr_creates(command, parser):
    """[(draft, head|None)] cho mỗi `gh pr create|new` thật trong lệnh."""
    found = []
    for raw in parser.segments(command):
        tokens = parser.program(raw)
        if not tokens or os.path.basename(tokens[0]) != "gh":
            continue
        args, i = tokens[1:], 0
        while i < len(args) and args[i].startswith("-"):   # cờ chung của gh trước lệnh con
            i += 2 if args[i] in GH_GLOBAL_VALUE else 1
        if args[i:i + 1] != ["pr"]:
            continue
        i += 1
        while i < len(args) and args[i].startswith("-"):
            i += 2 if args[i] in GH_GLOBAL_VALUE else 1
        if i >= len(args) or args[i] not in ("create", "new"):
            continue
        draft, head, j, rest = False, None, 0, args[i + 1:]
        while j < len(rest):
            a = rest[j]
            if a == "--":
                break
            name, eq, val = a.partition("=")
            if a.startswith("--"):
                if name == "--draft":
                    draft = (val.lower() not in ("false", "0")) if eq else True
                elif name == "--head":
                    head = val if eq else (rest[j + 1] if j + 1 < len(rest) else None)
                if name in VALUE_LONG and not eq:
                    j += 1
            elif a.startswith("-") and len(a) > 1:   # cụm cờ ngắn: chữ boolean đi tiếp, chữ nhận giá trị lấy phần còn lại hoặc từ kế
                for k, ch in enumerate(a[1:], start=1):
                    if ch == "d":
                        draft = True
                    elif ch in VALUE_SHORT:
                        v = a[k + 1:]
                        if not v:
                            j += 1
                            v = rest[j] if j < len(rest) else ""
                        if ch == "H":
                            head = v
                        break
            j += 1
        found.append((draft, head))
    return found


def git_top(cwd):
    try:
        r = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=10)
        return r.stdout.strip() or None
    except (OSError, subprocess.TimeoutExpired):
        return None


def current_branch(cwd):
    try:
        r = subprocess.run(["git", "-C", cwd, "symbolic-ref", "--short", "-q", "HEAD"], capture_output=True, text=True, timeout=10)
        return r.stdout.strip() or None
    except (OSError, subprocess.TimeoutExpired):
        return None


def board_root(cwd):
    """Gốc repo có .claude/super-board/configs/*.json, hoặc None."""
    for d in (git_top(cwd), os.environ.get("CLAUDE_PROJECT_DIR")):
        if d and glob.glob(os.path.join(d, ".claude", "super-board", "configs", "*.json")):
            return d
    return None


FIX_STEPS = (
    "BLOCKED (#1192): repo này có super-board — PR phải mở từ nhánh `issue-<N>-<slug>` để có thẻ ở board ngay khi mở "
    "(lane QA/Review duyệt và merge gate merge; không hỏi chủ repo duyệt). Nhánh hiện tại: {branch}. Cách sửa:\n"
    "  1. Tạo hoặc chọn issue N: `gh issue create --title … --label bug|feature --body-file …` (KHÔNG nhãn `qa`; thiếu nhãn thì "
    "`gh label create <tên> --force` trước).\n"
    "  2. Đổi tên nhánh: `DEVKIT_ALLOW_BRANCH=1 git branch -m issue-<N>-<slug>`.\n"
    "  3. Đẩy nhánh đó: `git push origin issue-<N>-<slug>`.\n"
    "  4. Chạy lại `gh pr create` với `Closes #<N>` trong body (thẻ tự vào lane QA).\n"
    "PR nháp (`--draft`) của lane builder không bị chặn."
)


def pre(command, cwd, parser):
    creates = pr_creates(command, parser)
    if not creates or not board_root(cwd):
        return 0
    for draft, head in creates:
        if draft:
            continue
        branch = head.split(":", 1)[-1] if head else current_branch(cwd)
        if branch and not ISSUE_BRANCH.match(branch):
            sys.stderr.write(FIX_STEPS.format(branch=branch) + "\n")
            return 2
    return 0


def response_text(resp):
    if isinstance(resp, str):
        return resp
    if isinstance(resp, dict):
        return "\n".join(str(resp.get(k) or "") for k in ("stdout", "output", "stderr"))
    return ""


def post(command, cwd, resp, parser):
    if not pr_creates(command, parser):
        return
    nums = PR_URL.findall(response_text(resp))
    root = board_root(cwd) if nums else None
    if not root:
        return
    script = os.path.join(root, ".claude", "bin", "super-board-route-pr.sh")
    if not os.path.isfile(script):
        msg = f"PR #{nums[-1]} chưa vào board: thiếu {script} (cài lại pack super-board)."
    else:
        try:
            r = subprocess.run(["bash", script, nums[-1]], cwd=cwd, capture_output=True, text=True, timeout=90)
            out = (r.stdout + r.stderr).strip()[-600:]
            if r.returncode == 0:
                msg = (f"PR #{nums[-1]} đã vào luồng board: {out}. Lane QA/Review duyệt và merge gate merge — KHÔNG hỏi chủ repo "
                       "duyệt hay merge.")
            else:
                msg = (f"PR #{nums[-1]} CHƯA vào board: super-board-route-pr.sh exit {r.returncode}: {out}. "
                       f"Sửa theo thông báo rồi chạy `bash .claude/bin/super-board-route-pr.sh {nums[-1]}`.")
        except (OSError, subprocess.TimeoutExpired) as e:
            msg = f"PR #{nums[-1]} CHƯA vào board: không chạy được super-board-route-pr.sh ({type(e).__name__}: {e})."
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg}}, ensure_ascii=False))


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        if not isinstance(payload, dict):
            return 0
        ti = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
        command = ti.get("command")
        if not isinstance(command, str) or not re.search(r"\bgh\b", command) or not re.search(r"\b(create|new)\b", command):
            return 0
        cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) and payload.get("cwd") else os.getcwd()
        parser = _load_parser()
        if payload.get("hook_event_name") == "PostToolUse":
            post(command, cwd, payload.get("tool_response"), parser)
            return 0
        return pre(command, cwd, parser)
    except Exception as e:   # noqa: BLE001 — hook hỏng không được chặn việc khác, nhưng phải nói ra
        sys.stderr.write("route_pr_to_board: skipped (%s: %s)\n" % (type(e).__name__, str(e)[:160]))
        return 0


if __name__ == "__main__":
    sys.exit(main())
