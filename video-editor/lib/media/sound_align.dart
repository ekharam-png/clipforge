// Pure Dart: "Line up by sound" (1.10). Finds where a separately recorded
// voice file (a microphone, a Zoom per-speaker recording) sits against the
// sound a video clip recorded itself.
//
// How:
//  1. Both sounds are decoded by ffmpeg to 8 kHz mono 16-bit raw files
//     ([buildAlignDecodeCommand]; source timing kept, like processed sound)
//     and read in chunks into an ENVELOPE ([SoundEnvelope]): one loudness
//     value every [kAlignHopMs] (5 ms), compressed (4th root of the
//     energy) so that loud and quiet recordings look alike, minus its own
//     one-second average, which leaves the rhythm of the syllables. A
//     40-minute file is 480 000 numbers (2 MB); the raw file is never in
//     memory as a whole.
//  2. COARSE: both envelopes are thinned to 20 ms and cross-correlated over
//     every possible shift at once (FFT). The best few peaks are kept.
//  3. FINE: for each of them, up to [kAlignWindows] windows of
//     [kAlignWindowMs] spread over the part where the two overlap (start
//     ... middle ... end) are correlated at 5 ms steps around the peak,
//     properly normalised (Pearson), and the sum over the windows is
//     interpolated to about a millisecond. The candidate with the best
//     score wins.
//  4. CONFIDENCE (0..1) from that score and from how far it stands above
//     the second-best candidate. Below [kAlignConfident] the caller should
//     not trust the offset.
//  5. DRIFT: every window also reports its own best offset; a straight
//     line through the trustworthy ones says how far the two recordings
//     walk apart over the overlap. It is REPORTED, not repaired: the
//     offset returned is the single constant one that fits best (repairing
//     would mean stretching the voice, which is not done).
//
// The offset's meaning everywhere in the app ([AudioClip.syncOffsetMs]):
//
//     time in the voice file = time in the video file + offset
//
// so a positive offset means the voice recording started EARLIER than the
// camera. Nothing here imports Flutter: the app and clipforge-mcp share it.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Sample rate the sounds are decoded to.
const int kAlignRate = 8000;

/// Step of the envelope.
const int kAlignHopMs = 5;

/// Step of the coarse search, in envelope values (4 = 20 ms).
const int kAlignCoarseStep = 4;

/// Length and number of the windows of the fine search.
const int kAlignWindowMs = 30000;
const int kAlignWindows = 7;

/// How far around a coarse peak the fine search looks.
const int kAlignFineRangeMs = 600;

/// From this confidence on the offset is used without asking.
const double kAlignConfident = 0.5;

/// Drift (over the whole overlap) from which the user is told.
const int kAlignDriftWarnMs = 80;

/// Arguments (no program name) that write the sound of [path] (audio
/// stream [audioTrack]) to [outputPath] as raw 16-bit mono at
/// [kAlignRate], sample n = source time n / rate.
List<String> buildAlignDecodeCommand({
  required String path,
  required String outputPath,
  int audioTrack = 0,
}) =>
    [
      '-i', path,
      '-vn', '-sn', '-dn',
      '-map', '0:a:${audioTrack < 0 ? 0 : audioTrack}',
      '-af',
      'aresample=$kAlignRate:async=1:first_pts=0,highpass=f=120',
      '-ac', '1',
      '-f', 's16le',
      '-y', outputPath,
    ];

/// The loudness rhythm of a sound: one value per [hopMs].
class SoundEnvelope {
  SoundEnvelope(this.values, {this.hopMs = kAlignHopMs});

  final Float32List values;
  final int hopMs;

  int get durationMs => values.length * hopMs;

  /// False for digital silence (nothing to compare).
  late final bool hasSound = () {
    for (final v in values) {
      if (v.abs() > 1e-7) return true;
    }
    return false;
  }();

