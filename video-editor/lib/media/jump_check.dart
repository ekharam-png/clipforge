// The jump check for automatic cuts: how much does the picture change
// between the frame just before a cut and the frame just after it? A
// person who moved in the meantime makes a visible jump; a still speaker
// does not. dart:io only.
//
// For each cut, ffmpeg grabs the two frames at 32x18 grey (fast seek, a
// handful of cuts per run) and the score is their mean absolute
// difference, 0..1 with 1 = 25 grey levels or more (of 255):
//   under 0.2  smooth - nobody will notice
//   0.2..0.5   slight - gets a short dissolve
//   0.5 up     jumpy  - Light and Normal leave such a filler in
// (thresholds in core/transcript/cut_plan.dart). Measured with synthetic
// video only: a box that stays put scores ~0, one that moves a fifth of
// the frame scores 1. Real faces and hand movements were not measured.

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'media_common.dart';

/// An engine that can score cuts.
abstract interface class JumpCheckEngine {
  /// The jump score (0..1) of each of [cuts] in the video file [path]: the
  /// picture at [beforeMs] against the picture at [afterMs] (source
  /// times). Null where a frame could not be read.
  Future<List<double?>> jumpScores(
      String path, List<({int beforeMs, int afterMs})> cuts);
}

const int _w = 32, _h = 18;

/// Cuts looked at per ffmpeg run (two inputs each).
const int kJumpBatch = 8;

/// The grey-level difference that counts as a full jump.
const double kJumpFullDifference = 25;

/// The score of two frames of [_w] x [_h] grey bytes.
double jumpScoreOf(Uint8List before, Uint8List after) {
  final n = before.length < after.length ? before.length : after.length;
  if (n == 0) return 0;
  var sum = 0;
  for (var i = 0; i < n; i++) {
    final d = before[i] - after[i];
    sum += d < 0 ? -d : d;
  }
  final score = sum / n / kJumpFullDifference;
  return score > 1 ? 1 : score;
}

String _t(int ms) => (ms < 0 ? 0 : ms / 1000).toStringAsFixed(3);

/// [JumpCheckEngine.jumpScores] on top of [run].
Future<List<double?>> jumpScoresWith(FfmpegRunner run, String path,
    List<({int beforeMs, int afterMs})> cuts) async {
  final out = List<double?>.filled(cuts.length, null);
  if (cuts.isEmpty) return out;
  final dir = await Directory.systemTemp.createTemp('clipforge_jump_');
  try {
    for (var from = 0; from < cuts.length; from += kJumpBatch) {
      final batch = cuts.skip(from).take(kJumpBatch).toList();
      final args = <String>['-nostats', '-loglevel', 'error', '-y'];
      final graph = <String>[];
      final maps = <String>[];
      for (var i = 0; i < batch.length; i++) {
        for (final (k, ms) in [(0, batch[i].beforeMs), (1, batch[i].afterMs)]) {
          final n = i * 2 + k;
          args.addAll(['-ss', _t(ms), '-i', path]);
          graph.add('[$n:v:0]scale=$_w:$_h:flags=area,format=gray[o$n]');
          maps.addAll([
            '-map', '[o$n]', '-frames:v', '1', '-f', 'rawvideo', //
            p.join(dir.path, '${from + i}_$k.raw'),
          ]);
        }
      }
      await run([...args, '-filter_complex', graph.join(';'), ...maps]);
      for (var i = 0; i < batch.length; i++) {
        final a = File(p.join(dir.path, '${from + i}_0.raw'));
        final b = File(p.join(dir.path, '${from + i}_1.raw'));
        if (!await a.exists() || !await b.exists()) continue;
        final fa = await a.readAsBytes(), fb = await b.readAsBytes();
        if (fa.length < _w * _h || fb.length < _w * _h) continue;
        out[from + i] = jumpScoreOf(fa, fb);
      }
    }
  } finally {
    await deleteQuietly(dir);
  }
  return out;
}
