# Claude control test 6 (for ClipForge 1.17.0, build 136)

MEDIA FOLDER: <owner fills in>

A full pass over the Claude tools (74 in all) before any 1.18 work, the new
and risky things first:

- `self_test` and `get_guide` before anything else.
- The long file through Claude: a 20 to 30 minute video, alone and with its
  two voice files (the material that made the app stop answering on the
  owner's Windows PC), with the time every call took.
- 1.17: a part of the timeline (`edit_part`: cut out, silence, lower,
  delete, speed, clean, duplicate, with `rows`), `list_quiet_parts`,
  `remove_quiet_part`, `set_only_when_speaking`; `list_markers` with
  `overlapping`; `restore_cut` bringing back the captions of a part that
  was cut out.
- Background jobs: `export_video`, `export_kit`, `transcribe`, their status
  and cancel tools.
- Then every other tool group once: projects, clips, titles and captions,
  sound and tracks, voices, overlay, markers and shorts, publishing notes,
  speech, the "open in the app" lock.

Before you start:

- Connect Claude first. In ClipForge 1.17 open **Help > Connect to
  Claude…** and press **Connect** (or **Replace with this version**) for
  Claude Desktop or Claude Code, or check that the row already says
  "Connected (ClipForge 1.17.0)". Then close Claude and open it again once.
- Put these in the media folder (the test skips what is missing):
  - LONGFILE: the talking video of 20 to 30 minutes, and LV1 + LV2: the
    two voice files recorded for it (one per speaker);
  - TALK: a talking video of 1 to 3 minutes;
  - SHORT: a video under 45 seconds;
  - PHOTO: a photo; MUSIC: a music file longer than TALK;
  - optional: a subtitle file (.srt) for TALK, with the same file name.
- Speech to text is only used when a speech program is on the computer
  (the test tells you what it found and never downloads a language pack
  without asking you). Without one, section J is skipped and the rest runs.
- In ClipForge, go to the project list (or close the app). Steps 14, 50
  and 62 need you (and step 51, if a language pack is needed); until
  Claude asks, leave ClipForge on the project list.
- It takes a while (the long file, three exports, one kit). Stay nearby.
- At the end Claude writes a results file,
  `clipforge-test-output\test6\claude-control-test-6-results.md`, in the
  media folder. Send that file back.

Paste into a new Claude chat (Claude Code or Claude Desktop on Windows):

```
Run "ClipForge test 6" with the ClipForge tools (ClipForge 1.17.0, build 136).
MEDIA FOLDER: <owner fills in>
Exports and files you write go to: <media folder>\clipforge-test-output\test6\
Never delete, move, rename or overwrite anything of mine. Only create new projects whose names start with "T6 ".
If an output file or folder already exists from an earlier run, add "-2" to the new name instead of reusing it.
For each step report PASS / FAIL / SKIPPED and the numbers you saw (lengths as m:ss, sizes in MB, frame sizes as
width x height, counts) and, where a step says "time it", how many seconds the tool call took.
If a step needs a file or a program I do not have, say so, mark it SKIPPED with the reason and go on.
Do not guess: you cannot see or hear the videos, so never judge picture, lip sync or sound; list those for me at the end.
You CAN read captions and transcripts; say so when a judgement comes from the text.
Where a step says STOP, ask me and wait for my answer. Never download a language pack without my yes.
Before EVERY change that touches many things at once (remove_silences, replace_in_captions, make_chapters,
captions_from_transcript, remove_fillers, restore_cut, edit_part, set_clip_properties "all", apply_to_all) run it with
dry_run true first, report what it would do, and only then run it for real. Quote exactly what a tool answered when
something is refused. If a tool does not answer within 3 minutes, or the connection drops, write down the step and the
time, call get_status, and go on with the next step: that is a finding, not a reason to stop.
Keep a list of every tool you called; it is checked in step 64.

A. Connection
 0. Before anything else: call get_guide (section "start") and say in two lines what it tells
    you to do first. Then run self_test and paste its table (every row PASS; speech may be
    SKIPPED). Time it.
 1. get_status. Report: the version line (must say 1.17.0 and build 136); the helper's path (it
    must be in a ClipForge "claude" folder under my user's app data, NOT next to clipforge.exe)
    and whether it says this is the helper the app installed; the projects folder; ffmpeg and
    ffprobe with versions and paths; whether an export or a transcription is running; every
    speech program found and the language packs on the computer (or the exact sentence about
    what to install when none was found). FAIL if the version or the build is different. Count
    the ClipForge tools you have been given: 74 expected. Say whether edit_part,
    list_quiet_parts, remove_quiet_part and set_only_when_speaking are among them.
 2. get_guide sections "tools", "recipes" and "troubleshooting", one call each. For each: its
    size in KB and whether it mentions edit_part, "Only when speaking" and the "overlapping"
    note of list_markers. Then get_guide section "nonsense": quote the answer (it must name
    the sections that exist, not fail without a word).
 3. Look at the media folder. Pick and name: LONGFILE = the talking video of 20 to 30 minutes
    (if there is none, the longest video, and say its length), LV1 and LV2 = the sound files
    recorded per speaker for it (say which speaker name you read from each file name), TALK =
    a talking video of 1 to 3 minutes, SHORT = a video under 45 seconds, PHOTO = a photo,
    MUSIC = a music file, SRT = a subtitle file for TALK if there is one. Tell me which files
    you chose and their lengths.

B. The long file (do this before everything else)
 4. create_project "T6 Long" (16:9) with LONGFILE. Time it. Report the short summary (length,
    size and why, tracks). FAIL if it took longer than 60 s or did not answer.
 5. get_project "T6 Long" with defaults (time it; the size of the answer in KB), then with a
    time range from_ms 600000 to_ms 660000. list_projects: "T6 Long" is there with its length.
 6. get_speech_map "T6 Long" (view "turns"). Time the first call and a second one (the second
    must answer at once). Report the speakers, their shares and the number of turns.
 7. add_voice LV1, then LV2 (SKIPPED without them; the rest of B then runs with the camera
    sound). Time each. Report offset_ms, confidence, drift_ms, the track each made, and that
    the camera's own sound is muted. Confidence under 0.5 is NOT lined up: say so.
 8. list_sound_tracks and get_project (first page): each voice on its own speech track with
    role "voice", linked_clip and offset_ms. get_speech_map again: two speakers now; time it;
    the shares add up to about 100 %.
 9. remove_silences on "T6 Long" with dry_run true. Time it. Report what it listened to (the
    voices, not the muted camera), the number of cuts, the time it would remove, cuts per
    minute. Do NOT run it for real here. get_project: still one clip.
10. edit_part on "T6 Long": action "silence", from_ms 300000, to_ms 303000, rows = [the track
    of the first speaker]. dry_run true first, then for real. Time both. Report the rows it
    names as changed. list_quiet_parts: one quiet part, on that voice, with timeline and source
    times. Then undo; list_quiet_parts: none.
11. duplicate_project "T6 Long" to "T6 Long cut". Time it. In the copy: split_at 900000 and
    remove_clip the second piece (the copy is 15 minutes now). Report the length and that both
    voices were cut with the picture (one item per voice, same offset_ms).
12. export_video "T6 Long cut", quality small, to ...\test6\t6-long-cut.mp4. It is a background
    job: report the FIRST answer exactly (job id, estimate) and the clock time. Poll
    get_export_status with wait_seconds 45 until it is finished; never start it twice. While
    it runs, between two polls, call get_status and list_projects once each and time them
    (they must answer in a second or two while the export runs). Report the number of status
    calls, the percent values, the total minutes, the file size, and with ffprobe the length,
    the frame size and the codecs of the file.
13. A second job and cancel_export: export_video "T6 Long" (the full 20 to 30 minutes), quality
    small, to ...\test6\t6-long-cancel.mp4. After the second status call, cancel_export it.
    Report what the cancel answered, what get_export_status says afterwards, and that no
    t6-long-cancel.mp4 and no file ending in ".part" is left in the folder.
14. STOP and ask me: "Please open ClipForge, open the project T6 Long, wait one minute, try
    zoom, scroll and Play, then go back to the project list and type what you saw (did it
    answer; did the top bar say Saved; was 'Drawing sound…' or 'Sound waves were paused…'
    shown). If it stalled: Help > Copy version info, and paste it here." Wait. Write my answer
    (and the pasted text, if any) into the report word for word.

C. A part of the timeline: edit_part (1.17)
15. create_project "T6 Part" (16:9) with TALK, then add_media SHORT and PHOTO after it, and
    add_music MUSIC at 0 ms. add_title "T6 title" at 3000 ms for 4 s. add_caption six times,
    one every 5 s from 2 s on, 3 s long each: "Sam Taylor: Part line N." for N = 1, 3, 5 and
    "Alex K: Part line N." for N = 2, 4, 6. Report the length, the clip count (3), the tracks
    and the caption count (6).
16. edit_part "silence", from_ms 6000, to_ms 8000, rows ["video"]: dry run, then real. Report
    the answer (rows changed; rows it could not change and why, if any), that the length and
    the clip count did not change by more than the splits it names, and list_quiet_parts
    (item_id, row, from_ms..to_ms on the timeline, source_from_ms..source_to_ms, "silent").
17. edit_part "lower", from_ms 10000, to_ms 14000, level_db -12, rows [the music track]: dry
    run, then real. list_quiet_parts: two items now; the music one says -12 dB.
18. The quiet part follows the cut: trim_clip the first clip 1 s shorter at its START (in_ms
    1000). list_quiet_parts: the silenced part is 1 s earlier on the timeline and has the SAME
    source times. undo: back.
19. remove_quiet_part for the video clip's part, dry_run true, then real, with the
    source_from_ms / source_to_ms from list_quiet_parts. list_quiet_parts: only the music
    one is left. undo: two again. Then remove_quiet_part on the music item WITHOUT source
    times: every quiet part of that item is gone. undo.
20. edit_part "cut_out" WITH rows ["video"], from_ms 20000, to_ms 23000: it must be REFUSED
    with the reason (cut out needs every row). Quote it. Nothing changed (length as before).
21. edit_part "delete", from_ms 30000, to_ms 33000, rows [the music track]: dry run, then real.
    Report: the music has a gap there and the music after it did not move (give its start
    before and after); the video length is unchanged. Then "delete" with rows ["video"]:
    refused with the reason (the main track has no gaps). Quote it.
22. edit_part "speed", speed 0.5, on the first 4 s of SHORT's clip (take its timeline times from
    get_project): dry run, then real. Report: the clips it made, the new length of the part
    (8 s), that the music kept its place, and what it says about the part's own sound. Then
    the same with speed 0.25 as a DRY RUN only: mute_own_sound must default to true.
23. edit_part "clean", 5 s of TALK where someone speaks, rows ["video"]: dry run, then real.
    Report the pieces and which one has Clean up sound on (get_project).
24. edit_part "duplicate", from_ms 2000, to_ms 6000: dry run, then real. The video is 4 s longer
    and the copy lies right after the part; captions inside it: copied or not? Report what
    the tool says. undo, redo, undo: report the length after each (one undo step each).
25. Wrong input, each must give a clear message and change nothing: edit_part with to_ms before
    from_ms; with from_ms past the end of the video; action "lower" with level_db 5; rows
    ["no such row"]. Quote the four answers.

D. restore_cut brings the captions back (1.17)
26. duplicate_project "T6 Part" to "T6 Put back". get_captions on the copy with ids true: note
    every caption's start, end and text.
27. edit_part "cut_out" without rows, covering captions 2 and 3 completely (take the times from
    step 26, half a second of room on each side): dry run (it names what goes: time, clips,
    captions), then real. Report: the length is shorter by the part; get_captions shows 4
    captions (2 and 3 are gone) and the later ones moved earlier by the length of the part.
28. list_auto_cuts: the cut is listed with kind "part", its id, where it was and how long.
    restore_cut that cut_id with dry_run true (what would come back, captions named?), then
    for real. Report: the old length; the clip is one piece again there (or say what it is);
    get_captions shows 6 captions, and captions 2 and 3 have their OLD start, end and text
    (compare with step 26, to the millisecond). FAIL if they did not come back.
29. undo (the cut is out again, 4 captions), redo (6 again). Then cut the same part out once
    more and restore_cut "all": the same result. Also try restore_cut "all" with kind "part"
    and quote the answer (the tool's description lists only filler, silence and text for
    kind: report whether "part" is accepted).

E. Only when speaking (1.17)
30. On "T6 Part" (no speech track): set_only_when_speaking track_id "all": quote the answer (a
    clear reason, no change).
31. On "T6 Long cut" (two voices; SKIPPED without LV1 and LV2): set_only_when_speaking for the
    first speaker's track with dry_run true, then real with defaults. Report what it says it
    will do (room_db -18), and list_quiet_parts: it names the tracks with "Only when speaking"
    on. Then track_id "all", room_db -100; then on false for "all"; then on true again with
    room_db -18. list_sound_tracks after each: report what it shows for the tracks.
32. Exports apply it: make_short from "T6 Long cut", from_ms 120000 to_ms 180000, name "T6 Gate
    short", shape "16:9" if make_short takes it (else its default), snap_to_speech true. Report
    whether the short has both voices and whether "Only when speaking" is on in it
    (list_quiet_parts / list_sound_tracks; switch it on there if it is not). export_video the
    short, quality small, to ...\test6\t6-gate-on.mp4; then set_only_when_speaking "all" on
    false in the short and export to ...\test6\t6-gate-off.mp4. Poll both to the end. With
    ffprobe: both have the same length. If you can run ffmpeg: measure the mean volume of each
    file's sound (volumedetect) and report both numbers (the gated one should be lower); if
    you cannot run programs, say so. The listening is for me (final list).

F. Markers, "overlapping", shorts (1.14, changed in 1.17)
33. create_project "T6 Markers" (16:9) with SHORT only. add_marker at one third of its length
    (label "T6 a") and at two thirds (label "T6 b"). list_markers. Report for each: time,
    label, and the part a short would take (shortFromMs - shortToMs and its length). In a
    video under a minute each part must be about HALF the video (at least 8 s), the two parts
    must be DIFFERENT, and neither may be the whole video. No "overlapping" in the answer.
34. remove_marker "T6 b". add_marker 2 s after "T6 a" (label "T6 c"). list_markers: the answer
    must now carry "overlapping" (the two marker ids and ONE range, oneShortFromMs -
    oneShortToMs) and a note telling you to ask the user. Quote the note. add_marker at the
    time of "T6 a" again: what does it answer?
35. Do what the note says: STOP is not needed here, I answer now: "one short covering both".
    make_short with the one range, name "T6 Markers short", caption_style "short",
    snap_to_speech true. Report the times asked and used, the length, the size (1080 x 1920),
    the warnings, and say in one line how many shorts you made (1). list_projects: exactly
    one new project.
36. On "T6 Part": add_marker at 0:40 and at 1:20 (or one quarter and three quarters). list_markers:
    in a video over a minute each part is about 20 s before to 25 s after the marker, moved
    to pauses; no "overlapping". trim_clip the first clip 5 s shorter at its START:
    list_markers shows both markers 5 s earlier. undo.
37. suggest_shorts on "T6 Part" with defaults: where the words came from, how many candidates,
    the first two exactly as returned. (Without transcript the captions are the source; if it
    says there is nothing to go by, quote it.) make_short from the first candidate (or from
    5 s to 35 s), name "T6 Short 1", caption_style "short", title "T6 watch this",
    snap_to_speech true: report id, times asked and used, length, size, caption count, title
    item, warnings, and that "T6 Part" is unchanged.

G. Clips and projects (every remaining clip tool once)
38. On a copy: duplicate_project "T6 Part" to "T6 Clips"; rename_project it to "T6 Clips 2" and
    then to the name "T6 Part" (taken: what does it answer or what name does it get?), then
    back to "T6 Clips". set_project_settings: shape 9:16, then video size 1080p; report the
    size and why after each; set the shape back to 16:9.
39. split_at the middle of the first clip; move_clip the photo to the first place and back;
    duplicate_clip the SHORT clip; remove_clip the copy; freeze_frame at 3 s. Report the clip
    count and the length after each, and undo the freeze frame.
40. set_clip_properties on the first clip: speed 1.5, volume 0.5, fit "blur", filter "vintage",
    fade_out 1 s (use the names the guide's "tools" section gives; report the old -> new
    values the answer shows). Then set_clip_properties "all" speed 1.0 with dry_run true:
    the "would" form with a list. copy_clip_settings from the first clip to the last with
    dry_run true, then real. apply_to_all for the filter with dry_run true only.
41. undo five times and redo five times: the clip count and the length after the last redo
    are those before the first undo. Report what undo answers when there is nothing left to
    undo (call it until it says so on a fresh duplicate "T6 Undo" with two edits).
42. relink_media: quote what it answers for a clip whose file is NOT missing (it must not
    break the clip). Do not move or rename any file of mine to test more.

H. Titles, captions, subtitles
43. On "T6 Clips": add_title "Привет / שלום" at 1 s with a font and position of your choice;
    update_title: text "T6 changed", position lower third, appear "pop"; get_project shows it.
    remove_title it. Report the title ids and what each answer says.
44. export_srt "T6 Part" to ...\test6\t6-part.srt (timeline times), and with time_base "source"
    to ...\test6\t6-part-source.srt. Report the caption count in each and the first cue of
    each. create_project "T6 Srt" with TALK and import_srt t6-part.srt (and SRT, if I have
    one, into another project "T6 Srt 2"): report the count and any warning.
45. get_captions "T6 Srt": defaults, then format "paragraphs", then limit 2 offset 2, then ids
    true from_ms 0 to_ms 10000. replace_in_captions find "Part" replace "Test" whole_word
    true: dry run (the default) gives the "would" form with places and captions; then
    dry_run false; get_captions shows "Test line"; undo takes it all back in one step.

I. Sound, tracks, voices, overlay
46. On "T6 Clips": list_sound_tracks. add_sound_track "T6 effects"; update_sound_track: volume
    0.8, mute true, then mute false, and "lower under speech" on for the music track;
    move_sound_track it up and down; add_music MUSIC a second time at 0 ms (where does it
    land?); move_audio_to_track that second music to "T6 effects"; update_audio: volume 0.4,
    fade in and out 2 s; fit_music_to_video on the first music (report the new end and the
    fade); remove_audio the second music; remove_sound_track "T6 effects". Report the track
    list after each change, briefly.
47. separate_sound on the first clip (dry run for "all" first, then only that clip): the clip is
    muted and its sound is an item on a voice track with linked_clip. trim_clip that clip 1 s
    shorter at its end: the sound item followed. reattach_sound: the item is gone and the
    clip is no longer muted.
48. align_audio on "T6 Long cut" (SKIPPED without voices): nudge_ms 40 on the first speaker's
    voice (offset before and after), nudge_ms -40 (back), then line up again without nudge
    (offset and confidence as in step 7, within a few ms?). Then link false, get_project
    shows no linked_clip, undo.
49. add_overlay SHORT on "T6 Clips" at 5 s (picture-in-picture); update_overlay: another corner,
    size 0.5, then layout side by side; edit_part "silence" over the overlay's time with rows
    ["overlay"] (dry run, then real) and list_quiet_parts shows it on the overlay;
    remove_overlay. Report each answer in one line.
50. export_video "T6 Part", quality small, to ...\test6\t6-part.mp4; poll to the end. Then STOP
    and ask me: "Please play t6-part.mp4 at <the silenced part>, <the part with lower music>
    and <the slow part> (I give the times): is the voice silent / the music quieter / the
    picture slow there, without a click? Type yes or no for each." Write my three answers into
    the report (PASS only for three times yes).

J. Speech to text (SKIPPED with the reason when get_status found no speech program)
51. transcribe "T6 Part" with the language spoken (ask me if unsure), quality "auto", WITHOUT
    download_pack. If it answers that a language pack is needed: STOP, show me the pack's
    name and size and the smaller choices, and ask "Download <pack> (<size>)? yes / no". Only
    after my yes call it again with download_pack true. Report the FIRST answer exactly; poll
    get_transcribe_status (wait_seconds 45) to the end; never start it twice. Report the
    program, the pack or model (my own model file, if get_status named one), the device, the
    language, the word count, the minutes.
52. A second transcription and cancel_transcribe: transcribe "T6 Long cut" (15 minutes), and
    after the second status call cancel_transcribe. Report what it answered and what
    get_transcribe_status says afterwards; get_status: no transcription running.
53. get_transcript "T6 Part": defaults (phrases, words, KB, first three lines), then limit 20
    and offset 20 limit 20 (no line twice), then format "words" from_ms 0 to_ms 10000.
    find_in_transcript: a word said several times; a word that is certainly not said.
54. captions_from_transcript on a copy ("T6 Speech", duplicate of "T6 Part"): dry run with
    replace_existing true (count, first three), then real. get_captions: none under 1 s or
    over 6 s, none overlapping.
55. remove_fillers on "T6 Speech": dry run with strength "light" and "strong" (how many, how
    much time), then "light" for real. list_auto_cuts kind "filler": the cuts. restore_cut the
    first one (dry run, real): the length grows by that cut. restore_cut "all" kind "filler".
    If no fillers were found, quote the answer and run remove_silences for real instead, then
    list_auto_cuts kind "silence" and restore_cut "all" kind "silence": the old length is back.

K. Publishing notes, chapters, the kit
56. get_publishing_notes "T6 Part" (empty). set_publishing_notes: title "T6 test video", a
    description of two sentences, 5 hashtags, short_title "T6 watch this". get_publishing_notes
    gives the same back. make_chapters dry_run true (the list and what it was made from, or
    the reason why not), then real. set_publishing_notes chapters "0:05 Start\n0:09 Too soon":
    quote the warning; undo.
57. export_kit: project "T6 Part" with destinations ["youtube", "podcast", "whatsapp"], projects
    [{"T6 Short 1", ["shorts"]}], output_dir ...\test6\kit. ONE background job: the FIRST
    answer exactly, then poll get_export_status (wait_seconds 45) to the end. Report the
    files from the final answer with sizes and warnings (pass a warning about 60 seconds or
    16 MB on with "check the site").
58. Check the kit folder with ffprobe: "T6 Part - YouTube.mp4" 1920 x 1080; "T6 Short 1 - Short
    9x16.mp4" 1080 x 1920; the WhatsApp file 1280 x 720; "T6 Part - audio.mp3" sound only;
    "T6 Part - text.txt" with title, description, hashtags, chapters, the short title and a
    part per file. No ".part" file is left; list_projects has no shape copy.
59. get_export_status without job_id: every job of this test is listed with its state
    (finished or cancelled). get_status: nothing is running.

L. The lock, and the end
60. create_project "T6 Lock" (16:9) with SHORT. add_caption "Lock test 0" at 1 s: accepted.
61. Reading stays possible on a project of mine: list_projects, and get_project on the FIRST
    project that does not start with "T6 " (first page only). Change nothing in it.
62. STOP and ask me: "In the ClipForge app, open the project T6 Lock and leave it open. Then
    type: open". Wait. Then:
    a. get_project "T6 Lock": it must show that it is open in the app.
    b. add_caption "Lock test 1" at 2 s: REFUSED with a message that the project is open in
       the ClipForge app. Quote it. The caption count did not change.
    c. edit_part "silence" from_ms 0 to_ms 1000: refused the same way. With dry_run true:
       allowed, saves nothing.
    d. set_only_when_speaking and set_publishing_notes: refused too? Quote the answers.
    e. Ask me: "Please go back to ClipForge's project list, then type: closed". Wait.
    f. add_caption "Lock test 2" at 3 s: accepted now. get_project: not open, 2 captions.
63. list_projects: every T6 project with clip count and length; no two have the same name.
    get_status: no export and no transcription running.
64. The tool check: list the 74 tool names (from the tools you were given) and mark each as
    called / not called in this test. Every tool should be "called"; for each that is not,
    say in which step it was skipped and why.

Finish with:
- a results table: step, PASS / FAIL / SKIPPED, the key numbers, notes;
- a timing table for the long file (steps 4 to 13): tool, seconds, size of the answer in KB;
  the slowest call of the whole test; every call that did not answer within 3 minutes;
- an export table: file or kit, first estimate, real time, factor, size in MB;
- a parts table (section C): action, rows asked, rows changed, rows refused and why;
- the tool check of step 64;
- "Surprises": anything unclear, slow, inconsistent, or an answer that was too long or too
  short to work with (say which tool and roughly how many KB), and anything the guide told
  you that did not match what a tool did;
- "For the owner to watch and listen", as a list of file + time + what to check, at least:
  t6-long-cut.mp4 at the start, the middle and the last minute (picture and both voices in
  sync);
  t6-part.mp4 at the silenced part, the part with lower music, the slow part and the cleaned
  part (I give the times);
  t6-gate-on.mp4 against t6-gate-off.mp4, the same 30 seconds of each with headphones (with
  "on": the other speaker's voice much quieter under each speaker, no word cut off, no dead
  silence between the turns);
  kit\T6 Short 1 - Short 9x16.mp4 from start to end (title at the top, big outlined
  captions, the person in the frame);
  the project "T6 Markers short" in the app (it covers both markers);
  the project "T6 Put back" in the app (captions 2 and 3 are on their words again);
- "Most important problems": at most five lines, the worst first, each with the step number.
Then write this whole report, unshortened, as a file:
<media folder>\clipforge-test-output\test6\claude-control-test-6-results.md
(first line: "ClipForge test 6 results", the version line from get_status, the date and time). If you cannot write
files, say so and print the report in one block so that I can save it under that name. Tell me the full path: I send
that file back.
```

What "good" looks like, for whoever reads the report:

| Area | Expected in 1.17.0 |
|---|---|
| Status | Version line with 1.17.0 and build 136; the helper runs from the ClipForge "claude" folder under the user's app data and says it is the one the app installed; 74 tools. |
| Long file | A 20 to 30 minute video is added in seconds; voices line up with a confidence of 0.5 or more; `get_project`, `get_speech_map` and a `remove_silences` dry run answer without a timeout; an export of 15 minutes runs as a job to the end while other tools still answer; `cancel_export` leaves no file behind. |
| Parts | `edit_part` does one thing to one stretch in one undo step and names the rows it changed and the rows it could not change, with the reason. `cut_out` with `rows` is refused; `delete` on the video row is refused. Dry runs save nothing. |
| Quiet parts | `list_quiet_parts` gives timeline and source times; a quiet part keeps its source times through a trim; `remove_quiet_part` gives the sound back for one range or for the whole item. |
| Put back | `edit_part` "cut_out" is listed by `list_auto_cuts` as kind "part"; `restore_cut` brings back the footage AND the captions that were on it, at their old times, in one undo step. |
| Only when speaking | Off unless set; per speech track or "all"; `room_db` -18 by default, -100 for silence; shown by `list_quiet_parts`; applied by exports that Claude starts. Refused with a reason when there is no speech track. |
| Markers | In a video under a minute a marker's short is about half the video (at least 8 s), never the whole video. Markers close together are reported under `overlapping` with one range and a note to ask the user and to say how many shorts were made. |
| Jobs | `export_video`, `export_kit` and `transcribe` answer at once with a job; the status tools follow them; cancelling works; nothing is started twice; no ".part" file is left. |
| Captions | `get_captions` pages without gaps; `replace_in_captions` is a dry run unless `dry_run` is false; one `undo` takes it all back. |
| Lock | Edits (also `edit_part`) are refused only while the project is open in the app; a dry run is still allowed; after going back to the project list they are accepted. |
| Tool check | Every one of the 74 tools was called at least once, or the report says why not. |
| Results file | `claude-control-test-6-results.md` in `clipforge-test-output\test6\` holds the whole report. |
