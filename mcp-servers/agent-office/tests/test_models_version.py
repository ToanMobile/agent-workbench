"""Model GLB được trình duyệt giữ một ngày: URL phải mang mã phiên bản đổi theo file, nếu không dựng lại model vẫn hiện bản cũ."""
import os, re, sys, tempfile, time, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server  # noqa: E402


class ModelsVersionTest(unittest.TestCase):
    def test_every_model_load_carries_the_version(self):
        with open(os.path.join(HERE, "web", "index.html"), encoding="utf-8") as f:
            page = f.read()
        loads = re.findall(r"\.load\('models/[^)]*?,", page)
        self.assertTrue(loads)
        for ld in loads:
            self.assertIn("MODELS_V", ld, ld)
        self.assertIn("__MODELS_V__", page)

    def test_version_changes_when_a_model_is_rebuilt(self):
        with tempfile.TemporaryDirectory() as d:
            os.mkdir(os.path.join(d, "models"))
            p = os.path.join(d, "models", "a.glb")
            open(p, "wb").write(b"x")
            os.utime(p, (1000, 1000))
            v1 = server.models_version(d)
            os.utime(p, (2000, 2000))
            self.assertNotEqual(v1, server.models_version(d))

    def test_version_changes_when_a_model_is_replaced_keeping_its_mtime(self):
        with tempfile.TemporaryDirectory() as d:
            os.mkdir(os.path.join(d, "models"))
            p = os.path.join(d, "models", "a.glb")
            open(p, "wb").write(b"x")
            os.utime(p, (1000, 1000))
            v1 = server.models_version(d)
            open(p, "wb").write(b"xyz")  # cp -p / rsync -a from an older build: new bytes, old mtime
            os.utime(p, (1000, 1000))
            self.assertNotEqual(v1, server.models_version(d))

    def test_index_gets_the_version_filled_in(self):
        page = server.fill_models_version(b"const MODELS_V = '?v=__MODELS_V__';", "123")
        self.assertEqual(page, b"const MODELS_V = '?v=123';")


if __name__ == "__main__":
    unittest.main()
