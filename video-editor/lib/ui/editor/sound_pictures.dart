// The sound pictures of an open project (1.13): the waveforms on the
// timeline and who is speaking. Each file's picture is read once, in the
// background, one file at a time (the engine keeps it on disk); the
// timeline draws what is there and is told when more arrives.

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../core/model/project.dart';
import '../../core/perf_log.dart';
import '../../media/media_api.dart';
import '../../media/sound_peaks_job.dart';
import '../../media/speech_map.dart';

// Top-level, so that only the pictures travel to the other isolate (a
// closure inside the class would take the whole object along).
Future<List<TimeRange>> _singleElsewhere(SoundPeaks peaks) =>
    Isolate.run(() => speechStretches(peaks));

Future<List<List<TimeRange>>> _groupElsewhere(
        List<({SoundPeaks peaks, int offsetMs})> mics) =>
    Isolate.run(() => groupSpeechStretches(mics));

class SoundPictures extends ChangeNotifier {
  SoundPictures({
    required this.engine,
    required this.cacheDir,
    this.fileExists,
    this.playing,
    this.longFileMs = 600000,
    this.startDelay = const Duration(milliseconds: 1500),
  });

  /// True while the video plays. The pictures of LONG files are background
  /// work of the lowest priority (1.17): none is started while this says
  /// true, so reading them never competes with the preview's players.
  final bool Function()? playing;

  /// A project with a file at least this long counts as long: its
  /// pictures start only [startDelay] after the project was opened (the
  /// preview and the players come first) and wait while the video plays.
  /// Short projects are drawn at once, as before.
  final int longFileMs;
  final Duration startDelay;

  /// Files drawn and files asked for since the queue was last empty:
  /// "Drawing sound… 1 of 3".
  int get doneCount => _done;
  int get totalCount => _done + _queue.length + (_current == null ? 0 : 1);
  int _done = 0;
  ({String path, int track})? _current;
  Completer<void>? _cancel;

  /// The user pressed the ✕ next to "Drawing sound…": nothing more is
  /// read until the project changes its files or [resume] is called.
  bool get stopped => _stopped;
  bool _stopped = false;

  /// Stops reading now: the running ffmpeg is cancelled, the queue
  /// emptied. What is already drawn stays.
  void stop() {
    _stopped = true;
    _queue.clear();
    final c = _cancel;
    if (c != null && !c.isCompleted) c.complete();
    notifyListeners();
  }

  /// Reads the missing pictures after all ("Draw the sound", "Turn back
  /// on").
  void resume() {
    if (!_stopped) return;
    _stopped = false;
    _pausedForApp = false;
    if (_project != null) update(_project!);
    notifyListeners();
  }

  /// The safety valve (1.17): the app could not respond for [gapMs] while
  /// pictures were being drawn. Picture work stops for this editor (the
  /// setting stays as it is) and the timeline says so in one line, with
  /// "Turn back on" ([resume]). Does nothing when no picture is in work.
  void pauseForResponsiveness(int gapMs) {
    if (_disposed || !busy || _stopped) return;
    PerfLog.instance.note('sound pictures paused: the app did not respond '
        'for $gapMs ms while they were drawn');
    _pausedForApp = true;
    stop();
  }

  /// True after [pauseForResponsiveness], until [resume].
  bool get pausedForApp => _pausedForApp;
  bool _pausedForApp = false;

  /// Debug builds: how long each picture took (never in a release).
  static bool logTimings = false;

  final MediaEngine engine;

  /// The folder the pictures are kept in; null (or failing): not kept.
  final Future<String?> Function() cacheDir;

  /// Says whether a file is there (missing files are not asked for).
  final bool Function(String path)? fileExists;

  final Map<String, SoundPeaks> _peaks = {};
  final Set<String> _failed = {};
  final List<({String path, int track})> _queue = [];
  bool _running = false;
  bool _disposed = false;
  bool _enabled = true;
  Project? _project;
  String? _dir;
  bool _dirKnown = false;

  final SpeechCache _speech = SpeechCache();
  SpeechResolver? _resolver;
  List<SpeakerTrack>? _speakers;

  /// Bumped whenever a picture arrived.
  int get version => _version;
  int _version = 0;

