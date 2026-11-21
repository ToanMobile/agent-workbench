#!/usr/bin/env bash
# super-board-account-pool.sh (also invoked via `ccswitch`)
# Claude-only account pool (#1412, lệnh chủ repo 21/11): mỗi repo chỉ chạy bằng tài khoản Claude đã ghim; tài khoản ghim
# chạm ngưỡng thì `resolve` trả state=pause kèm resets_at, KHÔNG đổi sang tài khoản Claude khác, Antigravity hay hãng khác.
#   1. finos            -> ~/.claude-finos         | FinOS Org (toan.huynh@finos.asia)
#   2. finos_team       -> ~/.claude-finos_team    | FinOS Team (linhnt@finos.asia)
#   3. max              -> ~/.claude-max           | Personal 5x Max (toan.huynh@finos.asia)
#   7. finos_lua        -> ~/.claude-finos_lua     | FinOS Lua (ngoclua892@gmail.com)
# Antigravity (antigravity, antigravity_pro) chỉ còn là đích chọn tay của `switch`; trong vai reviewer nó đi qua antigravity-pm.

set -euo pipefail

POOL_ACCOUNTS=("finos" "finos_team" "max" "finos_lua")
SB_DIR="${SB_STATE_DIR:-$HOME/.claude/super-board}"
# Script usage nằm cạnh file này trong kit; gọi qua symlink `ccswitch` (không có script anh em) thì dùng bản ở ~/.claude/bin.
USAGE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/super-board-usage.sh"
[ -f "$USAGE_SH" ] || USAGE_SH="$HOME/.claude/bin/super-board-usage.sh"
USAGE_SH="${SB_USAGE_SH:-$USAGE_SH}"
AGY_BIN="${AGY_BIN:-$HOME/.local/bin/agy}"
mkdir -p "$SB_DIR"

usage_file_for() { echo "$SB_DIR/usage-${1}.json"; }

keychain_service_for() {
  case "$1" in
    finos)      echo "Claude Code-credentials-08fc04bc" ;;
    finos_team) echo "Claude Code-credentials-25aa58cc" ;;
    max)        echo "Claude Code-credentials-0f12add9" ;;
    finos_lua)  echo "Claude Code-credentials-5a4c5915" ;;
    *)          echo "" ;;
  esac
}

account_label() {
  case "$1" in
    finos)            echo "toan.huynh@finos.asia [FinOS]" ;;
    finos_team)       echo "linhnt@finos.asia [FinOS Team]" ;;
    max)              echo "toan.huynh@finos.asia [5x Max]" ;;
    finos_lua)        echo "ngoclua892@gmail.com [FinOS Lua]" ;;
    antigravity)      echo "phathuy.vetgo@gmail.com [Ultra]" ;;
    antigravity_pro)  echo "alex.1993.dev@gmail.com [Pro]" ;;
    *)                echo "$1" ;;
  esac
}

set_antigravity_google_account() {
  local acct="$1" active_email="phathuy.vetgo@gmail.com" old_email="alex.1993.dev@gmail.com"
  if [ "$acct" = "antigravity_pro" ]; then
    active_email="alex.1993.dev@gmail.com"
    old_email="phathuy.vetgo@gmail.com"
  fi
  mkdir -p "$HOME/.gemini/antigravity-cli"
  printf '{\n  "active": "%s",\n  "old": [\n    "%s"\n  ]\n}\n' "$active_email" "$old_email" > "$HOME/.gemini/google_accounts.json"
  printf '{\n  "model": "gemini-4-argon-high",\n  "effort": "xhigh",\n  "activeAccount": "%s"\n}\n' "$active_email" > "$HOME/.gemini/antigravity-cli/settings.json"
}

