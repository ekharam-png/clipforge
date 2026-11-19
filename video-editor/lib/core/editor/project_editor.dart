import 'dart:convert';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../model/project.dart';
import 'edit_labels.dart';
import 'sound_tracks.dart';
import 'marker_follow.dart';
import 'title_anchors.dart';

/// Holds a project and applies every edit, with undo/redo. Pure Dart (no
/// Flutter), so that it can run in the app (wrapped by `EditorController`)
/// and in command-line tools such as the MCP server.
///
/// Undo/redo is snapshot based: [Project] is immutable, so the history is a
/// stack of earlier projects. Edits that would not change anything (unknown
/// ids, values that clamp back to the current state) are complete no-ops:
/// no undo entry, no notification, `updatedAt` untouched.
///
/// Time units: positions named `timelineMs` are on the project timeline
/// (speed and transition overlaps applied). Trim values (`inMs` / `outMs`)
/// and the ranges of [removeSourceRanges] are positions in the clip's
/// SOURCE file.
///
/// ## Titles follow the picture
///
/// Titles and captions are stored at timeline times, but every edit that
/// changes the timing of the main track (add / remove / move / trim / split
/// / speed / transition / [removeSourceRanges] / [insertFreezeFrame] /
/// [applyClipSettingsToAll] with speed) moves them so that they stay over
/// the picture they were placed on. The move is part of the same undo step
/// as the edit. Music ([AudioClip]) deliberately stays at absolute times.
///
/// Before the edit each title's start and end are anchored:
///  * the START to the clip [Project.clipIndexAt] reports for it (inside a
///    transition: the incoming clip) and the source position shown there
///    (for photos: the offset inside the clip);
///  * the END to the same clip when the title ends inside it, otherwise to
///    the clip playing 1 ms before the end. The part of a title that lies
///    past the end of the track is kept as a fixed extra length.
///  * A title that starts at or after the end of the track, and every title
///    while there are no clips, is not anchored: it stays untouched.
///
/// After the edit each anchor is looked up again:
///  * in the clip with the same id, or in a clip the edit created from the
///    same file (the second half of a split, the pieces [removeSourceRanges]
///    leaves) - whichever piece now contains that source position. An end
///    exactly on a cut belongs to the piece before it, a start to the piece
///    after it. So titles move with a reordered clip, shift when something
///    before them changes length, and stretch or shrink with a speed change.
///  * If the source position was trimmed or cut away, the edge is clamped
///    to the nearest kept piece: a start moves forward to the next kept
///    frame, an end back to the last kept one.
///  * If the clip was deleted, a start moves to the beginning of the next
///    clip that followed it (or the end of the track), an end to the end of
///    the clip that preceded it (or 0).
///  * A title is DELETED when both edges were on deleted clips, or when
///    its start frame is gone and after clamping nothing is left (it lay
///    wholly inside a deleted clip or inside a trimmed / cut range). A
///    title that is only partly affected keeps what remains. A title whose
///    start frame is still on the track is never deleted.
///  * If a reorder puts the clip with the end frame before the clip with
///    the start frame, the title keeps its start and its length.
///  * A title never gets shorter than [minDurationMs]: its start is kept
///    and its end extended.
///
/// Anchors are remembered (as fractional source positions) for as long as
/// the title still is where they put it, so a series of edits, a drag and
/// undo/redo do not add up rounding errors: an untouched title stays within
/// half a timeline millisecond of its source frame. Inside a [transaction]
/// the anchors of the state before the transaction stay in force, so
/// dragging a trim handle over a title and back restores the title
/// (including one that was deleted on the way); once the transaction ends,
/// what was clamped or deleted stays that way.
///
/// ## Sound tracks
///
/// Sound clips ([AudioClip]) sit on sound tracks ([Project.soundTracks]):
/// at most [maxSoundTracks] besides the video's own sound. The rules (see
/// sound_tracks.dart):
///  * clips on ONE track never overlap; different tracks are mixed;
///  * ADDING a clip ([addAudio], [separateSound]) puts it on the wanted
///    track when it is free there, else on the first other track that is
///    free there, else on a new track (while there are fewer than
///    [maxSoundTracks]), else on the wanted track right AFTER what is in
///    the way;
///  * MOVING a clip by hand ([updateAudio] with a new start or track,
///    [moveAudioToTrack]) puts it at the free place nearest to where it was
///    dropped; TRIMMING stops at the neighbours (clamped, never pushed);
///  * a track can be deleted only when it is empty ([removeSoundTrack]).
///
/// ## Separated sound follows its clip
///
/// [separateSound] copies a video clip's sound (part of the file, speed,
/// volume, clean-up, voice focus, track and side) to a sound clip on a
/// track and mutes the video clip. While the sound clip is "linked"
/// ([AudioClip.linked]) it follows the clip through every edit of the main
/// track, in the same undo step: same place, part of the file and speed;
/// it is deleted with the clip; pieces cut from the clip (split, remove
/// silences) get linked sounds of their own. Moving or trimming the sound
/// by hand unlinks it (for L- and J-cuts): from then on it stays at its
/// absolute time like music. [reattachSound] puts a sound back on its
/// clip. Plain music never follows the picture.
///
/// A VOICE RECORDED SEPARATELY ([addVoice], [AudioClip.syncOffsetMs]: a
/// microphone or Zoom per-speaker file lined up with a clip) follows in the
/// same way and by the same code ([syncLinkedSound]); its part of its own
/// file is the clip's part shifted by the offset, cut where the voice file
/// has no sound. It belongs to the video FILE: every clip of that file has
/// its piece, and several recordings (one per speaker) can be lined up
/// with the same clips, each on its own speech track. [nudgeVoice] moves it
/// against the picture, [unlinkVoice] ends the link, [linkVoice] lines an
/// existing sound up (again).
///
/// ## Crop and position
///
/// [setFraming], [rotatePicture], [flipPicture], [setPictureCrop],
/// [setPicturePan] and [resetFraming] work on a main-track clip or an
/// overlay item alike (by id). Turning and mirroring take the crop and the
/// position along, so the same part of the picture stays in shot.
///
/// ## Overlay track
///
/// One extra video row ([Project.overlays]). Its items never overlap:
/// [addOverlay] puts an item at the wanted time when it is free there,
/// else right AFTER what is in the way; moving one ([updateOverlay] with a
/// new start) puts it at the free place nearest to where it was dropped;
/// trimming stops at the neighbours. Overlay items stay at their timeline
/// time when the main track is edited (like music).
class ProjectEditor {
  /// [clock] and [newId] exist for tests; they default to `DateTime.now`
  /// and a v4 UUID.
  ProjectEditor(
    Project project, {
    DateTime Function()? clock,
    String Function()? newId,
  })  : _project = project,
        _clock = clock ?? DateTime.now,
        _newId = newId ?? const Uuid().v4;

  final DateTime Function() _clock;
  final String Function() _newId;

  Project _project;
  Project get project => _project;

  /// Minimum length a clip, audio clip or title may be trimmed/split to.
  /// For a clip this holds both for the piece of source used and for the
  /// time it takes on the timeline (so a 4x clip needs 400 ms of source).
  static const int minDurationMs = 100;

  /// Longest time a photo may stay on screen.
  static const int maxPhotoDurationMs = 60000;

  /// Volume range for clips and audio (1.0 = unchanged).
  static const double minVolume = 0.0;
  static const double maxVolume = 2.0;

  /// Title text height range, as a fraction of canvas height.
  static const double minTitleFontSize = 0.01;
  static const double maxTitleFontSize = 0.5;

  /// Playback speed range of a video clip.
  static const double minSpeed = 0.25;
  static const double maxSpeed = 4.0;

  /// Range of brightness / contrast / saturation (0 = unchanged).
  static const double minAdjustment = -1.0;
  static const double maxAdjustment = 1.0;

  /// Centre zoom range (1 = whole picture).
  static const double minZoom = 1.0;
  static const double maxZoom = 4.0;

  /// Range of [Clip.voiceFocus] (0 = off).
  static const double minVoiceFocus = 0.0;
  static const double maxVoiceFocus = 1.0;

  /// Range of [Clip.transitionMs].
  static const int minTransitionMs = 100;
  static const int maxTransitionMs = 2000;

  /// Most sound tracks besides the video's own sound (the app's limit; the
  /// model has no limit).
  static const int maxSoundTracks = 3;

  /// Longest name of a sound track.
  static const int maxTrackNameLength = 40;

  /// Number of undo steps kept; the oldest are dropped beyond this.
  static const int maxUndoSteps = 100;

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  /// Where the titles are attached to the main track; see the class comment.
  TitleAnchors _anchors = TitleAnchors.empty;

  int _txDepth = 0;
  String? _txLabel;
  final List<String> _txHints = [];
  int _txEdits = 0;
  Project? _txStart;
  TitleAnchors _txStartAnchors = TitleAnchors.empty;
  bool _txRenamed = false;

  // Listeners ----------------------------------------------------------------
  final List<void Function()> _listeners = [];

