// The help search: plain functions, used in the browser by components/HelpSearch.tsx.

export type Entry = { id: string; title: string; section: string; keywords: string; text: string };
export type Hit = { entry: Entry; score: number; snippet: string };

const words = (s: string) => s.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);

// One typing mistake is forgiven in words of four letters or more: a wrong,
// missing or extra letter, or two neighbours swapped ("musci").
export function near(a: string, b: string): boolean {
  if (a === b) return true;
  const la = a.length;
  const lb = b.length;
  if (Math.abs(la - lb) > 1) return false;
  let i = 0;
  while (i < la && i < lb && a[i] === b[i]) i++;
  if (la === lb)
    return a.slice(i + 1) === b.slice(i + 1) || (a[i] === b[i + 1] && a[i + 1] === b[i] && a.slice(i + 2) === b.slice(i + 2));
  return la > lb ? a.slice(i + 1) === b.slice(i) : a.slice(i) === b.slice(i + 1);
}

export function search(index: Entry[], query: string): Hit[] {
  const tokens = words(query);
  if (!tokens.length) return [];
  const hits: Hit[] = [];
  for (const entry of index) {
    const title = entry.title.toLowerCase();
    const keys = entry.keywords.toLowerCase();
    const text = entry.text.toLowerCase();
    const titleWords = words(title);
    const keyWords = words(keys);
    let score = 0;
    let all = true;
    for (const t of tokens) {
      let s = 0;
      if (titleWords.some((w) => w.startsWith(t))) s += 12;
      else if (title.includes(t)) s += 8;
      if (keyWords.some((w) => w.startsWith(t))) s += 6;
      if (text.includes(t)) s += 2;
      if (!s && t.length >= 4) {
        const fuzzy = (w: string) => near(w, t) || near(w.slice(0, t.length), t);
        if (titleWords.some(fuzzy)) s += 6;
        else if (keyWords.some(fuzzy)) s += 3;
      }
      if (!s) {
        all = false;
        break;
      }
      score += s;
    }
    if (!all) continue;
    const at = Math.max(0, text.indexOf(tokens[0]));
    const start = Math.max(0, at - 50);
    const snippet = (start > 0 ? "…" : "") + entry.text.slice(start, start + 150).trim() + (entry.text.length > start + 150 ? "…" : "");
    hits.push({ entry, score, snippet });
  }
  return hits.sort((a, b) => b.score - a.score).slice(0, 12);
}
