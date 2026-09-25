#!/usr/bin/env python3
"""
regression_checklist.py — Living regression checklist (features + bugs → tests → last result).

One place to see, across tasks, which features and fixed bugs are covered by which
regression test and whether that test last PASSED or FAILED, when, in which task
and on which commit.

  .agents/regression_status.json   source of truth (machine-written)
  .agents/CHECKLIST.md             human view (dashboard), regenerated from the JSON;
                                   .agents/regression_checklist.md is a link to it (old name)
  .agents/INBOX.md                 the user's to-do lines — read, never written (a template once)
  .agents/evidence/                full runner output of every real run (git-ignored)

Rules that keep it honest (same lesson as post-fix-gate: never a fabricated PASS):
  - A PASS/FAIL result is written ONLY by post-fix-gate after it actually ran the
    test command (--run-tests). There is no CLI to mark an item passed by hand.
  - A changed source file that no matrix rule covers becomes an UNCOVERED item —
    nobody invents a test for it; a human/agent must map it to a real test id.
  - A recorded bug starts as "needs test" until it is linked to a test id; from then
    on it shows that test's real last result.

CLI:
  regression_checklist.py show                     print the checklist
  regression_checklist.py link <ITEM> <TEST-ID>    link a bug / uncovered item to a matrix test
  regression_checklist.py render                   regenerate the Markdown view
  regression_checklist.py import <table> [--dry-run]
      past bugs from a tab- or |-separated table (agent-kit bugs import):
      bug_id | title | severity | fixed? | module | test_id_or_NONE | evidence
      A bug is never PASS on import: NEEDS_TEST (no test), NOT_IN_MATRIX (a test the gate
      never runs), NOT_RUN (linked to a matrix test, not run since), OPEN (not fixed);
      PASS/FAIL come from the next real gate run of its matrix test.
  regression_checklist.py add "<title>" [--severity S] [--module M] [--evidence E]
                              [--test REF]... [--fixed] [--id BUG-ID]    (agent-kit bugs add)
      one new bug: OPEN (not fixed), NEEDS_TEST (fixed, no test), NOT_RUN / NOT_IN_MATRIX
      (with a test); never PASS. Same normalized title + module → the existing row, no
      duplicate. --id confirms a REPORTED row (or names the new row).
  regression_checklist.py bug-link <BUG-ID> <TEST-REF>                  (agent-kit bugs link)
      a matrix id, test file or class, resolved like `import` does; the bug counts as fixed
  regression_checklist.py drop <BUG-ID>                                 (agent-kit bugs drop)
  regression_checklist.py restore [--list | --dismiss | <snapshot>]     (agent-kit checklist restore)
      every save is journaled (.agents/regression_journal/: time, writer, pid, content hash +
      the last snapshots; git-ignored). A file overwritten outside the DevKit with content lost
      (red_proof, unlink, link, row, result) is a rollback: every load warns until a restore
      MERGES the last good snapshot back — newer red_proof/result per row by ts, union of links
      minus recorded unlinks, rows added since kept. Never a blind copy.
  regression_checklist.py check                                         (agent-kit checklist check)

REPORTED rows come from the UserPromptSubmit hook (scripts/enrich_context.py): a prompt
classified as a bug fix, not yet confirmed. The classifier has false positives, so they
are shown apart and not counted as bugs until linked to a test or confirmed with --id.

100% standard library.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
import re
import sys
import tempfile
import time
import unicodedata
from pathlib import Path

STATUS_FILE = Path(".agents") / "regression_status.json"
VIEW_FILE = Path(".agents") / "CHECKLIST.md"
OLD_VIEW_FILE = Path(".agents") / "regression_checklist.md"   # a link to VIEW_FILE
HISTORY_LIMIT = 10
RESULT_STATES = {"PASS", "FAIL", "TIMEOUT"}

ICON = {
    "PASS": "✅ PASS",
    "FAIL": "❌ FAIL",
    "TIMEOUT": "❌ TIMEOUT",
    "NOT_RUN": "⏳ chưa chạy",
    "NEEDS_TEST": "⚠️ cần test",
    "UNCOVERED": "⚠️ chưa có test",
    "NOT_IN_MATRIX": "⚠️ có test, gate không chạy",
    "OPEN": "🐞 chưa sửa",
    "REPORTED": "🟡 báo qua prompt, chưa xác nhận",
    "FLAKY": "🔁 FLAKY (đỏ rồi xanh cùng code)",
    "STALE": "🟡 CẦN CHẠY LẠI (code đã đổi)",
    "UNPROVEN": "⏳ chưa chứng minh ĐỎ",
    "AUTO_CLOSED": "💤 tự đóng (REPORTED 14 ngày không ai đụng)",
    "VACUOUS": "🚫 TEST VÔ HIỆU (xanh cả khi bỏ bản sửa)",
}
SESSIONS_LIMIT = 20
# Bug states that mean "nothing guards this bug from coming back".
NO_REGRESSION_TEST = ("NEEDS_TEST", "NOT_IN_MATRIX")


def _now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def load(project_dir: Path) -> dict:
    path = Path(project_dir) / STATUS_FILE
    raw = path.read_bytes() if path.exists() else None
    try:   # overwritten outside the DevKit with older content (a rollback) → a kept warning
        _check_journal(project_dir, raw)
    except (OSError, ValueError):
        pass
    if raw is None:
        return {"version": 1, "items": {}}
    data = json.loads(raw.decode("utf-8"))  # a corrupt file is an error, never silently reset to empty
    if not isinstance(data, dict) or not isinstance(data.get("items"), dict):
        raise ValueError(f"{path} không đúng định dạng checklist")
    return data


def save(project_dir: Path, data: dict, *, stale: bool = True) -> Path:
    """Write the JSON and re-render the view. stale=False skips the git-based STALE check
    (the prompt hook has no time budget for git)."""
    if stale:
        try:
            mark_stale(data, project_dir)
        except OSError:
            pass
        inbox = Path(project_dir) / INBOX_FILE
        if not inbox.exists() and inbox.parent.is_dir():
            inbox.write_text(INBOX_TEMPLATE, encoding="utf-8")   # created once; never rewritten
    path = Path(project_dir) / STATUS_FILE
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".regression_status.")
    with os.fdopen(fd, "wb") as f:
        f.write(raw)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
    try:   # after the replace: a reader never sees a journal newer than the file
        _journal_save(project_dir, raw, data)
    except (OSError, ValueError):
        pass   # the journal is a safety net; it never blocks a save
    render(project_dir, data)
    return path


@contextlib.contextmanager
def locked(project_dir: Path):
    """Serialize load → change → save of one checklist between the prompt hook and the
    CLI (two sessions, one project). The lock file lives in the temp dir, not .agents/."""
    import fcntl
    key = hashlib.sha1(str(Path(project_dir).resolve()).encode()).hexdigest()[:16]
    with open(os.path.join(tempfile.gettempdir(), f"regression_status.{key}.lock"), "w") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(fh, fcntl.LOCK_UN)


# ── Write journal, rollback detection, snapshots, restore ────────────────────────────────
# Incident 2026-09-24: `git show HEAD:.agents/regression_status.json > …` outside the lock wiped a
# day of red_proof results and link/unlink edits, and nothing noticed. Every save() journals
# {time, writer, pid, content hash} and keeps a snapshot; load() compares the file with the last
# journaled one. A file that lost content (a red_proof, an unlink, a link, a row, a result) is a
# rollback: rollback.json keeps the warning and pins the last good snapshot until
# `agent-kit checklist restore` merges it back. Git-ignored by its own .gitignore, like evidence/.
JOURNAL_DIR = Path(".agents") / "regression_journal"
JOURNAL_NAME = "journal.jsonl"
ROLLBACK_NAME = "rollback.json"
REMOVED_NAME = "removed.json"   # rows removed by a DevKit save (drop, UNCOVERED linked/pruned), last 500
SNAP_SUBDIR = "snapshots"
LINK_KEYS = ("tests", "runs_in_suite", "test_refs")
PROOF_LIVE = ("PROVEN", "VACUOUS", "INCONCLUSIVE", "PENDING")
_WARNED: set = set()


def _env_int(name: str, default: int) -> int:
    try:
        return max(1, int(os.environ.get(name, default)))
    except ValueError:
        return default


def _jdir(project_dir: Path, create: bool = False) -> Path:
    d = Path(project_dir) / JOURNAL_DIR
    if create:
        (d / SNAP_SUBDIR).mkdir(parents=True, exist_ok=True)
        if not (d / ".gitignore").exists():
            (d / ".gitignore").write_text("*\n", encoding="utf-8")   # never committed
    return d


def _sha(raw) -> str:
    return "" if raw is None else hashlib.sha256(raw).hexdigest()


def _writer() -> str:
    return os.environ.get("DEVKIT_TOOL") or os.path.basename(sys.argv[0] or "") or "python"


def _records(project_dir: Path) -> list:
    try:
        lines = (_jdir(project_dir) / JOURNAL_NAME).read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    out = []
    for line in lines:
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if isinstance(rec, dict):
            out.append(rec)
    return out


def _last_known(project_dir: Path):
    """The last record that says which content the file should hold."""
    for rec in reversed(_records(project_dir)):
        if "hash" in rec:
            return rec
    return None


def _append(project_dir: Path, rec: dict) -> None:
    """One JSON line; the file keeps its last CHECKLIST_JOURNAL_MAX lines (default 500)."""
    path = _jdir(project_dir, create=True) / JOURNAL_NAME
    rec = {"at": _now(), "ts": round(time.time(), 3), "writer": _writer(), "pid": os.getpid(), **rec}
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    cap = _env_int("CHECKLIST_JOURNAL_MAX", 500)
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    if len(lines) > cap:
        _write_bytes(path, "".join(lines[-cap:]).encode("utf-8"))


def _write_bytes(path: Path, raw: bytes) -> None:
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp.")
    with os.fdopen(fd, "wb") as f:
        f.write(raw)
    os.replace(tmp, path)


def _removed(project_dir: Path) -> dict:
    try:
        gone = json.loads((_jdir(project_dir) / REMOVED_NAME).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return gone if isinstance(gone, dict) else {}


def _rollback(project_dir: Path):
    try:
        return json.loads((_jdir(project_dir) / ROLLBACK_NAME).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _snap_rel(name: str) -> str:
    return (JOURNAL_DIR / SNAP_SUBDIR / name).as_posix()


def _snapshot(project_dir: Path, raw: bytes, digest: str) -> str:
    """Keep this content as a snapshot (once per hash); the newest CHECKLIST_SNAPSHOTS (default
    10) are kept, plus the ones an open rollback pins. Returns the snapshot's name."""
    folder = _jdir(project_dir, create=True) / SNAP_SUBDIR
    for old in folder.glob(f"*-{digest[:12]}.json"):
        os.utime(old)   # the newest again: rotation must not drop the current baseline
        return old.name
    name = f"{time.strftime('%Y%m%d-%H%M%S')}-{digest[:12]}.json"
    _write_bytes(folder / name, raw)
    pinned = set((_rollback(project_dir) or {}).get("good", []))
    snaps = sorted((p for p in folder.glob("*.json") if p.name not in pinned),
                   key=lambda p: (p.stat().st_mtime_ns, p.name))
    for p in snaps[:-_env_int("CHECKLIST_SNAPSHOTS", 10)]:
        p.unlink()
    return name


