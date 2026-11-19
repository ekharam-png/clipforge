#!/usr/bin/env python3
# Tests of tool/ci/release_assets.py: the exact file list of a release, the
# three downloads on the page, and no link to a file that is not released.
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import release_assets as m  # noqa: E402
import make_latest_json  # noqa: E402


class ReleaseAssets(unittest.TestCase):
    def test_the_list(self):
        self.assertEqual(m.DOWNLOADS, ["ClipForge-Setup.exe", "ClipForge-macos.zip",
                                       "ClipForge-android.apk"])
        self.assertEqual(sorted(m.ASSETS), sorted(m.DOWNLOADS + ["ClipForge-windows.zip",
                                                                 "latest.json"]))
        # Everything latest.json names is released, and no 32-bit phone file.
        for name in make_latest_json.FILES.values():
            self.assertIn(name, m.ASSETS)
        self.assertEqual(sorted(make_latest_json.FILES), ["android", "macos", "windows"])

    def test_the_folder_must_hold_exactly_the_list(self):
        with tempfile.TemporaryDirectory() as d:
            for name in m.ASSETS:
                open(os.path.join(d, name), "w").close()
            self.assertEqual(m.check_dir(d), [])
            open(os.path.join(d, "ClipForge-1.15.0-build200-windows.zip"), "w").close()
            self.assertEqual(len(m.check_dir(d)), 1, "an extra (versioned) file")
            os.remove(os.path.join(d, "ClipForge-1.15.0-build200-windows.zip"))
            os.remove(os.path.join(d, "ClipForge-Setup.exe"))
            self.assertEqual(len(m.check_dir(d)), 1, "a missing file")

    def test_the_real_page_and_every_link(self):
        if not os.path.exists(os.path.join(m.REPO, "site", "index.html")):
            self.skipTest("not inside the repository")
        self.assertEqual(m.check_links(), [])

    def test_a_fourth_download_or_a_removed_file_is_noticed(self):
        base = "https://github.com/example/clipforge/releases/latest/download/"
        with tempfile.TemporaryDirectory() as d:
            page = os.path.join(d, "index.html")
            with open(page, "w", encoding="utf-8") as f:
                f.write("".join('<a href="%s%s">x</a>' % (base, n) for n in m.DOWNLOADS))
            self.assertEqual([p for p in m.check_links(page) if "index.html must" in p], [])
            with open(page, "a", encoding="utf-8") as f:
                f.write('<a href="%sClipForge-windows.zip">zip</a>' % base)
            self.assertEqual(len([p for p in m.check_links(page) if "index.html must" in p]), 1)
        self.assertEqual(m.LINK.findall(base + "ClipForge-android-old-32bit-phones.apk"),
                         ["ClipForge-android-old-32bit-phones.apk"])
        self.assertNotIn("ClipForge-android-old-32bit-phones.apk", m.ASSETS)


if __name__ == "__main__":
    unittest.main(verbosity=2)
