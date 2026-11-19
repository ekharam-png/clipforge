# When something does not work

Explain the fix to the owner in one or two plain sentences. Do not paste
error text unless they ask.

## The `clipforge` tools are not there

ClipForge is not connected to this Claude yet. Tell them:

In ClipForge on the computer: **Help > Connect to Claude…**. From 1.14
that page does the set-up itself: a row for **Claude Desktop** and one for
**Claude Code**, each with a light and a **Connect** button. After
pressing it they must close Claude completely and open it again (Claude
Desktop: also quit it from the icon near the clock; Claude Code: a new
session, `/mcp` shows the list). The reason, if they ask: Claude reads its
list of tools when it starts and then starts the helper itself; ClipForge
does not need to be running and there is no server to switch on.

- The page's **Test** button runs the helper by itself: PASS there means
  the helper is fine and the problem is on Claude's side (not restarted,
  the entry was removed).
- **Details** on that page shows what Connect did; ask them to read it to
  you when Connect fails.
- The other ways still exist: the extension file (Claude > Settings >
  Extensions > Advanced settings > Install Extension…; double-clicking a
  .mcpb does not work with the Claude from the Microsoft Store) and the
  one line for a terminal with a Copy button.

It needs doing only once: from ClipForge 1.12 on the app keeps the helper
up to date by itself. The tools only work on the computer (Windows or
Mac), not on the phone, and not in claude.ai in a web browser.

## Is everything working? (after an update, or when in doubt)

Run `self_test`. It makes its own small sample video in a temporary
folder, runs the real tools on it (never on the owner's projects) and
returns a PASS / FAIL table in under a minute. Tell the owner the result
in one sentence; for a FAIL, the note in that row says what is wrong
(most often FFmpeg or the title fonts are missing).

## The tools appear twice, or answers come from an old version

An old hand-made `clipforge` entry in `claude_desktop_config.json` is still
there next to the extension. `get_status` shows which helper program is
running, its version, and whether it is the one the app installed. Ask them
to press **Connect** on Help > Connect to Claude… (it replaces an old
entry and says when the extension and an entry are both there: one of the
two must go) and restart Claude. After an app update, Claude uses the new
helper the next time Claude is started.

## "FFmpeg could not be found"

`get_status` gives the one-line fix. Windows: `winget install ffmpeg` in
Terminal; Mac: `brew install ffmpeg`. Then they must quit and reopen Claude.
Until then you can still rearrange, trim, title and change settings; adding
files, finding silences, freeze frames and exporting need FFmpeg.

## "… is open in the ClipForge app"

Ask them to go back to ClipForge's home screen (the project list) or close
the app, wait for their answer, then repeat the same edit. If they say it is
closed and it still refuses, the app may have crashed earlier: the mark
clears itself about 3 minutes after the app stopped; try again then.

## "The project file changed" / an edit was not saved

Something else (the app) saved the project in between. `get_project` again,
then redo the edit. Never force it.

## No projects found, or the wrong ones

`get_status` shows the projects folder. The app keeps projects in
`Documents/ClipForge/projects` (also when Documents is inside OneDrive). If
the folder is wrong, the helper has to be started with
`--projects-dir <folder>`: point them to the setup guide.

## A file is missing ("[FILE MISSING]")

The video, photo or song was moved, renamed or deleted. Ask where it is
now, then `relink_media` (`old_path` from `get_project`, `new_path` the new
place). It must be the same recording. Never move files yourself to "fix"
it.

## A file cannot be added

Check the path is a full path to a file (not a folder) and that it exists.
Unusual formats may not be readable; say which file and suggest they try
adding it in the ClipForge app.

## The export takes long or the call timed out

That is normal for long videos. The export keeps running on its own. Call
`get_export_status` (with the `job_id`, or without to list recent exports)
and keep polling with `wait_seconds: 45`. Do not start it again.

- `failed`: pass on the reason in plain words (disk full, a missing file).
- `lost`: the export's process stopped without finishing (the computer went
  to sleep or the program was closed). Start it once more and ask them to
  keep the computer awake.
