#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# session_card.sh — UserPromptSubmit + PreToolUse (Edit|Write). A task that starts in chat has no issue, so it never
# reached the GitHub Project board nor Agent Office (03/11, owner: "mọi task đều phải hiển thị lên board để theo dõi").
# This hook gives every such session ONE card:
#   UserPromptSubmit  stash the session's first prompt (the transcript of the running turn is not flushed yet, see
#                     read_ledger.sh), nothing else.
#   PreToolUse        the first edit of a file inside the repo claims the session (atomic mkdir: parallel Edit hooks make one
#                     card) and forks the worker: `gh issue create --label session` → project item-add →
#                     super-board-card.sh move N Building. The card sits in Building, never Ready (a Ready card is built by
#                     the runner, a duplicate of the chat session; the runner leaves label `session` alone when it reclaims
#                     stranded Building cards). The PR of the session closes it with `Closes #N`; a later edit tells the
#                     session its number once.
# Skipped: a subagent (agent_id), a board lane (issue-N-* branch/worktree), a repo with no super-board config or card script,
# an edit outside the repo (or in .claude/audit-gate, .agents/local), a headless `claude -p` run (entrypoint sdk-cli), SESSION_CARD=0.
# Never blocks: always exit 0; the worker is in the background, logs to <main>/.claude/audit-gate/session_card.log, and a
# failed attempt is retried at the next edit, 3 tries in all. State: <main>/.claude/audit-gate/session_card/<session>.*
# (main checkout = parent of the git common dir, so a worktree session does not get a second card).
# SESSION_CARD_WAIT=1 runs the worker in the foreground (test seam).
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

SC_MAX_TRIES=3

