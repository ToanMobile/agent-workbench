#!/usr/bin/env bash
# proof-capture.py: the emulator it boots runs HEADLESS (no window) by default; PROOF_WINDOW=1 brings the window back.
# Tests the pure command builder emulator_cmd() only: no emulator, no adb, no device is touched.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CMD="${PROOF_CAPTURE_CMD:-$DEVKIT_DIR/bin/proof-capture.py}"
python3 - "$CMD" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("pc", sys.argv[1])
pc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pc)
fails = []


def check(c, m):
    print(("✔ " if c else "✖ ") + m)
    if not c:
        fails.append(m)


def build(avd, window):
    if window is None:
        os.environ.pop("PROOF_WINDOW", None)
    else:
        os.environ["PROOF_WINDOW"] = window
    return pc.emulator_cmd("emu", avd, 5554)


d = build("PhoneConnect", None)
check("-no-window" in d and "-no-audio" in d, "default: headless, no audio")
check("-gpu" in d and d[d.index("-gpu") + 1] == "swiftshader_indirect", "default: software GPU")
check("-no-boot-anim" in d and d[:5] == ["emu", "-avd", "PhoneConnect", "-port", "5554"], "default: keeps base args")
w = build("PhoneConnect", "1")
check("-no-window" not in w and "-no-audio" not in w and "-gpu" not in w, "PROOF_WINDOW=1: window mode, no headless flags")
check("-no-window" not in build("PhoneConnect", "true"), "PROOF_WINDOW=true also means window")
check("-no-window" in build("PhoneConnect", "0") and "-no-window" in build("PhoneConnect", ""), "PROOF_WINDOW=0/empty stays headless")
c = build("CarConnect", None)
check("-no-window" in c and "-no-audio" not in c and "-allow-host-audio" in c and "-writable-system" in c,
      "CarConnect headless keeps its audio + writable-system flags")
check(c.count("-gpu") == 1, "CarConnect: exactly one -gpu")
cw = build("CarConnect", "1")
check("-no-window" not in cw and "-allow-host-audio" in cw, "CarConnect window mode unchanged")
check("-no-window" not in build("PhoneConnect", " On ") and "-no-window" in build("PhoneConnect", "off"), "PROOF_WINDOW is case/space tolerant")

# Wiring: boot_avd must launch the emulator with the built command (Popen and wait_boot faked: nothing starts).
launched = []
pc.subprocess.Popen = lambda argv, **kw: launched.append(argv)
pc.wait_boot = lambda *a, **k: True
os.environ.pop("PROOF_WINDOW", None)
pc.boot_avd("adb", "emu", "PhoneConnect", [], 5554, 1)
check(len(launched) == 1 and "-no-window" in launched[0], "boot_avd launches the headless command")
sys.exit(1 if fails else 0)
PY
