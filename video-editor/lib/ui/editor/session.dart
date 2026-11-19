import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/editor/editor_controller.dart';
import '../../core/model/project.dart';
import '../../core/storage/project_store.dart';
import '../../media/media_api.dart';
import '../../media/processed_sound_cache.dart';
import '../../media/speech_map.dart';
import '../playback/playback_controller.dart';
import '../playback/timeline_player.dart';
import '../gallery_search.dart';
import '../music_search.dart';
import '../publish_service.dart';
import '../services.dart';
import '../speech/speech_service.dart';
import 'sound_pictures.dart';
import 'sound_renders.dart';

enum ItemKind { clip, audio, title, overlay }

/// Where the Text window sits in a wide window: a column at the right
/// (default) or under the preview.
enum TextDock { right, below }

/// The Text window is never narrower than this; its default sizes.
const double kTextMinWidth = 420;
const double kTextDefaultWidth = 460;
const double kTextMinHeight = 160;
const double kTextDefaultHeight = 280;

/// What the editor's save indicator says.
enum SaveState {
  /// Everything is on disk.
  saved,

  /// A change is waiting to be written, or being written.
  saving,

  /// The latest save did not work.
  failed,
}

@immutable
class SaveStatus {
  const SaveStatus(this.state, {this.savedAt});
  final SaveState state;

  /// When the project was last written by this editor; null before the
  /// first save (it was already on disk when it was opened).
  final DateTime? savedAt;

  @override
  bool operator ==(Object other) =>
      other is SaveStatus && other.state == state && other.savedAt == savedAt;

  @override
  int get hashCode => Object.hash(state, savedAt);
}

/// Something slow the editor is doing that quitting would cut short.
class RunningJob {
  RunningJob._(this.kind, this.cancel);

  /// What the user would call it, as in "An export is still running".
  final JobKind kind;

  /// Stops the job; null when it cannot be stopped (it ends with the app).
  final Future<void> Function()? cancel;
}

enum JobKind { export, analysis }

/// The jobs that are running, so that leaving or quitting can ask first.
class JobTracker extends ChangeNotifier {
  final List<RunningJob> _jobs = [];
  bool _disposed = false;

  List<RunningJob> get running => List.unmodifiable(_jobs);
  bool get isEmpty => _jobs.isEmpty;

  /// Registers a job; call [end] with the result when it is over.
  RunningJob start(JobKind kind, {Future<void> Function()? cancel}) {
    final job = RunningJob._(kind, cancel);
    if (_disposed) return job;
    _jobs.add(job);
    notifyListeners();
    return job;
  }

  /// Safe to call after [dispose] and more than once.
  void end(RunningJob job) {
    if (_jobs.remove(job) && !_disposed) notifyListeners();
  }

