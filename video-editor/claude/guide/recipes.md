# ClipForge recipes

Each recipe is a plan to show the owner in a few plain bullets before you
start (`get_guide` section "start", "The workflow"). Skip steps they do not want. After every
recipe: tell them where the result is and what to watch or listen for, and
ask them to open the project in ClipForge.

Contents: Podcast clean-up · Podcast with music · Sound only · Family
montage · Sport highlight · Vertical version · Vertical with the person in
shot · Picture-in-picture · Captions from speech · Remove filler words,
gently · Find the best shorts in a long video · Finished look

## Podcast clean-up

1. Offer a safety copy (`duplicate_project`).
2. `remove_silences` with `dry_run: true`. Tell them how much it removes
   and in how many cuts. If that sounds wrong to them (far too much / too
   little), retry the dry run with `threshold_db` a few dB lower / higher
   than the level it reported.
3. `remove_silences` for real. Pass `min_caption_ms: 1200` when the project
   has captions.
4. `set_clip_properties` with `clip_id: "all"`: `denoise: true`,
   `voice_focus: 50`.
5. Optional: speed 1.1–1.25 on all clips (ask; say the new length).
6. Captions: `transcribe`, then `captions_from_transcript` (see "Captions
   from speech"); or from an .srt they already have (`import_srt`; use
   `time_base: "source"` when the .srt was made from the uncut recording).
7. Export. Ask them to listen to two or three cuts: words must not be
   chopped.

## Podcast with music

1. `separate_sound` with `all: true` (try `dry_run` first): every clip's
   voice goes to the "Voice" track, which counts as speech.
2. `add_music` with `track_id: "Music"` at 0 ms, `volume` 0.5–0.7,
   `fade_in_ms` 1000.
3. `update_sound_track` on the Music track: `duck_under_speech: true`.
4. `remove_silences` (the separated voice follows the picture).
5. `fit_music_to_video` (ask before `loop: true`).
6. Export. The answer has a "Music under speech" report; it is worked out
   from the timeline, not measured, so say "the music should drop while
   people talk — please listen at 0:30".

## Podcast with a separate microphone / Zoom recording

They have a video and, next to it, sound files that were recorded at the
same time: a separate microphone, a recorder, or a Zoom local recording
(one `video….mp4` plus one `audio<Name><digits>.m4a` per person).

1. `add_media` with the video only (sound files are not clips).
2. `add_voice` once per sound file, `path` only. It compares the file with
   the camera's sound, lines it up, links it and mutes the camera. The
   track is named after the speaker when the file name says who it is
   (`track_name` to set it). At most 3 sound tracks: with music, two
   voices fit; say so if they have more.
3. Read the answer: `confidence` 0.5 or more = lined up; report
   `offset_ms` in seconds. A warning "Could not line it up automatically"
   means it is NOT in sync (the voice sits at the start of the clip, the
   camera is still on): ask them for a moment where a word or a clap is
   visible, or try `align_audio` with `offset_ms`, and tell them to check
   by eye. `drift_ms` over about 80: say the voice slowly drifts and that
   ClipForge cannot repair that.
4. Already in the project as music (the app before 1.10 put it on the
   Music track)? `align_audio` with its `audio_id` instead of adding it
   again.
5. Then the usual: `remove_silences` (`dry_run` first; it listens to the
   voice(s), the camera is muted), `update_audio` with `denoise` /
   `voice_focus` on the voice items, music with `duck_under_speech`,
   export. Ask them to watch a few lines of speech: lips and voice must
   match. If the voice is early or late, `align_audio` with `nudge_ms`
   (positive = later), 40 ms is one frame.

## Sound only (podcast as audio)

The podcast clean-up above, then `export_video` with `format: "m4a"` and an
`output_path` ending in `.m4a` (or `"mp3"` / `.mp3` when they ask for MP3;
if MP3 is refused because this FFmpeg cannot make it, offer M4A).

## Family montage

1. `create_project` (ask: upright 9:16 for phones, or wide 16:9 for a TV).
2. `add_media` with the videos and photos in the order they want (ask when
   unclear; by file name / date is a fair default — say which you used).
   Photos: `photo_duration_ms` 3000.
