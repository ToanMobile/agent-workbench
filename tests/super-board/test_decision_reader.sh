#!/usr/bin/env bash
# Test hồi quy #516: không script nào nhận ra `[orchestrator] [decision]` (ủy quyền thường trực của chủ 28/10), nên merge gate
# vẫn đọc `❌ Not done` của QA cũ, needs-you.py mark vẫn gắn lại nhãn, deps.sh vẫn đặt needsYou=true vì 🙋 cũ.
# Sửa: bộ đọc dùng chung super-board-decision.py (hợp lệ chỉ khi marker orchestrator HOẶC comment tay của chủ không marker;
# header/marker lane thì bỏ qua) + deps.sh, needs-you.py mark, qa-report.py dùng nó. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEC="$ROOT/.claude/bin/super-board-decision.py"
DEPS="$ROOT/.claude/bin/super-board-deps.sh"
NEEDS="$ROOT/.claude/bin/super-board-needs-you.py"
QAR="$ROOT/.claude/bin/super-board-qa-report.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export SB_GITHUB_HALT_FILE="$TMP/github-halt.json"

# Một comment: $1 body (đã escape JSON), $2 authorAssociation, $3 login
cm() { printf '{"body":"%s","authorAssociation":"%s","author":{"login":"%s"}}' "$1" "${2:-OWNER}" "${3:-ToanMobile}"; }
latest() { printf '[%s]' "$1" | python3 "$DEC" latest ${2:+--config "$2"} 2>&1 | tail -1; }

# ---- 1. bộ đọc: mỗi luật 1–5 của chủ, ghi tay không marker, đều là quyết định hợp lệ ----
for n in 1 2 3 4 5; do
  R="$(latest "$(cm "[orchestrator] [decision] luật $n: lý do, bằng chứng. Quyết định cuối, không hỏi lại")")"
  [ "$R" = "0" ] && ok "luật $n: comment tay của chủ hợp lệ" || fail "luật $n bị bỏ qua: $R"
done
R="$(latest "$(cm "<!-- sb-decision:orchestrator -->\n[orchestrator] [decision] luật 1")")"
[ "$R" = "0" ] && ok "marker orchestrator hợp lệ" || fail "marker orchestrator bị bỏ qua: $R"

# ---- 2. lane không tự quyết cho thẻ mình ----
R="$(latest "$(cm "[builder] [decision] luật 1 tự chấp nhận")")"
[ "$R" = "-1" ] && ok "header [builder]: bỏ qua" || fail "builder tự quyết được: $R"
R="$(latest "$(cm "[qa] [decision] luật 2")")"
[ "$R" = "-1" ] && ok "header [qa]: bỏ qua" || fail "qa tự quyết được: $R"
R="$(latest "$(cm "[reviewer] [decision] luật 2")")"
[ "$R" = "-1" ] && ok "header [reviewer]: bỏ qua" || fail "reviewer tự quyết được: $R"
R="$(latest "$(cm "<!-- sb-write:abc123 -->\n[orchestrator] [decision] luật 1")")"
[ "$R" = "-1" ] && ok "marker sb-write (lane đăng): bỏ qua" || fail "comment sb-write được tin: $R"
R="$(latest "$(cm "<!-- super-review:report -->\n[orchestrator] [decision] luật 1")")"
[ "$R" = "-1" ] && ok "marker super-review: bỏ qua" || fail "comment super-review được tin: $R"
R="$(latest "$(cm "[orchestrator] [decision] luật 1" NONE stranger)")"
[ "$R" = "-1" ] && ok "người lạ: bỏ qua" || fail "người lạ quyết được: $R"

# ---- 3. config tắt ----
echo '{"decision_policy":{"enabled":false}}' > "$TMP/off.json"
R="$(latest "$(cm "[orchestrator] [decision] luật 1")" "$TMP/off.json")"
[ "$R" = "-1" ] && ok "decision_policy.enabled=false: tắt" || fail "config tắt mà vẫn nhận: $R"

