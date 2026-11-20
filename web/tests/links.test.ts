// The outside addresses come from ONE file, ../video-editor/tool/ci/links.json,
// shared with the app and its release tools. The site must not carry its own
// copy of its address (the app's test suite scans this folder too).
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, join, relative } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const WEB = join(dirname(fileURLToPath(import.meta.url)), "..");
const LINKS = join(WEB, "..", "video-editor", "tool", "ci", "links.json");
const file = JSON.parse(readFileSync(LINKS, "utf8")) as {
  site: string;
  links: Record<string, string>;
  repository: string;
  old_pages: string;
};

test("build-content writes the addresses of links.json for the pages", () => {
  execFileSync(process.execPath, [join(WEB, "scripts", "build-content.mjs"), "--offline"], { stdio: "pipe" });
  const made = JSON.parse(readFileSync(join(WEB, "content", "generated", "links.json"), "utf8"));
  assert.equal(made.links.site, file.site);
  for (const [name, value] of Object.entries(file.links)) {
    assert.equal(made.links[name], value.startsWith("/") ? file.site + value : value);
  }
  assert.deepEqual(Object.keys(made.links).sort(), ["download", "feedback_api", "feedback_page", "help", "privacy", "site"]);
  assert.equal(made.repository, file.repository);
  assert.equal(`https://github.com/${made.repo}`, file.repository);
  assert.equal(made.oldPages, file.old_pages);
  assert.equal(made.claudePage, `${file.site}/claude`);
});

test("the pages the app is told about exist on this site", () => {
  for (const [name, value] of Object.entries(file.links)) {
    assert.ok(value.startsWith("/"), `${name} is a page of this site`);
    const dir = join(WEB, "app", ...value.split("/").filter(Boolean));
    assert.ok(
      existsSync(join(dir, "page.tsx")) || existsSync(join(dir, "route.ts")),
      `links.json says ${name} is ${value}, but app${value} has no page`,
    );
  }
});

test("no file of the site writes the site's address (or the old one) itself", () => {
  const needles = [new URL(file.site).host, new URL(file.old_pages).host];
  const skip = new Set(["node_modules", ".next", "generated", ".vercel", "shots"]);
  const text = new Set([".ts", ".tsx", ".mjs", ".js", ".json", ".md", ".css", ".html", ".txt", ".example", ""]);
  const found: string[] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) {
        if (!skip.has(name)) walk(path);
      } else if (text.has(extname(name)) && statSync(path).size < 2_000_000) {
        const content = readFileSync(path, "utf8");
        for (const needle of needles) if (content.includes(needle)) found.push(`${relative(WEB, path)}: ${needle}`);
      }
    }
  };
  walk(WEB);
  assert.deepEqual(found, [], "read the address from lib/site.ts (LINKS) instead");
});

test("the feedback page shows a note when the app opened it", () => {
  const form = readFileSync(join(WEB, "components", "FeedbackForm.tsx"), "utf8");
  assert.match(form, /q\.get\("source"\) === "app"/);
  assert.match(form, /From the app\./);
});
