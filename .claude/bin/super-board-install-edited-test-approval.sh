#!/usr/bin/env bash
# Cài .claude/audit-gate/approved_tests.json vào scratch từ comment edited-tests thắng cuộc (#643).
# --has-edited-tests <meta.json> <sha40>: in true hoặc false, thoát 0 hoặc 1.
# Chế độ cài luôn thoát 0, kể cả khi không ghi gì.
HERE=$(cd "$(dirname "$0")" && pwd)
JQ_FILTER="$HERE/super-board-approved-head.jq"
AUDIT="$HERE/super-board-audit-check.py"

has_mode=0
SCRATCH="" SHA="" META="" PR="" TOP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --has-edited-tests)
      has_mode=1
      META="${2:-}"
      SHA="${3:-}"
      shift $#
      ;;
    --scratch) SCRATCH="${2:-}"; shift 2 ;;
    --sha) SHA="${2:-}"; shift 2 ;;
    --meta) META="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --top) TOP="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

# jq quyết định sha và task:; python chỉ đọc mảng edited-tests của đúng comment đó.
winning() {
  local line
  line=$(jq -r -f "$JQ_FILTER" "$META" 2>/dev/null || true)
  WIN_F1=$(printf '%s\n' "$line" | awk -F '\t' 'NR==1 { print $1 }')
  WIN_F2=$(printf '%s\n' "$line" | awk -F '\t' 'NR==1 { print $2 }')
  WIN_F3=$(printf '%s\n' "$line" | awk -F '\t' 'NR==1 { print $3 }')
  [ "$WIN_F1" = ok ] && [ "$WIN_F2" = "$SHA" ] || return 1
  case "$WIN_F3" in
    task:*) TASK_ID=${WIN_F3#task:} ;;
    *) return 1 ;;
  esac
  [ -n "$TASK_ID" ]
}

if [ "$has_mode" -eq 1 ]; then
  if ! winning; then
    printf '%s\n' false
    exit 1
  fi
  export QA_INS_META="$META"
  if python3 -c "$(cat <<'PY'
