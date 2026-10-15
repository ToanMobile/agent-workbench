#!/usr/bin/env python3
"""capture_3d_proof.py — Visual 3D Proof Capture for Blender & Unity Game Scenes.

Renders or captures a verified proof PNG from a 3D asset or scene to satisfy the DevKit
acceptance gate (reports/proof-<stamp>.png, >= 8KB, valid PNG header, non-blank).

Usage:
    python3 scripts/capture_3d_proof.py --prop coin
    python3 scripts/capture_3d_proof.py --blend Art/Source/hero.blend
    python3 scripts/capture_3d_proof.py --image Assets/Art/Sprites/UI/coin_gold.png
"""

import sys
import os
import re
import time
import shutil
import argparse
import subprocess
from pathlib import Path

PNG_SIG = b"\x89PNG\r\n\x1a\n"
MIN_BYTES = 8192
MIN_DISTINCT_ROWS = 0.01


def is_valid_png(path: Path) -> bool:
    if not path.is_file():
        return False
    data = path.read_bytes()
    if len(data) < MIN_BYTES or not data.startswith(PNG_SIG):
        return False
    return True


def render_blender_prop(output_path: Path, prop: str, color: str = "gold", resolution: int = 512, blend: str = "") -> bool:
    blender_bin = shutil.which("blender")
    if not blender_bin:
        # Check standard macOS locations
        for mac_path in ["/Applications/Blender.app/Contents/MacOS/Blender",
                         os.path.expanduser("~/Applications/Blender.app/Contents/MacOS/Blender")]:
            if os.path.exists(mac_path):
                blender_bin = mac_path
                break

    devkit_dir = Path(__file__).resolve().parent.parent
    if not (devkit_dir / "profiles").is_dir() and (devkit_dir.parent / "profiles").is_dir():
        devkit_dir = devkit_dir.parent
    prop_script = devkit_dir / "profiles" / "game" / "scripts" / "render_game_prop.py"
    if not prop_script.is_file():
        prop_script = Path(__file__).resolve().parent / "render_game_prop.py"

    if blender_bin and prop_script.is_file():
        cmd = [
            blender_bin, "--disable-autoexec", "-b", "-P", str(prop_script), "--",   # a source may come from the web (AI asset): never run its scripts
            "--output", str(output_path),
            "--resolution", str(resolution),
        ]
        # a source replaces the built-in prop: --prop/--color would be dropped, so the script refuses them together
        cmd += ["--blend", blend] if blend else ["--prop", prop, "--color", color]
        output_path.unlink(missing_ok=True)   # a PNG left by an earlier run must never pass for this run's proof
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            if res.returncode == 0 and is_valid_png(output_path):
                return True
            print("Blender exit %s: %s" % (res.returncode, (res.stderr or res.stdout).strip()[-400:]), file=sys.stderr)
        except (subprocess.TimeoutExpired, OSError) as err:
            print("Blender run failed: %s" % err, file=sys.stderr)
    else:
        print("Blender or render_game_prop.py not found", file=sys.stderr)

    # No drawn stand-in: Blender 3D is the only source of a game asset or of its proof.
    return False


def main():
    parser = argparse.ArgumentParser(description="Capture 3D visual proof for Blender/Unity.")
    parser.add_argument("--project", default=".", help="Project directory")
    parser.add_argument("--output", help="Explicit output PNG path")
    parser.add_argument("--prop", choices=["coin", "gem", "chest", "trophy", "potion"], help="Prop type (default coin; not with --blend)")
    parser.add_argument("--color", help="Material color (default gold; not with --blend)")
    parser.add_argument("--blend", help="Render this .blend source instead of a built-in prop")
    parser.add_argument("--image", help="Existing rendered 3D asset image to copy as proof")
    args = parser.parse_args()

    project = Path(args.project).resolve()
    reports_dir = project / "reports"
    reports_dir.mkdir(parents=True, exist_ok=True)

    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = Path(args.output) if args.output else (reports_dir / f"proof-{stamp}.png")

    if args.image is not None:   # an explicit image is the proof or nothing: never a default asset rendered in its place
        src = Path(args.image)
        if is_valid_png(src):
            shutil.copyfile(src, dest)
            print(f"{dest} 3d-asset")
            sys.exit(0)
        print(f"Error: --image {src} is missing or not a valid PNG (>= {MIN_BYTES} bytes); no stand-in is rendered", file=sys.stderr)
        sys.exit(1)
    blend = args.blend
    if blend is not None and not blend:
        parser.error("--blend is empty")
    if blend and (args.prop or args.color):   # the wrapper cannot tell a typed value from a default, so the defaults live here
        parser.error("--prop and --color describe a built-in prop; they do not apply to --blend")
    prop, color = args.prop or "coin", args.color or "gold"
    if blend and not os.path.isabs(blend):
        blend = str(project / blend)   # relative to --project, not to wherever the tool runs

    success = render_blender_prop(dest, prop, color, blend=blend or "")
    if success and dest.is_file():
        print(f"{dest} blender-3d")
        sys.exit(0)
    else:
        print(f"Error: Khong the render anh 3D proof tai {dest}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
