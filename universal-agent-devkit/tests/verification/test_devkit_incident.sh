#!/usr/bin/env bash
# Test: devkit_incident.py (scripts/governance) — lỗi DO DEVKIT khi board/workflow chạy ở các repo app tự thành thẻ 🐛
# trên ToanMobile/agent-workbench (Project #1). Người dùng 24/10: "khi 5 repo kia chạy mà board, workflow có lỗi gì do
# devkit thì tạo task trên devkit cho tôi". Script board ở repo app là bản copy, kit là symlink: bộ gom đọc log mà board
# đã ghi (manifest runner, watchdog log, audit-gate log), phân loại, chống trùng theo chữ ký, rồi gọi create_task.py.
# gh giả (đầu PATH) ghi mọi lệnh vào calls.jsonl. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DI="$DEVKIT_DIR/scripts/governance/devkit_incident.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/bin" "$TMP/home"
export FAKE_LOG="$TMP/calls.jsonl" FAKE_N="$TMP/n.txt"
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"gh": a}, ensure_ascii=False) + "\n")
if os.environ.get("FAKE_FAIL"):
    sys.stderr.write("fake gh: network down\n"); sys.exit(1)
if a[:2] == ["issue", "create"]:
    n = int(open(os.environ["FAKE_N"]).read()) + 1 if os.path.exists(os.environ["FAKE_N"]) else 500
    open(os.environ["FAKE_N"], "w").write(str(n))
    print("https://github.com/ToanMobile/agent-workbench/issues/%d" % n); sys.exit(0)
if a[:2] == ["project", "item-add"]:
    print(json.dumps({"id": "PVTI_1"})); sys.exit(0)
if a[:2] == ["project", "item-list"]:   # Backlog có sẵn một thẻ bug gom được: thiếu --new-card thì sự cố bị gom vào #7
    print(json.dumps({"items": [{"status": "Backlog", "labels": ["bug"], "content": {
        "type": "Issue", "repository": "ToanMobile/agent-workbench", "number": 7, "title": "🐛 [bug] khác: việc khác",
        "body": "## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Risk\n🟡 Medium\n\n## Blocked by\n- None.\n"}}]})); sys.exit(0)
if a[:2] == ["issue", "list"]:   # FAKE_OPEN: board đã có thẻ mở mang đúng marker được tìm
    term = a[a.index("--search") + 1]
    print(json.dumps([{"number": 42, "body": "## Problem\nmã `%s`" % term}] if os.environ.get("FAKE_OPEN") else [])); sys.exit(0)
if a[:2] in (["project", "item-edit"], ["label", "create"], ["issue", "comment"], ["issue", "edit"]):
    sys.exit(0)
if a[:2] == ["issue", "view"]:
    closed = a[2] == os.environ.get("FAKE_CLOSED")
    print(json.dumps({"state": "CLOSED" if closed else "OPEN", "body": "",
                      "closedAt": os.environ.get("FAKE_CLOSED_AT", "2000-01-01T00:00:00Z") if closed else None})); sys.exit(0)