# ponytail: title heuristics are keyword based (fix/docs/refactor/test/feat, else chore); upgrade when cards come out mistyped.
sc_title() {   # sc_title <prompt file> <transcript> <rel file> <session> → one line
  python3 -I - "$@" <<'PY'
import json, os, re, sys
pf, tr, rel, sid = sys.argv[1:5]

def first_user(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(d, dict) or d.get("isMeta"):
                    continue
                m = d.get("message") if isinstance(d.get("message"), dict) else {}
                if d.get("type") != "user" and m.get("role") != "user":
                    continue
                c = m.get("content", d.get("content"))
                if isinstance(c, list):
                    c = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
                if isinstance(c, str) and c.strip() and not c.lstrip().startswith("<"):
                    return c
    except OSError:
        pass
    return ""

text = ""
try:
    with open(pf, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
except OSError:
    pass
if not text.strip() and tr:
    text = first_user(tr)
line = next((l.strip() for l in text.splitlines() if l.strip()), "")
# The issue may be public: mask tokens, long opaque strings and key=value secrets before the prompt leaves the machine.
line = re.sub(r"(?i)\b(password|passwd|token|secret|api[_-]?key)\b\s*[=:]\s*\S+", r"\1=***", line)
line = re.sub(r"\b(?:gh[pousr]_|sk-|xox[a-z]-|AKIA)[A-Za-z0-9_\-]{8,}", "***", line)
line = re.sub(r"[A-Za-z0-9+/_\-]{32,}", "***", line)
line = re.sub(r"\s+", " ", line)
if not line:
    line = "chat session " + sid[:8]
subject = line if len(line) <= 72 else line[:71].rstrip() + "…"
low = line.lower()[:300]
for rx, emoji, kind in (
    (r"\b(fix|bug|crash|hotfix)\b|lỗi", "🐛", "fix"),
    (r"\b(docs?|readme)\b|tài liệu", "📝", "docs"),
    (r"\brefactor", "♻️", "refactor"),
    (r"\btests?\b", "🧪", "test"),
    (r"\b(add|implement|feat|new|build|create)\b|thêm|tạo", "✨", "feat"),
):
    if re.search(rx, low):
        break
else:
    emoji, kind = "🔧", "chore"
scope = rel.split("/")[0] if "/" in rel else os.path.splitext(rel)[0]
print(f"{emoji} [{kind}] {scope or 'session'}: {subject}")
PY
}

sc_config() {   # sc_config <main> <top> → "<config path>\t<owner>\t<number>\t<owner/repo>"
  python3 -I - "$@" <<'PY'
import glob, json, os, re, subprocess, sys
main, top = sys.argv[1:3]
def slug(url):
    m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", url or "")
    return m.group(1) if m else ""
try:
    origin = slug(subprocess.run(["git", "-C", top, "remote", "get-url", "origin"], capture_output=True, text=True, timeout=10).stdout.strip())
except (OSError, subprocess.SubprocessError):
    origin = ""
best = None
for p in sorted(glob.glob(os.path.join(main, ".claude/super-board/configs/*.json"))):
    try:
        c = json.load(open(p))
        s = slug(c["repo"]["remote"]) or origin
        row = (p, c["project"]["owner"], str(c["project"]["number"]), s)
    except (OSError, ValueError, KeyError, TypeError):
        continue
    if best is None or (origin and s == origin and best[3] != origin):
        best = row
if best and best[3]:
    print("\t".join(best))
PY
}

sc_worker() {
  local SD="$SC_SD" SID="$SC_SID" LOG="$SC_MAIN/.claude/audit-gate/session_card.log" wd rc=0
  sc_log() { echo "[$(date +%Y-%m-%dT%H:%M:%S)] ${SID} $*" >> "$LOG" 2>/dev/null || true; }
  ( sleep 120; kill -TERM $$ 2>/dev/null ) >/dev/null 2>&1 & wd=$!
  trap 'kill "$wd" 2>/dev/null' EXIT
  sc_fail() {
    local n; n=$(( $(cat "$SD/$SID.fails" 2>/dev/null || echo 0) + 1 ))
    echo "$n" > "$SD/$SID.fails"
    sc_log "FAILED ($1) try $n/$SC_MAX_TRIES"
    [ "$n" -ge "$SC_MAX_TRIES" ] || rm -rf "$SD/$SID.d"   # release the claim: the next edit retries
    exit 0
  }
  local cfg owner number slug card="$SC_TOP/.claude/bin/super-board-card.sh" row
  [ -f "$card" ] || card="$SC_MAIN/.claude/bin/super-board-card.sh"
  row="$(sc_config "$SC_MAIN" "$SC_TOP")"
  [ -n "$row" ] || { sc_log "no usable super-board config"; exit 0; }
  IFS=$'\t' read -r cfg owner number slug <<<"$row"
  local n url title body
  n="$(cat "$SD/$SID.card" 2>/dev/null || true)"
  if [ -z "$n" ]; then   # a retry after a half-done try reuses the issue
    title="$(sc_title "$SD/$SID.prompt" "$SC_TRANSCRIPT" "$SC_REL" "$SID")" || sc_fail "title"
    body="## Problem
Task started in a chat session with no ticket; this card tracks it on the board (DevKit hooks/session_card.sh).

## Context
- session: ${SID}
- first edit: ${SC_REL}
- opened: $(date +%Y-%m-%dT%H:%M:%S%z)

## Fix
In progress in that session. Its PR closes this card with a closing keyword and this issue's number.

## Blocked by
- None.

<!-- sb:session ${SID} -->"
    gh label create session --repo "$slug" --color 5319E7 --description "Task started in a chat session (not built by the board)" --force >/dev/null 2>&1 || true
    url="$(gh issue create --repo "$slug" --title "$title" --label session --body "$body" 2>>"$LOG")" || sc_fail "issue create"
    n="${url##*/}"
    case "$n" in ''|*[!0-9]*) sc_fail "issue url '$url'" ;; esac
    echo "$n" > "$SD/$SID.card"
  else
    url="https://github.com/$slug/issues/$n"
  fi
  gh project item-add "$number" --owner "$owner" --url "$url" >>"$LOG" 2>&1 || sc_fail "project item-add"
  if ! bash "$card" --config "$cfg" move "$n" Building >>"$LOG" 2>&1; then
    sleep 3   # the new item may not be readable yet
    bash "$card" --config "$cfg" move "$n" Building >>"$LOG" 2>&1 || sc_fail "move to Building"
  fi
  rm -f "$SD/$SID.fails"
  sc_log "card #${n} → Building"
  exit 0
}

if [ "${1:-}" = "--worker" ]; then sc_worker; exit 0; fi

INPUT="$(cat)"
[ "${SESSION_CARD:-1}" = "0" ] && exit 0
[ "${CLAUDE_CODE_ENTRYPOINT:-}" = "sdk-cli" ] && exit 0   # `claude -p`: a runner/tool run, not a chat task
RX_AGENT='"agent_id"[[:space:]]*:[[:space:]]*"[^"]'
[[ ${INPUT} =~ ${RX_AGENT} ]] && exit 0
RX_SID='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9][A-Za-z0-9._-]*)"'
[[ ${INPUT} =~ ${RX_SID} ]] && SID="${BASH_REMATCH[1]}" || exit 0
RX_EV='"hook_event_name"[[:space:]]*:[[:space:]]*"([A-Za-z]+)"'
[[ ${INPUT} =~ ${RX_EV} ]] && EVENT="${BASH_REMATCH[1]}" || EVENT=""
RX_CWD='"cwd"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
[[ ${INPUT} =~ ${RX_CWD} ]] && CWD="${BASH_REMATCH[1]}" || CWD="${CLAUDE_PROJECT_DIR:-.}"
[ -d "${CWD}" ] || exit 0

TOP="$(git -C "${CWD}" rev-parse --show-toplevel 2>/dev/null)" || exit 0
COMMON="$(git -C "${CWD}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exit 0
MAIN="$(dirname "${COMMON}")"
# A board lane works an issue-N-* branch/worktree: its card exists already.
BRANCH="$(git -C "${CWD}" symbolic-ref --short -q HEAD 2>/dev/null || true)"
case "${BRANCH}" in issue-[0-9]*|*/issue-[0-9]*) exit 0 ;; esac
case "${TOP}/" in */.claude/worktrees/issue-[0-9]*) exit 0 ;; esac
# Only a repo with a board and a card script has anything to file into.
ls "${MAIN}"/.claude/super-board/configs/*.json >/dev/null 2>&1 || exit 0
[ -f "${TOP}/.claude/bin/super-board-card.sh" ] || [ -f "${MAIN}/.claude/bin/super-board-card.sh" ] || exit 0

SD="${MAIN}/.claude/audit-gate/session_card"
mkdir -p "${SD}" 2>/dev/null || exit 0
[ -e "${MAIN}/.claude/audit-gate/.gitignore" ] || printf '*\n' > "${MAIN}/.claude/audit-gate/.gitignore" 2>/dev/null || true

if [ "${EVENT}" = "UserPromptSubmit" ]; then
  if [ ! -e "${SD}/${SID}.prompt" ] && [ ! -d "${SD}/${SID}.d" ]; then
    python3 -I -c 'import json,sys
d = json.loads(sys.stdin.read() or "{}")
p = d.get("prompt") if isinstance(d, dict) else ""
open(sys.argv[1], "w", encoding="utf-8").write(p if isinstance(p, str) else "")' "${SD}/${SID}.prompt" <<<"${INPUT}" 2>/dev/null || true
  fi
  exit 0
fi

RX_FILE='"file_path"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
[[ ${INPUT} =~ ${RX_FILE} ]] && FILE="${BASH_REMATCH[1]}" || exit 0
case "${FILE}" in /*) ;; *) FILE="${CWD}/${FILE}" ;; esac
case "${FILE}" in "${TOP}"/*) ;; *) exit 0 ;; esac
REL="${FILE#"${TOP}"/}"
case "${REL}" in .claude/audit-gate/*|.agents/local/*) exit 0 ;; esac

if ! mkdir "${SD}/${SID}.d" 2>/dev/null; then
  # Already claimed. Once the card number is known, tell the session (a hint: it can write `Closes #N` in its PR).
  if [ -s "${SD}/${SID}.card" ] && mkdir "${SD}/${SID}.told" 2>/dev/null; then
    N="$(cat "${SD}/${SID}.card")"
    case "${N}" in ''|*[!0-9]*) ;; *)
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Board card #%s tracks this session (DevKit session_card). Put `Closes #%s` in the PR body."}}\n' "${N}" "${N}" ;;
    esac
  fi
  exit 0
fi

export SC_SID="${SID}" SC_TOP="${TOP}" SC_MAIN="${MAIN}" SC_SD="${SD}" SC_REL="${REL}"
RX_TR='"transcript_path"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
[[ ${INPUT} =~ ${RX_TR} ]] && export SC_TRANSCRIPT="${BASH_REMATCH[1]}" || export SC_TRANSCRIPT=""
if [ "${SESSION_CARD_WAIT:-0}" = "1" ]; then
  bash "$0" --worker </dev/null >/dev/null 2>&1 || true
else
  nohup bash "$0" --worker </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi
exit 0
