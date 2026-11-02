#!/usr/bin/env bash
# Hồi quy #742 (review P0 d1facdea5d, INSTINCT-089): super-board-merge-policy.py đọc đường dẫn file bị xoá từ header của diff git.
# File rỗng bị xoá không có dòng ---/+++, chỉ có `diff --git` + `deleted file mode`. Đường dẫn có khoảng trắng / UTF-8 thì git
# (core.quotePath mặc định) in dạng C-quoted `"a/…\303\251…" "b/…"`: phải giải mã escape bát phân và tách đúng hai nửa, nếu không
# PR xoá file được bảo vệ lách cổng `delete-protected` / `delete-reviewable` (T0209 trên main). Diff thật do git sinh ra.
# Tách A3 từ #742 (02/11): bỏ phần drop_files/POLICY_SELF_TESTS (#747, hoãn); ĐỎ trên policy của main d49f26cf.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1   # diff.noprefix / mnemonicPrefix toàn cục không đổi header fixture
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-policy-hdr.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
echo '{}' > "$TMP/cfg.json"
echo '{"labels":[],"body":"","files":[{"path":"x","additions":0,"deletions":0}]}' > "$TMP/meta.json"

R="$TMP/repo"; git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t; git -C "$R" config core.quotePath true
# deleted_diff <path> <content|""> → $TMP/d.diff: commit the file, delete it, git diff of the deletion
deleted_diff() {
  mkdir -p "$(dirname "$R/$1")"; printf '%s' "$2" > "$R/$1"
  git -C "$R" add -A; git -C "$R" commit -qm add
  git -C "$R" rm -q -- "$1"; git -C "$R" commit -qm del
  git -C "$R" diff HEAD~1 HEAD > "$TMP/d.diff"
}
gone() { python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta.json" --diff "$TMP/d.diff" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" | ".join(h["category"] + ": " + h["why"] for h in d["human"] if h["category"].startswith("delete-")))'; }

deleted_diff ".agents/local/rules/ghi chú é.md" ""
grep -q '^diff --git "a/' "$TMP/d.diff" && ! grep -q '^--- ' "$TMP/d.diff" || fail "fixture: expected a C-quoted header without ---/+++ lines"
w=$(gone)
case "$w" in "delete-reviewable: deletes .agents/local/rules/ghi chú é.md "*) ok "empty reviewable file with a C-quoted path: delete-reviewable, path decoded ($w)" ;;
  *) fail "empty protected file with a C-quoted path slipped past delete-protected: [$w]" ;; esac

deleted_diff ".agents/local/rules/ghi chú 2 é.md" "rule"
w=$(gone)
case "$w" in "delete-reviewable: deletes .agents/local/rules/ghi chú 2 é.md "*) ok "non-empty protected file with a C-quoted path: decoded on the --- line ($w)" ;;
  *) fail "non-empty quoted protected delete: [$w]" ;; esac

deleted_diff ".agents/local/rules/x b/y.md" ""
w=$(gone)
case "$w" in *"deletes .agents/local/rules/x b/y.md "*) ok "empty protected file whose path holds \" b/\": header split in the middle ($w)" ;;
  *) fail "path with \" b/\" read wrong: [$w]" ;; esac

echo '{"merge_policy":{"protected_paths":["docs/kept é/**"]}}' > "$TMP/cfg.json"
deleted_diff "docs/kept é/a b.md" ""
w=$(gone)
case "$w" in "delete-protected: deletes docs/kept é/a b.md "*) ok "empty file under a custom protected glob, C-quoted path: delete-protected ($w)" ;;
  *) fail "custom protected glob, quoted empty delete: [$w]" ;; esac
echo '{}' > "$TMP/cfg.json"

deleted_diff "docs/plain é.md" ""
[ -z "$(gone)" ] && ok "deleting an unprotected quoted file stays auto" || fail "unprotected quoted delete gated: [$(gone)]"

