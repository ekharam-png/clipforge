import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/model/project.dart';
import '../../media/media_api.dart';
import '../../media/processed_sound.dart';
import '../../media/processed_sound_cache.dart';

/// Where a clip's processed sound is (see media/processed_sound.dart).
enum SoundState {
  /// The clip needs no processed sound (no clean-up or voice focus, no
  /// sound, or its file is missing).
  none,

  /// Waiting: the settings may still change (a slider being dragged), or
  /// other clips go first.
  waiting,

  /// Being rendered now ([SoundStatus.fraction]).
  processing,

  /// Ready: the preview plays it and the export reads it.
  ready,

  /// The render failed ([SoundStatus.error]); preview and export use the
  /// normal chain.
  failed,

  /// The user stopped it; it waits for "Process sound" or a new setting.
  stopped,
}

@immutable
class SoundStatus {
  const SoundStatus(this.state, {this.fraction = 0, this.error});
  final SoundState state;

  /// 0..1 while [SoundState.processing].
  final double fraction;
  final String? error;

  static const none = SoundStatus(SoundState.none);

  /// True while the sound is on its way (waiting or processing).
  bool get preparing =>
      state == SoundState.waiting || state == SoundState.processing;

  /// "Processing sound… 40%", "Preparing sound…", ...
  String get label => switch (state) {
        SoundState.none => '',
        SoundState.waiting => 'Preparing sound…',
        SoundState.processing =>
          'Processing sound… ${(fraction * 100).floor().clamp(0, 99)}%',
        SoundState.ready => 'Sound ready',
        SoundState.failed => 'Sound could not be processed',
        SoundState.stopped => 'Sound processing stopped',
      };

  @override
  bool operator ==(Object other) =>
      other is SoundStatus &&
      other.state == state &&
      other.fraction == fraction &&
      other.error == error;

  @override
  int get hashCode => Object.hash(state, fraction, error);
}

/// Renders the processed sound of the clips of the open project in the
/// background ("instant sound processing"), one or two at a time.
///
/// * [update] after every edit: each clip that needs processed sound
///   ([clipNeedsProcessedSound]) gets its cache key ([ProcessedSoundCache.
///   keyFor]); files already in the cache are ready at once. Pieces of one
///   file with the same settings share one key, so one render.
/// * A key only starts rendering once it has been wanted for [debounce]
///   without the wanted set changing (a slider being dragged changes the
///   key on every frame; nothing renders until it settles). A render whose
///   key is no longer wanted by any clip is stopped.
/// * At most [maxBusy] renders run at once; while the preview plays
///   ([playing]) only one, so that the preview keeps up. The clip under
///   the playhead ([focusIndex]) goes first, then the rest in timeline
///   order.
/// * The user can [stop] a render (it then waits until [retry] or until
///   the settings change) and [retry] a failed or stopped one.
/// * After every finished render the cache is cut down to [maxCacheBytes]
///   (least recently used first, never a file a clip wants now).
class SoundRenders extends ChangeNotifier {
  SoundRenders({
    required this.engine,
    required this.cache,
    this.debounce = const Duration(milliseconds: 800),
    this.maxBusy = 2,
    this.maxCacheBytes = kProcessedSoundCacheBytes,
    this.focusIndex,
  }) {
    _cacheReady = cache.ready().then((_) {
      if (_disposed) return;
      _isCacheReady = true;
      _refresh(force: true);
    }, onError: (Object e) {
      _cacheError = '$e';
    });
  }

  final MediaEngine engine;
  final ProcessedSoundCache cache;
  final Duration debounce;
  final int maxBusy;
  final int maxCacheBytes;

  /// Index of the clip under the playhead (it is rendered first).
  final int Function()? focusIndex;

  late final Future<void> _cacheReady;
  bool _isCacheReady = false;
  String? _cacheError;
  bool _disposed = false;

  Project? _project;

  /// clip id -> key, from the last [update].
  Map<String, String> _keys = const {};

  /// key -> the first clip (timeline order) that wants it.
  Map<String, Clip> _wanted = const {};

  final Set<String> _ready = {};

  /// Changes whenever a file becomes ready or stops being used.
  int get readyVersion => _readyVersion;
  int _readyVersion = 0;
  Set<String> _lastReady = const {};

  @override
  void notifyListeners() {
    final now = {
      for (final k in _ready)
        if (_wanted.containsKey(k)) k
    };
    if (!setEquals(now, _lastReady)) {
      _lastReady = now;
      _readyVersion++;
    }
    super.notifyListeners();
  }
  final Map<String, _Render> _busy = {};
  final Map<String, String> _failed = {};
  final Set<String> _stopped = {};

