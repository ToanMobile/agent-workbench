#!/usr/bin/env bash
# #1000 mục 8 và 7: super-board-audit-check.py --chain-audit (qua --has-edited-tests ... --top --base).
#  U1 (comment #1000, GeelyEx2 #211): ma trận gọi một script không đuôi chứa byte không phải UTF-8; PR sửa test đã có và có audit pass tại head
#     -> vẫn `0 pm` (code cũ: UnicodeDecodeError -> pm-unknown). Byte lạ không được thành duyệt: U1b cùng repo, KHÔNG có audit -> `1 false`.
#  U2 (mục 7): head PR chỉ còn trong auditHistory (lượt audit sau đã REVISE, verdicts.audit = fail) -> `0 pm-unknown` (không kiểm được duyệt
#     hiện hành: bi quan, không tin biên nhận cây), code cũ: `0 pm` như duyệt còn hiệu lực. Không bao giờ `false` (false = đường lỏng nhất).
#  U3 đối chứng: verdicts.audit pass hiện hành tại head PR -> `0 pm`.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
INS="$ROOT/.claude/bin/super-board-install-edited-test-approval.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-chain-robust.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
export DEVKIT_PM_HOME_TEST=1
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R/tests" "$R/bin" "$R/.agents" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
echo a > tests/t.sh
printf 'echo caf\351 \377\376 ok\n' > bin/runner          # Latin-1 / byte rác: không giải mã được UTF-8
printf '{"rules":[{"mandatory_regression_tests":[{"command":"bash bin/runner"}]}]}' > .agents/regression_matrix.active.json
git add -A && git commit -qm M0
git checkout -q -b feat && echo b > tests/t.sh && git commit -qam "PR sửa test"
H="$(git rev-parse HEAD)"
echo '{"comments":[]}' > "$TMP/meta.json"
task() {   # task <id> <verdicts-json>
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  printf '{"id":"%s","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-04T00:00:00Z"}],"verdicts":%s}\n' \
    "$1" "$(pwd -P)" "$2" > "$TMP/pm/projects/p-$1/tasks/$1/task.json"
}
has_et() { local out rc=0; out=$(bash "$INS" --has-edited-tests "$TMP/meta.json" "$@" 2>"$TMP/err") || rc=$?; printf '%s %s' "$rc" "$out"; }

got="$(has_et "$H" --top "$R" --base main)"
[ "$got" = "1 false" ] && ok "U1b: byte lạ, không có audit -> false (không thành duyệt)" || fail "U1b: '$got' (muốn '1 false'): $(cat "$TMP/err")"

task T4001-cur '{"audit":{"verdict":"pass","round":1,"reviewer":"grok","notes":"ok","auditedHead":"'"$H"'"}}'
got="$(has_et "$H" --top "$R" --base main)"
[ "$got" = "0 pm" ] && ok "U1/U3: script ma trận có byte không UTF-8 + audit pass hiện hành tại head -> pm" \
  || fail "U1/U3: '$got' (muốn '0 pm'): $(cat "$TMP/err")"
grep -q UnicodeDecodeError "$TMP/err" && fail "U1: stderr vẫn có UnicodeDecodeError" || ok "U1: không có UnicodeDecodeError"
rm -rf "$TMP/pm/projects/p-T4001-cur"

# U2 trên repo thứ hai không có byte lạ (để kết quả không lẫn với lỗi giải mã của U1).
R2="$TMP/repo2"; mkdir -p "$R2/tests" && cd "$R2" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
echo a > tests/t.sh && git add -A && git commit -qm M0
git checkout -q -b feat && echo b > tests/t.sh && git commit -qam "PR sửa test"
H2="$(git rev-parse HEAD)"
task T4002-hist '{"audit":{"verdict":"fail","round":2,"reviewer":"grok","notes":"REVISE"},"auditHistory":[{"auditedHead":"'"$H2"'","reviewer":"grok","at":"2026-11-04T00:00:00Z"}]}'
got="$(has_et "$H2" --top "$R2" --base main)"
[ "$got" = "0 pm-unknown" ] && ok "U2: head chỉ còn trong auditHistory (lượt sau REVISE) -> pm-unknown" \
  || fail "U2: '$got' (muốn '0 pm-unknown'): $(cat "$TMP/err")"

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
