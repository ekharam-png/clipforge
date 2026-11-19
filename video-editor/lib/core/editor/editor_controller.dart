import 'package:flutter/foundation.dart';

import '../model/project.dart';
import 'project_editor.dart';
export 'project_editor.dart' show HistoryStep, ClipSettings;

/// Holds the open project and applies every edit. All edits go through this
/// class so that undo/redo and autosave see them. Notifies listeners after
/// each change. CONTRACT: public signatures here are relied on by the UI.
///
/// This is a thin [ChangeNotifier] wrapper: the editing rules live in
/// [ProjectEditor] (pure Dart, shared with command-line tools). See there
/// for the exact behaviour of every method.
///
/// Edits that would not change anything (unknown ids, values that clamp
/// back to the current state) are complete no-ops: no undo entry, no
/// notification, `updatedAt` untouched.
class EditorController extends ChangeNotifier {
  /// [clock] and [newId] exist for tests; they default to `DateTime.now`
  /// and a v4 UUID.
  EditorController(
    Project project, {
    DateTime Function()? clock,
    String Function()? newId,
  }) : this.wrap(ProjectEditor(project, clock: clock, newId: newId));

  /// Wraps an existing [editor].
  EditorController.wrap(this.editor) {
    editor.addListener(notifyListeners);
  }

  /// The pure editing core behind this controller.
  final ProjectEditor editor;

  Project get project => editor.project;

  /// Minimum length a clip, audio clip or title may be trimmed/split to.
  static const int minDurationMs = ProjectEditor.minDurationMs;

  /// Longest time a photo may stay on screen.
  static const int maxPhotoDurationMs = ProjectEditor.maxPhotoDurationMs;

  /// Volume range for clips and audio (1.0 = unchanged).
  static const double minVolume = ProjectEditor.minVolume;
  static const double minVoiceFocus = ProjectEditor.minVoiceFocus;
  static const double maxVoiceFocus = ProjectEditor.maxVoiceFocus;
  static const double maxVolume = ProjectEditor.maxVolume;

  /// Title text height range, as a fraction of canvas height.
  static const double minTitleFontSize = ProjectEditor.minTitleFontSize;
  static const double maxTitleFontSize = ProjectEditor.maxTitleFontSize;

  /// Playback speed range of a video clip.
  static const double minSpeed = ProjectEditor.minSpeed;
  static const double maxSpeed = ProjectEditor.maxSpeed;

  /// Range of brightness / contrast / saturation (0 = unchanged).
  static const double minAdjustment = ProjectEditor.minAdjustment;
  static const double maxAdjustment = ProjectEditor.maxAdjustment;

  /// Centre zoom range (1 = whole picture).
  static const double minZoom = ProjectEditor.minZoom;
  static const double maxZoom = ProjectEditor.maxZoom;

  /// Range of a transition's length.
  static const int minTransitionMs = ProjectEditor.minTransitionMs;
  static const int maxTransitionMs = ProjectEditor.maxTransitionMs;

  /// Number of undo steps kept; the oldest are dropped beyond this.
  static const int maxUndoSteps = ProjectEditor.maxUndoSteps;

  /// True while a [transaction] body is running.
  bool get inTransaction => editor.inTransaction;

  bool get canUndo => editor.canUndo;
  bool get canRedo => editor.canRedo;

  /// Restores the previous snapshot. Ignored inside a [transaction].
  void undo() => editor.undo();

  /// Re-applies the last undone step. Ignored inside a [transaction].
  void redo() => editor.redo();

  /// The editing history, oldest first; see [ProjectEditor.history].
  List<HistoryStep> get history => editor.history;

  /// How many steps of [history] are done.
  int get historyPosition => editor.historyPosition;

  /// Goes back (or forward) to the state after step [position] of
  /// [history] in one jump; see [ProjectEditor.jumpToHistory].
  void jumpToHistory(int position) => editor.jumpToHistory(position);

  /// Names the next edit in the [history]; see [ProjectEditor.nameNextEdit].
  void nameNextEdit(String label) => editor.nameNextEdit(label);

  // Main track -------------------------------------------------------------
  /// Inserts [clip] at [index] (end of track when null). The index is
  /// clamped to the track and the clip's values are clamped like any other
  /// edit. A clip whose id is already on the track gets a fresh id.
  void addClip(Clip clip, {int? index}) => editor.addClip(clip, index: index);

  void removeClip(String clipId) => editor.removeClip(clipId);

