# ClipForge feature log

Everything ClipForge can do, grouped by area, with the version it arrived in
(the version is the one in Help > About ClipForge). Plain descriptions; the
in-app Help explains how to use each one. Newest changes are in
`CHANGELOG.md` ("What's new" in the app). Keep this file up to date with
every release: a test fails when CHANGELOG.md has a version this file does
not mention.

Versions so far: 1.0.0, 1.1.0, 1.2.0, 1.3.0, 1.4.0, 1.5.0, 1.6.0, 1.7.0,
1.8.0, 1.9.0, 1.10.0.

## Projects

| Feature | Since | What it does |
|---|---|---|
| Project list | 1.0.0 | All your projects with a picture, length and date; tap one to open it. |
| Saving by itself | 1.0.0 | Every change is saved a moment after you make it. |
| Undo and redo | 1.0.0 | Take back a change, or bring it back. |
| Duplicate a project | 1.1.0 | Makes a copy to try something without risk. |
| Share project file / Open project file | 1.1.0 | Packs a project with all its media into one file to move it between phone and computer (also a backup). |
| "Not saved — retry" | 1.2.0 | Says clearly when a save failed and lets you try again. |
| Missing files and Find file | 1.2.0 | Shows which file is gone and lets you point at it again; checked before every export. |
| Unused copies cleaned up | 1.2.0 | Copies of media no project uses any more are deleted by themselves. |
| Drag and drop onto ClipForge (computers) | 1.3.0 | Drop videos, photos, music or a project file to start or add to a project. |
| History | 1.4.0 | A named list of your changes; tap one to go back to that point. |
| Long videos | 1.4.0 | Projects of 40 minutes and more stay smooth; a note for very long projects. |
| Version line and Copy version info | 1.4.0 | Shows exactly which build you have, for bug reports. |
| Rename project from the editor | 1.7.0 | File menu > Rename project. |
| Android keeps its own copy of every file | 1.8.0 | Videos no longer go missing when the gallery moves or deletes the original; the same file is stored once. |
| Find file: Search the gallery (Android) | 1.8.0 | Looks for a missing file by its name on the phone and copies it in. |
| Clean-up never deletes what is in use | 1.8.0 | Files the open project or its undo history still needs are always kept. |
| "Open in the app" mark | 1.9.0 | An open project is marked, so Claude does not change it at the same time; leftovers of a crash are ignored and cleaned up. |

## Timeline & cutting

| Feature | Since | What it does |
|---|---|---|
| Add videos and photos | 1.0.0 | Pick several at once; they go after the selected clip or at the end. |
| Trim, split, delete, reorder | 1.0.0 | Drag the ends to trim, Split at the playhead, drag to reorder. |
| Live preview | 1.0.0 | Plays the edit as it will look, with seeking. |
| Transitions | 1.1.0 | Crossfade, fade through black, slide left, slide up. |
| Speed 0.25×–4× | 1.1.0 | Slow motion or faster, voice pitch kept. |
| Freeze frame | 1.1.0 | Holds the picture under the playhead still. |
| Remove silences | 1.1.0 | Cuts the quiet parts out of talking clips. |
| Apply to all clips | 1.2.0 | Gives every clip the same setting. |
| Keyboard shortcuts | 1.2.0 | Space, arrows, Delete, undo/redo and more (computers). |
| Adaptive silence finding and Sensitivity | 1.5.0 | Measures the background noise first; fewer or more cuts. |
| Duplicate a clip or title | 1.7.0 | A copy right after it (Ctrl/Cmd+D). |
| Copy settings / Paste settings | 1.7.0 | Gives another clip the same look, speed, sound, crop and fit. |
| Snapping | 1.7.0 | Drags line up with the playhead and the edges of other items (yellow line). |
| J / K / L, I / O, zoom keys | 1.7.0 | Play backwards / stop / forwards, start or end a clip at the playhead, zoom the timeline. |
| Frame-exact arrow keys | 1.7.0 | Step exactly one frame of the clip shown. |

## Picture

| Feature | Since | What it does |
|---|---|---|
| Shape 9:16, 16:9, 1:1, 4:5, original | 1.0.0 | The shape of the finished video. |
| Fit, Fill, Blur | 1.0.0 | How a clip of another shape sits in the frame. |
| Brightness, contrast, saturation, zoom | 1.1.0 | Rescue dark footage, zoom in. |
| Video size 720p / 1080p / 4K | 1.5.0 | Export size instead of the first clip's size. |
| Crop | 1.6.0 | Drag the corners of a frame on the picture, free or held to a shape. |
| Rotate and flip | 1.6.0 | For videos filmed the wrong way round. |
| Position | 1.6.0 | Choose which part stays in the frame with Fill or zoom. |
| Overlay (picture-in-picture, side by side, top and bottom, full) | 1.6.0 | A second video row above the clips, with its own trim, speed, volume and fades. |
| Fade in from black / Fade out to black | 1.7.0 | For the whole video and for each clip. |
| Filter (Warm, Cool, Black & white, Vintage, Vivid) and Warmth | 1.7.0 | One-tap colour looks. |
| Frames per second 24 / 25 / 30 / 60 / as clips | 1.7.0 | Export frame rate. |
| Smooth preview (phones) | 1.8.0 | Lighter video decoding while editing; exports unchanged. |
| Lighter preview while playing | 1.8.0 | Titles and the picture are only redrawn when they change. |

