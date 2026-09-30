#!/usr/bin/env python3
"""Run Unity Test Framework tests headless and report them (Unity 2021+ / Unity 6).

    run_unity_tests.py [--platform editmode|playmode] [--project .] [--output reports/unity-test-results.xml]

Runs profiles/game/scripts/unity-batch.sh (Editor lock guard, PlayerPrefs restore, timeout)
with -batchmode -nographics -runTests, copies the NUnit 3 XML to --output and the Editor log
to <output dir>/unity_test.log, then prints the totals and each failed test with its message.

Editor: UNITY_PATH, else /Applications/Unity/Hub/Editor/<m_EditorVersion>/... from
ProjectSettings/ProjectVersion.txt, else unity-batch.sh looks in the Hub secondary install path.
Another Editor version is never used: opening a project with it in batchmode upgrades the project.

Exit: 0 = every test passed · 1 = a test failed · 2 = compile error, no results, no Editor.
ponytail: "compile error" = the unity-batch.sh regex over the whole Editor log, so a test that
logs "error CS1234" also exits 2; scope the scan to the pre-test part of the log in both files
if that happens.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

HUB_ROOT = Path("/Applications/Unity/Hub/Editor")
EDITOR_IN_HUB = Path("Unity.app/Contents/MacOS/Unity")
BATCH = Path(__file__).resolve().parent.parent / "profiles" / "game" / "scripts" / "unity-batch.sh"
COMPILE_ERROR = re.compile(r"error CS\d+|Scripts have compiler errors|Shader error in")


def installed_editors(hub_root: Path) -> dict:
    return {p.parent.parent.parent.parent.name: p for p in hub_root.glob("*/" + str(EDITOR_IN_HUB)) if os.access(p, os.X_OK)}


def project_version(project: Path) -> str | None:
    try:
        text = (project / "ProjectSettings" / "ProjectVersion.txt").read_text(encoding="utf-8")
    except OSError:
        return None
    m = re.search(r"^m_EditorVersion:\s*(\S+)", text, re.M)
    return m.group(1) if m else None


def find_editor(project: Path, hub_root: Path = HUB_ROOT, env=os.environ) -> str | None:
    if env.get("UNITY_PATH"):
        return env["UNITY_PATH"]
    hit = installed_editors(hub_root).get(project_version(project) or "")
    return str(hit) if hit else None


def test_cases(xml: Path) -> list | None:
    """<test-case> elements of an NUnit 3 result file; None when it is missing or unreadable."""
    try:
        return list(ET.parse(xml).getroot().iter("test-case"))
    except (OSError, ET.ParseError):
        return None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Run Unity EditMode/PlayMode tests headless.")
    ap.add_argument("--platform", choices=("editmode", "playmode"), default="editmode")
    ap.add_argument("--project", default=".")
    ap.add_argument("--output", default="reports/unity-test-results.xml")
    args = ap.parse_args(argv)
    project = Path(args.project).resolve()
    output = Path(args.output).resolve()
    log = output.parent / "unity_test.log"
    platform = "PlayMode" if args.platform == "playmode" else "EditMode"
    output.parent.mkdir(parents=True, exist_ok=True)

    env = dict(os.environ, UNITY_PROJECT=str(project), UNITY_NOGRAPHICS="1")
    editor = find_editor(project)
    if editor:
        env["UNITY_PATH"] = editor
    with tempfile.TemporaryDirectory(prefix="unity-tests-") as out:
        env["UNITY_BATCH_OUT"] = out
        res = subprocess.run(["bash", str(BATCH), args.platform], env=env, capture_output=True, text=True)
        batch_out = (res.stdout or "") + (res.stderr or "")
        tmp_xml, tmp_log = Path(out) / ("tests_%s.xml" % platform), Path(out) / ("tests_%s.log" % platform)
        if tmp_log.is_file():
            shutil.copyfile(tmp_log, log)
        else:
            log.unlink(missing_ok=True)  # an earlier run's log is not this run's log
        if tmp_xml.is_file():
            shutil.copyfile(tmp_xml, output)
        else:
            output.unlink(missing_ok=True)  # a result file from an earlier run is not this run's result

    if res.returncode == 2:
        print(batch_out.strip(), file=sys.stderr)
        found = ", ".join(sorted(installed_editors(HUB_ROOT))) or "(none)"
        print("UNTESTED: project Editor %s; installed under %s: %s" % (project_version(project), HUB_ROOT, found), file=sys.stderr)
        return 2
    errors = [ln for ln in (log.read_text(encoding="utf-8", errors="replace").splitlines() if log.is_file() else [])
              if COMPILE_ERROR.search(ln)]
    if errors:
        print("COMPILE ERROR (%s):" % log, file=sys.stderr)
        print("\n".join(errors[:40]), file=sys.stderr)
        return 2
    cases = test_cases(output)
    if not cases:
        print(batch_out.strip(), file=sys.stderr)
        print("RUN ERROR: %s has no test results (log: %s)" % (output, log), file=sys.stderr)
        return 2
    failed = [c for c in cases if c.get("result") == "Failed"]
    passed = sum(1 for c in cases if c.get("result") == "Passed")
    print("Unity %s: total %d, passed %d, failed %d, skipped %d — %s" % (
        platform, len(cases), passed, len(failed), len(cases) - passed - len(failed), output))
    for case in failed:
        print("  FAILED %s\n    %s" % (case.get("fullname"),
                                       (case.findtext("failure/message") or "").strip().replace("\n", "\n    ")))
    if failed:
        return 1
    if res.returncode != 0:
        print(batch_out.strip(), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