  /// Calls [listener] after every change of [project].
  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    if (_listeners.isEmpty) return;
    for (final l in List<void Function()>.of(_listeners)) {
      if (_listeners.contains(l)) l();
    }
  }

  // History ------------------------------------------------------------------
  /// True while a [transaction] body is running.
  bool get inTransaction => _txDepth > 0;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Restores the previous snapshot. Ignored inside a [transaction].
  void undo() {
    if (inTransaction || _undo.isEmpty) return;
    _undoQuietly();
    _notify();
  }

  /// Re-applies the last undone step. Ignored inside a [transaction].
  void redo() {
    if (inTransaction || _redo.isEmpty) return;
    _redoQuietly();
    _notify();
  }

  void _undoQuietly() {
    final s = _undo.removeLast();
    _redo.add((
      project: _project,
      anchors: _anchors,
      hint: s.hint,
      time: s.time,
    ));
    _project = s.project.copyWith(updatedAt: _clock());
    _anchors = s.anchors;
  }

  void _redoQuietly() {
    final s = _redo.removeLast();
    _pushUndo(_project, _anchors, hint: s.hint, time: s.time);
    _project = s.project.copyWith(updatedAt: _clock());
    _anchors = s.anchors;
  }

  /// The editing history, oldest step first: the steps that are done
  /// ([historyPosition] of them, the newest of which made the current
  /// state), then the undone steps that [redo] would bring back, in the
  /// order it would. At most [maxUndoSteps] done steps are kept. Per
  /// editor: not saved with the project.
  ///
  /// Each step has a short name: the one the edit gave (e.g. "Removed 12
  /// silences"), else one worked out from what changed ([describeEdit];
  /// a [transaction] is one step and gets one name).
  List<HistoryStep> get history {
    final out = <HistoryStep>[];
    for (var i = 0; i < _undo.length; i++) {
      final s = _undo[i];
      final after = i + 1 < _undo.length ? _undo[i + 1].project : _project;
      out.add(HistoryStep(s.hint ?? _describe(s.project, after), s.time));
    }
    for (var i = _redo.length - 1; i >= 0; i--) {
      final s = _redo[i];
      final before = i == _redo.length - 1 ? _project : _redo[i + 1].project;
      out.add(HistoryStep(s.hint ?? _describe(before, s.project), s.time));
    }
    return out;
  }

  /// [describeEdit], remembered per pair of states (the list is asked for
  /// again after every edit).
  static final Expando<(Project, String)> _labels = Expando('edit labels');
  static String _describe(Project before, Project after) {
    final known = _labels[before];
    if (known != null && identical(known.$1, after)) return known.$2;
    final label = describeEdit(before, after);
    _labels[before] = (after, label);
    return label;
  }

  /// How many steps of [history] are done: 0 is the state before the
  /// first kept step.
  int get historyPosition => _undo.length;

  /// Goes to the state after step [position] of [history] (0: before the
  /// first) in one jump: as many undos or redos as it takes, with one
  /// notification. The later steps stay redoable until a new edit. Ignored
  /// inside a [transaction] and for positions out of range.
  void jumpToHistory(int position) {
    if (inTransaction) return;
    if (position < 0 || position > _undo.length + _redo.length) return;
    if (position == _undo.length) return;
    while (_undo.length > position) {
      _undoQuietly();
    }
    while (_undo.length < position && _redo.isNotEmpty) {
      _redoQuietly();
    }
    _notify();
  }

  /// Names the next edit (or, inside a [transaction], the whole
  /// transaction) in the [history], instead of the name worked out from
  /// what changed. For edits whose result does not tell what was done.
  void nameNextEdit(String label) => _nextHint = label;
  String? _nextHint;

  // Main track -------------------------------------------------------------
  /// Inserts [clip] at [index] (end of track when null). The index is
  /// clamped to the track and the clip's trim, volume, speed, look and
  /// transition values are clamped like any other edit. A clip whose id is
  /// already on the track gets a fresh id.
  void addClip(Clip clip, {int? index}) => _edit((p) {
        var c = _normalizeClip(clip);
        if (p.clips.any((e) => e.id == c.id)) c = c.copyWith(id: _freshId(p));
        final at = (index ?? p.clips.length).clamp(0, p.clips.length);
        return p.copyWith(clips: [...p.clips]..insert(at, c));
      });

  void removeClip(String clipId) => _edit((p) {
        if (!p.clips.any((c) => c.id == clipId)) return null;
        return p.copyWith(
          clips: [
            for (final c in p.clips)
              if (c.id != clipId) c,
          ],
        );
      });

  /// Moves the clip at [fromIndex] so that it ends up at [toIndex] (the
  /// index in the resulting list, clamped to the track). An out-of-range
  /// [fromIndex] is a no-op. Clips keep their own transition setting (it
  /// always means "from whatever clip is now before me").
  void moveClip(int fromIndex, int toIndex) => _edit((p) {
        final n = p.clips.length;
        if (fromIndex < 0 || fromIndex >= n) return null;
        final to = toIndex.clamp(0, n - 1);
        if (to == fromIndex) return null;
        final clips = [...p.clips];
        clips.insert(to, clips.removeAt(fromIndex));
        return p.copyWith(clips: clips);
      });

  /// Sets the trim range in SOURCE milliseconds; values are clamped to the
  /// source and to the minimum length (see [minDurationMs]; a sped-up clip
  /// needs `minDurationMs * speed` of source). For photos only [outMs] (the
  /// display time) matters.
  ///
  /// When only one edge is given the other edge stays where it is, so
  /// dragging the in-handle past the out-handle stops short of it instead
  /// of pushing it.
  void trimClip(String clipId, {int? inMs, int? outMs}) => _editClip(clipId, (c) {
        if (c.type == ClipType.photo) {
          if (outMs == null) return c;
          return c.copyWith(inMs: 0, outMs: _clampPhoto(outMs));
        }
        // A video without a known source length cannot be extended.
        final source = c.sourceDurationMs > 0 ? c.sourceDurationMs : c.outMs;
        final min = _minSpan(c.speed);
        var newIn = inMs ?? c.inMs;
        var newOut = outMs ?? c.outMs;
        if (inMs != null && outMs == null) {
          newIn = _clamp(newIn, 0, c.outMs - min);
        } else if (outMs != null && inMs == null) {
          newOut = _clamp(newOut, c.inMs + min, source);
        }
        final r = _clampRange(newIn, newOut, source, min);
        return c.copyWith(inMs: r.inMs, outMs: r.outMs);
      });

  /// Splits the clip under [timelineMs] in two. Returns false when the
  /// position is outside the track or so close to a clip edge that one of
  /// the pieces would be shorter than [minDurationMs].
  ///
  /// The clip is the one [Project.clipIndexAt] reports, so inside a
  /// transition it is the INCOMING clip, measured from where its transition
  /// begins. The position is converted to a source position through the
  /// clip's speed. The first half keeps the clip's id and its transition;
  /// the second half gets a new id, the same speed and look, and no
  /// transition.
  bool splitAt(int timelineMs) {
    final s = _split(_project, timelineMs);
    if (s == null) return false;
    _edit((_) => s.project);
    return true;
  }

  void setClipVolume(String clipId, double volume) => _editClip(
      clipId, (c) => c.copyWith(volume: _clampVolume(volume, c.volume)));

  void setClipMuted(String clipId, bool muted) =>
      _editClip(clipId, (c) => c.copyWith(muted: muted));

  void setClipFit(String clipId, FitMode fit) =>
      _editClip(clipId, (c) => c.copyWith(fit: fit));

  // Clip look, speed and transitions ---------------------------------------
  /// [minSpeed]..[maxSpeed]. Ignored for photos. The speed is also limited
  /// so that the clip still lasts [minDurationMs] on the timeline. The
  /// trim range (source) is untouched; the clip's timeline length changes.
  void setClipSpeed(String clipId, double speed) => _editClip(clipId, (c) {
        if (c.type == ClipType.photo) return c;
        final s = _capSpeed(_clampSpeed(speed, c.speed), c.sourceSpanMs);
        return c.copyWith(speed: s);
      });

  void setClipDenoise(String clipId, bool denoise) =>
      _editClip(clipId, (c) => c.copyWith(denoise: denoise));

  /// Voice focus strength, [minVoiceFocus]..[maxVoiceFocus] (0 = off).
  /// Ignored for photos (they have no sound).
  void setClipVoiceFocus(String clipId, double strength) =>
      _editClip(clipId, (c) {
        if (c.type == ClipType.photo) return c;
        return c.copyWith(voiceFocus: _clampFocus(strength, c.voiceFocus));
      });

  /// Which sound of the file a video clip uses: audio stream [track] (0 =
  /// first) and, for a stereo stream, [channel]. Null leaves a value as it
  /// is. The result is kept to what the file has ([Clip.audioStreams]): a
  /// track it does not have becomes 0, and a side other than
  /// [AudioChannel.both] needs a stream of exactly two channels. Ignored
  /// for photos.
  void setClipAudioSource(String clipId, {int? track, AudioChannel? channel}) =>
      _editClip(clipId, (c) {
        if (c.type == ClipType.photo) return c;
        return _normalizeAudioSource(c.copyWith(
            audioTrack: track ?? c.audioTrack,
            audioChannel: channel ?? c.audioChannel));
      });

  /// Replaces what is known about the audio streams of a clip's file
  /// ([Clip.audioStreams], from a probe), e.g. for a clip added by an older
  /// version. Track and side are kept to what the file has.
  ///
  /// Probe data is a fact about the FILE, not an edit: it is not an undo
  /// step of its own and not in the History. It is written into the
  /// current state and into every state on the undo and redo stacks (for
  /// the clips of the same file), so undo never takes it back.
  void setClipAudioStreams(String clipId, List<int> streams) {
    final c = _project.clips.where((c) => c.id == clipId).firstOrNull;
    if (c == null) return;
    final list = List<int>.unmodifiable(streams);
    setProbeData(c.path, audioStreams: list);
  }

  /// What a probe found out about the file at [path], for every clip,
  /// overlay item and sound clip that uses it: its audio streams
  /// ([Clip.audioStreams]), whether it has sound at all and its frame
  /// rate. Not an undo step (see [setClipAudioStreams]).
  void setProbeData(String path,
      {List<int>? audioStreams, bool? hasAudio, double? frameRate}) {
    Clip fixClip(Clip c) {
      if (c.path != path) return c;
      var n = c;
      if (audioStreams != null) n = n.copyWith(audioStreams: audioStreams);
      if (hasAudio != null) n = n.copyWith(hasAudio: hasAudio);
      if (frameRate != null && c.type == ClipType.video) {
        n = n.copyWith(frameRate: frameRate);
      }
      return identical(n, c) ? c : _normalizeAudioSource(n);
    }

    AudioClip fixAudio(AudioClip a) {
      if (a.path != path || audioStreams == null) return a;
      final n = a.copyWith(audioStreams: audioStreams);
      final s = _normalizeAudioSource(n.soundClip);
      return n.copyWith(audioTrack: s.audioTrack, audioChannel: s.audioChannel);
    }

    _editQuietly((p) {
      final clips = [for (final c in p.clips) fixClip(c)];
      final overlays = [
        for (final o in p.overlays) o.copyWith(clip: fixClip(o.clip)),
      ];
      final audio = [for (final a in p.audio) fixAudio(a)];
      return p.copyWith(clips: clips, overlays: overlays, audio: audio);
    });
  }

  /// Changes [_project] and every state on the undo / redo stacks (and the
  /// start of a running transaction) with [change], without an undo step.
  /// Listeners are told when the current state changed.
  void _editQuietly(Project Function(Project p) change,
      {bool evenIfCurrentSame = false}) {
    final next = change(_project);
    final same = _sameContent(next, _project);
    if (same && !evenIfCurrentSame) return;
    _Snapshot fix(_Snapshot s) => (
          project: change(s.project),
          anchors: s.anchors,
          hint: s.hint,
          time: s.time,
        );
    for (var i = 0; i < _undo.length; i++) {
      _undo[i] = fix(_undo[i]);
    }
    for (var i = 0; i < _redo.length; i++) {
      _redo[i] = fix(_redo[i]);
    }
    if (inTransaction) _txStart = change(_txStart!);
    if (same) return;
    _project = next.copyWith(updatedAt: _clock());
    _notify();
  }

  /// Copies settings of clip [fromClipId] to every other clip, as one undo
  /// step, and returns the number of clips that changed (0, and no undo
  /// step, when the id is unknown, no group is selected or nothing differs).
  ///
  ///  * [speed]: the playback speed, to VIDEO clips only (and only when the
  ///    source clip is a video). Each clip keeps its own limit: the speed is
  ///    capped so that the clip still lasts [minDurationMs].
  ///  * [look]: brightness, contrast, saturation, filter, warmth, zoom and
  ///    fit, to every clip (videos and photos).
  ///  * [sound]: volume, muted, denoise, voice focus and the sound source
  ///    (track and side), to VIDEO clips only (and only when the source
  ///    clip is a video). Track and side are kept to what each clip's file
  ///    has, see [setClipAudioSource].
  int applyClipSettingsToAll(String fromClipId,
      {bool speed = false, bool look = false, bool sound = false}) {
    final p = _project;
    final at = p.clips.indexWhere((c) => c.id == fromClipId);
    if (at < 0 || !(speed || look || sound)) return 0;
    final from = p.clips[at];
    var changed = 0;
    final clips = <Clip>[];
    for (final c in p.clips) {
      var n = c;
      if (c.id != from.id) {
        if (look) {
          n = n.copyWith(
            brightness: from.brightness,
            contrast: from.contrast,
            saturation: from.saturation,
            zoom: from.zoom,
            fit: from.fit,
            filter: from.filter,
            warmth: from.warmth,
          );
        }
        if (c.type == ClipType.video && from.type == ClipType.video) {
          if (speed) {
            n = n.copyWith(speed: _capSpeed(from.speed, c.sourceSpanMs));
          }
          if (sound) {
            n = _normalizeAudioSource(n.copyWith(
              volume: from.volume,
              muted: from.muted,
              denoise: from.denoise,
              voiceFocus: from.voiceFocus,
              audioTrack: from.audioTrack,
              audioChannel: from.audioChannel,
            ));
          }
        }
        if (!_sameJson(n.toJson(), c.toJson())) changed++;
      }
      clips.add(n);
    }
    if (changed == 0) return 0;
    final what = [
      if (look) 'look',
      if (speed) 'speed',
      if (sound) 'sound',
    ];
    final name = what.length == 1
        ? '${what.single[0].toUpperCase()}${what.single.substring(1)}'
        : 'Settings';
    _edit((p) => p.copyWith(clips: clips),
        hint: '$name of clip ${at + 1} applied to all clips');
    return changed;
  }

  /// Each -1..1; null leaves the value unchanged.
  void setClipAdjustments(String clipId,
          {double? brightness, double? contrast, double? saturation}) =>
      _editClip(
          clipId,
          (c) => c.copyWith(
                brightness: brightness == null
                    ? null
                    : _clampAdjustment(brightness, c.brightness),
                contrast: contrast == null
                    ? null
                    : _clampAdjustment(contrast, c.contrast),
                saturation: saturation == null
                    ? null
                    : _clampAdjustment(saturation, c.saturation),
              ));

  /// [minZoom]..[maxZoom].
  void setClipZoom(String clipId, double zoom) =>
      _editClip(clipId, (c) => c.copyWith(zoom: _clampZoom(zoom, c.zoom)));

  /// One-tap colour look of a clip ([LookFilter]).
  void setClipFilter(String clipId, LookFilter filter) =>
      _editClip(clipId, (c) => c.copyWith(filter: filter));

  /// Warmth of a clip, -1 (cooler) .. 1 (warmer), 0 = unchanged.
  void setClipWarmth(String clipId, double warmth) => _editClip(
      clipId, (c) => c.copyWith(warmth: _clampAdjustment(warmth, c.warmth)));

  /// "Reset look": brightness, contrast, saturation, filter, warmth and
  /// zoom back to unchanged, as one step named "Reset look on clip N".
  void resetLook(String clipId) {
    final i = _project.clips.indexWhere((c) => c.id == clipId);
    if (i < 0) return;
    _editClip(
        clipId,
        (c) => c.copyWith(
            brightness: 0,
            contrast: 0,
            saturation: 0,
            zoom: 1,
            filter: LookFilter.none,
            warmth: 0),
        hint: 'Reset look on ${_clipName(_project.clips[i], i)}');
  }

  /// Longest fade of a clip ([Clip.fadeInMs] / [Clip.fadeOutMs]).
  static const int maxClipFadeMs = 10000;

  /// Fade from black / to black (picture and the clip's own sound) at the
  /// start / end of a clip; null leaves a value as it is. Each is kept to
  /// 0..[maxClipFadeMs] and together to the clip's length.
  void setClipFades(String clipId, {int? fadeInMs, int? fadeOutMs}) =>
      _editClip(clipId, (c) {
        final d = c.durationMs;
        final fin = _clamp(fadeInMs ?? c.fadeInMs, 0, math.min(maxClipFadeMs, d));
        final fout = _clamp(
            fadeOutMs ?? c.fadeOutMs, 0, math.min(maxClipFadeMs, d - fin));
        return c.copyWith(fadeInMs: fin, fadeOutMs: fout);
      });

  /// Fade of the whole video from black at the start / to black at the end
  /// ([Project.fadeInMs], [Project.fadeOutMs]); null leaves a value as it
  /// is. Each 0..[Project.maxFadeMs] (the export uses at most half the
  /// video for each).
  void setProjectFades({int? fadeInMs, int? fadeOutMs}) => _edit((p) {
        final fin = _clamp(fadeInMs ?? p.fadeInMs, 0, Project.maxFadeMs);
        final fout = _clamp(fadeOutMs ?? p.fadeOutMs, 0, Project.maxFadeMs);
        if (fin == p.fadeInMs && fout == p.fadeOutMs) return null;
        return p.copyWith(fadeInMs: fin, fadeOutMs: fout);
      });

  // Duplicate, copy and paste -------------------------------------------------
  /// Puts a copy of clip [clipId] (same part of the file and every setting)
  /// right after it, as one step named "Duplicated clip N". Returns the
  /// copy's id; null for an unknown id. A clip whose sound is separated
  /// gets a linked sound of its own.
  String? duplicateClip(String clipId) {
    final p = _project;
    final i = p.clips.indexWhere((c) => c.id == clipId);
    if (i < 0) return null;
    final copy = p.clips[i].copyWith(id: _freshId(p));
    _edit((p) => p.copyWith(clips: [...p.clips]..insert(i + 1, copy)),
        hint: 'Duplicated ${_clipName(p.clips[i], i)}');
    return copy.id;
  }

  /// Puts a copy of title or caption [titleId] right after it on the
  /// timeline (same length, text and look). Returns the copy's id.
  String? duplicateTitle(String titleId) {
    final t = _project.titles.where((t) => t.id == titleId).firstOrNull;
    if (t == null) return null;
    final id = _freshIdNotIn({for (final x in _project.titles) x.id});
    final len = t.endMs - t.startMs;
    nameNextEdit(t.kind == TitleKind.caption
        ? 'Duplicated caption'
        : 'Duplicated title');
    addTitle(t.copyWith(id: id, startMs: t.endMs, endMs: t.endMs + len));
    return id;
  }

  /// Pastes [settings] (see [ClipSettings]) onto the clips [clipIds], as
  /// one step. Speed and sound only go to video clips (and only when they
  /// were copied from one). Returns how many clips changed.
  int pasteClipSettings(List<String> clipIds, ClipSettings settings) {
    final p = _project;
    final targets = {...clipIds};
    var changed = 0;
    int? only;
    final clips = <Clip>[];
    for (var i = 0; i < p.clips.length; i++) {
      final c = p.clips[i];
      if (!targets.contains(c.id)) {
        clips.add(c);
        continue;
      }
      var n = _normalizeClip(settings.applyTo(c));
      // A clip whose sound plays from a sound track stays muted.
      if (c.muted && p.audio.any((a) => a.sourceClipId == c.id)) {
        n = n.copyWith(muted: true);
      }
      final next = c.type == ClipType.video
          ? n.copyWith(speed: _capSpeed(n.speed, n.sourceSpanMs))
          : n;
      if (!_sameJson(next.toJson(), c.toJson())) {
        changed++;
        only = i;
      }
      clips.add(next);
    }
    if (changed == 0) return 0;
    _edit((p) => p.copyWith(clips: clips),
        hint: changed == 1
            ? 'Pasted settings on ${_clipName(p.clips[only!], only)}'
            : 'Pasted settings on $changed clips');
    return changed;
  }

  static String _clipName(Clip c, int index) =>
      '${c.type == ClipType.photo ? 'photo' : 'clip'} ${index + 1}';

  /// Transition from the previous clip into [clipId]. [durationMs] is
  /// clamped to [minTransitionMs]..[maxTransitionMs]; null keeps the clip's
  /// current value. The setting is stored on the first clip too, where it
  /// has no effect until another clip is moved in front of it.
  void setClipTransition(String clipId, TransitionType type,
          {int? durationMs}) =>
      _editClip(
          clipId,
          (c) => c.copyWith(
                transition: type,
                transitionMs: durationMs == null
                    ? null
                    : _clamp(durationMs, minTransitionMs, maxTransitionMs),
              ));

  /// Cuts [sourceRanges] (times in the clip's SOURCE file, e.g. detected
  /// silences) out of the clip, leaving the kept pieces as separate clips in
  /// its place. One undo step.
  ///
  /// Ranges may be unsorted and may overlap; they are limited to the clip's
  /// trim range. Kept pieces that would be shorter than [minDurationMs]
  /// are dropped as well. The first kept piece keeps the clip's id and
  /// transition; later pieces get new ids and no transition; all keep the
  /// speed and look. Photos, unknown ids, ranges that miss the clip and
  /// ranges that would remove the whole clip change nothing and return 0.
  ///
  /// Returns the number of separate stretches of source that were removed.
  int removeSourceRanges(
      String clipId, List<({int startMs, int endMs})> sourceRanges) {
    final p = _project;
    final index = p.clips.indexWhere((c) => c.id == clipId);
    if (index < 0) return 0;
    final clip = p.clips[index];
    if (clip.type == ClipType.photo) return 0;

    final cuts = <({int startMs, int endMs})>[];
    for (final r in sourceRanges) {
      final s = r.startMs < clip.inMs ? clip.inMs : r.startMs;
      final e = r.endMs > clip.outMs ? clip.outMs : r.endMs;
      if (e > s) cuts.add((startMs: s, endMs: e));
    }
    if (cuts.isEmpty) return 0;
    cuts.sort((a, b) => a.startMs.compareTo(b.startMs));

    // Kept stretches are what lies between the cuts.
    final kept = <({int inMs, int outMs})>[];
    void keep(int from, int to) {
      if (to <= from) return;
      final piece = clip.copyWith(inMs: from, outMs: to);
      if (_longEnough(piece)) kept.add((inMs: from, outMs: to));
    }

    var at = clip.inMs;
    for (final c in cuts) {
      if (c.startMs > at) keep(at, c.startMs);
      if (c.endMs > at) at = c.endMs;
    }
    keep(at, clip.outMs);
    if (kept.isEmpty) return 0;

    final removed = (kept.first.inMs > clip.inMs ? 1 : 0) +
        (kept.last.outMs < clip.outMs ? 1 : 0) +
        (kept.length - 1);
    if (removed == 0) return 0;

    final used = {for (final c in p.clips) c.id};
    final pieces = <Clip>[];
    for (var i = 0; i < kept.length; i++) {
      final k = kept[i];
      pieces.add(i == 0
          ? clip.copyWith(inMs: k.inMs, outMs: k.outMs)
          : clip.copyWith(
              id: _freshIdNotIn(used),
              inMs: k.inMs,
              outMs: k.outMs,
              transition: TransitionType.none,
            ));
    }
    // Its callers remove silences; the result alone would read as a cut.
    _edit(
        (p) => p.copyWith(
              clips: [...p.clips]..replaceRange(index, index + 1, pieces),
            ),
        hint: removed == 1 ? 'Removed 1 silence' : 'Removed $removed silences');
    return removed;
  }

  /// Splits the clip at [timelineMs] (same rules as [splitAt]) and inserts
  /// [photo] between the two halves. One undo step. Returns false, changing
  /// nothing, when the position cannot be split.
  ///
  /// [photo] should be a photo clip showing the RAW source frame at that
  /// position: its picture settings (fit, zoom, brightness, contrast,
  /// saturation) are replaced by those of the split clip so that the still
  /// matches the video around it, and its transition is removed. Its
  /// display time (`outMs`) is kept (clamped like any photo).
  bool insertFreezeFrame(int timelineMs, Clip photo) {
    final s = _split(_project, timelineMs);
    if (s == null) return false;
    final source = s.project.clips[s.index];
    var still = _normalizeClip(photo).copyWith(
      fit: source.fit,
      zoom: source.zoom,
      brightness: source.brightness,
      contrast: source.contrast,
      saturation: source.saturation,
      filter: source.filter,
      warmth: source.warmth,
      transition: TransitionType.none,
      framing: source.framing,
      fadeInMs: 0,
      fadeOutMs: 0,
    );
    if (s.project.clips.any((c) => c.id == still.id)) {
      still = still.copyWith(id: _freshId(s.project));
    }
    _edit((_) => s.project.copyWith(
          clips: [...s.project.clips]..insert(s.index + 1, still),
        ));
    return true;
  }

  // Audio ------------------------------------------------------------------
  /// Adds [audio] (clamped) on its track ([AudioClip.trackId]; a missing
  /// track is made, up to [maxSoundTracks]) by the placement rule (see
  /// "Sound tracks" in the class comment). An id that is already in use is
  /// replaced by a fresh one. Returns the id it was added under.
  String addAudio(AudioClip audio) {
    var a = _normalizeAudio(audio);
    if (_project.audio.any((e) => e.id == a.id)) {
      a = a.copyWith(id: _freshIdNotIn({for (final e in _project.audio) e.id}));
    }
    _edit((p) => placeOnTracks(p, a, maxTracks: maxSoundTracks, newId: _newId));
    return a.id;
  }

  void removeAudio(String audioId) => _edit((p) {
        if (!p.audio.any((a) => a.id == audioId)) return null;
        return p.copyWith(
          tracks: p.soundTracks,
          audio: [
            for (final a in p.audio)
              if (a.id != audioId) a,
          ],
        );
      });

  /// Replaces the audio clip with the same id by [audio] (clamped), keeping
  /// the track rules: a new track or a new start (a move) puts it at the
  /// nearest free place on that track; new trim points stop at the
  /// neighbours. A track that does not exist is ignored. Moving, trimming
  /// or changing the speed of a linked separated sound unlinks it.
  void updateAudio(AudioClip audio) => _edit((p) {
        final i = p.audio.indexWhere((a) => a.id == audio.id);
        if (i < 0) return null;
        final old = p.audio[i];
        var next = _normalizeAudio(audio);
        if (p.trackById(next.trackId) == null ||
            next.trackId == SoundTrack.videoId) {
          next = next.copyWith(trackId: old.trackId);
        }
        final timing = next.startMs != old.startMs ||
            next.inMs != old.inMs ||
            next.outMs != old.outMs ||
            next.speed != old.speed ||
            next.loopMs != old.loopMs ||
            next.trackId != old.trackId;
        if (timing && old.linked) next = next.copyWith(linked: false);
        final moved = next.trackId != old.trackId ||
            (next.inMs == old.inMs &&
                next.outMs == old.outMs &&
                next.speed == old.speed &&
                next.loopMs == old.loopMs);
        if (moved) {
          next = next.copyWith(
              startMs: nearestFreeStart(
                  p, next.trackId, next.startMs, next.durationMs,
                  ignoreId: next.id));
        } else {
          final limits = trimLimits(p, old);
          if (next.startMs < limits.lowest) {
            final cut = limits.lowest - next.startMs;
            next = next.copyWith(
                startMs: limits.lowest,
                inMs: next.inMs + (cut * next.speed).round());
          }
          final hi = limits.highest;
          if (hi != null && next.endMs > hi) {
            // A looped sound gets shorter repeats-wise, not a shorter pass.
            next = next.looped
                ? next.copyWith(loopMs: hi - next.startMs)
                : next.copyWith(
                    outMs: next.outMs - ((next.endMs - hi) * next.speed).round());
          }
          if (next.durationMs < minDurationMs ||
              next.sourceSpanMs < minDurationMs) {
            return null;
          }
          next = _normalizeAudio(next);
        }
        if (_sameJson(next.toJson(), old.toJson())) return null;
        return p.copyWith(tracks: p.soundTracks, audio: [...p.audio]..[i] = next);
      });

  /// "Fit music to video" (1.8, music panel and MCP `fit_music_to_video`):
  /// makes the sound [audioId] end exactly where the video ends, with a
  /// [kFitMusicFadeOutMs] fade-out. One undo step, History "Fitted music to
  /// the video" / "Looped music to fit the video".
  ///
  ///  * Longer than needed: cut so it ends with the video (not looped).
  ///  * Shorter: with [loop] its trimmed part repeats ([AudioClip.loopMs],
  ///    short cross-fades) up to the end; without, nothing changes and
  ///    [FitMusicResult.tooShort] says the user may want a loop.
  ///  * Another sound later on the same track is in the way: it stops just
  ///    before that one ([FitMusicResult.stoppedAtNext]).
  FitMusicResult fitMusicToVideo(String audioId, {bool loop = false}) {
    final p = _project;
    final a = p.audio.where((a) => a.id == audioId).firstOrNull;
    if (a == null) return FitMusicResult.notFound;
    final videoEnd = p.durationMs;
    if (videoEnd <= 0 || a.startMs >= videoEnd - minDurationMs) {
      return FitMusicResult.startsAfterVideo;
    }
    var target = videoEnd;
    var stopped = false;
    for (final o in p.audio) {
      if (o.id == a.id || o.trackId != a.trackId) continue;
      if (o.startMs >= a.startMs && o.startMs < target) {
        target = o.startMs;
        stopped = true;
      }
    }
    final needed = target - a.startMs;
    if (needed < minDurationMs) return FitMusicResult.stoppedAtNext;
    final speed = a.speed <= 0 ? 1.0 : a.speed;
    final available = ((a.sourceDurationMs - a.inMs) / speed).floor();
    AudioClip next;
    String label;
    var result = stopped ? FitMusicResult.stoppedAtNext : FitMusicResult.fitted;
    if (available >= needed) {
      next = a.copyWith(
          outMs: a.inMs + (needed * speed).round(), loopMs: 0);
      label = 'Fitted music to the video';
    } else if (!loop) {
      return FitMusicResult.tooShort;
    } else {
      next = a.copyWith(loopMs: needed);
      if (next.passMs < 4 * minDurationMs) return FitMusicResult.tooShort;
      label = 'Looped music to fit the video';
      if (!stopped) result = FitMusicResult.looped;
    }
    final fade = kFitMusicFadeOutMs < needed ~/ 2 ? kFitMusicFadeOutMs : needed ~/ 2;
    next = next.copyWith(fadeOutMs: fade);
    final before = _project;
    _edit((p) {
      final i = p.audio.indexWhere((x) => x.id == audioId);
      if (i < 0) return null;
      var n = _normalizeAudio(next);
      if (_sameJson(n.toJson(), p.audio[i].toJson())) return null;
      return p.copyWith(tracks: p.soundTracks, audio: [...p.audio]..[i] = n);
    }, hint: label);
    if (identical(before, _project)) return FitMusicResult.alreadyFits;
    return result;
  }

  /// Stops a looped sound from repeating: it plays its trimmed part once.
  /// One undo step ("Music no longer loops").
  void stopLoop(String audioId) {
    final a = _project.audio.where((a) => a.id == audioId).firstOrNull;
    if (a == null || !a.looped) return;
    final next = a.copyWith(loopMs: 0);
    _edit((p) {
      final i = p.audio.indexWhere((x) => x.id == audioId);
      if (i < 0) return null;
      return p.copyWith(
          tracks: p.soundTracks,
          audio: [...p.audio]..[i] = _normalizeAudio(next));
    });
  }

  /// Sets where the music came from ([AudioClip.credit]) without an undo
  /// step of its own (it is a fact about the file, like probe data).
  void setMusicCredit(String path, MusicCredit credit) {
    _editQuietly((p) => p.copyWith(audio: [
          for (final a in p.audio)
            a.path == path ? a.copyWith(credit: credit) : a,
        ]));
  }

  /// Moves a sound clip to another track, at [startMs] (default: where it
  /// is), by the "moving" rule. Same as [updateAudio] with a new track.
  void moveAudioToTrack(String audioId, String trackId, {int? startMs}) {
    final a = _project.audio.where((a) => a.id == audioId).firstOrNull;
    if (a == null) return;
    updateAudio(a.copyWith(trackId: trackId, startMs: startMs));
  }

  /// "Lower music under speech" for every track that is not a speech
  /// track, and the default for music tracks made later
  /// ([Project.duckMusic]). One undo step.
  void setDuckMusic(bool duck) => _edit((p) {
        final tracks = [
          for (final t in p.soundTracks)
            t.speech ? t : t.copyWith(duck: duck),
        ];
        final next = p.copyWith(duckMusic: duck, tracks: tracks);
        return _sameContent(p, next) ? null : next;
      }, hint: duck ? 'Lower music under speech on' : 'Lower music under speech off');

  // Sound tracks -----------------------------------------------------------
  /// Adds an empty sound track at the bottom and returns its id; null when
  /// there are already [maxSoundTracks]. [name] defaults to the first of
  /// "Voice", "Music", "Effects" not in use. A "Voice" track counts as
  /// speech; a "Music" track lowers itself under speech when the project's
  /// default ([Project.duckMusic]) says so.
  String? addSoundTrack({String? name}) {
    final p = _project;
    if (p.soundTracks.length >= maxSoundTracks) return null;
    var n = (name ?? '').trim();
    if (n.isEmpty) n = nextTrackName(p);
    if (n.length > maxTrackNameLength) n = n.substring(0, maxTrackNameLength);
    final id = _freshIdNotIn({
      for (final t in p.soundTracks) t.id,
      SoundTrack.videoId,
      kMusicTrackId,
    });
    _edit((p) => p.copyWith(tracks: [...p.soundTracks, newTrack(p, id, n)]));
    return id;
  }

  /// Renames a sound track. The name is trimmed and cut to
  /// [maxTrackNameLength]; an empty name or an unknown id is ignored.
  void renameSoundTrack(String trackId, String name) {
    var n = name.trim();
    if (n.isEmpty) return;
    if (n.length > maxTrackNameLength) n = n.substring(0, maxTrackNameLength);
    _editTrack(trackId, (t) => t.copyWith(name: n));
  }

  /// Volume (clamped like a clip's), mute, solo, "Lower this track under
  /// speech" ([duck]) and "counts as speech" ([speech]) of a sound track;
  /// null leaves a value as it is. [trackId] [SoundTrack.videoId] is the
  /// video's own sound (volume, mute and solo only).
  void setSoundTrack(String trackId,
      {double? volume, bool? muted, bool? solo, bool? duck, bool? speech}) {
    final video = trackId == SoundTrack.videoId;
    _editTrack(
        trackId,
        (t) => t.copyWith(
              volume: volume == null ? null : _clampVolume(volume, t.volume),
              muted: muted,
              solo: solo,
              duck: video ? null : duck,
              speech: video ? null : speech,
            ));
  }

  /// Deletes an EMPTY sound track. Returns false (changing nothing) when
  /// the track has sound clips or does not exist.
  bool removeSoundTrack(String trackId) {
    final p = _project;
    if (!p.soundTracks.any((t) => t.id == trackId)) return false;
    if (p.audio.any((a) => a.trackId == trackId)) return false;
    _edit((p) => p.copyWith(
        tracks: [for (final t in p.soundTracks) if (t.id != trackId) t]));
    return true;
  }

  /// Moves sound track [trackId] up ([by] < 0) or down in the list of
  /// tracks (what is shown top to bottom). Returns false when it cannot
  /// move that way.
  bool moveSoundTrack(String trackId, int by) {
    final tracks = [..._project.soundTracks];
    final i = tracks.indexWhere((t) => t.id == trackId);
    if (i < 0 || by == 0) return false;
    final to = (i + by).clamp(0, tracks.length - 1);
    if (to == i) return false;
    tracks.insert(to, tracks.removeAt(i));
    _edit((p) => p.copyWith(tracks: tracks));
    return true;
  }

  void _editTrack(String trackId, SoundTrack Function(SoundTrack t) change) =>
      _edit((p) {
        if (trackId == SoundTrack.videoId) {
          final next = change(p.videoSound);
          if (_sameJson(next.toJson(), p.videoSound.toJson())) return null;
          return p.copyWith(videoSound: next);
        }
        final tracks = [...p.soundTracks];
        final i = tracks.indexWhere((t) => t.id == trackId);
        if (i < 0) return null;
        final next = change(tracks[i]);
        if (_sameJson(next.toJson(), tracks[i].toJson())) return null;
        tracks[i] = next;
        // One truth for "Lower music under speech": the default for music
        // tracks made later follows what the tracks say now.
        final music = [for (final t in tracks) if (!t.speech) t];
        return p.copyWith(
            tracks: tracks,
            duckMusic: music.isEmpty
                ? p.duckMusic
                : music.every((t) => t.duck));
      });

  // Separate sound -----------------------------------------------------------
  /// Why the sound of clip [clipId] cannot be separated, in words for the
  /// user; null when it can.
  static String? separateSoundProblem(Project p, String clipId) {
    final c = p.clips.where((c) => c.id == clipId).firstOrNull;
    if (c == null) return 'That clip is not in the project.';
    if (c.type != ClipType.video) return 'A photo has no sound to separate.';
    if (!c.hasAudio) return 'This clip has no sound.';
    if (c.muted && p.audio.any((a) => a.isSeparated && a.sourceClipId == c.id)) {
      return 'The sound of this clip is already separated.';
    }
    return null;
  }

  /// The track [separateSound] uses when none is given: the first speech
  /// track, else a new "Voice" track (null: it would be made), else the
  /// first track.
  static String? defaultVoiceTrack(Project p) {
    for (final t in p.soundTracks) {
      if (t.speech) return t.id;
    }
    if (p.soundTracks.length < maxSoundTracks) return null;
    return p.soundTracks.first.id;
  }

  /// "Separate sound": copies the sound of video clip [clipId] to a linked
  /// sound clip on [trackId] (default: [defaultVoiceTrack], a "Voice" track
  /// made when there is none) at the clip's place, and mutes the clip. The
  /// clip's speed is carried over (pitch kept), as are its volume, clean-up,
  /// voice focus, track and side. One undo step. Returns the new sound
  /// clip's id, or null when [separateSoundProblem] has an answer.
  String? separateSound(String clipId, {String? trackId}) {
    final ids = _separate([clipId], trackId);
    return ids.isEmpty ? null : ids.single;
  }

  /// [separateSound] for every video clip with sound that is not separated
  /// yet, as one undo step. Returns the number of clips.
  int separateAllSound({String? trackId}) {
    final ids = [
      for (final c in _project.clips)
        if (separateSoundProblem(_project, c.id) == null && !c.muted) c.id,
    ];
    return _separate(ids, trackId).length;
  }

  List<String> _separate(List<String> clipIds, String? trackId) {
    var p = _project;
    final todo = [
      for (final id in clipIds)
        if (separateSoundProblem(p, id) == null) id,
    ];
    if (todo.isEmpty) return const [];
    var track = trackId;
    if (track != null && p.trackById(track) == null) track = null;
    if (track == SoundTrack.videoId) track = null;
    track ??= defaultVoiceTrack(p);
    if (track == null) {
      track = _freshIdNotIn({
        for (final t in p.soundTracks) t.id,
        SoundTrack.videoId,
        kMusicTrackId,
      });
      p = p.copyWith(
          tracks: [...p.soundTracks, newTrack(p, track, 'Voice')]);
    } else {
      p = p.copyWith(tracks: p.soundTracks);
    }
    final used = {for (final a in p.audio) a.id};
    final added = <String>[];
    final linkedTrack = <String, String>{
      for (final a in p.audio)
        if (a.linked && a.isSeparated) a.sourceClipId!: a.trackId,
    };
    final clips = [...p.clips];
    for (final clipId in todo) {
      final i = clips.indexWhere((c) => c.id == clipId);
      final c = clips[i];
      final id = _freshIdNotIn(used);
      final base = AudioClip(
        id: id,
        path: c.path,
        sourceDurationMs: c.sourceDurationMs,
        startMs: 0,
        inMs: c.inMs,
        outMs: c.outMs,
        volume: c.volume,
        trackId: track,
        speed: c.speed,
        denoise: c.denoise,
        voiceFocus: c.voiceFocus,
        audioTrack: c.audioTrack,
        audioChannel: c.audioChannel,
        audioStreams: c.audioStreams,
        sourceClipId: c.id,
        linked: true,
      );
      final prev = i > 0 ? clips[i - 1].id : null;
      final placed = mirrorClip(p, i, base,
          prevOnTrack: prev != null && linkedTrack[prev] == track);
      p = placeOnTracks(p, placed, maxTracks: maxSoundTracks, newId: _newId);
      final put = p.audio.firstWhere((a) => a.id == id);
      linkedTrack[c.id] = put.trackId;
      clips[i] = c.copyWith(muted: true);
      p = p.copyWith(clips: [...clips]);
      added.add(id);
    }
    final n = _project.clips.indexWhere((c) => c.id == todo.first) + 1;
    final result = p;
    _edit((_) => result,
        hint: todo.length == 1
            ? 'Separated sound of clip $n'
            : 'Separated sound of ${todo.length} clips');
    return added;
  }

  /// Puts a separated sound back on its video clip: the sound clip is
  /// deleted and the clip plays its own sound again, with the sound clip's
  /// volume, clean-up, voice focus, track and side. Returns false (changing
  /// nothing) when [audioId] is not a separated sound or its clip is gone.
  bool reattachSound(String audioId) {
    final p = _project;
    final a = p.audio.where((a) => a.id == audioId).firstOrNull;
    if (a == null || !a.isSeparated) return false;
    final i = p.clips.indexWhere((c) => c.id == a.sourceClipId);
    if (i < 0) return false;
    final c = p.clips[i];
    _edit(
        (p) => p.copyWith(
              tracks: p.soundTracks,
              clips: [...p.clips]..[i] = _normalizeAudioSource(c.copyWith(
                  muted: false,
                  volume: a.volume,
                  denoise: a.denoise,
                  voiceFocus: a.voiceFocus,
                  audioTrack: a.audioTrack,
                  audioChannel: a.audioChannel,
                )),
              audio: [
                for (final x in p.audio)
                  if (x.id != audioId) x,
              ],
            ),
        hint: 'Put sound back on clip ${i + 1}');
    return true;
  }

  // Voice recorded separately ------------------------------------------------
  /// "Voice for the video": adds the separately recorded [voice] (its file,
  /// length, volume and sound settings; id, place and trim are ignored)
  /// lined up with video clip [clipId] at [offsetMs]
  /// ([AudioClip.syncOffsetMs]: time in the voice file = time in the clip's
  /// file + offset), as LINKED sound: one item for every clip of that video
  /// file, each following its clip like a separated sound does (see
  /// "Separated sound follows its clip" in the class comment and
  /// [buildVoice] for the choice of track: its own speech track, named
  /// [trackName], default "Voice", "Voice 2"...). [muteClips] mutes the
  /// camera's own sound of those clips. One undo step, named "Added voice
  /// for clip N, lined up (+0.42 s)" when [linedUp], else "Added voice for
  /// clip N (not lined up)".
  ///
  /// Returns the ids of the new items; throws [VoiceProblem] (changing
  /// nothing) when it cannot be added.
  List<String> addVoice(
    AudioClip voice, {
    required String clipId,
    required int offsetMs,
    String? trackId,
    String? trackName,
    bool muteClips = true,
    bool linedUp = true,
  }) {
    final p = _project;
    final built = buildVoice(p, _voiceTemplate(voice),
        clipId: clipId,
        offsetMs: offsetMs,
        trackId: trackId,
        trackName: trackName,
        muteClips: muteClips,
        maxTracks: maxSoundTracks,
        newId: _newId);
    final n = p.clips.indexWhere((c) => c.id == clipId) + 1;
    _edit((_) => built.project,
        hint: linedUp
            ? 'Added voice for clip $n, lined up (${offsetLabel(offsetMs)})'
            : 'Added voice for clip $n (not lined up)');
    return built.ids;
  }

  /// "+0.42 s" / "−1.50 s" / "0.00 s": an offset for History and messages.
  static String offsetLabel(int offsetMs) {
    final s = (offsetMs.abs() / 1000).toStringAsFixed(2);
    return offsetMs > 0 ? '+$s s' : (offsetMs < 0 ? '\u2212$s s' : '$s s');
  }

  static AudioClip _voiceTemplate(AudioClip voice) {
    final n = _normalizeAudio(voice.copyWith(
        inMs: 0,
        outMs: voice.sourceDurationMs,
        startMs: 0,
        speed: 1.0,
        loopMs: 0));
    return n.copyWith(clearCredit: true);
  }

  /// "Line up with the video" for a sound that is already in the project
  /// (plain music that is really a voice, or a voice whose link was
  /// broken): [audioId] and the other items of the same recording
  /// ([voiceGroup]) are replaced by linked items for every clip of
  /// [clipId]'s file at [offsetMs], on the same track when that is a speech
  /// track, else by [buildVoice]'s rule. Volume, clean-up, voice focus,
  /// track and side are kept. One undo step ("Lined up voice with clip N
  /// (+0.42 s)"). Throws [VoiceProblem], changing nothing, when it cannot.
  List<String> linkVoice(
    String audioId, {
    required String clipId,
    required int offsetMs,
    String? trackName,
    bool? muteClips,
  }) {
    final p = _project;
    final a = p.audio.where((a) => a.id == audioId).firstOrNull;
    if (a == null) throw const VoiceProblem('That sound is not in the project.');
    final gone = {for (final x in voiceGroup(p, a)) x.id};
    final without = p.copyWith(
      tracks: p.soundTracks,
      audio: [
        for (final x in p.audio)
          if (!gone.contains(x.id)) x,
      ],
    );
    final speechTrack = p.trackById(a.trackId)?.speech ?? false;
    final target = p.clips.where((c) => c.id == clipId).firstOrNull;
    final built = buildVoice(without, _voiceTemplate(a),
        clipId: clipId,
        offsetMs: offsetMs,
        trackId: speechTrack ? a.trackId : null,
        trackName: trackName,
        muteClips: muteClips ?? (target?.muted ?? false),
        maxTracks: maxSoundTracks,
        newId: _newId);
    final n = p.clips.indexWhere((c) => c.id == clipId) + 1;
    _edit((_) => built.project,
        hint: 'Lined up voice with clip $n (${offsetLabel(offsetMs)})');
    return built.ids;
  }

  /// Nudges a linked voice recording: [deltaMs] > 0 makes it heard LATER
  /// against the picture, < 0 earlier (its offset changes by -[deltaMs]).
  /// Every item of the recording moves ([voiceGroup]); they stay linked.
  /// One undo step. Returns false for anything that is not a linked voice.
  bool nudgeVoice(String audioId, int deltaMs) {
    final p = _project;
    final a = p.audio.where((a) => a.id == audioId).firstOrNull;
    if (a == null || !a.isVoice || !a.linked || deltaMs == 0) return false;
    final ids = {
      for (final x in voiceGroup(p, a))
        if (x.linked) x.id,
    };
    final offset = a.syncOffsetMs! - deltaMs;
    final ms = deltaMs.abs();
    _edit(
        (p) => p.copyWith(tracks: p.soundTracks, audio: [
              for (final x in p.audio)
                ids.contains(x.id) ? x.copyWith(syncOffsetMs: offset) : x,
            ]),
        hint: 'Nudged voice $ms ms ${deltaMs > 0 ? 'later' : 'earlier'}');
    return true;
  }

  /// Ends the link of a voice recording with its clips: every item of the
  /// recording ([voiceGroup]) stays exactly where it is and from then on
  /// keeps its place like music. [unmuteClips] switches the camera's own
  /// sound of those clips back on. One undo step. Returns false for
  /// anything that is not a linked voice.
  bool unlinkVoice(String audioId, {bool unmuteClips = true}) {
    final p = _project;
    final a = p.audio.where((a) => a.id == audioId).firstOrNull;
    if (a == null || !a.isVoice || !a.linked) return false;
    final group = [
      for (final x in voiceGroup(p, a))
        if (x.linked) x,
    ];
    final ids = {for (final x in group) x.id};
    final clipIds = {for (final x in group) x.sourceClipId};
    final n = p.clips.indexWhere((c) => c.id == a.sourceClipId) + 1;
    _edit(
        (p) => p.copyWith(
              tracks: p.soundTracks,
              audio: [
                for (final x in p.audio)
                  ids.contains(x.id) ? x.copyWith(linked: false) : x,
              ],
              clips: unmuteClips
                  ? [
                      for (final c in p.clips)
                        clipIds.contains(c.id) && c.muted
                            ? c.copyWith(muted: false)
                            : c,
                    ]
                  : p.clips,
            ),
        hint: 'Unlinked voice from clip $n');
    return true;
  }

  /// Mutes / unmutes the camera's own sound of the clips the voice
  /// recording [audioId] is lined up with. One undo step.
  bool setVoiceClipsMuted(String audioId, bool muted) {
    final p = _project;
    final a = p.audio.where((a) => a.id == audioId).firstOrNull;
    if (a == null || !a.isVoice) return false;
    final clipIds = {for (final x in voiceGroup(p, a)) x.sourceClipId};
    if (!p.clips.any((c) => clipIds.contains(c.id) && c.muted != muted)) {
      return false;
    }
    _edit(
        (p) => p.copyWith(clips: [
              for (final c in p.clips)
                clipIds.contains(c.id) && c.type == ClipType.video
                    ? c.copyWith(muted: muted)
                    : c,
            ]),
        hint: muted ? 'Muted the camera sound' : 'Unmuted the camera sound');
    return true;
  }

  /// Clean-up of a sound clip (like [setClipDenoise]).
  void setAudioDenoise(String audioId, bool denoise) =>
      _editAudio(audioId, (a) => a.copyWith(denoise: denoise));

  /// Voice focus of a sound clip (like [setClipVoiceFocus]).
  void setAudioVoiceFocus(String audioId, double strength) => _editAudio(
      audioId, (a) => a.copyWith(voiceFocus: _clampFocus(strength, a.voiceFocus)));

  /// Track and side of a sound clip's file (like [setClipAudioSource]).
  void setAudioSource(String audioId, {int? track, AudioChannel? channel}) =>
      _editAudio(
          audioId,
          (a) => a.copyWith(
              audioTrack: track ?? a.audioTrack,
              audioChannel: channel ?? a.audioChannel));

  /// What is known about the audio streams of a sound clip's file. Not an
  /// undo step (see [setClipAudioStreams]).
  void setAudioStreams(String audioId, List<int> streams) {
    final a = _project.audio.where((a) => a.id == audioId).firstOrNull;
    if (a == null) return;
    setProbeData(a.path, audioStreams: List<int>.unmodifiable(streams));
  }

  void _editAudio(String audioId, AudioClip Function(AudioClip a) change) =>
      _edit((p) {
        final i = p.audio.indexWhere((a) => a.id == audioId);
        if (i < 0) return null;
        final next = _normalizeAudio(change(p.audio[i]));
        if (_sameJson(next.toJson(), p.audio[i].toJson())) return null;
        return p.copyWith(tracks: p.soundTracks, audio: [...p.audio]..[i] = next);
      });

  // Crop and position --------------------------------------------------------
  /// Rotation, mirroring, crop and position of the picture of [itemId] (a
  /// main-track clip or an overlay item), kept to their ranges: rotation in
  /// quarter turns, the crop inside the picture and at least
  /// [CropRect.minSize] each way, the pan -1..1.
  void setFraming(String itemId, Framing framing) =>
      _editPicture(itemId, (_) => framing);

  /// Only the crop of [itemId]'s framing.
  void setPictureCrop(String itemId, CropRect crop) =>
      _editPicture(itemId, (f) => f.copyWith(crop: crop));

  /// Only the position (pan) of [itemId]; null keeps a value.
  void setPicturePan(String itemId, {double? x, double? y}) =>
      _editPicture(itemId, (f) => f.copyWith(panX: x, panY: y));

  /// Turns [itemId]'s picture a quarter turn ([clockwise] or not); the crop
  /// and the position turn with it.
  void rotatePicture(String itemId, {bool clockwise = true}) =>
      _editPicture(itemId, (f) => f.turned(clockwise ? 1 : -1));

  /// Mirrors [itemId]'s picture left to right ([horizontal]) or top to
  /// bottom; the crop and the position are mirrored with it.
  void flipPicture(String itemId, {required bool horizontal}) =>
      _editPicture(itemId, (f) => f.flipped(horizontal: horizontal));

  /// No crop, no rotation, no mirroring, centred.
  void resetFraming(String itemId) =>
      _editPicture(itemId, (_) => Framing.none);

  void _editPicture(String itemId, Framing Function(Framing f) change) {
    final p = _project;
    if (p.clips.any((c) => c.id == itemId)) {
      _edit((p) {
        final i = p.clips.indexWhere((c) => c.id == itemId);
        final c = p.clips[i];
        final f = change(c.framing).normalized();
        if (f == c.framing) return null;
        return p.copyWith(clips: [...p.clips]..[i] = c.copyWith(framing: f));
      });
    } else if (p.overlays.any((o) => o.id == itemId)) {
      _edit((p) {
        final i = p.overlays.indexWhere((o) => o.id == itemId);
        final o = p.overlays[i];
        final f = change(o.clip.framing).normalized();
        if (f == o.clip.framing) return null;
        return p.copyWith(
            overlays: [...p.overlays]
              ..[i] = o.copyWith(clip: o.clip.copyWith(framing: f)));
      });
    }
  }

  // Overlay track ------------------------------------------------------------
  /// Adds [overlay] (clamped) to the overlay track at its start, or right
  /// after the item in the way when that place is taken. An id already in
  /// use (by an overlay or a main-track clip) is replaced by a fresh one.
  /// Returns the id it was added under.
  String addOverlay(OverlayClip overlay) {
    var o = _normalizeOverlay(overlay);
    final used = {
      for (final x in _project.overlays) x.id,
      for (final c in _project.clips) c.id,
    };
    if (used.contains(o.id)) {
      o = o.copyWith(clip: o.clip.copyWith(id: _freshIdNotIn(used)));
    }
    final placed = o.copyWith(
        startMs: _overlayStartAfter(_project.overlays, o.startMs, o.durationMs));
    _edit((p) => p.copyWith(overlays: _sortedOverlays([...p.overlays, placed])));
    return placed.id;
  }

  void removeOverlay(String overlayId) => _edit((p) {
        if (!p.overlays.any((o) => o.id == overlayId)) return null;
        return p.copyWith(
            overlays: [for (final o in p.overlays) if (o.id != overlayId) o]);
      });

  /// Replaces the overlay item with the same id by [overlay] (clamped),
  /// keeping the track's rule: a new start with the same trim and speed (a
  /// move) goes to the free place nearest to it; new trim points stop at
  /// the neighbours.
  void updateOverlay(OverlayClip overlay) => _edit((p) {
        final i = p.overlays.indexWhere((o) => o.id == overlay.id);
        if (i < 0) return null;
        final old = p.overlays[i];
        var next = _normalizeOverlay(overlay);
        final others = [for (final o in p.overlays) if (o.id != old.id) o];
        final sameTiming = next.clip.inMs == old.clip.inMs &&
            next.clip.outMs == old.clip.outMs &&
            next.clip.speed == old.clip.speed;
        if (sameTiming) {
          if (next.startMs != old.startMs) {
            next = next.copyWith(
                startMs: _overlayNearestFree(
                    others, next.startMs, next.durationMs));
          }
        } else {
          // Trimmed (or a new speed): stop at the neighbours.
          var lowest = 0;
          int? highest;
          for (final o in others) {
            if (o.endMs <= old.startMs && o.endMs > lowest) lowest = o.endMs;
            if (o.startMs >= old.endMs &&
                (highest == null || o.startMs < highest)) {
              highest = o.startMs;
            }
          }
          final speed = next.clip.type == ClipType.photo ? 1.0 : next.clip.speed;
          if (next.startMs < lowest) {
            final cut = lowest - next.startMs;
            next = next.copyWith(
                startMs: lowest,
                clip: next.clip.type == ClipType.photo
                    ? next.clip.copyWith(outMs: next.clip.outMs - cut)
                    : next.clip.copyWith(
                        inMs: next.clip.inMs + (cut * speed).round()));
          }
          final hi = highest;
          if (hi != null && next.endMs > hi) {
            final over = next.endMs - hi;
            next = next.copyWith(
                clip: next.clip.copyWith(
                    outMs: next.clip.outMs - (over * speed).round()));
          }
          if (next.durationMs < minDurationMs) return null;
          next = _normalizeOverlay(next);
          if (_overlayClashes(others, next.startMs, next.durationMs)) {
            return null;
          }
        }
        if (_sameJson(next.toJson(), old.toJson())) return null;
        return p.copyWith(
            overlays: _sortedOverlays([...others, next]));
      });

  static List<OverlayClip> _sortedOverlays(List<OverlayClip> list) =>
      list..sort((a, b) => a.startMs.compareTo(b.startMs));

  static bool _overlayClashes(List<OverlayClip> others, int start, int dur) =>
      others.any((o) => start < o.endMs && o.startMs < start + dur);

  /// [start] when it is free for [dur], else the end of what is in the way
  /// (again and again).
  static int _overlayStartAfter(List<OverlayClip> others, int start, int dur) {
    var s = start < 0 ? 0 : start;
    final sorted = [...others]..sort((a, b) => a.startMs.compareTo(b.startMs));
    for (var guard = 0; guard <= sorted.length; guard++) {
      final hit = sorted
          .where((o) => s < o.endMs && o.startMs < s + dur)
          .firstOrNull;
      if (hit == null) return s;
      s = hit.endMs;
    }
    return s;
  }

  /// The free start for [dur] nearest to [start] (never before 0).
  static int _overlayNearestFree(
      List<OverlayClip> others, int start, int dur) {
    final want = start < 0 ? 0 : start;
    if (!_overlayClashes(others, want, dur)) return want;
    final sorted = [...others]..sort((a, b) => a.startMs.compareTo(b.startMs));
    int? best;
    void consider(int lo, int? hi) {
      // A gap from lo to hi (open end when null).
      if (hi != null && hi - lo < dur) return;
      final latest = hi == null ? null : hi - dur;
      var at = want < lo ? lo : want;
      if (latest != null && at > latest) at = latest;
      if (best == null || (at - want).abs() < (best! - want).abs()) best = at;
    }
    var prevEnd = 0;
    for (final o in sorted) {
      consider(prevEnd, o.startMs);
      if (o.endMs > prevEnd) prevEnd = o.endMs;
    }
    consider(prevEnd, null);
    return best ?? prevEnd;
  }

  static OverlayClip _normalizeOverlay(OverlayClip o) {
    final c = _normalizeClip(o.clip).copyWith(
      transition: TransitionType.none,
      framing: o.clip.framing.normalized(),
    );
    final duration = c.durationMs;
    final fadeIn = _clamp(o.fadeInMs, 0, duration);
    final fadeOut = _clamp(o.fadeOutMs, 0, duration - fadeIn);
    final size = o.size.isNaN
        ? 0.33
        : o.size.clamp(OverlayClip.minSize, OverlayClip.maxSize).toDouble();
    return o.copyWith(
      clip: c,
      startMs: o.startMs < 0 ? 0 : o.startMs,
      fadeInMs: fadeIn,
      fadeOutMs: fadeOut,
      size: size,
      x: _clampUnit(o.x, 0.75),
      y: _clampUnit(o.y, 0.75),
    );
  }

  /// Replaces the list of automatic cuts ([Project.autoCuts]).
  void setAutoCuts(List<AutoCut> cuts) =>
      _edit((p) => p.copyWith(autoCuts: List.unmodifiable(cuts)));

  // Titles -----------------------------------------------------------------
  /// Adds [title] (clamped). An id that is already in use is replaced by a
  /// fresh one.
  void addTitle(TitleOverlay title) => addTitles([title]);

  /// Adds many titles at once (subtitle import) as one undo step. Each is
  /// clamped like [addTitle]; ids already in use (in the project or earlier
  /// in [titles]) are replaced by fresh ones. An empty list is a no-op.
  void addTitles(List<TitleOverlay> titles) => _edit((p) {
        if (titles.isEmpty) return null;
        final used = {for (final t in p.titles) t.id};
        final added = <TitleOverlay>[];
        for (final title in titles) {
          var t = _normalizeTitle(title);
          if (used.contains(t.id)) t = t.copyWith(id: _freshIdNotIn(used));
          used.add(t.id);
          added.add(t);
        }
        return p.copyWith(titles: [...p.titles, ...added]);
      });

  void removeTitle(String titleId) => _edit((p) {
        if (!p.titles.any((t) => t.id == titleId)) return null;
        return p.copyWith(
          titles: [
            for (final t in p.titles)
              if (t.id != titleId) t,
          ],
        );
      });

  /// Replaces the title with the same id by [title] (clamped).
  void updateTitle(TitleOverlay title) => _edit((p) {
        final i = p.titles.indexWhere((t) => t.id == title.id);
        if (i < 0) return null;
        final next = _normalizeTitle(title);
        if (_sameJson(next.toJson(), p.titles[i].toJson())) return null;
        return p.copyWith(titles: [...p.titles]..[i] = next);
      });

  // Publishing notes and markers (1.14) -------------------------------------

  /// The text that goes with the video when it is posted
  /// ([Project.publishing]). One undo step, named after what changed
  /// ("Publishing title", "Chapters (6)", ...; see edit_labels.dart).
  void setPublishingNotes(PublishingNotes notes) => _edit(
      (p) => p.publishing == notes ? null : p.copyWith(publishing: notes));

  /// Most markers a project keeps.
  static const int maxMarkers = 200;

  /// Drops a "good moment" marker at [timelineMs] (kept inside the video).
  /// Returns its id; null when the project has no clips, a marker is
  /// already within 200 ms of that time, or there are [maxMarkers].
  String? addMarker(int timelineMs, {String label = ''}) {
    final p = _project;
    if (p.clips.isEmpty || p.markers.length >= maxMarkers) return null;
    final ms = _clamp(timelineMs, 0, p.durationMs);
    if (p.markers.any((m) => (m.ms - ms).abs() < 200)) return null;
    final id = _freshIdNotIn({for (final m in p.markers) m.id});
    _edit((p) => p.copyWith(
        markers: List.unmodifiable([
      ...p.markers,
      Marker(id: id, ms: ms, label: label.trim()),
    ]..sort((a, b) => a.ms.compareTo(b.ms)))));
    return id;
  }

  /// Removes the marker [markerId]; false when there is none.
  bool removeMarker(String markerId) {
    if (!_project.markers.any((m) => m.id == markerId)) return false;
    _edit((p) => p.copyWith(markers: [
          for (final m in p.markers)
            if (m.id != markerId) m,
        ]));
    return true;
  }

  /// Moves or renames the marker with [marker]'s id.
  void updateMarker(Marker marker) => _edit((p) {
        final i = p.markers.indexWhere((m) => m.id == marker.id);
        if (i < 0) return null;
        final next = marker.copyWith(
            ms: _clamp(marker.ms, 0, p.durationMs), label: marker.label.trim());
        if (next == p.markers[i]) return null;
        return p.copyWith(
            markers: List.unmodifiable(
                ([...p.markers]..[i] = next)
                  ..sort((a, b) => a.ms.compareTo(b.ms))));
      });

  // Project ----------------------------------------------------------------
  void setAspect(CanvasAspect aspect) =>
      _edit((p) => p.aspect == aspect ? null : p.copyWith(aspect: aspect));

  /// Size of the exported video ([Project.videoSize]).
  void setVideoSize(VideoSize size) => _edit(
      (p) => p.videoSize == size ? null : p.copyWith(videoSize: size));

  /// Renames the project. The name is trimmed; an empty name is ignored.
  ///
  /// A rename is NOT an undo step: listeners are notified (so it is saved)
  /// but [undo] and [redo] never change the name back - the earlier states
  /// on the undo and redo stacks take the new name too.
  void rename(String name) {
    final n = name.trim();
    if (n.isEmpty || n == _project.name) return;
    _Snapshot renamed(_Snapshot s) => (
          project: s.project.copyWith(name: n),
          anchors: s.anchors,
          hint: s.hint,
          time: s.time,
        );
    for (var i = 0; i < _undo.length; i++) {
      _undo[i] = renamed(_undo[i]);
    }
    for (var i = 0; i < _redo.length; i++) {
      _redo[i] = renamed(_redo[i]);
    }
    if (inTransaction) {
      _txStart = _txStart!.copyWith(name: n);
      _txRenamed = true;
    }
    _project = _project.copyWith(name: n, updatedAt: _clock());
    _notify();
  }

  /// Every media file the current project, the start of a running
  /// transaction and every undo / redo state use: what the unused-media
  /// clean-up must leave alone while this editor is open.
  Set<String> get mediaPathsInHistory {
    final out = <String>{};
    void addAll(Project p) {
      for (final c in p.clips) {
        out.add(c.path);
      }
      for (final a in p.audio) {
        out.add(a.path);
      }
      for (final o in p.overlays) {
        out.add(o.path);
      }
    }

    addAll(_project);
    final start = _txStart;
    if (start != null) addAll(start);
    for (final s in _undo) {
      addAll(s.project);
    }
    for (final s in _redo) {
      addAll(s.project);
    }
    return out;
  }

  /// Like [relinkMedia] for several files at once, but NOT an undo step
  /// and in every undo / redo state too: the app moved files it owns
  /// (e.g. out of the cache folder), which is not the user's edit.
  void relinkMediaQuietly(Map<String, String> moved) {
    if (moved.isEmpty) return;
    String to(String path) => moved[path] ?? path;
    _editQuietly(evenIfCurrentSame: true, (p) => p.copyWith(
          clips: [for (final c in p.clips) c.copyWith(path: to(c.path))],
          audio: [for (final a in p.audio) a.copyWith(path: to(a.path))],
          overlays: [
            for (final o in p.overlays)
              o.copyWith(clip: o.clip.copyWith(path: to(o.path))),
          ],
        ));
  }

  /// Points every clip, audio clip and overlay item that uses the file [oldPath] at
  /// [newPath] instead (a file that was moved or re-imported). One undo
  /// step; nothing happens when no item uses [oldPath] or the paths are
  /// equal. Trim ranges and sizes are kept, so [newPath] should be the same
  /// recording.
  void relinkMedia(String oldPath, String newPath) => _edit((p) {
        if (oldPath == newPath || newPath.isEmpty) return null;
        if (!p.clips.any((c) => c.path == oldPath) &&
            !p.audio.any((a) => a.path == oldPath) &&
            !p.overlays.any((o) => o.path == oldPath)) {
          return null;
        }
        return p.copyWith(
          clips: [
            for (final c in p.clips)
              c.path == oldPath ? c.copyWith(path: newPath) : c,
          ],
          audio: [
            for (final a in p.audio)
              a.path == oldPath ? a.copyWith(path: newPath) : a,
          ],
          overlays: [
            for (final o in p.overlays)
              o.path == oldPath
                  ? o.copyWith(clip: o.clip.copyWith(path: newPath))
                  : o,
          ],
        );
      });

  /// Groups the edits made inside [body] into one undo step (used while
  /// dragging a trim handle or a slider).
  ///
  /// Listeners are still notified after every edit inside [body], so the
  /// preview follows a drag. Nested calls join the outermost transaction.
  /// If the project ends up with the same content it started with, no undo
  /// step is recorded. [undo] and [redo] are ignored inside [body]. If
  /// [body] throws, the edits made so far are kept as one step and the
  /// error is rethrown.
  void transaction(void Function() body, {String? label}) {
    if (_txDepth == 0) {
      _txStart = _project;
      _txStartAnchors = _anchors;
      _txRenamed = false;
      _txLabel = label ?? _nextHint;
      _nextHint = null;
      _txHints.clear();
      _txEdits = 0;
    }
    _txDepth++;
    try {
      body();
    } finally {
      _txDepth--;
      if (_txDepth == 0) {
        final start = _txStart!;
        _txStart = null;
        if (!identical(start, _project)) {
          if (_sameContent(start, _project)) {
            // Only a rename (not an undo step) keeps its new save time.
            if (!_txRenamed) _project = start;
            _anchors = _txStartAnchors;
          } else {
            // One name for the whole transaction: its own, else the one
            // name all its edits gave, else worked out from the result.
            final hints = _txHints.toSet();
            _pushUndo(start, _txStartAnchors,
                hint: _txLabel ??
                    (hints.length == 1 && _txHints.length == _txEdits
                        ? hints.single
                        : null),
                time: _clock());
            _redo.clear();
            _anchors = _anchors.settled();
          }
          _notify();
        } else {
          _anchors = _txStartAnchors;
        }
        _txStartAnchors = TitleAnchors.empty;
      }
    }
  }

  // Internals --------------------------------------------------------------
  void _edit(Project? Function(Project p) change, {String? hint}) {
    final before = _project;
    var next = change(before);
    if (next == null || identical(next, before)) return;
    hint = _nextHint ?? hint;
    _nextHint = null;
    next = _withOriginalSize(before, next);
    final anchorsBefore = _anchors;
    final moved = retimeTitles(
      before: before,
      after: next,
      state: _anchors,
      minDurationMs: minDurationMs,
    );
    if (moved != null) {
      if (!identical(moved.titles, next.titles)) {
        next = next.copyWith(titles: moved.titles);
      }
      _anchors = inTransaction ? moved.state : moved.state.settled();
    }
    next = syncLinkedSound(before, next,
        maxTracks: maxSoundTracks, newId: _newId);
    // "Good moment" markers stay on their picture (marker_follow.dart).
    final markers = retimeMarkers(before, next);
    if (!identical(markers, next.markers)) {
      next = next.copyWith(markers: markers);
    }
    if (!inTransaction) {
      _pushUndo(before, anchorsBefore, hint: hint, time: _clock());
      _redo.clear();
    } else {
      _txEdits++;
      if (hint != null) _txHints.add(hint);
    }
    _project = next.copyWith(updatedAt: _clock());
    _notify();
  }

  /// Captures the size the canvas is derived from when the first clip
  /// arrives, and forgets it when the last clip goes (see
  /// [Project.originalWidth]). A project from an older version, which has
  /// clips but no captured size, captures the clip that is first BEFORE the
  /// edit, so that the edit itself cannot change the shape of the video.
  static Project _withOriginalSize(Project before, Project next) {
    final captured = next.originalWidth != null && next.originalHeight != null;
    if (next.clips.isEmpty) {
      return captured ? next.copyWith(clearOriginalSize: true) : next;
    }
    if (captured) return next;
    final size = Project.originalSizeOf(
        before.clips.isNotEmpty ? before.clips.first : next.clips.first);
    if (size.width <= 0 || size.height <= 0) return next;
    return next.copyWith(
        originalWidth: size.width, originalHeight: size.height);
  }

  void _editClip(String clipId, Clip Function(Clip c) change,
          {String? hint}) =>
      _edit((p) {
        final i = p.clips.indexWhere((c) => c.id == clipId);
        if (i < 0) return null;
        final next = change(p.clips[i]);
        if (_sameJson(next.toJson(), p.clips[i].toJson())) return null;
        return p.copyWith(clips: [...p.clips]..[i] = next);
      }, hint: hint);

  /// [p] with the clip under [timelineMs] split in two, and the index of
  /// the first half; null when the position cannot be split.
  ({Project project, int index})? _split(Project p, int timelineMs) {
    if (p.clips.isEmpty || timelineMs < 0 || timelineMs >= p.durationMs) {
      return null;
    }
    final index = p.clipIndexAt(timelineMs);
    final clip = p.clips[index];
    final offset = timelineMs - p.clipStartMs(index);
    if (offset <= 0 || offset >= clip.durationMs) return null;
    var first = clip;
    var second = clip;
    if (clip.type == ClipType.photo) {
      first = clip.copyWith(inMs: 0, outMs: offset);
      second = clip.copyWith(inMs: 0, outMs: clip.durationMs - offset);
    } else {
      final cut = clip.sourceMsAt(offset);
      first = clip.copyWith(outMs: cut);
      second = clip.copyWith(inMs: cut);
    }
    if (!_longEnough(first) || !_longEnough(second)) return null;
    second = second.copyWith(id: _freshId(p), transition: TransitionType.none);
    return (
      project: p.copyWith(
        clips: [...p.clips]
          ..[index] = first
          ..insert(index + 1, second),
      ),
      index: index,
    );
  }

  String _freshId(Project p) => _freshIdNotIn({for (final c in p.clips) c.id});

  /// A new id that is not in [used]; it is added to [used].
  String _freshIdNotIn(Set<String> used) {
    var id = _newId();
    while (used.contains(id)) {
      id = _newId();
    }
    used.add(id);
    return id;
  }

  void _pushUndo(Project p, TitleAnchors anchors,
      {String? hint, required DateTime time}) {
    _undo.add((project: p, anchors: anchors, hint: hint, time: time));
    if (_undo.length > maxUndoSteps) {
      _undo.removeRange(0, _undo.length - maxUndoSteps);
    }
  }

  static bool _sameJson(Map<String, dynamic> a, Map<String, dynamic> b) =>
      jsonEncode(a) == jsonEncode(b);

  // Every field of the model is part of toJson, so this covers them all.
  static bool _sameContent(Project a, Project b) {
    // The captured canvas size alone is not a change worth an undo step.
    String key(Project p) => jsonEncode(p.toJson()
      ..remove('updatedAt')
      ..remove('originalWidth')
      ..remove('originalHeight'));
    return key(a) == key(b);
  }

  /// Like [num.clamp] but tolerates an empty range (returns [lo]).
  static int _clamp(int v, int lo, int hi) =>
      hi < lo ? lo : (v < lo ? lo : (v > hi ? hi : v));

  static int _clampPhoto(int ms) => _clamp(ms, minDurationMs, maxPhotoDurationMs);

  static double _clampVolume(double v, double fallback) =>
      v.isNaN ? fallback : v.clamp(minVolume, maxVolume).toDouble();

  static double _clampUnit(double v, double fallback) =>
      v.isNaN ? fallback : v.clamp(0.0, 1.0).toDouble();

  static double _clampFocus(double v, double fallback) =>
      v.isNaN ? fallback : v.clamp(minVoiceFocus, maxVoiceFocus).toDouble();

  /// [c] with [Clip.audioTrack] and [Clip.audioChannel] kept to what its
  /// file is known to have: an unknown track becomes 0, a side needs a
  /// stream of exactly two channels.
  static Clip _normalizeAudioSource(Clip c) {
    final track = c.audioTrackInUse;
    final probe = c.copyWith(audioTrack: track);
    return probe.copyWith(
        audioChannel: probe.audioChannelsInUse == 2
            ? c.audioChannel
            : AudioChannel.both);
  }

  static double _clampSpeed(double v, double fallback) =>
      v.isNaN ? fallback : v.clamp(minSpeed, maxSpeed).toDouble();

  static double _clampAdjustment(double v, double fallback) =>
      v.isNaN ? fallback : v.clamp(minAdjustment, maxAdjustment).toDouble();

  static double _clampZoom(double v, double fallback) =>
      v.isNaN ? fallback : v.clamp(minZoom, maxZoom).toDouble();

  /// Shortest stretch of source a video clip playing at [speed] may use.
  static int _minSpan(double speed) {
    final scaled = (minDurationMs * speed).ceil();
    return scaled > minDurationMs ? scaled : minDurationMs;
  }

  /// Limits [speed] so that [sourceSpanMs] of source still lasts
  /// [minDurationMs] on the timeline. Never limits below normal speed.
  static double _capSpeed(double speed, int sourceSpanMs) {
    final cap = sourceSpanMs >= minDurationMs
        ? sourceSpanMs / minDurationMs
        : 1.0;
    return speed > cap ? cap : speed;
  }

  /// Whether [c] is long enough both in the source and on the timeline.
  static bool _longEnough(Clip c) =>
      c.sourceSpanMs >= minDurationMs && c.durationMs >= minDurationMs;

  /// Clamps a trim range to `[0, source]` keeping at least [min].
  /// A [source] of 0 or less means the length is unknown (no upper bound).
  /// A source shorter than [min] is used whole.
  static ({int inMs, int outMs}) _clampRange(int inMs, int outMs, int source,
      [int min = minDurationMs]) {
    if (source <= 0) {
      final i = inMs < 0 ? 0 : inMs;
      return (inMs: i, outMs: outMs < i + min ? i + min : outMs);
    }
    if (source < min) return (inMs: 0, outMs: source);
    final i = _clamp(inMs, 0, source - min);
    return (inMs: i, outMs: _clamp(outMs, i + min, source));
  }

  static Clip _normalizeClip(Clip c) {
    final look = _normalizeAudioSource(c).copyWith(
      volume: _clampVolume(c.volume, 1.0),
      voiceFocus: c.type == ClipType.photo ? 0 : _clampFocus(c.voiceFocus, 0),
      brightness: _clampAdjustment(c.brightness, 0),
      contrast: _clampAdjustment(c.contrast, 0),
      saturation: _clampAdjustment(c.saturation, 0),
      zoom: _clampZoom(c.zoom, 1.0),
      transitionMs: _clamp(c.transitionMs, minTransitionMs, maxTransitionMs),
      framing: c.framing.normalized(),
      warmth: _clampAdjustment(c.warmth, 0),
      fadeInMs: _clamp(c.fadeInMs, 0, maxClipFadeMs),
      fadeOutMs: _clamp(c.fadeOutMs, 0, maxClipFadeMs),
    );
    if (c.type == ClipType.photo) {
      return look.copyWith(
          inMs: 0, outMs: _clampPhoto(c.outMs - c.inMs), speed: 1.0);
    }
    final r = _clampRange(c.inMs, c.outMs, c.sourceDurationMs);
    return look.copyWith(
      inMs: r.inMs,
      outMs: r.outMs,
      speed: _capSpeed(_clampSpeed(c.speed, 1.0), r.outMs - r.inMs),
    );
  }

  static AudioClip _normalizeAudio(AudioClip a) {
    final speed = _clampSpeed(a.speed, 1.0);
    final r = _clampRange(a.inMs, a.outMs, a.sourceDurationMs, _minSpan(speed));
    var sized = a.copyWith(inMs: r.inMs, outMs: r.outMs, speed: speed);
    // A loop is at least one pass long; one that is shorter (or a pass too
    // short to repeat) is simply not looped.
    if (sized.loopMs < 0 ||
        (sized.loopMs > 0 &&
            (sized.loopMs <= sized.passMs || sized.passMs < 4 * minDurationMs))) {
      sized = sized.copyWith(loopMs: 0);
    }
    final duration = sized.durationMs;
    final fadeIn = _clamp(a.fadeInMs, 0, duration);
    final fadeOut = _clamp(a.fadeOutMs, 0, duration - fadeIn);
    final sound = _normalizeAudioSource(sized.soundClip);
    return sized.copyWith(
      startMs: a.startMs < 0 ? 0 : a.startMs,
      volume: _clampVolume(a.volume, 1.0),
      fadeInMs: fadeIn,
      fadeOutMs: fadeOut,
      voiceFocus: _clampFocus(a.voiceFocus, 0),
      audioTrack: sound.audioTrack,
      audioChannel: sound.audioChannel,
    );
  }

  static TitleOverlay _normalizeTitle(TitleOverlay t) {
    final start = t.startMs < 0 ? 0 : t.startMs;
    return t.copyWith(
      startMs: start,
      endMs: t.endMs < start + minDurationMs ? start + minDurationMs : t.endMs,
      x: _clampUnit(t.x, 0.5),
      y: _clampUnit(t.y, 0.5),
      fontSize: t.fontSize.isNaN
          ? 0.06
          : t.fontSize.clamp(minTitleFontSize, maxTitleFontSize).toDouble(),
    );
  }
}

