"use client";

import Link from "next/link";
import { useEffect, useId, useMemo, useRef, useState } from "react";

import { search, type Entry } from "../lib/search.ts";

/**
 * Search over the help articles, in the browser. The index is one small file
 * made when the site is built (/help-index.json); nothing typed here leaves
 * the visitor's device.
 */
export function HelpSearch() {
  const id = useId();
  const [query, setQuery] = useState("");
  const [index, setIndex] = useState<Entry[] | null>(null);
  const [failed, setFailed] = useState(false);
  const asked = useRef(false);

  const load = () => {
    if (asked.current) return;
    asked.current = true;
    fetch("/help-index.json")
      .then((r) => (r.ok ? r.json() : Promise.reject()))
      .then((data: Entry[]) => setIndex(data))
      .catch(() => setFailed(true));
  };

  useEffect(() => {
    const q = new URLSearchParams(window.location.search).get("q");
    if (q) {
      setQuery(q.slice(0, 80));
      load();
    }
  }, []);

  const hits = useMemo(() => (index ? search(index, query) : []), [index, query]);
  const typed = query.trim().length > 0;

  return (
    <div className="search" role="search">
      <label htmlFor={id}>Search the help</label>
      <input
        id={id}
        className="field"
        type="search"
        value={query}
        placeholder="For example: music, captions, slow motion"
        autoComplete="off"
        spellCheck={false}
        maxLength={80}
        onFocus={load}
        onChange={(e) => {
          load();
          setQuery(e.target.value);
        }}
      />
      <p className="count" aria-live="polite">
        {!typed
          ? ""
          : failed
            ? "The search could not be loaded. The list of topics below still works."
            : !index
              ? "Loading…"
              : hits.length
                ? `${hits.length} ${hits.length === 1 ? "topic" : "topics"} found`
                : "Nothing found. Try another word, or one word less."}
      </p>
      {typed && hits.length ? (
        <ul className="results">
          {hits.map(({ entry, snippet }) => (
            <li key={entry.id}>
              <Link href={`/help/${entry.id}`}>
                <span className="rsec">{entry.section}</span>
                <br />
                <span className="rt">{entry.title}</span>
                <span className="rs">{snippet}</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : null}
      {typed && index && !hits.length ? (
        <p className="small">
          Still stuck? <Link href="/feedback">Ask a question</Link> and it may become a help page.
        </p>
      ) : null}
    </div>
  );
}
