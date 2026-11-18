import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/model/project.dart';
import '../../media/clip_audio.dart';
import '../../media/processed_sound.dart' show clipNeedsProcessedSound;
import 'timeline_player.dart';

/// What one layer of the preview shows.
enum PreviewLayerKind {
  /// The picture of the video player [PreviewLayer.deck].
  video,
  photo,

  /// The file is gone or will not play.
  missing,

  /// Nothing to show yet (a video that is still loading).
  blank,
}

@immutable
class PreviewLayer {
  const PreviewLayer(this.kind, this.clip, [this.deck]);

  final PreviewLayerKind kind;

  /// The clip whose picture this is: it decides shape, fit, zoom and colour.
  /// Around a change of file this can still be the clip shown before, whose
  /// last frame the player keeps until the new file is loaded.
  final Clip clip;

  /// Which video player shows it, for [PreviewLayerKind.video].
  final int? deck;

  @override
  bool operator ==(Object other) =>
      other is PreviewLayer &&
      other.kind == kind &&
      identical(other.clip, clip) &&
      other.deck == deck;

  @override
  int get hashCode => Object.hash(kind, clip, deck);

  @override
  String toString() => 'PreviewLayer(${kind.name}, ${clip.id}, deck $deck)';
}

/// The picture at the playhead: the current clip and, during a transition,
/// the clip it comes from.
@immutable
class PreviewScene {
  const PreviewScene({
    this.current,
    this.outgoing,
    this.transition = TransitionType.none,
    this.progress = 1,
  });

  final PreviewLayer? current;

  /// The previous clip while a transition runs, else null.
  final PreviewLayer? outgoing;

  /// [TransitionType.none] whenever [outgoing] is null.
  final TransitionType transition;

  /// 0 at the start of the transition (only [outgoing] visible), 1 at its
  /// end (only [current]).
  final double progress;
}

/// What the overlay track shows at the playhead.
@immutable
class OverlayView {
  const OverlayView(this.kind, this.item, {this.deck});

  /// [PreviewLayerKind.video] (on overlay player [deck]), photo, missing,
  /// or blank (a video that is still loading: the main picture shows).
  final PreviewLayerKind kind;
  final OverlayClip item;

  /// Index into [PlaybackController.overlayPlayers].
  final int? deck;

  @override
  bool operator ==(Object other) =>
      other is OverlayView &&
      other.kind == kind &&
      identical(other.item, item) &&
      other.deck == deck;

  @override
  int get hashCode => Object.hash(kind, item, deck);
}

