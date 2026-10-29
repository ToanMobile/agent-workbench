#!/usr/bin/env python3
"""Thẻ chỉ chờ thẻ khác ở lại Ready với nhãn `waiting-on:#N`, không vào Blocked (#601).

  super-board-waiting-on.py mark    --config C --issue I --on 9,10 [--why TEXT]
  super-board-waiting-on.py sweep   --config C [--items FILE]
  super-board-waiting-on.py migrate --config C [--items FILE] [--dry-run]

mark    đọc trạng thái từng N TRƯỚC mọi lần ghi (`gh issue view N --json state,url`): CLOSED/MERGED bỏ; OPEN (issue hay PR)
        giữ; N không tồn tại → 64; đọc hỏng → 79, chưa ghi gì. Không còn N mở → không ghi gì, labels=[] (caller giao thẻ).
        Còn N mở: tạo nhãn `waiting-on:#N`, comment MỘT lần (marker `<!-- sb-waiting-on I:N1,N2 -->`), CUỐI CÙNG gắn nhãn
        — gắn nhãn hỏng thì lần sau marker chặn comment lặp, chỉ gắn nốt nhãn. Comment không có dòng nào bắt đầu bằng
        `blocked-by:` (super-board-deps.sh đọc dòng đó để quyết định thẻ cần người). In {"issue","labels","commented"}.
sweep   mỗi số N trong nhãn `waiting-on:#N` của thẻ chưa Done được đọc trạng thái ĐÚNG một lần; N đã CLOSED/MERGED thì gỡ
        nhãn trên mọi thẻ mang nó. N đọc hỏng tạm thời giữ nhãn và cho exit 79 sau khi xử lý các N khác; N không tồn tại giữ
        nhãn, ghi vào errors, không chặn N khác. In {"removed","kept","errors"}.
migrate thẻ Blocked chỉ chờ thẻ khác (`pending` của super-board-wave-plan.sh) không phải thẻ cần người, không bị cầu chì
        gộp: mark rồi chuyển về Ready, gỡ nhãn cũ `⏳ chờ thẻ khác`. Chạy lại không ghi gì (thẻ đã Ready rời `pending`).
        In {"migrated","skipped"}.
--items FILE: board đã đọc sẵn (JSON của `super-board-card.sh items`) — runner truyền cache, không tốn thêm GraphQL.

Env: SB_GH (mặc định gh), SB_CARD, SB_WAVE_PLAN (mặc định cùng thư mục), INFLIGHT_DIR (mặc định
<main checkout>/.claude/super-board/inflight; main checkout = `.repo.path` tuyệt đối của config nếu tồn tại, không thì cha
của `git rev-parse --git-common-dir`). Mọi lệnh gh có `--repo` từ `.repo.remote` của config (fallback origin).
Timeout: 30 s mỗi lệnh gh đơn, 120 s cho card.sh / wave-plan (đủ cho retry của github-read); SB_WAITING_ON_TIMEOUT (giây)
đè cả hai. Hết giờ → giết cả nhóm tiến trình. Mỗi lệnh con chạy với SB_GITHUB_HALT_FILE riêng (xoá sau đó): một lần đọc
hỏng của card.sh/deps.sh không ghi file halt dùng chung, không dừng cả board.
Exit: 0 xong · 64 tham số sai · 69 ghi hỏng · 79 đọc hỏng.
"""
import argparse
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile

OK, USAGE, WRITE_FAILED, READ_FAILED = 0, 64, 69, 79
GH_TIMEOUT = 30       # một lệnh gh đơn
PLAN_TIMEOUT = 120    # card.sh items/move, wave-plan: github-read thử lại 3 lần × 30 s + backoff
LABEL_COLOR = "FBCA04"
OLD_WAITING_LABEL = "⏳ chờ thẻ khác"
LABEL_RE = re.compile(r"^waiting-on:#([0-9]+)$", re.IGNORECASE)
HERE = os.path.dirname(os.path.abspath(__file__))


class Fail(Exception):
    """Lỗi có exit code của hợp đồng (64/69/79)."""

    def __init__(self, code, why):
        super().__init__(why)
        self.code = code


class ArgParser(argparse.ArgumentParser):
    # argparse mặc định thoát 2; hợp đồng là 64 cho tham số sai
    def error(self, message):
        self.print_usage(sys.stderr)
        print(f"{self.prog}: error: {message}", file=sys.stderr)
        sys.exit(USAGE)


