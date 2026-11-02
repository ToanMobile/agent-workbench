"""#757 F2: every control on /cc-switcher is a web touch target >= 44x44 px, with >= 8 px between neighbouring controls.

Reads the <style> of web/cc-switcher.html (standard library only). Every rule that names a checked selector, inside
@media blocks too, must keep min-height (and min-width where asserted) >= 44 px; every container that lays out
several controls must keep each gap value >= 8 px.
"""
import os, re, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE = os.path.join(HERE, "web", "cc-switcher.html")

MIN_TARGET_PX = 44
MIN_GAP_PX = 8

# selector -> properties that must be >= 44 px
TARGETS = {
    ".btn": ("min-height", "min-width"),
    ".btn.sm": ("min-height",),
    ".seg button": ("min-height", "min-width"),
    "select": ("min-height",),
    ".field input": ("min-height",),
    ".custom input": ("min-height",),
    ".back": ("min-height",),
}
# flex/grid containers whose children include two or more buttons/selects/inputs
CONTROL_ROWS = (".seg", ".rp-assign", ".custom", ".actions", ".acc-actions", ".top .right", ".addform",
                "dialog .row", ".banner")


def style_text():
    with open(PAGE, encoding="utf-8") as f:
        html = f.read()
    m = re.search(r"<style>(.*?)</style>", html, re.S)
    if not m:
        raise AssertionError("no <style> block in cc-switcher.html")
    return re.sub(r"/\*.*?\*/", "", m.group(1), flags=re.S)


def rules(css):
    """(selector list, {property: value}) for every style rule, at any @media depth."""
    out, stack, start = [], [], 0
    for i, ch in enumerate(css):
        if ch == "{":
            stack.append((css[start:i].strip(), i + 1))
            start = i + 1
        elif ch == "}":
            head, body_start = stack.pop()
            body = css[body_start:i]
            if not head.startswith("@") and "{" not in body:
                decls = {}
                for part in body.split(";"):
                    if ":" in part:
                        k, v = part.split(":", 1)
                        decls[k.strip().lower()] = v.strip()
                out.append(([s.strip() for s in head.split(",")], decls))
            start = i + 1
    return out


def px_values(value):
    vals = re.findall(r"(-?\d+(?:\.\d+)?)px", value)
    return [float(v) for v in vals]


class CcSwitcherTouchTargets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rules = rules(style_text())

    def decls_for(self, selector, prop):
        return [d[prop] for sels, d in self.rules if selector in sels and prop in d]

    def test_controls_are_at_least_44px(self):
        for selector, props in TARGETS.items():
            for prop in props:
                with self.subTest(selector=selector, prop=prop):
                    values = self.decls_for(selector, prop)
                    self.assertTrue(values, f"{selector} declares no {prop}")
                    for v in values:
                        px = px_values(v)
                        self.assertTrue(px, f"{selector} {prop}: {v!r} is not in px")
                        self.assertGreaterEqual(min(px), MIN_TARGET_PX, f"{selector} {prop}: {v}")

    def test_neighbouring_controls_are_8px_apart(self):
        for selector in CONTROL_ROWS:
            with self.subTest(selector=selector):
                values = self.decls_for(selector, "gap")
                self.assertTrue(values, f"{selector} declares no gap")
                for v in values:
                    px = px_values(v)
                    self.assertTrue(px, f"{selector} gap: {v!r} is not in px")
                    self.assertGreaterEqual(min(px), MIN_GAP_PX, f"{selector} gap: {v}")


if __name__ == "__main__":
    unittest.main()
