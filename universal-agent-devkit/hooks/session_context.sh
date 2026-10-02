#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# session_context.sh — SessionStart hook: what the model must know before the first
# edit of a session, loaded by the harness instead of left to "read AGENTS.md".
#
# Prints (added to the model's context), in a few dozen lines at most:
#   • the active profile (.agents/active-profile.json)
#   • the MAP of the project's failure memory (.agents/instincts.md): one line per
#     trap with its line number — not the whole file, so a large memory never floods
#     the context. Over 20 KB the index (.agents/instincts-index.md, from
#     scripts/index_memory.py) is regenerated when stale and pointed to instead.
#   • the regression checklist state (FAIL / UNCOVERED / OPEN / NEEDS_TEST counts, and
#     REPORTED bug prompts apart — not confirmed, not counted as bugs), the git pre-commit
#     gate, and the regression matrix state the Stop gate will really see — asked
#     from regression_gate.sh itself (REGRESSION_GATE_PROBE=1: its adoption rule and
#     post-fix-gate's load_active_matrix trust rule), so "a matrix file exists" is
#     never reported as "tests will run" when the gate does not trust it
#   • the gates that will actually run, so the model does not have to guess
#
# Never blocks: always exit 0. Escape hatch: SESSION_CONTEXT=0.
# Protocol: stdin JSON; stdout is added to the context.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

