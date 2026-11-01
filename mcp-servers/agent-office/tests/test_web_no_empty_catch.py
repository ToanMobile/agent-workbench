"""#742 review 409a7296, BUG-REV fc1b157568 (INSTINCT-007): no page under web/ swallows an error in an empty catch block.

The registry scan of INSTINCT-007 does not read .html, so web/cc-switcher.html shipped `catch (e) {}` around localStorage
(private mode, quota): a storage failure left no trace. Every inline script of every page is checked with INSTINCT-007's own
detect pattern, plus the optional-binding form `catch {}`. Standard library only.
"""
import glob, os, re, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EMPTY_CATCH = re.compile(r"catch\s*\([^)]*\)\s*\{\s*\}|catch\s*\{\s*\}")


class WebNoEmptyCatch(unittest.TestCase):
    def test_pages_exist(self):
        names = {os.path.basename(p) for p in glob.glob(os.path.join(HERE, "web", "*.html"))}
        self.assertTrue({"index.html", "cc-switcher.html"} <= names, names)

    def test_no_empty_catch(self):
        hits = []
        for page in sorted(glob.glob(os.path.join(HERE, "web", "*.html"))):
            with open(page, encoding="utf-8") as fh:
                text = fh.read()
            for m in EMPTY_CATCH.finditer(text):   # the whole file: a `catch (e) {` + `}` on the next line is empty too
                hits.append(f"{os.path.basename(page)}:{text.count(chr(10), 0, m.start()) + 1}: {m.group(0)[:120]}")
        self.assertEqual(hits, [], "empty catch blocks (log the error or show it):\n" + "\n".join(hits))


if __name__ == "__main__":
    unittest.main()
