#!/usr/bin/env bash
# Test hồi quy (#686, PR 1 "cờ + override + watch"): bin/gate_rules.py đọc cờ .agents/gate-rules.json (§2.2/§2.3/§2.5 của thiết kế v3.1).
# Repo giả: main + worktree + bare origin. Mỗi lệnh chạy trong tiến trình riêng (lru_cache của module không che ca sau).
#   1. thiếu file ⇒ off, TTL 21600;
#   2. HEAD on mà origin off ⇒ off; cả hai on ⇒ on (đọc từ main lẫn từ worktree);
#   3. worktree PR sửa file ⇒ off; main bẩn ⇒ off; `shadow` / JSON rác / giá trị lạ ⇒ off;
#   4. override `off` thắng, override `on` bị bỏ;
#   5. env `off` thắng, env `on` bị bỏ;
#   6. CLI `off`: SB_BOARD_WORKER=1 ⇒ exit 3, không ghi; thường ⇒ ghi, idempotent;
#   7. post-fix-gate.suite_env không mang DEVKIT_GATE_RULE_* / SB_L3_*;
#   8. TTL: trần 86400, env chỉ hạ, `zero` ⇒ 0, rác/bool/≤0 ⇒ 21600, min(HEAD, origin);
#   9. local_state_sha không đổi theo cờ/override/env; `tokens` đúng;
#  10. log_decision không raise khi thư mục chỉ đọc, ghi đúng dòng khi ghi được; used_ok;
#  11. raise-check: c1–c4, ok, off, ttl (mọi ca của §2.4 ở mức logic; ca qua merge gate nằm ở tests/super-board/test_merge_gate_rules_raise.sh).
# Chưa có bin/gate_rules.py thì ĐỎ. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GR="$DEVKIT_DIR/bin/gate_rules.py"
PFG="$DEVKIT_DIR/bin/post-fix-gate.py"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

[ -f "$GR" ] || { echo "✖ không có bin/gate_rules.py: chưa có cờ gate-rules"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-rules-flags.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd)"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }
unset DEVKIT_GATE_RULE_L1 DEVKIT_GATE_RULE_L2 DEVKIT_GATE_RULE_L3 DEVKIT_GATE_RULE_B DEVKIT_GATE_RULE_CACHE \
      DEVKIT_SUITE_CACHE_MAX_S DEVKIT_GATE_CACHE_MAX_S SB_BOARD_WORKER

# gr <dir> <args...>: chạy CLI trong <dir>, in stdout (stderr bỏ); rc ở $GRRC
# rc ghi vào file (gr hay bị gọi trong $(...), biến không về được shell cha); đọc bằng grrc
gr() { local d="$1"; shift; local out rc; out="$(cd "$d" && python3 -B "$GR" "$@" 2>/dev/null)"; rc=$?; echo "$rc" > "$T/.grrc"; printf '%s' "$out"; }
grrc() { cat "$T/.grrc" 2>/dev/null || echo 99; }

# --- repo giả ---------------------------------------------------------------------------------------------------------------
g init -q --bare "$T/origin.git"
g init -q "$T/main"
M="$T/main"
mkdir -p "$M/.agents"
rules_json() { # <L1> <L2> <L3> <B> <ttl>
  printf '{"version": 1, "rules": {"L1": "%s", "L2": "%s", "L3": "%s", "B": "%s"}, "ttl": {"suite_cache_max_s": %s}}\n' "$1" "$2" "$3" "$4" "$5"
}

