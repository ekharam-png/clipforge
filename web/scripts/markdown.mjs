// A small, safe Markdown reader for the three files the site is built from.
// It never produces HTML: it produces plain data (blocks and inline pieces)
// that components/Rich.tsx turns into elements, so nothing in the source
// files can inject markup.
//
// Blocks:  { t: "p", c }  { t: "h", c }  { t: "ul" | "ol", items: [{ c, sub? }] }
// Inline:  { t: "text" | "b" | "code", v }  { t: "a", v, href }

const INLINE = /`([^`\n]+)`|\*\*(?=\S)(.+?)(?<=\S)\*\*|\[([^\]\n]+)\]\(([^()\s]+)\)/g;

export function inline(text) {
  const out = [];
  let pos = 0;
  for (const m of text.matchAll(INLINE)) {
    if (m.index > pos) out.push({ t: "text", v: text.slice(pos, m.index) });
    if (m[1] !== undefined) out.push({ t: "code", v: m[1] });
    else if (m[2] !== undefined) out.push({ t: "b", v: m[2].replace(/`/g, "") });
    else if (/^(https?:\/\/|#|\/)/.test(m[4])) out.push({ t: "a", v: m[3], href: m[4] });
    else out.push({ t: "text", v: m[3] });
    pos = m.index + m[0].length;
  }
  if (pos < text.length) out.push({ t: "text", v: text.slice(pos) });
  return out;
}

export function plain(text) {
  return text
    .replace(INLINE, (_, code, bold, label) => code ?? bold ?? label)
    .replace(/\s+/g, " ")
    .trim();
}

const BULLET = /^(\s*)(?:-|(\d+)\.)\s+(.*)$/;

export function blocks(text) {
  const out = [];
  let para = [];
  let list = null;
  const flushPara = () => {
    if (para.length) out.push({ t: "p", c: inline(para.join(" ")) });
    para = [];
  };
  const flushList = () => {
    if (list) out.push(list);
    list = null;
  };
  for (const raw of text.replace(/\r/g, "").split("\n")) {
    const line = raw.replace(/\s+$/, "");
    if (!line.trim()) {
      flushPara();
      continue;
    }
    const h = /^#{2,4}\s+(.*)$/.exec(line);
    if (h) {
      flushPara();
      flushList();
      out.push({ t: "h", c: inline(h[1]) });
      continue;
    }
    const b = BULLET.exec(line);
    if (b) {
      flushPara();
      const kind = b[2] ? "ol" : "ul";
      const nested = b[1].length >= 2 && list && list.items.length > 0;
      if (nested) {
        const parent = list.items[list.items.length - 1];
        if (!parent.sub || parent.sub.t !== kind) parent.sub = { t: kind, items: [] };
        parent.sub.items.push({ c: inline(b[3]) });
      } else {
        if (!list || list.t !== kind) {
          flushList();
          list = { t: kind, items: [] };
        }
        list.items.push({ c: inline(b[3]) });
      }
      continue;
    }
    if (list && /^\s{2,}\S/.test(raw) && !para.length) {
      // A wrapped line that continues the last bullet.
      const items = list.items;
      const last = items[items.length - 1];
      const target = last.sub ? last.sub.items[last.sub.items.length - 1] : last;
      target.c = target.c.concat(inline(" " + line.trim()));
      continue;
    }
    flushList();
    para.push(line.trim());
  }
  flushPara();
  flushList();
  return out;
}

// --- help_en.md -----------------------------------------------------------

