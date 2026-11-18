// The sound pictures of an open project (1.13): the waveforms on the
// timeline and who is speaking. Each file's picture is read once, in the
// background, one file at a time (the engine keeps it on disk); the
// timeline draws what is there and is told when more arrives.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/model/project.dart';
import '../../media/media_api.dart';
import '../../media/sound_peaks_job.dart';
import '../../media/speech_map.dart';

class SoundPictures extends ChangeNotifier {
  SoundPictures({
    required this.engine,
    required this.cacheDir,
    this.fileExists,
  });

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
    if (on && _project != null) update(_project!);
    if (!on) _queue.clear();
    notifyListeners();
  }

  /// True while pictures are being read ("drawing sound…").
  bool get busy => _running || _queue.isNotEmpty;

  static String _key(String path, int track) => '$path|$track';

  SoundPeaks? peaksOf(String path, int audioTrack) =>
      _enabled ? _peaks[_key(path, audioTrack)] : null;

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
    if (!_enabled || engine is! SoundPeaksEngine) return;
    final wanted = <String, ({String path, int track})>{};
    for (final a in project.audio) {
      final t = a.soundClip.audioTrackInUse;
      wanted[_key(a.path, t)] = (path: a.path, track: t);
    }
    for (final c in project.clips) {
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
      _queue.add(e.value);
    }
    if (_queue.isNotEmpty && !_running) unawaited(_run());
  }

  Future<void> _run() async {
    _running = true;
    // Let the frame that asked finish first.
    await Future<void>.delayed(Duration.zero);
    if (!_disposed) notifyListeners();
    try {
      if (!_dirKnown) {
        _dirKnown = true;
        try {
          _dir = await cacheDir();
          if (_dir != null) unawaited(evictSoundPeaks(_dir!));
        } catch (_) {
          _dir = null;
        }
      }
      while (_queue.isNotEmpty && !_disposed && _enabled) {
        final job = _queue.removeAt(0);
        final key = _key(job.path, job.track);
        try {
          final peaks = await (engine as SoundPeaksEngine)
              .soundPeaks(job.path, audioTrack: job.track, cacheDir: _dir);
          if (_disposed) return;
          if (peaks == null) {
            _failed.add(key);
          } else {
            _peaks[key] = peaks;
            _version++;
            _resolver = null;
            _speakers = null;
            notifyListeners();
          }
        } catch (_) {
          // Unreadable sound: the block stays plain.
          _failed.add(key);
        }
      }
    } finally {
      _running = false;
      if (!_disposed) notifyListeners();
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
    super.dispose();
  }
}
