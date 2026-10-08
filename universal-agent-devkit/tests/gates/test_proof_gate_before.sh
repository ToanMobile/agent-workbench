#!/usr/bin/env bash
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

HOOKS="$(cd "$(dirname "$0")/../../hooks" && pwd)"
HOOK="$HOOKS/proof_gate.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/proofbefore.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

REPO="$TMP/repo"; mkdir -p "$REPO/src" "$REPO/.agents" "$REPO/reports" "$REPO/.claude/audit-gate"
( cd "$REPO" && git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt && echo '{"profile":"android"}' > .agents/active-profile.json
  printf '.claude/audit-gate/\n' > .gitignore
  git add -A && git commit -qm init )
TR="$TMP/transcript.jsonl"
N=0

turn_start() { sleep 1; N=$((N + 1)); python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi UI"}}))' > "$TR"; }

tool() { # Bash <command> or Edit <file_path>
  local name="$1"
  local arg="$2"
  if [ "$name" = "Bash" ]; then
    python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"assistant","timestamp":t,"message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-1","name":sys.argv[1],"input":{"command":sys.argv[2]}}]}}))' "$name" "$arg" >> "$TR"
    (cd "$REPO" && eval "$arg")
  else
    python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"assistant","timestamp":t,"message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-1","name":sys.argv[1],"input":{"file_path":sys.argv[2]}}]}}))' "$name" "$arg" >> "$TR"
    (cd "$REPO" && echo "// edit" >> "$arg")
  fi
}

stop() { # <reply>
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "$1" "sess-$N" \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }

png() { python3 - "$1" "$2" <<'PY'
import sys, zlib, struct, os
path, size = sys.argv[1], int(sys.argv[2])
sig = b"\x89PNG\r\n\x1a\n"
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
data = sig + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)) + chunk(b"IDAT", os.urandom(max(size - 60, 1))) + chunk(b"IEND", b"")
open(path, "wb").write(data)
PY
}

write_turn_class() { # <0|1> 1 = write both intents
  local f="$REPO/.claude/audit-gate/turn_class_sess-$N.json"
  if [ "$1" = 1 ]; then
    python3 -c 'import datetime,json,sys,time
print(json.dumps({"ts":time.time(),"intents":["BUG_FIX","UI_INTERACTION"]}))' > "$f"
  elif [ "$1" = 2 ]; then
    python3 -c 'import datetime,json,sys,time
print(json.dumps({"ts":time.time(),"intents":["BUG_FIX"]}))' > "$f"
  else
    rm -f "$f"
  fi
}

mkdir -p "$REPO/.git/postfix-gate"

# Helper to write receipt matching current time
write_receipt() {
  local fp
  fp="$(python3 "$HOOKS/../bin/tree_fp.py" "$REPO")"
  python3 -c 'import time,json,sys; print(json.dumps({"exit":0,"time":time.time()+3600,"fingerprint":sys.argv[1]}))' "$fp" > "$REPO/.git/postfix-gate/full_pass.json"
}

rep="1. Đã fix gì: abc
2. Chặn bug cũ: abc
3. Nguy cơ bug mới: abc
4. An toàn mã nguồn: abc"

# (1) prompt UI-bug + chỉ ảnh SAU ⇒ từ chối "BEFORE evidence missing"
turn_start; write_turn_class 1;
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
$rep"; rc=$?
[ "$rc" = 2 ] && grep -q "before-" "$TMP/err" && ok "ca 1 rejected without before" || fail "ca 1 failed (rc=$rc, err=$(cat "$TMP/err"))"

# (2) + file reports/before-<stamp>.png có mtime SỚM HƠN lần sửa app source đầu tiên ⇒ chấp nhận
turn_start; write_turn_class 1;
B="reports/before-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$B" 20000
sleep 1
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20001
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
Ảnh $B
$rep"; rc=$?
[ "$rc" = 0 ] && ok "ca 2 accepted" || fail "ca 2 failed (rc=$rc, err=$(cat "$TMP/err"), log=$(cat $REPO/.claude/audit-gate/proof_gate.log))"

