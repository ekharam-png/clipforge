import type { Metadata } from "next";
import Link from "next/link";
import { PageHead } from "@/components/Chrome";
import { FeedbackForm } from "@/components/FeedbackForm";
import { ISSUES_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Feedback",
  description: "Tell the maker of ClipForge about a problem, an idea, something you liked, or ask a question.",
};

export default function Feedback() {
  return (
    <>
      <PageHead eyebrow="Feedback" title="Tell us what you think">
        <p className="lede">
          A problem, an idea, something you liked, a question: all welcome. A person reads every message.
        </p>
      </PageHead>
      <div className="wrap">
        <section className="band" aria-label="Feedback form">
          <noscript>
            <p className="note">
              This form needs JavaScript to send. Without it, you can <a href={ISSUES_URL}>write on GitHub</a> instead.
            </p>
          </noscript>
          <FeedbackForm />
          <p className="small" style={{ marginTop: 26, maxWidth: "42em" }}>
            Reporting a problem? In the app, <b>Help</b> &gt; <b>Copy version info</b> copies exactly which build you
            have; paste it into the message. What happens to a message is on the <Link href="/privacy">privacy page</Link>
            . If you use GitHub, you can also <a href={ISSUES_URL}>open an issue</a> there (that is public).
          </p>
        </section>
      </div>
    </>
  );
}
