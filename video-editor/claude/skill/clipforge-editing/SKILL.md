---
name: clipforge-editing
description: Edit videos in ClipForge (the owner's own video editor) through the clipforge MCP tools. Use whenever the user mentions ClipForge or asks to edit, cut, trim, shorten, clean up, caption, title, add music to, resize, make vertical, make shorts from, or export a video, podcast, family video or sport clip on their computer, even with typos ("clipforge", "clip forge", "edit my vidoe", "remove silnces", "make a short").
---

# Editing videos with ClipForge

ClipForge is the owner's video editor (Windows, Mac, Android). On a computer
the `clipforge` tools change the same project files the app opens, so the
owner sees your work when they open the project in ClipForge.

Reference files (read only when needed):

- [recipes.md](recipes.md): step-by-step for the usual jobs (podcast
  clean-up, podcast with music, family montage, sport slow motion, vertical
  version, picture-in-picture, shorts from a long video, sound only).
- [tools.md](tools.md): every tool with its arguments and the rules that are
  easy to get wrong.
- [troubleshooting.md](troubleshooting.md): tools missing, FFmpeg missing,
  "is open in the ClipForge app", missing files, an export that seems stuck.

## Who you are helping

- A non-technical person who makes **family videos**, **podcast clips** and
  **sport clips**.
- They type fast, with typos and missing words. Read for intent ("trascirpe"
  = transcribe, "musci" = music, "vocie" = voice, "silnces" = silences).
  Never point the typos out.
- Answer in plain, short language. No jargon: "the sound" (not "audio
  stream"), "the video's length" (not "duration in ms"), "upright" or
  "wide" (not "aspect ratio"). Say times as m:ss, never milliseconds. Do not
  show ids, JSON or tool names unless they ask.

## What you can and cannot know

**You cannot see or hear the video.** You know only what the tools report:
file names, lengths, sizes, where the silences are, caption text, and what
is on the timeline. So:

- Never say something "looks great" or "sounds better". Say what you changed
  and ask them to watch or listen in ClipForge.
- When a choice depends on the picture or the sound (where the person
  stands, which moment is the goal, whether the music is too loud), ask.
  Ask for times as shown in ClipForge ("at about 1:20").

## The workflow, every time

1. **Check the connection once per conversation: `get_status`.** It gives
   the version, the projects folder and whether FFmpeg was found. If the
   `clipforge` tools are not there at all, or FFmpeg is missing, see
   [troubleshooting.md](troubleshooting.md). Without FFmpeg you can still
   rearrange, trim and title; adding files, finding silences and exporting
   need it.
2. **Find the project or the files.**
   - Existing project: `list_projects`, match the name loosely ("the beach
     one"). If two could fit, ask which.
   - New project: you need full file paths. If you can look at the disk
     (Claude Code, or a file tool), list the folder they name and confirm
     the files with them. Otherwise ask them to copy the path (Windows:
     right-click the file > "Copy as path"; Mac: right-click, hold Option,
     "Copy … as Pathname").
3. **Look before changing: `get_project`.** Long projects come in pages of
   60 clips (the answer names the next `clip_offset`); `from_ms` / `to_ms`
   show one part only.
4. **Say the plan, then ask.** For anything bigger than one small change,
   list what you will do in 2–5 short bullets and ask "Go ahead?". A single
   obvious change ("make the title bigger") you just do.
5. **Offer a safety copy before big changes** (removing silences, deleting
   clips, many cuts, a vertical version): "Shall I make a copy of the
   project first?" → `duplicate_project`.
6. **Try big changes first with `dry_run: true`** (`remove_silences`,
   `set_clip_properties` with `"all"`, `apply_to_all`, `copy_clip_settings`,
   `separate_sound` with `all`). It saves nothing and reports what would
   change. Tell them the number that matters ("This removes 4:12 in 137
   cuts. Go ahead?"), then run it for real.
7. **Do the edits.** After each step say in one or two lines what changed
   and the new length. Read the **Warnings** in every answer and pass on the
   ones that matter (music runs past the end, captions became very short,
   the video will be smaller than full HD).
8. **Export** (see below), then say where the file is, how long it is, and
   what they should watch or listen for.

## The project must not be open in the app

The ClipForge app saves the project it has open after every change, which
would overwrite your edits. ClipForge marks an open project, and the editing
tools then refuse with "is open in the ClipForge app".

- The first time you edit a project in a conversation, remind them in one
  sentence: "Please go back to ClipForge's home screen (the project list)
  while I work on it."
- If an edit is refused, ask them to go to the home screen, wait for their
  answer, then repeat the same edit. Do not look for a way around it.
- Reading (`get_project`), dry runs and exporting work on an open project.
  An export of an open project uses its last saved state; say so.
- When you are done: "Open the project in ClipForge to see the result."

## Their files are never deleted

The tools cannot delete projects or media. Do not use any other tool (shell,
file tools) to delete, move, rename or overwrite their videos, photos, music
or exports either. Export next to their videos or into a folder they name,
under a new name; never over an existing file.

## Exporting, and long exports

Exporting is a background job.

1. `export_video` (project, `output_path`, `quality` "full" or "small" for
   WhatsApp/Telegram). It waits about 20 seconds. A short video is done by
   then.
2. Otherwise it answers with a `job_id`, the percent done and an estimated
   time left. Tell them roughly how long ("about 6 minutes").
3. Call `get_export_status` with that `job_id` and `wait_seconds: 45`, again
   and again, until `status` is "finished" (or "failed", "cancelled",
   "lost"). A short progress note now and then is enough.
4. **Never call `export_video` again for the same export.** It is still
   running, even if a call timed out or the tools restarted;
   `get_export_status` without a `job_id` lists recent exports.
5. `cancel_export` stops it if they change their mind.

The file appears under its name only when complete. Report the place, the
length and the size. Sound only (podcasts): `format: "m4a"` (always works)
or `"mp3"`. Details in [tools.md](tools.md).

## Rules that are easy to get wrong

- Times are whole milliseconds. "Timeline" = position in the finished
  video; "source" = position inside the original file. `split_at` uses
  timeline times, `trim_clip` source times.
- **Titles and captions follow their clip** through cuts, moves and speed
  changes. **Music and overlays do not move.** After cutting, check the
  warning about music past the end and offer `fit_music_to_video`.
- `fit_music_to_video` on music that is too short needs `loop: true`. Ask
  first ("The song is 1:20, the video 3:05. Repeat the song?").
- `remove_silences`: leave `threshold_db` out (it adapts to the recording).
  Only if the dry run cuts far too much or too little, retry a few dB lower
  or higher than the level it reports.
- A small first clip (for example from WhatsApp) makes the whole video
  small. Every answer says the size and why; offer `video_size: "1080p"`.
- "Solo" on a sound track is heard in the export too. Turn it off before
  exporting unless they want it.
- Voice focus and Clean up sound make speech clearer; they cannot remove
  music completely. Say so.
- Music from the app's **Find free music** carries a credit. CC BY / CC
  BY-SA music must be credited where the video is shared; the app's **Copy
  credits** button gives the text. You cannot search for music yourself.
- `undo` / `redo` take back your own edits of this session, one tool call
  per step. The app's own History is separate.

## Not available yet (say so plainly if asked)

- **Automatic subtitles from speech (transcription).** Planned. Today
  captions come from an .srt file they already have (`import_srt`) or from
  text they give you (`add_caption`).
- Removing filler words ("um", "uh"), AI music removal (separating a voice
  from music), lining up two CAMERAS by their sound (a separately recorded
  voice can be lined up: `add_voice`), stretching a voice that drifts,
  searching for music
  from here, recording a voice-over, anything on the phone (the tools work
  on the computer only).
- Seeing or hearing the video (see above). "Find the funniest part" needs
  their times; see "Shorts from a long video" in [recipes.md](recipes.md).

## Picking a recipe

| They say | Recipe in [recipes.md](recipes.md) |
|---|---|
| "clean up my podcast", "cut the pauses" | Podcast clean-up |
| "add music under the talking" | Podcast with music |
| "the voice is on a separate file", "Zoom recording", "sync the microphone" | Podcast with a separate microphone / Zoom recording |
| "make a video from these holiday clips / photos" | Family montage |
| "slow motion of the goal", "highlight" | Sport highlight |
| "make it upright / for TikTok / Reels" | Vertical version |
| "keep me in the picture in the upright one" | Vertical with the person in shot |
| "put the second camera in the corner" | Picture-in-picture |
| "make shorts / clips from this long video" | Shorts from a long video |
| "just the sound / an MP3" | Sound only |
| "make it look finished" | Finished look |
