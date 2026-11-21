#!/usr/bin/env python3
"""Lỗi DO DEVKIT khi board / workflow chạy ở các repo app → thẻ 🐛 trên board DevKit (ToanMobile/agent-workbench, Project #1).

Người dùng 24/10: "khi 5 repo kia chạy mà board, workflow có lỗi gì do devkit thì tạo task trên devkit cho tôi".
Script board ở repo app là bản COPY (.claude/bin), còn kit là symlink (.agents/devkit), nên bộ gom này nằm trong kit và
chỉ ĐỌC những gì board đã ghi, không sửa repo app:
  a. docs/super-board/runs/*.md            manifest của runner (log() tee vào đây)
  b. .claude/super-board/runner/*.watchdog.log
  c. docs/super-board/runner.log, runner/*.start.log, runner/*.watchdog.launchd.log   stderr runner/watchdog: Traceback + lỗi shell
  d. .claude/audit-gate/*.log              chỉ Traceback (hook / gate của kit vỡ)
Lên issue (repo PUBLIC) chỉ có bằng chứng đã che: secret, đường dẫn tuyệt đối, tên nhánh, link/số thẻ repo app, chữ của worker
sau "last log line:", output lệnh thô của self-reload; Traceback chỉ mang tên file:hàm từng frame + loại exception.
Mỗi file chỉ đọc phần MỚI (offset trong ledger); lần đầu thấy một file thì bắt đầu ở cuối file (không báo lại lỗi cũ).
Mỗi dòng khớp một luật trong RULES thành một sự cố có chữ ký (luật + văn bản đã bỏ số, sha, đường dẫn; KHÔNG gồm tên
repo: cùng lỗi ở nhiều repo là một thẻ). Sự cố nằm trong spool của ledger tới khi lên được GitHub; chữ ký đã có thẻ mở
thì chỉ đếm thêm. Không bao giờ làm hỏng caller: lỗi gh / create_task chỉ để lại spool, luôn exit 0.

  devkit_incident.py scan [--quiet]       gom + đẩy (SessionStart của kit gọi nền; mọi phiên worker board đều chạy nó)
  devkit_incident.py report [tuỳ chọn]    lane báo lỗi nghi do DevKit: tạo 1 task [devkit] (chống trùng) + trả marker chặn thẻ app
  devkit_incident.py status               in ledger tóm tắt
Biến môi trường: DEVKIT_INCIDENT=0 tắt · DEVKIT_INCIDENT_REPOS (os.pathsep) · DEVKIT_INCIDENT_HOME ·
DEVKIT_INCIDENT_MIN_INTERVAL_S (mặc định 300).
"""
from __future__ import annotations

