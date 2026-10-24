"""Menu "Điện thoại": mở hộp thoại phải hiện chữ chờ ngay, không để vùng QR trống lúc /api/phone còn chậm."""
import os, re, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class PhoneLoading(unittest.TestCase):
    def test_open_shows_waiting_text_before_fetch(self):
        with open(os.path.join(HERE, "web", "index.html"), encoding="utf-8") as f:
            html = f.read()
        m = re.search(r"\$\('#btnPhone'\)\.onclick = \(\) => \{(.*?)\};\n", html, re.S)
        self.assertIsNotNone(m, "không thấy handler #btnPhone")
        body = m.group(1)
        wait = body.find("Đang lấy mã")
        self.assertGreaterEqual(wait, 0, "handler không đặt chữ chờ")
        self.assertLess(wait, body.find("loadPhone(false)"), "chữ chờ phải đặt trước khi gọi loadPhone")
        self.assertIn("#phoneUrl", body[:body.find("loadPhone(false)")], "phải xoá #phoneUrl cũ")


if __name__ == "__main__":
    unittest.main()
