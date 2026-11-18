// Runtime side of the hardware video encoders: finds out once which one
// works on this machine, and runs an export with it, falling back to the
// processor (libx264) when it fails.
//
// Pure Dart (dart:io, dart:ffi for the processor type): used by both
// engines, so also by the Claude control server.

import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'media_api.dart';
import 'media_common.dart';
import 'video_encoder.dart';

/// The [EncoderPlatform] this program runs on.
EncoderPlatform currentEncoderPlatform() {
  if (Platform.isMacOS) {
    // An Intel build running under Rosetta reports x64, and its FFmpeg is
    // the x86_64 slice, which refuses constant quality: both agree.
    return Abi.current() == Abi.macosArm64
        ? EncoderPlatform.macosAppleSilicon
        : EncoderPlatform.macosIntel;
  }
  if (Platform.isWindows) return EncoderPlatform.windows;
  if (Platform.isAndroid) return EncoderPlatform.android;
  if (Platform.isLinux) return EncoderPlatform.linux;
  return EncoderPlatform.other;
}

/// Which hardware encoder works with one FFmpeg on this machine, found out
/// once and remembered for the run of the program ([shared]).
///
/// Finding out: the encoder list of FFmpeg (`-encoders`) is narrowed to the
/// candidates for [platform], then each is tried with a tiny test encode
/// ([encoderTestArgs]) until one succeeds. A listed encoder often does not
/// work (no such card, old driver), so the list alone proves nothing.
class HardwareEncoders {
  HardwareEncoders({
    required this.platform,
    required this.listEncoders,
    required this.run,
    this.testTimeout = const Duration(seconds: 20),
  });

  /// One instance per FFmpeg ([key]) for the whole run of the program, so
  /// that the test encodes happen once and a failure is remembered.
  factory HardwareEncoders.shared(String key, HardwareEncoders Function() create) =>
      _shared[key] ??= create();
  static final Map<String, HardwareEncoders> _shared = {};

  final EncoderPlatform platform;

  /// The output of `ffmpeg -encoders` (null or empty when it cannot be had:
  /// every candidate is then tried).
  final Future<String?> Function() listEncoders;

  /// Runs ffmpeg (the test encodes).
  final FfmpegRunner run;
  final Duration testTimeout;

  Future<VideoEncoder?>? _found;
  final Set<VideoEncoder> _failed = {};

  /// The hardware encoder that passed the test, or null.
  Future<VideoEncoder?> detect() => _found ??= _detect();

  Future<VideoEncoder?> _detect() async {
    if (hardwareEncoderCandidates(platform).isEmpty) return null;
    Set<String>? available;
    try {
      final listing = await listEncoders();
      final names = listing == null ? <String>{} : parseEncoderList(listing);
      // A list without even libx264 was not captured properly.
      if (names.contains('libx264')) available = names;
    } catch (_) {}
    for (final e in encoderCandidates(platform: platform, available: available)) {
      if (!e.hardware) break;
      if (await _passes(e)) return e;
    }
    return null;
  }

  Future<bool> _passes(VideoEncoder e) async {
    try {
      final r = await run(encoderTestArgs(e, platform)).timeout(testTimeout);
      return r.ok;
    } catch (_) {
      return false;
    }
  }

  /// True when exports can use the graphics card now.
  Future<bool> available() async => await current() != null;

  /// The hardware encoder exports use now: the one that passed the test,
  /// unless it failed in a real export since. Null: the processor.
  Future<VideoEncoder?> current() async {
    final e = await detect();
    return e == null || _failed.contains(e) ? null : e;
  }

  /// The encoder for an export: the working hardware one when [hardware]
  /// is wanted and it has not failed in this run, otherwise libx264.
  Future<VideoEncoder> choose({required bool hardware}) async {
    if (!hardware) return VideoEncoder.libx264;
    VideoEncoder? e;
    try {
      e = await detect();
    } catch (_) {}
    return e == null || _failed.contains(e) ? VideoEncoder.libx264 : e;
  }

  /// [e] failed in a real export (and the processor then succeeded): not
  /// used again in this run of the program.
  void markFailed(VideoEncoder e) {
    if (e.hardware) _failed.add(e);
  }
}

/// Starts the engine's own export job with a given encoder.
typedef EncoderJobStarter = ExportJob Function(VideoEncoder encoder);