_detect_current_account_raw() {
  local repo="${1:-$PWD}"
  local acct=""
  # 1. Ưu tiên tuyệt đối cấu hình cố định theo từng Repo (.claude/settings.local.json -> {"account": "finos" | "finos_team"})
  # Hỗ trợ kế thừa từ repo gốc khi đang đứng trong git worktree (.claude/worktrees/issue-*)
  # Đặt TRƯỚC CLAUDE_CONFIG_DIR để khi super-board-run.sh được gọi từ một shell cha có sẵn CLAUDE_CONFIG_DIR cũ,
  # nó vẫn luôn tuân thủ đúng tài khoản đã gắn cho Repo đó.
  if [ -d "$repo" ] && command -v jq >/dev/null 2>&1; then
    local root common_dir f
    root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || echo "$repo")"
    common_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    for f in "$repo/.claude/settings.local.json" "$root/.claude/settings.local.json" "${common_dir:+$(dirname "$common_dir")/.claude/settings.local.json}"; do
      [ -n "$f" ] && [ -f "$f" ] || continue
      acct="$(jq -r '.account // empty' "$f" 2>/dev/null || true)"
      if [ -n "$acct" ]; then
        echo "$acct"
        return 0
      fi
    done
  fi
  # 2. Nếu repo không ghim cố định thì mới xét biến môi trường CLAUDE_CONFIG_DIR
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    local base
    base="$(basename "$CLAUDE_CONFIG_DIR")"
    case "$base" in
      .claude-*) echo "${base#.claude-}"; return 0 ;;
    esac
  fi
  # 3. Fallback về cấu hình toàn cục của cc-switch
  local cc_cfg="$HOME/.cc-switch/settings.json"
  if [ -f "$cc_cfg" ] && command -v jq >/dev/null 2>&1; then
    acct="$(jq -r '.currentProviderClaude // empty' "$cc_cfg" 2>/dev/null || true)"
  fi
  if [ -z "$acct" ] && [ -f "$SB_DIR/active-account" ]; then
    acct="$(cat "$SB_DIR/active-account" 2>/dev/null || true)"
  fi
  echo "${acct:-finos}"
}

# cc-switcher da doi id (finos->finos_toan, finos_team->finos_linh, max->finos_toan_max, antigravity->antigravity_ultra) nhung thu muc
# ~/.claude-finos... va khoa Keychain van theo ten cu (Keychain luu dang nhap theo sha256 duong dan). Ghim account moi duoc doi ve ten cu
# tai day de moi ham ben duoi (thu muc, quota, ordered_pool_for, antigravity) khong phai biet id moi.
normalize_account() {
  case "$1" in
    finos_toan)        echo "finos" ;;
    finos_linh)        echo "finos_team" ;;
    finos_toan_max)    echo "max" ;;
    antigravity_ultra) echo "antigravity" ;;
    *)                 echo "$1" ;;
  esac
}

detect_current_account() {
  normalize_account "$(_detect_current_account_raw "$@")"
}

# Id moi cua cung tai khoan (ten cu -> id cc-switcher). switcher-state.json do cc-switcher ghi chi con khoa id moi.
alt_account() {
  case "$1" in
    finos)       echo "finos_toan" ;;
    finos_team)  echo "finos_linh" ;;
    max)         echo "finos_toan_max" ;;
    antigravity) echo "antigravity_ultra" ;;
    *)           echo "$1" ;;
  esac
}