# (3) before MỚI hơn lần sửa đầu ⇒ từ chối
turn_start; write_turn_class 1;
tool Edit src/Core.kt
sleep 1
B="reports/before-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$B" 20000
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20001
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
Ảnh $B
$rep"; rc=$?
[ "$rc" = 2 ] && grep -q "phải chụp TRƯỚC" "$TMP/err" && ok "ca 3 rejected (newer than first edit)" || fail "ca 3 failed (rc=$rc, err=$(cat "$TMP/err"))"

# (4) ảnh SAU trùng byte với ảnh TRƯỚC bị từ chối bởi kiểm ảnh SAU
turn_start; write_turn_class 1;
B="reports/before-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$B" 20000
sleep 1
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; cp "$REPO/$B" "$REPO/$P"
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
Ảnh $B
$rep"; rc=$?
[ "$rc" = 2 ] && grep -q "trùng byte" "$TMP/err" && cat "$TMP/err" && ok "ca 4 rejected by AFTER image check" || fail "ca 4 failed (rc=$rc, err=$(cat "$TMP/err"))"

# (5) before 0 byte ⇒ từ chối
turn_start; write_turn_class 1;
B="reports/before-$(date +%Y%m%d-%H%M%S).png"; touch "$REPO/$B"
sleep 1
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
Ảnh $B
$rep"; rc=$?
[ "$rc" = 2 ] && grep -q "0 byte" "$TMP/err" && ok "ca 5 rejected (0 byte)" || fail "ca 5 failed (rc=$rc, err=$(cat "$TMP/err"))"

# (6) dòng `before: không cần — <lý do>` ⇒ chấp nhận
turn_start; write_turn_class 1;
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000
stop "XONG
Đã fix lỗi.
Gate exit 0
before: không cần — do UI tự tạo ra
Ảnh $P
$rep"; rc=$?
[ "$rc" = 0 ] && ok "ca 6 accepted with waiver" || fail "ca 6 failed (rc=$rc, err=$(cat "$TMP/err"))"

# (7) profile backend / prompt không phải lỗi UI / PROOF_BEFORE=0 / câu trả lời không mở bằng XONG
# Backend
echo '{"profile":"backend"}' > "$REPO/.agents/active-profile.json"
git -C "$REPO" add -f .agents/active-profile.json
git -C "$REPO" commit -q -m "switch to backend"
turn_start; write_turn_class 1;
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
$rep"; rc=$?
[ "$rc" = 0 ] && ok "ca 7a accepted (backend)" || fail "ca 7a failed (rc=$rc, err=$(cat "$TMP/err"))"
echo '{"profile":"android"}' > "$REPO/.agents/active-profile.json"

# No intents
turn_start; write_turn_class 2; 
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
$rep"; rc=$?
[ "$rc" = 0 ] && ok "ca 7b accepted (no UI intents)" || fail "ca 7b failed (rc=$rc, err=$(cat "$TMP/err"))"

# PROOF_BEFORE=0
turn_start; write_turn_class 1;
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000
PROOF_BEFORE=0 stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
$rep"; rc=$?
[ "$rc" = 0 ] && ok "ca 7c accepted (PROOF_BEFORE=0)" || fail "ca 7c failed (rc=$rc, err=$(cat "$TMP/err"))"

# Not XONG
turn_start; write_turn_class 1;
tool Edit "src/Core.kt"
write_receipt
stop "CHƯA XONG"; rc=$?
[ "$rc" = 0 ] && ok "ca 7d accepted (Not XONG)" || fail "ca 7d failed (rc=$rc, err=$(cat "$TMP/err"))"

