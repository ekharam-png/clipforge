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
| `ClipForge-<version>-build<n>-windows.zip` | Windows 10 / 11 (64-bit) |
| `ClipForge-<version>-build<n>-macos.zip` | Mac (macOS 12 or newer) |

For example `ClipForge-1.4.0-build21-macos.zip`: version 1.4.0, made by run 21.
The Windows and Mac zips also hold `Release notes.txt` (what changed in that
version). Downloads are kept for 90 days; after that, run the workflow again.

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

1. Download `ClipForge-windows.zip`, right-click it and choose **Extract All**.
2. Open the `ClipForge` folder and double-click `clipforge.exe`. Keep all the
   other files in that folder next to it.
3. Windows shows a blue "Windows protected your PC" box because the app is not
   signed: click **More info**, then **Run anyway**.

### macOS

1. Download `ClipForge-macos.zip` and double-click it. It unpacks to a
   folder holding `ClipForge.app` and a `ClipForge-Claude` folder. Drag
   `ClipForge.app` into **Applications**.
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

### Step 2 (Mac only): put the helper in place

The Mac download unpacks to `ClipForge.app` and a folder called
`ClipForge-Claude`. Drag that folder into **Applications** too, then open
**Terminal** and run this once, because the helper (like the app) is not
signed by an identified Apple developer and macOS would otherwise block it:

```sh
xattr -dr com.apple.quarantine /Applications/ClipForge-Claude
```

The helper is built for Macs with Apple chips (M1 and newer).

On Windows there is nothing to do: `clipforge-mcp.exe` is already in the
`ClipForge` folder next to `clipforge.exe`. Keep it there.

### Step 3: connect Claude Desktop (the easy way: the extension)

The step-by-step page with pictures of the lines to remove is
`docs/claude-setup.html` ("Connect Claude to ClipForge"; it is also inside
the Windows and Mac downloads). In short:

1. From the build page download `ClipForge-<version>-build<n>-claude-windows.mcpb`
   (Mac: `...-claude-macos.mcpb`). This is the ClipForge **extension** for
   Claude Desktop: one file with the helper, its fonts and a description.
   Do not unzip it.
2. Double-click it. Claude opens and shows **ClipForge** with **Install**.
   If nothing happens: in Claude open **Settings > Extensions** (newer
   layout: **Settings > Desktop app > Extensions > Manage**), then
   **Advanced settings > Install Extension…** and choose the file.
3. If you added `clipforge` to `claude_desktop_config.json` by hand before,
   remove that entry (**Settings > Developer > Edit Config**), or Claude
   gets every ClipForge tool twice.
4. Quit Claude completely and start it again.

With the extension, steps 2 (Mac) and the config file below are not needed:
the helper lives inside Claude's own extensions folder. A new ClipForge
build means installing the new `.mcpb` the same way (extensions installed
from a file do not update themselves).

On a Mac the helper inside the extension is not signed by an identified
Apple developer. If the extension does not start, run this once in
Terminal and restart Claude (not yet tried on a real Mac):

```sh
xattr -dr com.apple.quarantine ~/Library/Application\ Support/Claude/Claude\ Extensions
```

### Step 3, the manual way (fallback)

Use this only if the extension cannot be installed. Use one or the other,
not both.

1. In Claude Desktop open **Settings**, then **Developer**, and click
   **Edit Config**. This shows a file called `claude_desktop_config.json`
   (on Windows in `%APPDATA%\Claude`, on a Mac in
   `~/Library/Application Support/Claude`).
2. Open it with Notepad (Windows) or TextEdit (Mac) and make it look like one
   of the examples below. If the file already has other things in it, add
   only the `"clipforge": { ... }` part inside the existing `"mcpServers"`.
3. Save, then quit Claude Desktop completely and start it again.

