#!/usr/bin/env python3
# Reads tool/ci/links.json: THE one place for ClipForge's outside addresses
# (see the "about" line in that file and docs/RENAMING.md).
#
#   python3 tool/ci/links.py            prints the addresses in full
#
# Used by make_latest_json.py (latest.json's "links"), make_readme_html.py
# and the tests. Standard library only.
import json
import os
import sys
from urllib.parse import urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))
LINKS_JSON = os.path.join(HERE, "links.json")

# What latest.json's "links" holds, in this order (lib/core/links.dart
# reads the same names).
NAMES = ["site", "download", "feedback_api", "feedback_page", "help", "privacy"]
MAX_LENGTH = 200


def load(path=None):
    """The file as it is, plus "full": every address written out."""
    with open(path or LINKS_JSON, encoding="utf-8") as f:
        data = json.load(f)
    site = data["site"].rstrip("/")
    full = {"site": site}
    for name, value in data["links"].items():
        full[name] = site + value if value.startswith("/") else value
    data["full"] = full
    data["claude_page_full"] = site + data["claude_page"] if data["claude_page"].startswith("/") else data["claude_page"]
    return data


def problems(data):
    """What the app would refuse (lib/core/links.dart checks the same)."""
    out = []
    full = data["full"]
    for name in NAMES:
        if name not in full:
            out.append("links.json has no %s" % name)
    for name, url in full.items():
        parts = urlsplit(url)
        if parts.scheme != "https" or not parts.hostname or "." not in parts.hostname:
            out.append("%s must be an https address: %s" % (name, url))
        if len(url) > MAX_LENGTH or "@" in parts.netloc or any(c.isspace() for c in url):
            out.append("%s is not a plain, short address: %s" % (name, url))
    if not out:
        allowed = [urlsplit(full["site"]).hostname] + list(data.get("feedback_api_hosts", []))
        if urlsplit(full["feedback_api"]).hostname not in allowed:
            out.append("feedback_api must be on the site's own host or in feedback_api_hosts")
    for name in ("repository", "old_pages"):
        if not str(data.get(name, "")).startswith("https://"):
            out.append("links.json needs an https %s" % name)
    return out


def latest_links(path=None):
    """The "links" object for latest.json; raises ValueError when wrong."""
    data = load(path)
    bad = problems(data)
    if bad:
        raise ValueError("; ".join(bad))
    return {name: data["full"][name] for name in NAMES}


if __name__ == "__main__":
    d = load()
    for p in problems(d):
        print("error: %s" % p, file=sys.stderr)
    print(json.dumps({"links": d["full"], "claude_page": d["claude_page_full"],
                      "repository": d["repository"], "old_pages": d["old_pages"]}, indent=2))
    sys.exit(1 if problems(d) else 0)
