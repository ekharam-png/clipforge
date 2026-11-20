# Claude control test 5 (for ClipForge 1.15.0, build 130)

Checks what versions 1.13 and 1.14 added to the Claude tools (70 tools in
all), and one compact run from a long video to a publishing kit:

- 1.13: reading and fixing captions in bulk (`get_captions`,
  `replace_in_captions`), and who speaks when from the sound alone
  (`get_speech_map`), with a cut made at speaker turns.
- 1.14: good-moment markers (`add_marker`, `list_markers`,
  `remove_marker`), candidates for shorts (`suggest_shorts`) and shorts in
  the Short caption look (`make_short` with `caption_style`, `title`,
  `snap_to_speech`), publishing notes and chapters (`get_publishing_notes`,
  `set_publishing_notes`, `make_chapters`), and the kit export as one
  background job (`export_kit`, followed with `get_export_status`).
- The recipe "From a long video to a publishing kit", once, end to end, on
  a duplicate project.
- The "open in the app" lock, once more.

Before you start:

- Connect Claude first. In ClipForge 1.15 open **Help > Connect to
  Claude…** and press **Connect** for Claude Desktop or Claude Code (or
  check that the row already says "Connected (ClipForge 1.15.0)"). Then
  close Claude and open it again once.
- Put these in the media folder (the test skips what is missing):
  - LONG: a talking video of 3 to 10 minutes (a conversation is best; with
    a Zoom recording also the sound file of each speaker). A longer video
    works too: the test then uses only its first 6 minutes;
  - SHORT: a video under 1 minute;
  - optional: a subtitle file (.srt) for LONG, with the same file name.
- Words are needed for the shorts and the notes. They come from the
  subtitle file, or from speech to text when a speech program is on the
  computer (the test tells you what it found and never downloads a
  language pack without asking you). Without either, the parts that need
  words are skipped and the rest still runs.
- In ClipForge, go to the project list (or close the app). Steps 21, 24, 33
  and 38 need you (and step 4, if a language pack is needed); until Claude asks, leave ClipForge on the project list.
- It takes a while (one kit export of the long video, one more of the
  recipe). Stay nearby.

Paste into a new Claude chat (Claude Code or Claude Desktop on Windows):