  /// Moves the clip at [fromIndex] so that it ends up at [toIndex] (the
  /// index in the resulting list, clamped to the track). An out-of-range
  /// [fromIndex] is a no-op.
  void moveClip(int fromIndex, int toIndex) =>
      editor.moveClip(fromIndex, toIndex);

  /// Sets the trim range in SOURCE milliseconds; values are clamped to the
  /// source and to [minDurationMs] (times the speed for sped-up clips). For
  /// photos only [outMs] (the display time) matters.
  ///
  /// When only one edge is given the other edge stays where it is, so
  /// dragging the in-handle past the out-handle stops short of it instead
  /// of pushing it.
  void trimClip(String clipId, {int? inMs, int? outMs}) =>
      editor.trimClip(clipId, inMs: inMs, outMs: outMs);

  /// Splits the clip under [timelineMs] in two. Returns false when the
  /// position is too close to a clip edge or outside the track.
  ///
  /// Inside a transition the INCOMING clip is the one that is split. The
  /// first half keeps the clip's id and transition; the second half gets a
  /// new id, the same speed and look, and no transition.
  bool splitAt(int timelineMs) => editor.splitAt(timelineMs);

  void setClipVolume(String clipId, double volume) =>
      editor.setClipVolume(clipId, volume);

  void setClipMuted(String clipId, bool muted) =>
      editor.setClipMuted(clipId, muted);

  void setClipFit(String clipId, FitMode fit) => editor.setClipFit(clipId, fit);

  // Clip look, speed and transitions (contract v2) --------------------------
  /// 0.25..4. Ignored for photos. Also limited so that the clip still lasts
  /// [minDurationMs] on the timeline.
  void setClipSpeed(String clipId, double speed) =>
      editor.setClipSpeed(clipId, speed);

  void setClipDenoise(String clipId, bool denoise) =>
      editor.setClipDenoise(clipId, denoise);

  /// Voice focus strength 0..1 (0 = off). Ignored for photos.
  void setClipVoiceFocus(String clipId, double strength) =>
      editor.setClipVoiceFocus(clipId, strength);

  /// Audio stream and side of a video clip; see
  /// [ProjectEditor.setClipAudioSource].
  void setClipAudioSource(String clipId, {int? track, AudioChannel? channel}) =>
      editor.setClipAudioSource(clipId, track: track, channel: channel);

  /// Copies settings of clip [fromClipId] to every other clip as one undo
  /// step and returns the number of clips changed. [speed] and [sound]
  /// (volume, muted, denoise, voice focus, sound source) only go from a video to video clips; [look]
  /// (brightness, contrast, saturation, zoom, fit) goes to every clip.
  int applyClipSettingsToAll(String fromClipId,
          {bool speed = false, bool look = false, bool sound = false}) =>
      editor.applyClipSettingsToAll(fromClipId,
          speed: speed, look: look, sound: sound);

  /// Each -1..1; null leaves the value unchanged.
  void setClipAdjustments(String clipId,
          {double? brightness, double? contrast, double? saturation}) =>
      editor.setClipAdjustments(clipId,
          brightness: brightness, contrast: contrast, saturation: saturation);

  /// 1..4.
  void setClipZoom(String clipId, double zoom) =>
      editor.setClipZoom(clipId, zoom);

  /// Transition from the previous clip into [clipId]. [durationMs] is
  /// clamped to 100..2000; null keeps the current length.
  void setClipTransition(String clipId, TransitionType type,
          {int? durationMs}) =>
      editor.setClipTransition(clipId, type, durationMs: durationMs);

  /// Cuts [sourceRanges] (times in the clip's SOURCE file, e.g. detected
  /// silences) out of the clip, leaving the kept pieces as separate clips in
  /// its place. One undo step. Returns the number of pieces removed.
  int removeSourceRanges(
          String clipId, List<({int startMs, int endMs})> sourceRanges) =>
      editor.removeSourceRanges(clipId, sourceRanges);

  /// Splits the clip at [timelineMs] and inserts [photo] (a still of that
  /// frame) between the two halves. One undo step. Returns false when the
  /// position cannot be split. The still takes over the split clip's fit,
  /// zoom and colour adjustments.
  bool insertFreezeFrame(int timelineMs, Clip photo) =>
      editor.insertFreezeFrame(timelineMs, photo);

  /// Adds many titles at once (subtitle import) as one undo step.
  void addTitles(List<TitleOverlay> titles) => editor.addTitles(titles);
  void setDuckMusic(bool duck) => editor.setDuckMusic(duck);

