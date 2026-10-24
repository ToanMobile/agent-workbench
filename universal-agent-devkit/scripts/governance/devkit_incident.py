#!/usr/bin/env python3
"""Lỗi DO DEVKIT khi board / workflow chạy ở các repo app → thẻ 🐛 trên board DevKit (ToanMobile/agent-workbench, Project #1).

Người dùng 24/10: "khi 5 repo kia chạy mà board, workflow có lỗi gì do devkit thì tạo task trên devkit cho tôi".
Script board ở repo app là bản COPY (.claude/bin), còn kit là symlink (.agents/devkit), nên bộ gom này nằm trong kit và
chỉ ĐỌC những gì board đã ghi, không sửa repo app:
  a. docs/super-board/runs/*.md            manifest của runner (log() tee vào đây)
  b. .claude/super-board/runner/*.watchdog.log
  c. .claude/audit-gate/*.log              chỉ Traceback (hook / gate của kit vỡ)
Mỗi file chỉ đọc phần MỚI (offset trong ledger); lần đầu thấy một file thì bắt đầu ở cuối file (không báo lại lỗi cũ).
Mỗi dòng khớp một luật trong RULES thành một sự cố có chữ ký (luật + văn bản đã bỏ số, sha, đường dẫn; KHÔNG gồm tên
repo: cùng lỗi ở nhiều repo là một thẻ). Sự cố nằm trong spool của ledger tới khi lên được GitHub; chữ ký đã có thẻ mở
thì chỉ đếm thêm. Không bao giờ làm hỏng caller: lỗi gh / create_task chỉ để lại spool, luôn exit 0.

  devkit_incident.py scan [--quiet]       gom + đẩy (SessionStart của kit gọi nền; mọi phiên worker board đều chạy nó)
  devkit_incident.py status               in ledger tóm tắt
Biến môi trường: DEVKIT_INCIDENT=0 tắt · DEVKIT_INCIDENT_REPOS (os.pathsep) · DEVKIT_INCIDENT_HOME ·
DEVKIT_INCIDENT_MIN_INTERVAL_S (mặc định 300).
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

DEVKIT_REPO = "ToanMobile/agent-workbench"
# Whitelist "5 repo" của người dùng (memory default-four-repos, 24/10). ponytail: danh sách cứng, đọc từ một file cấu hình
# khi người dùng thêm/bớt repo thường xuyên hơn.
DEFAULT_REPOS = [
    "/Volumes/Data/Toan/OfficeReader/OfficeReader",
    "/Volumes/Data/Toan/GeelyEx2",
    "/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D",
    "/Volumes/Data/Toan/Game/Humans-vs.-UFOs",
    "/Volumes/Data/Toan/agent-workbench",
]
CREATE_TASK = Path(__file__).resolve().parent / "create_task.py"
GH_TIMEOUT_S = 60
MAX_NEW_CARDS_PER_SCAN = 3
COMMENT_EVERY_S = 24 * 3600
PENDING_TTL_S = 7 * 24 * 3600     # sự cố dưới ngưỡng mà không lặp lại trong 7 ngày thì quên
MAX_READ = 2 * 1024 * 1024         # đọc tối đa 2 MB phần mới của một file mỗi lần

# (id, regex, tiêu đề ngắn, số lần tối thiểu mới thành thẻ, khoá chữ ký: số nhóm regex | chuỗi cố định | None = cả dòng)
# Thứ tự: luật BỎ trước. ponytail: heuristic theo chữ của log board; thêm/bớt luật khi thấy thẻ nhầm hoặc lỗi lọt.
IGNORE = re.compile("|".join([
    r"git fetch origin main failed",            # mạng tạm, runner tự thử lại
    r"error connecting to api\.github\.com",
    r"block-rate alert",                        # thẻ app bị chặn, không phải kit
    r"sleep \d+s killed by signal",
    r"stop marker", r"stopping dispatcher loop", r"refusing to start", r"start overruled",
    r": holding\b", r"\btick —",
    r"auto-resumed", r"replayed OK",            # halt mạng đã tự hồi phục
]))
RULES = [
    # self-reload: khoá = phần trước dấu ":" đầu tiên (chi tiết sau đó là tên worktree/phiên, đổi mỗi lần)
    ("self-reload", re.compile(r"⚠ self-reload: ([^:]*)"), "self-reload: {0}", 1, 1),
    ("runaway", re.compile(r"RUNAWAY"), "board RUNAWAY: không thẻ nào tới Done", 1, "runaway"),
    ("crash-loop", re.compile(r"gave up \(crash loop\)"), "watchdog bỏ cuộc: runner crash loop", 1, "crash-loop"),
    # Hai luật dưới dùng bộ đếm CÓ CỬA SỔ mà runner tự in: runner ngắt thẻ ở lần thứ 2 (early_backoff: 2 lần chết sớm / 10
    # phút; SB_NOOP_MAX: 2 no-op / 24 h). Lần 1 lẻ tẻ (worker xong nhanh hợp lệ, hook SessionEnd của người dùng) không báo.
    ("worker-noop", re.compile(r"\(lane (\w+)\): worker ended with the card still in .* no-op ([2-9]|\d\d) of"),
     "worker lane {0} kết thúc không làm gì lặp lại", 1, 1),
    ("early-death", re.compile(r"\(lane (\w+)\) ended \d+s after dispatch .* early end ([2-9]|\d\d) of this lane"),
     "worker lane {0} chết sớm lặp lại", 1, 1),
    ("shell-error", re.compile(r"([\w./-]+): (?:line \d+: )?(command not found|unbound variable|syntax error)"),
     "script lỗi shell: {0}: {1}", 1, 0),   # khoá = cả "<script>: <lỗi>" (cùng script, khác lỗi = khác thẻ)
]
TRACEBACK = re.compile(r"^Traceback \(most recent call last\):")
EXC_LINE = re.compile(r"^([A-Za-z_][\w.]*(?:Error|Exception|Interrupt|Exit)\b.*)$")
FRAME = re.compile(r'^\s*File "([^"]+)", line \d+, in (\S+)')


def env_home() -> Path:
    return Path(os.environ.get("DEVKIT_INCIDENT_HOME") or Path.home() / ".claude" / "super-board" / "devkit-incidents")


def repos() -> list[Path]:
    raw = os.environ.get("DEVKIT_INCIDENT_REPOS")
    paths = raw.split(os.pathsep) if raw else DEFAULT_REPOS
    return [Path(p) for p in paths if p and Path(p).is_dir()]


def log(home: Path, msg: str) -> None:
    try:
        with open(home / "incident.log", "a", encoding="utf-8") as f:
            f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")
    except OSError as e:   # log là phụ: không có chỗ ghi thì in ra stderr, không làm hỏng scan
        print(f"devkit_incident: cannot write incident.log: {e}", file=sys.stderr)


def normalize(text: str) -> str:
    t = re.sub(r"\b[0-9a-f]{7,40}\b", "SHA", text)
    t = re.sub(r"(?:[\w.\-~]*/)+([\w.\-]+)", r"\1", t)   # đường dẫn → tên file cuối (a.sh và b.sh vẫn là hai chữ ký)
    t = re.sub(r"\d+", "N", t)
    return re.sub(r"\s+", " ", t).strip()[:160]


def signature(rule: str, key: str) -> str:
    return hashlib.sha1(f"{rule}|{normalize(key)}".encode()).hexdigest()[:12]


def log_files(repo: Path) -> list[tuple[Path, str]]:
    """board = lời của runner / watchdog (mọi luật); raw = stderr của runner / watchdog (Traceback + lỗi shell);
    hook = log của hook kit (chỉ Traceback)."""
    sb = repo / ".claude/super-board/runner"
    out = [(p, "board") for p in sorted((repo / "docs/super-board/runs").glob("*.md"))]
    out += [(p, "board") for p in sorted(sb.glob("*.watchdog.log"))]
    out += [(p, "raw") for p in [repo / "docs/super-board/runner.log", *sorted(sb.glob("*.start.log")),
                                 *sorted(sb.glob("*.watchdog.launchd.log"))]]
    out += [(p, "hook") for p in sorted((repo / ".claude/audit-gate").glob("*.log"))]
    return out


def read_new(path: Path, offsets: dict, since: float):
    """(dòng mới đủ \\n, mốc thời gian mà mọi dòng đó được ghi SAU nó). Chỉ file thường: một FIFO trong audit-gate
    (proof_gate.sh) mà open() thì treo."""
    key = str(path)
    try:
        st = path.stat()
    except OSError:
        return [], 0.0
    if not stat.S_ISREG(st.st_mode):
        return [], 0.0
    prev = offsets.get(key)
    born = getattr(st, "st_birthtime", None)   # thiếu trường này (docs os.stat_result: chỉ một số nền tảng có) thì không backfill
    if prev is None:
        # Chưa thấy file: file có từ trước lần quét đầu tiên của máy thì không backfill (lỗi cũ có thể đã sửa); file sinh
        # SAU đó (manifest ngày mới, log hook mới) thì đọc từ đầu, không bỏ lỡ lỗi ghi trước lượt quét kế tiếp.
        start = 0 if born is not None and born >= since else st.st_size
        after = born or 0.0
    elif prev.get("ino") != st.st_ino or prev.get("off", 0) > st.st_size:
        start, after = 0, born or 0.0                 # file bị thay / cắt: đọc lại từ đầu
    else:
        start, after = prev["off"], prev.get("mtime", 0.0)
    start = max(start, st.st_size - MAX_READ)
    try:
        with open(path, "rb") as f:
            f.seek(start)
            chunk = f.read(st.st_size - start)        # đúng tới kích thước đã stat: phần ghi thêm lúc đọc để lượt sau
    except OSError as e:                              # không quyền đọc / file bị xoay giữa stat và open: bỏ file này,
        print(f"devkit_incident: skip {path}: {e}", file=sys.stderr)   # không mất các file khác của lượt quét
        return [], 0.0
    end = chunk.rfind(b"\n") + 1                      # dòng đang ghi dở (chưa có \n) cũng để lượt sau
    offsets[key] = {"ino": st.st_ino, "off": start + end, "mtime": st.st_mtime}
    return chunk[:end].decode("utf-8", "replace").splitlines(), after


def classify_board(line: str):
    # Chữ sau "last log line:" là output của worker (việc của repo app, hook riêng của người dùng như `tuios`), không
    # phải lời runner: không phân loại theo nó.
    line = line.split("last log line:", 1)[0]
    if IGNORE.search(line):
        return None
    for rid, rx, title, min_count, group in RULES:
        m = rx.search(line)
        if m:
            key = group if isinstance(group, str) else m.group(group) if group is not None else line
            return rid, title.format(*m.groups()), min_count, key
    return None


def classify_shell(line: str):
    """stderr của runner / watchdog: chỉ lỗi shell (lời runner đã nằm trong manifest, đọc ở đó, không đếm đôi)."""
    rid, rx, title, min_count, group = next(r for r in RULES if r[0] == "shell-error")
    m = rx.search(line)
    return (rid, title.format(*m.groups()), min_count, m.group(group)) if m else None


def classify_tracebacks(lines: list[str]):
    """Mỗi Traceback → (frame cuối, dòng exception). Chữ ký theo hai thứ đó, không theo số dòng."""
    out, i = [], 0
    while i < len(lines):
        if not TRACEBACK.match(lines[i]):
            i += 1
            continue
        frame, j, found = "", i + 1, False
        while j < len(lines) and j < i + 200 and not (j > i + 1 and TRACEBACK.match(lines[j])):
            fm = FRAME.match(lines[j])
            if fm:
                frame = f"{Path(fm.group(1)).name}:{fm.group(2)}"
            em = EXC_LINE.match(lines[j])
            if em and not lines[j].startswith(" "):
                out.append(("traceback", f"Python lỗi trong {frame or '?'}: {em.group(1)[:60]}", 1,
                            f"{frame} {em.group(1).split(':')[0]}", "\n".join(lines[i:j + 1])))
                found = True
                break
            j += 1
        i = j + 1 if found else j     # không thấy dòng exception: dòng j (có thể là Traceback kế tiếp) chưa được xét
    return out


def load_ledger(home: Path) -> dict:
    try:
        data = json.loads((home / "ledger.json").read_text(encoding="utf-8"))
        if isinstance(data, dict):
            data.setdefault("offsets", {})
            data.setdefault("incidents", {})
            return data
    except FileNotFoundError:
        pass
    except (OSError, ValueError) as e:
        log(home, f"ledger unreadable, starting fresh: {e}")
    return {"offsets": {}, "incidents": {}, "last_scan": 0}   # "since" do scan() đặt ở lần quét đầu


def save_ledger(home: Path, data: dict) -> None:
    tmp = home / f"ledger.json.{os.getpid()}"
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, home / "ledger.json")


def record(incidents: dict, fp: str, rule: str, title: str, min_count: int, repo: Path, src: Path, evidence: str,
           after: float) -> None:
    """after = mốc mà lần gặp này chắc chắn được GHI sau (mtime của file ở lần đọc trước): so với lúc thẻ đóng."""
    now = int(time.time())
    inc = incidents.setdefault(fp, {"rule": rule, "title": mask(title), "min_count": min_count, "count": 0, "repos": [],
                                    "first": now, "evidence": [], "issue": None, "last_comment": 0, "reported_count": 0})
    inc["count"] += 1
    inc["last"] = now
    inc["last_after"] = max(inc.get("last_after", 0.0), after)
    if repo.name not in inc["repos"]:
        inc["repos"].append(repo.name)
    # Ba bằng chứng GẦN NHẤT: thẻ mở lại sau hồi quy phải mang lần gặp mới, không phải lần đầu tiên.
    inc["evidence"] = (inc["evidence"] + [{"repo": repo.name, "file": str(src.relative_to(repo)),
                                           "text": mask(evidence)[-1200:]}])[-3:]   # che TRƯỚC khi cắt: không cắt đôi secret


# Bằng chứng đi từ log repo app (private) lên issue của ToanMobile/agent-workbench, repo PUBLIC: dùng bộ che secret
# chung của kit (bin/regression_checklist.py), thêm phần riêng của đường này: khoá=giá trị ngắn, URL có mật khẩu, khoá PEM,
# đường dẫn tuyệt đối của máy, và chữ tự do sau "last log line:" (nội dung việc trong repo private).
_KIT_BIN = Path(__file__).resolve().parents[2] / "bin"
try:
    sys.path.insert(0, str(_KIT_BIN))
    from regression_checklist import redact_secrets   # noqa: E402
except ImportError as _e:   # kit cài thiếu bin/: vẫn che bằng các mẫu dưới, ghi rõ vào stderr
    print(f"devkit_incident: kit redact_secrets unavailable ({_e}); using local patterns only", file=sys.stderr)

    def redact_secrets(text):
        return text
finally:
    if sys.path and sys.path[0] == str(_KIT_BIN):
        sys.path.pop(0)
EXTRA_SECRETS = [
    # khoá=giá trị, kể cả dạng JSON / repr có ngoặc: "api_key": "x", {'password': 'y'}
    (re.compile(r"(?i)\b([A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD|AUTHORIZATION)[A-Z0-9_]*)(['\"]?\s*[=:]\s*)['\"]?"
                r"(?:(?:bearer|token|basic)\s+)?[^\s'\",}]+['\"]?"), r"\1\2«redacted»"),
    # runner (ready_card_held) giữ thẻ nêu thẻ / PR của repo khác: chỉ giữ tên ngắn, bỏ owner và số
    (re.compile(r"(?i)https?://github\.com/(?!toanmobile/agent-workbench\b)[\w.-]+/([\w.-]+)/\S*"), r"«\1 link»"),
    (re.compile(r"(?i)\b(?!toanmobile/agent-workbench#)[\w.-]+/([\w.-]+)#\d+"), r"«\1 issue»"),
    (re.compile(r"\b(gh[pousr]_|github_pat_|sk-|xox[abprs]-|AKIA)[A-Za-z0-9_\-]{6,}"), r"\1«redacted»"),
    (re.compile(r"(?i)\b(bearer)\s+\S+"), r"\1 «redacted»"),
    (re.compile(r"://[^/\s:@]+:[^/\s@]+@"), "://«redacted»@"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(-----END [A-Z ]*PRIVATE KEY-----|$)", re.S), "«redacted key»"),
    (re.compile(r"(?:/Volumes|/Users|/home|/private|/var|/tmp)(?:/[^\s\"'`:,)]+)+"), "«path»"),
    (re.compile(r"(last log line:).*"), r"\1 «bỏ — nội dung repo private»"),
]


def mask(text: str) -> str:
    text = redact_secrets(text)
    for rx, repl in EXTRA_SECRETS:
        text = rx.sub(repl, text)
    return text


def gh(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(["gh", *args], capture_output=True, text=True, timeout=GH_TIMEOUT_S)


def find_open_issue(fp: str):
    """Thẻ mở trên board DevKit đã mang marker này (cả khi nó nằm trong mục Gộp thêm của thẻ khác)."""
    res = gh(["issue", "list", "--repo", DEVKIT_REPO, "--state", "open", "--search", f"kitbug{fp}",
              "--json", "number,body", "--limit", "5"])
    if res.returncode != 0:
        raise RuntimeError(f"gh issue list exit {res.returncode}: {res.stderr.strip()[:200]}")
    for it in json.loads(res.stdout or "[]"):
        if f"kitbug{fp}" in (it.get("body") or ""):
            return it["number"]
    return None


def issue_closed_at(number: int):
    """Epoch lúc thẻ đóng, hoặc None khi thẻ còn mở."""
    res = gh(["issue", "view", str(number), "--repo", DEVKIT_REPO, "--json", "state,closedAt"])
    if res.returncode != 0:
        raise RuntimeError(f"gh issue view #{number} exit {res.returncode}: {res.stderr.strip()[:200]}")
    info = json.loads(res.stdout or "{}")
    if info.get("state") != "CLOSED":
        return None
    stamp = info.get("closedAt") or ""
    try:
        return datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0      # đóng mà không đọc được lúc đóng: coi như đóng từ lâu (lần gặp nào sau đó cũng là hồi quy)


def card_args(fp: str, inc: dict) -> list[str]:
    ev = "\n".join(f"- `{e['repo']}` · `{e['file']}`:\n```\n{e['text']}\n```" for e in inc["evidence"])
    problem = (f"DevKit tự phát hiện lỗi do kit khi board/workflow chạy (mã `kitbug{fp}`, luật `{inc['rule']}`). "
               f"Gặp {inc['count']} lần ở: {', '.join(inc['repos'])}.\n\nBằng chứng:\n{ev}")
    # --new-card: một lỗi kit một thẻ. Gom vào thẻ bug khác thì marker chống trùng và AC của sự cố dính vào thẻ không liên quan.
    return ["--repo", DEVKIT_REPO, "--labels", "bug", "--new-card", "devkit-incident tự phát hiện: một lỗi kit một thẻ",
            "--title", f"🐛 [bug] devkit-incident: {inc['title']}"[:70],
            "--problem", problem,
            "--fix", "Tìm nguyên nhân gốc trong script / hook của kit đã sinh dòng log trên, sửa một lần ở kit (mọi repo dùng chung qua symlink).",
            "--ac", (f"- [ ] Có test ĐỎ→XANH tái hiện lỗi `{inc['rule']}` ở tầng thấp nhất\n"
                     f"- [ ] Dòng log gây ra `kitbug{fp}` không còn sinh ra trong kịch bản của test đó"),
            "--risk", "🟡 **Medium** · lỗi kit dùng chung, chạm mọi repo đang cài DevKit"]


def create_card(fp: str, inc: dict):
    res = subprocess.run([sys.executable, str(CREATE_TASK), *card_args(fp, inc)], capture_output=True, text=True,
                         timeout=GH_TIMEOUT_S * 4)
    out = res.stdout + res.stderr
    m = re.search(r"/issues/(\d+)", out) or re.search(r"vào thẻ Backlog #(\d+)", out)
    if res.returncode not in (0, 3) or not m:
        raise RuntimeError(f"create_task exit {res.returncode}: {out.strip()[-300:]}")
    return int(m.group(1))


def flush(home: Path, data: dict, quiet: bool) -> None:
    now, made = int(time.time()), 0
    for fp, inc in sorted(data["incidents"].items(), key=lambda kv: kv[1].get("first", 0)):
        if inc["count"] < inc.get("min_count", 1):
            continue
        try:
            if inc.get("issue") is not None and inc["count"] > inc.get("reported_count", 0):
                # Trạng thái đóng chỉ hỏi GitHub tối đa mỗi giờ một lần cho mỗi thẻ (scan chạy mỗi 300 s), và luôn hỏi
                # ngay trước một comment: không comment "gặp lại" vào thẻ vừa đóng.
                closed_at = None
                comment_due = now - inc.get("last_comment", 0) >= COMMENT_EVERY_S
                if comment_due or now - inc.get("state_checked", 0) >= int(os.environ.get("DEVKIT_INCIDENT_STATE_CHECK_S", "3600")):
                    closed_at = issue_closed_at(inc["issue"])
                    inc["state_checked"] = now
                if closed_at is not None and inc.get("last_after", 0) > closed_at:
                    # Lỗi được GHI sau lúc thẻ đóng = hồi quy: thẻ mới chỉ mang lần gặp mới nhất, không comment vào thẻ đóng.
                    log(home, f"kitbug{fp}: #{inc['issue']} closed, the error came back after it — filing a new card")
                    inc["issue"], inc["count"] = None, 1
                    inc["evidence"] = inc["evidence"][-1:]
                    inc["repos"] = [inc["evidence"][-1]["repo"]] if inc["evidence"] else inc["repos"][-1:]
                elif closed_at is not None:
                    inc["reported_count"] = inc["count"]   # mọi lần gặp đều trước lúc đóng: đã được sửa, không gì mới
            if inc.get("issue") is None:
                inc["issue"] = find_open_issue(fp)
                if inc["issue"] is not None:
                    inc["reported_count"] = inc["count"]
                    inc["last_comment"] = now
            if inc.get("issue") is None:
                if made >= MAX_NEW_CARDS_PER_SCAN:
                    continue
                inc["issue"] = create_card(fp, inc)
                inc["reported_count"], inc["last_comment"] = inc["count"], now
                made += 1
                log(home, f"filed #{inc['issue']} for kitbug{fp} ({inc['rule']}, repos={inc['repos']})")
                if not quiet:
                    print(f"🐛 DevKit incident kitbug{fp} → {DEVKIT_REPO}#{inc['issue']}")
            elif inc["count"] > inc.get("reported_count", 0) and now - inc.get("last_comment", 0) >= COMMENT_EVERY_S:
                res = gh(["issue", "comment", str(inc["issue"]), "--repo", DEVKIT_REPO, "--body",
                          f"🔁 `kitbug{fp}` gặp lại: tổng {inc['count']} lần, repo: {', '.join(inc['repos'])}."])
                if res.returncode == 0:
                    inc["reported_count"], inc["last_comment"] = inc["count"], now
                else:
                    log(home, f"comment on #{inc['issue']} failed: {res.stderr.strip()[:200]}")
        except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as e:
            log(home, f"kitbug{fp} kept in spool: {e}")   # GitHub hỏng / mạng: lần scan sau thử lại
    # Sự cố DƯỚI NGƯỠNG mà lâu không lặp lại: quên, để ledger không phình. Sự cố đủ ngưỡng chưa lên được GitHub (gh hỏng,
    # trần thẻ mỗi lượt) nằm trong spool tới khi đẩy được, không bị dọn.
    for fp in [fp for fp, i in data["incidents"].items()
               if i.get("issue") is None and i["count"] < i.get("min_count", 1) and now - i.get("last", now) > PENDING_TTL_S]:
        del data["incidents"][fp]


def scan(quiet: bool) -> int:
    if os.environ.get("DEVKIT_INCIDENT", "1") == "0":
        return 0
    # Máy không có repo nào trong danh sách (máy khác cài kit, CI): trả về ngay, trước khi tạo thư mục hay gọi gh
    # (test_devkit_incident.sh ca 17).
    if not repos():
        return 0
    home = env_home()
    home.mkdir(parents=True, exist_ok=True)
    with open(home / "scan.lock", "w") as lk:
        try:
            fcntl.flock(lk, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0       # một scan khác (phiên khác) đang chạy
        data = load_ledger(home)
        interval = int(os.environ.get("DEVKIT_INCIDENT_MIN_INTERVAL_S", "300"))
        if time.time() - data.get("last_scan", 0) < interval:
            return 0
        data["last_scan"] = int(time.time())
        since = data.setdefault("since", time.time())   # lần quét đầu tiên của máy: mốc "file có từ trước"
        for repo in repos():
            for path, kind in log_files(repo):
                lines, after = read_new(path, data["offsets"], since)
                for rid, title, mc, key, ev in classify_tracebacks(lines):
                    record(data["incidents"], signature(rid, key), rid, title, mc, repo, path, ev, after)
                if kind == "hook":
                    continue
                for line in lines:
                    hit = classify_board(line) if kind == "board" else classify_shell(line)
                    if hit:
                        rid, title, mc, key = hit
                        record(data["incidents"], signature(rid, key), rid, title, mc, repo, path, line.strip(), after)
        data["offsets"] = {k: v for k, v in data["offsets"].items() if Path(k).exists()}   # file log đã xoá: bỏ offset
        save_ledger(home, data)     # offsets trước: GitHub hỏng giữa chừng thì dòng đã đọc vẫn nằm trong spool
        flush(home, data, quiet)
        save_ledger(home, data)
    return 0


def status() -> int:
    data = load_ledger(env_home())
    for fp, i in sorted(data["incidents"].items(), key=lambda kv: -kv[1].get("last", 0)):
        state = f"#{i['issue']}" if i.get("issue") else f"chờ ({i['count']}/{i.get('min_count', 1)})"
        print(f"kitbug{fp}  {state:>12}  {i['rule']:<12} {i['count']:>4}×  {','.join(i['repos'])}  {i['title']}")
    return 0


def main() -> int:
    args = sys.argv[1:]
    cmd = args[0] if args and not args[0].startswith("-") else "scan"
    try:
        if cmd == "status":
            return status()
        if cmd == "scan":
            return scan("--quiet" in args)
    except Exception as e:   # noqa: BLE001 — bộ gom chạy nền trong SessionStart: không bao giờ làm hỏng caller
        try:
            home = env_home()
            home.mkdir(parents=True, exist_ok=True)
            log(home, f"scan crashed: {type(e).__name__}: {e}")
        except OSError as e2:
            print(f"devkit_incident: {type(e).__name__}: {e}; log failed: {e2}", file=sys.stderr)
        return 0
    print(__doc__)
    return 64


if __name__ == "__main__":
    sys.exit(main())
