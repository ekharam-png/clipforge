#!/usr/bin/env python3
# Writes "Read me first.html": the guide that is PART of the Windows and
# macOS downloads - installed by ClipForge-Setup.exe (and offered on its
# last page), and beside ClipForge.app inside ClipForge-macos.zip. Since
# 1.15 it is not a separate download any more.
#
#   python3 tool/ci/make_readme_html.py --platform windows|macos \
#       --version 1.14.1 --build 123 --date 2026-11-19T07:20:00Z \
#       --changelog CHANGELOG.md --out "dist/Read me first.html"
#
# ONE self-contained file: no web fonts, no remote images, no scripts; it
# reads the same with no internet. Light and dark follow the system.
#
# The words are written once, here (PLATFORMS and the SECTION_* texts). The
# install steps are the same sentences as on the download page
# (site/index.html); tool/ci/make_readme_html_test.py fails when the two
# drift apart. "What is new" is the version's section of CHANGELOG.md, put
# through the small Markdown converter below (headings, lists, bold, inline
# code, links; everything else is escaped), followed by the three sections
# before it, folded.
#
# Fails (exit 1) when CHANGELOG.md has no section for the version.
# Standard library only.
import argparse
import datetime
import html
import re
import sys

DOWNLOAD_PAGE = "https://ekharam-png.github.io/clipforge/"
HELP_ONLINE = "https://github.com/ekharam-png/clipforge/blob/main/video-editor/assets/help/help_en.md"
LICENCE = "https://github.com/ekharam-png/clipforge/blob/main/LICENSE"
SOURCE = "https://github.com/ekharam-png/clipforge"

# The file should stay a quick read and a small download.
MAX_BYTES = 40 * 1024
EARLIER_SECTIONS = 3

LEDE = ("A free, simple video editor for family videos, podcast clips and sport clips. "
        "Trim, add titles, captions and music, then export.")

SMARTSCREEN = ('If you see "Windows protected your PC", click <b>More info</b>, '
               "then <b>Run anyway</b>.")

# Install steps: small HTML (only <b>), the same sentences as site/index.html.
PLATFORMS = {
    "windows": {
        "system": "Windows",
        "routes": [
            (None, [
                "Open the downloaded <b>ClipForge-Setup.exe</b>.",
                SMARTSCREEN,
                "Click through the installer. It needs no administrator password "
                "and puts ClipForge in the Start menu.",
                "On the last page, leave <b>Show the read-me</b> ticked if you would "
                "like the short guide. It is installed with ClipForge and is also in "
                'the Start menu, as "ClipForge read me".',
                "Open the <b>Start menu</b> and choose <b>ClipForge</b>.",
            ]),
        ],
        "notes": [
            "The warning appears because ClipForge is not signed by Microsoft. That is expected.",
            "Do not start ClipForge from a folder whose name ends in <b>.update-new</b>: "
            "that is a download waiting to be put in place.",
        ],
        "claude_note": "",
    },
    "macos": {
        "system": "Mac",
        "routes": [
            (None, [
                "Double-click the downloaded <b>ClipForge-macos.zip</b> to unzip it. "
                "A folder appears with <b>ClipForge</b> and the short guide "
                "<b>Read me first</b> in it (these same steps, to keep).",
                "Drag <b>ClipForge</b> into your <b>Applications</b> folder.",
                "<b>macOS 15 or newer:</b> open ClipForge once. macOS says it cannot open it: "
                "close that message. Then open <b>System Settings</b>, choose "
                "<b>Privacy &amp; Security</b>, scroll down, click <b>Open Anyway</b> "
                "next to the line about ClipForge, and confirm.",
                "<b>Older macOS:</b> right-click ClipForge, choose <b>Open</b>, "
                "then <b>Open</b> again.",
            ]),
        ],
        "notes": [
            "This is needed once, because ClipForge is not signed by Apple. "
            "After that it opens like any other app.",
        ],
        "claude_note": "On a Mac this needs an Apple chip (M1 or newer).",
    },
}

FIRST_STEPS = [
    "On the project list, click <b>New project</b>.",
    "Click <b>Add media</b> and pick your videos or photos. You can also drag them into the window.",
    "Stuck? Every screen has a <b>Help</b> button (the <b>?</b> at the top) with short "
    "articles. <b>Show the tour</b> there walks you through the editor again.",
]

PROJECTS = [
    "Your projects are kept in your <b>Documents</b> folder, in <b>ClipForge</b>.",
    "Updating, reinstalling or removing ClipForge does not touch them.",
    "ClipForge uses your videos, photos and music where they are. Do not move or delete "
    "them while a project uses them.",
]