## Text

| Feature | Since | What it does |
|---|---|---|
| Titles | 1.0.0 | Text over the picture for a time. |
| Captions and subtitle (.srt) import / export | 1.1.0 | Lower text lines; bring in or save subtitle files. |
| Titles follow their clip | 1.2.0 | Text stays with its clip through cuts and speed changes. |
| Text fits vertical videos | 1.2.0 | Sized from the frame's short side, kept inside the frame. |
| Fonts with English, Russian and Hebrew letters | 1.7.0 | Classic, Modern, Elegant, Handwritten. |
| Outline, Shadow, styles, positions, alignment | 1.7.0 | Ready-made looks, top / middle / lower third / bottom, left / centre / right. |
| Appear / Disappear animations | 1.7.0 | Fade, slide up, pop. |
| Credits caption | 1.8.0 | Add credits at the end puts the music credits on the last 4 seconds. |

## Sound

| Feature | Since | What it does |
|---|---|---|
| Music with volume and fades | 1.0.0 | Add a song at the playhead; fade in and out. |
| Volume and mute per clip | 1.0.0 | How loud each clip's own sound is. |
| Clean up sound | 1.1.0 | Lowers hum, hiss and background noise (export, and instantly since 1.4). |
| Lower music under speech | 1.1.0 | Music gets quieter while someone talks. |
| Music fades out at the video's end | 1.2.0 | Instead of stopping dead. |
| Preview volume matches export | 1.2.0 | What you hear is what you get. |
| Voice focus | 1.3.0 | Clearer speech, quieter background. |
| Sound from (track, left / right only) | 1.3.0 | Choose which sound of the file to use. |
| Hear a sample | 1.3.0 | 15 seconds with and without your sound settings. |
| Instant sound processing | 1.4.0 | Clean-up and voice focus prepared in the background, heard in the preview. |
| Hear original | 1.4.0 | Compare with the untouched sound. |
| Sound tracks (up to 3) | 1.5.0 | Voice, Music, Effects rows with volume, mute and solo. |
| Separate sound to track / Put sound back | 1.5.0 | Move a clip's sound to its own track (L-cuts and J-cuts). |
| Video sound in one place | 1.5.0 | Mute or turn down all clips' own sound. |
| Move sound tracks up and down | 1.7.0 | Reorder the rows. |
| "What is this sound?" | 1.10.0 | Every sound file you add is asked about: Voice for the video, Music or Sound effect, guessed from its name and length. |
| Voice recorded separately, lined up by sound | 1.10.0 | A microphone or Zoom per-speaker file is compared with the camera's sound and placed in sync; own track named after the speaker; camera muted. |
| Voice follows its clip | 1.10.0 | Trim, split, speed, Remove silences and delete keep a lined-up voice in sync, in the same Undo step; several speakers each on their own track. |
| Nudge, Line up again, Unlink | 1.10.0 | Move a voice by 1 frame / 10 ms / 100 ms, retry the comparison, or end the link (the voice stays where it is). |
| Remove silences listens to the voice | 1.10.0 | With a lined-up voice the quiet parts are found in the voice(s), not in the muted camera sound. |
| Fit music to video | 1.8.0 | The music ends exactly with the video, with a 2-second fade-out. |
| Loop music | 1.8.0 | Short music repeats with soft cross-fades until the video ends. |
| Find free music | 1.8.0 | Search openly licensed music (Openverse), listen, download and add it. |
| Music credits | 1.8.0 | Licence and artist kept with the music; Copy credits for your post. |

## Export

| Feature | Since | What it does |
|---|---|---|
| Export full or small | 1.0.0 | Same quality as the clips or a smaller file. |
| Android: straight to the gallery | 1.1.0 | The finished video appears in Movies. |
| Share sheet on phones | 1.2.0 | Send the video to another app. |
| 60 fps export | 1.2.0 | Smooth motion for sport (frame rate choice since 1.7). |
| Graphics card export | 1.3.0 | Faster exports, falls back to the processor if needed. |
| Estimated size and free space check | 1.4.0 | Warns before a full disk spoils an export. |
| Keeps exporting with the screen off (Android) | 1.4.0 | A notification keeps the export running. |
| Sound only (M4A, MP3) | 1.7.0 | Export just the sound. |
| Safer animated titles in the export | 1.8.0 | Popping and fading titles are drawn in a way that does not crash FFmpeg. |