/// An export that uses the hardware encoder when wanted and possible, and
/// redoes the export once with libx264 when the hardware attempt fails
/// (ffmpeg reports an error at the start or later, or the file it wrote
/// does not hold the whole video). The failed attempt's file is deleted by
/// the engine's job, so no broken file is left. When the processor attempt
/// then succeeds the hardware encoder is not used again in this run.
class EncoderFallbackJob implements ExportJob {
  EncoderFallbackJob({
    required this.encoders,
    required this.options,
    required this.start,
    this.verify,
  }) {
    _done.future.ignore();
    _run();
  }

  final HardwareEncoders encoders;
  final ExportOptions options;
  final EncoderJobStarter start;

  /// Checks a finished hardware export (e.g. probes it); false or an error
  /// counts as a failed attempt. The processor's output is not checked
  /// here (the engines already check that it exists and is not empty).
  final Future<bool> Function(String path)? verify;

  final _progress = StreamController<ExportProgress>.broadcast();
  final _done = Completer<String>();
  ExportJob? _current;
  bool _cancelled = false;
  VideoEncoder? _used;

  @override
  Stream<ExportProgress> get progress => _progress.stream;

  @override
  Future<String> get done => _done.future;

  @override
  VideoEncoder? get videoEncoder => _used;

  List<String> _warnings = const [];

  @override
  List<String> get warnings => _warnings;

  Future<void> _run() async {
    // Let the caller attach listeners first.
    await Future<void>.delayed(Duration.zero);
    try {
      // Sound only: no picture to encode, nothing to check for one.
      final audioOnly = options.format.audioOnly;
      final first = await encoders.choose(
          hardware: options.useHardwareEncoder && !audioOnly);
      if (_cancelled) throw ExportException('Export cancelled', cancelled: true);
      try {
        final path = await _attempt(first);
        if (!audioOnly &&
            first.hardware &&
            verify != null &&
            !await _verified(path)) {
          await deleteQuietly(File(path));
          throw ExportException(
              'The graphics card made an incomplete video file',
              log: 'Output check failed for ${first.ffmpegName}');
        }
        _finish(path, first);
      } on ExportException catch (e) {
        if (!first.hardware ||
            _cancelled ||
            e.cancelled ||
            e.log == null || // not an ffmpeg failure (missing file, ...)
            e.missingPaths.isNotEmpty) {
          rethrow;
        }
        final path = await _attempt(VideoEncoder.libx264);
        encoders.markFailed(first);
        _finish(path, VideoEncoder.libx264);
      }
    } catch (e, st) {
      if (!_done.isCompleted) {
        _done.completeError(_cancelled
            ? ExportException('Export cancelled', cancelled: true)
            : e is ExportException
                ? e
                : ExportException('Export failed: $e', log: '$st'));
      }
    } finally {
      await _progress.close();
    }
  }

  Future<bool> _verified(String path) async {
    try {
      return await verify!(path);
    } catch (_) {
      return false;
    }
  }

  void _finish(String path, VideoEncoder used) {
    _used = used;
    if (!_done.isCompleted) _done.complete(path);
  }

  Future<String> _attempt(VideoEncoder encoder) async {
    final job = start(encoder);
    _current = job;
    // Every attempt builds the same sound, so the last one tells.
    void takeWarnings() => _warnings = job.warnings;
    final sub = job.progress.listen((p) {
      if (!_progress.isClosed) _progress.add(p);
    }, onError: (Object _) {});
    if (_cancelled) await job.cancel();
    try {
      return await job.done;
    } finally {
      takeWarnings();
      await sub.cancel();
      _current = null;
    }
  }

  @override
  Future<void> cancel() async {
    if (_done.isCompleted) return;
    _cancelled = true;
    await _current?.cancel();
    try {
      await _done.future;
    } catch (_) {}
  }
}

/// A check for [EncoderFallbackJob.verify]: the file at the path has a
/// picture and lasts about [expectedMs] (within 5 %, at least 1 s).
Future<bool> Function(String path) outputCheck(
        Future<MediaInfo> Function(String path) probe, int expectedMs) =>
    (path) async {
      final info = await probe(path);
      if (!info.hasVideo || info.width <= 0) return false;
      if (expectedMs <= 0) return true;
      final slack = expectedMs * 0.05 < 1000 ? 1000 : expectedMs * 0.05;
      return info.durationMs >= expectedMs - slack;
    };
