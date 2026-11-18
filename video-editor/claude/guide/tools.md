# ClipForge tools

All 62 tools of the `clipforge` MCP server (ClipForge 1.13). A test in the
ClipForge repository fails when a tool is missing from this file.

General rules:

- Times are whole milliseconds. **Timeline** = position in the finished
  video; **source** = position inside the original file.
- Ids (`project_id`, `clip_id`, `audio_id`, `title_id`, `overlay_id`,
  `track_id`) come from `list_projects` / `get_project` /
  `list_sound_tracks` and from the answers of the tools that add things.
- Edit tools answer with a short summary: counts, length, the output size
  and why, the ids added / removed / changed, warnings, who saved last.
  When one item (up to three) changed, the answer lists every changed
  setting as old -> new (`changes.clips.fields`); when many changed, which
  settings changed on how many items (`fieldsChanged`). A dry run of
  `apply_to_all` / `copy_clip_settings` shows the same under "What would
  change".
  `detail: "full"` adds the whole timeline (small projects only; otherwise
  page through `get_project`).
- Edit tools refuse while the project is open in the app (section "start").
- File paths are full paths. Files are used where they are, not copied, so
  they must stay in place.
- Adding media or music, `remove_silences`, `freeze_frame` and exporting
  need FFmpeg on the computer.

## The guide and the self-test

| Tool | What it does | Arguments worth knowing |
|---|---|---|
| `get_guide` | This guide, from inside the helper (always the installed version). Call with no arguments first in a conversation. | `section`: "start" (default), "recipes", "tools", "troubleshooting" |
| `self_test` | Checks the whole installation in under a minute with its own sample video in a temporary folder (create, add, split, speed, titles in Cyrillic and Hebrew, sound tracks, separate sound, silences, an export job checked with ffprobe, undo / redo, the open-in-app refusal, speech-to-text when installed). Never touches the owner's projects. Returns a PASS / FAIL table. | `keep_files` |

## Status and projects

| Tool | What it does | Arguments worth knowing |
|---|---|---|
| `get_status` | Version, which helper program runs and from where (and whether it is the one the app installed), projects folder, title fonts, FFmpeg found or not, running exports, and for speech-to-text: which speech programs and language packs are on the computer. Call first. | none |
| `list_projects` | All projects, newest first, with id, name, length. | none |
| `get_project` | The timeline: clips, music, overlays, titles, size and why, warnings, whether it is open in the app. Every media file is listed once in a `media` table (`m1`, `m2`, … with the full path, whether it is missing, how often it is used); clips, sound and overlays name the key. | `clip_offset` / `clip_limit` (30, max 300), `title_offset` / `title_limit`, `from_ms` / `to_ms` |
| `create_project` | New empty project. | `name`, `aspect` ("original", "9:16", "16:9", "1:1", "4:5") |
| `duplicate_project` | A copy (media shared, not copied). The safety copy, or a second version. | `name` |
| `rename_project` | New name. | `name` |
| `set_project_settings` | Shape, size, fades of the whole video, music lower under speech. | `aspect`, `video_size` ("match_first_clip", "720p", "1080p", "4k"), `fade_in_ms`, `fade_out_ms`, `duck_music` |
| `undo` / `redo` | Take back / redo YOUR last edit of this session (one tool call = one step). Refuses when the project changed since. | |
| `relink_media` | A file was moved or renamed ("[FILE MISSING]"): point every item at its new place. Must be the same recording. | `old_path`, `new_path` |

## Clips on the main track