import argparse
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
# Whitelist "6 repo" của người dùng (memory default-four-repos, 25/10: Idle-Plaza-3D thay Neighbours-From-Hell). ponytail: danh sách cứng, đọc từ một file cấu hình
# khi người dùng thêm/bớt repo thường xuyên hơn.
DEFAULT_REPOS = [
    "/Volumes/Data/Toan/OfficeReader/OfficeReader",
    "/Volumes/Data/Toan/GeelyEx2",
    "/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D",
    "/Volumes/Data/Toan/Game/Humans-vs.-UFOs",
    "/Volumes/Data/Toan/Game/Idle-Plaza-3D",
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
    r"RUNAWAY \(daemon\)",                      # daemon tự hoãn giao việc rồi chạy tiếp (tải máy cao làm worker chậm); chỉ 🛑 halt là thẻ
    r"sleep \d+s killed by signal",
    r"\[x\] PASS\b",                           # dòng kết quả test hồi quy xanh (chép vào runs/*.md) có thể chứa chữ RUNAWAY trong mô tả
    r"stop marker", r"stopping dispatcher loop", r"refusing to start", r"start overruled",
    r": holding\b", r"\btick —",
    r"auto-resumed", r"replayed OK",            # halt mạng đã tự hồi phục
    r"self-reload: main stays \w+, behind origin/\S+ \w+: uncommitted edits in the way",   # #1388: file sửa dở của chủ repo chặn ff, đã báo chủ repo; không phải lỗi kit
]))
RULES = [
    # self-reload: khoá = phần trước dấu ":" đầu tiên (chi tiết sau đó là tên worktree/phiên, đổi mỗi lần)
    ("self-reload", re.compile(r"⚠ self-reload: ([^:]*)"), "self-reload: {0}", 1, 1),
    ("runaway", re.compile(r"RUNAWAY"), "board RUNAWAY: không thẻ nào tới Done", 1, "runaway"),
    ("crash-loop", re.compile(r"gave up \(crash loop\)"), "watchdog bỏ cuộc: runner crash loop", 1, "crash-loop"),
    # Hai luật dưới dùng bộ đếm CÓ CỬA SỔ mà runner tự in: runner ngắt thẻ ở lần thứ 2 (early_backoff: 2 lần chết sớm / 10
    # phút; SB_NOOP_MAX: 2 no-op / 24 h). Lần 1 lẻ tẻ (worker xong nhanh hợp lệ, hook SessionEnd của người dùng) không báo.
    # no-op: runner chỉ in "no-op N of max" khi CÒN DƯỚI ngưỡng, tới ngưỡng thì tự chuyển thẻ sang Blocked (block_noop_workers,
    # super-board-run.sh); lỗi thật của pipeline là khi việc chuyển đó thất bại.
    ("worker-noop", re.compile(r"— (\w+) worker is a no-op \d+ times but the card could not be moved to Blocked"),
     "worker lane {0} no-op lặp lại mà runner không chặn được thẻ", 1, 1),
    ("early-death", re.compile(r"\(lane (\w+)\) ended \d+s after dispatch .* early end ([2-9]|\d\d) of this lane"),
     "worker lane {0} chết sớm lặp lại", 1, 1),
    # bash: "<script>: line N: [<lệnh|biến>: ]<lỗi>" — khoá = cả cụm (cùng script, khác lệnh/lỗi = khác thẻ)
    ("shell-error", re.compile(r"([\w./-]+\.(?:sh|bash|py)): (?:line \d+: )?(?:([^:\s]+): )?"
                               r"(command not found|unbound variable|syntax error)"),
     "script lỗi shell: {0}: {1} {2}", 1, 0),
]
TRACEBACK = re.compile(r"^Traceback \(most recent call last\):")
# Dòng cuối của một Traceback: "<module.>*<Class>" hoặc "<module.>*<Class>: <thông điệp>", đoạn cuối viết hoa theo quy ước class
# Python — mọi tên kiểu subprocess.TimeoutExpired / StopIteration, không chỉ đuôi Error/Exception (25/10: runner OfficeReader chết vì
# TimeoutExpired). Chỉ xét ở dòng không thụt lề ĐẦU TIÊN sau frame; loại đoạn cuối viết thường ("fatal: …", "com.x.app", URL).
# ponytail: đánh đổi về phía không đăng nhầm lên repo public — bỏ sót exception tên viết thường (socket.gaierror, struct.error) và
# vẫn nhận một từ có chữ thường kiểu Java/Python (Killed, com.x.PrivApp) đứng NGAY sau frame cuối — chỉ khi một tiến trình khác
# chen đúng chỗ đó (tên đó SẼ lên issue public); đoạn cuối TOÀN HOA (WARNING, PRIVPKG) bị loại vì class exception luôn có chữ thường.
# Nới khi thấy Traceback thật bị bỏ sót trong log board.
# `[^\Wa-z]*` (ký tự \w trừ a-z) dừng ĐÚNG ở chữ thường đầu tiên: cùng ngôn ngữ với `\w*[a-z]` mà không quay lui bậc hai trên một dòng
# dài (OCR 26/10: 'A' + 'a'*32000 + '!' mất ~10 s CPU mỗi lượt quét).
EXC_LINE = re.compile(r"^((?:[A-Za-z_]\w*\.)*[A-Z][^\Wa-z]*[a-z]\w*(?::.*)?)$")
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
    """(dòng mới đủ \\n, mốc thời gian mà mọi dòng đó được ghi SAU nó, vị trí byte từng dòng). Chỉ file thường: một FIFO trong audit-gate
    (proof_gate.sh) mà open() thì treo."""
    key = str(path)
    read_at = time.time()       # trước stat: mọi byte vượt quá kích thước sắp đọc được ghi sau mốc này
    try:
        st = path.stat()
    except OSError:
        return [], 0.0, []
    if not stat.S_ISREG(st.st_mode):
        return [], 0.0, []
    prev = offsets.get(key)
    born = getattr(st, "st_birthtime", None)   # thiếu trường này (docs os.stat_result: chỉ một số nền tảng có) thì không backfill
    if prev is None:
        # Chưa thấy file: file có từ trước lần quét đầu tiên của máy thì không backfill (lỗi cũ có thể đã sửa); file sinh
        # SAU đó (manifest ngày mới, log hook mới) thì đọc từ đầu, không bỏ lỡ lỗi ghi trước lượt quét kế tiếp.
        start = 0 if born is not None and born >= since else st.st_size
        after = born or 0.0
    elif prev.get("ino") != st.st_ino:
        start, after = 0, born or 0.0                 # file bị thay (inode mới), nội dung khác: đọc lại từ đầu
    elif prev.get("off", 0) > st.st_size:
        # cắt ngắn tại chỗ (ghi lại bằng `>`): mọi byte hiện có được ghi sau lần đọc trước
        start, after = 0, prev.get("read_at", prev.get("mtime", 0.0))
    else:
        # byte sau offset đã đọc chắc chắn được ghi SAU lần stat trước: mốc là lúc đọc trước, không phải mtime
        # (log ít ghi có mtime cũ hơn nhiều so với lúc đọc)
        start, after = prev["off"], prev.get("read_at", prev.get("mtime", 0.0))
    clamped = start < st.st_size - MAX_READ
    if clamped:
        start = st.st_size - MAX_READ - 1               # lấy thêm 1 byte trước điểm kẹp: nếu là \n thì dòng đầu còn nguyên, không bỏ nhầm
    try:
        with open(path, "rb") as f:
            f.seek(start)
            chunk = f.read(st.st_size - start)        # đúng tới kích thước đã stat: phần ghi thêm lúc đọc để lượt sau
    except OSError as e:                              # không quyền đọc / file bị xoay giữa stat và open: bỏ file này,
        print(f"devkit_incident: skip {path}: {e}", file=sys.stderr)   # không mất các file khác của lượt quét
        return [], 0.0, []
    end = chunk.rfind(b"\n") + 1                      # dòng đang ghi dở (chưa có \n) cũng để lượt sau
    offsets[key] = {"ino": st.st_ino, "off": start + end, "mtime": st.st_mtime, "read_at": read_at}
    head = 0
    if clamped:                                       # bị kẹp vào giữa một dòng: bỏ mẩu dòng cụt ở đầu
        head = chunk.find(b"\n") + 1
    # tách đúng theo b"\n" trên byte (splitlines còn tách \r, \x0b…): vị trí byte từng dòng khớp file thật dù đọc từ đâu
    lines, offs, o = [], [], start + head
    for seg in chunk[head:end].split(b"\n")[:-1]:
        lines.append(seg.decode("utf-8", "replace"))
        offs.append(o)
        o += len(seg) + 1
    return lines, after, offs


