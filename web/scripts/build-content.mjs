#!/usr/bin/env node
// Runs before every build (and before dev, lint). It reads the app's own
// files from ../video-editor and writes what the pages need:
//
//   content/generated/help.json        every help article (from help_en.md)
//   content/generated/changelog.json   What's new (from CHANGELOG.md)
//   content/generated/features.json    the feature log (from FEATURES.md)
//   content/generated/shots.json       size and alt text of every screenshot used
//   content/generated/version.json     the current version
//   content/generated/links.json       the outside addresses, from
//                                      ../video-editor/tool/ci/links.json (the ONE
//                                      place they are written; the app reads the same)
//   public/help-index.json             the search index for the Help page
//   public/shots/*.png                 ONLY the screenshots named in content/shots.json
//
// Nothing here needs the network, except the optional look at GitHub for the
// newest version, which gives up quietly after a few seconds. Pass --offline
// (or set CLIPFORGE_OFFLINE=1) to skip it.
//
// Standard library only.
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseChangelog, parseFeatures, parseHelp } from "./markdown.mjs";

const WEB = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const APP = resolve(WEB, "..", "video-editor");
const GENERATED = join(WEB, "content", "generated");
const SHOTS_OUT = join(WEB, "public", "shots");
const SHOTS_IN = join(APP, "docs", "screenshots");
const MAX_LOCAL_VIDEO = 5 * 1024 * 1024;

function fail(message) {
  console.error("\nbuild-content: " + message + "\n");
  process.exit(1);
}

function read(path) {
  if (!existsSync(path)) fail("cannot find " + path + ". The site is built from the app's files in ../video-editor.");
  return readFileSync(path, "utf8");
}

function writeJson(path, data) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(data));
}

function pngSize(path) {
  const b = readFileSync(path);
  if (b.length < 24 || b.toString("ascii", 1, 4) !== "PNG") fail(path + " is not a PNG file.");
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
}

// --- The outside addresses ---------------------------------------------------
// One file for the app, its release tools and this site: change the site's
// address or the product's home there and nowhere else.

