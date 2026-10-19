#!/usr/bin/env python3
"""super-board-device-online.py — is a real device online for a `needs-device` QA card? (#95)

Exit 0 when `adb devices` lists a device in state `device` that is not an emulator (`emulator-*`: the label asks for real
hardware, and proof-capture leaves AVDs running) and not denylisted. Exit 1 otherwise, the reason on stderr.
Device listing and denylist (ADB_DENY_SERIALS, ~/.config/universal-agent-devkit/adb-denylist, <repo>/.adb-denylist) are the
DevKit's proof-capture.py rules, imported so the two never disagree; the DevKit is looked for as the merge gate does
(<repo>/universal-agent-devkit, <repo>/.agents/devkit, then the same two in the main checkout: .agents/devkit is a git-ignored
link a fresh worktree lacks). adb missing, hung (proof-capture's 8 s) or failing, or no DevKit: exit 1 — a card held for that
shows in "Waiting on you"; one dispatched without a device only parks in Blocked.
adb: $PROOF_ADB, else `adb` on PATH. ponytail: Android only (adb); an iPhone board needs `xcrun devicectl` here.

Usage: super-board-device-online.py [--repo <repo root>]
  Default: the checkout holding this script, so the runner, the planner and status (which pass none) read one denylist.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import subprocess
import sys
from pathlib import Path


def find_kit(repo: Path) -> Path | None:
    roots = [repo]
    try:
        out = subprocess.run(["git", "-C", str(repo), "worktree", "list", "--porcelain"],
                             capture_output=True, text=True, timeout=10, check=False).stdout
        if out.startswith("worktree "):
            roots.append(Path(out.splitlines()[0][len("worktree "):]))
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"main checkout unknown ({exc}); looking for the DevKit in {repo} only", file=sys.stderr)
    for root in roots:
        for kit in (root / "universal-agent-devkit", root / ".agents" / "devkit"):
            if (kit / "bin" / "proof-capture.py").is_file():
                return kit / "bin" / "proof-capture.py"
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=str(Path(__file__).absolute().parents[2]))
    repo = Path(parser.parse_args().repo)
    kit = find_kit(repo)
    try:
        if kit is None:
            raise FileNotFoundError("no universal-agent-devkit or .agents/devkit here or in the main checkout")
        spec = importlib.util.spec_from_file_location("sb_proof_capture", kit)
        pc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(pc)
        listing, deny = pc.adb_devices, pc.load_deny
    except Exception as exc:  # a missing or broken kit: no rules to tell a real device by
        print(f"cannot tell whether a real device is online: DevKit proof-capture.py unusable for {repo} ({exc})", file=sys.stderr)
        return 1
    adb = os.environ.get("PROOF_ADB") or "adb"
    try:
        devices = listing(adb)
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"no real device online: `{adb} devices` failed ({exc})", file=sys.stderr)
        return 1
    denied = deny(repo)
    # emulator-* and an AVD reached by `adb connect` over loopback are not hardware
    real = [d for d in devices
            if d["state"] == "device" and not d["serial"].startswith(("emulator-", "127.0.0.1:", "localhost:"))
            and d["serial"] not in denied]
    if real:
        print(f"{len(real)} real device(s) online")
        return 0
    print(f"no real device online ({len(devices)} listed by adb: offline, unauthorized, emulator or denylisted)", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