[ "${SESSION_CONTEXT:-1}" = "0" ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0
INPUT="$(cat)"  # only the session id is used (worktree heal below)

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SELF="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null)"
INDEXER=""
for cand in "$(dirname "$(dirname "${SELF}")")/scripts/governance/index_memory.py" \
            "$(dirname "$(dirname "${SELF}")")/scripts/index_memory.py" \
            "${DEVKIT_ROOT:-}/scripts/governance/index_memory.py" \
            "${DEVKIT_ROOT:-}/scripts/index_memory.py" \
            "${HOME}/.universal-agent-devkit/scripts/governance/index_memory.py" \
            "${HOME}/.universal-agent-devkit/scripts/index_memory.py"; do
  [ -f "${cand}" ] && { INDEXER="${cand}"; break; }
done
HOOK_FILE="$(git -C "${REPO_ROOT}" rev-parse --path-format=absolute --git-path hooks/pre-commit 2>/dev/null || true)"
GATE_HOOK="$(dirname "${SELF}")/regression_gate.sh"
# The files AGENTS.md loads at startup (.agents/context/) follow edits to the project's
# rules and DevKit updates — refreshed in the background for the next session.
CTX_SYNC="$(dirname "$(dirname "${SELF}")")/scripts/governance/context_sync.py"
[ -f "${CTX_SYNC}" ] || CTX_SYNC="$(dirname "$(dirname "${SELF}")")/scripts/context_sync.py"
[ -f "${CTX_SYNC}" ] && [ -d "${REPO_ROOT}/.agents" ] && (python3 "${CTX_SYNC}" "${REPO_ROOT}" --quiet >/dev/null 2>&1 &)
# A worktree the host made itself (Grok, OfficeReader 2026-09-28) lacks the git-ignored
# .agents/devkit link and local config: set it up like `agent-kit worktree add` (no-op elsewhere).
WT_SCRIPT="$(dirname "$(dirname "${SELF}")")/scripts/git/worktree.py"
[ -f "${WT_SCRIPT}" ] || WT_SCRIPT="$(dirname "$(dirname "${SELF}")")/scripts/worktree.py"
if [ -f "${WT_SCRIPT}" ]; then
  WT_SID="$(printf '%s' "${INPUT:-}" | python3 -c 'import json,sys
try: print(str(json.load(sys.stdin).get("session_id") or ""))
except Exception: pass' 2>/dev/null)"
  HEALED="$(cd "${REPO_ROOT}" 2>/dev/null && python3 "${WT_SCRIPT}" heal "--devkit=$(dirname "$(dirname "${SELF}")")" "--session=${WT_SID}" 2>/dev/null)"
  [ -n "${HEALED}" ] && echo "[DevKit] ${HEALED}"
fi
# The regression baseline (T0003): verified_head recorded before the first turn can commit, so a
# commit of turn 1 is never taken as already verified.
HARNESS_PY="$(dirname "${SELF}")/devkit_harness.py"
[ -f "${HARNESS_PY}" ] && git -C "${REPO_ROOT}" rev-parse -q --verify HEAD >/dev/null 2>&1 \
  && python3 "${HARNESS_PY}" baseline "${REPO_ROOT}" >/dev/null 2>&1

REPO_ROOT="${REPO_ROOT}" INDEXER="${INDEXER}" HOOK_FILE="${HOOK_FILE}" GATE_HOOK="${GATE_HOOK}" WT_SCRIPT="${WT_SCRIPT}" python3 - <<'PY' 2>/dev/null
import json, os, re, signal, subprocess, sys

root = os.environ["REPO_ROOT"]
out = []

prof = "none"
try:
    pf = os.path.join(root, ".agents", "active-profile.json")
    if not os.path.isfile(pf):
        pf = os.path.join(root, ".active-profile.json")       # before DevKit 1.3
    with open(pf, encoding="utf-8") as f:
        prof = json.load(f).get("profile") or "none"
except (OSError, ValueError, AttributeError):
    pass
out.append(f"[DevKit] Phiên mới — profile: {prof}. DevKit là core; bộ riêng của dự án ở .agents/local/.")

# Failure memory map
inst = os.path.join(root, ".agents", "instincts.md")
if os.path.isfile(inst):
    text = open(inst, encoding="utf-8", errors="replace").read()
    visible = re.sub(r"<!--.*?-->", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.DOTALL)
    heads = [(i + 1, l[4:].strip()) for i, l in enumerate(visible.splitlines())
             if l.startswith("### [INSTINCT-") and "XXX" not in l.split("]")[0]]
    size_kb = os.path.getsize(inst) / 1024
    if size_kb > 20:
        index = os.path.join(root, ".agents", "instincts-index.md")
        indexer = os.environ.get("INDEXER")
        if indexer and (not os.path.exists(index) or os.path.getmtime(index) < os.path.getmtime(inst)):
            subprocess.run([sys.executable, indexer, inst], capture_output=True, timeout=20)
        out.append(f"Bài học của dự án: .agents/instincts.md ({len(heads)} mục, {size_kb:.0f} KB — KHÔNG đọc cả file). "
                   f"Tra mục lục .agents/instincts-index.md rồi đọc đúng mục bằng `sed -n 'a,bp'`.")
    elif heads:
        out.append(f"Bài học của dự án (.agents/instincts.md, {len(heads)} mục) — trước khi sửa code chạm vào "
                   f"chủ đề nào, đọc đúng mục đó: `sed -n '<dòng>,+12p' .agents/instincts.md`")
        for line, title in heads[:40]:
            out.append(f"  L{line} {title}")
        if len(heads) > 40:
            out.append(f"  … và {len(heads) - 40} mục nữa")

bounds = os.path.join(root, ".agents", "context", "hardware-boundaries.json")
if os.path.isfile(bounds):
    try:
        rows = json.load(open(bounds, encoding="utf-8")).get("boundaries") or []
    except (OSError, ValueError, AttributeError):
        rows = []
    titles = [f"{r.get('id')}: {r.get('title')}" for r in rows if isinstance(r, dict) and r.get("id")]
    if titles:
        out.append("Ngõ cụt phần cứng đã đo — đọc .agents/context/hardware-boundaries.json trước khi sửa triệu chứng trùng:")
        for title in titles[:8]:
            out.append(f"  {title}")

# Regression state
matrix = os.path.join(root, ".agents", "regression_matrix.active.json")
status = os.path.join(root, ".agents", "regression_status.json")
parts = []
probe = {}
gate_hook = os.environ.get("GATE_HOOK") or ""
if os.path.isfile(gate_hook):
    try:  # read-only: the Stop gate answers what it would do, runs no test
        r = subprocess.run(["bash", gate_hook], input="{}", capture_output=True, text=True, timeout=20,
                           env={**os.environ, "REGRESSION_GATE_PROBE": "1", "CLAUDE_PROJECT_DIR": root})
        probe = json.loads((r.stdout.strip().splitlines() or ["{}"])[-1])
    except Exception:
        probe = {}
state, m = probe.get("state"), probe.get("matrix") or ""
off = " — khi dừng KHÔNG chạy test hồi quy"
if state == "trusted":
    parts.append(f"ma trận hồi quy: {m} (được gate tin — test hồi quy chạy khi dừng)")
elif state == "untrusted":
    parts.append(f"ma trận hồi quy: {m} CHƯA được gate tin ({probe.get('problem')}){off} theo nó; cần người review rồi "
                 f"commit {m} (gate chỉ tin ma trận đã commit, hoặc giống từng byte bản `agent-kit matrix`)")
elif state == "sample":
    parts.append(f"ma trận hồi quy: {m} là ma trận MẪU của DevKit, chưa áp dụng{off} (`agent-kit matrix --write`, "
                 "hoặc sửa thành test thật của dự án / thêm \"adopted\": true rồi commit)")
elif state == "outside":
    parts.append(f"ma trận hồi quy: {m} nằm ngoài repo (link vào DevKit){off}")
elif state == "none":
    parts.append("ma trận hồi quy: chưa có" + off)
elif state == "nogate":
    parts.append("ma trận hồi quy: không tìm thấy post-fix-gate.py" + off)
elif state == "disabled":
    parts.append("ma trận hồi quy: REGRESSION_GATE=0" + off)
else:  # gate hook unreachable / probe failed: what is on disk, trust unknown
    parts.append("ma trận hồi quy: " + (".agents/regression_matrix.active.json (chưa rõ gate có tin không)"
                                        if os.path.isfile(matrix) else "chưa có"))
try:
    indexer = os.environ.get("INDEXER") or ""
    counts = {}
    if indexer and os.path.isfile(status):
        _top = os.path.dirname(os.path.dirname(indexer))    # DevKit root when index_memory.py sits in scripts/
        if not os.path.isfile(os.path.join(_top, "bin", "regression_checklist.py")):
            _top = os.path.dirname(_top)                     # …or in scripts/<group>/ since the regrouping
        sys.path.insert(0, os.path.join(_top, "bin"))
        sys.dont_write_bytecode = True
        import regression_checklist as rc  # the same status rules the checklist view uses
        with rc.locked(root):   # code changed since a PASS → STALE, written back only when it changed
            data = rc.load(root)
            before = json.dumps(data, sort_keys=True)
            rc.mark_stale(data, root)
            rc.auto_close_reported(data)
            if json.dumps(data, sort_keys=True) != before:
                rc.save(root, data, stale=False)
        counts = rc.summary(data)
        out.extend(filter(None, [rc.rollback_warning(root)]))  # checklist rolled back outside the DevKit
        try:
            _gov = os.path.dirname(indexer)    # scripts/governance (scripts/ before the regrouping)
            rerun = next((p for p in (os.path.join(os.path.dirname(_gov), "testing", "stale_rerun.py"),
                                      os.path.join(_gov, "stale_rerun.py")) if os.path.isfile(p)),
                         os.path.join(_gov, "stale_rerun.py"))
            sys.path.insert(0, os.path.dirname(rerun))
            from stale_rerun import is_light     # the same light/heavy rule the re-run applies
            light = [t for t, it in data["items"].items() if it.get("kind") == "test"
                     and rc.effective_status(data, it) == "STALE" and is_light(it.get("command"))]
            if light and state == "trusted" and os.environ.get("STALE_RERUN", "1") != "0":
                # detaches at once; heavy suites wait for the nightly job
                subprocess.Popen([sys.executable, rerun, root], stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
                parts.append(f"{len(light)} suite nhẹ CẦN CHẠY LẠI (code đổi sau lần PASS): đang chạy lại nền "
                             "(Gradle/Unity: `postfix-gate --run-tests --full`, hoặc `agent-kit nightly` nếu đã cài) — kết quả vào checklist")
        except Exception:
            pass  # the background re-run is a convenience; the counts below must still print
    bad = {k: v for k, v in counts.items() if k in ("FAIL", "TIMEOUT", "FLAKY", "STALE", "UNCOVERED", "NEEDS_TEST",
                                                    "NOT_IN_MATRIX", "OPEN", "ORPHAN_TEST")}
    if bad:
        parts.append("checklist còn " + ", ".join(f"{v} {k}" for k, v in sorted(bad.items()))
                     + " (.agents/CHECKLIST.md)")
    if counts.get("REPORTED"):  # bug prompts nobody confirmed yet — not counted as bugs above
        parts.append(f"{counts['REPORTED']} REPORTED (bug báo qua prompt, chưa xác nhận: "
                     "`agent-kit bugs add \"<tiêu đề>\" --id <ID>` / `bugs link <ID> <test>` / `bugs drop <ID>`)")
except Exception:
    pass  # a corrupt checklist must not break session start
hook = os.environ.get("HOOK_FILE") or ""
try:
    text = open(hook, encoding="utf-8", errors="replace").read()
    # the DevKit's hook, or the project's own one chaining the DevKit gate (githooks.sh status)
    pre = "universal-agent-devkit:githook" in text or any(
        ("scripts/git-pre-commit.sh" in l or "scripts/git/git-pre-commit.sh" in l) and not l.lstrip().startswith("#") for l in text.splitlines())
except OSError:
    pre = False
parts.append("git pre-commit: " + ("bật" if pre else "chưa cài (agent-kit githooks install)"))
out.append("Trạng thái: " + "; ".join(parts) + ".")

# One developer, one branch: a branch behind/ahead of its upstream, leftover worktrees and extra
# local branches split the code (GeelyEx2, 2026-09-26: local main 2 commits behind origin).
# Fetch first (bounded; SESSION_FETCH=0 skips it) so "behind" covers pushes from elsewhere.
def git_out(*args, timeout=5):
    try:
        r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None

try:
    drift = []
    main_like = re.compile(r"^(main|master|trunk|develop|release/.+|hotfix/.+)$")
    cur = git_out("symbolic-ref", "-q", "--short", "HEAD")
    up = git_out("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}") if cur else None
    if up and os.environ.get("SESSION_FETCH", "1") != "0":
        # Never prompt (BatchMode), and on timeout kill the whole group so no ssh outlives it.
        ssh = os.environ.get("GIT_SSH_COMMAND") or git_out("config", "core.sshCommand") or "ssh"
        env = {**os.environ, "GIT_TERMINAL_PROMPT": "0",
               "GIT_SSH_COMMAND": ssh + " -o BatchMode=yes -o ConnectTimeout=4"}
        try:
            p = subprocess.Popen(["git", "-C", root, "fetch", "--quiet", "--no-tags", up.split("/", 1)[0]],
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 env=env, start_new_session=True)
            try:
                p.wait(timeout=6)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid, signal.SIGKILL)
                p.wait()
        except OSError:
            pass  # git cannot be spawned: the report below uses the refs from the last fetch
    counts_lr = git_out("rev-list", "--left-right", "--count", f"HEAD...{up}") if up else None
    ahead, behind = (int(x) for x in counts_lr.split()) if counts_lr else (0, 0)
    if ahead and behind:
        drift.append(f"{cur} trước {ahead}, sau {behind} commit so với {up} — `git pull --no-rebase` "
                     "(lệnh riêng, kiểm exit code) rồi mới `git push`")
    elif behind:
        drift.append(f"{cur} sau {up} {behind} commit — `git pull --ff-only` trước khi sửa/push")
    elif ahead:
        drift.append(f"{cur} có {ahead} commit chưa push lên {up}")
    if git_out("rev-parse", "--git-dir") is not None and not cur:
        drift.append("HEAD tách rời (detached) — về nhánh chính trước khi sửa")
    elif cur and not main_like.match(cur):
        drift.append(f"đang ở nhánh phụ {cur} — xong thì merge về nhánh chính và xoá nhánh")
    here = os.path.realpath(git_out("rev-parse", "--show-toplevel") or root)
    porcelain = (git_out("worktree", "list", "--porcelain") or "").splitlines()
    wts = [l[len("worktree "):] for l in porcelain if l.startswith("worktree ")]
    wt_branches = {l[len("branch refs/heads/"):] for l in porcelain if l.startswith("branch refs/heads/")}
    extra_wt = [w for w in wts[1:] if os.path.realpath(w) != here]
    if extra_wt:
        # Name each worktree whose work is NOT in trunk (scripts/worktree.py inventory): a bare count let
        # finished worktrees sit unmerged while tasks were redone (OfficeReader / GeelyEx2, 2026-10-01).
        class _WtTimeout(BaseException):   # not OSError/SystemExit: worktree.py catches those around git calls
            pass

        def _wt_timeout(*_):
            raise _WtTimeout()
        try:
            sys.path.insert(0, os.path.dirname(os.environ.get("WT_SCRIPT") or ""))
            import worktree as _wt
            signal.signal(signal.SIGALRM, _wt_timeout)
            signal.alarm(4)   # git status per worktree: never let it eat the whole session-start budget
            todo = [r for r in _wt.inventory(root) if r["unintegrated"] and os.path.realpath(r["path"]) != here]
        except (Exception, SystemExit, _WtTimeout):
            todo = None
        finally:
            signal.alarm(0)
        if todo is None:
            drift.append(f"{len(extra_wt)} worktree còn lại: {', '.join(extra_wt[:3])} — TRƯỚC khi gộp/xoá bất kỳ cái nào chạy "
                         "`agent-kit worktree status` (cái nào còn việc CHƯA gộp thì đem về trước), rồi `agent-kit worktree remove <path>`")
        elif todo:
            items = "; ".join(f"{r['path']} [{r['branch'] or 'detached'}] ahead={'?' if r['ahead'] is None else r['ahead']} "
                              f"dirty={'?' if r['dirty'] is None else r['dirty']}" for r in todo[:4])
            drift.append(f"{len(todo)} worktree còn việc CHƯA về trunk: {items} — đem về (`agent-kit worktree diff <path> | git apply --3way` "
                         "hoặc `git merge --no-edit <branch>`), commit, rồi `agent-kit worktree remove <path>`; worktree phiên khác đang làm thì để yên")
        else:
            drift.append(f"{len(extra_wt)} worktree đã gộp hết nhưng còn để lại: {', '.join(extra_wt[:3])} — xoá: `agent-kit worktree remove <path>`")
    heads = (git_out("for-each-ref", "--format=%(refname:short)", "refs/heads/") or "").splitlines()
    extra = [b for b in heads if b and b != cur and b not in wt_branches and not main_like.match(b)]
    merged = set((git_out("branch", "--format=%(refname:short)", "--merged", "HEAD") or "").splitlines())
    done = [b for b in extra if b in merged]
    unmerged = [b for b in extra if b not in merged]
    if done:
        drift.append(f"{len(done)} nhánh thừa đã merge — `git branch -d {' '.join(done[:5])}`")
    if unmerged:
        drift.append(f"{len(unmerged)} nhánh chưa merge vào {cur or 'HEAD'}: {', '.join(unmerged[:5])} — "
                     "merge về hoặc hỏi User")
    if drift:
        out.append("Nhánh (luật 1 dev, 1 nhánh): " + "; ".join(drift) + ".")
except Exception:
    pass  # branch hygiene is advice; it must never break session start

stop_tests = ("test hồi quy theo ma trận" if state == "trusted"
              else "test hồi quy CHỈ khi ma trận được áp dụng và gate tin (hiện chưa — xem Trạng thái)")
out.append("Gate chạy tự động: Bash chặn git nguy hiểm/--no-verify; Edit cần Read trước; khi dừng: " + stop_tests +
           ", 'test pass' phải có kết quả runner và test mới phải từng ĐỎ, 'đã fix' phải có cặp test "
           "ĐỎ→XANH trong phiên, sửa bug xong được nhắc ghi bài học (agent-kit learn).")
print("\n".join(out))
PY
exit 0
