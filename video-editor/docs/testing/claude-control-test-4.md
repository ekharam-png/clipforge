# Claude control test 4 (for ClipForge 1.12.0, build 109)

Checks what versions 1.10 and 1.11 added to the Claude tools, and the fixes
that came out of the report of test 3:

- 1.10: a voice recorded separately (`add_voice`, `align_audio`): lined up
  with the video by sound, linked to its clip, cut together with the picture.
- 1.11: speech to text as a background job (`transcribe`,
  `get_transcribe_status`), reading and searching what is said
  (`get_transcript`, `find_in_transcript`), captions from speech
  (`captions_from_transcript`), gentle filler removal (`remove_fillers`,
  `list_auto_cuts`, `restore_cut`) and shorts (`make_short`).
- Fixes: the "open in the app" lock, two projects with the same name, export
  time estimates, shorter answers, wording, right-aligned titles.

Before you start:

- Connect Claude first. In ClipForge 1.12 open Help > Connect to Claude…:
  save the Claude extension file and install it in Claude Desktop, or copy
  the Claude Code line shown there. If Claude was connected to an older
  ClipForge, connect once more: the helper moved to a new place in 1.12.
- Speech to text needs a speech program on the computer (FFmpeg 8 with its
  "whisper" filter, whisper.cpp, faster-whisper or OpenAI whisper) and, for
  the first two, a language pack. The test tells you what it found. It never
  downloads a pack without asking you.
- Put these in the media folder (the test skips what is missing):
  - a Zoom-style set: ONE video of a conversation plus ONE sound file per
    speaker (Zoom names them `audio<Name><digits>.m4a`), ideally 5 to 25
    minutes;
  - a short video under 1 minute;
  - optional: a clip where someone speaks Hebrew or Russian.
- In ClipForge, go to the project list (or close the app). Steps 9, 27 and
  36 need you; until Claude asks, leave ClipForge on the project list.
- It takes a while (transcribing and four exports). Stay nearby.

Paste into a new Claude chat (Claude Code on Windows):

