#!/usr/bin/env python3
# Tests for tool/ci/links.json (THE one place for ClipForge's outside
# addresses), tool/ci/links.py and what make_latest_json.py writes from
# them. Run: python3 tool/ci/links_test.py
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import links as m  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
FILES = {"ClipForge-windows.zip": b"w" * 10, "ClipForge-macos.zip": b"m" * 20, "ClipForge-android.apk": b"a" * 30}


def make_latest(extra, links=None):
    with tempfile.TemporaryDirectory() as d:
        for name, data in FILES.items():
            with open(os.path.join(d, name), "wb") as f:
                f.write(data)
        if links is not None:
            path = os.path.join(d, "links-test.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(links, f)
            extra = extra + ["--links", path]
        run = subprocess.run(
            [sys.executable, os.path.join(HERE, "make_latest_json.py"), "--dir", d, "--version", "1.16.0",
             "--build", "160", "--tag", "v1.16.0", "--base-url", "https://github.com/example/app",
             "--date", "2026-11-20T10:00:00Z"] + extra,
            capture_output=True, text=True)
        out = os.path.join(d, "latest.json")
        text = None
        if os.path.exists(out) and run.returncode == 0:
            with open(out, encoding="utf-8") as f:
                text = f.read()
        return run, json.loads(text) if text else None


class LinksTest(unittest.TestCase):
    def test_the_file_is_complete_and_passes_the_apps_rules(self):
        data = m.load()
        self.assertEqual(m.problems(data), [])
        self.assertEqual(sorted(data["full"]), sorted(m.NAMES))
        site = data["full"]["site"]
        self.assertFalse(site.endswith("/"))
        for name in m.NAMES:
            self.assertTrue(data["full"][name].startswith(site), name)
        self.assertTrue(data["old_pages"].endswith("/"))

    def test_what_is_wrong_is_said(self):
        base = {"site": "https://example.org", "claude_page": "/claude",
                "links": {"download": "/install", "feedback_api": "/api/feedback",
                          "feedback_page": "/feedback", "help": "/help", "privacy": "/privacy"},
                "feedback_api_hosts": [], "repository": "https://github.com/example/app",
                "old_pages": "https://example.github.io/app/"}

        def problems(change):
            data = json.loads(json.dumps(base))
            change(data)
            with tempfile.TemporaryDirectory() as d:
                path = os.path.join(d, "l.json")
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(data, f)
                return m.problems(m.load(path))

        self.assertEqual(problems(lambda d: None), [])
        self.assertTrue(problems(lambda d: d.update(site="http://example.org")))
        self.assertTrue(problems(lambda d: d["links"].update(feedback_api="https://elsewhere.example/api")))
        self.assertEqual(problems(lambda d: (d["links"].update(feedback_api="https://elsewhere.example/api"),
                                             d.update(feedback_api_hosts=["elsewhere.example"]))), [])
        self.assertTrue(problems(lambda d: d["links"].pop("privacy")))
        self.assertTrue(problems(lambda d: d["links"].update(help="https://user@example.org/help")))
        self.assertTrue(problems(lambda d: d["links"].update(help="https://example.org/" + "h" * 200)))

    def test_latest_json_carries_the_links_and_keeps_the_old_fields(self):
        run, latest = make_latest([])
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(latest["links"], m.latest_links())
        self.assertEqual(list(latest["links"]), m.NAMES)
        self.assertEqual([latest["version"], latest["build"], latest["date"], latest["notes_url"]],
                         ["1.16.0", 160, "2026-11-20T10:00:00Z", "https://github.com/example/app/releases/tag/v1.16.0"])
        self.assertEqual(sorted(latest["platforms"]), ["android", "macos", "windows"])
        win = latest["platforms"]["windows"]
        self.assertEqual(win["sha256"], hashlib.sha256(FILES["ClipForge-windows.zip"]).hexdigest())
        self.assertEqual(win["size"], 10)

    def test_no_links_and_bad_links(self):
        run, latest = make_latest(["--no-links"])
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertNotIn("links", latest)
        # A links.json the app would refuse stops the release.
        run, latest = make_latest([], links={
            "site": "https://example.org", "claude_page": "/claude",
            "links": {"download": "/install", "feedback_api": "https://elsewhere.example/api",
                      "feedback_page": "/feedback", "help": "/help", "privacy": "/privacy"},
            "repository": "https://github.com/example/app", "old_pages": "https://example.github.io/app/"})
        self.assertNotEqual(run.returncode, 0)
        self.assertIsNone(latest)
        self.assertIn("feedback_api", run.stderr)

    def test_the_old_pages_signpost_points_at_the_site(self):
        index = os.path.join(REPO, "site", "index.html")
        if not os.path.exists(index):
            self.skipTest("not inside the repository")
        data = m.load()
        with open(index, encoding="utf-8") as f:
            page = f.read()
        site = data["full"]["site"]
        self.assertIn('href="%s/"' % site, page)
        self.assertIn('href="%s"' % data["full"]["download"], page)
        # Every address on the page is the site, the repository, or a page next to it.
        for href in re.findall(r'href="([^"]+)"', page):
            self.assertTrue(href.startswith(site + "/") or href.startswith(data["repository"])
                            or href == "claude-setup.html", href)
        self.assertNotIn("http-equiv", page)  # no automatic redirect: the downloads stay usable
        # Old versions of the app link to the Claude page next to it.
        self.assertTrue(os.path.exists(os.path.join(REPO, "site", "claude-setup.html")))

    def test_the_read_me_uses_the_same_addresses(self):
        import make_readme_html as readme
        data = m.load()
        self.assertEqual(readme.DOWNLOAD_PAGE, data["full"]["download"])
        self.assertEqual(readme.HELP_ONLINE, data["full"]["help"])
        self.assertEqual(readme.SOURCE, data["repository"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
