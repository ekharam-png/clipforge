# ClipForge

ClipForge is a simple video editor for Android, Windows and macOS. You add
videos, photos and music, trim and arrange them on a timeline, add titles, and
export the result as an MP4 file. It is written in Flutter; previews use
media_kit (mpv) and exports use FFmpeg.

## What it can do

- **Clips**: add videos and photos, trim their ends, split at the playhead,
  drag to reorder, delete. Tapping a clip selects it and shows it in the
  preview. New clips go in after the selected clip (or after the clip under
  the playhead).
- **Shape** (the button next to Export): keep the original shape or make the
  video upright (9:16, 4:5), wide (16:9) or square. Each clip can fit, fill
  or sit on a blurred copy of itself.
- **Crop and position**: crop each clip with handles on the preview (free
  or held to 16:9, 9:16, 1:1, 4:5), turn it a quarter turn, mirror it, and
  choose which part stays in the frame with Fill or zoom (for example, keep
  the person in shot when a wide video becomes upright).
- **Overlay**: one extra video row above the main clips for
  picture-in-picture (corner and size, optional white frame), side by side,
  top and bottom, full screen (cut-aways, a second camera) or anywhere you
  drag it. Overlays have their own trim, speed, volume and fades; their
  sound plays with the video's. Titles stay on top.
- **Speed** from 0.25× to 4× (voices keep their pitch), **look** (brightness,
  contrast, saturation, zoom, one-tap filters Warm / Cool / Black & white /
  Vintage / Vivid and a Warmth slider), **sound** (volume, mute, clean-up,
  voice focus) and **transitions** between clips. "Apply to all clips"
  copies a clip's speed, look or sound settings to the others in one step;
  **Copy settings / Paste settings** copy them to one clip; **Duplicate**
  copies a clip or title.
- **Fades** from and to black: for the whole video (titles and all sound
  fade too) and for each clip (its picture and its own sound).
- **Voice focus** (0–100 % per clip) makes speech clearer and tones down
  music, rumble and hiss behind it. It works best on music that is spread
  wide in stereo; it cannot remove music completely (voice and music share
  the same pitches; separating them needs AI). The preview plays part of it,
  the export all of it. "Clean up sound" is mostly heard in the export.
  "Hear original" switches the preview's sound changes off and on, and
  "Hear a sample" makes 15 seconds exactly as the export will sound, next to
  the original. A small badge on a clip shows that clean-up or voice focus
  is on.
- **Sound from**: for recordings that keep each microphone on its own side
  or track, a clip can use only the left or right side (heard on both) or
  another sound track of the file. Shown only for files where it applies.
- **Remove silences** cuts the quiet gaps out of a clip; **freeze frame**
  holds the picture at the playhead.
- **Music** with volume, fade in and fade out, and "lower music under speech"
  for the whole project. Music that runs past the end of the video fades out
  at the video's end; that part is greyed out on the timeline.
- **Publishing kit and shorts** (1.14): in the Export window, "Where is it
  going?" makes the right file for YouTube, Shorts / Reels / TikTok,
  Instagram, WhatsApp or a podcast, and "Export several…" makes them all
  into one folder with a text file to paste from (title, description,
  hashtags, chapters: "Publishing notes"). "Make a short from this…" in the
  Text window, 30 / 45 / 60 s from the playhead, or one short around every
  good-moment marker (key M). ClipForge never uploads and has no logins.
- **Text window** (1.13): everything said or written in the video as one
  readable page - the captions (whatever made them), the transcript, the
  titles - grouped by speaker, with search; click a sentence to go there,
  double-click a caption to fix a word. On phones under More > Text.
- **Sound waves and who is speaking** (1.13): every sound on the timeline
  shows its waveform; on the Voice rows each speaker's talk is bright in
  that speaker's colour and the pauses are dim, and Ctrl+Left / Right jump
  to where speech starts.
- **Voice recorded separately** (1.10): add the sound file of a separate
  microphone or a Zoom recording (one file per person) and choose "Voice for
  the video". ClipForge lines it up with the picture by comparing it with
  the camera's sound, gives it its own track, mutes the camera and keeps it
  in sync through every cut. When it cannot be lined up it says so and you
  nudge it by hand.