```
Run "ClipForge test 4" with the ClipForge tools (ClipForge 1.12.0, build 109).
Media folder: C:\Users\<you>\Videos\clipforge-test
Exports and files you write go to: <media folder>\clipforge-test-output\test4\
Never delete, move, rename or overwrite anything of mine. Only create new projects whose names start with "T4 ".
If an output file already exists from an earlier run, add "-2" to the new file name instead of reusing it.
For each step report PASS / FAIL / SKIPPED and the numbers you saw (lengths as m:ss, sizes in MB, offsets in ms).
If a step needs a file I do not have, say so, mark it SKIPPED with the reason and go on.
Do not guess: you cannot see or hear the videos, so never judge picture, lip sync or sound; list those for me at the end.
You CAN read what is said once it is transcribed; say so when a judgement comes from the transcript.
Where a step says STOP, ask me and wait for my answer. Never download a language pack without my yes.
Use dry_run where a step says so, and quote exactly what the tool answered when something is refused.

A. Connection
 0. Before anything else: call get_guide (section "start") and say in two lines what it tells
    you to do first. Then run self_test and paste its table (every row PASS, speech may be
    SKIPPED). Report the helper's path from get_status: it should be in a ClipForge "claude"
    folder under the user's app data, not next to clipforge.exe.
 1. get_status. Report: the version line (must say 1.12.0 and build 109), the program path, the
    projects folder, ffmpeg and ffprobe with versions, whether an export or a transcription is
    running. From the speech part report: every speech program found (id, label, whether word
    times are measured or estimated, whether it uses ClipForge's language packs or its own
    models), the language packs on the computer (name, size, languages), my own model file if
    any, the space the packs use, and which packs could be downloaded with their sizes.
    FAIL if the speech part is missing. If NO speech program was found, quote what it says to
    install; sections C to F are then SKIPPED (B and G still run).
 2. Look at the media folder. Pick and name: ZOOM = the video of a conversation that has one
    sound file per speaker next to it; VOICE1, VOICE2 = those sound files (say which speaker
    name you read from each file name); SHORT = a video under 1 minute; FOREIGN = a clip with
    Hebrew or Russian speech (ask me if you cannot tell from the names). Tell me which files
    you chose and their lengths. With only one separate voice file, run B with one speaker.
    With none, B is SKIPPED and C to F use the longest talking video instead of ZOOM.

B. Voice recorded separately (1.10)
 3. Create project "T4 Zoom" (shape 16:9) with ZOOM. Report the short summary (length, size and why).
 4. add_voice VOICE1 (no track_name, no clip_id). Report: offset_ms, confidence, drift_ms, the
    warnings, the name of the track it made (must be the speaker's name from the file name),
    and whether the camera's own sound is now muted. Confidence under 0.5 means NOT lined up:
    report that as FAIL for this file, quote the warning, and do not call it in sync.
 5. add_voice VOICE2 the same way. Report the same numbers. Both offsets should be close to each
    other when the files come from one Zoom recording (say how far apart they are).
 6. list_sound_tracks and get_project (first page): each voice is on its own track that counts
    as speech, has role "voice", a linked_clip and an offset_ms; the clip is muted. Report
    track order, names and the item count per track.
 7. remove_silences with dry_run true and no threshold. The answer must be in the "would" form.
    Report: what it listened to (must be the two voices, not the muted camera), the number of
    cuts, the time it would remove, cuts per minute, the first three cuts. get_project: still
    one clip and one item per voice (nothing saved).
 8. remove_silences for real (min_caption_ms 1200). Report: pieces, time removed, new length,
    cuts per minute, warnings. Then check that picture and both voices were cut TOGETHER:
    the number of items on each voice track equals the number of clips (or say why not), every
    voice item still has the same offset_ms as in steps 4 and 5, and for clips 1, 10 and the
    last one the voice item starts and ends at the clip's own timeline times (list them).
    Compare with step 7: same numbers? The cuts must be listed once in the answer, not twice.
 9. export_video "T4 Zoom", quality small, to ...\test4\t4-zoom-small.mp4 (poll with
    get_export_status, wait_seconds 45, never start it twice). Note the first time estimate for
    step 31. Then STOP and ask me: "Please watch t4-zoom-small.mp4 at <time 1>, <time 2> and
    <time 3> for about 10 seconds each: do the lips match the voice? Type yes or no for each."
    Choose three times just after a cut: one in the first minute, one in the middle, one in the
    last minute. Write my three answers into the report (PASS only if I said yes three times).
10. Nudge and unlink, on a copy: duplicate_project "T4 Zoom" to "T4 Zoom nudge". In the copy:
    align_audio on the first speaker's voice with nudge_ms 40: report offset_ms before and
    after (which direction did it move?), and whether every piece of that recording moved.
    align_audio nudge_ms -40: the offset is back. align_audio without nudge (line up again):
    report offset and confidence (same as step 4, within a few ms?). Then align_audio with
    link false: the item no longer has linked_clip. trim_clip the first clip 2 s shorter at
    its end: report the warning about a voice that is not linked going out of sync (quote it),
    and that the second speaker's voice (still linked) followed the cut. undo twice: linked
    again. Confirm "T4 Zoom" itself is unchanged.

C. Speech to text (1.11)
11. transcribe "T4 Zoom" with language set to the language spoken (ask me if unsure), quality
    "auto", and WITHOUT download_pack. If the answer says a language pack is needed: STOP and
    show me the pack's name, its size and what it is for, plus the smaller choices, and ask
    "Download <pack> (<size>)? yes / no / I will copy a model file myself". Only after my yes
    call transcribe again with download_pack true and the size I chose. If I say no:
    C to F are SKIPPED.
12. It runs as a background job: report the FIRST answer exactly (job_id, percent, which
    recording of how many). Poll get_transcribe_status with wait_seconds 45 until it is
    finished. Do NOT call transcribe again. Report: number of status calls, percent values,
    total minutes, and from the final answer: the speech program used, the pack or model,
    the device (graphics card or processor; say "not reported" if empty), the language it
    found, the word count per recording, and whether word times are "measured" or "estimated".
    Work out the speed: minutes of speech per minute of waiting.
13. transcribe again with the same settings: it must skip what is already done (no new work).
    get_transcribe_status without job_id: the job is listed as finished.
14. get_transcript with defaults. Report: the number of phrases and words it says there are,
    the size of the answer (roughly, in KB), the first three lines exactly, and whether each
    line starts with a time and the SPEAKER'S NAME (the names of the two voice tracks). Then
    page: get_transcript with limit 20, then offset 20 limit 20: no line twice, none missing.
15. get_transcript with from_ms 60000 and to_ms 120000: only what is said in that minute of the
    finished video. Then the same range with time_base "source" and with format "words"
    (first 10 words with their times). Do the timeline times fit the cut video (after
    Remove silences), and the source times the original recording? Report one phrase in both.
16. Per speaker: from the transcript, report for each speaker the number of phrases and the
    first phrase with its time. Does any phrase have no speaker, or the wrong track name?
17. find_in_transcript: pick a word you saw several times and a two-word phrase you saw once.
    Report the number of places, and for the first place the time, clip, speaker and the words
    around it. Then a word that is certainly not said: a clear "not said" answer, no error.

D. Captions from speech
18. captions_from_transcript "T4 Zoom" with dry_run true, from_ms 0, to_ms 120000. The answer is
    in the "would" form. Report: how many captions, the shortest and the longest (seconds and
    text), the longest line in characters, whether any overlap, and the first three captions.
    get_project: the caption count did not change.
19. The same for real. Report the caption count (same as the dry run?), that the answer gives
    counts and at most a dozen ids (not every id), and check with get_project from_ms 0 to_ms
    120000: no caption under 1 s or over 6 s, none overlapping, none after 2:00.
20. Hebrew or Russian (SKIPPED without FOREIGN): create "T4 Foreign" with FOREIGN, transcribe
    with language "he" or "ru" (pack rule as in step 11: the Small pack is weak in Hebrew; ask
    me before any download). Report program, device, minutes, words. get_transcript: quote the
    first three lines exactly as returned (real letters, no "?" or boxes).
    captions_from_transcript dry_run, then real. Export small to ...\test4\t4-foreign.mp4 and
    list it for me to check (Hebrew right to left, the full stop on the left end of the line).

E. Remove filler words
21. duplicate_project "T4 Zoom" to "T4 Fillers" (the transcript comes with it: get_transcript
    with limit 3 must work in the copy without transcribing again).
22. remove_fillers on "T4 Fillers" three times as a dry run: strength "light", then "normal",
    then "strong". For each report as a table row: found / would cut / left because too close /
    left because the picture would jump / other reasons, time saved, cuts per minute, and the
    riskiest cuts it lists. Each answer is in the "would" form and get_project shows nothing
    changed. Light must cut the fewest; Strong the most.
23. Word times: say whether this transcript's word times are measured or estimated, and which
    program made it. If ESTIMATED: call remove_fillers strength "light" with dry_run false and
    WITHOUT allow_estimated_times: it must REFUSE; quote the message; nothing changed. (Also
    report how many fillers were found at all: the FFmpeg filter usually leaves "um" out.)
24. Apply Light: remove_fillers strength "light", dry_run false (with allow_estimated_times true
    only if step 23 refused; this is a test copy). Report cuts made (same as the Light dry
    run?), time saved, new length, how many got a dissolve, warnings. If Light found nothing
    to cut, apply "normal" instead and say so; if that also cuts nothing, 24 to 26 are SKIPPED.
25. list_auto_cuts on "T4 Fillers": report the totals (count, time, per minute), and the first
    three entries (id, kind, word, file and part removed, by whom, jump score, dissolve).
    The silence cuts of step 8 are there too: list_auto_cuts with kind "filler" and sort
    "risk" shows only the fillers, riskiest first.
26. restore_cut one filler cut (dry_run first, then real): the clip count goes down by one, the
    length grows by that cut's length, both voices came back with it, list_auto_cuts has one
    fewer. Then restore_cut cut_id "all" kind "filler": no filler cuts left, the length is as
    before step 24; the silence cuts are still listed. Then undo: the fillers are cut again
    (one step). undo again: back to one restored. Report counts and lengths after each.

F. A short
27. Read the transcript of "T4 Zoom" (page through all of it) and propose THREE moments that
    would work as a short of 20 to 60 seconds: for each the start and end time (m:ss), the
    speaker, the first and last words, and a one-line reason. Each must start and end at a
    sentence. Then STOP and ask me: "Which one shall I make: 1, 2 or 3?" Wait.
28. make_short for the one I chose: shape 9:16, captions true, name "T4 Short". Report: the new
    project's name and id, length, size and why (must be the 1080p upright size), caption
    count, both voices still there and linked, and that "T4 Zoom" is unchanged (length, clip
    and caption counts as before).
29. export_video "T4 Short", full quality, to ...\test4\t4-short.mp4 as a background job; poll
    until finished. Report size, length, frame size, encoder, minutes.

G. Fix checks from the test 3 report
30. Same name twice: create_project "T4 Lock A" (16:9) with SHORT. create_project "T4 Lock A"
    again: the answer must say the name was taken and that it is now "T4 Lock A (2)". Then
    create_project "T4 Lock B" with SHORT. duplicate_project "T4 Lock B" to "T4 Lock B": report
    the name it got. get_project by the name "T4 Lock A": does it find the right one, and
    what does a name that fits two projects answer (ids, dates, lengths)? Use ids from here on.
31. Export estimate against the real time, three kinds, all from "T4 Zoom": full quality to
    ...\test4\t4-zoom-full.mp4; small (already done in step 9); sound only, format m4a, to
    ...\test4\t4-zoom.m4a. For each report: the FIRST estimate (the single figure, the range
    "between ... and ...", and what it says it is based on), the real time, and real / estimate
    as a factor. Is the real time inside the range? The estimate of the full export should
    already use the speed of this computer measured in step 9: does it say so?
32. Answer sizes. export_srt "T4 Zoom" with time_base "source" to ...\test4\t4-zoom.srt (the
    captions of step 19). duplicate_project "T4 Zoom" to "T4 Subtitles", remove_title with
    all_captions true, then import_srt that file with time_base "source". The answer must give
    COUNTS and at most about 12 ids, not one id per line; report the caption count and the
    size of the answer. If the file has under 40 captions, first make more with
    captions_from_transcript on the whole video in the copy, export those, and import them.
33. Wording. In "T4 Lock B": set_clip_properties volume 1.0 on the first clip (it already is
    1.0): the answer must say plainly that nothing was changed. Quote it. Then
    set_clip_properties "all" speed 1.25 with dry_run true: quote the first sentence (it must
    say "Would ..."), and get_project shows speed 1.
34. Right-aligned title. In "T4 Lock B": add_title "Right edge test 12345" at 1 s for 3 s, align
    right; add_title "שלום עולם 2026." at 4 s for 3 s, align right. get_project: report x and
    align of both. export_video small to ...\test4\t4-title.mp4. Then, with the ffmpeg that
    get_status named, save one picture at 2 s and one at 5 s as ...\test4\t4-title-2s.png and
    ...\test4\t4-title-5s.png (if you cannot run programs, say so). STOP and ask me: "Please
    open the two pictures: is the whole text inside the picture, near the right edge, with
    nothing cut off? Type yes or no for each." Write my answers into the report.
35. Projects still closed in the app: add_caption "Lock test 0" at 1 s in "T4 Lock A" and in
    "T4 Lock B": both accepted.
36. The lock (needs me). STOP and ask me: "In the ClipForge app: open the project T4 Lock A,
    go back to the project list, then open T4 Lock B and leave it open. Then type: B is open".
    Wait. Then:
    a. get_project of both: B must show that it is open in the app; A must NOT.
    b. add_caption "Lock test 1" at 2 s in "T4 Lock B": must be REFUSED with a message that the
       project is open in the ClipForge app. Quote it. The caption count did not change.
    c. add_caption "Lock test 1" at 2 s in "T4 Lock A": must be ACCEPTED (in 1.9 the mark stayed
       on the first project opened). Report the caption count.
    d. set_clip_properties "all" speed 1.1 with dry_run true in "T4 Lock B": allowed, saves nothing.
    e. Ask me: "Please go back to ClipForge's project list, then type: closed". Wait.
    f. add_caption "Lock test 2" at 3 s in "T4 Lock A" and in "T4 Lock B": both accepted now.
       get_project of both: neither is open in the app. Report the caption counts.
37. list_projects: report every T4 project with clip count and length; no two have the same
    name. get_status once more: no export and no transcription still running.

Finish with:
- a results table: step, PASS / FAIL / SKIPPED, the key numbers, notes;
- a speech table: recording, program, pack or model, device, language, words, minutes of
  speech, minutes it took, speed, word times measured or estimated;
- the filler table of step 22 (Light / Normal / Strong) and what was really cut in step 24;
- an export table: file, kind, first estimate and range, real time, factor;
- "Surprises": anything unclear, slow, inconsistent, or an answer that was too long or too
  short to work with (say which tool and roughly how many KB);
- "For the owner to watch and listen", as a list of file + time + what to check, at least:
  t4-zoom-full.mp4 at three cuts (lips match the voice, words not chopped, both speakers
  heard, no camera sound doubled underneath) and the first 2 minutes (captions: right words,
  right moment, readable, 1-2 lines);
  t4-short.mp4 from start to end (starts and ends at a sentence, upright framing shows the
  speaker, captions fit the width);
  the "T4 Fillers" project in the app at the times of the cuts from step 24 (no jump in the
  picture, no clipped word; I give the times);
  t4-foreign.mp4 (Hebrew right to left, punctuation on the correct side; Russian letters);
  t4-title-2s.png and t4-title-5s.png (text fully inside, at the right);
- "Most important problems": at most five lines, the worst first, each with the step number.
```

