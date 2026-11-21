#!/usr/bin/env bash
# Test hồi quy #1412: bể tài khoản (.claude/bin/super-board-account-pool.sh) chỉ dùng tài khoản Claude và khớp quota thật.
# 19/11 02:53 worker của finos_team chết vì "You've hit your weekly limit · resets Nov 22 at 12am"; runner ghi nó thành
# five_hour 100 % tới 22/11 00:00 trong usage-finos_team.json. Pool tin file đó trước quota sống, chép tiếp vào
# frozenUntil.finos_team (id cũ) và 21/11 16:36 vẫn coi tài khoản là PAUSE (còn 432 phút) dù /cc-switcher báo còn 35 %;
# `resolve` trả engine=antigravity. Lệnh chủ repo 21/11: chỉ tài khoản Claude, tài khoản ghim chạm ngưỡng thì pause.
# Offline: HOME giả, repo giả, switcher-state.json giả; không chạm ~/.claude, ~/.cc-switch thật. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POOL="$ROOT/.claude/bin/super-board-account-pool.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

[ -f "$POOL" ] || { echo "✖ thiếu $POOL (script pool phải nằm trong kit)"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-pool-1412.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SB_STATE_DIR="$TMP/state" SB_USAGE_SH="$ROOT/.claude/bin/super-board-usage.sh"
unset CLAUDE_CONFIG_DIR SB_FALLBACK_ANTIGRAVITY SB_FALLBACK_GROK AGY_BIN GROK_BIN
mkdir -p "$HOME/.claude-finos" "$HOME/.claude-finos_team" "$HOME/.claude-max" "$HOME/.claude-finos_lua" "$HOME/.cc-switch" \
  "$HOME/.local/bin" "$SB_STATE_DIR" "$TMP/repo/.claude" "$TMP/repo-agy/.claude"
# agy giả chạy được: bản cũ thấy nó là đổi sang Antigravity.
printf '#!/usr/bin/env bash\necho ran >> "%s/agy-ran"\n' "$TMP" > "$HOME/.local/bin/agy"; chmod +x "$HOME/.local/bin/agy"
echo '{"account":"finos_linh"}' > "$TMP/repo/.claude/settings.local.json"
echo '{"account":"antigravity_ultra"}' > "$TMP/repo-agy/.claude/settings.local.json"
STATE="$HOME/.cc-switch/switcher-state.json"
NOW=$(date +%s)

usage_file() {   # $1 acct, $2 window, $3 recorded_at, $4 resets_at
  jq -n --arg w "$2" --argjson rec "$3" --argjson r "$4" \
    '{recorded_at:$rec, source:"super-board-run worker log", rate_limits:{($w):{used_percentage:100, resets_at:$r}}}' > "$SB_STATE_DIR/usage-$1.json"
}
state_file() {   # $1 = 5h used %, $2 = 5h reset (giây, 0 = không có), $3 = tuần còn %, $4 = reset tuần (giây), $5 = frozenUntil JSON
  jq -n --argjson now "$NOW" --argjson used "$1" --argjson r5 "$2" --argjson wk "$3" --argjson rw "$4" --argjson fr "$5" '
    {frozenUntil:$fr, quotaCache:{finos_linh:{usedPct:$used, remainingPct:(100-$used), resetAtMs:($r5*1000),
      weeklyRemainingPct:$wk, weeklyResetAtMs:($rw*1000), updatedAtMs:(($now-30)*1000), source:"anthropic_oauth"}}}' > "$STATE"
}
resolve() { OUT=$(bash "$POOL" resolve "${1:-$TMP/repo}" 2>/dev/null); RC=$?; }
field() { printf '%s' "$OUT" | jq -r "$1" 2>/dev/null; }
reset_fixture() { rm -f "$SB_STATE_DIR"/usage-*.json "$STATE" "$TMP/agy-ran"; }

# ── 1. AC1 (đúng số liệu 21/11): quota sống còn 35 %, bản ghi five_hour cũ 2,5 ngày và frozenUntil dưới id cũ còn 432 phút.
reset_fixture
state_file 65 $((NOW + 2640)) 71 $((NOW + 25920)) "{\"finos_team\": $(( (NOW + 25920) * 1000 ))}"
usage_file finos_team five_hour $((NOW - 216000)) $((NOW + 25920))
resolve
[ "$RC" -eq 0 ] && [ "$(field .state)" = "ok" ] && [ "$(field .engine)" = "claude" ] && [ "$(field .account)" = "finos_team" ] \
  && ok "1: live quota 35 % left beats the stale five_hour record and the old-id freeze: pinned account, engine=claude" \
  || fail "1: stale freeze still wins: rc=$RC out=$OUT"

# ── 1b. Chỉ còn frozenUntil cũ dưới id cũ (không có file usage), dài hơn giờ reset 5 giờ thật: vẫn là tài khoản ghim.
reset_fixture
state_file 65 $((NOW + 2640)) 71 $((NOW + 25920)) "{\"finos_team\": $(( (NOW + 25920) * 1000 ))}"
resolve
[ "$RC" -eq 0 ] && [ "$(field .state)" = "ok" ] && [ "$(field .account)" = "finos_team" ] \
  && ok "1b: an old-id freeze that outlasts the real 5-hour reset is ignored when live quota is under the threshold" \
  || fail "1b: rc=$RC out=$OUT"

# ── 2. Bản ghi five_hour không bao giờ dài hơn 5 giờ kể từ lúc ghi (không cần quota sống).
reset_fixture
usage_file finos_team five_hour $((NOW - 21600)) $((NOW + 36000))
resolve
[ "$RC" -eq 0 ] && [ "$(field .state)" = "ok" ] \
  && ok "2a: a five_hour record older than 5 hours has expired whatever resets_at it carries" \
  || fail "2a: rc=$RC out=$OUT"
usage_file finos_team five_hour $((NOW - 3600)) $((NOW + 108000))
resolve
r=$(field '.resets_at // 0')
[ "$RC" -eq 10 ] && [ "$(field .state)" = "pause" ] && [ "$r" -gt "$NOW" ] && [ "$r" -le $((NOW + 14400)) ] \
  && ok "2b: a five_hour record 1 hour old pauses for at most the 4 hours left of its window" \
  || fail "2b: rc=$RC resets_at=$r out=$OUT"

# ── 2c. Worker vừa chết trong cửa sổ 5 giờ hiện tại: giữ pause tới giờ reset thật dù quota sống báo còn %, và
# frozenUntil được chép dưới id mới (finos_linh), không còn id cũ.
reset_fixture
state_file 65 $((NOW + 2640)) 71 $((NOW + 25920)) '{}'
usage_file finos_team five_hour $((NOW - 60)) $((NOW + 7200))
resolve
r=$(field '.resets_at // 0')
[ "$RC" -eq 10 ] && [ "$(field .window)" = "five_hour" ] && [ "$r" -gt "$NOW" ] && [ "$r" -le $((NOW + 2640)) ] \
  && ok "2c: a death inside the current 5-hour window pauses until the real reset, never past it" \
  || fail "2c: rc=$RC resets_at=$r (real reset $((NOW + 2640))) out=$OUT"
[ "$(jq -r '.frozenUntil.finos_linh // 0' "$STATE")" -gt 0 ] && [ "$(jq -r '.frozenUntil | has("finos_team")' "$STATE")" = "false" ] \
  && ok "2c: the freeze is mirrored under the new id finos_linh only" \
  || fail "2c: frozenUntil=$(jq -c .frozenUntil "$STATE")"

# ── 2d. Giới hạn tuần (runner ghi seven_day): pause tới giờ reset tuần, đúng loại cửa sổ.
reset_fixture
state_file 20 $((NOW + 2640)) 71 $((NOW + 172800)) '{}'
usage_file finos_team seven_day $((NOW - 3600)) $((NOW + 172800))
resolve
r=$(field '.resets_at // 0')
[ "$RC" -eq 10 ] && [ "$(field .window)" = "seven_day" ] && [ "$r" -eq $((NOW + 172800)) ] \
  && ok "2d: a weekly-limit record pauses until the weekly reset and is reported as seven_day" \
  || fail "2d: rc=$RC out=$OUT"

# ── 3. AC3: tài khoản ghim chạm ngưỡng ⇒ pause kèm resets_at; không Antigravity, không tài khoản Claude khác.
reset_fixture
state_file 97 $((NOW + 5400)) 71 $((NOW + 172800)) '{}'
resolve
r=$(field '.resets_at // 0')
[ "$RC" -eq 10 ] && [ "$(field .state)" = "pause" ] && [ "$r" -eq $((NOW + 5400)) ] && [ "$(field .engine)" = "claude" ] \
  && [ "$(field '.account // "none"')" = "none" ] && [ "$(field .preferred)" = "finos_team" ] \
  && ok "3a: pinned account at the threshold: state=pause with the live reset time, no other account" \
  || fail "3a: rc=$RC out=$OUT"
OUT=$(SB_FALLBACK_ANTIGRAVITY=1 SB_FALLBACK_GROK=1 bash "$POOL" resolve "$TMP/repo" 2>/dev/null); RC=$?
[ "$RC" -eq 10 ] && [ "$(field .state)" = "pause" ] && [ "$(field .engine)" = "claude" ] && [ ! -e "$TMP/agy-ran" ] \
  && ok "3b: the old fallback switches change nothing: still pause, never engine=antigravity" \
  || fail "3b: rc=$RC out=$OUT"

# ── 3c. Giới hạn tuần theo quota sống (tuần còn 2 %): pause tới giờ reset tuần.
reset_fixture
state_file 10 $((NOW + 5400)) 2 $((NOW + 172800)) '{}'
resolve
[ "$RC" -eq 10 ] && [ "$(field .window)" = "seven_day" ] && [ "$(field '.resets_at // 0')" -eq $((NOW + 172800)) ] \
  && ok "3c: live weekly quota at the threshold pauses until the weekly reset" \
  || fail "3c: rc=$RC out=$OUT"

# ── 3d. Repo ghim một profile Antigravity: pool vẫn chỉ trả tài khoản Claude.
reset_fixture
resolve "$TMP/repo-agy"
[ "$RC" -eq 0 ] && [ "$(field .engine)" = "claude" ] && [ ! -e "$TMP/agy-ran" ] \
  && ok "3d: a repo pinned to an Antigravity profile still resolves to a Claude account" \
  || fail "3d: rc=$RC out=$OUT"

# ── 3e. Máy chưa dựng bộ nhiều tài khoản (không có ~/.claude-<account> nào): pool không chặn runner, worker dùng claude mặc định.
OUT=$(HOME="$TMP/empty-home" bash "$POOL" resolve "$TMP/repo" 2>/dev/null); RC=$?
[ "$RC" -eq 0 ] && [ "$(field .state)" = "ok" ] && [ "$(field .engine)" = "claude" ] && [ "$(field '.account // "none"')" = "none" ] \
  && [ "$(field '.config_dir // "none"')" = "none" ] \
  && ok "3e: no account directories on the machine: ok with the default claude account, not a pause" \
  || fail "3e: rc=$RC out=$OUT"

# ── 3f. `exec`: máy không có thư mục tài khoản thì không đặt CLAUDE_CONFIG_DIR; có thì chạy lệnh với thư mục của tài khoản ghim.
reset_fixture
got=$(HOME="$TMP/empty-home" bash "$POOL" exec "$TMP/repo" -- sh -c 'echo "cfg=${CLAUDE_CONFIG_DIR:-unset}"' 2>/dev/null)
[ "$got" = "cfg=unset" ] && ok "3f: exec without account directories leaves CLAUDE_CONFIG_DIR unset" || fail "3f: exec (no dirs) printed '$got'"
got=$(bash "$POOL" exec "$TMP/repo" -- sh -c 'echo "cfg=$CLAUDE_CONFIG_DIR acct=$SB_ACTIVE_ACCOUNT"' 2>/dev/null)
[ "$got" = "cfg=$HOME/.claude-finos_team acct=finos_team" ] && ok "3f: exec runs the command on the pinned Claude account" || fail "3f: exec printed '$got'"

# ── 4. Không còn Grok: không chuỗi nào trong script, không dòng nào trong bảng status; status có đủ 4 tài khoản Claude.
grep -qi 'grok' "$POOL" && fail "4a: script còn chuỗi grok: $(grep -nci 'grok' "$POOL") dòng" || ok "4a: no grok string left in the pool script"
ST=$(cd "$TMP/repo" && bash "$POOL" status 2>&1)
printf '%s\n' "$ST" | grep -qi 'grok' && fail "4b: status còn dòng Grok" || ok "4b: status has no Grok row"
n=0; for a in finos finos_team max finos_lua; do printf '%s\n' "$ST" | grep -q "[★ ] $a " && n=$((n + 1)); done
[ "$n" -eq 4 ] && ok "4c: status lists the 4 Claude accounts" || fail "4c: status lists $n/4 Claude accounts"
printf '%s\n' "$ST" | grep -q 'AUTO #' && fail "4d: status còn dòng dự phòng tự động (AUTO #)" || ok "4d: status shows no automatic cross-vendor fallback"

# ── 5. Review đợt gộp #1416 (P2/P3 của #1412). Mọi lệnh ngoài (security, sqlite3) là bản giả đầu PATH: không chạm Keychain,
# không chạm ~/.cc-switch thật.
FAKE="$TMP/fakebin"; mkdir -p "$FAKE"
cat > "$FAKE/security" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG/security-argv"
case "${1:-}" in
  find-generic-password) printf '%s\n' "tok-SECRET-1412" ;;
  -i) cat >> "$FAKE_LOG/security-stdin" ;;
