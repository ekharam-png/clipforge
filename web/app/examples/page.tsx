import type { Metadata } from "next";
import Link from "next/link";
import { PageHead } from "@/components/Chrome";
import { Shot } from "@/components/Shot";
import { examples, shots } from "@/lib/content";

export const metadata: Metadata = {
  title: "Examples",
  description: "What people make with ClipForge: a family video, a podcast, a sport highlight and a vertical short.",
};

// The whole gallery comes from content/examples.json. See web/README.md for
// how to add an example or a real video.
const COLOURS = ["title", "music", "video", "caption", "photo"];

export default function Examples() {
  return (
    <>
      <PageHead eyebrow="Examples" title="What you can make">
        <p className="lede">Four everyday videos, and what was done to make each one.</p>
      </PageHead>
      <div className="wrap">
        <section className="band" aria-label="Examples">
          <div className="note" role="note">
            <p>{examples.notice}</p>
          </div>
          {examples.examples.map((ex, i) => (
            <article
              className="example"
              key={ex.id}
              id={ex.id}
              aria-labelledby={`${ex.id}-h`}
              style={{ "--c": `var(--c-${COLOURS[i % COLOURS.length]})` } as React.CSSProperties}
            >
              {ex.kind ? <p className="kind">{ex.kind}</p> : null}
              <h2 id={`${ex.id}-h`}>{ex.title}</h2>
              <p className="prose">{ex.description}</p>

              {ex.video ? (
                <video
                  controls
                  preload="none"
                  playsInline
                  poster={ex.poster && shots[ex.poster] ? `/shots/${ex.poster}.png` : undefined}
                  aria-label={`Video: ${ex.title}`}
                >
                  <source src={ex.video} />
                  <a href={ex.video}>Watch the video</a>
                </video>
              ) : null}

              {ex.before || ex.after ? (
                <div className="ba">
                  {ex.before ? (
                    <div>
                      <p className="label">{ex.beforeLabel || "Before"}</p>
                      <Shot name={ex.before} sizes="(max-width: 700px) 100vw, 500px" />
                    </div>
                  ) : null}
                  {ex.after ? (
                    <div>
                      <p className="label">{ex.afterLabel || "After"}</p>
                      <Shot name={ex.after} sizes="(max-width: 700px) 100vw, 500px" />
                    </div>
                  ) : null}
                </div>
              ) : null}

              <h3 className="sr-only">What was done</h3>
              <ul className="done">
                {ex.done.map((d) => (
                  <li key={d}>{d}</li>
                ))}
              </ul>
              {ex.link ? (
                <p style={{ margin: 0 }}>
                  {ex.link.href.startsWith("/") ? (
                    <Link href={ex.link.href}>{ex.link.label}</Link>
                  ) : (
                    <a href={ex.link.href}>{ex.link.label}</a>
                  )}
                </p>
              ) : null}
            </article>
          ))}
          <div className="note">
            <p>
              Made something with ClipForge that you would like to see here? <Link href="/feedback">Write to us</Link>{" "}
              and say where the video can be watched.
            </p>
          </div>
        </section>
      </div>
    </>
  );
}