def _read_snap(project_dir: Path, name) -> dict | None:
    if not name:
        return None
    try:
        data = json.loads((_jdir(project_dir) / SNAP_SUBDIR / name).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) and isinstance(data.get("items"), dict) else None


def _ts(rec) -> float:
    """When a result / proof / unlink was written: its ts, else its `at`, else 0."""
    if not isinstance(rec, dict):
        return 0.0
    if isinstance(rec.get("ts"), (int, float)):
        return float(rec["ts"])
    try:
        return time.mktime(time.strptime(str(rec.get("at")), "%Y-%m-%d %H:%M:%S"))
    except (ValueError, OverflowError):
        return 0.0


def _ukey(u) -> tuple:
    return (u.get("at"), u.get("ref")) if isinstance(u, dict) else (None, str(u))


def _unlinked_refs(item: dict) -> set:
    refs = set()
    for u in item.get("unlinked") or []:
        if isinstance(u, dict):
            refs.add(u.get("ref"))
            refs.update(u.get("removed") or [])
    return refs


def losses(good: dict, cur: dict, gone=()) -> list:
    """What `good` holds that `cur` lost: rows, red_proof results, unlinks, links, test results.
    Empty = `cur` descends from `good` (an out-of-band write that only added is no rollback).
    `gone`: rows a DevKit save removed (drop, UNCOVERED linked or pruned) — no loss."""
    out = []
    citems = cur.get("items") or {}
    for iid, g in (good.get("items") or {}).items():
        c = citems.get(iid)
        if not isinstance(g, dict):
            continue
        if not isinstance(c, dict):
            if iid not in gone:
                out.append(f"{iid}: dòng bị mất")
            continue
        gp, cp = g.get("red_proof"), c.get("red_proof")
        if isinstance(gp, dict) and (not isinstance(cp, dict) or _ts(cp) < _ts(gp)):
            out.append(f"{iid}: red_proof {gp.get('status')} bị mất")
        lost_u = {_ukey(u) for u in g.get("unlinked") or []} - {_ukey(u) for u in c.get("unlinked") or []}
        if lost_u:
            out.append(f"{iid}: {len(lost_u)} unlink bị mất")
        undone = _unlinked_refs(c)
        for key in LINK_KEYS:
            lost_l = [v for v in g.get(key) or [] if v not in (c.get(key) or []) and v not in undone]
            if lost_l:
                out.append(f"{iid}: link {', '.join(map(str, lost_l))} bị mất")
        gl, cl = g.get("last"), c.get("last")
        if isinstance(gl, dict) and (not isinstance(cl, dict) or _ts(cl) < _ts(gl)):
            out.append(f"{iid}: kết quả {gl.get('status')} bị mất")
    return out


def _check_journal(project_dir: Path, raw) -> None:
    """Called by load(): the file is not the last journaled content and lost content → open (or
    extend) rollback.json. An unknown file that lost nothing is adopted as the new baseline."""
    last = _last_known(project_dir)
    if last is None:
        return
    digest = _sha(raw)
    if digest != last.get("hash"):
        time.sleep(0.2)   # a save between its os.replace and its journal line (reader outside the lock)
        last = _last_known(project_dir) or last
    if digest != last.get("hash"):
        good_name = last.get("snapshot")
        good = _read_snap(project_dir, good_name)
        cur = json.loads(raw.decode("utf-8")) if raw is not None else {"items": {}}
        lost = losses(good, cur, _removed(project_dir)) if good is not None and isinstance(cur, dict) else []
        snap = _snapshot(project_dir, raw, digest) if raw is not None else None
        if not lost:
            _append(project_dir, {"event": "external", "hash": digest, "snapshot": snap})
        else:
            older = any(r.get("hash") == digest for r in _records(project_dir))
            rb = _rollback(project_dir) or {"detected_at": _now(), "good": [], "losses": [], "count": 0}
            if good_name not in rb["good"]:
                rb["good"] = (rb["good"] + [good_name])[-5:]
            rb["losses"] = list(dict.fromkeys(rb["losses"] + lost))[:50]
            rb["count"] = len(rb["losses"])
            rb.update({"hash": digest, "last_seen": _now(), "older_copy": older or rb.get("older_copy", False),
                       "missing": raw is None})
            _write_bytes(_jdir(project_dir, create=True) / ROLLBACK_NAME,
                         json.dumps(rb, ensure_ascii=False, indent=2).encode("utf-8"))
            _append(project_dir, {"event": "rollback", "hash": digest, "snapshot": snap, "good": good_name,
                                  "lost": len(lost)})
    msg = rollback_warning(project_dir)
    key = str(Path(project_dir).resolve())
    if msg and key not in _WARNED:
        _WARNED.add(key)
        print(msg, file=sys.stderr)


def _journal_save(project_dir: Path, raw: bytes, data: dict) -> None:
    digest = _sha(raw)
    last = _last_known(project_dir)
    if last is not None and last.get("hash") == digest:
        return   # the same content again: no line, no snapshot slot burnt
    items = data.get("items") or {}
    prev = _read_snap(project_dir, (last or {}).get("snapshot"))
    gone = _removed(project_dir)
    new_gone = {**{k: v for k, v in gone.items() if k not in items},
                **{k: _now() for k in (prev or {}).get("items", {}) if k not in items and k not in gone}}
    if new_gone != gone:   # rows this DevKit save removed: a restore must not bring them back
        _write_bytes(_jdir(project_dir, create=True) / REMOVED_NAME,
                     json.dumps(dict(list(new_gone.items())[-500:]), ensure_ascii=False).encode("utf-8"))
    snap = _snapshot(project_dir, raw, digest)
    rec = {"event": "save", "hash": digest, "snapshot": snap, "rows": len(items),
           "proven": sum(1 for it in items.values() if ((it or {}).get("red_proof") or {}).get("status") == "PROVEN")}
    rb = _rollback(project_dir)
    if rb:
        if _still_lost(project_dir, rb, data):
            rec["lineage"] = "broken"   # a save on top of a rollback: the warning stays
        else:
            (_jdir(project_dir) / ROLLBACK_NAME).unlink()
            rec["resolved"] = True
    _append(project_dir, rec)


def _still_lost(project_dir: Path, rb: dict, data: dict) -> list:
    gone = _removed(project_dir)
    return [x for n in rb.get("good", []) for x in losses(_read_snap(project_dir, n) or {"items": {}}, data, gone)]


def rollback_warning(project_dir: Path) -> str | None:
    """One line for the open rollback, or None. Read-only (the SessionStart hook shows it)."""
    rb = _rollback(project_dir)
    if not rb:
        return None
    good = rb.get("good") or []
    how = "xoá" if rb.get("missing") else ("chép đè bằng bản cũ hơn" if rb.get("older_copy") else "ghi đè ngoài DevKit")
    n = rb.get("count", 0)
    ex = "; ".join(rb.get("losses", [])[:3]) + ("; …" if n > 3 else "")
    return (f"⚠️ ROLLBACK checklist: {STATUS_FILE.as_posix()} bị {how} (phát hiện {rb.get('detected_at')}) — mất {n} "
            f"thay đổi ({ex}). Bản tốt cuối: {_snap_rel(good[-1]) if good else '?'} — gộp lại (merge, không chép "
            "đè): agent-kit checklist restore")


def _merge_item(s: dict, c: dict, stats: dict) -> None:
    """Merge snapshot row `s` into current row `c` (in place)."""
    sp, cp = s.get("red_proof"), c.get("red_proof")
    if isinstance(sp, dict) and (not isinstance(cp, dict) or _ts(sp) > _ts(cp)):
        c["red_proof"] = dict(sp)
        stats["red_proof"] += 1
    sl, cl = s.get("last"), c.get("last")
    if isinstance(sl, dict) and (not isinstance(cl, dict) or _ts(sl) > _ts(cl)):
        c["last"] = dict(sl)
        stats["results"] += 1
    if s.get("history") or c.get("history"):
        hist = {(_ts(h), h.get("status")): h for h in (c.get("history") or []) + (s.get("history") or [])
                if isinstance(h, dict)}
        c["history"] = [hist[k] for k in sorted(hist, key=lambda k: -k[0])][:HISTORY_LIMIT]
    seen = {_ukey(u) for u in c.get("unlinked") or []}
    back = [u for u in s.get("unlinked") or [] if _ukey(u) not in seen]
    if back:
        c["unlinked"] = sorted((c.get("unlinked") or []) + back, key=_ts)
        stats["unlinks"] += len(back)
    undone = _unlinked_refs(c)
    for key in LINK_KEYS + ("covers",):
        sv, cv = s.get(key) or [], c.get(key) or []
        both = [v for v in cv if v in sv]   # both sides agree: a re-link after an unlink stays
        merged = [v for v in dict.fromkeys(list(cv) + list(sv)) if v in both or v not in undone]
        if merged != cv:
            stats["links"] += 1
            c[key] = merged
    last_unlink = max((_ts(u) for u in c.get("unlinked") or []), default=0.0)
    proof = c.get("red_proof")
    if isinstance(proof, dict) and proof.get("status") in PROOF_LIVE and last_unlink > _ts(proof):
        proof.update({"status": "OUTDATED", "reason": "đã gỡ link sau lần chứng minh này — chứng minh lại"})
    if s.get("fixed") and not c.get("fixed"):
        c["fixed"] = True
    if s.get("state") == "confirmed" and c.get("state") in (None, "reported", "auto_closed"):
        c["state"] = "confirmed"
    if (s.get("linked_ts") or 0) > (c.get("linked_ts") or 0):
        c["linked_at"], c["linked_ts"] = s.get("linked_at"), s["linked_ts"]
    for k, v in s.items():   # anything else only the snapshot has
        if k not in c:
            c[k] = json.loads(json.dumps(v))


def merge_snapshot(snap: dict, cur: dict, gone=()) -> dict:
    """Bring back into `cur` what `snap` holds and `cur` lost: the newer red_proof and result
    per row (by ts), the union of unlinks, the union of links minus the unlinked refs, rows only
    the snapshot has (not ones removed through the DevKit since). Rows and edits made after the
    snapshot are kept. Returns counts."""
    stats = {"rows": 0, "red_proof": 0, "unlinks": 0, "links": 0, "results": 0}
    items = cur.setdefault("items", {})
    for iid, s in (snap.get("items") or {}).items():
        if not isinstance(s, dict):
            continue
        if iid not in items:
            if iid not in gone:
                items[iid] = json.loads(json.dumps(s))
                stats["rows"] += 1
            continue
        _merge_item(s, items[iid], stats)
    for k, v in (snap.get("stats") or {}).items():
        if isinstance(v, int):
            cur.setdefault("stats", {})[k] = max(v, int((cur.get("stats") or {}).get(k, 0)))
    for k, v in snap.items():
        cur.setdefault(k, v)
    return stats


