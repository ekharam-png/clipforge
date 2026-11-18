// Pure Dart: "Remove silences" with a threshold that adapts to the
// recording.
//
// Why: `silencedetect` with a fixed -35 dB found nothing on noisy phone
// recordings (owner's first test). It compares every SAMPLE with the
// threshold, and the peaks of steady background noise at -35 dB RMS reach
// about -25 dB, so a "silence" never lasted long enough.
//
// How: one ffmpeg pass measures the loudness (RMS) of short windows
// ([kLevelWindowMs]) over the clip's part of the file
// ([buildLevelScanCommand], `astats` per window printed by `ametadata`).
// From those levels ([analyseLevels]):
//
//  * noise floor = the 10th percentile of the window levels (the quiet
//    between words and sentences), loud = the 90th percentile (speech);
//  * threshold = floor + margin, margin = 35 % of (loud - floor), at least
//    4 dB and at most 12 dB, the threshold kept within -70..-12 dB; when
//    loud and floor are less than 6 dB apart there is nothing to tell
//    apart and nothing counts as silence;
//  * a silence is a stretch of windows below the threshold lasting at
//    least the minimum length ([silencesFromLevels]).
//
// So a clean recording (floor -45, speech -15) gets -35 dB, the old fixed
// value, and a noisy one (floor -30, speech -15) gets about -25 dB.
// [SilenceSensitivity] moves the threshold by [kSensitivityStepDb] for more
// or fewer cuts, without listening again.
//
// Everything used exists with the same spelling in FFmpeg 6.1 and 8.x
// (astats `measure_overall` since 4.4).

import '../core/model/project.dart' show AudioChannel;

/// Length of one measured window.
const int kLevelWindowMs = 40;

/// What "More cuts" / "Fewer cuts" add to / take from the automatic
/// threshold.
const double kSensitivityStepDb = 4;

/// Level given to a window of digital silence (`-inf` in the log).
const double kSilentWindowDb = -120;

/// How many quiet parts count as silence.
enum SilenceSensitivity {
  /// Only clearly quiet parts: threshold lower by [kSensitivityStepDb].
  fewerCuts,

  /// The automatic threshold.
  auto,

  /// Also somewhat louder pauses: threshold higher by [kSensitivityStepDb].
  moreCuts;

  double get offsetDb => switch (this) {
        SilenceSensitivity.fewerCuts => -kSensitivityStepDb,
        SilenceSensitivity.auto => 0,
        SilenceSensitivity.moreCuts => kSensitivityStepDb,
      };
}

/// The window levels of a stretch of sound and what they say.
class SilenceLevels {
  SilenceLevels._(this.fromMs, this.spanMs, this.windowMs, this.starts,
      this.levels, this.noiseFloorDb, this.loudDb);

  /// Builds the analysis from window start times (ms, relative to the
  /// stretch) and levels (dB).
  factory SilenceLevels(
      {required int fromMs,
      int spanMs = 0,
      int windowMs = kLevelWindowMs,
      required List<int> starts,
      required List<double> levels}) {
    final sorted = [...levels]..sort();
    double pct(double p) => sorted.isEmpty
        ? kSilentWindowDb
        : sorted[((sorted.length - 1) * p).round()];
    return SilenceLevels._(fromMs, spanMs, windowMs, List.unmodifiable(starts),
        List.unmodifiable(levels), pct(0.10), pct(0.90));
  }

  /// Source time the stretch starts at.
  final int fromMs;

  /// Its length (0: unknown); silences end at most there.
  final int spanMs;
  final int windowMs;

  /// Start of each window, ms from [fromMs].
  final List<int> starts;

  /// RMS level of each window, dB (digital silence: [kSilentWindowDb]).
  final List<double> levels;

  /// 10th percentile of the levels: the background between words.
  final double noiseFloorDb;

  /// 90th percentile: speech.
  final double loudDb;

  /// False when quiet and loud parts are too close to tell apart (a steady
  /// tone, constant music, noise only): then nothing counts as silence.
  bool get hasQuietParts => loudDb - noiseFloorDb >= 6;

  /// The automatic threshold (see the top of this file).
  double get autoThresholdDb {
    final span = loudDb - noiseFloorDb;
    final margin = (span * 0.35).clamp(4.0, 12.0);
    return (noiseFloorDb + margin).clamp(-70.0, -12.0).toDouble();
  }

