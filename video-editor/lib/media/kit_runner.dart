// How FFmpeg INSIDE the app (the FFmpegKit plugin: Windows, macOS,
// Android) is run without holding up the app's own isolate. Pure Dart: the
// plugin is behind [KitPlatform], so the rules are tested without it
// (test/media/v117_responsive_test.dart).
//
// 1.17, second pass after a real Windows test (importing one 25-minute
// video left "Saving…" and "Drawing sound…" on screen and the window did
// not answer). What was found in the plugin (ffmpeg_kit_flutter_new
// 4.6.8, Windows sources) and what this file does about it:
//
//  * EVERY line FFmpeg prints is sent to Dart as one message - on Windows
//    a posted window message and an event-channel message each, on the
//    platform thread - whether or not a log callback is set, and the
//    plugin's Dart side then prints it. `disableLogs` ([KitPlatform.quiet],
//    once) stops that at the source. The native session still keeps the
//    lines; they are fetched once, at the end, and only when the run
//    failed or its text is the result (`-encoders`, silencedetect).
//  * FFmpeg's log level is ONE value for the whole process, and every
//    session start sets it back to "info": a run started with
//    `-loglevel error` can be raised again by any other session. So no
//    run may depend on being quiet for the app to stay responsive - hence
//    the point above - and every run still says `-loglevel error
//    -nostats` ([args]).
//  * Fetching a session's log is a synchronous call on the platform
//    thread that waits up to FIVE seconds for lines still on their way.
//    It is not asked for after a successful quiet run, and never with
//    more than [kKitLogWaitMs].
//  * Statistics arrive about twice a second by themselves; they are
//    passed on at most four times a second anyway ([Throttle]).
//  * One run at a time, the user's first ([FfmpegLane]): sound pictures
//    and thumbnail strips are background runs, stopped and started again
//    when something else needs the lane, and they wait while an export
//    runs. Probes and exports are not in the lane.

import 'dart:async';

import '../core/perf_log.dart';
import 'ffmpeg_lane.dart';
import 'media_common.dart' show FfmpegRun;

/// The longest a log fetch may wait for lines still on their way (ms).
const int kKitLogWaitMs = 300;

/// How long a run that was asked to stop may take to end before the lane
/// goes on without it.
const Duration kKitStopGrace = Duration(seconds: 5);

/// A running FFmpeg session of the plugin.
abstract class KitSession {
  /// Completes with true when FFmpeg finished successfully.
  Future<bool> get finished;
  Future<void> cancel();

  /// Everything the session printed, waiting at most [waitMs] for lines
  /// still on their way.
  Future<String> log(int waitMs);
}

/// What [KitRunner] needs of the plugin. There is deliberately no way to
/// ask for log lines one by one.
abstract class KitPlatform {
  /// Switches the per-line log messages to Dart off (once per app run).
  Future<void> quiet();

  /// Starts FFmpeg with [args]; [onStatistics] gets the output position
  /// (ms) as often as the plugin reports it.
  Future<KitSession> start(List<String> args,
      {void Function(int timeMs)? onStatistics});
}

class KitRunner {
  KitRunner(this.platform,
      {FfmpegLane? lane, PerfLog? log, this.stopGrace = kKitStopGrace})
      : _log = log ?? PerfLog.instance,
        lane = lane ?? FfmpegLane(log: log);

  final KitPlatform platform;
  final Duration stopGrace;
  final FfmpegLane lane;
  final PerfLog _log;
  Future<void>? _quietOnce;

  /// The log messages are switched off before the first run (and stay
  /// off). A plugin that cannot do it is noted, not fatal.
  Future<void> quiet() => _quietOnce ??= () async {
        try {
          await platform.quiet();
          _log.note('ffmpeg in the app: log messages off');
        } catch (e) {
          _log.note('ffmpeg in the app: could not switch the log messages '
              'off (${e.runtimeType})');
        }
      }();

