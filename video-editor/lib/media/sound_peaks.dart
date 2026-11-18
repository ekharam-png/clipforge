// Pure Dart (dart:io only for the cache file): the "sound picture" of a
// media file (1.13). One pass over the low-rate decode that "Line up by
// sound" already uses ([buildAlignDecodeCommand]: 8 kHz mono) gives, per
// [kPeakHopMs]:
//
//  * the PEAK of the samples (drawn as the waveform on the timeline), and
//  * the RMS LEVEL in dB (who is speaking: [speechStretches]).
//
// Two bytes per hop: 40 minutes are 240 KB, in memory and on disk
// (`<app media>/peaks/pk_<fingerprint>_a<track>.cfpk`, see
// sound_peaks_job.dart).
//
// Who is speaking uses the rule of "Remove silences"
// (silence_levels.dart): noise floor = 10th percentile of the levels,
// threshold = floor + 35 % of (loud - floor), at least 4 and at most
// 12 dB. Differences: digital silence (a muted Zoom track) is left out of
// the percentiles, and "loud" is the 95th percentile, so someone who
// talks for a tenth of the time is still found.
//
// Several microphones recorded together (one linked voice file per
// speaker) hear each other. [groupSpeechStretches] compares them hop by
// hop: where two are active at once, the one that is clearly louder
// RELATIVE TO ITS OWN SPEECH LEVEL wins and the other is taken as bleed -
// unless that one is loud by its own measure too (both talk: overlap).
// One that is far louder in plain numbers ([kBleedFarDb]) always wins.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Length of one measured step.
const int kPeakHopMs = 20;

/// Sample rate the decode gives ([kAlignRate]).
const int kPeakRate = 8000;

/// Levels are stored from this (and below) up to 0 dB.
const double kPeakMinDb = -96;

/// A level at or below this is digital silence.
const double kDigitalSilenceDb = -90;

typedef TimeRange = ({int startMs, int endMs});

/// Peak and level per [hopMs] of one sound.
class SoundPeaks {
  SoundPeaks(this.peaks, this.levels, {this.hopMs = kPeakHopMs})
      : assert(peaks.length == levels.length);

  /// Highest sample of each hop, 0..255 (square root of the amplitude,
  /// so that quiet speech is still visible).
  final Uint8List peaks;

  /// RMS level of each hop: 0 = [kPeakMinDb] or less, 255 = 0 dB.
  final Uint8List levels;
  final int hopMs;

  int get length => peaks.length;
  int get durationMs => length * hopMs;

  static double dbOf(int level) => kPeakMinDb + level * (-kPeakMinDb / 255);
  static int levelOf(double db) =>
      ((db - kPeakMinDb) * 255 / -kPeakMinDb).round().clamp(0, 255);

  /// Highest peak (0..1) between source times [fromMs] and [toMs].
  double peakBetween(int fromMs, int toMs) {
    var a = fromMs ~/ hopMs, b = (toMs + hopMs - 1) ~/ hopMs;
    if (a < 0) a = 0;
    if (b > length) b = length;
    if (b <= a) {
      if (a >= length || a < 0) return 0;
      b = a + 1;
    }
    var m = 0;
    for (var i = a; i < b; i++) {
      final v = peaks[i];
      if (v > m) m = v;
    }
    return m / 255;
  }

  /// From 16-bit little-endian mono samples at [rate].
  factory SoundPeaks.fromPcm16(Uint8List bytes,
          {int rate = kPeakRate, int hopMs = kPeakHopMs}) =>
      (PeaksBuilder(rate: rate, hopMs: hopMs)..add(bytes)).finish();

  /// From levels in dB per hop (tests): the peak follows the level.
  factory SoundPeaks.fromLevels(List<double> db, {int hopMs = kPeakHopMs}) {
    final p = Uint8List(db.length), l = Uint8List(db.length);
    for (var i = 0; i < db.length; i++) {
      l[i] = levelOf(db[i]);
      final amp = math.pow(10, db[i] / 20).toDouble() * 1.4;
      p[i] = (math.sqrt(amp.clamp(0.0, 1.0)) * 255).round();
    }
    return SoundPeaks(p, l, hopMs: hopMs);
  }

  static const List<int> _magic = [0x43, 0x46, 0x50, 0x4B, 1]; // "CFPK", v1

  Uint8List toBytes() {
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..add((ByteData(6)
            ..setUint16(0, hopMs, Endian.little)
            ..setUint32(2, length, Endian.little))
          .buffer
          .asUint8List())
      ..add(peaks)
      ..add(levels);
    return out.toBytes();
  }