def list_snapshots(project_dir: Path) -> list:
    """[(name, rows, proven, flags)] newest first."""
    folder = _jdir(project_dir) / SNAP_SUBDIR
    rb = _rollback(project_dir) or {}
    path = Path(project_dir) / STATUS_FILE
    cur = _sha(path.read_bytes()) if path.exists() else ""
    out = []
    for p in sorted(folder.glob("*.json"), key=lambda p: (p.stat().st_mtime_ns, p.name), reverse=True):
        items = (_read_snap(project_dir, p.name) or {"items": {}})["items"]
        flags = (["bản tốt trước rollback"] if p.name in rb.get("good", []) else []) + \
                (["= file hiện tại"] if cur and p.name.endswith(f"-{cur[:12]}.json") else [])
        proven = sum(1 for it in items.values() if ((it or {}).get("red_proof") or {}).get("status") == "PROVEN")
        out.append((p.name, len(items), proven, flags))
    return out


def restore(project_dir: Path, snapshot: str | None = None) -> tuple:
    """Merge a snapshot (default: the good ones an open rollback pinned, else the newest) into the
    current checklist, under the lock, through save(). (snapshot names, counts, still lost)."""
    folder = _jdir(project_dir) / SNAP_SUBDIR
    with locked(project_dir):
        _WARNED.add(str(Path(project_dir).resolve()))   # restore prints its own result
        data = load(project_dir)
        if snapshot:
            name = Path(snapshot).name
            if not (folder / name).is_file() and (folder / f"{name}.json").is_file():
                name += ".json"
            names = [name]
        else:
            names = list((_rollback(project_dir) or {}).get("good") or [])
            if not names:
                names = [s[0] for s in list_snapshots(project_dir)[:1]]
        if not names:
            raise ValueError(f"không có snapshot nào trong {JOURNAL_DIR.as_posix()}/{SNAP_SUBDIR}")
        total = {"rows": 0, "red_proof": 0, "unlinks": 0, "links": 0, "results": 0}
        for name in names:
            snap = _read_snap(project_dir, name)
            if snap is None:
                raise ValueError(f"không đọc được snapshot {_snap_rel(name)}")
            for k, v in merge_snapshot(snap, data, _removed(project_dir)).items():
                total[k] += v
        os.environ.setdefault("DEVKIT_TOOL", "checklist-restore")
        save(project_dir, data)
        rb = _rollback(project_dir)
        left = _still_lost(project_dir, rb, data) if rb else []
    return names, total, left


def dismiss_rollback(project_dir: Path) -> bool:
    """Accept the current file as it is (a deliberate reset): close the warning, keep snapshots."""
    path = _jdir(project_dir) / ROLLBACK_NAME
    if not path.exists():
        return False
    path.unlink()
    _append(project_dir, {"event": "dismiss"})
    return True


def _slug(text: str, max_len: int = 40) -> str:
    # Vietnamese titles keep their letters: "bị xóa" → "bi-xoa", not "b-x-a".
    text = unicodedata.normalize("NFKD", text.lower().replace("đ", "d"))
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    s = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return (s[:max_len].rstrip("-")) or "bug"


def norm_title(text: str) -> str:
    """The dedupe key of a bug title: case, spacing, punctuation and where the tone
    mark sits ("xoá" / "xóa") do not count."""
    text = unicodedata.normalize("NFKD", (text or "").lower().replace("đ", "d"))
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return " ".join(re.findall(r"\w+", text))


def sync_from_matrix(data: dict, matrix: dict) -> None:
    """Every mandatory regression test of the matrix is a checklist row (feature coverage)."""
    for rule in matrix.get("rules", []) or []:
        comp = rule.get("component", "UnknownComponent")
        for test in rule.get("mandatory_regression_tests", []) or []:
            tid = test.get("id")
            if not tid:
                continue
            item = data["items"].setdefault(tid, {"id": tid, "kind": "test", "last": None, "history": []})
            item.update({"title": test.get("name") or tid, "component": comp,
                         "command": test.get("command"), "watch_files": rule.get("watch_files", [])})
            if test.get("impacted_command"):   # the same runner limited to given tests (red_proof.py)
                item["impacted_command"] = test["impacted_command"]
            else:
                item.pop("impacted_command", None)


EVIDENCE_DIR = Path(".agents") / "evidence"
EVIDENCE_KEEP = 10
EVIDENCE_MAX_BYTES = 1_000_000


def write_evidence(project_dir: Path, test_id: str, output: str, meta: dict) -> str | None:
    """Keep one run's full runner output as acceptance evidence:
    .agents/evidence/<test-id>/<timestamp>.log, a `# key: value` header first, only the
    last EVIDENCE_KEEP logs per test (env EVIDENCE_KEEP), the tail of an output over 1 MB.
    Git-ignored — a runner can print secrets. Returns the path relative to the project."""
    root = Path(project_dir) / EVIDENCE_DIR
    folder = root / re.sub(r"[^A-Za-z0-9_.-]", "_", test_id or "test")
    folder.mkdir(parents=True, exist_ok=True)
    ignore = root / ".gitignore"
    if not ignore.exists():
        ignore.write_text("*\n", encoding="utf-8")
    stamp = time.strftime("%Y%m%d-%H%M%S")
    path, n = folder / f"{stamp}.log", 2
    while path.exists():
        path, n = folder / f"{stamp}-{n}.log", n + 1
    body = output or ""
    if len(body.encode("utf-8", "replace")) > EVIDENCE_MAX_BYTES:
        body = "… (đầu log bị cắt, giữ 1 MB cuối)\n" + body[-EVIDENCE_MAX_BYTES:]
    head = "".join(f"# {k}: {v}\n" for k, v in meta.items() if v not in (None, ""))
    path.write_text(f"# test: {test_id}\n# at: {_now()}\n{head}\n{body}", encoding="utf-8")
    try:
        keep = max(1, int(os.environ.get("EVIDENCE_KEEP", EVIDENCE_KEEP)))
    except ValueError:
        keep = EVIDENCE_KEEP
    for old in sorted(folder.glob("*.log"), key=lambda f: (f.stat().st_mtime_ns, f.name))[:-keep]:
        old.unlink()
    return str(path.relative_to(project_dir))


def _git_lines(project: Path, *args) -> list | None:
    import subprocess
    r = subprocess.run(["git", "-C", str(project), *args], capture_output=True, text=True)
    return r.stdout.splitlines() if r.returncode == 0 else None


def mark_stale(data: dict, project_dir: Path) -> list:
    """Flag PASS suites whose code changed since the run: item["stale_since"] (+ the files),
    cleared when nothing changed. A watched file that differs from the run's commit counts
    only if it was modified after the run (mtime) — a dirty run already tested what was in
    the tree, even once committed; a file gone since a clean run counts; a run commit that
    no longer resolves counts (nothing proves the code is the same). One `git diff` per
    distinct commit, one untracked-file listing. Needs git: not on the prompt-hook path.
    Returns the ids newly marked."""
    import fnmatch
    project = Path(project_dir)
    untracked = _git_lines(project, "ls-files", "--others", "--exclude-standard")
    if untracked is None:
        return []                         # not a git work tree: nothing can be said
    for it in data["items"].values():      # a proved test file changed since → prove again
        proof = it.get("red_proof") or {}
        if proof.get("status") in ("PROVEN", "VACUOUS") and proof.get("files"):
            for f, h in proof["files"].items():
                try:
                    cur = hashlib.sha1((project / f).read_bytes()).hexdigest()[:16]
                except OSError:
                    cur = None
                if cur != h:
                    proof.update({"status": "OUTDATED", "reason": f"{f} đã đổi sau lần chứng minh"})
                    break
    diffs, newly = {}, []
    covers = {tid: it.get("covers", []) for tid, it in data["items"].items() if it.get("kind") == "test"}
    for tid, item in data["items"].items():
        last = item.get("last") or {}
        if item.get("kind") != "test" or last.get("status") != "PASS":
            item.pop("stale_since", None); item.pop("stale_files", None)
            continue
        raw = last.get("commit") or ""
        sha, dirty = raw.split("+")[0], raw.endswith("+dirty")
        if sha not in diffs:
            diffs[sha] = _git_lines(project, "diff", "--name-only", sha) if sha else None
        changed = diffs[sha]
        pats = list(item.get("watch_files", [])) + [f for f in covers.get(tid, [])]
        if changed is None:
            hits = ["(commit %s không còn trong repo)" % (sha or "?")]
        else:
            hits = []
            ts = last.get("ts") or 0
            for f in dict.fromkeys(changed + untracked):
                if not any(fnmatch.fnmatch(f, pat) for pat in pats):
                    continue
                try:
                    if (project / f).stat().st_mtime > ts:
                        hits.append(f)
                except OSError:
                    if not dirty:
                        hits.append(f)   # deleted since a clean run
        if hits:
            if not item.get("stale_since"):
                item["stale_since"] = _now()
                newly.append(tid)
            item["stale_files"] = hits[:5]
        else:
            item.pop("stale_since", None); item.pop("stale_files", None)
    meta = data.setdefault("meta", {})
    st = _git_lines(project, "status", "--porcelain", "--", ".agents/regression_matrix.active.json")
    meta["matrix_pending"] = bool(st) if st is not None else None
    cutoff = time.time() - ARCHIVE_DAYS * 86400
    for it in data["items"].values():        # stable bugs → archive view (view only)
        if it.get("kind") != "bug":
            continue
        linked = it.get("linked_ts") or 0
        stable = bool(linked) and linked <= cutoff and effective_status(data, it) == "PASS"
        if stable:
            n = _git_lines(project, "rev-list", "--count", f"--since={int(linked)}", "HEAD")
            stable = bool(n) and n[0].isdigit() and int(n[0]) >= ARCHIVE_COMMITS
        if stable:
            it["archived"] = True
        else:
            it.pop("archived", None)
    return newly


# A red run counts as a FAILED TEST (so red-then-green is FLAKY) only when the runner reported a
# test failure. A build / infra failure — Gradle losing its own output file when two builds share
# a tree, a daemon crash, a lock — then green on the re-run is a real PASS of the same code.
TEST_FAILED_RE = re.compile(
    r"There were failing tests|\d+ tests? completed, \d+ failed|^\S.* > .+ FAILED\s*$|FAIL: (?:Edit|Play)Mode|"
    r"\b[1-9]\d* (?:failed|failures?|failing)\b|FAILED \((?:failures|errors)=|^--- FAIL:|^not ok\b|"
    r"AssertionError|AssertionFailedError|Expected: .*\n\s+But was|\[Failed\]", re.M)


