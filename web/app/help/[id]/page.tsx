import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Rich } from "@/components/Rich";
import { help, helpArticle } from "@/lib/content";

// One page per help article, all made when the site is built.
export const dynamicParams = false;

export function generateStaticParams() {
  return help.map((a) => ({ id: a.id }));
}

type Props = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const article = helpArticle((await params).id);
  if (!article) return {};
  return { title: `${article.title} (Help)`, description: article.summary };
}

export default async function HelpArticlePage({ params }: Props) {
  const article = helpArticle((await params).id);
  if (!article) notFound();
  const related = article.related.map(helpArticle).filter((a) => a !== undefined);
  return (
    <div className="wrap">
      <article className="article pagehead" aria-labelledby="title">
        <p className="crumbs">
          <Link href="/help">Help</Link> <span aria-hidden="true">›</span> {article.section}
        </p>
        <h1 id="title">{article.title}</h1>
        {article.comingLater ? (
          <p className="note" style={{ marginTop: 18 }}>
            This is not in ClipForge yet. It is planned for a later version.
          </p>
        ) : null}
        <div style={{ marginTop: 22 }}>
          <Rich blocks={article.body} heading="h2" />
        </div>
        {related.length ? (
          <aside className="related" aria-labelledby="related-h">
            <h2 id="related-h">Related</h2>
            <ul>
              {related.map((r) => (
                <li key={r.id}>
                  <Link href={`/help/${r.id}`}>{r.title}</Link>
                </li>
              ))}
            </ul>
          </aside>
        ) : null}
        <p className="small" style={{ marginTop: 26 }}>
          <Link href="/help">All help topics</Link> · Was this unclear? <Link href="/feedback">Tell us</Link>.
        </p>
      </article>
    </div>
  );
}