  /// `-hide_banner`, and `-loglevel error -nostats` unless [args] choose
  /// a level themselves. A run whose position is wanted ([progress]) gets
  /// no `-nostats`: on some builds the statistics come from the same
  /// report; at level error its text line is not printed anyway.
  static List<String> args(List<String> args, {bool progress = false}) => [
        '-hide_banner',
        if (!args.contains('-loglevel') && !args.contains('-v')) ...[
          '-loglevel', 'error',
        ],
        if (!progress && !args.contains('-nostats')) '-nostats',
        ...args,
      ];

  /// True when the text FFmpeg prints is the result of the run.
  static bool wantsLog(List<String> args) {
    final i = args.indexOf('-loglevel');
    if (i >= 0 && i + 1 < args.length && args[i + 1] != 'error') return true;
    return args.contains('-encoders') || args.contains('-filters');
  }

  /// What a run is, for the performance log (never a file name).
  static String label(List<String> args) {
    if (args.contains('-encoders') || args.contains('-filters')) return 'list';
    if (args.any((a) => a.contains('f%05d.jpg'))) return 'thumbnail strip';
    if (args.contains('s16le')) return 'sound decode';
    if (args.any((a) => a.contains('astats'))) return 'level scan';
    if (args.any((a) => a.contains('silencedetect'))) return 'silence scan';
    return 'run';
  }

  /// One FFmpeg run, outside any queue. [onTimeMs]: its position, at
  /// most four times a second. [stop] completing cancels it. The log is
  /// fetched only when the run failed by itself or [wantsLog].
  Future<FfmpegRun> session(List<String> runArgs,
      {void Function(int timeMs)? onTimeMs, Future<void>? stop}) async {
    await quiet();
    final throttle = onTimeMs == null ? null : Throttle<int>(onTimeMs);
    final session = await platform.start(
        args(runArgs, progress: onTimeMs != null),
        onStatistics: throttle?.add);
    var over = false, stopped = false;
    // A session that was asked to stop and does not end must not hold
    // the lane for ever (cancelling inside the plugin could not be tried
    // on every system): after [stopGrace] the run counts as over.
    final abandoned = Completer<bool>();
    Timer? grace;
    if (stop != null) {
      unawaited(stop.then((_) async {
        if (over) return;
        stopped = true;
        grace = Timer(stopGrace, () {
          if (over || abandoned.isCompleted) return;
          _log.note('ffmpeg in the app: a stopped run did not end within '
              '${stopGrace.inMilliseconds} ms; going on without it');
          abandoned.complete(false);
        });
        await session.cancel();
      }));
    }
    final ok = await Future.any([session.finished, abandoned.future]);
    over = true;
    grace?.cancel();
    throttle?.close();
    // Nobody reads the log of a run that was stopped on purpose.
    final log = !stopped && (!ok || wantsLog(runArgs))
        ? await session.log(kKitLogWaitMs)
        : '';
    return FfmpegRun(ok, log);
  }

  /// A run the user waits for: next in the lane.
  Future<FfmpegRun> user(List<String> runArgs) =>
      lane.run(LanePriority.user, label(runArgs), (_) => session(runArgs));

  /// Like [user], with progress and a way to stop.
  Future<FfmpegRun> streaming(List<String> runArgs,
          void Function(int timeMs) onTimeMs, Future<void> cancel) =>
      lane.run(LanePriority.user, label(runArgs),
          (_) => session(runArgs, onTimeMs: onTimeMs, stop: cancel));

  /// Background work (sound pictures, thumbnail strips): after everything
  /// else, stopped and started again when the lane is needed. [cancel]:
  /// the caller no longer wants it at all.
  Future<FfmpegRun> background(List<String> runArgs, {Future<void>? cancel}) {
    var cancelled = false;
    final inLane = lane.run(LanePriority.background, label(runArgs), (run) {
      // Its turn came (again) after the caller gave it up.
      if (cancelled) return Future.value(const FfmpegRun(false, ''));
      return session(runArgs,
          stop: cancel == null
              ? run.preempted
              : Future.any([run.preempted, cancel]));
    });
    if (cancel == null) return inLane;
    // The caller is let go at once, also while the run still waits for
    // its turn (behind an export, say).
    return Future.any([
      inLane,
      cancel.then((_) {
        cancelled = true;
        return const FfmpegRun(false, '');
      }),
    ]);
  }
}
