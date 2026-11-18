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
#   python3 gen_checklist.py ClipForge-Test-Round-5.html       --round 5       --build "..."
#   python3 gen_checklist.py ClipForge-Test-Round-4.html       --round 4       --build "..."
#   python3 gen_checklist.py ClipForge-Test-Round-4-Phone.html --round 4-phone --build "..."
#
# --build is the build the testers should have: the version line from the
# CI run (its summary shows it, and the downloads are named
# ClipForge-<version>-build<n>-...). The tester pastes what the app itself
# says (Help > About ClipForge > Copy version info) into "Version shown in
# the app", so a mismatch is visible at once.
import argparse, json, html, sys

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

INSTR_5 = """You are testing ClipForge 1.12.0 (build 109), a video editor, on the owner's Windows PC. Problems are expected; your job is to find them and write them down precisely. This round checks only what is new in 1.10 and 1.11 on the computer: a voice recorded separately (the "What is this sound?" question, lining up, nudging, unlinking), speech to text (Transcribe speech…, language packs), Captions from speech…, the Transcript, Remove filler words… and Automatic cuts…, project names, the export window and the menus, plus five steps that check the basics still work. Older features were tested in round 4.

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

# labels of the tags, and the wording that differs (page title, hints in the
# Device and Note boxes). The key is also the browser-storage key and part of
# the name of the downloaded results file. Old rounds stay so their pages can
# be regenerated.
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
args = ap.parse_args()
R = ROUNDS[args.round]
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
const OPTS=__OPTS__;const TAGS=__TAGS__;const RESULT=__RESULT__;const NOTE=__NOTE__;
let data=JSON.parse(document.getElementById('data').textContent);
try{const s=localStorage.getItem('clipforge-round__ROUND__');if(s){const l=JSON.parse(s);if(l&&l.items)data=Object.assign(data,l);}}catch(e){}
document.getElementById('instr').textContent=INSTR;document.getElementById('build').textContent=data.build;
const root=document.getElementById('steps');
for(const [group,items] of STEPS){const h=document.createElement('h2');h.textContent=group;root.appendChild(h);
 for(const st of items){const five=st.length>4,id=st[0],title=st[1],act=five?st[2]:'',exp=five?st[3]:st[2],tag=st[st.length-1];const it=data.items[id]||(data.items[id]={status:"",note:""});
  const c=document.createElement('article');c.className='card step';c.dataset.s=it.status;
  const t=document.createElement('h3');t.textContent=title;for(const k of (tag?tag.split(','):[])){const g=document.createElement('span');g.className='tag';g.textContent=TAGS[k]||k+' only';t.appendChild(g);}
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
page = page.replace("__ROUND__", str(args.round)).replace("__DATA__", json.dumps(data)).replace("__STEPS__", json.dumps(R["steps"])).replace("__INSTR__", json.dumps(R["instr"])).replace("__OPTS__", json.dumps(R["opts"])).replace("__TAGS__", json.dumps(R["tags"])).replace("__RESULT__", json.dumps(R["result"]))
with open(args.output, "w", encoding="utf-8") as f:
    f.write(page)
print(sum(len(i) for _, i in R["steps"]), "steps")