# 1. thiếu file
D1="$T/nofile"; g init -q "$D1"; ( cd "$D1" && g commit -q --allow-empty -m init )
chk "1. thiếu file ⇒ get L3 = off" '[ "$(gr "$D1" get L3)" = off ] && [ "$(grrc)" -eq 0 ]'
chk "1. thiếu file ⇒ ttl = 21600" '[ "$(gr "$D1" ttl suite_cache_max_s)" = 21600 ]'
# thêm file cờ lần đầu với mọi luật off ⇒ hiệu lực y như khi chưa có file (json, tokens, từng get)
D1c="$T/alloff"; g init -q "$D1c"; mkdir -p "$D1c/.agents"
printf '{"version": 1, "rules": {"L1": "off", "L2": "off", "L3": "off", "B": "off"}, "ttl": {"suite_cache_max_s": 21600}}\n' > "$D1c/.agents/gate-rules.json"
( cd "$D1c" && g add -A && g commit -q -m "thêm cờ, toàn off" )
chk "1. file cờ toàn off lần đầu ⇒ json / tokens giống hệt khi chưa có file" '[ "$(gr "$D1c" json)" = "$(gr "$D1" json)" ] && [ "$(gr "$D1c" tokens)" = "$(gr "$D1" tokens)" ]' "$(gr "$D1c" json) vs $(gr "$D1" json)"
chk "1. file cờ toàn off ⇒ get mọi khoá + ttl giống khi chưa có file" 'same=1; for k in L1 L2 L3 B CACHE; do [ "$(gr "$D1c" get $k)" = "$(gr "$D1" get $k)" ] || same=0; done; [ "$same" = 1 ] && [ "$(gr "$D1c" ttl suite_cache_max_s)" = "$(gr "$D1" ttl suite_cache_max_s)" ]'
D1b="$T/notgit"; mkdir -p "$D1b"
chk "1. ngoài git ⇒ off, exit 0 (lỗi không raise)" '[ "$(gr "$D1b" get L3)" = off ] && [ "$(grrc)" -eq 0 ]'
chk "1. get rule lạ ⇒ off, exit 0" '[ "$(gr "$D1" get ZZ)" = off ] && [ "$(grrc)" -eq 0 ]'

# 2. HEAD / origin
rules_json off off off off 21600 > "$M/.agents/gate-rules.json"
( cd "$M" && g add -A && g commit -q -m base && g remote add origin "$T/origin.git" && g push -q origin main && g remote set-head origin main >/dev/null 2>&1 )
g -C "$M" worktree add -q --detach "$T/wt" >/dev/null 2>&1
W="$T/wt"
chk "2. toàn off ⇒ get L3 off" '[ "$(gr "$M" get L3)" = off ]'
rules_json off off on off 21600 > "$M/.agents/gate-rules.json"
( cd "$M" && g commit -q -am "L3 on (chưa push)" )
chk "2. HEAD on, origin off ⇒ off (main)" '[ "$(gr "$M" get L3)" = off ]'
chk "2. HEAD on, origin off ⇒ off (worktree)" '[ "$(gr "$W" get L3)" = off ]'
( cd "$M" && g push -q origin main )
chk "2. HEAD on, origin on ⇒ on (main)" '[ "$(gr "$M" get L3)" = on ]'
chk "2. HEAD on, origin on ⇒ on (worktree: đọc HEAD của main, không phải của worktree)" '[ "$(gr "$W" get L3)" = on ]'
chk "2. luật khác vẫn off" '[ "$(gr "$M" get B)" = off ] && [ "$(gr "$M" get L1)" = off ]'
J="$(gr "$M" json)"
chk "2. json có rules.L3=on và ttl" 'echo "$J" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d[\"rules\"][\"L3\"]==\"on\" and d[\"rules\"][\"B\"]==\"off\" and d[\"ttl\"][\"suite_cache_max_s\"]==21600"' "$J"

# 3. worktree PR sửa file, main bẩn, shadow / rác
rules_json on off on on 21600 > "$W/.agents/gate-rules.json"
chk "3. worktree sửa file (chưa commit) ⇒ L1/B vẫn off" '[ "$(gr "$W" get L1)" = off ] && [ "$(gr "$W" get B)" = off ]'
( cd "$W" && g add -A && g commit -q -m "PR bật L1 B" )
chk "3. worktree PR commit bật L1/B ⇒ vẫn off (đọc blob của main + origin)" '[ "$(gr "$W" get L1)" = off ] && [ "$(gr "$W" get B)" = off ]'
rules_json off off on on 21600 > "$M/.agents/gate-rules.json"
chk "3. main bẩn (file khác HEAD) ⇒ mọi luật off, kể cả L3 đang on ở cả hai blob" '[ "$(gr "$M" get L3)" = off ] && [ "$(gr "$M" get B)" = off ]'
( cd "$M" && g checkout -q -- .agents/gate-rules.json )
chk "3. main sạch lại ⇒ L3 on" '[ "$(gr "$M" get L3)" = on ]'
printf '{"version": 1, "rules": {"L1": "shadow", "L2": "ON", "L3": true, "B": 1}}\n' > "$M/.agents/gate-rules.json"
( cd "$M" && g commit -q -am "giá trị lạ" && g push -q origin main )
chk "3. shadow / ON / true / 1 ⇒ off" '[ "$(gr "$M" get L1)" = off ] && [ "$(gr "$M" get L2)" = off ] && [ "$(gr "$M" get L3)" = off ] && [ "$(gr "$M" get B)" = off ]'
printf '{not json' > "$M/.agents/gate-rules.json"
( cd "$M" && g commit -q -am "rác" && g push -q origin main )
chk "3. JSON rác ⇒ off, exit 0" '[ "$(gr "$M" get L3)" = off ] && [ "$(grrc)" -eq 0 ] && [ "$(gr "$M" ttl suite_cache_max_s)" = 21600 ]'

