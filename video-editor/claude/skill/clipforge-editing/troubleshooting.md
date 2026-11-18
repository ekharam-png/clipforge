# When something does not work

Explain the fix to the owner in one or two plain sentences. Do not paste
error text unless they ask.

## The `clipforge` tools are not there

ClipForge is not connected to this Claude yet. Tell them:

- **Claude Desktop:** install the ClipForge extension (the file ending in
  `.mcpb` from the ClipForge download page): double-click it, or Settings >
  Extensions > Advanced settings > Install Extension…, then restart Claude.
- **Claude Code:** run once in a terminal:
  `claude mcp add --scope user clipforge -- "<full path of clipforge-mcp>"`
- The tools only work on the computer (Windows or Mac), not on the phone,
  and not in claude.ai in a web browser.

The step-by-step guide is "Connect Claude to ClipForge"
(docs/claude-setup.html in the ClipForge download / repository).

## The tools appear twice, or answers come from an old version

An old hand-made `clipforge` entry in `claude_desktop_config.json` is still
there next to the extension. `get_status` shows the program path and version
in use. Ask them to remove the old entry (the setup guide shows which lines)
and restart Claude.

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
- On Windows with Claude Code: closing Claude Code while an export runs may
  stop the export. Ask them to keep it open until you say it is finished.

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

## Something they ask for does not exist

Say so plainly and offer the nearest thing that works (SKILL.md, "Not
available yet"). Do not attempt it with shell commands or other tools on
their files.
