#!/usr/bin/env bash
# Regression test: scripts/governance/runs_archive.py nối runs.jsonl vào archive/runs-<YYYYMMDD>.jsonl (plan ổn định 0.5, #686).
# Thư mục common giả (--common-dir) chứa postfix-gate/runs.jsonl:
#   * chạy 2 lần liên tiếp trên cùng runs.jsonl => archive không có dòng trùng, file không đổi;
#   * thêm dòng mới => CHỈ dòng mới được nối (dòng cũ giữ nguyên thứ tự và byte);
#   * dòng của hai ngày khác nhau => hai file runs-<ngày>.jsonl;
#   * xoá file mốc (.runs-archive.state) rồi chạy lại => vẫn không trùng (khử trùng bằng sha256 của dòng);
#   * dòng cuối chưa có "\n" (gate ghi dở) và dòng hỏng không được lưu; hoàn tất dòng đó thì lần sau lưu;
#   * runs.jsonl gốc không đổi (sha256 trước/sau mỗi lần chạy); thiếu runs.jsonl => exit 0; common-dir sai => exit 2.
#   RA_SCRIPT=<file>  thử bản khác của script (chưa có script: ĐỎ; bản mutant bỏ khử trùng: phải ĐỎ)
#   RA_PY=<python>    trình thông dịch (mặc định python3)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${RA_SCRIPT:-$DEVKIT_DIR/scripts/governance/runs_archive.py}"
PYBIN="${RA_PY:-python3}"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
"$PYBIN" -I - "$SCRIPT" "$TMP" <<'PYEND'
import glob, hashlib, json, os, subprocess, sys, time

SCRIPT, TMP = sys.argv[1], sys.argv[2]
PY = sys.executable
fails = 0
DAY = 86400
# giữa trưa giờ máy của một ngày cố định: +- vài giờ vẫn cùng ngày, +1 ngày chắc chắn sang ngày khác
D1 = int(time.mktime((2026, 10, 29, 12, 0, 0, 0, 0, -1)))


def chk(cond, good, why=""):
    global fails
    if cond:
        print("✔ " + good, flush=True)
    else:
        fails += 1
        print("✖ %s: %s" % (good, why), flush=True)
    return bool(cond)