3. Different shapes mixed: `set_clip_properties` `"all"` with `fit: "blur"`
   (blurred background) or `"fill"` (fills the frame, cuts the edges).
4. Transitions: `transition: "crossfade"`, `transition_ms` 500–700 on every
   clip after the first.
5. Music: `add_music`, `volume` 0.6, then `set_project_settings`
   `duck_music: true` so it drops under talking, then
   `fit_music_to_video`.
6. Title on the first clip (`add_title`, 3 s); `set_project_settings`
   `fade_in_ms: 1000`, `fade_out_ms: 1500`.
7. If the answer says the video is small because the first clip is small:
   `video_size: "1080p"`.
8. Export full quality; `quality: "small"` too if they want to send it in a
   chat app.

## Sport highlight (slow motion)

1. Ask for the moment: "At what time in ClipForge does it happen, and how
   long should the slow part be?"
2. `split_at` just before and just after it (timeline times).
3. The middle piece: `set_clip_properties` `speed: 0.5` (or 0.25), optional
   `zoom: 1.3–1.5`.
4. Optional `freeze_frame` on the key moment (`at_ms`, `duration_ms` 1500).
5. Short title over it (`add_title`, `style: "outline"`,
   `animation_in: "pop"`), for example "GOAL!".
6. Export with `fps: "60"` when they say it was filmed at 50/60 frames per
   second (fast sport often is); `quality: "small"` for sharing.

## Vertical version (Reels / TikTok / Shorts)

1. `duplicate_project` ("… vertical"), so the wide version stays.
2. `set_project_settings` `aspect: "9:16"`.
3. Wide clips: `set_clip_properties` `"all"` `fit: "blur"` (whole picture,
   blurred bars) — the safe choice when you do not know where people are.
4. Captions / title if wanted. Export.

## Vertical with the person in shot

1. `duplicate_project` (offer), `aspect: "9:16"`.
2. `set_clip_properties` `"all"` `fit: "fill"`.
3. You cannot see where the person is. Ask: "In the wide picture, is the
   person on the left, in the middle or on the right? Is it the same for
   all clips?"
4. `position_x` -1 (left) / 0 (middle) / 1 (right), per clip or `"all"`.
5. Ask them to check in ClipForge; nudge with values in between (-0.5).
6. Export.

## Picture-in-picture (second camera, guest, screen)

1. Finish cutting the main track first (`remove_silences` etc.): overlays
   stay at their time and do not move with cuts.
2. `add_overlay` with the second file at its `start_ms`:
   `layout: "pip"`, `corner: "bottom_right"`, `size_percent: 30`,
   `border: true`.
3. `muted: true` when both cameras recorded the same voices (otherwise it
   echoes).
4. Other looks: `layout: "side_by_side"` (split screen), `"top_bottom"`,
   `"full"` (a cut-away; place several one after another to switch angles).
5. The two recordings must be lined up by the owner: ask at what time the
   second camera should start. Lining up by sound is not available.
6. Export; ask them to watch the first seconds of the overlay for sync.

## Cut by who is speaking (no transcript needed)

For a talk with one voice file per person (see above), or any video
where people take turns.

1. `get_speech_map`: read the totals (who talks how much) and the turns.
2. Say what you found in plain words ("Dana talks for 14 minutes, Sam for
   8; the first 40 seconds are Sam's introduction") and ask what should
   go or stay. You cannot know what is said without `transcribe`.
3. To take a turn out: `split_at` its start and its end (keep about
   150 ms of air on each side), then `remove_clip` the piece between.
   Work from the END of the video backwards, so that earlier times stay
   valid; or call `get_speech_map` again after each cut.
4. Tell them which times to watch. Linked voices follow the cuts.

## Fix captions that are already there

Subtitles they imported, or captions made from speech, with mistakes.

1. `get_captions` to read them (page with `offset` when it says so).
2. A name or word that is wrong everywhere: `replace_in_captions` with
   `whole_word: true`; the dry run says how many places. Tell them the
   number, then `dry_run: false`.
3. Single mistakes: `get_captions` with `ids: true` and `from_ms` /
   `to_ms` around the place, then `update_title` with the new `text`.
4. They can also do this themselves in the app's Text window (double
   click a caption).