BRANCH = re.compile(r"\bbranch '[^']*'")   # runner: "main checkout is on branch '<x>', not main"


def classify_board(line: str):
    # Chữ sau "last log line:" là output của worker (việc của repo app, hook riêng của người dùng như `tuios`), không
    # phải lời runner: không phân loại theo nó.
    line = line.split("last log line:", 1)[0]
    line = BRANCH.sub("branch «branch»", line)   # tên nhánh của repo app: không lên issue public, không tách chữ ký
    if IGNORE.search(line):
        return None
    for rid, rx, title, min_count, group in RULES:
        m = rx.search(line)
        if m:
            key = group if isinstance(group, str) else m.group(group) if group is not None else line
            return rid, title.format(*(g or "" for g in m.groups())), min_count, key, line[:m.end()] if rid == "self-reload" else line
    return None


def classify_shell(line: str):
    """stderr của runner / watchdog: chỉ lỗi shell. Dòng log() có dấu thời gian của runner (tee ra stdout nên cũng vào
    runner.log) đã đọc ở manifest — bỏ, không đếm đôi và không quét phần "last log line:" của worker trong nó."""
    if STAMPED.match(line):
        return None
    line = line.split("last log line:", 1)[0]
    rid, rx, title, min_count, group = next(r for r in RULES if r[0] == "shell-error")
    m = rx.search(line)
    return (rid, title.format(*(g or "" for g in m.groups())), min_count, m.group(group), m.group(0)) if m else None