def run(cmd, what, timeout=GH_TIMEOUT):
    """Chạy một lệnh. Trả CompletedProcess; timeout/không chạy được → returncode 124/127 kèm stderr.

    Lệnh con chạy trong phiên (nhóm tiến trình) riêng: hết giờ thì giết cả nhóm, con cháu không còn giữ pipe làm treo.
    SB_GITHUB_HALT_FILE trỏ vào thư mục tạm riêng (file CHƯA tồn tại: github-read coi file có sẵn là đang halt), xoá trong
    finally — lỗi đọc của lệnh con chỉ thành exit code ở đây, không dừng cả board."""
    override = os.environ.get("SB_WAITING_ON_TIMEOUT")
    if override:
        try:
            timeout = max(1, int(override))
        except ValueError:
            print(f"SB_WAITING_ON_TIMEOUT={override!r} is not a whole number; using {timeout}s", file=sys.stderr)
    halt_dir = tempfile.mkdtemp(prefix="sb-waiting-halt.")
    halt_file = os.path.join(halt_dir, "github-halt.json")
    env = dict(os.environ, SB_GITHUB_HALT_FILE=halt_file)
    try:
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env,
                                    start_new_session=True)
        except OSError as exc:
            return subprocess.CompletedProcess(cmd, 127, "", f"{what}: {exc}")
        try:
            out, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass   # cả nhóm đã thoát giữa lúc hết giờ và lúc giết
            proc.communicate()
            return subprocess.CompletedProcess(cmd, 124, "", f"{what}: timeout after {timeout}s (process group killed)")
        if os.path.exists(halt_file):
            err = (err or "") + f"\n{what}: this read would have halted the board (private halt file, not the shared one)"
        return subprocess.CompletedProcess(cmd, proc.returncode, out, err)
    finally:
        shutil.rmtree(halt_dir, ignore_errors=True)


def gh_cmd():
    return shlex.split(os.environ.get("SB_GH") or "gh")


def tool(env_name, default_name):
    path = os.environ.get(env_name) or os.path.join(HERE, default_name)
    return ["bash", path] if path.endswith(".sh") else [path]


def load_config(config):
    try:
        with open(config, encoding="utf-8") as fh:
            cfg = json.load(fh)
    except (OSError, ValueError) as exc:
        raise Fail(USAGE, f"cannot read config {config}: {exc}")
    return cfg if isinstance(cfg, dict) else {}


def repo_root(config):
    """Main checkout dùng chung (nơi $INFLIGHT_DIR mặc định nằm), kể cả khi chạy từ một worktree.

    Ưu tiên `.repo.path` của config khi là đường dẫn tuyệt đối có thật; không thì cha của `git rev-parse --git-common-dir`
    (trong worktree, --show-toplevel là chính worktree chứ không phải main checkout); cuối cùng là cwd."""
    path = (load_config(config).get("repo") or {}).get("path") or ""
    if isinstance(path, str) and os.path.isabs(path) and os.path.isdir(path):
        return path
    r = run(["git", "rev-parse", "--git-common-dir"], "git rev-parse")
    common = r.stdout.strip() if r.returncode == 0 else ""
    return os.path.dirname(os.path.abspath(common)) if common else os.getcwd()


def normalize_repo(remote):
    remote = re.sub(r"^(https?://github\.com/|git@github\.com:)", "", remote.strip())
    return re.sub(r"\.git$", "", remote)


def resolve_repo(config):
    remote = (load_config(config).get("repo") or {}).get("remote") or ""
    if not remote:
        r = run(["git", "remote", "get-url", "origin"], "git remote")
        remote = r.stdout.strip() if r.returncode == 0 else ""
    repo = normalize_repo(remote)
    if not re.fullmatch(r"[^/\s]+/[^/\s]+", repo):
        raise Fail(USAGE, f"repo unknown: set repo.remote in {config} or an origin remote")
    return repo


def parse_numbers(text):
    if not re.fullmatch(r"\s*[0-9]+(?:\s*,\s*[0-9]+)*\s*", text or ""):
        raise Fail(USAGE, f"--on must be issue numbers separated by commas: {text!r}")
    nums = sorted({int(n) for n in text.split(",")})
    if 0 in nums:
        raise Fail(USAGE, "--on: issue number 0 is not valid")
    return nums