  /// "Show sound waves" (an app setting, on by default).
  bool get enabled => _enabled;
  set enabled(bool on) {
    if (_enabled == on) return;
    _enabled = on;
    if (!on) {
      // Off stops a computation that is running, not only the queue -
      // unless "Only when speaking" still needs the pictures.
      _queue.clear();
      final needed = _project != null && _gateNeeds(_project!);
      final c = _cancel;
      if (!needed && c != null && !c.isCompleted) c.complete();
    } else {
      _stopped = false;
      _pausedForApp = false;
    }
    if (_project != null) update(_project!);
    notifyListeners();
  }

  /// True while pictures are being read ("drawing sound…").
  bool get busy => _running || _queue.isNotEmpty;

  static String _key(String path, int track) => '$path|$track';

  SoundPeaks? peaksOf(String path, int audioTrack) =>
      _enabled ? _peaks[_key(path, audioTrack)] : null;

  /// The picture whether or not "Show sound waves" is on: "Only when
  /// speaking" (1.17) needs it to work, not to be drawn.
  SoundPeaks? peaksFor(String path, int audioTrack) =>
      _peaks[_key(path, audioTrack)];

  /// The cache of where speech is, shared with the gate.
  SpeechCache get speechCache => _speech;

  /// The sounds whose pictures are needed even with "Show sound waves"
  /// off: everything on a speech track when a track has "Only when
  /// speaking" on (microphones recorded together are compared).
  static bool _gateNeeds(Project p) => p.soundTracks.any((t) => t.gate);

  /// Asks for the pictures [project] needs and drops what it no longer
  /// uses from memory.
  void update(Project project) {
    if (_disposed) return;
    final changed = !identical(project, _project);
    _project = project;
    if (changed) {
      _resolver = null;
      _speakers = null;
    }
    final forGate = !_enabled && _gateNeeds(project);
    if ((!_enabled && !forGate) || engine is! SoundPeaksEngine) return;
    _long = project.clips.any((c) => c.sourceDurationMs >= longFileMs) ||
        project.audio.any((a) => a.sourceDurationMs >= longFileMs);
    final speechTracks = {
      for (final t in project.soundTracks)
        if (t.speech) t.id,
    };
    final wanted = <String, ({String path, int track})>{};
    for (final a in project.audio) {
      if (forGate && !a.isVoice && !speechTracks.contains(a.trackId)) continue;
      final t = a.soundClip.audioTrackInUse;
      wanted[_key(a.path, t)] = (path: a.path, track: t);
    }
    for (final c in project.clips) {
      if (forGate) break;
      if (c.type != ClipType.video || !c.hasAudio) continue;
      wanted[_key(c.path, c.audioTrackInUse)] =
          (path: c.path, track: c.audioTrackInUse);
    }
    _peaks.removeWhere((k, _) => !wanted.containsKey(k));
    _queue.removeWhere((q) => !wanted.containsKey(_key(q.path, q.track)));
    for (final e in wanted.entries) {
      if (_peaks.containsKey(e.key) || _failed.contains(e.key)) continue;
      if (_queue.any((q) => _key(q.path, q.track) == e.key)) continue;
      if (fileExists != null && !fileExists!(e.value.path)) continue;
      if (_stopped) continue;
      _queue.add(e.value);
    }
    if (_queue.isNotEmpty && !_running) unawaited(_run());
  }

  bool _long = false;
  bool _delayed = false;

  /// The length of the file [path] in whole seconds as the project knows
  /// it (-1: unknown), for the performance log.
  int _secondsOf(String path) {
    final p = _project;
    if (p == null) return -1;
    for (final c in p.clips) {
      if (c.path == path) return c.sourceDurationMs ~/ 1000;
    }
    for (final a in p.audio) {
      if (a.path == path) return a.sourceDurationMs ~/ 1000;
    }
    return -1;
  }

  bool get _wanted =>
      _enabled || (_project != null && _gateNeeds(_project!));

