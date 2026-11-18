# Claude control test 2 (longer; for version 1.4.0)

Close ClipForge first. Paste into a new Claude chat.

```
Run "ClipForge test 2" with the ClipForge tools. Media folder: C:\Users\<you>\Videos\test
Exports go to: C:\Users\<you>\Videos\test\clipforge-test-output\test2\
Never delete or overwrite anything. For each step report PASS / FAIL and the numbers you saw.
If a step needs a file I don't have (for example music), say so and skip it.

A. Podcast-style clean-up
 1. Create project "T2 Podcast" (shape 16:9) with the longest talking video.
 2. Add a caption at 20 s ("Caption A", 2 s) and another at 40 s ("Caption B", 2 s).
 3. remove_silences with a threshold that actually finds pauses (try -35, then -30, then -25 dB).
    Report pieces and seconds removed, and the new times of Caption A and B (they must have
    moved earlier by the removed time before them, and still be 2 s long).
 4. Set clip "all": speed 1.25, denoise on, voice_focus 50. Report the new total length.
 5. Undo is not available across calls, so instead: duplicate_project to "T2 Podcast copy",
    then in the copy set speed back to 1 on all clips; confirm the original is unchanged.
 6. Export "T2 Podcast" full quality. Report size, length, encoder.

B. Family montage
 7. Create "T2 Family" (shape 9:16) with all videos and photos in the folder (photos 3 s each).
 8. Crossfade (600 ms) into every clip after the first; set fit "blur" on all clips.
 9. If there is any music file (mp3/m4a/wav) in the folder or in my Music folder, add it at 0 s,
    volume 0.6, fade-in 1 s, fade-out 2 s, and turn on duck_music. Otherwise skip.
10. Title "Our day" for the first 3 s; caption "The end" in the last 2 s.
11. Export full and small. Then set shape 1:1 and export again ("T2 Family square").
    Report all three sizes, lengths and encoders.

C. Sport-style slow motion
12. Create "T2 Slowmo" with one video. Split at 3 s and 5 s; set the middle piece to speed 0.25,
    zoom 1.5. Add title "Slow motion" over the slow part. Report the new length.
13. Export small.

D. Robustness
14. Try to add a file that does not exist and a folder instead of a file: both must give a clear
    error, nothing changes.
15. export_srt for "T2 Podcast"; then create "T2 Captions only" from the same video and
    import_srt that text. Report how many captions came across.
16. list_projects and get_project for each T2 project: report clip counts and lengths.

Finish with a table (step, PASS/FAIL, notes) and a list of anything that surprised you.
Then tell me which exported files to listen to, and at which times.
```