/// Plays a [Project] as one continuous timeline.
///
/// * Video clips are played by up to two [TimelinePlayer]s ("decks"). The
///   front deck plays the clip under the playhead and its reported position
///   is the clock. The back deck either plays the previous clip while a
///   transition overlaps the two, or holds the NEXT clip, loaded and paused
///   at its in point shortly before the current one ends, so that the cut
///   is a swap of decks instead of a file load.
/// * Photos (and clips whose file is missing or will not play) have no
///   player; [tick] moves time forward for them.
/// * Sound clips ([AudioClip], on sound tracks) are played by a small pool
///   of players: per track the clip under the playhead and the next one
///   (loaded ahead), so at most two per track. Each plays at its track's
///   level (volume, mute, solo: [Project.trackGain]), its speed, and with
///   its sound options (processed sound file when ready, else the live
///   filters), exactly like a video clip's own sound.
///
/// * Overlay items ([Project.overlays]) with a video play on up to two more
///   video players ("overlay decks"), on the timeline clock like sound
///   clips: the item under the playhead, and the next one loaded ahead
///   (so that two items in a row, e.g. camera angles, cut without a
///   gap). Each plays at its speed, with its volume and fades at the level
///   of the video's own sound; a player that drifts from the clock is put
///   back. Photos need no player.
///
/// All timeline <-> source conversions go through the [Project] helpers, so
/// clip speed and transition overlaps are honoured everywhere.
///
/// The owner calls [tick] once per frame while [playing] and
/// [updateProject] after every edit.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this._project,
    required TimelinePlayer video,
    this._createVideoPlayer,
    required this._createAudioPlayer,
    bool Function(String path)? fileExists,
  }) : _fileExists = fileExists ?? ((p) => File(p).existsSync()) {
    _addDeck(video);
    _index();
    _makeBackIfUseful();
    _syncVideo();
  }

  /// Two clips cut from the same file play through without a seek when the
  /// second starts within this distance of the first one's end.
  static const int seamToleranceMs = 60;

  /// After a seek, positions further than this from the target are leftovers
  /// from before the seek and are ignored.
  static const int settleToleranceMs = 1500;

  /// A video that reports no position for this long is treated as unplayable
  /// and timed by the clock instead, so that playback never hangs on it.
  static const int stallLimitMs = 4000;

  /// Music that starts more than this late (its file had to be loaded
  /// first) is moved to where the playhead is by then.
  static const int audioLateToleranceMs = 80;

  /// Music is loaded (paused) this long before the playhead reaches it, so
  /// that it starts on time whatever else is being loaded just then.
  static const int audioPreloadLeadMs = 1500;

  /// The next clip is loaded into the back deck this long (timeline time)
  /// before the current clip hands over to it.
  static const int preloadLeadMs = 3000;

  /// Between two position reports of the player the clock is carried on by
  /// [tick] for at most this long, only to leave a clip on time.
  static const int extrapolateLimitMs = 100;

  final TimelinePlayer Function()? _createVideoPlayer;
  final TimelinePlayer Function() _createAudioPlayer;
  final bool Function(String path) _fileExists;

  Project _project;
  bool _playing = false;
  bool _disposed = false;
  final ValueNotifier<int> _position = ValueNotifier(0);

  /// Start of every clip on the timeline, from [Project.clipStartMs].
  List<int> _starts = const [];

  // Video decks.
  final List<_Deck> _decks = [];
  int _frontIndex = 0;

  /// What the back deck is doing; see [_syncBack].
  Object? _backKey;
  bool _backIsOutgoing = false;

  /// True while the front deck's last picture may stand in for a clip whose
  /// file is still loading (it was on screen just before).
  bool _held = false;
  int _stallMs = 0;

  final Map<String, bool> _existsCache = {};
  final Set<String> _unplayable = {};
  final List<_AudioSlot> _audio = [];

  /// The sound clips of each track in timeline order, for [_project].
  Map<String, List<AudioClip>> _trackClips = const {};

  Project get project => _project;
  bool get playing => _playing;

  /// Timeline position in ms. Changes every frame during playback; listen to
  /// this instead of the controller for anything that follows the playhead.
  ValueListenable<int> get position => _position;
  int get positionMs => _position.value;

  /// "Hear original": while true the clips play without their sound
  /// filters (clean-up, voice focus, one side only), to compare. The track
  /// choice stays. Not part of the project.
  ValueListenable<bool> get hearOriginal => _hearOriginal;
  final ValueNotifier<bool> _hearOriginal = ValueNotifier(false);

  set hearOriginalSound(bool on) {
    if (_disposed || _hearOriginal.value == on) return;
    _hearOriginal.value = on;
    _applyVolumes(exact: true);
    _syncClipSound(reposition: true);
    _syncAudio();
  }

  String _filterFor(Clip clip) =>
      _hearOriginal.value ? '' : previewAudioFilter(clip);
  int get durationMs => _project.durationMs;

  /// Index of the clip under the playhead, -1 for an empty project. During
  /// a transition this is the incoming clip.
  int get clipIndex => _indexAt(positionMs);
  Clip? get currentClip {
    final i = clipIndex;
    return i < 0 ? null : _project.clips[i];
  }

  /// The first video player (deck 0).
  TimelinePlayer get video => _decks.first.player;

  /// The video players made so far: one, or two once a second was needed.
  List<TimelinePlayer> get videoPlayers =>
      [for (final d in _decks) d.player];

  /// The deck that plays the clip under the playhead.
  int get frontDeck => _frontIndex;

  /// The file the front deck holds right now; null while it is loading
  /// another one.
  String? get loadedVideoPath => _front.loadedPath;

  _Deck get _front => _decks[_frontIndex];
  _Deck? get _back => _decks.length > 1 ? _decks[1 - _frontIndex] : null;

  /// True when [path] is gone or the player could not play it.
  bool isMissing(String path) =>
      _unplayable.contains(path) ||
      !(_existsCache[path] ??= _fileExists(path));

  /// Forgets what is known about files so they are checked again.
  void recheckFiles() {
    if (_disposed) return;
    _existsCache.clear();
    _unplayable.clear();
    _syncVideo();
    notifyListeners();
  }

  bool _isPlayableVideo(Clip? c) =>
      c != null && c.type == ClipType.video && !isMissing(c.path);

  // Timeline geometry --------------------------------------------------------

  void _index() {
    _starts = [
      for (var i = 0; i < _project.clips.length; i++) _project.clipStartMs(i)
    ];
    _trackClips = {
      // Looped sounds as their repeats (AudioClip.loopPieces), like the
      // export: two players overlap at each repeat and cross-fade.
      for (final t in _project.soundTracks)
        t.id: [
          for (final a in _project.clipsOnTrack(t.id)) ...a.loopPieces,
        ],
    };
  }

  /// Same answer as [Project.clipIndexAt], from the cached starts.
  int _indexAt(int timeMs) {
    var found = -1;
    for (var i = 0; i < _starts.length; i++) {
      if (i == 0 || _starts[i] <= timeMs) found = i;
    }
    return found;
  }

  /// Where clip [i] hands over to the next one (the start of the next
  /// clip, which is before this clip's end when they overlap), or its end
  /// for the last clip.
  int _handoverMs(int i) => i + 1 < _starts.length
      ? _starts[i + 1]
      : _starts[i] + _project.clips[i].durationMs;

  /// Length of the transition into clip [i] if the playhead is inside it.
  int _activeOverlapMs(int i) {
    final overlap = _project.transitionOverlapMs(i);
    return overlap > 0 && positionMs < _starts[i] + overlap ? overlap : 0;
  }

  /// Progress of the transition into the current clip: 0 at its start, 1 at
  /// its end and whenever no transition is running.
  double get transitionProgress {
    final i = clipIndex;
    if (i < 0) return 1;
    final overlap = _activeOverlapMs(i);
    if (overlap <= 0) return 1;
    return ((positionMs - _starts[i]) / overlap).clamp(0.0, 1.0);
  }

  /// Source position of clip [i] at the playhead.
  int _sourceMs(int i) =>
      _project.clips[i].sourceMsAt(positionMs - _starts[i]);

  // Commands ---------------------------------------------------------------

  void play() {
    if (_disposed || _playing || durationMs <= 0) return;
    if (positionMs >= durationMs) _position.value = 0;
    _playing = true;
    _syncVideo();
    _syncAudio(reposition: true);
    _syncClipSound(reposition: true);
    _syncOverlay(reposition: true);
    notifyListeners();
  }

  void pause() {
    if (_disposed || !_playing) return;
    _playing = false;
    _syncVideo();
    _syncAudio();
    _syncClipSound();
    _syncOverlay(reposition: true);
    notifyListeners();
  }

  void toggle() => _playing ? pause() : play();

  /// Moves the playhead; playback continues from there when playing.
  void seek(int timelineMs) {
    if (_disposed) return;
    final before = clipIndex;
    _position.value = timelineMs.clamp(0, durationMs);
    _syncVideo();
    _syncAudio(reposition: true);
    _syncClipSound(reposition: true);
    final overlayBefore = overlay;
    _syncOverlay(reposition: true);
    if (clipIndex != before || overlay != overlayBefore) notifyListeners();
  }

  /// Call after every edit. Keeps the playhead inside the timeline and
  /// reloads the picture if the frame under the playhead changed.
  void updateProject(Project project) {
    if (_disposed || identical(project, _project)) return;
    final before = _videoKey();
    _project = project;
    _index();
    _makeBackIfUseful();
    if (positionMs > durationMs) _position.value = durationMs;
    if (_playing && durationMs <= 0) _playing = false;
    // Held pictures follow edits of their clip (fit, zoom, colour).
    for (final d in _decks) {
      final shown = d.shownClip;
      if (shown == null) continue;
      for (final c in project.clips) {
        if (c.id == shown.id && c.path == shown.path) d.shownClip = c;
      }
    }
    if (_videoKey() != before) {
      _syncVideo();
    } else {
      _applyVolumes(exact: true);
      _syncBack();
    }
    _syncAudio();
    _syncClipSound();
    _syncOverlay();
    notifyListeners();
  }

  /// Advances the clock by [deltaMs]; call once per frame while playing.
  void tick(int deltaMs) {
    if (_disposed || !_playing || deltaMs <= 0) return;
    final i = clipIndex;
    if (i < 0) {
      _finish();
      return;
    }
    final clip = _project.clips[i];
    if (_isPlayableVideo(clip)) {
      final d = _front;
      _stallMs += deltaMs;
      if (_stallMs > stallLimitMs) {
        _unplayable.add(clip.path);
        _stallMs = 0;
        _syncVideo();
        notifyListeners();
      } else if (d.settled && d.reported && d.moving == 0) {
        // The player reports its position once per video frame. Between two
        // reports, carry on from the last one to leave the clip on time
        // instead of one report (or, at the end of a file, one "completed"
        // event) late.
        d.sinceReportMs += deltaMs;
        if (d.sinceReportMs <= extrapolateLimitMs) {
          final src = d.lastSrcMs + (d.sinceReportMs * clip.speed).round();
          if (_leaves(i, clip, src)) _advanceFrom(i);
        }
      }
    } else {
      final end = _handoverMs(i);
      final t = positionMs + deltaMs;
      if (t >= end) {
        _advanceFrom(i, carryMs: t - end);
      } else {
        _position.value = t;
      }
    }
    if (_playing) {
      _moved();
      _syncAudio();
    }
  }

  // Video ------------------------------------------------------------------

  _Deck _addDeck(TimelinePlayer player) {
    final d = _Deck(_decks.length, player);
    d.positionSub = player.positionStream.listen((ms) => _onPosition(d, ms));
    d.completedSub = player.completedStream.listen((_) => _onCompleted(d));
    _decks.add(d);
    return d;
  }

  /// Makes the second player as soon as the project has a cut it can help
  /// with, while nothing is in a hurry: setting a player up takes long
  /// enough to hold up whatever else starts at that moment (measured: the
  /// music came in most of a second late when this was left until the first
  /// cut drew near during playback).
  void _makeBackIfUseful() {
    if (_decks.length > 1 || _project.clips.length < 2) return;
    if (_project.clips.any((c) => c.type == ClipType.video)) _ensureBack();
  }

  /// The back deck, made now if it was not there yet. Null when there is
  /// only one player.
  _Deck? _ensureBack() {
    if (_decks.length > 1) return _back;
    final create = _createVideoPlayer;
    if (create == null || _disposed) return null;
    _addDeck(create());
    // The preview has a new surface to put in its tree.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
    return _back;
  }

  void _setLoaded(_Deck d, String? path, [Clip? clip]) {
    if (clip != null) d.shownClip = clip;
    if (d.loadedPath == path) return;
    d.loadedPath = path;
    if (_disposed) return;
    if (path != null && identical(d, _front) && currentClip?.path == path) {
      _held = true;
    }
    notifyListeners();
  }

  /// Everything that decides which frames the players show; when it does
  /// not change in an edit, the players are left alone.
  Object _videoKey() {
    final i = clipIndex;
    if (i < 0) return const (null, 0);
    final clip = _project.clips[i];
    final front = _isPlayableVideo(clip)
        ? (clip.path, _sourceMs(i), clip.speed)
        : null;
    Object? outgoing;
    if (i > 0 && _activeOverlapMs(i) > 0) {
      final prev = _project.clips[i - 1];
      if (_isPlayableVideo(prev)) {
        outgoing = (prev.path, _sourceMs(i - 1), prev.speed);
      }
    }
    return (front, outgoing);
  }

  /// Level of a clip's own sound: its volume, times the video sound's
  /// level ([Project.videoSound]: volume, mute, solo).
  double _clipVolume(Clip c) =>
      c.muted ? 0 : c.volume * _project.trackGain(_project.videoSound);

  /// The clip at [i]'s own fade and the fade of the whole video at the
  /// playhead (1 without fades), as the export applies them to the sound.
  double _fadeAt(int i) {
    var g = _project.fadeGainAt(positionMs);
    if (i >= 0 && i < _project.clips.length && i < _starts.length) {
      final c = _project.clips[i];
      if (c.fadeInMs > 0 || c.fadeOutMs > 0) {
        g *= c.fadeGainAt((positionMs - _starts[i]).clamp(0, c.durationMs));
      }
    }
    return g;
  }

  /// Level of a video player playing [c]: silent while [c]'s processed
  /// sound plays on a sound player instead (see [processedSound]).
  double _deckVolume(Clip c) => _soundPlaysFor(c) ? 0 : _clipVolume(c);

  /// Runs a player command after the ones already waiting.
  void _run(_Deck d, Future<void> Function() command, {bool moves = false}) {
    if (moves) d.moving++;
    d.queue = d.queue.then((_) async {
      try {
        if (!_disposed) await command();
      } catch (_) {
        // A failing player must not break the queue; a clip that never
        // plays is caught by the stall check in [tick].
      } finally {
        if (moves) d.moving--;
      }
    });
  }

  /// Puts [clip] on deck [d] at source position [src], playing or paused.
  /// Newer calls replace ones still waiting. With [preload] the deck is
  /// being made ready ahead of time; a later call for the same place then
  /// only has to press play.
  void _cue(
    _Deck d,
    Clip clip,
    int src, {
    required bool play,
    required double volume,
    bool preload = false,
  }) {
    final gen = ++d.gen;
    final path = clip.path;
    final rate = clip.speed;
    final target = (path, src);
    final handoff = play && d.preloadDone && d.preloaded == target;
    d.preloaded = preload ? target : null;
    d.preloadDone = false;
    d.expectedSrcMs = src;
    d.settled = false;
    d.reported = false;
    d.sinceReportMs = 0;
    final setVolume = d.volume != volume;
    final setRate = d.rate != rate;
    final track = previewAudioTrack(clip);
    final filter = _filterFor(clip);
    final setTrack = d.audioTrack != track;
    final setFilter = d.audioFilter != filter;
    d.volume = volume;
    d.rate = rate;
    d.audioTrack = track;
    d.audioFilter = filter;
    if (d.loadedPath == path) d.shownClip = clip;
    _run(d, moves: true, () async {
      // Level, speed and sound are remembered as set, so they are never
      // skipped. Track and filters go before the file is opened, so that
      // it starts with them.
      if (setVolume) await d.player.setVolume(volume);
      if (setRate) await d.player.setRate(rate);
      if (setTrack) await d.player.setAudioTrack(track);
      if (setFilter) await d.player.setAudioFilter(filter);
      if (gen != d.gen) return;
      if (handoff) {
        await d.player.play();
      } else if (d.loadedPath == path) {
        await d.player.seek(src);
        await (play ? d.player.play() : d.player.pause());
      } else {
        _setLoaded(d, null);
        await d.player.open(path, positionMs: src, play: play);
        _setLoaded(d, path, clip);
      }
      d.playing = play;
      if (preload && gen == d.gen) d.preloadDone = true;
    });
  }

  /// Stops a deck that has nothing to show.
  void _park(_Deck d) {
    final gen = ++d.gen;
    d.preloaded = null;
    d.preloadDone = false;
    d.settled = false;
    d.reported = false;
    _run(d, moves: true, () async {
      if (gen != d.gen || !d.playing) return;
      d.playing = false;
      await d.player.pause();
    });
  }

  void _setVolume(_Deck d, double volume, {required bool exact}) {
    final old = d.volume;
    if (old == volume) return;
    // During a crossfade small steps are skipped, the ends never are.
    final end = volume == 0 || !_inTransition;
    if (!exact && !end && old != null && (volume - old).abs() < 0.03) return;
    d.volume = volume;
    _run(d, () => d.player.setVolume(volume));
  }

  /// Puts the sound settings of [clip] (stream, side, voice focus; see
  /// media/clip_audio.dart) on deck [d] when they differ from what it has.
  void _setSound(_Deck d, Clip clip) {
    final track = previewAudioTrack(clip);
    final filter = _filterFor(clip);
    if (d.audioTrack != track) {
      d.audioTrack = track;
      _run(d, () => d.player.setAudioTrack(track));
    }
    if (d.audioFilter != filter) {
      d.audioFilter = filter;
      _run(d, () => d.player.setAudioFilter(filter));
    }
  }

  bool get _inTransition {
    final i = clipIndex;
    return i > 0 && _activeOverlapMs(i) > 0;
  }

  /// Levels of the clip sound: the clip's own, crossfaded over a transition.
  void _applyVolumes({bool exact = false}) {
    final i = clipIndex;
    if (i < 0) return;
    final clip = _project.clips[i];
    final p = transitionProgress;
    if (_isPlayableVideo(clip)) {
      _setVolume(_front, _deckVolume(clip) * p * _fadeAt(i), exact: exact);
      // Same file, settings changed: an edit, or the next piece of one
      // file playing through.
      if (_front.loadedPath == clip.path) _setSound(_front, clip);
    }
    final back = _back;
    if (_backIsOutgoing && back != null && i > 0) {
      final prev = _project.clips[i - 1];
      _setVolume(back, _deckVolume(prev) * (1 - p) * _fadeAt(i - 1),
          exact: exact);
      if (back.loadedPath == prev.path) _setSound(back, prev);
    }
  }

  void _flip() {
    _frontIndex = 1 - _frontIndex;
  }

  /// Brings the players in line with the playhead after a jump: right
  /// files, right frames, playing or paused.
  void _syncVideo() {
    final i = clipIndex;
    final clip = i < 0 ? null : _project.clips[i];
    _stallMs = 0;
    // Inside a transition the previous clip goes to the back deck. A deck
    // that already holds a file keeps it, which saves loading it again.
    final prev = i > 0 && _activeOverlapMs(i) > 0 ? _project.clips[i - 1] : null;
    final frontHasPrev = prev != null &&
        _isPlayableVideo(prev) &&
        _front.loadedPath == prev.path &&
        _back?.loadedPath != prev.path;
    if (!_isPlayableVideo(clip)) {
      _held = false;
      if (frontHasPrev && _ensureBack() != null) _flip();
      _park(_front);
    } else {
      final back = _back;
      if (_front.loadedPath != clip!.path) {
        if (back != null && back.loadedPath == clip.path) {
          _flip();
        } else if (frontHasPrev && _ensureBack() != null) {
          _flip();
          _held = false;
        }
      }
      if (_front.loadedPath == clip.path) _held = true;
      _cue(_front, clip, _sourceMs(i),
          play: _playing,
          volume: _deckVolume(clip) * transitionProgress * _fadeAt(i));
    }
    _syncBack(force: true);
  }

  bool _seamlessAfter(int i) {
    if (i + 1 >= _project.clips.length) return false;
    final a = _project.clips[i], b = _project.clips[i + 1];
    return _project.transitionOverlapMs(i + 1) == 0 &&
        _isPlayableVideo(a) &&
        b.type == ClipType.video &&
        a.path == b.path &&
        a.speed == b.speed &&
        a.audioTrackInUse == b.audioTrackInUse &&
        (b.inMs - a.outMs).abs() <= seamToleranceMs;
  }

  /// Gives the back deck its job for the place the playhead is at:
  ///
  /// * inside a transition, the previous clip (it plays on to its end);
  /// * while playing towards a cut to another video, that video, loaded
  ///   and paused at its in point;
  /// * otherwise nothing.
  ///
  /// Unless [force]d (after a jump), the deck is only touched when the job
  /// changes.
  void _syncBack({bool force = false}) {
    final i = clipIndex;
    final clips = _project.clips;
    Clip? outgoing, upcoming;
    if (i > 0 && _activeOverlapMs(i) > 0 && _isPlayableVideo(clips[i - 1])) {
      outgoing = clips[i - 1];
    } else if (_playing &&
        i >= 0 &&
        i + 1 < clips.length &&
        _isPlayableVideo(clips[i + 1]) &&
        !_seamlessAfter(i) &&
        _handoverMs(i) - positionMs <= preloadLeadMs) {
      upcoming = clips[i + 1];
    }
    final Object? key = outgoing != null
        ? ('out', outgoing.id, outgoing.path, outgoing.inMs, outgoing.speed)
        : upcoming != null
            ? ('pre', upcoming.path, upcoming.inMs, upcoming.speed)
            : null;
    if (!force && key == _backKey) return;
    _backKey = key;
    _backIsOutgoing = false;
    if (outgoing != null) {
      final back = _ensureBack();
      if (back == null) return;
      _backIsOutgoing = true;
      _cue(back, outgoing, _sourceMs(i - 1),
          play: _playing,
          volume: _deckVolume(outgoing) *
              (1 - transitionProgress) *
              _fadeAt(i - 1));
    } else if (upcoming != null) {
      final back = _ensureBack();
      if (back == null) return;
      if (back.preloaded == (upcoming.path, upcoming.inMs)) return;
      // Silent if it will fade in.
      final fadesIn = _project.transitionOverlapMs(i + 1) > 0;
      _cue(back, upcoming, upcoming.inMs,
          play: false,
          volume: fadesIn ? 0 : _deckVolume(upcoming),
          preload: true);
    } else {
      final back = _back;
      if (back != null) _park(back);
    }
  }

  /// Follows the playhead after it moved on by itself.
  void _moved() {
    _syncBack();
    _applyVolumes();
    _syncClipSound();
    _syncOverlay();
  }

  /// True when source position [srcMs] of the playing clip [i] is at or
  /// past the point where the timeline moves on to the next clip.
  bool _leaves(int i, Clip clip, int srcMs) {
    if (srcMs >= clip.outMs) return true;
    final local = ((srcMs - clip.inMs) / clip.speed).round();
    return local >= _handoverMs(i) - _starts[i];
  }

  void _onPosition(_Deck d, int srcMs) {
    if (!_playing || d.moving > 0) return;
    final i = clipIndex;
    if (i < 0) return;
    if (!identical(d, _front)) {
      _onBackPosition(d, i, srcMs);
      return;
    }
    final clip = _project.clips[i];
    if (!_isPlayableVideo(clip)) return;
    if (!d.settled) {
      if ((srcMs - d.expectedSrcMs).abs() > settleToleranceMs) return;
      d.settled = true;
    }
    _stallMs = 0;
    d.reported = true;
    d.lastSrcMs = srcMs;
    d.sinceReportMs = 0;
    _videoReportUs = _clock.elapsedMicroseconds;
    if (_leaves(i, clip, srcMs)) {
      _advanceFrom(i);
      return;
    }
    final limit = math.max(0, _handoverMs(i) - _starts[i] - 1);
    final int local =
        ((srcMs - clip.inMs) / clip.speed).round().clamp(0, limit);
    _position.value = _starts[i] + local;
    _moved();
  }

  /// The outgoing clip of a transition stops at its own end.
  void _onBackPosition(_Deck d, int i, int srcMs) {
    if (!_backIsOutgoing || i <= 0 || !d.playing) return;
    if (!d.settled) {
      if ((srcMs - d.expectedSrcMs).abs() > settleToleranceMs) return;
      d.settled = true;
    }
    if (srcMs < _project.clips[i - 1].outMs) return;
    d.playing = false;
    _run(d, d.player.pause);
  }

  void _onCompleted(_Deck d) {
    if (!_playing || d.moving > 0 || !identical(d, _front)) return;
    final i = clipIndex;
    if (i < 0 || !_isPlayableVideo(_project.clips[i])) return;
    _advanceFrom(i);
  }

  /// Leaves clip [index] at its handover point and enters the next one, or
  /// stops at the end of the timeline.
  void _advanceFrom(int index, {int carryMs = 0}) {
    final next = index + 1;
    if (next >= _project.clips.length) {
      _finish();
      return;
    }
    final prev = _project.clips[index];
    final clip = _project.clips[next];
    final start = _starts[next];
    final overlap = _project.transitionOverlapMs(next);
    final prevOnFront = _isPlayableVideo(prev);
    _stallMs = 0;
    if (_isPlayableVideo(clip)) {
      _position.value = start;
      final seamless = _seamlessAfter(index) &&
          _front.loadedPath == clip.path &&
          _front.playing;
      if (seamless) {
        // Same file, same place: let the player run on.
        final d = _front;
        d.expectedSrcMs = clip.inMs;
        d.shownClip = clip;
        _moved();
      } else {
        final back = _back;
        final ready = back != null &&
            back.preloadDone &&
            back.preloaded == (clip.path, clip.inMs);
        // With a transition the previous clip has to play on, which it
        // can only do on its own deck.
        final keepPrev = overlap > 0 && prevOnFront;
        if (ready || (keepPrev && _ensureBack() != null)) {
          _flip();
          if (!ready) _held = _front.loadedPath == clip.path;
          _cue(_front, clip, clip.inMs,
              play: true, volume: _deckVolume(clip) * (overlap > 0 ? 0 : 1));
          if (ready) _held = true;
          if (keepPrev) {
            // The old front deck is the outgoing clip now; it is already
            // playing in the right place.
            _backKey =
                ('out', prev.id, prev.path, prev.inMs, prev.speed);
            _backIsOutgoing = true;
            _applyVolumes(exact: true);
          } else {
            _syncBack(force: true);
          }
        } else {
          _syncVideo();
        }
      }
    } else {
      final int local =
          carryMs.clamp(0, math.max(0, _handoverMs(next) - start - 1));
      _position.value = start + local;
      if (overlap > 0 && prevOnFront && _ensureBack() != null) {
        // The video plays on under the incoming photo.
        _flip();
        _held = false;
        _park(_front);
        _backKey = ('out', prev.id, prev.path, prev.inMs, prev.speed);
        _backIsOutgoing = true;
        _applyVolumes(exact: true);
      } else {
        _syncVideo();
      }
    }
    _syncClipSound();
    notifyListeners();
  }

  void _finish() {
    _playing = false;
    _position.value = durationMs;
    _syncVideo();
    _syncAudio();
    _syncClipSound();
    _syncOverlay(reposition: true);
    notifyListeners();
  }

  // Picture ----------------------------------------------------------------

  /// What the preview should draw for the playhead position.
  PreviewScene get scene {
    final i = clipIndex;
    if (i < 0) return const PreviewScene();
    final clip = _project.clips[i];
    final PreviewLayer current;
    if (isMissing(clip.path)) {
      current = PreviewLayer(PreviewLayerKind.missing, clip);
    } else if (clip.type == ClipType.photo) {
      current = PreviewLayer(PreviewLayerKind.photo, clip);
    } else if (_front.loadedPath == clip.path) {
      current = PreviewLayer(PreviewLayerKind.video, clip, _frontIndex);
    } else if (_held && _front.shownClip != null) {
      // Still loading: the player keeps the last frame of what it showed
      // before, which stays in its own shape.
      current =
          PreviewLayer(PreviewLayerKind.video, _front.shownClip!, _frontIndex);
    } else {
      current = PreviewLayer(PreviewLayerKind.blank, clip);
    }
    if (i == 0 || _activeOverlapMs(i) <= 0) {
      return PreviewScene(current: current);
    }
    final prev = _project.clips[i - 1];
    PreviewLayer? outgoing;
    if (isMissing(prev.path)) {
      outgoing = null;
    } else if (prev.type == ClipType.photo) {
      outgoing = PreviewLayer(PreviewLayerKind.photo, prev);
    } else {
      final back = _back;
      if (_backIsOutgoing && back != null && back.loadedPath == prev.path) {
        outgoing = PreviewLayer(PreviewLayerKind.video, prev, back.index);
      }
    }
    // A side that cannot be shown turns the transition into a cut.
    if (outgoing == null) return PreviewScene(current: current);
    if (current.kind == PreviewLayerKind.blank) {
      return PreviewScene(current: outgoing);
    }
    return PreviewScene(
      current: current,
      outgoing: outgoing,
      transition: clip.transition,
      progress: transitionProgress,
    );
  }

  // Audio ------------------------------------------------------------------

  /// Level of [a] at timeline time [timeMs], fades included, as a linear
  /// amplitude factor (the export's scale).
  ///
  /// [audibleEndMs] is where the sound stops being heard on the timeline
  /// ([Project.audibleEndMs]: its own end, or the end of the video when it
  /// runs past that); the fade-out finishes there, as in the export.
  static double audioGain(AudioClip a, int timeMs, {int? audibleEndMs}) {
    final rel = timeMs - a.startMs;
    var duration = a.durationMs;
    if (audibleEndMs != null && audibleEndMs - a.startMs < duration) {
      duration = audibleEndMs - a.startMs;
    }
    if (rel < 0 || rel >= duration) return 0;
    var gain = 1.0;
    if (a.fadeInMs > 0 && rel < a.fadeInMs) gain = rel / a.fadeInMs;
    if (a.fadeOutMs > 0 && rel > duration - a.fadeOutMs) {
      gain = math.min(gain, (duration - rel) / a.fadeOutMs);
    }
    return a.volume * gain.clamp(0.0, 1.0);
  }

  /// The file a sound clip plays from: its ready processed sound file
  /// (clean-up, voice focus done), else its own file.
  String _audioPath(AudioClip a) {
    if (!_hearOriginal.value && clipNeedsProcessedSound(a.soundClip)) {
      final ready = _processedSound?.call(a.soundClip);
      if (ready != null) return ready;
    }
    return a.path;
  }

  /// The clip of [clips] (timeline order, no overlaps) playing at [t], and
  /// the next one after [t].
  static (AudioClip?, AudioClip?) _around(List<AudioClip> clips, int t) {
    var lo = 0, hi = clips.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (clips[mid].startMs <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    // clips[lo - 1] is the last that starts at or before t.
    final cur = lo > 0 && t < clips[lo - 1].endMs ? clips[lo - 1] : null;
    final next = lo < clips.length ? clips[lo] : null;
    return (cur, next);
  }

  /// Sound clips run on the timeline clock whatever the speed of the video
  /// clips: at their own speed from their own place. Ducking ("lower under
  /// speech") is not imitated: the export ducks with a compressor that
  /// follows the actual loudness of the speech, which a fixed dip would
  /// misstate.
  void _syncAudio({bool reposition = false}) {
    if (_disposed) return;
    final t = positionMs;
    final total = durationMs;
    // What should play now, and what should wait loaded, per track.
    final active = <AudioClip>[];
    final soon = <AudioClip>[];
    for (final track in _project.soundTracks) {
      if (_project.trackGain(track) <= 0) continue;
      final clips = _trackClips[track.id];
      if (clips == null || clips.isEmpty) continue;
      final (cur, next) = _around(clips, t);
      if (_playing && cur != null && t < total && !isMissing(cur.path)) {
        // The repeat before is still fading out (a looped sound).
        final i = clips.indexOf(cur);
        final before = i > 0 ? clips[i - 1] : null;
        if (before != null &&
            t < before.endMs &&
            loopBaseId(before.id) == loopBaseId(cur.id)) {
          active.add(before);
        }
        active.add(cur);
      }
      if (_playing &&
          next != null &&
          next.startMs - t <= audioPreloadLeadMs &&
          next.startMs < total &&
          !isMissing(next.path)) {
        soon.add(next);
      }
    }

    // Players: the one already on a clip keeps it; then one cued for it;
    // then one holding its file; then any free one; else a new one.
    final free = [..._audio];
    final pairs = <(_AudioSlot, AudioClip, bool)>[];
    final open = <(AudioClip, bool)>[
      for (final a in active) (a, true),
      for (final a in soon) (a, false),
    ];
    open.removeWhere((w) {
      final s = free.where((s) => s.audioId == w.$1.id).firstOrNull;
      if (s == null) return false;
      free.remove(s);
      pairs.add((s, w.$1, w.$2));
      return true;
    });
    for (final (a, play) in open) {
      final path = _audioPath(a);
      var s = free.where((s) => s.loadedPath == path).firstOrNull;
      s ??= free.isNotEmpty ? free.first : null;
      if (s != null) {
        free.remove(s);
      } else {
        final made = s = _AudioSlot(_createAudioPlayer());
        made.sub = made.player.positionStream
            .listen((ms) => _onAudioPosition(made, ms));
        _audio.add(s);
      }
      pairs.add((s, a, play));
    }
    final ids = {
      for (final list in _trackClips.values)
        for (final a in list) a.id,
    };
    for (final s in free) {
      if (s.playing) {
        s.playing = false;
        s.run(s.player.pause);
      }
      s.cued = null;
      // A player whose sound is gone from the project is let go.
      if (s.audioId != null && !ids.contains(s.audioId)) {
        _audio.remove(s);
        s.sub?.cancel();
        s.run(s.player.dispose);
      }
    }
    for (final (s, a, play) in pairs) {
      s.audioId = a.id;
      if (play) {
        _playAudio(s, a, t, reposition: reposition);
      } else {
        _cueAudio(s, a);
      }
    }
  }

  /// Track, filters and speed of [a] on [s], set only when they differ
  /// (a new player plays the first stream at normal speed, unfiltered).
  void _setAudioSound(_AudioSlot s, AudioClip a, String path) {
    final processed = path != a.path;
    final track = processed ? 0 : previewAudioTrack(a.soundClip);
    final filter =
        processed || _hearOriginal.value ? '' : previewAudioFilter(a.soundClip);
    final rate = a.speed;
    if (s.rate != rate) {
      s.rate = rate;
      s.run(() => s.player.setRate(rate));
    }
    if (s.audioTrack != track) {
      s.audioTrack = track;
      s.run(() => s.player.setAudioTrack(track));
    }
    if (s.audioFilter != filter) {
      s.audioFilter = filter;
      s.run(() => s.player.setAudioFilter(filter));
    }
  }

  /// Loaded and waiting at the first sample of [a].
  void _cueAudio(_AudioSlot s, AudioClip a) {
    if (s.playing) {
      s.playing = false;
      s.run(s.player.pause);
    }
    final path = _audioPath(a);
    final placement = (path, a.startMs, a.inMs);
    if (s.cued == placement) return;
    s.cued = placement;
    _setAudioSound(s, a, path);
    s.run(() async {
      if (s.loadedPath == path) {
        await s.player.seek(a.inMs);
        await s.player.pause();
      } else {
        s.loadedPath = null;
        await s.player.open(path, positionMs: a.inMs, play: false);
        s.loadedPath = path;
      }
    });
  }

  void _playAudio(_AudioSlot s, AudioClip a, int t, {required bool reposition}) {
    final path = _audioPath(a);
    final placement = (path, a.startMs, a.inMs);
    int srcAt(int time) => a.inMs + ((time - a.startMs) * a.speed).round();
    final src = srcAt(t);
    final volume = audioGain(a, t, audibleEndMs: _project.audibleEndMs(a)) *
        _project.trackGainOf(a.trackId) *
        _project.fadeGainAt(t);
    if (!s.playing || reposition || s.placement != placement) {
      // Waiting at the start and the playhead just got there: play.
      final fromCue = s.cued == placement &&
          !reposition &&
          src - a.inMs <= audioLateToleranceMs;
      s.cued = null;
      s.playing = true;
      s.placement = placement;
      s.volume = volume;
      // A sound that follows a video clip is kept on the picture's clock.
      s.linkClipId = a.linked ? a.sourceClipId : null;
      s.linkOffsetMs = a.syncOffsetMs ?? 0;
      s.drift = null;
      s.reports = 0;
      s.startFixed = false;
      _setAudioSound(s, a, path);
      s.run(moves: true, () async {
        await s.player.setVolume(volume);
        if (fromCue && s.loadedPath == path) {
          await s.player.play();
        } else if (s.loadedPath == path) {
          await s.player.seek(src);
          await s.player.play();
          return;
        } else {
          s.loadedPath = null;
          await s.player.open(path, positionMs: src, play: true);
          s.loadedPath = path;
        }
        // Getting it going takes a moment while the picture plays on:
        // catch up, or the sound stays that much behind.
        if (_disposed || !_playing || !s.playing) return;
        if (s.placement != placement) return;
        final now = srcAt(positionMs);
        if (now - src > audioLateToleranceMs && now < a.outMs) {
          await s.player.seek(now);
        }
      });
    } else if ((volume - (s.volume ?? -1)).abs() > 0.01 ||
        (volume == 0) != ((s.volume ?? -1) == 0)) {
      s.volume = volume;
      s.run(() => s.player.setVolume(volume));
    }
  }

  // Processed clip sound ----------------------------------------------------
  //
  // "Instant sound processing" (media/processed_sound.dart): once a clip's
  // processed sound file is ready, the clip's video player plays silent and
  // a sound player plays that file in step with the picture: same source
  // position (the file is the whole source at source timing), the clip's
  // speed as playback rate (pitch kept), its volume and mute, and the
  // transition crossfade (an incoming and an outgoing sound player). Until
  // the file is ready - and while "Hear original" is on - the video player
  // plays the clip's own sound with the light live filters, as before.

  /// The ready processed sound file of a clip, or null (set by the editor).
  /// Call [soundFilesChanged] when what it answers changes.
  String? Function(Clip clip)? get processedSound => _processedSound;
  set processedSound(String? Function(Clip clip)? f) {
    _processedSound = f;
    soundFilesChanged();
  }

  String? Function(Clip clip)? _processedSound;

  /// Re-reads [processedSound] (a file became ready or went away).
  void soundFilesChanged() {
    if (_disposed) return;
    _syncClipSound();
    _applyVolumes(exact: true);
    _syncAudio();
  }

  /// A sound player that runs this far AHEAD of the picture is put back in
  /// step (measured on the smoothed difference). Sound that comes early is
  /// noticed sooner than sound that comes late (about 45 ms against
  /// 125 ms, ITU-R BT.1359), and every correction is a seek that can be
  /// heard, so a late sound gets more room ([soundLagLimitMs]).
  static const int soundDriftLimitMs = 45;

  /// The same for a sound player that runs BEHIND the picture.
  static const int soundLagLimitMs = 80;

  /// At most one correction per this long.
  static const int soundFixIntervalMs = 2000;

  /// Position reports averaged before a correction.
  static const int soundFixReports = 5;

  /// The first correction after the sound player (re)started uses this
  /// tighter limit both ways: a separate player starts some tens of ms
  /// after the picture (measured 60..80 ms with mpv on Linux), and a seek
  /// right at the start is the least noticeable.
  static const int soundStartLimitMs = 30;

  final Stopwatch _clock = Stopwatch()..start();

  /// When the front video player last reported its position.
  int _videoReportUs = 0;

  final List<_SoundSlot> _sounds = [];

  /// The sound players made so far (tests, measurements).
  List<TimelinePlayer> get clipSoundPlayers => [for (final s in _sounds) s.player];

  /// The processed file a sound player plays right now for the clip under
  /// the playhead; null when its own sound plays (not ready, "Hear
  /// original", nothing processed).
  String? get playingProcessedSound {
    final c = currentClip;
    if (c == null || !_soundPlaysFor(c)) return null;
    return _processedPath(c);
  }

  /// Sound minus picture, in ms (positive: the sound is ahead), smoothed,
  /// as last measured while a processed sound played; null before.
  double? get soundOffsetMs => _soundOffsetMs;
  double? _soundOffsetMs;

  /// How often the sound was put back in step.
  int get soundCorrections => _soundCorrections;
  int _soundCorrections = 0;

  String? _processedPath(Clip c) {
    if (_hearOriginal.value || c.type != ClipType.video) return null;
    return _processedSound?.call(c);
  }

  /// True when a sound player has [c]'s processed file loaded, so that the
  /// video player can go quiet (never earlier: no gap while it loads).
  bool _soundPlaysFor(Clip c) {
    final path = _processedPath(c);
    if (path == null) return false;
    return _sounds.any((s) => s.loadedPath == path);
  }

  _SoundSlot _newSlot() {
    final s = _SoundSlot(_createAudioPlayer());
    s.sub = s.player.positionStream.listen((ms) => _onSoundPosition(s, ms));
    _sounds.add(s);
    return s;
  }

  /// Gives the sound players what the playhead needs: the processed sound
  /// of the clip under it and, during a transition, of the clip before.
  void _syncClipSound({bool reposition = false}) {
    if (_disposed) return;
    final wants = <_SoundWant>[];
    final i = clipIndex;
    if (i >= 0 && positionMs < durationMs) {
      final c = _project.clips[i];
      final p = transitionProgress;
      final path = _processedPath(c);
      if (path != null && _isPlayableVideo(c)) {
        wants.add(_SoundWant(c, path, _sourceMs(i), _clipVolume(c) * p * _fadeAt(i)));
      }
      if (i > 0 && _activeOverlapMs(i) > 0) {
        final prev = _project.clips[i - 1];
        final pp = _processedPath(prev);
        final src = _sourceMs(i - 1);
        if (pp != null && _isPlayableVideo(prev) && src < prev.outMs) {
          wants.add(_SoundWant(
              prev, pp, src, _clipVolume(prev) * (1 - p) * _fadeAt(i - 1)));
        }
      }
    }
    if (wants.isEmpty && _sounds.every((s) => s.clipId == null && !s.playing)) {
      return;
    }
    final free = [..._sounds];
    final pairs = <(_SoundSlot, _SoundWant)>[];
    final open = <_SoundWant>[];
    // The player already playing this clip, then one holding the file.
    for (final w in wants) {
      final s = free.where((s) => s.clipId == w.clip.id && s.path == w.path).firstOrNull;
      if (s == null) {
        open.add(w);
      } else {
        free.remove(s);
        pairs.add((s, w));
      }
    }
    for (final w in open) {
      var s = free.where((s) => s.path == w.path).firstOrNull;
      s ??= free.isNotEmpty ? free.first : null;
      if (s != null) {
        free.remove(s);
      } else {
        s = _newSlot();
      }
      pairs.add((s, w));
    }
    for (final s in free) {
      _driveSound(s, null, reposition: reposition);
    }
    for (final (s, w) in pairs) {
      _driveSound(s, w, reposition: reposition);
    }
  }

  void _driveSound(_SoundSlot s, _SoundWant? w, {required bool reposition}) {
    if (w == null) {
      s.clipId = null;
      if (s.playing) {
        s.playing = false;
        s.run(s.player.pause);
      }
      return;
    }
    final prevClip = s.clipId;
    final prevOut = s.clipOutMs;
    s.clipId = w.clip.id;
    s.clipOutMs = w.clip.outMs;
    final rate = w.clip.speed;
    if (s.rate != rate) {
      s.rate = rate;
      s.run(() => s.player.setRate(rate));
    }
    final volume = w.volume;
    final old = s.volume;
    if (old == null ||
        (volume - old).abs() >= 0.03 ||
        (volume == 0) != (old == 0) ||
        (reposition && volume != old)) {
      s.volume = volume;
      s.run(() => s.player.setVolume(volume));
    }
    final path = w.path;
    if (!_playing) {
      if (s.playing) {
        s.playing = false;
        s.run(s.player.pause);
      }
      // Loaded and waiting at the playhead, so that play starts at once.
      if (s.path != path) {
        _soundOpen(s, w, play: false);
      } else if (reposition || prevClip != w.clip.id) {
        s.expectedSrcMs = w.srcMs;
        s.settled = false;
        s.run(() => s.player.seek(w.srcMs), moves: true);
      }
      return;
    }
    if (s.playing && !reposition && s.path == path) {
      if (prevClip == w.clip.id) return;
      // The next piece of the same file, where the last one ended: the
      // sound runs on, like the picture does.
      if (prevOut != null &&
          (w.clip.inMs - prevOut).abs() <= seamToleranceMs &&
          (w.srcMs - w.clip.inMs).abs() <= seamToleranceMs * 2) {
        return;
      }
    }
    s.playing = true;
    s.startFixed = false;
    if (s.path == path && s.loadedPath == path) {
      s.expectedSrcMs = w.srcMs;
      s.settled = false;
      s.drift = null;
      s.run(moves: true, () async {
        await s.player.seek(w.srcMs);
        await s.player.play();
      });
    } else {
      _soundOpen(s, w, play: true);
    }
  }

  void _soundOpen(_SoundSlot s, _SoundWant w, {required bool play}) {
    final path = w.path;
    final clipId = w.clip.id;
    s.path = path;
    s.loadedPath = null;
    s.expectedSrcMs = w.srcMs;
    s.settled = false;
    s.drift = null;
    _applyVolumes(exact: true);
    s.run(moves: true, () async {
      await s.player.open(path, positionMs: w.srcMs, play: play);
      if (_disposed || s.path != path) return;
      s.loadedPath = path;
      // The video player goes quiet now that this one has the sound.
      _applyVolumes(exact: true);
      if (!play || !_playing || !s.playing || s.clipId != clipId) return;
      // Loading took a moment while the picture played on: catch up.
      final now = _soundTargetMs(s);
      if (now != null && (now - w.srcMs).abs() > audioLateToleranceMs) {
        s.expectedSrcMs = now;
        await s.player.seek(now);
      }
    });
  }

  /// Where the sound of the clip [s] plays for should be now, by the
  /// picture's clock (its last report carried on by the time since);
  /// null when that clip is not on screen.
  int? _soundTargetMs(_SoundSlot s) => _clipSourceNow(s.clipId);

  /// Where clip [clipId] is in its file now, by the picture's clock (its
  /// last report carried on by the time since); null when that clip is
  /// not on screen.
  int? _clipSourceNow(String? clipId) {
    final i = clipIndex;
    if (i < 0 || clipId == null) return null;
    final j = _project.clips[i].id == clipId
        ? i
        : (i > 0 && _project.clips[i - 1].id == clipId ? i - 1 : -1);
    if (j < 0) return null;
    final clip = _project.clips[j];
    var src = _sourceMs(j);
    if (_playing && j == i && _front.reported && _front.settled) {
      final sinceUs = _clock.elapsedMicroseconds - _videoReportUs;
      final since = math.min(extrapolateLimitMs, sinceUs ~/ 1000);
      src = math.min(clip.outMs, _front.lastSrcMs + (since * clip.speed).round());
    }
    return src;
  }

  /// Keeps a sound that follows a video clip (a voice recorded separately,
  /// a separated sound) in step with the picture, as [_onSoundPosition]
  /// does for processed clip sound: the same limits, at most one
  /// correction every [soundFixIntervalMs]. Music is left alone (it only
  /// has to be near the clock).
  void _onAudioPosition(_AudioSlot s, int ms) {
    if (_disposed || !_playing || !s.playing || s.moving > 0) return;
    final clipId = s.linkClipId;
    if (clipId == null) return;
    final d = _front;
    if (!d.settled || !d.reported || d.moving > 0) return;
    final clipNow = _clipSourceNow(clipId);
    if (clipNow == null) return;
    final target = clipNow + s.linkOffsetMs;
    final diff = (ms - target).toDouble();
    // A report from before a seek, or the picture is elsewhere.
    if (diff.abs() > settleToleranceMs) return;
    s.drift = s.drift == null ? diff : s.drift! * 0.7 + diff * 0.3;
    s.reports++;
    _voiceOffsetMs = s.drift;
    final drift = s.drift!;
    if (s.reports < soundFixReports) return;
    final starting = !s.startFixed;
    if (starting && s.reports >= soundFixReports * 2) s.startFixed = true;
    final ahead = starting ? soundStartLimitMs : soundDriftLimitMs;
    final behind = starting ? soundStartLimitMs : soundLagLimitMs;
    if (drift <= ahead && drift >= -behind) return;
    s.startFixed = true;
    final nowUs = _clock.elapsedMicroseconds;
    if (!starting && nowUs - s.lastFixUs < soundFixIntervalMs * 1000) return;
    s.lastFixUs = nowUs;
    _voiceCorrections++;
    s.drift = null;
    s.reports = 0;
    s.run(moves: true, () => s.player.seek(target));
  }

  /// Smoothed "linked sound minus picture" of the last report (ms; null
  /// before the first), and how often such a sound was put back in step.
  /// For tests and diagnostics.
  double? get voiceOffsetMs => _voiceOffsetMs;
  double? _voiceOffsetMs;
  int get voiceCorrections => _voiceCorrections;
  int _voiceCorrections = 0;

  void _onSoundPosition(_SoundSlot s, int ms) {
    if (_disposed || !_playing || !s.playing || s.moving > 0) return;
    if (!s.settled) {
      if ((ms - s.expectedSrcMs).abs() > settleToleranceMs) return;
      s.settled = true;
      s.drift = null;
      s.reports = 0;
      return;
    }
    // Only against a picture whose clock can be trusted.
    final d = _front;
    if (!d.settled || !d.reported || d.moving > 0) return;
    final target = _soundTargetMs(s);
    if (target == null) return;
    final diff = (ms - target).toDouble();
    s.drift = s.drift == null ? diff : s.drift! * 0.7 + diff * 0.3;
    s.reports++;
    _soundOffsetMs = s.drift;
    final drift = s.drift!;
    if (s.reports < soundFixReports) return;
    final starting = !s.startFixed;
    if (starting && s.reports >= soundFixReports * 2) s.startFixed = true;
    final ahead = starting ? soundStartLimitMs : soundDriftLimitMs;
    final behind = starting ? soundStartLimitMs : soundLagLimitMs;
    if (drift <= ahead && drift >= -behind) return;
    s.startFixed = true;
    final nowUs = _clock.elapsedMicroseconds;
    if (!starting && nowUs - s.lastFixUs < soundFixIntervalMs * 1000) return;
    s.lastFixUs = nowUs;
    _soundCorrections++;
    s.expectedSrcMs = target;
    s.settled = false;
    s.drift = null;
    s.run(moves: true, () => s.player.seek(target));
  }

  // Overlay track -----------------------------------------------------------

  /// An overlay player that is this far from where the clock says is put
  /// back (at most once per [soundFixIntervalMs]).
  static const int overlayDriftLimitMs = 150;

  /// The next overlay video is loaded (paused) this long before it starts.
  static const int overlayPreloadLeadMs = 1500;

  /// Most overlay players.
  static const int maxOverlayDecks = 2;

  final List<_OverlayDeck> _overlayDecks = [];

  /// The overlay players made so far (their pictures are drawn by the
  /// preview).
  List<TimelinePlayer> get overlayPlayers =>
      [for (final d in _overlayDecks) d.player];

  /// The overlay item under the playhead (before the end of the video).
  OverlayClip? get overlayItem {
    final t = positionMs;
    if (t >= durationMs) return null;
    return _project.overlayAt(t);
  }

  /// What the overlay track shows at the playhead, or null.
  OverlayView? get overlay {
    final o = overlayItem;
    if (o == null) return null;
    if (isMissing(o.path)) return OverlayView(PreviewLayerKind.missing, o);
    if (o.clip.type == ClipType.photo) {
      return OverlayView(PreviewLayerKind.photo, o);
    }
    for (var i = 0; i < _overlayDecks.length; i++) {
      final d = _overlayDecks[i];
      if (d.itemId == o.id && d.loadedPath == o.path) {
        return OverlayView(PreviewLayerKind.video, o, deck: i);
      }
    }
    return OverlayView(PreviewLayerKind.blank, o);
  }

  int _overlaySrc(OverlayClip o, int t) =>
      o.clip.sourceMsAt(t - o.startMs);

  double _overlayVolume(OverlayClip o, int t) {
    if (!o.audible) return 0;
    return audioGain(o.sound, t, audibleEndMs: _project.durationMs) *
        _project.trackGain(_project.videoSound) *
        _project.fadeGainAt(t);
  }

  _OverlayDeck? _newOverlayDeck() {
    final create = _createVideoPlayer;
    if (create == null || _disposed) return null;
    if (_overlayDecks.length >= maxOverlayDecks) return null;
    final d = _OverlayDeck(create());
    d.sub = d.player.positionStream.listen((ms) => _onOverlayPosition(d, ms));
    _overlayDecks.add(d);
    // The preview has a new surface to put in its tree.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
    return d;
  }

  /// Gives the overlay players what the playhead needs: the video of the
  /// overlay item under it (playing, or paused on the right frame), and
  /// while playing, the next one loaded and waiting at its first frame.
  void _syncOverlay({bool reposition = false}) {
    if (_disposed) return;
    final t = positionMs;
    final items = _project.overlays;
    if (items.isEmpty && _overlayDecks.every((d) => d.itemId == null)) return;
    final cur = overlayItem;
    OverlayClip? next;
    if (_playing) {
      for (final o in items) {
        if (o.startMs > t && o.startMs - t <= overlayPreloadLeadMs) {
          next = o;
          break;
        }
        if (o.startMs > t) break;
      }
    }
    bool playable(OverlayClip? o) =>
        o != null && o.clip.type == ClipType.video && !isMissing(o.path);
    final wants = <(OverlayClip, bool)>[
      if (playable(cur)) (cur!, true),
      if (playable(next) && next!.id != cur?.id) (next, false),
    ];
    final free = [..._overlayDecks];
    final pairs = <(_OverlayDeck, OverlayClip, bool)>[];
    final open = <(OverlayClip, bool)>[];
    for (final w in wants) {
      final d = free.where((d) => d.itemId == w.$1.id).firstOrNull;
      if (d == null) {
        open.add(w);
      } else {
        free.remove(d);
        pairs.add((d, w.$1, w.$2));
      }
    }
    for (final w in open) {
      var d = free.where((d) => d.loadedPath == w.$1.path).firstOrNull;
      d ??= free.isNotEmpty ? free.first : null;
      if (d != null) {
        free.remove(d);
      } else {
        d = _newOverlayDeck();
        if (d == null) continue;
      }
      pairs.add((d, w.$1, w.$2));
    }
    for (final d in free) {
      if (d.itemId != null) {
        d.itemId = null;
        d.key = null;
        d.cued = null;
        notifyListeners();
      }
      if (d.playing) {
        d.playing = false;
        d.run(d.player.pause);
      }
    }
    for (final (d, o, current) in pairs) {
      if (current) {
        _driveOverlay(d, o, t, reposition: reposition);
      } else {
        _cueOverlay(d, o);
      }
    }
  }

  /// Loaded and waiting at the first frame of [o].
  void _cueOverlay(_OverlayDeck d, OverlayClip o) {
    final placement = (o.path, o.startMs, o.clip.inMs, o.clip.speed);
    if (d.itemId == o.id && d.cued == placement) return;
    final changed = d.itemId != o.id;
    d.itemId = o.id;
    d.key = null;
    d.cued = placement;
    if (d.playing) {
      d.playing = false;
      d.run(d.player.pause);
    }
    if (changed) notifyListeners();
    _setOverlayRate(d, o);
    if (d.volume != 0) {
      d.volume = 0;
      d.run(() => d.player.setVolume(0));
    }
    final path = o.path;
    d.expectedSrcMs = o.clip.inMs;
    d.settled = false;
    d.run(moves: true, () async {
      if (d.loadedPath == path) {
        await d.player.seek(o.clip.inMs);
        await d.player.pause();
      } else {
        d.loadedPath = null;
        await d.player.open(path, positionMs: o.clip.inMs, play: false);
        d.loadedPath = path;
        if (!_disposed) notifyListeners();
      }
    });
  }

  void _setOverlayRate(_OverlayDeck d, OverlayClip o) {
    final rate = o.clip.speed;
    if (d.rate != rate) {
      d.rate = rate;
      d.run(() => d.player.setRate(rate));
    }
    final track = previewAudioTrack(o.clip);
    if (d.audioTrack != track) {
      d.audioTrack = track;
      d.run(() => d.player.setAudioTrack(track));
    }
  }

  /// [o] on [d] at the playhead [t]: playing along, or paused on its frame.
  void _driveOverlay(_OverlayDeck d, OverlayClip o, int t,
      {required bool reposition}) {
    final src = _overlaySrc(o, t);
    final volume = _playing ? _overlayVolume(o, t) : 0.0;
    final key = (o.path, o.startMs, o.clip.inMs, o.clip.outMs, o.clip.speed);
    final changed = d.itemId != o.id;
    final fromCue = d.cued != null &&
        d.cued == (o.path, o.startMs, o.clip.inMs, o.clip.speed) &&
        src - o.clip.inMs <= audioLateToleranceMs + 100;
    d.itemId = o.id;
    d.cued = null;
    if (changed) notifyListeners();
    _setOverlayRate(d, o);
    final old = d.volume;
    if (old == null ||
        (volume - old).abs() >= 0.02 ||
        (volume == 0) != (old == 0)) {
      d.volume = volume;
      d.run(() => d.player.setVolume(volume));
    }
    final same = d.key == key && d.playing == _playing && !reposition;
    if (same) return;
    d.key = key;
    d.playing = _playing;
    d.expectedSrcMs = src;
    d.settled = false;
    // A fresh start may be corrected at once (once it reports near where
    // it was put); after that at most every [soundFixIntervalMs].
    d.lastFixUs = -1 << 40;
    final path = o.path;
    final play = _playing;
    d.run(moves: true, () async {
      if (d.loadedPath == path) {
        if (!(fromCue && play)) await d.player.seek(src);
        await (play ? d.player.play() : d.player.pause());
      } else {
        d.loadedPath = null;
        await d.player.open(path, positionMs: src, play: play);
        d.loadedPath = path;
        if (!_disposed) notifyListeners();
        // Loading took a moment while the clock ran on: catch up.
        if (_disposed || !play || !_playing || d.itemId != o.id) return;
        final now = _overlaySrc(o, positionMs);
        if ((now - src).abs() > audioLateToleranceMs) {
          d.expectedSrcMs = now;
          await d.player.seek(now);
        }
      }
    });
  }

  void _onOverlayPosition(_OverlayDeck d, int ms) {
    if (_disposed || !_playing || !d.playing || d.moving > 0) return;
    final o = _project.overlays.where((x) => x.id == d.itemId).firstOrNull;
    if (o == null) return;
    if (!d.settled) {
      if ((ms - d.expectedSrcMs).abs() > settleToleranceMs) return;
      d.settled = true;
      return;
    }
    final target = _overlaySrc(o, positionMs);
    if ((ms - target).abs() <= overlayDriftLimitMs) return;
    final nowUs = _clock.elapsedMicroseconds;
    if (nowUs - d.lastFixUs < soundFixIntervalMs * 1000) return;
    d.lastFixUs = nowUs;
    d.expectedSrcMs = target;
    d.settled = false;
    d.run(moves: true, () => d.player.seek(target));
  }

  /// Lets go of the players. Call once the video surfaces are out of the
  /// widget tree (the editor's own dispose comes after its children's).
  /// Safe to call more than once.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final d in _decks) {
      d.positionSub?.cancel();
      d.completedSub?.cancel();
      d.player.dispose().catchError((_) {});
    }
    for (final slot in _audio) {
      slot.sub?.cancel();
      slot.run(slot.player.dispose);
    }
    _audio.clear();
    for (final d in _overlayDecks) {
      d.sub?.cancel();
      d.run(d.player.dispose);
    }
    _overlayDecks.clear();
    for (final s in _sounds) {
      s.sub?.cancel();
      s.run(s.player.dispose);
    }
    _sounds.clear();
    _position.dispose();
    _hearOriginal.dispose();
    super.dispose();
  }
}

