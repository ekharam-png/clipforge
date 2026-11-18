# Claude control test (paste into a new Claude chat)

Before pasting: close ClipForge (or go back to its project list). In File
Explorer, select 2-3 short videos and 1 photo, hold Shift, right-click, choose
"Copy as path", and paste them where it says FILES.

```
Use the ClipForge tools to run a test. Report each step as PASS or FAIL with what happened.
Never delete or overwrite anything.

FILES:
<paste the copied paths here, one per line>

1. get_status: report the version, projects folder and whether FFmpeg was found.
2. create_project "Claude test 1" with shape 9:16.
3. add_media with the FILES above (videos first, then the photo). Report each clip's length.
4. split_at the middle of clip 1, then set the second half to speed 2.
5. Add a crossfade transition (500 ms) into clip 2.
6. add_title "Claude test" for the first 3 seconds; add_caption "Hello" at 5 seconds for 2 seconds.
7. On the longest video clip: denoise on, voice_focus 60.
8. remove_silences on the longest video clip; report how many pieces it made.
9. get_project: check the title and caption still sit on the same picture after the cuts.
10. export_video full quality to
    C:\Users\<you>\Videos\test\clipforge-test-output\claude-full.mp4
    and small quality to
    C:\Users\<you>\Videos\test\clipforge-test-output\claude-small.mp4
    Report size, length and which encoder was used for each.
11. Finish with a short table: step, PASS/FAIL, notes. Then tell me to open
    "Claude test 1" in ClipForge and listen to both exports.
```
