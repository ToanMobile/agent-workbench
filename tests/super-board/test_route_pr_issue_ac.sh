#!/usr/bin/env bash
# #1197: route-pr đưa thẻ vào QA nhưng issue ngoài khuôn (không có `## Acceptance Criteria`) bị preflight giữ lại.
#  (a) issue thiếu AC + PR có `## AC` -> thân issue được chép mục AC của PR trước khi move QA
#  (b) issue thiếu AC + PR không có AC -> thêm dòng '- [ ] Kiểm thử của PR đạt'
#  (c) issue đã có `## Acceptance Criteria` -> không sửa issue
#  (d) thẻ ở Review (giữ, không move QA) -> không sửa issue
# Chạy offline: gh và super-board-card.sh là stub. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ROUTE="$ROOT/.claude/bin/super-board-route-pr.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-route-ac.XXXXXX")"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export GIT_CEILING_DIRECTORIES="$TMP"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE SB_CONFIG CLAUDE_CODE_ENTRYPOINT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/st"
cp "$ROUTE" "$TMP/bin/super-board-route-pr.sh"
printf '{"project":{"owner":"acme","number":7},"repo":{"path":".","remote":"https://github.com/acme/widgets"},"base_branch":"main"}\n' > "$TMP/cfg.json"
cat > "$TMP/bin/super-board-card.sh" <<'SH'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in --config) shift 2 ;; *) break ;; esac; done
case "$1" in status) cat "$ST/status" ;; move) echo "move $2 $3" >> "$ST/writes" ;; esac
SH
cat > "$TMP/path/gh" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view")    jq -c --rawfile b "$ST/pbody" '. + {body: $b}' "$ST/pr" ;;
  "issue view") cat "$ST/ibody" ;;
  "issue edit") f=""; while [ $# -gt 0 ]; do [ "$1" = --body-file ] && f="$2"; shift; done
                echo "issue-edit" >> "$ST/writes"; cp "$f" "$ST/ibody" ;;
  "pr edit")    echo "pr-edit" >> "$ST/writes" ;;
  *) echo "gh $*" >> "$ST/writes" ;;
esac
SH
chmod +x "$TMP/bin/"* "$TMP/path/gh"
export ST="$TMP/st" PATH="$TMP/path:$PATH"
setup() {  # setup <status> <issue body> <pr body>
  printf '{"number":42,"isDraft":false,"headRefName":"issue-12-x","title":"t","state":"OPEN","url":"u"}' > "$ST/pr"
  printf '%s\n' "$1" > "$ST/status"; printf '%s' "$2" > "$ST/ibody"; printf '%s' "$3" > "$ST/pbody"; : > "$ST/writes"
}
route() { ( cd "$TMP" && bash "$TMP/bin/super-board-route-pr.sh" 42 --config "$TMP/cfg.json" >"$TMP/out" 2>"$TMP/err" ); echo $?; }

setup Building $'## Problem\nx' $'Closes #12\n\n## AC\n- [ ] đo được A\n- [ ] đo được B\n\n## Risk\nthấp'
rc=$(route)
if [ "$rc" = 0 ] && grep -qx "move 12 QA" "$ST/writes" && grep -q '^## Acceptance Criteria' "$ST/ibody" \
   && grep -q 'đo được A' "$ST/ibody" && grep -q 'đo được B' "$ST/ibody" && ! grep -q 'Risk' "$ST/ibody"; then
  ok "(a) missing AC: PR's AC copied into the issue, then moved to QA"; else fail "(a) rc=$rc body=$(cat "$ST/ibody") err=$(head -c 200 "$TMP/err")"; fi

setup Ready $'## Problem\nx' 'Closes #12'
rc=$(route)
[ "$rc" = 0 ] && grep -q '^- \[ \] Kiểm thử của PR đạt' "$ST/ibody" && grep -qx "move 12 QA" "$ST/writes" \
  && ok "(b) missing AC and PR without AC: default line added" || fail "(b) rc=$rc body=$(cat "$ST/ibody")"

setup Building $'## Problem\nx\n\n## Acceptance Criteria\n- [ ] giữ nguyên' $'Closes #12\n\n## AC\n- [ ] khác'
rc=$(route)
[ "$rc" = 0 ] && ! grep -qx "issue-edit" "$ST/writes" && grep -q 'giữ nguyên' "$ST/ibody" && grep -qx "move 12 QA" "$ST/writes" \
  && ok "(c) issue with AC: untouched" || fail "(c) rc=$rc writes=$(tr '\n' ' ' <"$ST/writes")"

setup Review $'## Problem\nx' 'Closes #12'
rc=$(route)
[ "$rc" = 0 ] && ! grep -qx "issue-edit" "$ST/writes" && ok "(d) card in Review: issue untouched" || fail "(d) rc=$rc writes=$(tr '\n' ' ' <"$ST/writes")"

[ "$FAILS" = 0 ] && { echo "route-pr issue AC: all passed"; exit 0; } || { echo "route-pr issue AC: $FAILS failed"; exit 1; }
