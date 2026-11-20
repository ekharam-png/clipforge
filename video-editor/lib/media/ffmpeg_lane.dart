// The order in which FFmpeg runs inside the app's own process (the
// FFmpegKit engine: Windows, macOS, Android). Pure Dart, tested without
// the plugin.
//
// Why (1.17, a real Windows PC stalled with "Saving…" and "Drawing
// sound…" on screen): every run is a whole FFmpeg in the app's process.
// The rules:
//
//  * ONE run at a time in the lane.
//  * What the user is waiting for ([LanePriority.user]: a frame, a
//    thumbnail of the project list, Remove silences, Line up by sound)
//    goes before background work ([LanePriority.background]: sound
//    pictures, thumbnail strips).
//  * Background work is PRE-EMPTED: when a user run arrives while a
//    background run is going, that one is told to stop, the user run goes
//    first, and the background run starts again later (from the
//    beginning; its caller only sees that it took longer).
//  * While an export runs ([exportStarted] .. [exportEnded]) no
//    background run is started and a running one is stopped; it comes
//    back after the export.
//
// Probes and saves are NOT in the lane: they never wait for a run.

import 'dart:async';
import 'dart:collection';

import '../core/perf_log.dart';

enum LanePriority { user, background }

/// What a job in the lane is given.
class LaneRun {
  final Completer<void> _stop = Completer<void>();

  /// Completes when the job must stop now because something more
  /// important is waiting. Only ever completes for background jobs.
  Future<void> get preempted => _stop.future;

  bool get isPreempted => _stop.isCompleted;
}

class _Job<T> {
  _Job(this.priority, this.label, this.body);
  final LanePriority priority;
  final String label;
  final Future<T> Function(LaneRun run) body;
  final Completer<T> done = Completer<T>();
  int starts = 0;
}

class FfmpegLane {
  FfmpegLane({PerfLog? log, this.maxRestarts = 20})
      : _log = log ?? PerfLog.instance;

  final PerfLog _log;

  /// A background job that was pre-empted this often runs to the end the
  /// next time (it could otherwise never finish).
  final int maxRestarts;

  final Queue<_Job<Object?>> _user = Queue();
  final Queue<_Job<Object?>> _background = Queue();
  _Job<Object?>? _running;
  LaneRun? _run;
  int _exports = 0;

  /// Jobs waiting (not the running one).
  int get waiting => _user.length + _background.length;
  bool get busy => _running != null;
  bool get exporting => _exports > 0;

  /// Runs [body] when it is its turn. [label] goes to the performance
  /// log (no file names).
  Future<T> run<T>(LanePriority priority, String label,
      Future<T> Function(LaneRun run) body) {
    final job = _Job<Object?>(priority, label, body);
    (priority == LanePriority.user ? _user : _background).add(job);
    if (priority == LanePriority.user) _preempt('a user run is waiting');
    _pump();
    return job.done.future.then((v) => v as T);
  }

  /// An export started: background runs wait until [exportEnded].
  void exportStarted() {
    _exports++;
    _log.note('lane: export started, background runs wait');
    _preempt('an export started');
  }

  void exportEnded() {
    if (_exports > 0) _exports--;
    if (_exports == 0) _log.note('lane: export over');
    _pump();
  }

  void _preempt(String why) {
    final job = _running;
    final run = _run;
    if (job == null || run == null) return;
    if (job.priority != LanePriority.background) return;
    if (run.isPreempted || job.starts > maxRestarts) return;
    _log.note('lane: ${job.label} put back ($why)');
    run._stop.complete();
  }

  void _pump() {
    if (_running != null) return;
    final _Job<Object?> job;
    if (_user.isNotEmpty) {
      job = _user.removeFirst();
    } else if (_background.isNotEmpty && _exports == 0) {
      job = _background.removeFirst();
    } else {
      return;
    }
    _running = job;
    final run = _run = LaneRun();
    job.starts++;
    final end = _log.span('lane: ${job.label}');
    () async {
      Object? value;
      Object? error;
      StackTrace? trace;
      try {
        value = await job.body(run);
      } catch (e, st) {
        error = e;
        trace = st;
      }
      _running = null;
      _run = null;
      if (run.isPreempted && job.priority == LanePriority.background) {
        // Whatever it answered while being stopped does not count: it
        // goes again, before the other background jobs.
        end('put back');
        _background.addFirst(job);
      } else if (error != null) {
        end('failed');
        job.done.completeError(error, trace);
      } else {
        end();
        job.done.complete(value);
      }
      _pump();
    }();
  }
}

/// Lets at most one call in [minGap] through (the first at once, the
/// latest value when the gap is over): progress of an FFmpeg run arrives
/// as often as FFmpeg likes, the app's own isolate is told at most four
/// times a second.
class Throttle<T> {
  Throttle(this.onValue, {this.minGap = const Duration(milliseconds: 250)});

  final void Function(T value) onValue;
  final Duration minGap;
  final Stopwatch _since = Stopwatch();
  Timer? _timer;
  T? _latest;
  bool _has = false;

  void add(T value) {
    if (!_since.isRunning || _since.elapsed >= minGap) {
      _timer?.cancel();
      _timer = null;
      _has = false;
      _since
        ..reset()
        ..start();
      onValue(value);
      return;
    }
    _latest = value;
    _has = true;
    _timer ??= Timer(minGap - _since.elapsed, () {
      _timer = null;
      if (!_has) return;
      _has = false;
      _since
        ..reset()
        ..start();
      onValue(_latest as T);
    });
  }

  /// Drops a value that is still waiting (the run is over).
  void close() {
    _timer?.cancel();
    _timer = null;
    _has = false;
  }
}