# Review vòng 1 (Antigravity + Claude 02/11): `\n` trong tên C-quoted giải mã thành xuống dòng thật; glob `**` phải khớp qua nó.
cats() { gone | python3 -c 'import sys; print(" ".join(sorted({w.split(":")[0] for w in sys.stdin.read().split(" | ") if w.strip()})))'; }
deleted_diff $'.agents/local/rules/a\nb.md' ""
grep -q '^diff --git "a/\.agents/local/rules/a\\nb\.md"' "$TMP/d.diff" || fail "fixture: expected a C-quoted header holding \\n"
[ "$(cats)" = "delete-reviewable" ] && ok "empty rules file with a newline in its name: delete-reviewable" \
  || fail "newline-named rules file slipped the delete gate: [$(cats)]"
deleted_diff $'.agents/local/memory/m\nn.md' "note"
[ "$(cats)" = "delete-reviewable" ] && ok "non-empty memory file with a newline in its name: delete-reviewable" \
  || fail "newline-named memory file slipped the delete gate: [$(cats)]"
deleted_diff $'keys\nx/app.jks' "k"
[ "$(cats)" = "delete-protected" ] && ok "keystore under a newline-named folder: delete-protected" \
  || fail "newline-named folder hid a sensitive delete: [$(cats)]"

printf 'diff --git "a/bad\\9" "b/bad\\9"\ndeleted file mode 100644\nindex e69de29..0000000\n' > "$TMP/d.diff"
case "$(gone)" in "delete-protected: deletes <unreadable path> "*) ok "a deletion whose header cannot be read: delete-protected (fail-closed)" ;;
  *) fail "unreadable deleted header passed: [$(gone)]" ;; esac
echo '{"merge_policy":{"protected_paths":[]}}' > "$TMP/cfg.json"
[ -z "$(gone)" ] && ok "protected_paths [] (off): an unreadable header is not gated" || fail "protected_paths off still gated: [$(gone)]"
echo '{}' > "$TMP/cfg.json"

# Nội dung hunk sau @@ mang dòng bắt đầu bằng `-- a/…` rồi `++ /dev/null` (trong diff thành `--- a/…` / `+++ /dev/null`) không phải xoá file.
mkdir -p "$R/docs"
printf '%s\n' '-- a/.agents/local/rules/not-deleted.md' > "$R/docs/notes.txt"
git -C "$R" add -A; git -C "$R" commit -qm "add notes"
printf '%s\n' '++ /dev/null' > "$R/docs/notes.txt"
git -C "$R" add -A; git -C "$R" commit -qm "edit notes"
git -C "$R" diff HEAD~1 HEAD > "$TMP/d.diff"
grep -q '^--- a/\.agents/local/rules/not-deleted\.md$' "$TMP/d.diff" && grep -q '^+++ /dev/null$' "$TMP/d.diff" \
  || fail "fixture: expected hunk lines starting with --- a/... and +++ /dev/null"
[ -z "$(gone)" ] && ok "hunk content lines mimicking --- a/<protected> + +++ /dev/null after @@ do not trigger delete-protected" \
  || fail "hunk content false-triggered delete-protected: [$(gone)]"

# parser units: diff_git_paths splits plain and C-quoted headers like git; deleted_paths reads an empty deleted file
python3 -I - "$POLICY" <<'PY' && ok "parser units: quoted/unquoted headers, octal + backslash escapes, empty deleted file" || fail "parser units"
import importlib.util as u, sys
s = u.spec_from_file_location("p", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
assert m.diff_git_paths('diff --git a/x y b/x y') == ("x y", "x y")
assert m.diff_git_paths('diff --git a/d b/x b/d b/x') == ("d b/x", "d b/x")
assert m.diff_git_paths('diff --git "a/t\\303\\251 \\"q\\"\\t" "b/t\\303\\251 \\"q\\"\\t"') == ('té "q"\t', 'té "q"\t')
assert m.diff_git_paths('diff --git a/old "b/n\\303\\251w"') == ("old", "néw")
assert m.diff_git_paths('diff --git "a/bad\\9" "b/bad\\9"') is None
assert m.deleted_paths('diff --git a/k.txt b/k.txt\ndeleted file mode 100644\nindex e69de29..0000000\n') == ["k.txt"]
PY

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