# ---- 4. deps.sh: needsYou ----
PU='Reason tag: needs you 🙋\nblocked-by: -'
DEC1='[orchestrator] [decision] luật 1'
deps() {  # $1 labels json array, $2 comments; in ra "<needsYou>"
  printf '[{"number":9,"title":"t","state":"OPEN","body":"## Blocked by\\n- None.\\n","labels":{"nodes":%s},"comments":{"nodes":[%s]}}]' "$1" "$2" > "$TMP/p.json"
  "$DEPS" --repo o/r --from "$TMP/p.json" 2>&1 | jq -r '.["9"].needsYou' 2>&1 | tail -1
}
R="$(deps '[]' "$(cm "$PU"),$(cm "$DEC1")")"
[ "$R" = "false" ] && ok "deps: 🙋 cũ + [decision] mới hơn, không nhãn: needsYou=false" || fail "deps vẫn needsYou: $R"
R="$(deps '[]' "$(cm "$DEC1"),$(cm "$PU")")"
[ "$R" = "true" ] && ok "deps: 🙋 mới hơn [decision]: needsYou=true" || fail "deps bỏ qua 🙋 mới: $R"
R="$(deps '[{"name":"needs-you"}]' "$(cm "$PU"),$(cm "$DEC1")")"
[ "$R" = "true" ] && ok "deps: còn nhãn needs-you: needsYou=true" || fail "deps bỏ qua nhãn: $R"
R="$(deps '[]' "$(cm "$PU"),$(cm "[builder] [decision] luật 1")")"
[ "$R" = "true" ] && ok "deps: [decision] của builder không gỡ 🙋" || fail "deps tin decision của lane: $R"

# ---- 5. needs-you.py mark (gh giả) ----
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *issues/9/comments*) cat "$STUB_COMMENTS" ;;
  *issues/9*) echo '{"labels":[],"body":""}' ;;
  *labels/needs-you*) echo '{"color":"D93F0B","description":"🙋 Cần người thực hiện bước chỉ con người được làm"}' ;;
  *) echo '{}' ;;
esac
STUB
chmod +x "$TMP/bin/gh"
mark() {  # $1 comments json (mảng), $2 --action
  printf '[%s]' "$1" > "$TMP/comments.json"
  PATH="$TMP/bin:$PATH" STUB_COMMENTS="$TMP/comments.json" python3 "$NEEDS" mark --repo o/r --issue 9 --action "$2" --dry-run 2>&1 | tail -1
}
R="$(mark "$(cm "$DEC1")" "xác nhận mẫu đo thay thế đủ chứng minh cơ chế")"
case "$R" in *"needs-you added"*) fail "mark gắn lại needs-you dù đã có [decision]: $R" ;; *) ok "mark: đã có [decision] thì không gắn lại needs-you" ;; esac
R="$(mark "$(cm "$DEC1")" "lái xe thử một buổi trên xe thật")"
case "$R" in *"needs-you added"*) ok "mark: ca DỪNG (lái xe) vẫn gắn needs-you" ;; *) fail "ca DỪNG bị bỏ qua: $R" ;; esac
R="$(mark "$(cm "$DEC1")" "đưa secret API vào kho khoá")"
case "$R" in *"needs-you added"*) ok "mark: ca DỪNG (secret) vẫn gắn needs-you" ;; *) fail "ca DỪNG secret bị bỏ qua: $R" ;; esac
R="$(mark "$(cm "[builder] [decision] luật 1")" "xác nhận mẫu đo thay thế đủ chứng minh cơ chế")"
case "$R" in *"needs-you added"*) ok "mark: builder tự đăng [decision] bị bỏ qua, blocker vẫn gắn" ;; *) fail "builder tự gỡ blocker của mình: $R" ;; esac
R="$(mark "" "xác nhận mẫu đo thay thế đủ chứng minh cơ chế")"
case "$R" in *"needs-you added"*) ok "mark: không có [decision] thì gắn như cũ" ;; *) fail "mark thường hỏng: $R" ;; esac

# ---- 6. qa-report.py ----
BODY='## Acceptance Criteria\n- [ ] AC1 mẫu đo thay thế chứng minh đúng cơ chế\n'
QA='[qa] [report] ❌\n❌ Not done: AC1 chưa có mẫu đo thật'
qa() {  # $1 comments (mảng nối bằng dấu phẩy); in ra exit code
  printf '{"body":"%s","author":{"login":"ToanMobile"},"comments":[%s]}' "$BODY" "$1" > "$TMP/pr.json"
  python3 "$QAR" --meta "$TMP/pr.json" >/dev/null 2>&1; echo $?
}
R="$(qa "$(cm "$QA")")"
[ "$R" = "1" ] && ok "qa-report: ❌ Not done AC1 không có decision: chặn" || fail "qa-report không chặn Not done thường: $R"
R="$(qa "$(cm "$QA"),$(cm "$DEC1")")"
[ "$R" = "0" ] && ok "qa-report: [decision] hợp lệ mới hơn: không chặn" || fail "qa-report vẫn chặn dù đã có decision: $R"
R="$(qa "$(cm "$DEC1"),$(cm "$QA")")"
[ "$R" = "1" ] && ok "qa-report: QA mới hơn [decision]: vẫn chặn" || fail "qa-report bỏ qua QA mới: $R"
R="$(qa "$(cm "$QA"),$(cm "[qa] [decision] luật 1")")"
[ "$R" = "1" ] && ok "qa-report: [decision] của lane QA: vẫn chặn" || fail "qa-report tin decision của lane: $R"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
