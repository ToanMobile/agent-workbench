"""Bộ nội thất office.glb (dựng bằng blender/build_office.py) phải có đủ các khối mà trang nhân bản theo tên."""
import json, os, struct, unittest

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


if __name__ == "__main__":
    unittest.main()