def test_failure_reported(output: str) -> bool:
    return bool(TEST_FAILED_RE.search(output or ""))


def record_results(data: dict, tests: list, *, task: str | None, commit: str | None) -> None:
    """Store results of tests the gate ACTUALLY ran. NOT_RUN only flags the row as impacted."""
    for t in tests:
        tid = t.get("id")
        if not tid or tid not in data["items"]:
            continue
        item = data["items"][tid]
        if t.get("status") not in RESULT_STATES:
            item["impacted_at"] = _now()
            continue
        result = {"status": t["status"], "at": _now(), "ts": time.time(), "task": task, "commit": commit,
                  "duration": t.get("duration"), "exit_code": t.get("exit_code"), "log": t.get("log")}
        if t.get("flaky"):
            result["flaky"] = True   # red, then green on a re-run of the same code: not a PASS
        if t.get("infra_retry"):
            result["infra_retry"] = True   # first run broke in the build, the re-run ran green
        item["last"] = result
        item["history"] = ([result] + item.get("history", []))[:HISTORY_LIMIT]
        for k in ("impacted_at", "stale_since", "stale_files"):
            item.pop(k, None)
        if result.get("flaky"):
            register_bug(data, f"Test chập chờn (flaky): {tid}", fixed=False,
                         component=item.get("component") or "-", test_ids=[tid],
                         evidence=result.get("log"))


def add_uncovered(data: dict, files: list, *, task: str | None) -> list:
    """Changed source files no matrix rule covers → UNCOVERED rows (deduplicated by path)."""
    added = []
    for f in files:
        key = f"UNCOVERED:{f}"
        if key in data["items"]:
            data["items"][key]["seen_at"] = _now()
            continue
        data["items"][key] = {"id": key, "kind": "uncovered", "title": f, "component": "-",
                              "file": f, "created_at": _now(), "task": task, "last": None, "history": []}
        added.append(key)
    return added


def prune_uncovered(data: dict, still_uncovered) -> list:
    """Drop UNCOVERED rows whose file no longer counts as uncovered code.

    `still_uncovered(files)` is the gate's own rule (profile extensions, docs/.agents
    roots, test paths, watch patterns, existence) and returns the files that still are.
    Rows from before a rule changed (docs XML counted as code, a file a rule now
    watches, a deleted file) would otherwise stay "⚠️ chưa có test" forever.
    """
    rows = {k: it.get("file") for k, it in data["items"].items() if it.get("kind") == "uncovered"}
    keep = set(still_uncovered([f for f in rows.values() if f]))
    removed = [k for k, f in rows.items() if f not in keep]
    for k in removed:
        del data["items"][k]
    return removed


def find_bug(data: dict, title: str, component: str = "-", *, open_only: bool = False):
    """Id of the bug row with the same normalized title and module, or None. A REPORTED
    row has no module yet and matches any. open_only: only rows not fixed yet."""
    key = norm_title(title)
    for bid, it in data["items"].items():
        if it.get("kind") != "bug" or norm_title(it.get("title", "")) != key:
            continue
        if open_only and not (it.get("state") in ("reported", "auto_closed") or it.get("fixed") is False):
            continue
        comp = it.get("component") or "-"
        if comp == (component or "-") or (it.get("state") in ("reported", "auto_closed") and comp == "-"):
            return bid
    return None


def touch_session(item: dict, session: str | None) -> None:
    if session:
        item["touched_at"] = _now()
        if session not in item.setdefault("sessions", []):
            item["sessions"] = (item["sessions"] + [session])[-SESSIONS_LIMIT:]


AUTO_CLOSE_DAYS = 14


def auto_close_reported(data: dict, days: int = AUTO_CLOSE_DAYS) -> list:
    """REPORTED rows nobody touched for `days` → state auto_closed (💤): not counted, not
    deleted; the same bug prompt again reopens the row. Returns the ids closed."""
    cutoff = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - days * 86400))
    closed = []
    for bid, it in data["items"].items():
        if it.get("kind") == "bug" and it.get("state") == "reported" and not it.get("tests") \
                and not it.get("test_refs") and (it.get("touched_at") or it.get("created_at") or "") < cutoff:
            it["state"] = "auto_closed"
            closed.append(bid)
    return closed


def register_bug(data: dict, title: str, *, fixed=True, component: str = "-", severity: str | None = None,
                 evidence: str | None = None, cause: str | None = None, task: str | None = None,
                 test_ids: list = (), state: str | None = None, session: str | None = None,
                 bug_id: str | None = None, open_only: bool = False, linked_now: bool = True) -> tuple:
    """(id, created). A new bug row, or the existing one with the same normalized title
    + module (or the row bug_id names) updated in place — never a duplicate. Never a
    result: linked tests show NOT_RUN until a real gate run. state="reported" is a bug
    prompt nobody confirmed yet; any other call confirms the row. linked_now=False only
    for tests the caller has just run itself (post-fix-gate), so their result counts."""
    title = " ".join((title or "").split())
    if not title:
        raise ValueError("thiếu tiêu đề bug")
    component = component or "-"
    if bug_id and not bug_id.upper().startswith("BUG"):
        bug_id = f"BUG-{bug_id}"
    bid = bug_id if bug_id in data["items"] else (None if bug_id else find_bug(data, title, component, open_only=open_only))
    created = bid is None
    if created:
        bid = bug_id or f"BUG-{time.strftime('%Y%m%d')}-{_slug(title)}"
        n = 2
        while bid in data["items"] and not bug_id:
            bid = f"BUG-{time.strftime('%Y%m%d')}-{_slug(title)}-{n}"
            n += 1
        data["items"][bid] = {"id": bid, "kind": "bug", "title": title, "cause": cause, "component": component,
                              "created_at": _now(), "task": task, "tests": [], "last": None, "history": []}
    item = data["items"][bid]
    if item.get("kind") != "bug":
        raise ValueError(f"{bid} không phải bug")
    if state == "reported":
        if created or item.get("state") == "auto_closed":   # reported again: reopen
            item.update({"state": "reported", "fixed": None})
        if created:
            _count(data, "reported_total")
    else:
        if item.get("state") == "reported" or not created:
            item.update({"title": title, "state": "confirmed"})
        item["fixed"] = bool(fixed) or (item.get("fixed") is True and not created)
        if component != "-":
            item["component"] = component
        for k, v in (("severity", severity), ("evidence", evidence), ("cause", cause), ("task", task)):
            if v:
                item[k] = v
    new_links = [t for t in test_ids if t not in item.setdefault("tests", [])]
    if new_links:
        item["tests"] += new_links
        if linked_now:   # an older result predates the link: not re-run yet, never PASS
            item["linked_at"], item["linked_ts"] = _now(), time.time()
    touch_session(item, session)
    return bid, created


def add_bug(data: dict, title: str, *, cause: str | None, task: str | None, test_ids: list, **kw) -> str:
    """A fixed bug (post-fix-gate --record-lesson). Linked to the regression test(s) the
    gate just ran green for it, if any. The same title again updates that row."""
    return register_bug(data, title, cause=cause, task=task, test_ids=test_ids, linked_now=False, **kw)[0]


def link(data: dict, item_id: str, test_id: str) -> None:
    if item_id not in data["items"]:
        raise KeyError(f"Không có mục {item_id!r} trong checklist")
    if test_id not in data["items"] or data["items"][test_id].get("kind") != "test":
        raise KeyError(f"{test_id!r} không phải test id trong regression matrix (chạy gate một lần để đồng bộ)")
    item = data["items"][item_id]
    if item["kind"] == "uncovered":
        # Covered now: the row is resolved; keep it traceable as a note on the test.
        data["items"][test_id].setdefault("covers", []).append(item["file"])
        del data["items"][item_id]
        return
    if item["kind"] != "bug":
        raise ValueError("Chỉ link được mục bug hoặc UNCOVERED vào test")
    item.setdefault("tests", [])
    if test_id not in item["tests"]:
        item["tests"].append(test_id)
    item["linked_at"], item["linked_ts"] = _now(), time.time()  # older results predate the link: not re-run yet


def _resolve_refs(data: dict, refs: list, project: Path | None) -> tuple:
    """(matrix ids, refs the matrix never runs, refs shown next to their suite) — the
    same resolution `import_bugs` uses."""
    in_matrix, outside, in_suite = [], [], []
    for t in refs:
        ids = resolve_test_ref(project, t, data) if project else \
            ([t] if (data["items"].get(t) or {}).get("kind") == "test" else [])
        if ids:
            in_matrix += [i for i in ids if i not in in_matrix]
            if ids != [t]:
                in_suite.append(t)
        else:
            outside.append(t)
    return in_matrix, outside, in_suite


def link_bug(data: dict, bug_id: str, ref: str, *, project: Path | None = None,
             session: str | None = None) -> tuple:
    """Link a bug to the test that proves its fix (a matrix id, test file or class):
    (matrix ids, refs outside the matrix). The bug counts as fixed and confirmed; it
    shows NOT_RUN until a real gate run, or NOT_IN_MATRIX when the gate never runs it."""
    item = data["items"].get(bug_id)
    if item is None:
        raise KeyError(f"Không có bug {bug_id!r} trong checklist")
    if item.get("kind") != "bug":
        raise ValueError(f"{bug_id} không phải bug")
    in_matrix, outside, in_suite = _resolve_refs(data, [ref], project)
    new_links = [t for t in in_matrix if t not in item.setdefault("tests", [])]
    item["tests"] += new_links
    if new_links:
        item["linked_at"], item["linked_ts"] = _now(), time.time()
    for key, vals in (("runs_in_suite", in_suite), ("test_refs", outside)):
        for v in vals:
            if v not in item.setdefault(key, []):
                item[key].append(v)
    item.update({"fixed": True, "state": "confirmed"})
    touch_session(item, session)
    return in_matrix, outside


_TAG_RE = re.compile(r"\[(BUG-[A-Za-z0-9_.-]+|FIX-[A-Za-z0-9_.-]+|INSTINCT-\d+)\]")
_SCAN_SKIP = {".git", "build", ".gradle", "Library", "Temp", "node_modules", "out", ".idea"}


def _tag_ids(tag: str, items: dict) -> list:
    """Checklist ids a tag can name. A tag never marks the bug fixed."""
    cands = [tag]
    if tag.startswith(("FIX-", "INSTINCT-")):
        cands.append("BUG-" + tag)
    return [c for c in cands if (items.get(c) or {}).get("kind") == "bug"]


