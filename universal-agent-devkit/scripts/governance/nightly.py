#!/usr/bin/env python3
"""
nightly.py — the local nightly regression job (a macOS LaunchAgent; never a cloud agent:
the cloud has no Unity Editor, Android SDK, device or local secrets).

  nightly.py run [<project>...]       every registered project, now; or exactly the named ones (no list change, no weekly report;
                                      a named project that a session holds - idle at its prompt too - prints `skip: <reason>`)
  nightly.py add|remove <project>     the project list (~/.config/agent-kit/nightly-projects)
  nightly.py install [--hour H] [--minute M]   daily LaunchAgent (default 02:17)
  nightly.py uninstall | status

A run, per project (one at a time, one suite at a time — no load spike, no backend spam):
  - only a matrix the Stop gate trusts (else the project is skipped and said so)
  - every suite of the matrix for real, heavy ones included; a FAIL is re-run once (green
    then → FLAKY, still not a PASS); results + evidence logs in the checklist
  - the pending RED-proofs, heavy suites included (scripts/red_proof.py --pending --heavy)
  - STALE / auto-close refreshed
Then ONE notification if any row TURNED red (FAIL / TIMEOUT / FLAKY / VACUOUS) — silence
when everything stays green, no repeat while a row stays red — and, every 7 days, the
one-line weekly report (reminders/blocks that needed a human, REPORTED rows dropped as
false positives, FLAKY, VACUOUS), also kept in .agents/evidence/weekly.log.
Env: NIGHTLY_NOTIFY=0 (no notification), NIGHTLY_NOTIFY_CMD (test hook), NIGHTLY_LAUNCHCTL,
NIGHTLY_SUITE_TIMEOUT_S (default 3600). Standard library only.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

DEVKIT = Path(__file__).resolve().parent.parent
if not (DEVKIT / "profiles").is_dir() and (DEVKIT.parent / "profiles").is_dir():
    DEVKIT = DEVKIT.parent
sys.path.insert(0, str(DEVKIT / "bin"))
for _sub in ("audits", "context", "git", "governance", "linters", "testing"):
    _sub_path = str(DEVKIT / "scripts" / _sub)
    if _sub_path not in sys.path:
        sys.path.insert(0, _sub_path)
sys.dont_write_bytecode = True
import regression_checklist as rc  # noqa: E402
import session_lock  # noqa: E402
import stale_rerun  # noqa: E402

LABEL = "com.universal-agent-devkit.nightly"
RED = ("FAIL", "TIMEOUT", "FLAKY", "VACUOUS")


def config_dir() -> Path:
    return Path(os.environ.get("HOME", "~")).expanduser() / ".config" / "agent-kit"


def projects_file() -> Path:
    return config_dir() / "nightly-projects"


def plist_path() -> Path:
    return Path(os.environ.get("HOME", "~")).expanduser() / "Library" / "LaunchAgents" / f"{LABEL}.plist"


def load_projects() -> list:
    try:
        return [l.strip() for l in projects_file().read_text(encoding="utf-8").splitlines() if l.strip()]
    except OSError:
        return []


def save_projects(items: list) -> None:
    projects_file().parent.mkdir(parents=True, exist_ok=True)
    projects_file().write_text("".join(f"{p}\n" for p in items), encoding="utf-8")


def notify(text: str) -> None:
    if os.environ.get("NIGHTLY_NOTIFY", "1") == "0":
        return
    cmd = os.environ.get("NIGHTLY_NOTIFY_CMD")
    try:
        if cmd:
            subprocess.run([cmd, text], timeout=30)
        else:
            safe = text.replace("\\", "\\\\").replace('"', '\\"')
            subprocess.run(["osascript", "-e", f'display notification "{safe}" with title "DevKit — hồi quy đêm"'],
                           timeout=30, capture_output=True)
    except (OSError, subprocess.SubprocessError):
        pass


def statuses(project: Path) -> dict:
    try:
        data = rc.load(project)
    except (OSError, ValueError):
        return {}
    return {i: rc.effective_status(data, it) for i, it in data["items"].items()}


def human_touches(project: Path, since: float) -> int:
    """Stops held for a human decision in the last 7 days (the Stop gates' own log)."""
    n = 0
    for log in ("test_evidence_gate.log", "regression_gate.log", "review_gate.log"):
        try:
            lines = (project / ".claude" / "audit-gate" / log).read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            m = re.match(r"\[(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)\]", line)
            if not m or ("BLOCK" not in line and "reminder" not in line):
                continue
            try:
                if time.mktime(time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")) >= since:
                    n += 1
            except ValueError:
                pass
    return n


def checkout_busy(project: Path) -> str | None:
    """Why a NAMED run leaves `project` alone: a session holds its checkout, idle at its prompt too. `session_lock.py --status` calls an
    idle holder free, but that session takes the lock back at the user's next prompt and edits the tree this run is testing (and its Stop
    gate then queues behind the suite's test_run.lock). Judged as worktree_merge_gate judges it: idle_frees=False, live_pid_holds=True.
    ponytail: a session that opens while a suite runs is seen only at the next check (the next suite, or red_proof); upgrade to a lock watcher
    that stops the running suite when a session is seen editing during a night run."""
    gdir, top = session_lock.git_dir(str(project))
    if not gdir:   # the path was checked to hold a .git: one git cannot read (a pointer to a gitdir that is gone) is no go-ahead
        return "không đọc được git dir"
    lock, now = session_lock.read_checkout_lock(gdir), time.time()
    if session_lock.is_free_for(lock, "", now, idle_frees=False, live_pid_holds=True):
        return None
    return f"{session_lock.describe(lock, now)} đang giữ checkout"


def run_project(project: Path, named: bool = False) -> tuple:
    """(turned red: [(id, status)], message) for one project. `named`: the project was named on the command line, so a session that
    holds its checkout is not run over (the unnamed run is the night's own LaunchAgent: nobody works then)."""
    busy = checkout_busy(project) if named else None
    if busy:
        return [], f"{project.name}: skip: {busy}"
    if not (project / rc.STATUS_FILE).is_file() and not (project / ".agents" / "regression_matrix.active.json").is_file():
        return [], f"{project.name}: không có checklist/ma trận — bỏ qua"
    if rc.skip_bookkeeping(project):   # a LINKED worktree leaves the tracked checklist alone: a night's runs could not be recorded
        return [], f"{project.name}: worktree liên kết — không ghi checklist ở đó, bỏ qua (DEVKIT_WORKTREE_CHECKLIST=1 để ghi)"
    if not stale_rerun.matrix_trusted(project):
        return [], f"{project.name}: ma trận không được gate tin (chưa commit / khác bản agent-kit matrix) — bỏ qua"
    with rc.locked(project):
        data = rc.load(project)
        mf = project / ".agents" / "regression_matrix.active.json"
        rc.sync_from_matrix(data, json.loads(mf.read_text(encoding="utf-8")))
        rc.mark_stale(data, project)
        rc.save(project, data)
    before = statuses(project)
    try:
        timeout = float(os.environ.get("NIGHTLY_SUITE_TIMEOUT_S", "3600"))
    except ValueError:
        timeout = 3600.0
    lines, stopped = [], None
    for tid, it in sorted(data["items"].items()):
        if it.get("kind") != "test" or not it.get("command"):
            continue
        stopped = checkout_busy(project) if named else None   # a session may have opened since the last suite
        if stopped:
            lines.append(f"skip: {stopped} - dừng trước {tid}")
            break
        pats = list(it.get("watch_files", [])) + list(it.get("covers", []))
        lines.append(stale_rerun.run_one(project, tid, it["command"], pats, timeout, mode="nightly", retry=True))
    if named and not stopped:   # a session may have opened during the LAST suite, and red_proof adds and removes worktrees in this repo's .git
        stopped = checkout_busy(project)
        if stopped:
            lines.append(f"skip: {stopped} - red_proof không chạy")
    if not stopped:
        _red_proof_script = DEVKIT / "scripts" / "testing" / "red_proof.py"
        if not _red_proof_script.is_file():
            _red_proof_script = DEVKIT / "scripts" / "red_proof.py"
        subprocess.run([sys.executable, str(_red_proof_script), str(project), "--pending", "--heavy", "--wait"],
                       capture_output=True, text=True)
        with rc.locked(project):
            data = rc.load(project)
            rc.auto_close_reported(data)
            rc.save(project, data)
    after = statuses(project)
    turned = [(i, s) for i, s in sorted(after.items()) if s in RED and before.get(i) not in RED]
    return turned, f"{project.name}: " + "; ".join(lines)


def weekly(projects: list) -> str | None:
    """The one-line weekly report, once per 7 days."""
    state_f = config_dir() / "nightly-state.json"
    try:
        state = json.loads(state_f.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        state = {}
    now = time.time()
    if now - float(state.get("last_weekly", 0)) < 7 * 86400:
        return None
    parts = []
    for p in projects:
        project = Path(p)
        try:
            data = rc.load(project)
        except (OSError, ValueError):
            continue
        st = rc.summary(data)
        stats = data.get("stats") or {}
        line = (f"{project.name}: cần người {human_touches(project, now - 7 * 86400)} lần · REPORTED bị drop "
                f"{stats.get('reported_dropped', 0)}/{stats.get('reported_total', 0)} · FLAKY {st.get('FLAKY', 0)} · "
                f"TEST VÔ HIỆU {st.get('VACUOUS', 0)} · ✅ {st.get('PASS', 0)}")
        parts.append(line)
        try:
            ev = project / rc.EVIDENCE_DIR
            ev.mkdir(parents=True, exist_ok=True)
            with open(ev / "weekly.log", "a", encoding="utf-8") as fh:
                fh.write(f"{rc._now()} {line}\n")
        except OSError:
            pass
    state["last_weekly"] = now
    state_f.parent.mkdir(parents=True, exist_ok=True)
    state_f.write_text(json.dumps(state), encoding="utf-8")
    return ("Báo cáo tuần — " + " | ".join(parts)) if parts else None


def path_problem(raw: str) -> str | None:
    """Why a path named on the command line is no project to run, else None. Path("") is the cwd (the audit's own workbench), so an empty
    path is refused before it is resolved; a directory without .agents/ or that is not a git root (the 12/10 OfficeReader outer folder)
    would only say "bỏ qua" with exit 0, which hides the mistake."""
    if not raw.strip():
        return "empty path"
    try:
        p = Path(raw).expanduser()
    except RuntimeError:   # ~user of a user that does not exist
        return "cannot expand ~ (no such user or no home directory)"
    if not p.is_dir():
        return "not a directory"
    if not (p / ".agents").is_dir():
        return "no .agents/ - not a DevKit project"
    if not os.path.lexists(p / ".git"):
        return "not a git root - is it the folder around the repository?"
    return None


def unique_projects(paths: list) -> list:
    """The named paths, resolved, one entry per directory. Identity is (device, inode): a case-insensitive filesystem (APFS) spells one repo
    several ways that resolve() keeps apart, and `run .../r1 .../R1` ran it twice."""
    seen, out = set(), []
    for p in paths:
        q = Path(p).expanduser().resolve()
        try:
            st = os.stat(q)
            key = (st.st_dev, st.st_ino)
        except OSError:
            key = str(q)
        if key not in seen:
            seen.add(key)
            out.append(str(q))
    return out


def cmd_run(paths: list | None = None) -> int:
    """Every registered project, or exactly `paths` (the daily /devkit-audit runs one repo at a time, only those whose
    checkout is free). A named run leaves the project list alone and sends no weekly report: its 7-day slot would go to
    whichever repo came first, with a one-repo line."""
    projects = unique_projects(paths) if paths else load_projects()   # one repo, one run
    reds = []
    for p in projects:
        try:
            turned, msg = run_project(Path(p), named=bool(paths))
        except OSError as e:   # a project gone mid-run (W1 R5a: save() refuses to re-create it): the others still run
            turned, msg = [], f"{Path(p).name}: {e}"
        print(msg)
        reds += [f"{Path(p).name} {i} {s}" for i, s in turned]
    if reds:
        notify(f"{len(reds)} mục chuyển sang đỏ: " + ", ".join(reds[:6]) + (" …" if len(reds) > 6 else ""))
    report = None if paths else weekly(projects)
    if report:
        notify(report)
        print(report)
    return 0


PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>{label}</string>
  <key>ProgramArguments</key>
  <array><string>{python}</string><string>{script}</string><string>run</string></array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>{hour}</integer><key>Minute</key><integer>{minute}</integer></dict>
  <key>StandardOutPath</key><string>{log}</string>
  <key>StandardErrorPath</key><string>{log}</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict>
</plist>
"""


def launchctl(*args) -> None:
    exe = os.environ.get("NIGHTLY_LAUNCHCTL", "launchctl")
    subprocess.run([exe, *args], capture_output=True)


def cmd_install(hour: int, minute: int) -> int:
    pl = plist_path()
    pl.parent.mkdir(parents=True, exist_ok=True)
    config_dir().mkdir(parents=True, exist_ok=True)
    pl.write_text(PLIST.format(label=LABEL, python=sys.executable, script=Path(__file__).resolve(), hour=hour,
                               minute=minute, log=config_dir() / "nightly.log"), encoding="utf-8")
    uid = str(os.getuid())
    launchctl("bootout", f"gui/{uid}", str(pl))
    launchctl("bootstrap", f"gui/{uid}", str(pl))
    print(f"✔ job đêm {hour:02d}:{minute:02d} hằng ngày: {pl}\n  gỡ: agent-kit nightly uninstall")
    return 0


def cmd_status() -> int:
    pl = plist_path()
    if pl.is_file():
        text = pl.read_text(encoding="utf-8")
        nums = re.findall(r"<integer>(\d+)</integer>", text)
        print(f"job đêm: bật, {int(nums[0]):02d}:{int(nums[1]):02d} hằng ngày ({pl})" if len(nums) >= 2 else f"job đêm: {pl}")
    else:
        print("job đêm: chưa cài (agent-kit nightly install)")
    for p in load_projects():
        print(f"  - {p}")
    return 0


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    cmd = args[0] if args else "status"
    if cmd == "run":
        bad = []
        for p in args[1:]:
            why = path_problem(p)
            if why:
                bad.append(f"{p!r} ({why})")
        if bad:   # all or nothing: one bad path means nothing runs
            print(f"nightly.py run: not a DevKit project to run: {', '.join(bad)}", file=sys.stderr)
            return 2
        return cmd_run(args[1:])
    if cmd in ("add", "remove"):
        if len(args) < 2:
            print(f"nightly.py {cmd} <project>", file=sys.stderr)
            return 2
        p = str(Path(args[1]).expanduser().resolve())
        items = [x for x in load_projects() if x != p]
        if cmd == "add":
            items.append(p)
        save_projects(items)
        print(f"✔ {'thêm' if cmd == 'add' else 'bỏ'} {p}")
        return 0
    if cmd == "install":
        hour = int(args[args.index("--hour") + 1]) if "--hour" in args else 2
        minute = int(args[args.index("--minute") + 1]) if "--minute" in args else 17
        return cmd_install(hour, minute)
    if cmd == "uninstall":
        pl = plist_path()
        if pl.exists():
            launchctl("bootout", f"gui/{os.getuid()}", str(pl))
            pl.unlink()
        print("✔ đã gỡ job đêm")
        return 0
    if cmd == "status":
        return cmd_status()
    print("nightly.py run [<project>...] | add <project> | remove <project> | install [--hour H] [--minute M] | uninstall | status",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
