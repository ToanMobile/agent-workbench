#!/usr/bin/env bash
# #712: merge gate giữ scratch (#559) khi bộ test DevKit đỏ. REG-DK-ALL-01 đã tách thành 3 shard REG-DK-ALL-GATES-01 / -WORKTREE-01 /
# -REST-01 (#616, #650) và dòng gate thật in "<trạng thái> | <ID> : <mô tả>", nên reg_dk_all_not_pass cũ (khoá "REG-DK-ALL-01 |") không bao
# giờ khớp: merge gate #707 lúc 20:07 30/10 đỏ ở shard gates mà scratch bị xoá, mất log đỏ. Test gọi THẲNG hàm của merge gate với các dòng
# đúng định dạng gate thật (có cả mã màu ANSI), dòng cũ "REG-DK-ALL-01 |" (không hồi quy) và các dòng KHÔNG được khớp.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-keep-shards.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# lấy đúng thân hàm từ merge gate (không source cả script: nó chạy luôn)
sed -n '/^reg_dk_all_not_pass() {/,/^}/p' "$GATE" > "$TMP/fn.sh"
grep -q '^reg_dk_all_not_pass() {' "$TMP/fn.sh" || { echo "✖ không tìm thấy reg_dk_all_not_pass trong $GATE"; exit 1; }
. "$TMP/fn.sh"

E=$(printf '\033')
case_log() { # tên, kỳ vọng (keep|no), dòng log
  printf '%s\n' "$3" > "$TMP/log"
  if reg_dk_all_not_pass "$TMP/log"; then got=keep; else got=no; fi
  [ "$got" = "$2" ] && ok "$1" || fail "$1 (muốn $2, được $got): $3"
}
case_log "shard gates FAIL (định dạng gate thật) ⇒ giữ" keep \
  "    [ ] FAIL | REG-DK-ALL-GATES-01 : #616 shard thay REG-DK-ALL-01 (đã bỏ ở #650) theo thư mục (tests/gates): DevKit tests"
case_log "shard gates FAIL có mã màu ANSI ⇒ giữ" keep \
  "    ${E}[91m[ ] FAIL${E}[0m | ${E}[1mREG-DK-ALL-GATES-01${E}[0m : #616 shard thay REG-DK-ALL-01"
case_log "shard rest TIMEOUT ⇒ giữ" keep "    [ ] TIMEOUT | REG-DK-ALL-REST-01 : #616 shard (phần còn lại)"
case_log "shard worktree TIMEOUT (HANG) ⇒ giữ" keep "    [ ] TIMEOUT (HANG) | REG-DK-ALL-WORKTREE-01 : #616 shard"
case_log "dòng cũ REG-DK-ALL-01 | FAIL ⇒ vẫn giữ (không hồi quy)" keep "[ ] FAIL | REG-DK-ALL-01 | devkit"
case_log "shard PASS ⇒ không giữ" no "    [x] PASS | REG-DK-ALL-GATES-01 : #616 shard"
case_log "shard UNTESTED (không chạy vì suite trước đỏ) ⇒ không giữ" no "    [ ] UNTESTED | REG-DK-ALL-REST-01 : #616 shard"
case_log "suite khác FAIL chỉ NHẮC REG-DK-ALL-01 trong mô tả ⇒ không giữ" no \
  "    [ ] FAIL | REG-SB-MERGE-SCRATCH-KEEP-559-01 : #559: REG-DK-ALL-01 không PASS thì giữ scratch"
case_log "ID gần giống (REG-DK-ALLX-01) FAIL ⇒ không giữ" no "    [ ] FAIL | REG-DK-ALLX-01 : khác"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_keep_scratch_shards: tất cả XANH"; exit 0; }
echo "test_merge_gate_keep_scratch_shards: $FAILS FAIL"; exit 1