esac
exit 0
SH
cat > "$FAKE/sqlite3" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG/sqlite-argv"
case "$*" in
  *"SELECT name FROM providers"*"'antigravity'"*) echo "Antigravity Ultra — ultra@example.invalid (x)" ;;
  *"SELECT name FROM providers"*"'antigravity_pro'"*) echo "Antigravity Pro — pro@example.invalid (x)" ;;
esac
exit 0
SH
chmod +x "$FAKE/security" "$FAKE/sqlite3"
export FAKE_LOG="$TMP"
fpath() { PATH="$FAKE:$PATH" "$@"; }

# 5a. P2: có thư mục ~/.claude-<khác> nhưng thiếu thư mục của tài khoản GHIM ⇒ không phải "chạm ngưỡng": state=misconfigured,
# lý do nêu đúng thư mục thiếu, không có resets_at giả; exec không chạy lệnh.
H2="$TMP/home-missing"; mkdir -p "$H2/.claude-max" "$TMP/repo-lua/.claude"
echo '{"account":"finos_lua"}' > "$TMP/repo-lua/.claude/settings.local.json"
OUT=$(HOME="$H2" bash "$POOL" resolve "$TMP/repo-lua" 2>/dev/null); RC=$?
[ "$RC" -ne 0 ] && [ "$(field .state)" = "misconfigured" ] && printf '%s' "$(field .reason)" | grep -q 'missing ~/.claude-finos_lua' \
  && [ "$(field '.resets_at // "none"')" = "none" ] \
  && ok "5a: pinned account directory missing: state=misconfigured naming ~/.claude-finos_lua, not a limit pause" \
  || fail "5a: rc=$RC out=$OUT"
