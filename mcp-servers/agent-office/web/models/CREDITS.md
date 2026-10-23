# Model credits

Everything here is built in this repo with Blender 5.2 (headless), no third-party models:

| File | Built by | What |
|---|---|---|
| `chibi1.glb` ... `chibi5.glb` | `../blender/build_chibi.py` | Five chibi people (big head, big sparkly eyes, short limbs) with a skeleton and Idle and Walk clips. The page tints the `Shirt` material with the lane colour and poses the bones to sit or stand at a station. |
| `office.glb` | `../blender/build_office.py` | Desk, swivel chair, monitor, keyboard, mouse, mug, plant, card shelf. |
| `stations.glb` | `../blender/build_stations.py` | QAMatrix and ReviewCockpit, the standing stations of the QA and Review runner lanes. |

The helper functions of `build_office.py` are adapted from https://github.com/tinhthanh/vetgo-3d-demo/blob/main/blender/build_characters.py.
The earlier Quaternius people (CC0 1.0, from https://github.com/tinhthanh/vetgo-3d-demo/tree/main/models) were replaced by the chibi set and removed.