```
Run "ClipForge test 5" with the ClipForge tools (ClipForge 1.15.0, build 130).
Media folder: C:\Users\<you>\Videos\clipforge-test
Exports and files you write go to: <media folder>\clipforge-test-output\test5\
Never delete, move, rename or overwrite anything of mine. Only create new projects whose names start with "T5 ".
If an output file or folder already exists from an earlier run, add "-2" to the new name instead of reusing it.
For each step report PASS / FAIL / SKIPPED and the numbers you saw (lengths as m:ss, sizes in MB, frame sizes as width x height, counts).
If a step needs a file or a program I do not have, say so, mark it SKIPPED with the reason and go on.
Do not guess: you cannot see or hear the videos, so never judge picture, lip sync or sound; list those for me at the end.
You CAN read captions and transcripts; say so when a judgement comes from the text.
Where a step says STOP, ask me and wait for my answer. Never download a language pack without my yes.
Before EVERY change that touches many things at once (remove_silences, replace_in_captions, make_chapters,
captions_from_transcript, restore_cut, set_clip_properties "all") run it with dry_run true first, report what it would do,
and only then run it for real. Quote exactly what the tool answered when something is refused.

A. Connection
 0. Before anything else: call get_guide (section "start") and say in two lines what it tells you
    to do first. Then run self_test and paste its table (every row PASS; speech may be SKIPPED).
 1. get_status. Report: the version line (must say 1.15.0 and build 130); the helper's path (it
    must be in a ClipForge "claude" folder under my user's app data, NOT next to clipforge.exe)
    and whether it says this is the helper the app installed; the projects folder; ffmpeg and
    ffprobe with versions and paths (you need ffprobe in step 28); whether an export or a
    transcription is running; every speech program found and the language packs on the computer
    (or the exact sentence about what to install when none was found). FAIL if the version or
    the build is different. Also count the ClipForge tools you have been given: 70 expected.
 2. Look at the media folder. Pick and name: LONG = the talking video of 3 to 10 minutes (if
    only longer ones exist, the longest talking one), VOICES = sound files recorded per speaker
    for LONG if there are any (say which speaker name you read from each file name), SRT = a
    subtitle file for LONG if there is one, SHORT = a video under 1 minute. Tell me which files
    you chose and their lengths.
 3. create_project "T5 Long" (16:9) with LONG. If LONG is longer than 10 minutes, trim_clip it to
    its first 6 minutes (out_ms 360000) and say so. With VOICES: add_voice each one (report
    offset_ms and confidence; under 0.5 is NOT lined up: say so). Report the short summary
    (length, size and why, tracks).
 4. Words for "T5 Long", in this order: (a) with SRT: import_srt it and report the caption count;
    (b) else, if get_status found a speech program: transcribe with the language spoken (ask me
    if unsure), quality "auto", WITHOUT download_pack. If it answers that a language pack is
    needed: STOP, show me the pack's name and size and the smaller choices, and ask "Download
    <pack> (<size>)? yes / no". Only after my yes call it again with download_pack true. Poll
    get_transcribe_status (wait_seconds 45) to the end; never start it twice. Then
    captions_from_transcript with dry_run true (report the count and the first three), then for
    real; (c) else: say "no words", and mark steps 16 to 23 and section G as SKIPPED where they
    need words (each step says what to do instead). Report which of a / b / c happened.

B. Captions: read and replace (1.13)
 5. duplicate_project "T5 Long" to "T5 Captions". In the copy: remove_title with all_captions true
    (dry run does not exist for it: this is a test copy), then add 24 captions with add_caption,
    one every 5 s from 5 s on, 3 s long each, with these texts: number N from 1 to 24;
    N = 1, 7, 13, 19: "Sam Taylor: Sem says test line N."; N = 4, 10, 16, 22: "Alex K: Sem was
    right about line N."; every other N: "This is line N." Report the caption count (24).
 6. get_captions with defaults. Report: the count it gives, the size of the answer (roughly, in
    KB), the first four lines exactly, and whether each line has the form
    "start-end [m:ss] Speaker: text".
 7. Paging: get_captions with limit 10; then offset 10 limit 10; then offset 20 limit 10. No line
    twice, none missing, 24 in all; the answer says when there is more.
 8. get_captions with format "paragraphs": report the first three paragraphs. Captions without a
    name must be joined to the speaker before them (lines 2 and 3 belong to Sam Taylor, 5 and 6
    to Alex K). Then get_captions with ids true and limit 3 (each line has a title_id), and with
    from_ms 30000 to_ms 60000 (only the captions in that half minute: say which numbers).
 9. replace_in_captions find "Sem" replace "Sam" whole_word true, WITHOUT dry_run (dry run is the
    default): the answer must be in the "would" form with the number of places (8) in the number
    of captions (8) and examples. get_captions: "Sem" is still there (nothing changed).
10. The same with dry_run false. Report places and captions changed (same as step 9?). get_captions:
    no "Sem" left, "Sam Taylor: Sam says test line 1." is there. Then replace_in_captions find
    "xyzzy" replace "q" (dry run): a clear "not found" answer, no error.
11. undo: get_captions shows "Sem" again in all 8 captions (one step took it all back). redo: "Sam"
    again. Report the counts after each.

C. Who speaks when, and a cut at the turns (1.13)
12. get_speech_map on "T5 Long" (view "turns"). Report: how long the first call took, the speakers
    (with VOICES: their track names; without: the video's own sound as one speaker), for each
    the total talking time and the share (the shares add up to about 100 %), the number of
    turns, and the first five turns exactly as returned ("start-end [m:ss] Name 12.4 s").
13. get_speech_map again with view "stretches", from_ms 0, to_ms 60000: the stretches of the first
    minute. It must answer at once (the listening is kept). Then with a speaker name (or the one
    speaker) and min_ms 2000: only that speaker's longer stretches.
14. duplicate_project "T5 Long" to "T5 Turns". From the turns of step 12 find the longest pause
    between two turns in the first three minutes (at least 2 s; say from when to when). Cut it
    out of the copy, leaving 150 ms of air on each side: split_at the pause's start + 150 ms,
    split_at its end - 150 ms, remove_clip the middle piece. Report: the clip count (3, then 2),
    the length before and after (shorter by the pause minus 300 ms), and with VOICES that every
    voice has one item per clip and kept its offset_ms.
15. get_speech_map on "T5 Turns": the turn after the cut now starts earlier by the length removed
    (give both times). Then undo three times: "T5 Turns" is one clip of the old length again.

D. Good-moment markers (1.14)
16. In "T5 Long": add_marker at 0:40 with label "T5 first", at one third of the video with label
    "T5 middle" and at two thirds without a label. Report the three marker ids. add_marker at
    0:40 again: what does it answer?
17. list_markers. Report for each: time, label, what is said there (from the captions or the
    transcript; with "no words": say what it shows instead), and the part a short around it
    would take (from - to and length: about 20 s before to 25 s after, moved outward to pauses).
18. remove_marker the one without a label; list_markers shows two. Then trim_clip the first clip
    5 s shorter at its START (in_ms 5000) and list_markers again: both markers moved 5 s earlier
    with their picture (give the times). undo: back where they were.
19. A short from a marker: make_short with the from - to that list_markers gave for "T5 middle",
    name "T5 Marker short", caption_style "short", snap_to_speech true. Report the times asked
    and the times it used, the length, the size (1080 x 1920), the caption count, the warnings.

E. Shorts: candidates, your pick, my choice (1.14)
20. suggest_shorts on "T5 Long" with defaults. Report: where the words came from (transcript or
    captions), how many candidates in all, the size of the answer in KB, and the first two
    candidates exactly as returned (times, speaker, text, signals). Page once (offset / limit):
    no candidate twice. With min_seconds 20 and max_seconds 45: how many are left?
    (With "no words": report the exact answer of suggest_shorts, mark 20 to 22 SKIPPED, and in
    step 22 make one short from the longest single turn of step 12 between 20 and 45 s instead.)
21. Read the candidates and propose THREE, by the rules of the guide's recipe "Find the best
    shorts in a long video" (call get_guide section "recipes" first): a hook in the first 3
    seconds, one idea, a complete thought, ends on a point, no inside references, 20 to 45 s.
    For each: start and end (m:ss), length, speaker, first and last words, a title of a few
    words, and ONE line saying why. Say once that you cannot see the picture. Then STOP and ask
    me: "Which one shall I make: 1, 2 or 3?" Wait.
22. make_short for the one I chose: from_ms / to_ms of the candidate, name "T5 Short 1",
    caption_style "short", title = the title you proposed, snap_to_speech true. Report: the new
    project's id, the times asked and used (did snapping move them, by how much?), the length,
    the size and why (1080 x 1920), the caption count, whether a title item sits at the top for
    the whole length (get_project), the warnings (longer than 60 s? mid-sentence?), and that
    "T5 Long" is unchanged (length, clip, caption and marker counts as before).
23. get_captions on "T5 Short 1" (limit 5): the captions start near 0:00 and no line is longer
    than two lines' worth (say the longest in characters). With VOICES: both voices are in the
    short and still linked.

F. Publishing notes, chapters, the kit (1.14)
24. get_publishing_notes on "T5 Long": everything empty (say what it shows for music credits).
    Then, from the words you read, offer me THREE titles, each under 70 characters and different
    in angle, and STOP: "Which title: 1, 2 or 3 (or type your own)?" Wait. (With "no words":
    offer three plain titles from the file name and say so.)
25. set_publishing_notes with the title I chose, a description of two or three plain sentences,
    5 to 10 hashtags, and short_title = the title of "T5 Short 1". Show me what you wrote.
    get_publishing_notes: the same text comes back. Report what the answer says about undo.
26. make_chapters with dry_run true: report the list, what it was made from (titles, captions or
    who speaks) and that get_publishing_notes still has no chapters. Then make_chapters for
    real: the same list is stored. Check the rules: first at 0:00, at least three, each at
    least 10 s. If the video is too short for chapters, quote the answer and mark this SKIPPED.
    Then set_publishing_notes chapters "0:05 Start\n0:09 Too soon": quote the warning it gives;
    then undo, and get_publishing_notes has the good list again.
27. export_kit: project "T5 Long" with destinations ["youtube", "podcast"], projects
    [{"T5 Short 1", ["shorts"]}], output_dir ...\test5\kit. It is ONE background job: report the
    FIRST answer exactly (job id, what it will make, the time estimate) and note the clock time.
    Poll get_export_status with wait_seconds 45 until status is finished; never start it twice.
    Report: the number of status calls, the percent values and the file named in each, the
    total minutes, and the list of files from the final answer with any warning (pass a warning
    about 60 seconds or 16 MB on with "check the site").
28. Check the kit folder with the ffprobe that get_status named (if you cannot run programs, say
    so and report what get_export_status listed instead). For each file: size in MB, and from
    ffprobe the frame size, the length and the video / audio codec. Expected:
    "T5 Long - YouTube.mp4" 1920 x 1080 and as long as "T5 Long"; "T5 Short 1 - Short 9x16.mp4"
    1080 x 1920 and as long as the short; "T5 Long - audio.mp3" sound only, as long as "T5 Long";
    "T5 Long - text.txt". No file ending in ".part" is left. Nothing was added to the project
    list by the export (list_projects: the same T5 projects as before step 27).
29. Read "T5 Long - text.txt" and report its headings in order and, for each, the first line under
    it. It must hold the title, description, hashtags and chapters exactly as in step 25 and 26,
    the short title, and a part for each file saying what to paste there. Say whether the part
    for the short uses the short title.

G. The recipe, once, end to end
30. duplicate_project "T5 Long" to "T5 Recipe" (say what came with it: captions, transcript,
    markers, publishing notes). Call get_guide section "recipes" and follow "From a long
    video to a publishing kit" on "T5 Recipe", step by step, reporting one line per recipe step.
    Note the clock time at the start.
31. Recipe step 1 (clean-up): remove_silences with dry_run true (report cuts, time it would
    remove, cuts per minute), then for real with min_caption_ms 1200. Report the new length.
32. Recipe steps 2 to 4: the words are already there (say so). make_chapters dry_run true, rewrite
    the names from what each part is about (keep the times), and save them with
    set_publishing_notes together with the SAME title I chose in step 24 (do not ask again), a
    description and hashtags.
33. Recipe steps 5 to 7: list_markers first (say what you found), then suggest_shorts on the
    cleaned video, pick TWO and say why in one line each, then STOP: "Shall I make both, one of
    them, or others?" Wait.
34. Recipe step 8: make_short for each one I chose (names "T5 Recipe short 1", "… 2";
    caption_style "short", snap_to_speech true, a title each). Read the warnings and fix what
    they name before going on. Then, as a dry run only, set_clip_properties "all" with fit
    "blur" on the first short: report what it would change, and ask me in the final list
    whether I want blur or fill.
35. Recipe step 9: ONE export_kit: "T5 Recipe" with ["youtube", "podcast", "whatsapp"] and each
    recipe short with ["shorts"], output_dir ...\test5\recipe-kit. Poll to the end. Report the
    files, their sizes, the warnings, the minutes.
36. Recipe step 10 (hand over): write the message you would give me: the folder, each file by
    name with where it goes, what to paste from the text file, every warning with "check the
    site", and what I should watch before posting. Then report the clock time the whole recipe
    took and how many times you had to stop for me (it should be once).

H. The lock, and tidy end
37. create_project "T5 Lock" (16:9) with SHORT. add_caption "Lock test 0" at 1 s: accepted.
38. STOP and ask me: "In the ClipForge app, open the project T5 Lock and leave it open. Then
    type: open". Wait. Then:
    a. get_project "T5 Lock": it must show that it is open in the app.
    b. add_caption "Lock test 1" at 2 s: must be REFUSED with a message that the project is open
       in the ClipForge app. Quote it. The caption count did not change.
    c. set_clip_properties "all" speed 1.1 with dry_run true: allowed, saves nothing.
    d. set_publishing_notes title "Lock": refused too? Quote the answer.
    e. Ask me: "Please go back to ClipForge's project list, then type: closed". Wait.
    f. add_caption "Lock test 2" at 3 s: accepted now. get_project: not open in the app, 2 captions.
39. list_projects: report every T5 project with clip count and length; no two have the same name.
    get_status once more: no export and no transcription still running. get_export_status
    without job_id: the two kit jobs are listed as finished.

Finish with:
- a results table: step, PASS / FAIL / SKIPPED, the key numbers, notes;
- a kit table for both kits: file, destination, frame size, length, size in MB, warnings;
- an export table: kit, number of files, first estimate, real time, factor;
- the three shorts you proposed in step 21 with their reasons, and which one I chose;
- "Surprises": anything unclear, slow, inconsistent, or an answer that was too long or too
  short to work with (say which tool and roughly how many KB), and anything the guide told you
  that did not match what a tool did;
- "For the owner to watch and listen", as a list of file + time + what to check, at least:
  kit\T5 Long - YouTube.mp4 at the start, the middle and the last 20 seconds (picture and
  voice in sync, captions readable and on time);
  kit\T5 Short 1 - Short 9x16.mp4 from start to end (starts and ends at a sentence, the title
  at the top, big outlined captions in the lower middle, the person in the frame);
  kit\T5 Long - audio.mp3 for 30 seconds (the same sound as the video);
  the project "T5 Marker short" in the app (does it start and end at a pause?);
  recipe-kit: each Short file from start to end, and the WhatsApp file for 20 seconds (small
  but readable); the YouTube file at three of the silence cuts (I give the times: no chopped
  words);
  the project "T5 Turns" needs no watching (the cut was undone);
- "Most important problems": at most five lines, the worst first, each with the step number.
```

