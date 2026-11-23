import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
STUDIO_HTML = os.path.join(os.path.dirname(HERE), "web", "studio.html")


class TestStudioUiStandards(unittest.TestCase):
    def test_studio_html_exists_and_is_self_contained(self):
        self.assertTrue(os.path.isfile(STUDIO_HTML), "web/studio.html must exist")
        with open(STUDIO_HTML, encoding="utf-8") as f:
            html = f.read()
        # No Antigravity or external Tailwind CDN
        self.assertNotIn("gstatic.com/antigravity", html)
        self.assertNotIn("cdn.tailwindcss.com", html)
        # Must define self-contained Light + Dark semantic tokens & Telegram theme bridge
        self.assertIn(":root", html)
        self.assertIn('[data-theme="dark"]', html)
        self.assertIn("viewport-fit=cover", html)
        self.assertIn("safe-area-inset-bottom", html)
        self.assertIn("visualViewport", html)
        self.assertIn("prefers-reduced-motion", html)

    def test_studio_zero_inline_handlers_and_uses_native_dialog(self):
        with open(STUDIO_HTML, encoding="utf-8") as f:
            html = f.read()
        # Zero inline onclick/onchange attributes (prevents XSS & draft-wiping patterns)
        self.assertIsNone(re.search(r'\bon(?:click|change|input|submit)\s*=', html, re.I))
        # Must use native <dialog> for accessible modals
        self.assertIn("<dialog", html)
        self.assertIn("showModal", html)

    def test_studio_ergonomics_44px_targets_8px_gaps_16px_mobile_inputs(self):
        with open(STUDIO_HTML, encoding="utf-8") as f:
            html = f.read()
        self.assertIn("min-height: 44px", html)
        self.assertIn("min-width: 44px", html)
        self.assertIn("font-size: 16px", html)
        # Must include auth headers & real CC-Switcher fields
        self.assertIn("X-AAF-Studio", html)
        self.assertIn("X-Telegram-Init-Data", html)
        self.assertIn("X-AAF-Session", html)
        self.assertIn("needsForce", html)
        self.assertIn("repoAssignments", html)
        self.assertIn("allowOAuthLogin", html)


if __name__ == "__main__":
    unittest.main()
