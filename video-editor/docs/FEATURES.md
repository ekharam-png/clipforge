# ClipForge feature log

Everything ClipForge can do, grouped by area, with the version it arrived in
(the version is the one in Help > About ClipForge). Plain descriptions; the
in-app Help explains how to use each one. Newest changes are in
`CHANGELOG.md` ("What's new" in the app). Keep this file up to date with
every release: a test fails when CHANGELOG.md has a version this file does
not mention.

Versions so far: 1.0.0, 1.1.0, 1.2.0, 1.3.0, 1.4.0, 1.5.0, 1.6.0, 1.7.0,
1.8.0, 1.9.0, 1.10.0, 1.11.0, 1.12.0, 1.13.0, 1.14.0, 1.14.1, 1.15.0,
1.16.0.

## Projects

| Feature | Since | What it does |
|---|---|---|
| Project list | 1.0.0 | All your projects with a picture, length and date; tap one to open it. |
| Saving by itself | 1.0.0 | Every change is saved a moment after you make it. |
| Undo and redo | 1.0.0 | Take back a change, or bring it back. |
| Duplicate a project | 1.1.0 | Makes a copy to try something without risk. |
| Share project file / Open project file | 1.1.0 | Packs a project with all its media into one file to move it between phone and computer (also a backup). |
| "Not saved — retry" | 1.2.0 | Says clearly when a save failed and lets you try again. |
| Missing files and Find file | 1.2.0 | Shows which file is gone and lets you point at it again; checked before every export. |
| Unused copies cleaned up | 1.2.0 | Copies of media no project uses any more are deleted by themselves. |
| Drag and drop onto ClipForge (computers) | 1.3.0 | Drop videos, photos, music or a project file to start or add to a project. |
| History | 1.4.0 | A named list of your changes; tap one to go back to that point. |
| Long videos | 1.4.0 | Projects of 40 minutes and more stay smooth; a note for very long projects. |
| Version line and Copy version info | 1.4.0 | Shows exactly which build you have, for bug reports. |
| Rename project from the editor | 1.7.0 | File menu > Rename project. |
| Android keeps its own copy of every file | 1.8.0 | Videos no longer go missing when the gallery moves or deletes the original; the same file is stored once. |
| Find file: Search the gallery (Android) | 1.8.0 | Looks for a missing file by its name on the phone and copies it in. |
| Clean-up never deletes what is in use | 1.8.0 | Files the open project or its undo history still needs are always kept. |
| "Open in the app" mark | 1.9.0 | An open project is marked, so Claude does not change it at the same time; leftovers of a crash are ignored and cleaned up. |

## Feedback and the website (1.16.0)

| Feature | Since | What it does |
|---|---|---|
| Send feedback | 1.16.0 | Help > Send feedback… (phones: the three dots); also in About, Help, Settings. Problem, Idea, Praise or Question, a message, and an e-mail address if you want an answer. |
| "What is sent" box | 1.16.0 | Shows exactly what goes before you press Send: the message, the address if given, the app's version and build, the system's name and version. Never projects, file names or media. |
| Sent only when you press Send | 1.16.0 | One request, no second try, nothing in the background. Offline: a plain message, Open the feedback page in the browser, Copy my message. |
| Draft kept | 1.16.0 | What you wrote stays, also after closing the page, until it has been sent. |
| Feedback after an update that did not work | 1.16.0 | The message has Send feedback; a tick box (off) adds the last update log lines, shown first. |
| The ClipForge website | 1.16.0 | Downloads, install steps, walk-through, help, feedback form. Open the download page opens it; About shows its address; the old download page is a signpost. |
| Addresses that can move | 1.16.0 | The website's address travels with the update check, so a move needs no new version of the app. Feedback is only ever sent to the website's own address. |

## Finding things (1.15.0)

No new editing feature: the same commands, sorted so that they can be found. Every keyboard shortcut of 1.14.1 still works.