export function parseHelp(source) {
  const articles = [];
  const parts = source.replace(/\r/g, "").split(/^=== /m).slice(1);
  for (const part of parts) {
    const nl = part.indexOf("\n");
    const id = part.slice(0, nl).trim();
    const rest = part.slice(nl + 1);
    const gap = rest.search(/\n\s*\n/);
    const head = gap < 0 ? rest : rest.slice(0, gap);
    const body = gap < 0 ? "" : rest.slice(gap);
    const meta = {};
    for (const line of head.split("\n")) {
      const m = /^([a-z]+):\s*(.*)$/.exec(line);
      if (m) meta[m[1]] = m[2].trim();
    }
    if (!/^[a-z0-9-]+$/.test(id) || !meta.title) continue;
    const list = (s) => (s ? s.split(",").map((x) => x.trim()).filter(Boolean) : []);
    articles.push({
      id,
      title: meta.title,
      section: meta.section || "Other",
      keywords: list(meta.keywords),
      related: list(meta.related),
      comingLater: meta.status === "coming-later",
      body: blocks(body),
      text: plain(body.replace(/^#{2,4}\s+/gm, "").replace(/^\s*(?:-|\d+\.)\s+/gm, "")),
    });
  }
  const ids = new Set(articles.map((a) => a.id));
  for (const a of articles) a.related = a.related.filter((r) => ids.has(r));
  return articles;
}

// --- CHANGELOG.md ---------------------------------------------------------

export function parseChangelog(source) {
  const versions = [];
  const parts = source.replace(/\r/g, "").split(/^## /m).slice(1);
  for (const part of parts) {
    const nl = part.indexOf("\n");
    const heading = part.slice(0, nl < 0 ? undefined : nl).trim();
    const m = /^(\d+(?:\.\d+)+)\s*(?:[–—-]\s*(.*))?$/.exec(heading);
    if (!m) continue;
    versions.push({
      version: m[1],
      date: (m[2] || "").trim(),
      body: blocks(nl < 0 ? "" : part.slice(nl + 1)),
    });
  }
  return versions;
}

// --- FEATURES.md ----------------------------------------------------------

function cells(line) {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split(/(?<!\\)\|/)
    .map((c) => c.trim());
}

// Where a feature exists, as one of three marks plus the original words.
export function whereMark(where, section, feature) {
  const w = (where || "").toLowerCase();
  if (w) {
    if (/^both/.test(w)) return "both";
    if (/^(phone|android)/.test(w)) return "phone";
    if (/^(computer|windows|mac)/.test(w)) return "computer";
  }
  const f = feature.toLowerCase();
  if (/android/.test(f) && /windows|mac/.test(f)) return "both";
  if (/claude control/i.test(section)) return "computer";
  if (/\((computers?|windows|mac)[^)]*\)|keyboard|menu bar|j \/ k \/ l|arrow keys|graphics card|drag and drop/.test(f))
    return "computer";
  if (/\((phones?|android)[^)]*\)|^android|\(android\)|screen off|share sheet|smooth preview/.test(f)) return "phone";
  return "both";
}

export function parseFeatures(source) {
  const sections = [];
  const planned = [];
  const parts = source.replace(/\r/g, "").split(/^## /m).slice(1);
  for (const part of parts) {
    const lines = part.split("\n");
    const rawTitle = lines[0].trim();
    const title = rawTitle.replace(/\s*\(\d+(?:\.\d+)+\)\s*$/, "");
    if (/^planned$/i.test(title)) {
      for (const l of lines.slice(1)) {
        const b = /^- (.*)$/.exec(l);
        if (b) planned.push(inline(b[1]));
      }
      continue;
    }
    const table = lines.filter((l) => l.trim().startsWith("|"));
    if (table.length < 3) continue;
    const head = cells(table[0]).map((h) => h.toLowerCase());
    const col = (name) => head.findIndex((h) => h.startsWith(name));
    const iFeature = col("feature");
    const iSince = col("since");
    const iWhere = col("where");
    const iWhat = col("what");
    const intro = lines
      .slice(1)
      .filter((l) => l.trim() && !l.trim().startsWith("|"))
      .join(" ")
      .trim();
    const rows = [];
    for (const line of table.slice(2)) {
      const c = cells(line);
      const feature = c[iFeature] || "";
      if (!feature) continue;
      const where = iWhere >= 0 ? c[iWhere] || "" : "";
      const note = /^(both|computer|phone)\s*\((.*)\)\s*$/i.exec(where);
      rows.push({
        feature: inline(feature),
        since: c[iSince] || "",
        where: whereMark(where, title, feature),
        whereNote: note ? note[2] : /^(both|computer|phone)$/i.test(where) ? "" : where,
        what: inline(c[iWhat] || ""),
      });
    }
    sections.push({ title, intro: intro ? inline(intro) : null, rows });
  }
  return { sections, planned };
}