def label_names(item):
    """Nhãn của một thẻ: gộp .labels và .content.labels, nhận chuỗi hoặc {name}, bỏ null."""
    out = []
    content = item.get("content") or {}
    for lbl in (item.get("labels") or []) + (content.get("labels") or []):
        name = lbl.get("name") if isinstance(lbl, dict) else lbl
        if isinstance(name, str) and name:
            out.append(name)
    return out


def read_board(config, items_file=None):
    """Board: file --items (cache của runner) nếu có, không thì `card.sh items`. Trả (JSON thô, [item])."""
    if items_file:
        try:
            with open(items_file, encoding="utf-8") as fh:
                raw = fh.read()
        except OSError as exc:
            raise Fail(READ_FAILED, f"cannot read --items {items_file}: {exc}")
    else:
        r = run(tool("SB_CARD", "super-board-card.sh") + ["--config", config, "items"], "card.sh items", PLAN_TIMEOUT)
        if r.returncode != 0:
            raise Fail(READ_FAILED, f"board read failed (exit {r.returncode}): {r.stderr.strip()[:200]}")
        raw = r.stdout
    try:
        items = json.loads(raw).get("items") or []
    except (ValueError, AttributeError) as exc:
        raise Fail(READ_FAILED, f"board read returned no JSON items: {exc}")
    return raw, [i for i in items if isinstance(i, dict)]


def comment_body(issue, nums, why):
    on = ", ".join(f"#{n}" for n in nums)
    # why gom về một dòng: không dòng nào của comment được bắt đầu bằng `blocked-by:`
    reason = " ".join((why or "").split())
    did = f"Did: in Ready, labelled {', '.join(f'waiting-on:#{n}' for n in nums)}"
    if reason:
        did += f" — {reason}"
    lines = [
        f"[orchestrator] [report] ⏳ waiting · on {on}",
        did,
        f"Next: the runner removes each label when {on} closes; the card is built after that",
        marker(issue, nums),
    ]
    return "\n".join(lines)


def marker(issue, nums):
    return f"<!-- sb-waiting-on {issue}:{','.join(str(n) for n in nums)} -->"


def open_numbers(repo, nums):
    """Giữ các N còn OPEN (issue hay PR mở đều là chờ hợp lệ), bỏ CLOSED/MERGED. Đọc hết TRƯỚC mọi lần ghi:
    N không tồn tại → Fail(64); đọc hỏng hay trạng thái lạ → Fail(79)."""
    gh, out = gh_cmd(), []
    for n in nums:
        r = run(gh + ["issue", "view", str(n), "--repo", repo, "--json", "state,url"], "gh issue view")
        if r.returncode != 0:
            if "could not resolve" in r.stderr.lower():
                raise Fail(USAGE, f"#{n} not found in {repo}")
            raise Fail(READ_FAILED, f"cannot read #{n}: {r.stderr.strip()[:200]}")
        try:
            state = str(json.loads(r.stdout).get("state") or "").upper()
        except (ValueError, AttributeError) as exc:
            raise Fail(READ_FAILED, f"gh issue view #{n} returned no JSON state: {exc}")
        if state == "OPEN":
            out.append(n)
        elif state not in ("CLOSED", "MERGED"):
            raise Fail(READ_FAILED, f"#{n}: unexpected state {state!r}")
    return out


def do_mark(repo, issue, nums, why):
    """Tạo nhãn → comment một lần (marker) → CUỐI CÙNG gắn nhãn vào thẻ. Trả (labels, commented); lỗi → Fail(69|79).

    Gắn nhãn sau cùng: add-label hỏng thì lần gọi sau thấy marker, không comment lặp, chỉ gắn nốt nhãn."""
    gh = gh_cmd()
    labels = [f"waiting-on:#{n}" for n in nums]
    for lbl in labels:
        r = run(gh + ["label", "create", lbl, "--repo", repo, "--force", "--color", LABEL_COLOR], "gh label create")
        if r.returncode != 0:
            raise Fail(WRITE_FAILED, f"gh label create {lbl} failed: {r.stderr.strip()[:200]}")
    r = run(gh + ["issue", "view", str(issue), "--repo", repo, "--json", "comments"], "gh issue view")
    if r.returncode != 0:
        raise Fail(READ_FAILED, f"gh issue view #{issue} comments failed: {r.stderr.strip()[:200]}")
    try:
        comments = json.loads(r.stdout).get("comments") or []
    except (ValueError, AttributeError) as exc:
        raise Fail(READ_FAILED, f"gh issue view #{issue} returned no JSON comments: {exc}")
    mk = marker(issue, nums)
    commented = False
    if not any(isinstance(c, dict) and mk in (c.get("body") or "") for c in comments):
        r = run(gh + ["issue", "comment", str(issue), "--repo", repo, "--body", comment_body(issue, nums, why)],
                "gh issue comment")
        if r.returncode != 0:
            raise Fail(WRITE_FAILED, f"gh issue comment #{issue} failed: {r.stderr.strip()[:200]}")
        commented = True
    edit = gh + ["issue", "edit", str(issue), "--repo", repo]
    for lbl in labels:
        edit += ["--add-label", lbl]
    r = run(edit, "gh issue edit")
    if r.returncode != 0:
        raise Fail(WRITE_FAILED, f"gh issue edit #{issue} --add-label failed: {r.stderr.strip()[:200]}")
    return labels, commented


