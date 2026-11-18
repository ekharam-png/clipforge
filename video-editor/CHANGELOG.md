# What's new in ClipForge

Newest first. The version you have is in Help > About ClipForge (and at the
bottom of the project list). This file is also the "What's new" page in the
app's Help.

## 1.13.0 – 18 November 2026

- The **Text** window: everything said or written in the video as one readable page, instead of small blocks on the timeline. Computer: the **Text** button at the top, or Edit > **Text window** (Ctrl+Shift+T). Phone: **More** > **Text**. It takes the place of the Transcript column.
  - It shows the **Captions** on the timeline, whatever made them (a subtitle file you imported, captions from speech, typed ones), the **Transcript** when the speech was transcribed, and the **Titles**; a switch at the top chooses.
  - The lines of one speaker are joined into paragraphs with the time at the side. A caption that starts with a name and a colon ("Sam: …") is that speaker's: the name is shown once, in the speaker's colour. Hebrew and Arabic read right to left.
  - While the video plays, the line being spoken is marked and kept in view; scrolling by hand stops that and **Now** goes back. Click a sentence to go there; click a caption on the timeline and the window shows it.
  - **Find in the text…** (Ctrl+F) marks and counts every place, with next and previous.
  - Fix a wrong word: double-click a caption (or **Edit**), change it, **Enter**. **Delete caption** removes one, or several selected with Shift-click (computer). Each is one Undo step, named in the History.
  - **Cut this part out of the video…** (computer): select the lines of a part you do not want; ClipForge shows from when to when and how long, asks, and cuts. It is listed under **Automatic cuts…** so it can be put back.
  - **Copy all text**, **Copy with times and names**, **Save as text file…**, **Save as subtitle file (.srt)…**.
  - On a computer it sits at the right or under the preview (the three dots), and its edge can be dragged; ClipForge remembers.
- Sound waves on the timeline: every sound shows where it is loud and where it is quiet, and a video clip whose own sound is on has a slim wave along its bottom. ClipForge listens to each file once in the background ("Drawing sound…"); after that it is instant. **Show sound waves** (Playback menu; phones: **More**) turns it off on a slow device.
- See who is speaking: on speech tracks (one voice file per person, for example from a Zoom recording) the stretches where that person really talks are bright in the speaker's colour and the pauses are dim. The other person's voice heard faintly in a microphone is not shown as talk.
  - Dragging on the timeline also snaps to where talk starts and ends.
  - **Next speech start** / **Previous speech start**: the double arrows next to Play, Ctrl+Right / Ctrl+Left, or the Playback menu (phones: **More**). With a voice selected they follow that speaker, otherwise they stop wherever the speaker changes.
- Many captions on the timeline: when it is zoomed out so far that the blocks are too narrow for their words, they are drawn as slim marks, a thin line above them shows the caption under the playhead, and pointing at a mark shows its text.
- Claude control:
  - "Read me the captions" works for long captioned projects: Claude gets them as compact text with speakers and times.
  - "Change Sem to Sam in all captions": find and replace over every caption at once; Claude first says how many places it would change.
  - "Who talks when?" Claude can see the speaker turns from the sound alone, without a transcript, and cut by them.
- New help pages: "Read and search the text", "See who is speaking".

## 1.12.0 – 18 November 2026

- ClipForge updates itself. When a newer version is out, the project list shows a quiet line: "Version X is available", with **What's new**, **Update** and **Later** (the three dots have **Skip this version**).
  - It looks once a day when the app starts. The only thing it reads from the internet for this is one small file that says which version is the newest; nothing about you or your videos is sent. Switch it off in Help > **Check for updates automatically** (phones: the three dots on the project list); **Check for updates…** asks right now.
  - Windows and Mac: **Update** downloads the new version, checks that it is exactly the published file, then ClipForge closes and opens again as the new version. If anything goes wrong the old version stays as it was.
  - Android: ClipForge downloads and checks the new version and hands it to Android, which asks you to confirm. The first time, Android asks to allow installs from ClipForge.
  - **Open the download page** is always there as the other way. Your projects and videos are never touched by an update.
- Connect Claude once. Help > **Connect to Claude…** (computers) shows whether the Claude helper is installed, saves the Claude extension file straight from the app (**Save the Claude extension file…**) and shows the one line for Claude Code with **Copy**. From this version on ClipForge keeps the helper up to date by itself: after an app update there is nothing to install or upload again.
- Claude control:
  - The guide for Claude now lives inside ClipForge's helper, so it always fits the installed version. The skill is only a short pointer and never needs uploading again.
  - "Run the ClipForge self-test": Claude checks everything in under a minute with its own sample video in a temporary folder (your projects are not touched) and shows a list of what passed.
  - On Windows an export or a transcription started by Claude keeps running when Claude or Claude Code is closed.
  - Answers say exactly what changed (old value → new value) for a single change, and a dry run lists which settings would change.
  - A project's files are listed once with short names, so answers for long projects are much smaller; the first page is smaller too.
  - "What is the ClipForge status?" also says which helper is running and where it is.