| Tool | What it does | Arguments worth knowing |
|---|---|---|
| `add_media` | Adds videos and photos in the order given, at the end or at `index`. | `paths`, `index`, `photo_duration_ms` |
| `trim_clip` | Which part of the file is used. **Source** times. | `in_ms`, `out_ms`, `min_caption_ms` |
| `split_at` | Cuts the clip playing at a **timeline** time in two; nothing is removed. To cut a part out: split twice, `remove_clip` the middle. | `timeline_ms` |
| `remove_clip` | Takes a clip off the timeline; later clips move up. The file stays. | `clip_id` |
| `move_clip` | New place in the order. | `to_index` (0 = first) |
| `duplicate_clip` | A copy right after the clip. | `clip_id` |
| `set_clip_properties` | Everything about one clip, or every clip with `clip_id: "all"`. See below. | `dry_run`, `min_caption_ms` |
| `copy_clip_settings` | Look, fit / zoom, crop / position, and (video to video) speed and sound from one clip to others. Not trim, transition, fades. | `from_clip_id`, `to_clip_ids` (ids or `["all"]`), `dry_run` |
| `apply_to_all` | Like the app's "Apply to all clips". | `look`, `speed`, `sound` (true / false), `dry_run` |
| `freeze_frame` | Holds the picture at a timeline time; the video gets longer. | `at_ms`, `duration_ms` |
| `remove_silences` | Cuts the quiet gaps out of one clip, or all video clips when `clip_id` is left out. Keeps 150 ms of quiet around speech. Says how many cuts a minute it makes; every cut is remembered (`list_auto_cuts`, `restore_cut`). | `dry_run`, `threshold_db` (leave out: automatic), `min_silence_ms` (longer = gentler), `max_cuts_per_minute`, `min_caption_ms` |

`set_clip_properties` settings:

- Speed and sound: `speed`, `volume`, `muted`, `denoise` (the app's **Clean
  up sound**: less hiss and rumble), `voice_focus` 0–100 (**Voice focus**:
  clearer speech, quieter background; cannot remove music completely),
  `audio_channel` ("both", "left", "right") and `audio_track` (when the
  voice was recorded on its own side or track).
- Frame: `fit` ("fit" = whole picture with bars, "fill" = fills the frame
  and cuts the edges, "blur" = whole picture on a blurred background),
  `zoom`.
- Crop and position: `crop_shape` ("9:16", "16:9", "1:1", "4:5", "none")
  or `crop_x` / `crop_y` / `crop_width` / `crop_height` (0..1 of the
  picture); `rotation` 0 / 90 / 180 / 270 (absolute, clockwise),
  `flip_horizontal`, `flip_vertical`; `position_x` / `position_y` (-1..1,
  0 = middle) choose which part stays in the frame when the picture is
  bigger than it (fill, zoom). Position does nothing with "fit" and no zoom.
- Colour: `brightness`, `contrast`, `saturation`, `filter` ("warm", "cool",
  "black_and_white", "vintage", "vivid", "none"), `warmth` (-1 cooler .. 1
  warmer).
- Fades and transition: `fade_in_ms` / `fade_out_ms` (this clip's picture
  and own sound, from / to black; the way to start the first clip from
  black), `transition` INTO this clip ("none", "crossfade", "fadeBlack",
  "slideLeft", "slideUp") with `transition_ms`.
- Speeding clips up shortens their captions; the answer warns about
  captions under 1.2 s. Pass `min_caption_ms: 1200` to keep them readable.

## Titles and captions

| Tool | What it does | Arguments worth knowing |
|---|---|---|
| `add_title` | Text over the picture (default centred, white, bold, 3 s). | `text`, `start_ms`, `end_ms` or `duration_ms`, `style`, `font`, `position`, `align`, `outline`, `shadow`, `background`, `color`, `font_size`, `animation_in` / `animation_out` |
| `add_caption` | One subtitle line in the standard caption look. | `text`, `start_ms`, `end_ms` or `duration_ms` |
| `update_title` | Changes text, time or look of a title or caption. | same as `add_title` |
| `remove_title` | Removes one, or all captions with `all_captions: true` (titles stay). | |
| `import_srt` | Every cue of an .srt file becomes a caption. | `path` or `srt_text`, `time_base` ("timeline" / "source"), `offset_ms`, `replace_existing_captions` |
| `export_srt` | The captions as .srt text, written to `path` when given. | `time_base`, `path`, `overwrite` |
| `get_captions` | The captions on the timeline as compact text, whatever made them (a subtitle file, the speech, typed): one line each, "start-end [m:ss] Speaker: text". The way to READ a captioned project (500 captions are about 35 KB; `get_project` shows 30 at a time with their whole look). | `from_ms` / `to_ms`, `offset` / `limit` (400, max 2000), `format` ("text", "paragraphs"), `ids` (adds each `title_id`), `kind` ("captions", "titles", "all") |
| `replace_in_captions` | Find and replace over ALL captions at once (a misspelt name). **Dry run by default**: says how many places in how many captions and shows examples; `dry_run: false` does it as one undo step. | `find`, `replace`, `whole_word`, `case_sensitive`, `from_ms` / `to_ms`, `include_titles`, `dry_run` |