def cmd_mark(args):
    if args.issue <= 0:
        raise Fail(USAGE, "--issue must be a positive number")
    nums = parse_numbers(args.on)
    if args.issue in nums:
        raise Fail(USAGE, f"#{args.issue} cannot wait on itself")
    repo = resolve_repo(args.config)
    nums = open_numbers(repo, nums)
    if nums:
        labels, commented = do_mark(repo, args.issue, nums, args.why)
    else:
        # mọi blocker đã đóng: không nhãn, không comment — caller giao thẻ như thường
        labels, commented = [], False
    print(json.dumps({"issue": args.issue, "labels": labels, "commented": commented}, ensure_ascii=False, separators=(",", ":")))
    return OK


def cmd_sweep(args):
    repo = resolve_repo(args.config)
    _, items = read_board(args.config, args.items)
    holders = {}   # N -> [(issue, tên nhãn đúng như trên thẻ)]
    for item in items:
        if item.get("status") == "Done":
            continue
        issue = (item.get("content") or {}).get("number")
        if not isinstance(issue, int):
            continue
        for name in label_names(item):
            m = LABEL_RE.match(name)
            if m:
                pair = (issue, name)
                lst = holders.setdefault(int(m.group(1)), [])
                if pair not in lst:
                    lst.append(pair)
    removed, kept, errors = [], [], []
    read_failed = write_failed = False
    gh = gh_cmd()
    for n in sorted(holders):
        r = run(gh + ["issue", "view", str(n), "--repo", repo, "--json", "state", "--jq", ".state"], "gh issue view")
        state = r.stdout.strip().upper() if r.returncode == 0 else ""
        if r.returncode != 0 or state not in ("OPEN", "CLOSED", "MERGED"):
            if r.returncode != 0 and "could not resolve" in r.stderr.lower():
                # số không tồn tại: lỗi dữ liệu của thẻ, không phải sự cố — giữ nhãn, không chặn các số khác
                errors.append({"n": n, "why": f"#{n} not found in {repo}"})
            else:
                read_failed = True
                why = r.stderr.strip()[:200] if r.returncode != 0 else f"unexpected state {state!r}"
                errors.append({"n": n, "why": f"cannot read #{n}: {why}"})
            kept += [[i, n] for i, _ in holders[n]]
            continue
        if state == "OPEN":
            kept += [[i, n] for i, _ in holders[n]]
            continue
        for issue, name in holders[n]:
            w = run(gh + ["issue", "edit", str(issue), "--repo", repo, "--remove-label", name], "gh issue edit")
            if w.returncode != 0:
                write_failed = True
                errors.append({"n": n, "why": f"remove {name} from #{issue} failed: {w.stderr.strip()[:200]}"})
                kept.append([issue, n])
            else:
                removed.append([issue, n])
    print(json.dumps({"removed": removed, "kept": kept, "errors": errors}, ensure_ascii=False, separators=(",", ":")))
    if write_failed:
        return WRITE_FAILED
    return READ_FAILED if read_failed else OK


def read_folded(config):
    # INFLIGHT_DIR (runner truyền) ưu tiên nhất; mặc định là thư mục dùng chung ở main checkout, không phải worktree đang chạy
    base = os.environ.get("INFLIGHT_DIR") or os.path.join(repo_root(config), ".claude", "super-board", "inflight")
    path = os.path.join(base, "fuse", "folded.tsv")
    out = set()
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                head = line.split("\t", 1)[0].strip()
                if head.isdigit():
                    out.add(int(head))
    except FileNotFoundError:
        pass   # chưa có cầu chì nào gộp thẻ: tập rỗng
    except OSError as exc:   # PermissionError, IsADirectoryError…: không nuốt, migrate dừng 79
        raise Fail(READ_FAILED, f"cannot read {path}: {exc}")
    return out