- **Remove filler words…**: the play button in the list now plays the spot the way it would be after the cut (a moment before, skipping the filler, a moment after).
- A language pack whose check failed after downloading can be used with **Use it anyway** (or removed).
- **Share project file** now includes the transcripts, so speech does not have to be transcribed again on the other device.
- Renaming a project to a name another project has gives it " (2)".
- New help pages: "Updates", "Connect Claude (computer only)", "Check that Claude works (self-test)".

## 1.11.0 – 18 November 2026

- Speech to text, on the computer (Windows, Mac, Linux; not on phones). ClipForge can turn what is said in a video into text with the time of every word. Select a clip, open **Sound** and click **Transcribe speech…** (also Edit > Speech).
  - It uses a speech program that is already on the computer and finds it by itself: FFmpeg 8 with its "whisper" filter, whisper.cpp, faster-whisper or OpenAI whisper. If none is there, it says in plain words what to install.
  - Language packs, only when you ask. Nothing is bundled and nothing is downloaded by itself; the app stays the same size. Each language offers Small (about 140 MB: quick, more mistakes), Medium (about 470 MB: good) and Large (about 1.6 GB: best, every language). The size is shown before you press **Download**; **Remove** frees the space again. Packs for all languages are shared, never downloaded twice.
  - With a voice recorded separately, the voice files are transcribed, one per speaker.
  - The text stays right through cuts, speed changes and **Remove silences**: you transcribe once.
- **Captions from speech…** writes the captions for you: one or two lines, split at sentences and pauses, in the look your captions have, one Undo step. "Um" and "uh" are left out.
- Hebrew and Arabic titles and captions are now laid out right to left, in the preview and in the exported video: the full stop, question mark or number at the end of a line is on the correct side.
- **Remove filler words…** cuts "um", "uh" and the like, gently by default so the video does not get jumpy: **Light**, **Normal** or **Strong**; a list to review with each filler's time, length and whether the picture would jump there; cuts kept apart; a short dissolve where the picture changes a little.
- **Automatic cuts…** lists everything **Remove filler words…** and **Remove silences** cut out, with **Put back** for one cut and **Put back all**.
- **Transcript**: a column that shows what is said, phrase by phrase, with times and speakers. Click a phrase to go there; search for a word.
- Claude control:
  - Claude can now read what is said (it still cannot see the picture): it transcribes in the background, reads and searches the transcript, makes captions, removes fillers gently (always showing the numbers first), and can put any automatic cut back.
  - "Find the best shorts in a long video": Claude reads the transcript, proposes moments with a reason, and makes each one a new upright project with captions.
  - Claude never downloads a language pack by itself: it tells you the size and asks first.
  - Two projects can no longer end up with the same name: a new one gets "(2)". When a name is not enough to tell projects apart, Claude gets the ids and dates.
  - Shorter answers again (long lists of ids are counted, not listed; silence cuts are listed once), clearer wording when nothing changed or in a dry run, a warning when a voice that is not linked to its clip goes out of sync after a cut.
- Fixed: the "open in the app" mark could stay on the first project of a session. It now always belongs to the project that is really open.
- New help pages (computer only): "Transcribe speech", "Captions from speech", "Remove filler words", "The transcript".

## 1.10.0 – 17 November 2026