  Future<void> _run() async {
    _running = true;
    _done = 0;
    // Let the frame that asked finish first.
    await Future<void>.delayed(Duration.zero);
    if (!_disposed) notifyListeners();
    try {
      // A long project: the preview and its players first.
      if (_long && !_delayed) {
        _delayed = true;
        await Future<void>.delayed(startDelay);
      }
      if (!_dirKnown) {
        _dirKnown = true;
        try {
          _dir = await cacheDir();
          if (_dir != null) unawaited(evictSoundPeaks(_dir!));
        } catch (_) {
          _dir = null;
        }
      }
      while (_queue.isNotEmpty && !_disposed && _wanted && !_stopped) {
        // Never START a long file while the video plays: one file at a
        // time, lowest priority.
        if (_long && (playing?.call() ?? false)) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        final job = _queue.removeAt(0);
        final key = _key(job.path, job.track);
        _current = job;
        final cancel = _cancel = Completer<void>();
        final watch = Stopwatch()..start();
        // Kind and length only: never a file name in the log.
        final seconds = _secondsOf(job.path);
        final noted = PerfLog.instance.span('sound picture '
            '${_done + 1} of $totalCount (${seconds < 0 ? 'unknown length' : '$seconds s'})');
        var outcome = 'end';
        notifyListeners();
        try {
          final e = engine;
          final peaks = e is CancellableSoundPeaksEngine
              ? await (e as CancellableSoundPeaksEngine).soundPeaksCancellable(
                  job.path,
                  audioTrack: job.track, cacheDir: _dir, cancel: cancel.future)
              : await (e as SoundPeaksEngine)
                  .soundPeaks(job.path, audioTrack: job.track, cacheDir: _dir);
          if (kDebugMode && logTimings) {
            debugPrint('sound picture: ${job.path} track ${job.track} in '
                '${watch.elapsedMilliseconds} ms');
          }
          if (_disposed) return;
          _done++;
          if (peaks != null) {
            // Before the timeline sees the picture.
            await PerfLog.instance
                .track('who is speaking', () => _primeSpeech(key, peaks));
            if (_disposed) return;
          }
          if (peaks == null) {
            outcome = 'no sound';
            _failed.add(key);
          } else {
            _peaks[key] = peaks;
            _version++;
            _resolver = null;
            _speakers = null;
            notifyListeners();
          }
        } on SoundPeaksCancelled {
          // Stopped on purpose: not a failure, it is asked for again
          // when wanted.
          outcome = 'stopped';
        } catch (_) {
          // Unreadable sound: the block stays plain.
          outcome = 'failed';
          _failed.add(key);
        } finally {
          noted(outcome);
          _current = null;
          if (identical(_cancel, cancel)) _cancel = null;
        }
        // Between two files: let the frames through.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _running = false;
      _current = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// Who talks when, for LONG files, worked out on another isolate before
  /// the timeline asks (1.17): the comparison of microphones recorded
  /// together goes hop by hop over every file, and the timeline asks for
  /// it while it builds a frame. Short files are quick and stay inline.
  Future<void> _primeSpeech(String newKey, SoundPeaks newPeaks) async {
    final p = _project;
    if (p == null) return;
    if (newPeaks.length * newPeaks.hopMs < longFileMs) return;
    final resolver = SpeechResolver(
        p,
        (path, track) =>
            _key(path, track) == newKey ? newPeaks : peaksFor(path, track),
        _speech);
    final seen = <String>{};
    for (final a in p.audio) {
      final job = resolver.speechJob(a);
      if (job == null) continue;
      final mics = job.mics;
      if (!mics.any((m) => m.peaks.length * m.peaks.hopMs >= longFileMs)) {
        continue;
      }
      final key = job.key;
      try {
        if (key == null) {
          final peaks = mics.single.peaks;
          if (_speech.hasSingle(peaks)) continue;
          _speech.putSingle(
              peaks, await _singleElsewhere(peaks));
        } else {
          if (!seen.add(key) || _speech.hasGroup(key, mics)) continue;
          _speech.putGroup(
              key, mics, await _groupElsewhere(mics));
        }
      } catch (_) {
        // Worked out inline when asked for, as before.
      }
      if (_disposed) return;
    }
  }

  SpeechResolver? get _resolved {
    final p = _project;
    if (p == null || !_enabled) return null;
    return _resolver ??= SpeechResolver(p, peaksOf, _speech);
  }

  /// True when [a] is drawn as speech (talk bright, pauses dim).
  bool isSpeech(AudioClip a) => _resolved?.isSpeech(a) ?? false;

  /// Where someone talks in [a]'s file (file time); null: not speech, or
  /// no picture yet.
  List<TimeRange>? speechOf(AudioClip a) => _resolved?.fileStretches(a);

  /// The speakers of the project with their talk on the timeline.
  List<SpeakerTrack> get speakers {
    final p = _project;
    if (p == null || !_enabled) return const [];
    return _speakers ??= speakerTracks(p, peaksOf, _speech);
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    // Leaving the project stops the ffmpeg that is reading a picture.
    final c = _cancel;
    if (c != null && !c.isCompleted) c.complete();
    super.dispose();
  }
}