  /// Keys waiting for [debounce] to pass.
  final Set<String> _settling = {};

  /// Keys waiting for a free slot.
  final Set<String> _queued = {};
  Timer? _settle;

  bool _playing = false;

  /// While true at most one render runs.
  bool get playing => _playing;
  set playing(bool on) {
    if (_playing == on) return;
    _playing = on;
    if (!on) _pump();
  }

  /// Completes once the cache folder is known (tests).
  Future<void> get cacheReady => _cacheReady;

  /// Number of renders running now.
  int get busyCount => _busy.length;

  /// The keys being rendered now (tests).
  Iterable<String> get busyKeys => _busy.keys;

  int get _limit => _playing ? 1 : maxBusy;

  /// Call after every change of the project.
  void update(Project project) {
    if (_disposed || identical(project, _project)) return;
    _project = project;
    _refresh();
  }

  void _refresh({bool force = false}) {
    final project = _project;
    if (project == null || _disposed) return;
    final keys = <String, String>{};
    final wanted = <String, Clip>{};
    for (final c in _sources(project)) {
      final k = cache.keyFor(c);
      if (k == null) continue;
      keys[c.id] = k;
      wanted.putIfAbsent(k, () => c);
    }
    final changed = force ||
        !mapEquals(keys, _keys) ||
        !setEquals(wanted.keys.toSet(), _wanted.keys.toSet());
    _keys = keys;
    _wanted = wanted;
    if (!changed) return;

    // What is no longer wanted stops waiting, and stops rendering.
    _settling.removeWhere((k) => !wanted.containsKey(k));
    _queued.removeWhere((k) => !wanted.containsKey(k));
    for (final k in [..._busy.keys]) {
      if (!wanted.containsKey(k)) _busy.remove(k)!.obsolete();
    }
    _stopped.removeWhere((k) => !wanted.containsKey(k));
    _failed.removeWhere((k, _) => !wanted.containsKey(k));

    var added = false;
    if (_isCacheReady) {
      for (final k in wanted.keys) {
        if (_ready.contains(k)) continue;
        if (cache.has(k)) {
          _ready.add(k);
          cache.touch(k);
          continue;
        }
        if (_busy.containsKey(k) ||
            _queued.contains(k) ||
            _failed.containsKey(k) ||
            _stopped.contains(k)) {
          continue;
        }
        if (_settling.add(k)) added = true;
      }
    }
    // Ready files that vanished (cleared by hand, evicted elsewhere).
    _ready.removeWhere((k) => wanted.containsKey(k) && !cache.has(k));
    if (added) {
      // Every new wish starts the wait again: a drag settles first.
      _settle?.cancel();
      _settle = Timer(debounce, _settled);
    }
    _pump();
    notifyListeners();
  }

  void _settled() {
    _settle = null;
    if (_disposed) return;
    _queued.addAll(_settling);
    _settling.clear();
    _pump();
    notifyListeners();
  }

  /// Starts renders while there is room, nearest the playhead first.
  void _pump() {
    if (_disposed || !_isCacheReady) return;
    while (_busy.length < _limit && _queued.isNotEmpty) {
      final key = _next();
      _queued.remove(key);
      final clip = _wanted[key];
      if (clip == null) continue;
      _start(key, clip);
    }
  }

  String _next() {
    final project = _project;
    final clips = project == null ? const <Clip>[] : _sources(project);
    final focus = focusIndex?.call() ?? -1;
    String? best;
    var bestRank = 1 << 30;
    for (var i = 0; i < clips.length; i++) {
      final k = _keys[clips[i].id];
      if (k == null || !_queued.contains(k)) continue;
      // The clip under the playhead, then those after it, then before.
      final rank = focus < 0 ? i : (i >= focus ? i - focus : clips.length + i);
      if (rank < bestRank) {
        bestRank = rank;
        best = k;
      }
    }
    return best ?? _queued.first;
  }

