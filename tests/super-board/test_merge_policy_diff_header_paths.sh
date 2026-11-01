#!/usr/bin/env bash
# Hồi quy #742 (review P0 d1facdea5d, INSTINCT-089): super-board-merge-policy.py đọc đường dẫn file bị xoá từ header của diff git.
# File rỗng bị xoá không có dòng ---/+++, chỉ có `diff --git` + `deleted file mode`. Đường dẫn có khoảng trắng / UTF-8 thì git
# (core.quotePath mặc định) in dạng C-quoted `"a/…\303\251…" "b/…"`: phải giải mã escape bát phân và tách đúng hai nửa, nếu không
# PR xoá file được bảo vệ lách cổng người duyệt `delete-protected`. Diff thật do git sinh ra, không viết tay.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
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
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" | ".join(h["why"] for h in d["human"] if h["category"] == "delete-protected"))'; }

deleted_diff ".agents/local/rules/ghi chú é.md" ""
grep -q '^diff --git "a/' "$TMP/d.diff" && ! grep -q '^--- ' "$TMP/d.diff" || fail "fixture: expected a C-quoted header without ---/+++ lines"
w=$(gone)
case "$w" in *".agents/local/rules/ghi chú é.md"*) ok "empty protected file with a C-quoted path: delete-protected, path decoded ($w)" ;;
  *) fail "empty protected file with a C-quoted path slipped past delete-protected: [$w]" ;; esac

deleted_diff ".agents/local/rules/ghi chú 2 é.md" "rule"
w=$(gone)
case "$w" in *".agents/local/rules/ghi chú 2 é.md"*) ok "non-empty protected file with a C-quoted path: decoded on the --- line ($w)" ;;
  *) fail "non-empty quoted protected delete: [$w]" ;; esac

deleted_diff ".agents/local/rules/x b/y.md" ""
w=$(gone)
case "$w" in *"deletes .agents/local/rules/x b/y.md "*) ok "empty protected file whose path holds \" b/\": header split in the middle ($w)" ;;
  *) fail "path with \" b/\" read wrong: [$w]" ;; esac

deleted_diff "docs/plain é.md" ""
[ -z "$(gone)" ] && ok "deleting an unprotected quoted file stays auto" || fail "unprotected quoted delete gated: [$(gone)]"

printf 'diff --git "a/bad\\9" "b/bad\\9"\ndeleted file mode 100644\nindex e69de29..0000000\n' > "$TMP/d.diff"
case "$(gone)" in *"<unreadable path>"*) ok "a deletion whose header cannot be read: delete-protected (fail-closed)" ;;
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

# drop_files: the policy's own test fixtures (POLICY_SELF_TESTS) are dropped by their decoded +++ path, other files stay
python3 -I - "$POLICY" <<'PY' && ok "parser units: quoted/unquoted headers, octal + backslash escapes, drop_files by decoded path" || fail "parser units"
import importlib.util as u, sys
s = u.spec_from_file_location("p", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
assert m.diff_git_paths('diff --git a/x y b/x y') == ("x y", "x y")
assert m.diff_git_paths('diff --git a/d b/x b/d b/x') == ("d b/x", "d b/x")
assert m.diff_git_paths('diff --git "a/t\\303\\251 \\"q\\"\\t" "b/t\\303\\251 \\"q\\"\\t"') == ('té "q"\t', 'té "q"\t')
assert m.diff_git_paths('diff --git a/old "b/n\\303\\251w"') == ("old", "néw")
assert m.diff_git_paths('diff --git "a/bad\\9" "b/bad\\9"') is None
sec = ('diff --git "a/tests/super-board/test_merge_policy_\\303\\251.sh" "b/tests/super-board/test_merge_policy_\\303\\251.sh"\n'
       'new file mode 100644\n--- /dev/null\n+++ "b/tests/super-board/test_merge_policy_\\303\\251.sh"\n@@ -0,0 +1 @@\n+drop table x\n')
assert m.drop_files(sec, m.POLICY_SELF_TESTS) == ""
other = sec.replace("test_merge_policy_", "other_")
assert m.drop_files(other, m.POLICY_SELF_TESTS) == other
PY

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