  /// Null when [bytes] is not a complete peaks file.
  static SoundPeaks? fromBytes(Uint8List bytes) {
    if (bytes.length < 11) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return null;
    }
    final head = ByteData.sublistView(bytes, 5, 11);
    final hop = head.getUint16(0, Endian.little);
    final n = head.getUint32(2, Endian.little);
    if (hop <= 0 || bytes.length != 11 + 2 * n) return null;
    return SoundPeaks(Uint8List.sublistView(bytes, 11, 11 + n),
        Uint8List.sublistView(bytes, 11 + n, 11 + 2 * n),
        hopMs: hop);
  }

  static Future<SoundPeaks?> readFile(String path) async {
    try {
      return fromBytes(await File(path).readAsBytes());
    } on FileSystemException {
      return null;
    }
  }

  /// Reads a raw file written by `buildAlignDecodeCommand`, in chunks.
  static Future<SoundPeaks> fromRawFile(String path,
      {int rate = kPeakRate, int hopMs = kPeakHopMs}) async {
    final b = PeaksBuilder(rate: rate, hopMs: hopMs);
    await for (final chunk in File(path).openRead()) {
      b.add(chunk);
    }
    return b.finish();
  }
}

/// Builds [SoundPeaks] from 16-bit samples arriving in pieces.
class PeaksBuilder {
  PeaksBuilder({this.rate = kPeakRate, this.hopMs = kPeakHopMs})
      : _perHop = math.max(1, rate * hopMs ~/ 1000);
  final int rate;
  final int hopMs;
  final int _perHop;
  final BytesBuilder _peaks = BytesBuilder(copy: false);
  final BytesBuilder _levels = BytesBuilder(copy: false);
  Uint8List _p = Uint8List(4096), _l = Uint8List(4096);
  int _n = 0;
  int _max = 0;
  int _sum = 0; // sum of squares of 16-bit samples: fits in 63 bits
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
    final s = u >= 0x8000 ? u - 0x10000 : u;
    final a = s < 0 ? -s : s;
    if (a > _max) _max = a;
    _sum += s * s;
    if (++_count == _perHop) _flush();
  }

  void _flush() {
    final rms = math.sqrt(_sum / _count) / 32768.0;
    final db = rms <= 0 ? kPeakMinDb : 20 * math.log(rms) / math.ln10;
    _p[_n] = (math.sqrt(_max / 32768.0) * 255).round().clamp(0, 255);
    _l[_n] = SoundPeaks.levelOf(db);
    if (++_n == _p.length) {
      _peaks.add(_p);
      _levels.add(_l);
      _p = Uint8List(4096);
      _l = Uint8List(4096);
      _n = 0;
    }
    _max = 0;
    _sum = 0;
    _count = 0;
  }

  SoundPeaks finish() {
    if (_count >= _perHop ~/ 2) _flush();
    _peaks.add(Uint8List.sublistView(_p, 0, _n));
    _levels.add(Uint8List.sublistView(_l, 0, _n));
    return SoundPeaks(_peaks.toBytes(), _levels.toBytes(), hopMs: hopMs);
  }
}

/// What the levels of one sound say (see the top of this file).
class SpeechLevels {
  const SpeechLevels(this.floorDb, this.loudDb, this.thresholdDb, this.hasSpeech);
  final double floorDb;
  final double loudDb;
  final double thresholdDb;

  /// False for digital silence and for sound without quiet and loud parts
  /// that is quiet throughout.
  final bool hasSpeech;
}

SpeechLevels analyseSpeechLevels(SoundPeaks p) {
  final hist = List<int>.filled(256, 0);
  final silent = SoundPeaks.levelOf(kDigitalSilenceDb);
  var n = 0;
  for (final v in p.levels) {
    if (v <= silent) continue;
    hist[v]++;
    n++;
  }
  if (n < math.max(5, p.length ~/ 1000)) {
    return const SpeechLevels(kPeakMinDb, kPeakMinDb, 0, false);
  }
  double pct(double q) {
    final want = ((n - 1) * q).round();
    var seen = 0;
    for (var v = 0; v < 256; v++) {
      seen += hist[v];
      if (seen > want) return SoundPeaks.dbOf(v);
    }
    return 0;
  }

  final floor = pct(0.10), loud = pct(0.95);
  final span = loud - floor;
  if (span < 6) {
    // Nothing to tell apart: steady sound. Loud enough: all of it counts.
    return SpeechLevels(floor, loud, floor - 1, loud > -45);
  }
  final margin = (span * 0.35).clamp(4.0, 12.0);
  final threshold = (floor + margin).clamp(-70.0, -12.0).toDouble();
  return SpeechLevels(floor, loud, threshold, true);
}

/// Gaps shorter than this inside speech are bridged (pauses inside words
/// and between words), and speech shorter than [kMinSpeechMs] is dropped.
const int kSpeechBridgeMs = 300;
const int kMinSpeechMs = 160;