def classify_tracebacks(lines: list[str]):
    """Mỗi Traceback → (frame cuối, dòng exception). Chữ ký theo hai thứ đó, không theo số dòng."""
    # Mọi thứ khớp trên dòng GỐC (chỉ bỏ "\r" cuối của CRLF), y như trước. Ngoại lệ duy nhất: dòng mở đầu "Traceback" có thể đứng sau
    # "\r" của tiến trình khác (git fetch ghi đè dòng): header khớp theo phần sau "\r" cuối. Không dùng phần đó cho dòng exception:
    # "\r" trong THÔNG ĐIỆP exception là chữ của chính dòng đó. Chỉ số dòng giữ nguyên: vị trí byte (offs) theo b"\n".
    lines = [ln.rstrip("\r") for ln in lines]
    heads = [ln.rsplit("\r", 1)[-1] for ln in lines]
    out, i = [], 0
    while i < len(lines):
        if not (TRACEBACK.match(lines[i]) or TRACEBACK.match(heads[i])):
            i += 1
            continue
        frames, j, found = [], i + 1, False
        while j < len(lines) and j < i + 200 and not (j > i + 1 and TRACEBACK.match(lines[j])):
            fm = FRAME.match(lines[j])
            if fm:
                frames.append(f"{Path(fm.group(1)).name}:{fm.group(2)}")
            if frames and lines[j].strip() and not lines[j].startswith((" ", "\t")):
                # Dòng không thụt lề đầu tiên sau frame KẾT THÚC Traceback: không khớp tên exception (class cục bộ <locals>,
                # màu ANSI, dòng tiến trình khác chen vào) thì bỏ qua cả Traceback, không quét tiếp tới dòng lạ phía sau.
                em = EXC_LINE.match(lines[j])
                if not em:
                    break
                # Lên repo PUBLIC chỉ có tên file:hàm của từng frame + LOẠI exception: thông điệp lỗi và dòng code
                # có thể mang dữ liệu của repo app (đường dẫn tương đối, giá trị, tên khoá).
                exc = em.group(1).split(":")[0]
                frame = frames[-1]
                out.append(("traceback", f"Python {exc} trong {frame}", 1, f"{frame} {exc}", i,
                            "Traceback: " + " → ".join(frames[-8:]) + f" → {exc}"))
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


STAMPED = re.compile(r"^\[[\d:\- ]{8,19}\] ")   # "[07:32:45] …" (manifest) / "[2026-10-24 13:00:00] …" (watchdog)
SEEN_TTL_S = 14 * 86400   # dấu vân tay dòng đã đếm (mỗi sự cố) sống 14 ngày: theo thời gian, không theo số lượng (#391)


def record(incidents: dict, fp: str, rule: str, title: str, min_count: int, repo: Path, src: Path, evidence: str,
           after: float, raw_line: str = "", pos: int = -1) -> None:
    """after = mốc mà lần gặp này chắc chắn được GHI sau (lúc đọc trước của file): so với lúc thẻ đóng.
    Dòng có dấu thời gian của runner/watchdog ("[HH:MM:SS] …") là một sự kiện duy nhất: đã thấy thì bỏ qua — manifest do git
    theo dõi được checkout / ff ghi lại (inode mới, đọc lại từ đầu) mà không được đếm lại hay mở thẻ hồi quy giả."""
    now = int(time.time())
    inc = incidents.setdefault(fp, {"rule": rule, "title": mask(title), "min_count": min_count, "count": 0, "repos": [],
                                    "first": now, "evidence": [], "issue": None, "last_comment": 0, "reported_count": 0})
    stamped = bool(STAMPED.match(raw_line))
    if raw_line and (stamped or src.parent.name == "runs"):
        # ponytail: manifest chỉ in giờ, không in ngày — cùng câu đúng cùng giây ở hai ngày khác nhau của MỘT repo bị coi là
        # một lần gặp; thêm ngày (tên manifest) vào khoá khi thấy hồi quy bị bỏ sót vì vậy.
        # Dòng KHÔNG dấu thời gian trong manifest (stderr runner ghi thẳng vào): khoá = tên manifest + VỊ TRÍ BYTE của dòng —
        # git checkout / ghi lại cùng nội dung giữ nguyên vị trí (không đếm lại), lỗi nguyên văn ghi thêm sau đó nằm ở vị trí
        # mới (vẫn là một lần gặp, kể cả hồi quy sau khi thẻ đóng trong cùng ngày).
        key = f"{repo.name}|{raw_line.strip()}" if stamped else f"{repo.name}|{src.name}|{pos}|{raw_line.strip()}"
        uid = hashlib.sha1(key.encode()).hexdigest()[:12]
        seen = inc.get("seen")
        if not isinstance(seen, dict):   # ledger cũ: danh sách uid → {uid: lúc thấy}
            seen = inc["seen"] = {u: now for u in seen or []}
        if uid in seen:
            return
        # ponytail: trần theo thời gian thay trần 2000 dòng (lỗi in mỗi tick vượt 2000 lần/ngày làm uid cũ rơi khỏi seen, git ghi
        # lại manifest thì bị đếm lại); manifest git ghi lại sau 14 ngày bị đếm lại, nâng SEEN_TTL_S khi thấy hồi quy giả như vậy.
        seen[uid] = now
        oldest = next(iter(seen))   # dict giữ thứ tự chèn = thứ tự thời gian: bỏ từ đầu tới mục còn hạn, không quét hết
        while now - seen[oldest] > SEEN_TTL_S:
            del seen[oldest]
            oldest = next(iter(seen))
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
REDACT_ERROR = ""
try:
    sys.path.insert(0, str(_KIT_BIN))
    from regression_checklist import redact_secrets   # noqa: E402