## Captions from speech

1. `transcribe` with the `language` they speak ("en", "ru", "he"). If it
   answers that a language pack is needed, tell them the sizes and ask
   which (see the "start" section); then call again with `quality` and
   `download_pack: true`. Poll `get_transcribe_status` to the end.
2. `captions_from_transcript` with `dry_run: true`; show them the first
   few. Upright video gets shorter lines by itself.
3. For real (add `replace_existing: true` when captions are already
   there). Style with `position`, `style`, `font` as for any title.
4. Ask them to read the captions in ClipForge before exporting: names and
   numbers are where speech recognition goes wrong. Small packs make more
   mistakes, most of all in Hebrew; offer the Medium pack when they
   complain.

## Remove filler words, gently

1. `transcribe` (as above). A transcript made by the FFmpeg filter rarely
   contains "um" at all and has no exact word times: say so, and suggest
   whisper.cpp or faster-whisper if they care about fillers.
2. `remove_fillers` (dry run, strength "light" by default). Tell them the
   numbers plainly: found, would cut, cuts per minute, time saved, how many
   were left because the picture would jump.
3. On "go ahead": `dry_run: false`. Then give them the times in `riskiest`
   to watch.
4. "It feels jumpy": `list_auto_cuts` with `sort: "risk"`, `restore_cut`
   the worst, or `cut_id: "all"`. "Take out more": `strength: "normal"`,
   dry run first. `"strong"` only when they ask or for sound only.
5. Also cutting pauses? Add up the cuts per minute of `remove_silences`
   and `remove_fillers`; stay near 6 a minute or below for a talking head
   (`remove_silences` takes `max_cuts_per_minute` and a longer
   `min_silence_ms`).

## Find the best shorts in a long video

You can read what is said, so you can propose moments. You still cannot
see the picture: say so once.

1. **Transcribe**: `transcribe` (language, pack as above), poll
   `get_transcribe_status`.
2. **Read**: `get_transcript` (default text; page with `offset` until
   there is no `nextOffset`). A 25-minute talk is one or two answers.
3. **Propose 3–5 moments**, each 20–60 s, that stand on their own: a
   complete thought, a story with its ending, a strong claim, a funny
   exchange. Give for each the times as m:ss, a one-line reason, and the
   first words, for example: "12:31–13:08 — why sourdough fails the first
   time ('The mistake everyone makes…')". Start at the start of a sentence
   and end at the end of one: use `find_in_transcript` or
   `get_transcript` with `format: "words"` around the spot for the exact
   times, and leave about 300 ms before the first word and after the last.
4. **Wait for their choice.** They may change times or drop some.
5. **For each approved moment**: `make_short` with `from_ms`, `to_ms` and a
   `name`. It copies the project, keeps only that part (titles, captions
   and linked voices follow), makes it upright 9:16 at 1080p and adds
   captions from the speech. The long project is not changed.
6. Upright framing: `set_clip_properties` `"all"` on the short with
   `fit: "blur"`, or `"fill"` + `position_x` after asking where the person
   is in the picture.
7. **Export** each short (`export_video`, `quality: "small"` suits phones),
   one at a time: start, poll `get_export_status` to the end, then the
   next. Tell them where the files are and ask them to watch each once.

No transcript possible (no speech program)? Then work from their times
("12:30–13:10") or from the long pauses `remove_silences` `dry_run: true`
lists, and say that you are choosing blind.

## Finished look

- `set_project_settings` `fade_in_ms: 1000`, `fade_out_ms: 1500`.
- One mood for all clips: `set_clip_properties` `"all"` with a `filter`
  ("warm", "cool", "black_and_white", "vintage", "vivid") — dry run first,
  and ask them to look at it; you cannot judge colours.
- Match the clips to one they like: `copy_clip_settings` from that clip to
  `["all"]`.
- Start one clip from black: `fade_in_ms` on that clip
  (`set_clip_properties`).