/// One video player and what the controller knows about it.
class _Deck {
  _Deck(this.index, this.player);

  final int index;
  final TimelinePlayer player;
  StreamSubscription<int>? positionSub;
  StreamSubscription<void>? completedSub;

  Future<void> queue = Future.value();

  /// Commands that move the player and are not finished; while there are
  /// any, the positions it reports are not to be trusted.
  int moving = 0;
  int gen = 0;

  /// The file the player holds; null while it is loading another one.
  String? loadedPath;

  /// The clip whose picture the player shows (its last frame while another
  /// file loads).
  Clip? shownClip;
  bool playing = false;
  double? volume;
  double rate = 1.0;

  /// Sound settings as last set (a new player plays the first stream with
  /// no filters).
  int audioTrack = 0;
  String audioFilter = '';

  /// Where the last seek / load put the player; reports far from it are
  /// leftovers until one close to it arrives ([settled]).
  int expectedSrcMs = 0;
  bool settled = false;

  /// The last trusted position report and the time since.
  bool reported = false;
  int lastSrcMs = 0;
  int sinceReportMs = 0;

  /// File and position this deck was asked to hold ready (paused), and
  /// whether it got there.
  (String, int)? preloaded;
  bool preloadDone = false;
}

class _AudioSlot {
  _AudioSlot(this.player);
  final TimelinePlayer player;
  String? loadedPath;
  bool playing = false;
  double? volume;

