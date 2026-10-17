#!/usr/bin/env bash
# Test hồi quy cho merge_policy.size_exclude của config agent-workbench (.claude/bin/super-board-merge-policy.py).
# 2026-10-17: PR #33 (issue-4) review sạch, truth-check 82/100, nhưng bị giữ chờ người vì diff 512 dòng > 400, trong đó
# 355 dòng là bằng chứng QA ở docs/super-board/runs/ (không phải code). Bằng chứng QA không tính vào cỡ PR;
# code vượt trần vẫn phải chờ người duyệt.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
CONFIG="$ROOT/.claude/super-board/configs/agent-workbench.json"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
: > "$TMP/empty.diff"

size_verdict() {  # $1 = meta json; in ra "size" nếu chính sách đòi người duyệt vì cỡ PR, ngược lại "ok"
  python3 "$POLICY" --config "$CONFIG" --meta "$1" --diff "$TMP/empty.diff" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print("size" if any(h.get("category")=="size" for h in d["human"]) else "ok")'
}

# 157 dòng code + 355 dòng bằng chứng QA = 512 dòng: chỉ 157 dòng được tính.
cat > "$TMP/evidence.json" <<'JSON'
{"labels":[],"body":"","files":[
{"path":"universal-agent-devkit/hooks/test_evidence_gate.sh","additions":46,"deletions":0},
{"path":"universal-agent-devkit/tests/verification/test_evidence_check7_pair.sh","additions":111,"deletions":0},
{"path":"docs/super-board/runs/issue-4-qa-v2/report.md","additions":355,"deletions":0}]}
JSON
[ "$(size_verdict "$TMP/evidence.json")" = ok ] \
  && ok "QA evidence under docs/super-board/runs/ is not counted toward the PR size cap" \
  || fail "512-line PR with 355 lines of QA evidence still waits for a human (evidence counted)"

# 450 dòng code thật: vẫn vượt trần 400, phải chờ người.
cat > "$TMP/code.json" <<'JSON'
{"labels":[],"body":"","files":[
{"path":"universal-agent-devkit/hooks/big_change.sh","additions":450,"deletions":0}]}
JSON
[ "$(size_verdict "$TMP/code.json")" = size ] \
  && ok "450 lines of real code still exceeds the cap: waits for a human" \
  || fail "450-line code PR no longer waits for a human (cap weakened)"

# Setting size_exclude thay toàn bộ mặc định: lockfile vẫn phải được loại.
cat > "$TMP/lock.json" <<'JSON'
{"labels":[],"body":"","files":[
{"path":"app/src/a.sh","additions":50,"deletions":0},
{"path":"web/package-lock.json","additions":900,"deletions":0}]}
JSON
[ "$(size_verdict "$TMP/lock.json")" = ok ] \
  && ok "default exclusions (lockfiles) kept after size_exclude was set" \
  || fail "lockfile lines counted: size_exclude replaced the defaults without re-listing them"

# Chỉ loại ĐỊNH DẠNG bằng chứng: code đặt dưới docs/super-board/runs/ vẫn phải tính vào trần (OCR 17/10), kể cả file trông giống
# thư mục bị loại (runs-tool/) và dòng xoá.
cat > "$TMP/hidden-code.json" <<'JSON'
{"labels":[],"body":"","files":[
{"path":"docs/super-board/runs/issue-9-qa/helper.py","additions":450,"deletions":0}]}
JSON
[ "$(size_verdict "$TMP/hidden-code.json")" = size ] \
  && ok "executable code under docs/super-board/runs/ still counts toward the cap" \
  || fail "450 lines of .py under docs/super-board/runs/ were skipped: the cap can be dodged"
cat > "$TMP/lookalike.json" <<'JSON'
{"labels":[],"body":"","files":[
{"path":"docs/super-board/runs-tool/notes.md","additions":450,"deletions":0}]}
JSON
[ "$(size_verdict "$TMP/lookalike.json")" = size ] \
  && ok "a path that only looks like the evidence folder (runs-tool/) still counts" \
  || fail "docs/super-board/runs-tool/ was treated as evidence"

# Biên của trần: đúng 400 dòng tính được thì qua, 401 thì chờ người; dòng xoá cũng tính.
cat > "$TMP/cap400.json" <<'JSON'
{"labels":[],"body":"","files":[{"path":"app/a.sh","additions":300,"deletions":100}]}
JSON
cat > "$TMP/cap401.json" <<'JSON'
{"labels":[],"body":"","files":[{"path":"app/a.sh","additions":300,"deletions":101}]}
JSON
[ "$(size_verdict "$TMP/cap400.json")" = ok ] && [ "$(size_verdict "$TMP/cap401.json")" = size ] \
  && ok "the cap is exact: 400 changed lines (additions + deletions) pass, 401 wait for a human" \
  || fail "cap boundary wrong (400 -> $(size_verdict "$TMP/cap400.json"), 401 -> $(size_verdict "$TMP/cap401.json"))"

[ "$FAILS" -eq 0 ] && echo "✅ test_size_exclude_evidence: all passed" || { echo "❌ test_size_exclude_evidence: $FAILS failed"; exit 1; }