What "good" looks like, for whoever reads the report:

| Area | Expected in 1.12.0 |
|---|---|
| Status | Version line with 1.12.0 and build 109; a speech part that lists the programs found, the packs on the computer and what could be downloaded. |
| Separate voice | `add_voice` answers offset, confidence (0.5 or more = lined up) and drift; the track is named after the speaker; the camera is muted. Files of one Zoom recording have nearly the same offset and no drift. |
| Cuts keep sync | `remove_silences` listens to the linked voices and cuts picture and every voice together; the offsets do not change. A voice that is not linked gets a warning after a cut. |
| Transcribe | A background job with a `job_id`; `get_transcribe_status` until finished; asking again is skipped. No pack is downloaded without `download_pack`, and Claude asks the owner first with name and size. |
| Word times | whisper.cpp, faster-whisper and OpenAI whisper: measured. The FFmpeg filter: estimated; `remove_fillers` then refuses to cut without `allow_estimated_times`. |
| Transcript | One line per phrase with times and the speaker (the voice track's name); paging and time ranges; timeline times follow the cuts. |
| Captions | 1-2 lines, 1 to 6 seconds, never overlapping; the dry run and the real run give the same count. |
| Fillers | Dry run by default. Light cuts least (at most about 4 a minute), Strong most; every cut is in `list_auto_cuts` and can be put back, one or all. |
| Short | A new project, upright 1080 x 1920, with captions; the original is untouched. |
| Lock | Only the project that is really open in the app is refused; the one opened before it is free again. |
| Names | A second project with a taken name gets "(2)" and the answer says so. |
| Estimates | A range, based on the speed of the last export of that kind on this computer; sound only is much faster than video. |