  // Audio ------------------------------------------------------------------
  /// Adds [audio] (clamped). An id that is already in use is replaced by a
  /// fresh one.
  String addAudio(AudioClip audio) => editor.addAudio(audio);

  void removeAudio(String audioId) => editor.removeAudio(audioId);

  /// Replaces the audio clip with the same id by [audio] (clamped, kept
  /// to the track rules); see [ProjectEditor.updateAudio].
  void updateAudio(AudioClip audio) => editor.updateAudio(audio);

  /// See [ProjectEditor.moveAudioToTrack].
  void moveAudioToTrack(String audioId, String trackId, {int? startMs}) =>
      editor.moveAudioToTrack(audioId, trackId, startMs: startMs);

  // Sound tracks -------------------------------------------------------------
  static const int maxSoundTracks = ProjectEditor.maxSoundTracks;
  static const int maxTrackNameLength = ProjectEditor.maxTrackNameLength;

  /// See [ProjectEditor.separateSoundProblem].
  static String? separateSoundProblem(Project p, String clipId) =>
      ProjectEditor.separateSoundProblem(p, clipId);

  /// See [ProjectEditor.defaultVoiceTrack].
  static String? defaultVoiceTrack(Project p) =>
      ProjectEditor.defaultVoiceTrack(p);

  /// See [ProjectEditor.addSoundTrack].
  String? addSoundTrack({String? name}) => editor.addSoundTrack(name: name);
  void renameSoundTrack(String trackId, String name) =>
      editor.renameSoundTrack(trackId, name);

  /// See [ProjectEditor.setSoundTrack].
  void setSoundTrack(String trackId,
          {double? volume, bool? muted, bool? solo, bool? duck, bool? speech}) =>
      editor.setSoundTrack(trackId,
          volume: volume, muted: muted, solo: solo, duck: duck, speech: speech);
  bool removeSoundTrack(String trackId) => editor.removeSoundTrack(trackId);

  /// See [ProjectEditor.separateSound].
  String? separateSound(String clipId, {String? trackId}) =>
      editor.separateSound(clipId, trackId: trackId);
  int separateAllSound({String? trackId}) =>
      editor.separateAllSound(trackId: trackId);
  bool reattachSound(String audioId) => editor.reattachSound(audioId);

  /// See [ProjectEditor.addVoice].
  List<String> addVoice(
    AudioClip voice, {
    required String clipId,
    required int offsetMs,
    String? trackId,
    String? trackName,
    bool muteClips = true,
    bool linedUp = true,
  }) =>
      editor.addVoice(voice,
          clipId: clipId,
          offsetMs: offsetMs,
          trackId: trackId,
          trackName: trackName,
          muteClips: muteClips,
          linedUp: linedUp);

  /// See [ProjectEditor.linkVoice].
  List<String> linkVoice(String audioId,
          {required String clipId,
          required int offsetMs,
          String? trackName,
          bool? muteClips}) =>
      editor.linkVoice(audioId,
          clipId: clipId,
          offsetMs: offsetMs,
          trackName: trackName,
          muteClips: muteClips);

  /// See [ProjectEditor.nudgeVoice].
  bool nudgeVoice(String audioId, int deltaMs) =>
      editor.nudgeVoice(audioId, deltaMs);

  /// See [ProjectEditor.unlinkVoice].
  bool unlinkVoice(String audioId, {bool unmuteClips = true}) =>
      editor.unlinkVoice(audioId, unmuteClips: unmuteClips);

  /// See [ProjectEditor.setVoiceClipsMuted].
  bool setVoiceClipsMuted(String audioId, bool muted) =>
      editor.setVoiceClipsMuted(audioId, muted);
  void setAudioDenoise(String audioId, bool denoise) =>
      editor.setAudioDenoise(audioId, denoise);
  void setAudioVoiceFocus(String audioId, double strength) =>
      editor.setAudioVoiceFocus(audioId, strength);
  void setAudioSource(String audioId, {int? track, AudioChannel? channel}) =>
      editor.setAudioSource(audioId, track: track, channel: channel);
  void setVideoSize(VideoSize size) => editor.setVideoSize(size);

