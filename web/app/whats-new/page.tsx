import type { Metadata } from "next";
import Link from "next/link";
import { PageHead } from "@/components/Chrome";
import { Rich } from "@/components/Rich";
import { changelog } from "@/lib/content";

export const metadata: Metadata = {
  title: "What's new",
  description: "What changed in each version of ClipForge, newest first.",
};

export default function WhatsNew() {
  return (
    <>
      <PageHead eyebrow="What's new" title="What's new in ClipForge">
        <p className="lede">
          Newest first. The version you have is in <b>Help</b> &gt; <b>About ClipForge</b>, and at the bottom of the
          project list. From version 1.12 on the app <Link href="/help/updates">updates itself</Link>.
        </p>
      </PageHead>
      <div className="wrap">
        {changelog.map((v) => (
          <section className="release" key={v.version} id={`v${v.version}`} aria-labelledby={`v${v.version}-h`}>
            <div className="ver">
              <h2 id={`v${v.version}-h`}>{v.version}</h2>
              {v.date ? <p>{v.date}</p> : null}
            </div>
            <div className="body">
              <Rich blocks={v.body} heading="h3" />
            </div>
          </section>
        ))}
      </div>
    </>
  );
}
