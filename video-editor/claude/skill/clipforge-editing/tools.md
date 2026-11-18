# ClipForge tools

All 47 tools of the `clipforge` MCP server (ClipForge 1.10). A test in the
ClipForge repository fails when a tool is missing from this file.

General rules:

- Times are whole milliseconds. **Timeline** = position in the finished
  video; **source** = position inside the original file.
- Ids (`project_id`, `clip_id`, `audio_id`, `title_id`, `overlay_id`,
  `track_id`) come from `list_projects` / `get_project` /
  `list_sound_tracks` and from the answers of the tools that add things.
- Edit tools answer with a short summary: counts, length, the output size
  and why, the ids added / removed / changed, warnings, who saved last.
  `detail: "full"` adds the whole timeline (small projects only; otherwise
  page through `get_project`).
- Edit tools refuse while the project is open in the app (SKILL.md).
- File paths are full paths. Files are used where they are, not copied, so
  they must stay in place.
- Adding media or music, `remove_silences`, `freeze_frame` and exporting
  need FFmpeg on the computer.

## Status and projects

| Tool | What it does | Arguments worth knowing |
|---|---|---|
| `get_status` | Version, program path, projects folder, title fonts, FFmpeg found or not, running exports. Call first. | none |
| `list_projects` | All projects, newest first, with id, name, length. | none |
| `get_project` | The timeline: clips, music, overlays, titles, size and why, warnings, whether it is open in the app. | `clip_offset` / `clip_limit` (60, max 300), `title_offset` / `title_limit`, `from_ms` / `to_ms` |
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
| `remove_silences` | Cuts the quiet gaps out of one clip, or all video clips when `clip_id` is left out. Keeps 150 ms of quiet around speech. | `dry_run`, `threshold_db` (leave out: automatic), `min_silence_ms`, `min_caption_ms` |

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

- `style`: "classic", "outline", "boxed", "yellow", "elegant",
  "handwritten" (sets several things at once; choose it first).
- `font`: "classic", "modern", "elegant", "handwritten". All have Latin,
  Cyrillic (Russian) and Hebrew letters.
- `position`: "top", "middle", "lower_third", "bottom"; `align`: "left",
  "center", "right" (also moves the text to that side).
- `animation_in` / `animation_out`: "fade", "slide_up", "pop", "none".
- Titles and captions follow their clip through cuts, moves and speed.
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