- `style`: "classic", "outline", "boxed", "yellow", "elegant",
  "handwritten" (sets several things at once; choose it first).
- `font`: "classic", "modern", "elegant", "handwritten". All have Latin,
  Cyrillic (Russian) and Hebrew letters.
- `position`: "top", "middle", "lower_third", "bottom"; `align`: "left",
  "center", "right" (also moves the text to that side).
- `animation_in` / `animation_out`: "fade", "slide_up", "pop", "none".
- Titles and captions follow their clip through cuts, moves and speed.
- Speakers in captions: a caption that starts with "Name:" is that
  speaker's; captions without a name belong to whoever spoke last. The
  app's Text window and `get_captions` read them the same way. To fix one
  caption use `update_title` with `text` (get the `title_id` from
  `get_captions` with `ids: true`); to fix the same word everywhere use
  `replace_in_captions` (`whole_word: true` for names).
- .srt time bases: "timeline" files fit only the cut they were made from.
  `export_srt` with `time_base: "source"` writes times of the ORIGINAL
  recording, and `import_srt` with `time_base: "source"` puts them back in
  the right place after any re-cut. `import_srt` warns when a file made
  here no longer fits.

## Music and sound tracks

| Tool | What it does | Arguments worth knowing |
|---|---|---|
| `add_music` | A music / voice / effect file on a sound track from `start_ms`. | `path`, `start_ms`, `in_ms`, `out_ms`, `volume`, `fade_in_ms`, `fade_out_ms`, `track_id` ("Music", "Voice", "Effects" or an id) |
| `update_audio` | Start, used part, volume, fades, clean-up, voice focus of a sound item. | `start_ms`, `in_ms`, `out_ms`, `volume`, `fade_in_ms`, `fade_out_ms`, `denoise`, `voice_focus` |
| `remove_audio` | Takes a sound item out. The file stays. | `audio_id` |
| `fit_music_to_video` | Music ends exactly with the video, 2 s fade-out. Too-short music is refused unless `loop: true` (repeats with short cross-fades). Do it after cutting. | `audio_id`, `loop` |
| `list_sound_tracks` | The tracks (top to bottom) and what is on each; `video` is the clips' own sound. | |
| `add_sound_track` | An empty track (at most 3). Default names "Voice" (speech), "Music", "Effects". | `name` |
| `update_sound_track` | Name, volume, mute, solo, lower under speech, counts as speech. `track_id: "video"` = the clips' own sound. | `name`, `volume`, `muted`, `solo`, `duck_under_speech`, `speech` |
| `remove_sound_track` | Removes an EMPTY track. | |
| `move_sound_track` | Order of the tracks. | `direction` ("up" / "down") |
| `move_audio_to_track` | Moves a sound item to another track. | `track_id`, `start_ms` |
| `separate_sound` | Copies a clip's own sound to a track (default "Voice") and mutes the clip. | `clip_id` or `all: true`, `track_id`, `dry_run` |
| `reattach_sound` | Puts a separated sound back on its clip. | `audio_id` |
| `add_voice` | A voice recorded on its own file (separate microphone, Zoom's file per speaker): lined up with the video by sound, linked to the clip (follows every cut), own speech track, camera muted. Answers `offset_ms`, `confidence`, `drift_ms`, `warnings`. | `path`, `clip_id` (default: best match), `track_name` (speaker), `mute_clip` (true), `align` (true), `offset_ms` (with `align: false`), `volume` |
| `align_audio` | "Line up with the video" for a sound item that is already there (music that is really a voice; a broken link). Or set the offset by hand, nudge, unlink. Nothing changes when the sounds do not match. | `audio_id`, `clip_id`, `offset_ms`, `nudge_ms` (+ = later), `mute_clip`, `link: false` |

- Items on one track never overlap: a taken place sends the item to the
  first free track, or next to what is in the way.
- Every sound item in `get_project` has a `role`: `voice`, `music` or
  `effect`. A voice lined up with the video also has `linked_clip` (the
  clip it follows) and `offset_ms` (time in the voice file = time in the
  video file + `offset_ms`).
- A linked voice follows its clip like a separated sound. `remove_silences`
  listens to the linked voice(s), not to the muted camera. `add_voice`
  under 0.5 confidence does not line up: it puts the voice at the clip's
  start, leaves the camera on and warns; do not report that as in sync.
- **Music does not move when clips are cut.** The answer warns when music
  runs past the end of the video (the export stops it there and moves its
  fade-out; without a fade-out it stops abruptly).
- A separated sound FOLLOWS its clip through trims, splits,
  `remove_silences` and deletes, until it is moved or trimmed with
  `update_audio`; then it stays put (that is how the sound starts a little
  before or after the picture).
- "Lower under speech" (`duck_under_speech` on a track, or `duck_music` for
  the project) is applied in the export only. Solo is heard in the export
  too.

## Overlay (picture-in-picture)

| Tool | What it does | Arguments worth knowing |
|---|---|---|
| `add_overlay` | A video or photo over the main video from `start_ms`. | `path`, `start_ms`, `in_ms` / `out_ms` (`duration_ms` for a photo), `layout`, `corner`, `size_percent`, `border`, `overlay_side`, `x` / `y`, `volume`, `muted`, crop / rotation / position like clips |
| `update_overlay` | Changes an overlay item. | same |
| `remove_overlay` | Takes it off. The file stays. | `overlay_id` |

- `layout`: "pip" (a corner; `corner`, `size_percent`, `border`),
  "side_by_side" / "top_bottom" (`overlay_side`), "full" (covers the
  picture: cut-away or second camera), "free" (`x` / `y`).
- One overlay row; items never overlap; titles stay on top. Overlays stay
  at their time when main clips are cut, so add them after cutting.
- Their sound plays with the video sound (`volume`, `muted`).

## Exporting

| Tool | What it does | Arguments worth knowing |
|---|---|---|
| `export_video` | Starts the export as a background job and waits up to `wait_seconds` (20, max 45). | `output_path`, `quality` ("full" / "small"), `format` ("video", "m4a", "mp3"), `fps` ("same", "24", "25", "30", "60"), `overwrite`, `hardware` |
| `get_export_status` | How a job is doing; without `job_id`, the recent exports. | `job_id`, `wait_seconds` (use 45) |
| `cancel_export` | Stops a running export; nothing is left under the output name. | `job_id` |

- Poll `get_export_status` until `status` is "finished", "failed",
  "cancelled" or "lost". Never start the same export twice.
- The render runs in its own process and survives a restart of the tools.
  Until it is complete the file is called `<name>.<id>.part.mp4`.
- `quality: "small"` (WhatsApp / Telegram): the frame is scaled to 720 on
  its short side when bigger and the bitrate capped; the answer says what
  it did.
- `format: "m4a"` / `"mp3"`: sound only; the path must end in `.m4a` /
  `.mp3`. M4A always works; MP3 needs an FFmpeg that can make MP3.
- When a track is lowered under speech the answer has a "Music under
  speech" report. It is worked out from the timeline, not measured.
- Never export over an existing file unless they ask (`overwrite`).

## Speech: what is said (1.11, computer only)

Needs a speech program on the computer (`get_status` lists what was found:
the system FFmpeg's whisper filter, whisper.cpp, faster-whisper or OpenAI
whisper) and, for the first two, a language pack. **Nothing is downloaded
unless `download_pack` is true** — ask the owner first.

| Tool | What it does | Arguments worth knowing |
|---|---|---|
| `transcribe` | Speech to text with a time for every word, as a background job. One transcript per media file (per speaker for linked voices), kept in the project folder, valid through every cut. Files already done are skipped. | `language` ("auto", "en", "ru", "he", …), `quality` ("auto" = largest pack installed, "small", "medium", "large"), `download_pack`, `clip_id`, `backend`, `force`, `wait_seconds` |
| `get_transcribe_status` | How the job is doing; `wait_seconds` up to 45. Without `job_id`: recent jobs. | `job_id`, `wait_seconds` |
| `cancel_transcribe` | Stops the job; finished files keep their transcripts. | `job_id` |
| `get_transcript` | What is said, with times. Default: timeline time, one line per phrase ("start-end [m:ss] Speaker: text", ms). | `format` ("text", "segments", "words"), `time_base` ("timeline", "source"), `from_ms` / `to_ms`, `clip_id`, `offset` / `limit` |
| `find_in_transcript` | Where a word or phrase is said: times, clip, speaker, the words around it. | `phrase`, `prefix`, `limit` |
| `captions_from_transcript` | Captions from the speech: 1–2 lines of about 32–42 characters, split at sentences and pauses, never overlapping; the project's caption look; Hebrew drawn right to left. | `dry_run`, `from_ms` / `to_ms`, `max_line_chars`, `max_lines`, `min_duration_ms`, `max_duration_ms`, `replace_existing`, `keep_filler_sounds`, title style arguments |
| `remove_fillers` | Cuts "um", "uh", "э-э", "אה"… out, gently. **Dry run by default.** Reports found / cut / left because too close / left because the picture would jump, time saved, cuts per minute, the 5 riskiest cuts. | `strength` ("light" default, "normal", "strong"), `dry_run`, `include_word_fillers`, `fillers`, `language`, `allow_estimated_times`, `jump_check`; advanced: `min_cut_ms`, `min_distance_ms`, `max_cuts_per_minute`, `min_piece_ms`, `pad_ms` |
| `list_auto_cuts` | The automatic cuts the project remembers (fillers, silences, and parts the owner cut out from the app's Text window, kind "text"): id, word, file and part removed, by whom, jump score, dissolve; totals. | `kind`, `sort` ("time", "risk"), `offset` / `limit` |
| `restore_cut` | Puts a cut back (the two pieces become one clip again), or all of them. | `cut_id` (an id or "all"), `kind`, `dry_run` |
| `make_short` | A NEW project with only one part of this one's timeline: upright 9:16 by default, 1080p, captions from the speech. The original is untouched. | `from_ms`, `to_ms`, `name`, `shape`, `captions` |

`remove_fillers` strengths (every one leaves no piece shorter than 0.6 s):

| | light | normal | strong |
|---|---|---|---|
| shortest cut | 350 ms, standing alone between pauses | 200 ms | everything found |
| closest two cuts | 2.5 s | 1.5 s | 0.7 s |
| most cuts a minute | 4 | 8 | no limit |
| picture would jump | left in | left in | cut anyway |
| slight picture change | cut with a short dissolve | same | same |

## Who speaks when (1.13, no transcript needed)

| Tool | What it does | Arguments worth knowing |
|---|---|---|
| `get_speech_map` | Who talks when, from the SOUND: per speaker (a speech track: a voice added with `add_voice`, or a voice-over; without speech tracks the video's own sound is the one speaker) the stretches of talk on the timeline as it is cut now, the total and the share of the talking. Default `view: "turns"`: speaker turns in time order, "start-end [m:ss] Name 12.4 s". | `view` ("turns", "stretches"), `from_ms` / `to_ms`, `speaker`, `min_ms`, `offset` / `limit` (300, max 2000) |

- It is worked out from loudness with the same adaptive rule as
  `remove_silences`. Microphones recorded together are compared: one
  speaker heard faintly in the other's microphone does not count, both
  loud at once is an overlap (the turns then overlap).
- A turn's start and end are safe cut points (`split_at`, then
  `remove_clip`). Leave about 150 ms of air; check a doubtful spot with
  `view: "stretches"` and `from_ms` / `to_ms`.
- It tells loud from quiet, not speech from music or laughter, and not
  WHAT is said: for that, `transcribe` and `get_transcript`.
- The first call listens to each file once (a few seconds for 40
  minutes) and keeps the result; later calls are instant.
- The app draws the same thing on the timeline: sound waves on every
  sound, each speaker's talk in that speaker's colour.

Word times: whisper.cpp, faster-whisper and OpenAI whisper time every
word; the FFmpeg filter times phrases only (word times are then
estimated: fine for captions, reading and shorts; `remove_fillers` refuses
to cut unless `allow_estimated_times`). The FFmpeg filter also usually
leaves "um" out of the text.
