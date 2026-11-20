import type { Metadata } from "next";
import Link from "next/link";
import { PageHead } from "@/components/Chrome";
import { Mark } from "@/components/Mark";
import { ShotPair } from "@/components/Shot";

export const metadata: Metadata = {
  title: "Your first video in 10 minutes",
  description:
    "A step-by-step walk-through of ClipForge with real screenshots: new project, add videos, cut, titles and captions, music, export. Then recipes for family videos, podcasts, sport highlights and vertical shorts.",
};

const css = (c: string) => ({ "--c": `var(--c-${c})` }) as React.CSSProperties;

function Step(props: { id: string; time: string; color: string; kicker: string; title: string; children: React.ReactNode }) {
  return (
    <li className="step" id={props.id}>
      <div className="step-time" aria-hidden="true">
        {props.time}
      </div>
      <div className="step-body" style={css(props.color)}>
        <p className="step-kicker">{props.kicker}</p>
        <h3>{props.title}</h3>
        {props.children}
      </div>
    </li>
  );
}

function Variants({ computer, phone }: { computer: React.ReactNode; phone: React.ReactNode }) {
  return (
    <div className="variants">
      <div className="variant">
        <h4>
          <Mark where="computer" />
        </h4>
        <p>{computer}</p>
      </div>
      <div className="variant">
        <h4>
          <Mark where="phone" />
        </h4>
        <p>{phone}</p>
      </div>
    </div>
  );
}

