"""Bộ nội thất office.glb (dựng bằng blender/build_office.py) phải có đủ các khối mà trang nhân bản theo tên."""
import json, os, re, struct, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GLB = os.environ.get("OFFICE_GLB") or os.path.join(HERE, "web", "models", "office.glb")  # biến môi trường: chạy thử trên file khác để thấy test bắt lỗi
NEEDED = {"Desk", "Chair", "Keyboard", "Mouse", "Mug", "Plant", "Monitor", "Shelf"}


def glb_json(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"glTF":
        raise ValueError("không phải glb")
    length, kind = struct.unpack("<II", data[12:20])
    if kind != 0x4E4F534A:  # 'JSON'
        raise ValueError("chunk đầu không phải JSON")
    return json.loads(data[20:20 + length])


class OfficeGlbTest(unittest.TestCase):
    def test_named_roots_and_screen(self):
        j = glb_json(GLB)
        roots = {j["nodes"][i].get("name") for i in j["scenes"][0]["nodes"]}
        self.assertTrue(NEEDED <= roots, NEEDED - roots)
        monitor = next(n for n in j["nodes"] if n.get("name") == "Monitor")
        kids = {j["nodes"][c].get("name") for c in monitor.get("children", [])}
        self.assertIn("Screen", kids)  # trang gắn màn hình canvas vào lưới tên Screen
        screen = next(n for n in j["nodes"] if n.get("name") == "Screen")
        prim = j["meshes"][screen["mesh"]]["primitives"][0]
        self.assertIn("TEXCOORD_0", prim["attributes"])  # cần UV để hiện nội dung màn hình

    def test_small_enough(self):
        self.assertLess(os.path.getsize(GLB), 400_000)


class StationsGlbTest(unittest.TestCase):
    """Trang dựng trạm đứng của lane QA và Review bằng cách nhân bản khối theo tên trong stations.glb."""
    def test_every_station_the_page_uses_exists(self):
        j = glb_json(os.path.join(HERE, "web", "models", "stations.glb"))
        roots = {j["nodes"][i].get("name") for i in j["scenes"][0]["nodes"]}
        with open(os.path.join(HERE, "web", "index.html"), encoding="utf-8") as f:
            page = f.read()
        used = set(re.findall(r"station: '(\w+)'", page))
        self.assertEqual(used, {"QAMatrix", "ReviewCockpit"})
        self.assertTrue(used <= roots, used - roots)


class ChibiGlbTest(unittest.TestCase):
    """Mã tư thế ngồi/đứng của trang tìm xương theo tên và lấy chiều cao từ Head_end: mọi người chibi phải giữ đúng hợp đồng đó."""
    BONES = {"Hips", "Head", "Head_end", "UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R", "Foot.L", "Foot.R",
             "UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R", "Hand.L", "Hand.R"}

    def test_every_person_the_page_loads_is_rigged(self):
        with open(os.path.join(HERE, "web", "index.html"), encoding="utf-8") as f:
            page = f.read()
        chars = page[page.index("const CHARS = ["):]
        files = re.findall(r"file: '([\w.]+\.glb)'", chars[:chars.index("];")])
        self.assertEqual(files, ["chibi_girl.glb", "chibi_boy.glb"])
        for name in files:
            path = os.path.join(HERE, "web", "models", name)
            j = glb_json(path)
            nodes = {n.get("name") for n in j["nodes"]}
            self.assertTrue(self.BONES <= nodes, (name, self.BONES - nodes))
            self.assertEqual({a["name"].lower() for a in j["animations"]}, {"idle", "walk"})
            mats = [m["name"] for m in j["materials"]]
            self.assertTrue(any(m.startswith("Shirt") for m in mats) and any(m.startswith("Hair") for m in mats), (name, mats))
            self.assertLess(os.path.getsize(path), 800_000)  # hai người cộng lại vẫn nhẹ hơn bộ Quaternius cũ (khoảng 3,3 MB)

if __name__ == "__main__":
    unittest.main()
