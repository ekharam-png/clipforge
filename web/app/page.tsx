import Link from "next/link";
import { Downloads } from "@/components/Downloads";
import { DeviceMark, VersionLive } from "@/components/Live";
import { Shot } from "@/components/Shot";
import { builtVersion } from "@/lib/content";

const css = (c: string) => ({ "--c": `var(--c-${c})` }) as React.CSSProperties;

const WHY = [
  { c: "video", title: "Free", text: "Free to download and free to use, on every system. The source code is open for anyone to read." },
  { c: "music", title: "No subscription", text: "Nothing to sign up for, no account, no trial that runs out, nothing to unlock later." },
  { c: "title", title: "No watermark", text: "Your video is yours. ClipForge puts no logo on it and adds nothing at the end." },
  { c: "photo", title: "Works offline", text: "It edits and exports without the internet. Only the search for free music and the update check go online." },
  { c: "caption", title: "Your videos stay on your device", text: "Nothing is uploaded. ClipForge makes the files; you decide where to post them." },
  { c: "video", title: "Claude can edit for you", text: "On a computer, tell Claude in plain words what you want, and it cuts, cleans up, captions and exports the project." },
];

const TRACKS = [
  { c: "video", name: "Cut", text: "Split, trim, reorder, change the speed, freeze a frame, remove silences. Undo anything, with a history list." },
  { c: "photo", name: "Picture", text: "Wide, upright and square shapes, crop, rotate, a second video in a corner or side by side, filters and fades." },
  { c: "music", name: "Sound", text: "Up to three sound tracks, clean up sound, clearer voices, and a voice recorded separately lined up with the picture." },
  { c: "music", name: "Music", text: "Your own files or a search for free music, fitted to the length of the video, and lowered while someone talks." },
  { c: "title", name: "Text", text: "Titles and captions with fonts for English, Russian and Hebrew, outlines, animations and subtitle files." },
  { c: "caption", name: "Voice to text", text: "On a computer: captions written from what is said, a transcript you can search, gentle removal of “um” and “uh”." },
  { c: "video", name: "Export", text: "Ready-made choices for YouTube, Shorts / Reels / TikTok, Instagram, WhatsApp and podcast audio, several at once." },
];

export default function Home() {
  return (
    <>
      <DeviceMark />
      <div className="hero wrap">
        <h1 className="name">ClipForge</h1>
        <p className="lede">
          ClipForge is a free, simple video editor for family videos, podcast clips and sport clips, on Windows, Mac and
          Android.
        </p>
        <p className="meta">
          <span className="beta">Beta</span>
          <VersionLive built={builtVersion} />
          <span aria-hidden="true">·</span>
          <Link href="/whats-new">What&rsquo;s new</Link>
        </p>

        <div id="download">
          <Downloads />
        </div>

        <div className="hero-shot">
          <Shot
            name="editor_desktop"
            first
            caption="The editor on a computer, with a small test project. The phone version has the same tools."
          />
        </div>
      </div>

      <div className="wrap">
        <section className="band" aria-labelledby="why">
          <h2 id="why">Why ClipForge</h2>
          <div className="grid c3">
            {WHY.map((w) => (
              <div className="card" key={w.title} style={css(w.c)}>
                <h3>{w.title}</h3>
                <p>{w.text}</p>
              </div>
            ))}
          </div>
          <p className="small" style={{ marginTop: 16 }}>
            How Claude fits in is on the <Link href="/claude">Claude page</Link>. What leaves your device, and what does
            not, is on the <Link href="/privacy">privacy page</Link>.
          </p>
        </section>

        <section className="band" aria-labelledby="what">
          <h2 id="what">What it can do</h2>
          <p className="h2-note">One track for each kind of work, like the timeline in the app.</p>
          <ul className="tracks">
            {TRACKS.map((t) => (
              <li key={t.name}>
                <span className="tname" style={css(t.c)}>
                  {t.name}
                </span>
                <span className="tdesc">{t.text}</span>
              </li>
            ))}
          </ul>
          <div className="buttons">
            <Link className="button" href="/walkthrough">
              Your first video in 10 minutes
            </Link>
            <Link className="button quiet" href="/features">
              Every feature
            </Link>
            <Link className="button quiet" href="/examples">
              Examples
            </Link>
          </div>
        </section>

        <section className="band" aria-labelledby="same">
          <div className="split">
            <div className="prose">
              <h2 id="same">The same app on a phone and a computer</h2>
              <p>
                Start on the phone where the videos are, finish on the computer where the screen is big, or the other way
                round. A project packs into one file that you send across, with all its videos, photos and music inside.
              </p>
              <p>
                Every screen has a <b>?</b> button with short help articles and a tour of the editor. The same articles
                are on this site, with a search.
              </p>
              <div className="buttons">
                <Link className="button quiet" href="/help">
                  Read the help
                </Link>
                <Link className="button quiet" href="/feedback">
                  Tell us what you think
                </Link>
              </div>
            </div>
            <Shot name="editor_phone" caption="The editor on a phone." />
          </div>
        </section>
      </div>
    </>
  );
}
