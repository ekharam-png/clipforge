import type { Metadata } from "next";
import Link from "next/link";
import { PageHead } from "@/components/Chrome";
import { REPO_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy",
  description:
    "In plain words: ClipForge works offline, your videos stay on your device, and this site uses no cookies and no analytics.",
};

const turnstile = Boolean(process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY);

export default function Privacy() {
  return (
    <>
      <PageHead eyebrow="Privacy" title="Privacy, in plain words">
        <p className="lede">
          Your videos stay on your device. The app works offline. This site has no cookies and no analytics.
        </p>
      </PageHead>
      <div className="wrap">
        <section className="band prose" aria-labelledby="app">
          <h2 id="app">The app</h2>
          <p>
            ClipForge edits and exports on your own phone or computer. Your videos, photos, music and projects are not
            uploaded anywhere, and there is no account and no sign-in.
          </p>
          <p>
            <b>The only thing the app does by itself over the internet is the update check.</b> At most once a day it
            reads one small file from the project&rsquo;s release page on GitHub to see whether a newer version is out.
            Nothing about you or your videos is sent with it. You can switch it off in the Help menu.
          </p>
          <p>The app goes online in these other cases, and only when you ask it to:</p>
          <ul>
            <li>
              <b>Update:</b> when you press Update, it downloads the new version from the same release page.
            </li>
            <li>
              <b>Find free music:</b> what you type in the search goes to Openverse, a public catalogue of free music,
              and a song you choose is downloaded from where it is kept.
            </li>
            <li>
              <b>Language packs for voice to text</b> (computer): downloaded only when you press Download. The
              transcribing itself happens on your computer.
            </li>
            <li>
              <b>Upload pages:</b> after an export, a link can open YouTube&rsquo;s or another site&rsquo;s own upload
              page in your browser. ClipForge itself posts nothing.
            </li>
          </ul>
          <p>
            <b>Claude</b> is separate. If you choose to connect it, Claude changes project files on your computer
            through a small helper. What you write to Claude, and what Claude reads from a project (times, pauses and,
            with voice to text, the words that are said), is handled by Anthropic under Claude&rsquo;s own terms.
            Nothing of this happens unless you set it up. <Link href="/claude">More about Claude</Link>
          </p>
        </section>

        <section className="band prose" aria-labelledby="feedback">
          <h2 id="feedback">Feedback</h2>
          <p>
            A message is sent only when you press <b>Send</b>, and it contains exactly what the form shows: the kind of
            message, your text, and the e-mail address, version and system if you filled them in. Nothing is added
            behind your back: no location, no list of your files, nothing from your videos.
          </p>
          <p>
            The message goes as one e-mail to the person who makes ClipForge, through an e-mail delivery service
            (Resend). The site itself does not keep a copy. Your e-mail address is used only to answer you. To have a
            message deleted, write again and say so.
          </p>
          <p>
            To slow down junk, the site remembers for about ten minutes how many messages came from one internet
            address. That count lives in memory only and is never written down.
          </p>
          {turnstile ? (
            <p>
              The form also shows a small &quot;are you human&quot; check from Cloudflare (Turnstile). It loads only on
              the feedback page, and Cloudflare sees your internet address and some technical details of your browser
              to decide.
            </p>
          ) : null}
        </section>

        <section className="band prose" aria-labelledby="site">
          <h2 id="site">This website</h2>
          <ul>
            <li>
              <b>No cookies.</b> The site sets none, so there is no cookie banner.
            </li>
            <li>
              <b>No analytics, no trackers, no advertising.</b> No visitor counting of any kind is built in.
            </li>
            <li>
              <b>No fonts or scripts from other companies.</b> The pages use the fonts already on your device.
            </li>
            <li>
              <b>The help search runs in your browser.</b> What you type there is not sent anywhere.
            </li>
          </ul>
          <p>Three things you should know about, because other companies are involved:</p>
          <ul>
            <li>
              <b>Hosting.</b> The site is delivered by a hosting company (Vercel). Like every web server, it sees the
              internet address and the page each request asks for, and keeps short technical logs to run the service.
            </li>
            <li>
              <b>The version number.</b> The home page asks GitHub once for the number of the newest version. GitHub
              sees that request, like any visit to its site.
            </li>
            <li>
              <b>Downloads.</b> The download buttons lead to files on GitHub, under GitHub&rsquo;s own privacy terms.
            </li>
          </ul>
          <p>
            The code of this site and of the app is public: <a href={REPO_URL}>read it on GitHub</a>. Questions?{" "}
            <Link href="/feedback">Ask</Link>.
          </p>
        </section>
      </div>
    </>
  );
}