UPDATES = [
    'ClipForge looks for a newer version by itself. When there is one, the project list '
    'shows "Version … is available": click <b>Update</b>.',
    "To ask right now: <b>Help</b>, then <b>Check for updates…</b>",
    'If an update ever does not work, get the newest version from the '
    '<a href="%s">download page</a> and install it over the one you have. '
    "Your projects are kept." % DOWNLOAD_PAGE,
]

CLAUDE_INTRO = ("Claude can edit your ClipForge projects for you: cut silences, add titles, "
                "captions and music, and export. You do not need this to use ClipForge.")
CLAUDE_STEPS = [
    "In ClipForge, open <b>Help</b>, then <b>Connect to Claude…</b>",
    "Click <b>Connect</b> next to your Claude.",
    "Close Claude and open it again once.",
]

CSS = """
:root{--paper:#eef0f4;--panel:#fff;--ink:#18202c;--muted:#566173;--rule:#d3d8e0;
--accent:%(accent)s;--head:#c8372d;--link:#2f5fc4;--code:#e2e6ec}
@media (prefers-color-scheme:dark){:root{--paper:#12161d;--panel:#1b212b;--ink:#e9edf3;
--muted:#a3adbd;--rule:#2c3442;--accent:%(accent_dark)s;--head:#ff6a5c;--link:#8ea2ff;--code:#2c3442}}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%%}
body{margin:0;background:var(--paper);color:var(--ink);
font-family:"Segoe UI Variable Text","Segoe UI",system-ui,-apple-system,Roboto,"Helvetica Neue",Arial,sans-serif;
font-size:17px;line-height:1.55;overflow-wrap:break-word}
.wrap{max-width:760px;margin:0 auto;padding:0 16px}
a{color:var(--link);text-underline-offset:3px}
a:focus-visible,summary:focus-visible{outline:3px solid var(--link);outline-offset:3px;border-radius:4px}
header{padding:40px 0 8px}
h1{font-size:clamp(40px,9vw,64px);line-height:1;letter-spacing:-.035em;margin:0;font-weight:800}
h1 span{color:var(--muted);font-weight:600}
.lede{font-size:19px;margin:14px 0 8px;max-width:34em}
.meta{color:var(--muted);font-size:15px;margin:0}
.beta{display:inline-block;padding:1px 9px;margin-right:8px;border:1.5px solid var(--head);
color:var(--head);border-radius:999px;font-weight:600;font-size:14px}
nav{margin:20px 0 0;font-size:15px;line-height:2}
nav a{margin-right:14px;white-space:nowrap}
section{padding:26px 0;border-top:1px solid var(--rule)}
header+main section:first-child{border-top:0}
h2{font-size:26px;letter-spacing:-.02em;line-height:1.2;margin:0 0 14px}
h3{font-size:18px;margin:18px 0 8px}
h4{font-size:16px;margin:14px 0 6px}
p{margin:0 0 12px}
ol,ul{margin:0 0 12px;padding-left:24px}
li{margin:5px 0}
li>ul,li>ol{margin:5px 0 0}
.install{background:var(--panel);border:1px solid var(--rule);border-left:5px solid var(--accent);
border-radius:10px;padding:18px 20px 8px;margin-top:8px}
.install h3:first-child{margin-top:0}
.install ol{padding-left:26px}
.install li{margin:8px 0;padding-left:2px}
.install li::marker{font-weight:700;color:var(--accent)}
.note{color:var(--muted);font-size:15px}
code{font-family:ui-monospace,"Cascadia Mono",Consolas,Menlo,monospace;font-size:.9em;
background:var(--code);padding:1px 5px;border-radius:4px}
details{border:1px solid var(--rule);border-radius:8px;margin:8px 0;background:var(--panel)}
summary{cursor:pointer;padding:10px 14px;font-weight:600}
details>div{padding:0 14px 6px}
.news{font-size:16px}
footer{padding:22px 0 44px;border-top:1px solid var(--rule);color:var(--muted);font-size:15px}
footer p{margin:0 0 6px}
@media (max-width:480px){body{font-size:16px}.install{padding:14px 14px 4px}h2{font-size:23px}}
@media print{body{background:#fff}details{border:0}}
"""

ACCENTS = {"windows": ("#2c4a75", "#6f9ad8"), "macos": ("#2e7d5b", "#4fb08b")}


# --- The small Markdown converter -----------------------------------------

_INLINE = re.compile(
    r"`([^`\n]+)`"                                   # 1: inline code
    r"|\*\*(?=\S)(.+?)(?<=\S)\*\*"                   # 2: bold
    r"|\[([^\]\n]+)\]\(([^()\s]+)\)"                 # 3, 4: link
)