  // 1.7: fades, colour filters, duplicate, copy / paste settings, track
  // order, probe data.
  static const int maxClipFadeMs = ProjectEditor.maxClipFadeMs;
  void setClipFilter(String clipId, LookFilter filter) =>
      editor.setClipFilter(clipId, filter);
  void setClipWarmth(String clipId, double warmth) =>
      editor.setClipWarmth(clipId, warmth);
  void resetLook(String clipId) => editor.resetLook(clipId);
  void setClipFades(String clipId, {int? fadeInMs, int? fadeOutMs}) =>
      editor.setClipFades(clipId, fadeInMs: fadeInMs, fadeOutMs: fadeOutMs);
  void setProjectFades({int? fadeInMs, int? fadeOutMs}) =>
      editor.setProjectFades(fadeInMs: fadeInMs, fadeOutMs: fadeOutMs);
  String? duplicateClip(String clipId) => editor.duplicateClip(clipId);
  String? duplicateTitle(String titleId) => editor.duplicateTitle(titleId);
  int pasteClipSettings(List<String> clipIds, ClipSettings settings) =>
      editor.pasteClipSettings(clipIds, settings);
  bool moveSoundTrack(String trackId, int by) =>
      editor.moveSoundTrack(trackId, by);
  void setClipAudioStreams(String clipId, List<int> streams) =>
      editor.setClipAudioStreams(clipId, streams);
  void setProbeData(String path,
          {List<int>? audioStreams, bool? hasAudio, double? frameRate}) =>
      editor.setProbeData(path,
          audioStreams: audioStreams, hasAudio: hasAudio, frameRate: frameRate);

  // Titles -----------------------------------------------------------------
  /// Adds [title] (clamped). An id that is already in use is replaced by a
  /// fresh one.
  void addTitle(TitleOverlay title) => editor.addTitle(title);

  void removeTitle(String titleId) => editor.removeTitle(titleId);

  /// Replaces the title with the same id by [title] (clamped).
  void updateTitle(TitleOverlay title) => editor.updateTitle(title);

  // Project ----------------------------------------------------------------
  void setAspect(CanvasAspect aspect) => editor.setAspect(aspect);

  /// Publishing notes and "good moment" markers (1.14).
  void setPublishingNotes(PublishingNotes notes) =>
      editor.setPublishingNotes(notes);
  String? addMarker(int timelineMs, {String label = ''}) =>
      editor.addMarker(timelineMs, label: label);
  bool removeMarker(String markerId) => editor.removeMarker(markerId);
  void updateMarker(Marker marker) => editor.updateMarker(marker);

  /// Renames the project. The name is trimmed; an empty name is ignored.
  /// Not an undo step: undo/redo never change the name back.
  void rename(String name) => editor.rename(name);

  /// Points every clip and audio clip that uses the file [oldPath] at
  /// [newPath]. One undo step; a no-op when nothing uses [oldPath].
  void relinkMedia(String oldPath, String newPath) =>
      editor.relinkMedia(oldPath, newPath);

  // Crop and position (a main-track clip or an overlay item) ------------------
  /// See [ProjectEditor.setFraming].
  void setFraming(String itemId, Framing framing) =>
      editor.setFraming(itemId, framing);
  void setPictureCrop(String itemId, CropRect crop) =>
      editor.setPictureCrop(itemId, crop);
  void setPicturePan(String itemId, {double? x, double? y}) =>
      editor.setPicturePan(itemId, x: x, y: y);
  void rotatePicture(String itemId, {bool clockwise = true}) =>
      editor.rotatePicture(itemId, clockwise: clockwise);
  void flipPicture(String itemId, {required bool horizontal}) =>
      editor.flipPicture(itemId, horizontal: horizontal);
  void resetFraming(String itemId) => editor.resetFraming(itemId);

  // Overlay track --------------------------------------------------------------
  /// See [ProjectEditor.addOverlay]. Returns the id it was added under.
  String addOverlay(OverlayClip overlay) => editor.addOverlay(overlay);
  void removeOverlay(String overlayId) => editor.removeOverlay(overlayId);

  /// See [ProjectEditor.updateOverlay].
  void updateOverlay(OverlayClip overlay) => editor.updateOverlay(overlay);

  /// Groups the edits made inside [body] into one undo step (used while
  /// dragging a trim handle or a slider).
  ///
  /// Listeners are still notified after every edit inside [body], so the
  /// preview follows a drag. Nested calls join the outermost transaction.
  /// If the project ends up with the same content it started with, no undo
  /// step is recorded. [undo] and [redo] are ignored inside [body]. If
  /// [body] throws, the edits made so far are kept as one step and the
  /// error is rethrown.
  ///
  /// [label] names the step in the [history] (otherwise it is worked out
  /// from what changed).
  void transaction(void Function() body, {String? label}) =>
      editor.transaction(body, label: label);

  @override
  void dispose() {
    editor.removeListener(notifyListeners);
    super.dispose();
  }
}