const linksFile = JSON.parse(read(join(APP, "tool", "ci", "links.json")));
const site = String(linksFile.site || "").replace(/\/+$/, "");
if (!/^https:\/\/[^/\s]+$/.test(site)) fail("links.json: 'site' must be an https address without a path.");
const full = (value) => (String(value).startsWith("/") ? site + value : String(value));
const links = { site };
for (const [name, value] of Object.entries(linksFile.links || {})) links[name] = full(value);
for (const name of ["download", "feedback_api", "feedback_page", "help", "privacy"])
  if (!/^https:\/\//.test(links[name] || "")) fail("links.json: '" + name + "' is missing or not an https address.");
if (!/^https:\/\/github\.com\/[^/\s]+\/[^/\s]+$/.test(linksFile.repository || ""))
  fail("links.json: 'repository' must be the project's address on GitHub.");
const REPO = linksFile.repository.replace("https://github.com/", "");
writeJson(join(GENERATED, "links.json"), {
  links,
  claudePage: full(linksFile.claude_page || "/claude"),
  repository: linksFile.repository,
  repo: REPO,
  oldPages: String(linksFile.old_pages || "").replace(/\/+$/, "") + "/",
});

// --- Help, What's new, Features --------------------------------------------

const help = parseHelp(read(join(APP, "assets", "help", "help_en.md")));
if (help.length < 10) fail("help_en.md gave only " + help.length + " articles; has its format changed?");
writeJson(join(GENERATED, "help.json"), help.map(({ text, ...rest }) => ({ ...rest, summary: text.slice(0, 180) })));
writeJson(
  join(WEB, "public", "help-index.json"),
  help.map((a) => ({ id: a.id, title: a.title, section: a.section, keywords: a.keywords.join(" "), text: a.text })),
);

const changelog = parseChangelog(read(join(APP, "CHANGELOG.md")));
if (!changelog.length) fail("CHANGELOG.md has no version sections.");
writeJson(join(GENERATED, "changelog.json"), changelog);

const features = parseFeatures(read(join(APP, "docs", "FEATURES.md")));
if (features.sections.length < 5) fail("FEATURES.md gave only " + features.sections.length + " sections.");
writeJson(join(GENERATED, "features.json"), features);

// --- Screenshots: copy only the ones the pages use --------------------------

const registry = JSON.parse(read(join(WEB, "content", "shots.json")));
rmSync(SHOTS_OUT, { recursive: true, force: true });
mkdirSync(SHOTS_OUT, { recursive: true });
const shots = {};
let bytes = 0;
for (const [name, alt] of Object.entries(registry)) {
  if (name.startsWith("//")) continue;
  if (!/^[a-z0-9_-]+$/i.test(name)) fail("content/shots.json: '" + name + "' is not a plain screenshot name.");
  if (typeof alt !== "string" || alt.trim().length < 15) fail("content/shots.json: '" + name + "' needs a real description (alt text).");
  const from = join(SHOTS_IN, name + ".png");
  if (!existsSync(from)) fail("content/shots.json names '" + name + "', but " + from + " does not exist.");
  copyFileSync(from, join(SHOTS_OUT, name + ".png"));
  bytes += statSync(from).size;
  shots[name] = { ...pngSize(from), alt: alt.trim() };
}
writeJson(join(GENERATED, "shots.json"), shots);

// --- Examples: check what the data file points at ---------------------------

const examples = JSON.parse(read(join(WEB, "content", "examples.json")));
if (!Array.isArray(examples.examples)) fail("content/examples.json needs an 'examples' list.");
for (const ex of examples.examples) {
  const where = "content/examples.json, '" + (ex.id || ex.title || "?") + "': ";
  for (const key of ["id", "title", "description"]) if (!ex[key]) fail(where + "'" + key + "' is missing.");
  if (!Array.isArray(ex.done) || !ex.done.length) fail(where + "'done' must list what was done.");
  for (const key of ["before", "after", "poster"]) {
    if (ex[key] && !shots[ex[key]]) fail(where + "'" + key + "' is '" + ex[key] + "', which is not in content/shots.json.");
  }
  if (ex.video) {
    if (/^https:\/\//.test(ex.video)) continue;
    if (!ex.video.startsWith("/media/")) fail(where + "'video' must be an https:// address or a file under /media/ (web/public/media).");
    const file = join(WEB, "public", ex.video);
    if (!existsSync(file)) fail(where + "the video " + ex.video + " is not in web/public" + ex.video + ".");
    if (statSync(file).size > MAX_LOCAL_VIDEO)
      fail(where + ex.video + " is larger than 5 MB. Put big videos somewhere else and use their https:// address.");
  }
}

// --- Version ----------------------------------------------------------------

async function newestRelease() {
  if (process.argv.includes("--offline") || process.env.CLIPFORGE_OFFLINE) return null;
  try {
    const res = await fetch("https://api.github.com/repos/" + REPO + "/releases/latest", {
      headers: { Accept: "application/vnd.github+json" },
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) return null;
    const tag = String((await res.json()).tag_name || "").replace(/^v/, "");
    return /^\d+(\.\d+){1,3}$/.test(tag) ? tag : null;
  } catch {
    return null;
  }
}

const fromGitHub = await newestRelease();
const version = { version: fromGitHub || changelog[0].version, from: fromGitHub ? "github" : "changelog" };
writeJson(join(GENERATED, "version.json"), version);

const left = readdirSync(SHOTS_OUT).length;
console.log(
  "build-content: " + help.length + " help articles, " + changelog.length + " versions, " +
    features.sections.length + " feature groups, " + left + " screenshots (" + (bytes / 1048576).toFixed(1) +
    " MB), version " + version.version + " (" + version.from + ").",
);
