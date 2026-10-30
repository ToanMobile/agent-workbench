#!/usr/bin/env bash
# Test hồi quy (#686, PR 1, §10.3 của thiết kế v3.1): `gate_rules.py watch` — 5 tín hiệu tắt ngay, mỗi tín hiệu một ca, dùng record
# giả theo schema cố định của §10.2 (<common>/postfix-gate/archive/rules-<R>-<ngày>.jsonl) và lịch sử đêm giả (nightly/history.jsonl).
#   L3    blob test đã duyệt ở commit squash (#PR) của main lệch với approved_blobs; hoặc test đỏ ∈ protected ở đêm;
#   B     record red_reused có exit ≠ 1;
#   CACHE record false_green ⇒ off CACHE --zero;
#   L2    đêm đỏ ngoài tập đỏ nền mà một quyết định applied không chọn; plist mất; không có lượt đêm trong 36 h;
#   L1    đêm đỏ ngoài tập đỏ nền có suite ∈ skipped_suites/skipped_tests của một lần miễn.
# Mỗi ca: --dry-run in kế hoạch (off + PR + thẻ) và không ghi gì. Ca thật: ghi override, idempotent, PR/thẻ chỉ chạy qua lệnh móc.
# Chưa có `watch` trong bin/gate_rules.py thì ĐỎ. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GR="$DEVKIT_DIR/bin/gate_rules.py"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

[ -f "$GR" ] || { echo "✖ không có bin/gate_rules.py: chưa có watcher"; exit 1; }
python3 -B "$GR" watch --help >/dev/null 2>&1 || { echo "✖ gate_rules.py chưa có lệnh watch"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-rules-watch.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd)"
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }
unset DEVKIT_GATE_RULE_L1 DEVKIT_GATE_RULE_L2 DEVKIT_GATE_RULE_L3 DEVKIT_GATE_RULE_B DEVKIT_GATE_RULE_CACHE \
      DEVKIT_SUITE_CACHE_MAX_S DEVKIT_GATE_CACHE_MAX_S SB_BOARD_WORKER DEVKIT_RULES_WATCH_PR_CMD DEVKIT_RULES_WATCH_CARD_CMD DEVKIT_RULES_WATCH_NOW
export DEVKIT_LAUNCH_AGENTS_DIR="$T/LaunchAgents"; mkdir -p "$DEVKIT_LAUNCH_AGENTS_DIR"

# --- repo giả: base (4 ngày trước, toàn off) → bật cả 4 luật + TTL 86400 (3 ngày trước) → commit squash "(#12)" sửa tests/x.sh ----------
NOW="$(python3 -c 'import time; print(int(time.time()))')"
d4=$((NOW - 4 * 86400)); d3=$((NOW - 3 * 86400))
g init -q --bare "$T/origin.git"; g init -q "$T/main"; M="$T/main"
mkdir -p "$M/.agents" "$M/tests"
rj() { printf '{"version": 1, "rules": {"L1": "%s", "L2": "%s", "L3": "%s", "B": "%s"}, "ttl": {"suite_cache_max_s": %s}}\n' "$1" "$1" "$1" "$1" "$2"; }
rj off 21600 > "$M/.agents/gate-rules.json"; echo v0 > "$M/tests/x.sh"
( cd "$M" && g add -A && GIT_AUTHOR_DATE="@$d4 +0000" GIT_COMMITTER_DATE="@$d4 +0000" g commit -q -m base && g remote add origin "$T/origin.git" \
  && g push -q origin main && g remote set-head origin main >/dev/null 2>&1 )
rj on 86400 > "$M/.agents/gate-rules.json"
( cd "$M" && GIT_AUTHOR_DATE="@$d3 +0000" GIT_COMMITTER_DATE="@$d3 +0000" g commit -q -am "bật cờ" && g push -q origin main )
echo v1 > "$M/tests/x.sh"
( cd "$M" && g commit -q -am "sửa test x (#12)" && g push -q origin main )
GOOD_BLOB="$(git -C "$M" rev-parse origin/main:tests/x.sh)"
COMMON="$(cd "$M" && git rev-parse --path-format=absolute --git-common-dir)"
PG="$COMMON/postfix-gate"; ARCH="$PG/archive"; NIGHT="$PG/nightly"; OV="$PG/gate-rules.override.json"; ST="$PG/gate-rules-watch.json"
mkdir -p "$ARCH" "$NIGHT"

