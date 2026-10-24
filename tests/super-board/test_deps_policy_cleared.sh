#!/usr/bin/env bash
# Test hồi quy: thẻ Blocked vì human-gate phải TỰ ra khi chính sách hiện tại không còn đòi người duyệt.
# 2026-10-18: GeelyEx2 #40 (PR #45) và OfficeReader #80 (PR #127) kẹt Blocked với comment 🙋 "size" của 16/10, dù PR #57 đã đặt
# auto_max_lines = 0 từ 18/10. super-board-approval.py --deps chỉ nhận một comment `done` của người, không bao giờ chạy lại
# chính sách, nên chủ repo phải gõ `done` tay. Sửa: `--deps --config <cfg>` chạy lại merge-policy trên PR của request; plan.human
# và plan.needs_you rỗng thì needsYouDone = true. Chính sách vẫn đòi người (cỡ code thật, always_human, needs-you) thì giữ nguyên.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APPROVAL="$ROOT/.claude/bin/super-board-approval.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export SB_GITHUB_HALT_FILE="$TMP/github-halt.json"   # never the real checkout's board halt (24/10: o/r halted the board)

HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
cat > "$TMP/harness.py" <<'PY'
import importlib.util, io, json, sys

approval_path, config, files_json, body, pr_head, with_config = sys.argv[1:7]
spec = importlib.util.spec_from_file_location("approval", approval_path)
approval = importlib.util.module_from_spec(spec)
spec.loader.exec_module(approval)

HEAD = "a" * 40
REQUEST = {"repo": "o/r", "pr": 7, "head": HEAD, "scope": "b" * 64}
COMMENT = {"id": 1, "user": {"login": "owner", "type": "User"}, "created_at": "2026-10-16T18:17:31Z",
           "updated_at": "2026-10-16T18:17:31Z",
           "body": "🙋 Reason tag: needs you\napproval-request: " + json.dumps(REQUEST, sort_keys=True, separators=(",", ":"))}
files = json.loads(files_json)
META = {"labels": [], "body": body, "files": files,
        "additions": sum(f["additions"] for f in files), "deletions": sum(f["deletions"] for f in files),
        "changedFiles": len(files)}


def fake_read(args, kind="json", meta=None, recovering=False):
    args = list(args)
    if args[0] == "api" and args[-1].endswith("/permission"):
        return "", {"permission": "admin"}
    if args[0] == "api" and "--paginate" in args and "graphql" not in args:
        return "", [[COMMENT] if "/issues/40/" in args[-1] else []]
    if "graphql" in args:
        node = {"headRefOid": pr_head, "state": "OPEN", "baseRefName": "main", "body": "",
                "closingIssuesReferences": {"pageInfo": {"hasNextPage": False},
                                            "nodes": [{"number": 40, "repository": {"nameWithOwner": "o/r"}}]}}
        return "", [{"data": {"repository": {"defaultBranchRef": {"name": "main"}, "pullRequest": node}}}]
    if args[:2] == ["pr", "view"]:
        return "", META
    if args[:2] == ["pr", "diff"]:
        return "", ""
    raise AssertionError("unexpected gh read: %r" % (args,))


approval.github_read.read = fake_read
sys.argv = ["approval", "--deps", "--repo", "o/r"] + (["--config", config] if with_config == "1" else [])
sys.stdin = io.StringIO(json.dumps({"40": {"number": 40, "needsYou": True}}))
approval.main()
PY

run() {  # $1 config, $2 files json, $3 body, $4 PR head, $5 pass --config (1/0); in ra "<needsYouDone>|<approvalRefresh>|<why>"
  python3 "$TMP/harness.py" "$APPROVAL" "$1" "$2" "$3" "$4" "$5" 2>&1 | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    e = json.loads(raw)["40"]
    print("%s|%s|%s" % (str(e["needsYouDone"]).lower(), str(e["approvalRefresh"]).lower(), e.get("approvalWhy", "")))
except Exception:
    print("ERROR|" + raw.strip().splitlines()[-1][:160] if raw.strip() else "ERROR|empty")'
}

echo '{"merge_policy":{"default":"auto","auto_max_lines":0},"base_branch":"main"}' > "$TMP/open.json"
echo '{"merge_policy":{"default":"auto","auto_max_lines":400},"base_branch":"main"}' > "$TMP/cap400.json"
BIG='[{"path":"app/src/Feature.kt","additions":225,"deletions":84},{"path":"docs/super-board/runs/x/report.md","additions":725,"deletions":0}]'
HUGE='[{"path":"app/src/Feature.kt","additions":450,"deletions":0}]'
AUTH='[{"path":"server/auth/login.kt","additions":5,"deletions":0}]'

R="$(run "$TMP/open.json" "$BIG" "" "$HEAD" 1)"
[ "${R%%|*}" = true ] && ok "cap 0 (no size gate) + no human step: blocked card is cleared without a human 'done'" \
  || fail "card stays Blocked although policy no longer asks for a human: $R"

R="$(run "$TMP/open.json" "$BIG" "" "$HEAD" 0)"
[ "${R%%|*}" = false ] && ok "no --config: behaviour unchanged (still waits for a human)" \
  || fail "approval cleared without a config to re-run the policy: $R"

R="$(run "$TMP/cap400.json" "$HUGE" "" "$HEAD" 1)"
[ "${R%%|*}" = false ] && ok "450 lines of real code over cap 400: still waits for a human" \
  || fail "size gate weakened by the re-check: $R"

R="$(run "$TMP/open.json" "$AUTH" "" "$HEAD" 1)"
[ "${R%%|*}" = false ] && ok "always_human (auth path) still waits for a human with cap 0" \
  || fail "auth change cleared automatically: $R"

R="$(run "$TMP/open.json" "$BIG" "needs-you: npm run db:migrate:live" "$HEAD" 1)"
[ "${R%%|*}" = false ] && ok "PR body 'needs-you:' step still waits for a human" \
  || fail "needs-you step cleared automatically: $R"

R="$(run "$TMP/open.json" "$BIG" "" "cccccccccccccccccccccccccccccccccccccccc" 1)"
case "$R" in
  false\|true\|*) ok "head moved after the request: not cleared, approval refresh requested" ;;
  *) fail "head change must stay a refresh case, not a clearance: $R" ;;
esac

[ "$FAILS" -eq 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