| Feature | Since | Where | What it does |
|---|---|---|---|
| Menus by task | 1.15.0 | Computer | File, Edit, Add, Clip, Sound, Text and speech, View, Playback, Help. One tree for the macOS menu bar and the bar in the window on Windows and Linux. The full tree is in the README ("Where everything is") and in the "menus" help article. |
| Greyed-out items say why | 1.15.0 | Both | An item that cannot be used stays in place and its label (menus, context menu) or second line (phone sheets) or tooltip (panel buttons) gives the reason: "Fit music to video (select a music clip)". One source for menus, side panel, phone and context menu. |
| Timeline context menu | 1.15.0 | Both | Right-click (computer) or hold (phone) a clip, sound, title or caption, overlay, marker or an empty place: the actions of that item. Holding and dragging a clip still moves it. |
| Settings page | 1.15.0 | Both | One page: Editing (Snap to playhead and edges, Show sound waves, Smooth preview on phones), Text window position (computers), Export (Use graphics card, remembered), Suggestions, Updates (Check for updates automatically, Check now, version), Claude (computers), About (About, Copy version info, What's new, Licences). File > Settings… / Ctrl+comma; phones: the three dots on the project list and in a project. The View menu and the Export window use the same switches. |
| Snapping can be turned off on a phone | 1.15.0 | Phone | Settings > Snap to playhead and edges (before: computers only). |
| Use graphics card is remembered | 1.15.0 | Both | The switch in the Export window is a setting now. |
| Suggestions | 1.15.0 | Both | One quiet line with a button, a cross and "Don't show again": music longer or shorter than the video (Fit to video), a voice added as music (Line up with the picture), a small first clip with "Same as the first clip" (Use 1080p), a clip of another shape (Fill / Blur / Crop…), a long clip with pauses (Remove silences…), music over speech (Lower the music), captions and the Text window never opened (Open Text), speech and no captions on a computer (Captions from speech…), the first voice track (See who is speaking). One at a time by priority, never during playback or under a dialog. Computer: a thin bar under the top bar; phone: a line above the tools that can be swiped away. |
| Notes in the Export window | 1.15.0 | Both | One line when an upright video is longer than a short (60 s), and one line about the graphics card on the first export. Not questions. |
| "Updated to X · What's new" | 1.15.0 | Both | A quiet line on the project list after the app became a newer version, with What's new one tap away; also Help > What's new. |
| Lower music under speech: one truth | 1.15.0 | Both | The per-track switches are what the export uses; the project-level switch (side panel, Sound menu, context menu) shows all / some / none of the tracks that are not speech and sets them all. |
| Phone: Add, Text, Split, More | 1.15.0 | Phone | The bottom bar with nothing selected. Add opens ONE sheet with everything addable (videos or photos, music or sound, voice recording, title, caption, overlay, good moment marker), each with a line of explanation. |
| Phone: More grouped like the menus | 1.15.0 | Phone | Clip / Edit / Sound / Text, with "Trim start to here" and "Trim end to here" (the I and O keys' actions). |
| Phone: one project menu | 1.15.0 | Phone | The three dots at the top of a project: Shape and size, Fade in and out, Publishing notes, Text, History, Markers, Settings, Help. |
| Computer layout from 840 dp | 1.15.0 | Tablet, phone held sideways | The side-panel layout instead of the phone bars. |
| Touch targets | 1.15.0 | Phone | Tool-bar and top-bar buttons at least 48 dp; a tool bar that has to scroll shows it. |
| What moved | 1.15.0 | Both | Shown once after updating from an older version: the biggest moves, "Show me Settings", What's new. |
| The same words everywhere | 1.15.0 | Both | Captions (on screen) vs subtitle file (.srt); Text (the window); Same as the first clip; Pause (K); Go to start; Crop and position; Move earlier / later; Check for updates automatically; sound, not audio. A test keeps them. |
| Three downloads | 1.15.0 | Release | Windows installer, Mac zip, Android APK. The guide is part of the install; no 32-bit Android APK; no separate read-me, .mcpb or skill files in a release. |

## Publishing kit and shorts (1.14.0)

ClipForge uploads nothing and has no logins: it makes the files and the text, the user posts them.

| Feature | Since | Where | What it does |
|---|---|---|---|
| Where is it going? | 1.14.0 | Both | Export presets from one table: YouTube (16:9, 1080p), Shorts / Reels / TikTok (9:16, 1080p), Instagram post (4:5 or 1:1), WhatsApp / Telegram (small file), Podcast audio (MP3 / M4A), Custom (the old controls). |
| Limit warnings | 1.14.0 | Both | A plain warning when a video is longer (60 s for short-form) or bigger (about 16 MB for WhatsApp) than the destination is sure to take; conservative values, "check the site". Never blocks. |
| Make a copy in this shape / Export as it is | 1.14.0 | Both | A destination with another shape never changes the project: either a new project in that shape (blurred background, Crop and position to follow) or the export keeps the project's shape. |
| Export several… | 1.14.0 | Both (computer: one chosen folder; phone: a gallery album named after the project) | Several destinations as one job with overall progress and cancel, clear file names, shape copies only in memory unless "Keep the shape copies as projects" is ticked. |
| Publishing notes | 1.14.0 | Both | Title, description, hashtags, chapters, optional short-form title and description; a copy button per field; undoable, named in the History. |
| Chapters from titles / captions… | 1.14.0 | Both | A YouTube-style list (first at 0:00, at least 10 s apart) from the titles, else the captions, else who is speaking; rule breaks in a typed list are named. |
| Text file with the kit | 1.14.0 | Both (phone: shared with the files) | "<Project> - text.txt": title, description, hashtags, tags, chapters, music credits and a section per exported file. |
| Share after export | 1.14.0 | Phone | The system share sheet with the exported file(s) and the text; "Copy title and description" stays visible. |
| Show in folder, Open upload page | 1.14.0 | Computer | Opens the file manager at the file; opens the upload page of YouTube / Instagram / TikTok in the user's browser. No embedded browser, no account. |
| Make a short from this… | 1.14.0 | Both (several sentences at once: computer; phone: one sentence + 30 / 45 / 60 s) | From a selection in the Text window: a new upright 1080p project with only that part, Short caption look, optional title at the top, start and end at a pause; opens it or stays. |
| Make a short from here… | 1.14.0 | Both | 30 / 45 / 60 s from the playhead (the timeline has no range selection). |
| Good-moment markers | 1.14.0 | Both (M key: computer; More: phone) | Markers dropped while watching, shown as flags on the ruler and in a list; they follow their picture through cuts. |
| Make shorts from markers… | 1.14.0 | Both | One short around each marker (20 s before to 25 s after, moved outward to pauses, never into a word or caption). |
| Claude: suggest_shorts, make_short extras, publishing notes, make_chapters, export_kit, markers | 1.14.0 | Computer | Candidate passages for Claude to judge; caption_style "short", title, snap_to_speech and warnings; notes and chapters; a kit as one background job; add / list / remove markers (70 tools). |

## Updates that finish on real PCs (1.14.1)

| Feature | Since | Where | What it does |
|---|---|---|---|
| Update by replacing the files in the folder | 1.14.1 | Windows | The script no longer renames the app folder (that never happened on real PCs). Safety copy, robocopy /MIR of the new files, a check against the version file, the safety copy mirrored back on failure. A held folder (Explorer, a terminal) does not matter; a held file is named and nothing changes. |
| The helper must report in | 1.14.1 | Computer | The script is started outside the app's process tree; the app closes only after the script's first line is in the log. PowerShell first, a plain cmd / robocopy script as the fallback; neither starts: the app stays open and offers the download page. |
| Update log, Copy details | 1.14.1 | Computer | update-log.txt in the state folder with the steps of the app and the scripts (kept across updates, cut at about 200 KB); "Copy details" on failure messages; Copy version info adds the app folder and the log's last 40 lines. |
| Tidy up | 1.14.1 | Windows | When the app runs from a folder ending in ".update-new": a one-time question (per version) to move into "ClipForge" (or the original folder) and remove proven older ClipForge folders next to it, listed with versions and untickable. |
| Windows installer | 1.14.1 | Windows | ClipForge-Setup.exe (Inno Setup): per user, no administrator rights, %LOCALAPPDATA%\Programs\ClipForge, Start-menu shortcut, uninstaller; the in-app updater works there. |
| Version file in the app folder | 1.14.1 | Windows | data/clipforge-version.json, written by the build; the scripts compare it, the app reads it to tell which ClipForge a folder holds. |

## Connect to Claude and updates, reworked (1.14.0)

| Feature | Since | Where | What it does |
|---|---|---|---|
| Connect / Disconnect buttons for Claude Desktop and Claude Code | 1.14.0 | Computer | The app finds both (Claude Desktop also from the Microsoft Store), shows a status light per target and connects with one button: Claude Desktop by adding only the "clipforge" entry to its settings file (dated backup first, unreadable files refused), Claude Code by running `claude mcp add` itself (an older connection is listed and replaced after asking). |
| "In use by Claude now" | 1.14.0 | Computer | The helper keeps a small file while a Claude session has it open; the page shows which Claude and when it was last used. |
| Test button | 1.14.0 | Computer | Starts the helper by itself, does the handshake and the quick self-test: PASS / FAIL independent of Claude. |
| "Restart ClipForge to finish", Later = at the next start | 1.14.0 | Computer | A downloaded and checked update that was not finished is applied when the app next starts; never while something is busy. |
| Update outcome and leftovers | 1.14.0 | Computer | "Updated to …" in one line (with a note when the folder is named after an old version), or the reason with Try again / Open the download page; ".update-new" / ".update-old" folders are removed only when the updater made them (marker). |

## Text window, sound waves, who is speaking (1.13.0)

| Feature | Since | Where | What it does |
|---|---|---|---|
| Text window | 1.13.0 | Both (phones: a full-screen sheet under More > Text) | Everything said or written as a readable document: Captions (whatever made them), Transcript (computer), Titles, with a switch. Takes the place of the Transcript column. |
| Paragraphs by speaker and pauses | 1.13.0 | Both | A caption starting with "Name:" is that speaker's; lines of one speaker join into a paragraph, the name shown once in the speaker's colour, a time at each paragraph; right to left for Hebrew / Arabic. |
| Follow playback, click to jump | 1.13.0 | Both | The line (for transcripts: the word) being spoken is marked and kept in view; a follow toggle that scrolling by hand turns off, and Now; click a sentence to move the playhead and select the caption; selecting a caption on the timeline shows it in the window. |
| Find in the text | 1.13.0 | Both | Search with a count, next and previous; Ctrl/Cmd+F. |
| Fix or delete captions in the Text window | 1.13.0 | Both (several at once with Shift-click: computer) | Double-click or Edit changes a caption in place; Delete caption(s); each one undo step named in the History. |
| Cut this part out of the video… | 1.13.0 | Computer | For the selected lines: shows from / to / length, asks, cuts with the editor's own cut and records it under Automatic cuts (kind "text") for Put back. |
| Copy all text, Save as text file, Save as .srt | 1.13.0 | Both | Plain, or with times and speaker names. |
| Text window at the right or under the preview | 1.13.0 | Computer | Resizable (at least 420 wide), place and size remembered. |
| Sound waves on the timeline | 1.13.0 | Both | A waveform in every sound item and a slim one along video clips whose sound is on; read once per file in the background and kept on disk; only the visible part is drawn. "Show sound waves" switch. |
| Who is speaking | 1.13.0 | Both | On speech tracks, talk is bright in the speaker's colour and pauses are dim; microphones recorded together are compared so that bleed does not count. |
| Snap to speech, next / previous speech start | 1.13.0 | Both (keys: computer) | Dragging snaps to where talk starts and ends; Ctrl/Cmd+Right / Left, buttons next to Play, Playback menu, More on phones. |
| Slim marks and the caption line | 1.13.0 | Both | Zoomed out, narrow caption blocks become slim marks, a line above them shows the caption under the playhead, and a tooltip shows a block's text. |
| Claude: get_captions, replace_in_captions, get_speech_map | 1.13.0 | Computer | Read captions as compact text; find and replace over all captions (dry run by default); who talks when from the sound, as speaker turns (62 tools). |

## Updates and Claude connection (1.12.0)

| Feature | Since | Where | What it does |
|---|---|---|---|
| "Version X is available" | 1.12.0 | Both | A quiet line on the project list when a newer version is out: What's new, Update, Later, Skip this version. |
| Check for updates (automatic, once a day; or by hand) | 1.12.0 | Both | Reads one small file (latest.json) from the release page; nothing else is sent or read. Can be switched off. |
| Update on Windows | 1.12.0 | Windows | Downloads the zip, checks size and SHA-256, unpacks next to the app, swaps the folders after the app closed and restarts; rolls back on failure; opens the download page when the folder cannot be written. |
| Update on Mac | 1.12.0 | Mac | The same with ClipForge.app; shows the new app in Finder instead when the app's place cannot be changed. |
| Update on Android | 1.12.0 | Android | Downloads the APK, checks it, hands it to the system installer (Android asks to confirm). |
| Open the download page | 1.12.0 | Both | Plan B for every update; the only way on Linux. |
| Connect to Claude page | 1.12.0 | Computer | Help > Connect to Claude…: helper installed or not, Save the Claude extension file…, the Claude Code line with Copy. |
| Claude helper kept up to date by the app | 1.12.0 | Computer | The app puts its helper into a fixed per-user folder at every start; Claude is pointed at it once. |
| Guide inside the helper (get_guide) | 1.12.0 | Computer | Claude reads how to work with ClipForge from the helper itself; the skill is a thin pointer. |
| Self-test for Claude (self_test) | 1.12.0 | Computer | A scripted check of the real tools with sample media in a temporary folder; PASS / FAIL table. |
| Exports survive Claude Code quitting (Windows) | 1.12.0 | Windows | The export / transcribe worker is started outside the helper's process tree. |
| Old → new values, dry-run setting lists, media table | 1.12.0 | Computer | Smaller and clearer answers for Claude. |
| Filler preview with the cut applied | 1.12.0 | Computer | The play button in Remove filler words skips the part that would be removed. |
| "Use it anyway" for a language pack | 1.12.0 | Computer | Accept a downloaded pack whose check failed, or remove it. |
| Transcripts inside project files | 1.12.0 | Both | Share project file carries the transcripts along. |
| Renaming to a taken name gives " (2)" | 1.12.0 | Both | On the project list and in the editor. |

## Speech (1.11.0)

"Where" says where each one exists: Computer = Windows, Mac and Linux only;
Both = phones too.

| Feature | Since | Where | What it does |
|---|---|---|---|
| Transcribe speech | 1.11.0 | Computer | Turns what is said into text with word times, using a speech program already on the computer (FFmpeg 8 whisper filter, whisper.cpp, faster-whisper, OpenAI whisper). One transcript per media file, kept in the project folder; survives every cut. |
| Language packs on demand | 1.11.0 | Computer | Small / Medium / Large per language, size shown first, downloaded only on a click, shared between languages, removable; "Use a model file I have". |
| Voices recorded separately are transcribed per speaker | 1.11.0 | Computer | The voice files are read instead of the muted camera sound; the transcript shows who speaks. |
| Captions from speech | 1.11.0 | Computer (the captions then show and export everywhere) | Caption items from the transcript: 1–2 lines, split at sentences and pauses, current caption look, one undo step. |
| Right-to-left lines (Hebrew, Arabic) | 1.11.0 | Both | Titles and captions are laid out right to left in preview and export (punctuation and numbers on the correct side). |
| Remove filler words | 1.11.0 | Computer | Finds "um", "uh", "э-э", "אה"…; Light / Normal / Strong; review list with jump rating; cuts kept apart; short dissolve on slight picture changes. |
| Automatic cuts, Put back | 1.11.0 | Computer (cuts made on a phone by Remove silences are recorded too) | Every automatic cut (fillers, silences) is remembered and can be put back one by one or all together. |
| Transcript column | 1.11.0 | Computer | Read-only text by phrase with time and speaker; click to jump; search. Since 1.13.0 it is the Transcript source of the Text window. |
| Claude: transcribe, read, find, captions, fillers, shorts | 1.11.0 | Computer | Tools for Claude to transcribe in the background, read and search the transcript, make captions, remove fillers gently, list and restore automatic cuts, and make a short from a part of the timeline. |
| Project names are unique | 1.11.0 | Both | A new project or copy whose name is taken gets "(2)", "(3)"… |

## Timeline & cutting

| Feature | Since | What it does |
|---|---|---|
| Add videos and photos | 1.0.0 | Pick several at once; they go after the selected clip or at the end. |
| Trim, split, delete, reorder | 1.0.0 | Drag the ends to trim, Split at the playhead, drag to reorder. |
| Live preview | 1.0.0 | Plays the edit as it will look, with seeking. |
| Transitions | 1.1.0 | Crossfade, fade through black, slide left, slide up. |
| Speed 0.25×–4× | 1.1.0 | Slow motion or faster, voice pitch kept. |
| Freeze frame | 1.1.0 | Holds the picture under the playhead still. |
| Remove silences | 1.1.0 | Cuts the quiet parts out of talking clips. |
| Apply to all clips | 1.2.0 | Gives every clip the same setting. |
| Keyboard shortcuts | 1.2.0 | Space, arrows, Delete, undo/redo and more (computers). |
| Adaptive silence finding and Sensitivity | 1.5.0 | Measures the background noise first; fewer or more cuts. |
| Duplicate a clip or title | 1.7.0 | A copy right after it (Ctrl/Cmd+D). |
| Copy settings / Paste settings | 1.7.0 | Gives another clip the same look, speed, sound, crop and fit. |
| Snapping | 1.7.0 | Drags line up with the playhead and the edges of other items (yellow line). |
| J / K / L, I / O, zoom keys | 1.7.0 | Play backwards / stop / forwards, start or end a clip at the playhead, zoom the timeline. |
| Frame-exact arrow keys | 1.7.0 | Step exactly one frame of the clip shown. |

## Picture

| Feature | Since | What it does |
|---|---|---|
| Shape 9:16, 16:9, 1:1, 4:5, original | 1.0.0 | The shape of the finished video. |
| Fit, Fill, Blur | 1.0.0 | How a clip of another shape sits in the frame. |
| Brightness, contrast, saturation, zoom | 1.1.0 | Rescue dark footage, zoom in. |
| Video size 720p / 1080p / 4K | 1.5.0 | Export size instead of the first clip's size. |
| Crop | 1.6.0 | Drag the corners of a frame on the picture, free or held to a shape. |
| Rotate and flip | 1.6.0 | For videos filmed the wrong way round. |
| Position | 1.6.0 | Choose which part stays in the frame with Fill or zoom. |
| Overlay (picture-in-picture, side by side, top and bottom, full) | 1.6.0 | A second video row above the clips, with its own trim, speed, volume and fades. |
| Fade in from black / Fade out to black | 1.7.0 | For the whole video and for each clip. |
| Filter (Warm, Cool, Black & white, Vintage, Vivid) and Warmth | 1.7.0 | One-tap colour looks. |
| Frames per second 24 / 25 / 30 / 60 / as clips | 1.7.0 | Export frame rate. |
| Smooth preview (phones) | 1.8.0 | Lighter video decoding while editing; exports unchanged. |
| Lighter preview while playing | 1.8.0 | Titles and the picture are only redrawn when they change. |

## Text

| Feature | Since | What it does |
|---|---|---|
| Titles | 1.0.0 | Text over the picture for a time. |
| Captions and subtitle (.srt) import / export | 1.1.0 | Lower text lines; bring in or save subtitle files. |
| Titles follow their clip | 1.2.0 | Text stays with its clip through cuts and speed changes. |
| Text fits vertical videos | 1.2.0 | Sized from the frame's short side, kept inside the frame. |
| Fonts with English, Russian and Hebrew letters | 1.7.0 | Classic, Modern, Elegant, Handwritten. |
| Outline, Shadow, styles, positions, alignment | 1.7.0 | Ready-made looks, top / middle / lower third / bottom, left / centre / right. |
| Appear / Disappear animations | 1.7.0 | Fade, slide up, pop. |
| Credits caption | 1.8.0 | Add credits at the end puts the music credits on the last 4 seconds. |

## Sound

| Feature | Since | What it does |
|---|---|---|
| Music with volume and fades | 1.0.0 | Add a song at the playhead; fade in and out. |
| Volume and mute per clip | 1.0.0 | How loud each clip's own sound is. |
| Clean up sound | 1.1.0 | Lowers hum, hiss and background noise (export, and instantly since 1.4). |
| Lower music under speech | 1.1.0 | Music gets quieter while someone talks. |
| Music fades out at the video's end | 1.2.0 | Instead of stopping dead. |
| Preview volume matches export | 1.2.0 | What you hear is what you get. |
| Voice focus | 1.3.0 | Clearer speech, quieter background. |
| Sound from (track, left / right only) | 1.3.0 | Choose which sound of the file to use. |
| Hear a sample | 1.3.0 | 15 seconds with and without your sound settings. |
| Instant sound processing | 1.4.0 | Clean-up and voice focus prepared in the background, heard in the preview. |
| Hear original | 1.4.0 | Compare with the untouched sound. |
| Sound tracks (up to 3) | 1.5.0 | Voice, Music, Effects rows with volume, mute and solo. |
| Separate sound to track / Put sound back | 1.5.0 | Move a clip's sound to its own track (L-cuts and J-cuts). |
| Video sound in one place | 1.5.0 | Mute or turn down all clips' own sound. |
| Move sound tracks up and down | 1.7.0 | Reorder the rows. |
| "What is this sound?" | 1.10.0 | Every sound file you add is asked about: Voice for the video, Music or Sound effect, guessed from its name and length. |
| Voice recorded separately, lined up by sound | 1.10.0 | A microphone or Zoom per-speaker file is compared with the camera's sound and placed in sync; own track named after the speaker; camera muted. |
| Voice follows its clip | 1.10.0 | Trim, split, speed, Remove silences and delete keep a lined-up voice in sync, in the same Undo step; several speakers each on their own track. |
| Nudge, Line up again, Unlink | 1.10.0 | Move a voice by 1 frame / 10 ms / 100 ms, retry the comparison, or end the link (the voice stays where it is). |
| Remove silences listens to the voice | 1.10.0 | With a lined-up voice the quiet parts are found in the voice(s), not in the muted camera sound. |
| Fit music to video | 1.8.0 | The music ends exactly with the video, with a 2-second fade-out. |
| Loop music | 1.8.0 | Short music repeats with soft cross-fades until the video ends. |
| Find free music | 1.8.0 | Search openly licensed music (Openverse), listen, download and add it. |
| Music credits | 1.8.0 | Licence and artist kept with the music; Copy credits for your post. |

## Export

| Feature | Since | What it does |
|---|---|---|
| Export full or small | 1.0.0 | Same quality as the clips or a smaller file. |
| Android: straight to the gallery | 1.1.0 | The finished video appears in Movies. |
| Share sheet on phones | 1.2.0 | Send the video to another app. |
| 60 fps export | 1.2.0 | Smooth motion for sport (frame rate choice since 1.7). |
| Graphics card export | 1.3.0 | Faster exports, falls back to the processor if needed. |
| Estimated size and free space check | 1.4.0 | Warns before a full disk spoils an export. |
| Keeps exporting with the screen off (Android) | 1.4.0 | A notification keeps the export running. |
| Sound only (M4A, MP3) | 1.7.0 | Export just the sound. |
| Safer animated titles in the export | 1.8.0 | Popping and fading titles are drawn in a way that does not crash FFmpeg. |

## Help

| Feature | Since | What it does |
|---|---|---|
| First-launch tour | 1.4.0 | "Would you like a quick tour?" then 8 steps over the real buttons. |
| Searchable help | 1.4.0 | Copes with typos; "Did you mean". |
| "?" hints | 1.4.0 | Next to the trickier settings. |
| What's new | 1.4.0 | This app's change list, in Help. |
| Keyboard shortcuts page | 1.7.0 | Every shortcut, in Help and the menus. |
| Feature log | 1.8.0 | This file. |

## Claude control

| Feature | Since | What it does |
|---|---|---|
| clipforge-mcp helper | 1.2.0 | Claude Desktop / Claude Code can list, create, edit and export projects (computers). |
| Voice focus and sound source tools | 1.3.0 | Same settings as the app. |
| Sound track and separate sound tools | 1.5.0 | Tracks, moving sound between them. |
| Crop, rotation, overlay tools | 1.6.0 | Same as the app. |
| Fades, filters, title styles, duplicate, copy settings, freeze frame, undo / redo | 1.7.0 | 42 tools. |
| fit_music_to_video | 1.8.0 | Fit or loop music to the video (43 tools). |
| Exports as background jobs | 1.9.0 | export_video answers with a job; get_export_status (progress, time left, result) and cancel_export; the render runs in its own process, survives a server restart and writes a .part file renamed when complete (45 tools). |
| Short answers, paged timeline | 1.9.0 | Edits answer with a summary (what changed, warnings, size and why, who saved last); detail "full" and get_project paging / time range for long projects. |
| Refuses to edit a project open in the app | 1.9.0 | Reading and exporting still work. |
| Dry runs | 1.9.0 | remove_silences (every cut and the total), set_clip_properties "all", apply_to_all, copy_clip_settings, separate_sound "all". |
| Warnings and reports | 1.9.0 | Music past the end, very short captions (min_caption_ms keeps them readable), output size and why, what Small changed, where music is lowered under speech. |
| Subtitles with source times | 1.9.0 | export_srt time_base "source"; import warns when a file no longer fits the cut. |
| add_voice and align_audio | 1.10.0 | Add a separately recorded voice lined up with the video (offset, confidence, drift, warnings); line up, set the offset of, nudge or unlink an existing sound; role / linked_clip / offset_ms in listings; a recipe for Zoom recordings (47 tools). |
| Fuller get_status | 1.9.0 | Program path, version, projects / fonts / jobs folders and FFmpeg first. |
| Claude Desktop extension (.mcpb) | 1.9.0 | One file to double-click instead of editing Claude's config by hand; one per system (Windows, Mac) on the build page. |
| ClipForge skill for Claude | 1.9.0 | A guide Claude loads by itself (upload the zip under Customize > Skills): plan first, safety copy, dry runs, long exports, recipes incl. shorts from a long video, and what it cannot do. |
| "Connect Claude to ClipForge" page | 1.9.0 | Step-by-step setup for Claude Desktop, the skill and Claude Code (docs/claude-setup.html, also in the downloads). |

## Platforms

| Feature | Since | What it does |
|---|---|---|
| Android, Windows, macOS apps | 1.0.0 | One code base; installers built by GitHub Actions. |
| Menu bar on Windows and Linux | 1.4.0 | File, Edit, Playback, Help along the top. |
| macOS menu bar with every command | 1.7.0 | With shortcuts. |
| Mac quit crash fixed | 1.3.0 | Quitting saves first and asks only when something would be lost. |
| Updates install over the old app (Android) | 1.8.0 | One fixed signing key; projects survive updates (one uninstall from 1.7). |

## Planned

From the roadmap in `docs/HANDOVER.md`; not built yet.

- AI voice separation (voice and background as two levels), on the device.
- Speech to text on phones, and a speech engine built into the app (1.11 uses a speech program installed on the computer).
- Signed and notarized Mac app, a signed Windows installer (the 1.14.1 installer is unsigned); updates for the Linux development build.
- Removing filler words ("um", "uh") and captions from speech (with the planned on-device transcription).
- Transcript-based editing, then a local AI assistant (computers, experimental).
- A separate personal "Publisher" helper that posts for the owner (on hold; see docs/HANDOVER.md). ClipForge itself will not upload or log in anywhere.
- Voiceover recording.
- Saved title styles and intro / outro templates.
- Skip back / forward 5 s buttons; zoom the preview; animated zoom and pan (Ken Burns).
- Camera-angle sync by sound for overlay items; rounded picture-in-picture corners.
- iPhone (on hold: needs an Apple account or sideloading).
- Stickers, keyframes, green screen.
- Jamendo music search (needs a client id; Openverse already includes much of Jamendo).