# --- từ đây dùng main: L3 on, B on, TTL 86400 ở cả HEAD lẫn origin -----------------------------------------------------------
rules_json off off on on 86400 > "$M/.agents/gate-rules.json"
( cd "$M" && g commit -q -am "L3 B on, ttl 86400" && g push -q origin main )
chk "base. L3 on, B on, ttl 86400" '[ "$(gr "$M" get L3)" = on ] && [ "$(gr "$M" get B)" = on ] && [ "$(gr "$M" ttl suite_cache_max_s)" = 86400 ]'
COMMON="$(cd "$M" && git rev-parse --path-format=absolute --git-common-dir)"
OV="$COMMON/postfix-gate/gate-rules.override.json"

# 4. override
mkdir -p "$COMMON/postfix-gate"
printf '{"rules": {"L3": {"value": "off", "reason": "t", "at": 1, "by": "t"}, "L1": {"value": "on", "reason": "t", "at": 1, "by": "t"}}}\n' > "$OV"
chk "4. override off thắng ⇒ L3 off" '[ "$(gr "$M" get L3)" = off ]'
chk "4. override on bị bỏ ⇒ L1 vẫn off (blob off), B vẫn on" '[ "$(gr "$M" get L1)" = off ] && [ "$(gr "$M" get B)" = on ]'
printf '{"rules": {"B": {"value": "on"}}}\n' > "$OV"
chk "4. override on không đổi B đang on, không bật gì thêm" '[ "$(gr "$M" get B)" = on ] && [ "$(gr "$M" get L3)" = on ]'
printf 'rác' > "$OV"
chk "4. override rác bị bỏ (không làm hỏng, không bật)" '[ "$(gr "$M" get L3)" = on ] && [ "$(grrc)" -eq 0 ]'
rm -f "$OV"

# 5. env
chk "5. env off thắng" '[ "$(DEVKIT_GATE_RULE_L3=off gr "$M" get L3)" = off ]'
chk "5. env on bị bỏ (L1 blob off)" '[ "$(DEVKIT_GATE_RULE_L1=on gr "$M" get L1)" = off ]'
chk "5. env on không đổi L3 đang on, env giá trị lạ bị bỏ" '[ "$(DEVKIT_GATE_RULE_L3=on gr "$M" get L3)" = on ] && [ "$(DEVKIT_GATE_RULE_L3=shadow gr "$M" get L3)" = on ]'