def line(epoch, tag):
    return json.dumps({"v": 1, "epoch": epoch, "ts": "t", "project": "p", "tag": tag}, sort_keys=True)


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def run(common):
    p = subprocess.run([PY, "-I", SCRIPT, "--common-dir", common], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    return p.returncode, p.stdout.decode(), p.stderr.decode()


def archive_files(common):
    return sorted(glob.glob(os.path.join(common, "postfix-gate", "archive", "runs-*.jsonl")))


def lines_of(path):
    return [l for l in open(path, encoding="utf-8").read().split("\n") if l]


def all_archived(common):
    out = []
    for f in archive_files(common):
        out.extend(lines_of(f))
    return out


print("python %s, script %s" % (sys.version.split()[0], SCRIPT), flush=True)
if not chk(os.path.isfile(SCRIPT), "script tồn tại", SCRIPT):
    sys.exit(1)

common = os.path.join(TMP, "common")
pg = os.path.join(common, "postfix-gate")
os.makedirs(pg)
runs = os.path.join(pg, "runs.jsonl")
a1, a2, a3 = line(D1, "a1"), line(D1 + 60, "a2"), line(D1 + 120, "a3")
b1 = line(D1 + DAY, "b1")
with open(runs, "w") as fh:
    fh.write("\n".join([a1, a2, a3, b1]) + "\n")
sha_runs = sha(runs)

rc, out, err = run(common)
chk(rc == 0, "lần 1: exit 0", "rc=%s err=%s" % (rc, err[-200:]))
files = archive_files(common)
chk(len(files) == 2, "dòng của hai ngày => hai file runs-<ngày>.jsonl", files)
if len(files) == 2:
    chk(lines_of(files[0]) == [a1, a2, a3] and lines_of(files[1]) == [b1], "ngày 1 có 3 dòng đúng thứ tự, ngày 2 có 1 dòng", [lines_of(f) for f in files])
    chk(os.path.basename(files[0]) == time.strftime("runs-%Y%m%d.jsonl", time.localtime(D1)), "tên file theo epoch của dòng", files[0])
chk(os.path.isfile(os.path.join(pg, "archive", ".runs-archive.state")), "có file mốc .runs-archive.state")
chk(sha(runs) == sha_runs, "lần 1: runs.jsonl gốc không đổi (sha256)")
snap = [sha(f) for f in archive_files(common)]

rc, out, err = run(common)
chk(rc == 0, "lần 2 (cùng runs.jsonl): exit 0", err[-200:])
chk([sha(f) for f in archive_files(common)] == snap, "lần 2: archive không đổi một byte")
chk(len(all_archived(common)) == len(set(all_archived(common))) == 4, "lần 2: không có dòng trùng, tổng 4", all_archived(common))
chk(sha(runs) == sha_runs, "lần 2: runs.jsonl gốc không đổi")

c1, c2 = line(D1 + DAY + 60, "c1"), line(D1 + 2 * DAY, "c2")
with open(runs, "a") as fh:
    fh.write(c1 + "\n" + c2 + "\n")
sha_runs = sha(runs)
rc, out, err = run(common)
chk(rc == 0, "lần 3 (thêm 2 dòng): exit 0", err[-200:])
files = archive_files(common)
chk(len(files) == 3, "lần 3: thêm file của ngày 3", files)
if len(files) == 3:
    chk(lines_of(files[1]) == [b1, c1], "ngày 2: chỉ nối c1 sau b1, dòng cũ giữ nguyên", lines_of(files[1]))
    chk(sha(files[0]) == snap[0], "ngày 1 không đổi một byte")
    chk(lines_of(files[2]) == [c2], "ngày 3 chỉ có c2", lines_of(files[2]))
chk(sha(runs) == sha_runs, "lần 3: runs.jsonl gốc không đổi")

os.unlink(os.path.join(pg, "archive", ".runs-archive.state"))
rc, out, err = run(common)
everything = all_archived(common)
chk(rc == 0 and len(everything) == len(set(everything)) == 6, "xoá mốc rồi chạy lại: vẫn 6 dòng, không trùng", everything)

# dòng dở dang (chưa có \n) và dòng hỏng không được lưu
d1 = line(D1 + 2 * DAY - 60, "d1")             # ghi muộn: epoch nhỏ hơn mốc (c2) nhưng trong khoảng gối đầu
with open(runs, "a") as fh:
    fh.write("không phải json\n" + d1)           # d1 chưa có \n cuối
rc, out, err = run(common)
chk(rc == 0 and d1 not in all_archived(common), "dòng cuối chưa có \\n chưa được lưu", all_archived(common))
chk("không phải json" not in "\n".join(all_archived(common)), "dòng hỏng không được lưu")
with open(runs, "a") as fh:
    fh.write("\n")
rc, out, err = run(common)
chk(rc == 0 and all_archived(common).count(d1) == 1, "hoàn tất dòng dở: lần sau lưu đúng một lần", all_archived(common))

# thiếu runs.jsonl / common-dir sai
empty = os.path.join(TMP, "empty-common")
os.makedirs(empty)
rc, out, err = run(empty)
chk(rc == 0, "thiếu runs.jsonl => exit 0", "rc=%s %s" % (rc, err[-200:]))
rc, out, err = run(os.path.join(TMP, "khong-co"))
chk(rc == 2, "common-dir không tồn tại => exit 2", "rc=%s" % rc)

print("\n%d lỗi" % fails if fails else "\nTất cả PASS")
sys.exit(1 if fails else 0)
PYEND
