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
# FAKE_APPROVAL_FAIL=1: thoát 1 (gate lùi về {"approved":false}); FAKE_APPROVAL_UNVERIFIED=1: why "approval evidence could not be verified".
cat > "$TMP/gatebin/super-board-approval.py" <<'PY'
#!/usr/bin/env python3
import glob, json, os, re, sys
a = sys.argv
head, pr = a[a.index("--head") + 1], a[a.index("--pr") + 1]
line = 'approval-request: {"head":"%s","pr":%s,"repo":"o/r","scope":"%s"}' % (head, pr, "a" * 64)
if "--request" in a:
    print(line); sys.exit(0)
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

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
