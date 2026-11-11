#!/usr/bin/env bash
# #812 (2): own_repo() không đọc được origin ⇒ dòng cảnh báo stderr mở đầu `[ac-check]` (không phải `ac-check:`: merge-train/queue
# chép mọi dòng `ac-check:*` vào comment PR) và không lộ đường dẫn tuyệt đối của máy. Offline, bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AC="${SB_AC:-$ROOT/.claude/bin/super-board-ac-check.py}"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-ac-stderr.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_CEILING_DIRECTORIES="$TMP"
unset SB_REPO_PATH
mkdir -p "$TMP/nogit" "$TMP/else"
git init -q "$TMP/else" && git -C "$TMP/else" remote add origin git@gitlab.com:someone/else.git
printf 'Closes #31\nCloses other/repo#32\n' > "$TMP/body.md"

# S1 — không phải repo git: không đọc được origin.
(cd "$TMP/nogit" && SB_REPO_PATH="$TMP/nogit" python3 "$AC" --pr-body "$TMP/body.md" --branch issue-31-x >/dev/null 2>"$TMP/err1")
# S2 — origin không phải GitHub.
(cd "$TMP/else" && SB_REPO_PATH="$TMP/else" python3 "$AC" --pr-body "$TMP/body.md" --branch issue-31-x >/dev/null 2>"$TMP/err2")
for n in 1 2; do
  if [ -s "$TMP/err$n" ] && ! grep -q '^ac-check:' "$TMP/err$n" && grep -q '^\[ac-check\]' "$TMP/err$n"; then ok "S$n stderr mở đầu [ac-check], không phải ac-check:"
  else fail "S$n tiền tố stderr: $(cat "$TMP/err$n")"; fi
  if ! grep -q "$TMP" "$TMP/err$n" && ! grep -Eq '(^|[ (])/[A-Za-z0-9_.-]+/' "$TMP/err$n"; then ok "S$n stderr không chứa đường dẫn tuyệt đối"
  else fail "S$n lộ đường dẫn: $(cat "$TMP/err$n")"; fi
done
if [ "$FAILS" -eq 0 ]; then echo "test_ac_check_stderr_812: all passed"; exit 0; else echo "test_ac_check_stderr_812: $FAILS failed"; exit 1; fi