# (8) các lời từ chối ảnh SAU hiện có vẫn bắn và đứng trước
turn_start; write_turn_class 1;
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 0
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
$rep"; rc=$?
[ "$rc" = 2 ] && grep -q "lớn hơn 8 KB" "$TMP/err" && ok "ca 8 rejected (after image invalid first)" || fail "ca 8 failed (rc=$rc, err=$(cat "$TMP/err"))"


# (A) Bash `ls reports` -> chụp before -> Edit -> rc=2
turn_start; write_turn_class 1;
tool Bash "ls reports"
B="reports/before-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$B" 20000
sleep 1
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20001
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
Ảnh $B
$rep"; rc=$?
[ "$rc" = 0 ] && ok "ca A accepted (Bash ls ignored)" || fail "ca A failed (rc=$rc, err=$(cat "$TMP/err"))"

# (B) before -> Edit{file_path} -> accepted
turn_start; write_turn_class 1;
B="reports/before-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$B" 20000
sleep 1
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20001
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
Ảnh $B
$rep"; rc=$?
[ "$rc" = 0 ] && ok "ca B accepted" || fail "ca B failed (rc=$rc, err=$(cat "$TMP/err"))"

# (9) tc_ts = start - 2s -> demands before
turn_start
# write turn_class manually with ts = start - 2s
python3 -c 'import json,sys,time; print(json.dumps({"ts":time.time()-2, "intents":["BUG_FIX","UI_INTERACTION"]}))' > "$REPO/.claude/audit-gate/turn_class_sess-$N.json"
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20001
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
$rep"; rc=$?
[ "$rc" = 2 ] && grep -q "BEFORE EVIDENCE:" "$TMP/err" && ok "ca 9 rejected (ts = start - 2s)" || fail "ca 9 failed (rc=$rc, err=$(cat "$TMP/err"))"

# (10) tc_ts = start - 120s -> DOES NOT demand before
turn_start
python3 -c 'import json,sys,time; print(json.dumps({"ts":time.time()-120, "intents":["BUG_FIX","UI_INTERACTION"]}))' > "$REPO/.claude/audit-gate/turn_class_sess-$N.json"
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20001
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
$rep"; rc=$?
[ "$rc" = 0 ] && ok "ca 10 accepted (ts = start - 120s)" || fail "ca 10 failed (rc=$rc, err=$(cat "$TMP/err"))"



# (12) Only BEFORE missing + has AFTER image -> prints full BEFORE error
turn_start; write_turn_class 1
sleep 1
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
$rep"; rc=$?
[ "$rc" = 2 ] && grep -q "BEFORE EVIDENCE: thiếu báo cáo trạng thái trước khi sửa (reports/before-... hoặc \`before: không cần — <lý do>\`)" "$TMP/err" && ok "ca 12 rejected (full before msg preserved)" || fail "ca 12 failed (rc=$rc, err=$(cat "$TMP/err"))"

# (13) No images at all -> still prints BEFORE error
turn_start; write_turn_class 1
sleep 1
tool Edit "src/Core.kt"
write_receipt
stop "XONG
Đã fix lỗi.
Gate exit 0
$rep"; rc=$?
[ "$rc" = 2 ] && grep -q "BEFORE EVIDENCE: thiếu báo cáo trạng thái trước khi sửa" "$TMP/err" && ok "ca 13 rejected (before msg when cited empty)" || fail "ca 13 failed (rc=$rc, err=$(cat "$TMP/err"))"

# (14) BEFORE image is not valid PNG
turn_start; write_turn_class 1
B="reports/before-$(date +%Y%m%d-%H%M%S).png"
echo "XX" > "$REPO/$B"
sleep 1
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
Ảnh $B
$rep"; rc=$?
[ "$rc" = 2 ] && grep -q "không phải định dạng PNG hợp lệ" "$TMP/err" && ok "ca 14 rejected (invalid PNG signature)" || fail "ca 14 failed (rc=$rc, err=$(cat "$TMP/err"))"