# 6. CLI off
chk "6. SB_BOARD_WORKER=1 off ⇒ exit 3" 'SB_BOARD_WORKER=1 gr "$M" off L3 --reason t >/dev/null; [ "$(grrc)" -eq 3 ]'
chk "6. exit 3 không ghi override" '[ ! -e "$OV" ]'
chk "6. thiếu --reason ⇒ exit 2" 'gr "$M" off L3 >/dev/null; [ "$(grrc)" -eq 2 ]'
chk "6. rule lạ ⇒ exit 2" 'gr "$M" off ZZ --reason t >/dev/null; [ "$(grrc)" -eq 2 ]'
chk "6. --zero cho luật thường ⇒ exit 2" 'gr "$M" off L3 --zero --reason t >/dev/null; [ "$(grrc)" -eq 2 ]'
gr "$M" off L3 --reason "thử" >/dev/null; rc1=$(grrc)
chk "6. off L3 ⇒ exit 0, ghi override có reason/at/by" '[ "$rc1" -eq 0 ] && python3 -c "
import json,sys; d=json.load(open(sys.argv[1])); r=d[\"rules\"][\"L3\"]; assert r[\"value\"]==\"off\" and r[\"reason\"]==\"thử\" and r[\"at\"] and r[\"by\"]" "$OV"'
chk "6. sau off L3 ⇒ get L3 = off, B vẫn on" '[ "$(gr "$M" get L3)" = off ] && [ "$(gr "$M" get B)" = on ]'
before="$(cat "$OV")"; gr "$M" off L3 --reason "lần hai" >/dev/null; rc2=$(grrc)
chk "6. idempotent: gọi lại exit 0, không đổi bản ghi cũ" '[ "$rc2" -eq 0 ] && [ "$(cat "$OV")" = "$before" ]'
gr "$M" off B --reason t2 >/dev/null
chk "6. off thêm luật khác giữ luật cũ" '[ "$(gr "$M" get B)" = off ] && [ "$(gr "$M" get L3)" = off ]'
rm -f "$OV"

# 8. TTL (trước 7/9 vì dùng cùng nền)
chk "8. ttl file 86400 ⇒ 86400" '[ "$(gr "$M" ttl suite_cache_max_s)" = 86400 ]'
chk "8. env DEVKIT_SUITE_CACHE_MAX_S=3600 hạ ⇒ 3600" '[ "$(DEVKIT_SUITE_CACHE_MAX_S=3600 gr "$M" ttl suite_cache_max_s)" = 3600 ]'
chk "8. env DEVKIT_GATE_CACHE_MAX_S=7200 hạ ⇒ 7200" '[ "$(DEVKIT_GATE_CACHE_MAX_S=7200 gr "$M" ttl suite_cache_max_s)" = 7200 ]'
chk "8. env 100000 không nâng ⇒ vẫn 86400" '[ "$(DEVKIT_SUITE_CACHE_MAX_S=100000 gr "$M" ttl suite_cache_max_s)" = 86400 ]'
chk "8. env rác bị bỏ ⇒ 86400" '[ "$(DEVKIT_SUITE_CACHE_MAX_S=abc gr "$M" ttl suite_cache_max_s)" = 86400 ]'
chk "8. env 0 ⇒ 0 (hạ)" '[ "$(DEVKIT_SUITE_CACHE_MAX_S=0 gr "$M" ttl suite_cache_max_s)" = 0 ]'
chk "8. DEVKIT_GATE_RULE_CACHE=zero ⇒ 0" '[ "$(DEVKIT_GATE_RULE_CACHE=zero gr "$M" ttl suite_cache_max_s)" = 0 ]'
chk "8. DEVKIT_GATE_RULE_CACHE=off ⇒ 21600 (hành vi 46b553fa)" '[ "$(DEVKIT_GATE_RULE_CACHE=off gr "$M" ttl suite_cache_max_s)" = 21600 ]'
chk "8. get CACHE: on / zero / off" '[ "$(gr "$M" get CACHE)" = on ] && [ "$(DEVKIT_GATE_RULE_CACHE=zero gr "$M" get CACHE)" = zero ] && [ "$(DEVKIT_GATE_RULE_CACHE=off gr "$M" get CACHE)" = off ]'
gr "$M" off CACHE --zero --reason t >/dev/null
chk "8. CLI off CACHE --zero ⇒ ttl 0" '[ "$(grrc)" -eq 0 ] && [ "$(gr "$M" ttl suite_cache_max_s)" = 0 ]'
gr "$M" off CACHE --reason t >/dev/null
chk "8. off CACHE sau zero không nới lại (giữ zero)" '[ "$(gr "$M" ttl suite_cache_max_s)" = 0 ]'
rm -f "$OV"
gr "$M" off CACHE --reason t >/dev/null
chk "8. off CACHE (không --zero) ⇒ 21600" '[ "$(gr "$M" ttl suite_cache_max_s)" = 21600 ]'
rm -f "$OV"
for v in 999999 0 -5 true '"abc"' 1.5e9 5.5; do
  rules_json off off on on "$v" > "$M/.agents/gate-rules.json"
  ( cd "$M" && g commit -q -am "ttl $v" && g push -q origin main )
  case "$v" in 999999) want=86400 ;; *) want=21600 ;; esac
  chk "8. ttl file $v ⇒ $want" '[ "$(gr "$M" ttl suite_cache_max_s)" = "$want" ]' "$(gr "$M" ttl suite_cache_max_s)"