  /// From loudness values (any positive scale) per hop: compresses and
  /// removes the slow average. Used by [fromPcm16] and by tests.
  factory SoundEnvelope.fromEnergy(List<double> energy,
      {int hopMs = kAlignHopMs}) {
    final n = energy.length;
    final f = Float32List(n);
    for (var i = 0; i < n; i++) {
      final e = energy[i];
      f[i] = e <= 0 ? 0 : math.sqrt(math.sqrt(e));
    }
    return SoundEnvelope(_removeSlow(f, 1000 ~/ hopMs), hopMs: hopMs);
  }

  /// From 16-bit little-endian mono samples at [rate].
  factory SoundEnvelope.fromPcm16(Uint8List bytes,
      {int rate = kAlignRate, int hopMs = kAlignHopMs}) {
    final b = EnvelopeBuilder(rate: rate, hopMs: hopMs)..add(bytes);
    return b.finish();
  }

  /// Reads a raw file written by [buildAlignDecodeCommand], in chunks.
  static Future<SoundEnvelope> fromRawFile(String path,
      {int rate = kAlignRate, int hopMs = kAlignHopMs}) async {
    final b = EnvelopeBuilder(rate: rate, hopMs: hopMs);
    await for (final chunk in File(path).openRead()) {
      b.add(chunk);
    }
    return b.finish();
  }
}

/// Builds a [SoundEnvelope] from 16-bit samples arriving in pieces.
class EnvelopeBuilder {
  EnvelopeBuilder({this.rate = kAlignRate, this.hopMs = kAlignHopMs})
      : _perHop = rate * hopMs ~/ 1000;

  final int rate;
  final int hopMs;
  final int _perHop;
  final List<double> _energy = [];
  double _sum = 0;
  int _count = 0;
  int? _low;

  void add(List<int> bytes) {
    var i = 0;
    final n = bytes.length;
    if (_low != null && n > 0) {
      _sample(_low! | (bytes[0] << 8));
      _low = null;
      i = 1;
    }
    for (; i + 1 < n; i += 2) {
      _sample(bytes[i] | (bytes[i + 1] << 8));
    }
    if (i < n) _low = bytes[i];
  }

  void _sample(int u) {
    final s = (u >= 0x8000 ? u - 0x10000 : u) / 32768.0;
    _sum += s * s;
    if (++_count == _perHop) {
      _energy.add(_sum / _perHop);
      _sum = 0;
      _count = 0;
    }
  }

  SoundEnvelope finish() => SoundEnvelope.fromEnergy(_energy, hopMs: hopMs);
}

/// [f] minus its moving average over [window] values (centred).
Float32List _removeSlow(Float32List f, int window) {
  final n = f.length;
  final out = Float32List(n);
  if (n == 0) return out;
  final half = window ~/ 2;
  final prefix = Float64List(n + 1);
  for (var i = 0; i < n; i++) {
    prefix[i + 1] = prefix[i] + f[i];
  }
  for (var i = 0; i < n; i++) {
    final a = i - half < 0 ? 0 : i - half;
    final b = i + half + 1 > n ? n : i + half + 1;
    out[i] = f[i] - (prefix[b] - prefix[a]) / (b - a);
  }
  return out;
}

/// What one window of the fine search found.
class AlignWindow {
  const AlignWindow(
      {required this.atMs, required this.offsetMs, required this.score});

  /// Middle of the window, as a time in the VIDEO's sound.
  final int atMs;

  /// The offset that fits this window best.
  final double offsetMs;

  /// Correlation there (-1..1).
  final double score;

  Map<String, dynamic> toJson() => {
        'at_ms': atMs,
        'offset_ms': offsetMs.round(),
        'score': double.parse(score.toStringAsFixed(3)),
      };
}

/// The answer of [alignEnvelopes].
class AlignResult {
  const AlignResult({
    required this.offsetMs,
    required this.confidence,
    required this.score,
    required this.peakRatio,
    required this.driftMs,
    required this.overlapMs,
    this.windows = const [],
    this.reason,
  });

