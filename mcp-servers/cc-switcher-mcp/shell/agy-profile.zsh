# agy nhiều profile. Nạp bằng một dòng trong ~/.zshrc:  source <repo>/mcp-servers/cc-switcher-mcp/shell/agy-profile.zsh
# agy chỉ tách tài khoản qua HOME. Mỗi repo chọn tài khoản qua .claude/settings.local.json: {"agyAccount": "<tên>"}
# -> HOME=$HOME/.agy-<tên> (chỉ .gemini là thật, còn lại symlink về HOME thật). Khoá "account" của Claude không bị đụng.
_agy_repo_account() {
  local root common f val rc
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  common="${$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null):h}"
  for f in "$root/.claude/settings.local.json" "$common/.claude/settings.local.json"; do
    [[ -f $f ]] || continue
    if ! command -v jq >/dev/null 2>&1; then
      grep -q agyAccount "$f" 2>/dev/null && { print -u2 "❌ [agy] cần jq để đọc agyAccount trong $f"; return 1; }
      continue
    fi
    val=$(jq -er '.agyAccount // empty' "$f" 2>/dev/null); rc=$?
    [[ $rc == 5 ]] && { print -u2 "❌ [agy] $f không phải JSON hợp lệ"; return 1; }
    [[ -n $val ]] && { print -r -- "$val"; return 0; }
  done
  return 0
}

_agy_build_home() {
  # Idempotent, chạy mỗi lần agy(): thêm link còn thiếu; .gemini tạo SAU CÙNG nên build dở dang sẽ được làm lại.
  setopt localoptions nullglob globdots
  local h="${AGY_REAL_HOME:-$HOME}/.agy-$1" rh="${AGY_REAL_HOME:-$HOME}" e n
  mkdir -p "$h" || return 1
  for e in "$rh"/*; do
    n=${e:t}
    [[ $n == .gemini || $n == .agy-* ]] && continue
    if [[ -e $h/$n || -L $h/$n ]]; then
      [[ -L $h/$n ]] || print -u2 "⚠️  [agy] $h/$n là file thật, không còn đồng bộ với $e"
    else
      ln -sn "$e" "$h/$n"
    fi
  done
  mkdir -p "$h/.gemini"
}

agy() {
  local account real_home="${AGY_REAL_HOME:-$HOME}"
  account=$(_agy_repo_account) || return 1   # lỗi đọc cấu hình: dừng, không chạy nhầm tài khoản
  if [[ -z $account ]]; then command agy "$@"; return; fi
  if [[ ! $account =~ ^[A-Za-z0-9_-]+$ ]]; then print -u2 "❌ [agy] agyAccount \"$account\" không hợp lệ."; return 1; fi
  _agy_build_home "$account" || return 1
  print -u2 "⚡ [agy] Đang chạy với profile: $account (HOME=$real_home/.agy-$account)"
  AGY_REAL_HOME="$real_home" HOME="$real_home/.agy-$account" command agy "$@"
}

# agy-profile            -> xem profile agy của repo hiện tại
# agy-profile <tên>      -> đặt profile agy cho repo hiện tại và dựng HOME riêng (đăng nhập lần đầu: chạy agy trong repo)
agy-profile() {
  local root f tmp
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { print -u2 "agy-profile: không ở trong Git repo."; return 1; }
  f="$root/.claude/settings.local.json"
  if [[ -z $1 ]]; then print "Repo:    $root"; print "Profile: ${$(_agy_repo_account):-<chưa đặt: dùng ~/.gemini mặc định>}"; return 0; fi
  [[ $1 =~ ^[A-Za-z0-9_-]+$ ]] || { print -u2 "agy-profile: tên \"$1\" không hợp lệ."; return 1; }
  command -v jq >/dev/null 2>&1 || { print -u2 "agy-profile: cần jq."; return 1; }
  mkdir -p "$root/.claude" || return 1
  case $1 in antigravity|antigravity_pro) ;; *) print -u2 "⚠️  [agy-profile] \"$1\" không phải profile cc-switcher biết (antigravity, antigravity_pro).";; esac
  _agy_build_home "$1" || return 1
  if [[ -s $f ]]; then
    tmp="$f.tmp.$$"
    { jq --arg a "$1" '.agyAccount = $a' "$f" > "$tmp" && mv "$tmp" "$f"; } || { rm -f "$tmp"; print -u2 "agy-profile: $f không phải JSON hợp lệ, giữ nguyên."; return 1; }
  else
    printf '{\n  "agyAccount": "%s"\n}\n' "$1" > "$f" || return 1
  fi
  print "✅ $root -> agy profile: $1 (HOME=${AGY_REAL_HOME:-$HOME}/.agy-$1)"
}