- **Titles and captions**: drag them on the picture; import and export
  subtitle files (.srt). They move along with their clip when the timeline
  changes. Four fonts with Latin, Cyrillic and Hebrew letters (DejaVu Sans,
  Rubik, Bona Nova, Amatic SC), outline, shadow, quick positions,
  left / centre / right, ready-made styles and entry / exit animations
  (fade, slide up, pop). What you see in the preview is where and how the
  export draws them.
- **Snapping**: on the timeline, dragged edges snap to the playhead and to
  the edges of clips, titles, sounds and overlays (yellow line); hold Alt /
  Option to place freely; can be turned off in the Playback menu.
- **Export** in full quality or as a small file for messaging apps, at the
  frame rate of the clips or 24 / 25 / 30 / 60 frames a second, or the
  sound only as M4A or MP3. Before it starts,
  ClipForge tells you if a file has gone missing and lets you point to where
  it is now ("Find file…").
- **Undo and redo** for everything; projects are saved automatically. If a
  save fails (for example, the storage is full) the editor says so and does
  not let you leave without asking.

Keyboard shortcuts (computer; Cmd instead of Ctrl on a Mac): Space
play/pause, J / K / L backwards / stop / forwards (backwards jumps in small
steps), S split at the playhead, I / O start / end the selected clip at the
playhead, Delete or Backspace delete the selection, Ctrl+D duplicate,
Ctrl+Shift+C / Ctrl+Shift+V copy / paste clip settings, Ctrl+Z undo,
Ctrl+Shift+Z or Ctrl+Y redo, Ctrl+Shift+H history, Ctrl+E export, + / -
timeline zoom, Left/Right one frame of the clip shown (with Shift one
second), Home/End jump to the start/end, F1 (Cmd+? on a Mac) help. They are
off while you type in a text field. Every editor command is also in the
menu bar (macOS menu bar; on Windows and Linux at the top of the window).

### Moving a project between phone and computer

A project can be packed, with all its videos, photos and music, into one
`.clipforge.zip` file and opened on another device.

1. On the device that has the project, open ClipForge's project list, tap the
   three dots on the project and choose **Share project file**.
   - On a phone the system's share sheet opens: send the file to your computer
     any way you like (Quick Share / Nearby Share, a cloud drive, a USB cable
     through a file manager, a messaging app that accepts large files).
   - On a computer you choose where to save the file; copy it to the phone.
2. On the other device choose **Open project file** in the project list and
   pick the file. It appears as a new project; the original is not changed.

If some of the project's media could not be found, ClipForge lists what was
left out after packing.

### Where your files are kept

- On a **computer** ClipForge uses your videos, photos and music where they
  are. Do not move or delete them while a project uses them; if you do, the
  clip is marked "Missing" and "Find file…" lets you point to the new place.
- On a **phone** ClipForge keeps its own copy of every file you add, so a
  project keeps working even if you delete the original from the gallery.
  These copies take up space. They are removed automatically once no project
  uses them any more (after you delete the project, or the next time the app
  starts); your gallery is never touched.
- Freeze frames and the media of an opened project file are also copies owned
  by the app and are cleaned up the same way.

## Help and tour

The first time ClipForge opens it asks **"Would you like a quick tour?"**.
**Show me around** walks through the main buttons in 8 short steps, first on
the project list, then inside a small sample project the tour makes for the
purpose (at the end you can keep it or delete it). **Not now** is fine too:
the question is not asked again, and the tour is always in Help.

- **Help** is the **?** at the top of the project list and of the editor
  (on a Mac also in the menu bar: Help > ClipForge Help, Help > Show the
  tour). It has about 45 short articles (including **What's new**, made from
  `CHANGELOG.md`) and a search box that finds what
  you mean even with typos ("musci", "vocie", "trascirpe"). It works
  without the internet.
- Small **?** buttons next to the settings that are easy to misunderstand
  (Clean up sound, Voice focus, Sound from, Lower music under speech, Remove
  silences, Fit to frame, Shape, Use graphics card) open the matching
  article.
- During the tour, **Skip tour** (or the Esc key on a computer) ends it at
  any time.

### Adding or changing a help article

All articles are in one text file, `assets/help/help_en.md`. Each one starts
with a line `=== some-id`, then a few `key: value` lines (`title`, `section`,
`keywords`, `related`, and `status: coming-later` for things not built yet),
a blank line, and the text. In the text a blank line starts a new paragraph,
`- ` makes a bullet, `1. ` a numbered step, `## ` a small heading, and
`**Bold**` marks the app's own button names, which must be written exactly
as the app shows them. Put words people might type in `keywords`; typos are
handled by the search. `flutter test test/ui/help_content_test.dart` checks
the file: every article parses, every `related` id exists, and every bold
button name really appears in the app. A translation is a copy of the file
named `help_<language>.md` with the ids, sections and related lines kept.

