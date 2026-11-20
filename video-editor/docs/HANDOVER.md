# ClipForge handover

Read this first in a new session. It records what was built, why, how it fits
together, how to build and test it, and what is still open. Last updated
20 November 2026 (1.16.0: Send feedback from inside the app, ONE source
for the outside addresses - `tool/ci/links.json`, which also travels in
latest.json so installed apps follow a move of the site - the website in
`web/`, the old Pages page as a signpost, and `docs/RENAMING.md`; see
"Feedback, one source for addresses, rename readiness (1.16.0)". Before
that 1.15.0: finding things - the menus by task, ONE Settings
page, suggestions, the phone layout, the timeline's context menu, one truth
for "Lower music under speech", and three downloads instead of six; see
"Finding things (1.15.0)" and "Three downloads (1.15.0)". Before that
1.14.1: the Windows update never finished on the owner's
real PC - the script now replaces the folder's contents instead of
renaming the folder, must report in before the app closes, leaves a log,
and there is a tidy-up and an installer; see "Updates that finish on real
PCs". Before that 1.14.0: publishing kit, publishing notes, shorts and
markers, Connect to Claude done by the app, clearer updates; before that
1.13.0: the Text window, sound waves and who is speaking;
before that 1.12.0: the app updates itself, the Claude helper follows the
app, get_guide and self_test; 1.11.0: speech to text).

## What ClipForge is

A personal CapCut-style video editor for the owner (non-technical), installed
as a real app on **Android, Windows and macOS** (iPhone later). Used for short
family videos, podcast clips and sport clips, up to about 5–7 minutes. Possibly
shared with a few friends later.