# (11) transcript_path unreadable -> hook exit 0, log has "first_edit lookup failed"
B="reports/before-$(date +%Y%m%d-%H%M%S).png"; touch "$REPO/$B"; sleep 1
png "$REPO/$B" 20000
sleep 1
turn_start; write_turn_class 1
python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi UI"}}))
print(json.dumps({"tool_use": True, "timestamp":t, "message": "this_is_a_string_not_a_dict"}))' > "$TR"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000
stop "XONG
Đã fix.
Gate exit 0
Ảnh $P
Ảnh $B
$rep"; rc=$?
[ "$rc" = 0 ] && grep -q "first_edit lookup failed" "$REPO/.claude/audit-gate/proof_gate.log" && ok "ca 11 passed (bad transcript ignored, logged)" || fail "ca 11 failed (rc=$rc, err=$(cat "$TMP/err"), log=$(cat "$REPO/.claude/audit-gate/proof_gate.log" 2>/dev/null))"


# (15) Bad turn_class payloads do not crash the hook
for bad in '[]' '"str"' 'null' '{"ts":"x","intents":[]}' '{"ts":0,"intents":5}'; do
  turn_start
  echo "$bad" > "$REPO/.claude/audit-gate/turn_class_sess-$N.json"
  tool Edit "src/Core.kt"
  stop "XONG"; rc=$?
  [ "$rc" = 2 ] && ! grep -q "Traceback" "$TMP/err" && ok "ca 15 bad turn_class ($bad) rejected without Traceback" || fail "ca 15 bad turn_class ($bad) failed (rc=$rc, err=$(cat "$TMP/err"))"
done

# (16) mkdir reports/zz.png does not crash BEFORE image check
turn_start; write_turn_class 1
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000
mkdir -p "$REPO/reports/before-20261008-000000.png"
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
Ảnh reports/before-20261008-000000.png
$rep"; rc=$?
[ "$rc" = 2 ] && ! grep -q "Traceback" "$TMP/err" && ok "ca 16 directory BEFORE image handled without Traceback" || fail "ca 16 failed (rc=$rc, err=$(cat "$TMP/err"))"


# (17) Secret in transcript is not leaked to log
turn_start; write_turn_class 1
tool Edit "src/Core.kt"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000
# Write tool containing API_TOKEN=ghp_FAKESECRET123 ... push
python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"assistant","timestamp":t,"message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-leak","name":"Write","input":{"TargetFile":"test.sh", "command":"API_TOKEN=ghp_FAKESECRET123 git push"}}]}}))' >> "$TR"
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
$rep"; rc=$?
if grep -q "ghp_FAKESECRET123" "$REPO/.claude/audit-gate/proof_gate.log" 2>/dev/null; then
    fail "ca 17 leaked secret to proof_gate.log"
else
    ok "ca 17 secret not leaked"
fi


# (18) Bash sed -i does not trigger first_edit, so BEFORE is valid
turn_start; write_turn_class 1
B="reports/before-$(date +%Y%m%d-%H%M%S).png"; touch "$REPO/$B"; sleep 1
png "$REPO/$B" 20000
sleep 1
# This tool_use simulates Bash 'sed -i ...' which proof_gate NO LONGER detects as an app source edit
python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"assistant","timestamp":t,"message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-sed","name":"Bash","input":{"command":"sed -i s/a/b/ src/Core.kt"}}]}}))' >> "$TR"
write_receipt
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000
stop "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
Ảnh $B
$rep"; rc=$?
[ "$rc" = 0 ] && ok "ca 18 bash sed -i accepted (mtime not checked)" || fail "ca 18 failed (rc=$rc, err=$(cat "$TMP/err"))"

if [ "$FAIL" -ne 0 ]; then
  echo "$FAIL FAILED"
  exit 1
else
  echo "ALL OK"
  exit 0
fi
