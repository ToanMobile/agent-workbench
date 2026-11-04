#!/usr/bin/env bash
# Port từ upstream EricTechPro/super-board 3.3.0 (T0247), ba bản sửa nhỏ:
# 1. setup: hai lần fix trong cùng một khoảng thời gian ghi cùng thư mục backup → FileExistsError, config không được migrate.
#    Tên backup có giây; thư mục đã có thì thêm hậu tố -2, -3.
# 2. merge-policy: dòng `> needs-you: <lệnh>` trong status alert của PR body cũng là bước chỉ người làm.
# 3. submodule: halt và cache thẻ nằm trong git dir của chính submodule (phần 3 bên dưới).
# Chỉ đọc repo, ghi vào thư mục tạm. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SETUP="$ROOT/.claude/bin/super-board-setup.py"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-upstream-330.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# --- 1. backup() hai lần cùng stamp ---
mkdir -p "$TMP/repo/.claude/super-board/configs"
echo '{}' > "$TMP/repo/.claude/super-board/configs/a.json"
OUT="$(python3 - "$SETUP" "$TMP/repo" <<'PY' 2>&1
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("sbsetup", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
root = sys.argv[2]
paths = [os.path.join(root, ".claude", "super-board", "configs")]
first = m.backup(root, paths, "20261104-1200")
second = m.backup(root, paths, "20261104-1200")
print(first, second)
for d in (first, second):
    assert os.path.isfile(os.path.join(root, d, ".claude/super-board/configs/a.json")), d
assert first != second
PY
)"
RC=$?
if [ "$RC" -eq 0 ]; then ok "backup(): second call with the same stamp gets its own folder ($OUT)"; else fail "backup(): same-stamp second call crashed: $(echo "$OUT" | tail -1)"; fi
if grep -q 'stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")' "$SETUP"; then ok "fix() stamp carries seconds"; else fail "fix() stamp has no seconds"; fi

# --- 2. needs-you trong status alert ---
: > "$TMP/empty.diff"
echo '{}' > "$TMP/cfg.json"
needs() { # $1 = body
  python3 - "$1" > "$TMP/meta.json" <<'PY'
import json, sys
print(json.dumps({"labels": [], "body": sys.argv[1], "files": []}))
PY
  python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta.json" --diff "$TMP/empty.diff" \
    | python3 -c 'import json,sys; print("|".join(json.load(sys.stdin)["needs_you"]))'
}
[ "$(needs $'> [!NOTE]\n> needs-you: rotate the key')" = "rotate the key" ] \
  && ok "needs-you inside a status alert is read" || fail "needs-you inside a status alert is ignored"
[ "$(needs 'needs-you: bare line')" = "bare line" ] \
  && ok "bare needs-you line still read" || fail "bare needs-you line regressed"
[ "$(needs $'> needs-you: done')" = "" ] \
  && ok "needs-you: done in an alert stays cleared" || fail "needs-you: done in an alert still blocks"

# --- 3. submodule: halt và cache nằm trong git dir của submodule ---
GITQ=(git -c protocol.file.allow=always -c user.name=t -c user.email=t@t -c commit.gpgsign=false)
mkdir -p "$TMP/sub" "$TMP/parent"
( cd "$TMP/sub" && git init -q && echo x > f && git add f && "${GITQ[@]}" commit -q -m i ) >/dev/null 2>&1
( cd "$TMP/parent" && git init -q && echo y > g && git add g && "${GITQ[@]}" commit -q -m i \
  && "${GITQ[@]}" submodule add -q "$TMP/sub" mod && "${GITQ[@]}" commit -q -m s ) >/dev/null 2>&1
if [ ! -d "$TMP/parent/mod" ]; then fail "fixture: submodule not created"; else
  SUBGIT="$(cd "$TMP/parent/mod" && git rev-parse --absolute-git-dir)"
  HALT="$(cd "$TMP/parent/mod" && SB_REPO_PATH="$TMP/parent/mod" python3 - "$ROOT/.claude/bin/super-board-github-read.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sbread", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.halt_path())
PY
)"
  case "$HALT" in "$SUBGIT"/super-board/*) ok "halt file of a submodule lives in its own git dir";; *) fail "halt file of a submodule is $HALT (want under $SUBGIT/super-board)";; esac
  CACHE="$(cd "$TMP/parent/mod" && bash -c "$(sed -n '/^cache_dir() {/,/^}/p' "$ROOT/.claude/bin/super-board-card.sh"); cache_dir")"
  case "$CACHE" in "$SUBGIT"/super-board/cache) ok "card cache of a submodule lives in its own git dir";; *) fail "card cache of a submodule is $CACHE (want $SUBGIT/super-board/cache)";; esac
fi
# repo thường và worktree giữ nguyên chỗ cũ
HALT_N="$(cd "$TMP/sub" && SB_REPO_PATH="$TMP/sub" python3 - "$ROOT/.claude/bin/super-board-github-read.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sbread", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.halt_path())
PY
)"
[ "$HALT_N" = "$(cd "$TMP/sub" && pwd -P)/.claude/super-board/github-halt.json" ] \
  && ok "normal repo halt path unchanged" || fail "normal repo halt path changed: $HALT_N"
CACHE_N="$(cd "$TMP/sub" && bash -c "$(sed -n '/^cache_dir() {/,/^}/p' "$ROOT/.claude/bin/super-board-card.sh"); cache_dir")"
[ "$CACHE_N" = "$(cd "$TMP/sub" && pwd -P)/.claude/super-board/cache" ] || [ "$CACHE_N" = "$TMP/sub/.claude/super-board/cache" ] \
  && ok "normal repo card cache unchanged" || fail "normal repo card cache changed: $CACHE_N"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
