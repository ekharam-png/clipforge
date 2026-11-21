// Everything the app does in the background by itself (sound pictures,
// thumbnail strips, FFmpeg runs nobody waits for, processed sound) can be
// PAUSED in one go (1.18).
//
// 1.17 had a safety valve for the sound pictures only. A real Mac then
// did not respond for 100 s right after a project opened, with the
// pictures long finished: the valve had nothing to pause. Now every kind
// of background work registers here, and a gap of two seconds or more
// (PerfLog) pauses all of it until the user turns it back on. Pure Dart.

import 'perf_log.dart';

/// One kind of background work.
class BackgroundTask {
  BackgroundTask(this.name,
      {required this.pause, required this.resume, required this.busy});

  /// Whether any of it is running or waiting right now.
  final bool Function() busy;

  /// For the performance log (never a file name).
  final String name;

  /// Stops what is running and starts nothing new until [resume].
  final void Function() pause;
  final void Function() resume;
}

class BackgroundWork {
  BackgroundWork({PerfLog? log}) : _log = log ?? PerfLog.instance;

  /// The app's one registry. Tests may make their own.
  static final BackgroundWork instance = BackgroundWork();

  final PerfLog _log;
  final List<BackgroundTask> _tasks = [];
  final List<void Function()> _listeners = [];

  /// True from [pauseAll] to [resumeAll].
  bool get paused => _paused;
  bool _paused = false;

  /// How long the app could not respond when the work was paused (ms).
  int get pausedAfterMs => _pausedAfterMs;
  int _pausedAfterMs = 0;

  List<String> get names => [for (final t in _tasks) t.name];

  /// Adds [task]; work that registers while everything is paused is
  /// paused at once.
  void add(BackgroundTask task) {
    _tasks.add(task);
    if (_paused) _safely(task.pause);
  }

  void remove(BackgroundTask task) => _tasks.remove(task);

  void addListener(void Function() f) => _listeners.add(f);
  void removeListener(void Function() f) => _listeners.remove(f);

  /// The app could not respond for [gapMs]: all background work stops.
  /// Does nothing below [kUnresponsiveMs] or when already paused.
  void onGap(int gapMs) {
    if (gapMs < kUnresponsiveMs) return;
    pauseAll(gapMs);
  }

  /// Nothing happens when no background work is running or waiting: a
  /// gap with nothing in the background (the computer slept, a slow
  /// dialog of the system) is not theirs to fix.
  void pauseAll(int gapMs) {
    if (_paused) return;
    final busy = [
      for (final t in _tasks)
        if (_isBusy(t)) t.name,
    ];
    if (busy.isEmpty) return;
    _paused = true;
    _pausedAfterMs = gapMs;
    _log.note('background work paused: the app did not respond for '
        '$gapMs ms (busy: ${busy.join(', ')})');
    for (final t in [..._tasks]) {
      _safely(t.pause);
    }
    _tell();
  }

  /// "Turn back on".
  void resumeAll() {
    if (!_paused) return;
    _paused = false;
    _log.note('background work turned back on');
    for (final t in [..._tasks]) {
      _safely(t.resume);
    }
    _tell();
  }

  void _tell() {
    for (final f in [..._listeners]) {
      _safely(f);
    }
  }

  static bool _isBusy(BackgroundTask t) {
    try {
      return t.busy();
    } catch (_) {
      return false;
    }
  }

  static void _safely(void Function() f) {
    try {
      f();
    } catch (_) {}
  }
}