  void _start(String key, Clip clip) {
    final ExportJob job;
    try {
      job = engine.renderClipSound(clip, cache.pathFor(key));
    } catch (e) {
      _failed[key] = '$e';
      return;
    }
    final render = _busy[key] = _Render(job);
    render.sub = job.progress.listen((e) {
      if (_disposed || _busy[key] != render) return;
      final f = e.fraction.clamp(0.0, 1.0);
      // A step of a percent is worth showing; less is not.
      if ((f - render.fraction).abs() < 0.01 && f < 1) return;
      render.fraction = f;
      notifyListeners();
    });
    job.done.then((_) {
      if (_disposed || _busy[key] != render) return;
      _busy.remove(key);
      render.sub?.cancel();
      if (cache.has(key)) {
        _ready.add(key);
        cache.touch(key);
        unawaited(cache
            .evict(maxBytes: maxCacheBytes, keep: _wanted.keys.toSet())
            .catchError((Object _) => 0));
      } else {
        _failed[key] = 'The processed sound was not written.';
      }
      _pump();
      notifyListeners();
    }, onError: (Object e) {
      render.sub?.cancel();
      if (_disposed || _busy[key] != render) return;
      _busy.remove(key);
      if (render.stoppedByUser || (e is ExportException && e.cancelled)) {
        _stopped.add(key);
      } else {
        _failed[key] = e is ExportException ? e.message : '$e';
      }
      _pump();
      notifyListeners();
    });
  }

  /// The key of [clip]'s processed sound as of the last [update]; null
  /// when it needs none.
  String? keyOf(Clip clip) {
    final k = _keys[clip.id];
    if (k == null) return null;
    // A clip that is not the one in the project (being dragged, from
    // another state): only if it has the same settings.
    final project = _project;
    final own = project == null
        ? null
        : _sources(project).where((c) => c.id == clip.id).firstOrNull;
    if (own == null || identical(own, clip)) return k;
    return processedSoundSignature(own) == processedSoundSignature(clip) &&
            own.path == clip.path
        ? k
        : cache.keyFor(clip);
  }

  SoundStatus statusOf(Clip clip) {
    final k = keyOf(clip);
    if (k == null) return SoundStatus.none;
    if (_ready.contains(k)) return const SoundStatus(SoundState.ready);
    final busy = _busy[k];
    if (busy != null) {
      return SoundStatus(SoundState.processing, fraction: busy.fraction);
    }
    final failed = _failed[k] ?? _cacheError;
    if (failed != null) return SoundStatus(SoundState.failed, error: failed);
    if (_stopped.contains(k)) return const SoundStatus(SoundState.stopped);
    return const SoundStatus(SoundState.waiting);
  }

  /// The ready processed file of [clip], or null.
  String? readyPath(Clip clip) {
    final k = keyOf(clip);
    if (k == null || !_ready.contains(k)) return null;
    return cache.pathFor(k);
  }

  /// Ready processed files by clip id, for the export
  /// ([ExportOptions.processedSound]). Checked on disk once more.
  Map<String, String> readyFiles(Project project) {
    final out = <String, String>{};
    for (final c in _sources(project)) {
      final k = cache.keyFor(c);
      if (k == null || !_ready.contains(k) || !cache.has(k)) continue;
      out[c.id] = cache.pathFor(k);
    }
    return out;
  }

  /// Stops the render of [clip]'s sound (the preview and export use the
  /// normal chain) until [retry] or a change of its settings.
  void stop(Clip clip) {
    final k = keyOf(clip);
    if (k == null) return;
    _settling.remove(k);
    _queued.remove(k);
    final busy = _busy[k];
    if (busy != null) {
      busy.stoppedByUser = true;
      unawaited(busy.job.cancel());
    } else {
      _stopped.add(k);
    }
    notifyListeners();
  }

  /// Renders [clip]'s sound again after a failure or [stop], at once.
  void retry(Clip clip) {
    final k = keyOf(clip);
    if (k == null || _ready.contains(k) || _busy.containsKey(k)) return;
    _failed.remove(k);
    _stopped.remove(k);
    _settling.remove(k);
    _queued.add(k);
    _pump();
    notifyListeners();
  }

  /// Stops every render (the editor closes).
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _settle?.cancel();
    for (final r in _busy.values) {
      r.obsolete();
    }
    _busy.clear();
    super.dispose();
  }
}

class _Render {
  _Render(this.job);
  final ExportJob job;
  double fraction = 0;
  bool stoppedByUser = false;
  StreamSubscription<ExportProgress>? sub;

  void obsolete() {
    sub?.cancel();
    unawaited(job.cancel().catchError((Object _) {}));
  }
}

/// Everything with a clip's sound settings: the video clips, then the
/// sound clips seen as clips ([AudioClip.soundClip]: a separated sound
/// with clean-up or voice focus is processed like its clip, and shares
/// its file when the settings are the same).
List<Clip> _sources(Project p) {
  final cached = _sourceCache[p];
  if (cached != null) return cached;
  final out = p.audio.isEmpty
      ? p.clips
      : List<Clip>.unmodifiable([...p.clips, for (final a in p.audio) a.soundClip]);
  _sourceCache[p] = out;
  return out;
}

final Expando<List<Clip>> _sourceCache = Expando('sound sources');
