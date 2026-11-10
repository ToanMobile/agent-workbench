#!/usr/bin/env bash
# PR #924 (03/11): khi chính merge gate gửi nút Approve Telegram (chạy standalone, --preflight do drain_merge.sh hay người gọi), không ai
# đăng approval-request lên GitHub, nên bấm Approve bị bot từ chối "Chưa có approval-request cho head <sha7> của người có quyền ghi".
# Gate tự gửi nút thì tự đăng đúng một comment PR chứa dòng `approval-request:` đã in (chạy lại có comment đó rồi thì không đăng nữa);
# train/queue gọi khi queue bật thì như cũ (không comment, không nút: queue lo); đăng lỗi chỉ log, vẫn gửi nút, exit giữ nguyên;
# --dry-run không ghi GitHub nên không đăng.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
unset SB_MERGE_QUEUE SB_MERGE_CALLER SB_NOTIFY_SKIP SB_BOARD_WORKER
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-approve-req.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/heavy-slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
cp -R "$ROOT/.claude/bin" "$TMP/gatebin"
GATE="$TMP/gatebin/super-board-merge-gate.sh"
# approval giả: request in đúng một dòng, ghim head (đối số --head) như bản thật. Kiểm (không --request) theo luật validate() của bản
# thật, thu gọn: block MỚI NHẤT (tên file tăng dần) trên PR + issue liên kết (pr<n>.comments, issue7.comments); không block → "no request
# from …"; block mới nhất không chứa đúng dòng request → "the latest request does not cover …"; có → "waiting for … done …".
# FAKE_APPROVAL_JSON=<json>: kiểm in đúng json đó (why lấy nguyên văn từ approval.py thật, mục 10 ghim);
# FAKE_APPROVAL_FAIL=1: thoát 1 (gate lùi về {"approved":false}); FAKE_APPROVAL_UNVERIFIED=1: why "approval evidence could not be verified".
cat > "$TMP/gatebin/super-board-approval.py" <<'PY'
#!/usr/bin/env python3
import glob, json, os, re, sys
a = sys.argv
open(os.environ["FAKE_DIR"] + "/approval.calls", "a").write(" ".join(a[1:]) + "\n")  # mục 15 kiểm lần gọi
head, pr = a[a.index("--head") + 1], a[a.index("--pr") + 1]
line = 'approval-request: {"head":"%s","pr":%s,"repo":"o/r","scope":"%s"}' % (head, pr, "a" * 64)
if "--request" in a:
    print(line); sys.exit(0)
if os.environ.get("FAKE_APPROVAL_JSON"):   # sau nhánh --request: gate vẫn có dòng request nên vẫn vào case của needs_you_notify
    print(os.environ["FAKE_APPROVAL_JSON"]); sys.exit(0)
if os.environ.get("FAKE_APPROVAL_FAIL") == "1":
    sys.exit(1)
if os.environ.get("FAKE_APPROVAL_UNVERIFIED") == "1":
    print(json.dumps({"approved": False, "why": "approval evidence could not be verified"})); sys.exit(0)
d = os.environ["FAKE_DIR"]
files = glob.glob(f"{d}/pr{pr}.comments/*") + glob.glob(f"{d}/issue7.comments/*")
blocks = []
for f in files:
    body = open(f, encoding="utf-8").read()
    if re.search(r"Reason tag:[^\n]*🙋|^approval-request:", body, re.M):
        blocks.append((os.path.basename(f), body))
if not blocks:
    why = "no request from a trusted repository collaborator"
elif line not in max(blocks)[1].splitlines():
    why = "the latest request does not cover the current code and human steps"
else:
    why = "waiting for a trusted human to comment done on the current request"
print(json.dumps({"approved": False, "why": why}))
PY
cat > "$TMP/gatebin/super-board-notify.py" <<PY
#!/usr/bin/env python3
import sys
open("$TMP/notify.log", "a").write(" ".join(sys.argv[1:]) + "\n")
PY