done
rules_json off off on on 3600 > "$M/.agents/gate-rules.json"
( cd "$M" && g commit -q -am "ttl 3600" && g push -q origin main )
rules_json off off on on 86400 > "$M/.agents/gate-rules.json"
( cd "$M" && g commit -q -am "ttl 86400 chưa push" )
chk "8. min(HEAD 86400, origin 3600) ⇒ 3600" '[ "$(gr "$M" ttl suite_cache_max_s)" = 3600 ]' "$(gr "$M" ttl suite_cache_max_s)"
( cd "$M" && g push -q origin main )

# 7. suite_env + 9. local_state_sha / tokens (nạp post-fix-gate.py bằng importlib)
cat > "$T/pfg_probe.py" <<'PY'
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1])
pfg = importlib.util.module_from_spec(spec); spec.loader.exec_module(pfg)
proj = sys.argv[2]
os.environ.pop("DEVKIT_CAPACITY", None)
base_sha = pfg.local_state_sha(proj)
os.environ.update({"DEVKIT_GATE_RULE_L3": "off", "DEVKIT_GATE_RULE_CACHE": "zero", "SB_L3_AUDITED": "x", "DEVKIT_CAPACITY": "1.5"})
env = pfg.suite_env()
with_env_sha = pfg.local_state_sha(proj)
print(json.dumps({"leak": [k for k in env if k.startswith(("DEVKIT_GATE_RULE_", "SB_L3_"))],
                  "kept_capacity": env.get("DEVKIT_CAPACITY"), "same_sha": base_sha == with_env_sha, "sha": base_sha}))
PY
P="$(cd "$M" && python3 -B "$T/pfg_probe.py" "$PFG" "$M" 2>"$T/probe.err")"
chk "7. suite_env bỏ DEVKIT_GATE_RULE_* và SB_L3_*, giữ DEVKIT_CAPACITY" 'echo "$P" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d[\"leak\"]==[] and d[\"kept_capacity\"]==\"1.5\""' "$P $(tail -2 "$T/probe.err")"
chk "9. local_state_sha không đổi khi env cờ đặt" 'echo "$P" | python3 -c "import json,sys; assert json.load(sys.stdin)[\"same_sha\"]"' "$P"
printf '{"rules": {"L3": {"value": "off"}}}\n' > "$OV"
P2="$(cd "$M" && python3 -B "$T/pfg_probe.py" "$PFG" "$M" 2>/dev/null)"
chk "9. local_state_sha không đổi khi có file override" '[ "$(echo "$P" | python3 -c "import json,sys; print(json.load(sys.stdin)[\"sha\"])")" = "$(echo "$P2" | python3 -c "import json,sys; print(json.load(sys.stdin)[\"sha\"])")" ]'
rm -f "$OV"

tokens_of() { gr "$1" tokens | tr '\n' ' '; }
chk "9. tokens (L2 off, L3 on): hiện hành trước, rồi hạ" '[ "$(tokens_of "$M")" = "L2=off,L3=on L2=off,L3=off" ]' "$(tokens_of "$M")"
rules_json off on on on 86400 > "$M/.agents/gate-rules.json"
( cd "$M" && g commit -q -am "L2 on" && g push -q origin main )
tk="$(tokens_of "$M")"
chk "9. tokens (L2 on, L3 on): 4 token, hiện hành đầu tiên" '[ "${tk%% *}" = "L2=on,L3=on" ] && [ "$(gr "$M" tokens | grep -c .)" = 4 ] && echo "$tk" | grep -q "L2=off,L3=off" && echo "$tk" | grep -q "L2=on,L3=off" && echo "$tk" | grep -q "L2=off,L3=on"' "$tk"
chk "9. tokens khi cờ lỗi ⇒ L2=off,L3=off" '[ "$(gr "$D1b" tokens)" = "L2=off,L3=off" ]'

# 10. log_decision + used_ok
cat > "$T/api_probe.py" <<'PY'
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("gate_rules", sys.argv[1])
gr = importlib.util.module_from_spec(spec); spec.loader.exec_module(gr)
proj, mode = sys.argv[2], sys.argv[3]
if mode == "log":
    gr.log_decision("L3", {"kind": "decision", "decision": "applied", "detail": {"used": True}}, proj)
    gr.log_decision("ZZ", {"x": 1}, proj)   # rule lạ: không raise, không ghi
    print("ok")
