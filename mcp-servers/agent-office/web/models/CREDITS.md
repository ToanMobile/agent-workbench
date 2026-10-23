# Model credits

Five low-poly people with Idle and Walk clips (woman2 and woman3 also have Sit). Author Quaternius, licence CC0 1.0 (public domain).
Copied unchanged from https://github.com/tinhthanh/vetgo-3d-demo/tree/main/models (re-exported from Blender with the animation clips), originals from Poly Pizza.

| File | Title | Author | Licence | Source |
|---|---|---|---|---|
| man.glb | Casual Character | Quaternius | CC0 1.0 | https://poly.pizza/m/kZ3DmIoGip |
| woman.glb | Animated Woman | Quaternius | CC0 1.0 | https://poly.pizza/m/qJ2gsTUBHL |
| woman2.glb | Woman Casual | Quaternius | CC0 1.0 | https://poly.pizza/m/jpKRgGDxhk |
| woman3.glb | Woman in Dress | Quaternius | CC0 1.0 | https://poly.pizza/m/zMyPlQXBzq |
| beach.glb | Beach Character | Quaternius | CC0 1.0 | https://poly.pizza/m/DojKLcO34E |

`office.glb` (desk, swivel chair, monitor, keyboard, mouse, mug, plant, card shelf) is built in this repo by `../blender/build_office.py` (Blender 5.2, headless); its helper functions are adapted from https://github.com/tinhthanh/vetgo-3d-demo/blob/main/blender/build_characters.py.

`stations.glb` (QAMatrix and ReviewCockpit, the standing stations of the QA and Review lanes) is built by `../blender/build_stations.py` (Blender 5.2, headless), reusing the helpers of `build_office.py`. The page clones them for the QA and Review runner lanes. The people are the Quaternius models above with a chibi look applied in `index.html` (`CHIBI`: bigger head, shorter body).