  /// Nothing to compare.
  const AlignResult.none(String this.reason)
      : offsetMs = 0,
        confidence = 0,
        score = 0,
        peakRatio = 1,
        driftMs = 0,
        overlapMs = 0,
        windows = const [];

  /// time in the voice file = time in the video file + [offsetMs].
  final int offsetMs;

  /// 0..1; trust the offset from [kAlignConfident].
  final double confidence;

  /// Correlation of the two envelopes at the offset (-1..1).
  final double score;

  /// Best score / second-best candidate's score (1 = no better than the
  /// runner-up).
  final double peakRatio;

  /// How far the two recordings walk apart from the start to the end of
  /// their overlap (ms; positive: the offset grows, the voice gets later
  /// against the picture).
  /// 0 when it cannot be told.
  final int driftMs;

  /// How much of the two sounds overlaps at [offsetMs].
  final int overlapMs;
  final List<AlignWindow> windows;

  /// Why nothing was found (no sound, too short), else null.
  final String? reason;

  bool get matched => confidence >= kAlignConfident;
  bool get drifts => matched && driftMs.abs() >= kAlignDriftWarnMs;

  Map<String, dynamic> toJson() => {
        'offset_ms': offsetMs,
        'confidence': double.parse(confidence.toStringAsFixed(2)),
        'matched': matched,
        'score': double.parse(score.toStringAsFixed(3)),
        'drift_ms': driftMs,
        'overlap_ms': overlapMs,
        if (reason != null) 'reason': reason,
      };

  @override
  String toString() => 'AlignResult(offset $offsetMs ms, confidence '
      '${confidence.toStringAsFixed(2)}, score ${score.toStringAsFixed(3)}, '
      'ratio ${peakRatio.toStringAsFixed(2)}, drift $driftMs ms)';
}

/// Finds the offset of [voice] against [video] (the camera's own sound):
/// see the top of this file. [minOverlapMs]: shifts that leave less in
/// common are not considered (default: 10 s, or half the shorter sound).
AlignResult alignEnvelopes(SoundEnvelope video, SoundEnvelope voice,
    {int? minOverlapMs}) {
  assert(video.hopMs == voice.hopMs);
  final hop = video.hopMs;
  if (!video.hasSound) return const AlignResult.none('The video has no sound.');
  if (!voice.hasSound) return const AlignResult.none('The file is silent.');
  final shorter = math.min(video.durationMs, voice.durationMs);
  if (shorter < 2000) {
    return const AlignResult.none('Too short to compare.');
  }
  final minOverlap =
      minOverlapMs ?? math.min(10000, shorter ~/ 2);

  // Coarse ---------------------------------------------------------------
  final step = kAlignCoarseStep;
  final a = _thin(video.values, step);
  final b = _thin(voice.values, step);
  final coarseHopMs = hop * step;
  final minOverlapC = math.max(8, minOverlap ~/ coarseHopMs);
  final candidates = _coarsePeaks(a, b, minOverlapC, 6);
  if (candidates.isEmpty) {
    return const AlignResult.none('Too short to compare.');
  }

  // Fine -----------------------------------------------------------------
  // The candidates are compared by how sure their score is: a score over
  // a long stretch counts for more than the same score over a short one.
  _Fine? best;
  var second = 0.0;
  for (final lagC in candidates) {
    final f = _fine(video, voice, lagC * step);
    if (f == null) continue;
    if (best == null || f.sureness > best.sureness) {
      if (best != null && (best.offsetHops - f.offsetHops).abs() * hop > 300) {
        second = math.max(second, best.sureness);
      }
      best = f;
    } else if ((best.offsetHops - f.offsetHops).abs() * hop > 300) {
      second = math.max(second, f.sureness);
    }
  }
  if (best == null) return const AlignResult.none('Too short to compare.');

  final score = best.score;
  final ratio = second <= 0.02 ? 50.0 : best.sureness / second;
  // Score: a speaker's own microphone against a camera that hears the
  // whole room gives 0.3..0.9. Unrelated sounds reach about
  // 1.1 / sqrt(seconds compared) by chance (0.2 for one 30 s window), so
  // the bar depends on how much was compared.
  final bar = 0.08 + 0.9 / math.sqrt(math.max(1.0, best.comparedMs / 1000));
  final byScore = ((score - bar) / 0.17).clamp(0.0, 1.0);
  final byRatio = ((ratio - 1.15) / 0.6).clamp(0.0, 1.0);
  final confidence = (byScore * byRatio).toDouble();

  // Drift ------------------------------------------------------------------
  final good = [
    for (final w in best.windows)
      if (w.score >= math.max(0.2, score * 0.5)) w,
  ];
  var drift = 0.0;
  if (good.length >= 3) {
    final t0 = good.first.atMs.toDouble();
    final t1 = good.last.atMs.toDouble();
    if (t1 - t0 >= 60000) {
      // Least squares line offset = k * at + c.
      var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
      for (final w in good) {
        sx += w.atMs;
        sy += w.offsetMs;
        sxx += w.atMs.toDouble() * w.atMs;
        sxy += w.atMs * w.offsetMs;
      }
      final n = good.length;
      final den = n * sxx - sx * sx;
      if (den != 0) {
        final k = (n * sxy - sx * sy) / den;
        drift = k * best.overlapMs;
      }
    }
  }
  return AlignResult(
    offsetMs: (best.offsetHops * hop).round(),
    confidence: confidence,
    score: score,
    peakRatio: ratio,
    driftMs: drift.abs() < 15 ? 0 : drift.round(),
    overlapMs: best.overlapMs,
    windows: best.windows,
  );
}