elif mode == "used":
    print(json.dumps([gr.used_ok(["L3"], proj), gr.used_ok([], proj), gr.used_ok(None, proj), gr.used_ok(["L1"], proj),
                      gr.used_ok(["L3", "L1"], proj), gr.used_ok({"L3": "on"}, proj), gr.used_ok(["ZZ"], proj)]))
PY
ARCH="$COMMON/postfix-gate/archive"
mkdir -p "$ARCH"
out="$(python3 -B "$T/api_probe.py" "$GR" "$M" log 2>/dev/null)"
f="$(ls "$ARCH"/rules-L3-*.jsonl 2>/dev/null | head -1)"
chk "10. log_decision ghi rules-L3-<ngày UTC>.jsonl, dòng đủ trường chung" '[ "$out" = ok ] && [ -n "$f" ] && python3 -c "
import json,sys,re; l=open(sys.argv[1]).read().splitlines(); assert len(l)==1; d=json.loads(l[0]); assert d[\"rule\"]==\"L3\" and d[\"decision\"]==\"applied\" and d[\"ts\"] and d[\"value\"]==\"on\" and re.search(r\"rules-L3-\d{8}\.jsonl\$\", sys.argv[1])" "$f"' "$out $f"
chk "10. rule lạ không tạo file" '[ -z "$(ls "$ARCH"/rules-ZZ-* 2>/dev/null)" ]'
rm -f "$ARCH"/rules-L3-*.jsonl; chmod 555 "$ARCH"
out="$(python3 -B "$T/api_probe.py" "$GR" "$M" log 2>"$T/log.err")"; rc=$?
chk "10. thư mục archive chỉ đọc ⇒ không raise (exit 0, in cảnh báo)" '[ "$rc" -eq 0 ] && [ "$out" = ok ]' "rc=$rc $out $(tail -2 "$T/log.err")"
chmod 755 "$ARCH"
U="$(python3 -B "$T/api_probe.py" "$GR" "$M" used 2>/dev/null)"
chk "10. used_ok: chỉ ok khi mọi luật đã dùng còn on (L3 on, L1 off, ZZ lạ)" 'echo "$U" | python3 -c "
import json,sys; r=json.load(sys.stdin); ok=[x[0] for x in r]; assert ok==[True,True,True,False,False,True,False], r; assert \"L1\" in r[3][1]"' "$U"

# 11. raise-check (mức logic)
RC_DIR="$T/rc"; mkdir -p "$RC_DIR"
rj() { rules_json "$@"; }
rck() { # <old|-> <new> <paths-file-content> <guard-same> → rc
  local oldf="$RC_DIR/old.json" newf="$RC_DIR/new.json" pf="$RC_DIR/paths"
  if [ "$1" = "-" ]; then oldarg="-"; else printf '%s' "$1" > "$oldf"; oldarg="$oldf"; fi
  printf '%s' "$2" > "$newf"; printf '%s' "$3" > "$pf"
  ( cd "$M" && python3 -B "$GR" raise-check --old "$oldarg" --new "$newf" --paths "$pf" --guard-same "$4" >/dev/null 2>&1 ); return $?
}
OFF="$(rj off off off off 21600)"; L3ON="$(rj off off on off 21600)"; L3B="$(rj off off on on 21600)"; BON="$(rj off off off on 21600)"
INM=$'.agents/gate-rules.json\nuniversal-agent-devkit/bin/l3_gate.py\ntests/super-board/test_merge_gate_l3_x.sh\n'
rck "$OFF" "$L3ON" "$INM" 1; r=$?;                                     chk "11 ok. bật L3, chỉ chạm manifest ⇒ 0" '[ "$r" -eq 0 ]' "rc=$r"
rck "$OFF" "$L3ON" "$INM" 0; r=$?;                                     chk "11 c1. bật L3 mà guard đổi ⇒ 10" '[ "$r" -eq 10 ]' "rc=$r"
rck "$OFF" "$L3ON" $'.agents/gate-rules.json\nuniversal-agent-devkit/bin/gate_rules.py\n' 0; r=$?; chk "11 c1b. bật L3 và sửa gate_rules.py ⇒ 10" '[ "$r" -eq 10 ]' "rc=$r"
rck "$OFF" "$L3B" "$INM" 1; r=$?;                                      chk "11 c2a. bật L3 + B cùng lúc ⇒ 10" '[ "$r" -eq 10 ]' "rc=$r"
rck "$BON" "$L3ON" "$INM" 1; r=$?;                                     chk "11 c2b. bật L3 và hạ B ⇒ 10" '[ "$r" -eq 10 ]' "rc=$r"
rck "$OFF" "$L3ON" "$INM"$'universal-agent-devkit/bin/scoped_gate.py\n' 1; r=$?; chk "11 c3. chạm file ngoài MANIFEST[L3] ⇒ 10" '[ "$r" -eq 10 ]' "rc=$r"
rck "$OFF" "$L3ON" "$INM"$'universal-agent-devkit/bin/scoped_gate.py\n' 1; r=$?; chk "11 c4. trailer Freeze-exception không đổi kết quả (bộ kiểm không đọc commit) ⇒ 10" '[ "$r" -eq 10 ]' "rc=$r"
rck "$L3ON" "$OFF" $'.agents/gate-rules.json\nbất kỳ/file.txt\n' 0; r=$?; chk "11 off. on→off kèm file bất kỳ, guard đổi ⇒ 0" '[ "$r" -eq 0 ]' "rc=$r"
rck "$L3B" "$L3ON" $'x\n' 0; r=$?;                                     chk "11 off2. hạ B còn L3 giữ nguyên ⇒ 0" '[ "$r" -eq 0 ]' "rc=$r"
T21="$(rj off off off off 21600)"; T86="$(rj off off off off 86400)"; T36="$(rj off off off off 3600)"
rck "$T21" "$T86" $'.agents/gate-rules.json\nuniversal-agent-devkit/bin/suite_cache.py\n' 1; r=$?; chk "11 ttl. TTL 21600→86400 chỉ chạm MANIFEST[CACHE] ⇒ 0" '[ "$r" -eq 0 ]' "rc=$r"
rck "$T21" "$T86" $'.agents/gate-rules.json\nuniversal-agent-devkit/bin/l3_gate.py\n' 1; r=$?;    chk "11 ttl. TTL tăng mà chạm ngoài MANIFEST[CACHE] ⇒ 10" '[ "$r" -eq 10 ]' "rc=$r"
rck "$T86" "$T36" $'.agents/gate-rules.json\nbất kỳ\n' 0; r=$?;           chk "11 ttl. 86400→3600 (hạ) ⇒ 0" '[ "$r" -eq 0 ]' "rc=$r"
rck "$T21" "$(rj off off on off 86400)" "$INM" 1; r=$?;                 chk "11 ttl. TTL tăng cùng lúc bật L3 (2 khoá) ⇒ 10" '[ "$r" -eq 10 ]' "rc=$r"
rck - "$OFF" $'.agents/gate-rules.json\n' 0; r=$?;                      chk "11 new. file mới toàn off (không có bản cũ) ⇒ 0" '[ "$r" -eq 0 ]' "rc=$r"
rck - "$L3ON" "$INM" 1; r=$?;                                           chk "11 new. file mới bật L3 từ không có gì, trong manifest ⇒ 0" '[ "$r" -eq 0 ]' "rc=$r"
rck "$OFF" '{không phải json' $'x\n' 0; r=$?;                          chk "11 junk. bản mới là rác (mọi luật off) ⇒ 0" '[ "$r" -eq 0 ]' "rc=$r"
rck "$OFF" "$(rj off off shadow off 21600)" $'x\n' 0; r=$?;            chk "11 shadow. shadow không tính là bật ⇒ 0" '[ "$r" -eq 0 ]' "rc=$r"
rck "$OFF" "$L3ON" "" 1; r=$?;                                         chk "11 paths. diff rỗng (bật luật mà không có path nào) ⇒ 10 (đóng)" '[ "$r" -eq 10 ]' "rc=$r"
( cd "$M" && python3 -B "$GR" raise-check --old /nonexistent --new /nonexistent --paths /nonexistent --guard-same 1 >/dev/null 2>&1 ); r=$?
chk "11 err. đầu vào đọc không được ⇒ không raise (rc 0 hoặc 10, không traceback)" '[ "$r" -eq 0 ] || [ "$r" -eq 10 ]' "rc=$r"

echo
if [ "$fails" -eq 0 ]; then echo "test_gate_rules_flags: PASS"; exit 0; else echo "test_gate_rules_flags: FAIL ($fails)"; exit 1; fi