O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/review-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm card
git -C "$R" push -q origin issue-5-x
H=$(git -C "$R" rev-parse issue-5-x)
git -C "$R" push -q origin "$H:refs/heads/issue-6-x"
git -C "$R" diff origin/main issue-5-x > "$TMP/pr5.diff"; cp "$TMP/pr5.diff" "$TMP/pr6.diff"
printf '{"files":[{"path":"b"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr5.meta"
printf '{"files":[{"path":"b"}],"labels":[],"body":"needs-you: run the live backfill","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr6.meta"
echo "$H" > "$TMP/pr5.head"; echo "$H" > "$TMP/pr6.head"

# gh giả: comment của PR n nằm trong $FAKE_DIR/pr<n>.comments (mỗi comment một file thân trong thư mục đó); `pr comment` ghi thêm một
# file (FAKE_COMMENT_FAIL=1: thoát 1, không ghi). `pr view --json comments` đọc lại chúng.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/gh.calls"
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
cdir="$FAKE_DIR/pr$n.comments"; mkdir -p "$cdir"
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"--json comments"*) for f in "$cdir"/*; do [ -f "$f" ] && cat "$f" && echo; done; exit 0 ;;
  *" pr view "*"title"*) echo "card $n" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr comment "*)
    [ "${FAKE_COMMENT_FAIL:-0}" = 1 ] && { echo "fake gh: comment refused" >&2; exit 1; }
    while [ $# -gt 0 ]; do [ "$1" = --body ] && { printf '%s' "$2" > "$cdir/9-$(date +%s)-$$-$RANDOM"; exit 0; }; shift; done
    echo "fake gh: pr comment without --body" >&2; exit 1 ;;
  *" pr merge "*) echo "fake gh: this test never merges" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
mkcfg() {  # mkcfg <file> <merge_queue.enabled> <merge_policy.default>
  python3 -c 'import json,sys
c={"base_branch":"main","repo":{"path":".","remote":""},"worker_backend":"claude-p",
   "merge_policy":{"default":sys.argv[3]},
   "merge_queue":{"enabled":sys.argv[2]=="true","enabled_at":None},
   "verify_commands":["touch " + sys.argv[4]]}
print(json.dumps(c))' "$1" "$2" "$3" "$TMP/verified" > "$1"
}
CFG_HUMAN_OFF="$TMP/cfg-human-off.json"; CFG_HUMAN_ON="$TMP/cfg-human-on.json"; CFG_OFF="$TMP/cfg-off.json"
mkcfg "$CFG_HUMAN_OFF" false human; mkcfg "$CFG_HUMAN_ON" true human; mkcfg "$CFG_OFF" false auto
REQ5="approval-request: {\"head\":\"$H\",\"pr\":5,\"repo\":\"o/r\",\"scope\":\"$(printf 'a%.0s' $(seq 64))\"}"
REQ6="approval-request: {\"head\":\"$H\",\"pr\":6,\"repo\":\"o/r\",\"scope\":\"$(printf 'a%.0s' $(seq 64))\"}"

gate() {  # gate <pr> <env…> -- <args…>
  local pr="$1"; shift
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  rm -f "$TMP/verified"; : > "$TMP/gh.calls"; : > "$TMP/notify.log"
  rm -rf "$R/.git/super-board/verified-trees"
  ( cd "$WT" && env ${envs[@]+"${envs[@]}"} bash "$GATE" --pr "$pr" "$@" ) >"$TMP/out" 2>"$TMP/err"; RC=$?
}
ncomments() { ls "$TMP/pr$1.comments" 2>/dev/null | wc -l | tr -d ' '; }
nreq() { for f in "$TMP/pr$1.comments"/*; do [ -f "$f" ] && cat "$f" && echo; done | grep -cxF "$2" | tr -d ' '; }  # mỗi file một thân, cách dòng
napprove() { grep -c '^approve-button ' "$TMP/notify.log" | tr -d ' '; }
why() { echo "rc=$RC comments=$(ncomments "${1:-5}") approve=$(napprove) out=[$(tail -3 "$TMP/out" | tr '\n' '|')] err=[$(tail -3 "$TMP/err" | tr '\n' '|')]"; }
clear_comments() { rm -rf "$TMP/pr$1.comments"; }

# ── 1. Standalone, queue tắt, policy cần người: exit 7, đúng một comment PR chứa dòng approval-request của head này, nút được gửi.
clear_comments 5
gate 5 -- --config "$CFG_HUMAN_OFF" --expect-head "$H"
[ "$RC" -eq 7 ] && grep -qxF "$REQ5" "$TMP/out" \
  && ok "standalone human-gate: exit 7 and the approval-request line still on stdout" || fail "standalone exit 7: $(why)"
[ "$(ncomments 5)" = 1 ] && [ "$(nreq 5 "$REQ5")" = 1 ] \
  && ok "standalone human-gate: exactly one PR comment carrying the approval-request line for head ${H:0:7}" \
  || fail "standalone comment, want 1 with the request: $(why)"
cat "$TMP/pr5.comments"/* 2>/dev/null | head -1 | grep -qxF "[merge-gate] [blocker] 🛑 needs a person · head ${H:0:7}" \
  && ok "the comment opens with the house blocker line naming head ${H:0:7}" || fail "comment header: $(cat "$TMP/pr5.comments"/* 2>/dev/null | head -1)"
[ "$(napprove)" = 1 ] && ok "standalone human-gate: the approve button is sent once" || fail "standalone button: $(why)"

# ── 2. Chạy lại khi comment đó đã có: không comment thứ hai, nút vẫn gửi, exit 7.
gate 5 -- --config "$CFG_HUMAN_OFF" --expect-head "$H"
[ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 1 ] && [ "$(napprove)" = 1 ] \
  && ok "rerun with the request already on the PR: no second comment, button sent, exit 7" || fail "rerun dedupe: $(why)"

# ── 3. Queue bật, SB_MERGE_CALLER=queue: không comment, không nút (queue lo), exit 7 như cũ.
clear_comments 5
gate 5 SB_MERGE_CALLER=queue -- --config "$CFG_HUMAN_ON" --expect-head "$H"
[ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 0 ] && [ "$(napprove)" = 0 ] && ! grep -q ' pr comment ' "$TMP/gh.calls" \
  && ok "queue caller with the queue on: no comment, no button, exit 7" || fail "queue caller: $(why)"
gate 5 SB_MERGE_CALLER=train -- --config "$CFG_HUMAN_ON" --expect-head "$H" --preflight
[ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 0 ] && [ "$(napprove)" = 0 ] \
  && ok "train --preflight with the queue on: no comment, no button, exit 7" || fail "train preflight queue on: $(why)"

# ── 3b. Queue bật, --standalone (super-review ngoài board): gate tự gửi nút nên tự đăng request.
gate 5 -- --config "$CFG_HUMAN_ON" --expect-head "$H" --standalone
[ "$RC" -eq 7 ] && [ "$(nreq 5 "$REQ5")" = 1 ] && [ "$(napprove)" = 1 ] \
  && ok "queue on + --standalone: request posted, button sent, exit 7" || fail "standalone queue on: $(why)"

# ── 4. --preflight (drain_merge.sh, queue tắt) với bước chỉ người làm: exit 8, comment request được đăng, nút gửi.
clear_comments 6
gate 6 SB_MERGE_CALLER=train -- --config "$CFG_OFF" --expect-head "$H" --preflight
[ "$RC" -eq 8 ] && grep -qxF 'needs-you: run the live backfill' "$TMP/out" \
  && ok "--preflight needs-you: exit 8 with the needs-you line" || fail "preflight exit 8: $(why 6)"
[ "$(ncomments 6)" = 1 ] && [ "$(nreq 6 "$REQ6")" = 1 ] && [ "$(napprove)" = 1 ] \
  && ok "--preflight needs-you: one PR comment with the approval-request, button sent" || fail "preflight comment: $(why 6)"

# ── 5. Đăng lỗi: log rõ, vẫn gửi nút, exit 7 giữ nguyên.
clear_comments 5
gate 5 FAKE_COMMENT_FAIL=1 -- --config "$CFG_HUMAN_OFF" --expect-head "$H"
[ "$RC" -eq 7 ] && [ "$(napprove)" = 1 ] && grep -q 'approval-request' "$TMP/err" && grep -qi 'could not post' "$TMP/err" \
  && ok "comment post fails: a clear log line, the button still goes out, exit 7" || fail "post failure: $(why)"

# ── 6. --dry-run không ghi GitHub: không comment, exit 7 như cũ.
clear_comments 5
gate 5 -- --config "$CFG_HUMAN_OFF" --expect-head "$H" --dry-run
[ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 0 ] && ! grep -q ' pr comment ' "$TMP/gh.calls" \
  && ok "--dry-run: no PR comment, exit 7" || fail "dry-run: $(why)"
# Humans-vs.-UFOs PR #129 (08/11): dry-run gửi nút cho head mới mà không đăng request, bấm thì bot báo "Yêu cầu duyệt mới nhất
# không phải cho PR #129 head …". Ca này đòi: dry-run chưa có request hiện hành thì không gửi nút.
[ "$(napprove)" = 0 ] && grep -q 'button not sent' "$TMP/err" \
  && ok "--dry-run, no current request: no dead Approve button" || fail "dry-run dead button: $(why)"
# Request hiện hành đã có (đang chờ done): dry-run vẫn gửi nút, nút đó dùng được.
mkdir -p "$TMP/pr5.comments"; printf '[merge-gate] [blocker] 🛑 needs a person\n%s' "$REQ5" > "$TMP/pr5.comments/001"
gate 5 -- --config "$CFG_HUMAN_OFF" --expect-head "$H" --dry-run
[ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 1 ] && [ "$(napprove)" = 1 ] \
  && ok "--dry-run, request current: button sent, exit 7" || fail "dry-run current request: $(why)"
clear_comments 5

# ── 7. (a) Block 🙋 của lane trên issue liên kết đã mang đúng dòng request: request hiện hành có rồi → không đăng lên PR (đăng thì PR
#       giữ block mới nhất và `done` trên issue bị bỏ qua); nút vẫn gửi, exit 7.
clear_comments 5; rm -rf "$TMP/issue7.comments"; mkdir -p "$TMP/issue7.comments"
printf '[merge-queue] [blocker] 🛑 blocked · 🙋\nReason tag:  🙋\n%s\nblocked-by: -' "$REQ5" > "$TMP/issue7.comments/001"
gate 5 -- --config "$CFG_HUMAN_OFF" --expect-head "$H"
[ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 0 ] && [ "$(napprove)" = 1 ] \
  && ok "(a) current request already on the linked issue: no PR comment, button sent, exit 7" || fail "(a) linked-issue request: $(why)"
rm -rf "$TMP/issue7.comments"

# ── 8. (a2) Kiểm duyệt đọc lỗi (approval.py thoát lỗi, hay why "could not be verified"): không đăng (có thể đè một `done`); nút vẫn gửi.
clear_comments 5
gate 5 FAKE_APPROVAL_FAIL=1 -- --config "$CFG_HUMAN_OFF" --expect-head "$H"
[ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 0 ] && [ "$(napprove)" = 1 ] && grep -qxF "$REQ5" "$TMP/out" \
  && ok "(a2) approval check failed: no PR comment, request still on stdout, button sent, exit 7" || fail "(a2) approval failure: $(why)"
gate 5 FAKE_APPROVAL_UNVERIFIED=1 -- --config "$CFG_HUMAN_OFF" --expect-head "$H"
[ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 0 ] && [ "$(napprove)" = 1 ] \
  && ok "(a2) approval evidence could not be verified: no PR comment, button sent, exit 7" || fail "(a2) unverified: $(why)"

# ── 9. (b) PR có dòng request cũ L nhưng block mới hơn mang scope khác: request hiện hành không còn → đăng lại L, nút gửi, exit 7.
clear_comments 5; mkdir -p "$TMP/pr5.comments"
printf '[merge-gate] [blocker] 🛑 needs a person · head %s\n%s' "${H:0:7}" "$REQ5" > "$TMP/pr5.comments/001"
printf '%s' "${REQ5/aaaaaaaa/bbbbbbbb}" > "$TMP/pr5.comments/002"
gate 5 -- --config "$CFG_HUMAN_OFF" --expect-head "$H"
[ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 3 ] && [ "$(nreq 5 "$REQ5")" = 2 ] && [ "$(napprove)" = 1 ] \
  && ok "(b) newer block with another scope: the current request is posted again, button sent, exit 7" || fail "(b) superseded request: $(why)"

# ── 10. Chuỗi why mà case của needs_you_notify so khớp phải có nguyên văn trong approval.py THẬT (không phải bản giả ở trên): sửa câu
#        chữ ở approval.py mà quên gate thì gate thôi đăng request mà không test nào đỏ. Rút literal từ mã gate, không chép tay.
python3 - "$ROOT/.claude/bin/super-board-merge-gate.sh" "$ROOT/.claude/bin/super-board-approval.py" <<'PY' >"$TMP/pin.out" 2>&1 \
  && ok "every why literal in the needs_you_notify case is verbatim in the real approval.py ($(tail -1 "$TMP/pin.out"))" \
  || fail "why literals vs real approval.py: $(tr '\n' '|' < "$TMP/pin.out")"
import re, sys
gate = open(sys.argv[1], encoding="utf-8").read()
real = open(sys.argv[2], encoding="utf-8").read()
body = re.search(r"^needs_you_notify\(\) \{\n(.*?)^\}", gate, re.S | re.M)
if not body:
    sys.exit("needs_you_notify() not found in the gate")
lits = []
for line in body.group(1).splitlines():
    m = re.match(r'\s*("[^"]*"(?:\|"[^"]*")*)\s*\)', line)
    if m:
        lits += re.findall(r'"([^"]*)"', m.group(1))
if len(lits) < 2:
    sys.exit(f"too few case literals extracted: {lits}")
missing = [l for l in lits if f'"{l}"' not in real]
if missing:
    sys.exit("not in the real approval.py: " + "; ".join(missing))
print(f"{len(lits)} literals")
PY
# Các why mục 11–13 đưa vào bản giả cũng phải là chuỗi thật.
WHY_EDITED="approval request was edited; post a fresh request"
WHY_CROSS="waiting for a cross-review marker or a trusted human done on the current request"
WHY_DONE="trusted human confirmed the current request"
for w in "$WHY_EDITED" "$WHY_CROSS" "$WHY_DONE"; do
  grep -qF "\"$w\"" "$ROOT/.claude/bin/super-board-approval.py" && ok "fake why is a real approval.py string: $w" || fail "fake why not in approval.py: $w"
done

# ── 11. Request mới nhất bị sửa (why "approval request was edited…"): không còn request hiện hành → đăng request, nút gửi, exit 7.
clear_comments 5
gate 5 "FAKE_APPROVAL_JSON={\"approved\":false,\"why\":\"$WHY_EDITED\"}" -- --config "$CFG_HUMAN_OFF" --expect-head "$H"
[ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 1 ] && [ "$(nreq 5 "$REQ5")" = 1 ] && [ "$(napprove)" = 1 ] \
  && ok "edited request: the current request is posted, button sent, exit 7" || fail "edited request: $(why)"

# ── 12. Đang chờ marker duyệt chéo hay `done` trên request hiện hành: không đăng, không khuyên đăng tay, nút gửi, exit 7.
clear_comments 5
gate 5 "FAKE_APPROVAL_JSON={\"approved\":false,\"why\":\"$WHY_CROSS\"}" -- --config "$CFG_HUMAN_OFF" --expect-head "$H"
[ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 0 ] && [ "$(napprove)" = 1 ] && grep -qxF "$REQ5" "$TMP/out" && ! grep -q 'by hand' "$TMP/err" \
  && ok "waiting for a cross-review marker: no PR comment, no hand-post advice, button sent, exit 7" || fail "cross-review wait: $(why)"

# ── 13. Người đã `done` hợp lệ (approved=true) nhưng migration lỗi sau verify (exit 8): không đăng, và không khuyên đăng tay (đăng
#        request mới sẽ đè `done` đó); nút vẫn gửi.
git -C "$R" branch -q --no-track issue-8-x main
WT8="$R/.claude/worktrees/review-8"; git -C "$R" worktree add -q "$WT8" issue-8-x
mkdir -p "$WT8/db/migrate"; echo 'create table t (id int);' > "$WT8/db/migrate/001_add.sql"
git -C "$WT8" add db; git -C "$WT8" commit -qm mig; git -C "$R" push -q origin issue-8-x
H8=$(git -C "$R" rev-parse issue-8-x); echo "$H8" > "$TMP/pr8.head"
git -C "$R" diff origin/main issue-8-x > "$TMP/pr8.diff"
printf '{"files":[{"path":"db/migrate/001_add.sql"}],"labels":[],"body":"needs-you: run the live backfill","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr8.meta"
CFG_MIG="$TMP/cfg-mig.json"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); c["migrations"]={"allowed_envs":["test"],"target_env":"test","commands":{"test":"false"}}; json.dump(c,open(sys.argv[2],"w"))' "$CFG_OFF" "$CFG_MIG"
clear_comments 8; : > "$TMP/gh.calls"; : > "$TMP/notify.log"
( cd "$WT8" && env "FAKE_APPROVAL_JSON={\"approved\":true,\"why\":\"$WHY_DONE\"}" SB_MERGE_RECHECK_DELAY_S=0 SB_MERGE_AUTO_POLL_S=1 \
    bash "$GATE" --pr 8 --config "$CFG_MIG" --expect-head "$H8" --lock-timeout 5 ) >"$TMP/out" 2>"$TMP/err"; RC=$?
[ "$RC" -eq 8 ] && grep -q 'FAILED: migrate test' "$TMP/err" && [ "$(ncomments 8)" = 0 ] && [ "$(napprove)" = 1 ] \
  && ! grep -q 'by hand' "$TMP/err" && ! grep -q 'no clear verdict' "$TMP/err" \
  && ok "approved=true, migration failed: exit 8, no PR comment, no hand-post advice, button sent" || fail "approved + failed migration: $(why 8)"

# ── 14. (Grok P1) SB_NOTIFY_SKIP=1: board_notify không gửi nút nên gate không đăng request (trước PR #924 gate không ghi gì).
clear_comments 5
gate 5 SB_NOTIFY_SKIP=1 -- --config "$CFG_HUMAN_OFF" --expect-head "$H"
[ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 0 ] && [ "$(napprove)" = 0 ] && ! grep -q ' pr comment ' "$TMP/gh.calls" \
  && grep -qxF "$REQ5" "$TMP/out" \
  && ok "SB_NOTIFY_SKIP=1: no button, no PR comment, request still on stdout, exit 7" || fail "notify skip: $(why)"

# ── 15. (Grok P1) Migration lỗi, policy không human / needs_you: approval_check chưa chạy nên APPROVAL rỗng. Gate tự đọc phán quyết
#        (approval.py kiểm, không --request, phải được gọi), không có request → đăng request, nút gửi, exit 8.
git -C "$R" branch -q --no-track issue-9-x main
WT9="$R/.claude/worktrees/review-9"; git -C "$R" worktree add -q "$WT9" issue-9-x
mkdir -p "$WT9/db/migrate"; echo 'create table u (id int);' > "$WT9/db/migrate/001_add.sql"
git -C "$WT9" add db; git -C "$WT9" commit -qm mig9; git -C "$R" push -q origin issue-9-x
H9=$(git -C "$R" rev-parse issue-9-x); echo "$H9" > "$TMP/pr9.head"
git -C "$R" diff origin/main issue-9-x > "$TMP/pr9.diff"
printf '{"files":[{"path":"db/migrate/001_add.sql"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr9.meta"
REQ9="approval-request: {\"head\":\"$H9\",\"pr\":9,\"repo\":\"o/r\",\"scope\":\"$(printf 'a%.0s' $(seq 64))\"}"
clear_comments 9; : > "$TMP/gh.calls"; : > "$TMP/notify.log"; : > "$TMP/approval.calls"
( cd "$WT9" && env SB_MERGE_RECHECK_DELAY_S=0 SB_MERGE_AUTO_POLL_S=1 \
    bash "$GATE" --pr 9 --config "$CFG_MIG" --expect-head "$H9" --lock-timeout 5 ) >"$TMP/out" 2>"$TMP/err"; RC=$?
[ "$RC" -eq 8 ] && grep -q 'FAILED: migrate test' "$TMP/err" && grep -v -- '--request' "$TMP/approval.calls" | grep -q -- "--head $H9" \
  && ok "failed migration, no human/needs_you: exit 8 and the approval check is run on the spot" \
  || fail "on-the-spot check: $(why 9) calls=[$(tr '\n' '|' < "$TMP/approval.calls")]"
[ "$(ncomments 9)" = 1 ] && [ "$(nreq 9 "$REQ9")" = 1 ] && [ "$(napprove)" = 1 ] \
  && ok "failed migration, no human/needs_you: the request is posted and the button sent" || fail "on-the-spot post: $(why 9)"

# ── 16. (Grok P2) Kiểm lỗi / không đọc được bằng chứng: không đăng và không khuyên người đăng tay (comment tay thành block mới nhất,
#        có thể bỏ rơi một `done` mà lần kiểm không đọc được).
for e in FAKE_APPROVAL_FAIL=1 FAKE_APPROVAL_UNVERIFIED=1; do
  clear_comments 5
  gate 5 "$e" -- --config "$CFG_HUMAN_OFF" --expect-head "$H"
  [ "$RC" -eq 7 ] && [ "$(ncomments 5)" = 0 ] && [ "$(napprove)" = 1 ] && ! grep -qi 'by hand' "$TMP/err" \
    && ! grep -qi 'post the approval-request line' "$TMP/err" && grep -q 'approval-request not posted' "$TMP/err" \
    && ok "$e: no PR comment, no hand-post advice, button sent, exit 7" || fail "$e advice: $(why)"
done

# ── 17. Lần đọc phán quyết tại chỗ (mục 15) lỗi: không fatal, không đăng, nút vẫn gửi, exit 8 giữ nguyên.
clear_comments 9; : > "$TMP/gh.calls"; : > "$TMP/notify.log"; : > "$TMP/approval.calls"
( cd "$WT9" && env FAKE_APPROVAL_FAIL=1 SB_MERGE_RECHECK_DELAY_S=0 SB_MERGE_AUTO_POLL_S=1 \
    bash "$GATE" --pr 9 --config "$CFG_MIG" --expect-head "$H9" --lock-timeout 5 ) >"$TMP/out" 2>"$TMP/err"; RC=$?
[ "$RC" -eq 8 ] && [ "$(ncomments 9)" = 0 ] && [ "$(napprove)" = 1 ] && grep -q 'approval-request not posted' "$TMP/err" \
  && grep -v -- '--request' "$TMP/approval.calls" | grep -q -- "--head $H9" \
  && ok "on-the-spot check fails: non-fatal, no PR comment, button sent, exit 8" || fail "on-the-spot failure: $(why 9)"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