except ImportError as _e:   # kit cài thiếu bin/: KHÔNG đăng gì lên repo public (flush dừng, sự cố ở lại spool)
    REDACT_ERROR = f"kit redact_secrets unavailable: {_e}"

    def redact_secrets(text):
        return text
finally:
    if sys.path and sys.path[0] == str(_KIT_BIN):
        sys.path.pop(0)
EXTRA_SECRETS = [
    # khoá=giá trị, kể cả dạng JSON / repr có ngoặc: "api_key": "x", {'password': 'y'}
    # giá trị trong ngoặc được che trọn tới ngoặc đóng (mật khẩu có dấu cách); không ngoặc thì tới khoảng trắng
    (re.compile(r"(?i)\b([A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD|AUTHORIZATION)[A-Z0-9_]*)(['\"]?\s*[=:]\s*)"
                r"(?:\"[^\"\n]*\"?|'[^'\n]*'?|(?:(?:bearer|token|basic)\s+)?[^\s'\",}]+)"), r"\1\2«redacted»"),
    # runner (ready_card_held) giữ thẻ nêu thẻ / PR của repo khác: chỉ giữ tên ngắn, bỏ owner và số
    (re.compile(r"(?i)(?:https?://)?github\.com/(?!toanmobile/agent-workbench\b)[\w.-]+/([\w.-]+)/\S*"), r"«\1 link»"),
    (re.compile(r"(?i)\b(?!toanmobile/agent-workbench#)[\w.-]+/([\w.-]+)#\d+"), r"«\1 issue»"),
    (re.compile(r"\b(gh[pousr]_|github_pat_|sk-|xox[abprs]-|AKIA)[A-Za-z0-9_\-]{6,}"), r"\1«redacted»"),
    (re.compile(r"(?i)\b(bearer)\s+\S+"), r"\1 «redacted»"),
    (re.compile(r"://[^/\s:@]+:[^/\s]*@"), "://«redacted»@"),   # tới '@' CUỐI trước host: mật khẩu có '@' không lọt
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


def _run_create_task(args: list[str], *, dry_run: bool = False):
    """Gọi create_task.py với tập tham số chuẩn (bỏ CLAUDE_CODE_SESSION_ID để không đụng hạn mức phiên người)."""
    env = {k: v for k, v in os.environ.items() if k != "CLAUDE_CODE_SESSION_ID"}
    cmd = [sys.executable, str(CREATE_TASK), *args]
    if dry_run:
        cmd.append("--dry-run")
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=GH_TIMEOUT_S * 4, env=env)
    out = res.stdout + res.stderr
    if dry_run:
        if res.returncode != 0:
            raise RuntimeError(f"create_task --dry-run exit {res.returncode}: {out.strip()[-300:]}")
        return None, out
    m = re.search(r"/issues/(\d+)", out) or re.search(r"vào thẻ Backlog #(\d+)", out)
    if res.returncode not in (0, 3) or not m:
        raise RuntimeError(f"create_task exit {res.returncode}: {out.strip()[-300:]}")
    return int(m.group(1)), out


def create_card(fp: str, inc: dict):
    issue_no, _ = _run_create_task(card_args(fp, inc))
    return issue_no


KIT_TRACE_PATTERNS = (
    re.compile(r"(?:^|[\s\"'/`(])(?:\.agents/devkit|universal-agent-devkit)/[\w./-]+"),
    re.compile(r"(?:^|[\s\"'/`(])\.agents/skills/[\w./-]+"),
    re.compile(r"(?:^|[\s\"'/`(])(?:\.claude|\.agents)/hooks/[\w./-]+"),
    re.compile(r"(?:^|[\s\"'/`(])hooks/[\w./-]+\.(?:sh|py)\b"),
    re.compile(r"(?:^|[\s\"'/`(])\.claude/bin/super-board-[\w.-]+"),
    re.compile(r"(?:^|[\s\"'/`(])\.claude/skills/super-[\w./-]+"),
    re.compile(r"(?:^|[\s\"'/`(])\.claude/workflows/super-board-[\w.-]+"),
    re.compile(r"\b(?:post-fix-gate\.py|proof_gate\.(?:sh|py)|review_gate\.(?:sh|py)|"
               r"hardware_safety_gate(?:_main)?\.(?:sh|py)|block-dangerous-git\.sh|"
               r"block_dangerous_git_main\.py|agent-kit|super-board-[\w-]+\.(?:sh|py|js))\b"),
    re.compile(r"đồng bộ từ agent-workbench"),
)