# fx: helper dựng record / lịch sử đêm (mốc thời gian tương đối "ago_h" giờ trước)
cat > "$T/fx.py" <<'PY'
import datetime, json, os, sys, time
pg, cmd = sys.argv[1], sys.argv[2]
arch, night = os.path.join(pg, "archive"), os.path.join(pg, "nightly")
now = time.time()
if cmd == "clear":
    for d in (arch, night):
        for f in os.listdir(d):
            os.unlink(os.path.join(d, f))
elif cmd == "hist":   # '[{ago_h, result, red, red_tests}]'
    with open(os.path.join(night, "history.jsonl"), "w", encoding="utf-8") as fh:
        for e in json.loads(sys.argv[3]):
            at = datetime.datetime.fromtimestamp(now - e.pop("ago_h") * 3600).isoformat(timespec="seconds")
            e.setdefault("result", "green"); e.setdefault("red", [])
            fh.write(json.dumps(dict(e, at=at, ref="origin/main", sha="0" * 40, suspect="", card="", log="")) + "\n")
elif cmd == "rec":    # <rule> '{ago_h, kind, decision, pr, detail}'
    rule, r = sys.argv[3], json.loads(sys.argv[4])
    ts = now - r.pop("ago_h", 1) * 3600
    rec = {"ts": ts, "rule": rule, "value": "on", "decision": "applied", "kind": "decision", "caller": "test", "fp": "f", "head": "h",
           "base": "b", "pr": None, "reason": "", "detail": {}}
    rec.update(r)
    day = datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).strftime("%Y%m%d")
    with open(os.path.join(arch, "rules-%s-%s.jsonl" % (rule, day)), "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec) + "\n")
PY
fx() { python3 -B "$T/fx.py" "$PG" "$@"; }
QUIET='[{"ago_h":80,"result":"green"},{"ago_h":10,"result":"green"}]'
# plist giả của lịch đêm: tên nhãn theo slug của gate-full-schedule.sh (tên thư mục + sha1[:8] của đường dẫn vật lý)
PHYS="$(cd "$M" && pwd -P)"; H8="$(printf '%s' "$PHYS" | shasum -a 1 | cut -c1-8)"
SLUG="$(printf '%s' "$(basename "$PHYS")" | LC_ALL=C tr -c 'A-Za-z0-9-' '-')-$H8"
PLIST="$DEVKIT_LAUNCH_AGENTS_DIR/com.toanmobile.devkit.gate-full.$SLUG.plist"
python3 - "$PLIST" "$PHYS" <<'PY'
import plistlib, sys
with open(sys.argv[1], "wb") as f:
    plistlib.dump({"Label": "x", "ProgramArguments": ["/usr/bin/nice", "-n", "10", "python3", "gate_full.py", "run", "--repo", sys.argv[2]]}, f)
PY

# wd [args]: chạy watch trong main, in "R:tín_hiệu" của từng action (một dòng JSON mỗi action), rc ở $T/.rc
wd() {
  local out; out="$(cd "$M" && python3 -B "$GR" watch "$@" 2>"$T/watch.err")"; echo $? > "$T/.rc"
  printf '%s\n' "$out" > "$T/watch.out"
  printf '%s\n' "$out" | python3 -c "
import json,sys
r=[]
for l in sys.stdin:
    l=l.strip()
    if l.startswith('{'):
        d=json.loads(l); r.append('%s:%s' % (d['rule'], d['signal']))
print(' '.join(sorted(r)))"
}
rc() { cat "$T/.rc"; }
reset() { fx clear; fx hist "$QUIET"; rm -f "$OV" "$ST"; }

# 0. không record ⇒ không action
reset
chk "0. lặng (không record, đêm xanh gần đây, plist có) ⇒ không action, exit 0" '[ -z "$(wd --dry-run)" ] && [ "$(rc)" -eq 0 ]' "$(cat "$T/watch.out") $(cat "$T/watch.err")"

# --- L3 ---------------------------------------------------------------------------------------------------------------------------
reset; fx rec L3 '{"pr":12,"detail":{"audited":{"T1":"a"},"used":["tests/x.sh"],"protected":{"tests/x.sh":"bb"},"approved_blobs":{"tests/x.sh":"0000000000000000000000000000000000000000"}}}'
chk "L3a. blob test đã duyệt lệch blob ở commit squash (#12) ⇒ L3:approved_blob_mismatch" '[ "$(wd --dry-run)" = "L3:approved_blob_mismatch" ]' "$(cat "$T/watch.out")"
reset; fx rec L3 "{\"pr\":12,\"detail\":{\"used\":[\"tests/x.sh\"],\"protected\":{},\"approved_blobs\":{\"tests/x.sh\":\"$GOOD_BLOB\"}}}"
chk "L3a'. blob khớp ⇒ không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"
reset; fx rec L3 '{"pr":999,"detail":{"used":["tests/x.sh"],"protected":{},"approved_blobs":{"tests/x.sh":"0000000000000000000000000000000000000000"}}}'
chk "L3a''. chưa thấy commit squash của PR (chưa merge) ⇒ chưa kết luận, không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"
reset; fx rec L3 '{"pr":12,"decision":"declined","detail":{"used":[],"protected":{},"approved_blobs":{"tests/x.sh":"0000"}}}'
chk "L3a'''. quyết định declined/không dùng L3 ⇒ không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"
reset; fx rec L3 '{"ago_h":30,"pr":13,"detail":{"used":["tests/x.sh"],"protected":{"tests/x.sh":"bb"},"approved_blobs":{}}}'
fx hist '[{"ago_h":80,"result":"green"},{"ago_h":10,"result":"red","red":["REG-Z"],"red_tests":["tests/x.sh"]}]'
chk "L3b. test đỏ ∈ protected ở đêm (ngoài tập đỏ nền) ⇒ L3:protected_red" '[ "$(wd --dry-run)" = "L3:protected_red" ]' "$(cat "$T/watch.out")"
fx hist '[{"ago_h":80,"result":"red","red_tests":["tests/x.sh"]},{"ago_h":10,"result":"red","red_tests":["tests/x.sh"]}]'
chk "L3b'. cùng test đã đỏ ở đêm trước ngày bật (tập đỏ nền) ⇒ không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"
fx hist '[{"ago_h":80,"result":"green"},{"ago_h":10,"result":"red","red":["REG-Z"],"red_tests":["tests/other.sh"]}]'
chk "L3b''. test đỏ không ∈ protected ⇒ không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"

# --- B ----------------------------------------------------------------------------------------------------------------------------
reset; fx rec B '{"kind":"red_reused","detail":{"suites":["REG-A"],"keys":["k"],"exit":0}}'
chk "B. red_reused có exit 0 ⇒ B:red_reused_exit" '[ "$(wd --dry-run)" = "B:red_reused_exit" ]' "$(cat "$T/watch.out")"
reset; fx rec B '{"kind":"red_reused","detail":{"suites":["REG-A"],"keys":["k"],"exit":1}}'
chk "B'. red_reused exit 1 ⇒ không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"
reset; fx rec B '{"kind":"red_reused","detail":{"suites":["REG-A"],"keys":["k"]}}'
chk "B''. red_reused thiếu exit ⇒ tắt (đóng)" '[ "$(wd --dry-run)" = "B:red_reused_exit" ]' "$(cat "$T/watch.out")"
reset; fx rec B '{"ago_h":100,"kind":"red_reused","detail":{"exit":0}}'
chk "B'''. record trước ngày bật B ⇒ không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"

# --- CACHE ------------------------------------------------------------------------------------------------------------------------
reset; fx rec CACHE '{"kind":"false_green","detail":{"suite":"REG-A","key":"k","pass_age_s":25000}}'
chk "CACHE. false_green ⇒ CACHE:false_green, bước off dùng --zero" '[ "$(wd --dry-run)" = "CACHE:false_green" ] && grep -q -- "--zero" "$T/watch.out"' "$(cat "$T/watch.out")"
reset; fx rec CACHE '{"kind":"decision","detail":{"suite":"REG-A","key":"k","pass_age_s":10}}'
chk "CACHE'. record decision thường ⇒ không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"

# --- L2 ---------------------------------------------------------------------------------------------------------------------------
reset; fx hist '[{"ago_h":80,"result":"green"},{"ago_h":30,"result":"green"},{"ago_h":10,"result":"red","red":["REG-A"]}]'
fx rec L2 '{"ago_h":20,"detail":{"lowered":["f.py"],"tests":[],"suites":["REG-B"],"smoke":[]}}'
chk "L2a. đêm đỏ REG-A (ngoài nền), quyết định L2 applied trong khoảng không chọn REG-A ⇒ L2:unselected_red" '[ "$(wd --dry-run)" = "L2:unselected_red" ]' "$(cat "$T/watch.out")"
reset; fx hist '[{"ago_h":80,"result":"green"},{"ago_h":30,"result":"green"},{"ago_h":10,"result":"red","red":["REG-A"]}]'
fx rec L2 '{"ago_h":20,"detail":{"lowered":["f.py"],"tests":[],"suites":["REG-A"],"smoke":[]}}'
chk "L2a'. suite đỏ ∈ suites đã chọn ⇒ không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"
fx rec L2 '{"ago_h":15,"detail":{"lowered":["g.py"],"tests":[],"suites":[],"smoke":["REG-A"]}}'
chk "L2a''. suite đỏ ∈ smoke ⇒ không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"
reset; fx hist '[{"ago_h":80,"result":"red","red":["REG-A"]},{"ago_h":30,"result":"green"},{"ago_h":10,"result":"red","red":["REG-A"]}]'
fx rec L2 '{"ago_h":20,"detail":{"lowered":["f.py"],"tests":[],"suites":["REG-B"],"smoke":[]}}'
chk "L2a'''. REG-A đã đỏ ở đêm trước ngày bật (tập đỏ nền) ⇒ không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"
reset; fx hist '[{"ago_h":80,"result":"green"},{"ago_h":30,"result":"green"},{"ago_h":10,"result":"red","red":["REG-A"]}]'
fx rec L2 '{"ago_h":40,"detail":{"lowered":["f.py"],"tests":[],"suites":["REG-B"],"smoke":[]}}'
chk "L2a''''. quyết định L2 nằm ngoài khoảng giữa hai lượt đêm ⇒ không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"
reset; mv "$PLIST" "$PLIST.bak"
chk "L2b. plist lịch đêm mất ⇒ L2:plist_missing" '[ "$(wd --dry-run)" = "L2:plist_missing" ]' "$(cat "$T/watch.out")"
mv "$PLIST.bak" "$PLIST"
reset; fx hist '[{"ago_h":80,"result":"green"},{"ago_h":40,"result":"green"}]'
chk "L2c. không có lượt đêm trong 36 h ⇒ L2:no_night_run" '[ "$(wd --dry-run)" = "L2:no_night_run" ]' "$(cat "$T/watch.out")"
reset; fx hist '[]'
chk "L2c'. chưa từng có lượt đêm (đã bật > 36 h) ⇒ L2:no_night_run" '[ "$(wd --dry-run)" = "L2:no_night_run" ]' "$(cat "$T/watch.out")"

# --- L1 ---------------------------------------------------------------------------------------------------------------------------
reset; fx hist '[{"ago_h":80,"result":"green"},{"ago_h":30,"result":"green"},{"ago_h":10,"result":"red","red":["REG-S"]}]'
fx rec L1 '{"ago_h":20,"detail":{"old":"o","new":"n","diff":["a"],"closure_hits":[],"skipped_tests":[],"skipped_suites":["REG-S"]}}'
chk "L1a. đêm đỏ REG-S (ngoài nền), một lần miễn skipped_suites có REG-S ⇒ L1:skipped_red" '[ "$(wd --dry-run)" = "L1:skipped_red" ]' "$(cat "$T/watch.out")"
reset; fx hist '[{"ago_h":80,"result":"green"},{"ago_h":30,"result":"green"},{"ago_h":10,"result":"red","red":["REG-S"],"red_tests":["tests/y.sh"]}]'
fx rec L1 '{"ago_h":20,"detail":{"old":"o","new":"n","diff":["a"],"closure_hits":[],"skipped_tests":["tests/y.sh"],"skipped_suites":[]}}'
chk "L1b. test đỏ ∈ skipped_tests ⇒ L1:skipped_red" '[ "$(wd --dry-run)" = "L1:skipped_red" ]' "$(cat "$T/watch.out")"
reset; fx hist '[{"ago_h":80,"result":"green"},{"ago_h":30,"result":"green"},{"ago_h":10,"result":"red","red":["REG-S"]}]'
fx rec L1 '{"ago_h":20,"detail":{"old":"o","new":"n","diff":["a"],"closure_hits":[],"skipped_tests":[],"skipped_suites":["REG-OTHER"]}}'
chk "L1c. suite đỏ không ∈ skipped_* ⇒ không action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"

# --- kế hoạch dry-run: off + PR + thẻ; không ghi gì ---------------------------------------------------------------------------------
reset; fx rec B '{"kind":"red_reused","detail":{"exit":0}}'
wd --dry-run >/dev/null
chk "dry. action có 3 bước off / pr / card, dry_run=true" 'python3 - "$T/watch.out" <<PY
import json,sys
d=json.loads([l for l in open(sys.argv[1]) if l.startswith("{")][0])
s={x["step"]:x for x in d["steps"]}
assert d["dry_run"] is True and d["rule"]=="B" and set(s)=={"off","pr","card"}, d
assert s["pr"]["branch"].startswith("gate-rules-off-B-") and "tắt B" in s["pr"]["title"] and "tắt B" in s["card"]["title"], d
PY' "$(cat "$T/watch.out")"
chk "dry. không ghi override, không ghi state" '[ ! -e "$OV" ] && [ ! -e "$ST" ]'
touch -t 202001010000 "$ARCH/rules-B-20200101.jsonl"; wd --dry-run >/dev/null
chk "dry. không xoá file archive cũ" '[ -e "$ARCH/rules-B-20200101.jsonl" ]'

# --- chạy thật: ghi override, idempotent, PR/thẻ qua lệnh móc, dọn archive > 30 ngày ------------------------------------------------
HOOK="$T/hook.sh"; printf '#!/bin/sh\necho "$@" >> "%s/hook.calls"\n' "$T" > "$HOOK"; chmod +x "$HOOK"
wd >/dev/null
chk "real. chưa đặt lệnh móc: ghi override B off, exit 0" '[ "$(rc)" -eq 0 ] && python3 -c "
import json,sys; d=json.load(open(sys.argv[1])); r=d[\"rules\"][\"B\"]; assert r[\"value\"]==\"off\" and r[\"reason\"] and r[\"at\"]" "$OV"' "$(cat "$T/watch.err")"
chk "real. get B = off sau khi watch tắt" '[ "$(cd "$M" && python3 -B "$GR" get B)" = off ]'
chk "real. get L3 vẫn on (chỉ tắt luật có tín hiệu)" '[ "$(cd "$M" && python3 -B "$GR" get L3)" = on ]'
chk "real. không có hook ⇒ PR/thẻ không chạy" '[ ! -e "$T/hook.calls" ]'
chk "real. file archive cũ hơn 30 ngày bị xoá" '[ ! -e "$ARCH/rules-B-20200101.jsonl" ]'
chk "real. state ghi enabled_at" 'python3 -c "
import json,sys; d=json.load(open(sys.argv[1])); assert d[\"enabled_at\"][\"B\"] > 0" "$ST"'
chk "real. lần hai: B đã off ⇒ không action nữa (idempotent)" '[ -z "$(wd)" ] && [ "$(rc)" -eq 0 ]' "$(cat "$T/watch.out")"
rm -f "$OV"; reset; fx rec B '{"kind":"red_reused","detail":{"exit":0}}'
DEVKIT_RULES_WATCH_PR_CMD="$HOOK pr" DEVKIT_RULES_WATCH_CARD_CMD="$HOOK card" wd >/dev/null
chk "real. đặt lệnh móc ⇒ PR và thẻ mỗi bên gọi đúng một lần, có tên luật" '[ "$(grep -c "^pr " "$T/hook.calls")" = 1 ] && [ "$(grep -c "^card " "$T/hook.calls")" = 1 ] && grep "^pr " "$T/hook.calls" | grep -q "gate-rules-off-B-"' "$(cat "$T/hook.calls" 2>/dev/null)"
rm -f "$OV"

# --- luật off ⇒ bỏ qua; worker ⇒ exit 3 -------------------------------------------------------------------------------------------
reset; printf '{"rules": {"B": {"value": "off", "reason": "t", "at": 1, "by": "t"}}}\n' > "$OV"; fx rec B '{"kind":"red_reused","detail":{"exit":0}}'
chk "off. B đã off (override) ⇒ record B không tạo action" '[ -z "$(wd --dry-run)" ]' "$(cat "$T/watch.out")"
rm -f "$OV"
reset; fx rec B '{"kind":"red_reused","detail":{"exit":0}}'
SB_BOARD_WORKER=1 wd --dry-run >/dev/null
chk "worker. SB_BOARD_WORKER=1 ⇒ exit 3, không ghi" '[ "$(rc)" -eq 3 ] && [ ! -e "$OV" ]'
# nhiều luật cùng lúc: mỗi luật một action
reset; fx rec B '{"kind":"red_reused","detail":{"exit":0}}'; fx rec CACHE '{"kind":"false_green","detail":{"suite":"S","key":"k","pass_age_s":1}}'
chk "multi. B và CACHE cùng có tín hiệu ⇒ hai action" '[ "$(wd --dry-run)" = "B:red_reused_exit CACHE:false_green" ]' "$(cat "$T/watch.out")"
# lỗi đầu vào: record rác, history rác ⇒ không raise
reset; echo 'rác' >> "$ARCH/rules-B-$(date -u +%Y%m%d).jsonl"; echo 'rác' >> "$NIGHT/history.jsonl"
chk "junk. dòng archive / history rác ⇒ bỏ qua, exit 0, không traceback" '[ -z "$(wd --dry-run)" ] && [ "$(rc)" -eq 0 ] && ! grep -q Traceback "$T/watch.err"' "$(cat "$T/watch.err")"

echo
if [ "$fails" -eq 0 ]; then echo "test_gate_rules_watch: PASS"; exit 0; else echo "test_gate_rules_watch: FAIL ($fails)"; exit 1; fi
