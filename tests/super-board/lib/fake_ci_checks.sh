# shellcheck shell=bash
# Fixture dùng chung (A4, tách từ #742): merge gate giờ đọc CI (`gh pr checks <PR> --json name,state,bucket`) sau verify, trước
# migration và merge. gh giả của các test merge gate / merge train cũ chưa biết lệnh đó (trả "unexpected" → gate thoát 4). Fixture
# chỉ thêm đúng tiền điều kiện ấy, không đụng assertion nào:
#   sb_ci_checks_fixture <thư mục chứa gh giả>   (gọi sau khi test đã ghi và chmod gh giả của nó)
# Bọc gh giả: `gh pr checks …` → ${SB_FAKE_CI_JSON:-[]} (mặc định: không có check nào, gate merge như trước); lệnh khác → gh giả cũ
# (gh.inner). Gọi lại sau khi test ghi gh giả mới: bản mới thành gh.inner; wrapper đã có thì không bọc wrapper lần nữa.
sb_ci_checks_fixture() {
  local bin="$1"
  [ -x "$bin/gh" ] || { echo "sb_ci_checks_fixture: no fake gh in $bin" >&2; return 1; }
  grep -q '^# sb-ci-checks-fixture' "$bin/gh" 2>/dev/null || mv -f "$bin/gh" "$bin/gh.inner"
  cat > "$bin/gh" <<'SH'
#!/usr/bin/env bash
# sb-ci-checks-fixture wrapper
if [ "${1:-}" = pr ] && [ "${2:-}" = checks ]; then
  printf '%s\n' "${SB_FAKE_CI_JSON:-[]}"
  exit 0
fi
exec "$(dirname "$0")/gh.inner" "$@"
SH
  chmod +x "$bin/gh"
}
