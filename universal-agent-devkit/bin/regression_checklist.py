#!/usr/bin/env python3
"""
regression_checklist.py — Living regression checklist (features + bugs → tests → last result).

One place to see, across tasks, which features and fixed bugs are covered by which
regression test and whether that test last PASSED or FAILED, when, in which task
and on which commit.

  .agents/regression_status.json   source of truth (machine-written)
  .agents/regression_checklist.md  human view, regenerated from the JSON

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

100% standard library.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path

STATUS_FILE = Path(".agents") / "regression_status.json"
VIEW_FILE = Path(".agents") / "regression_checklist.md"
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
}
# Bug states that mean "nothing guards this bug from coming back".
NO_REGRESSION_TEST = ("NEEDS_TEST", "NOT_IN_MATRIX")


def _now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def load(project_dir: Path) -> dict:
    path = Path(project_dir) / STATUS_FILE
    if not path.exists():
        return {"version": 1, "items": {}}
    with open(path, encoding="utf-8") as f:
        data = json.load(f)  # a corrupt file is an error, never silently reset to empty
    if not isinstance(data, dict) or not isinstance(data.get("items"), dict):
        raise ValueError(f"{path} không đúng định dạng checklist")
    return data


def save(project_dir: Path, data: dict) -> Path:
    path = Path(project_dir) / STATUS_FILE
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".regression_status.")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
    render(project_dir, data)
    return path


def _slug(text: str, max_len: int = 40) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return (s[:max_len].rstrip("-")) or "bug"


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
                  "duration": t.get("duration"), "exit_code": t.get("exit_code")}
        item["last"] = result
        item["history"] = ([result] + item.get("history", []))[:HISTORY_LIMIT]
        item.pop("impacted_at", None)


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


def add_bug(data: dict, title: str, *, cause: str | None, task: str | None, test_ids: list) -> str:
    """A fixed bug. Linked to the regression test(s) the gate just ran green for it, if any."""
    bid = f"BUG-{time.strftime('%Y%m%d')}-{_slug(title)}"
    n = 2
    while bid in data["items"]:
        bid = f"BUG-{time.strftime('%Y%m%d')}-{_slug(title)}-{n}"
        n += 1
    data["items"][bid] = {"id": bid, "kind": "bug", "title": title, "cause": cause, "component": "-",
                          "created_at": _now(), "task": task, "tests": list(test_ids),
                          "last": None, "history": []}
    return bid


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


TSV_COLUMNS = ("bug_id", "title", "severity", "fixed", "module", "test_id", "evidence")


def parse_bug_table(text: str) -> list:
    """Rows of a bug table: tab- or `|`-separated, columns
    bug_id | title | severity | fixed? | module | test_id_or_NONE | evidence
    (a header row and blank/# lines are skipped; several test ids split on , or ;)."""
    rows = []
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        cells = [c.strip() for c in (line.split("\t") if "\t" in line else line.strip().strip("|").split("|"))]
        if len(cells) < 2 or cells[0].lower() in ("bug_id", "id") or set(cells[0]) <= set("-: "):
            continue
        cells += [""] * (len(TSV_COLUMNS) - len(cells))
        row = dict(zip(TSV_COLUMNS, cells[:len(TSV_COLUMNS)]))
        tid = row["test_id"]
        row["tests"] = [] if tid.upper() in ("", "NONE", "-", "N/A") else \
            [t.strip() for t in tid.replace(";", ",").split(",") if t.strip()]
        row["fixed"] = row["fixed"].strip().lower() not in ("no", "n", "false", "0", "open", "không", "chưa")
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
    import subprocess
    name = ref.split("#")[0].split("::")[0].strip()
    if "/" in name:
        paths = [name] if (project / name).exists() else []
    else:
        cls = name.split(".")[-1] if not name.endswith((".kt", ".java", ".cs", ".swift", ".ts", ".py")) else name.rsplit(".", 1)[0].split(".")[-1]
        out = subprocess.run(["git", "-C", str(project), "ls-files", f"*/{cls}.*", f"{cls}.*"],
                             capture_output=True, text=True).stdout.split()
        paths = [x for x in out if x.rsplit("/", 1)[-1].split(".")[0] == cls]
    ids = []
    for path in paths:
        for tid, item in data["items"].items():
            if item.get("kind") != "test":
                continue
            watched = any(fnmatch.fnmatch(path, pat) for pat in item.get("watch_files", []))
            if watched and _runs_source_set(path, item.get("command"), project) and tid not in ids:
                ids.append(tid)
    return sorted(ids)


def import_bugs(data: dict, rows: list, *, source: str, project: Path = None) -> dict:
    """Past bugs as kind=bug rows. Never a result: a test id of the matrix is linked and
    shows "not re-run" until a real gate run after the import; a test outside the matrix
    (the gate never runs it) and no test at all are both gaps. Re-importing updates the
    description and links; results and history are never touched."""
    counts = {"added": 0, "updated": 0}
    for row in rows:
        bid = row["bug_id"] if row["bug_id"].upper().startswith("BUG") else f"BUG-{row['bug_id']}"
        in_matrix, outside, refs = [], [], []
        for t in row["tests"]:
            ids = resolve_test_ref(project, t, data) if project else \
                ([t] if (data["items"].get(t) or {}).get("kind") == "test" else [])
            if ids:
                in_matrix += [i for i in ids if i not in in_matrix]
                if ids != [t]:
                    refs.append(t)        # a class/file the linked suite runs: kept for display
            else:
                outside.append(t)
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
    if kind == "bug":
        if item.get("fixed") is False:
            return "OPEN"
        tests = [data["items"].get(t) for t in item.get("tests", [])]
        tests = [t for t in tests if t]
        if not tests:
            return "NOT_IN_MATRIX" if item.get("test_refs") else "NEEDS_TEST"
        linked = item.get("linked_ts")
        if linked and not any(((t.get("last") or {}).get("ts") or 0) > linked for t in tests):
            return "NOT_RUN"     # linked to a matrix test that has not run since
        states = [effective_status(data, t) for t in tests]
        for bad in ("FAIL", "TIMEOUT", "NOT_RUN"):
            if bad in states:
                return bad
        return "PASS"
    return (item.get("last") or {}).get("status") or "NOT_RUN"


def summary(data: dict) -> dict:
    counts: dict = {}
    for item in data["items"].values():
        st = effective_status(data, item)
        counts[st] = counts.get(st, 0) + 1
    return counts


def _cell(text) -> str:
    return str(text if text not in (None, "") else "-").replace("|", "\\|").replace("\n", " ")


def render(project_dir: Path, data: dict) -> Path:
    order = {"FAIL": 0, "TIMEOUT": 0, "OPEN": 1, "UNCOVERED": 1, "NEEDS_TEST": 1, "NOT_IN_MATRIX": 1, "NOT_RUN": 2, "PASS": 3}
    rows = sorted(data["items"].values(), key=lambda i: (order.get(effective_status(data, i), 9), i["id"]))
    c = summary(data)
    lines = [
        "# 🧪 Regression Checklist",
        "",
        "> Tự sinh bởi `post-fix-gate --run-tests` — **không sửa tay** (sửa sẽ bị ghi đè).",
        "> PASS/FAIL chỉ đến từ lần gate chạy test thật. Link bug / file chưa có test vào test id:",
        "> `python3 bin/regression_checklist.py link <ID> <TEST-ID>`",
        "",
        f"**Cập nhật:** {_now()} · ✅ {c.get('PASS', 0)} · ❌ {c.get('FAIL', 0) + c.get('TIMEOUT', 0)}"
        f" · ⚠️ {c.get('UNCOVERED', 0) + c.get('NEEDS_TEST', 0) + c.get('NOT_IN_MATRIX', 0)} · ⏳ {c.get('NOT_RUN', 0)}"
        + (f" · 🐞 {c.get('OPEN')} chưa sửa" if c.get("OPEN") else ""),
        "",
        f"**Bug không có test hồi quy nào chặn tái phát: {sum(c.get(k, 0) for k in NO_REGRESSION_TEST)}**"
        f" ({c.get('NEEDS_TEST', 0)} chưa có test · {c.get('NOT_IN_MATRIX', 0)} có test nhưng gate không chạy)",
        "",
        "| Trạng thái | ID | Tính năng / Bug | Component | Lần chạy gần nhất | Task | Commit | Test |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for item in rows:
        st = effective_status(data, item)
        last = item.get("last") or {}
        if item.get("kind") == "bug":
            tests = ", ".join(item.get("tests", []) + [f"{r} (trong suite)" for r in item.get("runs_in_suite", [])]
                              + [f"{r} (ngoài matrix)" for r in item.get("test_refs", [])]) or "chưa link"
            last_ts = max((((data["items"].get(t) or {}).get("last") or {}).get("at", "") for t in item.get("tests", [])), default="")
        else:
            tests = item.get("command") or ("chưa có — cần gắn test" if item.get("kind") == "uncovered" else "-")
            last_ts = last.get("at", "")
        lines.append("| " + " | ".join(_cell(x) for x in (
            ICON.get(st, st), item["id"], item.get("title"), item.get("component"),
            last_ts, last.get("task") or item.get("task"), last.get("commit"), tests)) + " |")
    lines.append("")
    path = Path(project_dir) / VIEW_FILE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


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
    args = parser.parse_args(argv)
    project = Path(args.project)
    try:
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
            print(render(project, data))
        else:
            print((project / VIEW_FILE).read_text(encoding="utf-8") if (project / VIEW_FILE).exists()
                  else "Chưa có checklist — chạy post-fix-gate --run-tests một lần.")
    except (KeyError, ValueError, OSError) as e:
        print(f"✖ {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
