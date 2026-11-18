#!/usr/bin/env python3
# Builds the two things that connect Claude to ClipForge without editing a
# config file by hand:
#
#   1. the Claude Desktop extension (.mcpb, an "MCP Bundle", formerly .dxt):
#      a zip with manifest.json, the clipforge-mcp program, the title fonts
#      and an icon. Double-clicking it in Claude Desktop installs the
#      `clipforge` tools.
#
#        python3 docs/tools/build_claude_bundles.py mcpb \
#            --binary build/mcp/clipforge-mcp --platform macos \
#            --version 1.9.0 --build 32 --out dist
#        -> dist/ClipForge-1.9.0-build32-claude-macos.mcpb
#
#   2. the skill zip (claude/skill/clipforge-editing), for
#      Claude > Customize > Skills > Upload a skill:
#
#        python3 docs/tools/build_claude_bundles.py skill --version 1.9.0 --out dist
#        -> dist/ClipForge-1.9.0-claude-skill.zip
#
# Run it from video-editor/. Python 3.8+, standard library only (the GitHub
# Windows, macOS and Linux runners all have it).
#
# Manifest format: MCPB manifest_version 0.3
# (https://github.com/anthropics/mcpb/blob/main/MANIFEST.md, checked on
# 17 Nov 2026 together with schemas/mcpb-manifest-v0.3.schema.json: the
# top level allows no keys other than the ones in TOP_LEVEL_KEYS below, and
# a "binary" server needs type, entry_point and mcp_config.command).
#
# Layout of the bundle (what clipforge-mcp expects: the fonts in a `fonts`
# folder next to the program, see locateFonts in lib/mcp/environment.dart):
#
#   manifest.json
#   icon.png
#   server/clipforge-mcp(.exe)
#   server/fonts/*.ttf + the font licences
#   server/CLAUDE.md                (the guide, for reference)
import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))  # video-editor/

# manifest "compatibility.platforms" value, executable name, label.
PLATFORMS = {
    "windows": ("win32", "clipforge-mcp.exe"),
    "macos": ("darwin", "clipforge-mcp"),
    "linux": ("linux", "clipforge-mcp"),  # not shipped; for testing the script
}

# From schemas/mcpb-manifest-v0.3.schema.json (additionalProperties: false).
TOP_LEVEL_KEYS = {
    "$schema", "dxt_version", "manifest_version", "name", "display_name",
    "version", "description", "long_description", "author", "repository",
    "homepage", "documentation", "support", "icon", "icons", "screenshots",
    "localization", "server", "tools", "tools_generated", "prompts",
    "prompts_generated", "keywords", "license", "privacy_policies",
    "compatibility", "user_config", "_meta",
}
REQUIRED_KEYS = ("manifest_version", "name", "version", "description", "author", "server")
REQUIRED_FONTS = ("DejaVuSans.ttf", "DejaVuSans-Bold.ttf")

DESCRIPTION = ("Lets Claude edit your ClipForge videos: cut out silences, trim and "
               "reorder clips, add titles, captions and music, and export the result.")
LONG_DESCRIPTION = """\
ClipForge is a video editor. With this extension you can ask Claude in plain words to work on your ClipForge projects, for example:

- "Make a new project from the videos in my Holiday folder and add quiet music."
- "Remove the silent pauses from my podcast project, then export it."
- "Add the title 'Summer 2026' at the start and make an upright version for my phone."

Good to know:

- Go back to ClipForge's project list (or close the app) before asking Claude to change a project.
- Claude never deletes your projects, videos, photos or music.
- Claude cannot see or hear the video. It works with lengths, times and text, and asks you to check the result in ClipForge.
- Adding files, finding silences and exporting need the free program FFmpeg on this computer (Windows: `winget install ffmpeg`; Mac: `brew install ffmpeg`). Ask Claude "What is the ClipForge status?" to see whether it was found.

Build: {display}
"""