  /// The sound clip it last played or waited for.
  String? audioId;

  /// Speed, stream and filters as last set.
  double rate = 1;
  int audioTrack = 0;
  String audioFilter = '';
  (String, int, int)? placement;

  /// Placement this player was loaded for ahead of time (paused at the
  /// start of the sound).
  (String, int, int)? cued;
  StreamSubscription<int>? sub;

  /// For a sound that belongs to a video clip and follows it (a voice
  /// recorded separately, a separated sound): that clip, and where the
  /// sound's file is against the clip's (file time = clip time + offset).
  /// Such a sound is kept in step with the PICTURE (lip sync), like
  /// processed clip sound; see [PlaybackController._onAudioPosition].
  String? linkClipId;
  int linkOffsetMs = 0;

  /// Smoothed sound-minus-picture difference, and how many reports made it.
  double? drift;
  int reports = 0;
  int lastFixUs = -1 << 40;
  bool startFixed = false;

  /// Commands that move it and are not finished.
  int moving = 0;
  Future<void> _queue = Future.value();

  /// Runs player commands one after another, swallowing player errors.
  void run(Future<void> Function() command, {bool moves = false}) {
    if (moves) moving++;
    _queue = _queue.then((_) async {
      try {
        await command();
      } catch (_) {
      } finally {
        if (moves) moving--;
      }
    });
  }
}

