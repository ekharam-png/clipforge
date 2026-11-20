import type { Metadata } from "next";
import Link from "next/link";
import { PageHead } from "@/components/Chrome";
import { Mark } from "@/components/Mark";
import { Text } from "@/components/Rich";
import { features, type FeatureSection } from "@/lib/content";
import { REPO_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Features",
  description: "Everything ClipForge can do, grouped by area, with a mark for phone, computer or both.",
};

// The order people look for things in, and one track colour per group. The
// rows themselves come from video-editor/docs/FEATURES.md at build time; a
// group that is new there shows up by itself, after these.
const ORDER: [RegExp, string][] = [
  [/^projects/i, "video"],
  [/^timeline/i, "video"],
  [/^picture/i, "photo"],
  [/^text$/i, "title"],
  [/^sound/i, "music"],
  [/^speech/i, "caption"],
  [/^text window/i, "caption"],
  [/^publishing/i, "title"],
  [/^export/i, "video"],
  [/^help/i, "photo"],
  [/^claude control/i, "music"],
];
// Mostly about how updating and the Claude connection work inside: folded.
const FOLDED = /update|platform|connect to claude/i;

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const rank = (s: FeatureSection) => {
  const i = ORDER.findIndex(([re]) => re.test(s.title));
  return i < 0 ? ORDER.length : i;
};
const colour = (s: FeatureSection) => ORDER.find(([re]) => re.test(s.title))?.[1] ?? "video";

function Rows({ section }: { section: FeatureSection }) {
  return (
    <>
      {section.intro ? (
        <p className="fintro">
          <Text c={section.intro} />
        </p>
      ) : null}
      <ul className="frows">
        {section.rows.map((row, i) => (
          <li key={i}>
            <span className="fname">
              <Text c={row.feature} />
            </span>
            <span className="fwhat">
              <Text c={row.what} />
              {row.whereNote ? <span className="fnote">{row.whereNote}</span> : null}
            </span>
            <span className="fmeta">
              <Mark where={row.where} />
              {row.since ? <span>since {row.since}</span> : null}
            </span>
          </li>
        ))}
      </ul>
    </>
  );
}

export default function Features() {
  const sorted = [...features.sections].sort((a, b) => rank(a) - rank(b));
  const main = sorted.filter((s) => !FOLDED.test(s.title));
  const folded = sorted.filter((s) => FOLDED.test(s.title));
  const total = features.sections.reduce((n, s) => n + s.rows.length, 0);
  return (
    <>
      <PageHead eyebrow="Features" title="Everything ClipForge can do">
        <p className="lede">
          {total} features in {features.sections.length} groups, each with the version it arrived in and a mark for
          where it works. The <Link href="/help">help</Link> explains how to use each one.
        </p>
        <p className="legend">
          <Mark where="both" /> on phones and computers
          <Mark where="computer" /> Windows and Mac only
          <Mark where="phone" /> Android only
        </p>
        <ul className="toc" aria-label="Groups">
          {main.map((s) => (
            <li key={s.title}>
              <a href={`#${slug(s.title)}`}>{s.title}</a>
            </li>
          ))}
          <li>
            <a href="#planned">Planned</a>
          </li>
        </ul>
      </PageHead>

      <div className="wrap">
        <section className="band" aria-label="Feature groups">
          {main.map((s) => (
            <section
              className="fgroup"
              key={s.title}
              id={slug(s.title)}
              aria-labelledby={`${slug(s.title)}-h`}
              style={{ "--c": `var(--c-${colour(s)})` } as React.CSSProperties}
            >
              <h2 id={`${slug(s.title)}-h`}>{s.title}</h2>
              <Rows section={s} />
            </section>
          ))}

          {folded.length ? (
            <>
              <h2 style={{ marginTop: 34 }}>Under the bonnet</h2>
              <p className="h2-note">
                How updates, the installers and the Claude connection work inside. Open a group if you are curious.
              </p>
              {folded.map((s) => (
                <details className="fgroup" key={s.title} id={slug(s.title)}>
                  <summary>
                    {s.title} <span className="small">({s.rows.length})</span>
                  </summary>
                  <Rows section={s} />
                </details>
              ))}
            </>
          ) : null}
        </section>

        <section className="band" id="planned" aria-labelledby="planned-h">
          <h2 id="planned-h">Planned</h2>
          <p className="h2-note">On the list, not built yet. No promises about dates.</p>
          <ul className="prose">
            {features.planned.map((item, i) => (
              <li key={i}>
                <Text c={item} />
              </li>
            ))}
          </ul>
          <p className="small">
            This page is made from the project&rsquo;s own{" "}
            <a href={`${REPO_URL}/blob/main/video-editor/docs/FEATURES.md`}>feature log</a>. Missing something?{" "}
            <Link href="/feedback">Send an idea</Link>.
          </p>
        </section>
      </div>
    </>
  );
}