def inline(text):
    """Bold, inline code and links; every other character is escaped."""
    out = []
    pos = 0
    for m in _INLINE.finditer(text):
        out.append(html.escape(text[pos:m.start()], quote=True))
        if m.group(1) is not None:
            out.append("<code>%s</code>" % html.escape(m.group(1), quote=True))
        elif m.group(2) is not None:
            out.append("<b>%s</b>" % inline(m.group(2)))
        else:
            label, url = m.group(3), m.group(4)
            # Only real web addresses become links (no javascript:, data:, ...).
            if re.match(r"(?i)https?://[^\s\"'<>]+$", url):
                out.append('<a href="%s" rel="noopener">%s</a>'
                           % (html.escape(url, quote=True), inline(label)))
            else:
                out.append(html.escape(m.group(0), quote=True))
        pos = m.end()
    out.append(html.escape(text[pos:], quote=True))
    return "".join(out)


def markdown_to_html(text, heading_shift=2):
    """Headings (#), bullet and numbered lists (nested by indent), paragraphs.

    Raw HTML in the text is escaped, never passed through. A heading "#" in
    the text becomes <h(1 + heading_shift)>, at most <h6>.
    """
    out = []
    stack = []        # open lists: (indent, tag); the last <li> of each is open
    para = []

    def close_para():
        if para:
            out.append("<p>%s</p>" % inline(" ".join(para)))
            del para[:]

    def close_lists(to_indent=-1):
        while stack and stack[-1][0] > to_indent:
            out.append("</li></%s>" % stack.pop()[1])

    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip():
            close_para()
            if not stack:
                continue
            # A blank line ends the lists unless the next line continues them;
            # simple rule: it ends them.
            close_lists()
            continue
        m = re.match(r"(#{1,6})\s+(.*)$", line)
        if m:
            close_para()
            close_lists()
            level = min(6, len(m.group(1)) + heading_shift)
            out.append("<h%d>%s</h%d>" % (level, inline(m.group(2).strip()), level))
            continue
        m = re.match(r"(\s*)([-*+]|\d{1,3}[.)])\s+(.*)$", line)
        if m:
            close_para()
            indent = len(m.group(1).replace("\t", "    "))
            tag = "ul" if m.group(2) in "-*+" else "ol"
            if stack and indent > stack[-1][0]:
                out.append("<%s><li>" % tag)             # nested in the open <li>
                stack.append((indent, tag))
            else:
                close_lists(indent)
                if stack and stack[-1][0] == indent and stack[-1][1] == tag:
                    out.append("</li><li>")
                else:
                    close_lists(indent - 1)
                    out.append("<%s><li>" % tag)
                    stack.append((indent, tag))
            out.append(inline(m.group(3)))
            continue
        if stack and line[:1] in " \t":
            out[-1] += " " + inline(line.strip())        # a wrapped list line
            continue
        close_lists()
        para.append(line.strip())
    close_para()
    close_lists()
    return "\n".join(out)


def changelog_sections(text):
    """[(version, title, body)] in file order, from the "## <version> ..." headings."""
    sections = []
    current = None
    for line in text.splitlines():
        m = re.match(r"##\s+(\S+)\s*(.*)$", line)
        if m:
            current = [m.group(1), line[2:].strip(), []]
            sections.append(current)
        elif current is not None:
            current[2].append(line)
    return [(v, t, "\n".join(b).strip("\n")) for v, t, b in sections]


# --- The page ---------------------------------------------------------------

def pretty_date(value):
    """'2026-11-19T07:20:00Z' or '2026-11-19' -> '19 November 2026'; else as given."""
    value = (value or "").strip()
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", value)
    if m:
        try:
            d = datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
            return "%d %s %d" % (d.day, d.strftime("%B"), d.year)
        except ValueError:
            pass
    return value


def _ol(items):
    return "<ol>\n%s\n</ol>" % "\n".join("<li>%s</li>" % i for i in items)


def _ul(items):
    return "<ul>\n%s\n</ul>" % "\n".join("<li>%s</li>" % i for i in items)