## Getting the app (no tools needed)

The easy way: open the download page (link in the repository's main
README) or the newest **Release** of this repository and pick your file.
Each version is published as a GitHub Release with these files.

Every change to this folder is also built automatically by GitHub. To get
a test build that is not released yet:

1. Sign in to GitHub and open this repository.
2. Click the **Actions** tab at the top.
3. In the list on the left, click **ClipForge builds**.
4. Click the newest run that has a green tick. (No run yet? Click
   **Run workflow**, then the green **Run workflow** button, and wait about
   15 minutes.)
5. Scroll down to **Artifacts** and click the file you need:

| File | For |
| --- | --- |
| `ClipForge-<version>-build<n>-android.apk` | Android phones and tablets |
| `ClipForge-<version>-build<n>-android-old-32bit-phones.apk` | Only if the first one refuses to install (very old phones) |
| `ClipForge-<version>-build<n>-windows-setup.exe` | Windows 10 / 11 (64-bit): the installer (recommended; 1.14.1) |
| `ClipForge-<version>-build<n>-windows.zip` | Windows 10 / 11 (64-bit): the same app as a zip, no install |
| `ClipForge-<version>-build<n>-macos.zip` | Mac (macOS 12 or newer) |

For example `ClipForge-1.4.0-build21-macos.zip`: version 1.4.0, made by run 21.
The Windows and Mac zips also hold `Release notes.txt` (what changed in that
version). Downloads are kept for 90 days; after that, run the workflow again.

## Updates

From version 1.12 on ClipForge looks for a newer version by itself, at most
once a day when it starts, and shows "Version … is available" on the project
list with **What's new**, **Update** and **Later** (**Skip this version**
and **Open the download page** are under the three dots). **Help > Check for
updates…** asks right now; **Check for updates automatically** switches the
daily check off (phones: the three dots on the project list).

Privacy: the check reads one small file, `latest.json`, from the newest
GitHub Release. That is the only request the app makes by itself; nothing
about you, your device or your videos is sent. The new version is downloaded
only when you press **Update**, and it is used only if its size and SHA-256
fingerprint are exactly the ones `latest.json` names.

| System | What Update does |
| --- | --- |
| Windows | Downloads `ClipForge-windows.zip`, checks it, unpacks it next to the ClipForge folder (a folder ending in `.update-new`), starts a small script and closes once the script has reported in. The script replaces the files inside the ClipForge folder (1.14.1: the folder itself is never renamed, so an open Explorer window or terminal is not in the way), checks the result, starts the new version and removes the unpacked folder. A safety copy (`.update-old`) is put back if a step fails. A ClipForge folder that cannot be changed (for example inside Program Files) opens the download page instead. The same works for an install made with `ClipForge-Setup.exe`. |
| Mac | The same with `ClipForge.app`. When the app's place cannot be changed (it was opened straight from the download, or no permission), the new app is unpacked into Downloads and shown in Finder: drag it into Applications. |
| Android | Downloads the APK, checks it and hands it to Android's installer, which asks you to confirm (the first time also to allow installs from ClipForge). |
| Linux (development builds) | Opens the download page. |

Projects and media (`Documents/ClipForge`) are never touched by an update.