  /// The threshold for [sensitivity].
  double thresholdFor(SilenceSensitivity sensitivity) =>
      (autoThresholdDb + sensitivity.offsetDb).clamp(-75.0, -6.0).toDouble();

  /// The silences at [thresholdDb] (source times), at least
  /// [minSilenceMs] long. None when there are no quiet parts.
  List<({int startMs, int endMs})> silences(
      {required double thresholdDb, int minSilenceMs = 700}) {
    if (!hasQuietParts) return const [];
    return silencesFromLevels(this,
        thresholdDb: thresholdDb, minSilenceMs: minSilenceMs);
  }
}

/// Stretches of windows of [l] below [thresholdDb] lasting at least
/// [minSilenceMs], as source times.
List<({int startMs, int endMs})> silencesFromLevels(SilenceLevels l,
    {required double thresholdDb, int minSilenceMs = 700}) {
  final out = <({int startMs, int endMs})>[];
  int? start;
  var end = 0;
  void close() {
    final s = start;
    if (l.spanMs > 0 && end > l.spanMs) end = l.spanMs;
    if (s != null && end - s >= minSilenceMs) {
      out.add((startMs: l.fromMs + s, endMs: l.fromMs + end));
    }
    start = null;
  }

  for (var i = 0; i < l.levels.length; i++) {
    final t = l.starts[i];
    if (l.levels[i] < thresholdDb) {
      // A gap in the reports (should not happen) ends a silence.
      if (start != null && t - end > l.windowMs) close();
      start ??= t;
      end = t + l.windowMs;
    } else {
      close();
    }
  }
  close();
  return out;
}

/// Arguments (no program name) that print the RMS level of every
/// [kLevelWindowMs] window of audio stream [audioTrack] of [path] to the
/// log (level info), for source times [fromMs]..[fromMs] + [spanMs]
/// ([spanMs] 0: to the end). See [parseLevelLog].
List<String> buildLevelScanCommand({
  required String path,
  int audioTrack = 0,
  AudioChannel channel = AudioChannel.both,
  int fromMs = 0,
  int spanMs = 0,
}) {
  const rate = 48000;
  final n = rate * kLevelWindowMs ~/ 1000;
  String sec(int ms) => (ms / 1000).toStringAsFixed(3);
  return [
    if (fromMs > 0) ...['-ss', sec(fromMs)],
    '-i', path,
    if (spanMs > 0) ...['-t', sec(spanMs)],
    '-map', '0:a:${audioTrack < 0 ? 0 : audioTrack}',
    '-af',
    '${switch (channel) {
      AudioChannel.both => '',
      AudioChannel.left => 'pan=mono|c0=c0,',
      AudioChannel.right => 'pan=mono|c0=c1,',
    }}aresample=$rate,asetnsamples=n=$n:p=0,'
        'astats=metadata=1:reset=1:measure_perchannel=none'
        ':measure_overall=RMS_level,'
        'ametadata=mode=print:key=lavfi.astats.Overall.RMS_level',
    '-f', 'null',
    '-',
  ];
}

final RegExp _ptsRe = RegExp(r'pts_time:\s*(-?[\d.]+(?:[eE][-+]?\d+)?)');
final RegExp _rmsRe =
    RegExp(r'lavfi\.astats\.Overall\.RMS_level=\s*(-?inf|-?[\d.]+(?:[eE][-+]?\d+)?|nan)');

/// The windows in a log of [buildLevelScanCommand]: start times (ms) and
/// levels (dB), in order.
({List<int> starts, List<double> levels}) parseLevelLog(String log) {
  final starts = <int>[];
  final levels = <double>[];
  int? pending;
  var index = 0;
  for (final line in log.split('\n')) {
    final pts = _ptsRe.firstMatch(line);
    if (pts != null) {
      final t = double.tryParse(pts.group(1)!);
      pending = t == null ? index * kLevelWindowMs : (t * 1000).round();
      continue;
    }
    final m = _rmsRe.firstMatch(line);
    if (m == null) continue;
    final raw = m.group(1)!;
    var db = double.tryParse(raw) ?? kSilentWindowDb;
    if (db.isNaN || db < kSilentWindowDb) db = kSilentWindowDb;
    starts.add(pending ?? index * kLevelWindowMs);
    levels.add(db);
    pending = null;
    index++;
  }
  return (starts: starts, levels: levels);
}