- **Voice recorded separately.** A voice that was recorded on its own file while the camera filmed (a separate microphone, a recorder, or Zoom's sound file per person) can now be put under the picture and kept there:
  - When you add a sound file (dropped on the window, **Music** > **My files**, or picked with **Add media**), ClipForge asks what it is: **Voice for the video**, **Music** or **Sound effect**. It guesses from the file's name and length.
  - A voice is lined up with the picture by itself: ClipForge compares it with the sound the camera recorded. It gets its own track, named after the speaker when the file name says who it is, and the camera's own sound is muted (you are asked).
  - The voice then follows its clip: trimming, splitting, speed, **Remove silences** and deleting keep it in sync, in the same Undo step. Several speakers: one file each, each on its own track.
  - **Remove silences** listens to the voice (all of them, with several speakers) instead of the muted camera.
  - If it cannot be lined up (the camera has no sound, or the sounds are too different), ClipForge says so and you nudge the voice by hand: 1 frame, 10 ms or 100 ms earlier or later. **Line up with the video again** retries; **Unlink** lets the voice stay where it is.
  - A sound that is already in a project as music can be turned into a lined-up voice: **This is a voice: line up with the video** (on a computer also Edit > Sound).
- Claude control: two new tools, to add a separately recorded voice lined up with the video and to line up, nudge or unlink a sound that is already there. Listings say whether a sound is a voice, music or an effect.
- New help page "Voice recorded separately (microphone, Zoom)".

## 1.9.0 – 17 November 2026

- While a project is open in ClipForge, Claude can no longer change it by mistake: Claude is told to ask you to close it first (it can still look at it and export it). A mark left behind by a crash is cleaned up by itself.
- Claude control, from a long test with Claude Code:
  - Long exports no longer fail with "Request timed out": an export runs on its own in the background, Claude follows its progress and gets the time left, and it keeps going even if Claude restarts. Claude can also stop it. The file only appears under its name when it is complete.
  - Shorter answers after each change (the length, what changed, warnings) instead of the whole timeline, so big projects (100+ pieces) work; Claude reads a long timeline page by page.
  - Warnings when music now runs past the end of the video (with the one-step fix, **Fit music to video**), when captions became very short after speeding up, and why the video has its size ("464x824 because the first clip is small").
  - Claude can try big changes first (remove silences, change all clips) and tell you what they would do without changing anything, can keep sped-up captions on screen long enough, and can save subtitles with the times of the original recording so they still fit after re-cutting.
  - The export result says what **Small** changed and, when music is lowered under speech, where and by roughly how much.

## 1.8.0 – 17 November 2026

- Android: fixed videos showing as **Missing** after a while. ClipForge now really keeps its own copy of every video, photo and song you add (the same file is stored only once), and copies files of older projects the next time you open them, if they are still there.
- **Find file** on Android can **Search the gallery** for the missing file by its name.
- New versions now install over the old one and keep your projects. Once only, from 1.7 to 1.8: save your projects with **Share project file**, uninstall the old app, install 1.8 and open them again (Help: "Android: installing and updating").
- **Fit music to video**: the music ends exactly with the video, with a fade-out. Music that is too short can **Loop**: it repeats with a soft cross-fade at each repeat.
- **Find free music**: search free music (Openverse) inside **Add music**, listen, and add it. Only music you may use in shared videos is shown; ClipForge keeps the credit, which you can copy (**Copy credits**) or put at the end of the video (**Add credits at the end**).
- Smoother editing on phones: the editor redraws much less while playing, and **Smooth preview** (in **More**) lightens video decoding while you edit.
- Titles that pop, slide or fade are made in a simpler way when exporting, which avoids a crash seen with some FFmpeg versions.
- Claude control: a new tool to fit music to the video (and loop it).
- A feature log, docs/FEATURES.md in the project's files, lists everything ClipForge can do and the version it came in. New help on free music, music credits, fitting music and smooth preview.

## 1.7.0 – 17 November 2026

- **Fade in from black** and **Fade out to black**: for the whole video (with nothing selected; phones: **More** > **Fade in and out**) and for each clip, picture and sound together (**Transition and fades**). The first clip can now start from black.
- **Duplicate** a clip or title (Ctrl/Cmd+D), and **Copy settings** / **Paste settings** to give another clip the same look, speed, sound, crop and fit (Ctrl/Cmd+Shift+C and V).
- Snapping: dragging on the timeline lines things up with the playhead and the edges of clips, titles, sounds and overlays, with a yellow line. Hold Alt (Option on a Mac) to place freely; **Snap to playhead and edges** in the Playback menu turns it off.
- Text: four fonts with English, Russian and Hebrew letters, **Outline**, **Shadow**, quick positions (top, middle, lower third, bottom), left / centre / right, ready-made styles, and animations to **Appear** and **Disappear** (fade, slide up, pop).
- **Filter** (Warm, Cool, Black & white, Vintage, Vivid) and **Warmth** in the Look panel.
- Export the sound only, as M4A or MP3, and choose the **Frames per second** (as the clips, 24, 25, 30 or 60).
- Keyboard: J / K / L to play backwards, stop and play forwards; I / O to start or end the selected clip at the playhead; + and - to zoom the timeline; the arrow keys now step exactly one frame of the clip being shown.
- Menu bar on computers: almost every editor command is in it now, with its shortcut; Help > **Keyboard shortcuts**. Sound tracks can be moved up and down (track menu).
- History: clearer names (pasting, duplicating, Reset look, Apply to all clips, splitting a photo), and reading a file's sound tracks is no longer an undo step.
- Claude control: fades, filters, warmth, text styles, sound-only export and frame rate, and new tools to duplicate a clip, copy clip settings, apply settings to all clips, freeze a frame, move a sound track, and undo or redo Claude's own edits.

## 1.6.0 – 17 November 2026

- **Crop**: crop any clip or photo by dragging the corners of a frame on the picture, free or held to 16:9, 9:16, 1:1 or 4:5.
- **Rotate left**, **Rotate right**, **Flip sideways** and **Flip upside down** for videos filmed the wrong way round.
- **Position**: choose which part of the picture stays in the frame with Fill or zoom, for example to keep a person in shot when a wide video becomes upright.
- **Overlay**: a second video row above your clips for picture-in-picture, side by side, top and bottom, or a full-screen cut-away to another camera. Drag it on the picture to place it and drag its corner to resize it; it has its own trim, speed, volume and fades.
- Menu bar on computers: **Crop and position…**, **Rotate right** and **Add overlay video or photo…** in the Edit menu.
- Claude control: crop, rotation, flips and position in set_clip_properties, and tools for overlays.

## 1.5.0 – 17 November 2026

- Sound tracks: up to three rows of sound under the video (for example Voice, Music and Effects) that play together, each with its own volume, mute and solo. Drag a sound up or down to move it to another track.
- **Separate sound to track…**: moves a clip's own sound to the Voice track and mutes the clip. The sound follows its clip until you drag it, so it can start before or after the picture.
- The sound of the video clips can be muted or turned down in one place: tap **Video** left of the timeline.
- Lower music under speech now works per track, and a Voice track counts as speech.
- Remove silences measures the background noise first, so it also finds the gaps in noisy phone recordings; **Sensitivity** gives fewer or more cuts.
- **Video size**: export at 720p, 1080p or 4K instead of the size of the first clip (in the Export window and the Shape menu).
- Claude control: tools for sound tracks, separating sound and the video size.

## 1.4.0 – 16 November 2026

- Help in the app: a quick tour the first time ClipForge opens, a searchable help screen that copes with typos, and small "?" buttons next to the trickier settings.
- Windows and Linux: a menu bar along the top of the window (File, Edit, Playback, Help).
- Instant sound: Clean up sound and Voice focus are prepared in the background, so you hear the result in the preview without exporting first.
- **History**: a list of your changes by name; click one to go back to that point.
- Long videos (up to 40 minutes and more): smooth timeline, faster clip pictures, a progress bar and Cancel for Remove silences, an estimated file size and a free space check before exporting, and phones keep exporting with the screen off.
- Version numbers: Help > **About ClipForge** shows exactly which build you have, and **Copy version info** copies it for bug reports.

## 1.3.0 – 16 November 2026

- **Voice focus**: makes speech clearer and background sound quieter.
- Choose which sound to use: another sound track, or only the left or right side.
- Hear a sample: listen to 15 seconds with and without your sound settings.
- Fixed a crash when quitting on a Mac; quitting now saves first and asks only when something would be lost.
- Drag and drop videos, photos and music from a folder onto ClipForge (computers).
- Exports can use the graphics card, and fall back to the processor if that fails.

## 1.2.0 – 15 November 2026

- Fixes from a full review: titles and captions now follow their clip when you edit, text fits on vertical videos, and the picture shape no longer changes when clips are reordered.
- Clearer saving: a "Not saved — retry" bar instead of silent failures, and a "Find file…" button when a video has moved.
- Keyboard shortcuts, a 1.25× speed button, 60 fps export, and a clean-up of unused copies.
- Claude control: Claude Desktop or Claude Code can edit and export your projects on a computer.
- Long edits with many cuts export with far less memory.

## 1.1.0 – 15 November 2026

- Transitions between clips: crossfade, fade through black, slide.
- Speed from 0.25× to 4×, with the voice pitch kept.
- Brightness, contrast, saturation, zoom and freeze frame.
- Clean up sound, lower music under speech, and remove silences.
- Captions, with subtitle (.srt) import and export.
- Duplicate a project, and move projects between phone and computer.
- Android: exported videos go straight to the gallery.
- No more black gap in the preview between two videos.

## 1.0.0 – 15 November 2026

- The first editor: add videos and photos, trim, split, delete and reorder clips, live preview, music with volume and fades, titles, picture shapes (9:16, 16:9, 1:1, 4:5), export in full or small size, undo and redo, saving by itself, and a project list.
