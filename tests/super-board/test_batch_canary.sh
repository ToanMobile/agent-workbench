#!/usr/bin/env bash
# Test hồi quy cho universal-agent-devkit/bin/batch_canary.py (canary production của merge theo đợt, Pha 2 lớp 3),
# dòng WARN của agent-health.py và bước canary của scripts/governance/nightly.py.
# Chạy offline: gh giả, runs.jsonl giả, ledger incident trong thư mục tạm. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$ROOT/universal-agent-devkit"
CANARY="$KIT/bin/batch_canary.py"
. "$KIT/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
has() { printf '%s' "$1" | grep -qF -- "$2"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-canary-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
NOW=$(python3 -c 'import time; print(int(time.time()))')

# gen <file> <merge> <train> <other> <epoch>: runs.jsonl giả, mỗi lượt một dòng
gen_runs() {
  python3 - "$@" <<'PY'
import json, sys
path, m, t, o, ep = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
with open(path, "a", encoding="utf-8") as f:
    for i in range(m):
        f.write(json.dumps({"epoch": ep + i, "project": f".merge-scratch-{i:06d}", "mode": "full"}) + "\n")
    for i in range(t):
        f.write(json.dumps({"epoch": ep + i, "project": f".train-scratch-{i:06d}", "mode": "full"}) + "\n")
    for i in range(o):
        f.write(json.dumps({"epoch": ep + i, "project": "agent-workbench", "mode": "full"}) + "\n")
PY
}
# gen_merged <file> <n> <epoch>: danh sách PR merged dạng `gh pr list --json number,mergedAt`
gen_merged() {
  python3 - "$@" <<'PY'
import datetime as dt, json, sys
path, n, ep = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
iso = lambda e: dt.datetime.fromtimestamp(e, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump([{"number": 100 + i, "mergedAt": iso(ep + i)} for i in range(n)], open(path, "w", encoding="utf-8"))
PY
}
SINCE=$(python3 -c "import datetime as dt; print(dt.datetime.fromtimestamp($NOW - 7200, dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")
EP=$((NOW - 3600))

# ── 1. Hôm nay: 73 PR merged, 48 lượt merge gate, 0 train → ĐỎ exit 1
gen_runs "$TMP/r1.jsonl" 48 0 30 "$EP"; gen_merged "$TMP/m1.json" 73 "$EP"
out=$(python3 "$CANARY" --runs "$TMP/r1.jsonl" --since "$SINCE" --merged-json "$TMP/m1.json" 2>&1); rc=$?
if [ "$rc" = 1 ] && has "$out" "merged PRs=73 merge-gate verifies=48 train verifies=0" && has "$out" "RED:" \
   && has "$out" "no train verify"; then ok "73 PR / 48 merge / 0 train → ĐỎ exit 1"
else fail "73/48/0 phải ĐỎ exit 1 (rc=$rc): $out"; fi

# ── 2. 6 PR / 1 train / 0 merge → XANH exit 0
gen_runs "$TMP/r2.jsonl" 0 1 5 "$EP"; gen_merged "$TMP/m2.json" 6 "$EP"
out=$(python3 "$CANARY" --runs "$TMP/r2.jsonl" --since "$SINCE" --merged-json "$TMP/m2.json" 2>&1); rc=$?
if [ "$rc" = 0 ] && has "$out" "merged PRs=6 merge-gate verifies=0 train verifies=1 verifies/PR=0.17" && has "$out" "GREEN"; then
  ok "6 PR / 1 train / 0 merge → XANH exit 0"
else fail "6/1/0 phải XANH exit 0 (rc=$rc): $out"; fi

# ── 3. Tỉ lệ: 4 PR, 1 train + 2 merge = 0.75 > 0.5 → ĐỎ; --max-ratio 1 → XANH
gen_runs "$TMP/r3.jsonl" 2 1 0 "$EP"; gen_merged "$TMP/m3.json" 4 "$EP"
out=$(python3 "$CANARY" --runs "$TMP/r3.jsonl" --since "$SINCE" --merged-json "$TMP/m3.json" 2>&1); rc=$?
out2=$(python3 "$CANARY" --runs "$TMP/r3.jsonl" --since "$SINCE" --merged-json "$TMP/m3.json" --max-ratio 1 2>&1); rc2=$?
if [ "$rc" = 1 ] && has "$out" "verifies/PR 0.75 > 0.5" && [ "$rc2" = 0 ] && has "$out2" "GREEN"; then
  ok "verifies/PR 0.75 > 0.5 → ĐỎ; --max-ratio 1 → XANH"
else fail "tỉ lệ (rc=$rc rc2=$rc2): $out | $out2"; fi

# ── 4. enabled_at trong config lọc lượt cũ (trước lúc bật): 40 merge cũ + 30 PR cũ không tính
ENA=$((NOW - 1800))
gen_runs "$TMP/r4.jsonl" 40 0 0 $((ENA - 86400)); gen_runs "$TMP/r4.jsonl" 0 1 0 $((ENA + 10))
gen_merged "$TMP/m4.json" 30 $((ENA - 86400)); gen_merged "$TMP/m4b.json" 3 $((ENA + 10))
python3 - "$TMP/m4.json" "$TMP/m4b.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1])) + [dict(x, number=x["number"] + 1000) for x in json.load(open(sys.argv[2]))]
json.dump(a, open(sys.argv[1], "w"))
PY
printf '{"merge_queue":{"enabled":true,"enabled_at":%s,"batch_max":6,"max_wait_min":60}}\n' "$ENA" > "$TMP/cfg_on.json"
printf '{"merge_queue":{"enabled":false,"enabled_at":null,"batch_max":6,"max_wait_min":60}}\n' > "$TMP/cfg_off.json"
out=$(python3 "$CANARY" --runs "$TMP/r4.jsonl" --config "$TMP/cfg_on.json" --merged-json "$TMP/m4.json" 2>&1); rc=$?
OLD_SINCE=$(python3 -c "import datetime as dt; print(dt.datetime.fromtimestamp($ENA - 90000, dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")
old=$(python3 "$CANARY" --runs "$TMP/r4.jsonl" --since "$OLD_SINCE" --merged-json "$TMP/m4.json" 2>&1); rco=$?
off=$(python3 "$CANARY" --runs "$TMP/r4.jsonl" --config "$TMP/cfg_off.json" --merged-json "$TMP/m4.json" 2>&1); rcf=$?
if [ "$rc" = 0 ] && has "$out" "merged PRs=3 merge-gate verifies=0 train verifies=1" && [ "$rco" = 1 ] \
   && [ "$rcf" = 0 ] && has "$off" "canary off"; then
  ok "enabled_at lọc lượt cũ; config tắt / enabled_at null → canary off exit 0"
else fail "enabled_at (rc=$rc rco=$rco rcf=$rcf): $out | $old | $off"; fi
# enabled_at dạng ISO cũng nhận
ISO_ENA=$(python3 -c "import datetime as dt; print(dt.datetime.fromtimestamp($ENA, dt.timezone.utc).isoformat())")
printf '{"merge_queue":{"enabled":true,"enabled_at":"%s"}}\n' "$ISO_ENA" > "$TMP/cfg_iso.json"
out=$(python3 "$CANARY" --runs "$TMP/r4.jsonl" --config "$TMP/cfg_iso.json" --merged-json "$TMP/m4.json" 2>&1); rc=$?
if [ "$rc" = 0 ] && has "$out" "merged PRs=3 merge-gate verifies=0 train verifies=1"; then ok "enabled_at ISO được nhận"
else fail "enabled_at ISO (rc=$rc): $out"; fi

# ── 5. Dòng JSON hỏng bị bỏ qua, không traceback
gen_runs "$TMP/r5.jsonl" 3 0 0 "$EP"
printf '{broken\n[]\n"str"\n{"epoch":"x","project":".merge-scratch-zz"}\n{"project":".train-scratch-noepoch"}\n\n' >> "$TMP/r5.jsonl"
gen_merged "$TMP/m5.json" 3 "$EP"
out=$(python3 "$CANARY" --runs "$TMP/r5.jsonl" --since "$SINCE" --merged-json "$TMP/m5.json" 2>&1); rc=$?
if [ "$rc" = 1 ] && has "$out" "merge-gate verifies=3 train verifies=0" && ! has "$out" "Traceback"; then
  ok "dòng JSON hỏng / không phải object / epoch sai bị bỏ qua"
else fail "JSON hỏng (rc=$rc): $out"; fi

# ── 6. Lỗi đầu vào → exit 2 kèm lý do (không traceback)
bad_in() {   # <tên> <chuỗi phải có> <args...>
  local name="$1" want="$2"; shift 2
  local o r; o=$(python3 "$CANARY" "$@" 2>&1); r=$?
  if [ "$r" = 2 ] && has "$o" "batch_canary: error:" && has "$o" "$want" && ! has "$o" "Traceback"; then ok "exit 2: $name"
  else fail "exit 2 $name (rc=$r): $o"; fi
}
printf '{"not":"a list"}' > "$TMP/bad_list.json"; printf '[{"number":1}]' > "$TMP/bad_item.json"; printf '[oops' > "$TMP/bad_json.json"
bad_in "runs không có" "runs" --runs "$TMP/none.jsonl" --since "$SINCE" --merged-json "$TMP/m2.json"
bad_in "--since sai" "--since" --runs "$TMP/r2.jsonl" --since "hôm qua" --merged-json "$TMP/m2.json"
bad_in "thiếu --since và --config" "--since" --runs "$TMP/r2.jsonl" --merged-json "$TMP/m2.json"
bad_in "merged-json không phải list" "merged" --runs "$TMP/r2.jsonl" --since "$SINCE" --merged-json "$TMP/bad_list.json"
bad_in "merged-json thiếu mergedAt" "mergedAt" --runs "$TMP/r2.jsonl" --since "$SINCE" --merged-json "$TMP/bad_item.json"
bad_in "merged-json hỏng" "merged" --runs "$TMP/r2.jsonl" --since "$SINCE" --merged-json "$TMP/bad_json.json"
bad_in "config hỏng" "config" --runs "$TMP/r2.jsonl" --config "$TMP/bad_json.json" --merged-json "$TMP/m2.json"

# ── 7. Không --merged-json → gọi gh; gh lỗi → exit 2; gh trả JSON → dùng
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/gh.calls"
if [ -e "$FAKE_DIR/gh_fail" ]; then echo "HTTP 502" >&2; exit 1; fi
case " $* " in
  *" pr list "*"--state merged"*"number,mergedAt"*) cat "$FAKE_DIR/m1.json" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
out=$(PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" python3 "$CANARY" --runs "$TMP/r1.jsonl" --since "$SINCE" 2>&1); rc=$?
if [ "$rc" = 1 ] && has "$out" "merged PRs=73 merge-gate verifies=48" && grep -q -- "--limit 200" "$TMP/gh.calls"; then
  ok "không --merged-json → gh pr list --state merged --limit 200"
else fail "gh thật (rc=$rc): $out"; fi
touch "$TMP/gh_fail"
out=$(PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" python3 "$CANARY" --runs "$TMP/r1.jsonl" --since "$SINCE" 2>&1); rc=$?
if [ "$rc" = 2 ] && has "$out" "gh" && has "$out" "HTTP 502"; then ok "gh lỗi → exit 2 kèm lý do"
else fail "gh lỗi phải exit 2 (rc=$rc): $out"; fi
rm -f "$TMP/gh_fail"

# ── 8. agent-health: config bật merge_queue + canary 24 h đỏ → một dòng WARN, exit KHÔNG đổi
T="$TMP/target"; mkdir -p "$T"; git init -q -b main "$T"
mkdir -p "$T/.git/postfix-gate"
gen_runs "$T/.git/postfix-gate/runs.jsonl" 3 0 2 $((NOW - 600))
HEALTH="$KIT/bin/agent-health.py"
h1=$(python3 "$HEALTH" -t "$T" 2>&1); hr1=$?
mkdir -p "$T/.claude/super-board/configs"
printf '{"merge_queue":{"enabled":true,"enabled_at":%s,"batch_max":6,"max_wait_min":60}}\n' $((NOW - 3600)) \
  > "$T/.claude/super-board/configs/t.json"
h2=$(PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" python3 "$HEALTH" -t "$T" 2>&1); hr2=$?
score() { printf '%s' "$1" | grep -E 'hạng mục đã đo|checks measured' | sed 's/\x1b\[[0-9;]*m//g'; }
rm -f "$TMP/gh.calls"
h3=$(PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" python3 "$HEALTH" -t "$T" 2>&1); hr3=$?
if [ "$hr1" = "$hr2" ] && ! has "$h1" "batch canary" && has "$h2" "batch canary" && has "$h2" "merge-gate verifies=3 train verifies=0" \
   && [ "$(score "$h1")" = "$(score "$h2")" ] && [ ! -e "$TMP/gh.calls" ] && ! has "$h2" "Traceback"; then
  ok "agent-health: WARN batch canary khi đỏ, exit ($hr1) và điểm không đổi, không gọi gh"
else fail "agent-health (hr1=$hr1 hr2=$hr2): $(score "$h1") | $(score "$h2") | $(printf '%s' "$h2" | grep -i canary)"; fi
# canary xanh (có train) → không WARN
gen_runs "$T/.git/postfix-gate/runs.jsonl" 0 1 0 $((NOW - 300))
h4=$(python3 "$HEALTH" -t "$T" 2>&1); hr4=$?
if [ "$hr4" = "$hr1" ] && ! has "$h4" "batch canary"; then ok "agent-health: canary xanh → không WARN"
else fail "agent-health xanh (hr4=$hr4): $(printf '%s' "$h4" | grep -i canary)"; fi

# ── 9. nightly: canary đỏ → đúng MỘT thẻ incident theo chữ ký, lần sau không tạo thêm; xanh / tắt → không thẻ
# clean_git_env.sh đặt DEVKIT_INCIDENT=0 (không thẻ thật); ca này bật lại với ledger tạm và gh / create_card giả.
export DEVKIT_INCIDENT_HOME="$TMP/incident"
N="$TMP/nproj"; mkdir -p "$N/.claude/super-board/configs"; git init -q -b main "$N"; mkdir -p "$N/.git/postfix-gate"
gen_runs "$N/.git/postfix-gate/runs.jsonl" 5 0 0 $((NOW - 600))
printf '{"merge_queue":{"enabled":true,"enabled_at":%s}}\n' $((NOW - 3600)) > "$N/.claude/super-board/configs/n.json"
nout=$(DEVKIT_INCIDENT=1 python3 - "$KIT" "$N" "$TMP/m1.json" <<'PY' 2>&1
import json, sys
from pathlib import Path
kit, proj, merged = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
sys.path.insert(0, f"{kit}/scripts/governance"); sys.path.insert(0, f"{kit}/bin")
import nightly, devkit_incident as di, batch_canary as bc
calls = []
data = json.load(open(merged))
bc.gh_merged = lambda cwd=None: data
di.find_open_issue = lambda fp: None
di.issue_closed_at = lambda n: None
di.create_card = lambda fp, inc: calls.append((fp, inc["rule"], inc["title"])) or 501
def gh_forbidden(args):
    raise AssertionError(f"gh called: {args}")
di.gh = gh_forbidden
m1 = nightly.canary_project(proj)
m2 = nightly.canary_project(proj)
print("CARDS", len(calls), calls[0][1] if calls else "-")
print("MSG1", m1); print("MSG2", m2)
led = json.load(open(Path(di.env_home()) / "ledger.json"))
inc = [i for i in led["incidents"].values() if i["rule"] == "batch-canary"]
print("LEDGER", len(inc), inc[0]["issue"] if inc else "-", inc[0]["count"] if inc else "-")
print("EVIDENCE", json.dumps(inc[0]["evidence"]) if inc else "-")
# xanh: thêm train → không thẻ mới
with open(proj / ".git/postfix-gate/runs.jsonl", "a") as f:
    import time
    for i in range(40):
        f.write(json.dumps({"epoch": int(time.time()) - 60, "project": f".train-scratch-{i}"}) + "\n")
m3 = nightly.canary_project(proj)
print("MSG3", m3); print("CARDS3", len(calls))
PY
); nrc=$?
if [ "$nrc" = 0 ] && has "$nout" "CARDS 1 batch-canary" && has "$nout" "LEDGER 1 501 2" && has "$nout" "CARDS3 1" \
   && has "$nout" "MSG1" && has "$nout" "RED" && ! has "$(printf '%s' "$nout" | grep EVIDENCE)" "$N"; then
  ok "nightly: canary đỏ → 1 thẻ incident chống trùng, lần 2 chỉ đếm, xanh không tạo thẻ, bằng chứng không lộ đường dẫn"
else fail "nightly canary (rc=$nrc): $nout"; fi
# config không bật → nightly không làm gì
rm -f "$N/.claude/super-board/configs/n.json"
nout=$(python3 -c "
import sys; sys.path.insert(0, '$KIT/scripts/governance'); sys.path.insert(0, '$KIT/bin')
import nightly; print('MSG', nightly.canary_project(__import__('pathlib').Path('$N')))" 2>&1); nrc=$?
if [ "$nrc" = 0 ] && has "$nout" "MSG None"; then ok "nightly: merge_queue không bật → bỏ qua"
else fail "nightly tắt (rc=$nrc): $nout"; fi

if [ "$FAILS" -eq 0 ]; then echo "PASS test_batch_canary"; exit 0; fi
echo "FAIL test_batch_canary ($FAILS)"; exit 1
