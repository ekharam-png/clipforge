// Work on long media files that the plain [MediaEngine] calls do badly:
//
// - a thumbnail STRIP of a whole video in one ffmpeg run (instead of one
//   run per thumbnail: 238 runs and 3 minutes for a 40-minute video cut
//   into 480 pieces), cached on disk per (file, size, date, interval);
// - silence detection with progress and cancel, limited to the part of
//   the file a clip uses.
//
// Both are optional extras of an engine ([ThumbnailStripEngine],
// [SilenceJobEngine]); callers check with `engine is ...` and fall back to
// the plain calls. Pure Dart (dart:io only), like the rest of lib/media.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/model/project.dart' show AudioChannel;
import 'ffmpeg_command.dart';
import 'media_api.dart';
import 'media_common.dart';
import 'silence_levels.dart';

export 'silence_levels.dart' show SilenceLevels, SilenceSensitivity;

// Thumbnail strips -------------------------------------------------------

/// Small frames of one video at a fixed source interval: frame `i` shows
/// (about) source time `i * intervalMs`.
class ThumbnailStrip {
  const ThumbnailStrip({required this.intervalMs, required this.frames});

  final int intervalMs;

  /// JPEG files, in time order. Never empty.
  final List<String> frames;

  /// The frame nearest to [sourceMs] (the first / last one outside).
  String frameAt(int sourceMs) {
    if (intervalMs <= 0) return frames.first;
    final i = (sourceMs / intervalMs).round();
    if (i <= 0) return frames.first;
    if (i >= frames.length) return frames.last;
    return frames[i];
  }
}

/// An engine that can make a [ThumbnailStrip] of a video in one go.
abstract interface class ThumbnailStripEngine {
  /// Makes (or finds in the cache) the strip of the video [path].
  /// [durationMs] is the file's length when the caller knows it (else it is
  /// probed). Throws [ExportException] when no frame can be read.
  Future<ThumbnailStrip> thumbnailStrip(String path,
      {int durationMs = 0, int height = kStripFrameHeight});
}

/// Height of the strip frames: the timeline blocks are 56 px high.
const int kStripFrameHeight = 96;

/// About this many frames per file at most, whatever its length.
const int kStripMaxFrames = 300;

/// Files longer than this are read keyframe by keyframe (fast: no frame in
/// between is decoded), shorter ones frame by frame (exact).
const int kStripKeyframesFromMs = 60000;

/// The source interval between two strip frames of a [durationMs] file:
/// 1 s for files up to 5 minutes, then longer so that a file never has
/// more than about [kStripMaxFrames] frames (10 s for 40 minutes).
int thumbnailStripIntervalMs(int durationMs) {
  if (durationMs <= 0) return 2000;
  final perFrame = (durationMs / kStripMaxFrames / 1000).ceil() * 1000;
  return perFrame < 1000 ? 1000 : perFrame;
}

/// ffmpeg arguments that write the strip of [path] as `<dir>/f00000.jpg`,
/// `f00001.jpg`, ... (one per [intervalMs] of source time, [height] px
/// high). With [keyframesOnly] only keyframes are decoded (each output
/// frame is then the keyframe nearest its time).
List<String> buildThumbnailStripCommand({
  required String path,
  required String outputDir,
  required int intervalMs,
  int height = kStripFrameHeight,
  bool keyframesOnly = false,
}) {
  final h = height < 2 ? 2 : height;
  final ms = intervalMs < 1 ? 1 : intervalMs;
  return [
    '-y',
    // Keyframes only: the other packets are dropped before they reach the
    // decoder, and the deblocking filter (invisible at this size) is
    // skipped. 40 minutes of 720p: about 2 s instead of 12.
    if (keyframesOnly) ...[
      '-skip_frame', 'nokey',
      '-discard', 'nokey',
      '-skip_loop_filter', 'all',
    ],
    '-i', path,
    '-map', '0:v:0',
    '-an', '-sn', '-dn',
    '-vf', "fps=fps=1000/$ms,scale=-2:'min($h,ih)'",
    '-q:v', '5',
    '-f', 'image2',
    '-start_number', '0',
    p.join(outputDir, 'f%05d.jpg'),
  ];
}