got=$(HOME="$H2" bash "$POOL" exec "$TMP/repo-lua" -- sh -c 'echo ran' 2>/dev/null); rc=$?
[ "$rc" -ne 0 ] && [ "$got" != "ran" ] && ok "5a: exec refuses to run on a misconfigured pool" || fail "5a: exec rc=$rc printed '$got'"

# 5b. P3: `switch <repo> <target>` đi qua cùng whitelist với dạng một đối số: đích lạ bị từ chối TRƯỚC mọi lần ghi (không gọi
# sqlite3, không ghi active-account); đích hợp lệ vẫn chạy.
: > "$HOME/.cc-switch/cc-switch.db"; rm -f "$TMP/sqlite-argv" "$SB_STATE_DIR/active-account"
fpath bash "$POOL" switch "$TMP/repo" "x' OR 1=1; --" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && [ ! -e "$TMP/sqlite-argv" ] && [ ! -e "$SB_STATE_DIR/active-account" ] \
  && ok "5b: two-argument switch rejects a target outside the whitelist before any write" \
  || fail "5b: rc=$rc sqlite='$(cat "$TMP/sqlite-argv" 2>/dev/null)' active='$(cat "$SB_STATE_DIR/active-account" 2>/dev/null)'"
fpath bash "$POOL" switch "$TMP/repo" 2 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q "id = 'finos_team'" "$TMP/sqlite-argv" 2>/dev/null && [ "$(cat "$SB_STATE_DIR/active-account" 2>/dev/null)" = "finos_team" ] \
  && ok "5b: two-argument switch with a whitelisted alias still switches (2 -> finos_team)" \
  || fail "5b: valid two-arg switch rc=$rc sqlite='$(cat "$TMP/sqlite-argv" 2>/dev/null)'"