What "good" looks like, for whoever reads the report:

| Area | Expected in 1.15.0 |
|---|---|
| Status | Version line with 1.15.0 and build 130; the helper runs from the ClipForge "claude" folder under the user's app data and says it is the one the app installed; 70 tools. |
| Captions | `get_captions` gives one compact line per caption with time and speaker, pages without gaps, and joins captions without a name to the speaker before them. |
| Replace | `replace_in_captions` is a dry run unless `dry_run` is false; the dry run and the real run give the same counts; one `undo` takes it all back. |
| Who speaks | `get_speech_map` lists turns and each speaker's share from the sound alone; the second call is instant; after a cut the later turns are earlier by exactly what was removed. |
| Markers | Added, listed with what is said there and the part a short would take, removed; they move with their picture when the clip is trimmed. |
| Shorts | `suggest_shorts` offers whole-sentence passages with signals and no verdict; Claude proposes three with a reason each and waits; `make_short` makes a NEW upright 1080 x 1920 project with the Short caption look and a title, snapped to pauses, and warns over 60 s. The long video is untouched. |
| Notes | Three title options, the owner picks; `set_publishing_notes` is one undo step and warns when a chapter list breaks YouTube's rules. |
| Chapters | `make_chapters`: dry run first; first at 0:00, at least three, each at least 10 s. |
| Kit | One job for all files; `get_export_status` follows it to the end; clear file names, the right frame sizes, a text file with what to paste where; no shape copy in the project list; no ".part" file left. |
| Recipe | The whole road with one stop for the owner (which shorts), a dry run before each bulk change, and a hand-over message that names the folder, the files and what to paste. |
| Lock | Edits are refused only while the project is open in the app; a dry run is still allowed; after going back to the project list they are accepted. |