/// [ThumbnailStripEngine.thumbnailStrip] on top of an engine's [run] and
/// [probe]. Strips are kept in [cacheDir] (default: the system temp folder,
/// like single thumbnails), one folder per file version and interval.
Future<ThumbnailStrip> thumbnailStripWith(
  FfmpegRunner run,
  Future<MediaInfo> Function(String path) probe,
  String path, {
  int durationMs = 0,
  int height = kStripFrameHeight,
  Directory? cacheDir,
}) {
  final key = '$path|$durationMs|$height|${cacheDir?.path}';
  return _stripsRunning[key] ??= _makeStrip(run, probe, path,
          durationMs: durationMs, height: height, cacheDir: cacheDir)
      .whenComplete(() {
    // (A block: returning the removed future would make this one wait
    // for itself.)
    _stripsRunning.remove(key);
  });
}

final Map<String, Future<ThumbnailStrip>> _stripsRunning = {};

Future<ThumbnailStrip> _makeStrip(
  FfmpegRunner run,
  Future<MediaInfo> Function(String path) probe,
  String path, {
  required int durationMs,
  required int height,
  Directory? cacheDir,
}) async {
  var duration = durationMs;
  if (duration <= 0) {
    try {
      duration = (await probe(path)).durationMs;
    } catch (_) {}
  }
  final interval = thumbnailStripIntervalMs(duration);
  final root = cacheDir ??
      Directory(p.join(Directory.systemTemp.path, 'clipforge_thumbs'));
  var stamp = '';
  try {
    final st = await File(path).stat();
    stamp = '${st.size}_${st.modified.millisecondsSinceEpoch}';
  } catch (_) {}
  final dir = Directory(
      p.join(root.path, 'strip_${_hash('$path|$stamp|$interval|$height')}'));
  final manifest = File(p.join(dir.path, 'strip.json'));

  ThumbnailStrip? read() {
    try {
      final m = jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
      final count = m['count'] as int;
      final frames = [
        for (var i = 0; i < count; i++) p.join(dir.path, _frameName(i)),
      ];
      if (frames.isEmpty || !File(frames.last).existsSync()) return null;
      return ThumbnailStrip(intervalMs: m['intervalMs'] as int, frames: frames);
    } catch (_) {
      return null;
    }
  }

  if (await manifest.exists()) {
    final cached = read();
    if (cached != null) return cached;
  }

  await root.create(recursive: true);
  final work = await root.createTemp('strip_tmp_');
  try {
    Future<(FfmpegRun, int)> attempt(bool keyframesOnly) async {
      for (final f in work.listSync()) {
        await deleteQuietly(f);
      }
      final r = await run([
        '-loglevel', 'error',
        ...buildThumbnailStripCommand(
            path: path,
            outputDir: work.path,
            intervalMs: interval,
            height: height,
            keyframesOnly: keyframesOnly),
      ]);
      return (r, _countFrames(work));
    }

    final keyframes = duration > kStripKeyframesFromMs;
    var (r, count) = await attempt(keyframes);
    // Some files give no frame when only keyframes are decoded.
    if (count == 0 && keyframes) (r, count) = await attempt(false);
    if (count == 0) {
      throw ExportException('Cannot make thumbnails of $path',
          log: (LogTail()..add(r.log)).toString());
    }
    await File(p.join(work.path, 'strip.json')).writeAsString(
        jsonEncode({'intervalMs': interval, 'count': count}),
        flush: true);
    await deleteQuietly(dir);
    try {
      await work.rename(dir.path);
    } on FileSystemException {
      // Made at the same time by someone else: use theirs.
      await deleteQuietly(work);
    }
    final made = read();
    if (made == null) {
      throw ExportException('Cannot make thumbnails of $path');
    }
    return made;
  } finally {
    await deleteQuietly(work);
  }
}

