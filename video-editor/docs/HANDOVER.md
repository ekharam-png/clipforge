# ClipForge handover

Read this first in a new session. It records what was built, why, how it fits
together, how to build and test it, and what is still open. Last updated
18 November 2026 (1.11.0: speech to text, captions from speech, gentle
filler removal, shorts for Claude; computers only).

## What ClipForge is

A personal CapCut-style video editor for the owner (non-technical), installed
as a real app on **Android, Windows and macOS** (iPhone later). Used for short
family videos, podcast clips and sport clips, up to about 5–7 minutes. Possibly
shared with a few friends later.

"ClipForge" is a working name.

## Where things are

- Repository: this public repository, folder `video-editor/`,
  branch `main`. Versions are published as GitHub Releases (tags `v*`) and
  the download page lives in `site/` (GitHub Pages).
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
- `test/core`, `test/media`, `test/ui`, `test/mcp` — 1516 tests (1.11.0; 1393 at 1.10.0).
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

## One-click Claude install, the skill, test documents (17 Nov 2026, no app change)

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
  then the sample project opens: 3 Add media, 4 timeline, 5 Split (first
  clip selected), 6 clip tools — phone: the Speed/Look/Sound tool-bar
  buttons; desktop: the side panel with Sound open — 7 Shape, 8 save sign +
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
  found. Entry points: "?" on the home and editor app bars, macOS menu Help
  > ClipForge Help / Show the tour, and `HelpHint` "?" buttons next to
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
  `Release notes.txt` (the version's CHANGELOG section). Android versionCode
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
   build number, time, commit, artifact names, release notes.
4. Generate the test checklists with the build line:
   `python3 docs/testing/gen_checklist.py docs/testing/ClipForge-Test-Round-4.html --round 4 --build "ClipForge X.Y.Z (build N) · ..."`
   and the same with `ClipForge-Test-Round-4-Phone.html --round 4-phone`.
   `--round` picks the step list (ROUNDS in the script; default 4):
   3 = 1.4.0 (40 steps), 4 = computers, 1.9.0 (61 steps: new since 1.4.0 + a
   short regression core, PASS/FAIL results, "ask the owner to listen /
   watch" tags), 4-phone = the Android phone through Phone Link (42 steps).
   For Claude itself: `docs/testing/claude-control-test-3.md` (paste into a
   chat).
5. The run's artifacts now also include the Claude Desktop extension
   (`…-claude-windows.mcpb`, `…-claude-macos.mcpb`) and
   `ClipForge-<version>-claude-skill.zip`; the owner's guide is
   `docs/claude-setup.html`.

History so far: 1.11 speech to text on computers (transcribe, captions from speech, gentle filler removal with put back, Transcript column, shorts for Claude, right-to-left text), unique project names, app lock fix; 1.10 voice recorded separately (asked on add, lined up by sound, linked, nudge, add_voice / align_audio); 1.9 Claude control from the owner's test (export jobs, short answers, open-in-app lock, dry runs, warnings); 1.8 Android media copies (missing-file fix), gallery search, fixed signing key, phone speed, fit/loop music, free music search, feature log; 1.7 fades, filters, text styles, snapping, duplicate / copy settings, sound-only export, frame rate, menus and keyboard; 1.6 crop and position, overlay track (picture-in-picture); 1.5 sound tracks, separate sound, adaptive silences, video size; 1.0 basic editor; 1.1 round-2 features; 1.2 review fixes +
Claude control; 1.3 Voice focus, quit crash fix, drag and drop, graphics
card; 1.4 help and tour, Windows menu bar, instant sound, History, long
videos, version numbers.

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

- Speech to text on phones, a speech engine built into the app (1.11 uses a
  program installed on the computer), transcripts inside project bundles,
  previewing a filler cut before applying it.
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
flutter test                                   # all tests (1516)
flutter build apk --release --split-per-abi --target-platform android-arm64
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
