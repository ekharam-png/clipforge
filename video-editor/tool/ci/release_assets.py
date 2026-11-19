#!/usr/bin/env python3
# THE list of files a ClipForge release publishes (1.15), and the checks
# around it.
#
#   python3 tool/ci/release_assets.py --check-dir <folder>
#       The folder must hold exactly these files, no more and no fewer (the
#       release job uploads the folder as it is).
#   python3 tool/ci/release_assets.py --check-links
#       The download page (site/index.html) must offer exactly the three
#       downloads people see, and every "releases/latest/download/<name>"
#       link on the site, in the app (lib/, assets/) and in the docs must
#       name a file in the list. Run in the "check" job.
#
# What people see - three downloads, one per kind of device:
#   ClipForge-Setup.exe     Windows (the guide is installed with it)
#   ClipForge-macos.zip     Mac (the guide sits beside the app in the zip)
#   ClipForge-android.apk   Android
# What only the app's own Update button uses (not on the page):
#   ClipForge-windows.zip   the Windows app as a folder (apps from 1.12 on
#                           update from it; do not remove it while such
#                           versions are in use)
#   latest.json             version, and per system the address, size and
#                           SHA-256 of its file
# Standard library only.
import argparse
import os
import re
import sys

DOWNLOADS = ["ClipForge-Setup.exe", "ClipForge-macos.zip", "ClipForge-android.apk"]
UPDATER_ONLY = ["ClipForge-windows.zip", "latest.json"]
ASSETS = DOWNLOADS + UPDATER_ONLY

LINK = re.compile(r"releases/latest/download/([A-Za-z0-9._-]+)")
HERE = os.path.dirname(os.path.abspath(__file__))
EDITOR = os.path.normpath(os.path.join(HERE, "..", ".."))
REPO = os.path.normpath(os.path.join(EDITOR, ".."))

# Where links to release files may be written.
SCANNED = [
    (REPO, "site"),
    (EDITOR, "lib"),
    (EDITOR, "assets"),
    (EDITOR, "README.md"),
    (EDITOR, "docs/claude-setup.html"),
    (EDITOR, "docs/FEATURES.md"),
    (EDITOR, "claude"),
    (EDITOR, "windows/installer"),
    (REPO, "README.md"),
]
TEXT = (".html", ".md", ".dart", ".txt", ".json", ".iss", ".py", ".yaml", ".yml", ".ps1", ".sh")


def check_dir(folder):
    have = sorted(os.listdir(folder))
    want = sorted(ASSETS)
    if have == want:
        print("release files: %s" % ", ".join(have))
        return []
    return ["the release folder must hold exactly %s, but holds %s" % (want, have)]


def files_under(base, rel):
    path = os.path.join(base, rel)
    if os.path.isfile(path):
        yield path
        return
    for root, _, names in os.walk(path):
        for name in names:
            if name.lower().endswith(TEXT):
                yield os.path.join(root, name)


def links_in(path):
    try:
        with open(path, encoding="utf-8") as f:
            return LINK.findall(f.read())
    except (OSError, UnicodeDecodeError):
        return []


def check_links(site_index=None):
    problems = []
    index = site_index or os.path.join(REPO, "site", "index.html")
    if os.path.exists(index):
        on_page = links_in(index)
        if sorted(on_page) != sorted(DOWNLOADS):
            problems.append(
                "site/index.html must have exactly three download links (%s), "
                "but has: %s" % (", ".join(DOWNLOADS), ", ".join(on_page) or "none"))
    elif site_index is None:
        print("note: no site/index.html here, only the other files are checked")
    for base, rel in SCANNED:
        for path in files_under(base, rel):
            for name in links_in(path):
                if name not in ASSETS:
                    problems.append("%s links to %s, which no release has"
                                    % (os.path.relpath(path, REPO), name))
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check-dir")
    ap.add_argument("--check-links", action="store_true")
    ap.add_argument("--site-index", help="another index.html (tests)")
    args = ap.parse_args()
    problems = []
    if args.check_dir:
        problems += check_dir(args.check_dir)
    if args.check_links or args.site_index:
        problems += check_links(args.site_index)
    for p in problems:
        print("error: %s" % p, file=sys.stderr)
    if not problems and (args.check_links or args.site_index):
        print("download links: the page offers %s; every link names a release file"
              % ", ".join(DOWNLOADS))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