Windows: use the place where *you* unpacked ClipForge, and write every `\`
twice:

```json
{
  "mcpServers": {
    "clipforge": {
      "command": "C:\\Users\\me\\ClipForge\\clipforge-mcp.exe"
    }
  }
}
```

Mac:

```json
{
  "mcpServers": {
    "clipforge": {
      "command": "/Applications/ClipForge-Claude/clipforge-mcp"
    }
  }
}
```

To check that it works (either way), ask Claude: **"What version of
ClipForge are you connected to?"** It answers with the version line (the
same as Help > About ClipForge in the app), the projects folder it uses,
how many projects it found and whether FFmpeg was found. The first time, macOS may ask whether Claude may
access the Documents folder: allow it, that is where the projects are.

**Claude Code** (as well as, or instead of, Claude Desktop): it does not
use the `.mcpb` file but the helper program from the ClipForge download.
Run one command in a terminal:

```sh
# Windows (your own ClipForge folder; right-click clipforge-mcp.exe > Copy as path)
claude mcp add --scope user clipforge -- "C:\Users\me\ClipForge\clipforge-mcp.exe"
# Mac
claude mcp add --scope user clipforge -- /Applications/ClipForge-Claude/clipforge-mcp
```

It prints a line starting with `Added`. `claude mcp list` shows it,
`claude mcp remove clipforge` takes it away again. `--scope user` makes it
available in every folder.

### Step 4 (recommended): give Claude the ClipForge skill

The **skill** teaches Claude how to edit with ClipForge: check the
connection first, find your files, show its plan before big changes, offer
a safety copy, try big changes first, wait properly for long exports, and
recipes for a podcast clean-up, podcast with music, family video, sport
slow motion, an upright version with the person in shot, picture-in-picture
and shorts from a long video. It also says honestly what Claude cannot do
(it cannot see or hear your video).

1. Download `ClipForge-<version>-claude-skill.zip` from the build page. Do
   not unzip it.
2. In Claude open **Customize > Skills**, click **Upload a skill** and
   choose the zip. Make sure **clipforge-editing** is switched on.
   (Older versions: **Settings > Capabilities**. The wording may differ.)
3. Claude Code loads the same skill when you are signed in with the same
   Claude account; or unzip it into `~/.claude/skills/` so that
   `~/.claude/skills/clipforge-editing/SKILL.md` exists.

The same guidance as one file is `CLAUDE.md` (next to `clipforge-mcp` in
the download), for Claude Code or a Claude Desktop Project:

- **Claude Code:** copy `CLAUDE.md` into your ClipForge folder in Documents
  (`Documents/ClipForge`, the folder that holds `projects`), then start
  Claude Code there: `cd ~/Documents/ClipForge` and `claude`. Claude Code
  reads `CLAUDE.md` automatically when it starts in that folder.
- **Claude Desktop:** create a Project called ClipForge, open its
  instructions and paste the text of `CLAUDE.md`. Start your video chats
  inside that Project.

The helper also gives Claude a shorter version of these rules on its own, so
this step is a bonus, not a requirement.

For developers: the skill is `claude/skill/clipforge-editing/` (SKILL.md
plus `recipes.md`, `tools.md`, `troubleshooting.md`); `claude/CLAUDE.md` is
the single-file version. `test/mcp/claude_guides_test.dart` fails when
either does not name every tool of the server.
`docs/tools/build_claude_bundles.py` builds the `.mcpb` (subcommand `mcpb`)
and the skill zip (`skill`); CI runs it and uploads the results.

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
- **The server does not start on a Mac.** Run the `xattr` command from step 2
  again after moving the folder, and check the path in the config.

### What Claude can do

| Area | Tools |
| --- | --- |
| Projects | list, show, create, duplicate, rename; shape (original, 9:16, 16:9, 1:1, 4:5); lower music under speech |
| Clips | add videos and photos, trim, split, remove, reorder; speed, volume, mute, fit, audio clean-up, voice focus, sound track / left or right side, brightness / contrast / saturation, zoom, transitions; cut out silences; relink a moved file |
| Text | titles, captions, import and export of `.srt` subtitles (also subtitles made for the uncut recording) |
| Speech (1.11) | transcribe in the background, read and search what is said, captions from speech, remove filler words gently, list and put back automatic cuts, make a short from one part |
| Music | add, move, trim, volume, fades, remove |
| Voice | add a separately recorded voice lined up with the video; line up, nudge or unlink a sound that is already there |
| Output | export an MP4 in full or small (720p) quality, with progress |

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
`assets/fonts`).

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