"ClipForge" is a working name; the owner may change it ("too many
ClipForge out there"). `docs/RENAMING.md` says what a rename touches and
what must not change.

## Where things are

- Repository: this public repository, folder `video-editor/`,
  branch `main`. Versions are published as GitHub Releases (push a tag
  `v<version>`, or run the build workflow by hand on `main` with "publish"
  ticked: the release then creates the tag) and
  the website lives in `web/` (Next.js on Vercel, see `web/README.md`;
  its address is in `video-editor/tool/ci/links.json` and nowhere else).
  `site/` (GitHub Pages, the download page until 1.15) is a signpost to
  the website that still offers the three downloads: versions before 1.16
  open it.
- CI: `.github/workflows/video-editor-build.yml` (repo root).
- User docs: `video-editor/README.md` (install steps, features, Claude control).

## Why it is built the way it is

| Decision | Reason |
|---|---|
| Flutter (one codebase) | Installed apps on Android, Windows, macOS from one code base; iPhone possible later. |
| Project = plain JSON description (`<Documents>/ClipForge/projects/<id>/project.json`), originals never modified | Makes undo, autosave, phone↔computer transfer and Claude control (MCP) all simple. |
| FFmpeg for export (ffmpeg_kit_flutter_new on Android/Windows/macOS = FFmpeg 8.1; system ffmpeg via Process on Linux/dev) | Same export result on every device. Licence: full-GPL build → GPL-3 if distributed publicly. |
| media_kit (libmpv) for live preview | Cross-platform playback with frame-accurate seeking. |
| Pure-Dart core and media layers (no Flutter imports) | So the MCP server can run as a plain command-line program on the computer. |
| Installers built by GitHub Actions | The owner has no developer tools. Windows/macOS jobs run only when started by hand (workflow_dispatch) to save build minutes. |

## Code layout (`video-editor/`)

- `lib/core/model/project.dart` — data model (schema v2). All times are int ms.
  `Clip.durationMs` is timeline length (speed applied); `sourceSpanMs` is raw
  trimmed length. Transitions overlap clips (`Project.transitionOverlapMs`).
  `originalWidth/Height` fix the canvas size once the first clip is added.
- `lib/core/model/title_layout.dart` — `layoutTitleBlock`: line wrapping, font
  size from the canvas **short side**, clamped inside the frame. Used by both
  preview and export so they match.
- `lib/core/model/picture_layout.dart` — where a picture goes (crop,
  rotation, fit, zoom, pan, overlay boxes). Used by both preview and export.
- `lib/core/editor/project_editor.dart` — every edit operation, clamping rules,
  undo/redo, transactions. `editor_controller.dart` is a thin Flutter wrapper.
  `title_anchors.dart` — titles/captions follow their clip through edits.
- `lib/core/storage/` — file store, project bundles (.clipforge.zip),
  missing-media check, cleanup of unused app-owned media.
- `lib/core/subtitles/srt.dart` — SRT import/export.
- `lib/media/sound_align.dart` (pure maths), `sound_align_job.dart` (ffmpeg
  decode), `clip_silences.dart` — 1.10 "Voice recorded separately".
- `lib/media/ffmpeg_command.dart` — builds the whole export filter graph
  (pure function). `process_media_engine.dart`, `ffmpeg_kit_media_engine.dart`
  — the two engines. `media_engine_factory.dart` — platform choice.
- `lib/ui/` — home screen, editor (preview, timeline, tools, clip panels,
  export dialog), `playback/` (A/B preview players, colour matrix), `services.dart`
  (file pickers, gallery save, share sheet).
- `lib/mcp/`, `bin/clipforge_mcp.dart`, `bin/build_mcp.dart` — Claude control.
- `claude/CLAUDE.md` (guide for Claude Code), `claude/skill/clipforge-editing/`
  (the skill), `docs/tools/build_claude_bundles.py` (.mcpb extension and
  skill zip), `docs/claude-setup.html` (owner's setup guide).
- `lib/core/update`, `lib/ui/update`, `lib/core/claude`, `lib/ui/claude`,
  `assets/update`, `tool/ci` — 1.12 self-update and the Claude helper folder.
- `lib/core/text/text_document.dart`, `lib/ui/editor/text_panel.dart` — the
  1.13 Text window. `lib/media/sound_peaks*.dart`, `speech_map.dart`,
  `lib/ui/editor/sound_pictures.dart`, `sound_wave.dart`,
  `lib/ui/speaker_colors.dart` — 1.13 sound waves and who is speaking.
  `lib/mcp/tools_text.dart` — get_captions, replace_in_captions,
  get_speech_map.
- 1.14: `lib/core/model/publishing.dart` (notes, chapters, markers),
  `lib/core/publish/` (chapters + kit text, shorts), `lib/media/destinations.dart`
  (THE presets table), `lib/media/export_kit.dart`, `lib/ui/publish_service.dart`,
  `lib/ui/editor/publishing_panel.dart`, `shorts_actions.dart`,
  `lib/mcp/tools_publish.dart`, `lib/core/claude/connect.dart` +
  `lib/ui/claude/claude_connect.dart`, `lib/mcp/heartbeat.dart`.
- 1.16: `lib/core/links.dart` (the outside addresses + `kAppName`),
  `lib/ui/links.dart` (the ones in use, remembered from latest.json),
  `lib/core/feedback/feedback.dart` (payload, the one request, limits),
  `lib/ui/feedback/feedback_screen.dart`, `tool/ci/links.json` +
  `links.py`, `docs/RENAMING.md`.
- `test/core`, `test/media`, `test/ui`, `test/mcp` — 1931 tests (1.16.0; 1888 at 1.15.0, 1827 at 1.14.1, 1796 at 1.14.0, 1690 at 1.13.0, 1611 at 1.12.0, 1516 at 1.11.0).
  `integration_test/real_app_test.dart` — drives the real app on Linux.

## What was built, and why

### Round 1 — basic editor
Import videos/photos; timeline with trim, split, delete, reorder; live preview;
music with volume and fades; titles; aspect 9:16 / 16:9 / 1:1 / 4:5 / original
with fit / fill / blur; full or small export; undo/redo; autosave; project list.
**Why:** the owner's core list ("import, edit, cut, connect a few videos, add
music, titles, export in same resolution and different orientation").

### Round 2 — features the owner asked for plus later-phase ideas
- Transitions (crossfade, fade through black, slide left, slide up).
- Speed 0.25×–4× (pitch kept). **Why:** slow motion for sport, faster podcasts.
- Brightness / contrast / saturation, zoom, freeze frame. **Why:** sport and
  rescuing dark footage.
- **Sound clean-up** ("Clean up sound" toggle per clip, applied on export):
  `highpass=f=80, afftdn=nr=12:nf=-35, dynaudnorm=f=250:g=7:p=0.8:m=2:b=1`.
  Measured: noise in pauses about −8 dB, no timing change. **Why:** owner asked
  for removing noise and improving audio. **Never listened to on real speech.**
- Lower music under speech (sidechain compressor, export only). About −9 dB under
  normal speech, recovers in 0.3–0.6 s. **Never listened to.**
- Remove silences (keeps 150 ms each side, ignores gaps under 300 ms). **Why:**
  podcasts.
- Captions + SRT import/export (no automatic speech-to-text).
- Duplicate project; share/open project file (zip with media) for phone↔computer.
- Android: export saved straight to the gallery (`gal` plugin).
- Preview loads the next clip in a second player, removing the black gap
  between videos.

### Consistency review fixes
A separate reviewer walked full podcast / family / sport journeys. Fixed:
- Titles/captions did not follow their clip after edits → now re-anchored to
  (clip, source time) on every timing edit, one undo step. Music deliberately
  stays at absolute times.
- Text oversized on vertical video → size from canvas short side, clamped.
- Settings applied to one piece after remove-silences → "Apply to all clips".
- Canvas flipped when clips were reordered → size captured from first clip;
  short side capped 2160 (1080 when a photo).
- Selecting a clip did not show it → tapping seeks into it; Split/Freeze act on
  the clip under the playhead.
- Music past the end was cut hard → fades at the video's end.
- Silent save failures and unreadable export errors → "Not saved — retry" bar,
  missing-file pre-flight with "Find file…".
- Preview volume did not match export (mpv volume is cubic) → compensated.
- Keyboard shortcuts, clearer labels ("Shape", "Saturation"), phone share sheet,
  storage cleanup, 1.25× preset, 60 fps export option.
- New media goes after the selected clip, else at the end.

### Performance and engine fixes
- 100 silence-cut pieces used 3.7 GB to export → consecutive pieces of one file
  are now read from a single input (about 220 MB), also when sped up.
- Very large filter graphs go through a file (`-filter_complex_script` on
  FFmpeg < 7, `-/filter_complex` on 7+).
- FFmpeg 7+ exported photos as full-range colour → forced limited range.
- FFmpeg 8.0's `aselect` passes all frames (bug) → audio pieces now joined with
  atrim + concat.

### Claude control (MCP server, computer only)
`clipforge-mcp` ships beside the Windows/macOS apps. 25 tools in 1.2, 35 in 1.6, 42 in 1.7, 45 in 1.9 (list/create/edit
projects, add media/music, trim/split/move, clip properties incl. "all",
remove silences, titles/captions/SRT, export with progress). Cannot delete
projects or media; refuses to save if project.json changed underneath, and
(1.9) refuses to edit a project the app has open (`.open-in-app` lock).
Needs a separately installed ffmpeg/ffprobe. Install routes: the Claude
Desktop extension (.mcpb, one click), `claude mcp add` for Claude Code, or
the manual config entry (see "One-click Claude install" below). Project must be closed in the app
while Claude edits it. MCP protocol 2025-11-25. macOS binary is Apple Silicon only.
`dart compile exe` does not work inside the Flutter package (build hooks), so
`bin/build_mcp.dart` copies the pure code into a temp package and compiles there.

## Sound of a clip (voice focus, sound source, clean-up)

All in `lib/media/clip_audio.dart` (pure Dart), used by the export graph and
by the preview. Stages, in this order:

1. **Source** — `Clip.audioTrack` (which audio stream; `[N:a:T]` in the
   graph) then `Clip.audioChannel` (both / left only / right only = that side
   copied to both, `pan`). `Clip.audioStreams` records the channel count of
   every audio stream at import (probe); empty for clips added before this
   (the choice is then not offered; the MCP tool probes such clips when a
   track or side is set). A track/side the file is not known to have is
   ignored (`audioTrackInUse`, `audioChannelInUse`). "Remove silences"
   listens to the chosen track and side.
2. **Clean up sound** (`kDenoiseChain`: highpass 80, afftdn, dynaudnorm).
3. **Voice focus** (`Clip.voiceFocus` 0..1, UI 0–100 % in steps of 5):
   `highpass` 60→150 Hz, `lowpass` ~17→7.5 kHz, `equalizer` +3 dB×s at 3 kHz,
   then centre emphasis: `dialoguenhance` + `pan` back to stereo, keeping
   sound that is the same on both sides at its level and lowering the rest
   to 1/(1+2s). Its 1536-sample delay is padded/trimmed away (sync tested).
4. Speed (atempo), volume.

Identical settings across pieces of one file still share one input ("runs").
Schema stays 2 (fields are additive with defaults).

**Measured** (FFmpeg 6.1, synthetic fixtures: formant "voice" in the centre,
f0 ~130 Hz; wide-stereo "music" with bass, chords, guitar notes, hi-hats;
music bed ~3 dB under the voice). Change vs. untouched, 50 % / 100 %:

| | music-only stretch | voice-only stretch | voice band 300–4000 Hz | voice/music ratio while both play (300–4000 Hz) |
|---|---|---|---|---|
| wide-stereo mix | −6.1 / −8.8 dB | −0.9 / −1.5 dB | 0.0 / −0.1 dB | +2.8 / +3.9 dB |
| mono (phone, music in the room) | −2.0 / −2.4 dB | −0.9 / −1.5 dB | 0.0 / −0.1 dB | −0.3 / −0.6 dB |
| voice panned 75/25 + wide music | −6.1 / −8.8 dB | −5.3 / −8.1 dB | −4.4 / −6.6 dB | +0.2 / +0.1 dB |

The integration fixture (`test/media/voice_focus_integration_test.dart`,
more bass and hiss) gives music −9.4 / −13.9 dB, hiss −12.7 / −22.3 dB, voice
±0.4 dB. Peaks never went up; length unchanged.
Left out after measuring: a 300 Hz "mud" cut (lowered the voice more than the
music) and a compressor (raised music between phrases by 3.5 dB relative to
the voice). `dialoguenhance` (FFmpeg 5.1+; stereo in, 3.0 out) gives the
biggest gain on stereo mixes and is a no-op (+0.1 dB) on mono; it makes a
voice that is off to one side quieter, and softens the first ~0.2 s after
silence by up to 2 dB. Honest limits: on a mono phone recording voice focus
is mostly a bass/hiss cut; it cannot take music out.

**Preview.** media_kit's libmpv builds for Android (v1.1.7), Windows
(2023-09-24) and macOS (v0.6.0) contain FFmpeg 6.0 configured with
`--disable-filters --enable-filter=overlay --enable-filter=equalizer`:
`equalizer` is the only FFmpeg audio filter in the shipped players (checked in
the downloaded binaries). The Linux dev build uses the system libmpv, which
has everything, so Linux alone proves nothing. The preview therefore uses
only `equalizer` (in one `lavfi=[...]` graph, after mpv's
`format=format=floatp` so libavfilter never needs `aresample`, which the
shipped builds lack) plus mpv's own `format=channels=` and the `aid`
property:
- live: sound track, left/right only (measured through mpv: kept side at its
  exact level, other side −58…−75 dB), voice focus tone part (high-pass
  approximated within 1 dB, presence identical);
- clean-up: only its 80 Hz rumble cut plays live (same fitted low cut);
- export only: voice focus low-pass and centre emphasis (so on wide-stereo
  music the export is much stronger than the preview — the UI says so), and
  the noise reduction and levelling of "Clean up sound" (afftdn/dynaudnorm
  are not in the players).

**Owner feedback (Mac): "Clean up sound just clicked, no visible change".**
Answered by: a confirmation message when Clean up / Voice focus is switched
on; a badge (wand = clean-up, speaking head = voice focus) on the clip's
timeline block; "Hear original" in the Sound panel (`PlaybackController.
hearOriginalSound`, preview filters off while on, not saved); and
"Hear a sample" (`lib/ui/editor/sound_sample.dart`): renders 15 s around the
playhead (5 s before, 10 s after) of that clip alone with the real export
engine at small quality — once with its sound settings, once without — and
plays them in a dialog with a With changes / Original switch. That is the
only way to hear clean-up's noise reduction before exporting.
Gotchas found by the e2e test: mpv 0.37 fails with "Layout indicates a
different number of channels" when two lavfi filters follow a `format=channels`
conversion (hence one graph, before it); asking mpv for an `aid` the loaded
file lacks turns the option into "no" for the next file (hence the player
re-applies the track after every open, only when it differs).

**Room for AI separation** (being researched separately): per clip, a voice
stem + background stem with a level each would replace stage 1 (the export
mixes the stems where it now reads `[N:a:T]`; the preview plays the mix).
Stages 2–4 stay as they are. See the comments at `Clip.voiceFocus` and the
top of `clip_audio.dart`.

## Instant sound processing and History (16 November 2026)

Owner: "If we make changes, why do I need to wait for the export to hear
them? Let's make changes, have a history of them, and undo if needed."

**Instant sound processing.** When a clip needs clean-up or voice focus
(`clipNeedsProcessedSound`; track/side alone stay live, they are exact),
its sound is rendered in the background with the export's own chain
(`clipSoundFilters`) into `<app media>/processed/snd_<hash>.flac`:
- `lib/media/processed_sound.dart` (pure): the WHOLE source file at SOURCE
  timing (sample n = source time n/48000, `aresample=async=1:first_pts=0`),
  stages 1..3 only (speed/volume stay live), 48 kHz stereo 16-bit FLAC
  (lossless for the export, ~2 MB/min, sample-accurate seeking). Key = hash
  of path + size + mtime + sound settings + `kSoundChainVersion` (bump it
  when the chain changes), so split halves and silence-cut pieces share one
  file and a changed file/setting gets a new one. The AI-separation
  extension point is documented at the top of that file.
- `lib/media/processed_sound_cache.dart`: folder, LRU eviction to 1.5 GB
  (never a file a clip wants now; touch on use), `processedSoundPathsOf`
  for the unused-media clean-up (`removeUnreferencedMedia(alsoUses:)`).
- `lib/media/sound_render_job.dart` + `MediaEngine.renderClipSound` (both
  engines): one ffmpeg run, progress, cancel, `.part` file renamed when done.
- `lib/ui/editor/sound_renders.dart` (`EditorSession.sounds`): queue; a key
  starts 800 ms after the wanted set stops changing (slider drags), 2 at a
  time, 1 while playing, playhead clip first; Stop / Process sound / Try
  again; renders nobody wants any more are cancelled.
- Preview (`PlaybackController.processedSound`): when ready, the video
  player is silenced only once a sound player has the file loaded, and the
  sound player plays it at the clip's source position, speed as rate
  (pitch kept), volume/mute, transition crossfade (two sound players);
  pieces of one file play through; drift correction (sound > 45 ms early or
  > 80 ms late, 30 ms for the first after a start, 5 reports smoothed, at
  most every 2 s). "Hear original" switches back instantly.
  Not ready: light live preview + "Preparing sound…" (preview note, clip
  block bar "Sound 40%", Sound panel row).
- Export: `ExportOptions.processedSound` (clip id -> ready file; the app
  passes `sounds.readyFiles`) reads the file as the clip's audio input
  (`-ss in -t span`), runs still share one input. MCP passes nothing and
  uses the normal chain. `test/media/processed_sound_integration_test.dart`
  compares with the normal chain (FFmpeg 6.1): same level within 0.15 dB,
  0 samples lag, difference -29 dB (one clip: the normal chain's clean-up
  starts cold at the trim point) / -41 dB (run); with speed 1.5 atempo
  differs in phase (30 samples), level identical.
- Measured: render 1.2 s per minute of sound (10 min file, clean-up + voice
  focus, this 4-core container), ~2 s/min for a 12 s file. Linux e2e: file
  ready 0.7 s after the 800 ms wait for 12 s of sound; sound minus picture
  median -13 / -32 ms (mpv time-pos, null audio output, machine loaded).
- Not done: playback from finished chunks of a long file (a 40 min file is
  one render, ~50 s here, longer on a phone, progress shown).
- Unverified: FLAC decoding and the extra sound player on the shipped
  Android/Windows/macOS libmpv builds; sync with real audio devices; render
  speed on phones.

**History.** `ProjectEditor.history` / `historyPosition` /
`jumpToHistory` (one notification, later steps stay redoable until a new
edit) / `nameNextEdit` / `transaction(label:)`. Names come from
`lib/core/editor/edit_labels.dart` (`describeEdit(before, after)`, so MCP
and every UI path get them without changes), or a hint (remove silences).
Per editor session, not saved (cheap to save, but undo snapshots are not
saved either). UI: `lib/ui/editor/history_panel.dart`; desktop top-bar
button, Edit > History (Ctrl/Cmd+Shift+H) in both menu bars; phones: More
(bottom bar) > History, sheet. Help articles `history`, `preparing-sound`.
Screenshots `editor_*_history`, `editor_*_sound_processing`,
`editor_*_sound_ready`.

## Sound tracks, separate sound, adaptive silences, video size (1.5.0, 17 Nov 2026)

Owner: "two or three sound tracks and video, and mute the video's own sound".

- **Model** (`project.dart`, schema still 2, additive): `SoundTrack` (id, name,
  volume, muted, solo, duck = "Lower this track under speech", speech);
  `Project.tracks`, `Project.videoSound` (video's own sound: volume/mute/solo,
  id `video`), `Project.videoSize`. `Project.soundTracks` = tracks + an implicit
  track for any unknown `AudioClip.trackId` (code-built projects). Old JSON
  (no `tracks`): music goes on "Music" with the old duckMusic; overlapping old
  music spreads over "Music 2/3...". `AudioClip` gained trackId, speed, the clip
  sound options (denoise, voiceFocus, audioTrack/Channel/Streams),
  sourceClipId, linked; `AudioClip.soundClip` views it as a Clip so
  clip_audio / processed sound / preview filters apply unchanged (a separated
  sound with the same settings shares the clip's processed file).
- **Rules** (`core/editor/sound_tracks.dart`, documented in ProjectEditor):
  no overlap on one track; adding at a busy spot → first free track → new
  track (max 3, `ProjectEditor.maxSoundTracks`) → after the overlap on the
  wanted track; moving → nearest free place; trimming → clamped at neighbours;
  delete track only when empty. `duckMusic` stays as the default for new
  Music tracks; `setDuckMusic` sets every non-speech track.
- **Separate sound**: speed is CARRIED (atempo / player rate). The sound is
  linked: it mirrors its clip on every edit (place, in/out, speed), is deleted
  with it, and pieces from split / remove silences get their own linked
  sounds; transitions between linked neighbours start the later sound after
  the overlap. Moving/trimming/speed by hand unlinks (L/J-cuts). Reattach
  copies sound settings back and unmutes. One undo step each, History labels.
- **Export** (`buildSoundTrackMix` in ffmpeg_command.dart): clip chain per
  sound clip → per-track amix, padded, track gain (volume/mute/solo) → duck per
  track with side chain = video sound + other audible speech tracks → amix
  normalize=0 → alimiter. Muted video sound → `[acat]anullsink`. Pieces of one
  file on one track share one input (`findSoundRuns`, span ≤ 5 min, gaps ≤ 10 s).
  No sound tracks + video gain 1 → `[acat]` exactly as before.
- **Preview**: per track the clip under the playhead + the next one (≤ 2
  players/track, pooled), track gain live, speed as rate, processed file when
  ready; video sound gain multiplies every deck. Ducking not previewed.
- **UI**: row header column left of the timeline (44 px phones / 112 px
  wider; tests use `timelineOrigin`); handles/lane blocks use
  `DragStartBehavior.down`. `sound_tracks_ui.dart`: headers (M/S on desktop,
  icon → menu on phones), track menu, "Separate sound to track…", sound clip
  options. Help: `sound-tracks`, `separate-sound` (limit 60 articles).
- **Remove silences** (`media/silence_levels.dart`): 40 ms RMS windows via
  astats/ametadata; floor = 10th pct, loud = 90th; threshold = floor +
  clamp(35 % of span, 4..12) dB in −70..−12; nothing when span < 6 dB.
  Fixed −35 dB failed because silencedetect is per-sample (noise peaks).
  `thresholdDb` null = auto; a number keeps silencedetect. Dialog: Sensitivity
  Fewer/Automatic/More (±4 dB, no re-scan). Fixtures: floor −45 → −34 dB,
  floor −30 → −24 dB, 5/5 gaps.
- **Video size**: Match first clip / 720p / 1080p / 4K short side, capped 2160.
- **MCP**: list/add/update/remove_sound_track, move_audio_to_track,
  separate_sound, reattach_sound; add_music track_id; update_audio
  denoise/voice_focus; set_project_settings video_size; remove_silences auto.
- Unverified: by ear (mix, ducking per track, sync of separated sound on real
  players), several sound players at once on Android/Windows/macOS libmpv,
  the e2e does not drive sound tracks in the real app.

## Crop and position, overlay track (1.6.0, 17 Nov 2026)

Owner (CapCut comparison): crop/reframe clips (keep the person in shot when
a wide video becomes vertical), rotate/flip, and a second video row for
picture-in-picture, split screen and camera cut-aways.

- **Model** (`project.dart`, schema still 2, additive; defaults = no change,
  so old projects load and export exactly as before): `Framing` on every
  `Clip` (flat JSON keys `crop` {x,y,width,height}, `rotation`, `flipH`,
  `flipV`, `panX`, `panY`). Order: the picture as the file shows it
  (metadata rotation applied) → turned `rotation`° clockwise → mirrored →
  cropped (crop fractions are of the turned, mirrored picture) → fit / fill
  / blur, zoom → pan. `Framing.turned` / `flipped` take crop and pan along
  (so "Rotate right" keeps the same part in shot; a single mirror makes the
  stored rotation go the other way). `Clip.framedSize` = size after turn +
  crop, used for "same shape" and fitting.
- **Pan** (-1..1, 0 = centred) = where the visible window sits in the
  EXCESS picture: Fill's crop and Zoom's window (also Blur's sharp
  picture). With Fit and zoom 1 it does nothing (no black is ever panned
  in); the panel says so. This also answers the owner's earlier idea
  "choose the zoom point" (zoom + pan). Ken Burns animation is still open.
- **Overlay track**: `Project.overlays` (`OverlayClip` = a `Clip` for the
  media/trim/speed/volume/mute/framing + `startMs`, fades, `layout` pip /
  sideBySide / topBottom / full / free, `corner`, `size` (fits into that
  fraction of the frame both ways, own shape after crop), `x`/`y` (free),
  `overlayFirst` (split side), `border`). Exactly one overlay row (decision:
  the spec's "at most 1 extra track"; the model is a flat list, so a second
  row later would need a `row` field). Rules in `ProjectEditor`: items never
  overlap; add at a busy place → right after what is in the way; move →
  nearest free place; trim → stops at neighbours. Overlays stay at their
  timeline time when the main track is edited (like music; not anchored
  like titles) — decision for simplicity; the MCP notes tell Claude to add
  overlays after cutting.
- **Geometry shared by preview and export**: `lib/core/model/picture_layout.dart`
  (`placeClip`, `placeCover`, `overlayFrame`, `cropEditorPicture`,
  `cropForRatio`). Side by side / top and bottom: the overlay fills one half
  (cover + pan), and the MIDDLE of the main picture (unscaled, a half-size
  window) moves to the other half — the main clip's own pan/crop decide
  what is in that middle. PiP: margin 3 % of the short side, frame 0.6 %
  (min 2 px), drawn outside the box.
- **Export** (`ffmpeg_command.dart`): `framingFilters` (transpose / hflip /
  vflip / even-sized expression crop) right after the frame-rate step of
  each main chain (runs only join pieces with the same framing); pan adds
  `:x=(iw-ow)*k:y=(ih-oh)*k` to the Fill / Zoom / Blur crops — a default
  clip produces the identical graph as 1.5. `buildOverlayChains`: one input
  per overlay item, chain fps → framing → `scale…increase:out_range=tv` →
  crop to box (pan) → optional white `pad` → `format=yuva420p` → tpad/trim to
  its frames → alpha `fade`s → `setpts=…+start/TB` → `overlay=x:y:
  eof_action=pass:repeatlast=0:enable=gte(t,a)*lt(t,b)` onto `[vcat]`
  (split layouts first `split`/`crop`/`overlay` the main middle); titles
  are drawn on the result. Overlay sound: `OverlayClip.sound` as an
  implicit "overlay" speech track in `buildSoundTrackMix` at the video
  sound's level (mute/solo of "Video" apply; it ducks music like speech).
  Items past the end are dropped / cut. Verified with FFmpeg 6.1 by pixel
  colour sampling (`test/media/crop_overlay_integration_test.dart`).
- **Preview**: `_ClipLayer._canvas` now lays the player surface out at the
  clip's native size, `RotatedBox` + `Transform.flip`, positioned at
  `placeClip(...).fullPicture(crop)` and clipped to the visible box (blur
  backdrop: cover of the cropped picture). `_MainRegion` wraps the main
  layer (same tree always, so surfaces never move) and shifts it for split
  layouts. `_OverlayLayer` draws the overlay (fades = opacity, border,
  selection frame, drag to move → becomes "free", corner grip → size).
  `PlaybackController` has up to 2 overlay players ("overlay decks";
  `PlayerBackend` may now be asked for 4 video players; the media_kit pool
  lends them): the item under the playhead plays on the timeline clock
  (speed as rate, volume × fades × video sound level), the next one is
  loaded paused 1.5 s ahead (adjacent camera-angle items cut without a
  load), paused scrubbing seeks it, a player > 150 ms off is re-seeked (at
  most every 2 s). Photos need no player.
- **Crop UI** (`lib/ui/editor/picture_tools.dart`): `CropPanel` (shape
  pills Free/Original/16:9/9:16/1:1/4:5 — a shape is held while dragging,
  `EditorSession.cropRatio`; Rotate left/right, Flip sideways/upside down,
  Position sliders, Reset). While a CropPanel is mounted it sets
  `EditorSession.cropTarget`: the preview shows the whole turned picture
  (14 px inset so edge handles are reachable) with `CropFrame` (dimmed
  outside, thirds, 8 grips + drag inside; one undo step per drag via
  `LiveEdit`); titles hide, an overlay hides while a main clip is cropped.
  Desktop: "Crop" section in the side panel (clip and overlay). Phones:
  clip → More → **Crop and position**, overlay → tool bar Crop; both open a
  NON-modal Scaffold bottom sheet so the preview stays draggable (a modal
  sheet would block it). Phone clip tool bar unchanged (8 buttons would
  scroll).
- **Overlay UI**: Add → **Overlay** (desktop panel; phones "+" sheet
  "Overlay (picture-in-picture)"), PiP bottom right 33 % at the playhead.
  Timeline row above the main track, shown only when the project has
  overlays (keeps the 1.5 geometry otherwise; header "Overlay" in the
  1.5 header column); drag to move, handles to trim. Inspector sections
  Layout / Crop / "Sound, speed and fades" (phones: tool bar buttons +
  sheets). `ItemKind.overlay`; Delete key / menu delete it.
- **Menus**: Edit > Crop and position… / Rotate right / Add overlay video or
  photo… (macOS and Windows/Linux bars; `EditorMenuActions.canCrop`,
  `canAddOverlay`).
- **History** labels (`edit_labels.dart`): "Rotated clip 2", "Flipped …",
  "Crop on …", "Position on …", "Crop and position reset on …", "Added
  overlay", "Moved overlay", "Trimmed overlay", "Overlay Side by side",
  "Overlay size 50%", "Muted overlay", "Rotated overlay", etc.
- **Storage**: missing-media check, unused-media clean-up and project
  bundles include overlay files; `relinkMedia` relinks them.
- **MCP**: `set_clip_properties` `crop_shape`, `crop_x/y/width/height`,
  `rotation` (absolute), `flip_horizontal/vertical`, `position_x/y`;
  `add_overlay`, `update_overlay`, `remove_overlay` (same framing args);
  `get_project` lists `overlays` (text + JSON). 35 tools.
- Help: `crop-position`, `overlay` (44 articles); `look`, `fit-fill-blur`,
  `shape` point to them.
- **Not built / future**: camera-angle sync by sound (line up a second
  camera automatically by cross-correlating the two sound tracks — the
  natural next step for multi-camera podcasts; today the user places it by
  eye), rounded corners on PiP (needs an alpha mask; only a square white
  frame now), "Separate sound" for overlay items, sound clean-up / voice
  focus / look on overlays, more than one overlay row, overlays that follow
  main-track edits, Ken Burns (animated zoom/pan), free rotation angles.
- **Unverified**: overlay players on real Android/Windows/macOS libmpv (4
  decoders at once on a phone — the pool and hwdec may struggle; the
  overlay deck simply shows nothing until loaded), preview/export match by
  eye on real footage (only geometry unit tests + FFmpeg pixel sampling),
  overlay sync by eye, crop handles with a real finger, FFmpeg 8 for the
  overlay graph (CI runs 8.0). The Linux e2e (step 7d2) checks with the
  real mpv players: crop gives bars, full / PiP / side-by-side overlay
  colours in the right places, 100 % of pictures blue while a full overlay
  plays and red after it; it sets crop and overlays through the editor, not
  by dragging handles.

## Fades, filters, text styles, snapping, sound-only export (1.7.0, 17 Nov 2026)

Built from a read-only audit of 1.5.0 (CapCut comparison). Everything is
additive in the model (schema still 2; defaults change nothing, so a 1.6
project loads and exports exactly as before — the export graph of a
project without the new settings is byte-identical, the old command tests
prove it).

- **Model** (`project.dart`): `Clip.fadeInMs/fadeOutMs` (picture from/to
  black + the clip's own sound), `Clip.filter` (`LookFilter`
  none/warm/cool/blackWhite/vintage/vivid), `Clip.warmth` (-1..1),
  `Clip.frameRate` (probe data, 0 = unknown); `Project.fadeInMs/fadeOutMs`
  (whole video incl. titles/overlays/all sound; `projectFades` caps each at
  half the video; `fadeGainAt`); `TitleOverlay.font` (`TitleFont`
  classic/modern/elegant/handwritten), `outline` + `outlineColorArgb`,
  `shadow` (default true = old behaviour), `align`, `animIn`/`animOut`
  (`TitleAnimation` none/fade/slideUp/pop). Overlay items keep their own
  fades (`OverlayClip.fromJson` zeroes the clip ones, the JSON keys are
  shared).
- **Fonts**: Rubik (modern), Bona Nova (elegant serif), Amatic SC
  (handwritten), Regular + Bold, SIL OFL 1.1, all with Latin + Cyrillic +
  Hebrew (checked with fontTools: 64/64 Cyrillic, 27/27 Hebrew letters).
  Static TTFs from the `@expo-google-fonts/*` npm packages (Google Fonts
  builds), licence texts from `@fontsource/*` (`assets/fonts/*-OFL.txt`).
  ~1.5 MB. Width tables for line wrapping:
  `lib/core/model/title_font_metrics.dart`, generated by
  `docs/tools/title_font_metrics.py` (part of title_layout.dart).
  `FontPaths.files` + `pathFor(font, bold)`; a missing file falls back to
  DejaVu. `media_fonts.dart` unpacks all eight; the MCP looks for them next
  to DejaVu (CI macOS copies `assets/fonts/*.ttf` + licences). Preview:
  one Flutter family per file (`titleFontFamily`).
- **Export** (`ffmpeg_command.dart`): clip fades = frame-exact
  `fade=t=in:s=0:n=F` / `fade=t=out` on the clip's n frames (before the
  transition split) + sample-exact `afade ss/ns`; clips with fades never
  join a run. Project fades on the finished picture `[vfade]` and sound
  `[afade]`. Colour look = ONE RGB matrix (`core/model/look_filter.dart`,
  filter then warmth) after `eq`: `format=gbrap,colorchannelmixer=…
  (offsets in the alpha column, alpha is opaque),scale=out_range=tv,
  format=yuv420p` — bars stay black. Titles: `buildTitleDraws` (split out
  of buildExportCommand): font file, `borderw/bordercolor` outline
  (`titleOutlinePx` = 6 % of the font size), shadow only when on and no
  box, alignment (lines against the block's estimated left/right edge),
  animations as ffmpeg expressions of `t` (`titleAnimationExpr`, the same
  curves as `titleAnimationAt`: per-frame `alpha`, `fontsize` and `y`; a
  verified drawtext feature on 6.1). An animated BOXED title draws its box
  with drawtext's own box around an invisible space (`boxw/boxh`, FFmpeg
  6.1+) because drawbox cannot fade; the box takes opacity and move but not
  the pop size (preview does the same). Sound only (`ExportFormat` m4a/mp3):
  same sound graph, no picture inputs (`-vn`, silent clips/photos get no
  input), no overlays/titles, AAC 192k `-f ipod` or `libmp3lame` 192k.
  `ExportOptions.frameRateChoices` 24/25/30/60 + `sameAsSourceFps`
  (highest clip fps rounded, ≤ 60). libmp3lame is in the shipped FFmpegKit
  builds (Android arm64 `--enable-libmp3lame`, Windows `libmp3lame-0.dll`,
  macOS libavcodec strings checked); the Process engine checks
  `-encoders` and says "Export the sound as M4A instead" without it (MCP
  with a system ffmpeg). No hardware encoder or output check for sound only.
- **Preview**: clip fades = an always-present `Opacity` around each clip
  layer (black canvas below); project fades = `_ProjectFadeLayer` (black
  over everything, under the crop layer); sound gains multiply fades in
  `PlaybackController` (`_fadeAt`: clip decks, processed sound players,
  sound tracks and overlays get the project fade). Colour look composed
  into the existing `ColorFilter.matrix` (`clipColorMatrix`). Titles:
  `titleAnimationAt` (opacity/move for the block, scale for the text
  only), outline = stroke text (2× width) under the fill text, alignment
  via `OverflowBox` alignment + box padding.
  **Known differences, documented in the help:** the export clips after
  eq and again after the matrix, the preview applies both at once (extreme
  highlights/shadows can differ slightly); the export's RGB step uses the
  BT.601 matrix both ways (HD colours may shift by 1-2/255); HarfBuzz
  kerning in FFmpeg ≥ 6.1 can make a line a few pixels narrower than the
  preview; drawtext's outline is not scaled during a pop (preview's is).
- **Editor** (`ProjectEditor`): `setClipFades`, `setProjectFades`,
  `setClipFilter`, `setClipWarmth`, `resetLook` ("Reset look on clip N"),
  `duplicateClip` (right after; a clip with separated sound gets its own
  linked sound via syncLinkedSound), `duplicateTitle` (right after on the
  timeline), `ClipSettings` + `pasteClipSettings` (look incl.
  filter/warmth, fit/zoom, framing, and video→video speed + sound; never
  trim, transition, fades; a clip whose sound is separated stays muted),
  `moveSoundTrack` (track menu Move up / Move down; implements the
  previously unused "Moved sound track" label). **Probe data is not an
  undo step**: `setClipAudioStreams`, `setAudioStreams`, `setProbeData`
  (audioStreams / hasAudio / frameRate by FILE path) go through
  `_editQuietly`, which rewrites the current state and every undo/redo
  snapshot (and a running transaction's start) like `rename` does.
  `applyClipSettingsToAll` names its step ("Look of clip 1 applied to all
  clips"). Labels: photo split ("Split photo 2"), fades, filter, warmth,
  title font/animation/alignment/outline/shadow, sound clip "Read sound
  tracks of music", project fades.
- **Snapping** (`core/editor/snapping.dart`): targets = 0, end, playhead,
  every clip edge, title/caption, sound and overlay start/end (minus the
  dragged item), computed at drag start; 10 px; trim handles and body
  moves (snapSpan: whichever edge is nearer). `EditorSession.snapping`
  (app pref flag `snappingOff`, `AppPrefs.clearFlag` added) and
  `snapLine` (yellow line painted over the timeline). Alt / Option held =
  no snap for that drag. Main-track clips are reordered, not placed, so
  only their trim handles snap.
- **Keyboard** (`editor_screen.dart` `_onKey`; the editor handles every key
  itself, menus only show them): J (backwards = playhead steps back
  120 ms every 120 ms — media players cannot play backwards smoothly), K
  stop, L play; I / O trim the selected clip (else the one under the
  playhead) to start / end at the playhead (labelled transaction);
  Ctrl/Cmd+D duplicate; Ctrl/Cmd+Shift+C / V copy / paste settings
  (`EditorSession.copiedSettings`, per editor); + (=, numpad +) / -
  timeline zoom; arrows = `frameStepFor` (1000 / source fps / speed; 33 ms
  when unknown, e.g. clips added before 1.7).
- **Menus** (`app_menu.dart`): `EditorMenuExtra` (null action = greyed;
  its `state` list decides when the bars rebuild). File: Add media / music,
  Import / Export subtitles, Rename project. Edit: Duplicate, Copy / Paste
  settings, Delete (macOS shows ⌫; Windows "Delete (or Backspace)"), Split,
  Start / End clip at playhead, Freeze frame, Remove silences, Move clip
  earlier / later, crop, rotate, Add title / caption / overlay, submenus
  Sound (Add sound track, Separate sound, Put sound back, Lower music
  under speech ✓), Shape, Video size. Playback: Play (Space shown on
  macOS too), Play backwards / Stop / Play forwards, Go to start / end,
  Previous / Next frame, Zoom in / out, Snap to playhead and edges ✓.
  Help: Keyboard shortcuts. Redo shows Ctrl+Shift+Z on Windows/Linux like
  Cmd+Shift+Z on the Mac (Ctrl+Y still works; help says both). Help is F1
  on Windows/Linux, Cmd+? on macOS (both in the help). Double firing: on
  macOS the key goes to Flutter first and the menu only gets keys nobody
  handled; on Windows/Linux the bar's shortcuts are display-only except
  Ctrl+E / Ctrl+Shift+H / F1 / Ctrl+N / Ctrl+O / Ctrl+Q, which nothing
  else handles. Plain-letter key equivalents in the macOS menu are
  **unverified on a real Mac**.
- **UI**: Look panel Filter pills + Warmth slider; "Transition and fades"
  (was "Transition") with per-clip fade sliders (first clip: "use Fade
  in"); Project panel (nothing selected) / phones More > "Fade in and out":
  project fades; title panel: Style, Font, Outline, Shadow, Position,
  Left / Centre / Right, Appear / Disappear; desktop tool bar Duplicate for
  clips and titles, phones clip More > Duplicate / Copy settings / Paste
  settings; Export window "Make" (Video / Sound M4A / Sound MP3), "Frames
  per second" (As clips / 24 / 25 / 30 / 60; replaces the 60 fps switch,
  default stays 30), phones get "Send to another app" for a sound file (the
  gallery takes videos only). Phone bottom sheets are capped at 75 % of
  the screen height (long title panel; the preview stays visible).
- **MCP** (42 tools): set_project_settings `fade_in_ms/fade_out_ms`;
  set_clip_properties `fade_in_ms/fade_out_ms/filter/warmth`; add_title /
  update_title `style/font/outline/outline_color/shadow/align/position/
  animation_in/animation_out`; new `duplicate_clip`, `copy_clip_settings`,
  `apply_to_all`, `freeze_frame` (PNG in `<projects>/<id>/media/`),
  `move_sound_track`, `undo`, `redo`; export_video `format` + `fps`.
  **Undo/redo decision:** the app's history is in memory only (per open
  editor) and the MCP builds a fresh ProjectEditor per call, so the server
  keeps its OWN stack of the edits it saved (per project, while the server
  runs); it refuses (and clears it) when project.json no longer matches
  what it saved (edited in the app). A persistent per-project history was
  not built (the app would have to share it; not simple).
- Help (51 articles): new `fades`, `filters`, `text-styles`,
  `duplicate-copy`, `snapping`, `export-options`, `menus`;
  `keyboard-shortcuts` complete; `undo-and-saving` says renaming cannot be
  undone; `volume-and-mute` "Apply to all clips" wording fixed.
- Tests: `test/core/v17_test.dart`, `test/media/v17_command_test.dart`,
  `test/media/v17_integration_test.dart` (real FFmpeg 6.1: fades by pixel
  luma and sound level, every filter against the preview matrix within
  8/255, fonts/outline/alignment/animations/animated box by pixels, M4A,
  MP3, 24/25/60 fps frame counts), `test/mcp/tools_v17_test.dart`,
  `test/ui/v17_ui_test.dart`; e2e step 7d3 (filter, clip fade, project
  fade, styled title with the real players).
- **Not built / open**: real reverse playback; L pressed twice for faster
  play; snapping of main-track clip moves (they reorder); duplicate for
  overlays and sounds; a font picker preview in each font; per-title
  animation length; filters on overlay items; preview of ducking.
- **Unverified**: everything on real Mac/Windows/Android (menus with plain
  key equivalents on macOS, fonts on phones), MP3 export through FFmpegKit
  (only checked that lame is linked), the animated-box drawtext path on
  FFmpeg 8 (CI runs 8.0), sound-only export on a phone (share sheet).

## Missing files, signing, phone speed, music (1.8.0, 17 Nov 2026)

Owner feedback from a Samsung phone (1.6.0 build): "Missing ·
20261116_205955.mp4" with Find file, a bit sluggish, wants a button to match
music to the video, free music search inside the app, and a feature log.

### Missing files on Android — root cause and fix
- **Cause.** The file picker (file_picker 13.3.3 → android_file_picker
  2.1.6) copies EVERY picked file to `<cache>/file_picker/<uuid>/<name>` and
  returns the path with links resolved (`File.canonicalFile`):
  `/data/data/com.ekcut.clipforge/cache/...`. `getTemporaryDirectory()`
  answers `/data/user/0/com.ekcut.clipforge/cache` — a symbolic link to the
  same folder. 1.7's `_keep` compared the two with `p.isWithin` (strings),
  which never matched, so the "move it to permanent storage" step never ran
  and every project pointed INTO THE CACHE folder, which Android (and
  Samsung's Device care / storage optimisation) empties whenever it likes.
  The name in the message is the original camera name (kept by the picker
  in its uuid folder), which matches what the owner saw. The help even
  promised "ClipForge keeps its own copy" — it did not. (Not verified on
  the device: no phone here; the path forms are from the plugin source and
  path_provider; the link /data/user/0 → /data/data is standard Android.)
- Other routes checked: no share/VIEW intents on Android (manifest has
  none); drag and drop is desktop only (MainActivity removes the plugin's
  listener); project bundles unpack into `<media>/<id>/` (fine); freeze
  frames go to the media folder (fine); clean-up (`media_cleanup.dart`)
  only deletes files no SAVED project uses and runs on the home screen
  (once per run, after deleting the tour sample) — it could not cause this.
  It still had a hole: the undo history of an open editor (it runs while no
  editor is open today, so in practice not hit). Uninstalling (needed for
  every new debug-signed APK) deletes projects AND media, so it gives "no
  projects", not "missing".
- **Fix** (`lib/core/storage/media_import.dart`, pure, tested):
  `isWithinDir` compares real paths; `keepMediaCopy` puts every outside
  file in `<media>/imported/<fingerprint>/<original name>` — fingerprint =
  FNV-1a 64 of size + first + last 256 KB, so the same recording is stored
  once (also across projects); the picker's cache copy is MOVED (rename,
  no extra space); other paths are copied via `.part`; when the copy would
  leave < 300 MB free the file is used in place with a warning; copies
  ≥ 1 GB say so. `PlatformFileService.keepPickedFile` does this on Android
  for every pick (media, music, Find file). Opening a project
  (`mediaRescueProvider` in `editor_screen._load`) moves files of pre-1.8
  projects that are still in the cache and saves the project.
- **Clean-up:** `removeUnreferencedMedia(keep:)`; `LiveMedia`
  (`liveMediaProvider`) collects what open editors use including every
  undo/redo state (`ProjectEditor.mediaPathsInHistory`). Reused copies get
  a fresh mtime so the 10-minute grace covers them until saved.
- **Find file** on Android asks "Search the gallery" / "Choose it myself…":
  MediaStore query by DISPLAY_NAME (channel `clipforge/gallery` in
  MainActivity; asks READ_MEDIA_VIDEO/IMAGES/AUDIO, READ_EXTERNAL_STORAGE
  ≤ Android 12; Android 14 partial access counts), list with folder / size
  / date, the chosen one is streamed to the cache and kept like a pick.
  `missingFileName` strips the old `<time>_` prefix. Unverified on a device.
- **Release manifest had no INTERNET permission** (only debug/profile
  had it); added for the music search.

### Stable Android signing
- The ClipForge release key (PKCS12, alias `clipforge`, RSA 4096,
  CN=ClipForge, valid 30 years to 2056) is NOT in the repository. It lives
  in the repository secrets `ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
  (the owner keeps a backup of the file). Certificate SHA-256
  `2F:36:DB:D0:DA:E6:7C:DE:38:D2:BB:7C:EA:0C:04:D8:50:FD:44:33:69:3D:20:96:09:F7:97:DF:4F:23:65:5B`.
  `build.gradle.kts`: key.properties (CI writes it from the secrets) signs
  release builds; without it a release build uses the debug key. CI
  requires the certificate above with apksigner when the secrets are set
  and only warns (debug key, not for release) when they are not.
- **Owner must uninstall once** (1.7 → 1.8: debug key → this key). Before:
  on the project list, three dots → **Share project file** for each project
  (send it to the computer / a drive / Files), uninstall, install 1.8,
  **Open project file** for each. After that every build installs over the
  last one. Help `android-install` and README say this.

### Phone performance
Read through: the preview's picture layer (`_buildScene`), the titles layer
(`layoutTitleBlock` for every title, every frame), the project-fade layer
and the split-screen region all rebuilt on EVERY playhead change (60/s);
the timeline already only repaints the playhead; players are created
lazily (2 main, ≤ 2 overlay, sound players on demand); autosave is debounced
800 ms. Changed (no visible behaviour change):
- `SelectBuilder` (widgets.dart): the builder runs again only when a
  selected key changes (or the parent / an inherited widget did); the key
  is read when the frame is BUILT, not when the playhead notifies — the
  first version read it at notify time and the Linux e2e caught a paused
  crossfade drawn stale (a seek loads the outgoing player right after the
  position notification). Unchanged key = the same widget instance is
  returned, so Flutter skips the subtree.
  Scene key = layers, transition progress, clip fades, crop target; titles
  key = visible titles + time only while one animates; project fade =
  gain in 1/1000. Measured in `v18_ui_test` (120 playhead moves inside a
  photo, title on screen before): titles layer 0 builds, picture layer 0
  builds (before: 120 each).
- **Smooth preview** (phones, More sheet, on by default, pref
  `smoothPreviewOff`): mpv `vd-lavc-skiploopfilter=all` + `vd-lavc-fast=yes`
  on the video players — helps only software decoding (hwdec refused, several
  decoders at once); exports untouched. Decode resolution can not be capped
  on Android (media_kit's VideoController width/height are ignored there).
- Not done: frame build times on a real phone; releasing idle sound
  players.

### Fit music to video and loops
- `AudioClip.loopMs` (> 0 = the trimmed range repeats to fill that much
  timeline; `durationMs` = loopMs), `loopPieces` (repeats overlapping by
  `kLoopCrossfadeMs` 300 ms, at most a quarter pass, ids `<id>~loop<k>`,
  linear fade-out/in at each overlap). Export: the track's clips are the
  pieces (amix sums the overlap = cross-fade), processed sound shared.
  Preview: `_trackClips` holds the pieces; during an overlap both pieces
  play (2 players). Timeline: repeat icon, "· loops", thin lines at the
  repeats; end handle changes loopMs, start handle keeps the end.
- `ProjectEditor.fitMusicToVideo(id, loop:)` → `FitMusicResult` (fitted /
  looped / stoppedAtNext / tooShort / alreadyFits / startsAfterVideo); 2 s
  fade-out; one step "Fitted music to the video" / "Looped music to fit the
  video"; `stopLoop` ("Music no longer loops"). Music panel button + Stop
  looping; Edit > Sound > Fit music to video; MCP `fit_music_to_video`
  (refuses too-short without `loop: true`). Real FFmpeg test: no level dip
  at the repeats (`test/media/v18_test.dart`).

### Free music search (Openverse)
- `lib/core/music/openverse.dart` (pure): `GET
  https://api.openverse.org/v1/audio/?q=…&license=cc0,pdm,by,by-sa
  &page_size=20&page=N&mature=false`, no key (anonymous use is rate-limited;
  429 → "busy"), User-Agent `ClipForge/<version> (personal video editor)`.
  Results re-filtered by licence on our side; mature dropped. Toggle "Also
  show music with stricter licences" adds by-nc, by-nc-sa, by-nd, by-nc-nd.
  Decision: NC excluded by default (a monetised post may count as
  commercial), ND excluded (music under a video is an adaptation);
  sampling licences never shown.
- **Not verified live**: this container cannot reach api.openverse.org
  (proxy 403/DNS). Written against the documented v1 format, tested with a
  recorded-style fixture `test/core/fixtures/openverse_audio.json`. Check
  the first real search on a device; if fields differ, adjust
  `MusicResult.fromJson`.
- Terms: Openverse is a search index; licences are asserted by the source
  sites (Jamendo, Freesound, Wikimedia, ccMixter…), not verified by
  Openverse or us. The credit stores the source page so the owner can
  check. Openverse asks API users to identify themselves (UA) and keep to
  light use; registering an app for a key raises limits (not needed now).
- UI: "Add music" window (dialog on computers, full screen on phones) with
  **My files** and **Find free music** (opens on the search). Results: title,
  artist, length, licence, ▶ (streams the URL in a separate media_kit
  player), **Use** → download to `<media>/music/<id>/<title - artist>.<ext>`
  (`.part`, reused when there) → added like a picked file with
  `AudioClip.credit` (`MusicCredit`: title, creator, licence + version + URL,
  source page, provider, attribution). Music panel **Credits**: short line,
  **Copy credits** (all music, with links), **Add credits at the end**
  (boxed small title over the last 4 s, "Added music credits"); Edit >
  Sound > Copy music credits. Offline: "No connection…", My files still
  works. Credits survive in the JSON (`credit` key) and in project bundles.
- **Jamendo** directly: skipped — its API needs a client_id (registration);
  Openverse already indexes much of Jamendo.

### CI FFmpeg crash in the animated-title test (exit code -11)
- CI's `ubuntu-latest` + apt ffmpeg crashed in
  `v17_integration_test` "animations: fade, pop, slide up and an animated
  box"; the same test passes here on FFmpeg 6.1.1 (20/20 runs of each of
  the four graphs, and valgrind memcheck clean). This handover said "CI
  runs 8.0", i.e. the runner image has moved to a newer Ubuntu — the
  workflow now prints `ffmpeg -version` so the log says which. I could not
  run another FFmpeg here (no download of binaries allowed), so the exact
  crashing construct is NOT confirmed. The 1.7 graph used two drawtext
  features that only arrived in 6.1 and are rarely used: a per-frame
  `fontsize` EXPRESSION (pop) — every frame re-sizes the face and drops the
  glyph cache under HarfBuzz shaping — and a box drawn by drawtext around a
  single SPACE with `boxw/boxh` + expression alpha (animated box). Both are
  gone: the animated box is a `color` source (`black@0.55`, layout size) →
  `format=yuva420p` → `fade … alpha=1` (in/out, the preview's linear curves;
  pop over a third) → `overlay` with `y` as the move expression, enabled for
  the title's time; a pop is one drawtext PER OUTPUT FRAME of the pop with a
  fixed size, opacity and place from `titleAnimationAt` (the preview's own
  function), enabled for that frame only; the rest of the title is one
  drawtext with alpha / y expressions (as before, common features).
  Fade and slide titles keep their expression draw. The integration test
  checks a half-faded box at 200 ms and a slide-up + pop-out two-line box
  title. If CI still crashes, the remaining suspects are the alpha/y
  expressions of drawtext on that FFmpeg (look at the printed version).

### Feature log
`docs/FEATURES.md`: every feature by area with its version, plus Planned.
`test/core/features_log_test.dart` fails when CHANGELOG has a version the
log does not mention.

### Not verified (1.8.0)
Everything on a real phone: the cache-path cause on the owner's Samsung,
the move out of the cache, gallery search and its permission prompt, Smooth
preview's effect, streaming previews and downloads from Openverse, the
loop's sound on real music, the new signing key installing over itself
(APK signature checked with apksigner here).

## Claude control after the owner's long test (1.9.0, 17 Nov 2026)

The owner ran a 27-step test of clipforge-mcp with Claude Code on Windows
(against 1.4/1.5; 26 passed). What was already fixed by 1.8 when this was
re-checked: `video_size` (1.5), adaptive silence threshold (1.5), fade from
black (1.7), fit music to video (1.8), and the export already moved music's
fade-out to the video's end (`Project.audibleEndMs`, 1.2). Built now:

- **Exports are jobs** (`lib/mcp/export_jobs.dart`). Cause of the failure:
  the MCP TypeScript SDK gives up on a request after ~60 s ("Request timed
  out"), Claude Code then restarted the server, and our own shutdown
  (`ToolCall._abandon` → `job.cancel`) killed FFmpeg. Now `export_video`
  writes `<ClipForge>/claude-jobs/<id>.json` (+ `<id>.project.json`, a
  snapshot of the project) and starts `clipforge-mcp --export-job <file>`
  (`separateProcessLauncher`: detached on macOS/Linux; on Windows a normal
  child, so it shares the server's hidden console and FFmpeg pops no window
  — Windows does not kill children with their parent). The worker
  (`runExportJob`) renders to `<name>.<id8>.part.<ext>` (extension kept so
  FFmpeg picks the container), writes progress + heartbeat every second,
  watches `<id>.cancel`, renames when done, probes, stores size / length /
  encoder / measured speed. `export_video` waits `wait_seconds` (default 20,
  max 45) with MCP progress notifications, then returns the job;
  `get_export_status` (job_id, wait_seconds; no id = recent jobs) and
  `cancel_export`. A running job whose heartbeat is > 30 s old and whose
  process is gone reads as "lost". The client giving up on a call ends the
  WAIT only. Estimate up front: output megapixel-seconds / speed of the last
  export on this computer (default 2.7 MP·s/s), then progress-based ETA.
  Falls back to rendering inside the server if the process cannot start.
  Jobs older than 7 days are deleted when listed. 45 tools.
- **Short answers** (`lib/mcp/report.dart`, `_projectResult`): edits return
  counts, length, size and why (`canvasReason`), ids added/removed/changed
  (`projectChanges`), warnings, who saved last; `detail: "full"` adds the
  timeline. `get_project` pages: `clip_offset`/`clip_limit` (60, max 300),
  `title_offset`/`title_limit` (60), `from_ms`/`to_ms`. A 137-clip edit
  answer is < 6 KB (was ~90 KB). Test clients ask for `detail: "full"` by
  default (`Client.fullDetail`).
- **Who saved last**: the server writes `<project>/.claude-edit` (FNV hash
  of the project.json it wrote + tool); same hash = Claude, else the app.
- **"Open in the app" lock** (`lib/core/storage/project_lock.dart`): the
  editor writes `<project>/.open-in-app` (pid, host, app version, openedAt,
  heartbeatAt, token) on open, renews it every minute, deletes it on close /
  quit (only its own token). Stale = heartbeat > 3 min, or same host and the
  pid is gone (`/proc`, `tasklist`, `kill -0`). The home screen's media
  clean-up also removes stale locks (`removeStaleLocks`). MCP edit tools
  (also undo/redo, freeze_frame, remove_silences before analysing) refuse
  with a clear message; get_project shows `openInApp`; export works and
  notes that it uses the last saved state. Dry runs are allowed.
- **Warnings**: sound past the end of the video (every answer; says the
  export stops it there and moves its fade-out, or stops abruptly without
  one; points at fit_music_to_video); captions an edit made shorter than
  1.2 s. **Decision:** `min_caption_ms` default 0 (captions keep following
  their picture as in the app); the warning tells Claude to pass 1200; when
  given, shortened captions are lengthened up to the next caption / video
  end in the same save.
- **dry_run** on remove_silences (lists every cut: timeline position now,
  source range, length; total), set_clip_properties, apply_to_all,
  copy_clip_settings, separate_sound: runs the edit, saves nothing, no undo
  step.
- **Small export** result/description say whether the frame was scaled
  (short side 720) and that the bitrate is capped at 2500 kbit/s (CRF 27).
- **Ducking report** in the export result (`duckingReport`): per ducked
  track, how long it is heard, how long the video's sound / speech tracks /
  overlay sound play under it, stretches, the filter's nominal −9 dB
  (−3…−13). Honest: worked out from the timeline, not measured; music comes
  back up in pauses inside a clip.
- **SRT**: `export_srt time_base "source"` (`captionsToSourceTimes`; a cue
  across a removed part ≤ 2 s stays one cue), round-trips with import.
  Instead of a marker in the file (players choke on non-standard lines) the
  server remembers what it exported (`claude-jobs/srt-exports.json`: content
  hash, project, time base, `timelineKey`) and `import_srt` warns on a wrong
  time base or a file made for a different cut.
- **get_status** starts with version, program command, projects folder,
  title fonts, ffmpeg / ffprobe, jobs folder and running exports.

**App export of long projects** (checked, nothing to change): a 137-piece
project (8.3 s pieces of a 25:40 1280x720 25 fps 258 MB file, 60 captions,
19:02 output) builds ONE input (runs) and a 38.8 KB filter graph (goes
through a file); exported with the Process engine (FFmpeg 6.1, libx264 veryfast, 4 cores) in 146 s, 19:02.567 long, 313 MB, ffmpeg peak memory 250 MB, progress steady. The app never had the timeout problem (no
call limit); the risk was the MCP only.

**Whisper lead (for on-device transcription / filler words, not built):**
FFmpeg 8.0 added a `whisper` audio filter (needs `--enable-whisper` +
whisper.cpp). The bundled FFmpegKit 8.1.2 Android AAR
(`ffmpeg-kit-full-gpl-2.2.3.aar`, checked offline in the Gradle cache) is
configured without it (no `--enable-whisper`, no "whisper" string in
libavfilter.so). The Windows/macOS 8.1.2 builds are downloaded at build time
from github.com/sk3llo/ffmpeg_kit_flutter releases (same "full-gpl" recipe)
and could not be checked here; assume absent. The owner's winget FFmpeg has
it, so the MCP could transcribe with a system FFmpeg plus a downloaded
ggml model; the app would need sherpa-onnx / whisper.cpp itself (roadmap).

Tests: `test/mcp/tools_v19_test.dart` (fake slow engine: jobs, restart,
cancel, failure, lost; paging; locks; dry runs; warnings; SRT; ducking;
status), remove_silences dry run in `tools_media_test`, and the e2e test now
checks that an export survives the server stopping and that a new server
reports it finished.

Not verified: Windows behaviour of the worker process (console, whether
Claude Code ends it when Claude Code itself quits — a job object with
kill-on-close would), the lock on real Mac/Windows/Android (pid check via
`kill -0` / `tasklist`), Claude Code's handling of progress notifications
and of the shorter answers in a real session.

## Voice recorded separately, lined up by sound (1.10.0, 17 Nov 2026)

Owner: dropped a 23 min podcast video `video1406335665.mp4` plus a
separately recorded voice `audioSamTaylor21406335665.m4a` (a Zoom local
recording: one video + one sound file per participant). The sound landed on
the Music track; there was no way to say "this is the voice for this video"
and line it up.

**What the user sees.** Every sound file that is added (drop on the window
or timeline, Music > My files, a sound picked in Add media, Edit > Sound >
"Add voice recording…") gets ONE question per batch, "What is this sound?":
**Voice for the video** / **Music** / **Sound effect**
(`lib/ui/editor/voice_actions.dart`; a bottom sheet under 600 px wide, a
dialog otherwise). Music from the free music search is not asked about.
The guess (`guessSoundRole`, `guessBatchRole`): Voice when EVERY file of the
batch has voice / mic / audio / podcast / zoom / interview... as a word in its
name, or is Zoom's `audio<Name><digits>`, or is within 10 % of the length of
a video clip's file (5 s or longer); else Music. Voice is offered only when
the project has a video clip. With Voice: one name field per file (prefilled
by `speakerNameFromFile`: `audioSamTaylor2140…` -> "Sam Taylor", the
digit after the name is Zoom's participant counter; `mic - Anna.wav` ->
"Anna") and "Mute the camera's own sound" (on). Sound effect: an "Effects"
track (made when there is room, else the Music track with a message), no
fade-out. There is no "remember for this project" (not wanted).

**Lining up** (`lib/media/sound_align.dart`, pure Dart, shared with MCP;
`sound_align_job.dart` = the ffmpeg part, `SoundAlignEngine` on both
engines):
1. ffmpeg decodes each sound to 8 kHz mono s16 in a temp file
   (`aresample=8000:async=1:first_pts=0,highpass=120`, source timing kept
   like processed sound), read in chunks into an ENVELOPE: energy per 5 ms,
   4th root (level-independent), minus its own 1 s moving average (leaves
   the syllable rhythm). 40 min = 480 000 floats; the raw file (16 KB/s) is
   never in memory whole and is deleted. The last 4 envelopes are cached in
   memory (several speakers decode the video once).
2. Coarse: envelopes thinned to 20 ms, cross-correlated over ALL shifts by
   FFT (own radix-2), 6 best peaks kept (overlap of at least 10 s or half
   the shorter sound).
3. Fine, per peak: up to 7 windows of 30 s spread over the overlap (in each
   seventh the window with the most voice in it, so a speaker who is quiet
   most of the time still counts), Pearson correlation at 5 ms steps within
   +-600 ms, summed (weighted by how much the speaker talks), parabola to
   ~1 ms. Candidates are compared by score x sqrt(seconds compared).
4. Confidence 0..1 = f(score above a bar of 0.08 + 0.9/sqrt(seconds
   compared)) x f(best / runner-up above 1.15). `matched` from 0.5
   (`kAlignConfident`). Measured: same speech through a room 0.6..0.93,
   unrelated speech 0.1..0.3 with ratio ~1.0..1.3 -> confidence 0.
5. Drift: a line through the offsets of the trustworthy windows -> ms over
   the overlap; told to the user from 80 ms. **Decision:** drift is
   reported, NOT repaired (that needs stretching the voice); the offset is
   the best single one. Zoom local recordings share a clock (no drift);
   two separate devices typically differ 20-50 ppm (50-120 ms in 40 min).
Offset convention everywhere: **time in the voice file = time in the video
file + offset** (positive = the voice recording started earlier).
Timing here (4 cores, FFmpeg 6.1): a 25 min 1280x720 253 MB video + 25 min
m4a: **10.4 s** the first time (nearly all of it ffmpeg reading the two
sounds), 0.4 s for the comparison alone (second speaker, cached). Tests:
3 files of 20-40 s in 0.6 s.
Several video files in the project: the voice is compared with each (one
per file, with sound) and the best confidence wins.

**Link** (the 1.5 "separated sound follows its clip" mechanism, extended):
`AudioClip.syncOffsetMs` (null for everything else) + the existing
`sourceClipId` / `linked`. `mirrorClip` gives such an item the clip's part
shifted by the offset in ITS OWN file, same speed; where the voice file has
nothing (before its start / after its end) the item starts later / ends
earlier (silence), and a clip it has no sound for (< 100 ms) gets no item.
`syncLinkedSound` (called from `ProjectEditor._edit`, so every edit and MCP
tool, same undo step) now handles several linked sounds per clip and treats
a voice as belonging to the video FILE: every new clip of that file (a
piece from a split or Remove silences, a duplicate, the file added again)
gets its piece of every voice lined up with it and is muted like its
siblings. `buildVoice` (sound_tracks.dart) creates one item per clip of the
file. Editor API: `addVoice`, `linkVoice` (line up an existing sound /
again; replaces the whole group), `nudgeVoice` (+ = later; offset -=
delta; every item of the recording), `unlinkVoice`, `setVoiceClipsMuted`;
`voiceGroup` = same file, same track, clips of the same video file.
Moving / trimming one item by hand still unlinks that item (as for
separated sound). `isSeparated` now means "the clip's own sound" only;
`isVoice`, `belongsToClip` are new. History: "Added voice for clip 1, lined
up (+0.42 s)", "... (not lined up)", "Added 2 voices, lined up", "Lined up
voice with clip 1 (+0.42 s)", "Nudged voice 10 ms later", "Unlinked voice
from clip 1", "Muted the camera sound".
JSON: a voice writes `syncOffsetMs`, `voiceClipId`, `voiceLinked` and NO
`sourceClipId`, on purpose: 1.9 and older would take `sourceClipId` for a
sound of the clip's own file and swap the file on the next edit. They now
read a voice as plain music at its place (it just does not follow). Schema
stays 2.

**Tracks. Decision: the cap stays 3** (`ProjectEditor.maxSoundTracks`).
Each voice file gets its own speech track ("Voice", "Voice 2", or the
speaker's name): an empty speech track is reused (and renamed), else a new
one; when there is no room, a speech track on which every piece is free;
else it is refused with "There is no free sound track for this voice: a
project has at most 3 sound tracks, and voices that talk at the same time
cannot share one. Delete a sound track you do not need...". So with a
Music track two speakers fit. Raising the cap is cheap in the model and the
export (nothing counts on 3), but each track adds up to 2 preview players
and a timeline row, and several sound players at once are still unverified
on the shipped Android / Windows / macOS libmpv builds, so it was not
raised now. To raise: the constant, the help text "three sound tracks",
`sound_tracks_test` (uses the constant) and a look at the phone timeline
height.

**Not lined up** (confidence < 0.5, no camera sound, engine cannot): the
voice is still added LINKED, with offset = -clip.inMs (file start at the
start of the selected video clip / the one under the playhead / the
first), **the camera is left on** (so the two can be compared by ear) and
the message says "Could not line it up automatically — nudge it by hand".
The sound's panel (`VoicePanel`): what it is lined up with, nudge buttons
(100 ms, 10 ms, 1 frame of the clip's frame rate or 33 ms; earlier /
later), "Line up with the video again", "Unlink" (asks; the sound stays
where it is; a tick box "Switch the camera's own sound back on" when it is
muted), a "Mute the camera's own sound" switch. Plain music has "This is a
voice: line up with the video" (the owner's existing project): matched ->
asks "Mute the camera's own sound?" and moves it to a speech track; not
matched -> linked where it is now (so it follows and can be nudged).
A clip's Sound panel says "Voice from a separate recording (track)" with
"Show the voice". Menus: Edit > Sound > "Add voice recording…", "Line up
with the video" (both menu bars).

**Remove silences** (`lib/media/clip_silences.dart`, used by the dialog and
by MCP): for a clip with linked voice(s) it listens to the voice file(s)
(only the part the clip uses, shifted by the offset; voices on a muted /
non-solo track or at volume 0 are skipped) and to the camera only while
the clip is not muted. Silent = silent in ALL of them (the intersection of
the per-file silences, which is "the mix is silent" without mixing); where
a voice file has no sound it counts as silent. A clip without linked voice
behaves exactly as before. The sensitivity choice re-computes from every
file's levels. The dialog says "Listened to the voice recorded separately".
Gotcha found by a widget test: never `await subscription.cancel()` /
`controller.close()` of an already finished stream in code that widget
tests run (the future never completes under FakeAsync).

**Preview and export agree by construction**: a voice piece is an ordinary
`AudioClip` (start, in, out, speed) whose values `mirrorClip` computed; both
sides already handle those. Checked by export in
`voice_align_integration_test` (exported sound vs. expected: 15 ms / 3 ms at
speed 2; silence before a late voice and after a short one) and in the
Linux e2e (voice file time minus picture time in the real players).
**Preview lip sync** (`PlaybackController._onAudioPosition`, new): sound
track players only caught up once at the start (80 ms tolerance; fine for
music). A sound that FOLLOWS a clip (a linked voice, and also a linked
separated sound) is now kept on the picture's clock like processed clip
sound: smoothed voice-minus-picture difference, corrected by a seek when
more than 30 ms off right after a start, later 45 ms early / 80 ms late, at
most every 2 s (`voiceOffsetMs`, `voiceCorrections` for tests). Without it
the Linux e2e measured the voice 72 ms late, which would have misled
nudging by eye; with it -10 ms (1 correction). Music is not touched.
**Processed-sound cache**: nothing to add. The key is the sound FILE (path,
size, mtime) + sound settings + chain version; the processed file is the
whole voice file at its own timing, and the offset only decides which part
is read, so all pieces of a voice (and any nudge) share one file.
Clean up sound / Voice focus work on a voice item as on a separated sound
(`AudioClip.soundClip`).

**MCP** (47 tools): `add_voice` (path, clip_id, track_name, mute_clip true,
align true, offset_ms with align false, volume) -> `offset_ms`,
`confidence`, `drift_ms`, `lined_up`, `warnings`, `audioIds`, `trackId`,
`clipId`, `cameraMuted`; not matched = added at the clip's start, camera
on, a warning that tells Claude to use align_audio. `align_audio`
(audio_id, clip_id, offset_ms, nudge_ms, mute_clip, link false): line up an
existing sound (nothing changes when it does not match), set the offset,
nudge, unlink. `add_music` unchanged (description points to add_voice).
Sound items in get_project / edit answers: `role` (voice / music / effect:
`Project.soundRoleOf` = belongs to a clip or on a speech track -> voice;
track named "Effects…" -> effect; else music), `linked_clip`, `offset_ms`.
**Naming:** these three are snake_case as specified, next to the older
camelCase keys. `separatedFromClipId` is now only for separated sound;
`followsClip` is kept for both. `reattach_sound` on a voice explains what
to use instead. remove_silences targets clips with a linked voice even
when the camera has no sound, and names "(voice recorded separately)" in
the thresholds it reports. Guides: claude/CLAUDE.md, skill tools.md (47),
recipes.md "Podcast with a separate microphone / Zoom recording",
troubleshooting "The separately recorded voice is not in sync".

**Tests** (see the counts under "Building and testing"):
`test/media/sound_align_test.dart` (synthetic speech: + / - offsets,
between steps, noise + 26 dB quieter + duller microphone, one speaker's
microphone against a camera hearing two, a short file in a long video,
12 unrelated pairs, music vs speech, silence, drift 150 ms / 5 min, a
40 min pair under 8 s, names), `voice_align_integration_test.dart` (real
ffmpeg: camera through a room vs band-limited AAC microphones, +2150 found
as 2140, -2850 as -2861; unrelated / noise / no sound refused; export in
sync after trim + cut and at speed 2; late / short voice; Remove silences),
`test/core/voice_link_test.dart` (follow rule: trim, move, speed, split,
remove silences, transitions, several speakers, copies, undo; nudge,
unlink, relink; tracks; JSON), `test/ui/voice_ui_test.dart` (the question
on phone and desktop, a Zoom file end to end, music / effect / cancel, not
lined up + nudge buttons, the panel, music -> voice, two speakers and the
third refused, drift message, menu, Remove silences),
`test/mcp/tools_v110_test.dart`. Existing tests that add music now answer
the question. Screenshots `editor_{phone,desktop}_sound_question`,
`_voice_linked`, `_voice_panel` (looked at, both sizes).
Linux e2e (`real_app_test`, step 7i; passes): the question, the real
engine lines up a fixture pair (found 800 ms, true 800, 2.2 s for 14 s
files), linked on "Anna Lee", camera muted, follows a split, and the voice
player's file time minus the picture's time is the offset (790 vs 800 ms).
`flutter build linux --release` and `dart run bin/build_mcp.dart` build;
the built clipforge-mcp lists 47 tools.

**Limits / decisions worth knowing**
- A voice piece that an edit leaves without any sound of its file (the
  clip trimmed past the end of the voice file) is removed and does NOT come
  back when the clip is trimmed back in the same drag; Undo, or "Line up
  with the video again" (rebuilds every piece), brings it back.
- "Line up with the video again" / `linkVoice` rebuild the group: the items
  get new ids (MCP answers say so) and per-piece fades are reset.
- The batch guess is all-or-nothing: a drop of a song and a voice file
  together is asked once and defaults to Music.
- A mixed-rate drift cannot be repaired; a voice cut into parts cannot be
  lined up part by part.
- Envelope matching needs the camera to have heard the speech at all. A
  camera far from the speakers with loud music in the room may not match;
  then it is the nudge buttons.

**Not verified (1.10)**: with real speech and a real Zoom recording (all
fixtures are synthetic: noise bursts, echo, band-limiting, AAC); the
owner's actual 23 min pair; the confidence threshold on real rooms; drift
between two real devices; FFmpegKit on Android / Windows / macOS running
the decode (`-f s16le` to a file in the temp folder; only the Process
engine ran it) and its speed on a phone (a 25 min file's sound must be
read twice); the bottom sheet with a real phone keyboard; by ear / by eye
(lip sync) on any device; the preview correction above on real audio
devices (Linux e2e ran with a null audio output); several sound players (two voices + music) on
the shipped libmpv builds; Claude using add_voice in a real session.

## Speech to text, captions, fillers, shorts (1.11.0, 18 Nov 2026)

Goal: voice -> text with word times, so that (a) the app makes captions and
removes filler words and (b) Claude can read what is said, pick short clips,
cut and caption them.

**Owner decisions (do not reopen without asking):**
- Speech-to-text runs ON THE COMPUTER ONLY (Windows / macOS / Linux).
  Nothing about it shows on phones: no menu, no button, nothing greyed out
  (`speechServiceProvider` gives null on Android / iOS and every entry
  point is built only when `EditorSession.speech != null`).
- No "edit by text" editor. The Transcript column is read-only; Claude does
  the cutting through the MCP tools.
- No big files. Nothing is bundled, nothing downloads by itself; the app
  download keeps its size. Language packs are optional, per language, three
  sizes the user picks from, size shown first, a Remove button, total space
  shown. No pack is preselected. Large may be offered but never starts on
  its own. Claude must ask first (`download_pack`).
- "Remove filler words" is gentle by default (owner: too many cuts make
  the video jumpy, especially when the speaker moves): strengths, guard
  rails, a jump check, everything logged and restorable, Claude told not
  to overdo it.

### Where the code is
- `lib/core/transcript/` (pure): `transcript.dart` (model, estimated
  words, tidy), `transcript_store.dart`, `transcript_timeline.dart`
  (source -> timeline, speech sources, phrases, find), `captions.dart`,
  `fillers.dart`, `cut_plan.dart` (strengths, guard rails), `speech_edits.dart`
  (apply cuts, auto-cut log, put back, keep one part for shorts).
- `lib/media/transcribe/` (pure, dart:io): `transcription.dart` (backend
  interface, `ProcessHost`), `backends.dart`, `whisper_output.dart`
  (parsers), `speech_models.dart` (packs, `ModelStore`), `model_download.dart`,
  `transcription_service.dart`. `lib/media/jump_check.dart`.
- `lib/mcp/transcribe_jobs.dart`, `lib/mcp/tools_speech.dart` (a `part` of
  tools.dart).
- `lib/ui/speech/speech_service.dart` (the app's thin layer + provider),
  `lib/ui/editor/speech_actions.dart` (dialogs), `transcript_panel.dart`.

### Backends (pluggable: `TranscriptionBackend`)
1. `FfmpegWhisperBackend`: the SYSTEM ffmpeg's `whisper` filter (FFmpeg 8+,
   found with `ffmpeg -filters`; never the FFmpeg inside the app, which has
   no such filter). Options, from the FFmpeg filter documentation as
   remembered: `model=<ggml file>`, `language=auto|<code>`, `queue=20`
   (seconds gathered per recognition; the doc recommends large for
   accuracy), `use_gpu=true`, `destination=transcript.json`, `format=json`
   (one `{"start":ms,"end":ms,"text":"..."}` per line, text NOT escaped:
   the parser is tolerant), `vad_model=<file>` only when a
   `ggml-silero-*.bin` sits in the models folder. The run's working
   directory is a temp folder so `destination` needs no escaping; the model
   path goes through `escapeFilterPath`. It times PHRASES only -> word
   times are ESTIMATED (spread over the phrase by word length,
   `WordTiming.estimated`). It has no prompt option, so whisper drops
   nearly all "um"s (owner's real run: one "um" in 23 minutes).
2. `WhisperCliBackend`: a program on the PATH / usual folders (WinGet
   links, scoop, chocolatey, pip `Scripts` folders, Homebrew, ~/.local/bin)
   or a path in `speech-settings.json` (`programPath`). Tried in this
   order: `whisper-ctranslate2`, `faster-whisper-xxl`, `faster-whisper`,
   `whisper-cli`, `whisper-cpp`, `whisper`; the KIND is read from its
   `--help` (so a program merely called "whisper" is not used).
   - whisper.cpp: `-m <ggml> -f <16 kHz wav> -l <lang> -ml 1 -sow -oj -of
     <out> -pp --prompt <filler prompt>`: one word per entry = measured
     word times (token JSON `-ojf` is also parsed).
   - faster-whisper / OpenAI: `<file> --model <name> --output_dir <dir>
     --output_format json --word_timestamps True [--language] [--initial_prompt]`.
     They keep and fetch their OWN models; ClipForge looks in their usual
     caches (`~/.cache/whisper/<name>.pt`, the Hugging Face hub folder) and
     treats a missing one like a missing pack (consent first).
   - `PYTHONIOENCODING=utf-8` is set (Python on Windows otherwise fails
     printing Russian / Hebrew).
   - The filler prompt (`fillerPrompt`: "Um, uh, like, you know…", Russian
     and Hebrew versions) makes whisper keep hesitation sounds. Effect not
     measured.
3. **Built-in backend: not built, on purpose** (decision): it needs a
   native library (whisper.cpp via FFI or sherpa-onnx) in three desktop
   builds that cannot be built or tested in the cloud container. The seam
   is `TranscriptionBackend` + `TranscriptionService.backends`: one more
   class, registered first; packs, store, mapping, UI and tools stay.

"auto" picks a backend that can start with NO download first; among equals
whisper.cpp > faster-whisper > OpenAI > FFmpeg filter (measured word times
before estimated). GPU: FFmpeg runs with `use_gpu=true`; whisper.cpp falls
back by itself ("Unsupported GPU: …" on the owner's RTX 4070 laptop), and
if the run fails outright it is repeated once with `use_gpu=false`. The
transcript records `device` ("graphics card" / "processor" / '') from the
program's log (`deviceFromLog`, heuristics).
The sound for CLI programs is first written as 16 kHz mono WAV by the
system ffmpeg (`-map 0:a:<track>`); a Python program gets the file as it
is when there is no ffmpeg.

### Language packs (`speech_models.dart`)
Standard whisper.cpp ggml files into `<ClipForge>/models/`:

| | Small (~140 MB) | Medium (~470 MB) | Large (~1.6 GB) |
|---|---|---|---|
| English | base.en | small.en | large-v3-turbo |
| Russian, Hebrew, others, Automatic | base | small | large-v3-turbo |

"tiny" is not offered (too many mistakes). The all-languages files are
shared and also serve English (someone with `base` needs no `base.en`).
Quality "auto" = the largest installed pack that can do the language (the
dialog lets the user pick another). `models.json` in that folder overrides
/ adds table entries (url, sha256, size…) without a new build;
`speech-settings.json` holds `modelPath` ("Use a model file I have…"),
`programPath`, `ffmpegPath` (shared by app and MCP).
Download (`model_download.dart`): `.part` file, HTTP Range resume, 60 s
idle timeout, SHA-256 of the whole file, then rename. A wrong hash is kept
as `<file>.unverified` and NOT used (`ModelStore.acceptUnverified` exists;
the app does not show a "use anyway" button yet — the user can point at
the file with "Use a model file I have…").
**UNVERIFIED:** the URLs
(`huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-*.bin`) and the
approximate sizes; the build container cannot reach that host and no real
download was made. The built-in table carries NO SHA-256 values (they could
not be checked and a wrong one would reject a good file): a complete
download is accepted when it starts like a whisper.cpp model file
(`looksLikeWhisperModel`). To pin hashes later, read the "SHA256" on each
file's page and put them in the table (or `models.json`).

### Data
- One transcript per SOURCE FILE and audio stream:
  `<project>/transcripts/<fingerprint>_a<track>.json` (fingerprint =
  `mediaFingerprint`: size + first / last 256 KB, so a moved or relinked
  file keeps its transcript). Words `[text, startMs, endMs]` in source
  time, grouped in segments; language, requested language, model, quality,
  backend, wordTiming, device. Never in project.json. Asking again with
  the same settings is a cache hit (`Transcript.madeWith`).
  `FileProjectStore.duplicate` copies the folder (make_short relies on it).
  Project bundles (.clipforge.zip) do NOT carry transcripts yet.
- Source -> timeline (`timelineWords`): for every clip of the file,
  `timeline = clipStart + (source - in) / speed`, words whose middle is
  outside the trimmed part dropped. Nothing is stored on the timeline, so
  cuts, speed, reordering and Remove silences need no bookkeeping.
- Linked voices (1.10): `speechSourcesOf` gives the voice files of a clip
  instead of its own sound, with `time in voice file = clip time + offset`
  and the track's name as the speaker. The audio channel choice (left /
  right only) is ignored for transcription.
- `Project.autoCuts` (additive JSON key, only written when not empty):
  kind (filler / silence), file, source in / out removed, word, when, by
  (app / claude), jump score, smoothed.

### Captions (`captions.dart`)
1–2 lines, default 37 characters (UI slider 32–42), new caption at a
sentence end, a pause of 600 ms, a speaker change, a cut; a comma once two
thirds full; min 1 s, max 6 s, 200 ms linger, never overlapping; lines are
also checked against the real title layout (`captionLineFits`), so upright
video gets shorter lines and nothing is re-wrapped. Hesitation sounds are
left out. Style = the project's newest caption, else `CaptionDefaults`.
**Right-to-left (found while checking the title pipeline):** preview and
export both laid lines out with a left-to-right base direction, which put
a Hebrew line's closing full stop / question mark / number on the wrong
side. `bidiLine` (title_layout.dart) now wraps a line whose first strong
letter is Hebrew / Arabic in RIGHT-TO-LEFT MARKs (U+200F, zero width in
`estimateTextWidth`), used by `preview_view` and by the export's text
files. Checked by eye with FFmpeg 6.1 (libfribidi) in all eight font
files: correct order, no stray glyph. This changes every Hebrew title, not
only captions (for the better). FFmpeg 8 drawtext: unverified.

### Remove filler words: gentle (`cut_plan.dart`)

| | Light (default) | Normal | Strong |
|---|---|---|---|
| shortest cut (filler + its pause) | 350 ms | 200 ms | 80 ms |
| must stand alone between pauses | yes, 120 ms both sides | no | no |
| closest two cuts | 2.5 s | 1.5 s | 0.7 s |
| most cuts in any minute | 4 | 8 | no limit |
| shortest piece of clip left | 0.6 s | 0.6 s | 0.6 s |
| jumpy picture (score >= 0.5) | left in | left in | cut |
| slight change (score >= 0.2) | cut + 150 ms dissolve | same | same |

When cuts compete (too close, minute full) the LONGER one wins. A cut runs
from 40 ms after the previous word to 40 ms before the next, at most
150 ms beyond the filler. Fillers under another speaker's words are never
cut. Lists per language (`kDefaultFillers`): sounds (um, uh, er…; э-э, эм,
мм…; אה, אממ…) and filler WORDS that are also real words (like, you know;
ну, как бы, типа; כאילו) — the words are listed but never ticked /
cut unless asked. Comparison ignores case, punctuation, drawn-out letters.
**Jump check** (`jump_check.dart`): the frame 40 ms before the cut against
the frame 10 ms after it, 32x18 grey, fast seek, 8 cuts per ffmpeg run;
score = mean absolute difference / 25 grey levels. Under a full-frame
overlay: 0. **Smoothing decision:** the existing transition mechanism
takes 100 ms and up, so a slight jump gets a 150 ms crossfade on the piece
after the cut (picture dissolve; the sound crossfades with it). Estimated
word times (FFmpeg filter): nothing is ticked in the app, MCP refuses to
cut without `allow_estimated_times`.
**Put back** (`restoreAutoCut`): when the piece ending at the cut and the
next clip starting at its end are still neighbours, they become one clip
again (titles on the later piece are re-added, moved by the length that
returns); otherwise the removed part comes back as its own clip after the
last piece of that file before it. One undo step. Remove silences (app
and MCP) writes log entries too. The app's play button in the review list
plays the spot AS IT IS NOW (1.5 s before to 1.5 s after) — it does not
preview the cut applied (not built).

### App (computers)
Sound panel of a clip: **Transcribe speech…**, then **Captions from
speech…**, **Remove filler words…**, **Automatic cuts…**; Edit > Speech
(both menu bars) has the same plus Transcript; top bar Transcript button
(column 300 px; a dialog in a narrow window). The app's transcription
never downloads: packs only through the Download buttons.
Phones: silences cut there are logged, but there is no Automatic cuts
list.

### MCP (57 tools)
`transcribe` (job in `<ClipForge>/claude-jobs/transcribe/`, worker
`clipforge-mcp --transcribe-job <file>`, same heartbeat / cancel / lost
rules as exports), `get_transcribe_status`, `cancel_transcribe`,
`get_transcript` (text by default: `start-end [m:ss] Speaker: text`; 3500
words = 389 phrases ≈ 35 KB in one answer; `segments` / `words`, paging,
both time bases), `find_in_transcript`, `captions_from_transcript`,
`remove_fillers` (dry run default TRUE, strength light), `list_auto_cuts`,
`restore_cut`, `make_short` (duplicate -> `keepTimelineRange` -> shape ->
1080p -> captions). `get_status` has a `transcription` block (programs,
packs, what can be downloaded, running jobs). `remove_silences` gained
`max_cuts_per_minute`, reports cuts per minute, logs its cuts.

### For the owner (relay this)
- **Zero-install route:** any whisper program on the PATH, or the system
  FFmpeg with the whisper filter, is picked up automatically; with a
  language pack already in `Documents\ClipForge\models` (or a model file
  chosen with "Use a model file I have…") nothing is downloaded at all.
- **Day one on Windows:** (1) the winget FFmpeg they already have (8.x
  with the whisper filter) on the PATH; (2) one language pack — either
  click Download in **Transcribe speech…** (Small English ≈ 140 MB) or
  copy the `ggml-base.en.bin` they already used into
  `Documents\ClipForge\models\`; (3) for Claude: the 1.11 `clipforge-mcp`
  (extension) — same FFmpeg. For filler removal with exact word times and
  more "um"s found: install whisper.cpp (`whisper-cli.exe` on the PATH) or
  `pip install whisper-ctranslate2`; ClipForge then prefers it.
- **Claude Code can also run whisper itself** on a file, write an .srt and
  bring it in with `import_srt` (`time_base: "source"`), as the owner did
  in their test (539 captions placed correctly).

### From the owner's "Claude control test 3" report (1.9.0), same version
- **Fixed — app lock.** The `.open-in-app` mark could stay on the first
  project of a session. In widget tests the lifecycle was already right
  (new test `app_lock_test.dart`: A, list, B, list passes on the old code
  too), so the exact cause on Windows is NOT reproduced; the likely one is
  an editor whose `dispose` did not get as far as releasing the lock (the
  release sat after other clean-up). Now: the release is the FIRST thing in
  `dispose` and also happens in `_close` before the route pops, and
  `AppProjectLock.acquire` ends every other lock this app process holds
  (one editor at a time), heartbeat included. Why the 1.9 test missed it:
  it pumped one editor alone and replaced it with an empty widget; it
  never went back to the list or opened a second project. Note also that
  two projects were both called "T3 Podcast" in that test: Claude may have
  looked at the other one.
- **Verified — multi-mic.** `tools_v110_test`: one video + TWO linked
  speaker files, camera muted; remove_silences dry run and real cut
  picture and both voices together at unchanged offsets and listen to the
  speech tracks. New warning (`unlinkedSpeechWarning`) when unlinked sound
  on a speech track is left behind by a cut, pointing to add_voice /
  align_audio.
- **Done — names.** `FileProjectStore.freeName`: create / duplicate /
  make_short give "(2)", "(3)"… and say so; an ambiguous name lists ids,
  dates and lengths. (Renaming to a taken name in the app is not blocked.)
- **Done — estimates.** Speed remembered per kind (video on the graphics
  card / on the processor / sound only, by the encoder that really ran),
  titles / overlays / sound items counted in, a range in the answer, time
  left corrected from real progress as before. Sound-only default 20x.
- **Done — smaller answers.** Changed ids: 12 listed + counts; silence
  cuts once (structured), 8 in the text. **Not done:** the `media` table
  with short keys in get_project (clip paths are still repeated).
- **Done — wording.** "Nothing was changed" alone (notes kept); dry runs
  say "Would …"; History says "Lined up title" / "Outline on title"; the
  "small" note no longer claims x264 for a graphics card export; the
  subtitle "different cut" note is in `warnings`.
- **Not done:** old -> new values on single-clip edits, and the list of
  settings a dry run of apply_to_all / copy_clip_settings would change.
- **Already fine — align right.** `x` is the block's centre, but
  `layoutTitleBlock.place` clamps the block inside a 2 % margin, so x = 1
  means "against the right margin": the existing real-ffmpeg pixel test
  (`v17_integration_test`, "alignment holds") finds the text's right edge
  at 610–630 of 640; a layout assertion was added in
  `tools_v111_report_test`.

### Verified (here) / not verified
Runs on 18 Nov 2026 (Linux container, FFmpeg 6.1.1, no whisper filter):
`flutter analyze` clean; `flutter test` 1516 passed; Linux e2e passed
(step 7j: "20 words via whisper-cpp", 4 captions, jump to a phrase);
`flutter build linux --release` and `dart run bin/build_mcp.dart` built;
the built clipforge-mcp lists 57 tools and, with a shell script as
whisper-cli, ran a transcribe job in its separate worker process, then
get_transcript, make_short and a remove_fillers dry run (whose real jump
check left the filler in on a moving test picture). New tests:
`test/core/transcript_test.dart`, `cut_plan_test.dart`,
`test/media/transcribe_test.dart`, `model_download_test.dart`,
`jump_check_test.dart`, `test/mcp/tools_v111_test.dart`,
`tools_v111_report_test.dart`, `test/ui/speech_ui_test.dart`,
`app_lock_test.dart`; screenshots `editor_desktop_transcribe_*`,
`_transcript*`, `_speech_captions`, `_fillers`, `_auto_cuts`,
`_hebrew_captions` (looked at; the test font has no Hebrew letters, so
the Hebrew transcript screenshot shows boxes — real systems have them).
Verified with fakes and fixtures only — **no real speech program ran**:
parsers against hand-written recorded-style outputs
(`test/media/fixtures/speech/`), backends against a pretend computer
(`FakeHost`), the downloader against a local test HTTP server, MCP jobs
with the same fakes, the app with `FakeSpeech`; the Linux e2e (step 7j)
runs the REAL service and real ffmpeg (WAV) with a shell script standing
in for whisper-cli. Real: FFmpeg 6.1 drawtext for right-to-left text (by
eye), the jump check on synthetic video, `keepTimelineRange` / captions /
fillers through the real editor.
Not verified: any real whisper output (formats were written from memory:
whisper.cpp `-oj` field names, the FFmpeg filter's JSON lines and option
names, Python CLI option names); FFmpeg 8 at all; the pack URLs and
hashes; a real download; GPU detection strings; Windows PATH / pip
Scripts discovery and `.cmd` shims; whether Homebrew's FFmpeg has the
filter; transcription quality and speed in Russian / Hebrew; the filler
prompt's effect; jump thresholds on real faces; the 150 ms dissolve by
eye; Claude using the tools in a real session; the Windows worker process
for transcribe jobs (same caveat as export jobs: Claude Code ending the
process tree ends the job).

## Self-update, Claude helper that follows the app, self-test (1.12.0, 18 Nov 2026)

Owner: friends download from the page in `site/`; every update meant a new
download, a new Claude extension and a new skill upload. 1.12 makes all
three "once".

### Where the code is
- `lib/core/update/update_info.dart` (latest.json, newer / skip / once a
  day), `update_download.dart` (resume, size + SHA-256, a failed file is
  deleted), `update_install.dart` (where the app is, unpack next to it,
  start the swap script, result file). Pure Dart.
- `assets/update/clipforge-update.ps1` (Windows) and `.sh` (macOS): the
  swap scripts, shipped as assets and written to the app's support folder
  before use.
- `lib/ui/update/update_controller.dart` (`UpdatePlatform` = what differs
  per system; `UpdateController`), `update_ui.dart` (banner, Update window,
  "Check for updates").
- `lib/core/claude/helper_install.dart` (the per-user helper folder),
  `lib/mcp/delegate.dart` (hand-over), `lib/ui/claude/claude_helper.dart`,
  `connect_claude.dart` (Help > Connect to Claude…).
- `claude/guide/*.md` -> `tool/gen_guide.dart` -> `lib/mcp/guide_content.dart`
  (generated, checked in); `lib/mcp/tools_selftest.dart` (get_guide,
  self_test; a `part` of tools.dart).
- `tool/ci/`: `make_latest_json.py`, `windows_swap_test.py`,
  `job_survives_test.py`, `mcp_client.py`.
- Android: `MainActivity.kt` channel `clipforge/update` (openUrl,
  installApk, is64Bit), manifest `REQUEST_INSTALL_PACKAGES`, FileProvider
  `${applicationId}.updates` (`res/xml/update_paths.xml`: cache/updates only).

### Decisions
- **latest.json** keeps `version`, `build`, `date`, `notes_url` and gains
  `platforms.{windows,macos,android}.{url,size,sha256}` (1.15: no
  `android32` any more, see "Three downloads"). The url
  is the fixed-name file of THAT release (`releases/download/<tag>/…`), not
  `latest/…`, so size and hash always belong to the file. The release job
  also checks that latest.json carries the hashes of the files it uploads.
  The app accepts https addresses only and never keeps a file that failed
  the check. A latest.json without `platforms` (1.11 and older releases)
  only offers the download page.
- **The check**: once per run on the project list, at most every 24 h
  (`updateLastCheck` in settings.json), not when `updateCheckOff`, and
  **never for builds made on someone's own computer** (`BuildInfo.isCi`
  false: their build number is 1, so every release would look newer).
  Errors are silent; "Check for updates…" reports them. "Later" = this run;
  "Skip this version" = `updateSkipBuild`, shown again by a manual check or
  a newer build. No URL-launcher plugin was added: pages open through
  `rundll32 url.dll` / `open` / `xdg-open` / an Android intent.
- **Windows swap** (AS BUILT IN 1.12; it never worked on the owner's real
  PC and was replaced in 1.14.1, see "Updates that finish on real PCs"):
  unpack to `<install>.update-new` (Dart, in an isolate),
  "Restart ClipForge" starts PowerShell detached (`-ExecutionPolicy Bypass
  -WindowStyle Hidden -File …`, working folder = the app's support folder,
  never the install folder) and quits. The script waits for the app's pid
  (60 s), `Directory.Move` install -> `.update-old` (30 tries: a rename of a
  folder is all or nothing, so a locked file means nothing changed), new ->
  install (on failure old is moved back), writes `update-result.json`
  (`updated` / `failed` / `broken`), starts the app, deletes `.update-old`.
  The app reads the result once on the next start and tidies leftovers.
  Not writable (Program Files) or unknown place -> the download page, nothing
  downloaded. Exit codes 0/2/3/4/5 are the same in both scripts.
- **macOS**: the same swap with `ClipForge.app` (`ditto -x -k` to unpack,
  `/bin/sh` script, `open -n`). Reasoning: a zip the app itself downloaded
  is not quarantined, so the swapped app should open without a Gatekeeper
  prompt; `mv` keeps the ad-hoc signature. When the bundle path contains
  `/AppTranslocation/` (opened straight from Downloads) or its folder is
  not writable, nothing is replaced: the new app is unpacked into
  `~/Downloads/ClipForge <version>/` and shown in Finder with one sentence.
- **Android**: the APK goes to `<cache>/updates/`, is checked, then
  `ACTION_VIEW` with a FileProvider uri; Android's own dialogs do the rest
  (the "allow from this source" prompt is explained before it appears).
  A 32-bit device has no entry since 1.15 (`updatePlatformKey(..., only32Bit:
  true)` is null): the app offers the download page.
- **Claude helper**: built BEFORE the app in CI, packed into the .mcpb,
  and the .mcpb is an app asset (`assets/claude/ClipForge-claude.mcpb`,
  not in git). The app unpacks `server/` from it into
  `%LOCALAPPDATA%\ClipForge\claude` / `~/Library/Application Support/
  ClipForge/claude` (`versions/<version>-b<build>-<hash8>/`), switches
  `current.json`, and refreshes the stable-path copy by rename-then-copy
  (Windows lets a running .exe be renamed, not overwritten); failure there
  does not matter. **The .mcpb still carries a full helper** rather than a
  manifest that points at the stable path: the MCPB variables
  (`${HOME}`, `${user_config.*}`) could not be re-read here (github.com
  docs were not fetched in this round), `entry_point` must exist in the
  bundle, and %LOCALAPPDATA% is not always `${HOME}\AppData\Local`. Any
  copy that is started (extension, stable path) reads `current.json` and
  starts the installed version when its build is >= its own
  (`ProcessStartMode.inheritStdio`, exit code passed on); `--version`,
  workers and `dart run` never hand over; `CLIPFORGE_MCP_NO_HANDOVER=1`
  switches it off (all tests and CI checks set it). The manifest says
  `tools_generated: true`. The previous version's folder is kept one update
  longer (Claude may still run it and needs its fonts); older ones are
  removed program-first so a folder in use stays whole.
  **clipforge-mcp.exe is no longer next to clipforge.exe** (a helper
  running from the install folder would block the folder swap); the Mac zip
  has no `ClipForge-Claude` folder any more. Owners who connected Claude
  before 1.12 must connect once more (setup page says so).
- **Guide**: `get_guide` (start / recipes / tools / troubleshooting), also
  as MCP resources `clipforge://guide/<section>` (the server gained
  `resources/list` / `read`; prompts were not added). Server instructions
  start with "call get_guide first". Skill and `claude/CLAUDE.md` are thin
  pointers; `claude_guides_test` checks generated == Markdown, every tool
  is in the bundled tools section, no unknown tool names, thin skill.
- **self_test**: a second `ClipForgeTools` on a temp folder with the same
  media tools and the SAME export launcher (so the worker process is
  tested), in-process speech with the real packs. 15 rows; about 2-6 s
  here. `keep_files` leaves the folder.
- **Windows worker** (`startWorkerProcess` in export_jobs.dart): started by
  a short-lived `powershell.exe … Start-Process -WindowStyle Hidden
  -PassThru` (values through CF_WORKER_* environment variables, no
  quoting), so its parent is gone and `taskkill /T` on the server does not
  reach it; falls back to the old child process. WMI was rejected (drops
  the environment). Does NOT help against a job object without breakaway.
- get_project default page is 30 clips / 30 titles (was 60); `media` table
  only in get_project (edit answers with detail "full" are unchanged).

### Verified here (Linux container, FFmpeg 6.1.1) / not verified
Verified: `flutter analyze` clean; `flutter test` 1611 passed; Linux e2e
passed with a new step 0 (the banner on the real project list; the real app
unpacked the helper from its asset into a per-user folder and the stable
path answered); `flutter build linux --release`; `flutter build apk --debug`
(manifest shows the permission and the provider); the built helper's
self_test through the app-installed stable path: 14 PASS, 1 skipped (no
speech engine), hand-over visible in get_status; `tool/ci/
job_survives_test.py` on Linux (process group killed, 150 s export
finished); the sh swap script in every branch (pretend folders, a failing
`mv`); downloads against a local server (resume, bad hash, bad size).
**Not verified, first real run is the next workflow / the owner's devices:**
- Windows: the PowerShell swap script (never executed anywhere yet;
  `windows_swap_test.py` in the Windows job is its first run), execution
  policy set by group policy, antivirus reaction to a detached PowerShell,
  whether a window flashes, Explorer holding the folder; the PowerShell
  worker start and whether Claude Code really uses a plain tree kill;
  `rundll32` opening the page; `choco install ffmpeg` on the runner.
- macOS: everything (ditto, quarantine assumption, Gatekeeper after the
  swap, translocation detection, `open -n` relaunch, /Applications
  permission, the helper started from Application Support without a
  quarantine prompt, Intel Macs have no helper).
- Android: the installer hand-off, the FileProvider grant on Samsung, the
  "unknown sources" flow, that the release-signed APK installs over itself.
- The real latest.json and release assets (URL redirects, Range support on
  GitHub's download host), the release job's new lines, the new CI steps.
- Claude Desktop: that the .mcpb with `tools_generated` installs, that the
  bundled copy handing over works inside Claude's extension sandbox, that
  Claude reads the instructions and calls get_guide; MCP resources in a
  real client.
- The release app could not be started under xvfb here (the debug build in
  the e2e can); filler preview and "Use it anyway" by eye / ear.

## Text window, sound waves, who is speaking (1.13.0, 18 Nov 2026)

Two pieces of owner feedback on real podcast projects (22 and 23 minutes):
(1) hundreds of captions imported from a subtitle file ("Sam: it's okay to
have…") were only tiny blocks on the timeline, and the 1.11 Transcript
column was empty because it listed transcripts only: "a window to see the
entire text, like in Descript"; (2) with two linked voice files the sound
rows were plain green bars: "show when I speak and when the other person
speaks, if we want to cut manually".

### The Text window (`text_panel.dart`, `core/text/text_document.dart`)
- ONE place: it replaces the Transcript column (file `transcript_panel.dart`
  is gone; `EditorSession.showTranscript` is `showText`; Edit > Speech no
  longer has "Transcript"). It is NOT tied to speech-to-text any more, so
  phones have it (More > Text, a full-screen sheet; also what a computer
  window narrower than 900 px gets).
- Sources (`TextSource`): captions (every `TitleKind.caption`, whatever
  made it), transcript (computers, when one is stored), titles. Default:
  the first that exists in that order; a SegmentedButton when more than one.
- Speakers (`splitSpeaker`): "Name: text" at the start of a caption = that
  speaker (at most 4 words / 40 characters, starts with a letter, no
  sentence punctuation; "10:30" and "Note this. One thing: x" are not
  names; a full-width colon works). **A caption without a name belongs to
  whoever spoke last** (subtitle files often name the speaker only on a
  change). Not stored anywhere: read from the text every time.
- Paragraphs (`buildTextDocument`): a new one on a speaker change, a pause
  of 2 s, or when it is 600 characters long (400 at a sentence end). The
  name is shown when it differs from the paragraph before; a coloured bar
  runs down the side. Colours: `speakerColors` (ui/speaker_colors.dart) -
  a name equal to a speech track's name gets that track's colour, so text
  and timeline agree.
- **Virtualised with exact heights.** Every paragraph is measured once per
  width with a TextPainter using the same text and style it is drawn with;
  the ListView gets `itemExtentBuilder`. That is what makes "jump to line
  1490 of 1500" one step and the scroll bar true. Kept exact by: one text
  style for the whole paragraph (highlights only change the background),
  the measured text = the lines joined with single spaces, a fixed-height
  editor box. The column width moves in 16 px steps (so dragging the edge
  re-measures now and then) and is capped at 880 px. A paragraph that lays
  out a hair taller would be clipped, never an overflow error. Note: the
  list only ESTIMATES its total length until it has been to the end
  (`maxScrollExtent` is corrected with ScrollUpdateNotifications), so the
  own measured length is used for clamping and those corrections must not
  count as "the user scrolled".
- Follow: `followOffset` (pure) says where to scroll so that the line being
  spoken sits in the upper part. Follow turns off on a drag, a fling, the
  mouse wheel or the scroll bar's thumb (pointer down), never by the
  window's own scrolling. "Now" / the round button turn it on again.
- Selection: a click selects one line, moves the playhead and selects the
  caption on the timeline; Shift-click selects the range (computers). The
  timeline's selection is followed the other way round. The Delete key with
  several selected goes through `EditorSession.textDeleteHook`.
- Editing (captions only, owner decision: no edit-by-text editor): double
  click or Edit opens the caption's STORED text (with name and line break)
  in a box inside its paragraph; Enter saves (`updateTitle`: History
  "Edited caption '…'"), Esc cancels, an empty text is refused. Delete:
  `removeTitle`, or a transaction labelled "Deleted N captions".
  `describeEdit` now says "Deleted N captions" / "Edited N captions".
- **Cut this part out of the video…** (computers; captions and transcript):
  `planTimelineCut` / `applyTimelineCut` in `speech_edits.dart`. The
  selection's first start to last end is mapped per clip to source ranges
  (`removeSourceRanges`; a clip wholly inside is removed; a photo partly
  inside is left alone and the dialog says so), one undo step, and every
  removed piece of a video file is added to `Project.autoCuts` with the new
  kind **"text"** (word = the first 40 characters), so the existing
  Automatic cuts list and `restore_cut` put it back. Limits, said in the
  dialog: captions on the removed part come back only with Undo, not with
  Put back; a whole clip that was the only piece of its file cannot be
  put back from the log (Undo can).
- Layout: `EditorSession.textDock` right (default, a column after the
  inspector, 460 wide, never under 420) or below (under the preview and
  transport, 280 high); a 7 px drag handle; place and size in the app
  settings (`textDock`, `textWidth`, `textHeight`). **Not built: a detached
  OS window** (Flutter desktop has no second window here); "under the
  preview" is the wide alternative.
- Ctrl/Cmd+F: the editor's key handler (and a CallbackShortcuts around the
  panel for when the cursor is in one of its text boxes) opens the window
  and focuses the search. Ctrl+Shift+T toggles it (windowMenuShortcuts /
  the Mac menu).

### Many captions on the timeline (`timeline_view.dart`)
The smallest change that helps, no redesign: blocks narrower than 12 px are
slim marks; blocks narrower than 44 px have a tooltip with their text; and
when the AVERAGE caption is narrower than 110 px a 20 px strip above the
title rows shows the caption under the playhead as one line (a click
selects it). The strip depends on zoom and captions only, so the timeline
does not change height while playing.

### Sound waves (`media/sound_peaks.dart`, `sound_peaks_job.dart`)
- One low-rate decode per SOURCE FILE and audio stream - the same ffmpeg
  command as "Line up by sound" (`buildAlignDecodeCommand`, 8 kHz mono) -
  gives per 20 ms the peak (drawn) and the RMS level (who speaks): two
  bytes per hop, 240 KB for 40 minutes. Measured here: 40 minutes of
  samples are reduced in well under a second of Dart; the decode itself is
  ffmpeg's (not measured on the owner's machines).
- Cache: `<app support>/peaks/pk_<mediaFingerprint>_a<track>.cfpk`, NEXT TO
  the app's media folder, not in it (the clean-up of unused media deletes
  what no project references). Least recently used files go when the
  folder passes 48 MB (`evictSoundPeaks`, on the first use per editor).
  The MCP helper keeps its own in `<ClipForge>/sound-pictures/`.
- Engine seam: `SoundPeaksEngine.soundPeaks(path, audioTrack, cacheDir)`,
  implemented by both engines with their own ffmpeg runner.
- App: `SoundPictures` (one per `EditorSession`): asks for the files the
  project uses, one at a time, never blocking; "Drawing sound…" at the top
  right of the timeline while it runs; missing files are skipped; a file
  that cannot be read stays plain. Off entirely with "Show sound waves"
  (`kSoundWavesOffFlag`; Playback menu, More on phones).
- Drawing (`sound_wave.dart`): one bar every 2 px for the part of the block
  near the view only (`waveColumns`, pure; the timeline's existing window),
  the loudest moment of the stretch a bar stands for, through trim, speed
  and loops; `drawRawPoints`. Sound blocks: around the middle; video clips
  whose sound is on: a 15 px strip along the bottom. Over a waveform the
  block's name sits on a dark tag.

### Who is speaking (`sound_peaks.dart`, `speech_map.dart`)
- Per file: the rule of Remove silences (floor = 10th percentile,
  threshold = floor + 35 % of the span, 4..12 dB), with two changes:
  digital silence is left out of the percentiles and "loud" is the 95th
  percentile. Gaps under 300 ms are bridged, talk under 160 ms dropped.
- Bleed (`groupSpeechStretches`): voices LINKED to clips of the same video
  file were recorded together and are compared hop by hop in the video's
  time (each one's `syncOffsetMs`). Where two are active, one is taken as
  bleed when the other is 8 dB louder RELATIVE TO ITS OWN SPEECH LEVEL and
  this one is more than 6 dB under its own, or when the other is 15 dB
  louder in plain numbers (someone who hardly talks has no speech level of
  their own). Both loud = overlap, both shown.
- Speakers = speech tracks (`SoundTrack.speech`); without any, the video's
  own sound ("Video"). Stretches are kept in FILE time and mapped per
  sound through in / out / speed / start (`stretchesOnTimeline`), so cuts
  need no bookkeeping. `speakerTurns` merges them into turns (same speaker,
  pause under 3 s); `speechStarts` / `neighbourStart` drive Ctrl+Left /
  Right (the selected sound's track, else any turn start); `speechEdges`
  are extra snap targets (not the dragged sound's own track).
- Colours: the n-th speech track gets `kSpeakerColors[n]`; the block is
  that colour dimmed, talk is a band of the full colour, the row header's
  microphone has it.
- Not built (optional in the request): the thin "who speaks" summary strip
  above the tracks.

### MCP (62 tools)
`get_captions` (text / paragraphs, ids optional, paged; get_project still
lists captions with their look, 30 at a time), `replace_in_captions` (dry
run default TRUE; literal find, optional whole word / case; one undo
step), `get_speech_map` (turns or stretches, per speaker totals and share;
listens once, cached). `list_auto_cuts` / `restore_cut` know kind "text".
Guide: tools.md (both sections), start.md, two new recipes, one
troubleshooting entry.

### Verified here / not verified
Verified: `flutter analyze` clean; `flutter test` 1690 passed (79 new:
`test/core/text_document_test.dart`, `test/media/sound_peaks_test.dart`,
`test/ui/text_window_test.dart`, `test/ui/sound_waves_test.dart`,
`test/mcp/tools_v113_test.dart`, which uses the real ffmpeg for
get_speech_map); the Linux e2e with new steps (the Text window shows a
real transcript, then the captions; a caption is edited in place; the
sound picture of a real file is read by the real engine and drawn);
`flutter build linux --release`; `dart run bin/build_mcp.dart` and the
built helper answering tools/list (62) and get_guide; `dart run
tool/gen_guide.dart --check`. Screenshots looked at: `docs/screenshots/
text_window_*.png`, `timeline_waves_*.png`, `timeline_many_captions.png`.
Performance bounds in tests: 1500 captions / 40 minutes open the Text
window building under 40 paragraphs; 40 minutes of samples become peaks in
under 4 s (in practice far less); 150 waveform windows of a 40-minute
block in under 1.5 s. **Not verified:** real Windows / macOS / Android
devices; how long the first decode of a 40-minute file takes there (on a
phone it runs through FFmpegKit); scrolling smoothness of the Text window
and of the waveforms by eye on a real screen; the speaker colours and the
bleed rule on a real Zoom recording (tuned on synthetic two-microphone
fixtures only); Cmd+F / Cmd+Shift+T through the real macOS menu bar.

## Publishing kit, notes, shorts, markers (1.14.0, 19 Nov 2026)

Owner (non-technical; podcasts, family videos, sport clips; Windows, Mac,
Android): after editing, get a ready "publishing kit" - a few videos in the
right formats plus the text to paste - and better help making good short
clips, with Claude doing the picking where it can and a simple manual way
in the app.

**Owner decisions (do not reopen without asking):**
- **NO uploading** to YouTube / Instagram / TikTok from the app, and **no
  logins**. ClipForge makes files and text; the owner posts them. The only
  network use added is opening a site's own upload page in the user's own
  browser (plain https links from the table, the same open-URL mechanism
  as updates; no embedded browser, no account).
- **On hold, recorded as a future idea: a personal "Publisher".** A
  SEPARATE tool (not part of ClipForge, not shipped to friends) that
  drives the owner's own browser profile to fill in the upload forms from
  the kit folder (files + "… - text.txt"). Rules if it is ever built: it
  never stores passwords (it uses the browser profile the owner is already
  signed in to), it STOPS BEFORE "Publish" so the owner presses the last
  button, and it reads only the kit folder. Nothing of it exists.

### Destinations are data (`lib/media/destinations.dart`)
`kDestinations` is the one table (order = order in the Export window):
youtube (16:9, 1080p, full), shorts (9:16, 1080p, `maxSeconds` =
`kShortMaxSeconds` 60, three upload pages), instagram (4:5 and 1:1, 60 s),
whatsapp (quality small, `maxMegabytes` 16), podcast (mp3, m4a), custom.
To add a row, add it there: the Export window, "Export several…", the
warnings, the file names, the upload links and Claude's export_kit all
read it. **The limits are conservative guesses from November 2026 and were
not checked against the sites** (no network to them here): every warning
carries `limitNote`, which says whose limit it is, that it changes, and
"check the site". The 16 MB for WhatsApp is the old limit and will warn on
most videos over ~50 s; raise it in the table if the owner finds it noisy.
`KitChoice` = destination + shape + file kind (`key`: "shorts",
"instagram:1x1", "podcast:m4a"). File names: `kitFileName` ("<Project> -
YouTube.mp4", "- Short 9x16.mp4", "- Instagram 4x5.mp4", "- WhatsApp.mp4",
"- audio.mp3"), `kitTextFileName` ("- text.txt").

### A destination never changes the project
`shapeDiffers` (more than 2 % apart, so 1920x1080 is 16:9).
`applyDestinationShape` (one undo step "Shape 9:16 with blurred
background"): aspect + video size, and clips set to Fit whose own picture
has another shape get FitMode.blur (a clip the user set to Fill keeps it;
nothing is cropped - the dialog reminds of Crop and position).
`destinationVariant` returns the project as a destination needs it IN
MEMORY. Single export with another shape asks: **Make a copy in this
shape** (the variant is saved as a new project "<name> - 9x16" through
`onKeepCopy` = store.duplicate + save, and exported from it; the finished
screen says the copy is in the project list) or **Export as it is**.
"Export several…" uses variants in memory only (nothing in the project
list) unless "Keep the shape copies as projects" is ticked.

### Export several (`lib/media/export_kit.dart`)
`planKit` -> `runExportKit(engine, plan, folder)`: one after another,
each rendered as `<name>.part.<ext>` and renamed (replacing an older file
of that name), progress weighted by megapixel-seconds, cancel throws the
current file away and keeps finished ones, then the text file. Computers:
`PublishService.chooseFolder` once, files go straight into it. Phones: the
app's `exports/<project>/` folder + each video into a gallery album named
after the project (`Gal.putVideo(album:)`); sound and text stay in the
app folder and go out through Share. The runner uses blocking file calls
on purpose (widget tests cannot await real file IO).
**Phones keep the exported file now**: `saveCopy` no longer deletes the
app's copy after the gallery copy (Share needs it); `removeOldExports`
deletes exports older than two days before each new export.
Fixed on the way: `chooseSavePath` appended ".mp4" to a sound-only export's
name on computers.

### Publishing notes (`Project.publishing`, `core/publish/chapters.dart`)
`PublishingNotes` (title, description, hashtags, chapters, shortTitle,
shortDescription) under the additive JSON key `publishing` (written only
when not empty; schema stays 2; older versions ignore it and drop it on
save). `ProjectEditor.setPublishingNotes` = one undo step; History names
from `publishingChange` ("Publishing title", "Hashtags", "Chapters (6)",
several at once = "Publishing notes"). The panel
(`publishing_panel.dart`: dialog on computers, full screen on phones;
Export window, File menu, Project panel, phones More) stores a field when
it loses the focus, so each field is one step.
**Chapter rules in one place: `kChapterRules`** (first at 0:00, at least
10 s each, at least 3, at most 12 automatic ones, titles to 60
characters). `buildChapters`: titles -> else caption paragraphs (speaker
change / 2 s pause, named by the first words) -> else speaker turns
("Part n - Name"). `chapterProblems` names what a typed list breaks.
`kitText` builds the text file (TITLE, DESCRIPTION, HASHTAGS, TAGS,
CHAPTERS, MUSIC CREDITS, short-form title, a section per file with what
to paste there); a single export on a computer writes it next to the file
only when there are notes or music credits.

### After export
Phones: **Share** (`PublishService.share`: share_plus with files + text +
subject), with "Copy title and description" kept visible (many apps
ignore shared text) and "Saved to your gallery" as before. Computers:
**Show in folder** (`explorer /select,` / `open -R` / `xdg-open`), Copy
buttons, **Open … upload page** per destination.

### Shorts
- `core/publish/shorts.dart` is shared by the app and Claude: the "Short"
  look defined once (`ShortLook`, `shortCaptionStyle`: 0.075 of the short
  side, y 0.68, outline, Rubik; `shortTopTitle` at y 0.13);
  `applyShortCaptionLook` divides a caption that would need more than two
  lines into several, time shared by length; `buildShort` (keep the range,
  9:16, 1080p, optional blur, captions from words when the part has none);
  `snapShortRange` (outward to a pause, at most 4 s, 150 ms of the quiet
  kept, then never inside a word / caption); `shortCandidates`.
- App: Text window selection -> **Make a short from this…** (computers:
  Shift-click a range; phones select one line, so the dialog offers 30 /
  45 / 60 s from there). **Timeline: there is no range concept** (I / O
  trim the clip), so the light action was built: **Make a short from
  here…** (30 / 45 / 60 s from the playhead; Edit > Shorts, Project panel,
  phones More > Shorts and good moments). The short is a new project
  (store.duplicate -> buildShort -> save; notes and markers are not
  copied); then "Open it" (`EditorSession.openProject` = save, release the
  lock, pushReplacement) or "Stay here". Warning over `kShortMaxSeconds`,
  never a refusal.
- **Markers** (`Project.markers`, key `markers`, additive): M on
  computers (also while playing), More > Mark a good moment on phones;
  flags on the ruler (tap = go there); "Good moments…" list; "Make shorts
  from markers…" = `markerRange` (20 s before to 25 s after) snapped with
  the 1.13 speech map when its picture is ready (`pausesIn`), else the
  gaps between captions / transcript words. **Markers follow their
  picture** (`core/editor/marker_follow.dart`, run in
  `ProjectEditor._edit`): found again by clip id + source position, also
  in pieces a cut made; a marker whose moment was cut away stays at the
  cut. Lighter than title anchors and stateless.

### Claude (70 tools; `lib/mcp/tools_publish.dart`)
`suggest_shorts` (CANDIDATES only, the helper has no AI: whole sentences
between pauses / speaker turns in a length window, from the transcript's
words or else the captions; signals starts-with-a-question, figures,
pause before / after, `emphasisDb` from the sound picture; for each start
the shortest and the longest natural passage; paged), `make_short` gained
`caption_style: "short"`, `title`, `snap_to_speech` and warnings (longer
than 60 s, starts / ends mid-sentence), `get_publishing_notes` /
`set_publishing_notes`, `make_chapters` (dry_run, replace), `export_kit`
(project_id + destinations, `projects` for the shorts; ONE job in the 1.9
job store with `format: "kit"` and a `<id>.kit.json` plan; the worker
runs `runKitJob`; **get_export_status and cancel_export cover it**, no
sibling tools), `add_marker` / `list_markers` / `remove_marker`.
`self_test` gained `quick`. Guide: recipe "From a long video to a
publishing kit" (how to pick: hook in 3 s, one idea, complete thought,
ends on a point, no inside references; three title options; ask before
making), tools section, start section; regenerate with
`dart run tool/gen_guide.dart`.

### Tests (1796 in all)
`test/core/publishing_test.dart`, `test/media/destinations_test.dart`
(pretend engine + one real FFmpeg kit: 3 files with the right sizes and
the text file), `test/mcp/tools_v114_test.dart`,
`test/ui/v114_ui_test.dart` (phone + desktop; screenshots `export_*_
destination`, `_several`, `_several_done`, `_finished`,
`publishing_notes_*`, `short_dialog_*`, `short_made_*`, `markers_*`).
Linux e2e step 5b: Export several through the real window with the real
engine (YouTube 1920x1080, Short 1080x1920, MP3, text file).

### Not built / not verified (1.14 publishing and shorts)
Not built: remembering the last destination; per-destination notes beyond
the short title / description; a thumbnail image for YouTube; markers with
labels typed in the app (Claude can label them); dragging a marker; a
range selection on the timeline; auto-reframing (the person in shot is
still Crop and position by hand). Not verified: everything on real
devices - the Android share sheet with a video + text, the gallery album
(`Gal.requestAccess(toAlbum: true)` asks for more permission than before),
that the kept app copy of an export is really removed after two days,
FilePicker's folder dialog on Windows / macOS, `explorer /select,` with
odd paths, the upload URLs (not opened from here), the site limits, the
Short caption look by eye on real footage, Claude using the new tools in
a real session, the kit job's worker process on Windows.

## Connect to Claude done by the app; clearer updates (1.14.0, 19 Nov 2026)

Two pieces of feedback from the owner's first real in-app update on
Windows (1.12.0 build 114 -> 1.13.0 build 118; it was believed to have
worked end to end - WRONG, see "Updates that finish on real PCs (1.14.1)":
the new version had been started by hand from the ".update-new" folder;
About shows 1.13.0) and from connecting Claude.

### Updates
What was seen: next to the install folder "ClipForge-1.12.0" (the owner's
own folder name) a folder "ClipForge-1.12.0.update-new" appeared. Every
path that leaves `<install>.update-new` / `.update-old` behind:
1. download + unpack done, the user has not pressed Restart yet
   (transient; this is almost certainly what was seen);
2. the swap script still waiting for the app's process (up to 60 s);
3. a failed rename (Explorer or a terminal open in the folder, antivirus
   scanning): `.update-new` stays, result "failed";
4. the script never ran (PowerShell blocked): no result file at all -
   1.13 then silently deleted the download at the next start;
5. the new app is in place but `.update-old` could not be deleted;
6. 1.13's start-up clean-up deleted ANY folder of those names.
Changes:
- **Marker**: only folders the updater made are ever removed.
  Windows: `.clipforge-update-marker` inside the folder (written into the
  unpacked update, and by the script into the folder that steps aside);
  macOS: a file NEXT TO the bundle (`<bundle>.update-new.marker`),
  because a file added inside a signed .app would break its seal. Both
  scripts refuse (exit 2, "a folder ClipForge did not make is in the
  way") instead of deleting an unmarked `.update-old`.
- **`update-pending.json`** in the state folder remembers an unpacked
  update. `decideUpdateAtStart` (pure, tested as a table): result
  "updated" -> one quiet line "Updated to X" with What's new; "failed" /
  "broken" -> a window with the reason, **Try again** (re-runs the swap,
  no new download) and **Open the download page**; pending + swap started
  + no result -> "the step that swaps the versions did not run"; pending,
  swap never started ("Later", or the app closed another way) ->
  **applied at the next START** (decision: at start nothing is open and
  nothing runs; applying on close would restart an app the user just
  closed). It is tried once by itself; after that only by Try again.
- The dialog after a checked download says what is left and offers
  **Restart ClipForge to finish** / **Later** (with the sentence about
  the ".update-new" folder).
- **Never while busy**: `UpdatePlatform.mayQuit` =
  `ServicesBinding.handleRequestAppExit()`, so an open editor saves first
  and a running export says no; the update then waits for the next start.
  (Before, `exitApplication(required)` skipped that question.) Claude's
  export / transcribe jobs run from the helper folder, not the install
  folder, and are not touched by the swap.
- **Folder names**: the Windows zip already unpacks to one folder called
  "ClipForge" (the workflow now checks that); "Extract All" wraps it in a
  folder named after the zip, which is where versioned names come from.
  Install steps (site/index.html, README, help "Updates") say: keep it
  in a folder called "ClipForge", no version in the name. When the app
  runs from a folder whose name holds another version, the "Updated" line
  adds one sentence (`folderNameNote`); the folder is NEVER renamed by
  the app (shortcuts).
- `tool/ci/windows_swap_test.py` gained scenarios 7-9 (marker / no
  marker, the old folder left with a marker, apply at the next start).
- **Long-term answer (not built): a proper Windows installer** - a
  per-user install (no admin rights, e.g. under %LOCALAPPDATA%\Programs)
  with a Start-menu shortcut, so that there is no folder for the user to
  name, move or keep open, and the updater always knows where it is.
- Not verified: everything on real Windows / macOS (the new script lines
  have only run in the sh form here; scenarios 7-9 run first in the next
  Windows job), `handleRequestAppExit` on the desktop embedders, the
  restart flicker of "apply at the next start".

### Connect to Claude (`lib/core/claude/connect.dart`, the page in
`lib/ui/claude/connect_claude.dart`)
Problems: the Microsoft Store build of Claude Desktop is not registered
for `.mcpb` (double-click opens "Select an app…"), and the Claude Code
set-up felt confusing ("why restart, why can't I choose it in Claude,
start it from the app like Blender, see if it is running").
- Per target a status light and ONE button. **Claude Code**:
  `findClaudeCode` (PATH, ~/.local/bin, ~/.claude/local, npm's folder,
  WinGet links; .exe / .cmd), status from `claude mcp get clipforge`
  (`parseMcpGet`, defensive) and from `~/.claude.json` (read only, also
  when the program is absent); Connect runs `claude mcp remove clipforge
  -s user`, removes project-folder entries that start an OLD
  clipforge-mcp (listed first, asked once; somebody's own tool that
  happens to be called clipforge is left alone), then `claude mcp add
  --scope user clipforge -- <stable helper path>`. ClipForge never writes
  Claude Code's own file. **Claude Desktop**: `findClaudeDesktop` -
  `%APPDATA%\Claude`, the Store build under `%LOCALAPPDATA%\Packages\
  <a package with "claude" in its name>\LocalCache\Roaming\Claude`,
  macOS `~/Library/Application Support/Claude`; Connect =
  `editDesktopConfig`: only `mcpServers.clipforge` changes, by splicing
  the text (every other byte kept, the file's indent and line ends used;
  falls back to re-encoding when the result would not mean exactly what is
  wanted), a dated backup first, **a file that is not plain JSON is
  refused**, a missing file becomes a minimal one only when Claude's
  folder exists. An installed extension next to an entry is pointed out
  ("one of the two is enough"). **Disconnect** removes only the entry.
- **"Is it running?"**: the helper writes `<stable>/in-use/<pid>.json`
  at the MCP handshake (client name from `clientInfo`), refreshes it at
  most every 5 s on tool calls, removes it on exit
  (`lib/mcp/heartbeat.dart`; not under `CLIPFORGE_MCP_NO_HANDOVER`); the
  page deletes files whose process is gone.
- **Test**: starts the stable helper itself, handshake, `self_test
  quick: true`, PASS / FAIL with Details.
- **No HTTP / "start server" mode (decision).** Claude Desktop and Claude
  Code both START a local helper from their own config; a server inside
  the app would still need the same one-time entry in Claude and would
  only work while the app is open - more to explain, not less. The page
  says so in one sentence ("Claude starts the helper itself; ClipForge
  does not have to be running"). Can be revisited if Claude gains a way to
  pick a running local server from its own interface.
- **NOT VERIFIED - there is no Claude install in the build container:**
  the wording of `claude mcp get / list / add / remove` (fixtures in
  `test/core/fixtures/claude/` are written from memory), the scope flags,
  the `.cmd` shim through `runInShell`, where `~/.claude.json` keeps
  project entries, the Store package's folder name and that Claude reads
  the config from there, the folder name of an installed extension
  ("Claude Extensions"), that Claude Desktop accepts an entry without
  "args" problems, and the Settings path for installing an extension by
  hand. The page's **Details** shows exactly what was run and answered:
  ask the owner for it when a light is wrong.

## Updates that finish on real PCs (1.14.1, 19 Nov 2026)

### What was found on the owner's real Windows 11 PC
The first real users of the in-app update. The 1.12.0 zip was unpacked
into a folder named `ClipForge-1.12.0`; the app was updated in-app twice
(1.12 -> 1.13, 1.13 -> 1.14). Download, check and unpack worked both
times. **The swap never happened.** Product versions per folder:

    ClipForge-1.12.0                         1.12.0+109
    ClipForge-1.12.0.update-new              1.13.0+118
    ClipForge-1.12.0.update-new.update-new   1.14.0+121

Each new version stayed in `<install>.update-new`, the old folder was
untouched, and the new version was then started BY HAND from the
".update-new" folder (so the next update nested one deeper). The
statement in the 1.14.0 section that the first update "worked end to
end" was wrong: About showed 1.13.0 because the app had been started from
the unpacked folder. No `update-result.json` or `update-pending.json` was
found afterwards, and the app said nothing. In CI on windows-latest the
1.14 script passed every scenario.

### Root-cause candidates (NOT determined - there was no log)
A. **The script never ran or was ended with the app.** 1.12 - 1.14
   started `powershell.exe -File …` with Dart's
   `ProcessStartMode.detached` and then called `exit(0)`. Possible:
   PowerShell without a console and without standard handles ends at
   once; a job object ends it with the app; an execution policy set by
   group policy (it outranks `-ExecutionPolicy Bypass`); security
   software. Fits best: no result file, no restart of the old app, and
   1.13's start-up clean-up did not delete the unpacked folder (it would
   have if the old app had been started again by the script).
B. **`Directory.Move(install, install.update-old)` failed for the whole
   retry window** because something held the folder itself: an Explorer
   window showing it, a terminal with it as current folder, a scanner
   reading the fresh files, a child process. The script then writes
   "failed" and restarts the old app, which would have shown a message
   (1.14) - the owner saw none, so B alone does not explain it, but B is
   real on any PC (CI scenario 4 now holds the folder and the rename is
   refused there).
The CI test ran the script from Python with nothing holding the folder,
so neither class could show.

### What 1.14.1 does (both classes are assumed real)
- **No rename of the app folder any more (covers B).**
  `assets/update/clipforge-update.ps1`: wait for the app's pid (still
  alive after 60 s: exit 6, nothing done) -> every file in the folder is
  tried for writing (a held file: named in the result, exit 3, nothing
  changed) -> safety copy `robocopy <install> <install>.update-old /MIR
  /R:2 /W:1` (marker written first and again after) -> `robocopy
  <install>.update-new <install> /MIR /IS /IT` (6 tries; exit codes
  below 8 are success) -> check (clipforge.exe has the new size,
  `data\clipforge-version.json` is byte-equal to the new one) -> on
  failure the safety copy is mirrored back (exit 4; if even that fails:
  "broken", the app is started from the safety copy, exit 5) -> result
  "updated", start the app, remove `.update-new` (marker) and the safety
  copy. **Decision: copy, not move**, for the safety copy: reading files
  is almost never refused, nothing in the live folder changes until the
  copy is complete, and a failed copy leaves nothing to undo. Cost: the
  app's size in free disk space and a few seconds.
  `/XF .clipforge-update-marker unins*.exe unins*.dat unins*.msg`: the
  marker is never copied into the app folder, and the installer's
  uninstaller (which no update contains) is never deleted by the mirror.
  Like the old swap, a mirror removes files in the app folder that the
  new version does not have (they are in the safety copy until the end).
- **The script must report in (covers A as far as an app can).**
  `startSwap` (`lib/core/update/update_install.dart`): the scripts are
  written to the state folder (never the install folder, CRLF line ends),
  all values go through the environment (`CF_UPD_*`, always all of them),
  and the script is started the way 1.12 starts export workers: a
  short-lived `powershell -Command "Start-Process powershell -File …
  -WindowStyle Hidden"` (`kWindowsSwapStartScript`), so the script is not
  in the app's process tree and has its own hidden console. The app then
  waits up to 15 s for the line `started token=<token>` in the log. Not
  there: the **cmd fallback** `clipforge-update.cmd` (same steps with
  robocopy, no PowerShell; started as `cmd /c start /min cmd /c
  clipforge-update.cmd` from the state folder) and another 15 s. Still
  not there: the app does NOT close, says "could not start the small
  helper…" with the log's path, Copy details and the download page.
  A lock folder (`<result>.<token>.lock`) makes a late first script and
  the fallback exclude each other (exit 7). What this cannot cover: a
  job object that ends the script when the app exits. The log then ends
  after "started…/args…" with no "has closed" line, and the next start
  says "did not finish and left no answer" - that is the evidence to ask
  for. (WMI `Win32_Process.Create` or a scheduled task would leave a
  job; not built.)
- **Evidence: `update-log.txt`** (`lib/core/update/update_log.dart`) in
  the state folder (`%APPDATA%\com.ekcut\ClipForge\update-state\`,
  macOS `~/Library/Application Support/<bundle id>/update-state/`), kept
  across updates, cut to its newer half above 200 KB. Lines:
  `<time> app: …` (what was asked for, how each start went, "closing
  now", and at the next start what was found and decided) and
  `<time> script(ps|cmd|sh): …` (started, args, each robocopy exit code,
  the check, the result, done). Help > Copy version info adds the app's
  folder and the last 40 lines; failure messages have **Copy details**.
  **How to read it**: find the last `app: swap:` line. Then
  - no `started token=` after it -> the script did not start (class A;
    the `start by PowerShell: exit code …, said: …` line has
    PowerShell's own words);
  - `started` but no `has closed` -> the script was ended with the app,
    or the app never closed;
  - `in use, waiting: <file>` / `still in use` -> a locked file (named);
  - `robocopy (…) exit code N` with N >= 8 -> the copy failed, the
    lines after it are robocopy's own;
  - `result: updated` and `done` -> it worked; a `could not remove` line
    names a leftover folder.
- **Tidy up** (`lib/core/update/tidy_up.dart`, `offerTidyUp` in
  `lib/ui/update/update_ui.dart`, called from the project list after the
  update outcome): Windows, the app's folder name ends in ".update-new"
  (any number of times). One question per version (`tidyUpDeclined` in
  settings.json holds "version+build"). Target: "ClipForge" next to it
  (default) or the original name without the endings; a target that
  exists is used only when it is PROVEN to hold an older ClipForge (then
  it is brought up to date), otherwise it is shown as taken. Older
  folders offered for removal: name is `<base>` or `<base>.update-new…`
  AND it holds clipforge.exe with a lower version
  (`readInstalledVersion`: the version file, else "ProductVersion" read
  from the exe's bytes, e.g. "1.12.0+109"). Listed with versions,
  untickable. The move is the same script with `-Mode move`
  (`CF_UPD_MODE=move`): `<install>` = the target (may not exist),
  `<new>` = the running folder, removed afterwards without needing a
  marker, plus the remove list (the script itself re-checks: next to the
  target, holds the program). On failure the app is restarted from where
  it was. Shortcuts: a zip install has none, nothing to fix (said in the
  dialog). The owner gets there like this: 1.14.0 downloads 1.14.1 into
  a third ".update-new" folder, its old script fails as before, the
  owner starts 1.14.1 from that folder by hand once - or simply runs
  ClipForge-Setup.exe.
- **Installer** `windows/installer/clipforge.iss` (Inno Setup 6):
  per user (`PrivilegesRequired=lowest`), `{localappdata}\Programs\
  ClipForge`, Start-menu shortcut, optional desktop icon, uninstaller.
  Built by the Windows job from `dist\ClipForge` (the zip's folder),
  smoke-tested (silent install into a temp folder with a space, files +
  version file + shortcut, the PowerShell update script run against the
  installed folder, silent uninstall), published as
  `ClipForge-Setup.exe`; latest.json still names only the zip, which is
  what the in-app updater uses in an installed copy too. Unsigned:
  SmartScreen shows the same "Windows protected your PC" box. The
  version in Settings > Apps stays the installed one after in-app
  updates (not corrected). The uninstaller removes only named things
  (`data`, clipforge.exe, *.dll, the two documents, the marker), never
  the whole folder.
- **Version file**: `windows/CMakeLists.txt` (and linux, to test the
  CMake lines here) writes `data/clipforge-version.json`
  (`{"version":"1.14.1+123"}`) at install time; CI checks it.
- **macOS** (`clipforge-update.sh`): reviewed. `mv` of a bundle works
  whatever is open in it, so class B does not exist there; kept as a
  rename. Added: the log and the "started" line (the app waits for it
  like on Windows), and an app that is still running after the wait is
  left alone (exit 6) instead of being swapped under its feet.
- Tests: `test/core/update_log_test.dart`, `tidy_up_test.dart`,
  `update_install_test.dart` (script consistency, version reading,
  `startSwap` with the real sh script and with stand-in launchers),
  `test/ui/update_1141_test.dart` (tidy-up dialog on real temp folders,
  Not now, helper not started, Copy details, Copy version info),
  `update_controller_test.dart`. Widget tests never start a script
  (`swapStarterProvider`, `Fakes.swaps`).
  `tool/ci/windows_swap_test.py`: 13 PowerShell scenarios (4 = folder
  held by a handle and by a process whose current folder it is: the
  update must SUCCEED; 5 = a held file: named, nothing changed, and with
  `-SkipLockCheck` the roll-back; 11 = tidy-up; 13 = started by the
  app's launcher line and surviving `taskkill /T` of the "app") and 6
  cmd scenarios.
- **Still unknown / not verified**: which class it was on the owner's
  PC; everything in the new .ps1 / .cmd / .iss / workflow steps has
  never run (no Windows here: no PowerShell, cmd, robocopy or Inno
  Setup) - the next Windows job is their first run, expect to fix
  details; robocopy's rule that `/XF` files are also not purged from the
  target is relied on (CI scenarios 1 and 14a check it); whether Inno
  Setup is on the runner or installs from Chocolatey; SmartScreen's
  reaction to the unsigned installer; `chcp 65001` + `for /f` on a
  remove list with non-ASCII paths in the cmd script (CI uses ASCII
  there); the 15 s wait on a slow PC with a scanner.

## Feedback, one source for addresses, rename readiness (1.16.0, 20 Nov 2026)

Owner: the website goes live on Vercel (deployed from the owner's own
session), the app should be able to send feedback to it, and "the name
may change later, so nothing may hard-code the site address in many
places".

### One source for outside addresses

- **`tool/ci/links.json`** is THE file: `site`, and under `links` the
  pages `download` (`/install`), `feedback_api` (`/api/feedback`),
  `feedback_page`, `help`, `privacy` (a value starting with `/` is a page
  of `site`), plus `claude_page`, `repository`, `old_pages` (the GitHub
  Pages address) and `feedback_api_hosts` (extra hosts feedback may go
  to; empty). `tool/ci/links.py` reads and checks it.
- **Readers**: `make_latest_json.py` (writes `links` into latest.json;
  `--links <file>`, `--no-links`; a links.json the app would refuse stops
  the release), `make_readme_html.py` (download page, help online,
  source), `web/scripts/build-content.mjs` (-> `web/content/generated/links.json`
  -> `web/lib/site.ts`), and the tests.
- **The app's built-in copy**: `lib/core/links.dart` (`AppLinks.builtIn`,
  `kRepositoryUrl`, `kReleasesUrl`, `kLatestJsonUrl`, `kFeedbackApiHosts`,
  and `kAppName`). `kLatestJsonUrl` / `kDownloadPageUrl` left
  `update_info.dart`. `test/core/links_test.dart` fails when the copy
  differs from links.json, and when the site's host or the old Pages host
  is written in any other file under `lib/`, `tool/`, `bin/`, `assets/`
  or `../web/` (`web/tests/links.test.ts` checks `web/` again from its
  side). To move the site: edit links.json, copy into links.dart.
- **Without a new build**: `UpdateInfo.links` (raw text map from
  latest.json; null in files before 1.16, which parse as before).
  `UpdateController.check` hands it to `LinksController.remember`
  (`lib/ui/links.dart`, `linksProvider`), which keeps
  `{"v": <app version>, "links": {...}}` in settings.json (`linksSeen`)
  and uses `AppLinks.builtIn.withOverrides(...)`. A latest.json without
  `links` changes nothing. A newer app version ignores what an older one
  remembered (its built-in addresses are at least as new) until its first
  check.
- **Checks** (`checkedLink`, `withOverrides`): text, <= 200 characters,
  https (http only with `allowHttp`, used by tests and the e2e), a host
  with a dot, no user name, no spaces or control characters; bad values
  are ignored one by one. `feedback_api` is taken only when its host is
  the (new) site's own host or in `kFeedbackApiHosts`; otherwise the
  built-in feedback address stays. The latest.json address itself cannot
  be changed this way.
- **Users of the source in the app**: "Open the download page" and the
  release-notes fallback (`UpdateController`), About ClipForge ("Website"
  row, `openOutsidePage`), Send feedback (API, page), `get_status`
  (`site`, the built-in one: the helper does not read the app's
  settings). Help and Connect to Claude show no outside address (checked:
  none in `lib/ui/help`, `lib/ui/claude`). Third-party addresses
  (Openverse, upload pages, the speech models, brew.sh) are not ours and
  stay where they are.

### Send feedback

- **Core** (`lib/core/feedback/feedback.dart`, pure Dart):
  `buildFeedbackPayload` -> schema v1 exactly as `web/lib/feedback.ts`
  takes it: `{v:1, kind, message, email?, app:{version, build?, os},
  source:"app"}`. No `device`, no `locale`, nothing else, ever. `os` is
  `DeviceDetails.system` cut to 60 characters (the website refuses
  longer). `sendFeedback(api, payload)`: ONE POST, 15 s for all of it
  (`kFeedbackTimeout`), no redirect followed, never throws, never retries
  -> `FeedbackOutcome` kind `sent` / `offline` (no connection, no answer
  in time) / `refused` (4xx: the website's own `error` words are shown) /
  `failed` (5xx, or a 200 that is not `{"ok":true}`).
  `feedbackPageUri` (the website's form with `source=app&kind=&version=&os=`;
  the message and address are deliberately NOT put into the address),
  `feedbackRecentSends` / `feedbackLimitNote` (5 per 10 minutes),
  `FeedbackDraft`.
- **Page** (`lib/ui/feedback/feedback_screen.dart`): `openFeedback(context,
  {updateFailed, problem})`; a dialog from 700 px, a page below. Kind
  chips (**Problem** / **Idea** / **Praise** / **Question**), message,
  optional e-mail, the box **What is sent** (every row is rendered from
  the payload map itself; keys `feedback-sent-kind/-message/-email/
  -version/-system`, and the sentence `feedback-never-included`),
  **Send**. Sent -> "Sent. Thank you!". Not sent -> the plain message
  (`feedback-problem`), **Open the feedback page in the browser**
  (`feedback-open-page`), **Copy my message** (`feedback-copy`).
  `feedbackSenderProvider` is the seam for tests.
- **Draft**: `feedbackDraft` in settings.json (kind, message, e-mail),
  written 400 ms after a change and on closing, removed when sent or
  emptied. **Local limit**: `feedbackSent` (times in ms); only requests
  the website answered count, so trying again while offline is free.
- **Update log lines**: only with `updateFailed` and when a log exists:
  the tick box **Include the last update log lines** (off), the last 12
  lines (`kFeedbackLogLines`) are appended to the message under "Last
  lines of the update log:" and therefore shown in the box first; older
  lines drop out when the message would pass 5000 characters. They can
  name the install folder (the box says so).
- **Entry points**: Help > **Send feedback…** (`HelpMenuActions.sendFeedback`,
  menu id `send-feedback`), the phone's three dots on the project list
  (`home-more-feedback`) and the editor's project menu
  (`project-menu-feedback`), About ClipForge (`about-send-feedback`),
  the Help footer, Settings > About, the Update window's failed state
  (`update-send-feedback`) and "The update was not installed"
  (`update-failed-feedback`).
- **Claude**: no feedback tool, on purpose (Claude must not send e-mail
  on its own); a test fails if `lib/mcp` ever uses the sender.
- **Privacy words**: help article `send-feedback`, the Privacy part of
  `updates` (the four cases in which the app goes online), the website's
  privacy page.

### Website (`web/`) and the old Pages page (`site/`)

- `web/lib/site.ts` takes every address from links.json (`LINKS`,
  `REPO_URL`, `OLD_PAGES_URL`, `CLAUDE_SETUP_URL`); `siteUrl()` is the
  `site` of links.json on the production deployment.
- `/feedback?source=app` shows a "From the app" note
  (`components/FeedbackForm.tsx`).
- **The shared fixture** `test/core/fixtures/feedback_payloads.json`:
  `test/core/feedback_test.dart` checks the app builds exactly each
  `payload` (same keys, same order), `web/tests/app-feedback.test.ts`
  posts each to the real handler and checks the mail. Change the schema
  on both sides, then the fixture.
- Found and fixed on the way: the site linked to release files that no
  release has since 1.15 (`ClipForge-readme-*.html`, the `.mcpb`s, the
  skill zip). They are gone, and `release_assets.py --check-links` now
  scans `web/` too.
- `site/index.html`: "ClipForge has a new home", a button to the site,
  the three downloads, no automatic redirect. `site/claude-setup.html` is
  unchanged. `tool/ci/links_test.py` ties the signpost to links.json.
  The read-me generator's install steps are now compared with
  `web/app/install/page.tsx` (which got the two sentences it lacked).

### Rename readiness

`docs/RENAMING.md`: what must not change (Android package id and signing
key, the installer's AppId, `clipforge.exe`, the release file names, the
helper's name and the MCP server name `clipforge`, Windows `ProductName`
because the app-support folder hangs on it), what to keep or migrate
(Documents/ClipForge), what a rename changes (display names per platform,
strings, links.json, GitHub, Vercel) and the order of work. `kAppName`
exists and feeds the window title, the About title and the licence page;
the ~390 literals in `lib/` were NOT replaced (inside sentences that tests
compare; not mechanical) and are listed there by folder.

### Tests (new in 1.16)

`test/core/links_test.dart`, `test/core/feedback_test.dart` (fixture; a
real local HTTP server: sent, 400 with words, 429, 404, 502, 500, a 200
that is not ok, a redirect, no answer in time, nothing listening),
`test/ui/feedback_ui_test.dart` (computer and phone, the box, the draft,
not-sent with both ways out, the limit, the update-log tick box, the
addresses from an update check, what is remembered),
`tool/ci/links_test.py`, `web/tests/app-feedback.test.ts`,
`web/tests/links.test.ts`. `Fakes` got `feedbackPosts` / `feedbackAnswer`.
The Linux e2e gained step 0b: the update check hands the app a local
"website" (as a latest.json would), Help > Send feedback… posts one real
message to it.

Do not use `tester.runAsync` around `UpdateController.check` or anything
that awaits `LinksController.ready()` in a widget test: its future was
made in the fake-time zone and the test hangs. Call it and
`pumpAndSettle`.

### Not built / not verified (1.16)

- **Nothing was tried against the real website**: the build container
  cannot reach it. The feedback API is exercised through its handler in
  `web/tests` and through a local server from the app. First thing to
  check after the deployment: Send feedback from a real 1.16 app, and
  the pages named in links.json (`/install`, `/feedback`, `/help`,
  `/privacy`).
- Until the website's `RESEND_API_KEY` / `FEEDBACK_TO` / `FEEDBACK_FROM`
  are set, the API answers 503 and the app shows its words ("Feedback is
  not set up on this site yet...") with the two other ways.
- Posts from the app are not asked for Turnstile (as designed in
  `web/lib/feedback.ts`); the rate limits on both sides are best effort.
- Not on real devices: the page on a phone with the keyboard open, the
  browser opening on Android (`clipforge/update` channel `openUrl`,
  unchanged code).
- The root `README.md` still links to the Pages address (the signpost).
  Change it to the website once the deployment is confirmed.
- The helper's `get_status` shows the built-in site address, not one
  remembered from a later latest.json.

## Finding things (1.15.0, 19 Nov 2026)

Owner (non-technical, compares to CapCut) approved a reorganisation after a
read-only audit of the menus and settings: "this version is about finding
things", "think about mobile as well". NO new editing feature; every
keyboard shortcut and every action of 1.14.1 still works.

### The menu tree (`lib/ui/app_menu.dart`)

ONE tree, `buildMenuTree(editor, help:, home:, platform:)` -> `MenuNode`s,
drawn twice: `buildAppMenus` (macOS `PlatformMenuBar`: adds the app menu
with About / Services / Hide / Quit, and Window before Help) and
`WindowMenuBar` (Windows / Linux, `MenuBar` in the window). They cannot
drift apart any more. `describeMenuTree` turns the tree into text;
`test/ui/menu_tree_snapshot.txt` is the full snapshot for macOS, Windows
and Linux (regenerate: `UPDATE_MENU_SNAPSHOT=1 flutter test
test/ui/menu_tree_test.dart`).

```
File            New project (Ctrl/Cmd+N) · Open project file… (Ctrl/Cmd+O) |
                Rename project… · Publishing notes… · Back to projects |
                Export… (Ctrl/Cmd+E) · Export several… · Export subtitles (.srt)… |
                Settings… (Ctrl/Cmd+,) | Quit (Linux Ctrl+Q) / Exit (Windows Alt+F4)
                (macOS: Quit is in the app menu, as on every Mac)
Edit            Undo · Redo · History (Ctrl/Cmd+Shift+H) | Duplicate (Ctrl/Cmd+D) ·
                Copy settings · Paste settings (Ctrl/Cmd+Shift+C / V) · Delete |
                Find in the text… (Ctrl/Cmd+F)
Add             Videos or photos… · Music or sound… · Voice recording… · Title ·
                Caption… · Subtitle file (.srt)… · Overlay video or photo… ·
                Good moment marker (M)
Clip            Split (S) · Start at playhead (I) · End at playhead (O) ·
                Freeze frame · Remove silences… · Crop and position… ·
                Rotate right · Move earlier · Move later |
                Make a short from here… · Make shorts from markers… · Good moments…
Sound           Fit music to video · Line up voice with video · Separate sound… ·
                Put sound back · Add sound track · Lower music under speech ·
                Copy music credits
Text and speech Text window (Ctrl/Cmd+Shift+T) · Transcribe speech… ·
                Captions from speech… · Remove filler words… · Automatic cuts…
                (the four speech items only where a speech service exists)
View            Zoom in (+) · Zoom out (-) · Snap to playhead and edges ·
                Show sound waves | Shape ▸ · Video size ▸
Playback        Play/Pause (Space) · Play backwards (J) · Pause (K) ·
                Play forwards (L) | Go to start (Home) · Go to end (End) ·
                Previous frame (Left) · Next frame (Right) |
                Previous speech start · Next speech start (Ctrl+Left / Right shown
                on Windows / Linux only)
Help            ClipForge Help (F1 / Cmd+?) · Keyboard shortcuts · Show the tour ·
                What's new | Connect to Claude… · Check for updates… |
                Send feedback… (1.16) · Copy version info · About ClipForge
```

Where the items the owner did not list went: **Publishing notes…** and
**Export several…** in File (next to Rename and Export); **Make shorts
from markers…** and **Good moments…** (the markers list) in Clip, under
"Make a short from here…"; **Subtitle file (.srt)…** (was "Import
subtitles") in Add; "Check for updates automatically" left the Help menu
for Settings; the phone's "Smooth preview" and "Show sound waves" left
More for Settings. "Play" / "Pause" (one item that changed its name) is
"Play/Pause", because K is "Pause" now.

Keys: `windowMenuShortcuts` handles only what nothing else does (Ctrl+N,
Ctrl+O, Ctrl+E, Ctrl+Shift+H, Ctrl+Shift+T, Ctrl+comma, F1, Ctrl+Q on
Linux); every other key shown is done by the editor's own `_onKey`
(unchanged). `menu_tree_test.dart` keeps a list of every shortcut the
1.14.1 menus showed and fails when one is gone or shown twice.

### One source for "can it be done, and why not" (`lib/ui/editor/`)

- `acts.dart`: `enum Act` (every action of the editor), `actLabel`,
  `actIcon`, `actHint`, and `ActionEntry` (label, icon, `reason`, `checked`,
  `mixed`, `onTap`). No heavy imports: the menu bar uses it.
- `editor_actions.dart`: `EditorActions(session)` with `whyNot(act)` (null:
  possible; else a short lower-case reason without a full stop, e.g.
  "select a music clip"), `checked`, `mixed`, `entry(context, act)` and
  `run(context, act)`. ALL enable conditions live here. Also the helpers
  that used to be private to the editor screen (`toggleTextWindow`,
  `findInTextWindow`, `toggleHistory`, `openCrop`, `openPublishingNotes`,
  `deleteSelection`, `frameStepFor`).
- What only the screen can do (export needs the autosaver, rename needs the
  store, play backwards has a timer) goes through `EditorSession.hooks`
  (`EditorHooks`, set in `_load`).
- Users of the source: the menu bar (`_updateMenu` builds
  `EditorMenuActions(entries: {Act: ActionEntry})`; a disabled item's label
  is "<label> (<reason>)" on both bars), the side panel and phone tool bar
  (`buildToolActions`; a greyed button's tooltip is "<label>: <reason>"),
  the phone sheets (`ActionTile`: second line "Not now: <reason>") and the
  context menu.
- `EditorSession.playheadClip` (a ValueNotifier<int>) tells the bars and
  the menu when the playhead moves onto another clip ("Freeze frame" needs
  a video there) without listening to every frame.
- On the project list the editor's items are greyed without a reason (a
  whole greyed menu explains itself; nine menus of "(open a project
  first)" would be noise).
- To add an action: a value in `Act` + its label / icon (the switches are
  exhaustive, the compiler lists the places), its condition in `whyNot`,
  its effect in `run`, and a line in `buildMenuTree` (then update the
  snapshot).

### Timeline context menu (`action_sheets.dart`, `timeline_view.dart`)

`contextActs(TimelineTarget, session)` is THE list per kind (clip / sound /
title or caption / overlay / marker / empty place);
`showTimelineContextMenu` selects the item first (so the reasons are about
it) and shows a popup menu at the pointer in a wide window, a sheet in a
narrow one. Triggers: `onSecondaryTapUp` everywhere; `onLongPressStart` on
lane blocks, markers and the background; a clip keeps "hold and drag to
move" - a long press that is let go without moving 10 px opens the menu
instead (`_pressStart/_pressUpdate/_pressEnd`). "Edit" is in the list only
in a narrow window (computers have the side panel).

### "Lower music under speech": one truth

`lowerMusicState(project)` in `lib/core/editor/sound_tracks.dart` ->
`LowerMusic.none / some / all` over the sound tracks that are not speech.
The per-track switches (`SoundTrack.duck`, the track menu and the selected
sound's panel) are what the export uses. The project-level control (side
panel `DuckMusicSwitch`, Sound menu, context menu) only shows that state
and sets every such track (`setDuckMusic`; from "some" it turns all on).
`Project.duckMusic` is still stored but is now just the default for music
tracks made later, kept equal to "all" by `_editTrack` (so Claude's
`duck_music` reads the same thing). Tests: `test/core/lower_music_test.dart`,
`test/ui/v115_actions_test.dart`.

### Settings (`lib/ui/app_settings.dart`, `lib/ui/settings/settings_screen.dart`)

`AppSettings` (a ChangeNotifier over `AppPrefs`, `appSettingsProvider`) is
the single live source; the Settings page, the View menu (through
`EditorHooks.setSnapping / setSoundWaves`), the editor (`_onSettings`
copies it into the session's notifiers at once) and the Export window all
use it. The automatic update check stays in `UpdateController`
(`autoCheck` / `setAutoCheck`), which Settings shows.

Keys in `settings.json` (all "off" flags, so a missing file means the
defaults):

| Key | Kind | Meaning |
|---|---|---|
| `snappingOff` | flag | Snap to playhead and edges off |
| `soundWavesOff` | flag | Show sound waves off |
| `smoothPreviewOff` | flag | Smooth preview off (phones) |
| `textDock` | text | `right` / `below` (Text window position) |
| `textWidth`, `textHeight` | text | Size of the Text window |
| `graphicsCardOff` | flag | Use graphics card off (1.15: remembered) |
| `suggestionsOff` | flag | Show suggestions off |
| `hint.<id>.off` | flag | "Don't show again" for one suggestion |
| `hintsOff` | text | The ids with `.off`, comma separated (for "Show hidden suggestions again") |
| `hint.<id>.<projectId>` | flag | Closed or used in this project |
| `hint.<id>.ever` | flag | A once-ever suggestion was closed or used |
| `textOpened` | flag | The Text window was opened at least once |
| `exportedOnce` | flag | An export was started at least once |
| `whatMoved115Seen` | flag | The "What moved" note was shown (or not needed) |
| `lastRunVersion` | text | The version that ran last |
| `updatedLineSeen` | text | The version whose "Updated to" line was closed |
| `updateCheckOff`, `updateLastCheck`, `updateSkipBuild` | | as before |

`openSettings(context)`: a dialog from 700 px wide, a page below. Sections:
Editing, Text window (not on phones), Export, Suggestions, Updates, Claude
(only where `claudeHelperProvider.supported`), About (About ClipForge, Copy
version info, What's new, Licences = Flutter's licence page). "Default
export destination remembered" from the proposal was NOT built (optional;
the destination is chosen per export).

### Suggestions (`lib/ui/editor/suggestions.dart`)

`kSuggestions` is the registry: `Suggestion(id, priority, scope, icon,
when, message, buttons)`. `SuggestionController` (one per open editor)
listens to the editor, playback, the sound pictures, the selection and the
settings, waits 400 ms, and picks the highest priority whose `when` is true
and which is not closed. It changes nothing while the video plays or while
the editor's route is not the current one (a dialog or sheet is open), and
`current` is null during playback. `SuggestionBar`: computer - a 30 px bar
under the top bar; phone - a line above the tool bar inside a `Dismissible`
(48 dp buttons, on a second line under the words).

| id | priority | scope | when | button -> action |
|---|---|---|---|---|
| `voice-as-music` | 90 | project | a sound that is not linked to a clip and whose name or length says "voice" (`guessSoundRole`) | Line up with the picture -> `lineUpVoice` |
| `fit-music` | 80 | project | music (>= 10 s, not looped) ends > 2 s after the video, or starts at the start and ends > 3 s before it | Fit to video -> `fitMusic` |
| `lower-music` | 70 | project | >= 3 s of music on a track that is not lowered overlaps known speech, and the state is not "all" | Lower the music -> `setDuckMusic(true)` |
| `small-first-clip` | 60 | project | video size "Same as the first clip" and the first clip's short side < 700 | Use 1080p -> `setVideoSize` |
| `clip-shape` | 50 | project | a clip whose shape differs > 2 % from the canvas, fit = fit, framing untouched | Fill / Blur -> `setClipFit`; Crop… -> `openCrop` |
| `remove-silences` | 40 | project | a video clip >= 60 s with speech and >= 10 s of pauses > 1.5 s | Remove silences… |
| `captions-from-speech` | 30 | project | a speech service, `canTranscribe`, no captions, >= 5 s of known speech | Captions from speech… |
| `open-text` | 20 | ever | captions exist and `textOpened` is not set | Open Text |
| `who-is-speaking` | 10 | ever | a voice clip exists | See who is speaking -> help article |

"Known speech" is `session.pictures.speakers` (the sound pictures of
1.13), i.e. only what was already worked out; with "Show sound waves" off
the three speech-based suggestions never fire. A trigger must never start
an analysis.

Three more lines are not in the registry because they are not in the bar:
the long-upright-video note and the first-export line in the Export window
(`_longNote`, `_firstExportNote`; `hint.long-upright.<projectId>`,
`exportedOnce`; shown only with a non-null `settings`), and "Updated to X ·
What's new" on the project list (`UpdatedLine`, driven by `lastRunVersion`;
the 1.14 outcome snack is skipped when the line shows, unless it carries
the folder note).

**To add a suggestion**: add one `Suggestion` to `kSuggestions` (a new id
that never changes, a priority that is not taken, a cheap `when` over
`SuggestionContext`, the message, one or a few `SuggestionButton`s), add
its line to the "suggestions" help article and to the table above, and a
test in `test/ui/v115_suggestions_test.dart` (the first test lists the ids
in priority order, so it fails until updated).

### Phone layout (`tools.dart`, `action_sheets.dart`, `editor_screen.dart`)

- Bottom bar, nothing selected: Add (`tool-add`), Text (`tool-text`),
  Split, More (`tool-more`). `showAddSheet`: `kAddActs` as `ActionTile`s.
- Selected: that item's tools + More. Clip: Done, Split, Speed, Look,
  Sound, More, Delete (7 x 48 dp fits 360). Sound: Done, Edit, Fit, More,
  Delete. Title: Done, Edit, Duplicate, More, Delete. While something is
  selected, the + next to Play (`transport-add`) opens the Add sheet, so
  adding "after the selected clip" stays possible.
- `showMoreSheet`: `moreGroups(session)` -> headings Clip / Edit / Sound /
  Text with `ActionTile`s; phone words where they differ (`_phoneLabel`:
  "Trim start to here" = Start at playhead).
- Top bar (narrow): Back, name, save sign, Undo, Redo, Export and ONE
  `PopupMenuButton` (`project-menu`): Shape and size (`showShapeAndSizeSheet`),
  Fade in and out, Publishing notes, Text, History, Markers (the good
  moments list), Settings, and Help (added: the "?" had no other place).
  The Shape button and "?" are in the top bar only in the wide layout.
- `kWideLayoutWidth` is 840 (was 900): tablets and landscape phones get
  the side panel. Below 960 the Text window docks under the preview even
  when set to "right" (no room).
- `ToolBar`: buttons >= 48 x 60; when they do not fit it scrolls and shows
  a fade with a chevron at the right (`tool-bar-more-to-the-right`).

### What moved, tour, words

- `lib/ui/help/what_moved.dart`: `showWhatMoved` once, from
  `_versionNotes` in the home screen: an existing user (tour answered)
  whose `lastRunVersion` is older than 1.15 or missing. A first install
  gets neither this nor the "Updated to" line. Buttons: What's new, Show
  me Settings, OK.
- Tour: step 3 (`add-media`) points at the phone's Add button and says
  what it lists; step 7 (`shape`) points at the project menu on phones
  (the Shape button on computers) and mentions Settings. Anchors are
  unchanged ids (`TourIds.addMedia`, `TourIds.shape`), `tour_test.dart`
  still checks them at 390x844 and 1280x800.
- `test/words_test.dart`: a list of banned variants ("As first clip",
  "Back to start", "Move clip earlier", "Check automatically", "Import
  subtitles", "audio" in a sentence, old menu paths ...) checked in the
  strings of `lib/ui`, the help and the Claude guide.

### Tests (new in 1.15)

`test/ui/menu_tree_test.dart` (+ snapshot), `v115_actions_test.dart`,
`v115_settings_test.dart` (page <-> prefs, What moved, Updated line),
`v115_suggestions_test.dart`, `v115_phone_layout_test.dart` (360x760,
900x600 tablet, context menus), `test/core/lower_music_test.dart`,
`test/words_test.dart`, `tool/ci/release_assets_test.py`. Test helpers in
`test/ui/fakes.dart`: `tapAdd`, `tapMore`, `tapProjectMenu`; the harness
prefs start "settled" (no What moved, no Updated line, suggestions off) so
tests about other things are not disturbed. The Linux e2e gained step 4b
(the nine menus, a greyed item's reason, Settings <-> the editor's
snapping, the context menu, a suggestion).

### Not built / not verified (1.15)

- Not on real devices: the phone layout, long press vs. hold-and-drag on a
  real touch screen, the macOS menu bar (only its tree is tested), a
  right-click with a real trackpad.
- macOS cannot show a tooltip or a dimmed second line in a native menu, so
  the reason is part of the label on both bars (same words everywhere).
- "Default export destination remembered" (optional in the proposal).
- The suggestion for missing files from the audit: the editor already says
  so before an export and on the clip ("Find file").

## Three downloads (1.15.0, 19 Nov 2026)

Owner: "the small HTML guide should be part of the install and not
separate; let's not have 6 files, let's have 3 - Mac, Windows, APK for
Android - and no need for the old one (32-bit phones) as well."

- `tool/ci/release_assets.py` is THE list: `DOWNLOADS` =
  `ClipForge-Setup.exe`, `ClipForge-macos.zip`, `ClipForge-android.apk`;
  `UPDATER_ONLY` = `ClipForge-windows.zip`, `latest.json`. `--check-dir`
  (the release job: the publish folder must hold exactly these five) and
  `--check-links` (the check job: `site/index.html` has exactly the three
  download links, and no `releases/latest/download/<name>` anywhere on the
  site, in `lib/`, `assets/`, the READMEs, the Claude files or the
  installer script names a file outside the list). Test:
  `tool/ci/release_assets_test.py`.
- The release job copies the five files into `$RUNNER_TEMP/publish` under
  their fixed names and uploads exactly those by name (no globs). No
  versioned duplicates (the version is in the release title, in
  latest.json and inside the files), no `ClipForge-readme-*.html`, no
  `.mcpb`, no skill zip. A run without the installer no longer publishes
  (it was a warning before): `ClipForge-Setup.exe` is the Windows download.
  The workflow's artifacts are unchanged otherwise (the read-mes, the
  `.mcpb`s and the skill zip are still uploaded as run artifacts for
  debugging, and the `.mcpb` is still built because the app bundles it).
- The guide: installed by the installer (and offered on its last page,
  Start menu "ClipForge read me"), and beside `ClipForge.app` in the Mac
  zip (the release job checks it is in there). `make_readme_html.py` now
  has one Windows route (the installer); its test still fails when its
  steps and `site/index.html` drift apart.
- No 32-bit Android: the workflow builds `android-arm64` only (and fails
  if an armeabi APK appears), `make_latest_json.py` has no `android32`,
  `updatePlatformKey('android', only32Bit: true)` is null. A 32-bit phone
  that still runs 1.14 finds no `android32` entry in the new latest.json:
  its "Update" opens the download page, where the 64-bit APK will not
  install. That is the accepted end of the line for those phones.
- `site/index.html`: three rows, three links; the zip alternative, the
  32-bit link, the two "Full guide" links and the Claude extension / skill
  links are gone (one sentence says Claude is connected from inside the
  app, with the link to `claude-setup.html`). `claude-setup.html` (site and
  docs) no longer points at downloads of the `.mcpb` or the skill zip; the
  skill's folder stays in the repository (`claude/skill/clipforge-editing`).
- **`ClipForge-windows.zip` must stay in every release for now**: installed
  1.12 - 1.15 apps on Windows update from it (latest.json names it).

### Next step (evaluated, NOT done): update Windows from the installer

Letting the in-app update run `ClipForge-Setup.exe /VERYSILENT` when the
app was installed by the installer would make the zip unnecessary one day.
It was not small or safe enough for 1.15:

- The app must know it was installed by the installer (Inno Setup leaves
  `unins000.exe` next to `clipforge.exe`; a registry key
  `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{AppId}_is1`
  is the reliable sign) and must fall back to the zip for unpacked folders.
- latest.json needs a `windows-setup` entry (size + SHA-256), and the app
  must check it like the zip.
- The installer has to wait for the app to close, install silently
  (`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS`), start
  the app again and report into `update-log.txt` / the result file the app
  reads at the next start; a failed or cancelled install must leave the old
  version working (the zip route has a safety copy; Inno Setup does not
  roll back by itself).
- None of this can be tested in this container; it needs the Windows CI
  job (silent install / update / uninstall exist there since 1.14.1) plus a
  run on a real PC, which is where 1.14.0's update failed.
- Only after a version that updates from the installer has been out long
  enough may the zip leave the release.

## One-click Claude install, the skill, test documents (17 Nov 2026, no app change)

(1.12 changed this: the extension is installed once and hands over to the
helper the app installs, the skill is a thin pointer, the guide is in
`claude/guide`; see the 1.12 section above.)

The owner had to hand-edit `claude_desktop_config.json` (Claude Desktop from
the Microsoft Store) to add `clipforge-mcp.exe` and found it painful. Added,
without touching the app or the version (still 1.9.0):

- **Claude Desktop extension (.mcpb)**, one per system:
  `ClipForge-<version>-build<n>-claude-{windows,macos}.mcpb`. A zip with
  `manifest.json`, `icon.png` (the app icon, 256 px), `server/clipforge-mcp(.exe)`,
  `server/fonts/` (all title fonts + licences; `locateFonts` finds `fonts/`
  next to the program) and `server/CLAUDE.md`. Manifest: `manifest_version`
  "0.3", name `clipforge`, display name "ClipForge", version = app version
  (the full build line is at the end of `long_description`), server type
  `binary`, `entry_point` `server/clipforge-mcp(.exe)`, `mcp_config.command`
  `${__dirname}/server/clipforge-mcp(.exe)`, no args, the 45 tools listed
  (name + first sentence), `compatibility.platforms` `win32` / `darwin`. No
  `user_config` (projects folder and FFmpeg are found automatically; the
  manual config stays the way to pass `--projects-dir`).
- **Builder**: `docs/tools/build_claude_bundles.py` (Python, standard
  library). `mcpb --binary … --platform windows|macos|linux --version
  --build --display --out`: stages the files, starts the staged program
  (tools/list + get_status) and fails when its tools differ from
  `lib/mcp/tools.dart`, when it does not find the bundle's own fonts or
  reports another version; writes and validates the manifest (required
  fields, only keys the 0.3 schema allows, every named file present), zips
  with the program marked 0755 whatever system builds it, then reads the
  file back. `--no-run` (program built for another system) takes the tool
  names from the source. `skill` zips `claude/skill/clipforge-editing` with
  the folder at the zip root (`ClipForge-<version>-claude-skill.zip`) after
  checking frontmatter, length and links.
- **CI**: check job builds the skill zip (uploaded, every push) and
  assembles a Linux .mcpb as a test of the script; the Windows and macOS
  jobs build and upload their .mcpb (`archive: false`, like the APK). The
  macOS job unpacks it again and checks the program is executable, its
  ad-hoc signature verifies and `--version` matches. `docs/claude-setup.html`
  is copied into both downloads as "Connect Claude to ClipForge.html".
- **Skill**: `claude/skill/clipforge-editing/` — `SKILL.md` (workflow:
  get_status → find project / files → get_project → plan and "Go ahead?" →
  safety copy → dry run → edit → export and poll; the open-in-app rule;
  never delete; what Claude cannot know; not available), `recipes.md`
  (podcast clean-up, with music, sound only, family montage, sport, vertical,
  vertical with the person in shot, picture-in-picture, **shorts from a long
  video**, finished look), `tools.md` (all 45 tools), `troubleshooting.md`.
  Shorts recipe is honest: Claude cannot see or hear, so moments come from
  the owner's times, from the pauses `remove_silences dry_run` lists, or
  from an existing .srt; it improves when transcription is built.
  `claude/CLAUDE.md` stays the single-file version (Claude Code, shipped
  next to the program); it got a pointer to the skill, the seven tool names
  it never mentioned and the shorts recipe.
  `test/mcp/claude_guides_test.dart` keeps them in step: every registered
  tool is named in `tools.md` and in `CLAUDE.md`, no guide names a tool
  that does not exist, and the skill keeps the upload shape.
- **Owner guide**: `docs/claude-setup.html` (self-contained, light / dark,
  phone-readable): A extension, removing the old manual entry (which lines),
  restart; B skill upload; C Claude Code one-liner; D "What version of
  ClipForge are you connected to?"; problems; manual config as fallback.
- **Test documents**: `docs/testing/claude-control-test-3.md` (31 steps for
  Claude with 1.9.0: status, short answers / paging, silence dry run, sound
  tracks / ducking / loop, the lock with the owner opening the project,
  export job + poll + cancel, sound-only, SRT round trip, picture, overlay,
  titles in Hebrew / Russian, copies, undo / redo, robustness);
  `gen_checklist.py --round 4-phone` → `ClipForge-Test-Round-4-Phone.html`
  (42 steps for the Samsung phone, driven by ChatGPT through Windows Phone
  Link mirroring: touch wording, phone UI names, "ask the owner" for sound
  and smoothness, never delete, exports go to the gallery; its own browser
  storage key `clipforge-round4-phone`); `--round 4` regenerated for 1.9.0
  (61 steps: + "New in 1.9.0": lock is invisible, long export, Claude names
  the same version). Round keys are text now ("3", "4", "4-phone").

**Checked against live documentation on 17 Nov 2026:**
- MCPB: github.com/anthropics/mcpb `README.md`, `MANIFEST.md` (spec 0.3,
  last updated 2 Dec 2025; 0.4 only adds the `uv` server type) and
  `schemas/mcpb-manifest-v0.3.schema.json`. The generated manifests validate
  against that schema (python `jsonschema`, locally). The official
  `mcpb validate` / `mcpb pack` CLI was NOT run (npx was not allowed in the
  build container); the file is a plain zip as the README describes.
- Claude Desktop install of a custom extension (support.claude.com, "Getting
  started with local MCP servers on Claude Desktop"): Settings > Desktop app
  > Manage next to Extensions (older layout: Settings > Extensions) >
  Advanced settings > Extension Developer > Install Extension… > choose the
  .mcpb. "For privately distributed extensions, users will need to install
  updated .mcpb files manually."
- Skills (support.claude.com, "Using skills in Claude", "How to create
  custom skills"): Customize > Skills > "Upload a skill"; the zip holds the
  skill folder at its root; skills enabled in the account also load in
  Claude Code (v2.1.273+) under `~/.claude/skills/synced/`.
- Claude Code (code.claude.com/docs/en/mcp): `claude mcp add [options]
  <name> -- <command> [args...]`, `--scope user`; prints "Added …".
  **Finding:** the same page says that on Windows Claude Code ends the
  server's *process tree* when it disconnects (session end). The export
  worker is a normal child of the server on Windows (not detached), so
  closing Claude Code during an export probably kills the render there; the
  guides tell the owner to keep it open. Detaching the worker on Windows
  (without the console window popping up) would fix it — not done (no app
  work in this round).

**Assumed, not verified:**
- Double-clicking a .mcpb opens Claude Desktop's install dialog (the mcpb
  README says so for "Claude for macOS and Windows"; not confirmed for the
  Microsoft Store build — the guide gives the Settings route as plan B).
- Where Claude Desktop unpacks extensions on a Mac
  (`~/Library/Application Support/Claude/Claude Extensions`, used in the
  `xattr` command of the guide) and whether macOS quarantines the unpacked
  program at all (files written by Claude itself normally are not
  quarantined). The program is ad-hoc signed, not notarized, Apple Silicon
  only.
- That Claude Desktop keeps the executable bit when unpacking (the zip
  stores mode 0755 with Unix attributes).
- The Windows and macOS CI steps themselves (written here, first real run
  is the next workflow_dispatch); Python is `python` on the Windows runner
  and `python3` on macOS.
- Everything in the phone checklist about Phone Link behaviour (drags,
  paste between PC and phone, sound) and what the phone does when rotated
  or when the app is in the background during an export: the steps ask the
  tester to write down what happens.

## Drag and drop, graphics card

**Drag and drop** (computers only): `desktop_drop` 0.8.4 (0.9.x needs
cross_file 0.4, which share_plus 13 does not allow; 0.8.4 pins dbus 0.7,
which moved wakelock_plus from 1.8.2 to 1.8.0 — only a dbus bump and a
web-only change between them). Seam: `FileDropService` in `services.dart`
(`FakeFileDropService` in the tests); UI in `lib/ui/file_drop.dart`.
Home: videos/photos/music/.srt start a new project, opened with them in it
in the order the system hands them over (macOS: the dragged selection,
Windows: Explorer's order, Linux: the uri-list); `.clipforge.zip` opens as
a project. Editor: `addDroppedFiles` in `import_actions.dart` (same probe,
problem list and insertion rule as "Add media"; over the timeline, between
the nearest clips via `timelineDropLocators`). A folder gives the files
directly inside it, sorted by name. macOS: no entitlement needed (sandbox
off); "file promise" drops (Photos, Mail) land in a temporary folder and
are copied to the app's media folder. Android: the plugin registers a drag
listener on the window; `MainActivity.onStart` removes it again. Verified
with a real XDND drop on Linux (Xvfb + xdotool + a GTK drag source): new
project in drop order, unsupported file listed, insert on the timeline.

**Graphics card export.** `lib/media/video_encoder.dart` (pure: platform +
available encoders + quality → arguments) and `hardware_encoding.dart`
(asks `ffmpeg -encoders` once, test-encodes 10 black frames with each
candidate, remembers the result for the run; `EncoderFallbackJob` redoes a
failed or incomplete hardware export once with libx264 and then keeps to
libx264 for the run). Bundled FFmpeg 8.1.2 builds contain: macOS
`h264_videotoolbox`; Windows `h264_mf` only (no nvenc/qsv/amf); Android
`h264_mediacodec`. Settings: VideoToolbox `-q:v 65` / 55 on Apple silicon
(bitrate on Intel Macs, where FFmpeg refuses `-q:v`), NVENC `-cq 23`, QSV
ICQ 23, others ~0.12 bit/pixel VBR; small files capped at 2500k like x264;
all nv12 (8-bit 4:2:0), High profile, limited range, +faststart, AAC.
**Hardware encoding has never run on real hardware** (no GPU here; on this
Linux box nvenc/qsv fail their test encode and the export uses libx264).
Preview: desktop VideoControllers get `hwdec=auto-safe` (media_kit default
was `auto`); Android keeps media_kit's `auto-safe` (`no` in emulators).

## Help and tour

Owner asked: "when we first open, it will ask if we want a guide and then
show us around, and will have a help file that we can search". All in
`lib/ui/help/`, no new dependency.

- **First launch** (`showFirstLaunchOffer` in `home/home_screen.dart`):
  "Would you like a quick tour?" with **Show me around** / **Not now**
  (Not now also says the tour is in Help). Answered once, remembered in
  `<application support>/settings.json` (`lib/ui/app_prefs.dart`,
  `appPrefsProvider`; tests and the e2e runs use `MemoryAppPrefs`).
- **Tour** (`tour.dart`): `TourAnchor(id: TourIds.x)` wraps the real widgets
  (registry, not GlobalKeys, so a widget can appear on several pages);
  `TourController` (`tourControllerProvider`) holds the steps;
  `TourOverlayHost` sits in `MaterialApp.builder` above the navigator and
  draws a spotlight + caption card (Back / Next / Skip tour, "Step n of 8")
  that never covers its target when there is room, and is always fully on
  screen. Taps on the app are blocked while it runs; Esc skips; reduced
  motion makes the spotlight jump. 8 steps (`buildTourSteps`):
  1 New project (desktop text adds drag-and-drop), 2 Open project file,
  then the sample project opens: 3 Add media (1.15, phones: the Add
  button and what it lists), 4 timeline, 5 Split (first
  clip selected), 6 clip tools — phone: the Speed/Look/Sound tool-bar
  buttons; desktop: the side panel with Sound open — 7 Shape (1.15,
  phones: the project menu, which has Shape and size) , 8 save sign +
  Export. End card: keep or delete the sample. Skip deletes it. The home
  screen and the sample's editor attach `TourHomeHooks` / `TourEditorHooks`.
  "Show the tour" from Help or the macOS menu closes an open editor (saving)
  and starts on the project list.
- **Sample project** (`tour_sample.dart`): the bundled 5 s 640x360 stereo
  video `assets/tour/sample.mp4` (86 KB, ffmpeg `gradients` + two sines;
  its facts are constants checked against the file by a test) plus two
  photos drawn with `dart:ui` into the app media folder; cleaned up with
  the other app media when the project is deleted.
- **Help** (`help_screen.dart`, `help_content.dart`, `help_search.dart`):
  51 articles (1.7) in `assets/help/help_en.md` (format at the top of the file
  and in README "Help and tour"); per-language file, so translation is a
  copy. Search is pure Dart: exact / stem / prefix / typo match (optimal
  string alignment distance, 1 edit for 4–5 letters, 2 for 6–8, 3 above),
  title x3, keywords x2.5, text x1, stop words ignored, a known word is not
  also read as a typo; "Did you mean" + popular topics when nothing is
  found. Entry points: "?" on the home and editor app bars (1.15: on a
  phone the editor's is in the project menu, the three dots), the Help
  menu > ClipForge Help / Show the tour / What's new, and `HelpHint` "?" buttons next to
  Clean up sound, Voice focus, Sound from, Lower music under speech, Remove
  silences, Fit to frame, Use graphics card, plus "Which shape should I
  use?" in the Shape menu (sheet on phones, dialog on computers).
- Tests: `test/ui/tour_test.dart` (every step's anchors must be on screen at
  390x844 and 1280x800 — a renamed or removed anchor fails the test),
  `help_screen_test.dart`, `help_content_test.dart` (parsing, links, the
  owner's typos, bold labels exist in `lib/ui`). Screenshots
  `docs/screenshots/tour_*`, `help_*`, `first_launch_*`.
- Not verified on a device: the tour on a real phone/Mac/Windows (only
  widget tests and screenshots), and writing the sample files on Android.

## Long videos (40 minutes)

Measured with 40-minute 720p/1080p fixtures (exports exact, sync ±27 ms,
memory flat); these were the slow spots, now fixed:

- **Timeline** (`timeline_view.dart`): only a window around the view is
  built and painted (the view plus ≥1600 px each side, moved in half-view
  steps as it scrolls; `_zoomOffset` builds the right window in the frame of
  a zoom). The ruler paints only that window; the scrolled content is a
  `RepaintBoundary`; the playhead is a separate layer over the scroll view
  that repaints from the position/scroll listenables without a rebuild.
  Video blocks show thumbnail tiles (one per picture width, each the
  nearest strip frame) only inside the window. The dragged / selected
  items stay built. Timeline width capped at 4 M px
  (`EditorSession.maxTimelinePixels`; affects only projects > ~2.3 h).
- **Clip timing** (`Project`): start times and length are computed once
  per (immutable) project in an `Expando`: `clipStartMs`/`durationMs` O(1),
  `clipIndexAt` binary search (plain scan if starts are ever not ordered).
  Property test against the old maths: `test/core/project_timing_test.dart`.
- **Thumbnails** (`lib/media/media_jobs.dart`, `ThumbnailStripEngine`): one
  ffmpeg run per file writes ≤ ~300 small frames (1 s apart up to 5 min,
  8 s for 40 min; files > 60 s decode keyframes only with
  `-skip_frame/-discard nokey -skip_loop_filter all`), cached per
  (path, size, mtime, interval). `ThumbnailCache` runs requests newest
  first; `getNow`/`stripNow` avoid a blank frame on rebuild. The per-time
  `thumbnail()` API is unchanged (home screen, engines without strips).
- **Remove silences**: `SilenceJobEngine.startSilenceDetection` (both
  engines; Process: `-progress pipe:1`; FFmpegKit: statistics callback)
  listens to the clip's own range only, reports progress and can be
  cancelled (dialog Cancel, quitting). The dialog shows a percentage and
  "This will cut the clip into N pieces" before applying. Big projects
  (≥150 clips+titles) are JSON-encoded on another isolate when saved.
- **Export** (`export_dialog.dart`, `lib/media/export_estimate.dart`,
  `lib/ui/long_jobs.dart`): estimated size shown (0.12 bit/pixel + sound;
  small files at their cap); free space of the target folder checked
  (Linux/macOS `df -Pk`, Windows PowerShell DriveInfo, Android StatFs):
  "Not enough free space" blocks below half the usual size, "Space is
  tight" asks below the largest size + 200 MB; phones count the gallery
  copy twice. While exporting: wakelock_plus (all platforms) and, on
  Android, `ExportService` (foreground service, dataSync/mediaProcessing,
  partial wake lock, keep-screen-on) via channel `clipforge/long_jobs`;
  "Keep ClipForge open while it exports."
- **Note**: projects of 20 minutes or more get "Long videos work, but some
  steps take longer." once (remembered in settings.json,
  `longProjectNote.<id>`).

Harness numbers (debug build, Xvfb, software GL, load 7–11 from other
work), before → after: scroll at 1500 px/s build p50/p90 39/56 → 1/28 ms
(one clip), 32/79 → 0/49 (480 pieces); max-zoom first frame 416 → 117 ms,
960 → 78 ms; scroll at max zoom 342 → 22 ms; play 15 s build p50 47 → 4
(one clip), 36 → 5 (pieces), longest stall 648 → 144 ms; apply 480 cuts
1548 → 241 ms; thumbnails after the cut 238 ffmpeg runs/55 s → 0 (one strip
of 300 frames at import, 6.4 s under load, ~2 s idle). Worse: fast
jump-scrolling at the smallest zoom (whole window rebuilt each frame,
~200 tiny blocks): build p50 6 → 35 ms.

Not verified: the Android service and free-space channel on a device
(only `flutter build apk --debug`), Windows free space (PowerShell),
wakelock on macOS/Windows, FFmpegKit progress/cancel of the silence job.

## Version numbers and releases

Owner: "add version numbers to make sure we are aligned, and the release
date and time" (they test on Mac, Windows and Android, often with an AI
tester, and must say exactly which build they ran).

- **One line per build**, `lib/core/build_info.dart` (pure Dart, shared by
  the app and clipforge-mcp): `ClipForge 1.4.0 (build 21) · 16 Nov 2026,
  07:20 UTC · 877e482`; "local build" instead of a time when built without
  CI's details. Sources: `FLUTTER_BUILD_NAME`/`FLUTTER_BUILD_NUMBER` (Flutter
  puts them in every `flutter build/run/test` from pubspec or
  `--build-name/--build-number`; bin/build_mcp.dart passes the same to
  `dart compile exe`, defaulting to pubspec) and `CLIPFORGE_BUILD_TIME` /
  `CLIPFORGE_COMMIT` / `CLIPFORGE_CHANNEL` via `--dart-define-from-file`.
- **CI**: the `check` job computes version (pubspec), time (UTC, once per
  run), short SHA and the display line (job outputs); every build job writes
  `build/clipforge_build.json` and passes `--build-name <version>
  --build-number <run number> --dart-define-from-file=build/clipforge_build.json`
  to flutter build and build_mcp. CI fails if clipforge-mcp's `--version`
  differs from the computed line (Linux, macOS) or version (Windows).
  Artifacts: `ClipForge-<version>-build<run>-{android.apk,
  android-old-32bit-phones.apk, windows.zip, macos.zip}`; the zips hold
  `Read me first.html` (1.14.1, instead of `Release notes.txt`; see
  "Read me first.html in the downloads" below). Android versionCode
  keeps Flutter's per-CPU offset (2000+run arm64, 1000+run armv7, so a new
  run always installs over an older one); macOS CFBundleVersion and the
  Windows file version (1.4.0.<run>) are the run number.
- **Where it shows**: project list bottom line (tap: About), About ClipForge
  (macOS app menu replaces the system About panel; Windows/Linux Help menu;
  phones: More (three dots) on the project list), Help footer, "Copy version
  info" (line in UTC + raw details + system/device/screen; Android model via
  channel `clipforge/device` in MainActivity), Help > What's new (generated at
  load from the bundled CHANGELOG.md, `lib/ui/help/whats_new.dart`), help
  article `about-version`, `clipforge --version` (Linux), MCP `--version` and
  `get_status` (`build` object). The app shows local time; copies use UTC.
- Tests: `test/core/build_info_test.dart`, `test/ui/whats_new_test.dart`
  (newest CHANGELOG version == pubspec version; bold labels exist),
  `test/ui/about_test.dart`, MCP tools/e2e tests.

**How to release a new version:**
1. `pubspec.yaml`: `version: X.Y.Z+1` (leave `+1`; CI sets the build
   number). Patch for fixes only, minor for new features.
2. `CHANGELOG.md`: add `## X.Y.Z – <day> <Month> <year>` at the top with a
   few plain-language bullets (bold only for the app's own labels).
   `flutter test` fails if the two disagree.
3. Commit and start the workflow (workflow_dispatch). CI does the rest:
   build number, time, commit, artifact names, release notes, and
   "Read me first.html" for the Windows and Mac downloads (from the
   CHANGELOG section: keep it plain Markdown - lists, bold, code, links).
4. Generate the test checklists with the build line:
   `python3 docs/testing/gen_checklist.py docs/testing/ClipForge-Test-Round-4.html --round 4 --build "ClipForge X.Y.Z (build N) · ..."`
   and the same with `ClipForge-Test-Round-4-Phone.html --round 4-phone`.
   `--round` picks the step list (ROUNDS in the script; default 4):
   3 = 1.4.0 (40 steps), 4 = computers, 1.9.0 (61 steps: new since 1.4.0 + a
   short regression core, PASS/FAIL results, "ask the owner to listen /
   watch" tags), 4-phone = the Android phone through Phone Link (42 steps).
   For Claude itself: `docs/testing/claude-control-test-3.md` (paste into a
   chat).
   Since 1.12 a release is what running apps update to: push the tag
   `v<version>` only when the build is good; the release job writes
   latest.json with the files' sizes and SHA-256. After changing
   `claude/guide/*.md` run `dart run tool/gen_guide.dart`. Keep the
   fixed-name assets and the latest.json fields: old apps read them.
   Since 1.16 latest.json also carries `links` from `tool/ci/links.json`:
   when the site moves, edit that file (and `lib/core/links.dart`) and
   release while the old address still answers.
5. The run's artifacts now also include the Claude Desktop extension
   (`…-claude-windows.mcpb`, `…-claude-macos.mcpb`) and
   `ClipForge-<version>-claude-skill.zip`; the owner's guide is
   `docs/claude-setup.html`.

History so far: 1.16 Send feedback (page, what-is-sent box, draft, local limit, update-log tick box), one source for outside addresses (links.json, in latest.json, remembered by the app), the website and the Pages signpost, RENAMING.md; 1.15 menus by task, one Settings page, suggestions, the phone layout, context menu, three downloads; 1.14.1 "Read me first.html" in the Windows and Mac downloads (instead of Release notes.txt), Windows update by replacing the folder's contents (the rename never happened on a real PC), helper must report in, cmd fallback, update-log.txt, tidy-up, Inno Setup installer; 1.14 publishing kit (destinations, export several, publishing notes, chapters, share / upload pages), shorts in the app, good-moment markers, suggest_shorts / export_kit for Claude, Connect to Claude buttons, update leftovers and apply-at-start; 1.13 Text window, sound waves, who is speaking; 1.12 self-update (banner, Windows / Mac swap, Android installer), Claude helper installed by the app + hand-over, Connect to Claude page, get_guide, self_test, Windows jobs survive Claude Code, old -> new answers, media table; 1.11 speech to text on computers (transcribe, captions from speech, gentle filler removal with put back, Transcript column, shorts for Claude, right-to-left text), unique project names, app lock fix; 1.10 voice recorded separately (asked on add, lined up by sound, linked, nudge, add_voice / align_audio); 1.9 Claude control from the owner's test (export jobs, short answers, open-in-app lock, dry runs, warnings); 1.8 Android media copies (missing-file fix), gallery search, fixed signing key, phone speed, fit/loop music, free music search, feature log; 1.7 fades, filters, text styles, snapping, duplicate / copy settings, sound-only export, frame rate, menus and keyboard; 1.6 crop and position, overlay track (picture-in-picture); 1.5 sound tracks, separate sound, adaptive silences, video size; 1.0 basic editor; 1.1 round-2 features; 1.2 review fixes +
Claude control; 1.3 Voice focus, quit crash fix, drag and drop, graphics
card; 1.4 help and tour, Windows menu bar, instant sound, History, long
videos, version numbers.

### Read me first.html in the downloads (1.14.1)

Owner: "we also need a guide for when someone downloads and reads; notes
should be in HTML format." The readers are non-technical friends on
Windows and Mac.

- **Script** `tool/ci/make_readme_html.py` (Python standard library):
  `--platform windows|macos --version --build --date --changelog --out`.
  One self-contained page (no web fonts, images or scripts; light / dark
  from the system; about 23 KB, limit 40 KB - earlier versions are dropped
  first when a changelog is long): title and one sentence, "Install on
  <system>" for that system only, First steps, Where your projects are,
  Updates, Use it with Claude, "What is new in <version>" (the version's
  CHANGELOG section through a small Markdown converter: headings, lists,
  bold, inline code, https links; everything else escaped) and the three
  sections before it folded in `<details>`, footer. It exits 1 when
  CHANGELOG.md has no section for the version (this replaces the old
  grep in the Windows and macOS jobs).
- **The words live once**, in the script (`PLATFORMS`, `FIRST_STEPS`, …).
  The install steps are the same sentences as on `site/index.html`; the
  test fails when they differ, so change both together. The Mac steps now
  lead with the macOS 15+ route (open once, System Settings > Privacy &
  Security > Open Anyway), then right-click > Open for older macOS.
- **Test** `tool/ci/make_readme_html_test.py` (unittest, run in "Analyze
  and test", which also writes the real page for both systems): steps per
  system, version, sections, balanced tags, nothing a browser would fetch
  (no script / img / link tags, no url() in the style), Markdown injection
  escaped, the size limit, a missing version, and site/index.html
  agreement.
- **Where it lands**:
  - Windows zip: `ClipForge/Read me first.html`, next to `clipforge.exe`
    (the job checks the zip for it and that `Release notes.txt` is gone).
  - Windows installer: the same folder, so `{app}\Read me first.html`;
    Start-menu entry "ClipForge read me"; last installer page "Show the
    read-me" (ticked; `postinstall shellexec skipifsilent`). The installer
    test checks the file and the entry after install and update, and that
    both go on uninstall.
  - macOS zip: at the top of the zip, beside `ClipForge.app` and "Connect
    Claude to ClipForge.html". **The macOS zip has no "ClipForge" folder
    around the app and must not get one**: `unpackMacUpdate` looks for the
    `.app` directly at the top of the unpacked zip. Double-clicking the zip
    in Finder makes a folder named after the zip with the three items.
  - Release: `ClipForge-readme-windows.html` / `ClipForge-readme-macos.html`
    (fixed names only; latest.json unchanged). The download page links to
    them as "Full guide"; GitHub serves release files as downloads, so the
    link saves the page and the reader opens it.
  - Android: no bundle, nothing added; the download page's Android steps
    were completed instead.
- **Updates**: the Windows update mirrors the new folder into the install
  folder, so a 1.14.0 install loses `Release notes.txt` and gains the
  read-me by itself (the Start-menu entry only exists after an install
  with the 1.14.1+ installer). The Mac update swaps only the `.app`; the
  read-me is not inside it.
- Not verified: everything in the workflow (zip checks, installer entry,
  the artifact / release steps) has not run yet; the pages were looked at
  in headless Chromium at 900 and 400 px only, not in Edge / Safari on
  real machines.

## Verified vs. not verified

Verified:
- 938 automated tests pass locally (ffmpeg 6.1) and on GitHub CI (ffmpeg 8.0).
- Real app driven end to end on Linux (import, playback, seek, transitions,
  speed, colour, export).
- All installers build (CI run 43767330405).
- The macOS app opened on the owner's Mac (after Privacy & Security → Open Anyway).

Not verified:
- Anything else on a real phone, Windows PC or Mac.
- Sound by ear (clean-up, ducking, volume, sync, voice focus — never
  listened to on real speech or real music; numbers above are synthetic).
- Voice focus / sound source on FFmpeg 8 (`dialoguenhance` output layout and
  delay are assumed unchanged; the integration tests on CI 8.0 check both),
  and the preview filters on the real Android/Windows/macOS players (only
  checked that the filters exist in those binaries; run on Linux mpv 0.37).
- Gallery save, share sheet, touch gestures, two simultaneous decoders on Android.
- FfmpegKit engine execution (only compiled).
- Claude control with a real Claude Desktop / Claude Code.

## Not built yet

- A detached (second OS window) Text window; an edit-by-text editor (owner
  decision); the "who speaks" summary strip; telling speech from music
  (the speech map is loudness only); two speakers on one microphone.
- Speech to text on phones, a speech engine built into the app (1.11 uses a
  program installed on the computer). (Transcripts inside project bundles
  and previewing a filler cut: built in 1.12.)
- Signed / notarized builds (the Windows installer of 1.14.1 is
  unsigned); a signature on latest.json
  (today: https + SHA-256 from the same release page); update for the
  Linux build; MCP prompts.
- Searchable music library — built in 1.8 (Openverse); Jamendo direct needs a client_id.
- Voiceover recording — no microphone in the build container.
- Saved (user-made) title styles and intro / outro templates (one-tap filters and built-in title styles exist since 1.7).
- iPhone (needs $99/year Apple account), stickers, keyframes, green screen.
- Camera-angle sync by sound for overlay items (see "Crop and position,
  overlay track"): `lib/media/sound_align.dart` (1.10) already finds the
  offset between two recordings; what is missing is the overlay side.
- Repairing drift of a separately recorded voice (stretching it), more than
  3 sound tracks.

## Owner-facing pages (claude.ai, private to the owner)

- Test checklist (Works/Problem marks stored in the page's database, collection
  `checks`, one doc per step id): https://claude.ai/artifact/MGs9WHHovRPdrC5iMd7Xbh
- Progress report: https://claude.ai/artifact/UbffQhdvRQ4p4eZ4rP56gm
- Build record (what and why): https://claude.ai/artifact/1NPfHXFn2vveebmaGSruzn

**Current state:** the owner is testing on their devices (possibly with ChatGPT
computer-use filling the checklist). The owner asked to **hold all further
building** until they report results. Read the checklist marks first.

## Building and testing (cloud container)

- Flutter 3.50.0 stable at `/opt/sdk/flutter` (download from
  storage.googleapis.com flutter_infra_release if the container is fresh).
- Android SDK at `/opt/sdk/android` (`ANDROID_HOME`). Downloading it needs
  `dl.google.com`, allowed by the cloud environment.
- Linux build needs `libgtk-3-dev libmpv-dev mpv libjson-glib-dev`; media_kit's
  CMake download of `mimalloc-2.1.2.tar.gz` is blocked by the proxy — copy it
  from an existing build dir or rebuild from a git clone of the tag.

```sh
export PATH=/opt/sdk/flutter/bin:$PATH ANDROID_HOME=/opt/sdk/android
cd video-editor
flutter analyze
flutter test                                   # all tests (1931)
flutter build apk --release --split-per-abi --target-platform android-arm64
python3 tool/ci/release_assets_test.py && python3 tool/ci/release_assets.py --check-links
python3 tool/ci/links_test.py && python3 tool/ci/make_readme_html_test.py
(cd ../web && npm ci && npm test && npm run build)   # the website; needs Node 22.18+
dart run bin/build_mcp.dart -o build/clipforge-mcp
# real app on Linux:
E2E_OUT=/tmp/e2e E2E_NULL_AO=1 LIBGL_ALWAYS_SOFTWARE=1 \
  xvfb-run -a -s "-screen 0 1280x800x24" \
  flutter test integration_test/real_app_test.dart -d linux
```

Commit WIP checkpoints with `[skip ci]` in the message; start the full build
(including Windows/macOS) with a workflow_dispatch run on the branch.

## Owner decisions and roadmap (16 November 2026)

- AI features run **on the device** (free, offline, private). Runtime: sherpa-onnx
  (spike results: DPDFNet2 48 kHz default for voice separation; Voc_FT → DPDFNet
  "high quality" on desktop; Whisper small on phones, turbo on desktop; models
  downloaded on first use with pinned SHA-256). Separation flow: separate →
  listen to Voice / Background → confirm or Swap → two level sliders.
- Owner wants **help**: first-launch "Would you like a quick tour?", 6–8 step
  tour over real buttons, searchable offline help screen, "?" hints. **Built**
  (see "Help and tour").
- **Local AI assistant**: experimental, **computer only**, downloadable and
  swappable models via a shared model manager (also used for separation and
  speech-to-text). Always shows its plan, needs approval, one undo step. Uses the
  same tools as the MCP server. Run a feasibility spike before building.
- Order: current batch → help/tour → model manager + AI voice separation →
  automatic subtitles → transcript-based editing → local assistant.
- Owner asked for test clips to be requested: Russian and Hebrew speech, and a
  phone video with talking over a pop song.

### Future ideas from the owner (16 Nov 2026, not built)
- Skip back / forward 5 s: buttons next to Play. (1.7: J / K / L are
  backwards / stop / forwards; arrows one source frame, Shift = 1 s.)
- Zoom the preview to inspect detail (magnify the preview, not the export).
- Animated zoom and pan on a clip ("Ken Burns"). (Choosing the zoom point
  is done in 1.6: zoom + Position.)
- Test checklists live in docs/testing/ (generated by gen_checklist.py; the
  HTML has instructions for an AI tester and a "Download filled checklist"
  button that bakes the results into the file). The build line is an
  argument (`--build`), and the tester must paste "Version shown in the
  app" (Copy version info).

### iPhone (owner decision, 16 Nov 2026: on hold)
- Discussed: Flutter + plugins support iOS; work needed = Photos picker/save,
  HDR (iPhone HLG/Dolby Vision footage looks washed out in our 8-bit export —
  worth fixing for all platforms anyway), no background export, icons/permissions.
- Owner prefers no Apple account for now. Plan when resumed: CI builds an
  unsigned .ipa; owner sideloads with a free Apple ID via AltStore (auto-refresh
  every 7 days) or Sideloadly. Paid account + TestFlight only if they want
  longer-lived installs or to share. App Store is not planned (GPL FFmpeg build
  is widely considered incompatible with App Store terms).