Float64List _thin(Float32List f, int step) {
  final n = f.length ~/ step;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    var s = 0.0;
    for (var k = 0; k < step; k++) {
      s += f[i * step + k];
    }
    out[i] = s / step;
  }
  return out;
}

/// The lags (voice index = video index + lag) of the highest peaks of the
/// cross-correlation of [a] (video) and [b] (voice), at least 15 values
/// apart, each leaving at least [minOverlap] values in common.
List<int> _coarsePeaks(Float64List a, Float64List b, int minOverlap, int count) {
  final na = a.length, nb = b.length;
  if (na < minOverlap || nb < minOverlap) return const [];
  var size = 1;
  while (size < na + nb) {
    size <<= 1;
  }
  final ar = Float64List(size), ai = Float64List(size);
  final br = Float64List(size), bi = Float64List(size);
  ar.setRange(0, na, a);
  br.setRange(0, nb, b);
  _fft(ar, ai, false);
  _fft(br, bi, false);
  // c[l] = sum_i a[i] * b[i + l]  <=>  conj(A) * B.
  for (var i = 0; i < size; i++) {
    final re = ar[i] * br[i] + ai[i] * bi[i];
    final im = ar[i] * bi[i] - ai[i] * br[i];
    ar[i] = re;
    ai[i] = im;
  }
  _fft(ar, ai, true);
  // Lags from -(na - minOverlap) to nb - minOverlap.
  final lo = -(na - minOverlap), hi = nb - minOverlap;
  final lags = <int>[];
  final vals = <double>[];
  for (var l = lo; l <= hi; l++) {
    final v = ar[l < 0 ? l + size : l];
    final overlap = math.min(na, nb - l) - math.max(0, -l);
    if (overlap < minOverlap) continue;
    // Favour neither long nor short overlaps too much.
    lags.add(l);
    vals.add(v / math.sqrt(overlap.toDouble()));
  }
  final order = List<int>.generate(lags.length, (i) => i)
    ..sort((x, y) => vals[y].compareTo(vals[x]));
  final out = <int>[];
  for (final i in order) {
    if (vals[i] <= 0) break;
    final l = lags[i];
    if (out.any((o) => (o - l).abs() < 15)) continue;
    out.add(l);
    if (out.length >= count) break;
  }
  return out;
}