rm -f "$HOME/.cc-switch/cc-switch.db"

# 5c. P3: lượt kiểm tra paused không ghi lại switcher-state.json khi frozenUntil không đổi (cc-switcher-mcp ghi file mỗi 30 s).
reset_fixture
state_file 65 $((NOW + 2640)) 71 $((NOW + 25920)) '{}'
usage_file finos_team five_hour $((NOW - 60)) $((NOW + 7200))
resolve
ino1=$(ls -i "$STATE" | awk '{print $1}')
resolve
ino2=$(ls -i "$STATE" | awk '{print $1}')
[ "$RC" -eq 10 ] && [ -n "$ino1" ] && [ "$ino1" = "$ino2" ] \
  && ok "5c: a second paused check leaves switcher-state.json untouched (same inode)" \
  || fail "5c: rc=$RC inode $ino1 -> $ino2 (file rewritten with no change)"

# 5d. P3: token OAuth không nằm trong argv của `security` (ps thấy được); vẫn tới Keychain qua stdin (`security -i`, dạng hex).
# Tên dịch vụ Keychain lấy từ sha256 của thư mục tài khoản (cách Claude Code đặt tên), không chép cứng.
rm -f "$TMP/security-argv" "$TMP/security-stdin"
fpath bash "$POOL" switch finos >/dev/null 2>&1; rc=$?
hex=$(printf '%s' "tok-SECRET-1412" | od -An -v -tx1 | tr -d ' \n')
svc="Claude Code-credentials-$(printf '%s' "$HOME/.claude-finos" | shasum -a 256 | cut -c1-8)"
[ "$rc" -eq 0 ] && [ -s "$TMP/security-argv" ] && ! grep -q "tok-SECRET-1412" "$TMP/security-argv" && ! grep -qi "$hex" "$TMP/security-argv" \
  && ok "5d: the credential never appears in security's argv" \
  || fail "5d: rc=$rc argv='$(cat "$TMP/security-argv" 2>/dev/null)'"