## Help

| Feature | Since | What it does |
|---|---|---|
| First-launch tour | 1.4.0 | "Would you like a quick tour?" then 8 steps over the real buttons. |
| Searchable help | 1.4.0 | Copes with typos; "Did you mean". |
| "?" hints | 1.4.0 | Next to the trickier settings. |
| What's new | 1.4.0 | This app's change list, in Help. |
| Keyboard shortcuts page | 1.7.0 | Every shortcut, in Help and the menus. |
| Feature log | 1.8.0 | This file. |

## Claude control

| Feature | Since | What it does |
|---|---|---|
| clipforge-mcp helper | 1.2.0 | Claude Desktop / Claude Code can list, create, edit and export projects (computers). |
| Voice focus and sound source tools | 1.3.0 | Same settings as the app. |
| Sound track and separate sound tools | 1.5.0 | Tracks, moving sound between them. |
| Crop, rotation, overlay tools | 1.6.0 | Same as the app. |
| Fades, filters, title styles, duplicate, copy settings, freeze frame, undo / redo | 1.7.0 | 42 tools. |
| fit_music_to_video | 1.8.0 | Fit or loop music to the video (43 tools). |
| Exports as background jobs | 1.9.0 | export_video answers with a job; get_export_status (progress, time left, result) and cancel_export; the render runs in its own process, survives a server restart and writes a .part file renamed when complete (45 tools). |
| Short answers, paged timeline | 1.9.0 | Edits answer with a summary (what changed, warnings, size and why, who saved last); detail "full" and get_project paging / time range for long projects. |
| Refuses to edit a project open in the app | 1.9.0 | Reading and exporting still work. |
| Dry runs | 1.9.0 | remove_silences (every cut and the total), set_clip_properties "all", apply_to_all, copy_clip_settings, separate_sound "all". |
| Warnings and reports | 1.9.0 | Music past the end, very short captions (min_caption_ms keeps them readable), output size and why, what Small changed, where music is lowered under speech. |
| Subtitles with source times | 1.9.0 | export_srt time_base "source"; import warns when a file no longer fits the cut. |
| add_voice and align_audio | 1.10.0 | Add a separately recorded voice lined up with the video (offset, confidence, drift, warnings); line up, set the offset of, nudge or unlink an existing sound; role / linked_clip / offset_ms in listings; a recipe for Zoom recordings (47 tools). |
| Fuller get_status | 1.9.0 | Program path, version, projects / fonts / jobs folders and FFmpeg first. |
| Claude Desktop extension (.mcpb) | 1.9.0 | One file to double-click instead of editing Claude's config by hand; one per system (Windows, Mac) on the build page. |
| ClipForge skill for Claude | 1.9.0 | A guide Claude loads by itself (upload the zip under Customize > Skills): plan first, safety copy, dry runs, long exports, recipes incl. shorts from a long video, and what it cannot do. |
| "Connect Claude to ClipForge" page | 1.9.0 | Step-by-step setup for Claude Desktop, the skill and Claude Code (docs/claude-setup.html, also in the downloads). |

## Platforms

| Feature | Since | What it does |
|---|---|---|
| Android, Windows, macOS apps | 1.0.0 | One code base; installers built by GitHub Actions. |
| Menu bar on Windows and Linux | 1.4.0 | File, Edit, Playback, Help along the top. |
| macOS menu bar with every command | 1.7.0 | With shortcuts. |
| Mac quit crash fixed | 1.3.0 | Quitting saves first and asks only when something would be lost. |
| Updates install over the old app (Android) | 1.8.0 | One fixed signing key; projects survive updates (one uninstall from 1.7). |

## Planned

From the roadmap in `docs/HANDOVER.md`; not built yet.

- AI voice separation (voice and background as two levels), on the device.
- Automatic subtitles from speech (needs an owner decision: on-device or paid service).
- Removing filler words ("um", "uh") and captions from speech (with the planned on-device transcription).
- Transcript-based editing, then a local AI assistant (computers, experimental).
- Voiceover recording.
- Saved title styles and intro / outro templates.
- Skip back / forward 5 s buttons; zoom the preview; animated zoom and pan (Ken Burns).
- Camera-angle sync by sound for overlay items; rounded picture-in-picture corners.
- iPhone (on hold: needs an Apple account or sideloading).
- Stickers, keyframes, green screen.
- Jamendo music search (needs a client id; Openverse already includes much of Jamendo).