class _Fine {
  _Fine(this.offsetHops, this.score, this.windows, this.overlapMs,
      this.comparedMs);
  final double offsetHops;
  final double score;
  final List<AlignWindow> windows;
  final int overlapMs;

  /// Total length of the windows that were compared.
  final int comparedMs;

  /// The score in units of what chance would give.
  double get sureness => score * math.sqrt(comparedMs / 1000);
}

/// Fine search around [lag] (in envelope values; voice = video + lag).
_Fine? _fine(SoundEnvelope video, SoundEnvelope voice, int lag) {
  final hop = video.hopMs;
  final v = video.values, w = voice.values;
  final range = kAlignFineRangeMs ~/ hop;
  // Overlap in video indices at this lag, leaving room for the range.
  final from = math.max(0, -lag) + range;
  final to = math.min(v.length, w.length - lag) - range;
  final overlap = to - from;
  if (overlap < 400 ~/ hop * 5) return null;
  final win = math.min(kAlignWindowMs ~/ hop, overlap);
  final count = math.max(1, math.min(kAlignWindows, overlap ~/ win));
  final sums = Float64List(2 * range + 1);
  var weight = 0.0;
  var compared = 0;
  final windows = <AlignWindow>[];
  // Sum of squares of the voice up to each index, to find where the
  // speaker talks.
  final sq = Float64List(overlap + 1);
  for (var i = 0; i < overlap; i++) {
    final x = w[from + lag + i];
    sq[i + 1] = sq[i] + x * x;
  }
  final part = overlap ~/ count;
  final slide = math.max(1, 5000 ~/ hop);
  for (var k = 0; k < count; k++) {
    // In each part of the overlap: the window with the most voice in it.
    final lo = part * k;
    final hi = math.max(lo, (k == count - 1 ? overlap : lo + part) - win);
    var start = lo;
    var most = -1.0;
    for (var s = lo; s <= hi; s += slide) {
      final e = sq[s + win] - sq[s];
      if (e > most) {
        most = e;
        start = s;
      }
    }
    start += from;
    // The voice part is fixed; the video part slides.
    final j0 = start + lag;
    var mw = 0.0;
    for (var i = 0; i < win; i++) {
      mw += w[j0 + i];
    }
    mw /= win;
    var vw = 0.0;
    for (var i = 0; i < win; i++) {
      final d = w[j0 + i] - mw;
      vw += d * d;
    }
    if (vw <= 1e-12) continue; // the speaker is silent here
    var bestR = -2.0;
    var bestD = 0;
    final rs = Float64List(2 * range + 1);
    for (var d = -range; d <= range; d++) {
      // voice index j <-> video index j - (lag + d)
      final i0 = start - d;
      var mv = 0.0;
      for (var i = 0; i < win; i++) {
        mv += v[i0 + i];
      }
      mv /= win;
      var num = 0.0, vv = 0.0;
      for (var i = 0; i < win; i++) {
        final x = v[i0 + i] - mv;
        num += x * (w[j0 + i] - mw);
        vv += x * x;
      }
      final r = vv <= 1e-12 ? 0.0 : num / math.sqrt(vv * vw);
      rs[d + range] = r;
      if (r > bestR) {
        bestR = r;
        bestD = d;
      }
    }
    // Windows where the speaker actually talks count more.
    final wgt = math.sqrt(vw);
    for (var i = 0; i < rs.length; i++) {
      sums[i] += rs[i] * wgt;
    }
    weight += wgt;
    compared += win;
    windows.add(AlignWindow(
      atMs: (start + win ~/ 2) * hop,
      offsetMs: (lag + _peak(rs, bestD + range) - range) * hop,
      score: bestR,
    ));
  }
  if (weight <= 0) return null;
  var bi = 0;
  for (var i = 1; i < sums.length; i++) {
    if (sums[i] > sums[bi]) bi = i;
  }
  final at = _peak(sums, bi);
  return _Fine(lag + at - range, sums[bi] / weight, windows,
      (overlap + 2 * range) * hop, compared * hop);
}

