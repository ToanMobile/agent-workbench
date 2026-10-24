# Model credits

Everything here is built in this repo with Blender 5.2 (headless), no third-party models:

| File | Built by | What |
|---|---|---|
| `chibi_girl.glb`, `chibi_boy.glb` | `../blender/build_chibi.py` | The QC chibi girl (twin tails, curly ahoge, star clip, big blue eyes, mint puff-sleeve shirt, pink skirt) and a matching boy, with a skeleton and Idle and Walk clips. The page shades them with a toon ramp and an outline, tints `Shirt` with the lane colour and `Hair` per agent. |
| `office.glb` | `../blender/build_office.py` | Desk, swivel chair, monitor, keyboard, mouse, mug, plant, card shelf. |
| `stations.glb` | `../blender/build_stations.py` | QAMatrix and ReviewCockpit, the standing stations of the QA and Review runner lanes. |

The helper functions of `build_office.py` are adapted from https://github.com/tinhthanh/vetgo-3d-demo/blob/main/blender/build_characters.py.
The earlier Quaternius people (CC0 1.0, from https://github.com/tinhthanh/vetgo-3d-demo/tree/main/models) were replaced by the chibi set and removed.