account_email() {
  local acct="$1"
  case "$acct" in
    antigravity)     echo "phathuy.vetgo@gmail.com"; return 0 ;;
    antigravity_pro) echo "alex.1993.dev@gmail.com"; return 0 ;;
  esac
  local cfg="$HOME/.claude-${acct}/.claude.json"
  if [ -f "$cfg" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.oauthAccount.emailAddress // "unknown"' "$cfg" 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

check_account_quota() {
  local acct="$1" threshold="${2:-95}" ufile state_file out="" rc=0 alt now live="null"
  ufile="$(usage_file_for "$acct")"
  state_file="$HOME/.cc-switch/switcher-state.json"
  alt="$(alt_account "$acct")"
  now="$(date +%s)"
  # Quota sống của tài khoản (cc-switcher-mcp đo từ Anthropic OAuth API, ghi vào switcher-state.json dưới id mới).
  if [ -f "$state_file" ] && command -v jq >/dev/null 2>&1; then
    live="$(jq -c --arg a "$acct" --arg b "$alt" '(.quotaCache[$a] // .quotaCache[$b] // null)' "$state_file" 2>/dev/null || true)"
    [ -n "$live" ] || live="null"
  fi

  # 1. Kiểm tra file usage-<acct>.json trước: nếu worker của Super-Board vừa chết vì chạm limit,
  # note_worker_limit() trong super-board-run.sh ghi ngay used_percentage=100 kèm resets_at vào file này (five_hour hoặc
  # seven_day). Bản ghi chỉ có giá trị trong đúng cửa sổ của nó (#1412: 19/11 một giới hạn tuần bị ghi thành five_hour tới
  # 22/11 và pool giữ PAUSE 432 phút dù cửa sổ 5 giờ thật còn 35 %):
  #   - five_hour không bao giờ dài hơn 5 giờ kể từ lúc ghi;
  #   - quota sống đo SAU bản ghi (và mới ≤ 15 phút) cho biết cửa sổ thật: bản ghi thuộc cửa sổ đã kết thúc thì bỏ, còn trong
  #     cửa sổ hiện tại thì giữ tới min(resets_at của bản ghi, giờ reset thật). Worker vừa chết trong cửa sổ hiện tại vẫn
  #     thắng số % sống (tránh vòng giao-chết-giao).
  if [ -f "$ufile" ]; then
    out="$(SB_USAGE_FILE="$ufile" bash "$USAGE_SH" check --threshold "$threshold" 2>/dev/null)" || rc=$?
    if [ "$rc" -eq 10 ]; then
      local rec
      rec="$(jq -r '.recorded_at // 0 | floor' "$ufile" 2>/dev/null || echo 0)"
      out="$(printf '%s' "$out" | jq -c --argjson now "$now" --argjson rec "${rec:-0}" --argjson q "$live" '
        (if .window == "seven_day" then 604800 else 18000 end) as $len
        | (((if .window == "seven_day" then ($q.weeklyResetAtMs // 0) else ($q.resetAtMs // 0) end) / 1000) | floor) as $live_reset
        | (($q.updatedAtMs // 0) / 1000) as $measured
        | ($q != null and $measured > $rec and ($now - $measured) <= 900) as $fresh
        | (if .window == "five_hour" and $rec > 0 then ([.resets_at, $rec + 18000] | min) else .resets_at end) as $cap
        | (if $fresh and (.window == "five_hour" or $live_reset > 0) then
             (if ($live_reset <= $now or $rec < ($live_reset - $len)) then 0 else ([$cap, $live_reset] | min) end)
           else $cap end) as $until
        | if $until > $now then .resets_at = $until
          else {state:"ok", window:null, used:0, resets_at:null, age:.age, reason:"recorded limit expired: its \(.window) window has ended"} end
      ' 2>/dev/null || printf '%s' "$out")"
      if [ "$(printf '%s' "$out" | jq -r '.state // "pause"' 2>/dev/null)" = "pause" ]; then
        if [ -f "$state_file" ] && command -v jq >/dev/null 2>&1; then
          local u_reset_ms stmp
          u_reset_ms="$(echo "$out" | jq -r 'if (.resets_at // 0) > 0 then ((.resets_at | tonumber) * 1000) else 0 end' 2>/dev/null || echo 0)"
          if [ "${u_reset_ms:-0}" -gt 0 ]; then
            # Chép mốc dưới id mới của cc-switcher; khoá id cũ do bản trước ghi bị gỡ (cc-switcher gộp hai khoá theo mốc lớn hơn).
            stmp="$state_file.tmp.$$"
            jq --arg a "$alt" --arg old "$acct" --argjson r "$u_reset_ms" \
              '(if ((.frozenUntil[$a] // 0) < $r) then .frozenUntil[$a] = $r else . end)
               | if $old != $a then del(.frozenUntil[$old]) else . end' \
              "$state_file" > "$stmp" 2>/dev/null && mv "$stmp" "$state_file" 2>/dev/null || rm -f "$stmp"
          fi
        fi
        echo "$out"
        return 10
      fi
      rc=0
    fi
  fi

  # 2. Kiểm tra dữ liệu Quota thực tế từ Anthropic OAuth API & frozenUntil do cc-switcher-mcp đồng bộ mỗi 30s.
  # Quota sống quyết định trước (5 giờ và tuần). Mốc frozenUntil chỉ giữ khi không mâu thuẫn với quota sống: quota còn mới,
  # dưới ngưỡng, mà mốc đóng băng dài hơn giờ reset 5 giờ thật thì mốc đó là mốc cũ (#1412), bỏ qua như syncLiveQuotas làm.
  if [ -f "$state_file" ] && command -v jq >/dev/null 2>&1; then
    local now_ms live_json live_state
    now_ms=$(( now * 1000 ))
    live_json="$(jq -c --arg a "$acct" --arg b "$alt" --argjson now "$now_ms" --argjson th "$threshold" '
      ([(.frozenUntil[$a] // 0), (.frozenUntil[$b] // 0)] | max) as $frozen
      | (.quotaCache[$a] // .quotaCache[$b] // null) as $q
      | ($q != null and ($q.updatedAtMs // 0) > 0) as $has
      | ($has and ($now - ($q.updatedAtMs // 0)) <= 900000) as $fresh
      | ($q.resetAtMs // 0) as $rm
      | ($q.weeklyResetAtMs // 0) as $wm
      | (if $has then (if ($rm > 0 and $rm <= $now) then 0 else ($q.usedPct // (100 - ($q.remainingPct // 100))) end) else 0 end) as $used
      | (if ($has and $q.weeklyRemainingPct != null and $wm > $now) then (100 - $q.weeklyRemainingPct) else 0 end) as $wused
      | (if $rm > $now then (($rm / 1000) | floor) else null end) as $resets
      | if ($has and $wused >= $th) then
          {state:"pause", window:"seven_day", used:$wused, resets_at:(($wm / 1000) | floor), age:0, reason:"live oauth weekly quota >= threshold"}
        elif ($has and $used >= $th and ($rm == 0 or $rm > $now)) then
          {state:"pause", window:"five_hour", used:$used, resets_at:$resets, age:0, reason:"live oauth quota >= threshold"}
        elif ($frozen > $now and (($fresh and $frozen > ([$rm, $now] | max)) | not)) then
          {state:"pause", window:"five_hour", used:100, resets_at:(($frozen / 1000) | floor), age:0, reason:"frozen in switcher-state.json"}
        elif $has then
          {state:"ok", window:"five_hour", used:$used, resets_at:$resets, age:0, reason:"live oauth quota ok"}
        else empty end
    ' "$state_file" 2>/dev/null || true)"
    if [ -n "$live_json" ]; then
      live_state="$(echo "$live_json" | jq -r '.state // "ok"')"
      echo "$live_json"
      [ "$live_state" = "pause" ] && return 10 || return 0
    fi
  fi

  if [ ! -f "$ufile" ]; then
    echo '{"state":"ok","window":null,"used":0,"resets_at":null,"age":null,"reason":"ready (no limit hit recorded)"}'
    return 0
  fi
  if [ "$rc" -eq 3 ]; then
    echo "$out" | jq -c '.state = "ok"'
    return 0
  fi
  echo "$out"
  return "$rc"
}

ordered_pool_for() {
  local preferred="$1"
  # Chế độ Anti-Ban (Cô lập cứng theo Repo): Mỗi nhóm repo chỉ dùng duy nhất tài khoản Claude đã ghim
  # (Nhóm 1: finos, Nhóm 2: finos_team), TUYỆT ĐỐI KHÔNG nhảy chéo sang tài khoản Claude khác khi chạm limit.
  case "$preferred" in
    finos|finos_team|max|finos_lua)
      printf '%s\n' "$preferred"
      return 0
      ;;
  esac
  printf '%s\n' "finos"
}

cmd_record() {
  local acct="${1:-}" payload
  [ -n "$acct" ] || acct="$(detect_current_account "$PWD")"
  payload="$(cat)"
  printf '%s' "$payload" | SB_USAGE_FILE="$(usage_file_for "$acct")" bash "$USAGE_SH" record
  printf '%s' "$payload" | SB_USAGE_FILE="$SB_DIR/usage.json" bash "$USAGE_SH" record
}

cmd_resolve() {
  local repo="$PWD" threshold=95
  while [ $# -gt 0 ]; do
    case "$1" in
      --threshold) threshold="$2"; shift 2 ;;
      *) repo="$1"; shift ;;
    esac
  done
  local preferred
  preferred="$(detect_current_account "$repo")"
  # #1412 (lệnh chủ repo 21/11): chỉ tài khoản Claude. Repo ghim một profile không phải Claude cũng đi qua ordered_pool_for
  # (trả finos); không còn nhánh trả engine=antigravity.
  # Máy không có thư mục ~/.claude-<account> nào (chưa dựng bộ nhiều tài khoản): pool không can thiệp, worker dùng tài khoản
  # claude mặc định như lúc script này chưa nằm trong kit.
  local any_dir=0 a
  for a in "${POOL_ACCOUNTS[@]}"; do [ -d "$HOME/.claude-${a}" ] && any_dir=1; done
  if [ "$any_dir" -eq 0 ]; then
    jq -n --arg preferred "$preferred" \
      '{state:"ok", engine:"claude", account:null, preferred:$preferred, rotated:false, config_dir:null, reason:"no ~/.claude-<account> directory on this machine; default claude account"}'
    return 0
  fi
  local earliest_reset="" pause_window="" acct qjson qstate qreset
  while IFS= read -r acct; do
    [ -d "$HOME/.claude-${acct}" ] || continue
    set +e; qjson="$(check_account_quota "$acct" "$threshold")"; set -e
    qstate="$(echo "$qjson" | jq -r '.state // "ok"')"
    if [ "$qstate" != "pause" ]; then
      local rotated="false"
      [ "$acct" != "$preferred" ] && rotated="true"
      jq -n --arg engine "claude" --arg account "$acct" --arg preferred "$preferred" \
        --arg config_dir "$HOME/.claude-${acct}" --arg email "$(account_email "$acct")" \
        --arg label "$(account_label "$acct")" --argjson rotated "$rotated" --argjson quota "$qjson" \
        '{state:"ok", engine:$engine, account:$account, preferred:$preferred, rotated:$rotated, config_dir:$config_dir, email:$email, label:$label, quota:$quota}'
      return 0
    fi
    qreset="$(echo "$qjson" | jq -r '.resets_at // empty')"
    if [ -n "$qreset" ] && { [ -z "$earliest_reset" ] || [ "$qreset" -lt "$earliest_reset" ]; }; then
      earliest_reset="$qreset"
      pause_window="$(echo "$qjson" | jq -r '.window // empty')"
    fi
  done < <(ordered_pool_for "$preferred")

  # Tài khoản ghim chạm ngưỡng: pause tới giờ reset. Không có dự phòng khác hãng, không nhảy sang tài khoản Claude khác (#1412):
  # runner không giao worker cho repo này tới resets_at.
  jq -n --arg preferred "$preferred" --argjson resets_at "${earliest_reset:-null}" --arg window "$pause_window" \
    '{state:"pause", engine:"claude", account:null, preferred:$preferred, resets_at:$resets_at, window:(if $window == "" then null else $window end), reason:"pinned Claude account is >= threshold; Claude-only pool: no dispatch for this repo until the reset"}'
  return 10
}

cmd_status() {
  local threshold="${1:-95}" current
  current="$(detect_current_account "$PWD")"
  echo "╭─────────────────┬──────────────────────────────────┬──────────┬──────────┬──────────────────────────────────────╮"
  echo "│ ACCOUNT         │ EMAIL / PLAN / ENGINE            │ QUOTA    │ STATUS   │ CONFIG & REPO ASSIGNMENT             │"
  echo "├─────────────────┼──────────────────────────────────┼──────────┼──────────┼──────────────────────────────────────┤"
  local acct qjson used state label shared_ok marker rcount d r_acct
  for acct in "${POOL_ACCOUNTS[@]}"; do
    label="$(account_label "$acct")"
    set +e; qjson="$(check_account_quota "$acct" "$threshold")"; set -e
    used="$(echo "$qjson" | jq -r 'if .used != null then "\(.used)%" else "0%" end')"
    state="$(echo "$qjson" | jq -r '.state // "ok"' | tr '[:lower:]' '[:upper:]')"
    rcount=0
    for d in \
      /Volumes/Data/Toan/agent-workbench \
      /Volumes/Data/Toan/OfficeReader/OfficeReader \
      /Volumes/Data/Toan/Game/Neighbours-From-Hell \
      /Volumes/Data/Toan/GeelyEx2 \
      /Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D \
      /Volumes/Data/Toan/Game/Humans-vs.-UFOs; do
      if [ -f "$d/.claude/settings.local.json" ] && command -v jq >/dev/null 2>&1; then
        r_acct="$(jq -r '.account // empty' "$d/.claude/settings.local.json" 2>/dev/null || true)"
        [ "$(normalize_account "$r_acct")" = "$acct" ] && rcount=$((rcount + 1))
      fi
    done
    if [ "$rcount" -gt 0 ]; then
      shared_ok="~/.claude-${acct} (${rcount} repos · isolated ✔)"
      [ "$state" = "OK" ] && state="ACTIVE"
    elif [ -L "$HOME/.claude-${acct}/projects" ] && [ -L "$HOME/.claude-${acct}/sessions" ]; then
      shared_ok="~/.claude-${acct} (manual standby ✔)"
    else
      shared_ok="~/.claude-${acct} (isolated)"
    fi
    marker="  $acct"
    if [ "$acct" = "$current" ] || { [ "$rcount" -gt 0 ] && [ "$state" != "PAUSE" ]; }; then
      marker="★ $acct"
    fi
    printf "│ %-15s │ %-32s │ %-8s │ %-8s │ %-36s │\n" "$marker" "$label" "$used" "$state" "$shared_ok"
  done
  # Antigravity không còn là dự phòng tự động (#1412): chỉ là đích chọn tay của `switch`.
  if [ -x "$AGY_BIN" ]; then
    marker="  antigravity"; [ "$current" = "antigravity" ] && marker="★ antigravity"
    printf "│ %-15s │ %-32s │ %-8s │ %-8s │ %-36s │\n" "$marker" "$(account_label antigravity)" "N/A" "MANUAL" "~/.gemini/antigravity (chọn tay)"
    marker="  antigravity_pro"; [ "$current" = "antigravity_pro" ] && marker="★ antigravity_pro"
    printf "│ %-15s │ %-32s │ %-8s │ %-8s │ %-36s │\n" "$marker" "$(account_label antigravity_pro)" "N/A" "MANUAL" "~/.gemini/antigravity (chọn tay)"
  fi
  echo "╰─────────────────┴──────────────────────────────────┴──────────┴──────────┴──────────────────────────────────────╯"
}

sync_global_claude_credentials() {
  local target="$1" src_cfg="$HOME/.claude-${1}/.claude.json" svc
  svc="$(keychain_service_for "$target")"
  if [ "$target" = "antigravity" ] || [ "$target" = "antigravity_pro" ]; then
    set_antigravity_google_account "$target"
  fi
  if [ -f "$src_cfg" ]; then
    cp "$src_cfg" "$HOME/.claude.json" 2>/dev/null || true
    cp "$src_cfg" "$HOME/.claude/.claude.json" 2>/dev/null || true
  fi
  if [ -n "$svc" ]; then
    local cred=""
    cred="$(security find-generic-password -s "$svc" -w 2>/dev/null || true)"
    if [ -n "$cred" ]; then
      security add-generic-password -U -s "Claude Code-credentials" -a "$(id -un)" -w "$cred" >/dev/null 2>&1 || true
    fi
  fi
  if [ -f "$HOME/.cc-switch/cc-switch.db" ] && command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$HOME/.cc-switch/cc-switch.db" \
      "UPDATE providers SET is_current = CASE WHEN id = '$target' THEN 1 ELSE 0 END WHERE app_type = 'claude';" 2>/dev/null || true
    if [ "$target" = "antigravity" ] || [ "$target" = "antigravity_pro" ]; then
      sqlite3 "$HOME/.cc-switch/cc-switch.db" \
        "UPDATE providers SET is_current = CASE WHEN id = '$target' THEN 1 ELSE 0 END WHERE app_type = 'gemini';" 2>/dev/null || true
    fi
  fi
  if [ -f "$HOME/.cc-switch/settings.json" ] && command -v jq >/dev/null 2>&1; then
    local stmp="$HOME/.cc-switch/settings.json.tmp.$$"
    jq --arg t "$target" '.currentProviderClaude = $t | .showProfileSwitcher = true | .enableFailoverToggle = true' \
      "$HOME/.cc-switch/settings.json" > "$stmp" && mv "$stmp" "$HOME/.cc-switch/settings.json"
  fi
  echo "$target" > "$SB_DIR/active-account"
}

cmd_switch() {
  local repo="$PWD" target=""
  if [ $# -eq 0 ]; then
    local cur; cur="$(detect_current_account "$PWD")"
    # Không đối số: vòng qua các tài khoản Claude; Antigravity phải gọi đích danh.
    case "$cur" in
      finos)       target="finos_team" ;;
      finos_team)  target="max" ;;
      max)         target="finos_lua" ;;
      *)           target="finos" ;;
    esac
  elif [ $# -eq 1 ]; then
    case "$1" in
      finos|1)                          target="finos" ;;
      finos_team|2)                     target="finos_team" ;;
      max|3)                            target="max" ;;
      finos_lua|7)                      target="finos_lua" ;;
      antigravity|agy|agy_ultra|4)      target="antigravity" ;;
      antigravity_pro|agy_pro|5)        target="antigravity_pro" ;;
      *) echo "error: invalid account '$1'" >&2; return 64 ;;
    esac
  else
    repo="$1"; target="$2"
    [ "$target" = "agy" ] || [ "$target" = "agy_ultra" ] && target="antigravity"
    [ "$target" = "agy_pro" ] && target="antigravity_pro"
  fi
  sync_global_claude_credentials "$target"
  echo "✔ Switched -> '$target' ($(account_label "$target"), 100% sessions preserved)"
}

cmd_exec() {
  local repo="$PWD"
  if [ $# -gt 0 ] && [ "$1" != "--" ]; then repo="$1"; shift; fi
  [ "${1:-}" = "--" ] && shift
  local resolved acct cfg_dir
  resolved="$(cmd_resolve "$repo")" || { echo "$resolved" >&2; return 10; }
  acct="$(echo "$resolved" | jq -r '.account // empty')"
  cfg_dir="$(echo "$resolved" | jq -r '.config_dir // empty')"
  # Máy không có thư mục tài khoản nào: chạy lệnh với tài khoản claude mặc định, không đặt CLAUDE_CONFIG_DIR.
  [ -n "$cfg_dir" ] || exec "$@"
  if [ "$(echo "$resolved" | jq -r '.rotated')" = "true" ]; then
    echo "🔄 [Multi-Account Pool] Auto-rotated from $(echo "$resolved" | jq -r '.preferred') -> $acct ($cfg_dir)" >&2
  fi
  export CLAUDE_CONFIG_DIR="$cfg_dir"
  export SB_ACTIVE_ACCOUNT="$acct"
  exec "$@"
}

MODE="${1:-status}"
[ $# -gt 0 ] && shift
case "$MODE" in
  status|list|--list|-l)                                                 cmd_status "$@" ;;
  resolve)                                                               cmd_resolve "$@" ;;
  record)                                                                cmd_record "$@" ;;
  switch|--switch|-s)                                                    cmd_switch "$@" ;;
  exec)                                                                  cmd_exec "$@" ;;
  finos|finos_team|max|finos_lua|antigravity|agy|agy_ultra|antigravity_pro|agy_pro) cmd_switch "$MODE" ;;
  *) echo "Usage: $(basename "$0") [status|list|switch [finos|finos_team|max|finos_lua|antigravity|antigravity_pro]|resolve|record|exec]" >&2; exit 64 ;;
esac
