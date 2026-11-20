import type { Metadata } from "next";
import Link from "next/link";
import { PageHead } from "@/components/Chrome";
import { HelpSearch } from "@/components/HelpSearch";
import { help, helpSections } from "@/lib/content";

export const metadata: Metadata = {
  title: "Help",
  description: "Every help article from the ClipForge app, with a search.",
};

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

export default function Help() {
  const sections = helpSections();
  return (
    <>
      <PageHead eyebrow="Help" title="Help">
        <p className="lede">
          The same {help.length} short articles as behind the <b>?</b> button in the app. Search, or pick a topic.
        </p>
        <HelpSearch />
      </PageHead>
      <div className="wrap">
        <nav aria-label="Help topics">
          {sections.map((s) => (
            <section className="helpsec" key={s.name} id={slug(s.name)} aria-labelledby={`${slug(s.name)}-h`}>
              <h2 id={`${slug(s.name)}-h`}>{s.name}</h2>
              <ul className="topics">
                {s.articles.map((a) => (
                  <li key={a.id}>
                    <Link href={`/help/${a.id}`}>{a.title}</Link>
                    {a.comingLater ? <span className="later">coming later</span> : null}
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </nav>
        <p className="small" style={{ marginTop: 10 }}>
          New here? Start with the <Link href="/walkthrough">walk-through</Link>. Did not find it?{" "}
          <Link href="/feedback">Ask a question</Link>.
        </p>
      </div>
    </>
  );
}