def note_test_ref(data: dict, bug_id: str, ref: str) -> bool:
    """Record that a test file names this bug. Does not set fixed or confirmed."""
    item = data["items"].get(bug_id)
    if item is None or item.get("kind") != "bug":
        return False
    refs = item.setdefault("test_refs", [])
    if ref in refs or ref in item.get("tests", []) or ref in item.get("runs_in_suite", []):
        return False
    refs.append(ref)
    item["linked_by"] = item.get("linked_by") or "tag"
    return True


def autolink_tags(project: Path, data: dict) -> list:
    """Link bugs whose id appears as [BUG-…], [FIX-…], or [INSTINCT-NNN] in a test file.

    Returns [(bug_id, path)] newly recorded. Unfixed bugs stay unfixed: the tag
    only says which test talks about them.
    """
    roots = []
    if project.is_dir():
        for dirpath, dirnames, _names in os.walk(project):
            dirnames[:] = [d for d in dirnames if d not in _SCAN_SKIP and not d.startswith(".")]
            base = os.path.basename(dirpath)
            parent = os.path.basename(os.path.dirname(dirpath))
            if base in ("test", "androidTest", "Tests") and parent in ("src", "_Project", "tests"):
                roots.append(Path(dirpath))
            elif base == "tests" and parent == project.name:
                roots.append(Path(dirpath))
    seen = set()
    linked = []
    for root in roots:
        if not root.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in _SCAN_SKIP]
            for name in filenames:
                if not re.search(r"(Test|Tests|Spec)\.(cs|kt|java|swift)$|^test_.*\.py$|_test\.py$", name):
                    continue
                path = Path(dirpath) / name
                key = str(path.resolve())
                if key in seen:
                    continue
                seen.add(key)
                try:
                    text = path.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
                if "[" not in text:
                    continue
                rel = path.relative_to(project).as_posix()
                for tag in dict.fromkeys(_TAG_RE.findall(text)):
                    for bid in _tag_ids(tag, data["items"]):
                        if note_test_ref(data, bid, rel):
                            linked.append((bid, rel))
    return linked


def unlink_bug(data: dict, bug_id: str, ref: str, *, project: Path | None = None) -> list:
    """Undo a link that is context, not a guard. `ref` is a matrix test id linked directly, or a
    test file / class on the row; a suite goes only when no remaining test of the row maps to it.
    The RED-proof becomes OUTDATED (what it proved changed). Returns what was removed."""
    item = data["items"].get(bug_id)
    if item is None or item.get("kind") not in ("bug", "req"):
        raise KeyError(f"Không có bug {bug_id!r} trong checklist")
    removed = []
    for key in ("runs_in_suite", "test_refs"):
        if ref in item.get(key, []):
            item[key].remove(ref)
            removed.append(ref)
    if (data["items"].get(ref) or {}).get("kind") == "test" and ref in item.get("tests", []):
        item["tests"].remove(ref)
        removed.append(ref)
    elif removed and project is not None:
        still = set()
        for r in item.get("runs_in_suite", []):
            still.update(resolve_test_ref(project, r, data))
        for tid in resolve_test_ref(project, ref, data):
            if tid in item.get("tests", []) and tid not in still:
                item["tests"].remove(tid)
                removed.append(tid)
    if not removed:
        raise ValueError(f"{ref!r} không được link vào {bug_id}")
    proof = item.get("red_proof")
    if proof and proof.get("status") in ("PROVEN", "VACUOUS", "INCONCLUSIVE", "PENDING"):
        proof.update({"status": "OUTDATED", "reason": f"đã gỡ link {ref} — chứng minh lại"})
    item.setdefault("unlinked", []).append({"at": _now(), "ts": time.time(), "ref": ref, "removed": removed})
    return removed


def drop(data: dict, bug_id: str) -> dict:
    """Remove a bug row (a REPORTED prompt that was no bug, a duplicate). Tests and
    UNCOVERED rows are not bugs and cannot be dropped here."""
    item = data["items"].get(bug_id)
    if item is None:
        raise KeyError(f"Không có bug {bug_id!r} trong checklist")
    if item.get("kind") not in ("bug", "req"):
        raise ValueError(f"{bug_id} không phải bug/REQ — chỉ xoá được dòng bug hoặc REQ")
    if item.get("state") in ("reported", "auto_closed"):
        _count(data, "reported_dropped")     # a classifier false positive: tunes the bug detector
    return data["items"].pop(bug_id)


def _count(data: dict, key: str) -> None:
    """Weekly-report counters (scripts/nightly.py): kept in the checklist JSON."""
    stats = data.setdefault("stats", {})
    stats[key] = int(stats.get(key, 0)) + 1


def _crit_hash(texts: list) -> str:
    return hashlib.sha1("\n".join(norm_title(t) for t in texts).encode()).hexdigest()[:12]


def _union_links(item: dict) -> None:
    """A REQ's row-level tests / refs = the union of its criteria's (the status, the gate
    and red_proof.py read the row level)."""
    for key in ("tests", "runs_in_suite", "test_refs"):
        vals = []
        for c in item.get("criteria", []):
            vals += [v for v in c.get(key, []) if v not in vals]
        item[key] = vals


def register_req(data: dict, title: str, criteria: list, *, component: str = "-", source: str | None = None,
                 inbox: str | None = None, reason: str | None = None, req_id: str | None = None,
                 session: str | None = None) -> tuple:
    """(id, created). A requirement with acceptance criteria. The criteria are locked by
    hash when first written (before the code, so the tests are not fitted to it): a
    different set needs a reason, kept in criteria_changes. Same title + module → same row."""
    title = " ".join((title or "").split())
    criteria = [" ".join(c.split()) for c in criteria if c and c.strip()]
    if not title:
        raise ValueError("thiếu tiêu đề REQ")
    if not criteria:
        raise ValueError("REQ cần ít nhất một --criterion (tiêu chí nghiệm thu kiểm được)")
    component = component or "-"
    rid = req_id if req_id in data["items"] else None
    if rid is None and not req_id:
        key = norm_title(title)
        rid = next((i for i, it in data["items"].items() if it.get("kind") == "req"
                    and norm_title(it.get("title", "")) == key and (it.get("component") or "-") == component), None)
    created = rid is None
    h = _crit_hash(criteria)
    if created:
        n = max([int(m.group(1)) for m in (re.match(r"REQ-(\d+)$", i) for i in data["items"]) if m] + [0]) + 1
        rid = req_id or f"REQ-{n:03d}"
        data["items"][rid] = {"id": rid, "kind": "req", "title": title, "component": component,
                              "criteria": [{"text": c, "tests": [], "runs_in_suite": [], "test_refs": []} for c in criteria],
                              "criteria_hash": h, "source": source, "created_at": _now(), "last": None, "history": []}
    else:
        item = data["items"][rid]
        if item.get("kind") != "req":
            raise ValueError(f"{rid} không phải REQ")
        if item.get("criteria_hash") != h:
            if not reason:
                raise ValueError(f"tiêu chí của {rid} đã khoá (hash {item.get('criteria_hash')}) — đổi phải có "
                                 "--reason \"<vì sao>\"; tiêu chí viết trước khi code để test không bị viết cho khớp code")
            old = {c["text"]: c for c in item.get("criteria", [])}
            item.setdefault("criteria_changes", []).append(
                {"at": _now(), "reason": reason, "old_hash": item.get("criteria_hash"),
                 "old": [c["text"] for c in item.get("criteria", [])]})
            item["criteria"] = [old.get(c) or {"text": c, "tests": [], "runs_in_suite": [], "test_refs": []}
                                for c in criteria]
            item["criteria_hash"] = h
            _union_links(item)
        if source:
            item["source"] = source
        if component != "-":
            item["component"] = component
    if inbox:
        box = data.setdefault("inbox", {})
        if inbox not in box:
            raise KeyError(f"không có mục hộp thư {inbox!r}")
        box[inbox]["req"] = rid
    touch_session(data["items"][rid], session)
    return rid, created


def link_req(data: dict, req_id: str, which: str, ref: str, *, project: Path | None = None) -> tuple:
    """Link criterion `which` (1-based, or "all") of a REQ to a test (matrix id, file, class)."""
    item = data["items"].get(req_id)
    if item is None or item.get("kind") != "req":
        raise KeyError(f"Không có REQ {req_id!r} trong checklist")
    crit = item.get("criteria", [])
    if which == "all":
        picked = crit
    else:
        try:
            picked = [crit[int(which) - 1]]
        except (ValueError, IndexError):
            raise ValueError(f"{req_id} có {len(crit)} tiêu chí — chọn 1..{len(crit)} hoặc all") from None
    in_matrix, outside, in_suite = _resolve_refs(data, [ref], project)
    new = False
    for c in picked:
        for key, vals in (("tests", in_matrix), ("runs_in_suite", in_suite), ("test_refs", outside)):
            for v in vals:
                if v not in c.setdefault(key, []):
                    c[key].append(v)
                    new = new or key == "tests"
    _union_links(item)
    if new:
        item["linked_at"], item["linked_ts"] = _now(), time.time()
    return in_matrix, outside


INBOX_FILE = Path(".agents") / "INBOX.md"
INBOX_TEMPLATE = ("# 📥 Hộp thư — ghi việc cho agent\n\n"
                  "> Mỗi dòng `- [ ] …` là một yêu cầu; thêm `@làm` để agent làm luôn (tiêu chí → test ĐỎ → code → XANH).\n"
                  "> Agent KHÔNG sửa file này. Trạng thái từng mục: `.agents/CHECKLIST.md`.\n\n")
_INBOX_LINE = re.compile(r"^\s*[-*]\s+\[ \]\s+(.+?)\s*$")


def read_inbox(project_dir: Path) -> list:
    """(key, text, do_now) of the unticked `- [ ]` lines of the user's INBOX.md."""
    try:
        text = (Path(project_dir) / INBOX_FILE).read_text(encoding="utf-8")
    except OSError:
        return []
    out = []
    for line in text.splitlines():
        m = _INBOX_LINE.match(line)
        if m:
            t = m.group(1)
            key = hashlib.sha1(norm_title(t).encode()).hexdigest()[:10]
            out.append((key, t, "@làm" in t or "@lam" in norm_title(t).replace(" ", "")))
    return out


def inbox_new(data: dict, project_dir: Path) -> list:
    """Inbox lines not seen before, now recorded as seen: [(key, text, do_now)]."""
    box = data.setdefault("inbox", {})
    new = []
    for key, text, now in read_inbox(project_dir):
        if key not in box:
            box[key] = {"text": text, "seen_at": _now(), "req": None}
            new.append((key, text, now))
    return new