/// What a sound player should play: [path] (a processed file) for [clip]
/// at source position [srcMs] and level [volume].
class _SoundWant {
  _SoundWant(this.clip, this.path, this.srcMs, this.volume);
  final Clip clip;
  final String path;
  final int srcMs;
  final double volume;
}

/// A sound player for processed clip sound and what is known about it.
class _SoundSlot {
  _SoundSlot(this.player);
  final TimelinePlayer player;
  StreamSubscription<int>? sub;

  /// The file asked for, and the file it has loaded (null while loading).
  String? path;
  String? loadedPath;

  /// The clip it plays for, and that clip's out point.
  String? clipId;
  int? clipOutMs;
  bool playing = false;
  double? volume;
  double rate = 1;

  /// Where the last seek / load put it; reports far from it are leftovers.
  int expectedSrcMs = 0;
  bool settled = false;

  /// Smoothed sound-minus-picture difference, and how many reports made it.
  double? drift;
  int reports = 0;
  int lastFixUs = -1 << 40;

  /// The start-up correction is done (or was not needed) since it last
  /// started playing.
  bool startFixed = false;

  /// Commands that move it and are not finished.
  int moving = 0;
  Future<void> _queue = Future.value();

  /// Runs player commands one after another, swallowing player errors.
  void run(Future<void> Function() command, {bool moves = false}) {
    if (moves) moving++;
    _queue = _queue.then((_) async {
      try {
        await command();
      } catch (_) {
      } finally {
        if (moves) moving--;
      }
    });
  }
}

/// A video player of the overlay track and what is known about it.
class _OverlayDeck {
  _OverlayDeck(this.player);
  final TimelinePlayer player;
  StreamSubscription<int>? sub;

  /// The overlay item it plays (or waits for), and what it was set up for.
  String? itemId;
  Object? key;
  (String, int, int, double)? cued;

  /// The file it holds; null while loading one.
  String? loadedPath;
  bool playing = false;
  double? volume;
  double rate = 1;
  int audioTrack = 0;
  int expectedSrcMs = 0;
  bool settled = false;
  int lastFixUs = -1 << 40;
  int moving = 0;
  Future<void> _queue = Future.value();

  void run(Future<void> Function() command, {bool moves = false}) {
    if (moves) moving++;
    _queue = _queue.then((_) async {
      try {
        await command();
      } catch (_) {
      } finally {
        if (moves) moving--;
      }
    });
  }
}