- Since ClipForge 1.12 an export or a transcription keeps running when
  Claude or Claude Code is closed (also on Windows); open Claude again and
  call `get_export_status` to see how far it is. The computer must stay
  awake.

## The exported video is small or blurry

The first clip decides the size by default, and a clip sent through a chat
app is small. `set_project_settings` `video_size: "1080p"`, export again
under a new name.

## Music is cut off or stops suddenly at the end

Music does not move when clips are cut. `fit_music_to_video` (ask before
`loop: true`).

## It cut too much / too little silence

Undo (`undo`, or go back to the safety copy), then `remove_silences` with
`dry_run: true` and a `threshold_db` a few dB lower (cuts less) or higher
(cuts more) than the level the first run reported.

## The separately recorded voice is not in sync

`add_voice` / `align_audio` said "Could not line it up automatically", or
they see lips and voice apart. Causes: the camera recorded no sound, the
two files are from different takes, or very different sound (music playing
in the room). Ask for a moment they can name (a clap, the first word) in
both files, work out `offset_ms` = time in the voice file − time in the
video file, and set it with `align_audio`. Small corrections: `nudge_ms`
(positive = voice later; one frame is 33–40 ms). A voice that is right at
the start and wrong at the end drifts (`drift_ms` in the answer): the
recorders ran at slightly different speeds; ClipForge does not stretch
sound. Splitting the video and voice into shorter parts is not supported
either; say so.

## Speech-to-text: "no speech program was found"

`transcribe` needs a program on the computer; ClipForge finds these by
itself (`get_status` lists what it found):

- **FFmpeg 8 or newer with the whisper filter.** On Windows:
  `winget install ffmpeg` in PowerShell, then restart Claude. This is the
  simplest route and needs a language pack (below).
- **whisper.cpp** (`whisper-cli`; on a Mac `brew install whisper-cpp`):
  times every word and keeps more "um"s. Uses the same language packs.
- **faster-whisper** (`pip install whisper-ctranslate2`) or **OpenAI
  whisper** (`pip install openai-whisper`): time every word; they keep
  their own models and fetch them themselves the first time.

If you can run commands yourself (Claude Code), you may also run a whisper
program directly on the file, write an .srt and bring it in with
`import_srt` (`time_base: "source"`). Ask first.

## Speech-to-text: "a language pack is needed"

Nothing is downloaded without the owner's yes. Tell them: Small (about
140 MB) is quick with more mistakes, Medium (about 470 MB) is good, Large
(about 1.6 GB) is best. English has its own Small and Medium; the others
share files, and Large covers every language. After their answer:
`transcribe` with `quality` and `download_pack: true`. Packs live in the
`models` folder next to the projects folder and can be removed in the app
(Transcribe speech…).

## The transcript or the captions are wrong

Speech recognition makes mistakes. Say so; offer a larger pack
(`quality: "medium"`, `force: true`), giving the `language` instead of
"auto", or fixing single captions with `update_title`. The same wrong
word in many captions: `replace_in_captions` (dry run first). In the app
they can fix a caption in the Text window by double-clicking it.

## "Who speaks" looks wrong (`get_speech_map`, the colours on the timeline)

It is worked out from loudness. Loud music, laughter or a noisy room
count as talk; a very quiet speaker may be missed. Two people on ONE
microphone cannot be told apart: that needs one voice file per person
(`add_voice`). When one speaker shows up on the other's row, the two
files are probably not lined up (`align_audio`).

## Removing fillers found nothing, or made the video jumpy

- Found nothing: speech programs often leave "um" out, the FFmpeg filter
  nearly always. whisper.cpp / faster-whisper keep more.
- Jumpy: `list_auto_cuts` `sort: "risk"`, then `restore_cut` for the
  worst, or `cut_id: "all"`. Use `strength: "light"` next time.

## Something they ask for does not exist

Say so plainly and offer the nearest thing that works (section "start", "Not
available yet"). Do not attempt it with shell commands or other tools on
their files.