def cmd_migrate(args):
    repo = resolve_repo(args.config)
    raw, items = read_board(args.config, args.items)
    fd, items_path = tempfile.mkstemp(prefix="sb-waiting-items.", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(raw)
        r = run(tool("SB_WAVE_PLAN", "super-board-wave-plan.sh") + ["--config", args.config, "--items", items_path],
                "wave-plan", PLAN_TIMEOUT)
    finally:
        os.unlink(items_path)
    if r.returncode != 0:
        raise Fail(READ_FAILED, f"wave plan failed (exit {r.returncode}): {r.stderr.strip()[:200]}")
    try:
        pending = json.loads(r.stdout).get("pending") or []
    except (ValueError, AttributeError) as exc:
        raise Fail(READ_FAILED, f"wave plan returned no JSON: {exc}")
    folded = read_folded(args.config)
    labels_by_issue = {}
    for item in items:
        n = (item.get("content") or {}).get("number")
        if isinstance(n, int):
            labels_by_issue.setdefault(n, []).extend(label_names(item))
    migrated, skipped = [], []
    code = OK
    for p in pending:
        if not isinstance(p, dict) or not isinstance(p.get("number"), int):
            continue
        issue = p["number"]
        blockers = sorted({b for b in (p.get("openBlockers") or []) if isinstance(b, int) and b > 0 and b != issue})
        lower = [x.lower() for x in labels_by_issue.get(issue, [])]
        if not blockers:
            skipped.append({"number": issue, "why": "no open blocker"})
        elif p.get("needsYou") is True:
            skipped.append({"number": issue, "why": "needs-you (deps)"})
        elif "needs-you" in lower or "human-gated" in lower:
            # kiểm thô, không miễn trừ loop:*: thẻ có nhãn cần người không bao giờ tự rời Blocked
            skipped.append({"number": issue, "why": "needs-you label"})
        elif issue in folded:
            skipped.append({"number": issue, "why": "folded by the suite fuse"})
        elif args.dry_run:
            migrated.append(issue)
        else:
            try:
                do_mark(repo, issue, blockers, "moved out of Blocked: it only waits on other cards")
                if OLD_WAITING_LABEL.lower() in lower:
                    w = run(gh_cmd() + ["issue", "edit", str(issue), "--repo", repo, "--remove-label", OLD_WAITING_LABEL],
                            "gh issue edit")
                    if w.returncode != 0:
                        raise Fail(WRITE_FAILED, f"remove {OLD_WAITING_LABEL} from #{issue} failed: {w.stderr.strip()[:200]}")
                w = run(tool("SB_CARD", "super-board-card.sh") + ["--config", args.config, "move", str(issue), "Ready"],
                        "card.sh move", PLAN_TIMEOUT)
                if w.returncode != 0:
                    raise Fail(WRITE_FAILED, f"move #{issue} Ready failed (exit {w.returncode}): {w.stderr.strip()[:200]}")
            except Fail as exc:
                # dừng ở thẻ hỏng: lần chạy sau làm tiếp (thẻ còn Blocked nên vẫn trong pending)
                print(str(exc), file=sys.stderr)
                code = exc.code
                break
            migrated.append(issue)
    print(json.dumps({"migrated": migrated, "skipped": skipped}, ensure_ascii=False, separators=(",", ":")))
    return code


def main(argv=None):
    p = ArgParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", parser_class=ArgParser)
    m = sub.add_parser("mark")
    m.add_argument("--config", required=True)
    m.add_argument("--issue", required=True, type=int)
    m.add_argument("--on", required=True)
    m.add_argument("--why", default="")
    s = sub.add_parser("sweep")
    s.add_argument("--config", required=True)
    s.add_argument("--items", default=None)
    g = sub.add_parser("migrate")
    g.add_argument("--config", required=True)
    g.add_argument("--items", default=None)
    g.add_argument("--dry-run", action="store_true")
    args = p.parse_args(argv)
    if not args.cmd:
        p.error("a command is required: mark, sweep or migrate")
    try:
        return {"mark": cmd_mark, "sweep": cmd_sweep, "migrate": cmd_migrate}[args.cmd](args)
    except Fail as exc:
        print(str(exc), file=sys.stderr)
        return exc.code


if __name__ == "__main__":
    sys.exit(main())
