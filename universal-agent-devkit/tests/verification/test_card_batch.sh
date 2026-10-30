#!/usr/bin/env bash
# Test #724: một đợt thẻ = một nhánh, một PR, một lần gate.
# Trước: create_task chỉ gom thẻ cùng scope/file (T0054); 5 việc khác scope ⇒ 5 thẻ ⇒ 5 nhánh/PR ⇒ 5 lần gate + 5 merge gate.
# Bây giờ: thẻ mới không gom được (khác chủ đề, thẻ đủ trần AC) vào ĐỢT của thẻ trưởng chưa chạy cùng loại — chỉ ghi trên chính
# thẻ mới (Blocked by thẻ trưởng + marker `<!-- sb:batch-of #N -->`), không sửa thẻ trưởng. card_batch.py plan cho builder MỘT
# nhánh issue-<trưởng>-, một PR Closes từng thẻ; card_batch.py split tách thẻ bị chặn (revert đúng commit của nó, thẻ thành riêng).
# Trần đợt SB_MAX_BATCH_CARDS / SB_MAX_BATCH_AC (#369); 🔴 High, --blocked-by, needs-you, --new-card vẫn riêng.
# gh giả (đầu PATH): item-list trả FAKE_ITEMS, issue create cấp số tăng dần, mọi lệnh ghi vào calls.jsonl. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CT="$DEVKIT_DIR/scripts/governance/create_task.py"
CB="$DEVKIT_DIR/scripts/governance/card_batch.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset SB_MAX_BATCH_CARDS SB_MAX_BATCH_AC SB_MAX_CARD_AC

mkdir -p "$TMP/bin" "$TMP/repo" "$TMP/gh"
export FAKE_LOG="$TMP/calls.jsonl" FAKE_ITEMS="$TMP/items.json" FAKE_DIR="$TMP/gh"
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
d = os.environ["FAKE_DIR"]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"gh": a}, ensure_ascii=False) + "\n")
def arg(name):
    return a[a.index(name) + 1] if name in a else None
def items():
    return json.load(open(os.environ["FAKE_ITEMS"]))["items"] if os.path.exists(os.environ["FAKE_ITEMS"]) else []
if a[:2] == ["issue", "create"]:
    nf = os.path.join(d, "next")
    n = int(open(nf).read()) if os.path.exists(nf) else 99
    open(nf, "w").write(str(n + 1))
    open(os.path.join(d, "issue%d.body" % n), "w").write(arg("--body"))
    print("https://github.com/ToanMobile/agent-workbench/issues/%d" % n); sys.exit(0)
if a[:2] == ["project", "item-add"]:
    print(json.dumps({"id": "PVTI_1"})); sys.exit(0)
if a[:2] == ["project", "item-list"]:
    print(json.dumps({"items": items()})); sys.exit(0)
if a[:2] == ["issue", "view"]:
    n = a[2]
    p = os.path.join(d, "issue%s.body" % n)
    body = open(p).read() if os.path.exists(p) else next(
        (i["content"]["body"] for i in items() if str(i["content"]["number"]) == n), None)
    if body is None:
        sys.stderr.write("fake gh: no issue %s\n" % n); sys.exit(1)
    closed = n in os.environ.get("FAKE_CLOSED", "").split(",")
    title = next((i["content"]["title"] for i in items() if str(i["content"]["number"]) == n), "t")
    print(json.dumps({"body": body, "state": "CLOSED" if closed else "OPEN", "title": title})); sys.exit(0)
if a[:2] == ["issue", "edit"]:
    open(os.path.join(d, "issue%s.body" % a[2]), "w").write(arg("--body")); sys.exit(0)
if a[:2] == ["pr", "view"]:
    print(json.dumps({"body": open(os.path.join(d, "pr%s.body" % a[2])).read()})); sys.exit(0)
if a[:2] == ["pr", "edit"]:
    open(os.path.join(d, "pr%s.body" % a[2]), "w").write(arg("--body")); sys.exit(0)
if a[:2] in (["project", "item-edit"], ["label", "create"], ["issue", "comment"]):
    sys.exit(0)
if a[:2] == ["pr", "list"]:
    print("[]"); sys.exit(0)