TSV_COLUMNS = ("bug_id", "title", "severity", "fixed", "module", "test_id", "evidence")
# Header names accepted for each column (lower-case, trailing "?" and spaces ignored).
COLUMN_ALIASES = {
    "bug_id": ("bug_id", "bug", "id", "bug id"),
    "title": ("title", "summary", "name", "bug"),
    "severity": ("severity", "sev", "priority"),
    "fixed": ("fixed", "fixed_in_code", "fixed in code", "status", "done"),
    "module": ("module", "component", "area"),
    "test_id": ("test_id_or_none", "test_id", "test", "tests", "test_ref", "test id"),
    "evidence": ("evidence", "source", "ref", "notes"),
}
REQUIRED_COLUMNS = ("bug_id", "title", "test_id")


def _split_cells(line: str) -> list:
    return [c.strip() for c in (line.split("\t") if "\t" in line else line.strip().strip("|").split("|"))]


def _header_map(cells: list):
    """{column: index} when cells are a header row naming the columns, else None."""
    norm = [c.lower().rstrip("?").strip() for c in cells]
    if not any(n in COLUMN_ALIASES["bug_id"] for n in norm):
        return None
    found = {}
    for col, names in COLUMN_ALIASES.items():
        for i, n in enumerate(norm):
            if n in names and i not in found.values():
                found[col] = i
                break
    return found


def parse_bug_table(text: str) -> list:
    """Rows of a bug table, tab- or `|`-separated. With a header row, columns are read by
    NAME (aliases in COLUMN_ALIASES; order free, severity/module/fixed/evidence optional,
    bug_id/title/test_id required — a table missing one is refused). Without a header,
    by position: bug_id | title | severity | fixed? | module | test_id_or_NONE | evidence.
    Blank, `#` and |---| lines are skipped; several test ids split on , or ;."""
    rows, cols = [], None
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        cells = _split_cells(line)
        if len(cells) < 2 or all(set(c) <= set("-: ") for c in cells):
            continue
        if cols is None and not rows:
            header = _header_map(cells)
            if header is not None:
                missing = [c for c in REQUIRED_COLUMNS if c not in header]
                if missing:
                    raise ValueError(f"bảng thiếu cột bắt buộc {missing} (header: {' | '.join(cells)})")
                cols = header
                continue
        if cols is None:
            cells += [""] * (len(TSV_COLUMNS) - len(cells))
            row = dict(zip(TSV_COLUMNS, cells[:len(TSV_COLUMNS)]))
        else:
            row = {c: (cells[i] if i < len(cells) else "") for c, i in cols.items()}
            for c in TSV_COLUMNS:
                row.setdefault(c, "")
        tid = row["test_id"]
        row["tests"] = [] if tid.upper() in ("", "NONE", "-", "N/A") else \
            [t.strip() for t in tid.replace(";", ",").split(",") if t.strip()]
        row["fixed"] = row["fixed"].strip().lower().rstrip("?") not in (
            "no", "n", "false", "0", "open", "không", "chưa", "not fixed", "todo")
        rows.append(row)
    return rows


def _gradle_module(project: Path, path: str) -> str:
    """":core:data" for core/data/src/test/…: the nearest folder above path with a build.gradle*."""
    parts = path.replace("\\", "/").split("/")[:-1]
    while parts:
        d = project.joinpath(*parts)
        if (d / "build.gradle").is_file() or (d / "build.gradle.kts").is_file():
            return ":" + ":".join(parts)
        parts.pop()
    return ""


def _runs_source_set(path: str, command: str, project: Path = None) -> bool:
    """Does a suite command run the test at path? Heuristic on the source set: an
    instrumented test (src/androidTest) needs a connected*/androidTest task, a unit test
    (src/test) a unit-test task; Unity Tests/EditMode vs Tests/PlayMode need that mode;
    a screenshot test is not run by a command that excludes screenshot tests."""
    p, c = path.replace("\\", "/").lower(), (command or "").lower()
    if "screenshot" in p and "excludescreenshot" in c:
        return False
    if "/androidtest/" in p:
        return "connected" in c or "androidtest" in c
    if "/editmode/" in p:
        return "editmode" in c or "-testplatform editmode" in c
    if "/playmode/" in p:
        return "playmode" in c
    if "test" not in c and "check" not in c:
        return False
    # A Gradle command naming module tasks (:app:testReleaseUnitTest) runs only those
    # modules; an unqualified task (testDebugUnitTest) runs every module that has it.
    if project is not None and "gradlew" in c:
        tasks = [t for t in (command or "").split() if not t.startswith("-")][1:]
        qualified = [t.rsplit(":", 1)[0] for t in tasks if t.startswith(":") and t.count(":") >= 2]
        if tasks and len(qualified) == len([t for t in tasks if "test" in t.lower() or "check" in t.lower()]):
            return _gradle_module(project, path) in qualified
    return True


def resolve_test_ref(project: Path, ref: str, data: dict) -> list:
    """Matrix test ids whose suite runs the test `ref` names: a matrix id itself, or a file
    path / class name (com.a.FooTest, FooTest#m, CozyGoods.Tests.EditMode.WalletMergeTests)
    found with `git ls-files`, whose path a rule watches and whose command runs its source
    set. [] when the gate never runs it."""
    if (data["items"].get(ref) or {}).get("kind") == "test":
        return [ref]
    import fnmatch
    ids = []
    for path in ref_paths(project, ref):
        for tid, item in data["items"].items():
            if item.get("kind") != "test":
                continue
            watched = any(fnmatch.fnmatch(path, pat) for pat in item.get("watch_files", []))
            if watched and _runs_source_set(path, item.get("command"), project) and tid not in ids:
                ids.append(tid)
    return sorted(ids)


def ref_paths(project: Path, ref: str) -> list:
    """The test files a reference names: a path that exists, or a class / module name
    (com.a.FooTest, FooTest#m, :module|path#Class.method [TAGS], Ns.EditMode.FooTests)
    found with `git ls-files`."""
    import subprocess
    import re as _re
    name = _re.sub(r"\s*\[[^\]]*\]\s*$", "", ref.strip())      # trailing [TAGS]
    if "|" in name:                                                # :module|path#Class.method
        name = name.split("|", 1)[1]
    name = name.split("#")[0].split("::")[0].strip()
    if "/" in name:
        paths = [name] if (project / name).exists() else []
    else:
        base = name.rsplit(".", 1)[0] if name.endswith((".kt", ".java", ".cs", ".swift", ".ts", ".py")) else name
        paths = []
        # Namespace.Class, Class.method, EditMode.Class.method: the class is one of the
        # last dotted parts — the first that names a file wins.
        for cls in list(reversed(base.split(".")))[:3]:
            out = subprocess.run(["git", "-C", str(project), "ls-files", f"*/{cls}.*", f"{cls}.*"],
                                 capture_output=True, text=True).stdout.split()
            paths = [x for x in out if x.rsplit("/", 1)[-1].split(".")[0] == cls]
            if paths:
                break
    return paths


def import_bugs(data: dict, rows: list, *, source: str, project: Path = None) -> dict:
    """Past bugs as kind=bug rows. Never a result: a test id of the matrix is linked and
    shows "not re-run" until a real gate run after the import; a test outside the matrix
    (the gate never runs it) and no test at all are both gaps. Re-importing updates the
    description and links; results and history are never touched."""
    counts = {"added": 0, "updated": 0}
    for row in rows:
        bid = row["bug_id"] if row["bug_id"].upper().startswith("BUG") else f"BUG-{row['bug_id']}"
        # a class/file the linked suite runs is kept in refs for display
        in_matrix, outside, refs = _resolve_refs(data, row["tests"], project)
        item = data["items"].get(bid)
        if item is None:
            item = data["items"][bid] = {"id": bid, "kind": "bug", "created_at": _now(), "last": None,
                                         "history": [], "tests": []}
            counts["added"] += 1
        else:
            counts["updated"] += 1
        new_links = [t for t in in_matrix if t not in item.get("tests", [])]
        item.update({"title": row["title"], "severity": row["severity"], "fixed": row["fixed"],
                     "component": row["module"] or "-", "evidence": row["evidence"],
                     "test_refs": outside, "runs_in_suite": refs, "source": source})
        item.setdefault("tests", []).extend(new_links)
        if new_links:
            item["linked_at"], item["linked_ts"] = _now(), time.time()
    return counts


def effective_status(data: dict, item: dict) -> str:
    kind = item.get("kind")
    if kind == "uncovered":
        return "UNCOVERED"
    if kind == "req":
        crit = item.get("criteria") or []
        if not crit or any(not c.get("tests") for c in crit):
            return "NOT_IN_MATRIX" if crit and all(c.get("tests") or c.get("test_refs") for c in crit) else "NEEDS_TEST"
        return _linked_status(data, item)
    if kind == "bug":
        if item.get("state") == "reported" and not item.get("tests") and not item.get("test_refs"):
            return "REPORTED"   # a bug prompt nobody confirmed yet: not counted as a bug
        if item.get("state") == "auto_closed" and not item.get("tests") and not item.get("test_refs"):
            return "AUTO_CLOSED"
        if item.get("fixed") is False:
            return "OPEN"
        return _linked_status(data, item)
    return _test_status(item)


def _linked_status(data: dict, item: dict) -> str:
    """A bug's or REQ's status from the suites it is linked to and its RED-proof."""
    tests = [data["items"].get(t) for t in item.get("tests", [])]
    tests = [t for t in tests if t]
    if not tests:
        return "NOT_IN_MATRIX" if item.get("test_refs") else "NEEDS_TEST"
    proof = (item.get("red_proof") or {}).get("status")
    if proof == "VACUOUS":
        return "VACUOUS"    # green without the fix too: the test guards nothing
    linked = item.get("linked_ts")
    if linked and not any(((t.get("last") or {}).get("ts") or 0) > linked for t in tests):
        return "NOT_RUN"     # linked to a matrix test that has not run since
    states = [effective_status(data, t) for t in tests]
    for bad in ("FAIL", "TIMEOUT", "FLAKY", "STALE", "NOT_RUN"):
        if bad in states:
            return bad
    # A green suite is a PASS for the bug only once its test was seen RED on the
    # unfixed code (scripts/red_proof.py): otherwise it may not test the bug at all.
    return "PASS" if proof == "PROVEN" else "UNPROVEN"


def _test_status(item: dict) -> str:
    last = item.get("last") or {}
    if last.get("status") == "FAIL" and last.get("flaky"):
        return "FLAKY"
    if last.get("status") == "PASS" and (item.get("stale_since")
                                         or (item.get("impacted_at") or "") > (last.get("at") or "")):
        return "STALE"   # code changed since the run, or only part of the suite ran after it
    return last.get("status") or "NOT_RUN"


def summary(data: dict) -> dict:
    counts: dict = {}
    for item in data["items"].values():
        st = effective_status(data, item)
        counts[st] = counts.get(st, 0) + 1
    return counts


def _cell(text) -> str:
    return str(text if text not in (None, "") else "-").replace("|", "\\|").replace("\n", " ")