def extract_kit_paths(text: str) -> list[str]:
    """Trích các dấu vết thuộc DevKit (core-rules §20 mục 1); rỗng nếu lỗi không dẫn tới kit."""
    if not text:
        return []
    found: list[str] = []
    seen: set[str] = set()
    for rx in KIT_TRACE_PATTERNS:
        for m in rx.finditer(text):
            token = m.group(0).strip().lstrip("\"'`(").rstrip("\"'`),.:;")
            # Chuẩn hoá đường dẫn tuyệt đối về phần từ mốc kit trở đi để chữ ký không phụ thuộc máy/worktree
            for anchor in (".agents/devkit/", "universal-agent-devkit/", ".agents/skills/",
                           ".claude/bin/", ".claude/skills/", ".claude/workflows/", ".claude/hooks/", ".agents/hooks/"):
                idx = token.find(anchor)
                if idx >= 0:
                    token = token[idx:]
                    break
            if token and token not in seen:
                seen.add(token)
                found.append(token)
    return found


def normalize_return_col(from_col: str | None) -> str:
    """Cột trả về sau khi kit sửa và đồng bộ: Building phải về Ready để runner/wave chọn lại."""
    col = (from_col or "").strip()
    if col in ("Ready", "QA", "Review"):
        return col
    return "Ready"


def format_app_block_comment(kit_issue: int | None, from_col: str | None, lane: str = "orchestrator",
                             symptom: str = "", evidence: str = "") -> tuple[str, str, str]:
    """Tạo marker phân loại, cột đích và nội dung block comment chuẩn cho thẻ app bị lỗi kit (không gắn needs-you/🙋)."""
    target_col = normalize_return_col(from_col)
    lane_role = lane if lane in ("builder", "qa", "reviewer", "collect", "orchestrator") else "orchestrator"
    issue_ref = f"{DEVKIT_REPO}#{kit_issue}" if kit_issue else f"{DEVKIT_REPO}#TBD"
    marker = f"<!-- sb-blocked-reason: devkit-incident repo={DEVKIT_REPO} issue={kit_issue or 0} from={target_col} -->"
    why_txt = mask(symptom or "lỗi phát sinh từ thành phần dùng chung của DevKit")
    ev_txt = mask(evidence or "xem chi tiết tại task [devkit]")[:240]
    body = "\n".join([
        f"[{lane_role}] [blocker] 🛑 blocked · ⚙ lỗi DevKit ({issue_ref})",
        f"Reason tag:  ⚙",
        f"Why blocked: {why_txt} (đã gắn task {issue_ref})",
        f"Evidence:    {ev_txt}",
        f"Checked:     đối chiếu dấu vết theo core-rules §20 mục 1 và kiểm tra trùng trên {DEVKIT_REPO}",
        f"What blocks: chờ {issue_ref} đóng và repo này đồng bộ bản sửa của DevKit",
        f"Why I (bot) cannot decide:",
        f"             mã nguồn DevKit nằm ở {DEVKIT_REPO}; sửa trực tiếp ở repo con sẽ bị ghi đè khi đồng bộ",
        f"To unblock:  [ ] Đợi {issue_ref} đóng và chạy `agent-kit parity --fix` / `agent-kit init` để đồng bộ",
        f"Move back:   drag this card to {target_col} after the steps above are done",
        marker,
        f"blocked-by:  {issue_ref}",
    ])
    return marker, target_col, body


