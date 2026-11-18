# Claude control test 3 (for ClipForge 1.9.0)

Checks what versions 1.5 to 1.9 added to the Claude tools: status, short
answers and paging on a long project, automatic silence level and dry runs,
exports as background jobs (poll, cancel), the "open in the app" lock, video
size, sound tracks and ducking, crop / position / rotate, overlays, fades,
filters, title styles with Hebrew and Russian text, duplicate / copy
settings, fit and loop music, subtitle round trip, sound-only export, undo
and redo.

Before you start:

- Connect Claude first (docs/claude-setup.html): the ClipForge extension or
  the `claude mcp add` line, and the skill if you want to test it too.
- In ClipForge, go to the project list (or close the app). Step 14 asks you
  to open a project; until then leave ClipForge on the project list.
- It takes a while (a long export is part of it). Stay nearby: Claude asks
  you something at step 14.

Paste into a new Claude chat (Claude Code or Claude Desktop):

```
Run "ClipForge test 3" with the ClipForge tools (ClipForge 1.9.0).
Media folder: C:\Users\<you>\Videos\test
Exports and files you write go to: C:\Users\<you>\Videos\test\clipforge-test-output\test3\
Never delete, move, rename or overwrite anything of mine. Only create new projects whose names start with "T3 ".
If a T3 project or output file already exists from an earlier run, add " (2)" / "-2" to the new name instead of reusing it.
For each step report PASS / FAIL / SKIPPED and the numbers you saw (lengths as m:ss, sizes in MB).
If a step needs a file I do not have (for example music), say so, mark it SKIPPED and go on.
Do not guess: you cannot see or hear the videos, so never judge picture or sound; list those for me at the end.
Use dry_run where a step says so, and say exactly what the tool answered when something is refused.

A. Connection
 1. get_status. Report: the version line (must say 1.9.0 and a build number), the program path,
    the projects folder, the title fonts folder, ffmpeg and ffprobe with versions, the export jobs
    folder, and whether an export is running. FAIL if any of these is missing from the answer.
 2. Look at the media folder. Pick and name: LONG = the longest talking video (the podcast),
    SHORT = a video under 1 minute, PHOTO = a photo, MUSIC = a music file (mp3 / m4a / wav; also
    look in my Music folder). Tell me which files you chose.

B. Long podcast: short answers, silences, paging
 3. Create project "T3 Podcast" (shape 16:9) with LONG. The answer must be a SHORT summary
    (counts, length, size and why, ids) and not the whole timeline. Report the "size and why" line.
 4. Add a caption at 20 s ("Caption A", 2 s) and one at 40 s ("Caption B", 2 s).
 5. remove_silences with dry_run true and NO threshold. Report: the background noise it measured,
    the level it used, the number of cuts, the total time it would remove, and the first three
    cuts (position and length). Then get_project: it must still be ONE clip (nothing saved).
 6. remove_silences for real (no threshold, min_caption_ms 1200). Report pieces, time removed,
    new length, the new times of Caption A and B, and any warnings. The answer must be short
    (ids and counts, well under 10 KB) even with 100+ pieces. Compare with step 5: same numbers?
 7. Paging: get_project with defaults (at most 60 clips, and it must name the next clip_offset
    when there are more). Fetch the next page with that clip_offset. Then get_project with
    from_ms 60000 and to_ms 120000: only what plays in that minute. If the project has fewer
    than 61 clips, use clip_limit 20 to force pages. Report clips per page and the totals.
 8. undo: the project is one clip again. redo: the pieces are back. Report both clip counts.
 9. One small edit with detail "full" (set volume 1.0 on the first clip): the answer now has the
    timeline. Then the same without detail: short again.

C. Sound tracks, separate sound, ducking, loop
10. separate_sound with all true and dry_run true: report how many clips it would separate.
    Then for real. list_sound_tracks: a "Voice" track that counts as speech holds one sound per
    clip, and the clips are muted. reattach_sound for the first piece, then separate_sound that
    one clip again. Report the counts after each.
11. add_music MUSIC on track "Music" at 0 s, volume 0.6, fade-in 1 s. add_music MUSIC again at
    0 s on "Music": it must NOT overlap; report where it went (track and start). remove_audio
    the second one; if that left an empty extra track, remove_sound_track it. move_sound_track
    the Music track up, then down. Report the track order after each.
12. update_sound_track Music: duck_under_speech true. Then fit_music_to_video WITHOUT loop:
    if the music is shorter than the video it must refuse and say it is too short. Then with
    loop true: report the music's new end (must equal the video's end), loopMs, and the fade-out.
    (If the music is longer than the video, it is cut to the end instead: report that, loop SKIPPED.)
13. Read the warnings of the last answers: is any sound still past the end of the video? Report.

D. The "open in the app" lock (needs me)
14. STOP and ask me: "Please open the project T3 Podcast in the ClipForge app, then type: open".
    Wait for my answer. Then:
    a. get_project must show that it is open in the app.
    b. add_caption "Lock test" at 5 s must be REFUSED with a message that the project is open in
       the ClipForge app. Quote the message. Check the caption count did not change.
    c. set_clip_properties "all" speed 1.1 with dry_run true must be ALLOWED and save nothing.
    d. Ask me: "Please go back to ClipForge's project list, then type: closed". Wait.
    e. add_caption "Lock test" at 5 s again: must work now. Report the caption count.

E. Long export as a background job
15. export_video "T3 Podcast", full quality, to ...\test3\t3-podcast.mp4. Report the FIRST answer
    exactly: finished, or job_id + percent + estimated time left. If it is a job: call
    get_export_status with the job_id and wait_seconds 45 until status is finished. Do NOT call
    export_video again. Report: number of status calls, total minutes, percent values you saw,
    and at the end size, length, encoder. While it runs, look in the test3 folder (if you can):
    the file should have a ".part" name until it is complete.
    Also report the "Music under speech" part of the final answer (how long the music plays
    under speech, by how many dB), and say that it is calculated, not measured.
16. Start a second export: quality small, to ...\test3\t3-podcast-small.mp4. As soon as you have a
    job_id, cancel_export it. Then get_export_status: status must be cancelled, and there must be
    no t3-podcast-small.mp4 (and no leftover .part file) in the folder. If it finished before you
    could cancel, say so and mark SKIPPED. Then get_export_status without job_id: both exports
    are listed.
17. Start the small export again and let it finish (poll as in 15). Report what the answer says
    "small" changed (frame size, bitrate limit), and compare size and length with t3-podcast.mp4.
18. Sound only: export format m4a to ...\test3\t3-podcast.m4a, then format mp3 to
    ...\test3\t3-podcast.mp3. Report size and length of each (same length as the video?). If MP3 is
    refused, quote the message (M4A must work).

F. Subtitles round trip
19. export_srt "T3 Podcast" with time_base "source" to ...\test3\t3-source.srt, and with the default
    time base to ...\test3\t3-timeline.srt. Report the times of Caption A in both files (source must
    be 20 s; timeline is earlier by the silence removed before it).
20. duplicate_project to "T3 Podcast recut". In the copy: remove_title with all_captions true,
    then speed 1.25 on "all". import_srt t3-source.srt with time_base "source": report how many
    captions came back and where Caption A and B are now, and check they sit on the same
    footage (get_project around them). Then import_srt t3-timeline.srt with the default time
    base and replace_existing_captions true: it must WARN that this file was made for a
    different cut. Quote the warning. Finally import t3-source.srt (source) again with
    replace_existing_captions true so the copy ends correct. Confirm "T3 Podcast" itself is unchanged.

G. Picture: size, crop, position, rotate, overlay
21. Create "T3 Picture" (shape original) with SHORT, PHOTO (3 s) and SHORT again. Report the
    "size and why" line. set_project_settings video_size "1080p": report the new size and why.
22. On the first clip: crop_shape "1:1" (report the crop numbers get_project shows); rotation 90,
    then 0; flip_horizontal true, then false; crop_shape "none". Then set shape 9:16, fit "fill"
    on "all", and position_x -1, then 1, then 0 on the first clip. Report the values after each.
23. add_overlay SHORT at 2 s: layout pip, corner bottom_right, size_percent 30, border true,
    muted true. update_overlay: layout side_by_side; then pip, corner top_left, size_percent 40.
    add_overlay PHOTO (3 s) at 2 s too: it must not overlap the first; report where it went.
    remove_overlay the photo. Report the overlay list.

H. Look, titles, copies
24. set_project_settings fade_in_ms 1000, fade_out_ms 1500. First clip: fade_in_ms 800,
    filter "vintage", warmth 0.3. apply_to_all from the first clip with look true and
    dry_run true: report what it would change; get_project shows nothing changed. Then
    copy_clip_settings from the first clip to ["all"], dry_run first, then for real. Report which
    clips changed and that trims, transitions and fades were not copied.
25. duplicate_clip the second clip: report the clip count and that the copy is right after it.
26. Six titles, 2 s each, one after another from 0 s, one per style, with exactly these texts:
    classic "Hello ClipForge", outline "שלום עולם", boxed "Привет, мир", yellow "משפחה 2026",
    elegant "Большое спасибо", handwritten "Hello / שלום / Привет".
    Give them different font, position and animation_in / animation_out values (use every font
    and every position at least once). Then get_project: each text must come back EXACTLY as
    written (compare letter by letter; no "?" or empty boxes in the text).
    update_title on the second: align right, outline true. Report.
27. add_music MUSIC at 0 s, then fit_music_to_video without loop: the music is longer than this
    short video, so it is cut to end with the video (2 s fade-out). Report its end and the video's
    end. If MUSIC is shorter, use loop true and say so.
28. undo three times, then redo three times. Report after the undos what was taken back (in
    order), and that after the redos the project is as before (clip, title, overlay, music counts).
29. Export "T3 Picture" full quality to ...\test3\t3-picture.mp4, then format mp3 to
    ...\test3\t3-picture.mp3. Report size, length, frame size (must be the 1080p upright size),
    encoder.

I. Robustness
30. add_media with a file that does not exist: a clear error, nothing changes. export_video to
    ...\test3\t3-picture.mp4 again WITHOUT overwrite: must be refused (the file exists).
    relink_media with an old_path that is not in the project: a clear answer, nothing changes.
31. list_projects: report every T3 project with clip count and length. get_status once more:
    no export still running.

Finish with:
- a results table: step, PASS / FAIL / SKIPPED, the key numbers, notes;
- "Surprises": anything unclear, slow, inconsistent, or an answer that was too long or too short
  to work with (say which tool);
- how long each export took and the speed (video minutes per minute of waiting);
- "For the owner to watch and listen", as a list of file + time + what to check, at least:
  t3-podcast.mp4 at two cuts (words not chopped), at 0:20-1:00 (music lower under the voice,
  back up in pauses), at a loop point of the music (no click or gap) and the last 5 seconds
  (music fades out with the video);
  t3-podcast.mp3 / .m4a first minute (same mix as the video);
  t3-picture.mp4 from start to end (fade from black, vintage look on all clips, the six titles:
  Hebrew reads right to left and no boxes, each style and animation, overlay in the top left
  corner from 0:02 with a white frame, upright 1080 x 1920 framing, fade to black at the end).
```

What "good" looks like, for whoever reads the report:

| Area | Expected in 1.9.0 |
|---|---|
| Status | Version line first, then program, projects folder, fonts, ffmpeg / ffprobe, jobs folder. |
| Short answers | Edits answer with counts, length, size and why, ids, warnings: a 137-clip edit is under 6 KB. `detail: "full"` adds the timeline. |
| Paging | `get_project` gives 60 clips per page and names the next `clip_offset`; `from_ms` / `to_ms` show one part. |
| Silences | No threshold needed: it measures the background noise. `dry_run` lists every cut and saves nothing. |
| Export | First answer after about 20 s with a `job_id`; `get_export_status` until finished; `cancel_export` leaves no file. |
| Lock | With the project open in the app, edits are refused with a clear message; reading, dry runs and exporting work. |
| Music | Too-short music is refused without `loop`; with it, the music ends with the video. |
| Subtitles | A "source" .srt fits any re-cut; a timeline .srt of another cut is warned about. |