sys.stderr.write("fake gh: unexpected %r\n" % (a,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
cd "$TMP/repo" && git init -q . && git remote add origin https://github.com/ToanMobile/agent-workbench.git
export PATH="$TMP/bin:$PATH"

# items <json-list>: mỗi thẻ {n, status, label/labels, title, body, repo}; body mặc định: 2 AC, Risk 🟢, Blocked by - None.
items() { python3 - "$1" <<'PY'
import json, os, sys
out = []
for c in json.loads(sys.argv[1]):
    body = c.get("body") or open(os.path.join(os.environ["FAKE_DIR"], "issue%d.body" % c["n"])).read() if c.get("from_created") \
        else c.get("body", "## Problem\nx\n\n## Acceptance Criteria\n- [ ] trưởng a\n- [ ] trưởng b\n\n## Risk\n🟢\n\n## Blocked by\n- None.\n")
    out.append({"status": c.get("status", "Backlog"), "labels": c.get("labels") or [c.get("label", "feature")],
                "content": {"type": "Issue", "repository": c.get("repo", "ToanMobile/agent-workbench"), "number": c["n"],
                            "title": c.get("title", "✨ [feature] hooks: thẻ %d" % c["n"]), "body": body}})
open(os.environ["FAKE_ITEMS"], "w").write(json.dumps({"items": out}))
PY
}
reset_gh() { rm -f "$FAKE_DIR"/*; }
run() { : > "$FAKE_LOG"; (cd "$TMP/repo" && python3 "$CT" "$@") >"$TMP/out" 2>&1; echo $?; }
called() { python3 - "$1" "$2" <<'PY'
import json, os, sys
print(sum(1 for l in open(os.environ["FAKE_LOG"]) if json.loads(l).get("gh", [])[:2] == sys.argv[1:3]))
PY
}
created() { cat "$FAKE_DIR/issue$1.body" 2>/dev/null; }
marker_of() { created "$1" | sed -n 's/.*<!-- sb:batch-of #\([0-9]*\) -->.*/\1/p' | head -1; }
na() { A=(--title "✨ [feature] $1: việc $1" --problem "vấn đề $1" --fix "sửa $1" --ac "- [ ] AC-$1"); }   # đặt mảng A (bash 3.2: hàm không trả mảng)

# 1. Ba thẻ khác scope (hooks, gate, suite-cache) cùng loại → MỘT đợt của thẻ trưởng #7; thẻ trưởng không bị sửa.
na gate; reset_gh; items '[{"n":7}]'
rc=$(run "${A[@]}")
[ "$rc" = 0 ] && [ "$(called issue create)" = 1 ] && [ "$(called issue edit)" = 0 ] && [ "$(marker_of 99)" = 7 ] \
  && ok "1a thẻ khác scope → thẻ mới #99 vào đợt #7 (marker), không sửa #7" || fail "1a rc=$rc create=$(called issue create) edit=$(called issue edit) marker=$(marker_of 99): $(tail -3 "$TMP/out")"
python3 - "$(created 99)" <<'PY' && ok "1b Blocked by của #99 là đúng một dòng '- #7 — đợt…' (deps.sh đọc là blocker) + marker" || fail "1b Blocked by sai: $(created 99 | tail -4)"
import re, sys
b = sys.argv[1]
sec = re.split(r"(?m)^## Blocked by\s*$", b)[-1].strip().splitlines()
bullets = [l for l in sec if re.match(r"^[ \t]*(-[ \t]*)?#[0-9]+", l)]
sys.exit(0 if len(bullets) == 1 and bullets[0].startswith("- #7 — đợt") and "<!-- sb:batch-of #7 -->" in sec
         and not any(re.match(r"^[ \t]*-[ \t]*[Nn]one", l) for l in sec) else 1)
PY
grep -q "đợt #7" "$TMP/out" && ok "1c in 'đợt #7' cho người tạo" || fail "1c không báo đợt: $(tail -3 "$TMP/out")"
na suite-cache; items '[{"n":7},{"n":99,"from_created":1,"title":"✨ [feature] gate: việc gate"}]'
rc=$(run "${A[@]}")
[ "$rc" = 0 ] && [ "$(marker_of 100)" = 7 ] && [ "$(called issue edit)" = 0 ] && ok "1d thẻ thứ ba (scope khác nữa) → #100 cùng đợt #7" || fail "1d rc=$rc marker=$(marker_of 100)"
items '[{"n":7},{"n":99,"from_created":1,"title":"✨ [feature] gate: việc gate"},{"n":100,"from_created":1,"title":"✨ [feature] suite-cache: việc suite-cache"},{"n":8,"title":"✨ [feature] docs: thẻ ngoài đợt"}]'
out=$(cd "$TMP/repo" && python3 "$CB" plan --lead 7 2>"$TMP/plan.err"); prc=$?
python3 - "$out" <<'PY' && ok "1e plan --lead 7: cards [7,99,100], một nhánh issue-7-, ba dòng Closes, AC cộng 4 (2+1+1)" || fail "1e plan rc=$prc: $out $(cat "$TMP/plan.err")"
import json, sys
p = json.loads(sys.argv[1])
sys.exit(0 if p["cards"] == [7, 99, 100] and p["branch_prefix"] == "issue-7-" and p["ac_total"] == 4
         and p["closes"].splitlines() == ["Closes #7", "Closes #99", "Closes #100"] and [m["number"] for m in p["members"]] == [99, 100] else 1)
PY
out=$(cd "$TMP/repo" && FAKE_CLOSED=100 python3 "$CB" plan --lead 7 2>/dev/null)
python3 -c 'import json,sys; sys.exit(0 if json.loads(sys.argv[1])["cards"] == [7, 99] else 1)' "$out" 2>/dev/null \
  && ok "1f plan bỏ thành viên đã đóng" || fail "1f plan còn thành viên đóng: $out"

printf '## Problem\nbàn về cơ chế\n\n```\n<!-- sb:batch-of #7 -->\n```\n\n## Blocked by\n- None.\n' > "$FAKE_DIR/issue101.body"
items '[{"n":7},{"n":99,"from_created":1},{"n":101,"from_created":1}]'
out=$(cd "$TMP/repo" && python3 "$CB" plan --lead 7 2>/dev/null)
python3 -c 'import json,sys; sys.exit(0 if json.loads(sys.argv[1])["cards"] == [7, 99] else 1)' "$out" 2>/dev/null \
  && ok "1g marker trong code fence (thẻ bàn về cơ chế) không phải thành viên — cùng luật ac-check" || fail "1g plan: $out"

# 2. Trần đợt (#369): số thẻ, tổng AC; env rác → mặc định + cảnh báo.
reset_gh; echo 101 > "$FAKE_DIR/next"
items '[{"n":7},{"n":99,"body":"## Acceptance Criteria\n- [ ] m\n\n## Blocked by\n- #7 — đợt\n<!-- sb:batch-of #7 -->\n"},{"n":100,"body":"## Acceptance Criteria\n- [ ] m\n\n## Blocked by\n- #7 — đợt\n<!-- sb:batch-of #7 -->\n"}]'
na gate; rc=$(SB_MAX_BATCH_CARDS=3 run "${A[@]}")
[ "$rc" = 0 ] && [ "$(called issue create)" = 1 ] && [ -z "$(marker_of 101)" ] && ok "2a đợt đủ 3 thẻ (SB_MAX_BATCH_CARDS=3) → thẻ mới đứng riêng" || fail "2a rc=$rc marker=$(marker_of 101)"
reset_gh; echo 101 > "$FAKE_DIR/next"
na gate; rc=$(SB_MAX_BATCH_CARDS=4 run "${A[@]}")
[ "$(marker_of 101)" = 7 ] && ok "2b còn chỗ (4 thẻ) → vào đợt" || fail "2b marker=$(marker_of 101)"
reset_gh; echo 101 > "$FAKE_DIR/next"
rc=$(SB_MAX_BATCH_AC=4 run --title "✨ [feature] gate: việc 2 AC" --problem p --ac "- [ ] a" --ac "- [ ] b")
[ -z "$(marker_of 101)" ] && ok "2c 2 + 1 + 1 + 2 AC > SB_MAX_BATCH_AC=4 → riêng" || fail "2c marker=$(marker_of 101)"
reset_gh; echo 101 > "$FAKE_DIR/next"
na gate; rc=$(SB_MAX_BATCH_AC=5 run "${A[@]}")
[ "$(marker_of 101)" = 7 ] && ok "2d 2 + 1 + 1 + 1 = 5 ≤ 5 → vào đợt" || fail "2d marker=$(marker_of 101)"
reset_gh; echo 101 > "$FAKE_DIR/next"
na gate; rc=$(SB_MAX_BATCH_CARDS=abc run "${A[@]}")
[ "$rc" = 0 ] && grep -q "SB_MAX_BATCH_CARDS='abc' không hợp lệ" "$TMP/out" && ! grep -q Traceback "$TMP/out" && [ "$(marker_of 101)" = 7 ] \
  && ok "2e SB_MAX_BATCH_CARDS rác → cảnh báo, trần mặc định (5)" || fail "2e rc=$rc: $(head -3 "$TMP/out")"

# 3. Vẫn thẻ riêng: 🔴 High, --blocked-by, needs-you, --new-card, khác loại, thẻ trưởng High / là thành viên / đã đóng, repo chưa bật.
alone() {  # alone <tên ca> <lệnh create_task…>: thẻ mới tạo ra không có marker đợt
  local name="$1"; shift
  reset_gh; local r; r=$(run "$@")
  if [ "$r" = 0 ] && [ "$(called issue create)" = 1 ] && ! grep -q 'sb:batch-of' "$FAKE_DIR"/issue*.body 2>/dev/null; then ok "3 $name → thẻ riêng"
  else fail "3 $name rc=$r create=$(called issue create): $(grep -h 'sb:batch-of' "$FAKE_DIR"/issue*.body 2>/dev/null)"; fi
}
items '[{"n":7}]'
na gate; alone "🔴 High" "${A[@]}" --risk "🔴 **High** · đụng auth"
alone "--blocked-by" "${A[@]}" --blocked-by "- #123 — chờ"
alone "--needs-you" "${A[@]}" --needs-you "Cắm máy thật"
alone "--new-card" "${A[@]}" --new-card "việc độc lập cần PR riêng"
alone "khác loại (bug vs feature)" --title "🐛 [bug] gate: lỗi Z" --problem z --ac "- [ ] z"
items '[{"n":7,"body":"## Acceptance Criteria\n- [ ] a\n\n## Risk\n🔴 **High** · auth\n\n## Blocked by\n- None.\n"}]'
alone "thẻ trưởng High" "${A[@]}"
items '[{"n":7,"body":"## Acceptance Criteria\n- [ ] a\n\n## Blocked by\n- #5 — đợt\n<!-- sb:batch-of #5 -->\n"}]'
alone "ứng viên là thành viên đợt khác" "${A[@]}"
items '[{"n":7}]'
FAKE_CLOSED=7; export FAKE_CLOSED; alone "thẻ trưởng đã đóng" "${A[@]}"; unset FAKE_CLOSED
items '[{"n":7,"repo":"ToanMobile/OfficeReader"}]'
alone "repo chưa bật đợt (OfficeReader)" --repo ToanMobile/OfficeReader "${A[@]}"

# 4. --dry-run báo sẽ vào đợt #7, không tạo gì; cùng scope vẫn GOM (gom luôn trước đợt).
reset_gh; items '[{"n":7}]'
na gate; rc=$(run --dry-run "${A[@]}")
[ "$rc" = 0 ] && [ "$(called issue create)" = 0 ] && grep -q "đợt #7" "$TMP/out" && grep -q "sb:batch-of #7" "$TMP/out" \
  && ok "4a dry-run: báo đợt #7, body xem trước có marker, không tạo" || fail "4a rc=$rc: $(tail -3 "$TMP/out")"
na hooks; reset_gh; items '[{"n":7}]'
rc=$(run "${A[@]}")
[ "$rc" = 0 ] && [ "$(called issue create)" = 0 ] && [ "$(called issue edit)" = 1 ] && ok "4b cùng scope (hooks) → vẫn gom vào #7, không mở đợt" || fail "4b rc=$rc create=$(called issue create)"

# 5. split: thẻ bị chặn review tách khỏi đợt — revert đúng commit của nó, thẻ thành riêng, PR bỏ Closes + dòng sb:ac của nó.
reset_gh; items '[{"n":7},{"n":99},{"n":100},{"n":101}]'
G="$TMP/split"; git init -q --bare -b main "$G.git"; git init -q -b main "$G"
git -C "$G" config user.email t@example.invalid; git -C "$G" config user.name t
echo base > "$G/shared"; git -C "$G" add shared; git -C "$G" commit -qm init
git -C "$G" remote add origin "$G.git"; git -C "$G" push -q origin main; git -C "$G" fetch -q origin
git -C "$G" checkout -q -b issue-7-dot
for c in 7 99 100; do echo "$c" > "$G/f$c"; git -C "$G" add "f$c"; git -C "$G" commit -qm "✨ [feature] việc $c (#$c)"; done
member() { printf '## Problem\nm\n\n## Acceptance Criteria\n- [ ] m%s\n\n## Blocked by\n- #%s — đợt: build chung nhánh issue-%s-…\n<!-- sb:batch-of #%s -->\n' "$1" "$2" "$2" "$2" > "$FAKE_DIR/issue$1.body"; }
member 99 7; member 100 7; member 101 7
printf 'Tóm tắt\n\nCloses #7\nCloses #99\nCloses #100\n\n<!-- sb:ac -->\n- [x] trưởng a\n- [x] [#99] m99\n  ↳ bằng chứng 99\n- [x] [#100] m100\n<!-- /sb:ac -->\n' > "$FAKE_DIR/pr50.body"
split() { : > "$FAKE_LOG"; (cd "$G" && python3 "$CB" split --lead 7 --base origin/main "$@") >"$TMP/split.out" 2>&1; echo $?; }
rc=$(split --card 99 --reason "review chặn: thiếu test" --pr 50)
[ "$rc" = 0 ] && [ ! -e "$G/f99" ] && [ -e "$G/f7" ] && [ -e "$G/f100" ] && [ -z "$(git -C "$G" status --porcelain)" ] \
  && ok "5a split #99: commit (#99) bị revert, việc của #7/#100 còn, cây sạch" || fail "5a rc=$rc: $(tail -3 "$TMP/split.out"); $(ls "$G")"
python3 - "$FAKE_DIR/issue99.body" <<'PY' && ok "5b #99 thành thẻ riêng: Blocked by '- None.', không còn marker" || fail "5b body #99: $(cat "$FAKE_DIR/issue99.body")"
import re, sys
b = open(sys.argv[1]).read()
sec = re.split(r"(?m)^## Blocked by\s*$", b)[-1].strip().splitlines()
sys.exit(0 if "sb:batch-of" not in b and sec == ["- None."] and "- [ ] m99" in b else 1)
PY
[ "$(called issue comment)" = 1 ] && ok "5c comment lý do trên #99" || fail "5c comment=$(called issue comment)"
python3 - "$FAKE_DIR/pr50.body" <<'PY' && ok "5d PR #50: Closes #99 → Refs #99, dòng [#99] + dòng ↳ của nó bị bỏ, phần còn lại giữ" || fail "5d PR body: $(cat "$FAKE_DIR/pr50.body")"
import sys
b = open(sys.argv[1]).read()
sys.exit(0 if "Refs #99" in b and "Closes #99" not in b and "[#99]" not in b and "bằng chứng 99" not in b
         and "Closes #7" in b and "Closes #100" in b and "- [x] [#100] m100" in b and "- [x] trưởng a" in b else 1)
PY
rc=$(split --card 99 --reason lại)
[ "$rc" = 2 ] && grep -q "không còn là thành viên đợt #7" "$TMP/split.out" && ok "5e split lần hai (đã tách, hết marker) → exit 2, không đụng gì" || fail "5e rc=$rc: $(tail -2 "$TMP/split.out")"
rc=$(split --card 101 --reason "không có commit")
[ "$rc" = 3 ] && grep -q 'sb:batch-of #7' "$FAKE_DIR/issue101.body" && ok "5f thành viên chưa có commit nào → exit 3, thẻ giữ nguyên" || fail "5f rc=$rc"
git -C "$G" checkout -q main
rc=$(split --card 100 --reason "sai nhánh")
[ "$rc" = 4 ] && ok "5g đứng trên main (không phải issue-7-…) → exit 4" || fail "5g rc=$rc"
git -C "$G" checkout -q issue-7-dot; echo bẩn > "$G/f100"
rc=$(split --card 100 --reason "cây bẩn")
[ "$rc" = 4 ] && [ "$(cat "$G/f100")" = bẩn ] && ok "5h cây bẩn → exit 4, không revert, không mất sửa đổi" || fail "5h rc=$rc"
git -C "$G" checkout -q -- f100
# xung đột: #102 sửa `shared`, #7 sửa tiếp đúng dòng đó → revert #102 xung đột → exit 5, abort, cây sạch, thẻ giữ marker.
echo v102 > "$G/shared"; git -C "$G" commit -qam "✨ [feature] việc 102 (#102)"
echo v7b > "$G/shared"; git -C "$G" commit -qam "✨ [feature] việc 7 phần 2 (#7)"
member 102 7; head=$(git -C "$G" rev-parse HEAD)
rc=$(split --card 102 --reason "xung đột")
[ "$rc" = 5 ] && [ "$(git -C "$G" rev-parse HEAD)" = "$head" ] && [ -z "$(git -C "$G" status --porcelain)" ] \
  && [ ! -e "$G/.git/REVERT_HEAD" ] && grep -q 'sb:batch-of #7' "$FAKE_DIR/issue102.body" \
  && ok "5i revert xung đột → exit 5, abort, HEAD + cây như cũ, thẻ giữ marker" || fail "5i rc=$rc head=$(git -C "$G" rev-parse HEAD) st=$(git -C "$G" status --porcelain): $(tail -3 "$TMP/split.out")"

[ "$FAILS" -eq 0 ] && { echo "✅ test_card_batch: all passed"; exit 0; }
echo "❌ test_card_batch: $FAILS failed"; exit 1
