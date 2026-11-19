#!/usr/bin/env python3
# Checks tool/ci/make_readme_html.py ("Read me first.html" in the Windows
# and macOS downloads). Run by the "Analyze and test" job:
#
#   python3 tool/ci/make_readme_html_test.py
#
# Standard library only.
import os
import re
import sys
import tempfile
import unittest
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_readme_html as m  # noqa: E402

SAMPLE = """# What's new

Intro text that belongs to no version.

## 9.9.9 – 1 January 2030

A first paragraph with <script>alert(1)</script> & an <img src=x onerror=y>.

- **Bold label** and `inline <code>` and a [link](https://example.org/a?b=1&c=2).
  - A nested item with a [bad link](javascript:alert(1)) and "quotes".
  - Another nested one.
- Second item
  wrapped onto a second line.

### A sub heading <b>

1. Numbered one
2. Numbered two

## 9.9.8 – 31 December 2029

- Older A

## 9.9.7 – 30 December 2029

- Older B

## 9.9.6 – 29 December 2029

- Older C

## 9.9.5 – 28 December 2029

- Too old to show
"""

VOID = {"meta", "br", "hr", "img", "link", "input"}


class Checker(HTMLParser):
    """Tag balance, and every address a tag would load by itself."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.problems = []
        self.tags = []
        self.loads = []        # (tag, attribute, value) the browser would fetch
        self.links = []
        self.text = []

    def handle_starttag(self, tag, attrs):
        self.tags.append(tag)
        a = dict(attrs)
        for name in ("src", "srcset", "poster", "data", "action", "background"):
            if a.get(name):
                self.loads.append((tag, name, a[name]))
        if tag == "link" and a.get("href"):
            self.loads.append((tag, "href", a["href"]))
        if tag == "a" and a.get("href"):
            self.links.append(a["href"])
        for name, _ in attrs:
            if name.startswith("on"):
                self.problems.append("event attribute %s on <%s>" % (name, tag))
        if tag not in VOID:
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1] != tag:
            self.problems.append("</%s> closes %s" % (tag, self.stack[-1:] or "nothing"))
            return
        self.stack.pop()

    def handle_data(self, data):
        self.text.append(data)


def parse(page):
    c = Checker()
    c.feed(page)
    c.close()
    return c


def words(fragment):
    """The visible text of a piece of HTML, spaces normalised."""
    c = parse(fragment)
    return re.sub(r"\s+", " ", "".join(c.text)).strip()


class ReadmeTest(unittest.TestCase):
    def assertIn(self, member, container, msg=None):
        # Without the whole page in the failure message.
        if member not in container:
            self.fail("%s%r was not found" % ((msg + ": ") if msg else "", member))

    def page(self, platform, version="9.9.9", changelog=SAMPLE):
        return m.build_within_limit(platform, version, "123", "2030-01-01T10:00:00Z", changelog)

    def test_each_platform_has_its_own_steps_only(self):
        win, mac = self.page("windows"), self.page("macos")
        for step in ("ClipForge-Setup.exe", "Windows protected your PC", "More info",
                     "Run anyway", "Start menu", "Show the read-me",
                     "Install on Windows"):
            self.assertIn(step, win)
        for step in ("Applications", "System Settings", "Privacy &amp; Security",
                     "Open Anyway", "macOS 15 or newer", "right-click ClipForge",
                     "not signed by Apple", "Apple chip", "Install on Mac"):
            self.assertIn(step, mac)
        self.assertNotIn("Open Anyway", win)
        self.assertNotIn("ClipForge-Setup.exe", mac)
        self.assertNotIn("Run anyway", mac)
        for platform in m.PLATFORMS:
            page = self.page(platform)
            for _, steps in m.PLATFORMS[platform]["routes"]:
                for step in steps:
                    self.assertIn("<li>%s</li>" % step, page)

    def test_version_sections_and_fixed_parts(self):
        for platform in m.PLATFORMS:
            page = self.page(platform)
            text = words(page)
            self.assertIn("<title>ClipForge 9.9.9", page)
            self.assertIn("Version 9.9.9 (build 123) · 1 January 2030", text)
            for part in ("First steps", "New project", "Add media", "Show the tour",
                         "Where your projects are", "Documents",
                         "Updates", "Version … is available", "Check for updates…",
                         "Use it with Claude (optional)", "Connect to Claude…",
                         "What is new in 9.9.9", "Earlier versions",
                         "GNU GPL version 3", "no warranty",
                         "Keep copies of videos you care about"):
                self.assertIn(part, text)
            self.assertIn(m.DOWNLOAD_PAGE, parse(page).links)
            # The three sections before it, folded; not the fourth, not the intro.
            self.assertEqual(page.count("<details>"), 3)
            for older in ("Older A", "Older B", "Older C"):
                self.assertIn(older, text)
            self.assertNotIn("Too old to show", text)
            self.assertNotIn("belongs to no version", text)
            self.assertNotIn("<details open", page)

    def test_nothing_is_fetched_and_the_html_is_balanced(self):
        for platform in m.PLATFORMS:
            page = self.page(platform)
            c = parse(page)
            self.assertEqual(c.problems, [])
            self.assertEqual(c.stack, [], "unclosed tags")
            # No tag that loads something by itself, from anywhere.
            self.assertEqual(c.loads, [])
            for tag in ("script", "img", "link", "iframe", "object", "embed", "video",
                        "audio", "source", "form", "base"):
                self.assertNotIn(tag, c.tags)
            # The style sheet: no url(...), no @import, no web fonts.
            style = re.search(r"<style>(.*?)</style>", page, re.S).group(1)
            for word in ("url(", "@import", "@font-face", "http://", "https://"):
                self.assertNotIn(word, style)
            # Addresses appear only as links to click, and only https ones.
            self.assertTrue(c.links)
            for href in c.links:
                self.assertTrue(href.startswith("https://") or href.startswith("#"), href)
            outside_links = re.sub(r"<a\s[^>]*>", "", page)
            self.assertNotIn("http://", outside_links)
            self.assertNotIn("https://", outside_links)
            self.assertTrue(page.startswith("<!doctype html>"))
            self.assertIn('<meta name="viewport"', page)
            self.assertIn("prefers-color-scheme:dark", page)
            self.assertLessEqual(len(page.encode("utf-8")), m.MAX_BYTES)

    def test_markdown_is_converted_and_injection_is_escaped(self):
        page = self.page("windows")
        self.assertIn("<b>Bold label</b>", page)
        self.assertIn("<code>inline &lt;code&gt;</code>", page)
        self.assertIn('<a href="https://example.org/a?b=1&amp;c=2" rel="noopener">link</a>', page)
        self.assertIn("&lt;script&gt;alert(1)&lt;/script&gt; &amp; an &lt;img src=x onerror=y&gt;", page)
        self.assertIn("<h5>A sub heading &lt;b&gt;</h5>", page)
        self.assertIn("<ol><li>\nNumbered one\n</li><li>\nNumbered two\n</li></ol>".replace("\n", ""),
                      page.replace("\n", ""))
        self.assertIn("Second item wrapped onto a second line.", page)
        c = parse(page)
        self.assertNotIn("script", c.tags)
        self.assertNotIn("img", c.tags)
        self.assertFalse([h for h in c.links if "javascript" in h.lower()])
        self.assertIn("[bad link](javascript:alert(1))", "".join(c.text))
        # Nested list: a <ul> inside the first <li>.
        self.assertRegex(page.replace("\n", ""), r"<ul><li><b>Bold label</b>.*?<ul><li>A nested item")

    def test_converter_pieces(self):
        self.assertEqual(m.inline('a < b & "c"'), "a &lt; b &amp; &quot;c&quot;")
        self.assertEqual(m.inline("**x** `y`"), "<b>x</b> <code>y</code>")
        self.assertEqual(m.inline("[t](data:text/html,x)"), "[t](data:text/html,x)")
        self.assertEqual(m.inline('[t](https://e.org/"onclick="x)'),
                         "[t](https://e.org/&quot;onclick=&quot;x)")
        self.assertEqual(m.markdown_to_html("- a\n- b\n\ntext"),
                         "<ul><li>\na\n</li><li>\nb\n</li></ul>\n<p>text</p>")
        self.assertEqual(m.pretty_date("2026-11-19T07:20:00Z"), "19 November 2026")
        self.assertEqual(m.pretty_date("soon"), "soon")

    def test_a_missing_version_fails_and_a_long_changelog_stays_small(self):
        with self.assertRaises(ValueError):
            m.build("windows", "1.2.3", "1", "", SAMPLE)
        with tempfile.TemporaryDirectory() as tmp:
            log = os.path.join(tmp, "CHANGELOG.md")
            out = os.path.join(tmp, "Read me first.html")
            with open(log, "w", encoding="utf-8") as f:
                f.write(SAMPLE)
            args = ["--platform", "macos", "--build", "7", "--date", "2030-01-01",
                    "--changelog", log, "--out", out]
            self.assertEqual(m.main(args + ["--version", "1.2.3"]), 1)
            self.assertFalse(os.path.exists(out))
            self.assertEqual(m.main(args + ["--version", "9.9.9"]), 0)
            with open(out, encoding="utf-8") as f:
                self.assertIn("Install on Mac", f.read())
        big = SAMPLE.replace("- Older B", "\n".join("- %s" % ("word " * 60) for _ in range(120)))
        page = m.build_within_limit("windows", "9.9.9", "1", "", big)
        self.assertLessEqual(len(page.encode("utf-8")), m.MAX_BYTES)
        self.assertIn("Older A", page)
        self.assertNotIn("Older C", page)
        self.assertEqual(parse(page).stack, [])

    def test_the_real_changelog_and_the_download_page_agree(self):
        root = os.path.normpath(os.path.join(HERE, "..", ".."))
        changelog = os.path.join(root, "CHANGELOG.md")
        site = os.path.join(root, "..", "site", "index.html")
        if not (os.path.exists(changelog) and os.path.exists(site)):
            self.skipTest("not inside the repository")
        with open(changelog, encoding="utf-8") as f:
            text = f.read()
        newest = m.changelog_sections(text)[0][0]
        for platform in m.PLATFORMS:
            page = m.build_within_limit(platform, newest, "1", "2026-11-19", text)
            c = parse(page)
            self.assertEqual((c.problems, c.stack, c.loads), ([], [], []))
            self.assertLessEqual(len(page.encode("utf-8")), m.MAX_BYTES)
        # The install steps here and on the download page are the same words.
        with open(site, encoding="utf-8") as f:
            site_text = words(f.read())
        for platform, p in m.PLATFORMS.items():
            for _, steps in p["routes"]:
                for step in steps:
                    self.assertIn(words(step), site_text,
                                  "site/index.html does not have this %s step" % platform)
            # The guide is part of the download since 1.15, not a link.
            self.assertNotIn("ClipForge-readme-%s.html" % platform,
                             open(site, encoding="utf-8").read())
        # The zip is only for the app's own updater now.
        self.assertNotIn("Extract All", self.page("windows"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