ALERT_TODO = {
    "FAIL": "sửa code/test rồi chạy lại — xem log",
    "TIMEOUT": "suite quá giờ — tìm test treo, chạy lại",
    "FLAKY": "test chập chờn — tìm nguồn (thời gian, thứ tự, mạng), không tắt test",
    "VACUOUS": "viết lại test cho ĐỎ trên code lỗi rồi chứng minh lại (.agents/devkit/scripts/red_proof.py)",
    "STALE": "code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`)",
    "NEEDS_TEST": "viết test tái hiện → `agent-kit bugs link` / `req link`",
    "NOT_IN_MATRIX": "test có nhưng gate không chạy — đưa vào ma trận hoặc link suite của ma trận",
    "OPEN": "sửa theo ĐỎ→XANH rồi `agent-kit bugs link`",
    "UNCOVERED": "file code chưa có test — gắn test (`regression_checklist.py link`)",
}
ARCHIVE_FILE = Path(".agents") / "archive" / "BUG_ARCHIVE.md"
ARCHIVE_DAYS = ARCHIVE_COMMITS = 30


def _tests_cell(item: dict) -> str:
    tests = ", ".join(item.get("tests", []) + [f"{r} (trong suite)" for r in item.get("runs_in_suite", [])]
                      + [f"{r} (ngoài matrix)" for r in item.get("test_refs", [])]) or "chưa link"
    if item.get("linked_by") == "auto" and item.get("tests"):
        tests = "🤖 " + tests   # linked by the Stop hook from one-to-one RED→GREEN evidence
    return tests


def _title(item: dict) -> str:
    if item.get("kind") == "req":
        crit = item.get("criteria", [])
        return f"REQ: {item.get('title')} ({sum(1 for c in crit if c.get('tests'))}/{len(crit)} tiêu chí có test)"
    return item.get("title") or item["id"]


def _signature(item: dict) -> str:
    """Test | time | exit code | commit | log — the run that backs the row's status."""
    last = item.get("last") or {}
    if not last:
        return "chưa chạy"
    log = last.get("log")
    link = f" · [log]({Path(log).relative_to('.agents')})" if log and log.startswith(".agents/") else ""
    return (f"{last.get('at', '')} · {last.get('duration') or '-'} · exit {last.get('exit_code')} · "
            f"{last.get('commit') or '-'}{link}")


def _evidence(data: dict, item: dict) -> str:
    proof = item.get("red_proof") or {}
    if proof.get("log", "").startswith(".agents/"):
        return f"RED-proof {proof.get('status')}: [log]({Path(proof['log']).relative_to('.agents')})"
    for t in item.get("tests", []):
        log = ((data["items"].get(t) or {}).get("last") or {}).get("log")
        if log and log.startswith(".agents/"):
            return f"[log {t}]({Path(log).relative_to('.agents')})"
    return str(item.get("evidence") or "-")[:80]


def _table(head: str, rows: list) -> list:
    cols = head.count("|") - 1
    return [head, "|" + "---|" * cols] + ["| " + " | ".join(_cell(x) for x in r) + " |" for r in rows]


def render(project_dir: Path, data: dict) -> Path:
    """The dashboard .agents/CHECKLIST.md (and .agents/archive/BUG_ARCHIVE.md): HUD line,
    🚨 alert zone first, inbox, modules (folded at 100% PASS), bug ledger, REPORTED."""
    items = data["items"]
    status = {i: effective_status(data, it) for i, it in items.items()}
    c = summary(data)
    confirmed = [i for i, it in items.items() if it.get("kind") in ("test", "req", "bug")
                 and status[i] not in ("REPORTED", "AUTO_CLOSED")]
    passed = sum(1 for i in confirmed if status[i] == "PASS")
    pct = round(100 * passed / len(confirmed)) if confirmed else 0
    pending = (data.get("meta") or {}).get("matrix_pending")
    lines = [
        "# 🧪 Regression Checklist",
        "",
        f"**An toàn {pct}% ({passed}/{len(confirmed)})** · ❌ {c.get('FAIL', 0) + c.get('TIMEOUT', 0)}"
        f" · 🔁 {c.get('FLAKY', 0)} · 🚫 {c.get('VACUOUS', 0)} · 🟡 {c.get('STALE', 0)} cần chạy lại"
        f" · ⚠️ {c.get('UNCOVERED', 0) + c.get('NEEDS_TEST', 0) + c.get('NOT_IN_MATRIX', 0)} cần test"
        f" · 🐞 {c.get('OPEN', 0)} chưa sửa · ⏳ {c.get('NOT_RUN', 0) + c.get('UNPROVEN', 0)} chờ"
        f" · 🟡 REPORTED {c.get('REPORTED', 0)}"
        f" · ma trận chờ duyệt: {'có' if pending else 'không' if pending is not None else '?'}",
        "",
        f"> Sinh tự động lúc {_now()} — **không sửa tay**. % an toàn = PASS ÷ mọi dòng test/REQ/bug đã xác nhận "
        "(REPORTED không tính). PASS chỉ từ lần chạy thật + (bug/REQ) test đã chứng minh ĐỎ.",
        "",
        f"**Bug không có test hồi quy nào chặn tái phát: {sum(c.get(k, 0) for k in NO_REGRESSION_TEST)}**"
        f" ({c.get('NEEDS_TEST', 0)} chưa có test · {c.get('NOT_IN_MATRIX', 0)} có test nhưng gate không chạy)",
        "",
    ]
    order = {"FAIL": 0, "TIMEOUT": 0, "VACUOUS": 0, "FLAKY": 1, "STALE": 2, "OPEN": 3, "NEEDS_TEST": 4,
             "NOT_IN_MATRIX": 4, "UNCOVERED": 5}
    alert = sorted((i for i in items if status[i] in ALERT_TODO), key=lambda i: (order.get(status[i], 9), i))
    lines.append(f"## 🚨 Cần xử lý ({len(alert)})")
    lines.append("")
    if alert:
        lines += _table("| Trạng thái | ID | Tính năng / Bug | Component | Việc cần làm |",
                        [(ICON.get(status[i], status[i]), i, _title(items[i]), items[i].get("component"),
                          ALERT_TODO[status[i]]) for i in alert])
    else:
        lines.append("Không có gì — mọi dòng đã xác nhận đang an toàn hoặc chờ lần chạy tới.")
    lines.append("")
    box = data.get("inbox") or {}
    inbox = [(k, t) for k, t, _ in read_inbox(project_dir)]
    if inbox:
        lines += [f"## 📥 Hộp thư ({len(inbox)} mục chưa xong — `.agents/INBOX.md`)", ""]
        lines += _table("| Yêu cầu | Trạng thái |",
                        [(t, (f"→ {r} ({ICON.get(status.get(r), '?')})" if (r := (box.get(k) or {}).get("req")) in items
                              else "chưa nhận thành REQ")) for k, t in inbox])
        lines.append("")
    # Modules: the matrix's components — its suites and the REQs that name them.
    modules: dict = {}
    for i, it in items.items():
        if it.get("kind") in ("test", "req"):
            modules.setdefault(it.get("component") or "-", []).append(i)
    lines += ["## 🧩 Phân hệ", ""]
    for comp in sorted(modules, key=lambda m: (m == "-", m)):
        ids = sorted(modules[comp], key=lambda i: (items[i].get("kind") != "test", i))
        ok_ = sum(1 for i in ids if status[i] == "PASS")
        body = _table("| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |",
                      [(ICON.get(status[i], status[i]), i, _title(items[i]),
                        _signature(items[i]) if items[i].get("kind") == "test" else "-",
                        items[i].get("command") if items[i].get("kind") == "test" else _tests_cell(items[i]))
                       for i in ids])
        head = f"{'Khác' if comp == '-' else comp} — {ok_}/{len(ids)} PASS"
        if ok_ == len(ids):
            lines += [f"<details><summary>✅ {head}</summary>", ""] + body + ["", "</details>", ""]
        else:
            lines += [f"### {head}", ""] + body + [""]
    bugs = [i for i, it in items.items() if it.get("kind") == "bug" and status[i] not in ("REPORTED", "AUTO_CLOSED")]
    archived = sorted(i for i in bugs if items[i].get("archived") and status[i] == "PASS")
    ledger = sorted((i for i in bugs if i not in archived), key=lambda i: (order.get(status[i], 8), i))
    lines += [f"## 📒 Sổ tay bug ({len(ledger)}" + (f" · {len(archived)} trong archive" if archived else "") + ")", ""]
    lines += _table("| Trạng thái | Mã | Mô tả | Component | Test bảo vệ | Bằng chứng |",
                    [(ICON.get(status[i], status[i]), i, items[i].get("title"), items[i].get("component"),
                      _tests_cell(items[i]), _evidence(data, items[i])) for i in ledger])
    lines.append("")
    reported = sorted(i for i in items if status[i] == "REPORTED")
    closed = sorted(i for i in items if status[i] == "AUTO_CLOSED")
    if reported:
        # The prompt hook's classifier has false positives: out of the counts until confirmed.
        lines += [f"## 🟡 REPORTED — bug báo qua prompt, chưa xác nhận ({len(reported)})", "",
                  "> Chưa tính là bug. Xác nhận: `agent-kit bugs add \"<tiêu đề>\" --id <ID>` · có test ĐỎ→XANH: "
                  "`agent-kit bugs link <ID> <TEST>` · không phải bug: `agent-kit bugs drop <ID>`", ""]
        lines += _table("| ID | Prompt | Ngày |", [(i, items[i].get("title"), items[i].get("created_at")) for i in reported])
        lines.append("")
    if closed:
        lines += [f"<details><summary>💤 Tự đóng — REPORTED {AUTO_CLOSE_DAYS} ngày không ai đụng ({len(closed)})"
                  "</summary>", ""]
        lines += _table("| ID | Prompt | Ngày |", [(i, items[i].get("title"), items[i].get("created_at")) for i in closed])
        lines += ["", "</details>", ""]
    if archived:
        lines += [f"> 🗄️ {len(archived)} bug ổn định (PASS ≥ {ARCHIVE_DAYS} ngày và ≥ {ARCHIVE_COMMITS} commit) ở "
                  "`archive/BUG_ARCHIVE.md` — test của chúng vẫn chạy; đỏ lại là tự quay về vùng cần xử lý.", ""]
    project = Path(project_dir)
    path = project / VIEW_FILE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")
    old = project / OLD_VIEW_FILE     # one file: the old name links to the new one
    try:
        if not (old.is_symlink() and os.readlink(old) == VIEW_FILE.name):
            if old.exists() or old.is_symlink():
                old.unlink()
            old.symlink_to(VIEW_FILE.name)
    except OSError:
        pass
    if archived:
        arch = project / ARCHIVE_FILE
        arch.parent.mkdir(parents=True, exist_ok=True)
        arch.write_text("\n".join(
            ["# 🗄️ Bug archive — chỉ để xem", "",
             f"> Sinh tự động lúc {_now()}. Bug PASS (đã chứng minh ĐỎ) ≥ {ARCHIVE_DAYS} ngày và ≥ {ARCHIVE_COMMITS} "
             "commit kể từ khi link. Test vẫn chạy mỗi lần gate chạy; đỏ lại → quay về `CHECKLIST.md`.", ""]
            + _table("| Mã | Mô tả | Component | Test bảo vệ | Link từ |",
                     [(i, items[i].get("title"), items[i].get("component"), _tests_cell(items[i]),
                       items[i].get("linked_at")) for i in archived]) + [""]), encoding="utf-8")
    return path