def fail(message):
    print("error: " + message, file=sys.stderr)
    sys.exit(1)


def pubspec_version():
    with open(os.path.join(ROOT, "pubspec.yaml"), encoding="utf-8") as f:
        m = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)", f.read(), re.M)
    if not m:
        fail("no version in pubspec.yaml")
    return m.group(1)


def tool_names_from_source():
    """The tool names registered in lib/mcp/tools.dart and its part
    tools_speech.dart (fallback when the program cannot be run on this
    computer)."""
    names = []
    for name in ("tools.dart", "tools_speech.dart"):
        with open(os.path.join(ROOT, "lib", "mcp", name), encoding="utf-8") as f:
            names += re.findall(r"^\s{6,10}name: '([a-z_]+)',$", f.read(), re.M)
    return [{"name": n} for n in names]


def first_sentence(text, limit=140):
    text = " ".join((text or "").split())
    m = re.match(r"(.+?[.!?])(\s|$)", text)
    s = m.group(1) if m else text
    return s if len(s) <= limit else s[: limit - 1].rstrip() + "…"


def tools_from_binary(binary):
    """Asks the program itself for its tools (MCP tools/list over stdio)."""
    with tempfile.TemporaryDirectory() as tmp:
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                "protocolVersion": "2025-11-25", "capabilities": {},
                "clientInfo": {"name": "build_claude_bundles", "version": "1"}}},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
             "params": {"name": "get_status", "arguments": {}}},
        ]
        run = subprocess.run(
            [binary, "--projects-dir", os.path.join(tmp, "projects")],
            input="".join(json.dumps(m) + "\n" for m in messages).encode("utf-8"),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    tools, status = None, None
    for line in run.stdout.decode("utf-8", "replace").splitlines():
        try:
            reply = json.loads(line)
        except ValueError:
            continue
        if reply.get("id") == 2:
            tools = [{"name": t["name"], "description": first_sentence(t.get("description"))}
                     for t in reply["result"]["tools"]]
        if reply.get("id") == 3:
            status = reply["result"].get("structuredContent") or {}
    if not tools:
        fail("the program did not answer tools/list:\n" + run.stderr.decode("utf-8", "replace")[-2000:])
    return tools, status


def make_manifest(platform, version, display, tools):
    node_platform, exe = PLATFORMS[platform]
    return {
        "manifest_version": "0.3",
        "name": "clipforge",
        "display_name": "ClipForge",
        "version": version,
        "description": DESCRIPTION,
        "long_description": LONG_DESCRIPTION.format(display=display),
        "author": {"name": "ClipForge"},
        "icon": "icon.png",
        "server": {
            "type": "binary",
            "entry_point": "server/" + exe,
            "mcp_config": {
                "command": "${__dirname}/server/" + exe,
                "args": [],
                "env": {},
            },
        },
        "tools": tools,
        "keywords": ["video", "video editor", "clipforge", "podcast", "subtitles", "export"],
        "compatibility": {"platforms": [node_platform]},
    }


def validate_manifest(manifest, stage):
    """The checks of the 0.3 schema that matter here, plus that every file
    the manifest names is really in the bundle."""
    problems = []
    for key in REQUIRED_KEYS:
        if key not in manifest:
            problems.append("missing required field: " + key)
    for key in manifest:
        if key not in TOP_LEVEL_KEYS:
            problems.append("field not allowed by the schema: " + key)
    if manifest.get("manifest_version") != "0.3":
        problems.append("manifest_version must be \"0.3\"")
    if not re.fullmatch(r"\d+\.\d+\.\d+", str(manifest.get("version", ""))):
        problems.append("version must look like 1.9.0")
    for key in ("name", "description"):
        if not isinstance(manifest.get(key), str) or not manifest.get(key):
            problems.append(key + " must be text")
    author = manifest.get("author")
    if not isinstance(author, dict) or not author.get("name"):
        problems.append("author.name is required")
    server = manifest.get("server") or {}
    if set(server) - {"type", "entry_point", "mcp_config"}:
        problems.append("server has fields the schema does not allow")
    if server.get("type") not in ("node", "python", "binary"):
        problems.append("server.type must be node, python or binary")
    config = server.get("mcp_config") or {}
    if set(config) - {"command", "args", "env", "platform_overrides"}:
        problems.append("server.mcp_config has fields the schema does not allow")
    entry = server.get("entry_point")
    if not entry or not os.path.isfile(os.path.join(stage, entry)):
        problems.append("server.entry_point is not in the bundle: %r" % entry)
    command = config.get("command")
    if not isinstance(command, str) or not command:
        problems.append("server.mcp_config.command is required")
    elif "${__dirname}" in command:
        resolved = command.replace("${__dirname}", stage)
        if not os.path.isfile(resolved):
            problems.append("server.mcp_config.command does not point at a file in the bundle: " + command)
    if not all(isinstance(a, str) for a in config.get("args", [])):
        problems.append("server.mcp_config.args must be a list of text")
    icon = manifest.get("icon")
    if icon and not icon.startswith("https://") and not os.path.isfile(os.path.join(stage, icon)):
        problems.append("icon is not in the bundle: " + icon)
    names = []
    for tool in manifest.get("tools", []):
        if not isinstance(tool, dict) or not tool.get("name") or set(tool) - {"name", "description"}:
            problems.append("bad tools entry: %r" % (tool,))
        else:
            names.append(tool["name"])
    if len(names) != len(set(names)):
        problems.append("a tool is listed twice")
    platforms = (manifest.get("compatibility") or {}).get("platforms", [])
    if any(p not in ("darwin", "win32", "linux") for p in platforms):
        problems.append("compatibility.platforms: only darwin, win32, linux")
    return problems


def zip_folder(folder, out_path, root_name="", executables=()):
    """Zips [folder]; entries start with [root_name] when given. Files in
    [executables] (paths relative to the folder) get Unix mode 0755 whatever
    system this runs on, so macOS can run them after unpacking."""
    count = 0
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for base, dirs, files in os.walk(folder):
            dirs.sort()
            for name in sorted(files):
                full = os.path.join(base, name)
                rel = os.path.relpath(full, folder).replace(os.sep, "/")
                arc = (root_name + "/" + rel) if root_name else rel
                info = zipfile.ZipInfo(arc, date_time=(2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 3  # Unix: keeps the mode below
                mode = 0o755 if rel in executables else 0o644
                info.external_attr = (stat.S_IFREG | mode) << 16
                with open(full, "rb") as f:
                    z.writestr(info, f.read(), compresslevel=9)
                count += 1
    return count


def same_folder(a, b):
    """True when both paths are the same folder (Windows runners use short
    8.3 names for the temp folder, so the text may differ)."""
    try:
        return os.path.samefile(a, b)
    except OSError:
        return os.path.normcase(os.path.realpath(a)) == os.path.normcase(os.path.realpath(b))


def cmd_mcpb(args):
    platform = args.platform
    node_platform, exe = PLATFORMS[platform]
    binary = os.path.abspath(args.binary)
    if not os.path.isfile(binary):
        fail("no such file: " + binary)
    version = args.version or pubspec_version()
    display = args.display or "ClipForge %s (build %s)" % (version, args.build)
    fonts_dir = os.path.abspath(args.fonts or os.path.join(ROOT, "assets", "fonts"))
    for font in REQUIRED_FONTS:
        if not os.path.isfile(os.path.join(fonts_dir, font)):
            fail("%s is missing from %s" % (font, fonts_dir))
    icon = os.path.abspath(args.icon or os.path.join(
        ROOT, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset", "app_icon_256.png"))

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)
    stage = tempfile.mkdtemp(prefix="clipforge-mcpb-")
    try:
        server = os.path.join(stage, "server")
        os.makedirs(os.path.join(server, "fonts"))
        staged_binary = os.path.join(server, exe)
        shutil.copy2(binary, staged_binary)
        os.chmod(staged_binary, 0o755)
        for name in sorted(os.listdir(fonts_dir)):
            if name.lower().endswith((".ttf", ".txt")):
                shutil.copy2(os.path.join(fonts_dir, name), os.path.join(server, "fonts", name))
        guide = os.path.join(ROOT, "claude", "CLAUDE.md")
        if os.path.isfile(guide):
            shutil.copy2(guide, os.path.join(server, "CLAUDE.md"))
        has_icon = os.path.isfile(icon)
        if has_icon:
            shutil.copy2(icon, os.path.join(stage, "icon.png"))
        else:
            print("note: no icon at %s; the extension gets the default icon" % icon)

        # The tool list: from the program itself when it runs on this
        # computer (it always does in CI, which builds it for its own
        # system); otherwise from the source.
        status = None
        if args.no_run:
            tools = tool_names_from_source()
        else:
            tools, status = tools_from_binary(staged_binary)
            source = {t["name"] for t in tool_names_from_source()}
            listed = {t["name"] for t in tools}
            if source != listed:
                fail("the program's tools differ from lib/mcp/tools.dart: %s" %
                     sorted(source ^ listed))
            found = (status or {}).get("fontsDir") or ""
            if not same_folder(found, os.path.join(server, "fonts")):
                fail("the program in the bundle did not find the bundle's fonts (fontsDir: %r)" % found)
            shown = ((status or {}).get("build") or {}).get("version")
            if shown and shown != version:
                fail("the program says version %s, the bundle %s" % (shown, version))

        manifest = make_manifest(platform, version, display, tools)
        if not has_icon:
            del manifest["icon"]
        with open(os.path.join(stage, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)
            f.write("\n")
        problems = validate_manifest(manifest, stage)
        if problems:
            fail("manifest.json is not valid:\n  " + "\n  ".join(problems))

        out = os.path.join(out_dir, "ClipForge-%s-build%s-claude-%s.mcpb" % (version, args.build, platform))
        if os.path.exists(out):
            os.remove(out)
        count = zip_folder(stage, out, executables=("server/" + exe,))
    finally:
        shutil.rmtree(stage, ignore_errors=True)

    check_mcpb(out, exe)
    print("%s (%d files, %.1f MB, %d tools, %s)" % (
        out, count, os.path.getsize(out) / 1e6, len(tools),
        "tools read from the program" if status is not None else "tools read from the source"))
    return out


def check_mcpb(path, exe):
    """Reads the finished file back: the zip opens, manifest.json parses and
    is valid against the unpacked files, the program is marked executable."""
    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad:
            fail("damaged zip entry: " + bad)
        names = z.namelist()
        if "manifest.json" not in names:
            fail("manifest.json must be at the top of the bundle")
        tmp = tempfile.mkdtemp(prefix="clipforge-mcpb-check-")
        try:
            z.extractall(tmp)
            with open(os.path.join(tmp, "manifest.json"), encoding="utf-8") as f:
                manifest = json.load(f)
            problems = validate_manifest(manifest, tmp)
            for font in REQUIRED_FONTS:
                if "server/fonts/" + font not in names:
                    problems.append("missing server/fonts/" + font)
            mode = (z.getinfo("server/" + exe).external_attr >> 16) & 0o777
            if mode != 0o755:
                problems.append("server/%s is not marked executable (mode %o)" % (exe, mode))
            if problems:
                fail("the finished bundle is not valid:\n  " + "\n  ".join(problems))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


def read_skill(folder):
    """Returns (name, description, body lines, problems) of a skill folder."""
    problems = []
    path = os.path.join(folder, "SKILL.md")
    if not os.path.isfile(path):
        return None, None, [], ["no SKILL.md in " + folder]
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
    if not m:
        return None, None, [], ["SKILL.md must start with a --- frontmatter block"]
    front, body = m.group(1), m.group(2)
    fields = {}
    key = None
    for line in front.splitlines():
        fm = re.match(r"([a-z-]+):\s*(.*)$", line)
        if fm:
            key = fm.group(1)
            fields[key] = fm.group(2).strip()
        elif key and line.startswith(" "):
            fields[key] = (fields[key] + " " + line.strip()).strip()
    name = fields.get("name", "")
    description = fields.get("description", "").lstrip(">|-").strip()
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name) or len(name) > 64:
        problems.append("name must be lowercase letters, digits and hyphens (max 64): %r" % name)
    if name != os.path.basename(os.path.normpath(folder)):
        problems.append("the folder must be named like the skill (%s)" % name)
    if not description or len(description) > 1024:
        problems.append("description is required (max 1024 characters, now %d)" % len(description))
    lines = body.splitlines()
    if len(lines) > 500:
        problems.append("SKILL.md body is %d lines; keep it under 500" % len(lines))
    # Every reference file the skill points at must be there.
    for ref in sorted(set(re.findall(r"\]\(([A-Za-z0-9_./-]+\.md)\)", text))):
        if not os.path.isfile(os.path.join(folder, ref)):
            problems.append("SKILL.md links to a missing file: " + ref)
    return name, description, lines, problems


def cmd_skill(args):
    folder = os.path.abspath(args.folder or os.path.join(ROOT, "claude", "skill", "clipforge-editing"))
    name, _, lines, problems = read_skill(folder)
    if problems:
        fail("the skill is not valid:\n  " + "\n  ".join(problems))
    version = args.version or pubspec_version()
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "ClipForge-%s-claude-skill.zip" % version)
    if os.path.exists(out):
        os.remove(out)
    # Claude's "Upload a skill" expects the skill FOLDER at the top of the
    # zip (clipforge-editing/SKILL.md), not the files themselves.
    count = zip_folder(folder, out, root_name=name)
    with zipfile.ZipFile(out) as z:
        names = z.namelist()
        if name + "/SKILL.md" not in names or any(not n.startswith(name + "/") for n in names):
            fail("the skill zip must hold exactly one folder, %s/" % name)
    print("%s (%d files, SKILL.md body %d lines)" % (out, count, len(lines)))
    return out


def main():
    ap = argparse.ArgumentParser(description="Build the ClipForge Claude Desktop extension (.mcpb) and the skill zip.")
    sub = ap.add_subparsers(dest="what", required=True)
    m = sub.add_parser("mcpb", help="the Claude Desktop extension")
    m.add_argument("--binary", required=True, help="the built clipforge-mcp / clipforge-mcp.exe")
    m.add_argument("--platform", required=True, choices=sorted(PLATFORMS))
    m.add_argument("--version", help="app version (default: pubspec.yaml)")
    m.add_argument("--build", default="0", help="build number (the CI run number)")
    m.add_argument("--display", help='the full version line, e.g. "ClipForge 1.9.0 (build 32) · 17 Nov 2026, 04:51 UTC · 097beac"')
    m.add_argument("--fonts", help="folder with the title fonts (default: assets/fonts)")
    m.add_argument("--icon", help="a PNG icon (default: the app icon, 256 px)")
    m.add_argument("--out", default="dist", help="output folder (default: dist)")
    m.add_argument("--no-run", action="store_true",
                   help="do not start the program (when it was built for another system); the tool list then comes from the source")
    m.set_defaults(run=cmd_mcpb)
    s = sub.add_parser("skill", help="the skill zip")
    s.add_argument("--folder", help="the skill folder (default: claude/skill/clipforge-editing)")
    s.add_argument("--version", help="app version (default: pubspec.yaml)")
    s.add_argument("--out", default="dist", help="output folder (default: dist)")
    s.set_defaults(run=cmd_skill)
    args = ap.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