sys.stderr.write("fake gh: unexpected %r\n" % (a,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export DEVKIT_INCIDENT_HOME="$TMP/home" DEVKIT_INCIDENT_MIN_INTERVAL_S=0 DEVKIT_INCIDENT_STATE_CHECK_S=0
unset DEVKIT_INCIDENT FAKE_FAIL 2>/dev/null || true

mkrepo() {   # mkrepo <name>: một repo app giả với ba nguồn log của board
  local r="$TMP/$1"
  mkdir -p "$r/docs/super-board/runs" "$r/.claude/super-board/runner" "$r/.claude/audit-gate"
  printf '[07:00:00] tick — Ready=0\n[07:00:01] ⚠ self-reload: cannot create worktree OLD-ALREADY-FIXED\n' > "$r/docs/super-board/runs/2026-10-24-$1.md"
  : > "$r/.claude/super-board/runner/$1.watchdog.log"
  : > "$r/.claude/audit-gate/proof_gate.log"
  echo "$r"
}
A="$(mkrepo OfficeReader)"; B="$(mkrepo GeelyEx2)"
export DEVKIT_INCIDENT_REPOS="$A:$B"
MA="$A/docs/super-board/runs/2026-10-24-OfficeReader.md"; MB="$B/docs/super-board/runs/2026-10-24-GeelyEx2.md"

scan() { python3 "$DI" scan >"$TMP/out.txt" 2>&1; echo $?; }
creates() { local c; c=$(grep -c '"issue", "create"' "$FAKE_LOG" 2>/dev/null); echo "${c:-0}"; }
: > "$FAKE_LOG"

# 1. Lần đầu thấy file: không backfill lỗi cũ (đã sửa từ lâu).
rc=$(scan)
[ "$rc" = 0 ] && [ "$(creates)" = 0 ] && ok "lần đầu: không backfill, exit 0" || { fail "lần đầu backfill (rc=$rc, create=$(creates))"; cat "$TMP/out.txt"; }

# 2. Một lỗi do kit mới ở repo app + nhiễu → đúng 1 thẻ trên board DevKit.
cat >> "$MA" <<'EOF'
[10:00:00] tick — Ready=1 Building=0
[10:00:01] build workers 1/10: load 71.6 >= 36: holding
[10:00:02] ⚠ self-reload: cannot create worktree .claude/worktrees/self-reload-50323-1792858640: trees/dropped-card-sweep — worktree khác đang giữ
[10:00:03] 🛑 stop marker .claude/super-board/runner/officereader.stopped — board stopped by the user; runner exits
EOF
rc=$(scan)
if [ "$rc" = 0 ] && [ "$(creates)" = 1 ]; then ok "lỗi kit → 1 thẻ"; else fail "lỗi kit: rc=$rc create=$(creates)"; cat "$TMP/out.txt"; fi
python3 - "$FAKE_LOG" <<'PY' && ok "thẻ ở ToanMobile/agent-workbench, có marker kitbug + tên repo nguồn" || fail "thẻ sai repo/thiếu marker"
import json, sys
c = [json.loads(l)["gh"] for l in open(sys.argv[1]) if '"create"' in l][0]
body = c[c.index("--body") + 1]
assert c[c.index("--repo") + 1] == "ToanMobile/agent-workbench", c
assert "kitbug" in body and "OfficeReader" in body and "self-reload" in body, body
assert c[c.index("--label") + 1] == "bug", c
assert "/Volumes" not in body and "/private" not in body, body   # repo đích PUBLIC: không đường dẫn máy
PY

# 3. Cùng lỗi (số khác) ở repo thứ hai → không thẻ mới.
echo '[11:00:00] ⚠ self-reload: cannot create worktree .claude/worktrees/self-reload-777-1792999999: trees/push-agent-workload — worktree khác đang giữ' >> "$MB"
rc=$(scan)
[ "$rc" = 0 ] && [ "$(creates)" = 1 ] && ok "cùng chữ ký ở repo khác → không thẻ mới" || fail "trùng chữ ký tạo thẻ mới: create=$(creates)"

# 4. Chỉ có nhiễu → 0 thẻ.
cat >> "$MB" <<'EOF'
[11:01:00] ⚠ self-reload: git fetch origin main failed; retrying next check
[11:01:01] error connecting to api.github.com
[11:01:02] ⚠ block-rate alert: 3/5 (60%)
[11:01:03] ⚠ sleep 30s killed by signal 15 — runner keeps going; stop a board only with super-board-stop.sh
[11:01:04] ⚠ worker of #9 (lane qa) ended 30s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: SessionEnd hook [tuios agent-hook] failed: tuios: command not found
EOF
rc=$(scan)
[ "$(creates)" = 1 ] && ok "nhiễu (mạng, block-rate, sleep) → không thẻ" || fail "nhiễu tạo thẻ: create=$(creates)"

# 5. gh hỏng: giữ trong spool, exit 0; gh lành lại → lần scan sau tạo thẻ.
printf 'Traceback (most recent call last):\n  File "/x/.agents/devkit/hooks/proof_gate.py", line 88, in main\n    x = d["k"]\nKeyError: '"'"'k'"'"'\n' >> "$A/.claude/audit-gate/proof_gate.log"
rc=$(FAKE_FAIL=1 scan)
[ "$rc" = 0 ] && [ "$(creates)" = 1 ] && ok "gh lỗi: exit 0, chưa có thẻ" || fail "gh lỗi: rc=$rc"
grep -q 'KeyError' "$TMP/home/ledger.json" && ok "gh lỗi: sự cố còn trong spool" || fail "gh lỗi: mất sự cố"
rc=$(scan)
[ "$(creates)" = 2 ] && ok "gh lành lại → Traceback hook thành thẻ" || { fail "spool không flush: create=$(creates)"; cat "$TMP/out.txt"; }

# 6. Worker chết sớm: bộ đếm có cửa sổ của runner. Lần 1 trong 10 phút (worker xong nhanh hợp lệ) → 0, dù lặp ở nhiều thẻ;
#    lần 2 (runner ngắt thẻ) → 1 thẻ. Chữ tự do sau "last log line:" (việc trong repo private) không lên issue public.
d='⚠ worker of #11 (lane build) ended 91s after dispatch (a crash or a very quick exit) — early end 1 of this lane in 600s; last log line: BÍ MẬT APP private'
printf '[12:00:00] %s\n[12:01:00] %s\n[12:01:30] %s\n' "$d" "${d/\#11/\#12}" "${d/\#11/\#14}" >> "$MA"
scan >/dev/null
[ "$(creates)" = 2 ] && ok "chết sớm lần 1 trong cửa sổ (3 thẻ) → chưa thẻ" || fail "chết sớm lần 1 tạo thẻ: create=$(creates)"
printf '[12:02:00] %s\n' "${d/early end 1/early end 2}" >> "$MB"
scan >/dev/null
[ "$(creates)" = 3 ] && ok "chết sớm lần 2 trong cửa sổ → 1 thẻ" || fail "chết sớm đủ ngưỡng không tạo thẻ: create=$(creates)"
grep -q 'BÍ MẬT APP' "$FAKE_LOG" && fail "chữ sau 'last log line:' lọt lên issue" || ok "chữ sau 'last log line:' bị bỏ"

# 7. Watchdog bỏ cuộc → thẻ; DEVKIT_INCIDENT=0 → không làm gì.
echo '[2026-10-24 13:00:00] runner died 5 times in a row — gave up (crash loop): read its log, then start the board explicitly' >> "$A/.claude/super-board/runner/OfficeReader.watchdog.log"
DEVKIT_INCIDENT=0 python3 "$DI" scan >/dev/null 2>&1
[ "$(creates)" = 3 ] && ok "DEVKIT_INCIDENT=0 → tắt" || fail "công tắc tắt không có tác dụng"
scan >/dev/null
[ "$(creates)" = 4 ] && ok "watchdog gave up → thẻ" || fail "watchdog gave up không thành thẻ: create=$(creates)"

# 8. Board đã có thẻ MỞ mang marker (vd. thẻ gom từ máy khác, ledger mất): nhận thẻ đó, không tạo thẻ mới.
echo '[14:00:00] ⚠ self-reload: origin/main moved during reload' >> "$MA"
FAKE_OPEN=1 scan >/dev/null
[ "$(creates)" = 4 ] && grep -q '"issue": 42' "$TMP/home/ledger.json" && ok "marker có sẵn trên board → nhận thẻ #42" \
  || fail "marker có sẵn mà vẫn tạo thẻ: create=$(creates)"

# 9. Thẻ đó đã ĐÓNG (đã sửa) mà lỗi gặp lại → hồi quy: thẻ mới, không comment vào thẻ đóng.
echo '[14:10:00] ⚠ self-reload: origin/main moved during reload' >> "$MB"
FAKE_CLOSED=42 scan >/dev/null
[ "$(creates)" = 5 ] && ok "thẻ đã đóng + lỗi gặp lại → thẻ mới" || fail "hồi quy sau khi đóng không có thẻ mới: create=$(creates)"
grep -q '"comment", "42"' "$FAKE_LOG" && fail "comment vào thẻ đã đóng" || ok "không comment vào thẻ đã đóng"

# 10. Secret trong dòng log không lên GitHub.
echo '[14:20:00] ⚠ self-reload: push refused GITHUB_TOKEN=ghp_ABCDEFGHIJKLMNOP1234 with Bearer abcdefghijklmnop' >> "$MA"
scan >/dev/null
[ "$(creates)" = 6 ] && ok "secret: thẻ vẫn được tạo" || fail "secret: create=$(creates)"
grep -q 'ghp_ABCDEFGHIJ\|abcdefghijklmnop' "$FAKE_LOG" "$TMP/home/ledger.json" && fail "secret lọt lên issue/ledger" || ok "secret được che"

# 11. File log sinh SAU lần quét đầu (manifest ngày mới) đọc từ đầu; 12. dòng đang ghi dở chờ lượt sau.
printf '[00:00:01] runner died 5 times in a row — gave up (crash loop)\n' > "$A/docs/super-board/runs/2026-10-25-OfficeReader.md"
printf '[00:00:02] ⚠ self-reload: half writ' >> "$MB"
scan >/dev/null
[ "$(creates)" = 6 ] && ok "file mới: lỗi trùng chữ ký crash-loop không tạo thẻ mới; dòng dở chưa đọc" \
  || fail "file mới / dòng dở: create=$(creates)"
python3 - "$TMP/home/ledger.json" <<'PY' && ok "file mới được đọc từ đầu (crash-loop đếm 2)" || fail "file mới bị bỏ qua"
import json, sys
inc = [i for i in json.load(open(sys.argv[1]))["incidents"].values() if i["rule"] == "crash-loop"]
assert len(inc) == 1 and inc[0]["count"] == 2, inc
PY
printf 'ten line\n' >> "$MB"
scan >/dev/null
[ "$(creates)" = 7 ] && ok "dòng dở hoàn tất → đọc đúng một lần" || fail "dòng dở: create=$(creates)"

# 13. Thẻ đóng mà mọi lần gặp đều TRƯỚC lúc đóng (đã sửa xong, chưa comment) → không thẻ trùng.
echo '[15:00:00] ⚠ self-reload: lock file left behind' >> "$MA"
scan >/dev/null
n=$(creates)
echo '[15:00:30] ⚠ self-reload: lock file left behind' >> "$MB"
FAKE_CLOSED=$(cat "$FAKE_N") FAKE_CLOSED_AT=2999-01-01T00:00:00Z scan >/dev/null   # gặp lần 2, ghi TRƯỚC lúc đóng
[ "$(creates)" = "$n" ] && ok "thẻ đóng sau mọi lần gặp → không thẻ trùng" || fail "đóng thẻ sinh thẻ trùng: create=$(creates) (trước $n)"

# 15. Repo đích PUBLIC: khoá dạng JSON/repr và thẻ/PR của repo app không lên issue (runner giữ thẻ nêu owner/repo#N khác).
kname="api""_key"   # ghép lúc chạy: fixture giả, không phải secret tĩnh trong file
printf '[16:00:00] ⚠ self-reload: config {"%s": "zz9-secret-value"} for ToanMobile/OfficeReader#77 rejected\n' "$kname" >> "$MA"
scan >/dev/null
grep -q 'zz9-secret-value' "$FAKE_LOG" "$TMP/home/ledger.json" && fail "khoá JSON lọt" || ok "khoá dạng JSON được che"
pname="pass""word"
printf '[16:00:01] ⚠ self-reload: retry {"%s": "horse9 battery9 staple9"} denied\n' "$pname" >> "$MA"
scan >/dev/null
grep -q 'battery9\|staple9' "$FAKE_LOG" "$TMP/home/ledger.json" && fail "phần sau dấu cách của mật khẩu lọt" \
  || ok "giá trị trong ngoặc có dấu cách được che trọn"

# 21. Log ít ghi: mtime cũ hơn lúc thẻ đóng, lỗi được ghi SAU lúc đóng → vẫn là hồi quy (thẻ mới).
#     Thứ tự: các lần gặp cũ < lúc đóng thẻ < lần đọc trước (log im, mtime 2020) < lỗi mới được ghi.
WL="$A/.claude/super-board/runner/OfficeReader.watchdog.log"
sleep 1; CLOSED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ); sleep 1
touch -t 202001010000 "$WL"; scan >/dev/null      # lần đọc này: mtime 2020, lúc đọc = sau lúc đóng thẻ
CL=$(python3 -c 'import json,sys; print(next(i["issue"] for i in json.load(open(sys.argv[1]))["incidents"].values() if i["rule"] == "crash-loop"))' "$TMP/home/ledger.json")
n=$(creates)
echo '[x] runner died 5 times in a row — gave up (crash loop)' >> "$WL"
FAKE_CLOSED=$CL FAKE_CLOSED_AT=$CLOSED_AT scan >/dev/null
[ "$(creates)" = $((n + 1)) ] && ok "log ít ghi: lỗi sau lúc đóng thẻ → thẻ mới" || fail "log ít ghi bỏ lỡ hồi quy: create=$(creates) (trước $n)"
grep -q 'OfficeReader#77' "$FAKE_LOG" && fail "owner/repo#N của repo app lọt lên thẻ" || ok "owner/repo#N của repo app được bỏ"

# 16. stderr của runner (docs/super-board/runner.log): lỗi shell thành thẻ; FIFO trong audit-gate không làm treo scan.
mkfifo "$A/.claude/audit-gate/proof_gate.fifo.log"
echo '.claude/bin/super-board-run.sh: line 912: lane_slot_frees: command not found' >> "$A/docs/super-board/runner.log"
n=$(creates); scan >/dev/null
[ "$(creates)" = $((n + 1)) ] && ok "stderr runner: command not found → thẻ; FIFO bỏ qua" || fail "stderr runner: create=$(creates) (trước $n)"

# 17. Hook SessionStart: công tắc DEVKIT_INCIDENT=0 không quét; bật thì quét (nền); không repo nào trong danh sách → im.
hook_scan() {   # hook_scan <home> [env…]: chạy session_context.sh trong một repo nháp, chờ scan nền tối đa 10 s
  local h="$1"; shift
  mkdir -p "$TMP/hookrepo" && git -C "$TMP/hookrepo" init -q 2>/dev/null
  printf '{"session_id":"di","hook_event_name":"SessionStart","source":"startup"}' \
    | env SESSION_FETCH=0 STALE_RERUN=0 WORKTREE_GC=0 DEVKIT_INCIDENT_HOME="$h" "$@" \
      CLAUDE_PROJECT_DIR="$TMP/hookrepo" bash "$DEVKIT_DIR/hooks/session_context.sh" >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$h/ledger.json" ] && return 0; sleep 1; done; return 1
}
hook_scan "$TMP/h-off" DEVKIT_INCIDENT=0 && fail "hook: DEVKIT_INCIDENT=0 vẫn quét" || ok "hook: DEVKIT_INCIDENT=0 → không quét"
hook_scan "$TMP/h-on" && ok "hook: bật → SessionStart chạy scan nền" || fail "hook: SessionStart không chạy scan"
hook_scan "$TMP/h-none" DEVKIT_INCIDENT_REPOS="$TMP/khong-co" && fail "không repo nào mà vẫn tạo ledger" \
  || ok "máy không có repo trong danh sách → không làm gì"

# 18. Thẻ đã có, đến hạn comment, mà thẻ vừa đóng (trước lần kiểm tra theo giờ): không comment vào thẻ đóng.
python3 - "$TMP/home/ledger.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for i in d["incidents"].values():
    i["last_comment"] = 0; i["state_checked"] = 2**40   # hạn comment đã tới; kiểm tra theo giờ thì chưa
json.dump(d, open(p, "w"))
PY
echo '[17:00:00] ⚠ self-reload: lock file left behind' >> "$MA"
N=$(python3 -c 'import json,sys; print(next(i["issue"] for i in json.load(open(sys.argv[1]))["incidents"].values() if "lock file" in i["title"]))' "$TMP/home/ledger.json")
DEVKIT_INCIDENT_STATE_CHECK_S=3600 FAKE_CLOSED=$N FAKE_CLOSED_AT=2999-01-01T00:00:00Z scan >/dev/null
grep -q "\"comment\", \"$N\"" "$FAKE_LOG" && fail "comment vào thẻ vừa đóng #$N" || ok "đến hạn comment: hỏi trạng thái trước, không comment thẻ đóng"

# 19. Lỗi shell ở hai script khác nhau là hai thẻ; cùng script khác dòng là một. Secret ở đầu một Traceback dài không lọt
#     vì bị cắt đôi (che trước, cắt sau).
n=$(creates)
{ echo '.claude/bin/super-board-run.sh: line 10: syntax error near unexpected token'
  echo '.claude/bin/super-board-card.sh: line 20: syntax error near unexpected token'; } >> "$A/docs/super-board/runner.log"
# cùng lỗi đó nhưng qua manifest (đường classify_board), khác đuôi: vẫn đúng chữ ký "<script>: <lỗi>"
echo "[18:00:00] .claude/bin/super-board-card.sh: line 99: syntax error near unexpected token \`done'" >> "$MB"
scan >/dev/null
[ "$(creates)" = $((n + 2)) ] && ok "shell-error: 2 script → 2 thẻ, cùng script → 1" || fail "shell-error chữ ký: create=$(creates) (trước $n)"
{ echo 'Traceback (most recent call last):'
  echo "  File \"/x/.agents/devkit/hooks/review_gate.py\", line 5, in main"
  # khoá nằm >1200 ký tự trước đuôi giá trị: cắt trước rồi mới che thì mất tên khoá, đuôi LEAKMARK7 lọt
  kname="api""_key"   # ghép lúc chạy: fixture giả, không phải secret tĩnh trong file
  printf '    cfg = {"%s": "%sLEAKMARK7"}\n' "$kname" "$(printf 'p%.0s' $(seq 1 1300))"
  echo 'ValueError: bad config'; } >> "$A/.claude/audit-gate/review_gate.log"
scan >/dev/null
grep -q 'LEAKMARK7' "$FAKE_LOG" "$TMP/home/ledger.json" && fail "secret bị cắt đôi rồi lọt" || ok "che trước khi cắt: secret không lọt"

# 20. Traceback cụt (không có dòng exception) ngay trước một Traceback đầy đủ: cái sau vẫn thành thẻ;
#     một file log không đọc được (chmod 000) không làm mất sự cố của các file khác trong cùng lượt.
n=$(creates)
: > "$A/.claude/audit-gate/locked.log"; chmod 000 "$A/.claude/audit-gate/locked.log"
{ echo 'Traceback (most recent call last):'
  echo "  File \"/x/.agents/devkit/hooks/claim_check.py\", line 3, in run"
  echo 'Traceback (most recent call last):'
  echo "  File \"/x/.agents/devkit/hooks/claim_check.py\", line 9, in parse"
  echo 'IndexError: list index out of range'; } >> "$B/.claude/audit-gate/proof_gate.log"
scan >/dev/null
chmod 644 "$A/.claude/audit-gate/locked.log"
[ "$(creates)" = $((n + 1)) ] && ok "Traceback sau một Traceback cụt vẫn thành thẻ; file không đọc được bị bỏ qua" \
  || fail "Traceback cụt / file khoá: create=$(creates) (trước $n)"

# 14. Mỗi sự cố một thẻ riêng (--new-card): không gom vào thẻ bug khác.
grep '"issue", "create"' "$FAKE_LOG" >/dev/null && python3 - "$FAKE_LOG" <<'PY' && ok "--new-card: không gom vào thẻ khác" || fail "thiếu --new-card"
import json, sys
calls = [json.loads(l)["gh"] for l in open(sys.argv[1])]
assert not any(c[:2] == ["issue", "edit"] for c in calls), "gom vào thẻ khác"
PY

[ "$FAILS" = 0 ] && { echo "PASS test_devkit_incident"; exit 0; }
echo "FAIL test_devkit_incident ($FAILS)"; exit 1
