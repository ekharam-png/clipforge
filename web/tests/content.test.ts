// The small Markdown reader that the pages are built with.
import assert from "node:assert/strict";
import { test } from "node:test";
// @ts-expect-error a plain JavaScript module without types
import { blocks, inline, parseChangelog, parseFeatures, parseHelp, whereMark } from "../scripts/markdown.mjs";

test("inline keeps bold, code and safe links, and nothing else", () => {
  assert.deepEqual(inline("Tap **Export** or `S`, see [here](https://example.org) <b>x</b>"), [
    { t: "text", v: "Tap " },
    { t: "b", v: "Export" },
    { t: "text", v: " or " },
    { t: "code", v: "S" },
    { t: "text", v: ", see " },
    { t: "a", v: "here", href: "https://example.org" },
    { t: "text", v: " <b>x</b>" },
  ]);
  assert.deepEqual(inline("[bad](javascript:alert(1))")[0].t, "text");
});

test("blocks reads paragraphs, headings and nested lists", () => {
  const b = blocks("One\ntwo.\n\n## Head\n\n- a\n  - a1\n- b\n\n1. first\n2. second\n");
  assert.equal(b[0].t, "p");
  assert.equal(b[1].t, "h");
  assert.equal(b[2].t, "ul");
  assert.equal(b[2].items.length, 2);
  assert.equal(b[2].items[0].sub.items[0].c[0].v, "a1");
  assert.equal(b[3].t, "ol");
});

test("help articles, versions and feature tables are read", () => {
  const help = parseHelp("# note\n\n=== first-one\ntitle: First\nsection: A\nkeywords: x, y\nrelated: gone, second\n\nHello **you**.\n\n=== second\ntitle: Second\nsection: A\nstatus: coming-later\n\nLater.\n");
  assert.equal(help.length, 2);
  assert.deepEqual(help[0].related, ["second"]);
  assert.equal(help[0].text, "Hello you.");
  assert.equal(help[1].comingLater, true);

  const log = parseChangelog("# What's new\n\nIntro\n\n## 1.2.0 – 3 May 2026\n\n- One\n\n## 1.1.0 – 1 May 2026\n\n- Zero\n");
  assert.deepEqual(log.map((v: { version: string }) => v.version), ["1.2.0", "1.1.0"]);
  assert.equal(log[0].date, "3 May 2026");

  const f = parseFeatures("# Log\n\n## Speech (1.11.0)\n\nA note.\n\n| Feature | Since | Where | What it does |\n|---|---|---|---|\n| Transcribe | 1.11.0 | Computer | Text. |\n| Lines | 1.11.0 | Both (phones: a sheet) | RTL. |\n\n## Planned\n\n- A thing.\n");
  assert.equal(f.sections[0].title, "Speech");
  assert.deepEqual(f.sections[0].rows.map((r: { where: string }) => r.where), ["computer", "both"]);
  assert.equal(f.sections[0].rows[1].whereNote, "phones: a sheet");
  assert.equal(f.planned.length, 1);
});

test("the phone / computer mark is guessed when a table has no Where column", () => {
  assert.equal(whereMark("", "Timeline", "Keyboard shortcuts"), "computer");
  assert.equal(whereMark("", "Export", "Keeps exporting with the screen off (Android)"), "phone");
  assert.equal(whereMark("", "Platforms", "Android, Windows, macOS apps"), "both");
  assert.equal(whereMark("", "Claude control", "Dry runs"), "computer");
  assert.equal(whereMark("", "Text", "Titles"), "both");
});

test("the help search finds by title, keyword and text, and forgives one typing mistake", async () => {
  const { search, near } = await import("../lib/search.ts");
  const index = [
    { id: "music", title: "Adding music, volume and fades", section: "Music", keywords: "song audio", text: "Tap Music to add a song." },
    { id: "split", title: "Splitting a clip", section: "Editing", keywords: "cut scissors", text: "Split cuts the clip under the playhead." },
    { id: "export", title: "Exporting your video", section: "Export", keywords: "save render", text: "Tap Export. Music is included." },
  ];
  assert.deepEqual(search(index, "music").map((h) => h.entry.id), ["music", "export"]);
  assert.deepEqual(search(index, "musci").map((h) => h.entry.id), ["music"]);
  assert.deepEqual(search(index, "scissors clip").map((h) => h.entry.id), ["split"]);
  assert.deepEqual(search(index, "zebra"), []);
  assert.deepEqual(search(index, "   "), []);
  assert.equal(near("captions", "captoins"), true);
  assert.equal(near("export", "exprt"), true);
  assert.equal(near("export", "import"), false);
});