import json, os, re, sys
pat = re.compile(r"(?m)^approved-head:([0-9a-f]{40})[ \t\r]*$")
et = re.compile(r"(?m)^edited-tests:[ \t]*(.*)$")
try:
    data = json.load(open(os.environ["QA_INS_META"], encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(1)
last = None
for c in data.get("comments") or []:
    if not isinstance(c, dict):
        continue
    if c.get("authorAssociation") not in ("OWNER", "MEMBER", "COLLABORATOR"):
        continue
    body = c.get("body") or ""
    if pat.search(body):
        last = body
if last is None:
    sys.exit(1)
m = et.search(last)
if not m:
    sys.exit(1)
try:
    arr = json.loads(m.group(1).strip())
except (ValueError, TypeError):
    sys.exit(1)
sys.exit(0 if isinstance(arr, list) and len(arr) > 0 else 1)
PY
)"; then
    printf '%s\n' true
    exit 0
  fi
  printf '%s\n' false
  exit 1
fi

if ! winning; then
  exit 0
fi
if [ -n "$PR" ]; then
  python3 "$AUDIT" "$TASK_ID" "$SHA" --top "$TOP" --pr "$PR" || exit 0
else
  python3 "$AUDIT" "$TASK_ID" "$SHA" --top "$TOP" || exit 0
fi
export QA_INS_META="$META" QA_INS_SCRATCH="$SCRATCH" QA_INS_TASK="$TASK_ID"
python3 -c "$(cat <<'PY'
import hashlib, json, os, re, subprocess, sys
from pathlib import Path

pat = re.compile(r"(?m)^approved-head:([0-9a-f]{40})[ \t\r]*$")
et = re.compile(r"(?m)^edited-tests:[ \t]*(.*)$")
hex64 = re.compile(r"[0-9a-f]{64}\Z")
scratch = Path(os.environ.get("QA_INS_SCRATCH") or "")
task_id = os.environ.get("QA_INS_TASK") or ""

def last_array():
    try:
        data = json.load(open(os.environ["QA_INS_META"], encoding="utf-8"))
    except (OSError, ValueError):
        return []
    last = None
    for c in data.get("comments") or []:
        if not isinstance(c, dict):
            continue
        if c.get("authorAssociation") not in ("OWNER", "MEMBER", "COLLABORATOR"):
            continue
        body = c.get("body") or ""
        if pat.search(body):
            last = body
    if last is None:
        return []
    m = et.search(last)
    if not m:
        return []
    try:
        arr = json.loads(m.group(1).strip())
    except (ValueError, TypeError) as exc:
        sys.stderr.write("install-edited-test-approval: dòng edited-tests không phải mảng JSON hợp lệ: %s\n" % exc)
        return []
    if not isinstance(arr, list):
        sys.stderr.write("install-edited-test-approval: dòng edited-tests không phải mảng JSON hợp lệ: cần mảng object, nhận %s\n" % type(arr).__name__)
        return []
    return arr

def nonempty(v):
    return isinstance(v, str) and v.strip() != ""

FIELDS = ("path", "sha256", "reviewer", "author", "task_id", "reason")

def reject(idx, why):
    # #693: một dòng stderr cho mỗi phần tử bị loại; không in nội dung phần tử.
    sys.stderr.write("install-edited-test-approval: edited-tests[%d] phần tử không hợp lệ: %s\n" % (idx, why))
    return None

def ok_entry(item, idx):
    if not isinstance(item, dict):
        return reject(idx, "không phải object (%s), cần {%s}" % (type(item).__name__, ", ".join(FIELDS)))
    path = item.get("path")
    digest = item.get("sha256")
    reviewer = item.get("reviewer")
    author = item.get("author")
    tid = item.get("task_id")
    reason = item.get("reason")
    missing = [k for k, v in (("path", path), ("reviewer", reviewer), ("author", author), ("task_id", tid), ("reason", reason)) if not nonempty(v)]
    if missing:
        return reject(idx, "thiếu hoặc rỗng trường %s" % ", ".join(missing))
    if not isinstance(digest, str) or not hex64.fullmatch(digest):
        return reject(idx, "sha256 phải là 64 ký tự hex thường")
    path = path.strip()
    if path.startswith("/") or ".." in Path(path).parts:
        return reject(idx, "path phải là đường dẫn tương đối trong repo, không có '..'")
    if reviewer.strip().casefold() == author.strip().casefold():
        return reject(idx, "reviewer trùng author")
    if tid.strip() != task_id:
        return reject(idx, "task_id lệch task của approved-by")
    target = scratch / path
    try:
        got = hashlib.sha256(target.read_bytes()).hexdigest()
    except OSError:
        return reject(idx, "path không đọc được trong scratch")
    if got != digest:
        return reject(idx, "sha256 không khớp file tại head")
    return {
        "path": path,
        "sha256": digest,
        "reviewer": reviewer.strip(),
        "author": author.strip(),
        "task_id": tid.strip(),
        "reason": reason.strip(),
    }

valid = []
for idx, item in enumerate(last_array()):
    row = ok_entry(item, idx)
    if row is not None:
        valid.append(row)
if not valid:
    sys.exit(0)

dest = scratch / ".claude" / "audit-gate" / "approved_tests.json"
rel = ".claude/audit-gate/approved_tests.json"
chk = subprocess.run(["git", "-C", str(scratch), "check-ignore", "-q", "--", rel])
if chk.returncode != 0:
    ex = subprocess.run(
        ["git", "-C", str(scratch), "rev-parse", "--path-format=absolute", "--git-path", "info/exclude"],
        capture_output=True, text=True)
    exclude = (ex.stdout or "").strip()
    if ex.returncode == 0 and exclude:
        ep = Path(exclude)
        ep.parent.mkdir(parents=True, exist_ok=True)
        prev = ep.read_text(encoding="utf-8") if ep.is_file() else ""
        if ".claude/audit-gate/" not in prev.splitlines():
            with ep.open("a", encoding="utf-8") as fh:
                if prev and not prev.endswith("\n"):
                    fh.write("\n")
                fh.write(".claude/audit-gate/\n")

existing = []
if dest.is_file():
    try:
        loaded = json.loads(dest.read_text(encoding="utf-8"))
        if isinstance(loaded, dict) and isinstance(loaded.get("approvals"), list):
            existing = loaded["approvals"]
    except (OSError, ValueError):
        existing = []
order = []
by_path = {}
for item in existing:
    if isinstance(item, dict) and isinstance(item.get("path"), str) and item["path"] not in by_path:
        order.append(item["path"])
        by_path[item["path"]] = item
for item in valid:
    if item["path"] not in by_path:
        order.append(item["path"])
    by_path[item["path"]] = item
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(json.dumps({"approvals": [by_path[p] for p in order]}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
)" || true
exit 0