def report_incident(trace: str, symptom: str = "", repo_name: str = "", root_cause: str = "",
                    fix: str = "", oracle: str = "", lane: str = "orchestrator",
                    from_col: str = "Ready", dry_run: bool = False) -> dict:
    """Phân loại lỗi từ lane; nếu thuộc DevKit thì chống trùng và tạo 1 task `[devkit]` ở repo nguồn."""
    combined = "\n".join(part for part in (trace, root_cause) if part)
    kit_paths = extract_kit_paths(combined)
    if not kit_paths:
        return {"is_devkit": False, "created": False, "duplicate": False, "issue": None, "kit_paths": []}
    if REDACT_ERROR and not dry_run:
        raise RuntimeError(f"fail-closed: {REDACT_ERROR}")

    first_err = next((ln.strip() for ln in trace.splitlines() if ln.strip()), "")
    short_sym = mask(symptom.strip() or first_err or f"lỗi tại {kit_paths[0]}")
    short_sym = re.sub(r"\s+", " ", short_sym).strip()[:58]
    title = f"[devkit] {short_sym}"[:70]
    sig_key = "|".join(sorted(kit_paths)[:4]) + "|" + normalize(symptom or first_err or kit_paths[0])
    fp = signature("devkit-lane", sig_key)
    marker_tag = f"kitbug{fp}"

    home = env_home()
    home.mkdir(parents=True, exist_ok=True)
    data = load_ledger(home)
    inc = data["incidents"].get(fp)
    existing_issue = None
    if isinstance(inc, dict) and inc.get("issue") is not None:
        closed_at = issue_closed_at(int(inc["issue"]))
        if closed_at is None:
            existing_issue = int(inc["issue"])
        else:
            inc["issue"] = None

    if existing_issue is None:
        existing_issue = find_open_issue(fp)

    duplicate = existing_issue is not None
    created = False
    issue_no = existing_issue
    dry_preview = ""

    if existing_issue is None:
        masked_trace = mask(trace.strip())[-1200:]
        masked_rc = mask(root_cause.strip()) if root_cause.strip() else f"Giả thuyết: lỗi tại {', '.join(kit_paths[:3])}"
        masked_fix = mask(fix.strip()) if fix.strip() else "Sửa nguyên nhân gốc một lần tại repo nguồn DevKit (agent-workbench) rồi đồng bộ sang repo con."
        masked_oracle = mask(oracle.strip()) if oracle.strip() else f"Test RED→GREEN cho dấu vết `{kit_paths[0]}` ở repo nguồn."
        src_label = mask(repo_name.strip()) if repo_name.strip() else "repo con"
        problem = (
            f"Triệu chứng ({src_label}, mã `{marker_tag}`): {mask(symptom or short_sym)}\n\n"
            f"Bằng chứng (đã che bí mật/đường dẫn riêng):\n```\n{masked_trace}\n```\n\n"
            f"Nguyên nhân gốc: {masked_rc}"
        )
        args = [
            "--repo", DEVKIT_REPO,
            "--labels", "bug",
            "--new-card", "devkit-incident từ lane: một lỗi kit một thẻ",
            "--title", title,
            "--problem", problem,
            "--fix", masked_fix,
            "--ac", f"- [ ] {masked_oracle}\n- [ ] Lỗi `{marker_tag}` không còn tái hiện sau khi đồng bộ kit sang repo con",
            "--risk", "🟡 **Medium** · lỗi kit dùng chung, chạm mọi repo đang cài DevKit",
        ]
        issue_no, dry_preview = _run_create_task(args, dry_run=dry_run)
        created = not dry_run and issue_no is not None

    if not dry_run and issue_no is not None:
        now = int(time.time())
        data["incidents"][fp] = {
            "rule": "devkit-lane",
            "title": title,
            "min_count": 1,
            "count": (inc.get("count", 0) + 1) if isinstance(inc, dict) else 1,
            "repos": sorted({*((inc.get("repos") or []) if isinstance(inc, dict) else []), *([repo_name] if repo_name else [])}),
            "first": inc.get("first", now) if isinstance(inc, dict) else now,
            "last": now,
            "evidence": [{"repo": repo_name or "lane", "file": kit_paths[0], "text": mask(trace)[-400:]}],
            "issue": issue_no,
            "reported_count": 1,
            "last_comment": now,
            "state_checked": now,
        }
        save_ledger(home, data)

    blk_marker, target_col, blk_comment = format_app_block_comment(
        issue_no, from_col, lane=lane, symptom=short_sym, evidence=first_err or kit_paths[0]
    )
    return {
        "is_devkit": True,
        "created": created,
        "duplicate": duplicate,
        "dry_run": dry_run,
        "fingerprint": marker_tag,
        "issue": issue_no,
        "ref": f"{DEVKIT_REPO}#{issue_no}" if issue_no else None,
        "title": title,
        "kit_paths": kit_paths,
        "target_col": target_col,
        "marker": blk_marker,
        "block_comment": blk_comment,
        "dry_preview": dry_preview if dry_run else "",
    }