def _sync_matrix(data: dict, project: Path) -> None:
    matrix_file = project / ".agents" / "regression_matrix.active.json"
    if matrix_file.is_file():   # matrix test ids must be known to be linked
        sync_from_matrix(data, json.loads(matrix_file.read_text(encoding="utf-8")))


def _bug_command(args, project: Path) -> int:
    """add / bug-link / drop: one row, under the lock, the id first on the result line."""
    with locked(project):
        data = load(project)
        _sync_matrix(data, project)
        if args.cmd == "bug-unlink":
            removed = unlink_bug(data, args.bug_id, args.test_ref, project=project)
            save(project, data)
            print(f"{args.bug_id} {effective_status(data, data['items'][args.bug_id])} — đã gỡ link: {', '.join(removed)}"
                  " (RED-proof cũ → OUTDATED, chứng minh lại)")
            return 0
        if args.cmd == "req-add":
            rid, created = register_req(data, args.title, args.criterion, component=args.module, source=args.source,
                                        inbox=args.inbox, reason=args.reason, req_id=args.req_id)
            save(project, data)
            it = data["items"][rid]
            print(f"{rid} {effective_status(data, it)} — {'đã thêm' if created else 'đã có, cập nhật'}: {it['title']} "
                  f"({len(it['criteria'])} tiêu chí, hash {it['criteria_hash']})")
            print(f"  link test cho từng tiêu chí: agent-kit req link {rid} <1..{len(it['criteria'])}|all> <test>")
            return 0
        if args.cmd == "req-link":
            in_matrix, outside = link_req(data, args.req_id, args.which, args.test_ref, project=project)
            save(project, data)
            st = effective_status(data, data["items"][args.req_id])
            print(f"{args.req_id} {st} — tiêu chí {args.which} → " + (", ".join(in_matrix) if in_matrix else
                  f"{args.test_ref} (ngoài matrix: gate không chạy)"))
            return 0
        if args.cmd == "drop":
            item = drop(data, args.bug_id)
            save(project, data)
            print(f"{args.bug_id} — đã xoá khỏi checklist: {item.get('title')}")
            return 0
        if args.cmd == "bug-link":
            in_matrix, outside = link_bug(data, args.bug_id, args.test_ref, project=project)
            save(project, data)
            st = effective_status(data, data["items"][args.bug_id])
            if in_matrix:
                print(f"{args.bug_id} {st} — đã link {args.test_ref} → {', '.join(in_matrix)} "
                      "(PASS chỉ có sau lần gate chạy thật: postfix-gate --run-tests)")
            else:
                print(f"{args.bug_id} {st} — {args.test_ref} không nằm trong suite nào của regression matrix: "
                      "gate KHÔNG chạy nó, bug chưa được chặn tái phát (thêm vào matrix hoặc link test id của matrix)")
            return 0
        in_matrix, outside, in_suite = _resolve_refs(data, args.test, project)
        bid, created = register_bug(data, args.title, fixed=args.fixed, component=args.module,
                                    severity=args.severity, evidence=args.evidence, test_ids=in_matrix,
                                    bug_id=args.bug_id)
        item = data["items"][bid]
        for key, vals in (("runs_in_suite", in_suite), ("test_refs", outside)):
            for v in vals:
                if v not in item.setdefault(key, []):
                    item[key].append(v)
        save(project, data)
        st = effective_status(data, item)
        print(f"{bid} {st} — {'đã thêm vào checklist' if created else 'đã có sẵn, cập nhật (không thêm trùng)'}: "
              f"{item['title']}")
        if st in ("OPEN", "NEEDS_TEST"):
            print(f"  sửa xong + test ĐỎ→XANH: agent-kit bugs link {bid} <test>")
        return 0


def _restore_command(args, project: Path) -> int:
    if args.dismiss:
        print("✔ đã đóng cảnh báo rollback (giữ nguyên file hiện tại, snapshot vẫn còn)" if dismiss_rollback(project)
              else "không có cảnh báo rollback nào đang mở")
        return 0
    if args.list:
        snaps = list_snapshots(project)
        if not snaps:
            print(f"chưa có snapshot nào ({JOURNAL_DIR.as_posix()}/{SNAP_SUBDIR}: mỗi lần DevKit ghi checklist)")
        for name, rows, proven, flags in snaps:
            print(f"{_snap_rel(name)}  {rows} dòng · {proven} PROVEN" + (f"  ← {', '.join(flags)}" if flags else ""))
        msg = rollback_warning(project)
        if msg:
            print(msg)
        return 0
    names, total, left = restore(project, args.snapshot)
    print(f"✔ merged {', '.join(_snap_rel(n) for n in names)} → {STATUS_FILE.as_posix()}: "
          f"+{total['rows']} dòng, {total['red_proof']} red_proof, {total['unlinks']} unlink, "
          f"{total['links']} dòng đổi link, {total['results']} kết quả (bản mới hơn theo ts được giữ)")
    if left:
        print(f"⚠️ vẫn còn {len(left)} thay đổi chưa về ({'; '.join(left[:3])}) — restore <snapshot> khác, "
              "hoặc --dismiss nếu cố ý")
        return 1
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Living regression checklist")
    parser.add_argument("--project", default=os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("show")
    sub.add_parser("render")
    p_link = sub.add_parser("link")
    p_link.add_argument("item_id")
    p_link.add_argument("test_id")
    p_imp = sub.add_parser("import", help="add past bugs from a table: "
                           "bug_id | title | severity | fixed? | module | test_id_or_NONE | evidence")
    p_imp.add_argument("table")
    p_imp.add_argument("--dry-run", action="store_true")
    p_add = sub.add_parser("add", help="one new bug: OPEN until fixed, NEEDS_TEST until a test is linked")
    p_add.add_argument("title")
    p_add.add_argument("--severity")
    p_add.add_argument("--module", default="-")
    p_add.add_argument("--evidence")
    p_add.add_argument("--test", action="append", default=[], help="matrix id, test file or class (repeatable)")
    p_add.add_argument("--fixed", action="store_true", help="already fixed in code")
    p_add.add_argument("--id", dest="bug_id", help="confirm this REPORTED row / name the new row")
    p_bl = sub.add_parser("bug-link", help="link a bug to the test that proves its fix")
    p_bl.add_argument("bug_id")
    p_bl.add_argument("test_ref")
    p_drop = sub.add_parser("drop", help="remove a bug or REQ row (not a bug / duplicate)")
    p_drop.add_argument("bug_id")
    p_ul = sub.add_parser("bug-unlink", help="undo a link that is context, not a guard")
    p_ul.add_argument("bug_id")
    p_ul.add_argument("test_ref")
    p_ra = sub.add_parser("req-add", help="a requirement with acceptance criteria (locked by hash)")
    p_ra.add_argument("title")
    p_ra.add_argument("--criterion", action="append", default=[])
    p_ra.add_argument("--module", default="-")
    p_ra.add_argument("--source", help="the prompt / request, verbatim")
    p_ra.add_argument("--inbox", help="the INBOX.md item key this REQ takes over")
    p_ra.add_argument("--reason", help="why locked criteria change")
    p_ra.add_argument("--id", dest="req_id")
    p_rl = sub.add_parser("req-link", help="link criterion N (or all) of a REQ to a test")
    p_rl.add_argument("req_id")
    p_rl.add_argument("which")
    p_rl.add_argument("test_ref")
    p_rs = sub.add_parser("restore", help="merge a journal snapshot back after the checklist was rolled back "
                          "(newer red_proof per row, links minus unlinks, later rows kept)")
    p_rs.add_argument("snapshot", nargs="?", help="snapshot name or path (default: the last good one)")
    p_rs.add_argument("--list", action="store_true", help="list the snapshots")
    p_rs.add_argument("--dismiss", action="store_true", help="accept the current file, close the warning")
    sub.add_parser("check", help="exit 1 + a warning when the checklist was rolled back outside the DevKit")
    args = parser.parse_args(argv)
    project = Path(args.project)
    try:
        if args.cmd == "check":
            _WARNED.add(str(project.resolve()))
            if (project / STATUS_FILE).exists() or (project / JOURNAL_DIR).is_dir():
                load(project)
            msg = rollback_warning(project)
            if msg:
                print(msg)
            return 1 if msg else 0
        if args.cmd == "restore":
            return _restore_command(args, project)
        if args.cmd in ("add", "bug-link", "bug-unlink", "drop", "req-add", "req-link"):
            return _bug_command(args, project)
        data = load(project)
        if args.cmd == "import":
            matrix_file = project / ".agents" / "regression_matrix.active.json"
            if matrix_file.is_file():   # matrix test ids must be known to be linked
                sync_from_matrix(data, json.loads(matrix_file.read_text(encoding="utf-8")))
            rows = parse_bug_table(Path(args.table).read_text(encoding="utf-8"))
            counts = import_bugs(data, rows, source=os.path.basename(args.table), project=project)
            c = {}
            for it in data["items"].values():
                if it.get("kind") == "bug":
                    st = effective_status(data, it)
                    c[st] = c.get(st, 0) + 1
            gaps = sum(c.get(k, 0) for k in NO_REGRESSION_TEST)
            print(f"{'(dry-run) ' if args.dry_run else ''}{len(rows)} bug: +{counts['added']} mới, {counts['updated']} cập nhật · "
                  f"không có test hồi quy: {gaps} (chưa có test {c.get('NEEDS_TEST', 0)}, ngoài matrix {c.get('NOT_IN_MATRIX', 0)})"
                  f" · đã link chưa chạy lại {c.get('NOT_RUN', 0)} · chưa sửa {c.get('OPEN', 0)}")
            if not args.dry_run:
                save(project, data)
                print(f"✔ {render(project, data)}")
        elif args.cmd == "link":
            link(data, args.item_id, args.test_id)
            save(project, data)
            print(f"✔ Đã link {args.item_id} → {args.test_id}")
        elif args.cmd == "render":
            with locked(project):
                data = load(project)
                save(project, data)
            print(project / VIEW_FILE)
        else:
            print((project / VIEW_FILE).read_text(encoding="utf-8") if (project / VIEW_FILE).exists()
                  else "Chưa có checklist — chạy post-fix-gate --run-tests một lần.")
    except (KeyError, ValueError, OSError) as e:
        print(f"✖ {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
