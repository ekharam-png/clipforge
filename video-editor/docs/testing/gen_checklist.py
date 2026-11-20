# Generates a ClipForge test checklist (e.g. ClipForge-Test-Round-3.html): a
# self-contained page that a person or a computer-use agent fills in and
# downloads with the results baked in.
#
#   python3 gen_checklist.py OUTPUT.html --build "ClipForge 1.4.0 (build 21) · 16 Nov 2026, 07:20 UTC · 877e482" [--round 4]
#
# --round picks the step list (ROUNDS below; default: 4). Round 3 = 1.4.0;
# round 4 = the computer round for 1.9.0 (what is new since 1.4.0 plus a
# regression core); round 4-phone = the Android phone round for 1.9.0,
# driven through Windows "Phone Link" screen mirroring. Each round has its
# own browser storage, so the pages do not mix their answers. Round 5 = the
# Windows computer round for 1.11.0 (only what is new in 1.10 and 1.11: a
# voice recorded separately, speech to text, captions from speech, the
# transcript, filler words, plus a 5-step regression core):
#
# Round 6 = the Windows computer round for 1.15.0 ("all the features" in
# one sitting: menus by topic, Settings, suggestions, sound, the Text
# window, speech, shorts and markers, publishing, Connect to Claude,
# updates, help); round 6-phone = the Android phone round for 1.15.0,
# driven through "Link to Windows" screen mirroring.
#
# Round 7 = the Windows computer round for 1.17.0 (EVERY feature before any
# 1.18 work, the new and risky things first: the in-app update, the long
# file that froze, everything 1.17 changed, then all the rest); round
# 7-phone = the Android phone round for 1.17.0. Their steps are numbered on
# the page and the instructions state the count. Both have the line
# "MEDIA FOLDER: <owner fills in>" near the top of the instructions;
# --media-folder "C:\\path" writes the owner's folder into that line (for
# the copy the owner hands to the tester; the pages in the repository keep
# the placeholder). Round 7-mac = round 7 for a Mac (derived from round 7:
# Cmd for Ctrl, the macOS menu bar, POSIX paths; a new first group with the
# install from ClipForge-macos.zip, Gatekeeper, the in-app update on a Mac
# and Connect to Claude; see "round 7, Mac" below):
#
#   python3 gen_checklist.py ClipForge-Test-Round-7.html       --round 7       --build "..."
#   python3 gen_checklist.py ClipForge-Test-Round-7-Mac.html   --round 7-mac   --build "..."
#   python3 gen_checklist.py ClipForge-Test-Round-7-Phone.html --round 7-phone --build "..."
#   python3 gen_checklist.py ClipForge-Test-Round-6.html       --round 6       --build "..."
#   python3 gen_checklist.py ClipForge-Test-Round-6-Phone.html --round 6-phone --build "..."
#   python3 gen_checklist.py ClipForge-Test-Round-5.html       --round 5       --build "..."
#   python3 gen_checklist.py ClipForge-Test-Round-4.html       --round 4       --build "..."
#   python3 gen_checklist.py ClipForge-Test-Round-4-Phone.html --round 4-phone --build "..."
#
# --build is the build the testers should have: the version line from the
# CI run (its summary shows it, and the downloads are named
# ClipForge-<version>-build<n>-...). The tester pastes what the app itself
# says (Help > About ClipForge > Copy version info) into "Version shown in
# the app", so a mismatch is visible at once.
import argparse, json, html, re, sys

# ---------------------------------------------------------------- round 3 (1.4.0)
# Steps: (id, title, expected, tag). tag: "", "Mac", "Windows" or "listen".
STEPS_3 = [
 ("Start and help", [
  ("start-open", "Install the new build and open ClipForge", "Mac: replace the app in Applications, then System Settings > Privacy & Security > Open Anyway. Windows: unzip and run clipforge.exe. The project list opens.", ""),
  ("start-version", "The app shows the expected version", "The small grey line at the bottom of the project list shows the same version and build number as the build named at the top of this page. Open About ClipForge (Mac: ClipForge menu; Windows: Help menu; phone: the three dots), click Copy version info and paste it into \"Version shown in the app\" at the top.", ""),
  ("tour-offer", "First-launch tour offer", "On the first start after installing, a dialog asks \"Would you like a quick tour?\" with Show me around / Not now. (It only appears once per computer; if it does not appear, note whether this computer ran this build before.)", ""),
  ("tour-run", "Run the tour to the end", "8 steps, each highlighting a real button, with Back, Next and Skip tour. At the end it asks to keep or delete the sample project.", ""),
  ("help-open", "Open Help", "The ? button at the top (or F1 on Windows, or Help in the menu bar) opens Help with a search box and a list of topics.", ""),
  ("help-typos", "Search Help with typos", "Type: musci, vocie, trascirpe. Each finds the right topic (music, Voice focus, automatic subtitles).", ""),
  ("help-hints", "Small ? next to settings", "In a clip's Sound panel, the ? next to Clean up sound or Voice focus opens the matching help article.", ""),
 ]),
 ("Menus and saving", [
  ("menu-win", "Windows: menu bar", "Windows only. File, Edit, Playback, Help at the top of the window. Ctrl+N new project, Ctrl+E export, F1 help.", "Windows"),
  ("menu-mac", "Mac: menu bar", "Mac only. The Mac menu bar has File, Edit (Undo, Redo, Delete, History), Playback and Help, and they work.", "Mac"),
  ("save-status", "Save status", "While editing, the top bar shows Saved, or Saving... briefly after a change.", ""),
  ("quit-clean", "Quit while editing, nothing running", "With a project open, quit (Cmd+Q / Alt+F4 / close window). It closes without asking. Reopen: the edits are there.", ""),
  ("quit-export", "Quit during an export", "Start an export, then try to quit. It asks whether to cancel the export or keep working.", ""),
  ("crash-loop", "No crash when opening and closing", "Open a project, play it, go back to the list. Repeat 5 times, then quit. The app never closes by itself.", ""),
 ]),
 ("Bringing files in", [
  ("drop-home", "Drag files onto the project list", "Computer only. Drag two videos from Finder/Explorer onto the project list: a new project opens with both.", ""),
  ("drop-editor", "Drag a file onto the timeline", "Drag a photo between two clips on the timeline: an insertion line shows and it lands there.", ""),
  ("drop-bad", "Drag an unsupported file", "Drag a PDF or text file in: a message lists it as not usable; nothing breaks.", ""),
 ]),
 ("Editing", [
  ("select-seek", "Select a clip", "Click a clip that is not under the playhead: the preview jumps to it.", ""),
  ("split", "Split", "Put the playhead inside a clip and press Split (or S): it becomes two clips.", ""),
  ("history-open", "History panel", "Make 3 changes (e.g. speed, split, title). Open History (Edit > History or the top-bar button; phone: More > History). The changes are listed by name, newest first.", ""),
  ("history-jump", "Jump back in History", "Click the oldest of the 3 steps: the project goes back to that point. Later steps look greyed but can be clicked to go forward again.", ""),
  ("keys", "Keyboard shortcuts", "Space plays/pauses, Ctrl/Cmd+Z undoes one step, Delete removes the selected clip, Left/Right arrows step a frame, Shift+arrow steps 1 second.", ""),
  ("title-size", "Title size", "Add a title, change its Size slider: the text gets bigger/smaller in the preview.", ""),
 ]),
 ("Sound (needs a person with headphones)", [
  ("sound-play", "Video sound plays in sync", "Play a clip with someone talking: sound is heard and lips match.", "listen"),
  ("clean-processing", "Clean up sound processes", "Turn on Clean up sound for a clip. After about a second the clip shows Sound xx% then finishes; the Sound panel shows progress with Stop.", ""),
  ("clean-hear", "Clean up sound is heard in the preview", "After processing, play the clip and switch Hear original on and off: background hiss/rumble is lower with it off.", "listen"),
  ("voice-focus", "Voice focus", "Set Voice focus to about 80%: after processing, speech sounds clearer and background music quieter (not removed).", "listen"),
  ("hear-sample", "Hear a sample", "Press Hear a sample: a dialog plays 15 seconds; With changes / Original sound different.", "listen"),
  ("music-fade", "Music fade", "Add a music file with a 2-second fade-out that runs past the end of the video: in the preview and in the export the music fades out at the video's end.", "listen"),
  ("duck", "Lower music under speech", "Turn it on and export: in the exported file, music drops while someone talks.", "listen"),
  ("sound-source", "Sound from: Left / Right / Track", "Only appears for some recordings (stereo, or several tracks). If shown, choosing Left only plays only that side. If it never appears, mark Not tested.", ""),
 ]),
 ("Long video and Remove silences", [
  ("long-load", "Load a long video (10-40 minutes)", "Import a long video. A note says long videos work but some steps take longer (once). Scrolling and zooming the timeline stays smooth.", ""),
  ("silences-progress", "Remove silences with progress", "On a talking clip, Remove silences shows a progress bar and a Cancel button, then says how many pieces it will cut into before applying.", ""),
  ("silences-apply", "Apply the cuts", "After applying, clip pictures appear on all pieces quickly and the app does not freeze for long. One Undo restores the clip.", ""),
 ]),
 ("Export", [
  ("export-gpu-info", "Graphics card info", "Open Export: it says Will use: Graphics card ... (or Processor). Write down exactly what it says.", ""),
  ("export-size", "Estimated size and space check", "The export window shows an estimated file size.", ""),
  ("export-run", "Export full quality", "Export finishes. The result says what was used (graphics card or processor) and how long it took. Write both down.", ""),
  ("export-play", "Exported file plays and matches", "Open the exported file in QuickTime / Movies & TV: picture, cuts, titles and sound match the preview.", ""),
  ("export-small", "Export small file", "Small export finishes and the file is clearly smaller.", ""),
 ]),
 ("Claude control (optional)", [
  ("cc-connect", "Connect Claude", "Follow the ClipForge Claude control setup guide. Ask Claude: What is the ClipForge status? It lists the projects folder and whether FFmpeg was found.", ""),
  ("cc-edit", "Claude edits a closed project", "Close the project in ClipForge, ask Claude to add a caption and export. Reopen the project: the caption is there.", ""),
 ]),
]

INSTR_3 = """You are testing ClipForge, a video editor, on this computer. Problems are expected; your job is to find them and write them down precisely.

RULES
- First fill in "Version shown in the app": in ClipForge open About ClipForge (Mac: ClipForge menu; Windows: Help menu; phone: the three dots on the project list), click Copy version info and paste the text. If it does not match the build named at the top of this page, say so in the Summary.
- Work through the steps below in order, in the ClipForge app.
- For each step choose a Status and write a Note. Start every note with the device ("Mac:" or "Windows:").
- Status meanings: Works = you saw exactly the expected result. Problem = something was wrong (say what you did, what happened, what you expected). Partial = part worked. Not tested = you could not do it (say why). Needs a person = you cannot judge it (sound, or drags you could not perform).
- Steps marked "needs a person with headphones" depend on hearing. Do the actions, check everything visible, then set Needs a person.
- If a drag does not work for you, try twice, then set Needs a person and say the drag could not be performed by you (it may still work for a human).
- Never delete, move or rename the user's files. Save exports into a new folder named clipforge-test-output next to the test videos.
- If the app closes by itself, write down exactly what you were doing, reopen it and continue. Fill in the Crash box.
- Do not guess. Only mark Works for what you actually saw.
- When finished, fill in the Summary box, then click "Download filled checklist" and give the downloaded file to the user."""

# ---------------------------------------------------------------- round 4 (1.7.0)
# What is new since 1.4.0 (1.5 sound tracks / separate sound / silences /
# video size, 1.6 crop / overlay, 1.7 fades / filters / text / duplicate /
# snapping / sound-only export / frame rate / keyboard / menus), plus a short
# regression core. Names are the app's own (assets/help/help_en.md).
# Steps: (id, title, do, expected, tag). tag: "", "Mac", "Windows",
# "listen" (ask the owner to listen) or "watch" (ask the owner to watch).
STEPS_4 = [
 ("Start and help", [
  ("start-open", "Install 1.9.0 and open ClipForge",
   "Mac: replace ClipForge in Applications with the new app and open it (if macOS blocks it: System Settings > Privacy & Security > Open Anyway). Windows: unzip the new download into a new folder and run clipforge.exe.",
   "The project list opens. Projects from earlier rounds are still listed and one of them opens without an error.", ""),
  ("start-version", "The app shows the expected version",
   "Read the small grey line at the bottom of the project list. Open About ClipForge (Mac: ClipForge menu; Windows: Help menu), click Copy version info and paste it into \"Version shown in the app\" at the top of this page.",
   "Both show version 1.9.0 and the same build as named at the top of this page. No red warning appears under the version box.", ""),
  ("help-new", "Help finds the new topics",
   "Open Help (the ? button at the top; F1 on Windows; Cmd+? on a Mac). Search for each of: overlay, snap, mp3, hebrew, fade. Close Help, then choose Help > Keyboard shortcuts in the menu bar.",
   "Each search shows the new article first: \"Overlay: picture-in-picture, side by side, cut-aways\", \"Snapping on the timeline\", \"Sound only and frames per second\", \"Text styles and animations\", \"Fade in from black, fade out to black\". Keyboard shortcuts opens a list that includes J / K / L, I / O and Ctrl+D.", ""),
 ]),
 ("Basics still work (short regression)", [
  ("reg-project", "Make the test project",
   "On the project list, drag files A, B and D (see the instructions) from Finder/Explorer onto the list, or make a new project and add them. Rename the project to \"Round 4 test\".",
   "The editor opens with three items on the main track in the order A, B, D, each with clip pictures. The top bar shows Saved (or Saving... briefly).", ""),
  ("reg-split", "Split, delete, undo",
   "Click clip A, put the playhead in its middle and press S. Click the second piece and press Delete. Press Ctrl/Cmd+Z once.",
   "S cuts A into two pieces. Delete removes the selected piece. One undo brings it back, so A is in two pieces again. Clicking a clip moves the preview to it.", ""),
  ("reg-clean", "Clean up sound still works",
   "Select the first piece of A, open Sound and switch on Clean up sound. Wait until it finishes. Play it and switch Hear original on and off while it plays.",
   "The clip shows Sound xx% and then finishes. Ask the owner to listen: background hiss or rumble is lower with Hear original off, and the voice stays in sync with the lips.", "listen"),
  ("reg-quit", "Quit while editing, and during an export",
   "With the project open and nothing exporting, quit (Cmd+Q on a Mac, Alt+F4 on Windows). Reopen ClipForge and the project. Then click Export > Full quality, and while it runs try to quit again; choose to keep working and let the export finish (save it as r4-quick.mp4).",
   "The first quit closes without asking, and after reopening the split is still there. During the export, quitting asks whether to cancel the export or keep working; keep working lets the export finish.", ""),
 ]),
 ("Sound tracks", [
  ("tr-add", "Add and delete sound tracks",
   "Click Sound track (the button above the row names, left of the timeline) four times. Then click the name of the last track on the left and choose Delete track in its menu.",
   "Each click adds a row of sound under the video with a name on the left. No more than three sound tracks can exist: the fourth click adds nothing (the button is greyed out or a message says so). Delete track removes the empty track. History shows \"Added sound track ...\" and \"Deleted sound track ...\".", ""),
  ("tr-music", "Music goes to a free track",
   "Put the playhead at 0:00. Click Music and pick file C. Put the playhead at 0:00 again, click Music and pick C again.",
   "The first music starts at 0:00 on the Music track. The second cannot overlap it, so it lands on another sound track (one is made if needed), also at 0:00.", ""),
  ("tr-mute-solo", "Mute and solo a track, mute the video sound",
   "Play from 0:00 and keep it playing. On the left of the timeline click M (mute) on the Music track, then click it again. Click S (solo) on the Music track, then again. Then click Video (the first name on the left), switch on Mute, then switch it off.",
   "M: that track's music goes silent while the voice continues. S: only that track is heard (no voice, no other music). Video > Mute: the voice of the clips goes silent while music still plays. Ask the owner to listen while you click. Each change is a step in History.", "listen"),
  ("tr-move-sound", "Move a sound to another track",
   "Drag the second music piece up or down onto a track where there is free space, and drop it. Then drag it onto the Music track at 0:00, where the first music already is. (If dragging fails: select it and choose another track under Track in its settings.)",
   "On free space it moves to that track. On a busy spot it does not overlap: it goes to the nearest free place. History shows \"Moved music to ...\". Undo puts it back.", ""),
  ("tr-move-track", "Move a whole sound track up and down",
   "Click the name of the second sound track on the left. In its menu click Move up. Open the menu again and click Move down.",
   "The whole row moves one place up together with its sounds, then back down. Each move is one History step (\"Moved sound track\") and can be undone.", ""),
  ("tr-duck", "Lower this track under speech",
   "Delete the second music piece. Click the Music track's name and switch on Lower this track under speech. Export > Full quality, save as r4-duck.mp4, and play the file in QuickTime (Mac) or Media Player / Movies & TV (Windows).",
   "In the exported file the music is clearly quieter while the person in A talks and comes back up in the pauses and over the photo. (The preview does not do this; only the export does.) Ask the owner to listen to the exported file.", "listen"),
 ]),
 ("Separate sound", [
  ("sep-do", "Separate sound to track",
   "Select the first piece of A, open Sound and click Separate sound to track…. If it offers \"Also the other clips with sound\", leave that off and confirm. Play that piece.",
   "The clip's sound appears as a piece on the Voice track right under the clip, and the clip shows as muted. Ask the owner to listen: the voice is heard once (not twice, no echo) and matches the lips.", "listen"),
  ("sep-lcut", "The sound follows its clip, then an L-cut",
   "Drag the left edge of that clip about 2 seconds to the right (trim). Then drag the Voice piece under it about 1 second to the right and drop it. Play across the start of the clip.",
   "After the trim the Voice piece is trimmed the same way (it follows its clip). After dragging it, the voice starts about 1 second after the picture and stays where you put it. Ask the owner to listen: the voice now lags the lips by about a second (that is the expected L-cut effect).", "listen"),
  ("sep-back", "Put the sound back",
   "Select the same clip, open Sound and click Put it back on the clip. Then press Ctrl/Cmd+Z, then Ctrl/Cmd+Shift+Z.",
   "Put back: the Voice piece disappears and the clip is no longer muted. Undo separates it again; redo puts it back again. History shows a step such as \"Put back on the clip\".", ""),
 ]),
 ("Remove silences", [
  ("sil-sensitivity", "Automatic silence level and Sensitivity",
   "Add file E at the end of the main track (if you have no E, use the second piece of A). Select it, open Sound and click Remove silences. When the result shows, click Fewer cuts, Automatic and More cuts under Sensitivity in turn. Write down the gap count and the \"Background noise about ... dB\" line for each.",
   "A progress bar with Cancel, then a line like \"Background noise about -45 dB; quieter than -34 dB counts as silence\" and a button like \"Remove 5 gaps\". Changing Sensitivity updates the count at once without scanning again; Fewer cuts gives no more gaps than Automatic, More cuts no fewer. On a noisy phone recording it still finds the pauses.", ""),
  ("sil-apply", "Apply the cuts",
   "With Automatic chosen, click the Remove ... gaps button. Play across two of the new cuts. Then press Ctrl/Cmd+Z once, then Ctrl/Cmd+Shift+Z.",
   "The clip becomes pieces with clip pictures, without a long freeze. Ask the owner to listen: words are not chopped at the cuts. One undo brings back the single clip; redo cuts it again. History has one step for it (for example \"Cut clip 4 into 6 pieces\").", "listen"),
 ]),
 ("Picture: video size, crop, rotate, position", [
  ("vsize", "Video size",
   "Open Export. Under Video size you see As first clip, 720p, 1080p, 4K. Choose a size different from file A's own size (if unsure, 720p), keep Full quality, export as r4-size.mp4. Then open the Shape button (next to Export): it also lists Video size. Set Video size back to As first clip there.",
   "The exported file has the chosen size (720p of a wide video = 1280 x 720). Check it: Mac: Finder > Get Info > More Info > Dimensions; Windows: right-click > Properties > Details > Frame width / Frame height. The Shape menu shows the same choices with a tick on the current one.", ""),
  ("crop-frame", "Crop with handles and shapes",
   "Select the first piece of A. In the side panel open Crop. On the preview drag the bottom-right corner of the frame inwards, then drag inside the frame to move it. Click 1:1, then drag a corner. Click 9:16, then Free, then Original.",
   "The preview shows the whole picture with a frame, 8 grips and the outside dimmed. A corner drag makes the frame smaller; a drag inside moves it. 1:1 / 9:16 make the frame square / tall and keep that shape while you drag; Free allows any shape; Original returns to the picture's own shape. Each drag is one History step (\"Crop on clip 1\" or similar).", ""),
  ("crop-rotate", "Rotate and flip",
   "With the same clip selected, in Crop click Rotate right, Rotate right, Rotate left, Flip sideways, Flip upside down. Click Reset crop and position. Then choose Edit > Rotate right in the menu bar, and Ctrl/Cmd+Z.",
   "Each button turns the picture a quarter turn or mirrors it, at once, in the preview. Reset puts it back to normal. The menu item turns it like the button and undo turns it back. History shows steps like \"Rotated clip 1\" and \"Flipped clip 1\".", ""),
  ("crop-position", "Position with Fill (keep the person in shot)",
   "Click Shape and choose 9:16 upright. Select the first piece of A, open Look and choose Fill. In Crop move Left – right fully to one end, then the other, then put the person in the middle. Then choose Fit in Look and look at Position again. Finally choose Fill again and set Shape back to Original (as the first clip).",
   "With Fill, Left – right changes which part of the wide picture fills the tall frame, so the person can be kept in the middle. With Fit (zoom 1) Position has no effect and the panel says so.", ""),
 ]),
 ("Overlay (picture-in-picture)", [
  ("ov-add", "Add an overlay",
   "Put the playhead at 0:05. Click Overlay in the side panel's Add area (or Edit > Add overlay video or photo…) and pick file B.",
   "B appears as a small picture in the bottom-right corner of the preview from 0:05. A new Overlay row appears above the main clips with B on it. History: \"Added overlay\".", ""),
  ("ov-pip", "Corner, size, frame, drag on the picture",
   "Select the overlay. Under Layout keep Picture-in-picture, set Corner to the top left, set Size to about 50%, switch on White frame. Then on the preview drag the overlay to the middle, and drag its corner grip outwards.",
   "Corner moves it to the top left, Size makes it bigger, White frame draws a thin border. Dragging it on the preview moves it anywhere (Layout changes to Free position); dragging the corner grip resizes it.", ""),
  ("ov-layouts", "Side by side, top and bottom, full screen",
   "Choose Layout Side by side, then Top and bottom, then Full screen. For each, play from 1 second before the overlay starts to 1 second after it ends.",
   "Side by side: your video on one half, B on the other. Top and bottom: one above the other. Full screen: B covers the whole picture while it plays, then your video comes back. Ask the owner to watch: B plays smoothly and starts and stops at the right moment (not frozen, not jumping).", "watch"),
  ("ov-row", "Move, trim and mute the overlay",
   "On the Overlay row drag the overlay about 3 seconds to the right, then drag its right end to make it shorter. In Sound, speed and fades switch on Mute overlay sound while playing, then off. Set Layout back to Picture-in-picture.",
   "It moves and trims on its row. Mute overlay sound silences B while your video's sound continues (ask the owner to listen). History: \"Moved overlay\", \"Trimmed overlay\", \"Muted overlay\".", "listen"),
 ]),
 ("Look and fades", [
  ("look-filter", "Filters and warmth",
   "Select the first piece of A, open Look. Under Filter click Warm, Cool, Black & white, Vintage, Vivid, None in turn. Choose Vintage. Move Warmth fully left, fully right, then about halfway to warm. Click Reset look, then Ctrl/Cmd+Z.",
   "Each filter changes the preview at once (Black & white has no colour; None removes it). Warmth makes the picture more orange or more blue on top of the filter. Reset look removes filter and warmth; one undo brings both back (\"Reset look on clip 1\" in History). Leave Vintage + warm on.", ""),
  ("fade-project", "Fade the whole video in and out",
   "Click an empty place on the timeline so nothing is selected. In the side panel set Fade in from black to about 2 s and Fade out to black to about 2 s. Play from 0:00, then play the last 4 seconds.",
   "The video starts from black and comes up; at the end the picture, titles, overlay and all sound go down to black and silence together. Ask the owner to watch and listen.", "watch"),
  ("fade-clip", "Fade one clip",
   "Select clip B on the main track, open Transition and fades, set Fade out to black to about 1 s. Play across the end of B.",
   "B's picture goes to black over its last second and B's own sound fades with it; the next item then starts normally. Ask the owner to watch and listen.", "watch"),
 ]),
 ("Titles", [
  ("title-font", "Fonts and styles",
   "Put the playhead at 0:02, click Title and type: Round 4 title. In the title panel click Font Classic, Modern, Elegant, Handwritten in turn. Then try two different Styles.",
   "Each font visibly changes the letters in the preview. A Style changes several settings at once.", ""),
  ("title-lang", "Hebrew and Russian letters",
   "Put the playhead at 0:10, click Title. Copy this text from this page and paste it into Text: שלום עולם / Привет, мир . Click each of the four fonts.",
   "In every font the Hebrew and Russian letters show properly (no empty boxes, no question marks). The Hebrew words keep their order: read right to left, שלום comes before עולם.", ""),
  ("title-outline", "Outline, shadow, position, alignment",
   "Select the first title. Switch on Outline. Switch Shadow off, then on. Switch Dark box behind text on, then off. Under Position click Top, Middle, Lower third, Bottom. Then click Left, Centre, Right.",
   "Outline draws a line around the letters; Shadow adds or removes a soft shadow; the box appears and goes. Each Position moves the text to that height; Left / Right line the text up and move it to that side.", ""),
  ("title-anim", "Appear and Disappear",
   "Set Appear to Slide up and Disappear to Pop. Play from 1 second before the title to 1 second after it. Then set Appear to Fade and play again.",
   "The title slides up into place at its start and pops away at its end, each in less than half a second; with Fade it fades in. Ask the owner to watch.", "watch"),
 ]),
 ("Duplicate, copy settings, snapping", [
  ("dup", "Duplicate a clip and a title",
   "Select clip B on the main track and press Ctrl/Cmd+D. Then select the first title and click Duplicate in the tool bar. Then delete the copy of the title.",
   "A copy of B appears right after B with the same settings (its fade out). A copy of the title appears right after it on the timeline. History: \"Duplicated ...\" for each.", ""),
  ("copy-paste", "Copy settings, Paste settings",
   "Open the Edit menu: look at Paste settings. Close it. Select the first piece of A (Vintage, warm, Fill) and press Ctrl/Cmd+Shift+C. Select the photo D and press Ctrl/Cmd+Shift+V. Then select the copy of B and choose Edit > Paste settings. Press Ctrl/Cmd+Z once.",
   "Before copying, Paste settings is greyed out. After pasting, the photo has the same look (Vintage, warmth) and fit as A, but keeps its own length. The copy of B gets the same look, and its fade is not changed. History: \"Pasted settings on ...\". One undo takes back only the last paste.", ""),
  ("snap", "Snapping",
   "Put the playhead at 0:08. Slowly drag the right end of the first title (on the timeline) towards the playhead. Then drag the end of the music towards the end of a clip.",
   "When it comes close, the edge jumps onto the playhead / clip edge and a yellow line shows where it snapped.", ""),
  ("snap-off", "Placing freely: Alt / Option, and the menu switch",
   "Hold Alt (Option on a Mac) while dragging the same title end slowly past the playhead. Then untick Playback > Snap to playhead and edges in the menu bar and drag again without Alt. Tick it again afterwards.",
   "With Alt / Option held there is no jump and no yellow line. With the menu item unticked, no snapping at all. After ticking it again, snapping works. (If you cannot hold a key while dragging, set Needs the owner for that part.)", ""),
 ]),
 ("Keyboard", [
  ("keys-jkl", "J / K / L",
   "Click an empty place on the timeline (not a text box). Press L, wait 2 seconds, press K. Press J, wait 2 seconds, press K.",
   "L plays forwards, K stops, J goes backwards: the playhead jumps back in small steps and the picture changes (not smooth playback; that is expected).", ""),
  ("keys-io", "I / O: start and end a clip at the playhead",
   "Select clip B on the main track. Put the playhead about 1 second into it and press I. Put the playhead about 1 second before its end and press O. Then press Ctrl/Cmd+Z twice.",
   "I: B now starts at the playhead (the part before is trimmed away). O: B ends at the playhead. Each is one History step, and each undo restores one.", ""),
  ("keys-frame", "Frame step, second step, zoom",
   "Pause on clip A and note the time shown. Press Right 30 times and note the time; press Left 30 times. Press Shift+Right once. Press + three times, then - three times. If you have file F (25 or 60 fps), add it and repeat Right 30 times on it.",
   "Each Right / Left moves one frame (the picture changes slightly with each press). 30 presses move about 1.0 s on a 30 fps clip (1.2 s at 25 fps, 0.5 s at 60 fps), and Left 30 times returns to the same time. Shift+Right moves 1 second. + zooms the timeline in, - zooms out. Write down the times you saw.", ""),
  ("keys-typing", "Shortcuts are off while typing",
   "Select a title, click into its Text box and type: jkl iso sd (with the spaces). Then click outside the box.",
   "The letters only go into the text. Nothing plays, splits, trims or duplicates (History gets only the text change).", ""),
 ]),
 ("Menus", [
  ("menu-mac", "Mac: menu bar contents",
   "Mac only. Open each menu in the Mac menu bar: ClipForge, File, Edit (and its Sound, Shape and Video size submenus), Playback, Help. Write down anything missing or without a shortcut.",
   "Edit has Undo, Redo, History, Duplicate (Cmd+D), Copy settings, Paste settings, Delete (⌫), Split, start / end clip at playhead, Freeze frame, Remove silences, move clip earlier / later, Crop and position…, Rotate right, add title / caption, Add overlay video or photo…, and the Sound (Add sound track, Separate sound, Put sound back, Lower music under speech), Shape and Video size submenus. Playback has Play (Space), Play backwards / Stop / Play forwards (J / K / L), go to start / end, previous / next frame, zoom in / out and Snap to playhead and edges (ticked). Help has Keyboard shortcuts.", "Mac"),
  ("menu-mac-keys", "Mac: one key press = one action",
   "Mac only. Select clip B, put the playhead in its middle and press S once. Open History. Press Cmd+D once and look at History again. Press L, then K. Then undo the split and the duplicate.",
   "Exactly one \"Split ...\" step and one \"Duplicated ...\" step appear (not two each); L and K play and stop normally. (The Mac menu also knows these keys; this checks that they do not fire twice.)", "Mac"),
  ("menu-win", "Windows: menu bar contents and shortcuts",
   "Windows only. Open File, Edit (and its Sound, Shape, Video size submenus), Playback and Help in the bar at the top of the window. Use Edit > Duplicate and Playback > Next frame once each. Undo, then press Ctrl+Shift+Z; undo again, then press Ctrl+Y. Press Ctrl+Shift+H twice and F1.",
   "The same items as in the Mac step, each with its shortcut (Redo shows Ctrl+Shift+Z; Delete shows \"Delete (or Backspace)\"). Duplicate from the menu adds exactly one copy; Next frame moves one frame. Ctrl+Shift+Z and Ctrl+Y both redo. Ctrl+Shift+H shows and hides History; F1 opens Help.", "Windows"),
 ]),
 ("History and undo", [
  ("hist-names", "History names of the new edits",
   "Open History (Ctrl/Cmd+Shift+H or Edit > History). Copy the newest 15 names into the note.",
   "Each step has a clear name, newest first, similar to \"Duplicated clip 3\", \"Pasted settings on clip 5\", \"Filter Vintage ...\", \"Fade in from black\", \"Font Elegant on title ...\", \"Added overlay\", \"Moved sound track\", \"Rotated clip 1\". No vague names like just \"Changed\" or \"Edit\", and adding a file did not create a \"Read sound tracks\" step.", ""),
  ("hist-undo", "Undo and redo the new edits",
   "Press Ctrl/Cmd+Z 8 times, watching the preview and the timeline after each, then Ctrl/Cmd+Shift+Z 8 times. Then in History click a step about 10 back, then the newest step.",
   "Each undo takes back exactly one of the latest changes, and each redo brings it back; the project ends exactly as before. Clicking an older step in History goes back there (later steps look grey); clicking the newest restores everything.", ""),
  ("hist-reopen", "Everything is saved",
   "Go back to the project list and open \"Round 4 test\" again.",
   "Everything is still there: sound tracks with their mute / lower-under-speech settings, Fill and position, overlay and its layout, filters, fades, title fonts, Hebrew / Russian text, outline and animations. History starts empty again (that is expected).", ""),
 ]),
 ("Export", [
  ("exp-full", "Export the full project",
   "Open Export. Make: Video, Full quality, Frames per second: As clips, Video size: As first clip. Export as r4-full.mp4.",
   "It finishes and says what was used (graphics card or processor) and how long it took. Write both down.", ""),
  ("exp-watch", "The export looks like the preview",
   "Play r4-full.mp4 in QuickTime (Mac) or Media Player / Movies & TV (Windows) and compare it with the ClipForge preview.",
   "Ask the owner to watch: cuts, Fill framing, overlay position, layout and timing, filters and warmth, fades from and to black, fonts, Hebrew / Russian text, outline, title positions and animations all match the preview.", "watch"),
  ("exp-listen", "The export sounds right",
   "Play r4-full.mp4 with sound from start to end.",
   "Ask the owner to listen: voice in sync with the lips, the voice of the trimmed clip not doubled, music lower under speech, the clip fade and the end fade, overlay sound present, no clicks or gaps at the cuts.", "listen"),
  ("exp-fps", "Frames per second",
   "Open Export, open Frames per second, choose 25 and export as r4-25fps.mp4. Check the frame rate: Mac: open it in QuickTime > Window > Show Movie Inspector; Windows: right-click > Properties > Details > Frame rate.",
   "The choices are As clips, 24, 25, 30, 60. The file reports 25 frames per second and has the same length as r4-full.mp4.", ""),
  ("exp-m4a", "Sound only: M4A",
   "Open Export, set Make to Sound M4A and export as r4-sound.m4a. Play it in QuickTime / Music (Mac) or Media Player (Windows).",
   "The picture settings (Video size, Frames per second) are hidden. An .m4a file is made with the same length as the video. Ask the owner to listen: it has the same mix as the video.", "listen"),
  ("exp-mp3", "Sound only: MP3",
   "Open Export, set Make to Sound MP3 and export as r4-sound.mp3. Play it.",
   "An .mp3 file is made and plays with the same sound as the M4A. If instead it says \"Export the sound as M4A instead\", write that down exactly. Ask the owner to listen.", "listen"),
 ]),
 ("New in 1.8.0", [
  ("m18-fit", "Fit music to video",
   "Make a new project \"Round 4 music\" with file B (the short video). Add music C. Select the music and click Fit music to video.",
   "The music now ends exactly where the video ends, with a short fade-out. History shows a step like \"Fitted music to the video\". Ctrl/Cmd+Z undoes it in one step.", ""),
  ("m18-loop", "Loop short music",
   "In \"Round 4 music\", add file A after file B so the video is longer than the music (if the music is still longer, skip and set Not tested). Select the music and click Fit music to video, and choose to loop it.",
   "The music piece shows a repeat icon and \"loops\", with marks where it repeats, and reaches the end of the video. Ask the owner to listen to the preview at the repeat points: no gap or click.", "listen"),
  ("m18-free", "Find free music",
   "Click Music (Add music). The window opens on Find free music. Search for \"piano\". Play the preview of one result, then click Use.",
   "Results show title, artist, length and licence (CC0, Public domain, CC BY or CC BY-SA). The preview plays. After Use the music is downloaded and added to the timeline. If it says it is offline or shows an error, write the exact text.", ""),
  ("m18-credits", "Music credits",
   "Select the downloaded music. Click Copy credits and paste into the note. Then click Add credits at the end.",
   "The pasted text names the track, the artist, the licence and a link. A caption with the credits appears over the last 4 seconds of the video.", ""),
  ("m18-find", "Find a missing file",
   "Only if a project shows a red \"Missing\" clip (otherwise set Not tested): click Find file....",
   "On a computer a file chooser opens; choosing the file brings the clip back. (On an Android phone it offers \"Search the gallery\": the owner tests that on the phone.)", ""),
 ]),
 ("New in 1.9.0", [
  ("m19-lock", "Opening and closing projects looks the same as before",
   "1.9.0 marks a project as \"open in the app\" so that Claude does not change it at the same time; you should not notice it. Open \"Round 4 test\", make one small change (for example move a title), go back to the project list and open it again. Then, with the project open, quit ClipForge (Cmd+Q on a Mac, Alt+F4 on Windows), start it again and open the project. Finally open \"Round 4 music\" and go back.",
   "Nothing new is visible: no message about the project being open or locked, no extra waiting, no new button. Every time the project opens normally with the last change in it, also after quitting with the project open. The top bar shows Saved as before.", ""),
  ("m19-long", "Export a long project (20 minutes or more)",
   "Only if the owner has a project or a video of 20 minutes or more (ask; otherwise set Not tested). Open it (or make a project \"Round 4 long\" with that video), click Export > Full quality and save it as r4-long.mp4. Leave the computer alone while it runs. Write down the length of the project, the time the export took and the file size.",
   "The progress moves steadily to 100% without stopping for minutes at one value, the app stays usable (the window can be moved, Cancel export is there), and it finishes with a result that says what was used and how long it took. The file has the project's length and plays to the end. Ask the owner to watch the last minute: picture and sound are still in sync.", "watch"),
  ("m19-claude", "Claude is connected and names the same version (optional)",
   "Only if the owner uses Claude with ClipForge (otherwise set Not tested). The owner has installed the ClipForge extension in Claude Desktop, or added it to Claude Code (guide: \"Connect Claude to ClipForge\"). With \"Round 4 test\" OPEN in ClipForge, ask Claude: \"What version of ClipForge are you connected to?\" and then \"Add the caption Hello at 0:03 in my project Round 4 test\". Then go back to the project list in ClipForge and tell Claude to try again. Open the project.",
   "Claude names the same version and build as About ClipForge. While the project is open in the app, Claude says it cannot change it because it is open in ClipForge and asks to go back to the project list (nothing is changed). After going back, Claude adds the caption, and it is there at 0:03 when the project is opened.", ""),
 ]),
]

INSTR_4 = """You are testing ClipForge 1.9.0, a video editor, on the owner's computer (a Mac or a Windows PC). Problems are expected; your job is to find them and write them down precisely. This round checks what is new since 1.4.0 (sound tracks, separate sound, Remove silences, video size, crop and position, overlays, fades, filters, text styles, duplicate and copy settings, snapping, sound-only export, frame rate, keyboard and menus, from 1.8.0 fit and loop music and free music search, and from 1.9.0 the invisible \"open in the app\" mark, long exports and the Claude connection) plus a short check that the basics still work. The Android phone has its own page (Round 4 phone).

BEFORE YOU START
- Fill in "Device" (for example "MacBook Air M5, macOS 26.6" or "Windows 11 laptop") and "Tester".
- Fill in "Version shown in the app": in ClipForge open About ClipForge (Mac: the ClipForge menu; Windows: the Help menu), click Copy version info and paste the text. If it does not match the build named at the top of this page (a red warning appears), tell the owner and say so in the Summary.
- Test files: ask the owner where the test videos are (Round 3 used the same folder). You need:
  A. a talking video, 1-3 minutes, one person speaking with some pauses, filmed wide (landscape);
  B. a second short video, 10-30 seconds, anything (used as the overlay);
  C. a music file (MP3 or M4A), at least 1 minute;
  D. a photo;
  E. optional: a phone recording with background noise and pauses (for Remove silences; otherwise use A);
  F. optional: a video filmed at 25 or 60 frames per second (for frame stepping).
  If something is missing, ask the owner. Do not download files from the internet.
- Most steps use one project, "Round 4 test", made in the step "Make the test project". Do the steps in order: later steps build on earlier ones.

RULES
- Each step has "Do" (exact actions) and "Expected" (what should happen). Do the actions exactly, then compare with Expected.
- For each step choose a Result and write a Note. Start every note with the device ("Mac:" or "Windows:").
- Result meanings: PASS = you saw exactly the expected result. FAIL = something was wrong (write what you did, what happened, and what you expected). Partial = part of it worked (say which part). Not tested = you could not do it (say why). Needs the owner = only a person can judge it and the owner was not available.
- Steps tagged "Mac only" or "Windows only": do them only on that system. On the other system set Not tested and write "other system".
- Steps tagged "ask the owner to listen" or "ask the owner to watch" depend on hearing, or on smooth movement and sync that screenshots cannot show. Do the actions and check everything you can see. Then ask the owner in the chat, for example: "Please play the preview from 0:05 and tell me whether the voice matches the lips." Write the owner's answer in the note starting with "Owner:", and set PASS or FAIL from it. If the owner is not available, set Needs the owner.
- On a Mac use Cmd where a step says Ctrl/Cmd, and Option where it says Alt.
- If a drag does not work for you, try twice. Then use the menu bar or panel buttons if the step offers them; otherwise set Needs the owner and write that you could not perform the drag (it may still work for a human).
- To type Hebrew or Russian text, copy it from this page and paste it with Ctrl/Cmd+V.
- Never delete, move or rename the owner's files. Save every export into a new folder named clipforge-test-output next to the test videos, with the file name the step gives (for example r4-full.mp4).
- If the app closes by itself or freezes, write down exactly what you were doing, fill in the Crash box, reopen it and continue.
- Do not guess. Only mark PASS for what you actually saw, or for what the owner told you they heard or saw.
- This page keeps your answers in this browser as you go. When finished, fill in the Summary box (most important problems first), then click "Download filled checklist" and give the downloaded file to the owner."""

# ---------------------------------------------------------------- round 4, phone (1.9.0)
# The Android phone, driven by an AI agent on the Windows PC through
# "Phone Link" / "Link to Windows" screen mirroring, with this page open on
# the PC. Touch wording only (tap, long-press, drag); no keyboard shortcuts
# and no menu bar. Names are the phone UI's own: the bottom tool bar and its
# sheets (lib/ui/editor/tools.dart), the track icons on the left of the
# timeline (sound_tracks_ui.dart), the Crop and Layout sheets
# (picture_tools.dart), Add music (music_actions.dart), Find file
# (clip_actions.dart, gallery_search.dart) and Export (export_dialog.dart).
STEPS_4P = [
 ("Install and first start", [
  ("p-install", "Install 1.9.0 over the version that is on the phone",
   "Do NOT uninstall the old ClipForge first. Before installing, open the old ClipForge and write down the names of the projects in the list (or \"no projects\"). Then ask the owner to download the new APK on the phone (the file ending in -android.apk) and tap it. If Android says the browser may not install unknown apps: tap Settings, switch on Allow from this source, go back, tap Install (or Update).",
   "Android offers Update (not a fresh install) and finishes without \"App not installed\". If it says \"App not installed\" or asks to uninstall first, write the exact text and stop this step as FAIL (do not uninstall without asking the owner: that deletes the projects).", ""),
  ("p-version", "The app shows the expected version",
   "Open ClipForge. Read the small grey line at the bottom of the project list. Tap the three dots (More) at the top right, tap About ClipForge, then Copy version info. Type or paste the version line into \"Version shown in the app\" at the top of this page (if copy and paste between phone and PC does not work, type the line you see).",
   "Both show version 1.9.0 and the same build as named at the top of this page. No red warning appears under the version box.", ""),
  ("p-keeps", "The update kept the projects",
   "Compare the project list with the names you wrote down before installing. Open the newest of the old projects, play 5 seconds, go back to the project list (the back arrow at the top left).",
   "Every project from before the update is still listed, opens without an error and plays. No clip says Missing. (If there were no projects before, set Not tested.)", ""),
  ("p-tour", "The tour",
   "On the project list tap ? (Help) at the top and start the tour (on a first start a dialog \"Would you like a quick tour?\" offers Show me around / Not now: choose Show me around). Go through it with Next to the end.",
   "Each step highlights a real button on the phone screen and its text fits on the screen (nothing cut off, Next / Back / Skip tour reachable). At the end it asks whether to keep or delete the sample project: choose delete.", ""),
 ]),
 ("Adding media, and the \"File not found\" fix", [
  ("p-new", "New project from the gallery",
   "Tap New project. The phone's own picker opens: choose camera video A (a talking video) and photo D from the gallery and confirm. When the editor opens, tap the + next to the Play button, tap Videos or photos and add video B.",
   "The editor opens with A and D on the timeline, each with clip pictures, and B is added after them (after the selected clip or the clip at the playhead). The top shows Saved (or Saving… briefly). A short wait with a progress message while files are copied is fine.", ""),
  ("p-reopen", "Close and reopen: the files are still there",
   "Go back to the project list. Close ClipForge completely: open the phone's recent-apps view and swipe ClipForge away. Open ClipForge again and open the project.",
   "All three clips are there with their pictures and play. No clip is red or says Missing, and no \"File not found\" message appears. (This was the main bug of earlier builds: ClipForge now keeps its own copy of every file.)", ""),
  ("p-reboot", "Still there after other apps and a wait",
   "Go back to the project list. Open the phone's Gallery app, look at two photos, open the Camera app and close it again. Wait one minute. Return to ClipForge and open the project again.",
   "The clips are still there and play. No Missing clip.", ""),
  ("p-find", "Find file… > Search the gallery",
   "Only if any project on the phone shows a clip marked Missing (look through the older projects; otherwise set Not tested and write \"no missing clip\"). Tap the missing clip, tap Find file in the bar at the bottom. A dialog asks \"Where is <name> now?\": tap Search the gallery. If Android asks whether ClipForge may see photos and videos, allow it.",
   "It shows \"Searching the gallery for <name>…\", then offers the matching file(s). After choosing one the clip is no longer Missing and plays. If nothing is found it says so and offers to choose the file yourself. Write down exactly what it said.", ""),
 ]),
 ("Cutting", [
  ("p-select", "Select a clip, play, scrub",
   "Tap clip A on the timeline. Tap Done in the bar at the bottom. Tap Play, let it run 5 seconds, tap Pause. Drag the timeline left and right with one finger.",
   "Tapping a clip selects it (the bar at the bottom changes to Done, Split, Speed, Look, Sound, More, Delete) and the preview jumps to it. Done clears the selection (the bar shows Add media, Music, Overlay, Title, Captions, Split, More). Dragging the timeline moves the playhead and the picture follows.", ""),
  ("p-split", "Split, delete, undo, redo",
   "Move the playhead to the middle of clip A and tap Split. Tap the second piece, tap Delete. Tap the Undo arrow at the top once, then the Redo arrow, then Undo again.",
   "Split cuts A into two pieces. Delete removes the selected piece. Undo brings it back, Redo removes it again, the second Undo brings it back: A ends in two pieces.", ""),
  ("p-trim", "Trim by dragging the end of a clip",
   "Tap the first piece of A. Drag its right edge about 2 seconds to the left. Then long-press clip B and drag it in front of the photo. (Through screen mirroring a drag or long-press may fail: try twice, then use More > Move earlier for the reorder, and set Needs the owner for the trim.)",
   "The clip gets shorter and the following clips close the gap. B moves to its new place. The total length at the top changes accordingly.", ""),
  ("p-history", "History",
   "Tap Done so nothing is selected. Tap More in the bar at the bottom, then History. Tap the oldest step in the list, then the newest.",
   "A sheet lists your changes by name, newest first (for example \"Split clip 1\", \"Deleted clip 2\"). Tapping an old step puts the project back to that point (later steps look grey); tapping the newest restores everything.", ""),
 ]),
 ("Shape, size, crop and position", [
  ("p-shape", "Shape and Video size",
   "Tap the Shape button at the top (next to Export). Tap 9:16 upright. Open it again and look at the Video size choices (As first clip, 720p, 1080p, 4K); tap 1080p. Open it once more and tap \"Which shape should I use?\", then close Help.",
   "The preview becomes upright; wide clips sit in it with bars (or blurred / filled if set). The menu shows a tick on the current shape and size. The help article about shapes opens and closes.", ""),
  ("p-crop", "Crop and position sheet",
   "Tap the first piece of A, tap More, tap Crop and position. On the preview drag a corner of the frame inwards, then drag inside the frame. Tap 1:1, then 9:16, then Free, then Original. Tap the rotate and flip buttons once each, then Reset crop and position. Tap Done.",
   "The sheet shows the whole picture with a frame and grips and the outside dimmed; the sheet does not cover the frame. Corner drags resize, a drag inside moves; 1:1 and 9:16 keep their shape. Rotate turns the picture a quarter turn, flip mirrors it, Reset puts everything back. (If the drags fail through mirroring, try twice, test the shape buttons, and set Needs the owner for the drags.)", ""),
  ("p-position", "Keep the person in shot",
   "With the shape still 9:16 upright, tap the first piece of A, tap Look and choose Fill under Fit to frame. Close the sheet. Tap More > Crop and position and move Left – right to one end, the other end, then so that the person is in the middle. Tap Done.",
   "With Fill the wide picture fills the upright frame, and Left – right changes which part is seen. Ask the owner to look at the phone: the person can be put in the middle.", "watch"),
 ]),
 ("Overlay and titles", [
  ("p-overlay", "Overlay (picture-in-picture)",
   "Tap Done. Move the playhead to about 0:03. Tap Overlay in the bar at the bottom (or + next to Play > Overlay (picture-in-picture)) and pick video B from the gallery. Tap the overlay on its row, tap Layout: set a different corner, move Size to about 50%, switch on White frame. Then try Side by side and Full screen, and go back to Picture-in-picture. Play across the overlay.",
   "B appears small in a corner of the preview from 0:03, on an Overlay row above the main clips. Corner, Size and White frame change it at once; Side by side and Full screen change the layout. Ask the owner to watch the phone while it plays: both videos move (the preview may stutter a little with an overlay; write down how much).", "watch"),
  ("p-title", "Title, fonts and styles",
   "Tap Done. Move the playhead to 0:01 and tap Title. The Edit title sheet opens: type Round 4 phone. Tap each Font (Classic, Modern, Elegant, Handwritten), two Styles, switch on Outline, tap Position Top and then Lower third. Set Appear to Pop. Close the sheet and play from 0:00.",
   "The text shows in the preview while typing; fonts and styles change it visibly; Outline draws a line around the letters; Top / Lower third move it. The sheet scrolls so that every setting is reachable and the keyboard does not hide the text box. On play the title pops in.", ""),
  ("p-hebrew", "Hebrew and Russian text",
   "Add another title at 0:05. Copy this text from this page and paste it into the title's text box on the phone (if pasting from the PC does not reach the phone, ask the owner to type or paste it on the phone): שלום עולם / Привет, мир . Tap each of the four fonts.",
   "In every font the Hebrew and Russian letters show properly (no empty boxes, no question marks). The Hebrew words keep their order: read right to left, שלום comes before עולם.", ""),
  ("p-caption", "A caption, duplicate and delete",
   "Tap Done. Tap Captions and add the caption: Test caption. Select it on the timeline, tap Duplicate, then delete the copy with Delete.",
   "The caption shows at the bottom of the picture in a dark box. Duplicate puts a copy right after it; Delete removes the copy.", ""),
 ]),
 ("Look and fades", [
  ("p-filter", "Filters",
   "Tap the first piece of A, tap Look. Tap Warm, Cool, Black & white, Vintage, Vivid, None in turn, then choose Vintage. Close the sheet. Tap More > Copy settings. Tap clip B, tap More > Paste settings.",
   "Each filter changes the preview at once. After pasting, B has the Vintage look too and keeps its own length.", ""),
  ("p-fades", "Fade in and out",
   "Tap Done. Tap More in the bar at the bottom, then Fade in and out. Set Fade in from black and Fade out to black to about 2 s each. Close the sheet, play the first 3 seconds and the last 3 seconds. Then tap clip B, More > Transition and fades, and pick Crossfade.",
   "The video comes up from black at the start and goes to black at the end. B now fades in from the clip before it. Ask the owner to watch the phone.", "watch"),
 ]),
 ("Sound", [
  ("p-tracks", "Sound tracks",
   "On the left edge of the timeline tap the small add-track icon at the top (its description is \"Add sound track\"). Then tap the icon of the new track on the left: a sheet opens. Change Volume, switch Mute on and off, look for Solo, Lower this track under speech, This track is speech, Move up, Move down and Delete track. Tap Delete track. Then tap the film icon (the first one on the left: Video sound) and switch Mute on and off.",
   "A new sound row appears with an icon on the left, and a short message names it. The sheet has all the listed settings and they stay as set. Delete track removes the empty track. The film icon opens the settings of the video's own sound.", ""),
  ("p-separate", "Separate sound to track",
   "Tap the first piece of A, tap Sound, tap Separate sound to track… and confirm with Separate (leave \"Also the other clips\" off). Close the sheet and play that piece. Then tap the same clip, Sound, Put it back on the clip.",
   "The clip's sound appears as its own piece on a Voice row under the clips and the clip shows as muted. Ask the owner to listen on the phone: the voice is heard once (no echo) and matches the lips. Put it back removes the Voice piece again.", "listen"),
  ("p-silences", "Remove silences",
   "Tap the first piece of A (the talking video), tap Sound, tap Remove silences. Wait for the result. Tap Fewer cuts, Automatic, More cuts under Sensitivity and write down the gap count for each. Choose Automatic and tap the Remove … gaps button. Play across two cuts. Tap Undo once.",
   "A progress bar with Cancel, then a line like \"Background noise about -45 dB; quieter than -34 dB counts as silence\" and a button like \"Remove 5 gaps\". After applying, the clip is several pieces and the phone does not freeze for long. Ask the owner to listen: words are not chopped. One Undo brings the single clip back.", "listen"),
  ("p-clean", "Clean up sound and Voice focus",
   "Tap the first piece of A, tap Sound, switch on Clean up sound and wait until it finishes; then set Voice focus to about 50% and wait again. Play the clip.",
   "The clip shows Sound xx% while it works and then finishes (on a phone this can take a while: write down roughly how long for how long a clip). Ask the owner to listen on the phone: less background noise, voice still in sync.", "listen"),
 ]),
 ("Music", [
  ("p-music-find", "Find free music: search and preview",
   "Tap Done. Move the playhead to 0:00 and tap Music. The Add music window opens with the tabs My files and Find free music. On Find free music type piano and tap Search. Tap the play button of one result, let it play a few seconds, stop it.",
   "Results show title, artist, length and licence (CC0, Public domain, CC BY or CC BY-SA). Ask the owner whether the preview is heard on the phone. If it says it is offline, \"Nothing found\" or shows an error, write the exact text. (Needs internet on the phone.)", "listen"),
  ("p-music-use", "Use a track, credits",
   "Tap Use on one result. When it is on the timeline, tap the music piece, tap Edit. Tap Copy credits (paste into the note if you can, otherwise write what the Credits line shows). Tap Add credits at the end.",
   "The music downloads and lands on a sound row from 0:00. Edit music shows Volume, Fade in, Fade out, Fit music to video, Track and Credits with the track's title, artist and licence. Add credits at the end puts a small caption with the credits over the last 4 seconds.", ""),
  ("p-music-file", "Music from the phone's files",
   "Tap Done, move the playhead to the middle of the video, tap Music > My files > Choose a music file… and pick music file C from the phone (if there is none, set Not tested).",
   "The phone's file picker opens; the chosen music lands at the playhead. Because the first music already plays there, it goes onto another sound row.", ""),
  ("p-fit", "Fit music to video, and loop",
   "Tap the first (downloaded) music piece, tap Edit, tap Fit music to video. If it says \"The music is shorter than the video\", tap Loop. Close the sheet and look at the end of the timeline. Then delete the second music piece (the one from My files).",
   "The music now ends exactly where the video ends, with a fade-out. Longer music is simply cut; shorter music asks to Loop and then shows a repeat sign and thin marks where it starts again. Ask the owner to listen to the last 5 seconds (and one repeat point if it loops): no click, no gap.", "listen"),
 ]),
 ("Playback speed of the phone", [
  ("p-smooth", "Smooth preview switch",
   "Tap Done, tap More in the bar at the bottom. Smooth preview should be ON. Close the sheet and play the whole project once from 0:00. Then More > switch Smooth preview OFF, go back to the project list, open the project again and play it once more. Switch it back ON afterwards.",
   "Ask the owner to watch the phone itself (mirroring adds its own stutter, so do not judge from the PC): with Smooth preview on, playback is fluent, perhaps a little softer; write down where it stutters or freezes (at cuts, during the overlay, during titles) in each mode. The switch keeps its setting.", "watch"),
  ("p-sync", "Sound and picture stay together",
   "Play 20 seconds of the talking clip from its start, then tap in the middle of it and play again.",
   "Ask the owner to watch and listen on the phone: lips and voice match, also after jumping; the music does not restart or double.", "listen"),
 ]),
 ("Export", [
  ("p-export-full", "Export full quality",
   "Tap Export at the top right. Make: Video, Full quality, Video size 1080p. Write down the \"File size: about …\" line and what it says about where the video goes. Tap Export and wait. Write down how long it took and the \"Saved to …\" line.",
   "The window says the finished video goes to your gallery. Progress runs to 100%, then \"Adding it to your gallery…\" and \"Video saved\" with \"Saved to …\" (the Movies folder of the gallery) and a Send to another app button. \"Keep ClipForge open while it exports\" is shown during the export.", ""),
  ("p-export-gallery", "The exported video is in the gallery and looks right",
   "Open the phone's Gallery app and find the new video (album Movies or ClipForge, newest first). Play it from start to end.",
   "The video is there and plays. Ask the owner to watch and listen on the phone: upright 9:16, fade from black, titles incl. Hebrew / Russian letters, the overlay in its corner, Vintage look, music ending with the video, fade to black; voice in sync.", "watch,listen"),
  ("p-export-small", "Export a small file",
   "Back in ClipForge tap Export, choose Small file, export. Compare the two files' sizes in the Gallery (details / info of each video).",
   "It finishes and is saved to the gallery like the first. The small file is clearly smaller (write down both sizes).", ""),
  ("p-export-sound", "Export the sound only",
   "Tap Export, set Make to Sound M4A, export. When it is done tap Send to another app and look at the share sheet (then cancel it without sending). Repeat with Sound MP3.",
   "Video size and Frames per second are hidden for sound. It ends with \"Sound saved\" and Send to another app opens Android's share sheet with the file. MP3 works too, or says to export as M4A instead: write down exactly what it says.", ""),
  ("p-export-bg", "Leave the app during an export",
   "Start a Full quality export again. At about 20%, press the phone's Home button, wait 30 seconds (open another app meanwhile), then return to ClipForge.",
   "Write down exactly what happened: the export kept running and finished / it paused and continued / it stopped with a message (\"The export stopped unexpectedly.\" with Try again) / the app restarted. If it stopped, Try again must work when the app stays open. No half-finished video appears in the gallery.", ""),
  ("p-export-lock", "Screen off during an export",
   "Start one more export and leave the phone alone without touching it until it is finished (the screen should stay on by itself).",
   "The screen stays on while exporting and the export finishes. If the screen went dark or locked, write down whether the export still finished.", ""),
 ]),
 ("Rotate, share, finish", [
  ("p-rotate", "Rotate the phone",
   "Ask the owner to make sure auto-rotate is on and to turn the phone on its side while the project is open, then back upright. Do this once while paused and once while playing.",
   "Write down what happens: either the editor rearranges itself for the wide screen, or it stays upright. In both cases nothing is lost: the project, the selection and the playhead are still there, playback continues or pauses cleanly, and the app does not close.", ""),
  ("p-share", "Share project file",
   "Go back to the project list. Tap the three dots on the project's card, tap Share project file. When Android's share sheet opens, look at the file name and cancel (do not send it anywhere unless the owner says where).",
   "It shows \"Packing …\" and then Android's share sheet with one file ending in .clipforge.zip. Cancelling says the project file was not sent anywhere; nothing else changes. The card menu also has Rename, Duplicate and Delete.", ""),
  ("p-duplicate", "Duplicate and rename a project",
   "On the same card menu tap Duplicate. On the copy tap Rename and call it Round 4 phone copy. Open the copy, delete one clip, go back, open the original.",
   "The copy appears in the list with the new name. Changing the copy does not change the original (it still has all its clips).", ""),
  ("p-help", "Help on the phone",
   "On the project list tap ? (Help). Search for: stutter. Open the article it finds. Search for: gallery.",
   "\"stutter\" finds \"Smooth preview on phones\"; \"gallery\" finds articles about where exported videos go and about missing files. The article text fits the phone screen and scrolls.", ""),
  ("p-final", "Everything was saved",
   "Close ClipForge from the recent-apps view (swipe it away). Open it again, open the test project and play it once.",
   "Everything is still there: cuts, 9:16 shape, Fill and position, overlay, titles with Hebrew / Russian text, filter, fades, music fitted to the video, credits caption. No clip is Missing.", ""),
 ]),
]

INSTR_4P = """You are testing ClipForge 1.9.0, a video editor, on the owner's Samsung Android phone. You work on the owner's Windows PC and see and touch the phone through "Phone Link" (the phone side is called "Link to Windows"): the phone's screen is shown in a window on the PC. This checklist page is open in a browser on the PC. Problems are expected; your job is to find them and write them down precisely.

HOW TO DRIVE THE PHONE
- In the Phone Link window a mouse click is a tap, holding the mouse button down for a second is a long-press, and click-and-drag is a drag. There are no keyboard shortcuts and no menu bar on the phone: use only what is on the phone's screen.
- If the phone screen is not shown, ask the owner to open Phone Link on the PC and choose the phone's screen (Apps > Open phone screen), and to unlock the phone. If the mirrored screen goes black or locks, ask the owner to unlock it.
- Drags and long-presses often fail through mirroring. Try twice. If it still fails, use the button the step offers instead (for example More > Move earlier); otherwise set "Needs the owner" and write that the drag could not be performed through mirroring (it may work fine with a finger). Ask the owner to try it with a finger if they are there.
- Typing: click into the text box on the phone and type on the PC keyboard. For Hebrew and Russian text copy it from this page and paste it (Ctrl+V) into the phone window; if that does not arrive, ask the owner to type it on the phone.
- SOUND: the phone's sound may not reach you through mirroring. Never judge sound yourself. For every step tagged "ask the owner to listen", do the actions, then ask the owner in the chat, for example: "Please listen on the phone: does the voice match the lips?" The same goes for smoothness: mirroring stutters by itself, so for steps tagged "ask the owner to watch" ask the owner to look at the phone itself. Write the answer in the note starting with "Owner:" and set PASS or FAIL from it. If the owner is not available, set "Needs the owner".

HOW THE PHONE APP IS LAID OUT (names as on the screen)
- Project list: New project and Open project file; ? (Help) and three dots (More > About ClipForge) at the top; each project card has three dots: Rename, Duplicate, Share project file, Delete.
- Editor, top: back arrow (Back to projects), Undo and Redo arrows, the Shape button, Export, ? (Help).
- Editor, middle: the preview; under it Play / Pause, a + button ("Add videos, photos, music or text": Videos or photos, Music, Overlay (picture-in-picture), Title, Caption) and timeline zoom buttons.
- Timeline: rows from top to bottom: Overlay (when there is one), the video clips, the sound tracks, titles. On the left edge are small icons: an add-track icon at the top (Add sound track), a film icon (the video's own sound) and one icon per sound track; tapping one opens its settings.
- Bottom tool bar with nothing selected: Add media, Music, Overlay, Title, Captions, Split, More. More holds: Fade in and out, History, Smooth preview.
- Bottom tool bar with a video clip selected: Done, Split, Speed, Look, Sound, More, Delete (and Find file when the file is missing). More holds: Crop and position, Transition and fades, Freeze frame, Duplicate, Copy settings, Paste settings, Move earlier, Move later.
- With music selected: Done, Edit, Delete. With a title or caption selected: Done, Edit, Duplicate, Delete. With an overlay selected: Done, Layout, Crop, Sound, Delete.
- Settings open as a sheet from the bottom; swipe it down or tap outside it to close it.

BEFORE YOU START
- Fill in "Device" (for example "Samsung Galaxy S23, Android 15, via Phone Link") and "Tester".
- Fill in "Version shown in the app": project list > three dots > About ClipForge > Copy version info, then type or paste the line. If it does not match the build named at the top of this page (a red warning appears), tell the owner and say so in the Summary.
- Test files on the phone (ask the owner which ones to use; do not download files from the internet except through the app's own Find free music):
  A. a talking video filmed with the phone's camera, 1-3 minutes, with some pauses, filmed wide (landscape) if possible;
  B. a second short camera video, 10-30 seconds;
  C. optional: a music file on the phone (MP3 or M4A);
  D. a photo from the gallery.
- Do the steps in order: later steps build on the project made in "New project from the gallery".

RULES
- Each step has "Do" (exact actions) and "Expected" (what should happen). Do the actions exactly, then compare with Expected.
- For each step choose a Result and write a Note. Result meanings: PASS = you saw exactly the expected result (or the owner confirmed it). FAIL = something was wrong (write what you did, what happened, and what you expected). Partial = part of it worked (say which part). Not tested = you could not do it (say why). Needs the owner = only a person can judge or perform it and the owner was not available.
- NEVER delete, move or rename the owner's photos, videos or music, in ClipForge's pickers, in the Gallery or in any other app. Do not uninstall ClipForge (that deletes the projects). Inside ClipForge only delete things this test made. Do not send or share anything to other people or apps: cancel every share sheet.
- Exported videos go to the phone's gallery (the Movies folder; the result says "Saved to ..."). Exported sound files stay in the app and are offered with "Send to another app". Leave the exported files in the gallery for the owner.
- If an Android permission dialog appears (photos and videos, music, notifications), allow it and write down that it appeared.
- If the app closes by itself or freezes, write down exactly what you were doing, fill in the Crash box, reopen it and continue.
- Do not guess. Only mark PASS for what you actually saw, or for what the owner told you they heard or saw.
- This page keeps your answers in this browser as you go. When finished, fill in the Summary box (most important problems first; also what was hard to do through mirroring), then click "Download filled checklist" and give the downloaded file to the owner."""

# Per round: steps, instructions, the result choices (first = empty), the
# ---------------------------------------------------------------- round 5 (1.11.0)
# The Windows computer round for 1.11.0: only what is new in 1.10 (a voice
# recorded separately) and 1.11 (speech to text, captions from speech, the
# transcript, Remove filler words, Automatic cuts, project names), plus a
# 5-step regression core. Labels are the app's own (lib/ui/editor/
# voice_actions.dart, speech_actions.dart, transcript_panel.dart,
# lib/ui/app_menu.dart, assets/help/help_en.md).
# Steps: (id, title, do, expected, tag) as in round 4.
STEPS_5 = [
 ("Start", [
  ("start-open", "Install 1.11.0 and open ClipForge",
   "Unzip the new download into a new folder and run clipforge.exe.",
   "The project list opens. Projects from earlier rounds are still listed and one of them opens without an error.", ""),
  ("start-version", "The app shows the expected version",
   "Read the small grey line at the bottom of the project list. Open Help > About ClipForge, click Copy version info and paste it into \"Version shown in the app\" at the top of this page.",
   "Both show version 1.11.0 and build 106, the same as named at the top of this page. No red warning appears under the version box.", ""),
  ("help-new", "Help finds the new topics",
   "Open Help (the ? button at the top, or F1). Search for each of: zoom, transcribe, captions from speech, filler, transcript. Then open What's new in Help.",
   "The searches find \"Voice recorded separately (microphone, Zoom)\", \"Transcribe speech (computer only)\", \"Captions from speech (computer only)\", \"Remove filler words (computer only)\" and \"The transcript (computer only)\". What's new starts with 1.11.0 (18 November 2026) and below it 1.10.0.", ""),
 ]),
 ("Basics still work (5-step regression)", [
  ("reg-project", "Make the test project",
   "On the project list click New project. Add files A and E (see the instructions): drag them from Explorer onto the window, or use Add media. Rename the project to \"Round 5 test\" (File > Rename project…).",
   "The editor shows two clips on the main track in the order A, E, each with clip pictures. The top bar shows Saved (or Saving... briefly).", ""),
  ("reg-split", "Split, delete, undo",
   "Click clip E, put the playhead in its middle and press S. Click the second piece and press Delete. Press Ctrl+Z once.",
   "S cuts E into two pieces. Delete removes the selected piece. One undo brings it back, so E is in two pieces again. Clicking a clip moves the preview to it.", ""),
  ("reg-clean", "Clean up sound still works",
   "Select clip A, open Sound and switch on Clean up sound. Wait until it finishes. Play it and switch Hear original on and off while it plays.",
   "The clip shows Sound xx% and then finishes. Ask the owner to listen: background hiss or rumble is lower with Hear original off, and the voice stays in sync with the lips.", "listen"),
  ("reg-music", "Music and Lower music under speech",
   "Put the playhead at 0:00, click Music, choose My files and pick file C. When ClipForge asks what the sound is, choose Music and click Add (the question itself is checked in the next group). Then choose Edit > Sound > Lower music under speech.",
   "The music starts at 0:00 on the Music track. The menu item shows as switched on. Ask the owner to listen to the first 20 seconds of the preview: voice and music are both heard.", "listen"),
  ("reg-quit", "Quit while editing: everything is saved",
   "With the project open and nothing exporting, press Alt+F4. Start ClipForge again and open \"Round 5 test\".",
   "It closes without asking. After reopening, the two pieces of E, Clean up sound on A and the music are all there.", ""),
 ]),
 ("Project names", [
  ("name-new", "Two new projects never get the same name",
   "Go back to the project list. Click New project, go back to the list, and click New project again. Go back to the list and read the names of the two new projects.",
   "A new project is named \"Video\" plus today's date. The second one made on the same day has the same name with \"(2)\" at the end. No two projects in the list have exactly the same name.", ""),
  ("name-dup", "Duplicating twice gives \"(2)\"",
   "On the card of \"Round 5 test\" open Project options (the three dots) and choose Duplicate. Do the same once more on \"Round 5 test\".",
   "The first copy is called \"Round 5 test copy\", the second \"Round 5 test copy (2)\". Write down the exact names. (Leave the copies; do not delete anything.)", ""),
 ]),
 ("Voice recorded separately (new in 1.10)", [
  ("v-ask", "\"What is this sound?\" when adding a sound file",
   "Open \"Round 5 test\". Drag music file C from Explorer onto the ClipForge window. Read the window that opens, then click Cancel. Then click Music > My files, pick C again and read the window again; click Cancel.",
   "Both times a window asks \"What is this sound?\" and names the file. It offers exactly three choices: Voice for the video, Music, Sound effect, each with one line of explanation, and the buttons Cancel and Add. For a music file, Music is the choice already selected. Cancel adds nothing.", ""),
  ("v-roles", "Music and Sound effect go to their tracks",
   "Put the playhead at 0:30. Add file C once more (Music > My files), choose Sound effect and click Add. Look at the names on the left of the timeline. Press Ctrl+Z.",
   "The sound lands at the playhead on a track called Effects (it is made when there is room; if there is no room a message says the sound is with the music). History shows \"Added sound effect\". One undo removes it.", ""),
  ("v-nomatch", "A voice that cannot be lined up says so",
   "Add file C once more, but this time choose Voice for the video, leave the name as it is and click Add and line up.",
   "With Voice chosen, a field \"Who speaks (name of its track)\" and a switch \"Mute the camera's own sound\" (on) appear, and the button reads Add and line up. It works for a moment (\"Lining up the voice with the video…\") and then says it could not line it up automatically and to nudge it by hand; the voice starts where clip 1 starts and the camera's own sound is still on. Write down the exact message. Then press Ctrl+Z so the music is gone again.", ""),
  ("v-add", "Add the real voice: lined up, linked, camera muted",
   "Needs files V and W (a video and the voice recorded separately for it; otherwise set Not tested for this and the next three steps). Make a new project, add V, rename it \"Round 5 voice\". Drag W onto the window (with several speakers: all voice files together). Check what is preselected, the name field(s), then click Add and line up. Play 20 seconds from three places.",
   "Voice for the video is preselected (the file name or its length tells ClipForge), with one name field per file, filled in from the file name when it names the speaker. After Add and line up a message says \"Lined up with clip 1 (...)\" with a time, that it follows the picture when you cut, and that the camera's own sound is muted (with several files: \"... voices lined up with the video, each on its own track\"). Each voice is on its own track named after the speaker. Write down the message. Ask the owner to watch and listen: lips match the voice in all three places, and no second, echoing voice is heard.", "watch,listen"),
  ("v-nudge", "Nudge buttons and \"Line up with the video again\"",
   "Click the voice on its track. Read the panel. Under Nudge the voice click Later > 100 ms three times and play; then Earlier > 100 ms three times and play. Try 10 ms and 1 frame once each way. Then click Later > 100 ms twice and click Line up with the video again. Open History.",
   "The panel says \"Voice for clip 1, lined up at ...\" and that it follows the clip when you cut. Under Nudge the voice there are two rows, Earlier (100 ms, 10 ms, 1 frame) and Later (1 frame, 10 ms, 100 ms), plus Line up with the video again, Unlink and the switch Mute the camera's own sound. After 300 ms later the voice is clearly behind the lips; after nudging back it fits again (ask the owner). Line up with the video again brings back the same time as in the previous step. History has steps like \"Nudged voice 100 ms later\" and \"Lined up voice with clip 1 (...)\".", "watch,listen"),
  ("v-cuts", "Cuts keep the voice in sync",
   "Select the video clip, put the playhead at about one third and press S. Drag the end of the first piece a little shorter. Then select the second piece, open Sound and run Remove silences and apply it. Play across three cuts. Then press Ctrl+Z once.",
   "Every cut of the picture cuts the voice (all voices) at the same place: the voice track shows one piece under each video piece. The Sound panel of a video piece says \"Voice from a separate recording (...)\" and that the camera's own sound is muted. Ask the owner to watch and listen at three cuts: lips still match the voice, no words chopped. One Ctrl+Z takes back Remove silences for picture and voice together.", "watch,listen"),
  ("v-unlink", "Unlink, and line up again",
   "Click a voice piece and click Unlink. Read the question, leave its switch as it is and click Unlink. Read the panel. Drag the end of the video clip above it a little shorter and look at the voice. Press Ctrl+Z. Click the voice again and click Line up with the video.",
   "The question is \"Unlink the voice from the video?\"; it explains that the voice stays where it is but no longer follows the picture, and offers \"Switch the camera's own sound back on\", Cancel and Unlink. Afterwards the panel says the voice is recorded separately and not linked to the video, and the button reads Line up with the video (without \"again\"). Trimming the clip now leaves the voice as it was. Line up with the video links it again with the same time as before. History shows \"Unlinked voice from clip ...\".", ""),
 ]),
 ("Transcribe speech (new in 1.11)", [
  ("t-open", "Transcribe speech…: the speech program, or a plain explanation",
   "Open \"Round 5 test\", select clip A, open Sound and click Transcribe speech…. Wait until \"Looking at what this computer has…\" is gone. Open the Language list. Do not click Download or Transcribe yet.",
   "A window \"Transcribe speech\" opens. It names the sound it will use, and Language offers Automatic, English, Russian, Hebrew and Other…. Then EITHER a line \"Uses: ...\" names the speech program found on this computer (write it down exactly), OR a box explains in plain words that turning speech into text needs a speech program, that none was found, which ones ClipForge can use and what to install on Windows (winget install ffmpeg). In the second case copy the text into the note, tell the owner, and set the remaining speech steps to Not tested unless the owner installs one and restarts ClipForge.", ""),
  ("t-packs", "Language packs: sizes shown, nothing downloads by itself",
   "In the same window read the part \"Language pack\". Change Language between English and Russian and read the rows again. Wait one minute without clicking anything.",
   "It says nothing is downloaded until you press Download. Three rows: Small, Medium and Large, each with its size (about 140 MB, 470 MB, 1.6 GB) and a note (quick, more mistakes / good / best, large download), and whether it is English only or for all languages, shared. Each row not on the computer has a Download button; one that is has Remove. Below: \"No packs on this computer yet.\" or \"Packs use ... on this computer.\", and Use a model file I have…. With no pack, Transcribe cannot be clicked. After a minute nothing has started downloading. (If instead it says the program uses its own model, write that text down; there are then no rows.)", ""),
  ("t-download", "Download a pack, stop it, continue",
   "Ask the owner which pack to download for the language of file A (suggest Small; NEVER click Download on Large without the owner saying so). Click Download on that row. After a few seconds click Stop. Then click Download again and let it finish.",
   "While downloading, the row shows how much of the size has arrived and a Stop button. Stop ends it within a few seconds. Download again continues and finishes; the row then shows Remove, it can be selected, the line below says how much space the packs use, and Transcribe can be clicked. If a download fails, copy the exact message.", ""),
  ("t-ownfile", "Use a model file that is already on the computer",
   "Click Use a model file I have…. If the owner has a whisper model file (a .bin file, for example ggml-base.en.bin), choose it; otherwise close the file chooser with Cancel and set Partial with \"no file\".",
   "A file chooser opens. After choosing a file the window shows \"Your own file: <name>\" with a Forget it button, and Transcribe can be clicked without any download. Click Forget it afterwards if the owner wants to use the downloaded pack.", ""),
  ("t-cancel", "Progress and Stop",
   "Choose the language of file A and click Transcribe. When the progress bar has moved a little, click Stop. Then look at the Sound panel of clip A.",
   "A progress bar and a line of text appear, with the note that a long recording takes a while and that you can stop at any time. The left button reads Stop while it runs. Stop ends it within a few seconds, the window closes and the app stays usable. The Sound panel still says \"Turns what is said into text, for captions and more.\" (no transcript was made).", ""),
  ("t-run", "Transcribe to the end",
   "Click Transcribe speech… again, choose the language and click Transcribe. Note the clock time at the start and at the end. Leave the computer alone while it runs.",
   "The progress moves to the end and a message says \"Speech transcribed: ... words. See it under Transcript.\" Write down the number of words, the length of clip A and how long it took. The Sound panel now says \"Transcribed. Use it for captions or to remove filler words.\" and shows Captions from speech… and Remove filler words…. Opening Transcribe speech… again shows \"already transcribed\" and the button Transcribe again.", ""),
  ("t-voices", "Separate voices are transcribed per speaker",
   "Only if \"Round 5 voice\" was made (otherwise Not tested). Open it, select the video clip, Sound > Transcribe speech… and click Transcribe. Then click the Transcript button at the top.",
   "The window says it will use the recordings, one per speaker, with the speakers' names (not the muted camera sound). While running it shows \"Recording 1 of ...\". In the Transcript column each phrase has its speaker's name above it, and the names are those of the voice tracks.", ""),
 ]),
 ("Captions from speech", [
  ("c-add", "Captions from speech…",
   "In \"Round 5 test\" select clip A, Sound > Captions from speech…. Read the window, switch Lines between 1 and 2, move the Longest line slider, then set 2 lines and 37 letters and click Add captions. Then press Ctrl+Z, and add them again the same way. Open Captions from speech… a third time, read it and click Cancel.",
   "The window \"Captions from speech\" says \"This adds ... captions, in the look your captions have\", shows the first three as a preview, and the count changes with Lines and Longest line (32 to 42 letters). Add captions puts them on the timeline and says \"Added ... captions from the speech. Undo takes them away.\" One Ctrl+Z removes all of them. The third time the window offers \"Replace the ... captions that are already there\". Write down the caption count.", ""),
  ("c-watch", "The captions fit what is said",
   "Play the first two minutes of \"Round 5 test\" in the preview.",
   "Ask the owner to watch and listen: each caption appears when its words are spoken, has one or two lines that fit inside the picture, stays long enough to read, and two captions never show at once. \"Um\" and \"uh\" are not written. Wrong words (names, numbers) are normal: write down two examples, but do not count them as FAIL.", "watch,listen"),
  ("c-foreign", "A Hebrew or Russian clip",
   "Only if the owner has file D (otherwise Not tested). Make a project \"Round 5 language\" with D. Sound > Transcribe speech…, choose Hebrew or Russian. If it needs another pack, ask the owner before clicking Download (the Small pack makes many mistakes in Hebrew). Transcribe, then Captions from speech… > Add captions. Open the Transcript. Export as r5-language.mp4.",
   "The transcript and the captions are in Hebrew or Russian letters (no question marks or empty boxes). Hebrew reads right to left in the Transcript column, in the preview and in the exported file, with the full stop or question mark at the LEFT end of the line. Ask an owner who reads the language to watch 30 seconds of the export and say whether the text is readable and on time.", "watch"),
 ]),
 ("Transcript", [
  ("tp-open", "The Transcript column",
   "In \"Round 5 test\" click the Transcript button in the top bar (or Edit > Speech > Transcript). Click three different phrases. Then split clip A somewhere and delete a piece, look at the column, and press Ctrl+Z twice.",
   "A column titled Transcript opens with what is said, phrase by phrase, each with its time. Clicking a phrase moves the playhead and the preview to that moment. After deleting a piece its phrases are gone from the column and the later times are earlier; after the undos they are back. The text cannot be edited. The button (and the menu item, which shows a tick) closes the column again.", ""),
  ("tp-search", "Search the transcript",
   "Type a word that is said several times into \"Find a word…\". Click one of the results. Clear the box and type: xyzzy.",
   "The column shows only the phrases with that word and a line \"Said in ... places\". Clicking one jumps there, and the word is heard when you play (ask the owner). For xyzzy it says that this is not said in this video.", "listen"),
 ]),
 ("Remove filler words", [
  ("f-open", "The review list",
   "Select clip A, Sound > Remove filler words… (or Edit > Speech). Wait until \"Checking the picture around each cut…\" is gone. Read the window. Click the play button of two rows. If it says no filler words were found, type a short word that is said often (for example: so) into \"Also look for\" so that rows appear, and say so in the note.",
   "A window \"Remove filler words\" with: Fillers of (a language list), Select with Light, Normal and Strong (Light is selected), a line that explains the selected strength, a summary line, and a list. Each row has a tick box, the time, the filler in quotes, its length, a rating of the picture across the cut (smooth, slight or jumpy) and a play button that plays that spot for about three seconds. A word that is also a real word says so and is not ticked. Copy the summary line and any note under the list into the note (for example that word times are only estimated and nothing is ticked, or that FFmpeg's speech filter leaves \"um\" out).", ""),
  ("f-strength", "Light, Normal, Strong",
   "Click Light, then Normal, then Strong. For each, copy the summary line (\"... of ... selected · saves ... · ... per minute\") and the line about fillers left in because the picture would jump, if shown. End on Light.",
   "The number selected is smallest on Light and largest on Strong (or equal when few were found); the number found stays the same. Light shows at most about 4 cuts per minute. On Light and Normal, fillers rated jumpy are not ticked and a line says how many are left in because the picture would jump there; on Strong they are ticked. Changing the strength resets ticks changed by hand.", ""),
  ("f-apply", "Remove (Light) and check the result",
   "On Light, untick one row and tick it again, then click Remove. Note the times of three removed fillers first. Play across those three places.",
   "A message says \"Removed ... filler words. Undo brings them back.\" The timeline has that many more pieces and the video is shorter by the time the summary line gave. Ask the owner to watch and listen at the three places: the \"um\" is gone, the words next to it are whole, and the picture does not jump badly (a short dissolve is fine).", "watch,listen"),
  ("f-autocuts", "Automatic cuts: Put back one, Put back all, Undo",
   "Sound > Automatic cuts… (or Edit > Speech > Automatic cuts…). Copy the summary line. Click Put back on the first row. Then click Put back all and close the window. Press Ctrl+Z once, then once more, and open Automatic cuts… again.",
   "The window \"Automatic cuts\" shows a line \"... cuts · ... removed · ... per minute\" and one row per cut: the word in quotes (or Silence), the file and time, the length, the rating, \"dissolve\" where one was added. Put back makes the row disappear, the count one lower, and that place in the video whole again. Put back all empties the list (\"Nothing was cut automatically in this project (or everything was put back).\"); the Automatic cuts… button and menu item are then greyed out or gone, which is correct. Each Ctrl+Z takes back one of these steps, so after two the cuts are back as after the first Put back.", ""),
 ]),
 ("Export", [
  ("exp-estimate", "Export: what it says before and after",
   "Open Export in \"Round 5 test\": Video, Full quality. Before clicking Export, copy the lines \"File size: about ...\" and \"Will use: ...\" (and an estimated time, if one is shown). Export as r5-full.mp4 and time it with the clock. Afterwards copy the result line and look up the real size of the file in Explorer.",
   "It finishes and says what was used (graphics card or processor) and \"Took ...\". Write down: estimated size, real size, time on the clock, time the app says, and the length of the video. The real size should be within about a third of the estimate, and the two times should agree.", ""),
  ("exp-watch", "The export matches the preview",
   "Play r5-full.mp4 in Media Player from start to end.",
   "Ask the owner to watch and listen: the captions from speech are there at the right moments, the filler cuts are where they were in the preview, music is lower under the voice, and picture and sound are in sync to the end.", "watch,listen"),
 ]),
 ("Menus", [
  ("menu-new", "The menus contain the new items",
   "With \"Round 5 test\" open and clip A selected, open Edit > Speech and Edit > Sound in the bar at the top of the window. Write down the items in order. Click Edit > Speech > Transcribe speech… and close it; click Edit > Sound > Add voice recording… and cancel.",
   "Edit > Speech has: Transcribe speech…, Captions from speech…, Remove filler words…, Transcript, Automatic cuts…. Edit > Sound has, besides the older items, Add voice recording… and Line up with the video. Transcribe speech… opens the same window as the button in Sound; Add voice recording… opens a file chooser and then the \"What is this sound?\" window.", ""),
  ("menu-grey", "Nothing about speech is greyed out or missing without a reason",
   "With a talking video in the project, look at: the Sound panel of clip A, the Transcript button in the top bar, and every item of Edit > Speech and the two voice items of Edit > Sound. Then select the music on its track and look at Edit > Sound again.",
   "Transcribe speech…, Captions from speech…, Remove filler words… and Transcript can be clicked. The only greyed items are those with a reason: Automatic cuts… while nothing is cut automatically, and Line up with the video while no sound is selected (it can be clicked once the music is selected; with the music selected the panel also offers \"This is a voice: line up with the video\"). The Sound panel always shows Transcribe speech… for a video clip with sound. Write down anything else that is greyed out or missing.", ""),
 ]),
 ("New in 1.12", [
  ("u-menu", "Update items in the Help menu",
   "Open the Help menu. Click Check for updates….",
   "The Help menu has Connect to Claude…, Check for updates… and a switch for checking automatically. Check for updates… answers with a plain message: either that this is the newest version, or that a version is available with What's new, Update and Later. Write down exactly what it says. Do NOT click Update unless the owner says so.", ""),
  ("u-connect", "Connect to Claude page",
   "Open Help > Connect to Claude….",
   "The page says whether the Claude helper is installed, has a button Save the Claude extension file… and shows one line for Claude Code with a Copy button. Click Copy and paste the line into the note. Click Save the Claude extension file… and save it into the clipforge-test-output folder: a file ending in .mcpb appears there.", ""),
  ("u-rename", "Renaming to a name that exists",
   "On the project list, rename a project to the exact name of another project.",
   "The renamed project gets \" (2)\" at the end of its name; no two projects share a name.", ""),
  ("u-fillerplay", "Filler preview plays the cut",
   "Only if Remove filler words… listed at least one filler: open it again and press the play button of one row.",
   "The preview plays about 1.5 seconds before the filler, skips the filler itself, and continues about 1.5 seconds after it. Ask the owner to listen: the filler word is not heard.", "listen"),
 ]),
 ("Finish", [
  ("t-remove", "Remove a language pack",
   "Ask the owner whether the pack downloaded in this round should stay. Only if the owner says remove it: open Transcribe speech… and click Remove on that row. Otherwise set Not tested with \"owner keeps the pack\".",
   "The row shows Download again and the line below shows less space used (or \"No packs on this computer yet.\"). The transcripts already made are still there: the Transcript column still shows the text.", ""),
 ]),
]

INSTR_5 = """You are testing ClipForge 1.12.0 (build 114), a video editor, on the owner's Windows PC. Problems are expected; your job is to find them and write them down precisely. This round checks only what is new in 1.10 and 1.11 on the computer: a voice recorded separately (the "What is this sound?" question, lining up, nudging, unlinking), speech to text (Transcribe speech…, language packs), Captions from speech…, the Transcript, Remove filler words… and Automatic cuts…, project names, the export window and the menus, plus five steps that check the basics still work. Older features were tested in round 4.

BEFORE YOU START
- Fill in "Device" (for example "Windows 11 laptop, RTX 4070") and "Tester".
- Fill in "Version shown in the app": in ClipForge open Help > About ClipForge, click Copy version info and paste the text. If it does not match the build named at the top of this page (a red warning appears), tell the owner and say so in the Summary.
- Test files: ask the owner where they are. You need:
  A. a talking video, 2-5 minutes, one person speaking with pauses and some "um" / "uh";
  C. a music file (MP3 or M4A), at least 1 minute;
  E. a second short video, 10-30 seconds, anything;
  V + W. optional: a video and the voice recorded separately for it (a separate microphone, or a Zoom recording: one video and one sound file per speaker);
  D. optional: a clip in which someone speaks Russian or Hebrew.
  If something is missing, ask the owner. Do not download files from the internet.
- Speech to text needs a speech program on the computer (FFmpeg 8 with its "whisper" filter, whisper.cpp, faster-whisper or OpenAI whisper) and usually a language pack. The step "Transcribe speech…" shows what was found. Do not install programs yourself: tell the owner what the window says.
- Language packs are downloads of about 140 MB (Small), 470 MB (Medium) and 1.6 GB (Large). Click Download only in the step that says so, and only for the pack the owner agreed to. NEVER download a Large pack without asking the owner first.
- Most steps use the project "Round 5 test", made in the step "Make the test project". Do the steps in order: later steps build on earlier ones.

RULES
- Each step has "Do" (exact actions) and "Expected" (what should happen). Do the actions exactly, then compare with Expected.
- For each step choose a Result and write a Note. Where a step says to copy a text or write down a number, put it in the note.
- Result meanings: PASS = you saw exactly the expected result. FAIL = something was wrong (write what you did, what happened, and what you expected). Partial = part of it worked (say which part). Not tested = you could not do it (say why). Needs the owner = only a person can judge it and the owner was not available.
- Steps tagged "ask the owner to listen" or "ask the owner to watch" depend on hearing, or on lip sync and movement that screenshots cannot show. Do the actions and check everything you can see. Then ask the owner in the chat, for example: "Please play the preview from 0:05 and tell me whether the voice matches the lips." Write the owner's answer in the note starting with "Owner:", and set PASS or FAIL from it. If the owner is not available, set Needs the owner.
- Buttons and menu items are written here as the app shows them. If a name on the screen is different, or an item is missing or greyed out when the step expects it to work, write down exactly what you see.
- If a drag does not work for you, try twice. Then use the menu bar or panel buttons if the step offers them; otherwise set Needs the owner and write that you could not perform the drag (it may still work for a human).
- Never delete, move or rename the owner's files or projects. Save every export into a new folder named clipforge-test-output next to the test videos, with the file name the step gives (for example r5-full.mp4).
- If the app closes by itself or freezes, write down exactly what you were doing, fill in the Crash box, reopen it and continue.
- Do not guess. Only mark PASS for what you actually saw, or for what the owner told you they heard or saw.
- This page keeps your answers in this browser as you go. When finished, fill in the Summary box (most important problems first), then click "Download filled checklist" and give the downloaded file to the owner."""

# ---------------------------------------------------------------- round 6 (1.15.0)
# The Windows computer round for 1.15.0 (build 130): "all the features" in
# one sitting. What is new since round 5 - the Text window, sound waves and
# who is speaking (1.13), publishing kit, notes, shorts, markers and the
# Connect to Claude page (1.14), the installer and the update log (1.14.1),
# menus by topic, Settings and suggestions (1.15) - plus a 6-step regression
# core. Labels are the app's own: test/ui/menu_tree_snapshot.txt,
# lib/ui/app_menu.dart, lib/ui/editor/acts.dart, editor_actions.dart (the
# reasons of greyed items), action_sheets.dart, suggestions.dart,
# text_panel.dart, export_dialog.dart, publishing_panel.dart,
# shorts_actions.dart, lib/ui/settings/settings_screen.dart,
# lib/ui/claude/connect_claude.dart, lib/ui/update/update_ui.dart,
# lib/ui/help/what_moved.dart. "Send feedback" is 1.16 and is not tested.
# Steps: (id, title, do, expected, tag) as in rounds 4 and 5.
STEPS_6 = [
 ("Start", [
  ("st-version", "The app shows 1.15.0, build 130",
   "Start ClipForge from the Windows Start menu. Read the small grey line at the bottom of the project list. Open Help > About ClipForge, read it, click Copy version info and paste it into \"Version shown in the app\" at the top of this page. Close About.",
   "The grey line and About both show version 1.15.0 and build 130, the same as named at the top of this page. No red warning appears under the version box. The pasted text has the version line, the system and a line starting with \"Folder:\".", ""),
  ("st-updated", "The \"Updated to\" line and the \"What moved\" note",
   "Look at the top of the project list right after the first start of 1.15.0. If a line \"Updated to 1.15.0\" is there, click What's new, close Help again, then close the line with its cross. If a window \"Things are easier to find now\" opens, read it and click Show me Settings, then close Settings. (Both appear only once. If the owner has already closed them, set Not tested and write \"owner saw it: yes / no\" after asking the owner.)",
   "One quiet line \"Updated to 1.15.0\" with a What's new button and a cross; What's new opens Help on the page that starts with 1.15.0. The note \"Things are easier to find now\" says nothing was removed and every keyboard shortcut works as before, lists what has a new place (Settings, Adding things, Split / trim / freeze / crop, Everything about sound, Text window and speech, Zoom / snapping / sound waves / shape / video size, Check for updates automatically, Right-click on the timeline) and has the buttons What's new, Show me Settings and OK. After closing, neither comes back at the next start.", ""),
  ("st-install", "Installed by the installer: Start menu and folder",
   "Open the Windows Start menu and type ClipForge. Then look at the \"Folder:\" line in the text you pasted in the first step.",
   "The Start menu has ClipForge and \"ClipForge read me\". The folder ends in AppData\\Local\\Programs\\ClipForge (the installer's place), not in a downloads folder and not in a name ending in \".update-new\". ClipForge did not ask \"ClipForge is running from a download folder. Tidy up?\". If the folder is somewhere else, write the whole line down.", ""),
  ("st-projects", "Earlier projects are still there",
   "Read the project list. Open one project from an earlier round, play 5 seconds, and go back with File > Back to projects.",
   "Projects from earlier rounds are listed, the one you opened shows its clips with pictures and plays, and no clip says Missing.", ""),
 ]),
 ("Menus by topic", [
  ("mn-project", "Make the test project",
   "On the project list click New project. Add files A and B (see the instructions): Add > Videos or photos…, or drag them from Explorer onto the window. Put the playhead at 0:00, choose Add > Music or sound…, then My files > Choose a music file… and pick M; when it asks \"What is this sound?\", leave Music selected and click Add. Put the playhead at 0:03 and choose Add > Title, and type: Round 6. Choose File > Rename project… and call it \"Round 6 test\". If a thin line with a tip and a button appears under the top bar at any time, leave it alone for now.",
   "The editor shows A and B on the main track with clip pictures, the music on a Music track from 0:00 and the title on a title row. The window asking \"What is this sound?\" offers Voice for the video, Music and Sound effect, with Cancel and Add. The top bar shows Saved (or Saving… briefly).", ""),
  ("mn-file-edit-add", "File, Edit and Add menus",
   "In the bar at the top of the window there are nine menus: File, Edit, Add, Clip, Sound, Text and speech, View, Playback, Help. Open File, Edit and Add and compare every item and shortcut with Expected. Do not click Find in the text… yet.",
   "File: New project (Ctrl+N), Open project file… (Ctrl+O) | Rename project…, Publishing notes…, Back to projects | Export… (Ctrl+E), Export several…, Export subtitles (.srt)… | Settings… (Ctrl+,) | Exit (Alt+F4). Edit: Undo (Ctrl+Z), Redo (Ctrl+Shift+Z), History (Ctrl+Shift+H) | Duplicate (Ctrl+D), Copy settings (Ctrl+Shift+C), Paste settings (Ctrl+Shift+V), Delete (Delete) | Find in the text… (Ctrl+F). Add: Videos or photos…, Music or sound…, Voice recording…, Title, Caption…, Subtitle file (.srt)…, Overlay video or photo…, Good moment marker (M). Nothing is missing and nothing extra is there (a greyed item may have a reason in brackets after its name). Write down every difference.", ""),
  ("mn-clip-sound-text", "Clip, Sound and Text and speech menus",
   "Open Clip, Sound and Text and speech and compare with Expected. Do not click Text window yet (it is tested later, and a suggestion depends on it not having been opened).",
   "Clip: Split (S), Start at playhead (I), End at playhead (O), Freeze frame, Remove silences…, Crop and position…, Rotate right, Move earlier, Move later | Make a short from here…, Make shorts from markers…, Good moments…. Sound: Fit music to video, Line up voice with video, Separate sound…, Put sound back, Add sound track, Lower music under speech, Copy music credits. Text and speech: Text window (Ctrl+Shift+T), Transcribe speech…, Captions from speech…, Remove filler words…, Automatic cuts…. Write down every difference.", ""),
  ("mn-view-playback-help", "View, Playback and Help menus",
   "Open View (and its Shape and Video size submenus), Playback and Help and compare with Expected. Click View > Zoom in and View > Zoom out once each, and Playback > Next frame once.",
   "View: Zoom in (+), Zoom out (-), Snap to playhead and edges (ticked), Show sound waves (ticked) | Shape > Original (as the first clip), 9:16 upright, 16:9 wide, 1:1 square, 4:5 upright | Video size > Same as the first clip, 720p, 1080p (Full HD), 4K; the current shape and size have a tick. Playback: Play/Pause (Space), Play backwards (J), Pause (K), Play forwards (L) | Go to start (Home), Go to end (End), Previous frame (Left), Next frame (Right) | Previous speech start (Ctrl+Left), Next speech start (Ctrl+Right). Help: ClipForge Help (F1), Keyboard shortcuts, Show the tour, What's new | Connect to Claude…, Check for updates… | Copy version info, About ClipForge. The zoom items zoom the timeline; Next frame moves one frame. Write down every difference, also an item that is in the app but not in this list.", ""),
  ("mn-grey", "A greyed item says why (three spot checks)",
   "Click an empty place on the timeline so nothing is selected. Open Sound and read Fit music to video. Open Edit and read Paste settings and Delete. Open Clip and read Make shorts from markers…. Then click the music on its track and open Sound again; then press Ctrl+Shift+C with the playhead on clip A and open Edit again. Finally go to the project list (File > Back to projects), open the Clip menu there, and open \"Round 6 test\" again.",
   "With nothing selected the items are grey, stay in their place and read: \"Fit music to video (select a music clip)\", \"Paste settings (copy settings first)\", \"Delete (select something first)\", \"Make shorts from markers… (no good moment markers yet)\". With the music selected Fit music to video can be clicked; after copying settings Paste settings can be clicked. On the project list the editor's items are grey without a reason. Write down the exact text of any greyed item that gives no reason while a project is open.", ""),
  ("mn-context", "Right-click menus on the timeline",
   "Right-click clip A; press Esc. Right-click the music; Esc. Right-click the title; Esc (do not choose Text window). Right-click an empty part of a track at about 0:10; Esc. Then right-click clip A again and choose Duplicate, and press Ctrl+Z.",
   "Each right-click selects that item and opens a small menu at the pointer. Clip: Split, Start at playhead, End at playhead | Duplicate, Copy settings, Paste settings | Freeze frame, Remove silences…, Crop and position…, Rotate right, Separate sound…, Put sound back | Move earlier, Move later, Make a short from here… | Delete. Music: Fit music to video, Line up voice with video, Put sound back, Lower music under speech, Copy music credits | Delete. Title: Duplicate, Text window | Delete. Empty place (the playhead jumps there): Videos or photos…, Music or sound…, Voice recording…, Title, Caption…, Overlay video or photo…, Good moment marker | Split, Make a short from here…. Items that cannot be used are grey with the reason in brackets, for example \"Put sound back (select a separated sound)\". Duplicate from the menu adds one copy; undo removes it.", ""),
 ]),
 ("Settings page", [
  ("set-open", "Open Settings",
   "Choose File > Settings…. Read the page from top to bottom and close it with the cross. Then press Ctrl+comma and close it again.",
   "A window \"Settings\" with the parts: Editing (Snap to playhead and edges, Show sound waves), Text window (Where it opens: At the right / Below), Export (Use graphics card (faster)), Suggestions (Show suggestions, and the button \"Show hidden suggestions again (none hidden)\"), Updates (Check for updates automatically, Check now, and the version line), Claude (a line about the helper for Claude, and Connect…), About (About ClipForge, Copy version info, What's new, Licences). Every switch has one line of explanation. Ctrl+comma opens the same window.", ""),
  ("set-snap", "Snap to playhead and edges",
   "Put the playhead at 0:08 and slowly drag the end of the title towards it: note whether it jumps onto the playhead. Open Settings and switch Snap to playhead and edges OFF; close Settings. Open the View menu. Drag the title end past the playhead again. Leave the switch OFF for now.",
   "With the switch on, the edge jumps onto the playhead and a yellow line shows. With it off there is no jump and no yellow line, and View > Snap to playhead and edges has no tick: the menu and Settings are the same switch. (If you cannot drag, try twice, then check only the tick in the View menu and set Partial.)", ""),
  ("set-waves", "Show sound waves",
   "Look at the music on the timeline and at the bottom edge of clip A. Open Settings, switch Show sound waves OFF, close Settings and look again. Open the View menu. Leave it OFF for now.",
   "With the switch on, the music shows its sound waves (tall where it is loud) and clip A has a slim wave along its bottom; the first time, \"Drawing sound…\" shows at the top right of the timeline for a moment. With it off the waves are gone at once and the blocks are plain, and View > Show sound waves has no tick.", ""),
  ("set-export-text", "Use graphics card (remembered), and where the Text window opens",
   "Open Settings. Switch Use graphics card (faster) OFF. Under Text window click Below. Close Settings. Press Ctrl+E, choose Custom under \"Where is it going?\", read the switch Use graphics card (faster) and the line \"Will use: …\", and click Cancel. (Do not open the Text window yet.)",
   "In the Export window the switch Use graphics card (faster) is off, as set in Settings, and the line reads \"Will use: Processor (graphics card turned off)\". (The Text window position is checked in the group \"Text window\".)", ""),
  ("set-suggest", "Show suggestions on and off",
   "Look under the top bar of \"Round 6 test\": a thin line with a tip is probably there (for example about the music). Write its text down. Open Settings, switch Show suggestions OFF and close Settings. Look again. Leave it OFF for now. (If no line was there before, set Partial and say so.)",
   "With the switch off no suggestion line is shown anywhere, at once. Nothing else changes.", ""),
  ("set-restart", "Every switch survives a restart",
   "Open Settings and switch Check for updates automatically OFF. Close Settings and choose File > Exit. Start ClipForge again, open \"Round 6 test\" and open Settings. Read all the switches, and the View menu. Then put everything back: Snap to playhead and edges ON, Show sound waves ON, Use graphics card (faster) ON, Show suggestions ON, Check for updates automatically ON. Leave the Text window on Below.",
   "After the restart every switch is as you left it: snapping off, sound waves off, Below selected, graphics card off, suggestions off, automatic update check off; the View menu has no ticks on its two switches and the timeline has no waves. After switching them back on, the waves and the suggestion line return and the View menu shows both ticks.", ""),
 ]),
 ("Suggestions", [
  ("sg-small", "A small first clip: Use 1080p",
   "Go to the project list and click New project. Add only file S (the small clip). Rename the project \"Round 6 tips\". Wait a second without playing. Read the line under the top bar. Click Use 1080p. Open View > Video size.",
   "A thin line under the top bar says \"The first clip is small (width×height), and the video takes its size from it.\" with the button Use 1080p, then Don't show again and a cross. After Use 1080p the line goes away and View > Video size has its tick on 1080p (Full HD). (If S is 720p or bigger on its short side, no line appears: set Not tested and write the size of S.)", ""),
  ("sg-shape", "A wide clip in a 9:16 video: Fill, Blur, Crop…",
   "In \"Round 6 tips\" add file A after S. Choose View > Shape > 9:16 upright. Wait a second. Read the line. Click Blur. Press Ctrl+Z, then Ctrl+Shift+Z.",
   "The line says \"A clip has another shape than the video, so it gets bars.\" with three buttons: Fill, Blur and Crop…. Blur selects that clip (the first one that sits between bars) and its bars become a blurred copy of the picture; the line goes away. Undo and redo take the blur back and bring it again. If another line shows first, write its text down and close it with the cross.", ""),
  ("sg-music", "Music longer than the video: Fit to video; hidden while playing",
   "Put the playhead at 0:00 and add music M (Add > Music or sound…, My files; choose Music when asked). Wait a second and read the line. Press Space, look at the place of the line while the video plays, and press Space again. Then click Fit to video.",
   "The line says \"The music is longer than the video.\" with Fit to video. While the video plays the line is not shown; it is back when playback stops. Fit to video selects the music and shortens it so that it ends with the video, and a message says \"The music now ends with the video, with a 2-second fade-out.\" The line is gone afterwards.", ""),
  ("sg-lower", "Music while someone talks: Lower the music",
   "Stay in \"Round 6 tips\" and wait until \"Drawing sound…\" at the top right of the timeline is gone (up to a minute). Read the line. Click Lower the music. Open the Sound menu.",
   "The line says \"Music plays while someone is talking.\" with Lower the music. After the click the line goes away and Sound > Lower music under speech has a tick. (It needs Show sound waves to be on. If instead a line \"A long clip has pauses in the talking.\" or \"There is talking in this video and no captions yet.\" shows, write it down, close it with the cross and say so.)", ""),
  ("sg-text", "Captions, and Text never opened: Open Text",
   "Put the playhead at 0:02, choose Add > Caption…, type: Sam Taylor: This is a test caption. and click Add. Wait a second. If a line about pauses or about captions from speech is shown, write it down and close it with the cross, then wait again. Read the line and click Open Text. Then close the Text window with its cross.",
   "The line says \"Text shows every caption in one place, to read, search and fix.\" with Open Text. The button opens the Text window with the caption in it. This suggestion is shown once ever: if the Text window was already opened on this computer with 1.15, it does not appear (set Not tested and say so).", ""),
  ("sg-never", "\"Don't show again\" sticks, and Settings brings it back",
   "Make a new project with file A only, rename it \"Round 6 tips 2\", and add music M at 0:00 as before. When \"The music is longer than the video.\" shows, click Don't show again. Go back to the project list and open \"Round 6 tips 2\" again. Open Settings and read the button under Show suggestions; click it; close Settings and wait a second.",
   "After Don't show again the line goes away and does not come back when the project is opened again (another suggestion may take its place). In Settings the button reads \"Show hidden suggestions again (1)\"; clicking it shows \"One suggestion can show again.\" and the button reads \"Show hidden suggestions again (none hidden)\". Back in the project the line about the music is shown again.", ""),
 ]),
 ("Basics still work (6-step regression)", [
  ("reg-split", "Split, delete, undo, redo",
   "Open \"Round 6 test\". Click clip B, put the playhead in its middle and press S. Click the second piece and press Delete. Press Ctrl+Z once, then Ctrl+Shift+Z, then Ctrl+Z.",
   "S cuts B into two pieces. Delete removes the selected piece. Undo brings it back, redo removes it again, the last undo brings it back: B ends in two pieces. Clicking a clip moves the preview to it.", ""),
  ("reg-history", "History",
   "Press Ctrl+Shift+H. Read the list. Click the oldest step, then the newest. Press Ctrl+Shift+H again.",
   "A History column opens with your changes by name, newest first (for example \"Split clip 2\"). Clicking an old step puts the project back to that point (later steps look grey); the newest restores everything. The same keys hide the column.", ""),
  ("reg-title", "A title: font, style, position, animation",
   "Click the title \"Round 6\" on the timeline. In the side panel click each Font, two different Styles, switch Outline on, click Position Top and then Lower third, and set Appear to Pop. Play from 0:02.",
   "Each font and style visibly changes the letters in the preview; Outline draws a line around them; Top and Lower third move the text. On play the title pops in at 0:03. Ask the owner to watch.", "watch"),
  ("reg-keys", "Keys: J K L, I and O",
   "Click an empty place on the timeline. Press L, wait 2 seconds, press K; press J, wait 2 seconds, press K. Select clip A, put the playhead about 2 seconds into it and press I; put it 2 seconds before the end of A and press O. Press Ctrl+Z twice.",
   "L plays, K pauses, J goes backwards in small steps. I makes A start at the playhead, O makes it end there; each is one History step (\"Start of clip 1 at playhead\", \"End of clip 1 at playhead\") and each undo restores one.", ""),
  ("reg-export", "Export the project",
   "Press Ctrl+E. Under \"Where is it going?\" choose Custom; Make: Video, Full quality. Copy the lines \"File size: about …\" and \"Will use: …\" into the note. Click Export and save as r6-full.mp4 in the clipforge-test-output folder. When it is done, play the file in Media Player.",
   "It finishes with \"Video saved\", says what was used (graphics card or processor) and \"Took …\". Ask the owner to watch and listen to the file: cuts, title and music as in the preview, voice in sync. (The first export ever on this computer may also show one line that starts \"Your first export:\".)", "watch,listen"),
  ("reg-quit", "Quit while editing: everything is saved",
   "With \"Round 6 test\" open and nothing exporting, press Alt+F4. Start ClipForge again and open the project.",
   "It closes without asking. After reopening, the two pieces of B, the title with its look and the music are all there.", ""),
 ]),
 ("Sound", [
  ("snd-tracks", "Sound tracks and a track's menu",
   "In \"Round 6 test\" choose Sound > Add sound track. Click the new track's name on the left of the timeline and read its menu; change Volume, switch Mute on and off, then click Delete track. Then click the name of the Music track and read the same menu without changing anything.",
   "A new sound row appears and a message names it. The track menu has Name, Volume, Mute, Solo, Lower this track under speech, This track is speech, Move up, Move down and Delete track. Delete track removes the empty track. No more than three sound tracks can exist (with three, the Sound menu item reads \"Add sound track (there are already 3 tracks)\").", ""),
  ("snd-lower", "Lower music under speech: all, some, none agree in three places",
   "Put the playhead at 0:00 and add music M a second time (it lands on another sound track). Click an empty place so nothing is selected. Look at three places: (1) the side panel, \"All music in this project\" > Lower music under speech; (2) the Sound menu; (3) the menu of each of the two music tracks (click its name), Lower this track under speech. Now switch the side-panel switch ON and look at all three. Then switch Lower this track under speech OFF in ONE track's menu and look at all three. Then click Sound > Lower music under speech once and look again. Finally delete the second music.",
   "None: the side-panel switch is off, the Sound menu item has no tick, both track switches are off. All: the side-panel switch is on, the Sound menu item has a tick, both track switches are on. Some: the side panel says \"On for some tracks only (set in each track's menu). Turn this on to lower every music track.\", and the Sound menu item shows a dash instead of a tick and reads \"Lower music under speech — on for some tracks\". Clicking the menu item from \"some\" turns every music track on. The three places never disagree.", ""),
  ("snd-voice", "A voice recorded separately: \"What is this sound?\", lined up",
   "Needs files V and W (otherwise set Not tested for this and the next step). Make a new project with V, rename it \"Round 6 voice\". Choose Add > Voice recording… and pick W (with a Zoom recording: all voice files together). In the window, check what is selected, type the speaker's name in \"Who speaks (name of its track)\" (use Sam Taylor, and Alex K for a second file), leave \"Mute the camera's own sound\" on and click Add and line up. Play 15 seconds from two places.",
   "The window asks \"What is this sound?\" (\"What are these sounds?\" for several files) with Voice for the video selected, a name field per file, the switch Mute the camera's own sound, and the buttons Cancel and Add and line up. It shows \"Lining up the voice with the video…\" and then \"Lined up with clip 1 (…). It follows the picture when you cut. The camera's own sound is muted.\" (several files: \"… voices lined up with the video, each on its own track. They follow the picture when you cut.\"). Each voice is on its own track named after the speaker. Copy the message. Ask the owner to watch and listen: lips match the voice and no second, echoing voice is heard.", "watch,listen"),
  ("snd-who", "Who is speaking: colours and waves",
   "In \"Round 6 voice\" wait until \"Drawing sound…\" is gone. Look at the voice rows, zoomed so that a minute fills the window. Click a video clip and look at its bottom edge. If a line \"With a voice track, the timeline shows who is speaking when.\" appears, click See who is speaking and close Help again.",
   "Every voice row has sound waves. The stretches where that person talks are bright in the speaker's colour and the pauses are dim; each speaker has a different colour and the microphone at the left of the row has it too. With two voices, a stretch where only one person talks is bright on that row only. A video clip whose own sound is muted has no wave along its bottom. See who is speaking opens the help article \"See who is speaking\". Ask the owner whether the bright stretches match who is talking in two places.", "watch,listen"),
  ("snd-speech-nav", "Previous and next speech start",
   "Open \"Round 6 test\" (or stay in \"Round 6 voice\") and wait until \"Drawing sound…\" is gone. Click an empty place. Go to the start (Home). Click the double arrow to the right of Play three times, then the double arrow to the left once. Press Ctrl+Right twice and Ctrl+Left once. Choose Playback > Next speech start once. In \"Round 6 voice\" also click one voice and press Ctrl+Right twice.",
   "The double arrows have the tooltips \"Previous speech start (Ctrl+Left)\" and \"Next speech start (Ctrl+Right)\". Each press moves the playhead to the next (or previous) place where talking starts after a pause; the buttons, the keys and the menu items do the same. With a voice selected they follow that speaker only. Before the sound is drawn the menu items read \"Next speech start (no speech found yet)\". Ask the owner to press Play at two of the stops: someone starts talking right there.", "listen"),
 ]),
 ("Text window", [
  ("tx-open", "Captions as a page, by speaker",
   "In \"Round 6 test\" add four captions with Add > Caption… (move the playhead first, type the text, click Add): at 0:02 \"Sam Taylor: Welcome to the test.\"; at 0:06 \"This line has no name.\"; at 0:10 \"Alex K: Thanks, happy to be here.\"; at 0:14 \"Alex K: Let us test the search.\" Then press Ctrl+Shift+T (or click the Text button at the top right, or Text and speech > Text window).",
   "The Add caption window has the field \"What is being said\" and says where the caption appears. The Text window opens UNDER the preview (as set in Settings: Below). It is titled Text and shows the captions as a readable page: the lines of one speaker joined into a paragraph with the time at the side, the name \"Sam Taylor\" shown once above his lines (the caption without a name belongs to him), then \"Alex K\" once, each with a coloured bar. If the project also has a transcript or titles, a switch at the top chooses Captions / Transcript / Titles.", ""),
  ("tx-follow", "Follow playback, click to jump",
   "Go to the start and press Play; watch the Text window until 0:16, then pause. Click the sentence \"Thanks, happy to be here.\" in the Text window. Then click the first caption block on the timeline.",
   "While the video plays, the line being spoken is marked, one after the other, and kept in view (if you scroll the page by hand, following stops and a Now button brings it back; with four captions the page may be too short to scroll). Clicking a sentence moves the playhead to 0:10 and selects that caption on the timeline. Clicking a caption on the timeline marks it in the Text window.", ""),
  ("tx-search", "Search",
   "Press Ctrl+F. Type: test. Press Enter twice, then Shift+Enter once. Clear the box and type: xyzzy. Clear the box.",
   "Ctrl+F puts the cursor into \"Find in the text…\". Every place with \"test\" is marked and counted (\"1 of 2\"); Enter goes to the next one, Shift+Enter to the previous one. For xyzzy it says \"Not found\".", ""),
  ("tx-edit", "Edit a caption, delete captions",
   "Double-click \"This line has no name.\" in the Text window, change it to \"This line was edited.\" and press Enter. Double-click it again, delete all its text and press Enter; then press Esc. Click the caption \"Let us test the search.\", then click Delete caption. Press Ctrl+Z. Click the first caption, Shift-click the second and click Delete captions. Press Ctrl+Z. Open History.",
   "Double-click opens the caption's text in a box with the hint \"Enter saves · Shift+Enter: new line\"; Enter saves and the preview shows the new text. An empty text is refused with \"A caption cannot be empty. Use \"Delete caption\" to remove it.\" Delete caption removes one (\"Caption deleted.\"); with two selected the bar says \"2 captions\" and Delete captions removes both (\"2 captions deleted.\"). Each Ctrl+Z brings them back in one step. History shows \"Edited caption '…'\" and \"Deleted 2 captions\".", ""),
  ("tx-cut", "Cut this part out of the video…",
   "Note the length of the video. In the Text window click the caption \"Thanks, happy to be here.\" and click Cut this part out of the video…. Read the question and click Cut it out. Note the new length. Do NOT undo (the step \"Automatic cuts\" below puts it back).",
   "A question \"Cut this part out of the video?\" says from when to when, how much \"of the picture and its sound will be removed\", shows the words, says that captions and titles on this part go with it, and offers Cancel and Cut it out. After Cut it out a message says \"Cut … out of the video.\" with Undo; the video is shorter by that much, clip A is in two pieces there, and that caption is gone from the page.", ""),
  ("tx-copy-dock", "Copy, save as text, dock right and below",
   "In the Text window click the three dots (\"Copy, save, place\"). Click Copy all text and paste it into the note. Open the three dots again: Copy with times and names, paste. Then Save as text file… and save it into clipforge-test-output. Then Show at the right; drag the left edge of the window a little; open the three dots and click Show under the preview. Open Settings and read \"Where it opens\".",
   "The menu has Copy all text, Copy with times and names, Save as text file…, Export subtitles (.srt)…, Show at the right, Show under the preview and a help line. The pasted text has every caption; with times and names it also has the times and \"Sam Taylor\" / \"Alex K\". A file \"Round 6 test.txt\" is saved (\"Text saved: …\"). Show at the right makes the window a column at the right whose edge can be dragged; Show under the preview puts it below again. Settings shows the same choice each time (At the right / Below).", ""),
 ]),
 ("Speech (Not tested: no speech engine is allowed)", [
  ("sp-open", "Transcribe speech…: the speech program, or a plain explanation",
   "In \"Round 6 test\" select clip A and choose Text and speech > Transcribe speech…. Wait until \"Looking at what this computer has…\" is gone. Read the window. Do not click Download.",
   "A window \"Transcribe speech\" with a Language list. EITHER a line \"Uses: …\" names the speech program found (write it down) and a part \"Language pack\" lists Small, Medium and Large with their sizes and Download or Remove (\"Nothing is downloaded until you press Download.\"), OR a box says in plain words: \"Turning speech into text needs a speech program on this computer, and none was found.\", which programs ClipForge can use, and what to install on Windows (winget install ffmpeg). In the second case set this step to PASS if the text is clear, copy it into the note, close the window, and set the next three steps to Not tested with \"no speech engine\".", ""),
  ("sp-run", "Transcribe",
   "Only with a speech program. If no language pack is on the computer, ask the owner which one to download (suggest Small; NEVER Large) and click Download on that row only after the owner says yes. Choose the language of file A and click Transcribe. Wait until it is finished.",
   "A progress bar with a Stop button; the app stays usable. At the end a message says \"Speech transcribed: … words. Read it in the Text window.\" Write down the number of words and how long it took. The Text window now has a switch with Captions and Transcript.", ""),
  ("sp-captions", "Captions from speech…",
   "Only with a transcript. Choose Text and speech > Captions from speech…. Read the window, tick \"Replace the … captions that are already there\" if it is offered, and click Add captions. Play the first minute.",
   "The window \"Captions from speech\" says how many captions it adds, with Lines and \"Longest line: … letters\". After Add captions a message says \"Added … captions from the speech. Undo takes them away.\" and the captions are on the timeline and in the Text window. Ask the owner to watch: each caption appears when its words are spoken and fits inside the picture (wrong names or numbers are normal: write down two examples).", "watch,listen"),
  ("sp-fillers", "Remove filler words…: the review list",
   "Only with a transcript. Choose Text and speech > Remove filler words…. Wait until \"Checking the picture around each cut…\" is gone. Click Light, Normal and Strong and copy the summary line of each. Press the play button of one row. Then click Cancel (nothing is removed in this round).",
   "A window \"Remove filler words\" with Fillers of (a language), Select: Light / Normal / Strong, a line that explains the strength, a summary line (\"… of … selected · saves …\") and a list with a tick box, the time, the filler in quotes and a play button (\"Play it as it would be after the cut\") per row; or the line \"No filler words were found in the transcript.\" Light selects the fewest, Strong the most. Cancel changes nothing.", ""),
  ("sp-autocuts", "Automatic cuts… → Put back",
   "Choose Text and speech > Automatic cuts… (this works without a speech engine too: the part cut out in the Text window is listed). Read the window. Click Put back on the row of that part. Close the window and look at the length of the video and at the Text window.",
   "The window \"Automatic cuts\" has a line with the number of cuts and the time removed, explains that it lists what Remove filler words, Remove silences and \"Cut this part out\" took out, and has one row per cut with Put back, plus Put back all and Close. After Put back the row is gone, the video has its old length and clip A is one piece again there; the caption that was on that part does NOT come back (only Undo returns captions). With nothing left the menu item reads \"Automatic cuts… (nothing was cut automatically)\". If the menu has no Automatic cuts… at all, write that down.", ""),
 ]),
 ("Shorts and markers", [
  ("sh-marker", "M drops a good-moment marker",
   "In \"Round 6 test\" play from the start and press M at about 0:25, and again at about 0:50 (if the video is shorter, use one third and two thirds). Pause. Put the playhead exactly on the first flag (click the flag) and press M again. Right-click the second flag and press Esc.",
   "Each M drops a small flag on the time ruler, also while playing, with the message \"Marked a good moment at …\" and Undo. Clicking a flag moves the playhead there. M on a place that has one says \"There is already a marker here.\" The right-click menu of a flag has Make a short from here…, Make shorts from markers…, Good moments… and Remove this marker.", ""),
  ("sh-moments", "Good moments list",
   "Choose Clip > Good moments…. Read the list. Close it. Click an empty place on the timeline and look at the bottom of the side panel (\"Shorts and publishing\").",
   "A window \"Good moments\" lists both markers with their times (and what is said there when there are captions), each with \"Make a short around it\" and \"Remove the marker\", and the buttons Make shorts from markers… and Close. The side panel, with nothing selected, has Good moment marker (M), Good moments (2)…, Make a short from here…, Make shorts from markers… and Publishing notes….", ""),
  ("sh-from-markers", "Make shorts from markers…",
   "Choose Clip > Make shorts from markers…. Read the question, leave Short caption look ticked and click Make them. When it is done click OK. Go to the project list, read the new names, and open \"Round 6 test\" again.",
   "The question \"Make 2 shorts from the markers?\" explains: one new upright project around each marker, about 20 seconds before it to 25 seconds after, starting and ending at a pause; it lists the two parts with their times and lengths. Afterwards \"2 shorts are ready\" lists the new projects by name and length, says this video was not changed, and has an OK button. The project list has two new projects; \"Round 6 test\" is unchanged.", ""),
  ("sh-here", "Make a short from here…",
   "Put the playhead at 0:05 and choose Clip > Make a short from here…. Click 30 s, 45 s, 60 s and back to 30 s, reading the line with the times each time. Leave \"Start and end at a pause\" and \"Short caption look\" ticked, tick \"Title at the top\" and type: Watch this. Name the project \"Round 6 short\" and click Make the short. Click Open it. Play it. Then go back to the project list.",
   "A window \"Make a short\" with the chips 30 s, 45 s and 60 s, a line \"From … to … · …\", the note that it is a new upright (9:16) project and this video is not changed, the three tick boxes and \"Name of the new project\". After Make the short: \"The short is ready\" with Stay here and Open it. The short is upright, about 30 seconds long, starts near 0:05 of the long video, has \"Watch this\" at the top for its whole length, and its captions are in the Short caption look: bigger, in the lower middle, outlined, one or two lines. Ask the owner to watch it once.", "watch"),
  ("sh-text", "A short from selected text",
   "Open \"Round 6 test\" and the Text window. Click the first caption, then Shift-click a later one (with only typed captions: the last one). Click Make a short from this…. Read the window, name it \"Round 6 text short\" and click Make the short, then Stay here.",
   "The bar above the page says how many captions are selected and from when to when. The window \"Make a short\" has the chip \"The selection\" selected (next to 30 s, 45 s, 60 s) and shows the selection's times and length; over 60 seconds it warns that Shorts, Reels and TikTok have their own limits. The new project is in the project list afterwards and \"Round 6 test\" is unchanged.", ""),
 ]),
 ("Publishing", [
  ("pb-notes", "Publishing notes with Copy buttons and chapters",
   "In \"Round 6 test\" choose File > Publishing notes…. Type a Title (Round 6 test video), a Description (two sentences) and Hashtags (clipforge test). Click the copy button next to Title and paste into the note. Click Chapters from titles / captions… and read what it says. Tick \"A different title for Shorts, Reels and TikTok\" and type a Short title. Click Copy title and description, paste into the note, and click Done. Open History.",
   "A window \"Publishing notes\" says ClipForge does not post anything itself, with the fields Title, Description, Hashtags and Chapters, each with its own copy button (\"Copy title\" …). Chapters from titles / captions… either fills the Chapters field with lines like \"0:00 …\" and says where they came from (\"… chapters from the captions, named by the first words said. Give them better names.\"), or says plainly why not (\"This video is too short for chapters (each is at least 10 seconds).\" or \"Nothing to make chapters from yet: …\"). Copy title and description copies title, description and hashtags in one go. History shows steps such as \"Publishing title\" and \"Hashtags\".", ""),
  ("pb-dest", "Where is it going? Destinations and warnings",
   "Press Ctrl+E. Under \"Where is it going?\" click each choice in turn and read the line under the choices and any warning: YouTube, Shorts / Reels / TikTok, Instagram post, WhatsApp / Telegram, Podcast audio, Custom. Stay in the window for the next step.",
   "Six choices. YouTube: \"Wide 16:9, 1080p, full quality.\" Shorts / Reels / TikTok: \"Upright 9:16, 1080p. …\"; because the test video is longer than 60 seconds a warning says how long it is, that the sites have their own longest length, that 60 seconds is safe, and \"Check the site.\" Instagram post: a choice Tall 4:5 / Square 1:1, and the same kind of warning. WhatsApp / Telegram: \"A small file (720p) that is quick to send.\", with a warning about 16 MB when the file would be bigger. Podcast audio: a choice MP3 / M4A and no picture settings. Custom: the controls from before (Make, Video size, Full quality / Small file, Frames per second, Use graphics card). The window also shows the publishing notes' title and a Publishing notes… button.", ""),
  ("pb-shape", "\"Make a copy in this shape\" or \"Export as it is\"",
   "In the Export window choose Shorts / Reels / TikTok (the project is wide). Read the question. Click Export as it is and read the size shown; then click Make a copy in this shape and read the size again. Click Export and save as r6-short.mp4 in clipforge-test-output. Read the finished screen. Afterwards check the file: right-click > Properties > Details > Frame width / Frame height. Go to the project list and look for the copy, then open \"Round 6 test\" again and look at its shape.",
   "It says \"Your video is 1920 × 1080; this needs 9:16.\" (the size of your own video; \"16:9\" if the project's shape was set to 16:9 wide) and offers Make a copy in this shape (a new project with a blurred background; this project stays as it is) and Export as it is (\"Keep the shape the video has now.\"). With Export as it is the size shown is wide (1920 × 1080); with the copy it is 1080 × 1920. The exported file is 1080 wide and 1920 high. The finished screen says the copy \"Round 6 test - 9x16\" is in your project list; it is there, and \"Round 6 test\" itself is still wide.", ""),
  ("pb-several", "Export several… into one folder",
   "Choose File > Export several…. Tick YouTube, Shorts / Reels / TikTok and Podcast audio; leave the others and \"Keep the shape copies as projects\" unticked. Read the file name under each tick and the lines below. Click Export 3 files and choose a new folder clipforge-test-output\\kit. Watch the progress. When it is done open the folder in Explorer, check the size of each video (Properties > Details) and open the text file.",
   "Each tick shows its file name. A line explains that for 9:16 a copy of the video in that shape is made for the export, with a blurred background, and that the project stays as it is; another says \"3 files, about … together. You choose the folder next.\" One progress bar with \"1 of 3: …\", \"2 of 3: …\" and one Cancel export; it ends with \"Files saved\". The folder holds \"Round 6 test - YouTube.mp4\" (1920 x 1080), \"Round 6 test - Short 9x16.mp4\" (1080 x 1920), \"Round 6 test - audio.mp3\" and \"Round 6 test - text.txt\". The text file has the title, description, hashtags and chapters from the notes and a part for each file saying what to paste there. No shape copy was added to the project list this time.", ""),
  ("pb-finish", "The finished screen: Show in folder, Copy, Open upload page",
   "On the finished screen of the last export click Show in folder. Click Copy title and description and paste into the note. Click Open YouTube upload page, look at the browser, and close the tab WITHOUT signing in or uploading anything. Then click Done.",
   "Show in folder opens Explorer on the kit folder (after a single export: with the file selected). The pasted text is the title, description and hashtags from the notes. The link line says ClipForge does not sign in or post; the button opens youtube.com's upload page in the owner's own browser (it may ask to sign in: do not). ClipForge itself uploaded nothing.", ""),
  ("pb-listen", "The kit files look and sound right",
   "Play \"Round 6 test - Short 9x16.mp4\" and \"Round 6 test - audio.mp3\" from the kit folder for 30 seconds each.",
   "Ask the owner to watch and listen: the short is upright with the wide picture in the middle and a blurred copy of it above and below, captions and title readable, voice in sync; the MP3 has the same sound as the video, with the music lower while someone talks if Lower music under speech is on.", "watch,listen"),
 ]),
 ("Connect to Claude page", [
  ("cl-page", "Status lights and Details",
   "Choose Help > Connect to Claude…. Read the page from top to bottom. Open every \"Details\" line you see. Do NOT click Connect or Disconnect.",
   "A page \"Connect to Claude\". First a card \"The Claude helper is installed\" with \"Version 1.15.0 (build 130). ClipForge refreshes it every time the app starts.\", the helper's folder (it ends in ClipForge\\claude, under the user's app data, not next to clipforge.exe) and a line that is either \"Not in use right now (that is normal: Claude starts it when needed).\" or \"In use by … now · last action …\". Then a card \"Claude Desktop (the Claude app)\" and a card \"Claude Code (in a terminal)\", each with a round light and one status line: \"Connected (ClipForge 1.15.0)\" (green), \"Connected to an old copy at …\" (amber), \"Not connected\", \"Claude Desktop not found\" / \"Claude Code not found\" (grey), and one button, Connect or Disconnect. Details shows exactly what was asked and answered. Copy both status lines into the note.", ""),
  ("cl-test", "The Test button",
   "On the same page click Test and wait. Open the Details under the result. Click Check again.",
   "The button reads \"Testing…\" for up to a minute, then a green line \"PASS: the helper works by itself (ClipForge 1.15.0).\" with Details that hold the self-test table. A red line starting with \"FAIL:\" is a FAIL for this step: copy the line and the Details. Check again reads the status lights afresh.", ""),
  ("cl-connect", "Connect (only if the owner agrees)",
   "Ask the owner: \"May I press Connect for Claude Desktop and for Claude Code on the Connect to Claude page?\" Only for a row the owner says yes to AND that does not already say Connected: click Connect. If a question \"Replace the old connection?\" appears, read it to the owner and click what the owner says. Also click Copy under \"Or paste this one line into a terminal yourself:\" and paste the line into the note. NEVER click Disconnect. If the owner says no, or both rows are already connected, set Not tested and say which.",
   "After Connect the row's light is green and it says \"Connected (ClipForge 1.15.0)\"; the button of that row now reads Disconnect. The card \"After connecting: close and reopen Claude once\" explains that Claude reads its list of tools when it starts and that ClipForge does not have to be running. The copied line starts with \"claude mcp add\" and ends with the helper's path in the ClipForge\\claude folder.", ""),
 ]),
 ("Updates", [
  ("up-check", "Check now says this is the newest version",
   "Go to the project list. Choose Help > Check for updates…. Then open Settings and click Check now. Do NOT click Update if a newer version is offered: tell the owner instead.",
   "Both answer with the same plain message at the bottom of the window: \"You have the newest version (1.15.0 (build 130)).\" If instead it says a version is available (\"Version … is available: see the top of the project list.\"), write the version down and set Partial: the check works, but 1.15.0 is no longer the newest. Without internet it says so in plain words.", ""),
  ("up-log", "Copy version info: the folder and the update log",
   "Choose Help > Copy version info and paste the text into the note.",
   "A message \"Version info copied. Paste it into your message.\" The text has the version line (1.15.0, build 130), the system, the screen, \"Folder: …\" with the install folder, and, when an in-app update was ever tried on this computer, \"Update log: …\" with the full path of update-log.txt (in a folder called update-state) and \"Its last … lines:\" followed by up to 40 lines of that log. If there is no \"Update log:\" part, write that down (it is correct on a computer where no in-app update ever ran).", ""),
 ]),
 ("Help", [
  ("hp-search", "Help search",
   "Press F1. Search for each of: settings, suggestion, menu, short, chapters, who is speaking. Then search with a typo: sugestion.",
   "Each search shows the fitting article first or near the top: \"Settings\", \"Suggestions\", \"Menus: where everything is\", \"Make a short\", \"Publishing notes: title, description, hashtags, chapters\", \"See who is speaking\". The typo still finds \"Suggestions\".", ""),
  ("hp-articles", "The Settings, Suggestions and Menus articles",
   "Open the articles \"Settings\", \"Suggestions\" and \"Menus: where everything is\" and read each once. Compare two facts of each with the app (for example: the parts of the Settings page; what the cross on a suggestion does; the items of the Sound menu).",
   "Each article opens and its text fits the app you just tested: Settings names the same parts (Editing, Text window, Export, Suggestions, Updates, Claude, About); Suggestions says the cross closes the line for this project, Don't show again turns one off, and lists the same suggestions; Menus lists the same nine menus with the same items and explains \"Greyed-out items say why\" and \"Right-click on the timeline\". Write down any sentence that does not match what you saw (a mention of \"Send feedback\" belongs to the next version and is not a problem of this test).", ""),
 ]),
]

INSTR_6 = """You are testing ClipForge 1.15.0 (build 130), a video editor, on the owner's Windows PC. It was installed with the Windows installer (ClipForge-Setup.exe). Problems are expected; your job is to find them and write them down precisely. This round goes through all the main features in one sitting: the menus sorted by topic, the Settings page, suggestions, sound tracks and voices, the Text window, speech (only if a speech program is on the computer), shorts and markers, publishing (destinations, Export several, Publishing notes), the Connect to Claude page, updates and Help, plus six steps that check the basics. The Android phone has its own page (Round 6 phone). "Send feedback" is not part of this round.

BEFORE YOU START
- Fill in "Device" (for example "Windows 11 laptop, RTX 4070") and "Tester".
- Fill in "Version shown in the app": in ClipForge open Help > About ClipForge, click Copy version info and paste the text. If it does not match the build named at the top of this page (a red warning appears), tell the owner and say so in the Summary.
- Test files: ask the owner where they are (for example C:\\Users\\<you>\\Videos\\clipforge-test). You need:
  A. a talking video, 1-3 minutes, filmed wide (landscape), one or two people speaking with some pauses;
  B. a second short video, 10-30 seconds, anything;
  M. a music file (MP3 or M4A) that is LONGER than video A;
  S. a small clip from a phone or a chat app (smaller than 720p, for example 640 x 360 or 480 x 848);
  V + W. optional: a video and the voice recorded separately for it (a separate microphone, or a Zoom recording: one video and one sound file per speaker);
  R. optional: a clip in which someone speaks Russian or Hebrew (only used if you have time left: add it to a new project and check that Text and captions show the letters properly).
  If something is missing, ask the owner. Do not download files from the internet.
- Do the groups in order: later steps build on the projects made earlier ("Round 6 test", "Round 6 tips", "Round 6 voice"). Do NOT open the Text window before the group "Suggestions" is finished: one suggestion only appears while Text was never opened.
- A thin line with a tip and a button may appear under the top bar at any time. That is a suggestion. Outside the group "Suggestions" leave it alone (do not click its button, its cross or Don't show again) unless a step says so.

RULES
- Each step has "Do" (exact actions) and "Expected" (what should happen). Do the actions exactly, then compare with Expected.
- For each step choose a Result and write a Note. Where a step says to copy a text or write down a number, put it in the note.
- Result meanings: PASS = you saw exactly the expected result. FAIL = something was wrong (write what you did, what happened, and what you expected). Partial = part of it worked (say which part). Not tested = you could not do it (say why, for example "no speech engine" or "no file V"). Needs the owner = only a person can judge it and the owner was not available.
- Steps tagged "ask the owner to listen" or "ask the owner to watch" depend on hearing, or on lip sync and movement that screenshots cannot show. Do the actions and check everything you can see. Then ask the owner in the chat, for example: "Please play the preview from 0:05 and tell me whether the voice matches the lips." Write the owner's answer in the note starting with "Owner:", and set PASS or FAIL from it. If the owner is not available, set Needs the owner.
- Buttons and menu items are written here as the app shows them; " | " in a list of menu items stands for a dividing line. If a name on the screen is different, or an item is missing or greyed out when the step expects it to work, write down exactly what you see.
- If a drag does not work for you, try twice. Then use the menu bar or panel buttons if the step offers them; otherwise set Needs the owner and write that you could not perform the drag (it may still work for a human).
- NEVER delete, move or rename the owner's files or the owner's own projects. Inside ClipForge only delete things this test made. Save every export into a folder named clipforge-test-output next to the test videos, with the file name the step gives (for example r6-full.mp4).
- Do NOT press Connect or Disconnect (Connect to Claude page) or Update (if a newer version is offered) without asking the owner first. Never press Disconnect in this round.
- Speech to text needs a speech program on the computer and usually a language pack (Small about 140 MB, Medium about 470 MB, Large about 1.6 GB). Do not install programs. Click Download only for the pack the owner agreed to, and NEVER download a Large pack.
- If the app closes by itself or freezes, write down exactly what you were doing, fill in the Crash box, reopen it and continue.
- Do not guess. Only mark PASS for what you actually saw, or for what the owner told you they heard or saw.
- This page keeps your answers in this browser as you go. When finished, fill in the Summary box (most important problems first), then click "Download filled checklist" and give the downloaded file to the owner."""

# ---------------------------------------------------------------- round 6, phone (1.15.0)
# The Android phone for 1.15.0 (build 130), updated in the app, driven by an
# AI agent on the Windows PC through "Link to Windows" screen mirroring.
# Taps only where possible. Names are the phone UI's own: the bottom bar
# and its sheets (lib/ui/editor/tools.dart, action_sheets.dart), the project
# menu (editor_screen.dart), Settings (settings_screen.dart), suggestions
# (suggestions.dart), the Text page (text_panel.dart), shorts
# (shorts_actions.dart), Export (export_dialog.dart).
STEPS_6P = [
 ("After the update", [
  ("p-version", "The app shows 1.15.0, build 130",
   "Open ClipForge on the phone. Read the small grey line at the bottom of the project list. Tap the three dots (More) at the top right, tap About ClipForge, then Copy version info. Type or paste the version line into \"Version shown in the app\" at the top of this page. Close About.",
   "Both show version 1.15.0 and build 130, the same as named at the top of this page. No red warning appears under the version box. The three dots list: Settings, What's new, Check for updates, About ClipForge, Copy version info.", ""),
  ("p-updated", "The result of the in-app update",
   "Look at the top of the project list. If a line \"Updated to 1.15.0\" is there, tap What's new, go back, then tap the cross of the line. (It appears once. If the owner already closed it, ask the owner what it said and set Not tested with the answer.)",
   "One quiet line \"Updated to 1.15.0\" with What's new and a cross. What's new opens Help on the page that starts with 1.15.0. No message says that an update did not work.", ""),
  ("p-moved", "The \"What moved\" note",
   "If a window \"Things are easier to find now\" opened at the first start, read it and tap OK. (It appears once. If the owner already closed it, set Not tested and write \"owner saw it: yes / no\".)",
   "It says nothing was removed, and lists the phone's new places: Add (one button at the bottom lists everything you can add), Text (its own button at the bottom), Shape, fades, notes, History (the three dots at the top of a project), Settings (one page), Sound waves and smooth preview (Settings > Editing), More (now grouped: Clip, Sound, Text), Hold a clip, sound or title (a list of what you can do with it), Trim start / end to here (More, under Clip). Buttons: What's new, Show me Settings, OK. The text fits the screen.", ""),
  ("p-keeps", "The update kept the projects",
   "Read the project list. Open the newest project from before the update, tap Play for 5 seconds, tap the back arrow.",
   "The projects from before the update are listed; the one you opened shows its clips with pictures and plays. No clip says Missing.", ""),
 ]),
 ("The bottom bar and Add", [
  ("p-new", "New project",
   "Tap New project. In the phone's picker choose video A (a talking video filmed wide) and confirm. When the editor opens, tap the name at the top and rename the project to Round 6 phone.",
   "The editor opens with A on the timeline with clip pictures. The top shows the back arrow, the name, the save sign, Undo, Redo, Export and three dots.", ""),
  ("p-bar", "The bottom bar: Add, Text, Split, More",
   "Tap an empty place on the timeline so nothing is selected. Read the bar at the bottom. Do NOT tap Text yet (a suggestion depends on it). Move the playhead to the middle of A and tap Split, then tap the Undo arrow.",
   "With nothing selected the bar has exactly four buttons: Add, Text, Split, More. Split cuts A into two pieces at the playhead; Undo makes it one again.", ""),
  ("p-add", "The Add sheet: every entry",
   "Tap Add. Read the list. Tap Videos or photos and add video B. Tap Add > Title, type Round 6 and close the sheet. Move the playhead to 0:02, tap Add > Caption, type: Sam Taylor: Hello from the phone. and tap Add. Add two more captions the same way at 0:06 (\"Alex K: Hello back.\") and at 0:10 (\"Alex K: Let us test the search.\"). Tap Add > Voice recording and cancel the picker. Tap Add > Overlay (picture-in-picture) and cancel the picker.",
   "A sheet \"Add\" lists, each with an icon and one line of explanation: Videos or photos, Music or sound, Voice recording, Title, Caption, Overlay (picture-in-picture), Good moment marker; at the bottom one sentence says where videos and photos go in. B lands after A. The title and the three captions appear on the timeline and in the preview. Voice recording and Overlay open the phone's picker; cancelling adds nothing.", ""),
  ("p-more", "More with nothing selected",
   "Tap an empty place, then tap More. Read the sheet from top to bottom (scroll it) and close it by swiping it down.",
   "A sheet \"More\" with small headings. CLIP: Trim start to here, Trim end to here, Freeze frame, Remove silences, Good moment marker, Make a short from here, Shorts and good moments. SOUND: Add sound track, Lower music under speech, Copy music credits. TEXT: Text, Find in the text, Subtitle file (.srt), Export subtitles (.srt). EDIT: History. A line that cannot be used now is grey and says why underneath, starting with \"Not now:\" (for example \"Not now: add music first\"). Nothing about Transcribe speech or Captions from speech is listed.", ""),
  ("p-plus", "The + next to Play when something is selected",
   "Tap clip A. Tap the + next to the Play button. Read the sheet and close it. Tap Done in the bottom bar.",
   "With a clip selected the bottom bar shows that clip's tools (no Add button), and the + next to Play opens the same Add sheet. Its last line now says that videos and photos go in after the selected clip. Done clears the selection and the bar shows Add, Text, Split, More again.", ""),
 ]),
 ("Something selected", [
  ("p-clip", "A clip: its tools, and More grouped by Clip / Edit / Sound / Text",
   "Tap clip A. Read the bottom bar. Tap More and read the sheet. Tap Duplicate in it, then Undo.",
   "Bar: Done, Split, Speed, Look, Sound, More, Delete. More: CLIP: Crop and position, Trim start to here, Trim end to here, Freeze frame, Remove silences, Move earlier, Move later, Make a short from here, Transition and fades. EDIT: Duplicate, Copy settings, Paste settings, History. SOUND: Separate sound, Put sound back, Lower music under speech. TEXT: Text. Grey lines say \"Not now: …\" (Paste settings: \"Not now: copy settings first\"; Move earlier on the first clip: \"Not now: it is already the first clip\"). Duplicate adds a copy after A; Undo removes it.", ""),
  ("p-trim", "Trim start to here, Trim end to here",
   "Tap clip A, move the playhead about 3 seconds into it, tap More > Trim start to here. Move the playhead to about 3 seconds before the end of A, tap More > Trim end to here. Tap Undo twice.",
   "Trim start to here makes A start at the playhead (the part before it is gone); Trim end to here makes it end at the playhead. The clips after it move up. Each Undo restores one.", ""),
  ("p-hold", "Hold: the action list; hold and drag: move",
   "Long-press clip B without moving (hold about a second, then let go). Read the list and close it. Long-press the title on the timeline, read, close. Long-press an empty part of the timeline, read, close. Then long-press clip B and, still holding, drag it in front of A; let go. Tap Undo. (Through mirroring a long-press or drag may fail: try twice. If the list never opens or the clip never moves, set Needs the owner and ask the owner to try with a finger.)",
   "Holding without moving opens a sheet titled Video clip with: Split, Trim start to here, Trim end to here, Duplicate, Copy settings, Paste settings, Freeze frame, Remove silences, Crop and position, Rotate right, Separate sound, Put sound back, Move earlier, Move later, Make a short from here, Delete. The title's sheet (\"Title\") has Edit, Duplicate, Text, Delete. An empty place (\"At 0:…\") has Videos or photos, Music or sound, Voice recording, Title, Caption, Overlay (picture-in-picture), Good moment marker, Split, Make a short from here. Holding and dragging still moves the clip to a new place.", ""),
  ("p-title", "A title or caption selected",
   "Tap the title on the timeline. Read the bar. Tap More, read, close. Tap Edit, change the text to Round 6 phone, close the sheet. Tap Done.",
   "Bar: Done, Edit, Duplicate, More, Delete. More: TEXT: Text, Find in the text, Export subtitles (.srt). EDIT: Duplicate, History. Edit opens the title's settings as a sheet; the new text shows in the preview.", ""),
 ]),
 ("The menu at the top", [
  ("p-top", "The three dots at the top of a project",
   "Tap the three dots at the top right of the editor. Read the list. Tap History, read, close it.",
   "The list has: Shape and size, Fade in and out, Publishing notes, Text, History, Markers, Settings, and Help, each with an icon. History opens a sheet with your changes by name, newest first.", ""),
  ("p-shape", "Shape and size",
   "Tap the three dots > Shape and size. Read the sheet. Tap 1080p (Full HD). Tap \"Which shape should I use?\" and go back from Help. Do not change the shape yet.",
   "A sheet \"Shape and size\" with SHAPE: Original (as the first clip), 9:16 upright, 16:9 wide, 1:1 square, 4:5 upright; VIDEO SIZE: Same as the first clip, 720p, 1080p (Full HD), 4K; a tick marks the current ones and moves to 1080p (Full HD). The question opens the help article about shapes.", ""),
  ("p-fades", "Fade in and out",
   "Tap the three dots > Fade in and out. Set Fade in from black and Fade out to black to about 2 s each. Close the sheet. Play the first 3 seconds.",
   "A sheet \"Fade in and out\" with the two settings. The video comes up from black at the start. Ask the owner to watch the phone.", "watch"),
 ]),
 ("Settings on the phone", [
  ("p-settings", "The Settings page",
   "Tap the three dots > Settings. Read the page from top to bottom. Go back. Then go to the project list, tap its three dots > Settings, and go back.",
   "A page \"Settings\" with: Editing (Snap to playhead and edges, Show sound waves, Smooth preview), Export (Use graphics card (faster)), Suggestions (Show suggestions; the button \"Show hidden suggestions again (none hidden)\"), Updates (Check for updates automatically, Check now, the version line), About (About ClipForge, Copy version info, What's new, Licences). There is NO part \"Text window\" and NO part \"Claude\" on the phone. Both ways open the same page.", ""),
  ("p-set-switches", "Sound waves, snapping and smooth preview change the app and are remembered",
   "Open the project. Look at clip A's bottom edge (a slim sound wave). Open Settings, switch Show sound waves OFF, Snap to playhead and edges OFF and Smooth preview OFF. Go back and look at the timeline. Close ClipForge completely (recent apps, swipe it away), open it again, open the project and Settings. Then switch all three ON again.",
   "With Show sound waves off the wave on the clip is gone at once. After closing and reopening the app all three switches are still off. After switching them on the wave returns (\"Drawing sound…\" may show briefly). Ask the owner, with a finger on the phone, whether dragging the end of the title jumps onto the playhead with snapping on and not with it off (otherwise set Partial for snapping).", ""),
  ("p-set-updates", "Check now",
   "In Settings tap Check now. Switch Check for updates automatically off and on again. Do NOT tap Update if a newer version is offered: tell the owner.",
   "A message at the bottom: \"You have the newest version (1.15.0 (build 130)).\" (If a newer version is offered, write the version down and set Partial.) The switch moves and stays as set.", ""),
 ]),
 ("Suggestions (the line above the bottom bar)", [
  ("p-sg-shape", "Another shape: the line, \"Don't show again\", Settings brings it back, Fill",
   "Tap the three dots > Shape and size > 9:16 upright and close the sheet. Wait a second without playing. Read the thin line just above the bottom bar. Tap the three dots ON THAT LINE and tap Don't show again. Open Settings (three dots at the top), read the button under Show suggestions, tap it, go back and wait a second. When the line is back, tap Fill.",
   "The line says \"A clip has another shape than the video, so it gets bars.\" with the buttons Fill, Blur and Crop… on a second row, three dots and a cross. Don't show again makes it go. In Settings the button reads \"Show hidden suggestions again (1)\"; tapping it says \"One suggestion can show again.\" and the line returns in the project. Fill makes that clip fill the upright frame (no bars), and the line goes.", ""),
  ("p-sg-music", "Music longer than the video: Fit to video; hidden while playing",
   "Move the playhead to 0:00. Tap Add > Music or sound. Use My files > Choose a music file… if the phone has a music file longer than the video; otherwise Find free music, search piano and tap Use on a track that is longer than the video. If it asks \"What is this sound?\", choose Music and tap Add. Wait a second and read the line. Tap Play, look where the line was, tap Pause. Then tap Fit to video.",
   "The line says \"The music is longer than the video.\" with Fit to video. While the video plays the line is not shown; it is back after Pause. Fit to video makes the music end with the video and says \"The music now ends with the video, with a 2-second fade-out.\"", ""),
  ("p-sg-swipe", "Swipe a suggestion away",
   "Wait a few seconds (until \"Drawing sound…\" is gone). Another line should appear, for example \"Music plays while someone is talking.\", \"A long clip has pauses in the talking.\" or \"Text shows every caption in one place, to read, search and fix.\" Write its text down. Swipe the line sideways off the screen (if the swipe fails twice through mirroring, tap its cross instead and say so). Go back to the project list and open the project again.",
   "The line slides away and does not come back in this project after reopening (a different one may appear; write that down too). Only one line is ever shown at a time.", ""),
 ]),
 ("The Text page", [
  ("p-text-open", "Text: read, search, tap to jump",
   "Tap an empty place, then tap Text in the bottom bar. Read the page. Tap the sentence \"Hello back.\" and look at the playhead when you return (close the page with its cross if it does not close by itself). Open Text again, tap into \"Find in the text…\" and type: hello. Then type: xyzzy.",
   "A full-screen page \"Text\" shows the captions as a readable page: \"Sam Taylor\" once above his line and \"Alex K\" once above the two lines that follow, each with a coloured bar and the time at the side. Tapping a sentence moves the playhead to it (0:06). The search marks and counts the places (\"1 of 2\"); xyzzy gives \"Not found\". Nothing on the page offers to transcribe speech.", ""),
  ("p-text-edit", "Edit a caption",
   "In Text tap the sentence \"Let us test the search.\" and tap Edit. Change it to \"Let us test the phone.\" and tap Save. Close Text and look at the preview at 0:10. Tap Undo, then Redo.",
   "Tapping a sentence shows a bar with Edit, Delete caption and Make a short from this…. Edit opens the caption's text (with the name \"Alex K:\" in front) in a box with Cancel and Save. After Save the page and the preview show the new words. Undo and Redo switch between the old and the new text.", ""),
  ("p-text-short", "A short from this line: 30, 45, 60 s",
   "Open Text, tap the first sentence and tap Make a short from this…. Read the window. Tap 30 s, 45 s and 60 s in turn, then 30 s. Leave the tick boxes as they are, name it Round 6 phone short and tap Make the short. Tap Stay here.",
   "A window \"Make a short\" with the choices The selection, 30 s, 45 s and 60 s; the line with the times changes with each choice. It says a new upright (9:16) project is made and this video is not changed, and has Start and end at a pause, Short caption look, Title at the top and \"Name of the new project\". Afterwards \"The short is ready\" with Stay here and Open it. (If the video is shorter than the chosen length, write down what it says.)", ""),
 ]),
 ("Markers and shorts", [
  ("p-marker", "Good moment markers",
   "Move the playhead to about one third of the video and tap Add > Good moment marker. Move it to about two thirds and tap More > Good moment marker. Then tap the three dots at the top > Markers.",
   "Each one puts a small flag on the time ruler and says \"Marked a good moment at …\" with Undo. Markers opens the list \"Good moments\" with both markers, each with \"Make a short around it\" and \"Remove the marker\", and the buttons Make shorts from markers… and Close.", ""),
  ("p-moments", "Shorts and good moments under More",
   "Close the list. Tap More > Shorts and good moments. Read the sheet.",
   "The line under More reads \"Shorts and good moments\" with \"2 markers\" under it. It opens a sheet \"Shorts\" with Good moment marker (M), Good moments (2)…, Make a short from here… and Make shorts from markers….", ""),
  ("p-shorts-markers", "Make shorts from markers",
   "Tap Make shorts from markers…. Read the question and tap Make them. When it is done tap OK. Go to the project list, read the names, open one of the new shorts, play 5 seconds and go back.",
   "The question \"Make 2 shorts from the markers?\" lists the two parts with times and lengths and has Short caption look, Cancel and Make them. Afterwards \"2 shorts are ready\" lists them, with OK. The project list has the new projects; a short is upright and plays; \"Round 6 phone\" is unchanged. Ask the owner to look at one short on the phone: captions bigger, in the lower middle, outlined.", "watch"),
 ]),
 ("Export, share, publishing notes", [
  ("p-notes", "Publishing notes",
   "Open \"Round 6 phone\". Tap the three dots > Publishing notes. Type a Title (Round 6 phone video) and a Description (one sentence). Tap the copy button next to Title. Tap Done.",
   "A full-screen page \"Publishing notes\" with Title, Description, Hashtags and Chapters, each with a copy button, Chapters from titles / captions…, \"A different title for Shorts, Reels and TikTok\", Copy title and description and Done. The keyboard does not hide the field being typed in.", ""),
  ("p-exp-dest", "Export for a destination",
   "Tap Export at the top. Read \"Where is it going?\" and tap each choice once. Then choose WhatsApp / Telegram and tap Export. Wait until it is done and read the finished screen (stay on it for the next step).",
   "Choices: YouTube, Shorts / Reels / TikTok, Instagram post, WhatsApp / Telegram, Podcast audio, Custom, each with one line of explanation. Because the project is upright now, YouTube asks \"Your video is 9:16; this needs 16:9.\" with Make a copy in this shape and Export as it is. WhatsApp / Telegram says \"A small file (720p) that is quick to send.\" The export runs to 100 %, then \"Video saved\" and \"Saved to …\" (the gallery). \"Keep ClipForge open while it exports.\" is shown while it runs.", ""),
  ("p-share", "Share, and Copy title and description",
   "On the finished screen tap Share. When Android's share sheet opens, look at it and close it WITHOUT choosing an app (back button). Then tap Copy title and description. Tap Done.",
   "Share opens Android's own share sheet with the video (choose nothing: nothing is sent). Back in ClipForge no error is shown. A note says that many apps ignore text shared with a video, which is why Copy title and description stays on screen; it copies the title and description from the notes (paste them into the note here if copying between phone and PC works, otherwise ask the owner to paste them into a notes app and read them).", ""),
  ("p-exp-several", "Export several into a gallery album",
   "Tap Export, then Export several…. Tick WhatsApp / Telegram and Podcast audio only. Read the line under the list. Tap Export 2 files and wait. If Android asks whether ClipForge may add to the gallery, allow it and write that down.",
   "Each tick shows its file name (\"Round 6 phone - WhatsApp.mp4\", \"Round 6 phone - audio.mp3\"). The line says \"2 files, about … together. The videos go to your gallery, in an album called \"Round 6 phone\".\" One progress bar (\"1 of 2: …\"), then \"Files saved\". The finished screen offers Share and Copy title and description.", ""),
  ("p-gallery", "The album in the gallery",
   "Open the phone's Gallery app and look for an album called Round 6 phone. Play the video in it for 10 seconds. Go back to ClipForge.",
   "The album exists and holds the WhatsApp video (the sound file and the text file stay in the app and go out through Share). Ask the owner to watch and listen on the phone: upright, the clip fills the frame, fade from black, captions readable, music heard, voice in sync.", "watch,listen"),
 ]),
 ("Files, rotation, what is not on a phone", [
  ("p-reopen", "Close and reopen: the media is still there",
   "Go to the project list. Close ClipForge completely (recent apps, swipe it away). Open the Gallery app, look at two photos, close it. Open ClipForge again and open \"Round 6 phone\". Play 5 seconds.",
   "Both clips are there with their pictures, the music is there, and everything plays. No clip is red or says Missing, and no \"File not found\" message appears.", ""),
  ("p-rotate", "The phone on its side",
   "Ask the owner to switch auto-rotate on and turn the phone on its side with the project open, then back upright. Look at the screen in both positions.",
   "Write down what happens. On a wide enough screen (a tablet, or a large phone on its side) the editor changes to the computer's layout: the settings panel at the side, a Shape button and \"?\" in the top bar, and no More sheet; otherwise it keeps the phone layout. In both cases nothing is lost: the project, the playhead and the selection are still there, and the app does not close.", ""),
  ("p-none", "Nothing about speech-to-text or Claude on the phone",
   "Look for the words Transcribe, Captions from speech, Remove filler words, Automatic cuts and Claude in: the three dots on the project list, the three dots in a project, Settings, the Add sheet, More (nothing selected and a clip selected) and the Text page.",
   "None of these places has an item about speech to text or about Claude. (Help may have articles marked \"computer only\": that is correct.) Write down any place where such an item shows up.", ""),
  ("p-final", "Everything was saved",
   "Open \"Round 6 phone\" once more and look through it: shape, fill, title, captions, fades, music, markers, publishing notes.",
   "Everything is as you left it: 9:16 upright, clip A filling the frame, the title \"Round 6 phone\", three captions (the last one edited), the fades, the music ending with the video, two flags on the ruler, and the title and description in Publishing notes.", ""),
 ]),
]

INSTR_6P = """You are testing ClipForge 1.15.0 (build 130), a video editor, on the owner's Android phone. The phone was updated from inside the app. You work on the owner's Windows PC and see and touch the phone through "Link to Windows" (the PC app is called Phone Link): the phone's screen is shown in a window on the PC. This checklist page is open in a browser on the PC. Problems are expected; your job is to find them and write them down precisely. "Send feedback" is not part of this round.

HOW TO DRIVE THE PHONE
- In the phone window a mouse click is a tap, holding the mouse button down for a second is a long-press, and click-and-drag is a drag or a swipe. There are no keyboard shortcuts and no menu bar on the phone: use only what is on the phone's screen. This round is written for taps; the few drags are marked.
- If the phone screen is not shown, ask the owner to open Phone Link on the PC and choose the phone's screen, and to unlock the phone. If the mirrored screen goes black or locks, ask the owner to unlock it.
- Drags, swipes and long-presses often fail through mirroring. Try twice. If it still fails, use the button the step offers instead; otherwise set "Needs the owner", write that it could not be performed through mirroring (it may work fine with a finger), and ask the owner to try it with a finger if they are there.
- Typing: tap into the text box on the phone and type on the PC keyboard.
- SOUND: the phone's sound may not reach you through mirroring. Never judge sound yourself. For every step tagged "ask the owner to listen", do the actions, then ask the owner in the chat. The same goes for smoothness: mirroring stutters by itself, so for steps tagged "ask the owner to watch" ask the owner to look at the phone itself. Write the answer in the note starting with "Owner:" and set PASS or FAIL from it. If the owner is not available, set "Needs the owner".

HOW THE PHONE APP IS LAID OUT IN 1.15 (names as on the screen)
- Project list: New project and Open project file; ? (Help) and three dots (Settings, What's new, Check for updates, About ClipForge, Copy version info) at the top; each project card has three dots: Rename, Duplicate, Share project file, Delete.
- Editor, top: back arrow, the project's name, the save sign, Undo, Redo, Export and three dots (Shape and size, Fade in and out, Publishing notes, Text, History, Markers, Settings, Help).
- Bottom bar with nothing selected: Add, Text, Split, More. Add opens one list of everything that can be added. More lists the rest under the headings Clip, Sound, Text, Edit.
- With something selected the bar shows that item's tools and More; Done clears the selection. A + next to Play opens the Add list while something is selected.
- A thin line with a tip and a button may appear just above the bottom bar: a suggestion. Outside the group "Suggestions" leave it alone.
- Sheets open from the bottom; swipe them down or tap outside to close them.

BEFORE YOU START
- Fill in "Device" (for example "Samsung Galaxy S23, Android 15, via Link to Windows") and "Tester".
- Fill in "Version shown in the app": project list > three dots > About ClipForge > Copy version info, then type or paste the line. If it does not match the build named at the top of this page (a red warning appears), tell the owner and say so in the Summary.
- Test files on the phone (ask the owner which ones to use): A. a talking video filmed wide (landscape), 1-3 minutes; B. a second short video; optional: a music file longer than video A (otherwise the app's own Find free music is used, which needs internet). Do not download files in any other way.
- Do the steps in order: later steps build on the project "Round 6 phone". Do NOT tap Text before the group "Suggestions" is finished.

RULES
- Each step has "Do" (exact actions) and "Expected" (what should happen). Do the actions exactly, then compare with Expected.
- For each step choose a Result and write a Note. Result meanings: PASS = you saw exactly the expected result (or the owner confirmed it). FAIL = something was wrong (write what you did, what happened, and what you expected). Partial = part of it worked (say which part). Not tested = you could not do it (say why). Needs the owner = only a person can judge or perform it and the owner was not available.
- NEVER delete, move or rename the owner's photos, videos or music, in ClipForge's pickers, in the Gallery or in any other app. Do not uninstall ClipForge (that deletes the projects). Inside ClipForge only delete things this test made. Do not send or share anything to other people or apps: when a share sheet opens, choose nothing and go back.
- Do not tap Update if a newer version is offered: tell the owner.
- Exported videos go to the phone's gallery; leave them there for the owner.
- If an Android permission dialog appears (photos and videos, music, notifications), allow it and write down that it appeared.
- If the app closes by itself or freezes, write down exactly what you were doing, fill in the Crash box, reopen it and continue.
- Do not guess. Only mark PASS for what you actually saw, or for what the owner told you they heard or saw.
- This page keeps your answers in this browser as you go. When finished, fill in the Summary box (most important problems first; also what was hard to do through mirroring), then click "Download filled checklist" and give the downloaded file to the owner."""

# ---------------------------------------------------------------- round 7 (1.17.0)
# The Windows computer round for 1.17.0 (build 136): EVERY feature, before
# any 1.18 work, ordered so that the new and risky things come first:
# (A) the in-app update, (B) the long-file freeze (a 20-30 minute video,
# alone and with two voice files; the performance log), (C-I) everything
# 1.17 changed (select a part, rows, the part's actions, Only when
# speaking, shorts from markers, "Use a model file I have", shortcuts after
# a click in each panel, Put back restores captions, Send feedback with
# "Include details about how ClipForge ran", the smaller things), then
# (J-X) every remaining area of docs/FEATURES.md. The filled Round 6 pages
# are not in the repository, so "failed / partial / not tested in Round 6"
# is covered through what docs/HANDOVER.md records of that test (the
# stall, shorts from markers, the model file, shortcuts, Put back, the
# seven smaller findings) and the Speech group, which Round 6 skipped.
# Labels are the app's own: test/ui/menu_tree_snapshot.txt, CHANGELOG.md
# 1.17.0, lib/ui/editor/part_actions.dart, add_from_path.dart,
# shorts_actions.dart, speech_actions.dart, timeline_view.dart,
# lib/ui/feedback/feedback_screen.dart, lib/ui/update/update_ui.dart,
# lib/ui/help/what_moved.dart, and the steps of rounds 4, 5 and 6.
# Steps: (id, title, do, expected, tag) as in rounds 4 to 6.
STEPS_7 = [
 ("A. Update and start", [
  ("up-before", "Before the update: which version is on this PC",
   "Start ClipForge from the Windows Start menu. Read the small grey line at the bottom of the project list and write it down. Look at the top of the project list for a line \"Version 1.17.0 is available\". If no such line is there and the app is older than 1.17.0, choose Help > Check for updates… once and look again. Do NOT click Update yet.",
   "On a PC that still has 1.15 or 1.16: a quiet line \"Version 1.17.0 is available\" with What's new, Update, Later and Skip this version. If the app already shows 1.17.0 (build 136), set Not tested for this step and the next one and write how it got there (ask the owner: in-app update or the installer).", ""),
  ("up-run", "The in-app update to 1.17.0",
   "Ask the owner: \"May I press Update now?\" After a yes click Update, read the window, and click Download and update. Wait. When the button Restart ClipForge to finish appears, click it. Do nothing while ClipForge closes and opens again (up to a minute). Write down how long each part took.",
   "A window \"Update to version 1.17.0\" says that ClipForge downloads the new version, checks it, then closes and opens again as the new version, and that the projects stay as they are. It shows \"Downloading… …%\", then \"Checking the download…\", then that the version is downloaded and checked with the buttons Restart ClipForge to finish and Later. After the restart ClipForge opens by itself as 1.17.0. If instead it says \"The update did not work.\": click Copy details, paste them into the note, set FAIL, and ask the owner to install 1.17.0 with ClipForge-Setup.exe so that the round can go on.", ""),
  ("st-version", "The app shows 1.17.0, build 136",
   "Read the grey line at the bottom of the project list. Open Help > About ClipForge, read it, click Copy version info and paste it into \"Version shown in the app\" at the top of this page. Close About.",
   "The grey line and About both show version 1.17.0 and build 136, the same as named at the top of this page. No red warning appears under the version box. The pasted text has the version line, the system, a line starting with \"Folder:\" (it ends in AppData\\Local\\Programs\\ClipForge, not in a name ending in \".update-new\"), the update log's last lines when an in-app update ran, and a part \"Performance log (longest gap … ms):\".", ""),
  ("st-notes", "\"Updated to 1.17.0\" and \"Two keys changed\"",
   "Look at the top of the project list right after the first start of 1.17.0. If a line \"Updated to 1.17.0\" is there, click What's new, close Help, then close the line with its cross. Open any project: if a window \"Two keys changed\" opens, read it and close it. (Both appear once. If the owner already closed them, set Not tested and write \"owner saw it: yes / no\".)",
   "One quiet line \"Updated to 1.17.0\" with What's new and a cross; What's new opens Help on the page that starts with 1.17.0. The note \"Two keys changed\" says that I and O now mark the start and the end of a selected part of the timeline, and that making the clip start or end at the playhead is Q and W now (both still in the Clip menu). Neither comes back at the next start. No message says that an update did not work.", ""),
  ("st-projects", "Earlier projects are still there",
   "Read the project list. Open one project from an earlier round, play 5 seconds, and go back with File > Back to projects.",
   "Projects from earlier rounds are listed, the one you opened shows its clips with pictures and plays, and no clip says Missing.", ""),
 ]),
 ("B. The long file (the freeze reported on this PC)", [
  ("lf-import", "Import the long video alone",
   "On the project list click New project. Choose Add > Add from a folder path…, paste the full path of file L (the 20-30 minute video; see the instructions), click the button that looks the path up, and add it. (If that does not work, use Add > Videos or photos… and say so.) Start counting seconds when you confirm. Watch the top bar (Saving… / Saved), the preview and the top right of the timeline for two minutes. Choose File > Rename project… and call it \"Round 7 long\".",
   "The clip is on the timeline within a few seconds with the right length (write the length down). The preview says \"Loading the video…\" until the first picture is there (not plain black without a word). The top bar goes from Saving… to Saved within about 5 seconds (write down how many). \"Drawing sound… 1 of 1\" (or \"Drawing sound…\") with a small cross shows at the top right of the timeline and goes away when the sound waves are drawn; write down how long that took. FAIL if Saving… stays for more than 30 seconds, if the window stops answering, or if the line \"Sound waves were paused to keep ClipForge responsive\" appears: then do the step \"The performance log\" below at once.", ""),
  ("lf-responsive", "The app answers while the sound waves are drawn",
   "Do this while \"Drawing sound…\" is still shown if you can (otherwise right after). Press + three times and - three times. Scroll the timeline to the end and back. Click the time ruler at about 10:00 and at about 20:00. Press Space, wait 5 seconds, press Space. Press F1 and close Help. Choose File > Back to projects, then open \"Round 7 long\" again.",
   "Every action answers within about a second: the timeline zooms and scrolls, the playhead jumps and the preview shows the picture of that place, the video plays with sound, Help opens and closes, the project closes and opens. While the video plays no new sound wave is started (the counter does not move). Write down anything that took longer than 2 seconds, with what was on screen.", ""),
  ("lf-restart", "A restart keeps the import",
   "Wait until the top bar says Saved. Choose File > Exit. Start ClipForge again and open \"Round 7 long\". Play 10 seconds at the start, in the middle and one minute before the end.",
   "The project is in the list with the right length and opens with the long clip in it (it was not lost). It plays at all three places. Ask the owner to watch one of them: picture and voice in sync.", "watch,listen"),
  ("lf-voices", "Add the two voice files to the long video",
   "Needs the two voice files of L (LV1 and LV2; otherwise set Not tested for this step and the next and say so). In \"Round 7 long\" choose Add > Voice recording… and pick both files together (or use Add > Add from a folder path… and answer \"What are these sounds?\" with Voice for the video). Type a speaker's name for each (Sam Taylor, Alex K), leave \"Mute the camera's own sound\" on and click Add and line up. Count the seconds until the message. Then watch the top bar and \"Drawing sound… 1 of 3\" for three minutes, and during that time press + and -, scroll, click the ruler at 12:00 and press Space twice.",
   "\"Lining up the voice with the video…\" and then a message that the voices are lined up with the video, each on its own track, and follow the picture when you cut (copy it). Two voice rows named after the speakers. The top bar reaches Saved within about 5 seconds after the message. \"Drawing sound… 1 of 3\" counts up and goes away; zoom, scroll, the ruler and Space answer within about a second the whole time. FAIL as in the first step of this group if Saving… stays, the window stops answering, or \"Sound waves were paused…\" appears (then click nothing else and do the step \"The performance log\" now).", ""),
  ("lf-voices-restart", "Restart with the voices; who is speaking",
   "Wait for Saved. Choose File > Exit, start ClipForge again and open \"Round 7 long\". Wait until \"Drawing sound…\" is gone (it should be quick now). Zoom so that about a minute fills the window and look at the two voice rows. Play 15 seconds where the two people take turns.",
   "Both voices are still there, on their tracks, in sync. Every voice row has sound waves: bright in the speaker's colour where that person talks, dim in the pauses, each speaker in a different colour. Ask the owner to watch and listen: lips match the voice, no second echoing voice, and the bright stretches match who is talking.", "watch,listen"),
  ("lf-stop", "The cross stops the drawing; \"Sound waves were paused…\"",
   "Open Settings (Ctrl+comma), switch Show sound waves OFF and ON again, close Settings and look at the top right of the timeline. If \"Drawing sound…\" shows, click the small cross next to it. If at any time in this round the line \"Sound waves were paused to keep ClipForge responsive\" is shown, click Turn back on once and write down when it appeared.",
   "The cross stops the drawing at once: the counter goes away and the rows that were not drawn yet stay plain; nothing else changes. (The pictures of files drawn earlier are kept, so there may be nothing to stop: then set Partial and say so.) \"Sound waves were paused…\" should NOT appear on its own; if it did, that is a finding (not a crash): Turn back on starts the drawing again, and the setting Show sound waves stayed on.", ""),
  ("lf-waves-off", "The same import with Show sound waves off",
   "Open Settings and switch Show sound waves OFF. Go to the project list, make a new project \"Round 7 long 2\", add file L as before and, if you have them, the two voice files as before. Watch Saving… / Saved, zoom, scroll, click the ruler, press Space twice. Exit, start again, open the project. Then switch Show sound waves ON again in Settings.",
   "With the switch off no \"Drawing sound…\" appears and the rows are plain blocks. The import is saved within about 5 seconds, the app answers within about a second, and after the restart the clip and the voices are there. Write down every difference to the run with sound waves on (faster, the same, slower). If it stalls HERE too, say so clearly in the Summary: then the sound waves are not the cause.", ""),
  ("lf-silences", "Remove silences on the long clip",
   "Open \"Round 7 long\". Click the long clip and choose Clip > Remove silences…. Count the seconds of the scan; while it runs move the window and look for a Cancel button. When the result shows, write down the line about the background noise and the number of gaps. Click the button that removes them. Then press Ctrl+Z once.",
   "A progress bar with Cancel; the window can be moved while it scans and the bar moves (at most about four times a second). Then a line like \"Background noise about -45 dB; quieter than -34 dB counts as silence\" and a button like \"Remove … gaps\". After removing, the clip is many pieces, the voices are cut with it, and the app still answers; one Ctrl+Z brings back the single clip. Write down the scan time, the number of gaps and how long the cutting and the undo took.", ""),
  ("lf-perf", "The performance log (do this at every stall too)",
   "Choose Help > Copy version info and paste ALL of it into the note of this step. If ClipForge stalled or was closed by force earlier in this round, do the same right after the next start and paste that text too, marked \"after the stall at step …\".",
   "The text ends with a part \"Performance log (longest gap … ms):\" and lines of the form \"HH:MM:SS.mmm +ms what\" (project opened, probe start / end, save start / end, sound picture … start / end, gap … ms). After a run that ended while the app did not answer there is also a part \"Previous run (ended while not responding):\". There are no file names and no project names in it. Write the \"longest gap\" number into the Summary.", ""),
 ]),
 ("C. Select a part of the timeline (new in 1.17)", [
  ("pt-project", "Make the test project",
   "New project. Choose Add > Add from a folder path…, paste the MEDIA FOLDER path, look it up, tick files A, B and P and add them. Put the playhead at 0:00, choose Add > Music or sound…, My files > Choose a music file… and pick M; when it asks \"What is this sound?\" leave Music and click Add. Put the playhead at 0:03, choose Add > Title and type: Round 7. Add four captions with Add > Caption… (move the playhead first): at 0:02 \"Sam Taylor: Welcome to the test.\"; at 0:06 \"This line has no name.\"; at 0:10 \"Alex K: Thanks, happy to be here.\"; at 0:14 \"Alex K: Let us test the search.\" Choose File > Rename project… and call it \"Round 7 test\".",
   "The window \"Add from a folder path\" lists the media files of the folder with tick boxes and a button like \"Add 3 files\". The editor shows A, B and the photo P on the main track with clip pictures, the music on a Music track from 0:00, the title and four captions. The top bar shows Saved.", ""),
  ("pt-strip", "Drag along the strip under the ruler",
   "Look directly under the time ruler: a thin strip says \"Drag here to select a part\". Drag along it from about 0:05 to about 0:12. Read what appears. Drag the right handle of the part to about 0:15 and the left one to about 0:04, slowly, near the end of a caption or the playhead. Click the time ruler at 0:20. Press Esc. (If the drag fails twice, use the next step's keys and set Partial.)",
   "A part of the timeline is highlighted across every row with its length, with a handle on each edge. A bar next to the timeline shows the start, the end and the length and the actions (Cut out, Silence, Lower volume…, Speed… and more), and every row gets a tick box at its name, all ticked. The handles snap to cuts, to where speech starts and stops, to markers and to the playhead. A click on the ruler still only moves the playhead (the part stays). Esc clears the part: band, bar and tick boxes are gone. Nothing of this is a History step.", ""),
  ("pt-io", "I and O, Shift+click, Shift+drag",
   "Put the playhead at 0:06 and press I. Put it at 0:12 and press O. Hold Shift and click the ruler at 0:18. Press Esc. Hold Shift and drag on the ruler itself from 0:08 to 0:11. Press Esc. With no part: put the playhead at 0:10 and press I, look, press Esc; press O, look, press Esc. Then press Space, and while it plays press I and two seconds later O; press Space.",
   "I sets the start of the part at the playhead, O its end (0:06 to 0:12). Shift+click stretches the part to that place. Shift+drag on the ruler selects a part; without Shift the ruler moves the playhead. With no part, I gives \"from the playhead to the end\" and O \"from the start to the playhead\". I and O also work while the video plays. Part > Part starts at playhead (I) and Part ends at playhead (O) do the same.", ""),
  ("pt-qw", "Q and W trim the clip (what I and O did before)",
   "Press Esc. Click clip A, put the playhead about 2 seconds into it and press Q; put it 2 seconds before the end of A and press W. Open the Clip menu and read the two items. Press Ctrl+Z twice.",
   "Q makes A start at the playhead, W makes it end there; each is one History step (\"Start of clip 1 at playhead\", \"End of clip 1 at playhead\") and each undo restores one. The Clip menu shows Start at playhead (Q) and End at playhead (W). I and O did NOT trim the clip.", ""),
  ("pt-quick", "Quick ways to select",
   "Double-click clip B. Press Esc. Double-click the music; Esc. Double-click the title; Esc. Put the playhead at 0:08 and choose Part > Select from the start to the playhead; then Part > Select from the playhead to the end; then Part > Clear the selected part. Put the playhead in a pause of the talking in A (wait until \"Drawing sound…\" is gone) and choose Part > Select the pause here; Esc. Read Part > Select between the markers here (no markers yet).",
   "A double-click selects exactly the time of that clip, sound or title. From the start to the playhead and From the playhead to the end select those stretches; Clear the selected part removes it. Select the pause here selects the pause around the playhead; where someone is talking it says so instead (\"The playhead is not in a pause: someone is talking …\"). Without markers the item is grey with its reason: \"Select between the markers here (no good moment markers yet)\". A single click on a clip still only selects the clip, without delay.", ""),
  ("pt-menu", "The Part menu and the right-click menu inside a part",
   "Select a part from 0:05 to 0:12 (I and O). Open the Part menu and compare with Expected. Then right-click INSIDE the highlighted part on the timeline, read the menu and press Esc.",
   "Part: Select a part, Part starts at playhead (I), Part ends at playhead (O), Select this clip's time, Select this speaker's turn, Select the pause here, Select between the markers here, Select from the start to the playhead, Select from the playhead to the end, Clear the selected part | Cut out, Delete and leave a gap, Silence, Lower volume…, Speed…, Clean up sound here | Make a short from the part…, Duplicate the part, Title over the part, Good moment marker at its start. A right-click inside the part offers the part's actions. Items that cannot be used are grey with the reason in brackets (for example \"… (no part is selected)\" when there is none). Write down every difference.", ""),
  ("pt-rows", "Rows: tick boxes, Alt+click, and why Cut out needs every row",
   "With the part selected, untick the tick box of the Music row. Read the bar (\"Rows: …\"). Move the pointer over Cut out in the bar and read what it says; click it. Then hold Alt and click the tick box of the Video row. Read the bar. Tick every row again (the bar has a way to choose everything).",
   "Every row has a tick box while a part is selected (the video, each sound track, titles and captions, the overlay row when there is one). The bar says which rows the actions apply to (\"Rows: everything\", \"Rows: 3 of 4\", or \"Only Video\" after Alt+click). With a row unticked, Cut out is refused with one line why (it removes time, so it needs every row: with only some, lips and voice would no longer match) and points to Silence and Delete and leave a gap; nothing is changed. While the pointer is on an action, the row names show which rows it cannot change.", ""),
  ("pt-cut", "Cut out",
   "Write down the length of the video. Select a part from 0:20 to 0:24 with every row ticked (a place with NO caption). Click Cut out. Read the message. Play across the place. Open History (Ctrl+Shift+H) and close it. Choose Text and speech > Automatic cuts… and read it; close it without putting anything back.",
   "A message like \"Cut 4.0 s out of everything. To put it back later: Automatic cuts, or Undo now.\" The video is 4 seconds shorter, everything after the part moved up on EVERY row (clips, music, title, captions), and the music has no hole. History has one step for it. The window \"Automatic cuts\" lists this cut with Put back. Ask the owner to listen across the cut: no click.", "listen"),
  ("pt-putback", "Put back brings the captions back (fixed in 1.17)",
   "Select a part that covers the whole caption \"Thanks, happy to be here.\" (for example 0:09 to 0:14), every row ticked, and click Cut out. Check that the caption is gone from the timeline. Choose Text and speech > Automatic cuts… and click Put back on the row of THAT cut; close the window. Then open the Text window (Ctrl+Shift+T), click the caption \"Let us test the search.\", click Cut this part out of the video…, click Cut it out, and again use Automatic cuts… > Put back for it.",
   "After Cut out the caption on that part is gone and the video is shorter. After Put back the video has its old length, the clip is one piece again there AND the caption \"Thanks, happy to be here.\" is back at its old time with its text. The same for the part cut out in the Text window: Put back returns the picture, the sound and the caption. (In 1.15 the caption stayed gone: that was the Round 6 finding.) A caption that was only shortened by a cut is not made longer again: that is expected.", ""),
  ("pt-gap", "Delete and leave a gap",
   "Select a part from 0:05 to 0:08. Hold Alt and click the tick box of the Music row. Click Delete and leave a gap. Look at the music. Press Ctrl+Z. Now Alt+click the tick box of the Video row and click Delete and leave a gap (or read why it is grey).",
   "On the music row the part is removed and a gap is left: the music before and after it stays exactly where it was, and nothing else moved; a message like \"Deleted that part on Music. Nothing moved.\" Undo brings it back. For the Video row it is refused with the reason (the main track cannot have gaps); it points to Cut out or Silence.", ""),
  ("pt-silence", "Silence on one row",
   "Select a part of about 2 seconds in which someone talks in clip A. Alt+click the tick box of the Video row. Click Silence. Read the message. Look at the slim sound wave along the bottom of clip A. Play from 2 seconds before the part to 2 seconds after it. Click clip A and look in the side panel for \"Quiet parts\".",
   "A message like \"Silenced 2.0 s on Video.\" Nothing moves and the length stays. The sound wave of the clip is flat (with a dark band) on that part. On play the clip's own sound is silent there while the music plays on; the sound goes down and comes back over a blink, without a click. The clip's settings list the part under Quiet parts (from – to, silent) with Remove. Ask the owner to listen.", "listen"),
  ("pt-lower", "Lower volume…",
   "Select another part of about 3 seconds. Alt+click the tick box of the Music row. Click Lower volume…. Read the window, choose 12 dB and confirm. Play across it. Click the music and look at its Quiet parts. Then select the same part again, open Lower volume… and move the slider instead; cancel.",
   "A window \"Lower volume\" with 6, 12 and 18 dB and a slider, and a line saying how long a stretch gets quieter on which rows, with short fades so nothing clicks. Afterwards a message like \"Lowered 3.0 s by 12 dB on Music.\" The music's wave is lower on that part; the music is clearly quieter there and the voice is not. The music's settings list it under Quiet parts with its level. Ask the owner to listen.", "listen"),
  ("pt-follow", "A quiet part stays on the same words; Remove",
   "Note the words that are silenced in clip A (from the step \"Silence on one row\"). Click clip A, put the playhead 1 second into it and press Q (the clip starts 1 second later). Play across the silenced words. Press Ctrl+Z. Then, in clip A's Quiet parts list, click Remove on that part and play again. Press Ctrl+Z so that the silence is back.",
   "After the trim the silence is still on the same words (it moved with the picture, 1 second earlier on the timeline). Remove gives the part its sound back; the row leaves the Quiet parts list. Each is one History step and one undo.", "listen"),
  ("pt-speed", "Speed… for a part",
   "Select a part of 4 seconds in clip B (double-click B and pull the handles in if B is longer), every row ticked. Click Speed…. Read the window. Click 0.5×, 0.25×, 1.5× and 2× in turn and read the line and the tick box each time. Choose 0.5× and confirm. Play across it. Press Ctrl+Z, then Ctrl+Shift+Z.",
   "A window \"Speed of this part\" with 0.25×, 0.5×, 1.5× and 2× (or any speed), a line like \"0.5×: this part will take 8.0 s (now 4.0 s)\", a note that the clip's own sound and voices lined up with it follow while music and other sound keep their speed and their place, and the tick box \"Mute this part's own sound\", which ticks itself below 0.5×. After confirming, B is cut at both ends of the part, the middle piece plays in slow motion and is twice as long, and the music did not move. Undo and redo are one step each. Ask the owner to watch: smooth slow motion, normal speed before and after.", "watch"),
  ("pt-clean", "Clean up sound here",
   "Select a part of about 5 seconds in clip A where there is talking. Alt+click the tick box of the Video row and click Clean up sound here. Read the message. Wait until the sound is prepared, then play across the part.",
   "A message that Clean up sound is on for this part on Video, and that you hear it once its sound is prepared, and in the export. The clip is cut at both ends of the part and only the middle piece has Clean up sound on (click it and look at its Sound settings). Ask the owner to listen: less hiss or hum on the part, the voice in sync.", "listen"),
  ("pt-more", "Short, duplicate, title and marker from a part",
   "Select a part from 0:02 to 0:10. Click Good moment marker at its start (in the bar under \"Make a short, duplicate, title, marker\", or in the Part menu). Then Title over the part. Then Duplicate the part; press Ctrl+Z. Then Make a short from the part…: read the window, name it \"Round 7 part short\", click Make the short and then Stay here.",
   "Marker: a flag at 0:02 and \"Marked 0:02 as a good moment.\" (a second time: \"There is already a marker there.\"). Title over the part: a new title that starts and ends with the part (History: \"Added a title over a part\"). Duplicate the part: \"A copy of the part is right after it (now selected).\" and the video is longer by the part. Make a short: the window \"Make a short\" shows the part's times and length; a new upright project \"Round 7 part short\" is in the project list and this project is unchanged.", ""),
  ("pt-text", "From the Text window: Select this part on the timeline",
   "Open the Text window (Ctrl+Shift+T). Click the first caption, Shift-click the second, and click Select this part on the timeline. Look at the timeline. Press Esc. Close the Text window.",
   "The bar above the page says how many captions are selected and from when to when. Select this part on the timeline selects exactly that stretch as a part on the timeline, with the bar and the tick boxes. Esc clears it.", ""),
  ("pt-export", "The export has the silence, the lower music and the slow part",
   "Press Ctrl+E, choose Custom, Make: Video, Small file, and export as r7-part.mp4 into the clipforge-test-output folder. Play the file in Media Player at the three places: the silenced part, the part with lower music, the slow-motion part.",
   "It finishes with \"Video saved\". Ask the owner to watch and listen to the file: at the silenced part the voice is gone and the music plays on, without a click at either edge; the music is quieter on its part; clip B is in slow motion on its part; everything else is as in the preview.", "watch,listen"),
  ("pt-help", "The four new help articles",
   "Press F1. Search for each of: select a part, silence, slow down, only when speaking. Open each article that comes first and read it once.",
   "The articles \"Select a part\", \"Silence or lower a part\", \"Slow down a part\" and \"Only when speaking\" are found and open. Their text fits what you just did (the strip, I and O, the rows, the bar). Write down any sentence that does not match the app.", ""),
 ]),
 ("D. Only when speaking (new in 1.17)", [
  ("ows-none", "Without a voice track it says why",
   "In \"Round 7 test\" (no voice track) open the Sound menu and read Only when speaking…; click it if it can be clicked.",
   "The item is grey with its reason, or a line says \"There is no speech track yet. Add a voice …\". Nothing is changed.", ""),
  ("ows-short", "A short project with the two voices",
   "Needs a video with one sound file per speaker (otherwise set Not tested for this group). Open \"Round 7 long\", select a part of 60 seconds in which both people talk, and choose Part > Make a short from the part…; UNTICK Short caption look, name it \"Round 7 two voices\", click Make the short and Open it. (With a short recording V and its voice files W, make a new project \"Round 7 two voices\" with them instead: Add > Voice recording….)",
   "The new project is about 60 seconds long and has both voice tracks, still lined up with the picture (play 10 seconds: the voices match the lips). If a line with a tip about two microphones appears under the top bar, write its text down and leave it for the next step.", ""),
  ("ows-suggest", "The suggestion with two voice tracks",
   "In \"Round 7 two voices\" wait until \"Drawing sound…\" is gone and read the thin line under the top bar. Click its button Only when speaking….",
   "A line \"Two microphones: each one also picks up the other speaker and the room.\" with the button Only when speaking… (another suggestion may show first: write it down, close it with its cross and wait). The button opens the window \"Only when speaking\".", ""),
  ("ows-on", "Switch it on",
   "If the window is not open: Sound > Only when speaking…. Read it. Switch it on for both voice tracks. Under \"Between the turns\" read the choices and leave \"A little room sound (−18 dB)\". Open \"How it works, and its limits\" and close Help again. Close the window. Click the name of one voice track on the left and read its menu.",
   "The window \"Only when speaking\" explains that each microphone also hears the other people, breathing and the room, and that switched on, a microphone is turned down while its speaker is not talking, in the preview and the export; it goes by loudness, not by words: listen to a stretch before you export. Each voice track has its switch (\"Turned down while this speaker is silent\"). Between the turns: A little room sound (−18 dB), More room sound (−12 dB), Hardly any (−30 dB) and silence. The track's menu has Only when speaking too, and it shows the same state. It is OFF unless switched on.", ""),
  ("ows-listen", "Hear and see it",
   "Look at the two voice rows on the timeline. Play 30 seconds in which the speakers take turns. Then switch Only when speaking OFF for both tracks (Sound > Only when speaking…) and play the same 30 seconds; switch it ON again.",
   "With it on, each voice's sound wave is small where that speaker is silent. Ask the owner to listen with headphones: with it on, the other person's voice and the room are much quieter under each speaker, no word is cut off at the start of a turn, and the sound between the turns is not dead silent; with it off the echo of the other microphone is back.", "listen"),
  ("ows-export", "It is in the export too",
   "With Only when speaking on, press Ctrl+E, choose Custom, Small file, and export as r7-speaking.mp4. Play the file.",
   "The export finishes. Ask the owner to listen to the same 30 seconds in the file: it sounds like the preview with Only when speaking on (the export's fades are exact; the preview's are a little coarser).", "listen"),
 ]),
 ("E. Shorts from markers (fixed in 1.17)", [
  ("shm-short", "Two markers in a short video: two different parts",
   "Make a new project with file B only (a video shorter than 45 seconds), rename it \"Round 7 markers\". Write down its length. Put the playhead at one third of it and press M, and at two thirds and press M. Choose Clip > Make shorts from markers…. Read the title, the text and the two lines with times. Untick Short caption look and click Make them. Read the result and click its button. Go to the project list and count the new projects.",
   "The window is titled \"Make 2 shorts from the markers?\" and says: one new upright project around each marker, about 20 seconds before it to 25 seconds after (less in a short video), starting and ending at a pause. The two parts listed are DIFFERENT and neither is the whole video: in a video under a minute each is about half the video (at least 8 seconds). Afterwards \"2 shorts are ready\" lists two projects, with Open the first. The project list has exactly two new projects, as many as the window said. (In 1.15 both parts were the whole video and one short was made.) If one could not be made, the message says \"1 of 2 shorts was made\" with \"Not made: …\" and the reason: copy it.", ""),
  ("shm-close", "Two markers close together: one short, or two",
   "Open \"Round 7 markers\". Remove both markers (right-click a flag > Remove this marker). Press M at one third of the video and again 2 seconds later. Choose Clip > Make shorts from markers…. Read the note and the choice. Leave \"One short covering both\" and click the button. Count the new projects. Then open the window again, choose Two shorts and make them. Count again.",
   "The window says \"The two markers are close together: their shorts would show mostly the same part.\" and offers One short covering both (ticked) and Two shorts (a short for every marker). With the first choice the title reads \"Make 1 short from the 2 markers?\", one part is listed, and exactly ONE new project is made (\"The short is ready\"). With Two shorts the title counts 2, two parts are listed and two projects are made. The number made is always the number in the title; a name that exists gets \"(2)\".", ""),
  ("shm-long", "Markers in a longer video",
   "Open \"Round 7 test\". Press M at about 0:40 and at about 1:20 (if the video is shorter, at one quarter and three quarters). Choose Clip > Make shorts from markers…, read the two parts, leave Short caption look ticked and click Make them, then Open the first. Play it and go back.",
   "In a video longer than a minute each part runs from about 20 seconds before its marker to about 25 seconds after it, moved to pauses. Two shorts are made. The first one opens: upright 9:16, the wide picture in the middle; captions that lie in that part are bigger, in the lower middle and outlined. \"Round 7 test\" is unchanged. Ask the owner to watch it once.", "watch"),
 ]),
 ("F. Keyboard shortcuts wherever you clicked last (fixed in 1.17)", [
  ("key-timeline", "After a click on the timeline",
   "In \"Round 7 test\" click clip A on the timeline. Then press, one after the other, and look each time: Space (plays), Space (stops), Right, Left, Home, End, Ctrl+Right, Ctrl+Left, S (splits), Ctrl+Z, Ctrl+Y (redo), Ctrl+Z, Ctrl+Shift+H (History opens), Ctrl+Shift+H, Ctrl+Shift+T (Text opens), Ctrl+Shift+T, Ctrl+F (the search box of Text gets the cursor), Esc, Ctrl+E (Export opens), Esc, F1, Esc.",
   "Every key does its job at the first press. Write down each key that did nothing or did something else.", ""),
  ("key-text", "After a click in the Text window",
   "Open the Text window and click a sentence in it. Press the same keys as in the step before, except S. Then click an EMPTY place of the Text page and press Space, Ctrl+Z and Ctrl+Y.",
   "The same result: Space plays and stops, the arrows move the playhead by a frame, Ctrl+Z / Ctrl+Y undo and redo, Ctrl+Shift+H, Ctrl+E, Ctrl+F and F1 open their windows. (In 1.15 the keys stopped working after a click in the Text window.)", ""),
  ("key-slider", "After a click on a slider or a switch in the side panel",
   "Click clip A. In the side panel click on the Volume slider (move it a little), then press Space, Space, Right, Left, Ctrl+Z, Ctrl+Y. Click a switch in the side panel (for example Mute) and press Space once: look whether the video plays or the switch flips. Click a button in the side panel and press Ctrl+Shift+H twice.",
   "After a click on a slider, Space plays the video (it does not move the slider), and Right / Left step one frame (they do not change the volume). After a click on a switch or a button, Space plays (it does not press the control again). Ctrl shortcuts always work. One exception that is intended: after pressing Tab to walk through the controls, plain keys go to the control until the next mouse click.", ""),
  ("key-typing", "While typing, the keys stay with the text field",
   "Click the title on the timeline, click into its Text box in the side panel and type: jkl iq wso m (with the spaces). Press Ctrl+Z once while still in the box. Click an empty place on the timeline and press L, then K.",
   "The letters only go into the text: nothing plays, splits, trims, marks a part or drops a marker (no flag, no highlighted part). Ctrl+Z in the box takes back typing in the box. After clicking outside, L plays and K pauses.", ""),
  ("key-comma", "Ctrl+comma opens Settings everywhere",
   "On the project list, click an empty place and press Ctrl+comma; close Settings. In a project press Ctrl+comma; close. Ask the owner whether a second keyboard layout is installed (for example Russian or Hebrew): if yes, switch to it (Win+Space), press Ctrl and the key that is the comma on the English layout, close Settings and switch back.",
   "Settings opens each time, also when nothing on the page has the keyboard and with a layout where that key types another letter. (Round 6: it did not open on this PC.) Without a second layout set Partial and say so.", ""),
 ]),
 ("G. Send feedback (1.16) with \"Include details about how ClipForge ran\" (1.17)", [
  ("fb-page", "The page and the \"What is sent\" box",
   "Choose Help > Send feedback…. Read the page. Click each of Problem, Idea, Praise, Question. Type into the message: TEST from Round 7, please ignore. Leave the e-mail address empty. Read the box \"What is sent\". Do NOT press Send yet.",
   "A page with the four kinds, a message box (\"What did you do, what did you expect, and what happened instead?\"), \"Your e-mail address (optional)\" with \"Only used to answer you.\", and a box \"What is sent\" that shows exactly what goes: the kind, your message, the version and build of ClipForge, the name and version of the system, and says that only this is sent, only when you press Send, and that nothing about your projects, file names, videos, photos or music is ever included.", ""),
  ("fb-details", "The tick box \"Include details about how ClipForge ran\"",
   "Find the tick box \"Include details about how ClipForge ran\" and read its explanation. Check that it is OFF. Tick it and read the box \"What is sent\" again, to its end. Look in those lines for the names of your test files and projects (for example \"Round 7\", the name of file L). Untick it and look again; tick it again.",
   "The box is off unless you tick it. Its explanation: the performance log (when ClipForge opened a project, saved, drew sound waves, and when it could not respond), no file names, no project names, nothing you typed; you see the lines before they are sent. Ticked, \"What is sent\" shows the performance-log lines; unticked, they are gone. No file name and no project name is in them. FAIL if a name of yours appears: copy that line.", ""),
  ("fb-draft", "The draft is kept; the other ways in",
   "Close the feedback page without sending. Open it again from Help > About ClipForge (its Send feedback button). Close it. Open Settings and find Send feedback there; open F1 and look at the bottom of Help.",
   "What you wrote is still on the page each time (the message, the kind). About ClipForge, the bottom of Help and Settings each have a way to Send feedback that opens the same page.", ""),
  ("fb-send", "Send one test message (only if the owner agrees)",
   "Ask the owner: \"May I send one test message with the performance details ticked? It goes to the ClipForge website.\" Only after a yes: with the message \"TEST from Round 7, please ignore.\", kind Problem, no e-mail address and the box ticked, press Send once. If the owner says no, set Not tested.",
   "\"Sent. Thank you!\" and the page is empty afterwards (the draft is gone). If it says \"The message could not be sent. Check the internet connection and try again.\", it offers Open the feedback page in the browser and Copy my message, and your text stays: copy what it says and set FAIL only if the internet works. Ask the owner later whether the message arrived with the performance lines.", ""),
 ]),
 ("H. Smaller things changed in 1.17", [
  ("sm-addpath", "Add from a folder path…, and Ctrl+V with a path",
   "In \"Round 7 test\" choose Add > Add from a folder path…. Type a path that does not exist (the media folder plus \\nothing-here) and look it up. Then paste the full path of file B alone and add it; press Ctrl+Z. Close the window. In Explorer, hold Shift, right-click file B and choose Copy as path; back in ClipForge click an empty place on the timeline and press Ctrl+V.",
   "The window explains: type or paste the path of a file, or of a folder to choose from (in Explorer: Shift+right-click > Copy as path). A wrong path says \"There is no file or folder at that path.\" A file path adds that file (a sound file asks \"What is this sound?\"); a path in quotation marks works too. Ctrl+V on the timeline with a copied path opens the same window with the path filled in. A project file is refused with \"That is a project file: open it from the project list.\"", ""),
  ("sm-menus-1", "File, Edit, Add and Clip menus",
   "There are ten menus now: File, Edit, Add, Clip, Part, Sound, Text and speech, View, Playback, Help. Open File, Edit, Add and Clip and compare every item and shortcut with Expected.",
   "File: New project (Ctrl+N), Open project file… (Ctrl+O) | Rename project…, Publishing notes…, Back to projects | Export… (Ctrl+E), Export several…, Export subtitles (.srt)… | Settings… (Ctrl+,) | Exit (Alt+F4). Edit: Undo (Ctrl+Z), Redo (Ctrl+Shift+Z / Ctrl+Y), History (Ctrl+Shift+H) | Duplicate (Ctrl+D), Copy settings (Ctrl+Shift+C), Paste settings (Ctrl+Shift+V), Delete (Delete / Backspace) | Find in the text… (Ctrl+F). Add: Videos or photos…, Music or sound…, Voice recording…, Title, Caption…, Subtitle file (.srt)…, Overlay video or photo…, Add from a folder path…, Good moment marker (M). Clip: Split (S), Start at playhead (Q), End at playhead (W), Freeze frame, Remove silences…, Crop and position…, Rotate right, Move earlier, Move later | Make a short from here…, Make shorts from markers…, Good moments…. In an open project New project and Open project file… are grey with \"(go back to the projects first)\". Write down every difference.", ""),
  ("sm-menus-2", "Sound, Text and speech, View, Playback and Help menus",
   "Open Sound, Text and speech, View (with Shape and Video size), Playback and Help and compare with Expected. (The Part menu was compared in group C.)",
   "Sound: Fit music to video, Line up voice with video, Separate sound…, Put sound back, Add sound track, Lower music under speech, Only when speaking…, Copy music credits. Text and speech: Text window (Ctrl+Shift+T), Transcribe speech…, Captions from speech…, Remove filler words…, Automatic cuts…. View: Zoom in (+), Zoom out (-), Snap to playhead and edges, Show sound waves | Shape > Original (as the first clip), 9:16 upright, 16:9 wide, 1:1 square, 4:5 upright | Video size > Same as the first clip, 720p, 1080p (Full HD), 4K. Playback: Play/Pause (Space), Play backwards (J), Pause (K), Play forwards (L) | Go to start (Home), Go to end (End), Previous frame (Left), Next frame (Right) | Previous speech start (Ctrl+Left), Next speech start (Ctrl+Right). Help: ClipForge Help (F1), Keyboard shortcuts, Show the tour, What's new | Connect to Claude…, Check for updates… | Send feedback…, Copy version info, About ClipForge. Zoom in shows \"+\". Write down every difference.", ""),
  ("sm-grey", "Greyed items say why, also on the project list",
   "In \"Round 7 test\" click an empty place so nothing is selected. Read Sound > Fit music to video, Edit > Paste settings, Edit > Delete and Part > Cut out. Then go to the project list (File > Back to projects) and open the Clip, Part and Sound menus there. Open the project again.",
   "In the project: \"Fit music to video (select a music clip)\", \"Paste settings (copy settings first)\", \"Delete (select something first)\", \"Cut out (no part is selected)\". On the project list every editor item is grey and says \"(open a project first)\" (in 1.15 they were grey without a reason). Write down any greyed item without a reason.", ""),
  ("sm-context", "Right-click menus stay inside the window",
   "Make the ClipForge window small (about half the screen height). Right-click clip A near the bottom of the timeline; press Esc. Right-click the music; Esc. Right-click the title; Esc. Right-click a flag on the ruler; Esc. Right-click an empty part of a track; Esc. Make the window large again.",
   "Each right-click selects that item and opens a small menu at the pointer with what can be done with it (clip: Split, Start at playhead, End at playhead, Duplicate, Copy settings, Paste settings, Freeze frame, Remove silences…, Crop and position…, Rotate right, Separate sound…, Put sound back, Move earlier, Move later, Make a short from here…, Delete, and the selecting of its time). A long menu never runs past the edge of the window: it fits, or it scrolls.", ""),
  ("sm-export-words", "The Export window's corrected lines",
   "Press Ctrl+E. Click WhatsApp / Telegram and read the size it shows. Click Shorts / Reels / TikTok and read the question about the shape. Click Instagram post and read its button for the site (it also shows on the finished screen). Click Custom and open Frames per second. Click Cancel.",
   "WhatsApp / Telegram shows the size that is really written (for a wide video 1280 × 720), not the project's size next to \"720p\". The shape question names both shapes the same way: \"Your video is 16:9 wide; this needs 9:16 upright\". The Instagram button says \"Open Instagram\". Frames per second offers Same as the clips, 24, 25, 30, 60.", ""),
 ]),
 ("I. Projects", [
  ("pr-list", "The project list and a project's menu",
   "Go to the project list. Read one project card (picture, name, length, date). Open the three dots of the card \"Round 7 markers\" and read the list. Click Duplicate twice. Rename one copy to the name of the other.",
   "Each card shows a picture, the name, the length and the date. The card menu has Rename, Duplicate, Share project file and Delete. The copies get names that are not taken (\"… (2)\", \"… (3)\"); renaming to a name that exists also gives a number in brackets, never two projects with the same name.", ""),
  ("pr-share", "Share project file and Open project file",
   "On the card of one copy choose Share project file and save the file into clipforge-test-output. Then choose File > Open project file… (Ctrl+O) and pick that file. Open the project it makes, play 5 seconds, go back. Delete the copies this test made (card menu > Delete), not the owner's projects.",
   "A file ending in .clipforge.zip is written (\"Packing …\" may show). Opening it adds a project with a free name that has the clips with their pictures and plays, with the markers. Delete asks first and removes only that project.", ""),
  ("pr-drop", "Drag and drop files onto ClipForge",
   "From Explorer drag file B onto the project list. Then, in the project that opens, drag file P onto the window. (If dragging between windows fails twice, set Needs the owner.)",
   "Dropping on the project list makes a new project with that file; dropping on an open project adds the file. A dropped sound file asks \"What is this sound?\".", ""),
  ("pr-missing", "A missing file and Find file",
   "In Explorer copy file B into clipforge-test-output as r7-missing.mp4 (a copy this test made). Make a new project \"Round 7 missing\" with that copy. Go to the project list and choose File > Exit. In Explorer rename the copy to r7-found.mp4. Start ClipForge, open the project, read what it shows, press Ctrl+E and read, cancel. Click Find file… on the clip and pick r7-found.mp4.",
   "The clip is marked Missing (red) and the app names the file that is gone. Export says that a file is missing before it starts. Find file… opens a file window; after choosing the file the clip has its picture again and plays. (If ClipForge kept its own copy and nothing is missing, write that down and set Partial.)", ""),
  ("pr-history", "History, undo and redo",
   "Open \"Round 7 test\". Press Ctrl+Shift+H. Copy the newest 15 names into the note. Click a step about 10 back, then the newest. Press Ctrl+Z 5 times and Ctrl+Y 5 times. Close History.",
   "A History column with your changes by name, newest first; the part actions have clear names (cut out, silenced, lowered, speed of a part, title over a part). Clicking an old step puts the project back to that point (later steps look grey); the newest restores everything. Each undo takes back exactly one change and each redo brings it back. No vague names like \"Changed\".", ""),
  ("pr-quit", "Quit while editing: everything is saved",
   "With \"Round 7 test\" open and nothing exporting, make one small change (move the title a little) and press Alt+F4 at once. Start ClipForge again and open the project.",
   "It closes without asking. After reopening, the last change and everything else is there. The top bar shows Saved.", ""),
 ]),
 ("J. Timeline and cutting", [
  ("tl-split", "Split, delete, undo; trim by dragging; reorder",
   "Make a new project \"Round 7 basics\" with A, B and P (Add from a folder path). Click clip A, put the playhead in its middle and press S. Click the second piece and press Delete; Ctrl+Z. Drag the right end of B about 2 seconds to the left. Drag the photo P in front of B. Then click P and use Clip > Move later and Clip > Move earlier.",
   "S cuts A into two pieces; Delete removes the selected piece and the rest moves up; undo brings it back. Dragging an end trims the clip. Dragging a clip moves it to a new place in the order; Move earlier / Move later do the same from the menu. (If a drag fails twice, use the menu and set Partial.)", ""),
  ("tl-transition", "Transitions",
   "Click clip B. In the side panel open Transition and fades. Choose each transition in turn (Crossfade, Fade through black, Slide left, Slide up) and play across the start of B each time. Leave Crossfade.",
   "Each choice changes how the clip before B changes into B: a soft mix, through black, B slides in from the right, B slides up. Ask the owner to watch: smooth, no frozen frame.", "watch"),
  ("tl-speed", "Speed of a clip",
   "Click the first piece of A. Open Speed in the side panel. Choose 0.5×, play 5 seconds; choose 2×, play; set it back to 1×.",
   "The speeds from 0.25× to 4× are offered. At 0.5× the clip is twice as long and slow; at 2× half as long and fast. Ask the owner to listen: the voice keeps its pitch (slower or faster, not deeper or higher).", "listen"),
  ("tl-freeze", "Freeze frame",
   "Put the playhead in the middle of B and choose Clip > Freeze frame. Play across it. Press Ctrl+Z.",
   "The picture under the playhead is held still for a moment as a new item between the two halves of B. One undo removes it.", ""),
  ("tl-dup", "Duplicate, Copy settings, Paste settings, Apply to all",
   "Click B and press Ctrl+D; delete the copy. Click the first piece of A, open Look, choose the filter Vintage and Fill. Press Ctrl+Shift+C. Click the photo P and press Ctrl+Shift+V. Press Ctrl+Z. Then, with the first piece of A selected, find Apply to all clips in the side panel and use it for the look; read what it asks; press Ctrl+Z.",
   "Ctrl+D adds one copy right after B with the same settings. Paste settings gives P the same look and fit as A but keeps its own length; one undo takes it back. Apply to all clips gives every clip the same setting in one step, and one undo takes it back.", ""),
  ("tl-snap", "Snapping, and Alt to place freely",
   "Put the playhead at 0:08. Add a title at 0:03 (Add > Title, type: Basics). Slowly drag the right end of the title towards the playhead. Then hold Alt and drag it slowly past the playhead. Open View and read Snap to playhead and edges.",
   "Near the playhead the edge jumps onto it and a yellow line shows. With Alt held there is no jump and no yellow line. View > Snap to playhead and edges is ticked. (If you cannot hold a key while dragging, set Needs the owner for that part.)", ""),
  ("tl-keys", "J K L, frame steps, second steps, zoom",
   "Click an empty place on the timeline. Press L, wait 2 seconds, press K; press J, wait 2 seconds, press K. Pause on clip A and note the time. Press Right 30 times and note the time; Left 30 times. Press Shift+Right once. Press + three times and - three times.",
   "L plays, K pauses, J goes backwards in small steps. Each Right / Left moves one frame; 30 presses move about 1.0 s on a 30 fps clip (1.2 s at 25 fps, 0.5 s at 60 fps) and Left 30 times returns to the same time. Shift+Right moves 1 second. + zooms the timeline in, - out. Write down the times you saw.", ""),
  ("tl-long-note", "A long project stays usable",
   "Open \"Round 7 long\". Read any note it shows about long projects. Zoom fully out and fully in, scroll from the start to the end, and click five places on the ruler quickly one after the other.",
   "The timeline scrolls and zooms without waiting, clip pictures fill in as they come into view, and the preview follows the playhead. A note for very long projects may be shown once: write its text down.", ""),
 ]),
 ("K. Picture", [
  ("pic-shape", "Shape, Fit, Fill, Blur",
   "In \"Round 7 basics\" choose View > Shape > 9:16 upright. Click the first piece of A and in Look choose Fit, then Blur, then Fill. Then try View > Shape > 1:1 square and 4:5 upright, and go back to 9:16 upright.",
   "The preview takes each shape. Fit shows the whole wide picture with bars, Blur fills the bars with a blurred copy of the picture, Fill makes the picture fill the frame (its sides are cut off).", ""),
  ("pic-position", "Position: keep the person in shot",
   "With Fill on the first piece of A, choose Clip > Crop and position…. Move Left – right fully to one end, then the other, then put the person in the middle.",
   "With Fill, Left – right changes which part of the wide picture fills the tall frame. With Fit the position has no effect and the panel says so.", ""),
  ("pic-crop", "Crop with handles and shapes, rotate and flip",
   "Choose View > Shape > Original (as the first clip). Click B and choose Clip > Crop and position…. On the preview drag the bottom-right corner of the frame inwards, then drag inside the frame. Click 1:1, 9:16, Free and Original. Click Rotate right twice, Rotate left, Flip sideways, Flip upside down, then Reset crop and position. Then choose Clip > Rotate right and press Ctrl+Z.",
   "The preview shows the whole picture with a frame, grips and the outside dimmed. A corner drag makes the frame smaller, a drag inside moves it; 1:1 and 9:16 keep their shape while you drag. Each rotate turns the picture a quarter turn, each flip mirrors it, Reset puts it back. The menu item turns it like the button and undo turns it back.", ""),
  ("pic-look", "Brightness, contrast, saturation, zoom; filters and warmth",
   "Click the first piece of A and open Look. Move Brightness, Contrast, Saturation and Zoom each a little and back. Under Filter click Warm, Cool, Black & white, Vintage, Vivid, None in turn. Choose Vintage and move Warmth left and right. Click Reset look, then Ctrl+Z.",
   "Each slider changes the preview at once. Each filter changes the colours at once (Black & white has no colour; None removes it). Warmth makes it more orange or more blue. Reset look removes filter and warmth; one undo brings them back.", ""),
  ("pic-size", "Video size",
   "Choose View > Video size > 720p. Press Ctrl+E, choose Custom, read the size shown, cancel. Choose View > Video size > Same as the first clip.",
   "The tick moves to 720p and the Export window shows that size (1280 × 720 for a wide video). 1080p (Full HD) and 4K are offered too.", ""),
  ("pic-overlay", "Overlay: add, corner, size, frame, drag",
   "Put the playhead at 0:05. Choose Add > Overlay video or photo… and pick file B. Click the overlay on its row. Under Layout keep Picture-in-picture, set Corner to the top left, Size to about 50 %, switch White frame on. On the preview drag the overlay to the middle and drag its corner grip outwards.",
   "B appears as a small picture in a corner of the preview from 0:05, on a new Overlay row above the main clips. Corner, Size and White frame change it at once. Dragging it on the preview moves it anywhere (Layout changes to Free position); the corner grip resizes it.", ""),
  ("pic-overlay-2", "Overlay layouts, trim, mute",
   "Choose Layout Side by side, then Top and bottom, then Full screen, and play across the overlay each time. Set it back to Picture-in-picture. On the Overlay row drag the overlay 3 seconds to the right and drag its right end shorter. Switch Mute overlay sound on and off while it plays. Right-click the overlay and read its menu.",
   "Side by side: your video on one half, B on the other. Top and bottom: one above the other. Full screen: B covers the picture while it plays. It moves and trims on its row; Mute overlay sound silences B only. The right-click menu has what can be done with an overlay (crop, rotate, selecting its time, delete). Ask the owner to watch and listen: B plays smoothly and starts and stops at the right moment.", "watch,listen"),
  ("pic-fades", "Fade the whole video, and one clip",
   "Click an empty place so nothing is selected. In the side panel set Fade in from black and Fade out to black to about 2 s each. Play from 0:00 and play the last 4 seconds. Then click B, open Transition and fades and set its Fade out to black to about 1 s; play across the end of B.",
   "The video comes up from black at the start; at the end picture, titles, overlay and all sound go down together. B's picture and own sound fade over its last second and the next item starts normally. Ask the owner to watch and listen.", "watch,listen"),
 ]),
 ("L. Titles and captions", [
  ("ti-fonts", "Fonts, styles, outline, shadow, position, alignment",
   "In \"Round 7 basics\" click the title \"Basics\". In the side panel click Font Classic, Modern, Elegant, Handwritten in turn, then two different Styles. Switch Outline on; Shadow off and on; Dark box behind text on and off. Under Position click Top, Middle, Lower third, Bottom; then Left, Centre, Right.",
   "Each font visibly changes the letters; a Style changes several settings at once. Outline draws a line around the letters, Shadow adds or removes a soft shadow, the box appears and goes. Each Position moves the text to that height; Left / Right line it up at that side.", ""),
  ("ti-lang", "Hebrew and Russian letters",
   "Put the playhead at 0:10 and choose Add > Title. Copy this text from this page and paste it into Text: שלום עולם / Привет, мир . Click each of the four fonts.",
   "In every font the Hebrew and Russian letters show properly (no empty boxes, no question marks). The Hebrew words keep their order: read right to left, שלום comes before עולם.", ""),
  ("ti-anim", "Appear and Disappear",
   "Click the title \"Basics\". Set Appear to Slide up and Disappear to Pop. Play from 1 second before the title to 1 second after it. Then set Appear to Fade and play again.",
   "The title slides up into place at its start and pops away at its end, each in less than half a second; with Fade it fades in. Ask the owner to watch.", "watch"),
  ("ti-follow", "A title follows its clip",
   "Note the time of the title \"Basics\" and which clip is under it. Click the clip BEFORE that one and press Delete. Look at the title. Press Ctrl+Z.",
   "The title moved earlier together with the clip it lies on (it still shows over the same picture). Undo puts both back.", ""),
  ("ti-srt", "Subtitle file: export and import",
   "Open \"Round 7 test\". Choose File > Export subtitles (.srt)… and save as r7-captions.srt in clipforge-test-output. Make a new project \"Round 7 srt\" with file A. Choose Add > Subtitle file (.srt)… and pick r7-captions.srt.",
   "A .srt file is saved with the four captions. After the import the new project has the same captions at the same times with the same text (open the Text window to read them); a message says how many were added.", ""),
  ("ti-vertical", "Text fits an upright video",
   "In \"Round 7 srt\" choose View > Shape > 9:16 upright and play the first 15 seconds. Then choose Original (as the first clip) again.",
   "The captions and titles stay inside the upright frame, wrapped onto more lines if needed, and are readable; nothing is cut off at the sides.", ""),
 ]),
 ("M. Sound", [
  ("so-music", "Music: volume, fades; a clip's volume and mute",
   "In \"Round 7 basics\" put the playhead at 0:00 and add music M (Add > Music or sound…, My files; Music). Click the music: set Volume to about half and Fade in and Fade out to about 2 s. Click clip A: move its Volume, switch Mute on and off. Play the start.",
   "The music starts at 0:00 on a Music track, fades in, and is quieter at half volume; at the video's end it fades out by itself instead of stopping dead. The clip's own sound gets louder, quieter or silent. Ask the owner to listen.", "listen"),
  ("so-clean", "Clean up sound, Hear original, Voice focus",
   "Click the first piece of A, open Sound and switch on Clean up sound. Wait until \"Preparing sound…\" is finished. Play it and switch Hear original on and off while it plays. Then switch on Voice focus, wait and play again.",
   "The clip shows \"Sound …%\" and then finishes; meanwhile the preview plays a light version. Ask the owner to listen: hiss or rumble is lower with Hear original off; with Voice focus the speech is clearer and the background quieter; the voice stays in sync with the lips.", "listen"),
  ("so-sample", "Sound from, and Hear a sample",
   "With the same clip selected, read \"Sound from\" in its Sound settings (the choices depend on the file) and click Hear a sample.",
   "Sound from lets you choose which sound of the file is used (a track, or left / right only) when the file has more than one. Hear a sample plays about 15 seconds with and without your sound settings. Ask the owner to listen.", "listen"),
  ("so-tracks", "Sound tracks: add, menu, mute, solo, move, delete",
   "Choose Sound > Add sound track until it is refused. Click the name of the last track on the left and read its menu. While the video plays click M and S on the Music track, each on and off. In a track's menu click Move up and Move down. Delete the empty tracks (Delete track). Click Video (the first name on the left) and switch Mute on and off.",
   "No more than three sound tracks: then the item reads \"Add sound track (there are already 3 tracks)\". The track menu has Name, Volume, Mute, Solo, Lower this track under speech, This track is speech, Only when speaking, Move up, Move down and Delete track. M silences that track, S plays only that track, Video > Mute silences the clips' own sound while music plays on. Ask the owner to listen while you click.", "listen"),
  ("so-separate", "Separate sound, an L-cut, Put sound back",
   "Click the first piece of A and choose Sound > Separate sound…; leave \"Also the other clips with sound\" off and confirm. Drag the left edge of that clip about 2 seconds to the right. Drag the sound piece under it about 1 second to the right. Play across the start of the clip. Then click the clip and choose Sound > Put sound back; Ctrl+Z; Ctrl+Y.",
   "The clip's sound appears as a piece on a Voice track under the clip and the clip shows as muted; the voice is heard once. After the trim the sound piece is trimmed the same way; after dragging it, the voice starts about 1 second after the picture (an L-cut). Put sound back removes the piece and unmutes the clip; undo and redo work. Ask the owner to listen.", "listen"),
  ("so-roles", "\"What is this sound?\": Music and Sound effect",
   "Put the playhead at 0:10 and add music M once more, but answer \"What is this sound?\" with Sound effect. Look where it lands. Delete it.",
   "The window offers Voice for the video, Music and Sound effect (guessed from the file's name and length), with Cancel and Add. A Sound effect goes to an Effects track, Music to a Music track; two sounds never overlap on one track.", ""),
  ("so-voice", "A voice recorded separately: nudge, Line up again, Unlink",
   "Open \"Round 7 two voices\" (or set Not tested without voice files). Click one voice on its track. In its settings click the nudge buttons (1 frame, 10 ms, 100 ms) once each way, then Line up again. Then click Unlink, read what it says, and press Ctrl+Z.",
   "The voice's settings show that it is lined up with its clip, with buttons to move it by 1 frame, 10 ms or 100 ms, Line up again (compares the sound again and puts it back in sync) and Unlink (the voice stays where it is and no longer follows the clip). Ask the owner to listen after Line up again: lips and voice match.", "listen"),
  ("so-voice-cuts", "Cuts keep the voice in sync",
   "In \"Round 7 two voices\" click the video clip, put the playhead at 0:20 and press S; click the second piece, put the playhead 3 seconds into it and press Q; set the speed of the last piece to 1.5×. Play across each change. Press Ctrl+Z three times.",
   "Every voice is cut, trimmed and sped up together with its clip, in the same undo step, and stays in sync. Ask the owner to watch and listen at each change.", "watch,listen"),
  ("so-silences", "Remove silences: Sensitivity, apply, undo",
   "Open \"Round 7 basics\", click a talking clip and choose Clip > Remove silences…. When the result shows, click Fewer cuts, Automatic and More cuts under Sensitivity and write down the gap count of each. With Automatic click the Remove … gaps button. Play across two cuts. Press Ctrl+Z, then Ctrl+Y.",
   "A progress bar with Cancel, then the background-noise line and a button like \"Remove 5 gaps\". Sensitivity changes the count at once without scanning again (Fewer cuts gives no more gaps than Automatic, More cuts no fewer). After removing, the clip is in pieces; one undo brings back the single clip. The cuts are listed under Text and speech > Automatic cuts…. Ask the owner to listen: no chopped words.", "listen"),
  ("so-fit", "Fit music to video, and loop short music",
   "In \"Round 7 basics\" click the music (longer than the video) and choose Sound > Fit music to video. Press Ctrl+Z. Then make the video longer than the music if you can (add file A two more times) and choose Fit music to video again, choosing to loop it. (If the music is still longer, set Partial.)",
   "Fit: the music ends exactly with the video, with the message \"The music now ends with the video, with a 2-second fade-out.\" Loop: the music piece shows that it repeats, with marks where, and reaches the end of the video. Ask the owner to listen at a repeat: no gap or click.", "listen"),
  ("so-free", "Find free music and credits",
   "Choose Add > Music or sound… and open Find free music. Search for: piano. Play the preview of one result and click Use. Click the downloaded music, click Copy credits and paste into the note; click Add credits at the end. Choose Sound > Copy music credits and paste.",
   "Results show title, artist, length and licence (CC0, Public domain, CC BY or CC BY-SA). The preview plays. After Use the music is downloaded and added. The pasted credits name the track, the artist, the licence and a link; a caption with the credits appears over the last 4 seconds. Without internet it says so in plain words: copy the text.", ""),
  ("so-lower", "Lower music under speech: three places agree",
   "Click an empty place. Look at (1) the side panel, \"All music in this project\" > Lower music under speech, (2) Sound > Lower music under speech, (3) the menu of each music track, Lower this track under speech. Switch the side-panel switch ON and look at all three. Switch it OFF in ONE track's menu and look again. Click the Sound menu item once and look again.",
   "None: all off, no tick. All: the switch on, a tick, the track switches on. Some: the side panel says \"On for some tracks only (set in each track's menu). Turn this on to lower every music track.\" and the menu item shows a dash and reads \"Lower music under speech — on for some tracks\". Clicking the menu item from \"some\" turns every music track on. The three places never disagree.", ""),
  ("so-waves", "Sound waves, slim marks, speech starts",
   "Look at the music and at the bottom edge of the clips: sound waves. Zoom far out and look at the captions of \"Round 7 test\" (open it): narrow captions become slim marks with the caption under the playhead shown on a line above. Go to the start, click the double arrow to the right of Play three times and the one to the left once; press Ctrl+Right twice and Ctrl+Left once.",
   "The music shows its waves (tall where it is loud) and each clip with sound a slim wave along its bottom. Zoomed out, narrow caption blocks are slim marks, the caption under the playhead is shown above them, and a block's tooltip shows its text. The double arrows (\"Previous speech start (Ctrl+Left)\", \"Next speech start (Ctrl+Right)\") and the keys move the playhead to where talking starts after a pause. Ask the owner to press Play at two of the stops: someone starts talking right there.", "listen"),
 ]),
 ("N. Settings and suggestions", [
  ("set-open", "The Settings page",
   "Choose File > Settings…. Read the page from top to bottom and close it.",
   "A window \"Settings\" with the parts: Editing (Snap to playhead and edges, Show sound waves), Text window (Where it opens: At the right / Below), Export (Use graphics card (faster)), Suggestions (Show suggestions, and the button \"Show hidden suggestions again (…)\"), Updates (Check for updates automatically, Check now, and the version line), Claude (a line about the helper for Claude, and Connect…), About (About ClipForge, Copy version info, What's new, Licences, and Send feedback). Every switch has one line of explanation.", ""),
  ("set-switches", "Every switch changes the app and survives a restart",
   "In Settings switch OFF: Snap to playhead and edges, Show sound waves, Use graphics card (faster), Show suggestions, Check for updates automatically; set the Text window to Below. Close Settings. Look at the timeline, the View menu and (Ctrl+E > Custom) the line \"Will use: …\"; cancel. Choose File > Exit, start again, open a project and Settings. Then put everything back ON and the Text window to At the right.",
   "With the switches off: no waves on the timeline, no ticks on the two View items, the Export window's graphics-card switch is off and reads \"Will use: Processor (graphics card turned off)\", no suggestion line anywhere. After the restart every switch is as you left it. After switching them back on, the waves and suggestions return and the View menu shows both ticks.", ""),
  ("sg-small", "Suggestion: a small first clip (Use 1080p)",
   "New project with only file S (the small clip), rename it \"Round 7 tips\". Wait a second without playing and read the line under the top bar. Click Use 1080p and open View > Video size. (If S is 720p or bigger, set Not tested and write its size.)",
   "A thin line says \"The first clip is small (width×height), and the video takes its size from it.\" with Use 1080p, Don't show again and a cross. After the click the line goes and Video size has its tick on 1080p (Full HD).", ""),
  ("sg-shape", "Suggestion: another shape (Fill, Blur, Crop…); it comes back for the next clip",
   "In \"Round 7 tips\" add file A after S and choose View > Shape > 9:16 upright. Read the line and click Blur. Then add file B (also wide) and wait a second.",
   "The line says \"A clip has another shape than the video, so it gets bars.\" with Fill, Blur and Crop…. Blur selects that clip and fills its bars with a blurred copy. For the next clip of another shape the suggestion comes back (new in 1.17): it is shown again after B was added.", ""),
  ("sg-music", "Suggestions about music; \"Don't show again\"; Settings brings it back",
   "Put the playhead at 0:00 and add music M (Music). Read the line. Press Space and look where the line was; press Space. Click Don't show again. Go to the project list and open the project again. Open Settings, read the button under Show suggestions, click it, close Settings. When the line is back click Fit to video. Wait until \"Drawing sound…\" is gone and read the next line; click Lower the music.",
   "\"The music is longer than the video.\" with Fit to video. While the video plays the line is hidden. Don't show again makes it go and stay away; in Settings the button reads \"Show hidden suggestions again (1)\" and brings it back (\"One suggestion can show again.\"). Fit to video shortens the music. Then \"Music plays while someone is talking.\" with Lower the music; afterwards Sound > Lower music under speech has a tick. Write down any other line that shows (pauses in the talking, captions from speech, the Text window).", ""),
 ]),
 ("O. Text window", [
  ("tx-open", "Captions as a page, by speaker; follow playback",
   "Open \"Round 7 test\" and the Text window (Ctrl+Shift+T, or the Text button at the top right). Read it. Go to the start and press Play; watch the Text window until 0:16, then pause. Click the sentence \"Thanks, happy to be here.\"; then click the first caption block on the timeline.",
   "The window is titled Text and shows the captions as a readable page: the lines of one speaker joined into a paragraph with the time at the side, \"Sam Taylor\" once above his lines (the caption without a name belongs to him), then \"Alex K\", each with a coloured bar. With a transcript or titles a switch chooses Captions / Transcript / Titles. While playing, the line being spoken is marked and kept in view. Clicking a sentence moves the playhead there and selects that caption on the timeline; clicking a caption on the timeline marks it in the window.", ""),
  ("tx-search", "Search",
   "Press Ctrl+F. Type: test. Press Enter twice, then Shift+Enter once. Clear the box and type: xyzzy. Clear the box.",
   "Ctrl+F puts the cursor into \"Find in the text…\". Every place with \"test\" is marked and counted (\"1 of 2\"); Enter goes to the next one, Shift+Enter to the previous one. For xyzzy it says \"Not found\".", ""),
  ("tx-edit", "Edit a caption, delete captions",
   "Double-click \"This line has no name.\", change it to \"This line was edited.\" and press Enter. Double-click it again, delete all its text and press Enter; press Esc. Click the caption \"Let us test the search.\" and click Delete caption; Ctrl+Z. Click the first caption, Shift-click the second, click Delete captions; Ctrl+Z.",
   "Double-click opens the text in a box with the hint \"Enter saves · Shift+Enter: new line\"; Enter saves and the preview shows the new text. An empty text is refused (\"A caption cannot be empty. Use \"Delete caption\" to remove it.\"). Delete caption removes one (\"Caption deleted.\"); with two selected the bar says \"2 captions\" and Delete captions removes both. Each Ctrl+Z brings them back in one step.", ""),
  ("tx-copy-dock", "Copy, save as text, at the right and below",
   "In the Text window click the three dots. Click Copy all text and paste into the note; then Copy with times and names and paste; then Save as text file… into clipforge-test-output. Then Show under the preview; then Show at the right and drag the window's left edge a little. Open Settings and read \"Where it opens\".",
   "The menu has Copy all text, Copy with times and names, Save as text file…, Export subtitles (.srt)…, Show at the right, Show under the preview. The pasted text has every caption; with times and names also the times and the speakers. A file \"Round 7 test.txt\" is saved. The window moves under the preview and back to the right, where its edge can be dragged; Settings shows the same choice.", ""),
 ]),
 ("P. Speech to text (needs a speech program; otherwise Not tested with the reason)", [
  ("sp-open", "Transcribe speech…: the speech program, or a plain explanation",
   "In \"Round 7 test\" click clip A and choose Text and speech > Transcribe speech…. Wait until \"Looking at what this computer has…\" is gone. Read the window. Do not click Download.",
   "A window \"Transcribe speech\" with a Language list. EITHER a line \"Uses: …\" names the speech program found (write it down) and a part \"Language pack\" lists Small, Medium and Large with their sizes and Download or Remove (\"Nothing is downloaded until you press Download.\"), with Use a model file I have… below, OR a box says in plain words that turning speech into text needs a speech program on this computer and none was found, and what to install. In the second case set this step to PASS if the text is clear, copy it, and set the rest of this group to Not tested with \"no speech engine\".", ""),
  ("sp-own", "Use a model file I have… (fixed in 1.17)",
   "Only if the owner has a speech model file on this PC (a file like ggml-base.en.bin or ggml-small.bin; ask where it is; otherwise set Not tested). In the Transcribe speech window leave Language on Automatic. Click Use a model file I have… and pick the file. Read the line under its name and look at the Transcribe button. If the file has \".en\" in its name, also choose another language (for example Russian) and read the line; then choose English again.",
   "The window shows \"Your own file: <name>\". The Transcribe button can be clicked now (in 1.15 it stayed grey). With an English-only file (\".en\" in its name) and Automatic it says \"This file understands English only, so the language was set to English.\"; for another language one line says why it cannot be used and what to choose instead. Your own file is used before the downloaded packs.", ""),
  ("sp-run", "Transcribe",
   "Only with a speech program. If neither a pack nor your own file is there, ask the owner which pack to download (suggest Small; NEVER Large) and click Download on that row only after a yes. Choose the language of file A and click Transcribe. Wait until it is finished. Meanwhile move the window and click the timeline.",
   "A progress bar with a Stop button; the app stays usable. At the end a message says \"Speech transcribed: … words. Read it in the Text window.\" Write down the number of words and how long it took. The Text window now has a switch with Captions and Transcript; in Transcript the word being spoken is marked while playing.", ""),
  ("sp-voices", "Separate voices are transcribed per speaker",
   "Only with a speech program and \"Round 7 two voices\". Open it, choose Text and speech > Transcribe speech… and transcribe. Open the Text window on Transcript.",
   "The voice files are read (not the muted camera sound) and the transcript shows who speaks: each speaker's name once above their paragraphs, in their colour.", ""),
  ("sp-captions", "Captions from speech…",
   "Only with a transcript, in \"Round 7 srt\" after transcribing its clip (or in \"Round 7 two voices\"). Choose Text and speech > Captions from speech…. Read the window, tick \"Replace the … captions that are already there\" if it is offered, and click Add captions. Play the first minute.",
   "The window \"Captions from speech\" says how many captions it adds, with Lines and \"Longest line: … letters\". Afterwards \"Added … captions from the speech. Undo takes them away.\" and the captions are on the timeline and in the Text window. Ask the owner to watch: each caption appears when its words are spoken and fits inside the picture (wrong names or numbers are normal: write down two examples).", "watch,listen"),
  ("sp-foreign", "A Russian or Hebrew clip",
   "Only with file R and a speech program. New project \"Round 7 language\" with R; transcribe it in its language; Captions from speech…; play 30 seconds and open the Text window.",
   "The letters show properly in the Text window and in the captions on the picture; Hebrew is laid out right to left with punctuation on the correct side. Ask the owner to read two captions.", "watch"),
  ("sp-fillers", "Remove filler words…: review, remove, check",
   "Only with a transcript. Choose Text and speech > Remove filler words…. Wait until \"Checking the picture around each cut…\" is gone. Click Light, Normal and Strong and copy the summary line of each. Press the play button of one row. Choose Light and click the button that removes them (if none were found, Cancel and say so). Play across two of the cuts.",
   "A window \"Remove filler words\" with Fillers of (a language), Select: Light / Normal / Strong, a summary line (\"… of … selected · saves …\") and a list with a tick box, the time, the filler in quotes and a play button (\"Play it as it would be after the cut\") per row; or \"No filler words were found in the transcript.\" After removing, the video is shorter by what the summary said. Ask the owner to listen at two cuts: the filler is gone and no word is chopped.", "listen"),
  ("sp-autocuts", "Automatic cuts…: Put back one, Put back all",
   "Choose Text and speech > Automatic cuts…. Read the window. Click Put back on one row. Then click Put back all. Close the window and press Ctrl+Z once, then Ctrl+Y.",
   "The window \"Automatic cuts\" has a line with the number of cuts and the time removed and one row per cut (fillers, silences, parts cut out) with Put back, plus Put back all and Close. Put back returns that part; Put back all returns everything and the video has its old length. Undo and redo of Put back all are one step each. With nothing left the menu item reads \"Automatic cuts… (nothing was cut automatically)\".", ""),
 ]),
 ("Q. Markers and shorts (the rest)", [
  ("sh-marker", "M, the flags, and the Good moments list",
   "In \"Round 7 test\" play from the start and press M once while it plays. Pause. Click a flag and press M again. Right-click a flag; Esc. Choose Clip > Good moments… and read the list; close it. Click an empty place and read the bottom of the side panel (\"Shorts and publishing\"). With two flags, put the playhead between them and choose Part > Select between the markers here; Esc.",
   "M drops a flag on the ruler, also while playing (\"Marked a good moment at …\" with Undo). M on a flag says \"There is already a marker here.\" The flag's menu has Make a short from here…, Make shorts from markers…, Good moments… and Remove this marker. The window \"Good moments\" lists the markers with their times and what is said there, each with \"Make a short around it\" and \"Remove the marker\". The side panel has Good moment marker (M), Good moments (…)…, Make a short from here…, Make shorts from markers… and Publishing notes…. Select between the markers here selects the stretch between the two flags around the playhead.", ""),
  ("sh-here", "Make a short from here…",
   "Put the playhead at 0:05 and choose Clip > Make a short from here…. Click 30 s, 45 s, 60 s and 30 s again, reading the line with the times. Leave \"Start and end at a pause\" and \"Short caption look\" ticked, tick \"Title at the top\" and type: Watch this. Name it \"Round 7 short\", click Make the short, then Open it. Play it and go back to the project list.",
   "A window \"Make a short\" with 30 s, 45 s and 60 s, a line \"From … to … · …\", the note that it is a new upright (9:16) project and this video is not changed, the three tick boxes and \"Name of the new project\". Then \"The short is ready\" with Stay here and Open it. The short is upright, about 30 seconds, has \"Watch this\" at the top for its whole length and captions in the Short caption look. Ask the owner to watch it once.", "watch"),
  ("sh-text", "A short from selected text",
   "Open \"Round 7 test\" and the Text window. Click the first caption, Shift-click the last, click Make a short from this…. Read the window, name it \"Round 7 text short\", click Make the short, then Stay here.",
   "The window \"Make a short\" has \"The selection\" selected (next to 30 s, 45 s, 60 s) and shows the selection's times and length; over 60 seconds it warns that Shorts, Reels and TikTok have their own limits. The new project is in the project list and \"Round 7 test\" is unchanged.", ""),
 ]),
 ("R. Publishing", [
  ("pb-notes", "Publishing notes with Copy buttons and chapters",
   "In \"Round 7 test\" choose File > Publishing notes…. Type a Title (Round 7 test video), a Description (two sentences) and Hashtags (clipforge test). Click the copy button next to Title and paste into the note. Click Chapters from titles / captions… and read what it says. Tick \"A different title for Shorts, Reels and TikTok\" and type a Short title. Click Copy title and description, paste, and click Done. Open History.",
   "A window \"Publishing notes\" says ClipForge does not post anything itself, with Title, Description, Hashtags and Chapters, each with its own copy button. Chapters from titles / captions… either fills Chapters with lines like \"0:00 …\" and says where they came from, or says plainly why not (\"This video is too short for chapters (each is at least 10 seconds).\"). Copy title and description copies title, description and hashtags in one go. History shows steps such as \"Publishing title\" and \"Hashtags\".", ""),
  ("pb-dest", "Where is it going? Destinations and warnings",
   "Press Ctrl+E. Click each choice in turn and read the line under the choices and any warning: YouTube, Shorts / Reels / TikTok, Instagram post, WhatsApp / Telegram, Podcast audio, Custom.",
   "YouTube: \"Wide 16:9, 1080p, full quality.\" Shorts / Reels / TikTok: upright 9:16, 1080p; for a video longer than 60 seconds a warning names the length and says 60 seconds is safe, \"Check the site.\" Instagram post: Tall 4:5 / Square 1:1. WhatsApp / Telegram: \"A small file (720p) that is quick to send.\", with a warning about 16 MB when the file would be bigger. Podcast audio: MP3 / M4A, no picture settings. Custom: Make, Video size, Full quality / Small file, Frames per second, Use graphics card. The window also shows the publishing notes' title and a Publishing notes… button. Warnings never block the export.", ""),
  ("pb-shape", "\"Make a copy in this shape\" or \"Export as it is\"",
   "In the Export window choose Shorts / Reels / TikTok (the project is wide). Click Export as it is and read the size; then Make a copy in this shape and read the size. Click Export and save as r7-short.mp4. Read the finished screen. Check the file (right-click > Properties > Details > Frame width / height). Look at the project list for the copy and at the shape of \"Round 7 test\".",
   "It offers Make a copy in this shape (a new project with a blurred background; this project stays as it is) and Export as it is. With Export as it is the size shown is wide; with the copy it is 1080 × 1920, and the exported file is 1080 wide and 1920 high. The finished screen says the copy \"Round 7 test - 9x16\" is in your project list; it is there, and \"Round 7 test\" itself is still wide.", ""),
  ("pb-several", "Export several… into one folder",
   "Choose File > Export several…. Tick YouTube, Shorts / Reels / TikTok and Podcast audio; leave \"Keep the shape copies as projects\" unticked. Read the file name under each tick. Click Export 3 files and choose a new folder clipforge-test-output\\kit7. Watch the progress. Then open the folder in Explorer, check the size of each video and open the text file.",
   "One progress bar with \"1 of 3: …\", \"2 of 3: …\" and one Cancel export; it ends with \"Files saved\". The folder holds \"Round 7 test - YouTube.mp4\" (1920 x 1080), \"Round 7 test - Short 9x16.mp4\" (1080 x 1920), \"Round 7 test - audio.mp3\" and \"Round 7 test - text.txt\". The text file has the title, description, hashtags and chapters from the notes, the music credits and a part for each file saying what to paste there. No shape copy was added to the project list.", ""),
  ("pb-finish", "The finished screen: Show in folder, Copy, Open upload page",
   "On the finished screen click Show in folder. Click Copy title and description and paste. Click Open YouTube upload page, look at the browser, and close the tab WITHOUT signing in or uploading. Click Done.",
   "Show in folder opens Explorer on the folder. The pasted text is the title, description and hashtags. The link line says ClipForge does not sign in or post; the button opens the upload page in the owner's own browser. ClipForge itself uploaded nothing.", ""),
  ("pb-listen", "The kit files look and sound right",
   "Play \"Round 7 test - Short 9x16.mp4\" and \"Round 7 test - audio.mp3\" from the kit7 folder for 30 seconds each.",
   "Ask the owner to watch and listen: the short is upright with the wide picture in the middle and a blurred copy above and below, captions and title readable, voice in sync; the MP3 has the same sound as the video.", "watch,listen"),
 ]),
 ("S. Export", [
  ("ex-full", "Full quality: what it says before and after",
   "Open \"Round 7 basics\". Press Ctrl+E, choose Custom; Make: Video, Full quality, Frames per second: Same as the clips. Copy the lines \"File size: about …\" and \"Will use: …\" into the note. Export as r7-full.mp4. Write down what the finished screen says.",
   "Before: an estimated file size and what will be used (graphics card or processor). It finishes with \"Video saved\", says what was used and \"Took …\". If the disk has too little free space it warns before starting.", ""),
  ("ex-watch", "The export looks and sounds like the preview",
   "Play r7-full.mp4 in Media Player from start to end and compare with the preview.",
   "Ask the owner to watch and listen: cuts, transition, Fill framing, overlay, filter, fades from and to black, fonts, Hebrew / Russian text, title animations all match the preview; voice in sync with the lips, music lower under speech if switched on, no clicks or gaps at the cuts.", "watch,listen"),
  ("ex-small-fps", "Small file, and frames per second",
   "Export once with Small file as r7-small.mp4. Then with Full quality and Frames per second 25 as r7-25fps.mp4 (and 60 as r7-60fps.mp4 if the owner films sport). Compare the file sizes; check the frame rate (right-click > Properties > Details > Frame rate).",
   "The small file is clearly smaller than r7-full.mp4 and has the same length. The 25 file reports 25 frames per second (the 60 file 60) and has the same length.", ""),
  ("ex-sound", "Sound only: M4A and MP3",
   "Ctrl+E, Custom, set Make to the sound-only M4A choice and export as r7-sound.m4a; then MP3 as r7-sound.mp3. Play both.",
   "The picture settings are hidden for sound only. Both files are made with the video's length. Ask the owner to listen: the same mix as the video.", "listen"),
  ("ex-gpu", "Graphics card on and off",
   "Ctrl+E, Custom: switch Use graphics card (faster) off, export as r7-cpu.mp4 and note \"Took …\"; switch it on again and compare with r7-full.mp4's time.",
   "With the switch off it says it used the processor; with it on, the graphics card (or it says that it fell back to the processor and why). Both files play. Write down both times.", ""),
  ("ex-quit", "Quit during an export",
   "Start one more Full quality export (r7-quit.mp4) and press Alt+F4 while it runs. Choose to keep working and let it finish.",
   "Quitting during an export asks whether to cancel the export or keep working; keep working lets the export finish, and the file plays.", ""),
  ("ex-long", "Export the long project (start it last and let it run)",
   "Do this as the LAST export of the round. Open \"Round 7 long\". Press Ctrl+E, choose Custom, Small file, and export as r7-long.mp4. Leave the computer alone. Write down the project's length, the time it took and the file size. Afterwards choose Help > Copy version info and paste it into the note.",
   "The progress moves steadily to 100 % without standing still for minutes, the window can be moved and Cancel export is there, and no sound waves or thumbnails are drawn meanwhile. It finishes saying what was used and how long it took. The file has the project's length and plays to the end. Ask the owner to watch the last minute: picture and sound still in sync, the two voices as in the preview.", "watch,listen"),
 ]),
 ("T. Connect to Claude page", [
  ("cl-page", "Status lights and Details",
   "Choose Help > Connect to Claude…. Read the page. Open every \"Details\" line. Do NOT click Connect, Disconnect or Replace with this version yet.",
   "A card \"The Claude helper is installed\" with \"Version 1.17.0 (build 136). ClipForge refreshes it every time the app starts.\", the helper's folder (it ends in ClipForge\\claude, under the user's app data) and \"Not in use right now …\" or \"In use by … now · last action …\". A card for Claude Desktop and one for Claude Code, each with a light and one status line: \"Connected (ClipForge 1.17.0)\" (green), \"Connected to an old copy at …\" (amber), \"Not connected\" or \"… not found\" (grey). When an old copy is connected, the ONE highlighted button is Replace with this version, with a line that says what it does (and Disconnect instead next to it). Copy both status lines into the note.", ""),
  ("cl-test", "The Test button",
   "Click Test and wait. Open the Details under the result. Click Check again.",
   "\"Testing…\" for up to a minute, then a green line \"PASS: the helper works by itself (ClipForge 1.17.0).\" with Details that hold the self-test table. A red line starting with \"FAIL:\" is a FAIL: copy the line and the Details.", ""),
  ("cl-connect", "Connect or Replace (only if the owner agrees)",
   "Ask the owner: \"May I press Connect (or Replace with this version) for Claude Desktop and for Claude Code?\" Only for a row the owner says yes to and that does not already say Connected (ClipForge 1.17.0): click that button. Also click Copy under \"Or paste this one line into a terminal yourself:\" and paste the line into the note. NEVER click Disconnect. If the owner says no, or both rows are already connected, set Not tested and say which.",
   "After the click the row's light is green and says \"Connected (ClipForge 1.17.0)\". The card \"After connecting: close and reopen Claude once\" explains why. The copied line starts with \"claude mcp add\" and ends with the helper's path in the ClipForge\\claude folder. (The Claude tools themselves are tested with the separate document \"Claude control test 6\".)", ""),
 ]),
 ("U. Updates and Help", [
  ("up-check", "Check now says this is the newest version",
   "On the project list choose Help > Check for updates…. Then open Settings and click Check now. Do NOT click Update if a newer version is offered: tell the owner.",
   "Both answer with the same plain message: \"You have the newest version (1.17.0 (build 136)).\" If a newer version is offered, write it down and set Partial.", ""),
  ("hp-search", "Help search, also with a typo",
   "Press F1. Search for each of: settings, suggestion, menu, short, chapters, who is speaking, feedback, overlay, snap, fade. Then with a typo: sugestion.",
   "Each search shows the fitting article first or near the top (\"Settings\", \"Suggestions\", \"Menus: where everything is\", \"Make a short\", \"Publishing notes: title, description, hashtags, chapters\", \"See who is speaking\", \"Send feedback\", \"Overlay: picture-in-picture, side by side, cut-aways\", \"Snapping on the timeline\", \"Fade in from black, fade out to black\"). The typo still finds \"Suggestions\" (or offers \"Did you mean\").", ""),
  ("hp-pages", "Keyboard shortcuts, What's new, the menus article, Licences",
   "Choose Help > Keyboard shortcuts and read the list. Choose Help > What's new and read the top. Open the article \"Menus: where everything is\". Open Settings > Licences and close it.",
   "Keyboard shortcuts lists I / O as the start and the end of a part and Q / W as start / end of the clip at the playhead, with J / K / L, M, Ctrl+D and the rest. What's new starts with 1.17.0. The menus article lists ten menus including Part, with the same items as the app. Licences opens a list. Write down any sentence that does not match the app.", ""),
  ("hp-tour", "The tour",
   "Choose Help > Show the tour and go through it to the end.",
   "The tour runs in steps over the real buttons, each step pointing at the right place, and ends without leaving anything changed in a project.", ""),
 ]),
 ("V. The end", [
  ("end-saved", "Everything was saved",
   "Choose File > Exit. Start ClipForge. Open \"Round 7 test\", \"Round 7 basics\", \"Round 7 two voices\" and \"Round 7 long\" one after the other and look through each.",
   "Each opens with everything as you left it: the quiet parts, the slow part, markers, captions, publishing notes; sound tracks, overlay, filters, fades, titles; Only when speaking on; the long clip with both voices. No clip says Missing.", ""),
  ("end-perf", "The performance log at the end of the round",
   "Choose Help > Copy version info and paste ALL of it into the note. Then fill in the Summary: first the long file (did it stall: yes / no; the longest gap; with sound waves on and off), then the worst problems.",
   "The text has the version line, the folder, the update log's last lines and the performance log with its \"longest gap\". This is what the maker needs if anything was slow.", ""),
 ]),
]

INSTR_7 = """You are testing ClipForge 1.17.0 (build 136), a video editor, on the owner's Windows PC. Problems are expected; your job is to find them and write them down precisely. This round goes through EVERY feature, with the new and risky things first: the in-app update, a long video that made an earlier version stop answering on this PC, everything version 1.17 changed, then all the rest. It has __NSTEPS__ numbered steps in __NGROUPS__ groups (A to V). The Android phone has its own page (Round 7 phone) and the Claude tools their own document (Claude control test 6).

MEDIA FOLDER: <owner fills in>

BEFORE YOU START
- Fill in "Device" (for example "Windows 11 laptop, RTX 4070") and "Tester".
- Do group A first: it updates the app. Then fill in "Version shown in the app" (Help > About ClipForge > Copy version info, paste). If it does not match the build named at the top of this page (a red warning appears), tell the owner and say so in the Summary.
- Test files are in the MEDIA FOLDER named above. Look into it and decide which file is which; ask the owner if something is missing. Do not download files from the internet. You need:
  L. the LONG talking video of 20 to 30 minutes (the recording that froze, if the owner has it), and LV1 + LV2: the two voice files recorded for it (one per speaker);
  A. a talking video, 1-3 minutes, filmed wide (landscape), with some pauses;
  B. a short video, 10-40 seconds (shorter than 45 seconds);
  P. a photo;
  M. a music file (MP3 or M4A) that is LONGER than video A;
  S. a small clip from a phone or a chat app (smaller than 720p);
  optional: V + W, a short video with one sound file per speaker; R, a clip in which someone speaks Russian or Hebrew; a speech model file (ggml-….bin).
- The easiest way to add files without the Windows file window: Add > Add from a folder path…, paste the path, tick the files.
- Do the groups in order: later steps build on the projects made earlier ("Round 7 long", "Round 7 test", "Round 7 two voices", "Round 7 basics"). If time runs out, groups A to H matter most; say in the Summary where you stopped.
- A thin line with a tip and a button may appear under the top bar at any time. That is a suggestion. Outside the groups that test them leave it alone unless a step says so.

IF CLIPFORGE STOPS ANSWERING (the most important finding of this round)
- Write down the time, the step, and what was on screen ("Saving…", "Drawing sound… 1 of 3", "Loading the video…").
- Wait two minutes. If it comes back, go on. If not, close it (Task Manager if needed) and start it again.
- In both cases choose Help > Copy version info right away and paste ALL of it into the Crash box: it carries the performance log, also of the run that stopped. Do the same whenever the line "Sound waves were paused to keep ClipForge responsive" appears.
- Then check whether the last thing you did was saved, and go on with the next step.

RULES
- Each step has "Do" (exact actions) and "Expected" (what should happen). Do the actions exactly, then compare with Expected.
- For each step choose a Result and write a Note. Where a step says to copy a text or write down a number, put it in the note.
- Result meanings: PASS = you saw exactly the expected result. FAIL = something was wrong (write what you did, what happened, and what you expected). Partial = part of it worked (say which part). Not tested = you could not do it (say why, for example "no speech engine" or "no voice files"). Needs the owner = only a person can judge it and the owner was not available.
- Steps tagged "ask the owner to listen" or "ask the owner to watch" depend on hearing, or on lip sync and movement that screenshots cannot show. Do the actions and check everything you can see. Then ask the owner in the chat, for example: "Please play the preview from 0:05 and tell me whether the voice matches the lips." Write the owner's answer in the note starting with "Owner:", and set PASS or FAIL from it. If the owner is not available, set Needs the owner. Never judge sound yourself.
- Buttons and menu items are written here as the app shows them; " | " in a list of menu items stands for a dividing line. If a name on the screen is different, or an item is missing or greyed out when the step expects it to work, write down exactly what you see.
- If a drag does not work for you, try twice. Then use the keys, the menu bar or the panel buttons if the step offers them; otherwise set Needs the owner and write that you could not perform the drag (it may still work for a human).
- NEVER delete, move or rename the owner's files or the owner's own projects. Inside ClipForge only delete things this test made. Save every export into a folder named clipforge-test-output inside the MEDIA FOLDER, with the file name the step gives (for example r7-full.mp4).
- Ask the owner before you press Update, Send (feedback), Connect or Replace with this version. Never press Disconnect in this round.
- Speech to text needs a speech program on the computer and usually a language pack (Small about 140 MB, Medium about 470 MB, Large about 1.6 GB). Do not install programs. Click Download only for the pack the owner agreed to, and NEVER download a Large pack.
- Do not guess. Only mark PASS for what you actually saw, or for what the owner told you they heard or saw.
- This page keeps your answers in this browser as you go. When finished, fill in the Summary box (the long file first, then the most important problems), then click "Download filled checklist" and give the downloaded file (ClipForge-Test-Round-7-results-….html) to the owner, who sends it back."""

# ---------------------------------------------------------------- round 7, phone (1.17.0)
# The Android phone for 1.17.0 (build 136), updated in the app, driven by an
# AI agent on the Windows PC through "Link to Windows" screen mirroring.
# EVERY phone feature, the new and risky things first: the in-app update, a
# long video, Select part with its bar and Actions sheet, Only when
# speaking, shorts from markers, Send feedback; then the layout of 1.15 and
# every older feature (rounds 4-phone and 6-phone), export and share. No
# speech to text and no Claude control: those are computer only. Names are
# the phone UI's own: lib/ui/editor/tools.dart, action_sheets.dart
# (moreGroups), editor_screen.dart (the project menu), part_actions.dart
# (PartBar phone, the part sheet), lib/ui/home/home_screen.dart,
# lib/ui/feedback/feedback_screen.dart, lib/ui/update/update_ui.dart.
STEPS_7P = [
 ("A. Update", [
  ("p-before", "Before the update: which version is on the phone",
   "Open ClipForge on the phone. Read the small grey line at the bottom of the project list and write it down. Look at the top of the list for a line \"Version 1.17.0 is available\". If it is not there and the app is older than 1.17.0, tap the three dots (More) at the top right > Check for updates and look again. Do NOT tap Update yet.",
   "On a phone that still has 1.15 or 1.16: a quiet line \"Version 1.17.0 is available\" with What's new, Update, Later and Skip this version. If the app already shows 1.17.0 (build 136), set Not tested for this step and the next and write how it got there (ask the owner).", ""),
  ("p-update", "The in-app update to 1.17.0",
   "Ask the owner: \"May I tap Update now?\" After a yes tap Update, read the window and tap Download and update. Wait for the download. When Android asks to confirm the update, tap Update / Install there (the first time Android may say that installing from ClipForge is not allowed: tap Settings, switch on \"Allow from this source\", go back and confirm). Wait until it is installed and open ClipForge again.",
   "The window explains that ClipForge downloads the new version, checks it and hands it to Android, which asks you to confirm, and that your projects and videos stay as they are. It shows \"Downloading… …%\" and \"Checking the download…\", then \"Android is now asking you to confirm the update. If nothing appeared, tap Update again.\" After Android's own install the app opens as 1.17.0. If it says \"The update did not work.\", tap Copy details, ask the owner to paste them into the chat, and set FAIL.", ""),
  ("p-version", "The app shows 1.17.0, build 136",
   "Read the grey line at the bottom of the project list. Tap the three dots at the top right, read the list, tap About ClipForge, then Copy version info. Type or paste the version line into \"Version shown in the app\" at the top of this page. Close About.",
   "Both show version 1.17.0 and build 136, the same as named at the top of this page. No red warning appears under the version box. The three dots list: Settings, What's new, Check for updates | Send feedback, About ClipForge, Copy version info.", ""),
  ("p-updated", "The result of the update",
   "Look at the top of the project list. If a line \"Updated to 1.17.0\" is there, tap What's new, go back, then tap the cross of the line. (It appears once. If the owner already closed it, ask what it said and set Not tested with the answer.)",
   "One quiet line \"Updated to 1.17.0\" with What's new and a cross. What's new opens Help on the page that starts with 1.17.0. No message says that an update did not work. (The note \"Two keys changed\" is for computers: it should NOT appear on the phone. Write it down if it does.)", ""),
  ("p-keeps", "The update kept the projects",
   "Read the project list. Open the newest project from before the update, tap Play for 5 seconds, tap the back arrow.",
   "The projects from before the update are listed; the one you opened shows its clips with pictures and plays. No clip says Missing.", ""),
 ]),
 ("B. A long video on the phone", [
  ("p-long-import", "Import the longest video",
   "Ask the owner which video on the phone is the longest (20 minutes or more is best; otherwise the longest there is, and write its length down). Tap New project, choose it in the picker and confirm. Count the seconds. Watch the preview, the save sign at the top and the timeline for two minutes. Tap the name at the top and rename the project to Round 7 phone long.",
   "The clip is on the timeline within a few seconds with the right length. The preview says \"Loading the video…\" until the first picture is there. The save sign shows saved within about 5 seconds. \"Drawing sound… 1 of 1\" (or \"Drawing sound…\") with a small cross shows at the timeline and goes away later: write down how long it took. FAIL if the app stops reacting to taps for more than a few seconds, or if the line \"Sound waves were paused to keep ClipForge responsive\" appears: then do the step \"The performance log\" at once.", ""),
  ("p-long-use", "The app answers while the sound waves are drawn",
   "While \"Drawing sound…\" is shown if you can: drag the timeline to the middle and to the end, tap Play, wait 5 seconds, tap Pause, tap Split and Undo, tap the three dots at the top and close the list. If \"Drawing sound…\" is still there, tap the cross next to it.",
   "Every tap answers within about a second (mirroring adds its own delay: ask the owner how it felt on the phone itself). While the video plays no new sound wave is started. The cross stops the drawing at once and the rows stay plain.", ""),
  ("p-long-reopen", "Close and reopen keeps the import",
   "Go to the project list. Close ClipForge completely (recent apps, swipe it away). Open it again and open \"Round 7 phone long\". Play 10 seconds at the start and near the end.",
   "The project is there with the long clip (it was not lost) and plays at both places. Ask the owner to watch on the phone: picture and voice in sync.", "watch,listen"),
  ("p-perf", "The performance log (also at every stall)",
   "On the project list tap the three dots > Copy version info. Paste it into the note if copying between phone and PC works; otherwise ask the owner to paste it into a notes app, read the last 15 lines and the line that starts with \"Performance log\", and type those into the note.",
   "\"Version info copied.\" The text has the version line and a part \"Performance log (longest gap … ms):\" with lines like \"project opened\", \"save start\" / \"save end\", \"sound picture … start\" / \"end\", \"gap … ms\". No file names and no project names are in it. Write down the \"longest gap\" number.", ""),
 ]),
 ("C. Select part (new in 1.17)", [
  ("p-new", "Make the test project",
   "Tap New project. In the phone's picker choose video A (a talking video filmed wide) and confirm. Rename the project to Round 7 phone. Tap Add > Videos or photos and add video B. Tap Add > Title, type Round 7 and close the sheet. Add three captions with Add > Caption (move the playhead first): at 0:02 \"Sam Taylor: Hello from the phone.\", at 0:06 \"Alex K: Hello back.\", at 0:10 \"Alex K: Let us test the search.\" Add music with Add > Music or sound (My files if the phone has a music file longer than the video, otherwise Find free music, search piano, Use; choose Music if it asks \"What is this sound?\").",
   "The editor shows A and B with clip pictures, the title, three captions and the music on a sound row. The top shows the back arrow, the name, the save sign, Undo, Redo, Export and three dots.", ""),
  ("p-part-select", "More > Select part: the handles and the bar",
   "Tap an empty place so nothing is selected. Move the playhead to 0:05. Tap More, read the heading PART and tap Select part. Read what appears between the timeline and the bottom bar.",
   "A part of 5 seconds starting at the playhead is highlighted across every row, with two handles (tabs) on the time ruler. A bar shows the start, the end and the length, arrows next to the start and the end, a button that reads \"Step 1 frame\" or \"Step 0.1 s\", a button Actions and a cross. Nothing is changed in the video yet and Undo did not get a new step.", ""),
  ("p-part-nudge", "Move the edges: arrows, the Step button, the handles",
   "Tap the arrow that moves the END later three times. Tap the Step button (it changes between \"Step 1 frame\" and \"Step 0.1 s\") and tap the same arrow three times again. Tap the arrow that moves the START earlier twice. Then drag the right handle on the ruler about 3 seconds to the right (through mirroring a drag may fail: try twice, then set Needs the owner for the drag only).",
   "Each tap moves that edge by one frame or by 0.1 s, as the Step button says, and the times and the length in the bar change with it. Dragging a handle moves that edge; it snaps to cuts, to where speech starts and stops, to markers and to the playhead. Dragging the timeline with one finger still scrolls it.", ""),
  ("p-part-ways", "The other ways to select, and the cross",
   "Tap the cross of the bar. Tap the three dots at the top > Select part; tap the cross. Long-press an empty part of the timeline, read the list and tap Select part; tap the cross. Tap clip B, tap More and under PART tap the line that selects this clip's time. Tap More again and read PART. Tap the cross.",
   "The cross clears the part: band, handles and bar are gone. Select part is in More (under PART), in the three dots at the top and in the list of an empty place. With a clip selected PART also has \"Select this clip's time\", which selects exactly clip B. Once the sound was drawn and talking was found, PART also lists Select this speaker's turn and Select the pause here; with markers, Select between the markers here; with a part selected, Clear the part.", ""),
  ("p-part-actions", "Actions: the rows and what can be done",
   "Select a part from about 0:04 to 0:08 (Select part, then the arrows). Tap Actions. Read the sheet from top to bottom. Tap \"Only this\" on the row of the music, look at the tick boxes, then tick every row again.",
   "A sheet with the rows first (the video, each sound row, titles and captions, the overlay row when there is one), each with a tick box, all ticked, and \"Only this\" next to each; then the actions, each with a line saying what it changes: Cut out, Delete and leave a gap, Silence, Lower volume…, Speed…, Clean up sound here, Make a short from the part…, Duplicate the part, Title over the part, Good moment marker at its start. An action that cannot be used with the ticked rows is grey and says why (\"Not now: …\").", ""),
  ("p-part-silence", "Silence on the video row only",
   "Select a part of about 2 seconds where someone talks. Tap Actions, tap \"Only this\" on the Video row, tap Silence. Read the message. Close the part with the cross and play across the place.",
   "A message like \"Silenced 2.0 s on Video.\" Nothing moves. The slim sound wave of the clip is flat there. Ask the owner to listen on the phone: the voice is silent on that part while the music plays on, without a click; before and after it is normal.", "listen"),
  ("p-part-lower", "Lower volume… on the music row",
   "Select another part of about 3 seconds. Tap Actions, \"Only this\" on the music's row, Lower volume…. Read the window, choose 12 dB and confirm. Play across it. Then tap the music, open its settings (Edit) and look for \"Quiet parts\"; tap Remove on the part and tap Undo.",
   "A window \"Lower volume\" with 6, 12 and 18 dB and a slider. Afterwards a message like \"Lowered 3.0 s by 12 dB on Music.\" The music is quieter on that part only. The music's settings list it under Quiet parts with Remove; Remove gives the sound back and Undo makes it quiet again. Ask the owner to listen.", "listen"),
  ("p-part-cut", "Cut out, and why it needs every row",
   "Write down the length of the video. Select a part of 3 seconds with NO caption on it. Tap Actions, untick the music's row and read the line of Cut out. Tick every row again and tap Cut out. Read the message. Tap Undo, then Redo.",
   "With a row unticked Cut out is grey and says why (it removes time, so it needs every row; otherwise lips and voice would no longer match). With every row it says \"Cut 3.0 s out of everything.\"; the video is 3 seconds shorter and everything after the part moved up on every row. Undo and Redo are one step each.", ""),
  ("p-part-gap", "Delete and leave a gap",
   "Select a part of 2 seconds. Tap Actions, \"Only this\" on the music's row, Delete and leave a gap. Look at the music. Tap Undo.",
   "The part is removed from the music and a gap is left; the music before and after it stays where it was and nothing else moved (\"Deleted that part on …. Nothing moved.\"). Undo brings it back.", ""),
  ("p-part-speed", "Speed… for a part",
   "Tap clip B, More > PART > Select this clip's time, and move the end 2 seconds earlier with the arrows (Step 0.1 s). Tap Actions > Speed…. Read the window, tap 0.5×, 0.25× and 2× and read the line and the tick box each time. Choose 0.5× and confirm. Play across it.",
   "A window \"Speed of this part\" with 0.25×, 0.5×, 1.5×, 2×, a line saying how long the part will take, the note that music and other sound keep their speed and place, and \"Mute this part's own sound\" (ticked by itself below 0.5×). Afterwards that part of B plays in slow motion and the music did not move. Ask the owner to watch the phone itself (mirroring stutters).", "watch"),
  ("p-part-more", "Short, duplicate, title and marker from a part",
   "Select a part from 0:02 to 0:10. Tap Actions > Good moment marker at its start. Select the part again if it is gone, Actions > Title over the part. Again Actions > Duplicate the part; tap Undo. Again Actions > Make a short from the part…, name it Round 7 phone part short, tap Make the short and Stay here.",
   "A flag at the start of the part (\"Marked … as a good moment.\"); a new title that starts and ends with the part; \"A copy of the part is right after it (now selected).\" and the video is longer; a new upright project in the project list while this one is unchanged.", ""),
 ]),
 ("D. Only when speaking (new in 1.17)", [
  ("p-ows-none", "Without a voice track it says why",
   "In \"Round 7 phone\" tap an empty place, tap More and read under SOUND the line Only when speaking…. Tap it if it can be tapped.",
   "Without a voice track the line is grey with \"Not now: …\" and its reason, or a window says that there is no speech track yet and to add a voice. Nothing is changed.", ""),
  ("p-ows-on", "With voice files: switch it on",
   "Only if the phone has a video with a sound file per speaker (ask the owner; otherwise set Not tested). New project \"Round 7 phone voices\" with the video; Add > Voice recording, pick the voice files, name the speakers Sam Taylor and Alex K, tap Add and line up. Wait until \"Drawing sound…\" is gone. Tap More > Only when speaking…, switch it on for both voices, leave \"A little room sound (−18 dB)\", close. Play 30 seconds where the speakers take turns.",
   "The voices are lined up, each on its own row named after the speaker. The window \"Only when speaking\" has a switch per voice track and, under \"Between the turns\", A little room sound (−18 dB), More room sound (−12 dB), Hardly any (−30 dB) and silence. With it on, each voice's wave is small where that speaker is silent. Ask the owner to listen with headphones on the phone: the other person's voice is much quieter under each speaker and no word is cut off.", "listen"),
 ]),
 ("E. Shorts from markers (fixed in 1.17)", [
  ("p-shm-short", "Two markers in a short video",
   "New project with video B only (shorter than 45 seconds), rename it Round 7 phone markers. Move the playhead to one third and tap Add > Good moment marker; to two thirds and tap More > Good moment marker. Tap More > Shorts and good moments > Make shorts from markers…. Read the title and the two lines with times. Tap Make them, then OK (or Open the first and go back). Count the new projects in the project list.",
   "The window is titled \"Make 2 shorts from the markers?\"; the two parts are DIFFERENT and neither is the whole video (in a video under a minute each is about half of it, at least 8 seconds). Afterwards \"2 shorts are ready\" lists two projects, and the project list has exactly two new ones. If one could not be made it says \"1 of 2 shorts was made\" with \"Not made: …\": copy it.", ""),
  ("p-shm-close", "Two markers close together",
   "Open \"Round 7 phone markers\". Tap the three dots > Markers and remove both markers. Add a marker at one third and another 2 seconds later. Open Make shorts from markers… again. Read the note and the choice; leave \"One short covering both\" and make it. Count the new projects.",
   "The window says \"The two markers are close together: their shorts would show mostly the same part.\" with One short covering both (ticked) and Two shorts. The title reads \"Make 1 short from the 2 markers?\" and exactly one new project is made (\"The short is ready\").", ""),
 ]),
 ("F. Send feedback", [
  ("p-fb-page", "The page, \"What is sent\" and the details tick box",
   "On the project list tap the three dots > Send feedback. Read the page. Tap Problem, Idea, Praise, Question. Type: TEST from Round 7 phone, please ignore. Leave the e-mail address empty. Read the box \"What is sent\". Find \"Include details about how ClipForge ran\": check it is OFF, tick it, read \"What is sent\" again, and look there for the names of your projects or videos. Go back without sending; open a project and tap its three dots > Send feedback.",
   "A page with the four kinds, the message box, \"Your e-mail address (optional)\" and a box \"What is sent\" with exactly what goes (kind, message, the app's version and build, the system's name and version) and the sentence that nothing about your projects, file names, videos, photos or music is ever included. The tick box is off; ticked, the performance-log lines are shown in \"What is sent\", with no file or project name in them. The keyboard does not hide the box being typed in. Your text is still there when the page is opened again, from either place.", ""),
  ("p-fb-send", "Send one test message (only if the owner agrees)",
   "Ask the owner: \"May I send one test message from the phone, with the details ticked?\" Only after a yes tap Send once. Otherwise set Not tested.",
   "\"Sent. Thank you!\" and the draft is gone. Without a connection it says \"The message could not be sent. Check the internet connection and try again.\" and offers Open the feedback page in the browser and Copy my message; the text stays.", ""),
 ]),
 ("G. The bottom bar, Add and More", [
  ("p-bar", "The bottom bar: Add, Text, Split, More",
   "Open \"Round 7 phone\". Tap an empty place so nothing is selected. Read the bar at the bottom. Move the playhead to the middle of A and tap Split, then Undo.",
   "With nothing selected the bar has exactly four buttons: Add, Text, Split, More. Split cuts A into two pieces at the playhead; Undo makes it one again.", ""),
  ("p-add", "The Add sheet: every entry",
   "Tap Add and read the list. Tap Voice recording and cancel the picker. Tap Add > Overlay (picture-in-picture) and cancel. Tap Add > Subtitle file (.srt) and cancel.",
   "A sheet \"Add\" lists, each with an icon and one line of explanation: Videos or photos, Music or sound, Voice recording, Title, Caption, Subtitle file (.srt) (new in 1.17), Overlay (picture-in-picture), Good moment marker; one sentence at the bottom says where videos and photos go in. Each picker opens; cancelling adds nothing.", ""),
  ("p-more", "More with nothing selected",
   "Tap an empty place, then More. Read the sheet from top to bottom (scroll it) and swipe it down.",
   "A sheet \"More\" with small headings. CLIP: Trim start to here, Trim end to here, Freeze frame, Remove silences, Good moment marker, Make a short from here, Shorts and good moments. PART: Select part (and the quick selections that are possible). SOUND: Add sound track, Lower music under speech, Only when speaking…, Copy music credits. TEXT: Text, Find in the text, Subtitle file (.srt), Export subtitles (.srt). EDIT: History. A line that cannot be used now is grey and says why underneath (\"Not now: …\"). Nothing about Transcribe speech or Captions from speech is listed.", ""),
  ("p-clip", "A clip selected: its tools, More, and the + next to Play",
   "Tap clip A. Read the bottom bar. Tap More and read the sheet. Tap Duplicate in it, then Undo. Tap the + next to the Play button, read, close. Tap Done.",
   "Bar: Done, Split, Speed, Look, Sound, More, Delete. More: CLIP: Crop and position, Trim start to here, Trim end to here, Freeze frame, Remove silences, Move earlier, Move later, Make a short from here. PART: Select part, Select this clip's time. EDIT: Duplicate, Copy settings, Paste settings, History. SOUND: Separate sound, Put sound back, Lower music under speech. TEXT: Text. Grey lines say \"Not now: …\". The + opens the Add sheet (videos and photos go in after the selected clip). Done clears the selection. Write down anything missing or extra.", ""),
  ("p-trim", "Trim start to here, Trim end to here; trim by dragging",
   "Tap clip A, move the playhead 3 seconds into it, More > Trim start to here. Move the playhead to 3 seconds before the end of A, More > Trim end to here. Tap Undo twice. Then drag the right edge of A about 2 seconds to the left (try twice through mirroring).",
   "Trim start to here makes A start at the playhead; Trim end to here makes it end there; the clips after it move up; each Undo restores one. Dragging an edge trims too (if the drag fails, set Needs the owner for the drag).", ""),
  ("p-hold", "Hold: the action list; hold and drag: move",
   "Long-press clip B without moving, read the list, close it. Long-press the title on the timeline, read, close. Long-press an empty part of the timeline, read, close. Then long-press clip B and, still holding, drag it in front of A; let go; Undo. (Try twice; otherwise set Needs the owner.)",
   "Holding opens a sheet titled Video clip with: Split, Trim start to here, Trim end to here, Duplicate, Copy settings, Paste settings, Freeze frame, Remove silences, Crop and position, Rotate right, Separate sound, Put sound back, Move earlier, Move later, Make a short from here, Delete (and selecting its time). The title's sheet has Edit, Duplicate, Text, Delete. An empty place (\"At 0:…\") has Videos or photos, Music or sound, Voice recording, Title, Caption, Overlay (picture-in-picture), Good moment marker, Split, Make a short from here and Select part. Holding and dragging still moves the clip.", ""),
  ("p-title-sel", "A title or caption selected",
   "Tap the title on the timeline. Read the bar. Tap More, read, close. Tap Edit, change the text to Round 7 phone, close the sheet. Tap Done.",
   "Bar: Done, Edit, Duplicate, More, Delete. More: TEXT: Text, Find in the text, Export subtitles (.srt); PART; EDIT: Duplicate, History. Edit opens the title's settings as a sheet; the new text shows in the preview.", ""),
 ]),
 ("H. The menu at the top, shape, fades", [
  ("p-top", "The three dots at the top of a project",
   "Tap the three dots at the top right of the editor. Read the list. Tap History, read, close it.",
   "The list has: Shape and size, Fade in and out, Select part, Publishing notes, Text, History, Markers, Settings | Help, Send feedback, each with an icon. History opens a sheet with your changes by name, newest first; tapping an older one goes back to that point.", ""),
  ("p-shape", "Shape and size",
   "Tap the three dots > Shape and size. Read the sheet. Tap 1080p (Full HD). Tap \"Which shape should I use?\" and go back from Help. Tap 9:16 upright and close the sheet.",
   "SHAPE: Original (as the first clip), 9:16 upright, 16:9 wide, 1:1 square, 4:5 upright; VIDEO SIZE: Same as the first clip, 720p, 1080p (Full HD), 4K; a tick marks the current ones. The question opens the help article about shapes. The preview becomes upright.", ""),
  ("p-fades", "Fade in and out",
   "Tap the three dots > Fade in and out. Set Fade in from black and Fade out to black to about 2 s each. Close the sheet. Play the first 3 seconds.",
   "The video comes up from black at the start. Ask the owner to watch the phone.", "watch"),
 ]),
 ("I. Picture and titles", [
  ("p-look", "Fit, Fill, Blur and filters; Copy and Paste settings",
   "Tap clip A, tap Look. Choose Fit, Blur, then Fill. Tap Warm, Cool, Black & white, Vintage, Vivid, None in turn, then Vintage. Close the sheet. More > Copy settings. Tap clip B, More > Paste settings.",
   "Fit shows the whole wide picture with bars, Blur fills the bars with a blurred copy, Fill fills the upright frame. Each filter changes the preview at once. After pasting, B has the same look and fit and keeps its own length.", ""),
  ("p-crop", "Crop and position",
   "Tap clip A, More > Crop and position. Drag a corner of the frame inwards, then drag inside the frame (try twice). Tap 1:1, 9:16, Free, Original. Tap the rotate and flip buttons once each, then Reset crop and position. With Fill, move Left – right to keep the person in the middle. Tap Done.",
   "The sheet shows the whole picture with a frame and grips and the outside dimmed, and does not cover the frame. 1:1 and 9:16 keep their shape; rotate turns a quarter turn, flip mirrors, Reset puts everything back; Left – right chooses which part fills the frame. (If the drags fail through mirroring, set Needs the owner for the drags.)", ""),
  ("p-speed", "Speed, freeze frame, transition",
   "Tap clip B, tap Speed, choose 0.5× then 2× then 1×. More > Freeze frame with the playhead in the middle of B; Undo. Look in B's tools for the transition and the clip's fades, choose Crossfade and play across the start of B.",
   "Speed changes the clip's length and pace. Freeze frame holds the picture under the playhead as a new item; Undo removes it. The transition changes how A turns into B. Ask the owner to watch the phone and to listen: at 0.5× the voice is slower, not deeper.", "watch,listen"),
  ("p-overlay", "Overlay (picture-in-picture), and its More",
   "Tap Done. Move the playhead to 0:03. Tap Add > Overlay (picture-in-picture) and pick video B. Tap the overlay on its row; read the bar; open Layout: another corner, Size about 50 %, White frame on; try Side by side and Full screen, then Picture-in-picture again. Tap More and read it. Play across the overlay.",
   "B appears small in a corner from 0:03 on an Overlay row above the clips. Corner, Size, White frame and the layouts change it at once. An overlay has More now (new in 1.17): CLIP: Crop and position, Rotate right; PART; EDIT: History. Ask the owner to watch the phone: both videos move.", "watch"),
  ("p-title", "Title: fonts, styles, position, animation; Hebrew and Russian",
   "Tap the title, tap Edit. Tap each Font (Classic, Modern, Elegant, Handwritten), two Styles, switch on Outline, tap Position Top and Lower third, set Appear to Pop. Close. Then Add > Title and paste or type: שלום עולם / Привет, мир . Play from 0:00.",
   "Fonts and styles change the letters; Outline draws a line around them; Top / Lower third move the text; the sheet scrolls and the keyboard does not hide the text box. Hebrew and Russian letters show properly, Hebrew right to left. On play the title pops in.", ""),
 ]),
 ("J. Sound", [
  ("p-tracks", "Sound tracks",
   "On the left edge of the timeline tap the add-track icon (\"Add sound track\"), or More > Add sound track. Tap the icon of the new track: a sheet opens. Change Volume, switch Mute on and off, read the other lines, tap Delete track. Then tap the film icon (Video sound) and switch Mute on and off.",
   "A new sound row appears and a message names it. The sheet has Name, Volume, Mute, Solo, Lower this track under speech, This track is speech, Only when speaking, Move up, Move down and Delete track. While a part is selected each row icon also has a tick box. The film icon opens the settings of the video's own sound.", ""),
  ("p-separate", "Separate sound, Put sound back",
   "Tap clip A, More > Separate sound; confirm (leave \"Also the other clips\" off). Play that piece. Then tap the clip, More > Put sound back.",
   "The clip's sound appears as its own piece on a Voice row and the clip shows as muted; Put sound back removes it again. Ask the owner to listen on the phone: the voice is heard once (no echo) and matches the lips.", "listen"),
  ("p-silences", "Remove silences",
   "Tap clip A (the talking video), More > Remove silences. Wait for the result. Tap Fewer cuts, Automatic, More cuts and write down the gap count of each. Choose Automatic and tap the Remove … gaps button. Play across two cuts. Tap Undo once.",
   "A progress bar with Cancel, then a line about the background noise and a button like \"Remove 5 gaps\". After applying, the clip is several pieces and the phone does not freeze for long. One Undo brings the single clip back. Ask the owner to listen: words are not chopped.", "listen"),
  ("p-clean", "Clean up sound and Voice focus",
   "Tap clip A, tap Sound, switch on Clean up sound and wait; then set Voice focus to about 50 % and wait. Play the clip. Read the clip's Volume and Mute there too.",
   "The clip shows \"Sound …%\" while it works and then finishes (write down roughly how long). Ask the owner to listen on the phone: less background noise, voice in sync.", "listen"),
  ("p-music", "Music: Find free music, credits, Fit to video, lower under speech",
   "Tap Add > Music or sound > Find free music, search piano, play one preview. (Do not add a second music if one is there.) Tap the music on its row, open its settings (Edit): read them, tap Copy credits, tap Add credits at the end, tap Fit music to video. Then tap an empty place, More > Lower music under speech; open More again and read the line.",
   "Results show title, artist, length and licence; the preview plays (it needs internet: otherwise copy what it says). The music's settings show Volume, Fade in, Fade out, Fit music to video, Track, Credits and its Quiet parts. Add credits at the end puts a caption over the last 4 seconds. Fit music to video makes it end with the video (\"The music now ends with the video, with a 2-second fade-out.\"). Lower music under speech shows as on afterwards.", ""),
 ]),
 ("K. Settings and suggestions", [
  ("p-settings", "The Settings page",
   "Tap the three dots > Settings. Read the page. Go back. From the project list tap its three dots > Settings and go back.",
   "A page \"Settings\" with: Editing (Snap to playhead and edges, Show sound waves, Smooth preview), Export (Use graphics card (faster)), Suggestions (Show suggestions; \"Show hidden suggestions again (…)\"), Updates (Check for updates automatically, Check now, the version line), About (About ClipForge, Copy version info, What's new, Licences, Send feedback). There is NO part \"Text window\" and NO part \"Claude\" on the phone.", ""),
  ("p-set-switches", "The switches change the app and are remembered",
   "Open Settings, switch Show sound waves OFF, Snap to playhead and edges OFF and Smooth preview OFF. Go back and look at the timeline. Close ClipForge completely, open it again, open the project and Settings. Switch all three ON again. Tap Check now.",
   "With Show sound waves off the waves are gone at once (and a drawing that was running stops). After reopening, all three switches are still off. Back on, the waves return. Check now says \"You have the newest version (1.17.0 (build 136)).\" Ask the owner, with a finger, whether dragging the end of the title jumps onto the playhead with snapping on and not with it off (otherwise set Partial).", ""),
  ("p-sg", "Suggestions: the line above the bottom bar",
   "In \"Round 7 phone\" (upright, with a wide clip and music) wait a second without playing and read the thin line just above the bottom bar. Write it down. Tap the three dots ON THAT LINE > Don't show again. Open Settings, read the button under Show suggestions, tap it, go back. When a line is back, tap its button. Tap Play and look where the line was. Swipe the next line sideways off the screen (or tap its cross).",
   "One line at a time, for example \"A clip has another shape than the video, so it gets bars.\" (Fill, Blur, Crop…), \"The music is longer than the video.\" (Fit to video), \"Music plays while someone is talking.\" (Lower the music). Don't show again hides it; Settings shows \"Show hidden suggestions again (1)\" and brings it back. The button does what it says. While playing the line is hidden. A swiped line does not come back in this project. With two voice tracks: \"Two microphones: each one also picks up the other speaker and the room.\"", ""),
 ]),
 ("L. The Text page", [
  ("p-text-open", "Text: read, search, tap to jump",
   "Tap an empty place, then Text in the bottom bar. Read the page. Tap the sentence \"Hello back.\" and look at the playhead when you return. Open Text again, tap into \"Find in the text…\" and type: hello. Then: xyzzy.",
   "A full-screen page \"Text\" shows the captions as a readable page: \"Sam Taylor\" once above his line and \"Alex K\" once above the two that follow, each with a coloured bar and the time. Tapping a sentence moves the playhead to it. The search marks and counts the places (\"1 of 2\"); xyzzy gives \"Not found\". Nothing offers to transcribe speech.", ""),
  ("p-text-edit", "Edit a caption; a short from a line",
   "In Text tap the sentence \"Let us test the search.\" and tap Edit. Change it to \"Let us test the phone.\" and tap Save. Tap Undo, then Redo. Open Text, tap the first sentence, tap Make a short from this…; tap 30 s, 45 s, 60 s, 30 s; name it Round 7 phone short; tap Make the short and Stay here.",
   "Tapping a sentence shows a bar with Edit, Delete caption and Make a short from this…. After Save the page and the preview show the new words; Undo and Redo switch. The window \"Make a short\" has The selection, 30 s, 45 s, 60 s, the line with the times, Start and end at a pause, Short caption look, Title at the top and the name; afterwards \"The short is ready\" with Stay here and Open it.", ""),
 ]),
 ("M. Markers and shorts", [
  ("p-marker", "Good moment markers and the lists",
   "Move the playhead to one third of the video and tap Add > Good moment marker; to two thirds and tap More > Good moment marker. Tap the three dots at the top > Markers; close. Tap More > Shorts and good moments and read the sheet. Tap Make shorts from markers…, read, tap Make them, then Open the first; play 5 seconds and go back.",
   "Each marker is a flag on the ruler (\"Marked a good moment at …\" with Undo). Markers opens \"Good moments\" with both, each with \"Make a short around it\" and \"Remove the marker\". The sheet \"Shorts\" has Good moment marker, Good moments (2)…, Make a short from here… and Make shorts from markers…. As many shorts are made as the window's title says; they are upright and play; this project is unchanged. Ask the owner to look at one short on the phone: captions bigger, in the lower middle, outlined.", "watch"),
 ]),
 ("N. Export, share, publishing notes", [
  ("p-notes", "Publishing notes",
   "Tap the three dots > Publishing notes. Type a Title (Round 7 phone video) and a Description (one sentence). Tap the copy button next to Title. Tap Chapters from titles / captions… and read what it says. Tap Done.",
   "A full-screen page \"Publishing notes\" with Title, Description, Hashtags and Chapters, each with a copy button, \"A different title for Shorts, Reels and TikTok\", Copy title and description and Done. The keyboard does not hide the field being typed in.", ""),
  ("p-exp-dest", "Export for a destination",
   "Tap Export at the top. Tap each choice under \"Where is it going?\" once and read its line. Choose WhatsApp / Telegram, read the size it shows, and tap Export. Wait and read the finished screen (stay on it).",
   "Choices: YouTube, Shorts / Reels / TikTok, Instagram post, WhatsApp / Telegram, Podcast audio, Custom. The project is upright, so YouTube asks about the shape, naming both the same way (\"Your video is 9:16 upright; this needs 16:9 wide\") with Make a copy in this shape and Export as it is. WhatsApp / Telegram shows the size that is really written (for an upright video 720 × 1280). The export runs to 100 %, then \"Video saved\" and \"Saved to …\" (the gallery). \"Keep ClipForge open while it exports.\" shows while it runs.", ""),
  ("p-share", "Share, and Copy title and description",
   "On the finished screen tap Share. Look at Android's share sheet and close it WITHOUT choosing an app. Tap Copy title and description. Tap Done.",
   "Share opens Android's own share sheet with the video (nothing is sent). A note says that many apps ignore text shared with a video, which is why Copy title and description stays on screen; it copies the title and description from the notes.", ""),
  ("p-exp-several", "Export several into a gallery album",
   "Tap Export > Export several…. Tick WhatsApp / Telegram and Podcast audio only. Read the line under the list. Tap Export 2 files and wait. Then open the phone's Gallery app, find the album Round 7 phone and play its video for 10 seconds.",
   "Each tick shows its file name. The line says \"2 files, about … together. The videos go to your gallery, in an album called \"Round 7 phone\".\" One progress bar (\"1 of 2: …\"), then \"Files saved\" with Share and Copy title and description. The album holds the video. Ask the owner to watch and listen on the phone: upright, fade from black, captions readable, the silenced and the quieter part as in the preview, voice in sync.", "watch,listen"),
  ("p-exp-custom", "Custom: full quality, small file, sound only",
   "Tap Export > Custom. Full quality: write down the \"File size: about …\" line, export, and write down how long it took. Then Small file. Then Make: sound only (M4A), and MP3. Compare the two videos' sizes in the Gallery.",
   "Each finishes (\"Video saved\" / \"Sound saved\"). The small file is clearly smaller. For sound only the picture settings are hidden and Share offers the file. If MP3 says to export as M4A instead, write that down exactly.", ""),
  ("p-exp-bg", "Leave the app, and screen off, during an export",
   "Start a Full quality export. At about 20 % press the phone's Home button, wait 30 seconds and return to ClipForge. Start one more export and do not touch the phone until it is finished.",
   "Write down exactly what happened: it kept running and finished (a notification keeps it running) / it stopped with a message and Try again. No half-finished video appears in the gallery. With the phone left alone the screen stays on and the export finishes.", ""),
  ("p-exp-long", "Export the long project (last, and let it run)",
   "Open \"Round 7 phone long\", tap Export > WhatsApp / Telegram (or Custom > Small file) and export. Leave the phone alone, on the charger. Write down the project's length, the time it took and the file size. Afterwards do Copy version info as in group B.",
   "The progress moves steadily to 100 % and it finishes; the video in the gallery has the project's length and plays to the end. Ask the owner to watch the last minute: picture and voice still in sync.", "watch,listen"),
 ]),
 ("O. Files, rotation, what is not on a phone", [
  ("p-project-menu", "Project cards: Rename, Duplicate, Share project file, Delete",
   "On the project list tap the three dots on the card of \"Round 7 phone markers\". Tap Duplicate. On the copy tap Rename and give it the name of the original. Tap Share project file on the copy; look at the share sheet and cancel. Delete the copy.",
   "The card menu has Rename, Duplicate, Share project file and Delete. A name that is taken gets \"(2)\". Share project file shows \"Packing …\" and Android's share sheet with one file ending in .clipforge.zip; cancelling sends nothing. Delete asks first.", ""),
  ("p-reopen", "Close and reopen: the media is still there",
   "Close ClipForge completely. Open the Gallery app, look at two photos, close it. Open ClipForge and \"Round 7 phone\". Play 5 seconds.",
   "All clips are there with their pictures, the music is there, and everything plays. No clip is red or says Missing. (If an older project shows a Missing clip: tap it, Find file > Search the gallery, and write down what it says.)", ""),
  ("p-rotate", "The phone on its side",
   "Ask the owner to switch auto-rotate on and turn the phone on its side with the project open, then back upright.",
   "Write down what happens. On a wide enough screen the editor changes to the computer's layout (side panel, the strip \"Drag here to select a part\" under the ruler); otherwise it keeps the phone layout. In both cases nothing is lost: the project, the playhead, the selection and a selected part are still there, and the app does not close.", ""),
  ("p-help", "Help and the tour on the phone",
   "On the project list tap ? (Help). Search for: select a part, only when speaking, feedback, stutter. Open one article. Start the tour and go through it with Next to the end.",
   "The searches find \"Select a part\", \"Only when speaking\", \"Send feedback\" and \"Smooth preview on phones\"; the article names the phone's way (More > Select part, the handles, Actions). The text fits the screen and scrolls. Each tour step highlights a real button and its text fits the screen.", ""),
  ("p-none", "Nothing about speech-to-text or Claude on the phone",
   "Look for the words Transcribe, Captions from speech, Remove filler words, Automatic cuts and Claude in: both three-dot menus, Settings, the Add sheet, More (nothing selected and a clip selected) and the Text page.",
   "None of these places has an item about speech to text or about Claude. (Help may have articles marked \"computer only\".) Write down any place where such an item shows up.", ""),
  ("p-final", "Everything was saved",
   "Open \"Round 7 phone\" once more and look through it. Then do Copy version info one last time (as in group B) and give the owner's reading of the \"longest gap\" in the Summary.",
   "Everything is as you left it: 9:16 upright, the look, the title, three captions (the last one edited), fades, the music with its quiet part, the silenced part, the slow part of B, the flags, the publishing notes.", ""),
 ]),
]

INSTR_7P = """You are testing ClipForge 1.17.0 (build 136), a video editor, on the owner's Android phone. You work on the owner's Windows PC and see and touch the phone through "Link to Windows" (the PC app is called Phone Link): the phone's screen is shown in a window on the PC. This checklist page is open in a browser on the PC. Problems are expected; your job is to find them and write them down precisely. This round goes through EVERY phone feature, the new and risky things first. It has __NSTEPS__ numbered steps in __NGROUPS__ groups (A to O). Speech to text and Claude control are computer only and are not part of this page.

MEDIA FOLDER: <owner fills in>

HOW TO DRIVE THE PHONE
- In the phone window a mouse click is a tap, holding the mouse button down for a second is a long-press, and click-and-drag is a drag or a swipe. There are no keyboard shortcuts and no menu bar on the phone: use only what is on the phone's screen.
- If the phone screen is not shown, ask the owner to open Phone Link on the PC and choose the phone's screen, and to unlock the phone. If the mirrored screen goes black or locks, ask the owner to unlock it.
- Drags, swipes and long-presses often fail through mirroring. Try twice. If it still fails, use the button the step offers instead; otherwise set "Needs the owner", write that it could not be performed through mirroring (it may work fine with a finger), and ask the owner to try it with a finger if they are there.
- Typing: tap into the text box on the phone and type on the PC keyboard.
- SOUND: the phone's sound may not reach you through mirroring. Never judge sound yourself. For every step tagged "ask the owner to listen", do the actions, then ask the owner in the chat. The same goes for smoothness: mirroring stutters by itself, so for steps tagged "ask the owner to watch" ask the owner to look at the phone itself. Write the answer in the note starting with "Owner:" and set PASS or FAIL from it. If the owner is not available, set "Needs the owner".

HOW THE PHONE APP IS LAID OUT IN 1.17 (names as on the screen)
- Project list: New project and Open project file; ? (Help) and three dots (Settings, What's new, Check for updates, Send feedback, About ClipForge, Copy version info) at the top; each project card has three dots: Rename, Duplicate, Share project file, Delete.
- Editor, top: back arrow, the project's name, the save sign, Undo, Redo, Export and three dots (Shape and size, Fade in and out, Select part, Publishing notes, Text, History, Markers, Settings, Help, Send feedback).
- Bottom bar with nothing selected: Add, Text, Split, More. Add opens one list of everything that can be added. More lists the rest under the headings Clip, Part, Sound, Text, Edit.
- With something selected the bar shows that item's tools and More; Done clears the selection. A + next to Play opens the Add list while something is selected.
- A selected part of the timeline has two handles on the ruler and its own bar between the timeline and the bottom bar: start, end, length, arrows, Actions and a cross.
- A thin line with a tip and a button may appear just above the bottom bar: a suggestion. Outside the group that tests them leave it alone.
- Sheets open from the bottom; swipe them down or tap outside to close them.

BEFORE YOU START
- Fill in "Device" (for example "Samsung Galaxy S23, Android 15, via Link to Windows") and "Tester".
- Do group A first: it updates the app. Then fill in "Version shown in the app": project list > three dots > About ClipForge > Copy version info, then type or paste the line. If it does not match the build named at the top of this page (a red warning appears), tell the owner and say so in the Summary.
- Test files must be ON THE PHONE (ask the owner which ones to use; the MEDIA FOLDER named above is where the same files are on the PC, in case the owner wants to copy one over): A. a talking video filmed wide (landscape), 1-3 minutes; B. a short video under 45 seconds; the longest video the phone has (20 minutes or more is best); optional: a music file longer than video A (otherwise the app's own Find free music is used, which needs internet), and a video with one sound file per speaker. Do not download files in any other way.
- Do the groups in order: later steps build on the project "Round 7 phone". If time runs out, groups A to F matter most; say in the Summary where you stopped.

IF CLIPFORGE STOPS ANSWERING ON THE PHONE
- Write down the time, the step and what was on screen ("Drawing sound… 1 of 1", "Loading the video…"). Wait two minutes. If it does not come back, close it from the recent-apps view and open it again.
- Then tap the three dots on the project list > Copy version info and get the text to the owner (paste it into a notes app on the phone): it carries the performance log, also of the run that stopped. Put what you can read of it into the Crash box. Do the same if the line "Sound waves were paused to keep ClipForge responsive" appears.

RULES
- Each step has "Do" (exact actions) and "Expected" (what should happen). Do the actions exactly, then compare with Expected.
- For each step choose a Result and write a Note. Result meanings: PASS = you saw exactly the expected result (or the owner confirmed it). FAIL = something was wrong (write what you did, what happened, and what you expected). Partial = part of it worked (say which part). Not tested = you could not do it (say why). Needs the owner = only a person can judge or perform it and the owner was not available.
- NEVER delete, move or rename the owner's photos, videos or music, in ClipForge's pickers, in the Gallery or in any other app. Do not uninstall ClipForge (that deletes the projects). Inside ClipForge only delete things this test made. Do not send or share anything to other people or apps: when a share sheet opens, choose nothing and go back.
- Ask the owner before you tap Update or Send (feedback).
- Exported videos go to the phone's gallery; leave them there for the owner.
- If an Android permission dialog appears (photos and videos, music, notifications, installing from this source), allow it and write down that it appeared.
- Do not guess. Only mark PASS for what you actually saw, or for what the owner told you they heard or saw.
- This page keeps your answers in this browser as you go. When finished, fill in the Summary box (the long video first, then the most important problems; also what was hard to do through mirroring), then click "Download filled checklist" and give the downloaded file (ClipForge-Test-Round-7-phone-results-….html) to the owner, who sends it back."""

# labels of the tags, and the wording that differs (page title, hints in the
# Device and Note boxes). The key is also the browser-storage key and part of
# the name of the downloaded results file. Old rounds stay so their pages can
# be regenerated.
# ---------------------------------------------------------------- round 7, Mac (1.17.0)
# The macOS round for 1.17.0 (build 136): round 7 adapted for a Mac (an
# Apple-silicon MacBook Air), run by a computer-use agent on the Mac itself.
# It is DERIVED from STEPS_7 / INSTR_7, so a step is written once:
#   * every round 7 step goes through _mac_text (Cmd for Ctrl, Option for
#     Alt, Cmd+? for F1, Quit in the ClipForge menu, Finder, QuickTime
#     Player, forward slashes);
#   * MAC_STEP changes single steps: "sub" = (old, new) pairs applied to the
#     converted text (each old text must be there, so a change in round 7
#     is noticed here), "do_add" / "exp_add" = a sentence added at the end,
#     "title" / "do" / "exp" = a whole new text;
#   * group A is new (MAC_A): the first install from ClipForge-macos.zip,
#     Gatekeeper, the first start, the in-app update (never run on a real
#     Mac), and the Connect to Claude page (round 7's group T, moved here).
#     The other groups keep their order and are lettered again.
# Checked against the source: lib/ui/app_menu.dart (buildMenuTree /
# buildAppMenus, test/ui/menu_tree_snapshot.txt: Cmd on macOS, Settings… in
# File, About in the ClipForge menu and in Help, Quit in the ClipForge
# menu, Help = Cmd+Shift+?, a tick is " ✓" after the label),
# lib/ui/editor/editor_screen.dart (_onKey takes Ctrl or Cmd),
# lib/core/update/update_install.dart + assets/update/clipforge-update.sh +
# lib/ui/update/update_controller.dart (ditto, <app>.update-new / -old,
# markers next to the bundle, plan B into ~/Downloads, the state folder in
# Application Support/<bundle id>), lib/core/claude/connect.dart and
# helper_install.dart (the Mac paths), lib/media/transcribe/* (which speech
# programs are looked for, and where), tool/ci/make_readme_html.py and the
# "Zip the app" step of the workflow (what the zip holds).
_MAC_TEXT = [
 (r"Alt\+F4", "Cmd+Q"),
 (r"File > Exit", "ClipForge > Quit ClipForge"),
 (r"\bExit, start again", "Quit (ClipForge > Quit ClipForge), start again"),
 (r"Ctrl\+", "Cmd+"),
 (r"\bCtrl shortcuts", "Cmd shortcuts"),
 (r"\bAlt\b", "Option"),
 (r"\bF1\b", "Cmd+?"),
 (r"press Delete\b", "press the Delete key (the one above Return)"),
 (r"\bExplorer\b", "Finder"),
 (r"\bMedia Player\b", "QuickTime Player"),
 (r"right-click > Properties > Details > Frame width / height", "in Finder click the file and press Cmd+I: \"More Info\" shows the dimensions"),
 (r"right-click > Properties > Details > Frame rate", "open the file in QuickTime Player and press Cmd+I: the Movie Inspector shows the frames per second (FPS)"),
 (r"clipforge-test-output\\", "clipforge-test-output/"),
 (r"\bon this PC\b", "on this Mac"),
]

def _mac_text(t):
    for a, b in _MAC_TEXT:
        t = re.sub(a, lambda m, b=b: b, t)
    return t

_MAC_SUPPORT = "~/Library/Application Support"
_MAC_STATE = _MAC_SUPPORT + "/com.ekcut.clipforge/update-state"

MAC_STEP = {
 "up-before": dict(
   title="Before the update: which version is on this Mac",
   sub=[("Start ClipForge from the Windows Start menu.", "Only in case (2) of the first step: an OLDER ClipForge is in Applications. Otherwise set Not tested for this step and the next two and say why. Start ClipForge from Applications."),
        ("On a PC that still has 1.15 or 1.16:", "On a Mac with a version older than 1.17.0:"),
        ("(ask the owner: in-app update or the installer)", "(ask the owner)")],
   do_add="Then choose Help > Copy version info, paste it into the note and look for a line starting with \"Folder:\".",
   exp_add="The \"Folder:\" line (if this older version has one) should be /Applications/ClipForge.app. If it has \"/AppTranslocation/\" in it, macOS runs this copy from a temporary place and ClipForge cannot replace it where it is: say so, and expect the other ending described in the next step."),
 "up-run": dict(
   title="The in-app update to 1.17.0 (never run on a real Mac before)",
   sub=[("Do nothing while ClipForge closes and opens again (up to a minute).", "Do nothing while ClipForge closes and opens again (up to a minute; meanwhile only look at the Applications folder in Finder, if it is open, for new items next to ClipForge)."),
        ("ask the owner to install 1.17.0 with ClipForge-Setup.exe so that the round can go on.", "ask the owner whether you may install 1.17.0 from ClipForge-macos.zip (the steps \"Move ClipForge into Applications\" and \"The first open\") so that the round can go on.")],
   exp_add="This is the first run on a real Mac: write down EXACTLY what happens, in order, with the times. Per the code the app unpacks the download next to itself, closes, a small script moves the old ClipForge aside, moves the new one in and opens it. Three other endings are possible. (a) A message \"The new ClipForge is in your Downloads folder (Finder shows it). Close ClipForge, drag the new one into Applications, choose Replace, then open it.\" with OK: ClipForge could not change its own place (it runs from a temporary place, or the folder that holds it cannot be changed) and put the new app into Downloads > \"ClipForge 1.17.0\"; copy the message, set Partial, ask the owner, then do what it says. (b) After the restart macOS shows its \"cannot be opened\" warning again: copy it, set Partial and go on as in the step \"The first open\" (ask the owner first). (c) ClipForge does not come back within two minutes: look into Applications, write down what is there, start ClipForge by hand and set FAIL for the restart."),
 "st-version": dict(
   sub=[("(it ends in AppData\\Local\\Programs\\ClipForge, not in a name ending in \".update-new\")", "(on a Mac: /Applications/ClipForge.app; not a name ending in \".update-new\" or \".update-old\", and without \"/AppTranslocation/\" in it)")],
   do_add="On the Mac About is in two places: open ClipForge > About ClipForge in the menu bar too.",
   exp_add="Both About items open the same window. The system line names macOS."),
 "st-notes": dict(
   do_add="After a fresh install from the zip (no update) neither is expected: set Not tested and write \"fresh install\", or write down what did appear."),
 "st-projects": dict(
   do_add="On a Mac that never had ClipForge the list is empty: set Not tested and say so."),
 "cl-page": dict(
   sub=[("(it ends in ClipForge\\claude, under the user's app data)", "(per the code " + _MAC_SUPPORT + "/ClipForge/claude)")],
   exp_add="How ClipForge looks on a Mac: Claude Desktop is found by its settings folder " + _MAC_SUPPORT + "/Claude (\"Claude Desktop not found\" when that folder is not there); Claude Code by the program \"claude\" on the PATH or in ~/.local/bin, ~/.claude/local, ~/.claude/bin, /usr/local/bin, /opt/homebrew/bin or ~/.npm-global/bin (\"Claude Code not found\" otherwise). Ask the owner which of the two are on this Mac and write down whether the lights agree with the answer."),
 "cl-connect": dict(
   sub=[("ends with the helper's path in the ClipForge\\claude folder", "ends with the helper's path (…/ClipForge/claude/clipforge-mcp)")],
   exp_add="On a Mac, Connect for Claude Desktop changes only the clipforge entry in " + _MAC_SUPPORT + "/Claude/claude_desktop_config.json and, when that file was there before, first saves a copy next to it (claude_desktop_config.backup-<date>-<time>.json): open that folder (Finder > Go > Go to Folder…) and write down whether the entry and the backup are there. Connect for Claude Code runs \"claude mcp add --scope user clipforge -- <the helper>\". If macOS asks a question at that moment, copy its words and ask the owner before you answer."),
 "key-timeline": dict(
   sub=[("Home, End, Cmd+Right", "Home, End (a MacBook has no such keys: Fn+Left and Fn+Right), Cmd+Right")],
   exp_add="On the Mac the menu bar shows Cmd+Z, Cmd+Shift+Z, Cmd+Shift+H, Cmd+Shift+T, Cmd+F, Cmd+E and Cmd+? next to their items; Cmd+Y and Cmd+Left / Cmd+Right are done by the editor itself and are not shown in the menu. (Ctrl instead of Cmd also works for the editor's own keys; that is not a fault.)"),
 "key-comma": dict(
   do="On the project list, click an empty place and press Cmd+comma; close Settings. In a project press Cmd+comma; close. Ask the owner whether a second keyboard layout is switched on (for example Russian or Hebrew): if yes, switch to it (the input menu at the right of the menu bar, or the Globe / Fn key), press Cmd and the key that is the comma on the English layout, close Settings and switch back.",
   exp="Settings opens each time, also when nothing on the page has the keyboard. On the Mac this key belongs to the menu item File > Settings… (Cmd+,), so macOS decides what happens with another layout: write down exactly what happened there (the fix made in 1.17 for Windows, where it did not open with such a layout, is for Ctrl+comma only). Without a second layout set Partial and say so."),
 "sm-addpath": dict(
   sub=[("(the media folder plus \\nothing-here)", "(the media folder plus /nothing-here)"),
        ("In Finder, hold Shift, right-click file B and choose Copy as path;", "In Finder, right-click file B, hold Option and choose Copy \"…\" as Pathname;"),
        ("(in Finder: Shift+right-click > Copy as path)", "(it names both ways: in Explorer Shift+right-click > Copy as path; in Finder Option+right-click > Copy as Pathname)")],
   exp_add="Paths on the Mac are POSIX paths (/Users/…/Movies/…, forward slashes); a path that starts with file:// works too."),
 "sm-menus-1": dict(
   do="There are ten ClipForge menus in the menu bar at the top of the screen: File, Edit, Add, Clip, Part, Sound, Text and speech, View, Playback, Help (macOS adds the ClipForge menu at the left and Window before Help). Open File, Edit, Add and Clip and compare every item and shortcut with Expected. (macOS draws the keys as symbols: ⌘ is Cmd, ⇧ is Shift, ⌫ is Delete.)",
   exp="File: New project (Cmd+N), Open project file… (Cmd+O) | Rename project…, Publishing notes…, Back to projects | Export… (Cmd+E), Export several…, Export subtitles (.srt)… | Settings… (Cmd+,). There is no Exit or Quit in File: Quit ClipForge (Cmd+Q) is in the ClipForge menu. Edit: Undo (Cmd+Z), Redo (Cmd+Shift+Z), History (Cmd+Shift+H) | Duplicate (Cmd+D), Copy settings (Cmd+Shift+C), Paste settings (Cmd+Shift+V), Delete (the Delete key, ⌫) | Find in the text… (Cmd+F). Add: Videos or photos…, Music or sound…, Voice recording…, Title, Caption…, Subtitle file (.srt)…, Overlay video or photo…, Add from a folder path…, Good moment marker (M). Clip: Split (S), Start at playhead (Q), End at playhead (W), Freeze frame, Remove silences…, Crop and position…, Rotate right, Move earlier, Move later | Make a short from here…, Make shorts from markers…, Good moments…. In an open project New project and Open project file… are grey with \"(go back to the projects first)\". Whether macOS shows and obeys the single-letter keys (S, Q, W, M) in its menus was never checked on a real Mac: write down what you see. Write down every difference."),
 "sm-menus-2": dict(
   sub=[("View: Zoom in (+), Zoom out (-), Snap to playhead and edges, Show sound waves |", "View: Zoom in (+), Zoom out (-), Snap to playhead and edges, Show sound waves (a switched-on item has a ✓ after its name) |"),
        ("Go to start (Home), Go to end (End)", "Go to start (Home, drawn as an arrow to the top left), Go to end (End, an arrow to the bottom right)"),
        ("Previous speech start (Cmd+Left), Next speech start (Cmd+Right)", "Previous speech start, Next speech start (no key is shown on the Mac; Cmd+Left and Cmd+Right still do it)"),
        ("ClipForge Help (Cmd+?)", "ClipForge Help (Cmd+?, drawn as ⇧⌘? or ⌘?)")],
   exp_add="Also on the Mac: the ClipForge menu (About ClipForge | Services | Hide ClipForge, Hide Others, Show All | Quit ClipForge) and the Window menu (Minimize, Zoom | a full-screen item); macOS may add items of its own to Edit, View, Window and Help (for example a search box in Help): name them, they are not faults."),
 "pr-quit": dict(
   exp_add="(Cmd+Q is ClipForge > Quit ClipForge. Also try the red button at the top left of the window once, after another small change: write down whether ClipForge quits or only the window closes, and that the change was saved.)"),
 "pb-finish": dict(
   sub=[("Show in folder opens Finder on the folder.", "Show in folder opens a Finder window with the file selected in its folder.")]),
 "ex-gpu": dict(
   exp_add="On an Apple chip the graphics-card choice reads \"Graphics card — VideoToolbox (Mac)\"."),
 "hp-pages": dict(
   sub=[("with J / K / L, M, Cmd+D and the rest", "with J / K / L, M, Ctrl+D and the rest (the list is written with Ctrl and says at its top \"On a Mac use Cmd where this says Ctrl\"; it names Cmd+? for help, Cmd+comma for Settings, Cmd+Q to quit and Option for dragging without snapping)")]),
 "so-waves": dict(
   sub=[("(\"Previous speech start (Cmd+Left)\", \"Next speech start (Cmd+Right)\")", "(their tooltips read \"Previous speech start (Ctrl+Left)\" and \"Next speech start (Ctrl+Right)\" on the Mac too: the code has one text for every system; write down what you see)")],
   exp_add="On a Mac press Cmd+Right and Cmd+Left: Ctrl with an arrow key usually belongs to macOS (it switches desktops)."),
 "sp-open": dict(
   title="Transcribe speech…: what this Mac has, or a plain explanation",
   exp_add="What ClipForge needs on a Mac (it brings no speech program of its own): one of whisper-ctranslate2, faster-whisper, whisper-cli or whisper-cpp (whisper.cpp), whisper, or an ffmpeg of version 8 or newer whose filter list has \"whisper\". It looks on the PATH and in /opt/homebrew/bin, /usr/local/bin, /opt/local/bin, /usr/bin, ~/.local/bin and ~/bin (so Homebrew programs are found). When none is there, the box ends for the Mac with \"On a Mac the simplest is Terminal: brew install whisper-cpp (or an FFmpeg 8 build that includes the whisper filter), then restart ClipForge.\" Do NOT install anything and do not open Terminal on your own: tell the owner what the box says. Only if the owner agrees and installs it (or tells you to), restart ClipForge and go on with this group; write down what was installed."),
 "sp-run": dict(
   exp_add="On a Mac with whisper.cpp ClipForge first reads the sound with an ffmpeg from the same places (\"Reading the sound…\"). If there is no ffmpeg on the Mac it stops with \"Reading the sound needs FFmpeg, which was not found on this computer.\": copy it, set Partial with \"whisper.cpp without ffmpeg\", tell the owner, and set the rest of the group to Not tested unless the owner installs ffmpeg."),
}

# Group A of the Mac round: tuples are new steps, plain ids are round 7 steps.
MAC_A = ("A. Install, update and Claude on this Mac (all of it new on a real Mac)", [
  ("mac-before", "Before anything: this Mac, and what is on it",
   "Choose Apple menu > About This Mac and write the model, the chip and the macOS version into \"Device\" at the top of this page. Open Finder > Applications and look for ClipForge. If it is there, start it (if macOS refuses to open it, do the step \"The first open\" below first), read the small grey line at the bottom of the project list and write the version down. Ask the owner where ClipForge-macos.zip of 1.17.0 is (usually the Downloads folder). If it is not on the Mac, ask the owner to get it from the ClipForge download page; do not download it yourself.",
   "You know which case this is, and wrote it into the note. Case (1), no ClipForge on this Mac: do the install steps and set the three update steps to Not tested with \"fresh install\". Case (2), an OLDER ClipForge is in Applications: do the zip step, set \"Move ClipForge into Applications\" and \"The first open\" to Not tested with \"kept the old version to test the update\", then do the update steps. Case (3), 1.17.0 (build 136) is already there: ask the owner how it got there, write that down, and set what cannot be done to Not tested. The Mac has an Apple chip (M1 or newer); on an Intel Mac say so in the Summary (the Claude helper is for Apple chips only).", ""),
  ("mac-zip", "Unzip ClipForge-macos.zip: what is in it",
   "In Finder double-click ClipForge-macos.zip (the zip itself stays). Open the folder that appears and write down every item in it. Double-click \"Read me first\" (it opens in the browser) and read it to the end. Double-click \"Connect Claude to ClipForge\" and read its start. Close both tabs.",
   "Three items side by side: ClipForge (the app), \"Read me first.html\" and \"Connect Claude to ClipForge.html\". There is no separate Claude program or \"ClipForge-Claude\" folder (the Claude helper is inside the app) and no \"Release notes.txt\". \"Read me first\" is written for the Mac: Install on Mac (unzip; drag ClipForge into Applications; macOS 15 or newer: open it once, close the message, then System Settings > Privacy & Security > Open Anyway; older macOS: right-click > Open, then Open), First steps, Where your projects are (Documents > ClipForge), Updates, Use it with Claude (with \"On a Mac this needs an Apple chip (M1 or newer).\") and \"What is new in 1.17.0\". Write down every sentence that does not fit a Mac or this version (a word about Windows, a wrong menu, a wrong key).", ""),
  ("mac-install", "Move ClipForge into Applications",
   "Only in case (1) of the first step, or when the owner says that the ClipForge in Applications may be replaced. Drag ClipForge from the unzipped folder into Applications. If Finder asks whether to replace a ClipForge that is there, or asks for a password, stop and ask the owner. Do not start ClipForge from the unzipped folder.",
   "ClipForge is in Applications, once. (Why not from the unzipped folder: macOS runs a downloaded app that was never moved from a hidden temporary place, and ClipForge then cannot update itself where it is.)", ""),
  ("mac-gatekeeper", "The first open: the macOS warning",
   "Double-click ClipForge in Applications. macOS is expected to refuse: copy the exact words of the message into the note and close it (never choose Move to Trash). Then ASK THE OWNER: \"macOS blocks ClipForge because it is not signed by an Apple-registered developer. May I allow it under System Settings > Privacy & Security > Open Anyway?\" Only after a yes. On macOS 15 or newer: open System Settings > Privacy & Security, scroll down to the line about ClipForge, click Open Anyway and confirm (the owner types the password or uses Touch ID if asked). On older macOS: right-click ClipForge in Applications, choose Open, then Open again. Change nothing else in System Settings.",
   "A message that ClipForge cannot be opened (for example \"Apple could not verify…\", \"…cannot be opened because it is from an unidentified developer\" or \"…is damaged\": write which). After Open Anyway (or right-click > Open) ClipForge starts and shows the project list, and from then on it opens with a normal double-click, without a question. This is what the read-me and the help article \"Mac: \"ClipForge can't be opened\"\" say: write down any difference. If the message says \"damaged\" and offers only Move to Trash, set FAIL and ask the owner. If the owner says no, set Not tested: the round cannot go on.", ""),
  ("mac-first-start", "The first start: questions from macOS, and the menu bar",
   "Watch the first minute after ClipForge opened. If macOS asks anything (for example \"ClipForge would like to access files in your Documents folder\"; later the same for Downloads, Desktop or a removable disk when test files are there), copy the words and ask the owner before you answer. If a tour starts, go through it. Then look at the menu bar at the top of the SCREEN: open the ClipForge menu and the Window menu and read them. Press Cmd+comma and close Settings.",
   "ClipForge keeps the projects in Documents > ClipForge, so one question about the Documents folder is normal. No question about the microphone, the camera or recording the screen is expected from ClipForge (it does not record): write down any that comes. The window has no menu bar of its own; at the top of the screen are ClipForge, File, Edit, Add, Clip, Part, Sound, Text and speech, View, Playback, Window, Help. The ClipForge menu has About ClipForge, Hide ClipForge, Hide Others, Show All and Quit ClipForge (Cmd+Q); Settings… is in the File menu (Cmd+,), not in the ClipForge menu. Cmd+comma opens Settings.", ""),
  "up-before",
  "up-run",
  ("mac-update-after", "After the update: nothing left behind, and the update log",
   "Only after an in-app update (otherwise set Not tested). In Finder open Applications and read every name that starts with ClipForge (press Cmd+Shift+. once to show hidden files, and once more afterwards to hide them again). Then choose Go > Go to Folder… in Finder, paste " + _MAC_STATE + " and press Return; write down the files there. In ClipForge choose Help > Copy version info and paste it into the note. Delete nothing.",
   "Applications holds exactly one ClipForge. Per the code the update makes these next to it, for a short time only: \"ClipForge.app.update-unpack\" and \"ClipForge.app.update-new\" (the new version), \"ClipForge.app.update-new.marker\", \"ClipForge.app.update-old\" (the old version stepping aside) and \"ClipForge.app.update-old.marker\"; the update or the next start of ClipForge removes them. Any of them still there after ClipForge was started twice is a finding: write the exact names. The update log is the file update-log.txt in " + _MAC_STATE + " (the pasted text names it in a line \"Update log: …\": if that is another place, write it down); a file update-result.json may be beside it for a moment. The pasted lines show the steps of the app and of the script, such as \"script(sh): started token=…\", \"the app (pid …) has closed\", \"result: updated\" and \"done\". The projects in Documents > ClipForge are as before.", ""),
  "st-version",
  "st-notes",
  "st-projects",
  "cl-page",
  "cl-test",
  "cl-connect",
])

_MAC_GROUP_TITLE = {
 "B. The long file (the freeze reported on this PC)": "B. The long file (it made an earlier version stop answering on the owner's Windows PC)",
}

def _mac_steps():
    by_id = {st[0]: st for _, items in STEPS_7 for st in items}
    used = set()
    def conv(sid):
        _, title, do, exp, tag = by_id[sid]
        title, do, exp = _mac_text(title), _mac_text(do), _mac_text(exp)
        o = MAC_STEP.get(sid, {})
        used.add(sid)
        for old, new in o.get("sub", []):
            assert (old in do) + (old in exp) == 1, "round 7-mac, %s: this text is not in the step (once): %s" % (sid, old)
            do, exp = do.replace(old, new), exp.replace(old, new)
        title, do, exp = o.get("title", title), o.get("do", do), o.get("exp", exp)
        if "do_add" in o: do += " " + o["do_add"]
        if "exp_add" in o: exp += " " + o["exp_add"]
        return (sid, title, do, exp, tag)
    first = [conv(s) if isinstance(s, str) else s for s in MAC_A[1]]
    moved = {s for s in MAC_A[1] if isinstance(s, str)}
    groups = [(MAC_A[0], first)]
    for name, items in STEPS_7:
        rest = [conv(st[0]) for st in items if st[0] not in moved]
        if rest:
            groups.append((_MAC_GROUP_TITLE.get(name, _mac_text(name)), rest))
    assert used == set(by_id), "round 7-mac must carry every round 7 step"
    assert set(MAC_STEP) <= used, "MAC_STEP names a step round 7 does not have"
    # Letter the groups again (round 7's group T moved into group A).
    return [("%s. %s" % (chr(65 + i), name.split(". ", 1)[1]), items)
            for i, (name, items) in enumerate(groups)]

STEPS_7M = _mac_steps()

def _between(text, start, end):
    """The part of [text] from [start] up to [end] (both must be there)."""
    a = text.index(start)
    return text[a:text.index(end, a)]

def _mac_instr():
    files = _between(INSTR_7, "- Test files are in the MEDIA FOLDER", "- The easiest way to add files")
    tip = _between(INSTR_7, "- A thin line with a tip", "IF CLIPFORGE STOPS ANSWERING")
    stops = _between(INSTR_7, "IF CLIPFORGE STOPS ANSWERING", "RULES\n")
    rules = INSTR_7[INSTR_7.index("RULES\n"):]
    for old, new in [
        ("close it (Task Manager if needed) and start it again.", "close it (Apple menu > Force Quit… if needed; tell the owner) and start it again. If macOS then shows \"ClipForge quit unexpectedly\", click Report…, copy the text into the Crash box and close that window without sending."),
    ]:
        assert old in stops
        stops = stops.replace(old, new)
    for old, new in [
        ("Ask the owner before you press Update, Send (feedback), Connect or Replace with this version.", "Ask the owner before you press Update, Send (feedback), Connect or Replace with this version, before you answer ANY question macOS asks (permissions, \"cannot be opened\", a password, Touch ID) and before you change anything in System Settings."),
        ("Do not install programs.", "Do not install programs (not with Homebrew either) unless the owner agrees; without a speech program the speech group is Not tested with that reason."),
        ("(ClipForge-Test-Round-7-results-….html)", "(ClipForge-Test-Round-7-mac-results-….html)"),
    ]:
        assert old in rules
        rules = rules.replace(old, new)
    return """You are testing ClipForge 1.17.0 (build 136), a video editor, on the owner's Mac (a MacBook Air with an Apple chip). You work on the Mac itself; this checklist page is open in a browser on the Mac. Problems are expected; your job is to find them and write them down precisely. This version has not been through a full test on a real Mac, and its in-app update has never run on one: write down exactly what you see, also when it works. This round goes through EVERY feature, with the new and risky things first: the install (or the in-app update) and the Claude connection on the Mac, a long video that made an earlier version stop answering on the owner's Windows PC, everything version 1.17 changed, then all the rest. It has __NSTEPS__ numbered steps in __NGROUPS__ groups (A to %(last)s). It is the Windows round 7 adapted for macOS. The Claude tools have their own document (Claude control test 6).

MEDIA FOLDER: <owner fills in>

HOW THE MAC DIFFERS FROM WINDOWS (read this once)
- The menus are in the menu bar at the top of the SCREEN, not in the window: ClipForge, File, Edit, Add, Clip, Part, Sound, Text and speech, View, Playback, Window, Help. Settings… is in the File menu (Cmd+comma). About ClipForge is in the ClipForge menu and in Help. Quit is ClipForge > Quit ClipForge (Cmd+Q). A switched-on menu item has a ✓ after its name; a greyed item says why in brackets in its name.
- Keys: Cmd where Windows has Ctrl (Cmd+Z, Cmd+Shift+Z, Cmd+E, Cmd+D, Cmd+F, Cmd+Shift+H, Cmd+Shift+T, Cmd+comma); Option where Windows has Alt; Help is Cmd+? (that is Cmd+Shift+/), not F1; the Delete key above Return deletes; a MacBook has no Home and End keys (Fn+Left and Fn+Right). Single letters (S, Q, W, I, O, M, J, K, L), Space, Esc, + and - are the same. If a key of a step does nothing, use the menu item, set Partial and write down which key.
- "Right-click" is a click with two fingers on the trackpad (a secondary click).
- File windows are the ones of macOS: in an open or save window press Cmd+Shift+G, paste a path and press Return to go there. Paths are written with forward slashes, for example /Users/name/Movies/ClipForge-test/video.mp4. To copy the path of a file in Finder: right-click the file, hold Option and choose Copy "…" as Pathname.
- macOS asks before an app may read some folders (Documents, Downloads, Desktop, removable disks) and before it opens an app it cannot verify. NEVER answer such a question and never change anything in System Settings without asking the owner first; copy the exact words of the question into the note. ClipForge does not record sound or pictures, so it should never ask for the microphone, the camera or screen recording. (What your own tool needs to see and control the Mac is the owner's business and not a finding.)

BEFORE YOU START
- Fill in "Device" (for example "MacBook Air M3, macOS 15.6") and "Tester".
- Do group A first: it installs or updates the app. Then fill in "Version shown in the app" (Help > About ClipForge > Copy version info, paste). If it does not match the build named at the top of this page (a red warning appears), tell the owner and say so in the Summary.
%(files)s- The easiest way to add files without the macOS file window: Add > Add from a folder path…, paste the path (for example /Users/name/Movies/ClipForge-test), tick the files.
- Do the groups in order: later steps build on the projects made earlier ("Round 7 long", "Round 7 test", "Round 7 two voices", "Round 7 basics"). If time runs out: groups A (install, update, Claude) and B (the long file: does it freeze, and Copy version info with the performance log) matter most, then C to H (everything 1.17 changed), then S (export) and P (speech to text). Say in the Summary where you stopped.
%(tip)s%(stops)s%(rules)s""" % dict(last=chr(64 + len(STEPS_7M)), files=files, tip=tip, stops=stops, rules=rules)

INSTR_7M = _mac_instr()

ROUNDS = {
 "3": dict(steps=STEPS_3, instr=INSTR_3,
         opts=["", "Works", "Problem", "Partial", "Not tested", "Needs a person"], result="Status",
         tags={"listen": "needs a person with headphones"}),
 "4": dict(steps=STEPS_4, instr=INSTR_4,
         opts=["", "PASS", "FAIL", "Partial", "Not tested", "Needs the owner"], result="Result",
         tags={"listen": "ask the owner to listen", "watch": "ask the owner to watch"}),
 "5": dict(steps=STEPS_5, instr=INSTR_5,
         opts=["", "PASS", "FAIL", "Partial", "Not tested", "Needs the owner"], result="Result",
         tags={"listen": "ask the owner to listen", "watch": "ask the owner to watch"},
         device="e.g. Windows 11 laptop, RTX 4070",
         note="What happened? Copy texts and numbers the step asks for; Owner: for what the owner saw or heard",
         crash="If the app closed by itself or froze: what were you doing?"),
 "6": dict(steps=STEPS_6, instr=INSTR_6,
         opts=["", "PASS", "FAIL", "Partial", "Not tested", "Needs the owner"], result="Result",
         tags={"listen": "ask the owner to listen", "watch": "ask the owner to watch"},
         device="e.g. Windows 11 laptop, RTX 4070",
         note="What happened? Copy texts and numbers the step asks for; Owner: for what the owner saw or heard",
         crash="If the app closed by itself or froze: what were you doing?"),
 "7": dict(steps=STEPS_7, instr=INSTR_7, numbered=True,
         opts=["", "PASS", "FAIL", "Partial", "Not tested", "Needs the owner"], result="Result",
         tags={"listen": "ask the owner to listen", "watch": "ask the owner to watch"},
         device="e.g. Windows 11 laptop, RTX 4070",
         note="What happened? Copy texts and numbers the step asks for; Owner: for what the owner saw or heard",
         crash="If the app closed by itself, froze or stopped answering: the time, the step, what was on screen. Then paste Help > Copy version info here (it carries the performance log)."),
 "7-mac": dict(steps=STEPS_7M, instr=INSTR_7M, numbered=True, title="ClipForge test round 7: Mac",
         opts=["", "PASS", "FAIL", "Partial", "Not tested", "Needs the owner"], result="Result",
         tags={"listen": "ask the owner to listen", "watch": "ask the owner to watch"},
         device="e.g. MacBook Air M3, macOS 15.6",
         note="What happened? Copy texts and numbers the step asks for; Owner: for what the owner saw or heard",
         crash="If the app closed by itself, froze or stopped answering: the time, the step, what was on screen. Then paste Help > Copy version info here (it carries the performance log), and the text of the Report… button if macOS said that ClipForge quit unexpectedly."),
 "7-phone": dict(steps=STEPS_7P, instr=INSTR_7P, numbered=True, title="ClipForge test round 7: Android phone",
         opts=["", "PASS", "FAIL", "Partial", "Not tested", "Needs the owner"], result="Result",
         tags={"listen": "ask the owner to listen", "watch": "ask the owner to watch"},
         device="e.g. Samsung Galaxy S23, Android 15, via Link to Windows",
         note="What happened? Start with Owner: for what the owner saw or heard",
         crash="If the app closed by itself, froze or stopped answering: the time, the step, what was on screen (include any message Android showed, and what Copy version info gave)."),
 "6-phone": dict(steps=STEPS_6P, instr=INSTR_6P, title="ClipForge test round 6: Android phone",
         opts=["", "PASS", "FAIL", "Partial", "Not tested", "Needs the owner"], result="Result",
         tags={"listen": "ask the owner to listen", "watch": "ask the owner to watch"},
         device="e.g. Samsung Galaxy S23, Android 15, via Link to Windows",
         note="What happened? Start with Owner: for what the owner saw or heard",
         crash="If the app closed by itself or froze: what were you doing? (include any message Android showed)"),
 "4-phone": dict(steps=STEPS_4P, instr=INSTR_4P, title="ClipForge test round 4: Android phone",
         opts=["", "PASS", "FAIL", "Partial", "Not tested", "Needs the owner"], result="Result",
         tags={"listen": "ask the owner to listen", "watch": "ask the owner to watch"},
         device="e.g. Samsung Galaxy S23, Android 15, via Phone Link",
         note="What happened? Start with Owner: for what the owner saw or heard",
         crash="If the app closed by itself or froze: what were you doing? (include any message Android showed)"),
}
DEFAULT_ROUND = "4"

ap = argparse.ArgumentParser(description="Generate a ClipForge test checklist.")
ap.add_argument("output", help="the HTML file to write")
ap.add_argument("--build", required=True, help='the build to test, e.g. "ClipForge 1.4.0 (build 21) · 16 Nov 2026, 07:20 UTC · 877e482"')
ap.add_argument("--round", default=DEFAULT_ROUND, choices=sorted(ROUNDS), help="test round (default: %s); picks the steps, title and browser storage" % DEFAULT_ROUND)
ap.add_argument("--media-folder", default="", help='rounds 7, 7-mac and 7-phone: the folder with the test files, written into the line "MEDIA FOLDER: ..." of the instructions (default: the placeholder stays)')
args = ap.parse_args()
R = ROUNDS[args.round]
MEDIA_LINE = "MEDIA FOLDER: <owner fills in>"
NSTEPS = sum(len(items) for _, items in R["steps"])
INSTR = R["instr"].replace("__NSTEPS__", str(NSTEPS)).replace("__NGROUPS__", str(len(R["steps"])))
if R.get("numbered"):
    assert INSTR.count(MEDIA_LINE) == 1, "the instructions need the media folder line once"
if args.media_folder:
    assert MEDIA_LINE in INSTR, "this round has no media folder line"
    INSTR = INSTR.replace(MEDIA_LINE, "MEDIA FOLDER: " + args.media_folder)
TITLE = R.get("title", "ClipForge test round " + args.round)
ids = [st[0] for _, items in R["steps"] for st in items]
assert len(ids) == len(set(ids)), "step ids must be unique"

data = {"device": "", "tester": "", "build": args.build, "version": "", "summary": "", "crash": "", "items": {}}
page = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>__PTITLE__</title>
<style>
:root{--bg:#f5f6fa;--card:#fff;--fg:#161a26;--muted:#5b6274;--line:#dfe2ec;--accent:#4257d6;--ok:#1f7a4d;--bad:#a8322b;--part:#9a5b00;--human:#6a3fb0}
@media (prefers-color-scheme:dark){:root{--bg:#0f1118;--card:#181b25;--fg:#eceef5;--muted:#9aa1b5;--line:#2a2f3f;--accent:#8c9bff;--ok:#6fd3a0;--bad:#ff9c94;--part:#f0b95a;--human:#c3a6ff;color-scheme:dark}}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,-apple-system,Segoe UI,sans-serif}
.wrap{max-width:900px;margin:0 auto;padding:28px 16px 64px;display:flex;flex-direction:column;gap:20px}
h1{margin:0;font-size:1.8rem}h2{margin:8px 0 0;font-size:1.2rem}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;display:flex;flex-direction:column;gap:8px}
.instr{white-space:pre-wrap;font-size:.95rem}
.step{border-left:6px solid var(--line)}
.step[data-s="Works"]{border-left-color:var(--ok)}.step[data-s="Problem"]{border-left-color:var(--bad)}.step[data-s="Partial"]{border-left-color:var(--part)}.step[data-s="Needs a person"]{border-left-color:var(--human)}
.step[data-s="PASS"]{border-left-color:var(--ok)}.step[data-s="FAIL"]{border-left-color:var(--bad)}.step[data-s="Needs the owner"]{border-left-color:var(--human)}
.do{margin:0;font-size:.95rem}
.step h3{margin:0;font-size:1.02rem}.exp{color:var(--muted);font-size:.93rem;margin:0}
.tag{font-size:.75rem;font-weight:600;border:1px solid var(--line);border-radius:999px;padding:1px 8px;margin-left:6px;color:var(--muted)}
.row{display:flex;gap:12px;flex-wrap:wrap;align-items:center}
select,input,textarea,button{font:inherit;color:inherit;background:var(--card);border:1px solid var(--line);border-radius:8px;padding:8px}
textarea{width:100%;box-sizing:border-box;min-height:64px}
button{cursor:pointer;background:var(--accent);color:#fff;border:0;font-weight:600;padding:10px 16px}
.counts{display:flex;gap:16px;flex-wrap:wrap;font-weight:600}
label{display:flex;flex-direction:column;gap:4px;font-size:.9rem;color:var(--muted)}
</style></head><body><div class="wrap">
<header class="card"><h1>__TITLE__</h1>
<p class="exp">Build: <b id="build"></b>. Fill in each step, then click <b>Download filled checklist</b> at the bottom and send the file back to Claude.</p>
<div class="row"><label>Device<input id="device" placeholder="__DEVICE__"></label><label>Tester<input id="tester" placeholder="e.g. ChatGPT agent, or your name"></label></div>
<label>Version shown in the app (required: About ClipForge &gt; Copy version info, then paste here)<textarea id="version" placeholder="ClipForge X.Y.Z (build N) · date, time UTC · commit" style="min-height:56px"></textarea></label>
<p class="exp" id="vwarn" style="color:var(--bad);margin:0"></p>
<div class="counts" id="counts"></div></header>
<section class="card"><h2>Instructions for the tester (person or AI agent)</h2><div class="instr" id="instr"></div></section>
<div id="steps" style="display:flex;flex-direction:column;gap:20px"></div>
<section class="card"><h2>Crash or freeze</h2><label>__CRASH__<textarea id="crash"></textarea></label></section>
<section class="card"><h2>Summary</h2><label>Most important problems first, plus anything confusing, slow or hard to find<textarea id="summary" style="min-height:120px"></textarea></label>
<div class="row"><button id="dl" type="button">Download filled checklist</button><span class="exp" id="saved"></span></div></section>
</div>
<script id="data" type="application/json">__DATA__</script>
<script>
const STEPS=__STEPS__;const INSTR=__INSTR__;
const OPTS=__OPTS__;const TAGS=__TAGS__;const NUM=__NUM__;const RESULT=__RESULT__;const NOTE=__NOTE__;
let data=JSON.parse(document.getElementById('data').textContent);
try{const s=localStorage.getItem('clipforge-round__ROUND__');if(s){const l=JSON.parse(s);if(l&&l.items)data=Object.assign(data,l);}}catch(e){}
document.getElementById('instr').textContent=INSTR;document.getElementById('build').textContent=data.build;
const root=document.getElementById('steps');
let stepNo=0;
for(const [group,items] of STEPS){const h=document.createElement('h2');h.textContent=NUM?group+' ('+items.length+(items.length===1?' step)':' steps)'):group;root.appendChild(h);
 for(const st of items){const five=st.length>4,id=st[0],title=st[1],act=five?st[2]:'',exp=five?st[3]:st[2],tag=st[st.length-1];const it=data.items[id]||(data.items[id]={status:"",note:""});
  const c=document.createElement('article');c.className='card step';c.dataset.s=it.status;
  stepNo++;const t=document.createElement('h3');t.textContent=NUM?stepNo+'. '+title:title;for(const k of (tag?tag.split(','):[])){const g=document.createElement('span');g.className='tag';g.textContent=TAGS[k]||k+' only';t.appendChild(g);}
  const d=document.createElement('p');d.className='do';d.textContent='Do: '+act;
  const p=document.createElement('p');p.className='exp';p.textContent='Expected: '+exp;
  const row=document.createElement('div');row.className='row';const sel=document.createElement('select');sel.setAttribute('aria-label',RESULT+': '+title);
  for(const o of OPTS){const op=document.createElement('option');op.value=o;op.textContent=o||RESULT+'...';if(o===it.status)op.selected=true;sel.appendChild(op);}
  row.appendChild(sel);const ta=document.createElement('textarea');ta.setAttribute('aria-label','Note: '+title);ta.placeholder=NOTE;ta.value=it.note;
  sel.addEventListener('change',()=>{it.status=sel.value;c.dataset.s=sel.value;save();});ta.addEventListener('input',()=>{it.note=ta.value;save();});
  if(act)c.append(t,d,p,row,ta);else c.append(t,p,row,ta);root.appendChild(c);}}
for(const k of ['device','tester','version','summary','crash']){const e=document.getElementById(k);e.value=data[k]||'';e.addEventListener('input',()=>{data[k]=e.value;save();});}
function counts(){const n={};let total=0;for(const [,items] of STEPS)for(const [id] of items){total++;const s=data.items[id].status||'Not done yet';n[s]=(n[s]||0)+1;}
 const el=document.getElementById('counts');el.textContent='';for(const [k,v] of Object.entries(n)){const s=document.createElement('span');s.textContent=k+': '+v;el.appendChild(s);}const s=document.createElement('span');s.textContent='Total: '+total;el.appendChild(s);}
function vcheck(){const v=(data.version||'').trim();const w=document.getElementById('vwarn');
 const b=data.build||'';const m=b.match(/\\d+\\.\\d+\\.\\d+ \\(build \\d+\\)/)||b.match(/\\d+\\.\\d+\\.\\d+/);const h=b.match(/\\b([0-9a-f]{7,40})\\s*$/);
 const bad=m&&!v.includes(m[0])?m[0]:(h&&!v.includes(h[1].slice(0,7))?h[1].slice(0,7):'');
 w.textContent=!v?'Please paste the version shown in the app (required).':(bad?'This is not the build named above ('+bad+'). Say so in the Summary.':'');}
function save(){counts();vcheck();try{localStorage.setItem('clipforge-round__ROUND__',JSON.stringify(data));document.getElementById('saved').textContent='Saved in this browser.';}catch(e){}}
counts();vcheck();
document.getElementById('dl').addEventListener('click',()=>{
 if(!(data.version||'').trim()&&!confirm('"Version shown in the app" is empty. Download anyway?'))return;
 const clone=document.documentElement.cloneNode(true);clone.querySelector('#data').textContent=JSON.stringify(data).replace(/</g,'\\\\u003c');
 clone.querySelector('#steps').innerHTML='';
 const blob=new Blob(['<!doctype html>\\n'+clone.outerHTML],{type:'text/html'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);
 const d=(data.device||'device').replace(/[^A-Za-z0-9]+/g,'-').slice(0,30);a.download='ClipForge-Test-Round-__ROUND__-results-'+d+'.html';document.body.appendChild(a);a.click();setTimeout(()=>{URL.revokeObjectURL(a.href);a.remove();},1000);});
</script></body></html>"""
esc = lambda t: html.escape(t, quote=True)
page = page.replace("__PTITLE__", esc(R.get("title", "ClipForge Test Round " + args.round))).replace("__TITLE__", esc(TITLE)).replace("__DEVICE__", esc(R.get("device", "e.g. MacBook Air M5, macOS 26.6 / Windows 11 laptop")))
page = page.replace("__CRASH__", esc(R.get("crash", "If the app closed by itself or froze: what were you doing? (paste a crash report if macOS shows one)")))
page = page.replace("__NOTE__", json.dumps(R.get("note", "What happened? Start with Mac: or Windows:")))
page = page.replace("__ROUND__", str(args.round)).replace("__DATA__", json.dumps(data)).replace("__STEPS__", json.dumps(R["steps"])).replace("__INSTR__", json.dumps(INSTR)).replace("__NUM__", json.dumps(bool(R.get("numbered")))).replace("__OPTS__", json.dumps(R["opts"])).replace("__TAGS__", json.dumps(R["tags"])).replace("__RESULT__", json.dumps(R["result"]))
with open(args.output, "w", encoding="utf-8") as f:
    f.write(page)
print(sum(len(i) for _, i in R["steps"]), "steps")
