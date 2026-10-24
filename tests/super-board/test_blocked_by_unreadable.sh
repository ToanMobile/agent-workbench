#!/usr/bin/env bash
# Test hồi quy #386 (24/10): `blocked-by: #377` (có dấu #) làm deps trả parseable:false, thẻ kẹt Blocked mà không ai biết:
# status gộp nó vào "other", runner không log gì. Luật:
#  1. super-board-status.py: thẻ Blocked có dòng blocked-by không đọc được vào nhóm riêng kèm lý do, không nằm trong "other".
#     `blocked-by: -` và `blocked-by: 32, 91` giữ nguyên hành vi (không phải nhóm này).
#  2. runner (sweep_blocked_cards): plan.flag của thẻ Blocked được log một lần cho mỗi (thẻ, lý do), bền qua lần gọi sau.
# Chạy offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-unreadable.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ── 1. status
OUT="$(cd "$ROOT" && PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT/.claude/bin/super-board-status.py" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sb_status", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
c = lambda *bodies: [{"body": b, "createdAt": "2026-10-24T0%d" % i} for i, b in enumerate(bodies)]
comments = {
    1: c("Reason tag: 🛡\nblocked-by: #377"),
    2: c("blocked-by: none — but #26 must merge first"),
    3: c("blocked-by: -"),
    4: c("blocked-by: 32, 91"),
    5: c("blocked-by: #377", "blocked-by: 377"),
    6: c("no line here"),
}
blockers = [{"number": n, "title": "t%d" % n} for n in comments]
bad, rest = m.split_unreadable_blocked_by(blockers, comments)
print("bad=" + ",".join(str(n) for n in sorted(bad)))
print("rest=" + ",".join(str(i["number"]) for i in rest))
print("why1=%s" % ("#377" in bad.get(1, "")))
print("why2=%s" % ("#26" in bad.get(2, "")))
PY
)"
chk() { printf '%s\n' "$OUT" | grep -qx "$1"; }
chk "bad=1,2" && chk "rest=3,4,5,6" && chk "why1=True" && chk "why2=True" \
  && ok "status: #377 và 'none — but #26' vào nhóm riêng có lý do; '-', '32, 91', dòng sửa lại, không có dòng: giữ nguyên" \
  || fail "status: $(echo "$OUT" | tr '\n' ' ')"

# ── 2. runner
mkdir -p "$TMP/sbin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/sbin/super-board-github-read.py"
printf '#!/usr/bin/env bash\nprintf %%s\\\\n "$STUB_PLAN"\n' > "$TMP/sbin/super-board-wave-plan.sh"
chmod +x "$TMP/sbin/"*
printf '{"project":{"owner":"x","number":1},"repo":{"path":".","remote":"https://github.com/x/y"}}' > "$TMP/cfg.json"
PLAN='{"sweep":[],"flag":[{"number":319,"title":"t","why":"the `blocked-by:` line reads \"#377\""}]}'
run_sweep() {   # $1 = plan; prints the log lines
  ( SB_LIB_ONLY=1 . "$RUNNER" || exit 99
    set +e
    log() { echo "$*" >> "$TMP/log"; }; gh_checkpoint() { :; }; gh_write_once() { :; }; set_card_status() { :; }
    SB_GITHUB_READ="$TMP/sbin/super-board-github-read.py"; CONFIG_PATH="$TMP/cfg.json"; RUN_MANIFEST=/dev/null
    INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
    SWEPT_CARDS=""; PROJECT_ITEMS_JSON='{"items":[{"id":"I319","status":"Blocked","labels":["bug"],"content":{"number":319,"assignees":[]}}]}'
    export STUB_PLAN="$1"
    sweep_blocked_cards; sweep_blocked_cards ) >/dev/null 2>&1
}
rm -f "$TMP/log"; run_sweep "$PLAN"
N="$(grep -c '#319.*#377' "$TMP/log" 2>/dev/null)"
[ "$N" = "1" ] && ok "runner: thẻ flag được log đúng 1 lần dù sweep chạy 2 tick" || fail "runner: log count=$N: $(cat "$TMP/log" 2>/dev/null)"

[ "$FAILS" -eq 0 ] && echo "✅ test_blocked_by_unreadable: all passed" || { echo "❌ test_blocked_by_unreadable: $FAILS failed"; exit 1; }