/// A state on the undo or redo stack, with the step that leads away from
/// it (undo stack) or to it (redo stack): its own name when the edit gave
/// one ([hint]; otherwise [describeEdit] names it) and when it was made.
typedef _Snapshot = ({
  Project project,
  TitleAnchors anchors,
  String? hint,
  DateTime time,
});

/// One step of the editing history ([ProjectEditor.history]).
class HistoryStep {
  const HistoryStep(this.label, this.time);

  /// What the step did, e.g. "Speed 1.25× on clip 2".
  final String label;

  /// When it was made (when it was first made, for a redone step).
  final DateTime time;

  @override
  String toString() => 'HistoryStep($label)';
}

/// The settings "Copy settings" takes from a clip and "Paste settings"
/// puts on others: the look (brightness, contrast, saturation, filter,
/// warmth), fit and zoom, crop and position, and - from a video clip - the
/// speed and the sound settings (volume, mute, clean-up, voice focus,
/// track and side). Not the trim, the transition or the fades: those
/// belong to the place of a clip.
class ClipSettings {
  const ClipSettings._(this.from);

  /// The settings of [clip].
  factory ClipSettings.of(Clip clip) => ClipSettings._(clip);

  final Clip from;

  bool get fromVideo => from.type == ClipType.video;

  /// [c] with these settings (speed and sound only for a video clip, and
  /// only when they come from one).
  Clip applyTo(Clip c) {
    var n = c.copyWith(
      brightness: from.brightness,
      contrast: from.contrast,
      saturation: from.saturation,
      filter: from.filter,
      warmth: from.warmth,
      fit: from.fit,
      zoom: from.zoom,
      framing: from.framing,
    );
    if (c.type == ClipType.video && fromVideo) {
      n = n.copyWith(
        speed: from.speed,
        volume: from.volume,
        muted: from.muted,
        denoise: from.denoise,
        voiceFocus: from.voiceFocus,
        audioTrack: from.audioTrack,
        audioChannel: from.audioChannel,
      );
    }
    return n;
  }
}

/// Fade-out "Fit music to video" gives the music.
const int kFitMusicFadeOutMs = 2000;

/// What [ProjectEditor.fitMusicToVideo] did.
enum FitMusicResult {
  /// Cut to end with the video.
  fitted,

  /// Repeats to the end of the video.
  looped,

  /// Ends just before the next sound on its track (fitted or looped).
  stoppedAtNext,

  /// Shorter than the video; ask whether to loop it.
  tooShort,

  /// Already ends with the video with that fade (no undo step).
  alreadyFits,

  /// It starts after (or at) the end of the video.
  startsAfterVideo,

  notFound,
}