def build(platform, version, build_number, date, changelog_text, earlier=EARLIER_SECTIONS):
    p = PLATFORMS[platform]
    esc = lambda s: html.escape(str(s), quote=True)  # noqa: E731
    sections = changelog_sections(changelog_text)
    index = next((i for i, s in enumerate(sections) if s[0] == version), None)
    if index is None:
        raise ValueError("CHANGELOG has no section for %s" % version)

    meta = ["Version %s" % esc(version)]
    if str(build_number or "").strip():
        meta[0] += " (build %s)" % esc(build_number)
    if pretty_date(date):
        meta.append(esc(pretty_date(date)))
    meta.append("for %s" % esc(p["system"]))

    install = []
    for title, steps in p["routes"]:
        if title:
            install.append("<h3>%s</h3>" % esc(title))
        install.append(_ol(steps))
    install.extend('<p class="note">%s</p>' % n for n in p["notes"])

    claude = "<p>%s</p>\n%s" % (CLAUDE_INTRO, _ol(CLAUDE_STEPS))
    claude += ('\n<p class="note">Claude reads its list of tools when it starts, so the restart '
               "is needed once. ClipForge does not have to be running.%s</p>"
               % (" " + p["claude_note"] if p["claude_note"] else ""))

    older = []
    for v, title, body in sections[index + 1:index + 1 + max(0, earlier)]:
        older.append("<details>\n<summary>%s</summary>\n<div class=\"news\">\n%s\n</div>\n</details>"
                     % (inline(title), markdown_to_html(body)))
    older_html = ""
    if older:
        older_html = ("<h3>Earlier versions</h3>\n%s\n" % "\n".join(older))
    older_html += ('<p class="note">All versions: <b>Help</b>, then <b>What\'s new</b> '
                   "in the app.</p>")

    accent, accent_dark = ACCENTS[platform]
    parts = [
        "<!doctype html>",
        '<html lang="en">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        "<title>ClipForge %s: read me first</title>" % esc(version),
        "<style>%s</style>" % (CSS % {"accent": accent, "accent_dark": accent_dark}),
        "</head>",
        "<body>",
        '<header class="wrap">',
        "<h1>ClipForge <span>%s</span></h1>" % esc(version),
        '<p class="lede">%s</p>' % LEDE,
        '<p class="meta"><span class="beta">Beta</span>%s</p>' % " · ".join(meta),
        '<nav aria-label="On this page"><a href="#install">Install</a><a href="#first">First steps</a>'
        '<a href="#projects">Your projects</a><a href="#updates">Updates</a>'
        '<a href="#claude">Claude</a><a href="#new">What is new</a></nav>',
        "</header>",
        '<main class="wrap">',
        '<section aria-labelledby="install">',
        '<h2 id="install">Install on %s</h2>' % esc(p["system"]),
        '<div class="install">\n%s\n</div>' % "\n".join(install),
        "</section>",
        '<section aria-labelledby="first">',
        '<h2 id="first">First steps</h2>',
        _ol(FIRST_STEPS),
        "</section>",
        '<section aria-labelledby="projects">',
        '<h2 id="projects">Where your projects are</h2>',
        _ul(PROJECTS),
        "</section>",
        '<section aria-labelledby="updates">',
        '<h2 id="updates">Updates</h2>',
        _ul(UPDATES),
        "</section>",
        '<section aria-labelledby="claude">',
        '<h2 id="claude">Use it with Claude (optional)</h2>',
        claude,
        "</section>",
        '<section aria-labelledby="new">',
        '<h2 id="new">What is new in %s</h2>' % esc(version),
        '<div class="news">\n%s\n</div>' % markdown_to_html(sections[index][2]),
        older_html,
        "</section>",
        "</main>",
        '<footer class="wrap">',
        '<p><a href="%s">Download page</a> · <a href="%s">Help online</a> · '
        'Free software under the <a href="%s">GNU GPL version 3</a> '
        '(<a href="%s">source code</a>).</p>' % (DOWNLOAD_PAGE, HELP_ONLINE, LICENCE, SOURCE),
        "<p>ClipForge is a beta made for personal use and comes with no warranty. "
        "Keep copies of videos you care about.</p>",
        "</footer>",
        "</body>",
        "</html>",
        "",
    ]
    return "\n".join(parts)


def build_within_limit(platform, version, build_number, date, changelog_text):
    """The page, with fewer earlier versions when it would pass MAX_BYTES."""
    page = ""
    for earlier in range(EARLIER_SECTIONS, -1, -1):
        page = build(platform, version, build_number, date, changelog_text, earlier=earlier)
        if len(page.encode("utf-8")) <= MAX_BYTES:
            break
    return page


def main(argv=None):
    ap = argparse.ArgumentParser(description='Writes "Read me first.html" for a ClipForge download.')
    ap.add_argument("--platform", required=True, choices=sorted(PLATFORMS))
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", default="")
    ap.add_argument("--date", default="")
    ap.add_argument("--changelog", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    with open(args.changelog, encoding="utf-8") as f:
        changelog = f.read()
    try:
        page = build_within_limit(args.platform, args.version, args.build, args.date, changelog)
    except ValueError as e:
        print("make_readme_html: %s" % e, file=sys.stderr)
        return 1
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(page)
    print("wrote %s (%d bytes)" % (args.out, len(page.encode("utf-8"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