/// How much louder (relative to its own speech level) another microphone
/// must be for this one to count as bleed, and how close to its own
/// speech level this one must be to count as talking anyway.
const double kBleedMarginDb = 8;
const double kOwnSpeechDb = 6;

/// Another microphone this much louder in plain numbers makes this one
/// bleed in any case (bleed is 15 to 30 dB down; recordings made together
/// rarely differ that much in level).
const double kBleedFarDb = 15;

Uint8List _mask(SoundPeaks p, SpeechLevels s) {
  final m = Uint8List(p.length);
  if (!s.hasSpeech) return m;
  final t = SoundPeaks.levelOf(s.thresholdDb);
  for (var i = 0; i < m.length; i++) {
    if (p.levels[i] >= t) m[i] = 1;
  }
  return m;
}

List<TimeRange> _stretches(Uint8List mask, int hopMs,
    {int bridgeMs = kSpeechBridgeMs, int minMs = kMinSpeechMs}) {
  final runs = <List<int>>[];
  var i = 0;
  final n = mask.length;
  while (i < n) {
    if (mask[i] == 0) {
      i++;
      continue;
    }
    var j = i;
    while (j < n && mask[j] != 0) {
      j++;
    }
    if (runs.isNotEmpty && (i - runs.last[1]) * hopMs < bridgeMs) {
      runs.last[1] = j;
    } else {
      runs.add([i, j]);
    }
    i = j;
  }
  return [
    for (final r in runs)
      if ((r[1] - r[0]) * hopMs >= minMs)
        (startMs: r[0] * hopMs, endMs: r[1] * hopMs),
  ];
}

/// The stretches of [p] where someone talks (times in the sound's own
/// file), by its own levels alone.
List<TimeRange> speechStretches(SoundPeaks p) =>
    _stretches(_mask(p, analyseSpeechLevels(p)), p.hopMs);

/// Level smoothed over +-[r] hops (highest), relative to [loudDb], in
/// level steps.
Int16List _relative(SoundPeaks p, double loudDb, int r) {
  final n = p.length;
  final out = Int16List(n);
  final loud = SoundPeaks.levelOf(loudDb);
  for (var i = 0; i < n; i++) {
    var m = 0;
    final a = i - r < 0 ? 0 : i - r, b = i + r >= n ? n - 1 : i + r;
    for (var k = a; k <= b; k++) {
      if (p.levels[k] > m) m = p.levels[k];
    }
    out[i] = m - loud;
  }
  return out;
}

/// Who talks when, for microphones recorded together. [offsetMs] of each:
/// time in its file = common time + offset (a linked voice's
/// `syncOffsetMs`). Result: per microphone, the stretches in its OWN
/// file's time, bleed from the others taken out.
List<List<TimeRange>> groupSpeechStretches(
    List<({SoundPeaks peaks, int offsetMs})> mics) {
  if (mics.length < 2) {
    return [for (final m in mics) speechStretches(m.peaks)];
  }
  final levels = [for (final m in mics) analyseSpeechLevels(m.peaks)];
  final masks = [
    for (var k = 0; k < mics.length; k++) _mask(mics[k].peaks, levels[k]),
  ];
  final rel = [
    for (var k = 0; k < mics.length; k++)
      _relative(mics[k].peaks, levels[k].loudDb, 2),
  ];
  final step = 255 / -kPeakMinDb; // level steps per dB
  final margin = (kBleedMarginDb * step).round();
  final own = -(kOwnSpeechDb * step).round();
  final far = (kBleedFarDb * step).round();
  final out = <List<TimeRange>>[];
  for (var a = 0; a < mics.length; a++) {
    final pa = mics[a].peaks;
    final mask = Uint8List.fromList(masks[a]);
    final loudA = SoundPeaks.levelOf(levels[a].loudDb);
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0) continue;
      // This microphone's own level, exactly here; the others' a little
      // smoothed (a dip inside their word is still their word).
      final ra = pa.levels[i] - loudA;
      final common = i * pa.hopMs - mics[a].offsetMs;
      for (var b = 0; b < mics.length; b++) {
        if (b == a) continue;
        final pb = mics[b].peaks;
        final j = (common + mics[b].offsetMs) ~/ pb.hopMs;
        if (j < 0 || j >= pb.length || masks[b][j] == 0) continue;
        final loudB = SoundPeaks.levelOf(levels[b].loudDb);
        // Far louder in plain numbers: bleed, whatever this microphone's
        // usual level is (someone who hardly ever talks has no usual
        // level of their own).
        if (rel[b][j] + loudB - pa.levels[i] >= far) {
          mask[i] = 0;
          break;
        }
        // Clearly louder by each one's own measure, and this one not
        // loud by its own: bleed.
        if (ra < own && rel[b][j] - ra >= margin) {
          mask[i] = 0;
          break;
        }
      }
    }
    out.add(_stretches(mask, pa.hopMs));
  }
  return out;
}
