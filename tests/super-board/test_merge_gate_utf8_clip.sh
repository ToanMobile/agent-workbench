#!/usr/bin/env bash
# INSTINCT-173 (GeelyEx2, 17-18/10): dưới locale C, `cut -c` cắt theo BYTE. .claude/bin/super-board-merge-gate.sh rút gọn lỗi của git bằng
# `cut -c1-300` / `cut -c1-200` rồi in vào cảnh báo (Reviewer dán vào PR / comment): lỗi chứa đường dẫn tiếng Việt bị cắt giữa một ký tự
# nhiều byte -> văn bản không còn là UTF-8 ("'utf-8' codec can't decode byte …" ở github-read). Luật: cắt theo ký tự, kể cả dưới LC_ALL=C.
# Ca: fetch sau merge hỏng vì origin trỏ vào một đường dẫn tiếng Việt dài; dòng cảnh báo phải là UTF-8 hợp lệ.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-utf8clip-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-3-x origin/main
git -C "$R" worktree add -q "$W/issue-3-build" issue-3-x
echo 3 > "$W/issue-3-build/c"; git -C "$W/issue-3-build" add c; git -C "$W/issue-3-build" commit -qm "card 3"
git -C "$R" push -q origin issue-3-x
H=$(git -C "$R" rev-parse issue-3-x)
git -C "$R" diff origin/main issue-3-x > "$TMP/pr3.diff"; echo "$H" > "$TMP/pr3.head"
printf '{"files":[{"path":"c"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr3.meta"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) git -C "$FAKE_REPO" push -q origin "$head:refs/heads/main" \
                    && git -C "$FAKE_REPO" remote set-url origin "$FAKE_BREAK_ORIGIN" && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
# Đường dẫn "ộ" (3 byte) đệm ASCII sao cho byte thứ 300 của "fatal: '<đường dẫn>…" rơi GIỮA một ký tự (dưới locale C cut -c1-300 cắt vỡ nó).
BROKEN="$(python3 -c 'import sys; t=sys.argv[1]+"/"; p=len(b"fatal: \x27")+len(t.encode()); k=next(k for k in range(3) if (300-p-k)%3==1); sys.stdout.write(t+"x"*k+"ộ"*150+".git")' "$TMP")"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R" FAKE_BREAK_ORIGIN="$BROKEN"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["true"]}' > "$CFG"
git -C "$R" worktree add -q --detach "$W/issue-3-review" "$H"
( cd "$W/issue-3-review" && bash "$GATE" --config "$CFG" --pr 3 --expect-head "$H" ) >"$TMP/gate.log" 2>&1; rc=$?
git -C "$R" remote set-url origin "$O"
[ "$rc" -eq 0 ] || fail "gate exit $rc: $(tail -5 "$TMP/gate.log")"
grep -a "warning: fetch origin main failed" "$TMP/gate.log" > "$TMP/warn.txt" || fail "fixture: no fetch warning: $(tail -5 "$TMP/gate.log")"
# Fixture thật sự làm vỡ cách cũ (OCR 18/10): lỗi fetch thật của git qua `cut -c1-300` dưới locale C không còn là UTF-8.
old_err=$(git -C "$R" fetch "$BROKEN" main --quiet 2>&1 >/dev/null)
printf '%s' "$old_err" | tr '\n\t' '  ' | cut -c1-300 > "$TMP/old.txt"
python3 -c 'import sys; open(sys.argv[1],"rb").read().decode("utf-8")' "$TMP/old.txt" 2>/dev/null \
  && fail "fixture does not break the old cut -c1-300 (git wording changed?): the test would prove nothing" || ok "fixture: the old cut -c1-300 under LC_ALL=C splits a character"
python3 -c 'import sys; open(sys.argv[1],"rb").read().decode("utf-8")' "$TMP/warn.txt" 2>/dev/null \
  && grep -q "ộộộ" "$TMP/warn.txt" && ok "LC_ALL=C: the clipped git error in the warning is still valid UTF-8 (cut by character)" \
  || fail "warning is not valid UTF-8 (byte-cut): $(od -c "$TMP/warn.txt" | tail -4 | head -2)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_utf8_clip: PASS"; exit 0; } || { echo "test_merge_gate_utf8_clip: FAIL ($FAILS)"; exit 1; }