export default function Walkthrough() {
  return (
    <>
      <PageHead eyebrow="Walk-through" title="Your first video in 10 minutes">
        <p className="lede">
          Six steps from an empty project to a finished video. The buttons are named exactly as the app shows them.
          Where the phone and the computer differ, both ways are given.
        </p>
        <ul className="toc" aria-label="On this page">
          <li><a href="#new-project">1. New project</a></li>
          <li><a href="#add">2. Add videos</a></li>
          <li><a href="#cut">3. Cut</a></li>
          <li><a href="#text">4. Titles and captions</a></li>
          <li><a href="#music">5. Music</a></li>
          <li><a href="#export">6. Export</a></li>
          <li><a href="#recipes">Recipes</a></li>
        </ul>
      </PageHead>

      <div className="wrap">
        <section className="band" aria-labelledby="steps-h">
          <h2 id="steps-h" className="sr-only">
            The six steps
          </h2>
          <p className="small" style={{ marginBottom: 22 }}>
            The pictures show ClipForge with small test clips, so the preview is a plain blue picture. Yours will show
            your video. Not installed yet? <Link href="/install">Install ClipForge</Link> first.
          </p>
          <ol className="steps">
            <Step id="new-project" time="0:00" color="video" kicker="Step 1" title="Start a new project">
              <p>
                ClipForge opens on the project list. Tap <b>New project</b>. A project is one video you are making: it
                remembers your clips, cuts, text and music. Everything is saved by itself as you go, so there is no
                Save button to remember.
              </p>
              <ShotPair computer="home_desktop" phone="home_phone" />
              <p className="tip">
                <b>First time?</b> ClipForge offers a quick tour of the real buttons. You can take it again later from
                Help (the <b>?</b> at the top), with <b>Show the tour</b>.
              </p>
            </Step>

            <Step id="add" time="1:00" color="photo" kicker="Step 2" title="Add your videos and photos">
              <p>
                Tap <b>Add media</b> and choose one or more videos or photos. They appear as clips on the timeline at
                the bottom, in the order you picked them. Later additions go in after the selected clip, or at the end.
              </p>
              <Variants
                computer={
                  <>
                    You can also drag videos, photos and music straight from a folder onto the ClipForge window. Drop a
                    whole folder to add everything in it, in name order.
                  </>
                }
                phone={
                  <>
                    You can also tap the <b>+</b> next to the play button and choose <b>Videos or photos</b>. The
                    phone&rsquo;s own picker opens: choose from your gallery or your files.
                  </>
                }
              />
              <ShotPair computer="editor_desktop_empty" phone="editor_phone_add" />
            </Step>

            <Step id="cut" time="2:30" color="video" kicker="Step 3" title="Cut: keep the good parts">
              <p>The white line on the timeline is the playhead: it shows what you see in the preview.</p>
              <ul>
                <li>
                  <b>Trim:</b> tap a clip to select it, then drag its left or right end to make it shorter.
                </li>
                <li>
                  <b>Split:</b> move the playhead to the spot and tap <b>Split</b>. The clip becomes two pieces that
                  you can move or delete on their own.
                </li>
                <li>
                  <b>Delete:</b> select a piece you do not want and tap <b>Delete</b>.
                </li>
                <li>
                  <b>Reorder:</b> hold a clip and drag it to a new place.
                </li>
              </ul>
              <Variants
                computer={
                  <>
                    The <b>S</b> key splits at the playhead, Space plays and stops, and Ctrl+Z (on a Mac Cmd+Z) undoes.
                    All of them are under <Link href="/help/keyboard-shortcuts">Keyboard shortcuts</Link>.
                  </>
                }
                phone={
                  <>
                    The tools for the selected clip are in the bar at the bottom. <b>More</b> holds the rest:{" "}
                    <b>Move earlier</b>, <b>Move later</b>, Crop, History.
                  </>
                }
              />
              <ShotPair computer="editor_desktop_clip_selected" phone="tour_phone_5_split" />
              <p className="tip">
                <b>Made a mistake?</b> <b>Undo</b> (the curved arrow at the top) takes back any change, and{" "}
                <Link href="/help/history">History</Link> goes back several steps at once.
              </p>
            </Step>

            <Step id="text" time="4:30" color="title" kicker="Step 4" title="Add a title and captions">
              <p>
                Tap <b>Title</b> to put text on the picture at the playhead, for 3 seconds. Type your words in{" "}
                <b>Text</b>, pick a <b>Style</b> and a <b>Font</b>, and drag the text on the picture to place it. Drag
                the title on the timeline to change when it shows.
              </p>
              <ShotPair computer="editor_desktop_text_styles" phone="editor_phone_title" />
              <p>
                Captions are the lines of subtitles at the bottom. Tap <b>Captions</b>, type what is being said and tap{" "}
                <b>Add</b>. The caption appears at the playhead; stretch it on the timeline to fit the sentence.
              </p>
              <Variants
                computer={
                  <>
                    ClipForge can write the captions for you: <b>Transcribe speech…</b>, then{" "}
                    <b>Captions from speech…</b>. See the <a href="#podcast">podcast recipe</a>.
                  </>
                }
                phone={
                  <>
                    Captions are typed by hand, or brought in with <b>Import subtitles (.srt)</b>. Captions made on a
                    computer travel with the project file and show on the phone too.
                  </>
                }
              />
              <ShotPair computer="editor_desktop_captions" phone="editor_phone_caption_entry" />
            </Step>

            <Step id="music" time="6:30" color="music" kicker="Step 5" title="Add music, and fit it to the video">
              <p>
                Tap <b>Music</b>. <b>My files</b> picks a song on your device; <b>Find free music</b> searches music
                you may use for free. The music starts at the playhead, on its own green track.
              </p>
              <p>
                Now the useful part: select the music on the timeline and tap <b>Fit music to video</b>. Music that is
                longer than the video is cut so it ends exactly where the video ends, with a 2-second fade-out. Music
                that is shorter asks whether to <b>Loop</b> it.
              </p>
              <ShotPair computer="editor_desktop_fit_music" phone="editor_phone_fit_music" />
              <p className="tip">
                <b>Cut your video first:</b> the music fits the video as it is when you tap the button. If people talk
                in the video, switch on <Link href="/help/lower-music">Lower music under speech</Link> and the music
                gets quieter by itself while they do.
              </p>
            </Step>

            <Step id="export" time="8:30" color="caption" kicker="Step 6" title="Export for where it is going">
              <p>
                Tap <b>Export</b> at the top right. Under <b>Where is it going?</b> choose the place, and ClipForge
                picks the right shape, size and kind of file:
              </p>
              <ul>
                <li>YouTube: wide 16:9, 1080p, full quality.</li>
                <li>Shorts / Reels / TikTok: upright 9:16, 1080p.</li>
                <li>Instagram post: tall 4:5 or square 1:1.</li>
                <li>WhatsApp / Telegram: a small file that is quick to send.</li>
                <li>Podcast audio: the sound only, as MP3 or M4A.</li>
              </ul>
              <p>
                <b>Export several…</b> makes more than one in a single go. Keep the app open until it finishes.
                ClipForge does not upload anything and never asks you to sign in: it makes the files, you post them.
              </p>
              <Variants
                computer={
                  <>
                    You choose where to save the file. Afterwards: <b>Show in folder</b>,{" "}
                    <b>Copy title and description</b>, and a link that opens the site&rsquo;s own upload page in your
                    browser.
                  </>
                }
                phone={
                  <>
                    The finished video goes to your gallery (Movies). <b>Share</b> hands it to another app;{" "}
                    <b>Copy title and description</b> stays on screen, because many apps ignore text sent with a video.
                  </>
                }
              />
              <ShotPair computer="export_desktop_destination" phone="export_phone_finished" />
              <p className="tip">
                <b>A wide video for an upright place?</b> ClipForge asks: <b>Make a copy in this shape</b> (a new
                project with a blurred background; yours stays as it is) or <b>Export as it is</b>.
              </p>
            </Step>

            <Step id="done" time="10:00" color="video" kicker="Done" title="That is a finished video">
              <p>
                The project stays on the project list, so you can come back, change a title and export again. Next:
                try a recipe below, look at the <Link href="/examples">examples</Link>, or search the{" "}
                <Link href="/help">help</Link> for the button you are wondering about.
              </p>
            </Step>
          </ol>
        </section>

        <section className="band" id="recipes" aria-labelledby="recipes-h">
          <h2 id="recipes-h">Recipes</h2>
          <p className="h2-note">Four kinds of video people make most, each as a short list.</p>
          <ul className="toc" aria-label="Recipes" style={{ margin: "0 0 26px" }}>
            <li><a href="#family">Family video</a></li>
            <li><a href="#podcast">Podcast clean-up</a></li>
            <li><a href="#sport">Sport highlight</a></li>
            <li><a href="#short">Vertical short for Reels</a></li>
          </ul>

          <article className="example recipe" id="family" style={css("title")}>
            <p className="kind">Recipe · <Mark where="both" /></p>
            <h2>Family video</h2>
            <p className="tagline">A trip, a birthday, a school play: several clips and photos, one title, one song.</p>
            <ol>
              <li>
                <b>New project</b>, then <b>Add media</b>: pick all the clips and photos at once. Photos become clips
                you can stretch.
              </li>
              <li>Trim the slow starts and ends of each clip, and drag the clips into the order of the day.</li>
              <li>
                Between two clips, add a gentle <Link href="/help/transitions">transition</Link>, for example
                Crossfade.
              </li>
              <li>
                <b>Title</b> at the start: the place and the year is enough. The <b>Handwritten</b> font suits it.
              </li>
              <li>
                <b>Music</b> &gt; <b>Find free music</b>: type something like &quot;happy ukulele&quot; or &quot;calm
                piano&quot;, listen, and tap <b>Use</b>. Then <b>Fit music to video</b>.
              </li>
              <li>
                <b>Export</b> with WhatsApp / Telegram for the family chat, or use <b>Export several…</b> to also keep
                a full-quality copy.
              </li>
            </ol>
            <ShotPair computer="editor_desktop_free_music" />
            <p className="tip">
              Free music comes with a licence and often wants the artist named. ClipForge keeps the credit with the
              music: see <Link href="/help/music-credits">Music credits</Link>.
            </p>
          </article>

          <article className="example recipe" id="podcast" style={css("music")}>
            <p className="kind">Recipe · voice to text is <Mark where="computer" /></p>
            <h2>Podcast clean-up</h2>
            <p className="tagline">
              A talk filmed with a camera, with the voices recorded separately on microphones or by Zoom.
            </p>
            <ol>
              <li>
                Add the video first, then each sound file: drop it on the window, or tap <b>Music</b> and{" "}
                <b>My files</b>.
              </li>
              <li>
                ClipForge asks what the sound is. Choose <b>Voice for the video</b>, type who speaks, and tap{" "}
                <b>Add and line up</b>. It compares the voice with the camera&rsquo;s sound, lines the two up, gives
                the voice its own track and mutes the camera.
              </li>
              <li>
                Select the clip, tap <b>Sound</b>, then <b>Remove silences</b>. ClipForge says how many gaps it found
                and how much shorter the clip gets; tap the button, for example <b>Remove 5 gaps</b>. Too many or too
                few? Change <b>Sensitivity</b>.
              </li>
              <li>
                Noisy room? In the same panel, switch on <b>Clean up sound</b>, and try <b>Voice focus</b>.
              </li>
              <li>
                Captions, on a computer: <b>Transcribe speech…</b>, choose the language, then{" "}
                <b>Captions from speech…</b> and <b>Add captions</b>. <b>Remove filler words…</b> takes out
                &quot;um&quot; and &quot;uh&quot;, with a list to review first. Read the captions through: names and
                numbers are where mistakes hide.
              </li>
              <li>
                <b>Export several…</b>: tick YouTube and Podcast audio to get the video and an MP3 from one job.
              </li>
            </ol>
            <ShotPair computer="timeline_waves_desktop" />
            <ShotPair computer="editor_desktop_silences" phone="editor_phone_silences" />
            <ShotPair computer="editor_desktop_speech_captions" />
            <p className="tip">
              <b>On a phone:</b> lining up a voice, Remove silences and the sound clean-up all work. Voice to text does
              not, so captions are typed or imported there. Transcribing happens on your computer; nothing is sent
              anywhere. It needs a speech program on the computer: <Link href="/help/transcribe-speech">what it needs</Link>.
            </p>
          </article>

          <article className="example recipe" id="sport" style={css("video")}>
            <p className="kind">Recipe · <Mark where="both" /></p>
            <h2>Sport highlight</h2>
            <p className="tagline">A long recording of a match, and the few seconds everyone wants to see again.</p>
            <ol>
              <li>
                Add the recording and watch it. Each time something good happens, mark it: press <b>M</b> on a
                computer; on a phone tap <b>More</b>, then <b>Mark a good moment</b>. A small flag appears on the time
                ruler.
              </li>
              <li>
                <b>Good moments…</b> lists your markers. <b>Make shorts from markers…</b> makes one short around each:
                about 20 seconds before to 25 seconds after. Each is a new project; the recording is not changed.
              </li>
              <li>
                For slow motion, <b>Split</b> just before and just after the best second, select that piece and tap{" "}
                <b>Speed</b>: 0.5× or 0.25×. It looks smoothest with videos filmed at a high frame rate.
              </li>
              <li>
                To hold the decisive picture still, put the playhead on it and use <b>Freeze</b>.
              </li>
              <li>
                <b>Export</b>, and for fast movement choose 60 under <b>Frames per second</b> (the window says when it
                helps).
              </li>
            </ol>
            <ShotPair computer="markers_desktop" />
            <ShotPair computer="editor_desktop_speed" phone="editor_phone_speed" />
          </article>

          <article className="example recipe" id="short" style={css("caption")}>
            <p className="kind">Recipe · <Mark where="both" /></p>
            <h2>Vertical short for Reels</h2>
            <p className="tagline">An upright video of up to a minute, from a new clip or from a part of a long one.</p>
            <ol>
              <li>
                <b>From a long video:</b> put the playhead where the good part starts and choose{" "}
                <b>Make a short from here…</b> (computer: the Edit menu, under Shorts; phone: <b>More</b>, then{" "}
                <b>Shorts and good moments</b>). Pick 30, 45 or 60 seconds. With captions in the project you can also
                select sentences in the Text window and choose <b>Make a short from this…</b>.
              </li>
              <li>
                Leave <b>Start and end at a pause</b> and <b>Short caption look</b> ticked, and give it a{" "}
                <b>Title at the top</b>: a few words that make people stop.
              </li>
              <li>
                <b>From scratch:</b> in any project, tap <b>Shape</b> (next to Export) and choose <b>9:16 upright</b>.
                Wide clips are fitted in; under <b>Look</b> choose <b>Fill</b> or <b>Blur</b> instead of black bars.
              </li>
              <li>
                Open <b>Crop</b> (on a phone: <b>More</b>, then <b>Crop and position</b>) and move the frame so the
                person stays in shot.
              </li>
              <li>
                <b>Export</b> with <b>Shorts / Reels / TikTok</b>. ClipForge warns when the video is longer than 60
                seconds, which is safe on all three; the sites change their limits, so check the site.
              </li>
            </ol>
            <ShotPair computer="short_dialog_desktop" phone="short_dialog_phone" />
            <ShotPair computer="editor_desktop_crop" phone="editor_phone_crop" />
          </article>

          <div className="note">
            <p>
              Something in a recipe did not work for you, or a recipe is missing?{" "}
              <Link href="/feedback">Tell us</Link>: this page grows from questions.
            </p>
          </div>
        </section>
      </div>
    </>
  );
}