Every step of an update on a computer is written to `update-log.txt` (Windows:
`%APPDATA%\com.ekcut\ClipForge\update-state\`; the exact path is in the
message when an update fails and in what **Copy version info** copies, which
also holds the log's last 40 lines). If ClipForge runs from a folder whose
name ends in `.update-new` (left by an update of 1.12 - 1.14 that did not
finish), it offers to **tidy up**: it moves itself into a folder called
`ClipForge` and removes the older ClipForge folders next to it.
Builds made on your own computer do not check by themselves.

## Which version do I have?

Every build carries one line that says exactly what it is, for example

    ClipForge 1.4.0 (build 21) · 16 Nov 2026, 07:20 UTC · 877e482

that is: the version (changes with each release, see `CHANGELOG.md`), the
build number (the GitHub Actions run that made it, the same on Android,
Windows and Mac from one run), when it was built and from which commit. A
build made on someone's own computer says "local build" instead of a time.

- In the app: small grey text at the bottom of the project list; tap it, or
  open **About ClipForge** (Mac: ClipForge menu; Windows: Help menu; phone:
  the three dots on the project list; anywhere: the bottom of Help). The app
  shows the time in your own time zone.
- **Copy version info** (in the same places) copies that line in UTC plus
  your system and device, ready to paste into a bug report or test checklist.
- Help > **What's new** lists the changes of every version.
- The Claude helper: `clipforge-mcp --version`, and `get_status` in Claude.
- On a computer the system shows it too: Mac Finder > Get Info ("1.4.0
  (21)"), Windows file Properties > Details (1.4.0.21), Android Settings >
  Apps > ClipForge (1.4.0).

### Android

1. Open the page above in the phone's browser and download
   `ClipForge-android.apk` (or download on a computer and send the file to the
   phone).
2. Tap the downloaded file. Android says the browser is not allowed to install
   unknown apps: tap **Settings**, switch on **Allow from this source**, go
   back and tap **Install**.
3. If Play Protect asks, choose **Install anyway**.

From 1.8 on, a newer build installs over the old one and keeps your projects.
Once only, going from 1.7 or older to 1.8, Android says "App not installed"
(the old builds were signed with a different key): first save each project
with **Share project file** (three dots on the project), uninstall the old
ClipForge, install 1.8, then bring the projects back with **Open project
file**. See "Keeping projects across updates" below.

### Windows

The installer (recommended, 1.14.1):

1. Download `ClipForge-Setup.exe` and open it. Windows shows a blue "Windows
   protected your PC" box because the app is not signed: click **More
   info**, then **Run anyway**.
2. It installs for you only (no administrator password), into
   `%LOCALAPPDATA%\Programs\ClipForge`, and adds ClipForge to the Start
   menu. To remove it: Settings > Apps > ClipForge > Uninstall. Projects
   (`Documents\ClipForge`) stay.

Or the zip (nothing is installed):

1. Download `ClipForge-windows.zip`, right-click it and choose **Extract All**.
2. Inside is a folder called `ClipForge`. Move that folder to where you want
   to keep it and keep the folder named `ClipForge`, without a version
   number: the app updates itself inside this folder. (A folder that is
   already called "ClipForge-1.12.0" keeps working; it can be renamed to
   "ClipForge" while the app is closed.)
3. Open the `ClipForge` folder and double-click `clipforge.exe`. Keep all the
   other files in that folder next to it. The zip makes no shortcuts.
4. Windows shows the same "Windows protected your PC" box: **More info**,
   then **Run anyway**.
5. Do not start ClipForge from a folder whose name ends in `.update-new`:
   that is a download waiting to be put in place. If it happened anyway,
   ClipForge offers to tidy up.

### macOS

1. Download `ClipForge-macos.zip` and double-click it. It unpacks to a
   folder holding `ClipForge.app`. Drag `ClipForge.app` into
   **Applications** (updates from inside the app need it there, not left in
   Downloads).
2. The first time, right-click (or Control-click) the app and choose **Open**,
   then **Open** again in the dialog.
3. On macOS 15 or newer that dialog has no Open button. Instead open
   **System Settings > Privacy & Security**, scroll down to the message about
   ClipForge and click **Open Anyway**.

This is needed once, because the app is not signed by an identified Apple
developer.

## Claude control

*Windows and Mac only.* The Windows and Mac downloads come with a small helper
program, `clipforge-mcp`. Once it is connected to **Claude Desktop** (or Claude
Code), you can ask Claude in plain words to edit your ClipForge projects, for
example:

- "Cut the silences out of my Podcast project, add captions from
  `C:\Users\me\Downloads\podcast.srt` and export it vertical."
- "Make a new project called Holiday from the three videos in
  `/Users/me/Movies/Trip`, put a title 'Summer 2026' on the first three
  seconds, add `/Users/me/Music/song.mp3` quietly underneath and fade it out."
- "In the Interview project, speed everything up a little, remove the second
  clip and add a crossfade between the others."
- "The Zoom recording is in the Podcast project; add
  `C:\Users\me\Documents\Zoom\audioSamTaylor2140.m4a` as Sam's voice
  and line it up with the video."

Claude changes the same project files the app uses, so afterwards you open the
project in ClipForge and see the result (or let Claude export the video
directly).

### The one rule: close the project in ClipForge first

While a project is open in ClipForge, the app works from its own copy and
saves it after every change you make there, which would overwrite what Claude
just did (and the app would not show Claude's changes anyway). So **before
asking Claude to edit a project, go back to ClipForge's home screen** (the
list of projects), or close the app. When Claude is done, open the project
again. Since ClipForge 1.9 the app marks the project it has open (a small
`.open-in-app` file in the project's folder, removed when you close it; one
left behind by a crash is ignored), and Claude's editing tools refuse to
change a marked project, saying so; looking at it and exporting still work.
Claude also refuses to save if it notices the project file changing while it
works.

Long exports run as a background job: Claude starts it, checks on it until it
is finished, and can stop it. The export keeps going even if Claude restarts
its connection to the helper; the file appears under its name only when it is
complete. The helper keeps a note of each export in a `claude-jobs` folder
next to the projects folder.

Good to know:

- Claude never deletes a project, a video or any other file. It only changes
  what is on the timeline. To be safe before a big change, ask it to "make a
  copy of the project first".
- Your videos, photos and music are used where they are (they are not copied
  into the project), so do not move or rename them afterwards. If you did,
  ask Claude to "relink" the file to its new place.
- Give Claude full file locations, like `C:\Users\me\Videos\clip.mp4`. On
  Windows, hold Shift, right-click a file and choose **Copy as path**; on a
  Mac, right-click it, hold the Option key and choose **Copy ... as Pathname**.

### Step 1: install FFmpeg (once)

The app has its video engine built in, but the helper needs the free program
FFmpeg installed on the computer for adding media, finding silences and
exporting. One command does it:

| Computer | What to do |
| --- | --- |
| Windows | Open **Terminal** (or PowerShell) from the Start menu, type `winget install ffmpeg` and press Enter. |
| Mac | Open **Terminal**, type `brew install ffmpeg` and press Enter. (This needs Homebrew; if the Mac says `brew` is not found, install it first from <https://brew.sh>.) |

Then quit and reopen Claude. Without FFmpeg Claude can still rearrange, trim
and title a project; it will tell you when something needs FFmpeg.

### Step 2: connect Claude, once (Help > Connect to Claude…)

Since ClipForge 1.12 the helper travels inside the app. Every time ClipForge
starts (and so after every update) it puts the helper into one fixed folder
of its own:

| Computer | Folder |
| --- | --- |
| Windows | `%LOCALAPPDATA%\ClipForge\claude\` |
| Mac | `~/Library/Application Support/ClipForge/claude/` |

Claude is pointed at that folder once, and never again. In ClipForge open
**Help > Connect to Claude…**. Since 1.14 the page does the set-up itself:

- **Claude Desktop:** press **Connect**. ClipForge adds one entry called
  `clipforge` to Claude's settings file (`claude_desktop_config.json`; it
  also finds the Claude from the Microsoft Store), keeps everything else in
  it, makes a dated backup next to it first, and refuses to change a file it
  cannot read. Then quit Claude completely (also from the icon near the
  clock) and open it again.
- **Claude Code:** press **Connect**. ClipForge runs
  `claude mcp add --scope user clipforge -- "<the helper's path>"` for you
  (an older ClipForge connection is listed and replaced after asking). Then
  start a new Claude Code session; `/mcp` shows the list.
- A light per row shows the state (connected, connected to an old copy, not
  connected, not found); **Disconnect** removes only the `clipforge` entry;
  **Details** shows what was run and what came back.
- "In use by Claude Desktop now · last action 2 min ago" appears while a
  Claude session has the helper open. **Test** starts the helper by itself
  and runs its quick self-test (PASS / FAIL), independent of Claude.
- The other ways stay: **Save the Claude extension file…** (then in Claude:
  Settings > Extensions > Advanced settings > Install Extension…;
  double-clicking the `.mcpb` does not work with the Microsoft Store Claude)
  and **Copy** for the Claude Code line.

Why Claude has to be closed and opened once: it reads its list of tools when
it starts, and then starts the helper itself whenever it needs it. ClipForge
does not have to be running, and there is no server to switch on.

That is all. When ClipForge is updated, the new helper goes into the same
folder and Claude uses it the next time Claude starts: no new extension, no
new skill. The step-by-step page is `docs/claude-setup.html` ("Connect Claude
to ClipForge"; also on the download page and in the Windows and Mac
downloads).

If you connected Claude before 1.12, do this once more (the old helper sat
inside the old extension or next to `clipforge.exe`, where it no longer is),
and remove a hand-made `clipforge` entry from `claude_desktop_config.json` if
you ever added one; the setup page shows which lines.

How it works, for the curious: the folder holds `clipforge-mcp(.exe)` (the
path Claude starts), `current.json` and `versions/<version>/` with the
helper and its title fonts. A new version always goes into a new folder (a
running program cannot be replaced on Windows), then `current.json` is
switched over. Whatever copy of the helper Claude starts, also the one
inside the extension, reads `current.json` first and hands over to the
current version. Ask Claude "What is the ClipForge status?" to see which
helper is running and from where.

The helper is built for Macs with Apple chips (M1 and newer).

### Step 3: check it ("Run the ClipForge self-test")

Ask Claude: **"Run the ClipForge self-test."** The helper makes its own small
sample video in a temporary folder and runs the real tools on it: create a
project, add media, split, speed, titles (also Cyrillic and Hebrew), sound
tracks, separate sound, remove silences (dry run, then for real), an export
as a background job that is checked with ffprobe, undo and redo, the refusal
while a project is open in the app, and speech to text when a speech program
and a language pack are installed. It takes under a minute, never touches
your projects, deletes the temporary folder and answers with a PASS / FAIL
list.

### The guide and the skill

The guide that tells Claude how to work (who it is helping, plan first,
safety copy, dry runs, recipes, every tool, troubleshooting) is compiled
into the helper and served by its `get_guide` tool, so it always matches the
installed version. Its source is `claude/guide/*.md`
(`dart run tool/gen_guide.dart` after changing it; a test fails otherwise).

The skill (`claude/skill/clipforge-editing`, `ClipForge-claude-skill.zip`)
is now only a short pointer: it helps Claude notice that a request is about
ClipForge and tells it to call `get_guide`. Uploading it (Claude >
**Customize** > **Skills** > **Upload a skill**) is optional and never has
to be repeated. `claude/CLAUDE.md` is the same pointer for Claude Code.

### The manual way (fallback)

In Claude Desktop: **Settings > Developer > Edit Config**, and in
`claude_desktop_config.json` (on Windows every `\` is written twice):

```json
{
  "mcpServers": {
    "clipforge": {
      "command": "C:\\Users\\me\\AppData\\Local\\ClipForge\\claude\\clipforge-mcp.exe"
    }
  }
}
```

On a Mac the command is
`/Users/me/Library/Application Support/ClipForge/claude/clipforge-mcp`. Use
either the extension or this entry, not both.

### If something does not work

- **Claude does not see your projects.** The helper looks in the same place
  as the app, `Documents/ClipForge/projects` (also when Documents is inside
  OneDrive). Ask Claude for the ClipForge status to see which folder it uses.
  If it is the wrong one, tell the helper the right folder by adding a line
  to the config (again with doubled `\` on Windows):
  `"args": ["--projects-dir", "C:\\Users\\me\\OneDrive\\Documents\\ClipForge\\projects"]`
- **"FFmpeg ... could not be found".** Do step 1, then restart Claude. If it
  is installed somewhere unusual, add
  `"args": ["--ffmpeg", "<full path of ffmpeg>", "--ffprobe", "<full path of ffprobe>"]`.
- **My edits disappeared.** The project was open in ClipForge while Claude
  worked on it. Close it first (see the rule above) and ask Claude again.
- **The helper does not start on a Mac.** See "If the Mac blocks it" in
  `docs/claude-setup.html`.
- **Claude still shows an old version after an update.** Quit Claude
  completely and start it again; the helper is chosen when Claude starts.

### What Claude can do

| Area | Tools |
| --- | --- |
| Projects | list, show, create, duplicate, rename; shape (original, 9:16, 16:9, 1:1, 4:5); lower music under speech |
| Clips | add videos and photos, trim, split, remove, reorder; speed, volume, mute, fit, audio clean-up, voice focus, sound track / left or right side, brightness / contrast / saturation, zoom, transitions; cut out silences; relink a moved file |
| Text | titles, captions, import and export of `.srt` subtitles (also subtitles made for the uncut recording) |
| Speech (1.11) | transcribe in the background, read and search what is said, captions from speech, remove filler words gently, list and put back automatic cuts, make a short from one part |
| Text and speakers (1.13) | read all captions as compact text, find and replace over all captions (dry run first), who talks when from the sound (speaker turns), without a transcript |
| Publishing and shorts (1.14) | candidate passages for shorts (whole sentences with times and signals, for Claude to judge), shorts with the Short caption look and a title, publishing notes and chapters, a publishing kit for several destinations as one background job, good-moment markers |
| Music | add, move, trim, volume, fades, remove |
| Voice | add a separately recorded voice lined up with the video; line up, nudge or unlink a sound that is already there |
| Output | export an MP4 in full or small (720p) quality, with progress; the export keeps running when Claude is closed (1.12: also on Windows) |
| Help for Claude (1.12) | `get_guide` (the guide inside the helper), `self_test` (checks the installation), `get_status` (which helper runs, and where) |

Titles and captions stay on the picture they were put on when clips are cut,
moved or sped up, exactly as in the app. Music stays where it is on the
timeline.

### For developers

The server is `bin/clipforge_mcp.dart` with its code in `lib/mcp`. It is plain
Dart (no Flutter) on top of `lib/core` and `lib/media`, speaks the Model
Context Protocol (revision 2025-11-25, also accepting 2025-06-18, 2025-03-26
and 2024-11-05) over standard input / output, and writes its log to standard
error.

```sh
dart run bin/clipforge_mcp.dart --help      # run from source
dart run bin/build_mcp.dart                 # build/mcp/clipforge-mcp(.exe), one file
flutter test test/mcp                       # includes a real session over stdio
```

`dart compile exe` cannot be run directly in this package (the Flutter plugins
bring build hooks, which it refuses), so `bin/build_mcp.dart` compiles the
pure-Dart sources in a temporary package. Options, each also available as an
environment variable: `--projects-dir` (`CLIPFORGE_PROJECTS_DIR`), `--ffmpeg`
(`CLIPFORGE_FFMPEG`), `--ffprobe` (`CLIPFORGE_FFPROBE`), `--fonts-dir`
(`CLIPFORGE_FONTS_DIR`; titles are drawn with the two DejaVu fonts, looked for
in `fonts/` next to the executable, in the app bundle next to it, then in
`assets/fonts`). `CLIPFORGE_MCP_NO_HANDOVER=1` makes a started helper answer
itself instead of handing over to the one the app installed (tests, CI);
`CLIPFORGE_WORKER_START=child` starts export workers the pre-1.12 way on
Windows.

The Claude extension file is built by `docs/tools/build_claude_bundles.py`;
with `--asset assets/claude` it is also copied to where the app build picks
it up (`assets/claude/README.txt`). CI checks on Windows that the update
scripts replace the app's files, cope with a held folder, name a held file
and roll back (`tool/ci/windows_swap_test.py`), builds the installer
(`windows/installer/clipforge.iss`, Inno Setup) and installs, updates and
uninstalls it silently, and that an
export survives the helper's process tree being killed
(`tool/ci/job_survives_test.py`, also run on Linux).

## Building it yourself

Install [Flutter](https://docs.flutter.dev/get-started/install) 3.50.0, then
from this folder:

```sh
flutter pub get
flutter run                      # run on the connected device or desktop
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
flutter build windows --release  # on Windows, needs Visual Studio with C++
flutter build macos --release    # on a Mac, needs Xcode and CocoaPods
flutter build linux --release    # needs libgtk-3-dev libmpv-dev libjson-glib-dev
```

Local builds take their version from `version:` in `pubspec.yaml` and say
"local build". To stamp a build like CI does, add
`--build-name=1.4.0 --build-number=21 --dart-define-from-file=build.json`
with a `build.json` like
`{"CLIPFORGE_BUILD_TIME":"2026-11-16T07:20:00Z","CLIPFORGE_COMMIT":"877e482","CLIPFORGE_CHANNEL":"ci"}`
(`bin/build_mcp.dart` takes the same options). On Linux,
`clipforge --version` prints the version line and quits.

Android needs the Android SDK (platform 36, NDK 28.2.13676358) and JDK 17 or
newer; set `ANDROID_HOME` to the SDK folder. The APKs end up in
`build/app/outputs/flutter-apk/`. A single APK for all phone types
(`flutter build apk --release`) also works but is about 260 MB instead of 76.

On Linux the app uses the `ffmpeg` and `ffprobe` programs installed on the
system. On Android, Windows and macOS, FFmpeg is built into the app.

### Keeping projects across updates (Android signing)

Every published APK is signed with the ClipForge release key (alias
`clipforge`, RSA 4096, valid until 2056, certificate SHA-256
`2F:36:DB:D0:DA:E6:7C:DE:38:D2:BB:7C:EA:0C:04:D8:50:FD:44:33:69:3D:20:96:09:F7:97:DF:4F:23:65:5B`),
so a new version installs over the previous one. The key is not in the
repository: the build reads it from four repository secrets (Settings >
Secrets and variables > Actions): `ANDROID_KEYSTORE_BASE64` (the keystore
file, base64-encoded), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`. Locally: `android/key.properties` with
`storeFile`, `storePassword`, `keyAlias`, `keyPassword` (never committed).
Without it a release build is signed with the debug key, which works for
testing but does not install over a published APK.

## Tests

```sh
flutter analyze
flutter test
```

The export tests in `test/media/` run real exports and need `ffmpeg` and
`ffprobe` on the PATH; without them they are skipped.

The tests in `test/ui/` drive the screens at phone size (390 × 844) and
desktop size (1280 × 800) with the players, the exporter and the file dialogs
replaced by fakes. They can also write the pictures in `docs/screenshots/`:

```sh
flutter test test/ui --dart-define=SCREENSHOTS=true
```

`integration_test/real_app_test.dart` runs the real app on a desktop: real
players (mpv), real FFmpeg, a real project folder; only the file dialogs are
replaced. It imports, plays, seeks, edits and exports, and checks the preview
by reading pixels. On Linux without a screen or sound card:

```sh
E2E_OUT=/tmp/clipforge-e2e E2E_NULL_AO=1 LIBGL_ALWAYS_SOFTWARE=1 \
  xvfb-run -a -s "-screen 0 1280x800x24" \
  flutter test integration_test/real_app_test.dart -d linux
```

Screenshots and the exported video end up in `$E2E_OUT`. Anything that only
happens on a phone (the file picker's copies, the gallery, the share sheet)
is not covered by these tests and has to be tried on a device.

## Project layout

| Folder | Contents |
| --- | --- |
| `lib/core` | The project model, editing operations (with undo), title layout, subtitles, saving and autosave, project files (`.clipforge.zip`), the checks for missing and unused media. Plain Dart, no Flutter UI. |
| `lib/media` | Reading media files, thumbnails, silence detection and exporting through FFmpeg. `media_api.dart` is the interface the UI uses. |
| `lib/ui` | Screens and widgets: `home` (project list), `editor` (timeline, preview, tools, export dialog), `playback` (the preview players). `services.dart` holds everything that touches the platform (file dialogs, share sheet, gallery, app folders). |
| `lib/mcp`, `bin` | The helper program for Claude (see "Claude control"). |
| `test` | Tests, in the same groups (`core`, `media`, `ui`, ...). |
| `integration_test` | The end-to-end test of the real app. |
| `docs/screenshots` | Pictures of every screen, written by the UI tests. |
| `android`, `windows`, `macos`, `linux` | Platform projects (app name, icons, permissions). |

## Licence note

The bundled FFmpeg build (from `ffmpeg_kit_flutter_new`, "full-gpl" variant)
is licensed under GPL-3.0. Anyone who distributes ClipForge must do so under
GPL-compatible terms and make the source available. The Windows download
includes the FFmpeg licence texts in its `licenses` folder.

Title fonts (in `assets/fonts`, licence files next to them): DejaVu Sans
(Bitstream Vera / DejaVu licence), Rubik, Bona Nova and Amatic SC (SIL Open
Font License 1.1; the Google Fonts builds, taken from the
`@expo-google-fonts` npm packages, licence texts from `@fontsource`).

## Third-party software

ClipForge is free software under the GNU GPL version 3 (`LICENSE` at the
root of the repository). It is built with:

- [Flutter](https://flutter.dev) (BSD 3-Clause) and the Dart packages listed
  in `pubspec.yaml`, each under its own licence.
- [FFmpeg](https://ffmpeg.org) through
  [ffmpeg_kit_flutter_new](https://pub.dev/packages/ffmpeg_kit_flutter_new)
  (GPL build, GPL-3.0) for export and media analysis.
- [media_kit](https://github.com/media-kit/media-kit) with libmpv for video
  playback (MIT; libmpv LGPL-2.1 or later).
- Title fonts DejaVu Sans, Rubik, Bona Nova and Amatic SC (see "Licence
  note" above; licence files in `assets/fonts`).