/// Position of the peak near index [i] of [r], between samples (parabola
/// through the three values around it).
double _peak(Float64List r, int i) {
  if (i <= 0 || i >= r.length - 1) return i.toDouble();
  final a = r[i - 1], b = r[i], c = r[i + 1];
  final den = a - 2 * b + c;
  if (den >= 0) return i.toDouble();
  return i + 0.5 * (a - c) / den;
}

/// In-place radix-2 FFT ([re].length a power of two).
void _fft(Float64List re, Float64List im, bool inverse) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = 2 * math.pi / len * (inverse ? -1 : 1);
    final wr = math.cos(ang), wi = math.sin(ang);
    final half = len >> 1;
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < half; k++) {
        final ur = re[i + k], ui = im[i + k];
        final xr = re[i + k + half] * cr - im[i + k + half] * ci;
        final xi = re[i + k + half] * ci + im[i + k + half] * cr;
        re[i + k] = ur + xr;
        im[i + k] = ui + xi;
        re[i + k + half] = ur - xr;
        im[i + k + half] = ui - xi;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
  if (inverse) {
    for (var i = 0; i < n; i++) {
      re[i] /= n;
      im[i] /= n;
    }
  }
}

// File names --------------------------------------------------------------

/// What a sound file probably is, from its name and length.
enum SoundRole { voice, music, effect }

final RegExp _zoomAudio = RegExp(r'^audio([A-Za-z][A-Za-z0-9_ .-]*?)(\d{6,})$');
final RegExp _voiceWord = RegExp(
    r'(^|[^a-z])(voice|voiceover|mic|microphone|audio|podcast|zoom|interview|'
    r'speech|narration|recording)([^a-z]|$)',
    caseSensitive: false);

/// The guess the "What is this sound?" question starts with: Voice when
/// the file name says so (voice, mic, audio, podcast, zoom, or Zoom's
/// `audio<Name><digits>`), or when its length is within 10 % of a video
/// clip's file ([videoDurationsMs]); else Music.
SoundRole guessSoundRole(String fileName,
    {int durationMs = 0, Iterable<int> videoDurationsMs = const []}) {
  final stem = _stem(fileName);
  if (_zoomAudio.hasMatch(stem) || _voiceWord.hasMatch(stem)) {
    return SoundRole.voice;
  }
  if (durationMs > 0) {
    for (final v in videoDurationsMs) {
      if (v >= 5000 && (durationMs - v).abs() <= v * 0.10) {
        return SoundRole.voice;
      }
    }
  }
  return SoundRole.music;
}

/// The speaker's name when the file name gives one: Zoom's
/// `audioSamTaylor21406335665.m4a` -> "Sam Taylor" (the digit right
/// after the name is Zoom's participant counter), `mic - Anna.wav` ->
/// "Anna". Null when it does not.
String? speakerNameFromFile(String fileName) {
  final stem = _stem(fileName);
  final zoom = _zoomAudio.firstMatch(stem);
  String? raw;
  if (zoom != null) {
    raw = zoom.group(1);
  } else {
    final m = RegExp(
            r'^(?:voice|mic|microphone|audio|speaker)\s*[-_ ]\s*([A-Za-z][A-Za-z .-]{1,38})$',
            caseSensitive: false)
        .firstMatch(stem);
    raw = m?.group(1);
  }
  if (raw == null) return null;
  var name = raw
      .replaceAll(RegExp(r'[_.-]+'), ' ')
      // SamTaylor -> Sam Taylor
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'\d+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (name.length < 2) return null;
  if (name.length > 40) name = name.substring(0, 40).trim();
  return name;
}

String _stem(String fileName) {
  var name = fileName.replaceAll('\\', '/');
  name = name.substring(name.lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