grep -q "add-generic-password" "$TMP/security-stdin" 2>/dev/null && grep -qi "$hex" "$TMP/security-stdin" \
  && ok "5d: the credential reaches security through stdin" \
  || fail "5d: stdin='$(cat "$TMP/security-stdin" 2>/dev/null)'"
grep -qF "find-generic-password -s $svc -w" "$TMP/security-argv" \
  && ok "5d: Keychain service derived from sha256(~/.claude-finos)" || fail "5d: no lookup of '$svc' in '$(cat "$TMP/security-argv" 2>/dev/null)'"

# 5e. P3: script được chép sang mọi repo board: không còn email cá nhân, mã Keychain chép cứng hay đường dẫn tuyệt đối của chủ máy.
if grep -nE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z.]+|credentials-[0-9a-f]{8}|/Volumes/' "$POOL" >/dev/null; then
  fail "5e: personal data left in the pool script: $(grep -nE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z.]+|credentials-[0-9a-f]{8}|/Volumes/' "$POOL" | cut -c1-80 | head -3 | tr '\n' ';')"
else
  ok "5e: no personal email, hardcoded Keychain id or absolute owner path in the pool script"
fi

# 5f. Nhãn tài khoản lấy từ ~/.claude-<acct>/.claude.json; danh sách repo lấy từ các project Claude có board config.
jq -n '{oauthAccount:{emailAddress:"team@example.invalid"}}' > "$HOME/.claude-finos_team/.claude.json"
mkdir -p "$TMP/repo/.claude/super-board/configs" "$TMP/repo/.claude/worktrees/issue-1-build/.claude/super-board/configs"
echo '{"account":"finos_linh"}' > "$TMP/repo/.claude/worktrees/issue-1-build/.claude/settings.local.json"
jq -n --arg a "$TMP/repo" --arg b "$TMP/repo/.claude/worktrees/issue-1-build" --arg c "$TMP/repo-agy" \
  '{projects:{($a):{}, ($b):{}, ($c):{}}}' > "$HOME/.claude.json"
reset_fixture
ST=$(cd "$TMP/repo" && bash "$POOL" status 2>&1)
row=$(printf '%s\n' "$ST" | grep '[★ ] finos_team ')
printf '%s' "$row" | grep -q 'team@example.invalid' && printf '%s' "$row" | grep -q '(1 repos' \
  && ok "5f: status label comes from the account's .claude.json; repo count from board repos in the Claude project list (worktrees skipped)" \
  || fail "5f: row='$row'"

# 5g. Email Google của Antigravity lấy từ tên provider trong cc-switch.db, không chép cứng.
: > "$HOME/.cc-switch/cc-switch.db"
fpath bash "$POOL" switch antigravity_pro >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(jq -r .active "$HOME/.gemini/google_accounts.json" 2>/dev/null)" = "pro@example.invalid" ] \
  && [ "$(jq -r '.old[0]' "$HOME/.gemini/google_accounts.json" 2>/dev/null)" = "ultra@example.invalid" ] \
  && ok "5g: Antigravity Google account emails come from the cc-switch provider names" \
  || fail "5g: rc=$rc google_accounts=$(cat "$HOME/.gemini/google_accounts.json" 2>/dev/null)"
rm -f "$HOME/.cc-switch/cc-switch.db"

[ "$FAILS" -eq 0 ] && echo "✅ test_account_pool_1412: all passed" || { echo "❌ test_account_pool_1412: $FAILS failed"; exit 1; }