  /// Stops every job that can be stopped and forgets them all.
  Future<void> cancelAll() async {
    final jobs = [..._jobs];
    _jobs.clear();
    if (!_disposed) notifyListeners();
    for (final j in jobs) {
      try {
        await j.cancel?.call();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _jobs.clear();
    super.dispose();
  }
}

/// The groups of settings a clip on the main track (or an overlay item:
/// [layout], [crop], [speed], [sound]) has.
enum ClipTool { speed, look, sound, transition, crop, layout }

@immutable
class Selection {
  const Selection(this.kind, this.id);
  final ItemKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is Selection && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// Everything the widgets of one open editor share.
class EditorSession {
  EditorSession({
    required this.editor,
    required this.playback,
    required this.backend,
    required this.engine,
    required this.files,
    required this.documents,
    required this.thumbnails,
    ProcessedSoundCache soundCache = const NoProcessedSoundCache(),
    this.gallery = const NoGallerySearch(),
    this.music = const NoMusicSearch(),
    this.speech,
    SoundPictures? pictures,
    this.store,
    this.publish,
  }) : sounds = SoundRenders(
          engine: engine,
          cache: soundCache,
          focusIndex: () => playback.clipIndex,
        ) {
    editor.addListener(_onEdited);
    // Instant sound processing: the clips' processed sound is rendered in
    // the background and the preview plays it once it is ready.
    playback.processedSound = sounds.readyPath;
    sounds.addListener(_onSoundsChanged);
    playback.addListener(_onPlaybackChanged);
    sounds.update(editor.project);
    this.pictures = pictures ??
        SoundPictures(
          engine: engine,
          // Next to the app's media folder, not inside it: the clean-up
          // of unused media must not take the pictures for media.
          cacheDir: () async =>
              p.join(p.dirname(await documents.mediaDir()), 'peaks'),
          fileExists: (path) => !playback.isMissing(path),
        );
    this.pictures.update(editor.project);
  }

  static const double minZoom = 6;
  static const double maxZoom = 480;

  final EditorController editor;
  final PlaybackController playback;
  final PlayerBackend backend;
  final MediaEngine engine;
  final FileService files;
  final DocumentService documents;
  final ThumbnailCache thumbnails;

  /// "Find file…" > "Search the gallery" (Android).
  final GallerySearch gallery;

  /// "Add music" > "Find free music" (Openverse).
  final MusicSearch music;

  /// The project list (1.14: shorts and shape copies are new projects in
  /// it). Null when there is none to add to.
  final ProjectStore? store;

  /// The kit folder, share sheet and upload pages (1.14).
  final PublishService? publish;

  /// Set by the editor screen: writes the project to disk now, and opens
  /// another project in place of this one.
  Future<void> Function()? saveNow;
  Future<void> Function(String projectId)? openProject;

  /// Who speaks when, as turns (for chapters of a project without titles
  /// or captions).
  List<({String name, int startMs, int endMs})> get speakerTurnsNow => [
        for (final t in speakerTurns(pictures.speakers))
          (name: t.name, startMs: t.startMs, endMs: t.endMs),
      ];

  /// Speech-to-text (1.11). Null on phones: nothing about speech is shown.
  final SpeechService? speech;

  /// The stored transcripts of this project's sounds, by
  /// [SpeechSource.key]; filled by [loadTranscripts].
  final ValueNotifier<Map<String, Transcript>> transcripts =
      ValueNotifier(const {});

  /// The Text window is shown (wide windows; narrow ones and phones open
  /// it as a full-screen sheet instead).
  final ValueNotifier<bool> showText = ValueNotifier(false);

  /// Where the Text window sits in a wide window.
  final ValueNotifier<TextDock> textDock = ValueNotifier(TextDock.right);

  /// Its width as a column at the right / its height under the preview
  /// (remembered app settings).
  final ValueNotifier<double> textWidth = ValueNotifier(kTextDefaultWidth);
  final ValueNotifier<double> textHeight = ValueNotifier(kTextDefaultHeight);

  /// Bumped to put the cursor in the Text window's search box (Ctrl+F).
  final ValueNotifier<int> findInText = ValueNotifier(0);

  /// Set by the Text window while it is open: the Delete key asks it
  /// first (true: it deleted its selected captions).
  bool Function()? textDeleteHook;

  /// "Show sound waves" (an app setting, on by default).
  final ValueNotifier<bool> showWaves = ValueNotifier(true);

  /// Moves the playhead to where speech next starts ([forward]) or last
  /// started: on the selected sound's track when that is a speaker's,
  /// else wherever the speaker changes. False when there is no such place
  /// (or no sound picture yet).
  bool goToSpeechStart({required bool forward}) {
    final tracks = pictures.speakers;
    if (tracks.isEmpty) return false;
    final selected = selectedAudio?.trackId;
    final to = neighbourStart(
        speechStarts(tracks,
            trackId: tracks.any((t) => t.id == selected) ? selected : null),
        playback.positionMs,
        forward: forward);
    if (to == null) return false;
    playback.seek(to);
    return true;
  }

  /// The waveforms on the timeline and who is speaking (1.13).
  late final SoundPictures pictures;

  Transcript? transcriptOf(String path, int audioTrack) =>
      transcripts.value['$path|$audioTrack'];

  /// Reads the transcripts the project's clips have (after opening, and
  /// when media was added).
  Future<void> loadTranscripts() async {
    final service = speech;
    if (service == null) return;
    try {
      final found = await service.transcriptsOf(
          project.id, speechSourcesOfProject(project));
      if (!_disposed) transcripts.value = found;
    } catch (_) {
      // No transcripts is a normal state.
    }
  }

  final ValueNotifier<Selection?> selection = ValueNotifier(null);

  /// Timeline scale in pixels per second.
  final ValueNotifier<double> zoom = ValueNotifier(60);

  /// The clip tool group that is open in the side panel (wide windows).
  final ValueNotifier<ClipTool?> openTool = ValueNotifier(null);

  /// The picture whose crop is being changed (a clip or overlay id): the
  /// preview shows it whole, with the crop frame and its handles. Set while
  /// a Crop panel is on screen.
  final ValueNotifier<String?> cropTarget = ValueNotifier(null);

  /// Shape the crop frame keeps while its handles are dragged (width /
  /// height in picture pixels); null: free.
  final ValueNotifier<double?> cropRatio = ValueNotifier(null);

  /// Settings taken with "Copy settings", for "Paste settings" (this
  /// editor only).
  final ValueNotifier<ClipSettings?> copiedSettings = ValueNotifier(null);

  /// Dragging on the timeline snaps to the playhead and to the edges of
  /// clips, titles, sounds and overlays (an app setting; Alt / Option held
  /// down turns it off for one drag).
  final ValueNotifier<bool> snapping = ValueNotifier(true);

  /// Where the timeline shows the snap line while a drag has snapped
  /// (timeline ms); null when nothing snapped.
  final ValueNotifier<int?> snapLine = ValueNotifier(null);

  /// The History column is shown (wide windows; phones use a sheet).
  final ValueNotifier<bool> showHistory = ValueNotifier(false);

  /// True while the latest changes could not be written to disk.
  final ValueNotifier<bool> saveFailed = ValueNotifier(false);

  /// What the save indicator in the top bar shows.
  final ValueNotifier<SaveStatus> saveStatus =
      ValueNotifier(const SaveStatus(SaveState.saved));

  /// Exports and analyses in progress.
  final JobTracker jobs = JobTracker();

  /// The background renders of the clips' processed sound.
  final SoundRenders sounds;
  int _soundsSeen = -1;

  void _onSoundsChanged() {
    if (_disposed) return;
    if (sounds.readyVersion == _soundsSeen) return;
    _soundsSeen = sounds.readyVersion;
    playback.soundFilesChanged();
  }

  void _onPlaybackChanged() {
    if (_disposed) return;
    sounds.playing = playback.playing;
  }

  Project get project => editor.project;

  void select(ItemKind kind, String id) => selection.value = Selection(kind, id);

  /// Selects the clip [id] and makes the preview show it: when the playhead
  /// is somewhere else it jumps to the clip's first frame that is fully
  /// visible (after the transition into it, if there is one). A playhead
  /// that is already on the clip stays where it is.
  void selectClipAndShow(String id) {
    select(ItemKind.clip, id);
    final i = project.clips.indexWhere((c) => c.id == id);
    if (i < 0) return;
    if (clipIndexUnderPlayhead == i) return;
    playback.seek(project.clipStartMs(i) + project.transitionOverlapMs(i));
  }

  /// Index of the clip the playhead is on, the one Split and Freeze frame
  /// act on. -1 when the playhead is at or past the end of the video.
  int get clipIndexUnderPlayhead {
    final t = playback.positionMs;
    return t < project.durationMs ? project.clipIndexAt(t) : -1;
  }

  /// Split and Freeze frame act at the playhead. When a clip is selected
  /// and the playhead has been moved onto another one, the selection moves
  /// there too, so what is highlighted is always what gets cut.
  void selectionFollowsPlayhead() {
    if (selection.value?.kind != ItemKind.clip) return;
    final i = clipIndexUnderPlayhead;
    if (i < 0) return;
    final under = project.clips[i];
    if (under.id != selection.value!.id) select(ItemKind.clip, under.id);
  }

  /// Where new media goes on the main track: right after the selected clip,
  /// or, with no clip selected, at the end of the track.
  int get insertIndex {
    final selected = selectedClip;
    if (selected != null) return project.clips.indexOf(selected) + 1;
    return project.clips.length;
  }

  /// Moves the playhead to the first visible frame of the clip without
  /// selecting it.
  void showClip(String id) {
    final i = project.clips.indexWhere((c) => c.id == id);
    if (i < 0 || clipIndexUnderPlayhead == i) return;
    playback.seek(project.clipStartMs(i) + project.transitionOverlapMs(i));
  }
  void clearSelection() => selection.value = null;

  /// The timeline is never wider than this (very long projects zoom in
  /// less far; a 40-minute one is 1.2 million pixels at [maxZoom]).
  static const double maxTimelinePixels = 4000000;

  void setZoom(double pixelsPerSecond) {
    final seconds = project.durationMs / 1000;
    var most = maxZoom;
    if (seconds > 0 && seconds * maxZoom > maxTimelinePixels) {
      most = (maxTimelinePixels / seconds).clamp(minZoom, maxZoom).toDouble();
    }
    zoom.value = pixelsPerSecond.clamp(minZoom, most).toDouble();
  }

  Clip? get selectedClip {
    final s = selection.value;
    if (s?.kind != ItemKind.clip) return null;
    return project.clips.where((c) => c.id == s!.id).firstOrNull;
  }

  AudioClip? get selectedAudio {
    final s = selection.value;
    if (s?.kind != ItemKind.audio) return null;
    return project.audio.where((a) => a.id == s!.id).firstOrNull;
  }

  OverlayClip? get selectedOverlay {
    final s = selection.value;
    if (s?.kind != ItemKind.overlay) return null;
    return project.overlays.where((o) => o.id == s!.id).firstOrNull;
  }

  /// Selects overlay item [id] and, when the playhead is not on it, moves
  /// the playhead to its first frame so that it shows.
  void selectOverlayAndShow(String id) {
    select(ItemKind.overlay, id);
    showOverlay(id);
  }

  /// Moves the playhead onto overlay item [id] when it is not there.
  void showOverlay(String id) {
    final o = project.overlays.where((o) => o.id == id).firstOrNull;
    if (o == null) return;
    final t = playback.positionMs;
    if (t >= o.startMs && t < o.endMs) return;
    playback.seek(o.startMs);
  }

  TitleOverlay? get selectedTitle {
    final s = selection.value;
    if (s?.kind != ItemKind.title) return null;
    return project.titles.where((t) => t.id == s!.id).firstOrNull;
  }

  void _onEdited() {
    playback.updateProject(editor.project);
    sounds.update(editor.project);
    pictures.update(editor.project);
    // Drop a selection whose item is gone (deleted or undone).
    final s = selection.value;
    if (s == null) return;
    final exists = switch (s.kind) {
      ItemKind.clip => project.clips.any((c) => c.id == s.id),
      ItemKind.audio => project.audio.any((a) => a.id == s.id),
      ItemKind.title => project.titles.any((t) => t.id == s.id),
      ItemKind.overlay => project.overlays.any((o) => o.id == s.id),
    };
    if (!exists) selection.value = null;
  }

  bool _disposed = false;

  /// True once [dispose] ran (callbacks after a frame check this).
  bool get isDisposed => _disposed;

  /// Lets go of everything. Safe to call more than once. The players go
  /// last but one: by now the video surfaces are out of the tree (the
  /// editor's children are disposed before the editor itself).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    editor.removeListener(_onEdited);
    sounds.removeListener(_onSoundsChanged);
    playback.removeListener(_onPlaybackChanged);
    sounds.dispose();
    playback.dispose();
    selection.dispose();
    zoom.dispose();
    openTool.dispose();
    cropTarget.dispose();
    cropRatio.dispose();
    showHistory.dispose();
    showText.dispose();
    textDock.dispose();
    textWidth.dispose();
    textHeight.dispose();
    findInText.dispose();
    showWaves.dispose();
    pictures.dispose();
    transcripts.dispose();
    copiedSettings.dispose();
    snapping.dispose();
    snapLine.dispose();
    saveFailed.dispose();
    saveStatus.dispose();
    jobs.dispose();
  }
}

/// Turns a continuous gesture (dragging a handle, a slider, typing) into a
/// single undo step.
///
/// Each [apply] takes back what the previous one did and applies the new
/// state in one [EditorController.transaction], so the edits passed in must
/// set absolute values worked out from where the gesture started, not add
/// to the current ones.
class LiveEdit {
  LiveEdit(this.editor);

  final EditorController editor;
  bool _applied = false;

  void apply(void Function() edit) {
    if (_applied) editor.undo();
    final base = editor.project;
    editor.transaction(edit);
    // Edits that change nothing leave no undo step behind.
    _applied = !identical(editor.project, base);
  }
}
