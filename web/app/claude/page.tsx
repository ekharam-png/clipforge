import type { Metadata } from "next";
import Link from "next/link";
import { PageHead } from "@/components/Chrome";
import { Shot } from "@/components/Shot";
import { CLAUDE_SETUP_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Editing with Claude",
  description:
    "On Windows and Mac, Claude can edit your ClipForge projects when you describe what you want: what it means, how it works, what it cannot do, and how to connect it.",
};

const css = (c: string) => ({ "--c": `var(--c-${c})` }) as React.CSSProperties;
// The full, longer setup page that also travels with the downloads.
const FULL_SETUP = CLAUDE_SETUP_URL;

const ASK = [
  "Clean up the podcast: remove the pauses, add captions, and make three short clips.",
  "Cut the silences out of my Podcast project and export it upright.",
  "Before you change anything, tell me how many pauses you would cut and how much shorter the video gets.",
  "Add the title “Summer 2026” at the start of Summer trip, and make the music end with the video.",
  "Find the part where we talk about the recipe and make a 30-second short from it.",
  "Export Bread talk for YouTube and as podcast audio, and write chapters from the titles.",
];

export default function Claude() {
  return (
    <>
      <PageHead eyebrow="Optional · computer only" title="Claude can edit for you">
        <p className="lede">
          Claude is an AI assistant made by Anthropic. On Windows and Mac, ClipForge comes with a small helper that
          lets Claude work on your projects: you say what you want in plain words, and Claude does the cutting.
        </p>
        <p className="small" style={{ marginTop: 12 }}>
          You do not need this to use ClipForge. Claude is a separate product with its own account and terms; ClipForge
          itself stays free.
        </p>
      </PageHead>

      <div className="wrap">
        <section className="band" aria-labelledby="how">
          <h2 id="how">How it goes</h2>
          <ol className="flow">
            <li style={css("video")}>
              <b>You ask</b>
              In plain words, in Claude Desktop or Claude Code: &quot;Clean up the podcast: remove the pauses and add
              captions.&quot;
            </li>
            <li style={css("photo")}>
              <b>Claude plans</b>
              It lists the steps and asks before big changes. It can say what it would do without changing anything.
            </li>
            <li style={css("music")}>
              <b>The helper edits</b>
              The helper changes the same project the app uses. Claude never deletes a project or any of your files.
            </li>
            <li style={css("title")}>
              <b>You watch</b>
              Open the project in ClipForge and see the result, or let Claude export the video.
            </li>
          </ol>
        </section>

        <section className="band" aria-labelledby="ask">
          <h2 id="ask">Things you can ask</h2>
          <div className="grid c2">
            <div>
              {ASK.slice(0, 3).map((a) => (
                <p className="say" key={a}>
                  {a}
                </p>
              ))}
            </div>
            <div>
              {ASK.slice(3).map((a) => (
                <p className="say" key={a}>
                  {a}
                </p>
              ))}
            </div>
          </div>
          <p className="small">
            Use your own project names. For files that are not in a project yet, give the full location, like{" "}
            <code>C:\Users\me\Videos\clip.mp4</code>.
          </p>
        </section>

        <section className="band" aria-labelledby="limits">
          <h2 id="limits">What it cannot do</h2>
          <div className="grid c3">
            <div className="card" style={css("caption")}>
              <h3>It cannot see the picture</h3>
              <p>
                Claude works from times, pauses and, with voice to text, the words that are said. It cannot tell
                whether a shot is pretty, who is in it, or whether a cut looks right. You watch; it cuts.
              </p>
            </div>
            <div className="card" style={css("video")}>
              <h3>Computer only</h3>
              <p>
                It needs Windows or a Mac (with an Apple chip, M1 or newer), ClipForge 1.12 or newer, and Claude
                Desktop or Claude Code. It does not work on the phone.
              </p>
            </div>
            <div className="card" style={css("title")}>
              <h3>One at a time</h3>
              <p>
                Before Claude changes a project, go back to ClipForge&rsquo;s project list. A project that is open in
                the app is marked, and Claude will not change it; it tells you to close it first.
              </p>
            </div>
          </div>
          <ul className="prose" style={{ marginTop: 18 }}>
            <li>Long videos take a while to export. Claude starts the export and checks on it until it is done.</li>
            <li>Speech recognition makes mistakes, mostly with names and numbers. Read captions before you post.</li>
            <li>
              What you write to Claude and what it reads from a project goes to Anthropic, under Claude&rsquo;s own
              terms. Your video files stay on your computer. See <Link href="/privacy">Privacy</Link>.
            </li>
          </ul>
        </section>

        <section className="band" aria-labelledby="setup">
          <h2 id="setup">Connect it once, in about 3 minutes</h2>
          <div className="split" style={{ gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1.1fr)", alignItems: "start" }}>
            <div>
              <h3>What you need</h3>
              <ul>
                <li>
                  A <b>Windows PC or a Mac</b> with <b>ClipForge 1.12 or newer</b>, started at least once.
                </li>
                <li>
                  <b>Claude Desktop</b> (the Claude app for Windows or Mac) or <b>Claude Code</b>.
                </li>
                <li>
                  <b>FFmpeg</b>, a free program Claude&rsquo;s helper uses to read and export videos. Windows: open{" "}
                  <b>Terminal</b> from the Start menu, type <code>winget install ffmpeg</code> and press Enter. Mac:{" "}
                  <code>brew install ffmpeg</code> (needs Homebrew).
                </li>
              </ul>
              <h3 style={{ marginTop: 18 }}>The steps</h3>
              <ol>
                <li>
                  In ClipForge, open <b>Help</b>, then <b>Connect to Claude…</b>
                </li>
                <li>
                  Click <b>Connect</b> next to your Claude. A small light turns green when it is connected.
                </li>
                <li>
                  Close Claude and open it again once. Claude reads its list of tools when it starts. (Windows: quit it
                  from the icon near the clock too.)
                </li>
                <li>
                  Check: start a new chat and ask <i>Run the ClipForge self-test.</i> After less than a minute Claude
                  shows a list with PASS for each check. Your own projects are not touched.
                </li>
              </ol>
              <p>
                After that there is nothing to do: when ClipForge is updated, it keeps the helper up to date by itself.
              </p>
            </div>
            <Shot
              name="connect_claude_desktop"
              sizes="(max-width: 760px) 100vw, 560px"
              caption="Help > Connect to Claude… in ClipForge on a computer."
            />
          </div>
        </section>

        <section className="band" aria-labelledby="trouble">
          <h2 id="trouble">If something does not work</h2>
          <div className="scroll">
            <table>
              <thead>
                <tr>
                  <th scope="col">What you see</th>
                  <th scope="col">What to do</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>Claude says it has no ClipForge tools</td>
                  <td>Close Claude completely and open it again. On the Connect to Claude page the light should be green.</td>
                </tr>
                <tr>
                  <td>&quot;FFmpeg could not be found&quot;</td>
                  <td>Install FFmpeg (see &quot;What you need&quot;), then restart Claude.</td>
                </tr>
                <tr>
                  <td>&quot;… is open in the ClipForge app&quot;</td>
                  <td>Go back to ClipForge&rsquo;s project list, then tell Claude to try again.</td>
                </tr>
                <tr>
                  <td>Claude finds no projects</td>
                  <td>Ask &quot;What is the ClipForge status?&quot; It names the folder it looks in.</td>
                </tr>
                <tr>
                  <td>The self-test shows a FAIL</td>
                  <td>The line says why, most often FFmpeg is missing. Tell Claude what you see; it knows the fix.</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p className="small" style={{ marginTop: 16 }}>
            The <a href={FULL_SETUP}>full setup guide</a> has the other ways to connect (the extension file for Claude
            Desktop, one line for Claude Code), what to do if you connected before version 1.12, and more fixes. In the
            help: <Link href="/help/connect-claude">Connect Claude</Link>,{" "}
            <Link href="/help/claude-self-test">Check that Claude works</Link>,{" "}
            <Link href="/help/claude-control">Claude control</Link>. There is nothing extra to download: what Claude
            needs is inside ClipForge.
          </p>
        </section>
      </div>
    </>
  );
}
