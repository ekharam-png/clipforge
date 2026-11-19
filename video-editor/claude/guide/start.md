# Editing videos with ClipForge

ClipForge is the owner's video editor (Windows, Mac, Android). On a computer
the `clipforge` tools change the same project files the app opens, so the
owner sees your work when they open the project in ClipForge.

This guide lives inside the `clipforge` tools themselves (`get_guide`), so
it always matches the version of ClipForge that is installed. This is the
"start" section; the others, read only when needed:

- `get_guide` section "recipes": step-by-step for the usual jobs (podcast
  clean-up, podcast with music, family montage, sport slow motion, vertical
  version, picture-in-picture, shorts from a long video, sound only).
- `get_guide` section "tools": every tool with its arguments and the rules
  that are easy to get wrong.
- `get_guide` section "troubleshooting": FFmpeg missing, "is open in the
  ClipForge app", missing files, an export that seems stuck, and
  `self_test` to check that everything works on this computer.

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

**You cannot see the picture.** Since ClipForge 1.11 you CAN know what is
said: `transcribe` turns the speech into text with times, and
`get_transcript` / `find_in_transcript` let you read and search it.
Captions that are already on the timeline (from a subtitle file, say) are
read with `get_captions`, and `get_speech_map` tells you WHO talks WHEN
from the sound alone. Apart
from that you know only what the tools report: file names, lengths, sizes,
where the silences are, caption text, and what is on the timeline. So:

- Never say something "looks great" or "sounds better". Say what you changed
  and ask them to watch or listen in ClipForge.
- When a choice depends on the picture or on how it sounds (where the
  person stands, which moment is the goal, whether the music is too loud),
  ask. Ask for times as shown in ClipForge ("at about 1:20").
- A transcript is what a program heard, not the truth: names, numbers and
  quiet words come out wrong, more so with a small language pack and in
  Hebrew. Quote it as "the transcript says…", and let them read captions
  before they publish. Before a video is transcribed you still cannot see
  or hear it at all.

## The workflow, every time

1. **Check the connection once per conversation: `get_status`.** It gives
   the version, the projects folder and whether FFmpeg was found. If the
   `clipforge` tools are not there at all, or FFmpeg is missing, see
   `get_guide` section "troubleshooting". Without FFmpeg you can still
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
   30 clips (the answer names the next `clip_offset`); `from_ms` / `to_ms`
   show one part only. Files are listed once (`m1`, `m2`, …) and the
   clips name the key.
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
or `"mp3"`. Details in `get_guide` section "tools".

## Speech: transcripts, captions, fillers, shorts

- **Transcribe once.** `transcribe` (give the `language` when you know it)
  starts a background job; poll `get_transcribe_status` like an export. The
  transcript belongs to the media FILE and stays right through every cut,
  so it does not matter whether you transcribe before or after editing.
- **Nothing is ever downloaded without the owner's yes.** When a language
  pack is missing, `transcribe` says which sizes exist (Small about 140 MB:
  quick, more mistakes; Medium about 470 MB: good; Large about 1.6 GB:
  best) and stops. Tell them the size in plain words, ask, and only then
  call again with `quality` and `download_pack: true`. When no speech
  program is installed at all, pass on what `get_status` says is needed.
- `get_transcript` is compact by default (one line per phrase); page long
  talks with `offset`. Use `format: "words"` only around a cut point.
- `captions_from_transcript`: dry run, show a few, then add. Ask them to
  read the captions through.
- **Removing filler words: gentle.** ALWAYS `remove_fillers` with the
  default dry run first and the default `strength: "light"`. Tell the owner
  the numbers in plain words: "I would remove 23 of 61 fillers, about 3
  cuts a minute, saving 19 seconds; 9 were left because the picture would
  jump." Only then `dry_run: false`. Never use `"strong"` unless the owner
  asks for it or the result is sound only. After cutting, give them the 3–5
  times from `riskiest` to watch. If they say it feels jumpy:
  `restore_cut` for the riskiest ones, or `cut_id: "all"`.
- **A budget for cuts.** `remove_silences` and `remove_fillers` both report
  cuts per minute. For a video where the speaker is seen, keep the total at
  about 6 a minute or less; do not run both hard on the same video without
  adding the two numbers up. `list_auto_cuts` shows what was cut so far.
- `make_short` copies the project and keeps one part; the long project is
  never cut. `suggest_shorts` lists candidate passages (whole sentences
  with times and simple signals) for YOU to judge; it does not judge.
  Propose 3-5 with a reason each and make them only after the owner chose.
- **Publishing**: ClipForge never uploads and has no logins. You prepare
  a kit: `set_publishing_notes` (offer three titles, the owner picks),
  `make_chapters`, then `export_kit` puts the files for YouTube, Shorts,
  WhatsApp and a podcast in one folder with a text file to paste from.
  Tell the owner where the folder is and what to paste where.
- **Captions that are already there** (imported subtitles, often with
  "Name:" in front): read them with `get_captions`, not page by page with
  `get_project`. A wrong word in one caption: `update_title`. The same
  wrong word in many: `replace_in_captions` (dry run first; tell the
  owner the count before doing it).
- **Who speaks when**: `get_speech_map` gives speaker turns with times
  from the sound itself, also when nothing was transcribed. Use it to cut
  by turns ("remove my long question at the start", "keep only the
  guest's answers") and to say how the talking is shared. It cannot tell
  what is said.
- In the app the owner reads all of this in the **Text window** (Edit >
  Text window): captions, transcript and titles as a document, with
  search; they can fix a caption there themselves.

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

- Speech-to-text when no speech program is on the computer (see
  `get_guide` section "troubleshooting"), and on the phone: it is a
  computer-only feature.
- Editing by changing the transcript text in the app (there is no such
  editor; you do the cutting with the tools).
- AI music removal (separating a voice from music), lining up two CAMERAS
  by their sound (a separately recorded voice can be lined up:
  `add_voice`), stretching a voice that drifts, searching for music from
  here, recording a voice-over, anything on the phone (the tools work on
  the computer only).
- Uploading or posting to YouTube, Instagram, TikTok or anywhere else,
  and anything that needs their account: ClipForge makes the files and
  the text, the owner posts them.
- Seeing the picture (see above). "Find the funniest part" works from what
  is SAID; see "Find the best shorts in a long video" in
  `get_guide` section "recipes".

## Picking a recipe

| They say | Recipe in `get_guide` section "recipes" |
|---|---|
| "clean up my podcast", "cut the pauses" | Podcast clean-up |
| "add music under the talking" | Podcast with music |
| "the voice is on a separate file", "Zoom recording", "sync the microphone" | Podcast with a separate microphone / Zoom recording |
| "make a video from these holiday clips / photos" | Family montage |
| "slow motion of the goal", "highlight" | Sport highlight |
| "make it upright / for TikTok / Reels" | Vertical version |
| "keep me in the picture in the upright one" | Vertical with the person in shot |
| "put the second camera in the corner" | Picture-in-picture |
| "make shorts / clips from this long video", "find the best moments" | Find the best shorts in a long video |
| "add subtitles", "caption what I say" | Captions from speech |
| "take out the ums" | Remove filler words, gently |
| "just the sound / an MP3" | Sound only |
| "get it ready for YouTube / to post", "make everything I need to publish" | From a long video to a publishing kit |
| "make it look finished" | Finished look |