def flush(home: Path, data: dict, quiet: bool) -> None:
    if REDACT_ERROR:   # fail closed: không có bộ che secret chung thì không đăng lên repo PUBLIC
        log(home, f"not posting ({REDACT_ERROR}); incidents stay in the spool")
        return
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
                lines, after, offs = read_new(path, data["offsets"], since)   # offs: vị trí byte từng dòng
                for rid, title, mc, key, at, ev in classify_tracebacks(lines):
                    record(data["incidents"], signature(rid, key), rid, title, mc, repo, path, ev, after, ev, offs[at])
                if kind == "hook":
                    continue
                for idx, line in enumerate(lines):
                    hit = classify_board(line) if kind == "board" else classify_shell(line)
                    if hit:
                        rid, title, mc, key, ev = hit   # ev: self-reload bỏ output lệnh thô sau dấu ":" (repo app)
                        record(data["incidents"], signature(rid, key), rid, title, mc, repo, path, ev.strip(), after, line, offs[idx])
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


def report_cmd(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="devkit_incident.py report")
    ap.add_argument("--trace", default="", help="Đoạn log / stack trace / đường dẫn lỗi")
    ap.add_argument("--trace-file", default="", help="File log cần đọc (tối đa 64 KB cuối)")
    ap.add_argument("--symptom", default="", help="Triệu chứng ngắn cho tiêu đề [devkit]")
    ap.add_argument("--repo-name", default="", help="Tên repo con gặp lỗi")
    ap.add_argument("--root-cause", default="", help="Nguyên nhân gốc hoặc file:dòng dự kiến")
    ap.add_argument("--fix", default="", help="Hướng sửa đề xuất")
    ap.add_argument("--oracle", default="", help="Test RED→GREEN kỳ vọng ở repo nguồn")
    ap.add_argument("--lane", default="orchestrator", help="Lane phát hiện lỗi (builder|qa|reviewer|orchestrator)")
    ap.add_argument("--from-col", default="Ready", help="Cột trước khi bị chặn (Ready|Building|QA|Review)")
    ap.add_argument("--dry-run", action="store_true", help="Chạy thử không tạo issue thật")
    ap.add_argument("--json", action="store_true", help="In JSON kết quả")
    args = ap.parse_args(argv)

    trace = args.trace
    if args.trace_file:
        try:
            with open(args.trace_file, "rb") as fh:
                fh.seek(0, os.SEEK_END)
                size = fh.tell()
                fh.seek(max(0, size - 65536))
                file_txt = fh.read().decode("utf-8", "replace")
            trace = f"{trace}\n{file_txt}".strip()
        except OSError as e:
            print(f"devkit_incident report: cannot read --trace-file: {e}", file=sys.stderr)
            return 64

    if not trace.strip() and not args.root_cause.strip():
        print("devkit_incident report: cần --trace, --trace-file hoặc --root-cause", file=sys.stderr)
        return 64

    res = report_incident(
        trace,
        symptom=args.symptom,
        repo_name=args.repo_name,
        root_cause=args.root_cause,
        fix=args.fix,
        oracle=args.oracle,
        lane=args.lane,
        from_col=args.from_col,
        dry_run=args.dry_run,
    )
    if args.json:
        print(json.dumps(res, ensure_ascii=False))
    elif res["is_devkit"]:
        status_word = "DRY-RUN" if res["dry_run"] else ("TRÙNG" if res["duplicate"] else "ĐÃ TẠO")
        print(f"🔧 [{status_word}] {res['ref'] or res['title']} ({res['fingerprint']}) · về {res['target_col']}")
    else:
        print("ℹ️ Dấu vết không thuộc DevKit — đi luồng xử lý thường.")
    return 0 if res["is_devkit"] else 1


def main() -> int:
    args = sys.argv[1:]
    cmd = args[0] if args and not args[0].startswith("-") else "scan"
    if cmd == "report":
        try:
            return report_cmd(args[1:])
        except SystemExit as e:
            return 64 if e.code else 0
        except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as e:
            print(f"devkit_incident report: {e}", file=sys.stderr)
            return 69
    if cmd == "scan" and "--quiet" in args:   # chạy nền từ hook: tách khỏi nhóm tiến trình của hook, không bị giết theo nó
        try:
            os.setsid()
        except OSError as e:                  # đã là trưởng session (chạy tay): giữ nguyên
            print(f"devkit_incident: setsid skipped: {e}", file=sys.stderr)
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