String _frameName(int i) => 'f${i.toString().padLeft(5, '0')}.jpg';

/// Frames written without a gap from f00000 (ffmpeg's numbering).
int _countFrames(Directory dir) {
  var n = 0;
  while (File(p.join(dir.path, _frameName(n))).existsSync()) {
    n++;
  }
  return n;
}

String _hash(String s) {
  // Two 32-bit FNV-1a passes (different seeds); enough for cache keys.
  String pass(int seed) {
    var h = seed;
    for (final c in s.codeUnits) {
      h ^= c & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
      h ^= c >> 8;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  return pass(0x811C9DC5) + pass(0x01234567);
}

// Silence detection with progress -----------------------------------------

typedef SourceRange = ({int startMs, int endMs});

/// A running search for silent stretches. [progress] goes from 0 to 1;
/// [result] completes with source time ranges (as
/// [MediaEngine.detectSilence]) or throws [ExportException] (with
/// `cancelled` set after [cancel]).
abstract class SilenceJob {
  Stream<double> get progress;

  /// With the automatic threshold: the silences at it. With a given
  /// threshold: the silences `silencedetect` finds at it.
  Future<List<SourceRange>> get result;

  /// With the automatic threshold, once [result] is there: the measured
  /// levels, to work out the silences at another sensitivity without
  /// listening again. Null with a given threshold.
  SilenceLevels? get levels;
  Future<void> cancel();
}

/// An engine that can run [SilenceJob]s.
abstract interface class SilenceJobEngine {
  /// Like [MediaEngine.detectSilence], limited to source times
  /// [fromMs]..[toMs] of [path] ([toMs] 0: to the end), with progress
  /// against that stretch and a way to stop.
  SilenceJob startSilenceDetection(String path,
      {double? thresholdDb,
      int minSilenceMs = 700,
      int audioTrack = 0,
      AudioChannel channel = AudioChannel.both,
      int fromMs = 0,
      int toMs = 0});
}

/// Runs ffmpeg with [args], calling [onTimeMs] with the output position as
/// it goes. Completes with the whole log (stderr). [cancel] completes when
/// the caller wants the run stopped.
typedef StreamingFfmpegRunner = Future<FfmpegRun> Function(
    List<String> args, void Function(int timeMs) onTimeMs, Future<void> cancel);

/// [SilenceJobEngine.startSilenceDetection] on top of an engine's [run] and
/// [probe].
SilenceJob silenceJobWith(
  StreamingFfmpegRunner run,
  Future<MediaInfo> Function(String path) probe,
  String path, {
  double? thresholdDb,
  int minSilenceMs = 700,
  int audioTrack = 0,
  AudioChannel channel = AudioChannel.both,
  int fromMs = 0,
  int toMs = 0,
}) {
  final job = _SilenceJob();
  job._run(run, probe, path,
      thresholdDb: thresholdDb,
      minSilenceMs: minSilenceMs,
      audioTrack: audioTrack,
      channel: channel,
      fromMs: fromMs,
      toMs: toMs);
  return job;
}

/// [buildSilenceDetectCommand] for source times [fromMs]..[toMs] only
/// (silencedetect then reports times from [fromMs]).
List<String> buildSilenceDetectRangeCommand({
  required String path,
  double thresholdDb = -35,
  int minSilenceMs = 700,
  int audioTrack = 0,
  AudioChannel channel = AudioChannel.both,
  int fromMs = 0,
  int spanMs = 0,
}) {
  final whole = buildSilenceDetectCommand(
      path: path,
      thresholdDb: thresholdDb,
      minSilenceMs: minSilenceMs,
      audioTrack: audioTrack,
      channel: channel);
  return [
    if (fromMs > 0) ...['-ss', ffSeconds(fromMs)],
    ...whole.sublist(0, 2), // -i path
    if (spanMs > 0) ...['-t', ffSeconds(spanMs)],
    ...whole.sublist(2),
  ];
}

class _SilenceJob implements SilenceJob {
  final _progress = StreamController<double>.broadcast();
  final _result = Completer<List<SourceRange>>();
  final _cancel = Completer<void>();
  double _last = 0;

  _SilenceJob() {
    _result.future.ignore();
  }

  @override
  Stream<double> get progress => _progress.stream;

  @override
  Future<List<SourceRange>> get result => _result.future;

  @override
  SilenceLevels? levels;

  @override
  Future<void> cancel() async {
    if (!_cancel.isCompleted) _cancel.complete();
    try {
      await _result.future;
    } catch (_) {}
  }

  void _emit(double f) {
    if (_progress.isClosed || f <= _last) return;
    _last = f;
    _progress.add(f);
  }

  Future<void> _run(
    StreamingFfmpegRunner run,
    Future<MediaInfo> Function(String path) probe,
    String path, {
    required double? thresholdDb,
    required int minSilenceMs,
    required int audioTrack,
    required AudioChannel channel,
    required int fromMs,
    required int toMs,
  }) async {
    try {
      await Future<void>.delayed(Duration.zero);
      final info = await probe(path);
      if (_cancel.isCompleted) {
        throw ExportException('Stopped', cancelled: true);
      }
      if (!info.hasAudio) {
        _result.complete(const []);
        return;
      }
      // Same choice of track and side as MediaEngine.detectSilence.
      final track = audioTrack > 0 && audioTrack < info.audioStreams.length
          ? audioTrack
          : 0;
      final side =
          track < info.audioStreams.length && info.audioStreams[track] == 2
              ? channel
              : AudioChannel.both;
      final from = fromMs < 0 ? 0 : fromMs;
      final end = toMs > from
          ? (info.durationMs > 0 && toMs > info.durationMs
              ? info.durationMs
              : toMs)
          : info.durationMs;
      final span = end > from ? end - from : 0;
      _emit(0.0001);
      final r = await run(
        thresholdDb == null
            ? buildLevelScanCommand(
                path: path,
                audioTrack: track,
                channel: side,
                fromMs: from,
                spanMs: toMs > from ? span : 0)
            : buildSilenceDetectRangeCommand(
                path: path,
                thresholdDb: thresholdDb,
                minSilenceMs: minSilenceMs,
                audioTrack: track,
                channel: side,
                fromMs: from,
                spanMs: toMs > from ? span : 0),
        (t) {
          if (span > 0) _emit((t / span).clamp(0.0, 0.99));
        },
        _cancel.future,
      );
      if (_cancel.isCompleted) {
        throw ExportException('Stopped', cancelled: true);
      }
      if (!r.ok) {
        throw ExportException('Cannot analyse the sound of $path',
            log: (LogTail()..add(r.log)).toString());
      }
      if (thresholdDb == null) {
        final w = parseLevelLog(r.log);
        final l = levels =
            SilenceLevels(fromMs: from, spanMs: span, starts: w.starts, levels: w.levels);
        _emit(1);
        _result.complete(l.silences(
            thresholdDb: l.autoThresholdDb, minSilenceMs: minSilenceMs));
        return;
      }
      final found = parseSilenceLog(r.log, durationMs: span > 0 ? span : null);
      _emit(1);
      _result.complete([
        for (final s in found)
          (startMs: s.startMs + from, endMs: s.endMs + from),
      ]);
    } catch (e) {
      if (!_result.isCompleted) {
        _result.completeError(_cancel.isCompleted
            ? ExportException('Stopped', cancelled: true)
            : (e is ExportException
                ? e
                : ExportException('Cannot analyse the sound of $path',
                    log: '$e')));
      }
    } finally {
      await _progress.close();
    }
  }
}
